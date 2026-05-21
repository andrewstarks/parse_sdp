# Plan

## Guiding Principles

- **Test first.** Every feature begins with failing tests.
- **Strict by spec.** Every validation check cites explicit normative spec
  text — a "shall" / "MUST", a "shall not" / "MUST NOT", or a defined value
  form / value set. Spec silence is not a reason to reject.
- **Layered.** Each tier (RFC 8866 → ST 2110 → IPMX) extends the previous;
  it never replaces it. RFC 8866 obsoletes RFC 4566.
- **Tight.** If a file is growing, stop and refactor before continuing.
  Prefer fewer, well-named things.
- **Fail loudly.** Parse failures report exactly where and why.
- **Round-trip.** `doc:to_sdp()` must produce output that re-parses to an
  equivalent table. This is a hard invariant.

## Tech Stack

| Concern | Choice |
| --- | --- |
| Language | Lua 5.5 |
| Parsing | LPEG |
| JSON | dkjson (pure Lua, LuaRocks) |
| Tests | busted |
| Container | Docker (Lua 5.5 + LuaRocks base image) |

## Test Command

```sh
busted spec/                  # hermetic suite (1162 tests)
busted spec_conformance/      # opt-in pinned AMWA + SDPoker fixtures
```

## Current State

1.1.1 shipped on 2026-05-21. 1162 hermetic tests passing. Every validation
check is grounded in explicit spec text; no opinion-based checks remain.
Public API surface is `parse_sdp/init.lua` (library) + `bin/parse_sdp`
(CLI). Grammar tier under `parse_sdp/grammar/{base,st2110,ipmx}.lua`;
serializer under `parse_sdp/serialize.lua`; registry under
`parse_sdp/errors.lua`. The 1.0 monolith has been deleted.

Recent doc additions (post-1.1.1):

- GUIDE.md "Producer Workflow" section + runnable
  `examples/producer_walkthrough.lua` — the build-then-validate loop
  for device manufacturers / SDK engineers.
- Four runnable kitchen-sink references in `examples/`:
  - `kitchen_sink.lua` (RFC 8866 + base RFC extensions)
  - `kitchen_sink_st2110.lua` (every ST 2110 attribute, asserts `is_st2110()`)
  - `kitchen_sink_ipmx.lua` (every IPMX TR-10 extension, asserts `is_ipmx()`)
  - `kitchen_sink_conflicts.lua` (eight per-conflict micro-fixtures)
- GUIDE.md "Kitchen-sink references" subsection (with the table of
  four hex-format conventions SDP uses).

## Next pass — diagnostic CLI + README polish

A field engineer with a customer's SDP, a compliance tester verifying a
product, and a SaaS engineer wiring `parse_sdp` into a service all want
slightly different things from the CLI. The library already produces
everything they need (structured findings with `id` / `spec_ref` / line+col,
introspectable `sdp.checks()` registry, conformance suite under
`spec_conformance/`); the gap is **CLI surface area** and **first-impression
positioning**. This pass closes both.

Pick items in order — each builds on the prior. Every CLI subcommand
should ship with: spec tests in `spec/cli_spec.lua`, a section in
GUIDE.md "CLI Reference", and a row in README's CLI example block.

### N.1 — `parse_sdp validate` subcommand

**Why.** The natural CLI invocation for "is this a valid ST 2110 SDP?" is
`parse_sdp validate --mode st2110 file.sdp`. Today the only way to do
this is `parse_sdp to_json --mode st2110 file.sdp >/dev/null`, ignore
stdout, read stderr, and inspect exit code. That buries the diagnostic
intent inside a converter and signals "this tool is for producing JSON,
not for telling me about my SDP."

**What it does.**

- Reads SDP from a file path (or stdin if `-` or no positional arg).
- Validates at `--mode` (default `sdp`; also accepts `st2110`, `ipmx`).
- On success: prints `OK` to stdout (one line, no JSON), exits 0.
- On failure: prints the human-formatted error block (same renderer as
  the other subcommands use via `errors.format`) to stderr, exits 1.
- Pairs with `--all-findings` (see N.3) to dump *every* finding the
  validator collected, not just the first error.

**Where it lives.**

- New subcommand in `bin/parse_sdp` (argparse :command()).
- Reuses `sdp.parse(text, mode, { fail_on_first = not opts.all_findings })`.
- No new library code — pure CLI plumbing.

