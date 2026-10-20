// url_source.js: load SDP from a URL as the server sends it. No DOM.
//
// Text copied from a log or a device web page often has the wrong line
// endings. The bytes fetched from the URL have the endings the server
// sends, so the line-ending checks see the real file. The fetch function
// is passed in, so the tests run under node without a network.

// The limits are decision parse_sdp-2w4. A local-network request waits
// longer, because the time includes the browser's permission prompt.
export const TIMEOUT_MS = 10000;
export const LOCAL_TIMEOUT_MS = 60000;
export const MAX_BYTES = 1000000;

// A failure to load. `kind` is one of: invalid-url, local-network,
// network, timeout, http-status, too-large.
export class LoadError extends Error {
  constructor(kind, message) {
    super(message);
    this.name = "LoadError";
    this.kind = kind;
  }
}

// Parse the text from the URL box. Only an absolute http: or https: URL
// is accepted. Returns a URL object, or null.
export function parseSdpUrl(input) {
  const s = String(input ?? "").trim();
  let url;
  try {
    url = new URL(s);
  } catch {
    return null;
  }
  return url.protocol === "http:" || url.protocol === "https:" ? url : null;
}

// Browsers treat loopback addresses as secure, so an HTTPS page can fetch
// http://localhost without a mixed-content block.
const LOOPBACK = new Set(["localhost", "127.0.0.1", "[::1]"]);

// True for an HTTP URL from an HTTPS page (mixed content). Chrome and Edge
// 142 and later send such a request to a device on the local network
// after the user allows local network access; the fetch option
// targetAddressSpace: "local" asks for that. Other browsers block the
// request (decision parse_sdp-2hr, which replaces parse_sdp-bc3).
export function isLocalNetworkRequest(url, pageProtocol) {
  return pageProtocol === "https:" && url.protocol === "http:" && !LOOPBACK.has(url.hostname);
}

// The last non-empty path segment, used to name downloads in the same way
// as a dropped file name. An IS-05 ".../transportfile" URL gives
// "transportfile". A URL with no path gives "session".
export function downloadName(url) {
  const segments = url.pathname.split("/").filter((s) => s !== "");
  const last = segments[segments.length - 1];
  if (!last) return "session";
  try {
    return decodeURIComponent(last);
  } catch {
    return last;
  }
}

// Decode the response bytes as UTF-8. CR LF pairs and a byte order mark
// are kept, so the parser reports what the file contains.
export function decodeBytes(bytes) {
  return new TextDecoder("utf-8", { ignoreBOM: true }).decode(bytes);
}

// The URL in single quotes for a POSIX shell. A ' in the URL becomes '\''.
function shellQuote(s) {
  return `'${String(s).replace(/'/g, "'\\''")}'`;
}

function workaround(url) {
  return `To check the file anyway, download the file with the browser and drop it on this page, or run: curl -s ${shellQuote(url)} | parse_sdp validate -`;
}

// The message shown for each kind of LoadError. A browser reports a CORS
// failure as a bare TypeError, the same error as a wrong address, so the
// network message names CORS only as a common reason (decision
// parse_sdp-4zf). `info` has `url` (string),
// `input` (the text from the URL box), and `status` and `statusText` for
// http-status.
export function loadErrorMessage(kind, info = {}) {
  const url = info.url ?? "";
  switch (kind) {
    case "invalid-url":
      return `"${info.input ?? ""}" is not an http or https URL. Enter a full address that starts with http:// or https://.`;
    case "local-network":
      return `The request for ${url} was blocked or failed. This page was loaded over HTTPS, and the address uses HTTP. Chrome and Edge (version 142 and later) send this request to a device on the local network after you allow local network access for this page. Other browsers block it (mixed content). The browser does not report the reason. Check that you use Chrome or Edge, that local network access is allowed for this page (in the site settings, from the icon to the left of the address bar), that the device sends the Access-Control-Allow-Origin header (CORS, Cross-Origin Resource Sharing), and that the device can be reached. ${workaround(url)}`;
    case "network":
      return `The request for ${url} was blocked or failed. The browser does not report the reason. A common reason is that the server does not send the Access-Control-Allow-Origin header (CORS, Cross-Origin Resource Sharing), so the browser does not give the response to this page. Other reasons are a wrong address or a server that cannot be reached. ${workaround(url)}`;
    case "timeout":
      return `The server did not send the complete response for ${url} within ${(info.timeoutMs ?? TIMEOUT_MS) / 1000} seconds, so the page stopped the request.`;
    case "http-status":
      return `The server returned HTTP ${info.status}${info.statusText ? ` ${info.statusText}` : ""} for ${url}.`;
    case "too-large":
      return `The response for ${url} is larger than 1 MB (${MAX_BYTES.toLocaleString("en-US")} bytes), so the page did not load it. An SDP file is typically a few kilobytes. Check that the address is the address of an SDP file.`;
    default:
      return `Could not load ${url}.`;
  }
}

