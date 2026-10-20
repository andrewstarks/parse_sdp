import { test } from "node:test";
import assert from "node:assert/strict";
import {
  parseSdpUrl, isLocalNetworkRequest, downloadName, decodeBytes, loadErrorMessage,
  fetchSdp, shareLink, urlFromQuery, LoadError, MAX_BYTES, LOCAL_TIMEOUT_MS,
} from "../src/url_source.js";

const CRLF_SDP = "v=0\r\no=- 1 1 IN IP4 192.0.2.1\r\ns=x\r\nt=0 0\r\n";
const enc = (s) => new TextEncoder().encode(s);

// A fetch stand-in that answers every request with the given Response.
const answer = (res) => async () => res;

async function rejectsWith(promise, kind) {
  await assert.rejects(promise, (e) => e instanceof LoadError && e.kind === kind);
}

test("parseSdpUrl accepts only absolute http and https URLs", () => {
  assert.equal(parseSdpUrl(" https://dev.example/x.sdp ").href, "https://dev.example/x.sdp");
  assert.equal(parseSdpUrl("http://192.0.2.10/sdp").protocol, "http:");
  assert.equal(parseSdpUrl("ftp://dev.example/x.sdp"), null);
  assert.equal(parseSdpUrl("file:///tmp/x.sdp"), null);
  assert.equal(parseSdpUrl("dev.example/x.sdp"), null);
  assert.equal(parseSdpUrl(""), null);
  assert.equal(parseSdpUrl(undefined), null);
});

test("isLocalNetworkRequest: an HTTP URL from an HTTPS page, except loopback", () => {
  const u = (s) => new URL(s);
  assert.equal(isLocalNetworkRequest(u("http://192.0.2.10/x.sdp"), "https:"), true);
  assert.equal(isLocalNetworkRequest(u("http://cam1.local/x.sdp"), "https:"), true);
  assert.equal(isLocalNetworkRequest(u("https://192.0.2.10/x.sdp"), "https:"), false);
  assert.equal(isLocalNetworkRequest(u("http://192.0.2.10/x.sdp"), "http:"), false);
  assert.equal(isLocalNetworkRequest(u("http://localhost:8080/x.sdp"), "https:"), false);
  assert.equal(isLocalNetworkRequest(u("http://127.0.0.1/x.sdp"), "https:"), false);
  assert.equal(isLocalNetworkRequest(u("http://[::1]/x.sdp"), "https:"), false);
});

test("downloadName is the last non-empty path segment", () => {
  const n = (s) => downloadName(new URL(s));
  assert.equal(n("https://d.example/a/cam1.sdp?x=1#y"), "cam1.sdp");
  assert.equal(n("http://d.example/x-nmos/connection/v1.1/single/senders/abc/transportfile"), "transportfile");
  assert.equal(n("http://d.example/sdp/"), "sdp");
  assert.equal(n("http://d.example/my%20cam.sdp"), "my cam.sdp");
  assert.equal(n("http://d.example/bad%E0.sdp"), "bad%E0.sdp");
  assert.equal(n("http://d.example/"), "session");
});

test("decodeBytes keeps CR LF and a byte order mark", () => {
  assert.equal(decodeBytes(enc(CRLF_SDP)), CRLF_SDP);
  const withBom = new Uint8Array([0xef, 0xbb, 0xbf, ...enc("v=0\r\n")]);
  assert.equal(decodeBytes(withBom), "\uFEFFv=0\r\n");
});

test("loadErrorMessage: a blocked fetch names CORS as a possible reason, not as certain", () => {
  const m = loadErrorMessage("network", { url: "https://d.example/x.sdp" });
  assert.match(m, /was blocked or failed/);
  assert.match(m, /Access-Control-Allow-Origin/);
  assert.match(m, /A common reason/);
  assert.match(m, /drop it on this page/);
  assert.match(m, /curl -s 'https:\/\/d\.example\/x\.sdp' \| parse_sdp validate -/);
});

test("loadErrorMessage: a failed local-network request names the reasons and the workaround", () => {
  const m = loadErrorMessage("local-network", { url: "http://192.0.2.10/x.sdp" });
  assert.match(m, /was blocked or failed/);
  assert.match(m, /Chrome and Edge \(version 142 and later\)/);
  assert.match(m, /local network access is allowed/);
  assert.match(m, /mixed content/);
  assert.match(m, /Access-Control-Allow-Origin/);
  assert.match(m, /curl -s 'http:\/\/192\.0\.2\.10\/x\.sdp' \| parse_sdp validate -/);
});

