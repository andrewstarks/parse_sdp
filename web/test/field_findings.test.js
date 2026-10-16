import { test } from "node:test";
import assert from "node:assert/strict";
import { attachFindings, countsLabel, shortMessage, worstSeverity } from "../src/field_findings.js";

const doc = {
  version: "0",
  session: { name: "x", attributes: [{ name: "ts-refclk", source: "ptp" }] },
  media: [
    { media: "video", port: 5000, attributes: [{ name: "rtpmap", payload_type: 96, encoding: "raw", clock_rate: 48000 }] },
    { media: "audio", port: 5002, attributes: [] },
  ],
};
const row = (id, severity, field_path, line = 0) => ({ key: `${id}|${line}|${field_path}`, finding: { id, severity, field_path, line, message: `msg ${id}` }, tiers: ["ipmx"] });

test("attachFindings attaches an exact path to that field and counts up every ancestor", () => {
  const { attachments, counts } = attachFindings(doc, [row("st2110-20.a.rtpmap.clock-rate", "error", "media[0].attributes[rtpmap:pt=96].clock_rate")]);
  const a = attachments.get("media[0].attributes[0].clock_rate");
  assert.equal(a.length, 1);
  assert.equal(a[0].missing, false);
  assert.deepEqual(a[0].path, ["media", 0, "attributes", 0, "clock_rate"]);
  for (const p of ["", "media", "media[0]", "media[0].attributes", "media[0].attributes[0]", "media[0].attributes[0].clock_rate"]) {
    assert.deepEqual(counts.get(p), { errors: 1, warnings: 0, worst: "error" }, p);
  }
  assert.equal(counts.has("media[1]"), false);
});

test("attachFindings: a missing field attaches to the nearest existing ancestor, flagged missing", () => {
  const { attachments } = attachFindings(doc, [
    row("tr-10-1.a.fmtp.marker-required", "error", "media[1].attributes[fmtp]"),
    row("tr-10-x.infoframe", "warn", "session.attributes[infoframe]"),
    row("x.port", "error", "media[5].port"),
  ]);
  assert.equal(attachments.get("media[1].attributes")[0].missing, true);
  assert.equal(attachments.get("media[1].attributes")[0].fieldPath, "media[1].attributes[fmtp]");
  assert.equal(attachments.get("session.attributes")[0].missing, true);
  assert.equal(attachments.get("media")[0].missing, true);
});

test("attachFindings: multiple findings stack on one field, errors first, missing before present at equal severity", () => {
  const { attachments, counts } = attachFindings(doc, [
    row("a.warn", "warn", "media[0]"),
    row("b.err", "error", "media[0]"),
    row("c.missing", "error", "media[0].attributes[fmtp:pt=96]"),
  ]);
  assert.deepEqual(attachments.get("media[0]").map((a) => a.finding.id), ["b.err", "a.warn"]);
  assert.deepEqual(attachments.get("media[0].attributes").map((a) => a.finding.id), ["c.missing"]);
  assert.deepEqual(counts.get("media[0]"), { errors: 2, warnings: 1, worst: "error" });
  assert.deepEqual(counts.get(""), { errors: 2, warnings: 1, worst: "error" });
});

test("attachFindings: line-anchored rows are ignored, unlocated document-level rows attach to the root", () => {
  const { attachments, counts } = attachFindings(doc, [{ key: "k", finding: { id: "l", severity: "warn", line: 3 }, tiers: ["sdp"] }]);
  assert.equal(attachments.size, 0);
  assert.equal(counts.size, 0);
  const u = attachFindings(doc, [{ key: "u", finding: { id: "st2110-20.a.fmtp.width-required", severity: "error", line: 0, col: 0, field_path: "" }, tiers: ["st2110"] }]);
  assert.equal(u.attachments.get("")[0].unlocated, true);
  assert.equal(u.attachments.get("")[0].missing, true);
  assert.deepEqual(u.counts.get(""), { errors: 1, warnings: 0, worst: "error" });
  assert.equal(attachFindings(null, [row("x", "error", "media[0]")]).attachments.size, 0);
});

test("countsLabel, worstSeverity, shortMessage", () => {
  assert.equal(countsLabel({ errors: 2, warnings: 1 }), "2 errors · 1 warning");
  assert.equal(countsLabel({ errors: 0, warnings: 1 }), "1 warning");
  assert.equal(countsLabel(undefined), "");
  assert.equal(worstSeverity(null, "warn"), "warn");
  assert.equal(worstSeverity("warn", "error"), "error");
  assert.equal(worstSeverity("error", "warn"), "error");
  assert.equal(shortMessage("short"), "short");
  const long = "media block must include a media-level 'a=mediaclk' attribute (every ST 2110 stream description requires one; session-level mediaclk does not satisfy the per-stream SHALL)";
  const s = shortMessage(long);
  assert.ok(s.length <= 91 && s.endsWith("…"), s);
  assert.ok(s.startsWith("media block must include a media-level 'a=mediaclk' attribute"));
});

test("attachFindings: line-anchored findings attach through the line map, skipIds are left to the source view", () => {
  const lineMap = ["version", "origin", "session.name", "session.time_descriptions[0]", "media[0]", "media[0].attributes[0]"];
  const rows = [
    { key: "r", finding: { id: "st2110-20.a.rtpmap.raw-clock-rate", severity: "error", line: 6, col: 22 }, tiers: ["st2110"] },
    { key: "lf", finding: { id: "sdp.line.lf-only-line-ending", severity: "warn", line: 6, col: 1 }, tiers: ["sdp"] },
    { key: "off", finding: { id: "x.y", severity: "warn", line: 99, col: 1 }, tiers: ["sdp"] },
  ];
  const { attachments, counts } = attachFindings(doc, rows, { lineMap, skipIds: new Set(["sdp.line.lf-only-line-ending"]) });
  const a = attachments.get("media[0].attributes[0]");
  assert.equal(a.length, 1);
  assert.equal(a[0].byLine, true);
  assert.equal(a[0].missing, false);
  assert.deepEqual(counts.get("media[0]"), { errors: 1, warnings: 0, worst: "error" });
  assert.equal(attachFindings(doc, rows).attachments.size, 0, "no line map → line rows ignored");
});

import { comparePaths, summaryEntries } from "../src/field_findings.js";

test("comparePaths follows SDP order: version < origin < session < media, indices numerically", () => {
  assert.ok(comparePaths(["session", "name"], ["media", 0]) < 0);
  assert.ok(comparePaths(["media", 2], ["media", 10]) < 0);
  assert.ok(comparePaths(["media", 0], ["media", 0, "port"]) < 0);
  assert.ok(comparePaths([], ["version"]) < 0);
  assert.equal(comparePaths(["media", 1, "attributes", 3], ["media", 1, "attributes", 3]), 0);
});

test("summaryEntries lists errors first, then by document position", () => {
  const { attachments } = attachFindings(doc, [
    row("w.media1", "warn", "media[1]"),
    row("e.media1.attr", "error", "media[1].attributes[fmtp]"),
    row("w.session", "warn", "session.name"),
    row("e.media0", "error", "media[0]"),
    { key: "u", finding: { id: "e.unlocated", severity: "error", line: 0, field_path: "" }, tiers: ["st2110"] },
  ]);
  assert.deepEqual(summaryEntries(attachments).map((a) => a.finding.id), ["e.unlocated", "e.media0", "e.media1.attr", "w.session", "w.media1"]);
});
