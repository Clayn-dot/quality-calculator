-- quality-calculator: the result window: what comes out and what must be supplied.
-- Tables and formatting are in gui_table.lua, the /qc-dump file is written by gui_dump.lua.

local calc = require("calc")
local collect = require("collect")
local tbl = require("gui_table")
local dump = require("gui_dump")

local gui = {}

local WINDOW = "qcalc_window"
local PERIODS = tbl.PERIODS
local GRAY = tbl.GRAY
gui.WINDOW = WINDOW
gui.PERIODS = PERIODS
gui.fmt, gui.pct = tbl.fmt, tbl.pct

local function player_state(player_index)
  storage.players = storage.players or {}
  local s = storage.players[player_index]
  if not s then
    s = {}
    storage.players[player_index] = s
  end
  s.period = s.period or 1
  s.decimals = s.decimals or 2
  s.entities = s.entities or {}
  return s
end
gui.player_state = player_state

-- Labels for the decimals drop-down: 0.0, 0.00, 0.000 ...
local function decimals_items()
  local items = {}
  for d = 1, 5 do items[d] = "0." .. string.rep("0", d) end
  return items
end

local function period_items()
  local items = {}
  for i, p in ipairs(PERIODS) do items[i] = {p.key} end
  return items
end


-- Footer next to the lists: how many machines are counted and how many not, with reasons and machine names.
local function set_footer(window, stats, result)
  local controls = window.children[2] and window.children[2]["qcalc_controls"]
  local footer = controls and controls["qcalc_footer"]
  if not footer then return end
  if stats.skipped > 0 then
    ---@type any[]
    local reasons = {""}
    for i, s in ipairs(stats.skipped_list) do
      if i > 3 then break end
      local proto = prototypes.entity[s.entity]
      if i > 1 then reasons[#reasons + 1] = ", " end
      reasons[#reasons + 1] = {"", s.count .. " × ", proto and proto.localised_name or s.entity,
        " (", {"qcalc.skip-" .. s.reason}, ")"}
    end
    footer.caption = {"qcalc.footer-skipped", tostring(stats.machines), tostring(stats.skipped), reasons}
  else
    footer.caption = {"qcalc.footer", tostring(stats.machines)}
  end
  if result and (result.throttled or 0) > 0 then
    footer.caption = {"", footer.caption, "\n", {"qcalc.footer-throttled", tostring(result.throttled),
      tostring(result.crafter_count), string.format("%.0f", result.average_load * 100)}}
  end
end

-- Calculation for the saved machines. Returns nil when no suitable machines are left.
local function compute(player, state)
  local player_settings = settings.get_player_settings(player.index)
  local keep = player_settings["qcalc-keep-from"]
  local mode = player_settings["qcalc-recycler-mode"]
  local skip_blocked = player_settings["qcalc-skip-blocked"]
  local limit = player_settings["qcalc-limit-by-supply"]
  local options = {
    skip = (skip_blocked == nil or skip_blocked.value) and state.blocked or nil,
    drill_cache = state.drill_cache,
    tick = game.tick,
    quality_only = true,
    limited = limit == nil or limit.value,
  }
  local input, stats = collect.build_input(state.entities, player.force, keep and keep.value or nil,
    mode and mode.value or nil, options)
  if state.supply and next(state.supply) then input.supply = state.supply end
  -- close the window only when no selected machines are left at all (destroyed); if they are just not
  -- counted (for example full output), show an empty result with a note at the bottom
  if stats.machines == 0 and stats.skipped == 0 then return nil end
  return input, stats, calc.run(input)
end

-- /qc-dump [name]: see gui_dump.lua. Returns the machine count and the file name, or nil without a selection.
function gui.dump(player, name)
  local state = player_state(player.index)
  local input, stats, result = compute(player, state)
  if not (input and stats and result) then return nil end
  return dump.write({player = player, name = name, state = state, input = input, stats = stats, result = result,
    period = PERIODS[state.period] or PERIODS[1], window_open = player.gui.screen[WINDOW] ~= nil})
end

function gui.close(player)
  local w = player.gui.screen[WINDOW]
  if w then w.destroy() end
  player_state(player.index).last = nil
end

local function create_window(player, state)
  local frame = player.gui.screen.add{type = "frame", name = WINDOW, direction = "vertical"}
  frame.auto_center = true

  local bar = frame.add{type = "flow", direction = "horizontal"}
  bar.drag_target = frame
  local title = bar.add{type = "label", caption = {"qcalc.title"}, style = "frame_title", ignored_by_interaction = true}
  title.style.top_margin = -3
  local filler = bar.add{type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true}
  filler.style.horizontally_stretchable = true
  filler.style.height = 24
  filler.style.right_margin = 4
  bar.add{type = "sprite-button", name = "qcalc_close", style = "frame_action_button", sprite = "utility/close",
    hovered_sprite = "utility/close_black", clicked_sprite = "utility/close_black", tags = {qcalc = "close"}}

  local inner = frame.add{type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical"}

  -- Period and decimals: two identical lists side by side, without labels (names are in tooltips).
  local controls = inner.add{type = "flow", name = "qcalc_controls", direction = "horizontal"}
  controls.style.horizontal_spacing = 6
  local period_dd = controls.add{type = "drop-down", name = "qcalc_period", items = period_items(),
    selected_index = state.period, tags = {qcalc = "period"}, tooltip = {"qcalc.period-tooltip"}}
  period_dd.style.width = 90
  local decimals_dd = controls.add{type = "drop-down", name = "qcalc_decimals", items = decimals_items(),
    selected_index = state.decimals, tags = {qcalc = "decimals"}, tooltip = {"qcalc.decimals-tooltip"}}
  decimals_dd.style.width = 118  -- "0.00000" must fit whole
  controls.style.vertical_align = "center"
  -- how many machines are counted and how many not: right of the lists, small
  local footer = controls.add{type = "label", name = "qcalc_footer", caption = ""}
  footer.style.font = "default-small"
  footer.style.font_color = GRAY
  footer.style.single_line = false
  footer.style.maximal_width = 260

  local scroll = inner.add{type = "scroll-pane", name = "qcalc_scroll",
    horizontal_scroll_policy = "never", vertical_scroll_policy = "auto"}
  scroll.style.maximal_height = 520
  scroll.style.minimal_width = 560
  scroll.style.top_margin = 6
  -- a scroll pane has no vertical_spacing (the game crashes), so inside it a flow gives the spacing between frames
  local content = scroll.add{type = "flow", name = "qcalc_content", direction = "vertical"}
  content.style.vertical_spacing = 6

  player.opened = frame
  return frame
end

-- Redraw the window from a finished calculation (state.last) without recalculating: used by period and decimals changes.
function gui.rebuild(player)
  local w = player.gui.screen[WINDOW]
  local state = player_state(player.index)
  local last = state.last
  if not (w and last) then return end
  local scroll = w.children[2] and w.children[2]["qcalc_scroll"]
  local content = scroll and scroll["qcalc_content"]
  if content then tbl.build_results(content, last, state) end
  set_footer(w, last.stats, last.result)
end

-- Recalculate for the selected machines and redraw. There is no auto refresh: recalculation happens only on selection.
-- If no machines are left at all (destroyed), the window closes.
function gui.recalculate(player)
  local w = player.gui.screen[WINDOW]
  if not w then return end
  local state = player_state(player.index)
  local input, stats, result = compute(player, state)
  if not input then
    gui.close(player)
    return
  end
  state.last = {chain = input.chain, stats = stats, result = result}
  gui.rebuild(player)
end

-- Show the window (create it if missing) and calculate.
function gui.show(player)
  local state = player_state(player.index)
  if not player.gui.screen[WINDOW] then create_window(player, state) end
  gui.recalculate(player)
end

-- Apply a selection. mode: "replace" (new), "add" (add), "remove" (remove).
-- If the selection has no suitable machines (empty, no recipe, no resource under a drill), nothing happens.
function gui.apply_selection(player, mode, entities)
  local state = player_state(player.index)
  local picked = {}
  for _, e in pairs(entities) do
    if e.valid and collect.MACHINE_TYPES[e.type] and e.unit_number then picked[e.unit_number] = e end
  end
  if next(picked) == nil then return end

  state.blocked = state.blocked or {}
  state.drill_cache = state.drill_cache or {}
  if mode == "remove" then
    for id in pairs(picked) do
      state.entities[id] = nil
      state.blocked[id] = nil
    end
    if player.gui.screen[WINDOW] then gui.recalculate(player) end
    return
  end

  local _, stats = collect.build_input(picked, player.force, nil, nil, {drill_cache = state.drill_cache, tick = game.tick,
    quality_only = true})
  -- With no machine that has a quality chance (modules, beacons, built-in quality) do nothing. When adding to an
  -- existing selection (Shift), it is enough that quality was in the selection earlier.
  local extending = mode == "add" and next(state.entities) ~= nil
  if stats.machines == 0 or (stats.quality_machines == 0 and not extending) then return end
  if mode ~= "add" then
    state.entities = {}
    state.blocked = {}
    state.supply = nil
  end
  -- Machines with full output (drills with "Target full") give nothing now: remember them at selection and
  -- do not count them (a setting turns it back on). One snapshot, so numbers do not jump.
  local statuses = defines.entity_status
  for id, e in pairs(picked) do
    state.entities[id] = e
    local status = e.status
    local blocked = status == statuses.full_output or status == statuses.waiting_for_space_in_destination
      or status == statuses.not_enough_space_in_output
    -- a drill that is not mining now (no resource, no power, disabled) gives nothing either
    if e.type == "mining-drill" and status and not blocked then
      blocked = status ~= statuses.working and status ~= statuses.normal and status ~= statuses.low_power
    end
    state.blocked[id] = blocked or nil
  end
  gui.show(player)
end

function gui.set_period(player, index)
  local state = player_state(player.index)
  state.period = math.min(math.max(index, 1), #PERIODS)
  gui.rebuild(player)
end

-- Supply of a raw item from outside entered in the input table (items per chosen period); an empty field removes the limit.
-- Recalculation uses the machines already selected, the window stays open and the area need not be selected again.
function gui.set_supply(player, item, text)
  local state = player_state(player.index)
  local period = PERIODS[state.period] or PERIODS[1]
  local value = tonumber(text)
  state.supply = state.supply or {}
  state.supply[item] = (value and value >= 0) and value / period.seconds or nil
  if next(state.supply) == nil then state.supply = nil end
  gui.recalculate(player)
end

function gui.set_decimals(player, decimals)
  local state = player_state(player.index)
  state.decimals = math.min(math.max(decimals, 1), 5)
  gui.rebuild(player)
end

return gui
