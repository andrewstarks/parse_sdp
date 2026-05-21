-- parse_sdp.errors — error registry, severity policy, findings buffer,
-- deepest-failure tracker, and 1.0-compatible formatter/new.
--
-- This module is the source of truth for every checkable spec clause the
-- parser enforces. Each check is registered with a stable ID, a default
-- severity, the legacy `code` enum value, a message template, and its
-- `spec_ref`. The grammar and tier validators emit findings via record();
-- callers supply an optional policy that overrides severity per ID.
--
-- The legacy errors.new / errors.format pair from parse_sdp.lua is re-exported
-- here unchanged so consumers that build errors directly (parser-level
-- syntactic failures with no registered ID) keep working. The new `id` field
-- on the error struct is additive.

local M = {}

-- ─── Registry ────────────────────────────────────────────────────────────────

local CHECKS = {}

local VALID_KINDS = {
  ["hard-syntactic"] = true,
  ["soft-syntactic"] = true,
  ["semantic"]       = true,
}

local VALID_SEVERITIES = {
  ["error"] = true,
  ["warn"]  = true,
  ["off"]   = true,
}

local VALID_CODES = {
  INVALID_VALUE  = true,
  MISSING_FIELD  = true,
  MALFORMED_LINE = true,
  WRONG_ORDER    = true,
}

-- Register a check definition. error()s loudly on malformed input —
-- a programmer mistake at module-load, not a parse-time failure.
function M.register(id, def)
  if type(id) ~= "string" or id == "" then
    error("check id must be a non-empty string", 2)
  end
  if CHECKS[id] then
    error("duplicate check id: " .. id, 2)
  end
  if type(def) ~= "table" then
    error("check definition must be a table for id " .. id, 2)
  end
  for _, k in ipairs({"kind", "default_severity", "code",
                      "message_template", "spec_ref", "verified"}) do
    if def[k] == nil then
      error("check '" .. id .. "' missing field '" .. k .. "'", 2)
    end
  end
  if not VALID_KINDS[def.kind] then
    error("check '" .. id .. "' has invalid kind: " .. tostring(def.kind), 2)
  end
  if not VALID_SEVERITIES[def.default_severity] then
    error("check '" .. id .. "' has invalid default_severity: "
          .. tostring(def.default_severity), 2)
  end
  if not VALID_CODES[def.code] then
    error("check '" .. id .. "' has invalid code: " .. tostring(def.code), 2)
  end
  if def.verified == false
     and (def.verification_note == nil or def.verification_note == "") then
    error("check '" .. id .. "' verified=false must include verification_note", 2)
  end
  CHECKS[id] = {
    id                = id,
    kind              = def.kind,
    default_severity  = def.default_severity,
    code              = def.code,
    message_template  = def.message_template,
    spec_ref          = def.spec_ref,
    verified          = def.verified,
    verification_note = def.verification_note,
  }
  return CHECKS[id]
end

function M.get(id) return CHECKS[id] end

-- Array of every registered check, sorted by id. Inspectable for audit.
function M.checks()
  local ids = {}
  for id in pairs(CHECKS) do ids[#ids + 1] = id end
  table.sort(ids)
  local out = {}
  for i, id in ipairs(ids) do out[i] = CHECKS[id] end
  return out
end

-- Table from id → default_severity for every registered check. Callers dump
-- this, edit it, and pass the edited table back via opts.policy.
function M.default_policy()
  local out = {}
  for id, def in pairs(CHECKS) do out[id] = def.default_severity end
  return out
end

-- ─── Severity resolution ────────────────────────────────────────────────────

function M.resolve_severity(policy, id)
  local def = CHECKS[id]
  if not def then error("unknown check id: " .. tostring(id), 2) end
  if policy and policy[id] then return policy[id] end
  return def.default_severity
end

-- ─── Policy validation ──────────────────────────────────────────────────────

-- Caller-supplied policy is validated against the registry: any unknown id is
-- a caller bug. Returns true | nil, err. err.policy_key names the bad entry.
function M.validate_policy(policy)
  if policy == nil then return true end
  if type(policy) ~= "table" then
    return nil, { message = "policy must be a table", code = "INVALID_VALUE" }
  end
  for id, sev in pairs(policy) do
    if not CHECKS[id] then
      return nil, {
        message    = "unknown check id in policy: " .. tostring(id),
        code       = "INVALID_VALUE",
        policy_key = id,
      }
    end
    if not VALID_SEVERITIES[sev] then
      return nil, {
        message    = "invalid severity for '" .. id .. "': " .. tostring(sev),
        code       = "INVALID_VALUE",
        policy_key = id,
      }
    end
  end
  return true
end

-- ─── Position helpers ───────────────────────────────────────────────────────

-- Translate an LPeg byte position into 1-indexed (line, col). LF
-- terminates a line for both bare-LF and CRLF (count LF only; CR sits
-- at the previous line's last column). Pure O(n) — finding emission
-- is rare enough that a position cache isn't worth the complexity.
function M.pos_to_line_col(text, pos)
  if not text or not pos or pos < 1 then return 0, 0 end
  if pos > #text + 1 then pos = #text + 1 end
  local line, last_lf = 1, 0
  for i = 1, pos - 1 do
    if text:byte(i) == 10 then  -- LF
      line = line + 1
      last_lf = i
    end
  end
  return line, pos - last_lf
end

-- ─── record() — the only way a check site emits a finding ───────────────────

-- ctx: { findings = {}, policy = {?}, fail_on_first = bool, text = ?str }
-- id:  registered check id
-- loc: { line=, col=, context=, field_path=, pos= }   (any field may be nil)
--
-- Position: when loc.pos + ctx.text are present, line/col are computed
-- from pos (in-grammar Cmts get them for free); otherwise loc.line/col
-- are used directly (semantic_checks doc walks have no pos).
--
-- Returns true to continue matching, false to fail the match (only when
-- effective severity is "error" and ctx.fail_on_first is true).
function M.record(ctx, id, loc)
  local def = CHECKS[id]
  if not def then error("record() with unknown check id: " .. tostring(id), 2) end
  local sev = (ctx.policy and ctx.policy[id]) or def.default_severity
  if sev == "off" then return true end
  local line, col = 0, 0
  if loc and loc.pos and ctx.text then
    line, col = M.pos_to_line_col(ctx.text, loc.pos)
  elseif loc then
    line, col = loc.line or 0, loc.col or 0
  end
  ctx.findings[#ctx.findings + 1] = {
    id         = id,
    severity   = sev,
    message    = def.message_template,
    spec_ref   = def.spec_ref,
    code       = def.code,
    line       = line,
    col        = col,
    context    = loc and loc.context or "",
    field_path = loc and loc.field_path,
  }
  if sev == "error" and ctx.fail_on_first then return false end
  return true
end

-- ─── Deepest-failure tracker ────────────────────────────────────────────────

-- Accumulator grammar Cmts write to before returning false. After a
-- failed match, tracker_deepest() reports the position closest to
-- end-of-input — usually the most informative failure. Tie-break:
-- later record wins.

function M.new_tracker()
  return { position = 0, info = nil }
end

function M.tracker_record(t, position, info)
  if position >= t.position then
    t.position = position
    t.info     = info
  end
end

function M.tracker_deepest(t)
  return t.position, t.info
end

-- ─── Legacy errors.new / errors.format (1.0 compatibility) ──────────────────

-- Build a structured error table. The `id` field is new and additive.
function M.new(msg, opts)
  local o = opts or {}
  return {
    message    = msg,
    line       = o.line    or 0,
    col        = o.col     or 0,
    context    = o.context or "",
    code       = o.code    or "MISSING_FIELD",
    field_path = o.field_path,
    spec_ref   = o.spec_ref,
    id         = o.id,
  }
end

function M.format(err)
  if not err then return "error: unknown" end
  local code_part = err.code and ("[" .. err.code .. "] ") or ""
  local out = { "error: " .. code_part .. (err.message or "unknown error") }
  -- field_path and line/col are complementary (where in the doc / where
  -- in the text) and both render when present.
  local has_field = err.field_path and err.field_path ~= ""
  local has_line  = err.line and err.line > 0
  if has_field then
    out[#out + 1] = " --> field: " .. err.field_path
  end
  if has_line then
    out[#out + 1] = string.format(
      "%s line %d, col %d",
      has_field and "      at" or " -->",
      err.line, err.col or 1)
    -- `context` is overloaded: 1.0 callers set it to the source-line text
    -- for the `N | <line>` highlight block; in-grammar Cmts use it for a
    -- metadata table downstream JSON consumers read. Render the highlight
    -- only when it's a string.
    if type(err.context) == "string" and err.context ~= "" then
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

-- ─── Seed registry: representative starting set ─────────────────────────────
--
-- Phase 0 ships a small seed. Phases 1+ add rows as each section of the new
-- grammar lands. The registry is append-only during the refactor; ids that
-- ship are public surface and must not be renamed without a deprecation.

M.register("sdp.v.must-be-zero", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "v= must be '0'",
  spec_ref         = "RFC 8866 §5.1",
  verified         = true,
})

M.register("sdp.o.username-required", {
  kind             = "semantic",
  default_severity = "error",
  code             = "MISSING_FIELD",
  message_template = "o= username is required",
  spec_ref         = "RFC 8866 §5.2",
  verified         = true,
})

M.register("sdp.file.bom-present", {
  kind             = "soft-syntactic",
  default_severity = "warn",
  code             = "MALFORMED_LINE",
  message_template = "file starts with a UTF-8 BOM; RFC 8866 §6 SDP charset signaling does not require it",
  spec_ref         = "RFC 8866 §6",
  verified         = true,
})

M.register("sdp.line.trailing-whitespace", {
  kind             = "soft-syntactic",
  default_severity = "warn",
  code             = "MALFORMED_LINE",
  message_template = "line has trailing whitespace before the terminator",
  spec_ref         = "RFC 8866 §9",
  verified         = true,
})

M.register("sdp.line.lf-only-line-ending", {
  kind             = "soft-syntactic",
  default_severity = "warn",
  code             = "MALFORMED_LINE",
  message_template = "line ended with bare LF; RFC 8866 §9 ABNF requires CRLF",
  spec_ref         = "RFC 8866 §9",
  verified         = true,
})

M.register("sdp.file.trailing-newline-missing", {
  kind             = "soft-syntactic",
  default_severity = "warn",
  code             = "MALFORMED_LINE",
  message_template = "SDP must end with a newline (RFC 8866 §5 / §9 ABNF)",
  spec_ref         = "RFC 8866 §5",
  verified         = true,
})

M.register("sdp.a.fmtp.trailing-semicolon", {
  kind             = "soft-syntactic",
  default_severity = "warn",
  code             = "MALFORMED_LINE",
  message_template = "a=fmtp value ends with a stray semicolon",
  spec_ref         = "RFC 8866 §6.15",
  verified         = true,
})

M.register("sdp.m.rtpmap-required-for-dynamic-pt", {
  kind             = "semantic",
  default_severity = "error",
  code             = "MISSING_FIELD",
  message_template = "dynamic RTP payload type (96-127) requires a matching a=rtpmap",
  spec_ref         = "RFC 8866 §8.2.3",
  verified         = true,
})

M.register("sdp.a.mid.duplicate-tag", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "a=mid identification-tag must be unique within the SDP",
  spec_ref         = "RFC 5888 §4",
  verified         = true,
})

M.register("sdp.a.ts-refclk.traceable-mix", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "ts-refclk: traceable and non-traceable sources cannot be mixed at the same level",
  spec_ref         = "RFC 7273 §4.8",
  verified         = true,
})

