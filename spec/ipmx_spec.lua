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
    "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
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
    "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200",
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
      "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX"
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200")
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200")
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

    -- M25 M11: TR-10-5 §10 specifies a=hkep as a session attribute only.
    -- Media-level a=hkep is rejected; see "M25 M11" describe block below for
    -- the new placement tests.
  end)

  -- ── a=privacy validation (TR-10-13 §13) ──────────────────────────────────────

  describe("a=privacy validation (TR-10-13 §13)", function()
    local VALID_PRIVACY =
      "a=privacy: protocol=RTP; mode=AES-128-CTR; iv=0102030405060708; key_generator=aabbccddeeff00112233445566778899; key_version=01020304; key_id=deadbeefcafebabe"

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
          "; iv=0102030405060708; key_generator=aabbccddeeff00112233445566778899; key_version=01020304; key_id=deadbeefcafebabe"
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
        "a=privacy: protocol=UDP; mode=AES-128-CTR; iv=0102030405060708; key_generator=aabbccddeeff00112233445566778899; key_version=01020304; key_id=deadbeefcafebabe",
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
        "a=privacy: protocol=RTP; mode=DES-56-ECB; iv=0102030405060708; key_generator=aabbccddeeff00112233445566778899; key_version=01020304; key_id=deadbeefcafebabe",
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "m=application 5100 TCP usb",
        "c=IN IP4 192.168.1.200",
        "a=setup:passive",
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "m=application 5100 TCP usb",
        "c=IN IP4 192.168.1.200",
        "a=setup:passive",
        "a=privacy: protocol=USB_KV; mode=AES-128-CTR_CMAC-64-AAD; iv=0102030405060708; key_generator=aabbccddeeff00112233445566778899; key_version=01020304; key_id=deadbeefcafebabe",
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "m=application 5100 TCP usb",
        "c=IN IP4 192.168.1.200",
        "a=setup:passive",
        -- AES-128-CTR is valid for RTP but NOT for USB (USB requires AAD variants)
        "a=privacy: protocol=USB_KV; mode=AES-128-CTR; iv=0102030405060708; key_generator=aabbccddeeff00112233445566778899; key_version=01020304; key_id=deadbeefcafebabe",
      }
      local doc = sdp.parse(table.concat(lines, "\r\n"))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("privacy", err.message)
      assert.matches("mode", err.message)
    end)

    -- TR-10-14 §14: "The SDP shall follow RFC 4145 with the following
    -- restrictions" — only m=, c=, a=privacy, a=setup are defined for USB
    -- blocks. RTP-specific attributes (rtpmap, fmtp, mediaclk, ts-refclk)
    -- have no meaning on a TCP transport and are rejected in strict mode.
    local function usb_sdp_with(extra_usb_attr)
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "m=application 5100 TCP usb",
        "c=IN IP4 192.168.1.200",
        "a=setup:passive",
      }
      lines[#lines + 1] = extra_usb_attr
      return table.concat(lines, "\r\n")
    end

    it("rejects a=rtpmap on a USB block", function()
      local doc = sdp.parse(usb_sdp_with("a=rtpmap:97 raw/90000"))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("rtpmap", err.message)
      assert.matches("USB", err.message)
      assert.matches("TR%-10%-14", err.spec_ref)
    end)

    it("rejects a=fmtp on a USB block", function()
      local doc = sdp.parse(usb_sdp_with("a=fmtp:97 anything"))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("fmtp", err.message)
      assert.matches("USB", err.message)
    end)

    it("rejects a=mediaclk on a USB block", function()
      local doc = sdp.parse(usb_sdp_with("a=mediaclk:direct=0"))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("mediaclk", err.message)
      assert.matches("USB", err.message)
    end)

    it("rejects media-level a=ts-refclk on a USB block", function()
      local doc = sdp.parse(usb_sdp_with(
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("ts%-refclk", err.message)
      assert.matches("USB", err.message)
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "m=application 5100 TCP usb",
        "c=IN IP4 192.168.1.200",
        "a=setup:passive",
        "a=privacy: protocol=USB_KV; mode=AES-256-CTR; iv=0102030405060708; key_generator=aabbccddeeff00112233445566778899; key_version=01020304; key_id=deadbeefcafebabe",
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; FECPROFILE=profile-a; IPMX")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("rejects unknown FECPROFILE value", function()
      local text = base_ipmx_sdp({}, {},
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; FECPROFILE=profile-z; IPMX")
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; FECPROFILE=profile-a; FEC_ADD_LATENCY_VIDEO=1000; IPMX")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("rejects non-integer FEC_ADD_LATENCY_VIDEO", function()
      local text = base_ipmx_sdp({}, {},
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; FECPROFILE=profile-a; FEC_ADD_LATENCY_VIDEO=notanumber; IPMX")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("FEC_ADD_LATENCY_VIDEO", err.message)
    end)

    it("accepts valid FEC_ADD_LATENCY_AUDIO with FECPROFILE", function()
      local text = base_ipmx_sdp({}, {},
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; FECPROFILE=profile-a; FEC_ADD_LATENCY_AUDIO=500; IPMX")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("accepts FEC_ADD_LATENCY_VIDEO=0 (zero is valid: non-negative integer)", function()
      local text = base_ipmx_sdp({}, {},
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; FECPROFILE=profile-a; FEC_ADD_LATENCY_VIDEO=0; IPMX")
      local doc, err = sdp.parse(text, "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts FEC_ADD_LATENCY_AUDIO=0 (zero is valid: non-negative integer)", function()
      local text = base_ipmx_sdp({}, {},
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; FECPROFILE=profile-a; FEC_ADD_LATENCY_AUDIO=0; IPMX")
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
        "a=privacy: protocol=RTP; mode=AES-128-CTR; iv=0102030405060708; key_generator=aabbccddeeff00112233445566778899; key_version=01020304; key_id=deadbeefcafebabe",
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
    local VFMTP_IPMX = "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX"
    local PRIV = "a=privacy: protocol=RTP; mode=AES-128-CTR; iv=0102030405060708; key_generator=aabbccddeeff00112233445566778899; key_version=01020304; key_id=deadbeefcafebabe"

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
      local priv2 = "a=privacy: protocol=RTP; mode=AES-256-CTR; iv=0102030405060708; key_generator=aabbccddeeff00112233445566778899; key_version=01020304; key_id=deadbeefcafebabe"
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

    -- RFC 3605 §2.1 grammar:
    --   rtcp-attribute = "rtcp:" port [SP nettype SP addrtype SP connection-address]
    -- The full optional triple, if present, must be well-formed.
    it("accepts a=rtcp:<port> IN IP4 <addr> (full RFC 3605 form)", function()
      local text = base_ipmx_sdp({}, { "a=rtcp:5001 IN IP4 239.100.0.1/64" })
      local doc, err = sdp.parse(text, "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects a=rtcp with malformed trailing content (e.g. slash form)", function()
      local text = base_ipmx_sdp({}, { "a=rtcp:5001/239.100.0.1" })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("rtcp", err.message)
    end)

    it("rejects a=rtcp:<port> IN IPX <addr> (bad addrtype)", function()
      local text = base_ipmx_sdp({}, { "a=rtcp:5001 IN IPX 239.100.0.1" })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("rtcp", err.message)
    end)

    it("rejects a=rtcp:<port> IN IP4 (missing address)", function()
      local text = base_ipmx_sdp({}, { "a=rtcp:5001 IN IP4" })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("rtcp", err.message)
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200",
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
        "a=privacy: protocol=RTP_KV; mode=AES-128-CTR; iv=0102030405060708; key_generator=aabbccddeeff00112233445566778899; key_version=01020304; key_id=deadbeefcafebabe",
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
        -- Default hex lengths match TR-10-13 §13: iv 16h, key_generator 32h,
        -- key_version 8h, key_id 16h. Tests override one field at a time.
        iv            = overrides.iv            or "0102030405060708",
        key_generator = overrides.key_generator or "aabbccddeeff00112233445566778899",
        key_version   = overrides.key_version   or "01020304",
        key_id        = overrides.key_id        or "deadbeefcafebabe",
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; FECPROFILE=profile-a; FEC_ADD_LATENCY_AUDIO=notanumber; IPMX")
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; FEC_ADD_LATENCY_VIDEO=1000; IPMX")
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; FEC_ADD_LATENCY_AUDIO=500; IPMX")
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; FECPROFILE=profile-a; FEC_ADD_LATENCY_VIDEO=1000; IPMX")
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
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

    -- RFC 5285 §7 ABNF: extensionattributes = byte-string. RFC 4566 §9 defines
    -- byte-string = 1*(%x01-09/%x0B-0C/%x0E-FF) — NUL, CR, LF are forbidden.
    it("rejects extmap ext-attr containing a NUL byte", function()
      local doc = sdp.parse(
        ipmx_with_session_extmap("1 urn:ietf:params:rtp-hdrext:smpte-tc bad\0attr"))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("extmap", err.message)
    end)

    it("accepts extmap with a printable ext-attr token (byte-string)", function()
      local doc, err = sdp.parse(
        ipmx_with_session_extmap("1 urn:ietf:params:rtp-hdrext:smpte-tc opt=val"),
        "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
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

  -- ── M22: media port range (TR-10-1 §7) ───────────────────────────────────────

  describe("media port range (TR-10-1 §7)", function()
    local function ipmx_with_port(port)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX Video",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=video " .. port .. " RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
      }, "\r\n")
    end

    it("accepts even port > 1024", function()
      local doc, err = sdp.parse(ipmx_with_port(5000), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects odd port", function()
      local doc = sdp.parse(ipmx_with_port(5001))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("even", err.message)
    end)

    it("rejects port <= 1024 (exactly 1024)", function()
      local doc = sdp.parse(ipmx_with_port(1024))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("1024", err.message)
    end)

    it("rejects port <= 1024 (port 80)", function()
      local doc = sdp.parse(ipmx_with_port(80))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("1024", err.message)
    end)

    it("spec_ref is TR-10-1 §7", function()
      local doc = sdp.parse(ipmx_with_port(5001))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.equal("TR-10-1 §7", err.spec_ref)
    end)

    it("USB block port is exempt from even/range check", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX Mix",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
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

  -- ── M22 / M25: IPMX audio — ptime required; AM824 accepted (TR-10-12) ────────

  describe("IPMX audio — ptime required and AM824 accepted (TR-10-3 §8 / TR-10-12)", function()
    local function ipmx_audio_sdp(overrides)
      local o = overrides or {}
      local rtpmap  = o.rtpmap  or "a=rtpmap:97 L24/48000/8"
      local fmtp    = o.fmtp    or "a=fmtp:97 channel-order=SMPTE2110.(ST); measuredsamplerate=48000; IPMX"
      local ptime   = o.ptime   -- nil = omit, string = include
      local lines = {
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX Audio",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=audio 5010 RTP/AVP 97",
        "c=IN IP4 239.100.0.2/64",
        rtpmap,
        fmtp,
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
      }
      if ptime then lines[#lines + 1] = ptime end
      return table.concat(lines, "\r\n")
    end

    it("accepts L24 audio with ptime", function()
      local doc, err = sdp.parse(ipmx_audio_sdp({ ptime = "a=ptime:1" }), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts L16 audio with ptime", function()
      local text = ipmx_audio_sdp({
        rtpmap = "a=rtpmap:97 L16/48000/2",
        fmtp   = "a=fmtp:97 channel-order=SMPTE2110.(ST); measuredsamplerate=48000; IPMX",
        ptime  = "a=ptime:1",
      })
      local doc, err = sdp.parse(text, "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects audio with no a=ptime", function()
      local doc = sdp.parse(ipmx_audio_sdp())
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("ptime", err.message)
    end)

    it("accepts AM824 encoding (TR-10-12 AES3 transparent transport)", function()
      local doc, err = sdp.parse(ipmx_audio_sdp({
        rtpmap = "a=rtpmap:97 AM824/48000/2",
        fmtp   = "a=fmtp:97 channel-order=SMPTE2110.(ST); measuredsamplerate=48000; IPMX",
        ptime  = "a=ptime:1",
      }), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("spec_ref for ptime is TR-10-3 §8", function()
      local doc = sdp.parse(ipmx_audio_sdp())
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.equal("TR-10-3 §8", err.spec_ref)
    end)

    -- IPMX permits the full AES67/extended professional-audio rate set. ST 2110-30
    -- §6.1 puts 32/88.2/176.4/192 kHz "out of scope" for that standard alone, but
    -- IPMX (which inherits ST 2110 baseline) does not restrict them. These tests
    -- guard against accidental tightening that would break legitimate IPMX SDPs.
    local extended_rates = { 32000, 88200, 176400, 192000 }
    for _, rate in ipairs(extended_rates) do
      it("accepts " .. rate .. " Hz (extended pro-audio rate)", function()
        local rtpmap = "a=rtpmap:97 L24/" .. rate .. "/2"
        local fmtp   = "a=fmtp:97 channel-order=SMPTE2110.(ST); measuredsamplerate="
                       .. rate .. "; IPMX"
        local doc, err = sdp.parse(ipmx_audio_sdp({
          rtpmap = rtpmap, fmtp = fmtp, ptime = "a=ptime:1",
        }), "ipmx")
        assert.is_nil(err)
        assert.is_table(doc)
      end)
    end

    -- IPMX permits mono (channel-order group "M") for PCM audio. ST 2110-30
    -- §6.2.2 Table 1 includes M as a valid named group; IPMX inherits this.
    -- Regression guard against accidental mono exclusion.
    it("accepts mono PCM audio (channel-order=SMPTE2110.(M))", function()
      local doc, err = sdp.parse(ipmx_audio_sdp({
        rtpmap = "a=rtpmap:97 L24/48000/1",
        fmtp   = "a=fmtp:97 channel-order=SMPTE2110.(M); measuredsamplerate=48000; IPMX",
        ptime  = "a=ptime:1",
      }), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  -- ── M22: IPMX baseband fmtp params (TR-10-2 §11, TR-10-3 §10.3) ─────────────

  describe("IPMX baseband fmtp params (TR-10-2 §11 / TR-10-3 §10.3)", function()
    local function video_with_extra_fmtp(extra)
      local fmtp = "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX; " .. extra
      return base_ipmx_sdp({}, {}, fmtp)
    end

    local function audio_with_extra_fmtp(extra)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX Audio",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=audio 5010 RTP/AVP 97",
        "c=IN IP4 239.100.0.2/64",
        "a=rtpmap:97 L24/48000/8",
        "a=fmtp:97 channel-order=SMPTE2110.(ST); measuredsamplerate=48000; IPMX; " .. extra,
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=ptime:1",
      }, "\r\n")
    end

    it("accepts video with valid measuredpixclk", function()
      local doc, err = sdp.parse(video_with_extra_fmtp("measuredpixclk=148500000"), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts video with valid vtotal and htotal", function()
      local doc, err = sdp.parse(video_with_extra_fmtp("vtotal=1125; htotal=2200"), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects video measuredpixclk=0 (not positive)", function()
      local doc = sdp.parse(video_with_extra_fmtp("measuredpixclk=0"))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("measuredpixclk", err.message)
    end)

    it("rejects video vtotal with non-integer value", function()
      local doc = sdp.parse(video_with_extra_fmtp("vtotal=1125.5"))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("vtotal", err.message)
    end)

    it("rejects video htotal with negative value", function()
      local doc = sdp.parse(video_with_extra_fmtp("htotal=-1"))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("htotal", err.message)
    end)

    it("accepts audio with valid measuredsamplerate", function()
      local doc, err = sdp.parse(audio_with_extra_fmtp("measuredsamplerate=48001"), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects audio measuredsamplerate=0 (not positive)", function()
      local doc = sdp.parse(audio_with_extra_fmtp("measuredsamplerate=0"))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("measuredsamplerate", err.message)
    end)

    it("spec_ref for video baseband params is TR-10-1 §10.2 (M25)", function()
      local doc = sdp.parse(video_with_extra_fmtp("measuredpixclk=0"))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("TR%-10%-1", err.spec_ref)
    end)

    it("spec_ref for audio baseband params is TR-10-1 §10.3 (M25)", function()
      local doc = sdp.parse(audio_with_extra_fmtp("measuredsamplerate=0"))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("TR%-10%-1", err.spec_ref)
    end)
  end)

  -- ── M23: a=group:FID forbidden at IPMX tier (TR-10-1 §10) ────────────────────

  describe("a=group:FID rejection (TR-10-1 §10)", function()
    it("rejects IPMX SDP with a=group:FID at session level", function()
      local text = base_ipmx_sdp({ "a=group:FID 1 2" })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("FID", err.message)
      assert.equal("TR-10-1 §10", err.spec_ref)
    end)

    it("still accepts IPMX SDP with a=group:DUP (not FID)", function()
      local text = base_ipmx_sdp({ "a=group:DUP 1 2", "a=mid:1" }, { "a=mid:1" })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      -- DUP validation may fail on mid resolution, but FID is not the reason
      if not ok then
        assert.not_matches("FID", err.message)
      end
    end)

    it("accepts ST 2110 SDP with a=group:FID (rule is IPMX-only)", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=ST2110 Video",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "a=group:FID 1 2",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022",
        "a=mediaclk:direct=0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      }, "\r\n")
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("st2110")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)
  end)

  -- ── M23: extmap ID uniqueness per RFC 5285 §3 ─────────────────────────────────

  describe("a=extmap ID uniqueness (RFC 5285 §3)", function()
    it("rejects duplicate extmap ID at session level", function()
      local text = base_ipmx_sdp({
        "a=extmap:1 urn:ietf:params:rtp-hdrext:ntp-64",
      })
      -- base_ipmx_sdp already adds a=extmap:1 at session level, so we'd have two :1
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("duplicate", err.message)
      assert.equal("RFC 5285 §3", err.spec_ref)
    end)

    it("accepts same extmap ID at session level and media level (different scopes)", function()
      -- extmap:1 at session scope + extmap:1 at media scope is allowed by RFC 5285
      local text = base_ipmx_sdp({}, { "a=extmap:1 urn:ietf:params:rtp-hdrext:ntp-64" })
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)
  end)

  -- ── M23: IPMX audio ptime edge cases ──────────────────────────────────────────

  describe("IPMX audio ptime edge cases (M23)", function()
    local function ipmx_audio_sdp_ptime(ptime_line)
      local lines = {
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX Audio",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=audio 5010 RTP/AVP 97",
        "c=IN IP4 239.100.0.2/64",
        "a=rtpmap:97 L24/48000/8",
        "a=fmtp:97 channel-order=SMPTE2110.(ST); measuredsamplerate=48000; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
      }
      if ptime_line then lines[#lines + 1] = ptime_line end
      return table.concat(lines, "\r\n")
    end

    it("rejects a=ptime:0 (non-positive value rejected at ST 2110 tier)", function()
      local doc = sdp.parse(ipmx_audio_sdp_ptime("a=ptime:0"))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("ptime", err.message)
    end)

    it("rejects a=ptime:-1 (negative value rejected at ST 2110 tier)", function()
      local doc = sdp.parse(ipmx_audio_sdp_ptime("a=ptime:-1"))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("ptime", err.message)
    end)
  end)

  -- ── M24: H2 — USB privacy protocol must be USB_KV (TR-10-14 §14) ─────────────

  describe("USB privacy protocol", function()
    -- Build an IPMX SDP with an RTP video block plus a USB application block;
    -- caller supplies the privacy line and the a=setup line for the USB block.
    local function with_usb(privacy_line, setup_line)
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "m=application 5100 TCP usb",
        "c=IN IP4 192.168.1.200",
        setup_line or "a=setup:passive",
      }
      if privacy_line then lines[#lines + 1] = privacy_line end
      return table.concat(lines, "\r\n")
    end
    local USB_AAD = "AES-128-CTR_CMAC-64-AAD"
    local HEX = "iv=0102030405060708; key_generator=aabbccddeeff00112233445566778899; key_version=01020304; key_id=deadbeefcafebabe"

    it("accepts USB block with protocol=USB_KV and AAD mode", function()
      local text = with_usb("a=privacy: protocol=USB_KV; mode=" .. USB_AAD .. "; " .. HEX)
      local doc = sdp.parse(text)
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("rejects USB block with protocol=RTP", function()
      local text = with_usb("a=privacy: protocol=RTP; mode=" .. USB_AAD .. "; " .. HEX)
      local doc = sdp.parse(text)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("protocol", err.message)
    end)

    it("rejects USB block with protocol=RTP_KV", function()
      local text = with_usb("a=privacy: protocol=RTP_KV; mode=" .. USB_AAD .. "; " .. HEX)
      local doc = sdp.parse(text)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("protocol", err.message)
    end)
  end)

  -- ── M24: H3 — USB blocks require a=setup:passive (TR-10-14 §14) ──────────────

  describe("USB a=setup:passive requirement", function()
    local function with_usb_setup(setup_line)
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "m=application 5100 TCP usb",
        "c=IN IP4 192.168.1.200",
      }
      if setup_line then lines[#lines + 1] = setup_line end
      return table.concat(lines, "\r\n")
    end

    it("accepts USB block with a=setup:passive", function()
      local doc, err = sdp.parse(with_usb_setup("a=setup:passive"), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects USB block missing a=setup", function()
      local doc = sdp.parse(with_usb_setup(nil))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("setup", err.message)
    end)

    it("rejects a=setup:active on USB", function()
      local doc = sdp.parse(with_usb_setup("a=setup:active"))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("setup", err.message)
    end)

    it("rejects a=setup:actpass on USB", function()
      local doc = sdp.parse(with_usb_setup("a=setup:actpass"))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("setup", err.message)
    end)
  end)

  -- ── M24: H4 — privacy hex digit counts (TR-10-13 §13) ────────────────────────

  describe("a=privacy exact hex digit counts", function()
    local function privacy_with(overrides)
      local f = {
        protocol      = overrides.protocol      or "RTP",
        mode          = overrides.mode          or "AES-128-CTR",
        iv            = overrides.iv            or "0102030405060708",                     -- 16h (64-bit)
        key_generator = overrides.key_generator or "aabbccddeeff00112233445566778899",     -- 32h (128-bit)
        key_version   = overrides.key_version   or "01020304",                             -- 8h  (32-bit)
        key_id        = overrides.key_id        or "deadbeefcafebabe",                     -- 16h (64-bit)
      }
      local val = string.format(
        "a=privacy: protocol=%s; mode=%s; iv=%s; key_generator=%s; key_version=%s; key_id=%s",
        f.protocol, f.mode, f.iv, f.key_generator, f.key_version, f.key_id)
      return base_ipmx_sdp({ val })
    end

    -- The "valid lengths accepted" case is already covered by every accept test
    -- in earlier describe blocks (they all use these exact defaults).

    -- iv (64-bit → 16 hex)
    it("rejects iv with 15 hex digits", function()
      local doc = sdp.parse(privacy_with({ iv = "010203040506070" }))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok); assert.matches("iv", err.message)
    end)
    it("rejects iv with 17 hex digits", function()
      local doc = sdp.parse(privacy_with({ iv = "01020304050607080" }))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok); assert.matches("iv", err.message)
    end)

    -- key_generator (128-bit → 32 hex)
    it("rejects key_generator with 31 hex digits", function()
      local doc = sdp.parse(privacy_with({ key_generator = string.rep("a", 31) }))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok); assert.matches("key_generator", err.message)
    end)
    it("rejects key_generator with 33 hex digits", function()
      local doc = sdp.parse(privacy_with({ key_generator = string.rep("a", 33) }))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok); assert.matches("key_generator", err.message)
    end)

    -- key_version (32-bit → 8 hex)
    it("rejects key_version with 7 hex digits", function()
      local doc = sdp.parse(privacy_with({ key_version = "0102030" }))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok); assert.matches("key_version", err.message)
    end)
    it("rejects key_version with 9 hex digits", function()
      local doc = sdp.parse(privacy_with({ key_version = "010203040" }))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok); assert.matches("key_version", err.message)
    end)

    -- key_id (64-bit → 16 hex)
    it("rejects key_id with 15 hex digits", function()
      local doc = sdp.parse(privacy_with({ key_id = "deadbeefcafebab" }))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok); assert.matches("key_id", err.message)
    end)
    it("rejects key_id with 17 hex digits", function()
      local doc = sdp.parse(privacy_with({ key_id = "deadbeefcafebabe0" }))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok); assert.matches("key_id", err.message)
    end)
  end)

  -- ── M24: M1 — b=AS format check (TR-10-7 §11) ────────────────────────────────

  describe("b=AS bandwidth format", function()
    -- Inline SDP so b= lands in the correct RFC 4566 order (between c= and a=).
    local function ipmx_video_with_bandwidth(b_line)
      local lines = {
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX Video",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
      }
      if b_line then lines[#lines + 1] = b_line end
      lines[#lines + 1] = "a=rtpmap:96 raw/90000"
      lines[#lines + 1] = "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX"
      lines[#lines + 1] = "a=mediaclk:direct=0"
      lines[#lines + 1] = "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF"
      return table.concat(lines, "\r\n")
    end

    it("accepts b=AS:<positive integer>", function()
      local doc, err = sdp.parse(ipmx_video_with_bandwidth("b=AS:5000"), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects b=AS:0 (must be positive)", function()
      local doc = sdp.parse(ipmx_video_with_bandwidth("b=AS:0"))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("b=AS", err.message)
    end)

    it("absent b=AS is accepted (optional today)", function()
      local doc, err = sdp.parse(ipmx_video_with_bandwidth(nil), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  -- ── M24: M2 — a=infoframe attribute (TR-10-10 §8) ────────────────────────────

  describe("a=infoframe format (TR-10-10 §8)", function()
    it("accepts a=infoframe:<port> SSN=ST2110-41:2024;DIT=100100", function()
      local doc, err = sdp.parse(
        base_ipmx_sdp({ "a=infoframe:5003 SSN=ST2110-41:2024;DIT=100100" }), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects a=infoframe with wrong SSN prefix", function()
      local doc = sdp.parse(
        base_ipmx_sdp({ "a=infoframe:5003 SSN=ST2110-20:2022;DIT=100100" }))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("infoframe", err.message)
    end)

    it("rejects a=infoframe with non-HDMI DIT", function()
      local doc = sdp.parse(
        base_ipmx_sdp({ "a=infoframe:5003 SSN=ST2110-41:2024;DIT=999999" }))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("DIT", err.message)
    end)

    it("rejects a=infoframe with non-numeric port", function()
      local doc = sdp.parse(
        base_ipmx_sdp({ "a=infoframe:notaport SSN=ST2110-41:2024;DIT=100100" }))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
    end)

    it("absent a=infoframe is accepted (optional)", function()
      local doc, err = sdp.parse(base_ipmx_sdp(), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  -- ── M25 ───────────────────────────────────────────────────────────────────────
  -- Validation gap closure round 4. See PLAN.md M25 for the full list and spec
  -- references. Each describe block names the gap ID(s) it addresses.

  describe("M25 C2: a=privacy trailing semicolon rejected (TR-10-13 §13)", function()
    local HEX = "iv=0102030405060708; key_generator=aabbccddeeff00112233445566778899; key_version=01020304; key_id=deadbeefcafebabe"
    local VALID = "a=privacy: protocol=RTP; mode=AES-128-CTR; " .. HEX

    it("accepts a=privacy without trailing semicolon", function()
      local doc, err = sdp.parse(base_ipmx_sdp({ VALID }), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects a=privacy with trailing semicolon", function()
      local doc = sdp.parse(base_ipmx_sdp({ VALID .. ";" }))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("semicolon", err.message)
      assert.equal("TR-10-13 §13", err.spec_ref)
    end)

    it("rejects a=privacy with trailing semicolon-and-space", function()
      local doc = sdp.parse(base_ipmx_sdp({ VALID .. "; " }))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("semicolon", err.message)
    end)
  end)

  describe("M25 H7: RFC 4145 a=setup / a=connection enums", function()
    local function with_usb_attrs(usb_setup, usb_connection)
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "m=application 5100 TCP usb",
        "c=IN IP4 192.168.1.200",
        "a=setup:" .. usb_setup,
      }
      if usb_connection then lines[#lines+1] = "a=connection:" .. usb_connection end
      return table.concat(lines, "\r\n")
    end

    it("accepts a=setup:passive on USB block (already required)", function()
      local doc, err = sdp.parse(with_usb_attrs("passive"), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects a=setup:garbage on USB block (RFC 4145 enum)", function()
      local doc = sdp.parse(with_usb_attrs("garbage"))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("setup", err.message)
    end)

    it("rejects a=setup:active on USB block (TR-10-14 still requires passive)", function()
      -- This already fails today via the TR-10-14 passive check. We just want
      -- to make sure the new enum check doesn't accidentally over-tolerate.
      local doc = sdp.parse(with_usb_attrs("active"))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
    end)

    it("accepts a=connection:new on USB block", function()
      local doc, err = sdp.parse(with_usb_attrs("passive", "new"), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts a=connection:existing on USB block", function()
      local doc, err = sdp.parse(with_usb_attrs("passive", "existing"), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects a=connection:bogus (RFC 4145 enum)", function()
      local doc = sdp.parse(with_usb_attrs("passive", "bogus"))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("connection", err.message)
    end)
  end)

  describe("M25 H5: IPMX baseband fmtp params required (TR-10-1 §10.2/§10.3)", function()
    -- Build an IPMX video SDP whose fmtp omits one of {measuredpixclk, vtotal, htotal}.
    local function video_missing(missing_key)
      local parts = {
        "sampling=YCbCr-4:2:2", "width=1920", "height=1080",
        "exactframerate=25", "depth=10", "TCS=SDR", "colorimetry=BT709",
        "PM=2110GPM", "SSN=ST2110-20:2022", "TP=2110TPN",
        "measuredpixclk=148500000", "vtotal=1125", "htotal=2200", "IPMX",
      }
      local kept = {}
      for _, p in ipairs(parts) do
        local k = p:match("^([^=]+)")
        if k ~= missing_key then kept[#kept+1] = p end
      end
      return base_ipmx_sdp({}, {}, "a=fmtp:96 " .. table.concat(kept, "; "))
    end

    it("rejects IPMX video fmtp missing measuredpixclk", function()
      local doc = sdp.parse(video_missing("measuredpixclk"))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("measuredpixclk", err.message)
      assert.equal("TR-10-1 §10.2", err.spec_ref)
    end)

    it("rejects IPMX video fmtp missing vtotal", function()
      local doc = sdp.parse(video_missing("vtotal"))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("vtotal", err.message)
    end)

    it("rejects IPMX video fmtp missing htotal", function()
      local doc = sdp.parse(video_missing("htotal"))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("htotal", err.message)
    end)

    it("rejects IPMX audio fmtp missing measuredsamplerate", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX Audio",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=audio 5010 RTP/AVP 97",
        "c=IN IP4 239.100.0.2/64",
        "a=rtpmap:97 L24/48000/8",
        "a=fmtp:97 channel-order=SMPTE2110.(ST); IPMX",  -- no measuredsamplerate
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=ptime:1",
      }, "\r\n")
      local doc = sdp.parse(text)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("measuredsamplerate", err.message)
      assert.equal("TR-10-1 §10.3", err.spec_ref)
    end)
  end)

  describe("M25 M10: TP required on IPMX video fmtp (TR-10-TP-1 §13.2)", function()
    it("rejects IPMX video fmtp missing TP", function()
      local fmtp = "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX"
      local doc = sdp.parse(base_ipmx_sdp({}, {}, fmtp))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("TP", err.message)
    end)
  end)

  describe("M25 H6: b=AS required for jxsv blocks (TR-10-7 §11)", function()
    local PTP = "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"
    local function jxsv_sdp(b_as_line)
      local lines = {
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX JPEG-XS",
        "t=0 0",
        PTP,
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
      }
      if b_as_line then lines[#lines+1] = b_as_line end
      lines[#lines+1] = "a=rtpmap:96 jxsv/90000"
      lines[#lines+1] = "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-22:2019; TP=2110TPNL; profile=High444.12; level=2k-1; sublevel=Sublev3bpp; transmode=1; packetmode=0; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX"
      lines[#lines+1] = "a=mediaclk:direct=0"
      lines[#lines+1] = PTP
      return table.concat(lines, "\r\n")
    end

    it("accepts jxsv with b=AS:50000", function()
      local doc, err = sdp.parse(jxsv_sdp("b=AS:50000"), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects jxsv missing b=AS", function()
      local doc = sdp.parse(jxsv_sdp(nil))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("b=AS", err.message)
      assert.matches("TR%-10%-7", err.spec_ref)
    end)
  end)

  describe("M25 M1/M2: JPEG XS fmtp value enums (TR-10-15-Part1 §8/§9)", function()
    local PTP = "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"
    local function jxsv_with_fmtp(fmtp_extras)
      local fmtp = "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-22:2019; TP=2110TPNL; " .. fmtp_extras .. "; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX"
      return table.concat({
        "v=0",
        "o=- 1 1 IN IP4 192.168.1.1",
        "s=jxsv enums",
        "t=0 0",
        PTP,
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "b=AS:50000",
        "a=rtpmap:96 jxsv/90000",
        fmtp,
        "a=mediaclk:direct=0",
        PTP,
      }, "\r\n")
    end

    -- M1
    it("accepts profile=High444.12", function()
      local doc, err = sdp.parse(jxsv_with_fmtp(
        "profile=High444.12; level=2k-1; sublevel=Sublev3bpp; transmode=1; packetmode=0"), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects profile=garbage", function()
      local doc = sdp.parse(jxsv_with_fmtp(
        "profile=garbage; level=2k-1; sublevel=Sublev3bpp; transmode=1; packetmode=0"))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("profile", err.message)
    end)

    it("rejects level=999X", function()
      local doc = sdp.parse(jxsv_with_fmtp(
        "profile=High444.12; level=999X; sublevel=Sublev3bpp; transmode=1; packetmode=0"))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("level", err.message)
    end)

    it("accepts sublevel=Sublev12bpp (above 4bpp per TR-10-15 §7.1)", function()
      local doc, err = sdp.parse(jxsv_with_fmtp(
        "profile=High444.12; level=2k-1; sublevel=Sublev12bpp; transmode=1; packetmode=0"), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects sublevel=Sublev5bpp (not defined)", function()
      local doc = sdp.parse(jxsv_with_fmtp(
        "profile=High444.12; level=2k-1; sublevel=Sublev5bpp; transmode=1; packetmode=0"))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("sublevel", err.message)
    end)

    -- M2
    it("accepts transmode=0 and packetmode=0", function()
      local doc, err = sdp.parse(jxsv_with_fmtp(
        "profile=High444.12; level=2k-1; sublevel=Sublev3bpp; transmode=0; packetmode=0"), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts transmode=1 and packetmode=1", function()
      local doc, err = sdp.parse(jxsv_with_fmtp(
        "profile=High444.12; level=2k-1; sublevel=Sublev3bpp; transmode=1; packetmode=1"), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects transmode=2", function()
      local doc = sdp.parse(jxsv_with_fmtp(
        "profile=High444.12; level=2k-1; sublevel=Sublev3bpp; transmode=2; packetmode=0"))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("transmode", err.message)
    end)

    it("rejects packetmode=99", function()
      local doc = sdp.parse(jxsv_with_fmtp(
        "profile=High444.12; level=2k-1; sublevel=Sublev3bpp; transmode=1; packetmode=99"))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("packetmode", err.message)
    end)
  end)

  describe("M25 H3/M8/M9: a=infoframe port-association and placement (TR-10-10 §8)", function()
    it("accepts a=infoframe with port == media port + 3", function()
      local doc, err = sdp.parse(
        base_ipmx_sdp({ "a=infoframe:5003 SSN=ST2110-41:2024;DIT=100100" }), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("H3 rejects a=infoframe whose port doesn't match any media port + 3", function()
      local doc = sdp.parse(
        base_ipmx_sdp({ "a=infoframe:9999 SSN=ST2110-41:2024;DIT=100100" }))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("infoframe", err.message)
      assert.matches("port", err.message)
      assert.equal("TR-10-10 §8", err.spec_ref)
    end)

    it("H3 rejects a=infoframe whose port equals media port + 1 (RTCP collision)", function()
      local doc = sdp.parse(
        base_ipmx_sdp({ "a=infoframe:5001 SSN=ST2110-41:2024;DIT=100100" }))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("infoframe", err.message)
    end)

    it("M8 rejects duplicate a=infoframe port", function()
      local doc = sdp.parse(base_ipmx_sdp({
        "a=infoframe:5003 SSN=ST2110-41:2024;DIT=100100",
        "a=infoframe:5003 SSN=ST2110-41:2024;DIT=100100",
      }))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("infoframe", err.message)
      assert.matches("duplicate", err.message)
    end)

    it("M9 rejects media-level a=infoframe (must be session-level)", function()
      local doc = sdp.parse(
        base_ipmx_sdp({}, { "a=infoframe:5003 SSN=ST2110-41:2024;DIT=100100" }))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("infoframe", err.message)
      assert.matches("session", err.message)
    end)
  end)

  describe("M25 M11: a=hkep placement is session-only (TR-10-5 §10)", function()
    local VALID_HKEP = "10000 IN IP4 192.168.1.100 550e8400-e29b-41d4-a716-446655440000 01-02-03-04-05"

    it("accepts a=hkep at session level", function()
      local doc, err = sdp.parse(
        base_ipmx_sdp({ "a=hkep:" .. VALID_HKEP }), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects a=hkep at media block level (session-only per TR-10-5 §10)", function()
      local doc = sdp.parse(
        base_ipmx_sdp({}, { "a=hkep:" .. VALID_HKEP }))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("hkep", err.message)
      assert.matches("session", err.message)
    end)
  end)

  describe("M25 M7: PEP IV-Counter extmap direction must be sendonly (TR-10-13 §20.1)", function()
    local PEP_FULL = "urn:ietf:params:rtp-hdrext:PEP-Full-IV-Counter"
    local PEP_SHORT = "urn:ietf:params:rtp-hdrext:PEP-Short-IV-Counter"

    it("accepts PEP-Full-IV-Counter extmap with /sendonly direction", function()
      local doc, err = sdp.parse(base_ipmx_sdp({
        "a=extmap:2/sendonly " .. PEP_FULL,
      }), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts PEP-Short-IV-Counter extmap with /sendonly direction", function()
      local doc, err = sdp.parse(base_ipmx_sdp({
        "a=extmap:2/sendonly " .. PEP_SHORT,
      }), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects PEP-Full-IV-Counter extmap with /recvonly direction", function()
      local doc = sdp.parse(base_ipmx_sdp({
        "a=extmap:2/recvonly " .. PEP_FULL,
      }))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("sendonly", err.message)
      assert.equal("TR-10-13 §20.1", err.spec_ref)
    end)

    it("rejects PEP-Full-IV-Counter extmap with no direction", function()
      local doc = sdp.parse(base_ipmx_sdp({
        "a=extmap:2 " .. PEP_FULL,
      }))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("sendonly", err.message)
    end)

    it("accepts non-PEP extmap with any direction", function()
      local doc, err = sdp.parse(base_ipmx_sdp({
        "a=extmap:2/recvonly urn:ietf:params:rtp-hdrext:smpte-tc-other",
      }), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  -- ── M25 LOW: coverage tightening ──────────────────────────────────────────────

  describe("M25 LOW: a=hkep IPv6 unicast address (TR-10-5 §10)", function()
    it("accepts a=hkep with IP6 addrtype and IPv6 unicast address", function()
      local doc, err = sdp.parse(base_ipmx_sdp({
        "a=hkep:10000 IN IP6 fe80::1 550e8400-e29b-41d4-a716-446655440000 01-02-03-04-05",
      }), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  describe("M25 LOW: PEP ECDH non-AAD on USB (TR-10-14 §12)", function()
    local function with_usb_privacy(privacy_value)
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
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "m=application 5100 TCP usb",
        "c=IN IP4 192.168.1.200",
        "a=setup:passive",
        "a=privacy: " .. privacy_value,
      }
      return table.concat(lines, "\r\n")
    end

    it("rejects ECDH_AES-128-CTR_CMAC-64 on USB (non-AAD ECDH variant not allowed)", function()
      local doc = sdp.parse(with_usb_privacy(
        "protocol=USB_KV; mode=ECDH_AES-128-CTR_CMAC-64; iv=0102030405060708; key_generator=aabbccddeeff00112233445566778899; key_version=01020304; key_id=deadbeefcafebabe"))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("mode", err.message)
    end)
  end)

  describe("M25 LOW: a=privacy key-order invariance (TR-10-13 §13)", function()
    local function privacy_text(value)
      return base_ipmx_sdp({ "a=privacy: " .. value })
    end

    it("accepts a=privacy with key_id appearing before protocol", function()
      local doc, err = sdp.parse(privacy_text(
        "key_id=deadbeefcafebabe; protocol=RTP; mode=AES-128-CTR; iv=0102030405060708; key_generator=aabbccddeeff00112233445566778899; key_version=01020304"
      ), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  describe("M25 LOW: USB block without a=privacy (TR-10-14 §12 encryption-off)", function()
    it("accepts USB block without a=privacy attribute", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX USB no privacy",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "m=application 5100 TCP usb",
        "c=IN IP4 192.168.1.200",
        "a=setup:passive",
      }, "\r\n")
      local doc, err = sdp.parse(text, "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  describe("M25 LOW: IPMX jxsv full-stack acceptance test", function()
    it("accepts a complete valid IPMX JPEG-XS SDP", function()
      local text = table.concat({
        "v=0",
        "o=- 1 1 IN IP4 192.168.1.1",
        "s=IPMX JXS",
        "t=0 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "b=AS:50000",
        "a=rtpmap:96 jxsv/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-22:2019; TP=2110TPNL; profile=High444.12; level=2k-1; sublevel=Sublev3bpp; transmode=1; packetmode=0; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
      }, "\r\n")
      local doc, err = sdp.parse(text, "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  describe("M25 LOW: a=infoframe port range and SSN year coverage", function()
    it("accepts a=infoframe SSN year 2099", function()
      local doc, err = sdp.parse(
        base_ipmx_sdp({ "a=infoframe:5003 SSN=ST2110-41:2099;DIT=100100" }), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects a=infoframe with malformed (non-4-digit) SSN year", function()
      local doc = sdp.parse(
        base_ipmx_sdp({ "a=infoframe:5003 SSN=ST2110-41:24;DIT=100100" }))
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("infoframe", err.message)
    end)
  end)

  describe("M25 M5: session-level b=AS validation (TR-10-7 §11)", function()
    it("rejects session-level b=AS:0 at IPMX tier", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX session b=AS:0",
        "b=AS:0",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
      }, "\r\n")
      local doc = sdp.parse(text)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.matches("b=AS", err.message)
    end)
  end)

  describe("M25 LOW: b=AS:1 lower-bound acceptance", function()
    it("accepts b=AS:1 (lower positive integer boundary)", function()
      local text = table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX b=AS lower bound",
        "t=0 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "b=AS:1",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
      }, "\r\n")
      local doc, err = sdp.parse(text, "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  -- ── M26 ──────────────────────────────────────────────────────────────────────
  -- Round-5 audit gap closure. Each describe block names the gap ID it addresses.

  describe("M26 H1: a=privacy session→media inheritance for DUP (TR-10-13 §13 line 859)", function()
    local MAC  = "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF"
    local VFMTP_IPMX = "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX"
    local PRIV = "a=privacy: protocol=RTP; mode=AES-128-CTR; iv=0102030405060708; key_generator=aabbccddeeff00112233445566778899; key_version=01020304; key_id=deadbeefcafebabe"
    local PRIV2 = "a=privacy: protocol=RTP; mode=AES-256-CTR; iv=0102030405060708; key_generator=aabbccddeeff00112233445566778899; key_version=01020304; key_id=deadbeefcafebabe"

    -- Build DUP-grouped IPMX SDP with optional session_privacy + per-leg privacy.
    local function dup_sdp(opts)
      opts = opts or {}
      local lines = {
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX M26 H1",
        "t=0 0",
        "a=group:DUP leg1 leg2",
        MAC,
      }
      if opts.session_privacy then lines[#lines+1] = opts.session_privacy end
      lines[#lines+1] = "m=video 5000 RTP/AVP 96"
      lines[#lines+1] = "c=IN IP4 239.100.0.1/64"
      lines[#lines+1] = "a=mid:leg1"
      lines[#lines+1] = "a=rtpmap:96 raw/90000"
      lines[#lines+1] = VFMTP_IPMX
      lines[#lines+1] = "a=mediaclk:direct=0"
      lines[#lines+1] = MAC
      lines[#lines+1] = "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc"
      if opts.privacy1 then lines[#lines+1] = opts.privacy1 end
      lines[#lines+1] = "m=video 5010 RTP/AVP 96"
      lines[#lines+1] = "c=IN IP4 239.100.0.2/64"
      lines[#lines+1] = "a=mid:leg2"
      lines[#lines+1] = "a=rtpmap:96 raw/90000"
      lines[#lines+1] = VFMTP_IPMX
      lines[#lines+1] = "a=mediaclk:direct=0"
      lines[#lines+1] = MAC
      if opts.privacy2 then lines[#lines+1] = opts.privacy2 end
      return table.concat(lines, "\r\n")
    end

    it("accepts DUP legs where session has a=privacy and both legs inherit", function()
      local doc, err = sdp.parse(dup_sdp({ session_privacy = PRIV }), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts DUP legs where session has a=privacy, leg1 inherits, leg2 explicit-same", function()
      local doc, err = sdp.parse(
        dup_sdp({ session_privacy = PRIV, privacy2 = PRIV }), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts DUP legs where session has a=privacy, leg2 inherits, leg1 explicit-same", function()
      local doc, err = sdp.parse(
        dup_sdp({ session_privacy = PRIV, privacy1 = PRIV }), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects DUP legs where inherited (session) value differs from explicit media value", function()
      local doc = sdp.parse(dup_sdp({ session_privacy = PRIV, privacy2 = PRIV2 }))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("privacy", err.message)
      assert.equal("TR-10-13 §13", err.spec_ref)
    end)

    it("rejects DUP legs where both legs have explicit different a=privacy values (regression)", function()
      local doc = sdp.parse(dup_sdp({ privacy1 = PRIV, privacy2 = PRIV2 }))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("privacy", err.message)
    end)
  end)

  describe("M26 H2: IPMX ts-refclk PTP version (TR-10-1 §10.4)", function()
    local function ipmx_with_tsrefclk(ts_value)
      return table.concat({
        "v=0",
        "o=- 1234567890 1 IN IP4 192.168.1.1",
        "s=IPMX M26 H2",
        "t=0 0",
        "a=ts-refclk:" .. ts_value,
        "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
        "m=video 5000 RTP/AVP 96",
        "c=IN IP4 239.100.0.1/64",
        "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
        "a=mediaclk:direct=0",
        "a=ts-refclk:" .. ts_value,
      }, "\r\n")
    end

    it("accepts ptp=IEEE1588-2008:<gmid>:<domain>", function()
      local doc, err = sdp.parse(
        ipmx_with_tsrefclk("ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0"), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("accepts ptp=IEEE1588-2008:traceable", function()
      local doc, err = sdp.parse(
        ipmx_with_tsrefclk("ptp=IEEE1588-2008:traceable"), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)

    it("rejects ptp=IEEE1588-2019:<gmid>:<domain>", function()
      local doc = sdp.parse(ipmx_with_tsrefclk("ptp=IEEE1588-2019:00-11-22-FF-FE-33-44-55:0"))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("IEEE1588%-2008", err.message)
    end)

    it("rejects ptp=IEEE1588-2002:<gmid>:<domain>", function()
      local doc = sdp.parse(ipmx_with_tsrefclk("ptp=IEEE1588-2002:00-11-22-FF-FE-33-44-55:0"))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("IEEE1588%-2008", err.message)
    end)

    it("rejects bare ptp=IEEE1588 (missing year suffix)", function()
      local doc = sdp.parse(ipmx_with_tsrefclk("ptp=IEEE1588:00-11-22-FF-FE-33-44-55:0"))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
    end)

    it("accepts localmac= (rule does not apply to non-ptp clock sources)", function()
      local doc, err = sdp.parse(
        ipmx_with_tsrefclk("localmac=AA-BB-CC-DD-EE-FF"), "ipmx")
      assert.is_nil(err)
      assert.is_table(doc)
    end)
  end)

  describe("M26 L1: a=rtcp port upper bound (RFC 768)", function()
    -- base_ipmx_sdp uses media port 5000, so rtcp must equal 5001. To exercise
    -- the upper-bound check specifically (not the port+1 check), use a port
    -- that wins on size: 100000 fails the upper bound regardless of media port.
    it("rejects a=rtcp:100000 (above UDP range)", function()
      local doc = sdp.parse(base_ipmx_sdp({}, { "a=rtcp:100000" }))
      assert.is_table(doc)
      local ok, err = doc:validate("ipmx")
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("65535", err.message)
    end)
  end)
end)
