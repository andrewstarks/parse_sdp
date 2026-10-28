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

-- Run a family's value-form rows over a lower-cased params view: each row
-- is { name, predicate } and records `<prefix><name>-invalid-value` when
-- the parameter is present and the predicate rejects it. `name` keeps the
-- RFC's spelling for the id; the lookup is case-insensitive.
local function check_value_forms(p, forms, prefix, ctx, field_path)
  for _, row in ipairs(forms) do
    local key, ok = row[1], row[2]
    local v = p[string.lower(key)]
    if v ~= nil and not ok(v) then
      if not record(ctx, prefix .. key .. "-invalid-value", field_path) then
        return false
      end
    end
  end
  return true
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
  if not check_value_forms(p, H264_VALUE_FORMS, "sdp.a.fmtp.h264.", ctx,
                           field_path) then return false end
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

-- ── H.265, RFC 7798 §7.1 ─────────────────────────────────────────────────────

local function hexn(n)
  local p = P(true)
  for _ = 1, n do p = p * HEX end
  return p * -1
end
local HEX8  = hexn(8)
local HEX12 = hexn(12)
local HEXS  = HEX ^ 1 * -1

-- include-dph: "a comma-separated list of hash types ... each hash type
-- provided as an unsigned integer value (0-255)"; "the value contains no
-- hash types" is a defined case, so an empty value passes.
local DPH_LIST = lpeg.Ct(lpeg.C(R("09") ^ 1) * (P(",") * lpeg.C(R("09") ^ 1)) ^ 0) * -1
local function dph_ok(v)
  if v == "" then return true end
  local t = type(v) == "string" and DPH_LIST:match(v)
  if not t then return false end
  for _, n in ipairs(t) do
    if tonumber(n) > 255 then return false end
  end
  return true
end

-- "The value of tx-mode MUST be equal to "SRST", "MRST" or "MRMT"."
local TX_MODES = { SRST = true, MRST = true, MRMT = true }
local function tx_mode_ok(v) return TX_MODES[v] == true end

-- Value forms, each quoted from RFC 7798 §7.1.
local H265_VALUE_FORMS = {
  -- "The value of profile-space MUST be in the range of 0 to 3, inclusive.
  -- The value of profile-id MUST be in the range of 0 to 31, inclusive."
  { "profile-space",                  int_in(0, 3) },
  { "profile-id",                     int_in(0, 31) },
  -- "The value of tier-flag MUST be in the range of 0 to 1, inclusive. The
  -- value of level-id MUST be in the range of 0 to 255, inclusive."
  { "tier-flag",                      int_in(0, 1) },
  { "level-id",                       int_in(0, 255) },
  -- "A base16 [RFC4648] (hexadecimal) representation of six bytes of data"
  { "interop-constraints",            matches(HEX12) },
  -- "A base16 [RFC4648] representation of four bytes of data."
  { "profile-compatibility-indicator", matches(HEX8) },
  -- "MUST be in the range of 0 to 6, inclusive." (both sub-layer ids)
  { "sprop-sub-layer-id",             int_in(0, 6) },
  { "recv-sub-layer-id",              int_in(0, 6) },
  -- "The value of max-recv-level-id MUST be in the range of 0 to 255"
  { "max-recv-level-id",              int_in(0, 255) },
  { "tx-mode",                        tx_mode_ok },
  -- "a comma-separated (',') list of base64 [RFC4648] representations"
  { "sprop-vps",                      matches(B64_LIST) },
  { "sprop-sps",                      matches(B64_LIST) },
  { "sprop-pps",                      matches(B64_LIST) },
  { "sprop-sei",                      matches(B64_LIST) },
  -- "The value of max-lsr is an integer" (and max-lps, max-cpb, max-br,
  -- max-tr, max-tc, max-fps). The level-relative ranges need the H.265
  -- level tables and are not compared (decision parse_sdp-aif).
  { "max-lsr",                        is_int },
  { "max-lps",                        is_int },
  { "max-cpb",                        is_int },
  { "max-br",                         is_int },
  { "max-tr",                         is_int },
  { "max-tc",                         is_int },
  { "max-fps",                        is_int },
  -- "The value of max-dpb MUST be in the range of 1 to 16, inclusive."
  { "max-dpb",                        int_in(1, 16) },
  -- "MUST be an integer in the range of 0 to 32767, inclusive." (both)
  { "sprop-max-don-diff",             int_in(0, 32767) },
  { "sprop-depack-buf-nalus",         int_in(0, 32767) },
  -- "MUST be an integer in the range of 0 to 4294967295, inclusive."
  { "sprop-depack-buf-bytes",         int_in(0, 4294967295) },
  -- "MUST be an integer in the range of 1 to 4294967295, inclusive."
  { "depack-buf-cap",                 int_in(1, 4294967295) },
  -- "MUST be an integer in the range of 0 to 3, inclusive."
  { "sprop-segmentation-id",          int_in(0, 3) },
  -- "A base16 [RFC4648] representation of the syntax element
  -- min_spatial_segmentation_idc"
  { "sprop-spatial-segmentation-idc", matches(HEXS) },
  { "include-dph",                    dph_ok },
}

