---@diagnostic disable
-- Property checks over mutated copies of every example and fixture.
--
-- Hand-written specs feed one deliberate defect each, usually with nothing
-- around it that depends on the defect. These properties vary where a
-- defect sits relative to the other lines, which is how the following
-- escaped the hand-written specs:
--   - checks that ran on a section cut short by an unparseable line, so a
--     later line's absence was reported instead of the bad line;
--   - `Cb` back-references to groups that only some inputs define, which
--     raise a Lua error instead of failing the match;
--   - shapes the parser produces but the serializer cannot render.
--
-- Each `it` covers one source file and reports every failing mutant.

local sdp = require("parse_sdp")

local unpack = table.unpack or unpack

local TIERS = {
  { dir = "generic", mode = "sdp"    },
  { dir = "st2110",  mode = "st2110" },
  { dir = "ipmx",    mode = "ipmx"   },
}
local MODES = { "sdp", "st2110", "ipmx" }

local function list(glob)
  local h = assert(io.popen("ls " .. glob .. " 2>/dev/null", "r"))
  local out = {}
  for line in h:lines() do out[#out + 1] = line end
  h:close()
  table.sort(out)
  return out
end

local function slurp(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local function split_lines(text)
  local lines = {}
  for l in (text .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = (l:gsub("\r$", ""))
  end
  while lines[#lines] == "" do lines[#lines] = nil end
  return lines
end

local function join(lines) return table.concat(lines, "\r\n") .. "\r\n" end

local function with(lines, fn)
  local t = { unpack(lines) }
  fn(t)
  return join(t)
end

-- Every parse runs under the default policy and under one that demotes
-- every error-severity check to warn (the CLI --all-findings policy), so
-- the shapes that only a demoted parse produces are covered too.
local DEMOTED = {}
for _, c in ipairs(sdp.checks()) do
  if c.default_severity == "error" then DEMOTED[c.id] = "warn" end
end

local function report(failures)
  local n = #failures
  local shown = {}
  for i = 1, math.min(n, 8) do shown[i] = "  " .. failures[i] end
  return ("%d failing mutant%s:\n%s"):format(n, n == 1 and "" or "s",
                                              table.concat(shown, "\n"))
end

-- ── Error location ─────────────────────────────────────────────────────────
-- A bad line is the reported error, wherever it sits. Each line below
-- fails on its own: an unknown line letter, an RFC 8866 §9 non-zero-real
-- ending in "0", channels = 0 (RFC 8866 §6.6 integer), and a NUL octet
-- (RFC 8866 §9 byte-string). The unknown letter and the NUL are pure
-- structural failures (PARSE_ERROR). The two malformed known attributes
-- report their own check id where an a= line may appear, and PARSE_ERROR
-- where it may not; either way the error is on the inserted line.

local UNPARSEABLE = {
  { "x=bad",                   "PARSE_ERROR" },
  { "a=ptime:1.0" },
  { "a=rtpmap:97 L24/48000/0" },
  { "a=tool:a\0b",             "PARSE_ERROR" },
}

for _, tier in ipairs(TIERS) do
  describe("mutation: a bad line is the reported error ("
           .. tier.dir .. ")", function()
    for _, path in ipairs(list("examples/" .. tier.dir .. "/valid/*.sdp")) do
      -- NOT-SPEC: library
      it(path, function()
        local lines = split_lines(slurp(path))
        local failures = {}
        for i = 1, #lines do
          for _, case in ipairs(UNPARSEABLE) do
            local bad, code = case[1], case[2]
            local text = with(lines, function(t) table.insert(t, i + 1, bad) end)
            local ok, doc, err = pcall(sdp.parse, text, tier.mode)
            if not ok or doc or err.line ~= i + 1
               or (code and err.code ~= code) then
              failures[#failures + 1] = ("%q after line %d: %s"):format(bad, i,
                not ok and ("threw " .. tostring(doc))
                or doc and "accepted"
                or ("%s on line %s"):format(err.id or err.code, tostring(err.line)))
            end
          end
        end
        assert(#failures == 0, report(failures))
      end)
    end
  end)
end

-- ── Parse contract, round-trip, and verdict agreement ─────────────────────
-- For every mutant, at every tier:
--   - sdp.parse returns a doc, or nil and an error table with an id or a
--     code; it never raises;
--   - fail_on_first = true and false agree on accept versus reject;
--   - a doc that parses renders with to_sdp and re-parses, under the same
--     policy, to the same JSON.

local function mutants(text)
  local lines = split_lines(text)
  local out = {}
  local function add(label, t) out[#out + 1] = { label, t } end
  local tpos = 4
  for i, l in ipairs(lines) do
    if l:sub(1, 2) == "t=" then tpos = i end
  end
  for i, l in ipairs(lines) do
    add("delete line " .. i, with(lines, function(t) table.remove(t, i) end))
    add("duplicate line " .. i, with(lines, function(t) table.insert(t, i, l) end))
    if l:sub(1, 2) == "a=" then
      add("copy line " .. i .. " to session level",
          with(lines, function(t) table.insert(t, tpos + 1, l) end))
    end
    local half = math.floor(#l / 2)
    add("cut line " .. i, with(lines, function(t) t[i] = l:sub(1, half) end))
    for _, ch in ipairs({ "\r", "\0" }) do
      local at = math.max(3, half)
      add(("%q inside line %d"):format(ch, i),
          with(lines, function(t) t[i] = l:sub(1, at) .. ch .. l:sub(at + 1) end))
    end
    if i < #lines then
      add("swap lines " .. i .. " and " .. (i + 1),
          with(lines, function(t) t[i], t[i + 1] = t[i + 1], t[i] end))
    end
  end
  -- Truncation inside every line, which leaves a final line with no
  -- terminator.
  local pos = 1
  for _, l in ipairs(lines) do
    for _, k in ipairs({ 1, math.floor(#l / 2), #l }) do
      add("truncate at byte " .. (pos + k - 1), text:sub(1, pos + k - 1))
    end
    pos = text:find("\n", pos, true)
    if not pos then break end
    pos = pos + 1
  end
  return out
end

local function round_trip_problem(doc, mode, opts)
  local out, serr = doc:to_sdp()
  if not out then return "to_sdp: " .. tostring(serr and serr.message) end
  local doc2, err2 = sdp.parse(out, mode, opts)
  if not doc2 then
    return "re-parse: " .. tostring(err2.id or err2.code) .. " on line "
           .. tostring(err2.line)
  end
  if doc2:to_json() ~= doc:to_json() then return "re-parsed JSON differs" end
end

local SOURCES = {}
for _, glob in ipairs({ "examples/*/valid/*.sdp", "examples/*/invalid/*.sdp",
                        "spec/fixtures/*.sdp" }) do
  for _, path in ipairs(list(glob)) do SOURCES[#SOURCES + 1] = path end
end

describe("mutation: parse contract, round-trip, and verdict agreement", function()
  for _, path in ipairs(SOURCES) do
    -- NOT-SPEC: library
    it(path, function()
      local failures = {}
      local function fail(label, mode, msg)
        failures[#failures + 1] = ("%s [%s]: %s"):format(label, mode, msg)
      end
      for _, m in ipairs(mutants(slurp(path))) do
        local label, text = m[1], m[2]
        for _, mode in ipairs(MODES) do
          local results = {}
          for _, opts in ipairs({ { fail_on_first = false },
                                  { fail_on_first = true },
                                  { policy = DEMOTED } }) do
            local ok, doc, err = pcall(sdp.parse, text, mode, opts)
            if not ok then
              fail(label, mode, "threw " .. tostring(doc))
            elseif not doc and not (type(err) == "table" and (err.id or err.code)) then
              fail(label, mode, "nil doc without an error table")
            elseif doc and not opts.fail_on_first then
              local problem = round_trip_problem(doc, mode,
                opts.policy and { policy = opts.policy } or nil)
              if problem then fail(label, mode, problem) end
            end
            results[#results + 1] = ok and doc ~= nil
          end
          if results[1] ~= results[2] then
            fail(label, mode, "fail_on_first changes the verdict")
          end
        end
      end
      assert(#failures == 0, report(failures))
    end)
  end
end)
