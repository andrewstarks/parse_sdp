-- parse_sdp.grammar.st2110 — SMPTE ST 2110 tier grammar.
--
-- Composed via `base.extend(base, overrides)`. ST 2110 narrowings are
-- expressed as overrides of base leaf rules — the value-set restrictions
-- live IN the grammar, not as a post-parse Lua walk over the captured doc.

local lpeg   = require("lpeg")
local base   = require("parse_sdp.grammar.base")
local errors = require("parse_sdp.errors")

local P, R, V, C, Cc, Cg, Cb, Ct, Cmt, Carg =
  lpeg.P, lpeg.R, lpeg.V, lpeg.C, lpeg.Cc, lpeg.Cg, lpeg.Cb, lpeg.Ct, lpeg.Cmt, lpeg.Carg

local patterns = require("parse_sdp.grammar.patterns")

local SP = P(" ")

-- ST 2110-20:2022 §7.2 + ST 2110-21:2022 §8.1 — required raw video fmtp
-- params. Spec order so fail_on_first emits absent keys in §7.2 reading
-- order.
local RAW_VIDEO_REQUIRED_PARAMS = {
  "sampling", "width", "height", "exactframerate", "depth",
  "colorimetry", "PM", "SSN", "TP",
}

-- Raw video fmtp enum value sets per ST 2110-20:2022 / -21:2022.
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

-- Order is the fail_on_first emission order.
local RAW_VIDEO_ENUM_KEYS = {
  "sampling", "depth", "colorimetry", "PM", "TP", "TCS", "RANGE",
}

-- Non-enum value-form validators. Each takes the raw captured string and
-- returns true iff it satisfies the ST 2110-20 form rule.

local function gcd(a, b)
  while b ~= 0 do a, b = b, a % b end
  return a
end

-- §7.2: width / height "Permitted values are integers between 1 and 32767
-- inclusive." `patterns.pos_int` guarantees POS-DIGIT *DIGIT form (no
-- leading zero, ≥ 1); the bound check adds the upper limit.
local function validate_pixel_dim(v)
  if not patterns.pos_int:match(v) then return false end
  return tonumber(v) <= 32767
end

-- §7.2: "non-integer rates shall be signaled as a ratio of two integer
-- decimal numbers separated by a 'forward-slash' character (e.g. 30000/1001),
-- utilizing the numerically smallest numerator value possible." Lowest-terms
-- requirement → gcd(n, d) == 1. Integer form: positive non-zero decimal.
local function validate_exactframerate(v)
  local n_str, d_str = patterns.fraction:match(v)
  if n_str then
    return gcd(tonumber(n_str), tonumber(d_str)) == 1
  end
  -- Integer form (no fraction).
  return patterns.pos_int:match(v) ~= nil
end

-- §7.3 + §6.4: positive integer no greater than the Extended UDP Size Limit
-- of 8960 octets.
local function validate_maxudp(v)
  if not patterns.pos_int:match(v) then return false end
  return tonumber(v) <= 8960
end

-- §7.3: W:H, both positive integers, in lowest terms.
local function validate_par(v)
  local w_str, h_str = patterns.ratio:match(v)
  if not w_str then return false end
  return gcd(tonumber(w_str), tonumber(h_str)) == 1
end

-- §7.2: SSN identifies the spec revision; defined values are ST2110-20:2017
-- and ST2110-20:2022. Other year tokens are not defined.
local function validate_ssn(v)
  return v == "ST2110-20:2017" or v == "ST2110-20:2022"
end

local RAW_VIDEO_VALUE_VALIDATORS = {
  width          = validate_pixel_dim,
  height         = validate_pixel_dim,
  exactframerate = validate_exactframerate,
  MAXUDP         = validate_maxudp,
  PAR            = validate_par,
  SSN            = validate_ssn,
}

local RAW_VIDEO_VALUE_FORM_KEYS = {
  "width", "height", "exactframerate", "MAXUDP", "PAR", "SSN",
}

-- §7.3: `interlace` and `segmented` are bare-attribute flags; a `=value`
-- on either is invalid (base captures flags as `true`, kv-pairs as
-- string, so the check fires on string-valued entries below).
local RAW_VIDEO_FLAG_ONLY_KEYS = { "interlace", "segmented" }

-- Per-fmtp raw-video required-presence + value-form check, one walk per
-- key class. Called both from the in-grammar fmtp dispatch and from
-- FMTP_REQUIRED_BY_ENCODING with empty params (no-fmtp case) — in that
-- case only the required-presence pass fires.
local function check_raw_video_fmtp(params, ctx, pos, field_path)
  for _, key in ipairs(RAW_VIDEO_REQUIRED_PARAMS) do
    if base.params_get(params, key) == nil then
      local cont = errors.record(
        ctx, "st2110-20.a.fmtp." .. key .. "-required",
        { pos = pos, field_path = field_path })
      if not cont then return false end
    end
  end
  for _, key in ipairs(RAW_VIDEO_ENUM_KEYS) do
    local val = base.params_get(params, key)
    if val ~= nil and not RAW_VIDEO_ENUM_VALUES[key][val] then
      local cont = errors.record(ctx,
        "st2110-20.a.fmtp." .. key .. "-invalid-value",
        { pos = pos, field_path = field_path })
      if not cont then return false end
    end
  end
  for _, key in ipairs(RAW_VIDEO_VALUE_FORM_KEYS) do
    local val = base.params_get(params, key)
    if val ~= nil and not RAW_VIDEO_VALUE_VALIDATORS[key](tostring(val)) then
      local cont = errors.record(ctx,
        "st2110-20.a.fmtp." .. key .. "-invalid-value",
        { pos = pos, field_path = field_path })
      if not cont then return false end
    end
  end
  for _, key in ipairs(RAW_VIDEO_FLAG_ONLY_KEYS) do
    local val = base.params_get(params, key)
    if val ~= nil and val ~= true then
      local cont = errors.record(ctx,
        "st2110-20.a.fmtp." .. key .. "-invalid-value",
        { pos = pos, field_path = field_path })
      if not cont then return false end
    end
  end
  return true
end

-- ── Cross-parameter SHALLs for raw video fmtp ────────────────────────────
-- Each helper evaluates one cross-parameter SHALL on a raw video fmtp's
-- params table. List order matches 1.0's check sequence for deterministic
-- fail_on_first emission.

