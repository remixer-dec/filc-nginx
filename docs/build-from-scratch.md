# Building Fil-C Nginx from Scratch

## Overview

This document describes how to build nginx with the Fil-C compiler on a blank Debian 12 (bookworm) environment. The standalone pizfix tarball (`filc-0.678-linux-x86_64.tar.xz`) is sufficient - you do NOT need the full `/opt/fil` release.

Last validated: 2026-05-16 on blank Debian 13 container. Also validated on Debian 12. Full nginx build succeeds — `objs-filc/nginx` binary produced (76-79MB).

## Critical Architecture Notes

### filcc is clang-20, not a wrapper

`filcc` is a symlink to `clang-20` — the same binary. Fil-C's clang has baked-in Fil-C runtime linking: it automatically links `-lc -lpizlo -lyoloc -lyolom -lyolort -lyolounwind` and sets RPATH to `pizfix/lib`. The deluge build scripts use raw `clang` (identical binary) with `CC="clang -g -O2"`.

**Key implication**: Any code compiled with `filcc`/`clang` produces objects with `pizlonated_` mangled symbols. These symbols are resolved at link time by `libpizlo.so` (for libc calls) and by Fil-C-built libraries (for third-party calls like zlib).

### Two library locations required

Fil-C-built libraries must live in **two places**:
1. `$PREFIX/lib/` — for the compiler to find during nginx build (headers in `$PREFIX/include/`)
2. `pizfix/lib/` — for the Fil-C runtime to find mangled symbols at link time

zlib **must** be in `pizfix/lib/` because OpenSSL calls `pizlonated_inflate`, `pizlonated_deflate`, etc.

### Host vs Container difference

The host container has `/opt/fil` (full 244MB release) with prebuilt OpenSSL in `/opt/fil/lib/` and headers in `/opt/fil/include/`. The host's nginx build links `-L/opt/fil/lib` for OpenSSL, **not** the freshly built `.filc-deps/prefix/`. The new container has no `/opt/fil`, so OpenSSL must be built from source and installed correctly.

## Environment Requirements

- **OS**: Debian 12/13 or compatible
- **Architecture**: x86_64
- **RAM**: 16GB+ recommended (OpenSSL build is memory-intensive)
- **Disk**: 4GB+ free space
- **Network**: Required for downloading Fil-C and dependency source tarballs

## Step 1: Install System Dependencies

Run the preinstall script to install all required system packages:

```bash
bash scripts/ci-preinstall.sh
```

