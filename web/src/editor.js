// editor.js — structured editor over the document table. Renders the
// table generically: scalars → typed inputs, scalar arrays → token lists,
// object arrays → collapsible cards, fmtp/privacy `params` → key/value
// rows. Mutates the doc in place through docpath.setAt and reports each
// change (debounced) so the app can re-validate.

import { h, replace, setText, debounce } from "./dom.js";
import { kindOf, coerceScalar, coerceToken, emptyOfKind, scalarToText } from "./coerce.js";
import { getAt, setAt, pathToString, resolvePath, clone } from "./docpath.js";
import { attachFindings, countsLabel, shortMessage, summaryEntries } from "./field_findings.js";
import { severityControl } from "./severity_control.js";
import { locationLabel } from "./findings.js";

// Keys whose arrays hold scalars even when empty (dkjson encodes {} as []).
const SCALAR_LISTS = new Set(["fmts", "emails", "phones", "offsets", "src_addresses", "tags"]);

// Display order for well-known keys; anything else follows alphabetically.
const KEY_ORDER = ["name", "version", "origin", "session", "media", "username", "sess_id", "sess_version",
  "net_type", "addr_type", "unicast_address", "info", "uri", "emails", "phones", "connection", "bandwidths",
  "time_descriptions", "time_zones", "attributes", "port", "port_count", "proto", "fmts", "payload_type",
  "encoding", "clock_rate", "channels", "params", "raw", "address", "type", "value", "start", "stop", "repeats",
  "interval", "duration", "offsets", "source", "mode", "offset", "filter_mode", "dest_address", "src_addresses",
  "semantics", "tags", "id", "direction", "adjustment_time"];
const KEY_RANK = new Map(KEY_ORDER.map((k, i) => [k, i]));

// Starting shapes for "add" actions. Attribute templates follow the
// decomposed shapes the serializer requires for known names.
const ATTRIBUTE_TEMPLATES = [
  ["generic", "Generic (name + value)", { name: "", value: "" }],
  ["flag", "Flag (e.g. sendonly)", { name: "sendonly" }],
  ["rtpmap", "rtpmap", { name: "rtpmap", payload_type: 96, encoding: "raw", clock_rate: 90000 }],
  ["fmtp", "fmtp", { name: "fmtp", payload_type: 96, params: [] }],
  ["mediaclk", "mediaclk (direct)", { name: "mediaclk", mode: "direct", offset: 0 }],
  ["ts-refclk", "ts-refclk (ptp)", { name: "ts-refclk", source: "ptp", version: "IEEE1588-2008", grandmaster: "00-00-00-00-00-00-00-00", domain: "0" }],
  ["source-filter", "source-filter", { name: "source-filter", filter_mode: "incl", net_type: "IN", addr_type: "IP4", dest_address: "", src_addresses: [] }],
];
const LIST_TEMPLATES = {
  media: { media: "video", port: 5004, proto: "RTP/AVP", fmts: ["96"], bandwidths: [], attributes: [] },
  bandwidths: { type: "AS", value: 0 },
  time_descriptions: { start: 0, stop: 0, repeats: [] },
  repeats: { interval: 0, duration: 0, offsets: [] },
  time_zones: { adjustment_time: 0, offset: 0 },
};
const FIELD_SUGGESTIONS = {
  "": ["version", "origin", "session", "media"],
  origin: ["username", "sess_id", "sess_version", "net_type", "addr_type", "unicast_address"],
  session: ["name", "info", "uri", "emails", "phones", "connection", "bandwidths", "time_descriptions", "time_zones", "attributes"],
  media: ["media", "port", "port_count", "proto", "fmts", "info", "connection", "bandwidths", "attributes"],
  connection: ["net_type", "addr_type", "address"],
  attributes: ["value", "payload_type", "encoding", "clock_rate", "channels", "params", "raw", "mode", "offset", "source", "version", "grandmaster", "domain", "semantics", "tags", "id", "uri", "direction"],
};

function isScalar(v) {
  return v === null || typeof v !== "object";
}

function orderedKeys(obj) {
  return Object.keys(obj).sort((a, b) => {
    const ra = KEY_RANK.has(a) ? KEY_RANK.get(a) : 1000;
    const rb = KEY_RANK.has(b) ? KEY_RANK.get(b) : 1000;
    return ra !== rb ? ra - rb : a < b ? -1 : a > b ? 1 : 0;
  });
}