-- ── c= connection-address checks (RFC 8866 §5.7 / §9) ──────────────────────

M.register("sdp.c.address.invalid-ipv4", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "c= IP4 address is not a valid dotted-quad",
  spec_ref         = "RFC 8866 §9 (IP4-address ABNF)",
  verified         = true,
})

M.register("sdp.c.address.invalid-ipv6", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "c= IP6 address is not a valid IPv6 form",
  spec_ref         = "RFC 8866 §9 (IP6-address ABNF)",
  verified         = true,
})

M.register("sdp.c.ipv4-multicast.ttl-required", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "IPv4 multicast c= address requires a '/<ttl>' suffix",
  spec_ref         = "RFC 8866 §9 (IP4-multicast ABNF)",
  verified         = true,
})

M.register("sdp.c.ipv4-multicast.ttl-out-of-range", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "IPv4 multicast c= TTL must be 0-255",
  spec_ref         = "RFC 8866 §5.7",
  verified         = true,
})

M.register("sdp.c.ipv4-multicast.numaddr-invalid", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "IPv4 multicast c= '<numaddr>' must be a positive integer",
  spec_ref         = "RFC 8866 §9 (IP4-multicast ABNF)",
  verified         = true,
})

M.register("sdp.c.ipv4-unicast.suffix-not-allowed", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "IPv4 unicast c= address must not include a '/' suffix",
  spec_ref         = "RFC 8866 §5.7",
  verified         = true,
})

M.register("sdp.c.ipv6-multicast.suffix-form-invalid", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "IPv6 multicast c= suffix must be '/<numaddr>' (no TTL field)",
  spec_ref         = "RFC 8866 §9 (IP6-multicast ABNF)",
  verified         = true,
})

M.register("sdp.c.ipv6-multicast.numaddr-invalid", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "IPv6 multicast c= '<numaddr>' must be a positive integer",
  spec_ref         = "RFC 8866 §9 (IP6-multicast ABNF)",
  verified         = true,
})

M.register("sdp.c.ipv6-unicast.suffix-not-allowed", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "IPv6 unicast c= address must not include a '/' suffix",
  spec_ref         = "RFC 8866 §5.7",
  verified         = true,
})

-- RFC 8866 §5.7: "A session description MUST contain either at least one
-- 'c=' line in each media description or a single 'c=' line at the session
-- level." A session-level c= covers every media block; otherwise every
-- media block must carry its own c=. With zero media blocks the SHALL is
-- vacuously satisfied (the "each media description" branch reduces to
-- true). field_path points at the first media block missing c= when the
-- session-level fallback is absent.
M.register("sdp.session.connection-required", {
  kind             = "semantic",
  default_severity = "error",
  code             = "MISSING_FIELD",
  message_template =
    "session must contain a connection address (c=) at session level"
    .. " or in every media description",
  spec_ref         = "RFC 8866 §5.7",
  verified         = true,
})

-- ── ST 2110 rtpmap narrowings per media type (Phase 6.B) ───────────────────
-- Each ST 2110 essence has a defined encoding-name × media-type × clock-rate
-- triple. Cited against primary spec text via the Phase-3 audit
-- (audits/SPEC_INVENTORY.md). These narrowings are scoped to a media block
-- whose rtpmap encoding matches the listed name; an SDP without that
-- encoding does not invoke the check.

-- ST 2110-20:2022 §7.1 — uncompressed video.
-- "The video streams described in this standard shall be declared in the
-- SDP using the Media Type name video and the Media Subtype name raw."
M.register("st2110-20.a.rtpmap.raw-media-type", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "rtpmap encoding 'raw' requires m=video",
  spec_ref         = "ST 2110-20:2022 §7.1",
  verified         = true,
})
-- ST 2110-20:2022 §7.1 + §6.1.3 — "The RTP Clock rate ... shall be 90 kHz"
-- and "The rtpmap clause of the SDP shall indicate the 90 kHz RTP Clock rate."
M.register("st2110-20.a.rtpmap.raw-clock-rate", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "rtpmap clock rate must be 90000 for encoding 'raw'",
  spec_ref         = "ST 2110-20:2022 §7.1",
  verified         = true,
})

-- ST 2110-22:2022 §6.2 — "The subtype name shall be the name registered for
-- the payload format." RFC 9134 registers `video/jxsv`, so jxsv lives under
-- the video media type by definition.
M.register("st2110-22.a.rtpmap.jxsv-media-type", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "rtpmap encoding 'jxsv' requires m=video",
  spec_ref         = "ST 2110-22:2022 §6.2 / RFC 9134",
  verified         = true,
})
-- ST 2110-22:2022 §5.2 — "The RTP Timestamp Clock rate shall be 90 kHz."
M.register("st2110-22.a.rtpmap.jxsv-clock-rate", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "rtpmap clock rate must be 90000 for encoding 'jxsv'",
  spec_ref         = "ST 2110-22:2022 §5.2",
  verified         = true,
})

-- ST 2110-40 / RFC 8331 — ANC data. RFC 8331 §4 registers `video/smpte291`,
-- making `m=video` the only legal SDP media-type for smpte291 streams.
M.register("st2110-40.a.rtpmap.smpte291-media-type", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "rtpmap encoding 'smpte291' requires m=video",
  spec_ref         = "RFC 8331 §4",
  verified         = true,
})
-- ST 2110-40:2023 §5.3 — "The RTP Clock rate shall be 90 kHz."
M.register("st2110-40.a.rtpmap.smpte291-clock-rate", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "rtpmap clock rate must be 90000 for encoding 'smpte291'",
  spec_ref         = "ST 2110-40:2023 §5.3",
  verified         = true,
})

-- ST 2110-31:2022 §6.1 — "Streams under this standard shall be signaled in
-- the SDP using the media type 'audio' and the media subtype 'AM824'."
M.register("st2110-31.a.rtpmap.am824-media-type", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "rtpmap encoding 'AM824' requires m=audio",
  spec_ref         = "ST 2110-31:2022 §6.1",
  verified         = true,
})
-- ST 2110-31:2022 §6.1 — "The <clock-rate> parameter shall take one of the
-- values 44100, 48000, or 96000."
M.register("st2110-31.a.rtpmap.am824-clock-rate-set", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "rtpmap clock rate for 'AM824' must be one of {44100, 48000, 96000}",
  spec_ref         = "ST 2110-31:2022 §6.1",
  verified         = true,
})

-- ── ST 2110-20 raw fmtp parameter form narrowings (Phase 6.C.B) ───────────
-- ST 2110-20:2022 §7.1 — "Each media type parameter entry shall be
-- constructed as either: a <name>=<value> pair, with no whitespace within
-- the name or value or between the name, equal sign, and value;
-- a <name> standalone declaration, with no whitespace within the name."
-- Scope: applies only when the surrounding rtpmap encoding is `raw`. Other
-- ST 2110 essence specs do not carry this prohibition.
M.register("st2110-20.a.fmtp.no-whitespace-around-equals", {
  kind             = "hard-syntactic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "fmtp parameter must not have whitespace around '='",
  spec_ref         = "ST 2110-20:2022 §7.1",
  verified         = true,
})

