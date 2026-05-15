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
  local port = tonumber(port_str)
  if port > 65535 then return nil, 1 end
  return {
    media      = mtype,
    port       = port,
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

-- RFC 4566 §9 token grammar (referenced by RFC 5888 §4/§5 for semantics and
-- identification-tag): token-char = %x21 / %x23-27 / %x2A-2B / %x2D-2E /
-- %x30-39 / %x41-5A / %x5E-7E. Excludes SP, DQUOTE, parens, comma, slash,
-- colon-through-at, brackets-and-backslash, DEL.
local _rfc4566_token_char =
    P("!")          -- 0x21
  + R("\35\39")     -- 0x23-0x27: # $ % & '
  + R("\42\43")     -- 0x2A-0x2B: * +
  + R("\45\46")     -- 0x2D-0x2E: - .
  + R("\48\57")     -- 0x30-0x39: 0-9
  + R("\65\90")     -- 0x41-0x5A: A-Z
  + R("\94\126")    -- 0x5E-0x7E: ^ _ ` a-z { | } ~
local _rfc4566_token_pat = _rfc4566_token_char^1 * P(-1)

-- RFC 5888 §5 a=group value: semantics *(SP identification-tag); semantics is
-- a token, each identification-tag is a token. Empty value is invalid.
local _group_value_pat =
    _rfc4566_token_char^1
  * (P(" ") * _rfc4566_token_char^1)^0
  * P(-1)

local function valid_mid_value(v)
  if not _rfc4566_token_pat:match(v or "") then
    return nil, "a=mid value must be an RFC 4566 token (alphanumeric plus !#$%&'*+-.^_`|~)"
  end
  return true
end

local function valid_group_value(v)
  if not _group_value_pat:match(v or "") then
    return nil, "a=group value must be <semantics> *(SP <identification-tag>), each an RFC 4566 token"
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

