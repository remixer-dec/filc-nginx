#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEPS_DIR="${DEPS_DIR:-$ROOT_DIR/.filc-deps}"
PREFIX_DIR="${PREFIX_DIR:-$DEPS_DIR/prefix}"
INSTALL_DIR="${INSTALL_DIR:-$ROOT_DIR/.filc-nginx-install}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/objs-filc}"

COMMON_CC_OPT="-O2 -fno-omit-frame-pointer -I$PREFIX_DIR/include"
COMMON_LD_OPT="-L$PREFIX_DIR/lib -Wl,-rpath,$PREFIX_DIR/lib"

cd "$ROOT_DIR"

./auto/configure \
  --builddir="$BUILD_DIR" \
  --prefix="$INSTALL_DIR" \
  --with-filc-mode \
  --with-cc="${CC:-cc}" \
  --with-cc-opt="$COMMON_CC_OPT" \
  --with-ld-opt="$COMMON_LD_OPT" \
  --without-http_ssi_module \
  --without-http_userid_module \
  --without-http_autoindex_module \
  --without-http_geo_module \
  --without-http_split_clients_module \
  --without-http_uwsgi_module \
  --without-http_scgi_module \
  --without-http_grpc_module \
  --without-http_memcached_module \
  --without-http_empty_gif_module \
  --without-http_browser_module \
  --without-http_upstream_hash_module \
  --without-http_upstream_ip_hash_module \
  --without-http_upstream_least_conn_module \
  --without-http_upstream_random_module \
  --without-http_upstream_keepalive_module \
  --without-http_upstream_zone_module \
  --without-mail_pop3_module \
  --without-mail_imap_module \
  --without-mail_smtp_module \
  --without-stream