-- ── ST 2110-20 raw video required fmtp parameters (Phase 6.C.C) ───────────
-- ST 2110-20:2022 §7.2 lists eight required Media Type Parameters for raw
-- video streams: sampling, depth, width, height, exactframerate,
-- colorimetry, PM, SSN. (depth is normatively defined in §7.4.2 but listed
-- in the §7.2 required set.) ST 2110-21:2022 §8.1 adds TP as required for
-- every raw video stream conforming to ST 2110-21 — and ST 2110-20:2022
-- §6.1.1 requires every raw stream to conform to ST 2110-21.
--
-- Each registration below covers one required parameter. Scope: a=fmtp on
-- a payload type whose a=rtpmap encoding is `raw`.
local REQUIRED_RAW_PARAMS = {
  { "sampling",       "ST 2110-20:2022 §7.2"   },
  { "width",          "ST 2110-20:2022 §7.2"   },
  { "height",         "ST 2110-20:2022 §7.2"   },
  { "exactframerate", "ST 2110-20:2022 §7.2"   },
  { "depth",          "ST 2110-20:2022 §7.4.2" },
  { "colorimetry",    "ST 2110-20:2022 §7.2"   },
  { "PM",             "ST 2110-20:2022 §7.2"   },
  { "SSN",            "ST 2110-20:2022 §7.2"   },
  { "TP",             "ST 2110-21:2022 §8.1"   },
}

for _, p in ipairs(REQUIRED_RAW_PARAMS) do
  local key, ref = p[1], p[2]
  M.register("st2110-20.a.fmtp." .. key .. "-required", {
    kind             = "semantic",
    default_severity = "error",
    code             = "MISSING_FIELD",
    message_template =
      "fmtp for raw video must include required '" .. key .. "' parameter",
    spec_ref         = ref,
    verified         = true,
  })
end

-- ── ST 2110-20 raw video fmtp value-set narrowings — enums (Phase 6.C.D.1) ─
-- ST 2110-20:2022 enumerates the permitted value set for each Media Type
-- parameter listed below. The corresponding error id fires when the
-- parameter is PRESENT on a raw video fmtp with a value outside the set;
-- absence is the *-required check's job.
local ENUM_RAW_PARAMS = {
  { "sampling",    "ST 2110-20:2022 §7.2"   },
  { "depth",       "ST 2110-20:2022 §7.4.2" },
  { "colorimetry", "ST 2110-20:2022 §7.5"   },
  { "PM",          "ST 2110-20:2022 §6.3"   },  -- §7.2 names PM; §6.3 defines values
  { "TP",          "ST 2110-21:2022 §8.1"   },
  { "TCS",         "ST 2110-20:2022 §7.6"   },
  { "RANGE",       "ST 2110-20:2022 §7.3"   },
}

for _, p in ipairs(ENUM_RAW_PARAMS) do
  local key, ref = p[1], p[2]
  M.register("st2110-20.a.fmtp." .. key .. "-invalid-value", {
    kind             = "semantic",
    default_severity = "error",
    code             = "INVALID_VALUE",
    message_template =
      "fmtp '" .. key .. "' value not in the permitted set",
    spec_ref         = ref,
    verified         = true,
  })
end

-- ── ST 2110-20 raw video fmtp value-form narrowings — non-enum (6.C.D.2) ──
-- Six parameters carry value FORMS rather than enumerated sets — integer
-- ranges, fractions in lowest terms, or fixed patterns. Each fires when
-- the parameter is PRESENT on a raw video fmtp with a value that doesn't
-- match the defined form; absence is the *-required check's job.
local NON_ENUM_RAW_PARAMS = {
  -- §7.2: width / height integers 1..32767 inclusive.
  { "width",          "ST 2110-20:2022 §7.2",
    "fmtp 'width' must be a positive integer between 1 and 32767" },
  { "height",         "ST 2110-20:2022 §7.2",
    "fmtp 'height' must be a positive integer between 1 and 32767" },
  -- §7.2: positive integer OR positive_n/positive_d in lowest terms.
  { "exactframerate", "ST 2110-20:2022 §7.2",
    "fmtp 'exactframerate' must be a positive integer or a positive"
    .. " n/d ratio in lowest terms" },
  -- §7.3: positive integer, no greater than the §6.4 Extended UDP Size
  -- Limit (8960 octets).
  { "MAXUDP",         "ST 2110-20:2022 §7.3",
    "fmtp 'MAXUDP' must be a positive integer not exceeding 8960" },
  -- §7.3: W:H with both positive and in lowest terms ("smallest integer
  -- values possible for width and height shall be used").
  { "PAR",            "ST 2110-20:2022 §7.3",
    "fmtp 'PAR' must be W:H with both positive integers in lowest terms" },
  -- §7.2: identifies the spec revision the sender implements; only two
  -- forms defined: ST2110-20:2017 and ST2110-20:2022.
  { "SSN",            "ST 2110-20:2022 §7.2",
    "fmtp 'SSN' must be ST2110-20:2017 or ST2110-20:2022" },
}

for _, p in ipairs(NON_ENUM_RAW_PARAMS) do
  local key, ref, msg = p[1], p[2], p[3]
  M.register("st2110-20.a.fmtp." .. key .. "-invalid-value", {
    kind             = "semantic",
    default_severity = "error",
    code             = "INVALID_VALUE",
    message_template = msg,
    spec_ref         = ref,
    verified         = true,
  })
end

-- ── ST 2110-20 §7.3 flag-only parameters (Phase 6.C.D.2) ──────────────────
-- §7.3 defines `interlace` and `segmented` as bare-attribute flags
-- ("...the optional 'interlace' parameter shall be set" — no value form
-- defined). Signaling either as a key=value pair is invalid.
local FLAG_ONLY_RAW_PARAMS = { "interlace", "segmented" }

for _, key in ipairs(FLAG_ONLY_RAW_PARAMS) do
  M.register("st2110-20.a.fmtp." .. key .. "-invalid-value", {
    kind             = "semantic",
    default_severity = "error",
    code             = "INVALID_VALUE",
    message_template =
      "fmtp '" .. key .. "' must be a bare flag (no '=value')",
    spec_ref         = "ST 2110-20:2022 §7.3",
    verified         = true,
  })
end

-- ── ST 2110-20 raw video fmtp cross-parameter SHALLs (Phase 6.C.E) ────────
-- Each entry below names a cross-parameter constraint: a SHALL or SHALL-NOT
-- that evaluates a RELATIONSHIP between two or more fmtp parameter values
-- (or between a value and the presence/absence of another). Per-key
-- presence and value-set narrowings live in 6.C.C / 6.C.D.

-- §7.2 SSN-conditional (JT-NM Tested — AMWA sdpoker Issue #11): a
-- :2022-only value (TCS=ST2115LOGS3 or colorimetry=ALPHA) must be paired
-- with SSN=ST2110-20:2022. Reverse direction ("SSN=:2022 without
-- :2022-only values forbidden") is deferred per PLAN.md known items.
M.register("st2110-20.a.fmtp.ssn-required-for-2022-only-values", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "SSN must be ST2110-20:2022 when a :2022-only value is signaled"
    .. " (TCS=ST2115LOGS3 or colorimetry=ALPHA)",
  spec_ref         = "ST 2110-20:2022 §7.2",
  verified         = true,
})

-- §7.3: "When the colorimetry value is BT2100, only the NARROW and FULL
-- values are permitted." Implies RANGE=FULLPROTECT is forbidden with
-- colorimetry=BT2100. Per-key RANGE value-set is already enforced in
-- 6.C.D.1; this is the additional cross-parameter narrowing.
M.register("st2110-20.a.fmtp.bt2100-range-fullprotect-forbidden", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "RANGE=FULLPROTECT is not permitted with colorimetry=BT2100"
    .. " (only NARROW and FULL are permitted)",
  spec_ref         = "ST 2110-20:2022 §7.3",
  verified         = true,
})

-- §7.3: "Signaling of [segmented] without the interlace parameter is
-- forbidden." (PsF requires interlace to be set as well.)
M.register("st2110-20.a.fmtp.segmented-requires-interlace", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "fmtp 'segmented' requires 'interlace' to also be present",
  spec_ref         = "ST 2110-20:2022 §7.3",
  verified         = true,
})

-- §6.3.3: "The Extended UDP size limit defined in SMPTE ST 2110-10 shall
-- not be used in the Block Packing Mode." MAXUDP signals operation
-- beyond the Standard UDP limit, so its presence with PM=2110BPM
-- violates §6.3.3.
M.register("st2110-20.a.fmtp.bpm-with-maxudp-forbidden", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "MAXUDP must not be signaled with PM=2110BPM"
    .. " (Block Packing Mode forbids Extended UDP size)",
  spec_ref         = "ST 2110-20:2022 §6.3.3",
  verified         = true,
})

-- §7.4.1: "the Key stream shall signal the colorimetry value 'ALPHA', and
-- shall not signal a TCS value." Two distinct SHALLs on sampling=KEY,
-- registered as two separate IDs so an audit can grep each independently.
M.register("st2110-20.a.fmtp.key-requires-alpha-colorimetry", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "sampling=KEY requires colorimetry=ALPHA",
  spec_ref         = "ST 2110-20:2022 §7.4.1",
  verified         = true,
})

