---@diagnostic disable
-- Phase 7.B: IPMX tier — TR-10-1 §10 baseline checks (FID prohibition +
-- IPMX fmtp marker).
--
-- Test ordering ([[test-ordering]]): topical by TR-10 part, then numerical
-- by section within. New IPMX checks (Phase 7.C+) slot into their TR-10
-- section, not appended at the file end.

local base   = require("parse_sdp.grammar.base")
local st2110 = require("parse_sdp.grammar.st2110")
local ipmx   = require("parse_sdp.grammar.ipmx")

-- ST 2110-10:2022 §8.2 + §8.3 require every RTP media block to carry
-- a=ts-refclk and a media-level a=mediaclk (Phase 6.D.A). Include both
-- in the build helpers so the ST 2110 tier doesn't reject IPMX fixtures
-- before the IPMX-tier check runs.
local TIMING_TS_REFCLK = "a=ts-refclk:localmac=00-11-22-33-44-55"
local TIMING_MEDIACLK  = "a=mediaclk:sender"

-- A complete IPMX-conformant raw-video fmtp containing every ST 2110-20:2022
-- §7.2 + §7.4.2 + ST 2110-21:2022 §8.1 required parameter, the TR-10-1
-- §10.2 params (measuredpixclk / vtotal / htotal — example values from
-- the §10.2 spec text, 1080p59.94), and the IPMX flag. Acceptance
-- fixtures use this so they don't trip ST 2110 / IPMX required-param
-- checks orthogonal to what they're testing.
local RAW_FMTP_IPMX_PT96 =
    "a=fmtp:96 sampling=YCbCr-4:2:2;width=1920;height=1080;"
 .. "exactframerate=60000/1001;depth=10;colorimetry=BT709;"
 .. "PM=2110GPM;SSN=ST2110-20:2022;TP=2110TPN;IPMX;"
 .. "measuredpixclk=148500000;vtotal=1125;htotal=2200"

-- Same fmtp without the IPMX flag — used by the §10.1 reject test.
local RAW_FMTP_NO_IPMX_PT96 =
    "a=fmtp:96 sampling=YCbCr-4:2:2;width=1920;height=1080;"
 .. "exactframerate=60000/1001;depth=10;colorimetry=BT709;"
 .. "PM=2110GPM;SSN=ST2110-20:2022;TP=2110TPN;"
 .. "measuredpixclk=148500000;vtotal=1125;htotal=2200"

local function lines_to_sdp(lines)
  return table.concat(lines, "\r\n") .. "\r\n"
end

