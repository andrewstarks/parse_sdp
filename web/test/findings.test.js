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

import { groupRows } from "../src/findings.js";

const mk = (id, line, severity = "warn", extra = {}) => ({ key: `${id}|${line}`, finding: { id, severity, line, col: 1, ...extra }, tiers: ["sdp", "st2110", "ipmx"] });

test("groupRows collapses repeated id+severity+tiers line findings into one row with count and lines", () => {
  const rows = [mk("sdp.line.lf-only-line-ending", 5), mk("sdp.line.lf-only-line-ending", 2), mk("sdp.line.lf-only-line-ending", 3)];
  const out = groupRows(rows);
  assert.equal(out.length, 1);
  assert.equal(out[0].group, true);
  assert.equal(out[0].count, 3);
  assert.deepEqual(out[0].lines, [2, 3, 5], "lines sorted ascending");
  assert.equal(out[0].finding.line, 2, "the representative finding is the earliest member");
  assert.equal(out[0].members.length, 3);
});

test("groupRows orders a group by its first line among the other rows", () => {
  const out = groupRows([mk("b.check", 1, "error"), mk("sdp.line.lf-only-line-ending", 4), mk("c.check", 3, "error"), mk("sdp.line.lf-only-line-ending", 9)]);
  assert.deepEqual(out.map((r) => (r.group ? `group@${r.lines[0]}` : `${r.finding.id}@${r.finding.line}`)), ["b.check@1", "c.check@3", "group@4"]);
});

test("groupRows leaves singletons untouched (same object)", () => {
  const single = mk("x.y", 7, "error");
  const out = groupRows([single, mk("sdp.line.lf-only-line-ending", 2), mk("sdp.line.lf-only-line-ending", 3)]);
  assert.equal(out.find((r) => !r.group), single);
  assert.equal(out.filter((r) => r.group).length, 1);
});

test("groupRows never merges different severities, tier sets, or rows with a field_path", () => {
  const a = mk("same.id", 2, "warn");
  const b = mk("same.id", 3, "error");
  const c = { ...mk("same.id", 4, "warn"), tiers: ["ipmx"] };
  const d = mk("same.id", 5, "warn", { field_path: "media[0]" });
  const e = mk("same.id", 6, "warn", { field_path: "media[0]" });
  const out = groupRows([a, b, c, d, e]);
  assert.equal(out.length, 5);
  assert.ok(out.every((r) => !r.group));
  const two = groupRows([a, mk("same.id", 9, "warn"), b]);
  assert.equal(two.length, 2);
  assert.equal(two.find((r) => r.group).count, 2);
});

test("groupRows on the pathological fixture collapses the 75 bare-LF warnings into one group", async () => {
  const rep = await fixtureJson("report_generic_pathological.json");
  const out = groupRows(dedupeFindings(rep.tiers));
  const g = out.find((r) => r.group && r.finding.id === "sdp.line.lf-only-line-ending");
  assert.equal(g.count, 75);
  assert.equal(g.lines[0], 1);  // the LF finding names the line that ended with the LF
  assert.equal(out.filter((r) => r.group).length, 1);
});
