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
-- No mode argument means RFC 4566 validation only.

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
print("  doc.session.timing.start       = " .. doc.session.timing.start)
print("  doc.session.timing.stop        = " .. doc.session.timing.stop)
print("  #doc.session.emails            = " .. #doc.session.emails)
print("  #doc.session.attributes        = " .. #doc.session.attributes)
print("  doc.session.attributes[1].name = " .. doc.session.attributes[1].name)
print("  #doc.media                     = " .. #doc.media)

subsection("doc.media — per-media fields")
for i, m in ipairs(doc.media) do
  print(string.format("  media[%d]  type=%-12s  port=%-6d  proto=%-8s  fmts=%s",
    i, m.media, m.port, m.proto, table.concat(m.fmts, " ")))
  for _, a in ipairs(m.attributes or {}) do
    local val = a.value and (": " .. a.value:sub(1, 48)) or ""
    print(string.format("    a=%-14s%s", a.name, val))
  end
end

-- ─────────────────────────────────────────────────────────────────────────────
section("2. Validation modes — sdp.parse(text, mode)")
-- ─────────────────────────────────────────────────────────────────────────────

-- The same file can be validated against different tiers by passing a mode.
-- "st2110" validates ST 2110-10/20/30/40/41 rules on top of RFC 4566.
-- "ipmx" validates IPMX rules (which first run ST 2110, which first runs RFC 4566).

local ipmx_text = read("examples/ipmx/valid/02_typical.sdp")

subsection("Parse with no mode  →  RFC 4566 only")
local d1 = sdp.parse(ipmx_text)
print("  sdp.parse(text)           →  " .. (d1 and "doc  (RFC 4566 valid)" or "nil"))

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

subsection("doc:to_sdp()  →  SDP text (CRLF, RFC 4566 field order)")
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
    name       = "Built Programmatically",
    timing     = { start = 0, stop = 0 },
    attributes = {},
    bandwidths = {},
    emails     = {},
    phones     = {},
  },
  media = {},
}

local built = sdp.new(raw)
print("  sdp.new(raw):is_sdp()   →  " .. tostring(built:is_sdp()))
print("  built:to_sdp():")
print("  " .. built:to_sdp():gsub("\r\n", "\\r\\n\n  "))

-- ─────────────────────────────────────────────────────────────────────────────
section("5. Error anatomy — what a failure looks like")
-- ─────────────────────────────────────────────────────────────────────────────

-- All parse and validation failures return nil, err  (never throw).
-- err is a plain table with these fields:

local function show_error(label, text, mode)
  print("\n" .. label)
  local _, e = sdp.parse(text, mode)
  print("  err.message    = " .. tostring(e.message))
  print("  err.code       = " .. tostring(e.code))
  print("  err.line       = " .. tostring(e.line))
  print("  err.col        = " .. tostring(e.col))
  print("  err.field_path = " .. tostring(e.field_path))
  print("  err.spec_ref   = " .. tostring(e.spec_ref))
end

show_error(
  "generic/invalid/02_wrong_order.sdp  (RFC 4566 field ordering)",
  read("examples/generic/invalid/02_wrong_order.sdp"))

show_error(
  "st2110/invalid/04_bad_tsrefclk_gmid.sdp  (malformed PTP GMID)",
  read("examples/st2110/invalid/04_bad_tsrefclk_gmid.sdp"), "st2110")

show_error(
  "ipmx/invalid/01_missing_extmap.sdp  (IPMX layer: extmap absent)",
  read("examples/ipmx/invalid/01_missing_extmap.sdp"), "ipmx")

-- ─────────────────────────────────────────────────────────────────────────────
section("6. Full sweep — all example files")
-- ─────────────────────────────────────────────────────────────────────────────

-- Format: PASS/FAIL  [expected]  filename  |  result detail

local function sweep(files, mode, expect_ok)
  for _, path in ipairs(files) do
    local text2 = read(path)
    local d, e = sdp.parse(text2, mode)
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

subsection("generic  (RFC 4566 only)")
print("  valid:")
sweep({
  "examples/generic/valid/01_simple_audio.sdp",
  "examples/generic/valid/02_simple_video.sdp",
  "examples/generic/valid/03_typical_conference.sdp",
  "examples/generic/valid/04_typical_streaming.sdp",
  "examples/generic/valid/05_pathological.sdp",
}, nil, true)
print("  invalid:")
sweep({
  "examples/generic/invalid/01_missing_fields.sdp",
  "examples/generic/invalid/02_wrong_order.sdp",
  "examples/generic/invalid/03_malformed_origin.sdp",
  "examples/generic/invalid/04_bad_version.sdp",
}, nil, false)

subsection("st2110  (ST 2110-10/20/30/40/41 + RFC 4566)")
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
  "examples/st2110/invalid/06_missing_channel_order.sdp",
  "examples/st2110/invalid/07_missing_did_sdid.sdp",
  "examples/st2110/invalid/08_missing_ssn.sdp",
}, "st2110", false)

subsection("ipmx  (IPMX + ST 2110 + RFC 4566)")
print("  valid:")
sweep({
  "examples/ipmx/valid/01_simple_video.sdp",
  "examples/ipmx/valid/02_typical.sdp",
  "examples/ipmx/valid/03_pathological.sdp",
}, "ipmx", true)
print("  invalid:")
sweep({
  "examples/ipmx/invalid/01_missing_extmap.sdp",
  "examples/ipmx/invalid/02_fails_st2110.sdp",
}, "ipmx", false)

print("\n" .. ("━"):rep(66))
print("  Done.")
print(("━"):rep(66) .. "\n")
