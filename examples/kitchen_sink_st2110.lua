-- examples/kitchen_sink_st2110.lua
-- Run from the repo root:  lua examples/kitchen_sink_st2110.lua
--
-- Sibling of examples/kitchen_sink.lua. Where the base sink covers
-- RFC 8866 + cross-RFC base extensions (rtpmap, fmtp, ssrc, msid,
-- extmap, etc.), this file covers every attribute and parameter
-- ST 2110 adds or narrows on top, one media block per essence:
--
--   1. ST 2110-20 raw video (with the redundant DUP pair)
--   2. ST 2110-22 JPEG-XS video
--   3. ST 2110-30 PCM audio (L24)
--   4. ST 2110-40 ancillary data (smpte291)
--   5. ST 2110-41 fast metadata
--
-- Every field carries an inline RFC / SMPTE citation and a one-line
-- description. The file ends with assert(doc:is_st2110()) + a
-- parse → serialize → re-parse → deep-equal check, so it acts as
-- both a producer reference and a contract canary.
--
-- This file does NOT re-explain attribute shapes already covered in
-- kitchen_sink.lua (rtpmap structure, fmtp params shape, etc.) —
-- read that first if a field's role isn't obvious from context.
--
-- Tier-validity constraint: RFC 7273 §4.8 forbids mixing traceable
-- and non-traceable clock sources at the same scope, so every block
-- here uses the non-traceable ptp= form with explicit GMID + domain.
-- See examples/kitchen_sink_conflicts.lua for the small fixture
-- that demonstrates the traceable / non-traceable rejection.

local sdp    = require("parse_sdp")
local dkjson = require("dkjson")

-- ─── Build the doc ──────────────────────────────────────────────────────────

