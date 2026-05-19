-- parse_sdp.grammar.st2110 — SMPTE ST 2110 tier grammar.
--
-- Composed via `base.extend(base, overrides)`. ST 2110 narrowings are
-- expressed as overrides of base leaf rules — the value-set restrictions
-- live IN the grammar, not as a post-parse Lua walk over the captured doc.
--
-- Phase 6.A — composition shell.
-- Phase 6.B — per-encoding rtpmap narrowings (this commit).
-- Phase 6.C — fmtp parameter narrowings.
-- Phase 6.D — required-attribute presence (ts-refclk, mediaclk, ptime).
-- Phase 6.E — cross-stream invariants (RFC 7104 group:DUP, RFC 2022-7).
--
-- Internal entry point only. The public `sdp.parse(text, "st2110")` continues
-- to use the 1.0 validator chain until Phase 9 (REFACTOR-PLAN.md §5).

local lpeg   = require("lpeg")
local base   = require("parse_sdp.grammar.base")
local errors = require("parse_sdp.errors")

local P, V, C, Cc, Cg, Cb, Ct, Cmt, Carg =
  lpeg.P, lpeg.V, lpeg.C, lpeg.Cc, lpeg.Cg, lpeg.Cb, lpeg.Ct, lpeg.Cmt, lpeg.Carg

local SP = P(" ")

-- ── Semantic checks ────────────────────────────────────────────────────────
-- Cross-section invariants the grammar alone can't express. Each check
-- inspects the captured doc and emits findings via errors.record. Functions
-- are appended to base.semantic_checks via the overrides table below.

-- ST 2110-20:2022 §7.2 (required parameters for raw video fmtp) +
-- ST 2110-21:2022 §8.1 (required TP for every raw video stream). Listed in
-- spec order so that on fail_on_first=true the first absent key emitted
-- matches the order a reader sees in §7.2.
local RAW_VIDEO_REQUIRED_PARAMS = {
  "sampling", "width", "height", "exactframerate", "depth",
  "colorimetry", "PM", "SSN", "TP",
}

-- Shared helper: returns a list of {media_index, payload_type, params} tuples,
-- one per rtpmap PT whose encoding matches `encoding_name` in the document.
-- `params` is the fmtp params table for the matching PT or {} when no fmtp
-- is present. Used by every encoding-scoped semantic check (raw / jxsv /
-- smpte291 / AM824) so the doc walk stays in one place.
local function each_fmtp_for_encoding(doc, encoding_name)
  local out = {}
  for i, m in ipairs(doc.media) do
    local matching_pts = {}
    for _, attr in ipairs(m.attributes) do
      if attr.name == "rtpmap" and attr.encoding == encoding_name then
        matching_pts[attr.payload_type] = true
      end
    end
    local fmtp_by_pt = {}
    for _, attr in ipairs(m.attributes) do
      if attr.name == "fmtp" then
        fmtp_by_pt[attr.payload_type] = attr
      end
    end
    for pt in pairs(matching_pts) do
      local fmtp = fmtp_by_pt[pt]
      out[#out + 1] = {
        media_index = i,
        payload_type = pt,
        params = (fmtp and fmtp.params) or {},
      }
    end
  end
  return out
end

-- Thin wrapper for raw video scope. Kept for readability at the call sites
-- of the -20 checks (each_raw_video_fmtp(doc) reads as cleanly as the
-- explicit-encoding form, and the call sites pre-date the refactor).
local function each_raw_video_fmtp(doc)
  return each_fmtp_for_encoding(doc, "raw")
end

-- Walks every media block, finds payload types whose a=rtpmap encoding is
-- `raw`, locates the matching a=fmtp on that PT, and verifies every required
-- parameter is present. If no fmtp exists for a raw PT, the first required
-- key (sampling) is reported missing — the §7.2 SHALL on the parameter
-- itself is also a SHALL on the fmtp's existence.
local function check_raw_video_fmtp_required(doc, ctx)
  for _, e in ipairs(each_raw_video_fmtp(doc)) do
    for _, key in ipairs(RAW_VIDEO_REQUIRED_PARAMS) do
      if e.params[key] == nil then
        local cont = errors.record(
          ctx,
          "st2110-20.a.fmtp." .. key .. "-required",
          { field_path = string.format(
              "media[%d].attributes[fmtp:pt=%d]",
              e.media_index, e.payload_type) })
        if not cont then return false end
      end
    end
  end
  return true
end

