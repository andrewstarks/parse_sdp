-- Native-operator bitops backend. Lua 5.3+ only — the `&` / `>>` / `<<`
-- syntax is a parse error under 5.1/5.2, so this file must never be
-- required there. The dispatcher in `bitops.lua` guards that.

local M = {}

function M.band(a, b)   return a & b   end
function M.rshift(a, n) return a >> n  end
function M.lshift(a, n) return a << n  end

return M
