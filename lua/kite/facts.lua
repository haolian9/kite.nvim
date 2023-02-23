local api = vim.api

local ns
do
  ns = api.nvim_create_namespace("kite")
  api.nvim_set_hl(ns, "NormalFloat", { ctermbg = 15, ctermfg = 8 })
  api.nvim_set_hl(ns, "WinSeparator", { ctermfg = 243 })
end

return {
  totem = "kite",
  max_children = 499,
  ns = ns,
}