-- §7.2 SSN-conditional. Forward direction only — reverse ("SSN=:2022
-- without :2022-only values forbidden") deferred per PLAN.md known items.
local function check_ssn_conditional(params, ctx, pos, field_path)
  local trigger
  if base.params_get(params, "TCS")         == "ST2115LOGS3" then trigger = "TCS=ST2115LOGS3" end
  if base.params_get(params, "colorimetry") == "ALPHA"       then trigger = "colorimetry=ALPHA" end
  if trigger and tostring(base.params_get(params, "SSN") or "") ~= "ST2110-20:2022" then
    local cont = errors.record(ctx,
      "st2110-20.a.fmtp.ssn-required-for-2022-only-values",
      { pos = pos, field_path = field_path, context = { trigger = trigger } })
    if not cont then return false end
  end
  return true
end

-- Cross-param check factory: when `predicate(params)` is true, record
-- `error_id` and (under fail_on_first) fail the match. Used for the
-- pairs of -20 / -22 SHALLs that share an identical predicate but
-- carry distinct error IDs because their authoring spec differs (see
-- RAW_VIDEO_CROSS_PARAM_CHECKS / JXSV_CROSS_PARAM_CHECKS below).
local function make_param_check(predicate, error_id)
  return function(params, ctx, pos, field_path)
    if predicate(params) then
      local cont = errors.record(ctx, error_id,
        { pos = pos, field_path = field_path })
      if not cont then return false end
    end
    return true
  end
end

-- §7.3 / RFC 9134 §7.1: BT2100 colorimetry permits only NARROW and FULL —
-- FULLPROTECT is forbidden. Per-key RANGE value-set is in 6.C.D.1.
local function pred_bt2100_fullprotect(params)
  return base.params_get(params, "colorimetry") == "BT2100"
     and base.params_get(params, "RANGE") == "FULLPROTECT"
end

local check_bt2100_range = make_param_check(
  pred_bt2100_fullprotect,
  "st2110-20.a.fmtp.bt2100-range-fullprotect-forbidden")

-- §7.3 / RFC 9134 §7.1: segmented requires interlace also present.
local function pred_segmented_no_interlace(params)
  return base.params_get(params, "segmented")
     and not base.params_get(params, "interlace")
end

local check_segmented_requires_interlace = make_param_check(
  pred_segmented_no_interlace,
  "st2110-20.a.fmtp.segmented-requires-interlace")

-- §6.3.3: PM=2110BPM forbids MAXUDP (Block Packing Mode is incompatible
-- with the Extended UDP Size Limit).
local function check_bpm_forbids_maxudp(params, ctx, pos, field_path)
  if base.params_get(params, "PM") == "2110BPM"
     and base.params_get(params, "MAXUDP") ~= nil then
    local cont = errors.record(ctx,
      "st2110-20.a.fmtp.bpm-with-maxudp-forbidden",
      { pos = pos, field_path = field_path })
    if not cont then return false end
  end
  return true
end

-- §7.4.1: sampling=KEY requires colorimetry=ALPHA AND forbids TCS.
-- Two separate registered IDs so an audit can target either independently.
local function check_key_sampling(params, ctx, pos, field_path)
  if base.params_get(params, "sampling") == "KEY" then
    if base.params_get(params, "colorimetry") ~= "ALPHA" then
      local cont = errors.record(ctx,
        "st2110-20.a.fmtp.key-requires-alpha-colorimetry",
        { pos = pos, field_path = field_path })
      if not cont then return false end
    end
    if base.params_get(params, "TCS") ~= nil then
      local cont = errors.record(ctx,
        "st2110-20.a.fmtp.key-forbids-tcs",
        { pos = pos, field_path = field_path })
      if not cont then return false end
    end
  end
  return true
end

-- §6.2.5: 4:2:0 sampling applies to progressive scan only — must not be
-- combined with the interlace flag. Detected via the `-4:2:0` suffix on
-- any sampling token (YCbCr-4:2:0 / CLYCbCr-4:2:0 / ICtCp-4:2:0).
local function check_420_progressive_only(params, ctx, pos, field_path)
  local s = base.params_get(params, "sampling")
  if s and type(s) == "string" and s:match("^[%w]+%-4:2:0$") then
    if base.params_get(params, "interlace") then
      local cont = errors.record(ctx,
        "st2110-20.a.fmtp.subsampling-420-with-interlace-forbidden",
        { pos = pos, field_path = field_path })
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

local function check_420_depth_restricted(params, ctx, pos, field_path)
  local s = base.params_get(params, "sampling")
  if s and type(s) == "string" and s:match("^[%w]+%-4:2:0$") then
    local depth = base.params_get(params, "depth")
    if depth and RAW_420_FORBIDDEN_DEPTHS[tostring(depth)] then
      local cont = errors.record(ctx,
        "st2110-20.a.fmtp.subsampling-420-depth-restricted",
        { pos = pos, field_path = field_path,
          context = { sampling = s, depth = depth } })
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

local function check_tcs_floating_point_depth(params, ctx, pos, field_path)
  local tcs = base.params_get(params, "TCS")
  local err_id = TCS_REQUIRES_16F[tcs]
  local depth = base.params_get(params, "depth")
  if err_id and tostring(depth or "") ~= "16f" then
    local cont = errors.record(ctx, err_id,
      { pos = pos, field_path = field_path,
        context = { TCS = tcs, depth = depth } })
    if not cont then return false end
  end
  return true
end

-- Per-fmtp dispatch helper: runs each cross-param check on a single
-- params table. Order matches 1.0's check sequence (with 6.C.F additions
-- appended) so fail_on_first behaviour is stable across tiers.
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

local function check_raw_video_fmtp_cross_param(params, ctx, pos, field_path)
  for _, fn in ipairs(RAW_VIDEO_CROSS_PARAM_CHECKS) do
    if not fn(params, ctx, pos, field_path) then return false end
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
  return patterns.pos_int:match(v) ~= nil
end

local function validate_integer(v)
  return patterns.int:match(v) ~= nil
end

local function validate_ssn22(v)
  return v == "ST2110-22:2019" or v == "ST2110-22:2022"
end

