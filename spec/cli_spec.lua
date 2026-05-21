---@diagnostic disable
local dkjson = require("dkjson")

-- Run `lua bin/parse_sdp <args_str>` as a subprocess.
-- The library lives at parse_sdp/init.lua; bin/parse_sdp is the CLI
-- shell that requires it. Running the CLI explicitly via `lua` (rather
-- than relying on the shebang + executable bit) keeps the test
-- portable across container / host environments.
-- stdin_text: optional string piped to the process's stdin.
-- Returns stdout (string), stderr (string), exit_code (number).
local function run(args_str, stdin_text)
  local tmp_err = os.tmpname()
  local tmp_in

  local cmd
  if stdin_text then
    tmp_in = os.tmpname()
    local f = assert(io.open(tmp_in, "w"))
    f:write(stdin_text)
    f:close()
    cmd = string.format("lua bin/parse_sdp %s < %s 2>%s", args_str, tmp_in, tmp_err)
  else
    cmd = string.format("lua bin/parse_sdp %s 2>%s", args_str, tmp_err)
  end

  local handle  = io.popen(cmd, "r")
  local stdout  = handle:read("*a")
  local _, _, code = handle:close()

  local ef     = io.open(tmp_err, "r")
  local stderr = ef and ef:read("*a") or ""
  if ef then ef:close() end

  os.remove(tmp_err)
  if tmp_in then os.remove(tmp_in) end

  return stdout, stderr, code or 0
end

-- ── validate subcommand ─────────────────────────────────────────────────────

describe("CLI: validate subcommand", function()

  -- NOT-SPEC: library
  it("valid SDP → 'OK' on stdout, exit 0", function()
    local stdout, stderr, code = run("validate spec/fixtures/minimal.sdp")
    assert.equal(0, code)
    assert.equal("", stderr)
    assert.equal("OK\n", stdout)
  end)

  -- NOT-SPEC: library
  it("invalid SDP → formatted error on stderr, exit 1", function()
    local stdout, stderr, code = run("validate spec/fixtures/invalid.sdp")
    assert.equal(1, code)
    assert.equal("", stdout)
    assert.truthy(stderr:match("^error:"))
  end)

  it("--mode st2110 accepts a valid ST 2110 file", function()
    local _, _, code = run("validate --mode st2110 spec/fixtures/st2110_video.sdp")
    assert.equal(0, code)
  end)

  it("--mode st2110 rejects a non-conformant SDP", function()
    -- 01_missing_tsrefclk lacks the per-media a=ts-refclk required by
    -- ST 2110-10:2022 §8.2. Same fixture the to_json test uses.
    local stdout, stderr, code = run(
      "validate --mode st2110 examples/st2110/invalid/01_missing_tsrefclk.sdp")
    assert.equal(1, code)
    assert.equal("", stdout)
    assert.truthy(stderr:match("^error:"))
  end)

  -- NOT-SPEC: library
  it("reads from stdin when '-' is given", function()
    local sdp_text = "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=Test\r\nt=0 0\r\n"
    local _, _, code = run("validate -", sdp_text)
    assert.equal(0, code)
  end)

  -- NOT-SPEC: library
  it("reads from stdin when file is omitted", function()
    local sdp_text = "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=Test\r\nt=0 0\r\n"
    local _, _, code = run("validate", sdp_text)
    assert.equal(0, code)
  end)

  -- NOT-SPEC: library
  it("unknown mode → formatted error on stderr, exit 1", function()
    local _, stderr, code = run("validate --mode bogus spec/fixtures/minimal.sdp")
    assert.equal(1, code)
    assert.truthy(stderr:match("unknown mode"))
  end)

  -- NOT-SPEC: library
  it("missing file → error on stderr, exit 1", function()
    local _, stderr, code = run("validate spec/fixtures/no_such.sdp")
    assert.equal(1, code)
    assert.truthy(stderr:match("^error:"))
  end)

  -- NOT-SPEC: library
  it("--help exits 0 and mentions --mode", function()
    local stdout, _, code = run("validate --help")
    assert.equal(0, code)
    assert.truthy(stdout:find("--mode", 1, true))
  end)

end)

-- ── diagnose subcommand ─────────────────────────────────────────────────────

