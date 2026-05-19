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

return M
