---@diagnostic disable
describe("parse_sdp", function()
  it("loads without error", function()
    local sdp = require("parse_sdp")
    assert.is_table(sdp)
  end)
end)

describe("grammar.tokenize_line", function()
  local grammar = require("parse_sdp")._grammar

  it("parses a valid CRLF line", function()
    local t, v, offset = grammar.tokenize_line("v=0\r\n")
    assert.equal("v", t)
    assert.equal("0", v)
    assert.equal(3, offset)
  end)

  it("parses a valid LF-only line", function()
    local t, v, offset = grammar.tokenize_line("s=My Session\n")
    assert.equal("s", t)
    assert.equal("My Session", v)
    assert.equal(3, offset)
  end)

  it("parses a line with no trailing newline", function()
    local t, v, offset = grammar.tokenize_line("v=0")
    assert.equal("v", t)
    assert.equal("0", v)
    assert.equal(3, offset)
  end)

  it("parses a line with a complex value", function()
    local t, v, offset = grammar.tokenize_line("o=- 0 0 IN IP4 127.0.0.1\r\n")
    assert.equal("o", t)
    assert.equal("- 0 0 IN IP4 127.0.0.1", v)
    assert.equal(3, offset)
  end)

  it("rejects empty input", function()
    local t, pos = grammar.tokenize_line("")
    assert.is_nil(t)
    assert.is_number(pos)
  end)

  it("rejects a line with no equals sign", function()
    local t, pos = grammar.tokenize_line("invalid\r\n")
    assert.is_nil(t)
    assert.is_number(pos)
  end)

  it("rejects a line with multi-char type field", function()
    local t, pos = grammar.tokenize_line("ab=value\r\n")
    assert.is_nil(t)
    assert.is_number(pos)
  end)

  it("rejects a line with non-alpha type character", function()
    local t, pos = grammar.tokenize_line("1=value\r\n")
    assert.is_nil(t)
    assert.is_number(pos)
  end)

  it("rejects a line with an empty value", function()
    local t, pos = grammar.tokenize_line("v=\r\n")
    assert.is_nil(t)
    assert.is_number(pos)
  end)

  it("returns failure position 1 for non-alpha type", function()
    local t, pos = grammar.tokenize_line("1=value\r\n")
    assert.is_nil(t)
    assert.equal(1, pos)
  end)

  it("returns failure position after type char for multi-char type", function()
    local t, pos = grammar.tokenize_line("ab=value\r\n")
    assert.is_nil(t)
    assert.equal(2, pos)  -- failed after consuming 'a'
  end)

  it("returns failure position at value start for empty value", function()
    local t, pos = grammar.tokenize_line("v=\r\n")
    assert.is_nil(t)
    assert.equal(3, pos)  -- failed at position 3 where value was expected
  end)
end)

describe("grammar.parse_version", function()
  local grammar = require("parse_sdp")._grammar

  it("accepts '0'", function()
    local v = grammar.parse_version("0")
    assert.equal("0", v)
  end)

  it("rejects '1'", function()
    local v, pos = grammar.parse_version("1")
    assert.is_nil(v)
    assert.is_number(pos)
  end)

  it("rejects empty string", function()
    local v, pos = grammar.parse_version("")
    assert.is_nil(v)
    assert.is_number(pos)
  end)

  it("rejects '0' with trailing content", function()
    local v, pos = grammar.parse_version("0 extra")
    assert.is_nil(v)
    assert.is_number(pos)
  end)
end)

describe("grammar.parse_origin", function()
  local grammar = require("parse_sdp")._grammar

  it("parses a valid origin value", function()
    local o = grammar.parse_origin("- 1234567890 1 IN IP4 192.0.2.1")
    assert.is_table(o)
    assert.equal("-",          o.username)
    assert.equal("1234567890", o.sess_id)
    assert.equal("1",          o.sess_version)
    assert.equal("IN",         o.net_type)
    assert.equal("IP4",        o.addr_type)
    assert.equal("192.0.2.1",  o.unicast_address)
  end)

  it("accepts IP6 address type", function()
    local o = grammar.parse_origin("- 1 1 IN IP6 ::1")
    assert.is_table(o)
    assert.equal("IP6", o.addr_type)
    assert.equal("::1", o.unicast_address)
  end)

  it("rejects too few fields", function()
    local o, pos = grammar.parse_origin("invalid")
    assert.is_nil(o)
    assert.is_number(pos)
  end)

  it("rejects non-numeric sess-id", function()
    local o, pos = grammar.parse_origin("- abc 1 IN IP4 192.0.2.1")
    assert.is_nil(o)
    assert.is_number(pos)
  end)

  it("rejects unknown nettype", function()
    local o, pos = grammar.parse_origin("- 1 1 OUT IP4 192.0.2.1")
    assert.is_nil(o)
    assert.is_number(pos)
  end)

  it("rejects unknown addrtype", function()
    local o, pos = grammar.parse_origin("- 1 1 IN IP5 192.0.2.1")
    assert.is_nil(o)
    assert.is_number(pos)
  end)
end)

