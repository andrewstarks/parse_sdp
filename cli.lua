local sdp    = require("parse_sdp")
local dkjson = require("dkjson")

local function die(err_table)
  io.stderr:write(dkjson.encode(err_table) .. "\n")
  os.exit(1)
end

local function parse_flags(args)
  local opts = { mode = nil, pretty = false, file = nil }
  local i = 1
  while i <= #args do
    local a = args[i]
    if a == "--mode" then
      i = i + 1
      if not args[i] then
        die({ message = "--mode requires a value", line = 0, col = 0, context = "" })
      end
      opts.mode = args[i]
    elseif a == "--pretty" then
      opts.pretty = true
    elseif a:sub(1, 1) ~= "-" then
      opts.file = a
    else
      die({ message = "unknown flag: " .. a, line = 0, col = 0, context = "" })
    end
    i = i + 1
  end
  return opts
end

local subcommands = {}

function subcommands.parse(args)
  local opts = parse_flags(args)

  local text
  if opts.file then
    local f, err = io.open(opts.file, "r")
    if not f then
      die({ message = "cannot open file: " .. (err or opts.file), line = 0, col = 0, context = "" })
    end
    text = f:read("*a")
    f:close()
  else
    text = io.read("*a")
  end

  local doc, perr = sdp.parse(text, opts.mode)
  if not doc then
    die(perr)
  end

  local encode_opts = opts.pretty and { indent = true } or nil
  io.write(dkjson.encode(doc, encode_opts) .. "\n")
  os.exit(0)
end

-- ── Entry ─────────────────────────────────────────────────────────────────────

local cmd_name = arg and arg[1]
if not cmd_name then
  die({ message = "usage: parse_sdp <subcommand> [options] [file]", line = 0, col = 0, context = "" })
end

local sub_args = {}
for i = 2, #arg do
  sub_args[#sub_args + 1] = arg[i]
end

local fn = subcommands[cmd_name]
if not fn then
  die({ message = "unknown subcommand: " .. cmd_name, line = 0, col = 0, context = "" })
end

fn(sub_args)