function isPairList(v) {
  return Array.isArray(v) && v.every((p) => Array.isArray(p) && p.length === 2 && typeof p[0] === "string");
}

function isScalarList(key, v) {
  if (SCALAR_LISTS.has(key)) return true;
  return v.length > 0 && v.every(isScalar);
}

// Which list key an item path belongs to ("attributes", "media", …).
function listKeyOf(path) {
  for (let i = path.length - 1; i >= 0; i--) if (typeof path[i] === "string") return path[i];
  return "";
}

function previewOf(item) {
  if (isScalar(item)) return scalarToText(item);
  return orderedKeys(item)
    .filter((k) => k !== "name")
    .map((k) => {
      const v = item[k];
      if (isScalar(v)) return `${k}=${scalarToText(v)}`;
      if (Array.isArray(v)) return `${k}[${v.length}]`;
      return `${k}{…}`;
    })
    .join(" ");
}

function titleOf(key, item, index) {
  if (isScalar(item)) return `${key}[${index}]`;
  switch (key) {
    case "attributes": return `a=${item.name ?? "?"}`;
    case "media": return `m=${item.media ?? "?"}`;
    case "bandwidths": return `b=${item.type ?? "?"}:${scalarToText(item.value)}`;
    case "time_descriptions": return `t=${scalarToText(item.start)} ${scalarToText(item.stop)}`;
    case "repeats": return `r=${scalarToText(item.interval)} ${scalarToText(item.duration)}`;
    default: return `${key}[${index}]`;
  }
}

