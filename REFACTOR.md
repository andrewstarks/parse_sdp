# Refactor Catalogue — parse_sdp.lua

Issues identified during code review (2026-05-13).  Each entry names the
problem, gives exact line references, states the rule it violates, and
describes the fix.  Items are ordered: correctness first, then DRY, then
naming, then comments.

---

## R1 — `valid_hkep` silently discards the network address (correctness)

**Lines:** 696–716

```lua
local port_s, nettype, addrtype, _, node_id, port_id =
  value:match("^(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%S+)$")
```

The fourth capture — the actual host address — is thrown away with `_`.
`nettype` and `addrtype` are validated, but the address itself is never
checked.  Whether the address should be validated (it was left out deliberately
because TR-10-5 does not constrain it beyond "it is present") or not, the
code must say so explicitly.

**Fix:** replace `_` with a named variable `addr` and add a one-line comment
explaining that address-format validation is out of scope per TR-10-5 §10.

---

## R2 — `rtpmap_clock_rate` and `rtpmap_encoding` duplicate the same prefix match (DRY)

**Lines:** 398–410

```lua
local function rtpmap_clock_rate(value)
  local rest = value:match("^%d+%s+(.+)$")   -- ← duplicated
  if not rest then return nil end
  local rate = rest:match("^[^/]+/(%d+)")
  return rate and tonumber(rate)
end

local function rtpmap_encoding(value)
  local rest = value:match("^%d+%s+(.+)$")   -- ← duplicated
  if not rest then return nil end
  return rest:match("^([^/]+)")
end
```

Both functions perform the same initial `"^%d+%s+(.+)$"` match.  Both are
called together in every code path that cares about an rtpmap value.

**Fix:** replace both with a single `rtpmap_parse(value)` that returns
`encoding, clock_rate` (or `nil` if the value does not match).  Call sites
receive both values in one call.

---

## R3 — `fmtp_params` is called once per branch inside `st2110.validate` (DRY)

**Lines:** 570–641

The attribute `fmtp` is located before the `if enc == "smpte291"` chain, but
`fmtp_params(fmtp.value or "")` — including identical error-handling — is
repeated inside each of the four branches (smpte291, ST2110-41, video, audio).

**Fix:** call `fmtp_params` once, immediately after the `fmtp` nil-check, and
store the result.  Each branch then uses the already-parsed `params` table.

---

## R4 — DUP group iteration is duplicated between `st2110.validate` and `ipmx.validate` (DRY)

**Lines:** 644–683 (`st2110`) and 900–935 (`ipmx`)

Both sections:
1. Build a `mid → media-block` index by scanning `doc.media`.
2. Loop over `doc.session.attributes` looking for `group` entries.
3. For each `DUP` group, split the MID list and look each up in the index.

They differ only in what they check once the legs are collected (media type
consistency vs. privacy consistency).  The outer scaffolding is copied verbatim.

**Fix:** extract a module-level helper `each_dup_group(doc, callback)` that
builds the mid-index and calls `callback(legs)` for each DUP group found,
where `legs` is an array of `{ idx, block }` entries.  Each validator passes
its own check as the callback.  The mid-index build and MID-lookup error are
defined once.

---

## R5 — Error-table construction is verbose and repetitive (DRY)

**Lines:** throughout `st2110` (≈17 occurrences) and `ipmx` (≈8 occurrences)

The pattern:

```lua
return nil, errors.new("...", {
  field_path = mpath .. ".attributes[foo]",
  spec_ref   = "ST 2110-10 §7.x",
  code       = "INVALID_VALUE",
})
```

repeats roughly 25 times.  The only variation is message, mpath, attribute
name, spec_ref, and occasionally the error code.

**Fix:** add a module-level helper:

```lua
local function attr_err(msg, mpath, attr_name, spec_ref, code)
  return nil, errors.new(msg, {
    field_path = mpath .. ".attributes[" .. attr_name .. "]",
    spec_ref   = spec_ref,
    code       = code or "INVALID_VALUE",
  })
end
```

---

## R6 — Module entry points are named after their own module (naming)

**Lines:** 496, 778, 370, 266

| Current call | Module |
|---|---|
| `st2110.st2110(doc)` | `st2110` |
| `ipmx.ipmx(doc)` | `ipmx` |
| `serialize.serialize(doc)` | `serialize` |
| `validate.sdp(doc)` | `validate` |

The last one is fine — `sdp` names the tier, not the module.  The first three
have the module calling a function with its own name.

**Fix:** rename to `st2110.validate`, `ipmx.validate`, `serialize.to_sdp`.
Update all call sites (within the file and the `validators` dispatch table).

---

## R7 — M16/M17 milestone tags in code comments (comment rot)

**Lines:** 900, 937

```lua
-- M16: DUP group privacy consistency (TR-10-13 §13 lines 329/335).
-- M17: RTCP port convention (TR-10-1 §8.7) — IPMX only.
```

Milestone numbers are task/PR context.  They mean nothing to a future reader
and will rot.  The spec references (`TR-10-13 §13`, `TR-10-1 §8.7`) are
already present and sufficient.

**Fix:** drop the `M16:`/`M17:` prefix; keep the spec reference.

---

## R8 — Over-documented trivial pass-through grammar functions (comment bloat)

**Lines:** 146–169

`parse_session_name`, `parse_info`, `parse_uri`, `parse_email`, `parse_phone`
each carry a four-line ldoc block describing a function whose entire body is
`return s`.  The comments duplicate what the function name and signature already
say.

**Fix:** replace each four-line block with a single `-- Returns the raw string
unchanged.` comment, or drop the comment entirely.

---

## R9 — `check_privacy` is a closure defined inside `ipmx.validate` (clarity)

**Lines:** 876–890

`check_privacy` is a nested function but it closes over nothing — all inputs
arrive via explicit arguments.  Defining it inside `ipmx.validate` means it is
recreated on every call to `ipmx.validate` and cannot be tested or referenced
independently.

**Fix:** hoist it to module-level alongside the other `valid_*` helpers.

---
