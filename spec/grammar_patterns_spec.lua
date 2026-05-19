---@diagnostic disable
-- Phase 6.J: shared LPeg numeric value-form patterns.
-- Both base.lua's RFC 8866 §9 numeric V-rules and st2110.lua's value
-- validators draw from this module — these tests are the single source
-- of truth for what each pattern shape accepts and rejects.

local patterns = require("parse_sdp.grammar.patterns")

describe("parse_sdp.grammar.patterns — pos_int (anchored)", function()

  -- NOT-SPEC: library — anchored RFC 8866 §9 integer (POS-DIGIT *DIGIT).
  it("accepts positive integers with no leading zero", function()
    assert.is_truthy(patterns.pos_int:match("1"))
    assert.is_truthy(patterns.pos_int:match("9"))
    assert.is_truthy(patterns.pos_int:match("10"))
    assert.is_truthy(patterns.pos_int:match("1920"))
    assert.is_truthy(patterns.pos_int:match("4294967295"))  -- 2^32-1
  end)

  -- NOT-SPEC: library
  it("rejects '0' (zero is not POS-DIGIT *DIGIT)", function()
    assert.is_nil(patterns.pos_int:match("0"))
  end)

  -- NOT-SPEC: library
  it("rejects leading zeros", function()
    assert.is_nil(patterns.pos_int:match("01"))
    assert.is_nil(patterns.pos_int:match("0010"))
  end)

  -- NOT-SPEC: library — the bug the pattern guards against vs. tonumber().
  it("rejects floats / scientific / hex / signs / whitespace", function()
    assert.is_nil(patterns.pos_int:match("1920.5"))
    assert.is_nil(patterns.pos_int:match("1e3"))
    assert.is_nil(patterns.pos_int:match("0x780"))
    assert.is_nil(patterns.pos_int:match("-100"))
    assert.is_nil(patterns.pos_int:match("+100"))
    assert.is_nil(patterns.pos_int:match("  1920  "))
    assert.is_nil(patterns.pos_int:match("1920\n"))
  end)

  -- NOT-SPEC: library
  it("rejects empty string and non-numeric", function()
    assert.is_nil(patterns.pos_int:match(""))
    assert.is_nil(patterns.pos_int:match("abc"))
    assert.is_nil(patterns.pos_int:match("1abc"))
  end)
end)

describe("parse_sdp.grammar.patterns — int (anchored, signed)", function()

  -- NOT-SPEC: library — extends pos_int to also accept 0 and a leading '-'.
  it("accepts positive integers", function()
    assert.is_truthy(patterns.int:match("1"))
    assert.is_truthy(patterns.int:match("1920"))
  end)

  -- NOT-SPEC: library
  it("accepts '0'", function()
    assert.is_truthy(patterns.int:match("0"))
  end)

  -- NOT-SPEC: library
  it("accepts negative integers", function()
    assert.is_truthy(patterns.int:match("-1"))
    assert.is_truthy(patterns.int:match("-1920"))
  end)

  -- NOT-SPEC: library
  it("rejects '+' prefix (RFC 8866 ABNF does not define one)", function()
    assert.is_nil(patterns.int:match("+1"))
  end)

  -- NOT-SPEC: library — even with leading '-', leading zeros are forbidden
  -- on the magnitude.
  it("rejects '-0010' and other leading-zero magnitudes", function()
    assert.is_nil(patterns.int:match("-0010"))
    assert.is_nil(patterns.int:match("00"))
  end)

  -- NOT-SPEC: library
  it("rejects floats / scientific / hex / whitespace", function()
    assert.is_nil(patterns.int:match("1.5"))
    assert.is_nil(patterns.int:match("-1.5"))
    assert.is_nil(patterns.int:match("1e3"))
    assert.is_nil(patterns.int:match("0x10"))
    assert.is_nil(patterns.int:match("  -5  "))
  end)
end)

describe("parse_sdp.grammar.patterns — zero_based_int_raw (composable)", function()

  -- NOT-SPEC: library — anchored form for whole-string tests in this spec.
  local zero_based_int = patterns.zero_based_int_raw * require("lpeg").P(-1)

  it("accepts 0 and positive integers", function()
    assert.is_truthy(zero_based_int:match("0"))
    assert.is_truthy(zero_based_int:match("96"))
    assert.is_truthy(zero_based_int:match("127"))
  end)

  it("rejects leading zeros (other than '0' alone)", function()
    assert.is_nil(zero_based_int:match("00"))
    assert.is_nil(zero_based_int:match("096"))
  end)

  it("rejects negative", function()
    assert.is_nil(zero_based_int:match("-1"))
  end)
end)

describe("parse_sdp.grammar.patterns — fraction (N/D)", function()

  -- NOT-SPEC: library — composable pattern returning two captures.
  it("captures numerator and denominator on match", function()
    local n, d = patterns.fraction:match("30000/1001")
    assert.equal("30000", n)
    assert.equal("1001",  d)
  end)

  -- NOT-SPEC: library
  it("rejects leading zeros on either side", function()
    assert.is_nil(patterns.fraction:match("030000/1001"))
    assert.is_nil(patterns.fraction:match("30000/01001"))
  end)

  -- NOT-SPEC: library
  it("rejects 0 on either side", function()
    assert.is_nil(patterns.fraction:match("0/1"))
    assert.is_nil(patterns.fraction:match("1/0"))
  end)

  -- NOT-SPEC: library
  it("rejects missing '/' separator", function()
    assert.is_nil(patterns.fraction:match("30000"))
    assert.is_nil(patterns.fraction:match("30000 1001"))
  end)
end)

describe("parse_sdp.grammar.patterns — ratio (W:H)", function()

  -- NOT-SPEC: library — same shape as fraction but ':' separator.
  it("captures W and H on match", function()
    local w, h = patterns.ratio:match("16:9")
    assert.equal("16", w)
    assert.equal("9",  h)
  end)

  -- NOT-SPEC: library
  it("rejects leading zeros / zero on either side", function()
    assert.is_nil(patterns.ratio:match("016:9"))
    assert.is_nil(patterns.ratio:match("16:09"))
    assert.is_nil(patterns.ratio:match("0:9"))
    assert.is_nil(patterns.ratio:match("16:0"))
  end)

  -- NOT-SPEC: library
  it("rejects missing ':' separator", function()
    assert.is_nil(patterns.ratio:match("16/9"))
    assert.is_nil(patterns.ratio:match("16-9"))
  end)
end)
