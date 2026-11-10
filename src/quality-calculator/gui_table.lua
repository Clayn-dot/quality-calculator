-- quality-calculator: result tables of the window (output and input), number formatting and tooltips.
-- Look follows Rate Calculator: icons instead of names (names are in tooltips), nested frames.

local calc = require("calc")

local tbl = {}

tbl.PERIODS = {
  {seconds = 1, key = "qcalc.period-1"},
  {seconds = 60, key = "qcalc.period-60"},
  {seconds = 600, key = "qcalc.period-600"},
  {seconds = 3600, key = "qcalc.period-3600"},
}
local PERIODS = tbl.PERIODS

local RED = {1, 0.59, 0.59}
local GRAY = {0.65, 0.65, 0.65}
local GREEN = {0.59, 1, 0.59}
tbl.RED, tbl.GRAY, tbl.GREEN = RED, GRAY, GREEN
local NUMBER_WIDTH = 64  -- minimum width of a quality column, wider when the longest label needs it
local SLOT_SIZE = 32
local SUPPLY_WIDTH = 88
-- The 64x64 quality pictures are not centered (normal and uncommon are pushed left), so in a cell they looked
-- shifted left from the numbers. The left margin in pixels at icon size 20 moves the picture to the column center
-- (picture center in the game files: 16 and 16.5 of 32, about 30 for the others).
local ICON_SIZE = 20
local ICON_MARGIN = {normal = 10, uncommon = 10, rare = 1, epic = 1, legendary = 1}

-- Fixed number of decimals, never scientific notation ("1e-05"). A very small but non-zero value shows as "<0.01".
-- Big numbers in cells are shortened (123.46K, 1.23M, 4.5B) to fit the column; full = true is for tooltips.
function tbl.fmt(v, decimals, full)
  if v <= 0 then return "-" end
  if not full and v >= 100000 then
    local div, suffix = 1000, "K"
    if v >= 1e9 then div, suffix = 1e9, "B" elseif v >= 1e6 then div, suffix = 1e6, "M" end
    return string.format("%." .. math.min(decimals, 2) .. "f", v / div) .. suffix
  end
  local limit = 10 ^ (-decimals)
  if v < limit then return "<" .. string.format("%." .. decimals .. "f", limit) end
  return string.format("%." .. decimals .. "f", v)
end

-- Percent with the same number of decimals as chosen in the window.
function tbl.pct(v, decimals)
  decimals = decimals or 2
  if v <= 0 then return "0" end
  local limit = 10 ^ (-decimals)
  if v < limit then return "<" .. string.format("%." .. decimals .. "f", limit) end
  return string.format("%." .. decimals .. "f", v)
end

local fmt, pct = tbl.fmt, tbl.pct

local function sum(v, n)
  local s = 0
  for i = 1, n do s = s + v[i] end
  return s
end

