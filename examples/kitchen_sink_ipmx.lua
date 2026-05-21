-- examples/kitchen_sink_ipmx.lua
-- Run from the repo root:  lua examples/kitchen_sink_ipmx.lua
--
-- Third in the kitchen-sink series. Builds on the ST 2110 sink by
-- adding the IPMX (VSF TR-10) deltas:
--
--   * IPMX bare flag in every RTP block's a=fmtp (TR-10-1 §10.1)
--   * measuredpixclk / vtotal / htotal on every video fmtp (TR-10-1 §10.2)
--   * measuredsamplerate on every audio fmtp (TR-10-1 §10.3)
--   * a=source-filter required on every RTP block (TR-10-TP-1 §13.2)
--   * Port must be even and > 1024 (TR-10-{2,3,4,11,12} §7)
--   * a=infoframe at session level (TR-10-10 §8) — HDMI InfoFrame
--   * a=hkep at session level (TR-10-5 §10) — HDCP key exchange
--   * a=privacy at media level (TR-10-13 §13) — Privacy Encryption
--   * FECPROFILE / FEC_ADD_LATENCY_VIDEO in fmtp (TR-10-6 §7.6)
--
-- Every field carries an inline TR-10 citation. The file ends with
-- assert(doc:is_ipmx()) + a round-trip check.
--
-- This file does NOT re-explain attribute shapes covered by the base
-- and ST 2110 sinks — read those first if a field's role isn't
-- obvious. Companion files:
--   * examples/kitchen_sink.lua          — RFC 8866 base
--   * examples/kitchen_sink_st2110.lua   — ST 2110 layer
--   * examples/kitchen_sink_conflicts.lua — combinations these
--                                           can't show together

local sdp    = require("parse_sdp")
local dkjson = require("dkjson")

-- ─── Build the doc ──────────────────────────────────────────────────────────

