--
-- design/features:
-- * refresh current root
-- * edit sibling file
-- * live rendering ~~dir buffer~~
-- * can be attached to current window
--
-- backlog
-- * proper cursor position
--   * change cursor: up to parent, down to child, open file
--

local M = {}

local bufopen = require("infra.bufopen")
local bufpath = require("infra.bufpath")
local fs = require("infra.fs")
local jelly = require("infra.jellyfish")("kite")
local ni = require("infra.ni")
local prefer = require("infra.prefer")
local repeats = require("infra.repeats")
local wincursor = require("infra.wincursor")

local entfmt = require("kite.entfmt")
local state = require("kite.state")
local UI = require("kite.UI")

do
  local function resolve_root(bufnr)
    if prefer.bo(bufnr, "buftype") == "help" then return fs.parent(ni.buf_get_name(bufnr)) end
    return bufpath.dir(bufnr, true)
  end

  --show the content of 'root' directory in a floatwin
  --NB: the current buffer should be either buftype={"",help}
  ---@param root? string @nil=bufpath.dir(current_buf)
  function M.fly(root)
    local anchor_winid = ni.get_current_win()
    local anchor_bufnr -- exclusive with root

    if root == nil then
      anchor_bufnr = ni.win_get_buf(anchor_winid)
      root = resolve_root(anchor_bufnr)
      if root == nil then return jelly.warn("cant resolve root dir of buf#%d", anchor_bufnr) end
    end

    local kite_winid = UI(anchor_winid, root)

    _ = (function() --- update cursor only when kite fly from normal buffer
      if anchor_bufnr == nil then return end
      local fpath = bufpath.file(anchor_bufnr)
      if fpath == nil then return end
      local basename = fs.basename(fpath)
      local cursor_row = state.entry_index(state.entries(root), entfmt.file(basename), 1)
      wincursor.g1(kite_winid, cursor_row, 0)
    end)()
  end
end

-- show content of root with kite in current window
---@param root string? @absolute dir
---@param open_mode infra.bufopen.Mode? @nil=inplace
function M.land(root, open_mode)
  if root == nil then root = vim.fn.expand("%:p:h") end
  if open_mode == nil then open_mode = "inplace" end
  local anchor_winid = ni.get_current_win()

  UI(anchor_winid, root, function(bufnr)
    bufopen(open_mode, bufnr)
    return ni.get_current_win()
  end)
end

-- made for operations which require a headless kite
---@param direction 'prev'|'next'
---@param open_mode? infra.bufopen.Mode
function M.open_sibling_file(direction, open_mode)
  direction = direction or "next"
  open_mode = open_mode or "inplace"

  repeats.remember_paren(function() M.open_sibling_file("next", "inplace") end, function() M.open_sibling_file("prev", "inplace") end)

  local move_step
  if direction == "next" then
    move_step = function(i) return i + 1 end
  elseif direction == "prev" then
    move_step = function(i) return i - 1 end
  else
    error("unknown direction")
  end

  local root = vim.fn.expand("%:p:h")

  local sibling_cursor_row, sibling_fpath
  do
    local cursor_row = state.cursor_row(root) or 1
    local entries = state.entries(root)
    assert(cursor_row >= 1 and cursor_row <= #entries)
    local step = cursor_row
    while true do
      step = move_step(step)
      local entry = entries[step]
      if entry == nil then break end
      if not entfmt.is_dir(entry) then
        sibling_cursor_row = step
        sibling_fpath = fs.joinpath(root, entfmt.strip(entry))
        break
      end
    end

    if sibling_cursor_row == nil then return jelly.info("reached last/first sibling file") end
  end

  state.cursor_row(root, sibling_cursor_row)
  bufopen(open_mode, sibling_fpath)
end

M.clear_cache = state.clear_cache

return M
