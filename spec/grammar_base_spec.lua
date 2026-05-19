---@diagnostic disable
-- Phase 1: structural acceptance/rejection tests for the base SDP grammar
-- skeleton. Every leaf is a placeholder accepting "any non-empty line
-- content" — Phase 2 will tighten leaves and add decomposition. These tests
-- exercise document shape (RFC 8866 §5) only.

local base = require("parse_sdp.grammar.base")

local function lines_to_sdp(lines)
  return table.concat(lines, "\r\n") .. "\r\n"
end

-- Minimal valid RFC 8866 SDP: v=, o=, s=, t=.
local function minimal(extra_lines, media_blocks)
  local out = {
    "v=0",
    "o=- 1234567890 1 IN IP4 192.0.2.1",
    "s=Test Session",
  }
  for _, l in ipairs(extra_lines or {}) do out[#out + 1] = l end
  out[#out + 1] = "t=0 0"
  for _, block in ipairs(media_blocks or {}) do
    for _, l in ipairs(block) do out[#out + 1] = l end
  end
  return lines_to_sdp(out)
end

describe("base SDP grammar — document shape (RFC 8866 §5)", function()

  -- NOT-SPEC: library
  it("accepts the minimal valid session (v=, o=, s=, t=)", function()
    assert.is_truthy(base.match(minimal()))
  end)

  -- NOT-SPEC: library
  it("accepts one media block", function()
    assert.is_truthy(base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000" },
    })))
  end)

  -- NOT-SPEC: library
  it("accepts multiple media blocks", function()
    -- Dynamic PT 96 requires a=rtpmap (RFC 8866 §8.2.3, Phase 3.B).
    assert.is_truthy(base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000" },
      { "m=audio 49172 RTP/AVP 0"  },
      { "m=text 49174 RTP/AVP 96",  "a=rtpmap:96 t140/1000" },
    })))
  end)

  -- NOT-SPEC: library
  it("accepts all optional session-level fields in RFC 8866 order", function()
    local text = lines_to_sdp({
      "v=0",
      "o=- 1 1 IN IP4 127.0.0.1",
      "s=X",
      "i=info",
      "u=http://example.com/",
      "e=alice@example.com",
      "p=+1 555 1234",
      "c=IN IP4 224.0.0.1/127",
      "b=AS:128",
      "t=0 0",
      "z=2882844526 -1h",
      "k=clear:password",
      "a=tool:foo",
    })
    assert.is_truthy(base.match(text))
  end)

  -- NOT-SPEC: library
  it("accepts multiple time descriptions (more than one t=)", function()
    local text = lines_to_sdp({
      "v=0",
      "o=- 1 1 IN IP4 127.0.0.1",
      "s=X",
      "t=0 0",
      "t=2873397496 2873404696",
    })
    assert.is_truthy(base.match(text))
  end)

  -- NOT-SPEC: library
  it("accepts r= lines after t=", function()
    local text = lines_to_sdp({
      "v=0",
      "o=- 1 1 IN IP4 127.0.0.1",
      "s=X",
      "t=2873397496 2873404696",
      "r=604800 3600 0 90000",
    })
    assert.is_truthy(base.match(text))
  end)

  -- NOT-SPEC: library
  it("accepts session-level a= attributes", function()
    local text = lines_to_sdp({
      "v=0",
      "o=- 1 1 IN IP4 127.0.0.1",
      "s=X",
      "t=0 0",
      "a=tool:foo",
      "a=type:broadcast",
    })
    assert.is_truthy(base.match(text))
  end)

  -- NOT-SPEC: library
  it("rejects empty input", function()
    assert.is_nil(base.match(""))
  end)

  -- NOT-SPEC: library
  it("rejects SDP with no v= (RFC 8866 §5: v= is required)", function()
    local text = lines_to_sdp({
      "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
    })
    assert.is_nil(base.match(text))
  end)

  -- NOT-SPEC: library
  it("rejects SDP with no o= (RFC 8866 §5: o= is required)", function()
    local text = lines_to_sdp({ "v=0", "s=X", "t=0 0" })
    assert.is_nil(base.match(text))
  end)

  -- NOT-SPEC: library
  it("rejects SDP with no s= (RFC 8866 §5: s= is required)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "t=0 0",
    })
    assert.is_nil(base.match(text))
  end)

  -- NOT-SPEC: library
  it("rejects SDP with no t= (RFC 8866 §5: at least one t= is required)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
    })
    assert.is_nil(base.match(text))
  end)

  -- NOT-SPEC: library
  it("rejects wrong order (s= before o=)", function()
    local text = lines_to_sdp({
      "v=0", "s=X", "o=- 1 1 IN IP4 127.0.0.1", "t=0 0",
    })
    assert.is_nil(base.match(text))
  end)

  -- NOT-SPEC: library
  it("rejects wrong order (c= before t=)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "t=0 0",
      "c=IN IP4 224.0.0.1/127",  -- c= belongs before t=, not after
    })
    -- after the t= block we only allow z=, k=, a=, then media sections
    assert.is_nil(base.match(text))
  end)

  -- NOT-SPEC: library
  it("rejects junk after the last media section", function()
    local text = minimal(nil, { { "m=video 49170 RTP/AVP 96" } }) .. "garbage\r\n"
    assert.is_nil(base.match(text))
  end)

  -- NOT-SPEC: library
  it("accepts bare LF line endings with a warn finding (Phase 5 soft-syntactic)", function()
    -- RFC 8866 §9 ABNF says CRLF; bare LF is non-conformant but common.
    -- Phase 5 added soft-syntactic tolerance that records the deviation
    -- via sdp.line.lf-only-line-ending. Detailed coverage lives in the
    -- "Phase 5 soft-syntactic findings" describe block below.
    local text = "v=0\no=- 1 1 IN IP4 127.0.0.1\ns=X\nt=0 0\n"
    assert.is_truthy(base.match(text))
  end)

  -- NOT-SPEC: library
  it("accepts missing final CRLF on the last line (Phase 5 soft-syntactic)", function()
    -- RFC 8866 §9 ABNF requires CRLF after every line including the last.
    -- Phase 5 records sdp.file.trailing-newline-missing instead of rejecting.
    local text = "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=X\r\nt=0 0"
    assert.is_truthy(base.match(text))
  end)

  -- NOT-SPEC: library
  it("rejects an empty value (RFC 8866 §5: text values must be non-empty)", function()
    local text = "v=\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=X\r\nt=0 0\r\n"
    assert.is_nil(base.match(text))
  end)

end)

describe("base SDP grammar — captured doc shape (Phase 2.A)", function()

  -- NOT-SPEC: library
  it("returns a captured table for minimal valid SDP", function()
    local doc = base.match(minimal())
    assert.is_table(doc)
  end)

  -- NOT-SPEC: library
  it("captures version = '0' (RFC 8866 §5.1)", function()
    local doc = base.match(minimal())
    assert.equal("0", doc.version)
  end)

  -- NOT-SPEC: library
  it("captures session.name (RFC 8866 §5.3)", function()
    local doc = base.match(minimal())
    assert.equal("Test Session", doc.session.name)
  end)

  -- NOT-SPEC: library
  it("captures session.name preserving spaces, punctuation, dashes", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1",
      "s=Multi-word session: with punctuation!",
      "t=0 0",
    })
    local doc = base.match(text)
    assert.equal("Multi-word session: with punctuation!", doc.session.name)
  end)

  -- NOT-SPEC: library
  it("rejects v= != '0' (RFC 8866 §5.1: only '0' currently defined)", function()
    local text = lines_to_sdp({
      "v=1", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
    })
    assert.is_nil(base.match(text))
  end)

  -- NOT-SPEC: library
  it("k= line is parsed and discarded (RFC 8866 §5.12 obsolete)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "k=clear:password",
    })
    local doc = base.match(text)
    assert.is_table(doc)
    assert.equal("0",  doc.version)
    assert.equal("X",  doc.session.name)
    assert.is_nil(doc.session.key)  -- §5.12 says discard; no field on doc
  end)

  -- NOT-SPEC: library
  it("captures session as a sub-table, not a top-level field bag", function()
    local doc = base.match(minimal())
    -- session.name is inside doc.session, not at doc top level.
    assert.is_table(doc.session)
    assert.is_nil(doc.name)
  end)

end)

describe("base SDP grammar — origin and connection captures (Phase 2.B)", function()

  -- NOT-SPEC: library
  it("captures doc.origin as a table with six fields (RFC 8866 §5.2)", function()
    local doc = base.match(minimal())
    assert.is_table(doc.origin)
    assert.equal("-",            doc.origin.username)
    assert.equal("1234567890",   doc.origin.sess_id)
    assert.equal("1",            doc.origin.sess_version)
    assert.equal("IN",           doc.origin.net_type)
    assert.equal("IP4",          doc.origin.addr_type)
    assert.equal("192.0.2.1",    doc.origin.unicast_address)
  end)

  -- NOT-SPEC: library
  it("captures IPv6 origin (addr_type = IP6)", function()
    local text = lines_to_sdp({
      "v=0",
      "o=alice 2890844526 2890844527 IN IP6 2001:db8::1",
      "s=X",
      "t=0 0",
    })
    local doc = base.match(text)
    assert.equal("alice",       doc.origin.username)
    assert.equal("2890844526",  doc.origin.sess_id)
    assert.equal("2890844527",  doc.origin.sess_version)
    assert.equal("IP6",         doc.origin.addr_type)
    assert.equal("2001:db8::1", doc.origin.unicast_address)
  end)

  -- NOT-SPEC: library
  it("keeps sess_id and sess_version as strings (preserves NTP-range precision)", function()
    -- 18446744073709551615 is 2^64 - 1, exceeds Lua 5.5 safe-integer range
    -- on a 32-bit lua_Integer build.
    local text = lines_to_sdp({
      "v=0",
      "o=u 18446744073709551615 18446744073709551614 IN IP4 192.0.2.1",
      "s=X",
      "t=0 0",
    })
    local doc = base.match(text)
    assert.is_string(doc.origin.sess_id)
    assert.equal("18446744073709551615", doc.origin.sess_id)
    assert.equal("18446744073709551614", doc.origin.sess_version)
  end)

  -- NOT-SPEC: library
  it("rejects o= with non-IN net_type (RFC 8866 §5.2 defines only IN)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 XX IP4 192.0.2.1", "s=X", "t=0 0",
    })
    assert.is_nil(base.match(text))
  end)

  -- NOT-SPEC: library
  it("rejects o= with unknown addr_type", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP9 192.0.2.1", "s=X", "t=0 0",
    })
    assert.is_nil(base.match(text))
  end)

  -- NOT-SPEC: library
  it("rejects o= with non-digit sess_id", function()
    local text = lines_to_sdp({
      "v=0", "o=- abc 1 IN IP4 192.0.2.1", "s=X", "t=0 0",
    })
    assert.is_nil(base.match(text))
  end)

  -- NOT-SPEC: library
  it("rejects o= with too few tokens", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4", "s=X", "t=0 0",
    })
    assert.is_nil(base.match(text))
  end)

  -- NOT-SPEC: library
  it("session.connection is nil when c= is absent", function()
    local doc = base.match(minimal())
    assert.is_nil(doc.session.connection)
  end)

  -- NOT-SPEC: library
  it("captures session.connection when c= is present (RFC 8866 §5.7)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 192.0.2.1", "s=X",
      "c=IN IP4 224.0.0.1/127",
      "t=0 0",
    })
    local doc = base.match(text)
    assert.is_table(doc.session.connection)
    assert.equal("IN",              doc.session.connection.net_type)
    assert.equal("IP4",             doc.session.connection.addr_type)
    -- /TTL suffix stays as part of the address string at this tier; Phase 3
    -- adds the decomposition + value-form validation.
    assert.equal("224.0.0.1/127",   doc.session.connection.address)
  end)

  -- NOT-SPEC: library
  it("captures IPv6 connection address", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP6 2001:db8::1", "s=X",
      "c=IN IP6 ff00::1",
      "t=0 0",
    })
    local doc = base.match(text)
    assert.equal("IP6",     doc.session.connection.addr_type)
    assert.equal("ff00::1", doc.session.connection.address)
  end)

  -- NOT-SPEC: library
  it("rejects c= with wrong net_type", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 192.0.2.1", "s=X",
      "c=ZZ IP4 224.0.0.1/127", "t=0 0",
    })
    assert.is_nil(base.match(text))
  end)

  -- NOT-SPEC: library
  it("rejects c= missing the address token", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 192.0.2.1", "s=X",
      "c=IN IP4", "t=0 0",
    })
    assert.is_nil(base.match(text))
  end)

