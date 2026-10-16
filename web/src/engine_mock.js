// engine_mock.js — stand-in for engine.js that answers from the recorded
// fixtures under ./mock and ./examples. Same interface as the real engine:
// createEngine(options) → { request(obj) → Promise<response>, version }.
//
// Used when the WebAssembly module cannot be loaded or the page URL has
// ?mock=1. Known inputs (the three example files) get their exact recorded
// responses; anything else gets a plausible report derived from the
// pathological fixture, clearly not a real analysis.

import { canonicalText, splitLines, toCRLF } from "./format.js";
import { clone } from "./docpath.js";
import { mockSerialize } from "./mock_serialize.js";
import { parseLuaLiteral } from "./lua_literal.js";
import { TIER_ORDER } from "./findings.js";

export const FIXTURES = [
  { name: "ipmx_typical", sdp: "examples/ipmx_typical.sdp", report: "mock/report_ipmx_typical.json" },
  { name: "st2110_invalid", sdp: "examples/st2110_invalid.sdp", report: "mock/report_st2110_invalid.json" },
  { name: "generic_pathological", sdp: "examples/generic_pathological.sdp", report: "mock/report_generic_pathological.json" },
];
const FALLBACK = "generic_pathological";

async function fetchLoader(relPath) {
  const res = await fetch(new URL(relPath, import.meta.url));
  if (!res.ok) throw new Error(`mock fixture ${relPath}: HTTP ${res.status}`);
  return relPath.endsWith(".json") ? res.json() : res.text();
}

function err(message, code = "INVALID_VALUE") {
  return { ok: false, error: { message, code } };
}

const LF_ONLY_ID = "sdp.line.lf-only-line-ending";

// Re-anchor a recorded tier onto a different text: per-line findings are
// regenerated for bare-LF lines (the one check that depends purely on line
// endings), other line-anchored findings are kept only while their line
// exists, and document-level findings are kept as they are.
function retarget(tier, text) {
  const lines = splitLines(text);
  const bareLF = text.includes("\n") && !text.includes("\r\n");
  const template = tier.findings.find((f) => f.id === LF_ONLY_ID);
  const findings = [];
  for (const f of tier.findings) {
    if (f.id === LF_ONLY_ID) continue;
    if (f.line > lines.length) continue;
    findings.push(f.line > 0 ? { ...f, line_text: lines[f.line - 1] } : f);
  }
  if (bareLF && template) {
    lines.forEach((line, i) => {
      if (i === 0) return;
      findings.push({ ...template, line: i + 1, line_text: line });
    });
  }
  const passes = !findings.some((f) => f.severity === "error");
  return { passes, findings };
}

function applyPolicy(tiers, policy) {
  if (!policy || Object.keys(policy).length === 0) return tiers;
  for (const name of TIER_ORDER) {
    const tier = tiers[name];
    tier.findings = tier.findings
      .filter((f) => policy[f.id] !== "off")
      .map((f) => (policy[f.id] ? { ...f, severity: policy[f.id] } : f));
    tier.passes = !tier.findings.some((f) => f.severity === "error");
  }
  return tiers;
}

export async function createEngine(options = {}) {
  const load = options.load ?? fetchLoader;
  const cache = new Map();
  const get = (path) => {
    if (!cache.has(path)) cache.set(path, load(path));
    return cache.get(path);
  };

  async function findFixture(text) {
    const want = canonicalText(text);
    for (const f of FIXTURES) {
      if (canonicalText(await get(f.sdp)) === want) return f;
    }
    return null;
  }

  async function fixtureFor(doc) {
    const name = doc?.session?.name;
    for (const f of FIXTURES) {
      const rep = await get(f.report);
      if (rep.doc?.session?.name === name) return f;
    }
    return FIXTURES.find((f) => f.name === FALLBACK);
  }

  async function report(text, policy, fixture) {
    if (typeof text !== "string") return err("text must be a string");
    const exact = fixture ?? (await findFixture(text));
    const rep = clone(await get((exact ?? FIXTURES.find((f) => f.name === FALLBACK)).report));
    const out = { ok: true, tiers: {}, doc: rep.doc, mock: exact ? "fixture" : "synthesized" };
    for (const name of TIER_ORDER) {
      out.tiers[name] = exact ? rep.tiers[name] : retarget(rep.tiers[name], text);
    }
    applyPolicy(out.tiers, policy);
    return out;
  }

  const ops = {
    async version() {
      return clone(await get("mock/version.json"));
    },
    async checks() {
      return clone(await get("mock/checks.json"));
    },
    report(req) {
      return report(req.text, req.policy);
    },
    async to_sdp(req) {
      if (req.doc === null || typeof req.doc !== "object") return err("doc must be an object");
      const r = mockSerialize(req.doc);
      return r.error ? { ok: false, error: r.error } : { ok: true, text: r.text };
    },
    async validate(req) {
      if (req.doc === null || typeof req.doc !== "object") return err("doc must be an object");
      const r = mockSerialize(req.doc);
      if (r.error) return { ok: true, serialize_error: r.error };
      const fixture = await fixtureFor(req.doc);
      const text = toCRLF(r.text);
      const exact = canonicalText(await get(fixture.sdp)) === canonicalText(text) ? fixture : null;
      const out = await report(text, req.policy, exact);
      if (!exact) {
        // Edited doc: keep the user's table, re-anchor the fixture's tiers.
        const rep = clone(await get(fixture.report));
        for (const name of TIER_ORDER) out.tiers[name] = retarget(rep.tiers[name], text);
        applyPolicy(out.tiers, req.policy);
        out.doc = clone(req.doc);
      }
      out.text = text;
      return out;
    },
    async from_lua(req) {
      if (typeof req.source !== "string") return err("source must be a string");
      try {
        const doc = parseLuaLiteral(req.source);
        if (doc === null || typeof doc !== "object") return err("chunk must produce a table");
        return { ok: true, doc };
      } catch (e) {
        return err(e.message, "MALFORMED_LINE");
      }
    },
  };

  async function request(obj) {
    const op = ops[obj?.op];
    if (!op) return err(`unknown op: ${obj?.op}`);
    return op(obj);
  }

  const version = await request({ op: "version" });
  return { request, version, mock: true };
}