-- ST 2110-20:2022 / ST 2110-21:2022 — enum value sets for raw video fmtp
-- parameters. Each table maps the literal string value to true. Lifted
-- verbatim from the 1.0 parser's VALID_* constants (parse_sdp.lua:769–791,
-- :1073, :1146) so the grammar tier accepts the same set of values.
local RAW_VIDEO_ENUM_VALUES = {
  sampling = {
    ["YCbCr-4:4:4"]   = true, ["YCbCr-4:2:2"]   = true, ["YCbCr-4:2:0"]   = true,
    ["CLYCbCr-4:4:4"] = true, ["CLYCbCr-4:2:2"] = true, ["CLYCbCr-4:2:0"] = true,
    ["ICtCp-4:4:4"]   = true, ["ICtCp-4:2:2"]   = true, ["ICtCp-4:2:0"]   = true,
    ["RGB"]           = true, ["XYZ"]           = true, ["KEY"]           = true,
  },
  depth = {
    ["8"]  = true, ["10"] = true, ["12"] = true,
    ["16"] = true, ["16f"] = true,
  },
  -- §7.5: BT601, BT709, BT2020, BT2100, ST2065-1, ST2065-3, UNSPECIFIED,
  -- XYZ (§7.5), ALPHA (KEY-essence companion per §7.5).
  colorimetry = {
    ["BT601"]    = true, ["BT709"]    = true, ["BT2020"]      = true,
    ["BT2100"]   = true, ["ST2065-1"] = true, ["ST2065-3"]    = true,
    ["XYZ"]      = true, ["ALPHA"]    = true, ["UNSPECIFIED"] = true,
  },
  PM = { ["2110GPM"] = true, ["2110BPM"] = true },
  TP = { ["2110TPN"] = true, ["2110TPNL"] = true, ["2110TPW"] = true },
  -- §7.6: 11 permitted TCS values; ST2115LOGS3 added in the 2022 revision.
  TCS = {
    ["SDR"]         = true, ["PQ"]         = true, ["HLG"]      = true,
    ["LINEAR"]      = true, ["BT2100LINPQ"] = true, ["BT2100LINHLG"] = true,
    ["ST2065-1"]    = true, ["ST428-1"]    = true, ["DENSITY"]  = true,
    ["ST2115LOGS3"] = true, ["UNSPECIFIED"] = true,
  },
  RANGE = { ["NARROW"] = true, ["FULLPROTECT"] = true, ["FULL"] = true },
}

-- Enum keys validated by check_raw_video_fmtp_values. Order is stable for
-- fail_on_first=true determinism: each fmtp's keys are checked in this order
-- so the first finding is predictable across runs.
local RAW_VIDEO_ENUM_KEYS = {
  "sampling", "depth", "colorimetry", "PM", "TP", "TCS", "RANGE",
}

-- Non-enum value-form validators (Phase 6.C.D.2). Each takes the raw string
-- value as captured by the fmtp grammar and returns true when the value
-- satisfies the ST 2110-20 form rule, false otherwise. Order matches the
-- _KEYS list for stable fail_on_first behaviour.

local function gcd(a, b)
  while b ~= 0 do a, b = b, a % b end
  return a
end

-- §7.2: width / height "Permitted values are integers between 1 and 32767
-- inclusive." Same form for both — single builder, two keys.
local function make_pixel_dim_validator()
  return function(v)
    if not v:match("^%d+$") then return false end
    local n = tonumber(v)
    return n ~= nil and n >= 1 and n <= 32767
  end
end

-- §7.2: "non-integer rates shall be signaled as a ratio of two integer
-- decimal numbers separated by a 'forward-slash' character (e.g. 30000/1001),
-- utilizing the numerically smallest numerator value possible." Lowest-terms
-- requirement → gcd(n, d) == 1. Integer form: positive non-zero decimal.
local function validate_exactframerate(v)
  -- N/D fraction form.
  local n_str, d_str = v:match("^(%d+)/(%d+)$")
  if n_str then
    local n, d = tonumber(n_str), tonumber(d_str)
    if not n or not d or n == 0 or d == 0 then return false end
    return gcd(n, d) == 1
  end
  -- Integer form.
  if not v:match("^%d+$") then return false end
  local n = tonumber(v)
  return n ~= nil and n > 0
end

-- §7.3 + §6.4: positive integer no greater than the Extended UDP Size Limit
-- of 8960 octets.
local function validate_maxudp(v)
  if not v:match("^%d+$") then return false end
  local n = tonumber(v)
  return n ~= nil and n >= 1 and n <= 8960
end

-- §7.3: W:H, both positive integers, in lowest terms.
local function validate_par(v)
  local w_str, h_str = v:match("^(%d+):(%d+)$")
  if not w_str then return false end
  local w, h = tonumber(w_str), tonumber(h_str)
  if not w or not h or w == 0 or h == 0 then return false end
  return gcd(w, h) == 1
end

-- §7.2: SSN identifies the spec revision; defined values are ST2110-20:2017
-- and ST2110-20:2022. Other year tokens are not defined.
local function validate_ssn(v)
  return v == "ST2110-20:2017" or v == "ST2110-20:2022"
end

local RAW_VIDEO_VALUE_VALIDATORS = {
  width          = make_pixel_dim_validator(),
  height         = make_pixel_dim_validator(),
  exactframerate = validate_exactframerate,
  MAXUDP         = validate_maxudp,
  PAR            = validate_par,
  SSN            = validate_ssn,
}

local RAW_VIDEO_VALUE_FORM_KEYS = {
  "width", "height", "exactframerate", "MAXUDP", "PAR", "SSN",
}

-- §7.3: `interlace` and `segmented` are bare-attribute flags; signaling
-- either with a `=value` is invalid. The base fmtp grammar captures flags
-- as params[key] == true and kv-pairs as params[key] == string; the check
-- fires when the captured shape is a string.
local RAW_VIDEO_FLAG_ONLY_KEYS = { "interlace", "segmented" }

