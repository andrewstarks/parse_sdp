local grammar   = require("lib.grammar")
local validate  = require("lib.validate")
local serialize = require("lib.serialize")

local M  = {}
local mt = {}
mt.__index = mt

function mt:validate(mode)
  mode = mode or "sdp"
  if mode == "sdp" then
    return validate.sdp(self)
  end
  return nil, { message = "unknown mode: " .. tostring(mode), line = 0, col = 0, context = "" }
end

function mt:is_sdp()
  return validate.sdp(self) == true
end

function mt:serialize()
  return serialize.serialize(self)
end

function mt:is_st2110()
  return false  -- implemented in M8
end

function mt:is_ipmx()
  return false  -- implemented in M9
end

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

local function peek_type(lines, pos)
  local t = grammar.tokenize_line(lines[pos])
  return t
end

-- ── Public API ────────────────────────────────────────────────────────────────

function M.parse(text, _mode)
  local lines = split_lines(text)
  local n     = #lines
  local pos   = 1
  local e

  local version
  version, e = parse_required(lines, pos, "v", grammar.parse_version)
  if not version then return nil, e end
  pos = pos + 1

  local origin
  origin, e = parse_required(lines, pos, "o", grammar.parse_origin)
  if not origin then return nil, e end
  pos = pos + 1

  local session_name
  session_name, e = parse_required(lines, pos, "s", grammar.parse_session_name)
  if not session_name then return nil, e end
  pos = pos + 1

  -- optional i=
  local info
  if pos <= n and peek_type(lines, pos) == "i" then
    info, e = parse_required(lines, pos, "i", grammar.parse_info)
    if not info then return nil, e end
    pos = pos + 1
  end

  -- optional u=
  local uri
  if pos <= n and peek_type(lines, pos) == "u" then
    uri, e = parse_required(lines, pos, "u", grammar.parse_uri)
    if not uri then return nil, e end
    pos = pos + 1
  end

  -- zero or more e=
  local emails = {}
  while pos <= n and peek_type(lines, pos) == "e" do
    local v
    v, e = parse_required(lines, pos, "e", grammar.parse_email)
    if not v then return nil, e end
    emails[#emails + 1] = v
    pos = pos + 1
  end

  -- zero or more p=
  local phones = {}
  while pos <= n and peek_type(lines, pos) == "p" do
    local v
    v, e = parse_required(lines, pos, "p", grammar.parse_phone)
    if not v then return nil, e end
    phones[#phones + 1] = v
    pos = pos + 1
  end

  -- optional c=
  local connection
  if pos <= n and peek_type(lines, pos) == "c" then
    connection, e = parse_required(lines, pos, "c", grammar.parse_connection)
    if not connection then return nil, e end
    pos = pos + 1
  end

  -- zero or more b=
  local bandwidths = {}
  while pos <= n and peek_type(lines, pos) == "b" do
    local v
    v, e = parse_required(lines, pos, "b", grammar.parse_bandwidth)
    if not v then return nil, e end
    bandwidths[#bandwidths + 1] = v
    pos = pos + 1
  end

  -- required t=
  local timing
  timing, e = parse_required(lines, pos, "t", grammar.parse_timing)
  if not timing then return nil, e end
  pos = pos + 1

  -- zero or more a=
  local attributes = {}
  while pos <= n and peek_type(lines, pos) == "a" do
    local v
    v, e = parse_required(lines, pos, "a", grammar.parse_attribute)
    if not v then return nil, e end
    attributes[#attributes + 1] = v
    pos = pos + 1
  end

  -- zero or more m= blocks, each with optional per-media fields
  local media = {}
  while pos <= n and peek_type(lines, pos) == "m" do
    local m
    m, e = parse_required(lines, pos, "m", grammar.parse_media)
    if not m then return nil, e end
    pos = pos + 1

    if pos <= n and peek_type(lines, pos) == "i" then
      m.info, e = parse_required(lines, pos, "i", grammar.parse_info)
      if not m.info then return nil, e end
      pos = pos + 1
    end

    if pos <= n and peek_type(lines, pos) == "c" then
      m.connection, e = parse_required(lines, pos, "c", grammar.parse_connection)
      if not m.connection then return nil, e end
      pos = pos + 1
    end

    m.bandwidths = {}
    while pos <= n and peek_type(lines, pos) == "b" do
      local v
      v, e = parse_required(lines, pos, "b", grammar.parse_bandwidth)
      if not v then return nil, e end
      m.bandwidths[#m.bandwidths + 1] = v
      pos = pos + 1
    end

    m.attributes = {}
    while pos <= n and peek_type(lines, pos) == "a" do
      local v
      v, e = parse_required(lines, pos, "a", grammar.parse_attribute)
      if not v then return nil, e end
      m.attributes[#m.attributes + 1] = v
      pos = pos + 1
    end

    media[#media + 1] = m
  end

  return setmetatable({
    version = version,
    origin  = origin,
    session = {
      name        = session_name,
      info        = info,
      uri         = uri,
      emails      = emails,
      phones      = phones,
      connection  = connection,
      bandwidths  = bandwidths,
      timing      = timing,
      attributes  = attributes,
    },
    media = media,
  }, mt)
end

function M.new(t)
  return setmetatable(t, mt)
end

return M
