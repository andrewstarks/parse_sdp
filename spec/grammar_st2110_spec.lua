---@diagnostic disable
-- Phase 6.B: ST 2110 rtpmap-per-media-type narrowings.
-- Each encoding (raw / jxsv / smpte291 / AM824) carries a defined media
-- type and clock rate. The grammar accepts an SDP under the base tier but
-- fails it under the st2110 tier when either constraint is violated.

local base   = require("parse_sdp.grammar.base")
local st2110 = require("parse_sdp.grammar.st2110")

-- ST 2110-10:2022 §8.2 + §8.3 require every media block to carry
-- a=ts-refclk and a media-level a=mediaclk (Phase 6.D.A). The build
-- helpers below include both by default so tests that aren't about
-- per-attribute presence don't trip the new semantic checks. Use the
-- TIMING_* constants directly when constructing custom SDPs.
local TIMING_TS_REFCLK = "a=ts-refclk:localmac=00-11-22-33-44-55"
local TIMING_MEDIACLK  = "a=mediaclk:sender"

local function build(media_line, rtpmap_line)
  return table.concat({
    "v=0",
    "o=- 1 1 IN IP4 192.0.2.1",
    "s=Test",
    "t=0 0",
    media_line,
    "c=IN IP4 239.0.0.1/64",
    rtpmap_line,
    TIMING_TS_REFCLK,
    TIMING_MEDIACLK,
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
    TIMING_TS_REFCLK,
    TIMING_MEDIACLK,
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

-- A complete jxsv fmtp line containing every ST 2110-22:2022 §7.2 +
-- RFC 9134 §7.1 required parameter (width, height, TP, packetmode).
-- Acceptance tests that aren't *about* jxsv required-param presence
-- append this so they don't trip the §7.2 / §7.1 semantic check
-- (Phase 6.C.G.1).
local JXSV_FMTP_COMPLETE_PT96 =
    "a=fmtp:96 width=1920;height=1080;TP=2110TPN;packetmode=0"

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
    -- fmtp included so the Phase 6.C.G.1 required-param check doesn't
    -- fail the match; this test asserts only the rtpmap narrowing.
    local doc = st2110.match(build_with_fmtp(
      "m=video 30000 RTP/AVP 96",
      "a=rtpmap:96 jxsv/90000",
      JXSV_FMTP_COMPLETE_PT96))
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
    -- Use the complete jxsv required-param set + an extra profile with
    -- whitespace around `=` so this test isolates only the ws-around-=
    -- narrowing (the 6.C.G.1 jxsv required-param check passes).
    assert.is_truthy(st2110.match(build_with_fmtp(
      "m=video 30000 RTP/AVP 96",
      "a=rtpmap:96 jxsv/90000",
      JXSV_FMTP_COMPLETE_PT96 .. ";profile = High444.12")))
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
      "a=ts-refclk:localmac=00-11-22-33-44-55",
      "a=mediaclk:sender",
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
  --
  -- The default set is balanced for cross-parameter compatibility: when
  -- testing an enum value that has a cross-param SHALL (KEY needs ALPHA;
  -- 4:2:0 forbids interlace — n/a here since defaults don't carry it),
  -- companion params are adjusted so the SOLE check under test is the
  -- per-key enum value-set. Otherwise the 6.C.E cross-param checks would
  -- mask the value-set acceptance test.
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
    -- Cross-param companion adjustments per §7.4.1: KEY sampling requires
    -- colorimetry=ALPHA AND forbids TCS. Pair the override accordingly so
    -- the only check under test is sampling's own value-set membership.
    if key == "sampling" and val == "KEY" then
      for i, p in ipairs(parts) do
        if p:sub(1, 12) == "colorimetry=" then
          parts[i] = "colorimetry=ALPHA"
        end
      end
    end

    -- Cross-param companion adjustments per §7.6 (Phase 6.C.F):
    -- floating-point linear TCS values are defined with `(depth=16f)`.
    -- Pair the override so isolation of the per-key value-set check
    -- isn't masked by the cross-param check.
    if key == "TCS" and (val == "LINEAR" or val == "BT2100LINPQ"
                          or val == "BT2100LINHLG" or val == "ST2065-1") then
      for i, p in ipairs(parts) do
        if p:sub(1, 6) == "depth=" then
          parts[i] = "depth=16f"
        end
      end
    end
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

-- ───────────────────────────────────────────────────────────────────────────
-- Phase 6.C.D.2 — ST 2110-20 raw video fmtp non-enum value forms +
-- §7.3 flag-only `interlace` / `segmented`. Six parameters carry value
-- forms (integer ranges, fractions in lowest terms, fixed patterns)
-- rather than enumerated sets; two are bare-attribute flags.

describe("ST 2110-20 raw video fmtp — non-enum value forms", function()

  local RAW_MEDIA  = "m=video 30000 RTP/AVP 96"
  local RAW_RTPMAP = "a=rtpmap:96 raw/90000"

  -- Build a raw fmtp where one required param is replaced (or one
  -- optional param appended) with the given value. Mirrors the
  -- helper in the enum block but parameter list is the complete §7.2
  -- required set so optional params are appended.
  local REQUIRED_PARAMS = {
    "sampling=YCbCr-4:2:2", "width=1920", "height=1080",
    "exactframerate=60000/1001", "depth=10", "colorimetry=BT709",
    "PM=2110GPM", "SSN=ST2110-20:2022", "TP=2110TPN",
  }

  local function fmtp_with(key, val)
    local parts = {}
    local replaced = false
    for _, p in ipairs(REQUIRED_PARAMS) do
      if p:sub(1, #key + 1) == (key .. "=") then
        parts[#parts + 1] = key .. "=" .. val
        replaced = true
      else
        parts[#parts + 1] = p
      end
    end
    if not replaced then
      parts[#parts + 1] = key .. "=" .. val
    end
    return "a=fmtp:96 " .. table.concat(parts, ";")
  end

  -- Append a bare-flag token (no `=value`) to the complete required set.
  local function fmtp_with_flag(key)
    local parts = {}
    for _, p in ipairs(REQUIRED_PARAMS) do
      parts[#parts + 1] = p
    end
    parts[#parts + 1] = key
    return "a=fmtp:96 " .. table.concat(parts, ";")
  end

  -- ── width / height [ST 2110-20:2022 §7.2] ────────────────────────────
  for _, key in ipairs({ "width", "height" }) do
    describe(("'%s' (integer 1..32767) [ST 2110-20:2022 §7.2]"):format(key),
        function()
      it(("accepts %s=1"):format(key), function()
        assert.is_truthy(st2110.match(build_with_fmtp(
          RAW_MEDIA, RAW_RTPMAP, fmtp_with(key, "1"))))
      end)
      it(("accepts %s=32767 (upper bound)"):format(key), function()
        assert.is_truthy(st2110.match(build_with_fmtp(
          RAW_MEDIA, RAW_RTPMAP, fmtp_with(key, "32767"))))
      end)
      it(("rejects %s=0"):format(key), function()
        local doc, ctx = st2110.match(build_with_fmtp(
          RAW_MEDIA, RAW_RTPMAP, fmtp_with(key, "0")))
        assert.is_nil(doc)
        assert.is_not_nil(finding_for(ctx,
          "st2110-20.a.fmtp." .. key .. "-invalid-value"))
      end)
      it(("rejects %s=32768 (over upper bound)"):format(key), function()
        local doc, ctx = st2110.match(build_with_fmtp(
          RAW_MEDIA, RAW_RTPMAP, fmtp_with(key, "32768")))
        assert.is_nil(doc)
        assert.is_not_nil(finding_for(ctx,
          "st2110-20.a.fmtp." .. key .. "-invalid-value"))
      end)
      it(("rejects non-integer %s"):format(key), function()
        local doc, ctx = st2110.match(build_with_fmtp(
          RAW_MEDIA, RAW_RTPMAP, fmtp_with(key, "abc")))
        assert.is_nil(doc)
        assert.is_not_nil(finding_for(ctx,
          "st2110-20.a.fmtp." .. key .. "-invalid-value"))
      end)
    end)
  end

  -- ── exactframerate [ST 2110-20:2022 §7.2] ────────────────────────────
  describe("'exactframerate' [ST 2110-20:2022 §7.2]", function()
    it("accepts positive integer", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_with("exactframerate", "60"))))
    end)
    it("accepts 30000/1001 (lowest terms)", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_with("exactframerate", "30000/1001"))))
    end)
    it("rejects 0", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_with("exactframerate", "0")))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-20.a.fmtp.exactframerate-invalid-value"))
    end)
    it("rejects 60000/2002 (not in lowest terms)", function()
      -- 60000/2002 reduces to 30000/1001; §7.2 requires lowest terms.
      local doc, ctx = st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_with("exactframerate", "60000/2002")))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-20.a.fmtp.exactframerate-invalid-value"))
    end)
    it("rejects 60/0 (zero denominator)", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_with("exactframerate", "60/0")))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-20.a.fmtp.exactframerate-invalid-value"))
    end)
  end)

  -- ── MAXUDP [ST 2110-20:2022 §7.3 + ST 2110-10 §6.4] ──────────────────
  describe("'MAXUDP' (positive int ≤8960) [ST 2110-20:2022 §7.3]", function()
    it("accepts MAXUDP=1500", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_with("MAXUDP", "1500"))))
    end)
    it("accepts MAXUDP=8960 (upper bound)", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_with("MAXUDP", "8960"))))
    end)
    it("rejects MAXUDP=0", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_with("MAXUDP", "0")))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-20.a.fmtp.MAXUDP-invalid-value"))
    end)
    it("rejects MAXUDP=8961 (over upper bound)", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_with("MAXUDP", "8961")))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-20.a.fmtp.MAXUDP-invalid-value"))
    end)
  end)

  -- ── PAR [ST 2110-20:2022 §7.3] ───────────────────────────────────────
  describe("'PAR' (W:H in lowest terms) [ST 2110-20:2022 §7.3]", function()
    it("accepts PAR=1:1", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_with("PAR", "1:1"))))
    end)
    it("accepts PAR=16:9", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_with("PAR", "16:9"))))
    end)
    it("rejects PAR=2:2 (not in lowest terms)", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_with("PAR", "2:2")))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-20.a.fmtp.PAR-invalid-value"))
    end)
    it("rejects PAR=0:1", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_with("PAR", "0:1")))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-20.a.fmtp.PAR-invalid-value"))
    end)
    it("rejects PAR=16-9 (wrong separator)", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_with("PAR", "16-9")))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-20.a.fmtp.PAR-invalid-value"))
    end)
  end)

  -- ── SSN [ST 2110-20:2022 §7.2] ───────────────────────────────────────
  describe("'SSN' pattern [ST 2110-20:2022 §7.2]", function()
    it("accepts SSN=ST2110-20:2017", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_with("SSN", "ST2110-20:2017"))))
    end)
    it("accepts SSN=ST2110-20:2022", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_with("SSN", "ST2110-20:2022"))))
    end)
    it("rejects SSN=ST2110-20:2019 (no such revision)", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_with("SSN", "ST2110-20:2019")))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-20.a.fmtp.SSN-invalid-value"))
    end)
    it("rejects SSN=wrong (wrong shape)", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_with("SSN", "wrong")))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-20.a.fmtp.SSN-invalid-value"))
    end)
  end)
