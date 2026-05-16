# FILC Nginx Port - Progress Report

## Status: BUILD SUCCESSFUL, BASIC RUNTIME FULLY WORKING, SHARED MEMORY BLOCKED

**Date**: 2026-05-14  
**Target**: nginx 1.31.0 compiled with Fil-C compiler (`filcc` v0.678, clang 20.1.8)  
**Fil-C Installation**: `/opt/fil`

---

## Build Configuration

```
--builddir=/workspace/filc-nginx-master/objs-filc
--prefix=/workspace/filc-nginx-master/.filc-nginx-install
--with-filc-mode
--with-cc=filcc
--with-cc-opt='-O2 -fno-omit-frame-pointer -I/workspace/filc-nginx-master/.filc-deps/prefix/include'
--with-ld-opt='-L/workspace/filc-nginx-master/.filc-deps/prefix/lib -Wl,-rpath,/workspace/filc-nginx-master/.filc-deps/prefix/lib'
```

### Enabled Features (via `--with-filc-mode`)
The `--with-filc-mode` flag enables Fil-C friendly probe behavior:
- Runtime probes for epoll, sendfile, prctl, mmap, sysvshm, POSIX semaphores are **skipped** (compile-only checks)
- GCC builtin atomic operations detected and enabled
- C99 variadic macros enabled
- EPOLLRDHUP, EPOLLEXCLUSIVE detected
- PCRE2, zlib, OpenSSL linked from Fil-C built dependencies

### Compiler Detection
- Fil-C detected as Clang-compatible via `filcc -v` output containing "clang version"
- Compiler string: `clang 20.1.8 (git@github.com:pizlonator/fil-c 139f13928892d95d8ab735ff4e0be797d9121449)`

---

## Bugs Fixed

### Bug 1: Inline Assembly Crash in `ngx_cpuinfo.c`

**File**: `src/core/ngx_cpuinfo.c`  
**Error**: `filc safety error: cannot handle inline asm (nontrivial assembly, cannot analyze): %7 = call { i32, i32, i32, i32 } asm "cpuid"`  
**Root Cause**: `__get_cpuid()` from `<cpuid.h>` expands to inline assembly that Fil-C runtime cannot execute.  
**Fix**: Replaced entire cpuinfo implementation with compile-time default. Fil-C cannot execute inline assembly, so the `cpuid` instruction must be avoided entirely.

```c
// Before: Used __get_cpuid() which emits inline asm
// After: Uses NGX_CPU_CACHE_LINE compile-time default (64 bytes)
```

### Bug 2: Inline Assembly in `ngx_cpu_pause`

**File**: `src/os/unix/ngx_atomic.h` (line 68)  
**Error**: `__asm__ ("pause")` inline assembly in GCC atomic path  
**Root Cause**: The `ngx_cpu_pause()` macro used inline assembly for the x86 PAUSE instruction.  
**Fix**: Replaced with `__builtin_ia32_lfence()` compiler builtin which Fil-C can handle.

```c
// Before: #define ngx_cpu_pause() __asm__ ("pause")
// After:  #define ngx_cpu_pause() __builtin_ia32_lfence()
```

### Bug 3: Slab Allocator Pointer-Integer Round-Trip (PARTIAL FIX - Capability Issue)

**File**: `src/core/ngx_slab.c`, `src/core/ngx_slab.h`  
**Error**: `filc safety error: cannot write pointer with null object` at `ngx_slab_alloc_pages`  
**Root Cause**: The nginx slab allocator stores pointers as `uintptr_t` integers in the `ngx_slab_page_t.prev` field, then casts them back to pointers. In Fil-C's InvisiCap model, casting an integer to a pointer produces a pointer with a **null capability**, which cannot be dereferenced.

**Attempted Fixes**:

1. **`zexact_ptrtable` approach (FAILED)**: Used `zexact_ptrtable_encode`/`zexact_ptrtable_decode` from `stdfil.h` to encode/decode pointers. Failed because the slab pool is allocated via `shmget`/`shmat` (shared memory), and `zexact_ptrtable` cannot properly track pointers into non-GC-managed memory regions. Pointers decoded from the table had null capabilities.

