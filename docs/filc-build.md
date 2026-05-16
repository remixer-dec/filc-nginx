# fil-c dependency + nginx packaging workflow

This repository includes helper scripts for producing a reproducible nginx build that links against fil-c-built dependency libraries.

## 1) Build memory-safe dependency libraries

```bash
scripts/build-filc-deps.sh
```

Defaults:
- `FILC_ROOT=/opt/filc`
- `DEPS_DIR=.filc-deps`
- `PREFIX_DIR=.filc-deps/prefix`

The script downloads and runs dependency builders from `pizlonator/fil-c` (branch `deluge`) for:
- PCRE2 (fallback to PCRE)
- zlib
- OpenSSL

`nghttp2` is fetched for parity with upstream helper scripts, but is not required for this non-QUIC build.

## 2) Configure nginx in a reproducible preset

```bash
scripts/configure-filc-nginx.sh
```

This preset:
- Uses deterministic `builddir` (`objs-filc`).
- Prefers headers/libraries from `.filc-deps/prefix`.
- Keeps essential modules enabled for rewrite/gzip/map/proxy/referer/fastcgi/http-cache paths.
- Keeps PCRE2 enabled (default nginx behavior) and uses the fil-c-built prefix for discovery.
- Disables optional mail/stream and several non-essential HTTP modules to reduce dependency complexity.
- Enables `--with-filc-mode` so fragile runtime feature probes are converted to compile-only checks where safe.

## 3) Build nginx (currently with host compiler)

```bash
make -C objs-filc -j"$(nproc)"
```

## 4) Package for deployment

```bash
scripts/package-filc-nginx.sh
```

Produces:
- `filc-nginx.tar.gz`

## 5) FIL-C build/fix loop for follow-up sessions

Use this loop to iteratively drive FIL-C remediation:

1. **Environment setup**
   ```bash
   export PATH=/opt/filc/build/bin:$PATH
   export CC=clang-20
   ```

2. **(Re)configure with the FIL-C preset**
   ```bash
   scripts/configure-filc-nginx.sh
   ```

3. **Run a partial compile and capture output**
   ```bash
   make -j"$(nproc)" -k 2>&1 | tee /tmp/filc-build.log
   ```

4. **Extract the first actionable diagnostics**
   ```bash
   rg -n "error:" /tmp/filc-build.log | head -n 50
   ```

5. **Apply one minimal fix at a time**
   - Prefer small, local edits that preserve behavior.
   - Reuse a documented pattern from `docs/filc-triage.md` and record it in the tracking table.

6. **Rebuild quickly and confirm progress**
   ```bash
   make -j"$(nproc)" -k 2>&1 | tee /tmp/filc-build.log
   rg -n "error:" /tmp/filc-build.log | head -n 50
   ```

7. **Checkpoint hygiene**
   - When a fix removes or reduces diagnostics, commit immediately with:
     - affected file(s)
     - error class
     - remediation pattern used

### Suggested per-session exit criteria
- At least one previously failing diagnostic is resolved or intentionally triaged.
- Tracking sheet is updated for every touched diagnostic family.
- Latest build log is saved to `/tmp/filc-build.log` and first-error list is reproducible with `rg`.
