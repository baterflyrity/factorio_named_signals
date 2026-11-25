-- ЛЭП-реле: жизненный цикл составной сущности и перенос проводов.
--
-- storage.relays[unit_number видимой опоры] = { pole = опора, switch = выключатель, input = входная опора }
-- storage.relay_by_part[unit_number выключателя] = unit_number видимой опоры (для окна и чертежей)
--
-- Включение и выключение делает движок (switch — обычный power-switch).
-- Скрипт на тиках только переносит новые медные провода игрока с видимой
-- опоры на входную. Событий «провод подключён» в API нет, поэтому опрос.
local names = require("scripts.names")

local M = {}

local W = defines.wire_connector_id
local PLAYER = defines.wire_origin.player
local SCRIPT = defines.wire_origin.script

local function prop(obj, key)
  local ok, v = pcall(function() return obj[key] end)
  if ok then return v end
  return nil
end

local function set_prop(obj, key, value)
  if value == nil then return end
  pcall(function() obj[key] = value end)
end

local function create_part(surface, name, position, force)
  local e = surface.create_entity({ name = name, position = position, force = force, create_build_effect_smoke = false })
  if e then
    e.destructible = false
    -- Скрытые части могли успеть автоматически подключиться к соседям при создании.
    local c = e.get_wire_connector(W.pole_copper, false)
    if c then c.disconnect_all() end
  end
  return e
end

-- Соединить три части скриптовыми (невидимыми) проводами:
--   вход выключателя <-> входная опора, выход выключателя <-> видимая опора,
--   логическая сеть видимой опоры <-> выключатель (условие задаётся проводом к опоре).
local function wire_parts(pole, switch, input)
  switch.get_wire_connector(W.power_switch_left_copper, true)
    .connect_to(input.get_wire_connector(W.pole_copper, true), false, SCRIPT)
  switch.get_wire_connector(W.power_switch_right_copper, true)
    .connect_to(pole.get_wire_connector(W.pole_copper, true), false, SCRIPT)
  for _, id in ipairs({ W.circuit_red, W.circuit_green }) do
    pole.get_wire_connector(id, true).connect_to(switch.get_wire_connector(id, true), false, SCRIPT)
  end
end

---------------------------------------------------------------------------
-- Настройки выключателя: для чертежей
---------------------------------------------------------------------------
function M.read_settings(switch)
  local cb = switch.get_control_behavior()
  return {
    state = switch.power_switch_state,
    enable_disable = cb and prop(cb, "circuit_enable_disable"),
    condition = cb and prop(cb, "circuit_condition"),
    logistic = cb and prop(cb, "connect_to_logistic_network"),
    logistic_condition = cb and prop(cb, "logistic_condition"),
  }
end

local function apply_settings(switch, s)
  if type(s) ~= "table" then return end
  if s.state ~= nil then switch.power_switch_state = s.state end
  if s.enable_disable or s.logistic then
    local cb = switch.get_or_create_control_behavior()
    set_prop(cb, "circuit_enable_disable", s.enable_disable)
    set_prop(cb, "circuit_condition", s.condition)
    set_prop(cb, "connect_to_logistic_network", s.logistic)
    set_prop(cb, "logistic_condition", s.logistic_condition)
  end
end

---------------------------------------------------------------------------
-- Жизненный цикл
---------------------------------------------------------------------------
local function register(pole, switch, input)
  storage.relays[pole.unit_number] = { pole = pole, switch = switch, input = input }
  storage.relay_by_part[switch.unit_number] = pole.unit_number
  script.register_on_object_destroyed(pole)
end

function M.on_built(pole, tags)
  local switch = create_part(pole.surface, names.relay_switch, pole.position, pole.force)
  local input = create_part(pole.surface, names.relay_input, pole.position, pole.force)
  if not (switch and input) then
    if switch then switch.destroy() end
    if input then input.destroy() end
    return
  end
  wire_parts(pole, switch, input)
  apply_settings(switch, tags and tags.ns_relay)
  register(pole, switch, input)
end

function M.on_destroyed(unit_number)
  local r = storage.relays[unit_number]
  if not r then return end
  if r.switch and r.switch.valid then
    storage.relay_by_part[r.switch.unit_number] = nil
    r.switch.destroy()
  end
  if r.input and r.input.valid then r.input.destroy() end
  storage.relays[unit_number] = nil
end

