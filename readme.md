a toy file picker for nvim

https://github.com/haolian9/zongzi/assets/6236829/1ce73de9-b494-4677-ac43-c0852a8485fe


## design choices, features, limits
* uses floating windows by default
* floatwins are relatived to cursor position and have proper width
* intuitive yet opinionated keymaps
* employs only one buffer
* no support `$ vi dir`, `:e dir`, `augroup FileExplorer`

## non-goals
* be a sidebar, persistent or not
* filesystem manipulations
* git integration
* icons

## status
* just works

## prerequisites
* linux
* nvim 0.10.*
* haolian9/infra.nvim
* haolian9/beckon.nvim

## usage
* `:lua require'kite'.fly()`
* my personal config
```
do --kite
  local g = G("kite")
  g.max_entries_per_dir = 999

  m.n("-", function() require("kite").fly() end)
  m.n("_", function() require("kite").land() end)
  m.n("[k", function() require("kite").open_sibling_file("prev") end)
  m.n("]k", function() require("kite").open_sibling_file("next") end)

  do --:Kite
    local function root_comp(prompt) return vim.fn.getcompletion(prompt, "dir", false) end

    local spell = cmds.Spell("Kite", function(args)
      local open_mode, root = "inplace", nil
      for k, v in pairs(args) do
        if k == "root" then root = v end
        if k ~= "root" then open_mode = k end
      end
      if root ~= nil then root = fs.abspath(root) end
      require("kite").land(root, open_mode)
    end)

    --stylua: ignore
    do
      spell:add_flag("inplace", "true", false)
      spell:add_flag("tab",     "true", false)
      spell:add_flag("left",    "true", false)
      spell:add_flag("right",   "true", false)
      spell:add_flag("above",   "true", false)
      spell:add_flag("below",   "true", false)
    end
    spell:add_arg("root", "string", false, ".", root_comp)

    cmds.cast(spell)
  end
end
```

## keymaps bound to Kite buffer/window
* h/l:       goto parent/child dir
* j/k:       up/down cursor
* <cr>,gf,i: file, edit; dir, cd in
* o:         file, split below; dir, cd in
* t:         file, tabedit; dir, cd in
* v,<c-/>:   file, split right; dir, cd in
* -:         goto parent dir
* r:         reload entries of the current dir
* /:         select an entry using beckon.select, respecting o/t/v/i keymaps
* q,<c-[>:   close Kite window

## thanks
* vim-dirvish which inspired me to roll my own one.
