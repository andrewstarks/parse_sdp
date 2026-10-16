// policy.js — severity overrides per check: one store (persisted in
// localStorage) behind two surfaces: the popout panel anchored to the
// report toolbar (filter box, grouped list with a select per check, count,
// reset) and the per-row controls that report.js renders through
// setSeverity(). Every change re-runs the current analysis via onChange.

import { h, replace, setText } from "./dom.js";
import { groupChecks, sanitizePolicy, countOverrides, countSilenced, isToggleable, SEVERITIES } from "./checks.js";

const STORAGE_KEY = "parse_sdp.policy.v1";

function loadStored() {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY) ?? "{}") ?? {};
  } catch {
    return {};
  }
}

function store(policy) {
  try {
    if (countOverrides(policy) === 0) localStorage.removeItem(STORAGE_KEY);
    else localStorage.setItem(STORAGE_KEY, JSON.stringify(policy));
  } catch {
    // Private mode or storage disabled: overrides simply do not persist.
  }
}

// root: the report section, which holds #policy-toggle and #policy-panel.
export function initPolicy(root, { onChange }) {
  const toggle = root.querySelector("#policy-toggle");
  const toggleCount = toggle.querySelector(".count");
  const panel = root.querySelector("#policy-panel");
  const groupsEl = panel.querySelector("#policy-groups");
  const countEl = panel.querySelector("#policy-count");
  const filterEl = panel.querySelector("#policy-filter");
  const resetBtn = panel.querySelector("#policy-reset");
  const closeBtn = panel.querySelector("#policy-close");
  let checks = [];
  let byId = new Map();
  let policy = {};
  let rowsById = new Map();
  const listeners = new Set();

  // ── popout ───────────────────────────────────────────────────────────
  function isOpen() {
    return toggle.getAttribute("aria-expanded") === "true";
  }
  function setOpen(open, { focus = true } = {}) {
    panel.hidden = !open;
    toggle.setAttribute("aria-expanded", String(open));
    if (open && focus) filterEl.focus();
  }
  toggle.addEventListener("click", () => setOpen(!isOpen()));
  closeBtn.addEventListener("click", () => { setOpen(false); toggle.focus(); });
  document.addEventListener("keydown", (e) => {
    if (e.key === "Escape" && isOpen()) {
      e.preventDefault();
      setOpen(false);
      toggle.focus();
    }
  });
  document.addEventListener("click", (e) => {
    if (isOpen() && !panel.contains(e.target) && !toggle.contains(e.target)) setOpen(false, { focus: false });
  });

  // ── store ────────────────────────────────────────────────────────────
  function getPolicy() {
    return sanitizePolicy(policy, checks);
  }

  function updateCount() {
    const n = countOverrides(policy);
    setText(toggleCount, n ? String(n) : "");
    toggleCount.hidden = n === 0;
    toggle.setAttribute("aria-label", n ? `Policy, ${n} override${n === 1 ? "" : "s"} active` : "Policy");
    setText(countEl, n === 0 ? "No overrides" : `${n} override${n === 1 ? "" : "s"} active`);
    resetBtn.disabled = n === 0;
    for (const group of groupsEl.querySelectorAll(".policy-group")) {
      const k = JSON.parse(group.dataset.ids).filter((id) => policy[id]).length;
      setText(group.querySelector(".group-overrides"), k ? `${k} overridden` : "");
    }
  }

  function syncRow(id) {
    const tr = rowsById.get(id);
    if (!tr) return;
    tr.classList.toggle("is-override", Boolean(policy[id]));
    const sel = tr.querySelector("select");
    if (sel) sel.value = policy[id] ?? "";
  }

  // Shared by the panel and the per-finding controls. `sev` of "" or the
  // default clears the override.
  function setSeverity(id, sev) {
    const c = byId.get(id);
    if (!c || !isToggleable(c)) return;
    if (!sev || sev === c.default_severity) delete policy[id];
    else if (SEVERITIES.includes(sev)) policy[id] = sev;
    else return;
    store(policy);
    syncRow(id);
    updateCount();
    for (const fn of listeners) fn();
    onChange?.(getPolicy());
  }

  // ── panel list ───────────────────────────────────────────────────────
  function severitySelect(check, label) {
    const sel = h("select", { "aria-label": label, on: { change: () => setSeverity(check.id, sel.value) } },
      h("option", { value: "" }, `default (${check.default_severity})`),
      SEVERITIES.map((s) => h("option", { value: s, selected: policy[check.id] === s }, s)));
    return sel;
  }

  function renderRow(check) {
    const tr = h("tr", { class: policy[check.id] ? "is-override" : "", dataset: { search: `${check.id} ${check.spec_ref ?? ""} ${check.message_template ?? ""}`.toLowerCase() } },
      h("td", { class: "pid" }, check.id, h("div", { class: "meta" }, check.message_template ?? "")),
      h("td", { class: "pkind" }, h("span", { class: "badge kind" }, check.kind)),
      h("td", { class: "pspec" }, check.spec_ref ?? ""),
      h("td", {}, isToggleable(check) ? severitySelect(check, `Severity for ${check.id}`) : h("span", { class: "meta" }, "fixed")));
    rowsById.set(check.id, tr);
    return tr;
  }

  function render() {
    rowsById = new Map();
    replace(groupsEl, groupChecks(checks).map((g) => h("details", { class: "card policy-group", dataset: { ids: JSON.stringify(g.checks.map((c) => c.id)) } },
      h("summary", {},
        h("span", { class: "card-title" }, g.label),
        h("span", { class: "badge tier" }, g.prefix),
        h("span", { class: "group-count" }, `${g.checks.length} check${g.checks.length === 1 ? "" : "s"}`),
        h("span", { class: "group-overrides meta" })),
      h("div", { class: "card-body" },
        h("table", { class: "policy-table" },
          h("thead", {}, h("tr", {}, h("th", {}, "Check"), h("th", { class: "pkind" }, "Kind"), h("th", {}, "Spec"), h("th", {}, "Severity"))),
          h("tbody", {}, g.checks.map(renderRow)))))));
    applyFilter();
    updateCount();
  }

  function applyFilter() {
    const q = filterEl.value.trim().toLowerCase();
    for (const group of groupsEl.querySelectorAll(".policy-group")) {
      let visible = 0;
      for (const tr of group.querySelectorAll("tbody tr")) {
        const show = !q || tr.dataset.search.includes(q);
        tr.hidden = !show;
        if (show) visible++;
      }
      group.hidden = visible === 0;
      if (q && visible) group.open = true;
    }
  }

  filterEl.addEventListener("input", applyFilter);
  resetBtn.addEventListener("click", () => {
    policy = {};
    store(policy);
    render();
    for (const fn of listeners) fn();
    onChange?.(getPolicy());
  });

  // checks: the `checks` array from the engine.
  function setChecks(list) {
    checks = list ?? [];
    byId = new Map(checks.map((c) => [c.id, c]));
    policy = sanitizePolicy(loadStored(), checks);
    store(policy);
    render();
  }

  return {
    setChecks,
    getPolicy,
    setSeverity,
    getCheck: (id) => byId.get(id),
    overrideFor: (id) => policy[id] ?? "",
    silencedCount: () => countSilenced(policy),
    open: () => setOpen(true),
    // Called on every store change (panel or row), before onChange.
    subscribe: (fn) => listeners.add(fn),
  };
}
