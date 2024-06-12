local fs = require("infra.fs")
local its = require("infra.its")
local jelly = require("infra.jellyfish")("kite.scandir", "debug")

local entfmt = require("kite.entfmt")
local g = require("kite.g")

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
    return jelly.fatal("ValueError", "unexpected ftype(%s) of %s", ftype, fname)
  end
end

--scan entities in the given dir, each entity will be formatted by the formatter
---@return string[]
return function(dir)
  return its(fs.iterdir(dir)) --
    :filtern(filter)
    :slicen(0, g.max_entries_per_dir)
    :mapn(format)
    :tolist()
end
