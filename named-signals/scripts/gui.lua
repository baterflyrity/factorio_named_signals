-- GUI: окно комбинатора и панель имени на сундуках и конвейерах.
--
-- Все элементы несут tags = { ns_action = ..., unit = ..., row = ... }:
-- обработчики событий по ним находят нужный комбинатор и строку конфига.
local names = require("scripts.names")
local logic = require("scripts.logic")
local signals = require("scripts.signals")
local sources = require("scripts.sources")
local combinator = require("scripts.combinator")

local M = {}

local FRAME = "ns_combinator"
local SRC_PANEL = "ns_source_panel"
local NETWORK_ITEM = "(вся сеть)"
local WARN_COLOR = { 1, 0.65, 0.3 }

---------------------------------------------------------------------------
-- Помощники
---------------------------------------------------------------------------
local function bold(parent, caption)
  local l = parent.add({ type = "label", caption = caption })
  l.style.font = "default-bold"
  return l
end

local function small_button(parent, caption, tags)
  local b = parent.add({ type = "button", caption = caption, tags = tags })
  b.style.minimal_width = 0
  b.style.width = 28
  b.style.padding = 0
  return b
end

-- Имена для выпадающих списков: подключённые группы + уже используемые в
-- конфиге (чтобы выбранное имя не пропадало, если провод временно сняли).
local function source_names(c)
  local set, list = {}, {}
  for name in pairs(c.members) do set[name] = true end
  for name in pairs(logic.referenced_sources(c.config)) do set[name] = true end
  for name in pairs(set) do list[#list + 1] = name end
  table.sort(list)
  return list
end

local function add_source_dropdown(parent, c, list, current, tags)
  local items, selected = { NETWORK_ITEM }, 1
  for i, name in ipairs(list) do
    items[#items + 1] = c.members[name] and name or (name .. " (не подключён)")
    if name == current then selected = i + 1 end
  end
  tags.names = list
  local dd = parent.add({ type = "drop-down", items = items, selected_index = selected, tags = tags })
  dd.style.width = 150
  return dd
end

local function add_signal_button(parent, sig, tags)
  local b = parent.add({ type = "choose-elem-button", elem_type = "signal", tags = tags })
  if sig then b.elem_value = sig end
  return b
end

local function result_caption(c)
  if c.passed then
    return "Сейчас: условие ИСТИННО, сигналов на выходе: " .. tostring(c.out_count or 0)
  end
  return "Сейчас: условие ложно"
end

---------------------------------------------------------------------------
-- Окно комбинатора
---------------------------------------------------------------------------
function M.fill(frame, c)
  local unit = c.entity.unit_number
  local list = source_names(c)

  -- Условия
  bold(frame, "Условия")
  for i, cond in ipairs(c.config.conditions) do
    local row = frame.add({ type = "flow", direction = "horizontal" })
    row.style.vertical_align = "center"

    if i == 1 then
      local spacer = row.add({ type = "empty-widget" })
      spacer.style.width = 64
    else
      local dd = row.add({
        type = "drop-down", items = { "И", "ИЛИ" },
        selected_index = (cond.join == "or") and 2 or 1,
        tags = { ns_action = "join", unit = unit, row = i },
      })
      dd.style.width = 64
    end

    add_source_dropdown(row, c, list, cond.left.source, { ns_action = "left_source", unit = unit, row = i })
    add_signal_button(row, cond.left.signal, { ns_action = "left_signal", unit = unit, row = i })

    local cmp = 1
    for k, v in ipairs(logic.COMPARATORS) do
      if v == cond.comparator then cmp = k end
    end
    local cdd = row.add({
      type = "drop-down", items = logic.COMPARATOR_LABELS, selected_index = cmp,
      tags = { ns_action = "comparator", unit = unit, row = i },
    })
    cdd.style.width = 60

    add_signal_button(row, cond.right.signal, { ns_action = "right_signal", unit = unit, row = i })
    if cond.right.signal then
      add_source_dropdown(row, c, list, cond.right.source, { ns_action = "right_source", unit = unit, row = i })
    else
      local tf = row.add({
        type = "textfield", text = tostring(cond.right.constant or 0),
        numeric = true, allow_negative = true, allow_decimal = false,
        tags = { ns_action = "right_const", unit = unit, row = i },
      })
      tf.style.width = 90
    end

    small_button(row, "x", { ns_action = "del_cond", unit = unit, row = i })
  end
  frame.add({ type = "button", caption = "+ условие", tags = { ns_action = "add_cond", unit = unit } })

  frame.add({ type = "line" })

  -- Выходы
  bold(frame, "Выход (если условия истинны)")
  for i, out in ipairs(c.config.outputs) do
    local row = frame.add({ type = "flow", direction = "horizontal" })
    row.style.vertical_align = "center"
    add_signal_button(row, out.signal, { ns_action = "out_signal", unit = unit, row = i })
    local mdd = row.add({
      type = "drop-down", items = { "= 1", "= значение на входе" },
      selected_index = (out.mode == "input") and 2 or 1,
      tags = { ns_action = "out_mode", unit = unit, row = i },
    })
    mdd.style.width = 180
    if out.mode == "input" then
      add_source_dropdown(row, c, list, out.source, { ns_action = "out_source", unit = unit, row = i })
    end
    small_button(row, "x", { ns_action = "del_out", unit = unit, row = i })
  end
  frame.add({ type = "button", caption = "+ выход", tags = { ns_action = "add_out", unit = unit } })

  frame.add({ type = "line" })

  -- Подключённые источники
  bold(frame, "Именованные источники на входе")
  local any = false
  for _, name in ipairs(list) do
    local members = c.members[name]
    if members then
      any = true
      local warn
      for _, e in ipairs(members) do
        if e.valid then
          local st = sources.status(e)
          if st ~= "ok" then warn = sources.STATUS_TEXT[st] end
        end
      end
      local caption = "- " .. name .. ": объектов " .. #members
      if warn then caption = caption .. " (!) " .. warn end
      local l = frame.add({ type = "label", caption = caption })
      if warn then l.style.font_color = WARN_COLOR end
    end
  end
  if not any then
    frame.add({ type = "label", caption = "Нет. Подключите провод к сундуку или конвейеру и задайте ему имя." })
  end

  if logic.has_wildcards(c.config) then
    local l = frame.add({ type = "label", caption = "(!) Сигналы «каждый / любой / все» пока не поддерживаются и игнорируются." })
    l.style.font_color = WARN_COLOR
  end

  frame.add({ type = "line" })
  frame.add({ type = "label", name = "ns_result", caption = result_caption(c) })
  frame.add({ type = "button", caption = "Закрыть", tags = { ns_action = "close" } })
end

function M.open(player, c)
  M.close(player)
  combinator.refresh_members(c)
  local frame = player.gui.screen.add({
    type = "frame", name = FRAME, direction = "vertical",
    caption = "Сравнивающий комбинатор с именами",
  })
  frame.auto_center = true
  M.fill(frame, c)
  player.opened = frame
  storage.open[player.index] = c.entity.unit_number
end

function M.close(player)
  local f = player.gui.screen[FRAME]
  if f then f.destroy() end
  storage.open[player.index] = nil
end

-- Перерисовать окно у всех игроков, у кого открыт этот комбинатор.
function M.refresh_for(c)
  local unit = c.entity.unit_number
  for pi, u in pairs(storage.open) do
    if u == unit then
      local p = game.get_player(pi)
      local f = p and p.gui.screen[FRAME]
      if f then
        f.clear()
        M.fill(f, c)
      end
    end
  end
end

---------------------------------------------------------------------------
-- Панель имени на сундуке / конвейере (пристыкована к ванильному окну)
---------------------------------------------------------------------------
local function anchors_for(entity)
  local rgt = defines.relative_gui_type
  local list = {}
  if entity.type == "transport-belt" then
    list[#list + 1] = rgt.transport_belt_gui
  else
    list[#list + 1] = rgt.container_gui
  end
  return list
end

local function source_status_caption(entity)
  local st = sources.status(entity)
  if st == "ok" then return "" end
  return "(!) " .. sources.STATUS_TEXT[st]
end

local function build_source_panel(frame, entity)
  local hint = frame.add({ type = "label", caption = "Имя источника. Одинаковое имя у нескольких объектов объединяет их в группу." })
  hint.style.single_line = false
  hint.style.maximal_width = 240
  local tf = frame.add({ type = "textfield", text = sources.get_name(entity) or "", tags = { ns_action = "source_name" } })
  tf.style.width = 240
  local st = frame.add({ type = "label", name = "ns_source_status", caption = source_status_caption(entity) })
  st.style.single_line = false
  st.style.maximal_width = 240
  st.style.font_color = WARN_COLOR
end

function M.open_source_panel(player, entity)
  M.close_source_panel(player)
  local made = false
  for i, anchor_gui in ipairs(anchors_for(entity)) do
    if anchor_gui then
      local frame = player.gui.relative.add({
        type = "frame", name = SRC_PANEL .. i, direction = "vertical",
        caption = "Именованный источник",
        anchor = { gui = anchor_gui, position = defines.relative_gui_position.right },
      })
      build_source_panel(frame, entity)
      made = true
    end
  end
  if not made then
    -- Запасной вариант, если в этой версии нет нужного типа якоря.
    local frame = player.gui.screen.add({
      type = "frame", name = SRC_PANEL, direction = "vertical", caption = "Именованный источник",
    })
    frame.location = { x = 20, y = 200 }
    build_source_panel(frame, entity)
  end
  storage.open_source[player.index] = entity
end

local function each_source_panel(player, fn)
  for _, child in pairs(player.gui.relative.children) do
    if child.name:sub(1, #SRC_PANEL) == SRC_PANEL then fn(child) end
  end
  local s = player.gui.screen[SRC_PANEL]
  if s then fn(s) end
end

function M.close_source_panel(player)
  each_source_panel(player, function(f) f.destroy() end)
  storage.open_source[player.index] = nil
end

---------------------------------------------------------------------------
-- События
---------------------------------------------------------------------------
local function get_c(tags)
  if not (tags and tags.unit) then return nil end
  local c = storage.combinators[tags.unit]
  if c and c.entity.valid then return c end
  return nil
end

local function changed(c, rebuild)
  c.last = nil -- принудительно перезаписать выход при следующем обновлении
  if rebuild then M.refresh_for(c) end
end

function M.on_opened(e)
  local player = game.get_player(e.player_index)
  local entity = e.entity
  if not (player and e.gui_type == defines.gui_type.entity and entity and entity.valid) then return end
  if entity.name == names.combinator then
    local c = storage.combinators[entity.unit_number]
    if c then M.open(player, c) end
  elseif sources.is_source(entity) then
    M.open_source_panel(player, entity)
  end
end

function M.on_closed(e)
  local player = game.get_player(e.player_index)
  if not player then return end
  if e.element and e.element.valid and e.element.name == FRAME then
    M.close(player)
  elseif e.entity then
    M.close_source_panel(player)
  end
end

function M.on_click(e)
  local el = e.element
  if not (el and el.valid) then return end
  local tags = el.tags
  if not (tags and tags.ns_action) then return end
  if tags.ns_action == "close" then
    local player = game.get_player(e.player_index)
    if player then M.close(player) end
    return
  end
  local c = get_c(tags)
  if not c then return end
  local cfg = c.config
  local a = tags.ns_action
  if a == "add_cond" then
    cfg.conditions[#cfg.conditions + 1] = logic.new_condition()
  elseif a == "del_cond" then
    table.remove(cfg.conditions, tags.row)
  elseif a == "add_out" then
    cfg.outputs[#cfg.outputs + 1] = logic.new_output()
  elseif a == "del_out" then
    table.remove(cfg.outputs, tags.row)
  else
    return
  end
  changed(c, true)
end

function M.on_elem_changed(e)
  local el = e.element
  if not (el and el.valid) then return end
  local tags = el.tags
  local c = get_c(tags)
  if not c then return end
  local sig = signals.copy(el.elem_value)
  local a, row = tags.ns_action, tags.row
  if a == "left_signal" then
    local cond = c.config.conditions[row]
    if not cond then return end
    cond.left.signal = sig
  elseif a == "right_signal" then
    local cond = c.config.conditions[row]
    if not cond then return end
    cond.right.signal = sig
    if not sig then cond.right.source = nil end
  elseif a == "out_signal" then
    local out = c.config.outputs[row]
    if not out then return end
    out.signal = sig
  else
    return
  end
  changed(c, true)
end

local function picked_name(tags, index)
  if index <= 1 then return nil end
  local list = tags.names or {}
  return list[index - 1]
end

function M.on_selection(e)
  local el = e.element
  if not (el and el.valid) then return end
  local tags = el.tags
  local c = get_c(tags)
  if not c then return end
  local a, row, idx = tags.ns_action, tags.row, el.selected_index
  local cond = c.config.conditions[row]
  local out = c.config.outputs[row]
  if a == "join" and cond then
    cond.join = (idx == 2) and "or" or "and"
  elseif a == "comparator" and cond then
    cond.comparator = logic.COMPARATORS[idx] or ">"
  elseif a == "left_source" and cond then
    cond.left.source = picked_name(tags, idx)
  elseif a == "right_source" and cond then
    cond.right.source = picked_name(tags, idx)
  elseif a == "out_mode" and out then
    out.mode = (idx == 2) and "input" or "one"
  elseif a == "out_source" and out then
    out.source = picked_name(tags, idx)
  else
    return
  end
  changed(c, true)
end

function M.on_text_changed(e)
  local el = e.element
  if not (el and el.valid) then return end
  local tags = el.tags
  if not (tags and tags.ns_action) then return end
  if tags.ns_action == "source_name" then
    local entity = storage.open_source[e.player_index]
    if entity and entity.valid then sources.set_name(entity, el.text) end
  elseif tags.ns_action == "right_const" then
    local c = get_c(tags)
    local cond = c and c.config.conditions[tags.row]
    if cond then
      cond.right.constant = signals.clamp(math.floor(tonumber(el.text) or 0))
      changed(c, false) -- без перерисовки, иначе поле теряет фокус
    end
  end
end

-- Периодическое обновление открытых окон (статус, предупреждения).
function M.tick()
  for pi, unit in pairs(storage.open) do
    local p = game.get_player(pi)
    local c = storage.combinators[unit]
    local f = p and p.gui.screen[FRAME]
    if not (p and f and c and c.entity.valid) then
      if p then M.close(p) else storage.open[pi] = nil end
    elseif f.ns_result then
      f.ns_result.caption = result_caption(c)
    end
  end
  for pi, entity in pairs(storage.open_source) do
    local p = game.get_player(pi)
    if not (p and entity.valid) then
      if p then M.close_source_panel(p) else storage.open_source[pi] = nil end
    else
      local caption = source_status_caption(entity)
      each_source_panel(p, function(f)
        if f.ns_source_status then f.ns_source_status.caption = caption end
      end)
    end
  end
end

return M
