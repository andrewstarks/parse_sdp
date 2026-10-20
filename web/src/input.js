// input.js: paste area, drop zone, file picker, URL loader and example
// buttons. Hands raw text (plus a file name for downloads) to the app; it
// never interprets the content itself.

import { h, replace, setText } from "./dom.js";
import { decodeBytes, fetchSdp, shareLink } from "./url_source.js";

// onSubmit(text, fileName); fetchText(path) → Promise<string> for examples.
export function initInput(root, { onSubmit, fetchText }) {
  const textarea = root.querySelector("#input-text");
  const dropZone = root.querySelector("#drop-zone");
  const fileInput = root.querySelector("#file-input");
  const meta = root.querySelector("#input-meta");
  const exampleSelect = root.querySelector("#example-select");
  const error = root.querySelector("#input-error");
  const urlForm = root.querySelector("#url-form");
  const urlInput = root.querySelector("#url-input");
  const copyLink = root.querySelector("#copy-link");
  const urlStatus = root.querySelector("#url-status");
  const urlError = root.querySelector("#url-error");
  let fileName = "session";
  // A textarea normalises CR LF to LF, which would turn every CRLF file
  // into a wall of bare-LF warnings. Keep the text as loaded (or pasted)
  // and submit that while the textarea still shows it unchanged.
  let raw = null;
  const lfOnly = (t) => t.replace(/\r\n?/g, "\n");

  function currentText() {
    return raw !== null && textarea.value === lfOnly(raw) ? raw : textarea.value;
  }

  function submit() {
    onSubmit(currentText(), fileName);
  }

  // The page address has ?url= only while the input is the text fetched
  // from that URL, so a copied link reproduces the result. Pasted text is
  // never put in the address (decision parse_sdp-q7s). A new input also
  // removes an earlier URL error.
  function setSourceUrl(url) {
    history.replaceState(history.state, "", shareLink(location.href, url));
    copyLink.hidden = !url;
    showBanner(urlError, null);
  }

  function loadText(text, name, sourceUrl = null) {
    setSourceUrl(sourceUrl);
    fileName = name;
    raw = text;
    textarea.value = text;
    setText(meta, name === "session" ? "" : name);
    submit();
  }

  // file.text() would drop a byte order mark; decodeBytes keeps it, as
  // the URL loader does.
  async function loadFile(file) {
    if (!file) return;
    loadText(decodeBytes(await file.arrayBuffer()), file.name);
  }

  async function loadUrl(input) {
    urlInput.value = input;
    showError(null);
    showBanner(urlError, null);
    setText(urlStatus, "Loading…");
    try {
      const r = await fetchSdp(input, { pageProtocol: location.protocol });
      urlInput.value = r.url;
      setText(urlStatus, "");
      loadText(r.text, r.name, r.url);
    } catch (e) {
      setText(urlStatus, "");
      // The URL error is shown under the URL box, next to the address
      // that failed, and not in the input error banner under the text box.
      showBanner(urlError, e.message);
    }
  }

  root.querySelector("#analyze").addEventListener("click", submit);
  textarea.addEventListener("keydown", (e) => {
    if ((e.ctrlKey || e.metaKey) && e.key === "Enter") {
      e.preventDefault();
      submit();
    }
  });
  textarea.addEventListener("input", () => {
    if (raw !== null && textarea.value !== lfOnly(raw)) {
      raw = null;
      setSourceUrl(null);
    }
  });
  textarea.addEventListener("paste", (e) => {
    const clip = e.clipboardData?.getData("text/plain") ?? "";
    // Let the paste land, then analyze what arrived (with its CRs when the
    // paste replaced the whole content).
    setTimeout(() => {
      raw = clip && textarea.value === lfOnly(clip) ? clip : null;
      setSourceUrl(null);
      fileName = "session";
      setText(meta, "");
      submit();
    }, 0);
  });
  fileInput.addEventListener("change", () => {
    loadFile(fileInput.files[0]);
    fileInput.value = "";
  });

  let dragDepth = 0;
  dropZone.addEventListener("dragenter", (e) => {
    e.preventDefault();
    dragDepth++;
    dropZone.classList.add("is-dragging");
  });
  dropZone.addEventListener("dragover", (e) => e.preventDefault());
  dropZone.addEventListener("dragleave", () => {
    if (--dragDepth <= 0) {
      dragDepth = 0;
      dropZone.classList.remove("is-dragging");
    }
  });
  dropZone.addEventListener("drop", (e) => {
    e.preventDefault();
    dragDepth = 0;
    dropZone.classList.remove("is-dragging");
    const file = e.dataTransfer?.files?.[0];
    if (file) loadFile(file);
    else {
      const text = e.dataTransfer?.getData("text/plain");
      if (text) loadText(text, "session");
    }
  });

  urlForm.addEventListener("submit", (e) => {
    e.preventDefault();
    loadUrl(urlInput.value);
  });
  copyLink.addEventListener("click", async () => {
    try {
      await navigator.clipboard.writeText(location.href);
      setText(urlStatus, "Link copied.");
    } catch {
      setText(urlStatus, "Clipboard unavailable. Copy the address from the address bar.");
    }
    setTimeout(() => setText(urlStatus, ""), 2500);
  });

  exampleSelect.addEventListener("change", async () => {
    const path = exampleSelect.value;
    if (!path) return;
    showError(null);
    try {
      loadText(await fetchText(path), path.split("/").pop());
    } catch (e) {
      showError(`Could not load example: ${e.message}`);
    }
  });

  // groups: [{ label, items: [{ label, path }] }] from examples.js.
  function setExamples(groups) {
    replace(exampleSelect, h("option", { value: "" }, "Load an example…"),
      groups.map((g) => h("optgroup", { label: g.label }, g.items.map((it) => h("option", { value: it.path }, it.label)))));
  }

  function showBanner(el, message) {
    setText(el, message ?? "");
    el.hidden = !message;
  }

  function showError(message) {
    showBanner(error, message);
  }

  return { showError, setExamples, loadUrl, getText: () => textarea.value, getFileName: () => fileName };
}
