
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
  --with-ld-opt="$COMMON_LD_OPT" 