describe("CLI: diagnose subcommand", function()

  -- NOT-SPEC: library
  it("media-less SDP shows ✓ at every tier and exits 0", function()
    -- An SDP with no m= blocks has nothing to violate at higher tiers;
    -- ST 2110 / IPMX checks are per-media-block.
    local stdout, _, code = run("diagnose spec/fixtures/minimal.sdp")
    assert.equal(0, code)
    assert.truthy(stdout:find("✓ RFC 8866", 1, true))
    assert.truthy(stdout:find("✓ SMPTE ST 2110", 1, true))
    assert.truthy(stdout:find("✓ IPMX", 1, true))
  end)

  -- NOT-SPEC: library
  it("ST 2110 failure shows ✓/✗ with finding detail, exits 0", function()
    -- 01_missing_tsrefclk is RFC 8866-valid but lacks the per-media
    -- a=ts-refclk that ST 2110-10:2022 §8.2 requires.
    local stdout, _, code = run(
      "diagnose examples/st2110/invalid/01_missing_tsrefclk.sdp")
    assert.equal(0, code)
    assert.truthy(stdout:find("✓ RFC 8866", 1, true))
    assert.truthy(stdout:find("✗ SMPTE ST 2110", 1, true))
    assert.truthy(stdout:find("st2110.attr.ts-refclk-required", 1, true))
    assert.truthy(stdout:find("ST 2110-10:2022 §8.2", 1, true))
  end)

  -- NOT-SPEC: library
  it("base SDP failure cascades, with 'inherits' note on higher tiers", function()
    local stdout, _, code = run("diagnose spec/fixtures/invalid.sdp")
    assert.equal(0, code)
    assert.truthy(stdout:find("✗ RFC 8866", 1, true))
    assert.truthy(stdout:find("✗ SMPTE ST 2110", 1, true))
    assert.truthy(stdout:find("✗ IPMX", 1, true))
    assert.truthy(stdout:find("inherits", 1, true))
  end)

  -- NOT-SPEC: library
  it("reads from stdin when '-' is given", function()
    local sdp_text = "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=Test\r\nt=0 0\r\n"
    local stdout, _, code = run("diagnose -", sdp_text)
    assert.equal(0, code)
    assert.truthy(stdout:find("✓ RFC 8866", 1, true))
  end)

  -- NOT-SPEC: library
  it("missing file → error on stderr, exit 1", function()
    -- The diagnostic itself can't run if input can't be read; that's an
    -- exit-1 condition, distinct from a per-tier failure.
    local _, stderr, code = run("diagnose spec/fixtures/no_such.sdp")
    assert.equal(1, code)
    assert.truthy(stderr:match("^error:"))
  end)

  -- NOT-SPEC: library
  it("--help exits 0", function()
    local stdout, _, code = run("diagnose --help")
    assert.equal(0, code)
    assert.truthy(stdout:find("tier", 1, true))
  end)

end)

-- ── --all-findings flag (validate / diagnose / to_json) ─────────────────────