end)

-- ───────────────────────────────────────────────────────────────────────────
-- Phase 6.C.D.2 (cont.) — ST 2110-20:2022 §7.3 flag-only parameters.
-- `interlace` and `segmented` must be bare-attribute flags, not kv-pairs.

describe("ST 2110-20 raw video fmtp — flag-only [ST 2110-20:2022 §7.3]", function()

  local RAW_MEDIA  = "m=video 30000 RTP/AVP 96"
  local RAW_RTPMAP = "a=rtpmap:96 raw/90000"

  -- Note: tests for `segmented` deliberately also include `interlace`
  -- bare in the fmtp because §7.3 requires it. Cross-parameter SHALL
  -- (segmented-without-interlace) lands in Phase 6.C.E.

  it("accepts bare 'interlace' flag", function()
    assert.is_truthy(st2110.match(build_with_fmtp(
      RAW_MEDIA, RAW_RTPMAP,
      RAW_FMTP_COMPLETE_PT96 .. ";interlace")))
  end)

  it("accepts bare 'segmented' flag (with interlace)", function()
    assert.is_truthy(st2110.match(build_with_fmtp(
      RAW_MEDIA, RAW_RTPMAP,
      RAW_FMTP_COMPLETE_PT96 .. ";interlace;segmented")))
  end)

  it("rejects 'interlace=1' (must be flag, not kv)", function()
    local doc, ctx = st2110.match(build_with_fmtp(
      RAW_MEDIA, RAW_RTPMAP,
      RAW_FMTP_COMPLETE_PT96 .. ";interlace=1"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "st2110-20.a.fmtp.interlace-invalid-value"))
  end)

  it("rejects 'segmented=true' (must be flag, not kv)", function()
    local doc, ctx = st2110.match(build_with_fmtp(
      RAW_MEDIA, RAW_RTPMAP,
      RAW_FMTP_COMPLETE_PT96 .. ";interlace;segmented=true"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "st2110-20.a.fmtp.segmented-invalid-value"))
  end)

  -- NOT-SPEC: library — base tier carries no flag-only narrowing.
  it("base tier accepts 'interlace=anything'", function()
    assert.is_truthy(base.match(build_with_fmtp(
      RAW_MEDIA, RAW_RTPMAP,
      RAW_FMTP_COMPLETE_PT96 .. ";interlace=anything")))
  end)
end)

-- ───────────────────────────────────────────────────────────────────────────
-- Phase 6.C.E — ST 2110-20 raw video fmtp cross-parameter SHALLs.
-- Seven constraints that evaluate a relationship across two or more fmtp
-- parameter values. Ported from the 1.0 parser at parse_sdp.lua:2063-2158
-- to preserve refactor parity.

describe("ST 2110-20 raw video fmtp — cross-parameter SHALLs", function()

  local RAW_MEDIA  = "m=video 30000 RTP/AVP 96"
  local RAW_RTPMAP = "a=rtpmap:96 raw/90000"

  -- Build fmtp from a params table; preserves order via REQUIRED_ORDER
  -- (matches §7.2 listing) and appends any unknown keys at the end.
  local PARAM_ORDER = {
    "sampling", "width", "height", "exactframerate", "depth",
    "colorimetry", "PM", "SSN", "TP", "TCS", "RANGE", "MAXUDP", "PAR",
  }
  local FLAG_KEYS = { "interlace", "segmented" }

  local function fmtp_from(params)
    local parts = {}
    for _, k in ipairs(PARAM_ORDER) do
      local v = params[k]
      if v ~= nil then parts[#parts + 1] = k .. "=" .. tostring(v) end
    end
    for _, k in ipairs(FLAG_KEYS) do
      if params[k] then parts[#parts + 1] = k end
    end
    return "a=fmtp:96 " .. table.concat(parts, ";")
  end

  -- Canonical complete params (mirrors RAW_FMTP_COMPLETE_PT96 but as a
  -- table so per-test overrides are obvious).
  local function defaults()
    return {
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
  end

  -- Apply overrides to defaults() and return a complete params table.
  local function with(overrides)
    local p = defaults()
    for k, v in pairs(overrides) do p[k] = v end
    return p
  end

  -- ── §7.2 SSN-conditional ─────────────────────────────────────────────
  describe("SSN conditional [ST 2110-20:2022 §7.2]", function()
    it("accepts colorimetry=ALPHA + SSN=ST2110-20:2022 (the only allowed pairing)",
        function()
      -- KEY sampling required to make ALPHA legal — §7.4.1 (covered below).
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
          sampling = "KEY", colorimetry = "ALPHA",
          SSN = "ST2110-20:2022",
        })))))
    end)
    it("accepts TCS=ST2115LOGS3 + SSN=ST2110-20:2022", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
          TCS = "ST2115LOGS3", SSN = "ST2110-20:2022",
        })))))
    end)
    it("rejects colorimetry=ALPHA + SSN=ST2110-20:2017 (ALPHA undefined in :2017)",
        function()
      local doc, ctx = st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
          sampling = "KEY", colorimetry = "ALPHA",
          SSN = "ST2110-20:2017",
        }))))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-20.a.fmtp.ssn-required-for-2022-only-values"))
    end)
    it("rejects TCS=ST2115LOGS3 + SSN=ST2110-20:2017", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
          TCS = "ST2115LOGS3", SSN = "ST2110-20:2017",
        }))))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-20.a.fmtp.ssn-required-for-2022-only-values"))
    end)
  end)

  -- ── §7.3 BT2100 + FULLPROTECT forbidden ──────────────────────────────
  describe("BT2100 colorimetry + RANGE=FULLPROTECT [ST 2110-20:2022 §7.3]",
      function()
    it("accepts BT2100 + RANGE=NARROW", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
          colorimetry = "BT2100", RANGE = "NARROW",
        })))))
    end)
    it("accepts BT2100 + RANGE=FULL", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
          colorimetry = "BT2100", RANGE = "FULL",
        })))))
    end)
    it("rejects BT2100 + RANGE=FULLPROTECT", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
          colorimetry = "BT2100", RANGE = "FULLPROTECT",
        }))))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-20.a.fmtp.bt2100-range-fullprotect-forbidden"))
    end)
    -- NOT-SPEC: non-BT2100 colorimetry is unaffected.
    it("accepts BT709 + RANGE=FULLPROTECT (other colorimetries unrestricted)",
        function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
          colorimetry = "BT709", RANGE = "FULLPROTECT",
        })))))
    end)
  end)

  -- ── §7.3 segmented requires interlace ────────────────────────────────
  describe("'segmented' requires 'interlace' [ST 2110-20:2022 §7.3]", function()
    it("accepts segmented + interlace (both present)", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
          interlace = true, segmented = true,
        })))))
    end)
    it("rejects segmented without interlace", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({ segmented = true }))))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-20.a.fmtp.segmented-requires-interlace"))
    end)
    -- NOT-SPEC: interlace alone is fine.
    it("accepts interlace without segmented", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({ interlace = true })))))
    end)
  end)

  -- ── §6.3.3 PM=2110BPM forbids MAXUDP ─────────────────────────────────
  describe("PM=2110BPM forbids MAXUDP [ST 2110-20:2022 §6.3.3]", function()
    it("accepts PM=2110GPM with MAXUDP=1500", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
          PM = "2110GPM", MAXUDP = "1500",
        })))))
    end)
    it("accepts PM=2110BPM without MAXUDP", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({ PM = "2110BPM" })))))
    end)
    it("rejects PM=2110BPM with MAXUDP=1500", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
          PM = "2110BPM", MAXUDP = "1500",
        }))))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-20.a.fmtp.bpm-with-maxudp-forbidden"))
    end)
  end)

  -- ── §7.4.1 KEY sampling ──────────────────────────────────────────────
  describe("sampling=KEY [ST 2110-20:2022 §7.4.1]", function()
    it("accepts sampling=KEY with colorimetry=ALPHA + no TCS", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
          sampling = "KEY", colorimetry = "ALPHA",
        })))))
    end)
    it("rejects sampling=KEY with colorimetry=BT709 (must be ALPHA)",
        function()
      local doc, ctx = st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
          sampling = "KEY", colorimetry = "BT709",
        }))))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-20.a.fmtp.key-requires-alpha-colorimetry"))
    end)
    it("rejects sampling=KEY when TCS is signaled", function()
      -- Pair with the required ALPHA colorimetry so the KEY-requires-ALPHA
      -- check passes and we isolate the TCS prohibition.
      local doc, ctx = st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
          sampling = "KEY", colorimetry = "ALPHA", TCS = "SDR",
        }))))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-20.a.fmtp.key-forbids-tcs"))
    end)
  end)

  -- ── §6.2.5 4:2:0 sampling progressive only ───────────────────────────
  describe("4:2:0 sampling forbids interlace [ST 2110-20:2022 §6.2.5]",
      function()
    it("accepts 4:2:0 sampling progressive (no interlace)", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
          sampling = "YCbCr-4:2:0",
        })))))
    end)
    it("rejects YCbCr-4:2:0 + interlace", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
          sampling = "YCbCr-4:2:0", interlace = true,
        }))))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-20.a.fmtp.subsampling-420-with-interlace-forbidden"))
    end)
    it("rejects CLYCbCr-4:2:0 + interlace", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
          sampling = "CLYCbCr-4:2:0", interlace = true,
        }))))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-20.a.fmtp.subsampling-420-with-interlace-forbidden"))
    end)
    it("rejects ICtCp-4:2:0 + interlace", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
          sampling = "ICtCp-4:2:0", interlace = true,
        }))))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-20.a.fmtp.subsampling-420-with-interlace-forbidden"))
    end)
    -- NOT-SPEC: 4:2:2 / 4:4:4 are unrestricted by §6.2.5.
    it("accepts 4:2:2 sampling + interlace (not 4:2:0)", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
          sampling = "YCbCr-4:2:2", interlace = true,
        })))))
    end)
  end)

  -- NOT-SPEC: library — base tier carries no cross-parameter narrowing.
  it("base tier accepts all cross-param violations together", function()
    -- Aggregate violations: sampling=KEY+TCS, PM=BPM+MAXUDP, BT2100+FULLPROTECT,
    -- segmented without interlace, 4:2:0 with interlace. Base tier passes.
    assert.is_truthy(base.match(build_with_fmtp(
      RAW_MEDIA, RAW_RTPMAP,
      "a=fmtp:96 sampling=YCbCr-4:2:0;width=1920;height=1080;"
      .. "exactframerate=60;depth=10;colorimetry=BT2100;PM=2110BPM;"
      .. "SSN=ST2110-20:2017;TP=2110TPN;TCS=ST2115LOGS3;"
      .. "RANGE=FULLPROTECT;MAXUDP=1500;interlace;segmented")))
  end)
