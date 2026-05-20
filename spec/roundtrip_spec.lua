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
local ipmx      = require("parse_sdp.grammar.ipmx")
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

-- ── Phase 8.D: per-attribute renderers (base tier) ──────────────────────────

describe("parse_sdp.serialize — Phase 8.D rtpmap renderer", function()

  it("round-trips a=rtpmap with required fields only (audio, no channels)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 96",
      "a=rtpmap:96 opus/48000",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=rtpmap:96 opus/48000", 1, true))
  end)

  it("round-trips a=rtpmap with channels (stereo)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 96",
      "a=rtpmap:96 opus/48000/2",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=rtpmap:96 opus/48000/2", 1, true))
  end)

  it("round-trips a=rtpmap video form (no channels)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=video 49170 RTP/AVP 96",
      "a=rtpmap:96 H264/90000",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=rtpmap:96 H264/90000", 1, true))
  end)

  it("round-trips multiple a=rtpmap lines in one media block preserving order", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 96 97",
      "a=rtpmap:96 opus/48000/2",
      "a=rtpmap:97 PCMA/8000",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    local p96 = text2:find("a=rtpmap:96", 1, true)
    local p97 = text2:find("a=rtpmap:97", 1, true)
    assert.is_true(p96 < p97)
  end)

  it("returns nil, err when rtpmap is missing payload_type", function()
    local doc = {
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }} },
      media = {{ media = "audio", port = 49170, proto = "RTP/AVP",
                 fmts = {"96"},
                 attributes = {{ name = "rtpmap", encoding = "opus",
                                 clock_rate = 48000 }} }}, -- missing payload_type
    }
    local out, e = serialize.to_sdp(doc)
    assert.is_nil(out)
    assert.matches("payload_type", e.message)
  end)

  it("returns nil, err when rtpmap is missing clock_rate", function()
    local doc = {
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }} },
      media = {{ media = "audio", port = 49170, proto = "RTP/AVP",
                 fmts = {"96"},
                 attributes = {{ name = "rtpmap", payload_type = 96,
                                 encoding = "opus" }} }}, -- missing clock_rate
    }
    local out, e = serialize.to_sdp(doc)
    assert.is_nil(out)
    assert.matches("clock_rate", e.message)
  end)
end)

-- ── Phase 8.D.1: simple value-only attribute renderers ─────────────────────

describe("parse_sdp.serialize — Phase 8.D.1 mid renderer", function()

  it("round-trips a=mid:audio", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 0",
      "a=mid:audio",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=mid:audio", 1, true))
  end)

  it("round-trips a=mid with a numeric-token tag", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 0",
      "a=mid:1",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=mid:1", 1, true))
  end)

  it("returns nil, err when mid is missing tag", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }} },
      media = {{ media = "audio", port = 49170, proto = "RTP/AVP",
                 fmts = {"0"},
                 attributes = {{ name = "mid" }} }}, -- missing tag
    })
    assert.is_nil(out)
    assert.matches("tag", e.message)
  end)
end)

describe("parse_sdp.serialize — Phase 8.D.1 ptime renderer", function()

  it("round-trips a=ptime:20", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 0",
      "a=ptime:20",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=ptime:20", 1, true))
  end)

  it("returns nil, err when ptime is missing value", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }} },
      media = {{ media = "audio", port = 49170, proto = "RTP/AVP",
                 fmts = {"0"},
                 attributes = {{ name = "ptime" }} }}, -- missing value
    })
    assert.is_nil(out)
    assert.matches("value", e.message)
  end)
end)

describe("parse_sdp.serialize — Phase 8.D.1 maxptime renderer", function()

  it("round-trips a=maxptime:120", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 0",
      "a=maxptime:120",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=maxptime:120", 1, true))
  end)

  it("returns nil, err when maxptime is missing value", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }} },
      media = {{ media = "audio", port = 49170, proto = "RTP/AVP",
                 fmts = {"0"},
                 attributes = {{ name = "maxptime" }} }}, -- missing value
    })
    assert.is_nil(out)
    assert.matches("value", e.message)
  end)