-- For every raw video fmtp, validate every PRESENT value-typed parameter
-- against its spec rule. Three classes:
--   - enum keys: lookup in RAW_VIDEO_ENUM_VALUES
--   - non-enum value-form keys: predicate in RAW_VIDEO_VALUE_VALIDATORS
--   - flag-only keys: must be `true` (a kv-string value is invalid)
-- Absent parameters are the *-required check's concern. Each violation
-- records the corresponding -invalid-value finding.
local function check_raw_video_fmtp_values(doc, ctx)
  for _, e in ipairs(each_raw_video_fmtp(doc)) do
    local path = string.format(
      "media[%d].attributes[fmtp:pt=%d]", e.media_index, e.payload_type)

    for _, key in ipairs(RAW_VIDEO_ENUM_KEYS) do
      local val = e.params[key]
      if val ~= nil and not RAW_VIDEO_ENUM_VALUES[key][val] then
        local cont = errors.record(ctx,
          "st2110-20.a.fmtp." .. key .. "-invalid-value",
          { field_path = path })
        if not cont then return false end
      end
    end

    for _, key in ipairs(RAW_VIDEO_VALUE_FORM_KEYS) do
      local val = e.params[key]
      if val ~= nil and not RAW_VIDEO_VALUE_VALIDATORS[key](tostring(val)) then
        local cont = errors.record(ctx,
          "st2110-20.a.fmtp." .. key .. "-invalid-value",
          { field_path = path })
        if not cont then return false end
      end
    end

    for _, key in ipairs(RAW_VIDEO_FLAG_ONLY_KEYS) do
      local val = e.params[key]
      if val ~= nil and val ~= true then
        local cont = errors.record(ctx,
          "st2110-20.a.fmtp." .. key .. "-invalid-value",
          { field_path = path })
        if not cont then return false end
      end
    end
  end
  return true
end

-- ── Cross-parameter SHALLs for raw video fmtp (Phase 6.C.E) ──────────────
-- Each helper below evaluates a single cross-parameter constraint on a raw
-- video fmtp's params table. Helpers return true to continue or false to
-- short-circuit the surrounding loop (under fail_on_first=true the first
-- recorded finding fails the match). Ordered to match the 1.0 parser's
-- check order for deterministic fail_on_first behaviour.

-- §7.2 SSN-conditional. Forward direction only — reverse ("SSN=:2022
-- without :2022-only values forbidden") deferred per PLAN.md known items.
local function check_ssn_conditional(params, ctx, path)
  local trigger
  if params.TCS         == "ST2115LOGS3" then trigger = "TCS=ST2115LOGS3" end
  if params.colorimetry == "ALPHA"       then trigger = "colorimetry=ALPHA" end
  if trigger and tostring(params.SSN or "") ~= "ST2110-20:2022" then
    local cont = errors.record(ctx,
      "st2110-20.a.fmtp.ssn-required-for-2022-only-values",
      { field_path = path, context = { trigger = trigger } })
    if not cont then return false end
  end
  return true
end

-- §7.3: BT2100 colorimetry permits only NARROW and FULL — FULLPROTECT
-- forbidden. Per-key RANGE value-set is in 6.C.D.1.
local function check_bt2100_range(params, ctx, path)
  if params.colorimetry == "BT2100" and params.RANGE == "FULLPROTECT" then
    local cont = errors.record(ctx,
      "st2110-20.a.fmtp.bt2100-range-fullprotect-forbidden",
      { field_path = path })
    if not cont then return false end
  end
  return true
end

-- §7.3: segmented requires interlace also present.
local function check_segmented_requires_interlace(params, ctx, path)
  if params.segmented and not params.interlace then
    local cont = errors.record(ctx,
      "st2110-20.a.fmtp.segmented-requires-interlace",
      { field_path = path })
    if not cont then return false end
  end
  return true
end

-- §6.3.3: PM=2110BPM forbids MAXUDP (Block Packing Mode is incompatible
-- with the Extended UDP Size Limit).
local function check_bpm_forbids_maxudp(params, ctx, path)
  if params.PM == "2110BPM" and params.MAXUDP ~= nil then
    local cont = errors.record(ctx,
      "st2110-20.a.fmtp.bpm-with-maxudp-forbidden",
      { field_path = path })
    if not cont then return false end
  end
  return true
end

-- §7.4.1: sampling=KEY requires colorimetry=ALPHA AND forbids TCS.
-- Two separate registered IDs so an audit can target either independently.
local function check_key_sampling(params, ctx, path)
  if params.sampling == "KEY" then
    if params.colorimetry ~= "ALPHA" then
      local cont = errors.record(ctx,
        "st2110-20.a.fmtp.key-requires-alpha-colorimetry",
        { field_path = path })
      if not cont then return false end
    end
    if params.TCS ~= nil then
      local cont = errors.record(ctx,
        "st2110-20.a.fmtp.key-forbids-tcs",
        { field_path = path })
      if not cont then return false end
    end
  end
  return true
end

-- §6.2.5: 4:2:0 sampling applies to progressive scan only — must not be
-- combined with the interlace flag. Detected via the `-4:2:0` suffix on
-- any sampling token (YCbCr-4:2:0 / CLYCbCr-4:2:0 / ICtCp-4:2:0).
local function check_420_progressive_only(params, ctx, path)
  local s = params.sampling
  if s and type(s) == "string" and s:match("^[%w]+%-4:2:0$") then
    if params.interlace then
      local cont = errors.record(ctx,
        "st2110-20.a.fmtp.subsampling-420-with-interlace-forbidden",
        { field_path = path })
      if not cont then return false end
    end
  end
  return true
end

-- §6.2.5 Table 3 (Phase 6.C.F): the 4:2:0 pgroup construction table lists
-- 4:2:0 sampling tokens with depths {8, 10, 12} only. depth ∈ {16, 16f}
-- is outside the defined value combination → reject. Detected the same
-- way as check_420_progressive_only via the `-4:2:0` suffix.
local RAW_420_FORBIDDEN_DEPTHS = { ["16"] = true, ["16f"] = true }

local function check_420_depth_restricted(params, ctx, path)
  local s = params.sampling
  if s and type(s) == "string" and s:match("^[%w]+%-4:2:0$") then
    if params.depth and RAW_420_FORBIDDEN_DEPTHS[tostring(params.depth)] then
      local cont = errors.record(ctx,
        "st2110-20.a.fmtp.subsampling-420-depth-restricted",
        { field_path = path,
          context    = { sampling = s, depth = params.depth } })
      if not cont then return false end
    end
  end
  return true
end

-- §7.6 TCS table (Phase 6.C.F): four "floating-point linear" TCS values
-- are defined with `(depth=16f)` parenthetical. When the TCS is one of
-- these, depth must be 16f. Per-TCS error IDs so each value-row is
-- independently grep-able (matches inventory rows 115-118 one-for-one).
local TCS_REQUIRES_16F = {
  ["LINEAR"]       = "st2110-20.a.fmtp.tcs-linear-requires-depth-16f",
  ["BT2100LINPQ"]  = "st2110-20.a.fmtp.tcs-bt2100linpq-requires-depth-16f",
  ["BT2100LINHLG"] = "st2110-20.a.fmtp.tcs-bt2100linhlg-requires-depth-16f",
  ["ST2065-1"]     = "st2110-20.a.fmtp.tcs-st2065-1-requires-depth-16f",
}

local function check_tcs_floating_point_depth(params, ctx, path)
  local err_id = TCS_REQUIRES_16F[params.TCS]
  if err_id and tostring(params.depth or "") ~= "16f" then
    local cont = errors.record(ctx, err_id,
      { field_path = path,
        context    = { TCS = params.TCS, depth = params.depth } })
    if not cont then return false end
  end
  return true
end

-- Tier-level driver: walks every raw video fmtp and runs each cross-param
-- helper in turn. Order matches 1.0's check sequence (with 6.C.F additions
-- appended at the end) so fail_on_first behaviour is stable across tiers.
local RAW_VIDEO_CROSS_PARAM_CHECKS = {
  check_ssn_conditional,
  check_bt2100_range,
  check_segmented_requires_interlace,
  check_bpm_forbids_maxudp,
  check_key_sampling,
  check_420_progressive_only,
  check_420_depth_restricted,           -- 6.C.F
  check_tcs_floating_point_depth,       -- 6.C.F
}

