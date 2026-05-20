---@diagnostic disable
-- Phase 6.A: composition mechanism tests for base.extend(parent, overrides).
-- Covers:
--   - shape of the returned child table
--   - identity behavior of `extend(base, {})` (empty overrides)
--   - rule-override merging (child wins on collision)
--   - semantic_checks list extension (child's checks appended in order)
--   - chaining: child can itself be extended (Phase 7 IPMX precondition)
--   - parse_sdp.grammar.st2110 is the empty-extend shell

local base   = require("parse_sdp.grammar.base")
local lpeg   = require("lpeg")
local errors = require("parse_sdp.errors")

local function lines_to_sdp(lines)
  return table.concat(lines, "\r\n") .. "\r\n"
end

local MINIMAL = lines_to_sdp({
  "v=0",
  "o=- 1234567890 1 IN IP4 192.0.2.1",
  "s=Test Session",
  "t=0 0",
})

-- ST 2110-10:2022 §8.2 + §8.3 require every media block to carry
-- a=ts-refclk and a media-level a=mediaclk (Phase 6.D.A); include both
-- so the st2110 tier accepts this fixture once those checks fire.
local MINIMAL_WITH_RTPMAP = lines_to_sdp({
  "v=0",
  "o=- 1234567890 1 IN IP4 192.0.2.1",
  "s=Test Session",
  "t=0 0",
  "m=video 49170 RTP/AVP 96",
  "a=rtpmap:96 H264/90000",
  "a=ts-refclk:localmac=00-11-22-33-44-55",
  "a=mediaclk:sender",
})

describe("base.extend — composition mechanism", function()

  -- NOT-SPEC: library
  it("returns a child mirroring base's exported shape", function()
    local child = base.extend(base, {})
    assert.is_table(child.rules)
    assert.is_table(child.semantic_checks)
    assert.is_function(child.make_validate_doc)
    assert.is_function(child.extend)
    assert.is_function(child.match)
    assert.is_not_nil(child.grammar)
    assert.is_function(child.make_document_body)
  end)

  -- NOT-SPEC: library
  it("empty-extend grammar accepts every input the base grammar accepts", function()
    local child = base.extend(base, {})
    assert.is_truthy(child.match(MINIMAL))
    assert.is_truthy(child.match(MINIMAL_WITH_RTPMAP))
  end)

  -- NOT-SPEC: library
  it("empty-extend grammar rejects every input the base grammar rejects", function()
    local child = base.extend(base, {})
    -- v= MUST be "0" (RFC 8866 §5.1)
    local bad = lines_to_sdp({
      "v=1",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=x",
      "t=0 0",
    })
    assert.is_nil((child.match(bad)))
  end)

  -- NOT-SPEC: library
  it("returns distinct grammar / rules tables (not aliases of base)", function()
    local child = base.extend(base, {})
    assert.are_not.equal(base.grammar, child.grammar)
    assert.are_not.equal(base.rules,   child.rules)
    assert.are_not.equal(base.semantic_checks, child.semantic_checks)
  end)

  -- NOT-SPEC: library
  it("rule override replaces the parent rule in the child grammar", function()
    -- Override v_value to require "1" instead of "0".  This is non-spec —
    -- the test only exercises the composition mechanism, not a real check.
    local child = base.extend(base, {
      rules = { v_value = lpeg.C(lpeg.P("1")) },
    })
    -- Child rejects v=0 (which base accepts)
    assert.is_nil((child.match(MINIMAL)))
    -- Child accepts v=1 (which base rejects)
    local v1 = lines_to_sdp({
      "v=1",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=x",
      "t=0 0",
    })
    assert.is_truthy(child.match(v1))
    -- Base is unchanged by the extend call
    assert.is_truthy(base.match(MINIMAL))
    assert.is_nil((base.match(v1)))
  end)

  -- NOT-SPEC: library
  it("appends semantic_checks to the parent list in order", function()
    local call_log = {}
    local function check_a(doc, ctx)
      call_log[#call_log + 1] = "a"
      return true
    end
    local function check_b(doc, ctx)
      call_log[#call_log + 1] = "b"
      return true
    end
    local child = base.extend(base, {
      semantic_checks = { check_a, check_b },
    })
    -- Child inherits base's 4 checks then appends 2
    assert.equal(#base.semantic_checks + 2, #child.semantic_checks)
    -- Match runs them in order after the inherited ones
    assert.is_truthy(child.match(MINIMAL))
    assert.same({ "a", "b" }, call_log)
  end)

  -- NOT-SPEC: library
  it("a semantic check returning false fails the match", function()
    local function reject(doc, ctx)
      -- Use a real registered id to exercise errors.record's path.
      return errors.record(ctx, "sdp.v.must-be-zero",
                            { line = 0, col = 0, context = "" })
    end
    local child = base.extend(base, { semantic_checks = { reject } })
    local doc, ctx = child.match(MINIMAL)
    assert.is_nil(doc)
    assert.equal(1, #ctx.findings)
    assert.equal("sdp.v.must-be-zero", ctx.findings[1].id)
  end)

  -- NOT-SPEC: library
  it("supports chaining: child.extend produces a grandchild", function()
    local function gc_check(doc, ctx) return true end
    local child      = base.extend(base, {})
    local grandchild = child.extend(child, {
      semantic_checks = { gc_check },
    })
    assert.is_function(grandchild.extend)
    assert.equal(#base.semantic_checks + 1, #grandchild.semantic_checks)
    assert.is_truthy(grandchild.match(MINIMAL))
  end)
end)

describe("parse_sdp.grammar.st2110 — Phase 6.A shell", function()

  local st2110 = require("parse_sdp.grammar.st2110")

  -- NOT-SPEC: library
  it("exposes the same shape as base.extend's return", function()
    assert.is_table(st2110.rules)
    assert.is_function(st2110.match)
    assert.is_function(st2110.extend)
  end)

  -- NOT-SPEC: library
  it("matches every input base.match matches (empty overrides)", function()
    assert.is_truthy(st2110.match(MINIMAL))
    assert.is_truthy(st2110.match(MINIMAL_WITH_RTPMAP))
  end)

  -- NOT-SPEC: library
  it("rejects every input base.match rejects (empty overrides)", function()
    local bad = lines_to_sdp({
      "v=1",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=x",
      "t=0 0",
    })
    assert.is_nil((st2110.match(bad)))
  end)

  -- NOT-SPEC: library — the ST 2110 tier inherits every base check (in
  -- the same relative order) and appends its own. The exact additional
  -- count tracks how many cross-section checks the tier has registered;
  -- assert the inheritance property without coupling to that count.
  it("inherits every base check in order, then appends ST 2110 checks", function()
    assert.is_true(#st2110.semantic_checks >= #base.semantic_checks)
    for i, fn in ipairs(base.semantic_checks) do
      assert.equal(fn, st2110.semantic_checks[i])
    end
  end)
end)

describe("parse_sdp.grammar.ipmx — Phase 7.A shell", function()

  local st2110 = require("parse_sdp.grammar.st2110")
  local ipmx   = require("parse_sdp.grammar.ipmx")

  -- NOT-SPEC: library
  it("exposes the same shape as base.extend's return", function()
    assert.is_table(ipmx.rules)
    assert.is_function(ipmx.match)
    assert.is_function(ipmx.extend)
    assert.is_table(ipmx.semantic_checks)
    assert.is_table(ipmx.media_section_checks)
    assert.is_not_nil(ipmx.grammar)
  end)

  -- NOT-SPEC: library
  it("matches every input the ST 2110 tier matches (empty overrides)", function()
    assert.is_truthy(ipmx.match(MINIMAL))
    assert.is_truthy(ipmx.match(MINIMAL_WITH_RTPMAP))
  end)

  -- NOT-SPEC: library
  it("rejects every input the ST 2110 tier rejects (empty overrides)", function()
    local bad = lines_to_sdp({
      "v=1",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=x",
      "t=0 0",
    })
    assert.is_nil((ipmx.match(bad)))
  end)

  -- NOT-SPEC: library — IPMX chains ST 2110, so its semantic_checks list
  -- starts with every ST 2110 check in order (which itself starts with
  -- every base check in order). Assert the inheritance property without
  -- coupling to the eventual TR-10 check count.
  it("inherits every ST 2110 check in order, then appends IPMX checks", function()
    assert.is_true(#ipmx.semantic_checks >= #st2110.semantic_checks)
    for i, fn in ipairs(st2110.semantic_checks) do
      assert.equal(fn, ipmx.semantic_checks[i])
    end
  end)

  -- NOT-SPEC: library — same chaining property for the per-media-block
  -- check list (Phase 6.K infrastructure).
  it("inherits every ST 2110 media_section_check in order", function()
    assert.is_true(#ipmx.media_section_checks >= #st2110.media_section_checks)
    for i, fn in ipairs(st2110.media_section_checks) do
      assert.equal(fn, ipmx.media_section_checks[i])
    end
  end)

  -- NOT-SPEC: library — distinct tables, not aliases of parent
  it("returns distinct grammar / rules / check tables (not aliases of st2110)", function()
    assert.are_not.equal(st2110.grammar, ipmx.grammar)
    assert.are_not.equal(st2110.rules,   ipmx.rules)
    assert.are_not.equal(st2110.semantic_checks,      ipmx.semantic_checks)
    assert.are_not.equal(st2110.media_section_checks, ipmx.media_section_checks)
  end)
end)
