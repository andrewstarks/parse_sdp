-- parse_sdp.grammar.base — RFC 8866 base SDP grammar skeleton.
--
-- This module exports the *rule table* for the base tier (Phase 1) and a
-- compiled `lpeg.P(rules)` for current use. The rule table is the unit of
-- composition: Phases 6 and 7 will produce st2110 and ipmx grammars by
-- calling `extend(base.rules, overrides)` and recompiling.
--
-- Phase 1 deliverable: document shape only. Every leaf is a placeholder that
-- accepts "any non-empty line content" — value-set checks, decomposition, and
-- the rich doc table all land in Phase 2 onward.
--
-- The grammar reads top-down from `document`, following RFC 8866 §5:
--
--   document        = session_section media_section* EOF
--   session_section = v= o= s= [i=] [u=] e=* p=* [c=] b=*
--                     (t= r=*)+ [z=] [k=] a=*
--   media_section   = m= [i=] [c=] b=* [k=] a=*

local lpeg = require("lpeg")
local P, V = lpeg.P, lpeg.V

local rules = {
  -- Start rule:
  "document",

  -- Document shape per RFC 8866 §5: session section followed by zero or
  -- more media sections, then end-of-input.
  document = V"session_section" * V"media_section"^0 * -1,

  -- Session section (RFC 8866 §5):
  --   v= (required), o= (required), s= (required),
  --   i=?, u=?, e=*, p=*, c=?, b=*,
  --   (t= r=*)+,  -- one or more time descriptions
  --   z=?, k=?, a=*
  session_section =
        V"v_line"
      * V"o_line"
      * V"s_line"
      * V"i_line" ^ -1
      * V"u_line" ^ -1
      * V"e_line" ^ 0
      * V"p_line" ^ 0
      * V"c_line" ^ -1
      * V"b_line" ^ 0
      * (V"t_line" * V"r_line" ^ 0) ^ 1
      * V"z_line" ^ -1
      * V"k_line" ^ -1
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

  -- Line shapes: <letter>= <value> <line-end>.
  -- Phase 2 replaces V"value" on each line with the field's specific
  -- value-grammar; the per-line wrapper structure stays.
  v_line = P("v=") * V"value" * V"line_end",
  o_line = P("o=") * V"value" * V"line_end",
  s_line = P("s=") * V"value" * V"line_end",
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

  -- Leaf placeholders. Phase 2 replaces these with field-specific grammars
  -- and capture-producing forms.
  --
  -- value: any non-empty run of bytes up to (but not including) the next
  --   line terminator. SDP values are required to be non-empty per RFC 8866
  --   §5 (the `text` production: `text = 1*(non-line-end-byte)`).
  -- line_end: CRLF per RFC 8866 §9 ABNF. §5 prose says "parsers SHOULD be
  --   tolerant and also accept lines terminated with a single newline" — bare
  --   LF acceptance moves into a soft-syntactic finding in Phase 5.
  value    = (1 - V"line_end") ^ 1,
  line_end = P("\r\n"),
}

local M = {}
M.rules   = rules
M.grammar = lpeg.P(rules)

return M