// policy: the store from policy.js, for the per-finding severity controls.
export function initEditor(root, { onChange, policy }) {
  const body = root.querySelector("#editor-root");
  const banner = root.querySelector("#serialize-error");
  const summary = root.querySelector("#editor-summary");
  const summaryCounts = root.querySelector("#editor-summary-title");
  const summaryToggle = root.querySelector("#editor-summary-toggle");
  const summaryList = root.querySelector("#editor-summary-list");
  const SUMMARY_KEY = "parse_sdp.editor.summary.v1";
  let doc = null;
  let openState = new Map();
  let uid = 0;
  let lastRows = [];                 // rows from the last markFindings, re-applied after a re-render
  let lastMarkOptions = {};
  let lastSerializeError = null;
  const expandedFindings = new Set(); // disclosure keys kept open across updates
  const notify = debounce(() => onChange?.(doc), 150);

  const nextId = () => `ed-${++uid}`;

  function pathAttr(path) {
    return pathToString(path);
  }

  // ── scalar rows ──────────────────────────────────────────────────────
  function renderScalarRow(obj, key, path) {
    const value = obj[key];
    const kind = kindOf(value);
    const id = nextId();
    const fieldPath = [...path, key];
    const isName = key === "name" && listKeyOf(path) === "attributes";
    let input;
    if (kind === "boolean") {
      input = h("input", { type: "checkbox", id, checked: value, on: { change: () => { setAt(doc, fieldPath, input.checked); notify(); } } });
    } else {
      input = h("input", {
        type: "text", id, value: scalarToText(value), inputmode: kind === "number" ? "decimal" : null,
        "aria-describedby": null,
        on: {
          change: () => {
            const v = coerceScalar(input.value, kind);
            if (v === undefined && isName) {
              input.value = scalarToText(getAt(doc, fieldPath));
              return;
            }
            setAt(doc, fieldPath, v);
            if (v === undefined) rerender();
            notify();
          },
        },
      });
    }
    const remove = isName ? null : h("button", {
      type: "button", class: "ghost small danger", "aria-label": `Remove ${key}`, title: "Remove field",
      on: { click: () => { setAt(doc, fieldPath, undefined); rerender(); notify(); } },
    }, "×");
    return h("div", { class: `row kind-${kind}`, dataset: { path: pathAttr(fieldPath) } },
      h("label", { for: id }, key, " ", h("span", { class: "kind" }, kind === "string" ? "" : kind)),
      h("div", { class: "row-input" }, input, remove));
  }

  // ── scalar lists (fmts, emails, …) ───────────────────────────────────
  function renderTokens(arr, path, key) {
    const siblingKind = arr.length ? kindOf(arr[0]) : "string";
    const tokens = arr.map((item, i) => {
      const itemPath = [...path, i];
      const input = h("input", {
        type: "text", value: scalarToText(item), size: Math.max(2, scalarToText(item).length), "aria-label": `${key} item ${i + 1}`,
        on: {
          change: () => {
            const v = coerceToken(input.value, siblingKind);
            setAt(doc, itemPath, v);
            if (v === undefined) rerender();
            notify();
          },
        },
      });
      return h("span", { class: "token", dataset: { path: pathAttr(itemPath) } }, input,
        h("button", { type: "button", "aria-label": `Remove ${key} item ${i + 1}`, on: { click: () => { setAt(doc, itemPath, undefined); rerender(); notify(); } } }, "×"));
    });
    const adder = h("input", {
      type: "text", placeholder: "add…", "aria-label": `Add ${key} item`,
      on: {
        change: () => {
          const v = coerceToken(adder.value, siblingKind);
          if (v === undefined) return;
          arr.push(v);
          rerender();
          notify();
        },
      },
    });
    return h("div", { class: "list", dataset: { path: pathAttr(path) } },
      h("span", { class: "list-label" }, key, " ", h("span", { class: "kind" }, "list")),
      h("div", { class: "tokens" }, tokens, adder));
  }

  // ── fmtp / privacy params: ordered [key, value | true] pairs ─────────
  function renderParams(params, path) {
    const rows = params.map((pair, i) => {
      const pairPath = [...path, i];
      const isFlag = pair[1] === true;
      const keyInput = h("input", { type: "text", value: pair[0], "aria-label": `Parameter ${i + 1} key`, on: { change: () => { pair[0] = keyInput.value; notify(); } } });
      const valInput = h("input", { type: "text", value: isFlag ? "" : scalarToText(pair[1]), disabled: isFlag, placeholder: isFlag ? "(flag)" : "", "aria-label": `Parameter ${i + 1} value`,
        on: { change: () => { pair[1] = valInput.value; notify(); } } });
      const flag = h("input", { type: "checkbox", checked: isFlag,
        on: { change: () => { pair[1] = flag.checked ? true : ""; valInput.disabled = flag.checked; valInput.value = ""; valInput.placeholder = flag.checked ? "(flag)" : ""; notify(); } } });
      return h("div", { class: "param-row", dataset: { path: pathAttr(pairPath) } }, keyInput, valInput,
        h("label", { class: "check" }, flag, "flag"),
        h("button", { type: "button", class: "ghost small danger", "aria-label": `Remove parameter ${i + 1}`, on: { click: () => { params.splice(i, 1); rerender(); notify(); } } }, "×"));
    });
    return h("div", { class: "params", dataset: { path: pathAttr(path) } },
      h("span", { class: "params-label" }, "params ", h("span", { class: "kind" }, "ordered key/value")),
      rows,
      h("div", { class: "add-bar" }, h("button", { type: "button", class: "small", on: { click: () => { params.push(["", ""]); rerender(); notify(); } } }, "Add parameter")));
  }

  // ── object cards ─────────────────────────────────────────────────────
  function cardOpen(path, key, inList) {
    const p = pathAttr(path);
    if (openState.has(p)) return openState.get(p);
    return !(inList && key === "attributes");
  }

  function card(title, preview, path, key, { tools = [], inList = false, level = 1 }, bodyChildren) {
    const details = h("details", { class: `card level-${level}`, open: cardOpen(path, key, inList), dataset: { path: pathAttr(path) } },
      h("summary", {}, h("span", { class: "card-title" }, title), preview ? h("span", { class: "card-preview" }, preview) : null,
        h("span", { class: "card-tools" }, tools)),
      h("div", { class: "card-body" }, bodyChildren));
    return details;
  }

  function tool(label, title, onClick, extra = "") {
    return h("button", { type: "button", class: `ghost small ${extra}`, "aria-label": title, title, on: { click: (e) => { e.preventDefault(); onClick(); } } }, label);
  }

  function listItemTools(arr, i) {
    return [
      tool("↑", "Move up", () => { if (i > 0) { [arr[i - 1], arr[i]] = [arr[i], arr[i - 1]]; rerender(); notify(); } }),
      tool("↓", "Move down", () => { if (i < arr.length - 1) { [arr[i + 1], arr[i]] = [arr[i], arr[i + 1]]; rerender(); notify(); } }),
      tool("⧉", "Duplicate", () => { arr.splice(i + 1, 0, clone(arr[i])); rerender(); notify(); }),
      tool("×", "Remove", () => { arr.splice(i, 1); rerender(); notify(); }, "danger"),
    ];
  }

  function renderObjectBody(obj, path, { level }) {
    const keys = orderedKeys(obj);
    const scalars = keys.filter((k) => isScalar(obj[k]));
    const nested = keys.filter((k) => !isScalar(obj[k]));
    return [
      scalars.length ? h("div", { class: "rows" }, scalars.map((k) => renderScalarRow(obj, k, path))) : null,
      nested.map((k) => renderNested(obj[k], [...path, k], k, level + 1)),
      renderAddField(obj, path),
    ];
  }

  function renderNested(value, path, key, level) {
    if (Array.isArray(value)) {
      if (key === "params" && isPairList(value)) return renderParams(value, path);
      if (isScalarList(key, value)) return renderTokens(value, path, key);
      return renderCardList(value, path, key, level);
    }
    const tools = path.length > 1 ? [tool("×", `Remove ${key}`, () => { setAt(doc, path, undefined); rerender(); notify(); }, "danger")] : [];
    return card(key, previewOf(value), path, key, { tools, level }, renderObjectBody(value, path, { level }));
  }

  function renderCardList(arr, path, key, level) {
    const items = arr.map((item, i) => {
      const itemPath = [...path, i];
      if (isScalar(item)) return renderTokens(arr, path, key);
      return card(titleOf(key, item, i), previewOf(item), itemPath, key, { tools: listItemTools(arr, i), inList: true, level },
        renderObjectBody(item, itemPath, { level }));
    });
    return h("div", { class: "list", dataset: { path: pathAttr(path) } },
      h("span", { class: "list-label" }, key, " ", h("span", { class: "kind" }, `${arr.length} item${arr.length === 1 ? "" : "s"}`)),
      h("div", { class: "cards" }, items),
      renderAddToList(arr, key));
  }

  function renderAddToList(arr, key) {
    if (key === "attributes") {
      const sel = h("select", { "aria-label": "Attribute template" }, ATTRIBUTE_TEMPLATES.map(([v, label]) => h("option", { value: v }, label)));
      return h("div", { class: "add-bar" }, sel,
        h("button", { type: "button", class: "small", on: { click: () => { arr.push(clone(ATTRIBUTE_TEMPLATES.find(([v]) => v === sel.value)[2])); rerender(); notify(); } } }, "Add attribute"));
    }
    return h("div", { class: "add-bar" },
      h("button", { type: "button", class: "small", on: { click: () => { arr.push(clone(LIST_TEMPLATES[key] ?? {})); rerender(); notify(); } } }, `Add ${key} item`));
  }

  function renderAddField(obj, path) {
    const listId = nextId();
    const context = path.length === 0 ? "" : listKeyOf(path);
    const suggestions = (FIELD_SUGGESTIONS[context] ?? []).filter((k) => !(k in obj));
    const name = h("input", { type: "text", list: listId, placeholder: "field name", "aria-label": "New field name", autocomplete: "off" });
    const kind = h("select", { "aria-label": "New field type" },
      ["string", "number", "boolean", "array", "object"].map((k) => h("option", { value: k }, k === "boolean" ? "flag" : k === "array" ? "list" : k)));
    const form = h("form", { class: "add-bar", on: { submit: (e) => {
      e.preventDefault();
      const key = name.value.trim();
      if (!key || key in obj) return;
      setAt(doc, [...path, key], emptyOfKind(kind.value));
      rerender();
      notify();
    } } },
      name, h("datalist", { id: listId }, suggestions.map((s) => h("option", { value: s }))), kind,
      h("button", { type: "submit", class: "small" }, "Add field"));
    return form;
  }

  // ── lifecycle ────────────────────────────────────────────────────────
  function captureOpenState() {
    openState = new Map();
    for (const d of body.querySelectorAll("details[data-path]")) openState.set(d.dataset.path, d.open);
  }

  function rerender() {
    captureOpenState();
    render(doc);
    applyMarks();
  }

  function render(nextDoc) {
    doc = nextDoc;
    if (!doc || typeof doc !== "object") {
      replace(body, h("p", { class: "empty" }, "No document to edit. Analyze an input first."));
      summary.hidden = true;
      return;
    }
    replace(body, h("div", { dataset: { path: "" } }, renderObjectBody(doc, [], { level: 0 })));
  }

  function findElement(path) {
    for (let i = path.length; i >= 0; i--) {
      const el = body.querySelector(`[data-path="${CSS.escape(pathToString(path.slice(0, i)))}"]`);
      if (el) return el;
    }
    return null;
  }

  function reveal(el) {
    for (let p = el; p; p = p.parentElement) if (p.tagName === "DETAILS") p.open = true;
    el.scrollIntoView({ block: "center", behavior: "smooth" });
  }

  // ── findings on fields ───────────────────────────────────────────────
  // Where a disclosure for `el` goes: inside a row (under the input), at
  // the top of a card body / list / params container, or after a token's
  // list label.
  function disclosureHost(el) {
    if (el.classList.contains("token")) el = el.closest(".list");
    if (el.tagName === "DETAILS") return { host: el.querySelector(":scope > .card-body"), first: true };
    if (el.classList.contains("list") || el.classList.contains("params")) return { host: el, afterLabel: true };
    if (el.dataset.path === "") return { host: el, first: true };
    return { host: el, first: false };
  }

  function insertDisclosure(el, node) {
    const { host, first, afterLabel } = disclosureHost(el);
    if (!host) return;
    if (afterLabel) {
      const label = host.querySelector(":scope > .list-label, :scope > .params-label");
      const anchor = host.querySelector(":scope > .field-findings");
      if (anchor) anchor.append(node);
      else {
        const wrap = h("div", { class: "field-findings" }, node);
        if (label) label.after(wrap); else host.prepend(wrap);
      }
      return;
    }
    let wrap = host.querySelector(":scope > .field-findings");
    if (!wrap) {
      wrap = h("div", { class: "field-findings" });
      if (first) host.prepend(wrap); else host.append(wrap);
    }
    wrap.append(node);
  }

  // The disclosure: one-line summary that expands to the full finding.
  // `actions` is the reserved slot for a future per-finding "Fix" button.
  function disclosure({ key, severity, id, message, spec_ref, location, missing, fieldPath, control, marker }) {
    const bodyId = nextId();
    const open = expandedFindings.has(key);
    const details = h("div", { class: "fdisc-body", id: bodyId, hidden: !open },
      h("p", { class: "fdisc-msg" }, message ?? ""),
      h("p", { class: "fdisc-meta" },
        spec_ref ? h("span", {}, spec_ref) : null,
        location ? h("span", { class: "mono" }, location) : null,
        fieldPath && missing ? h("span", { class: "mono" }, `expected at ${fieldPath}`) : null,
        !fieldPath && missing ? h("span", {}, "the engine reported no field for this finding") : null),
      h("div", { class: "fdisc-foot" },
        control ? h("label", { class: "fdisc-sev" }, "Severity ", control) : null,
        h("span", { class: "fdisc-actions", dataset: { checkId: id ?? "" }, "aria-hidden": "true" })));
    const toggle = h("button", {
      type: "button", class: "fdisc-summary", "aria-expanded": String(open), "aria-controls": bodyId,
      on: { click: () => setDisclosure(toggle, details, key, toggle.getAttribute("aria-expanded") !== "true") },
    },
      h("span", { class: `fdisc-glyph sev-${severity}`, "aria-hidden": "true" }, severity === "error" ? "✗" : "!"),
      h("span", { class: "visually-hidden" }, severity === "error" ? "error: " : "warning: "),
      missing || (marker && marker.startsWith("line ")) ? h("span", { class: `badge ${missing ? "missing" : "tier"}` }, marker ?? "missing") : null,
      h("span", { class: "fdisc-id" }, id ?? "serializer"),
      h("span", { class: "fdisc-short" }, shortMessage(message)));
    return h("div", { class: `fdisc sev-${severity}${missing ? " is-missing" : ""}`, dataset: { key, checkId: id ?? "" } }, toggle, details);
  }

  function setDisclosure(toggle, details, key, open) {
    toggle.setAttribute("aria-expanded", String(open));
    details.hidden = !open;
    if (open) expandedFindings.add(key); else expandedFindings.delete(key);
    updateExpandAll(toggle.closest("details.card"));
  }

  function setAllIn(card, open) {
    for (const d of card.querySelectorAll(".fdisc")) {
      setDisclosure(d.querySelector(".fdisc-summary"), d.querySelector(".fdisc-body"), d.dataset.key, open);
    }
  }

  // Refresh the "Expand findings" button of `card` and every enclosing
  // card (a media card's button reflects disclosures in its attribute cards).
  function updateExpandAll(card) {
    for (let c = card; c; c = c.parentElement?.closest("details.card")) {
      const btn = c.querySelector(":scope > summary .expand-findings");
      if (!btn) continue;
      const all = [...c.querySelectorAll(".fdisc-summary")];
      const anyClosed = all.some((t) => t.getAttribute("aria-expanded") !== "true");
      btn.setAttribute("aria-expanded", String(!anyClosed && all.length > 0));
      setText(btn, anyClosed ? "Expand findings" : "Collapse findings");
    }
  }

  function clearMarks() {
    for (const el of body.querySelectorAll(".finding-marks, .field-findings, .expand-findings")) el.remove();
    for (const el of body.querySelectorAll(".has-finding, .has-error")) el.classList.remove("has-finding", "sev-error", "sev-warn", "has-error");
  }

  // Applies lastRows + lastSerializeError to the current DOM without
  // re-rendering fields, so an input being edited keeps focus.
  function applyMarks() {
    clearMarks();
    if (!doc) return;
    const { attachments, counts } = attachFindings(doc, lastRows, lastMarkOptions);
    for (const [pathStr, c] of counts) {
      const card = body.querySelector(`details.card[data-path="${CSS.escape(pathStr)}"]`);
      if (!card) continue;
      const tools = card.querySelector(":scope > summary .card-tools");
      tools.before(h("span", { class: `finding-marks badge ${c.worst === "error" ? "error" : "warn"}`, title: countsLabel(c) }, countsLabel(c)));
      tools.prepend(h("button", {
        type: "button", class: "ghost small expand-findings", "aria-expanded": "false",
        on: { click: (e) => { e.preventDefault(); e.stopPropagation(); const btn = e.currentTarget; setAllIn(card, btn.getAttribute("aria-expanded") !== "true"); } },
      }, "Expand findings"));
    }
    for (const [pathStr, list] of attachments) {
      const el = body.querySelector(`[data-path="${CSS.escape(pathStr)}"]`);
      if (!el) continue;
      const worst = list.some((a) => a.finding.severity === "error") ? "error" : "warn";
      el.classList.add("has-finding", `sev-${worst}`);
      for (const a of list) {
        insertDisclosure(el, disclosure({
          key: `${pathStr}|${a.key}`, severity: a.finding.severity, id: a.finding.id ?? a.finding.code,
          message: a.finding.message, spec_ref: a.finding.spec_ref, location: locationLabel(a.finding),
          missing: a.missing, fieldPath: a.fieldPath, marker: a.unlocated ? "no location" : a.byLine ? `line ${a.finding.line}` : "missing",
          control: severityControl(policy, a.finding.id),
        }));
      }
    }
    if (lastSerializeError) applySerializeError(lastSerializeError);
    for (const card of body.querySelectorAll("details.card")) updateExpandAll(card);
    renderSummary(attachments, counts);
  }

  function applySerializeError(err) {
    if (!err.field_path) return;
    const { path, exact } = resolvePath(doc, err.field_path);
    const el = findElement(path);
    if (!el) return;
    el.classList.add("has-finding", "sev-error", "has-error");
    insertDisclosure(el, disclosure({
      key: `serialize|${err.field_path}`, severity: "error", id: null, message: err.message, spec_ref: err.spec_ref,
      missing: !exact, fieldPath: err.field_path, marker: "cannot serialize", control: null,
    }));
    const card = el.closest("details.card");
    if (card && !card.querySelector(":scope > summary .finding-marks")) {
      card.querySelector(":scope > summary .card-tools").before(h("span", { class: "finding-marks badge error" }, "cannot serialize"));
    }
  }

  // ── findings summary block (first thing in the section) ─────────────
  function summaryOpen() {
    try { return localStorage.getItem(SUMMARY_KEY) !== "collapsed"; } catch { return true; }
  }
  function setSummaryOpen(open) {
    summaryToggle.setAttribute("aria-expanded", String(open));
    summaryList.hidden = !open;
    setText(summaryToggle, open ? "Collapse" : "Expand");
    try { localStorage.setItem(SUMMARY_KEY, open ? "expanded" : "collapsed"); } catch { /* no persistence */ }
  }
  summaryToggle.addEventListener("click", () => setSummaryOpen(summaryToggle.getAttribute("aria-expanded") !== "true"));

  function renderSummary(attachments, counts) {
    if (!doc) {
      summary.hidden = true;
      return;
    }
    summary.hidden = false;
    const c = counts.get("") ?? { errors: 0, warnings: 0 };
    replace(summaryCounts,
      c.errors || c.warnings
        ? [c.errors ? h("span", { class: "n-err" }, `${c.errors} error${c.errors === 1 ? "" : "s"}`) : null,
           c.errors && c.warnings ? " · " : null,
           c.warnings ? h("span", { class: "n-warn" }, `${c.warnings} warning${c.warnings === 1 ? "" : "s"}`) : null]
        : "No findings in the document");
    const entries = summaryEntries(attachments);
    replace(summaryList, entries.map((a) => {
      const f = a.finding;
      const target = a.unlocated ? "" : a.byLine ? a.pathStr : a.fieldPath;
      const locText = a.unlocated ? "no location" : a.byLine ? `${a.pathStr} (line ${f.line})` : a.missing ? `${a.fieldPath} (missing)` : a.fieldPath;
      return h("li", { class: `sev-${f.severity}` },
        h("span", { class: `fdisc-glyph sev-${f.severity}`, "aria-hidden": "true" }, f.severity === "error" ? "✗" : "!"),
        h("span", {}, h("span", { class: "visually-hidden" }, f.severity === "error" ? "error: " : "warning: "),
          h("span", { class: "es-id" }, f.id ?? f.code ?? ""), " ", h("span", { class: "es-msg" }, shortMessage(f.message))),
        h("button", { type: "button", class: "es-loc", title: "Go to this field", on: { click: () => highlightPath(target) } }, locText));
    }));
    setSummaryOpen(summaryOpen());
  }

  // rows: de-duplicated finding rows from the report; options: { lineMap,
  // skipIds } as field_findings.attachFindings takes them.
  function markFindings(rows, options = {}) {
    lastRows = rows ?? [];
    lastMarkOptions = options;
    applyMarks();
  }

  // err: serialize_error table, or null to clear.
  function showSerializeError(err) {
    lastSerializeError = err ?? null;
    if (!err) {
      banner.hidden = true;
      setText(banner, "");
    } else {
      banner.hidden = false;
      setText(banner, `Cannot serialize: ${err.message}${err.field_path ? ` (at ${err.field_path})` : ""}`);
    }
    applyMarks();
    if (err?.field_path) {
      const el = findElement(resolvePath(doc, err.field_path).path);
      if (el) reveal(el);
    }
  }

  // fieldPath: grammar or serializer field_path string. Opens the enclosing
  // cards, expands the field's disclosures, scrolls and flashes it.
  function highlightPath(fieldPath) {
    if (!doc) return;
    const { path } = fieldPath ? resolvePath(doc, fieldPath) : { path: [] };
    const el = findElement(path);
    if (!el) return;
    reveal(el);
    const { host } = disclosureHost(el);
    for (const d of host?.querySelectorAll(":scope > .field-findings > .fdisc") ?? []) {
      setDisclosure(d.querySelector(".fdisc-summary"), d.querySelector(".fdisc-body"), d.dataset.key, true);
    }
    el.classList.add("is-target");
    setTimeout(() => el.classList.remove("is-target"), 1800);
    el.querySelector("input, select")?.focus({ preventScroll: true });
  }

  render(null);
  return { render, showSerializeError, highlightPath, markFindings, getDoc: () => doc };
}
