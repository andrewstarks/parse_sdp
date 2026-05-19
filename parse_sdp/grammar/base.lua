-- parse_sdp.grammar.base — RFC 8866 base SDP grammar.
--
-- This module exports the *rule table* for the base tier and a compiled
-- `lpeg.P(rules)` for current use. The rule table is the unit of
-- composition: Phases 6 and 7 will produce st2110 and ipmx grammars by
-- calling `extend(base.rules, overrides)` and recompiling.
--
-- Grammar discipline:
--   - The document rule wraps the structure in `Ct(...)` so named captures
--     become table fields.
--   - Each captured line rule produces ONE capture value (a string, number,
--     or table). The document scaffold uses `Cg(rule, "key")` to name the
--     capture as a doc field.
--   - Lines not yet captured (filled in by later 2.B/C/D/E sub-commits)
--     still match-and-discard via the loose `value` placeholder, so the
--     document shape (RFC 8866 §5 field order) is enforced from Phase 1.
--   - All field-presence and value-set checks that are *hard-syntactic*
--     (parsing cannot continue past a violation) live as pattern algebra.
--     Semantic checks that need findings + spec_ref attribution come in
--     Phase 3 with the Carg-threaded ctx.
--
-- Document shape follows RFC 8866 §5:
--
--   document        = session_section media_section* EOF
--   session_section = v= o= s= [i=] [u=] e=* p=* [c=] b=*
--                     (t= r=*)+ [z=] [k=] a=*
--   media_section   = m= [i=] [c=] b=* [k=] a=*

local lpeg      = require("lpeg")
local errors    = require("parse_sdp.errors")
local addresses = require("parse_sdp.grammar.addresses")
local P, R, S, V, C, Cc, Cg, Ct, Cmt, Carg =
  lpeg.P, lpeg.R, lpeg.S, lpeg.V, lpeg.C, lpeg.Cc, lpeg.Cg, lpeg.Ct, lpeg.Cmt, lpeg.Carg

-- Primary patterns shared across rules. These are plain LPeg values rather
-- than V-rules because they are not candidates for per-tier override.
local SP = P(" ")

-- Accumulator fold functions for the fmtp kv-list (a_fmtp rule). The `%`
-- operator wants a function f(acc, c1[, c2, ...]) — set_pair folds 2
-- captures (key, value), set_flag folds 1 (bare flag).
local function set_pair(t, k, v) t[k] = v;   return t end
local function set_flag(t, k)    t[k] = true; return t end

-- ── Semantic checks ─────────────────────────────────────────────────────────
-- Cross-section invariants the grammar alone can't express. Each check
-- inspects the captured doc and emits findings via errors.record.

-- Split a connection-address into the address part and an optional
-- suffix (everything after the first '/', not including the slash).
-- Returns (addr, suffix_or_nil). The trailing P(-1) ensures the whole
-- string is consumed; malformed inputs (e.g. with embedded whitespace)
-- fail the match.
local split_c_addr = C((1 - P("/")) ^ 1) * (P("/") * C(P(1) ^ 0)) ^ -1 * P(-1)

-- IPv4 multicast suffix: <ttl>[/<numaddr>] — RFC 8866 §9 IP4-multicast.
local ipv4_mcast_suffix = C(R("09") ^ 1) * (P("/") * C(R("09") ^ 1)) ^ -1 * P(-1)

-- IPv6 multicast suffix: <numaddr> — RFC 8866 §9 IP6-multicast.
local ipv6_numaddr = C(R("09") ^ 1) * P(-1)

-- Validate one connection-address. Records findings to ctx; returns true to
-- continue, false to fail the match (when record() returns false under
-- fail_on_first=true for an error-severity finding).
local function validate_c_address(addr_type, address, ctx, path)
  local addr, suffix = split_c_addr:match(address or "")

  if addr_type == "IP4" then
    if not addr or not addresses.ipv4:match(addr) then
      return errors.record(ctx, "sdp.c.address.invalid-ipv4", { field_path = path })
    end
    if addresses.is_ipv4_multicast(addr) then
      if not suffix then
        return errors.record(ctx, "sdp.c.ipv4-multicast.ttl-required",
                             { field_path = path })
      end
      local ttl_str, num_str = ipv4_mcast_suffix:match(suffix)
      if not ttl_str then
        return errors.record(ctx, "sdp.c.ipv4-multicast.ttl-required",
                             { field_path = path })
      end
      local ttl = tonumber(ttl_str)
      if not ttl or ttl > 255 then
        return errors.record(ctx, "sdp.c.ipv4-multicast.ttl-out-of-range",
                             { field_path = path })
      end
      if num_str then
        local n = tonumber(num_str)
        if not n or n < 1 then
          return errors.record(ctx, "sdp.c.ipv4-multicast.numaddr-invalid",
                               { field_path = path })
        end
      end
    elseif suffix then
      return errors.record(ctx, "sdp.c.ipv4-unicast.suffix-not-allowed",
                           { field_path = path })
    end
  elseif addr_type == "IP6" then
    if not addr or not addresses.ipv6:match(addr) then
      return errors.record(ctx, "sdp.c.address.invalid-ipv6", { field_path = path })
    end
    if addresses.is_ipv6_multicast(addr) then
      if suffix then
        local num_str = ipv6_numaddr:match(suffix)
        if not num_str then
          return errors.record(ctx, "sdp.c.ipv6-multicast.suffix-form-invalid",
                               { field_path = path })
        end
        local n = tonumber(num_str)
        if not n or n < 1 then
          return errors.record(ctx, "sdp.c.ipv6-multicast.numaddr-invalid",
                               { field_path = path })
        end
      end
    elseif suffix then
      return errors.record(ctx, "sdp.c.ipv6-unicast.suffix-not-allowed",
                           { field_path = path })
    end
  end
  return true
