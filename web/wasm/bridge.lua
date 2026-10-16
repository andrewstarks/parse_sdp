-- web/wasm/bridge.lua — JSON request/response façade over parse_sdp.
-- See web/CONTRACT.md. Pure Lua: runs natively (bridge_cli.lua) and
-- inside the Emscripten build (bridge.c calls M.handle).

local json   = require("dkjson")
local sdp    = require("parse_sdp")
local errors = require("parse_sdp.errors")

local TIERS = {
  sdp    = require("parse_sdp.grammar.base"),
  st2110 = require("parse_sdp.grammar.st2110"),
  ipmx   = require("parse_sdp.grammar.ipmx"),
}
local TIER_ORDER = { "sdp", "st2110", "ipmx" }

local M = {}

-- Mirrors the structural-failure diagnostic init.lua builds when the
-- grammar cannot match and no error finding explains why.
local function structural_error(text, ctx)
  local tracker_pos = (ctx and ctx.tracker and ctx.tracker.position) or 0
  local pos         = tracker_pos > 0 and tracker_pos or 1
  local line, col   = errors.pos_to_line_col(text, pos)
  local line_text   = errors.pos_to_line_text(text, pos)
  local msg = (line_text ~= "")
              and "could not parse from this line"
              or  "could not parse — reached end of input with required fields missing"
  local e = errors.new(msg, { code = "PARSE_ERROR", line = line, col = col,
                              line_text = line_text })
  e.severity = "error"
  return e
end

local function run_tier(name, text, policy)
  local doc, ctx = TIERS[name].match(text, { policy = policy, fail_on_first = false })
  local findings, has_error = {}, false
  for i, f in ipairs(ctx.findings or {}) do
    findings[i] = f
    if f.severity == "error" then has_error = true end
  end
  if not doc and not has_error then
    findings[#findings + 1] = structural_error(text, ctx)
    has_error = true
  end
  return { passes = doc ~= nil and not has_error, findings = findings }, doc
end

local function report(text, policy)
  if type(text) ~= "string" then
    return { ok = false, error = errors.new("text must be a string", { code = "INVALID_VALUE" }) }
  end
  local ok, perr = errors.validate_policy(policy)
  if not ok then return { ok = false, error = perr } end
  local out = { ok = true, tiers = {} }
  for _, name in ipairs(TIER_ORDER) do
    local tier, doc = run_tier(name, text, policy)
    out.tiers[name] = tier
    if doc then out.doc = doc end   -- highest tier that parsed wins
  end
  return out
end

local function to_sdp(doc)
  if type(doc) ~= "table" then
    return nil, errors.new("doc must be an object", { code = "INVALID_VALUE" })
  end
  return sdp.new(doc):to_sdp()
end

local OPS = {}

function OPS.report(req) return report(req.text, req.policy) end

function OPS.to_sdp(req)
  local text, err = to_sdp(req.doc)
  if not text then return { ok = false, error = err } end
  return { ok = true, text = text }
end

function OPS.validate(req)
  local text, err = to_sdp(req.doc)
  if not text then return { ok = true, serialize_error = err } end
  local out = report(text, req.policy)
  if out.ok then out.text = text end
  return out
end

function OPS.from_lua(req)
  if type(req.source) ~= "string" then
    return { ok = false, error = errors.new("source must be a string", { code = "INVALID_VALUE" }) }
  end
  local chunk, lerr = load(req.source, "=doc", "t", {})
  if not chunk then
    chunk, lerr = load("return " .. req.source, "=doc", "t", {})
  end
  if not chunk then
    return { ok = false, error = errors.new(lerr, { code = "MALFORMED_LINE" }) }
  end
  local ok, doc = pcall(chunk)
  if not ok then
    return { ok = false, error = errors.new(tostring(doc), { code = "MALFORMED_LINE" }) }
  end
  if type(doc) ~= "table" then
    return { ok = false, error = errors.new("chunk must produce a table", { code = "INVALID_VALUE" }) }
  end
  return { ok = true, doc = doc }
end

function OPS.checks() return { ok = true, checks = sdp.checks() } end

function OPS.version()
  local ok, v = pcall(require, "parse_sdp_version")
  return { ok = true, lua = _VERSION, lpeg = require("lpeg").version,
           parse_sdp = ok and v or "dev" }
end

function M.handle(request_json)
  local req, _, derr = json.decode(request_json, 1, nil)
  local res
  if type(req) ~= "table" then
    res = { ok = false, error = errors.new("request is not a JSON object: " .. tostring(derr),
                                           { code = "INVALID_VALUE" }) }
  else
    local op = OPS[req.op]
    if not op then
      res = { ok = false, error = errors.new("unknown op: " .. tostring(req.op),
                                             { code = "INVALID_VALUE" }) }
    else
      local ok, r = pcall(op, req)
      res = ok and r or { ok = false, error = errors.new(tostring(r), { code = "INVALID_VALUE" }) }
    end
  end
  return json.encode(res)
end

return M