2. **Global `zexact_ptrtable` approach (FAILED)**: Moved the ptrtable to a global static variable to avoid storing the ptrtable pointer in shared memory. Still failed for the same reason - shared memory pointers aren't tracked by the Fil-C GC.

3. **`zorptr`/`zandptr` pointer tagging approach (CURRENT - PARTIAL)**: Changed `prev` field from `uintptr_t` to `ngx_slab_page_t*` in Fil-C mode, using `zorptr` to tag type bits into the pointer and `zandptr` to strip them. This preserves pointer capabilities natively. **Builds successfully**, but shared memory tests still crash because Fil-C's InvisiCap model re-bases pointer capabilities on the memory region being read. When a pointer is read from shared memory (`shmget`/`shmat` region), the capability is the shared memory region's capability, which may not cover the target address properly.

**Current State**: The slab allocator code is modified for Fil-C mode with `zorptr`/`zandptr` macros:
```c
#define ngx_slab_set_prev(page, ptr, type)                                    \
    do { (page)->prev = (ngx_slab_page_t *) zorptr((void *)(ptr), (type)); } while (0)
#define ngx_slab_get_prev(page)                                               \
    ((ngx_slab_page_t *) zandptr((page)->prev, ~NGX_SLAB_PAGE_MASK))
```

**Required Fix**: The slab allocator needs a fundamental redesign for Fil-C shared memory. Options:
- **Index-based approach**: Replace pointer storage with array indices. All pointers in the slab allocator reference locations within the same contiguous allocation, so indices (offsets from `pool->pages`) could replace raw pointers.
- **`zsetcap` approach**: After initializing the slab pool, use `zsetcap` to set the capability of all stored pointers to match the slab pool's capability.
- **Avoid shared memory**: For single-process Fil-C nginx, use heap-allocated memory instead of `shmget`/`shmat`. This gives heap pointers with valid capabilities.

---

## Test Results

### Basic Runtime Tests (NO shared memory features): ALL PASSED ✅

| # | Test | Result | Details |
|---|------|--------|---------|
| 1 | Static HTML serving | ✅ PASS | Returns "Hello from FILC nginx!" |
| 2 | Return directive | ✅ PASS | Custom response bodies work |
| 3 | JSON response | ✅ PASS | `{"status":"ok","port":"filc"}` |
| 4 | Custom headers | ✅ PASS | Content-Type, Server headers correct |
| 5 | Redirect (302) | ✅ PASS | HTTP 302 returned correctly |
| 6 | Custom 404 | ✅ PASS | Error handling works |
| 7 | Content-Type JSON | ✅ PASS | Header manipulation works |
| 8 | Concurrent requests (20 parallel) | ✅ PASS | All 20 returned HTTP 200 |
| 9 | Sequential requests (50) | ✅ PASS | 50/50 returned HTTP 200 |
| 10 | POST request | ✅ PASS | Request body handling works |
| 11 | Keepalive connections | ✅ PASS | Connection reuse works |

### Version Check
```
$ nginx -V
nginx version: nginx/1.31.0
built by clang 20.1.8 (git@github.com:pizlonator/fil-c 139f13928892d95d8ab735ff4e0be797d9121449)
```

### Config Test
```
$ nginx -t
nginx: the configuration file syntax is ok
nginx: configuration file test is successful
```

### Shared Memory Tests: FAILED ❌

| Test | Result | Error |
|------|--------|-------|
| `limit_req_zone` | ❌ FAIL | `filc safety error: cannot write pointer with null object` at `ngx_slab_alloc_pages` |
| `limit_conn_zone` | ❌ FAIL | Same slab allocator crash |
| `upstream zone` | ❌ FAIL | Same slab allocator crash |

---

## Known Limitations

### Shared Memory Slab Allocator (BLOCKER for advanced features)

The slab allocator crash occurs because Fil-C's InvisiCap model doesn't preserve pointer capabilities across shared memory (`shmget`/`shmat`) read/write operations. When a pointer is stored in shared memory and read back, the resulting pointer has the shared memory region's capability, which may not properly cover the target address.

