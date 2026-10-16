---@diagnostic disable
-- Every file under examples/<tier>/<valid|invalid>/ carries its verdict in
-- its path: valid examples pass their tier, invalid ones fail it. This keeps
-- the shipped examples honest as checks are added or removed (the browser
-- playground lists them by directory).

local sdp = require("parse_sdp")

local function list_sdp_files(dir)
  local h = assert(io.popen("ls " .. dir .. "/*.sdp 2>/dev/null", "r"))
  local out = {}
  for line in h:lines() do out[#out + 1] = line end
  h:close()
  return out
end

local function slurp(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local TIERS = {
  { dir = "generic", mode = "sdp"    },
  { dir = "st2110",  mode = "st2110" },
  { dir = "ipmx",    mode = "ipmx"   },
}

for _, tier in ipairs(TIERS) do
  describe("examples/" .. tier.dir .. " — verdicts match their directory", function()

    for _, path in ipairs(list_sdp_files("examples/" .. tier.dir .. "/valid")) do
      it(path .. " passes " .. tier.mode, function()
        local doc, err = sdp.parse(slurp(path), tier.mode)
        assert.is_truthy(doc, err and (err.id or err.message))
      end)
    end

    for _, path in ipairs(list_sdp_files("examples/" .. tier.dir .. "/invalid")) do
      it(path .. " fails " .. tier.mode, function()
        local doc = sdp.parse(slurp(path), tier.mode)
        assert.is_nil(doc)
      end)
    end

  end)
end