-- A minimal IPMX-conformant video SDP: ST 2110-20 raw video at 90 kHz,
-- a=rtpmap + a=fmtp (with IPMX flag), required timing attributes, and
-- an a=mid:1 (so the helper can attach a session-level a=group that
-- references the media block without tripping RFC 5888 §6's "every
-- media block must carry an a=mid" requirement when a group is present).
local function build_video_sdp(opts)
  opts = opts or {}
  local fmtp_line = opts.fmtp_line or RAW_FMTP_IPMX_PT96
  local lines = {
    "v=0",
    "o=- 1 1 IN IP4 192.0.2.1",
    "s=Test",
    "t=0 0",
  }
  if opts.group_line then
    lines[#lines + 1] = opts.group_line
  end
  lines[#lines + 1] = "m=video 30000 RTP/AVP 96"
  lines[#lines + 1] = "c=IN IP4 239.0.0.1/64"
  lines[#lines + 1] = "a=mid:1"
  lines[#lines + 1] = "a=rtpmap:96 raw/90000"
  if fmtp_line then
    lines[#lines + 1] = fmtp_line
  end
  lines[#lines + 1] = TIMING_TS_REFCLK
  lines[#lines + 1] = TIMING_MEDIACLK
  return lines_to_sdp(lines)
end

local function finding_for(ctx, id)
  for _, f in ipairs(ctx.findings or {}) do
    if f.id == id then return f end
  end
  return nil
end

-- ── TR-10-1 §10 — FID prohibition (a=group:FID) ─────────────────────────────

describe("IPMX TR-10-1 §10 — a=group:FID forbidden", function()

  it("accepts a minimal IPMX-conformant video SDP (no a=group)", function()
    local doc = ipmx.match(build_video_sdp())
    assert.is_truthy(doc)
  end)

  it("accepts a=group:LS at session level (only FID is forbidden)", function()
    local doc = ipmx.match(build_video_sdp({ group_line = "a=group:LS 1" }))
    assert.is_truthy(doc)
  end)

  it("rejects a=group:FID at session level", function()
    local doc, ctx = ipmx.match(build_video_sdp({
      group_line = "a=group:FID 1",
    }))
    assert.is_nil(doc)
    local f = finding_for(ctx, "tr-10-1.a.group.fid-forbidden")
    assert.is_not_nil(f)
    assert.equal("session.attributes[group]", f.field_path)
  end)

  it("rejects a=group:FID with no tags", function()
    local doc, ctx = ipmx.match(build_video_sdp({
      group_line = "a=group:FID",
    }))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "tr-10-1.a.group.fid-forbidden"))
  end)

  -- NOT-SPEC: library — base / st2110 tiers MUST still accept a=group:FID,
  -- because the prohibition is IPMX-specific (TR-10-1 §10).
  it("base tier still accepts a=group:FID", function()
    assert.is_truthy(base.match(build_video_sdp({
      group_line = "a=group:FID 1",
    })))
  end)

  it("ST 2110 tier still accepts a=group:FID", function()
    assert.is_truthy(st2110.match(build_video_sdp({
      group_line = "a=group:FID 1",
    })))
  end)
end)

-- ── TR-10-1 §10.1 — required 'IPMX' declaration in a=fmtp ──────────────────

describe("IPMX TR-10-1 §10.1 — a=fmtp must contain 'IPMX' on RTP blocks", function()

  it("accepts an RTP block whose a=fmtp contains the IPMX flag", function()
    local doc = ipmx.match(build_video_sdp())  -- default fmtp has IPMX
    assert.is_truthy(doc)
  end)

  it("rejects an RTP block whose a=fmtp omits the IPMX flag", function()
    local doc, ctx = ipmx.match(build_video_sdp({
      fmtp_line = RAW_FMTP_NO_IPMX_PT96,
    }))
    assert.is_nil(doc)
    local f = finding_for(ctx, "tr-10-1.a.fmtp.marker-required")
    assert.is_not_nil(f)
    -- Block-level field_path: TR-10-1 §10.1 SHALL is satisfied as long
    -- as at least one a=fmtp on the block carries IPMX, so the finding
    -- is reported per-block (no `:pt=N` suffix).
    assert.equal("media[0].attributes[fmtp]", f.field_path)
  end)

  -- Parity with the 1.0 IPMX validator: absent a=fmtp is not caught by
  -- §10.1 directly. The ST 2110 raw video required-param check would
  -- catch it first; if the encoding had no per-essence fmtp SHALL,
  -- the marker check is silently skipped. Strict reading of §10.1
  -- (which would also reject "no fmtp at all" on every RTP block)
  -- is deferred to an audit-folder follow-up.
  it("does not fire when no a=fmtp is present on a static-PT RTP block", function()
    -- Static PT 0 (PCMU/8000) — no rtpmap, no fmtp required by ST 2110
    -- tier. IPMX §10.1 marker check should be a no-op here under parity.
    local sdp = lines_to_sdp({
      "v=0",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=Test",
      "t=0 0",
      "m=audio 30000 RTP/AVP 0",
      "c=IN IP4 239.0.0.1/64",
      TIMING_TS_REFCLK,
      TIMING_MEDIACLK,
    })
    local doc = ipmx.match(sdp)
    assert.is_truthy(doc)
  end)

  it("does not fire on a non-RTP application block (USB TR-10-14 shape)", function()
    -- m=application TCP usb is a non-RTP block under IPMX. The IPMX
    -- fmtp marker SHALL applies only to RTP blocks.
    local sdp = lines_to_sdp({
      "v=0",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=Test",
      "t=0 0",
      "m=application 30000 TCP usb",
      "c=IN IP4 192.0.2.2",
      "a=fmtp:usb dummy",  -- no IPMX flag; should be ignored
    })
    -- The IPMX-tier check itself should not flag this; other tiers may
    -- still reject for other reasons, so allow either pass-through or
    -- a finding from an unrelated id.
    local doc, ctx = ipmx.match(sdp)
    if doc == nil then
      assert.is_nil(finding_for(ctx, "tr-10-1.a.fmtp.marker-required"))
    else
      assert.is_truthy(doc)
    end
  end)

  -- NOT-SPEC: library — the marker requirement is IPMX-specific. Both
  -- lower tiers must still accept an RTP block whose a=fmtp lacks IPMX.
  it("ST 2110 tier still accepts an RTP block whose fmtp lacks IPMX", function()
    assert.is_truthy(st2110.match(build_video_sdp({
      fmtp_line = RAW_FMTP_NO_IPMX_PT96,
    })))
  end)
end)

-- ── TR-10-1 §10.2 + TR-10-9 §10 — video IPMX fmtp required params ──────────

-- Build a raw-video fmtp line missing one of the §10.2 keys (or with a
-- bad value). Reuses the rest of the IPMX-conformant fmtp so only the
-- targeted key is the cause of failure.
local function raw_fmtp_with_overrides(overrides)
  local pairs_list = {
    { "sampling",       "YCbCr-4:2:2"   },
    { "width",          "1920"          },
    { "height",         "1080"          },
    { "exactframerate", "60000/1001"    },
    { "depth",          "10"            },
    { "colorimetry",    "BT709"         },
    { "PM",             "2110GPM"       },
    { "SSN",            "ST2110-20:2022"},
    { "TP",             "2110TPN"       },
    { "measuredpixclk", "148500000"     },
    { "vtotal",         "1125"          },
    { "htotal",         "2200"          },
  }
  local parts = {}
  for _, kv in ipairs(pairs_list) do
    local k, v = kv[1], kv[2]
    if overrides[k] == false then
      -- skip (omit)
    elseif overrides[k] ~= nil then
      parts[#parts + 1] = k .. "=" .. tostring(overrides[k])
    else
      parts[#parts + 1] = k .. "=" .. v
    end
  end
  parts[#parts + 1] = "IPMX"
  return "a=fmtp:96 " .. table.concat(parts, ";")
end

describe("IPMX TR-10-1 §10.2 — video fmtp required params (raw)", function()

  for _, key in ipairs({ "measuredpixclk", "vtotal", "htotal" }) do
    it("rejects raw video fmtp missing '" .. key .. "'", function()
      local doc, ctx = ipmx.match(build_video_sdp({
        fmtp_line = raw_fmtp_with_overrides({ [key] = false }),
      }))
      assert.is_nil(doc)
      local f = finding_for(ctx, "tr-10-1.a.fmtp." .. key .. "-required")
      assert.is_not_nil(f)
      assert.equal("media[0].attributes[fmtp:pt=96]", f.field_path)
    end)
  end

  it("accepts raw video fmtp with all three §10.2 params present", function()
    local doc = ipmx.match(build_video_sdp())   -- default fixture
    assert.is_truthy(doc)
  end)
end)

describe("IPMX TR-10-1 §10.2 — video fmtp value forms (raw)", function()

  -- Per the spec: measuredpixclk = positive integer Hz, vtotal / htotal =
  -- positive integers. POS-DIGIT *DIGIT — leading zeros, signs, decimals,
  -- and non-numeric tokens all reject.
  for _, case in ipairs({
    { key = "measuredpixclk", value = "0",            label = "zero"           },
    { key = "measuredpixclk", value = "-148500000",   label = "negative"       },
    { key = "measuredpixclk", value = "148.5",        label = "decimal"        },
    { key = "measuredpixclk", value = "1.485e8",      label = "scientific"     },
    { key = "measuredpixclk", value = "abc",          label = "non-numeric"    },
    { key = "vtotal",         value = "0",            label = "zero"           },
    { key = "vtotal",         value = "01125",        label = "leading-zero"   },
    { key = "vtotal",         value = "-1125",        label = "negative"       },
    { key = "htotal",         value = "0",            label = "zero"           },
    { key = "htotal",         value = "2200.0",       label = "decimal"        },
  }) do
    it(string.format("rejects %s=%s (%s)", case.key, case.value, case.label), function()
      local doc, ctx = ipmx.match(build_video_sdp({
        fmtp_line = raw_fmtp_with_overrides({ [case.key] = case.value }),
      }))
      assert.is_nil(doc)
      local f = finding_for(ctx, "tr-10-1.a.fmtp." .. case.key .. "-invalid-value")
      assert.is_not_nil(f)
    end)
  end

  -- NOT-SPEC: library — value-form checks are IPMX-specific; ST 2110 tier
  -- doesn't know about measuredpixclk / vtotal / htotal and must accept
  -- any string value the params parser admits.
  it("ST 2110 tier accepts measuredpixclk=abc (out of scope for st2110)", function()
    assert.is_truthy(st2110.match(build_video_sdp({
      fmtp_line = raw_fmtp_with_overrides({ measuredpixclk = "abc" }),
    })))
  end)
end)

describe("IPMX TR-10-1 §10.2 — TR-10-11 jxsv inheritance", function()

  -- TR-10-11 §7 inherits TR-10-1 by reference, so the same required-
  -- param SHALL applies to compressed video. Build a minimal jxsv SDP
  -- and verify the IPMX dispatch also fires for jxsv encoding. Also
  -- carries b=AS:<kbps> per TR-10-7 §11 / ST 2110-22:2022 §7.3 (added
  -- in Phase 7.F).
  local function build_jxsv_sdp(fmtp_line)
    return lines_to_sdp({
      "v=0",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=Test",
      "t=0 0",
      "m=video 30000 RTP/AVP 96",
      "c=IN IP4 239.0.0.1/64",
      "b=AS:1500000",
      "a=mid:1",
      "a=rtpmap:96 jxsv/90000",
      fmtp_line,
      TIMING_TS_REFCLK,
      TIMING_MEDIACLK,
    })
  end

  local JXSV_FMTP_BASE =
      "width=1920;height=1080;TP=2110TPN;packetmode=0;IPMX"

  it("rejects jxsv fmtp missing measuredpixclk", function()
    local doc, ctx = ipmx.match(build_jxsv_sdp(
      "a=fmtp:96 " .. JXSV_FMTP_BASE .. ";vtotal=1125;htotal=2200"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "tr-10-1.a.fmtp.measuredpixclk-required"))
  end)

  it("accepts jxsv fmtp with all three §10.2 params present", function()
    local doc = ipmx.match(build_jxsv_sdp(
      "a=fmtp:96 " .. JXSV_FMTP_BASE
       .. ";measuredpixclk=148500000;vtotal=1125;htotal=2200"))
    assert.is_truthy(doc)
  end)
end)

-- A minimal IPMX-conformant audio SDP fixture (L24 stereo at 48 kHz)
-- with all required IPMX fmtp params present — used as a baseline for
-- §10.2 cross-encoding scope tests and as the foundation for §10.3
-- audio tests below.
local function build_audio_sdp(opts)
  opts = opts or {}
  local fmtp_line = opts.fmtp_line
     or "a=fmtp:97 channel-order=SMPTE2110.(ST);IPMX;measuredsamplerate=48000"
  return lines_to_sdp({
    "v=0",
    "o=- 1 1 IN IP4 192.0.2.1",
    "s=Test",
    "t=0 0",
    "m=audio 30000 RTP/AVP 97",
    "c=IN IP4 239.0.0.1/64",
    "a=mid:1",
    "a=rtpmap:97 L24/48000/2",
    fmtp_line,
    "a=ptime:1",
    TIMING_TS_REFCLK,
    TIMING_MEDIACLK,
  })
end

describe("IPMX TR-10-1 §10.2 — does not fire on non-video encodings", function()

  -- §10.2 is video-specific. Audio (L24) fmtps must not trip the
  -- measuredpixclk/vtotal/htotal-required checks regardless of the
  -- audio-side §10.3 state.
  it("does not fire on audio L24 fmtp", function()
    local doc, ctx = ipmx.match(build_audio_sdp())
    assert.is_truthy(doc)
    for _, key in ipairs({ "measuredpixclk", "vtotal", "htotal" }) do
      assert.is_nil(finding_for(ctx or {},
        "tr-10-1.a.fmtp." .. key .. "-required"))
    end
  end)
end)

-- ── TR-10-1 §10.3 + TR-10-9 §10 — audio IPMX fmtp measuredsamplerate ──────

describe("IPMX TR-10-1 §10.3 — audio fmtp measuredsamplerate (L16/L24)", function()

  it("accepts audio fmtp with measuredsamplerate present", function()
    local doc = ipmx.match(build_audio_sdp())   -- default has it
    assert.is_truthy(doc)
  end)

  it("rejects L24 audio fmtp missing measuredsamplerate", function()
    local doc, ctx = ipmx.match(build_audio_sdp({
      fmtp_line = "a=fmtp:97 channel-order=SMPTE2110.(ST);IPMX",
    }))
    assert.is_nil(doc)
    local f = finding_for(ctx, "tr-10-1.a.fmtp.measuredsamplerate-required")
    assert.is_not_nil(f)
    assert.equal("media[0].attributes[fmtp:pt=97]", f.field_path)
  end)

  for _, case in ipairs({
    { value = "0",         label = "zero"         },
    { value = "-48000",    label = "negative"     },
    { value = "48000.0",   label = "decimal"      },
    { value = "4.8e4",     label = "scientific"   },
    { value = "abc",       label = "non-numeric"  },
    { value = "048000",    label = "leading-zero" },
  }) do
    it(string.format("rejects measuredsamplerate=%s (%s)",
                     case.value, case.label), function()
      local doc, ctx = ipmx.match(build_audio_sdp({
        fmtp_line = "a=fmtp:97 channel-order=SMPTE2110.(ST);"
                 .. "IPMX;measuredsamplerate=" .. case.value,
      }))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "tr-10-1.a.fmtp.measuredsamplerate-invalid-value"))
    end)
  end

  -- AM824 (TR-10-12 §7) inherits TR-10-1 §10.3 the same way L16/L24 do.
  it("fires on AM824 audio fmtp missing measuredsamplerate", function()
    local sdp = lines_to_sdp({
      "v=0",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=Test",
      "t=0 0",
      "m=audio 30000 RTP/AVP 97",
      "c=IN IP4 239.0.0.1/64",
      "a=mid:1",
      "a=rtpmap:97 AM824/48000/2",
      "a=fmtp:97 channel-order=SMPTE2110.(ST);IPMX",
      "a=ptime:1",
      TIMING_TS_REFCLK,
      TIMING_MEDIACLK,
    })
    local doc, ctx = ipmx.match(sdp)
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "tr-10-1.a.fmtp.measuredsamplerate-required"))
  end)

  -- NOT-SPEC: library — ST 2110 tier doesn't know about
  -- measuredsamplerate and must still accept audio fmtps that omit it.
  it("ST 2110 tier still accepts audio fmtp without measuredsamplerate", function()
    assert.is_truthy(st2110.match(build_audio_sdp({
      fmtp_line = "a=fmtp:97 channel-order=SMPTE2110.(ST);IPMX",
    })))
  end)
end)

-- ── TR-10-2 §7 / TR-10-3 §7 / TR-10-4 §7 / TR-10-11 §7 / TR-10-12 §7 ─────
-- RTP UDP destination port must be even AND > 1024.

describe("IPMX TR-10-2 §7 — RTP port must be > 1024 and even", function()

  -- Use the IPMX-conformant video SDP fixture; vary the m= port only.
  local function build_with_port(port)
    local lines = {
      "v=0",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=Test",
      "t=0 0",
      string.format("m=video %d RTP/AVP 96", port),
      "c=IN IP4 239.0.0.1/64",
      "a=mid:1",
      "a=rtpmap:96 raw/90000",
      RAW_FMTP_IPMX_PT96,
      TIMING_TS_REFCLK,
      TIMING_MEDIACLK,
    }
    return lines_to_sdp(lines)
  end

  it("accepts a port that is even and > 1024", function()
    assert.is_truthy(ipmx.match(build_with_port(30000)))
  end)

  it("accepts the boundary port 1026", function()
    assert.is_truthy(ipmx.match(build_with_port(1026)))
  end)

  it("rejects port 1024 (not > 1024)", function()
    local doc, ctx = ipmx.match(build_with_port(1024))
    assert.is_nil(doc)
    local f = finding_for(ctx, "ipmx.m.port-must-exceed-1024")
    assert.is_not_nil(f)
    assert.equal("media[0].port", f.field_path)
  end)

  it("rejects port 1023 (not > 1024)", function()
    local doc, ctx = ipmx.match(build_with_port(1023))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "ipmx.m.port-must-exceed-1024"))
  end)

  it("rejects port 30001 (odd)", function()
    local doc, ctx = ipmx.match(build_with_port(30001))
    assert.is_nil(doc)
    local f = finding_for(ctx, "ipmx.m.port-must-be-even")
    assert.is_not_nil(f)
    assert.equal("media[0].port", f.field_path)
  end)

  -- NOT-SPEC: library — port constraint is IPMX-specific. Lower tiers
  -- must still accept odd / low-numbered ports.
  it("ST 2110 tier still accepts an odd port", function()
    assert.is_truthy(st2110.match(build_with_port(30001)))
  end)

  it("ST 2110 tier still accepts port 1024", function()
    assert.is_truthy(st2110.match(build_with_port(1024)))
  end)

  it("does not fire on non-RTP USB transport blocks", function()
    -- m=application TCP usb under TR-10-14 is a non-RTP block; the
    -- §7 RTP port constraint does not apply.
    local sdp = lines_to_sdp({
      "v=0",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=Test",
      "t=0 0",
      "m=application 1023 TCP usb",
      "c=IN IP4 192.0.2.2",
    })
    local doc, ctx = ipmx.match(sdp)
    if ctx then
      assert.is_nil(finding_for(ctx, "ipmx.m.port-must-exceed-1024"))
      assert.is_nil(finding_for(ctx, "ipmx.m.port-must-be-even"))
    end
    -- The block may pass or fail for unrelated reasons (USB setup,
    -- etc.); we only assert the IPMX port findings don't appear.
    if doc == nil then return end
    assert.is_truthy(doc)
  end)
end)

-- (ST 2110-22 §7.3 jxsv b=AS-required tests live in
-- spec/grammar_st2110_spec.lua next to other ST 2110-22 jxsv tests;
-- the IPMX tier inherits the check via composition.)

-- ── TR-10-10 §8 — a=infoframe attribute (HDMI InfoFrame signaling) ────────

describe("IPMX TR-10-10 §8 — a=infoframe attribute", function()

  -- Build an IPMX-conformant video SDP carrying an optional
  -- session-level a=infoframe line and an optional media-level
  -- a=infoframe line. Media port = 30000 so a session-level
  -- infoframe:30003 matches the +3 cross-section SHALL.
  local function build_video_with_infoframe(opts)
    opts = opts or {}
    local lines = {
      "v=0",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=Test",
      "t=0 0",
    }
    for _, l in ipairs(opts.session_lines or {}) do
      lines[#lines + 1] = l
    end
    lines[#lines + 1] = "m=video 30000 RTP/AVP 96"
    lines[#lines + 1] = "c=IN IP4 239.0.0.1/64"
    lines[#lines + 1] = "a=mid:1"
    lines[#lines + 1] = "a=rtpmap:96 raw/90000"
    lines[#lines + 1] = RAW_FMTP_IPMX_PT96
    for _, l in ipairs(opts.media_lines or {}) do
      lines[#lines + 1] = l
    end
    lines[#lines + 1] = TIMING_TS_REFCLK
    lines[#lines + 1] = TIMING_MEDIACLK
    return lines_to_sdp(lines)
  end

  it("accepts SDP with no a=infoframe (presence is conditional on HDMI)", function()
    assert.is_truthy(ipmx.match(build_video_with_infoframe()))
  end)

  it("accepts a well-formed session-level a=infoframe matching media+3", function()
    local doc = ipmx.match(build_video_with_infoframe({
      session_lines = { "a=infoframe:30003 SSN=ST2110-41:2024;DIT=100100" },
    }))
    assert.is_truthy(doc)
  end)

  it("decomposes a=infoframe into name / port / ssn / dit fields", function()
    local doc = ipmx.match(build_video_with_infoframe({
      session_lines = { "a=infoframe:30003 SSN=ST2110-41:2024;DIT=100100" },
    }))
    assert.is_truthy(doc)
    local attr
    for _, a in ipairs(doc.session.attributes) do
      if a.name == "infoframe" then attr = a; break end
    end
    assert.is_not_nil(attr)
    assert.equal(30003,             attr.port)
    assert.equal("ST2110-41:2024",  attr.ssn)
    assert.equal("100100",          attr.dit)
  end)

  it("rejects a=infoframe at media level", function()
    local doc, ctx = ipmx.match(build_video_with_infoframe({
      media_lines = { "a=infoframe:30003 SSN=ST2110-41:2024;DIT=100100" },
    }))
    assert.is_nil(doc)
    local f = finding_for(ctx, "tr-10-10.a.infoframe.must-be-session-level")
    assert.is_not_nil(f)
    assert.equal("media[0].attributes[infoframe]", f.field_path)
  end)

  it("rejects malformed SSN (not 'ST2110-41:<year>')", function()
    local doc, ctx = ipmx.match(build_video_with_infoframe({
      session_lines = { "a=infoframe:30003 SSN=WRONG:2024;DIT=100100" },
    }))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "tr-10-10.a.infoframe.ssn-invalid-form"))
  end)

  it("rejects SSN with non-digit year", function()
    local doc, ctx = ipmx.match(build_video_with_infoframe({
      session_lines = { "a=infoframe:30003 SSN=ST2110-41:abc;DIT=100100" },
    }))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "tr-10-10.a.infoframe.ssn-invalid-form"))
  end)

  it("rejects DIT other than 100100", function()
    local doc, ctx = ipmx.match(build_video_with_infoframe({
      session_lines = { "a=infoframe:30003 SSN=ST2110-41:2024;DIT=100101" },
    }))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "tr-10-10.a.infoframe.dit-invalid-value"))
  end)

  it("rejects a=infoframe whose port doesn't match any media port + 3", function()
    -- media port = 30000 → +3 = 30003; 40000 is unrelated
    local doc, ctx = ipmx.match(build_video_with_infoframe({
      session_lines = { "a=infoframe:40000 SSN=ST2110-41:2024;DIT=100100" },
    }))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "tr-10-10.a.infoframe.port-must-match-media-plus-3"))
  end)

  it("rejects duplicate session-level a=infoframe ports", function()
    -- Two media blocks (ports 30000 and 30010, +3 = 30003 / 30013) but
    -- both a=infoframe lines target the same port (30003).
    local sdp = lines_to_sdp({
      "v=0",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=Test",
      "t=0 0",
      "a=infoframe:30003 SSN=ST2110-41:2024;DIT=100100",
      "a=infoframe:30003 SSN=ST2110-41:2024;DIT=100100",
      "m=video 30000 RTP/AVP 96",
      "c=IN IP4 239.0.0.1/64",
      "a=mid:1",
      "a=rtpmap:96 raw/90000",
      RAW_FMTP_IPMX_PT96,
      TIMING_TS_REFCLK,
      TIMING_MEDIACLK,
      "m=video 30010 RTP/AVP 96",
      "c=IN IP4 239.0.0.1/64",
      "a=mid:2",
      "a=rtpmap:96 raw/90000",
      RAW_FMTP_IPMX_PT96,
      TIMING_TS_REFCLK,
      TIMING_MEDIACLK,
    })
    local doc, ctx = ipmx.match(sdp)
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "tr-10-10.a.infoframe.duplicate-port"))
  end)

  -- NOT-SPEC: library — a=infoframe is IPMX-specific (TR-10-10). The
  -- base and ST 2110 tiers must accept it as a generic attribute.
  it("base / ST 2110 tiers accept a=infoframe as a generic attribute", function()
    local sdp = build_video_with_infoframe({
      session_lines = { "a=infoframe:30003 SSN=ST2110-41:2024;DIT=100100" },
    })
    assert.is_truthy(base.match(sdp))
    assert.is_truthy(st2110.match(sdp))
  end)
end)

-- ── TR-10-5 §10 — a=hkep attribute (HDCP Key Exchange Protocol) ────────────

describe("IPMX TR-10-5 §10 — a=hkep attribute", function()

  -- Spec example: a=hkep:6001 IN IP4 192.0.2.10
  --                       6b2a8d4f-1234-5678-9abc-def0123456ab
  --                       01-02-03-04-05
  local WELL_FORMED_HKEP =
      "a=hkep:6001 IN IP4 192.0.2.10"
   .. " 6b2a8d4f-1234-5678-9abc-def0123456ab"
   .. " 01-02-03-04-05"

  local function build_with_hkep(opts)
    opts = opts or {}
    local lines = {
      "v=0",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=Test",
      "t=0 0",
    }
    for _, l in ipairs(opts.session_lines or {}) do
      lines[#lines + 1] = l
    end
    lines[#lines + 1] = "m=video 30000 RTP/AVP 96"
    lines[#lines + 1] = "c=IN IP4 239.0.0.1/64"
    lines[#lines + 1] = "a=mid:1"
    lines[#lines + 1] = "a=rtpmap:96 raw/90000"
    lines[#lines + 1] = RAW_FMTP_IPMX_PT96
    for _, l in ipairs(opts.media_lines or {}) do
      lines[#lines + 1] = l
    end
    lines[#lines + 1] = TIMING_TS_REFCLK
    lines[#lines + 1] = TIMING_MEDIACLK
    return lines_to_sdp(lines)
  end

  it("accepts a well-formed session-level a=hkep", function()
    assert.is_truthy(ipmx.match(build_with_hkep({
      session_lines = { WELL_FORMED_HKEP },
    })))
  end)

  it("accepts a well-formed media-level a=hkep", function()
    -- TR-10-5 §17 permits session, media, or both. Verify media-level
    -- form passes.
    assert.is_truthy(ipmx.match(build_with_hkep({
      media_lines = { WELL_FORMED_HKEP },
    })))
  end)

  it("accepts multiple session-level a=hkep lines", function()
    -- TR-10-5 §10 row 131: "may contain multiple 'hkep' session
    -- attributes, listed in order of preference"
    assert.is_truthy(ipmx.match(build_with_hkep({
      session_lines = {
        WELL_FORMED_HKEP,
        "a=hkep:6002 IN IP6 2001:db8::1"
            .. " 11111111-2222-3333-4444-555555555555"
            .. " aa-bb-cc-dd-ee",
      },
    })))
  end)

  it("decomposes a=hkep into port / nettype / addrtype / addr / node_id / port_id", function()
    local doc = ipmx.match(build_with_hkep({
      session_lines = { WELL_FORMED_HKEP },
    }))
    assert.is_truthy(doc)
    local attr
    for _, a in ipairs(doc.session.attributes) do
      if a.name == "hkep" then attr = a; break end
    end
    assert.is_not_nil(attr)
    assert.equal(6001,                                    attr.port)
    assert.equal("IN",                                    attr.nettype)
    assert.equal("IP4",                                   attr.addrtype)
    assert.equal("192.0.2.10",                            attr.addr)
    assert.equal("6b2a8d4f-1234-5678-9abc-def0123456ab",  attr.node_id)
    assert.equal("01-02-03-04-05",                        attr.port_id)
  end)

  it("rejects nettype != 'IN'", function()
    local doc, ctx = ipmx.match(build_with_hkep({
      session_lines = {
        "a=hkep:6001 OUT IP4 192.0.2.10"
          .. " 6b2a8d4f-1234-5678-9abc-def0123456ab"
          .. " 01-02-03-04-05",
      },
    }))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "tr-10-5.a.hkep.nettype-invalid-value"))
  end)

  it("rejects addrtype other than IP4 / IP6", function()
    local doc, ctx = ipmx.match(build_with_hkep({
      session_lines = {
        "a=hkep:6001 IN IP5 192.0.2.10"
          .. " 6b2a8d4f-1234-5678-9abc-def0123456ab"
          .. " 01-02-03-04-05",
      },
    }))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "tr-10-5.a.hkep.addrtype-invalid-value"))
  end)

  it("rejects malformed node-id (wrong group lengths)", function()
    local doc, ctx = ipmx.match(build_with_hkep({
      session_lines = {
        "a=hkep:6001 IN IP4 192.0.2.10"
          .. " 6b2a8d4f-1234-5678-9abc-def012345"  -- last group too short
          .. " 01-02-03-04-05",
      },
    }))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "tr-10-5.a.hkep.node-id-invalid-form"))
  end)

  it("rejects malformed node-id (non-hex chars)", function()
    local doc, ctx = ipmx.match(build_with_hkep({
      session_lines = {
        "a=hkep:6001 IN IP4 192.0.2.10"
          .. " ZZZZZZZZ-1234-5678-9abc-def0123456ab"
          .. " 01-02-03-04-05",
      },
    }))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "tr-10-5.a.hkep.node-id-invalid-form"))
  end)

  it("rejects malformed port-id (wrong group count)", function()
    local doc, ctx = ipmx.match(build_with_hkep({
      session_lines = {
        "a=hkep:6001 IN IP4 192.0.2.10"
          .. " 6b2a8d4f-1234-5678-9abc-def0123456ab"
          .. " 01-02-03-04",  -- 4 groups, not 5
      },
    }))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "tr-10-5.a.hkep.port-id-invalid-form"))
  end)

  it("rejects malformed port-id (group size != 2)", function()
    local doc, ctx = ipmx.match(build_with_hkep({
      session_lines = {
        "a=hkep:6001 IN IP4 192.0.2.10"
          .. " 6b2a8d4f-1234-5678-9abc-def0123456ab"
          .. " 1-02-03-04-05",  -- first group single hex
      },
    }))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "tr-10-5.a.hkep.port-id-invalid-form"))
  end)

  -- NOT-SPEC: library — a=hkep is IPMX-specific. Lower tiers accept it
  -- as a generic attribute regardless of form.
  it("base / ST 2110 tiers accept a=hkep as a generic attribute", function()
    local sdp = build_with_hkep({
      session_lines = {
        "a=hkep:6001 OUT BOGUS 192.0.2.10 ZZ ??",
      },
    })
    assert.is_truthy(base.match(sdp))
    assert.is_truthy(st2110.match(sdp))
  end)
end)

