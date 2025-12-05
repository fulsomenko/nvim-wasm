#ifndef WASI_SHIM_NETDB_H
#define WASI_SHIM_NETDB_H

#include <sys/socket.h>
#include <sys/types.h>

struct protoent {
  char *p_name;
  char **p_aliases;
  int p_proto;
};

struct addrinfo {
  int ai_flags;
  int ai_family;
  int ai_socktype;
  int ai_protocol;
  socklen_t ai_addrlen;
  struct sockaddr *ai_addr;
  char *ai_canonname;
  struct addrinfo *ai_next;
};

#define EAI_FAIL    -1
#define EAI_MEMORY  -2
#define EAI_NONAME  -3

#ifndef AI_PASSIVE
#define AI_PASSIVE      0x0001
#endif
#ifndef AI_CANONNAME
#define AI_CANONNAME    0x0002
#endif
#ifndef AI_NUMERICHOST
#define AI_NUMERICHOST  0x0004
#endif
#ifndef AI_NUMERICSERV
#define AI_NUMERICSERV  0x0400
#endif
#ifndef AI_ADDRCONFIG
#define AI_ADDRCONFIG   0x0020
#endif

static inline void freeaddrinfo(struct addrinfo *res) {
  (void)res;
}

static inline const char *gai_strerror(int ecode) {
  (void)ecode;
  return "wasi shim: getaddrinfo unsupported";
}

static inline int getaddrinfo(const char *node,
                              const char *service,
                              const struct addrinfo *hints,
                              struct addrinfo **res) {
  (void)node;
  (void)service;
  (void)hints;
  if (res) *res = NULL;
  return EAI_NONAME;
}

static inline struct protoent *getprotobyname(const char *name) {
  (void)name;
  return (struct protoent *)0;
}

static inline struct protoent *getprotobynumber(int num) {
  (void)num;
  return (struct protoent *)0;
}

#endif /* WASI_SHIM_NETDB_H */
