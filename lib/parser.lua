local grammar = require("lib.grammar")
local errors  = require("lib.errors")
local st2110  = require("lib.st2110")
local ipmx    = require("lib.ipmx")

local M = {}

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

-- Reads one required field from lines[pos], validates its type char and value.
-- parse_value(value_str) → parsed  or  nil, fail_col_in_value
-- Returns parsed on success; nil, err_table on any failure.
local function parse_required(lines, pos, type_char, parse_value)
  if pos > #lines then
    return nil, errors.new(
      string.format("missing required field '%s='", type_char),
      { line = pos, col = 1, context = "", code = "MISSING_FIELD" }
    )
  end
  local line = lines[pos]
  local t, v, offset = grammar.tokenize_line(line)
  if not t then
    return nil, errors.new("malformed line",
      { line = pos, col = v or 1, context = line, code = "MALFORMED_LINE" })
  end
  if t ~= type_char then
    return nil, errors.new(
      string.format("expected '%s=' but found '%s='", type_char, t),
      { line = pos, col = 1, context = line, code = "WRONG_ORDER" }
    )
  end
  local parsed, fail_col = parse_value(v)
  if not parsed then
    return nil, errors.new(
      string.format("invalid value for '%s='", type_char),
      { line = pos, col = offset + (fail_col or 1) - 1, context = line, code = "INVALID_VALUE" }
    )
  end
  return parsed
end

local function peek_type(lines, pos)
  local t = grammar.tokenize_line(lines[pos])
  return t
end

function M.parse(text, mode)
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

  local info
  if pos <= n and peek_type(lines, pos) == "i" then
    info, e = parse_required(lines, pos, "i", grammar.parse_info)
    if not info then return nil, e end
    pos = pos + 1
  end

  local uri
  if pos <= n and peek_type(lines, pos) == "u" then
    uri, e = parse_required(lines, pos, "u", grammar.parse_uri)
    if not uri then return nil, e end
    pos = pos + 1
  end

  local emails = {}
  while pos <= n and peek_type(lines, pos) == "e" do
    local v
    v, e = parse_required(lines, pos, "e", grammar.parse_email)
    if not v then return nil, e end
    emails[#emails + 1] = v
    pos = pos + 1
  end

  local phones = {}
  while pos <= n and peek_type(lines, pos) == "p" do
    local v
    v, e = parse_required(lines, pos, "p", grammar.parse_phone)
    if not v then return nil, e end
    phones[#phones + 1] = v
    pos = pos + 1
  end

  local connection
  if pos <= n and peek_type(lines, pos) == "c" then
    connection, e = parse_required(lines, pos, "c", grammar.parse_connection)
    if not connection then return nil, e end
    pos = pos + 1
  end

  local bandwidths = {}
  while pos <= n and peek_type(lines, pos) == "b" do
    local v
    v, e = parse_required(lines, pos, "b", grammar.parse_bandwidth)
    if not v then return nil, e end
    bandwidths[#bandwidths + 1] = v
    pos = pos + 1
  end

  local timing
  timing, e = parse_required(lines, pos, "t", grammar.parse_timing)
  if not timing then return nil, e end
  pos = pos + 1

  local attributes = {}
  while pos <= n and peek_type(lines, pos) == "a" do
    local v
    v, e = parse_required(lines, pos, "a", grammar.parse_attribute)
    if not v then return nil, e end
    attributes[#attributes + 1] = v
    pos = pos + 1
  end

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

  if pos <= n then
    local line = lines[pos]
    local t = peek_type(lines, pos)
    if t then
      return nil, errors.new(
        string.format("unexpected field '%s=' after all SDP fields", t),
        { line = pos, col = 1, context = line, code = "WRONG_ORDER" }
      )
    else
      return nil, errors.new(
        "unexpected content at end of SDP",
        { line = pos, col = 1, context = line, code = "MALFORMED_LINE" }
      )
    end
  end

  local doc = {
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
  }

  if mode == "st2110" then
    local ok, ve = st2110.st2110(doc)
    if not ok then return nil, ve end
  elseif mode == "ipmx" then
    local ok, ve = ipmx.ipmx(doc)
    if not ok then return nil, ve end
  end

  return doc
end

return M
