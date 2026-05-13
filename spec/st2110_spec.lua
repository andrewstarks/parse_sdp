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
    "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; colorimetry=BT709; PM=2110GPM; TP=2110TPN",
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; colorimetry=BT709; PM=2110GPM; TP=2110TPN",
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; colorimetry=BT709; PM=2110GPM; TP=2110TPN",
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; colorimetry=BT709; PM=2110GPM; TP=2110TPN",
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; colorimetry=BT709; PM=2110GPM; TP=2110TPN",
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; colorimetry=BT709; PM=2110GPM; TP=2110TPN",
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; colorimetry=BT709; PM=2110GPM; TP=2110TPN",
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; colorimetry=BT709; PM=2110GPM; TP=2110TPN",
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; colorimetry=BT709; PM=2110GPM; TP=2110TPN",
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
end)
