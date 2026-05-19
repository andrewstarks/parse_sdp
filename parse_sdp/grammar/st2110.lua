-- parse_sdp.grammar.st2110 — SMPTE ST 2110 tier grammar.
--
-- Composed via `base.extend(base, overrides)`. ST 2110 narrowings are
-- expressed as overrides of base leaf rules — the value-set restrictions
-- live IN the grammar, not as a post-parse Lua walk over the captured doc.
--
-- Phase 6.A — composition shell.
-- Phase 6.B — per-encoding rtpmap narrowings (this commit).
-- Phase 6.C — fmtp parameter narrowings.
-- Phase 6.D — required-attribute presence (ts-refclk, mediaclk, ptime).
-- Phase 6.E — cross-stream invariants (RFC 7104 group:DUP, RFC 2022-7).
--
-- Internal entry point only. The public `sdp.parse(text, "st2110")` continues
-- to use the 1.0 validator chain until Phase 9 (REFACTOR-PLAN.md §5).

local lpeg   = require("lpeg")
local base   = require("parse_sdp.grammar.base")
local errors = require("parse_sdp.errors")

local P, V, C, Cc, Cg, Cb, Ct, Cmt, Carg =
  lpeg.P, lpeg.V, lpeg.C, lpeg.Cc, lpeg.Cg, lpeg.Cb, lpeg.Ct, lpeg.Cmt, lpeg.Carg

local SP = P(" ")

-- ── Semantic checks ────────────────────────────────────────────────────────
-- Cross-section invariants the grammar alone can't express. Each check
-- inspects the captured doc and emits findings via errors.record. Functions
-- are appended to base.semantic_checks via the overrides table below.

-- ST 2110-20:2022 §7.2 (required parameters for raw video fmtp) +
-- ST 2110-21:2022 §8.1 (required TP for every raw video stream). Listed in
-- spec order so that on fail_on_first=true the first absent key emitted
-- matches the order a reader sees in §7.2.
local RAW_VIDEO_REQUIRED_PARAMS = {
  "sampling", "width", "height", "exactframerate", "depth",
  "colorimetry", "PM", "SSN", "TP",
}

-- Walks every media block, finds payload types whose a=rtpmap encoding is
-- `raw`, locates the matching a=fmtp on that PT, and verifies every required
-- parameter is present. If no fmtp exists for a raw PT, the first required
-- key (sampling) is reported missing — the §7.2 SHALL on the parameter
-- itself is also a SHALL on the fmtp's existence.
local function check_raw_video_fmtp_required(doc, ctx)
  for i, m in ipairs(doc.media) do
    -- Build PT → encoding map from this media block's rtpmap attributes.
    local raw_pts = {}
    for _, attr in ipairs(m.attributes) do
      if attr.name == "rtpmap" and attr.encoding == "raw" then
        raw_pts[attr.payload_type] = true
      end
    end
    -- Index fmtp attributes by payload type for direct lookup.
    local fmtp_by_pt = {}
    for _, attr in ipairs(m.attributes) do
      if attr.name == "fmtp" then
        fmtp_by_pt[attr.payload_type] = attr
      end
    end
    for pt in pairs(raw_pts) do
      local fmtp = fmtp_by_pt[pt]
      local params = fmtp and fmtp.params or {}
      for _, key in ipairs(RAW_VIDEO_REQUIRED_PARAMS) do
        if params[key] == nil then
          local cont = errors.record(
            ctx,
            "st2110-20.a.fmtp." .. key .. "-required",
            { field_path = string.format(
                "media[%d].attributes[fmtp:pt=%d]", i, pt) })
          if not cont then return false end
        end
      end
    end
  end
  return true
end

-- ── rtpmap encoding narrowings (Phase 6.B) ─────────────────────────────────
--
-- Each known ST 2110 essence encoding has:
--   - a defined m= media type (video for raw / jxsv / smpte291, audio for AM824)
--   - a defined clock-rate set (90000 for the three video encodings; one of
--     {44100, 48000, 96000} for AM824)
--
-- Both narrowings are expressed in-grammar:
--   - encoding-name literal: the branch matches only when the encoding token
--     is exactly the recognised name AND is followed by `/`, so a name like
--     "rawX" still falls through to the default branch.
--   - clock-rate value set: an inline Cmt validates the captured number and
--     records a finding when it falls outside the allowed set.
--   - media-type: a trailing Cmt reads the surrounding `media` capture via
--     `Cb"media"` and records a finding when it doesn't match the encoding's
--     defined media type.
--
-- The branches are gated by a negative lookahead on the default branch so a
-- malformed known-encoding rtpmap (e.g. raw/48000) fails the whole a_rtpmap
-- match rather than backtracking into the generic-encoding form.
--
-- Cb"media" reads the most recent complete group capture named "media" — the
-- one m_value emits inside every media_section Ct. Session-level a=rtpmap is
-- non-conformant per RFC 8866 §6.6 (rtpmap is media-only) and the surrounding
-- grammar never establishes a session-level "media" capture; ST 2110 inherits
-- that scope rule from base.

