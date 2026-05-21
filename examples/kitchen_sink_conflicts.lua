-- examples/kitchen_sink_conflicts.lua
-- Run from the repo root:  lua examples/kitchen_sink_conflicts.lua
--
-- The other kitchen-sink files build *valid* docs at their tier and
-- assert is_<tier>() passes. They can't show combinations that the
-- spec explicitly forbids — putting both halves of a forbidden combo
-- in the same doc would just fail the tier-validity assertion.
--
-- This file collects those forbidden combinations as tiny per-conflict
-- SDP text fixtures. Each fixture is the minimum lines needed to
-- trigger the rejection, paired with the structured finding the
-- validator produces. The aim is "here is exactly the wording the
-- spec uses, here is what trips it, here is what the validator
-- says when it does."
--
-- Companion files for the valid side:
--   * examples/kitchen_sink.lua          — RFC 8866 base
--   * examples/kitchen_sink_st2110.lua   — ST 2110 layer
--   * examples/kitchen_sink_ipmx.lua     — IPMX layer

local sdp = require("parse_sdp")

local function lines_to_sdp(lines)
  return table.concat(lines, "\r\n") .. "\r\n"
end

local function show(label, mode, lines)
  print("\n" .. ("━"):rep(72))
  print("  " .. label)
  print(("━"):rep(72))
  local text = lines_to_sdp(lines)
  print("  SDP (" .. #lines .. " lines, parsed at mode='" .. mode .. "'):")
  for _, ln in ipairs(lines) do print("    " .. ln) end
  local doc, err = sdp.parse(text, mode)
  if doc then
    print("\n  Unexpectedly parsed OK — fixture no longer demonstrates the conflict.")
    os.exit(1)
  end
  print("\n  Rejection:")
  print("    err.id       = " .. tostring(err.id))
  print("    err.message  = " .. tostring(err.message))
  print("    err.spec_ref = " .. tostring(err.spec_ref))
  if err.line and err.line > 0 then
    print("    err.line:col = " .. err.line .. ":" .. err.col)
  end
end

-- ── 1. RFC 7273 §4.8: traceable and non-traceable can't mix at one level ────
-- "Traceable time sources MUST NOT be mixed with non-traceable time
--  sources at any given level."
-- The two ts-refclk lines below — gps (traceable bare clksrc) and
-- ptp=…:GMID:domain (non-traceable) — sit at the same media level,
-- which violates the SHALL.
show("RFC 7273 §4.8 — ts-refclk traceable / non-traceable mix at one level",
  "sdp", {
    "v=0", "o=- 1 1 IN IP4 192.0.2.1", "s=t",
    "c=IN IP4 224.0.0.1/127", "t=0 0",
    "m=video 5000 RTP/AVP 96",
    "a=rtpmap:96 H264/90000",
    "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",   -- non-traceable
    "a=ts-refclk:gps",                                            -- traceable (bare gps)
  })

-- ── 2. RFC 7273 §4.8 EUI-64: ptp= GMID must be exactly 8 hex octets ─────────
-- "ptp-gmid = EUI64 = 7(2HEXDIG "-") 2HEXDIG"
-- The body below has 5 octets. Restored in 1.1.1 — the 1.1.0 grammar's
-- clksrc-ext fallback silently accepted this as an opaque extension.
show("RFC 7273 §4.8 — ts-refclk:ptp= with malformed (5-octet) GMID",
  "sdp", {
    "v=0", "o=- 1 1 IN IP4 192.0.2.1", "s=t",
    "c=IN IP4 224.0.0.1/127", "t=0 0",
    "m=video 5000 RTP/AVP 96",
    "a=rtpmap:96 H264/90000",
    "a=ts-refclk:ptp=IEEE1588-2008:AA-BB-CC-DD-EE:0",   -- 5 octets, not 8
  })

-- ── 3. ST 2110-10 §8.3: a=mediaclk MUST be per-media, not session-level ─────
-- "Each m= section shall contain an `a=mediaclk` attribute."
-- A session-level a=mediaclk does NOT satisfy the per-stream SHALL even
-- if it would be inherited by every block under RFC 8866 §5.7-style
-- inheritance. Each m= block needs its own.
show("ST 2110-10 §8.3 — session-level a=mediaclk does not satisfy the per-stream SHALL",
  "st2110", {
    "v=0", "o=- 1 1 IN IP4 192.0.2.1", "s=t", "t=0 0",
    "a=mediaclk:direct=0",                                       -- session-level
    "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
    "m=video 5000 RTP/AVP 96", "c=IN IP4 239.0.0.1/64",
    "a=rtpmap:96 raw/90000",
    "a=fmtp:96 sampling=YCbCr-4:2:2;width=1920;height=1080;exactframerate=25;depth=10;colorimetry=BT709;PM=2110GPM;TP=2110TPN;SSN=ST2110-20:2022",
    -- no per-media a=mediaclk
  })

-- ── 4. ST 2110-20 §7.4: PM=2110BPM forbids MAXUDP ────────────────────────────
-- "Senders that use Block Packing Mode shall not signal MAXUDP."
-- Block Packing Mode (2110BPM) packs sub-block-sized RTP payloads to
-- specific multiples; carrying that with the extended-UDP-size knob
-- defeats the BPM size invariants.
show("ST 2110-20 §7 — PM=2110BPM with MAXUDP is forbidden",
  "st2110", {
    "v=0", "o=- 1 1 IN IP4 192.0.2.1", "s=t", "t=0 0",
    "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
    "m=video 5000 RTP/AVP 96", "c=IN IP4 239.0.0.1/64",
    "a=rtpmap:96 raw/90000",
    "a=fmtp:96 sampling=YCbCr-4:2:2;width=1920;height=1080;exactframerate=25;depth=10;colorimetry=BT709;PM=2110BPM;TP=2110TPN;SSN=ST2110-20:2022;MAXUDP=1460",
    "a=mediaclk:direct=0",
  })

-- ── 5. TR-10-1 §10.1: every IPMX RTP block's fmtp must include 'IPMX' ───────
-- "IPMX Senders shall include the ' IPMX' declaration in the a=fmtp
--  clause of the SDP file."
-- The fmtp below has all the ST 2110-20 and TR-10-1 §10.2 measurement
-- params but is missing the bare IPMX flag.
show("TR-10-1 §10.1 — fmtp on an IPMX video block missing the IPMX marker",
  "ipmx", {
    "v=0", "o=- 1 1 IN IP4 192.0.2.1", "s=t", "t=0 0",
    "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
    "m=video 5000 RTP/AVP 96", "c=IN IP4 239.0.0.1/64",
    "a=source-filter: incl IN IP4 239.0.0.1 192.0.2.1",
    "a=rtpmap:96 raw/90000",
    "a=fmtp:96 sampling=YCbCr-4:2:2;width=1920;height=1080;exactframerate=25;depth=10;colorimetry=BT709;PM=2110GPM;TP=2110TPN;SSN=ST2110-20:2022;measuredpixclk=148500000;vtotal=1125;htotal=2200",
    -- no `IPMX` flag in the fmtp params
    "a=mediaclk:direct=0",
  })

-- ── 6. TR-10-{2,3,4,11,12} §7: IPMX UDP port must be even and > 1024 ────────
-- "All IPMX Media streams shall have a UDP destination port value that
--  is even and that is greater than 1024." Identical wording across the
--  per-essence TR-10s. Port 5001 is odd.
show("TR-10-2 §7 — IPMX m= UDP port must be even",
  "ipmx", {
    "v=0", "o=- 1 1 IN IP4 192.0.2.1", "s=t", "t=0 0",
    "a=ts-refclk:ptp=IEEE1588-2008:00-11-22-FF-FE-33-44-55:0",
    "m=video 5001 RTP/AVP 96", "c=IN IP4 239.0.0.1/64",   -- odd port
    "a=source-filter: incl IN IP4 239.0.0.1 192.0.2.1",
    "a=rtpmap:96 raw/90000",
    "a=fmtp:96 sampling=YCbCr-4:2:2;width=1920;height=1080;exactframerate=25;depth=10;colorimetry=BT709;PM=2110GPM;TP=2110TPN;SSN=ST2110-20:2022;measuredpixclk=148500000;vtotal=1125;htotal=2200;IPMX",
    "a=mediaclk:direct=0",
  })

-- ── 7. RFC 8866 §5.7: IPv4 multicast c= requires a TTL suffix ──────────────
-- "If the connection address is an IPv4 multicast address, the address
--  is followed by a '/' and the time-to-live (TTL) value of the
--  multicast IP packets sent on that address."
show("RFC 8866 §5.7 — IPv4 multicast c= without /TTL suffix",
  "sdp", {
    "v=0", "o=- 1 1 IN IP4 192.0.2.1", "s=t",
    "c=IN IP4 224.2.17.12",   -- multicast, no /TTL
    "t=0 0",
  })

-- ── 8. RFC 8866 §9 ABNF: c= IP4 address must be a literal dotted-quad ──────
-- "IP4-address = b1 3('.' decimal-uchar) ; decimal-uchar = 0..255"
show("RFC 8866 §9 ABNF — c= IP4 octet > 255",
  "sdp", {
    "v=0", "o=- 1 1 IN IP4 192.0.2.1", "s=t",
    "c=IN IP4 256.0.0.1",   -- 256 > 255
    "t=0 0",
  })

print("\n" .. ("━"):rep(72))
print("  Done. 8 fixtures, each demonstrating one forbidden combination")
print("  the layered kitchen-sink files can't show in a tier-valid doc.")
print(("━"):rep(72) .. "\n")