end)

describe("base SDP grammar — text fields and bandwidth (Phase 2.C)", function()

  -- NOT-SPEC: library
  it("captures session.info when i= present (RFC 8866 §5.4)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "i=A short session description",
      "t=0 0",
    })
    local doc = base.match(text)
    assert.equal("A short session description", doc.session.info)
  end)

  -- NOT-SPEC: library
  it("session.info is nil when i= absent", function()
    local doc = base.match(minimal())
    assert.is_nil(doc.session.info)
  end)

  -- NOT-SPEC: library
  it("captures session.uri when u= present (RFC 8866 §5.5)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "u=http://example.com/session.sdp",
      "t=0 0",
    })
    local doc = base.match(text)
    assert.equal("http://example.com/session.sdp", doc.session.uri)
  end)

  -- NOT-SPEC: library
  it("captures session.emails as an array (RFC 8866 §5.6)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "e=alice@example.com",
      "e=bob@example.com (Bob)",
      "t=0 0",
    })
    local doc = base.match(text)
    assert.is_table(doc.session.emails)
    assert.equal(2, #doc.session.emails)
    assert.equal("alice@example.com",      doc.session.emails[1])
    assert.equal("bob@example.com (Bob)",  doc.session.emails[2])
  end)

  -- NOT-SPEC: library
  it("session.emails is an empty array when no e= lines", function()
    local doc = base.match(minimal())
    assert.is_table(doc.session.emails)
    assert.equal(0, #doc.session.emails)
  end)

  -- NOT-SPEC: library
  it("captures session.phones as an array (RFC 8866 §5.6)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "p=+1 555 1234",
      "p=+44 20 7946 0958",
      "t=0 0",
    })
    local doc = base.match(text)
    assert.is_table(doc.session.phones)
    assert.equal(2, #doc.session.phones)
    assert.equal("+1 555 1234",        doc.session.phones[1])
    assert.equal("+44 20 7946 0958",   doc.session.phones[2])
  end)

  -- NOT-SPEC: library
  it("captures session.bandwidths with type + numeric value (RFC 8866 §5.8)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "b=AS:128",
      "b=TIAS:96000",
      "t=0 0",
    })
    local doc = base.match(text)
    assert.is_table(doc.session.bandwidths)
    assert.equal(2, #doc.session.bandwidths)
    assert.equal("AS",   doc.session.bandwidths[1].type)
    assert.equal(128,    doc.session.bandwidths[1].value)
    assert.is_number(doc.session.bandwidths[1].value)
    assert.equal("TIAS", doc.session.bandwidths[2].type)
    assert.equal(96000,  doc.session.bandwidths[2].value)
  end)

  -- NOT-SPEC: library
  it("session.bandwidths is an empty array when no b= lines", function()
    local doc = base.match(minimal())
    assert.is_table(doc.session.bandwidths)
    assert.equal(0, #doc.session.bandwidths)
  end)

  -- NOT-SPEC: library
  it("rejects b= with non-digit bandwidth value", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "b=AS:fast",
      "t=0 0",
    })
    assert.is_nil(base.match(text))
  end)

  -- NOT-SPEC: library
  it("rejects b= missing colon", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "b=AS 128",
      "t=0 0",
    })
    assert.is_nil(base.match(text))
  end)

end)

describe("base SDP grammar — media array shape (Phase 2.C)", function()

  -- NOT-SPEC: library
  it("doc.media is an empty array when no media blocks present", function()
    local doc = base.match(minimal())
    assert.is_table(doc.media)
    assert.equal(0, #doc.media)
  end)

  -- NOT-SPEC: library
  it("doc.media has one entry per m= section", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000" },
      { "m=audio 49172 RTP/AVP 0"  },
    }))
    assert.is_table(doc.media)
    assert.equal(2, #doc.media)
  end)

  -- NOT-SPEC: library
  it("captures media-level info when i= present", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96",
        "i=Video stream description",
        "a=rtpmap:96 H264/90000" },
    }))
    assert.equal("Video stream description", doc.media[1].info)
  end)

  -- NOT-SPEC: library
  it("captures media-level connection", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96",
        "c=IN IP4 239.1.1.1/127",
        "a=rtpmap:96 H264/90000" },
    }))
    assert.is_table(doc.media[1].connection)
    assert.equal("IP4",            doc.media[1].connection.addr_type)
    assert.equal("239.1.1.1/127",  doc.media[1].connection.address)
  end)

  -- NOT-SPEC: library
  it("captures media-level bandwidths as array of {type, value}", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96",
        "b=AS:5000",
        "b=TIAS:4500000",
        "a=rtpmap:96 H264/90000" },
    }))
    assert.equal(2, #doc.media[1].bandwidths)
    assert.equal("AS",       doc.media[1].bandwidths[1].type)
    assert.equal(5000,       doc.media[1].bandwidths[1].value)
    assert.equal("TIAS",     doc.media[1].bandwidths[2].type)
    assert.equal(4500000,    doc.media[1].bandwidths[2].value)
  end)

  -- NOT-SPEC: library
  it("media-level info / connection are nil when their lines are absent", function()
    -- Static PT 0 (PCMU) avoids needing rtpmap to exercise the
    -- "absent-optional-field" path.
    local doc = base.match(minimal(nil, { { "m=audio 49172 RTP/AVP 0" } }))
    assert.is_nil(doc.media[1].info)
    assert.is_nil(doc.media[1].connection)
    assert.is_table(doc.media[1].bandwidths)
    assert.equal(0, #doc.media[1].bandwidths)
  end)

end)

describe("base SDP grammar — timing, repeats, time zones (Phase 2.D)", function()

  -- NOT-SPEC: library
  it("captures doc.session.time_descriptions as an array (RFC 8866 §5.9)", function()
    local doc = base.match(minimal())
    assert.is_table(doc.session.time_descriptions)
    assert.equal(1, #doc.session.time_descriptions)
  end)

  -- NOT-SPEC: library
  it("captures t= start and stop as numbers (RFC 8866 §5.9)", function()
    local doc = base.match(minimal())
    local td = doc.session.time_descriptions[1]
    assert.is_number(td.start)
    assert.is_number(td.stop)
    assert.equal(0, td.start)
    assert.equal(0, td.stop)
  end)

  -- NOT-SPEC: library
  it("captures non-zero t= values", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "t=2873397496 2873404696",
    })
    local doc = base.match(text)
    assert.equal(2873397496, doc.session.time_descriptions[1].start)
    assert.equal(2873404696, doc.session.time_descriptions[1].stop)
  end)

  -- NOT-SPEC: library
  it("captures multiple time descriptions (multiple t=)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "t=0 0",
      "t=2873397496 2873404696",
    })
    local doc = base.match(text)
    assert.equal(2, #doc.session.time_descriptions)
    assert.equal(0,          doc.session.time_descriptions[1].start)
    assert.equal(2873397496, doc.session.time_descriptions[2].start)
  end)

  -- NOT-SPEC: library
  it("empty repeats array when t= has no following r= lines", function()
    local doc = base.match(minimal())
    assert.is_table(doc.session.time_descriptions[1].repeats)
    assert.equal(0, #doc.session.time_descriptions[1].repeats)
  end)

  -- NOT-SPEC: library
  it("captures r= with three tokens (interval, duration, one offset)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "t=2873397496 2873404696",
      "r=604800 3600 0",
    })
    local doc = base.match(text)
    local r = doc.session.time_descriptions[1].repeats[1]
    assert.is_table(r)
    assert.equal("604800", r.interval)
    assert.equal("3600",   r.duration)
    assert.is_table(r.offsets)
    assert.equal(1, #r.offsets)
    assert.equal("0", r.offsets[1])
  end)

  -- NOT-SPEC: library
  it("captures r= with multiple offsets", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "t=2873397496 2873404696",
      "r=604800 3600 0 90000",
    })
    local doc = base.match(text)
    local r = doc.session.time_descriptions[1].repeats[1]
    assert.equal(2, #r.offsets)
    assert.equal("0",     r.offsets[1])
    assert.equal("90000", r.offsets[2])
  end)

  -- NOT-SPEC: library
  it("captures typed-time suffix in r= tokens (7d, 1h, 25h)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "t=2873397496 2873404696",
      "r=7d 1h 0 25h",
    })
    local doc = base.match(text)
    local r = doc.session.time_descriptions[1].repeats[1]
    assert.equal("7d",  r.interval)
    assert.equal("1h",  r.duration)
    assert.equal("0",   r.offsets[1])
    assert.equal("25h", r.offsets[2])
  end)

  -- NOT-SPEC: library
  it("rejects t= with non-digit value", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "t=abc 0",
    })
    assert.is_nil(base.match(text))
  end)

  -- NOT-SPEC: library
  it("rejects r= with only 2 tokens (RFC 8866 §5.10 requires ≥3)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "t=2873397496 2873404696",
      "r=604800 3600",
    })
    assert.is_nil(base.match(text))
  end)

  -- NOT-SPEC: library
  it("doc.session.time_zones is nil when no z= line", function()
    local doc = base.match(minimal())
    assert.is_nil(doc.session.time_zones)
  end)

  -- NOT-SPEC: library
  it("captures z= as an array of pairs (RFC 8866 §5.11)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "t=0 0",
      "z=2882844526 -1h 2898848070 0",
    })
    local doc = base.match(text)
    assert.is_table(doc.session.time_zones)
    assert.equal(2, #doc.session.time_zones)
    assert.equal("2882844526", doc.session.time_zones[1].adjustment_time)
    assert.equal("-1h",        doc.session.time_zones[1].offset)
    assert.equal("2898848070", doc.session.time_zones[2].adjustment_time)
    assert.equal("0",          doc.session.time_zones[2].offset)
  end)

  -- NOT-SPEC: library
  it("z= offset supports signed typed-time (+ and -)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "t=0 0",
      "z=2882844526 +3600 2898848070 -2h",
    })
    local doc = base.match(text)
    assert.equal("+3600", doc.session.time_zones[1].offset)
    assert.equal("-2h",   doc.session.time_zones[2].offset)
  end)

  -- NOT-SPEC: library
  it("rejects z= with odd number of tokens (must be pairs)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "t=0 0",
      "z=2882844526 -1h 2898848070",
    })
    assert.is_nil(base.match(text))
  end)

