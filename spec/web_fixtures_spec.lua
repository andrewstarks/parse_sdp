---@diagnostic disable
-- The browser playground's mock engine answers from recorded bridge
-- responses (web/fixtures, copied to web/src/mock). They must match what
-- the native bridge returns for the same input today; otherwise the mock
-- shows findings the engine no longer makes, or hides ones it does.
-- Regenerate with:
--   printf '{"op":"checks"}' | lua web/wasm/bridge_cli.lua > web/fixtures/checks.json
--   (and an {"op":"report","text":...} request per web/fixtures/*.sdp),
-- then copy the .json files to web/src/mock/.

package.path = "./web/wasm/?.lua;" .. package.path
local bridge = require("bridge")
local dkjson = require("dkjson")

local function slurp(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local function decoded(text)
  local obj, _, err = dkjson.decode(text)
  assert(obj, err)
  return obj
end

local FIXTURES = { "generic_pathological", "ipmx_typical", "st2110_invalid" }

describe("web fixtures — recorded bridge responses match the native bridge", function()
  -- NOT-SPEC: library
  it("web/fixtures/checks.json is the current registry", function()
    local recorded = decoded(slurp("web/fixtures/checks.json"))
    local live     = decoded(bridge.handle(dkjson.encode({ op = "checks" })))
    assert.same(live, recorded)
  end)

  for _, name in ipairs(FIXTURES) do
    it(("web/fixtures/report_%s.json is the current report"):format(name), function()
      local text     = slurp(("web/fixtures/%s.sdp"):format(name))
      local recorded = decoded(slurp(("web/fixtures/report_%s.json"):format(name)))
      local live     = decoded(bridge.handle(dkjson.encode({ op = "report", text = text })))
      assert.same(live, recorded)
    end)
  end

  it("web/src/mock holds byte-identical copies", function()
    for _, file in ipairs({ "checks.json", "report_generic_pathological.json",
                            "report_ipmx_typical.json", "report_st2110_invalid.json",
                            "version.json" }) do
      assert.equal(slurp("web/fixtures/" .. file), slurp("web/src/mock/" .. file), file)
    end
  end)
end)
