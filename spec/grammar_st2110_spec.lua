---@diagnostic disable
-- Phase 6.B: ST 2110 rtpmap-per-media-type narrowings.
-- Each encoding (raw / jxsv / smpte291 / AM824) carries a defined media
-- type and clock rate. The grammar accepts an SDP under the base tier but
-- fails it under the st2110 tier when either constraint is violated.

local base   = require("parse_sdp.grammar.base")
local st2110 = require("parse_sdp.grammar.st2110")

local function build(media_line, rtpmap_line)
  return table.concat({
    "v=0",
    "o=- 1 1 IN IP4 192.0.2.1",
    "s=Test",
    "t=0 0",
    media_line,
    "c=IN IP4 239.0.0.1/64",
    rtpmap_line,
  }, "\r\n") .. "\r\n"
end

-- Build with an extra fmtp line after the rtpmap.
local function build_with_fmtp(media_line, rtpmap_line, fmtp_line)
  return table.concat({
    "v=0",
    "o=- 1 1 IN IP4 192.0.2.1",
    "s=Test",
    "t=0 0",
    media_line,
    "c=IN IP4 239.0.0.1/64",
    rtpmap_line,
    fmtp_line,
  }, "\r\n") .. "\r\n"
end

-- Finding helper: returns the first finding with the matched id, or nil.
local function finding_for(ctx, id)
  for _, f in ipairs(ctx.findings or {}) do
    if f.id == id then return f end
  end
  return nil
end

-- A complete raw video fmtp line containing every ST 2110-20:2022 §7.2 +
-- §7.4.2 + ST 2110-21:2022 §8.1 required parameter. Acceptance tests that
-- aren't *about* required-param presence append this so they don't trip
-- the §7.2 semantic check (Phase 6.C.C).
local RAW_FMTP_COMPLETE_PT96 =
    "a=fmtp:96 sampling=YCbCr-4:2:2;width=1920;height=1080;"
 .. "exactframerate=60000/1001;depth=10;colorimetry=BT709;"
 .. "PM=2110GPM;SSN=ST2110-20:2022;TP=2110TPN"

describe("ST 2110-20 raw — rtpmap narrowings (ST 2110-20:2022 §7.1)", function()

  it("accepts m=video with raw/90000", function()
    -- fmtp included so the Phase 6.C.C required-param check doesn't fail
    -- the match; this test asserts only the rtpmap narrowing.
    local doc = st2110.match(build_with_fmtp(
      "m=video 30000 RTP/AVP 96",
      "a=rtpmap:96 raw/90000",
      RAW_FMTP_COMPLETE_PT96))
    assert.is_truthy(doc)
  end)

  it("rejects raw with non-video media type", function()
    local doc, ctx = st2110.match(build("m=audio 30000 RTP/AVP 96",
                                        "a=rtpmap:96 raw/90000"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "st2110-20.a.rtpmap.raw-media-type"))
  end)

  it("rejects raw with clock rate ≠ 90000", function()
    local doc, ctx = st2110.match(build("m=video 30000 RTP/AVP 96",
                                        "a=rtpmap:96 raw/48000"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "st2110-20.a.rtpmap.raw-clock-rate"))
  end)

  -- NOT-SPEC: library — base tier MUST still accept the same input the
  -- ST 2110 tier rejects, so the narrowing is genuinely added (not
  -- inherited from base).
  it("base tier accepts the same input ST 2110 rejects", function()
    assert.is_truthy(base.match(build("m=audio 30000 RTP/AVP 96",
                                      "a=rtpmap:96 raw/90000")))
    assert.is_truthy(base.match(build("m=video 30000 RTP/AVP 96",
                                      "a=rtpmap:96 raw/48000")))
  end)
end)

describe("ST 2110-22 jxsv — rtpmap narrowings (ST 2110-22:2022 §5.2/§6.2)", function()

  it("accepts m=video with jxsv/90000", function()
    local doc = st2110.match(build("m=video 30000 RTP/AVP 96",
                                   "a=rtpmap:96 jxsv/90000"))
    assert.is_truthy(doc)
  end)

  it("rejects jxsv with non-video media type", function()
    local doc, ctx = st2110.match(build("m=audio 30000 RTP/AVP 96",
                                        "a=rtpmap:96 jxsv/90000"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "st2110-22.a.rtpmap.jxsv-media-type"))
  end)

  it("rejects jxsv with clock rate ≠ 90000", function()
    local doc, ctx = st2110.match(build("m=video 30000 RTP/AVP 96",
                                        "a=rtpmap:96 jxsv/48000"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "st2110-22.a.rtpmap.jxsv-clock-rate"))
  end)
end)