local doc = sdp.new({
  version = "0",                          -- RFC 8866 §5.1

  origin = {                              -- RFC 8866 §5.2
    username        = "-",
    sess_id         = "1122334455667788",
    sess_version    = "1",
    net_type        = "IN",
    addr_type       = "IP4",
    unicast_address = "10.10.0.1",
  },

  session = {
    name = "ST 2110 kitchen sink",        -- RFC 8866 §5.3
    info = "Annotated coverage across every ST 2110 sub-standard",  -- §5.4
    time_descriptions = { { start=0, stop=0, repeats={} } },        -- §5.9

    attributes = {
      -- a=ts-refclk at session level applies to every media block lacking
      -- its own. ST 2110-10:2022 §8.2 requires the `ptp=IEEE1588-2008:…`
      -- form when the device is referenced to PTPv2; the gmid is EUI-64
      -- (RFC 7273 §4.8) + a decimal domain.
      { name = "ts-refclk", source = "ptp",
        version     = "IEEE1588-2008",          -- ST 2110-10:2022 §6.1: PTPv2 only
        grandmaster = "00-11-22-FF-FE-33-44-55",-- RFC 7273 §4.8: 8-octet EUI-64
        domain      = "0",                      -- ST 2110-10:2022 §8.2: domain required
      },

      -- a=group:DUP — ST 2022-7 redundancy. The library cross-checks
      -- each tag has a matching a=mid on a real media block (ST 2110-10
      -- §8.5 / RFC 7104), and the two legs must share rtpmap encoding,
      -- clock rate, payload type, and fmtp body.
      { name = "group",
        semantics = "DUP",                       -- ST 2110-10 §8.5 / RFC 7104
        tags      = { "primary", "secondary" },
      },
    },
  },

  media = {

    -- ── Block 1: ST 2110-20 raw video (primary leg of the DUP group) ────────
    {
      media = "video", port = 20000, proto = "RTP/AVP", fmts = { "96" },
      connection = { net_type="IN", addr_type="IP4",
                     address = "239.100.10.1/64" },
      -- b=AS in kbps for raw video (ST 2110-20 references RFC 4566 §5.8).
      bandwidths = { { type = "AS", value = 2970000 } },
      attributes = {
        -- a=mid required on every m= line whenever any a=group is present,
        -- not just on grouped legs (RFC 5888 §6).
        { name = "mid", tag = "primary" },

        { name = "rtpmap", payload_type = 96, encoding = "raw",
          clock_rate = 90000 },              -- ST 2110-10 §6.2: dynamic PT 96–127

        -- ST 2110-20 §7.2 lists eight required fmtp parameters; ST 2110-21
        -- §8.1 adds the ninth (TP). All nine are validated for presence
        -- and value form. Per ST 2110-20 §7.1 the kv list uses "; " as
        -- the separator on the wire; the library accepts both forms but
        -- the serializer normalises to ";".
        { name = "fmtp", payload_type = 96, params = {
            { "sampling",       "YCbCr-4:2:2"    },  -- §7.2: sampling enum
            { "width",          "1920"           },  -- §7.2: positive int
            { "height",         "1080"           },  -- §7.2: positive int
            { "exactframerate", "50"             },  -- §7.2: positive int or N/D
            { "depth",          "10"             },  -- §7.2: 8/10/12/16/16f
            { "TCS",            "SDR"            },  -- §7.3: TCS enum (optional)
            { "colorimetry",    "BT709"          },  -- §7.2: colorimetry enum
            { "PM",             "2110GPM"        },  -- §7.2: packing mode
            { "SSN",            "ST2110-20:2022" },  -- §7.2: spec version stamp
            { "TP",             "2110TPN"        },  -- ST 2110-21 §8.1: traffic shaping profile
            -- Optional ST 2110-20 / ST 2110-21 params that pass-through
            -- validation when present (validated for value form only):
            { "RANGE",          "NARROW"         },  -- §7.3: RANGE enum
            { "PAR",            "1:1"            },  -- §7.3: pixel aspect ratio
            { "MAXUDP",         "1460"           },  -- ST 2110-10 §6.4: ≤ 8960
            -- ST 2110-10 §8.7 TSMODE / TSDELAY (optional, validated when present):
            { "TSMODE",         "NEW"            },  -- §8.7: NEW or SAMP
            { "TSDELAY",        "100"            },  -- §8.7: positive int (µs)
        }},

        -- a=mediaclk is REQUIRED at media level per ST 2110-10 §8.3.
        -- offset SHALL be 0; optional rate pair carries the source clock
        -- rate per RFC 7273 §5.4.
        { name = "mediaclk", mode = "direct", offset = 0 },
      },
    },

    -- ── Block 2: ST 2110-20 raw video (secondary DUP leg) ──────────────────
    -- Identical essence parameters to block 1; only port + c= addr differ.
    -- ST 2022-7 §6 requires identical PT, encoding, clock rate, fmtp body.
    {
      media = "video", port = 20002, proto = "RTP/AVP", fmts = { "96" },
      connection = { net_type="IN", addr_type="IP4",
                     address = "239.100.10.2/64" },
      bandwidths = { { type = "AS", value = 2970000 } },
      attributes = {
        { name = "mid", tag = "secondary" },
        { name = "rtpmap", payload_type = 96, encoding = "raw",
          clock_rate = 90000 },
        { name = "fmtp", payload_type = 96, params = {
            { "sampling",       "YCbCr-4:2:2"    },
            { "width",          "1920"           },
            { "height",         "1080"           },
            { "exactframerate", "50"             },
            { "depth",          "10"             },
            { "TCS",            "SDR"            },
            { "colorimetry",    "BT709"          },
            { "PM",             "2110GPM"        },
            { "SSN",            "ST2110-20:2022" },
            { "TP",             "2110TPN"        },
            { "RANGE",          "NARROW"         },
            { "PAR",            "1:1"            },
            { "MAXUDP",         "1460"           },
            { "TSMODE",         "NEW"            },
            { "TSDELAY",        "100"            },
        }},
        { name = "mediaclk", mode = "direct", offset = 0 },
      },
    },

    -- ── Block 3: ST 2110-22 JPEG-XS video ──────────────────────────────────
    -- RFC 9134 + ST 2110-22 — compressed video for IPMX-grade and lower-
    -- bandwidth applications. Mandatory params per §7.2 Table 1 + IANA
    -- video/jxsv (RFC 9134 §7.1) `packetmode`. ST 2110-22 §7.3 makes b=AS
    -- REQUIRED on every jxsv block (ST 2110 tier enforces this).
    {
      media = "video", port = 20010, proto = "RTP/AVP", fmts = { "97" },
      connection = { net_type="IN", addr_type="IP4",
                     address = "239.100.20.1/64" },
      bandwidths = { { type = "AS", value = 200000 } },   -- §7.3: REQUIRED
      attributes = {
        { name = "mid", tag = "jxs" },

        { name = "rtpmap", payload_type = 97, encoding = "jxsv",
          clock_rate = 90000 },              -- ST 2110-22 §6.2: video/jxsv at 90 kHz

        { name = "fmtp", payload_type = 97, params = {
            -- Required (§7.2 Table 1 + RFC 9134 §7.1):
            { "width",          "1920"         },   -- §7.2: positive int
            { "height",         "1080"         },   -- §7.2: positive int
            { "TP",             "2110TPN"      },   -- §7.2: 2110TPN/2110TPNL/2110TPW
            { "packetmode",     "0"            },   -- RFC 9134 §4.3: 1-bit
            -- Optional (validated for value form when present):
            { "sampling",       "YCbCr-4:2:2"  },   -- RFC 9134 §7.1: sampling enum
            { "depth",          "10"           },   -- RFC 9134 §7.1: positive int
            { "exactframerate", "25"           },   -- RFC 9134 §7.1: int or N/D
            { "colorimetry",    "BT709"        },   -- RFC 9134 §7.1: colorimetry enum
            { "profile",        "Main422.10"   },   -- §7.2: profile enum
            { "level",          "4k-1"         },   -- §7.2: level enum
            { "sublevel",       "Sublev3bpp"   },   -- §7.2: sublevel enum
            { "transmode",      "1"            },   -- IANA: 1-bit
        }},

        { name = "mediaclk", mode = "direct", offset = 0 },
      },
    },

    -- ── Block 4: ST 2110-30 PCM audio (L24, 6-channel 5.1) ─────────────────
    {
      media = "audio", port = 21000, proto = "RTP/AVP", fmts = { "100" },
      connection = { net_type="IN", addr_type="IP4",
                     address = "239.100.11.1/64" },
      attributes = {
        { name = "mid", tag = "aud" },

        -- ST 2110-30 §6.1: L16 / L24 / AM824. Channels (encoding-params)
        -- is part of the rtpmap value; the library captures it as
        -- `channels` on the decomposed attribute.
        { name = "rtpmap",
          payload_type = 100, encoding = "L24",
          clock_rate   = 48000,    -- §6.1: 48 kHz mandated, 44.1/96 permitted
          channels     = 6,
        },

        -- ST 2110-30 §6.2.2: channel-order convention for multichannel
        -- audio. Validated against the SMPTE2110.(<group-list>) form.
        { name = "fmtp", payload_type = 100, params = {
            { "channel-order", "SMPTE2110.(51)" },
        }},

        -- a=ptime is optional in ST 2110-30 but typical for low-latency
        -- audio (1 ms / 48 samples per packet at 48 kHz, etc.).
        { name = "ptime", value = 1 },

        { name = "mediaclk", mode = "direct", offset = 0 },
      },
    },

    -- ── Block 5: ST 2110-40 ancillary data (smpte291) ──────────────────────
    -- m=video per RFC 8331 §4.1 (smpte291 lives on a video m= line even
    -- though it carries ancillary metadata, not raster). ST 2110-40:2023
    -- §7 narrows the required fmtp set.
    {
      media = "video", port = 22000, proto = "RTP/AVP", fmts = { "101" },
      connection = { net_type="IN", addr_type="IP4",
                     address = "239.100.40.1/64" },
      attributes = {
        { name = "mid", tag = "anc" },

        { name = "rtpmap",
          payload_type = 101, encoding = "smpte291",
          clock_rate = 90000,                       -- ST 2110-40 §7: 90 kHz fixed
        },

        { name = "fmtp", payload_type = 101, params = {
            -- Required (ST 2110-40:2023 §7):
            { "SSN",            "ST2110-40:2018" }, -- §7: spec version (no TM signaled)
            { "exactframerate", "25"             }, -- §7: positive int or N/D
            -- Optional (validated when present):
            { "DID_SDID",       "{0x41,0x07}"    }, -- RFC 8331 §4: two hex octets
            { "VPID_Code",      "133"            }, -- ST 2110-40 §7.2: non-negative int
        }},

        { name = "mediaclk", mode = "direct", offset = 0 },
      },
    },

    -- ── Block 6: ST 2110-41 fast metadata ──────────────────────────────────
    -- m=application per ST 2110-41:2024 §5. Clock rate is data-item-
    -- defined per §5.3 (parser checks only "positive integer").
    {
      media = "application", port = 23000, proto = "RTP/AVP", fmts = { "102" },
      connection = { net_type="IN", addr_type="IP4",
                     address = "239.100.41.1/64" },
      attributes = {
        { name = "mid", tag = "fm" },

        { name = "rtpmap",
          payload_type = 102, encoding = "ST2110-41",
          clock_rate = 90000,                       -- §5.3: any positive int
        },

        { name = "fmtp", payload_type = 102, params = {
            -- Required (§6):
            { "SSN", "ST2110-41:2024" },            -- §6: ST2110-41:YYYY
            -- Optional (§6, §9.2.3):
            { "DIT", "100,2000A1,1013FC,3FFF00" },  -- §6: comma-separated uppercase hex
        }},

        { name = "mediaclk", mode = "direct", offset = 0 },
      },
    },
  },
})

