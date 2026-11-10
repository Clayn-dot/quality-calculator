-- quality-calculator: collects machine data from the game into plain tables for calc.lua.
-- This is the only place that knows the game API (prototypes, LuaEntity, LuaForce).

local collect = {}

local MACHINE_TYPES = {["assembling-machine"] = true, ["furnace"] = true, ["mining-drill"] = true}
collect.MACHINE_TYPES = MACHINE_TYPES

-- Quality chain from normal upward by `next`, only what the force has unlocked: the game gives no items above
-- the unlocked quality (checked by simulation), the chance collapses into the highest unlocked quality.
function collect.build_chain(force)
  local chain, index = {}, {}
  local q = prototypes.quality["normal"]
  local guard = 0
  while q and guard < 64 do
    guard = guard + 1
    if #chain > 0 and force and not force.is_quality_unlocked(q.name) then break end
    -- In 2.1 a quality has chain_probability. In 2.0 it does not: the first step up uses the effect chance,
    -- every next step uses next_probability of the reached quality (10% by default).
    local ok, chain_probability = pcall(function() return q.chain_probability end)
    local next_probability = q.next_probability
    if not ok or chain_probability == nil then
      chain_probability = next_probability or 0
      next_probability = 1
    end
    chain[#chain + 1] = {
      name = q.name,
      localised_name = q.localised_name,
      color = q.color,
      next_probability = next_probability,
      chain_probability = chain_probability,
    }
    index[q.name] = #chain
    q = q.next
  end
  return chain, index
end

-- Quality distribution straight from the game: LuaQualityPrototype.get_roll_chances(effect, force).
-- It accounts for the 10% chain and for locked qualities.
local function make_roll(chain, force)
  -- in 2.0 a quality has no get_roll_chances: use our own function (calc.roll)
  local ok, game_roll = pcall(function() return prototypes.quality["normal"].get_roll_chances end)
  if not ok or game_roll == nil then return nil end
  return function(base, chance)
    local result = prototypes.quality[chain[base].name].get_roll_chances(chance, force)
    local v = {}
    for i = 1, #chain do v[i] = result[chain[i].name] or 0 end
    return v
  end
end

local function name_of(id)
  if type(id) == "string" then return id end
  if id ~= nil then return id.name end
  return nil
end

-- Recipe and its quality of a machine. For furnaces (recyclers too) get_recipe() is empty between crafts,
-- so previous_recipe is used.
local function recipe_of(entity)
  local recipe, quality = entity.get_recipe()
  if recipe then return recipe.name, name_of(quality) or "normal" end
  if entity.type == "furnace" then
    local prev = entity.previous_recipe
    if prev then return name_of(prev.name), name_of(prev.quality) or "normal" end
  end
  return nil
end

-- proto.categories arrives as a list of names (the docs say dictionary): both forms are supported.
local function has_category(proto, category)
  local categories = proto.categories
  if not categories then return false end
  if categories[category] then return true end
  for _, value in pairs(categories) do
    if value == category then return true end
  end
  return false
end