end)

describe("parse_sdp.serialize — Phase 8.D.1 framerate renderer", function()

  it("round-trips a=framerate:30", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=video 49170 RTP/AVP 33",
      "a=framerate:30",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=framerate:30", 1, true))
  end)

  it("returns nil, err when framerate is missing value", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }} },
      media = {{ media = "video", port = 49170, proto = "RTP/AVP",
                 fmts = {"33"},
                 attributes = {{ name = "framerate" }} }}, -- missing value
    })
    assert.is_nil(out)
    assert.matches("value", e.message)
  end)
end)

describe("parse_sdp.serialize — Phase 8.D.1 quality renderer", function()

  it("round-trips a=quality:5", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=video 49170 RTP/AVP 33",
      "a=quality:5",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=quality:5", 1, true))
  end)

  it("returns nil, err when quality is missing value", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }} },
      media = {{ media = "video", port = 49170, proto = "RTP/AVP",
                 fmts = {"33"},
                 attributes = {{ name = "quality" }} }}, -- missing value
    })
    assert.is_nil(out)
    assert.matches("value", e.message)
  end)
end)

describe("parse_sdp.serialize — Phase 8.D.1 msid renderer", function()

  it("round-trips a=msid with msid_id only (no appdata)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 0",
      "a=msid:stream-1",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=msid:stream-1", 1, true))
  end)

  it("round-trips a=msid with msid_id and appdata", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 0",
      "a=msid:stream-1 track-a",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=msid:stream-1 track-a", 1, true))
  end)

  it("returns nil, err when msid is missing msid_id", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }} },
      media = {{ media = "audio", port = 49170, proto = "RTP/AVP",
                 fmts = {"0"},
                 attributes = {{ name = "msid", appdata = "track-a" }} }},
    })
    assert.is_nil(out)
    assert.matches("msid_id", e.message)
  end)
end)

describe("parse_sdp.serialize — Phase 8.D.1 ssrc renderer", function()

  it("round-trips a=ssrc with attribute only (no value)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 0",
      "a=ssrc:12345 sendonly",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=ssrc:12345 sendonly", 1, true))
  end)

  it("round-trips a=ssrc with attribute:value", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 0",
      "a=ssrc:12345 cname:user@example.com",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=ssrc:12345 cname:user@example.com", 1, true))
  end)

  it("returns nil, err when ssrc is missing ssrc_id", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }} },
      media = {{ media = "audio", port = 49170, proto = "RTP/AVP",
                 fmts = {"0"},
                 attributes = {{ name = "ssrc", attribute = "sendonly" }} }},
    })
    assert.is_nil(out)
    assert.matches("ssrc_id", e.message)
  end)

  it("returns nil, err when ssrc is missing attribute", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }} },
      media = {{ media = "audio", port = 49170, proto = "RTP/AVP",
                 fmts = {"0"},
                 attributes = {{ name = "ssrc", ssrc_id = 12345 }} }},
    })
    assert.is_nil(out)
    assert.matches("attribute", e.message)
  end)
end)

describe("parse_sdp.serialize — Phase 8.D.1 rtcp-mux renderer", function()

  it("round-trips a=rtcp-mux (flag attribute, no body)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 0",
      "a=rtcp-mux",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=rtcp-mux\r\n", 1, true))
  end)
end)

-- ── Phase 8.D.2: RTP-stack attribute renderers ─────────────────────────────

