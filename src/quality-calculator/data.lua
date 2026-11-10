-- quality-calculator
-- Area selection tool, a shortcut on the bar and a hotkey that puts the tool into the hand.
-- A plain selection replaces the set of machines, Shift adds, Shift plus right button removes.

local TOOL = "qcalc-selection-tool"
local FILTERS = {"assembling-machine", "furnace", "mining-drill"}

local function selection(color, box)
  return {
    border_color = color,
    cursor_box_type = box,
    mode = {"any-entity"},
    entity_type_filters = FILTERS,
  }
end

local select_new = selection({r = 0.9, g = 0.7, b = 0.1}, "copy")
local select_add = selection({r = 0.3, g = 0.9, b = 0.3}, "copy")
local select_remove = selection({r = 0.9, g = 0.3, b = 0.3}, "not-allowed")

data:extend({
  {
    type = "selection-tool",
    name = TOOL,
    icon = "__quality-calculator__/graphics/tool-64.png",
    icon_size = 64,
    flags = {"only-in-cursor", "spawnable", "not-stackable"},
    hidden = true,
    hidden_in_factoriopedia = true,
    stack_size = 1,
    subgroup = "tool",
    order = "z[qcalc]",
    select = select_new,
    alt_select = select_add,
    reverse_select = select_remove,
    alt_reverse_select = select_remove,
    super_forced_select = select_new,
  },
  {
    type = "custom-input",
    name = "qcalc-give-tool",
    key_sequence = "CONTROL + SHIFT + Q",
    action = "spawn-item",
    item_to_spawn = TOOL,
    order = "a",
  },
  {
    type = "shortcut",
    name = "qcalc-shortcut",
    order = "b[blueprints]-z[qcalc]",
    action = "spawn-item",
    item_to_spawn = TOOL,
    localised_name = {"shortcut-name.qcalc-shortcut"},
    associated_control_input = "qcalc-give-tool",
    icon = "__quality-calculator__/graphics/shortcut-56.png",
    icon_size = 56,
    small_icon = "__quality-calculator__/graphics/shortcut-24.png",
    small_icon_size = 24,
  },
})
