
#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPS_DIR="${DEPS_DIR:-$ROOT_DIR/.filc-deps}"
PREFIX_DIR="${PREFIX_DIR:-$DEPS_DIR/prefix}"
INSTALL_DIR="${INSTALL_DIR:-$ROOT_DIR/.filc-nginx-install}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/objs}"

COMMON_CC_OPT="-DNGX_FILC_MODE -g -O2 -Werror=implicit-function-declaration -ffile-prefix-map=$ROOT_DIR=. -fstack-protector-strong -fstack-clash-protection -Wformat -Werror=format-security -fcf-protection -Wp,-D_FORTIFY_SOURCE=2 -fPIC -I$PREFIX_DIR/include"
COMMON_LD_OPT="-Wl,-z,relro -Wl,-z,now -Wl,--as-needed -pie -L$PREFIX_DIR/lib -Wl,-rpath,$PREFIX_DIR/lib"

cd "$ROOT_DIR"

./auto/configure \
  --builddir="$BUILD_DIR" \
  --prefix="$INSTALL_DIR" \
  --with-filc-mode \
  --with-cc="${CC:-cc}" \
  --with-cc-opt="$COMMON_CC_OPT" \
  --with-ld-opt="$COMMON_LD_OPT" \
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
  --with-http_ssl_module \
  --with-http_stub_status_module \
  --with-http_sub_module \
  --with-http_v2_module \
  --with-stream \
  --with-stream_realip_module \
  --with-stream_ssl_module \
  --with-stream_ssl_preread_module