describe("parse_sdp.serialize — Phase 8.D.2 fmtp renderer", function()

  it("round-trips decomposed kv-list preserving input key order", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=video 49170 RTP/AVP 96",
      "a=rtpmap:96 H264/90000",
      "a=fmtp:96 profile-level-id=42801f;max-mbps=108000;max-fs=3600",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find(
      "a=fmtp:96 profile-level-id=42801f;max-mbps=108000;max-fs=3600\r\n",
      1, true))
  end)

  it("round-trips bare flags mixed with kv pairs", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=video 49170 RTP/AVP 96",
      "a=rtpmap:96 raw/90000",
      "a=fmtp:96 sampling=YCbCr-4:2:2;width=1920;interlace;segmented",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find(
      "a=fmtp:96 sampling=YCbCr-4:2:2;width=1920;interlace;segmented\r\n",
      1, true))
  end)

  it("round-trips a raw byte-string fmtp body (DTMF telephone-event form)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 101",
      "a=rtpmap:101 telephone-event/8000",
      "a=fmtp:101 0-15,256-511",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=fmtp:101 0-15,256-511\r\n", 1, true))
  end)

  it("returns nil, err when fmtp is missing payload_type", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }} },
      media = {{ media = "video", port = 49170, proto = "RTP/AVP",
                 fmts = {"96"},
                 attributes = {
                   { name = "rtpmap", payload_type = 96,
                     encoding = "H264", clock_rate = 90000 },
                   { name = "fmtp", raw = "0-15" }, -- missing payload_type
                 } }},
    })
    assert.is_nil(out)
    assert.matches("payload_type", e.message)
  end)

  it("returns nil, err when fmtp has neither params nor raw", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }} },
      media = {{ media = "video", port = 49170, proto = "RTP/AVP",
                 fmts = {"96"},
                 attributes = {
                   { name = "rtpmap", payload_type = 96,
                     encoding = "H264", clock_rate = 90000 },
                   { name = "fmtp", payload_type = 96 }, -- no body
                 } }},
    })
    assert.is_nil(out)
    assert.matches("params", e.message)
  end)
end)

describe("parse_sdp.serialize — Phase 8.D.2 rtcp renderer", function()

  it("round-trips a=rtcp with port only (no optional triple)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 0",
      "a=rtcp:49171",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=rtcp:49171\r\n", 1, true))
  end)

  it("round-trips a=rtcp with full net/addr/address triple", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 0",
      "a=rtcp:49171 IN IP4 192.0.2.1",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=rtcp:49171 IN IP4 192.0.2.1\r\n", 1, true))
  end)

  it("returns nil, err when rtcp is missing port", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }} },
      media = {{ media = "audio", port = 49170, proto = "RTP/AVP",
                 fmts = {"0"},
                 attributes = {{ name = "rtcp" }} }}, -- missing port
    })
    assert.is_nil(out)
    assert.matches("port", e.message)
  end)

  it("returns nil, err when rtcp triple is partially populated", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }} },
      media = {{ media = "audio", port = 49170, proto = "RTP/AVP",
                 fmts = {"0"},
                 attributes = {{ name = "rtcp", port = 49171,
                                 net_type = "IN" }} }}, -- missing addr_type+address
    })
    assert.is_nil(out)
    assert.matches("addr_type", e.message)
  end)
end)

describe("parse_sdp.serialize — Phase 8.D.2 rtcp-fb renderer", function()

  it("round-trips a=rtcp-fb with numeric payload_type and no parameters", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=video 49170 RTP/AVP 96",
      "a=rtpmap:96 H264/90000",
      "a=rtcp-fb:96 nack",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=rtcp-fb:96 nack\r\n", 1, true))
  end)

  it("round-trips a=rtcp-fb with parameters appended", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=video 49170 RTP/AVP 96",
      "a=rtpmap:96 H264/90000",
      "a=rtcp-fb:96 nack pli",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=rtcp-fb:96 nack pli\r\n", 1, true))
  end)

  it("round-trips a=rtcp-fb with wildcard '*' payload_type", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=video 49170 RTP/AVP 96",
      "a=rtpmap:96 H264/90000",
      "a=rtcp-fb:* ccm fir",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=rtcp-fb:* ccm fir\r\n", 1, true))
  end)

  it("returns nil, err when rtcp-fb is missing feedback_type", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }} },
      media = {{ media = "video", port = 49170, proto = "RTP/AVP",
                 fmts = {"96"},
                 attributes = {
                   { name = "rtpmap", payload_type = 96,
                     encoding = "H264", clock_rate = 90000 },
                   { name = "rtcp-fb", payload_type = 96 }, -- missing feedback_type
                 } }},
    })
    assert.is_nil(out)
    assert.matches("feedback_type", e.message)
  end)
