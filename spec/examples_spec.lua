---@diagnostic disable
-- Every file under examples/<tier>/<valid|invalid>/ carries its verdict in
-- its path: valid examples pass their tier, invalid ones fail it, and each
-- invalid one fails for the reason EXPECTED records. This keeps
-- the shipped examples honest as checks are added or removed (the browser
-- playground lists them by directory).

local sdp = require("parse_sdp")

local function list_sdp_files(dir)
  local h = assert(io.popen("ls " .. dir .. "/*.sdp 2>/dev/null", "r"))
  local out = {}
  for line in h:lines() do out[#out + 1] = line end
  h:close()
  return out
end

local function slurp(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

-- Why each invalid example fails. `error` and `line` are what the default
-- parse reports. `findings` lists every finding as "id@line" when every
-- error-severity check is demoted to warn (the CLI --all-findings view);
-- it is empty when the grammar cannot match at all. Line 0 means a
-- missing or cross-section item, located by field_path instead.
local EXPECTED = {
  ["examples/generic/invalid/01_missing_fields.sdp"] =
    { error = "PARSE_ERROR", line = 3 },
  ["examples/generic/invalid/02_wrong_order.sdp"] =
    { error = "PARSE_ERROR", line = 3 },
  ["examples/generic/invalid/03_malformed_origin.sdp"] =
    { error = "PARSE_ERROR", line = 2 },
  ["examples/generic/invalid/04_bad_version.sdp"] =
    { error = "PARSE_ERROR", line = 1 },
  ["examples/generic/invalid/05_multiple_errors.sdp"] =
    { error = "sdp.c.address.invalid-ipv4", line = 4,
      findings = { "sdp.c.address.invalid-ipv4@4" } },
  ["examples/generic/invalid/06_h264_interleaving_in_mode1.sdp"] =
    { error = "sdp.a.fmtp.h264.sprop-interleaving-depth-forbidden-in-mode",
      line = 0,
      findings = {
        "sdp.a.fmtp.h264.sprop-interleaving-depth-forbidden-in-mode@0",
        "sdp.a.fmtp.h264.sprop-max-don-diff-forbidden-in-mode@0",
      } },
  ["examples/st2110/invalid/01_missing_tsrefclk.sdp"] =
    { error = "st2110.attr.ts-refclk-required", line = 0,
      findings = { "st2110.attr.ts-refclk-required@0" } },
  ["examples/st2110/invalid/02_missing_mediaclk.sdp"] =
    { error = "st2110.attr.mediaclk-required", line = 0,
      findings = { "st2110.attr.mediaclk-required@0" } },
  ["examples/st2110/invalid/03_missing_fmtp.sdp"] =
    { error = "st2110-20.a.fmtp.sampling-required", line = 0,
      findings = {
        "st2110-20.a.fmtp.sampling-required@0",
        "st2110-20.a.fmtp.width-required@0",
        "st2110-20.a.fmtp.height-required@0",
        "st2110-20.a.fmtp.exactframerate-required@0",
        "st2110-20.a.fmtp.depth-required@0",
        "st2110-20.a.fmtp.colorimetry-required@0",
        "st2110-20.a.fmtp.PM-required@0",
        "st2110-20.a.fmtp.SSN-required@0",
        "st2110-20.a.fmtp.TP-required@0",
      } },
  ["examples/st2110/invalid/04_bad_tsrefclk_gmid.sdp"] =
    { error = "sdp.a.ts-refclk.ptp-malformed", line = 10,
      findings = { "sdp.a.ts-refclk.ptp-malformed@10" } },
  ["examples/st2110/invalid/05_missing_sampling.sdp"] =
    { error = "st2110-20.a.fmtp.sampling-required", line = 8,
      findings = { "st2110-20.a.fmtp.sampling-required@8" } },
  ["examples/st2110/invalid/06_bad_channel_order.sdp"] =
    { error = "st2110-30.a.fmtp.channel-order-invalid", line = 8,
      findings = { "st2110-30.a.fmtp.channel-order-invalid@8" } },
  ["examples/st2110/invalid/07_missing_smpte291_ssn.sdp"] =
    { error = "st2110-40.a.fmtp.ssn-required", line = 8,
      findings = { "st2110-40.a.fmtp.ssn-required@8" } },
  ["examples/st2110/invalid/08_missing_ssn.sdp"] =
    { error = "st2110-41.a.fmtp.SSN-required", line = 8,
      findings = { "st2110-41.a.fmtp.SSN-required@8" } },
  ["examples/st2110/invalid/09_bad_ptime.sdp"] =
    { error = "sdp.a.ptime.malformed", line = 10,
      findings = { "sdp.a.ptime.malformed@10" } },
  -- Demoted, the malformed fmtp is skipped, so the §7.2 parameters are
  -- reported missing.
  ["examples/st2110/invalid/10_fmtp_empty_entry.sdp"] =
    { error = "st2110-20.a.fmtp.malformed", line = 8,
      findings = {
        "st2110-20.a.fmtp.malformed@8",
        "st2110-20.a.fmtp.sampling-required@0",
        "st2110-20.a.fmtp.width-required@0",
        "st2110-20.a.fmtp.height-required@0",
        "st2110-20.a.fmtp.exactframerate-required@0",
        "st2110-20.a.fmtp.depth-required@0",
        "st2110-20.a.fmtp.colorimetry-required@0",
        "st2110-20.a.fmtp.PM-required@0",
        "st2110-20.a.fmtp.SSN-required@0",
        "st2110-20.a.fmtp.TP-required@0",
      } },
  ["examples/st2110/invalid/dup_group_type_mismatch.sdp"] =
    { error = "st2110-10.a.group-dup.media-type-same", line = 0,
      findings = {
        "st2110-10.a.group-dup.media-type-same@0",
        "st2110-10.a.group-dup.rtpmap-same@0",
        "st2110-10.a.group-dup.payload-type-same@0",
        "st2110-10.a.group-dup.fmtp-same@0",
      } },
  ["examples/ipmx/invalid/01_missing_ipmx_marker.sdp"] =
    { error = "tr-10-1.a.fmtp.measuredpixclk-required", line = 8,
      findings = {
        "tr-10-1.a.fmtp.measuredpixclk-required@8",
        "tr-10-1.a.fmtp.vtotal-required@8",
        "tr-10-1.a.fmtp.htotal-required@8",
        "tr-10-1.a.fmtp.marker-required@0",
      } },
  ["examples/ipmx/invalid/02_fails_st2110.sdp"] =
    { error = "tr-10-1.a.fmtp.measuredpixclk-required", line = 9,
      findings = {
        "tr-10-1.a.fmtp.measuredpixclk-required@9",
        "tr-10-1.a.fmtp.vtotal-required@9",
        "tr-10-1.a.fmtp.htotal-required@9",
        "tr-10-1.a.fmtp.marker-required@0",
        "st2110.attr.ts-refclk-required@0",
      } },
  ["examples/ipmx/invalid/dup_privacy_mismatch.sdp"] =
    { error = "tr-10-13.a.privacy.dup-legs-must-match", line = 0,
      findings = { "tr-10-13.a.privacy.dup-legs-must-match@0" } },
  ["examples/ipmx/invalid/rtcp_mux.sdp"] =
    { error = "tr-10-1.a.rtcp-mux.forbidden", line = 0,
      findings = { "tr-10-1.a.rtcp-mux.forbidden@0" } },
}

local DEMOTED = {}
for _, c in ipairs(sdp.checks()) do
  if c.default_severity == "error" then DEMOTED[c.id] = "warn" end
end

local TIERS = {
  { dir = "generic", mode = "sdp"    },
  { dir = "st2110",  mode = "st2110" },
  { dir = "ipmx",    mode = "ipmx"   },
}

describe("examples — EXPECTED covers exactly the invalid examples", function()
  -- NOT-SPEC: library
  it("has no entry for a file that does not exist", function()
    for path in pairs(EXPECTED) do
      assert(io.open(path, "rb"), "EXPECTED names a missing file: " .. path)
    end
  end)
end)

for _, tier in ipairs(TIERS) do
  describe("examples/" .. tier.dir .. " — verdicts match their directory", function()

    for _, path in ipairs(list_sdp_files("examples/" .. tier.dir .. "/valid")) do
      it(path .. " passes " .. tier.mode, function()
        local doc, err = sdp.parse(slurp(path), tier.mode)
        assert.is_truthy(doc, err and (err.id or err.message))
      end)
    end

    for _, path in ipairs(list_sdp_files("examples/" .. tier.dir .. "/invalid")) do
      it(path .. " fails " .. tier.mode .. " for its stated reason", function()
        local want = EXPECTED[path]
        assert(want, path .. " has no entry in EXPECTED")
        local text = slurp(path)
        local doc, err = sdp.parse(text, tier.mode)
        assert.is_nil(doc)
        assert.equal(want.error, err.id or err.code)
        assert.equal(want.line, err.line)
        local all = sdp.parse(text, tier.mode, { policy = DEMOTED })
        local got = {}
        for _, f in ipairs(all and all:findings() or {}) do
          got[#got + 1] = f.id .. "@" .. f.line
        end
        assert.same(want.findings or {}, got)
      end)
    end

  end)
end
