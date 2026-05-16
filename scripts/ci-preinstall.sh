#!/usr/bin/env bash
#
# ci-preinstall.sh - Install all system dependencies required to build filc-nginx
# from scratch on a blank Debian 12 (bookworm) environment.
#
# This script installs the minimal set of packages needed to:
#   1. Download and extract the Fil-C pizfix tarball
#   2. Run the Fil-C setup.sh script
#   3. Build dependencies (zlib, PCRE2, OpenSSL) with filcc
#   4. Configure and build nginx with filcc
#
# Usage: bash ci-preinstall.sh
#

set -euo pipefail

echo "=== ci-preinstall.sh: Installing system dependencies ==="

# Update package lists
apt-get update -qq

# Install minimal required packages
# - curl: download tarballs and scripts
# - ca-certificates: HTTPS verification
# - xz-utils: extract .tar.xz Fil-C tarball
# - patchelf: required by Fil-C setup.sh to fix RPATH
# - binutils: provides ld linker (Fil-C links against system ld)
# - make: build system for all dependencies and nginx
# - libc6-dev: kernel headers (/usr/include/linux/*.h) needed by Fil-C
# - perl: OpenSSL ./Configure script requires Perl
apt-get install -y --no-install-recommends \
    curl \
    ca-certificates \
    xz-utils \
    patchelf \
    binutils \
    make \
    libc6-dev \
    perl

echo "=== All system dependencies installed ==="
