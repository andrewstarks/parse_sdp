---@diagnostic disable
-- Bitwise-op shim. The dispatcher picks the native-operator backend
-- on Lua 5.3+ and the pure-Lua arithmetic backend on 5.1/5.2; these
-- tests cover the cases addresses.lua actually exercises and run
-- against whichever backend the current interpreter resolves to.
-- bitops_compat is loaded directly when reachable so its arithmetic
-- impl is also exercised under 5.3+.

local bitops = require("parse_sdp.grammar.bitops")

describe("parse_sdp.grammar.bitops — dispatcher", function()

  it("band masks the low byte of an IPv4 int", function()
    assert.are.equal(0x78, bitops.band(0x12345678, 0xff))
  end)

  it("rshift extracts the high byte of an IPv4 int", function()
    assert.are.equal(0x12, bitops.rshift(0x12345678, 24))
  end)

  it("rshift composes with band to extract any byte", function()
    assert.are.equal(0x34, bitops.band(bitops.rshift(0x12345678, 16), 0xff))
    assert.are.equal(0x56, bitops.band(bitops.rshift(0x12345678, 8),  0xff))
  end)

  it("band masks an IPv6 group to 16 bits", function()
    assert.are.equal(0xffff, bitops.band(0x1ffff, 0xffff))
    assert.are.equal(0xabcd, bitops.band(0xabcd,  0xffff))
  end)

  it("rshift carries an IPv6 group overflow into the next group", function()
    -- ipv6_add does `v = g[i] + carry; g[i] = v & 0xffff; carry = v >> 16`.
    -- 0xffff + 1 = 0x10000 — the carry-out is 1, the resulting group is 0.
    local v = 0xffff + 1
    assert.are.equal(0,     bitops.band(v, 0xffff))
    assert.are.equal(1,     bitops.rshift(v, 16))
  end)

  it("lshift round-trips with rshift for the values we use", function()
    assert.are.equal(0xab00,     bitops.lshift(0xab, 8))
    assert.are.equal(0xab,       bitops.rshift(bitops.lshift(0xab, 8), 8))
  end)

  it("band of zero is zero", function()
    assert.are.equal(0, bitops.band(0,          0xffffffff))
    assert.are.equal(0, bitops.band(0xffffffff, 0))
  end)

  it("rshift past width returns zero", function()
    assert.are.equal(0, bitops.rshift(0xff, 32))
  end)

end)

describe("parse_sdp.grammar.bitops_compat — pure-Lua backend", function()
  -- Exercised directly even on 5.3+ so the compat path is covered
  -- in CI without needing every job to run a 5.1/5.2 interpreter.

  local compat = require("parse_sdp.grammar.bitops_compat")

  it("band matches reference values across our call sites", function()
    assert.are.equal(0x78,   compat.band(0x12345678, 0xff))
    assert.are.equal(0xffff, compat.band(0x1ffff,    0xffff))
    assert.are.equal(0,      compat.band(0xaaaaaaaa, 0x55555555))
    assert.are.equal(0xff,   compat.band(0xff,       0xff))
  end)

  it("rshift matches reference values", function()
    assert.are.equal(0x12, compat.rshift(0x12345678, 24))
    assert.are.equal(1,    compat.rshift(0x10000,    16))
    assert.are.equal(0,    compat.rshift(0xff,       32))
  end)

  it("lshift matches reference values", function()
    assert.are.equal(0xab00, compat.lshift(0xab, 8))
    assert.are.equal(0x100,  compat.lshift(1,    8))
  end)

end)