**Affected features** (all require shared memory zones):
- `limit_req_zone` (rate limiting)
- `limit_conn_zone` (connection limiting)
- `upstream` zone directives
- `proxy_cache` with shared memory
- Any `zone=` parameter
- Open file cache with shared memory

---

## FILC Definitions Status

| Definition | Status | Notes |
|------------|--------|-------|
| `NGX_FILC_MODE` | ✅ ENABLED | Via `--with-filc-mode` configure flag |
| `NGX_HAVE_GCC_ATOMIC` | ✅ ENABLED | Uses `__sync_*` builtins (no inline asm) |
| `NGX_HAVE_C99_VARIADIC_MACROS` | ✅ ENABLED | |
| `NGX_HAVE_GCC_VARIADIC_MACROS` | ✅ ENABLED | |
| `NGX_HAVE_GCC_BSWAP64` | ✅ ENABLED | |
| `NGX_HAVE_EPOLL` | ✅ ENABLED | Compile-only check (filc_override=yes) |
| `NGX_HAVE_CLEAR_EVENT` | ✅ ENABLED | |
| `NGX_HAVE_EPOLLRDHUP` | ✅ ENABLED | |
| `NGX_HAVE_EPOLLEXCLUSIVE` | ✅ ENABLED | |
| `NGX_HAVE_EVENTFD` | ✅ ENABLED | Compile-only check |
| `NGX_HAVE_SYS_EVENTFD_H` | ✅ ENABLED | |
| `NGX_HAVE_O_PATH` | ✅ ENABLED | |
| `NGX_HAVE_SENDFILE` | ✅ ENABLED | Compile-only check (filc_override=yes) |
| `NGX_HAVE_SENDFILE64` | ✅ ENABLED | Compile-only check |
| `NGX_HAVE_PR_SET_DUMPABLE` | ✅ ENABLED | Compile-only check |
| `NGX_HAVE_PR_SET_KEEPCAPS` | ✅ ENABLED | Compile-only check |
| `NGX_HAVE_CAPABILITIES` | ✅ ENABLED | Compile-only check |
| `NGX_HAVE_GNU_CRYPT_R` | ✅ ENABLED | |
| `NGX_HAVE_BPF` | ✅ ENABLED | |
| `NGX_HAVE_SO_COOKIE` | ✅ ENABLED | |
| `NGX_HAVE_UDP_SEGMENT` | ✅ ENABLED | |
| `NGX_HAVE_NONALIGNED` | ✅ ENABLED | |
| `NGX_CPU_CACHE_LINE` | ✅ 64 | Compile-time default |
| `NGX_HAVE_CRYPT` | ✅ ENABLED | |
| `NGX_HAVE_POSIX_FADVISE` | ✅ ENABLED | |
| `NGX_HAVE_O_DIRECT` | ✅ ENABLED | |
| `NGX_HAVE_ALIGNED_DIRECTIO` | ✅ ENABLED | |
| `NGX_HAVE_STATFS` | ✅ ENABLED | |
| `NGX_HAVE_STATVFS` | ✅ ENABLED | |
| `NGX_HAVE_DLOPEN` | ✅ ENABLED | |
| `NGX_HAVE_SCHED_YIELD` | ✅ ENABLED | |
| `NGX_HAVE_SCHED_SETAFFINITY` | ✅ ENABLED | |
| `NGX_HAVE_REUSEPORT` | ✅ ENABLED | |
| `NGX_HAVE_TRANSPARENT_PROXY` | ✅ ENABLED | |
| `NGX_HAVE_IP_BIND_ADDRESS_NO_PORT` | ✅ ENABLED | |
| `NGX_HAVE_IP_PKTINFO` | ✅ ENABLED | |
| `NGX_HAVE_IPV6_RECVPKTINFO` | ✅ ENABLED | |
| `NGX_HAVE_IP_MTU_DISCOVER` | ✅ ENABLED | |
| `NGX_HAVE_IPV6_MTU_DISCOVER` | ✅ ENABLED | |
| `NGX_HAVE_IPV6_DONTFRAG` | ✅ ENABLED | |
| `NGX_HAVE_DEFERRED_ACCEPT` | ✅ ENABLED | |
| `NGX_HAVE_KEEPALIVE_TUNABLE` | ✅ ENABLED | |
| `NGX_HAVE_TCP_FASTOPEN` | ✅ ENABLED | |
| `NGX_HAVE_TCP_INFO` | ✅ ENABLED | |
| `NGX_HAVE_ACCEPT4` | ✅ ENABLED | |
| `NGX_HAVE_UNIX_DOMAIN` | ✅ ENABLED | |
| `NGX_HAVE_LITTLE_ENDIAN` | ✅ ENABLED | |
| `NGX_HAVE_INET6` | ✅ ENABLED | |
| `NGX_HAVE_PREAD` | ✅ ENABLED | |
| `NGX_HAVE_PWRITE` | ✅ ENABLED | |
| `NGX_HAVE_PWRITEV` | ✅ ENABLED | |
| `NGX_HAVE_STRERRORDESC_NP` | ✅ ENABLED | |
| `NGX_HAVE_LOCALTIME_R` | ✅ ENABLED | |
| `NGX_HAVE_CLOCK_MONOTONIC` | ✅ ENABLED | |
| `NGX_HAVE_POSIX_MEMALIGN` | ✅ ENABLED | |
| `NGX_HAVE_MEMALIGN` | ✅ ENABLED | |
| `NGX_HAVE_MAP_ANON` | ✅ ENABLED | Compile-only check (filc_override=yes) |
| `NGX_HAVE_MAP_DEVZERO` | ✅ ENABLED | |
| `NGX_HAVE_SYSVSHM` | ✅ ENABLED | Compile-only check (filc_override=yes) |
| `NGX_HAVE_POSIX_SEM` | ✅ ENABLED | Compile-only check (filc_override=yes) |
| `NGX_HAVE_MSGHDR_MSG_CONTROL` | ✅ ENABLED | |
| `NGX_HAVE_FIONBIO` | ✅ ENABLED | |
| `NGX_HAVE_FIONREAD` | ✅ ENABLED | |
| `NGX_HAVE_GMTOFF` | ✅ ENABLED | |
| `NGX_HAVE_D_TYPE` | ✅ ENABLED | |
| `NGX_HAVE_SC_NPROCESSORS_ONLN` | ✅ ENABLED | |
| `NGX_HAVE_LEVEL1_DCACHE_LINESIZE` | ✅ ENABLED | |
| `NGX_HAVE_OPENAT` | ✅ ENABLED | |
| `NGX_HAVE_GETADDRINFO` | ✅ ENABLED | |
| `NGX_HTTP_CACHE` | ✅ ENABLED | |
| `NGX_HTTP_GZIP` | ✅ ENABLED | |
| `NGX_HTTP_SSI` | ✅ ENABLED | |
| `NGX_CRYPT` | ✅ ENABLED | |
| `NGX_HTTP_X_FORWARDED_FOR` | ✅ ENABLED | |
| `NGX_HTTP_UPSTREAM_LEAST_TIME` | ✅ ENABLED | |
| `NGX_HTTP_UPSTREAM_ZONE` | ⚠️ COMPILED | Requires shared memory (blocked) |
| `NGX_HTTP_UPSTREAM_STICKY` | ✅ ENABLED | |
| `NGX_HTTP_UPSTREAM_SID` | ✅ ENABLED | |
| `NGX_PCRE2` | ✅ ENABLED | Fil-C built PCRE2 |
| `NGX_PCRE` | ✅ ENABLED | |
| `NGX_ZLIB` | ✅ ENABLED | Fil-C built zlib |
| `NGX_SMP` | ✅ ENABLED | |

