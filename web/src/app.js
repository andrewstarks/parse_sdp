// app.js — wires input → engine → report / editor / output / policy.
// Holds the only mutable state; every other module is a view over it.

import { createEngine as createMockEngine } from "./engine_mock.js";
import { detectFormat, fileStem } from "./format.js";
import { clone } from "./docpath.js";
import { dedupeFindings } from "./findings.js";
import { setText } from "./dom.js";
import { initInput } from "./input.js";
import { initReport } from "./report.js";
import { initEditor } from "./editor.js";
import { initOutput } from "./output.js";
import { initPolicy } from "./policy.js";
import { initNav } from "./nav.js";
import { groupExamples, sessionNameOf, BUNDLED_EXAMPLES } from "./examples.js";

const REPO_URL = "https://github.com/andrewstarks/parse_sdp";

// The real engine is an ES module produced by the WASM build; when it is
// missing (serving web/src directly) or fails to instantiate, or when the
// URL carries ?mock=1, the fixture-backed mock stands in.
async function loadEngine() {
  const wantMock = new URLSearchParams(location.search).get("mock") === "1";
  if (!wantMock) {
    try {
      const mod = await import("./engine.js");
      return { engine: await mod.createEngine(), kind: "wasm" };
    } catch (e) {
      console.warn("parse_sdp: WebAssembly engine unavailable, using the fixture mock.", e);
    }
  }
  return { engine: await createMockEngine(), kind: "mock" };
}

async function fetchText(path) {
  const res = await fetch(new URL(path, import.meta.url));
  if (!res.ok) throw new Error(`HTTP ${res.status}`);
  return res.text();
}

// examples/index.json is written by wasm/build.sh; without a build (plain
// web/src) the three bundled fixtures stand in.
async function loadExampleManifest() {
  try {
    const res = await fetch(new URL("./examples/index.json", import.meta.url));
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const manifest = await res.json();
    if (Array.isArray(manifest) && manifest.length > 0) return manifest;
  } catch (e) {
    console.info("parse_sdp: no examples manifest, using bundled examples.", e.message);
  }
  // Title the bundled files from their own s= line, as the build does.
  return Promise.all(BUNDLED_EXAMPLES.map(async (e) => ({ ...e, title: sessionNameOf(await fetchText(e.path).catch(() => "")) })));
}

function describeError(err) {
  if (!err) return "Unknown error.";
  const where = err.line ? ` (line ${err.line}${err.col ? `:${err.col}` : ""})` : err.field_path ? ` (${err.field_path})` : "";
  return `${err.message ?? "error"}${where}`;
}

