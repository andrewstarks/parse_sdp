---@diagnostic disable
-- Phase 1: structural acceptance/rejection tests for the base SDP grammar
-- skeleton. Every leaf is a placeholder accepting "any non-empty line
-- content" — Phase 2 will tighten leaves and add decomposition. These tests
-- exercise document shape (RFC 8866 §5) only.

local base = require("parse_sdp.grammar.base")
local g    = base.grammar

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
    assert.is_truthy(g:match(minimal()))
  end)

  -- NOT-SPEC: library
  it("accepts one media block", function()
    assert.is_truthy(g:match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96", "a=rtpmap:96 H264/90000" },
    })))
  end)

  -- NOT-SPEC: library
  it("accepts multiple media blocks", function()
    assert.is_truthy(g:match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96" },
      { "m=audio 49172 RTP/AVP 0"  },
      { "m=text  49174 RTP/AVP 96" },
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
    assert.is_truthy(g:match(text))
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
    assert.is_truthy(g:match(text))
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
    assert.is_truthy(g:match(text))
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
    assert.is_truthy(g:match(text))
  end)

  -- NOT-SPEC: library
  it("rejects empty input", function()
    assert.is_nil(g:match(""))
  end)

  -- NOT-SPEC: library
  it("rejects SDP with no v= (RFC 8866 §5: v= is required)", function()
    local text = lines_to_sdp({
      "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
    })
    assert.is_nil(g:match(text))
  end)

  -- NOT-SPEC: library
  it("rejects SDP with no o= (RFC 8866 §5: o= is required)", function()
    local text = lines_to_sdp({ "v=0", "s=X", "t=0 0" })
    assert.is_nil(g:match(text))
  end)

  -- NOT-SPEC: library
  it("rejects SDP with no s= (RFC 8866 §5: s= is required)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "t=0 0",
    })
    assert.is_nil(g:match(text))
  end)

  -- NOT-SPEC: library
  it("rejects SDP with no t= (RFC 8866 §5: at least one t= is required)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
    })
    assert.is_nil(g:match(text))
  end)

  -- NOT-SPEC: library
  it("rejects wrong order (s= before o=)", function()
    local text = lines_to_sdp({
      "v=0", "s=X", "o=- 1 1 IN IP4 127.0.0.1", "t=0 0",
    })
    assert.is_nil(g:match(text))
  end)

  -- NOT-SPEC: library
  it("rejects wrong order (c= before t=)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "t=0 0",
      "c=IN IP4 224.0.0.1/127",  -- c= belongs before t=, not after
    })
    -- after the t= block we only allow z=, k=, a=, then media sections
    assert.is_nil(g:match(text))
  end)

  -- NOT-SPEC: library
  it("rejects junk after the last media section", function()
    local text = minimal(nil, { { "m=video 49170 RTP/AVP 96" } }) .. "garbage\r\n"
    assert.is_nil(g:match(text))
  end)

  -- NOT-SPEC: library
  it("rejects bare LF line endings at this tier (Phase 5 will soften to a warning)", function()
    -- Phase 1 enforces CRLF strictly per RFC 8866 §9 ABNF. Phase 5 adds
    -- soft-syntactic LF tolerance that records a finding instead.
    local text = "v=0\no=- 1 1 IN IP4 127.0.0.1\ns=X\nt=0 0\n"
    assert.is_nil(g:match(text))
  end)

  -- NOT-SPEC: library
  it("rejects missing final CRLF on the last line", function()
    local text = "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=X\r\nt=0 0"
    assert.is_nil(g:match(text))
  end)

  -- NOT-SPEC: library
  it("rejects an empty value (RFC 8866 §5: text values must be non-empty)", function()
    local text = "v=\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=X\r\nt=0 0\r\n"
    assert.is_nil(g:match(text))
  end)

end)

describe("base SDP grammar — captured doc shape (Phase 2.A)", function()

  -- NOT-SPEC: library
  it("returns a captured table for minimal valid SDP", function()
    local doc = g:match(minimal())
    assert.is_table(doc)
  end)

  -- NOT-SPEC: library
  it("captures version = '0' (RFC 8866 §5.1)", function()
    local doc = g:match(minimal())
    assert.equal("0", doc.version)
  end)

  -- NOT-SPEC: library
  it("captures session.name (RFC 8866 §5.3)", function()
    local doc = g:match(minimal())
    assert.equal("Test Session", doc.session.name)
  end)

  -- NOT-SPEC: library
  it("captures session.name preserving spaces, punctuation, dashes", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1",
      "s=Multi-word session: with punctuation!",
      "t=0 0",
    })
    local doc = g:match(text)
    assert.equal("Multi-word session: with punctuation!", doc.session.name)
  end)

  -- NOT-SPEC: library
  it("rejects v= != '0' (RFC 8866 §5.1: only '0' currently defined)", function()
    local text = lines_to_sdp({
      "v=1", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
    })
    assert.is_nil(g:match(text))
  end)

  -- NOT-SPEC: library
  it("k= line is parsed and discarded (RFC 8866 §5.12 obsolete)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "k=clear:password",
    })
    local doc = g:match(text)
    assert.is_table(doc)
    assert.equal("0",  doc.version)
    assert.equal("X",  doc.session.name)
    assert.is_nil(doc.session.key)  -- §5.12 says discard; no field on doc
  end)

  -- NOT-SPEC: library
  it("captures session as a sub-table, not a top-level field bag", function()
    local doc = g:match(minimal())
    -- session.name is inside doc.session, not at doc top level.
    assert.is_table(doc.session)
    assert.is_nil(doc.name)
  end)

end)