end)

-- ───────────────────────────────────────────────────────────────────────────
-- Phase 6.C.F — ST 2110-20 raw video fmtp 1.0-gap closes.
-- Five cross-parameter SHALLs normatively in ST 2110-20:2022 but not
-- enforced by the 1.0 parser. Grounded by CLAUDE.md strictness polarity
-- #3 (defined value forms): §6.2.5 Table 3 defines the 4:2:0/depth
-- pairing; §7.6 TCS rows include `(depth=16f)` parentheticals. Inventory
-- rows 61, 115, 116, 117, 118.

describe("ST 2110-20 raw video fmtp — 1.0-gap closes (Phase 6.C.F)",
    function()

  local RAW_MEDIA  = "m=video 30000 RTP/AVP 96"
  local RAW_RTPMAP = "a=rtpmap:96 raw/90000"

  -- Re-use the table-based builder structure for clarity.
  local PARAM_ORDER = {
    "sampling", "width", "height", "exactframerate", "depth",
    "colorimetry", "PM", "SSN", "TP", "TCS",
  }

  local function fmtp_from(params)
    local parts = {}
    for _, k in ipairs(PARAM_ORDER) do
      local v = params[k]
      if v ~= nil then parts[#parts + 1] = k .. "=" .. tostring(v) end
    end
    return "a=fmtp:96 " .. table.concat(parts, ";")
  end

  local function defaults()
    return {
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
  end

  local function with(overrides)
    local p = defaults()
    for k, v in pairs(overrides) do p[k] = v end
    return p
  end

  -- ── §6.2.5 Table 3: 4:2:0 sampling permits depth ∈ {8, 10, 12} ───────
  describe("4:2:0 sampling × depth [ST 2110-20:2022 §6.2.5 Table 3]",
      function()
    -- Accept cases: every (4:2:0-sampling, allowed-depth) pair.
    local SAMPLING_420 = { "YCbCr-4:2:0", "CLYCbCr-4:2:0", "ICtCp-4:2:0" }
    local ALLOWED_DEPTHS = { "8", "10", "12" }
    for _, s in ipairs(SAMPLING_420) do
      for _, d in ipairs(ALLOWED_DEPTHS) do
        it(("accepts %s + depth=%s"):format(s, d), function()
          assert.is_truthy(st2110.match(build_with_fmtp(
            RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
              sampling = s, depth = d,
            })))))
        end)
      end
    end

    -- Reject cases: every (4:2:0-sampling, forbidden-depth) pair.
    local FORBIDDEN_DEPTHS = { "16", "16f" }
    for _, s in ipairs(SAMPLING_420) do
      for _, d in ipairs(FORBIDDEN_DEPTHS) do
        it(("rejects %s + depth=%s"):format(s, d), function()
          local doc, ctx = st2110.match(build_with_fmtp(
            RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
              sampling = s, depth = d,
            }))))
          assert.is_nil(doc)
          assert.is_not_nil(finding_for(ctx,
            "st2110-20.a.fmtp.subsampling-420-depth-restricted"))
        end)
      end
    end

    -- NOT-SPEC: non-4:2:0 sampling is unrestricted by Table 3.
    it("accepts non-4:2:0 sampling with depth=16f", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
          sampling = "YCbCr-4:2:2", depth = "16f",
          -- 16f also requires a floating-point TCS (§7.6) — pair them so
          -- this test isolates the §6.2.5 Table 3 narrowing only.
          TCS = "LINEAR",
        })))))
    end)
  end)

  -- ── §7.6 TCS rows: TCS=floating-point requires depth=16f ─────────────
  describe("TCS floating-point × depth=16f [ST 2110-20:2022 §7.6]",
      function()
    -- Each TCS value in this set is row-defined with `(depth=16f)`.
    local TCS_FLOATING_POINT = {
      { "LINEAR",       "tcs-linear-requires-depth-16f" },
      { "BT2100LINPQ",  "tcs-bt2100linpq-requires-depth-16f" },
      { "BT2100LINHLG", "tcs-bt2100linhlg-requires-depth-16f" },
      { "ST2065-1",     "tcs-st2065-1-requires-depth-16f" },
    }

    for _, p in ipairs(TCS_FLOATING_POINT) do
      local tcs, id_slug = p[1], p[2]

      it(("accepts TCS=%s + depth=16f"):format(tcs), function()
        assert.is_truthy(st2110.match(build_with_fmtp(
          RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
            TCS = tcs, depth = "16f",
          })))))
      end)

      for _, bad_depth in ipairs({ "8", "10", "12", "16" }) do
        it(("rejects TCS=%s + depth=%s"):format(tcs, bad_depth),
            function()
          local doc, ctx = st2110.match(build_with_fmtp(
            RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
              TCS = tcs, depth = bad_depth,
            }))))
          assert.is_nil(doc)
          assert.is_not_nil(finding_for(ctx,
            "st2110-20.a.fmtp." .. id_slug))
        end)
      end
    end

    -- NOT-SPEC: non-floating-point TCS values are unrestricted by §7.6.
    it("accepts TCS=SDR + depth=10 (not a floating-point TCS row)",
        function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
          TCS = "SDR", depth = "10",
        })))))
    end)

    -- NOT-SPEC: TCS absent → check inert.
    it("accepts absent TCS with arbitrary depth", function()
      -- Drop TCS by passing the default (no TCS key in the params).
      local p = defaults()
      p.depth = "10"
      assert.is_truthy(st2110.match(build_with_fmtp(
        RAW_MEDIA, RAW_RTPMAP, fmtp_from(p))))
    end)
  end)

  -- NOT-SPEC: library — base tier carries no 6.C.F narrowing.
  it("base tier accepts 4:2:0 + depth=16 and TCS=LINEAR + depth=10",
      function()
    assert.is_truthy(base.match(build_with_fmtp(
      RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
        sampling = "YCbCr-4:2:0", depth = "16",
      })))))
    assert.is_truthy(base.match(build_with_fmtp(
      RAW_MEDIA, RAW_RTPMAP, fmtp_from(with({
        TCS = "LINEAR", depth = "10",
      })))))
  end)
end)

-- ───────────────────────────────────────────────────────────────────────────
-- Phase 6.C.G.1 — ST 2110-22 jxsv fmtp required-param presence + per-key
-- value-set narrowings. Following the same shape as the 6.C.C / 6.C.D
-- structure used for -20 raw video.

