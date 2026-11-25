-- Движок условий. Чистая функция от (контекст сигналов, конфиг) -> выходы.
-- Не трогает game/storage: всё, что нужно, приходит через ctx.
--
-- Операнд:
--   { signal = SignalID, source = "имя"|nil, networks = { red, green }, agg = "sum"|"min"|"max"|"avg"|"count" }
--   source == nil   -> сигналы сети (как в ванили), agg не используется;
--   source == "имя" -> сигналы группы источников, свёрнутые агрегатом agg;
--   networks        -> какие провода учитывать (галочки R/G).
--
-- Конфиг:
--   conditions = { { join = "and"|"or", left = операнд, comparator, right = операнд + constant } }
--   outputs    = { { signal, mode = "one"|"input", source, networks, agg } }
--
-- Контекст: ctx.map(source, networks, agg) -> { [ключ сигнала] = число } (без нулей).
--
-- Спецсигналы (как в ванили 2.0):
--   «любой»/«все» слева — условие проверяется по всем сигналам карты операнда;
--   «каждый» (слева и/или справа) — вся схема считается по каждому сигналу S
--   отдельно; S берутся из карт всех операндов «каждый». На выходе «каждый»
--   выдаёт прошедшие S, «все» — все сигналы карты выхода, обычный сигнал —
--   сумму по прошедшим S.
local signals = require("scripts.signals")

local M = {}

M.COMPARATORS = { ">", "<", "=", ">=", "<=", "!=" }
M.COMPARATOR_LABELS = { ">", "<", "=", "≥", "≤", "≠" }
M.AGGREGATES = { "sum", "min", "max", "avg", "count" }
M.AGGREGATE_LABELS = { "сумма", "мин", "макс", "средн.", "кол-во" }

local WILD = { ["signal-each"] = "each", ["signal-anything"] = "anything", ["signal-everything"] = "everything" }

function M.wildcard(sig)
  if sig and sig.type == "virtual" then return WILD[sig.name] end
  return nil
end
local wild = M.wildcard

local function compare(a, op, b)
  if op == ">" then return a > b
  elseif op == "<" then return a < b
  elseif op == "=" then return a == b
  elseif op == ">=" then return a >= b
  elseif op == "<=" then return a <= b
  elseif op == "!=" then return a ~= b
  end
  return false
end

local function both() return { red = true, green = true } end

function M.operand_map(ctx, op)
  return ctx.map(op.source, op.networks or both(), op.source and (op.agg or "sum") or nil)
end
local op_map = M.operand_map

-- Значение операнда: для обычного сигнала — его значение, для «каждого» — значение S.
local function scalar(ctx, op, S)
  local k
  if wild(op.signal) == "each" then k = S else k = signals.key(op.signal) end
  if not k then return 0 end
  return op_map(ctx, op)[k] or 0
end

-- nil = правая часть недопустима (условие ложно).
local function right_value(ctx, cond, S)
  local r = cond.right
  if r.signal then
    local w = wild(r.signal)
    if w == "anything" or w == "everything" then return nil end
    if w == "each" and not S then return nil end
    return scalar(ctx, r, S)
  end
  return r.constant or 0
end

function M.eval_condition(ctx, cond, S)
  local l = cond.left
  if not (l and l.signal and l.signal.name) then return false end
  local w = wild(l.signal)
  if w == "each" and not S then return false end
  local b = right_value(ctx, cond, S)
  if b == nil then return false end
  if w == "anything" or w == "everything" then
    local any, all = false, true
    for _, v in pairs(op_map(ctx, l)) do
      if v ~= 0 then
        if compare(v, cond.comparator, b) then any = true else all = false end
      end
    end
    if w == "anything" then return any end
    return all -- «все» на пустой карте истинно, как в ванили
  end
  return compare(scalar(ctx, l, S), cond.comparator, b)
end

-- ИЛИ из групп И (у И приоритет выше). Возвращает итог и результаты условий.
local function combine(ctx, conditions, S)
  local each = {}
  if #conditions == 0 then return false, each end
  local result, group = false, true
  for i, cond in ipairs(conditions) do
    if i > 1 and cond.join == "or" then
      result = result or group
      group = true
    end
    each[i] = M.eval_condition(ctx, cond, S)
    group = group and each[i]
  end
  return result or group, each
end

function M.eval_conditions(ctx, conditions)
  return combine(ctx, conditions, nil)
end

function M.uses_each(cfg)
  for _, c in ipairs(cfg.conditions) do
    if wild(c.left.signal) == "each" or wild(c.right.signal) == "each" then return true end
  end
  return false
end

