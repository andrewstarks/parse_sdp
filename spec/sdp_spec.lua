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
