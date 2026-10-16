// policy.js — severity overrides per check, grouped by id prefix, persisted
// in localStorage. The app passes getPolicy() on every report/validate.

import { h, replace, setText } from "./dom.js";
import { groupChecks, sanitizePolicy, countOverrides, isToggleable, SEVERITIES } from "./checks.js";

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

export function initPolicy(root, { onChange }) {
  const groupsEl = root.querySelector("#policy-groups");
  const countEl = root.querySelector("#policy-count");
  const filterEl = root.querySelector("#policy-filter");
  const resetBtn = root.querySelector("#policy-reset");
  let checks = [];
  let policy = {};
  let rowsById = new Map();

  function updateCount() {
    const n = countOverrides(policy);
    setText(countEl, n === 0 ? "No overrides" : `${n} override${n === 1 ? "" : "s"} active`);
    resetBtn.disabled = n === 0;
    for (const group of groupsEl.querySelectorAll(".policy-group")) {
      const ids = JSON.parse(group.dataset.ids);
      const k = ids.filter((id) => policy[id]).length;
      setText(group.querySelector(".group-overrides"), k ? `${k} overridden` : "");
    }
  }

  function setSeverity(check, sev) {
    if (!sev || sev === check.default_severity) delete policy[check.id];
    else policy[check.id] = sev;
    rowsById.get(check.id)?.classList.toggle("is-override", Boolean(policy[check.id]));
    store(policy);
    updateCount();
    onChange?.(getPolicy());
  }

  function renderRow(check) {
    const sel = h("select", { "aria-label": `Severity for ${check.id}`, on: { change: () => setSeverity(check, sel.value) } },
      h("option", { value: "" }, `default (${check.default_severity})`),
      SEVERITIES.map((s) => h("option", { value: s, selected: policy[check.id] === s }, s)));
    const tr = h("tr", { class: policy[check.id] ? "is-override" : "", dataset: { search: `${check.id} ${check.spec_ref ?? ""} ${check.message_template ?? ""}`.toLowerCase() } },
      h("td", { class: "pid" }, check.id, h("div", { class: "meta" }, check.message_template ?? "")),
      h("td", { class: "pkind" }, h("span", { class: "badge kind" }, check.kind)),
      h("td", { class: "pspec" }, check.spec_ref ?? ""),
      h("td", {}, isToggleable(check) ? sel : h("span", { class: "meta" }, "fixed")));
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
    onChange?.(getPolicy());
  });

  function getPolicy() {
    return sanitizePolicy(policy, checks);
  }

  // checks: the `checks` array from the engine.
  function setChecks(list) {
    checks = list ?? [];
    policy = sanitizePolicy(loadStored(), checks);
    store(policy);
    render();
  }

  return { setChecks, getPolicy };
}