local function record_rate_and_media(rate_check_id, expected_media, media_check_id)
  return function(_, pos, rate, media, ctx)
    local ok = true
    if rate_check_id and not rate_check_id.set[rate] then
      ok = ok and errors.record(ctx, rate_check_id.id, {})
    end
    if media ~= expected_media then
      ok = ok and errors.record(ctx, media_check_id, {})
    end
    if not ok then return false end
    return pos
  end
end

-- Each rule produces:
--   Cg("encoding")   ← the literal encoding name
--   Cg("clock_rate") ← the parsed number
--   Cg("channels")?  ← optional, when present in the input
-- followed by a trailing Cmt that reads Cb"clock_rate" + Cb"media" + ctx and
-- emits findings via errors.record. The Cmt returns `pos` (no value) so it
-- doesn't add to the surrounding a_value Ct.

local function make_rtpmap_branch(encoding_name, rate_id, expected_media, media_id)
  return P(encoding_name) * Cg(Cc(encoding_name), "encoding") * P("/")
    * Cg(V"rfc8866_pos_int_num", "clock_rate")
    * (P("/") * Cg(V"rfc8866_pos_int_num", "channels")) ^ -1
    * Cmt(Cb"clock_rate" * Cb"media" * Carg(1),
          record_rate_and_media(rate_id, expected_media, media_id))
end

