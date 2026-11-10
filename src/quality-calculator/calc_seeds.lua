-- Finds items that loop inside the area (recycled, then crafted again) and are fed from outside.
local seeds = {}

-- Returns {{item=, q=, pool=}, ...}. A loop does not start by itself, so the supply goes into the lowest
-- lane of such an item. Used by the input.limited mode.
function seeds.find(input)
  local n = #input.chain
  local by_quality = input.recycler_mode == "by-quality"
  local crafted, sourced, edges, lowest = {}, {}, {}, {}
  local function edge(a, b)
    edges[a] = edges[a] or {}
    edges[a][b] = true
  end
  for _, m in ipairs(input.machines) do
    if m.kind == "recycler" then
      local item = m.recycler_item
      local q = by_quality and math.min(math.max(m.quality or 1, 1), n) or "pool"
      local low = lowest[item]
      if q == "pool" then
        lowest[item] = "pool"
      elseif low == nil or (low ~= "pool" and q < low) then
        lowest[item] = q
      end
      for _, prod in ipairs(m.products) do edge(item, prod.name) end
    else
      for _, prod in ipairs(m.products) do
        crafted[prod.name] = true
        -- drills and similar: the item exists without any loop, no need to start it from outside
        if #m.ingredients == 0 then sourced[prod.name] = true end
        for _, ing in ipairs(m.ingredients) do edge(ing.name, prod.name) end
      end
    end
  end
  local found_list = {}
  for item, low in pairs(lowest) do
    if crafted[item] and not sourced[item] then
      local seen, stack, found = {}, {}, false
      for nxt in pairs(edges[item] or {}) do stack[#stack + 1] = nxt end
      while #stack > 0 and not found do
        local cur = table.remove(stack)
        if cur == item then
          found = true
        elseif not seen[cur] then
          seen[cur] = true
          for nxt in pairs(edges[cur] or {}) do stack[#stack + 1] = nxt end
        end
      end
      if found then found_list[#found_list + 1] = {item = item, q = low == "pool" and 1 or low, pool = low == "pool"} end
    end
  end
  table.sort(found_list, function(a, b) return a.item < b.item end)
  return found_list
end

return seeds