describe("ST 2110-40 smpte291 — rtpmap narrowings (ST 2110-40:2023 §5.3 / RFC 8331 §4)", function()

  it("accepts m=video with smpte291/90000", function()
    local doc = st2110.match(build("m=video 30000 RTP/AVP 96",
                                   "a=rtpmap:96 smpte291/90000"))
    assert.is_truthy(doc)
  end)

  it("rejects smpte291 with non-video media type", function()
    local doc, ctx = st2110.match(build("m=audio 30000 RTP/AVP 96",
                                        "a=rtpmap:96 smpte291/90000"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "st2110-40.a.rtpmap.smpte291-media-type"))
  end)

  it("rejects smpte291 with clock rate ≠ 90000", function()
    local doc, ctx = st2110.match(build("m=video 30000 RTP/AVP 96",
                                        "a=rtpmap:96 smpte291/48000"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "st2110-40.a.rtpmap.smpte291-clock-rate"))
  end)
end)

describe("ST 2110-31 AM824 — rtpmap narrowings (ST 2110-31:2022 §6.1)", function()

  it("accepts m=audio with AM824/48000/2", function()
    local doc = st2110.match(build("m=audio 30000 RTP/AVP 96",
                                   "a=rtpmap:96 AM824/48000/2"))
    assert.is_truthy(doc)
  end)

  it("accepts m=audio with AM824/44100/2", function()
    assert.is_truthy(st2110.match(build("m=audio 30000 RTP/AVP 96",
                                        "a=rtpmap:96 AM824/44100/2")))
  end)

  it("accepts m=audio with AM824/96000/2", function()
    assert.is_truthy(st2110.match(build("m=audio 30000 RTP/AVP 96",
                                        "a=rtpmap:96 AM824/96000/2")))
  end)

  it("rejects AM824 with non-audio media type", function()
    local doc, ctx = st2110.match(build("m=video 30000 RTP/AVP 96",
                                        "a=rtpmap:96 AM824/48000/2"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "st2110-31.a.rtpmap.am824-media-type"))
  end)

  it("rejects AM824 with clock rate outside {44100,48000,96000}", function()
    local doc, ctx = st2110.match(build("m=audio 30000 RTP/AVP 96",
                                        "a=rtpmap:96 AM824/192000/2"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "st2110-31.a.rtpmap.am824-clock-rate-set"))
  end)
end)

describe("ST 2110 rtpmap narrowings — non-ST-2110 encodings pass through", function()

  -- NOT-SPEC: library — H264 has no ST 2110 rtpmap narrowing in 6.B; the
  -- check function leaves it alone. Per CLAUDE.md strictness, silence is
  -- not rejection.
  it("accepts m=video with H264/90000 (no ST 2110 rule for H264)", function()
    assert.is_truthy(st2110.match(build("m=video 30000 RTP/AVP 96",
                                        "a=rtpmap:96 H264/90000")))
  end)

  -- NOT-SPEC: library
  it("accepts m=audio with L16/48000/2 (no AES67 check in 6.B)", function()
    assert.is_truthy(st2110.match(build("m=audio 30000 RTP/AVP 96",
                                        "a=rtpmap:96 L16/48000/2")))
  end)
end)

-- ───────────────────────────────────────────────────────────────────────────
-- Phase 6.C.B — ST 2110-20 raw fmtp parameter-form narrowing
-- ST 2110-20:2022 §7.1: "Each media type parameter entry shall be
-- constructed as either: a <name>=<value> pair, with no whitespace within
-- the name or value or between the name, equal sign, and value."
-- Scope: only when the surrounding rtpmap encoding is `raw`.

