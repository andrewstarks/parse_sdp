import { test } from "node:test";
import assert from "node:assert/strict";
import { groupChecks, prefixOf, prefixLabel, sanitizePolicy, countOverrides, isToggleable } from "../src/checks.js";
import { fixtureJson } from "./helpers.js";

test("prefixOf / prefixLabel", () => {
  assert.equal(prefixOf("st2110-20.a.fmtp.depth-invalid-value"), "st2110-20");
  assert.equal(prefixLabel("st2110-20"), "SMPTE ST 2110-20");
  assert.equal(prefixLabel("tr-10-13"), "VSF TR-10-13 (IPMX)");
  assert.equal(prefixLabel("sdp"), "RFC 8866 — sdp");
  assert.equal(prefixLabel("weird"), "weird");
});

test("groupChecks orders base → ST 2110 by part → IPMX by TR part, ids sorted", async () => {
  const { checks } = await fixtureJson("checks.json");
  const groups = groupChecks(checks);
  assert.deepEqual(groups.map((g) => g.prefix), ["sdp", "st2110", "st2110-10", "st2110-20", "st2110-22", "st2110-30", "st2110-31", "st2110-40", "st2110-41", "ipmx", "tr-10-1", "tr-10-5", "tr-10-6", "tr-10-10", "tr-10-13", "tr-10-14"]);
  assert.equal(groups.reduce((n, g) => n + g.checks.length, 0), checks.length);
  const ids = groups[0].checks.map((c) => c.id);
  assert.deepEqual(ids, [...ids].sort());
});

test("sanitizePolicy drops unknown ids, defaults, bad severities and hard-syntactic checks", async () => {
  const { checks } = await fixtureJson("checks.json");
  const hard = checks.find((c) => c.kind === "hard-syntactic");
  assert.ok(hard);
  assert.equal(isToggleable(hard), false);
  const out = sanitizePolicy({
    "ipmx.m.port-must-be-even": "warn",
    "ipmx.m.port-must-exceed-1024": "error",
    "sdp.a.fmtp.trailing-semicolon": "off",
    "no.such.check": "off",
    "st2110-20.a.fmtp.depth-invalid-value": "loud",
    [hard.id]: "off",
  }, checks);
  assert.deepEqual(out, { "ipmx.m.port-must-be-even": "warn", "sdp.a.fmtp.trailing-semicolon": "off" });
  assert.equal(countOverrides(out), 2);
});

import { effectiveSeverity, canOverride, countSilenced } from "../src/checks.js";

test("effectiveSeverity: override wins, otherwise the default; unknown check → undefined", () => {
  const c = { id: "x.y", default_severity: "error", kind: "semantic" };
  assert.equal(effectiveSeverity(c, {}), "error");
  assert.equal(effectiveSeverity(c, { "x.y": "warn" }), "warn");
  assert.equal(effectiveSeverity(c, { "x.y": "off" }), "off");
  assert.equal(effectiveSeverity(c, { "x.y": "loud" }), "error", "invalid override falls back to default");
  assert.equal(effectiveSeverity(c, undefined), "error");
  assert.equal(effectiveSeverity(undefined, { "x.y": "warn" }), undefined);
});

test("canOverride: toggleable checks only; PARSE_ERROR rows (no check) never", () => {
  assert.equal(canOverride({ id: "a", kind: "semantic" }), true);
  assert.equal(canOverride({ id: "b", kind: "soft-syntactic" }), true);
  assert.equal(canOverride({ id: "c", kind: "hard-syntactic" }), false);
  assert.equal(canOverride(undefined), false);
});

test("countSilenced counts only 'off' overrides", () => {
  assert.equal(countSilenced({ a: "off", b: "warn", c: "off" }), 2);
  assert.equal(countSilenced({}), 0);
  assert.equal(countSilenced(undefined), 0);
});
