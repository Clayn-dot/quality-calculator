-- Final stage: turns the settled solver state into the result table.
local util = require("calc_util")

local EPS = util.EPS
local vec = util.vec

local result_stage = {}

-- All item names that appear anywhere in the settled state, sorted.
local function collect_names(st)
  local names, seen = {}, {}
  local function note(name)
    if not seen[name] then seen[name] = true; names[#names + 1] = name end
  end
  for name in pairs(st.produced_crafters) do note(name) end
  for name in pairs(st.recycled_out) do note(name) end
  for name in pairs(st.demand) do note(name) end
  for name in pairs(st.feed) do note(name) end
  table.sort(names)
  return names
end

-- Balance for every (item, quality) pair.
local function fill_balance(st, result, names)
  local n = st.n
  for _, name in ipairs(names) do
    local out, ext = vec(result.output, name, n), vec(result.external, name, n)
    local prod, cons = vec(result.produced, name, n), vec(result.consumed, name, n)
    local spent = vec(result.spent, name, n)
    local rec = vec(result.recycled, name, n)
    local dem = vec(result.demand, name, n)
    for q = 1, n do
      local p = (st.produced_crafters[name] and st.produced_crafters[name][q] or 0)
              + (st.recycled_out[name] and st.recycled_out[name][q] or 0)
      local d = st.demand[name] and st.demand[name][q] or 0
      local r = st.intake[name] and st.intake[name][q] or 0
      local fed = st.feed[name] and st.feed[name][q] or 0
      local used = math.min(p, d)
      prod[q] = p
      dem[q] = d
      cons[q] = used
      spent[q] = used + r
      rec[q] = r + fed
      ext[q] = math.max(0, d - used) + fed
      out[q] = math.max(0, p - used - r)
      if out[q] < EPS then out[q] = 0 end
      if ext[q] < EPS or (st.limited and st.made[name] and ext[q] < 1e-6 * d) then ext[q] = 0 end
    end
  end
end

-- Summary per lane: intake, load, and raw material the recyclers had no time to take.
-- Intake is counted like in the iteration: what is available in the lane, limited by its capacity.
local function fill_recyclers(st, result)
  for _, lane in ipairs(st.lane_list) do
    local item = lane.item
    local left_sum, avail_sum = 0, 0
    for q = 1, st.n do
      if lane.allowed[q] then
        left_sum = left_sum + (result.output[item] and result.output[item][q] or 0)
        local have = (st.produced_crafters[item] and st.produced_crafters[item][q] or 0)
                   + (st.recycled_out[item] and st.recycled_out[item][q] or 0)
        local need = st.demand[item] and st.demand[item][q] or 0
        avail_sum = avail_sum + math.max(0, have - need)
      end
    end
    local taken_sum = math.max(0, avail_sum - left_sum) + (lane.feed or 0)
    result.recyclers[#result.recyclers + 1] = {
      item = item,
      quality = lane.key ~= "pool" and lane.key or nil,  -- lane quality index, nil for the "any below threshold" lane
      machines = #lane.machines,
      capacity = lane.capacity,
      intake = taken_sum,
      load = lane.capacity > EPS and (taken_sum / lane.capacity) or 0,
      overflow = left_sum,  -- lane material the recyclers could not take
      feed = lane.feed or 0,  -- topped up from outside (raw item without a chain)
    }
  end
end

-- Items that can come from outside (rows of the Input table and the supply field).
local function fill_external_names(st, result)
  result.external_names = {}
  local ext_seen = {}
  for _, m in ipairs(st.crafters) do
    for _, need in ipairs(m._need) do
      if not st.made[need.name] and not ext_seen[need.name] then
        ext_seen[need.name] = true
        result.external_names[#result.external_names + 1] = need.name
      end
    end
  end
  for _, lane in ipairs(st.lane_list) do
    if (not st.made[lane.item] or lane.is_seed) and not ext_seen[lane.item] then
      ext_seen[lane.item] = true
      result.external_names[#result.external_names + 1] = lane.item
    end
  end
  table.sort(result.external_names)
end

function result_stage.build(st)
  local result = {
    output = {},      -- name -> vec: leaves the area
    external = {},    -- name -> vec: must be supplied from outside
    produced = {},    -- name -> vec: everything made inside
    consumed = {},    -- name -> vec: spent by ordinary machines from internal output
    keep_from = st.keep,
    spent = {},       -- name -> vec: spent inside from internal output (ordinary machines and recyclers)
    demand = {},      -- name -> vec: what ordinary machines want in total (inside + outside)
    recycled = {},    -- name -> vec: taken by recyclers
    recyclers = {},   -- summary per recycler lane
    makers = st.makers,  -- item -> machines that make it
    users = st.users,    -- item -> quality index -> machines that spend it
  }
  fill_balance(st, result, collect_names(st))
  fill_recyclers(st, result)
  -- how many machines idle because of a lack of inflow (limited mode only)
  local throttled, load_sum = 0, 0
  for _, m in ipairs(st.crafters) do
    load_sum = load_sum + m._u
    if m._u < 0.995 then throttled = throttled + 1 end
  end
  fill_external_names(st, result)
  result.throttled = throttled
  result.crafter_count = #st.crafters
  result.average_load = #st.crafters > 0 and load_sum / #st.crafters or 1
  return result
end

return result_stage