describe("ST 2110-22 jxsv fmtp — required parameters", function()

  local JXSV_MEDIA  = "m=video 30000 RTP/AVP 96"
  local JXSV_RTPMAP = "a=rtpmap:96 jxsv/90000"

  -- Required: width, height, TP (ST 2110-22:2022 §7.2 Table 1) and
  -- packetmode (RFC 9134 §7.1).
  local REQUIRED = {
    width      = "1920",
    height     = "1080",
    TP         = "2110TPN",
    packetmode = "0",
  }

  local PARAM_REF = {
    width      = "ST 2110-22:2022 §7.2",
    height     = "ST 2110-22:2022 §7.2",
    TP         = "ST 2110-22:2022 §7.2",
    packetmode = "RFC 9134 §7.1",
  }

  local ORDER = { "width", "height", "TP", "packetmode" }

  local function fmtp_omitting(key_to_omit)
    local parts = {}
    for _, k in ipairs(ORDER) do
      if k ~= key_to_omit then
        parts[#parts + 1] = k .. "=" .. REQUIRED[k]
      end
    end
    return "a=fmtp:96 " .. table.concat(parts, ";")
  end

  it("accepts jxsv fmtp with every required parameter present", function()
    assert.is_truthy(st2110.match(build_with_fmtp(
      JXSV_MEDIA, JXSV_RTPMAP, JXSV_FMTP_COMPLETE_PT96)))
  end)

  for _, key in ipairs(ORDER) do
    it(("rejects jxsv fmtp missing '%s' [%s]"):format(key, PARAM_REF[key]),
        function()
      local doc, ctx = st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP, fmtp_omitting(key)))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-22.a.fmtp." .. key .. "-required"))
    end)
  end

  -- NOT-SPEC: library — required-param check is scoped to jxsv. Other
  -- essences have their own required sets (or none).
  it("does NOT require jxsv params for raw (different essence)", function()
    assert.is_truthy(st2110.match(build_with_fmtp(
      "m=video 30000 RTP/AVP 96",
      "a=rtpmap:96 raw/90000",
      RAW_FMTP_COMPLETE_PT96)))
  end)

  it("rejects jxsv video with no a=fmtp at all", function()
    local doc, ctx = st2110.match(build(JXSV_MEDIA, JXSV_RTPMAP))
    assert.is_nil(doc)
    -- The first missing-param finding identifies the failure mode
    -- (width is first in ORDER).
    assert.is_not_nil(finding_for(ctx,
      "st2110-22.a.fmtp.width-required"))
  end)
end)

describe("ST 2110-22 jxsv fmtp — enum value sets", function()

  local JXSV_MEDIA  = "m=video 30000 RTP/AVP 96"
  local JXSV_RTPMAP = "a=rtpmap:96 jxsv/90000"

  -- Build a complete jxsv fmtp with one key overridden (or appended for
  -- optional keys). Mirrors the -20 enum helper.
  local function jxsv_fmtp_with(key, val)
    local parts = { "width=1920", "height=1080", "TP=2110TPN",
                    "packetmode=0" }
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

  -- Per-key permitted values, lifted from JXSV_ENUM_VALUES in
  -- parse_sdp/grammar/st2110.lua. Tests cover each value individually
  -- so any regression on the per-key set is caught.
  local ENUM_VALUES = {
    sampling = {
      "YCbCr-4:4:4", "YCbCr-4:2:2", "YCbCr-4:2:0",
      "CLYCbCr-4:4:4", "CLYCbCr-4:2:2", "CLYCbCr-4:2:0",
      "ICtCp-4:4:4", "ICtCp-4:2:2", "ICtCp-4:2:0",
      "RGB", "XYZ", "KEY", "UNSPECIFIED",
    },
    colorimetry = {
      "BT601-5", "BT709-2", "SMPTE240M",
      "BT601", "BT709", "BT2020", "BT2100",
      "ST2065-1", "ST2065-3", "XYZ", "UNSPECIFIED",
    },
    TCS       = { "SDR", "PQ", "HLG", "UNSPECIFIED" },
    RANGE     = { "NARROW", "FULLPROTECT", "FULL" },
    TP        = { "2110TPN", "2110TPNL", "2110TPW" },
    transmode = { "0", "1" },
    profile   = {
      "Unrestricted", "Light422.10", "Light444.12",
      "LightSubline422.10", "LightSubline444.12",
      "Main422.10", "Main444.12", "High444.12",
      "MLS.12",
      "LightBayer", "MainBayer", "HighBayer", "MLSBayer",
    },
    level = {
      "Unrestricted", "1k-1", "2k-1",
      "4k-1", "4k-2", "4k-3",
      "8k-1", "8k-2", "8k-3",
      "16k-1", "16k-2", "16k-3",
    },
    sublevel = {
      "Unrestricted", "Full", "Sublev12bpp", "Sublev9bpp",
      "Sublev6bpp", "Sublev4bpp", "Sublev3bpp", "Sublev2bpp",
    },
  }

  local SPEC_REF = {
    sampling    = "RFC 9134 §7.1",
    colorimetry = "RFC 9134 §7.1",
    TCS         = "RFC 9134 §7.1",
    RANGE       = "RFC 9134 §7.1",
    TP          = "ST 2110-22:2022 §5.3",
    transmode   = "RFC 9134 §7.1",
    profile     = "RFC 9134 §7.1",
    level       = "RFC 9134 §7.1",
    sublevel    = "RFC 9134 §7.1",
  }

  local KEY_ORDER = {
    "TP", "sampling", "colorimetry", "TCS", "RANGE",
    "transmode", "profile", "level", "sublevel",
  }

  for _, key in ipairs(KEY_ORDER) do
    describe(("'%s' [%s]"):format(key, SPEC_REF[key]), function()
      for _, v in ipairs(ENUM_VALUES[key]) do
        it(("accepts %s=%s"):format(key, v), function()
          assert.is_truthy(st2110.match(build_with_fmtp(
            JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with(key, v))))
        end)
      end
      it(("rejects %s=BOGUS"):format(key), function()
        local doc, ctx = st2110.match(build_with_fmtp(
          JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with(key, "BOGUS")))
        assert.is_nil(doc)
        assert.is_not_nil(finding_for(ctx,
          "st2110-22.a.fmtp." .. key .. "-invalid-value"))
      end)
    end)
  end

  -- Spec-divergence-from-1.0 sanity tests. The grammar tier follows
  -- RFC 9134 §7.1 verbatim; values 1.0 accepted but RFC 9134 omits
  -- must now be rejected, and values RFC 9134 permits but 1.0 rejected
  -- must now be accepted.
  describe("RFC 9134 §7.1 vs 1.0 enum divergence", function()
    it("rejects colorimetry=ALPHA on jxsv (RFC 9134 omits ALPHA)",
        function()
      local doc, ctx = st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with("colorimetry", "ALPHA")))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-22.a.fmtp.colorimetry-invalid-value"))
    end)
    it("accepts colorimetry=BT601-5 on jxsv (RFC 9134 permits)",
        function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with("colorimetry", "BT601-5"))))
    end)
    it("rejects TCS=LINEAR on jxsv (RFC 9134 omits)", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with("TCS", "LINEAR")))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-22.a.fmtp.TCS-invalid-value"))
    end)
    it("rejects TCS=ST2115LOGS3 on jxsv (RFC 9134 omits)", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with("TCS", "ST2115LOGS3")))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-22.a.fmtp.TCS-invalid-value"))
    end)
    it("accepts sampling=UNSPECIFIED on jxsv (RFC 9134 permits)",
        function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with("sampling", "UNSPECIFIED"))))
    end)
  end)
end)

describe("ST 2110-22 jxsv fmtp — non-enum value forms", function()

  local JXSV_MEDIA  = "m=video 30000 RTP/AVP 96"
  local JXSV_RTPMAP = "a=rtpmap:96 jxsv/90000"

  -- Same builder shape as the enum block, with `key` substitution.
  local function jxsv_fmtp_with(key, val)
    local parts = { "width=1920", "height=1080", "TP=2110TPN",
                    "packetmode=0" }
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

  -- ── width / height [ST 2110-22:2022 §7.2 + RFC 9134 §7.1] ────────────
  for _, key in ipairs({ "width", "height" }) do
    describe(("'%s' (integer 1..32767) [ST 2110-22:2022 §7.2]")
                :format(key), function()
      it(("accepts %s=1"):format(key), function()
        assert.is_truthy(st2110.match(build_with_fmtp(
          JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with(key, "1"))))
      end)
      it(("accepts %s=32767"):format(key), function()
        assert.is_truthy(st2110.match(build_with_fmtp(
          JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with(key, "32767"))))
      end)
      it(("rejects %s=0"):format(key), function()
        local doc, ctx = st2110.match(build_with_fmtp(
          JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with(key, "0")))
        assert.is_nil(doc)
        assert.is_not_nil(finding_for(ctx,
          "st2110-22.a.fmtp." .. key .. "-invalid-value"))
      end)
      it(("rejects %s=32768"):format(key), function()
        local doc, ctx = st2110.match(build_with_fmtp(
          JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with(key, "32768")))
        assert.is_nil(doc)
        assert.is_not_nil(finding_for(ctx,
          "st2110-22.a.fmtp." .. key .. "-invalid-value"))
      end)
    end)
  end

  -- ── packetmode / depth / exactframerate / MAXUDP / CMAX / SSN ────────
  describe("'depth' positive integer [RFC 9134 §7.1]", function()
    it("accepts depth=10", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with("depth", "10"))))
    end)
    it("accepts depth=8 / 12 / 16 (RFC 9134 'typical' examples)",
        function()
      for _, d in ipairs({ "8", "12", "16" }) do
        assert.is_truthy(st2110.match(build_with_fmtp(
          JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with("depth", d))))
      end
    end)
    it("rejects depth=0", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with("depth", "0")))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-22.a.fmtp.depth-invalid-value"))
    end)
    -- NOT-SPEC: library — RFC 9134 §7.1 doesn't close the depth enum,
    -- so values 1.0 rejects for raw (e.g. "13") are accepted for jxsv.
    it("accepts depth=13 (RFC 9134 doesn't close the set)", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with("depth", "13"))))
    end)
  end)

  describe("'exactframerate' [RFC 9134 §7.1]", function()
    it("accepts integer", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with("exactframerate", "30"))))
    end)
    it("accepts 30000/1001 (lowest terms)", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP,
        jxsv_fmtp_with("exactframerate", "30000/1001"))))
    end)
    it("rejects 60000/2002 (not lowest terms)", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP,
        jxsv_fmtp_with("exactframerate", "60000/2002")))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-22.a.fmtp.exactframerate-invalid-value"))
    end)
  end)

  describe("'MAXUDP' (positive int ≤ 8960) [ST 2110-10 §6.4]",
      function()
    it("accepts MAXUDP=8960", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with("MAXUDP", "8960"))))
    end)
    it("rejects MAXUDP=8961", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with("MAXUDP", "8961")))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-22.a.fmtp.MAXUDP-invalid-value"))
    end)
  end)

  describe("'CMAX' (integer) [ST 2110-21:2022 §8.2]", function()
    it("accepts CMAX=5000", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with("CMAX", "5000"))))
    end)
    it("rejects CMAX=abc (non-integer)", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with("CMAX", "abc")))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-22.a.fmtp.CMAX-invalid-value"))
    end)
  end)

  describe("'SSN' [ST 2110-22:2022 §7.2]", function()
    it("accepts SSN=ST2110-22:2019", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with("SSN", "ST2110-22:2019"))))
    end)
    it("accepts SSN=ST2110-22:2022", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with("SSN", "ST2110-22:2022"))))
    end)
    it("rejects SSN=ST2110-20:2022 (wrong subtype)", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP, jxsv_fmtp_with("SSN", "ST2110-20:2022")))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-22.a.fmtp.SSN-invalid-value"))
    end)
  end)
