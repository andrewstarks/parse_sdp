-- spec.support — shared test helpers and fixture constants.
--
-- Three things are duplicated across the per-tier grammar specs often
-- enough to live in one place:
--   * finding_for(ctx, id) — the standard finding-by-id lookup.
--   * TIMING_TS_REFCLK / TIMING_MEDIACLK — RFC 7273 attributes that
--     every ST 2110-tier SDP needs (§8.2 + §8.3) to pass the per-block
--     timing-attribute SHALLs unrelated to whatever a test is asserting.
-- File-specific fixture builders (build, build_video_sdp, etc.) stay
-- in their owning spec — they encode per-tier defaults that don't
-- generalize.

local M = {}

-- Return the first finding with the matched id, or nil.
function M.finding_for(ctx, id)
  for _, f in ipairs(ctx and ctx.findings or {}) do
    if f.id == id then return f end
  end
  return nil
end

-- ST 2110-10:2022 §8.2: "All stream descriptions shall have a ts-refclk
-- attribute." localmac is the minimal RFC 7273 §4.5 form (no PTP /
-- network state required).
M.TIMING_TS_REFCLK = "a=ts-refclk:localmac=00-11-22-33-44-55"

-- ST 2110-10:2022 §8.3: "All stream descriptions shall have a media-level
-- mediaclk attribute." `sender` (RFC 7273 §5.1) is the minimal form.
M.TIMING_MEDIACLK = "a=mediaclk:sender"

return M
