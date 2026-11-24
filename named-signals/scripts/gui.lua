-- GUI: окно комбинатора, окно справки и панель имени на сундуках и конвейерах.
--
-- Оформление повторяет ванильный сравнивающий комбинатор 2.x: заголовок с
-- перетаскиванием и кнопками, статус и превью объекта, строки условий в
-- shallow-рамках, которые подсвечиваются, когда условие выполнено.
-- Все стили и спрайты сверены с core/prototypes игры 2.1.
--
-- Все интерактивные элементы несут tags = { ns_action, unit, row, side, color }:
-- обработчики по ним находят комбинатор и поле конфига.
local names = require("scripts.names")
local logic = require("scripts.logic")
local signals = require("scripts.signals")
local sources = require("scripts.sources")
local combinator = require("scripts.combinator")

local M = {}

local FRAME = "ns_combinator"
local HELP = "ns_help"
local SRC_PANEL = "ns_source_panel"
local NETWORK_ITEM = "Вся сеть"
local WARN_COLOR = { 1, 0.65, 0.3 }
local RED = "[color=1,0.35,0.35]R[/color]"
local GREEN = "[color=0.35,1,0.35]G[/color]"

---------------------------------------------------------------------------
-- Общие помощники
---------------------------------------------------------------------------
local function titlebar(frame, caption, close_action, with_help)
  local bar = frame.add({ type = "flow", style = "frame_header_flow", direction = "horizontal" })
  bar.drag_target = frame
  bar.add({ type = "label", style = "frame_title", caption = caption, ignored_by_interaction = true })
  local drag = bar.add({ type = "empty-widget", style = "draggable_space_header", ignored_by_interaction = true })
  drag.style.height = 24
  drag.style.horizontally_stretchable = true
  drag.style.right_margin = 4
  if with_help then
    bar.add({
      type = "sprite-button", style = "frame_action_button", sprite = "utility/questionmark",
      tooltip = "Справка", tags = { ns_action = "help" },
    })
  end
  bar.add({
    type = "sprite-button", style = "frame_action_button", sprite = "utility/close",
    tooltip = "Закрыть", tags = { ns_action = close_action },
  })
end

local function heading(parent, caption)
  return parent.add({ type = "label", style = "caption_label", caption = caption })
end

local function wrapped_label(parent, caption, width, name)
  local l = parent.add({ type = "label", caption = caption, name = name })
  l.style.single_line = false
  l.style.maximal_width = width or 520
  return l
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

local function status_view(entity)
  local st = entity.status
  if st == defines.entity_status.no_power then return "utility/status_not_working", "Нет питания" end
  if st == defines.entity_status.low_power then return "utility/status_yellow", "Мало энергии" end
  return "utility/status_working", "Работает"
end

local function result_caption(c)
  if c.passed then
    return "Условие выполнено, сигналов на выходе: " .. tostring(c.out_count or 0)
  end
  return "Условие не выполнено"
end

