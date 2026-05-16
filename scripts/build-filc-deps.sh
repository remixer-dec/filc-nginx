#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILC_ROOT="${FILC_ROOT:-/opt/filc}"
DEPS_DIR="${DEPS_DIR:-$ROOT_DIR/.filc-deps}"
SRC_DIR="$DEPS_DIR/src"
PREFIX_DIR="${PREFIX_DIR:-$DEPS_DIR/prefix}"

mkdir -p "$SRC_DIR" "$PREFIX_DIR"

require_tool() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing tool: $1" >&2; exit 1; }
}

require_tool curl
require_tool bash

fetch_script() {
  local name="$1"
  local url="$2"
  local out="$SRC_DIR/$name"
  curl -fsSL "$url" -o "$out"
  chmod +x "$out"
}

# Build scripts from fil-c deluge branch.
fetch_script build_pcre.sh https://raw.githubusercontent.com/pizlonator/fil-c/refs/heads/deluge/build_pcre.sh
fetch_script build_pcre2.sh https://raw.githubusercontent.com/pizlonator/fil-c/refs/heads/deluge/build_pcre2.sh
fetch_script build_zlib.sh https://raw.githubusercontent.com/pizlonator/fil-c/refs/heads/deluge/build_zlib.sh
fetch_script build_openssl.sh https://raw.githubusercontent.com/pizlonator/fil-c/refs/heads/deluge/build_openssl.sh
fetch_script build_nghttp2.sh https://raw.githubusercontent.com/pizlonator/fil-c/refs/heads/deluge/build_nghttp2.sh

export PATH="$FILC_ROOT/bin:$PATH"
export CC="${CC:-filc}"
export CXX="${CXX:-filc++}"
export PREFIX="$PREFIX_DIR"

pushd "$SRC_DIR" >/dev/null

bash ./build_pcre2.sh || bash ./build_pcre.sh
bash ./build_zlib.sh
bash ./build_openssl.sh

echo "Built dependencies in: $PREFIX_DIR"
popd >/dev/null