local function check_raw_video_fmtp_cross_param(doc, ctx)
  for _, e in ipairs(each_raw_video_fmtp(doc)) do
    local path = string.format(
      "media[%d].attributes[fmtp:pt=%d]", e.media_index, e.payload_type)
    for _, fn in ipairs(RAW_VIDEO_CROSS_PARAM_CHECKS) do
      if not fn(e.params, ctx, path) then return false end
    end
  end
  return true
end

-- ── ST 2110-22 jxsv fmtp narrowings (Phase 6.C.G.1) ────────────────────────
-- ST 2110-22:2022 §7.2 Table 1 plus RFC 9134 §7.1 (IANA video/jxsv media-
-- type registration) define the jxsv fmtp parameter set: 3 required from
-- ST 2110-22 (width, height, TP), 1 required from RFC 9134 (packetmode),
-- plus 12 optional value-form parameters and 2 bare-flag parameters.
--
-- Value-set divergence from 1.0 parser:
--   * `colorimetry`: RFC 9134 lists {BT601-5, BT709-2, SMPTE240M, BT601,
--     BT709, BT2020, BT2100, ST2065-1, ST2065-3, XYZ, UNSPECIFIED}.
--     1.0 reuses ST 2110-20's set (includes ALPHA, omits the 3 legacy
--     values). The grammar tier follows RFC 9134 — primary spec text.
--   * `TCS`: RFC 9134 lists {SDR, PQ, HLG, UNSPECIFIED} only. 1.0 reuses
--     ST 2110-20's 11-value set. Grammar tier follows RFC 9134.
--   * `sampling`: RFC 9134 adds `UNSPECIFIED` to the -20 set. Grammar
--     tier includes it.

