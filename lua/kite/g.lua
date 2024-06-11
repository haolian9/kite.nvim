---@class kite.G
---@field max_entries_per_dir integer

---@type kite.G
local g = require("infra.G")("kite")

do
  if g.max_entries_per_dir == nil then g.max_entries = 999 end
end

return g
