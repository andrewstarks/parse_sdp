local lpeg = require("lpeg")
local P, R, C, Cp = lpeg.P, lpeg.R, lpeg.C, lpeg.Cp

local M = {}

-- ── Primitives ────────────────────────────────────────────────────────────────

local alpha      = R("az", "AZ")
local digit      = R("09")
local line_end   = P("\r\n") + P("\n")
local value_char = 1 - line_end        -- any octet except CR or LF
local SP         = P(" ")
local token      = (P(1) - SP - line_end) ^ 1  -- non-space, non-newline

-- ── Line tokenizer ────────────────────────────────────────────────────────────

-- Matches a single SDP line: one alpha type char, '=', non-empty value,
-- then a line ending or end of string.
-- On success returns: type_char (string), value (string), byte_offset_of_value (number).
local line_pat =
  C(alpha) * P("=") * Cp() * C(value_char ^ 1) * (line_end + -P(1))

-- Best-effort partial match to locate the failure byte position when line_pat fails.
local line_partial =
      alpha * P("=") * value_char ^ 0 * Cp()
    + alpha * Cp()
    + Cp()

-- Returns type_char, value, byte_offset on success; nil, fail_pos on failure.
function M.tokenize_line(s)
  local t, offset, v = line_pat:match(s)
  if t then
    return t, v, offset
  end
  return nil, line_partial:match(s)
end

-- ── Value parsers ─────────────────────────────────────────────────────────────
-- Each returns parsed_result on success, or nil, fail_col_in_value on failure.

-- v= : exactly "0"
local version_pat = P("0") * -P(1)

function M.parse_version(s)
  if version_pat:match(s) then
    return "0"
  end
  return nil, 1
end

-- o= : <username> SP <sess-id> SP <sess-version> SP <nettype> SP <addrtype> SP <unicast-address>
local nettype  = P("IN")
local addrtype = P("IP4") + P("IP6")

local origin_pat =
  C(token) * SP *
  C(digit ^ 1) * SP *
  C(digit ^ 1) * SP *
  C(nettype) * SP *
  C(addrtype) * SP *
  C(token) *
  -P(1)

function M.parse_origin(s)
  local user, sid, sver, ntype, atype, addr = origin_pat:match(s)
  if user then
    return {
      username        = user,
      sess_id         = sid,
      sess_version    = sver,
      net_type        = ntype,
      addr_type       = atype,
      unicast_address = addr,
    }
  end
  return nil, 1
end

-- s= : any non-empty text (tokenize_line already guarantees non-empty)
function M.parse_session_name(s)
  return s
end

-- t= : <start-time> SP <stop-time>  (decimal integers)
local timing_pat = C(digit ^ 1) * SP * C(digit ^ 1) * -P(1)

function M.parse_timing(s)
  local start_s, stop_s = timing_pat:match(s)
  if start_s then
    return { start = tonumber(start_s), stop = tonumber(stop_s) }
  end
  return nil, 1
end

return M
