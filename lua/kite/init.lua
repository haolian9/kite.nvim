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

local buflines = require("infra.buflines")
local bufpath = require("infra.bufpath")
local wincursor = require("infra.wincursor")
local dictlib = require("infra.dictlib")
local ex = require("infra.ex")
local fs = require("infra.fs")
local jelly = require("infra.jellyfish")("kite")
local prefer = require("infra.prefer")
local rifts = require("infra.rifts")

local dirbuf = require("kite.dirbuf")
local entfmt = require("kite.entfmt")
local state = require("kite.state")

local api = vim.api

do
  local function resolve_root(bufnr)
    if prefer.bo(bufnr, "buftype") == "help" then return fs.parent(api.nvim_buf_get_name(bufnr)) end
    return bufpath.dir(bufnr, true)
  end

  --show the content of 'root' directory in a floatwin
  --NB: the current buffer should be either buftype={"",help}
  ---@param root? string @nil=bufpath.dir(current_buf)
  function M.fly(root)
    local anchor_winid = api.nvim_get_current_win()
    local anchor_bufnr -- exclusive with root

    if root == nil then
      anchor_bufnr = api.nvim_win_get_buf(anchor_winid)
      root = resolve_root(anchor_bufnr)
      if root == nil then return jelly.warn("cant resolve root dir of buf#%d", anchor_bufnr) end
    end

    local kite_bufnr = dirbuf.new(root, anchor_winid)

    local kite_winid
    do
      local winopts = dictlib.merged({ relative = "cursor", border = "single" }, dirbuf.geometry(root))
      kite_winid = rifts.open.win(kite_bufnr, true, winopts)

      local wo = prefer.win(kite_winid)
      wo.number = false
      wo.relativenumber = false
      api.nvim_win_set_hl_ns(kite_winid, rifts.ns)
      --intended to have no auto-close on winleave
    end

    dirbuf.refresh(kite_winid, kite_bufnr, root, false)

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
function M.land(root)
  if root == nil then root = vim.fn.expand("%:p:h") end
  local anchor_winid = api.nvim_get_current_win()

  local kite_bufnr = dirbuf.new(root, anchor_winid)
  local kite_winid = api.nvim_get_current_win()
  api.nvim_win_set_buf(kite_winid, kite_bufnr)

  dirbuf.refresh(kite_winid, kite_bufnr, root, false)
end

do --rhs
  local function is_landed_kite_win(winid) return api.nvim_win_get_config(winid).relative == "" end

  local function edit_file(kite_winid, path, win_open_cmd)
    assert(win_open_cmd)

    ---no closing kite win when the kite buffer is
    ---* not bound to any window
    ---* bound to a landed window
    if kite_winid and not is_landed_kite_win(kite_winid) then api.nvim_win_close(kite_winid, false) end

    ex(win_open_cmd, path)
  end

  local function cd(winid, kite_bufnr, root)
    local path_from = dirbuf.kite_root(kite_bufnr)
    state.trail_behind(root, path_from)

    local need_resize = not is_landed_kite_win(winid)
    dirbuf.refresh(winid, kite_bufnr, root, need_resize)
  end

  -- open child file or dir selected from kite buffer
  function M.rhs_open(bufnr, win_open_cmd)
    bufnr = bufnr or api.nvim_get_current_buf()
    win_open_cmd = win_open_cmd or "e"

    local kite_winid = api.nvim_get_current_win()
    local root = dirbuf.kite_root(bufnr)

    local cursor = wincursor.position(kite_winid)

    local fname = entfmt.strip(buflines.line(bufnr, cursor.lnum))
    if fname == "" then return jelly.warn("no file found at the cursor line") end

    local path_to = fs.joinpath(root, fname)

    state.cursor_row(root, cursor.row)

    if entfmt.is_dir(fname) then
      jelly.debug("kite cd %s", path_to)
      cd(kite_winid, bufnr, path_to)
    else
      jelly.debug("%s %s", win_open_cmd, path_to)
      edit_file(kite_winid, path_to, win_open_cmd)
    end
  end

  -- goto child dir
  function M.rhs_open_dir(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()

    local kite_winid = api.nvim_get_current_win()
    local root = dirbuf.kite_root(bufnr)

    local cursor = wincursor.position(kite_winid)

    local fname = entfmt.strip(buflines.line(bufnr, cursor.lnum))
    if fname == "" then return end

    if not entfmt.is_dir(fname) then return end

    state.cursor_row(root, cursor.row)

    local path_to = fs.joinpath(root, fname)
    cd(kite_winid, bufnr, path_to)
  end

  -- goto parent dir, made for keymap
  function M.rhs_parent(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()

    local kite_winid = api.nvim_get_current_win()
    local root = dirbuf.kite_root(bufnr)
    local parent = fs.parent(root)

    state.cursor_row(root, wincursor.row(kite_winid))

    cd(kite_winid, bufnr, parent)
  end

  -- made for operations which require a headless kite
  function M.rhs_open_sibling_file(direction, win_open_cmd)
    direction = direction or "next"
    win_open_cmd = win_open_cmd or "e"

    local move_step
    if direction == "next" then
      move_step = function(i) return i + 1 end
    elseif direction == "prev" then
      move_step = function(i) return i - 1 end
    else
      error("unknown direction")
    end

    local root = vim.fn.expand("%:p:h")

    local sibling_cursor_row
    local sibling_fpath
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
    edit_file(nil, sibling_fpath, win_open_cmd)
  end

  function M.rhs_refresh(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()

    local kite_winid = api.nvim_get_current_win()
    local root = dirbuf.kite_root(bufnr)

    state.forget_entries(root)
    cd(kite_winid, bufnr, root)
  end

  function M.rhs_bufdir_stats(bufnr)
    local root = dirbuf.kite_root(bufnr)
    local entries = state.entries(root)
    jelly.info('"%s" %s entries', root, #entries)
  end
end

M.clear_cache = state.clear_cache

return M