This installs:
- `curl` - download tarballs and scripts
- `ca-certificates` - HTTPS verification
- `xz-utils` - extract .tar.xz Fil-C tarball
- `patchelf` - required by Fil-C setup.sh to fix RPATH
- `binutils` - provides ld linker (Fil-C links against system ld)
- `make` - build system for all dependencies and nginx
- `libc6-dev` - kernel headers (/usr/include/linux/*.h) needed by Fil-C
- `perl` - OpenSSL ./Configure script requires Perl

## Step 2: Install Fil-C Compiler

```bash
# Download the pizfix tarball (68MB)
curl -fsSL https://github.com/pizlonator/fil-c/releases/download/v0.678/filc-0.678-linux-x86_64.tar.xz -o filc.tar.xz

# Extract
tar xf filc.tar.xz
cd filc-0.678-linux-x86_64

# Run setup script (fixes RPATH, creates kernel header symlinks)
bash setup.sh

# Verify installation
build/bin/filcc --version
# Expected: Fil-C 0.678 clang version 20.1.8
```

### Obstacle 1: setup.sh exits with code 1

`setup.sh` fails with `mkdir: cannot create directory 'os-include': File exists` on second runs or if the symlinks already exist. This is a non-fatal error — the RPATH patching and symlinks were already applied successfully. The exit code 1 is from `set -e` catching the `mkdir` failure. You can safely ignore it, or run `setup.sh` once and proceed.

The compiler binaries are at `build/bin/`:
- `filcc` — symlink to `clang-20` (the Fil-C clang binary)
- `fil++` — symlink to `clang-20`
- `filcpp` — symlink to `clang-20`

## Step 3: Build Dependencies

The deluge branch build scripts (`build_zlib.sh`, `build_pcre2.sh`, `build_openssl.sh`) are hardcoded to the pizfix internal directory structure (`$PWD/../../../build/bin/clang`, `$PWD/../../../pizfix`) and will NOT work with a standalone extraction. You must build dependencies manually.

### Environment Setup

```bash
export FILC_ROOT="/path/to/filc-0.678-linux-x86_64/build"
export PATH="$FILC_ROOT/bin:$PATH"
export CC=filcc
export CXX="fil++"
export PREFIX="/path/to/your/deps/prefix"  # e.g. /tmp/filc-deps or .filc-deps
export PIZFIX_LIB="/path/to/filc-0.678-linux-x86_64/pizfix/lib"
```

### zlib 1.3

**Debian 13 note**: `cc` is not installed by default. `./configure` defaults to `cc` and will fail with "cc: not found". Always pass `CC=filcc` explicitly.

```bash
curl -fsSL https://zlib.net/fossils/zlib-1.3.tar.gz -o zlib-1.3.tar.gz
tar xzf zlib-1.3.tar.gz
cd zlib-1.3
CC=filcc ./configure --prefix=$PREFIX
make -j$(nproc) CC=filcc
make install
cd ..
```

**CRITICAL**: After building, copy the Fil-C-built zlib into `pizfix/lib/` so the Fil-C runtime can resolve mangled zlib symbols (`pizlonated_inflate`, `pizlonated_deflate`, etc.) at link time:

```bash
cp $PREFIX/lib/libz.a $PREFIX/lib/libz.so.1.3 $PIZFIX_LIB/
ln -sf libz.so.1.3 $PIZFIX_LIB/libz.so
ln -sf libz.so.1.3 $PIZFIX_LIB/libz.so.1
```

**Status**: Builds cleanly. Must be in both `$PREFIX/lib/` and `pizfix/lib/`.

### PCRE2 10.44

```bash
curl -fsSL https://github.com/PCRE2Project/pcre2/releases/download/pcre2-10.44/pcre2-10.44.tar.gz -o pcre2.tar.gz
tar xzf pcre2.tar.gz
cd pcre2-10.44
CC=filcc ./configure --prefix=$PREFIX --enable-pcre2-16 --enable-pcre2-32
make -j$(nproc) CC=filcc
make install
cd ..
```

**Status**: Builds cleanly with `filcc`. Only needs `$PREFIX/lib/`.

### OpenSSL 3.3.1

#### Obstacle 2: Must use raw clang, not filcc with extra flags

The deluge build script uses `CC="clang -g -O2"` (raw clang, same binary as filcc). Using `CC="filcc -I$PREFIX/include"` works for compilation but the resulting shared libraries link against system paths that don't include `pizfix/lib/`, causing `pizlonated_*` symbol resolution failures at link time.

**Fix**: Use raw `clang` with include path for headers and `LDFLAGS` pointing to `pizfix/lib/` for zlib:

```bash
curl -fsSL https://www.openssl.org/source/openssl-3.3.1.tar.gz -o openssl-3.3.1.tar.gz
tar xzf openssl-3.3.1.tar.gz
cd openssl-3.3.1
```

#### Obstacle 3: Inline assembly fails with Fil-C

OpenSSL 3.3.1 contains inline assembly in `crypto/x86_64cpuid.c` and other `.S` files that Fil-C cannot compile.

**Fix**: Pass `no-asm` to `./Configure`.

#### Obstacle 4: `make install_sw` fails on engine/test linking

Fil-C mangles all symbols with `pizlonated_` prefix. The libraries (`libcrypto.a`, `libssl.a`) compile fine, but linking test executables and shared engines fails.

**Fix**: Build only the libraries, then manually copy them.

#### Full OpenSSL Build Sequence (validated)

```bash
cd openssl-3.3.1

# Use raw clang with pizfix/lib for zlib resolution
CC="clang -I$PREFIX/include -g -O2" \
LDFLAGS="-L$PIZFIX_LIB" \
./Configure --prefix=$PREFIX --openssldir=$PREFIX/ssl zlib no-asm linux-x86_64

# Build libraries only (skip tests/engines)
make build_libs -j$(nproc)

# Manually install libraries to prefix (for compiler to find)
mkdir -p $PREFIX/lib
cp libcrypto.a libcrypto.so libcrypto.so.3 $PREFIX/lib/
cp libssl.a libssl.so libssl.so.3 $PREFIX/lib/
cp -r include/openssl $PREFIX/include/ 2>/dev/null || true

# Install shared libs to pizfix (for runtime symbol resolution)
cp libcrypto.so libcrypto.so.3 $PIZFIX_LIB/
cp libssl.so libssl.so.3 $PIZFIX_LIB/
cd ..
```

**Result**: `libcrypto.a` (~111MB), `libssl.a` (~32MB), plus shared `.so` variants. Headers in `$PREFIX/include/openssl/`.

### Dependency Summary

| Dependency | Version | Status | Locations Required | Obstacles |
|---|---|---|---|---|
| zlib | 1.3 | ✅ Clean build | `$PREFIX/lib/` + `pizfix/lib/` | Must be in pizfix for mangled symbols |
| PCRE2 | 10.44 | ✅ Clean build | `$PREFIX/lib/` only | None |
| OpenSSL | 3.3.1 | ✅ Libraries built | `$PREFIX/lib/` + `pizfix/lib/` | #2 (clang CC), #3 (no-asm), #4 (manual install) |

## Step 4: Configure and Build Nginx

### Obstacle 5: nginx cannot find OpenSSL without `--with-openssl`

`scripts/configure-filc-nginx.sh` does not pass `--with-openssl`, so nginx's `./auto/configure` searches `/usr/local`, `/usr/pkg`, `/opt/local`, `/opt/homebrew` but not arbitrary `$PREFIX`. The configure probe links with `-lssl -lcrypto` (shared libs) which fail because `libssl.so` cannot resolve its `pizlonated_*` dependencies from `libcrypto.so` at link time — shared-to-shared `pizlonated_*` symbol resolution fails with the system `ld`.

**Solution**: Use `--with-openssl=$PREFIX` with pre-populated `.openssl/` structure containing **static** libraries. Static `libssl.a` + `libcrypto.a` link correctly because all `pizlonated_*` symbols resolve within the archive.

#### Setup `.openssl/` structure for nginx

nginx expects the OpenSSL build artifacts in `$PREFIX/.openssl/`:

```bash
# Create .openssl directory structure
mkdir -p $PREFIX/.openssl/lib $PREFIX/.openssl/include/openssl

# Copy static libraries (nginx links these directly)
cp $PREFIX/lib/libssl.a $PREFIX/lib/libcrypto.a $PREFIX/.openssl/lib/

# Copy headers
cp -r $PREFIX/include/openssl/* $PREFIX/.openssl/include/openssl/
```

#### Configure with `--with-openssl`

```bash
./auto/configure \
  --builddir=objs-filc \
  --prefix=.filc-nginx-install \
  --with-filc-mode \
  --with-cc=filcc \
  --with-cc-opt="-O2 -fno-omit-frame-pointer -I$PREFIX/include -Wno-error" \
  --with-ld-opt="-L$PREFIX/lib -Wl,-rpath,$PREFIX/lib" \
  --with-http_ssl_module \
  --with-http_v2_module \
  --with-openssl=$PREFIX
```

**Note**: `-Wno-error` is required because Fil-C's `sys/socket.h` `CMSG_NXTHDR` macro triggers `-Wsign-compare` in `ngx_event_udp.c`.

#### Obstacle 7: OpenSSL rebuild rule fires during make

The generated Makefile contains a rule to rebuild OpenSSL from source if `$PREFIX/.openssl/include/openssl/ssl.h` is older than `objs-filc/Makefile`. This will fail because it tries to run `./config` (the OpenSSL Configure script) in `$PREFIX/` which is not an OpenSSL source directory.

**Fix**: Touch `ssl.h` after configure to make it newer than the Makefile:

```bash
sleep 1
touch $PREFIX/.openssl/include/openssl/ssl.h
```

### Obstacle 6: make must run from repo root

The nginx Makefile uses relative paths (`src/core/nginx.h`). Both `make -C objs-filc` and `make -f objs-filc/Makefile` require running from the repository root.

**Fix**: Run from the repository root:

```bash
cd /path/to/filc-nginx-master
make -f objs-filc/Makefile -j"$(nproc)"
```

### Result

The resulting binary at `objs-filc/nginx` (~79MB) links statically against Fil-C-built OpenSSL, zlib, and PCRE2. Verify with:

```bash
./objs-filc/nginx -V
# nginx version: nginx/1.31.0
# built by clang 20.1.8 (git@github.com:pizlonator/llvm-project-deluge.git ...)
# built with OpenSSL 3.3.1
```

## Complete Known Issues and Workarounds

### OpenSSL Inline Assembly (resolved via `no-asm`)

OpenSSL 3.3.1 contains inline assembly in `crypto/x86_64cpuid.c` that Fil-C cannot execute.

**Workaround**: Pass `no-asm` to OpenSSL's `./Configure`.

### Linux AIO (syscall 206)

Fil-C's `libpizlo.so` runtime does not support syscall 206 (`io_setup`). This blocks `--with-file-aio`.

**Workaround**: Build without `--with-file-aio`. Use standard synchronous I/O or `aio off`.

### Shared Memory Pointers

Pointers stored in and read from shared memory (`shmget`/`shmat`) have null capability in Fil-C's InvisiCap model. The nginx source in this repository includes the offset-based storage workaround (Bug 3 fix).

### Deluge Build Scripts Incompatible with Standalone Tarball

The scripts fetched from `pizlonator/fil-c` deluge branch (`build_zlib.sh`, `build_pcre2.sh`, `build_openssl.sh`) reference hardcoded paths like `$PWD/../../../build/bin/clang` and `$PWD/../../../pizfix`. They only work inside the full `/opt/fil` directory tree. For standalone pizfix tarball, build dependencies manually as documented in Step 3.

### Fil-C Symbol Mangling

Fil-C prefixes all exported symbols with `pizlonated_`. This causes linker failures when building executables or shared objects that link against Fil-C-compiled static libraries. The libraries themselves compile fine. Only final linking of binaries (test harnesses, engines, plugins) is affected.

**Impact**: OpenSSL test executables and engine `.so` files cannot be built. The core libraries (`libcrypto.a`, `libssl.a`) are unaffected and work correctly.

### Host `/opt/fil` masks the OpenSSL gap

The host machine has `/opt/fil` (full 244MB release) with prebuilt OpenSSL in `/opt/fil/lib/`. The host's nginx Makefile links `-L/opt/fil/lib -L.filc-deps/prefix/lib` — the OpenSSL comes from `/opt/fil`, while zlib/PCRE2 come from `.filc-deps/prefix/`. This means the host "works" even though `build-filc-deps.sh` never successfully installs OpenSSL to `.filc-deps/prefix/`. The container has no `/opt/fil`, exposing this gap.

## Pizfix vs /opt/fil

| Feature | Pizfix Tarball | /opt/fil Release |
|---|---|---|
| Size | 68MB | 244MB |
| libc | musl | glibc 2.40 |
| Root required | No | Yes |
| Prebuilt programs | No | Yes (ssh, git, tmux, etc.) |
| Prebuilt OpenSSL | No | Yes (`/opt/fil/lib/libssl.so`, `/opt/fil/include/openssl/`) |
| Suitable for nginx build | **Yes** | Yes |

The standalone pizfix tarball is sufficient for building nginx. The `/opt/fil` release is only needed if you want a complete Fil-C userland with prebuilt programs.

## Troubleshooting

### "ld doesn't exist"
Install `binutils`: `apt-get install binutils`

### "zlib.h file not found" (during OpenSSL build)
Pass `-I$PREFIX/include` in `CC` and set `LDFLAGS="-L$PIZFIX_LIB"` for OpenSSL's `./Configure`.

### "patchelf: command not found"
Install `patchelf`: `apt-get install patchelf`

### "Cannot exec: xz"
Install `xz-utils`: `apt-get install xz-utils`

### OpenSSL Configure fails with Perl error
Install `perl`: `apt-get install perl`

### "pizlonated_BIO_ctrl: undefined reference" during OpenSSL make
This is Obstacle 4. Run `make build_libs` instead of `make`, then manually copy `.a` and `.so` files to `$PREFIX/lib/` and `$PIZFIX_LIB/`.

### "pizlonated_inflate: symbol not found" at runtime
Fil-C-built zlib must be in `pizfix/lib/`. Copy: `cp $PREFIX/lib/libz.* $PIZFIX_LIB/`.

### setup.sh exits with code 1
This is Obstacle 1. The `mkdir os-include` fails if the directory already exists. The RPATH patching succeeded — safe to proceed.

### nginx configure: "SSL modules require the OpenSSL library"
This is Obstacle 5. The dynamic probe links `-lssl -lcrypto` (shared libs) which fail because `libssl.so` cannot resolve `pizlonated_*` from `libcrypto.so`. Use `--with-openssl=$PREFIX` with pre-populated `.openssl/` containing static libraries.

### "No rule to make target 'src/core/nginx.h'"
This is Obstacle 6. Run `make -f objs-filc/Makefile` from the repository root directory, not `make -C objs-filc`.

### "./config: not found" during make
This is Obstacle 7. The Makefile tries to rebuild OpenSSL from `$PREFIX/`. Fix: `touch $PREFIX/.openssl/include/openssl/ssl.h` after configure.

### "comparison of integers of different signs" in ngx_event_udp.c
Fil-C's `sys/socket.h` `CMSG_NXTHDR` macro triggers `-Wsign-compare`. Fix: add `-Wno-error` to `--with-cc-opt`.

### Shared libssl.so cannot link (pizlonated_* undefined)
Shared `libssl.so` cannot resolve `pizlonated_*` from shared `libcrypto.so` at link time with system `ld`. Use static `libssl.a` + `libcrypto.a` instead (nginx `--with-openssl=` does this automatically).