end)

describe("base SDP grammar — media line + attributes (Phase 2.E)", function()

  -- NOT-SPEC: library
  it("captures m= fields flat at media-block top level (RFC 8866 §5.14)", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000" },
    }))
    local m = doc.media[1]
    assert.equal("video",    m.media)
    assert.equal(49170,      m.port)
    assert.is_number(m.port)
    assert.equal("RTP/AVP",  m.proto)
    assert.is_table(m.fmts)
    assert.equal(1, #m.fmts)
    assert.equal("96", m.fmts[1])
    assert.is_nil(m.port_count)
  end)

  -- NOT-SPEC: library
  it("captures m= port_count when present (port/count form)", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170/2 RTP/AVP 96", "a=rtpmap:96 H264/90000" },
    }))
    assert.equal(49170, doc.media[1].port)
    assert.equal(2,     doc.media[1].port_count)
    assert.is_number(doc.media[1].port_count)
  end)

  -- NOT-SPEC: library
  it("captures m= with multiple format tokens", function()
    -- Dynamic PTs require matching a=rtpmap (RFC 8866 §8.2.3); include them
    -- so the test focuses on fmts-array capture, not the semantic check.
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96 97 98",
        "a=rtpmap:96 H264/90000",
        "a=rtpmap:97 H265/90000",
        "a=rtpmap:98 VP9/90000" },
    }))
    assert.same({"96", "97", "98"}, doc.media[1].fmts)
  end)

  -- NOT-SPEC: library
  it("captures proto with slashes verbatim", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/SAVP 96",
        "a=rtpmap:96 H264/90000" },
    }))
    assert.equal("RTP/SAVP", doc.media[1].proto)
  end)

  -- NOT-SPEC: library
  it("rejects m= missing the fmt token (RFC 8866 §5.14 requires ≥1 fmt)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=video 49170 RTP/AVP",
    })
    assert.is_nil(base.match(text))
  end)

  -- NOT-SPEC: library
  it("rejects m= with non-digit port", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=video abc RTP/AVP 96",
    })
    assert.is_nil(base.match(text))
  end)

  -- NOT-SPEC: library
  it("captures session-level a= as array of {name, value} (RFC 8866 §5.13)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=tool:libsdp 1.0",
      "a=type:broadcast",
      "a=recvonly",
    })
    local doc = base.match(text)
    assert.is_table(doc.session.attributes)
    assert.equal(3, #doc.session.attributes)
    assert.equal("tool",         doc.session.attributes[1].name)
    assert.equal("libsdp 1.0",   doc.session.attributes[1].value)
    assert.equal("type",         doc.session.attributes[2].name)
    assert.equal("broadcast",    doc.session.attributes[2].value)
    -- Flag attribute (no colon): name only, no value field.
    assert.equal("recvonly",     doc.session.attributes[3].name)
    assert.is_nil(doc.session.attributes[3].value)
  end)

  -- NOT-SPEC: library
  it("captures media-level a= attributes (rtpmap + fmtp decomposed)", function()
    -- Phase 4.A decomposes rtpmap; Phase 4.B decomposes fmtp.
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96",
        "a=rtpmap:96 H264/90000",
        "a=fmtp:96 profile-level-id=42801f",
        "a=sendonly" },
    }))
    local attrs = doc.media[1].attributes
    assert.equal(3, #attrs)
    assert.equal("rtpmap", attrs[1].name)
    assert.equal(96,       attrs[1].payload_type)
    assert.equal("H264",   attrs[1].encoding)
    assert.equal(90000,    attrs[1].clock_rate)
    assert.is_nil(attrs[1].value)
    assert.equal("fmtp",   attrs[2].name)
    assert.equal(96,       attrs[2].payload_type)
    assert.equal("42801f", attrs[2].params["profile-level-id"])
    assert.is_nil(attrs[2].value)
    assert.is_nil(attrs[2].raw)
    assert.equal("sendonly", attrs[3].name)
    assert.is_nil(attrs[3].value)
  end)

  -- NOT-SPEC: library
  it("session.attributes and media.attributes are empty arrays when absent", function()
    -- Using static PT 0 (PCMU) so the dynamic-PT-requires-rtpmap check
    -- (RFC 8866 §8.2.3, Phase 3.B) doesn't fire.
    local doc = base.match(minimal(nil, { { "m=audio 49172 RTP/AVP 0" } }))
    assert.is_table(doc.session.attributes)
    assert.equal(0, #doc.session.attributes)
    assert.is_table(doc.media[1].attributes)
    assert.equal(0, #doc.media[1].attributes)
  end)

  -- NOT-SPEC: library
  it("attribute values may contain colons (ts-refclk now fully decomposed, Phase 4.C)", function()
    -- Static PT 0 dodges the dynamic-PT-requires-rtpmap check; we're
    -- testing colon handling in attribute values here, not semantic checks.
    -- Phase 4.C decomposes ts-refclk into typed fields (was a generic
    -- string value through Phase 4.B).
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-1D-9A-FF-FE-2C-32-0F:0" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("ts-refclk", a.name)
    assert.equal("ptp", a.source)
    assert.equal("IEEE1588-2008", a.version)
    assert.equal("00-1D-9A-FF-FE-2C-32-0F", a.grandmaster)
    assert.equal("0", a.domain)
    assert.is_nil(a.value)
  end)

end)

describe("base SDP grammar — full round-trip doc shape (Phase 2 end)", function()

  -- NOT-SPEC: library
  it("produces a complete, structured doc for a realistic SDP", function()
    local text = lines_to_sdp({
      "v=0",
      "o=alice 2890844526 2890844527 IN IP4 192.0.2.1",
      "s=Realistic Session",
      "i=A test session",
      "u=http://example.com/info",
      "e=alice@example.com",
      "p=+1 555 1234",
      "c=IN IP4 224.2.17.12/127",
      "b=AS:5000",
      "t=2873397496 2873404696",
      "r=604800 3600 0 90000",
      "z=2882844526 -1h 2898848070 0",
      "a=tool:libsdp 1.0",
      "m=video 49170 RTP/AVP 96",
      "i=Camera 1",
      "c=IN IP4 239.1.1.1/127",
      "b=AS:4500000",
      "a=rtpmap:96 H264/90000",
      "a=sendonly",
      "m=audio 49172 RTP/AVP 0",
      "a=rtpmap:0 PCMU/8000",
    })
    local doc = base.match(text)
    assert.is_table(doc)

    -- Top level
    assert.equal("0", doc.version)
    assert.equal("alice",       doc.origin.username)
    assert.equal("2890844526",  doc.origin.sess_id)

    -- Session
    assert.equal("Realistic Session", doc.session.name)
    assert.equal("A test session",    doc.session.info)
    assert.equal("http://example.com/info", doc.session.uri)
    assert.equal(1, #doc.session.emails)
    assert.equal(1, #doc.session.phones)
    assert.equal("224.2.17.12/127", doc.session.connection.address)
    assert.equal(1, #doc.session.bandwidths)
    assert.equal(5000, doc.session.bandwidths[1].value)
    assert.equal(1, #doc.session.time_descriptions)
    assert.equal(2873397496, doc.session.time_descriptions[1].start)
    assert.equal(1, #doc.session.time_descriptions[1].repeats)
    assert.equal(2, #doc.session.time_zones)
    assert.equal(1, #doc.session.attributes)

    -- Media
    assert.equal(2, #doc.media)
    assert.equal("video", doc.media[1].media)
    assert.equal(49170,   doc.media[1].port)
    assert.equal("Camera 1", doc.media[1].info)
    assert.equal("239.1.1.1/127", doc.media[1].connection.address)
    assert.equal(2, #doc.media[1].attributes)
    assert.equal("audio", doc.media[2].media)
    assert.equal(1, #doc.media[2].attributes)
  end)

end)

describe("base SDP grammar — connection-address value-form (Phase 3.C, RFC 8866 §5.7 / §9)", function()

  local function build(c_line)
    return lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      c_line,
      "t=0 0",
    })
  end

  describe("IPv4", function()

    -- NOT-SPEC: library
    it("accepts unicast with no suffix", function()
      local doc, ctx = base.match(build("c=IN IP4 192.0.2.1"))
      assert.is_table(doc)
      assert.equal(0, #ctx.findings)
    end)

    -- NOT-SPEC: library
    it("accepts multicast with /ttl", function()
      local doc, ctx = base.match(build("c=IN IP4 224.2.17.12/127"))
      assert.is_table(doc)
      assert.equal(0, #ctx.findings)
    end)

    -- NOT-SPEC: library
    it("accepts multicast with /ttl/numaddr", function()
      local doc, ctx = base.match(build("c=IN IP4 239.1.1.1/127/3"))
      assert.is_table(doc)
      assert.equal(0, #ctx.findings)
    end)

    -- NOT-SPEC: library
    it("accepts TTL = 0 (RFC 8866 §5.7 explicitly permits zero)", function()
      local doc, ctx = base.match(build("c=IN IP4 224.0.0.1/0"))
      assert.is_table(doc)
      assert.equal(0, #ctx.findings)
    end)

    -- NOT-SPEC: library
    it("rejects multicast without /ttl (sdp.c.ipv4-multicast.ttl-required)", function()
      local doc, ctx = base.match(build("c=IN IP4 224.2.17.12"))
      assert.is_nil(doc)
      assert.equal("sdp.c.ipv4-multicast.ttl-required", ctx.findings[1].id)
    end)

    -- NOT-SPEC: library
    it("rejects multicast with TTL > 255 (sdp.c.ipv4-multicast.ttl-out-of-range)", function()
      local doc, ctx = base.match(build("c=IN IP4 224.2.17.12/256"))
      assert.is_nil(doc)
      assert.equal("sdp.c.ipv4-multicast.ttl-out-of-range", ctx.findings[1].id)
    end)

    -- NOT-SPEC: library
    it("rejects multicast with numaddr=0 (sdp.c.ipv4-multicast.numaddr-invalid)", function()
      local doc, ctx = base.match(build("c=IN IP4 224.2.17.12/127/0"))
      assert.is_nil(doc)
      assert.equal("sdp.c.ipv4-multicast.numaddr-invalid", ctx.findings[1].id)
    end)

    -- NOT-SPEC: library
    it("rejects unicast with a /suffix (sdp.c.ipv4-unicast.suffix-not-allowed)", function()
      local doc, ctx = base.match(build("c=IN IP4 192.0.2.1/127"))
      assert.is_nil(doc)
      assert.equal("sdp.c.ipv4-unicast.suffix-not-allowed", ctx.findings[1].id)
    end)

    -- NOT-SPEC: library
    it("rejects malformed IPv4 (sdp.c.address.invalid-ipv4)", function()
      local doc, ctx = base.match(build("c=IN IP4 256.0.0.1"))
      assert.is_nil(doc)
      assert.equal("sdp.c.address.invalid-ipv4", ctx.findings[1].id)
    end)

  end)

  describe("IPv6", function()

    -- NOT-SPEC: library
    it("accepts unicast with no suffix", function()
      local doc, ctx = base.match(build("c=IN IP6 2001:db8::1"))
      assert.is_table(doc)
      assert.equal(0, #ctx.findings)
    end)

    -- NOT-SPEC: library
    it("accepts multicast with no suffix (numaddr is optional)", function()
      local doc, ctx = base.match(build("c=IN IP6 ff02::1"))
      assert.is_table(doc)
      assert.equal(0, #ctx.findings)
    end)

    -- NOT-SPEC: library
    it("accepts multicast with /<numaddr>", function()
      local doc, ctx = base.match(build("c=IN IP6 ff02::1/3"))
      assert.is_table(doc)
      assert.equal(0, #ctx.findings)
    end)

    -- NOT-SPEC: library
    it("rejects multicast with a TTL-style /N/M suffix (sdp.c.ipv6-multicast.suffix-form-invalid)", function()
      local doc, ctx = base.match(build("c=IN IP6 ff02::1/127/3"))
      assert.is_nil(doc)
      assert.equal("sdp.c.ipv6-multicast.suffix-form-invalid", ctx.findings[1].id)
    end)

    -- NOT-SPEC: library
    it("rejects multicast with numaddr=0", function()
      local doc, ctx = base.match(build("c=IN IP6 ff02::1/0"))
      assert.is_nil(doc)
      assert.equal("sdp.c.ipv6-multicast.numaddr-invalid", ctx.findings[1].id)
    end)

    -- NOT-SPEC: library
    it("rejects unicast with a /suffix", function()
      local doc, ctx = base.match(build("c=IN IP6 2001:db8::1/64"))
      assert.is_nil(doc)
      assert.equal("sdp.c.ipv6-unicast.suffix-not-allowed", ctx.findings[1].id)
    end)

    -- NOT-SPEC: library
    it("rejects malformed IPv6 (sdp.c.address.invalid-ipv6)", function()
      local doc, ctx = base.match(build("c=IN IP6 gggg::1"))
      assert.is_nil(doc)
      assert.equal("sdp.c.address.invalid-ipv6", ctx.findings[1].id)
    end)

  end)

  describe("scope: media-level c= is also checked", function()

    -- NOT-SPEC: library — Phase 6.H moved this check in-grammar (Cmt on
    -- c_value) so findings now carry line/col instead of the
    -- session.connection / media[N].connection field_path the doc-walk
    -- used to emit. Same check, better diagnostic shape.
    it("media-level IPv4 multicast missing TTL is rejected", function()
      local doc, ctx = base.match(lines_to_sdp({
        "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
        "m=audio 49172 RTP/AVP 0",
        "c=IN IP4 224.2.17.12",  -- missing /ttl, line 6
      }))
      assert.is_nil(doc)
      assert.equal("sdp.c.ipv4-multicast.ttl-required", ctx.findings[1].id)
      assert.equal(6, ctx.findings[1].line)
    end)

  end)

  describe("policy interaction", function()

    -- NOT-SPEC: library
    it("policy = 'off' bypasses the check", function()
      local doc, ctx = base.match(
        build("c=IN IP4 192.0.2.1/127"),  -- normally an error
        { policy = { ["sdp.c.ipv4-unicast.suffix-not-allowed"] = "off" } }
      )
      assert.is_table(doc)
      assert.equal(0, #ctx.findings)
    end)

    -- NOT-SPEC: library
    it("policy = 'warn' downgrades, doc returned with warning finding", function()
      local doc, ctx = base.match(
        build("c=IN IP4 192.0.2.1/127"),
        { policy = { ["sdp.c.ipv4-unicast.suffix-not-allowed"] = "warn" } }
      )
      assert.is_table(doc)
      assert.equal("warn", ctx.findings[1].severity)
    end)

  end)

end)

describe("base SDP grammar — dynamic-PT requires rtpmap (Phase 3.B, RFC 8866 §8.2.3)", function()

  local function build(media_block)
    return lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      table.unpack(media_block),
    })
  end

  it("accepts dynamic PT 96 when a matching a=rtpmap is present", function()
    local doc, ctx = base.match(build({
      "m=video 49170 RTP/AVP 96",
      "a=rtpmap:96 H264/90000",
    }))
    assert.is_table(doc)
    assert.equal(0, #ctx.findings)
  end)

  it("rejects dynamic PT 96 with no matching a=rtpmap (RFC 8866 §8.2.3)", function()
    local doc, ctx = base.match(build({
      "m=video 49170 RTP/AVP 96",
    }))
    assert.is_nil(doc)
    assert.equal(1, #ctx.findings)
    local f = ctx.findings[1]
    assert.equal("sdp.m.rtpmap-required-for-dynamic-pt", f.id)
    assert.equal("RFC 8866 §8.2.3", f.spec_ref)
    assert.equal("MISSING_FIELD",   f.code)
    assert.equal("error",           f.severity)
    assert.equal("media[1].attributes[rtpmap]", f.field_path)
  end)

  it("accepts static PT 0 (PCMU) without rtpmap (static, not in 96-127)", function()
    local doc, ctx = base.match(build({ "m=audio 49172 RTP/AVP 0" }))
    assert.is_table(doc)
    assert.equal(0, #ctx.findings)
  end)

  it("accepts static PT 31 (H261) without rtpmap", function()
    local doc, ctx = base.match(build({ "m=video 49170 RTP/AVP 31" }))
    assert.is_table(doc)
    assert.equal(0, #ctx.findings)
  end)

  it("rejects on the FIRST missing rtpmap when several dynamic PTs are unmatched", function()
    local doc, ctx = base.match(build({
      "m=video 49170 RTP/AVP 96 97",
      -- no rtpmap for either
    }))
    assert.is_nil(doc)
    -- fail_on_first default: at least one finding, stops there.
    assert.is_truthy(#ctx.findings >= 1)
  end)

  it("collects all missing-rtpmap findings when fail_on_first = false", function()
    local doc, ctx = base.match(build({
      "m=video 49170 RTP/AVP 96 97 98",
    }), { fail_on_first = false })
    -- Match still succeeds because record() returns true when not failing.
    assert.is_table(doc)
    assert.equal(3, #ctx.findings)
    for _, f in ipairs(ctx.findings) do
      assert.equal("sdp.m.rtpmap-required-for-dynamic-pt", f.id)
    end
  end)

  it("skips the check entirely when policy['sdp.m.rtpmap-required-for-dynamic-pt'] = 'off'", function()
    local doc, ctx = base.match(build({
      "m=video 49170 RTP/AVP 96",
    }), { policy = { ["sdp.m.rtpmap-required-for-dynamic-pt"] = "off" } })
    assert.is_table(doc)
    assert.equal(0, #ctx.findings)
  end)

  it("downgrades to warning when policy maps the id to 'warn'", function()
    local doc, ctx = base.match(build({
      "m=video 49170 RTP/AVP 96",
    }), { policy = { ["sdp.m.rtpmap-required-for-dynamic-pt"] = "warn" } })
    assert.is_table(doc, "warn-severity findings do not fail the match")
    assert.equal(1, #ctx.findings)
    assert.equal("warn", ctx.findings[1].severity)
  end)

  it("does NOT fire for non-RTP proto (e.g., udp)", function()
    -- The check is gated on proto containing "RTP".
    local doc, ctx = base.match(build({ "m=video 49170 udp 96" }))
    assert.is_table(doc)
    assert.equal(0, #ctx.findings)
  end)

  it("fires only on the offending media block when multiple are present", function()
    local doc, ctx = base.match(build({
      "m=audio 49172 RTP/AVP 0",
      "m=video 49170 RTP/AVP 96",
    }))
    assert.is_nil(doc)
    -- field_path should name media[2] (the violator), not media[1].
    assert.equal("media[2].attributes[rtpmap]", ctx.findings[1].field_path)
  end)

  it("uses the registry message_template", function()
    local doc, ctx = base.match(build({ "m=video 49170 RTP/AVP 96" }))
    assert.is_nil(doc)
    assert.matches("dynamic RTP payload type", ctx.findings[1].message)
  end)

end)

describe("base SDP grammar — match() wrapper + ctx threading (Phase 3.A)", function()

  -- NOT-SPEC: library
  it("base.match(text) returns (doc, ctx)", function()
    local doc, ctx = base.match(minimal())
    assert.is_table(doc)
    assert.is_table(ctx)
    assert.is_table(ctx.findings)
  end)

  -- NOT-SPEC: library
  it("ctx.findings is empty on valid input with no semantic checks active yet", function()
    -- Phase 3.A ships an empty Cmt scaffold — no checks fire. Phase 3.B+
    -- will exercise this path.
    local _, ctx = base.match(minimal())
    assert.equal(0, #ctx.findings)
  end)

  -- NOT-SPEC: library
  it("ctx.fail_on_first defaults to true", function()
    local _, ctx = base.match(minimal())
    assert.is_true(ctx.fail_on_first)
  end)

  -- NOT-SPEC: library
  it("opts.fail_on_first = false threads to ctx", function()
    local _, ctx = base.match(minimal(), { fail_on_first = false })
    assert.is_false(ctx.fail_on_first)
  end)

  -- NOT-SPEC: library
  it("opts.policy threads to ctx", function()
    local p = { ["sdp.v.must-be-zero"] = "warn" }
    local _, ctx = base.match(minimal(), { policy = p })
    assert.equal(p, ctx.policy)
  end)

  -- NOT-SPEC: library
  it("opts.ctx lets caller share a buffer across matches", function()
    local shared = { findings = {}, fail_on_first = false }
    base.match(minimal(), { ctx = shared })
    base.match(minimal(), { ctx = shared })
    -- No findings emitted yet (no Phase 3.B+ checks), but the same ctx is
    -- threaded through both matches.
    assert.equal(0, #shared.findings)
  end)

  -- NOT-SPEC: library
  it("returns (nil, ctx) on grammar match failure", function()
    local doc, ctx = base.match("not a valid sdp")
    assert.is_nil(doc)
    assert.is_table(ctx)
  end)

end)

describe("base SDP grammar — Phase 4.A attribute decomposition", function()

  -- RFC 8866 §6.6: rtpmap-value = payload-type SP encoding-name "/" clock-rate
  --                                [ "/" encoding-params ]
  -- §6.6 normative: "the payload type number is indicated in a 7-bit field,
  -- limiting the values to inclusively between 0 and 127".
  describe("a=rtpmap (RFC 8866 §6.6)", function()
    -- SPEC: RFC 8866 §6.6
    it("decomposes rtpmap value into payload_type/encoding/clock_rate", function()
      local doc = base.match(minimal(nil, {
        { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000" },
      }))
      local a = doc.media[1].attributes[1]
      assert.equal("rtpmap", a.name)
      assert.equal(96,       a.payload_type)
      assert.equal("H264",   a.encoding)
      assert.equal(90000,    a.clock_rate)
      assert.is_nil(a.channels)
      assert.is_nil(a.value)  -- decomposed; no string value
    end)

    -- SPEC: RFC 8866 §6.6
    it("decomposes rtpmap with channels (audio encoding-params)", function()
      local doc = base.match(minimal(nil, {
        { "m=audio 49172 RTP/AVP 96", "a=rtpmap:96 L24/48000/2" },
      }))
      local a = doc.media[1].attributes[1]
      assert.equal("rtpmap", a.name)
      assert.equal(96,       a.payload_type)
      assert.equal("L24",    a.encoding)
      assert.equal(48000,    a.clock_rate)
      assert.equal(2,        a.channels)
    end)

    -- SPEC: RFC 8866 §6.6 (PT range 0..127)
    it("accepts payload-type 0 (static PCMU)", function()
      local doc = base.match(minimal(nil, {
        { "m=audio 49172 RTP/AVP 0", "a=rtpmap:0 PCMU/8000" },
      }))
      local a = doc.media[1].attributes[1]
      assert.equal(0, a.payload_type)
    end)

    -- SPEC: RFC 8866 §6.6 (PT range 0..127)
    it("rejects payload-type 128 (out of 7-bit range)", function()
      local doc = base.match(minimal(nil, {
        { "m=video 49170 RTP/AVP 96", "a=rtpmap:128 H264/90000" },
      }))
      assert.is_nil(doc)
    end)
  end)

  -- RFC 5888 §4: a=mid value is an identification-tag, which uses the RFC 8866
  -- §9 token grammar. Identification-tag MUST be unique within the SDP.
  describe("a=mid (RFC 5888 §4)", function()
    -- SPEC: RFC 5888 §4
    it("decomposes mid value into a tag field", function()
      local doc = base.match(minimal(nil, {
        { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000",
          "a=mid:video1" },
      }))
      local a = doc.media[1].attributes[2]
      assert.equal("mid",    a.name)
      assert.equal("video1", a.tag)
      assert.is_nil(a.value)
    end)

    -- SPEC: RFC 5888 §4 (identification-tag MUST be unique)
    it("rejects duplicate a=mid tags across media blocks", function()
      local doc, ctx = base.match(minimal(nil, {
        { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000", "a=mid:1" },
        { "m=audio 49172 RTP/AVP 0",  "a=mid:1" },
      }))
      assert.is_nil(doc)
      assert.equal(1, #ctx.findings)
      assert.equal("sdp.a.mid.duplicate-tag", ctx.findings[1].id)
    end)

    -- SPEC: RFC 5888 §4 / RFC 8866 §9 token char-set
    it("rejects mid with a space (not a valid §9 token)", function()
      local doc = base.match(minimal(nil, {
        { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000",
          "a=mid:tag with space" },
      }))
      assert.is_nil(doc)
    end)
  end)

  -- RFC 8866 §6.4: ptime-value = non-zero-int-or-real
  describe("a=ptime (RFC 8866 §6.4)", function()
    -- SPEC: RFC 8866 §6.4
    it("decomposes ptime value as a number", function()
      local doc = base.match(minimal(nil, {
        { "m=audio 49172 RTP/AVP 0", "a=ptime:20" },
      }))
      local a = doc.media[1].attributes[1]
      assert.equal("ptime", a.name)
      assert.equal(20,      a.value)
      assert.is_number(a.value)
    end)

    -- SPEC: RFC 8866 §6.4 + §9 non-zero-real
    it("accepts fractional ptime per non-zero-real ABNF", function()
      local doc = base.match(minimal(nil, {
        { "m=audio 49172 RTP/AVP 0", "a=ptime:2.5" },
      }))
      assert.equal(2.5, doc.media[1].attributes[1].value)
    end)

    -- SPEC: RFC 8866 §6.4 (non-zero-int-or-real; "0" excluded by ABNF)
    it("rejects ptime:0 (ABNF excludes zero)", function()
      local doc = base.match(minimal(nil, {
        { "m=audio 49172 RTP/AVP 0", "a=ptime:0" },
      }))
      assert.is_nil(doc)
    end)
  end)

  -- RFC 8866 §6.5: maxptime-value = non-zero-int-or-real
  describe("a=maxptime (RFC 8866 §6.5)", function()
    -- SPEC: RFC 8866 §6.5
    it("decomposes maxptime value as a number", function()
      local doc = base.match(minimal(nil, {
        { "m=audio 49172 RTP/AVP 0", "a=maxptime:30" },
      }))
      local a = doc.media[1].attributes[1]
      assert.equal("maxptime", a.name)
      assert.equal(30,         a.value)
    end)
  end)

  -- RFC 8866 §6.13: framerate-value = non-zero-int-or-real
  describe("a=framerate (RFC 8866 §6.13)", function()
    -- SPEC: RFC 8866 §6.13
    it("decomposes integer framerate value as a number", function()
      local doc = base.match(minimal(nil, {
        { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000",
          "a=framerate:60" },
      }))
      local a = doc.media[1].attributes[2]
      assert.equal("framerate", a.name)
      assert.equal(60,          a.value)
    end)

    -- SPEC: RFC 8866 §6.13 ("Decimal representations of fractional values are
    --                       allowed.")
    it("decomposes fractional framerate", function()
      local doc = base.match(minimal(nil, {
        { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000",
          "a=framerate:29.97" },
      }))
      assert.equal(29.97, doc.media[1].attributes[2].value)
    end)
  end)

  -- RFC 8866 §6.14: quality-value = zero-based-integer
  describe("a=quality (RFC 8866 §6.14)", function()
    -- SPEC: RFC 8866 §6.14
    it("decomposes quality value as a number", function()
      local doc = base.match(minimal(nil, {
        { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000",
          "a=quality:10" },
      }))
      local a = doc.media[1].attributes[2]
      assert.equal("quality", a.name)
      assert.equal(10,        a.value)
    end)

    -- SPEC: RFC 8866 §6.14 + §9 zero-based-integer (allows "0")
    it("accepts quality:0 (zero-based-integer)", function()
      local doc = base.match(minimal(nil, {
        { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000",
          "a=quality:0" },
      }))
      assert.equal(0, doc.media[1].attributes[2].value)
    end)
  end)

  -- NOT-SPEC: library — generic-attr fallback must still work for unknown attrs.
  it("unknown attributes still land in the generic {name, value=string} shape", function()
    local doc = base.match(lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0", "a=tool:libsdp 1.0",
    }))
    local a = doc.session.attributes[1]
    assert.equal("tool",       a.name)
    assert.equal("libsdp 1.0", a.value)
  end)

  -- NOT-SPEC: library — flag-attr (no value) keeps name-only shape.
  it("flag attributes keep name-only shape", function()
    local doc = base.match(lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0", "a=recvonly",
    }))
    local a = doc.session.attributes[1]
    assert.equal("recvonly", a.name)
    assert.is_nil(a.value)
  end)

end)

describe("base SDP grammar — Phase 4.B fmtp decomposition (RFC 8866 §6.15)", function()

  -- SPEC: RFC 8866 §6.15
  it("decomposes single k=v fmtp param", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000",
        "a=fmtp:96 profile-level-id=42801f" },
    }))
    local a = doc.media[1].attributes[2]
    assert.equal("fmtp", a.name)
    assert.equal(96,     a.payload_type)
    assert.is_table(a.params)
    assert.equal("42801f", a.params["profile-level-id"])
    assert.is_nil(a.raw)
    assert.is_nil(a.value)
  end)

  -- SPEC: RFC 8866 §6.15
  it("decomposes multiple semicolon-separated k=v params", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000",
        "a=fmtp:96 profile-level-id=42e016;max-mbps=108000;max-fs=3600" },
    }))
    local p = doc.media[1].attributes[2].params
    assert.equal("42e016", p["profile-level-id"])
    assert.equal("108000", p["max-mbps"])
    assert.equal("3600",   p["max-fs"])
  end)

  -- SPEC: RFC 8866 §6.15 + ST 2110-20:2022 §7.1 bare-flag tokens (interlace,
  -- segmented). At the base tier we accept bare tokens as flags; ST 2110-20
  -- narrowing comes in Phase 6.
  it("decomposes bare-flag tokens as params[flag]=true", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 raw/90000",
        "a=fmtp:96 sampling=YCbCr-4:2:2;width=1920;interlace;segmented" },
    }))
    local p = doc.media[1].attributes[2].params
    assert.equal("YCbCr-4:2:2", p.sampling)
    assert.equal("1920",        p.width)
    assert.is_true(p.interlace)
    assert.is_true(p.segmented)
  end)

  -- SPEC: RFC 8866 §6.15
  -- DTMF telephone-event uses non-k=v form (RFC 4733); spec ABNF
  -- (format-specific-params = byte-string) tolerates this. We capture the
  -- byte-string as raw and do not populate params.
  it("non-decomposable fmtp (DTMF) lands as raw byte-string", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 101", "a=rtpmap:101 telephone-event/8000",
        "a=fmtp:101 0-15,256-511" },
    }))
    local a = doc.media[1].attributes[2]
    assert.equal("fmtp", a.name)
    assert.equal(101,    a.payload_type)
    assert.is_nil(a.params)
    assert.equal("0-15,256-511", a.raw)
  end)

  -- NOT-SPEC: library — tolerance behavior for the common ';<SP>' form.
  it("tolerates optional whitespace after ';' between params", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000",
        "a=fmtp:96 profile-level-id=42e016; max-mbps=108000" },
    }))
    local p = doc.media[1].attributes[2].params
    assert.equal("42e016", p["profile-level-id"])
    assert.equal("108000", p["max-mbps"])
  end)

  -- NOT-SPEC: library — RFC 8866 §6.15 doesn't constrain whitespace around
  -- `=`; ST 2110-20 §7.1 will narrow this in Phase 6.
  it("tolerates whitespace around '=' at the base tier", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000",
        "a=fmtp:96 max-mbps = 108000" },
    }))
    local p = doc.media[1].attributes[2].params
    assert.equal("108000", p["max-mbps"])
  end)

  -- NOT-SPEC: library — trailing semicolons are a common convention; spec
  -- silent on rejection. Phase 5 will record a soft-syntactic finding
  -- (sdp.a.fmtp.trailing-semicolon, already in the registry). For 4.B we
  -- tolerate without emitting.
  it("tolerates trailing semicolon (Phase 5 will record a finding)", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000",
        "a=fmtp:96 profile-level-id=42e016;" },
    }))
    local p = doc.media[1].attributes[2].params
    assert.equal("42e016", p["profile-level-id"])
  end)

  -- SPEC: RFC 8866 §6.15 (PT in fmtp-value)
  it("rejects fmtp with no payload-type", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000",
        "a=fmtp: max-mbps=108000" },
    }))
    assert.is_nil(doc)
  end)

  -- SPEC: RFC 8866 §6.15 (format-specific-params = byte-string is `1*...` —
  -- empty params not allowed)
  it("rejects fmtp with PT but no params (empty byte-string)", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000",
        "a=fmtp:96" },
    }))
    assert.is_nil(doc)
  end)

