--- parse_sdp — RFC 8866 / ST 2110 / IPMX SDP parser, validator, and serializer.
-- Library entry point. `require("parse_sdp")` resolves here. The CLI
-- shell lives at `bin/parse_sdp` and consumes this module.
-- @module parse_sdp

-- ── External dependencies ─────────────────────────────────────────────────────
local dkjson = require("dkjson")

-- ── Internal modules ──────────────────────────────────────────────────────────
-- errors    — registry of checkable spec clauses (stable ids), severity
--             policy, record() emission helper, deepest-failure tracker,
--             legacy errors.new / errors.format.
-- grammar_* — per-tier LPeg grammars + semantic check lists.
--             base ⊆ st2110 ⊆ ipmx via base.extend() composition.
-- serialize — rendering pass over a doc table → SDP text (CRLF, strict
--             RFC 8866 ordering). Used by mt:to_sdp().
local errors             = require("parse_sdp.errors")
local grammar_base       = require("parse_sdp.grammar.base")
local grammar_st2110_mod = require("parse_sdp.grammar.st2110")
local grammar_ipmx_mod   = require("parse_sdp.grammar.ipmx")
local new_serialize      = require("parse_sdp.serialize")

local TIER_MATCH = {
  sdp    = grammar_base.match,
  st2110 = grammar_st2110_mod.match,
  ipmx   = grammar_ipmx_mod.match,
}

-- ── Public API ────────────────────────────────────────────────────────────────
local M  = {}
local mt = {}
mt.__index = mt

