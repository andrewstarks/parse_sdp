// web/src/engine.js — JS side of the parse_sdp WebAssembly engine.
// See web/CONTRACT.md. The only thing the UI talks to.

import createParseSdpModule from "./parse_sdp.js";

// wasm/build.sh sets CACHE_KEY to "?v=<version>" in web/dist, so that a
// browser fetches a new parse_sdp.wasm after each release instead of a
// cached copy. GitHub Pages lets a browser cache a file for 10 minutes.
const CACHE_KEY = "";

// options.locateFile(path, prefix) lets a host page relocate parse_sdp.wasm.
export async function createEngine(options = {}) {
  const moduleOptions = {};
  if (options.locateFile) moduleOptions.locateFile = options.locateFile;
  // Only a browser fetches the file by URL. Under node, prefix is a
  // directory path, and a query string would break the file read.
  else if (CACHE_KEY && typeof window !== "undefined") moduleOptions.locateFile = (path, prefix) => prefix + path + CACHE_KEY;
  const mod = await createParseSdpModule(moduleOptions);
  const sdpRequest = mod.cwrap("sdp_request", "string", ["string"]);

  const request = async (obj) => JSON.parse(sdpRequest(JSON.stringify(obj)));
  const version = await request({ op: "version" });
  return { request, version };
}
