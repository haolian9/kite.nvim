local strlib = require("infra.strlib")
local fs = require("infra.fs")

--entity formatter
local M = {
  file = function(basename)
    assert(not vim.startswith(basename, "/"))
    return string.format("   %s", basename)
  end,
  dir = function(basename)
    assert(not vim.startswith(basename, "/"))
    return string.format("   %s%s", basename, fs.sep)
  end,
  strip = function(formatted)
    return strlib.lstrip(formatted, " ")
  end,
  is_dir = function(formatted)
    return vim.endswith(formatted, fs.sep)
  end,
}

return M
