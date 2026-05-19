---@diagnostic disable
local errors = require("parse_sdp.errors")

describe("error registry", function()

  describe("CHECKS validation", function()

    -- NOT-SPEC: library
    it("every registered check passes schema", function()
      local valid_kind     = { ["hard-syntactic"]=1, ["soft-syntactic"]=1, ["semantic"]=1 }
      local valid_severity = { ["error"]=1, ["warn"]=1, ["off"]=1 }
      local valid_code     = { INVALID_VALUE=1, MISSING_FIELD=1, MALFORMED_LINE=1, WRONG_ORDER=1 }

      local cs = errors.checks()
      assert.is_truthy(#cs > 0, "registry should not be empty")
      for _, c in ipairs(cs) do
        assert.is_string(c.id, "id must be string")
        assert.is_truthy(valid_kind[c.kind],
          "kind invalid for " .. c.id .. ": " .. tostring(c.kind))
        assert.is_truthy(valid_severity[c.default_severity],
          "default_severity invalid for " .. c.id .. ": " .. tostring(c.default_severity))
        assert.is_truthy(valid_code[c.code],
          "code invalid for " .. c.id .. ": " .. tostring(c.code))
        assert.is_string(c.message_template)
        assert.is_string(c.spec_ref)
        assert.is_boolean(c.verified)
        if not c.verified then
          assert.is_string(c.verification_note,
            "verified=false requires verification_note for " .. c.id)
          assert.is_truthy(#c.verification_note > 0)
        end
      end
    end)

    -- NOT-SPEC: library
    it("includes at least one semantic and one soft-syntactic seed", function()
      local kinds = {}
      for _, c in ipairs(errors.checks()) do kinds[c.kind] = true end
      assert.is_truthy(kinds["semantic"],       "expect semantic seeds")
      assert.is_truthy(kinds["soft-syntactic"], "expect soft-syntactic seeds")
    end)

  end)

  describe(".checks()", function()
    -- NOT-SPEC: library
    it("returns entries sorted by id", function()
      local prev
      for _, c in ipairs(errors.checks()) do
        if prev then
          assert.is_truthy(prev < c.id,
            "checks() not sorted: " .. prev .. " before " .. c.id)
        end
        prev = c.id
      end
    end)
  end)

  describe(".default_policy()", function()
    -- NOT-SPEC: library
    it("maps every registered id to its default severity", function()
      local p = errors.default_policy()
      for _, c in ipairs(errors.checks()) do
        assert.equal(c.default_severity, p[c.id])
      end
    end)
  end)

end)

describe("severity resolution", function()

  -- NOT-SPEC: library
  it("returns default when policy is nil", function()
    assert.equal("error", errors.resolve_severity(nil, "sdp.v.must-be-zero"))
  end)

  -- NOT-SPEC: library
  it("returns default when policy doesn't override the id", function()
    assert.equal("error", errors.resolve_severity({}, "sdp.v.must-be-zero"))
  end)

  -- NOT-SPEC: library
  it("returns the override when policy specifies one", function()
    assert.equal("warn",
      errors.resolve_severity({["sdp.v.must-be-zero"]="warn"}, "sdp.v.must-be-zero"))
    assert.equal("off",
      errors.resolve_severity({["sdp.v.must-be-zero"]="off"},  "sdp.v.must-be-zero"))
  end)

  -- NOT-SPEC: library
  it("raises on unknown id", function()
    assert.has_error(function() errors.resolve_severity(nil, "no.such.id") end)
  end)

end)

describe("policy validation", function()

  -- NOT-SPEC: library
  it("accepts nil policy", function()
    assert.is_true(errors.validate_policy(nil))
  end)

  -- NOT-SPEC: library
  it("accepts empty policy", function()
    assert.is_true(errors.validate_policy({}))
  end)

  -- NOT-SPEC: library
  it("accepts policy with valid keys and severities", function()
    assert.is_true(errors.validate_policy({
      ["sdp.v.must-be-zero"]            = "warn",
      ["sdp.a.fmtp.trailing-semicolon"] = "off",
    }))
  end)

  -- NOT-SPEC: library
  it("rejects unknown id and names the offending key", function()
    local ok, err = errors.validate_policy({ ["no.such.id"] = "warn" })
    assert.is_nil(ok)
    assert.is_table(err)
    assert.equal("no.such.id", err.policy_key)
  end)

  -- NOT-SPEC: library
  it("rejects invalid severity", function()
    local ok, err = errors.validate_policy({ ["sdp.v.must-be-zero"] = "nope" })
    assert.is_nil(ok)
    assert.is_table(err)
    assert.equal("sdp.v.must-be-zero", err.policy_key)
  end)

  -- NOT-SPEC: library
  it("rejects a non-table policy", function()
    local ok, err = errors.validate_policy("not a table")
    assert.is_nil(ok)
    assert.is_table(err)
  end)

end)

describe("record()", function()

  -- NOT-SPEC: library
  it("appends a warn finding and returns true", function()
    local ctx = { findings = {}, fail_on_first = true }
    local cont = errors.record(ctx, "sdp.line.lf-only-line-ending",
                               { line = 3, col = 1, context = "v=0" })
    assert.is_true(cont)
    assert.equal(1, #ctx.findings)
    assert.equal("warn", ctx.findings[1].severity)
    assert.equal("sdp.line.lf-only-line-ending", ctx.findings[1].id)
    assert.equal(3, ctx.findings[1].line)
  end)

  -- NOT-SPEC: library
  it("appends an error finding and returns false when fail_on_first is true", function()
    local ctx = { findings = {}, fail_on_first = true }
    local cont = errors.record(ctx, "sdp.v.must-be-zero",
                               { line = 1, col = 1, context = "v=1" })
    assert.is_false(cont)
    assert.equal(1, #ctx.findings)
    assert.equal("error", ctx.findings[1].severity)
  end)

  -- NOT-SPEC: library
  it("appends an error finding and returns true when fail_on_first is false", function()
    local ctx = { findings = {}, fail_on_first = false }
    local cont = errors.record(ctx, "sdp.v.must-be-zero",
                               { line = 1, col = 1, context = "v=1" })
    assert.is_true(cont)
    assert.equal(1, #ctx.findings)
  end)

  -- NOT-SPEC: library
  it("drops the finding entirely when policy says off", function()
    local ctx = {
      findings      = {},
      policy        = { ["sdp.a.fmtp.trailing-semicolon"] = "off" },
      fail_on_first = true,
    }
    local cont = errors.record(ctx, "sdp.a.fmtp.trailing-semicolon",
                               { line = 5, col = 1, context = "a=fmtp:96 a=1;" })
    assert.is_true(cont)
    assert.equal(0, #ctx.findings)
  end)

  -- NOT-SPEC: library
  it("honors a policy override that downgrades error to warn", function()
    local ctx = {
      findings      = {},
      policy        = { ["sdp.v.must-be-zero"] = "warn" },
      fail_on_first = true,
    }
    local cont = errors.record(ctx, "sdp.v.must-be-zero",
                               { line = 1, col = 1, context = "v=1" })
    assert.is_true(cont, "warn must not fail the match")
    assert.equal("warn", ctx.findings[1].severity)
  end)

  -- NOT-SPEC: library
  it("populates spec_ref and code from the registry", function()
    local ctx = { findings = {}, fail_on_first = false }
    errors.record(ctx, "sdp.v.must-be-zero", { line = 1, col = 1, context = "v=1" })
    assert.equal("RFC 8866 §5.1", ctx.findings[1].spec_ref)
    assert.equal("INVALID_VALUE", ctx.findings[1].code)
  end)

  -- NOT-SPEC: library
  it("propagates field_path from the location table", function()
    local ctx = { findings = {}, fail_on_first = false }
    errors.record(ctx, "sdp.v.must-be-zero",
                  { line = 1, col = 1, context = "v=1", field_path = "version" })
    assert.equal("version", ctx.findings[1].field_path)
  end)

  -- NOT-SPEC: library
  it("raises on unknown id", function()
    assert.has_error(function()
      local ctx = { findings = {}, fail_on_first = false }
      errors.record(ctx, "no.such.id", { line = 1, col = 1, context = "" })
    end)
  end)

end)

describe("deepest-failure tracker", function()

  -- NOT-SPEC: library
  it("new_tracker starts empty", function()
    local t = errors.new_tracker()
    local pos, info = errors.tracker_deepest(t)
    assert.equal(0, pos)
    assert.is_nil(info)
  end)

  -- NOT-SPEC: library
  it("records a position and info, recalls them", function()
    local t = errors.new_tracker()
    errors.tracker_record(t, 17, { message = "boom" })
    local pos, info = errors.tracker_deepest(t)
    assert.equal(17, pos)
    assert.equal("boom", info.message)
  end)

  -- NOT-SPEC: library
  it("keeps the deepest position when later records are shallower", function()
    local t = errors.new_tracker()
    errors.tracker_record(t, 17, { message = "deep" })
    errors.tracker_record(t, 5,  { message = "shallow" })
    local pos, info = errors.tracker_deepest(t)
    assert.equal(17, pos)
    assert.equal("deep", info.message)
  end)

  -- NOT-SPEC: library
  it("advances when a later record is deeper", function()
    local t = errors.new_tracker()
    errors.tracker_record(t, 5,  { message = "first" })
    errors.tracker_record(t, 17, { message = "second" })
    local pos, info = errors.tracker_deepest(t)
    assert.equal(17, pos)
    assert.equal("second", info.message)
  end)

  -- NOT-SPEC: library
  it("on tie, last record wins (most recent failure at that depth)", function()
    local t = errors.new_tracker()
    errors.tracker_record(t, 10, { message = "first" })
    errors.tracker_record(t, 10, { message = "second" })
    local _, info = errors.tracker_deepest(t)
    assert.equal("second", info.message)
  end)

end)

describe("legacy compatibility", function()

  -- NOT-SPEC: library
  it(".new() preserves 1.0 shape", function()
    local e = errors.new("msg", { code = "INVALID_VALUE" })
    assert.equal("msg", e.message)
    assert.equal("INVALID_VALUE", e.code)
    assert.equal(0,  e.line)
    assert.equal(0,  e.col)
    assert.equal("", e.context)
  end)

  -- NOT-SPEC: library
  it(".new() carries the new id field when given", function()
    local e = errors.new("msg", { id = "sdp.v.must-be-zero" })
    assert.equal("sdp.v.must-be-zero", e.id)
  end)

  -- NOT-SPEC: library
  it(".new() leaves id nil when not given (additive, opt-in)", function()
    local e = errors.new("msg")
    assert.is_nil(e.id)
  end)

  -- NOT-SPEC: library
  it(".format() produces the 1.0 multi-line output shape", function()
    local e = errors.new("bad", {
      line = 2, col = 4, context = "v=XX",
      code = "INVALID_VALUE", spec_ref = "RFC 8866 §5.1",
    })
    local out = errors.format(e)
    assert.truthy(out:find("INVALID_VALUE", 1, true))
    assert.truthy(out:find("v=XX",          1, true))
    assert.truthy(out:find("RFC 8866",      1, true))
    assert.truthy(out:find("line 2, col 4", 1, true))
  end)

end)
