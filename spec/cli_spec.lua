local dkjson = require("dkjson")

-- Run `lua parse_sdp.lua <args_str>` as a subprocess.
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
    cmd = string.format("lua parse_sdp.lua %s < %s 2>%s", args_str, tmp_in, tmp_err)
  else
    cmd = string.format("lua parse_sdp.lua %s 2>%s", args_str, tmp_err)
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

-- ── to_json subcommand ───────────────────────────────────────────────────────

describe("CLI: to_json subcommand", function()

  it("parses a valid SDP file → JSON on stdout, exit 0", function()
    local stdout, stderr, code = run("to_json spec/fixtures/minimal.sdp")
    assert.equal(0, code)
    assert.equal("", stderr)
    local decoded = dkjson.decode(stdout)
    assert.is_table(decoded)
    assert.equal("0", decoded.version)
  end)

  it("reads from stdin when no file given → JSON on stdout, exit 0", function()
    local sdp_text = "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=Test\r\nt=0 0\r\n"
    local stdout, stderr, code = run("to_json", sdp_text)
    assert.equal(0, code)
    assert.equal("", stderr)
    local decoded = dkjson.decode(stdout)
    assert.is_table(decoded)
  end)

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

  it("--mode st2110 with plain SDP → human-readable error on stderr, exit 1", function()
    local stdout, stderr, code = run("to_json --mode st2110 spec/fixtures/minimal.sdp")
    assert.equal(1, code)
    assert.equal("", stdout)
    assert.truthy(stderr:match("^error:"))
  end)

  it("--pretty produces indented JSON", function()
    local stdout, _, code = run("to_json --pretty spec/fixtures/minimal.sdp")
    assert.equal(0, code)
    assert.truthy(stdout:find("\n", 2, true))
  end)

  it("unknown subcommand → exit 1", function()
    local _, _, code = run("bogus")
    assert.equal(1, code)
  end)

  it("missing file → human-readable error on stderr, exit 1", function()
    local stdout, stderr, code = run("to_json spec/fixtures/no_such_file.sdp")
    assert.equal(1, code)
    assert.equal("", stdout)
    assert.truthy(stderr:match("^error:"))
  end)

  it("--help exits 0 and prints usage", function()
    local stdout, _, code = run("--help")
    assert.equal(0, code)
    assert.truthy(stdout:find("parse_sdp", 1, true))
  end)

  it("to_json --help exits 0 and mentions --mode", function()
    local stdout, _, code = run("to_json --help")
    assert.equal(0, code)
    assert.truthy(stdout:find("--mode", 1, true))
  end)

end)

-- ── to_sdp subcommand ────────────────────────────────────────────────────────

describe("CLI: to_sdp subcommand", function()

  -- Parse a fixture to JSON, return the JSON string.
  local function fixture_json(sdp_file)
    local h = io.popen("lua parse_sdp.lua to_json " .. sdp_file, "r")
    local json = h:read("*a")
    h:close()
    return json
  end

  it("serializes JSON from stdin → SDP text on stdout, exit 0", function()
    local json = fixture_json("spec/fixtures/minimal.sdp")
    local stdout, stderr, code = run("to_sdp", json)
    assert.equal(0, code)
    assert.equal("", stderr)
    assert.truthy(stdout:find("v=0", 1, true))
    assert.truthy(stdout:find("s=Minimal", 1, true))
  end)

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

  it("invalid JSON → human-readable error on stderr, exit 1", function()
    local stdout, stderr, code = run("to_sdp", "not { valid } json")
    assert.equal(1, code)
    assert.equal("", stdout)
    assert.truthy(stderr:match("^error:"))
  end)

  it("missing file → human-readable error on stderr, exit 1", function()
    local stdout, stderr, code = run("to_sdp spec/fixtures/no_such.json")
    assert.equal(1, code)
    assert.equal("", stdout)
    assert.truthy(stderr:match("^error:"))
  end)

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
