#!/usr/bin/env lua
--- parse_sdp — RFC 4566 / ST 2110 / IPMX SDP parser, validator, and serializer.
-- Single-file library and CLI executable.  `require("parse_sdp")` loads the
-- library; running it directly activates the argparse CLI.
-- @module parse_sdp

-- ── External dependencies ─────────────────────────────────────────────────────
local lpeg   = require("lpeg")
local dkjson = require("dkjson")
local P, R, S, V, C, Cp, Ct = lpeg.P, lpeg.R, lpeg.S, lpeg.V, lpeg.C, lpeg.Cp, lpeg.Ct

-- ── Errors ────────────────────────────────────────────────────────────────────
local errors = {}

--- Build a structured error table.
-- @param msg string   Human-readable description of the error.
-- @param opts table   Optional fields: code, line, col, context, field_path, spec_ref.
--                     code defaults to "MISSING_FIELD".
-- @return table  Error table with message, code, line, col, context, field_path, spec_ref.
function errors.new(msg, opts)
  local o = opts or {}
  return {
    message    = msg,
    line       = o.line    or 0,
    col        = o.col     or 0,
    context    = o.context or "",
    code       = o.code    or "MISSING_FIELD",
    field_path = o.field_path,
    spec_ref   = o.spec_ref,
  }
end

