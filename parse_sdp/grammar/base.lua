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
local P, R, S, V, C, Cc, Cg, Cb, Ct, Cmt, Carg =
  lpeg.P, lpeg.R, lpeg.S, lpeg.V, lpeg.C, lpeg.Cc, lpeg.Cg, lpeg.Cb, lpeg.Ct, lpeg.Cmt, lpeg.Carg

-- Primary patterns shared across rules. These are plain LPeg values rather
-- than V-rules because they are not candidates for per-tier override.
local SP = P(" ")

-- Transform a captured list of fmtp entries — each a `{key, value}` or
-- `{flag, true}` sub-table — into the flat `{key = value, flag = true, …}`
-- params table the doc-shape contract exposes. Replaces an earlier
-- `Ct(P("")) * (entry % fold)` chain that triggered LPeg 1.1.0's
-- "no previous value for accumulator capture" intermittently under
-- specific harness conditions (see audits/FMTP_ACCUMULATOR_FLAKE.md).
local function fmtp_entries_to_params(entries)
  local t = {}
  for i = 1, #entries do
    local e = entries[i]
    t[e[1]] = e[2]
  end
  return t
end

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
-- fail_on_first=true for an error-severity finding). Called from a trailing
-- Cmt on the c_value rule (Phase 6.H), so it runs once per c= line at
-- parse time and pos carries the line/col for diagnostics.
local function validate_c_address(addr_type, address, ctx, pos)
  local addr, suffix = split_c_addr:match(address or "")

  if addr_type == "IP4" then
    if not addr or not addresses.ipv4:match(addr) then
      return errors.record(ctx, "sdp.c.address.invalid-ipv4", { pos = pos })
    end
    if addresses.is_ipv4_multicast(addr) then
      if not suffix then
        return errors.record(ctx, "sdp.c.ipv4-multicast.ttl-required",
                             { pos = pos })
      end
      local ttl_str, num_str = ipv4_mcast_suffix:match(suffix)
      if not ttl_str then
        return errors.record(ctx, "sdp.c.ipv4-multicast.ttl-required",
                             { pos = pos })
      end
      local ttl = tonumber(ttl_str)
      if not ttl or ttl > 255 then
        return errors.record(ctx, "sdp.c.ipv4-multicast.ttl-out-of-range",
                             { pos = pos })
      end
      if num_str then
        local n = tonumber(num_str)
        if not n or n < 1 then
          return errors.record(ctx, "sdp.c.ipv4-multicast.numaddr-invalid",
                               { pos = pos })
        end
      end
    elseif suffix then
      return errors.record(ctx, "sdp.c.ipv4-unicast.suffix-not-allowed",
                           { pos = pos })
    end
  elseif addr_type == "IP6" then
    if not addr or not addresses.ipv6:match(addr) then
      return errors.record(ctx, "sdp.c.address.invalid-ipv6", { pos = pos })
    end
    if addresses.is_ipv6_multicast(addr) then
      if suffix then
        local num_str = ipv6_numaddr:match(suffix)
        if not num_str then
          return errors.record(ctx, "sdp.c.ipv6-multicast.suffix-form-invalid",
                               { pos = pos })
        end
        local n = tonumber(num_str)
        if not n or n < 1 then
          return errors.record(ctx, "sdp.c.ipv6-multicast.numaddr-invalid",
                               { pos = pos })
        end
      end
    elseif suffix then
      return errors.record(ctx, "sdp.c.ipv6-unicast.suffix-not-allowed",
                           { pos = pos })
    end
  end
  return true
end

-- Cmt callback for the trailing-validate hook on c_value. Reads the captured
-- addr_type + address via Cb (resolves within the surrounding c_value Ct,
-- since the Cmt is INSIDE that Ct just after the three Cgs close).
local function c_value_validate(_, pos, addr_type, address, ctx)
  if not ctx then return pos end
  if not validate_c_address(addr_type, address, ctx, pos) then return false end
  return pos
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

-- RFC 7273 §4.6 (gps/gal/glonass are traceable to UTC) + §4.7 (`:traceable`
-- suffix on ntp/ptp/private indicates traceable). All other ts-refclk forms
-- (specific NTP servers, specific PTP grandmasters, `local`, bare `private`,
-- clksrc-ext such as `localmac=`) are non-traceable. The Phase 4.C structured
-- shape makes this a direct field lookup — no string-substring heuristics.
local TSREFCLK_TRACEABLE_BARE = { gps = true, gal = true, glonass = true }
local function tsrefclk_is_traceable(attr)
  if attr.traceable then return true end
  if TSREFCLK_TRACEABLE_BARE[attr.source] then return true end
  return false
