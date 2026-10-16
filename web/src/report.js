// report.js — tier cards, de-duplicated findings list with filters, and
// the numbered source view with line highlighting.

import { h, replace, setText } from "./dom.js";
import { TIER_ORDER, TIER_LABELS, dedupeFindings, filterRows, groupRows, tierSummary, locationLabel } from "./findings.js";
import { splitLines } from "./format.js";
import { canOverride, SEVERITIES } from "./checks.js";

// policy: the store from policy.js (getCheck / overrideFor / setSeverity /
// silencedCount / open), shared with the popout panel.
export function initReport(root, { onSelect, policy }) {
  const cards = root.querySelector("#tier-cards");
  const status = root.querySelector("#report-status");
  const list = root.querySelector("#findings");
  const source = root.querySelector("#source-lines");
  const filterTier = root.querySelector("#filter-tier");
  const filterError = root.querySelector("#filter-error");
  const filterWarn = root.querySelector("#filter-warn");
  const filterCount = root.querySelector("#filter-count");
  const silenced = root.querySelector("#silenced-notice");

  let rows = [];
  let lineMarks = new Map();
  let selectedKey = null;

  function renderCards(tiers) {
    replace(cards, TIER_ORDER.map((name, i) => {
      const tier = tiers?.[name];
      const s = tierSummary(tier);
      const state = !tier ? "none" : s.passes ? "pass" : "fail";
      // The inner wrapper is what the card's container query lays out.
      return h("article", { class: `tier-card ${state}`, "aria-label": `${TIER_LABELS[name]} tier` },
        h("div", { class: "tier-body" },
          h("div", { class: "tier-name" }, i > 0 ? h("span", { class: "tier-arrow" }, "→ ") : null, TIER_LABELS[name]),
          h("div", { class: "tier-state" }, !tier ? "—" : s.passes ? "Pass" : "Fail"),
          h("div", { class: "tier-counts" }, tier ? `${s.errors} error${s.errors === 1 ? "" : "s"} · ${s.warnings} warning${s.warnings === 1 ? "" : "s"}` : "not run")));
    }));
  }

  function currentFilter() {
    const severities = new Set();
    if (filterError.checked) severities.add("error");
    if (filterWarn.checked) severities.add("warn");
    return { tier: filterTier.value, severities };
  }

  let expanded = new Set();
  let gid = 0;

  function findingBody(f, row, extra) {
    return [
      h("span", { class: `badge ${f.severity}` }, f.severity === "warn" ? "warn" : "error"),
      h("span", { class: "f-main" },
        h("span", { class: "f-id" }, f.id || f.code || ""),
        h("span", { class: "f-msg" }, f.message || ""),
        h("span", { class: "f-sub" },
          f.spec_ref ? h("span", {}, f.spec_ref) : null,
          f.code && f.id ? h("span", {}, f.code) : null,
          row.tiers.map((t) => h("span", { class: "badge tier" }, TIER_LABELS[t])),
          extra)),
    ];
  }

  // Compact severity control for the check behind a row. None for
  // PARSE_ERROR rows (no id) or hard-syntactic checks.
  function severityControl(f) {
    const check = f.id ? policy.getCheck(f.id) : undefined;
    if (!canOverride(check)) return null;
    const sel = h("select", {
      class: "row-severity", "aria-label": `Severity for ${check.id}`, value: policy.overrideFor(check.id),
      title: `Severity for ${check.id} (default ${check.default_severity})`,
      on: { change: () => policy.setSeverity(check.id, sel.value) },
    },
      h("option", { value: "" }, `default (${check.default_severity})`),
      SEVERITIES.map((s) => h("option", { value: s }, s)));
    sel.value = policy.overrideFor(check.id);
    return sel;
  }

  function renderSingle(row) {
    const f = row.finding;
    const btn = h("button", {
      type: "button",
      class: `finding${row.key === selectedKey ? " is-selected" : ""}`,
      on: { click: () => select(row, btn) },
    }, findingBody(f, row), h("span", { class: "f-loc" }, locationLabel(f)));
    return h("li", { class: "finding-row" }, btn, severityControl(f));
  }

  // A collapsed group: the row toggles a list of its line numbers; each
  // line number behaves like a normal finding click.
  function renderGroup(row) {
    const f = row.finding;
    const id = `fg-${++gid}`;
    const open = expanded.has(row.key);
    const list = h("div", { class: "group-lines", id, hidden: !open, role: "group", "aria-label": `Lines with ${f.id}` },
      row.members.map((m) => {
        const lb = h("button", { type: "button", class: "line-chip", on: { click: () => select(m, lb) } }, String(m.finding.line));
        return lb;
      }));
    const toggle = h("button", {
      type: "button", class: "finding finding-toggle", "aria-expanded": String(open), "aria-controls": id,
      on: { click: () => {
        const now = toggle.getAttribute("aria-expanded") !== "true";
        toggle.setAttribute("aria-expanded", String(now));
        list.hidden = !now;
        if (now) expanded.add(row.key); else expanded.delete(row.key);
      } },
    }, findingBody(f, row, h("span", { class: "badge count" }, `${row.count} lines`)),
      h("span", { class: "f-loc" }, `${row.lines[0]}–${row.lines[row.lines.length - 1]}`));
    return h("li", { class: "finding-row finding-group" }, toggle, severityControl(f), list);
  }

  function renderNotice() {
    const n = policy.silencedCount();
    if (n === 0) {
      replace(silenced);
      silenced.hidden = true;
      return;
    }
    silenced.hidden = false;
    replace(silenced, `${n} check${n === 1 ? "" : "s"} silenced · `,
      // stopPropagation: the panel's outside-click handler must not see this click.
      h("button", { type: "button", class: "link", on: { click: (e) => { e.stopPropagation(); policy.open(); } } }, "show policy"));
  }

  function renderRows() {
    renderNotice();
    const visible = filterRows(rows, currentFilter());
    const grouped = groupRows(visible);
    const groups = grouped.filter((r) => r.group).length;
    setText(filterCount, rows.length
      ? `${visible.length} of ${rows.length} findings shown${groups ? ` · ${groups} repeated check${groups === 1 ? "" : "s"} collapsed` : ""}`
      : "");
    if (grouped.length === 0) {
      replace(list, h("li", { class: "empty" }, rows.length ? "No findings match the current filter." : "No findings."));
      return;
    }
    replace(list, grouped.map((row) => (row.group ? renderGroup(row) : renderSingle(row))));
  }

  function select(row, btn) {
    selectedKey = row.key;
    for (const el of list.querySelectorAll(".is-selected")) el.classList.remove("is-selected");
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
  return { render, clearReport, highlightLine, refreshRows: renderRows, setStatus: (msg) => setText(status, msg), getRows: () => rows };
}
