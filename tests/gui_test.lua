-- Смоук окна на имитации LuaGuiElement с правилами движка, на которых мы уже падали.
dofile(TESTS .. "/tests_env.lua")
local signals = require("scripts.signals")
local logic = require("scripts.logic")
local combinator = require("scripts.combinator")
local sources = require("scripts.sources")
local gui = require("scripts.gui")

local RESERVED = { text = 1, caption = 1, name = 1, style = 1, type = 1, tags = 1, parent = 1, children = 1, value = 1,
  state = 1, sprite = 1, tooltip = 1, visible = 1, enabled = 1, items = 1, location = 1, number = 1, index = 1 }
local FLOW_ONLY = { vertical_spacing = 1, horizontal_spacing = 1, vertical_align = 1, horizontal_align = 1 }
local STYLES = STYLE_TYPES -- имя стиля -> тип, из factorio-data

local function new_style(el)
  return setmetatable({}, { __newindex = function(t, k, v)
    if FLOW_ONLY[k] and el.type ~= "flow" then error(k .. " on " .. el.type) end
    rawset(t, k, v)
  end })
end

local function element(type_, props)
  local el = { type = type_, children_list = {}, valid = true }
  for k, v in pairs(props or {}) do el[k] = v end
  el.style = new_style(el)
  if props and props.style then
    local st = STYLES[props.style]
    if not st then error("unknown style " .. props.style) end
    el.style.name = props.style
  end
  el.children = el.children_list
  function el.add(p)
    if p.name and RESERVED[p.name] then error("reserved child name " .. p.name) end
    local child = element(p.type, p)
    child.parent = el
    el.children_list[#el.children_list + 1] = child
    if p.name then el[p.name] = child end
    return child
  end
  function el.clear() for _, ch in ipairs(el.children_list) do if ch.name then el[ch.name] = nil end end; el.children_list = {}; el.children = el.children_list end
  function el.destroy() el.valid = false; if el.parent and el.name then el.parent[el.name] = nil end end
  function el.force_auto_center() end
  return setmetatable(el, { __newindex = function(t, k, v)
    if k == "style" and type(v) == "string" then
      if not STYLES[v] then error("unknown style " .. v) end
      local s = new_style(t); s.name = v; rawset(t, "style", s); return
    end
    rawset(t, k, v)
  end })
end

local screen, relative = element("screen"), element("relative")
local player = { index = 1, gui = { screen = screen, relative = relative } }
game = { get_player = function() return player end }

-- Комбинатор с богатым конфигом: группа, агрегат, «каждый», константа, выход «все» с источника
local chest = SOURCE_CHEST
sources.set_name(chest, "Склад А")
local c = COMBINATOR
c.config = logic.normalize({
  conditions = {
    { left = { signal = { type = "virtual", name = "signal-each" }, source = "Склад А", agg = "min" }, comparator = "<",
      right = { signal = { type = "virtual", name = "signal-each" } } },
    { join = "or", left = { signal = { type = "item", name = "iron-plate" } }, comparator = ">", right = { constant = 5 } },
  },
  outputs = {
    { signal = { type = "virtual", name = "signal-everything" }, mode = "input", source = "Склад А", agg = "max" },
    { signal = { type = "virtual", name = "signal-A" }, mode = "one" },
  },
})
storage.combinators[c.entity.unit_number] = c
combinator.refresh_members(c)
combinator.update(c)

gui.open(player, c)
local frame = screen.ns_combinator
assert(frame, "frame")
local conds = frame.ns_content.ns_conds.ns_list
assert(conds.row_1.ns_val_left and conds.row_1.ns_val_right, "value labels in condition")
assert(conds.row_1.ns_val_left.caption:find("сигн"), "wildcard caption: " .. tostring(conds.row_1.ns_val_left.caption))
assert(conds.row_2.ns_val_left.caption:find("="), "plain caption")
assert(not conds.row_2.ns_val_right, "constant has no value label")
local outs = frame.ns_content.ns_outs.ns_list
assert(outs.row_1.ns_val_out, "output value label")
local sig_buttons = 0
for _, ch in ipairs(outs.row_1.children_list) do if ch.type == "choose-elem-button" then sig_buttons = sig_buttons + 1 end end
assert(sig_buttons == 1, "single signal button in output row")
assert(conds.row_1.ns_val_left.tooltip:find("Склад А"), "tooltip header")

gui.tick()
gui.refresh_for(c)
gui.toggle_help(player)
assert(screen.ns_help, "help")
gui.toggle_help(player)
gui.open_source_panel(player, chest)
gui.tick()
print("gui smoke: OK")
