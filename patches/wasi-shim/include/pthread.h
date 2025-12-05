#pragma once

#include_next <pthread.h>
#include <errno.h>
#include <signal.h>

static inline int pthread_sigmask(int how, const sigset_t *set, sigset_t *oldset)
{
  (void)how;
  (void)set;
  (void)oldset;
  errno = ENOSYS;
  return -1;
}

static inline void pthread_exit(void *retval)
{
  (void)retval;
}
