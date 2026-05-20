---@diagnostic disable
-- Phase 8: round-trip tests for parse_sdp.serialize.
--
-- The Phase 8 contract:
--   text ──base.match──> doc ──serialize.to_sdp──> text' ──base.match──> doc'
--   assert.same(doc, doc')
--
-- 8.A bootstrap scope: minimal SDP (v / o / s / t) only.
-- 8.B adds optional session fields (i / u / e / p / c / b), r= repeats,
--     z= time zones, generic + flag a= attributes (compound names like
--     rtpmap / fmtp / mid defer to 8.D), and media blocks (m + i / c / b /
--     generic+flag a=). Static payload types only (≤95) — dynamic PTs
--     require a=rtpmap which 8.D will register.
-- 8.D / 8.E add per-attribute fixtures.
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

-- ── Phase 8.B: optional session fields + repeats + time zones + media ───────

describe("parse_sdp.serialize — Phase 8.B optional session fields", function()

  it("round-trips i / u / e / p / c / b together", function()
    local text = lines_to_sdp({
      "v=0",
      "o=alice 2890844526 2890844527 IN IP4 192.0.2.1",
      "s=Session",
      "i=A description",
      "u=http://example.com/",
      "e=alice@example.com",
      "p=+1-555-0100",
      "c=IN IP4 192.0.2.1",
      "b=AS:128",
      "t=0 0",
    })
    local doc1, doc2 = round_trip(text)
    assert.same(doc1, doc2)
  end)

  it("preserves multiple e= and p= lines in input order", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "e=alice@example.com",
      "e=bob@example.com",
      "p=+1-555-0100",
      "p=+1-555-0101",
      "t=0 0",
    })
    local doc1, doc2 = round_trip(text)
    assert.same(doc1, doc2)
  end)

  it("preserves multiple b= lines (different bw-types)", function()
    -- RFC 8866 §5 ordering: b= comes before t= at session level.
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "b=AS:128",
      "b=CT:1024",
      "t=0 0",
    })
    local doc1, doc2 = round_trip(text)
    assert.same(doc1, doc2)
  end)
end)

describe("parse_sdp.serialize — Phase 8.B time descriptions + repeats", function()

  it("round-trips multiple t= blocks", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "t=3034423619 3042462419",
      "t=3050000000 3060000000",
    })
    local doc1, doc2 = round_trip(text)
    assert.same(doc1, doc2)
  end)

  it("round-trips r= repeats (numeric form, RFC 8866 §5.10 example)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "t=3034423619 3042462419",
      "r=604800 3600 0 90000",
    })
    local doc1, doc2 = round_trip(text)
    assert.same(doc1, doc2)
  end)

  it("round-trips r= repeats with typed-time units (7d 1h 0 25h)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "t=3034423619 3042462419",
      "r=7d 1h 0 25h",
    })
    local doc1, doc2 = round_trip(text)
    assert.same(doc1, doc2)
  end)

  it("round-trips multiple r= repeats per t= block", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X",
      "t=3034423619 3042462419",
      "r=604800 3600 0 90000",
      "r=86400 3600 0 90000",
    })
    local doc1, doc2 = round_trip(text)
    assert.same(doc1, doc2)
  end)

  it("returns nil, err when r= block is missing offsets", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X",
                  time_descriptions = {{ start = 0, stop = 0,
                    repeats = {{ interval = "1d", duration = "1h" }} }} }, -- no offsets
      media = {},
    })
    assert.is_nil(out)
    assert.matches("offsets", e.message)
  end)
end)

describe("parse_sdp.serialize — Phase 8.B z= time zones", function()

  it("round-trips z= with one (adj, offset) pair", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "z=2882844526 -1h",
    })
    local doc1, doc2 = round_trip(text)
    assert.same(doc1, doc2)
  end)

  it("round-trips z= with multiple pairs", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "z=2882844526 -1h 2898848070 0",
    })
    local doc1, doc2 = round_trip(text)
    assert.same(doc1, doc2)
  end)