-- ── TR-10-6 §7.6 — FECPROFILE / FEC_ADD_LATENCY_* fmtp parameters ─────────

describe("IPMX TR-10-6 §7.6 — FEC parameters in a=fmtp", function()

  -- Build a video SDP with a custom fmtp tail (after the §10.2 keys).
  -- The default RAW_FMTP_IPMX_PT96 carries every required-param so we
  -- only need to append optional FEC params.
  local function video_with_fmtp_extras(extras)
    local lines = {
      "v=0",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=Test",
      "t=0 0",
      "m=video 30000 RTP/AVP 96",
      "c=IN IP4 239.0.0.1/64",
      "a=mid:1",
      "a=rtpmap:96 raw/90000",
      RAW_FMTP_IPMX_PT96 .. ";" .. extras,
      TIMING_TS_REFCLK,
      TIMING_MEDIACLK,
    }
    return lines_to_sdp(lines)
  end

  it("accepts an fmtp with FECPROFILE=profile-a alone", function()
    assert.is_truthy(ipmx.match(video_with_fmtp_extras("FECPROFILE=profile-a")))
  end)

  it("accepts FECPROFILE=profile-a with FEC_ADD_LATENCY_VIDEO=100", function()
    assert.is_truthy(ipmx.match(video_with_fmtp_extras(
      "FECPROFILE=profile-a;FEC_ADD_LATENCY_VIDEO=100")))
  end)

  it("accepts FEC_ADD_LATENCY_*=0 (non-negative includes zero)", function()
    assert.is_truthy(ipmx.match(video_with_fmtp_extras(
      "FECPROFILE=profile-a;FEC_ADD_LATENCY_VIDEO=0;FEC_ADD_LATENCY_AUDIO=0")))
  end)

  it("rejects FECPROFILE with a value other than 'profile-a'", function()
    local doc, ctx = ipmx.match(video_with_fmtp_extras("FECPROFILE=profile-b"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "tr-10-6.a.fmtp.fecprofile-invalid-value"))
  end)

  it("rejects FEC_ADD_LATENCY_VIDEO without FECPROFILE", function()
    local doc, ctx = ipmx.match(video_with_fmtp_extras("FEC_ADD_LATENCY_VIDEO=100"))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "tr-10-6.a.fmtp.fec-add-latency-video-requires-fecprofile"))
  end)

  it("rejects FEC_ADD_LATENCY_AUDIO without FECPROFILE", function()
    -- Use an audio block — FEC_ADD_LATENCY_AUDIO is the audio-specific
    -- counterpart but the requires-fecprofile rule is encoding-agnostic.
    local sdp = lines_to_sdp({
      "v=0",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=Test",
      "t=0 0",
      "m=audio 30000 RTP/AVP 97",
      "c=IN IP4 239.0.0.1/64",
      "a=mid:1",
      "a=rtpmap:97 L24/48000/2",
      "a=fmtp:97 channel-order=SMPTE2110.(ST);IPMX;"
        .. "measuredsamplerate=48000;FEC_ADD_LATENCY_AUDIO=100",
      "a=ptime:1",
      TIMING_TS_REFCLK,
      TIMING_MEDIACLK,
    })
    local doc, ctx = ipmx.match(sdp)
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "tr-10-6.a.fmtp.fec-add-latency-audio-requires-fecprofile"))
  end)

  for _, case in ipairs({
    { value = "-100",   label = "negative"          },
    { value = "100.5",  label = "decimal"           },
    { value = "1e3",    label = "scientific"        },
    { value = "abc",    label = "non-numeric"       },
    { value = "0100",   label = "leading-zero"      },
  }) do
    it(string.format("rejects FEC_ADD_LATENCY_VIDEO=%s (%s)",
                     case.value, case.label), function()
      local doc, ctx = ipmx.match(video_with_fmtp_extras(
        "FECPROFILE=profile-a;FEC_ADD_LATENCY_VIDEO=" .. case.value))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "tr-10-6.a.fmtp.fec-add-latency-video-invalid-value"))
    end)
  end

  -- NOT-SPEC: library — FEC param SHALLs are IPMX-specific (TR-10-6
  -- §7.6). The ST 2110 tier accepts any fmtp param values.
  it("ST 2110 tier still accepts FECPROFILE=profile-bogus", function()
    assert.is_truthy(st2110.match(video_with_fmtp_extras("FECPROFILE=profile-bogus")))
  end)
