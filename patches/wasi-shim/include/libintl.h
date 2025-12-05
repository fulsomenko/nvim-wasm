#ifndef WASI_SHIM_LIBINTL_H
#define WASI_SHIM_LIBINTL_H

static inline const char* gettext(const char* msg) { return msg; }
static inline const char* ngettext(const char* msgid1, const char* msgid2, unsigned long n) {
  (void)msgid2; (void)n; return msgid1;
}
static inline int bindtextdomain(const char* domainname, const char* dirname) {
  (void)domainname; (void)dirname; return 0;
}
static inline int textdomain(const char* domainname) {
  (void)domainname; return 0;
}

#endif