--- Validate the document against the given tier.
--
-- Implemented as serialize-then-reparse (round-trip): rendering the doc
-- through `to_sdp()` produces a text the grammar tier can re-parse and
-- validate. This works because the grammar tier validates during parsing
-- (semantic_checks + media_section_checks fire from the document's Cmt);
-- there is no separate "validate a table" entry point.
--
-- @param mode string  "sdp" (default), "st2110", or "ipmx".
-- @return true  on success.
-- @return nil, err  on failure; err is an error table from errors.new.
function mt:validate(mode)
  mode = mode or "sdp"
  if TIER_MATCH[mode] == nil then
    return nil, errors.new("unknown mode: " .. tostring(mode),
                           { code = "INVALID_VALUE" })
  end
  local text, te = new_serialize.to_sdp(self)
  if not text then return nil, te end
  local doc, pe = M.parse(text, mode)
  if not doc then return nil, pe end
  return true
end

--- Test whether the document is a valid RFC 8866 SDP.
-- @return boolean
function mt:is_sdp()    return self:validate("sdp")    == true end

--- Test whether the document satisfies SMPTE ST 2110 requirements.
-- @return boolean
function mt:is_st2110() return self:validate("st2110") == true end

--- Test whether the document satisfies IPMX requirements.
-- @return boolean
function mt:is_ipmx()   return self:validate("ipmx")   == true end

--- Encode the document as a JSON string using dkjson.
-- @return string  JSON representation of the document.
function mt:to_json()
  return dkjson.encode(self)
end

--- Serialize the document back to RFC 8866 SDP text.
-- @return string  SDP text with CRLF line endings.
function mt:to_sdp()
  return new_serialize.to_sdp(self)
end

-- Weak-keyed side table maps doc → ordered list of findings produced when
-- the doc was parsed. Findings live here rather than on the doc itself so
-- to_json() / round-trip serialization stay clean. For sdp.new() the
-- lookup yields nil and the accessors return the empty list.
local doc_findings = setmetatable({}, { __mode = "k" })

local function findings_for(doc) return doc_findings[doc] or {} end

local function findings_filter(doc, severity)
  local out = {}
  for _, f in ipairs(findings_for(doc)) do
    if f.severity == severity then out[#out + 1] = f end
  end
  return out
end

--- All findings (error + warn) emitted while parsing the doc.
-- @return table  Array of finding tables; empty for sdp.new() docs.
function mt:findings() return findings_for(self) end

--- Warn-severity findings only.
-- @return table  Array of finding tables.
function mt:warnings() return findings_filter(self, "warn") end

--- Error-severity findings only. With the default fail_on_first behaviour
-- on the public-API path, sdp.parse returns nil + err when this list is
-- non-empty; this accessor lets a caller that disabled fail_on_first read
-- them off the surviving doc.
-- @return table  Array of finding tables.
function mt:errors()   return findings_filter(self, "error") end

--- Parse SDP text and return a doc object with metatable methods attached.
-- @param text string  Raw SDP text (CRLF or LF line endings).
-- @param mode string  Optional validation tier: "sdp" (default), "st2110",
--                     or "ipmx".
-- @param opts table   Optional. Fields:
--                     - policy (table) — id → "error" / "warn" / "off"
--                       override map. Keys are validated against the
--                       registry (sdp.checks()) at entry; an unknown id
--                       returns nil + err pointing at the offending key.
--                     - fail_on_first (bool) — when true (1.0-compatible),
--                       the first error-severity finding aborts the parse.
--                       Default is false: collect every finding, then
--                       partition (any error → nil, err; otherwise return
--                       doc with findings reachable via doc:warnings()).
-- @return doc  Parsed SDP document on success.
-- @return nil, err  on parse or validation failure.
function M.parse(text, mode, opts)
  opts = opts or {}
  mode = mode or "sdp"
  local ok, perr = errors.validate_policy(opts.policy)
  if not ok then return nil, perr end
  local match = TIER_MATCH[mode]
  if not match then
    return nil, errors.new("unknown mode: " .. tostring(mode),
                           { code = "INVALID_VALUE" })
  end
  local doc, ctx = match(text, {
    policy        = opts.policy,
    fail_on_first = opts.fail_on_first == true,
  })
  if not doc then
    -- Grammar match failed structurally. Use the deepest recorded
    -- error-severity finding (if any) — that's the most informative
    -- diagnostic. Otherwise fall back to the line_end progress tracker:
    -- ctx.tracker.position points at the start of the line the grammar
    -- couldn't match. That gives the user line/col + the offending source
    -- line instead of a bare "SDP parse failed".
    for _, f in ipairs(ctx and ctx.findings or {}) do
      if f.severity == "error" then return nil, f end
    end
    local tracker_pos = (ctx and ctx.tracker and ctx.tracker.position) or 0
    local pos         = tracker_pos > 0 and tracker_pos or 1
    local line, col   = errors.pos_to_line_col(text, pos)
    local line_text   = errors.pos_to_line_text(text, pos)
    local msg = (line_text and line_text ~= "")
                and "could not parse from this line"
                or  "could not parse — reached end of input with required fields missing"
    return nil, errors.new(msg, {
      code      = "PARSE_ERROR",
      line      = line,
      col       = col,
      line_text = line_text,
    })
  end
  -- Match succeeded. Surface the first error-severity finding (if any) via
  -- the conventional `nil, err` contract; otherwise attach all findings
  -- (warnings) to the side table and return the doc.
  for _, f in ipairs(ctx.findings or {}) do
    if f.severity == "error" then return nil, f end
  end
  setmetatable(doc, mt)
  doc_findings[doc] = ctx.findings
  return doc
end

--- Wrap an existing table as a doc object without parsing or validation.
-- @param t table  Any table to wrap.
-- @return doc  The table with SDP metatable methods attached.
function M.new(t)
  return setmetatable(t, mt)
end

--- Registered checks. Returns an array of every check the parser may emit,
-- sorted by id. Each entry is `{id, kind, default_severity, code, spec_ref,
-- message_template, verified [, verification_note]}`. Inspectable for audit
-- and for generating policy files via `sdp.default_policy()`.
M.checks = errors.checks

--- Default policy table — `{id = default_severity}` for every registered
-- check. Dump it, edit it, save it as your config, pass back via
-- `parse(text, mode, { policy = ... })`. Unknown ids in a policy fail at
-- parse() time so typos surface immediately.
M.default_policy = errors.default_policy

-- Exposed for spec access; not part of the public contract.
M._errors = errors

return M
