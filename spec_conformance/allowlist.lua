-- Fixtures we have reviewed and consciously decided to accept-as-failing,
-- keyed by manifest `id`. Each entry MUST carry a `reason` and a `spec_ref`.
--
-- This list is for *open questions* — divergences where we have not yet
-- confirmed whether our parser is over-strict or the upstream fixture is
-- non-conformant. When the question is resolved:
--   • If the parser was wrong → fix the parser; remove the entry.
--   • If the fixture is wrong → move the fixture to `expect = "fail"` in
--     manifest.lua with the citing clause; remove the entry.
--
-- This is the goal state: empty. All previously suspected over-strictness
-- has been resolved against primary spec text (see CHANGELOG).

return {}
