-- parse_sdp.grammar.codecs — base-tier checks from the IETF RTP payload-
-- format registrations: H.264 (RFC 6184). A payload-format RFC is
-- authored at the IETF layer, so its SHALLs sit beside the RFC 4570 /
-- 5888 / 7273 checks in the `sdp.` id family and run at every tier
-- (decision parse_sdp-59w). base.lua appends `check_codec_block` to its
-- media-section checks.
--
-- The checks read the block after it parsed: the rtpmap attributes bind
-- each payload type to an encoding, and each decomposed fmtp whose
-- payload type is bound to a known encoding gets that encoding's value-
-- form and presence rules. Encoding and parameter names compare case-
-- insensitively (RFC 8866 §6.6 via RFC 4855 §3: "these names are case-
-- insensitive in both places ... similar to parameter names which are
-- case-insensitive both in media type strings and in the default mapping
-- to the SDP "a=fmtp:" attribute").

local lpeg      = require("lpeg")
local errors    = require("parse_sdp.errors")
local accessors = require("parse_sdp.grammar.accessors")
local bitops    = require("parse_sdp.grammar.bitops")
local P, R, S   = lpeg.P, lpeg.R, lpeg.S

local M = {}

-- ── Value-form patterns ──────────────────────────────────────────────────────

local DIGITS = R("09") ^ 1 * -1
local HEX    = R("09", "af", "AF")
local HEX4   = HEX * HEX * HEX * HEX * -1
local HEX6   = HEX * HEX * HEX * HEX * HEX * HEX * -1

-- RFC 4648 §4 base64 alphabet with optional '=' padding. RFC 6184 §8.1:
-- sprop-parameter-sets is "a comma-separated (',') list of base64 [7]
-- representations of parameter set NAL units".
local B64      = (R("AZ", "az", "09") + S("+/")) ^ 1 * P("=") ^ -2
local B64_LIST = B64 * (P(",") * B64) ^ 0 * -1

-- RFC 6184 §8.1 sprop-level-parameter-sets: "Parameter sets for each level
-- are represented in the form of PLId:PSL, i.e., PLId followed by a colon
-- (':') and the base64 [7] representation of the initial parameter set NAL
-- units for the level. Each pair of PLId:PSLs is also separated by a
-- colon." PLId "has the same syntax as profile-level-id".
local PLID_PSL       = HEX * HEX * HEX * HEX * HEX * HEX * P(":")
                       * B64 * (P(",") * B64) ^ 0
local PLID_PSL_LIST  = PLID_PSL * (P(":") * PLID_PSL) ^ 0 * -1

local function matches(pattern)
  return function(v) return type(v) == "string" and pattern:match(v) ~= nil end
end

local function int_in(lo, hi)
  return function(v)
    if type(v) ~= "string" or not DIGITS:match(v) then return false end
    local n = tonumber(v)
    return n >= lo and n <= hi
  end
end

local is_int = matches(DIGITS)

-- Lower-cased view of an fmtp params list; first occurrence wins, as in
-- accessors.params_get.
local function params_ci(params)
  local t = {}
  for _, e in ipairs(params) do
    local k = string.lower(e[1])
    if t[k] == nil then t[k] = e[2] end
  end
  return t
end

local function record(ctx, id, field_path)
  return errors.record(ctx, id, { field_path = field_path })
end

-- ── H.264, RFC 6184 §8.1 ─────────────────────────────────────────────────────

-- Value forms, each quoted from RFC 6184 §8.1.
local H264_VALUE_FORMS = {
  -- "A base16 [7] (hexadecimal) representation of the following three bytes"
  { "profile-level-id",            matches(HEX6) },
  -- "a base16 (hexadecimal) representation of the two bytes after the
  -- syntax element profile_idc"
  { "max-recv-level",              matches(HEX4) },
  -- "The value of max-mbps is an integer" (and the same for the others)
  { "max-mbps",                    is_int },
  { "max-smbps",                   is_int },
  { "max-fs",                      is_int },
  { "max-cpb",                     is_int },
  { "max-dpb",                     is_int },
  { "max-br",                      is_int },
  -- "The value of redundant-pic-cap MUST be either 0 or 1."
  { "redundant-pic-cap",           int_in(0, 1) },
  { "sprop-parameter-sets",        matches(B64_LIST) },
  { "sprop-level-parameter-sets",  matches(PLID_PSL_LIST) },
  -- "The value MAY be equal to either 0 or 1." (three parameters)
  { "use-level-src-parameter-sets", int_in(0, 1) },
  { "in-band-parameter-sets",      int_in(0, 1) },
  { "level-asymmetry-allowed",     int_in(0, 1) },
  -- "MUST be an integer in the range of 0 to 2, inclusive."
  { "packetization-mode",          int_in(0, 2) },
  -- "MUST be an integer in the range of 0 to 32767, inclusive."
  { "sprop-interleaving-depth",    int_in(0, 32767) },
  { "sprop-max-don-diff",          int_in(0, 32767) },
  -- "MUST be an integer in the range of 0 to 4294967295, inclusive."
  { "sprop-deint-buf-req",         int_in(0, 4294967295) },
  { "deint-buf-cap",               int_in(0, 4294967295) },
  { "sprop-init-buf-time",         int_in(0, 4294967295) },
  { "max-rcmd-nalu-size",          int_in(0, 4294967295) },
  { "sar-understood",              is_int },
}

-- "sar-supported: ... The value of this parameter is an integer in the
-- range of 1 to sar-understood, inclusive, equal to 255." and "When
-- sar-understood is not present, the value MUST be inferred to be equal
-- to 13."
local function sar_supported_ok(v, p)
  if not is_int(v) then return false end
  local n = tonumber(v)
  if n == 255 then return true end
  local understood = is_int(p["sar-understood"]) and tonumber(p["sar-understood"]) or 13
  return n >= 1 and n <= understood
end

local function check_h264_fmtp(params, ctx, field_path)
  local p = params_ci(params)
  for _, row in ipairs(H264_VALUE_FORMS) do
    local key, ok = row[1], row[2]
    if p[key] ~= nil and not ok(p[key]) then
      if not record(ctx, "sdp.a.fmtp.h264." .. key .. "-invalid-value",
                    field_path) then return false end
    end
  end
  if p["sar-supported"] ~= nil and not sar_supported_ok(p["sar-supported"], p) then
    if not record(ctx, "sdp.a.fmtp.h264.sar-supported-invalid-value",
                  field_path) then return false end
  end

  -- packetization-mode: "When the value of packetization-mode is equal to
  -- 0 or packetization-mode is not present, the single NAL mode MUST be
  -- used." The rules below read the value as given; an out-of-range value
  -- is reported above and treated as absent here.
  local mode = int_in(0, 2)(p["packetization-mode"])
               and tonumber(p["packetization-mode"]) or nil

  -- "This parameter MUST NOT be present when packetization-mode is not
  -- present or the value of packetization-mode is equal to 0 or 1. This
  -- parameter MUST be present when the value of packetization-mode is
  -- equal to 2." (sprop-interleaving-depth; sprop-deint-buf-req has the
  -- same two sentences.)
  for _, key in ipairs({ "sprop-interleaving-depth", "sprop-deint-buf-req" }) do
    if mode == 2 then
      if p[key] == nil then
        if not record(ctx, "sdp.a.fmtp.h264." .. key .. "-required",
                      field_path) then return false end
      end
    elseif p[key] ~= nil then
      if not record(ctx, "sdp.a.fmtp.h264." .. key .. "-forbidden-in-mode",
                    field_path) then return false end
    end
  end

  -- "The parameter MUST NOT be present if the value of packetization-mode
  -- is equal to 0 or 1." (sprop-init-buf-time and sprop-max-don-diff)
  for _, key in ipairs({ "sprop-init-buf-time", "sprop-max-don-diff" }) do
    if (mode == 0 or mode == 1) and p[key] ~= nil then
      if not record(ctx, "sdp.a.fmtp.h264." .. key .. "-forbidden-in-mode",
                    field_path) then return false end
    end
  end

  -- "When in-band-parameter-sets is equal to 1, use-level-src-parameter-
  -- sets MUST NOT be present or MUST be equal to 0."
  if p["in-band-parameter-sets"] == "1"
     and p["use-level-src-parameter-sets"] ~= nil
     and p["use-level-src-parameter-sets"] ~= "0" then
    if not record(ctx,
        "sdp.a.fmtp.h264.use-level-src-parameter-sets-forbidden-with-in-band",
        field_path) then return false end
  end
  return true
