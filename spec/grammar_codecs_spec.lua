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

  -- SPEC: "If the level_idc byte ... is equal to 11 and bit 4 of the
  -- profile-iop byte ... is equal to 1 or if the level_idc byte ... is
  -- equal to 9 ... Level 1b."
  it("decodes level_idc 11 with constraint_set3_flag as level 1b", function()
    assert.equal("1b", decode("42100b").level)
  end)
  it("decodes level_idc 11 without constraint_set3_flag as level 1.1", function()
    assert.equal("1.1", decode("42000b").level)
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
