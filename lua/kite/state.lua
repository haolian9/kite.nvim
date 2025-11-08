local M = {}

local fs = require("infra.fs")
local its = require("infra.its")
local jelly = require("infra.jellyfish")("kite.state", "info")
local LRU = require("infra.LRU")
local ni = require("infra.ni")
local strlib = require("infra.strlib")

local entfmt = require("kite.entfmt")
local scandir = require("kite.scandir")

local cache = {}
do
  ---@private
  ---{root: {entries: [formatted-path], cursor_row: 0-based-int, widest: max(#entry)}}
  ---@type {[string]: {entries:string[]?, cursor_row:number?, widest:number?}}
  cache.lru = LRU(128)

  ---@param root string
  ---@param key 'entries'|'cursor_row'|'widest'
  function cache:get(root, key)
    local record = self.lru[root]
    if record == nil then return end
    return record[key]
  end

  ---@param root string
  ---@param key 'entries'|'cursor_row'|'widest'
  ---@param val string[]|number?
  function cache:set(root, key, val)
    if self.lru[root] == nil then self.lru[root] = {} end
    self.lru[root][key] = val
  end
end

function M.forget(root)
  cache:set(root, "entries", nil)
  cache:set(root, "cursor_row", nil)
  cache:set(root, "widest", nil)
end

---@param root string @abspath
---@return boolean
function M.entries_exist(root)
  assert(root ~= nil)
  return cache:get(root, "entries") == nil
end

---@return string[]
function M.entries(root)
  assert(root ~= nil)
  local entries = cache:get(root, "entries")

  if entries == nil then
    entries = scandir(root)
    cache:set(root, "entries", entries)
  end

  return entries
end

---@param root string
---@param newval number?
---@return number?
function M.cursor_row(root, newval)
  if newval == nil then return cache:get(root, "cursor_row") end
  cache:set(root, "cursor_row", newval)
end

--get the max entry-width of the root
---@param root string
---@return number
function M.widest(root)
  local known = cache:get(root, "widest")
  if known ~= nil then return known end

  local widest = its(M.entries(root)):map(ni.strwidth):max() or 0
  cache:set(root, "widest", widest)
  return widest
end

--get the given formatted entry's index the entries
---@param entries string[]
---@param formatted string
---@param default number
---@return number
function M.entry_index(entries, formatted, default)
  assert(default ~= nil and type(default) == "number")
  for key, val in ipairs(entries) do
    if val == formatted then return key end
  end
  if default ~= nil then return default end
  return jelly.fatal("NotFoundError", "entries=%s, formatted=%s, default=%s", entries, formatted, default)
end

do
  local function resolve_heading(from, to)
    if from == nil then return "lost" end
    if to == from then return "stay" end
    if strlib.startswith(to, from) then return "go_inside" end
    if strlib.startswith(from, to) then return "go_outside" end
    return "lost"
  end

  local function main(from, to)
    local heading = resolve_heading(from, to)
    if heading == "go_inside" then
      local outer, inner = from, to
      assert(outer)
      -- add trail outer->inner
      if M.cursor_row(outer) == nil then
        local inner_basename = fs.basename(inner)
        M.cursor_row(outer, M.entry_index(M.entries(outer), entfmt.dir(inner_basename), 1))
      end
      if M.cursor_row(inner) then return end
      M.cursor_row(inner, 1)
    elseif heading == "go_outside" then
      local outer, inner = to, from
      --NB: inner as an entry of outer, it should be focused always,
      --    no matter outer's cursor_row exists or not
      --
      --add trail inner->outer
      local inner_basename = fs.basename(assert(inner))
      M.cursor_row(outer, M.entry_index(M.entries(outer), entfmt.dir(inner_basename), 1))
    elseif heading == "lost" then
      if M.cursor_row(to) then return end
      M.cursor_row(to, 1)
    elseif heading == "stay" then
      if M.cursor_row(to) then return end
      M.cursor_row(to, 1)
    else
      error("unable to resolve trail")
    end
  end

  ---@param from string?
  ---@param to string
  function M.trail(from, to)
    main(from, to)
    assert(M.cursor_row(to), "trail() doesnt set cursor_row")
    assert(M.cursor_row(to) <= math.max(1, #M.entries(to)), "trail() resolves cursor_row wrong")
  end
end

function M.clear_cache() cache.lru = LRU(128) end

return M