end)

describe("base SDP grammar — Phase 4.C ts-refclk decomposition (RFC 7273 §4.8)", function()

  -- SPEC: RFC 7273 §4.8
  it("decomposes ntp= with hostport address", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=ts-refclk:ntp=192.0.2.1" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("ts-refclk", a.name)
    assert.equal("ntp",       a.source)
    assert.equal("192.0.2.1", a.address)
    assert.is_nil(a.traceable)
    assert.is_nil(a.value)
  end)

  -- SPEC: RFC 7273 §4.8 ntp-server-addr = hostport / "/traceable/"
  it("decomposes ntp=/traceable/ as traceable, no address", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=ts-refclk:ntp=/traceable/" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("ntp", a.source)
    assert.is_true(a.traceable)
    assert.is_nil(a.address)
  end)

  -- SPEC: RFC 7273 §4.8 + ST 2110-10:2017 §8.2 (bare-number domain form
  -- used in practice; RFC 7273 ABNF specifies 'domain-nmbr=N' but every
  -- real-world ST 2110 SDP uses ':N' bare; base tier accepts both).
  it("decomposes ptp=version:gmid:domain (bare-number domain)", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-1D-9A-FF-FE-2C-32-0F:127" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("ts-refclk",     a.name)
    assert.equal("ptp",           a.source)
    assert.equal("IEEE1588-2008", a.version)
    assert.equal("00-1D-9A-FF-FE-2C-32-0F", a.grandmaster)
    assert.equal("127",           a.domain)
    assert.is_nil(a.traceable)
  end)

  -- SPEC: RFC 7273 §4.8 — ptp domain is optional
  it("decomposes ptp=version:gmid with no domain", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-1D-9A-FF-FE-2C-32-0F" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("ptp", a.source)
    assert.equal("00-1D-9A-FF-FE-2C-32-0F", a.grandmaster)
    assert.is_nil(a.domain)
  end)

  -- SPEC: RFC 7273 §4.8 ptp-server = ... / "traceable"
  it("decomposes ptp=version:traceable", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=ts-refclk:ptp=IEEE1588-2008:traceable" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("ptp",           a.source)
    assert.equal("IEEE1588-2008", a.version)
    assert.is_true(a.traceable)
    assert.is_nil(a.grandmaster)
    assert.is_nil(a.domain)
  end)

  -- SPEC: RFC 7273 §4.8 bare clock-source names
  it("decomposes bare clock-source names (gps, gal, glonass, local)", function()
    for _, src in ipairs({ "gps", "gal", "glonass", "local" }) do
      local doc = base.match(minimal(nil, {
        { "m=audio 49172 RTP/AVP 0", "a=ts-refclk:" .. src },
      }))
      assert.is_truthy(doc, "failed to parse a=ts-refclk:" .. src)
      assert.equal(src, doc.media[1].attributes[1].source)
    end
  end)

  -- SPEC: RFC 7273 §4.8 private [":traceable"]
  it("decomposes 'private' with optional :traceable suffix", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0", "a=ts-refclk:private" },
    }))
    assert.equal("private", doc.media[1].attributes[1].source)
    assert.is_nil(doc.media[1].attributes[1].traceable)

    local doc2 = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0", "a=ts-refclk:private:traceable" },
    }))
    assert.equal("private", doc2.media[1].attributes[1].source)
    assert.is_true(doc2.media[1].attributes[1].traceable)
  end)

  -- SPEC: RFC 7273 §4.8 clksrc-ext (which ST 2110-10 §8.2 uses for
  -- 'localmac' — not promoted to a recognized clock source at the base
  -- tier; Phase 6 ST 2110 will narrow).
  it("clksrc-ext form: localmac=<mac> lands as source/value", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("ts-refclk",         a.name)
    assert.equal("localmac",          a.source)
    assert.equal("AA-BB-CC-DD-EE-FF", a.value)
  end)