local function check_h265_fmtp(params, ctx, field_path)
  local p = params_ci(params)
  -- dec-parallel-cap's ABNF puts ';' inside its braces, which the RFC 8866
  -- §6.15 key=value split cannot carry: the entries it breaks into would
  -- be checked as parameters of their own. A line that carries it is not
  -- checked (GUIDE.md limitation).
  if p["dec-parallel-cap"] ~= nil then return true end
  if not check_value_forms(p, H265_VALUE_FORMS, "sdp.a.fmtp.h265.", ctx,
                           field_path) then return false end

  -- "When sprop-max-don-diff is present and greater than 0, this
  -- parameter MUST be present and the value MUST be greater than 0."
  -- (sprop-depack-buf-nalus and sprop-depack-buf-bytes)
  local don = int_in(0, 32767)(p["sprop-max-don-diff"])
              and tonumber(p["sprop-max-don-diff"]) or 0
  if don > 0 then
    for _, key in ipairs({ "sprop-depack-buf-nalus", "sprop-depack-buf-bytes" }) do
      local v = p[key]
      if v == nil or (is_int(v) and tonumber(v) == 0) then
        if not record(ctx, "sdp.a.fmtp.h265." .. key
                      .. "-required-when-max-don-diff", field_path) then
          return false
        end
      end
    end
  end

  -- "max-recv-level-id MUST NOT be present when the highest level the
  -- receiver supports is not higher than the default level." The highest
  -- level "is equal to the value of max-recv-level-id divided by 30"; the
  -- default level is level-id, "93 (i.e., level 3.1)" when absent.
  if int_in(0, 255)(p["max-recv-level-id"]) then
    local level_id = int_in(0, 255)(p["level-id"]) and tonumber(p["level-id"]) or 93
    if tonumber(p["max-recv-level-id"]) <= level_id then
      if not record(ctx,
          "sdp.a.fmtp.h265.max-recv-level-id-not-higher-than-level-id",
          field_path) then return false end
    end
  end
  return true
end

-- ── AAC: mpeg4-generic (RFC 3640 §4.1) and MP4A-LATM (RFC 6416 §7.3) ───────

-- RFC 3640 §4.1 config: "A hexadecimal representation of an octet
-- string" (two digits per octet; "up to 7 zero-valued padding bits shall
-- follow the configuration data" to reach octet alignment), or "a quoted
-- empty hexadecimal octet string, as follows: config=\"\"". RFC 6416 §7.3
-- config and MPS-asc: the same octet-string form.
local HEX_OCTETS = (HEX * HEX) ^ 1 * -1
local hex_octets_ok = matches(HEX_OCTETS)
local function config_ok(v) return v == '""' or hex_octets_ok(v) end

