// The mock answers from copies of web/fixtures under web/src so they ship
// with the site. This keeps the copies honest.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { SRC, FIXTURES } from "./helpers.js";

const COPIES = [
  ["report_ipmx_typical.json", "mock/"],
  ["report_st2110_invalid.json", "mock/"],
  ["report_generic_pathological.json", "mock/"],
  ["checks.json", "mock/"],
  ["version.json", "mock/"],
  ["ipmx_typical.sdp", "examples/"],
  ["st2110_invalid.sdp", "examples/"],
  ["generic_pathological.sdp", "examples/"],
];

for (const [name, dir] of COPIES) {
  test(`web/src/${dir}${name} matches web/fixtures/${name}`, async () => {
    assert.equal(await readFile(`${SRC}${dir}${name}`, "utf8"), await readFile(`${FIXTURES}${name}`, "utf8"));
  });
}
