import { test } from "node:test";
import assert from "node:assert/strict";
import { diffLines, diffSummary } from "../src/diff.js";

test("diffLines marks identical input as all same", () => {
  const d = diffLines(["a", "b"], ["a", "b"]);
  assert.deepEqual(d.map((e) => e.type), ["same", "same"]);
  assert.equal(diffSummary(d).changed, false);
});

test("diffLines reports a changed line as del + add", () => {
  const d = diffLines(["v=0", "m=video 5000 RTP/AVP 96"], ["v=0", "m=video 5002 RTP/AVP 96"]);
  assert.deepEqual(d, [
    { type: "same", text: "v=0" },
    { type: "del", text: "m=video 5000 RTP/AVP 96" },
    { type: "add", text: "m=video 5002 RTP/AVP 96" },
  ]);
  assert.deepEqual(diffSummary(d), { added: 1, removed: 1, changed: true });
});

test("diffLines handles insertions, deletions and empty sides", () => {
  assert.deepEqual(diffLines(["a"], ["a", "b"]).map((e) => e.type), ["same", "add"]);
  assert.deepEqual(diffLines(["a", "b"], ["b"]).map((e) => e.type), ["del", "same"]);
  assert.deepEqual(diffLines([], ["x"]), [{ type: "add", text: "x" }]);
  assert.deepEqual(diffLines(["x"], []), [{ type: "del", text: "x" }]);
});