local JXSV_ENUM_VALUES = {
  -- RFC 9134 §7.1 — same family as -20 sampling plus UNSPECIFIED.
  sampling = {
    ["YCbCr-4:4:4"]   = true, ["YCbCr-4:2:2"]   = true, ["YCbCr-4:2:0"]   = true,
    ["CLYCbCr-4:4:4"] = true, ["CLYCbCr-4:2:2"] = true, ["CLYCbCr-4:2:0"] = true,
    ["ICtCp-4:4:4"]   = true, ["ICtCp-4:2:2"]   = true, ["ICtCp-4:2:0"]   = true,
    ["RGB"]           = true, ["XYZ"]           = true, ["KEY"]           = true,
    ["UNSPECIFIED"]   = true,
  },
  -- RFC 9134 §7.1 — colorimetry: 11 values; legacy `*-5/-2`/SMPTE240M
  -- forms are explicitly permitted alongside the modern names.
  colorimetry = {
    ["BT601-5"]   = true, ["BT709-2"]    = true, ["SMPTE240M"]   = true,
    ["BT601"]     = true, ["BT709"]      = true, ["BT2020"]      = true,
    ["BT2100"]    = true, ["ST2065-1"]   = true, ["ST2065-3"]    = true,
    ["XYZ"]       = true, ["UNSPECIFIED"] = true,
  },
  -- RFC 9134 §7.1 — TCS: 4 values only (much narrower than -20).
  TCS = {
    ["SDR"] = true, ["PQ"] = true, ["HLG"] = true, ["UNSPECIFIED"] = true,
  },
  -- RFC 9134 §7.1 — RANGE: 3 values. BT2100 narrowing is cross-param
  -- (Phase 6.C.G.2), not a member-of-set check.
  RANGE = { ["NARROW"] = true, ["FULLPROTECT"] = true, ["FULL"] = true },
  -- ST 2110-22:2022 §5.3 — same TP set as -21 §8.1.
  TP = { ["2110TPN"] = true, ["2110TPNL"] = true, ["2110TPW"] = true },
  -- RFC 9134 §7.1 — transmode T-bit, packetmode K-bit ∈ {0, 1}.
  transmode  = { ["0"] = true, ["1"] = true },
  packetmode = { ["0"] = true, ["1"] = true },
  -- RFC 9134 §7.1 — profile/level/sublevel reference ISO 21122-2.
  -- 1.0 parser hard-codes the JPEG-XS Part 2 enums; preserved here so
  -- the grammar tier doesn't regress past 1.0.
  profile = {
    ["Unrestricted"]       = true,
    ["Light422.10"]        = true,
    ["Light444.12"]        = true,
    ["LightSubline422.10"] = true,
    ["LightSubline444.12"] = true,
    ["Main422.10"]         = true,
    ["Main444.12"]         = true,
    ["High444.12"]         = true,
    ["MLS.12"]             = true,
    ["LightBayer"]         = true,
    ["MainBayer"]          = true,
    ["HighBayer"]          = true,
    ["MLSBayer"]           = true,
  },
  level = {
    ["Unrestricted"] = true,
    ["1k-1"]   = true,
    ["2k-1"]   = true,
    ["4k-1"]   = true, ["4k-2"]   = true, ["4k-3"]   = true,
    ["8k-1"]   = true, ["8k-2"]   = true, ["8k-3"]   = true,
    ["16k-1"]  = true, ["16k-2"]  = true, ["16k-3"]  = true,
  },
  sublevel = {
    ["Unrestricted"] = true,
    ["Full"]         = true,
    ["Sublev12bpp"]  = true,
    ["Sublev9bpp"]   = true,
    ["Sublev6bpp"]   = true,
    ["Sublev4bpp"]   = true,
    ["Sublev3bpp"]   = true,
    ["Sublev2bpp"]   = true,
  },
}

local JXSV_ENUM_KEYS = {
  "TP", "packetmode", "sampling", "TCS", "colorimetry", "RANGE",
  "transmode", "profile", "level", "sublevel",
}

-- Non-enum value-form validators. width/height/exactframerate/MAXUDP reuse
-- the -20 implementations (same form per RFC 9134 §7.1). depth is open
-- positive integer (RFC 9134 §7.1: "typical values 8, 10, 12, 16" —
-- non-closed). CMAX is any integer per ST 2110-21:2022 §8.2. SSN takes
-- ST2110-22:2019 or ST2110-22:2022 per ST 2110-22:2022 §7.2 Table 2.

local function validate_positive_integer(v)
  if not v:match("^%d+$") then return false end
  local n = tonumber(v)
  return n ~= nil and n > 0
end

local function validate_integer(v)
  if not v:match("^%-?%d+$") then return false end
  return tonumber(v) ~= nil
end

local function validate_ssn22(v)
  return v == "ST2110-22:2019" or v == "ST2110-22:2022"
end

local JXSV_VALUE_VALIDATORS = {
  width          = make_pixel_dim_validator(),
  height         = make_pixel_dim_validator(),
  exactframerate = validate_exactframerate,
  depth          = validate_positive_integer,
  MAXUDP         = validate_maxudp,
  CMAX           = validate_integer,
  SSN            = validate_ssn22,
}

local JXSV_VALUE_FORM_KEYS = {
  "width", "height", "exactframerate", "depth", "MAXUDP", "CMAX", "SSN",
}

local JXSV_FLAG_ONLY_KEYS = { "interlace", "segmented" }

-- RFC 9134 §7.1 — required parameters: width, height, TP (from
-- ST 2110-22:2022 §7.2 Table 1) and packetmode (from RFC 9134 §7.1).
local JXSV_REQUIRED_PARAMS = { "width", "height", "TP", "packetmode" }

local function check_jxsv_fmtp_required(doc, ctx)
  for _, e in ipairs(each_fmtp_for_encoding(doc, "jxsv")) do
    for _, key in ipairs(JXSV_REQUIRED_PARAMS) do
      if e.params[key] == nil then
        local cont = errors.record(ctx,
          "st2110-22.a.fmtp." .. key .. "-required",
          { field_path = string.format(
              "media[%d].attributes[fmtp:pt=%d]",
              e.media_index, e.payload_type) })
        if not cont then return false end
      end
    end
  end
  return true
end

-- ── Cross-parameter SHALLs for jxsv fmtp (Phase 6.C.G.2) ─────────────────
-- Two cross-parameter SHALLs in RFC 9134 §7.1, parallel in shape to two
-- of the -20 SHALLs (segmented-requires-interlace; BT2100/RANGE) but
-- with their own normative source.

local function check_jxsv_segmented_requires_interlace(params, ctx, path)
  if params.segmented and not params.interlace then
    local cont = errors.record(ctx,
      "st2110-22.a.fmtp.segmented-requires-interlace",
      { field_path = path })
    if not cont then return false end
  end
  return true
end

local function check_jxsv_bt2100_range(params, ctx, path)
  if params.colorimetry == "BT2100" and params.RANGE == "FULLPROTECT" then
    local cont = errors.record(ctx,
      "st2110-22.a.fmtp.bt2100-range-fullprotect-forbidden",
      { field_path = path })
    if not cont then return false end
  end
  return true
