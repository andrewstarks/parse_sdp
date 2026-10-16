// mock_serialize.js — render a document table to SDP text the way the Lua
// serializer does, for the mock engine only. Pure. The real engine never
// uses this; it exists so the output/diff views and serialize_error
// handling can be exercised without WebAssembly.
//
// Mirrors parse_sdp/serialize.lua: RFC 8866 §5 field order, CRLF line
// endings, a missing required field is the only error.

function missing(fieldPath) {
  return {
    message: `cannot serialize: missing required field ${fieldPath}`,
    field_path: fieldPath,
    code: "MISSING_FIELD",
    spec_ref: "RFC 8866 §5",
    line: 0,
    col: 0,
    context: "",
  };
}

class Missing extends Error {
  constructor(fieldPath) {
    super(fieldPath);
    this.error = missing(fieldPath);
  }
}

function need(obj, key, path) {
  if (obj === null || obj === undefined || obj[key] === undefined || obj[key] === null) throw new Missing(path);
  return obj[key];
}

function list(v) {
  return Array.isArray(v) ? v : [];
}

function connection(c, path) {
  return `c=${need(c, "net_type", `${path}.net_type`)} ${need(c, "addr_type", `${path}.addr_type`)} ${need(c, "address", `${path}.address`)}`;
}

function bandwidths(bs, path) {
  return list(bs).map((b, i) => `b=${need(b, "type", `${path}[${i}].type`)}:${need(b, "value", `${path}[${i}].value`)}`);
}

const FLAGS = new Set(["recvonly", "sendonly", "sendrecv", "inactive", "rtcp-mux"]);

function attribute(a, path) {
  if (a === null || typeof a !== "object") throw new Missing(`${path}.name`);
  const name = need(a, "name", `${path}.name`);
  switch (name) {
    case "rtpmap": {
      const pt = need(a, "payload_type", `${path}.payload_type`);
      const enc = need(a, "encoding", `${path}.encoding`);
      const rate = need(a, "clock_rate", `${path}.clock_rate`);
      return `a=rtpmap:${pt} ${enc}/${rate}${a.channels !== undefined ? `/${a.channels}` : ""}`;
    }
    case "fmtp": {
      const pt = need(a, "payload_type", `${path}.payload_type`);
      if (a.raw !== undefined) return `a=fmtp:${pt} ${a.raw}`;
      if (!Array.isArray(a.params)) throw new Missing(`${path}.params`);
      const toks = a.params.map(([k, v]) => (v === true ? String(k) : `${k}=${v}`));
      return `a=fmtp:${pt} ${toks.join(";")}`;
    }
    case "mediaclk": {
      const mode = need(a, "mode", `${path}.mode`);
      if (mode === "direct") return `a=mediaclk:direct=${need(a, "offset", `${path}.offset`)}`;
      return `a=mediaclk:${mode}${a.value !== undefined ? `=${a.value}` : ""}`;
    }
    case "ts-refclk": {
      const source = need(a, "source", `${path}.source`);
      if (source === "ptp") {
        const parts = [need(a, "version", `${path}.version`), need(a, "grandmaster", `${path}.grandmaster`)];
        if (a.domain !== undefined) parts.push(a.domain);
        return `a=ts-refclk:ptp=${parts.join(":")}`;
      }
      return `a=ts-refclk:${source}${a.value !== undefined ? `=${a.value}` : ""}`;
    }
    case "source-filter": {
      const srcs = need(a, "src_addresses", `${path}.src_addresses`);
      return `a=source-filter: ${need(a, "filter_mode", `${path}.filter_mode`)} ${need(a, "net_type", `${path}.net_type`)} ${need(a, "addr_type", `${path}.addr_type`)} ${need(a, "dest_address", `${path}.dest_address`)} ${list(srcs).join(" ")}`;
    }
    case "extmap": {
      const id = need(a, "id", `${path}.id`);
      const uri = need(a, "uri", `${path}.uri`);
      const dir = a.direction !== undefined ? `/${a.direction}` : "";
      const extra = a.attributes !== undefined ? ` ${a.attributes}` : "";
      return `a=extmap:${id}${dir} ${uri}${extra}`;
    }
    case "group":
      return `a=group:${need(a, "semantics", `${path}.semantics`)}${list(a.tags).map((t) => ` ${t}`).join("")}`;
    case "mid":
      return `a=mid:${need(a, "tag", `${path}.tag`)}`;
    case "ptime":
    case "maxptime":
    case "framerate":
    case "quality":
      return `a=${name}:${need(a, "value", `${path}.value`)}`;
    default:
      if (FLAGS.has(name) || a.value === undefined) return `a=${name}`;
      return `a=${name}:${a.value}`;
  }
}

