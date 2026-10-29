---@diagnostic disable
-- Base-tier checks from the IETF RTP payload-format registrations
-- (parse_sdp/grammar/codecs.lua; decision parse_sdp-59w). Every test cites
-- the clause it exercises. The checks run at every tier through
-- composition; the ST 2110 tier is exercised once per family to prove it.

local base    = require("parse_sdp.grammar.base")
local st2110  = require("parse_sdp.grammar.st2110")
local codecs  = require("parse_sdp.grammar.codecs")
local support = require("spec.support")

local finding_for = support.finding_for

local function sdp_with(media_lines)
  local out = {
    "v=0",
    "o=- 1 1 IN IP4 192.0.2.1",
    "s=Test",
    "c=IN IP4 233.252.0.1/127",
    "t=0 0",
  }
  for _, l in ipairs(media_lines) do out[#out + 1] = l end
  return table.concat(out, "\r\n") .. "\r\n"
end

local function match_all(text)
  return base.match(text, { fail_on_first = false })
end

local function ids_of(ctx)
  local out = {}
  for _, f in ipairs(ctx.findings) do out[#out + 1] = f.id end
  table.sort(out)
  return out
end

describe("codecs — H.264 rtpmap mapping (RFC 6184 §8.2.1)", function()

  -- SPEC: RFC 6184 §8.2.1 "The media name in the "m=" line of SDP MUST be
  -- video." / "The clock rate in the "a=rtpmap" line MUST be 90000."
  it("accepts m=video with H264/90000", function()
    local doc, ctx = match_all(sdp_with({
      "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000" }))
    assert.is_truthy(doc)
    assert.same({}, ctx.findings)
  end)

  it("rejects H264 on m=audio", function()
    local _, ctx = match_all(sdp_with({
      "m=audio 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000" }))
    local f = finding_for(ctx, "sdp.a.rtpmap.h264.media-type-must-be-video")
    assert.is_not_nil(f)
    assert.equal("media[0].attributes[rtpmap:pt=96]", f.field_path)
    assert.equal("RFC 6184 §8.2.1", f.spec_ref)
  end)

  it("rejects an H264 clock rate other than 90000", function()
    local _, ctx = match_all(sdp_with({
      "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/48000" }))
    assert.is_not_nil(finding_for(ctx, "sdp.a.rtpmap.h264.clock-rate-must-be-90000"))
  end)

  -- SPEC: RFC 8866 §6.6 (RFC 4855 §3): encoding names are case-insensitive.
  it("matches the encoding name case-insensitively (h264/48000)", function()
    local _, ctx = match_all(sdp_with({
      "m=video 49170 RTP/AVP 96", "a=rtpmap:96 h264/48000" }))
    assert.is_not_nil(finding_for(ctx, "sdp.a.rtpmap.h264.clock-rate-must-be-90000"))
  end)

  -- NOT-SPEC: library — the checks compose into every tier.
  it("fires at the ST 2110 tier too", function()
    local _, ctx = st2110.match(sdp_with({
      "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/48000",
      support.TIMING_TS_REFCLK, support.TIMING_MEDIACLK }), { fail_on_first = false })
    assert.is_not_nil(finding_for(ctx, "sdp.a.rtpmap.h264.clock-rate-must-be-90000"))
  end)

  -- NOT-SPEC: library — the default fail_on_first path fails the match.
  it("fails the match under fail_on_first", function()
    local doc = base.match(sdp_with({
      "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/48000" }))
    assert.is_nil(doc)
  end)
end)

describe("codecs — H.264 fmtp value forms (RFC 6184 §8.1)", function()

  local function h264_fmtp(body)
    return sdp_with({
      "m=video 49170 RTP/AVP 96",
      "a=rtpmap:96 H264/90000",
      "a=fmtp:96 " .. body,
    })
  end

  -- Each row: parameter, a conforming value, a non-conforming value, with
  -- the §8.1 clause the pair exercises.
  local FORMS = {
    -- "A base16 [7] (hexadecimal) representation of the following three bytes"
    { "profile-level-id", "42e01e", "42e01" },
    { "profile-level-id", "4D401F", "42e01eff" },
    -- "a base16 (hexadecimal) representation of the two bytes after the
    -- syntax element profile_idc"
    { "max-recv-level", "e033", "e0" },
    -- "The value of max-mbps is an integer" (and the five others)
    { "max-mbps",  "108000", "108k" },
    { "max-smbps", "108000", "-1" },
    { "max-fs",    "3600",   "3.6e3" },
    { "max-cpb",   "4000",   "" },
    { "max-dpb",   "8100",   "8100 " },
    { "max-br",    "20000",  "20000kbps" },
    -- "The value of redundant-pic-cap MUST be either 0 or 1."
    { "redundant-pic-cap", "1", "2" },
    -- "a comma-separated (',') list of base64 [7] representations"
    { "sprop-parameter-sets", "Z0IAHpZSBHI=,aM4BqDXI", "Z0IAHpZSBHI=,," },
    { "sprop-parameter-sets", "Z0IAHpZSBHI", "Z0IAH!pZ" },
    -- "PLId:PSL ... Each pair of PLId:PSLs is also separated by a colon."
    { "sprop-level-parameter-sets", "42e00b:Z0IAHpZSBHI=,aM4BqDXI:42e00d:Z0IADQ==", "42e00b" },
    { "sprop-level-parameter-sets", "42e00b:Z0IAHpZSBHI=", "zz00b:Z0IAHpZSBHI=" },
    -- "The value MAY be equal to either 0 or 1."
    { "use-level-src-parameter-sets", "0", "3" },
    { "in-band-parameter-sets",       "1", "true" },
    { "level-asymmetry-allowed",      "1", "-0" },
    -- "MUST be an integer in the range of 0 to 2, inclusive."
    { "packetization-mode", "2", "3" },
    -- "MUST be an integer in the range of 0 to 32767, inclusive."
    { "sprop-max-don-diff", "32767", "32768" },
    -- "MUST be an integer in the range of 0 to 4294967295, inclusive."
    { "deint-buf-cap",      "4294967295", "4294967296" },
    { "max-rcmd-nalu-size", "1400", "1400.0" },
    { "sar-understood", "16", "sixteen" },
  }
  for _, row in ipairs(FORMS) do
    local key, good, bad = row[1], row[2], row[3]
    local id = "sdp.a.fmtp.h264." .. key .. "-invalid-value"
    it(("accepts %s=%s"):format(key, good), function()
      local doc, ctx = match_all(h264_fmtp(key .. "=" .. good))
      assert.is_truthy(doc)
      assert.is_nil(finding_for(ctx, id))
    end)
    it(("rejects %s=%s [%s]"):format(key, bad, id), function()
      local _, ctx = match_all(h264_fmtp(key .. "=" .. bad))
      local f = finding_for(ctx, id)
      assert.is_not_nil(f)
      assert.equal("media[0].attributes[fmtp:pt=96]", f.field_path)
      assert.equal("RFC 6184 §8.1", f.spec_ref)
    end)
  end

  -- The mode-2 forms are tested with packetization-mode=2 and the other
  -- mode-2 parameters present, so the presence rules below do not also
  -- fire.
  local MODE2 = {
    ["sprop-interleaving-depth"] = "packetization-mode=2;sprop-deint-buf-req=1;",
    ["sprop-deint-buf-req"]      = "packetization-mode=2;sprop-interleaving-depth=1;",
    ["sprop-init-buf-time"]      =
      "packetization-mode=2;sprop-interleaving-depth=1;sprop-deint-buf-req=1;",
  }
  for _, row in ipairs({
    { "sprop-interleaving-depth", "32767", "32768" },
    { "sprop-deint-buf-req",      "0",     "4294967296" },
    { "sprop-init-buf-time",      "4294967295", "x" },
  }) do
    local key, good, bad = row[1], row[2], row[3]
    local id = "sdp.a.fmtp.h264." .. key .. "-invalid-value"
    it(("accepts %s=%s in mode 2"):format(key, good), function()
      local _, ctx = match_all(h264_fmtp(MODE2[key] .. key .. "=" .. good))
      assert.is_nil(finding_for(ctx, id))
    end)
    it(("rejects %s=%s in mode 2 [%s]"):format(key, bad, id), function()
      local _, ctx = match_all(h264_fmtp(MODE2[key] .. key .. "=" .. bad))
      assert.is_not_nil(finding_for(ctx, id))
    end)
  end

  -- SPEC: RFC 6184 §8.1 sar-supported "an integer in the range of 1 to
  -- sar-understood, inclusive, equal to 255" and "When sar-understood is
  -- not present, the value MUST be inferred to be equal to 13."
  describe("sar-supported against sar-understood", function()
    local ID = "sdp.a.fmtp.h264.sar-supported-invalid-value"
    it("accepts 13 with sar-understood absent", function()
      local _, ctx = match_all(h264_fmtp("sar-supported=13"))
      assert.is_nil(finding_for(ctx, ID))
    end)
    it("rejects 14 with sar-understood absent (inferred 13)", function()
      local _, ctx = match_all(h264_fmtp("sar-supported=14"))
      assert.is_not_nil(finding_for(ctx, ID))
    end)
    it("accepts 16 with sar-understood=16", function()
      local _, ctx = match_all(h264_fmtp("sar-understood=16;sar-supported=16"))
      assert.is_nil(finding_for(ctx, ID))
    end)
    it("accepts 255 regardless of sar-understood", function()
      local _, ctx = match_all(h264_fmtp("sar-understood=13;sar-supported=255"))
      assert.is_nil(finding_for(ctx, ID))
    end)
    it("rejects 0", function()
      local _, ctx = match_all(h264_fmtp("sar-supported=0"))
      assert.is_not_nil(finding_for(ctx, ID))
    end)
  end)

  -- SPEC: RFC 8866 §6.6 (RFC 4855 §3): parameter names are case-insensitive.
  it("matches parameter names case-insensitively", function()
    local _, ctx = match_all(h264_fmtp("Packetization-Mode=3"))
    assert.is_not_nil(finding_for(ctx, "sdp.a.fmtp.h264.packetization-mode-invalid-value"))
  end)

  -- NOT-SPEC: library — a bare flag is not a value.
  it("rejects a known parameter given as a bare flag", function()
    local _, ctx = match_all(h264_fmtp("packetization-mode"))
    assert.is_not_nil(finding_for(ctx, "sdp.a.fmtp.h264.packetization-mode-invalid-value"))
  end)

  -- NOT-SPEC: library — unknown parameters pass through.
  it("ignores parameters RFC 6184 does not define", function()
    local doc, ctx = match_all(h264_fmtp("packetization-mode=1;x-vendor=1"))
    assert.is_truthy(doc)
    assert.same({}, ctx.findings)
  end)

  -- NOT-SPEC: library — the fmtp of a payload type bound to another
  -- encoding, or to none, gets no H.264 checks.
  it("does not check an fmtp whose payload type is not an H264 rtpmap", function()
    local doc, ctx = match_all(sdp_with({
      "m=video 49170 RTP/AVP 96 97",
      "a=rtpmap:96 H264/90000",
      "a=rtpmap:97 VP8/90000",
      "a=fmtp:97 packetization-mode=9",
    }))
    assert.is_truthy(doc)
    assert.same({}, ctx.findings)
  end)

  -- NOT-SPEC: library — a raw (non k=v) fmtp body is not decomposed, so
  -- there is nothing to check.
  it("skips an fmtp that fell back to the raw form", function()
    local doc, ctx = match_all(h264_fmtp("0-15"))
    assert.is_truthy(doc)
    assert.same({}, ctx.findings)
  end)

  -- NOT-SPEC: library — every error-severity finding is collected.
  it("reports every violation on one fmtp line", function()
    local _, ctx = match_all(h264_fmtp(
      "profile-level-id=zz;packetization-mode=5;max-fs=big"))
    assert.same({
      "sdp.a.fmtp.h264.max-fs-invalid-value",
      "sdp.a.fmtp.h264.packetization-mode-invalid-value",
      "sdp.a.fmtp.h264.profile-level-id-invalid-value",
    }, ids_of(ctx))
  end)
end)

describe("codecs — H.264 packetization-mode presence rules (RFC 6184 §8.1)", function()

  local function h264_fmtp(body)
    return sdp_with({
      "m=video 49170 RTP/AVP 96",
      "a=rtpmap:96 H264/90000",
      "a=fmtp:96 " .. body,
    })
  end

  -- SPEC: "This parameter MUST NOT be present when packetization-mode is
  -- not present or the value of packetization-mode is equal to 0 or 1.
  -- This parameter MUST be present when the value of packetization-mode is
  -- equal to 2." (sprop-interleaving-depth, sprop-deint-buf-req)
  for _, key in ipairs({ "sprop-interleaving-depth", "sprop-deint-buf-req" }) do
    local forbidden = "sdp.a.fmtp.h264." .. key .. "-forbidden-in-mode"
    local required  = "sdp.a.fmtp.h264." .. key .. "-required"
    for _, prefix in ipairs({ "", "packetization-mode=0;", "packetization-mode=1;" }) do
      it(("rejects %s with %q"):format(key, prefix), function()
        local _, ctx = match_all(h264_fmtp(prefix .. key .. "=0"))
        assert.is_not_nil(finding_for(ctx, forbidden))
      end)
    end
    it(("accepts %s in mode 2"):format(key), function()
      local _, ctx = match_all(h264_fmtp(
        "packetization-mode=2;sprop-interleaving-depth=1;sprop-deint-buf-req=1"))
      assert.is_nil(finding_for(ctx, forbidden))
      assert.is_nil(finding_for(ctx, required))
    end)
    it(("requires %s in mode 2"):format(key), function()
      local _, ctx = match_all(h264_fmtp("packetization-mode=2"))
      local f = finding_for(ctx, required)
      assert.is_not_nil(f)
      assert.equal("MISSING_FIELD", f.code)
    end)
  end

  -- SPEC: "The parameter MUST NOT be present if the value of
  -- packetization-mode is equal to 0 or 1." (sprop-init-buf-time,
  -- sprop-max-don-diff). The clause names the values 0 and 1 only, so an
  -- absent packetization-mode does not fire it.
  for _, key in ipairs({ "sprop-init-buf-time", "sprop-max-don-diff" }) do
    local forbidden = "sdp.a.fmtp.h264." .. key .. "-forbidden-in-mode"
    for _, mode in ipairs({ "0", "1" }) do
      it(("rejects %s in mode %s"):format(key, mode), function()
        local _, ctx = match_all(h264_fmtp(
          "packetization-mode=" .. mode .. ";" .. key .. "=0"))
        assert.is_not_nil(finding_for(ctx, forbidden))
      end)
    end
    it(("accepts %s in mode 2"):format(key), function()
      local _, ctx = match_all(h264_fmtp(
        "packetization-mode=2;sprop-interleaving-depth=1;sprop-deint-buf-req=1;"
        .. key .. "=0"))
      assert.is_nil(finding_for(ctx, forbidden))
    end)
    it(("accepts %s with packetization-mode absent"):format(key), function()
      local _, ctx = match_all(h264_fmtp(key .. "=0"))
      assert.is_nil(finding_for(ctx, forbidden))
    end)
  end

  -- NOT-SPEC: library — an out-of-range mode is reported once and treated
  -- as absent for the presence rules.
  it("treats an invalid packetization-mode as absent for the presence rules", function()
    local _, ctx = match_all(h264_fmtp("packetization-mode=7;sprop-max-don-diff=0"))
    assert.same({ "sdp.a.fmtp.h264.packetization-mode-invalid-value" }, ids_of(ctx))
  end)

  -- SPEC: "When in-band-parameter-sets is equal to 1, use-level-src-
  -- parameter-sets MUST NOT be present or MUST be equal to 0."
  describe("in-band-parameter-sets and use-level-src-parameter-sets", function()
    local ID = "sdp.a.fmtp.h264.use-level-src-parameter-sets-forbidden-with-in-band"
    it("rejects use-level-src-parameter-sets=1 with in-band-parameter-sets=1", function()
      local _, ctx = match_all(h264_fmtp(
        "in-band-parameter-sets=1;use-level-src-parameter-sets=1"))
      assert.is_not_nil(finding_for(ctx, ID))
    end)
    it("accepts use-level-src-parameter-sets=0 with in-band-parameter-sets=1", function()
      local _, ctx = match_all(h264_fmtp(
        "in-band-parameter-sets=1;use-level-src-parameter-sets=0"))
      assert.is_nil(finding_for(ctx, ID))
    end)
    it("accepts use-level-src-parameter-sets=1 with in-band-parameter-sets=0", function()
      local _, ctx = match_all(h264_fmtp(
        "in-band-parameter-sets=0;use-level-src-parameter-sets=1"))
      assert.is_nil(finding_for(ctx, ID))
    end)
    -- NOT-SPEC: library — the values are compared as numbers once their
    -- 0/1 form passed, so a leading zero does not change the verdict.
    it("compares the values as numbers (00 is 0, 01 is 1)", function()
      local _, ctx = match_all(h264_fmtp(
        "in-band-parameter-sets=1;use-level-src-parameter-sets=00"))
      assert.is_nil(finding_for(ctx, ID))
      _, ctx = match_all(h264_fmtp(
        "in-band-parameter-sets=01;use-level-src-parameter-sets=1"))
      assert.is_not_nil(finding_for(ctx, ID))
    end)
  end)
end)

describe("codecs — decode_h264_profile_level_id (RFC 6184 §8.1)", function()
  local decode = codecs.decode_h264_profile_level_id

  -- SPEC: profile_idc, profile-iop (constraint_set0..5 from the MSB), level_idc.
  it("decodes 42e01e as Constrained Baseline level 3", function()
    local d = decode("42e01e")
    assert.equal(66, d.profile_idc)
    assert.equal(0xe0, d.profile_iop)
    assert.equal(30, d.level_idc)
    assert.is_true(d.constraint_set0_flag)
    assert.is_true(d.constraint_set1_flag)
    assert.is_true(d.constraint_set2_flag)
    assert.is_false(d.constraint_set3_flag)
    assert.equal("Constrained Baseline", d.profile)
    assert.equal("3", d.level)
  end)

  it("decodes 640028 as High level 4", function()
    local d = decode("640028")
    assert.equal("High", d.profile)
    assert.equal("4", d.level)
  end)

  it("decodes 4d401f as Main level 3.1", function()
    local d = decode("4D401F")
    assert.equal("Main", d.profile)
    assert.equal("3.1", d.level)
  end)

  -- SPEC: "when profile_idc is equal to 66, 77, or 88 (the Baseline,
  -- Main, or Extended profile), level_idc is equal to 11, and bit 4
  -- (constraint_set3_flag) of the profile-iop byte is equal to 1, the
  -- default level is Level 1b."
  it("decodes level_idc 11 with constraint_set3_flag as level 1b for Baseline, Main and Extended", function()
    for _, hex in ipairs({ "42100b", "4d100b", "58100b" }) do
      assert.equal("1b", decode(hex).level, hex)
    end
  end)
  it("decodes level_idc 11 without constraint_set3_flag as level 1.1", function()
    assert.equal("1.1", decode("42000b").level)
  end)
  it("decodes level_idc 11 with constraint_set3_flag as level 1.1 for High", function()
    assert.equal("1.1", decode("64100b").level)
    assert.equal("High", decode("64100b").profile)
  end)
  it("decodes level_idc 9 as level 1b", function()
    assert.equal("1b", decode("640009").level)
  end)

  -- NOT-SPEC: library — an unknown profile_idc leaves `profile` nil.
  it("leaves profile nil for an unknown profile_idc", function()
    local d = decode("ff0028")
    assert.is_nil(d.profile)
    assert.equal(255, d.profile_idc)
  end)

  -- NOT-SPEC: library — errors are values.
  it("returns nil, err for a value that is not six hex digits", function()
    local d, err = decode("42e0")
    assert.is_nil(d)
    assert.is_string(err)
    assert.is_nil(decode(nil))
  end)
end)

