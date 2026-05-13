#!/usr/bin/env lua
--- parse_sdp — RFC 4566 / ST 2110 / IPMX SDP parser, validator, and serializer.
-- Single-file library and CLI executable.  `require("parse_sdp")` loads the
-- library; running it directly activates the argparse CLI.
-- @module parse_sdp

-- ── External dependencies ─────────────────────────────────────────────────────
local lpeg   = require("lpeg")
local dkjson = require("dkjson")
local P, R, C, Cp, Ct = lpeg.P, lpeg.R, lpeg.C, lpeg.Cp, lpeg.Ct

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

--- Parse an s= field value; returns the raw string unchanged.
-- @param s string  Field value string.
-- @return string  Session name.
function grammar.parse_session_name(s) return s end

--- Parse an i= field value; returns the raw string unchanged.
-- @param s string  Field value string.
-- @return string  Session or media information text.
function grammar.parse_info(s)         return s end

--- Parse a u= field value; returns the raw string unchanged.
-- @param s string  Field value string.
-- @return string  URI.
function grammar.parse_uri(s)          return s end

--- Parse an e= field value; returns the raw string unchanged.
-- @param s string  Field value string.
-- @return string  Email address.
function grammar.parse_email(s)        return s end

--- Parse a p= field value; returns the raw string unchanged.
-- @param s string  Field value string.
-- @return string  Phone number.
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
function serialize.serialize(doc)
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

-- Extract the RTP clock rate from an rtpmap value (e.g. "96 raw/90000" → 90000).
-- Returns nil if the value does not match the expected encoding/clock format.
local function rtpmap_clock_rate(value)
  local rest = value:match("^%d+%s+(.+)$")
  if not rest then return nil end
  local rate = rest:match("^[^/]+/(%d+)")
  return rate and tonumber(rate)
end

-- Extract the encoding name from an rtpmap value (e.g. "96 raw/90000" → "raw").
local function rtpmap_encoding(value)
  local rest = value:match("^%d+%s+(.+)$")
  if not rest then return nil end
  return rest:match("^([^/]+)")
end

