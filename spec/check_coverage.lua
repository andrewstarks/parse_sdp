-- Fails when a registered check is never recorded by any spec.
--
--   lua spec/check_coverage.lua
--
-- A check that no spec triggers can be broken or unreachable without any
-- test noticing. This script runs `busted spec/` with a hook on
-- errors.record, then compares the ids it saw with sdp.checks(). Only
-- records made from code in parse_sdp/grammar/ count: a spec that calls
-- errors.record itself proves nothing about the grammar.
--
-- The same file is the hook: the driver loads it into the busted process
-- through LUA_INIT, and CHECK_COVERAGE_OUT tells it which role it has.

local out_path = os.getenv("CHECK_COVERAGE_OUT")
if out_path then
  local errors = require("parse_sdp.errors")
  local record = errors.record
  local out = assert(io.open(out_path, "w"))
  errors.record = function(ctx, id, ...)
    local caller = debug.getinfo(2, "S").source
    if caller:find("parse_sdp/grammar/", 1, true) then
      out:write(id, "\n")
      out:flush()
    end
    return record(ctx, id, ...)
  end
  return
end

-- Registered on purpose but never emitted. GUIDE.md documents each one.
local NOT_EMITTED = {
  -- The grammar rejects these structurally (PARSE_ERROR).
  ["sdp.v.must-be-zero"]      = true,
  ["sdp.o.username-required"] = true,
}

local tmp = os.tmpname()
local cmd = ("CHECK_COVERAGE_OUT=%q LUA_INIT=@spec/check_coverage.lua busted spec/ > %q 2>&1")
              :format(tmp, tmp .. ".log")
local ok = os.execute(cmd)
if ok ~= true and ok ~= 0 then
  io.stderr:write("busted spec/ failed; see " .. tmp .. ".log\n")
  os.exit(1)
end

local seen = {}
for id in io.lines(tmp) do seen[id] = true end
os.remove(tmp)
os.remove(tmp .. ".log")

local missing = {}
for _, c in ipairs(require("parse_sdp").checks()) do
  if not seen[c.id] and not NOT_EMITTED[c.id] then missing[#missing + 1] = c.id end
end

if #missing > 0 then
  io.stderr:write(#missing .. " registered check(s) never recorded by any spec:\n")
  for _, id in ipairs(missing) do io.stderr:write("  " .. id .. "\n") end
  os.exit(1)
end
print("every registered check is recorded by at least one spec")
