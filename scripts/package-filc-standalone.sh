#!/bin/bash
set -euo pipefail

# Package Fil-C nginx built from standalone pizfix tarball.
# Bundles objs-filc/nginx + Fil-C runtime libs from pizfix/lib into a portable archive.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STAGING="$ROOT_DIR/filc-nginx-bundle"
OUTPUT="$ROOT_DIR/filc-nginx.tar.gz"

TARGET_DIR="${TARGET_DIR:-/usr/local/filc-nginx}"
PIZFIX_LIB="${PIZFIX_LIB:-}"

BINARY="${BINARY:-$ROOT_DIR/objs-filc/nginx}"

if [ ! -f "$BINARY" ]; then
    echo "ERROR: Binary not found at $BINARY"
    exit 1
fi

# Find pizfix/lib if not set
if [ -z "$PIZFIX_LIB" ]; then
    for d in /tmp/filc-*/pizfix/lib "$ROOT_DIR/../filc-*/pizfix/lib"; do
        if [ -d "$d" ]; then
            PIZFIX_LIB="$d"
            break
        fi
    done
fi

if [ -z "$PIZFIX_LIB" ] || [ ! -d "$PIZFIX_LIB" ]; then
    echo "ERROR: PIZFIX_LIB not found. Set PIZFIX_LIB=/path/to/filc-*/pizfix/lib"
    exit 1
fi

# Clean staging
rm -rf "$STAGING"
mkdir -p "$STAGING/lib"

echo "=== Packaging Fil-C nginx ==="
echo "Binary:    $BINARY"
echo "Target:    $TARGET_DIR"
echo "Fil-C lib: $PIZFIX_LIB"

# Copy and patch binary
cp "$BINARY" "$STAGING/nginx"
patchelf --set-rpath '$ORIGIN/lib' "$STAGING/nginx"
patchelf --set-interpreter "$TARGET_DIR/lib/ld-yolo-x86_64.so" "$STAGING/nginx"
echo "  patched RUNPATH -> \$ORIGIN/lib"
echo "  patched INTERPRETER -> $TARGET_DIR/lib/ld-yolo-x86_64.so"

# Copy required libs from pizfix/lib
copy_lib() {
    local name="$1"
    local src="$PIZFIX_LIB/$name"
    if [ -f "$src" ]; then
        cp "$src" "$STAGING/lib/$name"
        echo "  + $name"
    elif [ -L "$src" ]; then
        local target
        target=$(readlink -f "$src" 2>/dev/null || true)
        if [ -n "$target" ] && [ -f "$target" ]; then
            local target_name
            target_name=$(basename "$target")
            if [ ! -f "$STAGING/lib/$target_name" ]; then
                cp "$target" "$STAGING/lib/$target_name"
                echo "  + $target_name"
            fi
            ln -s "$target_name" "$STAGING/lib/$name"
            echo "  + $name -> $target_name"
        else
            echo "  WARNING: $name symlink target not found"
        fi
    else
        echo "  WARNING: $name not found in $PIZFIX_LIB"
    fi
}

echo ""
echo "Copying Fil-C runtime libraries:"
copy_lib "ld-yolo-x86_64.so"
copy_lib "libc.so"
copy_lib "libc.so.6666"
copy_lib "libpizlo.so"
copy_lib "libyolocimpl.so"
copy_lib "libyolomimpl.so"
copy_lib "libyolort.so"
copy_lib "libyolounwind.so"
copy_lib "libc++.so.1.0"
copy_lib "libc++abi.so.1.0"
copy_lib "libcrypt.so.2"

echo ""
echo "Copying OpenSSL libraries:"
copy_lib "libssl.so"
copy_lib "libssl.so.3"
copy_lib "libcrypto.so"
copy_lib "libcrypto.so.3"
for f in "$STAGING/lib"/libssl.so.3 "$STAGING/lib"/libcrypto.so.3; do
    [ -f "$f" ] && patchelf --set-rpath '$ORIGIN' "$f"
done
echo "  patched: libssl.so.3, libcrypto.so.3 (RPATH -> \$ORIGIN)"

echo ""
echo "Copying zlib:"
copy_lib "libz.so"
copy_lib "libz.so.1"
copy_lib "libz.so.1.3"
copy_lib "libz.so.1.3.1"

echo ""
echo "Copying PCRE2:"
copy_lib "libpcre2-8.so"
copy_lib "libpcre2-8.so.0"
copy_lib "libpcre2-8.so.0.13.0"

echo ""
echo "Creating archive..."
tar -czf "$OUTPUT" -C "$STAGING" .

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
echo "Deploy:"
echo "  mkdir -p $TARGET_DIR"
echo "  tar xzf $OUTPUT -C $TARGET_DIR"
echo "  $TARGET_DIR/nginx -V"
