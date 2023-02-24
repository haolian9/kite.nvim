a file picker for nvim

## features
* uses floating windows
* the floatwin respects cursor position and sets proper width
* intuitive yet opinionated keymaps
* employs only one buffer

## non-goals
* sidebar
* filesystem modifications
* git integrations
* icons

## status: just works

## prerequisites
* linux
* nvim 0.8.*
* haolian9/infra.nvim

## usage
* `:lua require'kite'.fly()`

## keymaps bound to Kite window
* h/l:       cd out/in
* j/k:       up/down cursor
* <cr>,gf,i: edit
* o:         split
* t:         tabedit
* v,<c-/>:   vsplit
* -:         cd in parent dir
* r:         refresh entries of the current dir
* q,<c-[>:   close Kite window

## thanks
* vim-dirvish which inspired me to roll my own one.