end)

describe("parse_sdp.serialize — Phase 8.D.2 extmap renderer", function()

  it("round-trips a=extmap with id and uri only", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 0",
      "a=extmap:1 urn:ietf:params:rtp-hdrext:ssrc-audio-level",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find(
      "a=extmap:1 urn:ietf:params:rtp-hdrext:ssrc-audio-level\r\n",
      1, true))
  end)

  it("round-trips a=extmap with direction suffix", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 0",
      "a=extmap:2/sendrecv urn:ietf:params:rtp-hdrext:toffset",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find(
      "a=extmap:2/sendrecv urn:ietf:params:rtp-hdrext:toffset\r\n",
      1, true))
  end)

  it("round-trips a=extmap with trailing extension attributes", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 0",
      "a=extmap:3 urn:ietf:params:rtp-hdrext:csrc-audio-level vad=on",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find(
      "a=extmap:3 urn:ietf:params:rtp-hdrext:csrc-audio-level vad=on\r\n",
      1, true))
  end)

  it("returns nil, err when extmap is missing uri", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }} },
      media = {{ media = "audio", port = 49170, proto = "RTP/AVP",
                 fmts = {"0"},
                 attributes = {{ name = "extmap", id = 1 }} }}, -- missing uri
    })
    assert.is_nil(out)
    assert.matches("uri", e.message)
  end)
end)

describe("parse_sdp.serialize — Phase 8.D.2 ssrc-group renderer", function()

  it("round-trips a=ssrc-group with multiple ssrc ids", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 0",
      "a=ssrc-group:FID 1234 5678",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=ssrc-group:FID 1234 5678\r\n", 1, true))
  end)

  it("round-trips a=ssrc-group with a single ssrc id", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 0",
      "a=ssrc-group:FEC 9999",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=ssrc-group:FEC 9999\r\n", 1, true))
  end)

  it("round-trips a=ssrc-group with zero ssrc ids (ABNF allows)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "m=audio 49170 RTP/AVP 0",
      "a=ssrc-group:LS",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=ssrc-group:LS\r\n", 1, true))
  end)

  it("returns nil, err when ssrc-group is missing semantics", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }} },
      media = {{ media = "audio", port = 49170, proto = "RTP/AVP",
                 fmts = {"0"},
                 attributes = {{ name = "ssrc-group",
                                 ssrc_ids = {1234, 5678} }} }},
    })
    assert.is_nil(out)
    assert.matches("semantics", e.message)
  end)
end)

-- ── Phase 8.D.3: clock + grouping attribute renderers ──────────────────────

