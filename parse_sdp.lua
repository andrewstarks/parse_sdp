local grammar = require("lib.grammar")

local M  = {}
local mt = {}
mt.__index = mt

-- ── Helpers ───────────────────────────────────────────────────────────────────

local function split_lines(text)
  local lines = {}
  local i = 1
  while i <= #text do
    local j = text:find("\n", i, true)
    if j then
      local line = text:sub(i, j - 1)
      if line:sub(-1) == "\r" then
        line = line:sub(1, -2)
      end
      lines[#lines + 1] = line
      i = j + 1
    else
      local tail = text:sub(i)
      if tail ~= "" then
        lines[#lines + 1] = tail
      end
      break
    end
  end
  return lines
end

local function make_err(msg, line_num, col, context)
  return { message = msg, line = line_num, col = col, context = context }
end

-- Reads one required field from lines[pos], validates its type char and value.
-- parse_value(value_str) → parsed  or  nil, fail_col_in_value
-- Returns parsed on success; nil, err_table on any failure.
local function parse_required(lines, pos, type_char, parse_value)
  if pos > #lines then
    return nil, make_err(
      string.format("missing required field '%s='", type_char),
      pos, 1, ""
    )
  end
  local line = lines[pos]
  local t, v, offset = grammar.tokenize_line(line)
  if not t then
    return nil, make_err("malformed line", pos, v or 1, line)
  end
  if t ~= type_char then
    return nil, make_err(
      string.format("expected '%s=' but found '%s='", type_char, t),
      pos, 1, line
    )
  end
  local parsed, fail_col = parse_value(v)
  if not parsed then
    return nil, make_err(
      string.format("invalid value for '%s='", type_char),
      pos, offset + (fail_col or 1) - 1, line
    )
  end
  return parsed
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.parse(text, _mode)
  local lines = split_lines(text)

  local version, e = parse_required(lines, 1, "v", grammar.parse_version)
  if not version then return nil, e end

  local origin
  origin, e = parse_required(lines, 2, "o", grammar.parse_origin)
  if not origin then return nil, e end

  local session_name
  session_name, e = parse_required(lines, 3, "s", grammar.parse_session_name)
  if not session_name then return nil, e end

  local timing
  timing, e = parse_required(lines, 4, "t", grammar.parse_timing)
  if not timing then return nil, e end

  return setmetatable({
    version = version,
    origin  = origin,
    session = {
      name   = session_name,
      timing = timing,
    },
  }, mt)
end

function M.new(t)
  return setmetatable(t, mt)
end

return M
