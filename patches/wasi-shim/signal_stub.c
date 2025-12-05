// WASI stub for signal handling: all operations are no-ops.
#include "nvim/os/signal.h"

void signal_init(void) {}
void signal_teardown(void) {}
void signal_start(void) {}
void signal_stop(void) {}
void signal_reject_deadly(void) {}
void signal_accept_deadly(void) {}