end

-- Top-level check: validate every c= line (session-level and per-media).
local function check_connection_addresses(doc, ctx)
  if doc.session.connection then
    local c = doc.session.connection
    if not validate_c_address(c.addr_type, c.address, ctx, "session.connection") then
      return false
    end
  end
  for i, m in ipairs(doc.media) do
    if m.connection then
      local c = m.connection
      local path = string.format("media[%d].connection", i)
      if not validate_c_address(c.addr_type, c.address, ctx, path) then
        return false
      end
    end
  end
  return true
end

-- RFC 8866 §8.2.3: "If the payload type number is dynamically assigned by
-- this session description, an additional 'a=rtpmap:' attribute MUST be
-- included to specify the format name and parameters as defined by the
-- media type registration for the payload format."
-- Dynamic range is PT 96–127 (RFC 3551 §6 / RFC 8866 §6.6).
local function check_dynamic_pt_rtpmap(doc, ctx)
  for i, m in ipairs(doc.media) do
    if type(m.proto) == "string" and m.proto:find("RTP", 1, true) then
      local rtpmap_pts = {}
      for _, attr in ipairs(m.attributes) do
        if attr.name == "rtpmap" then
          rtpmap_pts[attr.payload_type] = true
        end
      end
      for _, fmt in ipairs(m.fmts) do
        local pt_n = tonumber(fmt)
        if pt_n and pt_n >= 96 and pt_n <= 127 and not rtpmap_pts[pt_n] then
          local cont = errors.record(ctx, "sdp.m.rtpmap-required-for-dynamic-pt", {
            field_path = string.format("media[%d].attributes[rtpmap]", i),
          })
          if not cont then return false end
        end
      end
    end
  end
  return true
end

-- RFC 5888 §4: "The identification-tag MUST be unique within an SDP session
-- description." Walks every media block's attribute list, collects mid tags,
-- and records a finding on the first duplicate.
local function check_mid_uniqueness(doc, ctx)
  local seen = {}
  for i, m in ipairs(doc.media) do
    for _, attr in ipairs(m.attributes) do
      if attr.name == "mid" then
        if seen[attr.tag] then
          local cont = errors.record(ctx, "sdp.a.mid.duplicate-tag", {
            field_path = string.format("media[%d].attributes[mid]", i),
          })
          if not cont then return false end
        else
          seen[attr.tag] = true
        end
      end
    end
  end
  return true
end

-- Document-level Cmt callback. Walks the captured doc, runs each semantic
-- check in order, records findings into ctx, and either continues (return
-- pos, doc) or fails the match (return false) per the ctx.fail_on_first
-- policy.
--
-- Signature follows the LPeg manual's Cmt contract:
--   f(subject, position, capture1, ..., captureN) → control values
-- The capture pattern is `Ct(body) * Carg(1)`, so captures are [doc, ctx].
local function validate_doc(_, position, doc, ctx)
  -- Grammar-only consumers (no extra-arg path) get ctx=nil; default to
  -- hard-fail-on-first with findings discarded.
  if ctx == nil then
    ctx = { findings = {}, fail_on_first = true }
  end

  if not check_connection_addresses(doc, ctx) then return false end
  if not check_dynamic_pt_rtpmap(doc, ctx) then return false end
  if not check_mid_uniqueness(doc, ctx) then return false end

  return position, doc
end

