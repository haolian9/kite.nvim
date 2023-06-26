--ui builder
local M = {}

local bufrename = require("infra.bufrename")
local prefer = require("infra.prefer")
local bufmap = require("infra.keymap.buffer")

local api = vim.api

local facts = require("kite.facts")
local state = require("kite.state")

function M:geometry(root)
  local width = math.max(30, math.min(state:widest(root) + 4, 50))
  -- 1 for winbar
  local height = math.min(math.floor(vim.go.lines * 0.9), math.max(2, #state:entries(root) + 1))
  -- no cursor jumping
  local row = -(state:cursor_line(root) or 2)
  return width, height, row, 0
end

function M:new_skeleton(root)
  local bufnr
  -- buf init
  do
    bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_var(bufnr, facts.totem, true)
    api.nvim_buf_set_var(bufnr, "kite_root", root)
    prefer.bo(bufnr, "bufhidden", "wipe")
    prefer.bo(bufnr, "filetype", "kite")
  end

  -- buf keymap
  do
    local function rhs_open(open_cmd)
      return function() require("kite").rhs_open(bufnr, open_cmd) end
    end
    local function rhs_parent() return require("kite").rhs_parent(bufnr) end
    local bm = bufmap.wraps(bufnr)
    bm.n([[<cr>]], rhs_open("e"))
    bm.n("gf", rhs_open("e"))
    bm.n("i", rhs_open("e"))
    bm.n("o", rhs_open("sp"))
    bm.n("t", rhs_open("tabe"))
    bm.n("v", rhs_open("vs"))
    bm.n([[<c-/>]], rhs_open("vs"))
    bm.n("h", rhs_parent)
    bm.n("l", function() require("kite").rhs_open_dir(bufnr) end)
    bm.n("-", rhs_parent)
    bm.n("r", function() require("kite").rhs_refresh(bufnr) end)
  end

  return bufnr
end

---@param winid number
---@param bufnr number
---@param root string @absolute path
---@param resize boolean
function M:fill_skeleton(winid, bufnr, root, resize)
  assert(winid ~= nil and bufnr ~= nil and root ~= nil and resize ~= nil)

  -- for cursor_line bounds check
  local entries_count = 0

  -- buf
  do
    bufrename(bufnr, string.format("kite://%s", vim.fs.basename(root)))
    api.nvim_buf_set_var(bufnr, "kite_root", root)
    local entries = state:entries(root)
    local bo = prefer.buf(bufnr)
    bo.modifiable = true
    api.nvim_buf_set_lines(bufnr, 0, -1, false, entries)
    bo.modifiable = false
    entries_count = #entries
  end

  -- win
  do
    if resize then
      if true then
        local width, height = self:geometry(root)
        api.nvim_win_set_width(winid, width)
        api.nvim_win_set_height(winid, height)
      else
        ---todo: await https://github.com/neovim/neovim/issues/24129
        ---also nvim_set_config will clear all the previous setting of the window
        local width, height, row, col = self:geometry(root)
        assert(api.nvim_win_get_config(winid).relative ~= "", "should be floating window")
        -- stylua: ignore
        api.nvim_win_set_config(winid, {
        relative = "cursor",
        width = width, height = height, row = row, col = col })
      end
    end
    prefer.wo(winid, "winbar", root)
    local cursor_line
    do
      cursor_line = state:cursor_line(root)
      if cursor_line == nil then
        -- fresh load
        cursor_line = 1
      elseif cursor_line > entries_count then
        -- last entry has been removed
        cursor_line = entries_count
      end
    end
    api.nvim_win_set_cursor(winid, { cursor_line, 0 })
  end
end

local function is_valid_kite_buf(bufnr)
  if not api.nvim_buf_is_valid(bufnr) then return false end
  if vim.b[bufnr][facts.totem] == nil then return false end
  return true
end

---@param bufnr number
---@return string
function M.kite_root(bufnr)
  if not is_valid_kite_buf(bufnr) then error(string.format("not a valid kite buf, bufnr=%d", bufnr)) end
  local root = vim.b[bufnr]["kite_root"]
  assert(root ~= nil and root ~= "")
  return root
end

return M
