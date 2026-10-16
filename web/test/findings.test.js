import { test } from "node:test";
import assert from "node:assert/strict";
import { dedupeFindings, filterRows, tierSummary, findingKey, locationLabel } from "../src/findings.js";
import { fixtureJson } from "./helpers.js";

const lf = (line) => ({ id: "sdp.line.lf-only-line-ending", severity: "warn", line, col: 1, field_path: undefined });
const tiers = {
  sdp: { passes: true, findings: [lf(2), lf(3)] },
  st2110: { passes: false, findings: [lf(2), lf(3), { id: "st2110.attr.ts-refclk-required", severity: "error", line: 0, col: 0, field_path: "media[0]" }] },
  ipmx: { passes: false, findings: [lf(3), lf(2), { id: "st2110.attr.ts-refclk-required", severity: "error", line: 0, col: 0, field_path: "media[0]" }, { id: "tr-10-1.a.fmtp.marker-required", severity: "error", line: 0, col: 0, field_path: "media[0].attributes[fmtp]" }] },
};

test("dedupeFindings collapses same id+line+field_path across tiers and tags the tiers", () => {
  const rows = dedupeFindings(tiers);
  assert.equal(rows.length, 4);
  assert.deepEqual(rows.map((r) => r.tiers), [["sdp", "st2110", "ipmx"], ["sdp", "st2110", "ipmx"], ["st2110", "ipmx"], ["ipmx"]]);
});

test("dedupeFindings orders by line then field_path, document-level last", () => {
  const rows = dedupeFindings(tiers);
  assert.deepEqual(rows.map((r) => r.finding.line || r.finding.field_path), [2, 3, "media[0]", "media[0].attributes[fmtp]"]);
});

test("findingKey falls back to code for PARSE_ERROR findings without id", () => {
  assert.equal(findingKey({ code: "PARSE_ERROR", line: 2, col: 1 }), "PARSE_ERROR|2|1|");
});

test("filterRows by tier membership and severity", () => {
  const rows = dedupeFindings(tiers);
  assert.equal(filterRows(rows, { tier: "sdp" }).length, 2);
  assert.equal(filterRows(rows, { tier: "ipmx" }).length, 4);
  assert.equal(filterRows(rows, { severities: new Set(["error"]) }).length, 2);
  assert.equal(filterRows(rows, { tier: "st2110", severities: new Set(["warn"]) }).length, 2);
});

test("tierSummary counts errors and warnings", () => {
  assert.deepEqual(tierSummary(tiers.ipmx), { passes: false, errors: 2, warnings: 2, total: 4 });
  assert.deepEqual(tierSummary(undefined), { passes: false, errors: 0, warnings: 0, total: 0 });
});

test("locationLabel prefers line:col, else field_path", () => {
  assert.equal(locationLabel({ line: 8, col: 157 }), "8:157");
  assert.equal(locationLabel({ line: 0, col: 0, field_path: "media[0]" }), "media[0]");
});

test("real fixture: st2110_invalid dedupes to the expected row set", async () => {
  const rep = await fixtureJson("report_st2110_invalid.json");
  const rows = dedupeFindings(rep.tiers);
  const ids = rows.map((r) => r.finding.id);
  assert.equal(ids.filter((id) => id === "sdp.line.lf-only-line-ending").length, 9);
  const ts = rows.find((r) => r.finding.id === "st2110.attr.ts-refclk-required");
  assert.deepEqual(ts.tiers, ["st2110", "ipmx"]);
  assert.deepEqual(rows.find((r) => r.finding.id === "tr-10-1.a.fmtp.vtotal-required").tiers, ["ipmx"]);
});
