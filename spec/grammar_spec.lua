---@diagnostic disable
-- Tests for the LPEG primitive parsers exposed via parse_sdp._grammar.
-- These are characterization tests for the parser internals — not part
-- of the public contract per CLAUDE.md. They are useful for parser-dev
-- iteration and sharp regression diagnostics but are white-box: a
-- refactor that inlined these helpers into parser.parse would fail
-- them even with identical public-API behavior. Tagged `NOT-SPEC:
-- implementation` so the next reader knows what they're signing up for.

describe("grammar.tokenize_line", function()
  local grammar = require("parse_sdp")._grammar

  -- NOT-SPEC: implementation
  it("parses a valid CRLF line", function()
    local t, v, offset = grammar.tokenize_line("v=0\r\n")
    assert.equal("v", t)
    assert.equal("0", v)
    assert.equal(3, offset)
  end)

  -- NOT-SPEC: implementation
  it("parses a valid LF-only line", function()
    local t, v, offset = grammar.tokenize_line("s=My Session\n")
    assert.equal("s", t)
    assert.equal("My Session", v)
    assert.equal(3, offset)
  end)

  -- NOT-SPEC: implementation
  it("parses a line with no trailing newline", function()
    local t, v, offset = grammar.tokenize_line("v=0")
    assert.equal("v", t)
    assert.equal("0", v)
    assert.equal(3, offset)
  end)

  -- NOT-SPEC: implementation
  it("parses a line with a complex value", function()
    local t, v, offset = grammar.tokenize_line("o=- 0 0 IN IP4 127.0.0.1\r\n")
    assert.equal("o", t)
    assert.equal("- 0 0 IN IP4 127.0.0.1", v)
    assert.equal(3, offset)
  end)

  -- NOT-SPEC: implementation
  it("rejects empty input", function()
    local t, pos = grammar.tokenize_line("")
    assert.is_nil(t)
    assert.is_number(pos)
  end)

  -- NOT-SPEC: implementation
  it("rejects a line with no equals sign", function()
    local t, pos = grammar.tokenize_line("invalid\r\n")
    assert.is_nil(t)
    assert.is_number(pos)
  end)

  -- NOT-SPEC: implementation
  it("rejects a line with multi-char type field", function()
    local t, pos = grammar.tokenize_line("ab=value\r\n")
    assert.is_nil(t)
    assert.is_number(pos)
  end)

  -- NOT-SPEC: implementation
  it("rejects a line with non-alpha type character", function()
    local t, pos = grammar.tokenize_line("1=value\r\n")
    assert.is_nil(t)
    assert.is_number(pos)
  end)

  -- NOT-SPEC: implementation
  it("rejects a line with an empty value", function()
    local t, pos = grammar.tokenize_line("v=\r\n")
    assert.is_nil(t)
    assert.is_number(pos)
  end)

  -- NOT-SPEC: implementation
  it("returns failure position 1 for non-alpha type", function()
    local t, pos = grammar.tokenize_line("1=value\r\n")
    assert.is_nil(t)
    assert.equal(1, pos)
  end)

  -- NOT-SPEC: implementation
  it("returns failure position after type char for multi-char type", function()
    local t, pos = grammar.tokenize_line("ab=value\r\n")
    assert.is_nil(t)
    assert.equal(2, pos)  -- failed after consuming 'a'
  end)

  -- NOT-SPEC: implementation
  it("returns failure position at value start for empty value", function()
    local t, pos = grammar.tokenize_line("v=\r\n")
    assert.is_nil(t)
    assert.equal(3, pos)  -- failed at position 3 where value was expected
  end)
end)

describe("grammar.parse_version", function()
  local grammar = require("parse_sdp")._grammar

  -- NOT-SPEC: implementation
  it("accepts '0'", function()
    local v = grammar.parse_version("0")
    assert.equal("0", v)
  end)

  -- NOT-SPEC: implementation
  it("rejects '1'", function()
    local v, pos = grammar.parse_version("1")
    assert.is_nil(v)
    assert.is_number(pos)
  end)

  -- NOT-SPEC: implementation
  it("rejects empty string", function()
    local v, pos = grammar.parse_version("")
    assert.is_nil(v)
    assert.is_number(pos)
  end)

  -- NOT-SPEC: implementation
  it("rejects '0' with trailing content", function()
    local v, pos = grammar.parse_version("0 extra")
    assert.is_nil(v)
    assert.is_number(pos)
  end)
end)

