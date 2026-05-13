describe("parse_sdp", function()
  it("loads without error", function()
    local sdp = require("parse_sdp")
    assert.is_table(sdp)
  end)
end)

describe("grammar.tokenize_line", function()
  local grammar = require("lib.grammar")

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
  local grammar = require("lib.grammar")

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
  local grammar = require("lib.grammar")

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
  local grammar = require("lib.grammar")

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

  it("returns nil, err for empty input", function()
    local doc, err = sdp.parse("")
    assert.is_nil(doc)
    assert.is_table(err)
    assert.equal(1, err.line)
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
  local grammar = require("lib.grammar")

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
end)
