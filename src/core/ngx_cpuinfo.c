
/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) Nginx, Inc.
 */


#include <ngx_config.h>
#include <ngx_core.h>


/*
 * Fil-C does not support inline assembly (cpuid instruction).
 * We use the compile-time detected NGX_CPU_CACHE_LINE (default 64)
 * which covers all modern x86_64 CPUs.
 */

void
ngx_cpuinfo(void)
{
#ifndef NGX_CPU_CACHE_LINE
    ngx_cacheline_size = 64;
#endif
}
