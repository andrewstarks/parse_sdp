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
local P, V, C, Cg, Ct = lpeg.P, lpeg.V, lpeg.C, lpeg.Cg, lpeg.Ct

local rules = {
  -- Start rule.
  "document",

  -- Top-level captured document. Fields are added one Cg per phase; today
  -- captured: version, session.name (Phase 2.A). The remaining session and
  -- media fields are placeholder pattern matches until their corresponding
  -- sub-commit (2.B–2.E) wraps the leaf in a Cg.
  document = Ct(
        Cg(V"v_line", "version")
      * V"o_line"
      * Cg(Ct(V"session_inner"), "session")
      * V"media_section" ^ 0
    ) * -1,

  -- Session-level inner section: s= through a=*. Phase 2.A captures only
  -- s= → name; 2.B–2.E will add Cg wrappers for i=, u=, e=, p=, c=, b=,
  -- t/r/z, and a=.
  session_inner =
        Cg(V"s_line", "name")
      * V"i_line" ^ -1
      * V"u_line" ^ -1
      * V"e_line" ^ 0
      * V"p_line" ^ 0
      * V"c_line" ^ -1
      * V"b_line" ^ 0
      * (V"t_line" * V"r_line" ^ 0) ^ 1
      * V"z_line" ^ -1
      * V"k_line" ^ -1                       -- RFC 8866 §5.12: parsed and discarded
      * V"a_line" ^ 0,

  -- Media section (RFC 8866 §5):
  --   m= (required), i=?, c=?, b=*, k=?, a=*
  media_section =
        V"m_line"
      * V"i_line" ^ -1
      * V"c_line" ^ -1
      * V"b_line" ^ 0
      * V"k_line" ^ -1
      * V"a_line" ^ 0,

  -- ── Captured line rules (Phase 2.A) ──────────────────────────────────
  -- Each produces ONE capture.
  v_line = P("v=") * V"v_value" * V"line_end",
  s_line = P("s=") * V"s_value" * V"line_end",

  -- ── Placeholder line rules (to be captured in 2.B–2.E) ───────────────
  -- These match-and-discard via V"value". Document shape is enforced;
  -- structural sub-fields aren't surfaced into the doc table yet.
  o_line = P("o=") * V"value" * V"line_end",
  i_line = P("i=") * V"value" * V"line_end",
  u_line = P("u=") * V"value" * V"line_end",
  e_line = P("e=") * V"value" * V"line_end",
  p_line = P("p=") * V"value" * V"line_end",
  c_line = P("c=") * V"value" * V"line_end",
  b_line = P("b=") * V"value" * V"line_end",
  t_line = P("t=") * V"value" * V"line_end",
  r_line = P("r=") * V"value" * V"line_end",
  z_line = P("z=") * V"value" * V"line_end",
  k_line = P("k=") * V"value" * V"line_end",
  a_line = P("a=") * V"value" * V"line_end",
  m_line = P("m=") * V"value" * V"line_end",

  -- ── Captured value rules ─────────────────────────────────────────────
  -- v= MUST be "0" (RFC 8866 §5.1; only value defined for SDP version).
  v_value = C(P("0")),
  -- s= is a non-empty text string. RFC 8866 §5.3 RECOMMENDS "s= " or "s=-"
  -- when there's no meaningful name; the parser accepts either.
  s_value = C((1 - V"line_end") ^ 1),

  -- ── Shared leaves ───────────────────────────────────────────────────
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