M.register("st2110-20.a.fmtp.key-forbids-tcs", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "sampling=KEY must not signal a TCS value",
  spec_ref         = "ST 2110-20:2022 §7.4.1",
  verified         = true,
})

-- §6.2.5: "The 4:2:0 sampling system shall only be applied to progressive
-- scan images transmitted in a progressive manner. This sampling system
-- does not apply to PsF or interlaced video essence." Scoped to raw
-- video only: §6.2.5 is in the §6 RTP-payload chapter; jxsv inherits the
-- §7 sampling value set but not §6 packaging constraints (RFC 9134 §7.1).
M.register("st2110-20.a.fmtp.subsampling-420-with-interlace-forbidden", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "4:2:0 sampling must not be combined with interlace"
    .. " (progressive scan only)",
  spec_ref         = "ST 2110-20:2022 §6.2.5",
  verified         = true,
})

-- ── ST 2110-20 raw video fmtp 1.0-gap closes (Phase 6.C.F) ────────────────
-- Five cross-parameter SHALLs that are normatively in ST 2110-20:2022 but
-- the 1.0 parser does NOT enforce. Grounded by CLAUDE.md strictness
-- polarity #3 (defined value forms) rather than explicit SHALL prose: each
-- constraint is a *defined value combination* in a spec table or row that
-- carries a `(depth=...)` parenthetical. Audit rows: 61, 115, 116, 117, 118.

-- §6.2.5 Table 3 — 4:2:0 pgroup construction. The table lists 4:2:0
-- sampling tokens (YCbCr-4:2:0, CLYCbCr-4:2:0, ICtCp-4:2:0) with depths
-- {8, 10, 12} only. depth ∈ {16, 16f} is not in the defined table → reject.
M.register("st2110-20.a.fmtp.subsampling-420-depth-restricted", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "4:2:0 sampling requires depth ∈ {8, 10, 12};"
    .. " depths 16 and 16f are not defined by Table 3",
  spec_ref         = "ST 2110-20:2022 §6.2.5 Table 3",
  verified         = true,
})

-- §7.6 TCS table — four "floating-point linear" TCS values are defined
-- with a `(depth=16f)` parenthetical in the row prose. When the TCS is
-- one of these, depth must be 16f. Separate IDs per TCS value so an
-- audit can grep each independently (matches the per-row inventory).
local TCS_REQUIRES_16F = {
  { "LINEAR",       "linear" },
  { "BT2100LINPQ",  "bt2100linpq" },
  { "BT2100LINHLG", "bt2100linhlg" },
  { "ST2065-1",     "st2065-1" },
}

for _, p in ipairs(TCS_REQUIRES_16F) do
  local _, slug = p[1], p[2]
  M.register("st2110-20.a.fmtp.tcs-" .. slug .. "-requires-depth-16f", {
    kind             = "semantic",
    default_severity = "error",
    code             = "INVALID_VALUE",
    message_template =
      "TCS=" .. p[1] .. " is defined with depth=16f;"
      .. " other depth values are not permitted by §7.6",
    spec_ref         = "ST 2110-20:2022 §7.6",
    verified         = true,
  })
end

-- ── ST 2110-22 jxsv fmtp narrowings (Phase 6.C.G.1) ───────────────────────
-- ST 2110-22:2022 §7.2 Table 1 lists three required jxsv format-specific
-- parameters: width, height, TP. RFC 9134 §7.1 (IANA video/jxsv) adds
-- packetmode as required, and defines value forms for the optional set
-- (sampling, exactframerate, depth, TCS, colorimetry, RANGE, transmode,
-- profile, level, sublevel, interlace, segmented).
--
-- Per-tier scope: a fmtp check fires only when its payload-type's rtpmap
-- encoding is `jxsv`. ctx.rtpmap_encodings carries the binding from the
-- a_rtpmap override (same mechanism as -20 raw).
--
-- Spec divergence from 1.0 parser: 1.0 reuses ST 2110-20's value sets for
-- jxsv `colorimetry` / `TCS` / `sampling`. RFC 9134 §7.1 defines its own
-- enums that overlap but are not identical. The grammar tier follows
-- RFC 9134 (primary spec text); see commit message for the diff.

-- Required-presence rows (ST 2110-22:2022 §7.2 Table 1 + RFC 9134 §7.1).
local REQUIRED_JXSV_PARAMS = {
  { "width",      "ST 2110-22:2022 §7.2"  },
  { "height",     "ST 2110-22:2022 §7.2"  },
  { "TP",         "ST 2110-22:2022 §7.2"  },
  { "packetmode", "RFC 9134 §7.1"         },
}

for _, p in ipairs(REQUIRED_JXSV_PARAMS) do
  local key, ref = p[1], p[2]
  M.register("st2110-22.a.fmtp." .. key .. "-required", {
    kind             = "semantic",
    default_severity = "error",
    code             = "MISSING_FIELD",
    message_template =
      "fmtp for jxsv must include required '" .. key .. "' parameter",
    spec_ref         = ref,
    verified         = true,
  })
end

-- Per-key value-set / value-form rows. Enum-typed and non-enum forms are
-- both registered under the `-invalid-value` suffix so the audit grep
-- pattern matches the -20 family one-for-one.
local JXSV_VALUE_FORM_PARAMS = {
  -- RFC 9134 §7.1 — required value forms
  { "width",          "ST 2110-22:2022 §7.2"  },
  { "height",         "ST 2110-22:2022 §7.2"  },
  { "TP",             "ST 2110-22:2022 §5.3"  },
  { "packetmode",     "RFC 9134 §7.1"         },
  -- RFC 9134 §7.1 — optional value forms
  { "sampling",       "RFC 9134 §7.1"         },
  { "exactframerate", "RFC 9134 §7.1"         },
  { "depth",          "RFC 9134 §7.1"         },
  { "TCS",            "RFC 9134 §7.1"         },
  { "colorimetry",    "RFC 9134 §7.1"         },
  { "RANGE",          "RFC 9134 §7.1"         },
  { "transmode",      "RFC 9134 §7.1"         },
  { "profile",        "RFC 9134 §7.1"         },
  { "level",          "RFC 9134 §7.1"         },
  { "sublevel",       "RFC 9134 §7.1"         },
  -- ST 2110-22:2022 §7.2 Table 2 optional rows (year-specific value form)
  { "SSN",            "ST 2110-22:2022 §7.2"  },
  -- ST 2110-10 §6.4 — Extended UDP Size Limit (referenced by ST 2110-22)
  { "MAXUDP",         "ST 2110-10 §6.4"       },
  -- ST 2110-21:2022 §8.2 — CMAX integer form (referenced by ST 2110-22)
  { "CMAX",           "ST 2110-21:2022 §8.2"  },
}

for _, p in ipairs(JXSV_VALUE_FORM_PARAMS) do
  local key, ref = p[1], p[2]
  M.register("st2110-22.a.fmtp." .. key .. "-invalid-value", {
    kind             = "semantic",
    default_severity = "error",
    code             = "INVALID_VALUE",
    message_template =
      "fmtp '" .. key .. "' value does not satisfy the defined value form",
    spec_ref         = ref,
    verified         = true,
  })
end

-- RFC 9134 §7.1 — interlace and segmented are bare-attribute flags;
-- signaling either as `key=value` is invalid. Same form as -20 §7.3 but
-- different normative source, so separate IDs.
local JXSV_FLAG_ONLY_PARAMS = { "interlace", "segmented" }

for _, key in ipairs(JXSV_FLAG_ONLY_PARAMS) do
  M.register("st2110-22.a.fmtp." .. key .. "-invalid-value", {
    kind             = "semantic",
    default_severity = "error",
    code             = "INVALID_VALUE",
    message_template =
      "fmtp '" .. key .. "' must be a bare flag (no '=value')",
    spec_ref         = "RFC 9134 §7.1",
    verified         = true,
  })
end

-- ── ST 2110-22 jxsv fmtp cross-parameter SHALLs (Phase 6.C.G.2) ───────────
-- Two cross-parameter SHALLs in RFC 9134 §7.1 — same constraints the -20
-- raw-video tier enforces but with their own normative source. Separate
-- IDs from the -20 family so audit grep can target either independently.

-- RFC 9134 §7.1 segmented row: "Signaling of this parameter without the
-- interlace parameter is forbidden."
M.register("st2110-22.a.fmtp.segmented-requires-interlace", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "fmtp 'segmented' requires 'interlace' to also be present",
  spec_ref         = "RFC 9134 §7.1",
  verified         = true,
})

-- RFC 9134 §7.1 RANGE row: "When paired with [BT.2100-2] colorimetry,
-- the allowed values are NARROW and FULL, corresponding to the ranges
-- specified in TABLE 9 of [BT.2100-2]." Implies FULLPROTECT forbidden
-- when colorimetry=BT2100. Per-key RANGE value-set is enforced in 6.C.G.1.
M.register("st2110-22.a.fmtp.bt2100-range-fullprotect-forbidden", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "RANGE=FULLPROTECT is not permitted with colorimetry=BT2100"
    .. " (only NARROW and FULL are permitted per RFC 9134 §7.1)",
  spec_ref         = "RFC 9134 §7.1",
  verified         = true,
})