-- Validate the value of a ts-refclk attribute per ST 2110-10 §7.2.
-- Returns true on success, or nil + error message string on failure.
local function valid_tsrefclk(value)
  if value == "gps" or value == "gal" or value == "glonass" then return true end
  local addr = value:match("^ntp=(.+)$")
  if addr then
    if addr:match("%s") then return nil, "invalid ts-refclk ntp address" end
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
    -- version:gmid[:domain] — GMID must be 8 HH-separated hex octets
    local _, gmid = ptp_rest:match("^([^:]+):([^:]+)")
    if not gmid then return nil, "invalid ts-refclk ptp value" end
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
function st2110.st2110(doc)
  local ok, e = validate.sdp(doc)
  if not ok then return nil, e end

  if #doc.media < 1 then
    return nil, errors.new("ST 2110 requires at least one media block",
      { field_path = "media", spec_ref = "ST 2110-10 §7" })
  end

  local sess_attrs = doc.session.attributes or {}

  for i, m in ipairs(doc.media) do
    local mpath  = string.format("media[%d]", i)
    local mattrs = m.attributes or {}

    local tsrefclk = find_attr(sess_attrs, "ts-refclk") or find_attr(mattrs, "ts-refclk")
    if not tsrefclk then
      return nil, errors.new("missing required attribute 'ts-refclk'", {
        field_path = mpath .. ".attributes[ts-refclk]",
        spec_ref   = "ST 2110-10 §7.2",
      })
    end
    local trok, trmsg = valid_tsrefclk(tsrefclk.value or "")
    if not trok then
      return nil, errors.new("invalid ts-refclk: " .. (trmsg or ""), {
        field_path = mpath .. ".attributes[ts-refclk]",
        spec_ref   = "ST 2110-10 §7.2",
        code       = "INVALID_VALUE",
      })
    end

    local mediaclk = find_attr(mattrs, "mediaclk")
    if not mediaclk then
      return nil, errors.new("missing required attribute 'mediaclk'", {
        field_path = mpath .. ".attributes[mediaclk]",
        spec_ref   = "ST 2110-10 §7.3",
      })
    end
    local mcok, mcmsg = valid_mediaclk(mediaclk.value or "")
    if not mcok then
      return nil, errors.new("invalid mediaclk: " .. (mcmsg or ""), {
        field_path = mpath .. ".attributes[mediaclk]",
        spec_ref   = "ST 2110-10 §7.3",
        code       = "INVALID_VALUE",
      })
    end

    local rtpmap = find_attr(mattrs, "rtpmap")
    if not rtpmap then
      return nil, errors.new("missing required attribute 'rtpmap'", {
        field_path = mpath .. ".attributes[rtpmap]",
        spec_ref   = "ST 2110-10 §7",
      })
    end

    local fmtp = find_attr(mattrs, "fmtp")
    if not fmtp then
      return nil, errors.new("missing required attribute 'fmtp'", {
        field_path = mpath .. ".attributes[fmtp]",
        spec_ref   = "ST 2110-10 §7",
      })
    end

    local enc = rtpmap_encoding(rtpmap.value or "")

    if enc == "smpte291" then
      -- ST 2110-40: ancillary data (RFC 8331 / SMPTE ST 2110-40)
      local clock_rate = rtpmap_clock_rate(rtpmap.value or "")
      if clock_rate ~= 90000 then
        return nil, errors.new(
          string.format("rtpmap clock rate must be 90000 for smpte291 (got %s)", tostring(clock_rate)),
          { field_path = mpath .. ".attributes[rtpmap]", spec_ref = "ST 2110-40 §7.2", code = "INVALID_VALUE" }
        )
      end
      local params, fmtp_err = fmtp_params(fmtp.value or "")
      if not params then
        return nil, errors.new("invalid fmtp: " .. fmtp_err, {
          field_path = mpath .. ".attributes[fmtp]", spec_ref = "ST 2110-40 §7.2", code = "INVALID_VALUE",
        })
      end
      if not params["DID_SDID"] then
        return nil, errors.new("fmtp missing required 'DID_SDID' parameter for ST 2110-40 (smpte291)", {
          field_path = mpath .. ".attributes[fmtp]", spec_ref = "ST 2110-40 §7.2",
        })
      end
      local dok, derr = valid_did_sdid(params["DID_SDID"])
      if not dok then
        return nil, errors.new("invalid DID_SDID: " .. derr, {
          field_path = mpath .. ".attributes[fmtp]", spec_ref = "ST 2110-40 §7.2", code = "INVALID_VALUE",
        })
      end

    elseif enc == "ST2110-41" then
      -- ST 2110-41: fast metadata
      local params, fmtp_err = fmtp_params(fmtp.value or "")
      if not params then
        return nil, errors.new("invalid fmtp: " .. fmtp_err, {
          field_path = mpath .. ".attributes[fmtp]", spec_ref = "ST 2110-41 §7.2", code = "INVALID_VALUE",
        })
      end
      if not params["SSN"] then
        return nil, errors.new("fmtp missing required 'SSN' parameter for ST 2110-41", {
          field_path = mpath .. ".attributes[fmtp]", spec_ref = "ST 2110-41 §7.2",
        })
      end
      if not params["DIT"] then
        return nil, errors.new("fmtp missing required 'DIT' parameter for ST 2110-41", {
          field_path = mpath .. ".attributes[fmtp]", spec_ref = "ST 2110-41 §7.2",
        })
      end

    elseif m.media == "video" then
      -- ST 2110-20: uncompressed video
      local clock_rate = rtpmap_clock_rate(rtpmap.value or "")
      if clock_rate ~= 90000 then
        return nil, errors.new(
          string.format("rtpmap clock rate must be 90000 for video (got %s)", tostring(clock_rate)),
          { field_path = mpath .. ".attributes[rtpmap]", spec_ref = "ST 2110-20 §7.2", code = "INVALID_VALUE" }
        )
      end
      local params, fmtp_err = fmtp_params(fmtp.value or "")
      if not params then
        return nil, errors.new("invalid fmtp: " .. fmtp_err, {
          field_path = mpath .. ".attributes[fmtp]", spec_ref = "ST 2110-20 §7.2", code = "INVALID_VALUE",
        })
      end
      if not params.sampling then
        return nil, errors.new("fmtp missing required 'sampling' parameter for video", {
          field_path = mpath .. ".attributes[fmtp]", spec_ref = "ST 2110-20 §7.2",
        })
      end

    elseif m.media == "audio" then
      -- ST 2110-30: audio (PCM)
      local params, fmtp_err = fmtp_params(fmtp.value or "")
      if not params then
        return nil, errors.new("invalid fmtp: " .. fmtp_err, {
          field_path = mpath .. ".attributes[fmtp]", spec_ref = "ST 2110-30 §7.2", code = "INVALID_VALUE",
        })
      end
      if not params["channel-order"] then
        return nil, errors.new("fmtp missing required 'channel-order' parameter for audio", {
          field_path = mpath .. ".attributes[fmtp]", spec_ref = "ST 2110-30 §7.2",
        })
      end
    end
  end

  return true