end)

describe("ST 2110-22 jxsv fmtp — flag-only [RFC 9134 §7.1]", function()

  local JXSV_MEDIA  = "m=video 30000 RTP/AVP 96"
  local JXSV_RTPMAP = "a=rtpmap:96 jxsv/90000"

  it("accepts bare 'interlace' flag", function()
    assert.is_truthy(st2110.match(build_with_fmtp(
      JXSV_MEDIA, JXSV_RTPMAP,
      JXSV_FMTP_COMPLETE_PT96 .. ";interlace")))
  end)

  it("accepts bare 'segmented' flag (with interlace)", function()
    assert.is_truthy(st2110.match(build_with_fmtp(
      JXSV_MEDIA, JXSV_RTPMAP,
      JXSV_FMTP_COMPLETE_PT96 .. ";interlace;segmented")))
  end)

  it("rejects 'interlace=1' (must be flag, not kv)", function()
    local doc, ctx = st2110.match(build_with_fmtp(
      JXSV_MEDIA, JXSV_RTPMAP,
      JXSV_FMTP_COMPLETE_PT96 .. ";interlace=1"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "st2110-22.a.fmtp.interlace-invalid-value"))
  end)

  it("rejects 'segmented=true'", function()
    local doc, ctx = st2110.match(build_with_fmtp(
      JXSV_MEDIA, JXSV_RTPMAP,
      JXSV_FMTP_COMPLETE_PT96 .. ";interlace;segmented=true"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "st2110-22.a.fmtp.segmented-invalid-value"))
  end)
end)

-- ───────────────────────────────────────────────────────────────────────────
-- Phase 6.C.G.2 — jxsv cross-parameter SHALLs [RFC 9134 §7.1].

describe("ST 2110-22 jxsv fmtp — cross-parameter SHALLs", function()

  local JXSV_MEDIA  = "m=video 30000 RTP/AVP 96"
  local JXSV_RTPMAP = "a=rtpmap:96 jxsv/90000"

  describe("segmented requires interlace [RFC 9134 §7.1]", function()
    it("accepts segmented + interlace (both bare flags)", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP,
        JXSV_FMTP_COMPLETE_PT96 .. ";interlace;segmented")))
    end)
    it("rejects segmented without interlace", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP,
        JXSV_FMTP_COMPLETE_PT96 .. ";segmented"))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-22.a.fmtp.segmented-requires-interlace"))
    end)
    -- NOT-SPEC: interlace alone is fine (no SHALL on the reverse direction).
    it("accepts interlace without segmented", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP,
        JXSV_FMTP_COMPLETE_PT96 .. ";interlace")))
    end)
  end)

  describe("BT2100 colorimetry + RANGE [RFC 9134 §7.1]", function()
    it("accepts colorimetry=BT2100 + RANGE=NARROW", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP,
        JXSV_FMTP_COMPLETE_PT96 .. ";colorimetry=BT2100;RANGE=NARROW")))
    end)
    it("accepts colorimetry=BT2100 + RANGE=FULL", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP,
        JXSV_FMTP_COMPLETE_PT96 .. ";colorimetry=BT2100;RANGE=FULL")))
    end)
    it("rejects colorimetry=BT2100 + RANGE=FULLPROTECT", function()
      local doc, ctx = st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP,
        JXSV_FMTP_COMPLETE_PT96 .. ";colorimetry=BT2100;RANGE=FULLPROTECT"))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-22.a.fmtp.bt2100-range-fullprotect-forbidden"))
    end)
    -- NOT-SPEC: non-BT2100 colorimetries are unrestricted.
    it("accepts colorimetry=BT709 + RANGE=FULLPROTECT", function()
      assert.is_truthy(st2110.match(build_with_fmtp(
        JXSV_MEDIA, JXSV_RTPMAP,
        JXSV_FMTP_COMPLETE_PT96 .. ";colorimetry=BT709;RANGE=FULLPROTECT")))
    end)
  end)

  -- NOT-SPEC: library — base tier carries no jxsv cross-param narrowing.
  it("base tier accepts all jxsv cross-param violations together",
      function()
    assert.is_truthy(base.match(build_with_fmtp(
      JXSV_MEDIA, JXSV_RTPMAP,
      JXSV_FMTP_COMPLETE_PT96
      .. ";segmented;colorimetry=BT2100;RANGE=FULLPROTECT")))
  end)
end)

-- ───────────────────────────────────────────────────────────────────────────
-- Phase 6.C.H — ST 2110-30 / -31 audio channel-order syntax. Optional fmtp
-- parameter on L16 / L24 / AM824 audio. RFC 3190 §6 form
-- `<convention>.<order>`; SMPTE2110 convention requires
-- `(<group>[,<group>...])` with each group from §6.2.2 Table 1, or a
-- Unn track symbol (U01–U64), or AES3 (AM824 only per ST 2110-31 §6.2).

describe("ST 2110-30 / -31 audio channel-order [ST 2110-30:2025 §6.2.2]",
    function()

  local function audio_sdp(rtpmap_line, fmtp_line)
    return table.concat({
      "v=0",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=Test",
      "t=0 0",
      "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      "m=audio 30000 RTP/AVP 96",
      "c=IN IP4 239.0.0.1/64",
      rtpmap_line,
      fmtp_line,
      "a=ptime:1",
      "a=mediaclk:direct=0",
    }, "\r\n") .. "\r\n"
  end

  -- ── Accept cases (SMPTE2110 convention, every Table 1 group) ─────────
  for _, group in ipairs({ "M", "DM", "ST", "LtRt", "51", "71", "222", "SGRP" }) do
    it(("accepts L24 channel-order SMPTE2110.(%s)"):format(group), function()
      assert.is_truthy(st2110.match(audio_sdp(
        "a=rtpmap:96 L24/48000/2",
        ("a=fmtp:96 channel-order=SMPTE2110.(%s)"):format(group))))
    end)
  end

  it("accepts SMPTE2110.(ST,M) — multiple groups", function()
    assert.is_truthy(st2110.match(audio_sdp(
      "a=rtpmap:96 L24/48000/3",
      "a=fmtp:96 channel-order=SMPTE2110.(ST,M)")))
  end)

  -- Unn tokens — sample the range bounds.
  for _, tok in ipairs({ "U01", "U64" }) do
    it(("accepts SMPTE2110.(%s) — Unn track symbol"):format(tok),
        function()
      assert.is_truthy(st2110.match(audio_sdp(
        "a=rtpmap:96 L24/48000/1",
        ("a=fmtp:96 channel-order=SMPTE2110.(%s)"):format(tok))))
    end)
  end

  -- ── AES3 — AM824-only (ST 2110-31:2022 §6.2 Table 2) ─────────────────
  it("accepts AES3 group on AM824", function()
    assert.is_truthy(st2110.match(audio_sdp(
      "a=rtpmap:96 AM824/48000/2",
      "a=fmtp:96 channel-order=SMPTE2110.(AES3)")))
  end)

  it("rejects AES3 group on L24 (AES3 requires AM824)", function()
    local doc, ctx = st2110.match(audio_sdp(
      "a=rtpmap:96 L24/48000/2",
      "a=fmtp:96 channel-order=SMPTE2110.(AES3)"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "st2110-31.a.fmtp.channel-order-aes3-requires-am824"))
  end)

  it("rejects AES3 group on L16", function()
    local doc, ctx = st2110.match(audio_sdp(
      "a=rtpmap:96 L16/48000/2",
      "a=fmtp:96 channel-order=SMPTE2110.(AES3)"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "st2110-31.a.fmtp.channel-order-aes3-requires-am824"))
  end)

  -- ── Reject malformations under SMPTE2110 convention ──────────────────
  it("rejects unknown group symbol BOGUS", function()
    local doc, ctx = st2110.match(audio_sdp(
      "a=rtpmap:96 L24/48000/2",
      "a=fmtp:96 channel-order=SMPTE2110.(BOGUS)"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "st2110-30.a.fmtp.channel-order-invalid"))
  end)

  it("rejects out-of-range Unn (U00)", function()
    local doc, ctx = st2110.match(audio_sdp(
      "a=rtpmap:96 L24/48000/1",
      "a=fmtp:96 channel-order=SMPTE2110.(U00)"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "st2110-30.a.fmtp.channel-order-invalid"))
  end)

  it("rejects out-of-range Unn (U65)", function()
    local doc, ctx = st2110.match(audio_sdp(
      "a=rtpmap:96 L24/48000/1",
      "a=fmtp:96 channel-order=SMPTE2110.(U65)"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "st2110-30.a.fmtp.channel-order-invalid"))
  end)

  it("rejects missing parentheses under SMPTE2110 convention", function()
    local doc, ctx = st2110.match(audio_sdp(
      "a=rtpmap:96 L24/48000/2",
      "a=fmtp:96 channel-order=SMPTE2110.ST"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "st2110-30.a.fmtp.channel-order-invalid"))
  end)

  it("rejects RFC 3190 form without dot separator", function()
    local doc, ctx = st2110.match(audio_sdp(
      "a=rtpmap:96 L24/48000/2",
      "a=fmtp:96 channel-order=NoDotHere"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "st2110-30.a.fmtp.channel-order-invalid"))
  end)

  -- ── Non-SMPTE2110 conventions: §6.2.2 is silent (accept structurally) ─
  it("accepts non-SMPTE2110 convention with arbitrary order (spec silent)",
      function()
    -- NOT-SPEC: §6.2.2 only constrains the SMPTE2110 convention. Any
    -- structurally-valid RFC 3190 form is accepted otherwise.
    assert.is_truthy(st2110.match(audio_sdp(
      "a=rtpmap:96 L24/48000/2",
      "a=fmtp:96 channel-order=Custom.MyArbitraryToken")))
  end)

  -- ── Channel-order absent: optional (no SHALL on presence) ────────────
  it("accepts audio fmtp without channel-order (optional)", function()
    -- NOT-SPEC: §6.2.2 defines channel-order as optional with absence
    -- interpreted as "Undefined".
    assert.is_truthy(st2110.match(audio_sdp(
      "a=rtpmap:96 L24/48000/2",
      "a=fmtp:96 dummy=value")))
  end)

  -- ── NOT-SPEC: base tier carries no channel-order narrowing ───────────
  it("base tier accepts AES3 on L24 (no -30/-31 narrowing in base)",
      function()
    assert.is_truthy(base.match(audio_sdp(
      "a=rtpmap:96 L24/48000/2",
      "a=fmtp:96 channel-order=SMPTE2110.(AES3)")))
  end)
end)

