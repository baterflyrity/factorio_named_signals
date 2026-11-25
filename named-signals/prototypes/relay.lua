-- ЛЭП-реле: средняя опора ЛЭП, которая включается и выключается как выключатель питания.
--
-- Составная сущность из трёх частей в одной точке:
--   ns-relay-mast       — ВИДИМАЯ опора (тип electric-pole): модель средней опоры,
--                         зона 7x7, ОДИН медный сокет. Провод игрока сюда только
--                         «приходит» — скрипт сразу переносит его на входную опору.
--   ns-relay-pole       — СКРЫТЫЙ выключатель (power-switch): выход соединён с видимой
--                         опорой, вход — со входной. Рисует светодиод и искры на
--                         голове опоры; его родное окно открывается вместо окна опоры.
--   ns-relay-pole-input — СКРЫТАЯ входная опора: на ней висят провода игрока.
--
-- Выключатель включён -> входная сеть доходит до видимой опоры -> зона питается.
-- Переключение делает движок, без Lua на тиках. Скрипт на тиках только переносит
-- новые провода с видимой опоры на входную.
local util = require("util")
local names = require("scripts.names")
local tint = require("prototypes.tint")

local pole = data.raw["electric-pole"]["medium-electric-pole"]
local switch = data.raw["power-switch"]["power-switch"]
local cp = pole.connection_points[1]

local HIDDEN_FLAGS = {
  "placeable-off-grid", "not-on-map", "not-blueprintable", "not-deconstructable",
  "hide-alt-info", "no-copy-paste", "not-upgradable",
}

local function hide(p)
  p.hidden = true
  p.flags = table.deepcopy(HIDDEN_FLAGS)
  p.minable = nil
  p.selectable_in_game = false
  p.collision_box = { { -0.1, -0.1 }, { 0.1, 0.1 } }
  p.collision_mask = { layers = {} }
  p.corpse = nil
  p.dying_explosion = nil
  p.fast_replaceable_group = nil
  p.next_upgrade = nil
  p.water_reflection = nil
end

local relay_icons = { { icon = pole.icon, icon_size = pole.icon_size or 64, tint = names.relay_tint } }

---------------------------------------------------------------------------
-- Видимая опора
---------------------------------------------------------------------------
local mast = table.deepcopy(pole)
mast.name = names.relay
mast.icons = relay_icons
mast.icon = nil
mast.minable = { mining_time = 0.1, result = names.relay_item }
mast.placeable_by = { item = names.relay_item, count = 1 }
mast.fast_replaceable_group = nil
mast.next_upgrade = nil
mast.auto_connect_up_to_n_wires = 0      -- сама ни к чему не подключается
mast.rewire_neighbours_when_destroying = false
tint(mast.pictures, names.relay_tint)

---------------------------------------------------------------------------
-- Скрытый выключатель: только светодиод и искры на голове опоры
---------------------------------------------------------------------------
local relay_switch = table.deepcopy(switch)
relay_switch.name = names.relay_switch
relay_switch.icons = relay_icons
relay_switch.icon = nil
hide(relay_switch)
relay_switch.max_health = pole.max_health
relay_switch.power_on_animation = {
  filename = "__core__/graphics/empty.png", priority = "extra-high", width = 1, height = 1, frame_count = 1,
}
local head = util.by_pixel(8, -86)
relay_switch.led_on.shift = head
relay_switch.led_off.shift = head
relay_switch.led_on.scale = 0.35
relay_switch.led_off.scale = 0.35
relay_switch.overlay_start.shift = util.by_pixel(8, -96)
relay_switch.overlay_loop.shift = util.by_pixel(8, -100)
relay_switch.overlay_start.scale = 0.3
relay_switch.overlay_loop.scale = 0.3
relay_switch.left_wire_connection_point = { wire = { copper = cp.wire.copper }, shadow = { copper = cp.shadow.copper } }
relay_switch.right_wire_connection_point = { wire = { copper = cp.wire.copper }, shadow = { copper = cp.shadow.copper } }
relay_switch.circuit_wire_connection_point = {
  wire = { red = cp.wire.red, green = cp.wire.green },
  shadow = { red = cp.shadow.red, green = cp.shadow.green },
}
relay_switch.wire_max_distance = pole.maximum_wire_distance

---------------------------------------------------------------------------
-- Скрытая входная опора: провода игрока висят здесь, зону не питает
---------------------------------------------------------------------------
local input = table.deepcopy(pole)
input.name = names.relay_input
input.icons = relay_icons
input.icon = nil
hide(input)
input.supply_area_distance = 0.01      -- практически без зоны: вход не должен ничего питать
input.maximum_wire_distance = 0.5      -- чужие опоры не подключатся к ней автоматически
input.auto_connect_up_to_n_wires = 0
input.rewire_neighbours_when_destroying = false
input.pictures = {
  filename = "__core__/graphics/empty.png", priority = "extra-high",
  width = 1, height = 1, direction_count = 1,
}
input.connection_points = { table.deepcopy(cp) }
input.radius_visualisation_picture = nil

---------------------------------------------------------------------------
-- Предмет, рецепт (сумма средней опоры и выключателя), технология
---------------------------------------------------------------------------
local item = table.deepcopy(data.raw.item["medium-electric-pole"])
item.name = names.relay_item
item.place_result = names.relay
item.icons = relay_icons
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
  name = names.relay_item,
  enabled = false,
  energy_required = (r_pole.energy_required or 0.5) + (r_switch.energy_required or 0.5),
  ingredients = merged_ingredients(r_pole, r_switch),
  results = { { type = "item", name = names.relay_item, amount = 1 } },
}

data:extend({ mast, relay_switch, input, item, recipe })

-- Открывается той же технологией, что и средняя опора ЛЭП.
local unlocked = false
for _, tech in pairs(data.raw.technology) do
  for _, eff in pairs(tech.effects or {}) do
    if eff.type == "unlock-recipe" and eff.recipe == "medium-electric-pole" then
      table.insert(tech.effects, { type = "unlock-recipe", recipe = names.relay_item })
      unlocked = true
      break
    end
  end
end
if not unlocked then recipe.enabled = true end