describe("grammar.parse_timing", function()
  local grammar = require("parse_sdp")._grammar

  it("parses '0 0'", function()
    local t = grammar.parse_timing("0 0")
    assert.is_table(t)
    assert.equal(0, t.start)
    assert.equal(0, t.stop)
  end)

  it("parses NTP timestamps", function()
    local t = grammar.parse_timing("3034423619 3042462419")
    assert.is_table(t)
    assert.equal(3034423619, t.start)
    assert.equal(3042462419, t.stop)
  end)

  it("rejects missing stop time", function()
    local t, pos = grammar.parse_timing("0")
    assert.is_nil(t)
    assert.is_number(pos)
  end)

  it("rejects non-numeric values", function()
    local t, pos = grammar.parse_timing("abc def")
    assert.is_nil(t)
    assert.is_number(pos)
  end)

  it("rejects trailing content after stop time", function()
    local t, pos = grammar.parse_timing("0 0 extra")
    assert.is_nil(t)
    assert.is_number(pos)
  end)
end)

describe("sdp.parse — required session fields", function()
  local sdp = require("parse_sdp")

  local minimal = table.concat({
    "v=0",
    "o=- 1234567890 1 IN IP4 192.0.2.1",
    "s=My Session",
    "t=0 0",
  }, "\r\n") .. "\r\n"

  it("parses a minimal valid SDP into a doc table", function()
    local doc, err = sdp.parse(minimal)
    assert.is_nil(err)
    assert.is_table(doc)
    assert.equal("0",           doc.version)
    assert.equal("-",           doc.origin.username)
    assert.equal("1234567890",  doc.origin.sess_id)
    assert.equal("1",           doc.origin.sess_version)
    assert.equal("IN",          doc.origin.net_type)
    assert.equal("IP4",         doc.origin.addr_type)
    assert.equal("192.0.2.1",   doc.origin.unicast_address)
    assert.equal("My Session",  doc.session.name)
    assert.equal(0,             doc.session.timing.start)
    assert.equal(0,             doc.session.timing.stop)
  end)

  it("accepts LF-only line endings", function()
    local lf = minimal:gsub("\r\n", "\n")
    local doc, err = sdp.parse(lf)
    assert.is_nil(err)
    assert.is_table(doc)
    assert.equal("My Session", doc.session.name)
  end)

  it("rejects SDP that does not end with a newline (RFC 4566 §5 / §9 ABNF)", function()
    local missing_nl = minimal:sub(1, -3)  -- strip trailing \r\n
    local doc, err = sdp.parse(missing_nl)
    assert.is_nil(doc)
    assert.is_table(err)
    assert.matches("newline", err.message)
    assert.equal("RFC 4566 §5", err.spec_ref)
  end)

  it("rejects blank lines between records (RFC 4566 §5 / §9 ABNF)", function()
    local with_blank = table.concat({
      "v=0",
      "o=- 1234567890 1 IN IP4 192.0.2.1",
      "",
      "s=My Session",
      "t=0 0",
    }, "\r\n") .. "\r\n"
    local doc, err = sdp.parse(with_blank)
    assert.is_nil(doc)
    assert.is_table(err)
  end)

  it("returns nil, err for empty input", function()
    local doc, err = sdp.parse("")
    assert.is_nil(doc)
    assert.is_table(err)
    assert.equal(1, err.line)
  end)

  -- RFC 8866 §5.3 (and RFC 4566 §5.3 with the same intent):
  -- "If a session has no meaningful name, then 's= ' or 's=-' is RECOMMENDED."
  -- The 's=' line MUST NOT be empty, but a single space or dash is valid.
  it("accepts 's= ' (single space session name per RFC 8866 §5.3)", function()
    local text = "v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns= \r\nt=0 0\r\n"
    local doc, err = sdp.parse(text)
    assert.is_nil(err)
    assert.is_table(doc)
    assert.equal(" ", doc.session.name)
  end)

  it("accepts 's=-' (single dash session name per RFC 8866 §5.3)", function()
    local text = "v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns=-\r\nt=0 0\r\n"
    local doc, err = sdp.parse(text)
    assert.is_nil(err)
    assert.is_table(doc)
    assert.equal("-", doc.session.name)
  end)

  it("rejects 's=' empty session name (RFC 8866 §5.3 MUST NOT be empty)", function()
    local text = "v=0\r\no=- 0 0 IN IP4 127.0.0.1\r\ns=\r\nt=0 0\r\n"
    local doc, err = sdp.parse(text)
    assert.is_nil(doc)
    assert.is_table(err)
  end)

  it("returns nil, err when v= is missing", function()
    local doc, err = sdp.parse(table.concat({
      "o=- 1234567890 1 IN IP4 192.0.2.1",
      "s=My Session",
      "t=0 0",
    }, "\r\n") .. "\r\n")
    assert.is_nil(doc)
    assert.is_table(err)
    assert.equal(1, err.line)
  end)

  it("returns nil, err for wrong field order", function()
    local doc, err = sdp.parse(table.concat({
      "v=0",
      "s=My Session",
      "o=- 1234567890 1 IN IP4 192.0.2.1",
      "t=0 0",
    }, "\r\n") .. "\r\n")
    assert.is_nil(doc)
    assert.is_table(err)
    assert.equal(2, err.line)
    assert.equal("s=My Session", err.context)
  end)

  it("returns nil, err for malformed o= value", function()
    local doc, err = sdp.parse(table.concat({
      "v=0",
      "o=invalid",
      "s=My Session",
      "t=0 0",
    }, "\r\n") .. "\r\n")
    assert.is_nil(doc)
    assert.is_table(err)
    assert.equal(2, err.line)
    assert.equal("o=invalid", err.context)
  end)

  it("returns nil, err for wrong v= value", function()
    local doc, err = sdp.parse(table.concat({
      "v=1",
      "o=- 1234567890 1 IN IP4 192.0.2.1",
      "s=My Session",
      "t=0 0",
    }, "\r\n") .. "\r\n")
    assert.is_nil(doc)
    assert.is_table(err)
    assert.equal(1, err.line)
    assert.equal("v=1", err.context)
  end)

  it("error table contains message, line, col, context", function()
    local doc, err = sdp.parse("v=1\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=x\r\nt=0 0\r\n")
    assert.is_nil(doc)
    assert.is_string(err.message)
    assert.is_number(err.line)
    assert.is_number(err.col)
    assert.is_string(err.context)
  end)

  it("ignores content after the four required fields", function()
    local doc, err = sdp.parse(minimal .. "a=recvonly\r\n")
    assert.is_nil(err)
    assert.is_table(doc)
  end)

  it("rejects unrecognized field type after all SDP fields", function()
    local doc, err = sdp.parse(minimal .. "x=garbage\r\n")
    assert.is_nil(doc)
    assert.is_table(err)
    assert.equal("WRONG_ORDER", err.code)
  end)

  it("rejects malformed content at end of SDP", function()
    local doc, err = sdp.parse(minimal .. "not-a-field\r\n")
    assert.is_nil(doc)
    assert.is_table(err)
    assert.is_string(err.message)
  end)
end)

