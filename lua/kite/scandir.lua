local fs = require("infra.fs")
local its = require("infra.its")

local entfmt = require("kite.entfmt")

local function filter(fname, ftype)
  local _ = fname
  -- maybe: respects .gitignore
  return ftype == "file" or ftype == "directory"
end

local function format(fname, ftype)
  if ftype == "file" then
    return entfmt.file(fname)
  elseif ftype == "directory" then
    return entfmt.dir(fname)
  else
    error("unexpected file type: " .. ftype)
  end
end

--scan entities in the given dir, each entity will be formatted by the formatter
---@return string[]
return function(dir)
  return its(fs.iterdir(dir)) --
    :filtern(filter)
    :slice(1, 999 + 1)
    :mapn(format)
    :tolist()
end
