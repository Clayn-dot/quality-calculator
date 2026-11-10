-- quality-calculator: pure calculation core (no game or script calls), so it can be tested outside the game.
--
-- Model (theoretical maximum, all machines work without downtime and ingredients are supplied):
--   * Ordinary machines (crafters) work at full load. What they make and spend follows from their recipe.
--   * Recyclers take only what other machines made beyond the needs of ordinary machines, and only qualities
--     BELOW the keep_from threshold. Their load is limited by capacity and by the amount of such material.
--   * What ordinary machines lack (after the recyclers' returns) goes to "must be supplied from outside".
--   * Everything else leaves the area: this is the "output".
--
-- Stages: calc_setup (parse machines), calc_solve (iteration), calc_result (final balance).

local util = require("calc_util")
local seeds = require("calc_seeds")
local setup = require("calc_setup")
local solve = require("calc_solve")
local result_stage = require("calc_result")

local calc = {}

calc.roll = util.roll
calc.product_per_craft = util.product_per_craft
calc.chance_at_least_one = util.chance_at_least_one
calc.find_seeds = seeds.find

-- input = {
--   chain = { {name=, next_probability=, chain_probability=}, ... },    -- lowest quality first
--   limited = true: ordinary machines are limited by what the area makes (raw items without a source do not limit),
--   keep_from = quality index in chain (default: the highest): from it up nothing is recycled (mode "pool"),
--   recycler_mode = "pool" (default: any quality below keep_from) or "by-quality" (each recycler takes only
--     the quality m.quality it worked on last time),
--   supply = {item = items per second}: how much of this item is really supplied from outside (all qualities);
--     no entry means unlimited. For raw items the area does not make, and for the item of a recycle-craft loop
--     (calc.find_seeds, it is fed into the lowest recycler lane).
--   machines = { {
--       kind = "crafter" | "recycler",
--       crafts_per_second = crafts per second at full load,
--       productivity = fraction (0.5 = +50%), quality_chance = fraction,
--       quality = quality index of the recipe in chain (crafter: quality of ingredients and base quality of products),
--       ingredients = { {name=, amount=}, ... }   -- items only
--       products = { {name=, amount_avg=, probability=, extra_count_fraction=, ignored_by_productivity=,
--                     affected_by_quality=, quality_change=}, ... }
--       recycler_item = name of the recycled item (recycler only; its ingredients[1].amount = items per craft)
--   }, ... }
-- }
-- Returns the result table (see calc_result.lua).
function calc.run(input)
  local unlimited
  if input.supply and next(input.supply) then
    local plain = {}
    for k, v in pairs(input) do
      if k ~= "supply" then plain[k] = v end
    end
    unlimited = calc.run(plain)
  end
  local st = setup.build(input)
  solve.run(st)
  local result = result_stage.build(st)
  result.unlimited_external = unlimited and unlimited.external or result.external
  return result
end

return calc