-- ── ST 2110-30 audio channel-order syntax (Phase 6.C.H) ───────────────────
-- ST 2110-30:2025 §6.2.2: "If channel order is signaled in the SDP, the
-- syntax of IETF RFC 3190 for the parameter channel-order shall be used."
-- RFC 3190 §6: `<convention>.<order>`. When convention is `SMPTE2110`,
-- the order SHALL be `(<group>[,<group>...])` with each group from
-- ST 2110-30 §6.2.2 Table 1 ({M, DM, ST, LtRt, 51, 71, 222, SGRP}) or a
-- Unn track symbol (U01–U64). Spec is silent on other conventions —
-- accept structurally. Applies to L16, L24, AM824 audio.
M.register("st2110-30.a.fmtp.channel-order-invalid", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "fmtp 'channel-order' must follow RFC 3190 syntax;"
    .. " SMPTE2110 convention requires (group[,group...]) with"
    .. " known group symbols",
  spec_ref         = "ST 2110-30:2025 §6.2.2",
  verified         = true,
})

-- ST 2110-31:2022 §6.2 Table 2 defines the AES3 channel-order group as
-- AM824-only ("The symbol AES3 is defined for use with AM824 streams").
-- Signaling AES3 on L16 / L24 PCM audio is invalid.
M.register("st2110-31.a.fmtp.channel-order-aes3-requires-am824", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "channel-order group 'AES3' is defined only for AM824 streams",
  spec_ref         = "ST 2110-31:2022 §6.2",
  verified         = true,
})

-- ── ST 2110-31 AM824 rtpmap channel-count parity (Phase 6.C.I) ────────────
-- ST 2110-31:2022 §6.1: "the number of AES3 Subframe sequences <nchan>
-- expressed in the SDP object shall always be an even number." AM824
-- transports AES3 signals, and each AES3 signal contains two sequences of
-- AES3 Subframes, so the SDP channel count must be even. This check is
-- registered under the rtpmap namespace because <nchan> appears in
-- a=rtpmap, not a=fmtp.
M.register("st2110-31.a.rtpmap.am824-channels-must-be-even", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "AM824 rtpmap channel count must be an even number"
    .. " (each AES3 signal carries two subframe sequences)",
  spec_ref         = "ST 2110-31:2022 §6.1",
  verified         = true,
})

-- ── ST 2110-41 Fast Metadata fmtp narrowings (Phase 6.C.J) ────────────────
-- ST 2110-41:2024 §6 (Required Parameters) requires SSN, and §6 also
-- defines DIT as optional with a constrained value form (uppercase hex
-- tokens, comma-separated, no '0x' prefix, no whitespace). §5.4 forbids
-- MAXUDP on ST 2110-41 streams ("The total length of the UDP packet …
-- shall be less than or equal to the Standard UDP Size Limit").

M.register("st2110-41.a.fmtp.SSN-required", {
  kind             = "semantic",
  default_severity = "error",
  code             = "MISSING_FIELD",
  message_template =
    "fmtp for ST 2110-41 must include required 'SSN' parameter",
  spec_ref         = "ST 2110-41:2024 §6",
  verified         = true,
})

-- §6 defines only one SSN value: ST2110-41:2024.
M.register("st2110-41.a.fmtp.SSN-invalid-value", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "fmtp 'SSN' must be ST2110-41:2024 (the only revision defined)",
  spec_ref         = "ST 2110-41:2024 §6",
  verified         = true,
})

-- §6: "The hexadecimal values shall not include the leading '0x' and any
-- alphabetic characters shall be uppercase. Whitespace characters shall
-- not appear in the comma-separated list of values."
M.register("st2110-41.a.fmtp.DIT-invalid-value", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "fmtp 'DIT' must be comma-separated uppercase hex tokens"
    .. " (no '0x' prefix, no whitespace)",
  spec_ref         = "ST 2110-41:2024 §6",
  verified         = true,
})

-- §5.4: "The total length of the UDP packet that encompasses each RTP
-- Packet shall be less than or equal to the Standard UDP Size Limit
-- defined in SMPTE ST 2110-10." MAXUDP signals operation beyond that
-- limit (ST 2110-10:2022 §6.4), so its presence violates §5.4.
M.register("st2110-41.a.fmtp.maxudp-forbidden", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "MAXUDP must not be signaled on ST 2110-41 streams"
    .. " (§5.4 limits UDP size to the Standard UDP Size Limit)",
  spec_ref         = "ST 2110-41:2024 §5.4",
  verified         = true,
})

-- ── ST 2110-10 required-attribute presence (Phase 6.D.A) ─────────────────
-- ST 2110-10:2022 §8.2: "All stream descriptions shall have a ts-refclk
-- attribute as specified in IETF RFC 7273 section 4."
-- ST 2110-10:2022 §8.3: "All stream descriptions shall have a media-level
-- mediaclk attribute as per IETF RFC 7273 section 5."
-- Both SHALLs are per-media-section presence requirements. Value-form
-- validation lives in the base grammar (RFC 7273 ABNF for ts-refclk and
-- mediaclk bodies); these checks only assert the attribute appears on
-- every media block. The §8.3 SHALL is satisfied only by a media-level
-- attribute, so a session-level mediaclk does not cover a media block
-- that lacks its own.

-- ── Phase 6.E.B — ST 2110-10 §8.5 group:DUP leg coherence ───────────────
-- ST 2110-10:2022 §8.5: "Duplicate RTP streams meeting the requirements
-- of SMPTE ST 2022-7 may be used for redundant transmission… Senders…
-- shall signal the RTP duplication using the session level group
-- attribute of IETF RFC 5888 and the duplication grouping DUP semantics
-- of IETF RFC 7104."
--
-- ST 2022-7:2019 §6 (verified on disk at /tmp/st2022-7.txt:234-236):
--   "The transmitter shall transmit at least two streams, each
--    containing copies of each RTP datagram. The RTP header and the RTP
--    payload shall be identical for each datagram copy."
--
-- Chain-of-SHALLs grounding: §8.5 requires "meeting the requirements of
-- SMPTE ST 2022-7"; §6 requires (a) at least two streams and (b)
-- bit-identical RTP header + payload across copies. SDP attributes that
-- DEFINE the RTP packet shape — media type (from m=), rtpmap (encoding
-- + clock rate), payload type number, fmtp essence parameters — must
-- therefore match across DUP legs, else the legs cannot satisfy §6's
-- bit-identity SHALL and the §8.5 SHALL is violated. The SDP-side cite
-- is §8.5 throughout; the §6 chain lives in error message comments.
--
-- §8.5 also directly forbids: "Redundant streams shall not use both
-- identical source addresses and identical destination addresses at
-- the same time" — the address-coherence check.

M.register("st2110-10.a.group-dup.mid-resolve", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "a=group:DUP tag does not resolve to any a=mid in the session"
    .. " (an unresolved tag reduces the effective leg count, breaking"
    .. " ST 2022-7 §6's 'at least two streams' SHALL chained from"
    .. " ST 2110-10 §8.5)",
  spec_ref         = "ST 2110-10:2022 §8.5",
  verified         = true,
})

M.register("st2110-10.a.group-dup.min-2-legs", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "a=group:DUP must have at least two resolved legs"
    .. " (ST 2022-7 §6: 'The transmitter shall transmit at least two"
    .. " streams')",
  spec_ref         = "ST 2110-10:2022 §8.5",
  verified         = true,
})

M.register("st2110-10.a.group-dup.media-type-same", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "a=group:DUP legs must have the same m= media type"
    .. " (ST 2022-7 §6 requires bit-identical RTP payload; different"
    .. " media types cannot satisfy that SHALL)",
  spec_ref         = "ST 2110-10:2022 §8.5",
  verified         = true,
})

M.register("st2110-10.a.group-dup.rtpmap-same", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "a=group:DUP legs must have the same a=rtpmap encoding and clock"
    .. " rate (ST 2022-7 §6 requires bit-identical RTP payload)",
  spec_ref         = "ST 2110-10:2022 §8.5",
  verified         = true,
})

M.register("st2110-10.a.group-dup.payload-type-same", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "a=group:DUP legs must use the same RTP payload type number"
    .. " (ST 2022-7 §6's bit-identical RTP header SHALL includes the"
    .. " PT field)",
  spec_ref         = "ST 2110-10:2022 §8.5",
  verified         = true,
})

M.register("st2110-10.a.group-dup.fmtp-same", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "a=group:DUP legs must have identical a=fmtp essence parameters"
    .. " (ST 2022-7 §6's bit-identical RTP payload SHALL implies"
    .. " identical signaled essence)",
  spec_ref         = "ST 2110-10:2022 §8.5",
  verified         = true,
})

M.register("st2110-10.a.group-dup.addr-coherence", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "a=group:DUP legs must not share BOTH source address and"
    .. " destination address (ST 2110-10:2022 §8.5: 'Redundant streams"
    .. " shall not use both identical source addresses and identical"
    .. " destination addresses at the same time')",
  spec_ref         = "ST 2110-10:2022 §8.5",
  verified         = true,
})

