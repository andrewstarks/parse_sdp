# Prompt — Independent Pre-1.0 Audit

You are auditing the `parse_sdp` Lua/LPEG library at
`/Users/andrewstarks/src/parse_sdp` for a 1.0 release. ~30 prior audit passes
(by prior Claude sessions, on Opus, with maxed thinking) have run on this
codebase. None has cleanly closed it out. The user is willing to do 30 more.
They will not ship 1.0 until a pass finds nothing of substance.

The reason prior passes have not closed it out is **confirmation bias**:
every prior pass read the parser first, then asked "is each check
defensible?" That direction can only ever find checks-without-cites. It
cannot find SHALLs the parser is silently failing to enforce, because those
don't appear in the parser to be reviewed.

This pass inverts the direction. You read the specs first, enumerate every
SHALL / SHALL NOT / defined-value-set clause cold, then check the parser
against the enumeration. Bidirectional coverage.

If you do this honestly, one of two things happens:
1. **You find real findings.** Land them in the same format as the prior
   audits (one commit per finding, primary-source quote in the body, tests
   covering both pass and fail paths, docs sync).
2. **You find nothing of substance.** That's the outcome we have not
   reached in 30 passes. If you reach it, say so explicitly and recommend
   the user cut 1.0.

There is no third option called "ship some small refactors." Don't do that.

---

## Hard rules (read before doing anything)

