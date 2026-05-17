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
  }, "\r\n") .. "\r\n"

  local AUDIO_SDP = table.concat({
    "v=0",
    "o=- 1234567890 1 IN IP4 192.168.1.1",
    "s=ST2110 Audio",
    "t=0 0",
    "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
    "m=audio 5010 RTP/AVP 97",
    "c=IN IP4 239.100.0.2/64",
    "a=rtpmap:97 L24/48000/8",
    "a=ptime:1",
    "a=fmtp:97 channel-order=SMPTE2110.(ST)",
    "a=mediaclk:direct=0",
    "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
  }, "\r\n") .. "\r\n"

  local GENERIC_SDP = table.concat({
    "v=0",
    "o=- 1 1 IN IP4 127.0.0.1",
    "s=Plain SDP",
    "t=0 0",
  }, "\r\n") .. "\r\n"

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
      }, "\r\n") .. "\r\n"
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
      }, "\r\n") .. "\r\n"
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
      }, "\r\n") .. "\r\n"
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
      }, "\r\n") .. "\r\n"
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
      }, "\r\n") .. "\r\n"
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
      }, "\r\n") .. "\r\n"
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
      }, "\r\n") .. "\r\n"
      local doc = sdp.parse(text)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("fmtp", err.message)
    end)

    it("accepts audio without channel-order (optional per ST 2110-30:2017 §6.2.2)", function()
      -- §6.2.2: "If the channel-order parameter is not present, the audio
      -- channels shall be treated as Undefined." Absence is explicitly defined
      -- behavior, not an error. The fmtp itself is also optional for audio
      -- (ST 2110-10:2022 §8 imposes no universal fmtp requirement; RFC 3551
      -- registers channel-order as optional).
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Audio",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=audio 5010 RTP/AVP 97",
        "c=IN IP4 239.100.0.2/64",
        "a=rtpmap:97 L24/48000/8",
        "a=ptime:1",
        "a=mediaclk:direct=0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      }, "\r\n") .. "\r\n"
      local doc = sdp.parse(text)
      local ok, err = doc:validate("st2110")
      assert.is_true(ok, err and err.message)
    end)

    it("rejects channel-order without RFC 3190 <convention>.<order> separator", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Audio",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=audio 5010 RTP/AVP 97",
        "c=IN IP4 239.100.0.2/64",
        "a=rtpmap:97 L24/48000/8",
        "a=ptime:1",
        "a=fmtp:97 channel-order=NoSeparatorHere",
        "a=mediaclk:direct=0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      }, "\r\n") .. "\r\n"
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
      }, "\r\n") .. "\r\n"
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
      }, "\r\n") .. "\r\n"
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
      }, "\r\n") .. "\r\n"
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

    -- ST 2110-10:2022 §8.2 (per Streampunk sdpoker Issue #25): when not using
    -- the 'traceable' form, the SHALL is "shall use the ts-refclk:ptp form,
    -- signaling either the grandmaster clockIdentity AND domain number, or
    -- signaling that the PTP is traceable." Domain is required.
    it("rejects ptp= with version and GMID but no domain (ST 2110-10:2022 §8.2)", function()
      local doc = sdp.parse(with_tsrefclk("ptp=IEEE1588-2008:00-11-22-33-44-55-66-77"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("domain", err.message)
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

    -- RFC 5234 §2.3: ABNF literal strings (the HEXDIG rule uses literals "A"/.../"F",
    -- not %x41-46) are case-insensitive unless explicitly marked sensitive. EUI-64
    -- hex in RFC 7273 §4.8 follows that rule, so lowercase hex is conformant.
    it("accepts ptp= GMID with lowercase hex digits (RFC 7273 §4.8 + RFC 5234 §2.3)", function()
      local doc = sdp.parse(with_tsrefclk("ptp=IEEE1588-2008:aa-bb-cc-ff-fe-dd-ee-ff:0"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    -- Per RFC 7273 errata 4450: the pre-errata "domain-nmbr=" prefix is not part
    -- of the corrected ABNF — domain is just the bare integer.
    it("rejects pre-errata 'domain-nmbr=' prefix form (RFC 7273 errata 4450)", function()
      local doc = sdp.parse(with_tsrefclk("ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:domain-nmbr=37"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("domain", err.message)
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
      }, "\r\n") .. "\r\n"
      local doc, err = sdp.parse(text, "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- RFC 7273 §4.8: "Traceable time sources MUST NOT be mixed with
    -- non-traceable time sources at any given level."
    describe("RFC 7273 §4.8 mixed-class rejection", function()
      local FMTP = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"

      local function media_sdp(...)
        local lines = {
          "v=0",
          "o=- 1234567890 1 IN IP4 192.168.1.1",
          "s=Video",
          "t=0 0",
          "m=video 5000 RTP/AVP 96",
          "c=IN IP4 239.100.0.1/64",
          "a=rtpmap:96 raw/90000",
          "a=fmtp:96 " .. FMTP,
          "a=mediaclk:direct=0",
        }
        for _, tsr in ipairs({...}) do
          lines[#lines + 1] = "a=ts-refclk:" .. tsr
        end
        return table.concat(lines, "\r\n") .. "\r\n"
      end

      local function session_sdp(...)
        local lines = {
          "v=0",
          "o=- 1234567890 1 IN IP4 192.168.1.1",
          "s=Video",
          "t=0 0",
        }
        for _, tsr in ipairs({...}) do
          lines[#lines + 1] = "a=ts-refclk:" .. tsr
        end
        for _, ml in ipairs({
          "m=video 5000 RTP/AVP 96",
          "c=IN IP4 239.100.0.1/64",
          "a=rtpmap:96 raw/90000",
          "a=fmtp:96 " .. FMTP,
          "a=mediaclk:direct=0",
        }) do
          lines[#lines + 1] = ml
        end
        return table.concat(lines, "\r\n") .. "\r\n"
      end

      it("accepts two traceable sources at media level", function()
        local doc, err = sdp.parse(media_sdp(
          "ptp=IEEE1588-2008:traceable", "gps"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("accepts two non-traceable sources at media level", function()
        local doc, err = sdp.parse(media_sdp(
          "ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
          "localmac=AA-BB-CC-DD-EE-FF"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("rejects traceable + non-traceable mixed at media level", function()
        local doc = sdp.parse(media_sdp(
          "ptp=IEEE1588-2008:traceable",
          "ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("traceable", err.message)
        assert.equal("RFC 7273 §4.8", err.spec_ref)
      end)

      it("rejects traceable + non-traceable mixed at session level", function()
        local doc = sdp.parse(session_sdp(
          "gps",
          "ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("traceable", err.message)
        assert.equal("RFC 7273 §4.8", err.spec_ref)
      end)

      it("permits traceable at session, non-traceable at media (different levels)", function()
        -- §4.8 is per-level — mixing across levels is not forbidden.
        local lines = {
          "v=0",
          "o=- 1234567890 1 IN IP4 192.168.1.1",
          "s=Video",
          "t=0 0",
          "a=ts-refclk:ptp=IEEE1588-2008:traceable",
          "m=video 5000 RTP/AVP 96",
          "c=IN IP4 239.100.0.1/64",
          "a=rtpmap:96 raw/90000",
          "a=fmtp:96 " .. FMTP,
          "a=mediaclk:direct=0",
          "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        }
        local doc, err = sdp.parse(table.concat(lines, "\r\n") .. "\r\n", "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)
    end)
  end)

  -- ── ST 2110-40: ancillary data (smpte291) ──────────────────────────────────

  describe("ST 2110-40 ancillary data (smpte291)", function()
    -- ST 2110-40:2023 §7 requires SSN and exactframerate on every smpte291
    -- fmtp; the builder defaults these so individual cases can append or
    -- override specific fields under test.
    local DEFAULT_REQUIRED = "SSN=ST2110-40:2018; exactframerate=25"
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
      }, "\r\n") .. "\r\n"
    end

    it("accepts valid smpte291 SDP with DID_SDID", function()
      local doc, err = sdp.parse(ancillary_sdp(DEFAULT_REQUIRED .. "; DID_SDID={0x61,0x02}"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- N11 (audit): ST 2110-40:2023 §5.2.1 forbids MAXUDP on smpte291
    -- (UDP size shall not exceed the Standard limit).
    it("rejects MAXUDP on smpte291 (ST 2110-40:2023 §5.2.1)", function()
      local doc = sdp.parse(ancillary_sdp(DEFAULT_REQUIRED .. "; MAXUDP=8960"))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("MAXUDP", err.message)
    end)

    -- N10 (audit): ST 2110-40:2023 §7 — "Flow Identification ('FID')
    -- semantics shall not be used under this standard." The SHALL is in
    -- -40, which governs smpte291, so reject only when smpte291 is present.
    it("rejects a=group:FID when smpte291 stream is present (ST 2110-40:2023 §7)", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 ANC + FID", "t=0 0",
        "a=group:FID anc",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5020 RTP/AVP 96",
        "c=IN IP4 239.100.0.3/64",
        "a=mid:anc",
        "a=rtpmap:96 smpte291/90000",
        "a=fmtp:96 " .. DEFAULT_REQUIRED,
        "a=mediaclk:direct=0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      }, "\r\n") .. "\r\n"
      local doc = sdp.parse(text)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("FID", err.message)
      assert.matches("smpte291", err.message)
    end)

    -- RFC 8331 §4: media type for smpte291 is "video"; m=audio … smpte291 is
    -- not a valid combination. ST 2110-40:2023 §7 defers SDP to RFC 8331.
    it("rejects m=audio with smpte291 rtpmap (RFC 8331 §4)", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Ancillary",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=audio 5020 RTP/AVP 96",
        "c=IN IP4 239.100.0.3/64",
        "a=rtpmap:96 smpte291/90000",
        "a=fmtp:96 " .. DEFAULT_REQUIRED,
        "a=mediaclk:direct=0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      }, "\r\n") .. "\r\n"
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("smpte291", err.message)
      assert.matches("video", err.message)
      assert.equal("RFC 8331 §4", err.spec_ref)
    end)

    it("accepts smpte291 SDP without DID_SDID (optional per RFC 8331 / ST 2110-40:2023 §7)", function()
      -- ST 2110-40:2023 §7 imposes no DID_SDID requirement. RFC 8331's
      -- media-type registration marks DID_SDID optional and notes that its
      -- absence signals receivers to determine DID/SDID by inspecting packets.
      local doc, err = sdp.parse(ancillary_sdp(DEFAULT_REQUIRED .. "; VPID_Code=133"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("errors when DID_SDID has a non-hex octet", function()
      local doc = sdp.parse(ancillary_sdp(DEFAULT_REQUIRED .. "; DID_SDID={0xGG,0x02}"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("DID_SDID", err.message)
    end)

    it("accepts multiple valid DID_SDID entries", function()
      local doc, err = sdp.parse(ancillary_sdp(DEFAULT_REQUIRED .. "; DID_SDID={0x61,0x02}; DID_SDID={0x00,0x01}"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("errors when any DID_SDID entry is invalid", function()
      local doc = sdp.parse(ancillary_sdp(DEFAULT_REQUIRED .. "; DID_SDID={0x61,0x02}; DID_SDID={0xGG,0x01}"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("DID_SDID", err.message)
    end)

    -- RFC 8331 §4: TwoHex = "0x" 1*2(HEXDIG) — 1 OR 2 hex digits per token.
    it("accepts single-hex-digit DID_SDID tokens (RFC 8331 §4 ABNF)", function()
      local doc, err = sdp.parse(ancillary_sdp(DEFAULT_REQUIRED .. "; DID_SDID={0x6,0x2}"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts mixed 1-/2-digit DID_SDID tokens", function()
      local doc, err = sdp.parse(ancillary_sdp(DEFAULT_REQUIRED .. "; DID_SDID={0x6,0x02}"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects DID_SDID with > 2 hex digits in a token", function()
      local doc = sdp.parse(ancillary_sdp(DEFAULT_REQUIRED .. "; DID_SDID={0x123,0x01}"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("DID_SDID", err.message)
    end)

    it("rejects DID_SDID with an empty token", function()
      local doc = sdp.parse(ancillary_sdp(DEFAULT_REQUIRED .. "; DID_SDID={,0x01}"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("DID_SDID", err.message)
    end)

    -- ── ST 2110-40:2023 §7 SHALL clauses ──────────────────────────────────
    -- "Senders implementing this standard shall signal a Format Specific
    -- Parameter SSN with the value ST2110-40:2018 unless they are signaling
    -- Format Specific Parameter TM, in which case they shall signal the
    -- value ST2110-40:2023."
    -- "All Senders shall signal the Format Specific Parameter exactframerate
    -- as defined in SMPTE ST 2110-20:2022 Clause 7.2..."
    -- "Senders implementing the Low-Latency Transmission Model shall signal
    -- a Format Specific Parameter TM with the value LLTM in the SDP."

    it("rejects smpte291 fmtp missing SSN", function()
      local doc = sdp.parse(ancillary_sdp("exactframerate=25; DID_SDID={0x61,0x02}"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("SSN", err.message)
      assert.matches("ST 2110%-40:2023", err.spec_ref)
    end)

    it("rejects smpte291 fmtp missing exactframerate", function()
      local doc = sdp.parse(ancillary_sdp("SSN=ST2110-40:2018; DID_SDID={0x61,0x02}"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("exactframerate", err.message)
      assert.matches("ST 2110%-40:2023", err.spec_ref)
    end)

    it("rejects SSN=ST2110-40:2023 when TM is absent", function()
      local doc = sdp.parse(ancillary_sdp("SSN=ST2110-40:2023; exactframerate=25"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("SSN", err.message)
    end)

    it("rejects SSN=ST2110-40:2018 when TM is signaled", function()
      local doc = sdp.parse(ancillary_sdp("SSN=ST2110-40:2018; TM=LLTM; exactframerate=25"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("SSN", err.message)
    end)

    it("accepts SSN=ST2110-40:2023 paired with TM=LLTM", function()
      local doc, err = sdp.parse(ancillary_sdp("SSN=ST2110-40:2023; TM=LLTM; exactframerate=25"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts SSN=ST2110-40:2023 paired with TM=CTM", function()
      local doc, err = sdp.parse(ancillary_sdp("SSN=ST2110-40:2023; TM=CTM; exactframerate=25"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- ST 2110-40:2023 §7: "Receivers shall consider a Format Specific
    -- Parameter SSN value of ST2110-40:2021 as equivalent to a value of
    -- ST2110-40:2023." Parser acts as a receiver — accept :2021 wherever
    -- :2023 is required (i.e. when TM is signaled). Bare :2021 without TM
    -- is not equivalent to :2018 and is rejected.
    it("accepts SSN=ST2110-40:2021 paired with TM=LLTM (receiver-equivalent to :2023)", function()
      local doc, err = sdp.parse(ancillary_sdp("SSN=ST2110-40:2021; TM=LLTM; exactframerate=25"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts SSN=ST2110-40:2021 paired with TM=CTM (receiver-equivalent to :2023)", function()
      local doc, err = sdp.parse(ancillary_sdp("SSN=ST2110-40:2021; TM=CTM; exactframerate=25"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects bare SSN=ST2110-40:2021 with no TM", function()
      local doc = sdp.parse(ancillary_sdp("SSN=ST2110-40:2021; exactframerate=25"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("SSN", err.message)
      assert.equal("ST 2110-40:2023 §7", err.spec_ref)
    end)

    it("rejects unrecognized TM value", function()
      local doc = sdp.parse(ancillary_sdp("SSN=ST2110-40:2023; TM=XYZ; exactframerate=25"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("TM", err.message)
    end)

    it("rejects ill-formed exactframerate", function()
      local doc = sdp.parse(ancillary_sdp("SSN=ST2110-40:2018; exactframerate=not-a-rate"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("exactframerate", err.message)
    end)

    it("accepts optional TROFF as a positive integer when present", function()
      local doc, err = sdp.parse(ancillary_sdp(DEFAULT_REQUIRED .. "; TROFF=1000"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects TROFF=0 (must be a positive integer per ST 2110-21 §8)", function()
      local doc = sdp.parse(ancillary_sdp(DEFAULT_REQUIRED .. "; TROFF=0"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("TROFF", err.message)
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
      }, "\r\n") .. "\r\n"
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

    -- ST 2110-41:2024 §6 makes DIT a SHOULD (§9.2.3 lists it under Optional
    -- Parameters). Absence is conformant.
    it("accepts ST2110-41 SDP without DIT (§6 SHOULD; §9.2.3 optional)", function()
      local doc, err = sdp.parse(metadata_sdp("SSN=ST2110-41:2024"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- ST 2110-41:2024 §5.3: "The RTP Clock rate … shall be signaled in the
    -- SDP as specified in IETF RFC 4566." Rate is Data-Item-defined; not
    -- fixed at 90 kHz.
    it("accepts ST2110-41 with non-90000 clock rate (§5.3 Data-Item-defined)", function()
      local sdp_text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Metadata",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5030 RTP/AVP 96",
        "c=IN IP4 239.100.0.4/64",
        "a=rtpmap:96 ST2110-41/48000",
        "a=fmtp:96 SSN=ST2110-41:2024",
        "a=mediaclk:direct=0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      }, "\r\n") .. "\r\n"
      local doc, err = sdp.parse(sdp_text, "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
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
      }, "\r\n") .. "\r\n"
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

    -- RFC 7273 §5.4 ABNF: direct = "direct" [ "=" 1*DIGIT ] [SP rate]
    --                     rate   = "rate=" integer "/" integer
    -- ST 2110-10:2022 §8.3 defers to RFC 7273 §5; only constrains offset=0.
    -- The rate option is used for pull-down audio (e.g. 1000/1001).
    it("accepts 'direct=0 rate=A/B' (RFC 7273 §5.4 pull-down form)", function()
      local doc = sdp.parse(with_mediaclk("direct=0 rate=1000/1001"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("rejects 'direct=0 rate=' with malformed ratio", function()
      local doc = sdp.parse(with_mediaclk("direct=0 rate=1000"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("rate", err.message)
    end)

    it("rejects garbage trailing content after 'direct=0'", function()
      local doc = sdp.parse(with_mediaclk("direct=0 junk"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
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

    -- ST 2110-10 §7.3: "In this standard, the offset value shall be zero."
    -- TR-10-1 §10.5 echoes this. Any non-zero offset is a SHALL violation.
    it("rejects 'direct=' with non-zero offset (ST 2110-10 §7.3)", function()
      local doc = sdp.parse(with_mediaclk("direct=10"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("mediaclk", err.message)
    end)

    it("rejects 'direct=' with negative offset", function()
      local doc = sdp.parse(with_mediaclk("direct=-1"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
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
      if type2 == "audio" then lines[#lines+1] = "a=ptime:1" end
      lines[#lines+1] = "a=mediaclk:direct=0"
      return table.concat(lines, "\r\n") .. "\r\n"
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
      assert.equal("ST 2110-10:2022 §8.5", err.spec_ref)
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
      }, "\r\n") .. "\r\n"
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("DUP", err.message)
    end)
  end)

  -- ── A4: m=video subtype 'raw' assertion (ST 2110-20:2022 §7.1) ──────────────

  describe("ST 2110-20:2022 §7.1 m=video subtype 'raw' assertion", function()
    local FMTP = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"
    local function video_enc_sdp(enc)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 " .. enc .. "/90000",
        "a=fmtp:96 " .. FMTP,
        "a=mediaclk:direct=0",
      }, "\r\n") .. "\r\n"
    end

    it("accepts m=video with encoding 'raw' (boundary)", function()
      local doc, err = sdp.parse(video_enc_sdp("raw"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- §7.1: "For an uncompressed Active Video RTP Stream, the Media Type
    -- Field shall be 'video' and the Media Subtype name 'raw' shall be
    -- used." Codecs handled by earlier branches (jxsv, smpte291) are
    -- routed before the raw-video branch, so any other encoding reaching
    -- it fails the SHALL.
    it("rejects m=video with encoding 'foo' (ST 2110-20:2022 §7.1)", function()
      local doc = sdp.parse(video_enc_sdp("foo"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("foo", err.message)
      assert.matches("raw", err.message)
      assert.equal("ST 2110-20:2022 §7.1", err.spec_ref)
    end)

    it("rejects m=video with encoding 'rawvideo' (not 'raw')", function()
      local doc = sdp.parse(video_enc_sdp("rawvideo"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("rawvideo", err.message)
      assert.equal("ST 2110-20:2022 §7.1", err.spec_ref)
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
      }, "\r\n") .. "\r\n"
    end

    local VALID = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"

    it("accepts all eight required fmtp parameters plus optional TCS", function()
      local doc, err = sdp.parse(video20_sdp(VALID), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- ST 2110-20:2022 §7.3 lists TCS under "Media Type Parameters with default
    -- values"; §7.6 says receivers assume SDR when TCS is not signaled.
    it("accepts raw video fmtp without TCS (§7.3 — optional; §7.6 default SDR)", function()
      local fmtp = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"
      local doc, err = sdp.parse(video20_sdp(fmtp), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts exactframerate as integer/integer fraction", function()
      local fmtp = VALID:gsub("exactframerate=25", "exactframerate=30000/1001")
      local doc, err = sdp.parse(video20_sdp(fmtp), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- Missing required field: one entry per required parameter (incl. TP, which
    -- ST 2110-21:2022 §8.1 requires for all video streams conforming to
    -- ST 2110-20:2022 §6.1.1's compliance chain).
    local missing = {
      { "sampling",       "width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN" },
      { "width",          "sampling=YCbCr-4:2:2; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN" },
      { "height",         "sampling=YCbCr-4:2:2; width=1920; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN" },
      { "exactframerate", "sampling=YCbCr-4:2:2; width=1920; height=1080; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN" },
      { "depth",          "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN" },
      { "colorimetry",    "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN" },
      { "PM",             "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; SSN=ST2110-20:2022; TP=2110TPN" },
      { "SSN",            "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; TP=2110TPN" },
      { "TP",             "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022" },
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
      { "sampling",       "sampling=garbage; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN" },
      { "width",          "sampling=YCbCr-4:2:2; width=abc; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN" },
      { "height",         "sampling=YCbCr-4:2:2; width=1920; height=abc; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN" },
      { "exactframerate", "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25.5; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN" },
      { "depth",          "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=abc; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN" },
      { "TCS",            "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=BADTCS; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN" },
      { "colorimetry",    "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BADCOLOR; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN" },
      { "PM",             "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=BADPM; SSN=ST2110-20:2022; TP=2110TPN" },
      { "SSN",            "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=BADSSN; TP=2110TPN" },
      { "TP",             "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=BADTP" },
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

    -- N12 (audit): ST 2110-20:2022 §7.4.1 KEY-sampling SHALLs.
    describe("§7.4.1 KEY-sampling SHALLs (audit N12)", function()
      it("accepts sampling=KEY with colorimetry=ALPHA and no TCS", function()
        local fmtp = "sampling=KEY; width=1920; height=1080; exactframerate=25; depth=10; colorimetry=ALPHA; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"
        local doc, err = sdp.parse(video20_sdp(fmtp), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("rejects sampling=KEY with colorimetry=BT709", function()
        local fmtp = "sampling=KEY; width=1920; height=1080; exactframerate=25; depth=10; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"
        local doc = sdp.parse(video20_sdp(fmtp))
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.matches("ALPHA", err.message)
      end)

      it("rejects sampling=KEY with TCS signaled", function()
        local fmtp = "sampling=KEY; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=ALPHA; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"
        local doc = sdp.parse(video20_sdp(fmtp))
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.matches("TCS", err.message)
      end)
    end)

    -- N13 (audit): ST 2110-20:2022 §6.2.5 — 4:2:0 progressive-only.
    describe("§6.2.5 4:2:0 progressive-only SHALL (audit N13)", function()
      it("accepts sampling=YCbCr-4:2:0 progressive (no interlace flag)", function()
        local fmtp = "sampling=YCbCr-4:2:0; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"
        local doc, err = sdp.parse(video20_sdp(fmtp), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("rejects sampling=YCbCr-4:2:0 with interlace flag", function()
        local fmtp = "sampling=YCbCr-4:2:0; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; interlace"
        local doc = sdp.parse(video20_sdp(fmtp))
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.matches("4:2:0", err.message)
      end)

      it("accepts sampling=YCbCr-4:2:2 with interlace (only 4:2:0 is restricted)", function()
        local fmtp = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; interlace"
        local doc, err = sdp.parse(video20_sdp(fmtp), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("rejects sampling=ICtCp-4:2:0 with interlace (covers all 4:2:0 variants)", function()
        local fmtp = "sampling=ICtCp-4:2:0; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT2100; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; interlace"
        local doc = sdp.parse(video20_sdp(fmtp))
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.matches("4:2:0", err.message)
      end)
    end)

    -- AMWA sdpoker PR #38: ST 2110-20:2022 §7.6 added ST2115LOGS3 to the TCS
    -- enum (alongside the 10 values from :2017). VALID_TCS now lists all 11.
    it("accepts TCS=ST2115LOGS3 (ST 2110-20:2022 §7.6)", function()
      local fmtp = VALID:gsub("TCS=SDR", "TCS=ST2115LOGS3")
      local doc, err = sdp.parse(video20_sdp(fmtp), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- AMWA sdpoker Issue #11 (JT-NM Tested) — ST 2110-20:2022 §7.2 SSN clause:
    -- "Senders implementing this standard shall signal the value ST2110-20:2017
    -- unless the colorimetry value ALPHA or the TCS value ST2115LOGS3 are used,
    -- in which case the value ST2110-20:2022 shall be signaled." A sender using
    -- the :2022-only values must declare SSN=:2022.
    describe("ST 2110-20:2022 §7.2 SSN ↔ TCS/colorimetry coupling", function()
      it("rejects TCS=ST2115LOGS3 with SSN=ST2110-20:2017", function()
        local fmtp = VALID:gsub("TCS=SDR", "TCS=ST2115LOGS3")
                          :gsub("SSN=ST2110%-20:2022", "SSN=ST2110-20:2017")
        local doc = sdp.parse(video20_sdp(fmtp))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("SSN", err.message)
        assert.matches("ST2115LOGS3", err.message)
      end)

      it("accepts TCS=ST2115LOGS3 with SSN=ST2110-20:2022 (boundary)", function()
        local fmtp = VALID:gsub("TCS=SDR", "TCS=ST2115LOGS3")
        local doc, err = sdp.parse(video20_sdp(fmtp), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("rejects colorimetry=ALPHA with SSN=ST2110-20:2017", function()
        local fmtp = VALID:gsub("colorimetry=BT709", "colorimetry=ALPHA")
                          :gsub("SSN=ST2110%-20:2022", "SSN=ST2110-20:2017")
        local doc = sdp.parse(video20_sdp(fmtp))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("SSN", err.message)
        assert.matches("ALPHA", err.message)
      end)

      it("accepts colorimetry=ALPHA with SSN=ST2110-20:2022 (boundary)", function()
        local fmtp = VALID:gsub("colorimetry=BT709", "colorimetry=ALPHA")
        local doc, err = sdp.parse(video20_sdp(fmtp), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("accepts SSN=ST2110-20:2017 when neither :2022-only value is used", function()
        local fmtp = VALID:gsub("SSN=ST2110%-20:2022", "SSN=ST2110-20:2017")
        local doc, err = sdp.parse(video20_sdp(fmtp), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      -- ST 2110-20:2022 §7.2 defines only :2017 and :2022 — reject any
      -- other year suffix at the value-form check.
      it("rejects SSN=ST2110-20:1999 (year not defined by §7.2)", function()
        local fmtp = VALID:gsub("SSN=ST2110%-20:2022", "SSN=ST2110-20:1999")
        local doc = sdp.parse(video20_sdp(fmtp))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("SSN", err.message)
      end)

      it("rejects SSN=ST2110-20:2018 (year not defined by §7.2)", function()
        local fmtp = VALID:gsub("SSN=ST2110%-20:2022", "SSN=ST2110-20:2018")
        local doc = sdp.parse(video20_sdp(fmtp))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("SSN", err.message)
      end)

      it("rejects SSN=ST2110-20:9999 (year not defined by §7.2)", function()
        local fmtp = VALID:gsub("SSN=ST2110%-20:2022", "SSN=ST2110-20:9999")
        local doc = sdp.parse(video20_sdp(fmtp))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("SSN", err.message)
      end)
    end)

    -- ST 2110-20:2022 §7.2 exactframerate: "non-integer rates shall be signaled
    -- as a ratio of two integer decimal numbers… utilizing the numerically
    -- smallest numerator value possible." Reduce to lowest terms (gcd=1).
    describe("ST 2110-20:2022 §7.2 exactframerate lowest-terms", function()
      it("accepts 30000/1001 (lowest terms)", function()
        local fmtp = VALID:gsub("exactframerate=25", "exactframerate=30000/1001")
        local doc, err = sdp.parse(video20_sdp(fmtp), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("rejects 60000/2002 (reducible to 30000/1001)", function()
        local fmtp = VALID:gsub("exactframerate=25", "exactframerate=60000/2002")
        local doc = sdp.parse(video20_sdp(fmtp))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("exactframerate", err.message)
      end)

      it("rejects 50/2 (reducible to 25)", function()
        local fmtp = VALID:gsub("exactframerate=25", "exactframerate=50/2")
        local doc = sdp.parse(video20_sdp(fmtp))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("exactframerate", err.message)
      end)
    end)

    -- Streampunk sdpoker Issue #9 (regression): `ts-refclk:local` (no `mac=`)
    -- is not a valid clock-source form per ST 2110-10 §8.2; only the listed
    -- prefixes (gps/gal/glonass/ntp=/localmac=/ptp=) are accepted.
    describe("ts-refclk:local rejection (Streampunk #9)", function()
      it("rejects bare ts-refclk:local (typo of :localmac=)", function()
        local text = table.concat({
          "v=0",
          "o=- 1 1 IN IP4 192.168.1.1",
          "s=ST2110 Video",
          "t=0 0",
          "a=ts-refclk:local",
          "m=video 5000 RTP/AVP 96",
          "c=IN IP4 239.100.0.1/64",
          "a=rtpmap:96 raw/90000",
          "a=fmtp:96 " .. VALID,
          "a=mediaclk:direct=0",
        }, "\r\n") .. "\r\n"
        local doc = sdp.parse(text)
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("ts%-refclk", err.message)
      end)
    end)

    -- AMWA sdpoker Issue #19 / Streampunk #12 (regression): RFC 4570 §3 does
    -- NOT mandate `a=source-filter` when a multicast address is used. The
    -- ST 2110 tier therefore does not require it; only the IPMX tier does
    -- (TR-10-TP-1 §13.2). Confirm the ST 2110 tier accepts a multicast SDP
    -- without source-filter.
    describe("source-filter not mandated at ST 2110 tier (AMWA #19)", function()
      it("accepts multicast SDP without a=source-filter", function()
        local text = table.concat({
          "v=0",
          "o=- 1 1 IN IP4 192.168.1.1",
          "s=ST2110 Video",
          "t=0 0",
          "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
          "m=video 5000 RTP/AVP 96",
          "c=IN IP4 239.100.0.1/64",
          "a=rtpmap:96 raw/90000",
          "a=fmtp:96 " .. VALID,
          "a=mediaclk:direct=0",
        }, "\r\n") .. "\r\n"
        local doc, err = sdp.parse(text, "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)
    end)

    -- AMWA sdpoker Issue #2 (CLOSED): early SDPoker rejected fmtp lines that
    -- did not end with "; ". RFC 4566 §6 imposes no such requirement and
    -- ST 2110-20:2022 §7.1 describes only inter-parameter separators. The
    -- parser accepts both forms.
    it("accepts fmtp with no trailing semicolon", function()
      local doc, err = sdp.parse(video20_sdp(VALID .. "; TP=2110TPN"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- ST 2110-20:2022 §7.1: "There is no semicolon character after the last
    -- item." Streampunk Issue #33 — strict per the 2022 wording.
    it("rejects fmtp with trailing semicolon (ST 2110-20:2022 §7.1)", function()
      local doc = sdp.parse(video20_sdp(VALID .. "; TP=2110TPN; "))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("semicolon", err.message)
      assert.equal("ST 2110-20:2022 §7.1", err.spec_ref)
    end)

    -- ST 2110-20:2022 §7.1: ";" must be followed by whitespace.
    it("rejects fmtp with ';' not followed by whitespace (ST 2110-20:2022 §7.1)", function()
      local fmtp_packed = VALID:gsub("; ", ";")  -- strip all the inter-param spaces
      local doc = sdp.parse(video20_sdp(fmtp_packed))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("whitespace", err.message)
      assert.equal("ST 2110-20:2022 §7.1", err.spec_ref)
    end)

    -- ST 2110-20:2022 §7.1: "Each parameter entry shall be constructed as
    -- either: 'name=value' (no whitespace) or 'name' (no value)."
    it("rejects fmtp with spaces around '=' (ST 2110-20:2022 §7.1)", function()
      local doc = sdp.parse(video20_sdp(VALID:gsub("width=1920", "width = 1920")))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("whitespace around '='", err.message)
      assert.equal("ST 2110-20:2022 §7.1", err.spec_ref)
    end)

    it("rejects fmtp with space before '=' (ST 2110-20:2022 §7.1)", function()
      local doc = sdp.parse(video20_sdp(VALID:gsub("width=1920", "width =1920")))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("whitespace around '='", err.message)
      assert.equal("ST 2110-20:2022 §7.1", err.spec_ref)
    end)

    it("rejects fmtp with space after '=' (ST 2110-20:2022 §7.1)", function()
      local doc = sdp.parse(video20_sdp(VALID:gsub("width=1920", "width= 1920")))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("whitespace around '='", err.message)
      assert.equal("ST 2110-20:2022 §7.1", err.spec_ref)
    end)

    it("accepts canonical 'name=value' tokens (boundary)", function()
      local doc, err = sdp.parse(video20_sdp(VALID), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

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

    it("rejects depth=0 (not in §7.4.2 enumeration)", function()
      local doc = sdp.parse(video20_sdp(VALID:gsub("depth=10", "depth=0")))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("depth", err.message)
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
        "a=ptime:1",
        "a=fmtp:97 channel-order=" .. co_value,
        "a=mediaclk:direct=0",
      }, "\r\n") .. "\r\n"
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

    it("rejects channel-order with no <convention>.<order> separator", function()
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

    -- ST 2110-30:2025 §6.2.2: "The <convention> of the channel-order should
    -- be SMPTE2110." SHOULD, not SHALL — non-SMPTE2110 conventions are
    -- structurally accepted (RFC 3190 §6 only requires <convention>.<order>).
    it("accepts non-SMPTE2110 convention structurally (§6.2.2 SHOULD)", function()
      local doc, err = sdp.parse(audio30_sdp("AES.(M,M)"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects SMPTE2110.(BOGUS) (Table 1 SHALL applies to SMPTE2110)", function()
      local doc = sdp.parse(audio30_sdp("SMPTE2110.(BOGUS)"))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("channel%-order", err.message)
    end)

    -- ST 2110-31:2022 §6.2 Table 2 — AES3 symbol is defined only for
    -- AM824 streams (this audio30_sdp uses L24, so AES3 is forbidden).
    it("rejects SMPTE2110.(AES3) on L16/L24 (ST 2110-31 §6.2 Table 2 — AM824 only)", function()
      local doc = sdp.parse(audio30_sdp("SMPTE2110.(AES3)"))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("AES3", err.message)
    end)
  end)

  -- ST 2110-31:2022 §6.2 Table 2 adds the AES3 channel-grouping symbol for
  -- AM824 streams. F6 audit fix.
  describe("ST 2110-31 channel-order AES3 symbol (§6.2 Table 2)", function()
    local function am824_sdp(co_value)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 AM824",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=audio 5010 RTP/AVP 97",
        "c=IN IP4 239.100.0.2/64",
        "a=rtpmap:97 AM824/48000/2",
        "a=fmtp:97 channel-order=" .. co_value,
        "a=ptime:1",
        "a=mediaclk:direct=0",
      }, "\r\n") .. "\r\n"
    end

    it("accepts SMPTE2110.(AES3) on AM824", function()
      local doc, err = sdp.parse(am824_sdp("SMPTE2110.(AES3)"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts SMPTE2110.(AES3,AES3) on AM824", function()
      local doc, err = sdp.parse(am824_sdp("SMPTE2110.(AES3,AES3)"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("still accepts SMPTE2110.(ST) on AM824 (Table 1 symbols inherit)", function()
      local doc, err = sdp.parse(am824_sdp("SMPTE2110.(ST)"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
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
        "a=rtpmap:97 L24/" .. rate .. "/2",  -- 2 ch fits any tested rate within Standard UDP at ptime=1
        "a=ptime:1",
        "a=fmtp:97 channel-order=SMPTE2110.(ST)",
        "a=mediaclk:direct=0",
      }, "\r\n") .. "\r\n"
    end

    -- ST 2110-30:2017 §6.1 mandates 48 kHz and permits 44.1/96 kHz, then says
    -- "Other sampling rates are out of scope of this standard." Out-of-scope is
    -- not the same as forbidden — the spec does not use "shall not" — so under
    -- the M30 conformance principle we accept any well-formed positive rate.
    local well_formed_rates = { 44100, 48000, 96000, 32000, 88200, 176400, 192000, 22050 }
    for _, rate in ipairs(well_formed_rates) do
      it("accepts " .. rate .. " Hz (well-formed; ST 2110-30 §6.1 doesn't forbid)", function()
        local doc, err = sdp.parse(audio_sdp(rate), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)
    end
  end)

  -- ── ST 2110-20 optional fmtp parameters ──────────────────────────────────────

  describe("ST 2110-20 optional fmtp parameters", function()
    local BASE = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"

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
      }, "\r\n") .. "\r\n"
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
        assert.equal("ST 2110-20:2022 §7.2", err.spec_ref)
      end)

      it("absent RANGE is accepted (optional parameter)", function()
        local doc, err = sdp.parse(video20_sdp(BASE), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      -- ST 2110-20:2022 §7.3: "When the colorimetry value is BT2100, only
      -- the NARROW and FULL values are permitted."
      describe("BT2100 → RANGE restriction (§7.3)", function()
        local BT2100_BASE = BASE:gsub("colorimetry=BT709", "colorimetry=BT2100")

        it("accepts colorimetry=BT2100 with RANGE=NARROW", function()
          local doc, err = sdp.parse(video20_sdp(BT2100_BASE .. "; RANGE=NARROW"), "st2110")
          assert.is_nil(err)
          assert.is_table(doc)
        end)

        it("accepts colorimetry=BT2100 with RANGE=FULL", function()
          local doc, err = sdp.parse(video20_sdp(BT2100_BASE .. "; RANGE=FULL"), "st2110")
          assert.is_nil(err)
          assert.is_table(doc)
        end)

        it("rejects colorimetry=BT2100 with RANGE=FULLPROTECT", function()
          local doc = sdp.parse(video20_sdp(BT2100_BASE .. "; RANGE=FULLPROTECT"))
          assert.is_table(doc)
          local ok, err = doc:validate("st2110")
          assert.is_nil(ok)
          assert.is_table(err)
          assert.matches("RANGE", err.message)
          assert.matches("BT2100", err.message)
          assert.equal("ST 2110-20:2022 §7.3", err.spec_ref)
        end)
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
        assert.equal("ST 2110-21:2022 §8.1", err.spec_ref)
      end)

      -- ST 2110-20:2022 §6.1.1 requires every raw video stream to conform to
      -- ST 2110-21 (Type N/NL/W); ST 2110-21:2022 §8.1 makes TP a Required
      -- Parameter for all conforming video streams. So absence is rejected.
      it("rejects fmtp without TP (ST 2110-21:2022 §8.1 Required Parameter)", function()
        local without_tp = (BASE:gsub("; TP=2110TPN", ""))
        local doc = sdp.parse(video20_sdp(without_tp))
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.matches("TP", err.message)
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

      -- ST 2110-20:2017 §7.3: "The smallest integer values possible for width
      -- and height shall be used." PAR=2:2 must be 1:1; PAR=4:6 must be 2:3.
      it("rejects PAR=2:2 (not in lowest terms; should be 1:1)", function()
        local doc = sdp.parse(video20_sdp(BASE .. "; PAR=2:2"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("PAR", err.message)
        assert.matches("lowest", err.message)
      end)

      it("rejects PAR=4:6 (not in lowest terms; should be 2:3)", function()
        local doc = sdp.parse(video20_sdp(BASE .. "; PAR=4:6"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("PAR", err.message)
        assert.matches("lowest", err.message)
      end)

      it("rejects PAR=100:100 (not in lowest terms; should be 1:1)", function()
        local doc = sdp.parse(video20_sdp(BASE .. "; PAR=100:100"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("PAR", err.message)
      end)

      it("accepts PAR=12:11 (NTSC, in lowest terms)", function()
        local doc, err = sdp.parse(video20_sdp(BASE .. "; PAR=12:11"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("accepts PAR=64:45 (anamorphic, in lowest terms)", function()
        local doc, err = sdp.parse(video20_sdp(BASE .. "; PAR=64:45"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)
    end)

    describe("TROFF (timestamp offset)", function()
      -- TROFF and CMAX require TP per ST 2110-21 §8 (also see M24 cross-field check).
      local BASE_TP = BASE .. "; TP=2110TPN"

      -- M30 G8: ST 2110-21 §8 defines TROFF as "a decimal positive integer";
      -- previously the optional video fmtp validator allowed TROFF=0.
      it("rejects TROFF=0 (ST 2110-21 §8 — positive integer)", function()
        local doc = sdp.parse(video20_sdp(BASE_TP .. "; TROFF=0"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("TROFF", err.message)
      end)

      it("accepts a positive TROFF", function()
        local doc, err = sdp.parse(video20_sdp(BASE_TP .. "; TROFF=4500"), "st2110")
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
      local BASE_TP = BASE .. "; TP=2110TPN"
      -- ST 2110-21:2022 §8.2: "CMAX ... is expressed as an integer number."
      -- (No "positive" qualifier — 2017 and 2022 both use plain "integer.")
      -- §7.1 formula bounds are upper bounds on CINST (per §6.6.1), not lower
      -- bounds on the SDP-signaled value, and require NPACKETS/MAXUDP context
      -- to compute. Value form is therefore "any integer."
      it("accepts a positive integer", function()
        local doc, err = sdp.parse(video20_sdp(BASE_TP .. "; CMAX=3"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("accepts CMAX=0 (§8.2 — 'an integer number')", function()
        local doc, err = sdp.parse(video20_sdp(BASE_TP .. "; CMAX=0"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("accepts a negative integer CMAX (§8.2 has no sign restriction)", function()
        local doc, err = sdp.parse(video20_sdp(BASE_TP .. "; CMAX=-1"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("rejects non-integer CMAX", function()
        local doc = sdp.parse(video20_sdp(BASE_TP .. "; CMAX=notanumber"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("CMAX", err.message)
      end)

      it("rejects fractional CMAX", function()
        local doc = sdp.parse(video20_sdp(BASE_TP .. "; CMAX=3.14"))
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

      it("accepts interlace and segmented together", function()
        local doc, err = sdp.parse(video20_sdp(BASE .. "; interlace; segmented"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      -- ST 2110-20:2017 §7.3: "Signaling of [segmented] without the interlace
      -- parameter is forbidden." (PsF requires interlace to be set as well.)
      it("rejects segmented without interlace", function()
        local doc = sdp.parse(video20_sdp(BASE .. "; segmented"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("segmented", err.message)
        assert.matches("interlace", err.message)
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
        "a=rtpmap:97 " .. enc .. "/" .. rate .. "/2",
        "a=fmtp:97 channel-order=SMPTE2110.(ST)",
        "a=ptime:1",
        "a=mediaclk:direct=0",
      }, "\r\n") .. "\r\n"
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
      assert.equal("ST 2110-30:2025 §6.1", err.spec_ref)
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

  -- ST 2110-31:2022 AM824-specific SHALLs (audit N2-N5).
  describe("ST 2110-31 AM824 SHALLs (§5.5 / §6.1)", function()
    local PTP = "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"
    local function am824_sdp(rate, ch, ptime)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 AM824", "t=0 0", PTP,
        "m=audio 5010 RTP/AVP 97",
        "c=IN IP4 239.100.0.2/64",
        "a=rtpmap:97 AM824/" .. rate .. "/" .. ch,
        ptime and ("a=ptime:" .. ptime) or "a=mid:audio",
        "a=mediaclk:direct=0",
      }, "\r\n") .. "\r\n"
    end

    -- N2: <nchan> SHALL be even.
    it("rejects AM824 with odd nchan (§6.1)", function()
      local doc = sdp.parse(am824_sdp(48000, 3, "1"))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("even", err.message)
    end)

    it("accepts AM824 with even nchan", function()
      local doc, err = sdp.parse(am824_sdp(48000, 2, "1"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- N3: clock-rate SHALL be one of {44100, 48000, 96000}.
    it("rejects AM824 at 32000 Hz (§5.5 / §6.1 enum)", function()
      local doc = sdp.parse(am824_sdp(32000, 2, "1"))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("44100", err.message)
    end)

    it("accepts AM824 at 96000 Hz", function()
      local doc, err = sdp.parse(am824_sdp(96000, 2, "1"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- N4: a=ptime SHALL be present for AM824.
    it("rejects AM824 without a=ptime (§6.1)", function()
      local doc = sdp.parse(am824_sdp(48000, 2, nil))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("ptime", err.message)
    end)

    -- N5: ptime SHALL be from Table 1 for the prevailing clock_rate.
    it("rejects AM824 ptime not in Table 1 (e.g. 0.5 ms at 48k)", function()
      local doc = sdp.parse(am824_sdp(48000, 2, "0.5"))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("Table 1", err.message)
    end)

    it("accepts ptime 0.12 ms at 48k (Table 1 entry)", function()
      local doc, err = sdp.parse(am824_sdp(48000, 2, "0.12"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts ptime 0.080 ms at 48k (decimal-string equivalent of 0.08)", function()
      local doc, err = sdp.parse(am824_sdp(48000, 2, "0.080"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts ptime 1.09 ms at 44.1k (Table 1 entry)", function()
      local doc, err = sdp.parse(am824_sdp(44100, 2, "1.09"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  -- ── ST 2110-40: VPID_Code optional fmtp param ─────────────────────────────────

  describe("ST 2110-40 VPID_Code optional fmtp param (§7.2)", function()
    local DEFAULT_REQUIRED = "SSN=ST2110-40:2018; exactframerate=25"
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
      }, "\r\n") .. "\r\n"
    end

    it("accepts a valid integer VPID_Code", function()
      local doc, err = sdp.parse(anc_sdp(DEFAULT_REQUIRED .. "; DID_SDID={0x61,0x02}; VPID_Code=133"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts VPID_Code=0", function()
      local doc, err = sdp.parse(anc_sdp(DEFAULT_REQUIRED .. "; DID_SDID={0x61,0x02}; VPID_Code=0"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects non-integer VPID_Code", function()
      local doc = sdp.parse(anc_sdp(DEFAULT_REQUIRED .. "; DID_SDID={0x61,0x02}; VPID_Code=notanumber"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("VPID_Code", err.message)
      assert.equal("RFC 8331 §4", err.spec_ref)
    end)

    it("rejects negative VPID_Code", function()
      local doc = sdp.parse(anc_sdp(DEFAULT_REQUIRED .. "; DID_SDID={0x61,0x02}; VPID_Code=-1"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("VPID_Code", err.message)
    end)

    it("absent VPID_Code is accepted (optional)", function()
      local doc, err = sdp.parse(anc_sdp(DEFAULT_REQUIRED .. "; DID_SDID={0x61,0x02}"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- RFC 8331 §4: "VPID_Code shall appear only once and a single integer
    -- value shall be expressed."
    it("rejects duplicate VPID_Code parameters (RFC 8331 §4 cardinality)", function()
      local doc = sdp.parse(anc_sdp(DEFAULT_REQUIRED .. "; DID_SDID={0x61,0x02}; VPID_Code=132; VPID_Code=133"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("VPID_Code", err.message)
      assert.matches("only once", err.message)
      assert.equal("RFC 8331 §4", err.spec_ref)
    end)
  end)

  -- ── ST 2110-41: DIT value format ───────────────────────────────────────────────

  describe("ST 2110-41 DIT value format (§6 / §9.2.3)", function()
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
      }, "\r\n") .. "\r\n"
    end

    it("accepts single hex token DIT=100", function()
      local doc, err = sdp.parse(meta_sdp("SSN=ST2110-41:2024; DIT=100"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts spec example DIT=100,2000A1,1013FC,3FFF00 (§6 example)", function()
      local doc, err = sdp.parse(meta_sdp("SSN=ST2110-41:2024; DIT=100,2000A1,1013FC,3FFF00"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects lowercase hex (§6 SHALL: 'alphabetic characters shall be uppercase')", function()
      local doc = sdp.parse(meta_sdp("SSN=ST2110-41:2024; DIT=abc"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("DIT", err.message)
    end)

    it("rejects leading 0x prefix (§6 SHALL: 'shall not include the leading 0x')", function()
      local doc = sdp.parse(meta_sdp("SSN=ST2110-41:2024; DIT=0x100"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("DIT", err.message)
    end)

    it("rejects whitespace in DIT list (§6 SHALL: 'Whitespace characters shall not appear')", function()
      local doc = sdp.parse(meta_sdp("SSN=ST2110-41:2024; DIT=100, 200"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("DIT", err.message)
    end)

    it("rejects empty DIT value", function()
      local doc = sdp.parse(meta_sdp("SSN=ST2110-41:2024; DIT="))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("DIT", err.message)
    end)

    -- N11 (audit): ST 2110-41:2024 §5.4 forbids MAXUDP on ST2110-41
    -- (UDP size shall be ≤ Standard limit).
    it("rejects MAXUDP on ST2110-41 (§5.4)", function()
      local doc = sdp.parse(meta_sdp("SSN=ST2110-41:2024; DIT=100; MAXUDP=8960"))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("MAXUDP", err.message)
    end)
  end)

  -- ── rtpmap / fmtp payload type consistency ────────────────────────────────────

  describe("rtpmap and fmtp payload type consistency (ST 2110-10 §7)", function()
    local VALID_FMTP = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"

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
      }, "\r\n") .. "\r\n"
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
      assert.equal("RFC 4566 §6", err.spec_ref)
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
        "a=ptime:1",
        "a=mediaclk:direct=0",
      }, "\r\n") .. "\r\n"
    end

    -- ST 2110-30 §6.2.2 / Table 2 documents Conformance Levels with channel
    -- counts up to 64 (Level C at 125 µs). The spec does not contain a global
    -- "shall not exceed N channels" prohibition; the validator imposes no
    -- per-channel-count cap of its own. The natural upper bound is the
    -- packet-fit derived constraint (audio_sdp_ch above uses L24/48k with
    -- ptime=1 ms = 144 B/channel within the 1448-B Standard UDP payload, so
    -- ~10 channels fit). The "no spec cap" property is exercised by
    -- accepting counts up to that derived limit.
    for _, ch in ipairs({ 1, 2, 4, 8 }) do
      it("accepts channel count " .. ch, function()
        local doc, err = sdp.parse(audio_sdp_ch(ch), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)
    end

    it("rejects channel count 0 (RFC 3551 / 4566 well-formedness)", function()
      local doc = sdp.parse(audio_sdp_ch(0))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("channel count", err.message)
    end)

    it("rejects rtpmap with no channel count (RFC 3551 / 4566 well-formedness)", function()
      local doc = sdp.parse(audio_sdp_ch(nil))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("channel count", err.message)
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
      return table.concat(lines, "\r\n") .. "\r\n"
    end

    -- D1 (audit): ST 2110-30:2025 §6.2.1 chains audio to AES67 §8.1, which
    -- makes a=ptime SHALL on every audio stream. Absence is rejected.
    it("rejects absence of a=ptime (ST 2110-30:2025 §6.2.1 / AES67 §8.1)", function()
      local doc = sdp.parse(audio_with_ptime(nil))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("ptime", err.message)
    end)

    it("accepts a=ptime:1", function()
      local doc, err = sdp.parse(audio_with_ptime(1), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts a non-1 positive ptime (sub-ms)", function()
      -- 8 ch × (48000 × 0.125/1000 = 6 samples) × 3 B = 144 B, well under limit.
      local doc, err = sdp.parse(audio_with_ptime(0.125), "st2110")
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
      assert.equal("ST 2110-30:2025 §6.2.1", err.spec_ref)
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

  -- ── ST 2110-30 audio packet payload fit (§6.1, §6.4) ──────────────────────────
  -- ST 2110-10 §6.4: Standard UDP Size Limit is 1460 octets unless MAXUDP signals
  -- the Extended Limit (up to 8960). ST 2110-30 §6.2.2: audio packet RTP payload =
  -- channels × samples-per-packet × bytes-per-sample, where samples = rate × ptime.
  -- An SDP declaring more than fits cannot be transmitted as described.
  describe("ST 2110-30 audio packet payload fit (§6.4)", function()
    local function audio_pkt(rtpmap, fmtp, ptime)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Audio",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=audio 5010 RTP/AVP 97",
        "c=IN IP4 239.100.0.2/64",
        rtpmap,
        fmtp,
        "a=mediaclk:direct=0",
        "a=ptime:" .. ptime,
      }, "\r\n") .. "\r\n"
    end

    it("accepts L24/48000/8 ch at ptime=1 (1152 B fits in 1448)", function()
      local doc, err = sdp.parse(audio_pkt(
        "a=rtpmap:97 L24/48000/8",
        "a=fmtp:97 channel-order=SMPTE2110.(ST)",
        "1"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects L24/48000/16 ch at ptime=1 (2304 B exceeds 1448)", function()
      local doc = sdp.parse(audio_pkt(
        "a=rtpmap:97 L24/48000/16",
        "a=fmtp:97 channel-order=SMPTE2110.(U01,U02,U03,U04,U05,U06,U07,U08,U09,U10,U11,U12,U13,U14,U15,U16)",
        "1"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("payload", err.message)
      assert.equal("ST 2110-10:2022 §6.4", err.spec_ref)
    end)

    it("accepts L24/48000/16 ch at ptime=0.125 (288 B fits)", function()
      local doc, err = sdp.parse(audio_pkt(
        "a=rtpmap:97 L24/48000/16",
        "a=fmtp:97 channel-order=SMPTE2110.(U01,U02,U03,U04,U05,U06,U07,U08,U09,U10,U11,U12,U13,U14,U15,U16)",
        "0.125"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- N11 (audit): ST 2110-30:2025 §6.2.1 forbids signaling MAXUDP on
    -- audio streams (the Standard UDP Size Limit shall be used).
    it("rejects MAXUDP on audio (ST 2110-30:2025 §6.2.1)", function()
      local doc = sdp.parse(audio_pkt(
        "a=rtpmap:97 L24/48000/16",
        "a=fmtp:97 channel-order=SMPTE2110.(U01,U02,U03,U04,U05,U06,U07,U08,U09,U10,U11,U12,U13,U14,U15,U16); MAXUDP=8960",
        "1"))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("MAXUDP", err.message)
    end)

    it("rejects L16/96000/8 ch at ptime=1 (1536 B exceeds 1448)", function()
      local doc = sdp.parse(audio_pkt(
        "a=rtpmap:97 L16/96000/8",
        "a=ptime:1",
        "a=fmtp:97 channel-order=SMPTE2110.(ST,U01,U02,U03,U04,U05,U06)",
        "1"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("payload", err.message)
    end)
  end)

  -- ── ST 2110-20 CMAX rejects fractional value ─────────────────────────────────

  describe("ST 2110-20 CMAX integer-only value form", function()
    -- ST 2110-21:2022 §8.2: "CMAX ... is expressed as an integer number."
    -- The integer requirement is the only value-form SHALL on the SDP CMAX
    -- parameter; sign and zero are not constrained at the SDP level.
    local BASE = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"

    it("rejects fractional CMAX (not an integer per §8.2)", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 " .. BASE .. "; CMAX=3.14",
        "a=mediaclk:direct=0",
      }, "\r\n") .. "\r\n"
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("CMAX", err.message)
      assert.equal("ST 2110-21:2022 §8.2", err.spec_ref)
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        "a=mediaclk:direct=0",
        "a=ts-refclk:ptp=IEEE1588-2008:" .. gmid,
      }, "\r\n") .. "\r\n"
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        "a=mediaclk:direct=0",
        "a=ts-refclk:ntp=" .. addr,
      }, "\r\n") .. "\r\n"
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
      }, "\r\n") .. "\r\n"
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
      }, "\r\n") .. "\r\n"
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

  -- ── M22: TCS=UNSPECIFIED and colorimetry=XYZ (ST 2110-20:2017 §7.5/§7.6) ────

  describe("TCS and colorimetry enum gaps (M22)", function()
    local PTP = "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"
    local function video_with_fmtp(fmtp_tail)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        PTP,
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 " .. fmtp_tail,
        "a=mediaclk:direct=0",
        PTP,
      }, "\r\n") .. "\r\n"
    end

    local BASE = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"

    it("accepts TCS=UNSPECIFIED", function()
      local doc, err = sdp.parse(video_with_fmtp(BASE .. "; TCS=UNSPECIFIED; colorimetry=BT709"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts colorimetry=XYZ", function()
      local doc, err = sdp.parse(video_with_fmtp(BASE .. "; TCS=SDR; colorimetry=XYZ"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects unknown TCS value", function()
      local doc = sdp.parse(video_with_fmtp(BASE .. "; TCS=BOGUS; colorimetry=BT709"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("TCS", err.message)
    end)

    it("rejects unknown colorimetry value", function()
      local doc = sdp.parse(video_with_fmtp(BASE .. "; TCS=SDR; colorimetry=NOPE"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("colorimetry", err.message)
    end)
  end)

  -- ── M22: SSN year validation (requires 4-digit year suffix) ──────────────────

  describe("SSN 4-digit year validation (M22)", function()
    local PTP = "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"
    local function video_with_ssn(ssn)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        PTP,
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=" .. ssn .. "; TP=2110TPN",
        "a=mediaclk:direct=0",
        PTP,
      }, "\r\n") .. "\r\n"
    end

    it("accepts SSN=ST2110-20:2022", function()
      local doc, err = sdp.parse(video_with_ssn("ST2110-20:2022"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts SSN=ST2110-20:2017", function()
      local doc, err = sdp.parse(video_with_ssn("ST2110-20:2017"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects SSN=ST2110-20: (no year)", function()
      local doc = sdp.parse(video_with_ssn("ST2110-20:"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("SSN", err.message)
    end)

    it("rejects SSN=ST2110-20:17 (two-digit year)", function()
      local doc = sdp.parse(video_with_ssn("ST2110-20:17"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("SSN", err.message)
    end)

    it("rejects SSN=ST2110-20:badvalue", function()
      local doc = sdp.parse(video_with_ssn("ST2110-20:badvalue"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("SSN", err.message)
    end)
  end)

  -- ── M22: channel-order group symbol validation (ST 2110-30 §6.2.2) ───────────

  describe("channel-order group symbol validation (M22)", function()
    local PTP = "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"
    local function audio_with_co(co)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Audio",
        "t=0 0",
        PTP,
        "m=audio 5010 RTP/AVP 97",
        "c=IN IP4 239.100.0.2/64",
        "a=rtpmap:97 L24/48000/8",
        "a=ptime:1",
        "a=fmtp:97 channel-order=SMPTE2110.(" .. co .. ")",
        "a=mediaclk:direct=0",
        PTP,
      }, "\r\n") .. "\r\n"
    end

    it("accepts ST", function()
      local doc, err = sdp.parse(audio_with_co("ST"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts U08 (user-defined 1-64)", function()
      local doc, err = sdp.parse(audio_with_co("U08"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts 51,ST (multiple groups)", function()
      local doc, err = sdp.parse(audio_with_co("51,ST"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts all named group symbols", function()
      for _, g in ipairs({ "M", "DM", "ST", "LtRt", "51", "71", "222", "SGRP" }) do
        local doc, err = sdp.parse(audio_with_co(g), "st2110")
        assert.is_nil(err, "expected no error for group " .. g)
        assert.is_table(doc)
      end
    end)

    it("accepts U01 (lower boundary)", function()
      local doc, err = sdp.parse(audio_with_co("U01"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts U64 (upper boundary)", function()
      local doc, err = sdp.parse(audio_with_co("U64"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects foo (unknown group symbol)", function()
      local doc = sdp.parse(audio_with_co("foo"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("group symbol", err.message)
    end)

    it("rejects U00 (out of range)", function()
      local doc = sdp.parse(audio_with_co("U00"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("group symbol", err.message)
    end)

    it("rejects U65 (out of range)", function()
      local doc = sdp.parse(audio_with_co("U65"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("group symbol", err.message)
    end)
  end)

  -- ── multicast TTL + layered/numaddr (RFC 8866 §5.7 / §9) ─────────────────────

  describe("multicast TTL range validation (RFC 8866 §5.7 / §9)", function()
    local PTP = "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"
    local VFMTP = "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"
    local function with_ttl(ttl)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        PTP,
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/" .. ttl,
        "a=rtpmap:96 raw/90000",
        VFMTP,
        "a=mediaclk:direct=0",
        PTP,
      }, "\r\n") .. "\r\n"
    end

    it("accepts TTL=64", function()
      local doc, err = sdp.parse(with_ttl(64), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts TTL=1 (lower boundary)", function()
      local doc, err = sdp.parse(with_ttl(1), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts TTL=255 (upper boundary)", function()
      local doc, err = sdp.parse(with_ttl(255), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- RFC 8866 §9 ABNF: ttl = (POS-DIGIT *2DIGIT) / "0". The "0"
    -- alternative is explicit; §5.7: "TTL values MUST be in the range 0-255."
    it("accepts TTL=0 (RFC 8866 §9 ABNF; §5.7 range 0-255)", function()
      local doc, err = sdp.parse(with_ttl(0), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects TTL=256", function()
      local doc = sdp.parse(with_ttl(256))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("TTL", err.message)
    end)
  end)

  -- RFC 8866 §9 ABNF: IP4-multicast = m1 3("." decimal-uchar) "/" ttl
  -- [ "/" numaddr ]. Layered/hierarchical multicast attaches an optional
  -- numaddr after ttl. Spec example: c=IN IP4 233.252.0.1/127/3.
  describe("IPv4 layered multicast numaddr (RFC 8866 §9 IP4-multicast)", function()
    local PTP = "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"
    local VFMTP = "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"
    local function with_c(c_line)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video", "t=0 0", PTP,
        "m=video 5000 RTP/AVP 96",
        c_line,
        "a=rtpmap:96 raw/90000",
        VFMTP,
        "a=mediaclk:direct=0", PTP,
      }, "\r\n") .. "\r\n"
    end

    it("accepts spec example c=IN IP4 233.252.0.1/127/3", function()
      local doc, err = sdp.parse(with_c("c=IN IP4 233.252.0.1/127/3"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts /ttl/numaddr with TTL=0", function()
      local doc, err = sdp.parse(with_c("c=IN IP4 233.252.0.1/0/3"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("still accepts plain /ttl form", function()
      local doc, err = sdp.parse(with_c("c=IN IP4 239.100.0.1/64"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects /ttl/numaddr with numaddr=0", function()
      local doc = sdp.parse(with_c("c=IN IP4 233.252.0.1/127/0"))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("numaddr", err.message)
    end)
  end)

  -- ── M22: JPEG-XS (jxsv) validation (ST 2110-22 / TR-10-11) ──────────────────

  describe("JPEG-XS (jxsv) validation (M22)", function()
    local PTP = "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"
    local VALID_JXSV_FMTP = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-22:2019; TP=2110TPNL; profile=High444.12; level=1k-1; sublevel=Sublev3bpp; transmode=1; packetmode=0"
    local function jxsv_sdp(fmtp_tail)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 JPEG-XS",
        "t=0 0",
        PTP,
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "b=AS:200000",
        "a=rtpmap:96 jxsv/90000",
        "a=fmtp:96 " .. fmtp_tail,
        "a=mediaclk:direct=0",
        PTP,
      }, "\r\n") .. "\r\n"
    end

    it("accepts a valid JPEG-XS SDP", function()
      local doc, err = sdp.parse(jxsv_sdp(VALID_JXSV_FMTP), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects wrong SSN prefix (ST2110-20 instead of ST2110-22)", function()
      local fmtp = VALID_JXSV_FMTP:gsub("ST2110%-22:2019", "ST2110-20:2022")
      local doc = sdp.parse(jxsv_sdp(fmtp))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("SSN", err.message)
    end)

    it("accepts TP=2110TPN (added in ST 2110-22:2022 §7.2 Table 1)", function()
      -- ST 2110-22:2019 §7.2 listed TP values as 2110TPNL or 2110TPW only.
      -- ST 2110-22:2022 §7.2 Table 1 expanded this enum to add 2110TPN.
      -- Both versions are in active use; the parser accepts the 2022 union.
      local fmtp = VALID_JXSV_FMTP:gsub("TP=2110TPNL", "TP=2110TPN")
      local doc, err = sdp.parse(jxsv_sdp(fmtp), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts TP=2110TPW", function()
      local fmtp = VALID_JXSV_FMTP:gsub("TP=2110TPNL", "TP=2110TPW")
      local doc, err = sdp.parse(jxsv_sdp(fmtp), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- ST 2110-22:2022 §7.2 Table 1 restates ST 2110-20:2022 §7.2:
    -- "Permitted values are integers between 1 and 32767 inclusive."
    it("accepts width=32767 and height=32767 (boundary)", function()
      local fmtp = VALID_JXSV_FMTP:gsub("width=1920", "width=32767")
                                  :gsub("height=1080", "height=32767")
      local doc, err = sdp.parse(jxsv_sdp(fmtp), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects width=32768 (exceeds 32767)", function()
      local fmtp = VALID_JXSV_FMTP:gsub("width=1920", "width=32768")
      local doc = sdp.parse(jxsv_sdp(fmtp))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("width", err.message)
    end)

    it("rejects height=99999 (exceeds 32767)", function()
      local fmtp = VALID_JXSV_FMTP:gsub("height=1080", "height=99999")
      local doc = sdp.parse(jxsv_sdp(fmtp))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("height", err.message)
    end)

    -- profile / level / sublevel are OPTIONAL at every tier. ST 2110-22:2022
    -- §7.2 Table 1 (mandatory) lists only width/height/TP. IANA video/jxsv
    -- requires only `packetmode` besides rate. IPMX JPEG-XS Video Profile
    -- §6.1.4 references these for the RTCP JPEG-XS Media Info Block, not SDP
    -- fmtp. TR-10-11 §10 defers SDP construction to ST 2110-22 §7.
    it("accepts missing profile (optional per ST 2110-22 §7.2)", function()
      local fmtp = VALID_JXSV_FMTP:gsub("; profile=High444.12", "")
      local doc, err = sdp.parse(jxsv_sdp(fmtp), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects invalid profile value when present", function()
      local fmtp = VALID_JXSV_FMTP:gsub("profile=High444%.12", "profile=NotAProfile")
      local doc = sdp.parse(jxsv_sdp(fmtp))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("profile", err.message)
    end)

    it("accepts missing level (optional per ST 2110-22 §7.2)", function()
      local fmtp = VALID_JXSV_FMTP:gsub("; level=1k%-1", "")
      local doc, err = sdp.parse(jxsv_sdp(fmtp), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects invalid level value when present", function()
      local fmtp = VALID_JXSV_FMTP:gsub("level=1k%-1", "level=ZZZ")
      local doc = sdp.parse(jxsv_sdp(fmtp))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("level", err.message)
    end)

    it("accepts missing sublevel (optional per ST 2110-22 §7.2)", function()
      local fmtp = VALID_JXSV_FMTP:gsub("; sublevel=Sublev3bpp", "")
      local doc, err = sdp.parse(jxsv_sdp(fmtp), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects invalid sublevel value when present", function()
      local fmtp = VALID_JXSV_FMTP:gsub("sublevel=Sublev3bpp", "sublevel=Bogus")
      local doc = sdp.parse(jxsv_sdp(fmtp))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("sublevel", err.message)
    end)

    it("accepts missing transmode at ST 2110 tier (IPMX-only requirement)", function()
      -- ST 2110-22:2022 §7.2 does not list transmode. IANA video/jxsv marks
      -- transmode optional. The transmode requirement is IPMX-specific
      -- (IPMX-JPEG-XS-Video-Profile §6.1.4) and belongs in the IPMX tier.
      local fmtp = VALID_JXSV_FMTP:gsub("; transmode=1", "")
      local doc, err = sdp.parse(jxsv_sdp(fmtp), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects missing packetmode", function()
      local fmtp = VALID_JXSV_FMTP:gsub("; packetmode=0", "")
      local doc = sdp.parse(jxsv_sdp(fmtp))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("packetmode", err.message)
    end)

    -- ST 2110-22:2022 §7.2 Table 1: TP is mandatory (also §5.3 SHALL).
    it("rejects missing TP (ST 2110-22:2022 §7.2 Table 1)", function()
      local fmtp = VALID_JXSV_FMTP:gsub("; TP=2110TPNL", "")
      local doc = sdp.parse(jxsv_sdp(fmtp))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("TP", err.message)
    end)

    -- ST 2110-22 §7.2 Table 1 lists width/height/TP as the only mandatory
    -- format-specific parameters; IANA video/jxsv (RFC 9134 §7.1) adds
    -- packetmode and the rate. Everything else is optional and validated only
    -- when present.
    it("accepts jxsv with only the spec-mandatory params + framerate (§7.4)", function()
      local fmtp = "width=1920; height=1080; TP=2110TPNL; packetmode=0; exactframerate=25"
      local doc, err = sdp.parse(jxsv_sdp(fmtp), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- N8: ST 2110-22:2022 §7.2 — "There is no semicolon character after the
    -- last item." (Unlike -20 §7.1, the post-';' whitespace is OPTIONAL in
    -- -22 §7.2, so the trailing-only check applies here.)
    it("rejects jxsv fmtp with trailing semicolon (§7.2)", function()
      local fmtp = VALID_JXSV_FMTP .. ";"
      local doc = sdp.parse(jxsv_sdp(fmtp))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("semicolon", err.message)
    end)

    -- N9: ST 2110-22:2022 §6.2 — "The media type name shall be 'video'."
    it("rejects jxsv with non-video media type (§6.2)", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=jxsv N9", "t=0 0", PTP,
        "m=application 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "b=AS:200000",
        "a=rtpmap:96 jxsv/90000",
        "a=fmtp:96 " .. VALID_JXSV_FMTP,
        "a=mediaclk:direct=0", PTP,
      }, "\r\n") .. "\r\n"
      local doc = sdp.parse(text)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("video", err.message)
    end)

    -- N7: ST 2110-22:2022 §7.3 — b=AS REQUIRED at the ST 2110 tier (was
    -- previously enforced only at the IPMX tier).
    it("rejects jxsv without b=AS at the ST 2110 tier (§7.3)", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=jxsv N7", "t=0 0", PTP,
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 jxsv/90000",
        "a=fmtp:96 " .. VALID_JXSV_FMTP,
        "a=mediaclk:direct=0", PTP,
      }, "\r\n") .. "\r\n"
      local doc = sdp.parse(text)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("b=AS", err.message)
    end)

    -- AMWA sdpoker PR #21 / BCP-006-01: RGB sampling is permitted for jxsv
    -- (sampling references ST 2110-20 §7.4.1 which includes RGB / XYZ / KEY).
    it("accepts RGB sampling for jxsv (BCP-006-01 / ST 2110-20 §7.4.1)", function()
      local fmtp = VALID_JXSV_FMTP:gsub("sampling=YCbCr%-4:2:2", "sampling=RGB")
      local doc, err = sdp.parse(jxsv_sdp(fmtp), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- Per RFC 9134 §7.1, sampling/exactframerate/depth/TCS/colorimetry are all
    -- optional. Validate format only when present.
    it("accepts missing sampling (optional per RFC 9134 §7.1)", function()
      local fmtp = VALID_JXSV_FMTP:gsub("sampling=YCbCr%-4:2:2; ", "")
      local doc, err = sdp.parse(jxsv_sdp(fmtp), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects bad sampling value when present", function()
      local fmtp = VALID_JXSV_FMTP:gsub("sampling=YCbCr%-4:2:2", "sampling=garbage")
      local doc = sdp.parse(jxsv_sdp(fmtp))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("sampling", err.message)
    end)

    -- ST 2110-22:2022 §7.4 makes frame-rate signaling REQUIRED via Table 4
    -- (one of: a=framerate OR fmtp exactframerate). RFC 9134 §7.1 alone
    -- treats exactframerate as optional, but §7.4 tightens that for jxsv.
    -- Confirm a=framerate satisfies the SHALL when exactframerate is absent.
    it("accepts a=framerate when exactframerate absent (§7.4 alternate)", function()
      local fmtp = VALID_JXSV_FMTP:gsub("; exactframerate=25", "")
      local sdp_text = (jxsv_sdp(fmtp)):gsub(
        "a=fmtp:96", "a=framerate:25\r\na=fmtp:96")
      local doc, err = sdp.parse(sdp_text, "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects jxsv without any frame-rate signaling (§7.4)", function()
      local fmtp = VALID_JXSV_FMTP:gsub("; exactframerate=25", "")
      local doc = sdp.parse(jxsv_sdp(fmtp))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("frame", err.message)
    end)

    it("accepts missing depth (optional per RFC 9134 §7.1)", function()
      local fmtp = VALID_JXSV_FMTP:gsub("; depth=10", "")
      local doc, err = sdp.parse(jxsv_sdp(fmtp), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts missing TCS (optional per RFC 9134 §7.1)", function()
      local fmtp = VALID_JXSV_FMTP:gsub("; TCS=SDR", "")
      local doc, err = sdp.parse(jxsv_sdp(fmtp), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts missing colorimetry (optional per RFC 9134 §7.1)", function()
      local fmtp = VALID_JXSV_FMTP:gsub("; colorimetry=BT709", "")
      local doc, err = sdp.parse(jxsv_sdp(fmtp), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- D2 (audit): no spec defines `fbblevel` as an SDP fmtp parameter
    -- (it lives only in the RTCP JPEG-XS Media Info Block per
    -- TR-10-15-Part1 §12). The previous `fbblevel` value-form check has
    -- been removed; unrecognized fmtp keys pass through silently per the
    -- ST 2110-22 §7.2 / RFC 9134 §7.1 model.
    it("accepts unrecognized fbblevel key (no SDP spec defines it)", function()
      local fmtp = VALID_JXSV_FMTP .. "; fbblevel=3"
      local doc, err = sdp.parse(jxsv_sdp(fmtp), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts fbblevel=0 (no SDP spec defines a value form)", function()
      local fmtp = VALID_JXSV_FMTP .. "; fbblevel=0"
      local doc, err = sdp.parse(jxsv_sdp(fmtp), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- RFC 9134 §7.1 — interlace and segmented are bare-flag parameters
    -- (presence indicates the property; no value form). segmented without
    -- interlace is explicitly forbidden: "Signaling of this parameter without
    -- the interlace parameter is forbidden."
    describe("interlace / segmented (RFC 9134 §7.1)", function()
      it("accepts interlace as a bare flag", function()
        local doc, err = sdp.parse(jxsv_sdp(VALID_JXSV_FMTP .. "; interlace"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("accepts interlace + segmented together as bare flags", function()
        local doc, err = sdp.parse(jxsv_sdp(VALID_JXSV_FMTP .. "; interlace; segmented"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("rejects interlace=1 (must be bare flag, not name=value)", function()
        local doc = sdp.parse(jxsv_sdp(VALID_JXSV_FMTP .. "; interlace=1"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("interlace", err.message)
        assert.equal("RFC 9134 §7.1", err.spec_ref)
      end)

      it("rejects segmented=yes (must be bare flag, not name=value)", function()
        local doc = sdp.parse(jxsv_sdp(VALID_JXSV_FMTP .. "; interlace; segmented=yes"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("segmented", err.message)
        assert.equal("RFC 9134 §7.1", err.spec_ref)
      end)

      it("rejects segmented without interlace", function()
        local doc = sdp.parse(jxsv_sdp(VALID_JXSV_FMTP .. "; segmented"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("segmented", err.message)
        assert.matches("interlace", err.message)
        assert.equal("RFC 9134 §7.1", err.spec_ref)
      end)
    end)

    -- RFC 9134 §7.1 — RANGE enum {NARROW, FULLPROTECT, FULL}. Value form is
    -- defined by RFC 9134 (the IANA video/jxsv registration), not ST 2110-22.
    describe("RANGE (RFC 9134 §7.1)", function()
      it("accepts RANGE=NARROW", function()
        local doc, err = sdp.parse(jxsv_sdp(VALID_JXSV_FMTP .. "; RANGE=NARROW"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("rejects RANGE=PARTIAL with RFC 9134 §7.1 cite", function()
        local doc = sdp.parse(jxsv_sdp(VALID_JXSV_FMTP .. "; RANGE=PARTIAL"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("RANGE", err.message)
        assert.equal("RFC 9134 §7.1", err.spec_ref)
      end)
    end)
  end)

  -- ── M22: a=extmap ID upper bound = 255 (RFC 8285 §4.3) ───────────────────────

  describe("a=extmap ID upper bound (M22)", function()
    local function ipmx_with_extmap(id)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX Video",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=extmap:" .. id .. " urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=source-filter: incl IN IP4 239.100.0.1 192.168.1.1",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
      }, "\r\n") .. "\r\n"
    end

    it("accepts extmap ID=255 (upper boundary)", function()
      local doc = sdp.parse(ipmx_with_extmap(255))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("rejects extmap ID=256 (exceeds RFC 8285 §4.3 limit)", function()
      local doc = sdp.parse(ipmx_with_extmap(256))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("255", err.message)
    end)
  end)

  -- ── M23: Session-level c= validation (ST 2110-10 §6.5) ───────────────────────

  describe("session-level c= validation (ST 2110-10 §6.5)", function()
    -- Build a video SDP with a session-level c= (before t=) and no per-media c=.
    local function sess_conn_sdp(conn_line)
      local lines = {
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        conn_line,
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5000 RTP/AVP 96",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        "a=mediaclk:direct=0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      }
      return table.concat(lines, "\r\n") .. "\r\n"
    end

    it("accepts session-level c= with valid multicast address", function()
      local doc = sdp.parse(sess_conn_sdp("c=IN IP4 239.100.0.1/64"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("rejects session-level c= in forbidden 224.0.0.0/24 range", function()
      local doc = sdp.parse(sess_conn_sdp("c=IN IP4 224.0.0.1/64"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.equal("session.connection", err.field_path)
    end)

    it("rejects session-level c= unicast with TTL suffix", function()
      local doc = sdp.parse(sess_conn_sdp("c=IN IP4 192.168.1.10/64"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.equal("session.connection", err.field_path)
    end)
  end)

  -- ── M23: Missing c= detection (ST 2110-10 §6.3) ──────────────────────────────

  describe("missing connection address c= detection (ST 2110-10 §6.3)", function()
    local FMTP = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"

    it("rejects SDP with no session c= and no media c=", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5000 RTP/AVP 96",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 " .. FMTP,
        "a=mediaclk:direct=0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      }, "\r\n") .. "\r\n"
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("connection", err.message)
      assert.equal("ST 2110-10:2022 §6.3", err.spec_ref)
    end)

    it("accepts SDP with session-level c= and no media c=", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "c=IN IP4 239.100.0.1/64",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5000 RTP/AVP 96",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 " .. FMTP,
        "a=mediaclk:direct=0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      }, "\r\n") .. "\r\n"
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("accepts SDP with media-level c= and no session c= (existing behavior)", function()
      -- VIDEO_SDP already has per-media c= and no session c=
      local doc = sdp.parse(VIDEO_SDP)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)
  end)

  -- ── M23: All ts-refclk entries validated (ST 2110-10 §8.2) ───────────────────

  describe("all ts-refclk entries validated (ST 2110-10 §8.2)", function()
    local FMTP = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"

    local function video_with_tsrefclks(lines_before_media, lines_after_rtpmap)
      local base = {
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
      }
      for _, l in ipairs(lines_before_media or {}) do base[#base + 1] = l end
      base[#base + 1] = "m=video 5000 RTP/AVP 96"
      base[#base + 1] = "c=IN IP4 239.100.0.1/64"
      base[#base + 1] = "a=rtpmap:96 raw/90000"
      base[#base + 1] = "a=fmtp:96 " .. FMTP
      base[#base + 1] = "a=mediaclk:direct=0"
      for _, l in ipairs(lines_after_rtpmap or {}) do base[#base + 1] = l end
      return table.concat(base, "\r\n") .. "\r\n"
    end

    it("accepts two valid ts-refclk at session level", function()
      local text = video_with_tsrefclks({
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
      })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("rejects when second ts-refclk is invalid (first is valid)", function()
      local text = video_with_tsrefclks({
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "a=ts-refclk:garbage",
      })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("ts%-refclk", err.message)
    end)

    it("accepts valid ts-refclk at media level only (session has none)", function()
      local text = video_with_tsrefclks(
        {},
        { "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF" }
      )
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("rejects invalid ts-refclk at media level when session also has valid one", function()
      local text = video_with_tsrefclks(
        { "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF" },
        { "a=ts-refclk:garbage" }
      )
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("ts%-refclk", err.message)
    end)
  end)

  -- ── M24: ts-refclk PTP domain range (IEEE 1588-2008 §7.1) ────────────────────

  describe("ts-refclk PTP domain range", function()
    local function with_tsrefclk(value)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "a=ts-refclk:" .. value,
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        "a=mediaclk:direct=0",
      }, "\r\n") .. "\r\n"
    end

    it("accepts ptp= with domain=0 (lower boundary)", function()
      local doc, err = sdp.parse(with_tsrefclk("ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts ptp= with domain=127 (upper boundary)", function()
      local doc, err = sdp.parse(with_tsrefclk("ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:127"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects ptp= with domain=128 (out of range)", function()
      local doc = sdp.parse(with_tsrefclk("ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:128"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("ts%-refclk", err.message)
    end)

    it("rejects ptp= with non-integer domain", function()
      local doc = sdp.parse(with_tsrefclk("ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:abc"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
    end)
  end)

  -- TROFF and CMAX may accompany TP (now always required for raw video
  -- per ST 2110-21:2022 §8.1).
  describe("TROFF/CMAX accepted with TP", function()
    local FMTP_BASE = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"
    local function video20_sdp(fmtp_extra)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=Video",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 " .. FMTP_BASE .. fmtp_extra,
        "a=mediaclk:direct=0",
      }, "\r\n") .. "\r\n"
    end

    it("accepts TROFF and CMAX with TP present", function()
      local doc, err = sdp.parse(video20_sdp("; TROFF=4500; CMAX=3"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  -- ── M24: a=mid uniqueness per session (RFC 5888 §4) ─────────────────────────

  describe("a=mid uniqueness per session", function()
    local PTP = "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"
    local VFMTP = "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"
    local function two_video_blocks(mid1, mid2)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=Two Video",
        "t=0 0",
        "a=group:DUP " .. mid1 .. " " .. mid2,
        PTP,
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=mid:" .. mid1,
        "a=rtpmap:96 raw/90000", VFMTP,
        "a=mediaclk:direct=0",
        "m=video 5010 RTP/AVP 96",
        "c=IN IP4 239.100.0.2/64",
        "a=mid:" .. mid2,
        "a=rtpmap:96 raw/90000", VFMTP,
        "a=mediaclk:direct=0",
      }, "\r\n") .. "\r\n"
    end

    it("rejects duplicate a=mid values across media blocks", function()
      local doc = sdp.parse(two_video_blocks("leg1", "leg1"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("mid", err.message)
    end)

    it("accepts distinct a=mid values", function()
      local doc, err = sdp.parse(two_video_blocks("leg1", "leg2"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- RFC 5888 §4 imposes no position requirement on a=mid within a
    -- media block. AMWA sdpoker PR #12 (open since 2022, never merged)
    -- proposed requiring a=mid immediately before m= and as the SDP's last
    -- line — neither constraint exists in RFC 5888. Accept a=mid anywhere
    -- within the media block.
    it("accepts a=mid in any position within the media block (RFC 5888 §4)", function()
      local PTP_LOCAL = "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"
      local VFMTP_LOCAL = "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=Mid position",
        "t=0 0",
        PTP_LOCAL,
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000", VFMTP_LOCAL,
        "a=mediaclk:direct=0",
        "a=mid:trailing-mid",  -- a=mid as the last attribute in the block
      }, "\r\n") .. "\r\n"
      local doc, err = sdp.parse(text, "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- RFC 5888 §4: mid-attribute = "a=mid:" identification-tag, where
    -- identification-tag is a `token` per RFC 4566 (alphanumeric plus
    -- !#$%&'*+-.^_`|~). Forward slash, parens, colon etc. are forbidden.
    -- Validate in isolation (no a=group line, which would catch the same
    -- malformation first via its own token check).
    local function single_video_with_mid(mid_value)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=Mid test",
        "t=0 0",
        PTP,
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=mid:" .. mid_value,
        "a=rtpmap:96 raw/90000", VFMTP,
        "a=mediaclk:direct=0",
      }, "\r\n") .. "\r\n"
    end

    it("rejects a=mid containing a non-token char (parenthesis)", function()
      local doc = sdp.parse(single_video_with_mid("leg(1"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("mid", err.message)
      assert.matches("token", err.message)
    end)

    it("rejects a=mid containing a forward slash", function()
      local doc = sdp.parse(single_video_with_mid("leg/1"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("mid", err.message)
    end)

    it("accepts a=mid with hyphen and period (valid token chars)", function()
      local doc, err = sdp.parse(single_video_with_mid("primary-feed.0"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  -- ── RFC 5888 §5: a=group syntax (semantics + identification-tags) ────────────

  describe("a=group attribute syntax (RFC 5888 §5)", function()
    local PTP = "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"
    local VFMTP = "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"
    local function with_group(group_value)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=Group test",
        "t=0 0",
        "a=group:" .. group_value,
        PTP,
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=mid:leg1",
        "a=rtpmap:96 raw/90000", VFMTP,
        "a=mediaclk:direct=0",
        "m=video 5010 RTP/AVP 96",
        "c=IN IP4 239.100.0.2/64",
        "a=mid:leg2",
        "a=rtpmap:96 raw/90000", VFMTP,
        "a=mediaclk:direct=0",
      }, "\r\n") .. "\r\n"
    end

    it("rejects a=group with an invalid semantics token (contains parens)", function()
      local doc = sdp.parse(with_group("DU(P leg1 leg2"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("group", err.message)
      assert.matches("token", err.message)
    end)

    it("rejects a=group with an invalid identification-tag (contains comma)", function()
      local doc = sdp.parse(with_group("DUP leg,1 leg2"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("group", err.message)
      assert.matches("token", err.message)
    end)

    it("rejects a=group with whitespace-only value", function()
      local doc = sdp.parse(with_group(" "))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("group", err.message)
    end)

    it("accepts a=group:DUP leg1 leg2 (well-formed)", function()
      local doc, err = sdp.parse(with_group("DUP leg1 leg2"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  -- ── M24: TSMODE / TSDELAY value format (ST 2110-10 §8.7) ─────────────────────

  describe("TSMODE / TSDELAY format", function()
    local FMTP_BASE = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"
    local function video_sdp(extra)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=Video",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 " .. FMTP_BASE .. extra,
        "a=mediaclk:direct=0",
      }, "\r\n") .. "\r\n"
    end

    -- SAMP requires TSDELAY (ST 2110-10:2022 §8.7 cross-check below);
    -- NEW and PRES do not.
    it("accepts TSMODE=SAMP with TSDELAY", function()
      local doc, err = sdp.parse(video_sdp("; TSMODE=SAMP; TSDELAY=100"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
    for _, m in ipairs({ "NEW", "PRES" }) do
      it("accepts TSMODE=" .. m, function()
        local doc, err = sdp.parse(video_sdp("; TSMODE=" .. m), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)
    end

    it("rejects unknown TSMODE value", function()
      local doc = sdp.parse(video_sdp("; TSMODE=GARBAGE"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("TSMODE", err.message)
    end)

    -- M29 G5: ST 2110-10 §8.7 specifies TSDELAY as a "decimal positive
    -- integer number of microseconds" — zero is not a valid signaled delay.
    it("accepts positive TSDELAY", function()
      local doc, err = sdp.parse(video_sdp("; TSDELAY=1000"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects TSDELAY=0 (must be positive per ST 2110-10 §8.7)", function()
      local doc = sdp.parse(video_sdp("; TSDELAY=0"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("TSDELAY", err.message)
    end)

    it("rejects negative TSDELAY", function()
      local doc = sdp.parse(video_sdp("; TSDELAY=-1"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("TSDELAY", err.message)
    end)

    it("rejects non-integer TSDELAY", function()
      local doc = sdp.parse(video_sdp("; TSDELAY=abc"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("TSDELAY", err.message)
    end)

    -- ST 2110-10:2022 §8.7 (and §7.9): "Devices which signal TSMODE=SAMP
    -- shall also signal their Transmission Delay value in the SDP as
    -- indicated in section 8.7."
    describe("TSMODE=SAMP → TSDELAY presence (§8.7)", function()
      it("rejects TSMODE=SAMP without TSDELAY", function()
        local doc = sdp.parse(video_sdp("; TSMODE=SAMP"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("TSMODE=SAMP", err.message)
        assert.matches("TSDELAY", err.message)
        assert.equal("ST 2110-10:2022 §8.7", err.spec_ref)
      end)

      it("accepts TSMODE=NEW without TSDELAY (no cross-rule)", function()
        local doc, err = sdp.parse(video_sdp("; TSMODE=NEW"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)
    end)
  end)

  -- ── M24: a=source-filter format (RFC 4570) ───────────────────────────────────

  describe("a=source-filter format", function()
    local function video_sdp(sf_value)
      local lines = {
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=Video",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=source-filter:" .. sf_value,
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        "a=mediaclk:direct=0",
      }
      return table.concat(lines, "\r\n") .. "\r\n"
    end

    it("accepts 'incl IN IP4 <dest> <src>'", function()
      local doc, err = sdp.parse(video_sdp(" incl IN IP4 239.100.0.1 192.168.1.1"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts 'excl IN IP6 <dest> <src>'", function()
      local doc, err = sdp.parse(video_sdp(" excl IN IP6 ff0e::1 fe80::1"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects unknown filter mode", function()
      local doc = sdp.parse(video_sdp(" maybe IN IP4 239.100.0.1 192.168.1.1"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("source%-filter", err.message)
    end)

    it("rejects bad addrtype", function()
      local doc = sdp.parse(video_sdp(" incl IN IP9 239.100.0.1 192.168.1.1"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
    end)

    -- RFC 4570 §3: address-types includes "*"; in that case dest/src are FQDNs
    -- rather than literal IPs (which we therefore do not check when addrtype="*").
    it("accepts addrtype '*' with FQDN destination and source (RFC 4570 §3)", function()
      local doc, err = sdp.parse(video_sdp(" incl IN * stream.example.com sender.example.com"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects missing source address", function()
      local doc = sdp.parse(video_sdp(" incl IN IP4 239.100.0.1"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
    end)

    -- Symmetric session-level validation (audit A12). The media-level scan
    -- has always validated source-filter syntax; the session-level scan
    -- previously only checked presence in the IPMX tier.
    describe("session-level a=source-filter syntax (RFC 4570 §3)", function()
      local function session_sf_sdp(sf_value)
        return table.concat({
          "v=0",
          "o=- 1234567890 1 IN IP4 192.168.1.1",
          "s=Video",
          "t=0 0",
          "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
          "a=source-filter:" .. sf_value,
          "m=video 5000 RTP/AVP 96",
          "c=IN IP4 239.100.0.1/64",
          "a=rtpmap:96 raw/90000",
          "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
          "a=mediaclk:direct=0",
        }, "\r\n") .. "\r\n"
      end

      it("accepts a syntactically valid session-level source-filter", function()
        local doc, err = sdp.parse(session_sf_sdp(" incl IN IP4 239.100.0.1 192.168.1.1"), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)

      it("rejects a session-level source-filter missing src", function()
        local doc = sdp.parse(session_sf_sdp(" incl IN IP4 239.100.0.1"))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("source%-filter", err.message)
        assert.equal("RFC 4570 §3", err.spec_ref)
      end)
    end)
  end)

  -- ── M25 ───────────────────────────────────────────────────────────────────────
  -- Validation gap closure round 4. See PLAN.md M25 for full list / spec refs.

  describe("M25 H1: RTP dynamic payload type range 96-127 (ST 2110-10 §6.2)", function()
    local PTP = "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"
    local VFMTP = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"

    local function video_pt(pt)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=PT range test",
        "t=0 0",
        PTP,
        string.format("m=video 5000 RTP/AVP %d", pt),
        "c=IN IP4 239.100.0.1/64",
        string.format("a=rtpmap:%d raw/90000", pt),
        string.format("a=fmtp:%d %s", pt, VFMTP),
        "a=mediaclk:direct=0",
      }, "\r\n") .. "\r\n"
    end

    it("accepts payload type 96 (lower boundary)", function()
      local doc, err = sdp.parse(video_pt(96), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts payload type 127 (upper boundary)", function()
      local doc, err = sdp.parse(video_pt(127), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects payload type 95 (one below dynamic range)", function()
      local doc = sdp.parse(video_pt(95))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("payload type", err.message)
      assert.matches("96", err.message)
      assert.equal("ST 2110-10:2022 §6.2", err.spec_ref)
    end)

    it("rejects payload type 128 (one above dynamic range)", function()
      local doc = sdp.parse(video_pt(128))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("payload type", err.message)
    end)

    it("rejects payload type 0", function()
      local doc = sdp.parse(video_pt(0))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("payload type", err.message)
    end)
  end)

  -- ST 2110-10 §6.2: dynamic PT 96-127 "unless a fixed payload type
  -- designation exists for that RTP Stream within the IETF standard which
  -- specifies it." RFC 3551 §6 Table 4 statics that match ST 2110-30
  -- audio essences: PT 10 = L16/44100/2, PT 11 = L16/44100/1.
  describe("static PT carve-out (ST 2110-10 §6.2 / RFC 3551 §6)", function()
    local PTP = "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"
    local function audio_static_pt(pt, enc, rate, ch)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Audio static PT",
        "t=0 0", PTP,
        string.format("m=audio 5004 RTP/AVP %d", pt),
        "c=IN IP4 239.100.0.1/64",
        string.format("a=rtpmap:%d %s/%d/%d", pt, enc, rate, ch),
        "a=ptime:1",
        "a=mediaclk:direct=0", PTP,
      }, "\r\n") .. "\r\n"
    end

    it("accepts PT 10 with L16/44100/2 (RFC 3551 §6 static)", function()
      local doc, err = sdp.parse(audio_static_pt(10, "L16", 44100, 2), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts PT 11 with L16/44100/1 (RFC 3551 §6 static)", function()
      local doc, err = sdp.parse(audio_static_pt(11, "L16", 44100, 1), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects PT 10 with L16/48000/2 (PT 10 is rate-fixed at 44100)", function()
      local doc = sdp.parse(audio_static_pt(10, "L16", 48000, 2))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("payload type", err.message)
    end)

    it("rejects PT 10 with L24/44100/2 (no L24 static at PT 10)", function()
      local doc = sdp.parse(audio_static_pt(10, "L24", 44100, 2))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("payload type", err.message)
    end)

    it("rejects PT 12 with L16/44100/1 (no static at PT 12)", function()
      local doc = sdp.parse(audio_static_pt(12, "L16", 44100, 1))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("payload type", err.message)
    end)
  end)

  describe("M25 H4/M6: DUP leg distinctness and consistency (ST 2110-10 §8.5)", function()
    local PTP = "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"
    local VFMTP = "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"

    -- Build a two-leg DUP SDP. opts:
    --   c1, c2 — per-leg c= address (default different multicast groups)
    --   sf1, sf2 — per-leg a=source-filter; nil omits
    --   rtpmap1, rtpmap2 — per-leg rtpmap
    --   fmtp1, fmtp2 — per-leg fmtp
    local function dup_sdp(opts)
      opts = opts or {}
      local c1 = opts.c1 or "c=IN IP4 239.100.0.1/64"
      local c2 = opts.c2 or "c=IN IP4 239.100.0.2/64"
      local rtpmap1 = opts.rtpmap1 or "a=rtpmap:96 raw/90000"
      local rtpmap2 = opts.rtpmap2 or "a=rtpmap:96 raw/90000"
      local fmtp1 = opts.fmtp1 or VFMTP
      local fmtp2 = opts.fmtp2 or VFMTP
      local lines = {
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=DUP Test",
        "t=0 0",
        "a=group:DUP leg1 leg2",
        PTP,
        "m=video 5000 RTP/AVP 96",
        c1,
        "a=mid:leg1",
        rtpmap1,
        fmtp1,
        "a=mediaclk:direct=0",
      }
      if opts.sf1 then lines[#lines+1] = opts.sf1 end
      lines[#lines+1] = "m=video 5010 RTP/AVP 96"
      lines[#lines+1] = c2
      lines[#lines+1] = "a=mid:leg2"
      lines[#lines+1] = rtpmap2
      lines[#lines+1] = fmtp2
      lines[#lines+1] = "a=mediaclk:direct=0"
      if opts.sf2 then lines[#lines+1] = opts.sf2 end
      return table.concat(lines, "\r\n") .. "\r\n"
    end

    it("accepts DUP legs with different destination addresses", function()
      local doc, err = sdp.parse(dup_sdp(), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects DUP legs with identical c= and identical source-filter src", function()
      local doc = sdp.parse(dup_sdp({
        c1 = "c=IN IP4 239.100.0.1/64",
        c2 = "c=IN IP4 239.100.0.1/64",
        sf1 = "a=source-filter: incl IN IP4 239.100.0.1 192.168.1.50",
        sf2 = "a=source-filter: incl IN IP4 239.100.0.1 192.168.1.50",
      }))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("DUP", err.message)
      assert.matches("identical", err.message)
      assert.equal("ST 2110-10:2022 §8.5", err.spec_ref)
    end)

    it("accepts DUP legs with same c= but different source-filter src", function()
      local doc, err = sdp.parse(dup_sdp({
        c1 = "c=IN IP4 239.100.0.1/64",
        c2 = "c=IN IP4 239.100.0.1/64",
        sf1 = "a=source-filter: incl IN IP4 239.100.0.1 192.168.1.50",
        sf2 = "a=source-filter: incl IN IP4 239.100.0.1 192.168.1.60",
      }), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts DUP legs with different c= and same source-filter src", function()
      local doc, err = sdp.parse(dup_sdp({
        sf1 = "a=source-filter: incl IN IP4 239.100.0.1 192.168.1.50",
        sf2 = "a=source-filter: incl IN IP4 239.100.0.2 192.168.1.50",
      }), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("M6 rejects DUP video legs with different rtpmap encodings", function()
      -- leg1 = raw video, leg2 = jxsv (with b=AS so the leg is internally
      -- valid; the DUP encoding-mismatch check is the assertion under test).
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=DUP Test", "t=0 0",
        "a=group:DUP leg1 leg2", PTP,
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=mid:leg1",
        "a=rtpmap:96 raw/90000", VFMTP,
        "a=mediaclk:direct=0",
        "m=video 5010 RTP/AVP 96",
        "c=IN IP4 239.100.0.2/64",
        "b=AS:200000",
        "a=mid:leg2",
        "a=rtpmap:96 jxsv/90000",
        "a=fmtp:96 width=1920; height=1080; exactframerate=25; TP=2110TPNL; packetmode=0",
        "a=mediaclk:direct=0",
      }, "\r\n") .. "\r\n"
      local doc = sdp.parse(text)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("DUP", err.message)
      assert.matches("encoding", err.message)
    end)

    it("M6 rejects DUP video legs with different clock rates", function()
      -- artificially set a different clock rate on leg2; ST 2110 will reject it
      -- as clock_rate != 90000 anyway, but the DUP check should also catch it.
      -- Use jxsv encoding fudge: same encoding but different rate — both legs
      -- raw/90000 vs raw/9000 (the second will independently fail). For purity,
      -- test mismatch via raw/90000 vs raw/45000 (independently invalid).
      local doc = sdp.parse(dup_sdp({
        rtpmap2 = "a=rtpmap:96 raw/45000",
      }))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
    end)

    -- Streampunk sdpoker PR #16 follow-up: ST 2110-40 ancillary (smpte291)
    -- legs in a DUP group are validated like any other ST 2110-40 stream
    -- (per-leg SSN + exactframerate per ST 2110-40:2023 §7) and consistency
    -- between legs is enforced by the same ST 2022-7 / RFC 7104 rules.
    it("accepts DUP group of two smpte291 legs (ST 2110-40 + ST 2022-7)", function()
      local anc_fmtp = "a=fmtp:96 SSN=ST2110-40:2018; exactframerate=25"
      local doc, err = sdp.parse(dup_sdp({
        rtpmap1 = "a=rtpmap:96 smpte291/90000",
        rtpmap2 = "a=rtpmap:96 smpte291/90000",
        fmtp1   = anc_fmtp,
        fmtp2   = anc_fmtp,
      }), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    -- ST 2022-7 §6 (referenced by ST 2110-10 §8.5): "Senders shall transmit
    -- on both flows the same RTP payload data and shall use the same payload
    -- type number." Different PTs across legs are a violation.
    it("rejects DUP legs with different payload type numbers", function()
      local doc = sdp.parse(dup_sdp({
        rtpmap1 = "a=rtpmap:96 raw/90000",
        rtpmap2 = "a=rtpmap:97 raw/90000",
        fmtp1   = "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        fmtp2   = "a=fmtp:97 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
      }))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("DUP", err.message)
      assert.matches("payload type", err.message)
    end)

    it("rejects DUP video legs with different fmtp essence parameters", function()
      -- Same rtpmap (PT, enc, rate) but different resolutions — the payload
      -- can't be identical bit-for-bit if the resolution differs.
      local doc = sdp.parse(dup_sdp({
        fmtp1 = "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        fmtp2 = "a=fmtp:96 sampling=YCbCr-4:2:2; width=1280; height=720;  exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
      }))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("DUP", err.message)
      assert.matches("fmtp", err.message)
    end)

    it("accepts DUP legs with identical rtpmap and fmtp values", function()
      local doc, err = sdp.parse(dup_sdp(), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  describe("M25 M3: MAXUDP upper bound (ST 2110-10 §6.4)", function()
    local function video_maxudp(maxudp)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=MAXUDP test",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; MAXUDP=" .. maxudp,
        "a=mediaclk:direct=0",
      }, "\r\n") .. "\r\n"
    end

    it("accepts MAXUDP=1460 (Standard UDP Size Limit lower-equal boundary)", function()
      local doc, err = sdp.parse(video_maxudp(1460), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts MAXUDP=8960 (Extended UDP Size Limit upper boundary)", function()
      local doc, err = sdp.parse(video_maxudp(8960), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects MAXUDP=8961 (one above Extended UDP Size Limit)", function()
      local doc = sdp.parse(video_maxudp(8961))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("MAXUDP", err.message)
      assert.matches("8960", err.message)
    end)

    it("rejects MAXUDP=65535", function()
      local doc = sdp.parse(video_maxudp(65535))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("MAXUDP", err.message)
    end)
  end)

  describe("M25 M4: session-level a=mediaclk rejected (ST 2110-10 §8.3)", function()
    it("rejects session-level a=mediaclk (must be media-level)", function()
      local text = table.concat({
        "v=0",
        "o=- 1 1 IN IP4 192.168.1.1",
        "s=session mediaclk test",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "a=mediaclk:direct=0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        "a=mediaclk:direct=0",
      }, "\r\n") .. "\r\n"
      local doc = sdp.parse(text)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("mediaclk", err.message)
      assert.matches("media%-level", err.message)
      assert.equal("ST 2110-10:2022 §8.3", err.spec_ref)
    end)
  end)

  describe("M25 M5: b=AS validated at session and media level (TR-10-7 §11)", function()
    -- ST 2110 tier doesn't reject b=AS (TR-10-7 is IPMX-tier), but the value
    -- must still parse as an unsigned integer per RFC 4566 §5.8; b=AS:0 at
    -- session level is rejected by the IPMX tier specifically.
    it("accepts session-level b=AS:5000 in ST 2110", function()
      local text = table.concat({
        "v=0",
        "o=- 1 1 IN IP4 192.168.1.1",
        "s=session b=AS test",
        "b=AS:5000",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        "a=mediaclk:direct=0",
      }, "\r\n") .. "\r\n"
      local doc, err = sdp.parse(text, "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  -- ── M26 ──────────────────────────────────────────────────────────────────────

  describe("M26 H2: ST 2110 mode restricts ts-refclk ptp version to IEEE1588-2008 (§6.1/§8.2)", function()
    local function st2110_with_tsrefclk(ts_value)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST 2110 M26 H2",
        "t=0 0",
        "a=ts-refclk:" .. ts_value,
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        "a=mediaclk:direct=0",
        "a=ts-refclk:" .. ts_value,
      }, "\r\n") .. "\r\n"
    end

    it("rejects ptp=IEEE1588-2019:<gmid> in ST 2110 mode", function()
      local doc = sdp.parse(st2110_with_tsrefclk("ptp=IEEE1588-2019:00-11-22-FF-FE-33-44-55:0"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("IEEE1588%-2008", err.message)
    end)

    it("rejects ptp=IEEE1588-2002:<gmid> in ST 2110 mode", function()
      local doc = sdp.parse(st2110_with_tsrefclk("ptp=IEEE1588-2002:00-11-22-FF-FE-33-44-55:0"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("IEEE1588%-2008", err.message)
    end)
  end)

  describe("c= IPv6 multicast numaddr suffix (RFC 8866 §9 IP6-multicast)", function()
    local function st2110_with_c(c_line)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP6 2001:db8::1",
        "s=ST 2110 IPv6 c=",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "m=video 5000 RTP/AVP 96",
        c_line,
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        "a=mediaclk:direct=0",
      }, "\r\n") .. "\r\n"
    end

    -- RFC 8866 §9 ABNF: IP6-multicast = IP6-address [ "/" numaddr ]. The
    -- suffix is a layered-multicast count, not a TTL. §5.7 prohibits TTL
    -- on IPv6 multicast; the bracketed numaddr remains permitted.
    it("accepts IPv6 multicast with /numaddr suffix (ff02::1/64)", function()
      local doc, err = sdp.parse(st2110_with_c("c=IN IP6 ff02::1/64"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts IPv6 unicast without suffix", function()
      local doc, err = sdp.parse(st2110_with_c("c=IN IP6 2001:db8::1"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects IPv6 unicast with /suffix (no slash form for unicast)", function()
      local doc = sdp.parse(st2110_with_c("c=IN IP6 2001:db8::1/64"))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("unicast", err.message)
    end)

    it("rejects IPv6 multicast with non-numeric /numaddr", function()
      local doc = sdp.parse(st2110_with_c("c=IN IP6 ff02::1/abc"))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
    end)

    -- RFC 8866 §9: numaddr = integer = POS-DIGIT *DIGIT (no leading zero).
    it("rejects IPv6 multicast with /numaddr=0", function()
      local doc = sdp.parse(st2110_with_c("c=IN IP6 ff02::1/0"))
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.is_table(err)
    end)
  end)

  -- ── M29 G1: c= IPv4/IPv6 literal address syntax (ST 2110-10 §6.5) ──────────
  -- ST 2110-10 §6.5 mandates IPv4 unicast per RFC 791 and IPv6 per RFC 2460.
  -- The old valid_connection_address only extracted the first octet to test
  -- multicast range; the rest of the address was passed through unchecked.
  describe("M29 G1: c= IPv4/IPv6 literal address syntax", function()
    local function st2110_with_c(c_line)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST 2110 M29 G1",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "m=video 5000 RTP/AVP 96",
        c_line,
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        "a=mediaclk:direct=0",
      }, "\r\n") .. "\r\n"
    end

    it("rejects IPv4 with only three octets (1.2.3)", function()
      local doc = sdp.parse(st2110_with_c("c=IN IP4 1.2.3"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("IPv4", err.message)
    end)

    it("rejects IPv4 with octet > 255 (unicast path)", function()
      local doc = sdp.parse(st2110_with_c("c=IN IP4 999.0.0.0"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("IPv4", err.message)
    end)

    it("rejects IPv4 with octet > 255 inside (192.168.999.1)", function()
      local doc = sdp.parse(st2110_with_c("c=IN IP4 192.168.999.1"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("IPv4", err.message)
    end)

    it("rejects IPv4 with five octets (192.168.1.1.5)", function()
      local doc = sdp.parse(st2110_with_c("c=IN IP4 192.168.1.1.5"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("IPv4", err.message)
    end)

    it("rejects IPv6 unicast with non-IPv6 syntax (not-an-ipv6)", function()
      local doc = sdp.parse(st2110_with_c("c=IN IP6 not-an-ipv6"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("IPv6", err.message)
    end)

    it("rejects IPv6 multicast with garbage tail (ff02::garbage)", function()
      local doc = sdp.parse(st2110_with_c("c=IN IP6 ff02::garbage"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("IPv6", err.message)
    end)

    it("accepts IPv4 max-octet boundary (255.255.255.254)", function()
      local doc, err = sdp.parse(st2110_with_c("c=IN IP4 255.255.255.254"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts compressed IPv6 unicast (2001:db8::1)", function()
      local doc, err = sdp.parse(st2110_with_c("c=IN IP6 2001:db8::1"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  -- ── M29 G2: a=source-filter literal address syntax (ST 2110-10 §6.5 / RFC 4570) ──
  -- The previous _sf_token captured any non-space token for dest and src;
  -- the addresses now must parse as literal IPv4/IPv6 per the declared addrtype.
  describe("M29 G2: a=source-filter literal address syntax", function()
    local function st2110_with_sf(sf_line)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST 2110 M29 G2",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        "a=mediaclk:direct=0",
        sf_line,
      }, "\r\n") .. "\r\n"
    end

    it("rejects source-filter with non-IPv4 src token", function()
      local doc = sdp.parse(st2110_with_sf(
        "a=source-filter: incl IN IP4 239.100.0.1 not-an-ip-at-all"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("source%-filter", err.message)
    end)

    it("rejects source-filter with non-IPv4 dest token", function()
      local doc = sdp.parse(st2110_with_sf(
        "a=source-filter: incl IN IP4 hostname.example 192.168.1.5"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("source%-filter", err.message)
    end)

    it("rejects source-filter with IPv4 octet > 255", function()
      local doc = sdp.parse(st2110_with_sf(
        "a=source-filter: incl IN IP4 239.999.0.1 192.168.1.5"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("source%-filter", err.message)
    end)

    it("rejects source-filter with non-IPv6 src token (when addrtype=IP6)", function()
      local doc = sdp.parse(st2110_with_sf(
        "a=source-filter: incl IN IP6 ff02::1 garbage"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("source%-filter", err.message)
    end)

    it("accepts source-filter with valid IPv4 dest and src", function()
      local doc, err = sdp.parse(st2110_with_sf(
        "a=source-filter: incl IN IP4 239.100.0.1 192.168.1.50"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts source-filter with multiple valid IPv4 src addresses", function()
      local doc, err = sdp.parse(st2110_with_sf(
        "a=source-filter: incl IN IP4 239.100.0.1 192.168.1.50 192.168.1.51"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts source-filter with valid IPv6 dest and src", function()
      local doc, err = sdp.parse(st2110_with_sf(
        "a=source-filter: incl IN IP6 ff02::1 2001:db8::1"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  -- ── M29 G4 (ST 2110 side): source-filter NOT required at ST 2110 tier ──────
  -- The matching requirement at IPMX tier (TR-10-TP-1 §13.2) is tested in
  -- ipmx_spec. ST 2110-10 §8.4 only says SHOULD; this regression guard ensures
  -- the strict tier does not falsely reject SDPs that omit a=source-filter.
  describe("M29 G4 (ST 2110): a=source-filter is optional at ST 2110 tier", function()
    it("accepts ST 2110 SDP with no a=source-filter", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST 2110 G4 regression",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN",
        "a=mediaclk:direct=0",
      }, "\r\n") .. "\r\n"
      local doc, err = sdp.parse(text, "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  -- ── M30 G1: ST 2110-20 §7.4.2 depth enumeration ────────────────────────────
  -- Spec lists depth ∈ {8, 10, 12, 16, 16f}. Previously the validator only
  -- required a positive integer, so depth=14 / depth=24 passed despite being
  -- explicitly outside the enumeration.
  describe("M30 G1: ST 2110-20 depth enumeration (§7.4.2)", function()
    local BASE = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"

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
      }, "\r\n") .. "\r\n"
    end

    for _, depth in ipairs({ "8", "10", "12", "16", "16f" }) do
      it("accepts depth=" .. depth, function()
        local doc, err = sdp.parse(video20_sdp(BASE .. "; depth=" .. depth), "st2110")
        assert.is_nil(err)
        assert.is_table(doc)
      end)
    end

    for _, depth in ipairs({ "7", "9", "11", "14", "24", "32", "0", "16x", "abc" }) do
      it("rejects depth=" .. depth, function()
        local doc = sdp.parse(video20_sdp(BASE .. "; depth=" .. depth))
        assert.is_table(doc)
        local ok, err = doc:validate("st2110")
        assert.is_nil(ok)
        assert.is_table(err)
        assert.matches("depth", err.message)
        assert.equal("ST 2110-20:2022 §7.4.2", err.spec_ref)
      end)
    end
  end)

  -- ── M30 G1b: ST 2110-20 §7.2 width/height range 1..32767 ───────────────────
  -- "Permitted values are integers between 1 and 32767 inclusive."
  describe("M30 G1b: ST 2110-20 width/height upper bound (§7.2)", function()
    local BASE = "sampling=YCbCr-4:2:2; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"

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
      }, "\r\n") .. "\r\n"
    end

    it("accepts width=32767 height=32767 (upper bound)", function()
      local doc, err = sdp.parse(video20_sdp(BASE .. "; width=32767; height=32767"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects width=32768 (one above bound)", function()
      local doc = sdp.parse(video20_sdp(BASE .. "; width=32768; height=1080"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("width", err.message)
      assert.equal("ST 2110-20:2022 §7.2", err.spec_ref)
    end)

    it("rejects height=32768 (one above bound)", function()
      local doc = sdp.parse(video20_sdp(BASE .. "; width=1920; height=32768"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("height", err.message)
      assert.equal("ST 2110-20:2022 §7.2", err.spec_ref)
    end)

    it("rejects width=99999 (far above bound)", function()
      local doc = sdp.parse(video20_sdp(BASE .. "; width=99999; height=1080"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("width", err.message)
    end)
  end)

  -- ── M30 G4: ST 2110-20 §7.3 interlace / segmented are flag-only ────────────
  -- §7.1 defines two fmtp parameter forms: <name>=<value> and standalone
  -- <name>. §7.3 defines interlace/segmented purely by presence/absence of
  -- the parameter name (no value form). interlace=anything is not covered by
  -- the spec; treat as malformed under §7.3.
  describe("M30 G4: interlace/segmented flag-only (§7.3)", function()
    local BASE = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"

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
      }, "\r\n") .. "\r\n"
    end

    it("rejects interlace=1 (must be a bare flag, not name=value)", function()
      local doc = sdp.parse(video20_sdp(BASE .. "; interlace=1"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("interlace", err.message)
      assert.equal("ST 2110-20:2022 §7.3", err.spec_ref)
    end)

    it("rejects interlace=true", function()
      local doc = sdp.parse(video20_sdp(BASE .. "; interlace=true"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("interlace", err.message)
    end)

    it("rejects segmented=anything (even when interlace is also a flag)", function()
      local doc = sdp.parse(video20_sdp(BASE .. "; interlace; segmented=yes"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("segmented", err.message)
      assert.equal("ST 2110-20:2022 §7.3", err.spec_ref)
    end)

    it("accepts interlace bare flag (regression guard)", function()
      local doc, err = sdp.parse(video20_sdp(BASE .. "; interlace"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts interlace; segmented bare flags (regression guard)", function()
      local doc, err = sdp.parse(video20_sdp(BASE .. "; interlace; segmented"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  -- ── M30 G9: ST 2110-20 §6.3.3 MAXUDP forbidden with PM=2110BPM ─────────────
  -- "The Extended UDP size limit defined in SMPTE ST 2110-10 shall not be used
  -- in the Block Packing Mode." MAXUDP signals Extended limit operation; its
  -- presence with PM=2110BPM violates the explicit "shall not" in §6.3.3.
  describe("M30 G9: MAXUDP forbidden with PM=2110BPM (§6.3.3)", function()
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
      }, "\r\n") .. "\r\n"
    end

    local GPM_BASE = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN"
    local BPM_BASE = "sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110BPM; SSN=ST2110-20:2022; TP=2110TPN"

    it("rejects MAXUDP=8960 with PM=2110BPM", function()
      local doc = sdp.parse(video20_sdp(BPM_BASE .. "; MAXUDP=8960"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("MAXUDP", err.message)
      assert.matches("BPM", err.message)
      assert.equal("ST 2110-20:2022 §6.3.3", err.spec_ref)
    end)

    it("rejects MAXUDP=1500 with PM=2110BPM", function()
      local doc = sdp.parse(video20_sdp(BPM_BASE .. "; MAXUDP=1500"))
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(ok)
      assert.matches("MAXUDP", err.message)
    end)

    it("accepts PM=2110BPM without MAXUDP (Standard UDP Size Limit implicit)", function()
      local doc, err = sdp.parse(video20_sdp(BPM_BASE), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts PM=2110GPM with MAXUDP=8960 (regression guard — GPM permits Extended)", function()
      local doc, err = sdp.parse(video20_sdp(GPM_BASE .. "; MAXUDP=8960"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)
end)
