-- Icons for the Quality++ qualities: the file name says which of its four extra qualities are on.
local EXTRA = {"mythical", "masterwork", "wondrous", "artifactual"}

local bits = ""
for _, name in ipairs(EXTRA) do
  local q = data.raw.quality[name]
  bits = bits .. ((q and not q.hidden) and "1" or "0")
end

if bits ~= "0000" then
  local base = "__quality-calculator__/graphics/ext-" .. bits
  data.raw["selection-tool"]["qcalc-selection-tool"].icon = base .. "-tool-64.png"
  local shortcut = data.raw.shortcut["qcalc-shortcut"]
  shortcut.icon = base .. "-shortcut-56.png"
  shortcut.small_icon = "__quality-calculator__/graphics/ext-shortcut-24.png"
end