describe("codecs — H.265 rtpmap mapping (RFC 7798 §7.2.1)", function()

  -- SPEC: RFC 7798 §7.2.1 "The media name in the "m=" line of SDP MUST be
  -- video." / "The clock rate in the "a=rtpmap" line MUST be 90000."
  it("accepts m=video with H265/90000", function()
    local doc, ctx = match_all(sdp_with({
      "m=video 49170 RTP/AVP 98", "a=rtpmap:98 H265/90000" }))
    assert.is_truthy(doc)
    assert.same({}, ctx.findings)
  end)

  it("rejects H265 on m=audio", function()
    local _, ctx = match_all(sdp_with({
      "m=audio 49170 RTP/AVP 98", "a=rtpmap:98 H265/90000" }))
    local f = finding_for(ctx, "sdp.a.rtpmap.h265.media-type-must-be-video")
    assert.is_not_nil(f)
    assert.equal("RFC 7798 §7.2.1", f.spec_ref)
  end)

  it("rejects an H265 clock rate other than 90000", function()
    local _, ctx = match_all(sdp_with({
      "m=video 49170 RTP/AVP 98", "a=rtpmap:98 h265/90001" }))
    assert.is_not_nil(finding_for(ctx, "sdp.a.rtpmap.h265.clock-rate-must-be-90000"))
  end)
end)