local overrides = {
  rules = {
    -- Override a_rtpmap with branched form: each known-encoding branch
    -- enforces its value-set/clock-rate/media-type SHALLs in-line; an
    -- unknown encoding falls through to the default branch and is captured
    -- with base's permissive shape (silence is not rejection — CLAUDE.md
    -- strictness principle).
    --
    -- Trailing Cmt records ctx.rtpmap_encodings[pt] = encoding so a later
    -- a=fmtp on the same media block can look the encoding up by PT. Each
    -- a= line is wrapped in its own a_value Ct, so a Cb"encoding" from one
    -- line is no longer in scope by the time the next line parses — ctx is
    -- the cross-line carrier.
    a_rtpmap = P("rtpmap:")
        * Cg(Cc("rtpmap"), "name")
        * Cg(V"payload_type", "payload_type") * SP
        * ( V"st2110_rtpmap_raw"
          + V"st2110_rtpmap_jxsv"
          + V"st2110_rtpmap_smpte291"
          + V"st2110_rtpmap_am824"
          + V"st2110_rtpmap_default" )
        * Cmt(Cb"payload_type" * Cb"encoding" * Carg(1),
              function(_, pos, pt, enc, ctx)
                if ctx then
                  ctx.rtpmap_encodings = ctx.rtpmap_encodings or {}
                  ctx.rtpmap_encodings[pt] = enc
                end
                return pos
              end),

    st2110_rtpmap_raw = make_rtpmap_branch(
      "raw",
      { id = "st2110-20.a.rtpmap.raw-clock-rate", set = { [90000] = true } },
      "video", "st2110-20.a.rtpmap.raw-media-type"),

    st2110_rtpmap_jxsv = make_rtpmap_branch(
      "jxsv",
      { id = "st2110-22.a.rtpmap.jxsv-clock-rate", set = { [90000] = true } },
      "video", "st2110-22.a.rtpmap.jxsv-media-type"),

    st2110_rtpmap_smpte291 = make_rtpmap_branch(
      "smpte291",
      { id = "st2110-40.a.rtpmap.smpte291-clock-rate", set = { [90000] = true } },
      "video", "st2110-40.a.rtpmap.smpte291-media-type"),

    st2110_rtpmap_am824 = make_rtpmap_branch(
      "AM824",
      { id = "st2110-31.a.rtpmap.am824-clock-rate-set",
        set = { [44100] = true, [48000] = true, [96000] = true } },
      "audio", "st2110-31.a.rtpmap.am824-media-type"),

    -- Default branch: any encoding token NOT a known ST 2110 essence
    -- followed by `/`. The negative lookahead prevents a malformed
    -- known-encoding rtpmap (e.g. raw/48000) from falling through here —
    -- if the input starts with a known encoding name + `/`, the lookahead
    -- fails the default branch and the corresponding known-encoding branch
    -- is the only one that can claim the match.
    st2110_rtpmap_default =
        -V"st2110_known_rtpmap_encoding"
        * Cg(V"rfc8866_token", "encoding") * P("/")
        * Cg(V"rfc8866_pos_int_num", "clock_rate")
        * (P("/") * Cg(V"rfc8866_pos_int_num", "channels")) ^ -1,

    st2110_known_rtpmap_encoding =
        (P("raw") + P("jxsv") + P("smpte291") + P("AM824")) * P("/"),

    -- ── fmtp parameter-form narrowings (Phase 6.C.B) ─────────────────────
    -- ST 2110-20:2022 §7.1: "Each media type parameter entry shall be
    -- constructed as either a <name>=<value> pair, with no whitespace
    -- within the name or value or between the name, equal sign, and
    -- value; a <name> standalone declaration, with no whitespace within
    -- the name." Scope: only when the surrounding rtpmap encoding is
    -- `raw`. Other ST 2110 essence specs (-22, -30, -31, -40) do not
    -- carry this prohibition; they keep base's loose form.
    --
    -- Encoding-gated alternation: the first branch matches only when this
    -- fmtp's payload_type was previously recorded (via a_rtpmap's trailing
    -- Cmt) as carrying encoding="raw" AND the input has no whitespace
    -- around `=`; the second branch matches when the recorded encoding is
    -- anything else (including absent — static PT with no rtpmap) and uses
    -- base's loose `fmtp_params_branch`. A `raw` fmtp with whitespace fails
    -- both branches → a_fmtp fails → match returns nil with the finding in
    -- ctx.findings (under fail_on_first=true).
    --
    -- The lookup is ctx-based rather than Cb-based because the rtpmap and
    -- fmtp lines each close their own a_value Ct, so the rtpmap's encoding
    -- Cg is no longer in scope at fmtp time. ctx.rtpmap_encodings is the
    -- cross-line carrier (populated in a_rtpmap above).
    a_fmtp = P("fmtp:")
        * Cg(Cc("fmtp"), "name")
        * Cg(V"payload_type", "payload_type") * SP
        * ( V"fmtp_st2110_raw_payload"
          + V"fmtp_payload_non_raw" ),

    fmtp_st2110_raw_payload =
        Cmt(Cb"payload_type" * Carg(1), function(_, pos, pt, ctx)
          local enc = ctx and ctx.rtpmap_encodings
                            and ctx.rtpmap_encodings[pt]
          return enc == "raw" and pos
        end)
        * V"fmtp_st2110_raw_params",

    fmtp_payload_non_raw =
        Cmt(Cb"payload_type" * Carg(1), function(_, pos, pt, ctx)
          local enc = ctx and ctx.rtpmap_encodings
                            and ctx.rtpmap_encodings[pt]
          return enc ~= "raw" and pos
        end)
        * ( V"fmtp_params_branch" + V"fmtp_raw_branch" ),

    -- Strict params branch for `raw`: each kv-pair captures the
    -- (key, ws_before_eq, ws_after_eq, value) tuple; a Cmt examines the
    -- whitespace captures, records sdp st2110-20.a.fmtp.no-whitespace-
    -- around-equals when either side is non-empty, and otherwise yields
    -- the {key, value} pair the outer transform expects.
    fmtp_st2110_raw_params =
        Cg(
            Ct(V"fmtp_st2110_raw_entry"
              * (V"fmtp_sep" * V"fmtp_st2110_raw_entry") ^ 0)
              / base.fmtp_entries_to_params,
            "params"
          )
        * V"fmtp_trailing_sep_record" ^ -1
        * #V"line_end_chars",

    fmtp_st2110_raw_entry =
        V"fmtp_st2110_raw_kv_pair" + V"fmtp_flag",

    fmtp_st2110_raw_kv_pair =
        Cmt(
          Ct(
            C(V"fmtp_key_chars" ^ 1)
            * C(V"fmtp_hws" ^ 0)
            * P("=")
            * C(V"fmtp_hws" ^ 0)
            * C(V"fmtp_val_chars" ^ 0)
          ) * Carg(1),
          function(_, pos, captured, ctx)
            local key, ws_l, ws_r, val =
              captured[1], captured[2], captured[3], captured[4]
            if #ws_l > 0 or #ws_r > 0 then
              local cont = errors.record(
                ctx, "st2110-20.a.fmtp.no-whitespace-around-equals", {})
              if not cont then return false end
            end
            return pos, { key, val }
          end),
  },

  semantic_checks = {
    check_raw_video_fmtp_required,
  },
}

return base.extend(base, overrides)