-- ─── Verify ────────────────────────────────────────────────────────────────

local function hr(label)
  print("\n" .. ("━"):rep(72)); print("  " .. label); print(("━"):rep(72))
end

hr("1. Doc table (dkjson with indent)")
print(dkjson.encode(doc, { indent = true }))

hr("2. doc:to_sdp()")
local sdp_text, serr = doc:to_sdp()
assert(sdp_text, serr and serr.message)
io.write(sdp_text)

hr("3. ST 2110 tier validation + round-trip")
local ok, err = doc:validate("st2110")
assert(ok, err and err.message)
print("  ✓ doc:is_st2110() == true")

local function nil_or_empty(x)
  return x == nil or (type(x) == "table" and next(x) == nil)
end
local function deep_equal(a, b, path)
  path = path or "(root)"
  if nil_or_empty(a) and nil_or_empty(b) then return true end
  if type(a) ~= type(b) then
    return false, path .. ": type " .. type(a) .. " vs " .. type(b)
  end
  if type(a) ~= "table" then
    if a == b then return true end
    return false, path .. ": " .. tostring(a) .. " ≠ " .. tostring(b)
  end
  for k, v in pairs(a) do
    local eq, why = deep_equal(v, b[k], path .. "." .. tostring(k))
    if not eq then return false, why end
  end
  for k, v in pairs(b) do
    if a[k] == nil and not nil_or_empty(v) then
      return false, path .. "." .. tostring(k) .. ": only in re-parsed"
    end
  end
  return true
end

local reparsed, perr = sdp.parse(sdp_text, "st2110")
assert(reparsed, perr and perr.message)
local eq, why = deep_equal(doc, reparsed, "doc")
if eq then
  print("  ✓ doc == sdp.parse(doc:to_sdp(), 'st2110')")
else
  print("  ✗ drift: " .. why); os.exit(1)
end

local total_attrs = #doc.session.attributes
for _, m in ipairs(doc.media) do total_attrs = total_attrs + #m.attributes end
print("\n" .. ("━"):rep(72))
print("  Done. " .. select(2, sdp_text:gsub("\r\n", "")) ..
      " lines of SDP, " .. #doc.media .. " media blocks (raw video DUP " ..
      "pair, JPEG-XS, L24 audio, smpte291 ANC, ST 2110-41 fast metadata), " ..
      total_attrs .. " total attributes.")
print(("━"):rep(72) .. "\n")