describe("CLI: --all-findings flag", function()

  -- NOT-SPEC: library
  it("validate: clean fixture with no findings still prints OK, exit 0", function()
    -- A file with no warnings either should match the no-flag behavior;
    -- --all-findings is a no-op on a finding-free parse. crlf.sdp is the
    -- one fixture in the suite known to use CRLF (no LF-only warnings).
    local sdp_text = "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=Test\r\nt=0 0\r\n"
    local stdout, stderr, code = run("validate --all-findings", sdp_text)
    assert.equal(0, code)
    assert.equal("OK\n", stdout)
    assert.equal("", stderr)
  end)

  -- NOT-SPEC: library
  it("validate: file with warnings only → list on stderr, exit 0", function()
    -- minimal.sdp uses LF-only line endings: every line emits the
    -- default-warn 'sdp.line.lf-only-line-ending' finding. No errors.
    local stdout, stderr, code = run(
      "validate --all-findings spec/fixtures/minimal.sdp")
    assert.equal(0, code)
    assert.equal("", stdout)
    assert.truthy(stderr:find("findings:", 1, true))
    assert.truthy(stderr:find("sdp.line.lf-only-line-ending", 1, true))
    assert.truthy(stderr:find("(warn)", 1, true))
  end)

  -- NOT-SPEC: library
  it("validate: file with multiple errors lists all of them, exit 1", function()
    -- 03_missing_fmtp has NO a=fmtp on a raw-video stream; ST 2110-20
    -- §7.2 lists 8 required params + §7.4.2 depth + §7.1 TP = 9 errors.
    local stdout, stderr, code = run(
      "validate --all-findings --mode st2110 examples/st2110/invalid/03_missing_fmtp.sdp")
    assert.equal(1, code)
    assert.equal("", stdout)
    -- Every required-param error should appear by id.
    for _, key in ipairs({ "sampling", "width", "height", "exactframerate",
                            "depth", "colorimetry", "PM", "SSN", "TP" }) do
      assert.truthy(stderr:find(
        "st2110-20.a.fmtp." .. key .. "-required", 1, true),
        "missing required-param finding: " .. key)
    end
    -- And they should be labeled (error) — the default severity before demotion.
    assert.truthy(stderr:find("(error)", 1, true))
  end)

  -- NOT-SPEC: library
  it("validate: --all-findings reads from stdin via '-'", function()
    local sdp_text = "v=0\no=- 1 1 IN IP4 127.0.0.1\ns=Test\nt=0 0\n"
    local stdout, stderr, code = run("validate --all-findings -", sdp_text)
    assert.equal(0, code)
    assert.equal("", stdout)
    assert.truthy(stderr:find("sdp.line.lf-only-line-ending", 1, true))
  end)

  -- NOT-SPEC: library
  it("to_json: --all-findings emits JSON on stdout + findings on stderr", function()
    local stdout, stderr, code = run(
      "to_json --all-findings --mode st2110 examples/st2110/invalid/03_missing_fmtp.sdp")
    assert.equal(1, code)
    -- JSON still emitted (the parse succeeded under demotion).
    local decoded = dkjson.decode(stdout)
    assert.is_table(decoded)
    assert.equal("0", decoded.version)
    -- Errors enumerated on stderr.
    assert.truthy(stderr:find("st2110-20.a.fmtp.sampling-required", 1, true))
  end)

  -- NOT-SPEC: library
  it("to_json: --all-findings on a clean file behaves like no flag", function()
    local sdp_text = "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=Test\r\nt=0 0\r\n"
    local stdout, stderr, code = run("to_json --all-findings", sdp_text)
    assert.equal(0, code)
    assert.equal("", stderr)
    local decoded = dkjson.decode(stdout)
    assert.is_table(decoded)
  end)

  -- NOT-SPEC: library
  it("diagnose: --all-findings shows every finding per tier, exit 0", function()
    -- diagnose's exit-code contract is unaffected by --all-findings: the
    -- diagnostic ran, so the verdict is the output (always 0).
    local stdout, _, code = run(
      "diagnose --all-findings examples/st2110/invalid/03_missing_fmtp.sdp")
    assert.equal(0, code)
    -- Multiple ST 2110 errors enumerated under the ✗ row (not just one).
    assert.truthy(stdout:find(
      "st2110-20.a.fmtp.sampling-required", 1, true))
    assert.truthy(stdout:find(
      "st2110-20.a.fmtp.TP-required", 1, true))
    -- IPMX collapses to the inherits note (no new IPMX-tier findings).
    assert.truthy(stdout:find("inherits SMPTE ST 2110", 1, true))
  end)

  -- NOT-SPEC: library
  it("validate --help mentions --all-findings", function()
    local stdout, _, code = run("validate --help")
    assert.equal(0, code)
    assert.truthy(stdout:find("--all-findings", 1, true))
  end)

end)

-- ── to_json subcommand ───────────────────────────────────────────────────────

