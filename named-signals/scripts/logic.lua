-- Движок условий. Чистая функция от (контекст сигналов, конфиг) -> выходы.
-- Не трогает game/storage: всё, что нужно, приходит через ctx.
--
-- Операнд:  { signal = SignalID, source = "имя"|nil, networks = { red = bool, green = bool } }
--   source == nil   -> значение из сети (как в ванили);
--   source == "имя" -> вклад группы источников с этим именем;
--   networks        -> какие провода учитывать (как галочки R/G в ванили 2.0).
--                      Для источника: учитываются те, кто подключён проводом этого цвета.
--
-- Конфиг комбинатора:
--   conditions = { { join = "and"|"or", left = операнд, comparator = ">"|..., right = операнд + constant } }
--   outputs    = { { signal = SignalID, mode = "one"|"input", source = ..., networks = ... } }
--
-- ctx.value(signal, source, networks) -> число
local signals = require("scripts.signals")

local M = {}

M.COMPARATORS = { ">", "<", "=", ">=", "<=", "!=" }
M.COMPARATOR_LABELS = { ">", "<", "=", "≥", "≤", "≠" }

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

local function operand_value(ctx, op)
  if not (op.signal and op.signal.name) then return 0 end
  return ctx.value(op.signal, op.source, op.networks or both())
end

function M.new_condition()
  return { join = "and", left = { networks = both() }, comparator = ">", right = { constant = 0, networks = both() } }
end

function M.new_output()
  return { mode = "one", networks = both() }
end

function M.new_config()
  return { conditions = { M.new_condition() }, outputs = { M.new_output() } }
end

local function norm_networks(n)
  if type(n) ~= "table" then return both() end
  return { red = n.red ~= false, green = n.green ~= false }
end

-- Привести конфиг к полному виду: после чертежа поля могли потеряться,
-- а конфиги 0.1.0 ещё не знают про networks.
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
    c.comparator = c.comparator or ">"
    if c.right.constant == nil then c.right.constant = 0 end
  end
  for _, o in ipairs(cfg.outputs) do
    o.mode = (o.mode == "input") and "input" or "one"
    o.networks = norm_networks(o.networks)
  end
  return cfg
end

function M.eval_condition(ctx, cond)
  local l = cond.left
  if not (l and l.signal) or signals.is_wildcard(l.signal) then return false end
  local a = operand_value(ctx, l)
  local r = cond.right or {}
  local b
  if r.signal then
    if signals.is_wildcard(r.signal) then return false end
    b = operand_value(ctx, r)
  else
    b = r.constant or 0
  end
  return compare(a, cond.comparator, b)
end

-- Как в ванили 2.0: ИЛИ из групп И (у И приоритет выше).
-- Возвращает общий результат и результаты каждого условия (для подсветки в GUI).
function M.eval_conditions(ctx, conditions)
  local each = {}
  if #conditions == 0 then return false, each end
  local result, group = false, true
  for i, cond in ipairs(conditions) do
    if i > 1 and cond.join == "or" then
      result = result or group
      group = true
    end
    each[i] = M.eval_condition(ctx, cond)
    group = group and each[i]
  end
  return result or group, each
end

-- Возвращает passed, outputs (массив { signal, count } в стабильном порядке), each.
function M.compute(ctx, cfg)
  local passed, each = M.eval_conditions(ctx, cfg.conditions)
  if not passed then return false, {}, each end
  local acc, order = {}, {}
  for _, out in ipairs(cfg.outputs) do
    local sig = out.signal
    if sig and sig.name and not signals.is_wildcard(sig) then
      local v = (out.mode == "input") and operand_value(ctx, out) or 1
      local k = signals.key(sig)
      if not acc[k] then
        acc[k] = { signal = sig, count = 0 }
        order[#order + 1] = k
      end
      acc[k].count = acc[k].count + v
    end
  end
  local res = {}
  for _, k in ipairs(order) do
    local e = acc[k]
    e.count = signals.clamp(e.count)
    if e.count ~= 0 then res[#res + 1] = e end
  end
  return true, res, each
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

function M.has_wildcards(cfg)
  for _, c in ipairs(cfg.conditions) do
    if signals.is_wildcard(c.left.signal) or signals.is_wildcard(c.right.signal) then return true end
  end
  for _, o in ipairs(cfg.outputs) do
    if signals.is_wildcard(o.signal) then return true end
  end
  return false
end

return M
