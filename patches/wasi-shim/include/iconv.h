#ifndef WASI_SHIM_ICONV_H
#define WASI_SHIM_ICONV_H
#include <stddef.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef void* iconv_t;

static inline iconv_t iconv_open(const char* tocode, const char* fromcode) {
  (void)tocode; (void)fromcode; return (iconv_t)-1;
}

static inline size_t iconv(iconv_t cd, char** inbuf, size_t* inbytesleft,
                            char** outbuf, size_t* outbytesleft) {
  (void)cd; (void)inbuf; (void)inbytesleft; (void)outbuf; (void)outbytesleft;
  return (size_t)-1;
}

static inline int iconv_close(iconv_t cd) {
  (void)cd; return -1;
}

#ifdef __cplusplus
}
#endif
#endif
