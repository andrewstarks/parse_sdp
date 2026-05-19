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

describe("ST 2110-20 raw — rtpmap narrowings (ST 2110-20:2022 §7.1)", function()

  it("accepts m=video with raw/90000", function()
    local doc = st2110.match(build("m=video 30000 RTP/AVP 96",
                                   "a=rtpmap:96 raw/90000"))
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
    local doc = st2110.match(build_with_fmtp(
      RAW_MEDIA, RAW_RTPMAP,
      "a=fmtp:96 sampling=YCbCr-4:2:2;width=1920;height=1080"))
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
