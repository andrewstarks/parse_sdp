---@diagnostic disable
describe("IPMX validation", function()
  local sdp = require("parse_sdp")

  -- ── Fixtures ──────────────────────────────────────────────────────────────────

  -- Minimal valid IPMX SDP: passes ST 2110, has a=extmap, has IPMX fmtp marker.
  local IPMX_VIDEO_SDP = table.concat({
    "v=0",
    "o=- 1234567890 1 IN IP4 192.168.1.1",
    "s=IPMX Video",
    "t=0 0",
    "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
    "m=video 5000 RTP/AVP 96",
    "c=IN IP4 239.100.0.1/64",
    "a=rtpmap:96 raw/90000",
    "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; IPMX",
    "a=mediaclk:direct=0",
    "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
    "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
  }, "\r\n")

  -- Valid ST 2110 SDP that lacks a=extmap (not IPMX).
  local ST2110_ONLY_SDP = table.concat({
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

  -- Generic RFC 4566 SDP (no media blocks, no ST 2110 attributes).
  local GENERIC_SDP = table.concat({
    "v=0",
    "o=- 1 1 IN IP4 127.0.0.1",
    "s=Plain SDP",
    "t=0 0",
  }, "\r\n")

  -- Build a minimal valid IPMX video SDP with optional extra attributes and fmtp override.
  local function base_ipmx_sdp(extra_session_attrs, extra_media_attrs, video_fmtp_override)
    local fmtp = video_fmtp_override or
      "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; IPMX"
    local lines = {
      "v=0",
      "o=- 1234567890 1 IN IP4 192.168.1.1",
      "s=IPMX Video",
      "t=0 0",
      "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
      "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
    }
    for _, a in ipairs(extra_session_attrs or {}) do lines[#lines + 1] = a end
    lines[#lines + 1] = "m=video 5000 RTP/AVP 96"
    lines[#lines + 1] = "c=IN IP4 239.100.0.1/64"
    lines[#lines + 1] = "a=rtpmap:96 raw/90000"
    lines[#lines + 1] = fmtp
    lines[#lines + 1] = "a=mediaclk:direct=0"
    lines[#lines + 1] = "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF"
    for _, a in ipairs(extra_media_attrs or {}) do lines[#lines + 1] = a end
    return table.concat(lines, "\r\n")
  end

  -- ── Original test suites (updated fixtures) ──────────────────────────────────

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

  describe("doc:validate('ipmx') — extmap location", function()
    it("returns true when extmap is at session level only", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX Video",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
      }, "\r\n")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(err)
      assert.equal(true, ok)
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

  -- ── IPMX fmtp marker (TR-10-1 §10.1) ─────────────────────────────────────────

  describe("IPMX fmtp marker (TR-10-1 §10.1)", function()
    it("rejects video fmtp without IPMX marker", function()
      local text = base_ipmx_sdp({}, {},
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("IPMX", err.message)
    end)

    it("accepts video fmtp with IPMX marker", function()
      local doc = sdp.parse(IPMX_VIDEO_SDP)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("error references TR-10-1 §10.1 and fmtp field_path", function()
      local text = base_ipmx_sdp({}, {},
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN")
      local doc = sdp.parse(text)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("fmtp", err.field_path)
      assert.matches("TR%-10%-1", err.spec_ref)
    end)
  end)

  -- ── a=hkep validation (TR-10-5 §10) ──────────────────────────────────────────

  describe("a=hkep validation (TR-10-5 §10)", function()
    local VALID_HKEP = "a=hkep:10000 IN IP4 192.168.1.100 550e8400-e29b-41d4-a716-446655440000 01-02-03-04-05"

    it("accepts valid a=hkep at session level", function()
      local text = base_ipmx_sdp({ VALID_HKEP })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("accepts multiple a=hkep lines", function()
      local text = base_ipmx_sdp({
        VALID_HKEP,
        "a=hkep:10001 IN IP4 192.168.1.101 660e8400-e29b-41d4-a716-446655440001 02-03-04-05-06",
      })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("rejects a=hkep with wrong nettype", function()
      local text = base_ipmx_sdp({
        "a=hkep:10000 OUT IP4 192.168.1.100 550e8400-e29b-41d4-a716-446655440000 01-02-03-04-05",
      })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("hkep", err.message)
      assert.matches("nettype", err.message)
    end)

    it("rejects a=hkep with wrong addrtype", function()
      local text = base_ipmx_sdp({
        "a=hkep:10000 IN IP3 192.168.1.100 550e8400-e29b-41d4-a716-446655440000 01-02-03-04-05",
      })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("hkep", err.message)
      assert.matches("addrtype", err.message)
    end)

    it("rejects a=hkep with malformed node-id", function()
      local text = base_ipmx_sdp({
        "a=hkep:10000 IN IP4 192.168.1.100 not-a-valid-uuid 01-02-03-04-05",
      })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("hkep", err.message)
      assert.matches("node%-id", err.message)
    end)

    it("rejects a=hkep with malformed port-id", function()
      local text = base_ipmx_sdp({
        "a=hkep:10000 IN IP4 192.168.1.100 550e8400-e29b-41d4-a716-446655440000 01:02:03:04:05",
      })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("hkep", err.message)
      assert.matches("port%-id", err.message)
    end)

    it("rejects a=hkep with too few fields", function()
      local text = base_ipmx_sdp({
        "a=hkep:10000 IN IP4 192.168.1.100",
      })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("hkep", err.message)
    end)

    it("error references TR-10-5 §10 and session field_path", function()
      local text = base_ipmx_sdp({
        "a=hkep:10000 IN IP4 192.168.1.100 bad-node-id 01-02-03-04-05",
      })
      local doc = sdp.parse(text)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("session", err.field_path)
      assert.matches("TR%-10%-5", err.spec_ref)
    end)

    it("accepts valid a=hkep at media block level", function()
      local text = base_ipmx_sdp(
        {},
        { "a=hkep:10000 IN IP4 192.168.1.100 550e8400-e29b-41d4-a716-446655440000 01-02-03-04-05" }
      )
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("rejects invalid a=hkep at media block level", function()
      local text = base_ipmx_sdp(
        {},
        { "a=hkep:10000 IN IP4 192.168.1.100 not-a-valid-uuid 01-02-03-04-05" }
      )
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("hkep", err.message)
      assert.matches("media%[1%]", err.field_path)
    end)
  end)

  -- ── a=privacy validation (TR-10-13 §13) ──────────────────────────────────────

  describe("a=privacy validation (TR-10-13 §13)", function()
    local VALID_PRIVACY =
      "a=privacy: protocol=RTP; mode=AES-128-CTR; iv=0102030405060708090a0b0c0d0e0f10; key_generator=aabbccdd; key_version=01; key_id=deadbeef"

    it("accepts valid a=privacy at session level", function()
      local text = base_ipmx_sdp({ VALID_PRIVACY })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("accepts valid a=privacy at media level", function()
      local text = base_ipmx_sdp({}, { VALID_PRIVACY })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("accepts all 12 valid mode values", function()
      local modes = {
        "AES-128-CTR", "AES-256-CTR",
        "AES-128-CTR_CMAC-64", "AES-256-CTR_CMAC-64",
        "AES-128-CTR_CMAC-64-AAD", "AES-256-CTR_CMAC-64-AAD",
        "ECDH_AES-128-CTR", "ECDH_AES-256-CTR",
        "ECDH_AES-128-CTR_CMAC-64", "ECDH_AES-256-CTR_CMAC-64",
        "ECDH_AES-128-CTR_CMAC-64-AAD", "ECDH_AES-256-CTR_CMAC-64-AAD",
      }
      for _, mode in ipairs(modes) do
        local privacy = "a=privacy: protocol=RTP; mode=" .. mode ..
          "; iv=0102030405060708090a0b0c0d0e0f10; key_generator=aabb; key_version=01; key_id=dead"
        local text = base_ipmx_sdp({ privacy })
        local doc = sdp.parse(text)
        assert.is_table(doc)
        local ok, err = doc:validate("ipmx")
        assert.is_nil(err, "mode " .. mode .. " should be valid")
        assert.equal(true, ok)
      end
    end)

    it("rejects invalid protocol value", function()
      local text = base_ipmx_sdp({
        "a=privacy: protocol=UDP; mode=AES-128-CTR; iv=0102030405060708090a0b0c0d0e0f10; key_generator=aabb; key_version=01; key_id=dead",
      })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("privacy", err.message)
      assert.matches("protocol", err.message)
    end)

    it("rejects invalid mode value", function()
      local text = base_ipmx_sdp({
        "a=privacy: protocol=RTP; mode=DES-56-ECB; iv=0102030405060708090a0b0c0d0e0f10; key_generator=aabb; key_version=01; key_id=dead",
      })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("privacy", err.message)
      assert.matches("mode", err.message)
    end)

    it("rejects missing required parameter", function()
      local text = base_ipmx_sdp({
        "a=privacy: protocol=RTP; mode=AES-128-CTR; iv=0102030405060708090a0b0c0d0e0f10; key_generator=aabb",
      })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("privacy", err.message)
    end)

    it("rejects non-hex iv value", function()
      local text = base_ipmx_sdp({
        "a=privacy: protocol=RTP; mode=AES-128-CTR; iv=not-hex!; key_generator=aabb; key_version=01; key_id=dead",
      })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("privacy", err.message)
    end)

    it("error references TR-10-13 §13 and field_path", function()
      local text = base_ipmx_sdp({
        "a=privacy: protocol=BAD; mode=AES-128-CTR; iv=aabb; key_generator=aabb; key_version=01; key_id=dead",
      })
      local doc = sdp.parse(text)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("session", err.field_path)
      assert.matches("TR%-10%-13", err.spec_ref)
    end)
  end)

  -- ── USB blocks bypass ST 2110 (TR-10-14) ──────────────────────────────────────

  describe("USB blocks bypass ST 2110 (TR-10-14)", function()
    it("accepts SDP with USB m=application block alongside valid IPMX video", function()
      local lines = {
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX USB Session",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "m=application 5100 TCP usb",
        "c=IN IP4 192.168.1.200",
      }
      local doc = sdp.parse(table.concat(lines, "\r\n"))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("USB block with valid a=privacy (AAD mode) is accepted", function()
      local lines = {
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX USB Session",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "m=application 5100 TCP usb",
        "c=IN IP4 192.168.1.200",
        "a=privacy: protocol=RTP; mode=AES-128-CTR_CMAC-64-AAD; iv=0102030405060708090a0b0c0d0e0f10; key_generator=aabb; key_version=01; key_id=dead",
      }
      local doc = sdp.parse(table.concat(lines, "\r\n"))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("USB block with non-AAD privacy mode is rejected", function()
      local lines = {
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX USB Session",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "m=application 5100 TCP usb",
        "c=IN IP4 192.168.1.200",
        -- AES-128-CTR is valid for RTP but NOT for USB (not AAD variant)
        "a=privacy: protocol=RTP; mode=AES-128-CTR; iv=0102030405060708090a0b0c0d0e0f10; key_generator=aabb; key_version=01; key_id=dead",
      }
      local doc = sdp.parse(table.concat(lines, "\r\n"))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("privacy", err.message)
      assert.matches("mode", err.message)
    end)

    it("error for USB privacy references TR-10-14 spec_ref", function()
      local lines = {
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX USB",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "m=application 5100 TCP usb",
        "c=IN IP4 192.168.1.200",
        "a=privacy: protocol=RTP; mode=AES-256-CTR; iv=0102030405060708090a0b0c0d0e0f10; key_generator=aabb; key_version=01; key_id=dead",
      }
      local doc = sdp.parse(table.concat(lines, "\r\n"))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("TR%-10%-14", err.spec_ref)
    end)
  end)

  -- ── FEC FECPROFILE (TR-10-6 §7.6) ────────────────────────────────────────────

  describe("FEC FECPROFILE (TR-10-6 §7.6)", function()
    it("accepts FECPROFILE=profile-a in fmtp", function()
      local text = base_ipmx_sdp({}, {},
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; FECPROFILE=profile-a; IPMX")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("rejects unknown FECPROFILE value", function()
      local text = base_ipmx_sdp({}, {},
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; FECPROFILE=profile-z; IPMX")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("FECPROFILE", err.message)
      assert.matches("TR%-10%-6", err.spec_ref)
    end)

    it("accepts valid FEC_ADD_LATENCY_VIDEO with FECPROFILE", function()
      local text = base_ipmx_sdp({}, {},
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; FECPROFILE=profile-a; FEC_ADD_LATENCY_VIDEO=1000; IPMX")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("rejects non-integer FEC_ADD_LATENCY_VIDEO", function()
      local text = base_ipmx_sdp({}, {},
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; FECPROFILE=profile-a; FEC_ADD_LATENCY_VIDEO=notanumber; IPMX")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("FEC_ADD_LATENCY_VIDEO", err.message)
    end)

    it("accepts valid FEC_ADD_LATENCY_AUDIO with FECPROFILE", function()
      local text = base_ipmx_sdp({}, {},
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; FECPROFILE=profile-a; FEC_ADD_LATENCY_AUDIO=500; IPMX")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("accepts FEC_ADD_LATENCY_VIDEO=0 (zero is valid: non-negative integer)", function()
      local text = base_ipmx_sdp({}, {},
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; FECPROFILE=profile-a; FEC_ADD_LATENCY_VIDEO=0; IPMX")
      local doc, err = sdp.parse(text, "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts FEC_ADD_LATENCY_AUDIO=0 (zero is valid: non-negative integer)", function()
      local text = base_ipmx_sdp({}, {},
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; FECPROFILE=profile-a; FEC_ADD_LATENCY_AUDIO=0; IPMX")
      local doc, err = sdp.parse(text, "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  -- ── HKEP and PEP coexistence ──────────────────────────────────────────────────

  describe("HKEP and PEP coexistence", function()
    it("accepts SDP with both a=hkep and a=privacy at session level", function()
      local text = base_ipmx_sdp({
        "a=hkep:10000 IN IP4 192.168.1.100 550e8400-e29b-41d4-a716-446655440000 01-02-03-04-05",
        "a=privacy: protocol=RTP; mode=AES-128-CTR; iv=0102030405060708090a0b0c0d0e0f10; key_generator=aabb; key_version=01; key_id=dead",
      })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)
  end)

  -- ── M16: a=group:DUP grouping — IPMX-specific checks (TR-10-13 §13) ──────────

  describe("a=group:DUP grouping — IPMX (TR-10-13 §13)", function()
    local MAC  = "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF"
    local VFMTP_IPMX = "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; IPMX"
    local PRIV = "a=privacy: protocol=RTP; mode=AES-128-CTR; iv=0102030405060708090a0b0c0d0e0f10; key_generator=aabb; key_version=01; key_id=dead"

    local function dup_ipmx_sdp(opts)
      opts = opts or {}
      local privacy1 = opts.privacy1
      local privacy2 = opts.privacy2
      local extmap1  = opts.extmap1 ~= false and "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc" or nil
      local extmap2  = opts.extmap2 == true   and "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc" or nil
      local lines = {
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX DUP Test",
        "t=0 0",
        "a=group:DUP leg1 leg2",
        MAC,
        -- leg 1
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=mid:leg1",
        "a=rtpmap:96 raw/90000",
        VFMTP_IPMX,
        "a=mediaclk:direct=0",
        MAC,
      }
      if extmap1 then lines[#lines+1] = extmap1 end
      if privacy1 then lines[#lines+1] = privacy1 end
      -- leg 2
      lines[#lines+1] = "m=video 5010 RTP/AVP 96"
      lines[#lines+1] = "c=IN IP4 239.100.0.2/64"
      lines[#lines+1] = "a=mid:leg2"
      lines[#lines+1] = "a=rtpmap:96 raw/90000"
      lines[#lines+1] = VFMTP_IPMX
      lines[#lines+1] = "a=mediaclk:direct=0"
      lines[#lines+1] = MAC
      if extmap2 then lines[#lines+1] = extmap2 end
      if privacy2 then lines[#lines+1] = privacy2 end
      return table.concat(lines, "\r\n")
    end

    it("accepts DUP grouping with no privacy on either leg", function()
      local doc, err = sdp.parse(dup_ipmx_sdp(), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts DUP grouping with identical privacy on both legs", function()
      local text = dup_ipmx_sdp({ privacy1 = PRIV, privacy2 = PRIV })
      local doc, err = sdp.parse(text, "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects DUP grouping where one leg has privacy and the other does not", function()
      local text = dup_ipmx_sdp({ privacy1 = PRIV })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("privacy", err.message)
    end)

    it("rejects DUP grouping where both legs have different privacy values", function()
      local priv2 = "a=privacy: protocol=RTP; mode=AES-256-CTR; iv=0102030405060708090a0b0c0d0e0f10; key_generator=aabb; key_version=01; key_id=dead"
      local text = dup_ipmx_sdp({ privacy1 = PRIV, privacy2 = priv2 })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("privacy", err.message)
    end)

    it("satisfies extmap requirement when only one leg carries a=extmap", function()
      -- extmap on leg 1 only; leg 2 has none — should still pass
      local text = dup_ipmx_sdp({ extmap1 = true, extmap2 = false })
      local doc, err = sdp.parse(text, "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("spec_ref for DUP privacy mismatch is TR-10-13 §13", function()
      local text = dup_ipmx_sdp({ privacy1 = PRIV })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.equal("TR-10-13 §13", err.spec_ref)
    end)

    it("rejects a=group:DUP with only one leg", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX DUP Test",
        "t=0 0",
        "a=group:DUP leg1",
        MAC,
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=mid:leg1",
        "a=rtpmap:96 raw/90000",
        VFMTP_IPMX,
        "a=mediaclk:direct=0",
        MAC,
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
      }, "\r\n")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("DUP", err.message)
    end)
  end)

  -- ── M17: RTCP port convention (TR-10-1 §8.7) — IPMX only ────────────────────

  describe("RTCP port convention (TR-10-1 §8.7)", function()
    it("accepts SDP with no a=rtcp attributes (implicit port+1 is not required to be stated)", function()
      local doc, err = sdp.parse(IPMX_VIDEO_SDP, "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts a=rtcp:<port> when port equals media port+1", function()
      local text = base_ipmx_sdp({}, { "a=rtcp:5001" })
      local doc, err = sdp.parse(text, "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects a=rtcp:<port> when port does not equal media port+1", function()
      local text = base_ipmx_sdp({}, { "a=rtcp:9999" })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("rtcp", err.message)
      assert.matches("port", err.message)
    end)

    it("rejects a=rtcp-mux on a media block", function()
      local text = base_ipmx_sdp({}, { "a=rtcp-mux" })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("rtcp%-mux", err.message)
    end)

    it("spec_ref for rtcp-mux rejection is TR-10-1 §8.7", function()
      local text = base_ipmx_sdp({}, { "a=rtcp-mux" })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.equal("TR-10-1 §8.7", err.spec_ref)
    end)

    it("ST 2110 mode accepts a=rtcp-mux (no restriction at ST 2110 level)", function()
      -- Build a valid ST 2110 SDP with rtcp-mux — should pass at st2110 tier
      local lines = {
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
        "a=rtcp-mux",
      }
      local doc, err = sdp.parse(table.concat(lines, "\r\n"), "st2110")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  -- ── a=privacy protocol=RTP_KV (TR-10-13 §13) ─────────────────────────────────

  describe("a=privacy protocol=RTP_KV", function()
    it("accepts protocol=RTP_KV", function()
      local text = base_ipmx_sdp({
        "a=privacy: protocol=RTP_KV; mode=AES-128-CTR; iv=0102030405060708090a0b0c0d0e0f10; key_generator=aabb; key_version=01; key_id=dead",
      })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)
  end)

  -- ── a=privacy non-hex fields (TR-10-13 §13) ───────────────────────────────────

  describe("a=privacy non-hex field rejection (TR-10-13 §13)", function()
    local function privacy_with(overrides)
      local fields = {
        protocol      = overrides.protocol      or "RTP",
        mode          = overrides.mode          or "AES-128-CTR",
        iv            = overrides.iv            or "0102030405060708090a0b0c0d0e0f10",
        key_generator = overrides.key_generator or "aabb",
        key_version   = overrides.key_version   or "01",
        key_id        = overrides.key_id        or "dead",
      }
      local val = string.format(
        "a=privacy: protocol=%s; mode=%s; iv=%s; key_generator=%s; key_version=%s; key_id=%s",
        fields.protocol, fields.mode, fields.iv,
        fields.key_generator, fields.key_version, fields.key_id)
      return base_ipmx_sdp({ val })
    end

    it("rejects non-hex key_generator", function()
      local doc = sdp.parse(privacy_with({ key_generator = "not-hex!" }))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("key_generator", err.message)
    end)

    it("rejects non-hex key_version", function()
      local doc = sdp.parse(privacy_with({ key_version = "zz" }))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("key_version", err.message)
    end)

    it("rejects non-hex key_id", function()
      local doc = sdp.parse(privacy_with({ key_id = "xyz!" }))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("key_id", err.message)
    end)

    it("rejects empty iv value", function()
      local doc = sdp.parse(privacy_with({ iv = "" }))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("iv", err.message)
    end)
  end)

  -- ── FEC_ADD_LATENCY_AUDIO invalid value ───────────────────────────────────────

  describe("FEC_ADD_LATENCY_AUDIO invalid value (TR-10-6 §7.6)", function()
    it("rejects non-integer FEC_ADD_LATENCY_AUDIO", function()
      local text = base_ipmx_sdp({}, {},
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; FECPROFILE=profile-a; FEC_ADD_LATENCY_AUDIO=notanumber; IPMX")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("FEC_ADD_LATENCY_AUDIO", err.message)
      assert.matches("TR%-10%-6", err.spec_ref)
    end)
  end)

  -- ── FEC_ADD_LATENCY_* without FECPROFILE ──────────────────────────────────────

  describe("FEC_ADD_LATENCY requires FECPROFILE (TR-10-6 §7.6)", function()
    it("rejects FEC_ADD_LATENCY_VIDEO without FECPROFILE", function()
      local text = base_ipmx_sdp({}, {},
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; FEC_ADD_LATENCY_VIDEO=1000; IPMX")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("FEC_ADD_LATENCY_VIDEO", err.message)
      assert.matches("FECPROFILE", err.message)
      assert.matches("TR%-10%-6", err.spec_ref)
    end)

    it("rejects FEC_ADD_LATENCY_AUDIO without FECPROFILE", function()
      local text = base_ipmx_sdp({}, {},
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; FEC_ADD_LATENCY_AUDIO=500; IPMX")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("FEC_ADD_LATENCY_AUDIO", err.message)
      assert.matches("FECPROFILE", err.message)
    end)

    it("accepts FEC_ADD_LATENCY_VIDEO alongside FECPROFILE=profile-a", function()
      local text = base_ipmx_sdp({}, {},
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; FECPROFILE=profile-a; FEC_ADD_LATENCY_VIDEO=1000; IPMX")
      local doc, err = sdp.parse(text, "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  -- ── m= protocol field validation (IPMX inherits ST 2110-10 §8.1) ─────────────

  describe("m= protocol field validation (IPMX)", function()
    local function ipmx_with_proto(proto)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX Video",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=video 5000 " .. proto .. " 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
      }, "\r\n")
    end

    it("rejects non-RTP/AVP protocol on RTP media block", function()
      local doc = sdp.parse(ipmx_with_proto("RTP/SAVPF"))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("proto", err.message)
    end)

    it("USB block with TCP protocol is exempt from RTP/AVP check", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX USB",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "m=application 9 TCP/MSRP *",
        "c=IN IP4 192.168.1.1",
      }, "\r\n")
      local doc, err = sdp.parse(text, "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  -- ── a=extmap URI format validation (RFC 5285) ─────────────────────────────

  describe("a=extmap URI format validation (RFC 5285)", function()
    local function ipmx_with_session_extmap(extmap_value)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX Video",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=extmap:" .. extmap_value,
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
      }, "\r\n")
    end

    it("accepts standard urn: URI", function()
      local doc, err = sdp.parse(
        ipmx_with_session_extmap("1 urn:ietf:params:rtp-hdrext:smpte-tc"), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts extmap with direction qualifier", function()
      local doc, err = sdp.parse(
        ipmx_with_session_extmap("1/sendonly urn:ietf:params:rtp-hdrext:smpte-tc"), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts IPMX vendor urn:x-ipmx: URI", function()
      local doc, err = sdp.parse(
        ipmx_with_session_extmap("2 urn:x-ipmx:signal-id"), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects extmap with no URI scheme", function()
      local doc = sdp.parse(ipmx_with_session_extmap("1 not-a-uri"))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("extmap", err.message)
    end)

    it("rejects extmap with invalid direction", function()
      local doc = sdp.parse(
        ipmx_with_session_extmap("1/baddir urn:ietf:params:rtp-hdrext:smpte-tc"))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("extmap", err.message)
    end)

    it("rejects extmap with ID only and no URI", function()
      local doc = sdp.parse(ipmx_with_session_extmap("1"))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("extmap", err.message)
    end)

    it("error field_path identifies session.attributes[extmap]", function()
      local doc = sdp.parse(ipmx_with_session_extmap("1 not-a-uri"))
      assert.is_table(doc)
      local _, err = doc:validate("ipmx")
      assert.matches("extmap", err.field_path)
    end)

    it("rejects bad extmap at media block level", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX Video",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=extmap:2 bad-value-no-scheme",
      }, "\r\n")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("extmap", err.message)
      assert.matches("media%[1%]", err.field_path)
    end)
  end)
end)
