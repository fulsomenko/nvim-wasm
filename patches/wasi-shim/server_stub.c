// WASI stub for RPC server: all operations are no-ops.
// Server/RPC functionality is not available under WASI.
#include <stdbool.h>
#include <stddef.h>

bool server_init(const char *listen_addr)
{
  (void)listen_addr;
  return true;  // Always succeed - no server needed on WASI
}

void server_teardown(void) {}

char *server_address_new(const char *name)
{
  (void)name;
  return NULL;
}

bool server_owns_pipe_address(const char *address)
{
  (void)address;
  return false;
}

int server_start(const char *addr)
{
  (void)addr;
  return 0;
}

bool server_stop(char *endpoint)
{
  (void)endpoint;
  return true;
}

char **server_address_list(size_t *size)
{
  if (size) *size = 0;
  return NULL;
}