describe("ST 2110-20 raw fmtp — no whitespace around '=' (ST 2110-20:2022 §7.1)", function()

  local RAW_MEDIA  = "m=video 30000 RTP/AVP 96"
  local RAW_RTPMAP = "a=rtpmap:96 raw/90000"

  it("accepts fmtp with no whitespace around '='", function()
    -- Use the complete required-param set so the Phase 6.C.C semantic
    -- check doesn't fire; this test asserts only the whitespace narrowing.
    local doc = st2110.match(build_with_fmtp(
      RAW_MEDIA, RAW_RTPMAP, RAW_FMTP_COMPLETE_PT96))
    assert.is_truthy(doc)
  end)

  it("rejects fmtp with whitespace on both sides of '='", function()
    local doc, ctx = st2110.match(build_with_fmtp(
      RAW_MEDIA, RAW_RTPMAP,
      "a=fmtp:96 sampling = YCbCr-4:2:2"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "st2110-20.a.fmtp.no-whitespace-around-equals"))
  end)

  it("rejects fmtp with whitespace before '='", function()
    local doc, ctx = st2110.match(build_with_fmtp(
      RAW_MEDIA, RAW_RTPMAP,
      "a=fmtp:96 sampling =YCbCr-4:2:2"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "st2110-20.a.fmtp.no-whitespace-around-equals"))
  end)

  it("rejects fmtp with whitespace after '='", function()
    local doc, ctx = st2110.match(build_with_fmtp(
      RAW_MEDIA, RAW_RTPMAP,
      "a=fmtp:96 sampling= YCbCr-4:2:2"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "st2110-20.a.fmtp.no-whitespace-around-equals"))
  end)

  it("rejects only the offending entry's row (later entry trips the check)", function()
    -- First entry is clean; second has whitespace around '='. The strict
    -- branch fails on the second entry, so the whole match fails.
    local doc, ctx = st2110.match(build_with_fmtp(
      RAW_MEDIA, RAW_RTPMAP,
      "a=fmtp:96 sampling=YCbCr-4:2:2;width = 1920"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "st2110-20.a.fmtp.no-whitespace-around-equals"))
  end)

  -- NOT-SPEC: library — narrowing is scoped to raw via Cb"encoding". Other
  -- ST 2110 essence specs do not carry the no-whitespace SHALL; they keep
  -- base's loose form (CLAUDE.md strictness: silence ≠ rejection).
  it("does NOT reject whitespace-around-= for jxsv (no narrowing applies)", function()
    assert.is_truthy(st2110.match(build_with_fmtp(
      "m=video 30000 RTP/AVP 96",
      "a=rtpmap:96 jxsv/90000",
      "a=fmtp:96 profile = High444.12")))
  end)

  -- NOT-SPEC: library
  it("does NOT reject whitespace-around-= for smpte291 (no narrowing applies)", function()
    assert.is_truthy(st2110.match(build_with_fmtp(
      "m=video 30000 RTP/AVP 96",
      "a=rtpmap:96 smpte291/90000",
      "a=fmtp:96 DID_SDID = {0x41,0x05}")))
  end)

  -- NOT-SPEC: library — base tier MUST still accept what ST 2110 rejects.
  it("base tier accepts whitespace around '=' even for raw", function()
    assert.is_truthy(base.match(build_with_fmtp(
      RAW_MEDIA, RAW_RTPMAP,
      "a=fmtp:96 sampling = YCbCr-4:2:2")))
  end)
end)

-- ───────────────────────────────────────────────────────────────────────────
-- Phase 6.C.C — ST 2110-20 raw video fmtp required-parameter presence
-- ST 2110-20:2022 §7.2 lists eight required fmtp parameters: sampling,
-- depth, width, height, exactframerate, colorimetry, PM, SSN. TP is also
-- required for every raw video stream per ST 2110-21:2022 §8.1.
-- Scope: only fires when the surrounding rtpmap encoding is `raw`.

