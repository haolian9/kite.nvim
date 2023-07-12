local M = {}

local api = vim.api

M.totem = "kite"
M.max_children = 499

do
  M.hl_ns = api.nvim_create_namespace("kite")
  api.nvim_set_hl(M.hl_ns, "NormalFloat", { ctermbg = 15, ctermfg = 8 })
  api.nvim_set_hl(M.hl_ns, "WinSeparator", { ctermfg = 243 })
end

return M
