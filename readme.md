a toy file picker for nvim

https://github.com/haolian9/zongzi/assets/6236829/1ce73de9-b494-4677-ac43-c0852a8485fe


## design choices, features, limits
* uses floating windows by default
* floatwins are relatived to cursor position and have proper width
* intuitive yet opinionated keymaps
* employs only one buffer

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

## keymaps bound to Kite window
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
