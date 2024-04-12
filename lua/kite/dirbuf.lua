local M = {}

local buflines = require("infra.buflines")
local bufrename = require("infra.bufrename")
local dictlib = require("infra.dictlib")
local Ephemeral = require("infra.Ephemeral")
local fs = require("infra.fs")
local bufmap = require("infra.keymap.buffer")
local prefer = require("infra.prefer")

local facts = require("kite.facts")
local state = require("kite.state")

local api = vim.api

function M.geometry(root)
  local width = math.max(30, math.min(state.widest(root) + 4, 50))
  local height = math.min(math.floor(vim.go.lines * 0.9), math.max(1, #state.entries(root)))
  -- no cursor jumping
  local row = -(state.cursor_line(root) or 2)
  return { width = width, height = height, row = row, col = 0 }
end

---@param root string @absolute path
---@param anchor_winid integer
---@return integer @bufnr
function M.new(root, anchor_winid)
  local bufnr
  -- buf init
  do
    bufnr = Ephemeral({ handyclose = true })
    api.nvim_buf_set_var(bufnr, facts.totem, true)
    api.nvim_buf_set_var(bufnr, "kite_root", root)
    api.nvim_buf_set_var(bufnr, "kite_anchor_winid", anchor_winid)
    prefer.bo(bufnr, "filetype", "kite")
  end

  -- buf keymap
  do
    local function rhs_open(open_cmd)
      return function() require("kite").rhs_open(bufnr, open_cmd) end
    end
    local function rhs_parent() return require("kite").rhs_parent(bufnr) end
    local bm = bufmap.wraps(bufnr)
    bm.n("<cr>", rhs_open("e"))
    bm.n("gf", rhs_open("e"))
    bm.n("i", rhs_open("e"))
    bm.n("o", rhs_open("sp"))
    bm.n("t", rhs_open("tabe"))
    bm.n("v", rhs_open("vs"))
    bm.n("<c-/>", rhs_open("vs"))
    bm.n("h", rhs_parent)
    bm.n("l", function() require("kite").rhs_open_dir(bufnr) end)
    bm.n("-", rhs_parent)
    bm.n("r", function() require("kite").rhs_refresh(bufnr) end)
    bm.n("<c-g>", function() require("kite").rhs_bufdir_stats(bufnr) end)
  end

  return bufnr
end

---@param winid number
---@param bufnr number
---@param root string @absolute path
---@param resize boolean
function M.refresh(winid, bufnr, root, resize)
  assert(winid ~= nil and bufnr ~= nil and root ~= nil and resize ~= nil)

  -- for cursor_line bounds check
  local entries_count = 0

  do -- buf
    bufrename(bufnr, string.format("kite://%s", fs.basename(root)))
    api.nvim_buf_set_var(bufnr, "kite_root", root)
    local entries = state.entries(root)
    local bo = prefer.buf(bufnr)
    --todo: use ctx.modifiable instead?
    bo.modifiable = true
    buflines.replaces_all(bufnr, entries)
    bo.modifiable = false
    entries_count = #entries
  end

  do -- win
    if resize then
      local winopts = dictlib.merged({ relative = "cursor" }, M.geometry(root))
      --win_set_config needs an anchor: https://github.com/neovim/neovim/issues/24129
      api.nvim_win_call(M.kite_anchor_winid(bufnr), function() api.nvim_win_set_config(winid, winopts) end)
    end
    local cursor_line
    do
      cursor_line = state.cursor_line(root)
      if cursor_line == nil then
        -- fresh load
        cursor_line = 1
      elseif entries_count == 0 then
        -- empty dir
        cursor_line = 1
      elseif cursor_line > entries_count then
        -- last entry has been removed
        cursor_line = entries_count
      end
    end
    api.nvim_win_set_cursor(winid, { cursor_line, 0 })
  end
end

do
  local function is_valid_kite_buf(bufnr)
    if not api.nvim_buf_is_valid(bufnr) then return false end
    if vim.b[bufnr][facts.totem] == nil then return false end
    return true
  end

  ---@param bufnr integer
  ---@param name string
  ---@return any
  local function get_kite_var(bufnr, name)
    if not is_valid_kite_buf(bufnr) then error(string.format("not a valid kite buf, bufnr=%d", bufnr)) end
    local val = api.nvim_buf_get_var(bufnr, name)
    assert(val ~= nil)
    return val
  end

  function M.kite_root(bufnr) return tostring(get_kite_var(bufnr, "kite_root")) end

  ---@return integer
  function M.kite_anchor_winid(bufnr) return assert(tonumber(get_kite_var(bufnr, "kite_anchor_winid"))) end
end

return M
