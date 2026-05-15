---@diagnostic disable
-- Opt-in conformance suite.
-- Run with:  busted spec_conformance/
-- Fixtures are downloaded into spec_conformance/.cache/ on first run.
-- See spec_conformance/README.md for sources, attribution, and policy.

local sdp = require("parse_sdp")
local manifest  = require("spec_conformance.manifest")
local render    = require("spec_conformance.render")
local fetcher   = require("spec_conformance.fetcher")
local allowlist = require("spec_conformance.allowlist")

local function describe_err(err)
  if type(err) ~= "table" then return tostring(err) end
  local parts = { err.message or "(no message)" }
  if err.line then parts[#parts+1] = string.format("at %d:%d", err.line, err.column or 0) end
  if err.spec_ref then parts[#parts+1] = "[" .. err.spec_ref .. "]" end
  if err.line_text then parts[#parts+1] = "→ " .. err.line_text end
  return table.concat(parts, " ")
end

describe("AMWA upstream conformance", function()
  for _, fixture in ipairs(manifest.fixtures) do
    local source = manifest.sources[fixture.source]
    assert(source, "unknown source: " .. tostring(fixture.source))

    it(fixture.id, function()
      local raw, ferr = fetcher.read(source, fixture.path)
      assert.is_not_nil(raw, ferr)

      local text = fixture.vars and render(raw, fixture.vars) or raw
      -- Normalize trailing newline. Some upstream fixtures (e.g. nmos-testing
      -- video-2022-7.sdp) ship without one. The conformance suite is concerned
      -- with substantive ST 2110 content checks, not RFC 4566 §5 / §9 ABNF
      -- file-format hygiene — the latter is verified by spec/sdp_spec.lua.
      if text ~= "" and text:sub(-1) ~= "\n" then text = text .. "\r\n" end
      local doc, perr = sdp.parse(text, fixture.mode)
      local entry = allowlist[fixture.id]

      if fixture.expect == "fail" then
        -- Negative test: the upstream fixture is non-conformant per a specific
        -- clause and our parser is expected to reject it for the right reason.
        if doc then
          error(string.format("%s was expected to be rejected (%s) but parsed cleanly",
            fixture.id, fixture.expect_spec_ref or "no spec_ref"))
        end
        if fixture.expect_spec_ref and perr and perr.spec_ref ~= fixture.expect_spec_ref then
          error(string.format("%s rejected but wrong spec_ref: expected %q, got %q (%s)",
            fixture.id, fixture.expect_spec_ref, tostring(perr.spec_ref), describe_err(perr)))
        end
        return
      end

      if not doc then
        if entry then
          pending(string.format("allowlisted (%s): %s — %s", entry.spec_ref or "?", entry.reason, describe_err(perr)))
          return
        end
        error(string.format("%s failed to parse as %s: %s",
          fixture.id, tostring(fixture.mode or "rfc4566"), describe_err(perr)))
      end

      assert.is_table(doc)
      assert.is_string(doc:to_sdp())
      assert.is_string(doc:to_json())
    end)
  end
end)