describe("base SDP grammar — origin and connection captures (Phase 2.B)", function()

  -- NOT-SPEC: library
  it("captures doc.origin as a table with six fields (RFC 8866 §5.2)", function()
    local doc = g:match(minimal())
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
    local doc = g:match(text)
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
    local doc = g:match(text)
    assert.is_string(doc.origin.sess_id)
    assert.equal("18446744073709551615", doc.origin.sess_id)
    assert.equal("18446744073709551614", doc.origin.sess_version)
  end)

  -- NOT-SPEC: library
  it("rejects o= with non-IN net_type (RFC 8866 §5.2 defines only IN)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 XX IP4 192.0.2.1", "s=X", "t=0 0",
    })
    assert.is_nil(g:match(text))
  end)

  -- NOT-SPEC: library
  it("rejects o= with unknown addr_type", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP9 192.0.2.1", "s=X", "t=0 0",
    })
    assert.is_nil(g:match(text))
  end)

  -- NOT-SPEC: library
  it("rejects o= with non-digit sess_id", function()
    local text = lines_to_sdp({
      "v=0", "o=- abc 1 IN IP4 192.0.2.1", "s=X", "t=0 0",
    })
    assert.is_nil(g:match(text))
  end)

  -- NOT-SPEC: library
  it("rejects o= with too few tokens", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4", "s=X", "t=0 0",
    })
    assert.is_nil(g:match(text))
  end)

  -- NOT-SPEC: library
  it("session.connection is nil when c= is absent", function()
    local doc = g:match(minimal())
    assert.is_nil(doc.session.connection)
  end)

  -- NOT-SPEC: library
  it("captures session.connection when c= is present (RFC 8866 §5.7)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 192.0.2.1", "s=X",
      "c=IN IP4 224.0.0.1/127",
      "t=0 0",
    })
    local doc = g:match(text)
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
    local doc = g:match(text)
    assert.equal("IP6",     doc.session.connection.addr_type)
    assert.equal("ff00::1", doc.session.connection.address)
  end)

  -- NOT-SPEC: library
  it("rejects c= with wrong net_type", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 192.0.2.1", "s=X",
      "c=ZZ IP4 224.0.0.1/127", "t=0 0",
    })
    assert.is_nil(g:match(text))
  end)

  -- NOT-SPEC: library
  it("rejects c= missing the address token", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 192.0.2.1", "s=X",
      "c=IN IP4", "t=0 0",
    })
    assert.is_nil(g:match(text))
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
    local doc = g:match(text)
    assert.equal("A short session description", doc.session.info)
  end)

  -- NOT-SPEC: library
  it("session.info is nil when i= absent", function()
    local doc = g:match(minimal())
    assert.is_nil(doc.session.info)
  end)

  -- NOT-SPEC: library
  it("captures session.uri when u= present (RFC 8866 §5.5)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "u=http://example.com/session.sdp",
      "t=0 0",
    })
    local doc = g:match(text)
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
    local doc = g:match(text)
    assert.is_table(doc.session.emails)
    assert.equal(2, #doc.session.emails)
    assert.equal("alice@example.com",      doc.session.emails[1])
    assert.equal("bob@example.com (Bob)",  doc.session.emails[2])
  end)

  -- NOT-SPEC: library
  it("session.emails is an empty array when no e= lines", function()
    local doc = g:match(minimal())
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
    local doc = g:match(text)
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
    local doc = g:match(text)
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
    local doc = g:match(minimal())
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
    assert.is_nil(g:match(text))
  end)

  -- NOT-SPEC: library
  it("rejects b= missing colon", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "b=AS 128",
      "t=0 0",
    })
    assert.is_nil(g:match(text))
  end)

end)

describe("base SDP grammar — media array shape (Phase 2.C)", function()

  -- NOT-SPEC: library
  it("doc.media is an empty array when no media blocks present", function()
    local doc = g:match(minimal())
    assert.is_table(doc.media)
    assert.equal(0, #doc.media)
  end)

  -- NOT-SPEC: library
  it("doc.media has one entry per m= section", function()
    local doc = g:match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96" },
      { "m=audio 49172 RTP/AVP 0"  },
    }))
    assert.is_table(doc.media)
    assert.equal(2, #doc.media)
  end)

  -- NOT-SPEC: library
  it("captures media-level info when i= present", function()
    local doc = g:match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96",
        "i=Video stream description" },
    }))
    assert.equal("Video stream description", doc.media[1].info)
  end)

  -- NOT-SPEC: library
  it("captures media-level connection", function()
    local doc = g:match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96",
        "c=IN IP4 239.1.1.1/127" },
    }))
    assert.is_table(doc.media[1].connection)
    assert.equal("IP4",            doc.media[1].connection.addr_type)
    assert.equal("239.1.1.1/127",  doc.media[1].connection.address)
  end)

  -- NOT-SPEC: library
  it("captures media-level bandwidths as array of {type, value}", function()
    local doc = g:match(minimal(nil, {
      { "m=video 49170 RTP/AVP 96",
        "b=AS:5000",
        "b=TIAS:4500000" },
    }))
    assert.equal(2, #doc.media[1].bandwidths)
    assert.equal("AS",       doc.media[1].bandwidths[1].type)
    assert.equal(5000,       doc.media[1].bandwidths[1].value)
    assert.equal("TIAS",     doc.media[1].bandwidths[2].type)
    assert.equal(4500000,    doc.media[1].bandwidths[2].value)
  end)

  -- NOT-SPEC: library
  it("media-level info / connection are nil when their lines are absent", function()
    local doc = g:match(minimal(nil, { { "m=video 49170 RTP/AVP 96" } }))
    assert.is_nil(doc.media[1].info)
    assert.is_nil(doc.media[1].connection)
    assert.is_table(doc.media[1].bandwidths)
    assert.equal(0, #doc.media[1].bandwidths)
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