describe("parse_sdp.serialize — Phase 8.D.3 ts-refclk renderer", function()

  it("round-trips a=ts-refclk:ntp=<address>", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=ts-refclk:ntp=time.example.com",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=ts-refclk:ntp=time.example.com\r\n", 1, true))
  end)

  it("round-trips a=ts-refclk:ntp=/traceable/", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=ts-refclk:ntp=/traceable/",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=ts-refclk:ntp=/traceable/\r\n", 1, true))
  end)

  it("round-trips a=ts-refclk:ptp=<version>:<grandmaster>", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-33-44-55-66-77",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find(
      "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-33-44-55-66-77\r\n",
      1, true))
  end)

  it("round-trips a=ts-refclk:ptp=<version>:<grandmaster>:<domain>", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-33-44-55-66-77:127",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find(
      "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-33-44-55-66-77:127\r\n",
      1, true))
  end)

  it("round-trips a=ts-refclk:ptp=<version>:traceable", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=ts-refclk:ptp=IEEE1588-2008:traceable",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find(
      "a=ts-refclk:ptp=IEEE1588-2008:traceable\r\n", 1, true))
  end)

  it("round-trips a=ts-refclk:private (bare)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=ts-refclk:private",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=ts-refclk:private\r\n", 1, true))
  end)

  it("round-trips a=ts-refclk:private:traceable", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=ts-refclk:private:traceable",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=ts-refclk:private:traceable\r\n", 1, true))
  end)

  it("round-trips a=ts-refclk:gps (bare clock-source)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=ts-refclk:gps",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=ts-refclk:gps\r\n", 1, true))
  end)

  it("round-trips a=ts-refclk:<ext>=<value> (clksrc-ext)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=ts-refclk:custom=opaque-clock-id",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find(
      "a=ts-refclk:custom=opaque-clock-id\r\n", 1, true))
  end)

  it("returns nil, err when ts-refclk:ntp is missing address", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }},
                  attributes = {{ name = "ts-refclk",
                                  source = "ntp" }} }, -- missing address
    })
    assert.is_nil(out)
    assert.matches("address", e.message)
  end)

  it("returns nil, err when ts-refclk:ptp non-traceable is missing grandmaster", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }},
                  attributes = {{ name = "ts-refclk",
                                  source = "ptp",
                                  version = "IEEE1588-2008" }} }, -- missing grandmaster
    })
    assert.is_nil(out)
    assert.matches("grandmaster", e.message)
  end)
end)

describe("parse_sdp.serialize — Phase 8.D.3 mediaclk renderer", function()

  it("round-trips a=mediaclk:sender", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=mediaclk:sender",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=mediaclk:sender\r\n", 1, true))
  end)

  it("round-trips a=mediaclk:direct (bare)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=mediaclk:direct",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=mediaclk:direct\r\n", 1, true))
  end)

  it("round-trips a=mediaclk:direct=<offset>", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=mediaclk:direct=963214424",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=mediaclk:direct=963214424\r\n", 1, true))
  end)

  it("round-trips a=mediaclk:direct=<offset> rate=<num>/<den>", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=mediaclk:direct=0 rate=90000/1",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find(
      "a=mediaclk:direct=0 rate=90000/1\r\n", 1, true))
  end)

  it("round-trips a=mediaclk:IEEE1722=<eui64>", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=mediaclk:IEEE1722=00-11-22-33-44-55-66-77",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find(
      "a=mediaclk:IEEE1722=00-11-22-33-44-55-66-77\r\n", 1, true))
  end)

  it("round-trips a=mediaclk:<ext>=<value> (mediaclock-ext)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=mediaclk:custom=foo",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=mediaclk:custom=foo\r\n", 1, true))
  end)

  it("round-trips a=mediaclk with id= prefix", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=mediaclk:id=src:42 direct=0",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find(
      "a=mediaclk:id=src:42 direct=0\r\n", 1, true))
  end)

  it("returns nil, err when mediaclk:IEEE1722 is missing stream_id", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }},
                  attributes = {{ name = "mediaclk",
                                  mode = "IEEE1722" }} }, -- missing stream_id
    })
    assert.is_nil(out)
    assert.matches("stream_id", e.message)
  end)
end)

describe("parse_sdp.serialize — Phase 8.D.3 group renderer", function()

  it("round-trips a=group with multiple tags", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=group:LS audio video",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=group:LS audio video\r\n", 1, true))
  end)

  it("round-trips a=group with a single tag", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=group:DUP primary",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=group:DUP primary\r\n", 1, true))
  end)

  it("round-trips a=group with zero tags (ABNF allows)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=group:FID",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("a=group:FID\r\n", 1, true))
  end)

  it("returns nil, err when group is missing semantics", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }},
                  attributes = {{ name = "group",
                                  tags = {"audio", "video"} }} }, -- missing semantics
    })
    assert.is_nil(out)
    assert.matches("semantics", e.message)
  end)