---------------------------------------------------------------------------
-- Провода
---------------------------------------------------------------------------
-- Новые провода игрока на видимой опоре -> на входную опору.
-- Если входная опора уже соединена с этой целью, значит игрок соединил ту же
-- пару повторно — в ванили это удаление провода. Удаляем оба.
local function move_wires(r)
  local pole_c = r.pole.get_wire_connector(W.pole_copper, false)
  if not pole_c then return end
  local input_c = r.input.get_wire_connector(W.pole_copper, true)
  for _, conn in ipairs(pole_c.connections) do
    if conn.origin == PLAYER then
      local target = conn.target
      pole_c.disconnect_from(target, PLAYER)
      if input_c.is_connected_to(target, PLAYER) then
        input_c.disconnect_from(target, PLAYER)
      else
        input_c.connect_to(target, false, PLAYER)
      end
    end
  end
end

function M.tick()
  for unit, r in pairs(storage.relays) do
    if r.pole and r.pole.valid and r.input and r.input.valid then
      move_wires(r)
    end
  end
end

-- Чужая опора при постройке автоматически подключается к соседям. К реле —
-- нельзя: его нужно подключать вручную.
function M.strip_auto_connections(entity)
  local c = entity.get_wire_connector(W.pole_copper, false)
  if not c then return end
  for _, conn in ipairs(c.connections) do
    local owner = conn.target.owner
    if owner and owner.valid and owner.name == names.relay then
      c.disconnect_from(conn.target, conn.origin)
    end
  end
end

---------------------------------------------------------------------------
-- Окно: открываем родное окно выключателя вместо окна опоры
---------------------------------------------------------------------------
function M.on_opened(e)
  local entity = e.entity
  if not (e.gui_type == defines.gui_type.entity and entity and entity.valid and entity.name == names.relay) then
    return false
  end
  local r = storage.relays[entity.unit_number]
  local player = game.get_player(e.player_index)
  if r and r.switch and r.switch.valid and player then
    pcall(function() player.opened = r.switch end)
  end
  return true
end

---------------------------------------------------------------------------
-- Чертежи
---------------------------------------------------------------------------
function M.blueprint_tags(pole)
  local r = storage.relays[pole.unit_number]
  if r and r.switch and r.switch.valid then return M.read_settings(r.switch) end
  return nil
end

---------------------------------------------------------------------------
-- Миграция 0.3.x: тогда видимой частью был выключатель (ns-relay-pole),
-- а зону питала скрытая опора ns-relay-pole-supply (её прототипа больше нет,
-- игра удалила такие опоры при загрузке).
---------------------------------------------------------------------------
function M.migrate()
  local old = {}
  for unit, r in pairs(storage.relays) do
    if r.entity then old[#old + 1] = { unit = unit, switch = r.entity } end
  end
  for _, o in ipairs(old) do
    storage.relays[o.unit] = nil
    local switch = o.switch
    if switch and switch.valid then
      local surface, pos, force = switch.surface, switch.position, switch.force
      -- Запомнить провода игрока со старого выключателя.
      local copper, circuit = {}, {}
      for _, id in ipairs({ W.power_switch_left_copper, W.power_switch_right_copper }) do
        local c = switch.get_wire_connector(id, false)
        if c then
          for _, conn in ipairs(c.connections) do
            if conn.origin == PLAYER then copper[#copper + 1] = { from = c, target = conn.target } end
          end
        end
      end
      for _, id in ipairs({ W.circuit_red, W.circuit_green }) do
        local c = switch.get_wire_connector(id, false)
        if c then
          for _, conn in ipairs(c.connections) do
            if conn.origin == PLAYER then circuit[#circuit + 1] = { id = id, from = c, target = conn.target } end
          end
        end
        end
      -- Снять все провода со старого выключателя (в т. ч. скриптовый к старой опоре).
      for _, id in ipairs({ W.power_switch_left_copper, W.power_switch_right_copper, W.circuit_red, W.circuit_green }) do
        local c = switch.get_wire_connector(id, false)
        if c then c.disconnect_all() end
      end

      local pole = surface.create_entity({ name = names.relay, position = pos, force = force, create_build_effect_smoke = false })
      local input = create_part(surface, names.relay_input, pos, force)
      if pole and input then
        switch.destructible = false
        wire_parts(pole, switch, input)
        local input_c = input.get_wire_connector(W.pole_copper, true)
        for _, w in ipairs(copper) do
          if w.target.valid and not input_c.is_connected_to(w.target, PLAYER) then
            input_c.connect_to(w.target, false, PLAYER)
          end
        end
        for _, w in ipairs(circuit) do
          if w.target.valid then pole.get_wire_connector(w.id, true).connect_to(w.target, false, PLAYER) end
        end
        register(pole, switch, input)
      else
        if pole then pole.destroy() end
        if input then input.destroy() end
      end
    end
  end
end

return M
