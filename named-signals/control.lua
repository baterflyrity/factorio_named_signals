-- Точка входа control-стадии: только регистрация событий и маршрутизация.
-- Каждое событие регистрируется ровно один раз (повторный script.on_event
-- перезаписывает обработчик), поэтому вся диспетчеризация собрана здесь.
local util = require("util")
local names = require("scripts.names")
local combinator = require("scripts.combinator")
local sources = require("scripts.sources")
local gui = require("scripts.gui")

local function init_storage()
  storage.combinators = storage.combinators or {}
  storage.sources = storage.sources or {}
  storage.open = storage.open or {}
  storage.open_source = storage.open_source or {}
  if storage.topology_dirty == nil then storage.topology_dirty = true end
end

script.on_init(init_storage)

script.on_configuration_changed(function()
  init_storage()
  -- Рецепт добавлен в уже изученную технологию: открыть его в старых сохранениях.
  for _, force in pairs(game.forces) do
    local tech = force.technologies["circuit-network"]
    local recipe = force.recipes[names.combinator]
    if tech and recipe and tech.researched then recipe.enabled = true end
  end
end)

---------------------------------------------------------------------------
-- Постройка (в том числе из чертежей: теги приходят в event.tags)
---------------------------------------------------------------------------
local function on_built(e)
  local entity = e.entity
  if not (entity and entity.valid) then return end
  local tags = e.tags
  if entity.name == names.combinator then
    combinator.on_built(entity, tags)
  elseif sources.is_source(entity) and tags and tags.ns_name then
    sources.set_name(entity, tags.ns_name)
  end
end

local build_filters = {
  { filter = "name", name = names.combinator },
  { filter = "type", type = "container" },
  { filter = "type", type = "logistic-container" },
  { filter = "type", type = "transport-belt" },
}

for _, ev in pairs({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.on_space_platform_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive,
}) do
  script.on_event(ev, on_built, build_filters)
end

---------------------------------------------------------------------------
-- Удаление: любой способ (разобран, уничтожен, скриптом) приходит сюда.
---------------------------------------------------------------------------
script.on_event(defines.events.on_object_destroyed, function(e)
  local id = e.useful_id
  if not id then return end
  combinator.on_destroyed(id)
  if storage.sources[id] then
    storage.sources[id] = nil
    storage.topology_dirty = true
  end
end)

---------------------------------------------------------------------------
-- Чертежи: сохраняем конфиг комбинатора и имена источников в теги.
---------------------------------------------------------------------------
script.on_event(defines.events.on_player_setup_blueprint, function(e)
  local bp
  if e.stack and e.stack.valid_for_read then
    bp = e.stack
  elseif e.record then
    bp = e.record
  end
  if not bp then return end
  local mapping = e.mapping and e.mapping.get()
  if not mapping then return end
  for index, entity in pairs(mapping) do
    if entity.valid then
      if entity.name == names.combinator then
        local c = storage.combinators[entity.unit_number]
        if c then
          pcall(function() bp.set_blueprint_entity_tag(index, "ns_config", c.config) end)
        end
      elseif sources.is_source(entity) then
        local n = sources.get_name(entity)
        if n then
          pcall(function() bp.set_blueprint_entity_tag(index, "ns_name", n) end)
        end
      end
    end
  end
end)

---------------------------------------------------------------------------
-- Копирование настроек (Shift+ПКМ / Shift+ЛКМ)
---------------------------------------------------------------------------
script.on_event(defines.events.on_entity_settings_pasted, function(e)
  local s, d = e.source, e.destination
  if not (s and s.valid and d and d.valid) then return end
  if s.name == names.combinator and d.name == names.combinator then
    local cs, cd = storage.combinators[s.unit_number], storage.combinators[d.unit_number]
    if cs and cd then
      cd.config = util.table.deepcopy(cs.config)
      cd.last = nil
      gui.refresh_for(cd)
    end
  elseif sources.is_source(s) and sources.is_source(d) then
    sources.set_name(d, sources.get_name(s) or "")
  end
end)

---------------------------------------------------------------------------
-- GUI
---------------------------------------------------------------------------
script.on_event(defines.events.on_gui_opened, gui.on_opened)
script.on_event(defines.events.on_gui_closed, gui.on_closed)
script.on_event(defines.events.on_gui_click, gui.on_click)
script.on_event(defines.events.on_gui_elem_changed, gui.on_elem_changed)
script.on_event(defines.events.on_gui_selection_state_changed, gui.on_selection)
script.on_event(defines.events.on_gui_text_changed, gui.on_text_changed)

---------------------------------------------------------------------------
-- Тик: пересканирование топологии, обновление комбинаторов, обновление окон.
-- Событий «провод подключён/отключён» в API нет, поэтому топология
-- пересканируется периодически и сразу после смены имени источника.
---------------------------------------------------------------------------
script.on_event(defines.events.on_tick, function(e)
  local tick = e.tick
  if storage.topology_dirty or tick % settings.global["ns-topology-interval"].value == 0 then
    storage.topology_dirty = false
    for _, c in pairs(storage.combinators) do
      if c.entity.valid then combinator.refresh_members(c) end
    end
  end
  if tick % settings.global["ns-update-interval"].value == 0 then
    for _, c in pairs(storage.combinators) do combinator.update(c) end
  end
  if tick % 30 == 0 then gui.tick() end
end)
