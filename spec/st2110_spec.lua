---@diagnostic disable
describe("ST 2110 validation", function()
  local sdp = require("parse_sdp")

  local VIDEO_SDP = table.concat({
    "v=0",
    "o=- 1234567890 1 IN IP4 192.168.1.1",
    "s=ST2110 Video",
    "t=0 0",
    "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
    "m=video 5000 RTP/AVP 96",
    "c=IN IP4 239.100.0.1/64",
    "a=rtpmap:96 raw/90000",
    "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
    "a=mediaclk:direct=0",
    "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
  }, "\r\n")

  local AUDIO_SDP = table.concat({
    "v=0",
    "o=- 1234567890 1 IN IP4 192.168.1.1",
    "s=ST2110 Audio",
    "t=0 0",
    "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
    "m=audio 5010 RTP/AVP 97",
    "c=IN IP4 239.100.0.2/64",
    "a=rtpmap:97 L24/48000/8",
    "a=fmtp:97 channel-order=SMPTE2110.(ST)",
    "a=mediaclk:direct=0",
    "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
  }, "\r\n")

  local GENERIC_SDP = table.concat({
    "v=0",
    "o=- 1 1 IN IP4 127.0.0.1",
    "s=Plain SDP",
    "t=0 0",
  }, "\r\n")

  describe("sdp.parse with 'st2110' mode", function()
    it("returns a doc for valid ST 2110-20 (video) SDP", function()
      local doc, err = sdp.parse(VIDEO_SDP, "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("returns a doc for valid ST 2110-30 (audio) SDP", function()
      local doc, err = sdp.parse(AUDIO_SDP, "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("returns nil+err for SDP with no media blocks", function()
      local doc, err = sdp.parse(GENERIC_SDP, "st2110")
      assert.is_nil(doc)
      assert.is_table(err)
      assert.is_string(err.message)
    end)

    it("returns nil+err for SDP missing ts-refclk everywhere", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        "a=mediaclk:direct=0",
      }, "\r\n")
      local doc, err = sdp.parse(text, "st2110")
      assert.is_nil(doc)
      assert.is_table(err)
      assert.matches("ts%-refclk", err.message)
    end)
  end)

  describe("doc:validate('st2110')", function()
    it("returns true for valid ST 2110-20 video", function()
      local doc = sdp.parse(VIDEO_SDP)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("returns true for valid ST 2110-30 audio", function()
      local doc = sdp.parse(AUDIO_SDP)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("returns nil+err for generic SDP with no media blocks", function()
      local doc = sdp.parse(GENERIC_SDP)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.is_string(err.message)
    end)

    it("error includes field_path and spec_ref when ts-refclk is missing", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        "a=mediaclk:direct=0",
      }, "\r\n")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.is_string(err.field_path)
      assert.is_string(err.spec_ref)
      assert.matches("ts%-refclk", err.message)
    end)

    it("errors when mediaclk is missing from media block", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      }, "\r\n")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("mediaclk", err.message)
    end)

    it("errors when video fmtp lacks sampling parameter", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 width=1920; height=1080",
        "a=mediaclk:direct=0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      }, "\r\n")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("sampling", err.message)
    end)

    it("errors when video rtpmap clock rate is not 90000", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/48000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        "a=mediaclk:direct=0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      }, "\r\n")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("90000", err.message)
    end)

    it("errors when rtpmap is missing from media block", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        "a=mediaclk:direct=0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      }, "\r\n")
      local doc = sdp.parse(text)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("rtpmap", err.message)
    end)

    it("errors when fmtp is missing from media block", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=mediaclk:direct=0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      }, "\r\n")
      local doc = sdp.parse(text)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("fmtp", err.message)
    end)

    it("errors when audio fmtp lacks channel-order parameter", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Audio",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=audio 5010 RTP/AVP 97",
        "c=IN IP4 239.100.0.2/64",
        "a=rtpmap:97 L24/48000/8",
        "a=fmtp:97 some-param=value",
        "a=mediaclk:direct=0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      }, "\r\n")
      local doc = sdp.parse(text)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("channel%-order", err.message)
    end)

    it("errors when video fmtp has a token without '=' sign", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 noequalssign",
        "a=mediaclk:direct=0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      }, "\r\n")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("fmtp", err.message)
    end)
  end)

  describe("doc:is_st2110()", function()
    it("returns true for valid ST 2110-20 video", function()
      local doc = sdp.parse(VIDEO_SDP)
      assert.is_table(doc)
      assert.equal(true, doc:is_st2110())
    end)

    it("returns true for valid ST 2110-30 audio", function()
      local doc = sdp.parse(AUDIO_SDP)
      assert.is_table(doc)
      assert.equal(true, doc:is_st2110())
    end)

    it("returns false for generic SDP", function()
      local doc = sdp.parse(GENERIC_SDP)
      assert.is_table(doc)
      assert.equal(false, doc:is_st2110())
    end)

    it("accepts localmac ts-refclk (PTP is not required)", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
      }, "\r\n")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      assert.equal(true, doc and doc:is_st2110())
    end)
  end)

  -- ── ts-refclk value format ──────────────────────────────────────────────────

  describe("ts-refclk value format", function()
    -- Build a minimal valid video SDP but with a custom ts-refclk value.
    local function with_tsrefclk(value)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        "a=mediaclk:direct=0",
        "a=ts-refclk:" .. value,
      }, "\r\n")
    end

    it("accepts ptp= with version, GMID, and domain", function()
      local doc = sdp.parse(with_tsrefclk("ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("accepts localmac= with valid MAC", function()
      local doc = sdp.parse(with_tsrefclk("localmac=AA-BB-CC-DD-EE-FF"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("accepts bare 'gps'", function()
      local doc = sdp.parse(with_tsrefclk("gps"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("rejects unrecognized clock source", function()
      local doc = sdp.parse(with_tsrefclk("garbage"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("ts%-refclk", err.message)
    end)

    it("rejects ptp= with missing GMID (no colon after version)", function()
      local doc = sdp.parse(with_tsrefclk("ptp=IEEE1588-2008"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("ts%-refclk", err.message)
    end)

    it("rejects localmac= with non-hex MAC", function()
      local doc = sdp.parse(with_tsrefclk("localmac=GG-BB-CC-DD-EE-FF"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("ts%-refclk", err.message)
    end)

    it("rejects localmac= with wrong octet count", function()
      local doc = sdp.parse(with_tsrefclk("localmac=AA-BB-CC"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("ts%-refclk", err.message)
    end)

    it("accepts bare 'gal'", function()
      local doc = sdp.parse(with_tsrefclk("gal"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("accepts bare 'glonass'", function()
      local doc = sdp.parse(with_tsrefclk("glonass"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("accepts ntp= with a valid address", function()
      local doc = sdp.parse(with_tsrefclk("ntp=192.0.2.1"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("rejects ntp= with whitespace in address", function()
      local doc = sdp.parse(with_tsrefclk("ntp=192.0.2.1 extra"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("ts%-refclk", err.message)
    end)

    it("accepts ptp= with version and GMID but no domain", function()
      local doc = sdp.parse(with_tsrefclk("ptp=IEEE1588-2008:00-11-22-33-44-55-66-77"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("accepts ptp=IEEE1588-2008:traceable form (ST 2110-10 §8.2)", function()
      local doc = sdp.parse(with_tsrefclk("ptp=IEEE1588-2008:traceable"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("rejects ptp= with unrecognized version string", function()
      local doc = sdp.parse(with_tsrefclk("ptp=IEEE1588-XXXX:00-11-22-33-44-55-66-77"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("ts%-refclk", err.message)
    end)

    it("session-level ts-refclk satisfies requirement with no per-media attribute", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        "a=mediaclk:direct=0",
      }, "\r\n")
      local doc, err = sdp.parse(text, "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  -- ── ST 2110-40: ancillary data (smpte291) ──────────────────────────────────

  describe("ST 2110-40 ancillary data (smpte291)", function()
    local function ancillary_sdp(fmtp_str)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Ancillary",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5020 RTP/AVP 96",
        "c=IN IP4 239.100.0.3/64",
        "a=rtpmap:96 smpte291/90000",
        "a=fmtp:96 " .. fmtp_str,
        "a=mediaclk:direct=0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      }, "\r\n")
    end

    it("accepts valid smpte291 SDP with DID_SDID", function()
      local doc, err = sdp.parse(ancillary_sdp("DID_SDID={0x61,0x02}"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("errors when fmtp is missing DID_SDID", function()
      local doc = sdp.parse(ancillary_sdp("VPID_Code=133"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("DID_SDID", err.message)
    end)

    it("errors when DID_SDID has a non-hex octet", function()
      local doc = sdp.parse(ancillary_sdp("DID_SDID={0xGG,0x02}"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("DID_SDID", err.message)
    end)

    it("accepts multiple valid DID_SDID entries", function()
      local doc, err = sdp.parse(ancillary_sdp("DID_SDID={0x61,0x02}; DID_SDID={0x00,0x01}"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("errors when any DID_SDID entry is invalid", function()
      local doc = sdp.parse(ancillary_sdp("DID_SDID={0x61,0x02}; DID_SDID={0xGG,0x01}"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("DID_SDID", err.message)
    end)
  end)

  -- ── ST 2110-41: fast metadata ───────────────────────────────────────────────

  describe("ST 2110-41 fast metadata", function()
    local function metadata_sdp(fmtp_str)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Metadata",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5030 RTP/AVP 96",
        "c=IN IP4 239.100.0.4/64",
        "a=rtpmap:96 ST2110-41/90000",
        "a=fmtp:96 " .. fmtp_str,
        "a=mediaclk:direct=0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      }, "\r\n")
    end

    it("accepts valid ST2110-41 SDP with SSN and DIT", function()
      local doc, err = sdp.parse(metadata_sdp("SSN=ST2110-41:2024; DIT=100"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("errors when fmtp is missing SSN", function()
      local doc = sdp.parse(metadata_sdp("DIT=100"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("SSN", err.message)
    end)

    it("errors when fmtp is missing DIT", function()
      local doc = sdp.parse(metadata_sdp("SSN=ST2110-41:2024"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("DIT", err.message)
    end)

    it("errors when ST2110-41 clock rate is not 90000", function()
      local bad_sdp = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Metadata",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5030 RTP/AVP 96",
        "c=IN IP4 239.100.0.4/64",
        "a=rtpmap:96 ST2110-41/48000",
        "a=fmtp:96 SSN=ST2110-41:2024; DIT=100",
        "a=mediaclk:direct=0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      }, "\r\n")
      local doc = sdp.parse(bad_sdp)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("90000", err.message)
    end)

    it("errors when SSN value has wrong format", function()
      local doc = sdp.parse(metadata_sdp("SSN=WRONG:2024; DIT=100"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("SSN", err.message)
    end)
  end)

  -- ── mediaclk value format ───────────────────────────────────────────────────

  describe("mediaclk value format", function()
    local function with_mediaclk(value)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "a=mediaclk:" .. value,
      }, "\r\n")
    end

    it("accepts 'direct=<integer>'", function()
      local doc = sdp.parse(with_mediaclk("direct=0"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("accepts 'sender'", function()
      local doc = sdp.parse(with_mediaclk("sender"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("rejects unrecognized mediaclk value", function()
      local doc = sdp.parse(with_mediaclk("garbage"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("mediaclk", err.message)
    end)

    it("rejects 'direct=' with non-integer offset", function()
      local doc = sdp.parse(with_mediaclk("direct=notanumber"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("mediaclk", err.message)
    end)

    it("accepts 'direct=' with a negative integer offset", function()
      local doc = sdp.parse(with_mediaclk("direct=-1"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)
  end)

  -- ── M16: a=group:DUP grouping (ST 2022-7 / RFC 7104) ─────────────────────────

  describe("a=group:DUP grouping (ST 2110-10 §8.5)", function()
    local PTP = "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"
    local VFMTP = "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"

    local function dup_sdp(opts)
      opts = opts or {}
      local mid1     = opts.mid1     or "leg1"
      local mid2     = opts.mid2     or "leg2"
      local type1    = opts.type1    or "video"
      local type2    = opts.type2    or "video"
      local fmtp2    = opts.fmtp2    or VFMTP
      local rtpmap2  = opts.rtpmap2  or "a=rtpmap:96 raw/90000"
      local omit_mid2 = opts.omit_mid2 or false
      local lines = {
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=DUP Test",
        "t=0 0",
        string.format("a=group:DUP %s %s", mid1, mid2),
        PTP,
        string.format("m=%s 5000 RTP/AVP 96", type1),
        "c=IN IP4 239.100.0.1/64",
        string.format("a=mid:%s", mid1),
        "a=rtpmap:96 raw/90000",
        VFMTP,
        "a=mediaclk:direct=0",
        string.format("m=%s 5010 RTP/AVP 96", type2),
        "c=IN IP4 239.100.0.2/64",
      }
      if not omit_mid2 then lines[#lines+1] = string.format("a=mid:%s", mid2) end
      lines[#lines+1] = rtpmap2
      lines[#lines+1] = fmtp2
      lines[#lines+1] = "a=mediaclk:direct=0"
      return table.concat(lines, "\r\n")
    end

    it("accepts valid DUP grouping with two video legs on different ports", function()
      local doc, err = sdp.parse(dup_sdp(), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts SDP without a=group:DUP (absence is not an error)", function()
      local doc, err = sdp.parse(VIDEO_SDP, "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects DUP referencing a mid that has no matching media block", function()
      local text = dup_sdp({ omit_mid2 = true })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("leg2", err.message)
    end)

    it("rejects DUP where the two legs have different media types", function()
      local text = dup_sdp({
        type2   = "audio",
        rtpmap2 = "a=rtpmap:97 L24/48000/8",
        fmtp2   = "a=fmtp:97 channel-order=SMPTE2110.(ST)",
      })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("media type", err.message)
    end)

    it("spec_ref for DUP errors is ST 2110-10 §8.5", function()
      local text = dup_sdp({ omit_mid2 = true })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.equal("ST 2110-10 §8.5", err.spec_ref)
    end)

    it("rejects a=group:DUP with only one leg", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=DUP Test",
        "t=0 0",
        "a=group:DUP leg1",
        PTP,
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=mid:leg1",
        "a=rtpmap:96 raw/90000",
        VFMTP,
        "a=mediaclk:direct=0",
      }, "\r\n")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("DUP", err.message)
    end)
  end)

  -- ── M18: ST 2110-20 fmtp value validation ────────────────────────────────────

  describe("ST 2110-20 fmtp value validation (§7.2)", function()
    local function video20_sdp(fmtp_str)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 " .. fmtp_str,
        "a=mediaclk:direct=0",
      }, "\r\n")
    end

    local VALID = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022"

    it("accepts all nine required fmtp parameters", function()
      local doc, err = sdp.parse(video20_sdp(VALID), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts exactframerate as integer/integer fraction", function()
      local fmtp = VALID:gsub("exactframerate=25", "exactframerate=30000/1001")
      local doc, err = sdp.parse(video20_sdp(fmtp), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- Missing required field: one entry per required parameter.
    local missing = {
      { "sampling",       "width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022" },
      { "width",          "sampling=YCbCr-4:2:2; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022" },
      { "height",         "sampling=YCbCr-4:2:2; width=1920; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022" },
      { "exactframerate", "sampling=YCbCr-4:2:2; width=1920; height=1080; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022" },
      { "depth",          "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022" },
      { "TCS",            "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022" },
      { "colorimetry",    "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; PM=2110GPM; SSN=ST2110-20:2022" },
      { "PM",             "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; SSN=ST2110-20:2022" },
      { "SSN",            "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM" },
    }
    for _, c in ipairs(missing) do
      local field, fmtp = c[1], c[2]
      it("rejects fmtp missing '" .. field .. "'", function()
        local doc = sdp.parse(video20_sdp(fmtp))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches(field, err.message)
      end)
    end

    -- Invalid value: one entry per validated parameter.
    local invalid = {
      { "sampling",       "sampling=garbage; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022" },
      { "width",          "sampling=YCbCr-4:2:2; width=abc; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022" },
      { "height",         "sampling=YCbCr-4:2:2; width=1920; height=abc; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022" },
      { "exactframerate", "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25.5; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022" },
      { "depth",          "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=abc; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022" },
      { "TCS",            "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=BADTCS; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022" },
      { "colorimetry",    "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BADCOLOR; PM=2110GPM; SSN=ST2110-20:2022" },
      { "PM",             "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=BADPM; SSN=ST2110-20:2022" },
      { "SSN",            "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=BADSSN" },
    }
    for _, c in ipairs(invalid) do
      local field, fmtp = c[1], c[2]
      it("rejects invalid '" .. field .. "' value", function()
        local doc = sdp.parse(video20_sdp(fmtp))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
      end)
    end

    it("rejects exactframerate=0", function()
      local doc = sdp.parse(video20_sdp(VALID:gsub("exactframerate=25", "exactframerate=0")))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("exactframerate", err.message)
    end)

    it("rejects width=0", function()
      local doc = sdp.parse(video20_sdp(VALID:gsub("width=1920", "width=0")))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("positive", err.message)
    end)

    it("rejects height=0", function()
      local doc = sdp.parse(video20_sdp(VALID:gsub("height=1080", "height=0")))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("positive", err.message)
    end)

    it("rejects depth=0", function()
      local doc = sdp.parse(video20_sdp(VALID:gsub("depth=10", "depth=0")))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("positive", err.message)
    end)
  end)

  -- ── M18: ST 2110-30 channel-order value validation ───────────────────────────

  describe("ST 2110-30 channel-order value validation (§7)", function()
    local function audio30_sdp(co_value)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Audio",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=audio 5010 RTP/AVP 97",
        "c=IN IP4 239.100.0.2/64",
        "a=rtpmap:97 L24/48000/8",
        "a=fmtp:97 channel-order=" .. co_value,
        "a=mediaclk:direct=0",
      }, "\r\n")
    end

    it("accepts SMPTE2110.(ST)", function()
      local doc, err = sdp.parse(audio30_sdp("SMPTE2110.(ST)"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts SMPTE2110.(51) (numeric group token)", function()
      local doc, err = sdp.parse(audio30_sdp("SMPTE2110.(51)"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects channel-order with wrong prefix", function()
      local doc = sdp.parse(audio30_sdp("garbage"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("channel%-order", err.message)
    end)

    it("rejects SMPTE2110.() with empty group", function()
      local doc = sdp.parse(audio30_sdp("SMPTE2110.()"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("channel%-order", err.message)
    end)
  end)

  -- ── ST 2110-30: audio rtpmap clock rate ──────────────────────────────────────

  describe("ST 2110-30 audio rtpmap clock rate (§7.1)", function()
    local function audio_sdp(rate)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Audio",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=audio 5010 RTP/AVP 97",
        "c=IN IP4 239.100.0.2/64",
        "a=rtpmap:97 L24/" .. rate .. "/8",
        "a=fmtp:97 channel-order=SMPTE2110.(ST)",
        "a=mediaclk:direct=0",
      }, "\r\n")
    end

    local known_rates = { 32000, 44100, 48000, 88200, 96000, 176400, 192000 }
    for _, rate in ipairs(known_rates) do
      it("accepts " .. rate .. " Hz", function()
        local doc, err = sdp.parse(audio_sdp(rate), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)
    end

    it("rejects an unknown rate (e.g. 22050)", function()
      local doc = sdp.parse(audio_sdp(22050))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("clock rate", err.message)
      assert.equal("ST 2110-30 §7.1", err.spec_ref)
    end)

    it("rejects a nonsense rate (e.g. 1)", function()
      local doc = sdp.parse(audio_sdp(1))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("clock rate", err.message)
    end)
  end)

  -- ── ST 2110-20 optional fmtp parameters ──────────────────────────────────────

  describe("ST 2110-20 optional fmtp parameters", function()
    local BASE = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022"

    local function video20_sdp(fmtp_str)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 " .. fmtp_str,
        "a=mediaclk:direct=0",
      }, "\r\n")
    end

    describe("RANGE", function()
      it("accepts RANGE=NARROW", function()
        local doc, err = sdp.parse(video20_sdp(BASE .. "; RANGE=NARROW"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("accepts RANGE=FULLPROTECT", function()
        local doc, err = sdp.parse(video20_sdp(BASE .. "; RANGE=FULLPROTECT"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("accepts RANGE=FULL", function()
        local doc, err = sdp.parse(video20_sdp(BASE .. "; RANGE=FULL"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("rejects invalid RANGE value", function()
        local doc = sdp.parse(video20_sdp(BASE .. "; RANGE=PARTIAL"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("RANGE", err.message)
        assert.equal("ST 2110-20 §7.2", err.spec_ref)
      end)

      it("absent RANGE is accepted (optional parameter)", function()
        local doc, err = sdp.parse(video20_sdp(BASE), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)
    end)

    describe("TP (transport profile)", function()
      it("accepts TP=2110TPN", function()
        local doc, err = sdp.parse(video20_sdp(BASE .. "; TP=2110TPN"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("accepts TP=2110TPNL", function()
        local doc, err = sdp.parse(video20_sdp(BASE .. "; TP=2110TPNL"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("accepts TP=2110TPW", function()
        local doc, err = sdp.parse(video20_sdp(BASE .. "; TP=2110TPW"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("rejects invalid TP value", function()
        local doc = sdp.parse(video20_sdp(BASE .. "; TP=2110BADTP"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("TP", err.message)
        assert.equal("ST 2110-20 §7.2", err.spec_ref)
      end)

      it("absent TP is accepted (optional parameter)", function()
        local doc, err = sdp.parse(video20_sdp(BASE), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)
    end)

    describe("MAXUDP", function()
      it("accepts a valid positive integer", function()
        local doc, err = sdp.parse(video20_sdp(BASE .. "; MAXUDP=1460"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("rejects non-integer MAXUDP", function()
        local doc = sdp.parse(video20_sdp(BASE .. "; MAXUDP=notanumber"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("MAXUDP", err.message)
      end)

      it("absent MAXUDP is accepted (optional parameter)", function()
        local doc, err = sdp.parse(video20_sdp(BASE), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("rejects MAXUDP=0", function()
        local doc = sdp.parse(video20_sdp(BASE .. "; MAXUDP=0"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("MAXUDP", err.message)
      end)
    end)

    describe("PAR (pixel aspect ratio)", function()
      it("accepts PAR=1:1 (square pixels)", function()
        local doc, err = sdp.parse(video20_sdp(BASE .. "; PAR=1:1"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("accepts PAR=16:15", function()
        local doc, err = sdp.parse(video20_sdp(BASE .. "; PAR=16:15"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("rejects PAR with wrong format (no colon)", function()
        local doc = sdp.parse(video20_sdp(BASE .. "; PAR=1x1"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("PAR", err.message)
      end)

      it("rejects PAR with zero numerator (0:1)", function()
        local doc = sdp.parse(video20_sdp(BASE .. "; PAR=0:1"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("PAR", err.message)
      end)

      it("rejects PAR with zero denominator (1:0)", function()
        local doc = sdp.parse(video20_sdp(BASE .. "; PAR=1:0"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("PAR", err.message)
      end)

      it("absent PAR is accepted (optional parameter)", function()
        local doc, err = sdp.parse(video20_sdp(BASE), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)
    end)

    describe("TROFF (timestamp offset)", function()
      it("accepts TROFF=0", function()
        local doc, err = sdp.parse(video20_sdp(BASE .. "; TROFF=0"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("accepts a positive TROFF", function()
        local doc, err = sdp.parse(video20_sdp(BASE .. "; TROFF=4500"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("rejects non-integer TROFF", function()
        local doc = sdp.parse(video20_sdp(BASE .. "; TROFF=notanumber"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("TROFF", err.message)
      end)

      it("absent TROFF is accepted (optional parameter)", function()
        local doc, err = sdp.parse(video20_sdp(BASE), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)
    end)

    describe("CMAX (max consecutive packets)", function()
      it("accepts a valid positive integer", function()
        local doc, err = sdp.parse(video20_sdp(BASE .. "; CMAX=3"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("rejects non-integer CMAX", function()
        local doc = sdp.parse(video20_sdp(BASE .. "; CMAX=notanumber"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("CMAX", err.message)
      end)

      it("absent CMAX is accepted (optional parameter)", function()
        local doc, err = sdp.parse(video20_sdp(BASE), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)
    end)

    describe("interlace and segmented (bare flags)", function()
      it("accepts interlace bare flag", function()
        local doc, err = sdp.parse(video20_sdp(BASE .. "; interlace"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("accepts segmented bare flag", function()
        local doc, err = sdp.parse(video20_sdp(BASE .. "; segmented"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("accepts interlace and segmented together", function()
        local doc, err = sdp.parse(video20_sdp(BASE .. "; interlace; segmented"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)
    end)
  end)

  -- ── ST 2110-30: audio rtpmap encoding name ────────────────────────────────────

  describe("ST 2110-30 audio rtpmap encoding name (§7.1)", function()
    local function audio_sdp_enc(enc, rate)
      rate = rate or 48000
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Audio",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=audio 5010 RTP/AVP 97",
        "c=IN IP4 239.100.0.2/64",
        "a=rtpmap:97 " .. enc .. "/" .. rate .. "/8",
        "a=fmtp:97 channel-order=SMPTE2110.(ST)",
        "a=mediaclk:direct=0",
      }, "\r\n")
    end

    it("accepts L16 encoding", function()
      local doc, err = sdp.parse(audio_sdp_enc("L16"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts L24 encoding", function()
      local doc, err = sdp.parse(audio_sdp_enc("L24"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts AM824 encoding at 48000 Hz", function()
      local doc, err = sdp.parse(audio_sdp_enc("AM824", 48000), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects unknown audio encoding name", function()
      local doc = sdp.parse(audio_sdp_enc("OPUS"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("OPUS", err.message)
      assert.equal("ST 2110-30 §7.1", err.spec_ref)
    end)

    it("rejects another unknown audio encoding name (AAC)", function()
      local doc = sdp.parse(audio_sdp_enc("AAC"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("AAC", err.message)
    end)
  end)

  -- ── ST 2110-40: VPID_Code optional fmtp param ─────────────────────────────────

  describe("ST 2110-40 VPID_Code optional fmtp param (§7.2)", function()
    local function anc_sdp(fmtp_str)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Ancillary",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5020 RTP/AVP 96",
        "c=IN IP4 239.100.0.3/64",
        "a=rtpmap:96 smpte291/90000",
        "a=fmtp:96 " .. fmtp_str,
        "a=mediaclk:direct=0",
      }, "\r\n")
    end

    it("accepts a valid integer VPID_Code", function()
      local doc, err = sdp.parse(anc_sdp("DID_SDID={0x61,0x02}; VPID_Code=133"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts VPID_Code=0", function()
      local doc, err = sdp.parse(anc_sdp("DID_SDID={0x61,0x02}; VPID_Code=0"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects non-integer VPID_Code", function()
      local doc = sdp.parse(anc_sdp("DID_SDID={0x61,0x02}; VPID_Code=notanumber"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("VPID_Code", err.message)
      assert.equal("ST 2110-40 §7.2", err.spec_ref)
    end)

    it("rejects negative VPID_Code", function()
      local doc = sdp.parse(anc_sdp("DID_SDID={0x61,0x02}; VPID_Code=-1"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("VPID_Code", err.message)
    end)

    it("absent VPID_Code is accepted (optional)", function()
      local doc, err = sdp.parse(anc_sdp("DID_SDID={0x61,0x02}"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  -- ── ST 2110-41: DIT value format ───────────────────────────────────────────────

  describe("ST 2110-41 DIT value format (§7.2)", function()
    local function meta_sdp(fmtp_str)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Metadata",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5030 RTP/AVP 96",
        "c=IN IP4 239.100.0.4/64",
        "a=rtpmap:96 ST2110-41/90000",
        "a=fmtp:96 " .. fmtp_str,
        "a=mediaclk:direct=0",
      }, "\r\n")
    end

    it("accepts DIT=0", function()
      local doc, err = sdp.parse(meta_sdp("SSN=ST2110-41:2024; DIT=0"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts DIT=100", function()
      local doc, err = sdp.parse(meta_sdp("SSN=ST2110-41:2024; DIT=100"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects non-integer DIT", function()
      local doc = sdp.parse(meta_sdp("SSN=ST2110-41:2024; DIT=notanumber"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("DIT", err.message)
      assert.equal("ST 2110-41 §7.2", err.spec_ref)
    end)

    it("rejects DIT with decimal point", function()
      local doc = sdp.parse(meta_sdp("SSN=ST2110-41:2024; DIT=1.5"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("DIT", err.message)
    end)

    it("rejects empty DIT value", function()
      local doc = sdp.parse(meta_sdp("SSN=ST2110-41:2024; DIT="))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("DIT", err.message)
    end)
  end)

  -- ── rtpmap / fmtp payload type consistency ────────────────────────────────────

  describe("rtpmap and fmtp payload type consistency (ST 2110-10 §7)", function()
    local VALID_FMTP = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022"

    local function video_with_pts(rtpmap_pt, fmtp_pt)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5000 RTP/AVP " .. rtpmap_pt,
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:" .. rtpmap_pt .. " raw/90000",
        "a=fmtp:" .. fmtp_pt .. " " .. VALID_FMTP,
        "a=mediaclk:direct=0",
      }, "\r\n")
    end

    it("accepts matching payload types", function()
      local doc, err = sdp.parse(video_with_pts(96, 96), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects when fmtp PT does not match rtpmap PT", function()
      local doc = sdp.parse(video_with_pts(96, 97))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("payload type", err.message)
      assert.equal("ST 2110-10 §7", err.spec_ref)
    end)
  end)

  -- ── ST 2110-30 channel count ──────────────────────────────────────────────────

  describe("ST 2110-30 channel count (§7.1)", function()
    local function audio_sdp_ch(ch)
      local rtpmap = ch ~= nil and ("a=rtpmap:97 L24/48000/" .. ch) or "a=rtpmap:97 L24/48000"
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Audio",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=audio 5010 RTP/AVP 97",
        "c=IN IP4 239.100.0.2/64",
        rtpmap,
        "a=fmtp:97 channel-order=SMPTE2110.(ST)",
        "a=mediaclk:direct=0",
      }, "\r\n")
    end

    for _, ch in ipairs({ 1, 8, 16 }) do
      it("accepts channel count " .. ch, function()
        local doc, err = sdp.parse(audio_sdp_ch(ch), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)
    end

    it("rejects channel count 0", function()
      local doc = sdp.parse(audio_sdp_ch(0))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("channel count", err.message)
      assert.equal("ST 2110-30 §7.1", err.spec_ref)
    end)

    it("rejects channel count 17", function()
      local doc = sdp.parse(audio_sdp_ch(17))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("channel count", err.message)
    end)

    it("rejects rtpmap with no channel count", function()
      local doc = sdp.parse(audio_sdp_ch(nil))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("channel count", err.message)
      assert.equal("ST 2110-30 §7.1", err.spec_ref)
    end)
  end)

  -- ── ST 2110-30 a=ptime ────────────────────────────────────────────────────────

  describe("ST 2110-30 a=ptime (§7.2)", function()
    local function audio_with_ptime(ptime_val)
      local lines = {
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Audio",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=audio 5010 RTP/AVP 97",
        "c=IN IP4 239.100.0.2/64",
        "a=rtpmap:97 L24/48000/8",
        "a=fmtp:97 channel-order=SMPTE2110.(ST)",
        "a=mediaclk:direct=0",
      }
      if ptime_val ~= nil then lines[#lines + 1] = "a=ptime:" .. ptime_val end
      return table.concat(lines, "\r\n")
    end

    it("accepts absence of a=ptime (optional)", function()
      local doc, err = sdp.parse(audio_with_ptime(nil), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts a=ptime:1", function()
      local doc, err = sdp.parse(audio_with_ptime(1), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts a non-1 positive ptime", function()
      local doc, err = sdp.parse(audio_with_ptime(20), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects a=ptime:0", function()
      local doc = sdp.parse(audio_with_ptime(0))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("ptime", err.message)
      assert.equal("ST 2110-30 §7.2", err.spec_ref)
    end)

    it("rejects a non-numeric ptime", function()
      local doc = sdp.parse(audio_with_ptime("notanumber"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("ptime", err.message)
    end)
  end)

  -- ── ST 2110-20 CMAX=0 rejection ───────────────────────────────────────────────

  describe("ST 2110-20 CMAX=0 rejection", function()
    local BASE = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022"

    it("rejects CMAX=0 (positive integer required)", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 " .. BASE .. "; CMAX=0",
        "a=mediaclk:direct=0",
      }, "\r\n")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("CMAX", err.message)
      assert.equal("ST 2110-20 §7.2", err.spec_ref)
    end)
  end)

  -- ── ts-refclk ptp= GMID octet count ──────────────────────────────────────────

  describe("ts-refclk ptp= GMID octet count", function()
    local function with_ptp(gmid)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022",
        "a=mediaclk:direct=0",
        "a=ts-refclk:ptp=IEEE1588-2008:" .. gmid,
      }, "\r\n")
    end

    it("rejects ptp= GMID with 6 octets instead of 8", function()
      local doc = sdp.parse(with_ptp("00-11-22-33-44-55"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("ts%-refclk", err.message)
    end)

    it("rejects ptp= GMID with 9 octets instead of 8", function()
      local doc = sdp.parse(with_ptp("00-11-22-33-44-55-66-77-88"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("ts%-refclk", err.message)
    end)
  end)

  -- ── ts-refclk ntp= address format (LPEG) ─────────────────────────────────────

  describe("ts-refclk ntp= address format (LPEG)", function()
    local function with_ntp(addr)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022",
        "a=mediaclk:direct=0",
        "a=ts-refclk:ntp=" .. addr,
      }, "\r\n")
    end

    it("accepts a valid IPv4 address", function()
      local doc, err = sdp.parse(with_ntp("10.0.0.1"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts IPv4 with max octet values (255.255.255.255)", function()
      local doc, err = sdp.parse(with_ntp("255.255.255.255"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts a fully-qualified hostname", function()
      local doc, err = sdp.parse(with_ntp("time.google.com"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts a single-label hostname", function()
      local doc, err = sdp.parse(with_ntp("ntpserver"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts an IPv6 address", function()
      local doc, err = sdp.parse(with_ntp("2001:db8::1"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects a token with special characters", function()
      local doc = sdp.parse(with_ntp("not@valid!"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("ts%-refclk", err.message)
    end)

    it("rejects a hostname label starting with a hyphen", function()
      local doc = sdp.parse(with_ntp("-badhost.com"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("ts%-refclk", err.message)
    end)

    it("accepts IPv6 loopback (::1)", function()
      local doc, err = sdp.parse(with_ntp("::1"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts IPv6 all-zeros (::)", function()
      local doc, err = sdp.parse(with_ntp("::"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts a full compressed IPv6 address", function()
      local doc, err = sdp.parse(with_ntp("2001:db8::8a2e:370:7334"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts IPv4-mapped IPv6 (::ffff:192.0.2.1)", function()
      local doc, err = sdp.parse(with_ntp("::ffff:192.0.2.1"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects triple-colon (:::)", function()
      local doc = sdp.parse(with_ntp(":::"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("ts%-refclk", err.message)
    end)

    it("rejects too-few groups without :: (1:2:3)", function()
      local doc = sdp.parse(with_ntp("1:2:3"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("ts%-refclk", err.message)
    end)
  end)

  -- ── m= protocol field validation (ST 2110-10 §8.1) ───────────────────────────

  describe("m= protocol field validation (ST 2110-10 §8.1)", function()
    local function with_proto(proto)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "m=video 5000 " .. proto .. " 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        "a=mediaclk:direct=0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      }, "\r\n")
    end

    it("accepts RTP/AVP protocol", function()
      local doc, err = sdp.parse(with_proto("RTP/AVP"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects UDP protocol", function()
      local doc = sdp.parse(with_proto("UDP"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("proto", err.message)
      assert.matches("ST 2110%-10", err.spec_ref)
    end)

    it("rejects RTP/SAVPF protocol", function()
      local doc = sdp.parse(with_proto("RTP/SAVPF"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("proto", err.message)
    end)

    it("error field_path identifies the media block", function()
      local doc = sdp.parse(with_proto("UDP"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("media%[1%]", err.field_path)
    end)
  end)

  -- ── c= connection address validation (ST 2110-10 §6.5) ───────────────────────

  describe("c= connection address validation (ST 2110-10 §6.5)", function()
    local PTP = "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"
    local VFMTP = "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"

    local function with_connection(addr)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 " .. addr,
        "a=rtpmap:96 raw/90000",
        VFMTP,
        "a=mediaclk:direct=0",
        PTP,
      }, "\r\n")
    end

    it("accepts IPv4 multicast address with TTL", function()
      local doc = sdp.parse(with_connection("239.100.0.1/64"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("accepts IPv4 unicast address without TTL", function()
      local doc = sdp.parse(with_connection("192.168.1.100"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("rejects IPv4 multicast address without TTL", function()
      local doc = sdp.parse(with_connection("239.100.0.1"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("TTL", err.message)
    end)

    it("rejects Local Network Control Block 224.0.0.0/24", function()
      local doc = sdp.parse(with_connection("224.0.0.5/32"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("forbidden", err.message)
    end)

    it("rejects Internetwork Control Block 224.0.1.0/24", function()
      local doc = sdp.parse(with_connection("224.0.1.5/32"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("forbidden", err.message)
    end)

    it("error field_path identifies the media block connection", function()
      local doc = sdp.parse(with_connection("239.100.0.1"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("media%[1%]", err.field_path)
    end)

    it("spec_ref is ST 2110-10 §6.5", function()
      local doc = sdp.parse(with_connection("224.0.0.5/32"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("ST 2110%-10", err.spec_ref)
    end)
  end)
end)