end

-- RFC 7273 §4.8: "Traceable time sources MUST NOT be mixed with non-traceable
-- time sources at any given level." Checks each level (session, every media)
-- independently — mixing across levels is permitted.
local function check_tsrefclk_traceability(doc, ctx)
  local function check_level(attrs, path)
    local saw_traceable, saw_non = false, false
    for _, attr in ipairs(attrs) do
      if attr.name == "ts-refclk" then
        if tsrefclk_is_traceable(attr) then
          saw_traceable = true
        else
          saw_non = true
        end
      end
    end
    if saw_traceable and saw_non then
      return errors.record(ctx, "sdp.a.ts-refclk.traceable-mix",
                           { field_path = path })
    end
    return true
  end

  if not check_level(doc.session.attributes, "session.attributes") then
    return false
  end
  for i, m in ipairs(doc.media) do
    if not check_level(m.attributes,
                       string.format("media[%d].attributes", i)) then
      return false
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

-- Phase 6.E.A — RFC 5888 §6 group-requires-mid-on-all-media + §9.2
-- group-references-port-zero-mid. Both checks iterate session-level
-- a=group attributes; sharing one function keeps the doc walk in one
-- place. The checks are independent (either may fire alone, both may
-- fire together) and report distinct error IDs.
--
-- §6:  "All of the 'm' lines of a session description that uses 'group'
--       MUST be identified with a 'mid' attribute whether they appear in
--       the group line(s) or not." Conditional on any a=group present.
-- §9.2: "'a=group' lines MUST NOT contain identification-tags that
--        correspond to 'm' lines with the port set to zero."
local function check_group_attribute_invariants(doc, ctx)
  local groups = {}
  for _, attr in ipairs(doc.session.attributes) do
    if attr.name == "group" then groups[#groups + 1] = attr end
  end
  if #groups == 0 then return true end

  -- §6: every m= must have an a=mid (semantics-independent).
  for i, m in ipairs(doc.media) do
    local has_mid = false
    for _, attr in ipairs(m.attributes) do
      if attr.name == "mid" then has_mid = true; break end
    end
    if not has_mid then
      local cont = errors.record(ctx,
        "sdp.a.group.requires-mid-on-all-media",
        { field_path = string.format("media[%d]", i - 1) })
      if not cont then return false end
    end
  end

  -- §9.2: collect mid → media-port, then reject any group tag whose mid
  -- resolves to a port-0 media block.
  local mid_to_port = {}
  for _, m in ipairs(doc.media) do
    for _, attr in ipairs(m.attributes) do
      if attr.name == "mid" then mid_to_port[attr.tag] = m.port end
    end
  end
  for gi, g in ipairs(groups) do
    for _, tag in ipairs(g.tags) do
      if mid_to_port[tag] == 0 then
        local cont = errors.record(ctx,
          "sdp.a.group.references-port-zero-mid",
          { field_path = string.format(
              "session.attributes[group][%d]", gi - 1),
            context    = { tag = tag } })
        if not cont then return false end
      end
    end
  end

  return true
end

-- Soft-syntactic finding recorders (Phase 5). Each runs in a Cmt callback
-- inside the grammar, records the finding via errors.record, and either
-- continues the match (return pos) or fails it (return false) per ctx.policy
-- + ctx.fail_on_first. Default severity is "warn" so warn-severity findings
-- accumulate without halting the parse; policy can promote to "error" or
-- suppress to "off".
local function record_soft(check_id)
  return function(_, pos, ctx)
    if not ctx then return pos end
    local cont = errors.record(ctx, check_id, { pos = pos })
    if not cont then return false end
    return pos
  end
end

local record_bare_lf          = record_soft("sdp.line.lf-only-line-ending")
local record_missing_newline  = record_soft("sdp.file.trailing-newline-missing")
local record_trailing_ws      = record_soft("sdp.line.trailing-whitespace")
-- a=fmtp trailing-';' uses an inline Cmt body inside fmtp_trailing_sep_record
-- because that Cmt has to *consume* the ';' (+ optional whitespace) — a
-- zero-width Cmt(Carg(1), ...) trips LPeg's "no previous value for
-- accumulator capture" error when nested inside the same Cg as the `%`
-- accumulator chain that folds entries into params.

-- Ordered list of cross-section semantic checks the document-level Cmt
-- runs after capture. Phase 6 extends this list per tier via M.extend; the
-- order in which checks execute is the order they appear here.
--
-- Phase 6.H: check_connection_addresses moved in-grammar (Cmt on
-- c_value). The remaining four are genuine cross-section invariants —
-- check_dynamic_pt_rtpmap + check_tsrefclk_traceability are per-media-
-- block and could move to a `media_section` Cmt if that infrastructure
-- gets added; check_mid_uniqueness + check_group_attribute_invariants
-- span media blocks and stay doc-level either way.
local base_semantic_checks = {
  check_dynamic_pt_rtpmap,
  check_mid_uniqueness,
  check_group_attribute_invariants,
  check_tsrefclk_traceability,
}

-- Factory producing a document-level Cmt callback bound to a specific
-- check list. Walks the captured doc, runs each check in order, records
-- findings into ctx, and either continues (return position, doc) or fails
-- the match (return false) per ctx.fail_on_first.
--
-- Signature follows the LPeg manual's Cmt contract:
--   f(subject, position, capture1, ..., captureN) → control values
-- Capture pattern is `document_body * Carg(1)`, so callback receives
-- [doc, ctx].
local function make_validate_doc(checks)
  return function(_, position, doc, ctx)
    -- Grammar-only consumers (no extra-arg path) get ctx=nil; default to
    -- hard-fail-on-first with findings discarded.
    if ctx == nil then
      ctx = { findings = {}, fail_on_first = true }
    end
    for i = 1, #checks do
      if not checks[i](doc, ctx) then return false end
    end
    return position, doc
  end
end

-- The Ct body of the `document` rule, as a factory that returns a FRESH
-- pattern each call. The body contains unresolved V-refs (V"v_line",
-- V"session_inner", etc.); reusing the same pattern object across two
-- grammar compilations (`lpeg.P(base.rules)` and `lpeg.P(child.rules)`)
-- causes intermittent runtime "no previous value for accumulator capture"
-- errors deep inside fmtp's `%` accumulator chain — symptom of LPeg
-- rewriting the shared tree's V-resolution on the second compile. Each
-- grammar must own its own document_body tree.
--
-- The V-rule alternative (`V"document_body"` in the rules table) is also
-- unsafe: it breaks `%` accumulator capture inside leaves because V-rule
-- indirection interferes with LPeg's compile-time resolution of
-- `Ct(P("")) * X % fold`.
local function make_document_body()
  return Ct(
        Cg(V"v_line", "version")
      * Cg(V"o_line", "origin")
      * Cg(Ct(V"session_inner"), "session")
      * Cg(Ct(V"media_section" ^ 0), "media")
    )
end

local rules = {
  -- Start rule.
  "document",

  -- Top-level captured document. Fields are added one Cg per phase; today
  -- captured: version, origin, session.name, session.connection (Phase 2.A–2.B).
  -- The remaining session and media fields are placeholder pattern matches
  -- until their corresponding sub-commit (2.C–2.E) wraps the leaf in a Cg.
  document = V"bom_opt" * Cmt(make_document_body() * Carg(1),
                              make_validate_doc(base_semantic_checks))
           * -1,

  -- Optional UTF-8 BOM (EF BB BF) at the start of the file. RFC 8866 §6
  -- doesn't require it and SDP charset signaling lives in `a=charset:`;
  -- some text editors emit one anyway. The Cmt consumes the three bytes
  -- and records the soft-syntactic finding.
  bom_opt = Cmt(P("\239\187\191") * Carg(1),
                function(_, pos, ctx)
                  if not ctx then return pos end
                  local cont = errors.record(ctx, "sdp.file.bom-present", {})
                  if not cont then return false end
                  return pos
                end) ^ -1,

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
  s_value = C((1 - V"value_boundary_chars") ^ 1),

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
      -- Phase 6.H: validate the captured address inline (multicast TTL/
      -- numaddr suffix forms, IPv4/IPv6 syntax, unicast-with-suffix
      -- rejection). Was a post-parse doc walk via check_connection_
      -- addresses; lifted in-grammar so findings carry line/col and the
      -- check fires the moment a c= line completes. Cb resolves within
      -- this Ct because the trailing Cmt sits just after the three Cgs.
      * Cmt(Cb"addr_type" * Cb"address" * Carg(1), c_value_validate)
    ),

  -- Text fields. RFC 8866 §5.4, §5.5, §5.6 — each takes a "text" value
  -- (one or more bytes up to the next CRLF). At the base tier we accept
  -- the value as a single string; Phase 3 will add a soft-syntactic
  -- finding for embedded bare CR (forbidden by the §9 ABNF byte-string).
  i_value = C((1 - V"value_boundary_chars") ^ 1),
  u_value = C((1 - V"value_boundary_chars") ^ 1),
  e_value = C((1 - V"value_boundary_chars") ^ 1),
  p_value = C((1 - V"value_boundary_chars") ^ 1),

  -- b= bandwidth (RFC 8866 §5.8):  b=<bwtype>:<bandwidth>
  -- bwtype is a token (defined value forms include "CT", "AS", "TIAS",
  -- "RS", "RR"; experimental ones use "X-..."); value-set validation
  -- lives in Phase 3. bandwidth is decimal digits, captured as a number.
  b_value = Ct(
        Cg(V"bw_type", "type")  * P(":")
      * Cg(V"digits" / tonumber, "value")
    ),
  bw_type = C((1 - P(":") - SP - V"line_end_chars") ^ 1),

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
      + V"a_source_filter"
      + V"a_group"
      + V"a_ssrc_group"
      + V"a_ssrc"
      + V"a_msid"
      + V"a_mid"
      + V"a_extmap"
      + V"a_rtcp_fb"
      + V"a_rtcp_mux"
      + V"a_rtcp"
      + V"a_ptime"
      + V"a_maxptime"
      + V"a_framerate"
      + V"a_quality"
      + V"a_generic"
    ),

  -- Look-ahead: a known compound-attribute name followed by ":" or
  -- end-of-line. Used as a negative lookahead in a_generic so malformed
  -- instances of a known attribute fail the match instead of degrading
  -- to the generic shape. Order: longer-prefix patterns before their
  -- shorter siblings (matters for "ssrc-group" vs "ssrc", "rtcp-mux" /
  -- "rtcp-fb" vs "rtcp", and the "maxptime" vs "ptime" group).
  known_attr_lookahead =
        (P("source-filter") + P("ssrc-group") + P("ts-refclk")
       + P("maxptime")      + P("framerate")  + P("mediaclk")
       + P("rtcp-mux")      + P("rtcp-fb")    + P("extmap")
       + P("rtpmap")        + P("quality")    + P("group")
       + P("ptime")         + P("msid")       + P("ssrc")
       + P("rtcp")          + P("fmtp")       + P("mid"))
      * (P(":") + V"line_end_chars"),

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

  -- Kv-list branch: only commits if the remaining bytes fully decompose
  -- into a non-empty sequence of k=v / flag entries (separated by `;` and
  -- optional horizontal whitespace) all the way to line_end. Each entry
  -- captures a 2-element sub-table — `{key, value}` for kv pairs and
  -- `{flag, true}` for bare flags. The outer `Ct(...) / fmtp_entries_to_params`
  -- transforms that list of pairs into the `{key = value, flag = true, …}`
  -- shape the doc contract exposes.
  --
  -- An earlier shape used LPeg 1.1.0's `%` accumulator
  -- (`Ct(P("")) * (entry % set_pair) * …`). That tripped LPeg's "no previous
  -- value for accumulator capture" intermittently under specific test-harness
  -- conditions (audits/FMTP_ACCUMULATOR_FLAKE.md); the function-capture form
  -- avoids the runtime path that error fires from.
  --
  -- The optional trailing-';' detector lives OUTSIDE the params Cg now so a
  -- `^-1` Cmt(...; Carg(1), …) tail can't interact with the params capture's
  -- internal state.
  fmtp_params_branch =
        Cg(
            Ct(V"fmtp_entry" * (V"fmtp_sep" * V"fmtp_entry") ^ 0)
              / fmtp_entries_to_params,
            "params"
          )
      * V"fmtp_trailing_sep_record" ^ -1
      * #V"line_end_chars",

  fmtp_trailing_sep_record =
      Cmt(P(";") * V"fmtp_hws" ^ 0 * Carg(1),
          function(_, pos, ctx)
            if not ctx then return pos end
            local cont = errors.record(ctx,
              "sdp.a.fmtp.trailing-semicolon", { pos = pos })
            if not cont then return false end
            return pos
          end),

  fmtp_entry   = V"fmtp_kv_pair" + V"fmtp_flag",
  fmtp_kv_pair = Ct(
      C(V"fmtp_key_chars" ^ 1) * V"fmtp_hws" ^ 0
      * P("=") * V"fmtp_hws" ^ 0
      * C(V"fmtp_val_chars" ^ 0)
    ),
  fmtp_flag    = Ct(C(V"fmtp_key_chars" ^ 1) * Cc(true)),
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
  fmtp_raw_branch = Cg(C((1 - V"value_boundary_chars") ^ 1), "raw"),

  -- mid (RFC 5888 §4): identification-tag = RFC 8866 §9 token.
  -- Uniqueness across the SDP is enforced at doc level (check_mid_uniqueness).
  a_mid = P("mid:")
      * Cg(Cc("mid"), "name")
      * Cg(V"rfc8866_token", "tag"),

  -- source-filter (RFC 4570 §3):
  --   filter-spec = filter-mode SP nettype SP addrtype SP dest-address
  --                                                    SP 1*(src-address SP)
  -- filter-mode = "incl" / "excl"
  -- nettype is "IN" (RFC 8866 §5.7 / §9). addrtype = "IP4" / "IP6" / "*";
  -- when "*" the dest/src are FQDNs (no literal-IP grammar enforced at the
  -- base tier — address-form validation belongs to a tiered narrowing, like
  -- ST 2110-10 §6.5 / §8.4).
  a_source_filter = P("source-filter:")
      * Cg(Cc("source-filter"), "name")
      * Cg(C(P("incl") + P("excl")), "filter_mode") * SP
      * Cg(C(P("IN")),                   "net_type") * SP
      * Cg(C(P("IP4") + P("IP6") + P("*")), "addr_type") * SP
      * Cg(V"non_ws_token", "dest_address")
      * Cg(Ct((SP * V"non_ws_token") ^ 1), "src_addresses"),

  non_ws_token = C((1 - SP - V"line_end_chars") ^ 1),

  -- group (RFC 5888 §5):
  --   group-attribute = "group:" semantics *(SP identification-tag)
  -- semantics and each identification-tag are RFC 8866 §9 tokens. The
  -- *(SP id-tag) is zero-or-more, so `a=group:LS` (no tags) is conformant
  -- per the ABNF, however nonsensical.
  a_group = P("group:")
      * Cg(Cc("group"), "name")
      * Cg(V"rfc8866_token", "semantics")
      * Cg(Ct((SP * V"rfc8866_token") ^ 0), "tags"),

  -- ssrc-group (RFC 5576 §10 Figure 5):
  --   ssrc-group-attr = "ssrc-group:" semantics *(SP ssrc-id)
  --   semantics       = "FEC" / "FID" / token         ; RFC 8866 §9 token
  --   ssrc-id         = integer                       ; 0..2^32-1
  -- *(SP ssrc-id) is zero-or-more per ABNF (matches the a_group shape).
  a_ssrc_group = P("ssrc-group:")
      * Cg(Cc("ssrc-group"), "name")
      * Cg(V"rfc8866_token", "semantics")
      * Cg(Ct((SP * V"ssrc_id_num") ^ 0), "ssrc_ids"),

  -- ssrc-id is 0..2^32-1 (RFC 5576 §10 Figure 4). Lua 5.5 integer subtype
  -- represents this range exactly, so we capture as a number via tonumber.
  -- No range-check Cmt yet — Phase 5 may add a soft-syntactic finding for
  -- overflow; for now we accept any decimal-digit run.
  ssrc_id_num = C(R("09") ^ 1) / tonumber,

  -- ssrc (RFC 5576 §10 Figure 4):
  --   ssrc-attr = "ssrc:" ssrc-id SP attribute
  -- where `attribute` is the RFC 8866 §5.13 attribute body: name [":" value].
  a_ssrc = P("ssrc:")
      * Cg(Cc("ssrc"), "name")
      * Cg(V"ssrc_id_num", "ssrc_id") * SP
      * Cg(V"attr_name", "attribute")
      * (P(":") * Cg(V"attr_value", "value")) ^ -1,

  -- msid (RFC 8830 §2):
  --   msid-value = msid-id [SP msid-appdata]
  -- Both msid-id and msid-appdata are tokens (the WebRTC use case forbids
  -- whitespace inside either; we use the non-ws-token form).
  a_msid = P("msid:")
      * Cg(Cc("msid"), "name")
      * Cg(V"non_ws_token", "msid_id")
      * (SP * Cg(V"non_ws_token", "appdata")) ^ -1,

  -- extmap (RFC 8285 §8):
  --   extmap-value        = mapentry SP extensionname [SP extensionattributes]
  --   mapentry            = "extmap:" 1*5DIGIT ["/" direction]
  --   extensionname       = URI
  --   extensionattributes = byte-string
  --   direction           = "sendonly" / "recvonly" / "sendrecv" / "inactive"
  -- The 1*5 DIGIT range bounds the local-id to 1..99999; we capture it as a
  -- number. URI form validation is out of scope at the base tier.
  a_extmap = P("extmap:")
      * Cg(Cc("extmap"), "name")
      * Cg(C(R("09") ^ 1) / tonumber, "id")
      * (P("/") * Cg(V"extmap_direction", "direction")) ^ -1
      * SP
      * Cg(V"non_ws_token", "uri")
      * (SP * Cg(C((1 - V"value_boundary_chars") ^ 1), "attributes")) ^ -1,

  extmap_direction = C(P("sendonly") + P("recvonly")
                     + P("sendrecv") + P("inactive")),

  -- rtcp-fb (RFC 4585 §4.2):
  --   rtcp-fb-syntax = "a=rtcp-fb:" rtcp-fb-pt SP rtcp-fb-val CRLF
  --   rtcp-fb-pt     = "*" / fmt        ; fmt is a payload-type integer
  --   rtcp-fb-val    = "ack" rtcp-fb-ack-param
  --                  / "nack" rtcp-fb-nack-param
  --                  / "trr-int" SP 1*DIGIT
  --                  / rtcp-fb-id rtcp-fb-param
  -- We decompose into {payload_type, feedback_type, parameters?}. The
  -- payload_type is a number for numeric fmt, or the string "*" for the
  -- wildcard form (consumers dispatch on type). The full feedback subgrammar
  -- (ack/nack-specific param sets) is not enforced at the base tier — that
  -- belongs to a tiered narrowing if needed; here we capture parameters
  -- verbatim as the rest of the line.
  a_rtcp_fb = P("rtcp-fb:")
      * Cg(Cc("rtcp-fb"), "name")
      * Cg(V"rtcp_fb_pt", "payload_type") * SP
      * Cg(V"rfc8866_token", "feedback_type")
      * (SP * Cg(C((1 - V"value_boundary_chars") ^ 1), "parameters")) ^ -1,

  -- Either the string "*" (captured as a literal) OR a numeric payload-type
  -- (captured as a number via tonumber). Type-polymorphic by design.
  rtcp_fb_pt = C(P("*")) + V"payload_type",

  -- rtcp (RFC 3605 §2.1):
  --   rtcp-attribute = "a=rtcp:" port  [nettype space addrtype space
  --                                     connection-address] CRLF
  -- port is a decimal integer (RFC 8866 §9 integer = POS-DIGIT *DIGIT).
  -- The optional nettype/addrtype/connection-address triple mirrors the
  -- c= line form; we capture each as a separate field for symmetry.
  a_rtcp = P("rtcp:")
      * Cg(Cc("rtcp"), "name")
      * Cg(V"rfc8866_pos_int_num", "port")
      * (SP * Cg(V"nettype",  "net_type")
            * SP * Cg(V"addrtype", "addr_type")
            * SP * Cg(V"token",    "address")) ^ -1,

  -- rtcp-mux (RFC 5761 §5.1.3): flag attribute, no value. The `#line_end`
  -- guard makes the rule reject "a=rtcp-mux:<anything>" — known_attr_lookahead
  -- then blocks a_generic from claiming it.
  a_rtcp_mux = P("rtcp-mux")
      * Cg(Cc("rtcp-mux"), "name")
      * #V"line_end_chars",

  -- ts-refclk (RFC 7273 §4.8):
  --   clksrc = ntp / ptp / gps / gal / glonass / local / private / clksrc-ext
  -- The base tier covers the recognized variants and falls back to the
  -- generic `clksrc-ext` form (clksrc-param-name ["=" byte-string]) for
  -- anything else — including `localmac=<mac>`, which ST 2110-10 §8.2
  -- defines as an extension and the Phase 6 ST 2110 tier will promote
  -- to a recognized form.
  -- Each branch ends with `#V"line_end_chars"` so the choice only commits on a
  -- branch that consumes exactly up to end-of-line — otherwise control
  -- falls through to the next alternative.
  a_ts_refclk = P("ts-refclk:")
      * Cg(Cc("ts-refclk"), "name")
      * ( V"tsr_ntp" + V"tsr_ptp" + V"tsr_private"
        + V"tsr_bare" + V"tsr_ext" ),

  tsr_ntp = P("ntp=") * Cg(Cc("ntp"), "source")
      * ( P("/traceable/") * Cg(Cc(true), "traceable") * #V"line_end_chars"
        + Cg(C((1 - V"value_boundary_chars") ^ 1), "address") ),

  tsr_ptp = P("ptp=") * Cg(Cc("ptp"), "source")
      * Cg(C(V"rfc8866_token_char" ^ 1), "version")
      * P(":")
      * V"tsr_ptp_server",

  tsr_ptp_server =
        P("traceable") * Cg(Cc(true), "traceable") * #V"line_end_chars"
      + Cg(V"eui64_str", "grandmaster")
          * (P(":") * Cg(C((1 - V"value_boundary_chars") ^ 1), "domain")) ^ -1
          * #V"line_end_chars",

  tsr_private = P("private") * Cg(Cc("private"), "source")
      * (P(":traceable") * Cg(Cc(true), "traceable")) ^ -1
      * #V"line_end_chars",

  -- Bare clock-source names: gps, gal, glonass, local. The `&line_end`
  -- guard prevents this branch from claiming a prefix-overlapping ext
  -- token (e.g. "local" inside "localmac=...").
  tsr_bare = Cg(C(P("glonass") + P("gps") + P("gal") + P("local")),
                "source")
      * #V"line_end_chars",

  -- Generic clksrc-ext fallback: <token>[=<byte-string>].
  tsr_ext = Cg(C(V"rfc8866_token_char" ^ 1), "source")
      * (P("=") * Cg(C((1 - V"value_boundary_chars") ^ 1), "value")) ^ -1
      * #V"line_end_chars",

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
      * Cg(C((1 - SP - V"line_end_chars") ^ 1), "id") * SP,

  mediaclk_body = V"mc_sender" + V"mc_direct" + V"mc_ieee1722" + V"mc_ext",

  mc_sender = P("sender") * Cg(Cc("sender"), "mode") * #V"line_end_chars",

  -- direct: bare or with =offset and/or " rate=N/N". Offset ABNF is
  -- 1*DIGIT (RFC 7273 §5.4) — looser than RFC 8866 §9 integer because
  -- it permits leading zeros; captured as a number via tonumber.
  mc_direct = P("direct") * Cg(Cc("direct"), "mode")
      * (P("=") * Cg(V"mediaclk_offset_num", "offset")) ^ -1
      * (SP * P("rate=") * Cg(V"rate_pair", "rate")) ^ -1
      * #V"line_end_chars",

  mediaclk_offset_num = C(R("09") ^ 1) / tonumber,

  rate_pair = Ct(
        Cg(V"rfc8866_pos_int_num", "num")
      * P("/")
      * Cg(V"rfc8866_pos_int_num", "den")
    ),

  mc_ieee1722 = P("IEEE1722=") * Cg(Cc("IEEE1722"), "mode")
      * Cg(V"eui64_str", "stream_id")
      * #V"line_end_chars",

  mc_ext = Cg(C(V"rfc8866_token_char" ^ 1), "mode")
      * (P("=") * Cg(C((1 - V"value_boundary_chars") ^ 1), "value")) ^ -1
      * #V"line_end_chars",

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
  attr_name  = C((1 - P(":") - SP - V"line_end_chars") ^ 1),
  attr_value = C((1 - V"value_boundary_chars") ^ 1),

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
  token    = C((1 - SP - V"line_end_chars") ^ 1),
  digits   = C(R("09") ^ 1),
  nettype  = C(P("IN")),
  addrtype = C(P("IP4") + P("IP6")),

  -- ── Bottom leaves ───────────────────────────────────────────────────
  -- value: any non-empty run of bytes up to (but not including) the next
  --   line terminator. Used by lines whose values aren't yet decomposed.
  -- line_end (Phase 5): three branches in priority order —
  --   1. strict CRLF (RFC 8866 §9 ABNF).
  --   2. bare LF — soft-syntactic, records sdp.line.lf-only-line-ending.
  --   3. end-of-input lookahead — fires once on the last line if the file
  --      ends without a terminator; records sdp.file.trailing-newline-missing.
  --      #P(-1) does not consume, so the surrounding `* -1` in `document`
  --      still matches EOF after the finding lands.
  -- line_end_chars: pure-structural counterpart used for byte-boundary
  -- lookaheads (`1 - V"line_end_chars"`, `#V"line_end_chars"`). Cmt
  -- callbacks fire during lookahead evaluation in LPeg, so using V"line_end"
  -- in a `1 -` predicate would spuriously record findings on every byte
  -- tested against the boundary. The chars-only rule has no captures and
  -- no side effects.
  value          = (1 - V"value_boundary_chars") ^ 1,
  -- A value position can stop at either a line terminator (line_end_chars)
  -- or at the FIRST byte of trailing horizontal whitespace that itself
  -- precedes a terminator (so the trailing-ws Cmt branch in line_end gets a
  -- chance to fire). Internal whitespace (ws not adjacent to a terminator)
  -- stays inside the value.
  value_boundary_chars = S(" \t") ^ 1 * V"line_end_chars" + V"line_end_chars",
  line_end_chars       = P("\r\n") + P("\n") + P(-1),

  line_end =
        Cmt(S(" \t") ^ 1 * Carg(1), record_trailing_ws) * V"line_end_core"
      + V"line_end_core",

  line_end_core = P("\r\n")
                + Cmt(P("\n") * Carg(1), record_bare_lf)
                + Cmt(#P(-1)  * Carg(1), record_missing_newline),
}

