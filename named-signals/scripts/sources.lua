-- Именованные источники: реестр имён и чтение вклада конкретного объекта.
--
-- Вклад читается напрямую из состояния объекта (вариант А),
-- а не из сети: в сети сигналы разных объектов уже сложены.
local signals = require("scripts.signals")
local names = require("scripts.names")

local M = {}

M.TYPES = {
  ["container"] = true,
  ["logistic-container"] = true,
  ["transport-belt"] = true,
}

M.CONNECTORS = { defines.wire_connector_id.circuit_red, defines.wire_connector_id.circuit_green }

local belt_modes = defines.control_behavior.transport_belt
  and defines.control_behavior.transport_belt.content_read_mode
local HOLD = belt_modes and belt_modes.hold

M.STATUS_TEXT = {
  mode = "конвейер не в режиме «Удержание»: именованные сигналы от него работать не будут",
  disabled = "чтение содержимого выключено: объект ничего не отдаёт в сеть",
  unsupported = "этот тип объекта пока не поддерживается",
}

-- Безопасное чтение свойства LuaObject: если свойства нет в этой версии API,
-- обращение бросает ошибку, а нам достаточно nil.
local function prop(obj, key)
  local ok, v = pcall(function() return obj[key] end)
  if ok then return v end
  return nil
end

function M.is_source(entity)
  return entity ~= nil and entity.valid and M.TYPES[entity.type] == true
end

---------------------------------------------------------------------------
-- Чтение вклада. Возвращает map { [key] = count } и статус:
--   "ok" | "mode" | "disabled" | "unsupported"
---------------------------------------------------------------------------
function M.read(entity)
  local map = {}
  local t = entity.type

  if t == "container" or t == "logistic-container" then
    local cb = entity.get_control_behavior()
    if cb and t == "logistic-container" and prop(cb, "read_contents") == false then
      return map, "disabled"
    end
    local inv = entity.get_inventory(defines.inventory.chest)
    if inv then signals.add_items(map, inv.get_contents()) end
    return map, "ok"

  elseif t == "transport-belt" then
    local cb = entity.get_control_behavior()
    if not (cb and cb.read_contents) then return map, "disabled" end
    if HOLD == nil or cb.read_contents_mode ~= HOLD then return map, "mode" end
    for i = 1, entity.get_max_transport_line_index() do
      signals.add_items(map, entity.get_transport_line(i).get_contents())
    end
    return map, "ok"
  end

  return map, "unsupported"
end

function M.status(entity)
  local _, st = M.read(entity)
  return st
end

-- Id сетей, в которые объект реально отдаёт сигналы. Учитывает выбор
-- выходных сетей (output_networks), если он есть у объекта.
function M.output_network_ids(entity)
  local ids = {}
  local cb = entity.get_control_behavior()
  local sel = cb and prop(cb, "output_networks")
  for i, wid in ipairs(M.CONNECTORS) do
    local allowed = true
    if sel then
      if i == 1 and sel.red == false then allowed = false end
      if i == 2 and sel.green == false then allowed = false end
    end
    if allowed then
      local net = entity.get_circuit_network(wid)
      if net then ids[#ids + 1] = net.network_id end
    end
  end
  return ids
end

---------------------------------------------------------------------------
-- Подписи в режиме Alt: текст с именем над объектом.
-- Это объект отрисовки (LuaRenderObject), привязанный к сущности: хранится в
-- сохранении, в сетевой игре синхронизируется движком и уничтожается вместе
-- с сущностью. Ссылка лежит в rec.label.
---------------------------------------------------------------------------
local LABEL_OFFSET = { 0, -0.55 } -- чуть выше верхнего края объекта 1x1

function M.update_label(rec)
  local e = rec.entity
  if not (e and e.valid) then return end
  if rec.label and rec.label.valid then
    rec.label.text = rec.name
    return
  end
  rec.label = rendering.draw_text({
    text = rec.name,
    surface = e.surface,
    target = { entity = e, offset = LABEL_OFFSET },
    color = names.tint,
    scale = 1.0,
    alignment = "center",
    vertical_alignment = "bottom",
    only_in_alt_mode = true,
    forces = { e.force },
  })
end

local function destroy_label(rec)
  if rec and rec.label and rec.label.valid then rec.label.destroy() end
end

-- Для миграции: создать недостающие подписи у уже названных объектов.
function M.ensure_labels()
  for _, rec in pairs(storage.sources) do M.update_label(rec) end
end

---------------------------------------------------------------------------
-- Реестр имён: storage.sources[unit_number] = { entity = LuaEntity, name = string, label = LuaRenderObject }
-- Имена не уникальны: одинаковое имя у нескольких объектов = группа.
---------------------------------------------------------------------------
function M.get_name(entity)
  local rec = storage.sources[entity.unit_number]
  return rec and rec.name or nil
end

function M.set_name(entity, name)
  name = name and name:match("^%s*(.-)%s*$") or ""
  local id = entity.unit_number
  if not id then return end
  local rec = storage.sources[id]
  if name == "" then
    destroy_label(rec)
    storage.sources[id] = nil
  else
    if not rec then
      script.register_on_object_destroyed(entity)
      rec = { entity = entity }
      storage.sources[id] = rec
    end
    rec.name = name
    M.update_label(rec)
  end
  storage.topology_dirty = true
end

return M