-- Value forms, each quoted from RFC 3640 §4.1.
local MPEG4_GENERIC_VALUE_FORMS = {
  -- "The integer value that indicates the type of MPEG-4 stream"
  { "streamType",              is_int },
  -- "A decimal representation of the MPEG-4 Profile Level indication."
  { "profile-level-id",        is_int },
  { "config",                  config_ok },
  -- "The decimal value from Table 8 in ISO/IEC 14496-1"
  { "objectType",              is_int },
  -- "The constant size in octets of each Access Unit"
  { "constantSize",            is_int },
  -- "The constant duration of each Access Unit ... measured with the same
  -- units as the RTP time stamp."
  { "constantDuration",        is_int },
  -- "The decimal representation of the maximum displacement in time"
  { "maxDisplacement",         is_int },
  -- "The decimal representation in number of octets"
  { "de-interleaveBufferSize", is_int },
  -- "The number of bits on which the ... field is encoded" (five lengths)
  { "sizeLength",              is_int },
  { "indexLength",             is_int },
  { "indexDeltaLength",        is_int },
  { "CTSDeltaLength",          is_int },
  { "DTSDeltaLength",          is_int },
  -- "A decimal value of zero or one"
  { "randomAccessIndication",  int_in(0, 1) },
  { "streamStateIndication",   is_int },
  { "auxiliaryDataSizeLength", is_int },
}

-- "Required parameters: ... streamType ... profile-level-id ... config
-- ... mode"
local MPEG4_GENERIC_REQUIRED = { "streamType", "profile-level-id", "config", "mode" }

local function check_mpeg4_generic_fmtp(params, ctx, field_path, block)
  local p = params_ci(params)
  for _, key in ipairs(MPEG4_GENERIC_REQUIRED) do
    if p[string.lower(key)] == nil then
      if not record(ctx, "sdp.a.fmtp.mpeg4-generic." .. key .. "-required",
                    field_path) then return false end
    end
  end
  if not check_value_forms(p, MPEG4_GENERIC_VALUE_FORMS,
                           "sdp.a.fmtp.mpeg4-generic.", ctx, field_path) then
    return false
  end

  -- "The sizeLength and the constantSize parameters MUST NOT be
  -- simultaneously present."
  if p["sizelength"] ~= nil and p["constantsize"] ~= nil then
    if not record(ctx, "sdp.a.fmtp.mpeg4-generic.constantSize-sizeLength-exclusive",
                  field_path) then return false end
  end

  -- §3.3.5 (AAC-lbr) and §3.3.6 (AAC-hbr): "In addition to the required
  -- MIME format parameters, the following parameters MUST be present:
  -- sizeLength, indexLength, and indexDeltaLength."
  local mode = type(p["mode"]) == "string" and string.upper(p["mode"]) or ""
  if mode == "AAC-HBR" or mode == "AAC-LBR" then
    if p["sizelength"] == nil or p["indexlength"] == nil
       or p["indexdeltalength"] == nil then
      if not record(ctx,
          "sdp.a.fmtp.mpeg4-generic.aac-mode-requires-size-and-index-lengths",
          field_path) then return false end
    end
  end

  -- streamStateIndication: "SHALL NOT be present for MPEG-4 audio and
  -- MPEG-4 video streams." (§4.1 maps those to m=audio and m=video)
  if p["streamstateindication"] ~= nil
     and (block.media == "audio" or block.media == "video") then
    if not record(ctx, "sdp.a.fmtp.mpeg4-generic.streamStateIndication-forbidden",
                  field_path) then return false end
  end
  return true
end

-- Value forms, each quoted from RFC 6416 §7.3.
local MP4A_LATM_VALUE_FORMS = {
  -- "a decimal representation of MPEG-4 Audio Profile Level indication"
  { "profile-level-id",     is_int },
  -- "a decimal representation of the MPEG Surround Profile Level"
  { "MPS-profile-level-id", is_int },
  -- "a decimal representation of the MPEG-4 Audio Object Type"
  { "object",               is_int },
  -- "a boolean parameter ... A 0 indicates ... a 1 indicates"
  { "cpresent",             int_in(0, 1) },
  -- "a hexadecimal representation of an octet string"
  { "config",               hex_octets_ok },
  -- "The same mapping rules as for the "config" parameter apply."
  { "MPS-asc",              hex_octets_ok },
  -- "a boolean parameter ... set to 0 ... set to 1"
  { "SBR-enabled",          int_in(0, 1) },
}