describe("CLI: to_json subcommand", function()

  -- NOT-SPEC: library
  it("parses a valid SDP file → JSON on stdout, exit 0", function()
    local stdout, stderr, code = run("to_json spec/fixtures/minimal.sdp")
    assert.equal(0, code)
    assert.equal("", stderr)
    local decoded = dkjson.decode(stdout)
    assert.is_table(decoded)
    assert.equal("0", decoded.version)
  end)

  -- NOT-SPEC: library
  it("reads from stdin when no file given → JSON on stdout, exit 0", function()
    local sdp_text = "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=Test\r\nt=0 0\r\n"
    local stdout, stderr, code = run("to_json", sdp_text)
    assert.equal(0, code)
    assert.equal("", stderr)
    local decoded = dkjson.decode(stdout)
    assert.is_table(decoded)
  end)

  -- NOT-SPEC: library
  it("invalid SDP → human-readable error on stderr, exit 1", function()
    local stdout, stderr, code = run("to_json spec/fixtures/invalid.sdp")
    assert.equal(1, code)
    assert.equal("", stdout)
    assert.truthy(stderr:match("^error:"))
  end)

  it("--mode st2110 with valid ST 2110 file → exit 0", function()
    local stdout, _, code = run("to_json --mode st2110 spec/fixtures/st2110_video.sdp")
    assert.equal(0, code)
    local decoded = dkjson.decode(stdout)
    assert.is_table(decoded)
  end)

  it("--mode st2110 with a non-conformant SDP → human-readable error on stderr, exit 1", function()
    -- 01_missing_tsrefclk has a media block lacking the per-block
    -- ts-refclk SHALL (ST 2110-10:2022 §8.2). Replaces the previous
    -- minimal.sdp fixture: the grammar tier no longer rejects empty
    -- SDPs at the st2110 mode (no spec text mandates ≥1 media block).
    local stdout, stderr, code = run(
      "to_json --mode st2110 examples/st2110/invalid/01_missing_tsrefclk.sdp")
    assert.equal(1, code)
    assert.equal("", stdout)
    assert.truthy(stderr:match("^error:"))
  end)

  -- NOT-SPEC: library
  it("--pretty produces indented JSON", function()
    local stdout, _, code = run("to_json --pretty spec/fixtures/minimal.sdp")
    assert.equal(0, code)
    assert.truthy(stdout:find("\n", 2, true))
  end)

  -- NOT-SPEC: library
  it("unknown subcommand → exit 1", function()
    local _, _, code = run("bogus")
    assert.equal(1, code)
  end)

  -- NOT-SPEC: library
  it("missing file → human-readable error on stderr, exit 1", function()
    local stdout, stderr, code = run("to_json spec/fixtures/no_such_file.sdp")
    assert.equal(1, code)
    assert.equal("", stdout)
    assert.truthy(stderr:match("^error:"))
  end)

  -- NOT-SPEC: library
  it("--help exits 0 and prints usage", function()
    local stdout, _, code = run("--help")
    assert.equal(0, code)
    assert.truthy(stdout:find("parse_sdp", 1, true))
  end)

  -- NOT-SPEC: library
  it("to_json --help exits 0 and mentions --mode", function()
    local stdout, _, code = run("to_json --help")
    assert.equal(0, code)
    assert.truthy(stdout:find("--mode", 1, true))
  end)

end)

-- ── checks subcommand ──────────────────────────────────────────────────────

