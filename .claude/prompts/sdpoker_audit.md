# Prompt — SDPoker / AMWA Regression Audit

Use this prompt to brief a fresh Claude session that needs to (a) confirm the
parser still covers every AMWA / Streampunk SDPoker / JT-NM Tested finding
the project has tracked, (b) check whether recent commits silently undid any
of that work, and (c) refresh the catalogue.

---

## Brief

You are working in the `parse_sdp` Lua/LPEG repo at
`/Users/andrewstarks/src/parse_sdp`. This repo has accumulated a backlog of
findings from AMWA SDPoker, the Streampunk SDPoker fork, JT-NM Tested, and
BCP-006-01 review feedback. Each finding has either landed a parser change,
been encoded as a regression-only test, or was deliberately not adopted
because primary spec text doesn't support it.

Your task is to verify the backlog is still covered after recent work, surface
any divergence, and update the index. Do **not** add or relax checks without
spec grounding — the project's strictness is spec-bounded, not opinion-bounded.

## What to read first (in order)

1. `/Users/andrewstarks/src/parse_sdp/SDPOKER_BACKLOG.md` — the canonical index
   of every finding, with source identifier, spec citation, resolution, and
   regression-test link. Start here. Treat each row as a claim to re-verify.
2. `/Users/andrewstarks/src/parse_sdp/CLAUDE.md` — the **Validation Strictness
   Principle** and the **Spec Verification Protocol** govern every decision.
   Read them before forming any verdict.
3. `/Users/andrewstarks/src/parse_sdp/PLAN.md` — current state, deferred
   items (especially "Known Deferred Items" — those are *not* bugs).
4. `/Users/andrewstarks/src/parse_sdp/CHANGELOG.md` `[Unreleased]` — the
   per-commit story behind the most recent audit (F1–F11, N1–N13, D1–D2).

## Files you will touch

- `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua` — single-file parser.
  SDPoker citations are inline; grep for them.
- `/Users/andrewstarks/src/parse_sdp/spec/st2110_spec.lua` — almost every
  SDPoker-cited regression test lives here.
- `/Users/andrewstarks/src/parse_sdp/spec/sdp_spec.lua`,
  `/Users/andrewstarks/src/parse_sdp/spec/ipmx_spec.lua`,
  `/Users/andrewstarks/src/parse_sdp/spec/errors_spec.lua`,
  `/Users/andrewstarks/src/parse_sdp/spec/cli_spec.lua` — other test files;
  search them too.
- `/Users/andrewstarks/src/parse_sdp/spec_conformance/manifest.lua` —
  pinned upstream SHAs and per-fixture test plan. Negative tests use
  `expect = "fail"` with `expect_spec_ref`.
- `/Users/andrewstarks/src/parse_sdp/spec_conformance/allowlist.lua` —
  divergence-pending list. Goal state: empty.
- `/Users/andrewstarks/src/parse_sdp/spec_conformance/conformance_spec.lua` —
  runner. Read once to understand pass/fail/allowlist semantics.
- `/Users/andrewstarks/src/parse_sdp/spec_conformance/README.md` — suite docs.
- `/Users/andrewstarks/src/parse_sdp/SDPOKER_BACKLOG.md` — update if you add
  rows, change resolutions, or move citations.
- `/Users/andrewstarks/src/parse_sdp/cspell.json` — add new technical terms
  here if the spell-checker flags them; verbatim RFC/SMPTE tokens are not
  errors.
- `/Users/andrewstarks/src/parse_sdp/GUIDE.md` — user-facing doc; sync if
  behavior changes.

## Grep commands you will reuse

```sh
# Inventory of SDPoker citations in code + tests:
grep -nE "AMWA #|Streampunk #|JT-NM|sdpoker" \
  /Users/andrewstarks/src/parse_sdp/spec/st2110_spec.lua \
  /Users/andrewstarks/src/parse_sdp/parse_sdp.lua

# All findings with surrounding context (broader):
grep -rn -E "sdpoker|SDPoker|AMWA|Streampunk|JT-NM|BCP-006" \
  --include="*.lua" --include="*.md" \
  /Users/andrewstarks/src/parse_sdp/ \
  | grep -v /\.git/ | grep -v /\.cache/

# Verify a specific finding ID still has a test:
grep -n "AMWA #11\|Issue #11\|JT-NM" \
  /Users/andrewstarks/src/parse_sdp/spec/st2110_spec.lua
```

