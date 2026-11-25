-- Моки Factorio API: ровно то, что используют модули.
defines = {
  wire_connector_id = { circuit_red = 1, circuit_green = 2, combinator_input_red = 3, combinator_input_green = 4,
                        combinator_output_red = 5, combinator_output_green = 6 },
  wire_origin = { script = 2 },
  control_behavior = {
    transport_belt = { content_read_mode = { pulse = 0, hold = 1, entire_belt_hold = 2 } },
    inserter = { hand_read_mode = { pulse = 0, hold = 1 } },
  },
  inventory = { chest = 1 },
  entity_status = { no_power = 99, low_power = 98, working = 1 },
  relative_gui_type = {}, relative_gui_position = {}, gui_type = {},
}
storage = { combinators = {}, sources = {}, open = {}, open_source = {} }
LABELS = {}
rendering = { draw_text = function(p)
  local o = { valid = true, text = p.text, params = p }
  function o.destroy() o.valid = false end
  LABELS[#LABELS + 1] = o
  return o
end }
script = { register_on_object_destroyed = function() end }
package.preload["util"] = function() return { table = { deepcopy = function(t) return t end } } end

local pass, fail = 0, 0
local function check(name, cond)
  if cond then pass = pass + 1 else fail = fail + 1; print("FAIL " .. name) end
end

local signals = require("scripts.signals")
local logic = require("scripts.logic")
local sources = require("scripts.sources")
local combinator = require("scripts.combinator")
require("scripts.gui") -- только проверка, что модуль загружается

local IRON = { type = "item", name = "iron-plate" }
local COPPER = { type = "item", name = "copper-plate" }
local COAL = { type = "item", name = "coal" }
local A = { type = "virtual", name = "signal-A" }
local EACH = { type = "virtual", name = "signal-each" }
local ANY = { type = "virtual", name = "signal-anything" }
local ALL = { type = "virtual", name = "signal-everything" }
local BOTH, ONLY_R, ONLY_G = { red = true, green = true }, { red = true, green = false }, { red = false, green = true }
local K = signals.key

---------------------------------------------------------------------------
-- signals
---------------------------------------------------------------------------
check("key normalize", K({ name = "iron-plate" }) == K({ type = "item", name = "iron-plate", quality = "normal" }))
check("key quality", K(IRON) ~= K({ name = "iron-plate", quality = "rare" }))
local back = signals.from_key(K({ type = "fluid", name = "crude-oil" }))
check("from_key", back.type == "fluid" and back.name == "crude-oil" and back.quality == "normal")
check("rich item", signals.rich(K(IRON)) == "[item=iron-plate]")
check("rich quality", signals.rich(K({ name = "iron-plate", quality = "rare" })) == "[item=iron-plate,quality=rare]")
check("rich virtual", signals.rich(K(A)) == "[virtual-signal=signal-A]")

local m1 = { [K(IRON)] = 10, [K(COAL)] = 4 }
local m2 = { [K(IRON)] = 30 }
local m3 = {}
check("agg sum", signals.aggregate({ m1, m2, m3 }, "sum")[K(IRON)] == 40)
check("agg min counts empty as 0", signals.aggregate({ m1, m2, m3 }, "min")[K(IRON)] == nil)
check("agg min of filled", signals.aggregate({ m1, m2 }, "min")[K(IRON)] == 10)
check("agg max", signals.aggregate({ m1, m2, m3 }, "max")[K(IRON)] == 30)
check("agg avg floors over all", signals.aggregate({ m1, m2, m3 }, "avg")[K(IRON)] == 13)
check("agg count", signals.aggregate({ m1, m2, m3 }, "count")[K(IRON)] == 2 and signals.aggregate({ m1, m2, m3 }, "count")[K(COAL)] == 1)
check("agg empty", next(signals.aggregate({}, "sum")) == nil)

---------------------------------------------------------------------------
-- logic: контекст-заглушка на картах
---------------------------------------------------------------------------
local nets = { red = { [K(IRON)] = 30 }, green = { [K(IRON)] = 120, [K(COPPER)] = 7 } }
local groups = {
  ["Склад А"] = { [K(IRON)] = 50, [K(COPPER)] = 20, [K(COAL)] = 5 },
  ["Склад Б"] = { [K(IRON)] = 100, [K(COPPER)] = 7 },
}
local ctx = { map = function(source, n, agg)
  if source then return groups[source] or {} end
  local m = {}
  if n.red then signals.merge(m, nets.red) end
  if n.green then signals.merge(m, nets.green) end
  return m
end }

local function op(sig, src, n) return { signal = sig, source = src, networks = n or BOTH, agg = "sum" } end
local function cond(l, opr, r)
  local c = logic.new_condition(); c.left = l; c.comparator = opr; c.right = r; return c
end
local function cfg_of(conds, outs) return logic.normalize({ conditions = conds, outputs = outs }) end
local function outmap(outs) local m = {}; for _, o in ipairs(outs) do m[K(o.signal)] = o.count end; return m end

check("network R+G = 150", logic.eval_condition(ctx, cond(op(IRON), "=", { constant = 150 })))
check("network only R = 30", logic.eval_condition(ctx, cond(op(IRON, nil, ONLY_R), "=", { constant = 30 })))
check("network only G = 120", logic.eval_condition(ctx, cond(op(IRON, nil, ONLY_G), "=", { constant = 120 })))
check("A < B", logic.eval_condition(ctx, cond(op(IRON, "Склад А"), "<", op(IRON, "Склад Б"))))

-- «любой» / «все» слева
check("anything @A > 40", logic.eval_condition(ctx, cond(op(ANY, "Склад А"), ">", { constant = 40 })))
check("anything @A > 60 false", not logic.eval_condition(ctx, cond(op(ANY, "Склад А"), ">", { constant = 60 })))
check("everything @A > 4", logic.eval_condition(ctx, cond(op(ALL, "Склад А"), ">", { constant = 4 })))
check("everything @A > 5 false", not logic.eval_condition(ctx, cond(op(ALL, "Склад А"), ">", { constant = 5 })))
check("everything on empty = true", logic.eval_condition(ctx, cond(op(ALL, "Пусто"), ">", { constant = 1000 })))
check("anything on empty = false", not logic.eval_condition(ctx, cond(op(ANY, "Пусто"), ">", { constant = -1 })))
check("right anything invalid", not logic.eval_condition(ctx, cond(op(IRON), ">", op(ANY))))

-- И/ИЛИ
local t = cond(op(IRON), ">", { constant = 0 })
local f = cond(op(IRON), "<", { constant = 0 })
local function with_join(c, j) local x = {}; for k, v in pairs(c) do x[k] = v end; x.join = j; return x end
local ok1, each1 = logic.eval_conditions(ctx, { f, with_join(t, "and"), with_join(t, "or") })
check("and/or 1", ok1 and each1[1] == false and each1[2] == true and each1[3] == true)
check("and/or 2", not logic.eval_conditions(ctx, { f, with_join(t, "or"), with_join(f, "and") }))
check("empty false", not logic.eval_conditions(ctx, {}))

-- Обычные выходы
local passed, outs = logic.compute(ctx, cfg_of({ t }, {
  { signal = A, mode = "one" },
  { signal = IRON, mode = "input", source = "Склад Б" },
  { signal = A, mode = "one" },
  { signal = COPPER, mode = "input", networks = ONLY_R }, -- 0 -> не выводится
}))
check("compute plain", passed and #outs == 2 and outmap(outs)[K(A)] == 2 and outmap(outs)[K(IRON)] == 100)

-- «Каждый»: балансировка — каждый предмет, которого в А меньше, чем в Б -> выдать значение из Б
passed, outs = logic.compute(ctx, cfg_of(
  { cond(op(EACH, "Склад А"), "<", op(EACH, "Склад Б")) },
  { { signal = EACH, mode = "input", source = "Склад Б" } }))
local om = outmap(outs)
check("each A<B: iron passes", passed and om[K(IRON)] == 100)
check("each A<B: copper/coal fail", om[K(COPPER)] == nil and om[K(COAL)] == nil)

-- «Каждый» против константы, выход «каждый» = 1
passed, outs = logic.compute(ctx, cfg_of({ cond(op(EACH, "Склад А"), ">=", { constant = 20 }) }, { { signal = EACH, mode = "one" } }))
om = outmap(outs)
check("each >= 20 -> iron, copper", om[K(IRON)] == 1 and om[K(COPPER)] == 1 and om[K(COAL)] == nil)

-- «Каждый» + обычный выход = число прошедших
passed, outs = logic.compute(ctx, cfg_of({ cond(op(EACH, "Склад А"), ">=", { constant = 20 }) }, { { signal = A, mode = "one" } }))
check("each + plain out = count", outmap(outs)[K(A)] == 2)

-- «Каждый» в одном условии + обычное условие через И
local c_each = cond(op(EACH, "Склад А"), ">", { constant = 0 })
local c_plain = with_join(cond(op(COPPER, "Склад Б"), ">", { constant = 100 }), "and") -- ложно
passed = logic.compute(ctx, cfg_of({ c_each, c_plain }, { { signal = EACH } }))
check("each AND false plain = false", passed == false)

-- Подсветка условий в режиме «каждый»: истинно, если прошёл хоть один S
local _, _, per = logic.compute(ctx, cfg_of({ cond(op(EACH, "Склад А"), ">", { constant = 40 }) }, {}))
check("each highlight", per[1] == true)

-- Выход «все» из источника, значения со входа
passed, outs = logic.compute(ctx, cfg_of({ t }, { { signal = ALL, mode = "input", source = "Склад А" } }))
om = outmap(outs)
check("everything out", om[K(IRON)] == 50 and om[K(COPPER)] == 20 and om[K(COAL)] == 5 and #outs == 3)
check("everything out sorted", K(outs[1].signal) < K(outs[2].signal) and K(outs[2].signal) < K(outs[3].signal))

-- Предупреждения
check("warn right anything", #logic.warnings(cfg_of({ cond(op(IRON), ">", op(ANY)) }, {})) == 1)
check("warn out anything", #logic.warnings(cfg_of({ t }, { { signal = ANY } })) == 1)
check("warn out each w/o each", #logic.warnings(cfg_of({ t }, { { signal = EACH } })) == 1)
check("no warnings", #logic.warnings(cfg_of({ c_each }, { { signal = EACH } })) == 0)

-- Миграция конфигов
local old = logic.normalize({ conditions = { { left = { signal = IRON }, right = {} } }, outputs = { { signal = A } } })
check("migrate networks+agg", old.conditions[1].left.networks.red and old.conditions[1].right.agg == "sum" and old.outputs[1].agg == "sum")
check("migrate keeps choices", logic.normalize({ conditions = { { left = { networks = { red = false }, agg = "max" } } } }).conditions[1].left.agg == "max")

---------------------------------------------------------------------------
-- Источники на моках
---------------------------------------------------------------------------
local function base_entity(t, wire_nets, cb)
  return {
    valid = true, type = t, unit_number = math.random(1, 1e9), surface = "nauvis", force = "player",
    get_control_behavior = function() return cb end,
    get_circuit_network = function(wid) local id = wire_nets[wid]; if id then return { network_id = id } end end,
  }
end
local function chest(items, wire_nets)
  local e = base_entity("container", wire_nets, nil)
  e.get_inventory = function() return { get_contents = function() return items end } end
  return e
end
local function belt(mode, read, items, wire_nets)
  local e = base_entity("transport-belt", wire_nets, { read_contents = read, read_contents_mode = mode })
  e.get_max_transport_line_index = function() return 2 end
  e.get_transport_line = function() return { get_contents = function() return items end } end
  return e
end

local G, R = defines.wire_connector_id.circuit_green, defines.wire_connector_id.circuit_red

check("belt hold both lanes", (sources.read(belt(1, true, { { name = "iron-plate", count = 3, quality = "normal" } }, {})))[K(IRON)] == 6)
check("belt pulse -> mode", select(2, sources.read(belt(0, true, {}, {}))) == "mode")
check("belt off -> disabled", select(2, sources.read(belt(1, false, {}, {}))) == "disabled")

-- Резервуар
local tank = base_entity("storage-tank", {}, { read_contents = true })
tank.fluidbox = { { name = "crude-oil", amount = 1234.7 } }
local tm, ts = sources.read(tank)
check("tank", ts == "ok" and tm[K({ type = "fluid", name = "crude-oil" })] == 1234)
local tank_off = base_entity("storage-tank", {}, { read_contents = false }); tank_off.fluidbox = { { name = "water", amount = 10 } }
check("tank off", select(2, sources.read(tank_off)) == "disabled")
local tank_empty = base_entity("storage-tank", {}, nil); tank_empty.fluidbox = {}
check("tank empty", select(2, sources.read(tank_empty)) == "ok" and next((sources.read(tank_empty))) == nil)

-- Манипулятор
local function inserter(read, mode, stack)
  local e = base_entity("inserter", {}, { circuit_read_hand_contents = read, circuit_hand_read_mode = mode })
  e.held_stack = stack
  return e
end
local hand = { valid_for_read = true, name = "iron-plate", count = 5, quality = { name = "rare" } }
local im, is = sources.read(inserter(true, 1, hand))
check("inserter hold", is == "ok" and im[K({ name = "iron-plate", quality = "rare" })] == 5)
check("inserter pulse", select(2, sources.read(inserter(true, 0, hand))) == "mode")
check("inserter off", select(2, sources.read(inserter(false, 1, hand))) == "disabled")
check("inserter empty hand", next((sources.read(inserter(true, 1, { valid_for_read = false })))) == nil)

-- Аккумулятор
local acc = base_entity("accumulator", {}, { read_charge = true, output_signal = { type = "virtual", name = "signal-C" } })
acc.electric_buffer_size = 5000000; acc.energy = 2600000
local am = sources.read(acc)
check("accumulator %", am[K({ type = "virtual", name = "signal-C" })] == 52)
local acc_def = base_entity("accumulator", {}, { read_charge = true }); acc_def.electric_buffer_size = 100; acc_def.energy = 100
check("accumulator default A", (sources.read(acc_def))[K(A)] == 100)
local acc_off = base_entity("accumulator", {}, { read_charge = false }); acc_off.electric_buffer_size = 100; acc_off.energy = 50
check("accumulator off", select(2, sources.read(acc_off)) == "disabled")

---------------------------------------------------------------------------
-- Подписи
---------------------------------------------------------------------------
local c_green = chest({ { name = "iron-plate", count = 50, quality = "normal" } }, { [G] = 10 })
c_green.selection_box = { left_top = { x = -0.5, y = 9.5 }, right_bottom = { x = 0.5, y = 10.5 } }
c_green.position = { x = 0, y = 10 }
local c_red = chest({ { name = "iron-plate", count = 7, quality = "normal" } }, { [R] = 20 })
local c_both = chest({ { name = "iron-plate", count = 100, quality = "normal" } }, { [R] = 20, [G] = 10 })
local far = chest({ { name = "iron-plate", count = 999, quality = "normal" } }, { [G] = 77 })
local b_hold = belt(1, true, { { name = "iron-plate", count = 3, quality = "normal" } }, { [G] = 10 })

sources.set_name(c_green, "Склад А"); sources.set_name(c_red, "Склад А"); sources.set_name(far, "Склад А")
sources.set_name(b_hold, "  Склад А  ")
sources.set_name(c_both, "Склад Б")

local rec = storage.sources[c_green.unit_number]
check("label created", rec.label and rec.label.valid and rec.label.text == "Склад А" and rec.label.params.only_in_alt_mode == true)
check("label above selection box", math.abs(rec.label.params.target.offset[2] - (-0.55)) < 1e-9)
local first = rec.label
sources.set_name(c_green, "Склад В")
check("label renamed in place", rec.label == first and first.text == "Склад В")
sources.set_name(c_green, "")
check("label removed with name", not first.valid and storage.sources[c_green.unit_number] == nil)
sources.set_name(c_green, "Склад А")
local n = #LABELS
sources.ensure_labels()
check("ensure_labels idempotent", #LABELS == n)
storage.sources[c_red.unit_number].label = nil
sources.ensure_labels()
check("ensure_labels fills missing", storage.sources[c_red.unit_number].label and #LABELS == n + 1)

---------------------------------------------------------------------------
-- Комбинатор целиком: топология, контекст с агрегатами, запись выхода
---------------------------------------------------------------------------
local written
local out_entity = { valid = true, get_or_create_control_behavior = function()
  return { sections_count = 1, get_section = function() return setmetatable({}, { __newindex = function(_, k, v) written = v end }) end }
end }
local main = {
  valid = true, unit_number = 1, status = 1,
  get_circuit_network = function(wid)
    if wid == 3 then return { network_id = 20, signals = { { signal = IRON, count = 107 } } } end
    if wid == 4 then return { network_id = 10, signals = { { signal = IRON, count = 156 } } } end
  end,
}
local c = { entity = main, output = out_entity, config = logic.normalize({
  conditions = { cond(op(IRON, "Склад А"), "<", op(IRON, "Склад Б")) },
  outputs = { { signal = IRON, mode = "input", source = "Склад А", networks = ONLY_G } },
}), members = {} }
combinator.refresh_members(c)
check("members A = green chest + red chest + belt, not far", #c.members["Склад А"] == 3)
check("member colors", c.members["Склад Б"][1].red and c.members["Склад Б"][1].green)

local ctx2 = combinator.make_context(c)
check("group A R+G sum = 50+7+6", ctx2.map("Склад А", BOTH, "sum")[K(IRON)] == 63)
check("group A only R = 7", ctx2.map("Склад А", ONLY_R, "sum")[K(IRON)] == 7)
check("group A min = 6", ctx2.map("Склад А", BOTH, "min")[K(IRON)] == 6)
check("group A max = 50", ctx2.map("Склад А", BOTH, "max")[K(IRON)] == 50)
check("group A avg = 21", ctx2.map("Склад А", BOTH, "avg")[K(IRON)] == 21)
check("group A count = 3", ctx2.map("Склад А", BOTH, "count")[K(IRON)] == 3)
check("group B counted once", ctx2.map("Склад Б", BOTH, "sum")[K(IRON)] == 100)
check("network red = 107", ctx2.map(nil, ONLY_R)[K(IRON)] == 107)
check("context memo", ctx2.map("Склад А", BOTH, "sum") == ctx2.map("Склад А", BOTH, "sum"))

combinator.update(c)
check("update passed", c.passed == true and c.each[1] == true)
check("output only green part of A = 56", written and #written == 1 and written[1].min == 56 and written[1].value.name == "iron-plate")
written = nil
combinator.update(c)
check("no rewrite when unchanged", written == nil)

-- Агрегат в условии: минимум по Складу А (6) < 10
c.config = logic.normalize({
  conditions = { cond({ signal = IRON, source = "Склад А", networks = BOTH, agg = "min" }, "<", { constant = 10 }) },
  outputs = { { signal = A, mode = "one" } },
})
c.last = nil
combinator.update(c)
check("min condition fires", c.passed and written and written[1].value.name == "signal-A" and written[1].min == 1)

print(string.format("tests: %d passed, %d failed", pass, fail))
if fail > 0 then error("tests failed") end