-- Aliases for the anchored IPv4/IPv6 patterns used by c= and a=source-filter
-- address validators. Spec basis: ST 2110-10 §6.5 (RFC 791 IPv4 / RFC 2460 IPv6
-- literal addressing for ST 2110/IPMX) and RFC 4570 for source-filter.
local _ipv4_addr_pat = _ntp_ipv4
local _ipv6_addr_pat = _ntp_ipv6

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
    -- ST 2110-10:2022 §8.2: "Devices which are referenced to IEEE Std
    -- 1588-2008 shall use the ts-refclk:ptp form, signaling EITHER the
    -- grandmaster clockIdentity AND domain number, OR signaling that the
    -- PTP is traceable." Form is version:gmid[:domain]; gmid is either
    -- "traceable" (no domain) or 8 hex octets in EUI-64 form (domain
    -- required, integer 0–127 per IEEE 1588-2008 §7.1).
    local version, gmid = ptp_rest:match("^([^:]+):([^:]+)")
    if not gmid then return nil, "invalid ts-refclk ptp value" end
    if version ~= "IEEE1588-2008" then
      return nil, "unrecognized ptp version '" .. version .. "' (expected IEEE1588-2008)"
    end
    if gmid ~= "traceable" then
      local count = 0
      for octet in gmid:gmatch("[^%-]+") do
        if not octet:match("^%x%x$") then return nil, "invalid ts-refclk ptp value" end
        count = count + 1
      end
      if count ~= 8 then return nil, "invalid ts-refclk ptp value" end
    end
    local domain = ptp_rest:match("^[^:]+:[^:]+:(.+)$")
    if domain then
      local d = tonumber(domain)
      if not d or d ~= math.floor(d) or d < 0 or d > 127 then
        return nil, "invalid ts-refclk ptp domain (must be 0-127)"
      end
    elseif gmid ~= "traceable" then
      return nil, "ts-refclk ptp domain is required when not using the 'traceable' form (ST 2110-10:2022 §8.2)"
    end
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
local _signed_int_pat = (P("-") + P("+"))^-1 * _digit_seq * P(-1)
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
-- ST 2110-20:2022 §7.6: 11 permitted TCS values. ST2115LOGS3 was added in
-- the 2022 revision (§7.6 final entry; §7.2 forces SSN=ST2110-20:2022 when
-- this value is used or when colorimetry=ALPHA).
local VALID_TCS = {
  ["SDR"]=true, ["PQ"]=true, ["HLG"]=true, ["LINEAR"]=true,
  ["BT2100LINPQ"]=true, ["BT2100LINHLG"]=true,
  ["ST2065-1"]=true, ["ST428-1"]=true, ["DENSITY"]=true,
  ["ST2115LOGS3"]=true, ["UNSPECIFIED"]=true,
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

-- RFC 4570 §3 a=source-filter: <filter> SP <nettype> SP <addrtype> SP <dest> SP <src>+
-- address-types = "*" / addrtype; addrtype = "IP4" / "IP6" / token.
-- When addrtype is "*", dest-address and src-list are FQDNs (no literal-IP check).
-- Some senders include a leading space after the ":" — accept it.
local _sf_filter   = P("incl") + P("excl")
local _sf_token    = (P(1) - P(" "))^1
local VALID_SOURCE_FILTER_PAT =
  P(" ")^-1
  * _sf_filter * P(" ")
  * P("IN") * P(" ")
  * (P("IP4") + P("IP6") + P("*")) * P(" ")
  * _sf_token                       -- destination address
  * (P(" ") * _sf_token)^1          -- one or more source addresses
  * P(-1)

-- M29 G2: validate source-filter dest and every src as a literal IPv4/IPv6
-- address matching the declared addrtype (ST 2110-10 §6.5 / RFC 4570).
local function valid_source_filter(value)
  if not VALID_SOURCE_FILTER_PAT:match(value) then
    return nil, "invalid a=source-filter format (RFC 4570)"
  end
  local trimmed = value:gsub("^%s+", "")
  local addrtype, rest = trimmed:match("^%S+ IN (IP[46]) (.+)$")
  if not addrtype then return true end
  local pat = (addrtype == "IP4") and _ipv4_addr_pat or _ipv6_addr_pat
  local idx = 0
  for tok in rest:gmatch("%S+") do
    idx = idx + 1
    if not pat:match(tok) then
      local which = (idx == 1) and "destination" or ("source #" .. (idx - 1))
      return nil, string.format(
        "invalid %s address in a=source-filter %s: %s", addrtype, which, tok)
    end
  end
  return true
end

-- Validate the address field of a c= line for ST 2110 media blocks (RFC 4566 +
-- ST 2110-10 §6.5). IPv4 multicast requires a TTL and must not fall within the
-- Local Network Control Block (224.0.0.0/24) or Internetwork Control Block
-- (224.0.1.0/24) forbidden ranges defined in RFC 5771. M29 G1: the address
-- portion (before any /suffix) must parse as a literal IPv4 or IPv6 address.
local function valid_connection_address(addr_type, addr)
  if addr_type == "IP6" then
    local ip6, rest6 = addr:match("^([^/]+)(.*)")
    if not ip6 then return nil, "invalid IPv6 address in c= line" end
    if not _ipv6_addr_pat:match(ip6) then
      return nil, "invalid IPv6 address syntax in c= line: " .. ip6
    end
    local is_mc6 = ip6:sub(1, 2):lower() == "ff"
    if is_mc6 then
      if rest6 == "" then return true end
      local n_str = rest6:match("^/(%d+)$")
      if not n_str then
        return nil, "IPv6 multicast c= suffix must be '/<integer>' (RFC 4566 §5.7)"
      end
      local n = tonumber(n_str)
      if not n or n < 1 then
        return nil, "IPv6 multicast c= suffix must be a positive integer"
      end
      return true
    end
    if rest6 ~= "" then
      return nil, "IPv6 unicast address must not include a '/' suffix"
    end
    return true
  end
  if addr_type ~= "IP4" then return true end
  local ip, rest = addr:match("^([^/]+)(.*)")
  if not ip or ip == "" then
    return nil, "invalid IPv4 address in c= line"
  end
  if not _ipv4_addr_pat:match(ip) then
    return nil, "invalid IPv4 address syntax in c= line: " .. ip
  end
  local o1 = tonumber(ip:match("^(%d+)%."))
  local is_mc = o1 and o1 >= 224 and o1 <= 239
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

-- Valid TP (transport profile) values per ST 2110-21 (uncompressed video, ST 2110-20).
local VALID_TP = { ["2110TPN"]=true, ["2110TPNL"]=true, ["2110TPW"]=true }
-- Valid TP values for compressed video per ST 2110-22:2022 §7.2 Table 1 (which
-- expanded the 2019 enum by adding 2110TPN). Both 2019 and 2022 SDPs are
-- accepted; rejecting a value the 2022 standard explicitly permits would be
-- spec-ungrounded.
local VALID_TP_22 = { ["2110TPN"]=true, ["2110TPNL"]=true, ["2110TPW"]=true }
-- Valid rtpmap encoding names for ST 2110-30/31 audio.
local VALID_AUDIO_ENC = { ["L16"]=true, ["L24"]=true, ["AM824"]=true }
-- Valid TSMODE values per ST 2110-10 §8.7 (RTP timestamp generation mode).
local VALID_TSMODE = { ["SAMP"]=true, ["NEW"]=true, ["PRES"]=true }

-- JPEG XS fmtp value enums per VSF TR-08 §8.1.1 and ISO/IEC 21122-2.
-- Cited from TR-10-15-Part1 §8/§9 (which incorporates TR-08 §8.1.1 by reference).
local VALID_JXS_PROFILE = {
  ["Unrestricted"]         = true,
  ["Light422.10"]          = true,
  ["Light444.12"]          = true,
  ["LightSubline422.10"]   = true,
  ["LightSubline444.12"]   = true,
  ["Main422.10"]           = true,
  ["Main444.12"]           = true,
  ["High444.12"]           = true,
  ["MLS.12"]               = true,
  ["LightBayer"]           = true,
  ["MainBayer"]            = true,
  ["HighBayer"]            = true,
  ["MLSBayer"]             = true,
}
local VALID_JXS_LEVEL = {
  ["Unrestricted"] = true,
  ["1k-1"] = true,
  ["2k-1"] = true,
  ["4k-1"] = true, ["4k-2"] = true, ["4k-3"] = true,
  ["8k-1"] = true, ["8k-2"] = true, ["8k-3"] = true,
  ["16k-1"] = true, ["16k-2"] = true, ["16k-3"] = true,
}
-- Sublevels per TR-10-15-Part1 §7.1 / ISO/IEC 21122-2. TR-10-15 explicitly
-- allows values above 4 bpp; Sublev5bpp is not a defined point.
local VALID_JXS_SUBLEVEL = {
  ["Unrestricted"] = true,
  ["Full"]         = true,
  ["Sublev12bpp"]  = true,
  ["Sublev9bpp"]   = true,
  ["Sublev6bpp"]   = true,
  ["Sublev4bpp"]   = true,
  ["Sublev3bpp"]   = true,
  ["Sublev2bpp"]   = true,
}
-- transmode (T-bit) and packetmode (K-bit) per RFC 9134 / TR-10-15-Part1 §9.
local VALID_JXS_BIT = { ["0"] = true, ["1"] = true }

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

-- Returns true for any signed integer (optional leading sign + one or more digits).
-- Used where the spec says only "an integer number" without a sign or zero
-- restriction — most notably ST 2110-21:2022 §8.2 CMAX.
local function valid_integer(value)
  if not _signed_int_pat:match(value) then return nil, "expected an integer" end
  return true
end

-- ST 2110-20:2017 §7.4.2: depth shall be one of {8, 10, 12, 16, 16f}.
local VALID_DEPTH = {
  ["8"]=true, ["10"]=true, ["12"]=true, ["16"]=true, ["16f"]=true,
}
local function valid_depth(value)
  if VALID_DEPTH[value] then return true end
  return nil, "invalid depth value '" .. tostring(value) ..
    "' (ST 2110-20 §7.4.2 permits 8, 10, 12, 16, 16f)"
end

-- ST 2110-20:2017 §7.2: width and height "Permitted values are integers between
-- 1 and 32767 inclusive." (Builder for either dimension; spec ref is the same.)
local function valid_pixel_dim(name)
  return function(value)
    if not _pos_int_pat:match(value) then return nil, "expected positive integer" end
    local n = tonumber(value)
    if n <= 0 then return nil, name .. " must be positive" end
    if n > 32767 then
      return nil, name .. " " .. value .. " exceeds 32767 (ST 2110-20 §7.2)"
    end
    return true
  end
end
local valid_width  = valid_pixel_dim("width")
local valid_height = valid_pixel_dim("height")

-- ST 2110-10 §6.4: Extended UDP Size Limit is 8960 octets. MAXUDP signals
-- that a sender exceeds the Standard UDP Size Limit (1460); the value SHALL
-- not exceed the Extended limit.
local function valid_maxudp(value)
  local ok, msg = valid_pos_int(value)
  if not ok then return nil, msg end
  if tonumber(value) > 8960 then
    return nil, "MAXUDP must not exceed Extended UDP Size Limit of 8960 (ST 2110-10 §6.4)"
  end
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

-- Returns the greatest common divisor of two positive integers.
local function gcd(a, b)
  while b ~= 0 do a, b = b, a % b end
  return a
end

-- Returns true for a PAR value in <W>:<H> format with both dimensions positive
-- and in lowest terms (ST 2110-20:2017 §7.3: "The smallest integer values
-- possible for width and height shall be used.").
local function valid_par(value)
  if not _par_pat:match(value) then
    return nil, "invalid PAR format (expected W:H with positive integers)"
  end
  local w, h = value:match("^(%d+):(%d+)$")
  local wn, hn = tonumber(w), tonumber(h)
  if wn == 0 or hn == 0 then
    return nil, "PAR dimensions must be positive"
  end
  if gcd(wn, hn) ~= 1 then
    return nil, string.format(
      "PAR %s is not in lowest terms (ST 2110-20 §7.3 requires smallest integer values)", value)
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

-- Validate the value of a mediaclk attribute per ST 2110-10 §8.3 (which defers
-- to IETF RFC 7273 §5) and TR-10-1 §10.5. Permitted forms:
--   "sender"                              (async; RFC 7273 §5.2)
--   "direct=<offset>"                     (RFC 7273 §5.4; offset SHALL be 0
--                                          at ST 2110 tier per §8.3)
--   "direct=<offset> rate=<int>/<int>"    (RFC 7273 §5.4 rate option, used
--                                          for pull-down e.g. 1000/1001)
-- Returns true on success, or nil + error message string on failure.
local _mc_pos_int  = R("09")^1
local _mc_rate_pat = P("rate=") * _mc_pos_int * P("/") * _mc_pos_int * P(-1)
local function valid_mediaclk(value)
  if value == "sender" then return true end
  local offset, rest = value:match("^direct=(%-?%d+)(.*)$")
  if not offset then return nil, "unrecognized mediaclk value" end
  if offset ~= "0" then
    return nil, "mediaclk direct offset must be 0 (ST 2110-10 §8.3)"
  end
  if rest == "" then return true end
  local rate_str = rest:match("^ (rate=.+)$")
  if not rate_str or not _mc_rate_pat:match(rate_str) then
    return nil, "invalid mediaclk rate (expected ' rate=<int>/<int>' per RFC 7273 §5.4)"
  end
  return true
end

-- ST 2110-20:2022 §7.1 fmtp formatting (strict): parameter entries SHALL be
-- separated by ";" followed by whitespace, AND there SHALL be no semicolon
-- after the last item. This is stricter than RFC 4566 §6 (which is silent on
-- inter-parameter spacing) and stricter than ST 2110-22:2022 §7.2 (which
-- explicitly makes the trailing space optional). Apply at the -20 branch only.
-- Returns true on conformance, or nil + error message string.
local function valid_st2110_20_fmtp_format(value)
  local params_str = value:match("^%d+%s+(.+)$")
  if not params_str then return true end  -- no params to check
  -- Forbid trailing semicolon (possibly followed by whitespace).
  if params_str:match("^.*;%s*$") then
    return nil, "no semicolon character after the last item (ST 2110-20:2022 §7.1)"
  end
  -- Every ';' SHALL be followed by whitespace (space or tab).
  local i = 1
  while true do
    local s = params_str:find(";", i, true)
    if not s then return true end
    local next_char = params_str:sub(s + 1, s + 1)
    if next_char ~= " " and next_char ~= "\t" then
      return nil, "fmtp ';' must be followed by whitespace (ST 2110-20:2022 §7.1)"
    end
    i = s + 1
  end
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

  -- ST 2110-10 §8.3: mediaclk SHALL be media-level only. Reject any session
  -- scope occurrence.
  for _, a in ipairs(sess_attrs) do
    if a.name == "mediaclk" then
      return nil, errors.new(
        "a=mediaclk must be media-level, not session-level",
        { field_path = "session.attributes[mediaclk]",
          spec_ref = "ST 2110-10 §8.3", code = "INVALID_VALUE" })
    end
  end

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

    -- Validate every a=source-filter on this media block (RFC 4570 / ST 2110-10 §8.4).
    for _, a in ipairs(mattrs) do
      if a.name == "source-filter" then
        local ok_sf, msg_sf = valid_source_filter(a.value or "")
        if not ok_sf then
          return attr_err(msg_sf, mpath, "source-filter",
            "ST 2110-10 §8.4 / RFC 4570", "INVALID_VALUE")
        end
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

    -- a=fmtp is NOT universally required by ST 2110-10:2022 §8. §8 covers SDP
    -- and contains no clause mandating fmtp on every RTP stream; presence
    -- requirements belong to the per-encoding specs (-20 / -22 / -41 require
    -- fmtp params; -30 / -31 / -40 do not require fmtp at all per IANA + the
    -- underlying RFCs). Per-encoding branches below enforce what they need.
    local fmtp = find_attr(mattrs, "fmtp")

    local rtp_pt = (rtpmap.value or ""):match("^(%d+)")
    if fmtp then
      local fmtp_pt = (fmtp.value or ""):match("^(%d+)")
      if rtp_pt ~= fmtp_pt then
        return attr_err(
          string.format("fmtp payload type %s does not match rtpmap payload type %s",
            tostring(fmtp_pt), tostring(rtp_pt)),
          mpath, "fmtp", "RFC 4566 §6", "INVALID_VALUE")
      end
    end
    -- ST 2110-10 §6.2: dynamic payload types SHALL be in 96..127.
    -- ST 2110 essence formats (raw, smpte291, L16/L24/AM824, jxsv, ST2110-41)
    -- have no IANA-static assignment, so the range is always required here.
    local pt_n = tonumber(rtp_pt)
    if not pt_n or pt_n < 96 or pt_n > 127 then
      return attr_err(
        string.format("RTP payload type %s out of dynamic range (must be 96-127)", tostring(rtp_pt)),
        mpath, "rtpmap", "ST 2110-10 §6.2", "INVALID_VALUE")
    end

    local enc, clock_rate = rtpmap_parse(rtpmap.value or "")

    local params = {}
    if fmtp then
      local p, fmtp_err = fmtp_params(fmtp.value or "")
      if not p then
        return attr_err("invalid fmtp: " .. fmtp_err, mpath, "fmtp", "RFC 4566 §6", "INVALID_VALUE")
      end
      params = p
    end

    if enc == "smpte291" then
      -- ST 2110-40:2023 §7 defers SDP construction to RFC 8331; the IANA
      -- registration is `video/smpte291`, so the m= media name SHALL be
      -- "video" (RFC 8331 §4 / RFC 4855 §1).
      if m.media ~= "video" then
        return attr_err(
          string.format("smpte291 requires m=video (got m=%s) per RFC 8331 §4", tostring(m.media)),
          mpath, "rtpmap", "RFC 8331 §4", "INVALID_VALUE")
      end
      -- ST 2110-40: ancillary data (RFC 8331 / SMPTE ST 2110-40:2023)
      if clock_rate ~= 90000 then
        return attr_err(
          string.format("rtpmap clock rate must be 90000 for smpte291 (got %s)", tostring(clock_rate)),
          mpath, "rtpmap", "ST 2110-40 §7.2", "INVALID_VALUE")
      end
      -- DID_SDID is OPTIONAL. ST 2110-40:2023 §7 (Session Description Protocol)
      -- does not mention DID_SDID at all; the SDP "shall be constructed as
      -- described in IETF RFC 8331, subject also to the provisions of SMPTE
      -- ST 2110-10." RFC 8331's media-type registration lists DID_SDID as
      -- optional, with the explicit note that its absence signals that
      -- receivers must inspect packets to determine DID/SDID. May appear
      -- multiple times — validate format on every occurrence when present.
      if fmtp then
        for v in (fmtp.value or ""):gmatch("DID_SDID=([^;%s]+)") do
          local dok, derr = valid_did_sdid(v)
          if not dok then
            return attr_err("invalid DID_SDID: " .. derr, mpath, "fmtp", "RFC 8331 §4", "INVALID_VALUE")
          end
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
      -- ST 2110-40:2023 §7: TM (Transmission Model) is OPTIONAL with two
      -- defined values. "Senders implementing the Low-Latency Transmission
      -- Model shall signal a Format Specific Parameter TM with the value
      -- LLTM in the SDP." "Senders implementing the Compatible Transmission
      -- Model may signal a Format Specific Parameter TM with the value CTM
      -- in the SDP." Receivers default to CTM when absent.
      local tm = params["TM"]
      if tm ~= nil and tm ~= true then
        local tm_str = tostring(tm)
        if tm_str ~= "LLTM" and tm_str ~= "CTM" then
          return attr_err("invalid TM value '" .. tm_str .. "' (must be 'LLTM' or 'CTM')",
            mpath, "fmtp", "ST 2110-40:2023 §7", "INVALID_VALUE")
        end
      end
      -- ST 2110-40:2023 §7: SSN is REQUIRED. "Senders implementing this
      -- standard shall signal a Format Specific Parameter SSN with the
      -- value ST2110-40:2018 unless they are signaling Format Specific
      -- Parameter TM, in which case they shall signal the value
      -- ST2110-40:2023." Value is tied to TM presence.
      local ssn = params["SSN"]
      if ssn == nil or ssn == true then
        return attr_err("fmtp missing required 'SSN' parameter for smpte291",
          mpath, "fmtp", "ST 2110-40:2023 §7")
      end
      local ssn_str = tostring(ssn)
      local expected_ssn = (tm and tm ~= true) and "ST2110-40:2023" or "ST2110-40:2018"
      if ssn_str ~= expected_ssn then
        return attr_err(string.format(
          "invalid SSN value '%s' (expected '%s' %s)", ssn_str, expected_ssn,
          (tm and tm ~= true) and "when TM is signaled" or "when TM is absent"),
          mpath, "fmtp", "ST 2110-40:2023 §7", "INVALID_VALUE")
      end
      -- ST 2110-40:2023 §7: exactframerate is REQUIRED. "All Senders shall
      -- signal the Format Specific Parameter exactframerate as defined in
      -- SMPTE ST 2110-20:2022 Clause 7.2 to indicate the frame rate related
      -- to the ANC data in the stream."
      local efr = params["exactframerate"]
      if efr == nil or efr == true then
        return attr_err("fmtp missing required 'exactframerate' parameter for smpte291",
          mpath, "fmtp", "ST 2110-40:2023 §7")
      end
      local efrok, efrmsg = valid_exactframerate(tostring(efr))
      if not efrok then
        return attr_err("exactframerate: " .. efrmsg, mpath, "fmtp", "ST 2110-40:2023 §7", "INVALID_VALUE")
      end
      -- ST 2110-40:2023 §7: TROFF, when signaled, uses ST 2110-21's
      -- definition. Presence is conditional on TR_OFFSETANC differing from
      -- TRO_DEFAULT for the prevailing video format — a runtime property
      -- not observable from SDP alone — so only validate the value form
      -- when present (positive integer per ST 2110-21 §8).
      local troff = params["TROFF"]
      if troff ~= nil and troff ~= true then
        local tok, tmsg = valid_pos_int(tostring(troff))
        if not tok then
          return attr_err("TROFF: " .. tmsg, mpath, "fmtp", "ST 2110-40:2023 §7 / ST 2110-21", "INVALID_VALUE")
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
      -- Mandatory jxsv fmtp parameters at the ST 2110-22 tier:
      --   - width, height, TP  per ST 2110-22:2022 §7.2 Table 1 ("shall include")
      --                        + §5.3 SHALL for TP=2110TPN/2110TPNL/2110TPW
      --   - packetmode         per IANA video/jxsv registration (RFC 9134 §7.1)
      -- All other parameters listed in RFC 9134 §7.1 (sampling, depth,
      -- exactframerate, TCS, colorimetry, RANGE, interlace, segmented,
      -- transmode, profile, level, sublevel, etc.) are OPTIONAL. Format is
      -- validated when present; absence is accepted.
      local jxs_req = {
        { "width",      valid_pos_int },
        { "height",     valid_pos_int },
        { "TP",         function(v) return valid_enum(v, VALID_TP_22,   "TP")         end },
        { "packetmode", function(v) return valid_enum(v, VALID_JXS_BIT, "packetmode") end },
      }
      -- Optional jxsv fmtp parameters, validated when present (RFC 9134 §7.1).
      local jxs_opt = {
        { "sampling",       function(v) return valid_enum(v, VALID_SAMPLING,    "sampling")    end },
        { "exactframerate", valid_exactframerate },
        { "depth",          valid_pos_int },
        { "TCS",            function(v) return valid_enum(v, VALID_TCS,         "TCS")         end },
        { "colorimetry",    function(v) return valid_enum(v, VALID_COLORIMETRY, "colorimetry") end },
      }
      -- profile, level, sublevel, and transmode are OPTIONAL in SDP at every
      -- tier. ST 2110-22:2022 §7.2 Table 1 (mandatory) lists only
      -- width/height/TP. IANA video/jxsv requires only `packetmode` besides
      -- rate. IPMX JPEG-XS Video Profile §6.1.4 lists these fields for the
      -- RTCP JPEG-XS Media Info Block (type 0x0003) — Media Info Blocks are
      -- out of scope for this SDP validator (see CLAUDE.md). TR-10-11 §10
      -- defers SDP construction to ST 2110-22 §7. Validate value formats
      -- when present; do not require presence.
      local transmode_v = params["transmode"]
      if transmode_v ~= nil and transmode_v ~= true then
        local vok, vmsg = valid_enum(tostring(transmode_v), VALID_JXS_BIT, "transmode")
        if not vok then
          return attr_err("transmode: " .. vmsg, mpath, "fmtp", "ST 2110-22 §7.2", "INVALID_VALUE")
        end
      end
      local profile_v = params["profile"]
      if profile_v ~= nil and profile_v ~= true then
        local vok, vmsg = valid_enum(tostring(profile_v), VALID_JXS_PROFILE, "profile")
        if not vok then
          return attr_err("profile: " .. vmsg, mpath, "fmtp", "ST 2110-22 §7.2", "INVALID_VALUE")
        end
      end
      local level_v = params["level"]
      if level_v ~= nil and level_v ~= true then
        local vok, vmsg = valid_enum(tostring(level_v), VALID_JXS_LEVEL, "level")
        if not vok then
          return attr_err("level: " .. vmsg, mpath, "fmtp", "ST 2110-22 §7.2", "INVALID_VALUE")
        end
      end
      local sublevel_v = params["sublevel"]
      if sublevel_v ~= nil and sublevel_v ~= true then
        local vok, vmsg = valid_enum(tostring(sublevel_v), VALID_JXS_SUBLEVEL, "sublevel")
        if not vok then
          return attr_err("sublevel: " .. vmsg, mpath, "fmtp", "ST 2110-22 §7.2", "INVALID_VALUE")
        end
      end
      -- PM (Packing Mode) is NOT a ST 2110-22 parameter. ST 2110-22:2019 §7.2
      -- Table 1 lists only width / height / TP as mandatory format-specific
      -- parameters; ST 2110-22:2022 §7.2 Table 1 is identical. PM (2110GPM /
      -- 2110BPM) is the uncompressed-video packing-mode marker defined by
      -- ST 2110-20 §7.2; for jxsv the analogous control is `packetmode` (IANA
      -- video/jxsv required parameter, per RFC 9134 §4.3).
      --
      -- SSN is OPTIONAL for jxsv. ST 2110-22:2022 §7.2 Table 2 marks SSN as
      -- optional with values ST2110-22:2019 or ST2110-22:2022; ST 2110-22:2019
      -- did not define SSN at all. Validate format only when present.
      local ssn = params["SSN"]
      if ssn ~= nil and ssn ~= true then
        if not _ssn22_pat:match(tostring(ssn)) then
          return attr_err("invalid SSN value (expected ST2110-22:YYYY, e.g. ST2110-22:2019 or ST2110-22:2022)",
            mpath, "fmtp", "ST 2110-22 §7.2", "INVALID_VALUE")
        end
      end
      for _, ck in ipairs(jxs_req) do
        local key, fn = ck[1], ck[2]
        local val = params[key]
        if val == nil then
          return attr_err("fmtp missing required '" .. key .. "' parameter for jxsv",
            mpath, "fmtp", "ST 2110-22 §7.2")
        end
        local vok, vmsg = fn(tostring(val))
        if not vok then
          return attr_err(key .. ": " .. vmsg, mpath, "fmtp", "ST 2110-22 §7.2", "INVALID_VALUE")
        end
      end
      for _, ck in ipairs(jxs_opt) do
        local key, fn = ck[1], ck[2]
        local val = params[key]
        if val ~= nil and val ~= true then
          local vok, vmsg = fn(tostring(val))
          if not vok then
            return attr_err(key .. ": " .. vmsg, mpath, "fmtp", "ST 2110-22 §7 / RFC 9134 §7.1", "INVALID_VALUE")
          end
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
      -- Optional: MAXUDP (1..8960 per ST 2110-10 §6.4), CMAX (any integer per
      -- ST 2110-21:2022 §8.2 "expressed as an integer number" — referenced by
      -- ST 2110-22:2022 §7.2 Table 2).
      local maxudp_v = params["MAXUDP"]
      if maxudp_v ~= nil and maxudp_v ~= true then
        local vok, vmsg = valid_maxudp(tostring(maxudp_v))
        if not vok then
          return attr_err("MAXUDP: " .. vmsg, mpath, "fmtp", "ST 2110-22 §7", "INVALID_VALUE")
        end
      end
      local cmax_v = params["CMAX"]
      if cmax_v ~= nil and cmax_v ~= true then
        local vok, vmsg = valid_integer(tostring(cmax_v))
        if not vok then
          return attr_err("CMAX: " .. vmsg, mpath, "fmtp", "ST 2110-21:2022 §8.2", "INVALID_VALUE")
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
      -- ST 2110-20:2022 §7.1: separator SHALL be ";" followed by whitespace,
      -- with no semicolon after the last item. Validate the raw fmtp string
      -- (per the strict 2022 wording — see Streampunk sdpoker Issue #33).
      if fmtp then
        local sfok, sfmsg = valid_st2110_20_fmtp_format(fmtp.value or "")
        if not sfok then
          return attr_err(sfmsg, mpath, "fmtp", "ST 2110-20:2022 §7.1", "INVALID_VALUE")
        end
      end
      -- All nine required fmtp parameters (ST 2110-20 §7.2): presence then value.
      -- Each entry: { key, validator, spec_ref (optional override of §7.2) }.
      local video_checks = {
        { "sampling",       function(v) return valid_enum(v, VALID_SAMPLING,    "sampling")    end },
        { "width",          valid_width },   -- §7.2: integer 1..32767
        { "height",         valid_height },  -- §7.2: integer 1..32767
        { "exactframerate", valid_exactframerate },
        { "depth",          valid_depth, "ST 2110-20 §7.4.2" },  -- M30 G1: enum {8,10,12,16,16f}
        { "TCS",            function(v) return valid_enum(v, VALID_TCS,         "TCS")         end },
        { "colorimetry",    function(v) return valid_enum(v, VALID_COLORIMETRY, "colorimetry") end },
        { "PM",             function(v) return valid_enum(v, VALID_PM,          "PM")          end },
        { "SSN",            function(v)
            if _ssn20_pat:match(v) then return true end
            return nil, "invalid SSN value (expected ST2110-20:YYYY, e.g. ST2110-20:2022)"
          end },
      }
      for _, ck in ipairs(video_checks) do
        local key, fn, ref = ck[1], ck[2], ck[3] or "ST 2110-20 §7.2"
        local val = params[key]
        if val == nil then
          return attr_err("fmtp missing required '" .. key .. "' parameter for video",
            mpath, "fmtp", ref)
        end
        local vok, vmsg = fn(tostring(val))
        if not vok then
          return attr_err(vmsg, mpath, "fmtp", ref, "INVALID_VALUE")
        end
      end
      local range_val = params["RANGE"]
      if range_val ~= nil then
        local vok, vmsg = valid_enum(tostring(range_val), VALID_RANGE, "RANGE")
        if not vok then
          return attr_err(vmsg, mpath, "fmtp", "ST 2110-20 §7.2", "INVALID_VALUE")
        end
      end
      -- TROFF and CMAX semantics are defined by ST 2110-21 only in the context
      -- of a transport profile (TP). Presence without TP is meaningless.
      if (params["TROFF"] or params["CMAX"]) and not params["TP"] then
        return attr_err("TROFF/CMAX require TP to also be present (ST 2110-21 §8)",
          mpath, "fmtp", "ST 2110-21 §8")
      end
      -- M30 G4: ST 2110-20 §7.3 defines interlace/segmented purely by parameter
      -- name presence (no <value> form). Bare flag → fmtp_params stores `true`;
      -- a `name=value` form stores a string. Reject the latter.
      for _, flag in ipairs({ "interlace", "segmented" }) do
        if params[flag] ~= nil and params[flag] ~= true then
          return attr_err(flag .. " must be a bare flag, not name=value (ST 2110-20 §7.3)",
            mpath, "fmtp", "ST 2110-20 §7.3", "INVALID_VALUE")
        end
      end
      -- ST 2110-20:2017 §7.3: "Signaling of [segmented] without the interlace
      -- parameter is forbidden." (PsF requires interlace to be set as well.)
      if params["segmented"] and not params["interlace"] then
        return attr_err("segmented requires interlace to also be present (ST 2110-20 §7.3)",
          mpath, "fmtp", "ST 2110-20 §7.3")
      end
      -- M30 G9: ST 2110-20 §6.3.3 — "The Extended UDP size limit defined in
      -- SMPTE ST 2110-10 shall not be used in the Block Packing Mode."
      -- MAXUDP signals operation beyond the Standard limit, so its presence
      -- with PM=2110BPM violates the §6.3.3 prohibition.
      if params["PM"] == "2110BPM" and params["MAXUDP"] ~= nil then
        return attr_err(
          "MAXUDP must not be signaled with PM=2110BPM (ST 2110-20 §6.3.3 forbids Extended UDP size in BPM)",
          mpath, "fmtp", "ST 2110-20 §6.3.3", "INVALID_VALUE")
      end
      -- Optional ST 2110-20 fmtp params that have defined value formats.
      -- TSMODE / TSDELAY are from ST 2110-10 §8.7 (RTP timestamp generation).
      -- Each entry: { key, validator, spec_ref (optional override of §7.2) }.
      local video_opt_checks = {
        { "TP",      function(v) return valid_enum(v, VALID_TP, "TP") end },
        { "MAXUDP",  valid_maxudp },
        { "PAR",     valid_par },
        -- ST 2110-21:2022 §8.2 — TROFF "is expressed as a positive integer
        -- number of microseconds". (§6.2 separately permits the underlying
        -- TROFFSET to be zero; the SDP value-form §8.2 SHALL says positive.)
        { "TROFF",   valid_pos_int,  "ST 2110-21:2022 §8.2" },
        -- ST 2110-21:2022 §8.2 — CMAX "is expressed as an integer number"
        -- (no sign or zero restriction). §7.1 formula bounds CINST (§6.6.1)
        -- and is therefore an upper bound, not a lower bound on the
        -- SDP-signaled value, and requires NPACKETS context to compute.
        { "CMAX",    valid_integer,  "ST 2110-21:2022 §8.2" },
        { "TSMODE",  function(v) return valid_enum(v, VALID_TSMODE, "TSMODE") end, "ST 2110-10 §8.7" },
        -- ST 2110-10:2022 §8.7 — TSDELAY "is represented as a decimal positive
        -- integer number of microseconds". (Annex B Informative SDP example
        -- shows TSDELAY=0; non-normative — §8.7 SHALL governs.)
        { "TSDELAY", valid_pos_int,  "ST 2110-10 §8.7" },
      }
      for _, ck in ipairs(video_opt_checks) do
        local key, fn, ref = ck[1], ck[2], ck[3] or "ST 2110-20 §7.2"
        local val = params[key]
        if val ~= nil and val ~= true then
          local vok, vmsg = fn(tostring(val))
          if not vok then
            return attr_err(key .. ": " .. vmsg, mpath, "fmtp", ref, "INVALID_VALUE")
          end
        end
      end

    elseif m.media == "audio" then
      -- ST 2110-30 §6.1 mandates L16/L24; ST 2110-31 adds AM824. Other encodings
      -- are not covered by the standard for the audio media type.
      if enc and not VALID_AUDIO_ENC[enc] then
        return attr_err(
          string.format("rtpmap encoding '%s' is not valid for ST 2110-30 audio (must be L16, L24, or AM824)",
            tostring(enc)),
          mpath, "rtpmap", "ST 2110-30 §7.1", "INVALID_VALUE")
      end
      -- Clock rate: ST 2110-30 §6.1 mandates 48 kHz and permits 44.1/96 kHz, then
      -- says "Other sampling frequencies … are out of scope of this standard."
      -- "Out of scope" is not "forbidden" (no "shall not"), so any well-formed
      -- positive rate is accepted (M30 G5 — conformance principle).
      -- Channel count is part of RFC 4566 rtpmap grammar (RFC 3551 §6); zero or
      -- missing makes the stream undefined. Spec does not impose an upper bound.
      local ch_s = (rtpmap.value or ""):match("^%d+%s+%S+/%d+/(%d+)$")
      if not ch_s then
        return attr_err(
          "rtpmap missing channel count for audio (RFC 3551 §6: encoding/rate/channels)",
          mpath, "rtpmap", "RFC 3551 §6")
      end
      local ch = tonumber(ch_s)
      if not ch or ch < 1 then
        return attr_err(
          string.format("rtpmap channel count %s must be positive", ch_s),
          mpath, "rtpmap", "RFC 3551 §6", "INVALID_VALUE")
      end
      -- Validate a=ptime if present (ST 2110-30 §7.2 recommends ptime=1 ms).
      local ptime_attr = find_attr(mattrs, "ptime")
      local ptime_ms
      if ptime_attr then
        ptime_ms = tonumber(ptime_attr.value or "")
        if not ptime_ms or ptime_ms <= 0 then
          return attr_err("invalid a=ptime value (expected positive number)",
            mpath, "ptime", "ST 2110-30 §7.2", "INVALID_VALUE")
        end
      end
      -- Packet payload fit (ST 2110-10 §6.4 + ST 2110-30 §6.2.2). When ptime is
      -- known, verify channels × samples-per-packet × bytes-per-sample fits in
      -- the available UDP payload (MAXUDP if signaled, else the 1460 Standard
      -- Limit). RTP fixed header (12 B) is subtracted from the UDP payload.
      if ptime_ms then
        local bps = (enc == "L16" and 2) or (enc == "L24" and 3) or (enc == "AM824" and 4)
        if bps then
          local samples_per_packet = clock_rate * ptime_ms / 1000
          local maxudp = tonumber(tostring(params["MAXUDP"] or "")) or 1460
          local rtp_payload_limit = maxudp - 12
          local needed = ch * samples_per_packet * bps
          if needed > rtp_payload_limit then
            return attr_err(
              string.format(
                "audio packet RTP payload %d B (%d ch × %g samples × %d B) exceeds limit %d B (UDP %d − RTP 12); raise MAXUDP or reduce ptime/channels",
                needed, ch, samples_per_packet, bps, rtp_payload_limit, maxudp),
              mpath, "fmtp", "ST 2110-10 §6.4", "INVALID_VALUE")
          end
        end
      end
      -- ST 2110-30:2017 §6.2.2: "If channel order is signaled in the SDP, the
      -- syntax of IETF RFC 3190 for the parameter channel-order shall be used."
      -- "If the channel-order parameter is not present, the audio channels
      -- shall be treated as Undefined." Absence is explicitly defined; the
      -- parameter is optional. Validate format only when present.
      local co = params["channel-order"]
      if co ~= nil and co ~= true then
        local cok, cmsg = valid_channel_order(tostring(co))
        if not cok then
          return attr_err(cmsg, mpath, "fmtp", "ST 2110-30 §6.2.2", "INVALID_VALUE")
        end
      end
    end
  end

  -- RFC 5888 §5: a=group value grammar (semantics + identification-tags),
  -- both required to be RFC 4566 tokens. Validate every a=group attribute
  -- regardless of semantics, before any DUP-specific checks.
  for _, attr in ipairs(doc.session.attributes or {}) do
    if attr.name == "group" then
      local gok, gerr = valid_group_value(attr.value or "")
      if not gok then
        return nil, errors.new("invalid a=group: " .. gerr, {
          field_path = "session.attributes[group]",
          spec_ref   = "RFC 5888 §5", code = "INVALID_VALUE",
        })
      end
    end
  end

  -- a=mid format (RFC 5888 §4: identification-tag = token) and uniqueness
  -- (RFC 5888 §8.1).
  local seen_mid = {}
  for i, m in ipairs(doc.media) do
    local mid_attr = find_attr(m.attributes or {}, "mid")
    if mid_attr and mid_attr.value then
      local mok, merr = valid_mid_value(mid_attr.value)
      if not mok then
        return nil, errors.new("invalid a=mid: " .. merr, {
          field_path = string.format("media[%d].attributes[mid]", i),
          spec_ref   = "RFC 5888 §4", code = "INVALID_VALUE",
        })
      end
      if seen_mid[mid_attr.value] then
        return nil, errors.new(
          "duplicate a=mid value '" .. mid_attr.value .. "'",
          { field_path = string.format("media[%d].attributes[mid]", i),
            spec_ref = "RFC 5888 §8.1", code = "INVALID_VALUE" })
      end
      seen_mid[mid_attr.value] = true
    end
  end

  -- Validate a=group:DUP grouping per ST 2110-10 §8.5 + RFC 7104.
  -- Rules enforced:
  --   * Same media type across legs.
  --   * Same rtpmap encoding name and clock rate across legs (M6) — ST 2022-7
  --     requires identical streams.
  --   * No two legs share BOTH source address and destination address (H4) —
  --     §8.5 "SHALL NOT use both identical source addresses and identical
  --     destination addresses at the same time."
  local function leg_addrs(block)
    local conn = block.connection or (doc.session and doc.session.connection)
    local dst = conn and conn.address or ""
    -- Source address is taken from the first a=source-filter line on the leg.
    -- Without source-filter, the source is unconstrained ("*") which cannot
    -- match identically across legs by this rule (empty string sentinel).
    local src = ""
    for _, a in ipairs(block.attributes or {}) do
      if a.name == "source-filter" then
        local s = (a.value or ""):match("^%s*%S+%s+%S+%s+%S+%s+%S+%s+(%S+)$")
        if s then src = s end
        break
      end
    end
    return src, dst
  end
  local dup_ok, dup_err = each_dup_group(doc, "ST 2110-10 §8.5", function(legs)
    local base_type   = legs[1].block.media
    local base_rtpmap = find_attr(legs[1].block.attributes or {}, "rtpmap")
    local base_fmtp   = find_attr(legs[1].block.attributes or {}, "fmtp")
    local base_enc, base_rate = rtpmap_parse((base_rtpmap and base_rtpmap.value) or "")
    local base_pt   = (base_rtpmap and base_rtpmap.value or ""):match("^(%d+)")
    local base_src, base_dst = leg_addrs(legs[1].block)
    for j = 2, #legs do
      if legs[j].block.media ~= base_type then
        return nil, errors.new(
          "a=group:DUP legs must have the same media type",
          { field_path = "session.attributes[group]",
            spec_ref = "ST 2110-10 §8.5", code = "INVALID_VALUE" })
      end
      local rm = find_attr(legs[j].block.attributes or {}, "rtpmap")
      local enc, rate = rtpmap_parse((rm and rm.value) or "")
      if enc ~= base_enc or rate ~= base_rate then
        return nil, errors.new(
          "a=group:DUP legs must have the same rtpmap encoding and clock rate",
          { field_path = "session.attributes[group]",
            spec_ref = "ST 2110-10 §8.5", code = "INVALID_VALUE" })
      end
      -- ST 2022-7 §6: DUP legs SHALL use the same RTP payload type number.
      local pt = (rm and rm.value or ""):match("^(%d+)")
      if pt ~= base_pt then
        return nil, errors.new(
          "a=group:DUP legs must use the same RTP payload type number (ST 2022-7 §6)",
          { field_path = "session.attributes[group]",
            spec_ref = "ST 2110-10 §8.5", code = "INVALID_VALUE" })
      end
      -- Identical RTP payload data (ST 2022-7 §6) implies identical essence
      -- parameters. Compare full fmtp value strings; differences in any
      -- essence field (resolution, sampling, channel-order, etc.) fail.
      local fm = find_attr(legs[j].block.attributes or {}, "fmtp")
      local base_fmtp_v = base_fmtp and base_fmtp.value or ""
      local leg_fmtp_v  = fm and fm.value or ""
      if base_fmtp_v ~= leg_fmtp_v then
        return nil, errors.new(
          "a=group:DUP legs must have identical fmtp essence parameters (ST 2022-7 §6)",
          { field_path = "session.attributes[group]",
            spec_ref = "ST 2110-10 §8.5", code = "INVALID_VALUE" })
      end
      local src, dst = leg_addrs(legs[j].block)
      if dst ~= "" and dst == base_dst and src == base_src then
        return nil, errors.new(
          "a=group:DUP legs must not use identical source and destination addresses (ST 2110-10 §8.5)",
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

-- TR-10-10 §8 a=infoframe: <port> SSN=ST2110-41:YYYY;DIT=100100
-- Port is the UDP destination for the InfoFrame stream (associated media port + 3).
-- DIT 100100 is the SMPTE-allocated Data Item Type for HDMI InfoFrame.
local _ifr_year = R("09") * R("09") * R("09") * R("09")
local VALID_INFOFRAME_PAT =
  R("09")^1 * P(" ")
  * P("SSN=ST2110-41:") * _ifr_year * P(";")
  * P("DIT=100100") * P(-1)

local function valid_infoframe(value)
  if VALID_INFOFRAME_PAT:match(value) then return true end
  if not value:match("^%d+%s") then
    return nil, "invalid a=infoframe (expected '<port> SSN=ST2110-41:YYYY;DIT=100100')"
  end
  if not value:match("SSN=ST2110%-41:%d%d%d%d") then
    return nil, "invalid a=infoframe SSN (must be ST2110-41:YYYY)"
  end
  if not value:match("DIT=100100") then
    return nil, "invalid a=infoframe DIT (must be 100100 for HDMI per TR-10-10 §8)"
  end
  return nil, "invalid a=infoframe format"
end

-- RFC 5285 §7 a=extmap: mapentry SP extensionname [SP extensionattributes]
-- extensionattributes = byte-string (RFC 4566 §9): 1*(%x01-09/%x0B-0C/%x0E-FF),
-- i.e. any byte except NUL, LF, CR.
local _extmap_id  = R("09")^1
local _extmap_dir = P("sendonly") + P("recvonly") + P("sendrecv") + P("inactive")
local _uri_scheme = R("az","AZ") * (R("az","AZ","09") + S("+-.")  )^0
local _uri_body   = (P(1) - S(" \t"))^1
local _byte_string = (P(1) - S("\0\r\n"))^1
local VALID_EXTMAP_PAT = _extmap_id
                       * (P("/") * _extmap_dir)^-1
                       * P(" ")
                       * _uri_scheme * P(":") * _uri_body
                       * (P(" ") * _byte_string)^-1
                       * P(-1)

-- TR-10-13 §20.1: PEP IV-Counter extmap URIs SHALL declare direction=sendonly.
local PEP_EXTMAP_URIS = {
  ["urn:ietf:params:rtp-hdrext:PEP-Full-IV-Counter"]  = true,
  ["urn:ietf:params:rtp-hdrext:PEP-Short-IV-Counter"] = true,
}

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

-- Extract the direction (or nil) and URI from a valid extmap value.
-- Caller is expected to have run valid_extmap first.
local function extmap_dir_uri(value)
  local direction, uri = value:match("^%d+/(%S+)%s+(%S+)")
  if direction then return direction, uri end
  return nil, value:match("^%d+%s+(%S+)")
end

-- TR-10-13 §20.1: if extmap URI is a PEP IV-Counter URN, direction must be
-- sendonly. Returns true on success or nil + error message string.
local function pep_extmap_direction_ok(value)
  local direction, uri = extmap_dir_uri(value)
  if uri and PEP_EXTMAP_URIS[uri] and direction ~= "sendonly" then
    return nil, "PEP IV-Counter extmap must declare /sendonly direction"
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

-- Valid protocol values for a=privacy, partitioned by transport.
-- RTP streams use RTP/RTP_KV (TR-10-13 §13); USB streams use USB_KV (TR-10-14 §14).
local PRIVACY_PROTOCOLS_RTP = { RTP = true, RTP_KV = true }
local PRIVACY_PROTOCOLS_USB = { USB_KV = true }

-- Exact hex-digit counts per privacy parameter (TR-10-13 §13).
-- iv 64-bit, key_generator 128-bit, key_version 32-bit, key_id 64-bit.
local PRIVACY_HEX_LEN = {
  iv            = 16,
  key_generator = 32,
  key_version   = 8,
  key_id        = 16,
}

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

-- Validate an a=privacy attribute value per VSF TR-10-13 §13 (RTP) /
-- TR-10-14 §14 (USB). Format:
--   protocol=<p>; mode=<m>; iv=<iv>; key_generator=<kg>; key_version=<kv>; key_id=<kid>
-- Pass usb_only=true to apply the USB transport rules (protocol must be USB_KV;
-- mode must be one of the four AAD variants).
local function valid_privacy(value, usb_only)
  local trimmed_value = value:match("^%s*(.-)%s*$")
  -- TR-10-13 §13: "There shall be no semicolon after the last parameter."
  if trimmed_value:sub(-1) == ";" then
    return nil, "trailing semicolon is not permitted after the last parameter"
  end
  local params = {}
  for kv in trimmed_value:gmatch("[^;]+") do
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
  local protocols = usb_only and PRIVACY_PROTOCOLS_USB or PRIVACY_PROTOCOLS_RTP
  if not protocols[params.protocol] then
    return nil, usb_only
      and "invalid protocol '" .. params.protocol .. "' (USB requires USB_KV)"
      or  "invalid protocol '" .. params.protocol .. "' (must be RTP or RTP_KV)"
  end
  local modes = usb_only and PRIVACY_USB_MODES or PRIVACY_MODES
  if not modes[params.mode] then
    return nil, "invalid mode '" .. params.mode .. "'"
  end
  -- Each hex parameter must be hexadecimal AND of the exact bit length defined
  -- in TR-10-13 §13. Iterating a fixed-order list keeps error messages stable.
  for _, f in ipairs({ "iv", "key_generator", "key_version", "key_id" }) do
    local v = params[f]
    if not v:match("^%x+$") then
      return nil, "invalid " .. f .. " value (must be hexadecimal)"
    end
    if #v ~= PRIVACY_HEX_LEN[f] then
      return nil, string.format(
        "invalid %s length (must be %d hex digits, got %d)", f, PRIVACY_HEX_LEN[f], #v)
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
-- IPMX fmtp marker (TR-10-1 §10.1), a=hkep format (TR-10-5 §10), a=privacy
-- format (TR-10-13 §13), FEC params (TR-10-6 §7.6), and IPMX-specific
-- transport rules. USB blocks (m=application with TCP transport, TR-10-14)
-- bypass ST 2110 media-block checks.
-- @param doc table  SDP document table.
-- @return true  on success.
-- @return nil, err  on failure; err includes field_path and spec_ref.
function ipmx.validate(doc)
  -- IPMX is a media transport profile built on ST 2110-10 §7 / §8.1, which
  -- describes the use of SDP to signal media streams. An SDP with zero media
  -- blocks isn't describing any IPMX stream. Mirrors the equivalent ST 2110
  -- check so the IPMX RFC-4566 fallback path (USB-only) doesn't silently
  -- accept empty SDPs.
  if #doc.media < 1 then
    return nil, errors.new("IPMX requires at least one media block",
      { field_path = "media", spec_ref = "ST 2110-10 §7" })
  end

  -- Two predicates over media blocks:
  --   non_rtp_set — any application block not on RTP/AVP; bypasses ST 2110
  --                 RTP-specific validation (a=rtpmap, a=fmtp IPMX marker, etc.).
  --   usb_set     — strictly `m=application <port> TCP usb` per TR-10-14 §14;
  --                 subject to additional rules (a=setup:passive, USB_KV privacy).
  -- usb_set ⊆ non_rtp_set.
  local non_rtp_set, usb_set = {}, {}
  for i, m in ipairs(doc.media) do
    if m.media == "application" and type(m.proto) == "string"
       and m.proto ~= "RTP/AVP" then
      non_rtp_set[i] = true
      if m.proto == "TCP" and m.fmts and m.fmts[1] == "usb" then
        usb_set[i] = true
      end
    end
  end

  -- Build a filtered media list (RTP only) for ST 2110 validation.
  local rtp_media = {}
  for i, m in ipairs(doc.media) do
    if not non_rtp_set[i] then rtp_media[#rtp_media + 1] = m end
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

  -- M9: a=infoframe SHALL be a session attribute (TR-10-10 §8).
  for i, m in ipairs(doc.media) do
    if find_attr(m.attributes or {}, "infoframe") then
      return attr_err(
        "a=infoframe must be a session-level attribute, not media-level",
        string.format("media[%d]", i), "infoframe", "TR-10-10 §8", "INVALID_VALUE")
    end
  end

  -- H3/M8: Validate every session-level a=infoframe — format, port = m.port + 3
  -- for some media block, and per-port uniqueness across infoframe lines.
  local infoframe_ports_seen = {}
  for _, attr in ipairs(doc.session.attributes or {}) do
    if attr.name == "infoframe" then
      local value = attr.value or ""
      local ok, msg = valid_infoframe(value)
      if not ok then
        return nil, errors.new("invalid a=infoframe: " .. msg, {
          field_path = "session.attributes[infoframe]",
          spec_ref   = "TR-10-10 §8", code = "INVALID_VALUE",
        })
      end
      local port = tonumber((value:match("^(%d+)")) or "") or 0
      if infoframe_ports_seen[port] then
        return nil, errors.new(
          string.format("duplicate a=infoframe port %d", port),
          { field_path = "session.attributes[infoframe]",
            spec_ref = "TR-10-10 §8", code = "INVALID_VALUE" })
      end
      infoframe_ports_seen[port] = true
      -- port SHALL equal some media-block port + 3.
      local matched = false
      for _, m in ipairs(doc.media) do
        if m.port and port == m.port + 3 then matched = true; break end
      end
      if not matched then
        return nil, errors.new(
          string.format("a=infoframe port %d does not match any media port + 3 (TR-10-10 §8)", port),
          { field_path = "session.attributes[infoframe]",
            spec_ref = "TR-10-10 §8", code = "INVALID_VALUE" })
      end
    end
  end

  -- RFC 4145 §4 enum check for a=setup / a=connection on every block that
  -- carries them. Run before the TR-10-14 USB passive check so the more
  -- specific "must be passive" message wins when the value is in-enum.
  local VALID_SETUP = {
    active = true, passive = true, actpass = true, holdconn = true,
  }
  local VALID_CONNECTION = { ["new"] = true, ["existing"] = true }
  for i, m in ipairs(doc.media) do
    for _, a in ipairs(m.attributes or {}) do
      if a.name == "setup" and not VALID_SETUP[a.value or ""] then
        return attr_err(
          "invalid a=setup value '" .. tostring(a.value) ..
            "' (must be active, passive, actpass, or holdconn)",
          string.format("media[%d]", i), "setup", "RFC 4145 §4", "INVALID_VALUE")
      end
      if a.name == "connection" and not VALID_CONNECTION[a.value or ""] then
        return attr_err(
          "invalid a=connection value '" .. tostring(a.value) ..
            "' (must be new or existing)",
          string.format("media[%d]", i), "connection", "RFC 4145 §4", "INVALID_VALUE")
      end
    end
  end

  -- TR-10-14 §14: every USB block (m=application TCP usb) must declare a=setup:passive.
  -- "The SDP shall follow RFC 4145 with the following restrictions" — RFC 4145
  -- defines TCP-based media transport and does not use RTP-specific attributes
  -- (rtpmap, fmtp, mediaclk, ts-refclk). Reject those on USB blocks.
  local USB_FORBIDDEN_ATTRS = {
    rtpmap = true, fmtp = true, mediaclk = true, ["ts-refclk"] = true,
  }
  for i, m in ipairs(doc.media) do
    if usb_set[i] then
      local mpath = string.format("media[%d]", i)
      local setup = find_attr(m.attributes or {}, "setup")
      if not setup then
        return attr_err("missing required attribute 'setup' for USB block",
          mpath, "setup", "TR-10-14 §14")
      end
      if setup.value ~= "passive" then
        return attr_err(
          "a=setup must be 'passive' for USB blocks (got '" .. tostring(setup.value) .. "')",
          mpath, "setup", "TR-10-14 §14", "INVALID_VALUE")
      end
      for _, a in ipairs(m.attributes or {}) do
        if USB_FORBIDDEN_ATTRS[a.name] then
          return attr_err(
            "a=" .. a.name .. " is not permitted on a USB block (TCP transport, RFC 4145)",
            mpath, a.name, "TR-10-14 §14", "INVALID_VALUE")
        end
      end
    end
  end

  -- b=AS bandwidth (TR-10-7 §11): value must be a positive integer (kbps) when
  -- present. For jxsv (compressed video) blocks, ST 2110-22 §7.3 makes b=AS
  -- REQUIRED.
  for i, m in ipairs(doc.media) do
    if not non_rtp_set[i] then
      local has_as = false
      for _, b in ipairs(m.bandwidths or {}) do
        if b.type == "AS" then
          has_as = true
          if not b.value or b.value <= 0 then
            return nil, errors.new(
              "b=AS value must be a positive integer (kbps)",
              { field_path = string.format("media[%d].bandwidths", i),
                spec_ref = "TR-10-7 §11", code = "INVALID_VALUE" })
          end
        end
      end
      local rm = find_attr(m.attributes or {}, "rtpmap")
      local enc = rm and rtpmap_parse(rm.value or "")
      if enc == "jxsv" and not has_as then
        return nil, errors.new(
          "b=AS is required on jxsv (compressed video) media blocks",
          { field_path = string.format("media[%d].bandwidths", i),
            spec_ref = "TR-10-7 §11" })
      end
    end
  end
  -- Session-level b=AS, when present, must also be a positive integer.
  for _, b in ipairs(doc.session.bandwidths or {}) do
    if b.type == "AS" and (not b.value or b.value <= 0) then
      return nil, errors.new(
        "session-level b=AS value must be a positive integer (kbps)",
        { field_path = "session.bandwidths",
          spec_ref = "TR-10-7 §11", code = "INVALID_VALUE" })
    end
  end

  -- a=extmap presence is NOT required by any IPMX-baseline spec — TR-10-13
  -- §1.1.1 only mandates it WHEN declaring RTP Extension Headers for PEP
  -- (privacy). The M31 audit removed an unconditional presence requirement
  -- that cited a non-existent "IPMX §6". When `a=extmap` IS present, its
  -- URI format is still validated (RFC 5285); for PEP IV-Counter URIs the
  -- direction must be `sendonly` (TR-10-13 §20.1).
  for _, attr in ipairs(doc.session.attributes or {}) do
    if attr.name == "extmap" then
      local val = attr.value or ""
      local ok, msg = valid_extmap(val)
      if not ok then
        return nil, errors.new("invalid a=extmap: " .. msg, {
          field_path = "session.attributes[extmap]",
          spec_ref   = "RFC 5285", code = "INVALID_VALUE",
        })
      end
      local pok, pmsg = pep_extmap_direction_ok(val)
      if not pok then
        return nil, errors.new("invalid a=extmap: " .. pmsg, {
          field_path = "session.attributes[extmap]",
          spec_ref   = "TR-10-13 §20.1", code = "INVALID_VALUE",
        })
      end
    end
  end
  for i, m in ipairs(doc.media) do
    if not non_rtp_set[i] then
      for _, attr in ipairs(m.attributes or {}) do
        if attr.name == "extmap" then
          local val = attr.value or ""
          local ok, emsg = valid_extmap(val)
          if not ok then
            return nil, errors.new("invalid a=extmap: " .. emsg, {
              field_path = string.format("media[%d].attributes[extmap]", i),
              spec_ref   = "RFC 5285", code = "INVALID_VALUE",
            })
          end
          local pok, pmsg = pep_extmap_direction_ok(val)
          if not pok then
            return nil, errors.new("invalid a=extmap: " .. pmsg, {
              field_path = string.format("media[%d].attributes[extmap]", i),
              spec_ref   = "TR-10-13 §20.1", code = "INVALID_VALUE",
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
    if not non_rtp_set[i] then
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

  -- Check IPMX fmtp marker and optional FEC params in each RTP block (TR-10-1 §10.1).
  for i, m in ipairs(doc.media) do
    if not non_rtp_set[i] then
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
        -- H5: TR-10-1 §10.2 requires baseband senders to include measuredpixclk,
        -- vtotal, htotal. TR-10-9 §10 extends this to non-baseband senders
        -- (with specific value formulae). The SDP-level validator can't tell
        -- baseband from non-baseband intent, so it requires presence in all
        -- IPMX video fmtps. M10: TP is also required (TR-10-TP-1 §13.2).
        if m.media == "video" then
          if not params["TP"] then
            return attr_err(
              "fmtp missing required 'TP' parameter for IPMX video (TR-10-TP-1 §13.2)",
              mpath, "fmtp", "TR-10-TP-1 §13.2")
          end
          for _, bp in ipairs({ "measuredpixclk", "vtotal", "htotal" }) do
            local v = params[bp]
            if v == nil then
              return attr_err(
                string.format("fmtp missing required '%s' parameter for IPMX video", bp),
                mpath, "fmtp", "TR-10-1 §10.2")
            end
            local n = tonumber(tostring(v))
            if not n or n <= 0 or n ~= math.floor(n) then
              return attr_err(
                string.format("fmtp '%s' must be a positive integer", bp),
                mpath, "fmtp", "TR-10-1 §10.2", "INVALID_VALUE")
            end
          end
        elseif m.media == "audio" then
          -- H5: TR-10-1 §10.3 / TR-10-9 §10 — measuredsamplerate is required.
          local v = params["measuredsamplerate"]
          if v == nil then
            return attr_err(
              "fmtp missing required 'measuredsamplerate' parameter for IPMX audio",
              mpath, "fmtp", "TR-10-1 §10.3")
          end
          local n = tonumber(tostring(v))
          if not n or n <= 0 or n ~= math.floor(n) then
            return attr_err(
              "fmtp 'measuredsamplerate' must be a positive integer",
              mpath, "fmtp", "TR-10-1 §10.3", "INVALID_VALUE")
          end
        end
      end
      -- IPMX audio: ptime is required (TR-10-3 §8). AM824 is permitted under
      -- TR-10-12 (IPMX equivalent of ST 2110-31 AES3 transparent transport).
      if m.media == "audio" then
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

  -- M11: TR-10-5 §10 specifies a=hkep as a session attribute only.
  for i, m in ipairs(doc.media) do
    if find_attr(m.attributes or {}, "hkep") then
      return attr_err(
        "a=hkep must be a session-level attribute, not media-level",
        string.format("media[%d]", i), "hkep", "TR-10-5 §10", "INVALID_VALUE")
    end
  end

  local pok, perr = check_privacy(doc.session.attributes, "session", false)
  if not pok then return nil, perr end
  for i, m in ipairs(doc.media) do
    local pok2, perr2 = check_privacy(
      m.attributes, string.format("media[%d]", i), usb_set[i] == true)
    if not pok2 then return nil, perr2 end
  end

  -- DUP group privacy consistency (TR-10-13 §13). Effective privacy for a leg
  -- is its media-level value, or the session-level value when absent (TR-10-13
  -- §13 line 859: "a session-level privacy attribute represents the default
  -- value for each media-level privacy attribute unless an explicit media-level
  -- privacy attribute is provided"). Undefined mids were already rejected by
  -- st2110.validate above.
  local sess_pattr  = find_attr(doc.session.attributes or {}, "privacy")
  local sess_priv   = sess_pattr and sess_pattr.value or false
  local function effective_privacy(block)
    local p = find_attr(block.attributes or {}, "privacy")
    if p then return p.value end
    return sess_priv
  end
  local dup_ok, dup_err = each_dup_group(doc, "TR-10-13 §13", function(legs)
    local first_val = effective_privacy(legs[1].block)
    for j = 2, #legs do
      if effective_privacy(legs[j].block) ~= first_val then
        return nil, errors.new(
          "a=privacy values must be identical on all DUP group legs",
          { field_path = "session.attributes[group]",
            spec_ref = "TR-10-13 §13", code = "INVALID_VALUE" })
      end
    end
    return true
  end)
  if not dup_ok then return nil, dup_err end

  -- RTCP port convention and port range — RTP blocks only.
  -- Port-even-and->1024 is a "General Provisions" clause repeated identically
  -- across every per-essence TR-10 (-2 §7, -3 §7, -4 §7, -11 §7, -12 §7):
  -- "All IPMX Media streams shall have a UDP destination port value that is
  -- even and that is greater than 1024." TR-10-1 itself does NOT contain
  -- this clause (M31 cite correction). Cite TR-10-2 §7 as the canonical
  -- per-essence reference (video is the dominant IPMX case; wording is
  -- identical across essences).
  for i, m in ipairs(doc.media) do
    if not non_rtp_set[i] then
      local mpath  = string.format("media[%d]", i)
      local mattrs = m.attributes or {}

      local port = m.port
      if port then
        if port <= 1024 then
          return attr_err(
            string.format("media port must be > 1024 (got %d)", port),
            mpath, "port", "TR-10-2 §7", "INVALID_VALUE")
        end
        if port % 2 ~= 0 then
          return attr_err(
            string.format("media port must be even (got %d)", port),
            mpath, "port", "TR-10-2 §7", "INVALID_VALUE")
        end
      end

      -- a=rtcp-mux is forbidden by derivation: TR-10-1 §8.7 mandates RTCP
      -- on media-port+1, while RFC 5761 defines a=rtcp-mux as RTP and RTCP
      -- sharing the same port. Signaling rtcp-mux therefore violates the
      -- TR-10-1 §8.7 "shall" on port+1.
      if find_attr(mattrs, "rtcp-mux") then
        return attr_err(
          "a=rtcp-mux is not permitted (TR-10-1 §8.7 mandates RTCP on media port+1; RFC 5761 rtcp-mux signals same port)",
          mpath, "rtcp-mux", "TR-10-1 §8.7 + RFC 5761", "INVALID_VALUE")
      end

      local rtcp_attr = find_attr(mattrs, "rtcp")
      if rtcp_attr then
        -- RFC 3605 §2.1: rtcp-attribute = "rtcp:" port [SP nettype SP addrtype
        -- SP connection-address]. The triple is optional but, when present,
        -- must follow exactly that form.
        local rtcp_v = rtcp_attr.value or ""
        local rtcp_port_s = rtcp_v:match("^(%d+)$")
        local rtcp_addrtype, rtcp_addr
        if not rtcp_port_s then
          rtcp_port_s, rtcp_addrtype, rtcp_addr =
            rtcp_v:match("^(%d+) IN (IP[46]) (%S+)$")
        end
        if not rtcp_port_s then
          return attr_err(
            "invalid a=rtcp format (RFC 3605 §2.1: '<port> [SP IN SP IP4|IP6 SP <address>]')",
            mpath, "rtcp", "RFC 3605 §2.1", "INVALID_VALUE")
        end
        local rtcp_port = tonumber(rtcp_port_s)
        if rtcp_port > 65535 then
          return attr_err(
            string.format("a=rtcp port %d is above UDP range (must be 1-65535)", rtcp_port),
            mpath, "rtcp", "RFC 768", "INVALID_VALUE")
        end
        if rtcp_port ~= (m.port + 1) then
          return attr_err(
            string.format("a=rtcp port must be media port+1 (expected %d, got %s)",
              m.port + 1, tostring(rtcp_port)),
            mpath, "rtcp", "TR-10-1 §8.7", "INVALID_VALUE")
        end
        if rtcp_addr then
          local cok, cmsg = valid_connection_address(rtcp_addrtype, rtcp_addr)
          if not cok then
            return attr_err("invalid a=rtcp address: " .. cmsg,
              mpath, "rtcp", "RFC 3605 §2.1", "INVALID_VALUE")
          end
        end
      end
    end
  end

  -- M29 G4: TR-10-TP-1 §13.2 lists a=source-filter under the parameters every
  -- IPMX sender's SDP is verified for. RFC 4570 allows the attribute at session
  -- level (applies to all media) or media level. Required on every RTP block;
  -- non-RTP application blocks (TR-10-14 USB) are exempt.
  local has_sess_sf = find_attr(doc.session.attributes or {}, "source-filter") ~= nil
  if not has_sess_sf then
    for i, m in ipairs(doc.media) do
      if not non_rtp_set[i] and not find_attr(m.attributes or {}, "source-filter") then
        return attr_err(
          "a=source-filter is required on every IPMX RTP media block (or at session level)",
          string.format("media[%d]", i), "source-filter", "TR-10-TP-1 §13.2")
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
  -- RFC 4566 §9 ABNF: every record (including the last) ends with CRLF.
  -- §5 permits LF tolerance, but a terminator must be present.
  if #text > 0 and text:sub(-1) ~= "\n" then
    return nil, errors.new(
      "SDP must end with a newline (RFC 4566 §5 / §9 ABNF)",
      { line = 1, col = #text, context = "", code = "MALFORMED_LINE",
        spec_ref = "RFC 4566 §5" })
  end
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