-- Table rows: items that have something to show, biggest amount first.
local function rows_of(vecs, n)
  local rows = {}
  for name, v in pairs(vecs) do
    local total = sum(v, n)
    if total > 0 then rows[#rows + 1] = {name = name, v = v, total = total} end
  end
  table.sort(rows, function(a, b)
    if a.total ~= b.total then return a.total > b.total end
    return a.name < b.name
  end)
  return rows
end

-- Which machines make an item and which spend it (for the tooltip).
local function machines_text(map)
  if not map then return "" end
  local list = {}
  for _, r in pairs(map) do list[#list + 1] = r end
  table.sort(list, function(a, b)
    if a.count ~= b.count then return a.count > b.count end
    return tostring(a.entity) < tostring(b.entity)
  end)
  local parts = {}
  for i, r in ipairs(list) do
    if i > 6 then parts[#parts + 1] = "..." break end
    parts[#parts + 1] = r.count .. " × [entity=" .. tostring(r.entity) .. ",quality=" .. r.quality .. "]"
  end
  return table.concat(parts, "   ")
end

-- Tooltip of an item icon: its name and who makes and spends it.
local function item_tooltip(result, name)
  local proto = prototypes.item[name]
  local title = proto and proto.localised_name or name
  ---@type any[]
  local lines = {"", title}
  local made = machines_text(result.makers and result.makers[name])
  if made ~= "" then
    lines[#lines + 1] = "\n"
    lines[#lines + 1] = {"qcalc.tip-makers", made}
  end
  local used = {}
  for _, per_quality in pairs(result.users and result.users[name] or {}) do
    for key, r in pairs(per_quality) do
      local u = used[key]
      if not u or r.count > u.count then used[key] = r end
    end
  end
  local used_text = machines_text(used)
  if used_text ~= "" then
    lines[#lines + 1] = "\n"
    lines[#lines + 1] = {"qcalc.tip-users", used_text}
  end
  return lines
end

-- Element at the column center: springs on both sides stretch equally, so all cells of a column share one center
-- however different the number widths are (the game does not align the labels themselves here).
local function centered(parent)
  local row = parent.add{type = "flow", direction = "horizontal"}
  row.style.horizontally_stretchable = true
  row.style.horizontal_spacing = 0
  row.style.vertical_align = "center"
  local left = row.add{type = "empty-widget"}
  left.style.horizontally_stretchable = true
  return row, function()
    local right = row.add{type = "empty-widget"}
    right.style.horizontally_stretchable = true
  end
end

local function number_label(parent, caption, tooltip)
  local row, close = centered(parent)
  local l = row.add{type = "label", caption = caption, tooltip = tooltip}
  close()
  return l
end

-- Number for a text field, without trailing zeros.
local function fmt_input(v)
  local text = string.format("%.2f", v)
  text = text:gsub("0+$", ""):gsub("%.$", "")
  return text
end

-- Panel frame with a header strip; returns the body to put content into.
local function add_panel(parent, title_key)
  local panel = parent.add{type = "frame", style = "inside_deep_frame", direction = "vertical"}
  local head = panel.add{type = "frame", style = "subheader_frame"}
  head.style.horizontally_stretchable = true
  head.add{type = "label", caption = {title_key}, style = "subheader_caption_label"}
  local body = panel.add{type = "flow", direction = "vertical"}
  body.style.padding = 8
  return body
end

-- Column width from the longest label of the table (a pixel estimate), one for all columns: the header and the
-- cells get exactly the same width and center, and the window is no wider than needed.
local function column_width(rows, n, result, seconds, decimals, with_share)
  local widest = 0
  local function take(text, per_char)
    widest = math.max(widest, #text * per_char)
  end
  for _, row in ipairs(rows) do
    local produced = result.produced and result.produced[row.name]
    local spent = result.spent and result.spent[row.name]
    for i = 1, n do
      take(fmt(row.v[i] * seconds, decimals), 8.5)
      if with_share and row.total > 0 then take(pct(row.v[i] / row.total * 100, decimals) .. "%", 7) end
      if with_share and produced then take("+" .. fmt(produced[i] * seconds, decimals), 7) end
      if with_share and spent then take("-" .. fmt(spent[i] * seconds, decimals), 7) end
    end
  end
  return math.max(NUMBER_WIDTH, math.ceil(widest) + 16)
end

local function add_header(t, ctx)
  t.add{type = "empty-widget"}
  for _, q in ipairs(ctx.chain) do
    local cell = t.add{type = "flow", direction = "vertical"}
    cell.style.width = ctx.colw
    local row, close = centered(cell)
    local icon = row.add{type = "sprite", sprite = "quality/" .. q.name, tooltip = q.localised_name}
    icon.resize_to_sprite = false
    icon.style.size = ICON_SIZE
    icon.style.left_margin = ICON_MARGIN[q.name] or 0
    close()
  end
  if ctx.supply_of then
    local cell = t.add{type = "flow", direction = "vertical"}
    cell.style.width = SUPPLY_WIDTH
    local row, close = centered(cell)
    row.add{type = "label", caption = {"qcalc.supply-header"}, tooltip = {"qcalc.supply-header-tooltip"}}
    close()
  end
end

-- Recycler lane that works on this quality of the item (how much it really takes, and how much at full supply).
local function lane_of(ctx, name, i)
  local lane
  for _, r in ipairs(ctx.with_share and ctx.result.recyclers or {}) do
    if r.item == name and (r.quality == i or (r.quality == nil and i <= (ctx.result.keep_from or ctx.n))) then
      lane = r
    end
  end
  return lane
end

-- Tooltip of a number cell: share and chance, made/spent balance, recycler load.
local function cell_tooltip(ctx, row, i, amount, made, used, show_balance, lane)
  local decimals = ctx.decimals
  ---@type any[]
  local tip = {""}
  if ctx.with_share and amount > 0 then
    local share = row.v[i] / row.total
    local chance = calc.chance_at_least_one(row.total * ctx.seconds, share) * 100
    tip[#tip + 1] = {"qcalc.cell-tooltip", ctx.chain[i].localised_name, fmt(amount, decimals, true),
      pct(share * 100, decimals), pct(chance, decimals)}
  end
  if show_balance then
    if #tip > 1 then tip[#tip + 1] = "\n" end
    tip[#tip + 1] = {"qcalc.cell-balance", fmt(made, decimals, true), fmt(used, decimals, true),
      fmt(math.max(0, made - used), decimals, true)}
  end
  if lane and show_balance then
    tip[#tip + 1] = "\n"
    tip[#tip + 1] = {"qcalc.cell-recyclers", fmt(used, decimals, true), fmt(lane.capacity * ctx.seconds, decimals, true)}
  end
  return #tip > 1 and tip or nil
end

local function small_label(cell, text, color, tooltip)
  local l = number_label(cell, text, tooltip)
  l.style.font = "default-small"
  l.style.font_color = color
end

local function add_cell(t, ctx, row, i, row_balance)
  local decimals, seconds = ctx.decimals, ctx.seconds
  local produced = ctx.result.produced and ctx.result.produced[row.name]
  local spent = ctx.result.spent and ctx.result.spent[row.name]
  local amount = row.v[i] * seconds
  local made = produced and produced[i] * seconds or 0
  local used = spent and spent[i] * seconds or 0
  local show_balance = row_balance and made > 0
  local cell = t.add{type = "flow", direction = "vertical"}
  cell.style.vertical_spacing = 0
  cell.style.vertical_align = "top"
  cell.style.vertically_stretchable = true
  cell.style.width = ctx.colw
  local tooltip = cell_tooltip(ctx, row, i, amount, made, used, show_balance, lane_of(ctx, row.name, i))
  number_label(cell, (row_balance and amount <= 0) and "0" or fmt(amount, decimals), tooltip)
  if ctx.with_share and amount > 0 then
    small_label(cell, pct(row.v[i] / row.total * 100, decimals) .. "%", GRAY, tooltip)
  end
  -- like Rate Calculator: green is made, red is spent, the number on top is what is left
  if show_balance then
    small_label(cell, "+" .. fmt(made, decimals), GREEN, tooltip)
    small_label(cell, used > 0 and ("-" .. fmt(used, decimals)) or "-", RED, tooltip)
  end
end

-- If anything in the row is spent inside the area, every cell of the row gets the colored lines.
local function has_balance(ctx, row)
  local produced = ctx.result.produced and ctx.result.produced[row.name]
  local spent = ctx.result.spent and ctx.result.spent[row.name]
  if not (ctx.with_share and spent) then return false end
  for i = 1, ctx.n do
    if spent[i] * ctx.seconds > 10 ^ (-ctx.decimals) / 2 and produced[i] > 0 then return true end
  end
  return false
end

local function add_supply_field(t, ctx, row)
  local result, seconds = ctx.result, ctx.seconds
  local value = ctx.supply_of.state.supply and ctx.supply_of.state.supply[row.name]
  local needed = 0
  for i = 1, ctx.n do
    needed = needed + (result.unlimited_external[row.name] and result.unlimited_external[row.name][i] or 0)
  end
  local field = t.add{type = "textfield", text = value and fmt_input(value * seconds) or "", numeric = true,
    allow_decimal = true, allow_negative = false, tags = {qcalc = "supply", item = row.name},
    tooltip = {"qcalc.supply-tooltip", fmt(needed * seconds, ctx.decimals, true)}}
  field.style.width = SUPPLY_WIDTH
end

-- Table: item icon on the left, then a column for every unlocked quality (and the supply field for the input).
-- with_share: under the number a small share of the quality among the item; the tooltip has the chance to get
-- at least one.
local function add_matrix(body, rows, chain, result, seconds, decimals, with_share, supply_of)
  local n = #chain
  local ctx = {chain = chain, n = n, result = result, seconds = seconds, decimals = decimals,
    with_share = with_share, supply_of = supply_of,
    colw = column_width(rows, n, result, seconds, decimals, with_share)}
  local t = body.add{type = "table", column_count = n + 1 + (supply_of and 1 or 0)}
  t.style.horizontal_spacing = 8
  t.style.vertical_spacing = 4
  add_header(t, ctx)
  for _, row in ipairs(rows) do
    local slot = t.add{type = "sprite-button", sprite = "item/" .. row.name, style = "slot_button",
      tooltip = item_tooltip(result, row.name)}
    slot.style.size = SLOT_SIZE
    local row_balance = has_balance(ctx, row)
    for i = 1, n do add_cell(t, ctx, row, i, row_balance) end
    if supply_of then add_supply_field(t, ctx, row) end
  end
end

-- Input rows: every item that can come from outside, even when it is zero right now at the set supply (otherwise
-- the field could not be set back). Sorted by how much is needed without limits.
local function input_rows(result, n)
  local ins = {}
  for _, name in ipairs(result.external_names or {}) do
    local v = result.external[name] or {}
    local full = result.unlimited_external[name] or v
    local vec = {}
    for i = 1, n do vec[i] = v[i] or 0 end
    ins[#ins + 1] = {name = name, v = vec, total = sum(full, n)}
  end
  table.sort(ins, function(a, b)
    if a.total ~= b.total then return a.total > b.total end
    return a.name < b.name
  end)
  return ins
end

-- Warning only when needed: recyclers lack capacity.
local function add_overflow_warnings(scroll, result, seconds, decimals, period)
  for _, r in ipairs(result.recyclers) do
    if r.overflow * seconds > 10 ^ (-decimals) / 2 then
      local proto = prototypes.item[r.item]
      local warn = scroll.add{type = "label", caption = {"qcalc.recycler-overflow",
        {"", "[item=" .. r.item .. "] ", proto and proto.localised_name or r.item},
        fmt(r.overflow * seconds, decimals), {period.key}}}
      warn.style.font_color = RED
      warn.style.single_line = false
      warn.style.maximal_width = 440
    end
  end
end

-- Draws the tables from a finished calculation last = {chain, stats, result} (kept in state.last).
function tbl.build_results(scroll, last, state)
  scroll.clear()
  local chain, result = last.chain, last.result
  local period = PERIODS[state.period] or PERIODS[1]
  local seconds, decimals = period.seconds, state.decimals

  -- output first, then input
  local outs = rows_of(result.output, #chain)
  local output_body = add_panel(scroll, "qcalc.section-output")
  if #outs > 0 then
    add_matrix(output_body, outs, chain, result, seconds, decimals, true)
  else
    output_body.add{type = "label", caption = {"qcalc.empty"}}
  end
  local ins = input_rows(result, #chain)
  if #ins > 0 then
    local input_body = add_panel(scroll, "qcalc.section-input")
    add_matrix(input_body, ins, chain, result, seconds, decimals, false, {state = state})
  end
  add_overflow_warnings(scroll, result, seconds, decimals, period)
end

return tbl
