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

-- Register a check definition. Validates the definition; errors loudly on
-- malformed input (this is a programmer mistake at module-load time, not a
-- parse-time failure).
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

-- ─── record() — the only way a check site emits a finding ───────────────────

-- ctx: { findings = {}, policy = {?}, fail_on_first = bool }
-- id:  registered check id
-- loc: { line=, col=, context=, field_path= }   (any field may be nil)
-- Returns true to continue matching, false to fail the match (only when the
-- effective severity is "error" and ctx.fail_on_first is true).
function M.record(ctx, id, loc)
  local def = CHECKS[id]
  if not def then error("record() with unknown check id: " .. tostring(id), 2) end
  local sev = (ctx.policy and ctx.policy[id]) or def.default_severity
  if sev == "off" then return true end
  ctx.findings[#ctx.findings + 1] = {
    id         = id,
    severity   = sev,
    message    = def.message_template,
    spec_ref   = def.spec_ref,
    code       = def.code,
    line       = loc and loc.line or 0,
    col        = loc and loc.col  or 0,
    context    = loc and loc.context or "",
    field_path = loc and loc.field_path,
  }
  if sev == "error" and ctx.fail_on_first then return false end
  return true
end

-- ─── Deepest-failure tracker ────────────────────────────────────────────────

-- Carg-passable accumulator that grammar Cmt callbacks write to before
-- returning false. After a failed match, tracker_deepest() reports the
-- position closest to end-of-input — usually the most informative failure.
-- Tie-break: later record wins (most recent failure at that depth).

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

return M