-- ── Phase 6.E.A — RFC 5888 group attribute cross-stream invariants ──────
-- RFC 5888 §6: "All of the 'm' lines of a session description that uses
-- 'group' MUST be identified with a 'mid' attribute whether they appear
-- in the group line(s) or not." Conditional MUST: triggered by presence
-- of any session-level a=group. Semantics-independent (LS, FID, DUP, …).
M.register("sdp.a.group.requires-mid-on-all-media", {
  kind             = "semantic",
  default_severity = "error",
  code             = "MISSING_FIELD",
  message_template =
    "media block lacks a=mid required when session contains a=group"
    .. " (RFC 5888 §6 requires every m= line to carry an identification"
    .. " tag whether or not it appears in a group line)",
  spec_ref         = "RFC 5888 §6",
  verified         = true,
})

-- RFC 5888 §9.2: "SIP entities refuse media streams by setting the port
-- to zero in the corresponding 'm' line. 'a=group' lines MUST NOT
-- contain identification-tags that correspond to 'm' lines with the
-- port set to zero." A port-0 m= signals a refused / inactive stream;
-- including its mid in a group is incoherent.
M.register("sdp.a.group.references-port-zero-mid", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "a=group references a mid whose m= line has port=0"
    .. " (port 0 marks the stream as refused / inactive; RFC 5888 §9.2"
    .. " forbids grouping refused streams)",
  spec_ref         = "RFC 5888 §9.2",
  verified         = true,
})

-- ── Phase 6.D.D — ST 2110-30 audio packet-payload-fit ───────────────────
-- ST 2110-30:2025 §6.2.1: "The Standard UDP Datagram Size Limit as
-- defined in SMPTE ST 2110-10 shall be used." ST 2110-10:2022 §6.4 sets
-- that Limit at 1460 octets (UDP payload). After subtracting the RTP
-- fixed header (12 octets per RFC 3550), the RTP payload available for
-- audio samples is 1448 octets per packet.
--
-- For PCM audio the packet payload is channels × bytes_per_sample ×
-- samples_per_packet, where samples_per_packet = round(clock_rate *
-- ptime / 1000) per AES67 §8.1. A combination exceeding 1448 octets
-- violates §6.2.1's SHALL.
--
-- Scope is L16 / L24 only (matching 6.D.B). AM824 is deferred because
-- ST 2110-31 has no UDP-size SHALL of its own.
M.register("st2110-30.audio.packet-payload-fit", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "audio packet RTP payload exceeds the Standard UDP Size Limit"
    .. " (channels × bytes-per-sample × samples-per-packet must fit"
    .. " in 1448 octets = 1460 UDP - 12 RTP); reduce ptime or channels",
  spec_ref         = "ST 2110-30:2025 §6.2.1",
  verified         = true,
})

-- ── Phase 6.D.C — ST 2110-31 AM824 rtpmap channels-required ─────────────
-- ST 2110-31:2022 §6.1: "The number of AES3 Subframe sequences multiplexed
-- within the payload shall be signaled in the SDP object on the a=rtpmap
-- line, using the syntactic field which typically communicates the number
-- of channels in an audio signal, as shown below: a=rtpmap:<pt> AM824/
-- <clock-rate>/<nchan>". The <nchan> field is therefore mandatory for any
-- AM824 rtpmap (the SHALL is on signaling the count via that field).
--
-- L16 / L24 channels-required is intentionally NOT enforced. The 1.0
-- parser tightens RFC 3551 §6 (which says channels is OPTIONAL and may
-- be omitted when 1) for L16 / L24 too, claiming "ST 2110-30 tightens
-- this." Primary text of ST 2110-30:2025 / AES67-2013 / RFC 3551 does
-- not carry that SHALL; the 1.0 limb stays flagged for audit follow-up.
M.register("st2110-31.a.rtpmap.am824-channels-required", {
  kind             = "semantic",
  default_severity = "error",
  code             = "MISSING_FIELD",
  message_template =
    "AM824 rtpmap must signal the number of AES3 Subframe sequences"
    .. " in the channels field (a=rtpmap:<pt> AM824/<clock-rate>/<nchan>)",
  spec_ref         = "ST 2110-31:2022 §6.1",
  verified         = true,
})

-- ── Phase 6.D.B — ST 2110-30 audio MAXUDP-forbidden ─────────────────────
-- ST 2110-30:2025 §6.2.1: "The Standard UDP Datagram Size Limit as
-- defined in SMPTE ST 2110-10 shall be used." Combined with ST 2110-10:2022
-- §6.4 / §8.6 (MAXUDP signals operation beyond the Standard Limit), a
-- conformant L16 / L24 stream cannot carry MAXUDP.
--
-- Scope is L16 / L24 only. The 1.0 parser also forbids MAXUDP for AM824
-- with cite "ST 2110-31 §5.x inherits"; -31 §5.2 actually defers to
-- ST 2110-10 which *permits* MAXUDP (§6.5). Primary text of -31 has no
-- MAXUDP-forbidden SHALL. The grammar tier intentionally drops the
-- AM824 limb of this check pending a separate audit-folder follow-up.
M.register("st2110-30.a.fmtp.maxudp-forbidden", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "MAXUDP must not be signaled on L16 / L24 audio streams"
    .. " (§6.2.1 requires the Standard UDP Size Limit; MAXUDP signals"
    .. " operation beyond that limit)",
  spec_ref         = "ST 2110-30:2025 §6.2.1",
  verified         = true,
})

M.register("st2110.attr.ts-refclk-required", {
  kind             = "semantic",
  default_severity = "error",
  code             = "MISSING_FIELD",
  message_template =
    "media block must include an 'a=ts-refclk' attribute"
    .. " (every ST 2110 stream description requires one)",
  spec_ref         = "ST 2110-10:2022 §8.2",
  verified         = true,
})

-- ST 2110-10:2022 §6.2: "All of the streams specified in this standard
-- shall use the Real-time Transport Protocol (RTP) as specified in IETF
-- RFC 3551 ... and shall conform to the RTP Profile specified in IETF
-- RFC 3551." The RTP Profile RFC 3551 defines is named "RTP/AVP" in
-- SDP. Scope: media blocks whose proto is RTP-shaped (proto starts with
-- "RTP/"); non-RTP transports (e.g. TR-10-14 USB at
-- `m=application <port> TCP usb`) are out of scope.
M.register("st2110-10.m.proto-must-be-rtp-avp", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "ST 2110 RTP streams must use the RTP/AVP profile"
    .. " (RFC 3551; only profile permitted by §6.2)",
  spec_ref         = "ST 2110-10:2022 §6.2",
  verified         = true,
})

-- ST 2110-10:2022 §8.7 — TSMODE / TSDELAY fmtp value forms. Cross-encoding:
-- the two parameters are defined under §8 "SDP Parameters" (not within
-- any media-type-specific section), so they may appear on any ST 2110
-- RTP stream's fmtp regardless of essence type.
--
-- TSMODE — §8.7: "Allowed values are: TSMODE=SAMP ... TSMODE=NEW ...
-- TSMODE=PRES." Three-value enum.
--
-- TSDELAY — §8.7: "The time value is represented as a decimal positive
-- integer number of microseconds." POS-DIGIT *DIGIT (>= 1; TSDELAY=0
-- is forbidden — see PLAN.md Known Deferred Items).
--
-- Out of scope: the §7.9-conditional "TSMODE=SAMP requires TSDELAY"
-- coupling — §8.7 restricts that pairing to §7.9 time-preserving
-- senders, which SDP alone cannot identify. The 1.0 parser enforced
-- the unconditional pairing; the grammar tier intentionally does not.
M.register("st2110-10.a.fmtp.tsmode-invalid-value", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "fmtp 'TSMODE' must be one of {SAMP, NEW, PRES} per §8.7",
  spec_ref         = "ST 2110-10:2022 §8.7",
  verified         = true,
})

M.register("st2110-10.a.fmtp.tsdelay-invalid-value", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "fmtp 'TSDELAY' must be a decimal positive integer (microseconds)",
  spec_ref         = "ST 2110-10:2022 §8.7",
  verified         = true,
})

M.register("st2110.attr.mediaclk-required", {
  kind             = "semantic",
  default_severity = "error",
  code             = "MISSING_FIELD",
  message_template =
    "media block must include a media-level 'a=mediaclk' attribute"
    .. " (every ST 2110 stream description requires one; session-level"
    .. " mediaclk does not satisfy the per-stream SHALL)",
  spec_ref         = "ST 2110-10:2022 §8.3",
  verified         = true,
})

-- ─── IPMX (TR-10 series) ────────────────────────────────────────────────────
-- Phase 7.B: TR-10-1 §10 baseline. The two SHALLs that constitute "this SDP
-- is IPMX": §10 forbids a=group:FID; §10.1 requires the 'IPMX' token in
-- a=fmtp on every RTP media block.

M.register("tr-10-1.a.group.fid-forbidden", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "a=group:FID is not permitted in IPMX"
    .. " (RFC 8331 §4.1 FID grouping conflicts with the 'one SDP object"
    .. " per RTP Stream' provision of SMPTE ST 2110-10)",
  spec_ref         = "TR-10-1 §10",
  verified         = true,
})

M.register("tr-10-1.a.fmtp.marker-required", {
  kind             = "semantic",
  default_severity = "error",
  code             = "MISSING_FIELD",
  message_template =
    "a=fmtp on an IPMX RTP media block must contain the 'IPMX' declaration",
  spec_ref         = "TR-10-1 §10.1",
  verified         = true,
})

