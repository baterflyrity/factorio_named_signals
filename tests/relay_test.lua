-- Имитация графа проводов 2.x для проверки логики реле.
defines = {
  wire_connector_id = { circuit_red = 1, circuit_green = 2, pole_copper = 7, power_switch_left_copper = 8, power_switch_right_copper = 9 },
  wire_origin = { player = 0, script = 1 },
  gui_type = { entity = 1 },
}
storage = { relays = {}, relay_by_part = {} }
local registered = {}
script = { register_on_object_destroyed = function(e) registered[e.unit_number] = true end }

local next_unit = 100
local entities = {}

local function connector(owner, id)
  local c = { owner = owner, id = id, list = {}, valid = true }
  local function find(t, origin)
    for i, x in ipairs(c.list) do if x.target == t and x.origin == origin then return i end end
  end
  function c.connect_to(t, reach, origin)
    origin = origin or 0
    if find(t, origin) then return false end
    c.list[#c.list + 1] = { target = t, origin = origin }
    t.list[#t.list + 1] = { target = c, origin = origin }
    return true
  end
  function c.disconnect_from(t, origin)
    origin = origin or 0
    local i = find(t, origin); if i then table.remove(c.list, i) end
    for j, x in ipairs(t.list) do if x.target == c and x.origin == origin then table.remove(t.list, j) break end end
  end
  function c.is_connected_to(t, origin) return find(t, origin or 0) ~= nil end
  function c.disconnect_all() while #c.list > 0 do c.disconnect_from(c.list[1].target, c.list[1].origin) end end
  setmetatable(c, { __index = function(_, k) if k == "connections" then
    local copy = {}; for i, x in ipairs(c.list) do copy[i] = { target = x.target, origin = x.origin } end; return copy end end })
  return c
end

local function entity(name, extra)
  next_unit = next_unit + 1
  local e = { name = name, unit_number = next_unit, valid = true, position = { 0, 0 }, force = "player", connectors = {} }
  e.surface = { create_entity = function(p) return entity(p.name) end }
  function e.get_wire_connector(id, create)
    if not e.connectors[id] and create then e.connectors[id] = connector(e, id) end
    return e.connectors[id]
  end
  function e.destroy()
    e.valid = false
    for _, c in pairs(e.connectors) do c.disconnect_all() end
  end
  local cb = { circuit_enable_disable = false }
  e.power_switch_state = false
  function e.get_control_behavior() return cb end
  function e.get_or_create_control_behavior() return cb end
  for k, v in pairs(extra or {}) do e[k] = v end
  entities[#entities + 1] = e
  return e
end

package.path = MOD .. "/?.lua;" .. package.path
local relay = require("scripts.relay")
local W, P, S = defines.wire_connector_id, defines.wire_origin.player, defines.wire_origin.script

local function ok(name, cond) if not cond then error("FAIL " .. name) end end

-- Постройка с тегами чертежа
local mast = entity("ns-relay-mast")
relay.on_built(mast, { ns_relay = { state = true, enable_disable = true, condition = { comparator = ">" } } })
local r = storage.relays[mast.unit_number]
ok("parts", r and r.switch.name == "ns-relay-pole" and r.input.name == "ns-relay-pole-input")
ok("switch -> mast (script)", r.switch.get_wire_connector(W.power_switch_right_copper).is_connected_to(mast.get_wire_connector(W.pole_copper), S))
ok("switch <- input (script)", r.switch.get_wire_connector(W.power_switch_left_copper).is_connected_to(r.input.get_wire_connector(W.pole_copper), S))
ok("circuit bridged", mast.get_wire_connector(W.circuit_red).is_connected_to(r.switch.get_wire_connector(W.circuit_red), S))
ok("tags applied", r.switch.power_switch_state == true and r.switch.get_control_behavior().circuit_enable_disable == true)

-- Игрок тянет провод от обычной опоры к реле -> провод уезжает на вход
local other = entity("medium-electric-pole")
other.get_wire_connector(W.pole_copper, true).connect_to(mast.get_wire_connector(W.pole_copper), true, P)
relay.tick()
local in_c = r.input.get_wire_connector(W.pole_copper)
ok("moved to input", in_c.is_connected_to(other.get_wire_connector(W.pole_copper), P))
ok("mast has no player wire", not mast.get_wire_connector(W.pole_copper).is_connected_to(other.get_wire_connector(W.pole_copper), P))
ok("script wire kept", mast.get_wire_connector(W.pole_copper).is_connected_to(r.switch.get_wire_connector(W.power_switch_right_copper), S))

-- Повторное соединение той же пары = удаление (как в ванили)
other.get_wire_connector(W.pole_copper).connect_to(mast.get_wire_connector(W.pole_copper), true, P)
relay.tick()
ok("toggle removes", not in_c.is_connected_to(other.get_wire_connector(W.pole_copper), P)
  and not mast.get_wire_connector(W.pole_copper).is_connected_to(other.get_wire_connector(W.pole_copper), P))

-- Чужая опора, поставленная рядом, автоподключилась к реле -> отключаем
local auto = entity("small-electric-pole")
auto.get_wire_connector(W.pole_copper, true).connect_to(mast.get_wire_connector(W.pole_copper), true, P)
local neighbour = entity("small-electric-pole")
auto.get_wire_connector(W.pole_copper).connect_to(neighbour.get_wire_connector(W.pole_copper, true), true, P)
relay.strip_auto_connections(auto)
ok("auto to relay stripped", not auto.get_wire_connector(W.pole_copper).is_connected_to(mast.get_wire_connector(W.pole_copper), P))
ok("auto to others kept", auto.get_wire_connector(W.pole_copper).is_connected_to(neighbour.get_wire_connector(W.pole_copper), P))

-- Два реле, соединённые друг с другом -> соединены входы
local mast2 = entity("ns-relay-mast"); relay.on_built(mast2, nil)
local r2 = storage.relays[mast2.unit_number]
mast.get_wire_connector(W.pole_copper).connect_to(mast2.get_wire_connector(W.pole_copper), true, P)
relay.tick(); relay.tick()
ok("relay-relay -> inputs", r.input.get_wire_connector(W.pole_copper).is_connected_to(r2.input.get_wire_connector(W.pole_copper), P))

-- Чертёж: читаем настройки выключателя
ok("blueprint tags", relay.blueprint_tags(mast).state == true)

-- Удаление
relay.on_destroyed(mast.unit_number)
ok("destroyed parts", not r.switch.valid and not r.input.valid and storage.relays[mast.unit_number] == nil)

-- Миграция 0.3.x: выключатель с проводами игрока на обоих сокетах и логическим проводом
local old_switch = entity("ns-relay-pole")
old_switch.surface = { create_entity = function(p) return entity(p.name) end }
local feeder, consumer_pole, comb = entity("medium-electric-pole"), entity("medium-electric-pole"), entity("decider")
old_switch.get_wire_connector(W.power_switch_left_copper, true).connect_to(feeder.get_wire_connector(W.pole_copper, true), true, P)
old_switch.get_wire_connector(W.power_switch_right_copper, true).connect_to(consumer_pole.get_wire_connector(W.pole_copper, true), true, P)
old_switch.get_wire_connector(W.circuit_green, true).connect_to(comb.get_wire_connector(W.circuit_green, true), true, P)
local old_supply = entity("ns-relay-pole-supply"); old_supply.valid = false -- прототип удалён
storage.relays[old_switch.unit_number] = { entity = old_switch, supply = old_supply }
relay.migrate()
local migrated
for _, x in pairs(storage.relays) do if x.switch == old_switch then migrated = x end end
ok("migrated", migrated and migrated.pole.name == "ns-relay-mast" and storage.relays[old_switch.unit_number] == nil)
local mi = migrated.input.get_wire_connector(W.pole_copper)
ok("copper wires -> input", mi.is_connected_to(feeder.get_wire_connector(W.pole_copper), P) and mi.is_connected_to(consumer_pole.get_wire_connector(W.pole_copper), P))
ok("no player copper left on switch", #old_switch.get_wire_connector(W.power_switch_right_copper).connections == 1) -- только скриптовый к опоре
ok("circuit wire -> mast", migrated.pole.get_wire_connector(W.circuit_green).is_connected_to(comb.get_wire_connector(W.circuit_green), P))

print("relay runtime: OK")
