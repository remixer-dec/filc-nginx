#!/usr/bin/env bash
set -euo pipefail

# Build nginx with Fil-C compiler from scratch on blank Debian 12.
# Uses standalone pizfix tarball (filc-0.678-linux-x86_64.tar.xz).
# Last validated: 2026-05-16 on Debian 12 container.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK_DIR="${WORK_DIR:-/tmp}"
FILC_VERSION="0.678"
PREFIX="${WORK_DIR}/filc-deps"
PIZFIX_DIR="${WORK_DIR}/filc-${FILC_VERSION}-linux-x86_64"
NGINX_DIR="${NGINX_DIR:-$SCRIPT_DIR}"

export PATH="$PIZFIX_DIR/build/bin:$PATH"
export PIZFIX_LIB="$PIZFIX_DIR/pizfix/lib"

log() { echo "[$(date +%H:%M:%S)] $*"; }

install_system_deps() {
    log "Installing system packages..."
    apt-get update -qq
    apt-get install -y -qq curl ca-certificates xz-utils patchelf binutils make libc6-dev perl >/dev/null 2>&1
    log "System packages installed."
}

install_filc() {
    if [ -x "$PIZFIX_DIR/build/bin/filcc" ]; then
        log "Fil-C already installed at $PIZFIX_DIR"
        return
    fi

    log "Downloading Fil-C ${FILC_VERSION}..."
    curl -fsSL "https://github.com/pizlonator/fil-c/releases/download/v${FILC_VERSION}/filc-${FILC_VERSION}-linux-x86_64.tar.xz" \
        -o "${WORK_DIR}/filc.tar.xz"
    tar xf "${WORK_DIR}/filc.tar.xz" -C "$WORK_DIR"
    cd "$PIZFIX_DIR"
    bash setup.sh || true  # Obstacle 1: mkdir os-include exit 1 is non-fatal
    cd -
    filcc --version
    log "Fil-C installed."
}

build_zlib() {
    if [ -f "$PREFIX/lib/libz.a" ]; then
        log "zlib already built"
        return
    fi

    log "Building zlib 1.3..."
    cd "$WORK_DIR"
    curl -fsSL https://zlib.net/fossils/zlib-1.3.tar.gz -o zlib-1.3.tar.gz
    tar xzf zlib-1.3.tar.gz
    cd zlib-1.3
    CC=filcc ./configure --prefix="$PREFIX"
    make -j"$(nproc)" CC=filcc
    make install
    # CRITICAL: copy to pizfix/lib for mangled symbol resolution
    cp "$PREFIX/lib/libz.a" "$PREFIX/lib/libz.so.1.3" "$PIZFIX_LIB/"
    ln -sf libz.so.1.3 "$PIZFIX_LIB/libz.so"
    ln -sf libz.so.1.3 "$PIZFIX_LIB/libz.so.1"
    cd -
    log "zlib built."
}

build_pcre2() {
    if [ -f "$PREFIX/lib/libpcre2-8.a" ]; then
        log "PCRE2 already built"
        return
    fi

    log "Building PCRE2 10.44..."
    cd "$WORK_DIR"
    curl -fsSL https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.44/pcre2-10.44.tar.gz -o pcre2.tar.gz
    tar xzf pcre2.tar.gz
    cd pcre2-10.44
    CC=filcc ./configure --prefix="$PREFIX" --enable-pcre2-16 --enable-pcre2-32
    make -j"$(nproc)" CC=filcc
    make install
    cd -
    log "PCRE2 built."
}

