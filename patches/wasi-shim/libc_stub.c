// WASI libc implementations for functions not provided by WASI preview1
// These are the correct implementations for a single-process sandboxed environment

// Note: This file is compiled via cmake target_sources and may include uv.h
// So we need to be careful about function signatures

#include <errno.h>
#include <stdint.h>
#include <stddef.h>

// File locking - no-op in single-process environment
int flock(int fd, int operation) {
    (void)fd;
    (void)operation;
    return 0;
}

// Process ID - single process always has ID 1
int getpid(void) {
    return 1;
}

// Shell command - no shell in WASI sandbox
int system(const char* command) {
    (void)command;
    return -1;
}

// Temp filename - no temp filesystem
char* tmpnam(char* s) {
    (void)s;
    return 0;
}
