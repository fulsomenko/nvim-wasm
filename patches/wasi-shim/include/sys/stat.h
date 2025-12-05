#pragma once

#include_next <sys/stat.h>
#include <errno.h>

static inline mode_t umask(mode_t mask)
{
  (void)mask;
  errno = ENOSYS;
  return 0;
}