describe("codecs — H.265 fmtp value forms (RFC 7798 §7.1)", function()

  local function h265_fmtp(body)
    return sdp_with({
      "m=video 49170 RTP/AVP 98",
      "a=rtpmap:98 H265/90000",
      "a=fmtp:98 " .. body,
    })
  end

  -- Each row: parameter, a conforming value, a non-conforming value, with
  -- the §7.1 clause the pair exercises.
  local FORMS = {
    -- "The value of profile-space MUST be in the range of 0 to 3 ... The
    -- value of profile-id MUST be in the range of 0 to 31"
    { "profile-space", "3", "4" },
    { "profile-id",    "0", "32" },
    -- "The value of tier-flag MUST be in the range of 0 to 1 ... The value
    -- of level-id MUST be in the range of 0 to 255"
    { "tier-flag", "1", "2" },
    { "level-id",  "255", "256" },
    -- "A base16 [RFC4648] (hexadecimal) representation of six bytes of data"
    { "interop-constraints", "B00000000000", "B000000000" },
    -- "A base16 [RFC4648] representation of four bytes of data."
    { "profile-compatibility-indicator", "60000000", "6000000" },
    -- "MUST be in the range of 0 to 6, inclusive."
    { "sprop-sub-layer-id", "6", "7" },
    { "recv-sub-layer-id",  "0", "-1" },
    -- "MUST be in the range of 0 to 255" (tested with level-id=0 so the
    -- not-higher-than rule stays quiet)
    { "max-recv-level-id", "level-id=0;max-recv-level-id=255", "level-id=0;max-recv-level-id=256", true },
    -- "MUST be equal to "SRST", "MRST" or "MRMT"."
    { "tx-mode", "MRMT", "srst" },
    -- "a comma-separated (',') list of base64 [RFC4648] representations"
    { "sprop-vps", "QAEMAf//AWAAAAMAAAMAAAMAAAMAlqwJ", "QAEMAf//AWAAAAMAAAMAAAMAAAMAlqwJ," },
    { "sprop-sps", "QgEBAWAAAAMAAAMAAAMAAAMAlqAB4CACHH+QvNJM7LdkAQAAAwABAAADAA8I", "Qg EB" },
    { "sprop-pps", "RAHA8vA8kA==", "RAHA8vA8kA===" },
    { "sprop-sei", "TgF/kA==,TgEAkA==", "TgF/kA==,," },
    -- "The value of max-lsr is an integer" (and six others)
    { "max-lsr", "133693440", "1.3e8" },
    { "max-lps", "8912896", "8912896px" },
    { "max-cpb", "40000", "" },
    { "max-br",  "40000", "40000k" },
    { "max-tr",  "22", "twenty-two" },
    { "max-tc",  "20", "0x14" },
    { "max-fps", "60", "59.94" },
    -- "The value of max-dpb MUST be in the range of 1 to 16, inclusive."
    { "max-dpb", "16", "0" },
    { "max-dpb", "1", "17" },
    -- "MUST be an integer in the range of 0 to 32767, inclusive."
    { "sprop-max-don-diff",     "0", "32768" },
    { "sprop-depack-buf-nalus", "32767", "32768" },
    -- "MUST be an integer in the range of 0 to 4294967295, inclusive."
    { "sprop-depack-buf-bytes", "4294967295", "4294967296" },
    -- "MUST be an integer in the range of 1 to 4294967295, inclusive."
    { "depack-buf-cap", "1", "0" },
    -- "MUST be an integer in the range of 0 to 3, inclusive."
    { "sprop-segmentation-id", "3", "4" },
    -- "A base16 [RFC4648] representation of the syntax element
    -- min_spatial_segmentation_idc"
    { "sprop-spatial-segmentation-idc", "1FF", "1FG" },
    -- "each hash type provided as an unsigned integer value (0-255)";
    -- "the value contains no hash types" is a defined case.
    { "include-dph", "0,2", "0,256" },
    { "include-dph", "", "0, 2" },
  }
  for _, row in ipairs(FORMS) do
    local key, good, bad, whole = row[1], row[2], row[3], row[4]
    local id = "sdp.a.fmtp.h265." .. key .. "-invalid-value"
    local good_body = whole and good or (key .. "=" .. good)
    local bad_body  = whole and bad  or (key .. "=" .. bad)
    it(("accepts %s"):format(good_body), function()
      local doc, ctx = match_all(h265_fmtp(good_body))
      assert.is_truthy(doc)
      assert.is_nil(finding_for(ctx, id))
    end)
    it(("rejects %s [%s]"):format(bad_body, id), function()
      local _, ctx = match_all(h265_fmtp(bad_body))
      local f = finding_for(ctx, id)
      assert.is_not_nil(f)
      assert.equal("media[0].attributes[fmtp:pt=98]", f.field_path)
      assert.equal("RFC 7798 §7.1", f.spec_ref)
    end)
  end

  -- SPEC: "When sprop-max-don-diff is present and greater than 0, this
  -- parameter MUST be present and the value MUST be greater than 0."
  describe("sprop-depack-buf-nalus / -bytes with sprop-max-don-diff", function()
    for _, key in ipairs({ "sprop-depack-buf-nalus", "sprop-depack-buf-bytes" }) do
      local id = "sdp.a.fmtp.h265." .. key .. "-required-when-max-don-diff"
      local other = key == "sprop-depack-buf-nalus"
        and "sprop-depack-buf-bytes=1" or "sprop-depack-buf-nalus=1"
      it(("requires %s when sprop-max-don-diff=1"):format(key), function()
        local _, ctx = match_all(h265_fmtp("sprop-max-don-diff=1;" .. other))
        local f = finding_for(ctx, id)
        assert.is_not_nil(f)
        assert.equal("MISSING_FIELD", f.code)
      end)
      it(("rejects %s=0 when sprop-max-don-diff=1"):format(key), function()
        local _, ctx = match_all(h265_fmtp(
          "sprop-max-don-diff=1;" .. other .. ";" .. key .. "=0"))
        assert.is_not_nil(finding_for(ctx, id))
      end)
      it(("accepts %s=1 when sprop-max-don-diff=1"):format(key), function()
        local _, ctx = match_all(h265_fmtp(
          "sprop-max-don-diff=1;" .. other .. ";" .. key .. "=1"))
        assert.is_nil(finding_for(ctx, id))
      end)
      it(("does not require %s when sprop-max-don-diff=0"):format(key), function()
        local _, ctx = match_all(h265_fmtp("sprop-max-don-diff=0"))
        assert.is_nil(finding_for(ctx, id))
      end)
      it(("does not require %s when sprop-max-don-diff is absent"):format(key), function()
        local _, ctx = match_all(h265_fmtp("tx-mode=SRST"))
        assert.is_nil(finding_for(ctx, id))
      end)
    end
  end)

  -- SPEC: "max-recv-level-id MUST NOT be present when the highest level
  -- the receiver supports is not higher than the default level." and "if
  -- no level-id is present, a value of 93 (i.e., level 3.1) MUST be
  -- inferred."
  describe("max-recv-level-id against level-id", function()
    local ID = "sdp.a.fmtp.h265.max-recv-level-id-not-higher-than-level-id"
    it("accepts max-recv-level-id=120 with level-id=93", function()
      local _, ctx = match_all(h265_fmtp("level-id=93;max-recv-level-id=120"))
      assert.is_nil(finding_for(ctx, ID))
    end)
    it("rejects max-recv-level-id=93 with level-id=93", function()
      local _, ctx = match_all(h265_fmtp("level-id=93;max-recv-level-id=93"))
      assert.is_not_nil(finding_for(ctx, ID))
    end)
    it("rejects max-recv-level-id=90 with level-id absent (inferred 93)", function()
      local _, ctx = match_all(h265_fmtp("max-recv-level-id=90"))
      assert.is_not_nil(finding_for(ctx, ID))
    end)
    it("accepts max-recv-level-id=120 with level-id absent", function()
      local _, ctx = match_all(h265_fmtp("max-recv-level-id=120"))
      assert.is_nil(finding_for(ctx, ID))
    end)
  end)

  -- NOT-SPEC: library — dec-parallel-cap carries ';' inside its braces,
  -- which the key=value split cannot represent, so a line that carries it
  -- is left unchecked rather than reported through its fragments.
  it("skips a line that carries dec-parallel-cap", function()
    local doc, ctx = match_all(h265_fmtp(
      "profile-id=99;dec-parallel-cap={w:8;level-id=120;max-lsr=133693440}"))
    assert.is_truthy(doc)
    assert.same({}, ctx.findings)
  end)

  -- SPEC: RFC 8866 §6.6 (RFC 4855 §3): names are case-insensitive.
  it("matches parameter names case-insensitively", function()
    local _, ctx = match_all(h265_fmtp("Tier-Flag=2"))
    assert.is_not_nil(finding_for(ctx, "sdp.a.fmtp.h265.tier-flag-invalid-value"))
  end)
end)