end

local JXSV_CROSS_PARAM_CHECKS = {
  check_jxsv_segmented_requires_interlace,
  check_jxsv_bt2100_range,
}

-- ── ST 2110-30 / -31 audio channel-order syntax (Phase 6.C.H) ─────────────
-- Returns a list of (media_index, payload_type, encoding, params) tuples
-- across every audio rtpmap PT in the document (L16, L24, AM824). Mirrors
-- each_fmtp_for_encoding but multiplexes the three audio encodings into
-- one walk so the channel-order check doesn't run three separate doc walks.
local AUDIO_ENCODINGS = { L16 = true, L24 = true, AM824 = true }

local function each_audio_fmtp(doc)
  local out = {}
  for i, m in ipairs(doc.media) do
    local audio_pts = {}
    for _, attr in ipairs(m.attributes) do
      if attr.name == "rtpmap" and AUDIO_ENCODINGS[attr.encoding] then
        audio_pts[attr.payload_type] = attr.encoding
      end
    end
    local fmtp_by_pt = {}
    for _, attr in ipairs(m.attributes) do
      if attr.name == "fmtp" then
        fmtp_by_pt[attr.payload_type] = attr
      end
    end
    for pt, enc in pairs(audio_pts) do
      local fmtp = fmtp_by_pt[pt]
      out[#out + 1] = {
        media_index  = i,
        payload_type = pt,
        encoding     = enc,
        params       = (fmtp and fmtp.params) or {},
      }
    end
  end
  return out
end

-- ST 2110-30 §6.2.2 Table 1 group symbol set (M, DM, ST, LtRt, 51, 71,
-- 222, SGRP). AES3 is added per ST 2110-31:2022 §6.2 Table 2 — AM824 only.
local AUDIO_CHANNEL_GROUPS = {
  ["M"]    = true, ["DM"]   = true, ["ST"]   = true, ["LtRt"] = true,
  ["51"]   = true, ["71"]   = true, ["222"]  = true, ["SGRP"] = true,
}

-- Validate a single channel-order value against §6.2.2 + RFC 3190. Returns
-- (true, nil) on accept, or (false, err_id) when the value violates a
-- specific SHALL. err_id distinguishes the two normative sources (-30 vs
-- -31) so audit grep can target either.
local function validate_channel_order(value, encoding)
  local convention, order = value:match("^([^.%s]+)%.(%S+)$")
  if not convention or order == "" then
    return false, "st2110-30.a.fmtp.channel-order-invalid"
  end
  if convention ~= "SMPTE2110" then
    -- §6.2.2 only constrains the SMPTE2110 convention. Other tokens are
    -- structurally valid RFC 3190 forms; accept them.
    return true
  end
  local groups_str = order:match("^%((.+)%)$")
  if not groups_str then
    return false, "st2110-30.a.fmtp.channel-order-invalid"
  end
  for grp in groups_str:gmatch("[^,]+") do
    local g = grp:match("^%s*(.-)%s*$")
    if g == "" then
      return false, "st2110-30.a.fmtp.channel-order-invalid"
    elseif AUDIO_CHANNEL_GROUPS[g] then
      -- known §6.2.2 Table 1 symbol — accept
    elseif g == "AES3" then
      if encoding ~= "AM824" then
        return false, "st2110-31.a.fmtp.channel-order-aes3-requires-am824"
      end
    else
      local nn = g:match("^U(%d%d)$")
      local n  = nn and tonumber(nn)
      if not n or n < 1 or n > 64 then
        return false, "st2110-30.a.fmtp.channel-order-invalid"
      end
    end
  end
  return true
end

local function check_audio_fmtp_channel_order(doc, ctx)
  for _, e in ipairs(each_audio_fmtp(doc)) do
    local co = e.params["channel-order"]
    if co ~= nil and co ~= true then
      local ok, err_id = validate_channel_order(tostring(co), e.encoding)
      if not ok then
        local path = string.format(
          "media[%d].attributes[fmtp:pt=%d]",
          e.media_index, e.payload_type)
        local cont = errors.record(ctx, err_id,
          { field_path = path,
            context    = { encoding = e.encoding, value = co } })
        if not cont then return false end
      end
    end
  end
  return true
end

local function check_jxsv_fmtp_cross_param(doc, ctx)
  for _, e in ipairs(each_fmtp_for_encoding(doc, "jxsv")) do
    local path = string.format(
      "media[%d].attributes[fmtp:pt=%d]", e.media_index, e.payload_type)
    for _, fn in ipairs(JXSV_CROSS_PARAM_CHECKS) do
      if not fn(e.params, ctx, path) then return false end
    end
  end
  return true
end

local function check_jxsv_fmtp_values(doc, ctx)
  for _, e in ipairs(each_fmtp_for_encoding(doc, "jxsv")) do
    local path = string.format(
      "media[%d].attributes[fmtp:pt=%d]", e.media_index, e.payload_type)

    for _, key in ipairs(JXSV_ENUM_KEYS) do
      local val = e.params[key]
      if val ~= nil and not JXSV_ENUM_VALUES[key][tostring(val)] then
        local cont = errors.record(ctx,
          "st2110-22.a.fmtp." .. key .. "-invalid-value",
          { field_path = path })
        if not cont then return false end
      end
    end

    for _, key in ipairs(JXSV_VALUE_FORM_KEYS) do
      local val = e.params[key]
      if val ~= nil and not JXSV_VALUE_VALIDATORS[key](tostring(val)) then
        local cont = errors.record(ctx,
          "st2110-22.a.fmtp." .. key .. "-invalid-value",
          { field_path = path })
        if not cont then return false end
      end
    end

    for _, key in ipairs(JXSV_FLAG_ONLY_KEYS) do
      local val = e.params[key]
      if val ~= nil and val ~= true then
        local cont = errors.record(ctx,
          "st2110-22.a.fmtp." .. key .. "-invalid-value",
          { field_path = path })
        if not cont then return false end
      end
    end
  end
  return true