end)

-- ── TR-10-13 §13 — a=privacy attribute (PEP signaling) ────────────────────

describe("IPMX TR-10-13 §13 — a=privacy attribute", function()

  -- A well-formed example carrying all 6 required params with valid
  -- hex lengths (16/32/8/16 chars) and a known mode value.
  local WELL_FORMED_PRIVACY =
      "a=privacy: protocol=RTP; mode=AES-128-CTR;"
   .. " iv=0123456789abcdef;"
   .. " key_generator=0123456789abcdef0123456789abcdef;"
   .. " key_version=00112233;"
   .. " key_id=fedcba9876543210"

  local function build_with_privacy(opts)
    opts = opts or {}
    local lines = {
      "v=0",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=Test",
      "t=0 0",
    }
    for _, l in ipairs(opts.session_lines or {}) do
      lines[#lines + 1] = l
    end
    lines[#lines + 1] = "m=video 30000 RTP/AVP 96"
    lines[#lines + 1] = "c=IN IP4 239.0.0.1/64"
    lines[#lines + 1] = "a=mid:1"
    lines[#lines + 1] = "a=rtpmap:96 raw/90000"
    lines[#lines + 1] = RAW_FMTP_IPMX_PT96
    for _, l in ipairs(opts.media_lines or {}) do
      lines[#lines + 1] = l
    end
    lines[#lines + 1] = TIMING_TS_REFCLK
    lines[#lines + 1] = TIMING_MEDIACLK
    return lines_to_sdp(lines)
  end

  it("accepts a well-formed session-level a=privacy", function()
    assert.is_truthy(ipmx.match(build_with_privacy({
      session_lines = { WELL_FORMED_PRIVACY },
    })))
  end)

  it("accepts a well-formed media-level a=privacy", function()
    assert.is_truthy(ipmx.match(build_with_privacy({
      media_lines = { WELL_FORMED_PRIVACY },
    })))
  end)

  it("decomposes a=privacy into name + params list", function()
    local doc = ipmx.match(build_with_privacy({
      session_lines = { WELL_FORMED_PRIVACY },
    }))
    assert.is_truthy(doc)
    local attr
    for _, a in ipairs(doc.session.attributes) do
      if a.name == "privacy" then attr = a; break end
    end
    assert.is_not_nil(attr)
    assert.is_table(attr.params)
    -- Build a kv lookup for assertion stability across iteration order
    local kv = {}
    for _, e in ipairs(attr.params) do kv[e[1]] = e[2] end
    assert.equal("RTP",                                kv.protocol)
    assert.equal("AES-128-CTR",                        kv.mode)
    assert.equal("0123456789abcdef",                   kv.iv)
    assert.equal("0123456789abcdef0123456789abcdef",   kv.key_generator)
    assert.equal("00112233",                           kv.key_version)
    assert.equal("fedcba9876543210",                   kv.key_id)
  end)

  it("rejects trailing semicolon after the last parameter", function()
    local bad =
        "a=privacy: protocol=RTP; mode=AES-128-CTR;"
     .. " iv=0123456789abcdef;"
     .. " key_generator=0123456789abcdef0123456789abcdef;"
     .. " key_version=00112233;"
     .. " key_id=fedcba9876543210;"  -- trailing ;
    local doc, ctx = ipmx.match(build_with_privacy({ session_lines = { bad } }))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "tr-10-13.a.privacy.trailing-semicolon"))
  end)

  for _, key in ipairs({
    "protocol", "mode", "iv", "key_generator", "key_version", "key_id",
  }) do
    it("rejects a=privacy missing '" .. key .. "'", function()
      -- Reconstruct WELL_FORMED_PRIVACY minus the target key.
      local parts = {
        { "protocol",      "RTP"                                 },
        { "mode",          "AES-128-CTR"                         },
        { "iv",            "0123456789abcdef"                    },
        { "key_generator", "0123456789abcdef0123456789abcdef"    },
        { "key_version",   "00112233"                            },
        { "key_id",        "fedcba9876543210"                    },
      }
      local kept = {}
      for _, p in ipairs(parts) do
        if p[1] ~= key then
          kept[#kept + 1] = p[1] .. "=" .. p[2]
        end
      end
      local line = "a=privacy: " .. table.concat(kept, "; ")
      local doc, ctx = ipmx.match(build_with_privacy({
        session_lines = { line },
      }))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "tr-10-13.a.privacy." .. key .. "-required"))
    end)
  end

  it("rejects protocol=NULL", function()
    local line =
        "a=privacy: protocol=NULL; mode=AES-128-CTR;"
     .. " iv=0123456789abcdef;"
     .. " key_generator=0123456789abcdef0123456789abcdef;"
     .. " key_version=00112233;"
     .. " key_id=fedcba9876543210"
    local doc, ctx = ipmx.match(build_with_privacy({ session_lines = { line } }))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "tr-10-13.a.privacy.protocol-null-forbidden"))
  end)

  it("rejects mode=NULL (subsumed by enum check)", function()
    local line =
        "a=privacy: protocol=RTP; mode=NULL;"
     .. " iv=0123456789abcdef;"
     .. " key_generator=0123456789abcdef0123456789abcdef;"
     .. " key_version=00112233;"
     .. " key_id=fedcba9876543210"
    local doc, ctx = ipmx.match(build_with_privacy({ session_lines = { line } }))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "tr-10-13.a.privacy.mode-invalid-value"))
  end)

  it("rejects mode not in the §20.1 enum", function()
    local line =
        "a=privacy: protocol=RTP; mode=NOT-A-MODE;"
     .. " iv=0123456789abcdef;"
     .. " key_generator=0123456789abcdef0123456789abcdef;"
     .. " key_version=00112233;"
     .. " key_id=fedcba9876543210"
    local doc, ctx = ipmx.match(build_with_privacy({ session_lines = { line } }))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx, "tr-10-13.a.privacy.mode-invalid-value"))
  end)

  -- Accept all 12 enumerated modes from §20.1 line 679.
  for _, mode in ipairs({
    "AES-128-CTR", "AES-256-CTR",
    "AES-128-CTR_CMAC-64", "AES-256-CTR_CMAC-64",
    "AES-128-CTR_CMAC-64-AAD", "AES-256-CTR_CMAC-64-AAD",
    "ECDH_AES-128-CTR", "ECDH_AES-256-CTR",
    "ECDH_AES-128-CTR_CMAC-64", "ECDH_AES-256-CTR_CMAC-64",
    "ECDH_AES-128-CTR_CMAC-64-AAD", "ECDH_AES-256-CTR_CMAC-64-AAD",
  }) do
    it("accepts mode=" .. mode, function()
      local line =
          "a=privacy: protocol=RTP; mode=" .. mode .. ";"
       .. " iv=0123456789abcdef;"
       .. " key_generator=0123456789abcdef0123456789abcdef;"
       .. " key_version=00112233;"
       .. " key_id=fedcba9876543210"
      assert.is_truthy(ipmx.match(build_with_privacy({
        session_lines = { line },
      })))
    end)
  end

  for _, case in ipairs({
    { key = "iv",            wrong = "0123",                                       label = "too short" },
    { key = "iv",            wrong = "0123456789abcdef00",                         label = "too long"  },
    { key = "iv",            wrong = "0123456789abcdeg",                           label = "non-hex"   },
    { key = "key_generator", wrong = "0123",                                       label = "too short" },
    { key = "key_version",   wrong = "001122",                                     label = "too short" },
    { key = "key_id",        wrong = "0123zzzz76543210",                           label = "non-hex"   },
  }) do
    it("rejects " .. case.key .. " (" .. case.label .. ")", function()
      local parts = {
        protocol      = "RTP",
        mode          = "AES-128-CTR",
        iv            = "0123456789abcdef",
        key_generator = "0123456789abcdef0123456789abcdef",
        key_version   = "00112233",
        key_id        = "fedcba9876543210",
      }
      parts[case.key] = case.wrong
      local line = string.format(
        "a=privacy: protocol=%s; mode=%s; iv=%s; key_generator=%s;"
        .. " key_version=%s; key_id=%s",
        parts.protocol, parts.mode, parts.iv, parts.key_generator,
        parts.key_version, parts.key_id)
      local doc, ctx = ipmx.match(build_with_privacy({
        session_lines = { line },
      }))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx,
        "tr-10-13.a.privacy." .. case.key .. "-invalid-form"))
    end)
  end

  -- NOT-SPEC: library — a=privacy is IPMX-specific. Lower tiers accept
  -- it as a generic attribute regardless of form.
  it("base / ST 2110 tiers accept a=privacy as a generic attribute", function()
    local sdp = build_with_privacy({
      session_lines = { "a=privacy: bogus=value" },
    })
    assert.is_truthy(base.match(sdp))
    assert.is_truthy(st2110.match(sdp))
  end)
