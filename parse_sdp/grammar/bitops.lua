-- Bitwise-op dispatcher. Lua 5.3+ has native `&` / `>>` / `<<`;
-- 5.1/5.2 do not (the operators are a parse error), so `bitops_53.lua`
-- is only ever required on 5.3+. 5.1/5.2 get a pure-Lua arithmetic
-- backend; nothing extra to install on any version.

if _VERSION == "Lua 5.1" or _VERSION == "Lua 5.2" then
  return require("parse_sdp.grammar.bitops_compat")
end
return require("parse_sdp.grammar.bitops_53")
