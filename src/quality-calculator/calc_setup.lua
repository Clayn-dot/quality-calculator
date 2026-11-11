-- Calculation setup: parses machines into crafters and recycler lanes, and works out what is made inside the area.
local util = require("calc_util")
local seeds = require("calc_seeds")

local EPS = util.EPS
local add_products = util.add_products

local setup = {}

-- Tracks which machines make an item and which spend it (for tooltips, like Rate Calculator).
-- makers: item -> "machine|quality" -> {entity=, quality=, count=}; users: item -> quality index -> same.
local function make_notes()
  local notes = {makers = {}, users = {}}
  local counted = {}
  local function bump(map, m, item, suffix)
    -- one machine (a drill with several resources) counts once per item
    local once = item .. "#" .. suffix .. "#" .. tostring(m.entity_id or {})
    if m.entity_id ~= nil then
      if counted[once] then return end
      counted[once] = true
    end
    local key = (m.entity_name or "?") .. "|" .. (m.entity_quality or "normal")
    local r = map[key]
    if not r then
      r = {entity = m.entity_name, quality = m.entity_quality or "normal", count = 0}
      map[key] = r
    end
    r.count = r.count + 1
  end
  function notes.maker(m)
    for _, prod in ipairs(m.products) do
      notes.makers[prod.name] = notes.makers[prod.name] or {}
      bump(notes.makers[prod.name], m, prod.name, "make")
    end
  end
  function notes.user(m, item, q)
    notes.users[item] = notes.users[item] or {}
    notes.users[item][q] = notes.users[item][q] or {}
    bump(notes.users[item][q], m, item, "use" .. q)
  end
  return notes
end