-- Множество S для режима «каждый»: объединение карт всех операндов «каждый».
local function each_keys(ctx, cfg)
  local set = {}
  for _, c in ipairs(cfg.conditions) do
    for _, op in ipairs({ c.left, c.right }) do
      if wild(op.signal) == "each" then
        for k, v in pairs(op_map(ctx, op)) do
          if v ~= 0 then set[k] = true end
        end
      end
    end
  end
  local keys = {}
  for k in pairs(set) do keys[#keys + 1] = k end
  table.sort(keys)
  return keys
end

-- Возвращает passed, outputs (массив { signal, count } в стабильном порядке), per_condition.
function M.compute(ctx, cfg)
  local conds = cfg.conditions
  local each_mode = M.uses_each(cfg)
  local passed, per = false, {}
  local passing = {}

  if each_mode then
    for _, S in ipairs(each_keys(ctx, cfg)) do
      local ok, res = combine(ctx, conds, S)
      for i, r in ipairs(res) do per[i] = per[i] or r end
      if ok then passing[#passing + 1] = S end
    end
    for i = 1, #conds do per[i] = per[i] or false end
    passed = #passing > 0
  else
    passed, per = combine(ctx, conds, nil)
  end
  if not passed then return false, {}, per end

  local acc, order = {}, {}
  local function add(k, v)
    if not acc[k] then
      acc[k] = 0
      order[#order + 1] = k
    end
    acc[k] = acc[k] + v
  end

  for _, out in ipairs(cfg.outputs) do
    local sig = out.signal
    local w = wild(sig)
    if sig and sig.name and w ~= "anything" then
      local input = out.mode == "input"
      if w == "each" or w == "everything" then
        local m = op_map(ctx, out)
        -- «каждый» без «каждого» в условиях ведёт себя как «все»
        local keys = (w == "each" and each_mode) and passing or signals.sorted_keys(m)
        for _, k in ipairs(keys) do add(k, input and (m[k] or 0) or 1) end
      else
        local k = signals.key(sig)
        local v = input and (op_map(ctx, out)[k] or 0) or 1
        add(k, v * (each_mode and #passing or 1))
      end
    end
  end

  local res = {}
  for _, k in ipairs(order) do
    local v = signals.clamp(acc[k])
    if v ~= 0 then res[#res + 1] = { signal = signals.from_key(k), count = v } end
  end
  return true, res, per
end

---------------------------------------------------------------------------
-- Конфиг
---------------------------------------------------------------------------
function M.new_condition()
  return { join = "and", left = { networks = both(), agg = "sum" }, comparator = ">",
           right = { constant = 0, networks = both(), agg = "sum" } }
end

function M.new_output()
  return { mode = "one", networks = both(), agg = "sum" }
end

function M.new_config()
  return { conditions = { M.new_condition() }, outputs = { M.new_output() } }
end

local function norm_networks(n)
  if type(n) ~= "table" then return both() end
  return { red = n.red ~= false, green = n.green ~= false }
end

local AGG_SET = { sum = true, min = true, max = true, avg = true, count = true }
local function norm_agg(a) return AGG_SET[a] and a or "sum" end

-- Привести конфиг к полному виду (чертежи, конфиги старых версий).
function M.normalize(cfg)
  cfg = cfg or {}
  cfg.conditions = cfg.conditions or {}
  cfg.outputs = cfg.outputs or {}
  for _, c in ipairs(cfg.conditions) do
    c.join = (c.join == "or") and "or" or "and"
    c.left = c.left or {}
    c.right = c.right or {}
    c.left.networks = norm_networks(c.left.networks)
    c.right.networks = norm_networks(c.right.networks)
    c.left.agg = norm_agg(c.left.agg)
    c.right.agg = norm_agg(c.right.agg)
    c.comparator = c.comparator or ">"
    if c.right.constant == nil then c.right.constant = 0 end
  end
  for _, o in ipairs(cfg.outputs) do
    o.mode = (o.mode == "input") and "input" or "one"
    o.networks = norm_networks(o.networks)
    o.agg = norm_agg(o.agg)
  end
  return cfg
end

function M.referenced_sources(cfg)
  local set = {}
  for _, c in ipairs(cfg.conditions) do
    if c.left.source then set[c.left.source] = true end
    if c.right.signal and c.right.source then set[c.right.source] = true end
  end
  for _, o in ipairs(cfg.outputs) do
    if o.mode == "input" and o.source then set[o.source] = true end
  end
  return set
end

-- Предупреждения о неподдерживаемых сочетаниях — для окна комбинатора.
function M.warnings(cfg)
  local list = {}
  for _, c in ipairs(cfg.conditions) do
    local w = wild(c.right.signal)
    if w == "anything" or w == "everything" then
      list[#list + 1] = "«Любой» и «все» справа не поддерживаются: такое условие всегда ложно."
      break
    end
  end
  for _, c in ipairs(cfg.conditions) do
    local wl, wr = wild(c.left.signal), wild(c.right.signal)
    if wr == "each" and (wl == "anything" or wl == "everything") then
      list[#list + 1] = "«Каждый» справа работает только с обычным сигналом или «каждым» слева."
      break
    end
  end
  local each_mode = M.uses_each(cfg)
  for _, o in ipairs(cfg.outputs) do
    local w = wild(o.signal)
    if w == "anything" then
      list[#list + 1] = "«Любой» на выходе не поддерживается и игнорируется."
    elseif w == "each" and not each_mode then
      list[#list + 1] = "«Каждый» на выходе без «каждого» в условиях выдаёт все сигналы, как «все»."
    end
  end
  return list
end

return M
