-- parse_sdp.grammar.patterns — shared LPeg primitives.
--
-- Numeric value-form patterns grounded in RFC 8866 §9 ABNF:
--   integer            = POS-DIGIT *DIGIT          ; 1..  (no leading zero)
--   zero-based-integer = "0" / integer             ; 0, or POS-DIGIT *DIGIT
--
-- The `_raw` forms are unanchored and compose into larger patterns (used
-- inside grammar V-rules and inside composite patterns like fraction/ratio
-- below). The non-raw forms (anchored with `* P(-1)`) are for whole-string
-- value validation via `pattern:match(captured_string)` — returns truthy
-- on full match, nil otherwise.
--
-- Why not `math.tointeger(v)` for value-form validation? Lua's converter
-- is too permissive for spec-conformant POS-DIGIT *DIGIT: it accepts hex
-- literals (`0x780`), scientific notation (`1e3`), leading/trailing
-- whitespace, and signs. These patterns enforce the exact ABNF shape.
--
-- Exports:
--   pos_int_raw         — POS-DIGIT *DIGIT, unanchored
--   zero_based_int_raw  — "0" / POS-DIGIT *DIGIT, unanchored
--   int_raw             — optional "-" + zero-based-integer, unanchored
--   pos_int             — anchored POS-DIGIT *DIGIT
--   zero_based_int      — anchored "0" / POS-DIGIT *DIGIT (non-negative
--                          integer; used by IPMX FEC latency value forms)
--   int                 — anchored signed integer (RFC 8866 doesn't define
--                          a signed-integer ABNF; provided for spec-defined
--                          parameters that are explicitly "any integer",
--                          like ST 2110-21 CMAX)
--   fraction            — anchored `<pos-int>/<pos-int>`, captures (n, d)
--   ratio               — anchored `<pos-int>:<pos-int>`, captures (w, h)

local lpeg = require("lpeg")
local P, R, C = lpeg.P, lpeg.R, lpeg.C

local pos_int_raw         = R("19") * R("09") ^ 0
local zero_based_int_raw  = P("0") + pos_int_raw
local int_raw             = P("-") ^ -1 * zero_based_int_raw

return {
  pos_int_raw         = pos_int_raw,
  zero_based_int_raw  = zero_based_int_raw,
  int_raw             = int_raw,
  pos_int             = pos_int_raw * P(-1),
  zero_based_int      = zero_based_int_raw * P(-1),
  int                 = int_raw * P(-1),
  fraction            = C(pos_int_raw) * P("/") * C(pos_int_raw) * P(-1),
  ratio               = C(pos_int_raw) * P(":") * C(pos_int_raw) * P(-1),
}
