#pragma once

#include_next <fcntl.h>
#include <errno.h>
#include <stdarg.h>
#include <unistd.h>

#ifndef F_DUPFD
#  define F_DUPFD 0
#endif

#ifndef F_DUPFD_CLOEXEC
#  define F_DUPFD_CLOEXEC F_DUPFD
#endif

#ifdef fcntl
#  undef fcntl
#endif

static inline int wasi_shim_fcntl(int fd, int cmd, ...)
{
  (void)fd;
  (void)cmd;
  errno = ENOSYS;
  return -1;
}

#define fcntl wasi_shim_fcntl
