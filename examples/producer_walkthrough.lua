-- examples/producer_walkthrough.lua
-- Run from the repo root:  lua examples/producer_walkthrough.lua
-- (or inside the container: docker compose run --rm test lua
--  examples/producer_walkthrough.lua)
--
-- Companion to GUIDE.md § Producer Workflow. Builds an ST 2110-20 1080p25
-- video sender SDP step by step. At each step we call to_sdp() and
-- validate() and print what they say — the error message is the next
-- thing to add. The doc that comes out of step 6 is a conforming
-- ST 2110 SDP; step 7 shows the IPMX delta.

local sdp = require("parse_sdp")

local function header(label)
  print("\n" .. ("━"):rep(72))
  print("  " .. label)
  print(("━"):rep(72))
end

local function check(t, modes)
  local doc = sdp.new(t)
  local out, serr = doc:to_sdp()
  print("  to_sdp()                    → " ..
        (out and "OK" or ("nil: " .. serr.message)))
  for _, mode in ipairs(modes or { "sdp", "st2110" }) do
    local ok, err = doc:validate(mode)
    print(string.format("  validate(%-8s)         → %s",
      "'" .. mode .. "'", ok and "OK" or err.message))
  end
end

-- The doc table we'll grow across steps. Re-checked after each mutation.
local doc = {}

header("Step 1 — empty doc")
check(doc)

header("Step 2 — minimal session (v=, o=, s=, t=)")
doc = {
  version = "0",
  origin  = { username        = "-",
              sess_id         = "1",
              sess_version    = "1",
              net_type        = "IN",
              addr_type       = "IP4",
              unicast_address = "192.0.2.1" },
  session = {
    name              = "Camera 1",
    time_descriptions = { { start = 0, stop = 0, repeats = {} } },
  },
  media = {},
}
check(doc)

header("Step 3 — add a bare m= block (dynamic PT 96)")
doc.media[1] = {
  media = "video", port = 50000, proto = "RTP/AVP", fmts = { "96" },
  connection = { net_type  = "IN",
                 addr_type = "IP4",
                 address   = "239.0.0.1/64" },
  attributes = {},
}
check(doc)

header("Step 4 — + a=rtpmap (resolves dynamic-PT requirement)")
table.insert(doc.media[1].attributes, {
  name = "rtpmap", payload_type = 96,
  encoding = "raw", clock_rate = 90000,
})
check(doc)

header("Step 5 — + a=fmtp (ST 2110-20 §7.2 + ST 2110-21 §8.1)")
table.insert(doc.media[1].attributes, {
  name = "fmtp", payload_type = 96,
  params = {
    { "sampling",       "YCbCr-4:2:2"    },
    { "width",          "1920"           },
    { "height",         "1080"           },
    { "exactframerate", "25"             },
    { "depth",          "10"             },
    { "colorimetry",    "BT709"          },
    { "PM",             "2110GPM"        },
    { "SSN",            "ST2110-20:2022" },
    { "TP",             "2110TPN"        },
  },
})
check(doc)

header("Step 6 — + a=ts-refclk + a=mediaclk (ST 2110-10 §8.2 / §8.3)")
table.insert(doc.media[1].attributes, {
  name = "ts-refclk", source = "ptp",
  version = "IEEE1588-2008",
  grandmaster = "00-1D-9A-FF-FE-2C-32-0F",
  domain = "0",
})
table.insert(doc.media[1].attributes, {
  name = "mediaclk", mode = "direct", offset = 0,
})
check(doc)

header("Step 6 — emitted SDP")
print(sdp.new(doc):to_sdp())

header("Step 7 — IPMX delta (TR-10-1 §10.2)")
-- ST 2110 was happy. IPMX adds further required fmtp parameters on
-- video — measuredpixclk, vtotal, htotal — and source-filter per
-- TR-10-TP-1 §13.2. Keep the same loop: validate, read the error,
-- add the field, repeat. This first call surfaces only the *first*
-- missing IPMX field; iterate to walk the rest.
check(doc, { "st2110", "ipmx" })

print("\n" .. ("━"):rep(72))
print("  Done. See GUIDE.md § Producer Workflow for the narrative,")
print("  GUIDE.md § ST 2110 Validation and § IPMX Validation for the")
print("  per-clause required-attribute tables.")
print(("━"):rep(72) .. "\n")