end)

describe("parse_sdp.serialize — Phase 8.B session-level a= attributes", function()

  it("round-trips flag attributes (a=recvonly / sendonly / inactive)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=recvonly",
      "a=inactive",
      "a=sendrecv",
    })
    local doc1, doc2 = round_trip(text)
    assert.same(doc1, doc2)
  end)

  it("round-trips generic name:value attributes", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=tool:OpenMCU 3.0",
      "a=type:broadcast",
      "a=charset:UTF-8",
      "a=sdplang:en",
      "a=lang:en",
    })
    local doc1, doc2 = round_trip(text)
    assert.same(doc1, doc2)
  end)

  it("preserves attribute order across round trip", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=recvonly",
      "a=tool:Test 1.0",
      "a=type:broadcast",
    })
    local _, _, text2 = round_trip(text)
    local lines = {}
    for l in text2:gmatch("[^\r\n]+") do lines[#lines + 1] = l end
    -- a= lines are the last three after v/o/s/t.
    assert.equal("a=recvonly",       lines[5])
    assert.equal("a=tool:Test 1.0",  lines[6])
    assert.equal("a=type:broadcast", lines[7])
  end)
end)

describe("parse_sdp.serialize — Phase 8.B media blocks", function()

  it("round-trips one media block with all optional fields", function()
    -- IPv4 multicast c= requires /TTL per RFC 8866 §5.7.
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 0", -- PT 0 = PCMU, static (no rtpmap needed)
      "i=Primary audio",
      "c=IN IP4 224.2.1.1/127",
      "b=AS:64",
      "a=sendonly",
    })
    local doc1, doc2 = round_trip(text)
    assert.same(doc1, doc2)
  end)

  it("round-trips m= with port_count (49170/2)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=video 49170/2 RTP/AVP 33", -- PT 33 = MPV, static
    })
    local _, doc2, text2 = round_trip(text)
    assert.is_table(doc2)
    assert.truthy(text2:find("m=video 49170/2 RTP/AVP 33", 1, true))
  end)

  it("round-trips multiple media blocks in order", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 0",
      "a=sendonly",
      "m=video 51372 RTP/AVP 33",
      "a=sendonly",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    -- m=audio precedes m=video in the output.
    local a_pos = text2:find("m=audio", 1, true)
    local v_pos = text2:find("m=video", 1, true)
    assert.is_true(a_pos < v_pos)
  end)

  it("round-trips m= with multiple fmts", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 0 8 9", -- PCMU + PCMA + G722, all static
    })
    local _, _, text2 = round_trip(text)
    assert.truthy(text2:find("m=audio 49170 RTP/AVP 0 8 9", 1, true))
  end)

  it("returns nil, err when m.media is absent", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }} },
      media = {{ port = 5004, proto = "RTP/AVP", fmts = {"0"} }}, -- no media
    })
    assert.is_nil(out)
    assert.matches("media%[0%]%.media", e.field_path)
  end)

  it("returns nil, err when m.fmts is empty", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }} },
      media = {{ media = "audio", port = 5004, proto = "RTP/AVP", fmts = {} }},
    })
    assert.is_nil(out)
    assert.matches("fmts", e.message)
  end)

  it("returns nil, err when b= block is missing type", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X",
                  time_descriptions = {{ start = 0, stop = 0 }},
                  bandwidths = {{ value = 128 }} }, -- no type
      media = {},
    })
    assert.is_nil(out)
    assert.matches("type", e.message)
  end)

  it("returns nil, err when c= block is missing address", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X",
                  time_descriptions = {{ start = 0, stop = 0 }},
                  connection = { net_type = "IN", addr_type = "IP4" } }, -- no address
      media = {},
    })
    assert.is_nil(out)
    assert.matches("address", e.message)
  end)
end)
