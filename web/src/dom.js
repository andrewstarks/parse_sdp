// dom.js — tiny element builder so modules never touch innerHTML.
// h(tag, attrs, ...children): attrs may hold `class`, `dataset`, `on`
// (event → handler), boolean/string attributes, and the `value` / `checked`
// properties; children are strings (text nodes), nodes, arrays or null.

const PROPS = new Set(["value", "checked", "disabled", "selected", "indeterminate", "open"]);

export function h(tag, attrs = {}, ...children) {
  const el = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs ?? {})) {
    if (v === undefined || v === null || v === false) continue;
    if (k === "class") el.className = v;
    else if (k === "dataset") Object.assign(el.dataset, v);
    else if (k === "on") for (const [ev, fn] of Object.entries(v)) el.addEventListener(ev, fn);
    else if (PROPS.has(k)) el[k] = v;
    else el.setAttribute(k, v === true ? "" : v);
  }
  append(el, children);
  return el;
}

export function append(el, children) {
  for (const c of children) {
    if (c === null || c === undefined || c === false) continue;
    if (Array.isArray(c)) append(el, c);
    else el.append(typeof c === "string" ? document.createTextNode(c) : c);
  }
  return el;
}

export function clear(el) {
  while (el.firstChild) el.removeChild(el.firstChild);
  return el;
}

export function replace(el, ...children) {
  return append(clear(el), children);
}

export function setText(el, text) {
  el.textContent = text ?? "";
  return el;
}

// Debounce helper for change-driven validation.
export function debounce(fn, ms) {
  let t = null;
  return (...args) => {
    clearTimeout(t);
    t = setTimeout(() => fn(...args), ms);
  };
}