-- ───────────────────────────────────────────────────────────────────────────
-- Phase 6.C.I — ST 2110-31:2022 §6.1: AM824 rtpmap channel count must be
-- even. AM824 transports AES3 signals; each AES3 signal contains two
-- sequences of AES3 Subframes, so <nchan> is always an even integer.

describe("ST 2110-31 AM824 rtpmap channel parity [ST 2110-31:2022 §6.1]",
    function()

  local function am824_sdp(rtpmap_line)
    return table.concat({
      "v=0",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=Test",
      "t=0 0",
      "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      "m=audio 30000 RTP/AVP 96",
      "c=IN IP4 239.0.0.1/64",
      rtpmap_line,
      "a=ptime:1",
      "a=mediaclk:direct=0",
    }, "\r\n") .. "\r\n"
  end

  -- Accept cases: every even channel count (sample the bounds + a middle).
  for _, ch in ipairs({ "2", "4", "8", "16", "32", "64" }) do
    it(("accepts AM824 channels=%s (even)"):format(ch), function()
      assert.is_truthy(st2110.match(am824_sdp(
        "a=rtpmap:96 AM824/48000/" .. ch)))
    end)
  end

  -- Reject cases: every odd channel count.
  for _, ch in ipairs({ "1", "3", "5", "7", "15" }) do
    it(("rejects AM824 channels=%s (odd)"):format(ch), function()
      local doc, ctx = st2110.match(am824_sdp(
        "a=rtpmap:96 AM824/48000/" .. ch))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-31.a.rtpmap.am824-channels-must-be-even"))
    end)
  end

  -- NOT-SPEC: library — narrowing is AM824-only.
  it("does NOT enforce parity on L24 (different encoding)", function()
    assert.is_truthy(st2110.match(am824_sdp(
      "a=rtpmap:96 L24/48000/1")))
  end)

  it("does NOT enforce parity on L16 (different encoding)", function()
    assert.is_truthy(st2110.match(am824_sdp(
      "a=rtpmap:96 L16/48000/1")))
  end)

  -- NOT-SPEC: base tier carries no -31 narrowing.
  it("base tier accepts AM824 with odd channels", function()
    assert.is_truthy(base.match(am824_sdp(
      "a=rtpmap:96 AM824/48000/3")))
  end)
end)

-- ───────────────────────────────────────────────────────────────────────────
-- Phase 6.C.J — ST 2110-41 Fast Metadata fmtp.
-- §6: SSN required (`ST2110-41:2024` only); DIT optional with comma-
-- separated uppercase hex tokens. §5.4: MAXUDP forbidden.

describe("ST 2110-41 fmtp [ST 2110-41:2024 §6 + §5.4]", function()

  local function st2110_41_sdp(fmtp_line)
    return table.concat({
      "v=0",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=Test",
      "t=0 0",
      "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      "m=video 30000 RTP/AVP 96",
      "c=IN IP4 239.0.0.1/64",
      "a=rtpmap:96 ST2110-41/27000000",  -- Data-Item-defined rate per §5.3
      fmtp_line,
      "a=mediaclk:direct=0",
    }, "\r\n") .. "\r\n"
  end

  -- ── SSN: required + value form [§6] ──────────────────────────────────
  describe("SSN required [§6]", function()
    it("accepts SSN=ST2110-41:2024", function()
      assert.is_truthy(st2110.match(st2110_41_sdp(
        "a=fmtp:96 SSN=ST2110-41:2024")))
    end)
    it("rejects fmtp without SSN", function()
      local doc, ctx = st2110.match(st2110_41_sdp(
        "a=fmtp:96 DIT=100,2000A1"))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-41.a.fmtp.SSN-required"))
    end)
    it("rejects SSN=ST2110-41:2019 (no such revision)", function()
      local doc, ctx = st2110.match(st2110_41_sdp(
        "a=fmtp:96 SSN=ST2110-41:2019"))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-41.a.fmtp.SSN-invalid-value"))
    end)
    it("rejects SSN=ST2110-20:2022 (wrong subtype)", function()
      local doc, ctx = st2110.match(st2110_41_sdp(
        "a=fmtp:96 SSN=ST2110-20:2022"))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-41.a.fmtp.SSN-invalid-value"))
    end)
  end)

  -- ── DIT: optional + value form [§6] ──────────────────────────────────
  describe("DIT optional value form [§6]", function()
    it("accepts DIT=100", function()
      assert.is_truthy(st2110.match(st2110_41_sdp(
        "a=fmtp:96 SSN=ST2110-41:2024;DIT=100")))
    end)
    it("accepts DIT=100,2000A1,1013FC,3FFF00 (multiple tokens)", function()
      assert.is_truthy(st2110.match(st2110_41_sdp(
        "a=fmtp:96 SSN=ST2110-41:2024;DIT=100,2000A1,1013FC,3FFF00")))
    end)
    it("rejects DIT=0x100 (forbidden '0x' prefix)", function()
      local doc, ctx = st2110.match(st2110_41_sdp(
        "a=fmtp:96 SSN=ST2110-41:2024;DIT=0x100"))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-41.a.fmtp.DIT-invalid-value"))
    end)
    it("rejects DIT=100a (lowercase hex)", function()
      local doc, ctx = st2110.match(st2110_41_sdp(
        "a=fmtp:96 SSN=ST2110-41:2024;DIT=100a"))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-41.a.fmtp.DIT-invalid-value"))
    end)
    it("rejects DIT=100, 200 (whitespace in list)", function()
      -- Note: the embedded whitespace breaks the kv-pair parse before the
      -- semantic check even runs at the base tier — but the assertion is
      -- on the eventual rejection by the ST 2110 tier, not the path.
      local doc, ctx = st2110.match(st2110_41_sdp(
        "a=fmtp:96 SSN=ST2110-41:2024;DIT=100, 200"))
      assert.is_nil(doc)
      -- Either the base-tier ws rejection OR the -41 DIT-invalid finding
      -- is acceptable; both indicate the value form was caught.
      assert.is_not_nil(
        finding_for(ctx, "st2110-41.a.fmtp.DIT-invalid-value")
        or finding_for(ctx, "sdp.a.fmtp.trailing-semicolon"))
    end)
  end)

  -- ── MAXUDP forbidden [§5.4] ──────────────────────────────────────────
  describe("MAXUDP forbidden [§5.4]", function()
    it("rejects MAXUDP when signaled", function()
      local doc, ctx = st2110.match(st2110_41_sdp(
        "a=fmtp:96 SSN=ST2110-41:2024;MAXUDP=1500"))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "st2110-41.a.fmtp.maxudp-forbidden"))
    end)
    -- NOT-SPEC: MAXUDP-forbidden fires only on -41. On -20 it's a value
    -- check (already covered in 6.C.D.2), not forbidden.
    it("does NOT fire MAXUDP-forbidden on raw video", function()
      -- The -20 raw video MAXUDP value check is permissive when value is
      -- valid; the -41 maxudp-forbidden finding must NOT fire here.
      local doc = st2110.match(build_with_fmtp(
        "m=video 30000 RTP/AVP 96",
        "a=rtpmap:96 raw/90000",
        RAW_FMTP_COMPLETE_PT96 .. ";MAXUDP=1500"))
      assert.is_truthy(doc)
    end)
  end)

  -- ── NOT-SPEC: base tier carries no -41 narrowing ─────────────────────
  it("base tier accepts ST 2110-41 fmtp with no SSN", function()
    assert.is_truthy(base.match(st2110_41_sdp(
      "a=fmtp:96 DIT=100")))
  end)
end)

-- ── Phase 6.D.A — ST 2110-10:2022 §8.2/§8.3 per-media-block presence ────
--
-- §8.2: "All stream descriptions shall have a ts-refclk attribute as
--        specified in IETF RFC 7273 section 4."
-- §8.3: "All stream descriptions shall have a media-level mediaclk
--        attribute as per IETF RFC 7273 section 5."
--
-- Both SHALLs are per-media-section presence requirements. The build
-- helpers include both attributes by default; these tests construct
-- custom SDPs that omit one or the other to exercise the new checks.
--
-- The "media-level" qualifier on §8.3 means a session-level mediaclk
-- does NOT satisfy the SHALL for a media block that lacks its own;
-- §8.2 has no such qualifier (RFC 7273 §4.8 explicitly allows session
-- or media level), so a session-level ts-refclk DOES cover media
-- blocks that don't carry one.