describe("ST 2110-20 raw video fmtp — required parameters", function()

  local RAW_MEDIA  = "m=video 30000 RTP/AVP 96"
  local RAW_RTPMAP = "a=rtpmap:96 raw/90000"

  -- Canonical complete raw fmtp; per-param tests omit one entry to assert
  -- the matching `<param>-required` finding fires.
  local REQUIRED = {
    sampling       = "YCbCr-4:2:2",
    width          = "1920",
    height         = "1080",
    exactframerate = "60000/1001",
    depth          = "10",
    colorimetry    = "BT709",
    PM             = "2110GPM",
    SSN            = "ST2110-20:2022",
    TP             = "2110TPN",
  }

  -- Stable order matching the 1.0 parser's check order (and §7.2's listing).
  local REQUIRED_ORDER = {
    "sampling", "width", "height", "exactframerate", "depth",
    "colorimetry", "PM", "SSN", "TP",
  }

  local function fmtp_omitting(key_to_omit)
    local parts = {}
    for _, k in ipairs(REQUIRED_ORDER) do
      if k ~= key_to_omit then
        parts[#parts + 1] = k .. "=" .. REQUIRED[k]
      end
    end
    return "a=fmtp:96 " .. table.concat(parts, ";")
  end

  local function fmtp_complete()
    local parts = {}
    for _, k in ipairs(REQUIRED_ORDER) do
      parts[#parts + 1] = k .. "=" .. REQUIRED[k]
    end
    return "a=fmtp:96 " .. table.concat(parts, ";")
  end

  it("accepts raw fmtp with every required parameter present", function()
    assert.is_truthy(st2110.match(build_with_fmtp(
      RAW_MEDIA, RAW_RTPMAP, fmtp_complete())))
  end)

  -- ST 2110-20:2022 §7.2 — sampling, width, height, exactframerate,
  -- depth (§7.4.2), colorimetry, PM, SSN. TP — ST 2110-21:2022 §8.1.
  local PER_PARAM_SPEC_REF = {
    sampling       = "ST 2110-20:2022 §7.2",
    width          = "ST 2110-20:2022 §7.2",
    height         = "ST 2110-20:2022 §7.2",
    exactframerate = "ST 2110-20:2022 §7.2",
    depth          = "ST 2110-20:2022 §7.4.2",
    colorimetry    = "ST 2110-20:2022 §7.2",
    PM             = "ST 2110-20:2022 §7.2",
    SSN            = "ST 2110-20:2022 §7.2",
    TP             = "ST 2110-21:2022 §8.1",
  }

  for _, key in ipairs(REQUIRED_ORDER) do
    it(("rejects raw fmtp missing '%s' [%s]"):format(key, PER_PARAM_SPEC_REF[key]),
       function()
      local doc, ctx = st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_omitting(key)))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-20.a.fmtp." .. key .. "-required"))
    end)
  end

  -- NOT-SPEC: library — narrowing is scoped to raw via the rtpmap encoding
  -- recorded in ctx. smpte291 / jxsv / AM824 fmtps have their own required
  -- sets, not enforced here.
  it("does NOT require -20 params for smpte291 (different essence)", function()
    assert.is_truthy(st2110.match(build_with_fmtp(
      "m=video 30000 RTP/AVP 96",
      "a=rtpmap:96 smpte291/90000",
      "a=fmtp:96 DID_SDID={0x41,0x05}")))
  end)

  -- NOT-SPEC: library — a static-PT fmtp has no rtpmap binding, so the
  -- raw-encoding lookup misses and the requirement does not fire.
  it("does NOT require -20 params when PT is unbound (no rtpmap)", function()
    assert.is_truthy(st2110.match(table.concat({
      "v=0",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=Test",
      "t=0 0",
      "m=video 30000 RTP/AVP 31",        -- PT 31 = H.261, static
      "c=IN IP4 239.0.0.1/64",
      "a=fmtp:31 CIF=2",                 -- no rtpmap → no raw binding
    }, "\r\n") .. "\r\n"))
  end)

  -- NOT-SPEC: library — base tier carries no ST 2110 requirements.
  it("base tier accepts raw rtpmap with no fmtp at all", function()
    assert.is_truthy(base.match(build(RAW_MEDIA, RAW_RTPMAP)))
  end)

  -- NOT-SPEC: library — ST 2110 tier also requires the fmtp itself to
  -- exist for raw video (no fmtp means no required params at all).
  it("rejects raw video with no a=fmtp at all", function()
    local doc, ctx = st2110.match(build(RAW_MEDIA, RAW_RTPMAP))
    assert.is_nil(doc)
    -- The first missing-param finding identifies the failure mode; the
    -- semantic check records the first absent key in §7.2 order.
    assert.is_not_nil(finding_for(ctx,
      "st2110-20.a.fmtp.sampling-required"))
  end)
end)

-- ───────────────────────────────────────────────────────────────────────────
-- Phase 6.C.D.1 — ST 2110-20 raw video fmtp enum value-set narrowings.
-- For each of seven enum-typed parameters (sampling, depth, colorimetry, PM,
-- TP, TCS, RANGE) verify the parser accepts the permitted set and rejects
-- a value outside the set, recording the matching -invalid-value finding.