describe("codecs — decode_h265_profile (RFC 7798 §7.1)", function()
  local decode = codecs.decode_h265_profile

  local function params_of(body)
    local doc = base.match(sdp_with({
      "m=video 49170 RTP/AVP 98", "a=rtpmap:98 H265/90000", "a=fmtp:98 " .. body }),
      { fail_on_first = false })
    return base.attr_get(doc.media[1], "fmtp").params
  end

  -- SPEC: inferred values "profile-space ... 0", "profile-id ... 1 (i.e.,
  -- the Main profile)", "tier-flag ... 0", "level-id ... 93 (i.e., level
  -- 3.1)", interop flags 1, 0, 1, 1.
  it("infers Main, Main tier, level 3.1, progressive when nothing is given", function()
    local d = decode(params_of("tx-mode=SRST"))
    assert.equal(0, d.profile_space)
    assert.equal(1, d.profile_id)
    assert.equal("Main", d.profile)
    assert.equal("Main", d.tier)
    assert.equal(93, d.level_id)
    assert.equal("3.1", d.level)
    assert.is_true(d.progressive_source_flag)
    assert.is_false(d.interlaced_source_flag)
    assert.is_true(d.non_packed_constraint_flag)
    assert.is_true(d.frame_only_constraint_flag)
    assert.is_true(d.profile_compatibility_flags[1])
    assert.is_false(d.profile_compatibility_flags[2])
  end)

  it("decodes profile-id=2, tier-flag=1, level-id=150 as Main 10, High tier, level 5", function()
    local d = decode(params_of("profile-id=2;tier-flag=1;level-id=150"))
    assert.equal("Main 10", d.profile)
    assert.equal("High", d.tier)
    assert.equal("5", d.level)
  end)

  -- SPEC: interop-constraints bits progressive_source_flag,
  -- interlaced_source_flag, non_packed_constraint_flag,
  -- frame_only_constraint_flag from the most significant bit.
  it("reads the interop-constraints flags", function()
    local d = decode(params_of("interop-constraints=400000000000"))
    assert.is_false(d.progressive_source_flag)
    assert.is_true(d.interlaced_source_flag)
    assert.is_false(d.non_packed_constraint_flag)
    assert.is_false(d.frame_only_constraint_flag)
  end)

  -- SPEC: "bit j of profile-compatibility-indicator =
  -- general_profile_compatibility_flag[j]", most significant bit first.
  it("reads profile-compatibility-indicator=60000000 as flags 1 and 2", function()
    local d = decode(params_of("profile-compatibility-indicator=60000000"))
    assert.is_false(d.profile_compatibility_flags[0])
    assert.is_true(d.profile_compatibility_flags[1])
    assert.is_true(d.profile_compatibility_flags[2])
    assert.is_false(d.profile_compatibility_flags[3])
    assert.is_false(d.profile_compatibility_flags[31])
  end)

  -- NOT-SPEC: library — errors are values.
  it("returns nil, err for a malformed value", function()
    local d, err = decode(params_of("level-id=999"))
    assert.is_nil(d)
    assert.is_string(err)
    assert.is_nil(decode(nil))
  end)
  it("returns nil, err for a bare flag, and ignores entries that are not pairs", function()
    for _, params in ipairs({
      { { "interop-constraints", true } },
      { { "profile-compatibility-indicator", true } },
      { { "level-id", true } },
    }) do
      local d, err = decode(params)
      assert.is_nil(d)
      assert.is_string(err)
    end
    assert.equal("Main", decode({ "a", { 1, 2 } }).profile)
  end)