end

-- ── Dispatch ─────────────────────────────────────────────────────────────────

-- Keyed by the lower-cased rtpmap encoding name. `media` and `clock_rate`
-- are the §8.2.1-style "MUST be" mappings; `fmtp` checks a decomposed
-- fmtp params list for that encoding.
local CODECS = {
  -- RFC 6184 §8.2.1: "The media name in the "m=" line of SDP MUST be
  -- video." / "The clock rate in the "a=rtpmap" line MUST be 90000."
  h264 = {
    media      = "video",
    media_id   = "sdp.a.rtpmap.h264.media-type-must-be-video",
    clock_rate = 90000,
    clock_id   = "sdp.a.rtpmap.h264.clock-rate-must-be-90000",
    fmtp       = check_h264_fmtp,
  },
}

local function check_codec_block(block, ctx)
  local codec_by_pt = {}
  for _, r in ipairs(accessors.attrs_get(block, "rtpmap")) do
    local codec = CODECS[string.lower(r.encoding)]
    if codec then
      local field_path = string.format("media[%d].attributes[rtpmap:pt=%d]",
                                       ctx.media_index or 0, r.payload_type)
      if block.media ~= codec.media then
        if not record(ctx, codec.media_id, field_path) then return false end
      end
      if r.clock_rate ~= codec.clock_rate then
        if not record(ctx, codec.clock_id, field_path) then return false end
      end
      if codec_by_pt[r.payload_type] == nil then
        codec_by_pt[r.payload_type] = codec
      end
    end
  end
  for _, f in ipairs(accessors.attrs_get(block, "fmtp")) do
    local codec = codec_by_pt[f.payload_type]
    if codec and f.params then
      local field_path = string.format("media[%d].attributes[fmtp:pt=%d]",
                                       ctx.media_index or 0, f.payload_type)
      if not codec.fmtp(f.params, ctx, field_path) then return false end
    end
  end
  return true
