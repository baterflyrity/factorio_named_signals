local util = require("util")
local names = require("scripts.names")
local tint_layers = require("prototypes.tint")

local function tinted_icons(proto)
  if proto.icons then
    local icons = table.deepcopy(proto.icons)
    for _, layer in pairs(icons) do layer.tint = names.tint end
    return icons
  end
  return { { icon = proto.icon, icon_size = proto.icon_size, tint = names.tint } }
end

---------------------------------------------------------------------------
-- Видимая часть: копия сравнивающего комбинатора.
-- Собственная (нативная) логика у неё остаётся пустой и ничего не выдаёт:
-- всё считает Lua, а результат отдаёт скрытый константный комбинатор.
---------------------------------------------------------------------------
local base = data.raw["decider-combinator"]["decider-combinator"]
local entity = table.deepcopy(base)
entity.name = names.combinator
entity.icons = tinted_icons(base)
entity.icon = nil
entity.minable = { mining_time = 0.1, result = names.combinator }
entity.next_upgrade = nil
entity.fast_replaceable_group = nil
tint_layers(entity.sprites, names.tint) -- корпус слегка синий; светодиоды и символы не трогаем

local item = table.deepcopy(data.raw.item["decider-combinator"])
item.name = names.combinator
item.place_result = names.combinator
item.icons = tinted_icons(item)
item.icon = nil
item.order = (item.order or "c") .. "-ns"

local recipe = table.deepcopy(data.raw.recipe["decider-combinator"])
recipe.name = names.combinator
recipe.results = { { type = "item", name = names.combinator, amount = 1 } }
recipe.main_product = nil
recipe.enabled = false

---------------------------------------------------------------------------
-- Скрытая часть: константный комбинатор, через который выдаётся результат.
-- Стоит в той же точке, соединён скриптовыми (невидимыми) проводами.
---------------------------------------------------------------------------
local hidden = table.deepcopy(data.raw["constant-combinator"]["constant-combinator"])
hidden.name = names.output
hidden.hidden = true
hidden.flags = {
  "placeable-off-grid", "not-on-map", "not-blueprintable", "not-deconstructable",
  "hide-alt-info", "no-copy-paste", "not-upgradable",
}
hidden.minable = nil
hidden.selectable_in_game = false
hidden.collision_box = { { -0.1, -0.1 }, { 0.1, 0.1 } }
hidden.collision_mask = { layers = {} }
hidden.sprites = util.empty_sprite()
hidden.activity_led_sprites = util.empty_sprite()
hidden.draw_circuit_wires = false
hidden.corpse = nil
hidden.dying_explosion = nil
hidden.next_upgrade = nil
hidden.fast_replaceable_group = nil

data:extend({ entity, item, recipe, hidden })

local tech = data.raw.technology["circuit-network"]
if tech then
  tech.effects = tech.effects or {}
  table.insert(tech.effects, { type = "unlock-recipe", recipe = names.combinator })
else
  recipe.enabled = true
end

require("prototypes.relay")