end)

describe("base SDP grammar — Phase 4.C mediaclk decomposition (RFC 7273 §5.4)", function()

  -- SPEC: RFC 7273 §5.4 mediaclock = sender / ...
  it("decomposes mediaclk:sender", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0", "a=mediaclk:sender" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("mediaclk", a.name)
    assert.equal("sender",   a.mode)
    assert.is_nil(a.offset)
    assert.is_nil(a.rate)
  end)

  -- SPEC: RFC 7273 §5.4 direct [ "=" 1*DIGIT ]
  it("decomposes mediaclk:direct (bare form, no offset)", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0", "a=mediaclk:direct" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("direct", a.mode)
    assert.is_nil(a.offset)
  end)

  -- SPEC: RFC 7273 §5.4
  it("decomposes mediaclk:direct=0", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0", "a=mediaclk:direct=0" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("direct", a.mode)
    assert.equal(0, a.offset)
    assert.is_number(a.offset)
    assert.is_nil(a.rate)
  end)

  -- SPEC: RFC 7273 §5.4 rate = "rate=" integer "/" integer
  it("decomposes mediaclk:direct=0 rate=1/48000", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0", "a=mediaclk:direct=0 rate=1/48000" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("direct", a.mode)
    assert.equal(0,        a.offset)
    assert.is_table(a.rate)
    assert.equal(1,     a.rate.num)
    assert.equal(48000, a.rate.den)
  end)

  -- SPEC: RFC 7273 §5.4 ieee1722-streamid = "IEEE1722=" avb-stream-id (EUI64)
  it("decomposes mediaclk:IEEE1722=<eui64>", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=mediaclk:IEEE1722=00-11-22-FF-FE-33-44-55" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("IEEE1722", a.mode)
    assert.equal("00-11-22-FF-FE-33-44-55", a.stream_id)
  end)

  -- SPEC: RFC 7273 §5.4 mediaclock-ext = mediaclock-param-name [...]
  it("mediaclock-ext: unknown <token>=<value> lands as mode/value", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0", "a=mediaclk:foo=bar" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("foo", a.mode)
    assert.equal("bar", a.value)
  end)

  -- SPEC: RFC 7273 §5.4 [ media-clkid SP ] mediaclock
  it("decomposes optional id= prefix", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=mediaclk:id=base64tag sender" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("base64tag", a.id)
    assert.equal("sender",    a.mode)
  end)

  -- SPEC: RFC 7273 §5.4 media-clkid = "id=" [ "src:" ] media-clktag
  it("decomposes id=src:<tag> form, preserving src: prefix inline", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=mediaclk:id=src:base64tag sender" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("src:base64tag", a.id)
    assert.equal("sender",        a.mode)
  end)

end)