local rules = {
  -- Start rule.
  "document",

  -- Top-level captured document. Fields are added one Cg per phase; today
  -- captured: version, origin, session.name, session.connection (Phase 2.A–2.B).
  -- The remaining session and media fields are placeholder pattern matches
  -- until their corresponding sub-commit (2.C–2.E) wraps the leaf in a Cg.
  document = Cmt(
      Ct(
            Cg(V"v_line", "version")
          * Cg(V"o_line", "origin")
          * Cg(Ct(V"session_inner"), "session")
          * Cg(Ct(V"media_section" ^ 0), "media")
        ) * Carg(1),
      validate_doc
    ) * -1,

  -- Session-level inner section: s= through a=*. Phase 2.A captures only
  -- s= → name; 2.B–2.E will add Cg wrappers for i=, u=, e=, p=, c=, b=,
  -- t/r/z, and a=.
  session_inner =
        Cg(V"s_line", "name")
      * (Cg(V"i_line", "info")) ^ -1
      * (Cg(V"u_line", "uri")) ^ -1
      * Cg(Ct(V"e_line" ^ 0), "emails")
      * Cg(Ct(V"p_line" ^ 0), "phones")
      * (Cg(V"c_line", "connection")) ^ -1
      * Cg(Ct(V"b_line" ^ 0), "bandwidths")
      * Cg(Ct(V"time_description" ^ 1), "time_descriptions")
      * (Cg(V"z_line", "time_zones")) ^ -1
      * V"k_line" ^ -1                       -- RFC 8866 §5.12: parsed and discarded
      * Cg(Ct(V"a_line" ^ 0), "attributes"),

  -- One time description per RFC 8866 §5.9–§5.10: a t= line followed by
  -- zero or more r= lines. The Ct collects start + stop (from t=) and
  -- repeats (from r=*) into one descriptor table.
  time_description = Ct(
        V"t_line"
      * Cg(Ct(V"r_line" ^ 0), "repeats")
    ),

  -- Media section (RFC 8866 §5):
  --   m= (required), i=?, c=?, b=*, k=?, a=*
  -- Wrapped in Ct so each media block lands as one table in doc.media[i].
  -- The m= fields (media, port, port_count, proto, fmts) land *flat* at the
  -- media-block top level rather than nested under "m" — to match the 1.0
  -- doc shape and avoid one level of indirection.
  media_section = Ct(
        V"m_line"
      * (Cg(V"i_line", "info")) ^ -1
      * (Cg(V"c_line", "connection")) ^ -1
      * Cg(Ct(V"b_line" ^ 0), "bandwidths")
      * V"k_line" ^ -1
      * Cg(Ct(V"a_line" ^ 0), "attributes")
    ),

  -- ── Captured line rules (Phase 2.A–2.D) ──────────────────────────────
  -- Each produces one or more captures consumed by the surrounding Ct.
  v_line = P("v=") * V"v_value" * V"line_end",
  o_line = P("o=") * V"o_value" * V"line_end",
  s_line = P("s=") * V"s_value" * V"line_end",
  i_line = P("i=") * V"i_value" * V"line_end",
  u_line = P("u=") * V"u_value" * V"line_end",
  e_line = P("e=") * V"e_value" * V"line_end",
  p_line = P("p=") * V"p_value" * V"line_end",
  c_line = P("c=") * V"c_value" * V"line_end",
  b_line = P("b=") * V"b_value" * V"line_end",
  t_line = P("t=") * V"t_value" * V"line_end",
  r_line = P("r=") * V"r_value" * V"line_end",
  z_line = P("z=") * V"z_value" * V"line_end",
  a_line = P("a=") * V"a_value" * V"line_end",
  m_line = P("m=") * V"m_value" * V"line_end",

  -- ── Placeholder line rule ────────────────────────────────────────────
  -- k= is obsolete per RFC 8866 §5.12 and never produces a capture —
  -- the grammar parses the line so the parser advances past it and the
  -- value is discarded.
  k_line = P("k=") * V"value" * V"line_end",

  -- ── Captured value rules ─────────────────────────────────────────────
  -- v= MUST be "0" (RFC 8866 §5.1; only value defined for SDP version).
  v_value = C(P("0")),

  -- s= is a non-empty text string. RFC 8866 §5.3 RECOMMENDS "s= " or "s=-"
  -- when there's no meaningful name; the parser accepts either.
  s_value = C((1 - V"line_end") ^ 1),

  -- o= origin (RFC 8866 §5.2):
  --   o=<username> <sess-id> <sess-version> <nettype> <addrtype> <unicast-address>
  -- Per ABNF, username is non-ws-string; sess-id and sess-version are
  -- decimal integers (kept as strings to preserve NTP-range precision);
  -- nettype is "IN"; addrtype is "IP4" or "IP6"; unicast-address is a
  -- non-ws-string (its internal address-form check belongs to Phase 3).
  o_value = Ct(
        Cg(V"token",    "username")       * SP
      * Cg(V"digits",   "sess_id")        * SP
      * Cg(V"digits",   "sess_version")   * SP
      * Cg(V"nettype",  "net_type")       * SP
      * Cg(V"addrtype", "addr_type")      * SP
      * Cg(V"token",    "unicast_address")
    ),

  -- c= connection (RFC 8866 §5.7):
  --   c=<nettype> <addrtype> <connection-address>
  -- connection-address is kept whole (including any /TTL or /<numaddrs>
  -- suffix per §5.7). Internal address-form validation lives in Phase 3
  -- where the findings context can attribute it to the right spec clause.
  c_value = Ct(
        Cg(V"nettype",  "net_type")  * SP
      * Cg(V"addrtype", "addr_type") * SP
      * Cg(V"token",    "address")
    ),

  -- Text fields. RFC 8866 §5.4, §5.5, §5.6 — each takes a "text" value
  -- (one or more bytes up to the next CRLF). At the base tier we accept
  -- the value as a single string; Phase 3 will add a soft-syntactic
  -- finding for embedded bare CR (forbidden by the §9 ABNF byte-string).
  i_value = C((1 - V"line_end") ^ 1),
  u_value = C((1 - V"line_end") ^ 1),
  e_value = C((1 - V"line_end") ^ 1),
  p_value = C((1 - V"line_end") ^ 1),

  -- b= bandwidth (RFC 8866 §5.8):  b=<bwtype>:<bandwidth>
  -- bwtype is a token (defined value forms include "CT", "AS", "TIAS",
  -- "RS", "RR"; experimental ones use "X-..."); value-set validation
  -- lives in Phase 3. bandwidth is decimal digits, captured as a number.
  b_value = Ct(
        Cg(V"bw_type", "type")  * P(":")
      * Cg(V"digits" / tonumber, "value")
    ),
  bw_type = C((1 - P(":") - SP - V"line_end") ^ 1),

  -- t= time-field (RFC 8866 §5.9):  t=<start-time> SP <stop-time>
  -- start/stop are decimal integers (or 0 for unbounded). Captured as
  -- Lua numbers. The two Cgs land in the surrounding time_description Ct.
  t_value =
        Cg(V"digits" / tonumber, "start") * SP
      * Cg(V"digits" / tonumber, "stop"),

  -- r= repeat-field (RFC 8866 §5.10):
  --   r=<repeat-interval> SP <active-duration> SP <offset>+
  -- Each token is "typed-time" (decimal integer optionally followed by
  -- d/h/m/s). At least 3 tokens required. Strings preserve the suffix
  -- (e.g., "7d" stays "7d" rather than being normalized to seconds).
  r_value = Ct(
        Cg(V"typed_time", "interval") * SP
      * Cg(V"typed_time", "duration") * SP
      * Cg(Ct(V"typed_time" * (SP * V"typed_time") ^ 0), "offsets")
    ),

  -- z= time-zone-adjustments (RFC 8866 §5.11):
  --   z=<adj-time> SP <offset> ( SP <adj-time> SP <offset> )*
  -- Even-numbered token count; minimum one pair. adjustment_time is a
  -- bare integer (digit string, kept verbatim); offset is signed
  -- typed-time.
  z_value = Ct(V"z_pair" * (SP * V"z_pair") ^ 0),
  z_pair = Ct(
        Cg(V"digits",            "adjustment_time") * SP
      * Cg(V"signed_typed_time", "offset")
    ),

  -- Typed-time sub-grammars (RFC 8866 §5.10): 1*DIGIT optionally followed
  -- by a single unit char (d/h/m/s). signed variant allows leading +/- for
  -- the z= offset use.
  typed_time        = C(R("09") ^ 1 * S("dhms") ^ -1),
  signed_typed_time = C((P("-") + P("+")) ^ -1 * R("09") ^ 1 * S("dhms") ^ -1),

  -- m= media-field (RFC 8866 §5.14):
  --   m=<media> <port>[/<port_count>] <proto> <fmt>+
  -- The captures are FLAT (not wrapped in a sub-Ct) so they land at the
  -- top level of the media_section Ct alongside info / connection / etc.
  -- media: RFC 8866 §5.14 defines audio/video/text/application/message;
  --   parser accepts any token (registry strictness deferred per PLAN.md
  --   Known Deferred Items).
  -- proto: any token (covers "RTP/AVP", "RTP/SAVP", "udp", etc.).
  -- port_count: present iff "/" follows the port; captured as number.
  -- fmts: array of payload-type or format-name tokens.
  m_value =
        Cg(V"token",            "media")  * SP
      * Cg(V"digits" / tonumber, "port")
      * (P("/") * Cg(V"digits" / tonumber, "port_count")) ^ -1
      * SP
      * Cg(V"token",            "proto")  * SP
      * Cg(Ct(V"token" * (SP * V"token") ^ 0), "fmts"),

  -- a= attribute (RFC 8866 §5.13):
  --   a=<attribute>            -- flag form, no colon
  --   a=<attribute>:<value>    -- key-value form
  -- Per-attribute decomposition (Phase 4.A: rtpmap, mid, ptime, maxptime,
  -- framerate, quality). Unknown attributes fall back to the generic
  -- {name, value=string?} shape. Known names with malformed values do NOT
  -- fall through — a_generic refuses to start on a known-name lookahead, so
  -- a malformed known-attr fails the whole grammar match instead of being
  -- silently downgraded to a generic carrier.
  a_value = Ct(
        V"a_rtpmap"
      + V"a_fmtp"
      + V"a_ts_refclk"
      + V"a_mediaclk"
      + V"a_mid"
      + V"a_ptime"
      + V"a_maxptime"
      + V"a_framerate"
      + V"a_quality"
      + V"a_generic"
    ),

  -- Look-ahead: a known compound-attribute name followed by ":" or
  -- end-of-line. Used as a negative lookahead in a_generic so malformed
  -- instances of a known attribute fail the match instead of degrading
  -- to the generic shape. Longer names first (matters for "maxptime"
  -- vs "ptime" / "ts-refclk" vs "mediaclk").
  known_attr_lookahead =
        (P("ts-refclk") + P("maxptime")  + P("framerate")
       + P("mediaclk")  + P("rtpmap")    + P("quality")
       + P("ptime")     + P("fmtp")      + P("mid"))
      * (P(":") + V"line_end"),

  -- rtpmap (RFC 8866 §6.6):
  --   rtpmap-value = payload-type SP encoding-name "/" clock-rate
  --                                                [ "/" encoding-params ]
  -- payload-type: zero-based-integer, normatively 0..127 per §6.6
  -- ("a 7-bit field, limiting the values to inclusively between 0 and 127").
  -- encoding-name: RFC 8866 §9 token. clock-rate: integer (POS-DIGIT *DIGIT).
  -- encoding-params = channels = integer (POS-DIGIT *DIGIT).
  a_rtpmap = P("rtpmap:")
      * Cg(Cc("rtpmap"), "name")
      * Cg(V"payload_type",          "payload_type") * SP
      * Cg(V"rfc8866_token",         "encoding")     * P("/")
      * Cg(V"rfc8866_pos_int_num",   "clock_rate")
      * (P("/") * Cg(V"rfc8866_pos_int_num", "channels")) ^ -1,

  -- fmtp (RFC 8866 §6.15):
  --   fmtp-value = fmt SP format-specific-params
  --   format-specific-params = byte-string
  -- The byte-string ABNF is intentionally opaque — codec-specific. The body
  -- text describes the convention "Format-specific parameters, semicolon
  -- separated" but does not mandate it; non-k=v forms (DTMF event ranges,
  -- red/ulpfec PT lists) are real and conformant. So decomposition is
  -- opportunistic: the kv-list branch commits via `&line_end` and only fires
  -- if the rest is fully decomposable into k=v / bare-flag tokens; otherwise
  -- the raw branch captures the entire byte-string as a string.
  -- Shape:
  --   decomposable -> { name="fmtp", payload_type, params={...} }
  --   opaque       -> { name="fmtp", payload_type, raw="..."     }
  -- params merges k=v (string value) and bare flags (params[flag] = true)
  -- per the 1.0 convention.
  a_fmtp = P("fmtp:")
      * Cg(Cc("fmtp"), "name")
      * Cg(V"payload_type", "payload_type") * SP
      * ( V"fmtp_params_branch" + V"fmtp_raw_branch" ),

  -- Kv-list branch: only commits if the remaining bytes fully decompose into
  -- a non-empty sequence of k=v / flag entries (separated by `;` and optional
  -- horizontal whitespace) all the way to line_end. The `% set_pair` and
  -- `% set_flag` accumulators fold each entry into the seed table from
  -- `Ct(P(""))`. The whole accumulator is wrapped in an anonymous Cg so its
  -- intermediate values don't leak into the surrounding `a_value` Ct
  -- (LPeg idiom: idioms.md §18).
  fmtp_params_branch =
        Cg(
            Ct(P(""))
              * V"fmtp_entry"
              * (V"fmtp_sep" * V"fmtp_entry") ^ 0
              * V"fmtp_sep" ^ -1,           -- optional trailing ';'
            "params"
          )
      * #V"line_end",

  fmtp_entry = V"fmtp_kv_pair" + V"fmtp_flag",
  fmtp_kv_pair =
      ( C(V"fmtp_key_chars" ^ 1) * V"fmtp_hws" ^ 0
        * P("=") * V"fmtp_hws" ^ 0
        * C(V"fmtp_val_chars" ^ 0)
      ) % set_pair,
  fmtp_flag    = C(V"fmtp_key_chars" ^ 1) % set_flag,
  fmtp_sep     = P(";") * V"fmtp_hws" ^ 0,
  fmtp_hws     = S(" \t"),
  -- key/flag char set: identifier-like — ALPHA / DIGIT / '_' / '-'. This
  -- matches the 1.0 parser's `^[%w_%-]+$` flag-token form and the actual
  -- key shape used by every codec we've inspected (H.264 profile-level-id,
  -- ST 2110-20 sampling/width/height, ST 2110-22 jxsv profile/level, Opus
  -- minptime/useinbandfec, etc). Tighter than RFC 8866 §6.15's opaque
  -- byte-string — but a stricter parse is the whole point of decomposition;
  -- non-identifier-shaped content falls into the raw branch instead.
  fmtp_key_chars = R("AZ") + R("az") + R("09") + S("_-"),
  -- value char set: any byte except ';' and CR/LF (RFC 8866 §9 byte-string
  -- forbids NUL/CR/LF; the ';' is the convention separator). Whitespace
  -- inside a value is allowed at the base tier (ST 2110-20 §7.1 narrows).
  fmtp_val_chars = 1 - S(";\r\n"),

  -- Raw fallback: any non-empty byte-string up to line_end. Captured as
  -- `raw` because no `params` field is populated.
  fmtp_raw_branch = Cg(C((1 - V"line_end") ^ 1), "raw"),

  -- mid (RFC 5888 §4): identification-tag = RFC 8866 §9 token.
  -- Uniqueness across the SDP is enforced at doc level (check_mid_uniqueness).
  a_mid = P("mid:")
      * Cg(Cc("mid"), "name")
      * Cg(V"rfc8866_token", "tag"),

  -- ts-refclk (RFC 7273 §4.8):
  --   clksrc = ntp / ptp / gps / gal / glonass / local / private / clksrc-ext
  -- The base tier covers the recognized variants and falls back to the
  -- generic `clksrc-ext` form (clksrc-param-name ["=" byte-string]) for
  -- anything else — including `localmac=<mac>`, which ST 2110-10 §8.2
  -- defines as an extension and the Phase 6 ST 2110 tier will promote
  -- to a recognized form.
  -- Each branch ends with `#V"line_end"` so the choice only commits on a
  -- branch that consumes exactly up to end-of-line — otherwise control
  -- falls through to the next alternative.
  a_ts_refclk = P("ts-refclk:")
      * Cg(Cc("ts-refclk"), "name")
      * ( V"tsr_ntp" + V"tsr_ptp" + V"tsr_private"
        + V"tsr_bare" + V"tsr_ext" ),

  tsr_ntp = P("ntp=") * Cg(Cc("ntp"), "source")
      * ( P("/traceable/") * Cg(Cc(true), "traceable") * #V"line_end"
        + Cg(C((1 - V"line_end") ^ 1), "address") ),

  tsr_ptp = P("ptp=") * Cg(Cc("ptp"), "source")
      * Cg(C(V"rfc8866_token_char" ^ 1), "version")
      * P(":")
      * V"tsr_ptp_server",

  tsr_ptp_server =
        P("traceable") * Cg(Cc(true), "traceable") * #V"line_end"
      + Cg(V"eui64_str", "grandmaster")
          * (P(":") * Cg(C((1 - V"line_end") ^ 1), "domain")) ^ -1
          * #V"line_end",

  tsr_private = P("private") * Cg(Cc("private"), "source")
      * (P(":traceable") * Cg(Cc(true), "traceable")) ^ -1
      * #V"line_end",

  -- Bare clock-source names: gps, gal, glonass, local. The `&line_end`
  -- guard prevents this branch from claiming a prefix-overlapping ext
  -- token (e.g. "local" inside "localmac=...").
  tsr_bare = Cg(C(P("glonass") + P("gps") + P("gal") + P("local")),
                "source")
      * #V"line_end",

  -- Generic clksrc-ext fallback: <token>[=<byte-string>].
  tsr_ext = Cg(C(V"rfc8866_token_char" ^ 1), "source")
      * (P("=") * Cg(C((1 - V"line_end") ^ 1), "value")) ^ -1
      * #V"line_end",

  -- mediaclk (RFC 7273 §5.4):
  --   media-clksrc = "mediaclk:" [media-clkid SP] mediaclock
  --   media-clkid  = "id=" [ "src:" ] media-clktag
  --   mediaclock   = sender / direct / ieee1722-streamid / mediaclock-ext
  --   direct       = "direct" [ "=" 1*DIGIT ] [SP rate]
  --   rate         = "rate=" integer "/" integer
  -- The optional `id=` prefix is decomposed into doc.id (the `src:`
  -- marker, if present, is preserved inline in the captured string).
  a_mediaclk = P("mediaclk:")
      * Cg(Cc("mediaclk"), "name")
      * (V"mediaclk_id_prefix") ^ -1
      * V"mediaclk_body",

  mediaclk_id_prefix = P("id=")
      * Cg(C((1 - SP - V"line_end") ^ 1), "id") * SP,

  mediaclk_body = V"mc_sender" + V"mc_direct" + V"mc_ieee1722" + V"mc_ext",

  mc_sender = P("sender") * Cg(Cc("sender"), "mode") * #V"line_end",

  -- direct: bare or with =offset and/or " rate=N/N". Offset ABNF is
  -- 1*DIGIT (RFC 7273 §5.4) — looser than RFC 8866 §9 integer because
  -- it permits leading zeros; captured as a number via tonumber.
  mc_direct = P("direct") * Cg(Cc("direct"), "mode")
      * (P("=") * Cg(V"mediaclk_offset_num", "offset")) ^ -1
      * (SP * P("rate=") * Cg(V"rate_pair", "rate")) ^ -1
      * #V"line_end",

  mediaclk_offset_num = C(R("09") ^ 1) / tonumber,

  rate_pair = Ct(
        Cg(V"rfc8866_pos_int_num", "num")
      * P("/")
      * Cg(V"rfc8866_pos_int_num", "den")
    ),

  mc_ieee1722 = P("IEEE1722=") * Cg(Cc("IEEE1722"), "mode")
      * Cg(V"eui64_str", "stream_id")
      * #V"line_end",

  mc_ext = Cg(C(V"rfc8866_token_char" ^ 1), "mode")
      * (P("=") * Cg(C((1 - V"line_end") ^ 1), "value")) ^ -1
      * #V"line_end",

  -- EUI-64: 8 hex octets separated by '-' (RFC 7273 §4.8 EUI64 = 7(2HEXDIG
  -- "-") 2HEXDIG). Used by ts-refclk:ptp grandmaster and mediaclk:IEEE1722
  -- stream-id.
  eui64_str = C(V"hex_octet" * (P("-") * V"hex_octet") ^ 7),
  hex_octet = (R("09") + R("AF") + R("af"))
            * (R("09") + R("AF") + R("af")),

  -- ptime (RFC 8866 §6.4) / maxptime (§6.5) / framerate (§6.13):
  -- value = non-zero-int-or-real.
  a_ptime = P("ptime:")
      * Cg(Cc("ptime"),    "name")
      * Cg(V"nonzero_int_or_real_num", "value"),
  a_maxptime = P("maxptime:")
      * Cg(Cc("maxptime"), "name")
      * Cg(V"nonzero_int_or_real_num", "value"),
  a_framerate = P("framerate:")
      * Cg(Cc("framerate"), "name")
      * Cg(V"nonzero_int_or_real_num", "value"),

  -- quality (RFC 8866 §6.14): value = zero-based-integer.
  -- §6.14's "range 0..10" is suggested meaning, not normative; not enforced.
  a_quality = P("quality:")
      * Cg(Cc("quality"), "name")
      * Cg(V"zero_based_int_num", "value"),

  -- Generic fallback: unknown attribute name. Refuses to start on a known
  -- compound-attribute name so malformed known-attrs fail the match.
  a_generic = -V"known_attr_lookahead"
      * Cg(V"attr_name", "name")
      * (P(":") * Cg(V"attr_value", "value")) ^ -1,
  attr_name  = C((1 - P(":") - SP - V"line_end") ^ 1),
  attr_value = C((1 - V"line_end") ^ 1),

  -- ── Numeric leaves (RFC 8866 §9 ABNF) ────────────────────────────────
  -- integer            = POS-DIGIT *DIGIT          ; 1..  (no leading zero)
  -- zero-based-integer = "0" / integer             ; 0, or POS-DIGIT *DIGIT
  -- non-zero-int-or-real = integer / non-zero-real
  -- non-zero-real      = zero-based-integer "." *DIGIT POS-DIGIT
  --                       ; "0" or POS-DIGIT *DIGIT, then ".", then *DIGIT,
  --                       ; ending on POS-DIGIT (so "1.0" is invalid)
  -- The *DIGIT POS-DIGIT tail uses `(DIGIT * #DIGIT)^0 * POS-DIGIT` because
  -- LPeg's `^0` is greedy and non-backtracking: a plain `DIGIT^0 * POS-DIGIT`
  -- would let the repetition consume the final digit and starve POS-DIGIT.
  -- The `#DIGIT` look-ahead only consumes a digit when another follows.
  -- _num variants apply tonumber via the / operator at the leaf.
  rfc8866_pos_int          = R("19") * R("09") ^ 0,
  rfc8866_zero_based_int   = P("0") + V"rfc8866_pos_int",
  rfc8866_nonzero_real     =
        V"rfc8866_zero_based_int" * P(".")
      * (R("09") * #R("09")) ^ 0 * R("19"),
  rfc8866_nonzero_int_or_real =
        V"rfc8866_nonzero_real" + V"rfc8866_pos_int",

  rfc8866_pos_int_num        = C(V"rfc8866_pos_int")              / tonumber,
  zero_based_int_num         = C(V"rfc8866_zero_based_int")       / tonumber,
  nonzero_int_or_real_num    = C(V"rfc8866_nonzero_int_or_real")  / tonumber,

  -- rtpmap payload-type: zero-based-integer constrained to 0..127 (RFC 8866
  -- §6.6). Range check via Cmt; returns the parsed number on success.
  payload_type = Cmt(
      C(V"rfc8866_zero_based_int"),
      function(_, _, s)
        local n = tonumber(s)
        if n > 127 then return false end
        return true, n
      end
    ),

  -- RFC 8866 §9 token character set (referenced by RFC 5888 §4 for
  -- identification-tag and §6.6 for encoding-name):
  --   token-char = %x21 / %x23-27 / %x2A-2B / %x2D-2E / %x30-39
  --              / %x41-5A / %x5E-7E
  -- Excludes SP, DQUOTE, parens, comma, "/", colon-through-"@",
  -- "[", "\", "]", and DEL.
  rfc8866_token_char =
        P("!")                  -- 0x21
      + R("\35\39")             -- 0x23..0x27   # $ % & '
      + R("\42\43")             -- 0x2A..0x2B   * +
      + R("\45\46")             -- 0x2D..0x2E   - .
      + R("\48\57")             -- 0x30..0x39   0-9
      + R("\65\90")             -- 0x41..0x5A   A-Z
      + R("\94\126"),           -- 0x5E..0x7E   ^ _ ` a-z { | } ~
  rfc8866_token = C(V"rfc8866_token_char" ^ 1),

  -- ── Shared sub-leaves ───────────────────────────────────────────────
  -- token: RFC 8866 ABNF "non-ws-string" — one or more VCHAR (any visible
  --   non-whitespace char up to the next SP or CRLF).
  -- digits: one or more ASCII digits, captured as string.
  -- nettype: RFC 8866 §5.2 / §5.7 defines only "IN".
  -- addrtype: RFC 8866 §5.2 / §5.7 defines "IP4" and "IP6".
  token    = C((1 - SP - V"line_end") ^ 1),
  digits   = C(R("09") ^ 1),
  nettype  = C(P("IN")),
  addrtype = C(P("IP4") + P("IP6")),

  -- ── Bottom leaves ───────────────────────────────────────────────────
  -- value: any non-empty run of bytes up to (but not including) the next
  --   line terminator. Used by lines whose values aren't yet decomposed.
  -- line_end: CRLF per RFC 8866 §9 ABNF. Phase 5 will add a soft-syntactic
  --   bare-LF alternative that records a finding.
  value    = (1 - V"line_end") ^ 1,
  line_end = P("\r\n"),
}

local M = {}
M.rules   = rules
M.grammar = lpeg.P(rules)

--- Match `text` against the base SDP grammar.
--
-- @param text  string  The SDP text to parse.
-- @param opts  table?  Optional. Fields:
--                        - policy (table) — id → severity overrides for the
--                          registry. Validated against the registry; unknown
--                          ids raise (caller bug).
--                        - fail_on_first (bool) — true (default) stops at
--                          the first error-severity finding. false collects
--                          everything; caller inspects ctx.findings.
--                        - ctx (table) — supply your own context object,
--                          ignoring policy / fail_on_first above. Lets a
--                          caller share one findings buffer across multiple
--                          matches.
-- @return  doc | nil, ctx
--   On success: the captured doc table, plus the ctx (so the caller can read
--   ctx.findings for warnings even on success).
--   On grammar match failure: nil, ctx (ctx.findings may carry the deepest
--   recorded finding via the tracker).
function M.match(text, opts)
  opts = opts or {}
  local ctx = opts.ctx or {
    findings      = {},
    policy        = opts.policy,
    fail_on_first = opts.fail_on_first ~= false,
  }
  local doc = M.grammar:match(text, 1, ctx)
  return doc, ctx
end

return M
