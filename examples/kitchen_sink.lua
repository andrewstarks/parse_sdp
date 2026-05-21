-- examples/kitchen_sink.lua
-- Run from the repo root:  lua examples/kitchen_sink.lua
--
-- A single doc that exercises every RFC 8866 line type and every
-- decomposed attribute the library understands, plus a forward-compat
-- "we don't have a spec for it" entry to show how unknown attributes
-- ride through the parse → serialize round-trip unchanged.
--
-- Every field in the Lua table carries an inline comment with the RFC
-- citation and a one-line description of what the field is for. The
-- file is meant to be read alongside the rendered SDP it prints.
--
-- The script prints three things and ends with a deep-equality check:
--
--   1. The doc as a Lua table (so you can see the shape sdp.new wants).
--   2. The same doc emitted via doc:to_sdp() (the wire form).
--   3. A round-trip assertion: parse the emitted text → deep-compare to
--      the source doc. If this ever fails, a shape contract has drifted
--      — the kitchen sink is the canary.
--
-- Target tier: RFC 8866 + the RFC extensions parse_sdp decomposes
-- natively (RFC 3605 rtcp, RFC 4570 source-filter, RFC 4585 rtcp-fb,
-- RFC 5576 ssrc / ssrc-group, RFC 5761 rtcp-mux, RFC 5888 mid / group,
-- RFC 7273 ts-refclk / mediaclk, RFC 8285 extmap, RFC 8830 msid).
--
-- Companion files for the higher tiers:
--   * examples/kitchen_sink_st2110.lua    — every ST 2110 attribute
--   * examples/kitchen_sink_ipmx.lua      — every IPMX extension
--   * examples/kitchen_sink_conflicts.lua — small fixtures for
--                                           combinations the layered
--                                           sinks can't show together
--                                           (e.g. RFC 7273 traceable /
--                                           non-traceable mix forbidden
--                                           at the same level).

local sdp    = require("parse_sdp")
local dkjson = require("dkjson")

-- ─── The kitchen-sink doc ───────────────────────────────────────────────────
-- Field shapes match the per-attribute renderers in parse_sdp/serialize.lua
-- (ATTR_RENDERERS) — that file is the canonical source of truth for "which
-- Lua keys does this attribute name expect."

