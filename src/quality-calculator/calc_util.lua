-- Shared pure helpers for the calculation core (no game API).
local util = {}

util.EPS = 1e-12
local EPS = util.EPS

-- Quality distribution of a result at roll chance `chance` (0.1 = 10%) when the base quality is chain[base].
-- chain: array of {next_probability=, chain_probability=}, lowest quality first.
-- The quality goes up one step with probability chance * next_probability; from the reached level it goes up
-- again with that level's chain_probability, and so on up to the highest quality.
function util.roll(chain, base, chance)
  local n = #chain
  local dist = {}
  for i = 1, n do dist[i] = 0 end
  if n == 0 then return dist end
  if base < 1 then base = 1 elseif base > n then base = n end
  local p = 0
  if chance > 0 and base < n then
    p = chance * (chain[base].next_probability or 1)
    if p > 1 then p = 1 end
  end
  dist[base] = 1 - p
  local carry = p
  local j = base + 1
  while carry > EPS and j <= n do
    local cp = 0
    if j < n then cp = chain[j].chain_probability or 0 end
    dist[j] = dist[j] + carry * (1 - cp)
    carry = carry * cp
    j = j + 1
  end
  return dist
end

-- Expected items of a product per craft, with productivity applied.
-- prod: {amount_avg=, probability=, extra_count_fraction=, ignored_by_productivity=}
function util.product_per_craft(prod, productivity)
  local p = prod.probability or 1
  local avg = prod.amount_avg or 0
  local base = p * (avg + (prod.extra_count_fraction or 0))
  local ignored = math.min(prod.ignored_by_productivity or 0, avg) * p
  return base + productivity * math.max(0, base - ignored)
end

-- Chance to get at least one item of the wanted quality in a period.
-- items: how many items (any quality) come out per period (may be fractional), p: chance of the wanted quality
-- for one item. Machines work evenly, so a random period gives either floor(items) or ceil(items) items, weighted
-- by the fractional part; for a whole count the chance is 1 - (1 - p)^count.
function util.chance_at_least_one(items, p)
  if items <= 0 or p <= 0 then return 0 end
  if p >= 1 then return math.min(1, items) end
  local whole = math.floor(items)
  local frac = items - whole
  local function at_least_one(count) return 1 - (1 - p) ^ count end
  return (1 - frac) * at_least_one(whole) + frac * at_least_one(whole + 1)
end

-- Returns t[name], creating a zero vector of length n when missing.
function util.vec(t, name, n)
  local v = t[name]
  if not v then
    v = {}
    for i = 1, n do v[i] = 0 end
    t[name] = v
  end
  return v
end

-- Adds the output of machine m into `into`: crafts_per_s crafts per second, base quality `base`.
-- roll(base, chance) -> quality distribution (in the game this is LuaQualityPrototype.get_roll_chances).
function util.add_products(into, m, crafts_per_s, base, n, roll)
  local dist = roll(base, m.quality_chance or 0)
  local base_only = {}
  for i = 1, n do base_only[i] = 0 end
  base_only[math.min(math.max(base, 1), n)] = 1
  for _, prod in ipairs(m.products) do
    local amount = util.product_per_craft(prod, m.productivity or 0) * crafts_per_s
    if amount > 0 then
      local d = dist
      if prod.affected_by_quality == false then d = base_only end
      if prod.quality_change and prod.quality_change ~= 0 and prod.affected_by_quality ~= false then
        d = roll(base + prod.quality_change, m.quality_chance or 0)
      end
      local v = util.vec(into, prod.name, n)
      for i = 1, n do v[i] = v[i] + amount * d[i] end
    end
  end
end

-- Cached roll: uses input.roll from the game when given, otherwise our own util.roll.
function util.make_roll(input, chain)
  local n = #chain
  local cache = {}
  return function(base, chance)
    base = math.min(math.max(base, 1), n)
    if chance < 0 then chance = 0 end
    local key = base .. ":" .. chance
    local v = cache[key]
    if not v then
      v = input.roll and input.roll(base, chance) or util.roll(chain, base, chance)
      cache[key] = v
    end
    return v
  end
end

return util
