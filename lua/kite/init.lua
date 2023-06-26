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

local api = vim.api

local fs = require("infra.fs")
local ex = require("infra.ex")
local jelly = require("infra.jellyfish")("kite")
local strlib = require("infra.strlib")
local prefer = require("infra.prefer")
local bufmap = require("infra.keymap.buffer")
local dictlib = require("infra.dictlib")

local facts = require("kite.facts")
local state = require("kite.state")
local builder = require("kite.builder")
local formatter = require("kite.formatter")

--determine the root for kite of a regular buffer
---@param bufnr number
---@return string
local function buf_root(bufnr)
  local buftype = prefer.bo(bufnr, "buftype")
  if not (buftype == "" or buftype == "help") then error(string.format("not a regular/help buffer: buftype=%s", buftype)) end
  local name = api.nvim_buf_get_name(bufnr)
  if strlib.find(name, "://") ~= nil then error("not a regular buffer: protocol://") end
  return vim.fn.fnamemodify(name, ":p:h")
end

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
  builder:fill_skeleton(winid, kite_bufnr, root, need_resize)
end

-- show content of current buffer's parent dir in a floatwin
function M.fly()
  local bufnr = api.nvim_get_current_buf()
  local root = buf_root(bufnr)

  local kite_bufnr = builder:new_skeleton(root)

  local kite_win_id
  -- win init
  do
    local width, height, row, col = builder:geometry(root)
    -- stylua: ignore
    kite_win_id = api.nvim_open_win(kite_bufnr, true, {
      relative = "cursor", style = "minimal", border = "single",
      width = width, height = height, row = row, col = col,
    })
  end

  -- win setup
  do
    local wo = prefer.win(kite_win_id)
    wo.number = false
    wo.relativenumber = false
    api.nvim_win_set_hl_ns(kite_win_id, facts.ns)
  end

  -- win cleanup
  do
    api.nvim_create_autocmd("WinLeave", {
      callback = function()
        if api.nvim_win_is_valid(kite_win_id) then api.nvim_win_close(kite_win_id, true) end
      end,
    })
    local function close_win() api.nvim_win_close(kite_win_id, false) end
    local bm = bufmap.wraps(kite_bufnr)
    bm.n("q", close_win)
    bm.n("<c-[>", close_win)
  end

  builder:fill_skeleton(kite_win_id, kite_bufnr, root, false)
  -- update cursor only when kite fly from normal buffer
  do
    if prefer.bo(bufnr, "buftype") ~= "" then return end
    local basename = vim.fs.basename(api.nvim_buf_get_name(bufnr))
    local cursor_line = state:entry_index(state:entries(root), formatter.file(basename), 1)
    api.nvim_win_set_cursor(kite_win_id, { cursor_line, 0 })
  end
end

-- show content of root with kite in current window
---@param root string? @absolute dir
function M.land(root)
  if root == nil then root = vim.fn.expand("%:p:h") end

  local kite_bufnr = builder:new_skeleton(root)
  local kite_win_id = api.nvim_get_current_win()
  api.nvim_win_set_buf(kite_win_id, kite_bufnr)

  builder:fill_skeleton(kite_win_id, kite_bufnr, root, false)
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
  local parent = vim.fs.dirname(root)

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
  -- stylua: ignore
  if direction == 'next' then
    move_step = function(i) return i + 1 end
  elseif direction == 'prev' then
    move_step = function(i) return i - 1 end
  else
    error('unknown direction')
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
