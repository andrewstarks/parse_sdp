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

local lpeg = require("lpeg")
local P, R, S, V, C, Cg, Ct = lpeg.P, lpeg.R, lpeg.S, lpeg.V, lpeg.C, lpeg.Cg, lpeg.Ct

-- Primary patterns shared across rules. These are plain LPeg values rather
-- than V-rules because they are not candidates for per-tier override.
local SP = P(" ")

local rules = {
  -- Start rule.
  "document",

  -- Top-level captured document. Fields are added one Cg per phase; today
  -- captured: version, origin, session.name, session.connection (Phase 2.A–2.B).
  -- The remaining session and media fields are placeholder pattern matches
  -- until their corresponding sub-commit (2.C–2.E) wraps the leaf in a Cg.
  document = Ct(
        Cg(V"v_line", "version")
      * Cg(V"o_line", "origin")
      * Cg(Ct(V"session_inner"), "session")
      * Cg(Ct(V"media_section" ^ 0), "media")
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
      * V"a_line" ^ 0,                       -- captured in 2.E

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
  -- m= itself is captured in 2.E; today it's a placeholder match (no fields
  -- yet from m=, but i/c/b are captured).
  media_section = Ct(
        V"m_line"
      * (Cg(V"i_line", "info")) ^ -1
      * (Cg(V"c_line", "connection")) ^ -1
      * Cg(Ct(V"b_line" ^ 0), "bandwidths")
      * V"k_line" ^ -1
      * V"a_line" ^ 0                        -- captured in 2.E
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

  -- ── Placeholder line rules (to be captured in 2.E) ───────────────────
  k_line = P("k=") * V"value" * V"line_end",
  a_line = P("a=") * V"value" * V"line_end",
  m_line = P("m=") * V"value" * V"line_end",

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

return M
