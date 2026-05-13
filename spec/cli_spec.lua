local dkjson = require("dkjson")

-- Run `lua cli.lua <args_str>` as a subprocess.
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
    cmd = string.format("lua cli.lua %s < %s 2>%s", args_str, tmp_in, tmp_err)
  else
    cmd = string.format("lua cli.lua %s 2>%s", args_str, tmp_err)
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

-- ── parse subcommand ──────────────────────────────────────────────────────────

describe("CLI: parse subcommand", function()

  it("parses a valid SDP file → JSON on stdout, exit 0", function()
    local stdout, stderr, code = run("parse spec/fixtures/minimal.sdp")
    assert.equal(0, code)
    assert.equal("", stderr)
    local decoded = dkjson.decode(stdout)
    assert.is_table(decoded)
    assert.equal("0", decoded.version)
  end)

  it("reads from stdin when no file given → JSON on stdout, exit 0", function()
    local sdp_text = "v=0\r\no=- 1 1 IN IP4 127.0.0.1\r\ns=Test\r\nt=0 0\r\n"
    local stdout, stderr, code = run("parse", sdp_text)
    assert.equal(0, code)
    assert.equal("", stderr)
    local decoded = dkjson.decode(stdout)
    assert.is_table(decoded)
  end)

  it("invalid SDP → JSON error on stderr, exit 1", function()
    local stdout, stderr, code = run("parse spec/fixtures/invalid.sdp")
    assert.equal(1, code)
    assert.equal("", stdout)
    local decoded = dkjson.decode(stderr)
    assert.is_table(decoded)
    assert.is_string(decoded.message)
  end)

  it("--mode st2110 with valid ST 2110 file → exit 0", function()
    local stdout, _, code = run("parse --mode st2110 spec/fixtures/st2110_video.sdp")
    assert.equal(0, code)
    local decoded = dkjson.decode(stdout)
    assert.is_table(decoded)
  end)

  it("--mode st2110 with plain SDP → JSON error on stderr, exit 1", function()
    local stdout, stderr, code = run("parse --mode st2110 spec/fixtures/minimal.sdp")
    assert.equal(1, code)
    assert.equal("", stdout)
    local decoded = dkjson.decode(stderr)
    assert.is_table(decoded)
    assert.is_string(decoded.message)
  end)

  it("--pretty produces indented JSON", function()
    local stdout, _, code = run("parse --pretty spec/fixtures/minimal.sdp")
    assert.equal(0, code)
    assert.truthy(stdout:find("\n", 2, true))
  end)

  it("unknown subcommand → exit 1", function()
    local _, _, code = run("bogus")
    assert.equal(1, code)
  end)

  it("missing file → JSON error on stderr, exit 1", function()
    local stdout, stderr, code = run("parse spec/fixtures/no_such_file.sdp")
    assert.equal(1, code)
    assert.equal("", stdout)
    local decoded = dkjson.decode(stderr)
    assert.is_table(decoded)
    assert.is_string(decoded.message)
  end)

end)
