// severity_control.js — the compact per-finding severity <select> used by
// report rows and editor disclosures. Returns null when the check cannot be
// overridden (PARSE_ERROR rows without an id, hard-syntactic checks).

import { h } from "./dom.js";
import { canOverride, SEVERITIES } from "./checks.js";

export function severityControl(policy, findingId) {
  const check = findingId ? policy.getCheck(findingId) : undefined;
  if (!canOverride(check)) return null;
  const sel = h("select", {
    class: "row-severity", "aria-label": `Severity for ${check.id}`,
    title: `Severity for ${check.id} (default ${check.default_severity})`,
    on: { change: () => policy.setSeverity(check.id, sel.value) },
  },
    h("option", { value: "" }, `default (${check.default_severity})`),
    SEVERITIES.map((s) => h("option", { value: s }, s)));
  sel.value = policy.overrideFor(check.id);
  return sel;
}
