---@diagnostic disable
-- Phase 8: round-trip tests for parse_sdp.serialize.
--
-- The Phase 8 contract:
--   text ──base.match──> doc ──serialize.to_sdp──> text' ──base.match──> doc'
--   assert.same(doc, doc')
--
-- 8.A bootstrap scope: minimal SDP (v / o / s / t) only. 8.B will extend
-- this file with optional session-level fields, multiple time descriptions,
-- r= repeats, and z= time zones. 8.D / 8.E add per-attribute fixtures.
--
-- The "structurally complete" contract is also tested here: missing required
-- fields → serializer returns nil + err, not a half-rendered string.

local base      = require("parse_sdp.grammar.base")
local serialize = require("parse_sdp.serialize")

local function lines_to_sdp(lines)
  return table.concat(lines, "\r\n") .. "\r\n"
end

-- Parse → serialize → parse, returning the two doc tables for deep-equal.
local function round_trip(text)
  local doc1, ctx1 = base.match(text)
  assert.is_truthy(doc1,
    "input failed to parse via base.match: " .. (ctx1 and ctx1.findings
      and ctx1.findings[1] and ctx1.findings[1].message or "no finding"))
  local text2, e = serialize.to_sdp(doc1)
  assert.is_nil(e, "serialize returned an error")
  assert.is_string(text2)
  local doc2 = base.match(text2)
  assert.is_truthy(doc2, "re-parse failed")
  return doc1, doc2, text2
end

describe("parse_sdp.serialize — Phase 8.A bootstrap (v/o/s/t)", function()

  local MINIMAL = lines_to_sdp({
    "v=0",
    "o=- 1234567890 1 IN IP4 192.0.2.1",
    "s=Test Session",
    "t=0 0",
  })

  it("emits CRLF line endings", function()
    local doc1 = base.match(MINIMAL)
    local out  = serialize.to_sdp(doc1)
    -- Equal CRLF count to LF count means every LF has a preceding CR.
    local crlf = select(2, out:gsub("\r\n", ""))
    local lf   = select(2, out:gsub("\n",   ""))
    assert.equal(crlf, lf)
    assert.is_true(crlf >= 4) -- v, o, s, t
  end)

  it("emits RFC 8866 §5 field order (v, o, s, t)", function()
    local doc1 = base.match(MINIMAL)
    local out  = serialize.to_sdp(doc1)
    local lines = {}
    for l in out:gmatch("[^\r\n]+") do lines[#lines + 1] = l end
    assert.equal("v=0",                            lines[1])
    assert.equal("o=- 1234567890 1 IN IP4 192.0.2.1", lines[2])
    assert.equal("s=Test Session",                 lines[3])
    assert.equal("t=0 0",                          lines[4])
  end)

  it("re-parses cleanly (parse → serialize → parse)", function()
    local doc1, doc2 = round_trip(MINIMAL)
    assert.is_table(doc2)
  end)

  it("round-trip is deep-equal for minimal SDP", function()
    local doc1, doc2 = round_trip(MINIMAL)
    assert.same(doc1, doc2)
  end)

  -- ── Structural-completeness errors (no validation, just renderability) ──

  it("returns nil, err when version is absent", function()
    local out, e = serialize.to_sdp({
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }} },
      media = {},
    })
    assert.is_nil(out)
    assert.is_table(e)
    assert.matches("version", e.message)
  end)

  it("returns nil, err when origin is absent", function()
    local out, e = serialize.to_sdp({
      version = "0",
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }} },
      media = {},
    })
    assert.is_nil(out)
    assert.matches("origin", e.message)
  end)

  it("returns nil, err when an origin sub-field is absent", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4" }, -- missing unicast_address
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }} },
      media = {},
    })
    assert.is_nil(out)
    assert.matches("unicast_address", e.message)
    assert.equal("origin.unicast_address", e.field_path)
  end)

  it("returns nil, err when session.name is absent", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { time_descriptions = {{ start = 0, stop = 0 }} },
      media = {},
    })
    assert.is_nil(out)
    assert.matches("session%.name", e.message)
  end)

  it("returns nil, err when session.time_descriptions is absent", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X" },
      media = {},
    })
    assert.is_nil(out)
    assert.matches("time_descriptions", e.message)
  end)

  it("returns nil, err when a t= block is missing start", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X",
                  time_descriptions = {{ stop = 0 }} }, -- missing start
      media = {},
    })
    assert.is_nil(out)
    assert.matches("start", e.message)
  end)

  it("rejects non-table input", function()
    local out, e = serialize.to_sdp("v=0\r\n")
    assert.is_nil(out)
    assert.matches("not a table", e.message)
  end)
end)