**Summary**: ~100 definitions enabled, all compile-time features detected. Runtime features work except those requiring shared memory zones.

---

## Build Artifacts

- **Binary**: `objs-filc/nginx` (14.9 MB)
- **Makefile**: `objs-filc/Makefile`
- **Auto-config**: `objs-filc/ngx_auto_config.h` (541 lines, ~100 features detected)
- **Install prefix**: `.filc-nginx-install/`
- **Dependencies**: `.filc-deps/prefix/` (PCRE2, zlib, OpenSSL built with Fil-C)

---

## Remaining Work for Full Port

### High Priority (BLOCKERS)
1. **Slab allocator shared memory fix** - Requires fundamental redesign:
   - Index-based approach (replace pointers with array indices)
   - Or heap-based allocation for single-process mode
   - Or `zsetcap`-based capability fixup after allocation
2. **Test with SSL/TLS** - Verify OpenSSL integration works at runtime (may also need shared memory for session cache)
3. **Test proxy module** - Verify reverse proxy functionality

### Medium Priority
4. **Stream module** - TCP/UDP proxy (requires shared memory)
5. **Mail module** - IMAP/POP3/SMTP proxy
6. **HTTP/2 support** - Requires OpenSSL ALPN

### Nice to Have
7. **Performance benchmarking** - Compare Fil-C vs native nginx performance
8. **Memory safety validation** - Intentionally trigger buffer overflows to confirm Fil-C catches them
9. **Fuzzing** - Run AFL/libFuzzer against Fil-C nginx to find memory safety issues

