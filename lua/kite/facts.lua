local M = {}

local highlighter = require("infra.highlighter")

local api = vim.api

M.totem = "kite"
M.max_children = 499

do
  M.hl_ns = api.nvim_create_namespace("kite")
  local hi = highlighter(M.hl_ns)
  if vim.go.background == "light" then
    hi("NormalFloat", { fg = 8 })
    hi("WinSeparator", { fg = 243 })
  else
    hi("NormalFloat", { fg = 7 })
    hi("WinSeparator", { fg = 243 })
  end
end

return M
