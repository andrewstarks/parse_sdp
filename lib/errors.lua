local M = {}

-- Format an error table into a human-readable string.
-- Recognised fields: message, code, line, col, context, field_path, spec_ref.
function M.format(err)
  if not err then return "error: unknown" end

  local code_part = err.code and ("[" .. err.code .. "] ") or ""
  local out = { "error: " .. code_part .. (err.message or "unknown error") }

  if err.field_path and err.field_path ~= "" then
    out[#out + 1] = " --> field: " .. err.field_path
  elseif err.line and err.line > 0 then
    out[#out + 1] = string.format(" --> line %d, col %d", err.line, err.col or 1)
    if err.context and err.context ~= "" then
      local col = err.col or 1
      out[#out + 1] = "  |"
      out[#out + 1] = string.format("%2d | %s", err.line, err.context)
      out[#out + 1] = "   | " .. string.rep(" ", col - 1) .. "^"
    end
  end

  if err.spec_ref and err.spec_ref ~= "" then
    out[#out + 1] = "  = note: required by " .. err.spec_ref
  end

  return table.concat(out, "\n")
end

return M
