import { test } from "node:test";
import assert from "node:assert/strict";
import { parsePath, pathToString, resolvePath, getAt, setAt, clone } from "../src/docpath.js";

const doc = {
  version: "0",
  session: {
    name: "x",
    attributes: [
      { name: "group", semantics: "DUP", tags: ["1", "2"] },
      { name: "group", semantics: "DUP", tags: ["3", "4"] },
      { name: "tool", value: "t" },
    ],
  },
  media: [
    {
      media: "video",
      port: 5000,
      attributes: [
        { name: "rtpmap", payload_type: 96, encoding: "raw", clock_rate: 90000 },
        { name: "fmtp", payload_type: 96, params: [["width", "1920"], ["IPMX", true]] },
        { name: "fmtp", payload_type: 97, params: [] },
        { name: "mediaclk", mode: "direct", offset: 0 },
      ],
    },
  ],
};

test("parsePath splits keys, indices and selectors", () => {
  assert.deepEqual(parsePath("media[0].attributes[fmtp:pt=96]"), ["media", 0, "attributes", { selector: "fmtp:pt=96" }]);
  assert.deepEqual(parsePath("session.attributes[group][1]"), ["session", "attributes", { selector: "group" }, 1]);
  assert.deepEqual(parsePath("origin.sess_id"), ["origin", "sess_id"]);
  assert.deepEqual(parsePath(""), []);
});

test("pathToString renders a plain path canonically", () => {
  assert.equal(pathToString(["media", 0, "attributes", 2, "params", 1, 0]), "media[0].attributes[2].params[1][0]");
  assert.equal(pathToString([]), "");
});

test("resolvePath: serializer-style plain paths", () => {
  assert.deepEqual(resolvePath(doc, "media[0].attributes[1].payload_type"), { path: ["media", 0, "attributes", 1, "payload_type"], exact: true });
});

test("resolvePath: name:pt selector picks the matching attribute", () => {
  assert.deepEqual(resolvePath(doc, "media[0].attributes[fmtp:pt=97]"), { path: ["media", 0, "attributes", 2], exact: true });
  assert.deepEqual(resolvePath(doc, "media[0].attributes[fmtp:pt=96]").path, ["media", 0, "attributes", 1]);
});

test("resolvePath: bare name selector picks the first match; [k] after it picks the k-th", () => {
  assert.deepEqual(resolvePath(doc, "media[0].attributes[fmtp]").path, ["media", 0, "attributes", 1]);
  assert.deepEqual(resolvePath(doc, "session.attributes[group][1]").path, ["session", "attributes", 1]);
  assert.deepEqual(resolvePath(doc, "session.attributes[group][0].tags"), { path: ["session", "attributes", 0, "tags"], exact: true });
});

test("resolvePath: unresolvable tail returns the deepest existing prefix", () => {
  assert.deepEqual(resolvePath(doc, "media[0].attributes[hkep]"), { path: ["media", 0, "attributes"], exact: false });
  assert.deepEqual(resolvePath(doc, "media[3].port"), { path: ["media"], exact: false });
  assert.deepEqual(resolvePath(doc, "media[0].attributes[fmtp:pt=99].params"), { path: ["media", 0, "attributes"], exact: false });
});

test("getAt / setAt round-trip and delete on undefined", () => {
  const d = clone(doc);
  setAt(d, ["media", 0, "port"], 5002);
  assert.equal(getAt(d, ["media", 0, "port"]), 5002);
  setAt(d, ["media", 0, "port"], undefined);
  assert.equal("port" in d.media[0], false);
  setAt(d, ["media", 0, "attributes", 0], undefined);
  assert.equal(d.media[0].attributes.length, 3);
  assert.equal(d.media[0].attributes[0].name, "fmtp");
  assert.equal(getAt(d, ["nope", "x"]), undefined);
  assert.equal(doc.media[0].port, 5000, "clone must not alias the original");
});