end)

describe("parse_sdp.serialize — Phase 8.D.3 source-filter renderer", function()

  it("round-trips a=source-filter incl with single src address", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=source-filter:incl IN IP4 224.2.1.1 192.0.2.10",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find(
      "a=source-filter:incl IN IP4 224.2.1.1 192.0.2.10\r\n", 1, true))
  end)

  it("round-trips a=source-filter incl with multiple src addresses", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=source-filter:incl IN IP4 224.2.1.1 192.0.2.10 192.0.2.11 192.0.2.12",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find(
      "a=source-filter:incl IN IP4 224.2.1.1 192.0.2.10 192.0.2.11 192.0.2.12\r\n",
      1, true))
  end)

  it("round-trips a=source-filter excl with single src address", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=source-filter:excl IN IP4 224.2.1.1 192.0.2.99",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find(
      "a=source-filter:excl IN IP4 224.2.1.1 192.0.2.99\r\n", 1, true))
  end)

  it("round-trips a=source-filter with IP6 addr_type", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=source-filter:incl IN IP6 ff15::101 2001:db8::1",
    })
    local doc1, doc2, text2 = round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find(
      "a=source-filter:incl IN IP6 ff15::101 2001:db8::1\r\n", 1, true))
  end)

  it("returns nil, err when source-filter is missing src_addresses", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }},
                  attributes = {{ name = "source-filter",
                                  filter_mode = "incl",
                                  net_type = "IN", addr_type = "IP4",
                                  dest_address = "224.2.1.1" }} }, -- empty/missing src_addresses
    })
    assert.is_nil(out)
    assert.matches("src_addresses", e.message)
  end)

  it("returns nil, err when source-filter has empty src_addresses list", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }},
                  attributes = {{ name = "source-filter",
                                  filter_mode = "incl",
                                  net_type = "IN", addr_type = "IP4",
                                  dest_address = "224.2.1.1",
                                  src_addresses = {} }} }, -- explicit empty
    })
    assert.is_nil(out)
    assert.matches("src_addresses", e.message)
  end)
end)

-- ── Phase 8.E: IPMX-tier attribute renderers ────────────────────────────────
-- These attributes are added by the IPMX tier via base's a_tier_extensions
-- hook (see parse_sdp/grammar/ipmx.lua). base.match doesn't know them and
-- routes them through the generic carrier, so round-trip has to drive
-- through ipmx.match.
--
-- We use `fail_on_first = false` so the round-trip exercise stays focused
-- on serializer correctness: tier semantic checks (e.g. the infoframe
-- port-must-match-media-plus-3 cross-section SHALL) record findings into
-- ctx without aborting the match, so the captured doc shape is preserved
-- and the deep-equal compare runs on doc tables only. Full fixture
-- validation lands in Phase 8.F.

local function ipmx_round_trip(text)
  local doc1, ctx1 = ipmx.match(text, { fail_on_first = false })
  assert.is_truthy(doc1,
    "input failed to parse via ipmx.match: " .. (ctx1 and ctx1.findings
      and ctx1.findings[1] and ctx1.findings[1].message or "no finding"))
  local text2, e = serialize.to_sdp(doc1)
  assert.is_nil(e, "serialize returned an error")
  assert.is_string(text2)
  local doc2 = ipmx.match(text2, { fail_on_first = false })
  assert.is_truthy(doc2, "re-parse failed")
  return doc1, doc2, text2
end

