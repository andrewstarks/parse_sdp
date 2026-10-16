/* web/wasm/bridge.c — C shim between Emscripten and bridge.lua.
 *
 * One lazily created lua_State. sdp_request(json) hands the request to
 * bridge.handle and returns the JSON response in a C-owned buffer that
 * stays valid until the next call. Every failure path yields a JSON
 * error object rather than aborting, so the host never sees a trap.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <emscripten.h>
#include "lua.h"
#include "lauxlib.h"
#include "lualib.h"

int luaopen_lpeg(lua_State *L);

static lua_State *L;
static char      *result;
static int        handle_ref = LUA_NOREF;

static const char *fail(const char *msg) {
  /* Escape just enough to keep the message a valid JSON string. */
  const char *prefix = "{\"ok\":false,\"error\":{\"message\":\"";
  const char *suffix = "\",\"code\":\"INVALID_VALUE\"}}";
  size_t n = strlen(prefix) + strlen(suffix) + 2 * strlen(msg) + 1;
  char *out = malloc(n), *p;
  if (!out) return "{\"ok\":false,\"error\":{\"message\":\"out of memory\",\"code\":\"INVALID_VALUE\"}}";
  p = out + sprintf(out, "%s", prefix);
  for (; *msg; msg++) {
    unsigned char c = (unsigned char)*msg;
    if (c == '"' || c == '\\') { *p++ = '\\'; *p++ = c; }
    else if (c < 0x20)         { p += sprintf(p, "\\u%04x", c); }
    else                       { *p++ = c; }
  }
  strcpy(p, suffix);
  free(result);
  result = out;
  return result;
}

/* Returns NULL on success, else an error message left on the Lua stack top. */
static const char *boot(void) {
  if (L) return NULL;
  L = luaL_newstate();
  if (!L) return "cannot create Lua state";
  luaL_openlibs(L);

  lua_getglobal(L, "package");
  lua_getfield(L, -1, "preload");
  lua_pushcfunction(L, luaopen_lpeg);
  lua_setfield(L, -2, "lpeg");
  lua_pop(L, 1);
  lua_pushliteral(L, "/lua/?.lua;/lua/?/init.lua");
  lua_setfield(L, -2, "path");
  lua_pop(L, 1);

  lua_getglobal(L, "require");
  lua_pushliteral(L, "bridge");
  if (lua_pcall(L, 1, 1, 0) != LUA_OK) return lua_tostring(L, -1);
  lua_getfield(L, -1, "handle");
  if (!lua_isfunction(L, -1)) return "bridge.handle is not a function";
  handle_ref = luaL_ref(L, LUA_REGISTRYINDEX);
  lua_pop(L, 1);
  return NULL;
}

EMSCRIPTEN_KEEPALIVE
const char *sdp_request(const char *json) {
  const char *err = boot();
  if (err) {
    const char *out = fail(err);
    if (L) { lua_close(L); L = NULL; handle_ref = LUA_NOREF; }
    return out;
  }
  lua_rawgeti(L, LUA_REGISTRYINDEX, handle_ref);
  lua_pushstring(L, json ? json : "");
  if (lua_pcall(L, 1, 1, 0) != LUA_OK) {
    const char *out = fail(lua_tostring(L, -1));
    lua_pop(L, 1);
    return out;
  }
  size_t len;
  const char *s = lua_tolstring(L, -1, &len);
  if (!s) { lua_pop(L, 1); return fail("bridge.handle did not return a string"); }
  free(result);
  result = malloc(len + 1);
  if (!result) { lua_pop(L, 1); return fail("out of memory"); }
  memcpy(result, s, len + 1);
  lua_pop(L, 1);
  return result;
}