end)

describe("codecs — mpeg4-generic (RFC 3640 §4.1)", function()

  local HBR = "streamType=5;profile-level-id=41;mode=AAC-hbr;config=1190;"
    .. "sizeLength=13;indexLength=3;indexDeltaLength=3"

  -- Remove one `key=value;` entry (the key may contain '-', a Lua pattern
  -- quantifier, so it is escaped).
  local function strip(body, key)
    local out = body:gsub(key:gsub("%-", "%%-") .. "=[^;]*;?", "")
    return (out:gsub(";$", ""))
  end

  local function aac(body, media)
    return sdp_with({
      "m=" .. (media or "audio") .. " 49230 RTP/AVP 96",
      "a=rtpmap:96 mpeg4-generic/48000/2",
      "a=fmtp:96 " .. body,
    })
  end

  -- SPEC: "Required parameters: ... streamType ... profile-level-id ...
  -- config ... mode"
  it("accepts an AAC-hbr fmtp with every required parameter", function()
    local doc, ctx = match_all(aac(HBR))
    assert.is_truthy(doc)
    assert.same({}, ctx.findings)
  end)
  for _, key in ipairs({ "streamType", "profile-level-id", "config", "mode" }) do
    it(("requires %s"):format(key), function()
      local body = strip(HBR, key)
      local _, ctx = match_all(aac(body))
      local f = finding_for(ctx, "sdp.a.fmtp.mpeg4-generic." .. key .. "-required")
      assert.is_not_nil(f)
      assert.equal("MISSING_FIELD", f.code)
      assert.equal("RFC 3640 §4.1", f.spec_ref)
    end)
  end

  -- SPEC: ""video" MUST be used for MPEG-4 Visual streams ... "audio" MUST
  -- be used for MPEG-4 Audio streams ... "application" MUST be used for
  -- MPEG-4 Systems streams"
  it("accepts mpeg4-generic on m=video and m=application", function()
    for _, media in ipairs({ "video", "application" }) do
      local _, ctx = match_all(aac(HBR, media))
      assert.is_nil(finding_for(ctx, "sdp.a.rtpmap.mpeg4-generic.media-type-invalid-value"))
    end
  end)
  it("rejects mpeg4-generic on m=text", function()
    local _, ctx = match_all(aac(HBR, "text"))
    assert.is_not_nil(finding_for(ctx, "sdp.a.rtpmap.mpeg4-generic.media-type-invalid-value"))
  end)

  -- Each row: parameter, conforming value, non-conforming value.
  local FORMS = {
    -- "The integer value that indicates the type of MPEG-4 stream"
    { "streamType", "5", "audio" },
    -- "A decimal representation of the MPEG-4 Profile Level indication."
    { "profile-level-id", "41", "0x29" },
    -- "A hexadecimal representation of an octet string" / config=""
    { "config", "1190", "119" },
    { "config", '""', "zz" },
    -- "The decimal value from Table 8 in ISO/IEC 14496-1"
    { "objectType", "2", "2.0" },
    { "constantSize", "27", "27b" },
    { "constantDuration", "1024", "1024.0" },
    { "maxDisplacement", "5", "-5" },
    { "de-interleaveBufferSize", "8192", "8k" },
    { "sizeLength", "13", "thirteen" },
    { "indexLength", "3", "" },
    { "indexDeltaLength", "3", "3x" },
    { "CTSDeltaLength", "16", "1e1" },
    { "DTSDeltaLength", "16", "0x10" },
    -- "A decimal value of zero or one"
    { "randomAccessIndication", "1", "2" },
    { "streamStateIndication", "4", "four" },
    { "auxiliaryDataSizeLength", "8", "eight" },
  }
  for _, row in ipairs(FORMS) do
    local key, good, bad = row[1], row[2], row[3]
    local id = "sdp.a.fmtp.mpeg4-generic." .. key .. "-invalid-value"
    -- constantSize and sizeLength are exclusive; test constantSize on a
    -- generic-mode body without sizeLength.
    local base_body = key == "constantSize"
      and "streamType=5;profile-level-id=14;mode=CELP-cbr;config=440E00"
      or strip(HBR, key)
    it(("accepts %s=%s"):format(key, good), function()
      local _, ctx = match_all(aac(base_body .. ";" .. key .. "=" .. good))
      assert.is_nil(finding_for(ctx, id))
    end)
    it(("rejects %s=%s [%s]"):format(key, bad, id), function()
      local _, ctx = match_all(aac(base_body .. ";" .. key .. "=" .. bad))
      local f = finding_for(ctx, id)
      assert.is_not_nil(f)
      assert.equal("RFC 3640 §4.1", f.spec_ref)
    end)
  end

  -- SPEC: "The sizeLength and the constantSize parameters MUST NOT be
  -- simultaneously present."
  it("rejects constantSize together with sizeLength", function()
    local _, ctx = match_all(aac(HBR .. ";constantSize=27"))
    assert.is_not_nil(finding_for(ctx,
      "sdp.a.fmtp.mpeg4-generic.constantSize-sizeLength-exclusive"))
  end)

  -- SPEC: §3.3.5 / §3.3.6 "the following parameters MUST be present:
  -- sizeLength, indexLength, and indexDeltaLength."
  for _, mode in ipairs({ "AAC-hbr", "AAC-lbr" }) do
    for _, key in ipairs({ "sizeLength", "indexLength", "indexDeltaLength" }) do
      it(("requires %s in mode %s"):format(key, mode), function()
        local body = strip((HBR:gsub("AAC%-hbr", mode)), key)
        local _, ctx = match_all(aac(body))
        local f = finding_for(ctx,
          "sdp.a.fmtp.mpeg4-generic.aac-mode-requires-size-and-index-lengths")
        assert.is_not_nil(f)
        assert.equal("RFC 3640 §3.3.5 / §3.3.6", f.spec_ref)
      end)
    end
  end
  it("does not require the lengths in mode generic", function()
    local _, ctx = match_all(aac(
      "streamType=5;profile-level-id=41;mode=generic;config=1190"))
    assert.is_nil(finding_for(ctx,
      "sdp.a.fmtp.mpeg4-generic.aac-mode-requires-size-and-index-lengths"))
  end)

  -- SPEC: "streamStateIndication ... MAY be present when transporting
  -- MPEG-4 system streams, and SHALL NOT be present for MPEG-4 audio and
  -- MPEG-4 video streams." The stream kind is streamType (ISO/IEC 14496-1
  -- Table 9: 4 VisualStream, 5 AudioStream).
  it("rejects streamStateIndication on an audio stream (streamType=5)", function()
    local _, ctx = match_all(aac(HBR .. ";streamStateIndication=4"))
    assert.is_not_nil(finding_for(ctx,
      "sdp.a.fmtp.mpeg4-generic.streamStateIndication-forbidden"))
  end)
  it("rejects streamStateIndication on a visual stream (streamType=4) whatever the m= type", function()
    local _, ctx = match_all(aac(
      "streamType=4;profile-level-id=1;mode=generic;config=\"\";streamStateIndication=4",
      "application"))
    assert.is_not_nil(finding_for(ctx,
      "sdp.a.fmtp.mpeg4-generic.streamStateIndication-forbidden"))
  end)
  -- SPEC: the §3.3.2 example, an MPEG-4 Systems (BIFS-Anim, streamtype=3)
  -- stream that §4.1 puts under m=video.
  it("accepts the RFC 3640 §3.3.2 example: streamStateIndication on an m=video systems stream", function()
    local doc, ctx = match_all(sdp_with({
      "m=video 49230 RTP/AVP 96",
      "a=rtpmap:96 mpeg4-generic/1000",
      "a=fmtp:96 streamtype=3; profile-level-id=1807; mode=generic; objectType=2; "
        .. "config=0842237F24001FB400094002C0; sizeLength=10; CTSDeltaLength=16; "
        .. "randomAccessIndication=1; streamStateIndication=4" }))
    assert.is_truthy(doc)
    assert.same({}, ctx.findings)
  end)
  it("accepts streamStateIndication on m=application with streamType=1", function()
    local _, ctx = match_all(aac(
      "streamType=1;profile-level-id=1;mode=generic;config=\"\";streamStateIndication=4",
      "application"))
    assert.is_nil(finding_for(ctx,
      "sdp.a.fmtp.mpeg4-generic.streamStateIndication-forbidden"))
  end)
  -- NOT-SPEC: library — an fmtp the grammar accepted as an opaque byte
  -- string (an empty ';;' entry) has no readable parameters, so the
  -- required ones are reported missing, on the fmtp line (decision
  -- parse_sdp-n7i). Attributes carry no position field afterwards.
  it("reports the required parameters of an fmtp it could not decompose, on its line", function()
    local doc, ctx = match_all(aac("streamType=5;;mode=AAC-hbr"))
    for _, key in ipairs({ "streamType", "profile-level-id", "config", "mode" }) do
      local f = finding_for(ctx, "sdp.a.fmtp.mpeg4-generic." .. key .. "-required")
      assert.is_not_nil(f, key)
      assert.equal(8, f.line)
      assert.equal("media[0].attributes[fmtp:pt=96]", f.field_path)
    end
    for _, a in ipairs(doc.media[1].attributes) do assert.is_nil(a._pos) end
  end)

  -- SPEC: RFC 3640 §4.1 "MIME format parameters are not case dependent"
  it("matches parameter names case-insensitively", function()
    local _, ctx = match_all(aac(
      "streamtype=5;PROFILE-LEVEL-ID=41;Mode=AAC-hbr;Config=1190;"
      .. "SizeLength=13;IndexLength=3;IndexDeltaLength=3"))
    assert.same({}, ctx.findings)
  end)
