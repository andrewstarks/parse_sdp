// checks.js — policy helpers over the `checks` registry. Pure.

export const SEVERITIES = ["error", "warn", "off"];

export function prefixOf(id) {
  const dot = String(id).indexOf(".");
  return dot === -1 ? String(id) : String(id).slice(0, dot);
}

// Human label for an id prefix. Unknown prefixes fall back to themselves.
export function prefixLabel(prefix) {
  if (prefix === "sdp") return "RFC 8866 — sdp";
  if (prefix === "st2110") return "ST 2110 — cross-section";
  if (prefix === "ipmx") return "IPMX — general";
  let m = /^st2110-(\d+)$/.exec(prefix);
  if (m) return `SMPTE ST 2110-${m[1]}`;
  m = /^tr-10-(\d+)$/.exec(prefix);
  if (m) return `VSF TR-10-${m[1]} (IPMX)`;
  return prefix;
}

// Tier ordering of prefixes: base, then ST 2110 by part number, then IPMX.
function prefixRank(prefix) {
  if (prefix === "sdp") return [0, 0];
  if (prefix === "st2110") return [1, 0];
  let m = /^st2110-(\d+)$/.exec(prefix);
  if (m) return [1, Number(m[1])];
  if (prefix === "ipmx") return [2, 0];
  m = /^tr-10-(\d+)$/.exec(prefix);
  if (m) return [2, Number(m[1])];
  return [3, 0];
}

export function comparePrefix(a, b) {
  const ra = prefixRank(a);
  const rb = prefixRank(b);
  if (ra[0] !== rb[0]) return ra[0] - rb[0];
  if (ra[1] !== rb[1]) return ra[1] - rb[1];
  return a < b ? -1 : a > b ? 1 : 0;
}

// [{ prefix, label, checks: [...sorted by id] }] in tier order.
export function groupChecks(checks) {
  const groups = new Map();
  for (const c of checks ?? []) {
    const p = prefixOf(c.id);
    if (!groups.has(p)) groups.set(p, { prefix: p, label: prefixLabel(p), checks: [] });
    groups.get(p).checks.push(c);
  }
  const out = [...groups.values()].sort((a, b) => comparePrefix(a.prefix, b.prefix));
  for (const g of out) g.checks.sort((a, b) => (a.id < b.id ? -1 : 1));
  return out;
}

// Hard-syntactic checks define parseability and cannot be toggled.
export function isToggleable(check) {
  return check.kind !== "hard-syntactic";
}

// Keep only overrides the engine will accept: known, toggleable ids with a
// valid severity that differs from the default. The bridge rejects a whole
// request over one unknown id, so stale localStorage entries must not leak
// through after the registry changes.
export function sanitizePolicy(overrides, checks) {
  const byId = new Map((checks ?? []).map((c) => [c.id, c]));
  const out = {};
  for (const [id, sev] of Object.entries(overrides ?? {})) {
    const c = byId.get(id);
    if (!c || !isToggleable(c)) continue;
    if (!SEVERITIES.includes(sev)) continue;
    if (sev === c.default_severity) continue;
    out[id] = sev;
  }
  return out;
}

export function countOverrides(policy) {
  return Object.keys(policy ?? {}).length;
}

// Severity a check currently reports at: the override when one is set,
// otherwise the registry default. Unknown checks (e.g. PARSE_ERROR rows,
// which carry no id) have no severity policy and yield undefined.
export function effectiveSeverity(check, policy) {
  if (!check) return undefined;
  const sev = policy?.[check.id];
  return SEVERITIES.includes(sev) ? sev : check.default_severity;
}

// Whether a finding row can carry a severity control.
export function canOverride(check) {
  return Boolean(check && isToggleable(check));
}

export function countSilenced(policy) {
  return Object.values(policy ?? {}).filter((s) => s === "off").length;
}