build_openssl() {
    if [ -f "$PREFIX/lib/libssl.a" ] && [ -f "$PREFIX/lib/libcrypto.a" ]; then
        log "OpenSSL already built"
        return
    fi

    log "Building OpenSSL 3.3.1..."
    cd "$WORK_DIR"
    curl -fsSL https://www.openssl.org/source/openssl-3.3.1.tar.gz -o openssl-3.3.1.tar.gz
    tar xzf openssl-3.3.1.tar.gz
    cd openssl-3.3.1

    # Use raw clang with pizfix/lib for zlib, no-asm for Fil-C compatibility
    CC="clang -I$PREFIX/include -g -O2" \
    LDFLAGS="-L$PIZFIX_LIB" \
    ./Configure --prefix="$PREFIX" --openssldir="$PREFIX/ssl" zlib no-asm linux-x86_64

    # Build libraries only (skip tests/engines - Obstacle 4)
    make build_libs -j"$(nproc)"

    # Manually install to prefix
    mkdir -p "$PREFIX/lib"
    cp libcrypto.a libcrypto.so libcrypto.so.3 "$PREFIX/lib/"
    cp libssl.a libssl.so libssl.so.3 "$PREFIX/lib/"
    mkdir -p "$PREFIX/include/openssl"
    cp -r include/openssl/* "$PREFIX/include/openssl/" 2>/dev/null || true

    # Install shared libs to pizfix for runtime resolution
    cp libcrypto.so libcrypto.so.3 "$PIZFIX_LIB/"
    cp libssl.so libssl.so.3 "$PIZFIX_LIB/"

    # Install headers to pizfix/include for filcc to find natively
    mkdir -p "$PIZFIX_DIR/pizfix/include/openssl"
    cp -r include/openssl/* "$PIZFIX_DIR/pizfix/include/openssl/" 2>/dev/null || true

    cd -
    log "OpenSSL built."
}

setup_openssl_for_nginx() {
    # Create .openssl structure that nginx expects (Obstacle 5+7)
    mkdir -p "$PREFIX/.openssl/lib" "$PREFIX/.openssl/include/openssl"
    cp "$PREFIX/lib/libssl.a" "$PREFIX/lib/libcrypto.a" "$PREFIX/.openssl/lib/"
    cp -r "$PREFIX/include/openssl/"* "$PREFIX/.openssl/include/openssl/"
    log "OpenSSL .openssl/ structure ready for nginx."
}

build_nginx() {
    if [ -f "$NGINX_DIR/objs-filc/nginx" ]; then
        log "nginx already built"
        return
    fi

    log "Configuring nginx..."
    cd "$NGINX_DIR"
    rm -rf objs-filc

    COMMON_CC_OPT="-DNGX_FILC_MODE -g -O2 -Werror=implicit-function-declaration -ffile-prefix-map=$NGINX_DIR=. -fstack-protector-strong -fstack-clash-protection -Wformat -Werror=format-security -Wno-error=sign-compare -fcf-protection -fPIC -I$PREFIX/include"
    COMMON_LD_OPT="-Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie -L$PREFIX/lib -Wl,-rpath,$PREFIX/lib"

    ./auto/configure \
        --builddir=objs-filc \
        --prefix=.filc-nginx-install \
        --with-filc-mode \
        --with-cc=filcc \
        --with-cc-opt="$COMMON_CC_OPT" \
        --with-ld-opt="$COMMON_LD_OPT" \
        --with-http_ssl_module \
        --with-http_v2_module \
        --with-openssl="$PREFIX" \
        --with-compat \
        --with-threads \
        --with-http_addition_module \
        --with-http_auth_request_module \
        --with-http_gunzip_module \
        --with-http_gzip_static_module \
        --with-http_random_index_module \
        --with-http_realip_module \
        --with-http_secure_link_module \
        --with-http_slice_module \
        --with-http_stub_status_module \
        --with-http_sub_module \
        --with-stream \
        --with-stream_realip_module \
        --with-stream_ssl_module \
        --with-stream_ssl_preread_module

    sleep 1
    touch "$PREFIX/.openssl/include/openssl/ssl.h"

    log "Building nginx..."
    make -f objs-filc/Makefile -j"$(nproc)"

    log "nginx binary: $(ls -lh objs-filc/nginx | awk '{print $5}')"
    ./objs-filc/nginx -V 2>&1 | head -3
}

main() {
    log "=== Fil-C Nginx Build from Scratch ==="
    log "WORK_DIR=$WORK_DIR PREFIX=$PREFIX NGINX_DIR=$NGINX_DIR"

    install_system_deps
    install_filc
    build_zlib
    build_pcre2
    build_openssl
    setup_openssl_for_nginx
    build_nginx

    log "=== Build complete ==="
    log "Binary: $NGINX_DIR/objs-filc/nginx"
}

main "$@"