describe("ST 2110-20 raw video fmtp — enum value sets", function()

  local RAW_MEDIA  = "m=video 30000 RTP/AVP 96"
  local RAW_RTPMAP = "a=rtpmap:96 raw/90000"

  -- Build the complete raw fmtp line with one parameter overridden to an
  -- arbitrary value. Used to assert per-key value-set narrowing.
  local function fmtp_with(key, val)
    local parts = {
      "sampling=YCbCr-4:2:2",
      "width=1920",
      "height=1080",
      "exactframerate=60000/1001",
      "depth=10",
      "colorimetry=BT709",
      "PM=2110GPM",
      "SSN=ST2110-20:2022",
      "TP=2110TPN",
    }
    -- Replace the line for the named key in place; if optional (TCS / RANGE),
    -- append.
    local replaced = false
    for i, p in ipairs(parts) do
      if p:sub(1, #key + 1) == (key .. "=") then
        parts[i] = key .. "=" .. val
        replaced = true
        break
      end
    end
    if not replaced then
      parts[#parts + 1] = key .. "=" .. val
    end
    return "a=fmtp:96 " .. table.concat(parts, ";")
  end

  -- Permitted value sets, lifted from RAW_VIDEO_ENUM_VALUES in
  -- parse_sdp/grammar/st2110.lua. Tests pick the first element from each
  -- set for an accept case and a single fixed out-of-set string for reject.
  local ENUM_VALUES = {
    sampling    = { "YCbCr-4:4:4", "YCbCr-4:2:2", "YCbCr-4:2:0",
                    "CLYCbCr-4:4:4", "CLYCbCr-4:2:2", "CLYCbCr-4:2:0",
                    "ICtCp-4:4:4", "ICtCp-4:2:2", "ICtCp-4:2:0",
                    "RGB", "XYZ", "KEY" },
    depth       = { "8", "10", "12", "16", "16f" },
    colorimetry = { "BT601", "BT709", "BT2020", "BT2100",
                    "ST2065-1", "ST2065-3", "XYZ", "ALPHA", "UNSPECIFIED" },
    PM          = { "2110GPM", "2110BPM" },
    TP          = { "2110TPN", "2110TPNL", "2110TPW" },
    TCS         = { "SDR", "PQ", "HLG", "LINEAR",
                    "BT2100LINPQ", "BT2100LINHLG",
                    "ST2065-1", "ST428-1", "DENSITY",
                    "ST2115LOGS3", "UNSPECIFIED" },
    RANGE       = { "NARROW", "FULLPROTECT", "FULL" },
  }

  local SPEC_REF = {
    sampling    = "ST 2110-20:2022 §7.2",
    depth       = "ST 2110-20:2022 §7.4.2",
    colorimetry = "ST 2110-20:2022 §7.5",
    PM          = "ST 2110-20:2022 §6.3",
    TP          = "ST 2110-21:2022 §8.1",
    TCS         = "ST 2110-20:2022 §7.6",
    RANGE       = "ST 2110-20:2022 §7.3",
  }

  local KEY_ORDER = {
    "sampling", "depth", "colorimetry", "PM", "TP", "TCS", "RANGE",
  }

  for _, key in ipairs(KEY_ORDER) do
    describe(("'%s' [%s]"):format(key, SPEC_REF[key]), function()
      for _, v in ipairs(ENUM_VALUES[key]) do
        it(("accepts %s=%s"):format(key, v), function()
          assert.is_truthy(st2110.match(build_with_fmtp(
            RAW_MEDIA, RAW_RTPMAP, fmtp_with(key, v))))
        end)
      end

      it(("rejects %s=BOGUS"):format(key), function()
        local doc, ctx = st2110.match(build_with_fmtp(
          RAW_MEDIA, RAW_RTPMAP, fmtp_with(key, "BOGUS")))
        assert.is_nil(doc)
        assert.is_not_nil(finding_for(ctx,
          "st2110-20.a.fmtp." .. key .. "-invalid-value"))
      end)

      -- NOT-SPEC: library — base tier carries no value-set narrowing.
      it(("base tier accepts %s=BOGUS"):format(key), function()
        assert.is_truthy(base.match(build_with_fmtp(
          RAW_MEDIA, RAW_RTPMAP, fmtp_with(key, "BOGUS"))))
      end)
    end)
  end

  -- NOT-SPEC: library — narrowing is scoped to raw. A non-raw essence
  -- with an out-of-set value passes the ST 2110 tier (no -20 SHALL
  -- applies to smpte291 fmtp).
  it("does NOT validate sampling values on non-raw essences", function()
    assert.is_truthy(st2110.match(build_with_fmtp(
      "m=video 30000 RTP/AVP 96",
      "a=rtpmap:96 smpte291/90000",
      "a=fmtp:96 sampling=BOGUS;DID_SDID={0x41,0x05}")))
  end)
end)
