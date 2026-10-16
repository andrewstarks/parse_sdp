// line_map.js — which document field each SDP line produced. Pure.
//
// The parser fills the doc in text order: a= lines become attributes[i]
// in order within their block, b= lines bandwidths[i], e=/p= emails[i] /
// phones[i], t= lines time_descriptions[i] with following r= lines as
// repeats[j], m= lines media[i]. Walking the text with the same counters
// gives a path for every line, so a line-anchored finding can be shown on
// the field it concerns. Lines the parser does not keep (unknown types,
// blanks) get null.

import { splitLines } from "./format.js";

export function lineToPath(text) {
  const out = [];
  let media = -1;            // index of the current m= block, -1 = session
  let attrs = 0, bands = 0, emails = 0, phones = 0, times = -1, repeats = 0;
  const block = () => (media < 0 ? "session" : `media[${media}]`);
  for (const line of splitLines(text)) {
    const type = line.length >= 2 && line[1] === "=" ? line[0] : null;
    let path = null;
    switch (type) {
      case "v": path = "version"; break;
      case "o": path = "origin"; break;
      case "s": path = "session.name"; break;
      case "i": path = `${block()}.info`; break;
      case "u": path = "session.uri"; break;
      case "e": path = `session.emails[${emails++}]`; break;
      case "p": path = `session.phones[${phones++}]`; break;
      case "c": path = `${block()}.connection`; break;
      case "b": path = `${block()}.bandwidths[${bands++}]`; break;
      case "t": times++; repeats = 0; path = `session.time_descriptions[${times}]`; break;
      case "r": path = times >= 0 ? `session.time_descriptions[${times}].repeats[${repeats++}]` : null; break;
      case "z": path = "session.time_zones"; break;
      case "a": path = `${block()}.attributes[${attrs++}]`; break;
      case "m": media++; attrs = 0; bands = 0; path = `media[${media}]`; break;
      default: path = null;
    }
    out.push(path);
  }
  return out;
}