-- TR-10-1 §10.2 (baseband video) + TR-10-9 §10 (non-baseband video):
-- every video IPMX block's a=fmtp MUST carry measuredpixclk, vtotal, and
-- htotal. Baseband senders report measured values; non-baseband senders
-- use substitute values (width*height*exactframerate, height, width).
-- The "non-baseband uses substitute values" SHALL is not validatable
-- from SDP alone (no baseband-vs-non-baseband state in SDP), but the
-- COMBINED effect of §10.2 + TR-10-9 §10 is that presence + positive-
-- integer form is required on every video IPMX block.

M.register("tr-10-1.a.fmtp.measuredpixclk-required", {
  kind             = "semantic",
  default_severity = "error",
  code             = "MISSING_FIELD",
  message_template = "a=fmtp on a video IPMX media block must include 'measuredpixclk'",
  spec_ref         = "TR-10-1 §10.2",
  verified         = true,
})

M.register("tr-10-1.a.fmtp.vtotal-required", {
  kind             = "semantic",
  default_severity = "error",
  code             = "MISSING_FIELD",
  message_template = "a=fmtp on a video IPMX media block must include 'vtotal'",
  spec_ref         = "TR-10-1 §10.2",
  verified         = true,
})

M.register("tr-10-1.a.fmtp.htotal-required", {
  kind             = "semantic",
  default_severity = "error",
  code             = "MISSING_FIELD",
  message_template = "a=fmtp on a video IPMX media block must include 'htotal'",
  spec_ref         = "TR-10-1 §10.2",
  verified         = true,
})

M.register("tr-10-1.a.fmtp.measuredpixclk-invalid-value", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "fmtp 'measuredpixclk' must be a positive integer (Hertz)",
  spec_ref         = "TR-10-1 §10.2",
  verified         = true,
})

M.register("tr-10-1.a.fmtp.vtotal-invalid-value", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "fmtp 'vtotal' must be a positive integer (total lines per frame)",
  spec_ref         = "TR-10-1 §10.2",
  verified         = true,
})

M.register("tr-10-1.a.fmtp.htotal-invalid-value", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "fmtp 'htotal' must be a positive integer (luminance sample periods per line)",
  spec_ref         = "TR-10-1 §10.2",
  verified         = true,
})

-- TR-10-1 §10.3 (baseband audio) + TR-10-9 §10 (non-baseband audio):
-- every audio IPMX block's a=fmtp MUST carry `measuredsamplerate`.
-- Baseband senders report the measured sample rate; non-baseband
-- senders use the rtpmap rate as the substitute. Either way, presence
-- + positive-integer Hertz form is required.

M.register("tr-10-1.a.fmtp.measuredsamplerate-required", {
  kind             = "semantic",
  default_severity = "error",
  code             = "MISSING_FIELD",
  message_template = "a=fmtp on an audio IPMX media block must include 'measuredsamplerate'",
  spec_ref         = "TR-10-1 §10.3",
  verified         = true,
})

M.register("tr-10-1.a.fmtp.measuredsamplerate-invalid-value", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "fmtp 'measuredsamplerate' must be a positive integer (Hertz)",
  spec_ref         = "TR-10-1 §10.3",
  verified         = true,
})

-- TR-10-2 §7 / TR-10-3 §7 / TR-10-4 §7 / TR-10-11 §7 / TR-10-12 §7 all
-- carry the same SHALL: "All IPMX Media streams shall have a UDP
-- destination port value that is even and that is greater than 1024."
-- Cite TR-10-2 §7 as canonical; the rule is identical across the
-- encoding-specific parts.

M.register("ipmx.m.port-must-be-even", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "m= UDP destination port must be even for IPMX RTP streams",
  spec_ref         = "TR-10-2 §7",
  verified         = true,
})

M.register("ipmx.m.port-must-exceed-1024", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "m= UDP destination port must be greater than 1024 for IPMX RTP streams",
  spec_ref         = "TR-10-2 §7",
  verified         = true,
})

-- ST 2110-22:2022 §7.3 (verbatim): "The media-level section of the SDP
-- object shall include the attribute listed in Table 3." Table 3's
-- only row is `b=<brtype>:<brvalue>` with `<brtype> shall be AS` and
-- `<brvalue>` an integer number of kilobits per second. Authored by
-- ST 2110-22:2022; TR-10-7 §11 substitutes only the Table 3 row's
-- cell contents (changes brvalue semantics from "average bit rate" to
-- "maximum target bit rate") but the wrapping §7.3 "shall include"
-- and per-row SHALLs persist verbatim by virtue of "shall be as
-- defined in RFC 4566" + the substituted Table 1 row. The check
-- therefore lives at the ST 2110 tier where its authoring SHALL
-- lives; IPMX inherits via composition.

M.register("st2110-22.b.as-required", {
  kind             = "semantic",
  default_severity = "error",
  code             = "MISSING_FIELD",
  message_template =
    "media block carrying a jxsv rtpmap must include a media-level"
    .. " b=AS:<kbps> attribute",
  spec_ref         = "ST 2110-22:2022 §7.3",
  verified         = true,
})

M.register("st2110-22.b.as-invalid-value", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "b=AS value must be a positive integer (kbps) on jxsv media blocks",
  spec_ref         = "ST 2110-22:2022 §7.3",
  verified         = true,
})

-- TR-10-10 §8 a=infoframe attribute (HDMI InfoFrame signaling).
-- Format: `a=infoframe:<port> SSN=ST2110-41:<year>;DIT=100100`.
-- SHALLs validated:
--   (1) Attribute appears only at the session level.
--   (2) SSN value starts with the literal "ST2110-41:" prefix.
--   (3) DIT value equals "100100" (HDMI Data-Item-Type code).
--   (4) Port equals one of the associated media blocks' port + 3.
--   (5) Port is unique across all session-level a=infoframe attributes
--       (a single device can carry multiple infoframe streams; one per
--        associated media stream).

M.register("tr-10-10.a.infoframe.must-be-session-level", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "a=infoframe must be a session-level attribute, not media-level",
  spec_ref         = "TR-10-10 §8",
  verified         = true,
})

M.register("tr-10-10.a.infoframe.ssn-invalid-form", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "a=infoframe SSN must use the form 'ST2110-41:<year>'",
  spec_ref         = "TR-10-10 §8",
  verified         = true,
})

M.register("tr-10-10.a.infoframe.dit-invalid-value", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "a=infoframe DIT must be '100100' (HDMI Data-Item-Type code)",
  spec_ref         = "TR-10-10 §8",
  verified         = true,
})

M.register("tr-10-10.a.infoframe.port-must-match-media-plus-3", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "a=infoframe port must equal some media block's UDP port + 3",
  spec_ref         = "TR-10-10 §8",
  verified         = true,
})

M.register("tr-10-10.a.infoframe.duplicate-port", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "a=infoframe port must be unique across session-level a=infoframe lines",
  spec_ref         = "TR-10-10 §8",
  verified         = true,
})

-- TR-10-5 §10 a=hkep attribute (HDCP key exchange protocol).
-- Format: `a=hkep:<port> <nettype> <addrtype> <unicast-address>
--                 <node-id> <port-id>`
-- SHALLs validated when the attribute is present:
--   (a) nettype = "IN"
--   (b) addrtype ∈ {"IP4", "IP6"}
--   (c) node-id form: 32 hex digits in xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
--   (d) port-id form: 10 hex digits in xx-xx-xx-xx-xx (5 hex pairs)
-- The <unicast-address> field is captured but not format-validated per
-- TR-10-5 §10 (it constrains presence, not syntax). Port is captured as
-- a number without range-bounding (consistent with base's m= port
-- handling — port-range narrowing is uniformly out of scope at the
-- grammar tier today).

M.register("tr-10-5.a.hkep.nettype-invalid-value", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "a=hkep nettype must be 'IN'",
  spec_ref         = "TR-10-5 §10",
  verified         = true,
})

M.register("tr-10-5.a.hkep.addrtype-invalid-value", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template = "a=hkep addrtype must be 'IP4' or 'IP6'",
  spec_ref         = "TR-10-5 §10",
  verified         = true,
})

M.register("tr-10-5.a.hkep.node-id-invalid-form", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "a=hkep node-id must be 32 hex digits formatted as"
    .. " xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx",
  spec_ref         = "TR-10-5 §10",
  verified         = true,
})

M.register("tr-10-5.a.hkep.port-id-invalid-form", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "a=hkep port-id must be 10 hex digits formatted as xx-xx-xx-xx-xx",
  spec_ref         = "TR-10-5 §10",
  verified         = true,
})

-- TR-10-6 §7.6 FEC parameter signaling (in a=fmtp). The audit (rows 147
-- + 151) extracts three normative constraints:
--   (1) FECPROFILE value MUST be "profile-a" when present.
--   (2) FEC_ADD_LATENCY_VIDEO / FEC_ADD_LATENCY_AUDIO are optional
--       parameters with non-negative integer values (microseconds);
--       presence of either implies a companion FEC stream is signaled,
--       which in turn requires FECPROFILE.
-- FECPROFILE itself is not unconditionally required by §7.6 — only by
-- transitive context (presence of latency parameters). Per-encoding,
-- presence-of-fmtp checks land in earlier IDs.