end

M.media_section_checks = { check_codec_block }

-- ── Decode helpers (parsed conveniences, never checks) ──────────────────────

-- RFC 6184 §8.1 profile-level-id: profile_idc, then "profile-iop, composed
-- of the values of constraint_set0_flag, constraint_set1_flag,
-- constraint_set2_flag, constraint_set3_flag, constraint_set4_flag,
-- constraint_set5_flag, and reserved_zero_2bits in bit-significance order,
-- starting from the most-significant bit", then level_idc. Level 1b: "If
-- the level_idc byte ... is equal to 11 and bit 4 of the profile-iop byte
-- ... is equal to 1 or if the level_idc byte ... is equal to 9". The
-- profile names follow ITU-T H.264 Annex A; a profile_idc the table does
-- not know leaves `profile` nil.
local CONSTRAINT_MASKS = { 128, 64, 32, 16, 8, 4 }  -- constraint_set0..5

local function h264_profile_name(idc, cs)
  if idc == 66  then return cs[1] and "Constrained Baseline" or "Baseline" end
  if idc == 77  then return "Main" end
  if idc == 88  then return "Extended" end
  if idc == 100 then
    if cs[4] and cs[5] then return "Constrained High" end
    return cs[4] and "Progressive High" or "High"
  end
  if idc == 110 then
    if cs[3] then return "High 10 Intra" end
    return cs[4] and "Progressive High 10" or "High 10"
  end
  if idc == 122 then return cs[3] and "High 4:2:2 Intra" or "High 4:2:2" end
  if idc == 244 then return cs[3] and "High 4:4:4 Intra" or "High 4:4:4 Predictive" end
  if idc == 44  then return "CAVLC 4:4:4 Intra" end
  if idc == 83  then return cs[5] and "Scalable Constrained Baseline" or "Scalable Baseline" end
  if idc == 86  then
    if cs[3] then return "Scalable High Intra" end
    return cs[5] and "Scalable Constrained High" or "Scalable High"
  end
  if idc == 118 then return "Multiview High" end
  if idc == 128 then return "Stereo High" end
  if idc == 138 then return "Multiview Depth High" end
  return nil
end

function M.decode_h264_profile_level_id(hex)
  if type(hex) ~= "string" or not HEX6:match(hex) then
    return nil, "profile-level-id must be six hexadecimal digits"
  end
  local profile_idc = tonumber(hex:sub(1, 2), 16)
  local profile_iop = tonumber(hex:sub(3, 4), 16)
  local level_idc   = tonumber(hex:sub(5, 6), 16)
  local cs = {}
  for i, mask in ipairs(CONSTRAINT_MASKS) do
    cs[i - 1] = bitops.band(profile_iop, mask) ~= 0
  end
  local level
  if level_idc == 9 or (level_idc == 11 and cs[3]) then
    level = "1b"
  elseif level_idc % 10 == 0 then
    level = string.format("%d", level_idc / 10)
  else
    level = string.format("%d.%d", (level_idc - level_idc % 10) / 10, level_idc % 10)
  end
  return {
    profile_idc          = profile_idc,
    profile_iop          = profile_iop,
    level_idc            = level_idc,
    constraint_set0_flag = cs[0],
    constraint_set1_flag = cs[1],
    constraint_set2_flag = cs[2],
    constraint_set3_flag = cs[3],
    constraint_set4_flag = cs[4],
    constraint_set5_flag = cs[5],
    profile              = h264_profile_name(profile_idc, cs),
    level                = level,
  }
end

return M