1. **Do not read these files until you have completed the spec inventory
   (Phase 1).** Reading them first reproduces the confirmation bias that
   has kept this audit open for 30 passes:
   - `/Users/andrewstarks/src/parse_sdp/CHANGELOG.md`
   - `/Users/andrewstarks/src/parse_sdp/PLAN.md` ("Resolved", "Known
     Deferred Items", "Pre-1.0 Conformance Audit" sections)
   - `/Users/andrewstarks/src/parse_sdp/SDPOKER_BACKLOG.md`
   - Prior audit reports anywhere in `.claude/`

   You may read `parse_sdp.lua` and the test files during Phase 1 *only to
   verify a specific clause is covered* — never to discover what the
   parser does. Discovery comes from the spec.

2. **Primary spec text is required.** CLAUDE.md "Spec Verification
   Protocol" rule 1 is the law. Prefer markdown; fall back to PDF; use
   `pdftotext` only when no markdown exists. IANA registrations, downstream
   RFCs, and reference implementations are evidence — never authority.

3. **Spec silence is acceptance.** Adding a check that has no SHALL behind
   it is a regression. If a check is "physically silly but not forbidden,"
   it's out of scope. CLAUDE.md "Validation Strictness Principle" is
   binding.

4. **Wrong citation IS a finding** even when behavior is correct. A
   wrongly-cited check is one upstream-spec-revision away from being a
   silent bug.

5. **Bidirectional.** Both directions are findings:
   - **Direction A:** a spec SHALL with no parser enforcement.
   - **Direction B:** a parser check with no spec SHALL behind it.

6. **When in doubt, stop and ask the user.** A finding that survives
   careful re-reading lands as a commit. A finding that's ambiguous gets
   flagged to the user — do not land a parser change to "be safe." Being
   safe is what introduced the opinion-based checks prior audits removed.

7. **Use the markdown specs the user is maintaining**. See CLAUDE.md
   Spec Verification Protocol rule 1 for paths. If a markdown file for a
   cited spec is missing, that's worth telling the user — they may have
   just not converted it yet.

---

## Spec inventory (Phase 1)

Walk every one of these specs, top to bottom, and enumerate every SHALL,
SHALL NOT, MUST, MUST NOT, "is forbidden," and defined-value-set clause
that touches SDP signaling. Build the inventory as a working file (use
`/tmp/audit_inventory.md` — do not commit it).

For each clause, capture:
- Spec ID + section (e.g. `ST 2110-30:2025 §6.2.1`)
- Verbatim quote (≤ 3 sentences)
- One-line summary of what it requires
- Whether it constrains SDP (vs. RTP packet behavior, RTCP, device
  capability, etc.). Only SDP-constraining clauses are in scope for this
  parser.

**Specs to walk** (every one — do not skip "obvious" ones):

### IETF (RFCs)

- RFC 4566 — SDP (legacy base)
- RFC 8866 — SDP (current; supersedes 4566 in some places — note where)
- RFC 3550 — RTP
- RFC 3551 — RTP A/V profile (PT statics)
- RFC 4570 — source-filter
- RFC 5888 — `a=group`
- RFC 7104 — RTP redundancy (relevant to `a=group:DUP`)
- RFC 7273 — Clock signaling (`ts-refclk`, `mediaclk`)
- RFC 8331 — RTP ancillary data / `smpte291`
- RFC 9134 — JPEG-XS RTP payload / `video/jxsv`
- AES67-2018 — Audio-over-IP

### SMPTE ST 2110 family

- ST 2110-10:2022 — System Timing
- ST 2110-20:2022 — Uncompressed Active Video
- ST 2110-21:2022 — Traffic Shaping
- ST 2110-22:2022 — Compressed Video (jxsv)
- ST 2110-30:2025 — PCM Audio
- ST 2110-31:2022 — AM824
- ST 2110-40:2023 — Ancillary Data (smpte291)
- ST 2110-41:2024 — Fast Metadata

### SMPTE ST 2022

- ST 2022-7 — Seamless Protection Switching (for `a=group:DUP`
  consistency)

### SMPTE Recommended Practices

- RP 2110-23 — (read; verify SDP scope)
- RP 2110-24:2023 — (read; verify SDP scope)
- RP 2110-25:2023 — (read; verify SDP scope)

### SMPTE codec specs (referenced by ST 2110-22 / RFC 9134)

- ST 2042-1:2012 — JPEG-XS codec definition (markdown available)
- ST 2110-43:2021 — verify which essence this covers and whether
  SDP-relevant

### VSF TR-10 (IPMX profile) — READ ALL OF THESE

The TR-10 series has expanded since the last audit. Several documents
were absent from prior audit prompts and may contain SDP-relevant SHALLs
that the parser does not yet enforce. Read TR-10-0 first — it is the
suite's document map.

- **TR-10-0:2026-01** — IPMX Document Organization (map; read first)
- TR-10-1:2024-02 — IPMX System Timing
- TR-10-2:2024-02 — IPMX PCM Audio
- TR-10-3:2024-02 — IPMX Compressed Audio
- **TR-10-4:2023-04** — IPMX SMPTE ST 291-1 Ancillary Data (likely
  SDP-relevant; was missing from prior audit prompts)
- TR-10-5_v2:2026-02 — IPMX HDCP / HKEP
- **TR-10-6:2023-08** — IPMX Forward Error Correction (FEC has SDP
  signaling — `a=group:FEC` / `a=fec-source-flow` etc.; was missing from
  prior audit prompts)
- TR-10-7:2024-11 — IPMX JPEG-XS
- **TR-10-8:2026-01** — IPMX NMOS Requirements (probably out of SDP
  scope — NMOS lives in IS-04 / IS-05 — but verify and explicitly mark)
- TR-10-9_v2:2025-05 — IPMX video / system timing extensions
- **TR-10-10:2024-10** — HDMI InfoFrame transport over ST 2110-41
  (uses ST 2110-41 Data Items — has SDP signaling; was missing from
  prior audit prompts)
- TR-10-11:2024-02 — IPMX JPEG-XS sender (RTCP MIB heavy — but verify
  SDP carve-outs)
- **TR-10-12:2023-08** — IPMX AES3 audio (the IPMX analogue of
  ST 2110-31 / TR-10-3 for AM824; has SDP signaling; was missing from
  prior audit prompts)
- TR-10-13_v2:2026-02 — IPMX privacy
- **TR-10-14:2026-04** — IPMX USB (probably out of SDP scope but
  verify)
- TR-10-15-Part1:2025-12 — IPMX JPEG-XS specifications
- **TR-10-16:2025-11** — IPMX HDR Info Block (likely RTCP — but verify
  whether any SDP fmtp signaling exists)
- TR-10-TP-1:2026-01 — IPMX test plan

### IPMX Released Docs (2026-01) — entire directory was missed by prior audits

These are the v1.0 final IPMX profile requirement documents released
2025-12. They may supersede or tighten earlier TR-10 requirements.
Location: `~/Library/CloudStorage/Dropbox/Personal/Claude/Macnica/Standards Related/IPMX Released Docs 2026-01 Markedowned Versions/`

- **IPMX-Uncompressed-Active-Video-Profile-Requirements-v1.0-2025-12**
- **IPMX-JPEG-XS-Video-Profile-Requirements-v1.0-2025-12**
- **IPMX-PCM-Digital-Audio-Profile-Requirements-v1.0-2025-12**
- IPMX-Product-Qualification-and-Certification-Requirements (likely
  out of SDP scope; mark and skip)
- IPMX-Branding-Usage-Guidelines (out of scope)
- IPMX-Visual-Identity-Guidelines (out of scope)

### AES (audio referenced by ST 2110-30/-31)

- **AES67-2018** — Audio-over-IP. **GAP: only AES67-2013 PDF is on
  disk.** ST 2110-30:2025 §6.2.1 references AES67-2018 — the 2018
  revision is normative. Flag this to the user before proceeding;
  conclusions about audio ptime SHALLs depend on the 2018 wording.
- AES3-1-2009 (markdown) — referenced by AES67 / AM824
- AES3-4-2009 (markdown) — referenced by AES67 / AM824

For each spec in the markdown library, also note:
- Whether markdown is available or only PDF
- Effective date / revision

If any of these specs are *not* in the local library, list them so the
user can decide whether to obtain or skip.

---

## Coverage map (Phase 2)

After Phase 1, for **every** enumerated SDP-constraining clause:

1. Search `parse_sdp.lua` and `spec/` for a check that enforces it.
2. Record one of:
   - **COVERED** — check exists, citation matches the spec section.
   - **COVERED-WRONG-CITE** — check exists, citation points at a
     different section or spec. (This is a finding even when behavior is
     correct — see hard rule 4.)
   - **COVERED-NO-TEST** — check exists but no `spec/` test covers it.
   - **MISSING** — no check exists. Determine if the clause should be
     enforced (some clauses constrain receiver behavior, not sender SDP,
     and are correctly out of scope).
   - **OUT-OF-SCOPE** — clause is not SDP-validatable (capability
     subsetting, RTP packet contents, RTCP, NMOS).

3. Also walk the reverse: for every `attr_err(...)` or rejection in
   `parse_sdp.lua`, confirm there is an enumerated SHALL behind it. Use:
   ```sh
   grep -nE 'spec_ref *= *"' /Users/andrewstarks/src/parse_sdp/parse_sdp.lua
   ```
   Any `spec_ref` not traceable to a Phase 1 entry is a candidate finding
   for Direction B.

Output the coverage map as a structured table in your report. The
canonical columns:

| Spec | Clause | SHALL summary | Status | Parser location | Test location | Notes |

The map for one spec may have hundreds of rows. Don't truncate.

---

## Files you will read

### Phase 1 — spec inventory (read freely)

Spec source-of-truth paths are in `/Users/andrewstarks/src/parse_sdp/CLAUDE.md`
"Spec Verification Protocol" rule 1. Use those.

### Phase 1 / Phase 2 — repo files needed for coverage check

- `/Users/andrewstarks/src/parse_sdp/parse_sdp.lua` — the parser. Single
  file, ~4500 lines. Section markers: `── errors ──`, `── util ──`,
  `── grammar ──`, `── validate ──`, `── serialize ──`, `── st2110 ──`,
  `── ipmx ──`, `── parser ──`, `── public API ──`, `── CLI ──`.
- `/Users/andrewstarks/src/parse_sdp/spec/sdp_spec.lua` — RFC 4566 tests.
- `/Users/andrewstarks/src/parse_sdp/spec/st2110_spec.lua` — ST 2110
  tests (largest file).
- `/Users/andrewstarks/src/parse_sdp/spec/ipmx_spec.lua` — IPMX tests.
- `/Users/andrewstarks/src/parse_sdp/spec/errors_spec.lua` — error
  formatting.
- `/Users/andrewstarks/src/parse_sdp/spec/cli_spec.lua` — CLI.
- `/Users/andrewstarks/src/parse_sdp/spec/fixtures/` — sample SDPs.
- `/Users/andrewstarks/src/parse_sdp/spec_conformance/manifest.lua` —
  pinned AMWA fixtures.
- `/Users/andrewstarks/src/parse_sdp/spec_conformance/allowlist.lua` —
  divergence list (goal: empty).
- `/Users/andrewstarks/src/parse_sdp/spec_conformance/conformance_spec.lua`
- `/Users/andrewstarks/src/parse_sdp/CLAUDE.md` — strictness principle +
  Spec Verification Protocol. Treat as the project's audit constitution.
- `/Users/andrewstarks/src/parse_sdp/GUIDE.md` — user-facing doc. After
  Phase 2, confirm GUIDE.md's tables match what the parser actually
  enforces.

### Phase 3 only — prior-audit context (read AFTER your inventory is done)

These exist to let you reconcile your independent findings against prior
work. Do not read them before Phase 1 + 2 are complete. If you do, you've
collapsed back into confirmation-biased mode — restart.

- `/Users/andrewstarks/src/parse_sdp/CHANGELOG.md` `[Unreleased]`
- `/Users/andrewstarks/src/parse_sdp/PLAN.md` (Resolved, Known Deferred
  Items, Pre-1.0 Conformance Audit)
- `/Users/andrewstarks/src/parse_sdp/SDPOKER_BACKLOG.md`

---

## Commands you will reuse

```sh
# Run hermetic suite (current baseline: 777 passing)
busted /Users/andrewstarks/src/parse_sdp/spec/

# Run conformance suite (current baseline: 10 passing, allowlist empty)
busted /Users/andrewstarks/src/parse_sdp/spec_conformance/

# Enumerate every spec_ref in the parser (for Direction B)
grep -nE 'spec_ref *= *"[^"]+"' /Users/andrewstarks/src/parse_sdp/parse_sdp.lua | \
  sed -E 's/.*spec_ref *= *"([^"]+)".*/\1/' | sort -u

# Count SHALLs in a markdown spec (rough coverage gauge)
grep -ciE '\b(shall|shall not|must|must not|forbidden)\b' \
  "<path-to-spec.md>"

# Extract a clause from a PDF when no markdown exists
pdftotext -layout -f <start-page> -l <end-page> \
  "<path-to-spec.pdf>" - | less
```

Spec PDFs / markdown live in the paths CLAUDE.md "Spec Verification
Protocol" rule 1 enumerates.

---

## Parallelism

You can — and should — use the Agent tool to read specs in parallel. Each
spec walk is independent. Recommended fan-out:

- One Agent per RFC (or one Agent per group of small related RFCs: e.g.
  `RFC 5888 + 7104` together).
- One Agent per ST 2110 part.
- One Agent for the TR-10 series (these are inter-related; one walker
  with the full set is cleaner than five).
- One Agent for AES67.

Brief each Agent with: "read this spec top to bottom, enumerate every
SDP-constraining SHALL / SHALL NOT / defined-value-set clause, output as
markdown table with verbatim quotes." Aggregate their outputs in
`/tmp/audit_inventory.md`.

Do **not** brief Agents to "check whether the parser enforces this." That
is Phase 2 work and belongs in the main thread, after the inventory is
assembled, so the main thread has full visibility.

---

## Two traps the last audit named

Both are in CLAUDE.md but worth repeating because they are how prior
passes have produced false findings:

1. **Bullet-scope binding** (Spec Verification Protocol rule 6). A
   bulleted list under a section header attaches to the *clause that
   immediately introduces it*, not to the section header. Real example:
   IPMX JPEG-XS §6.1.4 is titled "Required Sender Signaling (Media Info
   Block & SDP)," but its bullet list attaches to item 1's "shall
   populate the JPEG-XS Media Info Block… including:" — those bullets
   are RTCP MIB requirements, not SDP requirements. The previous
   `fbblevel` check was born from this misreading.