describe("parse_sdp.serialize — Phase 8.E infoframe renderer", function()

  it("round-trips a=infoframe at session level", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=infoframe:30003 SSN=ST2110-41:2024;DIT=100100",
    })
    local doc1, doc2, text2 = ipmx_round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find(
      "a=infoframe:30003 SSN=ST2110-41:2024;DIT=100100\r\n", 1, true))
  end)

  it("preserves decomposed fields (port / ssn / dit)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=infoframe:30003 SSN=ST2110-41:2024;DIT=100100",
    })
    local doc1 = ipmx_round_trip(text)
    local attr
    for _, a in ipairs(doc1.session.attributes) do
      if a.name == "infoframe" then attr = a; break end
    end
    assert.is_not_nil(attr)
    assert.equal(30003,            attr.port)
    assert.equal("ST2110-41:2024", attr.ssn)
    assert.equal("100100",         attr.dit)
  end)

  it("returns nil, err when infoframe is missing port", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }},
                  attributes = {{ name = "infoframe",
                                  ssn = "ST2110-41:2024",
                                  dit = "100100" }} }, -- missing port
    })
    assert.is_nil(out)
    assert.matches("port", e.message)
  end)

  it("returns nil, err when infoframe is missing ssn", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }},
                  attributes = {{ name = "infoframe", port = 30003,
                                  dit = "100100" }} }, -- missing ssn
    })
    assert.is_nil(out)
    assert.matches("ssn", e.message)
  end)

  it("returns nil, err when infoframe is missing dit", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }},
                  attributes = {{ name = "infoframe", port = 30003,
                                  ssn = "ST2110-41:2024" }} }, -- missing dit
    })
    assert.is_nil(out)
    assert.matches("dit", e.message)
  end)
end)

describe("parse_sdp.serialize — Phase 8.E hkep renderer", function()

  it("round-trips a=hkep at session level (IP4)", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=hkep:6001 IN IP4 192.0.2.10"
        .. " 6b2a8d4f-1234-5678-9abc-def0123456ab 01-02-03-04-05",
    })
    local doc1, doc2, text2 = ipmx_round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find(
      "a=hkep:6001 IN IP4 192.0.2.10"
        .. " 6b2a8d4f-1234-5678-9abc-def0123456ab 01-02-03-04-05\r\n",
      1, true))
  end)

  it("round-trips a=hkep with IP6 addrtype", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=hkep:6002 IN IP6 2001:db8::1"
        .. " 11111111-2222-3333-4444-555555555555 aa-bb-cc-dd-ee",
    })
    local doc1, doc2, text2 = ipmx_round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find(
      "a=hkep:6002 IN IP6 2001:db8::1"
        .. " 11111111-2222-3333-4444-555555555555 aa-bb-cc-dd-ee\r\n",
      1, true))
  end)

  it("preserves decomposed fields", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=hkep:6001 IN IP4 192.0.2.10"
        .. " 6b2a8d4f-1234-5678-9abc-def0123456ab 01-02-03-04-05",
    })
    local doc1 = ipmx_round_trip(text)
    local attr
    for _, a in ipairs(doc1.session.attributes) do
      if a.name == "hkep" then attr = a; break end
    end
    assert.is_not_nil(attr)
    assert.equal(6001,                                   attr.port)
    assert.equal("IN",                                   attr.nettype)
    assert.equal("IP4",                                  attr.addrtype)
    assert.equal("192.0.2.10",                           attr.addr)
    assert.equal("6b2a8d4f-1234-5678-9abc-def0123456ab", attr.node_id)
    assert.equal("01-02-03-04-05",                       attr.port_id)
  end)

  it("returns nil, err when hkep is missing port_id", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }},
                  attributes = {{ name = "hkep", port = 6001,
                                  nettype = "IN", addrtype = "IP4",
                                  addr = "192.0.2.10",
                                  node_id =
                                    "6b2a8d4f-1234-5678-9abc-def0123456ab"
                                }} }, -- missing port_id
    })
    assert.is_nil(out)
    assert.matches("port_id", e.message)
  end)

  it("returns nil, err when hkep is missing addr", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }},
                  attributes = {{ name = "hkep", port = 6001,
                                  nettype = "IN", addrtype = "IP4",
                                  node_id =
                                    "6b2a8d4f-1234-5678-9abc-def0123456ab",
                                  port_id = "01-02-03-04-05" }} }, -- missing addr
    })
    assert.is_nil(out)
    assert.matches("addr", e.message)
  end)