local doc = sdp.new({
  version = "0",
  origin = {
    username        = "-",
    sess_id         = "9988776655443322",
    sess_version    = "1",
    net_type        = "IN",
    addr_type       = "IP4",
    unicast_address = "10.50.0.1",
  },

  session = {
    name = "IPMX kitchen sink",
    info = "Annotated coverage across the TR-10 IPMX profile",
    time_descriptions = { { start = 0, stop = 0, repeats = {} } },

    attributes = {
      -- ST 2110-10 §8.2: PTPv2 with explicit GMID + domain (non-traceable).
      { name = "ts-refclk", source = "ptp",
        version     = "IEEE1588-2008",
        grandmaster = "00-11-22-FF-FE-33-44-55",
        domain      = "0",
      },

      -- a=group:DUP for ST 2022-7 redundancy on the raw video pair.
      { name = "group", semantics = "DUP",
        tags = { "primary", "secondary" },
      },

      -- TR-10-10 §8: HDMI InfoFrame signaling, session-level. The port
      -- number is constrained — it SHALL equal one of the video media
      -- block ports + 3 (TR-10-10 §8). Primary video here is port 30000,
      -- so 30003 is valid.
      { name = "infoframe",
        port = 30003,                       -- TR-10-10 §8: media port + 3
        ssn  = "ST2110-41:2024",            -- TR-10-10 §8: SSN form is "ST2110-41:<year>"
                                            --              (InfoFrame rides on -41 transport)
        dit  = "100100",                    -- TR-10-10 §8: literal "100100"
      },

      -- TR-10-5 §10: HDCP Key Exchange Protocol signaling, session-level
      -- (or media-level). Six space-separated fields per the §17 IANA
      -- registration ABNF. The library captures `nettype/addrtype/addr`
      -- without the underscored form used elsewhere — see comment in
      -- parse_sdp/serialize.lua.
      { name = "hkep",
        port     = 5004,
        nettype  = "IN",
        addrtype = "IP4",
        addr     = "10.50.0.1",
        node_id  = "00112233-4455-6677-8899-aabbccddeeff",  -- §17: 32 hex digits, UUID form
        port_id  = "00-11-22-33-44",                        -- §17: 10 hex digits, xx-xx-xx-xx-xx
      },
    },
  },

  media = {

    -- ── Block 1: Raw video (primary DUP leg) ───────────────────────────────
    {
      media = "video", port = 30000, proto = "RTP/AVP", fmts = { "96" },
      -- TR-10-{2,3,4,11,12} §7: "All IPMX Media streams shall have a UDP
      -- destination port value that is even and that is greater than 1024."
      connection = { net_type="IN", addr_type="IP4",
                     address = "239.201.10.1/64" },
      bandwidths = { { type = "AS", value = 2970000 } },
      attributes = {
        { name = "mid", tag = "primary" },

        -- TR-10-TP-1 §13.2: "IPMX Receivers shall support … a=source-filter"
        -- on every RTP block. Either media-level or session-level.
        { name = "source-filter",
          filter_mode = "incl", net_type = "IN", addr_type = "IP4",
          dest_address = "239.201.10.1", src_addresses = { "10.50.0.1" },
        },

        { name = "rtpmap", payload_type = 96, encoding = "raw",
          clock_rate = 90000 },

        -- fmtp combines ST 2110-20 §7.2 / ST 2110-21 §8.1 mandatory params
        -- + TR-10-1 §10.1 IPMX flag + TR-10-1 §10.2 measurement params.
        -- FECPROFILE + FEC_ADD_LATENCY_VIDEO optionally demonstrated.
        { name = "fmtp", payload_type = 96, params = {
            { "sampling",       "YCbCr-4:2:2"    },
            { "width",          "1920"           },
            { "height",         "1080"           },
            { "exactframerate", "50"             },
            { "depth",          "10"             },
            { "TCS",            "SDR"            },
            { "colorimetry",    "BT709"          },
            { "PM",             "2110GPM"        },
            { "TP",             "2110TPN"        },
            { "SSN",            "ST2110-20:2022" },
            { "measuredpixclk", "148500000"      }, -- TR-10-1 §10.2: pos int (Hz)
            { "vtotal",         "1125"           }, -- TR-10-1 §10.2: pos int
            { "htotal",         "2200"           }, -- TR-10-1 §10.2: pos int
            { "FECPROFILE",     "profile-a"      }, -- TR-10-6 §7.6: only enum value
            { "FEC_ADD_LATENCY_VIDEO", "1000"    }, -- TR-10-6 §7.6: zero-based int (µs)
            { "IPMX",           true             }, -- TR-10-1 §10.1: bare flag
        }},

        -- TR-10-13 §13: Privacy Encryption Protocol signaling. Six params
        -- are all required when a=privacy is present; each has a specific
        -- value form (hex string of fixed length, or enum). mode = NULL
        -- is forbidden in an SDP transport file (§13).
        { name = "privacy",
          params = {
            { "protocol",      "PEP-128-AES-CTR"                  }, -- §13: any non-NULL token
            { "mode",          "AES-128-CTR"                      }, -- §20.1: 12-value enum
            { "iv",            "0123456789ABCDEF"                 }, -- §13: 64-bit (16 hex digits)
            { "key_generator", "00112233445566778899AABBCCDDEEFF" }, -- §13: 128-bit (32 hex)
            { "key_version",   "00000001"                         }, -- §13: 32-bit (8 hex)
            { "key_id",        "0011223344556677"                 }, -- §13: 64-bit (16 hex)
          },
          trailing_semi = false,            -- §13: a=privacy SHALL NOT end with ';'
                                            --      (re-parser always sets this — match it
                                            --       in the source for clean round-trip)
        },

        { name = "mediaclk", mode = "direct", offset = 0 },
      },
    },

    -- ── Block 2: Raw video (secondary DUP leg) ─────────────────────────────
    -- Identical fmtp body (ST 2022-7 §6) at the IPMX layer.
    {
      media = "video", port = 30002, proto = "RTP/AVP", fmts = { "96" },
      connection = { net_type="IN", addr_type="IP4",
                     address = "239.201.10.2/64" },
      bandwidths = { { type = "AS", value = 2970000 } },
      attributes = {
        { name = "mid", tag = "secondary" },
        { name = "source-filter",
          filter_mode = "incl", net_type = "IN", addr_type = "IP4",
          dest_address = "239.201.10.2", src_addresses = { "10.50.0.1" },
        },
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
            { "TP",             "2110TPN"        },
            { "SSN",            "ST2110-20:2022" },
            { "measuredpixclk", "148500000"      },
            { "vtotal",         "1125"           },
            { "htotal",         "2200"           },
            { "FECPROFILE",     "profile-a"      },
            { "FEC_ADD_LATENCY_VIDEO", "1000"    },
            { "IPMX",           true             },
        }},
        { name = "privacy", params = {
            { "protocol",      "PEP-128-AES-CTR"                  },
            { "mode",          "AES-128-CTR"                      },
            { "iv",            "0123456789ABCDEF"                 },
            { "key_generator", "00112233445566778899AABBCCDDEEFF" },
            { "key_version",   "00000001"                         },
            { "key_id",        "0011223344556677"                 },
          }, trailing_semi = false,
        },
        { name = "mediaclk", mode = "direct", offset = 0 },
      },
    },

    -- ── Block 3: JPEG-XS video (IPMX measurement params still required) ────
    -- TR-10-9 §10 extends the TR-10-1 §10.2 measurement-param SHALLs to
    -- non-baseband senders, so jxsv still needs measuredpixclk/vtotal/htotal.
    {
      media = "video", port = 30010, proto = "RTP/AVP", fmts = { "97" },
      connection = { net_type="IN", addr_type="IP4",
                     address = "239.201.20.1/64" },
      bandwidths = { { type = "AS", value = 200000 } },  -- §7.3: REQUIRED on jxsv
      attributes = {
        { name = "mid", tag = "jxs" },
        { name = "source-filter",
          filter_mode = "incl", net_type = "IN", addr_type = "IP4",
          dest_address = "239.201.20.1", src_addresses = { "10.50.0.1" },
        },
        { name = "rtpmap", payload_type = 97, encoding = "jxsv",
          clock_rate = 90000 },
        { name = "fmtp", payload_type = 97, params = {
            { "width",          "1920"      },
            { "height",         "1080"      },
            { "TP",             "2110TPN"   },
            { "packetmode",     "0"         },
            { "sampling",       "YCbCr-4:2:2" },
            { "depth",          "10"        },
            { "exactframerate", "25"        },
            { "colorimetry",    "BT709"     },
            { "profile",        "Main422.10"},
            { "level",          "4k-1"      },
            { "sublevel",       "Sublev3bpp"},
            { "measuredpixclk", "148500000" }, -- TR-10-9 §10 → TR-10-1 §10.2
            { "vtotal",         "1125"      },
            { "htotal",         "2200"      },
            { "IPMX",           true        },
        }},
        { name = "mediaclk", mode = "direct", offset = 0 },
      },
    },

    -- ── Block 4: PCM audio L24 ─────────────────────────────────────────────
    {
      media = "audio", port = 31000, proto = "RTP/AVP", fmts = { "100" },
      connection = { net_type="IN", addr_type="IP4",
                     address = "239.201.11.1/64" },
      attributes = {
        { name = "mid", tag = "aud" },
        { name = "source-filter",
          filter_mode = "incl", net_type = "IN", addr_type = "IP4",
          dest_address = "239.201.11.1", src_addresses = { "10.50.0.1" },
        },
        { name = "rtpmap",
          payload_type = 100, encoding = "L24",
          clock_rate = 48000, channels = 6,
        },
        { name = "fmtp", payload_type = 100, params = {
            { "channel-order",      "SMPTE2110.(51)" },
            { "measuredsamplerate", "48000"          }, -- TR-10-1 §10.3
            { "IPMX",               true             }, -- TR-10-1 §10.1
        }},
        { name = "ptime", value = 1 },        -- TR-10-3 §8: a=ptime required
        { name = "mediaclk", mode = "direct", offset = 0 },
      },
    },

    -- ── Block 5: Ancillary smpte291 (TR-10-4) ──────────────────────────────
    -- TR-10-4 inherits ST 2110-40 §7 fmtp requirements and adds the
    -- IPMX bare flag. measuredpixclk-family params do NOT apply to
    -- smpte291 (only the IPMX_RTP_VIDEO_PARAM table covers raw/jxsv).
    {
      media = "video", port = 32000, proto = "RTP/AVP", fmts = { "101" },
      connection = { net_type="IN", addr_type="IP4",
                     address = "239.201.40.1/64" },
      attributes = {
        { name = "mid", tag = "anc" },
        { name = "source-filter",
          filter_mode = "incl", net_type = "IN", addr_type = "IP4",
          dest_address = "239.201.40.1", src_addresses = { "10.50.0.1" },
        },
        { name = "rtpmap",
          payload_type = 101, encoding = "smpte291",
          clock_rate = 90000,
        },
        { name = "fmtp", payload_type = 101, params = {
            { "SSN",            "ST2110-40:2018" },
            { "exactframerate", "25"             },
            { "IPMX",           true             }, -- TR-10-1 §10.1
        }},
        { name = "mediaclk", mode = "direct", offset = 0 },
      },
    },

    -- ── Block 6: ST 2110-41 fast metadata (TR-10-11 covers fast metadata in IPMX) ──
    {
      media = "application", port = 33000, proto = "RTP/AVP", fmts = { "102" },
      connection = { net_type="IN", addr_type="IP4",
                     address = "239.201.41.1/64" },
      attributes = {
        { name = "mid", tag = "fm" },
        { name = "source-filter",
          filter_mode = "incl", net_type = "IN", addr_type = "IP4",
          dest_address = "239.201.41.1", src_addresses = { "10.50.0.1" },
        },
        { name = "rtpmap",
          payload_type = 102, encoding = "ST2110-41",
          clock_rate = 90000,
        },
        { name = "fmtp", payload_type = 102, params = {
            { "SSN",  "ST2110-41:2024"            },
            { "DIT",  "100,2000A1,1013FC,3FFF00"  },
            { "IPMX", true                        }, -- TR-10-1 §10.1
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

hr("3. IPMX tier validation + round-trip")
local ok, err = doc:validate("ipmx")
assert(ok, err and err.message)
print("  ✓ doc:is_ipmx() == true")

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

local reparsed, perr = sdp.parse(sdp_text, "ipmx")
assert(reparsed, perr and perr.message)
local eq, why = deep_equal(doc, reparsed, "doc")
if eq then
  print("  ✓ doc == sdp.parse(doc:to_sdp(), 'ipmx')")
else
  print("  ✗ drift: " .. why); os.exit(1)
end

local total_attrs = #doc.session.attributes
for _, m in ipairs(doc.media) do total_attrs = total_attrs + #m.attributes end
print("\n" .. ("━"):rep(72))
print("  Done. " .. select(2, sdp_text:gsub("\r\n", "")) ..
      " lines of SDP, " .. #doc.media .. " media blocks (raw video DUP " ..
      "pair, JPEG-XS, L24 audio, smpte291 ANC, ST 2110-41 fast metadata), " ..
      total_attrs .. " total attributes including session-level a=infoframe, " ..
      "a=hkep, and per-block a=privacy.")
print(("━"):rep(72) .. "\n")