M.register("tr-10-6.a.fmtp.fecprofile-invalid-value", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "fmtp 'FECPROFILE' must be 'profile-a'"
    .. " (the only IPMX FEC profile currently defined)",
  spec_ref         = "TR-10-6 §7.6",
  verified         = true,
})

M.register("tr-10-6.a.fmtp.fec-add-latency-video-invalid-value", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "fmtp 'FEC_ADD_LATENCY_VIDEO' must be a non-negative integer (microseconds)",
  spec_ref         = "TR-10-6 §7.6",
  verified         = true,
})

M.register("tr-10-6.a.fmtp.fec-add-latency-audio-invalid-value", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "fmtp 'FEC_ADD_LATENCY_AUDIO' must be a non-negative integer (microseconds)",
  spec_ref         = "TR-10-6 §7.6",
  verified         = true,
})

M.register("tr-10-6.a.fmtp.fec-add-latency-video-requires-fecprofile", {
  kind             = "semantic",
  default_severity = "error",
  code             = "MISSING_FIELD",
  message_template =
    "fmtp 'FEC_ADD_LATENCY_VIDEO' requires 'FECPROFILE' on the same fmtp line",
  spec_ref         = "TR-10-6 §7.6",
  verified         = true,
})

M.register("tr-10-6.a.fmtp.fec-add-latency-audio-requires-fecprofile", {
  kind             = "semantic",
  default_severity = "error",
  code             = "MISSING_FIELD",
  message_template =
    "fmtp 'FEC_ADD_LATENCY_AUDIO' requires 'FECPROFILE' on the same fmtp line",
  spec_ref         = "TR-10-6 §7.6",
  verified         = true,
})

-- TR-10-13 §13 a=privacy attribute (Privacy Encryption Protocol signaling).
-- Format (§13 line 338): "semicolon and an optional space separating the
-- parameters and a CRLF to terminate the attribute line. There shall be
-- no semicolon after the last parameter. ... Octet String represented
-- in hexadecimal notation without spaces."
--
-- Required parameters (§13 line 324):
--   protocol, mode, iv, key_generator, key_version, key_id
--
-- Per-parameter SHALLs:
--   - protocol: §13 line 352 — NULL shall not be used in SDP
--   - mode:     §20.1 line 679 — must be one of 12 enumerated values
--               (NULL falls outside the enum, so the §13 line 362
--                "NULL mode shall not be used in SDP" SHALL is subsumed)
--   - iv:            64-bit Octet String (16 hex chars), §13 line 366
--   - key_generator: 128-bit Octet String (32 hex chars), §13 line 372
--   - key_version:   32-bit Octet String (8 hex chars), §13 line 376
--   - key_id:        64-bit Octet String (16 hex chars), §13 line 386
--
-- a=privacy may appear at session level or media level (§13 line 324).
-- USB-context narrowings (protocol = USB_KV, AAD-only modes) live in
-- TR-10-14 §12 and are handled by a separate Phase 7.L slice.

M.register("tr-10-13.a.privacy.protocol-required", {
  kind             = "semantic", default_severity = "error",
  code = "MISSING_FIELD",
  message_template = "a=privacy must include the 'protocol' parameter",
  spec_ref = "TR-10-13 §13", verified = true,
})
M.register("tr-10-13.a.privacy.mode-required", {
  kind             = "semantic", default_severity = "error",
  code = "MISSING_FIELD",
  message_template = "a=privacy must include the 'mode' parameter",
  spec_ref = "TR-10-13 §13", verified = true,
})
M.register("tr-10-13.a.privacy.iv-required", {
  kind             = "semantic", default_severity = "error",
  code = "MISSING_FIELD",
  message_template = "a=privacy must include the 'iv' parameter",
  spec_ref = "TR-10-13 §13", verified = true,
})
M.register("tr-10-13.a.privacy.key_generator-required", {
  kind             = "semantic", default_severity = "error",
  code = "MISSING_FIELD",
  message_template = "a=privacy must include the 'key_generator' parameter",
  spec_ref = "TR-10-13 §13", verified = true,
})
M.register("tr-10-13.a.privacy.key_version-required", {
  kind             = "semantic", default_severity = "error",
  code = "MISSING_FIELD",
  message_template = "a=privacy must include the 'key_version' parameter",
  spec_ref = "TR-10-13 §13", verified = true,
})
M.register("tr-10-13.a.privacy.key_id-required", {
  kind             = "semantic", default_severity = "error",
  code = "MISSING_FIELD",
  message_template = "a=privacy must include the 'key_id' parameter",
  spec_ref = "TR-10-13 §13", verified = true,
})

M.register("tr-10-13.a.privacy.trailing-semicolon", {
  kind             = "semantic", default_severity = "error",
  code = "INVALID_VALUE",
  message_template =
    "a=privacy must not end with a semicolon (no separator after the last parameter)",
  spec_ref = "TR-10-13 §13", verified = true,
})

M.register("tr-10-13.a.privacy.protocol-null-forbidden", {
  kind             = "semantic", default_severity = "error",
  code = "INVALID_VALUE",
  message_template =
    "a=privacy 'protocol' value 'NULL' is forbidden in an SDP transport file"
    .. " (omit the a=privacy attribute instead)",
  spec_ref = "TR-10-13 §13", verified = true,
})

M.register("tr-10-13.a.privacy.mode-invalid-value", {
  kind             = "semantic", default_severity = "error",
  code = "INVALID_VALUE",
  message_template =
    "a=privacy 'mode' must be one of the 12 enumerated values (AES-128-CTR,"
    .. " AES-256-CTR, ...CMAC-64, ...CMAC-64-AAD, and the six ECDH_ variants);"
    .. " NULL is forbidden in an SDP transport file",
  spec_ref = "TR-10-13 §20.1 (per §13 'NULL mode shall not be used')",
  verified = true,
})

M.register("tr-10-13.a.privacy.iv-invalid-form", {
  kind             = "semantic", default_severity = "error",
  code = "INVALID_VALUE",
  message_template =
    "a=privacy 'iv' must be a 64-bit Octet String (16 hex digits, no spaces)",
  spec_ref = "TR-10-13 §13", verified = true,
})
M.register("tr-10-13.a.privacy.key_generator-invalid-form", {
  kind             = "semantic", default_severity = "error",
  code = "INVALID_VALUE",
  message_template =
    "a=privacy 'key_generator' must be a 128-bit Octet String (32 hex digits, no spaces)",
  spec_ref = "TR-10-13 §13", verified = true,
})
M.register("tr-10-13.a.privacy.key_version-invalid-form", {
  kind             = "semantic", default_severity = "error",
  code = "INVALID_VALUE",
  message_template =
    "a=privacy 'key_version' must be a 32-bit Octet String (8 hex digits, no spaces)",
  spec_ref = "TR-10-13 §13", verified = true,
})
M.register("tr-10-13.a.privacy.key_id-invalid-form", {
  kind             = "semantic", default_severity = "error",
  code = "INVALID_VALUE",
  message_template =
    "a=privacy 'key_id' must be a 64-bit Octet String (16 hex digits, no spaces)",
  spec_ref = "TR-10-13 §13", verified = true,
})

-- TR-10-13 §20.1 (line 751): "The a=extmap attribute shall be used to
-- declare the RTP Extension Headers in the SDP transport file using
-- 'sendonly' as the direction parameter." Applies when the extmap URI
-- is one of the PEP IV-Counter URNs (§20.1 line 747). The check only
-- fires when an a=extmap with a PEP URI is present; missing direction
-- and any non-sendonly value both trigger this finding.

M.register("tr-10-13.a.extmap.pep-direction-must-be-sendonly", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "a=extmap for a PEP IV-Counter URN must declare 'sendonly' as its direction",
  spec_ref         = "TR-10-13 §20.1",
  verified         = true,
})

-- TR-10-14 §14 USB block constraints (m=application TCP usb):
-- §14 line 724: "The SDP shall follow RFC 4145 with the following
-- restrictions." RFC 4145 §3 makes a=setup mandatory on TCP-based
-- media streams; TR-10-14 §14 line 740 then narrows the value to
-- "passive". When a=privacy is on a USB block, TR-10-14 §14 line 736
-- requires protocol = USB_KV.

M.register("tr-10-14.usb.setup-required", {
  kind             = "semantic",
  default_severity = "error",
  code             = "MISSING_FIELD",
  message_template =
    "USB transport block (m=application TCP usb) must include a=setup"
    .. " (RFC 4145 §3 'Endpoints MUST include the setup attribute')",
  spec_ref         = "TR-10-14 §14 (per RFC 4145 §3)",
  verified         = true,
})

M.register("tr-10-14.usb.setup-must-be-passive", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "a=setup on a USB transport block must be 'passive'",
  spec_ref         = "TR-10-14 §14",
  verified         = true,
})

M.register("tr-10-14.a.privacy.usb-protocol-must-be-usb_kv", {
  kind             = "semantic",
  default_severity = "error",
  code             = "INVALID_VALUE",
  message_template =
    "a=privacy on a USB transport block must declare 'protocol=USB_KV'",
  spec_ref         = "TR-10-14 §14",
  verified         = true,
})

return M
