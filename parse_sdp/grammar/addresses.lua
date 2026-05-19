-- parse_sdp.grammar.addresses — IPv4 / IPv6 address grammars.
--
-- Per RFC 791 (IPv4) and RFC 4291 / RFC 3986 §3.2.2 (IPv6). The IPv6
-- grammar is the 38-alternative form that covers every valid compressed
-- and uncompressed representation, including IPv4-mapped IPv6 ("::ffff:1.2.3.4").
-- Adapted from lpeg_patterns © 2012–2016 daurnimator (MIT). All value
-- captures stripped; this module exports pure structural patterns plus
-- small classification helpers.
--
-- Exports:
--   ipv4_raw    — IPv4 dotted-quad, not anchored (composable, e.g. as ls32 in IPv6)
--   ipv4        — IPv4 anchored to end-of-input
--   ipv6        — IPv6 anchored to end-of-input (single rule entry point)
--   is_ipv4_multicast(addr_string)  — first-octet check (224–239)
--   is_ipv6_multicast(addr_string)  — first-octet check (ff00::/8)

local lpeg = require("lpeg")
local P, R, S, V, C = lpeg.P, lpeg.R, lpeg.S, lpeg.V, lpeg.C

-- IPv4 octet (0–255).
local octet = (P("25") * R("05"))
            + (P("2") * R("04") * R("09"))
            + (P("1") * R("09") * R("09"))
            + (R("19") * R("09"))
            + R("09")

local ipv4_raw = octet * P(".") * octet * P(".") * octet * P(".") * octet
local ipv4     = ipv4_raw * P(-1)

-- IPv6 grammar per RFC 4291 §2.2.
local HEXDIG = R("09", "af", "AF")
local ipv6 = P({
  "ipv6",

  h16    = HEXDIG * HEXDIG ^ -3,
  h16c   = V"h16" * P":",
  ls32   = (V"h16c" * V"h16") + ipv4_raw,

  mh16c_1 = V"h16c",
  mh16c_2 = V"h16c" * V"h16c",
  mh16c_3 = V"h16c" * V"h16c" * V"h16c",
  mh16c_4 = V"h16c" * V"h16c" * V"h16c" * V"h16c",
  mh16c_5 = V"h16c" * V"h16c" * V"h16c" * V"h16c" * V"h16c",
  mh16c_6 = V"h16c" * V"h16c" * V"h16c" * V"h16c" * V"h16c" * V"h16c",

  mcc = P("::"),

  mh16_1 = V"h16",
  mh16_2 = V"mh16c_1" * V"h16",
  mh16_3 = V"mh16c_2" * V"h16",
  mh16_4 = V"mh16c_3" * V"h16",
  mh16_5 = V"mh16c_4" * V"h16",
  mh16_6 = V"mh16c_5" * V"h16",
  mh16_7 = V"mh16c_6" * V"h16",

  ipv6 = (
                                  V"mh16c_6" * V"ls32"
        +             V"mcc"    * V"mh16c_5" * V"ls32"
        +             V"mcc"    * V"mh16c_4" * V"ls32"
        + V"h16"    * V"mcc"    * V"mh16c_4" * V"ls32"
        +             V"mcc"    * V"mh16c_3" * V"ls32"
        + V"h16"    * V"mcc"    * V"mh16c_3" * V"ls32"
        + V"mh16_2" * V"mcc"    * V"mh16c_3" * V"ls32"
        +             V"mcc"    * V"mh16c_2" * V"ls32"
        + V"h16"    * V"mcc"    * V"mh16c_2" * V"ls32"
        + V"mh16_2" * V"mcc"    * V"mh16c_2" * V"ls32"
        + V"mh16_3" * V"mcc"    * V"mh16c_2" * V"ls32"
        +             V"mcc"    * V"h16c"    * V"ls32"
        + V"h16"    * V"mcc"    * V"h16c"    * V"ls32"
        + V"mh16_2" * V"mcc"    * V"h16c"    * V"ls32"
        + V"mh16_3" * V"mcc"    * V"h16c"    * V"ls32"
        + V"mh16_4" * V"mcc"    * V"h16c"    * V"ls32"
        +             V"mcc"                 * V"ls32"
        + V"h16"    * V"mcc"                 * V"ls32"
        + V"mh16_2" * V"mcc"                 * V"ls32"
        + V"mh16_3" * V"mcc"                 * V"ls32"
        + V"mh16_4" * V"mcc"                 * V"ls32"
        + V"mh16_5" * V"mcc"                 * V"ls32"
        +             V"mcc"    * V"h16"
        + V"h16"    * V"mcc"    * V"h16"
        + V"mh16_2" * V"mcc"    * V"h16"
        + V"mh16_3" * V"mcc"    * V"h16"
        + V"mh16_4" * V"mcc"    * V"h16"
        + V"mh16_5" * V"mcc"    * V"h16"
        + V"mh16_6" * V"mcc"    * V"h16"
        +             V"mcc"
        + V"mh16_1" * V"mcc"
        + V"mh16_2" * V"mcc"
        + V"mh16_3" * V"mcc"
        + V"mh16_4" * V"mcc"
        + V"mh16_5" * V"mcc"
        + V"mh16_6" * V"mcc"
        + V"mh16_7" * V"mcc"
  ) * P(-1),
}) * P(-1)

-- Multicast classification helpers. These inspect the address-string prefix
-- using LPeg patterns rather than `string.match` (per the LPeg discipline).

-- Extract the first-octet digit run from an IPv4 string: pattern matches
-- 1–3 digits up to (but not consuming) the first dot.
local _ipv4_first_octet = C(R("09") * R("09") ^ -2) * P(".")
local function is_ipv4_multicast(addr)
  local o1_str = _ipv4_first_octet:match(addr)
  if not o1_str then return false end
  local n = tonumber(o1_str)
  return n ~= nil and n >= 224 and n <= 239  -- RFC 1112 / RFC 5771
end

-- IPv6 multicast: first 8 bits are 0xff (RFC 4291 §2.7). Two ASCII chars,
-- case-insensitive.
local _ipv6_mcast_prefix = S("fF") * S("fF")
local function is_ipv6_multicast(addr)
  return _ipv6_mcast_prefix:match(addr) ~= nil
end

return {
  ipv4_raw           = ipv4_raw,
  ipv4               = ipv4,
  ipv6               = ipv6,
  is_ipv4_multicast  = is_ipv4_multicast,
  is_ipv6_multicast  = is_ipv6_multicast,
}
