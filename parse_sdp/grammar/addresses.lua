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

-- ── Address arithmetic + canonicalization ───────────────────────────────
-- Supports the RFC 4570 §3.1 source-filter cross-check (Phase 10.A.0.5).
-- RFC 8866 §5.7: multicast c= addresses with a `/<numaddr>` suffix
-- describe `<numaddr>` contiguously allocated addresses above the base.
-- The cross-check expands each c= entry into the full list of described
-- addresses before comparing against source-filter dests.

local function ipv4_to_int(addr)
  local a, b, c, d = addr:match("^(%d+)%.(%d+)%.(%d+)%.(%d+)$")
  if not a then return nil end
  return (tonumber(a) * 0x1000000) + (tonumber(b) * 0x10000)
       + (tonumber(c) * 0x100)     + tonumber(d)
end

local function int_to_ipv4(n)
  return string.format("%d.%d.%d.%d",
    (n >> 24) & 0xff, (n >> 16) & 0xff,
    (n >> 8)  & 0xff,  n        & 0xff)
end

-- Parse an IPv6 textual address into 8 16-bit groups; expand "::" if
-- present. Returns nil on malformed input — callers fall back to the
-- literal string for cross-check membership (degrading gracefully).
local function ipv6_to_groups(addr)
  local lo = addr:lower()
  if lo == "::" then return { 0, 0, 0, 0, 0, 0, 0, 0 } end
  local dc = lo:find("::", 1, true)
  local left, right
  if dc then
    left  = lo:sub(1, dc - 1)
    right = lo:sub(dc + 2)
  else
    left, right = lo, ""
  end
  local function split(s)
    local out = {}
    if s == "" then return out end
    for tok in (s .. ":"):gmatch("([^:]*):") do
      out[#out + 1] = tok
    end
    return out
  end
  local lg, rg = split(left), split(right)
  if #lg + #rg > 8 then return nil end
  if not dc and #lg + #rg ~= 8 then return nil end
  local groups = {}
  for _, g in ipairs(lg) do
    local n = tonumber(g, 16)
    if not n or n < 0 or n > 0xffff then return nil end
    groups[#groups + 1] = n
  end
  for _ = 1, 8 - (#lg + #rg) do groups[#groups + 1] = 0 end
  for _, g in ipairs(rg) do
    local n = tonumber(g, 16)
    if not n or n < 0 or n > 0xffff then return nil end
    groups[#groups + 1] = n
  end
  if #groups ~= 8 then return nil end
  return groups
end

local function ipv6_canonical(groups)
  return string.format("%04x:%04x:%04x:%04x:%04x:%04x:%04x:%04x",
    groups[1], groups[2], groups[3], groups[4],
    groups[5], groups[6], groups[7], groups[8])
end

-- Add a small non-negative integer to an IPv6 group vector, with carry
-- propagating from the low-order group up. Used to enumerate the
-- `<base>/<numaddr>` range for cross-check membership.
local function ipv6_add(groups, n)
  local g = { groups[1], groups[2], groups[3], groups[4],
              groups[5], groups[6], groups[7], groups[8] }
  local carry = n
  for i = 8, 1, -1 do
    local v = g[i] + carry
    g[i] = v & 0xffff
    carry = v >> 16
    if carry == 0 then break end
  end
  return g
end

-- Expand a c= entry into a canonical-form address list per RFC 8866 §5.7
-- "multicast addresses so assigned are contiguously allocated above the
-- base address". Returns { addr_type, [addr1, addr2, ...] } where each
-- addrN is in canonical form (matching canonicalize() output). For
-- unparseable addresses (which the dedicated value-form check rejects
-- upstream) returns a single-entry list with the literal so the cross-
-- check degrades gracefully.
local function expand_connection(addr_type, addr_value)
  local out = { addr_type = addr_type }
  if addr_type == "IP4" then
    -- `<base>/<ttl>/<numaddr>` or `<base>/<ttl>` or bare `<base>`.
    local base, _ttl, num = addr_value:match("^([%d%.]+)/(%d+)/(%d+)$")
    if not base then
      base, _ttl = addr_value:match("^([%d%.]+)/(%d+)$")
      num = nil
    end
    if not base then base = addr_value end
    local base_n = ipv4_to_int(base)
    if not base_n then
      out[1] = base
      return out
    end
    local count = tonumber(num) or 1
    for i = 0, count - 1 do
      out[#out + 1] = int_to_ipv4(base_n + i)
    end
    return out
  elseif addr_type == "IP6" then
    -- `<base>/<numaddr>` or bare `<base>` (no TTL on IPv6 per §5.7).
    local base, num = addr_value:match("^([^/]+)/(%d+)$")
    if not base then base = addr_value end
    local groups = ipv6_to_groups(base)
    if not groups then
      out[1] = base:lower()
      return out
    end
    local count = tonumber(num) or 1
    for i = 0, count - 1 do
      out[#out + 1] = ipv6_canonical(ipv6_add(groups, i))
    end
    return out
  end
  -- Other addr_types (FQDN forms, "*") pass through verbatim.
  out[1] = addr_value
  return out
end

-- Normalize an address to the same canonical form `expand_connection`
-- emits, so source-filter dest membership is comparable string-to-string.
local function canonicalize(addr_type, addr)
  if addr_type == "IP4" then
    local n = ipv4_to_int(addr)
    return n and int_to_ipv4(n) or addr
  elseif addr_type == "IP6" then
    local g = ipv6_to_groups(addr)
    return g and ipv6_canonical(g) or addr:lower()
  end
  return addr
end

return {
  ipv4_raw            = ipv4_raw,
  ipv4                = ipv4,
  ipv6                = ipv6,
  is_ipv4_multicast   = is_ipv4_multicast,
  is_ipv6_multicast   = is_ipv6_multicast,
  expand_connection   = expand_connection,
  canonicalize        = canonicalize,
}
