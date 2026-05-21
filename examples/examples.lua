-- examples/examples.lua
-- Run from the repo root:  lua examples/examples.lua
-- (or inside the container: docker compose run --rm test lua examples/examples.lua)
--
-- Walks through the full public API using the files in examples/.
-- Sections are meant to be read alongside the output they produce.

local sdp = require("parse_sdp")

-- ── helpers ───────────────────────────────────────────────────────────────────

local function read(path)
  local f = assert(io.open(path, "r"), "cannot open " .. path)
  local t = f:read("*a"); f:close(); return t
end

local function hr() print(("─"):rep(66)) end
local function section(title)
  print("\n" .. ("━"):rep(66))
  print("  " .. title)
  print(("━"):rep(66))
end
local function subsection(title)
  print("\n── " .. title .. " " .. ("─"):rep(math.max(0, 62 - #title)))
end

-- ─────────────────────────────────────────────────────────────────────────────
section("1. Parsing — sdp.parse(text)")
-- ─────────────────────────────────────────────────────────────────────────────

-- sdp.parse(text) returns a doc table on success, or nil + error table on failure.
-- No mode argument means RFC 8866 validation only.

local text = read("examples/generic/valid/03_typical_conference.sdp")
local doc, err = sdp.parse(text)

print("\nFile: examples/generic/valid/03_typical_conference.sdp")
print("  sdp.parse(text)  →  " .. (doc and "doc" or "nil, err"))

subsection("doc is a plain Lua table — field access")
print("  doc.version                    = " .. tostring(doc.version))
print("  doc.origin.username            = " .. doc.origin.username)
print("  doc.origin.sess_id             = " .. doc.origin.sess_id)
print("  doc.origin.net_type            = " .. doc.origin.net_type)
print("  doc.origin.addr_type           = " .. doc.origin.addr_type)
print("  doc.origin.unicast_address     = " .. doc.origin.unicast_address)
print("  doc.session.name               = " .. doc.session.name)
print("  doc.session.info               = " .. tostring(doc.session.info))
print("  doc.session.uri                = " .. tostring(doc.session.uri))
local t = doc.session.time_descriptions and doc.session.time_descriptions[1] or {}
print("  doc.session.time_descriptions[1].start = " .. tostring(t.start))
print("  doc.session.time_descriptions[1].stop  = " .. tostring(t.stop))
print("  #doc.session.emails            = " .. #(doc.session.emails or {}))
print("  #doc.session.attributes        = " .. #(doc.session.attributes or {}))
if doc.session.attributes and #doc.session.attributes > 0 then
  print("  doc.session.attributes[1].name = " .. doc.session.attributes[1].name)
end
print("  #doc.media                     = " .. #doc.media)

subsection("doc.media — per-media fields")
-- Known attributes are returned in *decomposed* form in 1.1:
--   rtpmap → { name, payload_type, encoding, clock_rate [, channels] }
--   fmtp   → { name, payload_type, params={{key,val}, …} }   (or .raw)
--   mid, ptime, framerate, ts-refclk, mediaclk, group, ssrc, … similar.
-- Unknown / opaque attributes keep { name, value=string }.
local function format_attr(a)
  if a.name == "rtpmap" then
    local s = string.format("pt=%s %s/%s", a.payload_type, a.encoding, a.clock_rate)
    if a.channels then s = s .. "/" .. a.channels end
    return s
  elseif a.name == "fmtp" then
    if a.raw then return "pt=" .. tostring(a.payload_type) .. " " .. a.raw:sub(1, 48) end
    local kv = {}
    for _, p in ipairs(a.params or {}) do kv[#kv+1] = p[1] .. "=" .. tostring(p[2]) end
    return "pt=" .. tostring(a.payload_type) .. " " .. table.concat(kv, "; "):sub(1, 60)
  elseif a.value then
    return a.value:sub(1, 60)
  end
  return ""   -- flag-only attribute (e.g. recvonly)
end

for i, m in ipairs(doc.media) do
  print(string.format("  media[%d]  type=%-12s  port=%-6d  proto=%-8s  fmts=%s",
    i, m.media, m.port, m.proto, table.concat(m.fmts, " ")))
  for _, a in ipairs(m.attributes or {}) do
    local rendered = format_attr(a)
    local sep = rendered ~= "" and ": " or ""
    print(string.format("    a=%-10s%s%s", a.name, sep, rendered))
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
section("2. Validation modes — sdp.parse(text, mode)")
-- ─────────────────────────────────────────────────────────────────────────────

-- The same file can be validated against different tiers by passing a mode.
-- "st2110" validates ST 2110-10/20/30/40/41 rules on top of RFC 8866.
-- "ipmx" validates IPMX rules (which first run ST 2110, which first runs RFC 8866).

local ipmx_text = read("examples/ipmx/valid/02_typical.sdp")

subsection("Parse with no mode  →  RFC 8866 only")
local d1 = sdp.parse(ipmx_text)
print("  sdp.parse(text)           →  " .. (d1 and "doc  (RFC 8866 valid)" or "nil"))

subsection("Parse with mode='st2110'")
local d2 = sdp.parse(ipmx_text, "st2110")
print("  sdp.parse(text, 'st2110') →  " .. (d2 and "doc  (ST 2110 valid)" or "nil"))

subsection("Parse with mode='ipmx'")
local d3 = sdp.parse(ipmx_text, "ipmx")
print("  sdp.parse(text, 'ipmx')   →  " .. (d3 and "doc  (IPMX valid)" or "nil"))

-- ─────────────────────────────────────────────────────────────────────────────
section("3. doc methods — validate, is_*, to_sdp, to_json")
-- ─────────────────────────────────────────────────────────────────────────────

-- sdp.parse() with no mode still gives a full doc with all methods.
-- Validation can be run post-parse using doc:validate(mode).

local multi_text = read("examples/st2110/valid/05_typical_multistream.sdp")
local mdoc = sdp.parse(multi_text)

subsection("doc:validate(mode)  →  true  or  nil, err")
local ok1            = mdoc:validate()
local ok2            = mdoc:validate("st2110")
local ok3, ve        = mdoc:validate("ipmx")
print("  doc:validate()         →  " .. tostring(ok1))
print("  doc:validate('st2110') →  " .. tostring(ok2))
print("  doc:validate('ipmx')   →  " .. tostring(ok3) ..
      (ve and ("  (err: " .. ve.message .. ")") or ""))

subsection("doc:is_sdp(), doc:is_st2110(), doc:is_ipmx()  →  bool")
print("  doc:is_sdp()    →  " .. tostring(mdoc:is_sdp()))
print("  doc:is_st2110() →  " .. tostring(mdoc:is_st2110()))
print("  doc:is_ipmx()   →  " .. tostring(mdoc:is_ipmx()))

subsection("doc:to_sdp()  →  SDP text (CRLF, RFC 8866 field order)")
local serialized = mdoc:to_sdp()
print("  First 4 lines of output:")
local n = 0
for line in (serialized .. "\n"):gmatch("([^\n]*)\n") do
  print("    " .. line:gsub("\r", "\\r"))
  n = n + 1; if n == 4 then break end
end

subsection("doc:to_json()  →  JSON string (via dkjson)")
local json = mdoc:to_json()
-- Print just the first 300 chars to keep output readable
print("  " .. json:sub(1, 300) .. (json:len() > 300 and " …" or ""))

-- ─────────────────────────────────────────────────────────────────────────────
section("4. sdp.new(table)  →  wrap a table as a doc without parsing")
-- ─────────────────────────────────────────────────────────────────────────────

-- sdp.new() attaches the doc metatable to any plain table.
-- Useful for constructing documents programmatically.

local raw = {
  version = "0",
  origin  = {
    username        = "builder",
    sess_id         = "1",
    sess_version    = "1",
    net_type        = "IN",
    addr_type       = "IP4",
    unicast_address = "127.0.0.1",
  },
  session = {
    name              = "Built Programmatically",
    time_descriptions = { { start = 0, stop = 0 } },
    attributes        = {},
  },
  media = {},
}

local built = sdp.new(raw)
print("  sdp.new(raw):is_sdp()   →  " .. tostring(built:is_sdp()))
local sdp_text = built:to_sdp()
if sdp_text then
  print("  built:to_sdp():")
  print("  " .. sdp_text:gsub("\r\n", "\\r\\n\n  "))
else
  print("  built:to_sdp()  →  nil (structural gaps in hand-built doc)")
end

-- ─────────────────────────────────────────────────────────────────────────────
section("5. Error anatomy — what a failure looks like")
-- ─────────────────────────────────────────────────────────────────────────────

-- All parse and validation failures return nil, err  (never throw).
-- err is a plain table with these fields:

local function show_error(label, text, mode)
  print("\n" .. label)
  local doc, err = sdp.parse(text, mode)
  if err then
    print("  err.id         = " .. tostring(err.id))
    print("  err.message    = " .. tostring(err.message))
    print("  err.code       = " .. tostring(err.code))
    print("  err.line       = " .. tostring(err.line))
    print("  err.col        = " .. tostring(err.col))
    print("  err.field_path = " .. tostring(err.field_path))
    print("  err.spec_ref   = " .. tostring(err.spec_ref))
  else
    print("  (parse succeeded — no error returned)")
  end
end

show_error(
  "generic/invalid/05_multiple_errors.sdp  (bad IPv4 in c= line)",
  read("examples/generic/invalid/05_multiple_errors.sdp"))

show_error(
  "st2110/invalid/03_missing_fmtp.sdp  (raw video fmtp missing 'sampling')",
  read("examples/st2110/invalid/03_missing_fmtp.sdp"), "st2110")

show_error(
  "ipmx/invalid/01_missing_ipmx_marker.sdp  (IPMX layer: IPMX fmtp marker absent)",
  read("examples/ipmx/invalid/01_missing_ipmx_marker.sdp"), "ipmx")

-- ─────────────────────────────────────────────────────────────────────────────
section("5.5 — Findings, warnings, and errors (NEW in 1.1)")
-- ─────────────────────────────────────────────────────────────────────────────

-- Parse returns a doc even when warnings are present (unless fail_on_first=true).
-- Access findings via doc:findings(), doc:warnings(), doc:errors().

subsection("Soft-syntactic warnings (RFC 8866 valid, style issues)")
local warnings_text = read("examples/generic/valid/06_soft_syntactic_warnings.sdp")
local doc_warn = sdp.parse(warnings_text)
print("  sdp.parse(lf-only SDP with no trailing newline):")
print("    → doc (parse succeeded)")
if doc_warn then
  print("    doc:findings() count = " .. #doc_warn:findings())
  print("    doc:warnings() count = " .. #doc_warn:warnings())
  print("    doc:errors() count   = " .. #doc_warn:errors())

  if #doc_warn:warnings() > 0 then
    print("\n  Warnings emitted:")
    for i, w in ipairs(doc_warn:warnings()) do
      print(string.format("    [%d] %s  (id: %s)", i, w.message, w.id))
    end
  end
end

subsection("Collecting findings via policy demotion")
-- Public-API contract: sdp.parse always returns nil, err when any
-- *error*-severity finding is present, so on a returned doc:
--   doc:errors()   → empty (errors short-circuit the return)
--   doc:warnings() → every warn-severity finding the parser emitted
--   doc:findings() → every finding (= warnings, on a returned doc)
-- To inspect *all* problems in a file with errors, demote the offending
-- check ids to "warn" via the policy table and parse again.

local errors_text = read("examples/generic/invalid/05_multiple_errors.sdp")
local demote = { ["sdp.c.address.invalid-ipv4"] = "warn" }
local doc_coll = sdp.parse(errors_text, nil, { policy = demote })
print("  sdp.parse(05_multiple_errors.sdp, demote invalid-ipv4 → warn):")
if doc_coll then
  print("    → doc (every former error now collected as a warning)")
  print("    doc:findings() count = " .. #doc_coll:findings())
  print("    doc:warnings() count = " .. #doc_coll:warnings())
  print("    doc:errors() count   = " .. #doc_coll:errors())
  for i, f in ipairs(doc_coll:findings()) do
    print(string.format("    [%d] (%s) %s", i, f.severity, f.message))
  end
end

subsection("fail_on_first — abort early vs full pass")
-- fail_on_first=false (default): the parser completes the whole grammar
--   match, recording every finding, then returns the *first* error-severity
--   finding as err (and the rest are discarded — see the policy-demotion
--   pattern above to keep them).
-- fail_on_first=true (1.0-compatible): the parser aborts on the first
--   error finding mid-match. Either way the user sees nil, err on an
--   error-laden file; the difference is which error becomes "first".

local _, err_a = sdp.parse(errors_text)                                 -- default
local _, err_b = sdp.parse(errors_text, nil, { fail_on_first = true })
print("  fail_on_first=false (default) → err.message = " .. tostring(err_a and err_a.message))
print("  fail_on_first=true            → err.message = " .. tostring(err_b and err_b.message))

subsection("Policy overrides — demote or promote severity")
-- The policy table lets you override the default severity of any check.
-- Keys are check IDs; values are "error", "warn", or "off".

local policy = {
  ["sdp.line.lf-only-line-ending"]     = "off",    -- ignore LF-only warnings
  ["sdp.file.trailing-newline-missing"] = "error", -- promote to error
}
local doc_policy, err_policy = sdp.parse(warnings_text, nil, { policy = policy })
print("  sdp.parse(same LF-only SDP, with policy overrides):")
print("    policy = { lf-only=off, trailing-newline-missing=error }")
if doc_policy then
  print("    → doc")
  print("    doc:warnings() count = " .. #doc_policy:warnings())
  print("    doc:errors() count   = " .. #doc_policy:errors())
else
  print("    → nil, err (due to promoted trailing-newline-missing)")
  if err_policy then
    print("    err.id = " .. tostring(err_policy.id))
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
section("6. Full sweep — all example files")
-- ─────────────────────────────────────────────────────────────────────────────

-- Format: PASS/FAIL  [expected]  filename  |  result detail

local function sweep(files, mode, expect_ok)
  for _, path in ipairs(files) do
    local text2 = read(path)
    local d, e = sdp.parse(text2, mode, { fail_on_first = true })
    local got_ok = d ~= nil
    local status = (got_ok == expect_ok) and "PASS" or "FAIL"
    local label = path:match("examples/(.+)$")
    local detail
    if got_ok then
      local parts = {}
      if d.session.name then parts[#parts+1] = '"' .. d.session.name:sub(1,32) .. '"' end
      if #d.media > 0 then
        parts[#parts+1] = #d.media .. " media"
      end
      detail = table.concat(parts, ", ")
    else
      detail = e.message .. "  [" .. (e.code or "?") .. "]"
    end
    print(string.format("  %s  %-46s  %s", status, label, detail))
  end
end

subsection("generic  (RFC 8866 only)")
print("  valid:")
sweep({
  "examples/generic/valid/01_simple_audio.sdp",
  "examples/generic/valid/02_simple_video.sdp",
  "examples/generic/valid/03_typical_conference.sdp",
  "examples/generic/valid/04_typical_streaming.sdp",
  "examples/generic/valid/05_pathological.sdp",
  "examples/generic/valid/06_soft_syntactic_warnings.sdp",
}, nil, true)
print("  invalid:")
sweep({
  "examples/generic/invalid/01_missing_fields.sdp",
  "examples/generic/invalid/02_wrong_order.sdp",
  "examples/generic/invalid/03_malformed_origin.sdp",
  "examples/generic/invalid/04_bad_version.sdp",
  "examples/generic/invalid/05_multiple_errors.sdp",
}, nil, false)

subsection("st2110  (ST 2110-10/20/30/40/41 + RFC 8866)")
print("  valid:")
sweep({
  "examples/st2110/valid/01_simple_video.sdp",
  "examples/st2110/valid/02_simple_audio.sdp",
  "examples/st2110/valid/03_typical_hd_video.sdp",
  "examples/st2110/valid/04_typical_4k_video.sdp",
  "examples/st2110/valid/05_typical_multistream.sdp",
  "examples/st2110/valid/06_pathological.sdp",
  "examples/st2110/valid/07_ancillary_data.sdp",
  "examples/st2110/valid/08_fast_metadata.sdp",
}, "st2110", true)
print("  invalid:")
sweep({
  "examples/st2110/invalid/01_missing_tsrefclk.sdp",
  "examples/st2110/invalid/02_missing_mediaclk.sdp",
  "examples/st2110/invalid/03_missing_fmtp.sdp",
  "examples/st2110/invalid/04_bad_tsrefclk_gmid.sdp",
  "examples/st2110/invalid/05_missing_sampling.sdp",
  "examples/st2110/invalid/06_bad_channel_order.sdp",
  "examples/st2110/invalid/07_missing_smpte291_ssn.sdp",
  "examples/st2110/invalid/08_missing_ssn.sdp",
}, "st2110", false)

subsection("ipmx  (IPMX + ST 2110 + RFC 8866)")
print("  valid:")
sweep({
  "examples/ipmx/valid/01_simple_video.sdp",
  "examples/ipmx/valid/02_typical.sdp",
  "examples/ipmx/valid/03_pathological.sdp",
}, "ipmx", true)
print("  invalid:")
sweep({
  "examples/ipmx/invalid/01_missing_ipmx_marker.sdp",
  "examples/ipmx/invalid/02_fails_st2110.sdp",
}, "ipmx", false)

print("\n" .. ("━"):rep(66))
print("  Done.")
print(("━"):rep(66) .. "\n")
