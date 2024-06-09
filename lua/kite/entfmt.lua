local M = {}

local strlib = require("infra.strlib")

function M.file(basename)
  assert(not strlib.startswith(basename, "/"))
  return string.format(" %s", basename)
end

function M.dir(basename)
  assert(not strlib.startswith(basename, "/"))
  return string.format(" %s/", basename)
end

function M.strip(formatted) return strlib.lstrip(formatted, " ") end

function M.is_dir(formatted) return strlib.endswith(formatted, "/") end

return M
