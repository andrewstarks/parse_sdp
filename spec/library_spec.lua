---@diagnostic disable
-- Public-API tests.
--
-- Everything here tests the parse_sdp library's user-facing API contract:
-- method existence, return shape, mode-dispatch sanity, predicate behavior,
-- JSON serialization. None of these tests assert compliance with a published
-- standard — those live in the per-tier grammar specs:
--   spec/grammar_base_spec.lua   — RFC 8866 base SDP
--   spec/grammar_st2110_spec.lua — SMPTE ST 2110
--   spec/grammar_ipmx_spec.lua   — VSF TR-10 / IPMX
-- Tests for internal helpers live in:
--   spec/grammar_patterns_spec.lua / spec/grammar_addresses_spec.lua
--   spec/error_registry_spec.lua / spec/errors_spec.lua
-- Every it block below carries `-- NOT-SPEC: library`.

local sdp = require("parse_sdp")

-- ── Fixtures ─────────────────────────────────────────────────────────────────

local MINIMAL_SDP = table.concat({
  "v=0",
  "o=- 1 1 IN IP4 127.0.0.1",
  "s=Test",
  "t=0 0",
}, "\r\n") .. "\r\n"

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

local IPMX_VIDEO_SDP = table.concat({
  "v=0",
  "o=- 1234567890 1 IN IP4 192.168.1.1",
  "s=IPMX Video",
  "t=0 0",
  "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
  "m=video 5000 RTP/AVP 96",
  "c=IN IP4 239.100.0.1/64",
  "a=source-filter: incl IN IP4 239.100.0.1 192.168.1.1",
  "a=rtpmap:96 raw/90000",
  "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200; IPMX",
  "a=mediaclk:direct=0",
  "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
  "a=extmap:1 urn:ietf:params:rtp-hdrext:smpte-tc",
}, "\r\n") .. "\r\n"

local ST2110_ONLY_SDP = table.concat({
  "v=0",
  "o=- 1234567890 1 IN IP4 192.168.1.1",
  "s=ST2110 Video",
  "t=0 0",
  "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
  "m=video 5000 RTP/AVP 96",
  "c=IN IP4 239.100.0.1/64",
  "a=source-filter: incl IN IP4 239.100.0.1 192.168.1.1",
  "a=rtpmap:96 raw/90000",
  "a=fmtp:96 sampling=YCbCr-4:2:2; width=1920; height=1080; exactframerate=25; depth=10; TCS=SDR; colorimetry=BT709; PM=2110GPM; SSN=ST2110-20:2022; TP=2110TPN; measuredpixclk=148500000; vtotal=1125; htotal=2200",
  "a=mediaclk:direct=0",
  "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
}, "\r\n") .. "\r\n"