end

-- ── IPMX ──────────────────────────────────────────────────────────────────────
local ipmx = {}

--- Validate an SDP document against IPMX requirements.
-- Runs ST 2110 validation first, then checks that a=extmap is present at
-- session level or in at least one media block.
-- @param doc table  SDP document table.
-- @return true  on success.
-- @return nil, err  on failure; err includes field_path and spec_ref.
function ipmx.ipmx(doc)
  local ok, e = st2110.st2110(doc)
  if not ok then return nil, e end

  local has_extmap = find_attr(doc.session.attributes, "extmap") ~= nil
  if not has_extmap then
    for _, m in ipairs(doc.media) do
      if find_attr(m.attributes or {}, "extmap") then
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
    local ok, ve = st2110.st2110(doc)
    if not ok then return nil, ve end
  elseif mode == "ipmx" then
    local ok, ve = ipmx.ipmx(doc)
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
  st2110 = st2110.st2110,
  ipmx   = ipmx.ipmx,
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
function mt:is_st2110() return st2110.st2110(self) == true end

--- Test whether the document satisfies IPMX requirements.
-- @return boolean
function mt:is_ipmx()   return ipmx.ipmx(self) == true end

--- Encode the document as a JSON string using dkjson.
-- @return string  JSON representation of the document.
function mt:to_json()
  return dkjson.encode(self)
end

--- Serialize the document back to RFC 4566 SDP text.
-- @return string  SDP text with CRLF line endings.
function mt:to_sdp()
  return serialize.serialize(self)
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
    "  parse_sdp parse session.sdp",
    "  parse_sdp parse --mode st2110 --pretty session.sdp",
    "  parse_sdp parse < session.sdp | parse_sdp serialize",
    "  parse_sdp serialize session.json",
  }, "\n"))
  ap:command_target("command")

  local cmd_parse = ap:command("parse", "Parse and validate an SDP file; output JSON.")
  cmd_parse:argument("file", "Path to .sdp file. Reads stdin if omitted."):args("?")
  cmd_parse:option("--mode", "Validation tier: 'st2110' or 'ipmx'. Defaults to RFC 4566 only.")
  cmd_parse:flag("--pretty", "Pretty-print JSON output with indentation.")

  local cmd_ser = ap:command("serialize", "Convert a JSON SDP document back to SDP text.")
  cmd_ser:argument("file", "Path to .json file. Reads stdin if omitted."):args("?")

  local parsed = ap:parse()

  if parsed.command == "parse" then
    local text = read_input(parsed.file)
    local doc, perr = M.parse(text, parsed.mode)
    if not doc then die(perr) end
    local encode_opts = parsed.pretty and { indent = true } or nil
    io.write(dkjson.encode(doc, encode_opts) .. "\n")
    os.exit(0)

  elseif parsed.command == "serialize" then
    local json_text = read_input(parsed.file)
    local tbl, _, jsonerr = dkjson.decode(json_text)
    if not tbl then
      die(errors.new("invalid JSON: " .. (jsonerr or "parse error")))
    end
    local doc = M.new(tbl)
    local ok, result = pcall(function() return doc:to_sdp() end)
    if not ok then
      die(errors.new("serialize error: " .. tostring(result)))
    end
    io.write(result)
    os.exit(0)
  end
end

return M
