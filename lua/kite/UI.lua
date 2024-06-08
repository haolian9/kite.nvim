local buflines = require("infra.buflines")
local bufopen = require("infra.bufopen")
local bufrename = require("infra.bufrename")
local ctx = require("infra.ctx")
local dictlib = require("infra.dictlib")
local Ephemeral = require("infra.Ephemeral")
local fs = require("infra.fs")
local jelly = require("infra.jellyfish")("kite.ui", "info")
local bufmap = require("infra.keymap.buffer")
local prefer = require("infra.prefer")
local rifts = require("infra.rifts")
local wincursor = require("infra.wincursor")

local beckon_select = require("beckon.select")
local entfmt = require("kite.entfmt")
local state = require("kite.state")

local api = vim.api

local function is_landwin(winid) return api.nvim_win_get_config(winid).relative == "" end

local function resolve_geometry(root)
  local width = math.max(30, math.min(state.widest(root) + 4, 50))
  local height = math.min(math.floor(vim.go.lines * 0.9), math.max(1, #state.entries(root)))
  -- no cursor jumping
  local row = -(state.cursor_row(root) or 2)
  return { width = width, height = height, row = row, col = 0 }
end

---@param bufnr integer
---@param root string
---@return integer winid
local function default_open_win(bufnr, root)
  local winopts = dictlib.merged({ relative = "cursor", border = "single" }, resolve_geometry(root))
  local winid = rifts.open.win(bufnr, true, winopts)

  local wo = prefer.win(winid)
  wo.number = false
  wo.relativenumber = false
  api.nvim_win_set_hl_ns(winid, rifts.ns)
  --intended to have no auto-close on winleave

  return winid
end

local RHS
do
  ---@class kite.RHS
  ---@field bufnr integer
  ---@field root string @changes on every cd
  local Impl = {}
  Impl.__index = Impl

  do
    ---@param winid integer
    ---@param force? boolean
    ---@return boolean
    local function need_resize(winid, force)
      if is_landwin(winid) then return false end
      if force == nil then return false end
      return force
    end

    ---@private
    ---@param winid integer
    ---@param dest string
    function Impl:cd(winid, dest, force_resize)
      state.trail_behind(dest, self.root)

      do
        local entries = state.entries(dest)

        ctx.modifiable(self.bufnr, function() buflines.replaces_all(self.bufnr, entries) end)

        if self.root ~= dest then --
          bufrename(self.bufnr, string.format("kite://%s", fs.basename(dest)))
        end

        if need_resize(winid, force_resize) then --
          api.nvim_win_set_config(winid, resolve_geometry(dest))
        end

        do --cursor
          local cursor_row = state.cursor_row(dest)
          if cursor_row == nil then
            -- fresh load
            cursor_row = 1
          elseif #entries == 0 then
            -- empty dir
            cursor_row = 1
          elseif cursor_row > #entries then
            -- last entry has been removed
            cursor_row = #entries
          end

          wincursor.g1(winid, cursor_row, 0)
        end
      end

      self.root = dest
    end
  end

  do
    ---@param kite_winid? integer
    ---@param path string
    ---@param open_mode infra.bufopen.Mode
    local function edit_file(kite_winid, path, open_mode)
      ---no closing kite win when the kite buffer is
      ---* not bound to any window
      ---* bound to a landed window
      if kite_winid and not is_landwin(kite_winid) then api.nvim_win_close(kite_winid, false) end

      bufopen(open_mode, path)
    end

    ---open root/file or goto root/dir/
    ---@param open_mode? infra.bufopen.Mode
    function Impl:open(open_mode)
      local kite_winid = api.nvim_get_current_win()
      local cursor = wincursor.position(kite_winid)

      local fname = entfmt.strip(buflines.line(self.bufnr, cursor.lnum))
      if fname == "" then return jelly.warn("no file found at the cursor line") end

      state.cursor_row(self.root, cursor.row)

      local path_to = fs.joinpath(self.root, fname)
      if entfmt.is_dir(fname) then
        jelly.debug("kite cd %s", path_to)
        self:cd(kite_winid, path_to)
      else
        open_mode = open_mode or "inplace"
        jelly.debug("%s %s", open_mode, path_to)
        edit_file(kite_winid, path_to, open_mode)
      end
    end
  end

  ---goto root/dir/
  function Impl:open_dir()
    local kite_winid = api.nvim_get_current_win()

    local cursor = wincursor.position(kite_winid)

    local fname = entfmt.strip(buflines.line(self.bufnr, cursor.lnum))
    if fname == "" then return end

    if not entfmt.is_dir(fname) then return end

    state.cursor_row(self.root, cursor.row)

    local path_to = fs.joinpath(self.root, fname)
    self:cd(kite_winid, path_to)
  end

  -- goto parent dir, made for keymap
  function Impl:parent()
    local kite_winid = api.nvim_get_current_win()
    local parent = fs.parent(self.root)

    state.cursor_row(self.root, wincursor.row(kite_winid))

    self:cd(kite_winid, parent)
  end

  function Impl:reload()
    local winid = api.nvim_get_current_win()

    local root = self.root
    state.forget_entries(root)
    self:cd(winid, root)
  end

  function Impl:stats()
    local entries = state.entries(self.root)
    jelly.info('"%s" %s entries', self.root, #entries)
  end

  do
    local action_mode = { i = "inplace", a = "inplace", v = "right", o = "below", t = "tab", cr = "inplace", space = "inplace" }

    function Impl:beckon()
      local kite_winid = api.nvim_get_current_win()

      local open_win
      if is_landwin(kite_winid) then
        open_win = function(_, beckon_bufnr) return default_open_win(beckon_bufnr, self.root) end
      else
        local kite_winopts = api.nvim_win_get_config(kite_winid)
        open_win = function(_, beckon_bufnr)
          local beckon_winid = default_open_win(beckon_bufnr, self.root)
          api.nvim_win_set_config(beckon_winid, kite_winopts)
          return beckon_winid
        end
      end

      beckon_select(state.entries(self.root), {
        open_win = open_win,
      }, function(_, row, action) --
        wincursor.g1(kite_winid, row, 0)
        self:open(action_mode[action])
      end)
    end
  end

  ---@param bufnr integer
  ---@param root string
  ---@return kite.RHS
  function RHS(bufnr, root) return setmetatable({ bufnr = bufnr, root = root }, Impl) end
end

---@param root string
---@return integer bufnr
local function create_buf(root)
  local function namefn() return string.format("kite://%s", fs.basename(root)) end
  local bufnr = Ephemeral({ handyclose = true, namefn = namefn }, state.entries(root))
  prefer.bo(bufnr, "filetype", "kite")

  do --keymaps
    local bm = bufmap.wraps(bufnr)
    local rhs = RHS(bufnr, root)

    --stylua: ignore start
    bm.n("<cr>",  function() rhs:open("inplace") end)
    bm.n("gf",    function() rhs:open("inplace") end)
    bm.n("i",     function() rhs:open("inplace") end)
    bm.n("o",     function() rhs:open("below") end)
    bm.n("t",     function() rhs:open("tab") end)
    bm.n("v",     function() rhs:open("right") end)
    bm.n("<c-/>", function() rhs:open("right") end)
    bm.n("h",     function() rhs:parent() end)
    bm.n("l",     function() rhs:open_dir() end)
    bm.n("-",     function() rhs:parent() end)
    bm.n("r",     function() rhs:reload() end)
    bm.n("<c-g>", function() rhs:stats() end)
    bm.n("/",     function() rhs:beckon() end)
    --stylua: ignore end
  end

  return bufnr
end

---@param root string @absolute path
---@param open_win? fun(bufnr:integer,root:string):winid:integer
---@return integer winid
---@return integer bufnr
return function(root, open_win)
  open_win = open_win or default_open_win

  local bufnr = create_buf(root)
  local winid = open_win(bufnr, root)

  return winid, bufnr
end
