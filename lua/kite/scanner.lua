local fs = require("infra.fs")
local fn = require("infra.fn")

local facts = require("kite.facts")
local formatter = require("kite.formatter")

local jelly = require("infra.jellyfish")("kite.scanner")

--scan entities in the given dir, each entity will be formatted by the formatter
---@return string[]
return function(dir)
  local iter
  do
    local resolve_symlink = true
    local files = fn.filter(function(fname, ftype)
      local _ = fname
      if not (ftype == "file" or ftype == "directory") then return false end
      -- maybe: respects .gitignore
      return true
    end, fs.iterdir(dir, resolve_symlink))
    iter = fn.slice(files, 1, facts.max_children)
  end
  local entries = fn.concrete(fn.map(function(fname, ftype)
    if ftype == "file" then
      return formatter.file(fname)
    elseif ftype == "directory" then
      return formatter.dir(fname)
    else
      error("unexpected file type: " .. ftype)
    end
  end, iter))
  if iter() ~= nil then jelly.error("truncated result, just showed %d entries", facts.max_children) end
  return entries
end
