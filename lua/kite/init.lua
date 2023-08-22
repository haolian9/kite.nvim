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

local bufpath = require("infra.bufpath")
local dictlib = require("infra.dictlib")
local ex = require("infra.ex")
local fs = require("infra.fs")
local jelly = require("infra.jellyfish")("kite")
local prefer = require("infra.prefer")

local builder = require("kite.builder")
local facts = require("kite.facts")
local formatter = require("kite.formatter")
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
      local buftype = prefer.bo(anchor_bufnr, "buftype")
      assert(buftype == "" or buftype == "help")
      root = resolve_root(anchor_bufnr)
      if root == nil then return jelly.warn("cant resolve root dir of buf#%d", anchor_bufnr) end
    end

    local kite_bufnr = builder.new_skeleton(root, anchor_winid)

    local kite_winid
    do
      local winopts = dictlib.merged({ relative = "cursor", border = "single" }, builder.geometry(root))
      kite_winid = api.nvim_open_win(kite_bufnr, true, winopts)

      local wo = prefer.win(kite_winid)
      wo.number = false
      wo.relativenumber = false
      api.nvim_win_set_hl_ns(kite_winid, facts.hl_ns)
      --intended to have no auto-close on winleave
    end

    builder.fill_skeleton(kite_winid, kite_bufnr, root, false)

    _ = (function() --- update cursor only when kite fly from normal buffer
      if anchor_bufnr == nil then return end
      local fpath = bufpath.file(anchor_bufnr)
      if fpath == nil then return end
      local basename = fs.basename(fpath)
      local cursor_line = state:entry_index(state:entries(root), formatter.file(basename), 1)
      api.nvim_win_set_cursor(kite_winid, { cursor_line, 0 })
    end)()
  end
end

-- show content of root with kite in current window
---@param root string? @absolute dir
function M.land(root)
  if root == nil then root = vim.fn.expand("%:p:h") end
  local anchor_winid = api.nvim_get_current_win()

  local kite_bufnr = builder.new_skeleton(root, anchor_winid)
  local kite_win_id = api.nvim_get_current_win()
  api.nvim_win_set_buf(kite_win_id, kite_bufnr)

  builder.fill_skeleton(kite_win_id, kite_bufnr, root, false)
end

do --rhs
  local function is_landed_kite_win(winid) return api.nvim_win_get_config(winid).relative == "" end

  local function edit_file(kite_win_id, path, win_open_cmd)
    assert(win_open_cmd)

    -- close kite win when
    -- * kite buffer may not be showed in a window
    -- * landed kite window must not be closed
    if kite_win_id and not is_landed_kite_win(kite_win_id) then api.nvim_win_close(kite_win_id, false) end

    ex(win_open_cmd, path)
  end

  local function cd(winid, kite_bufnr, root)
    local path_from = builder.kite_root(kite_bufnr)
    state:trail_behind(root, path_from)

    local need_resize = not is_landed_kite_win(winid)
    builder.fill_skeleton(winid, kite_bufnr, root, need_resize)
  end
  -- open child file or dir selected from kite buffer
  function M.rhs_open(bufnr, win_open_cmd)
    bufnr = bufnr or api.nvim_get_current_buf()
    win_open_cmd = win_open_cmd or "e"

    local kite_win_id = api.nvim_get_current_win()
    local root = builder.kite_root(bufnr)

    local cursor_line, _ = unpack(api.nvim_win_get_cursor(kite_win_id))
    local fname
    do
      local lines = api.nvim_buf_get_lines(bufnr, cursor_line - 1, cursor_line, true)
      fname = formatter.strip(lines[1])
      if fname == "" then return jelly.warn("no file found at the cursor line") end
    end
    local path_to = fs.joinpath(root, fname)

    state:cursor_line(root, cursor_line)

    if formatter.is_dir(fname) then
      jelly.debug("kite cd %s", path_to)
      cd(kite_win_id, bufnr, path_to)
    else
      jelly.debug("%s %s", win_open_cmd, path_to)
      edit_file(kite_win_id, path_to, win_open_cmd)
    end
  end

  -- goto child dir
  function M.rhs_open_dir(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()

    local kite_win_id = api.nvim_get_current_win()
    local root = builder.kite_root(bufnr)

    local cursor_line, _ = unpack(api.nvim_win_get_cursor(kite_win_id))
    local fname
    do
      local lines = api.nvim_buf_get_lines(bufnr, cursor_line - 1, cursor_line, true)
      fname = formatter.strip(lines[1])
      if fname == "" then return end
    end

    if not formatter.is_dir(fname) then return end

    state:cursor_line(root, cursor_line)

    local path_to = fs.joinpath(root, fname)
    cd(kite_win_id, bufnr, path_to)
  end

  -- goto parent dir, made for keymap
  function M.rhs_parent(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()

    local kite_win_id = api.nvim_get_current_win()
    local root = builder.kite_root(bufnr)
    local parent = fs.parent(root)

    do
      local cursor_line, _ = unpack(api.nvim_win_get_cursor(kite_win_id))
      state:cursor_line(root, cursor_line)
    end

    cd(kite_win_id, bufnr, parent)
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

    local sibling_cursor_line
    local sibling_fpath
    do
      local cursor_line = state:cursor_line(root) or 1
      local entries = state:entries(root)
      assert(cursor_line >= 1 and cursor_line <= #entries)
      local step = cursor_line
      while true do
        step = move_step(step)
        local entry = entries[step]
        if entry == nil then break end
        if not formatter.is_dir(entry) then
          sibling_cursor_line = step
          sibling_fpath = fs.joinpath(root, formatter.strip(entry))
          break
        end
      end

      if sibling_cursor_line == nil then return jelly.info("reached last/first sibling file") end
    end

    state:cursor_line(root, sibling_cursor_line)
    edit_file(nil, sibling_fpath, win_open_cmd)
  end

  function M.rhs_refresh(bufnr)
    bufnr = bufnr or api.nvim_get_current_buf()

    local kite_win_id = api.nvim_get_current_win()
    local root = builder.kite_root(bufnr)

    state:forget_entries(root)
    cd(kite_win_id, bufnr, root)
  end
end

function M.clear_cache()
  local counts = {}
  local total = 0
  for root, cache in pairs(state.cache) do
    total = total + #cache.entries
    table.insert(counts, string.format("%s: %s", root, #cache.entries))
  end
  state.cache = dictlib.CappedDict(512)
  jelly.info("cleared cache: %d", total)
  jelly.info("cache details: %s", table.concat(counts, ", "))
end

return M
