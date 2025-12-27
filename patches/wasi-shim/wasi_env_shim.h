// WASI shims for nvim-wasm
// Provides minimal implementations for features missing in WASI.
#pragma once

#ifdef __wasi__

/*
 * Custom setjmp/longjmp that bypasses WASI SDK's exception handling requirement.
 * These stubs are compatible with Binaryen's asyncify transformation.
 * Must be defined BEFORE any other includes to prevent the WASI SDK setjmp.h from loading.
 */
#ifndef _WASI_SHIM_SETJMP_H
#define _WASI_SHIM_SETJMP_H

typedef long jmp_buf[16];
typedef long sigjmp_buf[16];

/* Declare as extern - implemented in setjmp_stub.c */
int setjmp(jmp_buf env) __attribute__((returns_twice));
void longjmp(jmp_buf env, int val) __attribute__((noreturn));
int sigsetjmp(sigjmp_buf env, int savemask) __attribute__((returns_twice));
void siglongjmp(sigjmp_buf env, int val) __attribute__((noreturn));

#define _setjmp(env) setjmp(env)
#define _longjmp(env, val) longjmp(env, val)

/* Prevent WASI SDK's setjmp.h from being included */
#define _SETJMP_H
#define __SETJMP_H
#define __SETJMP_H__

#endif /* _WASI_SHIM_SETJMP_H */

#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <errno.h>
#include <fcntl.h>

#if __has_include(<uv.h>)
#include <uv.h>
#else
#include <errno.h>
#define UV__ERR(x) (-(x))
#ifndef UV_EINVAL
#  define UV_EINVAL UV__ERR(EINVAL)
#endif
#ifndef UV_ENOENT
#  define UV_ENOENT UV__ERR(ENOENT)
#endif
#ifndef UV_ENOBUFS
#  define UV_ENOBUFS UV__ERR(ENOBUFS)
#endif
#ifndef UV_EIO
#  define UV_EIO UV__ERR(EIO)
#endif
#endif

static inline int nvim_wasi_uv_os_getenv(const char *name, char *buffer, size_t *size)
{
  if (!name || !size) {
    return UV_EINVAL;
  }
  const char *val = getenv(name);
  if (!val) {
    return UV_ENOENT;
  }
  size_t len = strlen(val) + 1;  // include NUL
  if (buffer == NULL || *size < len) {
    *size = len;
    return UV_ENOBUFS;
  }
  memcpy(buffer, val, len);
  *size = len;
  return 0;
}

static inline int nvim_wasi_uv_os_setenv(const char *name, const char *value)
{
  if (!name || !value) {
    return UV_EINVAL;
  }
  // setenv returns 0 on success, nonzero on failure.
  return setenv(name, value, 1) == 0 ? 0 : UV_EIO;
}

static inline int nvim_wasi_uv_os_unsetenv(const char *name)
{
  if (!name) {
    return UV_EINVAL;
  }
  return unsetenv(name) == 0 ? 0 : UV_EIO;
}

#define uv_os_getenv nvim_wasi_uv_os_getenv
#define uv_os_setenv nvim_wasi_uv_os_setenv
#define uv_os_unsetenv nvim_wasi_uv_os_unsetenv

// WASI libc lacks usable dup/dup2/dup3/fcntl(F_DUPFD*) support. Neovim's
// embedded-mode startup duplicates stdio; without a working dup the channel
// gets broken. Provide no-op shims that keep the original fds alive instead of
// failing with ENOSYS.
static inline int nvim_wasi_dup(int fd)
{
  return fd >= 0 ? fd : -1;
}

static inline int nvim_wasi_dup2(int oldfd, int newfd)
{
  // Keep stdio stable; otherwise just return target.
  (void)oldfd;
  return newfd < 0 ? -1 : newfd;
}

static inline int nvim_wasi_dup3(int oldfd, int newfd, int flags)
{
  (void)flags;
  return nvim_wasi_dup2(oldfd, newfd);
}

static inline int nvim_wasi_fcntl(int fd, int cmd, ...)
{
  va_list ap;
  switch (cmd) {
  case F_DUPFD:
#if defined(F_DUPFD_CLOEXEC) && F_DUPFD_CLOEXEC != F_DUPFD
  case F_DUPFD_CLOEXEC:
#endif
  {
    va_start(ap, cmd);
    int minfd = va_arg(ap, int);
    va_end(ap);
    // Keep stdio fds stable; otherwise just use minfd.
    if (fd >= 0 && fd <= 2) {
      return fd;
    }
    return minfd;
  }
  case F_GETFD:
  case F_GETFL:
    return 0;
  case F_SETFD:
  case F_SETFL:
    va_start(ap, cmd);
    (void)va_arg(ap, int);
    va_end(ap);
    return 0;
  default:
    errno = ENOSYS;
    return -1;
  }
}

#undef dup
#undef dup2
#undef dup3
#undef fcntl

#define dup(fd) nvim_wasi_dup(fd)
#define dup2(oldfd, newfd) nvim_wasi_dup2((oldfd), (newfd))
#define dup3(oldfd, newfd, flags) nvim_wasi_dup3((oldfd), (newfd), (flags))
#define fcntl(fd, cmd, ...) nvim_wasi_fcntl((fd), (cmd), ##__VA_ARGS__)

#endif  // __wasi__
