# Plan

## Guiding Principles

- **Test first.** Every feature begins with failing tests.
- **Strict by spec.** Every validation check must cite explicit normative spec
  text — a positive "shall" / "MUST", a prohibitive "shall not" / "MUST NOT" /
  "is forbidden", or a defined value form / value set for an optional field.
  Spec silence is not a reason to reject.
- **Layered.** Each tier (RFC 4566 → ST 2110 → IPMX) extends the previous; it
  never replaces it.
- **Tight.** If a file is growing, stop and refactor before continuing. Prefer
  fewer, well-named things.
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
busted spec/                  # local — hermetic suite
busted spec_conformance/      # opt-in upstream-fixture conformance suite
docker compose run test       # Docker (runs the hermetic suite)
```

The `spec_conformance/` suite downloads pinned SDP fixtures from
`AMWA-TV/nmos-testing` and `AMWA-TV/bcp-006-01` into a gitignored cache, then
runs them through the parser. See [spec_conformance/README.md](spec_conformance/README.md).

---

## Current State

728 tests passing (hermetic) · 10/10 upstream conformance · allowlist empty.
Every validation check is grounded in explicit spec text. No known check is
opinion-only.

The AMWA / Streampunk SDPoker cross-reference backlog has been walked end to
end. All actionable PR-tagged and Issue-tagged findings have been evaluated
against primary spec text and either landed parser changes, added regression
tests, or were documented as non-applicable. See CHANGELOG.md for the
specific spec citations.

## Next

The AMWA / Streampunk SDPoker backlog is fully walked. No tracked items
remain open. Future work is driven by new spec releases, new conformance-
fixture findings, or user reports.

## Pre-1.0 Conformance Audit (open findings, 2026-05-15)

**Resolved since audit opened (2026-05-15):**

- F1 + D3 — TCS optional per §7.3 + GUIDE doc sync.
- F2 + D4 — `a=hkep` permitted at media level per TR-10-5 §17 + GUIDE doc sync.
- F3 — ST 2110-41 DIT is optional + comma-separated uppercase hex per §6.
- F4 — ST 2110-41 clock rate is Data-Item-defined per §5.3 (not fixed at 90 kHz).
- F5 — `channel-order` convention is SHOULD per ST 2110-30:2025 §6.2.2; non-`SMPTE2110` accepted structurally.
- F6 — `AES3` channel-grouping symbol added for AM824 per ST 2110-31:2022 §6.2 Table 2.
- F7 — Reframed (cite cleanup, no parser change). RFC 8866 §9 ABNF has
  `IP6-multicast = IP6-address [ "/" numaddr ]` — the IPv6 `/N` suffix is a
  layered-address count, not a TTL; the audit's recommendation to reject
  it conflated §5.7's TTL prohibition with §9's `numaddr` permit. Parser
  behavior unchanged; messages/comments now use the correct ABNF term.
- F9 — IPv4 layered multicast `<addr>/<ttl>/<numaddr>` accepted per RFC 8866 §9 IP4-multicast ABNF.
- F10 — IPv4 multicast TTL=0 accepted per RFC 8866 §5.7 (range 0-255) / §9 ABNF.
- F8 — RFC 4566 §5 `r=`, `z=`, session/media `k=`, and multiple `t=` blocks
  parsed, validated, and round-tripped through `to_sdp()`.
- F11 — ST 2110-10 §6.2 fixed-PT carve-out implemented: PT 10 (L16/44100/2)
  and PT 11 (L16/44100/1) accepted per RFC 3551 §6 statics; all other
  PTs outside 96-127 still rejected.
- N1 — TP is required for raw video at the ST 2110 tier per ST 2110-20:2022
  §6.1.1 → ST 2110-21:2022 §8.1 chain. Cross-field "TROFF/CMAX require TP"
  check dropped (subsumed by the always-required TP).

These findings came out of a multi-spec audit that read every SDP-relevant
SHALL / SHALL-NOT / defined-value clause across RFC 4566, RFC 8866,
ST 2110-10/-20/-21/-22/-30/-31/-40/-41, ST 2022-7, RFC 7104, RFC 9134, and
VSF TR-10-1, -2, -3, -5 v2, -7, -10, -11, -13 v2, -14, -15, -TP-1, then
cross-referenced against the parser and tests.

**Working principle for the next thread.** Each item below names a clause and
quotes the diagnostic fragment. The audit was systematic, but the conformance
principle (CLAUDE.md) requires every check to be grounded in actual spec
text — not a paraphrase of it. Before changing parser behavior:

1. Open the cited spec (PDFs in `~/Library/CloudStorage/Dropbox/Personal/
   Claude/Macnica/Standards Related/smpte_standards_internal/`; TR-10 markdown
   in `…/TR-10 Markdowned Versions/`) and re-read the named clause in full
   context. The fragment quoted below may be qualified by surrounding text.
2. If the wording does not unambiguously support the finding, **stop and
   flag for discussion** — do not land a parser change pending confirmation.
   A finding that doesn't survive careful re-reading is, by definition,
   opinion-based and excluded by the strictness principle.
3. If the finding holds, land the parser change + new tests covering both
   passing and failing paths + GUIDE.md / README.md / CHANGELOG.md sync in
   one commit. The CHANGELOG entry should cite the same clause.

Items are grouped by severity. F = false positives (parser rejects compliant
SDPs; blockers for 1.0). N = false negatives (parser accepts non-conformant
SDPs; should-fix). D = documentation/citation cleanups.

---

### N2 — ST 2110-31 AM824 nchan even-number constraint not enforced

**Parser behavior:** Audio branch [parse_sdp.lua:1614-1683](parse_sdp.lua#L1614)
accepts any positive integer channel count for AM824.

**Spec basis:** ST 2110-31:2022 §6.1: *"Since this standard transports AES3
signals, and each AES3 signal contains two sequences of AES3 Subframes, the
number of AES3 Subframe sequences <nchan> expressed in the SDP object shall
always be an even number."*

**Verify before acting:** Re-read §6.1 to confirm the "always be an even
number" SHALL. Confirm it applies only to AM824 (encoding name), not to
L16/L24.

**Fix direction:** When the rtpmap encoding is `AM824`, reject odd `<nchan>`
values. Add to the audio branch alongside the existing channel-count check.

**Doc sync:** GUIDE.md "ST 2110-31 (AM824)" section (currently inherits from
the §6.2.2 deferred item) — add the even-nchan SHALL.

**Tests:** `a=rtpmap:96 AM824/48000/8` accepts; `a=rtpmap:96 AM824/48000/7`
rejects.

### N3 — ST 2110-31 AM824 clock rate enum not enforced

**Parser behavior:** Audio branch accepts any positive rate for AM824. The
code comment at L1623-1626 references ST 2110-30 "out of scope" rationale —
that rationale doesn't transfer to ST 2110-31.

**Spec basis:** ST 2110-31:2022 §5.5: *"AES3 streams in scope of this standard
shall have a sampling frequency of 44.1 kHz, 48 kHz, or 96 kHz."* And §6.1:
*"The <clock-rate> parameter shall take one of the values 44100, 48000, or
96000."*

**Verify before acting:** Re-read §5.5 and §6.1. Note this is an explicit
enum SHALL, distinct from ST 2110-30's "other rates are out of scope" phrasing.

**Fix direction:** When the rtpmap encoding is `AM824`, validate clock_rate ∈
{44100, 48000, 96000}. Reject otherwise. L16/L24 behavior unchanged.

**Doc sync:** GUIDE.md AM824 rtpmap section — state the {44.1, 48, 96} kHz enum.

**Tests:** AM824 at 48000 accepts; at 32000 rejects.

### N4 — ST 2110-31 AM824 `a=ptime` not required at ST 2110 tier

**Parser behavior:** ST 2110 tier audio path [parse_sdp.lua:1642-1650](parse_sdp.lua#L1642)
validates ptime *when present* but does not require it. (IPMX tier requires
it at L2374-2380 with misattributed cite — see D1.)

**Spec basis:** ST 2110-31:2022 §6.1: *"Senders under this standard shall
signal a ptime attribute in the SDP, as defined in IETF RFC 4566."* Table 1
enumerates valid `<packet-time>` values per clock rate.

**Verify before acting:** Confirm §6.1's "shall signal a ptime attribute"
language. Decide whether to also enforce Table 1 enum values for AM824 (see
N5 — they're paired).

**Fix direction:** When the rtpmap encoding is `AM824`, require `a=ptime`
to be present. (Do not extend this requirement to L16/L24 unless N5/N4 are
reframed via AES67 — see "open question" below.)

**Open question to investigate:** Is `a=ptime` also a SHALL for L16/L24
PCM audio? ST 2110-30:2025 §6.2.1 says "Audio senders and receivers shall
comply with the provisions of AES67 Clause 7.1." AES67 may make ptime a
SHALL. Verify by reading AES67-2018 (or current revision) §6/§7/§8 SDP
clauses. If AES67 makes ptime SHALL, extend this fix to all audio encodings
and update D1 accordingly.

**Doc sync:** GUIDE.md ST 2110-31 / AM824 section: state ptime is required.

**Tests:** AM824 SDP without ptime rejects; with valid ptime accepts.

### N5 — ST 2110-31 AM824 ptime value not constrained to Table 1

**Parser behavior:** Audio branch [parse_sdp.lua:1645-1649](parse_sdp.lua#L1645)
validates `ptime > 0` only — accepts any positive number.

**Spec basis:** ST 2110-31:2022 §6.1: *"The <packet-time> parameter shall
take one of the values from the Table 1, based on the prevailing sampling
rate and the desired number of AES3 Subframe sequences interleaved together
within the RTP stream."* Table 1 enumerates: at 48k → {1, 0.12, 0.08} ms;
at 96k → {1, 0.12, 0.08} ms; at 44.1k → {1.09, 0.14, 0.09} ms.

**Verify before acting:** Re-read §6.1 and Table 1. Confirm the SHALL on
"shall take one of the values from the Table 1". Note that Table 1 values
are decimal fractions; the parser already handles `tonumber` of decimal
strings.

**Fix direction:** When encoding is `AM824`, look up the valid ptime set
by clock_rate and reject any other value. (Allow small floating-point
tolerance — e.g., ±0.001 ms — to avoid rejecting strings like "0.080" that
round identically.)

**Caution:** L16/L24 may have similar AES67-derived constraints; this fix
should not silently extend to non-AM824 encodings.

**Doc sync:** GUIDE.md AM824 section — list Table 1 values.

**Tests:** AM824 at 48k with ptime=1 accepts; ptime=0.5 rejects; ptime=0.12
accepts.

### N6 — ST 2110-22 frame rate signaling not required

**Parser behavior:** jxsv branch [parse_sdp.lua:1320-1476](parse_sdp.lua#L1320)
lists `exactframerate` as an *optional* jxs param. No check on `a=framerate`.

**Spec basis:** ST 2110-22:2022 §7.4: *"The SDP object shall include an
indication of frame rate via one of the mechanisms listed in Table 4."*
Table 4 lists two mechanisms: `a=framerate:<frame rate>` attribute OR
`exactframerate=<frame rate>` fmtp parameter. At least one is REQUIRED.

**Verify before acting:** Re-read §7.4 and Table 4. Confirm the "shall include"
opens the SHALL. Both mechanisms are alternates — having either satisfies the
requirement.

**Fix direction:** In the jxsv branch, after fmtp validation, check whether
`exactframerate` is in `params` OR `a=framerate` is in `m.attributes`. If
neither, reject with cite `ST 2110-22 §7.4`. Validate `a=framerate` value
form per RFC 4566 §6 (decimal `<integer>.<fraction>` or integer).

**Doc sync:** GUIDE.md ST 2110-22 section — state that one of
`a=framerate` or `exactframerate` is required (currently lists exactframerate
under "optional" only).

**Tests:** jxsv with exactframerate accepts; jxsv with a=framerate accepts;
jxsv with neither rejects.

### N7 — ST 2110-22 b=AS not required at the ST 2110 tier

**Parser behavior:** [parse_sdp.lua:2194-2199](parse_sdp.lua#L2194) requires
b=AS on jxsv *only* inside `ipmx.validate`. ST 2110 mode accepts a jxsv
stream without b=AS.

**Spec basis:** ST 2110-22:2022 §7.3: *"The media-level section of the SDP
object shall include the attribute listed in Table 3."* Table 3 row: `b=<brtype>:<brvalue>`
with `<brtype>` = `AS`, `<brvalue>` an integer kbps.

**Verify before acting:** Re-read §7.3 to confirm the "shall include" SHALL
and that it applies to all ST 2110-22 streams (not just IPMX-tagged ones).

**Fix direction:** Move (or duplicate) the b=AS-required check into the
jxsv branch of `st2110.validate`. The value-form check (positive integer)
can stay shared.

**Doc sync:** GUIDE.md `b=AS` row currently cites "TR-10-7 §11" — add the
ST 2110-22 §7.3 cite for the ST 2110-tier requirement.

**Tests:** ST 2110 mode jxsv SDP without b=AS rejects (was accepting).

### N8 — ST 2110-22 fmtp "no trailing semicolon" not enforced on jxsv

**Parser behavior:** `valid_st2110_20_fmtp_format` at [parse_sdp.lua:1005-1023](parse_sdp.lua#L1005)
is only called for raw video at L1488. jxsv fmtp like
`width=1920;height=1080;TP=2110TPN;packetmode=0;IPMX;` (trailing semicolon)
is accepted.

**Spec basis:** ST 2110-22:2022 §7.2: *"The <format specific parameters>
section shall consist of a sequence of parameter entries separated by a
semicolon (';') character, with the semicolon optionally followed by a space
character. **There is no semicolon character after the last item.**"*

Note: §7.2 differs from ST 2110-20:2022 §7.1 in one aspect — ST 2110-22
makes the post-semicolon space *optional* (vs. mandatory in -20). So the
trailing-semicolon SHALL transfers but the post-semicolon-whitespace SHALL
does not (-20-only).

**Verify before acting:** Re-read both §7.1 (in -20) and §7.2 (in -22).
Confirm the trailing-semicolon prohibition in -22 §7.2 and confirm that the
post-`;`-whitespace requirement is only in -20 §7.1.

**Fix direction:** Factor the trailing-semicolon check out of
`valid_st2110_20_fmtp_format` into a small `no_trailing_semicolon` helper.
Call it from both the raw branch (existing) and the jxsv branch (new).
The post-`;`-whitespace check stays only in the raw branch.

**Doc sync:** GUIDE.md jxsv section — note the no-trailing-semicolon rule.

**Tests:** jxsv fmtp ending in `;` rejects; jxsv fmtp without trailing `;`
accepts; raw video still subject to both rules.

### N9 — ST 2110-22 requires m=video for jxsv; parser doesn't enforce

**Parser behavior:** jxsv branch [parse_sdp.lua:1320](parse_sdp.lua#L1320)
is reached whenever `enc == "jxsv"`, regardless of `m.media`. The smpte291
branch (L1204) has an analogous check; the jxsv branch does not.

**Spec basis:** ST 2110-22:2022 §6.2: *"The media type name shall be 'video'.
The subtype name shall be the name registered for the payload format."* (For
JPEG-XS, the subtype is `jxsv` per RFC 9134.)

**Verify before acting:** Re-read §6.2. Confirm "shall be 'video'" for the
media type name (i.e., the `m=` field).

**Fix direction:** At the start of the jxsv branch, reject if `m.media ~= "video"`.
Mirror the smpte291 pattern at L1204.

**Doc sync:** Add to GUIDE.md jxsv section.

**Tests:** `m=application 5004 RTP/AVP 96` with `a=rtpmap:96 jxsv/90000`
rejects (was accepting).

### N10 — ST 2110-40 FID prohibition not enforced at the ST 2110 tier

**Parser behavior:** [parse_sdp.lua:2065-2074](parse_sdp.lua#L2065) rejects
`a=group:FID` only inside `ipmx.validate`. ST 2110 mode allows FID even on
smpte291 streams.

**Spec basis:** ST 2110-40:2023 §7: *"Section 4.1 of IETF RFC 8331 permits
the use of Flow Identification ('FID') semantics to group streams within
the SDP; such use is inconsistent with the 'one SDP object per RTP Stream'
provision of SMPTE ST 2110-10 and therefore Flow Identification ('FID')
semantics shall not be used under this standard."*

**Verify before acting:** Confirm §7's FID prohibition. Decide whether to
limit the rejection to smpte291-bearing SDPs (strict reading: the SHALL
is in -40, which governs smpte291) or to broaden it to all ST 2110 SDPs
(arguable from ST 2110-10 §8.1's "one SDP per RTP stream" but not an
explicit FID SHALL in -10).

**Fix direction:** Conservative: in `st2110.validate`, after iterating
media blocks, if any block carries rtpmap encoding `smpte291`, reject any
session-level `a=group:FID`. Cite ST 2110-40:2023 §7.

**Caution:** Broader rejection (all ST 2110 streams, regardless of essence)
is arguable but not directly grounded in a single SHALL. Strict reading
recommended.

**Doc sync:** GUIDE.md ST 2110-40 / smpte291 section — note FID prohibition.

**Tests:** ST 2110 mode SDP with smpte291 and `a=group:FID` rejects;
without smpte291, FID is still accepted at ST 2110 tier.

### N11 — MAXUDP > Standard limit on smpte291 / ST 2110-41 / ST 2110-30 not enforced

**Parser behavior:** No MAXUDP-vs-encoding constraint exists. A sender that
signals `MAXUDP=8000` on smpte291, ST2110-41, or L16/L24/AM824 passes.

**Spec basis:** Three distinct SHALLs:
- **ST 2110-40:2023 §6.1.4** (RTP Payload Format section): *"The UDP size of
  each RTP packet shall not exceed the Standard UDP Size Limit as specified
  in SMPTE ST 2110-10."* MAXUDP > 1460 on smpte291 violates this.
- **ST 2110-41:2024 §5.4**: *"The total length of the UDP packet that
  encompasses each RTP Packet shall be less than or equal to the Standard
  UDP Size Limit defined in SMPTE ST 2110-10."*
- **ST 2110-30:2025 §6.2.1**: *"The Standard UDP Datagram Size Limit as
  defined in SMPTE ST 2110-10 shall be used."* For PCM L16/L24.

Note ST 2110-10:2022 §6.4 defines MAXUDP as the signaling that a sender
*exceeds* the Standard limit (1460). So *any* MAXUDP presence on a
Standard-only-permitted encoding is non-conformant (not just MAXUDP > 1460).

**Verify before acting:** Re-read each of the three clauses. Confirm
"Standard UDP Size Limit" is 1460 (ST 2110-10 §6.3). Confirm MAXUDP's
semantics in ST 2110-10 §6.4 / §8.6 — that its mere presence signals
exceeding the Standard limit.

**Fix direction:** In each of the three branches (smpte291, ST2110-41,
audio), reject any presence of `MAXUDP` in fmtp. (For audio, this applies
to L16/L24/AM824 — though AM824 inherits from -31 which uses Standard limit
per the chain from §5.x.)

**Doc sync:** GUIDE.md sections for ST 2110-30, ST 2110-31, ST 2110-40,
ST 2110-41 — note MAXUDP is forbidden.

**Tests:** smpte291 with MAXUDP rejects; ST2110-41 with MAXUDP rejects;
L16 with MAXUDP rejects; raw video with MAXUDP (and PM=2110GPM) still
accepts.

### N12 — ST 2110-20 §7.4.1 KEY-sampling SHALLs not enforced

**Parser behavior:** Raw video branch [parse_sdp.lua:1478-1612](parse_sdp.lua#L1478)
accepts any colorimetry with `sampling=KEY` and requires TCS even for KEY
streams.

**Spec basis:** ST 2110-20:2022 §7.4.1 (last paragraph): *"Key signals are
used in relationship to 'fill' signals of video content. The Key signal does
not have a specific TCS or Colorimetry value itself; the Key stream shall
signal the colorimetry value 'ALPHA', and shall not signal a TCS value."*

Two distinct SHALLs:
1. `sampling=KEY` → `colorimetry=ALPHA` (positive).
2. `sampling=KEY` → TCS absent (prohibitive).

**Scope question — jxsv inheritance.** Verified directly against the
RFC 9134 text (2026-05-15): RFC 9134 §7.1 does **not** cross-reference
ST 2110-20 §7 by section number. Instead it rewrites every parameter
(sampling, depth, exactframerate, TCS, colorimetry, RANGE, interlace,
segmented) with its own self-contained prose. The §7.1 `sampling` entry
ends with the line *"Key signals as defined in [SMPTE157] SHALL use the
value key for the Media Type Parameter 'sampling'. The key signal is
represented as a single component"* — and **stops there**. The next two
sentences from ST 2110-20:2022 §7.4.1 — *"The Key signal does not have a
specific TCS or Colorimetry value itself; the Key stream shall signal the
colorimetry value 'ALPHA', and shall not signal a TCS value"* — are not
carried into RFC 9134. Whether the omission was editorial or deliberate is
not knowable from the text alone, but the result is the same: RFC 9134 §7.1
contains no cross-parameter SHALL on KEY-sampling jxsv streams.

The **semantic** reasoning still holds: a key signal "as defined in
SMPTE RP 157" (cited in both specs) is a single-component matte with no
color or transfer characteristics, and JPEG-XS compression does not grant
it any. A jxsv KEY stream with `colorimetry=BT2020` or `TCS=PQ` is
semantically as incoherent as a raw one. But the strictness principle's
explicit carve-out (CLAUDE.md): *"'Physically silly but not forbidden' …
is not in scope. The validator tests for conformance, not for whether a
device is saying things that can't be true."* — applies precisely to this
case. Enforce on raw-video only; do not extend to jxsv.

**Verify before acting:**
- Re-read ST 2110-20:2022 §7.4.1 final paragraph for the raw-video SHALLs.
- Re-read RFC 9134 §7.1 `sampling` entry (the line beginning "Key signals
  as defined in [SMPTE157]"). Confirm the entry stops where the audit says
  it does — no ALPHA / no-TCS sentences follow.
- If a later RFC 9134 update or a new ST 2110-22 revision adds an
  explicit cross-reference to §7.4.1, the jxsv-out-of-scope decision
  should be revisited.

**Fix direction:** In the raw-video branch only (the `elseif m.media ==
"video"` block, NOT the `elseif enc == "jxsv"` block):
- If `params["sampling"] == "KEY"` and `params["colorimetry"] ~= "ALPHA"`,
  reject (cite §7.4.1).
- If `params["sampling"] == "KEY"` and `params["TCS"]` is set, reject
  (cite §7.4.1). With TCS now in `video_opt_checks` (resolved F1, 2026-05-15),
  "TCS is set" means the sender explicitly signaled it on a KEY stream,
  which is what §7.4.1 forbids.

**Doc sync:** GUIDE.md ST 2110-20 KEY-signal section. **Whichever scope is
chosen (raw-only vs. raw+jxsv), document the decision and the reasoning
behind it explicitly in GUIDE.md** — e.g., "We enforce §7.4.1 on raw video
only; RFC 9134 §7.1 carries the sampling value set over to jxsv but does
not reference §7.4.1's cross-parameter constraints, so by the strictness
principle they don't transfer." Future readers (and a future auditor) need
to see both *what* the parser does and *why* the spec supports that choice.
Mirror the note in CLAUDE.md's "What we do reject" / "What we do not
reject" lists if applicable.

**Tests:** raw video with `sampling=KEY; colorimetry=ALPHA` (no TCS)
accepts; with `sampling=KEY; colorimetry=BT709` rejects; with `sampling=KEY;
colorimetry=ALPHA; TCS=SDR` rejects.

### N13 — ST 2110-20 §6.2.5 4:2:0-progressive-only SHALL not enforced

**Parser behavior:** Raw video branch accepts any `sampling=*-4:2:0` with
the `interlace` or `segmented` bare flag.

**Spec basis:** ST 2110-20:2022 §6.2.5 (opening sentence): *"The 4:2:0
sampling system shall only be applied to progressive scan images transmitted
in a progressive manner. This sampling system does not apply to PsF or
interlaced video essence."*

Affected sampling values: `YCbCr-4:2:0`, `CLYCbCr-4:2:0`, `ICtCp-4:2:0`.

**Scope question — jxsv inheritance:** Weaker case than N12 even
semantically. §6.2.5 sits in ST 2110-20:2022 §6 ("Uncompressed Active Video
RTP Essence Format"), which is the chapter that defines the raw pgroup
construction tables. The chroma-sharing problem the SHALL prevents — 4:2:0
pgroups span two adjacent luminance rows, so interlaced transmission
creates ambiguity over which field "owns" the shared chroma sample — is a
property of the raw RTP packetization, not of the underlying signal.
JPEG-XS defines its own packetization (RFC 9134 §4) and its own handling
of interlaced content; the pgroup ambiguity does not arise the same way.

RFC 9134 §7.1 (verified 2026-05-15) gives `interlace` and `segmented` their
own self-contained definitions and does not import §6.2.5 by reference.

So unlike N12, the jxsv non-application here is supported by *both* the
strictness principle (RFC 9134 silence) *and* the underlying technical
reasoning (§6.2.5's mechanics are pgroup-specific, and jxsv has its own
packetization). Enforce on raw video only.

**Verify before acting:**
- Re-read §6.2.5 to confirm the SHALL on "shall only be applied to
  progressive scan images."
- Re-read §7.3 to confirm `interlace` and `segmented` are progressive/PsF
  markers (already enforced separately).
- For jxsv: don't enforce unless RFC 9134 or ST 2110-22 explicitly says so.

**Fix direction:** In the raw-video branch only:
- If `params["sampling"]` matches `^(YCbCr|CLYCbCr|ICtCp)-4:2:0$` and
  `params["interlace"]` is set, reject (cite §6.2.5).
- The "no `segmented` without `interlace`" rule already covers PsF
  transitively (segmented requires interlace, and 4:2:0 forbids both).

**Doc sync:** GUIDE.md ST 2110-20 §6.2.5 / sampling section. **As with N12,
the scope decision (raw-only vs. raw+jxsv) and its reasoning must be
documented in GUIDE.md regardless of which way it goes.** §6.2.5 sits in
the RTP-payload (pgroup-construction) chapter of ST 2110-20, which jxsv
does not use. RFC 9134's `sampling` inheritance carries the value set, not
the §6 RTP packaging constraints. Note this in GUIDE.md so readers see the
explicit reasoning, and mirror to CLAUDE.md if applicable.

**Tests:** `sampling=YCbCr-4:2:0` with `interlace` flag rejects;
`sampling=YCbCr-4:2:0` without flag (progressive) accepts;
`sampling=YCbCr-4:2:2` with `interlace` still accepts.

---

### D1 — `spec_ref = "TR-10-3 §8"` for IPMX audio a=ptime requirement is wrong

**Parser cite:** [parse_sdp.lua:2378](parse_sdp.lua#L2378).

**Actual spec basis:** TR-10-3 §8 is titled *"Payload Formats and Sample
Rates"* and contains no SDP/ptime SHALL. The actual basis is either:
- AES67 SDP requirements (transitively required by TR-10-3 §7 line 149:
  *"Audio PCM IPMX Sender's digital audio streams shall conform to AES67"*).
  Verify AES67 §6/§7/§8 for the SDP `a=ptime` SHALL — citation should
  resolve to that AES67 clause.
- ST 2110-31:2022 §6.1 — for AM824 specifically (see N4).

**Fix direction:** After resolving N4, update the `spec_ref` to cite the
correct underlying SHALL. If ptime is required for all audio (via AES67),
cite AES67. If only for AM824 (via ST 2110-31 §6.1), branch the check.

### D2 — `spec_ref = "TR-10-11 §12"` for fmtp `fbblevel` is wrong

**Parser cite:** [parse_sdp.lua:1470-1476](parse_sdp.lua#L1470).

**Actual spec basis:** TR-10-11 §12 is *"IPMX Info Block for Constant
Bit-Rate Compressed Video"* — describes RTCP Media Info Block fields, not
SDP fmtp. `fbblevel` is defined for the RTCP MIB (in TR-10-15-Part1 §12),
not for SDP fmtp. **No spec defines `fbblevel` as an SDP fmtp parameter.**

**Fix direction:** Two options:
- (a) Remove the `fbblevel` check entirely. The conformance principle
  forbids spec-ungrounded checks; an SDP `fbblevel` parameter is not
  defined anywhere.
- (b) Keep the check (since it only validates value form when present, and
  is permissive — accepts any positive integer) but mark the cite as
  "(no SDP spec — RTCP MIB defined in TR-10-15-Part1 §12; SDP form not
  standardized)" so future readers don't follow a misleading cite.

Recommend (a): remove. The check is technically opinion-based per the
strictness principle.

---

## Known Deferred Items

These were explicitly evaluated and set aside. Do not re-raise them in routine
development unless new spec evidence emerges.

- **ST 2110-20:2022 §7.2 "default to SSN=:2017 unless :2022-only values are
  used"** — the §7.2 SSN clause has a reverse direction ("Senders implementing
  this standard shall signal the value ST2110-20:2017 unless [exception]")
  that, strictly enforced, would invalidate `SSN=ST2110-20:2022` whenever
  neither `TCS=ST2115LOGS3` nor `colorimetry=ALPHA` is present. ~115 existing
  test fixtures and most real-world :2022-implementing senders signal :2022
  unconditionally. The forward direction (the JT-NM Tested ask) is enforced;
  the reverse is left to a future audit if SMPTE or AMWA clarifies intent.
- **Sampling × colorimetry × TCS × RANGE cross-table** — the spec lists value
  sets independently and contains no explicit "shall not" for any combination of
  valid individual values.
- **ST 2110-31 AES3 fmtp** — AM824 audio currently uses the ST 2110-30 path
  (encoding name, channel-order, packet-fit checks). Revisit if new
  AES3-specific normative text emerges.
- **ST 2110-21 §7.1 CMAX upper bound** — the type-specific formula
  `MAX(4, INT(NPACKETS/(43200 × R_ACTIVE × T_FRAME)))` (and the Type W
  variant with `16` and `21600`) is an upper bound on `CINST` per the
  Network Compatibility Model in §6.6.1, not a lower bound on the SDP
  CMAX value. Enforcing the upper bound requires NPACKETS / MAXUDP /
  width × height × depth × sampling × frame-rate context; not added.
- **ST 2110-21 §6.2 vs §8.2 TROFF zero handling** — §6.2 explicitly
  permits TROFFSET to be zero (and requires it be signaled when it
  differs from TRODEFAULT), while §8.2 says the SDP value is "expressed
  as a positive integer." The parser follows the §8.2 value-form SHALL
  and rejects `TROFF=0`. Revisit only if SMPTE issues an erratum.
- **ST 2110-10:2022 §8.7 vs Annex B TSDELAY zero** — §8.7 says
  "decimal positive integer"; Annex B (Informative) example shows
  `TSDELAY=0`. The §8.7 SHALL governs; parser rejects `TSDELAY=0`.
- **VSF TR-10-1 (IPMX System Timing) SDP-validation audit** — every
  SDP-touching SHALL in TR-10-1 §10 (and the SDP-adjacent §8.1 traffic
  shape) is already enforced by the parser: §10 FID prohibition
  ([parse_sdp.lua:2031](parse_sdp.lua#L2031)), §10.1 `IPMX` fmtp marker,
  §10.2 `measuredpixclk`/`vtotal`/`htotal` (extended to all IPMX video
  by TR-10-9 §10), §10.3 `measuredsamplerate` (extended by TR-10-9
  §10), §10.4 media-level `ts-refclk` (via ST 2110-10 §8.2) and
  `ts-refclk:localmac` format, §10.5 `mediaclk` presence + `direct=0`
  enforcement (via ST 2110-10 §8.3 — same SHALL). §8.1 specifies
  CMAX = Type W formula with an informative Note permitting Type N for
  interop; Type NL is silent. The parser accepts the ST 2110-22:2022
  §7.2 union {2110TPN, 2110TPNL, 2110TPW}; the strictness principle
  ("silence is not a reason to reject") rules out narrowing further on
  Note language alone. Audited 2026-05-15 — no actionable findings.
- **`o=` unicast_address literal-IP requirement** — RFC 4566 §5.7 ABNF allows
  FQDNs in the origin address; no ST 2110 clause explicitly forbids them there.

