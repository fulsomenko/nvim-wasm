// Stub implementations for env:: module imports that WASI doesn't provide
// This file is compiled separately (not via cmake target_sources) to avoid
// header conflicts with uv.h and time.h
//
// These functions are imported as env::* by the WASM module and need to be
// provided by the host or compiled into the binary.

#include <stdint.h>
#include <stddef.h>

// clock() - not measurable in WASI
// Signature from time.h: clock_t clock(void)
// clock_t is typically long on wasm32
long clock(void) {
    return 0;
}

// libuv UTF16/WTF8 conversion functions
// These are declared in uv.h with UV_EXTERN which creates imports

// size_t uv_utf16_length_as_wtf8(const uint16_t* utf16, ssize_t utf16_len)
size_t uv_utf16_length_as_wtf8(const uint16_t* utf16, long utf16_len) {
    (void)utf16;
    (void)utf16_len;
    return 0;
}

// int uv_utf16_to_wtf8(const uint16_t* utf16, ssize_t utf16_len, char** wtf8_ptr, size_t* wtf8_len_ptr)
int uv_utf16_to_wtf8(const uint16_t* utf16, long utf16_len, char** wtf8_ptr, size_t* wtf8_len_ptr) {
    (void)utf16;
    (void)utf16_len;
    (void)wtf8_ptr;
    (void)wtf8_len_ptr;
    return -38;  // UV_ENOSYS
}

// ssize_t uv_wtf8_length_as_utf16(const char* wtf8)
long uv_wtf8_length_as_utf16(const char* wtf8) {
    (void)wtf8;
    return 0;
}

// void uv_wtf8_to_utf16(const char* wtf8, uint16_t* utf16, size_t utf16_len)
void uv_wtf8_to_utf16(const char* wtf8, uint16_t* utf16, size_t utf16_len) {
    (void)wtf8;
    (void)utf16;
    (void)utf16_len;
}

// int uv_random(uv_loop_t* loop, uv_random_t* req, void* buf, size_t buflen,
//               unsigned int flags, uv_random_cb cb)
// Use void* for opaque pointer types
int uv_random(void* loop, void* req, void* buf, size_t buflen, unsigned flags, void* cb) {
    (void)loop;
    (void)req;
    (void)buf;
    (void)buflen;
    (void)flags;
    (void)cb;
    return -38;  // UV_ENOSYS
}
