describe("IPMX validation", function()
  local sdp = require("parse_sdp")

  -- Minimal valid IPMX SDP: passes ST 2110 + has a=extmap
  local IPMX_VIDEO_SDP = table.concat({
    "v=0",
    "o=- 1234567890 1 IN IP4 192.168.1.1",
    "s=IPMX Video",
    "t=0 0",
    "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
    "m=video 5000 RTP/AVP 96",
    "c=IN IP4 239.100.0.1/64",
    "a=rtpmap:96 raw/90000",
    "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; colorimetry=BT709; PM=2110GPM; TP=2110TPN",
    "a=mediaclk:direct=0",
    "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
    "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
  }, "\r\n")

  -- Valid ST 2110 SDP that lacks a=extmap (not IPMX)
  local ST2110_ONLY_SDP = table.concat({
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

  -- Generic RFC 4566 SDP (no media blocks, no ST 2110 attributes)
  local GENERIC_SDP = table.concat({
    "v=0",
    "o=- 1 1 IN IP4 127.0.0.1",
    "s=Plain SDP",
    "t=0 0",
  }, "\r\n")

  describe("sdp.parse with 'ipmx' mode", function()
    it("returns a doc for valid IPMX SDP (localmac ts-refclk, not PTP)", function()
      local doc, err = sdp.parse(IPMX_VIDEO_SDP, "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("returns nil+err for ST 2110 SDP missing extmap", function()
      local doc, err = sdp.parse(ST2110_ONLY_SDP, "ipmx")
      assert.is_nil(doc)
      assert.is_table(err)
      assert.matches("extmap", err.message)
    end)

    it("returns nil+err for generic SDP (fails ST 2110 tier first)", function()
      local doc, err = sdp.parse(GENERIC_SDP, "ipmx")
      assert.is_nil(doc)
      assert.is_table(err)
      assert.is_string(err.message)
    end)
  end)

  describe("doc:validate('ipmx')", function()
    it("returns true for valid IPMX SDP", function()
      local doc = sdp.parse(IPMX_VIDEO_SDP)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("returns nil+err for ST 2110 SDP missing extmap", function()
      local doc = sdp.parse(ST2110_ONLY_SDP)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("extmap", err.message)
    end)

    it("error includes field_path and spec_ref for missing extmap", function()
      local doc = sdp.parse(ST2110_ONLY_SDP)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.is_string(err.field_path)
      assert.is_string(err.spec_ref)
    end)

    it("returns nil+err for generic SDP (ST 2110 tier fails first)", function()
      local doc = sdp.parse(GENERIC_SDP)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.is_string(err.message)
    end)
  end)

  describe("doc:is_ipmx()", function()
    it("returns true for valid IPMX SDP", function()
      local doc = sdp.parse(IPMX_VIDEO_SDP)
      assert.is_table(doc)
      assert.equal(true, doc:is_ipmx())
    end)

    it("returns false for ST 2110 SDP without extmap", function()
      local doc = sdp.parse(ST2110_ONLY_SDP)
      assert.is_table(doc)
      assert.equal(false, doc:is_ipmx())
    end)

    it("returns false for generic SDP", function()
      local doc = sdp.parse(GENERIC_SDP)
      assert.is_table(doc)
      assert.equal(false, doc:is_ipmx())
    end)
  end)
end)
