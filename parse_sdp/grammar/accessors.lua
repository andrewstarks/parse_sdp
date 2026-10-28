-- Read helpers over the doc shape. Shared by the grammar tiers and by
-- parse_sdp.grammar.codecs, which base.lua loads, so they live outside
-- base.lua to keep the require graph acyclic. base.lua re-exports them
-- (base.params_get / attr_get / attrs_get) and init.lua publishes them.

local M = {}

-- Look up a value in the ordered kv-list shape `a_fmtp` and `a_privacy`
-- capture (Ct of {key, value | true} sub-tables, input order preserved
-- for round-trip determinism). Returns nil when absent, the value when
-- present (string for k=v entries, true for bare flags).
function M.params_get(params, key)
  if params == nil then return nil end
  for i = 1, #params do
    local e = params[i]
    if e[1] == key then return e[2] end
  end
  return nil
end

-- Outer-attribute accessors over a block's ordered `attributes` array
-- (a `doc.session` or `doc.media[i]` table). Mirror params_get for the
-- attribute list: attr_get returns the first decomposed attribute whose
-- `name` matches (or nil); attrs_get returns all matches in document
-- order (empty table when none). nil-safe on the block / its attributes.
-- A malformed attribute (`malformed = true`, see base.malformed_attr) is
-- not decomposed, so neither accessor returns it.
function M.attr_get(block, name)
  local attrs = block and block.attributes
  if attrs == nil then return nil end
  for i = 1, #attrs do
    local a = attrs[i]
    if a.name == name and not a.malformed then return a end
  end
  return nil
end

function M.attrs_get(block, name)
  local out = {}
  local attrs = block and block.attributes
  if attrs == nil then return out end
  for i = 1, #attrs do
    local a = attrs[i]
    if a.name == name and not a.malformed then out[#out + 1] = a end
  end
  return out
end

return M