local function item_ingredients(proto)
  local list = {}
  for _, ing in ipairs(proto.ingredients) do
    if ing.type == "item" then list[#list + 1] = {name = ing.name, amount = ing.amount} end
  end
  return list
end

-- products: array of Product from a recipe or from the properties of a mined resource.
local function item_products(products)
  local list = {}
  for _, p in ipairs(products or {}) do
    if p.type == "item" then
      local avg = p.amount
      if avg == nil then avg = ((p.amount_min or 0) + (p.amount_max or 0)) / 2 end
      local probability = p.independent_probability or 1
      local shared = p.shared_probability
      if shared then probability = probability * (shared.max - shared.min) end
      list[#list + 1] = {
        name = p.name,
        amount_avg = avg,
        probability = probability,
        extra_count_fraction = p.extra_count_fraction,
        ignored_by_productivity = p.ignored_by_productivity,
        affected_by_quality = p.affected_by_quality,
        quality_change = p.quality_change,
      }
    end
  end
  return list
end

-- Assembling machine, furnace, recycler. Returns a table, or nil and a reason.
local function crafter_machine(entity, index)
  local recipe_name, quality_name = recipe_of(entity)
  if not recipe_name then return nil, "norecipe" end
  local proto = prototypes.recipe[recipe_name]
  if not proto or not proto.energy or proto.energy <= 0 then return nil, "badrecipe" end

  local products = item_products(proto.products)
  local ingredients = item_ingredients(proto)
  if #products == 0 then return nil, "noitems" end

  -- Productivity: modules, beacons and the machine's own (entity.productivity_bonus) plus the recipe bonus from
  -- research (force.recipes[...].productivity_bonus, entity.productivity_bonus does not include it: checked in game).
  local productivity = entity.productivity_bonus or 0
  local force_recipe = entity.force.recipes[recipe_name]
  if force_recipe then productivity = productivity + force_recipe.productivity_bonus end
  local max_prod = proto.maximum_productivity
  if max_prod and productivity > max_prod then productivity = max_prod end

  local effects = entity.effects
  local m = {
    entity = entity,
    entity_id = entity.unit_number,
    entity_name = entity.name,
    entity_quality = entity.quality and entity.quality.name or "normal",
    recipe = recipe_name,
    recipe_quality = quality_name,
    crafts_per_second = entity.crafting_speed / proto.energy,
    productivity = productivity,
    quality_chance = effects and effects.quality or 0,
    quality = index[quality_name] or 1,
    ingredients = ingredients,
    products = products,
    kind = "crafter",
  }
  if has_category(proto, "recycling") then
    -- A recycler takes one item per craft; the item comes from the recipe.
    local item = ingredients[1]
    if not item then return nil, "noitems" end
    m.kind = "recycler"
    m.recycler_item = item.name
  end
  return m
end

-- Mining drill: resources under it (as in the game: by the number of tiles of each kind), speed with modules and the
-- research bonus (entity.productivity_bonus of a drill already includes mining research: checked in game). Returns
-- a list of "machines", one per resource kind.
-- Finding resources under a drill is the most expensive part, so the result is cached for 30 seconds
-- (cache: table per player, tick: current tick).
local DRILL_CACHE_TICKS = 1800

local function scan_resources(entity)
  local proto = entity.prototype
  local radius = (proto.mining_drill_radius or 0) + 0.01
  local p = entity.position
  local resources = entity.surface.find_entities_filtered{
    area = {{p.x - radius, p.y - radius}, {p.x + radius, p.y + radius}}, type = "resource"}
  local categories = proto.resource_categories or {}

  local by_name, total = {}, 0
  for _, res in pairs(resources) do
    local rp = res.prototype
    local mp = rp.mineable_properties
    if categories[rp.resource_category] and mp and mp.minable then
      local rec = by_name[res.name]
      if not rec then
        local mining_time = mp.mining_time
        if rp.infinite_resource and (rp.normal_resource_amount or 0) > 0 then
          mining_time = mining_time / (res.amount / rp.normal_resource_amount)
        end
        rec = {name = res.name, mining_time = mining_time, products = item_products(mp.products), count = 0}
        by_name[res.name] = rec
      end
      rec.count = rec.count + 1
      total = total + 1
    end
  end
  return by_name, total
end

local function drill_machines(entity, cache, tick)
  local proto = entity.prototype
  local speed = (proto.mining_speed or 0) * (1 + (entity.speed_bonus or 0))
  if speed <= 0 then return nil, "badrecipe" end

  local by_name, total
  local cached = cache and entity.unit_number and cache[entity.unit_number]
  if cached and tick and tick - cached.tick < DRILL_CACHE_TICKS then
    by_name, total = cached.by_name, cached.total
  else
    by_name, total = scan_resources(entity)
    if cache and entity.unit_number then cache[entity.unit_number] = {tick = tick or 0, by_name = by_name, total = total} end
  end
  if total == 0 then return nil, "noresource" end

  local effects = entity.effects
  local list = {}
  for _, rec in pairs(by_name) do
    if #rec.products > 0 and rec.mining_time > 0 then
      list[#list + 1] = {
        entity = entity,
        entity_id = entity.unit_number,
        entity_name = entity.name,
        entity_quality = entity.quality and entity.quality.name or "normal",
        recipe = rec.name,
        recipe_quality = "normal",
        is_resource = true,
        crafts_per_second = speed / rec.mining_time * (rec.count / total),
        productivity = entity.productivity_bonus or 0,
        quality_chance = effects and effects.quality or 0,
        quality = 1,
        ingredients = {},
        products = rec.products,
        kind = "crafter",
      }
    end
  end
  if #list == 0 then return nil, "noitems" end
  table.sort(list, function(a, b) return a.recipe < b.recipe end)
  return list
end

local function entity_quality_name(entity)
  local q = entity.quality
  return q and q.name or "normal"
end

-- Only what is tied to quality: machines with a quality chance, and of the recyclers those that take an item
-- such machines make (directly or through other recyclers). Removes the rest from entries
-- and returns how many were removed.
local function filter_quality(entries)
  local keep, items = {}, {}
  local function take(entry)
    keep[entry] = true
    for _, m in ipairs(entry.list) do
      for _, prod in ipairs(m.products) do items[prod.name] = true end
    end
  end
  for _, entry in ipairs(entries) do
    if entry.list then
      for _, m in ipairs(entry.list) do
        if m.kind ~= "recycler" and m.quality_chance > 0 then take(entry) break end
      end
    end
  end
  local changed = true
  while changed do
    changed = false
    for _, entry in ipairs(entries) do
      local first = entry.list and entry.list[1]
      if first and first.kind == "recycler" and not keep[entry]
         and (items[first.recycler_item] or first.quality_chance > 0) then
        take(entry)
        changed = true
      end
    end
  end
  local kept, ignored = {}, 0
  for _, entry in ipairs(entries) do
    -- machines without a recipe and skipped ones stay: they go into the "not counted" line only if they are linked
    if keep[entry] or (not entry.list and entry.why == "blocked") then
      kept[#kept + 1] = entry
    elseif entry.list then
      ignored = ignored + 1
    end
  end
  for i = #entries, 1, -1 do entries[i] = nil end
  for i, entry in ipairs(kept) do entries[i] = entry end
  return ignored
end

-- Scans the selected entities into entries {entity, list, why}: list is the machines found, why is the reason
-- when there are none.
local function scan_entities(entities, index, options)
  local entries = {}
  for _, entity in pairs(entities) do
    if entity.valid and MACHINE_TYPES[entity.type] then
      local list, why
      -- full output is skipped only for drills: for the others we count the theoretical maximum
      if options.skip and entity.type == "mining-drill" and entity.unit_number and options.skip[entity.unit_number] then
        why = "blocked"
      elseif entity.type == "mining-drill" then
        list, why = drill_machines(entity, options.drill_cache, options.tick)
      else
        local m
        m, why = crafter_machine(entity, index)
        list = m and {m} or nil
      end
      entries[#entries + 1] = {entity = entity, list = list, why = why}
    end
  end
  return entries
end

-- Counts a counted entry into the statistics and the machine list.
local function tally_counted(stats, machines, entity, list, entity_quality)
  stats.machines = stats.machines + 1
  local has_quality = false
  for _, m in ipairs(list) do
    machines[#machines + 1] = m
    -- effects.quality already includes the machine's built-in quality (from mods too)
    if m.quality_chance > 0 then has_quality = true end
  end
  if has_quality then stats.quality_machines = stats.quality_machines + 1 end
  local first = list[1]
  if first.kind == "recycler" then stats.recyclers = stats.recyclers + 1 end
  if first.is_resource then stats.drills = stats.drills + 1 end
  local label = first.recipe .. (#list > 1 and "+" or "")
  local key = entity.name .. "|" .. entity_quality .. "|" .. label .. "|" .. first.recipe_quality
  local g = stats.groups[key]
  if not g then
    g = {entity = entity.name, entity_quality = entity_quality, recipe = first.recipe,
         is_resource = first.is_resource, more = #list > 1, quality = first.recipe_quality, count = 0}
    stats.groups[key] = g
    stats.group_list[#stats.group_list + 1] = g
  end
  g.count = g.count + 1
end

-- Counts a skipped entry (no recipe, blocked, and so on) into the statistics.
local function tally_skipped(stats, entity, why, entity_quality)
  stats.skipped = stats.skipped + 1
  local key = entity.name .. "|" .. entity_quality .. "|" .. tostring(why)
  local s = stats.skipped_groups[key]
  if not s then
    s = {entity = entity.name, entity_quality = entity_quality, reason = why or "unknown", count = 0}
    stats.skipped_groups[key] = s
    stats.skipped_list[#stats.skipped_list + 1] = s
  end
  s.count = s.count + 1
end

-- entities: array or dictionary of LuaEntity. force: the player's force (which qualities are unlocked).
-- recycler_mode: "by-quality" (default: each recycler takes the quality it worked on last time)
-- or "pool" (any quality below the keep_from_name threshold).
-- options (optional): skip is a set of unit_number of machines not to count (full output);
-- drill_cache is the cache of resources under drills; tick is the current tick for the cache.
-- Returns the input for calc.run and statistics: how many machines, recyclers, drills, skipped, and groups
-- of "machine + recipe" for the summary.
function collect.build_input(entities, force, keep_from_name, recycler_mode, options)
  options = options or {}
  force = force or game.forces["player"]
  local chain, index = collect.build_chain(force)
  local machines = {}
  local stats = {machines = 0, ignored = 0, quality_machines = 0, recyclers = 0, drills = 0, skipped = 0, groups = {}, group_list = {},
                 skipped_groups = {}, skipped_list = {}}
  local entries = scan_entities(entities, index, options)
  if options.quality_only then stats.ignored = filter_quality(entries) end
  for _, entry in ipairs(entries) do
    local entity_quality = entity_quality_name(entry.entity)
    if entry.list then
      tally_counted(stats, machines, entry.entity, entry.list, entity_quality)
    else
      tally_skipped(stats, entry.entity, entry.why, entity_quality)
    end
  end
  table.sort(stats.group_list, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.entity .. a.recipe .. a.quality < b.entity .. b.recipe .. b.quality
  end)
  table.sort(stats.skipped_list, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return a.entity .. a.reason < b.entity .. b.reason
  end)

  local keep = #chain
  if keep_from_name and keep_from_name ~= "highest" and index[keep_from_name] then keep = index[keep_from_name] end
  return {chain = chain, machines = machines, keep_from = keep, roll = make_roll(chain, force),
          recycler_mode = recycler_mode or "by-quality", limited = options.limited or false}, stats
end

return collect
