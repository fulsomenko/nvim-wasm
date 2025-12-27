/*
 * Custom setjmp.h for nvim-wasm that bypasses WASI SDK's exception handling requirement.
 *
 * This provides minimal setjmp/longjmp stubs that can be transformed by Binaryen's
 * asyncify pass for stack rewinding, without requiring WASM exception handling instructions.
 */

#ifndef WASI_SHIM_SETJMP_H
#define WASI_SHIM_SETJMP_H

#ifdef __cplusplus
extern "C" {
#endif

/* jmp_buf is an opaque buffer to store execution context */
typedef long jmp_buf[16];

/*
 * setjmp: Save the current execution context.
 * Returns 0 when called directly, non-zero when returning via longjmp.
 *
 * Note: This is a stub that will be transformed by asyncify.
 */
int setjmp(jmp_buf env);

/*
 * longjmp: Restore execution context saved by setjmp.
 * Does not return; transfers control to the corresponding setjmp call.
 *
 * Note: This is a stub that will be transformed by asyncify.
 */
__attribute__((noreturn))
void longjmp(jmp_buf env, int val);

/* sigsetjmp/siglongjmp - signal-aware versions (same behavior in WASI) */
typedef long sigjmp_buf[16];

int sigsetjmp(sigjmp_buf env, int savemask);

__attribute__((noreturn))
void siglongjmp(sigjmp_buf env, int val);

/* _setjmp/_longjmp - BSD versions */
#define _setjmp(env) setjmp(env)
#define _longjmp(env, val) longjmp(env, val)

#ifdef __cplusplus
}
#endif

#endif /* WASI_SHIM_SETJMP_H */
