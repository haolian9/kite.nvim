--ui builder
local M = {}

local api = vim.api

local bufrename = require("infra.bufrename")

local facts = require("kite.facts")
local state = require("kite.state")

function M:dimensions(root)
  local width = math.max(30, math.min(state:widest(root) + 4, 50))
  -- 1 plus for winbar
  local height = math.min(math.floor(vim.o.lines * 0.9), math.max(2, #state:entries(root) + 1))
  return width, height, 1, 0
end

function M:new_skeleton(root)
  local bufnr
  -- buf init
  do
    bufnr = api.nvim_create_buf(false, true)
    api.nvim_buf_set_var(bufnr, facts.totem, true)
    api.nvim_buf_set_var(bufnr, "kite_root", root)
    api.nvim_buf_set_option(bufnr, "bufhidden", "wipe")
    api.nvim_buf_set_option(bufnr, "filetype", "kite")
  end

  -- buf keymap
  do
    local function rhs_open(open_cmd)
      return string.format([[<cmd>lua require'kite'.rhs_open(%d, '%s')<cr>]], bufnr, open_cmd)
    end
    local rhs_parent = string.format([[<cmd>lua require'kite'.rhs_parent(%d)<cr>]], bufnr)
    api.nvim_buf_set_keymap(bufnr, "n", [[<cr>]], rhs_open("e"), { noremap = true })
    api.nvim_buf_set_keymap(bufnr, "n", "gf", rhs_open("e"), { noremap = true })
    api.nvim_buf_set_keymap(bufnr, "n", "i", rhs_open("e"), { noremap = true })
    api.nvim_buf_set_keymap(bufnr, "n", "o", rhs_open("sp"), { noremap = true })
    api.nvim_buf_set_keymap(bufnr, "n", "t", rhs_open("tabe"), { noremap = true })
    api.nvim_buf_set_keymap(bufnr, "n", "v", rhs_open("vs"), { noremap = true })
    api.nvim_buf_set_keymap(bufnr, "n", [[<c-/>]], rhs_open("vs"), { noremap = true })
    api.nvim_buf_set_keymap(bufnr, "n", "h", rhs_parent, { noremap = true })
    api.nvim_buf_set_keymap(bufnr, "n", "l", string.format([[<cmd>lua require'kite'.rhs_open_dir(%d)<cr>]], bufnr), { noremap = true })
    api.nvim_buf_set_keymap(bufnr, "n", "-", rhs_parent, { noremap = true })
    api.nvim_buf_set_keymap(bufnr, "n", "r", string.format([[<cmd>lua require'kite'.rhs_refresh(%d)<cr>]], bufnr), { noremap = true })
  end

  return bufnr
end

---@param win_id number
---@param bufnr number
---@param root string @absolute path
---@param resize boolean
function M:fill_skeleton(win_id, bufnr, root, resize)
  assert(win_id ~= nil and bufnr ~= nil and root ~= nil and resize ~= nil)

  -- for cursor_line bounds check
  local entries_count = 0

  -- buf
  do
    bufrename(bufnr, string.format("kite://%s", vim.fs.basename(root)))
    api.nvim_buf_set_var(bufnr, "kite_root", root)
    local entries = state:entries(root)
    api.nvim_buf_set_option(bufnr, "modifiable", true)
    api.nvim_buf_set_lines(bufnr, 0, -1, false, entries)
    api.nvim_buf_set_option(bufnr, "modifiable", false)
    entries_count = #entries
  end

  -- win
  do
    if resize then
      local width, height = self:dimensions(root)
      api.nvim_win_set_width(win_id, width)
      api.nvim_win_set_height(win_id, height)
    end
    api.nvim_win_set_option(win_id, "winbar", root)
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
    api.nvim_win_set_cursor(win_id, { cursor_line, 0 })
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