-- Driver that runs `grammar` against `text` with a fresh ctx (or one the
-- caller supplied via opts.ctx). Shared by M.match and the M.extend
-- closure so child tiers don't re-implement it.
local function make_match(grammar)
  return function(text, opts)
    opts = opts or {}
    local ctx = opts.ctx or {
      findings      = {},
      policy        = opts.policy,
      fail_on_first = opts.fail_on_first ~= false,
      text          = text,   -- enables pos → line/col in errors.record
    }
    local doc = grammar:match(text, 1, ctx)
    return doc, ctx
  end
end

local M = {}
M.rules                   = rules
M.grammar                 = lpeg.P(rules)
M.semantic_checks         = base_semantic_checks
M.make_validate_doc       = make_validate_doc
M.make_document_body      = make_document_body
M.fmtp_entries_to_params  = fmtp_entries_to_params

--- Compose a child tier from a parent.
--
-- `parent` is a table with the same shape this module exports: `rules`,
-- `semantic_checks`, `make_validate_doc`. `overrides` carries the child's
-- contributions:
--   - `rules`            — table of rule-name → pattern overrides
--                          (merged into parent.rules; child wins on collision)
--   - `semantic_checks`  — ordered list of (doc, ctx) → bool functions
--                          appended to parent.semantic_checks
--
-- The child rebuilds the `document` rule so its Cmt validator closes over
-- the merged check list. Any rule override the child supplies (including
-- a leaf override that lives below `document`) is in the merged rules table
-- and gets picked up at lpeg.P(rules) compile time.
--
-- Returns a table mirroring base's exports plus `match` and `extend`, so
-- IPMX in Phase 7 chains with `st2110:extend({...})`-equivalent call.
function M.extend(parent, overrides)
  overrides = overrides or {}

  local child_rules = {}
  for k, v in pairs(parent.rules) do child_rules[k] = v end
  for k, v in pairs(overrides.rules or {}) do child_rules[k] = v end

  local child_checks = {}
  for _, c in ipairs(parent.semantic_checks) do
    child_checks[#child_checks + 1] = c
  end
  for _, c in ipairs(overrides.semantic_checks or {}) do
    child_checks[#child_checks + 1] = c
  end

  -- Build a fresh document_body for the child via the parent's factory.
  -- Sharing a single document_body pattern object across two grammar
  -- compilations is unsafe: LPeg rewrites the tree's V-resolution on the
  -- second compile, which intermittently corrupts the FIRST grammar's
  -- match behaviour (manifests as "no previous value for accumulator
  -- capture" inside fmtp's `%` accumulator).
  child_rules.document = V"bom_opt"
    * Cmt(parent.make_document_body() * Carg(1),
          parent.make_validate_doc(child_checks))
    * -1

  local child_grammar = lpeg.P(child_rules)
  local child = {
    rules                   = child_rules,
    grammar                 = child_grammar,
    semantic_checks         = child_checks,
    make_validate_doc       = parent.make_validate_doc,
    make_document_body      = parent.make_document_body,
    fmtp_entries_to_params  = parent.fmtp_entries_to_params,
    extend                  = M.extend,
    match                   = make_match(child_grammar),
  }
  return child
end

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
M.match = make_match(M.grammar)

return M