2. **§9 ABNF vs §5.7 prose conflicts** (audit F7 reframe). When a spec
   has both prose and ABNF, the ABNF is authoritative for value form.
   RFC 8866 §5.7 prose says "TTL MUST NOT be present for IPv6
   multicast"; §9 ABNF says `IP6-multicast = IP6-address [ "/" numaddr
   ]` — the `/N` suffix is a layered-address count, not a TTL. Both
   prohibitions hold; the prose just doesn't say it that way.

If you find yourself making the case for a finding by paraphrasing, stop
and quote the verbatim text. If the verbatim text doesn't say what your
paraphrase says, the paraphrase is wrong.

---

## Reporting (Phase 3)

After Phase 1 + 2, write a report with these sections:

### A. Inventory summary

- Specs read: list with markdown-vs-PDF source + revision date.
- Specs *not* read because the markdown/PDF was missing: list.
- Total SDP-constraining clauses enumerated: count.

### B. Coverage table

The full table from Phase 2 (no truncation).

### C. Findings — Direction A (spec SHALL not enforced)

For each: spec ID + §, verbatim quote, what the parser does today, what
it should do, recommended action.

### D. Findings — Direction B (parser check without spec SHALL)

For each: parser location, current behavior, what citation it claims,
why no SHALL backs it, recommended action (remove or re-cite).

### E. Citation errors (Direction C)

Checks where behavior is correct but `spec_ref` is wrong.

### F. Documentation drift

Anywhere GUIDE.md, README.md, or PLAN.md describes a behavior the parser
no longer matches.

### G. Reconciliation against prior audits (Phase 3 read)

Only after A–F are written: read CHANGELOG.md, PLAN.md "Known Deferred
Items," and SDPOKER_BACKLOG.md. For each of your findings, note whether
prior audits already addressed it. For each prior-audit conclusion that
your independent pass disagrees with, flag for the user.

### H. Verdict

One of:
- **"Recommend cutting 1.0."** Use this if your independent inventory
  produced findings only in categories that prior audits have already
  resolved, and nothing in A–F is actionable.
- **"Found N findings; recommend addressing before 1.0."** With the
  findings listed.
- **"Need user input on M ambiguous items."** With each item described
  and a specific question.

---

## What "done" looks like

You are done when:

- You have read every spec in the inventory list (or flagged the missing
  ones), independently.
- Every enumerated SHALL has a status in the coverage table.
- Every `spec_ref` in `parse_sdp.lua` traces to an enumerated clause.
- Your report is structured per Phase 3 above.
- Both test suites still pass.

If, after all that, your report's Section H is "Recommend cutting 1.0,"
and your independent inventory produced no findings the prior audits
missed, that is the outcome the user is waiting for. Say so clearly.

If your report finds something prior audits missed: that is also a
successful outcome. The user is not looking for a clean bill of health.
They are looking for the truth.

---

## A note on tone

The user has done this 30 times. They are not asking for reassurance, a
plan, or a status update mid-run. They are asking for evidence. Lead
with evidence. Quote spec text verbatim. When you make a claim, the
claim should be checkable against a quoted source in the same paragraph.

If something is genuinely ambiguous, say "ambiguous" — that's useful.
If something is wrong, say "wrong" with the quote that proves it.
If something is right, say "right" with the quote that confirms it.

Do not write "comprehensive analysis" or "rigorous review" anywhere.
The work either speaks for itself or it doesn't.
