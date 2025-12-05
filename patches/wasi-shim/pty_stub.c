// WASI stub for PTY support: returns ENOSYS so terminal features are skipped.
#include <errno.h>
#include <sys/types.h>
#include <termios.h>
#include <uv.h>

#include "nvim/event/loop.h"
#include "nvim/event/proc.h"
#include "nvim/os/pty_proc.h"

DLLEXPORT pid_t vim_forkpty(int *amaster, char *name, struct termios *termp, struct winsize *winp)
{
  (void)amaster;
  (void)name;
  (void)termp;
  (void)winp;
  errno = ENOSYS;
  return -1;
}

int pty_proc_spawn(PtyProc *ptyproc)
{
  (void)ptyproc;
  return UV_ENOSYS;
}

const char *pty_proc_tty_name(PtyProc *ptyproc)
{
  (void)ptyproc;
  return NULL;
}

void pty_proc_resize(PtyProc *ptyproc, uint16_t width, uint16_t height)
{
  ptyproc->width = width;
  ptyproc->height = height;
}

void pty_proc_close(PtyProc *ptyproc)
{
  (void)ptyproc;
}

void pty_proc_close_master(PtyProc *ptyproc)
{
  (void)ptyproc;
}

void pty_proc_teardown(Loop *loop)
{
  (void)loop;
}

PtyProc pty_proc_init(Loop *loop, void *data)
{
  PtyProc rv = { 0 };
  rv.proc.type = kProcTypePty;
  rv.proc.loop = loop;
  rv.proc.data = data;
  rv.width = 80;
  rv.height = 24;
  return rv;
}