describe("base SDP grammar — Phase 4.D source-filter (RFC 4570 §3)", function()

  -- SPEC: RFC 4570 §3
  it("decomposes incl filter with IPv4 dest + one source", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 0",
        "c=IN IP4 239.1.1.1/127",
        "a=source-filter:incl IN IP4 239.1.1.1 192.0.2.1" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("source-filter", a.name)
    assert.equal("incl", a.filter_mode)
    assert.equal("IN",   a.net_type)
    assert.equal("IP4",  a.addr_type)
    assert.equal("239.1.1.1", a.dest_address)
    assert.is_table(a.src_addresses)
    assert.equal(1, #a.src_addresses)
    assert.equal("192.0.2.1", a.src_addresses[1])
  end)

  -- SPEC: RFC 4570 §3 (multiple src addresses allowed)
  it("decomposes excl filter with multiple source addresses", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 0",
        "c=IN IP4 239.1.1.1/127",
        "a=source-filter:excl IN IP4 239.1.1.1 192.0.2.1 192.0.2.2 192.0.2.3" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("excl", a.filter_mode)
    assert.equal(3, #a.src_addresses)
    assert.equal("192.0.2.3", a.src_addresses[3])
  end)

  -- SPEC: RFC 4570 §3 addrtype = "IP4" / "IP6" / "*"
  it("accepts '*' addrtype (FQDN form)", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 0",
        "a=source-filter:incl IN * sender.example.com source.example.com" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("*", a.addr_type)
    assert.equal("sender.example.com", a.dest_address)
    assert.equal("source.example.com", a.src_addresses[1])
  end)

  -- SPEC: RFC 4570 §3 requires at least one src address
  it("rejects source-filter with no source addresses", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 0",
        "a=source-filter:incl IN IP4 239.1.1.1" },
    }))
    assert.is_nil(doc)
  end)

end)

describe("base SDP grammar — Phase 4.D group (RFC 5888 §5)", function()

  -- SPEC: RFC 5888 §5
  it("decomposes group:DUP with two identification-tags", function()
    local doc = base.match(lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=group:DUP primary backup",
    }))
    local a = doc.session.attributes[1]
    assert.equal("group", a.name)
    assert.equal("DUP",   a.semantics)
    assert.is_table(a.tags)
    assert.equal(2, #a.tags)
    assert.equal("primary", a.tags[1])
    assert.equal("backup",  a.tags[2])
  end)

  -- SPEC: RFC 5888 §5 — *(SP identification-tag) is zero-or-more
  it("accepts group with no tags (zero-or-more per ABNF)", function()
    local doc = base.match(lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=group:LS",
    }))
    local a = doc.session.attributes[1]
    assert.equal("LS", a.semantics)
    assert.is_table(a.tags)
    assert.equal(0, #a.tags)
  end)

end)

describe("base SDP grammar — Phase 4.D ssrc / ssrc-group (RFC 5576 §10)", function()

  -- SPEC: RFC 5576 §10 Figure 4
  -- ssrc-attr = "ssrc:" ssrc-id SP attribute  where attribute = name[":"value]
  it("decomposes ssrc with attribute name:value form", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=ssrc:12345 cname:user@example.com" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("ssrc",       a.name)
    assert.equal(12345,        a.ssrc_id)
    assert.equal("cname",      a.attribute)
    assert.equal("user@example.com", a.value)
  end)

  -- SPEC: RFC 5576 §10 Figure 4 — bare attribute (no :value)
  it("decomposes ssrc with bare flag-form attribute", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=ssrc:12345 sendonly" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal(12345,      a.ssrc_id)
    assert.equal("sendonly", a.attribute)
    assert.is_nil(a.value)
  end)

  -- SPEC: RFC 5576 §10 Figure 4 — ssrc-id is 32-bit unsigned (0..2^32-1)
  it("accepts the maximum 32-bit ssrc-id", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=ssrc:4294967295 cname:max" },
    }))
    assert.equal(4294967295, doc.media[1].attributes[1].ssrc_id)
  end)

  -- SPEC: RFC 5576 §10 Figure 5
  -- ssrc-group-attr = "ssrc-group:" semantics *(SP ssrc-id)
  it("decomposes ssrc-group:FID with multiple ssrc-ids", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 0",
        "a=ssrc-group:FID 12345 67890" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("ssrc-group", a.name)
    assert.equal("FID",        a.semantics)
    assert.is_table(a.ssrc_ids)
    assert.equal(2, #a.ssrc_ids)
    assert.equal(12345, a.ssrc_ids[1])
    assert.equal(67890, a.ssrc_ids[2])
  end)

end)

