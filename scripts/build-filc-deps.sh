#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FILC_ROOT="${FILC_ROOT:-/opt/fil}"
DEPS_DIR="${DEPS_DIR:-$ROOT_DIR/.filc-deps}"
PREFIX_DIR="${PREFIX_DIR:-$DEPS_DIR/prefix}"
OPTFIL_URL="${OPTFIL_URL:-https://github.com/pizlonator/fil-c/releases/download/v0.678/optfil-0.678-linux-x86_64.tar.xz}"

mkdir -p "$PREFIX_DIR/lib" "$PREFIX_DIR/include"

require_tool() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing tool: $1" >&2; exit 1; }
}

require_tool curl
require_tool bash
require_tool tar

ensure_optfil() {
  local archive="$DEPS_DIR/optfil.tar.xz"
  local extract_dir="$DEPS_DIR/optfil"

  if [ -x "$FILC_ROOT/bin/filcc" ] || [ -x /opt/fil/bin/filcc ]; then
    echo "Using preinstalled Fil-C tools from ${FILC_ROOT}"
    return
  fi

  mkdir -p "$extract_dir"
  curl -fsSL "$OPTFIL_URL" -o "$archive"
  tar -xf "$archive" -C "$extract_dir"

  local setup_sh
  setup_sh="$(find "$extract_dir" -maxdepth 3 -type f -name setup.sh | head -n 1)"
  if [ -z "$setup_sh" ]; then
    echo "Unable to locate setup.sh in extracted optfil archive" >&2
    exit 1
  fi

  local optfil_root
  optfil_root="$(cd "$(dirname "$setup_sh")" && pwd)"
  echo "Installing optfil from $optfil_root"
  (cd "$optfil_root" && bash ./setup.sh --unattended)
}

link_if_exists() {
  local src="$1"
  local dst="$2"
  if [ -e "$src" ]; then
    ln -sfn "$src" "$dst"
  fi
}

prepare_prefix_from_optfil() {
  local root="${FILC_ROOT}"
  if [ ! -d "$root/lib" ]; then
    root="/opt/fil"
  fi

  if [ ! -d "$root/lib" ] || [ ! -d "$root/include" ]; then
    echo "ERROR: Fil-C root missing lib/include dirs (checked $FILC_ROOT and /opt/fil)" >&2
    exit 1
  fi

  echo "Reusing prebuilt optfil libraries from $root"

  # Headers
  link_if_exists "$root/include/openssl" "$PREFIX_DIR/include/openssl"
  link_if_exists "$root/include/pcre2.h" "$PREFIX_DIR/include/pcre2.h"
  link_if_exists "$root/include/zlib.h" "$PREFIX_DIR/include/zlib.h"
  link_if_exists "$root/include/zconf.h" "$PREFIX_DIR/include/zconf.h"

  # OpenSSL
  link_if_exists "$root/lib/libssl.so" "$PREFIX_DIR/lib/libssl.so"
  link_if_exists "$root/lib/libssl.so.3" "$PREFIX_DIR/lib/libssl.so.3"
  link_if_exists "$root/lib/libcrypto.so" "$PREFIX_DIR/lib/libcrypto.so"
  link_if_exists "$root/lib/libcrypto.so.3" "$PREFIX_DIR/lib/libcrypto.so.3"

  # PCRE2
  link_if_exists "$root/lib/libpcre2-8.so" "$PREFIX_DIR/lib/libpcre2-8.so"
  link_if_exists "$root/lib/libpcre2-8.so.0" "$PREFIX_DIR/lib/libpcre2-8.so.0"

  # zlib
  link_if_exists "$root/lib/libz.so" "$PREFIX_DIR/lib/libz.so"
  link_if_exists "$root/lib/libz.so.1" "$PREFIX_DIR/lib/libz.so.1"

  # Additional common transitive deps used by optfil OpenSSL
  link_if_exists "$root/lib/libzstd.so" "$PREFIX_DIR/lib/libzstd.so"
  link_if_exists "$root/lib/libzstd.so.1" "$PREFIX_DIR/lib/libzstd.so.1"

  echo "Prepared dependency prefix in: $PREFIX_DIR"
}

ensure_optfil
prepare_prefix_from_optfil
