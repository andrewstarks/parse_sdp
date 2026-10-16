// report.js — tier cards, de-duplicated findings list with filters, and
// the numbered source view with line highlighting.

import { h, replace, setText } from "./dom.js";
import { TIER_ORDER, TIER_LABELS, dedupeFindings, filterRows, tierSummary, locationLabel } from "./findings.js";
import { splitLines } from "./format.js";

export function initReport(root, { onSelect }) {
  const cards = root.querySelector("#tier-cards");
  const status = root.querySelector("#report-status");
  const list = root.querySelector("#findings");
  const source = root.querySelector("#source-lines");
  const filterTier = root.querySelector("#filter-tier");
  const filterError = root.querySelector("#filter-error");
  const filterWarn = root.querySelector("#filter-warn");
  const filterCount = root.querySelector("#filter-count");

  let rows = [];
  let lineMarks = new Map();
  let selectedKey = null;

  function renderCards(tiers) {
    replace(cards, TIER_ORDER.map((name, i) => {
      const tier = tiers?.[name];
      const s = tierSummary(tier);
      const state = !tier ? "none" : s.passes ? "pass" : "fail";
      return h("article", { class: `tier-card ${state}`, "aria-label": `${TIER_LABELS[name]} tier` },
        h("div", { class: "tier-name" }, i > 0 ? h("span", { class: "tier-arrow" }, "→ ") : null, TIER_LABELS[name]),
        h("div", { class: "tier-state" }, !tier ? "—" : s.passes ? "Pass" : "Fail"),
        h("div", { class: "tier-counts" }, tier ? `${s.errors} error${s.errors === 1 ? "" : "s"} · ${s.warnings} warning${s.warnings === 1 ? "" : "s"}` : "not run"));
    }));
  }

  function currentFilter() {
    const severities = new Set();
    if (filterError.checked) severities.add("error");
    if (filterWarn.checked) severities.add("warn");
    return { tier: filterTier.value, severities };
  }

  function renderRows() {
    const visible = filterRows(rows, currentFilter());
    setText(filterCount, rows.length ? `${visible.length} of ${rows.length} shown` : "");
    if (visible.length === 0) {
      replace(list, h("li", { class: "empty" }, rows.length ? "No findings match the current filter." : "No findings."));
      return;
    }
    replace(list, visible.map((row) => {
      const f = row.finding;
      const btn = h("button", {
        type: "button",
        class: `finding${row.key === selectedKey ? " is-selected" : ""}`,
        on: { click: () => select(row, btn) },
      },
        h("span", { class: `badge ${f.severity}` }, f.severity === "warn" ? "warn" : "error"),
        h("span", { class: "f-main" },
          h("span", { class: "f-id" }, f.id || f.code || ""),
          h("span", { class: "f-msg" }, f.message || ""),
          h("span", { class: "f-sub" },
            f.spec_ref ? h("span", {}, f.spec_ref) : null,
            f.code && f.id ? h("span", {}, f.code) : null,
            row.tiers.map((t) => h("span", { class: "badge tier" }, TIER_LABELS[t])))),
        h("span", { class: "f-loc" }, locationLabel(f)));
      return h("li", {}, btn);
    }));
  }

  function select(row, btn) {
    selectedKey = row.key;
    for (const el of list.querySelectorAll(".finding.is-selected")) el.classList.remove("is-selected");
    btn.classList.add("is-selected");
    const f = row.finding;
    if (f.line > 0) highlightLine(f.line);
    onSelect?.(f);
  }

  function renderSource(text) {
    const lines = splitLines(text ?? "");
    if (!text) {
      replace(source, h("li", { class: "empty" }, "The analyzed text appears here."));
      return;
    }
    replace(source, lines.map((line, i) => {
      const n = i + 1;
      const mark = lineMarks.get(n);
      const cls = mark === "error" ? "has-error" : mark === "warn" ? "has-warn" : "";
      return h("li", { class: cls, dataset: { line: String(n) } },
        h("span", { class: "ln" }, String(n)),
        h("span", { class: "mark", "aria-hidden": "true" }, mark ? "●" : ""),
        h("span", { class: "txt" }, line === "" ? " " : line));
    }));
  }

  function highlightLine(n) {
    for (const el of source.querySelectorAll("li.hl")) el.classList.remove("hl");
    const el = source.querySelector(`li[data-line="${n}"]`);
    if (!el) return;
    el.classList.add("hl");
    el.scrollIntoView({ block: "center", behavior: "smooth" });
  }

  function statusLine(tiers) {
    return TIER_ORDER.map((name) => {
      const s = tierSummary(tiers?.[name]);
      return `${TIER_LABELS[name]}: ${s.passes ? "pass" : "fail"} (${s.errors} errors, ${s.warnings} warnings)`;
    }).join(" · ");
  }

  // tiers: response.tiers; text: the text the findings refer to.
  function render({ tiers, text }) {
    rows = dedupeFindings(tiers);
    lineMarks = new Map();
    for (const row of rows) {
      const f = row.finding;
      if (!f.line) continue;
      if (f.severity === "error" || !lineMarks.has(f.line)) lineMarks.set(f.line, f.severity);
    }
    selectedKey = null;
    renderCards(tiers);
    setText(status, statusLine(tiers));
    renderRows();
    renderSource(text);
  }

  function clearReport(message) {
    rows = [];
    lineMarks = new Map();
    renderCards(null);
    setText(status, message ?? "Nothing analyzed yet.");
    renderRows();
    renderSource("");
  }

  for (const ctl of [filterTier, filterError, filterWarn]) ctl.addEventListener("change", renderRows);

  clearReport();
  return { render, clearReport, highlightLine, setStatus: (msg) => setText(status, msg), getRows: () => rows };
}