local JXSV_VALUE_VALIDATORS = {
  width          = validate_pixel_dim,
  height         = validate_pixel_dim,
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
-- The merged check_jxsv_fmtp below this section (after the JXSV_*
-- constants) walks this list for required-presence and the other
-- three lists for enum / value-form / flag validation.
local JXSV_REQUIRED_PARAMS = { "width", "height", "TP", "packetmode" }

-- ── Cross-parameter SHALLs for jxsv fmtp (Phase 6.C.G.2) ─────────────────
-- Two cross-parameter SHALLs in RFC 9134 §7.1, parallel in shape to two
-- of the -20 SHALLs (segmented-requires-interlace; BT2100/RANGE). The
-- predicates are identical; only the registered error IDs differ
-- (RFC 9134 authors the SHALL for jxsv, ST 2110-20 §7.3 for raw). The
-- make_param_check factory above produces both pairs from one predicate.
local JXSV_CROSS_PARAM_CHECKS = {
  make_param_check(pred_segmented_no_interlace,
    "st2110-22.a.fmtp.segmented-requires-interlace"),
  make_param_check(pred_bt2100_fullprotect,
    "st2110-22.a.fmtp.bt2100-range-fullprotect-forbidden"),
}

-- ST 2110-30 / -31 audio channel-order syntax.
--
-- Validate a channel-order value against ST 2110-30 §6.2.2 + ST 2110-31
-- §6.2 Table 2 + RFC 3190. Pure-LPeg structural parse; the AES3-on-AM824
-- cross-encoding check is the only piece that needs Lua (it depends on
-- the runtime `encoding` argument).
--
-- Grammar (no whitespace inside `(...)` per the spec's literal form):
--   channel_order   = convention "." order
--   convention      = 1*(non-dot non-WS char)
--   For SMPTE2110:
--     order         = "(" group *("," group) ")"
--     group         = "M" | "DM" | "ST" | "LtRt" | "51" | "71" | "222"
--                   | "SGRP"                                  ; §6.2.2 Table 1
--                   | "AES3"                                  ; -31 §6.2 Table 2
--                   | "U" Udd                                 ; Undefined group
--     Udd           = "0"[1-9] | [1-5][0-9] | "6"[0-4]        ; 01..64
--   For any other convention: accepted without further structural check
--   (§6.2.2 only constrains the SMPTE2110 convention).
--
-- Returns (true, nil) on accept, or (false, err_id) on reject. err_id
-- distinguishes the two normative sources (-30 vs -31) so an audit grep
-- can target either.

-- "01".."64" — three disjoint sub-ranges captured by LPeg's ordered choice.
local _udd = P("0") * R("19")            -- 01..09
           + R("15") * R("09")           -- 10..59
           + P("6")  * R("04")           -- 60..64

local _channel_group =
      P("AES3")                          -- alternation order: longer first
    + P("LtRt")
    + P("SGRP")
    + P("DM")
    + P("ST")
    + P("222") + P("51") + P("71")
    + P("M")
    + P("U") * _udd

-- Returns array of captured group symbol-strings on match, nil on fail.
-- Anchored: must consume the whole order body.
local _smpte2110_order_pat =
      P("(")
    * Ct(C(_channel_group) * (P(",") * C(_channel_group)) ^ 0)
    * P(")")
    * P(-1)

-- Splits "<convention>.<order>" → (convention_str, order_str). Returns
-- nil when no '.' is present or either side is empty / contains whitespace.
local _channel_order_split_pat =
      C((1 - lpeg.S(". \t\r\n")) ^ 1)
    * P(".")
    * C((1 - lpeg.S(" \t\r\n")) ^ 1)
    * P(-1)

local function validate_channel_order(value, encoding)
  local convention, order = _channel_order_split_pat:match(value)
  if not convention then
    return false, "st2110-30.a.fmtp.channel-order-invalid"
  end
  if convention ~= "SMPTE2110" then
    return true
  end
  local groups = _smpte2110_order_pat:match(order)
  if not groups then
    return false, "st2110-30.a.fmtp.channel-order-invalid"
  end
  for _, g in ipairs(groups) do
    if g == "AES3" and encoding ~= "AM824" then
      return false, "st2110-31.a.fmtp.channel-order-aes3-requires-am824"
    end
  end
  return true
end

-- ── ST 2110-41 Fast Metadata fmtp narrowings (Phase 6.C.J) ────────────────
-- ST 2110-41:2024 fmtp shape is distinct from the -20 family: SSN is the
-- only required parameter, DIT is optional with a tight value form, and
-- MAXUDP is forbidden. The rtpmap encoding token is `ST2110-41` (the
-- IANA media-subtype name; ST 2110-41:2024 §6).

-- §6: SSN value is `ST2110-41:YYYY`; only 2024 is defined.
local function validate_ssn41(v) return v == "ST2110-41:2024" end

-- §6: "comma-separated uppercase hex tokens; no leading '0x'; no whitespace".
-- LPeg pattern mirrors the 1.0 parser's _dit_pat: Lua string-patterns don't
-- support quantified groups, so `(,token)*` isn't expressible as `string.match`.
local _dit_hex_upper = lpeg.R("09", "AF") ^ 1
local _dit_pat       = _dit_hex_upper
                     * (lpeg.P(",") * _dit_hex_upper) ^ 0
                     * lpeg.P(-1)

local function validate_dit(v)
  return _dit_pat:match(v) ~= nil
end

-- ── smpte291 fmtp checks (Phase 10.A.0.4) ─────────────────────────────────
-- ST 2110-40:2023 §7 + RFC 8331 §4 SHALLs for ANC data fmtp.

-- DID_SDID = `{0xH[H],0xH[H]}` per RFC 8331 §4 (TwoHex = "0x" 1*2(HEXDIG)).
local _hex     = lpeg.R("09", "af", "AF")
local _twohex  = lpeg.P("0x") * _hex * _hex ^ -1
local DID_SDID_PAT = lpeg.P("{") * _twohex * lpeg.P(",") * _twohex * lpeg.P("}")
                  * lpeg.P(-1)

local function validate_did_sdid(v)
  return DID_SDID_PAT:match(v) ~= nil
end

local function validate_vpid_code(v)
  -- Single integer; non-negative per the SMPTE ST 352M code field.
  return patterns.zero_based_int:match(v) ~= nil
end

local VALID_TM = { LLTM = true, CTM = true }

-- §7: SSN required + value depends on TM presence; ST2110-40:2021 is
-- accepted as equivalent to :2023 when TM is signaled (receiver-equivalence
-- clause). When TM is absent the value MUST be ST2110-40:2018.
local function validate_ssn40(v, tm_signaled)
  if tm_signaled then
    return v == "ST2110-40:2023" or v == "ST2110-40:2021"
  end
  return v == "ST2110-40:2018"
end

-- §7 delegates TROFF value form to ST 2110-21:2022 §8.2: positive integer.
local function validate_troff(v)
  return patterns.pos_int:match(v) ~= nil
end

local function check_smpte291_fmtp(params, ctx, pos, field_path, _encoding)
  -- RFC 8331 §4 — VPID_Code cardinality + value form.
  local vpid_first
  local vpid_count = 0
  for _, e in ipairs(params or {}) do
    if e[1] == "VPID_Code" then
      vpid_count = vpid_count + 1
      vpid_first = vpid_first or e[2]
    end
  end
  if vpid_count > 1 then
    local cont = errors.record(ctx,
      "st2110-40.a.fmtp.vpid-code-too-many",
      { pos = pos, field_path = field_path,
        context = { count = vpid_count } })
    if not cont then return false end
  end
  if vpid_first ~= nil and vpid_first ~= true
      and not validate_vpid_code(tostring(vpid_first)) then
    local cont = errors.record(ctx,
      "st2110-40.a.fmtp.vpid-code-invalid-value",
      { pos = pos, field_path = field_path,
        context = { value = tostring(vpid_first) } })
    if not cont then return false end
  end

  -- RFC 8331 §4 — every DID_SDID occurrence must match the TwoHex form.
  for _, e in ipairs(params or {}) do
    if e[1] == "DID_SDID" and e[2] ~= true and not validate_did_sdid(tostring(e[2])) then
      local cont = errors.record(ctx,
        "st2110-40.a.fmtp.did-sdid-invalid-value",
        { pos = pos, field_path = field_path,
          context = { value = tostring(e[2]) } })
      if not cont then return false end
    end
  end

  -- ST 2110-40:2023 §7 — TM value enum (when present).
  local tm = base.params_get(params, "TM")
  if tm ~= nil and tm ~= true and not VALID_TM[tostring(tm)] then
    local cont = errors.record(ctx,
      "st2110-40.a.fmtp.tm-invalid-value",
      { pos = pos, field_path = field_path,
        context = { value = tostring(tm) } })
    if not cont then return false end
  end

  -- ST 2110-40:2023 §7 — SSN required + value form (TM-conditional;
  -- receiver-equivalence accepts :2021 wherever :2023 is required).
  local ssn = base.params_get(params, "SSN")
  local tm_signaled = (tm ~= nil and tm ~= true)
  if ssn == nil then
    local cont = errors.record(ctx,
      "st2110-40.a.fmtp.ssn-required",
      { pos = pos, field_path = field_path })
    if not cont then return false end
  elseif ssn ~= true and not validate_ssn40(tostring(ssn), tm_signaled) then
    local cont = errors.record(ctx,
      "st2110-40.a.fmtp.ssn-invalid-value",
      { pos = pos, field_path = field_path,
        context = { value = tostring(ssn), tm_signaled = tm_signaled } })
    if not cont then return false end
  end

  -- ST 2110-40:2023 §7 — exactframerate required + value form
  -- (delegates to ST 2110-20:2022 §7.2 form via validate_exactframerate).
  local efr = base.params_get(params, "exactframerate")
  if efr == nil then
    local cont = errors.record(ctx,
      "st2110-40.a.fmtp.exactframerate-required",
      { pos = pos, field_path = field_path })
    if not cont then return false end
  elseif efr ~= true and not validate_exactframerate(tostring(efr)) then
    local cont = errors.record(ctx,
      "st2110-40.a.fmtp.exactframerate-invalid-value",
      { pos = pos, field_path = field_path,
        context = { value = tostring(efr) } })
    if not cont then return false end
  end

  -- ST 2110-40:2023 §7 — TROFF optional; when present, value form
  -- delegates to ST 2110-21:2022 §8.2 (positive integer).
  local troff = base.params_get(params, "TROFF")
  if troff ~= nil and troff ~= true and not validate_troff(tostring(troff)) then
    local cont = errors.record(ctx,
      "st2110-40.a.fmtp.troff-invalid-value",
      { pos = pos, field_path = field_path,
        context = { value = tostring(troff) } })
    if not cont then return false end
  end

  return true
end

local function check_st2110_41_fmtp(params, ctx, pos, field_path)
  -- §6: SSN required.
  local ssn = base.params_get(params, "SSN")
  if ssn == nil then
    local cont = errors.record(ctx,
      "st2110-41.a.fmtp.SSN-required",
      { pos = pos, field_path = field_path })
    if not cont then return false end
  elseif type(ssn) == "string" and not validate_ssn41(ssn) then
    local cont = errors.record(ctx,
      "st2110-41.a.fmtp.SSN-invalid-value",
      { pos = pos, field_path = field_path,
        context = { value = ssn } })
    if not cont then return false end
  end

  -- §6: DIT optional; when present, must match the hex-token form.
  local dit = base.params_get(params, "DIT")
  if dit ~= nil and dit ~= true then
    if type(dit) ~= "string" or not validate_dit(dit) then
      local cont = errors.record(ctx,
        "st2110-41.a.fmtp.DIT-invalid-value",
        { pos = pos, field_path = field_path,
          context = { value = dit } })
      if not cont then return false end
    end
  end

  -- §5.4: MAXUDP forbidden on ST 2110-41 streams.
  local maxudp = base.params_get(params, "MAXUDP")
  if maxudp ~= nil then
    local cont = errors.record(ctx,
      "st2110-41.a.fmtp.maxudp-forbidden",
      { pos = pos, field_path = field_path,
        context = { value = maxudp } })
    if not cont then return false end
  end
  return true
end

-- ST 2110-30:2025 §6.2.1: "The Standard UDP Datagram Size Limit as defined
-- in SMPTE ST 2110-10 shall be used." MAXUDP signals operation beyond the
-- Standard Limit (ST 2110-10:2022 §6.4 / §8.6), so its presence in an
-- L16 / L24 fmtp violates the §6.2.1 SHALL. AM824 intentionally excluded
-- (ST 2110-31 has no UDP-size SHALL — see conformance-principle audit).
local function check_audio_maxudp_forbidden(params, ctx, pos, field_path, encoding)
  if base.params_get(params, "MAXUDP") ~= nil then
    local cont = errors.record(ctx,
      "st2110-30.a.fmtp.maxudp-forbidden",
      { pos = pos, field_path = field_path,
        context = { encoding = encoding } })
    if not cont then return false end
  end
  return true
end

-- Phase 6.E.B — ST 2110-10:2022 §8.5 group:DUP leg coherence.
--
-- §8.5 requires duplicate RTP streams to "meet the requirements of SMPTE
-- ST 2022-7". ST 2022-7:2019 §6 requires (a) "at least two streams" and
-- (b) "RTP header and RTP payload shall be identical for each datagram
-- copy". The SDP attributes that define the RTP packet shape — m= media
-- type, a=rtpmap (encoding + clock rate + PT), a=fmtp params — must
-- therefore match across DUP legs. §8.5 also directly forbids identical
-- src+dst across legs. See parse_sdp/errors.lua header for the full
-- chain-of-SHALLs grounding.
--
-- Single tier-level semantic check walks doc.session.attributes for
-- group:DUP entries; for each, resolves tags via mid_index, validates
-- min-2 legs, then compares legs[2..N] to legs[1] across all five
-- essence attributes plus address coherence. All findings share
-- spec_ref "ST 2110-10:2022 §8.5".

-- Order-insensitive equality on two ordered kv-lists (each a Ct of
-- {key, value | true} sub-tables — see base.params_get). Compares by
-- key; element order is intentionally ignored so two fmtp lines that
-- list the same params in different orders are treated as equal (the
-- group:DUP coherence SHALL is on packet-shape equivalence, not on
-- SDP textual layout).
local function params_equal(a, b)
  if a == nil and b == nil then return true end
  if a == nil or b == nil then return false end
  if #a ~= #b then return false end
  for i = 1, #a do
    local e = a[i]
    if base.params_get(b, e[1]) ~= e[2] then return false end
  end
  return true
end

local function first_attr(block, name)
  for _, attr in ipairs(block.attributes) do
    if attr.name == name then return attr end
  end
  return nil
end

local function leg_src_dst(block, doc)
  local conn = block.connection or doc.session.connection
  local dst  = conn and conn.address or ""
  local sf   = first_attr(block, "source-filter")
  local src  = (sf and sf.src_addresses and sf.src_addresses[1]) or ""
  return src, dst
end

local function check_group_dup_coherence(doc, ctx)
  local mid_index = {}
  for i, m in ipairs(doc.media) do
    for _, attr in ipairs(m.attributes) do
      if attr.name == "mid" then
        mid_index[attr.tag] = { index = i, block = m }
      end
    end
  end

  for gi, gattr in ipairs(doc.session.attributes) do
    if gattr.name == "group" and gattr.semantics == "DUP" then
      local path = string.format(
        "session.attributes[group][%d]", gi - 1)

      local legs = {}
      for _, tag in ipairs(gattr.tags) do
        local entry = mid_index[tag]
        if not entry then
          local cont = errors.record(ctx,
            "st2110-10.a.group-dup.mid-resolve",
            { field_path = path, context = { tag = tag } })
          if not cont then return false end
        else
          legs[#legs + 1] = entry
        end
      end

      if #legs < 2 then
        local cont = errors.record(ctx,
          "st2110-10.a.group-dup.min-2-legs",
          { field_path = path, context = { resolved_legs = #legs } })
        if not cont then return false end
      else
        local lead       = legs[1].block
        local base_rm    = first_attr(lead, "rtpmap")
        local base_fm    = first_attr(lead, "fmtp")
        local base_src, base_dst = leg_src_dst(lead, doc)

        for j = 2, #legs do
          local leg = legs[j].block
          if leg.media ~= lead.media then
            local cont = errors.record(ctx,
              "st2110-10.a.group-dup.media-type-same",
              { field_path = path })
            if not cont then return false end
          end
          local rm = first_attr(leg, "rtpmap")
          if (rm and rm.encoding) ~= (base_rm and base_rm.encoding)
              or (rm and rm.clock_rate) ~= (base_rm and base_rm.clock_rate) then
            local cont = errors.record(ctx,
              "st2110-10.a.group-dup.rtpmap-same",
              { field_path = path })
            if not cont then return false end
          end
          if (rm and rm.payload_type) ~= (base_rm and base_rm.payload_type) then
            local cont = errors.record(ctx,
              "st2110-10.a.group-dup.payload-type-same",
              { field_path = path })
            if not cont then return false end
          end
          local fm = first_attr(leg, "fmtp")
          if not params_equal(fm and fm.params, base_fm and base_fm.params) then
            local cont = errors.record(ctx,
              "st2110-10.a.group-dup.fmtp-same",
              { field_path = path })
            if not cont then return false end
          end
          local src, dst = leg_src_dst(leg, doc)
          if dst ~= "" and dst == base_dst and src == base_src then
            local cont = errors.record(ctx,
              "st2110-10.a.group-dup.addr-coherence",
              { field_path = path })
            if not cont then return false end
          end
        end
      end
    end
  end
  return true
end

-- Phase 6.D.D — ST 2110-30:2025 §6.2.1 audio packet-payload-fit.
-- §6.2.1 requires "The Standard UDP Datagram Size Limit as defined in
-- SMPTE ST 2110-10 shall be used". ST 2110-10:2022 §6.4 sets that limit
-- at 1460 octets. With the 12-octet RTP fixed header (RFC 3550), the
-- RTP payload available for audio samples is 1448 octets.
--
-- Walk doc.media, find audio rtpmap PTs whose encoding is L16 or L24,
-- pair with the media-block's a=ptime, compute the required payload
-- size, and emit a finding when it exceeds the limit. AM824 is
-- intentionally excluded (6.D.D scope matches 6.D.B).
local PCM_BYTES_PER_SAMPLE = { L16 = 2, L24 = 3 }
local AUDIO_PACKET_PAYLOAD_LIMIT = 1448  -- 1460 (UDP) - 12 (RTP header)

local function check_audio_packet_payload_fit(block, ctx)
  local ptime
  for _, attr in ipairs(block.attributes) do
    if attr.name == "ptime" then ptime = attr.value end
  end
  if not ptime then return true end
  for _, attr in ipairs(block.attributes) do
    local bps = attr.name == "rtpmap"
        and PCM_BYTES_PER_SAMPLE[attr.encoding] or nil
    if bps and attr.clock_rate then
      local channels = attr.channels or 1
      local samples = math.floor(attr.clock_rate * ptime / 1000 + 0.5)
      local needed  = channels * bps * samples
      if needed > AUDIO_PACKET_PAYLOAD_LIMIT then
        local cont = errors.record(ctx,
          "st2110-30.audio.packet-payload-fit",
          { field_path = string.format(
              "media[%d].attributes[rtpmap:pt=%d]",
              ctx.media_index or 0, attr.payload_type),
            context    = { channels = channels, bps = bps,
                           samples_per_packet = samples,
                           needed = needed,
                           limit = AUDIO_PACKET_PAYLOAD_LIMIT } })
        if not cont then return false end
      end
    end
  end
  return true
end

local function check_audio_fmtp_channel_order(params, ctx, pos, field_path, encoding)
  local co = base.params_get(params, "channel-order")
  if co ~= nil and co ~= true then
    local ok, err_id = validate_channel_order(tostring(co), encoding)
    if not ok then
      local cont = errors.record(ctx, err_id,
        { pos = pos, field_path = field_path,
          context = { encoding = encoding, value = co } })
      if not cont then return false end
    end
  end
  return true
end

-- Phase 6.D.A — ST 2110-10:2022 §8.2 / §8.3 per-media-block presence.
-- §8.2: "All stream descriptions shall have a ts-refclk attribute as
--        specified in IETF RFC 7273 section 4."
-- §8.3: "All stream descriptions shall have a media-level mediaclk
--        attribute as per IETF RFC 7273 section 5."
-- Both checks walk doc.media and emit a finding on any block missing
-- the required attribute. RFC 7273 §4.8 permits ts-refclk at session
-- level — when present there it covers all media blocks. §8.3's
-- "media-level" qualifier explicitly restricts mediaclk: a session-
-- level mediaclk does NOT satisfy a per-stream block lacking its own.
local function has_attr(attrs, name)
  for _, attr in ipairs(attrs) do
    if attr.name == name then return true end
  end
  return false
end

-- ST 2110-10:2022 §8.2 / §8.3 ts-refclk and mediaclk SHALLs apply to
-- RTP streams. IPMX-tier extensions allow non-RTP media blocks (e.g.,
-- m=application TCP usb under TR-10-14) where these RTP-specific
-- timing attributes don't apply; gate on base.is_rtp_block so a non-
-- RTP block doesn't spuriously trip the ST 2110 presence checks.
local function check_ts_refclk_presence(doc, ctx)
  if has_attr(doc.session.attributes, "ts-refclk") then return true end
  for i, m in ipairs(doc.media) do
    if base.is_rtp_block(m)
       and not has_attr(m.attributes, "ts-refclk") then
      local cont = errors.record(ctx, "st2110.attr.ts-refclk-required",
        { field_path = string.format("media[%d]", i - 1) })
      if not cont then return false end
    end
  end
  return true
end

local function check_mediaclk_presence(block, ctx)
  if not base.is_rtp_block(block) then return true end
  if has_attr(block.attributes, "mediaclk") then return true end
  local cont = errors.record(ctx, "st2110.attr.mediaclk-required",
    { field_path = string.format("media[%d]", ctx.media_index or 0) })
  if not cont then return false end
  return true
end

-- ST 2110-10:2022 §6.2 — RTP streams shall conform to the RTP Profile
-- specified in IETF RFC 3551, which SDP names "RTP/AVP". Scope: RTP
-- blocks only (proto starts with "RTP/"); non-RTP transports are out
-- of scope. The check fires when a block declares an RTP-shaped proto
-- other than RTP/AVP (e.g. RTP/SAVP, RTP/AVPF) — those name different
-- IETF profiles not permitted by ST 2110-10 §6.2's RFC 3551 SHALL.
local function check_rtp_profile(block, ctx)
  if not base.is_rtp_block(block) then return true end
  if block.proto == "RTP/AVP" then return true end
  local cont = errors.record(ctx, "st2110-10.m.proto-must-be-rtp-avp",
    { field_path = string.format("media[%d].proto", ctx.media_index or 0),
      context    = { proto = block.proto } })
  if not cont then return false end
  return true
end

local function check_jxsv_fmtp_cross_param(params, ctx, pos, field_path)
  for _, fn in ipairs(JXSV_CROSS_PARAM_CHECKS) do
    if not fn(params, ctx, pos, field_path) then return false end
  end
  return true
end

-- Per-fmtp jxsv required-presence + value-form check, one walk per key
-- class. Mirrors check_raw_video_fmtp's structure: the function was
-- originally two (`_required` from Phase 6.C.G.1 and `_values` from
-- 6.C.G.1) and is merged here for symmetry and to eliminate the
-- duplicate iteration. Used by the in-grammar fmtp dispatch and by
-- FMTP_REQUIRED_BY_ENCODING (called with empty params to emit just the
-- required-presence half when no fmtp is present).
local function check_jxsv_fmtp(params, ctx, pos, field_path)
  -- Required-presence (RFC 9134 §7.1).
  for _, key in ipairs(JXSV_REQUIRED_PARAMS) do
    if base.params_get(params, key) == nil then
      local cont = errors.record(ctx,
        "st2110-22.a.fmtp." .. key .. "-required",
        { pos = pos, field_path = field_path })
      if not cont then return false end
    end
  end
  -- Enum value-set narrowings.
  for _, key in ipairs(JXSV_ENUM_KEYS) do
    local val = base.params_get(params, key)
    if val ~= nil and not JXSV_ENUM_VALUES[key][tostring(val)] then
      local cont = errors.record(ctx,
        "st2110-22.a.fmtp." .. key .. "-invalid-value",
        { pos = pos, field_path = field_path })
      if not cont then return false end
    end
  end
  -- Non-enum value-form predicates.
  for _, key in ipairs(JXSV_VALUE_FORM_KEYS) do
    local val = base.params_get(params, key)
    if val ~= nil and not JXSV_VALUE_VALIDATORS[key](tostring(val)) then
      local cont = errors.record(ctx,
        "st2110-22.a.fmtp." .. key .. "-invalid-value",
        { pos = pos, field_path = field_path })
      if not cont then return false end
    end
  end
  -- Flag-only keys: present iff the value is the boolean true.
  for _, key in ipairs(JXSV_FLAG_ONLY_KEYS) do
    local val = base.params_get(params, key)
    if val ~= nil and val ~= true then
      local cont = errors.record(ctx,
        "st2110-22.a.fmtp." .. key .. "-invalid-value",
        { pos = pos, field_path = field_path })
      if not cont then return false end
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
      ok = ok and errors.record(ctx, rate_check_id.id, { pos = pos })
    end
    if media ~= expected_media then
      ok = ok and errors.record(ctx, media_check_id, { pos = pos })
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

-- ── Phase 10.A.0.3 — cross-encoding fmtp value-form checks ────────────────
-- ST 2110-10:2022 §8.7 defines TSMODE and TSDELAY under §8 "SDP
-- Parameters" (the umbrella section), so they may appear on any ST 2110
-- RTP stream's fmtp regardless of essence type. These checks run BEFORE
-- the per-encoding dispatch so the value-form SHALL fires whether or
-- not the surrounding encoding has its own check list.

local VALID_TSMODE = { SAMP = true, NEW = true, PRES = true }

-- Signature matches the per-encoding contract (params, ctx, pos,
-- field_path, encoding) so the dispatch loop calls every check the
-- same way. `encoding` is unused here — the §8.7 SHALL is cross-encoding.
local function check_tsmode_tsdelay(params, ctx, pos, field_path, _encoding)
  local tsmode = base.params_get(params, "TSMODE")
  if tsmode ~= nil and tsmode ~= true and not VALID_TSMODE[tostring(tsmode)] then
    local cont = errors.record(ctx,
      "st2110-10.a.fmtp.tsmode-invalid-value",
      { pos = pos, field_path = field_path,
        context = { value = tostring(tsmode) } })
    if not cont then return false end
  end
  local tsdelay = base.params_get(params, "TSDELAY")
  if tsdelay ~= nil and tsdelay ~= true
      and not patterns.pos_int:match(tostring(tsdelay)) then
    local cont = errors.record(ctx,
      "st2110-10.a.fmtp.tsdelay-invalid-value",
      { pos = pos, field_path = field_path,
        context = { value = tostring(tsdelay) } })
    if not cont then return false end
  end
  return true
end

-- Cross-encoding checks fire on every structured fmtp regardless of the
-- rtpmap encoding (or its absence). Order matters: a hard-fail in any
-- entry aborts dispatch before per-encoding checks run.
local FMTP_COMMON_CHECKS = {
  check_tsmode_tsdelay,
}

-- ── Phase 6.F — per-fmtp-line check dispatch ───────────────────────────────
-- Each entry maps a rtpmap encoding string to the ordered list of (params,
-- ctx, encoding) → bool checks that fire when an a=fmtp on that encoding's
-- PT completes. The trailing Cmt on a_fmtp (in the overrides table below)
-- looks the encoding up via ctx.rtpmap_encodings[pt] (populated by
-- a_rtpmap's own trailing Cmt) and runs the matching list.
--
-- Encodings absent from this table get no per-encoding checks — unknown
-- encodings or essences with no spec-grounded fmtp narrowings. Cross-
-- encoding §8.7 TSMODE/TSDELAY value-form checks still fire via
-- FMTP_COMMON_CHECKS above.
local FMTP_CHECKS_BY_ENCODING = {
  raw = {
    check_raw_video_fmtp,
    check_raw_video_fmtp_cross_param,
  },
  jxsv = {
    check_jxsv_fmtp,
    check_jxsv_fmtp_cross_param,
  },
  -- Audio channel-order syntax applies to all three audio encodings
  -- (ST 2110-30 §6.2.2 + -31 §6.2 Table 2 extension). MAXUDP-forbidden
  -- is L16/L24 only — AM824 has no UDP-size SHALL.
  L16   = { check_audio_fmtp_channel_order, check_audio_maxudp_forbidden },
  L24   = { check_audio_fmtp_channel_order, check_audio_maxudp_forbidden },
  AM824 = { check_audio_fmtp_channel_order },
  ["ST2110-41"] = { check_st2110_41_fmtp },
  smpte291 = { check_smpte291_fmtp },
}

-- Dispatch contract: each check is invoked as
--   check(params, ctx, pos, field_path[, encoding]) → bool
-- pos:        LPeg byte position after the matched fmtp line (loc.pos for
--             line/col translation in errors.record).
-- field_path: pre-formatted "media[N].attributes[fmtp:pt=PT]" string
--             (Phase 6.K; N comes from ctx.media_index, set by the
--              leading Cmt on media_section).
-- encoding:   the rtpmap encoding name for this PT — only the audio checks
--             declare a 5th parameter; raw/jxsv/-41 checks ignore it
--             because the dispatch table already keyed by encoding.
local function fmtp_dispatch(_, pos, pt, params, ctx)
  if params == nil then return pos end       -- raw-fallback path; skip
  local enc = ctx and ctx.rtpmap_encodings
                    and ctx.rtpmap_encodings[pt]
  local field_path = string.format(
    "media[%d].attributes[fmtp:pt=%d]", ctx.media_index or 0, pt)
  -- Cross-encoding checks fire regardless of whether the PT has a
  -- recognized rtpmap (ST 2110-10 §8.7 applies to every ST 2110 RTP
  -- stream's fmtp).
  for _, check in ipairs(FMTP_COMMON_CHECKS) do
    if not check(params, ctx, pos, field_path, enc) then return false end
  end
  local checks = enc and FMTP_CHECKS_BY_ENCODING[enc]
  if not checks then return pos end
  for _, check in ipairs(checks) do
    if not check(params, ctx, pos, field_path, enc) then return false end
  end
  return pos
end

-- When a raw / jxsv / ST 2110-41 rtpmap is present, the matching a=fmtp
-- must also be present (the §7.2 / §7.1 / §6 required-Media-Type-parameter
-- SHALLs can't be satisfied otherwise). If no fmtp exists, call the same
-- per-encoding required-check against an empty params table — yields the
-- same `<key>-required` finding set the in-grammar dispatch would emit.
local FMTP_REQUIRED_BY_ENCODING = {
  raw           = check_raw_video_fmtp,
  jxsv          = check_jxsv_fmtp,
  ["ST2110-41"] = check_st2110_41_fmtp,
  smpte291      = check_smpte291_fmtp,
}

local function check_rtpmap_requires_fmtp(block, ctx)
  local needs, has = {}, {}
  for _, attr in ipairs(block.attributes) do
    if attr.name == "rtpmap"
       and FMTP_REQUIRED_BY_ENCODING[attr.encoding] then
      needs[attr.payload_type] = attr.encoding
    elseif attr.name == "fmtp" then
      has[attr.payload_type] = true
    end
  end
  for pt, enc in pairs(needs) do
    if not has[pt] then
      local check = FMTP_REQUIRED_BY_ENCODING[enc]
      if not check({}, ctx) then return false end
    end
  end
  return true
end

-- ST 2110-22:2022 §7.3 (verbatim): "The media-level section of the SDP
-- object shall include the attribute listed in Table 3." Table 3's only
-- row is `b=<brtype>:<brvalue>` with `<brtype> shall be AS` and
-- `<brvalue>` an integer number of kilobits per second. Applies per
-- media block that carries a jxsv rtpmap. (TR-10-7 §11 substitutes
-- only the Table 3 cell semantics for IPMX-compressed-video; the
-- §7.3 SHALL on presence is unchanged and inherited via composition.)
local function check_jxsv_bandwidth(block, ctx)
  local has_jxsv = false
  for _, attr in ipairs(block.attributes) do
    if attr.name == "rtpmap" and attr.encoding == "jxsv" then
      has_jxsv = true
      break
    end
  end
  if not has_jxsv then return true end

  local field_path = string.format(
    "media[%d].bandwidths", ctx.media_index or 0)
  local has_as = false
  for _, b in ipairs(block.bandwidths or {}) do
    if b.type == "AS" then
      has_as = true
      if type(b.value) ~= "number" or b.value <= 0 then
        local cont = errors.record(ctx, "st2110-22.b.as-invalid-value",
          { field_path = field_path })
        if not cont then return false end
      end
    end
  end
  if not has_as then
    local cont = errors.record(ctx, "st2110-22.b.as-required",
      { field_path = field_path })
    if not cont then return false end
  end
  return true
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

    -- AM824 branch: in-grammar enforcement of ST 2110-31:2022 §6.1
    -- channels-required (mandatory <nchan> field) and channels-even
    -- (parity of <nchan>). Ordered choice on the optional `/<channels>`
    -- suffix: present → Cmt verifies even; absent → Cmt records the
    -- required SHALL. Both Cmts return `pos` to continue matching so
    -- the trailing rate+media Cmt still fires.
    st2110_rtpmap_am824 =
        P("AM824") * Cg(Cc("AM824"), "encoding") * P("/")
        * Cg(V"rfc8866_pos_int_num", "clock_rate")
        * ( P("/") * Cg(V"rfc8866_pos_int_num", "channels")
            * Cmt(Cb"payload_type" * Cb"channels" * Carg(1),
                  function(_, pos, pt, channels, ctx)
                    if (channels % 2) ~= 0 then
                      local cont = errors.record(ctx,
                        "st2110-31.a.rtpmap.am824-channels-must-be-even",
                        { pos = pos,
                          field_path = string.format(
                            "media[%d].attributes[rtpmap:pt=%d]",
                            ctx and ctx.media_index or 0, pt),
                          context = { channels = channels } })
                      if not cont then return false end
                    end
                    return pos
                  end)
          + Cmt(Cb"payload_type" * Carg(1),
                function(_, pos, pt, ctx)
                  local cont = errors.record(ctx,
                    "st2110-31.a.rtpmap.am824-channels-required",
                    { pos = pos,
                      field_path = string.format(
                        "media[%d].attributes[rtpmap:pt=%d]",
                        ctx and ctx.media_index or 0, pt) })
                  if not cont then return false end
                  return pos
                end)
          )
        * Cmt(Cb"clock_rate" * Cb"media" * Carg(1),
              record_rate_and_media(
                { id = "st2110-31.a.rtpmap.am824-clock-rate-set",
                  set = { [44100] = true, [48000] = true, [96000] = true } },
                "audio",
                "st2110-31.a.rtpmap.am824-media-type")),

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
    -- Per-fmtp-line validators dispatch via a trailing Cmt after the
    -- params branch completes. `Cb"params" + Cc(nil)` resolves to the
    -- captured params table OR nil when the fmtp fell into the raw
    -- fallback branch (no structured params); fmtp_dispatch returns
    -- pos when params is nil so the check is silently skipped, but
    -- propagates `false` (failing the match) when a check records an
    -- error with fail_on_first=true.
    a_fmtp = P("fmtp:")
        * Cg(Cc("fmtp"), "name")
        * Cg(V"payload_type", "payload_type") * SP
        * ( V"fmtp_st2110_raw_payload"
          + V"fmtp_payload_non_raw" )
        * Cmt(Cb"payload_type" * (Cb"params" + Cc(nil)) * Carg(1),
              fmtp_dispatch),

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
              * (V"fmtp_sep" * V"fmtp_st2110_raw_entry") ^ 0),
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
                ctx, "st2110-20.a.fmtp.no-whitespace-around-equals",
                { pos = pos })
              if not cont then return false end
            end
            return pos, { key, val }
          end),
  },

  -- Doc-level only: cross-section invariants that need the full doc
  -- (e.g. session-level ts-refclk coverage per RFC 7273 §4.8;
  -- group:DUP leg comparison). Per-fmtp / per-rtpmap / per-media-block
  -- checks live in-grammar (Cmts) or in media_section_checks below.
  semantic_checks = {
    check_ts_refclk_presence,
    check_group_dup_coherence,
  },

  media_section_checks = {
    check_rtp_profile,
    check_rtpmap_requires_fmtp,
    check_mediaclk_presence,
    check_audio_packet_payload_fit,
    check_jxsv_bandwidth,
  },
}

return base.extend(base, overrides)