end

-- ── rtpmap encoding narrowings (Phase 6.B) ─────────────────────────────────
--
-- Each known ST 2110 essence encoding has:
--   - a defined m= media type (video for raw / jxsv / smpte291, audio for AM824)
--   - a defined clock-rate set (90000 for the three video encodings; one of
--     {44100, 48000, 96000} for AM824)
--
-- Both narrowings are expressed in-grammar:
--   - encoding-name literal: the branch matches only when the encoding token
--     is exactly the recognised name AND is followed by `/`, so a name like
--     "rawX" still falls through to the default branch.
--   - clock-rate value set: an inline Cmt validates the captured number and
--     records a finding when it falls outside the allowed set.
--   - media-type: a trailing Cmt reads the surrounding `media` capture via
--     `Cb"media"` and records a finding when it doesn't match the encoding's
--     defined media type.
--
-- The branches are gated by a negative lookahead on the default branch so a
-- malformed known-encoding rtpmap (e.g. raw/48000) fails the whole a_rtpmap
-- match rather than backtracking into the generic-encoding form.
--
-- Cb"media" reads the most recent complete group capture named "media" — the
-- one m_value emits inside every media_section Ct. Session-level a=rtpmap is
-- non-conformant per RFC 8866 §6.6 (rtpmap is media-only) and the surrounding
-- grammar never establishes a session-level "media" capture; ST 2110 inherits
-- that scope rule from base.

local function record_rate_and_media(rate_check_id, expected_media, media_check_id)
  return function(_, pos, rate, media, ctx)
    local ok = true
    if rate_check_id and not rate_check_id.set[rate] then
      ok = ok and errors.record(ctx, rate_check_id.id, {})
    end
    if media ~= expected_media then
      ok = ok and errors.record(ctx, media_check_id, {})
    end
    if not ok then return false end
    return pos
  end
end

-- Each rule produces:
--   Cg("encoding")   ← the literal encoding name
--   Cg("clock_rate") ← the parsed number
--   Cg("channels")?  ← optional, when present in the input
-- followed by a trailing Cmt that reads Cb"clock_rate" + Cb"media" + ctx and
-- emits findings via errors.record. The Cmt returns `pos` (no value) so it
-- doesn't add to the surrounding a_value Ct.

local function make_rtpmap_branch(encoding_name, rate_id, expected_media, media_id)
  return P(encoding_name) * Cg(Cc(encoding_name), "encoding") * P("/")
    * Cg(V"rfc8866_pos_int_num", "clock_rate")
    * (P("/") * Cg(V"rfc8866_pos_int_num", "channels")) ^ -1
    * Cmt(Cb"clock_rate" * Cb"media" * Carg(1),
          record_rate_and_media(rate_id, expected_media, media_id))
end