local doc = sdp.new({

  -- v= Protocol Version (RFC 8866 §5.1) — always "0".
  version = "0",

  -- o= Origin (RFC 8866 §5.2): session originator + identifier.
  origin = {
    username        = "alice",            -- §5.2: originator user name; "-" if unknown
    sess_id         = "2890844526",       -- §5.2: numeric session id, globally unique
    sess_version    = "1",                -- §5.2: bumped on every SDP edit
    net_type        = "IN",               -- §5.2 / §8.2.6: only "IN" defined (Internet)
    addr_type       = "IP4",              -- §5.2: "IP4" or "IP6"
    unicast_address = "192.0.2.1",        -- §5.2: originator's unicast address (FQDN or IP)
  },

  session = {

    -- s= Session Name (RFC 8866 §5.3): human-readable name; required, may be " ".
    name = "Kitchen-sink SDP — every line type the library understands",

    -- i= Session Information (RFC 8866 §5.4): free-form description.
    info = "Annotated coverage example — see examples/kitchen_sink.lua",

    -- u= URI (RFC 8866 §5.5): pointer to additional info; session-level only.
    uri = "https://example.com/sessions/kitchen-sink",

    -- e= Email Addresses (RFC 8866 §5.6): zero or more; bare addr or
    -- "Name <addr>" form. The library passes the line through verbatim.
    emails = {
      "alice@example.com",
      "Bob Builder <bob@example.com>",
    },

    -- p= Phone Numbers (RFC 8866 §5.6): zero or more; opaque string.
    phones = {
      "+1 555 0100",
    },

    -- c= Connection Information (RFC 8866 §5.7): optional at session level if
    -- every m= block has its own c=, required otherwise.
    connection = {
      net_type  = "IN",                   -- §5.7: "IN"
      addr_type = "IP4",                  -- §5.7: "IP4" or "IP6"
      address   = "224.2.17.12/127",      -- §5.7: literal addr or FQDN; IPv4
                                          --        multicast carries "/TTL" + opt "/count"
    },

    -- b= Bandwidth (RFC 8866 §5.8): zero or more; defined bwtypes are CT
    -- (RFC 8866 §5.8) and AS (§5.8). TIAS lives in RFC 3890 §6.2.
    -- Experimental bwtypes are namespaced with "X-" per §5.8 — RFC 8866
    -- says tools SHOULD ignore unknown bwtypes, so X-* is the canonical
    -- "legal-but-we-don't-have-a-spec-for-it" carrier at this layer.
    bandwidths = {
      { type = "CT",       value = 1500    },   -- §5.8: Conference Total, kbps
      { type = "AS",       value = 1024    },   -- §5.8: Application Specific, kbps
      { type = "TIAS",     value = 1000000 },   -- RFC 3890 §6.2: bps (not kbps)
      { type = "X-CUSTOM", value = 42      },   -- §5.8: experimental, opaque value
    },

    -- t= Time Description (RFC 8866 §5.9): ≥1 required. start/stop=0 means
    -- "permanent." Each t= may carry zero or more r= sub-blocks.
    time_descriptions = {
      {
        start   = 3724394400,             -- §5.9: NTP seconds-since-1900
        stop    = 3724398000,             -- §5.9: NTP seconds; 0 = open-ended
        repeats = {                       -- r= Repeat Times (RFC 8866 §5.10)
          {
            interval = "7d",              -- §5.10: bare seconds or typed-time string
            duration = "1h",              -- §5.10: same encoding as interval
            offsets  = { "0", "25h" },    -- §5.10: ≥1 offset; typed-time or bare seconds
          },
        },
      },
    },

    -- z= Time Zone Adjustments (RFC 8866 §5.11): session-only; one z= line
    -- carries one or more (adjustment_time, offset) pairs.
    time_zones = {
      -- adjustment_time is kept as a digit string (the grammar's `digits` capture
      -- doesn't run /tonumber here — large NTP values would overflow Lua 5.3
      -- integers if interpreted at parse time, so the carrier stays verbatim).
      { adjustment_time = "2882844526", offset = "-1h" }, -- §5.11: NTP time + offset
      { adjustment_time = "2898848070", offset = "0"   },
    },

    -- a= Session-level Attributes (RFC 8866 §5.13). Insertion order is
    -- preserved on emission. Known names get decomposed fields per
    -- their RFC; unknown names use {name, value?} as the forward-compat
    -- carrier.
    attributes = {
      -- Direction (RFC 8866 §6.7): flag attribute — no `value` field.
      { name = "recvonly" },                                   -- §6.7

      -- Session-level value attributes (RFC 8866 §6.x). Opaque values.
      { name = "type",    value = "broadcast"        },        -- §6.10: session type
      { name = "charset", value = "UTF-8"            },        -- §6.11: charset for `s=`/`i=`/etc.
      { name = "tool",    value = "parse_sdp kitchen sink" },  -- §6.x: tool name/version
      { name = "sdplang", value = "en"               },        -- §6.12: language of the SDP itself
      { name = "lang",    value = "en"               },        -- §6.12: language of the media

      -- a=group (RFC 5888 §5): groups media blocks by `semantics` token
      -- (LS = lip-sync, FID = flow id, etc.) referencing each block's
      -- a=mid value. Library cross-checks that every tag has a matching
      -- mid (audit A10).
      { name = "group",
        semantics = "LS",                  -- RFC 5888 §5: group semantics token
        tags      = { "audio", "video" },  -- RFC 5888 §5: zero or more identification-tags
      },

      -- a=source-filter (RFC 4570): SSM-style source filtering. May appear
      -- at session OR media level. dest_address must match a c= address
      -- in the same scope per §3.1 (cross-checked by the library).
      { name = "source-filter",
        filter_mode   = "incl",            -- RFC 4570 §3: "incl" or "excl"
        net_type      = "IN",              -- RFC 4570 §3: "IN"
        addr_type     = "IP4",             -- RFC 4570 §3: "IP4" / "IP6" / "*"
        dest_address  = "224.2.17.12",     -- RFC 4570 §3: the multicast group from c=
        src_addresses = { "192.0.2.1" },   -- RFC 4570 §3: ≥1 unicast source
      },

      -- Forward-compat: an attribute the library has never seen. The
      -- generic carrier is {name, value} for "a=name:value" and {name}
      -- alone for "a=name" (flag). Round-trips byte-for-byte.
      { name = "x-vendor-experimental", value = "opaque-payload-here" },
      { name = "x-vendor-feature-flag" },
    },
  },

  media = {

    -- ── m=audio: every non-traceable ts-refclk variant + direct mediaclk ────
    -- RFC 7273 §4.8 forbids mixing traceable and non-traceable clock
    -- sources at the same level, so each media block sticks to one
    -- side. Non-traceable sources are gathered here; the video block
    -- below collects the traceable ones.
    {
      -- m= Media Description (RFC 8866 §5.14): media + transport + formats.
      media      = "audio",               -- §5.14: media type ("audio", "video", "text", ...)
      port       = 49170,                 -- §5.14: transport port; 0 = "do not start"
      proto      = "RTP/AVP",             -- §5.14: transport proto (RTP/AVP, UDP, etc.)
      fmts       = { "96", "0", "8" },    -- §5.14: format list (PT for RTP; opaque otherwise)

      -- i= Media-level Session Information (RFC 8866 §5.4).
      info       = "Stereo Opus + PCMU/PCMA fallback",

      -- c= Media-level Connection (RFC 8866 §5.7); overrides session-level.
      connection = {
        net_type = "IN", addr_type = "IP4", address = "224.2.17.13/127",
      },

      -- b= Media-level Bandwidth (RFC 8866 §5.8).
      bandwidths = { { type = "AS", value = 96 } },

      attributes = {
        -- a=rtpmap (RFC 8866 §6.6): PT → encoding mapping. encoding-params
        -- (channels) is required for audio per RFC 8866 §6.6 ABNF when
        -- the channel count isn't the encoding's default.
        { name = "rtpmap",
          payload_type = 96,              -- §6.6: dynamic PT (96–127) or static (≤95)
          encoding     = "opus",          -- §6.6: IANA-registered encoding name
          clock_rate   = 48000,           -- §6.6: clock rate in Hz
          channels     = 2,               -- §6.6: encoding-params; audio channel count
        },
        { name = "rtpmap", payload_type = 0, encoding = "PCMU",
          clock_rate = 8000 },            -- channels omitted: 1 (PCMU default)
        { name = "rtpmap", payload_type = 8, encoding = "PCMA",
          clock_rate = 8000 },

        -- a=fmtp (RFC 8866 §6.15): format-specific parameters. The
        -- library has two carrier shapes — `params` (ordered kv list,
        -- preferred) and `raw` (opaque byte-string, see the video
        -- block). A `true` value in params renders as a bare flag.
        { name = "fmtp",
          payload_type = 96,              -- §6.15: must match an rtpmap PT
          params = {                      -- §6.15: ordered {key, value} pairs
            { "minptime",     "10" },
            { "useinbandfec", "1"  },
          },
        },

        -- a=ptime / a=maxptime (RFC 8866 §6.4 / §6.5): packet time in ms.
        { name = "ptime",    value = 20 },        -- §6.4: target packet duration (ms)
        { name = "maxptime", value = 60 },        -- §6.5: max packet duration (ms)

        -- a=quality (RFC 8866 §6.14): 0–10 quality hint. Video-by-
        -- convention but the §6.14 ABNF doesn't restrict the m= type.
        { name = "quality", value = 7 },

        -- a=mid (RFC 5888 §4): identification tag for this media block;
        -- referenced from a=group semantics above.
        { name = "mid", tag = "audio" },          -- RFC 5888 §4: tag is an RFC 8866 token

        -- a=ssrc (RFC 5576 §10): per-SSRC attribute. `attribute` is the
        -- attribute name being conveyed; `value` is its value (optional —
        -- e.g. `cname` carries a value, `fmtp` may not).
        { name = "ssrc",
          ssrc_id   = 12345,              -- RFC 5576 §10: 32-bit SSRC
          attribute = "cname",            -- RFC 5576 §10: attribute name
          value     = "alice@example.com",
        },
        { name = "ssrc", ssrc_id = 12345,
          attribute = "fmtp" },                   -- value omitted

        -- a=ts-refclk (RFC 7273 §4.8) — non-traceable clksrc variants.
        -- See the video block for the traceable variants.
        --
        -- ptp= form with full gmid + domain (non-traceable).
        { name = "ts-refclk",
          source      = "ptp",             -- §4.8: "ntp" / "ptp" / "gps" / ... / clksrc-ext
          version     = "IEEE1588-2008",   -- §4.8: ptp-version token
          grandmaster = "39-A7-94-FF-FE-07-CB-D0",  -- §4.8: EUI-64 (8 hex octets)
          domain      = "37",              -- §4.8: ptp-domain (decimal 0–127 typical)
        },
        -- ntp= with literal address (non-traceable).
        { name = "ts-refclk", source = "ntp",
          address = "192.0.2.1" },         -- §4.8: ntp-server-addr
        -- private (bare, non-traceable).
        { name = "ts-refclk", source = "private" },  -- §4.8: "private" literal
        -- local (bare, non-traceable).
        { name = "ts-refclk", source = "local" },    -- §4.8: "local" literal
        -- clksrc-ext (ST 2110-10 §8.2 "localmac=<mac>"; non-traceable).
        { name = "ts-refclk",
          source = "localmac",             -- §4.8: clksrc-param-name (extension token)
          value  = "00-11-22-33-44-55",    -- §4.8: clksrc-param-value (opaque)
        },

        -- a=mediaclk (RFC 7273 §5.4): media-clock signaling. `direct`
        -- with optional offset and optional rate pair.
        { name = "mediaclk",
          mode   = "direct",               -- §5.4: "sender" / "direct" / "IEEE1722" / ext
          offset = 0,                      -- §5.4: direct offset, 1*DIGIT
          rate   = { num = 48000, den = 1 },  -- §5.4: optional "rate=N/D" pair
        },

        -- Direction (per-media, overrides session-level).
        { name = "sendrecv" },                  -- RFC 8866 §6.7
      },
    },

    -- ── m=video: traceable ts-refclk variants + every other decomposed attr ─
    {
      media = "video",
      port  = 49180,
      proto = "RTP/AVP",
      fmts  = { "99" },

      attributes = {
        { name = "rtpmap", payload_type = 99, encoding = "H264",
          clock_rate = 90000 },

        -- a=fmtp with the `raw` (opaque) carrier — the alternative to
        -- the decomposed `params` form. The grammar tries `params`
        -- first; it only falls through to `raw` when the body fails to
        -- decompose into k=v pairs (e.g. legacy comma-lists like
        -- "0,1,2" in older codec specs, or any byte-string that
        -- contains chars outside the fmtp key/value char set).
        { name = "fmtp",
          payload_type = 99,
          raw = "0,1,2",                       -- §6.15: opaque byte-string fallback
        },

        -- a=framerate (RFC 8866 §6.13): video frames per second.
        { name = "framerate", value = 30 },     -- §6.13: non-zero-int-or-real

        { name = "mid", tag = "video" },        -- RFC 5888 §4

        -- a=ssrc-group (RFC 5576 §10 Figure 5): groups SSRCs by semantics.
        { name = "ssrc-group",
          semantics = "FID",                    -- RFC 5576 §4: e.g. "FID" (Flow ID)
          ssrc_ids  = { 11, 22 },               -- RFC 5576 §10: zero or more 32-bit SSRCs
        },

        -- a=msid (RFC 8830): media stream identification (WebRTC).
        { name = "msid",
          msid_id = "stream-id-xyz",            -- RFC 8830 §2: stream identifier
          appdata = "track-id-abc",             -- RFC 8830 §2: optional app-specific data
        },

        -- a=extmap (RFC 8285 §8): RTP header-extension URI mapping.
        { name = "extmap",
          id  = 1,                              -- RFC 8285 §8: extension id, 1..255
          uri = "urn:ietf:params:rtp-hdrext:toffset",  -- RFC 8285 §8: URI for the extension
        },
        { name = "extmap", id = 2,
          direction  = "recvonly",              -- RFC 8285 §8: optional direction filter
          uri        = "urn:ietf:params:rtp-hdrext:ssrc-audio-level",
        },
        { name = "extmap", id = 3,
          uri        = "urn:ietf:params:rtp-hdrext:csrc-audio-level",
          attributes = "vad=on",                -- RFC 8285 §8: optional extension attrs
        },

        -- a=rtcp (RFC 3605 §2.1): explicit RTCP port. The optional
        -- (net_type, addr_type, address) triple is all-or-nothing per
        -- the ABNF — populating one or two is a malformed doc.
        { name = "rtcp",
          port      = 53020,                    -- RFC 3605 §2.1: RTCP port
          net_type  = "IN",                     -- §2.1: opt triple — "IN"
          addr_type = "IP4",                    -- §2.1: opt triple — "IP4" / "IP6"
          address   = "192.0.2.99",             -- §2.1: opt triple — explicit RTCP addr
        },

        -- a=rtcp-mux (RFC 5761 §5.1.3): flag attribute, no value.
        { name = "rtcp-mux" },

        -- a=rtcp-fb (RFC 4585 §4.2): RTCP feedback capability. payload_type
        -- accepts either a number (numeric PT) or the string "*" (all PTs).
        { name = "rtcp-fb",
          payload_type  = 99,                   -- RFC 4585 §4.2: PT (number) or "*"
          feedback_type = "nack",               -- RFC 4585 §4.2: feedback type token
        },
        { name = "rtcp-fb", payload_type = "*", feedback_type = "nack",
          parameters = "pli",                   -- RFC 4585 §4.2: opt feedback parameters
        },

        -- a=source-filter at media level (RFC 4570) — also valid here in
        -- addition to the session-level one above.
        { name = "source-filter",
          filter_mode = "incl", net_type = "IN", addr_type = "IP4",
          dest_address = "224.2.17.12", src_addresses = { "192.0.2.1" },
        },

        -- a=ts-refclk (RFC 7273 §4.8) — traceable clksrc variants.
        --
        -- ptp= traceable (no gmid/domain).
        { name = "ts-refclk", source = "ptp",
          version   = "IEEE1588-2008",
          traceable = true },                   -- §4.8: "traceable" literal in place of gmid
        -- ntp= /traceable/ form (no address).
        { name = "ts-refclk", source = "ntp",
          traceable = true },                   -- §4.8: ntp=/traceable/
        -- private:traceable.
        { name = "ts-refclk", source = "private",
          traceable = true },                   -- §4.8: "private:traceable"
        -- Bare traceable sources — gps, gal, glonass.
        { name = "ts-refclk", source = "gps"     },  -- §4.8: "gps"
        { name = "ts-refclk", source = "gal"     },  -- §4.8: "gal"
        { name = "ts-refclk", source = "glonass" },  -- §4.8: "glonass"

        -- a=mediaclk (RFC 7273 §5.4) — every mode variant.
        { name = "mediaclk", mode = "sender" },           -- §5.4: "sender"
        { name = "mediaclk", mode = "IEEE1722",           -- §5.4: "IEEE1722="
          stream_id = "00-11-22-FF-FE-33-44-55" },        --        + AVB stream-id (EUI-64)
        { name = "mediaclk", mode = "x-vendor-clock",     -- §5.4: mediaclock-ext
          value = "opaque" },

        -- Forward-compat at media level — same {name, value?} carrier
        -- as session-level. The library will round-trip these
        -- byte-identically without ever resolving them to a schema.
        { name = "x-experimental-attr", value = "data" },
        { name = "x-experimental-flag" },
      },
    },
  },
})