-- RFC 4566 §5: support for r= (repeat times), z= (time zones),
-- k= (encryption keys, session and media level), and multiple t= blocks.
describe("sdp.parse — RFC 4566 §5 r=/z=/k=/multiple t= (audit F8)", function()
  local sdp = require("parse_sdp")

  local function make(extra_lines)
    local lines = { "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=Test" }
    for _, l in ipairs(extra_lines or {}) do lines[#lines + 1] = l end
    return table.concat(lines, "\r\n") .. "\r\n"
  end

  it("accepts t= followed by r= (RFC 4566 §5.10)", function()
    local doc, err = sdp.parse(make({ "t=2873397496 2873404696", "r=604800 3600 0 90000" }))
    assert.is_nil(err)
    assert.is_table(doc)
    assert.equal(1, #doc.session.time_descriptions)
    assert.equal("604800", doc.session.time_descriptions[1].repeats[1].interval)
  end)

  it("accepts t= followed by r= with typed-time tokens (7d 1h 0 25h)", function()
    local doc, err = sdp.parse(make({ "t=2873397496 2873404696", "r=7d 1h 0 25h" }))
    assert.is_nil(err)
    assert.is_table(doc)
    local r = doc.session.time_descriptions[1].repeats[1]
    assert.equal("7d", r.interval)
    assert.equal("1h", r.duration)
    assert.same({ "0", "25h" }, r.offsets)
  end)

  it("accepts multiple time descriptions (RFC 4566 §5)", function()
    local doc, err = sdp.parse(make({
      "t=2873397496 2873404696", "r=604800 3600 0 90000",
      "t=2880000000 2880003600",
    }))
    assert.is_nil(err)
    assert.is_table(doc)
    assert.equal(2, #doc.session.time_descriptions)
    assert.equal(2873397496, doc.session.time_descriptions[1].start)
    assert.equal(2880000000, doc.session.time_descriptions[2].start)
    assert.equal(0, #doc.session.time_descriptions[2].repeats)
    -- Back-compat: session.timing reflects the first description.
    assert.equal(2873397496, doc.session.timing.start)
  end)

  it("accepts z= time zones (RFC 4566 §5.11)", function()
    local doc, err = sdp.parse(make({
      "t=2873397496 2873404696",
      "z=2882844526 -1h 2898848070 0",
    }))
    assert.is_nil(err)
    assert.is_table(doc)
    assert.equal(2, #doc.session.time_zones)
    assert.equal("-1h", doc.session.time_zones[1].offset)
  end)

  -- RFC 8866 §5.12 obsoletes k=: "One MUST NOT include a 'k=' line in an
  -- SDP, and MUST discard it if it is received in an SDP." (Audit D1.1.)
  it("discards session-level k= without rejecting (RFC 8866 §5.12)", function()
    local doc, err = sdp.parse(make({ "t=0 0", "k=clear:secret" }))
    assert.is_nil(err)
    assert.is_table(doc)
    assert.is_nil(doc.session.key)
  end)

  it("discards session-level k= method-only form (RFC 8866 §5.12)", function()
    local doc, err = sdp.parse(make({ "t=0 0", "k=prompt" }))
    assert.is_nil(err)
    assert.is_nil(doc.session.key)
  end)

  it("discards media-level k= without rejecting (RFC 8866 §5.12)", function()
    local doc, err = sdp.parse(make({
      "t=0 0",
      "m=audio 49170 RTP/AVP 0",
      "k=base64:Zm9vYmFy",
    }))
    assert.is_nil(err)
    assert.is_table(doc)
    assert.is_nil(doc.media[1].key)
  end)

  it("serializer never emits k= (RFC 8866 §5.12) even if doc.session.key is set", function()
    -- Round-trip a fully-loaded SDP including k= lines and confirm the
    -- serialized form has neither session- nor media-level k=.
    local text = make({
      "c=IN IP4 224.2.17.12/127",
      "t=2873397496 2873404696",
      "r=7d 1h 0 25h",
      "t=2880000000 2880003600",
      "z=2882844526 -1h 2898848070 0",
      "k=clear:secret",
      "a=recvonly",
      "m=audio 49170 RTP/AVP 0",
      "k=base64:Zm9vYmFy",
    })
    local doc, err = sdp.parse(text)
    assert.is_nil(err)
    local out = doc:to_sdp()
    assert.falsy(out:find("k=", 1, true))
    -- Round-trip: re-parsed output keeps the rest of the structure.
    local doc2, err2 = sdp.parse(out)
    assert.is_nil(err2)
    assert.equal(2, #doc2.session.time_descriptions)
    assert.is_nil(doc2.session.key)
    assert.is_nil(doc2.media[1].key)
  end)

  it("rejects z= without preceding t=", function()
    -- z= requires t=. parser already requires t= first; this exercises ordering.
    local text = make({ "z=2882844526 -1h" })
    local _, err = sdp.parse(text)
    assert.is_table(err)
  end)

  it("rejects malformed r= (less than three tokens)", function()
    local _, err = sdp.parse(make({ "t=0 0", "r=604800 3600" }))
    assert.is_table(err)
  end)

  it("rejects malformed z= (odd token count)", function()
    local _, err = sdp.parse(make({ "t=0 0", "z=2882844526 -1h 2898848070" }))
    assert.is_table(err)
  end)
end)

describe("sdp.parse — optional session fields (M4)", function()
  local sdp = require("parse_sdp")

  local base = {
    "v=0",
    "o=- 1 1 IN IP4 127.0.0.1",
    "s=Test",
  }

  local function make(before_t, after_t)
    local lines = {}
    for _, l in ipairs(base) do lines[#lines + 1] = l end
    for _, l in ipairs(before_t or {}) do lines[#lines + 1] = l end
    lines[#lines + 1] = "t=0 0"
    for _, l in ipairs(after_t or {}) do lines[#lines + 1] = l end
    return table.concat(lines, "\r\n") .. "\r\n"
  end

  it("parses i= session information", function()
    local doc, err = sdp.parse(make({"i=A test session"}))
    assert.is_nil(err)
    assert.equal("A test session", doc.session.info)
  end)

  it("parses u= URI", function()
    local doc, err = sdp.parse(make({"u=http://example.com/seminar.pdf"}))
    assert.is_nil(err)
    assert.equal("http://example.com/seminar.pdf", doc.session.uri)
  end)

  it("parses multiple e= fields into an array in order", function()
    local doc, err = sdp.parse(make({"e=j.doe@example.com", "e=r.smith@example.net"}))
    assert.is_nil(err)
    assert.is_table(doc.session.emails)
    assert.equal(2,                    #doc.session.emails)
    assert.equal("j.doe@example.com",   doc.session.emails[1])
    assert.equal("r.smith@example.net", doc.session.emails[2])
  end)

  it("parses multiple p= fields into an array in order", function()
    local doc, err = sdp.parse(make({"p=+1 617 555 6011", "p=+44 171 380 7777"}))
    assert.is_nil(err)
    assert.is_table(doc.session.phones)
    assert.equal(2,                  #doc.session.phones)
    assert.equal("+1 617 555 6011",  doc.session.phones[1])
    assert.equal("+44 171 380 7777", doc.session.phones[2])
  end)

  it("parses c= with IPv4 connection address", function()
    local doc, err = sdp.parse(make({"c=IN IP4 224.2.1.1"}))
    assert.is_nil(err)
    assert.is_table(doc.session.connection)
    assert.equal("IN",        doc.session.connection.net_type)
    assert.equal("IP4",       doc.session.connection.addr_type)
    assert.equal("224.2.1.1", doc.session.connection.address)
  end)

  it("parses c= with IPv6 connection address", function()
    local doc, err = sdp.parse(make({"c=IN IP6 FF15::101"}))
    assert.is_nil(err)
    assert.is_table(doc.session.connection)
    assert.equal("IP6",       doc.session.connection.addr_type)
    assert.equal("FF15::101", doc.session.connection.address)
  end)

  it("parses b= with AS: bandwidth type", function()
    local doc, err = sdp.parse(make({"b=AS:128"}))
    assert.is_nil(err)
    assert.is_table(doc.session.bandwidths)
    assert.equal(1,    #doc.session.bandwidths)
    assert.equal("AS", doc.session.bandwidths[1].type)
    assert.equal(128,  doc.session.bandwidths[1].value)
  end)

  it("parses b= with CT: bandwidth type", function()
    local doc, err = sdp.parse(make({"b=CT:1000"}))
    assert.is_nil(err)
    assert.equal("CT", doc.session.bandwidths[1].type)
    assert.equal(1000, doc.session.bandwidths[1].value)
  end)

  it("parses b= with X- extension bandwidth type", function()
    local doc, err = sdp.parse(make({"b=X-YZ:256"}))
    assert.is_nil(err)
    assert.equal("X-YZ", doc.session.bandwidths[1].type)
    assert.equal(256,    doc.session.bandwidths[1].value)
  end)

  it("parses multiple b= fields into an array in order", function()
    local doc, err = sdp.parse(make({"b=AS:128", "b=CT:1000"}))
    assert.is_nil(err)
    assert.equal(2,    #doc.session.bandwidths)
    assert.equal("AS", doc.session.bandwidths[1].type)
    assert.equal("CT", doc.session.bandwidths[2].type)
  end)

  it("parses a= flag attribute after t=", function()
    local doc, err = sdp.parse(make({}, {"a=recvonly"}))
    assert.is_nil(err)
    assert.is_table(doc.session.attributes)
    assert.equal(1,          #doc.session.attributes)
    assert.equal("recvonly", doc.session.attributes[1].name)
    assert.is_nil(doc.session.attributes[1].value)
  end)

  it("parses a= attribute with value after t=", function()
    local doc, err = sdp.parse(make({}, {"a=rtpmap:99 h263-1998/90000"}))
    assert.is_nil(err)
    assert.equal("rtpmap",             doc.session.attributes[1].name)
    assert.equal("99 h263-1998/90000", doc.session.attributes[1].value)
  end)

  it("parses multiple a= attributes in order", function()
    local doc, err = sdp.parse(make({}, {"a=recvonly", "a=rtpmap:99 h263-1998/90000"}))
    assert.is_nil(err)
    assert.equal(2,          #doc.session.attributes)
    assert.equal("recvonly", doc.session.attributes[1].name)
    assert.equal("rtpmap",   doc.session.attributes[2].name)
  end)

  it("parses an SDP with all optional session fields present", function()
    local doc, err = sdp.parse(make(
      {"i=A description", "u=http://example.com", "e=user@example.com",
       "p=+1 617 555 6011", "c=IN IP4 224.2.1.1", "b=AS:128"},
      {"a=recvonly"}
    ))
    assert.is_nil(err)
    assert.equal("A description",      doc.session.info)
    assert.equal("http://example.com", doc.session.uri)
    assert.equal(1,                    #doc.session.emails)
    assert.equal("user@example.com",   doc.session.emails[1])
    assert.equal(1,                    #doc.session.phones)
    assert.is_table(doc.session.connection)
    assert.equal("224.2.1.1",          doc.session.connection.address)
    assert.equal(1,                    #doc.session.bandwidths)
    assert.equal("AS",                 doc.session.bandwidths[1].type)
    assert.equal(1,                    #doc.session.attributes)
    assert.equal("recvonly",           doc.session.attributes[1].name)
  end)

  it("minimal SDP has empty optional field collections", function()
    local doc, err = sdp.parse(make())
    assert.is_nil(err)
    assert.is_table(doc.session.emails)
    assert.equal(0, #doc.session.emails)
    assert.is_table(doc.session.phones)
    assert.equal(0, #doc.session.phones)
    assert.is_table(doc.session.bandwidths)
    assert.equal(0, #doc.session.bandwidths)
    assert.is_table(doc.session.attributes)
    assert.equal(0, #doc.session.attributes)
    assert.is_nil(doc.session.info)
    assert.is_nil(doc.session.uri)
    assert.is_nil(doc.session.connection)
  end)
end)

describe("grammar.parse_media", function()
  local grammar = require("parse_sdp")._grammar

  it("parses a minimal m= value", function()
    local m = grammar.parse_media("video 49170 RTP/AVP 96")
    assert.is_table(m)
    assert.equal("video",   m.media)
    assert.equal(49170,     m.port)
    assert.is_nil(m.port_count)
    assert.equal("RTP/AVP", m.proto)
    assert.equal(1,         #m.fmts)
    assert.equal("96",      m.fmts[1])
  end)

  it("parses m= with port count", function()
    local m = grammar.parse_media("video 49170/2 RTP/AVP 96")
    assert.is_table(m)
    assert.equal(49170, m.port)
    assert.equal(2,     m.port_count)
  end)

  it("parses multiple fmt tokens", function()
    local m = grammar.parse_media("video 49170 RTP/AVP 96 97 98")
    assert.is_table(m)
    assert.equal(3,    #m.fmts)
    assert.equal("96", m.fmts[1])
    assert.equal("97", m.fmts[2])
    assert.equal("98", m.fmts[3])
  end)

  it("rejects value missing port/proto/fmt", function()
    local m, pos = grammar.parse_media("audio")
    assert.is_nil(m)
    assert.is_number(pos)
  end)

  it("rejects value with non-numeric port", function()
    local m, pos = grammar.parse_media("audio abc RTP/AVP 0")
    assert.is_nil(m)
    assert.is_number(pos)
  end)

  -- M26 L1: UDP port range (RFC 768).
  it("accepts port at the upper bound (65535)", function()
    local m = grammar.parse_media("video 65535 RTP/AVP 96")
    assert.is_table(m)
    assert.equal(65535, m.port)
  end)

  it("rejects port above UDP range (65536)", function()
    local m, pos = grammar.parse_media("video 65536 RTP/AVP 96")
    assert.is_nil(m)
    assert.is_number(pos)
  end)

  it("rejects port well above UDP range (100000)", function()
    local m, pos = grammar.parse_media("video 100000 RTP/AVP 96")
    assert.is_nil(m)
    assert.is_number(pos)
  end)
end)

describe("sdp.parse — media blocks (M5)", function()
  local sdp = require("parse_sdp")

  local base = {
    "v=0",
    "o=- 1 1 IN IP4 127.0.0.1",
    "s=Test",
    "t=0 0",
  }

  local function make(media_lines)
    local lines = {}
    for _, l in ipairs(base) do lines[#lines + 1] = l end
    for _, l in ipairs(media_lines or {}) do lines[#lines + 1] = l end
    return table.concat(lines, "\r\n") .. "\r\n"
  end

  it("produces an empty media array when no m= blocks are present", function()
    local doc, err = sdp.parse(make())
    assert.is_nil(err)
    assert.is_table(doc.media)
    assert.equal(0, #doc.media)
  end)

  it("parses one video m= block with an attribute", function()
    local doc, err = sdp.parse(make({
      "m=video 49170 RTP/AVP 96",
      "a=rtpmap:96 H264/90000",
    }))
    assert.is_nil(err)
    assert.equal(1,               #doc.media)
    local m = doc.media[1]
    assert.equal("video",         m.media)
    assert.equal(49170,           m.port)
    assert.is_nil(m.port_count)
    assert.equal("RTP/AVP",       m.proto)
    assert.equal(1,               #m.fmts)
    assert.equal("96",            m.fmts[1])
    assert.equal(1,               #m.attributes)
    assert.equal("rtpmap",        m.attributes[1].name)
    assert.equal("96 H264/90000", m.attributes[1].value)
  end)

  it("accepts a=fmtp with payload type and no parameters (RFC 4566 §6)", function()
    local doc, err = sdp.parse(make({
      "m=video 49170 RTP/AVP 96",
      "a=rtpmap:96 H264/90000",
      "a=fmtp:96",
    }))
    assert.is_nil(err)
    assert.is_table(doc)
    local attrs = doc.media[1].attributes
    assert.equal("fmtp", attrs[#attrs].name)
    assert.equal("96",   attrs[#attrs].value)
  end)

  it("parses two media blocks in order", function()
    local doc, err = sdp.parse(make({
      "m=video 49170 RTP/AVP 96",
      "a=rtpmap:96 H264/90000",
      "m=audio 49172 RTP/AVP 0",
      "a=rtpmap:0 PCMU/8000",
    }))
    assert.is_nil(err)
    assert.equal(2,       #doc.media)
    assert.equal("video", doc.media[1].media)
    assert.equal(49170,   doc.media[1].port)
    assert.equal("audio", doc.media[2].media)
    assert.equal(49172,   doc.media[2].port)
  end)

  it("parses m= with port count (/2)", function()
    local doc, err = sdp.parse(make({
      "m=video 49170/2 RTP/AVP 96",
    }))
    assert.is_nil(err)
    assert.equal(49170, doc.media[1].port)
    assert.equal(2,     doc.media[1].port_count)
  end)

  it("parses multiple fmt tokens in a single m= block", function()
    local doc, err = sdp.parse(make({
      "m=video 49170 RTP/AVP 96 97 98",
    }))
    assert.is_nil(err)
    assert.equal(3,    #doc.media[1].fmts)
    assert.equal("96", doc.media[1].fmts[1])
    assert.equal("97", doc.media[1].fmts[2])
    assert.equal("98", doc.media[1].fmts[3])
  end)

  it("parses per-media i= and c= fields", function()
    local doc, err = sdp.parse(make({
      "m=video 49170 RTP/AVP 96",
      "i=A video stream",
      "c=IN IP4 224.2.1.1",
    }))
    assert.is_nil(err)
    assert.equal("A video stream", doc.media[1].info)
    assert.is_table(doc.media[1].connection)
    assert.equal("224.2.1.1",      doc.media[1].connection.address)
  end)

  it("parses per-media b= and a= fields", function()
    local doc, err = sdp.parse(make({
      "m=video 49170 RTP/AVP 96",
      "b=AS:1000",
      "a=recvonly",
    }))
    assert.is_nil(err)
    assert.equal(1,        #doc.media[1].bandwidths)
    assert.equal("AS",     doc.media[1].bandwidths[1].type)
    assert.equal(1000,     doc.media[1].bandwidths[1].value)
    assert.equal(1,        #doc.media[1].attributes)
    assert.equal("recvonly", doc.media[1].attributes[1].name)
  end)

  it("returns nil, err for a malformed m= value", function()
    local doc, err = sdp.parse(make({
      "m=audio",
    }))
    assert.is_nil(doc)
    assert.is_table(err)
    assert.is_string(err.message)
    assert.is_number(err.line)
  end)

  -- RFC 8866 §8.2.3 (audit D1.2): "If the payload type number is
  -- dynamically assigned by this session description, an additional
  -- 'a=rtpmap:' attribute MUST be included to specify the format name
  -- and parameters as defined by the media type registration for the
  -- payload format." Dynamic PT range is 96-127.
  describe("RFC 8866 §8.2.3 dynamic-PT requires a=rtpmap (base tier)", function()
    -- The base-tier check runs in validate.sdp, which is invoked via
    -- doc:validate() (or transitively by st2110/ipmx modes). sdp.parse()
    -- with the default mode only runs the grammar parser.

    it("accepts a dynamic-PT media block with a matching a=rtpmap", function()
      local doc = sdp.parse(make({
        "m=video 5000 RTP/AVP 96",
        "a=rtpmap:96 H264/90000",
      }))
      assert.is_table(doc)
      local ok, err = doc:validate()
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("rejects a dynamic-PT media block with no a=rtpmap", function()
      local doc = sdp.parse(make({
        "m=video 5000 RTP/AVP 96",
      }))
      assert.is_table(doc)
      local ok, err = doc:validate()
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("96", err.message)
      assert.matches("rtpmap", err.message)
      assert.equal("RFC 8866 §8.2.3", err.spec_ref)
    end)

    it("rejects when an a=rtpmap exists but for a different PT", function()
      local doc = sdp.parse(make({
        "m=video 5000 RTP/AVP 96",
        "a=rtpmap:97 H264/90000",  -- wrong PT
      }))
      assert.is_table(doc)
      local ok, err = doc:validate()
      assert.is_nil(ok)
      assert.is_table(err)
      assert.equal("RFC 8866 §8.2.3", err.spec_ref)
    end)

    it("accepts static PT (range 0-95) without a=rtpmap", function()
      -- PT 0 = PCMU/8000 per RFC 3551 §6 static table; no rtpmap required.
      local doc = sdp.parse(make({
        "m=audio 49170 RTP/AVP 0",
      }))
      assert.is_table(doc)
      local ok, err = doc:validate()
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("does not apply the check to non-RTP protocols", function()
      -- D1.2 only fires when m.proto contains "RTP". Other protocols
      -- (e.g. udp) don't have rtpmap requirements at base.
      local doc = sdp.parse(make({
        "m=application 5000 udp 96",
      }))
      assert.is_table(doc)
      local ok, err = doc:validate()
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("accepts a media block with two dynamic PTs both mapped", function()
      local doc = sdp.parse(make({
        "m=video 5000 RTP/AVP 96 97",
        "a=rtpmap:96 H264/90000",
        "a=rtpmap:97 H265/90000",
      }))
      assert.is_table(doc)
      local ok, err = doc:validate()
      assert.is_nil(err)
      assert.equal(true, ok)
    end)

    it("rejects a media block with two dynamic PTs where one lacks rtpmap", function()
      local doc = sdp.parse(make({
        "m=video 5000 RTP/AVP 96 97",
        "a=rtpmap:96 H264/90000",
      }))
      assert.is_table(doc)
      local ok, err = doc:validate()
      assert.is_nil(ok)
      assert.is_table(err)
      assert.matches("97", err.message)
      assert.equal("RFC 8866 §8.2.3", err.spec_ref)
    end)
  end)
end)

describe("sdp — doc object (M6)", function()
  local sdp = require("parse_sdp")

  local minimal = table.concat({
    "v=0",
    "o=- 1 1 IN IP4 127.0.0.1",
    "s=Test",
    "t=0 0",
  }, "\r\n") .. "\r\n"

  it("parsed doc has validate, is_sdp, is_st2110, is_ipmx methods", function()
    local doc = sdp.parse(minimal)
    assert.is_function(doc.validate)
    assert.is_function(doc.is_sdp)
    assert.is_function(doc.is_st2110)
    assert.is_function(doc.is_ipmx)
  end)

  it("sdp.new({}) has validate and is_sdp methods", function()
    local doc = sdp.new({})
    assert.is_function(doc.validate)
    assert.is_function(doc.is_sdp)
  end)

  it("doc:validate() returns true for a valid parsed doc", function()
    local doc = sdp.parse(minimal)
    local ok, err = doc:validate()
    assert.is_true(ok)
    assert.is_nil(err)
  end)

  it("doc:validate('sdp') also returns true", function()
    local doc = sdp.parse(minimal)
    local ok, err = doc:validate("sdp")
    assert.is_true(ok)
    assert.is_nil(err)
  end)

  it("doc:is_sdp() returns true for a valid parsed doc", function()
    local doc = sdp.parse(minimal)
    assert.is_true(doc:is_sdp())
  end)

  it("doc:is_sdp() returns false after mutation removes version", function()
    local doc = sdp.parse(minimal)
    doc.version = nil
    assert.is_false(doc:is_sdp())
  end)

  it("doc:validate() returns nil, err with message after mutation", function()
    local doc = sdp.parse(minimal)
    doc.version = nil
    local ok, err = doc:validate()
    assert.is_nil(ok)
    assert.is_table(err)
    assert.is_string(err.message)
  end)

  it("sdp.new({}) is_sdp() returns false", function()
    local doc = sdp.new({})
    assert.is_false(doc:is_sdp())
  end)

  it("doc:is_st2110() returns false for plain RFC 4566 SDP", function()
    local doc = sdp.parse(minimal)
    assert.is_false(doc:is_st2110())
  end)

  it("doc:is_ipmx() returns false for plain RFC 4566 SDP", function()
    local doc = sdp.parse(minimal)
    assert.is_false(doc:is_ipmx())
  end)

  it("doc:validate() returns nil, err for unknown mode", function()
    local doc = sdp.parse(minimal)
    local ok, err = doc:validate("unknown")
    assert.is_nil(ok)
    assert.is_table(err)
    assert.matches("unknown mode", err.message)
  end)
end)

describe("doc:to_sdp() (M7)", function()
  local sdp = require("parse_sdp")

  local minimal_text = table.concat({
    "v=0",
    "o=- 1 1 IN IP4 127.0.0.1",
    "s=Test",
    "t=0 0",
  }, "\r\n") .. "\r\n"

  local full_text = table.concat({
    "v=0",
    "o=- 1 1 IN IP4 127.0.0.1",
    "s=My Session",
    "i=A description",
    "u=http://example.com",
    "e=user@example.com",
    "p=+1 617 555 6011",
    "c=IN IP4 224.2.1.1",
    "b=AS:128",
    "t=0 0",
    "a=recvonly",
  }, "\r\n") .. "\r\n"

  local media_text = table.concat({
    "v=0",
    "o=- 1 1 IN IP4 127.0.0.1",
    "s=Test",
    "t=0 0",
    "m=video 49170 RTP/AVP 96",
    "c=IN IP4 224.2.1.1",
    "b=AS:1000",
    "a=rtpmap:96 H264/90000",
    "m=audio 49172 RTP/AVP 0",
    "a=rtpmap:0 PCMU/8000",
  }, "\r\n") .. "\r\n"

  local function lines_of(s)
    local t = {}
    for l in s:gmatch("[^\r\n]+") do t[#t + 1] = l end
    return t
  end

  it("serializes minimal SDP to a string", function()
    local doc = sdp.parse(minimal_text)
    assert.is_string(doc:to_sdp())
  end)

  it("uses CRLF line endings (no bare LF)", function()
    local out = sdp.parse(minimal_text):to_sdp()
    local crlf = select(2, out:gsub("\r\n", ""))
    local lf   = select(2, out:gsub("\n",   ""))
    assert.equal(crlf, lf)
  end)

  it("field order: v o s t for minimal SDP", function()
    local ls = lines_of(sdp.parse(minimal_text):to_sdp())
    assert.equal("v=0",                        ls[1])
    assert.equal("o=- 1 1 IN IP4 127.0.0.1",  ls[2])
    assert.equal("s=Test",                     ls[3])
    assert.equal("t=0 0",                      ls[4])
  end)

  it("re-parses cleanly", function()
    local out = sdp.parse(minimal_text):to_sdp()
    local doc2, err = sdp.parse(out)
    assert.is_nil(err)
    assert.is_table(doc2)
  end)

  it("round-trip: parse → serialize → parse is deep-equal for minimal SDP", function()
    local doc1 = sdp.parse(minimal_text)
    local doc2 = sdp.parse(doc1:to_sdp())
    assert.same(doc1, doc2)
  end)

  it("field order: v o s i u e p c b t a for full session", function()
    local ls = lines_of(sdp.parse(full_text):to_sdp())
    assert.equal("v=0",                        ls[1])
    assert.equal("o=- 1 1 IN IP4 127.0.0.1",  ls[2])
    assert.equal("s=My Session",               ls[3])
    assert.equal("i=A description",            ls[4])
    assert.equal("u=http://example.com",       ls[5])
    assert.equal("e=user@example.com",         ls[6])
    assert.equal("p=+1 617 555 6011",          ls[7])
    assert.equal("c=IN IP4 224.2.1.1",         ls[8])
    assert.equal("b=AS:128",                   ls[9])
    assert.equal("t=0 0",                      ls[10])
    assert.equal("a=recvonly",                 ls[11])
  end)

  it("round-trip: full session SDP", function()
    local doc1 = sdp.parse(full_text)
    local doc2 = sdp.parse(doc1:to_sdp())
    assert.same(doc1, doc2)
  end)

  it("serializes two media blocks in order", function()
    local ls = lines_of(sdp.parse(media_text):to_sdp())
    assert.equal("t=0 0",                        ls[4])
    assert.equal("m=video 49170 RTP/AVP 96",     ls[5])
    assert.equal("c=IN IP4 224.2.1.1",           ls[6])
    assert.equal("b=AS:1000",                    ls[7])
    assert.equal("a=rtpmap:96 H264/90000",       ls[8])
    assert.equal("m=audio 49172 RTP/AVP 0",      ls[9])
    assert.equal("a=rtpmap:0 PCMU/8000",         ls[10])
  end)

  it("serializes port count (/2) correctly", function()
    local text = table.concat({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=Test", "t=0 0",
      "m=video 49170/2 RTP/AVP 96",
    }, "\r\n") .. "\r\n"
    local out = sdp.parse(text):to_sdp()
    assert.truthy(out:find("m=video 49170/2 RTP/AVP 96", 1, true))
  end)

  it("round-trip: two media blocks", function()
    local doc1 = sdp.parse(media_text)
    local doc2 = sdp.parse(doc1:to_sdp())
    assert.same(doc1, doc2)
  end)
end)

-- ── M10: to_json ──────────────────────────────────────────────────────────────

describe("to_json", function()
  local sdp = require("parse_sdp")

  local full_text = table.concat({
    "v=0",
    "o=- 1234567890 1 IN IP4 192.168.1.1",
    "s=Test Session",
    "t=0 0",
    "a=tool:test",
    "m=video 5000 RTP/AVP 96",
    "c=IN IP4 239.100.0.1",
    "a=rtpmap:96 H264/90000",
  }, "\r\n") .. "\r\n"

  it("to_json method exists on parsed doc", function()
    local doc = sdp.parse(full_text)
    assert.is_table(doc)
    assert.is_function(doc.to_json)
  end)

  it("returns a string", function()
    local doc = sdp.parse(full_text)
    local out = doc:to_json()
    assert.is_string(out)
  end)

  it("output is valid JSON (parses back without error)", function()
    local dkjson = require("dkjson")
    local doc = sdp.parse(full_text)
    local out = doc:to_json()
    local decoded, _, err = dkjson.decode(out)
    assert.is_nil(err)
    assert.is_table(decoded)
  end)

  it("JSON contains top-level doc fields (version, origin, session, media)", function()
    local dkjson = require("dkjson")
    local doc = sdp.parse(full_text)
    local decoded = dkjson.decode(doc:to_json())
    assert.equal("0", decoded.version)
    assert.is_table(decoded.origin)
    assert.is_table(decoded.session)
    assert.is_table(decoded.media)
  end)

  it("JSON origin fields are correct", function()
    local dkjson = require("dkjson")
    local doc = sdp.parse(full_text)
    local decoded = dkjson.decode(doc:to_json())
    assert.equal("192.168.1.1", decoded.origin.unicast_address)
    assert.equal("IN",          decoded.origin.net_type)
    assert.equal("IP4",         decoded.origin.addr_type)
  end)

  it("JSON session attributes array is present", function()
    local dkjson = require("dkjson")
    local doc = sdp.parse(full_text)
    local decoded = dkjson.decode(doc:to_json())
    assert.is_table(decoded.session.attributes)
    assert.equal(1, #decoded.session.attributes)
    assert.equal("tool", decoded.session.attributes[1].name)
  end)

  it("JSON media array has correct entry", function()
    local dkjson = require("dkjson")
    local doc = sdp.parse(full_text)
    local decoded = dkjson.decode(doc:to_json())
    assert.equal(1, #decoded.media)
    assert.equal("video", decoded.media[1].media)
    assert.equal(5000,    decoded.media[1].port)
  end)

  it("sdp.new({}) has to_json method", function()
    local doc = sdp.new({})
    assert.is_function(doc.to_json)
  end)
end)
