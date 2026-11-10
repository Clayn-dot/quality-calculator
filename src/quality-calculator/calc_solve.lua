-- Iterative solver: loads of ordinary machines and intake of recycler lanes until the state settles.
-- Recycler output depends on what they receive, and they receive what everyone made (other recyclers too).
local util = require("calc_util")

local EPS = util.EPS
local vec = util.vec

local solve = {}

local function add_into(target, source, n)
  for name, v in pairs(source) do
    local t = vec(target, name, n)
    for i = 1, n do t[i] = t[i] + v[i] end
  end
end

-- Output of ordinary machines at their current load.
local function crafters_output(st)
  local n = st.n
  local out = {}
  for _, m in ipairs(st.crafters) do
    if m._u > EPS then
      for name, v in pairs(m._prod) do
        local t = vec(out, name, n)
        for i = 1, n do t[i] = t[i] + v[i] * m._u end
      end
    end
  end
  return out
end

-- Equal-share fill: the load of all machines grows evenly until some item runs out; machines that need it stay at
-- the reached level, the others keep growing. Returns the target load per machine.
local function fill_targets(st, total)
  local lim_machines, lim_key, capped = st.lim_machines, st.lim_key, st.capped
  local target = {}
  local active, frozen = {}, {}
  for _, m in ipairs(lim_machines) do
    active[#active + 1] = m
    target[m] = 0
  end
  for _ = 1, #lim_machines + 1 do
    if #active == 0 then break end
    local act = {}
    for _, m in ipairs(active) do
      for _, need in ipairs(m._lim) do act[need.key] = (act[need.key] or 0) + need.rate end
    end
    local level, tops = 1, {}
    for k, a in pairs(act) do
      local name, q = lim_key[k][1], lim_key[k][2]
      local have = total[name] and total[name][q] or 0
      if capped[name] then have = have + capped[name].cap * capped[name].w[q] end
      local t = math.max(0, (have - (frozen[k] or 0)) / a)
      tops[k] = t
      if t < level then level = t end
    end
    for _, m in ipairs(active) do target[m] = level end
    if level >= 1 then break end
    local next_active = {}
    for _, m in ipairs(active) do
      local saturated = false
      for _, need in ipairs(m._lim) do
        if tops[need.key] <= level + 1e-12 then saturated = true end
      end
      if saturated then
        for _, need in ipairs(m._lim) do frozen[need.key] = (frozen[need.key] or 0) + need.rate * level end
      else
        next_active[#next_active + 1] = m
      end
    end
    active = next_active
  end
  return target
end

-- Moves machine loads halfway to their targets. Returns the largest change.
local function update_loads(st, total)
  local udiff = 0
  if not st.limited then return udiff end
  local target = fill_targets(st, total)
  for _, m in ipairs(st.lim_machines) do
    local u = 0.5 * (m._u + target[m])
    udiff = math.max(udiff, math.abs(u - m._u))
    m._u = u
  end
  return udiff
end

-- Demand of ordinary machines at their current load.
local function compute_demand(st)
  local demand = {}
  for _, m in ipairs(st.crafters) do
    for _, need in ipairs(m._need) do
      local v = vec(demand, need.name, st.n)
      v[need.q] = v[need.q] + need.rate * m._u
    end
  end
  return demand
end

-- Outside supply into a lane that the area cannot start by itself (a recycle-craft loop): the lowest lane of
-- the item gets it, up to full capacity or the amount set in the "Available" field.
local function feed_seed(st, lane, sum, lane_taken, new_feed)
  local want = lane.capacity - sum
  local rate = st.input.supply and st.input.supply[lane.item]
  if rate ~= nil then want = math.min(want, rate) end
  lane.feed = want
  lane.is_seed = true
  lane_taken[lane.feed_q] = lane_taken[lane.feed_q] + want
  local fed = vec(new_feed, lane.item, st.n)
  fed[lane.feed_q] = fed[lane.feed_q] + want
end

-- Outside top-up of a lane with no internal source (raw item without a chain), up to full capacity.
local function feed_external(st, lane, sum, lane_taken, new_feed, total, demand)
  local item, n = lane.item, st.n
  lane.feed = lane.capacity - sum
  local cap = st.capped[item]
  if cap then
    -- ordinary machines take from the set supply first, recyclers get the rest
    local crafter_ext = 0
    for q = 1, n do
      crafter_ext = crafter_ext + math.max(0, (demand[item] and demand[item][q] or 0) - (total[item] and total[item][q] or 0))
    end
    lane.feed = math.min(lane.feed, math.max(0, cap.cap - crafter_ext))
  end
  lane_taken[lane.feed_q] = lane_taken[lane.feed_q] + lane.feed
  local fed = vec(new_feed, item, n)
  fed[lane.feed_q] = fed[lane.feed_q] + lane.feed
end

-- Quality items of the lane's item that the lane can take: what is made beyond the demand of ordinary machines.
local function lane_available(st, lane, total, demand)
  local item = lane.item
  local avail, sum = {}, 0
  for q = 1, st.n do
    local a = 0
    if lane.allowed[q] then
      local have = total[item] and total[item][q] or 0
      local need = demand[item] and demand[item][q] or 0
      a = math.max(0, have - need)
    end
    avail[q] = a
    sum = sum + a
  end
  return avail, sum
end

-- One lane: intake from the internal output (limited by capacity), outside top-up, and the lane's products.
local function lane_step(st, lane, total, demand, new_out, new_intake, new_feed)
  local n, item = st.n, lane.item
  local avail, sum = lane_available(st, lane, total, demand)
  local f = 0
  if sum > EPS and lane.capacity > EPS then f = math.min(1, lane.capacity / sum) end
  local taken = vec(new_intake, item, n)
  local lane_taken = {}
  for q = 1, n do
    lane_taken[q] = avail[q] * f
    taken[q] = taken[q] + lane_taken[q]
  end
  lane.feed = 0
  -- internal source other than the lane's own returns (its output from the previous iteration)
  local own_sum = 0
  if lane.own then
    for q = 1, n do
      if lane.allowed[q] then own_sum = own_sum + lane.own[q] end
    end
  end
  local other_sum = math.max(0, sum - own_sum)
  local external_ok = lane.external or ((not st.made[item]) and other_sum <= EPS)
  local seed = st.seed_by_item[item]
  if seed and (lane.key == "pool" or lane.key == seed.q) and lane.capacity > sum + EPS then
    feed_seed(st, lane, sum, lane_taken, new_feed)
  elseif external_ok and lane.capacity > sum + EPS then
    feed_external(st, lane, sum, lane_taken, new_feed, total, demand)
  end
  local lane_out = {}
  for q = 1, n do
    local intake_q = lane_taken[q]
    local unit = lane.unit[q]
    if intake_q > EPS and unit then
      for name, v in pairs(unit) do
        local t = vec(lane_out, name, n)
        for i = 1, n do t[i] = t[i] + intake_q * v[i] end
      end
    end
  end
  add_into(new_out, lane_out, n)
  lane.own = lane_out[item] or vec({}, item, n)
end

-- Largest difference between two output tables.
local function max_diff(a, b, n)
  local diff = 0
  for name, v in pairs(a) do
    local o = b[name]
    for i = 1, n do diff = math.max(diff, math.abs(v[i] - (o and o[i] or 0))) end
  end
  for name, o in pairs(b) do
    local v = a[name]
    for i = 1, n do diff = math.max(diff, math.abs(o[i] - (v and v[i] or 0))) end
  end
  return diff
end

-- Runs the iteration and stores the settled state in st.
function solve.run(st)
  local n = st.n
  st.recycled_out, st.intake, st.feed = {}, {}, {}
  for _ = 1, 400 do
    st.produced_crafters = crafters_output(st)
    local total = {}
    add_into(total, st.produced_crafters, n)
    add_into(total, st.recycled_out, n)
    local udiff = update_loads(st, total)
    local demand = compute_demand(st)
    st.demand = demand
    local new_out, new_intake, new_feed = {}, {}, {}
    for _, lane in ipairs(st.lane_list) do
      lane_step(st, lane, total, demand, new_out, new_intake, new_feed)
    end
    local diff = max_diff(new_out, st.recycled_out, n)
    st.recycled_out, st.intake, st.feed = new_out, new_intake, new_feed
    if diff < 1e-13 and udiff < 1e-13 then break end
  end
  st.demand = st.demand or {}
  st.produced_crafters = st.produced_crafters or {}
end

return solve