local overrides = {
  rules = {
    -- Override a_rtpmap with branched form: each known-encoding branch
    -- enforces its value-set/clock-rate/media-type SHALLs in-line; an
    -- unknown encoding falls through to the default branch and is captured
    -- with base's permissive shape (silence is not rejection — CLAUDE.md
    -- strictness principle).
    --
    -- Trailing Cmt records ctx.rtpmap_encodings[pt] = encoding so a later
    -- a=fmtp on the same media block can look the encoding up by PT. Each
    -- a= line is wrapped in its own a_value Ct, so a Cb"encoding" from one
    -- line is no longer in scope by the time the next line parses — ctx is
    -- the cross-line carrier.
    a_rtpmap = P("rtpmap:")
        * Cg(Cc("rtpmap"), "name")
        * Cg(V"payload_type", "payload_type") * SP
        * ( V"st2110_rtpmap_raw"
          + V"st2110_rtpmap_jxsv"
          + V"st2110_rtpmap_smpte291"
          + V"st2110_rtpmap_am824"
          + V"st2110_rtpmap_default" )
        * Cmt(Cb"payload_type" * Cb"encoding" * Carg(1),
              function(_, pos, pt, enc, ctx)
                if ctx then
                  ctx.rtpmap_encodings = ctx.rtpmap_encodings or {}
                  ctx.rtpmap_encodings[pt] = enc
                end
                return pos
              end),

    st2110_rtpmap_raw = make_rtpmap_branch(
      "raw",
      { id = "st2110-20.a.rtpmap.raw-clock-rate", set = { [90000] = true } },
      "video", "st2110-20.a.rtpmap.raw-media-type"),

    st2110_rtpmap_jxsv = make_rtpmap_branch(
      "jxsv",
      { id = "st2110-22.a.rtpmap.jxsv-clock-rate", set = { [90000] = true } },
      "video", "st2110-22.a.rtpmap.jxsv-media-type"),

    st2110_rtpmap_smpte291 = make_rtpmap_branch(
      "smpte291",
      { id = "st2110-40.a.rtpmap.smpte291-clock-rate", set = { [90000] = true } },
      "video", "st2110-40.a.rtpmap.smpte291-media-type"),

    st2110_rtpmap_am824 = make_rtpmap_branch(
      "AM824",
      { id = "st2110-31.a.rtpmap.am824-clock-rate-set",
        set = { [44100] = true, [48000] = true, [96000] = true } },
      "audio", "st2110-31.a.rtpmap.am824-media-type"),

    -- Default branch: any encoding token NOT a known ST 2110 essence
    -- followed by `/`. The negative lookahead prevents a malformed
    -- known-encoding rtpmap (e.g. raw/48000) from falling through here —
    -- if the input starts with a known encoding name + `/`, the lookahead
    -- fails the default branch and the corresponding known-encoding branch
    -- is the only one that can claim the match.
    st2110_rtpmap_default =
        -V"st2110_known_rtpmap_encoding"
        * Cg(V"rfc8866_token", "encoding") * P("/")
        * Cg(V"rfc8866_pos_int_num", "clock_rate")
        * (P("/") * Cg(V"rfc8866_pos_int_num", "channels")) ^ -1,

    st2110_known_rtpmap_encoding =
        (P("raw") + P("jxsv") + P("smpte291") + P("AM824")) * P("/"),

    -- ── fmtp parameter-form narrowings (Phase 6.C.B) ─────────────────────
    -- ST 2110-20:2022 §7.1: "Each media type parameter entry shall be
    -- constructed as either a <name>=<value> pair, with no whitespace
    -- within the name or value or between the name, equal sign, and
    -- value; a <name> standalone declaration, with no whitespace within
    -- the name." Scope: only when the surrounding rtpmap encoding is
    -- `raw`. Other ST 2110 essence specs (-22, -30, -31, -40) do not
    -- carry this prohibition; they keep base's loose form.
    --
    -- Encoding-gated alternation: the first branch matches only when this
    -- fmtp's payload_type was previously recorded (via a_rtpmap's trailing
    -- Cmt) as carrying encoding="raw" AND the input has no whitespace
    -- around `=`; the second branch matches when the recorded encoding is
    -- anything else (including absent — static PT with no rtpmap) and uses
    -- base's loose `fmtp_params_branch`. A `raw` fmtp with whitespace fails
    -- both branches → a_fmtp fails → match returns nil with the finding in
    -- ctx.findings (under fail_on_first=true).
    --
    -- The lookup is ctx-based rather than Cb-based because the rtpmap and
    -- fmtp lines each close their own a_value Ct, so the rtpmap's encoding
    -- Cg is no longer in scope at fmtp time. ctx.rtpmap_encodings is the
    -- cross-line carrier (populated in a_rtpmap above).
    a_fmtp = P("fmtp:")
        * Cg(Cc("fmtp"), "name")
        * Cg(V"payload_type", "payload_type") * SP
        * ( V"fmtp_st2110_raw_payload"
          + V"fmtp_payload_non_raw" ),

    fmtp_st2110_raw_payload =
        Cmt(Cb"payload_type" * Carg(1), function(_, pos, pt, ctx)
          local enc = ctx and ctx.rtpmap_encodings
                            and ctx.rtpmap_encodings[pt]
          return enc == "raw" and pos
        end)
        * V"fmtp_st2110_raw_params",

    fmtp_payload_non_raw =
        Cmt(Cb"payload_type" * Carg(1), function(_, pos, pt, ctx)
          local enc = ctx and ctx.rtpmap_encodings
                            and ctx.rtpmap_encodings[pt]
          return enc ~= "raw" and pos
        end)
        * ( V"fmtp_params_branch" + V"fmtp_raw_branch" ),

    -- Strict params branch for `raw`: each kv-pair captures the
    -- (key, ws_before_eq, ws_after_eq, value) tuple; a Cmt examines the
    -- whitespace captures, records sdp st2110-20.a.fmtp.no-whitespace-
    -- around-equals when either side is non-empty, and otherwise yields
    -- the {key, value} pair the outer transform expects.
    fmtp_st2110_raw_params =
        Cg(
            Ct(V"fmtp_st2110_raw_entry"
              * (V"fmtp_sep" * V"fmtp_st2110_raw_entry") ^ 0)
              / base.fmtp_entries_to_params,
            "params"
          )
        * V"fmtp_trailing_sep_record" ^ -1
        * #V"line_end_chars",

    fmtp_st2110_raw_entry =
        V"fmtp_st2110_raw_kv_pair" + V"fmtp_flag",

    fmtp_st2110_raw_kv_pair =
        Cmt(
          Ct(
            C(V"fmtp_key_chars" ^ 1)
            * C(V"fmtp_hws" ^ 0)
            * P("=")
            * C(V"fmtp_hws" ^ 0)
            * C(V"fmtp_val_chars" ^ 0)
          ) * Carg(1),
          function(_, pos, captured, ctx)
            local key, ws_l, ws_r, val =
              captured[1], captured[2], captured[3], captured[4]
            if #ws_l > 0 or #ws_r > 0 then
              local cont = errors.record(
                ctx, "st2110-20.a.fmtp.no-whitespace-around-equals", {})
              if not cont then return false end
            end
            return pos, { key, val }
          end),
  },

  semantic_checks = {
    check_raw_video_fmtp_required,
    check_raw_video_fmtp_values,
    check_raw_video_fmtp_cross_param,
    check_jxsv_fmtp_required,
    check_jxsv_fmtp_values,
    check_jxsv_fmtp_cross_param,
    check_audio_fmtp_channel_order,
  },
}

return base.extend(base, overrides)