describe("CLI: checks subcommand", function()

  -- NOT-SPEC: library
  it("default format lists every registered check, exit 0", function()
    local stdout, stderr, code = run("checks")
    assert.equal(0, code)
    assert.equal("", stderr)
    -- One line per check; row count matches the registry.
    local sdp = require("parse_sdp")
    local expected = #sdp.checks()
    local n = 0
    for _ in stdout:gmatch("[^\n]+") do n = n + 1 end
    assert.equal(expected, n)
    -- Each row has the id / severity / spec_ref shape.
    assert.truthy(stdout:find("sdp.v.must-be-zero", 1, true))
    assert.truthy(stdout:find("RFC 8866 §5.1", 1, true))
  end)

  -- NOT-SPEC: library
  it("--filter narrows by substring match against the id", function()
    -- Plain substring (not Lua pattern): the literal '-' in 'ts-refclk'
    -- would be a lazy quantifier under Lua patterns and silently match
    -- nothing, which is the wrong default for a filter UX.
    local stdout, _, code = run("checks --filter ts-refclk")
    assert.equal(0, code)
    -- All registered ts-refclk checks should be present.
    assert.truthy(stdout:find("sdp.a.ts-refclk.ptp-malformed", 1, true))
    assert.truthy(stdout:find("sdp.a.ts-refclk.traceable-mix", 1, true))
    -- Unrelated checks should be filtered out.
    assert.is_nil(stdout:find("sdp.v.must-be-zero", 1, true))
  end)

  -- NOT-SPEC: library
  it("--format json emits an array decodable to the registry shape", function()
    local stdout, _, code = run("checks --format json --filter sdp.v.must-be-zero")
    assert.equal(0, code)
    local arr = dkjson.decode(stdout)
    assert.is_table(arr)
    assert.equal(1, #arr)
    local entry = arr[1]
    assert.equal("sdp.v.must-be-zero", entry.id)
    assert.equal("error", entry.default_severity)
    assert.equal("semantic", entry.kind)
    assert.equal("RFC 8866 §5.1", entry.spec_ref)
    assert.is_string(entry.message_template)
    assert.equal(true, entry.verified)
  end)

  -- NOT-SPEC: library
  it("--format json without --filter matches sdp.checks() length", function()
    local stdout, _, code = run("checks --format json")
    assert.equal(0, code)
    local arr = dkjson.decode(stdout)
    assert.is_table(arr)
    local sdp = require("parse_sdp")
    assert.equal(#sdp.checks(), #arr)
  end)

  -- NOT-SPEC: library
  it("--unverified matches the registry's verified=false rows", function()
    local stdout, _, code = run("checks --unverified --format json")
    assert.equal(0, code)
    local arr = dkjson.decode(stdout)
    assert.is_table(arr)
    -- Every emitted row carries verified=false.
    for _, c in ipairs(arr) do
      assert.equal(false, c.verified)
    end
    -- And the count matches the registry's verified=false count.
    local sdp = require("parse_sdp")
    local expected = 0
    for _, c in ipairs(sdp.checks()) do
      if c.verified == false then expected = expected + 1 end
    end
    assert.equal(expected, #arr)
  end)

  -- NOT-SPEC: library
  it("unknown --format → error on stderr, exit 1", function()
    local _, stderr, code = run("checks --format bogus")
    assert.equal(1, code)
    assert.truthy(stderr:match("^error:"))
    assert.truthy(stderr:find("unknown --format", 1, true))
  end)

  -- NOT-SPEC: library
  it("--help exits 0 and mentions --filter / --format", function()
    local stdout, _, code = run("checks --help")
    assert.equal(0, code)
    assert.truthy(stdout:find("--filter", 1, true))
    assert.truthy(stdout:find("--format", 1, true))
  end)

end)

-- ── to_sdp subcommand ────────────────────────────────────────────────────────

describe("CLI: to_sdp subcommand", function()

  -- Parse a fixture to JSON, return the JSON string.
  local function fixture_json(sdp_file)
    local h = io.popen("lua bin/parse_sdp to_json " .. sdp_file, "r")
    local json = h:read("*a")
    h:close()
    return json
  end

  -- NOT-SPEC: library
  it("serializes JSON from stdin → SDP text on stdout, exit 0", function()
    local json = fixture_json("spec/fixtures/minimal.sdp")
    local stdout, stderr, code = run("to_sdp", json)
    assert.equal(0, code)
    assert.equal("", stderr)
    assert.truthy(stdout:find("v=0", 1, true))
    assert.truthy(stdout:find("s=Minimal", 1, true))
  end)

  -- NOT-SPEC: library
  it("serializes JSON from file → SDP text on stdout, exit 0", function()
    local json = fixture_json("spec/fixtures/minimal.sdp")
    local tmp = os.tmpname()
    local f = assert(io.open(tmp, "w"))
    f:write(json)
    f:close()
    local stdout, stderr, code = run("to_sdp " .. tmp)
    os.remove(tmp)
    assert.equal(0, code)
    assert.equal("", stderr)
    assert.truthy(stdout:find("v=0", 1, true))
  end)

  -- NOT-SPEC: library
  it("invalid JSON → human-readable error on stderr, exit 1", function()
    local stdout, stderr, code = run("to_sdp", "not { valid } json")
    assert.equal(1, code)
    assert.equal("", stdout)
    assert.truthy(stderr:match("^error:"))
  end)

  -- NOT-SPEC: library
  it("missing file → human-readable error on stderr, exit 1", function()
    local stdout, stderr, code = run("to_sdp spec/fixtures/no_such.json")
    assert.equal(1, code)
    assert.equal("", stdout)
    assert.truthy(stderr:match("^error:"))
  end)

  -- NOT-SPEC: library
  it("round-trip: to_json → to_sdp produces re-parseable SDP", function()
    local json = fixture_json("spec/fixtures/minimal.sdp")
    local stdout, _, code = run("to_sdp", json)
    assert.equal(0, code)
    local sdp = require("parse_sdp")
    local doc = sdp.parse(stdout)
    assert.is_table(doc)
    assert.equal("0", doc.version)
    assert.equal("Minimal", doc.session.name)
  end)

end)