---

## Fil-C Runtime Notes

- **GC**: FUGC (Fil's Unbelievable Garbage Collector) - concurrent, accurate, non-moving
- **Capabilities**: InvisiCap model - pointers carry invisible bounds/type capabilities
- **Performance**: ~1.5x-4x slower than native C (per Fil-C documentation)
- **Memory Safety**: All pointer accesses bounds-checked; freed objects trap on access
- **No inline assembly**: Fil-C cannot execute inline assembly at runtime
- **Shared memory**: `shmget`/`shmat` regions have different capability semantics than heap memory. Pointers stored in and read from shared memory are re-based to the shared memory region's capability.

---

## Commands for Reproduction

```bash
# Setup environment
export PATH=/opt/fil/bin:$PATH
export CC=filcc

# Configure
scripts/configure-filc-nginx.sh

# Build (with 500s timeout kill task)
(timeout 500 make -f objs-filc/Makefile -j$(nproc) 2>&1 | tee /tmp/filc-build.log) &
BUILD_PID=$!
(sleep 500 && kill -9 $BUILD_PID 2>/dev/null) &
wait $BUILD_PID

# Test
objs-filc/nginx -V          # Version info
objs-filc/nginx -t          # Config test (without shared memory zones)
objs-filc/nginx             # Run (needs valid config without zone= directives)
```

---

## Changelog

### 2026-05-14 (This Session)
- **Fixed**: Bug 3 - Slab allocator pointer-int round-trip (partial fix, `zorptr`/`zandptr` approach)
  - Modified `ngx_slab.h`: Changed `prev` field to `ngx_slab_page_t*` for Fil-C mode
  - Modified `ngx_slab.c`: Added `ngx_slab_set_prev`/`ngx_slab_get_prev`/`ngx_slab_get_type` macros
  - All 15+ pointer stores/loads converted to use capability-preserving operations
  - Build succeeds, basic runtime works, shared memory still blocked by InvisiCap model
- **Tested**: Comprehensive runtime test suite (11 tests, all passed without shared memory)
  - Basic HTML serving, JSON, redirects, concurrent requests, POST, keepalive
  - 50 sequential requests: 50/50 passed
  - 20 concurrent requests: all passed
- **Documented**: Updated PROGRESS.md with comprehensive status

### Previous Sessions
- **Fixed**: Bug 1 - Inline assembly in `ngx_cpuinfo.c` (replaced with compile-time default)
- **Fixed**: Bug 2 - Inline assembly in `ngx_cpu_pause` (replaced with `__builtin_ia32_lfence()`)
- **Built**: First successful Fil-C nginx binary (14.9 MB)
- **Tested**: Basic runtime functionality (10 tests, all passed)

---

## Reference Documents

- `Manifesto.md` - Fil-C philosophy and architecture
- `runtime.md` - Fil-C runtime (libc sandwich, libpizlo.so)
- `stdfil.md` - `stdfil.h` API reference (zptrtable, zgc_*, zorptr, zandptr, etc.)
- `docs/filc-build.md` - Build workflow documentation
- `docs/filc-triage.md` - Failure triage and remediation guide
