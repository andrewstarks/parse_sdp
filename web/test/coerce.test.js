import { test } from "node:test";
import assert from "node:assert/strict";
import { kindOf, coerceScalar, coerceToken, emptyOfKind, scalarToText } from "../src/coerce.js";

test("kindOf classifies values", () => {
  assert.equal(kindOf(1), "number");
  assert.equal(kindOf("1"), "string");
  assert.equal(kindOf(true), "boolean");
  assert.equal(kindOf([]), "array");
  assert.equal(kindOf({}), "object");
  assert.equal(kindOf(null), "null");
});

test("coerceScalar keeps numbers numeric and strings as strings", () => {
  assert.equal(coerceScalar("5004", "number"), 5004);
  assert.equal(coerceScalar(" 90000 ", "number"), 90000);
  assert.equal(coerceScalar("-1.5e3", "number"), -1500);
  assert.equal(coerceScalar("5004", "string"), "5004", "a string field never becomes a number");
  assert.equal(coerceScalar("abc", "number"), "abc", "non-numeric text is kept for the engine to flag");
});

test("coerceScalar: empty text means absent", () => {
  assert.equal(coerceScalar("", "number"), undefined);
  assert.equal(coerceScalar("", "string"), undefined);
});

test("coerceToken follows sibling kind", () => {
  assert.equal(coerceToken(" 96 "), "96");
  assert.equal(coerceToken("96", "number"), 96);
  assert.equal(coerceToken("  "), undefined);
});

test("emptyOfKind and scalarToText", () => {
  assert.deepEqual(emptyOfKind("array"), []);
  assert.equal(emptyOfKind("boolean"), true);
  assert.equal(scalarToText(0), "0");
  assert.equal(scalarToText(undefined), "");
});