describe("ST 2110-10 — required attribute presence (Phase 6.D.A)", function()

  local function sdp_lines(lines)
    return table.concat(lines, "\r\n") .. "\r\n"
  end

  local TIMING_TS_REFCLK = "a=ts-refclk:localmac=00-11-22-33-44-55"
  local TIMING_MEDIACLK  = "a=mediaclk:sender"

  describe("a=ts-refclk required per media block (§8.2)", function()

    it("accepts a media block that carries a=ts-refclk", function()
      local doc = st2110.match(sdp_lines({
        "v=0",
        "o=- 1 1 IN IP4 192.0.2.1",
        "s=Test",
        "t=0 0",
        "m=video 30000 RTP/AVP 96",
        "c=IN IP4 239.0.0.1/64",
        "a=rtpmap:96 raw/90000",
        RAW_FMTP_COMPLETE_PT96,
        TIMING_TS_REFCLK,
        TIMING_MEDIACLK,
      }))
      assert.is_truthy(doc)
    end)

    it("rejects a media block missing a=ts-refclk", function()
      local doc, ctx = st2110.match(sdp_lines({
        "v=0",
        "o=- 1 1 IN IP4 192.0.2.1",
        "s=Test",
        "t=0 0",
        "m=video 30000 RTP/AVP 96",
        "c=IN IP4 239.0.0.1/64",
        "a=rtpmap:96 raw/90000",
        RAW_FMTP_COMPLETE_PT96,
        TIMING_MEDIACLK,
      }))
      assert.is_nil(doc)
      local f = finding_for(ctx, "st2110.attr.ts-refclk-required")
      assert.is_not_nil(f)
      assert.equal("media[0]", f.field_path)
      assert.equal("ST 2110-10:2022 §8.2", f.spec_ref)
    end)

    it("accepts media-block omission when ts-refclk is at session level", function()
      -- RFC 7273 §4.8 explicitly permits ts-refclk at session level;
      -- §8.2's SHALL is satisfied as long as the attribute appears
      -- somewhere applicable to the stream. Session-level a= follows
      -- t= per RFC 8866 §5 ordering.
      local doc = st2110.match(sdp_lines({
        "v=0",
        "o=- 1 1 IN IP4 192.0.2.1",
        "s=Test",
        "t=0 0",
        TIMING_TS_REFCLK,
        "m=video 30000 RTP/AVP 96",
        "c=IN IP4 239.0.0.1/64",
        "a=rtpmap:96 raw/90000",
        RAW_FMTP_COMPLETE_PT96,
        TIMING_MEDIACLK,
      }))
      assert.is_truthy(doc)
    end)

    it("reports the offending media index when one block of two is missing", function()
      -- First media block has timing; second omits ts-refclk.
      local doc, ctx = st2110.match(sdp_lines({
        "v=0",
        "o=- 1 1 IN IP4 192.0.2.1",
        "s=Test",
        "t=0 0",
        "m=video 30000 RTP/AVP 96",
        "c=IN IP4 239.0.0.1/64",
        "a=rtpmap:96 raw/90000",
        RAW_FMTP_COMPLETE_PT96,
        TIMING_TS_REFCLK,
        TIMING_MEDIACLK,
        "m=video 30002 RTP/AVP 97",
        "c=IN IP4 239.0.0.2/64",
        "a=rtpmap:97 raw/90000",
        "a=fmtp:97 sampling=YCbCr-4:2:2;width=1920;height=1080;"
          .. "exactframerate=60000/1001;depth=10;colorimetry=BT709;"
          .. "PM=2110GPM;SSN=ST2110-20:2022;TP=2110TPN",
        TIMING_MEDIACLK,
      }))
      assert.is_nil(doc)
      local f = finding_for(ctx, "st2110.attr.ts-refclk-required")
      assert.is_not_nil(f)
      assert.equal("media[1]", f.field_path)
    end)
  end)

  describe("a=mediaclk required per media block (§8.3)", function()

    it("accepts a media block that carries a media-level a=mediaclk", function()
      local doc = st2110.match(sdp_lines({
        "v=0",
        "o=- 1 1 IN IP4 192.0.2.1",
        "s=Test",
        "t=0 0",
        "m=video 30000 RTP/AVP 96",
        "c=IN IP4 239.0.0.1/64",
        "a=rtpmap:96 raw/90000",
        RAW_FMTP_COMPLETE_PT96,
        TIMING_TS_REFCLK,
        TIMING_MEDIACLK,
      }))
      assert.is_truthy(doc)
    end)

    it("rejects a media block missing a=mediaclk", function()
      local doc, ctx = st2110.match(sdp_lines({
        "v=0",
        "o=- 1 1 IN IP4 192.0.2.1",
        "s=Test",
        "t=0 0",
        "m=video 30000 RTP/AVP 96",
        "c=IN IP4 239.0.0.1/64",
        "a=rtpmap:96 raw/90000",
        RAW_FMTP_COMPLETE_PT96,
        TIMING_TS_REFCLK,
      }))
      assert.is_nil(doc)
      local f = finding_for(ctx, "st2110.attr.mediaclk-required")
      assert.is_not_nil(f)
      assert.equal("media[0]", f.field_path)
      assert.equal("ST 2110-10:2022 §8.3", f.spec_ref)
    end)

    it("rejects media-block omission even when mediaclk is at session level", function()
      -- §8.3's "media-level mediaclk attribute" qualifier means a
      -- session-level mediaclk does NOT cover a media block lacking
      -- its own; the SHALL is unsatisfied. Session-level a= follows
      -- t= per RFC 8866 §5 ordering.
      local doc, ctx = st2110.match(sdp_lines({
        "v=0",
        "o=- 1 1 IN IP4 192.0.2.1",
        "s=Test",
        "t=0 0",
        TIMING_MEDIACLK,
        "m=video 30000 RTP/AVP 96",
        "c=IN IP4 239.0.0.1/64",
        "a=rtpmap:96 raw/90000",
        RAW_FMTP_COMPLETE_PT96,
        TIMING_TS_REFCLK,
      }))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx, "st2110.attr.mediaclk-required"))
    end)

    it("reports the offending media index when one block of two is missing", function()
      local doc, ctx = st2110.match(sdp_lines({
        "v=0",
        "o=- 1 1 IN IP4 192.0.2.1",
        "s=Test",
        "t=0 0",
        "m=video 30000 RTP/AVP 96",
        "c=IN IP4 239.0.0.1/64",
        "a=rtpmap:96 raw/90000",
        RAW_FMTP_COMPLETE_PT96,
        TIMING_TS_REFCLK,
        TIMING_MEDIACLK,
        "m=video 30002 RTP/AVP 97",
        "c=IN IP4 239.0.0.2/64",
        "a=rtpmap:97 raw/90000",
        "a=fmtp:97 sampling=YCbCr-4:2:2;width=1920;height=1080;"
          .. "exactframerate=60000/1001;depth=10;colorimetry=BT709;"
          .. "PM=2110GPM;SSN=ST2110-20:2022;TP=2110TPN",
        TIMING_TS_REFCLK,
      }))
      assert.is_nil(doc)
      local f = finding_for(ctx, "st2110.attr.mediaclk-required")
      assert.is_not_nil(f)
      assert.equal("media[1]", f.field_path)
    end)
  end)
end)

-- ── Phase 6.D.B — ST 2110-30:2025 §6.2.1 audio MAXUDP-forbidden ─────────
--
-- §6.2.1: "The Standard UDP Datagram Size Limit as defined in SMPTE ST
--          2110-10 shall be used."
-- ST 2110-10:2022 §6.4 / §8.6 define MAXUDP as the signal for operating
-- beyond the Standard Limit; its presence on a -30 stream therefore
-- violates the §6.2.1 SHALL.
--
-- Scope is L16 / L24 only. ST 2110-31 (AM824) defers to ST 2110-10 via
-- §5.2 but never narrows -10's MAXUDP-permitting prose, so the 1.0
-- parser's "MAXUDP forbidden on AM824" check is over-strict and
-- intentionally not ported. The 1.0 case stays flagged for audit-folder
-- follow-up.

describe("ST 2110-30 — audio MAXUDP-forbidden (Phase 6.D.B)", function()

  it("accepts L24 fmtp without MAXUDP", function()
    local doc = st2110.match(build_with_fmtp(
      "m=audio 30000 RTP/AVP 96",
      "a=rtpmap:96 L24/48000/2",
      "a=fmtp:96 channel-order=SMPTE2110.(ST)"))
    assert.is_truthy(doc)
  end)

  it("rejects L24 fmtp with MAXUDP", function()
    local doc, ctx = st2110.match(build_with_fmtp(
      "m=audio 30000 RTP/AVP 96",
      "a=rtpmap:96 L24/48000/2",
      "a=fmtp:96 MAXUDP=1500"))
    assert.is_nil(doc)
    local f = finding_for(ctx, "st2110-30.a.fmtp.maxudp-forbidden")
    assert.is_not_nil(f)
    assert.equal("ST 2110-30:2025 §6.2.1", f.spec_ref)
  end)

  it("rejects L16 fmtp with MAXUDP", function()
    local doc, ctx = st2110.match(build_with_fmtp(
      "m=audio 30000 RTP/AVP 96",
      "a=rtpmap:96 L16/48000/2",
      "a=fmtp:96 MAXUDP=1500"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "st2110-30.a.fmtp.maxudp-forbidden"))
  end)

  -- ── INTENTIONAL non-parity with 1.0 ──────────────────────────────────
  -- ST 2110-31 has no MAXUDP-forbidden SHALL; the 1.0 parser's check is
  -- conjecture per "§5.x inherits". Grammar tier does not enforce on
  -- AM824. Reason: §5.2 defers to ST 2110-10, which explicitly *permits*
  -- MAXUDP for streams exceeding the Standard Size Limit (§6.5).
  it("does NOT fire on AM824 fmtp with MAXUDP", function()
    local doc = st2110.match(build_with_fmtp(
      "m=audio 30000 RTP/AVP 96",
      "a=rtpmap:96 AM824/48000/2",
      "a=fmtp:96 MAXUDP=1500"))
    assert.is_truthy(doc)
  end)

  -- NOT-SPEC: MAXUDP on non-audio fmtp is governed by §6.2.5 / §6.3.3
  -- (already covered in 6.C.D.2 / 6.C.E); -30 forbidden check must not
  -- spill into raw video.
  it("does NOT fire on raw video fmtp with MAXUDP", function()
    local doc = st2110.match(build_with_fmtp(
      "m=video 30000 RTP/AVP 96",
      "a=rtpmap:96 raw/90000",
      RAW_FMTP_COMPLETE_PT96 .. ";MAXUDP=1500"))
    assert.is_truthy(doc)
  end)
end)