async function main() {
  initNav(document.querySelector(".site-header"));
  const engineStatus = document.querySelector("#engine-status");
  const { engine, kind } = await loadEngine();
  const v = engine.version ?? {};
  engineStatus.classList.toggle("is-mock", kind === "mock");
  setText(engineStatus, kind === "wasm" ? `Engine: parse_sdp ${v.parse_sdp ?? ""} (WebAssembly)` : "Engine: mock (recorded fixtures; results for unknown inputs are illustrative)");
  setText(document.querySelector("#footer-versions"),
    `parse_sdp ${v.parse_sdp ?? "?"} · ${v.lua ?? "Lua"} · ${v.lpeg ?? "LPeg"} · ${kind === "wasm" ? "compiled to WebAssembly with Emscripten" : "mock engine"}`);
  document.querySelector(".site-footer a").href = REPO_URL;

  // ── state ────────────────────────────────────────────────────────────
  const state = {
    mode: null,          // "sdp" (input text was reported) | "doc" (a table was validated)
    inputText: "",       // text the user supplied (re-reported on policy change)
    baselineText: "",    // serialization before any edit; the output diff baseline
    sourceText: "",      // text the current findings refer to
    currentText: "",     // latest serialized SDP
    doc: null,           // working document (mutated by the editor)
    tiers: null,
    edited: false,
    stem: "session",
  };

  const report = initReport(document.querySelector("#report"), {
    onSelect: (finding) => { if (!finding.line && finding.field_path) editor.highlightPath(finding.field_path); },
  });
  const editor = initEditor(document.querySelector("#editor"), { onChange: () => revalidate() });
  const output = initOutput({ section: document.querySelector("#output"), bar: document.querySelector(".site-header") });
  const policy = initPolicy(document.querySelector("#policy"), { onChange: () => rerun() });
  const input = initInput(document.querySelector("#input"), { onSubmit: analyze, fetchText });

  const [checks, manifest] = await Promise.all([engine.request({ op: "checks" }), loadExampleManifest()]);
  policy.setChecks(checks.ok ? checks.checks : []);
  input.setExamples(groupExamples(manifest));

  function applyTiers(tiers, sourceText) {
    state.tiers = tiers;
    state.sourceText = sourceText;
    report.render({ tiers, text: sourceText });
    editor.markFindings(dedupeFindings(tiers));
  }

  function renderOutput() {
    output.render({ text: state.currentText, baseline: state.baselineText, edited: state.edited, doc: state.doc, stem: state.stem });
  }

  // Text input → report; then serialize the parsed doc once so the output
  // view shows the canonical form even before any edit.
  async function analyzeText(text) {
    const res = await engine.request({ op: "report", text, policy: policy.getPolicy() });
    if (!res.ok) return input.showError(describeError(res.error));
    state.mode = "sdp";
    state.doc = res.doc ? clone(res.doc) : null;
    state.edited = false;
    editor.render(state.doc);
    editor.showSerializeError(null);
    applyTiers(res.tiers, text);
    state.currentText = "";
    if (state.doc) {
      const ser = await engine.request({ op: "to_sdp", doc: state.doc });
      if (ser.ok) state.currentText = ser.text;
    }
    state.baselineText = state.currentText;
    renderOutput();
  }

  // Table input (JSON or Lua) → validate; the response text becomes the
  // baseline the output diff compares against.
  async function analyzeDoc(doc) {
    const res = await engine.request({ op: "validate", doc, policy: policy.getPolicy() });
    if (!res.ok) return input.showError(describeError(res.error));
    state.mode = "doc";
    state.edited = false;
    state.doc = clone(res.serialize_error ? doc : (res.doc ?? doc));
    editor.render(state.doc);
    if (res.serialize_error) {
      editor.showSerializeError(res.serialize_error);
      report.clearReport(`Not validated: ${describeError(res.serialize_error)}`);
      state.tiers = null;
      state.baselineText = state.currentText = state.sourceText = "";
      renderOutput();
      return;
    }
    editor.showSerializeError(null);
    state.baselineText = state.currentText = res.text;
    applyTiers(res.tiers, res.text);
    renderOutput();
  }

  async function analyze(text, fileName) {
    input.showError(null);
    state.stem = fileStem(fileName);
    state.inputText = text;
    if (text.trim() === "") {
      state.doc = null;
      state.tiers = null;
      editor.render(null);
      report.clearReport();
      renderOutput();
      return;
    }
    const fmt = detectFormat(text);
    try {
      if (fmt.kind === "sdp") return await analyzeText(text);
      if (fmt.kind === "json") return await analyzeDoc(fmt.value);
      const res = await engine.request({ op: "from_lua", source: text });
      if (!res.ok) return input.showError(`Lua table literal: ${describeError(res.error)}`);
      return await analyzeDoc(res.doc);
    } catch (e) {
      input.showError(`Engine failure: ${e.message}`);
    }
  }

  // Editor change (debounced in the editor): serialize + re-report.
  async function revalidate() {
    if (!state.doc) return;
    state.edited = true;
    const res = await engine.request({ op: "validate", doc: state.doc, policy: policy.getPolicy() });
    if (!res.ok) return report.setStatus(`Validation failed: ${describeError(res.error)}`);
    if (res.serialize_error) {
      editor.showSerializeError(res.serialize_error);
      report.setStatus(`Report is stale: ${describeError(res.serialize_error)}`);
      state.currentText = "";
      renderOutput();
      return;
    }
    editor.showSerializeError(null);
    state.currentText = res.text;
    applyTiers(res.tiers, res.text);
    renderOutput();
  }

  // Policy changed: redo whatever produced the current report.
  function rerun() {
    if (state.mode === "sdp" && !state.edited) return analyzeText(state.inputText);
    if (state.doc) return revalidate();
    return undefined;
  }
}

main().catch((e) => {
  console.error(e);
  const el = document.querySelector("#engine-status");
  if (el) setText(el, `Failed to start: ${e.message}`);
});
