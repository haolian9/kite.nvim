local fs = require("infra.fs")
local itertools = require("infra.itertools")

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
  local iter
  iter = fs.iterdir(dir)
  iter = itertools.filtern(filter_ent, iter)
  iter = itertools.slice(iter, 1, facts.max_children + 1)
  iter = itertools.mapn(format_ent, iter)

  return itertools.tolist(iter)
end
