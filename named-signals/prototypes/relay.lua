-- ЛЭП-реле: средняя опора ЛЭП, которая включается и выключается как выключатель питания.
--
-- Устройство (составная сущность, как у комбинатора):
--   ns-relay-pole        — видимая часть, тип power-switch. Окно, условие по
--                          сигналу, ручной тумблер и медный вход — родные игровые.
--                          Выглядит как средняя опора ЛЭП в синем цвете.
--   ns-relay-pole-supply — скрытая опора с зоной 7x7 в той же точке. Соединена
--                          скриптовым (невидимым) медным проводом с выходом реле.
-- Реле включено -> входная сеть соединена с опорой -> зона питается.
-- Реле выключено -> опора отрезана. Переключение делает движок, без Lua на тиках.
local util = require("util")
local names = require("scripts.names")

local pole = data.raw["electric-pole"]["medium-electric-pole"]
local switch = data.raw["power-switch"]["power-switch"]

-- Покрасить все обычные слои спрайта (тени и свечение не трогаем).
local function tint_layers(node)
  if type(node) ~= "table" then return end
  if node.filename and not node.draw_as_shadow and not node.draw_as_glow and node.blend_mode ~= "additive" then
    node.tint = names.relay_tint
  end
  for _, v in pairs(node) do
    if type(v) == "table" then tint_layers(v) end
  end
end

-- Кадр опоры «первое направление» из листа с 4 направлениями -> Animation на 1 кадр.
local function pole_frame(layer)
  local a = table.deepcopy(layer)
  a.direction_count = nil
  a.x = 0
  a.y = 0
  a.frame_count = 1
  return a
end

local pole_layers = pole.pictures.layers
local cp = pole.connection_points[1]

---------------------------------------------------------------------------
-- Видимая часть
---------------------------------------------------------------------------
local relay = table.deepcopy(switch)
relay.name = names.relay
relay.icons = { { icon = pole.icon, icon_size = pole.icon_size or 64, tint = names.relay_tint } }
relay.icon = nil
relay.minable = { mining_time = 0.1, result = names.relay }
relay.fast_replaceable_group = nil
relay.next_upgrade = nil
relay.max_health = pole.max_health
relay.resistances = table.deepcopy(pole.resistances)
relay.corpse = pole.corpse
relay.dying_explosion = pole.dying_explosion
relay.collision_box = table.deepcopy(pole.collision_box)
relay.selection_box = table.deepcopy(pole.selection_box)
relay.drawing_box_vertical_extension = pole.drawing_box_vertical_extension
relay.damaged_trigger_effect = table.deepcopy(pole.damaged_trigger_effect)
relay.water_reflection = table.deepcopy(pole.water_reflection)
relay.wire_max_distance = pole.maximum_wire_distance -- 9, как у средней опоры

-- Модель: средняя опора, слегка синяя.
relay.power_on_animation = { layers = { pole_frame(pole_layers[1]), pole_frame(pole_layers[2]) } }
tint_layers(relay.power_on_animation)

-- Индикатор состояния (зелёный/красный светодиод) и искры при включении
-- переносим на голову опоры и уменьшаем.
local head = util.by_pixel(8, -86)
relay.led_on.shift = head
relay.led_off.shift = head
relay.led_on.scale = 0.35
relay.led_off.scale = 0.35
relay.overlay_start.shift = util.by_pixel(8, -96)
relay.overlay_loop.shift = util.by_pixel(8, -100)
relay.overlay_start.scale = 0.3
relay.overlay_loop.scale = 0.3

-- Точки подключения проводов: как у средней опоры.
relay.left_wire_connection_point = { wire = { copper = cp.wire.copper }, shadow = { copper = cp.shadow.copper } }
relay.right_wire_connection_point = { wire = { copper = cp.wire.copper }, shadow = { copper = cp.shadow.copper } }
relay.circuit_wire_connection_point = {
  wire = { red = cp.wire.red, green = cp.wire.green },
  shadow = { red = cp.shadow.red, green = cp.shadow.green },
}

---------------------------------------------------------------------------
-- Скрытая опора: только зона питания 7x7
---------------------------------------------------------------------------
local supply = table.deepcopy(pole)
supply.name = names.relay_supply
supply.hidden = true
supply.flags = {
  "placeable-off-grid", "not-on-map", "not-blueprintable", "not-deconstructable",
  "hide-alt-info", "no-copy-paste", "not-upgradable",
}
supply.minable = nil
supply.selectable_in_game = false
supply.collision_box = { { -0.1, -0.1 }, { 0.1, 0.1 } }
supply.collision_mask = { layers = {} }
supply.corpse = nil
supply.dying_explosion = nil
supply.fast_replaceable_group = nil
supply.next_upgrade = nil
supply.supply_area_distance = pole.supply_area_distance -- 3.5 -> 7x7
-- Почти нулевая дальность провода: никакая чужая опора не подключится к ней
-- автоматически, иначе питание шло бы в обход реле.
supply.maximum_wire_distance = 0.5
supply.auto_connect_up_to_n_wires = 0
supply.draw_copper_wires = false
supply.draw_circuit_wires = false
supply.pictures = {
  filename = "__core__/graphics/empty.png", priority = "extra-high",
  width = 1, height = 1, direction_count = 1,
}
supply.connection_points = { table.deepcopy(cp) }
supply.water_reflection = nil

---------------------------------------------------------------------------
-- Предмет, рецепт (сумма средней опоры и выключателя), технология
---------------------------------------------------------------------------
local item = table.deepcopy(data.raw.item["medium-electric-pole"])
item.name = names.relay
item.place_result = names.relay
item.icons = { { icon = pole.icon, icon_size = pole.icon_size or 64, tint = names.relay_tint } }
item.icon = nil
item.order = (item.order or "a") .. "-ns"

local function merged_ingredients(...)
  local acc, order = {}, {}
  for _, r in ipairs({ ... }) do
    for _, ing in ipairs(r.ingredients or {}) do
      local key = (ing.type or "item") .. "/" .. ing.name
      if not acc[key] then
        acc[key] = { type = ing.type or "item", name = ing.name, amount = 0 }
        order[#order + 1] = key
      end
      acc[key].amount = acc[key].amount + (ing.amount or 1)
    end
  end
  local res = {}
  for _, k in ipairs(order) do res[#res + 1] = acc[k] end
  return res
end

local r_pole = data.raw.recipe["medium-electric-pole"]
local r_switch = data.raw.recipe["power-switch"]
local recipe = {
  type = "recipe",
  name = names.relay,
  enabled = false,
  energy_required = (r_pole.energy_required or 0.5) + (r_switch.energy_required or 0.5),
  ingredients = merged_ingredients(r_pole, r_switch),
  results = { { type = "item", name = names.relay, amount = 1 } },
}

data:extend({ relay, supply, item, recipe })

-- Открывается той же технологией, что и средняя опора ЛЭП.
local unlocked = false
for _, tech in pairs(data.raw.technology) do
  for _, eff in pairs(tech.effects or {}) do
    if eff.type == "unlock-recipe" and eff.recipe == "medium-electric-pole" then
      table.insert(tech.effects, { type = "unlock-recipe", recipe = names.relay })
      unlocked = true
      break
    end
  end
end
if not unlocked then recipe.enabled = true end
