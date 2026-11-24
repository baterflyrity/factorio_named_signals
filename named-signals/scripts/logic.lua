-- Движок условий. Чистая функция от (контекст сигналов, конфиг) -> выходы.
-- Не трогает game/storage: всё, что нужно, приходит через ctx.
--
-- Конфиг комбинатора:
--   conditions = {
--     { join = "and"|"or",               -- связка с предыдущим условием
--       left  = { signal = SignalID, source = "имя"|nil },
--       comparator = ">"|"<"|"="|">="|"<="|"!=",
--       right = { signal = SignalID|nil, source = "имя"|nil, constant = int } },
--   }
--   outputs = {
--     { signal = SignalID, mode = "one"|"input", source = "имя"|nil },
--   }
-- source == nil означает «вся сеть» (как в ванили: сумма красного и зелёного).
--
-- ctx = { network = { [key] = count }, group = function(name) -> { [key] = count } }
local signals = require("scripts.signals")

local M = {}

M.COMPARATORS = { ">", "<", "=", ">=", "<=", "!=" }
M.COMPARATOR_LABELS = { ">", "<", "=", ">=", "<=", "!=" }

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

local function operand_value(ctx, sig, source)
  local k = signals.key(sig)
  if not k then return 0 end
  local map = source and ctx.group(source) or ctx.network
  return map[k] or 0
end

function M.new_condition()
  return { join = "and", left = {}, comparator = ">", right = { constant = 0 } }
end

function M.new_output()
  return { mode = "one" }
end

function M.new_config()
  return { conditions = { M.new_condition() }, outputs = { M.new_output() } }
end

-- Привести конфиг к полному виду (после чертежа поля могли потеряться).
function M.normalize(cfg)
  cfg = cfg or {}
  cfg.conditions = cfg.conditions or {}
  cfg.outputs = cfg.outputs or {}
  for _, c in ipairs(cfg.conditions) do
    c.join = (c.join == "or") and "or" or "and"
    c.left = c.left or {}
    c.right = c.right or {}
    c.comparator = c.comparator or ">"
    if c.right.constant == nil then c.right.constant = 0 end
  end
  for _, o in ipairs(cfg.outputs) do
    o.mode = (o.mode == "input") and "input" or "one"
  end
  return cfg
end

function M.eval_condition(ctx, cond)
  local l = cond.left
  if not (l and l.signal) or signals.is_wildcard(l.signal) then return false end
  local a = operand_value(ctx, l.signal, l.source)
  local r = cond.right or {}
  local b
  if r.signal then
    if signals.is_wildcard(r.signal) then return false end
    b = operand_value(ctx, r.signal, r.source)
  else
    b = r.constant or 0
  end
  return compare(a, cond.comparator, b)
end

-- Как в ванили 2.0: ИЛИ из групп И (у И приоритет выше).
-- Пустой список условий -> ложь.
function M.eval_conditions(ctx, conditions)
  if #conditions == 0 then return false end
  local result, group = false, true
  for i, cond in ipairs(conditions) do
    if i > 1 and cond.join == "or" then
      result = result or group
      group = true
    end
    group = group and M.eval_condition(ctx, cond)
  end
  return result or group
end

-- Возвращает passed, outputs (массив { signal, count } в стабильном порядке).
function M.compute(ctx, cfg)
  if not M.eval_conditions(ctx, cfg.conditions) then return false, {} end
  local acc, order = {}, {}
  for _, out in ipairs(cfg.outputs) do
    local sig = out.signal
    if sig and sig.name and not signals.is_wildcard(sig) then
      local v = (out.mode == "input") and operand_value(ctx, sig, out.source) or 1
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
  return true, res
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
