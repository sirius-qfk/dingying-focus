const path = require('node:path');
const { lua, lauxlib, lualib, to_luastring, to_jsstring } = require('fengari');
process.chdir(path.resolve(__dirname, '..'));
for (const file of ['tests/unit.lua', 'tests/integration.lua', 'tests/lifecycle.lua', 'tests/compatibility.lua']) {
  const L = lauxlib.luaL_newstate();
  lualib.luaL_openlibs(L);
  const result = lauxlib.luaL_dofile(L, to_luastring(file));
  if (result !== lua.LUA_OK) {
    console.error(to_jsstring(lua.lua_tostring(L, -1)));
    process.exitCode = 1;
    break;
  }
  lua.lua_close(L);
}