describe("base SDP grammar — Phase 4.D msid (RFC 8830 §2)", function()

  -- SPEC: RFC 8830 §2 — msid-value = msid-id [SP msid-appdata]
  it("decomposes msid with appdata", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 0",
        "a=msid:stream-id track-id" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("msid",      a.name)
    assert.equal("stream-id", a.msid_id)
    assert.equal("track-id",  a.appdata)
  end)

  -- SPEC: RFC 8830 §2 — appdata is optional
  it("decomposes msid without appdata", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 0",
        "a=msid:stream-id" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("stream-id", a.msid_id)
    assert.is_nil(a.appdata)
  end)

end)

describe("base SDP grammar — Phase 4.E extmap (RFC 8285 §8)", function()

  -- SPEC: RFC 8285 §8 — mapentry SP extensionname
  it("decomposes extmap with id + URI (no direction, no attributes)", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=extmap:1 urn:ietf:params:rtp-hdrext:ssrc-audio-level" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("extmap", a.name)
    assert.equal(1,        a.id)
    assert.is_number(a.id)
    assert.is_nil(a.direction)
    assert.equal("urn:ietf:params:rtp-hdrext:ssrc-audio-level", a.uri)
    assert.is_nil(a.attributes)
  end)

  -- SPEC: RFC 8285 §8 — mapentry = "extmap:" 1*5DIGIT ["/" direction]
  it("decomposes extmap with id/direction prefix", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=extmap:5/sendonly urn:example:hdrext" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal(5,          a.id)
    assert.equal("sendonly", a.direction)
    assert.equal("urn:example:hdrext", a.uri)
  end)

  -- SPEC: RFC 8285 §8 — [SP extensionattributes]
  it("decomposes extmap with trailing extensionattributes (byte-string)", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=extmap:3/recvonly urn:example:hdrext attr1=val1 attr2" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal(3,          a.id)
    assert.equal("recvonly", a.direction)
    assert.equal("urn:example:hdrext", a.uri)
    assert.equal("attr1=val1 attr2", a.attributes)
  end)

end)

describe("base SDP grammar — Phase 4.E rtcp-fb (RFC 4585 §4.2)", function()

  -- SPEC: RFC 4585 §4.2 — payload type can be "*" wildcard
  it("decomposes rtcp-fb with wildcard PT", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 0",
        "a=rtcp-fb:* ccm fir" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("rtcp-fb", a.name)
    assert.equal("*",       a.payload_type)
    assert.equal("ccm",     a.feedback_type)
    assert.equal("fir",     a.parameters)
  end)

  -- SPEC: RFC 4585 §4.2 — numeric payload type
  it("decomposes rtcp-fb with numeric PT and no parameters", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000",
        "a=rtcp-fb:96 nack" },
    }))
    local a = doc.media[1].attributes[2]
    assert.equal(96,     a.payload_type)
    assert.is_number(a.payload_type)
    assert.equal("nack", a.feedback_type)
    assert.is_nil(a.parameters)
  end)

  -- SPEC: RFC 4585 §4.2 — rtcp-fb-nack-param "pli"/"sli"/etc.
  it("decomposes rtcp-fb with parameters", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000",
        "a=rtcp-fb:96 nack pli" },
    }))
    local a = doc.media[1].attributes[2]
    assert.equal(96, a.payload_type)
    assert.equal("nack", a.feedback_type)
    assert.equal("pli",  a.parameters)
  end)

end)

describe("base SDP grammar — Phase 4.E rtcp (RFC 3605 §2.1)", function()

  -- SPEC: RFC 3605 §2.1 — minimal form: just port
  it("decomposes rtcp with port only", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=rtcp:53020" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("rtcp", a.name)
    assert.equal(53020,  a.port)
    assert.is_number(a.port)
    assert.is_nil(a.net_type)
    assert.is_nil(a.addr_type)
    assert.is_nil(a.address)
  end)

  -- SPEC: RFC 3605 §2.1 — port + nettype SP addrtype SP connection-address
  it("decomposes rtcp with port + nettype/addrtype/address", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=rtcp:53020 IN IP4 192.0.2.1" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal(53020,     a.port)
    assert.equal("IN",      a.net_type)
    assert.equal("IP4",     a.addr_type)
    assert.equal("192.0.2.1", a.address)
  end)

end)

describe("base SDP grammar — Phase 4.E rtcp-mux (RFC 5761 §5.1.3)", function()

  -- SPEC: RFC 5761 §5.1.3 — flag attribute, no value
  it("captures rtcp-mux as a flag attribute (no value)", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0", "a=rtcp-mux" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("rtcp-mux", a.name)
    assert.is_nil(a.value)
  end)

  -- SPEC: RFC 5761 §5.1.3 — rtcp-mux is flag-only (no ':<value>' form)
  it("rejects rtcp-mux with a value (RFC 5761 §5.1.3 is flag-only)", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0", "a=rtcp-mux:foo" },
    }))
    assert.is_nil(doc)
  end)

end)

describe("base SDP grammar — ts-refclk traceable-mix (RFC 7273 §4.8)", function()

  -- SPEC: RFC 7273 §4.8 — "Traceable time sources MUST NOT be mixed with
  -- non-traceable time sources at any given level." Traceability per §4.6
  -- (gps/gal/glonass are traceable to UTC) and §4.7 (':traceable' suffix on
  -- ntp/ptp/private).

  it("accepts two non-traceable ts-refclks at media level", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-1D-9A-FF-FE-2C-32-0F:0",
        "a=ts-refclk:ntp=192.0.2.1" },
    }))
    assert.is_truthy(doc)
  end)

  it("accepts two traceable ts-refclks at media level", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=ts-refclk:gps",
        "a=ts-refclk:ptp=IEEE1588-2008:traceable" },
    }))
    assert.is_truthy(doc)
  end)

  it("rejects traceable + non-traceable mix at media level", function()
    local doc, ctx = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=ts-refclk:gps",
        "a=ts-refclk:ntp=192.0.2.1" },
    }))
    assert.is_nil(doc)
    assert.equal(1, #ctx.findings)
    assert.equal("sdp.a.ts-refclk.traceable-mix", ctx.findings[1].id)
    assert.equal("media[1].attributes", ctx.findings[1].field_path)
  end)

  it("rejects traceable + non-traceable mix at session level", function()
    local doc, ctx = base.match(lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=ts-refclk:ptp=IEEE1588-2008:traceable",
      "a=ts-refclk:localmac=AA-BB-CC-DD-EE-FF",
    }))
    assert.is_nil(doc)
    assert.equal("sdp.a.ts-refclk.traceable-mix", ctx.findings[1].id)
    assert.equal("session.attributes", ctx.findings[1].field_path)
  end)

  -- RFC 7273 §4.8: the rule is per-level. Mix ACROSS levels is permitted.
  it("accepts traceable at one media level, non-traceable at another (different levels)", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0", "a=ts-refclk:gps" },
      { "m=video 49170 RTP/AVP 0", "a=ts-refclk:ntp=192.0.2.1" },
    }))
    assert.is_truthy(doc)
  end)

  -- gps/gal/glonass are traceable to UTC (§4.6). private alone is
  -- non-traceable; private:traceable is traceable (§4.7).
  it("classifies private (no suffix) as non-traceable", function()
    local doc, ctx = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=ts-refclk:gal",
        "a=ts-refclk:private" },
    }))
    assert.is_nil(doc)
    assert.equal("sdp.a.ts-refclk.traceable-mix", ctx.findings[1].id)
  end)

  it("classifies private:traceable as traceable", function()
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=ts-refclk:gps",
        "a=ts-refclk:private:traceable" },
    }))
    assert.is_truthy(doc)
  end)

end)