local function check_mp4a_latm_fmtp(params, ctx, field_path)
  local p = params_ci(params)
  if not check_value_forms(p, MP4A_LATM_VALUE_FORMS, "sdp.a.fmtp.mp4a-latm.",
                           ctx, field_path) then return false end
  -- "A 0 indicates the configuration data has not been multiplexed into
  -- an RTP payload, and in that case, the "config" parameter MUST be
  -- present"
  if p["cpresent"] == "0" and p["config"] == nil then
    if not record(ctx, "sdp.a.fmtp.mp4a-latm.config-required-when-cpresent-0",
                  field_path) then return false end
  end
  return true
end

-- ── Dispatch ─────────────────────────────────────────────────────────────────

-- Keyed by the lower-cased rtpmap encoding name. `media` is the set of
-- m= media types the registration maps the encoding to and `clock_rate`
-- the rate the registration fixes (nil when it fixes none); `fmtp` checks
-- a decomposed fmtp params list for that encoding.
local CODECS = {
  -- RFC 6184 §8.2.1: "The media name in the "m=" line of SDP MUST be
  -- video." / "The clock rate in the "a=rtpmap" line MUST be 90000."
  h264 = {
    media      = { video = true },
    media_id   = "sdp.a.rtpmap.h264.media-type-must-be-video",
    clock_rate = 90000,
    clock_id   = "sdp.a.rtpmap.h264.clock-rate-must-be-90000",
    fmtp       = check_h264_fmtp,
  },
  -- RFC 7798 §7.2.1: "The media name in the "m=" line of SDP MUST be
  -- video." / "The clock rate in the "a=rtpmap" line MUST be 90000."
  h265 = {
    media      = { video = true },
    media_id   = "sdp.a.rtpmap.h265.media-type-must-be-video",
    clock_rate = 90000,
    clock_id   = "sdp.a.rtpmap.h265.clock-rate-must-be-90000",
    fmtp       = check_h265_fmtp,
  },
  -- RFC 3640 §4.1: "video" MUST be used for MPEG-4 Visual streams,
  -- "audio" ... for MPEG-4 Audio streams, "application" ... for MPEG-4
  -- Systems streams. The clock rate is a SHOULD (§3.1), so none is fixed.
  ["mpeg4-generic"] = {
    media    = { video = true, audio = true, application = true },
    media_id = "sdp.a.rtpmap.mpeg4-generic.media-type-invalid-value",
    fmtp     = check_mpeg4_generic_fmtp,
  },
  -- RFC 6416 §7.4: "The media type (audio) goes in SDP "m=" as the media
  -- name." §7.3 rate: "The default value is 90000. Other rates MAY be
  -- indicated", so none is fixed.
  ["mp4a-latm"] = {
    media    = { audio = true },
    media_id = "sdp.a.rtpmap.mp4a-latm.media-type-must-be-audio",
    fmtp     = check_mp4a_latm_fmtp,
  },
  -- RFC 2250 §2: the RTP packet carries a "32 bit 90K Hz timestamp
  -- representing the target transmission time"; RFC 3551 Table 5 registers
  -- MP2T with clock rate 90,000 and media type "AV" (audio or video), so
  -- the media type is not checked. RFC 3555 §4.2.9: "Required parameters:
  -- None. Optional parameters: None.", so no fmtp parameter is defined.
  mp2t = {
    clock_rate = 90000,
    clock_id   = "sdp.a.rtpmap.mp2t.clock-rate-must-be-90000",
    fmtp       = function() return true end,
  },
}

local function check_codec_block(block, ctx)
  local codec_by_pt = {}
  for _, r in ipairs(accessors.attrs_get(block, "rtpmap")) do
    local codec = CODECS[string.lower(r.encoding)]
    if codec then
      local field_path = string.format("media[%d].attributes[rtpmap:pt=%d]",
                                       ctx.media_index or 0, r.payload_type)
      if codec.media_id and not codec.media[block.media] then
        if not record(ctx, codec.media_id, field_path) then return false end
      end
      if codec.clock_rate and r.clock_rate ~= codec.clock_rate then
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
      if not codec.fmtp(f.params, ctx, field_path, block) then return false end
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

