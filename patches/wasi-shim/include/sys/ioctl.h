#pragma once

#include <errno.h>
#include <stdarg.h>
#include <stdint.h>

struct winsize {
  unsigned short ws_row;
  unsigned short ws_col;
  unsigned short ws_xpixel;
  unsigned short ws_ypixel;
};

#ifndef TIOCSWINSZ
#  define TIOCSWINSZ 0
#endif
#ifndef TIOCSCTTY
#  define TIOCSCTTY 0
#endif
#ifndef I_PUSH
#  define I_PUSH 0
#endif

static inline int ioctl(int fd, unsigned long req, ...)
{
  (void)fd;
  (void)req;
  errno = ENOSYS;
  return -1;
}