describe("grammar.parse_origin", function()
  local grammar = require("parse_sdp")._grammar

  -- NOT-SPEC: implementation
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

  -- NOT-SPEC: implementation
  it("accepts IP6 address type", function()
    local o = grammar.parse_origin("- 1 1 IN IP6 ::1")
    assert.is_table(o)
    assert.equal("IP6", o.addr_type)
    assert.equal("::1", o.unicast_address)
  end)

  -- NOT-SPEC: implementation
  it("rejects too few fields", function()
    local o, pos = grammar.parse_origin("invalid")
    assert.is_nil(o)
    assert.is_number(pos)
  end)

  -- NOT-SPEC: implementation
  it("rejects non-numeric sess-id", function()
    local o, pos = grammar.parse_origin("- abc 1 IN IP4 192.0.2.1")
    assert.is_nil(o)
    assert.is_number(pos)
  end)

  -- NOT-SPEC: implementation
  it("rejects unknown nettype", function()
    local o, pos = grammar.parse_origin("- 1 1 OUT IP4 192.0.2.1")
    assert.is_nil(o)
    assert.is_number(pos)
  end)

  -- NOT-SPEC: implementation
  it("rejects unknown addrtype", function()
    local o, pos = grammar.parse_origin("- 1 1 IN IP5 192.0.2.1")
    assert.is_nil(o)
    assert.is_number(pos)
  end)
end)

describe("grammar.parse_timing", function()
  local grammar = require("parse_sdp")._grammar

  -- NOT-SPEC: implementation
  it("parses '0 0'", function()
    local t = grammar.parse_timing("0 0")
    assert.is_table(t)
    assert.equal(0, t.start)
    assert.equal(0, t.stop)
  end)

  -- NOT-SPEC: implementation
  it("parses NTP timestamps", function()
    local t = grammar.parse_timing("3034423619 3042462419")
    assert.is_table(t)
    assert.equal(3034423619, t.start)
    assert.equal(3042462419, t.stop)
  end)

  -- NOT-SPEC: implementation
  it("rejects missing stop time", function()
    local t, pos = grammar.parse_timing("0")
    assert.is_nil(t)
    assert.is_number(pos)
  end)

  -- NOT-SPEC: implementation
  it("rejects non-numeric values", function()
    local t, pos = grammar.parse_timing("abc def")
    assert.is_nil(t)
    assert.is_number(pos)
  end)

  -- NOT-SPEC: implementation
  it("rejects trailing content after stop time", function()
    local t, pos = grammar.parse_timing("0 0 extra")
    assert.is_nil(t)
    assert.is_number(pos)
  end)
end)

describe("grammar.parse_media", function()
  local grammar = require("parse_sdp")._grammar

  -- NOT-SPEC: implementation
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

  -- NOT-SPEC: implementation
  it("parses m= with port count", function()
    local m = grammar.parse_media("video 49170/2 RTP/AVP 96")
    assert.is_table(m)
    assert.equal(49170, m.port)
    assert.equal(2,     m.port_count)
  end)

  -- NOT-SPEC: implementation
  it("parses multiple fmt tokens", function()
    local m = grammar.parse_media("video 49170 RTP/AVP 96 97 98")
    assert.is_table(m)
    assert.equal(3,    #m.fmts)
    assert.equal("96", m.fmts[1])
    assert.equal("97", m.fmts[2])
    assert.equal("98", m.fmts[3])
  end)

  -- NOT-SPEC: implementation
  it("rejects value missing port/proto/fmt", function()
    local m, pos = grammar.parse_media("audio")
    assert.is_nil(m)
    assert.is_number(pos)
  end)

  -- NOT-SPEC: implementation
  it("rejects value with non-numeric port", function()
    local m, pos = grammar.parse_media("audio abc RTP/AVP 0")
    assert.is_nil(m)
    assert.is_number(pos)
  end)

  -- M26 L1: UDP port range (RFC 768).
  -- NOT-SPEC: implementation
  it("accepts port at the upper bound (65535)", function()
    local m = grammar.parse_media("video 65535 RTP/AVP 96")
    assert.is_table(m)
    assert.equal(65535, m.port)
  end)

  -- NOT-SPEC: implementation
  it("rejects port above UDP range (65536)", function()
    local m, pos = grammar.parse_media("video 65536 RTP/AVP 96")
    assert.is_nil(m)
    assert.is_number(pos)
  end)

  -- NOT-SPEC: implementation
  it("rejects port well above UDP range (100000)", function()
    local m, pos = grammar.parse_media("video 100000 RTP/AVP 96")
    assert.is_nil(m)
    assert.is_number(pos)
  end)
end)