end)

-- ── TR-10-13 §20.1 — a=extmap direction for PEP IV-Counter URNs ───────────

describe("IPMX TR-10-13 §20.1 — a=extmap PEP direction", function()

  local function build_with_extmap(opts)
    opts = opts or {}
    local lines = {
      "v=0",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=Test",
      "t=0 0",
    }
    for _, l in ipairs(opts.session_lines or {}) do
      lines[#lines + 1] = l
    end
    lines[#lines + 1] = "m=video 30000 RTP/AVP 96"
    lines[#lines + 1] = "c=IN IP4 239.0.0.1/64"
    lines[#lines + 1] = "a=mid:1"
    lines[#lines + 1] = "a=rtpmap:96 raw/90000"
    lines[#lines + 1] = RAW_FMTP_IPMX_PT96
    for _, l in ipairs(opts.media_lines or {}) do
      lines[#lines + 1] = l
    end
    lines[#lines + 1] = TIMING_TS_REFCLK
    lines[#lines + 1] = TIMING_MEDIACLK
    return lines_to_sdp(lines)
  end

  it("accepts session-level PEP-Full-IV-Counter extmap with direction=sendonly", function()
    assert.is_truthy(ipmx.match(build_with_extmap({
      session_lines = {
        "a=extmap:1/sendonly urn:ietf:params:rtp-hdrext:PEP-Full-IV-Counter",
      },
    })))
  end)

  it("accepts session-level PEP-Short-IV-Counter extmap with direction=sendonly", function()
    assert.is_truthy(ipmx.match(build_with_extmap({
      session_lines = {
        "a=extmap:2/sendonly urn:ietf:params:rtp-hdrext:PEP-Short-IV-Counter",
      },
    })))
  end)

  it("accepts media-level PEP extmap with direction=sendonly", function()
    assert.is_truthy(ipmx.match(build_with_extmap({
      media_lines = {
        "a=extmap:1/sendonly urn:ietf:params:rtp-hdrext:PEP-Full-IV-Counter",
      },
    })))
  end)

  it("rejects PEP extmap with direction=recvonly", function()
    local doc, ctx = ipmx.match(build_with_extmap({
      session_lines = {
        "a=extmap:1/recvonly urn:ietf:params:rtp-hdrext:PEP-Full-IV-Counter",
      },
    }))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "tr-10-13.a.extmap.pep-direction-must-be-sendonly"))
  end)

  it("rejects PEP extmap with direction=sendrecv", function()
    local doc, ctx = ipmx.match(build_with_extmap({
      session_lines = {
        "a=extmap:1/sendrecv urn:ietf:params:rtp-hdrext:PEP-Full-IV-Counter",
      },
    }))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "tr-10-13.a.extmap.pep-direction-must-be-sendonly"))
  end)

  it("rejects PEP extmap with no direction parameter", function()
    -- base.lua's a_extmap allows direction to be omitted (RFC 8285);
    -- for PEP URIs the SHALL requires it to be present and equal
    -- 'sendonly'.
    local doc, ctx = ipmx.match(build_with_extmap({
      session_lines = {
        "a=extmap:1 urn:ietf:params:rtp-hdrext:PEP-Full-IV-Counter",
      },
    }))
    assert.is_nil(doc)
    assert.is_not_nil(finding_for(ctx,
      "tr-10-13.a.extmap.pep-direction-must-be-sendonly"))
  end)

  it("does not fire on non-PEP extmap URIs", function()
    -- A different URI must not trip the §20.1 check — it's conditional
    -- on the URI being a PEP IV-Counter URN.
    assert.is_truthy(ipmx.match(build_with_extmap({
      session_lines = {
        "a=extmap:1 urn:ietf:params:rtp-hdrext:toffset",
      },
    })))
  end)

  -- NOT-SPEC: library — the direction requirement is IPMX-specific.
  -- Lower tiers must still accept any direction on PEP URI extmap.
  it("ST 2110 tier still accepts PEP extmap with direction=recvonly", function()
    assert.is_truthy(st2110.match(build_with_extmap({
      session_lines = {
        "a=extmap:1/recvonly urn:ietf:params:rtp-hdrext:PEP-Full-IV-Counter",
      },
    })))
  end)
end)

-- ── TR-10-14 §14 — USB transport block (m=application TCP usb) ───────────

describe("IPMX TR-10-14 §14 — USB block constraints", function()

  local function build_usb_sdp(lines_in)
    local lines = {
      "v=0",
      "o=- 1 1 IN IP4 192.0.2.1",
      "s=Test",
      "t=0 0",
      "m=application 30000 TCP usb",
      "c=IN IP4 192.0.2.2",
    }
    for _, l in ipairs(lines_in or {}) do
      lines[#lines + 1] = l
    end
    return lines_to_sdp(lines)
  end

  it("accepts a USB block with a=setup:passive", function()
    assert.is_truthy(ipmx.match(build_usb_sdp({ "a=setup:passive" })))
  end)

  it("rejects a USB block missing a=setup", function()
    local doc, ctx = ipmx.match(build_usb_sdp({}))
    assert.is_nil(doc)
    local f = finding_for(ctx, "tr-10-14.usb.setup-required")
    assert.is_not_nil(f)
    assert.equal("media[0].attributes[setup]", f.field_path)
  end)

  for _, role in ipairs({ "active", "actpass", "holdconn" }) do
    it("rejects a USB block with a=setup:" .. role, function()
      local doc, ctx = ipmx.match(build_usb_sdp({ "a=setup:" .. role }))
      assert.is_nil(doc)
      assert.is_not_nil(finding_for(ctx, "tr-10-14.usb.setup-must-be-passive"))
    end)
  end

  it("accepts a USB block with a=privacy using protocol=USB_KV", function()
    assert.is_truthy(ipmx.match(build_usb_sdp({
      "a=setup:passive",
      "a=privacy: protocol=USB_KV; mode=AES-128-CTR_CMAC-64-AAD;"
        .. " iv=0123456789abcdef;"
        .. " key_generator=0123456789abcdef0123456789abcdef;"
        .. " key_version=00112233;"
        .. " key_id=fedcba9876543210",
    })))
  end)

  it("rejects a USB block whose a=privacy uses protocol=RTP", function()
    local doc, ctx = ipmx.match(build_usb_sdp({
      "a=setup:passive",
      "a=privacy: protocol=RTP; mode=AES-128-CTR;"
        .. " iv=0123456789abcdef;"
        .. " key_generator=0123456789abcdef0123456789abcdef;"
        .. " key_version=00112233;"
        .. " key_id=fedcba9876543210",
    }))
    assert.is_nil(doc)
    local f = finding_for(ctx,
      "tr-10-14.a.privacy.usb-protocol-must-be-usb_kv")
    assert.is_not_nil(f)
    assert.equal("media[0].attributes[privacy]", f.field_path)
  end)

  -- The USB-block checks are scoped to m=application TCP usb. RTP
  -- video / audio blocks with a=setup:active are valid SDP and must
  -- not trip the §14 USB SHALL.
  it("does not fire on RTP video blocks", function()
    local doc, ctx = ipmx.match(build_video_sdp())
    assert.is_truthy(doc)
    if ctx then
      assert.is_nil(finding_for(ctx, "tr-10-14.usb.setup-required"))
      assert.is_nil(finding_for(ctx, "tr-10-14.usb.setup-must-be-passive"))
    end
  end)

  -- NOT-SPEC: library — USB block constraints are IPMX-specific. Lower
  -- tiers must still accept a USB block missing a=setup (RFC 4145
  -- compliance is signaled but the base grammar doesn't enforce it).
  it("base / ST 2110 tiers accept a USB block missing a=setup", function()
    local sdp = build_usb_sdp({})
    assert.is_truthy(base.match(sdp))
    assert.is_truthy(st2110.match(sdp))
  end)
end)