**Tests.** `spec/cli_spec.lua` — at least: valid SDP at each tier exits 0,
invalid SDP exits 1 with formatted error on stderr, stdin works with `-`,
unknown mode rejected with a non-zero exit + helpful message.

**Doc.** GUIDE.md § CLI Reference: new subsection right after `to_json`.
README: add the validate line to the CLI Example block.

### N.2 — `parse_sdp diagnose` subcommand

**Why.** A field engineer working a customer's SDP often doesn't know
which tier the customer *claims* compliance with — only that the stream
isn't working. The natural question is "what tier does this pass at?"

**What it does.** Runs validation at every tier and reports a tier
ladder. Example output:

```text
$ parse_sdp diagnose customer.sdp
  ✓ RFC 8866 (base SDP)
  ✗ SMPTE ST 2110
      sdp.m.ts-refclk-required
      media block must include an 'a=ts-refclk' attribute
      ST 2110-10:2022 §8.2
      at media[1].attributes[ts-refclk]
  ✗ IPMX (VSF TR-10)
      (inherits ST 2110 failure — fix it first)
```

- Always exits 0 (the diagnostic ran; the *file* may or may not be valid
  at a tier, but that's data, not error).
- For each tier the report shows: pass/fail glyph, tier name, and on
  failure the structured finding's `id`, `message`, `spec_ref`, and
  `field_path` indented under it.
- The IPMX line should say "(inherits ST 2110 failure)" when the
  preceding ST 2110 check failed — running IPMX validation under the
  hood will reproduce the same finding, but the report should be
  honest that fixing ST 2110 is the prerequisite.

**Where it lives.** `bin/parse_sdp` new subcommand. The "inheritance"
hint is just a check in the CLI code: if the ST 2110 finding's `id` is
also produced by the IPMX run, collapse the IPMX line.

**Tests.** `spec/cli_spec.lua` — at minimum: an RFC-8866-only-valid SDP
shows ✓/✗/✗ with both ✗ rows populated; an ST-2110-valid SDP shows
✓/✓/✗ with the IPMX row carrying a real IPMX-tier finding; a
malformed-at-base SDP shows ✗/✗/✗ with the base finding on the first
row and a clear "inherits" hint on the other two.

**Doc.** GUIDE.md § CLI Reference: new subsection. README's CLI Example
block gets a line for this — it's probably the most quotable subcommand
for first-impression positioning.

### N.3 — `--all-findings` flag

**Why.** Default `sdp.parse` returns at the first error finding (the
public-API contract: `nil, err`). For a field engineer, "show me
everything wrong" is the natural ask — they don't want to re-run after
every fix. The library already supports this via `fail_on_first = false`
combined with policy demotion (documented in GUIDE.md § "Findings,
warnings, and errors"), but the CLI doesn't expose it.

**What it does.** A `--all-findings` flag on `to_json`, `validate`, and
`diagnose`:

- Internally sets `opts.fail_on_first = false` and demotes every
  registered error-severity check to `"warn"` in `opts.policy`.
- Parse proceeds to completion; every finding lands in `doc:findings()`.
- Output: instead of one error, the CLI prints a numbered list of every
  finding (id, message, spec_ref, line:col) in the order they were
  recorded.
- Exit code: 0 if all findings would have been warnings under default
  severity, 1 if any were errors (the severity is computed against the
  default policy — `--all-findings` only changes *collection*, not
  whether the file is "really" valid).

**Where it lives.** `bin/parse_sdp` argparse global flag; CLI code
constructs the demotion policy by iterating `sdp.checks()` and writing
`policy[c.id] = "warn"` for every `c.default_severity == "error"`.

**Tests.** `spec/cli_spec.lua` — a file with multiple errors shows all
of them in the output (count matches the registry's expected hits);
a clean file shows nothing-new behaviour (`--all-findings` is a no-op).

**Doc.** GUIDE.md § CLI Reference flag table; one line in README CLI
example.

### N.4 — `parse_sdp checks` subcommand

**Why.** Compliance testers and downstream tooling want machine-readable
access to the registry — "every check the validator enforces, what
clause it cites, what its severity is." Today this is a Lua-only API
(`sdp.checks()`). Exposing it via the CLI is one of the highest-leverage
moves for the compliance-tester persona.

**What it does.** Dumps the registry, with filtering and formatting
options. Default format is a tabular human-readable list; `--format json`
emits the full registry as a JSON array (for piping into `jq`);
`--filter <pattern>` matches against `id` for selective lookup.

```text
$ parse_sdp checks --filter 'sdp.a.ts-refclk.*'
sdp.a.ts-refclk.ptp-malformed                error  RFC 7273 §4.8 (ptp / ptp-server / EUI64 ABNF)
sdp.a.ts-refclk.traceable-mix                error  RFC 7273 §4.8

$ parse_sdp checks --format json --filter 'tr-10-1.*' | jq '.[] | .id'
"tr-10-1.a.fmtp.htotal-invalid-value"
"tr-10-1.a.fmtp.htotal-required"
...
```

- Default tabular: `id   severity   spec_ref` (column-aligned).
- `--format json`: array of registry entries, one object per check,
  with all fields (`id`, `kind`, `default_severity`, `code`,
  `message_template`, `spec_ref`, `verified`, `verification_note`).
- `--filter <pattern>`: Lua-pattern (or simple glob — pick one and
  document it) match against `id`. Multiple filters AND together.
- `--unverified`: only checks with `verified=false` (matters to
  compliance testers — "what checks are pending primary-source
  re-verification?"). The library already tracks this; just surface it.
- Exit code 0; 1 only on usage errors (e.g. malformed `--format`).

**Where it lives.** `bin/parse_sdp` new subcommand. Pure CLI plumbing
over `sdp.checks()`.

**Tests.** `spec/cli_spec.lua` — default format is parseable, `--format
json` decodes cleanly to an array matching `sdp.checks()`, filter works,
`--unverified` matches the registry's `verified=false` rows.

**Doc.** GUIDE.md § CLI Reference: new subsection. Also worth a short
GUIDE.md § "Compliance audit workflow" using `parse_sdp checks` +
`parse_sdp validate --all-findings` as the building blocks. README:
mention briefly in the CLI block.

### N.5 — `parse_sdp conformance` subcommand

**Why.** `spec_conformance/` runs against pinned AMWA-TV + SDPoker
fixtures. Today the way to find out "does this version pass the
reference suite?" is to run `busted spec_conformance/` and read busted's
pass/fail dots. For an outside evaluator (or a CI gate, or anyone
quoting "this build passes the AMWA suite"), a single-line summary
suitable for piping into a report is the right shape.

**What it does.**

```text
$ parse_sdp conformance
AMWA-TV fixtures (pinned @ <commit>):       10/10 ✓
SDPoker valid fixtures (pinned @ <commit>): 47/47 ✓
SDPoker invalid fixtures (pinned @ <commit>): 32/32 correctly rejected
Total: 89/89 ✓
```

- Reuses `spec_conformance/manifest.lua` + `conformance_spec.lua`
  logic without going through busted — call the underlying
  fetcher/runner module directly from the CLI.
- One line per fixture group; final aggregate line.
- Exits 0 only if everything passes; 1 otherwise (output then includes
  per-failure detail beneath the affected group).
- A `--verbose` flag enumerates each fixture name + verdict.

**Where it lives.** `bin/parse_sdp` new subcommand. The logic in
`spec_conformance/conformance_spec.lua` may need a small extraction to
a plain Lua module so the CLI can call it without depending on busted.

**Tests.** `spec/cli_spec.lua` — at minimum a smoke test that running
the subcommand prints something parse-able and exits with a sensible
code. The substance of "did it actually work" is already covered by
`busted spec_conformance/`.

**Doc.** GUIDE.md gets a "Conformance suite" section explaining what
the pinned fixtures are and how to interpret the verdict. README adds
the line + badge-able output to the CLI Example block.

### N.6 — README first-impression polish

**Why.** Today the README opens with "A Lua 5.3-5.5 library for parsing,
validating, and serializing SDP files…" — accurate, but doesn't tell
a reader within 30 seconds whether the project is for *them*. A field
engineer scanning won't immediately see "this will tell me exactly
what's wrong with this SDP and which spec clause it violates." A
compliance tester won't immediately see "every check carries a
primary-source citation."

**What changes.**

- Add a 3-line "Who is this for?" stanza near the top, just under the
  one-paragraph intro. Three personas (field troubleshooting, compliance
  verification, SDK/product integration), one sentence each.
- Add a small CLI demo snippet showing realistic error output (the
  1.0-style carrot highlight + `err.id` + `err.spec_ref`). The
  `examples/st2110/invalid/03_missing_fmtp.sdp` fixture run via
  `parse_sdp validate --mode st2110` (once N.1 lands) is the right
  source.
- Keep the existing Features bullet list (it's useful) but reorder so
  spec-citation + structured-error points come first.

**Where it lives.** README.md, between the intro and the existing
Features section. Should add ~15-25 lines.

**Tests.** N/A (doc-only).

### N.7 — Troubleshooting recipes (GUIDE.md)

**Why.** A field engineer with an unfamiliar `err.id` wants "what does
this usually mean in the wild?" The error message says *what* the
validator found; a troubleshooting note can add *why this usually
happens* and *what to check next*. **Keep this tight** — the user
explicitly asked not to invent edge cases. Use real cases sourced from:

- The [SDPoker repository](https://github.com/AMWA-TV/sdpoker) — its
  test fixtures + issues + PRs are the canonical "things real senders
  get wrong" corpus. Search for closed issues with "fixed" labels and
  for the fixtures named `*_invalid*` in the SDPoker repo.
- The [AMWA nmos-testing repo](https://github.com/AMWA-TV/nmos-testing) —
  similar corpus from JT-NM Tested.
- The 1.1.1 incident itself: 5-octet PTP GMID. Real-world, recently
  fixed, has a citable `err.id`.

**What changes.** New GUIDE.md section "Troubleshooting" near the end
(after Serialization, before Test Suite Organization). Format: a small
table of *the most commonly seen errors in real-world senders*,
keyed by `err.id`, with one column for "common cause" and one for
"what to check on the device side." Cap at 6-8 entries — better tight
and useful than exhaustive.

Suggested seed entries (verify each against the SDPoker / AMWA-testing
corpora before adding):

| err.id | Common cause | Check |
| --- | --- | --- |
| `sdp.a.ts-refclk.ptp-malformed` | Device emitting a non-EUI-64 GMID (5- or 6-octet form) | Provisioning logic for the PTP grandmaster ID; must be exactly 8 hex octets |
| `sdp.c.ipv4-multicast.ttl-required` | IPv4 multicast c= line without /TTL — common when porting from RFC 4566 examples that pre-date strict ABNF | Append `/64` or `/127` per ST 2110-10 §6.5 |
| `st2110-20.a.fmtp.sampling-required` | Raw video fmtp missing `sampling=` — happens when the device falls back to JPEG-XS-style defaults on a raw stream | Check rtpmap encoding vs fmtp param set |
| `tr-10-1.a.fmtp.marker-required` | IPMX fmtp without the bare `IPMX` flag — typical when porting an ST 2110 SDP to IPMX | Add `;IPMX` to the fmtp params |
| `sdp.a.ts-refclk.traceable-mix` | A device with both PTP-traceable and PTP-not-traceable ts-refclk lines at the same level | One source-of-truth per scope |

**Where it lives.** GUIDE.md § Troubleshooting (new section). Cross-link
to the error registry CLI (N.4) and to `parse_sdp.checks()`.

**Tests.** N/A (doc-only). But the `err.id` strings in the table should
all exist in the registry — add a `spec/library_spec.lua` test
asserting that every cited `err.id` is in `sdp.checks()` so the
documentation can't go stale silently.

### Future (lower priority — track here, don't schedule yet)

- **Audit-trail export.** A compliance-tester workflow: run validation
  against a corpus of vendor SDPs and emit CSV / JSON of `(file, tier,
  pass/fail, err.id, err.spec_ref)`. The CLI primitives from N.1–N.4
  are enough to build this externally with shell + jq; an integrated
  `parse_sdp audit <directory>` subcommand would package it. Defer
  until the N.1–N.5 work is in users' hands and the actual ergonomics
  ask is clearer.

## Next phase: per-test citation labels in `it` names

(Pre-existing item — orthogonal to the diagnostic-CLI work above.
Mechanical pass over the three standards-tied spec files.)

Every `it` block in `spec/grammar_base_spec.lua`,
`spec/grammar_st2110_spec.lua`, and `spec/grammar_ipmx_spec.lua`
currently ties to a published clause, but the citation lives in the
describe name or in the parser-side `spec_ref` — not on the test name
itself. The next phase puts it on the test name so:

1. Citations show up in busted output — when a test fails the spec
   clause it was enforcing is on the same line.
2. The cite is grep-able from the command line — a single regex
   extracts `(file, line, doc, section)` tuples across the suite.
3. Every cite is re-verified against primary spec text before landing
   (Spec Verification Protocol from CLAUDE.md applies).

### Pattern

Suffix bracket at the end of the test name:

```lua
it("<description> [<doc> §<section>]", function()
```

- Document token: `RFC NNNN`, `ST 2110-NN`, `ST 2110-NN:YYYY`
  (year-pinned when the section number depends on the revision),
  `TR-10-NN`, `TR-10-NN-PartN`.
- Section token: `§N`, `§N.M`, `§N.M.L`.
- Multiple cites comma-separated, no "and":
  `[RFC 8866 §5.7, ST 2110-10 §6.5]`.
- No URLs — document IDs are the bibliographic anchor.

### Workflow (per file, one commit per file)

1. Walk every describe top to bottom.
2. For each `it`, locate the parser-side check it exercises and read
   the `spec_ref` value the validator emits — that is the authoritative
   citation.
3. Re-read the cited clause in the on-disk spec. If the wording does
   not unambiguously support the test, **stop and flag for discussion**
   before modifying.
4. Append the bracketed citation to the `it` name.
5. Confirm `busted spec/` still passes. Test count must not change.
6. Commit.

Coverage target: 100% of `it` blocks in the three standards-tied files.

## Known Deferred Items

These were explicitly evaluated and set aside. Do not re-raise them in
routine development unless new spec evidence emerges.

- **ST 2110-20:2022 §7.2 "default to SSN=:2017 unless :2022-only values
  are used"** — the §7.2 SSN clause has a reverse direction ("Senders
  implementing this standard shall signal the value ST2110-20:2017 unless
  [exception]") that, strictly enforced, would invalidate
  `SSN=ST2110-20:2022` whenever neither `TCS=ST2115LOGS3` nor
  `colorimetry=ALPHA` is present. ~115 existing test fixtures and most
  real-world :2022-implementing senders signal :2022 unconditionally. The
  forward direction (the JT-NM Tested ask) is enforced; the reverse is
  left to a future audit if SMPTE or AMWA clarifies intent.
- **Sampling × colorimetry × TCS × RANGE cross-table** — the spec lists
  value sets independently and contains no explicit "shall not" for any
  combination of valid individual values.
- **ST 2110-31 AES3 fmtp** — AM824 audio currently uses the ST 2110-30
  path (encoding name, channel-order, packet-fit checks). Revisit if new
  AES3-specific normative text emerges.
- **ST 2110-21 §7.1 CMAX upper bound** — the type-specific formula
  `MAX(4, INT(NPACKETS/(43200 × R_ACTIVE × T_FRAME)))` (and the Type W
  variant with `16` and `21600`) is an upper bound on `CINST` per the
  Network Compatibility Model in §6.6.1, not a lower bound on the SDP
  `CMAX` value. Enforcing the upper bound requires NPACKETS / MAXUDP /
  width × height × depth × sampling × frame-rate context; not added.
- **ST 2110-21 §6.2 vs §8.2 TROFF zero handling** — §6.2 explicitly
  permits TROFFSET to be zero (and requires it be signaled when it
  differs from TRODEFAULT); §8.2 says the SDP value is "expressed as a
  positive integer." The parser follows the §8.2 value-form SHALL and
  rejects `TROFF=0`. Revisit only if SMPTE issues an erratum.
- **ST 2110-10:2022 §8.7 vs Annex B TSDELAY zero** — §8.7 says "decimal
  positive integer"; Annex B (Informative) example shows `TSDELAY=0`. The
  §8.7 SHALL governs; parser rejects `TSDELAY=0`.
- **m= media type registry strictness (RFC 8866 §5.14 / §8.2.2)** — §5.14
  defines the five values (`audio`, `video`, `text`, `application`,
  `message`); §8.2.2 says `control` and `data` are SHOULD NOT, not MUST
  NOT, grounded in RFC 3840 SIP backward-compat. Not enforced per the
  strictness principle. Future-warning candidate.
- **`o=` unicast_address literal-IP requirement** — RFC 4566 §5.7 ABNF
  allows FQDNs in the origin address; no ST 2110 clause explicitly forbids
  them there.