function timeDescriptions(tds) {
  if (!Array.isArray(tds) || tds.length === 0) throw new Missing("session.time_descriptions");
  const out = [];
  tds.forEach((t, i) => {
    const p = `session.time_descriptions[${i}]`;
    out.push(`t=${need(t, "start", `${p}.start`)} ${need(t, "stop", `${p}.stop`)}`);
    list(t.repeats).forEach((r, j) => {
      const rp = `${p}.repeats[${j}]`;
      out.push(`r=${need(r, "interval", `${rp}.interval`)} ${need(r, "duration", `${rp}.duration`)} ${list(need(r, "offsets", `${rp}.offsets`)).join(" ")}`);
    });
  });
  return out;
}

// Returns { text } or { error } (the serialize_error table).
export function mockSerialize(doc) {
  try {
    const lines = [];
    lines.push(`v=${need(doc, "version", "version")}`);
    const o = need(doc, "origin", "origin");
    lines.push(`o=${["username", "sess_id", "sess_version", "net_type", "addr_type", "unicast_address"].map((k) => need(o, k, `origin.${k}`)).join(" ")}`);
    const s = need(doc, "session", "session");
    lines.push(`s=${need(s, "name", "session.name")}`);
    if (s.info !== undefined) lines.push(`i=${s.info}`);
    if (s.uri !== undefined) lines.push(`u=${s.uri}`);
    for (const e of list(s.emails)) lines.push(`e=${e}`);
    for (const p of list(s.phones)) lines.push(`p=${p}`);
    if (s.connection !== undefined) lines.push(connection(s.connection, "session.connection"));
    lines.push(...bandwidths(s.bandwidths, "session.bandwidths"));
    lines.push(...timeDescriptions(s.time_descriptions));
    if (Array.isArray(s.time_zones) && s.time_zones.length > 0) {
      lines.push(`z=${s.time_zones.map((z, i) => `${need(z, "adjustment_time", `session.time_zones[${i}].adjustment_time`)} ${need(z, "offset", `session.time_zones[${i}].offset`)}`).join(" ")}`);
    }
    list(s.attributes).forEach((a, i) => lines.push(attribute(a, `session.attributes[${i}]`)));
    list(doc.media).forEach((m, i) => {
      const p = `media[${i}]`;
      const port = need(m, "port", `${p}.port`);
      const portStr = m.port_count !== undefined ? `${port}/${m.port_count}` : String(port);
      lines.push(`m=${need(m, "media", `${p}.media`)} ${portStr} ${need(m, "proto", `${p}.proto`)} ${list(need(m, "fmts", `${p}.fmts`)).join(" ")}`);
      if (m.info !== undefined) lines.push(`i=${m.info}`);
      if (m.connection !== undefined) lines.push(connection(m.connection, `${p}.connection`));
      lines.push(...bandwidths(m.bandwidths, `${p}.bandwidths`));
      list(m.attributes).forEach((a, j) => lines.push(attribute(a, `${p}.attributes[${j}]`)));
    });
    return { text: lines.map((l) => `${l}\r\n`).join("") };
  } catch (e) {
    if (e instanceof Missing) return { error: e.error };
    throw e;
  }
}