--- Format an error table into a human-readable multi-line string.
-- Produces `error: [CODE] message`, a location arrow, context line with caret,
-- and an optional spec note — suitable for writing directly to stderr.
-- @param err table   Error table as returned by errors.new, or nil.
-- @return string  Formatted error text.
function errors.format(err)
  if not err then return "error: unknown" end
  local code_part = err.code and ("[" .. err.code .. "] ") or ""
  local out = { "error: " .. code_part .. (err.message or "unknown error") }
  if err.field_path and err.field_path ~= "" then
    out[#out + 1] = " --> field: " .. err.field_path
  elseif err.line and err.line > 0 then
    out[#out + 1] = string.format(" --> line %d, col %d", err.line, err.col or 1)
    if err.context and err.context ~= "" then
      local col = err.col or 1
      out[#out + 1] = "  |"
      out[#out + 1] = string.format("%2d | %s", err.line, err.context)
      out[#out + 1] = "   | " .. string.rep(" ", col - 1) .. "^"
    end
  end
  if err.spec_ref and err.spec_ref ~= "" then
    out[#out + 1] = "  = note: required by " .. err.spec_ref
  end
  return table.concat(out, "\n")
end

-- ── Util ──────────────────────────────────────────────────────────────────────
local util = {}

--- Find the first attribute in a list whose name matches.
-- @param attrs table   Array of attribute tables ({name[, value]}).
-- @param name string   Attribute name to search for.
-- @return table|nil  First matching attribute table, or nil if not found.
function util.find_attr(attrs, name)
  for _, a in ipairs(attrs or {}) do
    if a.name == name then return a end
  end
end

local find_attr = util.find_attr

-- ── Grammar ───────────────────────────────────────────────────────────────────
local grammar = {}

local alpha      = R("az", "AZ")
local digit      = R("09")
local line_end   = P("\r\n") + P("\n")
local value_char = 1 - line_end
local SP         = P(" ")
local token      = (P(1) - SP - line_end) ^ 1

-- Matches one SDP line: alpha type char, '=', non-empty value, then line end or EOS.
-- Capture order: type_char (C), value_start_offset (Cp), value (C).
local line_pat =
  C(alpha) * P("=") * Cp() * C(value_char ^ 1) * (line_end + -P(1))

-- Best-effort partial match to find failure byte position when line_pat fails.
local line_partial =
      alpha * P("=") * value_char ^ 0 * Cp()
    + alpha * Cp()
    + Cp()

--- Parse one SDP line into its type char, value, and value byte offset.
-- @param s string  Raw line text, with or without trailing CRLF or LF.
-- @return string, string, number  type_char, value, byte_offset_of_value on success.
-- @return nil, number  nil + failure byte position on malformed input.
function grammar.tokenize_line(s)
  local t, offset, v = line_pat:match(s)
  if t then return t, v, offset end
  return nil, line_partial:match(s)
end

local version_pat = P("0") * -P(1)

--- Parse a v= field value; only "0" is valid per RFC 4566.
-- @param s string  Field value string.
-- @return string  "0" on success.
-- @return nil, number  nil + failure column on invalid value.
function grammar.parse_version(s)
  if version_pat:match(s) then return "0" end
  return nil, 1
end

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

--- Parse an o= field value into an origin table.
-- @param s string  Field value string.
-- @return table   {username, sess_id, sess_version, net_type, addr_type, unicast_address} on success.
-- @return nil, number  nil + failure column on invalid value.
function grammar.parse_origin(s)
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

function grammar.parse_session_name(s) return s end
function grammar.parse_info(s)         return s end
function grammar.parse_uri(s)          return s end
function grammar.parse_email(s)        return s end
function grammar.parse_phone(s)        return s end

local timing_pat = C(digit ^ 1) * SP * C(digit ^ 1) * -P(1)

--- Parse a t= field value into a timing table.
-- @param s string  Field value string (e.g. "0 0" or two NTP timestamps).
-- @return table   {start=number, stop=number} on success.
-- @return nil, number  nil + failure column on invalid value.
function grammar.parse_timing(s)
  local start_s, stop_s = timing_pat:match(s)
  if start_s then
    return { start = tonumber(start_s), stop = tonumber(stop_s) }
  end
  return nil, 1
end

local connection_pat = C(nettype) * SP * C(addrtype) * SP * C(token) * -P(1)

--- Parse a c= field value into a connection table.
-- @param s string  Field value string (e.g. "IN IP4 224.2.1.1").
-- @return table   {net_type, addr_type, address} on success.
-- @return nil, number  nil + failure column on invalid value.
function grammar.parse_connection(s)
  local ntype, atype, addr = connection_pat:match(s)
  if ntype then
    return { net_type = ntype, addr_type = atype, address = addr }
  end
  return nil, 1
end

local bw_bwtype = (P(1) - P(":") - SP - line_end) ^ 1
local bw_pat    = C(bw_bwtype) * P(":") * C(digit ^ 1) * -P(1)

--- Parse a b= field value into a bandwidth table.
-- @param s string  Field value string (e.g. "AS:128").
-- @return table   {type=string, value=number} on success.
-- @return nil, number  nil + failure column on invalid value.
function grammar.parse_bandwidth(s)
  local bwtype, bwval = bw_pat:match(s)
  if bwtype then
    return { type = bwtype, value = tonumber(bwval) }
  end
  return nil, 1
end

local att_field   = (P(1) - P(":") - SP - line_end) ^ 1
local attr_kv_pat = C(att_field) * P(":") * C(value_char ^ 1) * -P(1)
local attr_k_pat  = C(att_field) * -P(1)

--- Parse an a= field value into an attribute table.
-- @param s string  Field value string (e.g. "recvonly" or "rtpmap:96 H264/90000").
-- @return table   {name=string} for flag attributes; {name, value=string} for key-value attributes.
-- @return nil, number  nil + failure column on invalid value.
function grammar.parse_attribute(s)
  local name, val = attr_kv_pat:match(s)
  if name then return { name = name, value = val } end
  local flag = attr_k_pat:match(s)
  if flag then return { name = flag } end
  return nil, 1
end

-- port_field captures the port token whole (e.g. "49170" or "49170/2"); split below.
local media_pat =
  C(token) * SP *
  C(token) * SP *
  C(token) * SP *
  Ct(C(token) * (SP * C(token)) ^ 0) *
  -P(1)

--- Parse an m= field value into a media table.
-- @param s string  Field value string (e.g. "video 49170 RTP/AVP 96 97").
-- @return table   {media, port=number, port_count=number|nil, proto, fmts=array} on success.
-- @return nil, number  nil + failure column on invalid value.
function grammar.parse_media(s)
  local mtype, port_field, proto, fmts = media_pat:match(s)
  if not mtype then return nil, 1 end
  local port_str, count_str = port_field:match("^(%d+)/(%d+)$")
  if not port_str then port_str = port_field:match("^(%d+)$") end
  if not port_str then return nil, 1 end
  return {
    media      = mtype,
    port       = tonumber(port_str),
    port_count = count_str and tonumber(count_str) or nil,
    proto      = proto,
    fmts       = fmts,
  }
end

-- ── Validate ──────────────────────────────────────────────────────────────────
local validate = {}

--- Validate an SDP document table against RFC 4566 structural requirements.
-- Checks version, all origin fields, session name, timing, and each media block's
-- required fields (media type, port, proto, fmts).
-- @param doc table  SDP document table.
-- @return true  on success.
-- @return nil, err  on failure; err is an error table from errors.new.
function validate.sdp(doc)
  if type(doc) ~= "table" then
    return nil, errors.new("doc must be a table", { code = "INVALID_VALUE" })
  end
  if doc.version ~= "0" then
    return nil, errors.new("version must be '0'", { code = "INVALID_VALUE" })
  end

  local o = doc.origin
  if type(o) ~= "table" then
    return nil, errors.new("origin is required", { code = "MISSING_FIELD" })
  end
  for _, f in ipairs({ "username", "sess_id", "sess_version",
                        "net_type", "addr_type", "unicast_address" }) do
    if type(o[f]) ~= "string" then
      return nil, errors.new("origin." .. f .. " is required", { code = "MISSING_FIELD" })
    end
  end
  if o.net_type ~= "IN" then
    return nil, errors.new("origin.net_type must be 'IN'", { code = "INVALID_VALUE" })
  end
  if o.addr_type ~= "IP4" and o.addr_type ~= "IP6" then
    return nil, errors.new("origin.addr_type must be 'IP4' or 'IP6'", { code = "INVALID_VALUE" })
  end

  local s = doc.session
  if type(s) ~= "table" then
    return nil, errors.new("session is required", { code = "MISSING_FIELD" })
  end
  if type(s.name) ~= "string" or s.name == "" then
    return nil, errors.new("session.name is required", { code = "MISSING_FIELD" })
  end
  local tim = s.timing
  if type(tim) ~= "table" or type(tim.start) ~= "number" or type(tim.stop) ~= "number" then
    return nil, errors.new("session.timing with numeric start and stop is required",
      { code = "MISSING_FIELD" })
  end

  if type(doc.media) ~= "table" then
    return nil, errors.new("media must be a table", { code = "INVALID_VALUE" })
  end
  for i, m in ipairs(doc.media) do
    if type(m.media) ~= "string" or m.media == "" then
      return nil, errors.new(string.format("media[%d].media is required", i),
        { code = "MISSING_FIELD" })
    end
    if type(m.port) ~= "number" then
      return nil, errors.new(string.format("media[%d].port must be a number", i),
        { code = "INVALID_VALUE" })
    end
    if type(m.proto) ~= "string" or m.proto == "" then
      return nil, errors.new(string.format("media[%d].proto is required", i),
        { code = "MISSING_FIELD" })
    end
    if type(m.fmts) ~= "table" or #m.fmts < 1 then
      return nil, errors.new(string.format("media[%d].fmts must be non-empty", i),
        { code = "MISSING_FIELD" })
    end
  end

  return true
end

-- ── Serialize ─────────────────────────────────────────────────────────────────
local serialize = {}

-- Emit one SDP field line with CRLF ending.
local function ln(t, v)
  return t .. "=" .. v .. "\r\n"
end

local function ser_connection(c)
  return ln("c", c.net_type .. " " .. c.addr_type .. " " .. c.address)
end

local function ser_bandwidth(b)
  return ln("b", b.type .. ":" .. tostring(b.value))
end

local function ser_attribute(a)
  if a.value then return ln("a", a.name .. ":" .. a.value) end
  return ln("a", a.name)
end

local function ser_media_block(m)
  local port_field = tostring(m.port)
  if m.port_count then port_field = port_field .. "/" .. tostring(m.port_count) end
  local parts = {
    ln("m", m.media .. " " .. port_field .. " " .. m.proto .. " " .. table.concat(m.fmts, " "))
  }
  if m.info       then parts[#parts + 1] = ln("i", m.info) end
  if m.connection then parts[#parts + 1] = ser_connection(m.connection) end
  for _, b in ipairs(m.bandwidths or {}) do parts[#parts + 1] = ser_bandwidth(b) end
  for _, a in ipairs(m.attributes or {}) do parts[#parts + 1] = ser_attribute(a) end
  return table.concat(parts)
end

--- Serialize an SDP document table to an RFC 4566 text string.
-- Field order follows RFC 4566 §5.  All lines use CRLF endings.
-- The caller is responsible for ensuring doc is structurally valid; no validation
-- is performed here.
-- @param doc table  SDP document table with version, origin, session, media fields.
-- @return string  SDP text with CRLF line endings.
function serialize.to_sdp(doc)
  local s = doc.session
  local o = doc.origin
  local parts = {}
  local function add(line) parts[#parts + 1] = line end

  add(ln("v", doc.version))
  add(ln("o", o.username .. " " .. o.sess_id .. " " .. o.sess_version
              .. " " .. o.net_type .. " " .. o.addr_type
              .. " " .. o.unicast_address))
  add(ln("s", s.name))
  if s.info then add(ln("i", s.info)) end
  if s.uri  then add(ln("u", s.uri)) end
  for _, e in ipairs(s.emails     or {}) do add(ln("e", e)) end
  for _, p in ipairs(s.phones     or {}) do add(ln("p", p)) end
  if s.connection then add(ser_connection(s.connection)) end
  for _, b in ipairs(s.bandwidths or {}) do add(ser_bandwidth(b)) end
  add(ln("t", tostring(s.timing.start) .. " " .. tostring(s.timing.stop)))
  for _, a in ipairs(s.attributes or {}) do add(ser_attribute(a)) end
  for _, m in ipairs(doc.media    or {}) do add(ser_media_block(m)) end
  return table.concat(parts)
end

-- ── ST 2110 ───────────────────────────────────────────────────────────────────
local st2110 = {}

-- Build a structured attribute-path error; shorthand used throughout st2110/ipmx.
local function attr_err(msg, mpath, attr_name, spec_ref, code)
  return nil, errors.new(msg, {
    field_path = mpath .. ".attributes[" .. attr_name .. "]",
    spec_ref   = spec_ref,
    code       = code,
  })
end

-- Call callback(legs) for every a=group:DUP entry in doc.session.attributes.
-- legs is an array of { idx=number, block=table } for each named MID.
-- Returns nil, err (using spec_ref) if a DUP references an undefined a=mid.
-- Returns nil, err if the callback itself returns nil, err.
local function each_dup_group(doc, spec_ref, callback)
  local mid_index = {}
  for i, m in ipairs(doc.media) do
    local ma = find_attr(m.attributes or {}, "mid")
    if ma and ma.value then
      mid_index[ma.value] = { idx = i, block = m }
    end
  end
  for _, attr in ipairs(doc.session.attributes or {}) do
    if attr.name == "group" then
      local val = attr.value or ""
      local semantics, rest = val:match("^(%S+)%s+(.+)$")
      if semantics == "DUP" and rest then
        local legs = {}
        for mid in rest:gmatch("%S+") do
          local entry = mid_index[mid]
          if not entry then
            return nil, errors.new(
              "a=group:DUP references undefined mid '" .. mid .. "'",
              { field_path = "session.attributes[group]",
                spec_ref = spec_ref, code = "INVALID_VALUE" })
          end
          legs[#legs + 1] = entry
        end
        if #legs < 2 then
          return nil, errors.new(
            "a=group:DUP must have at least 2 legs",
            { field_path = "session.attributes[group]",
              spec_ref = spec_ref, code = "INVALID_VALUE" })
        end
        local ok, err = callback(legs)
        if not ok then return nil, err end
      end
    end
  end
  return true
end

-- Parse an rtpmap value (e.g. "96 raw/90000") into encoding name and clock rate.
-- Returns encoding (string), clock_rate (number), or nil if the format does not match.
local function rtpmap_parse(value)
  local rest = value:match("^%d+%s+(.+)$")
  if not rest then return nil end
  local enc, rate_s = rest:match("^([^/]+)/(%d+)")
  if not enc then return nil end
  return enc, tonumber(rate_s)
end

-- LPEG patterns for ts-refclk ntp= address format validation.
local _ntp_octet =
  (P("25") * R("05")) +
  (P("2") * R("04") * R("09")) +
  (P("1") * R("09") * R("09")) +
  (R("19") * R("09")) +
  R("09")
-- _ipv4_raw: dotted-quad without end-anchor; shared as ls32 in the IPv6 grammar below.
local _ipv4_raw =
  _ntp_octet * P(".") * _ntp_octet * P(".") * _ntp_octet * P(".") * _ntp_octet
local _ntp_ipv4 = _ipv4_raw * P(-1)

local _ntp_alnum = R("az", "AZ", "09")
-- P("-")^0 allows consecutive hyphens (valid in IDN labels, e.g. xn--); trailing alnum
-- ensures labels never end with a hyphen.
local _ntp_label    = _ntp_alnum * (P("-")^0 * _ntp_alnum)^0
local _ntp_hostname = _ntp_label * (P(".") * _ntp_label)^0 * P(-1)

-- RFC 4291 / RFC 3986 §3.2.2 IPv6 address grammar.
-- Adapted from lpeg_patterns (MIT) © 2012–2016 daurnimator
-- https://github.com/daurnimator/lpeg_patterns
-- All value captures stripped; pure structural validation only.
local _HEXDIG = R("09", "af", "AF")
local _ntp_ipv6 = P({
  h16    = _HEXDIG * _HEXDIG^-3;
  h16c   = V"h16" * P":";
  ls32   = (V"h16c" * V"h16") + _ipv4_raw;

  mh16c_1 = V"h16c";
  mh16c_2 = V"h16c" * V"h16c";
  mh16c_3 = V"h16c" * V"h16c" * V"h16c";
  mh16c_4 = V"h16c" * V"h16c" * V"h16c" * V"h16c";
  mh16c_5 = V"h16c" * V"h16c" * V"h16c" * V"h16c" * V"h16c";
  mh16c_6 = V"h16c" * V"h16c" * V"h16c" * V"h16c" * V"h16c" * V"h16c";

  -- mcc_N in the source grammar injected N zero-captures; without captures all
  -- variants reduce to the same P"::" token, so one rule suffices.
  mcc = P"::";

  mh16_1 = V"h16";
  mh16_2 = V"mh16c_1" * V"h16";
  mh16_3 = V"mh16c_2" * V"h16";
  mh16_4 = V"mh16c_3" * V"h16";
  mh16_5 = V"mh16c_4" * V"h16";
  mh16_6 = V"mh16c_5" * V"h16";
  mh16_7 = V"mh16c_6" * V"h16";

  -- start rule: all 38 valid IPv6 forms (RFC 4291 §2.2 / RFC 3986 §3.2.2)
                         V"mh16c_6" * V"ls32"
  +             V"mcc" * V"mh16c_5" * V"ls32"
  +             V"mcc" * V"mh16c_4" * V"ls32"
  + V"h16"    * V"mcc" * V"mh16c_4" * V"ls32"
  +             V"mcc" * V"mh16c_3" * V"ls32"
  + V"h16"    * V"mcc" * V"mh16c_3" * V"ls32"
  + V"mh16_2" * V"mcc" * V"mh16c_3" * V"ls32"
  +             V"mcc" * V"mh16c_2" * V"ls32"
  + V"h16"    * V"mcc" * V"mh16c_2" * V"ls32"
  + V"mh16_2" * V"mcc" * V"mh16c_2" * V"ls32"
  + V"mh16_3" * V"mcc" * V"mh16c_2" * V"ls32"
  +             V"mcc" * V"h16c"    * V"ls32"
  + V"h16"    * V"mcc" * V"h16c"    * V"ls32"
  + V"mh16_2" * V"mcc" * V"h16c"    * V"ls32"
  + V"mh16_3" * V"mcc" * V"h16c"    * V"ls32"
  + V"mh16_4" * V"mcc" * V"h16c"    * V"ls32"
  +             V"mcc" *              V"ls32"
  + V"h16"    * V"mcc" *              V"ls32"
  + V"mh16_2" * V"mcc" *              V"ls32"
  + V"mh16_3" * V"mcc" *              V"ls32"
  + V"mh16_4" * V"mcc" *              V"ls32"
  + V"mh16_5" * V"mcc" *              V"ls32"
  +             V"mcc" * V"h16"
  + V"h16"    * V"mcc" * V"h16"
  + V"mh16_2" * V"mcc" * V"h16"
  + V"mh16_3" * V"mcc" * V"h16"
  + V"mh16_4" * V"mcc" * V"h16"
  + V"mh16_5" * V"mcc" * V"h16"
  + V"mh16_6" * V"mcc" * V"h16"
  +             V"mcc"
  + V"mh16_1" * V"mcc"
  + V"mh16_2" * V"mcc"
  + V"mh16_3" * V"mcc"
  + V"mh16_4" * V"mcc"
  + V"mh16_5" * V"mcc"
  + V"mh16_6" * V"mcc"
  + V"mh16_7" * V"mcc";
}) * P(-1)

local _ntp_addr_pat = _ntp_ipv4 + _ntp_ipv6 + _ntp_hostname

-- Validate the value of a ts-refclk attribute per ST 2110-10 §7.2.
-- Returns true on success, or nil + error message string on failure.
local function valid_tsrefclk(value)
  if value == "gps" or value == "gal" or value == "glonass" then return true end
  local addr = value:match("^ntp=(.+)$")
  if addr then
    if not _ntp_addr_pat:match(addr) then
      return nil, "invalid ts-refclk ntp address"
    end
    return true
  end
  local mac = value:match("^localmac=(.+)$")
  if mac then
    local count = 0
    for octet in mac:gmatch("[^%-]+") do
      if not octet:match("^%x%x$") then return nil, "invalid ts-refclk localmac value" end
      count = count + 1
    end
    if count ~= 6 then return nil, "invalid ts-refclk localmac value" end
    return true
  end
  local ptp_rest = value:match("^ptp=(.+)$")
  if ptp_rest then
    -- version:gmid[:domain] — version must be IEEE1588-2008 (ST 2110-10:2022 §8.2);
    -- GMID is either the literal "traceable" or 8 HH-separated hex octets (EUI-64).
    local version, gmid = ptp_rest:match("^([^:]+):([^:]+)")
    if not gmid then return nil, "invalid ts-refclk ptp value" end
    if version ~= "IEEE1588-2008" then
      return nil, "unrecognized ptp version '" .. version .. "' (expected IEEE1588-2008)"
    end
    if gmid == "traceable" then return true end
    local count = 0
    for octet in gmid:gmatch("[^%-]+") do
      if not octet:match("^%x%x$") then return nil, "invalid ts-refclk ptp value" end
      count = count + 1
    end
    if count ~= 8 then return nil, "invalid ts-refclk ptp value" end
    return true
  end
  return nil, "unrecognized ts-refclk clock source"
end

-- Validate a DID_SDID fmtp value; expected format: {0xHH,0xHH}.
local function valid_did_sdid(value)
  if value:match("^{0x%x%x,0x%x%x}$") then return true end
  return nil, "invalid DID_SDID value (expected {0xHH,0xHH})"
end

-- ── ST 2110-20/30 fmtp value validators ───────────────────────────────────────

-- LPEG patterns for structural validation of ST 2110-20 §7.2 fmtp values.
local _digit_seq   = R("09")^1
local _pos_int_pat = _digit_seq * P(-1)
local _efr_pat     = (_digit_seq * P("/") * _digit_seq + _digit_seq) * P(-1)
local _par_pat     = _digit_seq * P(":") * _digit_seq * P(-1)

-- SSN year suffix: exactly 4 decimal digits (e.g. "2017", "2022").
-- Combined with a prefix to form exact SSN patterns per each standard edition.
local _ssn_year  = R("09") * R("09") * R("09") * R("09")
local _ssn20_pat = P("ST2110-20:") * _ssn_year * P(-1)  -- ST 2110-20 §7.2
local _ssn22_pat = P("ST2110-22:") * _ssn_year * P(-1)  -- ST 2110-22 §7 (JPEG-XS)
local _ssn41_pat = P("ST2110-41:") * _ssn_year * P(-1)  -- ST 2110-41 §7.2

-- Allowed values for ST 2110-20 §7.2 enumerated fmtp fields.
local VALID_SAMPLING = {
  ["YCbCr-4:4:4"]=true, ["YCbCr-4:2:2"]=true, ["YCbCr-4:2:0"]=true,
  ["CLYCbCr-4:4:4"]=true, ["CLYCbCr-4:2:2"]=true, ["CLYCbCr-4:2:0"]=true,
  ["ICtCp-4:4:4"]=true, ["ICtCp-4:2:2"]=true, ["ICtCp-4:2:0"]=true,
  ["RGB"]=true, ["XYZ"]=true, ["KEY"]=true,
}
-- ST 2110-20:2017 §7.6: 10 TCS values (UNSPECIFIED added; was missing).
local VALID_TCS = {
  ["SDR"]=true, ["PQ"]=true, ["HLG"]=true, ["LINEAR"]=true,
  ["BT2100LINPQ"]=true, ["BT2100LINHLG"]=true,
  ["ST2065-1"]=true, ["ST428-1"]=true, ["DENSITY"]=true,
  ["UNSPECIFIED"]=true,
}
-- ST 2110-20:2017 §7.5: XYZ added (was missing); ALPHA retained (present in 2022 ed).
local VALID_COLORIMETRY = {
  ["BT601"]=true, ["BT709"]=true, ["BT2020"]=true, ["BT2100"]=true,
  ["ST2065-1"]=true, ["ST2065-3"]=true, ["UNSPECIFIED"]=true,
  ["XYZ"]=true, ["ALPHA"]=true,
}
local VALID_PM    = { ["2110GPM"]=true, ["2110BPM"]=true }
local VALID_RANGE = { ["NARROW"]=true, ["FULLPROTECT"]=true, ["FULL"]=true }
-- Valid m= transport protocols for ST 2110 RTP media blocks (ST 2110-10 §8.1).
local VALID_ST2110_PROTO = { ["RTP/AVP"] = true }

-- Validate the address field of a c= line for ST 2110 media blocks (RFC 4566 +
-- ST 2110-10 §6.5). IPv4 multicast requires a TTL and must not fall within the
-- Local Network Control Block (224.0.0.0/24) or Internetwork Control Block
-- (224.0.1.0/24) forbidden ranges defined in RFC 5771.
local function valid_connection_address(addr_type, addr)
  if addr_type ~= "IP4" then return true end
  local ip, rest = addr:match("^([^/]+)(.*)")
  local o1 = tonumber((ip or addr):match("^(%d+)%."))
  if not o1 then return nil, "invalid IPv4 address in c= line" end
  local is_mc = o1 >= 224 and o1 <= 239
  if is_mc then
    local ttl_str = rest:match("^/(%d+)$")
    if not ttl_str then
      return nil, "IPv4 multicast address requires a TTL suffix (e.g. 239.x.x.x/64)"
    end
    local ttl = tonumber(ttl_str)
    if not ttl or ttl < 1 or ttl > 255 then
      return nil, string.format("IPv4 multicast TTL must be 1-255 (got %s)", ttl_str)
    end
    local o2 = tonumber(ip:match("^%d+%.(%d+)%."))
    local o3 = tonumber(ip:match("^%d+%.%d+%.(%d+)%."))
    if o1 == 224 and o2 == 0 and (o3 == 0 or o3 == 1) then
      return nil, string.format(
        "forbidden multicast range 224.0.%d.0/24 (ST 2110-10 §6.5): %s", o3, ip)
    end
  else
    if rest ~= "" then
      return nil, "unicast address must not include a TTL suffix"
    end
  end
  return true
end

-- Known professional audio sample rates (Hz).
local VALID_AUDIO_RATES = {
  [32000]=true, [44100]=true, [48000]=true,
  [88200]=true, [96000]=true, [176400]=true, [192000]=true,
}
-- Valid TP (transport profile) values per ST 2110-21 (uncompressed video, ST 2110-20).
local VALID_TP = { ["2110TPN"]=true, ["2110TPNL"]=true, ["2110TPW"]=true }
-- Valid TP values for compressed video per ST 2110-22 (JPEG-XS); 2110TPN excluded.
local VALID_TP_22 = { ["2110TPNL"]=true, ["2110TPW"]=true }
-- Valid rtpmap encoding names for ST 2110-30/31 audio.
local VALID_AUDIO_ENC = { ["L16"]=true, ["L24"]=true, ["AM824"]=true }

-- Returns true if value is a key in set, otherwise nil + "invalid <name> value: <value>".
local function valid_enum(value, set, name)
  if set[value] then return true end
  return nil, "invalid " .. name .. " value: " .. tostring(value)
end

-- Returns true for a string of one or more digits that is > 0.
local function valid_pos_int(value)
  if not _pos_int_pat:match(value) then return nil, "expected positive integer" end
  if tonumber(value) <= 0 then return nil, "value must be positive" end
  return true
end

-- Returns true for a positive integer or a positive_n/positive_d fraction.
local function valid_exactframerate(value)
  if not _efr_pat:match(value) then
    return nil, "invalid exactframerate: " .. value
  end
  local n, d = value:match("^(%d+)/(%d+)$")
  if n then
    if tonumber(n) == 0 or tonumber(d) == 0 then
      return nil, "exactframerate fraction must have positive numerator and denominator"
    end
    return true
  end
  if tonumber(value) == 0 then return nil, "exactframerate must be positive" end
  return true
end

-- Returns true for a string of one or more digits (including zero).
local function valid_nonneg_int(value)
  if not _pos_int_pat:match(value) then return nil, "expected non-negative integer" end
  return true
end

-- Returns true for a PAR value in <W>:<H> format with both dimensions positive.
local function valid_par(value)
  if not _par_pat:match(value) then
    return nil, "invalid PAR format (expected W:H with positive integers)"
  end
  local w, h = value:match("^(%d+):(%d+)$")
  if tonumber(w) == 0 or tonumber(h) == 0 then
    return nil, "PAR dimensions must be positive"
  end
  return true
end

-- Returns true if value is a non-empty string with no whitespace (fmtp codec token).
local function valid_nonempty(value)
  if value and value ~= "" and not value:match("%s") then return true end
  return nil, "value must be a non-empty string"
end

-- Named channel-order grouping symbols from ST 2110-30:2017 §6.2.2 Table 1.
-- Unn (U01–U64) are handled separately by numeric range check below.
local VALID_CHAN_GROUPS = {
  ["M"]=true, ["DM"]=true, ["ST"]=true, ["LtRt"]=true,
  ["51"]=true, ["71"]=true, ["222"]=true, ["SGRP"]=true,
}

-- Returns true if value matches SMPTE2110.(<group>[,<group>...]) per ST 2110-30:2017 §6.2.2.
-- Each group must be a named symbol from Table 1 or Unn (U01–U64).
local function valid_channel_order(value)
  local groups_str = value:match("^SMPTE2110%.%((.+)%)$")
  if not groups_str then
    return nil, "invalid channel-order (expected SMPTE2110.(<group>[,<group>...]))"
  end
  for grp in groups_str:gmatch("[^,]+") do
    local g = grp:match("^%s*(.-)%s*$")
    if g == "" then
      return nil, "empty channel-order group symbol"
    end
    if not VALID_CHAN_GROUPS[g] then
      local nn = g:match("^U(%d%d)$")
      local n  = nn and tonumber(nn)
      if not n or n < 1 or n > 64 then
        return nil, "invalid channel-order group symbol: " .. g
      end
    end
  end
  return true
end

-- Validate the value of a mediaclk attribute per ST 2110-10 §7.3.
-- Returns true on success, or nil + error message string on failure.
local function valid_mediaclk(value)
  if value == "sender" then return true end
  local offset = value:match("^direct=(.+)$")
  if offset then
    if offset:match("^%-?%d+$") then return true end
    return nil, "invalid mediaclk direct= value"
  end
  return nil, "unrecognized mediaclk value"
end

-- Parse semicolon-separated key=value pairs from an fmtp attribute value.
-- Input format: "PT param1=v1; param2=v2; ..." (PT is the payload type prefix).
-- Returns a params table on success, or nil + error string if a token lacks '='.
local function fmtp_params(value)
  local params_str = value:match("^%d+%s+(.+)$")
  if not params_str then return {} end
  local params = {}
  for kv in params_str:gmatch("[^;]+") do
    local trimmed = kv:match("^%s*(.-)%s*$")
    if trimmed ~= "" then
      local k, v = trimmed:match("^([^=%s]+)%s*=%s*(.-)$")
      if k then
        params[k] = v
      elseif trimmed:match("^[%w_%-]+$") then
        params[trimmed] = true  -- bare flag token (e.g. "interlace" in ST 2110-20)
      else
        return nil, "malformed fmtp parameter: " .. trimmed
      end
    end
  end
  return params
end

--- Validate an SDP document against SMPTE ST 2110 requirements.
-- Runs RFC 4566 validation first, then for each media block checks:
-- ts-refclk (session or media level), mediaclk, rtpmap, fmtp, and
-- media-type-specific fmtp parameters (sampling for video,
-- channel-order for audio).
-- @param doc table  SDP document table.
-- @return true  on success.
-- @return nil, err  on failure; err includes field_path and spec_ref.
function st2110.validate(doc)
  local ok, e = validate.sdp(doc)
  if not ok then return nil, e end

  if #doc.media < 1 then
    return nil, errors.new("ST 2110 requires at least one media block",
      { field_path = "media", spec_ref = "ST 2110-10 §7" })
  end

  local sess_attrs = doc.session.attributes or {}

  -- Validate session-level c= if present (ST 2110-10 §6.5).
  local sess_conn = doc.session and doc.session.connection
  if sess_conn then
    local cok, msg = valid_connection_address(sess_conn.addr_type, sess_conn.address)
    if not cok then
      return nil, errors.new(msg, {
        field_path = "session.connection",
        spec_ref   = "ST 2110-10 §6.5", code = "INVALID_VALUE",
      })
    end
  end

  for i, m in ipairs(doc.media) do
    local mpath  = string.format("media[%d]", i)
    local mattrs = m.attributes or {}

    if not VALID_ST2110_PROTO[m.proto or ""] then
      return nil, errors.new(
        string.format("invalid media protocol '%s' (expected RTP/AVP)", tostring(m.proto)),
        { field_path = mpath .. ".proto", spec_ref = "ST 2110-10 §8.1", code = "INVALID_VALUE" })
    end

    local conn = m.connection
    if conn then
      local cok, msg = valid_connection_address(conn.addr_type, conn.address)
      if not cok then
        return nil, errors.new(msg, {
          field_path = mpath .. ".connection",
          spec_ref   = "ST 2110-10 §6.5", code = "INVALID_VALUE",
        })
      end
    end

    -- Require a connection address at session or media level (ST 2110-10 §6.3).
    if not conn and not sess_conn then
      return nil, errors.new(
        "missing required connection address (c=) for media block",
        { field_path = mpath .. ".connection", spec_ref = "ST 2110-10 §6.3" })
    end

    -- Validate all ts-refclk attrs from both session and media level (ST 2110-10 §8.2).
    -- Multiple sources are allowed; each must individually be valid.
    local all_tsrefclk = {}
    for _, a in ipairs(sess_attrs) do
      if a.name == "ts-refclk" then all_tsrefclk[#all_tsrefclk + 1] = a end
    end
    for _, a in ipairs(mattrs) do
      if a.name == "ts-refclk" then all_tsrefclk[#all_tsrefclk + 1] = a end
    end
    if #all_tsrefclk == 0 then
      return attr_err("missing required attribute 'ts-refclk'", mpath, "ts-refclk", "ST 2110-10 §7.2")
    end
    for _, tsrefclk in ipairs(all_tsrefclk) do
      local trok, trmsg = valid_tsrefclk(tsrefclk.value or "")
      if not trok then
        return attr_err("invalid ts-refclk: " .. (trmsg or ""), mpath, "ts-refclk", "ST 2110-10 §7.2", "INVALID_VALUE")
      end
    end

    local mediaclk = find_attr(mattrs, "mediaclk")
    if not mediaclk then
      return attr_err("missing required attribute 'mediaclk'", mpath, "mediaclk", "ST 2110-10 §7.3")
    end
    local mcok, mcmsg = valid_mediaclk(mediaclk.value or "")
    if not mcok then
      return attr_err("invalid mediaclk: " .. (mcmsg or ""), mpath, "mediaclk", "ST 2110-10 §7.3", "INVALID_VALUE")
    end

    local rtpmap = find_attr(mattrs, "rtpmap")
    if not rtpmap then
      return attr_err("missing required attribute 'rtpmap'", mpath, "rtpmap", "ST 2110-10 §7")
    end

    local fmtp = find_attr(mattrs, "fmtp")
    if not fmtp then
      return attr_err("missing required attribute 'fmtp'", mpath, "fmtp", "ST 2110-10 §7")
    end

    local rtp_pt  = (rtpmap.value or ""):match("^(%d+)")
    local fmtp_pt = (fmtp.value  or ""):match("^(%d+)")
    if rtp_pt ~= fmtp_pt then
      return attr_err(
        string.format("fmtp payload type %s does not match rtpmap payload type %s",
          tostring(fmtp_pt), tostring(rtp_pt)),
        mpath, "fmtp", "ST 2110-10 §7", "INVALID_VALUE")
    end

    local enc, clock_rate = rtpmap_parse(rtpmap.value or "")

    local params, fmtp_err = fmtp_params(fmtp.value or "")
    if not params then
      return attr_err("invalid fmtp: " .. fmtp_err, mpath, "fmtp", "ST 2110-10 §7", "INVALID_VALUE")
    end

    if enc == "smpte291" then
      -- ST 2110-40: ancillary data (RFC 8331 / SMPTE ST 2110-40)
      if clock_rate ~= 90000 then
        return attr_err(
          string.format("rtpmap clock rate must be 90000 for smpte291 (got %s)", tostring(clock_rate)),
          mpath, "rtpmap", "ST 2110-40 §7.2", "INVALID_VALUE")
      end
      -- DID_SDID may appear multiple times; collect and validate every occurrence.
      local did_sdid_list = {}
      for v in (fmtp.value or ""):gmatch("DID_SDID=([^;%s]+)") do
        did_sdid_list[#did_sdid_list + 1] = v
      end
      if #did_sdid_list == 0 then
        return attr_err("fmtp missing required 'DID_SDID' parameter for ST 2110-40 (smpte291)",
          mpath, "fmtp", "ST 2110-40 §7.2")
      end
      for _, dsval in ipairs(did_sdid_list) do
        local dok, derr = valid_did_sdid(dsval)
        if not dok then
          return attr_err("invalid DID_SDID: " .. derr, mpath, "fmtp", "ST 2110-40 §7.2", "INVALID_VALUE")
        end
      end
      local vpid = params["VPID_Code"]
      if vpid ~= nil and vpid ~= true then
        local n = tonumber(tostring(vpid))
        if not n or n < 0 or n ~= math.floor(n) then
          return attr_err("invalid VPID_Code value (must be a non-negative integer)",
            mpath, "fmtp", "ST 2110-40 §7.2", "INVALID_VALUE")
        end
      end

    elseif enc == "ST2110-41" then
      -- ST 2110-41: fast metadata
      if clock_rate ~= 90000 then
        return attr_err(
          string.format("rtpmap clock rate must be 90000 for ST2110-41 (got %s)", tostring(clock_rate)),
          mpath, "rtpmap", "ST 2110-41 §7.2", "INVALID_VALUE")
      end
      local ssn = params["SSN"]
      if not ssn then
        return attr_err("fmtp missing required 'SSN' parameter for ST 2110-41", mpath, "fmtp", "ST 2110-41 §7.2")
      end
      if not _ssn41_pat:match(ssn) then
        return attr_err("invalid SSN value (expected ST2110-41:YYYY, e.g. ST2110-41:2024)",
          mpath, "fmtp", "ST 2110-41 §7.2", "INVALID_VALUE")
      end
      if not params["DIT"] then
        return attr_err("fmtp missing required 'DIT' parameter for ST 2110-41", mpath, "fmtp", "ST 2110-41 §7.2")
      end
      local dit_val = tostring(params["DIT"])
      if not dit_val:match("^%d+$") then
        return attr_err("invalid DIT value (must be a non-negative integer)",
          mpath, "fmtp", "ST 2110-41 §7.2", "INVALID_VALUE")
      end

    elseif enc == "jxsv" then
      -- ST 2110-22: constant bit-rate compressed video (JPEG-XS encoding).
      -- Required fmtp: standard video params + JPEG-XS codec params.
      -- Spec refs: SMPTE ST 2110-22:2019 §7, TR-10-11, IPMX JPEG-XS Profile §6.1.4.
      if clock_rate ~= 90000 then
        return attr_err(
          string.format("rtpmap clock rate must be 90000 for jxsv (got %s)", tostring(clock_rate)),
          mpath, "rtpmap", "ST 2110-22 §7", "INVALID_VALUE")
      end
      -- Standard video fmtp params (same set as ST 2110-20 except SSN uses _ssn22_pat).
      local jxs_req = {
        { "sampling",       function(v) return valid_enum(v, VALID_SAMPLING,    "sampling")    end },
        { "width",          valid_pos_int },
        { "height",         valid_pos_int },
        { "exactframerate", valid_exactframerate },
        { "depth",          valid_pos_int },
        { "TCS",            function(v) return valid_enum(v, VALID_TCS,         "TCS")         end },
        { "colorimetry",    function(v) return valid_enum(v, VALID_COLORIMETRY, "colorimetry") end },
        { "PM",             function(v) return valid_enum(v, VALID_PM,          "PM")          end },
        { "SSN",            function(v)
            if _ssn22_pat:match(v) then return true end
            return nil, "invalid SSN value (expected ST2110-22:YYYY, e.g. ST2110-22:2019)"
          end },
        -- JPEG-XS codec params required by TR-10-11 / IPMX JPEG-XS Profile §6.1.4.
        { "profile",    valid_nonempty },
        { "level",      valid_nonempty },
        { "sublevel",   valid_nonempty },
        { "transmode",  valid_nonneg_int },
        { "packetmode", valid_nonneg_int },
      }
      for _, ck in ipairs(jxs_req) do
        local key, fn = ck[1], ck[2]
        local val = params[key]
        if val == nil then
          return attr_err("fmtp missing required '" .. key .. "' parameter for jxsv",
            mpath, "fmtp", "ST 2110-22 §7")
        end
        local vok, vmsg = fn(tostring(val))
        if not vok then
          return attr_err(key .. ": " .. vmsg, mpath, "fmtp", "ST 2110-22 §7", "INVALID_VALUE")
        end
      end
      -- Optional: RANGE (same enum as ST 2110-20).
      local range_val = params["RANGE"]
      if range_val ~= nil then
        local vok, vmsg = valid_enum(tostring(range_val), VALID_RANGE, "RANGE")
        if not vok then
          return attr_err(vmsg, mpath, "fmtp", "ST 2110-22 §7", "INVALID_VALUE")
        end
      end
      -- Optional: TP — ST 2110-22 allows only 2110TPNL and 2110TPW (not 2110TPN).
      local tp_val = params["TP"]
      if tp_val ~= nil and tp_val ~= true then
        local vok, vmsg = valid_enum(tostring(tp_val), VALID_TP_22, "TP")
        if not vok then
          return attr_err("TP: " .. vmsg .. " (ST 2110-22 allows 2110TPNL or 2110TPW only)",
            mpath, "fmtp", "ST 2110-22 §7", "INVALID_VALUE")
        end
      end
      -- Optional: MAXUDP, CMAX (positive integers).
      for _, k in ipairs({ "MAXUDP", "CMAX" }) do
        local v = params[k]
        if v ~= nil and v ~= true then
          local vok, vmsg = valid_pos_int(tostring(v))
          if not vok then
            return attr_err(k .. ": " .. vmsg, mpath, "fmtp", "ST 2110-22 §7", "INVALID_VALUE")
          end
        end
      end
      -- Optional: fbblevel (positive integer, TR-10-11 §12).
      local fbb = params["fbblevel"]
      if fbb ~= nil and fbb ~= true then
        local vok, vmsg = valid_pos_int(tostring(fbb))
        if not vok then
          return attr_err("fbblevel: " .. vmsg, mpath, "fmtp", "TR-10-11 §12", "INVALID_VALUE")
        end
      end

    elseif m.media == "video" then
      -- ST 2110-20: uncompressed video
      if clock_rate ~= 90000 then
        return attr_err(
          string.format("rtpmap clock rate must be 90000 for video (got %s)", tostring(clock_rate)),
          mpath, "rtpmap", "ST 2110-20 §7.2", "INVALID_VALUE")
      end
      -- All nine required fmtp parameters (ST 2110-20 §7.2): presence then value.
      local video_checks = {
        { "sampling",       function(v) return valid_enum(v, VALID_SAMPLING,    "sampling")    end },
        { "width",          valid_pos_int },
        { "height",         valid_pos_int },
        { "exactframerate", valid_exactframerate },
        { "depth",          valid_pos_int },
        { "TCS",            function(v) return valid_enum(v, VALID_TCS,         "TCS")         end },
        { "colorimetry",    function(v) return valid_enum(v, VALID_COLORIMETRY, "colorimetry") end },
        { "PM",             function(v) return valid_enum(v, VALID_PM,          "PM")          end },
        { "SSN",            function(v)
            if _ssn20_pat:match(v) then return true end
            return nil, "invalid SSN value (expected ST2110-20:YYYY, e.g. ST2110-20:2022)"
          end },
      }
      for _, ck in ipairs(video_checks) do
        local key, fn = ck[1], ck[2]
        local val = params[key]
        if val == nil then
          return attr_err("fmtp missing required '" .. key .. "' parameter for video",
            mpath, "fmtp", "ST 2110-20 §7.2")
        end
        local vok, vmsg = fn(tostring(val))
        if not vok then
          return attr_err(vmsg, mpath, "fmtp", "ST 2110-20 §7.2", "INVALID_VALUE")
        end
      end
      local range_val = params["RANGE"]
      if range_val ~= nil then
        local vok, vmsg = valid_enum(tostring(range_val), VALID_RANGE, "RANGE")
        if not vok then
          return attr_err(vmsg, mpath, "fmtp", "ST 2110-20 §7.2", "INVALID_VALUE")
        end
      end
      -- Optional ST 2110-20 fmtp params that have defined value formats.
      local video_opt_checks = {
        { "TP",     function(v) return valid_enum(v, VALID_TP, "TP") end },
        { "MAXUDP", valid_pos_int },
        { "PAR",    valid_par },
        { "TROFF",  valid_nonneg_int },
        { "CMAX",   valid_pos_int },
      }
      for _, ck in ipairs(video_opt_checks) do
        local key, fn = ck[1], ck[2]
        local val = params[key]
        if val ~= nil and val ~= true then
          local vok, vmsg = fn(tostring(val))
          if not vok then
            return attr_err(key .. ": " .. vmsg, mpath, "fmtp", "ST 2110-20 §7.2", "INVALID_VALUE")
          end
        end
      end

    elseif m.media == "audio" then
      -- ST 2110-30: audio (PCM) and ST 2110-31 (AES3/AM824)
      if enc and not VALID_AUDIO_ENC[enc] then
        return attr_err(
          string.format("rtpmap encoding '%s' is not valid for ST 2110-30 audio (must be L16, L24, or AM824)",
            tostring(enc)),
          mpath, "rtpmap", "ST 2110-30 §7.1", "INVALID_VALUE")
      end
      if not VALID_AUDIO_RATES[clock_rate] then
        return attr_err(
          string.format("rtpmap clock rate %s is not a known audio sample rate", tostring(clock_rate)),
          mpath, "rtpmap", "ST 2110-30 §7.1", "INVALID_VALUE")
      end
      -- Channel count is required in ST 2110-30 rtpmap and must be 1-16 (§7.1).
      local ch_s = (rtpmap.value or ""):match("^%d+%s+%S+/%d+/(%d+)$")
      if not ch_s then
        return attr_err(
          "rtpmap missing channel count for ST 2110-30 audio (expected encoding/rate/channels)",
          mpath, "rtpmap", "ST 2110-30 §7.1")
      end
      local ch = tonumber(ch_s)
      if not ch or ch < 1 or ch > 16 then
        return attr_err(
          string.format("rtpmap channel count %s is not valid for ST 2110-30 (must be 1-16)", ch_s),
          mpath, "rtpmap", "ST 2110-30 §7.1", "INVALID_VALUE")
      end
      -- Validate a=ptime if present (ST 2110-30 §7.2 recommends ptime=1 ms).
      local ptime_attr = find_attr(mattrs, "ptime")
      if ptime_attr then
        local n = tonumber(ptime_attr.value or "")
        if not n or n <= 0 then
          return attr_err("invalid a=ptime value (expected positive number)",
            mpath, "ptime", "ST 2110-30 §7.2", "INVALID_VALUE")
        end
      end
      local co = params["channel-order"]
      if not co then
        return attr_err("fmtp missing required 'channel-order' parameter for audio",
          mpath, "fmtp", "ST 2110-30 §7.2")
      end
      local cok, cmsg = valid_channel_order(tostring(co))
      if not cok then
        return attr_err(cmsg, mpath, "fmtp", "ST 2110-30 §7.2", "INVALID_VALUE")
      end
    end
  end

  -- Validate a=group:DUP grouping per ST 2110-10 §8.5 + RFC 7104.
  local dup_ok, dup_err = each_dup_group(doc, "ST 2110-10 §8.5", function(legs)
    local base_type = legs[1].block.media
    for j = 2, #legs do
      if legs[j].block.media ~= base_type then
        return nil, errors.new(
          "a=group:DUP legs must have the same media type",
          { field_path = "session.attributes[group]",
            spec_ref = "ST 2110-10 §8.5", code = "INVALID_VALUE" })
      end
    end
    return true
  end)
  if not dup_ok then return nil, dup_err end

  return true
end

-- ── IPMX ──────────────────────────────────────────────────────────────────────
local ipmx = {}

-- RFC 5285 a=extmap: entry-count ["/direction"] SP URI [SP ext-attr]
local _extmap_id  = R("09")^1
local _extmap_dir = P("sendonly") + P("recvonly") + P("sendrecv") + P("inactive")
local _uri_scheme = R("az","AZ") * (R("az","AZ","09") + S("+-.")  )^0
local _uri_body   = (P(1) - S(" \t"))^1
local VALID_EXTMAP_PAT = _extmap_id
                       * (P("/") * _extmap_dir)^-1
                       * P(" ")
                       * _uri_scheme * P(":") * _uri_body
                       * (P(" ") * P(1)^0)^-1
                       * P(-1)

local function valid_extmap(value)
  if not VALID_EXTMAP_PAT:match(value) then
    return nil, "invalid a=extmap format (expected: entry-count[/direction] URI)"
  end
  local id = tonumber(value:match("^(%d+)"))
  if not id or id < 1 then
    return nil, "a=extmap entry count must be >= 1"
  end
  if id > 255 then
    return nil, "a=extmap entry count must be 1-255 (RFC 5285)"
  end
  return true
end

-- Validate an a=hkep attribute value per VSF TR-10-5 §10.
-- Format: <port> IN <IP4|IP6> <addr> <node-id> <port-id>
-- node-id: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx (UUID, hex, no braces)
-- port-id: xx-xx-xx-xx-xx (5 groups of 2 hex digits)
local function valid_hkep(value)
  -- addr (4th token) is captured but not format-checked; TR-10-5 §10 constrains
  -- only that a host is present, not its specific syntax.
  local port_s, nettype, addrtype, _, node_id, port_id =
    value:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)$")
  if not port_s then
    return nil, "expected '<port> IN <addrtype> <addr> <node-id> <port-id>'"
  end
  local port = tonumber(port_s)
  if not port or port < 0 or port > 65535 or port ~= math.floor(port) then
    return nil, "invalid port number"
  end
  if nettype ~= "IN" then return nil, "nettype must be 'IN'" end
  if addrtype ~= "IP4" and addrtype ~= "IP6" then
    return nil, "addrtype must be 'IP4' or 'IP6'"
  end
  if not node_id:match(
    "^%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x$") then
    return nil, "invalid node-id (expected xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx)"
  end
  if not port_id:match("^%x%x%-%x%x%-%x%x%-%x%x%-%x%x$") then
    return nil, "invalid port-id (expected xx-xx-xx-xx-xx)"
  end
  return true
end

-- Valid protocol values for a=privacy (TR-10-13 §13).
local PRIVACY_PROTOCOLS = { RTP = true, RTP_KV = true }

-- All valid mode values for a=privacy (TR-10-13 §13).
local PRIVACY_MODES = {
  ["AES-128-CTR"]                  = true, ["AES-256-CTR"]                  = true,
  ["AES-128-CTR_CMAC-64"]          = true, ["AES-256-CTR_CMAC-64"]          = true,
  ["AES-128-CTR_CMAC-64-AAD"]      = true, ["AES-256-CTR_CMAC-64-AAD"]      = true,
  ["ECDH_AES-128-CTR"]             = true, ["ECDH_AES-256-CTR"]             = true,
  ["ECDH_AES-128-CTR_CMAC-64"]     = true, ["ECDH_AES-256-CTR_CMAC-64"]     = true,
  ["ECDH_AES-128-CTR_CMAC-64-AAD"] = true, ["ECDH_AES-256-CTR_CMAC-64-AAD"] = true,
}

-- Modes allowed on USB transport blocks only — must be AAD variants (TR-10-14 §12).
local PRIVACY_USB_MODES = {
  ["AES-128-CTR_CMAC-64-AAD"]      = true, ["AES-256-CTR_CMAC-64-AAD"]      = true,
  ["ECDH_AES-128-CTR_CMAC-64-AAD"] = true, ["ECDH_AES-256-CTR_CMAC-64-AAD"] = true,
}

-- Validate an a=privacy attribute value per VSF TR-10-13 §13.
-- Format: protocol=<p>; mode=<m>; iv=<iv>; key_generator=<kg>; key_version=<kv>; key_id=<kid>
-- Pass usb_only=true to restrict to the four AAD modes required by TR-10-14 §12.
local function valid_privacy(value, usb_only)
  local params = {}
  for kv in (value:match("^%s*(.-)%s*$")):gmatch("[^;]+") do
    local trimmed = kv:match("^%s*(.-)%s*$")
    if trimmed ~= "" then
      local k, v = trimmed:match("^([^=]+)%s*=%s*(.*)$")
      if not k then return nil, "malformed parameter: " .. trimmed end
      params[k:match("^%s*(.-)%s*$")] = v
    end
  end
  for _, f in ipairs({ "protocol", "mode", "iv", "key_generator", "key_version", "key_id" }) do
    if not params[f] then return nil, "missing required '" .. f .. "' parameter" end
  end
  if not PRIVACY_PROTOCOLS[params.protocol] then
    return nil, "invalid protocol '" .. params.protocol .. "' (must be RTP or RTP_KV)"
  end
  local modes = usb_only and PRIVACY_USB_MODES or PRIVACY_MODES
  if not modes[params.mode] then
    return nil, "invalid mode '" .. params.mode .. "'"
  end
  for _, f in ipairs({ "iv", "key_generator", "key_version", "key_id" }) do
    if not params[f]:match("^%x+$") then
      return nil, "invalid " .. f .. " value (must be hexadecimal)"
    end
  end
  return true
end

-- Validate every a=privacy attribute in attrs.
-- path is the field_path prefix (e.g. "session" or "media[1]").
-- Pass is_usb=true to restrict to the four AAD-only modes required by TR-10-14 §12.
local function check_privacy(attrs, path, is_usb)
  for _, attr in ipairs(attrs or {}) do
    if attr.name == "privacy" then
      local ok, perr = valid_privacy(attr.value or "", is_usb)
      if not ok then
        return nil, errors.new("invalid a=privacy: " .. perr, {
          field_path = path .. ".attributes[privacy]",
          spec_ref   = is_usb and "TR-10-14 §12" or "TR-10-13 §13",
          code       = "INVALID_VALUE",
        })
      end
    end
  end
  return true
end

--- Validate an SDP document against IPMX requirements.
-- Runs ST 2110 validation first on all non-USB media blocks, then checks:
-- a=extmap presence, IPMX fmtp marker (TR-10-1 §10.1), a=hkep format
-- (TR-10-5 §10), a=privacy format (TR-10-13 §13), FEC params (TR-10-6 §7.6).
-- USB blocks (m=application with TCP transport, TR-10-14) bypass ST 2110
-- media-block checks.
-- @param doc table  SDP document table.
-- @return true  on success.
-- @return nil, err  on failure; err includes field_path and spec_ref.
function ipmx.validate(doc)
  -- Identify USB media blocks: m=application with TCP transport (TR-10-14).
  local usb_set = {}
  for i, m in ipairs(doc.media) do
    if m.media == "application" and type(m.proto) == "string" and m.proto:match("TCP") then
      usb_set[i] = true
    end
  end

  -- Build a filtered media list (non-USB) for ST 2110 validation.
  local rtp_media = {}
  for i, m in ipairs(doc.media) do
    if not usb_set[i] then rtp_media[#rtp_media + 1] = m end
  end

  if #rtp_media > 0 then
    local filtered = { version = doc.version, origin = doc.origin,
                       session = doc.session, media = rtp_media }
    local ok, e = st2110.validate(filtered)
    if not ok then return nil, e end
  else
    local ok, e = validate.sdp(doc)
    if not ok then return nil, e end
  end

  -- Reject a=group:FID — TR-10-1 §10 ("shall not be used under this TR").
  for _, attr in ipairs(doc.session.attributes or {}) do
    if attr.name == "group" then
      local sem = (attr.value or ""):match("^(%S+)")
      if sem == "FID" then
        return nil, errors.new(
          "a=group:FID is not permitted in IPMX (TR-10-1 §10)",
          { field_path = "session.attributes[group]",
            spec_ref = "TR-10-1 §10", code = "INVALID_VALUE" })
      end
    end
  end

  -- Check for a=extmap at session level or in at least one non-USB media block.
  local has_extmap = find_attr(doc.session.attributes, "extmap") ~= nil
  if not has_extmap then
    for i, m in ipairs(doc.media) do
      if not usb_set[i] and find_attr(m.attributes or {}, "extmap") then
        has_extmap = true
        break
      end
    end
  end
  if not has_extmap then
    return nil, errors.new("missing required attribute 'extmap'", {
      field_path = "session.attributes[extmap]",
      spec_ref   = "IPMX §6",
    })
  end

  -- Validate URI format of every a=extmap attribute (RFC 5285).
  for _, attr in ipairs(doc.session.attributes or {}) do
    if attr.name == "extmap" then
      local ok, msg = valid_extmap(attr.value or "")
      if not ok then
        return nil, errors.new("invalid a=extmap: " .. msg, {
          field_path = "session.attributes[extmap]",
          spec_ref   = "IPMX §6 / RFC 5285", code = "INVALID_VALUE",
        })
      end
    end
  end
  for i, m in ipairs(doc.media) do
    if not usb_set[i] then
      for _, attr in ipairs(m.attributes or {}) do
        if attr.name == "extmap" then
          local ok, emsg = valid_extmap(attr.value or "")
          if not ok then
            return nil, errors.new("invalid a=extmap: " .. emsg, {
              field_path = string.format("media[%d].attributes[extmap]", i),
              spec_ref   = "IPMX §6 / RFC 5285", code = "INVALID_VALUE",
            })
          end
        end
      end
    end
  end

  -- Enforce a=extmap ID uniqueness per RFC 5285 §3 ("unique per level").
  -- Session scope and each media-block scope are checked independently.
  local sess_extmap_ids = {}
  for _, attr in ipairs(doc.session.attributes or {}) do
    if attr.name == "extmap" then
      local id = tonumber((attr.value or ""):match("^(%d+)"))
      if id then
        if sess_extmap_ids[id] then
          return nil, errors.new(
            string.format("duplicate a=extmap ID %d (must be unique per RFC 5285 §3)", id),
            { field_path = "session.attributes[extmap]",
              spec_ref = "RFC 5285 §3", code = "INVALID_VALUE" })
        end
        sess_extmap_ids[id] = true
      end
    end
  end
  for i, m in ipairs(doc.media) do
    if not usb_set[i] then
      local media_extmap_ids = {}
      for _, attr in ipairs(m.attributes or {}) do
        if attr.name == "extmap" then
          local id = tonumber((attr.value or ""):match("^(%d+)"))
          if id then
            if media_extmap_ids[id] then
              return nil, errors.new(
                string.format("duplicate a=extmap ID %d (must be unique per RFC 5285 §3)", id),
                { field_path = string.format("media[%d].attributes[extmap]", i),
                  spec_ref = "RFC 5285 §3", code = "INVALID_VALUE" })
            end
            media_extmap_ids[id] = true
          end
        end
      end
    end
  end

  -- Check IPMX fmtp marker and optional FEC params in each non-USB block (TR-10-1 §10.1).
  for i, m in ipairs(doc.media) do
    if not usb_set[i] then
      local mpath = string.format("media[%d]", i)
      local fmtp  = find_attr(m.attributes or {}, "fmtp")
      if fmtp then
        local params, ferr = fmtp_params(fmtp.value or "")
        if not params then
          return attr_err("invalid fmtp: " .. ferr, mpath, "fmtp", "TR-10-1 §10.1", "INVALID_VALUE")
        end
        if not params["IPMX"] then
          return attr_err("fmtp missing required 'IPMX' marker", mpath, "fmtp", "TR-10-1 §10.1")
        end
        if params["FECPROFILE"] and params["FECPROFILE"] ~= "profile-a" then
          return attr_err(
            "invalid FECPROFILE '" .. params["FECPROFILE"] .. "' (expected 'profile-a')",
            mpath, "fmtp", "TR-10-6 §7.6", "INVALID_VALUE")
        end
        for _, lat in ipairs({ "FEC_ADD_LATENCY_VIDEO", "FEC_ADD_LATENCY_AUDIO" }) do
          if params[lat] then
            if not params["FECPROFILE"] then
              return attr_err(
                lat .. " requires FECPROFILE to also be present",
                mpath, "fmtp", "TR-10-6 §7.6")
            end
            local n = tonumber(params[lat])
            if not n or n < 0 or n ~= math.floor(n) then
              return attr_err(
                "invalid " .. lat .. " value (must be a non-negative integer)",
                mpath, "fmtp", "TR-10-6 §7.6", "INVALID_VALUE")
            end
          end
        end
        -- Baseband params must be positive integers when present (TR-10-2 §11, TR-10-3 §10.3).
        if m.media == "video" then
          for _, bp in ipairs({ "measuredpixclk", "vtotal", "htotal" }) do
            if params[bp] then
              local n = tonumber(params[bp])
              if not n or n <= 0 or n ~= math.floor(n) then
                return attr_err(
                  string.format("fmtp '%s' must be a positive integer", bp),
                  mpath, "fmtp", "TR-10-2 §11", "INVALID_VALUE")
              end
            end
          end
        elseif m.media == "audio" then
          if params["measuredsamplerate"] then
            local n = tonumber(params["measuredsamplerate"])
            if not n or n <= 0 or n ~= math.floor(n) then
              return attr_err(
                "fmtp 'measuredsamplerate' must be a positive integer",
                mpath, "fmtp", "TR-10-3 §10.3", "INVALID_VALUE")
            end
          end
        end
      end
      -- IPMX audio: ptime is required (TR-10-3 §8); AM824 encoding is not valid.
      if m.media == "audio" then
        local rtpmap_a = find_attr(m.attributes or {}, "rtpmap")
        if rtpmap_a then
          local enc_a = rtpmap_parse(rtpmap_a.value or "")
          if enc_a == "AM824" then
            return attr_err(
              "AM824 encoding is not valid for IPMX audio (use L16 or L24)",
              mpath, "rtpmap", "TR-10-3 §8", "INVALID_VALUE")
          end
        end
        if not find_attr(m.attributes or {}, "ptime") then
          return attr_err(
            "a=ptime is required for IPMX audio",
            mpath, "ptime", "TR-10-3 §8")
        end
      end
    end
  end

  -- Validate a=hkep at session level if present; multiple lines allowed (TR-10-5 §10).
  for _, attr in ipairs(doc.session.attributes or {}) do
    if attr.name == "hkep" then
      local ok, herr = valid_hkep(attr.value or "")
      if not ok then
        return nil, errors.new("invalid a=hkep: " .. herr, {
          field_path = "session.attributes[hkep]",
          spec_ref   = "TR-10-5 §10", code = "INVALID_VALUE",
        })
      end
    end
  end

  -- Validate a=hkep at media block level if present (TR-10-5 §10).
  for i, m in ipairs(doc.media) do
    for _, attr in ipairs(m.attributes or {}) do
      if attr.name == "hkep" then
        local ok, herr = valid_hkep(attr.value or "")
        if not ok then
          return nil, errors.new("invalid a=hkep: " .. herr, {
            field_path = string.format("media[%d].attributes[hkep]", i),
            spec_ref   = "TR-10-5 §10", code = "INVALID_VALUE",
          })
        end
      end
    end
  end

  local pok, perr = check_privacy(doc.session.attributes, "session", false)
  if not pok then return nil, perr end
  for i, m in ipairs(doc.media) do
    local pok2, perr2 = check_privacy(
      m.attributes, string.format("media[%d]", i), usb_set[i] == true)
    if not pok2 then return nil, perr2 end
  end

  -- DUP group privacy consistency (TR-10-13 §13).
  -- Undefined mids were already rejected by st2110.validate above.
  local dup_ok, dup_err = each_dup_group(doc, "TR-10-13 §13", function(legs)
    local first_pattr = find_attr(legs[1].block.attributes or {}, "privacy")
    local first_val = first_pattr and first_pattr.value or false
    for j = 2, #legs do
      local pattr = find_attr(legs[j].block.attributes or {}, "privacy")
      local val = pattr and pattr.value or false
      if val ~= first_val then
        return nil, errors.new(
          "a=privacy values must be identical on all DUP group legs",
          { field_path = "session.attributes[group]",
            spec_ref = "TR-10-13 §13", code = "INVALID_VALUE" })
      end
    end
    return true
  end)
  if not dup_ok then return nil, dup_err end

  -- RTCP port convention and port range (TR-10-1 §7, §8.7) — IPMX only.
  for i, m in ipairs(doc.media) do
    if not usb_set[i] then
      local mpath  = string.format("media[%d]", i)
      local mattrs = m.attributes or {}

      -- Port must be even and > 1024 (TR-10-1 §7).
      local port = m.port
      if port then
        if port <= 1024 then
          return attr_err(
            string.format("media port must be > 1024 (got %d)", port),
            mpath, "port", "TR-10-1 §7", "INVALID_VALUE")
        end
        if port % 2 ~= 0 then
          return attr_err(
            string.format("media port must be even (got %d)", port),
            mpath, "port", "TR-10-1 §7", "INVALID_VALUE")
        end
      end

      if find_attr(mattrs, "rtcp-mux") then
        return attr_err(
          "a=rtcp-mux is not permitted (IPMX requires RTCP on media port+1)",
          mpath, "rtcp-mux", "TR-10-1 §8.7", "INVALID_VALUE")
      end

      local rtcp_attr = find_attr(mattrs, "rtcp")
      if rtcp_attr then
        local rtcp_port_s = (rtcp_attr.value or ""):match("^(%d+)")
        local rtcp_port   = rtcp_port_s and tonumber(rtcp_port_s)
        if not rtcp_port or rtcp_port ~= (m.port + 1) then
          return attr_err(
            string.format("a=rtcp port must be media port+1 (expected %d, got %s)",
              m.port + 1, tostring(rtcp_port)),
            mpath, "rtcp", "TR-10-1 §8.7", "INVALID_VALUE")
        end
      end
    end
  end

  return true
end

-- ── Parser ────────────────────────────────────────────────────────────────────
local parser = {}

-- Split SDP text into lines, stripping CRLF or LF endings.
-- Returns an array of raw line strings without any line-ending characters.
local function split_lines(text)
  local lines = {}
  local i = 1
  while i <= #text do
    local j = text:find("\n", i, true)
    if j then
      local line = text:sub(i, j - 1)
      if line:sub(-1) == "\r" then line = line:sub(1, -2) end
      lines[#lines + 1] = line
      i = j + 1
    else
      local tail = text:sub(i)
      if tail ~= "" then lines[#lines + 1] = tail end
      break
    end
  end
  return lines
end

-- Consume and validate the line at lines[pos] against the expected type_char.
-- Fails with a typed error if the line is absent, malformed, the wrong type,
-- or if parse_value rejects the value.
-- @return parsed_value on success, or nil + error table on failure.
local function parse_required(lines, pos, type_char, parse_value)
  if pos > #lines then
    return nil, errors.new(
      string.format("missing required field '%s='", type_char),
      { line = pos, col = 1, context = "", code = "MISSING_FIELD" }
    )
  end
  local line = lines[pos]
  local tc, v, offset = grammar.tokenize_line(line)
  if not tc then
    return nil, errors.new("malformed line",
      { line = pos, col = v or 1, context = line, code = "MALFORMED_LINE" })
  end
  if tc ~= type_char then
    return nil, errors.new(
      string.format("expected '%s=' but found '%s='", type_char, tc),
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

-- Return the SDP type char of lines[pos], or nil if absent or malformed.
local function peek_type(lines, pos)
  local tc = grammar.tokenize_line(lines[pos])
  return tc
end

--- Parse SDP text into a raw document table (no metatable attached).
-- Enforces RFC 4566 §5 field ordering strictly.  Optionally runs ST 2110
-- or IPMX validation after a successful RFC 4566 parse.
-- @param text string  Raw SDP text (CRLF or LF line endings).
-- @param mode string  Optional: "st2110" or "ipmx" for extended validation.
-- @return table  Raw SDP document table on success.
-- @return nil, err  on parse or validation failure.
function parser.parse(text, mode)
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
    local tc = peek_type(lines, pos)
    if tc then
      return nil, errors.new(
        string.format("unexpected field '%s=' after all SDP fields", tc),
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
    local ok, ve = st2110.validate(doc)
    if not ok then return nil, ve end
  elseif mode == "ipmx" then
    local ok, ve = ipmx.validate(doc)
    if not ok then return nil, ve end
  end

  return doc
end

-- ── Public API ────────────────────────────────────────────────────────────────
local M  = {}
local mt = {}
mt.__index = mt

local validators = {
  sdp    = validate.sdp,
  st2110 = st2110.validate,
  ipmx   = ipmx.validate,
}

--- Validate the document against the given tier.
-- @param mode string  "sdp" (default), "st2110", or "ipmx".
-- @return true  on success.
-- @return nil, err  on failure; err is an error table from errors.new.
function mt:validate(mode)
  mode = mode or "sdp"
  local fn = validators[mode]
  if not fn then return nil, errors.new("unknown mode: " .. tostring(mode)) end
  return fn(self)
end

--- Test whether the document is a valid RFC 4566 SDP.
-- @return boolean
function mt:is_sdp()    return validate.sdp(self) == true end

--- Test whether the document satisfies SMPTE ST 2110 requirements.
-- @return boolean
function mt:is_st2110() return st2110.validate(self) == true end

--- Test whether the document satisfies IPMX requirements.
-- @return boolean
function mt:is_ipmx()   return ipmx.validate(self) == true end

--- Encode the document as a JSON string using dkjson.
-- @return string  JSON representation of the document.
function mt:to_json()
  return dkjson.encode(self)
end

--- Serialize the document back to RFC 4566 SDP text.
-- @return string  SDP text with CRLF line endings.
function mt:to_sdp()
  return serialize.to_sdp(self)
end

--- Parse SDP text and return a doc object with metatable methods attached.
-- @param text string  Raw SDP text (CRLF or LF line endings).
-- @param mode string  Optional validation tier: "st2110" or "ipmx".
-- @return doc  Parsed SDP document on success.
-- @return nil, err  on parse or validation failure.
function M.parse(text, mode)
  local doc, e = parser.parse(text, mode)
  if not doc then return nil, e end
  return setmetatable(doc, mt)
end

--- Wrap an existing table as a doc object without parsing or validation.
-- @param t table  Any table to wrap.
-- @return doc  The table with SDP metatable methods attached.
function M.new(t)
  return setmetatable(t, mt)
end

-- Exposed for spec access; not part of the public contract.
M._grammar = grammar
M._errors  = errors

-- ── CLI (detect-if-main) ──────────────────────────────────────────────────────
if arg and arg[0] and arg[0]:match("parse_sdp") then
  local argparse = require("argparse")

  local function die(err_table)
    io.stderr:write(errors.format(err_table) .. "\n")
    os.exit(1)
  end

  local function read_input(file)
    if file then
      local f, ioerr = io.open(file, "r")
      if not f then die(errors.new("cannot open file: " .. (ioerr or file))); return end
      local text = f:read("*a")
      f:close()
      return text
    end
    return io.read("*a")
  end

  local ap = argparse("parse_sdp", "Parse, validate, and serialize SDP (RFC 4566 / ST 2110 / IPMX).")
  ap:epilog(table.concat({
    "Examples:",
    "  parse_sdp to_json session.sdp",
    "  parse_sdp to_json --mode st2110 --pretty session.sdp",
    "  parse_sdp to_json < session.sdp | parse_sdp to_sdp",
    "  parse_sdp to_sdp session.json",
  }, "\n"))
  ap:command_target("command")

  local cmd_parse = ap:command("to_json", "Parse and validate an SDP file; output JSON.")
  cmd_parse:argument("file", "Path to .sdp file. Reads stdin if omitted."):args("?")
  cmd_parse:option("--mode", "Validation tier: 'st2110' or 'ipmx'. Defaults to RFC 4566 only.")
  cmd_parse:flag("--pretty", "Pretty-print JSON output with indentation.")

  local cmd_ser = ap:command("to_sdp", "Convert a JSON SDP document back to SDP text.")
  cmd_ser:argument("file", "Path to .json file. Reads stdin if omitted."):args("?")

  local parsed = ap:parse()

  if parsed.command == "to_json" then
    local text = read_input(parsed.file)
    local doc, perr = M.parse(text, parsed.mode)
    if not doc then die(perr) end
    local encode_opts = parsed.pretty and { indent = true } or nil
    io.write(dkjson.encode(doc, encode_opts) .. "\n")
    os.exit(0)

  elseif parsed.command == "to_sdp" then
    local json_text = read_input(parsed.file)
    local tbl, _, jsonerr = dkjson.decode(json_text)
    if not tbl then
      die(errors.new("invalid JSON: " .. (jsonerr or "parse error")))
    end
    local doc = M.new(tbl)
    local ok, result = pcall(function() return doc:to_sdp() end)
    if not ok then
      die(errors.new("to_sdp error: " .. tostring(result)))
    end
    io.write(result)
    os.exit(0)
  end
end

return M