-- ── Phase 6.D.C — ST 2110-31:2022 §6.1 AM824 rtpmap channels-required ───
--
-- §6.1: "The number of AES3 Subframe sequences multiplexed within the
--        payload shall be signaled in the SDP object on the a=rtpmap
--        line ... a=rtpmap:<pt> AM824/<clock-rate>/<nchan>"
--
-- The <nchan> channels field is mandatory for AM824. L16 / L24
-- channels-presence is intentionally NOT enforced: RFC 3551 §6 makes
-- it OPTIONAL (defaults to 1), and ST 2110-30 / AES67 don't override.
-- The 1.0 parser's L16/L24 channels-required limb is over-strict per
-- the conformance-principle audit.

describe("ST 2110-31 — AM824 rtpmap channels-required (Phase 6.D.C)",
    function()

  local function audio_sdp(rtpmap_line)
    return table.concat({
      "v=0",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=Test",
      "t=0 0",
      "m=audio 30000 RTP/AVP 96",
      "c=IN IP4 239.0.0.1/64",
      rtpmap_line,
      "a=ts-refclk:localmac=00-11-22-33-44-55",
      "a=mediaclk:sender",
    }, "\r\n") .. "\r\n"
  end

  it("accepts AM824 rtpmap with channels field", function()
    assert.is_truthy(st2110.match(audio_sdp(
      "a=rtpmap:96 AM824/48000/2")))
  end)

  it("rejects AM824 rtpmap missing the channels field", function()
    local doc, ctx = st2110.match(audio_sdp(
      "a=rtpmap:96 AM824/48000"))
    assert.is_nil(doc)
    local f = finding_for(ctx, "st2110-31.a.rtpmap.am824-channels-required")
    assert.is_not_nil(f)
    assert.equal("ST 2110-31:2022 §6.1", f.spec_ref)
  end)

  it("reports the offending media index on a multi-block SDP", function()
    -- First block has channels (passes); second omits them.
    local doc, ctx = st2110.match(table.concat({
      "v=0",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=Test",
      "t=0 0",
      "m=audio 30000 RTP/AVP 96",
      "c=IN IP4 239.0.0.1/64",
      "a=rtpmap:96 AM824/48000/2",
      "a=ts-refclk:localmac=00-11-22-33-44-55",
      "a=mediaclk:sender",
      "m=audio 30002 RTP/AVP 97",
      "c=IN IP4 239.0.0.2/64",
      "a=rtpmap:97 AM824/48000",
      "a=ts-refclk:localmac=00-11-22-33-44-55",
      "a=mediaclk:sender",
    }, "\r\n") .. "\r\n")
    assert.is_nil(doc)
    local f = finding_for(ctx, "st2110-31.a.rtpmap.am824-channels-required")
    assert.is_not_nil(f)
    assert.equal("media[1].attributes[rtpmap:pt=97]", f.field_path)
  end)

  -- ── INTENTIONAL non-parity with 1.0 ──────────────────────────────────
  -- ST 2110-30 / AES67-2013 / RFC 3551 §6 do NOT require channels on
  -- L16 / L24 rtpmaps. The 1.0 parser enforces it citing a "ST 2110-30
  -- tightens RFC 3551" annotation that is not supported by primary
  -- text. Grammar tier accepts these.
  it("does NOT fire on L24 rtpmap missing channels", function()
    assert.is_truthy(st2110.match(audio_sdp(
      "a=rtpmap:96 L24/48000")))
  end)

  it("does NOT fire on L16 rtpmap missing channels", function()
    assert.is_truthy(st2110.match(audio_sdp(
      "a=rtpmap:96 L16/48000")))
  end)
end)

-- ── Phase 6.D.D — ST 2110-30:2025 §6.2.1 audio packet-payload-fit ───────
--
-- §6.2.1: "The Standard UDP Datagram Size Limit as defined in SMPTE ST
--          2110-10 shall be used."
-- ST 2110-10:2022 §6.4 sets that Limit at 1460 octets. With the 12-octet
-- RTP fixed header (RFC 3550), the RTP payload available for audio
-- samples is 1448 octets. For PCM audio:
--   needed = channels × bytes_per_sample × samples_per_packet
--   samples_per_packet = round(clock_rate × ptime / 1000)   (AES67 §8.1)
--
-- L16/L24 only; AM824 is deferred (matching 6.D.B scope — ST 2110-31
-- has no UDP-size SHALL of its own).

describe("ST 2110-30 — audio packet-payload-fit (Phase 6.D.D)", function()

  local function audio_sdp_with_ptime(rtpmap_line, ptime_line)
    return table.concat({
      "v=0",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=Test",
      "t=0 0",
      "m=audio 30000 RTP/AVP 96",
      "c=IN IP4 239.0.0.1/64",
      rtpmap_line,
      ptime_line,
      "a=ts-refclk:localmac=00-11-22-33-44-55",
      "a=mediaclk:sender",
    }, "\r\n") .. "\r\n"
  end

  it("accepts L24/48000/2 ptime=1 (288 B payload, well within 1448)", function()
    -- 2 ch × 3 B × 48 samples = 288 B
    assert.is_truthy(st2110.match(audio_sdp_with_ptime(
      "a=rtpmap:96 L24/48000/2", "a=ptime:1")))
  end)

  it("accepts L16/48000/2 ptime=1 (192 B payload)", function()
    assert.is_truthy(st2110.match(audio_sdp_with_ptime(
      "a=rtpmap:96 L16/48000/2", "a=ptime:1")))
  end)

  it("accepts L24/48000/2 ptime=5 at boundary (1440 B ≤ 1448)", function()
    -- 2 ch × 3 B × 240 samples = 1440 B
    assert.is_truthy(st2110.match(audio_sdp_with_ptime(
      "a=rtpmap:96 L24/48000/2", "a=ptime:5")))
  end)

  it("rejects L24/48000/2 ptime=6 (1728 B > 1448)", function()
    -- 2 ch × 3 B × 288 samples = 1728 B
    local doc, ctx = st2110.match(audio_sdp_with_ptime(
      "a=rtpmap:96 L24/48000/2", "a=ptime:6"))
    assert.is_nil(doc)
    local f = finding_for(ctx, "st2110-30.audio.packet-payload-fit")
    assert.is_not_nil(f)
    assert.equal("ST 2110-30:2025 §6.2.1", f.spec_ref)
  end)

  it("rejects L24/48000/64 ptime=1 (9216 B way over 1448)", function()
    -- 64 ch × 3 B × 48 samples = 9216 B
    local doc, ctx = st2110.match(audio_sdp_with_ptime(
      "a=rtpmap:96 L24/48000/64", "a=ptime:1"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "st2110-30.audio.packet-payload-fit"))
  end)

  it("rejects L16/48000/8 ptime=2 (1536 B > 1448)", function()
    -- 8 ch × 2 B × 96 samples = 1536 B
    local doc, ctx = st2110.match(audio_sdp_with_ptime(
      "a=rtpmap:96 L16/48000/8", "a=ptime:2"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "st2110-30.audio.packet-payload-fit"))
  end)

  it("treats absent channels as 1 (L24/48000 default ptime=1 → 144 B)", function()
    -- RFC 3551 §6: channels defaults to 1 when omitted on L16/L24.
    -- 1 ch × 3 B × 48 samples = 144 B, well within 1448.
    assert.is_truthy(st2110.match(audio_sdp_with_ptime(
      "a=rtpmap:96 L24/48000", "a=ptime:1")))
  end)

  -- NOT-SPEC: library — check needs both rtpmap clock_rate AND ptime to
  -- run. Without ptime, samples-per-packet is undefined; the check skips.
  -- (Whether ptime presence is itself required is a separate SHALL —
  -- AES67 §8.1 requires it for -30 streams; 1.0 enforces; grammar tier
  -- will pick up in a separate slice.)
  it("does NOT fire when ptime is absent", function()
    assert.is_truthy(st2110.match(table.concat({
      "v=0",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=Test",
      "t=0 0",
      "m=audio 30000 RTP/AVP 96",
      "c=IN IP4 239.0.0.1/64",
      "a=rtpmap:96 L24/48000/64",          -- 64ch but no ptime → skip
      "a=ts-refclk:localmac=00-11-22-33-44-55",
      "a=mediaclk:sender",
    }, "\r\n") .. "\r\n"))
  end)

  -- ── INTENTIONAL non-parity with 1.0 ──────────────────────────────────
  -- ST 2110-31 has no UDP-size SHALL; the 1.0 parser's AM824 packet-fit
  -- check is conjecture-based per the 6.D.B finding. Grammar tier skips.
  it("does NOT fire on AM824 stream with over-large payload", function()
    -- 64 ch × 4 B × 48 samples = 12288 B — would overflow if checked.
    assert.is_truthy(st2110.match(audio_sdp_with_ptime(
      "a=rtpmap:96 AM824/48000/64", "a=ptime:1")))
  end)
end)


