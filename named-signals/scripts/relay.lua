-- ЛЭП-реле: создание и удаление скрытой опоры.
-- storage.relays[unit_number] = { entity = реле, supply = скрытая опора }
--
-- Логики на тиках нет: включение и выключение делает сам движок
-- (реле — это power-switch). Здесь только жизненный цикл.
local names = require("scripts.names")

local M = {}

function M.on_built(entity)
  local supply = entity.surface.create_entity({
    name = names.relay_supply,
    position = entity.position,
    force = entity.force,
    create_build_effect_smoke = false,
  })
  if not supply then return end
  supply.destructible = false
  -- Скрытая опора может успеть автоматически подключиться к соседям при
  -- создании: снимаем все её провода, оставляем только наш.
  local copper = supply.get_wire_connector(defines.wire_connector_id.pole_copper, true)
  copper.disconnect_all()
  local out = entity.get_wire_connector(defines.wire_connector_id.power_switch_right_copper, true)
  out.connect_to(copper, false, defines.wire_origin.script)

  storage.relays[entity.unit_number] = { entity = entity, supply = supply }
  script.register_on_object_destroyed(entity)
end

function M.on_destroyed(unit_number)
  local r = storage.relays[unit_number]
  if not r then return end
  if r.supply and r.supply.valid then r.supply.destroy() end
  storage.relays[unit_number] = nil
end

return M