test("loadErrorMessage: the curl command quotes a ' in the URL for the shell", () => {
  const m = loadErrorMessage("network", { url: "https://d.example/it's.sdp" });
  assert.match(m, /curl -s 'https:\/\/d\.example\/it'\\''s\.sdp' \|/);
});

test("loadErrorMessage: other kinds name the URL and the value seen", () => {
  assert.match(loadErrorMessage("invalid-url", { input: "dev/x" }), /"dev\/x" is not an http or https URL/);
  assert.match(loadErrorMessage("timeout", { url: "https://d/x" }), /within 10 seconds/);
  assert.match(loadErrorMessage("timeout", { url: "http://d/x", timeoutMs: 60000 }), /within 60 seconds/);
  assert.match(loadErrorMessage("http-status", { url: "https://d/x", status: 404, statusText: "Not Found" }), /HTTP 404 Not Found for https:\/\/d\/x/);
  assert.match(loadErrorMessage("too-large", { url: "https://d/x" }), /larger than 1 MB \(1,000,000 bytes\)/);
});

test("fetchSdp returns the bytes as served, with CR LF kept", async () => {
  const seen = [];
  const fetch = async (url, init) => {
    seen.push({ url, init });
    return new Response(enc(CRLF_SDP));
  };
  const r = await fetchSdp("https://d.example/cams/cam1.sdp", { fetch });
  assert.deepEqual(r, { url: "https://d.example/cams/cam1.sdp", name: "cam1.sdp", text: CRLF_SDP });
  assert.ok(seen[0].init.signal instanceof AbortSignal);
});

test("fetchSdp refuses an invalid URL without fetching", async () => {
  let called = false;
  const fetch = async () => { called = true; return new Response(""); };
  await rejectsWith(fetchSdp("not a url", { fetch }), "invalid-url");
  assert.equal(called, false);
});

test("fetchSdp sends an HTTP URL from an HTTPS page as a local-network request", async () => {
  const seen = [];
  const fetch = async (url, init) => {
    seen.push(init);
    return new Response(enc(CRLF_SDP));
  };
  const r = await fetchSdp("http://172.16.11.20:3212/x-nmos/connection/v1.1/single/senders/s1/transportfile/", { fetch, pageProtocol: "https:" });
  assert.equal(r.text, CRLF_SDP);
  assert.equal(r.name, "transportfile");
  assert.equal(seen[0].targetAddressSpace, "local");
  await fetchSdp("https://d.example/x.sdp", { fetch, pageProtocol: "https:" });
  await fetchSdp("http://d.example/x.sdp", { fetch, pageProtocol: "http:" });
  assert.equal("targetAddressSpace" in seen[1], false);
  assert.equal("targetAddressSpace" in seen[2], false);
});

test("fetchSdp maps a failed local-network request to the local-network kind", async () => {
  const fetch = async () => { throw new TypeError("Failed to fetch"); };
  await rejectsWith(fetchSdp("http://192.0.2.10/x.sdp", { fetch, pageProtocol: "https:" }), "local-network");
});

test("fetchSdp waits longer for a local-network request", async () => {
  let timeout;
  const realSetTimeout = globalThis.setTimeout;
  globalThis.setTimeout = (fn, ms) => { timeout ??= ms; return realSetTimeout(fn, ms); };
  try {
    await fetchSdp("http://192.0.2.10/x.sdp", { fetch: answer(new Response("v=0\r\n")), pageProtocol: "https:" });
  } finally {
    globalThis.setTimeout = realSetTimeout;
  }
  assert.equal(timeout, LOCAL_TIMEOUT_MS);
});

test("fetchSdp maps a TypeError from fetch to the network kind", async () => {
  const fetch = async () => { throw new TypeError("Failed to fetch"); };
  await rejectsWith(fetchSdp("https://d.example/x.sdp", { fetch }), "network");
});

test("fetchSdp maps an HTTP error status", async () => {
  const fetch = answer(new Response("no", { status: 404, statusText: "Not Found" }));
  await assert.rejects(fetchSdp("https://d.example/x.sdp", { fetch }), (e) => e.kind === "http-status" && /HTTP 404 Not Found/.test(e.message));
});

test("fetchSdp aborts after the timeout", async () => {
  const fetch = (url, { signal }) => new Promise((_, reject) => {
    signal.addEventListener("abort", () => reject(new DOMException("aborted", "AbortError")));
  });
  await rejectsWith(fetchSdp("https://d.example/x.sdp", { fetch, timeoutMs: 20 }), "timeout");
});

test("fetchSdp refuses a body over the size limit", async () => {
  // Declared by Content-Length.
  const declared = answer(new Response("v=0\r\n", { headers: { "content-length": String(MAX_BYTES + 1) } }));
  await rejectsWith(fetchSdp("https://d.example/x.sdp", { fetch: declared }), "too-large");
  // Not declared: the stream is counted while it is read.
  const big = answer(new Response(new Uint8Array(64)));
  await rejectsWith(fetchSdp("https://d.example/x.sdp", { fetch: big, maxBytes: 63 }), "too-large");
  const fits = answer(new Response(new Uint8Array(63)));
  assert.equal((await fetchSdp("https://d.example/x.sdp", { fetch: fits, maxBytes: 63 })).text.length, 63);
});

test("shareLink sets ?url=, keeps other parameters, and drops the fragment", () => {
  const sdp = "http://192.0.2.10:8080/x-nmos/connection/v1.1/single/senders/a b/transportfile?x=1&y=2";
  const link = shareLink("https://andrewstarks.github.io/parse_sdp/?mock=1#report", sdp);
  const back = new URL(link);
  assert.equal(back.searchParams.get("mock"), "1");
  assert.equal(back.hash, "");
  assert.equal(urlFromQuery(back.search), sdp);
  assert.equal(shareLink(link, null), "https://andrewstarks.github.io/parse_sdp/?mock=1");
});

test("urlFromQuery returns null when ?url= is absent or empty", () => {
  assert.equal(urlFromQuery(""), null);
  assert.equal(urlFromQuery("?url="), null);
  assert.equal(urlFromQuery("?mock=1"), null);
});
