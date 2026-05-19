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

local P, V, Cc, Cg, Cb, Cmt, Carg =
  lpeg.P, lpeg.V, lpeg.Cc, lpeg.Cg, lpeg.Cb, lpeg.Cmt, lpeg.Carg

local SP = P(" ")

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
    a_rtpmap = P("rtpmap:")
        * Cg(Cc("rtpmap"), "name")
        * Cg(V"payload_type", "payload_type") * SP
        * ( V"st2110_rtpmap_raw"
          + V"st2110_rtpmap_jxsv"
          + V"st2110_rtpmap_smpte291"
          + V"st2110_rtpmap_am824"
          + V"st2110_rtpmap_default" ),

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
  },
}

return base.extend(base, overrides)
