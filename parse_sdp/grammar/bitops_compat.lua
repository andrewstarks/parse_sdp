-- Pure-Lua bitops backend for Lua 5.1/5.2 (where native `&` / `>>`
-- syntax doesn't parse). Operands at our call sites are bounded — at
-- most a 32-bit IPv4 int or a 16-bit IPv6 group — so an arithmetic
-- decomposition stays inside Lua 5.1's double-precision mantissa.

local floor = math.floor

local M = {}

function M.band(a, b)
  local r, p = 0, 1
  while a > 0 and b > 0 do
    local ax, bx = a % 2, b % 2
    if ax == 1 and bx == 1 then r = r + p end
    a, b, p = (a - ax) / 2, (b - bx) / 2, p * 2
  end
  return r
end

function M.rshift(a, n) return floor(a / 2 ^ n) end
function M.lshift(a, n) return a * 2 ^ n end

return M