end)

describe("parse_sdp.serialize — Phase 8.E privacy renderer", function()

  it("round-trips a=privacy with all six required params", function()
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=privacy:protocol=RTP;mode=AES-128-CTR;iv=0123456789abcdef;"
        .. "key_generator=0123456789abcdef0123456789abcdef;"
        .. "key_version=00112233;key_id=fedcba9876543210",
    })
    local doc1, doc2, text2 = ipmx_round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find(
      "a=privacy:protocol=RTP;mode=AES-128-CTR;iv=0123456789abcdef;"
        .. "key_generator=0123456789abcdef0123456789abcdef;"
        .. "key_version=00112233;key_id=fedcba9876543210\r\n",
      1, true))
  end)

  it("preserves param key order across round-trip", function()
    -- Order intentionally non-canonical to verify the ordered Ct shape
    -- (the Phase 8.C invariant) survives serialize → re-parse.
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=privacy:key_id=fedcba9876543210;iv=0123456789abcdef;"
        .. "key_version=00112233;mode=AES-128-CTR;protocol=RTP;"
        .. "key_generator=0123456789abcdef0123456789abcdef",
    })
    local doc1, doc2, text2 = ipmx_round_trip(text)
    assert.same(doc1, doc2)
    -- First emitted param is the first one captured (key_id).
    assert.truthy(text2:find("a=privacy:key_id=", 1, true))
  end)

  it("normalizes spacing around ';' separators (no-space emission)", function()
    -- The grammar tolerates ";<SP>" between entries, but the renderer
    -- emits ";". Both forms decompose to the same params + trailing_semi
    -- doc shape, so doc1 == doc2 even though text2 ≠ input text.
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=privacy: protocol=RTP; mode=AES-128-CTR; iv=0123456789abcdef;"
        .. " key_generator=0123456789abcdef0123456789abcdef;"
        .. " key_version=00112233; key_id=fedcba9876543210",
    })
    local doc1, doc2, text2 = ipmx_round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find(
      "a=privacy:protocol=RTP;mode=AES-128-CTR;", 1, true))
  end)

  it("preserves trailing semicolon when captured in doc shape", function()
    -- The §13 trailing-semi-forbidden SHALL records a finding under
    -- fail_on_first = false, but the doc still captures trailing_semi=true.
    -- The renderer must round-trip that captured shape faithfully so a
    -- consumer who parses a malformed line and re-serializes sees the
    -- same malformed line (and the same finding) on the second parse.
    local text = lines_to_sdp({
      "v=0", "o=- 1 1 IN IP4 127.0.0.1", "s=X", "t=0 0",
      "a=privacy:protocol=RTP;mode=AES-128-CTR;iv=0123456789abcdef;"
        .. "key_generator=0123456789abcdef0123456789abcdef;"
        .. "key_version=00112233;key_id=fedcba9876543210;",
    })
    local doc1, doc2, text2 = ipmx_round_trip(text)
    assert.same(doc1, doc2)
    assert.truthy(text2:find("key_id=fedcba9876543210;\r\n", 1, true))
  end)

  it("returns nil, err when privacy params list is empty", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }},
                  attributes = {{ name = "privacy", params = {} }} }, -- empty
    })
    assert.is_nil(out)
    assert.matches("params", e.message)
  end)

  it("returns nil, err when privacy params field is absent", function()
    local out, e = serialize.to_sdp({
      version = "0",
      origin = { username = "-", sess_id = "1", sess_version = "1",
                 net_type = "IN", addr_type = "IP4",
                 unicast_address = "127.0.0.1" },
      session = { name = "X", time_descriptions = {{ start = 0, stop = 0 }},
                  attributes = {{ name = "privacy" }} }, -- no params
    })
    assert.is_nil(out)
    assert.matches("params", e.message)
  end)
end)
