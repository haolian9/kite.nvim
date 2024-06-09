local fs = require("infra.fs")
local its = require("infra.its")

local entfmt = require("kite.entfmt")
local facts = require("kite.facts")

local function filter_ent(fname, ftype)
  local _ = fname
  -- maybe: respects .gitignore
  return ftype == "file" or ftype == "directory"
end

local function format_ent(fname, ftype)
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
    :filtern(filter_ent)
    :slice(1, facts.max_children + 1)
    :mapn(format_ent)
    :tolist()
end
