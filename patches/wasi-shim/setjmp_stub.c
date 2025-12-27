/*
 * Stub implementations of setjmp/longjmp for asyncify transformation.
 *
 * These are minimal implementations that will be transformed by Binaryen's
 * asyncify pass to support stack rewinding without WASM exception handling.
 */

#include "include/setjmp.h"
#include <stdlib.h>

/*
 * Simple setjmp implementation.
 * In the asyncify-transformed binary, this will save the stack state.
 * For now, just return 0 (normal path).
 */
int setjmp(jmp_buf env) {
    (void)env;
    return 0;
}

/*
 * Simple longjmp implementation.
 * In the asyncify-transformed binary, this will restore the stack state.
 * For now, just abort (should never reach here after asyncify transform).
 */
void longjmp(jmp_buf env, int val) {
    (void)env;
    (void)val;
    /* This should be transformed by asyncify. If we get here, something is wrong. */
    __builtin_trap();
}

int sigsetjmp(sigjmp_buf env, int savemask) {
    (void)savemask;
    return setjmp(env);
}

void siglongjmp(sigjmp_buf env, int val) {
    longjmp(env, val);
}