end)

describe("codecs — MP4A-LATM (RFC 6416 §7.3 / §7.4)", function()

  local function latm(body, media)
    return sdp_with({
      "m=" .. (media or "audio") .. " 49232 RTP/AVP 97",
      "a=rtpmap:97 MP4A-LATM/48000/2",
      "a=fmtp:97 " .. body,
    })
  end

  -- SPEC: §7.4 "The media type (audio) goes in SDP "m=" as the media name."
  it("rejects MP4A-LATM on m=video", function()
    local _, ctx = match_all(latm("cpresent=1", "video"))
    local f = finding_for(ctx, "sdp.a.rtpmap.mp4a-latm.media-type-must-be-audio")
    assert.is_not_nil(f)
    assert.equal("RFC 6416 §7.4", f.spec_ref)
  end)

  -- NOT-SPEC: library — §7.3 fixes no clock rate ("Other rates MAY be
  -- indicated"), so none is checked.
  it("accepts any clock rate", function()
    local doc, ctx = match_all(sdp_with({
      "m=audio 49232 RTP/AVP 97", "a=rtpmap:97 mp4a-latm/44100/2", "a=fmtp:97 cpresent=1" }))
    assert.is_truthy(doc)
    assert.same({}, ctx.findings)
  end)

  local FORMS = {
    { "profile-level-id",     "41", "41a" },
    { "MPS-profile-level-id", "55", "fifty-five" },
    { "object",               "2", "AAC-LC" },
    { "cpresent",             "0", "2" },
    { "config",               "40002310", "4000231" },
    { "MPS-asc",              "0000", "00g0" },
    { "SBR-enabled",          "1", "true" },
  }
  for _, row in ipairs(FORMS) do
    local key, good, bad = row[1], row[2], row[3]
    local id = "sdp.a.fmtp.mp4a-latm." .. key .. "-invalid-value"
    local lead = key == "config" and "" or "config=40002310;"
    it(("accepts %s=%s"):format(key, good), function()
      local _, ctx = match_all(latm(lead .. key .. "=" .. good))
      assert.is_nil(finding_for(ctx, id))
    end)
    it(("rejects %s=%s [%s]"):format(key, bad, id), function()
      local _, ctx = match_all(latm(lead .. key .. "=" .. bad))
      local f = finding_for(ctx, id)
      assert.is_not_nil(f)
      assert.equal("RFC 6416 §7.3", f.spec_ref)
    end)
  end

  -- SPEC: "A 0 indicates the configuration data has not been multiplexed
  -- into an RTP payload, and in that case, the "config" parameter MUST be
  -- present"
  it("requires config when cpresent=0 (or 00)", function()
    assert.is_not_nil(finding_for(select(2, match_all(latm("cpresent=00"))),
      "sdp.a.fmtp.mp4a-latm.config-required-when-cpresent-0"))
    local _, ctx = match_all(latm("profile-level-id=41;cpresent=0"))
    local f = finding_for(ctx, "sdp.a.fmtp.mp4a-latm.config-required-when-cpresent-0")
    assert.is_not_nil(f)
    assert.equal("MISSING_FIELD", f.code)
  end)
  it("accepts cpresent=0 with config", function()
    local _, ctx = match_all(latm("cpresent=0;config=40002310"))
    assert.is_nil(finding_for(ctx, "sdp.a.fmtp.mp4a-latm.config-required-when-cpresent-0"))
  end)
  it("does not require config when cpresent=1 or absent", function()
    for _, body in ipairs({ "cpresent=1", "profile-level-id=41" }) do
      local _, ctx = match_all(latm(body))
      assert.is_nil(finding_for(ctx, "sdp.a.fmtp.mp4a-latm.config-required-when-cpresent-0"))
    end
  end)
end)

describe("codecs — MPEG-2 transport stream, MP2T (RFC 2250 §2, RFC 3551 Table 5)", function()

  -- SPEC: RFC 2250 §2 "32 bit 90K Hz timestamp"; RFC 3551 Table 5 "33 MP2T
  -- AV 90,000".
  it("accepts MP2T/90000 on m=video and on m=audio (media type AV)", function()
    for _, media in ipairs({ "video", "audio" }) do
      local doc, ctx = match_all(sdp_with({
        "m=" .. media .. " 30000 RTP/AVP 33", "a=rtpmap:33 MP2T/90000" }))
      assert.is_truthy(doc)
      assert.same({}, ctx.findings)
    end
  end)

  it("rejects an MP2T clock rate other than 90000", function()
    local _, ctx = match_all(sdp_with({
      "m=video 30000 RTP/AVP 100", "a=rtpmap:100 mp2t/27000000" }))
    local f = finding_for(ctx, "sdp.a.rtpmap.mp2t.clock-rate-must-be-90000")
    assert.is_not_nil(f)
    assert.equal("RFC 2250 §2; RFC 3551 Table 5", f.spec_ref)
  end)

  -- NOT-SPEC: library — RFC 3555 §4.2.9 defines no parameters, so an fmtp
  -- on an MP2T payload type is left alone.
  it("does not check an MP2T fmtp", function()
    local doc, ctx = match_all(sdp_with({
      "m=video 30000 RTP/AVP 100", "a=rtpmap:100 MP2T/90000", "a=fmtp:100 x=1" }))
    assert.is_truthy(doc)
    assert.same({}, ctx.findings)
  end)

  -- SPEC: ST 2110-10:2022 §8.5 DUP leg coherence runs on any encoding; the
  -- RFC 7104 §4.2 shape (two MP2T legs, separate destinations) is the
  -- non-2110 case.
  it("ST 2110 tier: DUP coherence fires on MP2T legs with different fmtp", function()
    local _, ctx = st2110.match(table.concat({
      "v=0",
      "o=- 1122334455 1122334466 IN IP4 192.0.2.1",
      "s=DUP Grouping Semantics",
      "t=0 0",
      "a=group:DUP S1a S1b",
      "m=video 30000 RTP/AVP 100",
      "c=IN IP4 233.252.0.1/127",
      "a=source-filter: incl IN IP4 233.252.0.1 198.51.100.1",
      "a=rtpmap:100 MP2T/90000",
      "a=fmtp:100 x=1",
      "a=mid:S1a",
      support.TIMING_TS_REFCLK, support.TIMING_MEDIACLK,
      "m=video 30000 RTP/AVP 100",
      "c=IN IP4 233.252.0.2/127",
      "a=source-filter: incl IN IP4 233.252.0.2 198.51.100.1",
      "a=rtpmap:100 MP2T/90000",
      "a=fmtp:100 x=2",
      "a=mid:S1b",
      support.TIMING_TS_REFCLK, support.TIMING_MEDIACLK,
    }, "\r\n") .. "\r\n", { fail_on_first = false })
    assert.is_not_nil(finding_for(ctx, "st2110-10.a.group-dup.fmtp-same"))
    assert.is_nil(finding_for(ctx, "st2110-10.a.group-dup.rtpmap-same"))
  end)
end)

describe("codecs — L16 emphasis (RFC 4856 §2.1.15)", function()
  -- SPEC: "The only emphasis value defined here is emphasis=50-15"
  it("accepts emphasis=50-15", function()
    local doc, ctx = match_all(sdp_with({
      "m=audio 49170 RTP/AVP 97", "a=rtpmap:97 L16/48000/2", "a=fmtp:97 emphasis=50-15" }))
    assert.is_truthy(doc)
    assert.same({}, ctx.findings)
  end)
  it("rejects emphasis=75-15", function()
    local _, ctx = match_all(sdp_with({
      "m=audio 49170 RTP/AVP 97", "a=rtpmap:97 l16/48000/2", "a=fmtp:97 Emphasis=75-15" }))
    local f = finding_for(ctx, "sdp.a.fmtp.l16.emphasis-invalid-value")
    assert.is_not_nil(f)
    assert.equal("RFC 4856 §2.1.15", f.spec_ref)
  end)
  -- NOT-SPEC: library — L24 has no emphasis parameter in RFC 3190, so the
  -- L16 rule does not reach it.
  it("does not check emphasis on L24", function()
    local doc, ctx = match_all(sdp_with({
      "m=audio 49170 RTP/AVP 97", "a=rtpmap:97 L24/48000/2", "a=fmtp:97 emphasis=75-15" }))
    assert.is_truthy(doc)
    assert.same({}, ctx.findings)
  end)
end)
