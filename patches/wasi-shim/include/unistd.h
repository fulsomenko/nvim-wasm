#pragma once

#include_next <unistd.h>
#include <errno.h>

// WASI libc leaves these undefined; provide harmless stubs so code can build.
static inline int dup(int oldfd)
{
  (void)oldfd;
  errno = ENOSYS;
  return -1;
}

static inline int dup2(int oldfd, int newfd)
{
  (void)oldfd;
  (void)newfd;
  errno = ENOSYS;
  return -1;
}

static inline int dup3(int oldfd, int newfd, int flags)
{
  (void)oldfd;
  (void)newfd;
  (void)flags;
  errno = ENOSYS;
  return -1;
}