---------------------------------------------------------------------------
-- Операнд: [источник] [сигнал] [R/G]
---------------------------------------------------------------------------
local function add_source_dropdown(parent, c, list, current, tags)
  local items, selected = { NETWORK_ITEM }, 1
  for i, name in ipairs(list) do
    items[#items + 1] = c.members[name] and name or (name .. " (не подключён)")
    if name == current then selected = i + 1 end
  end
  tags.names = list
  local dd = parent.add({
    type = "drop-down", items = items, selected_index = selected, tags = tags,
    tooltip = "Откуда брать значение: из всей сети или только от источников с этим именем",
  })
  dd.style.width = 130
  return dd
end

local function add_signal_button(parent, sig, tags)
  local b = parent.add({
    type = "choose-elem-button", elem_type = "signal",
    style = "decider_combinator_signal_select_button", tags = tags,
  })
  if sig then b.elem_value = sig end
  return b
end

local function add_networks(parent, nets, tags)
  local flow = parent.add({ type = "flow", direction = "vertical" })
  flow.style.vertical_spacing = 0
  local tr = { ns_action = "net", color = "red" }
  local tg = { ns_action = "net", color = "green" }
  for k, v in pairs(tags) do tr[k] = v; tg[k] = v end
  tr.ns_action, tr.color = "net", "red"
  tg.ns_action, tg.color = "net", "green"
  flow.add({ type = "checkbox", state = nets.red ~= false, caption = RED, tags = tr, tooltip = "Учитывать красный провод" })
  flow.add({ type = "checkbox", state = nets.green ~= false, caption = GREEN, tags = tg, tooltip = "Учитывать зелёный провод" })
  return flow
end

local function add_operand(parent, c, list, op, tags)
  local function t(action)
    local x = { ns_action = action }
    for k, v in pairs(tags) do x[k] = v end
    return x
  end
  add_source_dropdown(parent, c, list, op.source, t("source"))
  add_signal_button(parent, op.signal, t("signal"))
  add_networks(parent, op.networks or {}, tags)
end

local function row_frame(parent, name, fulfilled)
  local f = parent.add({
    type = "frame", name = name, direction = "horizontal",
    style = fulfilled and "decider_combinator_fulfilled_frame" or "decider_combinator_frame",
  })
  f.style.horizontally_stretchable = true
  f.style.left_padding = 4
  f.style.right_padding = 4
  return f
end

-- Расстояние между дочерними элементами (vertical_spacing) бывает только у
-- flow и таблиц, не у frame/scroll-pane: поэтому содержимое кладём во flow.
local function list_flow(parent, spacing)
  local flow = parent.add({ type = "flow", name = "ns_list", direction = "vertical" })
  flow.style.vertical_spacing = spacing or 4
  flow.style.horizontally_stretchable = true
  return flow
end

local function trash_button(parent, tags)
  local b = parent.add({ type = "sprite-button", style = "tool_button_red", sprite = "utility/trash", tags = tags, tooltip = "Удалить" })
  return b
end

local function spacer(parent)
  local s = parent.add({ type = "empty-widget" })
  s.style.horizontally_stretchable = true
  return s
end

---------------------------------------------------------------------------
-- Окно комбинатора
---------------------------------------------------------------------------
local function fill_content(content, c)
  local unit = c.entity.unit_number
  local list = source_names(c)
  local each = c.each or {}

  -- Статус и превью, как у ванильных объектов
  local status = content.add({ type = "flow", name = "ns_status", direction = "horizontal" })
  status.style.vertical_align = "center"
  local sprite, text = status_view(c.entity)
  status.add({ type = "sprite", name = "ns_light", style = "status_image", sprite = sprite })
  status.add({ type = "label", name = "ns_text", caption = text })
  spacer(status)
  status.add({ type = "label", name = "ns_result", caption = result_caption(c) })

  local preview_frame = content.add({ type = "frame", style = "deep_frame_in_shallow_frame" })
  local preview = preview_frame.add({ type = "entity-preview", style = "wide_entity_button" })
  preview.style.horizontally_stretchable = true
  preview.style.height = 110
  preview.entity = c.entity

  -- Условия
  heading(content, "Условия")
  local conds = content.add({ type = "scroll-pane", name = "ns_conds", style = "deep_scroll_pane", direction = "vertical" })
  conds.style.maximal_height = 360
  conds.style.horizontally_stretchable = true
  conds.style.padding = 4
  local cond_list = list_flow(conds)
  for i, cond in ipairs(c.config.conditions) do
    local row = row_frame(cond_list, "row_" .. i, each[i])

    if i == 1 then
      local pad = row.add({ type = "empty-widget" })
      pad.style.width = 64
    else
      local dd = row.add({
        type = "drop-down", items = { "И", "ИЛИ" },
        selected_index = (cond.join == "or") and 2 or 1,
        tags = { ns_action = "join", unit = unit, row = i },
        tooltip = "Связка с предыдущим условием. «И» связывает сильнее, чем «ИЛИ»",
      })
      dd.style.width = 64
    end

    add_operand(row, c, list, cond.left, { unit = unit, row = i, side = "left" })

    local cmp = 1
    for k, v in ipairs(logic.COMPARATORS) do
      if v == cond.comparator then cmp = k end
    end
    row.add({
      type = "drop-down", style = "circuit_condition_comparator_dropdown",
      items = logic.COMPARATOR_LABELS, selected_index = cmp,
      tags = { ns_action = "comparator", unit = unit, row = i },
    })

    if cond.right.signal then
      add_operand(row, c, list, cond.right, { unit = unit, row = i, side = "right" })
    else
      local tf = row.add({
        type = "textfield", text = tostring(cond.right.constant or 0),
        numeric = true, allow_negative = true, allow_decimal = false,
        tags = { ns_action = "right_const", unit = unit, row = i },
        tooltip = "Константа. Чтобы сравнить с сигналом, выберите его в кнопке слева",
      })
      tf.style.width = 90
      add_signal_button(row, nil, { ns_action = "signal", unit = unit, row = i, side = "right" })
    end

    spacer(row)
    trash_button(row, { ns_action = "del_cond", unit = unit, row = i })
  end
  content.add({ type = "button", caption = "+ Добавить условие", tags = { ns_action = "add_cond", unit = unit } })

  -- Выходы
  heading(content, "Выход")
  local outs = content.add({ type = "scroll-pane", name = "ns_outs", style = "deep_scroll_pane", direction = "vertical" })
  outs.style.maximal_height = 240
  outs.style.horizontally_stretchable = true
  outs.style.padding = 4
  local out_list = list_flow(outs)
  for i, out in ipairs(c.config.outputs) do
    local row = row_frame(out_list, "row_" .. i, false)
    add_signal_button(row, out.signal, { ns_action = "signal", unit = unit, row = i, side = "out" })
    local mdd = row.add({
      type = "drop-down", items = { "1", "Значение со входа" },
      selected_index = (out.mode == "input") and 2 or 1,
      tags = { ns_action = "out_mode", unit = unit, row = i },
    })
    mdd.style.width = 170
    if out.mode == "input" then
      add_source_dropdown(row, c, list, out.source, { ns_action = "source", unit = unit, row = i, side = "out" })
      add_networks(row, out.networks or {}, { unit = unit, row = i, side = "out" })
    end
    spacer(row)
    trash_button(row, { ns_action = "del_out", unit = unit, row = i })
  end
  content.add({ type = "button", caption = "+ Добавить выход", tags = { ns_action = "add_out", unit = unit } })

  -- Подключённые источники
  heading(content, "Именованные источники на входе")
  local any = false
  for _, name in ipairs(list) do
    local members = c.members[name]
    if members then
      any = true
      local warn
      local r, g = false, false
      for _, m in ipairs(members) do
        if m.entity.valid then
          r = r or m.red
          g = g or m.green
          local st = sources.status(m.entity)
          if st ~= "ok" then warn = sources.STATUS_TEXT[st] end
        end
      end
      local wires = (r and (" " .. RED) or "") .. (g and (" " .. GREEN) or "")
      local caption = name .. ": объектов " .. #members .. wires
      if warn then caption = caption .. "  —  " .. warn end
      local l = wrapped_label(content, caption)
      if warn then l.style.font_color = WARN_COLOR end
    end
  end
  if not any then
    wrapped_label(content, "Нет. Подключите провод к сундуку или конвейеру и задайте ему имя в его окне.")
  end

  if logic.has_wildcards(c.config) then
    local l = wrapped_label(content, "Сигналы «каждый», «любой» и «все» пока не поддерживаются и игнорируются.")
    l.style.font_color = WARN_COLOR
  end
end

function M.fill(frame, c)
  titlebar(frame, "Сравнивающий комбинатор с именами", "close", true)
  local content = frame.add({ type = "frame", name = "ns_content", style = "entity_frame", direction = "vertical" })
  fill_content(content, c)
end

function M.open(player, c)
  M.close(player)
  combinator.refresh_members(c)
  local frame = player.gui.screen.add({ type = "frame", name = FRAME, direction = "vertical" })
  M.fill(frame, c)
  frame.force_auto_center()
  player.opened = frame
  storage.open[player.index] = c.entity.unit_number
end

function M.close(player)
  local f = player.gui.screen[FRAME]
  if f then f.destroy() end
  local h = player.gui.screen[HELP]
  if h then h.destroy() end
  storage.open[player.index] = nil
end

-- Перерисовать окно у всех игроков, у кого открыт этот комбинатор.
-- Пересобирается только содержимое: заголовок и положение окна сохраняются.
function M.refresh_for(c)
  local unit = c.entity.unit_number
  for pi, u in pairs(storage.open) do
    if u == unit then
      local p = game.get_player(pi)
      local f = p and p.gui.screen[FRAME]
      if f and f.ns_content then
        f.ns_content.clear()
        fill_content(f.ns_content, c)
      end
    end
  end
end

---------------------------------------------------------------------------
-- Справка
---------------------------------------------------------------------------
local HELP_TEXT = {
  { "Зачем это нужно",
    "В обычной игре сигналы всех объектов на одном проводе складываются, и узнать, сколько железа в конкретном сундуке, нельзя. Этот комбинатор умеет брать значение не из всей сети, а от конкретного именованного источника." },
  { "Имена источников",
    "Откройте сундук или конвейер: справа от его окна появится поле «Имя источника». Одинаковое имя у нескольких объектов объединяет их в группу, и их содержимое суммируется." },
  { "Условия",
    "Для каждого операнда выберите источник («Вся сеть» или имя), сигнал и провода R/G. Справа можно поставить константу или второй сигнал. Связки «И»/«ИЛИ» работают как в ванили: «И» связывает сильнее. Выполненные условия подсвечиваются зелёным." },
  { "Провода R и G",
    "Для «Всей сети» это обычный выбор красной и зелёной сети. Для именованного источника учитываются только объекты, подключённые к комбинатору проводом выбранного цвета. Объект, подключённый обоими проводами, считается один раз." },
  { "Выход",
    "Если условия выполнены, на выход подаются выбранные сигналы: со значением 1 или со значением со входа (из сети или от источника)." },
  { "Ограничения",
    "Конвейеры работают только в режиме «Удержание». В режимах «Импульс» и «Удержание (все конвейеры)» именованные сигналы от них не работают, об этом появится предупреждение. Сигналы «каждый», «любой» и «все» пока не поддерживаются. Остальные объекты на проводе по-прежнему видят обычную сумму." },
  { "Чертежи и копирование",
    "Настройки комбинатора и имена источников сохраняются в чертежах и копируются через Shift+ПКМ / Shift+ЛКМ." },
}

function M.toggle_help(player)
  local h = player.gui.screen[HELP]
  if h then
    h.destroy()
    return
  end
  h = player.gui.screen.add({ type = "frame", name = HELP, direction = "vertical" })
  titlebar(h, "Справка: комбинатор с именами", "help_close", false)
  local box = h.add({ type = "frame", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  local content = list_flow(box, 8)
  for _, section in ipairs(HELP_TEXT) do
    heading(content, section[1])
    wrapped_label(content, section[2], 460)
  end
  local main = player.gui.screen[FRAME]
  if main and main.location then
    h.location = { x = main.location.x + 40, y = main.location.y + 40 }
  else
    h.force_auto_center()
  end
end

---------------------------------------------------------------------------
-- Панель имени на сундуке / конвейере (пристыкована к ванильному окну)
---------------------------------------------------------------------------
local function anchor_for(entity)
  local rgt = defines.relative_gui_type
  if entity.type == "transport-belt" then return rgt.transport_belt_gui end
  return rgt.container_gui
end

local function source_status_caption(entity)
  local st = sources.status(entity)
  if st == "ok" then return "" end
  return sources.STATUS_TEXT[st]
end

local function group_caption(entity)
  local name = sources.get_name(entity)
  if not name then return "Без имени: объект не участвует в именованных сигналах" end
  local n = 0
  for _, rec in pairs(storage.sources) do
    if rec.name == name and rec.entity.valid then n = n + 1 end
  end
  return "Объектов с этим именем: " .. n
end

local function build_source_panel(frame, entity)
  local box = frame.add({ type = "frame", name = "ns_box", style = "inside_shallow_frame_with_padding", direction = "vertical" })
  local content = list_flow(box, 6)
  wrapped_label(content, "Одинаковое имя у нескольких объектов объединяет их в группу.", 240)
  local tf = content.add({ type = "textfield", text = sources.get_name(entity) or "", tags = { ns_action = "source_name" } })
  tf.style.width = 240
  content.add({ type = "label", name = "ns_group", caption = group_caption(entity) })
  local st = wrapped_label(content, source_status_caption(entity), 240, "ns_state")
  st.style.font_color = WARN_COLOR
end

function M.open_source_panel(player, entity)
  M.close_source_panel(player)
  local anchor_gui = anchor_for(entity)
  local frame
  if anchor_gui then
    frame = player.gui.relative.add({
      type = "frame", name = SRC_PANEL, direction = "vertical", caption = "Имя источника",
      anchor = { gui = anchor_gui, position = defines.relative_gui_position.right },
    })
  else
    -- Запасной вариант, если в этой версии нет нужного типа якоря.
    frame = player.gui.screen.add({ type = "frame", name = SRC_PANEL, direction = "vertical", caption = "Имя источника" })
    frame.location = { x = 20, y = 200 }
  end
  build_source_panel(frame, entity)
  storage.open_source[player.index] = entity
end

local function source_panel(player)
  return player.gui.relative[SRC_PANEL] or player.gui.screen[SRC_PANEL]
end

function M.close_source_panel(player)
  local f = player.gui.relative[SRC_PANEL]
  if f then f.destroy() end
  f = player.gui.screen[SRC_PANEL]
  if f then f.destroy() end
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

-- Операнд, на который указывают теги элемента.
local function operand_of(c, tags)
  if tags.side == "out" then return c.config.outputs[tags.row] end
  local cond = c.config.conditions[tags.row]
  if not cond then return nil end
  if tags.side == "right" then return cond.right end
  return cond.left
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
  local player = game.get_player(e.player_index)
  local a = tags.ns_action
  if a == "close" then
    if player then M.close(player) end
    return
  elseif a == "help" or a == "help_close" then
    if player then M.toggle_help(player) end
    return
  end
  local c = get_c(tags)
  if not c then return end
  local cfg = c.config
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
  if not (tags and tags.ns_action == "signal") then return end
  local c = get_c(tags)
  local op = c and operand_of(c, tags)
  if not op then return end
  op.signal = signals.copy(el.elem_value)
  if not op.signal and tags.side == "right" then op.source = nil end
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
  local a, idx = tags.ns_action, el.selected_index
  local cond = c.config.conditions[tags.row]
  local out = c.config.outputs[tags.row]
  if a == "join" and cond then
    cond.join = (idx == 2) and "or" or "and"
  elseif a == "comparator" and cond then
    cond.comparator = logic.COMPARATORS[idx] or ">"
  elseif a == "source" then
    local op = operand_of(c, tags)
    if not op then return end
    op.source = picked_name(tags, idx)
  elseif a == "out_mode" and out then
    out.mode = (idx == 2) and "input" or "one"
  else
    return
  end
  changed(c, true)
end

function M.on_checked(e)
  local el = e.element
  if not (el and el.valid) then return end
  local tags = el.tags
  if not (tags and tags.ns_action == "net") then return end
  local c = get_c(tags)
  local op = c and operand_of(c, tags)
  if not op then return end
  op.networks = op.networks or { red = true, green = true }
  op.networks[tags.color] = el.state
  changed(c, false) -- галочка уже в нужном состоянии, перерисовка не нужна
end

function M.on_text_changed(e)
  local el = e.element
  if not (el and el.valid) then return end
  local tags = el.tags
  if not (tags and tags.ns_action) then return end
  if tags.ns_action == "source_name" then
    local entity = storage.open_source[e.player_index]
    if entity and entity.valid then
      sources.set_name(entity, el.text)
      local player = game.get_player(e.player_index)
      local panel = player and source_panel(player)
      local list = panel and panel.ns_box and panel.ns_box.ns_list
      if list then list.ns_group.caption = group_caption(entity) end
    end
  elseif tags.ns_action == "right_const" then
    local c = get_c(tags)
    local cond = c and c.config.conditions[tags.row]
    if cond then
      cond.right.constant = signals.clamp(math.floor(tonumber(el.text) or 0))
      changed(c, false) -- без перерисовки, иначе поле теряет фокус
    end
  end
end

-- Периодическое обновление открытых окон: статус, подсветка условий, предупреждения.
function M.tick()
  for pi, unit in pairs(storage.open) do
    local p = game.get_player(pi)
    local c = storage.combinators[unit]
    local f = p and p.gui.screen[FRAME]
    if not (p and f and c and c.entity.valid) then
      if p then M.close(p) else storage.open[pi] = nil end
    elseif f.ns_content then
      local content = f.ns_content
      local status = content.ns_status
      if status then
        local sprite, text = status_view(c.entity)
        status.ns_light.sprite = sprite
        status.ns_text.caption = text
        status.ns_result.caption = result_caption(c)
      end
      local conds = content.ns_conds and content.ns_conds.ns_list
      if conds then
        local each = c.each or {}
        for i = 1, #c.config.conditions do
          local row = conds["row_" .. i]
          local target = each[i] and "decider_combinator_fulfilled_frame" or "decider_combinator_frame"
          if row and row.style.name ~= target then
            row.style = target
            row.style.horizontally_stretchable = true
            row.style.left_padding = 4
            row.style.right_padding = 4
          end
        end
      end
    end
  end
  for pi, entity in pairs(storage.open_source) do
    local p = game.get_player(pi)
    if not (p and entity.valid) then
      if p then M.close_source_panel(p) else storage.open_source[pi] = nil end
    else
      local panel = source_panel(p)
      local list = panel and panel.ns_box and panel.ns_box.ns_list
      if list then list.ns_state.caption = source_status_caption(entity) end
    end
  end
end

return M