describe("base SDP grammar — Phase 5 soft-syntactic findings", function()

  -- Helper for non-default policy + collect-all-findings runs.
  local function match_collect(text)
    return base.match(text, { fail_on_first = false })
  end

  -- ── 5.A.1: bare LF line endings ────────────────────────────────────────
  -- SPEC: RFC 8866 §9 ABNF requires CRLF. Bare LF is non-conformant but
  -- common in practice; lax form accepted with a default-warn finding.
  describe("bare LF instead of CRLF (sdp.line.lf-only-line-ending)", function()
    it("accepts bare-LF lines and emits a warn finding per LF line", function()
      local lf_text =
        "v=0\n" ..
        "o=- 1 1 IN IP4 127.0.0.1\n" ..
        "s=X\n" ..
        "t=0 0\n"
      local doc, ctx = match_collect(lf_text)
      assert.is_truthy(doc)
      local lf_findings = 0
      for _, f in ipairs(ctx.findings) do
        if f.id == "sdp.line.lf-only-line-ending" then
          lf_findings = lf_findings + 1
        end
      end
      assert.equal(4, lf_findings)
    end)

    it("under fail_on_first with warn severity, parse succeeds (warn doesn't halt)", function()
      local lf_text =
        "v=0\n" ..
        "o=- 1 1 IN IP4 127.0.0.1\n" ..
        "s=X\n" ..
        "t=0 0\n"
      local doc, ctx = base.match(lf_text)  -- default fail_on_first=true
      assert.is_truthy(doc)
      -- Warn-severity findings still record under fail_on_first.
      local found = false
      for _, f in ipairs(ctx.findings) do
        if f.id == "sdp.line.lf-only-line-ending" then found = true end
      end
      assert.is_true(found)
    end)

    it("policy 'off' suppresses LF findings entirely", function()
      local lf_text =
        "v=0\n" ..
        "o=- 1 1 IN IP4 127.0.0.1\n" ..
        "s=X\n" ..
        "t=0 0\n"
      local doc, ctx = base.match(lf_text,
        { policy = { ["sdp.line.lf-only-line-ending"] = "off" }, fail_on_first = false })
      assert.is_truthy(doc)
      for _, f in ipairs(ctx.findings) do
        assert.is_not.equal("sdp.line.lf-only-line-ending", f.id)
      end
    end)

    it("policy 'error' promotes LF finding to error (parse fails)", function()
      local lf_text =
        "v=0\n" ..
        "o=- 1 1 IN IP4 127.0.0.1\n" ..
        "s=X\n" ..
        "t=0 0\n"
      local doc = base.match(lf_text,
        { policy = { ["sdp.line.lf-only-line-ending"] = "error" } })
      assert.is_nil(doc)
    end)
  end)

  -- ── 5.B: trailing whitespace before terminator ────────────────────────
  -- SPEC: RFC 8866 §9 — line content is a non-whitespace text run followed
  -- by CRLF. Trailing whitespace is non-conformant; lax form accepts it
  -- with sdp.line.trailing-whitespace.
  describe("trailing whitespace (sdp.line.trailing-whitespace)", function()
    it("accepts a line with trailing spaces and emits one finding", function()
      local text =
        "v=0\r\n" ..
        "o=- 1 1 IN IP4 127.0.0.1\r\n" ..
        "s=Hello World  \r\n" ..    -- two trailing spaces
        "t=0 0\r\n"
      local doc, ctx = match_collect(text)
      assert.is_truthy(doc)
      local count = 0
      for _, f in ipairs(ctx.findings) do
        if f.id == "sdp.line.trailing-whitespace" then count = count + 1 end
      end
      assert.equal(1, count)
    end)

    -- The trailing whitespace must NOT land in the captured value.
    it("strips trailing whitespace from the captured value", function()
      local text =
        "v=0\r\n" ..
        "o=- 1 1 IN IP4 127.0.0.1\r\n" ..
        "s=Hello World  \r\n" ..    -- two trailing spaces
        "t=0 0\r\n"
      local doc = match_collect(text)
      assert.equal("Hello World", doc.session.name)
    end)

    -- Internal whitespace inside a text value must NOT trigger the finding.
    it("ignores internal whitespace inside a value", function()
      local text =
        "v=0\r\n" ..
        "o=- 1 1 IN IP4 127.0.0.1\r\n" ..
        "s=Hello World\r\n" ..
        "t=0 0\r\n"
      local _, ctx = match_collect(text)
      for _, f in ipairs(ctx.findings) do
        assert.is_not.equal("sdp.line.trailing-whitespace", f.id)
      end
    end)

    -- Trailing tabs also count as trailing whitespace per RFC 8866 §9.
    it("accepts trailing tabs and emits a finding", function()
      local text =
        "v=0\r\n" ..
        "o=- 1 1 IN IP4 127.0.0.1\r\n" ..
        "s=X\t\r\n" ..             -- trailing tab
        "t=0 0\r\n"
      local _, ctx = match_collect(text)
      local found = false
      for _, f in ipairs(ctx.findings) do
        if f.id == "sdp.line.trailing-whitespace" then found = true end
      end
      assert.is_true(found)
    end)
  end)

  -- ── 5.C: fmtp trailing semicolon ──────────────────────────────────────
  -- SPEC: RFC 8866 §6.15 — fmtp value form is byte-string with a semicolon
  -- separator convention. A trailing ';' is lax-tolerated with
  -- sdp.a.fmtp.trailing-semicolon.
  describe("fmtp trailing semicolon (sdp.a.fmtp.trailing-semicolon)", function()
    it("emits a finding when fmtp ends with a stray ';'", function()
      local doc, ctx = match_collect(minimal(nil, {
        { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000",
          "a=fmtp:96 profile-level-id=42e016;" },
      }))
      assert.is_truthy(doc)
      local count = 0
      for _, f in ipairs(ctx.findings) do
        if f.id == "sdp.a.fmtp.trailing-semicolon" then count = count + 1 end
      end
      assert.equal(1, count)
    end)

    it("emits no finding for fmtp without a trailing ';'", function()
      local _, ctx = match_collect(minimal(nil, {
        { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000",
          "a=fmtp:96 profile-level-id=42e016;max-mbps=108000" },
      }))
      for _, f in ipairs(ctx.findings) do
        assert.is_not.equal("sdp.a.fmtp.trailing-semicolon", f.id)
      end
    end)
  end)

  -- ── 5.D: UTF-8 BOM at file start ──────────────────────────────────────
  -- SPEC: RFC 8866 §6 — SDP charset is declared via `a=charset:`; a BOM
  -- isn't required and isn't part of the §9 ABNF, but some editors emit
  -- one. Lax form accepts it with sdp.file.bom-present.
  describe("UTF-8 BOM (sdp.file.bom-present)", function()
    local BOM = "\239\187\191"

    it("accepts a leading UTF-8 BOM and emits a finding", function()
      local text = BOM ..
        "v=0\r\n" ..
        "o=- 1 1 IN IP4 127.0.0.1\r\n" ..
        "s=X\r\n" ..
        "t=0 0\r\n"
      local doc, ctx = match_collect(text)
      assert.is_truthy(doc)
      local count = 0
      for _, f in ipairs(ctx.findings) do
        if f.id == "sdp.file.bom-present" then count = count + 1 end
      end
      assert.equal(1, count)
    end)

    it("emits no BOM finding when the file has no BOM", function()
      local text =
        "v=0\r\n" ..
        "o=- 1 1 IN IP4 127.0.0.1\r\n" ..
        "s=X\r\n" ..
        "t=0 0\r\n"
      local _, ctx = match_collect(text)
      for _, f in ipairs(ctx.findings) do
        assert.is_not.equal("sdp.file.bom-present", f.id)
      end
    end)
  end)

  -- ── 5.A.2: missing trailing newline ────────────────────────────────────
  -- SPEC: RFC 8866 §9 — every <fields> line is followed by CRLF, including
  -- the last. Lax form accepts a document that ends without a trailing
  -- terminator; emits sdp.file.trailing-newline-missing.
  describe("missing trailing newline (sdp.file.trailing-newline-missing)", function()
    it("accepts a document with no trailing newline and emits one finding", function()
      local text =
        "v=0\r\n" ..
        "o=- 1 1 IN IP4 127.0.0.1\r\n" ..
        "s=X\r\n" ..
        "t=0 0"          -- no trailing \r\n
      local doc, ctx = match_collect(text)
      assert.is_truthy(doc)
      local count = 0
      for _, f in ipairs(ctx.findings) do
        if f.id == "sdp.file.trailing-newline-missing" then count = count + 1 end
      end
      assert.equal(1, count)
    end)

    it("strict-CRLF document emits no missing-newline finding", function()
      local text =
        "v=0\r\n" ..
        "o=- 1 1 IN IP4 127.0.0.1\r\n" ..
        "s=X\r\n" ..
        "t=0 0\r\n"
      local _, ctx = match_collect(text)
      for _, f in ipairs(ctx.findings) do
        assert.is_not.equal("sdp.file.trailing-newline-missing", f.id)
      end
    end)
  end)

end)

describe("base SDP grammar — module exports", function()

  -- NOT-SPEC: library
  it("exposes a rules table (composable; for use by st2110 / ipmx extend())", function()
    assert.is_table(base.rules)
    assert.equal("document", base.rules[1])
    assert.is_truthy(base.rules.document)
    assert.is_truthy(base.rules.session_inner)
    assert.is_truthy(base.rules.media_section)
  end)

  -- NOT-SPEC: library
  it("exposes a compiled grammar", function()
    assert.is_truthy(base.grammar)
    -- Crude smoke test that it's an LPeg pattern (compiled patterns have a
    -- :match method).
    assert.is_function(base.grammar.match)
  end)

end)

-- ── Phase 6.E.A — RFC 5888 group attribute cross-stream invariants ──────
--
-- §6:  "All of the 'm' lines of a session description that uses 'group'
--       MUST be identified with a 'mid' attribute whether they appear in
--       the group line(s) or not."
-- §9.2: "'a=group' lines MUST NOT contain identification-tags that
--        correspond to 'm' lines with the port set to zero."

describe("base SDP grammar — group attribute invariants (Phase 6.E.A)",
    function()

  local function finding_for(ctx, id)
    for _, f in ipairs(ctx.findings or {}) do
      if f.id == id then return f end
    end
    return nil
  end

  describe("§6 — every m= requires a=mid when a=group is present", function()

    it("accepts when all media blocks carry a=mid", function()
      assert.is_truthy(base.match(lines_to_sdp({
        "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
        "a=group:DUP a b",
        "m=video 30000 RTP/AVP 96",
        "a=rtpmap:96 H264/90000",
        "a=mid:a",
        "m=video 30002 RTP/AVP 96",
        "a=rtpmap:96 H264/90000",
        "a=mid:b",
      })))
    end)

    it("does not fire when no a=group is present (mid is optional)", function()
      -- Without a=group, the §6 conditional doesn't trigger; missing
      -- a=mid is fine.
      assert.is_truthy(base.match(lines_to_sdp({
        "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
        "m=video 30000 RTP/AVP 96",
        "a=rtpmap:96 H264/90000",
      })))
    end)

    it("rejects when a=group present but a media block lacks a=mid", function()
      local doc, ctx = base.match(lines_to_sdp({
        "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
        "a=group:DUP a b",
        "m=video 30000 RTP/AVP 96",
        "a=rtpmap:96 H264/90000",
        "a=mid:a",
        "m=video 30002 RTP/AVP 96",
        "a=rtpmap:96 H264/90000",
        -- no a=mid here
      }))
      assert.is_nil(doc)
      local f = finding_for(ctx, "sdp.a.group.requires-mid-on-all-media")
      assert.is_not_nil(f)
      assert.equal("media[1]", f.field_path)
      assert.equal("RFC 5888 §6", f.spec_ref)
    end)

    it("fires regardless of whether m= block appears in any group tag", function()
      -- §6 wording is explicit: "whether they appear in the group line(s)
      -- or not." So a third m= block not referenced by the group must
      -- still carry a=mid.
      local doc, ctx = base.match(lines_to_sdp({
        "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
        "a=group:DUP a b",
        "m=video 30000 RTP/AVP 96",
        "a=rtpmap:96 H264/90000",
        "a=mid:a",
        "m=video 30002 RTP/AVP 96",
        "a=rtpmap:96 H264/90000",
        "a=mid:b",
        "m=audio 30004 RTP/AVP 96",
        "a=rtpmap:96 L24/48000/2",
        -- no a=mid on the third block
      }))
      assert.is_nil(doc)
      local f = finding_for(ctx, "sdp.a.group.requires-mid-on-all-media")
      assert.is_not_nil(f)
      assert.equal("media[2]", f.field_path)
    end)
  end)

  describe("§9.2 — a=group must not reference port-0 m= lines", function()

    it("accepts when all referenced mids have non-zero ports", function()
      assert.is_truthy(base.match(lines_to_sdp({
        "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
        "a=group:DUP a b",
        "m=video 30000 RTP/AVP 96",
        "a=rtpmap:96 H264/90000",
        "a=mid:a",
        "m=video 30002 RTP/AVP 96",
        "a=rtpmap:96 H264/90000",
        "a=mid:b",
      })))
    end)

    it("rejects a group tag whose mid resolves to a port=0 m=", function()
      local doc, ctx = base.match(lines_to_sdp({
        "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
        "a=group:DUP a b",
        "m=video 30000 RTP/AVP 96",
        "a=rtpmap:96 H264/90000",
        "a=mid:a",
        "m=video 0 RTP/AVP 96",            -- refused / inactive
        "a=rtpmap:96 H264/90000",
        "a=mid:b",
      }))
      assert.is_nil(doc)
      local f = finding_for(ctx, "sdp.a.group.references-port-zero-mid")
      assert.is_not_nil(f)
      assert.equal("RFC 5888 §9.2", f.spec_ref)
    end)

    it("does NOT fire on a port=0 m= line that no group references", function()
      -- The §9.2 prohibition is conditional on the mid being tagged in
      -- an a=group line. A port=0 block whose mid no group references
      -- is fine.
      assert.is_truthy(base.match(lines_to_sdp({
        "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
        "a=group:DUP a c",                 -- references a + c only
        "m=video 30000 RTP/AVP 96",
        "a=rtpmap:96 H264/90000",
        "a=mid:a",
        "m=video 0 RTP/AVP 96",            -- mid b not in any group
        "a=rtpmap:96 H264/90000",
        "a=mid:b",
        "m=video 30004 RTP/AVP 96",
        "a=rtpmap:96 H264/90000",
        "a=mid:c",
      })))
    end)
  end)
end)