-- RFC 7798 §7.1: profile-space (0 when absent), profile-id ("a value of 1
-- (i.e., the Main profile) MUST be inferred" when absent), tier-flag (0),
-- level-id ("93 (i.e., level 3.1)"); max-recv-level-id "divided by 30"
-- gives the level number, so level-id does too. interop-constraints is
-- "six bytes of data, consisting of progressive_source_flag,
-- interlaced_source_flag, non_packed_constraint_flag,
-- frame_only_constraint_flag, and reserved_zero_44bits", inferred 1, 0,
-- 1, 1 when absent. profile-compatibility-indicator: "bit j of profile-
-- compatibility-indicator = general_profile_compatibility_flag[j]" for
-- j = 0..31, read most-significant bit first as the HEVC syntax writes
-- the flags, so Main (j = 1 and 2) is 60000000. The profile names are the
-- ITU-T H.265 Annex A / G / H / I profile groups that general_profile_idc
-- selects; the sub-profiles that the constraint bits distinguish within
-- a group are not named.
local H265_PROFILE_NAMES = {
  [1]  = "Main",
  [2]  = "Main 10",
  [3]  = "Main Still Picture",
  [4]  = "Format range extensions",
  [5]  = "High throughput",
  [6]  = "Multiview Main",
  [7]  = "Scalable Main",
  [8]  = "3D Main",
  [9]  = "Screen content coding extensions",
  [10] = "Scalable format range extensions",
  [11] = "High throughput screen content coding extensions",
}

local function h265_int(p, key, lo, hi, default)
  local v = p[key]
  if v == nil then return default end
  if not int_in(lo, hi)(v) then
    return nil, "H265 fmtp '" .. key .. "' is not an integer from "
      .. lo .. " to " .. hi
  end
  return tonumber(v)
end

function M.decode_h265_profile(params)
  if type(params) ~= "table" then
    return nil, "expected an fmtp params list"
  end
  local p = params_ci(params)
  local profile_space, e1 = h265_int(p, "profile-space", 0, 3, 0)
  local profile_id, e2    = h265_int(p, "profile-id", 0, 31, 1)
  local tier_flag, e3     = h265_int(p, "tier-flag", 0, 1, 0)
  local level_id, e4      = h265_int(p, "level-id", 0, 255, 93)
  local err = e1 or e2 or e3 or e4
  if err then return nil, err end

  local interop = p["interop-constraints"]
  local flags
  if interop == nil then
    flags = { 1, 0, 1, 1 }
  elseif HEX12:match(interop) then
    local top = tonumber(interop:sub(1, 1), 16)
    flags = {}
    for i, mask in ipairs({ 8, 4, 2, 1 }) do
      flags[i] = bitops.band(top, mask) ~= 0 and 1 or 0
    end
  else
    return nil, "H265 fmtp 'interop-constraints' is not twelve hexadecimal digits"
  end

  local compat = p["profile-compatibility-indicator"]
  local compat_flags = {}
  if compat == nil then
    for j = 0, 31 do compat_flags[j] = (j == profile_id) end
  elseif HEX8:match(compat) then
    for j = 0, 31 do
      local digit = tonumber(compat:sub(1 + (j - j % 4) / 4, 1 + (j - j % 4) / 4), 16)
      compat_flags[j] = bitops.band(digit, 2 ^ (3 - j % 4)) ~= 0
    end
  else
    return nil, "H265 fmtp 'profile-compatibility-indicator' is not eight hexadecimal digits"
  end

  local level
  if level_id % 30 == 0 then
    level = string.format("%d", level_id / 30)
  else
    level = string.format("%.1f", level_id / 30)
  end
  return {
    profile_space               = profile_space,
    profile_id                  = profile_id,
    tier_flag                   = tier_flag,
    level_id                    = level_id,
    tier                        = tier_flag == 1 and "High" or "Main",
    level                       = level,
    profile                     = H265_PROFILE_NAMES[profile_id],
    progressive_source_flag     = flags[1] == 1,
    interlaced_source_flag      = flags[2] == 1,
    non_packed_constraint_flag  = flags[3] == 1,
    frame_only_constraint_flag  = flags[4] == 1,
    profile_compatibility_flags = compat_flags,
  }
end

return M
