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
end)
