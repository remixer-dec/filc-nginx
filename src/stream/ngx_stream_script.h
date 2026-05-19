
/*
 * Copyright (C) Igor Sysoev
 * Copyright (C) Nginx, Inc.
 */


#ifndef _NGX_STREAM_SCRIPT_H_INCLUDED_
#define _NGX_STREAM_SCRIPT_H_INCLUDED_


#include <ngx_config.h>
#include <ngx_core.h>
#include <ngx_stream.h>


typedef struct {
    u_char                       *ip;
    u_char                       *pos;
    ngx_stream_variable_value_t  *sp;

    ngx_str_t                     buf;
    ngx_str_t                     line;

    unsigned                      flushed:1;
    unsigned                      skip:1;

    ngx_stream_session_t         *session;
} ngx_stream_script_engine_t;


typedef struct {
    ngx_conf_t                   *cf;
    ngx_str_t                    *source;

    ngx_array_t                 **flushes;
    ngx_array_t                 **lengths;
    ngx_array_t                 **values;

    ngx_uint_t                    variables;
    ngx_uint_t                    ncaptures;
    ngx_uint_t                    size;

    void                         *main;

    unsigned                      complete_lengths:1;
    unsigned                      complete_values:1;
    unsigned                      zero:1;
    unsigned                      conf_prefix:1;
    unsigned                      root_prefix:1;
} ngx_stream_script_compile_t;


typedef struct {
    ngx_str_t                     value;
    ngx_uint_t                   *flushes;
    void                         *lengths;
    void                         *values;

    union {
        size_t                    size;
    } u;
} ngx_stream_complex_value_t;


typedef struct {
    ngx_conf_t                   *cf;
    ngx_str_t                    *value;
    ngx_stream_complex_value_t   *complex_value;

    unsigned                      zero:1;
    unsigned                      conf_prefix:1;
    unsigned                      root_prefix:1;
} ngx_stream_compile_complex_value_t;


typedef void (*ngx_stream_script_code_pt) (ngx_stream_script_engine_t *e);
typedef size_t (*ngx_stream_script_len_code_pt) (ngx_stream_script_engine_t *e);


#ifdef NGX_FILC_MODE

/*
 * Fil-C function pointers are capabilities.  Stream script bytecode stores
 * callable function pointers, so do not load opcodes through uintptr_t and do
 * not retag them as data pointers.  Retag only the bytecode storage address,
 * then read the stored opcode with its real function-pointer type.
 */

#define NGX_STREAM_SCRIPT_CODE_SENTINEL_SIZE                                  \
    sizeof(ngx_stream_script_code_pt)

#define NGX_STREAM_SCRIPT_LEN_SENTINEL_SIZE                                   \
    sizeof(ngx_stream_script_len_code_pt)

#define NGX_STREAM_SCRIPT_CODE_ALIGN                                          \
    sizeof(ngx_stream_script_code_pt)


static ngx_inline ngx_int_t
ngx_stream_script_get_code(ngx_stream_script_engine_t *e,
    ngx_stream_script_code_pt *code)
{
    ngx_stream_script_code_pt  *slot;

    if (e == NULL || e->ip == NULL || code == NULL) {
        return NGX_ERROR;
    }

    slot = (ngx_stream_script_code_pt *) ngx_filc_ptr(e->ip);
    if (slot == NULL) {
        return NGX_ERROR;
    }

    *code = *slot;

    if (*code == NULL) {
        return NGX_DONE;
    }

    return NGX_OK;
}


static ngx_inline ngx_int_t
ngx_stream_script_get_len_code(ngx_stream_script_engine_t *e,
    ngx_stream_script_len_code_pt *code)
{
    ngx_stream_script_len_code_pt  *slot;

    if (e == NULL || e->ip == NULL || code == NULL) {
        return NGX_ERROR;
    }

    slot = (ngx_stream_script_len_code_pt *) ngx_filc_ptr(e->ip);
    if (slot == NULL) {
        return NGX_ERROR;
    }

    *code = *slot;

    if (*code == NULL) {
        return NGX_DONE;
    }

    return NGX_OK;
}

#else

#define NGX_STREAM_SCRIPT_CODE_SENTINEL_SIZE  sizeof(uintptr_t)
#define NGX_STREAM_SCRIPT_LEN_SENTINEL_SIZE   sizeof(uintptr_t)
#define NGX_STREAM_SCRIPT_CODE_ALIGN          sizeof(uintptr_t)

#endif


typedef struct {
    ngx_stream_script_code_pt     code;
    uintptr_t                     len;
} ngx_stream_script_copy_code_t;


typedef struct {
    ngx_stream_script_code_pt     code;
    uintptr_t                     index;
} ngx_stream_script_var_code_t;


typedef struct {
    ngx_stream_script_code_pt     code;
    uintptr_t                     n;
} ngx_stream_script_copy_capture_code_t;


typedef struct {
    ngx_stream_script_code_pt     code;
    uintptr_t                     conf_prefix;
} ngx_stream_script_full_name_code_t;


void ngx_stream_script_flush_complex_value(ngx_stream_session_t *s,
    ngx_stream_complex_value_t *val);
ngx_int_t ngx_stream_complex_value(ngx_stream_session_t *s,
    ngx_stream_complex_value_t *val, ngx_str_t *value);
size_t ngx_stream_complex_value_size(ngx_stream_session_t *s,
    ngx_stream_complex_value_t *val, size_t default_value);
ngx_int_t ngx_stream_compile_complex_value(
    ngx_stream_compile_complex_value_t *ccv);
char *ngx_stream_set_complex_value_slot(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
char *ngx_stream_set_complex_value_zero_slot(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);
char *ngx_stream_set_complex_value_size_slot(ngx_conf_t *cf, ngx_command_t *cmd,
    void *conf);


ngx_uint_t ngx_stream_script_variables_count(ngx_str_t *value);
ngx_int_t ngx_stream_script_compile(ngx_stream_script_compile_t *sc);
u_char *ngx_stream_script_run(ngx_stream_session_t *s, ngx_str_t *value,
    void *code_lengths, size_t reserved, void *code_values);
void ngx_stream_script_flush_no_cacheable_variables(ngx_stream_session_t *s,
    ngx_array_t *indices);

void *ngx_stream_script_add_code(ngx_array_t *codes, size_t size, void *code);

size_t ngx_stream_script_copy_len_code(ngx_stream_script_engine_t *e);
void ngx_stream_script_copy_code(ngx_stream_script_engine_t *e);
size_t ngx_stream_script_copy_var_len_code(ngx_stream_script_engine_t *e);
void ngx_stream_script_copy_var_code(ngx_stream_script_engine_t *e);
size_t ngx_stream_script_copy_capture_len_code(ngx_stream_script_engine_t *e);
void ngx_stream_script_copy_capture_code(ngx_stream_script_engine_t *e);

#endif /* _NGX_STREAM_SCRIPT_H_INCLUDED_ */
