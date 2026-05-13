local lpeg = require("lpeg")
local P, R, C, Cp = lpeg.P, lpeg.R, lpeg.C, lpeg.Cp

local M = {}

local alpha      = R("az", "AZ")
local line_end   = P("\r\n") + P("\n")
local value_char = 1 - line_end  -- any octet except CR or LF

-- Matches a single SDP line: one alpha type char, '=', non-empty value,
-- then a line ending or end of string.
-- On success returns: type_char (string), value (string), byte_offset_of_value (number).
local line_pat =
  C(alpha) * P("=") * Cp() * C(value_char ^ 1) * (line_end + -P(1))

-- Best-effort partial match to locate the failure byte position when line_pat fails.
local partial =
      alpha * P("=") * value_char ^ 0 * Cp()
    + alpha * Cp()
    + Cp()

-- Returns type_char, value, byte_offset on success; nil, fail_pos on failure.
function M.tokenize_line(s)
  local t, offset, v = line_pat:match(s)
  if t then
    return t, v, offset
  end
  return nil, partial:match(s)
end

return M
