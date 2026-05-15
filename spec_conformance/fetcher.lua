-- Downloads a pinned path from a GitHub source into a local cache.
-- Uses curl via os.execute; no Lua HTTP dependency.

local M = {}

local CACHE_DIR = "spec_conformance/.cache"

local function shellescape(s) return "'" .. s:gsub("'", [['\'']]) .. "'" end

local function ensure_dir(path)
  os.execute("mkdir -p " .. shellescape(path))
end

local function cache_path_for(source, path)
  local key = source.repo:gsub("/", "_") .. "_" .. source.sha:sub(1, 12) .. "_" .. path:gsub("/", "_")
  return CACHE_DIR .. "/" .. key
end

local function file_exists(path)
  local f = io.open(path, "r")
  if not f then return false end
  f:close()
  return true
end

function M.fetch(source, path)
  ensure_dir(CACHE_DIR)
  local local_path = cache_path_for(source, path)
  if file_exists(local_path) then return local_path end

  local url = string.format("https://raw.githubusercontent.com/%s/%s/%s", source.repo, source.sha, path)
  local cmd = string.format("curl -fsSL --max-time 30 -o %s %s", shellescape(local_path), shellescape(url))
  local ok = os.execute(cmd)
  if not ok then
    os.remove(local_path)
    return nil, "download failed: " .. url
  end
  return local_path
end

function M.read(source, path)
  local local_path, err = M.fetch(source, path)
  if not local_path then return nil, err end
  local f, oerr = io.open(local_path, "r")
  if not f then return nil, oerr end
  local content = f:read("*a")
  f:close()
  return content
end

M.cache_dir = CACHE_DIR
return M