const fail = (kind, info) => new LoadError(kind, loadErrorMessage(kind, info));

// Read the body, and stop when it grows past maxBytes.
async function readCapped(res, maxBytes, info) {
  const declared = Number(res.headers.get("content-length"));
  if (declared > maxBytes) throw fail("too-large", info);
  if (!res.body) return new Uint8Array(await res.arrayBuffer());
  const reader = res.body.getReader();
  const chunks = [];
  let total = 0;
  for (;;) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel();
      throw fail("too-large", info);
    }
    chunks.push(value);
  }
  const out = new Uint8Array(total);
  let at = 0;
  for (const c of chunks) {
    out.set(c, at);
    at += c.byteLength;
  }
  return out;
}

// Fetch an SDP file. Returns { url, name, text }, or throws a LoadError.
// options: pageProtocol (location.protocol), fetch, timeoutMs, maxBytes.
// The default timeout is LOCAL_TIMEOUT_MS for a local-network request.
export async function fetchSdp(input, options = {}) {
  const { pageProtocol = "https:", fetch = globalThis.fetch, maxBytes = MAX_BYTES } = options;
  const url = parseSdpUrl(input);
  if (!url) throw fail("invalid-url", { input });
  const local = isLocalNetworkRequest(url, pageProtocol);
  const timeoutMs = options.timeoutMs ?? (local ? LOCAL_TIMEOUT_MS : TIMEOUT_MS);
  const info = { url: url.href, timeoutMs };

  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  const init = { signal: controller.signal, cache: "no-store" };
  if (local) init.targetAddressSpace = "local";
  try {
    let res;
    try {
      res = await fetch(url.href, init);
    } catch (e) {
      if (controller.signal.aborted) throw fail("timeout", info);
      throw fail(local ? "local-network" : "network", info);
    }
    if (!res.ok) throw fail("http-status", { ...info, status: res.status, statusText: res.statusText });
    let bytes;
    try {
      bytes = await readCapped(res, maxBytes, info);
    } catch (e) {
      if (e instanceof LoadError) throw e;
      throw controller.signal.aborted ? fail("timeout", info) : fail("network", info);
    }
    return { url: url.href, name: downloadName(url), text: decodeBytes(bytes) };
  } finally {
    clearTimeout(timer);
  }
}

// The page address with ?url=<sdpUrl> (decision parse_sdp-q7s). Other query parameters (such as
// mock=1) are kept, and the fragment is dropped. With no sdpUrl, the url
// parameter is removed.
export function shareLink(pageHref, sdpUrl) {
  const page = new URL(pageHref);
  if (sdpUrl) page.searchParams.set("url", sdpUrl);
  else page.searchParams.delete("url");
  page.hash = "";
  return page.href;
}

// The SDP URL named by ?url= in a query string, or null.
export function urlFromQuery(search) {
  const value = new URLSearchParams(search).get("url");
  return value && value.trim() !== "" ? value.trim() : null;
}
