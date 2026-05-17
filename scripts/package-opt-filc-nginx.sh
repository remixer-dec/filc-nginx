#!/bin/bash
set -euo pipefail

# Fil-C nginx packaging script
# Bundles the binary + all Fil-C runtime dependencies into a portable archive.
# Interpreter (INTERP) is patched to an absolute path at packaging time.
# The binary must be extracted to exactly that path to run.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FILC_LIB_DIR="/opt/fil/lib"
if [ -n "${BUILD_DIR:-}" ]; then
    BUILD_DIR="$BUILD_DIR"
elif [ -f "$ROOT_DIR/objs/nginx" ]; then
    BUILD_DIR="$ROOT_DIR/objs"
else
    BUILD_DIR="$ROOT_DIR/objs-filc"
fi
STAGING="$ROOT_DIR/filc-nginx-bundle"
OUTPUT="$ROOT_DIR/filc-nginx.tar.gz"

# Default target path — override with --target=/path
TARGET_DIR="${TARGET_DIR:-/usr/local/filc-nginx}"

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --target=*) TARGET_DIR="${1#*=}" ;;
        --target)   TARGET_DIR="$2"; shift ;;
        --help)
            echo "Usage: $0 [--target=/path/to/install]"
            echo "  --target  Deployment path (default: /usr/local/filc-nginx)"
            exit 0
            ;;
        *) echo "Unknown arg: $1"; exit 1 ;;
    esac
done

BINARY="$BUILD_DIR/nginx"

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

# Clean previous staging but preserve Dockerfile and docker-compose.yml
rm -rf "$OUTPUT"
if [ -d "$STAGING" ]; then
    cp -a "$STAGING/Dockerfile" "$ROOT_DIR/Dockerfile.tmp" 2>/dev/null || true
    cp -a "$STAGING/docker-compose.yml" "$ROOT_DIR/docker-compose.yml.tmp" 2>/dev/null || true
    rm -rf "$STAGING"
fi
mkdir -p "$STAGING/lib"
if [ -f "$ROOT_DIR/Dockerfile.tmp" ]; then
    mv "$ROOT_DIR/Dockerfile.tmp" "$STAGING/Dockerfile"
fi
if [ -f "$ROOT_DIR/docker-compose.yml.tmp" ]; then
    mv "$ROOT_DIR/docker-compose.yml.tmp" "$STAGING/docker-compose.yml"
fi

echo "=== Packaging Fil-C nginx ==="
echo "Target path: $TARGET_DIR"

# --- Copy binary and patch ---
cp "$BINARY" "$STAGING/nginx"
patchelf --set-rpath '$ORIGIN/lib' "$STAGING/nginx"
patchelf --set-interpreter "$TARGET_DIR/lib/ld-yolo-x86_64.so" "$STAGING/nginx"
echo "  patched RUNPATH    -> \$ORIGIN/lib"
echo "  patched INTERPRETER -> $TARGET_DIR/lib/ld-yolo-x86_64.so"

# --- Copy required libraries ---
copy_lib() {
    local name="$1"
    local src="$FILC_LIB_DIR/$name"
    if [ -f "$src" ]; then
        cp "$src" "$STAGING/lib/$name"
        echo "  + $name"
    elif [ -L "$src" ]; then
        local target
        target=$(readlink -f "$src")
        local target_name
        target_name=$(basename "$target")
        if [ ! -f "$STAGING/lib/$target_name" ]; then
            cp "$target" "$STAGING/lib/$target_name"
            echo "  + $target_name"
        fi
        ln -s "$target_name" "$STAGING/lib/$name"
        echo "  + $name -> $target_name"
    else
        echo "  WARNING: $name not found in $FILC_LIB_DIR"
    fi
}

echo ""
echo "Copying Fil-C runtime libraries:"

# Core Fil-C runtime
copy_lib "ld-yolo-x86_64.so"
copy_lib "libc.so.6666"
copy_lib "libpizlo.so"
copy_lib "libyolocimpl.so"
copy_lib "libyolomimpl.so"
copy_lib "libcrypt.so.2"

# OpenSSL (Fil-C built) — patch COPIES, never originals
copy_lib "libssl.so"
copy_lib "libssl.so.3"
copy_lib "libcrypto.so"
copy_lib "libcrypto.so.3"
patchelf --set-rpath '$ORIGIN' "$STAGING/lib/libssl.so.3"
patchelf --set-rpath '$ORIGIN' "$STAGING/lib/libcrypto.so.3"
echo "  patched copies: libssl.so.3, libcrypto.so.3 (RPATH -> \$ORIGIN)"

# zlib
copy_lib "libz.so"
copy_lib "libz.so.1"
copy_lib "libz.so.1.3.1"

# PCRE2
copy_lib "libpcre2-8.so"
copy_lib "libpcre2-8.so.0"
copy_lib "libpcre2-8.so.0.13.0"

# zstd (transitive OpenSSL dep)
copy_lib "libzstd.so"
copy_lib "libzstd.so.1"
copy_lib "libzstd.so.1.5.6"

# --- Create archive ---
echo ""
echo "Creating archive..."
tar -czf "$OUTPUT" -C "$STAGING" .

# --- Verify ---
echo ""
echo "=== Verification ==="
total_size=$(du -sh "$OUTPUT" | cut -f1)
lib_count=$(ls "$STAGING/lib" | wc -l)
echo "Archive:    $OUTPUT ($total_size)"
echo "Libraries:  $lib_count"
echo "Binary:     $(ls -lh "$STAGING/nginx" | awk '{print $5}')"

echo ""
echo "Binary metadata:"
readelf -d "$STAGING/nginx" 2>/dev/null | grep -E 'RUNPATH|NEEDED' || true
readelf -l "$STAGING/nginx" 2>/dev/null | grep Requesting || true

echo ""
echo "=== Done ==="
echo ""
echo "Deploy (must extract to EXACT path):"
echo "  mkdir -p $TARGET_DIR"
echo "  tar xzf $OUTPUT -C $TARGET_DIR"
echo "  $TARGET_DIR/nginx -V"
