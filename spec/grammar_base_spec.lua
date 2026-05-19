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
      { "m=text 49174 RTP/AVP 96",  "a=rtpmap:96 text/plain" },
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
  it("rejects bare LF line endings at this tier (Phase 5 will soften to a warning)", function()
    -- Phase 1 enforces CRLF strictly per RFC 8866 §9 ABNF. Phase 5 adds
    -- soft-syntactic LF tolerance that records a finding instead.
    local text = "v=0\no=- 1 1 IN IP4 127.0.0.1\ns=X\nt=0 0\n"
    assert.is_nil(base.match(text))
  end)

  -- NOT-SPEC: library
  it("rejects missing final CRLF on the last line", function()
    local text = "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=X\r\nt=0 0"
    assert.is_nil(base.match(text))
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
  it("captures media-level a= attributes (rtpmap/fmtp stay as strings at base tier)", function()
    local doc = base.match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96",
        "a=rtpmap:96 H264/90000",
        "a=fmtp:96 profile-level-id=42801f",
        "a=sendonly" },
    }))
    local attrs = doc.media[1].attributes
    assert.equal(3, #attrs)
    assert.equal("rtpmap",                    attrs[1].name)
    assert.equal("96 H264/90000",             attrs[1].value)
    assert.equal("fmtp",                      attrs[2].name)
    assert.equal("96 profile-level-id=42801f", attrs[2].value)
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
  it("attribute values may contain colons (only the first split point counts)", function()
    -- Static PT 0 dodges the dynamic-PT-requires-rtpmap check; we're
    -- testing colon handling in attribute values here, not semantic checks.
    local doc = base.match(minimal(nil, {
      { "m=audio 49172 RTP/AVP 0",
        "a=ts-refclk:ptp=IEEE1588-2008:00-1D-9A-FF-FE-2C-32-0F:0" },
    }))
    local a = doc.media[1].attributes[1]
    assert.equal("ts-refclk", a.name)
    assert.equal("ptp=IEEE1588-2008:00-1D-9A-FF-FE-2C-32-0F:0", a.value)
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

    -- NOT-SPEC: library
    it("media-level IPv4 multicast missing TTL is rejected with media[N].connection path", function()
      local doc, ctx = base.match(lines_to_sdp({
        "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
        "m=audio 49172 RTP/AVP 0",
        "c=IN IP4 224.2.17.12",  -- missing /ttl
      }))
      assert.is_nil(doc)
      assert.equal("sdp.c.ipv4-multicast.ttl-required", ctx.findings[1].id)
      assert.equal("media[1].connection", ctx.findings[1].field_path)
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