## Test commands

```sh
busted /Users/andrewstarks/src/parse_sdp/spec/              # hermetic — must pass 100%
busted /Users/andrewstarks/src/parse_sdp/spec_conformance/  # AMWA upstream fixtures
```

The hermetic suite is the primary CI gate. The conformance suite is opt-in
but allowlist-empty is the goal state — any divergence is a real signal.

## Spec source-of-truth

Follow CLAUDE.md "Spec Verification Protocol" rule 1 for where to find
primary spec text (markdown directories preferred; PDF fallback; RFCs via
WebFetch). Quote the SHALL clause verbatim in the parser comment, the test,
and the CHANGELOG entry.

CLAUDE.md "Spec Verification Protocol" rule 1 forbids substituting an IANA
registration, downstream RFC, AMWA NMOS profile, or reference implementation
for primary SMPTE text. Honor that rule.

## Upstream sources (pinned in spec_conformance/manifest.lua)

- `AMWA-TV/nmos-testing` — current pin in `manifest.lua`. Bump deliberately.
- `AMWA-TV/bcp-006-01` — current pin in `manifest.lua`. Bump deliberately.
- `AMWA-TV/sdpoker` — original AMWA repo (likely archived). Issue/PR numbers
  in the catalogue refer to its issue tracker.
- `Streampunk/sdpoker` — active fork. Separate issue numbering.

Before assuming anything is "still relevant", check the upstream SHAs against
what's in `manifest.lua`. If upstream has advanced significantly, ask the
user whether to bump the pin (see `spec_conformance/README.md` "Refreshing").

## Workflow

1. **Inventory.** Run the grep commands above. Confirm every row in
   `SDPOKER_BACKLOG.md` has at least one matching test reference. Confirm
   no test cites a finding that's missing from the catalogue.
2. **Verify.** Run both test suites. Both must be green. If either fails,
   stop and report — do not change parser behavior.
3. **Cross-check recent commits.** `git log --oneline -30` and skim diffs
   for anything that touched checks the SDPoker rows depend on. Any change
   to a check must be either (a) accompanied by a CHANGELOG note citing
   primary spec text, or (b) flagged for the user.
4. **Refresh the catalogue.** If you find a new SDPoker-cited test that
   isn't in the index, add a row. If a row's regression test moved, update
   the line link.
5. **Commit.** One commit per logical change. Use the existing commit
   convention: subject under 70 chars, body cites the spec clause, sign
   with `Co-Authored-By: Claude Opus 4.7 (1M context) <noreply@anthropic.com>`.

## Things the strictness principle forbids — do not be tempted

- "Most senders do X, so we should require X." — No. Need a SHALL.
- "An IANA registration says Y is optional, but the SMPTE spec might
  tighten it." — Read the SMPTE spec. Don't assume either direction.
- "This combination is physically silly." — Out of scope. The validator
  checks conformance, not physical plausibility.
- "Reference implementation Z does it this way." — Evidence, not
  authority. Need primary spec text.

## Two known traps

- **Bullet-scope binding** (CLAUDE.md Spec Verification Protocol rule 6):
  IPMX JPEG-XS Profile §6.1.4's bullets bind to "shall populate the
  RTCP Media Info Block, including:" — not to the section heading "Required
  Sender Signaling (Media Info Block & SDP)". Reading them as SDP fmtp
  requirements is the failure mode this rule prevents. Audit D2 (`fbblevel`)
  came from this same misreading.
- **§9 ABNF vs §5.7 prose conflicts** (RFC 8866 IPv6 multicast `/N`):
  the audit's F7 reframe is the canonical example. When a spec has both
  prose and ABNF, the ABNF is authoritative for value form; the prose may
  be qualified by it.

## Output expectations

When you're done, report:

- "Both suites green: 777 hermetic + 10 conformance" (or current numbers).
- "SDPOKER_BACKLOG.md has N rows; all M tests located and passing."
- Any new findings + the spec citation that grounds them, OR
- Any allowlist additions you made, with reason + spec_ref + a plan to
  resolve.
- Whether you bumped the upstream SHAs in `spec_conformance/manifest.lua`,
  and what changed.

If you stopped without changing code because a finding didn't survive
verification, **say so explicitly**. That is a successful outcome, not a
failed one.
