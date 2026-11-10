-- quality-calculator
-- Runtime script. Everything that must survive a save and behave the same in multiplayer lives in `storage`.

local collect = require("collect")
local calc = require("calc")
local gui = require("gui")

local TOOL = "qcalc-selection-tool"

script.on_init(function()
  storage.players = storage.players or {}
end)

script.on_configuration_changed(function()
  storage.players = storage.players or {}
end)

-- Selection: a plain one replaces the set of machines, Shift adds, Shift plus right button removes.
local function selection_handler(mode)
  return function(event)
    if event.item ~= TOOL then return end
    local player = game.get_player(event.player_index)
    if not player then return end
    gui.apply_selection(player, mode, event.entities)
  end
end

script.on_event(defines.events.on_player_selected_area, selection_handler("replace"))
script.on_event(defines.events.on_player_alt_selected_area, selection_handler("add"))
script.on_event(defines.events.on_player_reverse_selected_area, selection_handler("remove"))
script.on_event(defines.events.on_player_alt_reverse_selected_area, selection_handler("remove"))

script.on_event(defines.events.on_gui_click, function(event)
  local element = event.element
  if not (element and element.valid and element.tags and element.tags.qcalc) then return end
  local player = game.get_player(event.player_index)
  local kind = element.tags.qcalc
  if kind == "close" then
    gui.close(player)
  end
end)

script.on_event(defines.events.on_gui_selection_state_changed, function(event)
  local element = event.element
  if not (element and element.valid and element.tags) then return end
  local player = game.get_player(event.player_index)
  if element.tags.qcalc == "decimals" then
    gui.set_decimals(player, element.selected_index)
  elseif element.tags.qcalc == "period" then
    gui.set_period(player, element.selected_index)
  end
end)

script.on_event(defines.events.on_gui_confirmed, function(event)
  local element = event.element
  if not (element and element.valid and element.tags and element.tags.qcalc == "supply") then return end
  local player = game.get_player(event.player_index)
  if player then gui.set_supply(player, element.tags.item --[[@as string]], element.text) end
end)

script.on_event(defines.events.on_gui_closed, function(event)
  local element = event.element
  if element and element.valid and element.name == gui.WINDOW then
    element.destroy()
    local player = game.get_player(event.player_index)
    if player then gui.player_state(player.index).last = nil end
  end
end)

-- Interface for checks and debugging: calculation for an area without a window.
-- remote.call("quality-calculator", "calculate", surface_index, {{x1, y1}, {x2, y2}}, keep_from_quality_name)
remote.add_interface("quality-calculator", {
  -- Cost of one recalculation (data collection and calculation) on the machines of the area; the result goes to the log as QCALC_BENCH.
  benchmark = function(surface_index, area, repeats)
    local surface = game.get_surface(surface_index)
    if not surface then return end
    local entities = surface.find_entities_filtered{area = area, type = {"assembling-machine", "furnace", "mining-drill"}}
    local options = {drill_cache = {}, tick = game.tick}
    local cold = helpers.create_profiler()
    local input = collect.build_input(entities, game.forces["player"], nil, nil, options)
    calc.run(input)
    cold.stop()
    local warm = helpers.create_profiler()
    for _ = 1, repeats do
      input = collect.build_input(entities, game.forces["player"], nil, nil, options)
      calc.run(input)
    end
    warm.stop()
    ---@diagnostic disable-next-line: assign-type-mismatch
    log({"", "QCALC_BENCH machines=" .. #entities .. " first=", cold, " then " .. repeats .. " repeats total=", warm})
  end,

  calculate = function(surface_index, area, keep_from)
    local surface = game.get_surface(surface_index)
    if not surface then return nil end
    local entities = surface.find_entities_filtered{area = area, type = {"assembling-machine", "furnace", "mining-drill"}}
    local input, stats = collect.build_input(entities, game.forces["player"], keep_from)
    local result = calc.run(input)
    local chain_names = {}
    for i, q in ipairs(input.chain) do chain_names[i] = q.name end
    local machines = {}
    for i, m in ipairs(input.machines) do
      machines[i] = {
        entity = m.entity.name, recipe = m.recipe, kind = m.kind,
        crafts_per_second = m.crafts_per_second, productivity = m.productivity,
        quality_chance = m.quality_chance, quality = m.quality,
        products = m.products,
      }
    end
    return {chain = chain_names, stats = stats, result = result, machines = machines}
  end,
})

commands.add_command("qc-dump",
  "Quality Calculator: write the machines of the current selection to script-output/qc-dump[-name].json (for bug reports). Usage: /qc-dump [name].",
  function(command)
    local player = game.get_player(command.player_index)
    if not player then return end
    local name = command.parameter and command.parameter ~= "" and command.parameter or nil
    local count, file = gui.dump(player, name)
    if count then
      player.print("[Quality Calculator] " .. count .. " machines written to script-output/" .. file)
    else
      player.print("[Quality Calculator] nothing to write: select an area first")
    end
  end)
