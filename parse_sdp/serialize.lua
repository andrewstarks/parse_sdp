-- parse_sdp.serialize — render a doc table to RFC 8866 SDP text.
--
-- Contract (see CLAUDE.md "Serializer / Validator separation"):
--   * The serializer NEVER validates. It checks structural completeness
--     (the spec-required fields per RFC 8866 §5 / §6) so a renderable line
--     can be produced, and emits whatever's there. Value-form correctness,
--     enum membership, and cross-section invariants live in `doc:validate`.
--   * Required field absent → return nil, err. Present field of wrong shape
--     → stringified and emitted (round-trip may then fail; that's the
--     developer's signal).
--   * No fallback to a stored attr.value string for known decomposed
--     attribute names. The decomposed-shape contract is the only producer
--     surface — known-name renderers are registered in ATTR_RENDERERS below.
--
-- Slice scope:
--   8.A — v / o / s / t.
--   8.B — i / u / e / p / c / b (session + media) + r= repeats + z= time
--         zones + media blocks (m, optional sub-fields) + generic / flag
--         a= via ATTR_RENDERERS dispatch (empty until 8.D / 8.E populate
--         decomposed-attribute renderers).
--   8.C / 8.D / 8.E — fmtp ordered-params + base + IPMX attribute renderers.

local errors = require("parse_sdp.errors")

local M = {}

-- Wrap one field as "<type>=<value>\r\n" per RFC 8866 §9 ABNF.
local function ln(type_char, value)
  return type_char .. "=" .. value .. "\r\n"
end

local function err_missing(field_path, what)
  return errors.new(
    string.format("cannot serialize: missing required field %s", what),
    { field_path = field_path, code = "MISSING_FIELD",
      spec_ref = "RFC 8866 §5" })
end

-- Required field accessor. Returns the value if present (non-nil), else
-- emits the standard missing-required error.
local function require_field(parent, key, field_path, what)
  local v = parent and parent[key]
  if v == nil then return nil, err_missing(field_path, what) end
  return v
end

-- ── Top-level fields ────────────────────────────────────────────────────────

local function render_version(doc)
  local v, e = require_field(doc, "version", "version", "version")
  if not v then return nil, e end
  return ln("v", tostring(v))
end

-- o= (RFC 8866 §5.2): originator-and-session-identifier.
--   o=<username> <sess-id> <sess-version> <nettype> <addrtype> <unicast-address>
local function render_origin(doc)
  local o = doc.origin
  if o == nil then return nil, err_missing("origin", "origin") end
  local fields = { "username", "sess_id", "sess_version",
                   "net_type", "addr_type", "unicast_address" }
  local parts = {}
  for i, k in ipairs(fields) do
    local v, e = require_field(o, k, "origin." .. k, "origin." .. k)
    if not v then return nil, e end
    parts[i] = tostring(v)
  end
  return ln("o", table.concat(parts, " "))
end

-- s= (RFC 8866 §5.3): session name. Required, single line.
local function render_session_name(s)
  local name, e = require_field(s, "name", "session.name", "session.name")
  if not name then return nil, e end
  return ln("s", tostring(name))
end

-- ── Shared renderers (used at session and media level) ─────────────────────

-- c= (RFC 8866 §5.7): connection-information. Optional at both levels;
-- nil → emit nothing.
local function render_connection(c, field_path)
  if c == nil then return "" end
  local fields = { "net_type", "addr_type", "address" }
  local parts = {}
  for i, k in ipairs(fields) do
    local v, e = require_field(c, k, field_path .. "." .. k,
                               field_path .. "." .. k)
    if not v then return nil, e end
    parts[i] = tostring(v)
  end
  return ln("c", table.concat(parts, " "))
end

-- b= (RFC 8866 §5.8): bandwidth-information lines. Zero or more.
local function render_bandwidths(bws, field_prefix)
  if bws == nil or #bws == 0 then return "" end
  local parts = {}
  for i, b in ipairs(bws) do
    local prefix = string.format("%s[%d]", field_prefix, i)
    local btype, e1 = require_field(b, "type", prefix .. ".type",
                                    prefix .. ".type")
    if not btype then return nil, e1 end
    local bv, e2 = require_field(b, "value", prefix .. ".value",
                                 prefix .. ".value")
    if not bv then return nil, e2 end
    parts[#parts + 1] = ln("b", tostring(btype) .. ":" .. tostring(bv))
  end
  return table.concat(parts)
end

-- Known-name decomposed-attribute renderers register here (Phase 8.D / 8.E).
-- Generic / unknown attribute names fall through to the {name, value?}
-- carrier shape, which is also how flag attributes (a=recvonly) render.
local ATTR_RENDERERS = {}

local function render_attribute(attr, field_path)
  if type(attr) ~= "table" then
    return nil, errors.new(
      string.format("cannot serialize: %s is not a table", field_path),
      { field_path = field_path, code = "INVALID_ARG" })
  end
  local name = attr.name
  if name == nil then
    return nil, err_missing(field_path .. ".name", field_path .. ".name")
  end
  local renderer = ATTR_RENDERERS[name]
  if renderer then return renderer(attr, field_path) end
  -- Generic carrier: a=<name> or a=<name>:<value>.
  if attr.value ~= nil then
    return ln("a", tostring(name) .. ":" .. tostring(attr.value))
  end
  return ln("a", tostring(name))
end

local function render_attributes(attrs, field_prefix)
  if attrs == nil or #attrs == 0 then return "" end
  local parts = {}
  for i, a in ipairs(attrs) do
    local line, e = render_attribute(a,
      string.format("%s[%d]", field_prefix, i))
    if not line then return nil, e end
    parts[#parts + 1] = line
  end
  return table.concat(parts)
end

-- ── Time descriptions (t= and r=) ──────────────────────────────────────────

-- r= (RFC 8866 §5.10): repeat-time. ABNF requires interval, duration, and
-- at least one offset. Doc shape: {interval, duration, offsets={...}}.
-- typed-time tokens are kept as captured strings (e.g. "604800", "3600",
-- "0", "25h") and emitted verbatim.
local function render_repeats(repeats, field_prefix)
  if repeats == nil or #repeats == 0 then return "" end
  local parts = {}
  for i, r in ipairs(repeats) do
    local prefix = string.format("%s[%d]", field_prefix, i)
    local interval, e1 = require_field(r, "interval",
      prefix .. ".interval", prefix .. ".interval")
    if not interval then return nil, e1 end
    local duration, e2 = require_field(r, "duration",
      prefix .. ".duration", prefix .. ".duration")
    if not duration then return nil, e2 end
    local offsets = r.offsets
    if offsets == nil or #offsets == 0 then
      return nil, err_missing(prefix .. ".offsets",
        prefix .. ".offsets (at least one offset)")
    end
    local toks = { tostring(interval), tostring(duration) }
    for _, off in ipairs(offsets) do toks[#toks + 1] = tostring(off) end
    parts[#parts + 1] = ln("r", table.concat(toks, " "))
  end
  return table.concat(parts)
end

-- t= (RFC 8866 §5.9): at least one time-description per SDP. Each t= line
-- carries its own r= repeats sub-block per §5.9 ordering.
local function render_time_descriptions(s)
  local tds = s.time_descriptions
  if tds == nil or #tds == 0 then
    return nil, err_missing("session.time_descriptions",
      "session.time_descriptions (at least one t=)")
  end
  local parts = {}
  for i, td in ipairs(tds) do
    local prefix = string.format("session.time_descriptions[%d]", i)
    local start_v, e1 = require_field(td, "start",
      prefix .. ".start", prefix .. ".start")
    if not start_v then return nil, e1 end
    local stop_v, e2 = require_field(td, "stop",
      prefix .. ".stop", prefix .. ".stop")
    if not stop_v then return nil, e2 end
    parts[#parts + 1] = ln("t",
      tostring(start_v) .. " " .. tostring(stop_v))
    local r_block, re = render_repeats(td.repeats, prefix .. ".repeats")
    if not r_block then return nil, re end
    parts[#parts + 1] = r_block
  end
  return table.concat(parts)
end

-- z= (RFC 8866 §5.11): time-zone-adjustments. Optional. When present,
-- requires ≥1 (adjustment_time, offset) pair per the ABNF.
local function render_time_zones(s)
  local tzs = s.time_zones
  if tzs == nil or #tzs == 0 then return "" end
  local toks = {}
  for i, pair in ipairs(tzs) do
    local prefix = string.format("session.time_zones[%d]", i)
    local at, e1 = require_field(pair, "adjustment_time",
      prefix .. ".adjustment_time", prefix .. ".adjustment_time")
    if not at then return nil, e1 end
    local off, e2 = require_field(pair, "offset",
      prefix .. ".offset", prefix .. ".offset")
    if not off then return nil, e2 end
    toks[#toks + 1] = tostring(at)
    toks[#toks + 1] = tostring(off)
  end
  return ln("z", table.concat(toks, " "))
end

-- ── Media blocks ───────────────────────────────────────────────────────────

-- m= (RFC 8866 §5.14): media-field. Required fields per ABNF: media, port,
-- proto, at least one fmt. port_count is the optional "/N" suffix on port.
-- Doc shape: { media, port, port_count?, proto, fmts[], info?, connection?,
--              bandwidths[], attributes[] }.
local function render_media_block(m, idx)
  local prefix = string.format("media[%d]", idx)
  local media_v, e1 = require_field(m, "media",
    prefix .. ".media", prefix .. ".media")
  if not media_v then return nil, e1 end
  local port, e2 = require_field(m, "port",
    prefix .. ".port", prefix .. ".port")
  if not port then return nil, e2 end
  local proto, e3 = require_field(m, "proto",
    prefix .. ".proto", prefix .. ".proto")
  if not proto then return nil, e3 end
  if m.fmts == nil or #m.fmts == 0 then
    return nil, err_missing(prefix .. ".fmts",
      prefix .. ".fmts (at least one)")
  end

  local port_str = tostring(port)
  if m.port_count ~= nil then
    port_str = port_str .. "/" .. tostring(m.port_count)
  end
  local fmt_toks = {}
  for i, f in ipairs(m.fmts) do fmt_toks[i] = tostring(f) end
  local m_line = ln("m",
    tostring(media_v) .. " " .. port_str .. " "
    .. tostring(proto) .. " " .. table.concat(fmt_toks, " "))

  local parts = { m_line }
  if m.info ~= nil then parts[#parts + 1] = ln("i", tostring(m.info)) end
  local c_block, ce = render_connection(m.connection,
    prefix .. ".connection")
  if not c_block then return nil, ce end
  parts[#parts + 1] = c_block
  local b_block, be = render_bandwidths(m.bandwidths,
    prefix .. ".bandwidths")
  if not b_block then return nil, be end
  parts[#parts + 1] = b_block
  -- k= (§5.12) is obsolete; never emitted.
  local a_block, ae = render_attributes(m.attributes,
    prefix .. ".attributes")
  if not a_block then return nil, ae end
  parts[#parts + 1] = a_block
  return table.concat(parts)
end

-- ── Public entry point ─────────────────────────────────────────────────────

--- Serialize a doc table back to RFC 8866 SDP text.
-- @param doc table  Document table from parse_sdp.grammar.* match, or a
--                   hand-built table matching the same decomposed shape.
-- @return string  SDP text (CRLF line endings) on success.
-- @return nil, err  on structural-completeness failure.
function M.to_sdp(doc)
  if type(doc) ~= "table" then
    return nil, errors.new(
      "cannot serialize: doc is not a table",
      { code = "INVALID_ARG" })
  end
  local s = doc.session
  if s == nil then return nil, err_missing("session", "session") end

  local parts = {}
  local function push(piece) parts[#parts + 1] = piece end

  local v_line,  ev = render_version(doc);        if not v_line  then return nil, ev end; push(v_line)
  local o_line,  eo = render_origin(doc);         if not o_line  then return nil, eo end; push(o_line)
  local s_line,  es = render_session_name(s);     if not s_line  then return nil, es end; push(s_line)

  if s.info ~= nil then push(ln("i", tostring(s.info))) end
  if s.uri  ~= nil then push(ln("u", tostring(s.uri))) end
  for _, em in ipairs(s.emails or {}) do push(ln("e", tostring(em))) end
  for _, ph in ipairs(s.phones or {}) do push(ln("p", tostring(ph))) end

  local c_block, ec = render_connection(s.connection, "session.connection")
  if not c_block then return nil, ec end; push(c_block)
  local b_block, eb = render_bandwidths(s.bandwidths, "session.bandwidths")
  if not b_block then return nil, eb end; push(b_block)

  local t_block, et = render_time_descriptions(s)
  if not t_block then return nil, et end; push(t_block)
  local z_block, ez = render_time_zones(s)
  if not z_block then return nil, ez end; push(z_block)

  local a_block, ea = render_attributes(s.attributes, "session.attributes")
  if not a_block then return nil, ea end; push(a_block)

  for i, m in ipairs(doc.media or {}) do
    local mb, em_err = render_media_block(m, i - 1) -- 0-indexed field_path
    if not mb then return nil, em_err end
    push(mb)
  end

  return table.concat(parts)
end

return M
