-- Комбинатор: жизненный цикл составной сущности, топология и обновление.
--
-- storage.combinators[unit_number] = {
--   entity  = видимый комбинатор,
--   output  = скрытый константный комбинатор,
--   config  = конфиг условий (см. logic.lua),
--   members = { [имя группы] = { {entity, red, green}, ... } } -- подключённые источники,
--   each    = результаты отдельных условий (для подсветки в GUI),
--   last    = сериализованный последний выход,
--   passed  = результат условий на последнем обновлении,
--   out_count = число сигналов на выходе,
-- }
--
-- Важно для мультиплеера: members хранится в storage, а не в локальном кэше.
-- Иначе у подключившегося игрока кэш был бы свежим, а у хоста устаревшим
-- до следующего пересканирования, и результаты разошлись бы (десинк).
local util = require("util")
local names = require("scripts.names")
local logic = require("scripts.logic")
local signals = require("scripts.signals")
local sources = require("scripts.sources")

local M = {}

local INPUTS = {
  defines.wire_connector_id.combinator_input_red,
  defines.wire_connector_id.combinator_input_green,
}

local OUTPUT_WIRES = {
  { defines.wire_connector_id.combinator_output_red, defines.wire_connector_id.circuit_red },
  { defines.wire_connector_id.combinator_output_green, defines.wire_connector_id.circuit_green },
}

function M.on_built(entity, tags)
  local output = entity.surface.create_entity({
    name = names.output,
    position = entity.position,
    force = entity.force,
    create_build_effect_smoke = false,
  })
  output.destructible = false
  for _, pair in ipairs(OUTPUT_WIRES) do
    local from = entity.get_wire_connector(pair[1], true)
    local to = output.get_wire_connector(pair[2], true)
    from.connect_to(to, false, defines.wire_origin.script)
  end

  local config
  if tags and tags.ns_config then
    config = logic.normalize(util.table.deepcopy(tags.ns_config))
  else
    config = logic.new_config()
  end

  local c = { entity = entity, output = output, config = config, members = {} }
  storage.combinators[entity.unit_number] = c
  script.register_on_object_destroyed(entity)
  M.refresh_members(c)
  return c
end

function M.on_destroyed(unit_number)
  local c = storage.combinators[unit_number]
  if not c then return end
  if c.output and c.output.valid then c.output.destroy() end
  storage.combinators[unit_number] = nil
end

-- Какие именованные источники отдают сигналы во входные сети комбинатора
-- и каким цветом провода. Сравниваем network_id: это дешевле и надёжнее,
-- чем обходить граф проводов (столбы и ответвления движок уже учёл).
--   members[имя] = { { entity = LuaEntity, red = bool, green = bool }, ... }
function M.refresh_members(c)
  local red_net = c.entity.get_circuit_network(INPUTS[1])
  local green_net = c.entity.get_circuit_network(INPUTS[2])
  local red_id = red_net and red_net.network_id
  local green_id = green_net and green_net.network_id
  local members = {}
  if red_id or green_id then
    for _, rec in pairs(storage.sources) do
      local e = rec.entity
      if e.valid then
        local on_red, on_green = false, false
        for _, id in ipairs(sources.output_network_ids(e)) do
          if id == red_id then on_red = true end
          if id == green_id then on_green = true end
        end
        if on_red or on_green then
          local list = members[rec.name]
          if not list then
            list = {}
            members[rec.name] = list
          end
          list[#list + 1] = { entity = e, red = on_red, green = on_green }
        end
      end
    end
  end
  c.members = members
end

-- Вклад группы с учётом выбранных проводов. Каждый объект считается один раз,
-- даже если подключён к комбинатору и красным, и зелёным проводом.
function M.read_group(c, name, nets)
  local map = {}
  local list = c.members[name]
  if list then
    for _, m in ipairs(list) do
      if m.entity.valid and ((nets.red and m.red) or (nets.green and m.green)) then
        signals.merge(map, (sources.read(m.entity)))
      end
    end
  end
  return map
end

local function read_net(entity, wid)
  local map = {}
  local net = entity.get_circuit_network(wid)
  if net then signals.add_signals(map, net.signals) end
  return map
end

-- Контекст для движка условий с ленивым чтением и кэшем на один тик.
function M.make_context(c)
  local entity = c.entity
  local red, green
  local groups = {}
  return {
    value = function(sig, source, nets)
      local k = signals.key(sig)
      if not k then return 0 end
      if source then
        local gk = source .. (nets.red and "|r" or "|-") .. (nets.green and "g" or "-")
        local m = groups[gk]
        if not m then
          m = M.read_group(c, source, nets)
          groups[gk] = m
        end
        return m[k] or 0
      end
      local v = 0
      if nets.red then
        red = red or read_net(entity, INPUTS[1])
        v = v + (red[k] or 0)
      end
      if nets.green then
        green = green or read_net(entity, INPUTS[2])
        v = v + (green[k] or 0)
      end
      return v
    end,
  }
end

local function write_output(c, outputs)
  local cb = c.output.get_or_create_control_behavior()
  local section = (cb.sections_count > 0) and cb.get_section(1) or cb.add_section()
  local filters = {}
  for i, o in ipairs(outputs) do
    local s = o.signal
    filters[i] = {
      value = { type = s.type or "item", name = s.name, quality = s.quality or "normal", comparator = "=" },
      min = o.count,
    }
  end
  section.filters = filters
end

function M.update(c)
  local entity = c.entity
  if not (entity.valid and c.output and c.output.valid) then return end

  local passed, outputs, each = false, {}, {}
  if entity.status ~= defines.entity_status.no_power then
    passed, outputs, each = logic.compute(M.make_context(c), c.config)
  end

  c.passed = passed
  c.each = each
  c.out_count = #outputs
  local key = signals.serialize(outputs)
  if key == c.last then return end
  c.last = key
  write_output(c, outputs)
end

return M
