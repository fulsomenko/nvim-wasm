from pathlib import Path
import re

constants = Path("src/constants.c")
ct = constants.read_text()
ct = re.sub(
    r"static int luv_proto_string_to_num\(.*?return proto->p_proto;\n}",
    "static int luv_proto_string_to_num(const char* string) {\n"
    "  (void)string; return -1;\n}\n",
    ct,
    flags=re.S,
)
ct = re.sub(
    r"static const char\* luv_proto_num_to_string\(.*?return proto->p_name;\n}",
    "static const char* luv_proto_num_to_string(int num) {\n"
    "  (void)num; return NULL;\n}\n",
    ct,
    flags=re.S,
)
constants.write_text(ct)

dns = Path("src/dns.c")
dns.write_text(
    '#include "private.h"\n#include <uv.h>\n\n'
    "static int luv_getaddrinfo(lua_State* L) { return luv_error(L, UV_ENOSYS); }\n"
    "static int luv_getnameinfo(lua_State* L) { return luv_error(L, UV_ENOSYS); }\n"
    "static int luv_ip4_addr(lua_State* L) { return luv_error(L, UV_ENOSYS); }\n"
    "static int luv_ip6_addr(lua_State* L) { return luv_error(L, UV_ENOSYS); }\n"
    "static int luv_inet_ntop(lua_State* L) { return luv_error(L, UV_ENOSYS); }\n"
    "static int luv_inet_pton(lua_State* L) { return luv_error(L, UV_ENOSYS); }\n"
)

misc = Path("src/misc.c")
mt = misc.read_text()
mt = mt.replace(
    "  int uid = getuid();\n  lua_pushinteger(L, uid);\n  return 1;\n",
    "  return luv_error(L, UV_ENOSYS);\n",
)
mt = mt.replace(
    "  int gid = getgid();\n  lua_pushinteger(L, gid);\n  return 1;\n",
    "  return luv_error(L, UV_ENOSYS);\n",
)
mt = mt.replace(
    "  int uid = luaL_checkinteger(L, 1);\n"
    "  int r = setuid(uid);\n"
    "  if (-1 == r) {\n"
    "    luaL_error(L, \"Error setting UID\");\n"
    "  }\n"
    "  return 0;\n",
    "  return luv_error(L, UV_ENOSYS);\n",
)
mt = mt.replace(
    "  int gid = luaL_checkinteger(L, 1);\n"
    "  int r = setgid(gid);\n"
    "  if (-1 == r) {\n"
    "    luaL_error(L, \"Error setting GID\");\n"
    "  }\n"
    "  return 0;\n",
    "  return luv_error(L, UV_ENOSYS);\n",
)
misc.write_text(mt)
