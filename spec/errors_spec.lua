---@diagnostic disable
local errors = require("parse_sdp")._errors

describe("errors.format", function()

  -- NOT-SPEC: library
  it("includes the message", function()
    local out = errors.format({ message = "something failed", line = 0, col = 0, context = "" })
    assert.truthy(out:find("something failed", 1, true))
  end)

  -- NOT-SPEC: library
  it("includes the error code when present", function()
    local out = errors.format({ message = "field missing", code = "MISSING_FIELD",
                                 line = 0, col = 0, context = "" })
    assert.truthy(out:find("MISSING_FIELD", 1, true))
    assert.truthy(out:find("field missing",  1, true))
  end)

  -- NOT-SPEC: library
  it("omits code bracket when code is absent", function()
    local out = errors.format({ message = "oops", line = 0, col = 0, context = "" })
    assert.falsy(out:find("%[", 1, false))  -- no '[' character
  end)

  -- NOT-SPEC: library
  it("includes line and col when line > 0", function()
    local out = errors.format({ message = "bad", line = 3, col = 5, context = "" })
    assert.truthy(out:find("line 3", 1, true))
    assert.truthy(out:find("col 5",  1, true))
  end)

  -- NOT-SPEC: library
  it("shows context line and caret when context is non-empty", function()
    local out = errors.format({ message = "bad value", line = 2, col = 1, context = "s=Bad" })
    assert.truthy(out:find("s=Bad", 1, true))
    assert.truthy(out:find("^",     1, true))
  end)

  -- NOT-SPEC: library
  it("caret is offset by col-1 spaces", function()
    -- col 4 → 3 spaces before ^
    local out = errors.format({ message = "x", line = 1, col = 4, context = "v=XX" })
    assert.truthy(out:find("   ^", 1, true))
  end)

  -- NOT-SPEC: library
  it("col 1 produces caret with no leading spaces (just the prefix)", function()
    local out = errors.format({ message = "x", line = 1, col = 1, context = "v=0" })
    -- caret line ends with "| ^" (no spaces between | and ^)
    assert.truthy(out:find("| ^", 1, true))
  end)

  it("includes field_path for validation / ST 2110 errors", function()
    local out = errors.format({
      message    = "missing ts-refclk",
      field_path = "media[1].attributes[ts-refclk]",
      spec_ref   = "",
      line = 0, col = 0, context = "",
    })
    assert.truthy(out:find("media[1]", 1, true))
  end)

  it("includes spec_ref as a note", function()
    local out = errors.format({
      message    = "missing ts-refclk",
      field_path = "media[1].attributes[ts-refclk]",
      spec_ref   = "ST 2110-10:2022 §7.2",
      line = 0, col = 0, context = "",
    })
    assert.truthy(out:find("ST 2110-10", 1, true))
  end)

  it("skips spec_ref note when spec_ref is empty", function()
    local out = errors.format({
      message    = "missing field",
      field_path = "media[1]",
      spec_ref   = "",
      line = 0, col = 0, context = "",
    })
    assert.falsy(out:find("note:", 1, true))
  end)

  -- NOT-SPEC: library
  it("handles nil err gracefully", function()
    local out = errors.format(nil)
    assert.is_string(out)
    assert.truthy(#out > 0)
  end)

  -- Phase 6.K: format emits BOTH field_path AND line/col when both
  -- are present (was elseif before — only one or the other showed).
  -- field_path is doc-shape coordinates, line/col is text coordinates;
  -- they answer different questions.
  it("emits both field_path and line/col when both are present", function()
    local out = errors.format({
      message    = "bad fmtp",
      field_path = "media[1].attributes[fmtp:pt=96]",
      line       = 8,
      col        = 42,
      context    = "",
      spec_ref   = "ST 2110-20:2022 §7.2",
    })
    assert.truthy(out:find("media[1].attributes[fmtp:pt=96]", 1, true))
    assert.truthy(out:find("line 8",  1, true))
    assert.truthy(out:find("col 42", 1, true))
    assert.truthy(out:find("ST 2110-20:2022 §7.2", 1, true))
  end)

  -- Phase 6.K: `context` is overloaded — legacy 1.0 callers set it to
  -- the source-line string for the `N | <line>` highlight; newer
  -- in-grammar Cmts set it to a metadata table like
  -- {encoding="L24"}. Render the highlight only when context is a
  -- string (legacy path); a table context is for downstream JSON
  -- consumers and shouldn't be stringified into the highlight.
  it("skips the line-highlight when context is a table (not a string)", function()
    local out = errors.format({
      message    = "bad value",
      line       = 5,
      col        = 1,
      context    = { encoding = "L24", value = "foo" },
      spec_ref   = "",
    })
    assert.truthy(out:find("line 5",         1, true))
    assert.falsy (out:find("table:",         1, true))   -- no `tostring(table)`
    assert.falsy (out:find("  |",            1, true))   -- no highlight block
  end)

end)

describe("errors.new", function()

  -- NOT-SPEC: library
  it("returns a table with the given message", function()
    local e = errors.new("something went wrong")
    assert.is_table(e)
    assert.equal("something went wrong", e.message)
  end)

  -- NOT-SPEC: library
  it("defaults code to MISSING_FIELD", function()
    local e = errors.new("field missing")
    assert.equal("MISSING_FIELD", e.code)
  end)

  -- NOT-SPEC: library
  it("accepts explicit code override", function()
    local e = errors.new("bad value", { code = "INVALID_VALUE" })
    assert.equal("INVALID_VALUE", e.code)
  end)

  it("field_path and spec_ref are nil when not given", function()
    local e = errors.new("err")
    assert.is_nil(e.field_path)
    assert.is_nil(e.spec_ref)
  end)

  it("sets field_path and spec_ref when given", function()
    local e = errors.new("err", { field_path = "media[1]", spec_ref = "ST 2110-10:2022 §7" })
    assert.equal("media[1]",       e.field_path)
    assert.equal("ST 2110-10:2022 §7", e.spec_ref)
  end)

end)
