-- Смоук data-стадии: заглушка data.raw с той же структурой, что у base.
local function deepcopy(o)
  if type(o) ~= "table" then return o end
  local r = {}
  for k, v in pairs(o) do r[k] = deepcopy(v) end
  return r
end
table.deepcopy = deepcopy
package.preload["util"] = function()
  return {
    by_pixel = function(x, y) return { x / 32, y / 32 } end,
    by_pixel_hr = function(x, y) return { x / 64, y / 64 } end,
    empty_sprite = function() return { filename = "__core__/graphics/empty.png", width = 1, height = 1 } end,
    table = { deepcopy = deepcopy },
  }
end

local extended = {}
data = { raw = {}, extend = function(self, list) for _, p in ipairs(list) do
  extended[#extended + 1] = p
  data.raw[p.type] = data.raw[p.type] or {}
  data.raw[p.type][p.name] = p
end end }

local function sprite(f) return { filename = f, width = 10, height = 10 } end
local cp = { wire = { copper = { 0, -3 }, red = { 0.5, -3 }, green = { -0.5, -3 } },
             shadow = { copper = { 3, 0 }, red = { 3.5, 0 }, green = { 2.5, 0 } } }
data.raw["decider-combinator"] = { ["decider-combinator"] = { type = "decider-combinator", name = "decider-combinator", icon = "i.png", icon_size = 64,
  sprites = { north = { layers = { { filename = "body.png" }, { filename = "shadow.png", draw_as_shadow = true } } } },
  activity_led_sprites = { north = { filename = "led.png", draw_as_glow = true } } } }
data.raw["constant-combinator"] = { ["constant-combinator"] = { type = "constant-combinator", name = "constant-combinator", icon = "i.png" } }
data.raw["electric-pole"] = { ["medium-electric-pole"] = {
  type = "electric-pole", name = "medium-electric-pole", icon = "pole.png", max_health = 100,
  collision_box = { { -0.15, -0.15 }, { 0.15, 0.15 } }, selection_box = { { -0.5, -0.5 }, { 0.5, 0.5 } },
  maximum_wire_distance = 9, supply_area_distance = 3.5,
  radius_visualisation_picture = { filename = "radius.png", width = 12, height = 12 },
  pictures = { layers = {
    { filename = "pole.png", width = 84, height = 252, direction_count = 4 },
    { filename = "pole-shadow.png", width = 280, height = 64, direction_count = 4, draw_as_shadow = true },
  } },
  connection_points = { cp, cp, cp, cp },
} }
data.raw["power-switch"] = { ["power-switch"] = {
  type = "power-switch", name = "power-switch", icon = "ps.png",
  power_on_animation = { layers = { sprite("ps.png") } },
  overlay_start = sprite("start.png"), overlay_loop = sprite("loop.png"),
  led_on = sprite("led.png"), led_off = sprite("led.png"),
  left_wire_connection_point = {}, right_wire_connection_point = {}, circuit_wire_connection_point = {},
  wire_max_distance = 10, overlay_start_delay = 3,
} }
data.raw.item = {
  ["decider-combinator"] = { type = "item", name = "decider-combinator", icon = "i.png", icon_size = 64 },
  ["medium-electric-pole"] = { type = "item", name = "medium-electric-pole", icon = "pole.png", order = "a[energy]-b" },
}
data.raw.recipe = {
  ["decider-combinator"] = { type = "recipe", name = "decider-combinator", ingredients = {
    { type = "item", name = "copper-cable", amount = 5 }, { type = "item", name = "electronic-circuit", amount = 5 } }, results = {} },
  ["medium-electric-pole"] = { type = "recipe", name = "medium-electric-pole", ingredients = {
    { type = "item", name = "iron-stick", amount = 4 }, { type = "item", name = "steel-plate", amount = 2 },
    { type = "item", name = "copper-cable", amount = 2 } } },
  ["power-switch"] = { type = "recipe", name = "power-switch", energy_required = 2, ingredients = {
    { type = "item", name = "iron-plate", amount = 5 }, { type = "item", name = "copper-cable", amount = 5 },
    { type = "item", name = "electronic-circuit", amount = 2 } } },
}
data.raw.technology = {
  ["electric-energy-distribution-1"] = { effects = { { type = "unlock-recipe", recipe = "medium-electric-pole" } } },
  ["circuit-network"] = { effects = {} },
}

dofile(MOD .. "/data.lua")

local mast = data.raw["electric-pole"]["ns-relay-mast"]
local relay = data.raw["power-switch"]["ns-relay-pole"]
local input = data.raw["electric-pole"]["ns-relay-pole-input"]
local recipe = data.raw.recipe["ns-relay-pole"]
local item = data.raw.item["ns-relay-pole"]
assert(mast and relay and input and recipe and item, "prototypes missing")
assert(item.place_result == "ns-relay-mast" and mast.placeable_by.item == "ns-relay-pole" and mast.minable.result == "ns-relay-pole", "item links")
assert(mast.supply_area_distance == 3.5 and mast.maximum_wire_distance == 9 and mast.auto_connect_up_to_n_wires == 0, "mast")
assert(mast.pictures.layers[1].tint and not mast.pictures.layers[2].tint, "mast tint")
assert(relay.hidden and relay.selectable_in_game == false and relay.power_on_animation.frame_count == 1, "switch hidden")
assert(input.hidden and input.supply_area_distance < 0.1 and input.maximum_wire_distance <= 0.5, "input")
assert(not data.raw["electric-pole"]["ns-relay-pole-supply"], "old supply removed")
local amounts = {}
for _, i in ipairs(recipe.ingredients) do amounts[i.name] = i.amount end
-- +30% к сумме (4 стержня, 2 стали, 7 проводов, 5 пластин, 2 схемы), округление вверх
assert(amounts["iron-stick"] == 6 and amounts["steel-plate"] == 3 and amounts["copper-cable"] == 10
  and amounts["iron-plate"] == 7 and amounts["electronic-circuit"] == 3, "relay +30%")
local dc_amounts = {}
for _, i in ipairs(data.raw.recipe["ns-decider-combinator"].ingredients) do dc_amounts[i.name] = i.amount end
assert(dc_amounts["copper-cable"] == 8 and dc_amounts["electronic-circuit"] == 8, "combinator +50%")
assert(#data.raw.recipe["decider-combinator"].ingredients == 2 and data.raw.recipe["decider-combinator"].ingredients[1].amount == 5, "vanilla untouched")
local cost = require("prototypes.cost")
assert(cost.scale({ { name = "x", amount = 2 } }, 1.5)[1].amount == 3, "exact product not rounded up")
assert(cost.scale({ { type = "fluid", name = "water", amount = 10 } }, 1.3)[1].amount == 13, "fluid exact")
assert(recipe.energy_required == 2.5, "energy")
local found = false
for _, e in ipairs(data.raw.technology["electric-energy-distribution-1"].effects) do
  if e.recipe == "ns-relay-pole" then found = true end
end
assert(found, "tech unlock")
local dc = data.raw["decider-combinator"]["ns-decider-combinator"]
assert(dc.sprites.north.layers[1].tint and not dc.sprites.north.layers[2].tint and not dc.activity_led_sprites.north.tint, "combinator tint")
assert(not data.raw["decider-combinator"]["decider-combinator"].sprites.north.layers[1].tint, "vanilla untouched")
print("data stage: OK, prototypes: " .. #extended)
