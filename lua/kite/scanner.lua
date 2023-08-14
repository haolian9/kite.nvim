local fn = require("infra.fn")
local fs = require("infra.fs")
local jelly = require("infra.jellyfish")("kite.scanner")

local facts = require("kite.facts")
local formatter = require("kite.formatter")

local function filter_ent(fname, ftype)
  local _ = fname
  if not (ftype == "file" or ftype == "directory") then return false end
  -- maybe: respects .gitignore
  return true
end

local function format_ent(fname, ftype)
  if ftype == "file" then
    return formatter.file(fname)
  elseif ftype == "directory" then
    return formatter.dir(fname)
  else
    error("unexpected file type: " .. ftype)
  end
end

--scan entities in the given dir, each entity will be formatted by the formatter
---@return string[]
return function(dir)
  local iter
  iter = fs.iterdir(dir, true)
  iter = fn.filtern(filter_ent, iter)
  iter = fn.slice(iter, 1, facts.max_children + 1)
  iter = fn.mapn(format_ent, iter)

  return fn.tolist(iter)
end
