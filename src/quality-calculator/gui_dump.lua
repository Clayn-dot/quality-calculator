-- /qc-dump: writes everything needed to reproduce the window offline (for analysing mismatches with the game).
-- Machines as the calculation sees them, settings and window state, the result per item and quality (items per
-- second), the game's production statistics for a minute, ten minutes and an hour, and the statuses of all selected
-- entities (skipped ones too). The file has no references to entities.

local dump = {}

local function status_name_map()
  local names = {}
  for name, id in pairs(defines.entity_status) do names[id] = name end
  return names
end

local function copy_vecs(map)
  local out = {}
  for name, v in pairs(map or {}) do
    local arr = {}
    for i = 1, #v do arr[i] = v[i] end
    out[name] = arr
  end
  return out
end

local function dump_statistics(player, chain, names)
  local report = {surface = player.surface.name, items = {}, errors = {}}
  local ok, stats = pcall(function() return player.force.get_item_production_statistics(player.surface) end)
  if not ok then
    report.errors[#report.errors + 1] = "get_item_production_statistics: " .. tostring(stats)
    return report
  end
  local precisions = {one_minute = defines.flow_precision_index.one_minute,
    ten_minutes = defines.flow_precision_index.ten_minutes, one_hour = defines.flow_precision_index.one_hour}
  -- in the game statistics "input" is produced and "output" is consumed
  local categories = {produced = "input", consumed = "output"}
  for _, name in ipairs(names) do
    local per_quality = {}
    for qi, q in ipairs(chain) do
      local row = {}
      for cat_label, cat in pairs(categories) do
        for p_label, p in pairs(precisions) do
          local ok2, value = pcall(function()
            return stats.get_flow_count{name = {name = name, quality = q.name}, category = cat, precision_index = p}
          end)
          if ok2 then
            row[cat_label .. "_" .. p_label] = value
          elseif #report.errors < 5 then
            report.errors[#report.errors + 1] = name .. "/" .. q.name .. ": " .. tostring(value)
          end
        end
      end
      per_quality[qi] = row
    end
    report.items[name] = per_quality
  end
  return report
end

-- Machines without the entity reference, plus the sorted names of all items they touch.
local function copy_machines(input, status_names)
  local machines, items = {}, {}
  for _, m in ipairs(input.machines) do
    local copy = {}
    for k, v in pairs(m) do
      if k ~= "entity" then copy[k] = v end
    end
    local e = m.entity
    copy.status = e and e.valid and e.status and status_names[e.status] or nil
    copy.position = e and e.valid and {x = e.position.x, y = e.position.y} or nil
    machines[#machines + 1] = copy
    for _, p in ipairs(m.products or {}) do items[p.name] = true end
    for _, i in ipairs(m.ingredients or {}) do items[i.name] = true end
  end
  local item_names = {}
  for item in pairs(items) do item_names[#item_names + 1] = item end
  table.sort(item_names)
  return machines, item_names
end

-- All selected entities: their state now and what it was at selection.
local function copy_selected(state, status_names)
  local selected, histogram = {}, {}
  for id, e in pairs(state.entities) do
    if e.valid then
      local st = e.status and status_names[e.status] or "none"
      local key = e.name .. "|" .. (e.quality and e.quality.name or "normal") .. "|" .. st
      histogram[key] = (histogram[key] or 0) + 1
      selected[#selected + 1] = {id = id, name = e.name, quality = e.quality and e.quality.name or "normal",
        type = e.type, status_now = st, blocked_at_select = (state.blocked and state.blocked[id]) or false,
        x = e.position.x, y = e.position.y}
    end
  end
  return selected, histogram
end

local function copy_result(result)
  return {output = copy_vecs(result.output), external = copy_vecs(result.external),
    produced = copy_vecs(result.produced), spent = copy_vecs(result.spent), consumed = copy_vecs(result.consumed),
    demand = copy_vecs(result.demand), recycled = copy_vecs(result.recycled), recyclers = result.recyclers,
    throttled = result.throttled, crafter_count = result.crafter_count,
    average_load = result.average_load, units = "items per second"}
end

-- ctx = {player, name, state, input, stats, result, period, window_open}
-- Returns the number of machines and the file name.
function dump.write(ctx)
  local player, name, state, input, stats = ctx.player, ctx.name, ctx.state, ctx.input, ctx.stats
  local file = (name and name:match("^[%w_%-]+$")) and ("qc-dump-" .. name .. ".json") or "qc-dump.json"
  local status_names = status_name_map()
  local machines, item_names = copy_machines(input, status_names)
  local chain = {}
  for i, q in ipairs(input.chain) do
    chain[i] = {name = q.name, next_probability = q.next_probability, chain_probability = q.chain_probability}
  end
  local selected, histogram = copy_selected(state, status_names)
  local player_settings = settings.get_player_settings(player.index)
  local setting_values = {}
  for _, key in ipairs({"qcalc-keep-from", "qcalc-recycler-mode", "qcalc-skip-blocked", "qcalc-limit-by-supply"}) do
    local s = player_settings[key]
    setting_values[key] = s and s.value
  end
  local data = {
    meta = {tick = game.tick, mod_version = script.active_mods["quality-calculator"],
      game_version = script.active_mods["base"], player = player.name, force = player.force.name,
      surface = player.surface.name, label = name,
      drill_productivity_bonus = player.force.mining_drill_productivity_bonus},
    window = {open = ctx.window_open, period_key = ctx.period.key, period_seconds = ctx.period.seconds,
      supply_per_second = state.supply,
      decimals = state.decimals, settings = setting_values},
    chain = chain, keep_from = input.keep_from, recycler_mode = input.recycler_mode, limited = input.limited,
    stats = {machines = stats.machines, skipped = stats.skipped, quality_machines = stats.quality_machines,
      recyclers = stats.recyclers, drills = stats.drills, ignored = stats.ignored, skipped_list = stats.skipped_list},
    result = copy_result(ctx.result),
    game_statistics = dump_statistics(player, input.chain, item_names),
    status_histogram = histogram,
    selected = selected,
    machines = machines,
    skipped = stats.skipped_list, ignored = stats.ignored,
  }
  helpers.write_file(file, helpers.table_to_json(data), false, player.index)
  return #machines, file
end

return dump
