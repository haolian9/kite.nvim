local strlib = require("infra.strlib")

--entity formatter
local M = {
  file = function(basename)
    assert(not strlib.startswith(basename, "/"))
    return string.format(" %s", basename)
  end,
  dir = function(basename)
    assert(not strlib.startswith(basename, "/"))
    return string.format(" %s%s", basename, "/")
  end,
  strip = function(formatted) return strlib.lstrip(formatted, " ") end,
  is_dir = function(formatted) return strlib.endswith(formatted, "/") end,
}

return M