-- ─── Pretty-print the Lua table ─────────────────────────────────────────────

local function hr(label)
  print("\n" .. ("━"):rep(72))
  print("  " .. label)
  print(("━"):rep(72))
end

hr("1. The doc as a Lua table (rendered via dkjson with indent)")
print(dkjson.encode(doc, { indent = true, keyorder = {
  "version", "origin", "session", "media",
  "username", "sess_id", "sess_version", "net_type", "addr_type",
  "unicast_address", "name", "info", "uri", "emails", "phones",
  "connection", "bandwidths", "time_descriptions", "time_zones",
  "attributes", "media", "port", "port_count", "proto", "fmts",
} }))

-- ─── Render to SDP text ─────────────────────────────────────────────────────

hr("2. The same doc rendered with doc:to_sdp()")
local sdp_text, serr = doc:to_sdp()
assert(sdp_text, serr and serr.message)
io.write(sdp_text)

-- ─── Round-trip check ──────────────────────────────────────────────────────
-- Parse the emitted text and deep-compare to the source doc. If this
-- assertion ever fails, a shape contract for one of the listed
-- attributes has drifted — the kitchen sink is the canary.

-- Per GUIDE.md: nil and `{}` are equivalent for optional array fields
-- (parser fills absent arrays with `{}`; serializer renders neither). So
-- we treat nil-on-one-side as equal to an empty table on the other.
local function is_empty_table(x) return type(x) == "table" and next(x) == nil end
local function nil_or_empty(x) return x == nil or is_empty_table(x) end

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
    local ok, why = deep_equal(v, b[k], path .. "." .. tostring(k))
    if not ok then return false, why end
  end
  for k, v in pairs(b) do
    if a[k] == nil and not nil_or_empty(v) then
      return false, path .. "." .. tostring(k) .. ": present in re-parsed only"
    end
  end
  return true
end

hr("3. Round-trip: parse emitted SDP → deep-compare to source doc")
local reparsed, perr = sdp.parse(sdp_text)
assert(reparsed, perr and perr.message)
local ok, why = deep_equal(doc, reparsed, "doc")
if ok then
  print("  ✓ doc == sdp.parse(doc:to_sdp())")
else
  print("  ✗ drift: " .. why)
  os.exit(1)
end

print("\n" .. ("━"):rep(72))
print("  Done. " .. select(2, sdp_text:gsub("\r\n", "")) ..
      " lines of SDP, " ..
      #doc.session.attributes .. " session-level + " ..
      (#doc.media[1].attributes + #doc.media[2].attributes) ..
      " media-level attributes round-tripped cleanly.")
print(("━"):rep(72) .. "\n")
