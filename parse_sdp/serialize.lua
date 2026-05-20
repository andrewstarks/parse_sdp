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
--     surface.
--
-- Phase 8.A scope: v / o / s / t (and t-block r= repeats) only. Optional
-- session-level fields (i, u, e, p, c, b, z, attributes) and media blocks
-- land in 8.B. Compound attribute renderers land in 8.D.

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

-- ── Section renderers ──────────────────────────────────────────────────────

-- v= (RFC 8866 §5.1): single SDP-version-number, currently "0".
local function render_version(doc)
  local v, e = require_field(doc, "version", "version", "version")
  if not v then return nil, e end
  return ln("v", tostring(v))
end

-- o= (RFC 8866 §5.2): originator-and-session-identifier.
--   o=<username> <sess-id> <sess-version> <nettype> <addrtype> <unicast-address>
-- All six tokens are required.
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

-- s= (RFC 8866 §5.3): session name. Exactly one per SDP; cannot be empty
-- (§5.3 mandates at least one character; "-" or " " are common
-- placeholders).
local function render_session_name(doc)
  local s = doc.session
  if s == nil then return nil, err_missing("session", "session") end
  local name, e = require_field(s, "name", "session.name", "session.name")
  if not name then return nil, e end
  return ln("s", tostring(name))
end

-- t= (RFC 8866 §5.9–§5.10): zero-or-more time-descriptions. The ABNF
-- requires at least one t= line per session; §5.9's "permanent session"
-- convention is `t=0 0`. Each time_description carries optional r= repeats.
--
-- Doc shape: session.time_descriptions = {{start=N, stop=N, repeats={...}},
-- ...}. Phase 8.A only supports the bare t= form; r= repeat rendering lands
-- in 8.B.
local function render_time_descriptions(doc)
  local s = doc.session
  local tds = s and s.time_descriptions
  if tds == nil or #tds == 0 then
    return nil, err_missing("session.time_descriptions",
                            "session.time_descriptions (at least one t=)")
  end
  local parts = {}
  for i, td in ipairs(tds) do
    local prefix = string.format("session.time_descriptions[%d]", i)
    local start_v, e1 = require_field(td, "start", prefix .. ".start",
                                      prefix .. ".start")
    if not start_v then return nil, e1 end
    local stop_v, e2 = require_field(td, "stop", prefix .. ".stop",
                                     prefix .. ".stop")
    if not stop_v then return nil, e2 end
    parts[#parts + 1] = ln("t",
      tostring(start_v) .. " " .. tostring(stop_v))
    -- r= repeats deferred to Phase 8.B; non-empty repeats here are silently
    -- skipped so the bootstrap shell stays minimal. 8.B adds the renderer
    -- and a test guarding non-empty repeats.
  end
  return table.concat(parts)
end

-- ── Public entry point ─────────────────────────────────────────────────────

--- Serialize a doc table back to RFC 8866 SDP text.
-- @param doc table  Document table with at minimum version, origin,
--                   session.name, session.time_descriptions[].{start,stop}.
-- @return string  SDP text (CRLF line endings) on success.
-- @return nil, err  on structural-completeness failure.
function M.to_sdp(doc)
  if type(doc) ~= "table" then
    return nil, errors.new(
      "cannot serialize: doc is not a table",
      { code = "INVALID_ARG" })
  end

  local v_line, e1 = render_version(doc)
  if not v_line then return nil, e1 end
  local o_line, e2 = render_origin(doc)
  if not o_line then return nil, e2 end
  local s_line, e3 = render_session_name(doc)
  if not s_line then return nil, e3 end
  local t_block, e4 = render_time_descriptions(doc)
  if not t_block then return nil, e4 end

  return v_line .. o_line .. s_line .. t_block
end

return M
