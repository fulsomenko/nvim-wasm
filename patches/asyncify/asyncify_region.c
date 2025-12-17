#include <stdint.h>

// Reserved linear-memory region for Binaryen Asyncify state + stack.
// This avoids placing the asyncify data at the end of memory grown from JS,
// which can be overwritten by the program heap.
//
// Size can be overridden at compile time with -DNVIM_ASYNCIFY_STACK_SIZE=...
#ifndef NVIM_ASYNCIFY_STACK_SIZE
#define NVIM_ASYNCIFY_STACK_SIZE (64u * 1024u * 1024u)
#endif

__attribute__((aligned(8), used))
static uint32_t nvim_asyncify_data[2];

__attribute__((aligned(16), used))
static uint8_t nvim_asyncify_stack[NVIM_ASYNCIFY_STACK_SIZE];

__attribute__((export_name("nvim_asyncify_get_data_ptr")))
uint32_t nvim_asyncify_get_data_ptr(void) {
  return (uint32_t)(uintptr_t)nvim_asyncify_data;
}

__attribute__((export_name("nvim_asyncify_get_stack_start")))
uint32_t nvim_asyncify_get_stack_start(void) {
  return (uint32_t)(uintptr_t)nvim_asyncify_stack;
}

__attribute__((export_name("nvim_asyncify_get_stack_end")))
uint32_t nvim_asyncify_get_stack_end(void) {
  return (uint32_t)(uintptr_t)(nvim_asyncify_stack + NVIM_ASYNCIFY_STACK_SIZE);
}