-- A lane is a group of recyclers of one item that take the same qualities.
-- Mode "by-quality": a recycler takes only the quality it worked on last time (sorting lines);
-- mode "pool" (default): any quality below the keep threshold.
local function add_recycler(st, m, notes)
  local n, keep = st.n, st.keep
  local item = m.recycler_item
  local per_craft = 1
  for _, ing in ipairs(m.ingredients) do
    if ing.name == item then per_craft = ing.amount end
  end
  local quality = math.min(math.max(m.quality or 1, 1), n)
  local key = st.by_quality and quality or "pool"
  local id = item .. "|" .. tostring(key)
  local lane = st.lanes[id]
  if not lane then
    local allowed = {}
    if st.by_quality then
      allowed[quality] = true
    else
      for q = 1, n do if q < keep then allowed[q] = true end end
    end
    lane = {item = item, key = key, capacity = 0, machines = {}, allowed = allowed}
    st.lanes[id] = lane
    st.lane_list[#st.lane_list + 1] = lane
  end
  m._per_craft = per_craft
  m._capacity = m.crafts_per_second * per_craft
  lane.capacity = lane.capacity + m._capacity
  lane.machines[#lane.machines + 1] = m
  for q in pairs(lane.allowed) do notes.user(m, item, q) end
end

local function add_crafter(st, m, notes)
  local n = st.n
  local q = math.min(math.max(m.quality or 1, 1), n)
  m._need = {}
  for _, ing in ipairs(m.ingredients) do
    m._need[#m._need + 1] = {name = ing.name, q = q, rate = ing.amount * m.crafts_per_second}
    notes.user(m, ing.name, q)
  end
  -- output at full load; the solver multiplies it by the machine load m._u
  m._prod = {}
  add_products(m._prod, m, m.crafts_per_second, q, st.n, st.roll)
  m._u = 1
  st.crafters[#st.crafters + 1] = m
end

local function parse_machines(st)
  local notes = make_notes()
  for _, m in ipairs(st.input.machines) do
    notes.maker(m)
    if m.kind == "recycler" then
      add_recycler(st, m, notes)
    else
      add_crafter(st, m, notes)
    end
  end
  st.makers, st.users = notes.makers, notes.users
  table.sort(st.lane_list, function(a, b)
    if a.item ~= b.item then return a.item < b.item end
    return tostring(a.key) < tostring(b.key)
  end)
end

-- "Made by the area": ordinary machines (assemblers, furnaces, drills), plus recyclers when ordinary machines
-- spend their product (plates and components of a recycle-craft loop). Such items are limited by what is really
-- made. An item that is only recycled (ore from a train) comes from outside without limits; the Input table
-- shows how much of it is needed.
local function find_made(st)
  local made = {}
  for _, m in ipairs(st.crafters) do
    for name, v in pairs(m._prod) do
      for i = 1, st.n do
        if v[i] > EPS then made[name] = true break end
      end
    end
  end
  local consumed = {}
  for _, m in ipairs(st.crafters) do
    for _, ing in ipairs(m.ingredients) do consumed[ing.name] = true end
  end
  for _, lane in ipairs(st.lane_list) do
    for _, m in ipairs(lane.machines) do
      for _, prod in ipairs(m.products) do
        if consumed[prod.name] then made[prod.name] = true end
      end
    end
  end
  st.made = made
end

-- Raw items with a set supply: the amount that can come from outside for all qualities, split by quality in
-- proportion to what ordinary machines need at full load.
local function find_capped(st)
  local n = st.n
  local capped = {}
  for name, cap in pairs(st.input.supply or {}) do
    if not st.made[name] then
      local w, wsum = {}, 0
      for q = 1, n do w[q] = 0 end
      for _, m in ipairs(st.crafters) do
        for _, need in ipairs(m._need) do
          if need.name == name then w[need.q] = w[need.q] + need.rate wsum = wsum + need.rate end
        end
      end
      if wsum > 0 then for q = 1, n do w[q] = w[q] / wsum end end
      capped[name] = {cap = math.max(0, cap), w = w}
    end
  end
  st.capped = capped
  if next(capped) then st.limited = true end
end

-- Quality split of a supplied loop item: the same as the area's own machines make it (full load), since the
-- outside supply comes from machines like them. Without such machines the weights stay nil (all goes to the lowest lane).
local function find_seed_weights(st)
  st.seed_weights = {}
  for item in pairs(st.seed_by_item) do
    local w, sum = {}, 0
    for q = 1, st.n do w[q] = 0 end
    -- only crafters that take normal-quality (lowest recipe quality) ingredients: higher lines are fed from
    -- inside the area, not from outside. The quality of the machine itself does not matter here.
    local lowest = st.n + 1
    for _, m in ipairs(st.crafters) do
      if m._prod[item] and (m.quality or 1) < lowest then lowest = m.quality or 1 end
    end
    for _, m in ipairs(st.crafters) do
      local v = m._prod[item]
      if v and (m.quality or 1) == lowest then
        for q = 1, st.n do w[q] = w[q] + v[q] sum = sum + v[q] end
      end
    end
    if sum > EPS then
      for q = 1, st.n do w[q] = w[q] / sum end
      st.seed_weights[item] = w
    end
  end
end

-- Machines that depend on items made by the area itself (only they are limited by the inflow).
local function find_limited_machines(st)
  st.lim_machines, st.lim_key = {}, {}
  if not st.limited then return end
  for _, m in ipairs(st.crafters) do
    m._lim = {}
    for _, need in ipairs(m._need) do
      if st.made[need.name] or st.capped[need.name] then
        need.key = need.name .. "|" .. need.q
        st.lim_key[need.key] = {need.name, need.q}
        m._lim[#m._lim + 1] = need
      end
    end
    if #m._lim > 0 then st.lim_machines[#st.lim_machines + 1] = m end
  end
end

-- Outside supply goes into the lowest lane of an item (whatever quality it takes); any other lane is topped up
-- from outside only when it has no internal source at all (see the solver).
local function prepare_lanes(st)
  local n = st.n
  local lowest_lane = {}
  for _, lane in ipairs(st.lane_list) do
    if type(lane.key) == "number" and (not lowest_lane[lane.item] or lane.key < lowest_lane[lane.item]) then
      lowest_lane[lane.item] = lane.key
    end
  end
  for _, lane in ipairs(st.lane_list) do
    lane.feed_q = type(lane.key) == "number" and lane.key or 1
    lane.external = (not st.made[lane.item]) and (lane.key == "pool" or lane.key == lowest_lane[lane.item])
    -- lane output is linear in intake: compute once what comes out per 1 item taken of each quality
    lane.unit = {}
    for q = 1, n do
      if lane.allowed[q] then
        local acc = {}
        for _, m in ipairs(lane.machines) do
          local share = lane.capacity > EPS and (m._capacity / lane.capacity) or 0
          if share > 0 then add_products(acc, m, share / m._per_craft, q, n, st.roll) end
        end
        lane.unit[q] = acc
      end
    end
  end
end

-- Builds the shared state table the solver and the result stage work on.
function setup.build(input)
  local chain = input.chain
  local n = #chain
  local keep = input.keep_from or n
  if keep < 1 then keep = 1 end
  local st = {
    input = input, chain = chain, n = n, keep = keep,
    roll = util.make_roll(input, chain),
    crafters = {}, lanes = {}, lane_list = {},
    limited = input.limited,
    by_quality = input.recycler_mode == "by-quality",
  }
  parse_machines(st)
  find_made(st)
  st.seed_by_item = {}
  if input.limited then
    for _, seed in ipairs(seeds.find(input)) do st.seed_by_item[seed.item] = seed end
  end
  find_seed_weights(st)
  find_capped(st)
  find_limited_machines(st)
  prepare_lanes(st)
  return st
end

return setup