local ST2110_MISSING_TSREFCLK = table.concat({
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

local LOCALMAC_VIDEO_SDP = table.concat({
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

local FULL_TEXT_FOR_JSON = table.concat({
  "v=0",
  "o=- 1234567890 1 IN IP4 192.168.1.1",
  "s=Test Session",
  "t=0 0",
  "a=tool:test",
  "m=video 5000 RTP/AVP 96",
  -- RFC 8866 §9 IP4-multicast ABNF requires the /<ttl> suffix; grammar
  -- tier enforces (1.0 base parser was permissive).
  "c=IN IP4 239.100.0.1/64",
  "a=rtpmap:96 H264/90000",
}, "\r\n") .. "\r\n"

-- ── 1. Module loads ──────────────────────────────────────────────────────────

describe("library: parse_sdp module loads", function()
  -- NOT-SPEC: library
  it("loads without error", function()
    assert.is_table(sdp)
  end)
end)

-- ── 2. sdp.parse(text): doc shape ────────────────────────────────────────────

describe("library: sdp.parse() returns doc with API methods", function()
  -- NOT-SPEC: library
  it("parsed doc has validate, is_sdp, is_st2110, is_ipmx methods", function()
    local doc = sdp.parse(MINIMAL_SDP)
    assert.is_function(doc.validate)
    assert.is_function(doc.is_sdp)
    assert.is_function(doc.is_st2110)
    assert.is_function(doc.is_ipmx)
  end)
end)

-- ── 2a. sdp.parse() grammar-failure error shape ──────────────────────────────
--
-- When pattern algebra rejects the input (no error-severity finding recorded
-- — e.g. `v=1` instead of `v=0`, an unknown addrtype `IP7`, fields out of
-- order, or required tail fields missing), the returned err carries the
-- deepest line_end progress as line/col/line_text. The pre-fix behavior was
-- a bare `errors.new("SDP parse failed")` with no position info.

describe("library: sdp.parse() positioned error on grammar failure", function()
  -- NOT-SPEC: library
  it("rejects v=1 with line 1 / col 1 and the offending source line", function()
    local _, err = sdp.parse("v=1\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=x\r\nt=0 0\r\n")
    assert.is_table(err)
    assert.equals("PARSE_ERROR", err.code)
    assert.equals(1, err.line)
    assert.equals(1, err.col)
    assert.equals("v=1", err.line_text)
  end)

  -- NOT-SPEC: library
  it("points at the out-of-order line when fields are mis-ordered", function()
    local text = "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\nt=0 0\r\ns=Late\r\n"
    local _, err = sdp.parse(text)
    assert.is_table(err)
    assert.equals("PARSE_ERROR", err.code)
    assert.equals(3, err.line)
    assert.equals("t=0 0", err.line_text)
  end)

  -- NOT-SPEC: library
  it("points at the o= line when addrtype is unknown (IP7)", function()
    local text = "v=0\r\no=- 1 1 IN IP7 192.168.1.1\r\ns=x\r\nt=0 0\r\n"
    local _, err = sdp.parse(text)
    assert.is_table(err)
    assert.equals("PARSE_ERROR", err.code)
    assert.equals(2, err.line)
    assert.equals("o=- 1 1 IN IP7 192.168.1.1", err.line_text)
  end)

  -- NOT-SPEC: library
  it("reports a distinct message when input ends with required fields missing", function()
    local _, err = sdp.parse("v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\n")
    assert.is_table(err)
    assert.equals("PARSE_ERROR", err.code)
    -- line_text is empty (we're past EOF); message must NOT be the
    -- "could not parse from this line" variant since there's no line to show.
    assert.equals("", err.line_text)
    assert.matches("end of input", err.message)
  end)

  -- NOT-SPEC: library
  it("formats with rust-style block including code, line, col, source line", function()
    local errors = sdp._errors
    local _, err = sdp.parse("v=0\r\no=- 1 1 IN IP7 192.168.1.1\r\ns=x\r\nt=0 0\r\n")
    local formatted = errors.format(err)
    assert.matches("%[PARSE_ERROR%]", formatted)
    assert.matches("line 2, col 1", formatted)
    assert.matches("o=%- 1 1 IN IP7", formatted)
  end)
end)

-- ── 3. sdp.parse(text, 'st2110') mode dispatch ───────────────────────────────

describe("library: sdp.parse() with 'st2110' mode", function()
  -- NOT-SPEC: library
  it("returns a doc for valid ST 2110-20 (video) SDP", function()
    local doc, err = sdp.parse(VIDEO_SDP, "st2110")
    assert.is_nil(err)
    assert.is_table(doc)
  end)

  -- NOT-SPEC: library
  it("returns a doc for valid ST 2110-30 (audio) SDP", function()
    local doc, err = sdp.parse(AUDIO_SDP, "st2110")
    assert.is_nil(err)
    assert.is_table(doc)
  end)

  -- NOT-SPEC: library
  -- Behavior change from 1.0: the grammar tier does not require ≥1 media
  -- block at any tier (no spec text explicitly forbids an empty SDP).
  -- Tests asserting media-presence rejection moved out with the legacy
  -- 1.0 suite; ts-refclk-missing remains as the canonical st2110-rejection
  -- assertion (test below) since §8.2's per-block SHALL is unambiguous.
  it("returns nil+err for SDP missing ts-refclk everywhere", function()
    local doc, err = sdp.parse(ST2110_MISSING_TSREFCLK, "st2110")
    assert.is_nil(doc)
    assert.is_table(err)
    assert.matches("ts%-refclk", err.message)
  end)
end)

-- ── 4. sdp.parse(text, 'ipmx') mode dispatch ─────────────────────────────────

describe("library: sdp.parse() with 'ipmx' mode", function()
  -- NOT-SPEC: library
  it("returns a doc for valid IPMX SDP (localmac ts-refclk, not PTP)", function()
    local doc, err = sdp.parse(IPMX_VIDEO_SDP, "ipmx")
    assert.is_nil(err)
    assert.is_table(doc)
  end)

  -- NOT-SPEC: library
  it("returns nil+err for ST 2110 SDP missing IPMX fmtp marker", function()
    local doc, err = sdp.parse(ST2110_ONLY_SDP, "ipmx")
    assert.is_nil(doc)
    assert.is_table(err)
    assert.matches("IPMX", err.message)
  end)

  -- (no separate "no media block" assertion at ipmx; grammar tier permits
  -- empty SDPs at every tier — see comment above on the st2110 block.)
end)

-- ── 5. doc:validate() default and 'sdp' mode ─────────────────────────────────

describe("library: doc:validate() default and 'sdp' mode", function()
  -- NOT-SPEC: library
  it("doc:validate() returns true for a valid parsed doc", function()
    local doc = sdp.parse(MINIMAL_SDP)
    local ok, err = doc:validate()
    assert.is_true(ok)
    assert.is_nil(err)
  end)

  -- NOT-SPEC: library
  it("doc:validate('sdp') also returns true", function()
    local doc = sdp.parse(MINIMAL_SDP)
    local ok, err = doc:validate("sdp")
    assert.is_true(ok)
    assert.is_nil(err)
  end)

  -- NOT-SPEC: library
  it("doc:validate() returns nil, err with message after mutation", function()
    local doc = sdp.parse(MINIMAL_SDP)
    doc.version = nil
    local ok, err = doc:validate()
    assert.is_nil(ok)
    assert.is_table(err)
    assert.is_string(err.message)
  end)
end)

-- ── 6. doc:validate('st2110') mode dispatch + error contract ─────────────────

describe("library: doc:validate('st2110')", function()
  -- NOT-SPEC: library
  it("returns true for valid ST 2110-20 video", function()
    local doc = sdp.parse(VIDEO_SDP)
    assert.is_table(doc)
    local ok, err = doc:validate("st2110")
    assert.is_nil(err)
    assert.equal(true, ok)
  end)

  -- NOT-SPEC: library
  it("returns true for valid ST 2110-30 audio", function()
    local doc = sdp.parse(AUDIO_SDP)
    assert.is_table(doc)
    local ok, err = doc:validate("st2110")
    assert.is_nil(err)
    assert.equal(true, ok)
  end)

  -- NOT-SPEC: library
  it("error includes field_path and spec_ref when ts-refclk is missing", function()
    local doc = sdp.parse(ST2110_MISSING_TSREFCLK)
    assert.is_table(doc)
    local ok, err = doc:validate("st2110")
    assert.is_nil(ok)
    assert.is_table(err)
    assert.is_string(err.field_path)
    assert.is_string(err.spec_ref)
    assert.matches("ts%-refclk", err.message)
  end)
end)

-- ── 7. doc:validate('ipmx') mode dispatch + error contract ───────────────────

describe("library: doc:validate('ipmx')", function()
  -- NOT-SPEC: library
  it("returns true for valid IPMX SDP", function()
    local doc = sdp.parse(IPMX_VIDEO_SDP)
    assert.is_table(doc)
    local ok, err = doc:validate("ipmx")
    assert.is_nil(err)
    assert.equal(true, ok)
  end)

  -- NOT-SPEC: library
  it("returns nil+err for ST 2110 SDP missing IPMX fmtp marker", function()
    local doc = sdp.parse(ST2110_ONLY_SDP)
    assert.is_table(doc)
    local ok, err = doc:validate("ipmx")
    assert.is_nil(ok)
    assert.is_table(err)
    assert.matches("IPMX", err.message)
  end)

  -- NOT-SPEC: library
  it("error includes field_path and spec_ref", function()
    local doc = sdp.parse(ST2110_ONLY_SDP)
    assert.is_table(doc)
    local ok, err = doc:validate("ipmx")
    assert.is_nil(ok)
    assert.is_table(err)
    assert.is_string(err.field_path)
    assert.is_string(err.spec_ref)
  end)

end)

-- ── 8. doc:validate(unknown_mode) ────────────────────────────────────────────

describe("library: doc:validate(unknown_mode)", function()
  -- NOT-SPEC: library
  it("doc:validate() returns nil, err for unknown mode", function()
    local doc = sdp.parse(MINIMAL_SDP)
    local ok, err = doc:validate("unknown")
    assert.is_nil(ok)
    assert.is_table(err)
    assert.matches("unknown mode", err.message)
  end)
end)

-- ── 9. doc:is_sdp() predicate ────────────────────────────────────────────────

describe("library: doc:is_sdp() predicate", function()
  -- NOT-SPEC: library
  it("doc:is_sdp() returns true for a valid parsed doc", function()
    local doc = sdp.parse(MINIMAL_SDP)
    assert.is_true(doc:is_sdp())
  end)

  -- NOT-SPEC: library
  it("doc:is_sdp() returns false after mutation removes version", function()
    local doc = sdp.parse(MINIMAL_SDP)
    doc.version = nil
    assert.is_false(doc:is_sdp())
  end)

  -- NOT-SPEC: library
  it("sdp.new({}) is_sdp() returns false", function()
    local doc = sdp.new({})
    assert.is_false(doc:is_sdp())
  end)
end)

-- ── 10. doc:is_st2110() predicate ────────────────────────────────────────────

describe("library: doc:is_st2110() predicate", function()
  -- NOT-SPEC: library
  it("returns true for valid ST 2110-20 video", function()
    local doc = sdp.parse(VIDEO_SDP)
    assert.is_table(doc)
    assert.equal(true, doc:is_st2110())
  end)

  -- NOT-SPEC: library
  it("returns true for valid ST 2110-30 audio", function()
    local doc = sdp.parse(AUDIO_SDP)
    assert.is_table(doc)
    assert.equal(true, doc:is_st2110())
  end)

  -- NOT-SPEC: library
  it("returns false when a media block is missing ts-refclk (ST 2110-10 §8.2)", function()
    local doc = sdp.parse(ST2110_MISSING_TSREFCLK)
    assert.is_table(doc)
    assert.equal(false, doc:is_st2110())
  end)

  -- NOT-SPEC: library
  it("returns true for SDP with localmac ts-refclk (PTP not required)", function()
    local doc = sdp.parse(LOCALMAC_VIDEO_SDP)
    assert.is_table(doc)
    assert.equal(true, doc and doc:is_st2110())
  end)
end)

-- ── 11. doc:is_ipmx() predicate ──────────────────────────────────────────────

describe("library: doc:is_ipmx() predicate", function()
  -- NOT-SPEC: library
  it("returns true for valid IPMX SDP", function()
    local doc = sdp.parse(IPMX_VIDEO_SDP)
    assert.is_table(doc)
    assert.equal(true, doc:is_ipmx())
  end)

  -- NOT-SPEC: library
  it("returns false for ST 2110 SDP without IPMX fmtp marker", function()
    local doc = sdp.parse(ST2110_ONLY_SDP)
    assert.is_table(doc)
    assert.equal(false, doc:is_ipmx())
  end)
end)

-- ── 12. doc:to_json() ────────────────────────────────────────────────────────

describe("library: doc:to_json()", function()
  -- NOT-SPEC: library
  it("to_json method exists on parsed doc", function()
    local doc = sdp.parse(FULL_TEXT_FOR_JSON)
    assert.is_table(doc)
    assert.is_function(doc.to_json)
  end)

  -- NOT-SPEC: library
  it("returns a string", function()
    local doc = sdp.parse(FULL_TEXT_FOR_JSON)
    local out = doc:to_json()
    assert.is_string(out)
  end)

  -- NOT-SPEC: library
  it("output is valid JSON (parses back without error)", function()
    local dkjson = require("dkjson")
    local doc = sdp.parse(FULL_TEXT_FOR_JSON)
    local out = doc:to_json()
    local decoded, _, err = dkjson.decode(out)
    assert.is_nil(err)
    assert.is_table(decoded)
  end)

  -- NOT-SPEC: library
  it("JSON contains top-level doc fields (version, origin, session, media)", function()
    local dkjson = require("dkjson")
    local doc = sdp.parse(FULL_TEXT_FOR_JSON)
    local decoded = dkjson.decode(doc:to_json())
    assert.equal("0", decoded.version)
    assert.is_table(decoded.origin)
    assert.is_table(decoded.session)
    assert.is_table(decoded.media)
  end)

  -- NOT-SPEC: library
  it("JSON origin fields are correct", function()
    local dkjson = require("dkjson")
    local doc = sdp.parse(FULL_TEXT_FOR_JSON)
    local decoded = dkjson.decode(doc:to_json())
    assert.equal("192.168.1.1", decoded.origin.unicast_address)
    assert.equal("IN",          decoded.origin.net_type)
    assert.equal("IP4",         decoded.origin.addr_type)
  end)

  -- NOT-SPEC: library
  it("JSON session attributes array is present", function()
    local dkjson = require("dkjson")
    local doc = sdp.parse(FULL_TEXT_FOR_JSON)
    local decoded = dkjson.decode(doc:to_json())
    assert.is_table(decoded.session.attributes)
    assert.equal(1, #decoded.session.attributes)
    assert.equal("tool", decoded.session.attributes[1].name)
  end)

  -- NOT-SPEC: library
  it("JSON media array has correct entry", function()
    local dkjson = require("dkjson")
    local doc = sdp.parse(FULL_TEXT_FOR_JSON)
    local decoded = dkjson.decode(doc:to_json())
    assert.equal(1, #decoded.media)
    assert.equal("video", decoded.media[1].media)
    assert.equal(5000,    decoded.media[1].port)
  end)

  -- NOT-SPEC: library
  it("sdp.new({}) has to_json method", function()
    local doc = sdp.new({})
    assert.is_function(doc.to_json)
  end)
end)

-- ── 13. sdp.new(table) wrapper ───────────────────────────────────────────────

describe("library: sdp.new() wrapper", function()
  -- NOT-SPEC: library
  it("sdp.new({}) has validate and is_sdp methods", function()
    local doc = sdp.new({})
    assert.is_function(doc.validate)
    assert.is_function(doc.is_sdp)
  end)
end)

describe("library: sdp.checks() registry introspection", function()
  -- NOT-SPEC: library
  it("returns a non-empty array of check definitions", function()
    local cs = sdp.checks()
    assert.is_table(cs)
    assert.is_truthy(#cs > 0)
    for _, c in ipairs(cs) do
      assert.is_string(c.id)
      assert.is_string(c.spec_ref)
      assert.is_string(c.default_severity)
    end
  end)

  -- NOT-SPEC: library
  it("entries are sorted by id", function()
    local prev
    for _, c in ipairs(sdp.checks()) do
      if prev then assert.is_truthy(prev < c.id) end
      prev = c.id
    end
  end)
end)

describe("library: sdp.default_policy()", function()
  -- NOT-SPEC: library
  it("returns a table mapping every registered id to its default severity", function()
    local p = sdp.default_policy()
    assert.is_table(p)
    for _, c in ipairs(sdp.checks()) do
      assert.equal(c.default_severity, p[c.id])
    end
  end)

  -- NOT-SPEC: library
  it("returned table is a fresh copy (caller can mutate without polluting)", function()
    local p1 = sdp.default_policy()
    p1["sdp.v.must-be-zero"] = "warn"
    local p2 = sdp.default_policy()
    assert.equal("error", p2["sdp.v.must-be-zero"])
  end)
end)

describe("library: sdp.parse(text, mode, opts) policy validation", function()
  -- NOT-SPEC: library
  it("accepts opts.policy with all-known ids", function()
    local doc, err = sdp.parse(MINIMAL_SDP, nil,
      { policy = { ["sdp.v.must-be-zero"] = "warn" } })
    assert.is_not_nil(doc)
    assert.is_nil(err)
  end)

  -- NOT-SPEC: library
  it("rejects opts.policy with an unknown id and names the offending key", function()
    local doc, err = sdp.parse(MINIMAL_SDP, nil,
      { policy = { ["bogus.check.id"] = "warn" } })
    assert.is_nil(doc)
    assert.is_table(err)
    assert.equal("bogus.check.id", err.policy_key)
  end)

  -- NOT-SPEC: library
  it("rejects opts.policy with an invalid severity value", function()
    local doc, err = sdp.parse(MINIMAL_SDP, nil,
      { policy = { ["sdp.v.must-be-zero"] = "fatal" } })
    assert.is_nil(doc)
    assert.is_table(err)
    assert.equal("sdp.v.must-be-zero", err.policy_key)
  end)

  -- NOT-SPEC: library
  it("accepts an empty opts table", function()
    local doc = sdp.parse(MINIMAL_SDP, nil, {})
    assert.is_not_nil(doc)
  end)

  -- NOT-SPEC: library
  it("nil opts behaves as before (backward-compat)", function()
    local doc = sdp.parse(MINIMAL_SDP)
    assert.is_not_nil(doc)
  end)
end)

describe("library: doc findings accessors", function()
  -- NOT-SPEC: library
  it("doc:findings() returns an empty list for sdp.new()", function()
    local doc = sdp.new({})
    assert.is_table(doc:findings())
    assert.equal(0, #doc:findings())
  end)

  -- NOT-SPEC: library
  it("doc:warnings() returns an empty list for sdp.new()", function()
    local doc = sdp.new({})
    assert.is_table(doc:warnings())
    assert.equal(0, #doc:warnings())
  end)

  -- NOT-SPEC: library
  it("doc:errors() returns an empty list for sdp.new()", function()
    local doc = sdp.new({})
    assert.is_table(doc:errors())
    assert.equal(0, #doc:errors())
  end)

  -- NOT-SPEC: library
  it("all three are methods on every parsed doc", function()
    local doc = sdp.parse(MINIMAL_SDP)
    assert.is_function(doc.findings)
    assert.is_function(doc.warnings)
    assert.is_function(doc.errors)
  end)

  -- NOT-SPEC: library
  it("warnings() + errors() partition findings() by severity", function()
    local doc = sdp.parse(MINIMAL_SDP)
    local all  = doc:findings()
    local warn = doc:warnings()
    local errs = doc:errors()
    assert.equal(#all, #warn + #errs)
    for _, f in ipairs(warn) do assert.equal("warn", f.severity) end
    for _, f in ipairs(errs) do assert.equal("error", f.severity) end
  end)
end)
