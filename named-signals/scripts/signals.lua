-- Чистые помощники для работы с сигналами. Не обращаются к game/storage,
-- поэтому тестируются вне игры.
local M = {}

M.INT_MIN = -2147483648
M.INT_MAX = 2147483647

local WILDCARDS = { ["signal-each"] = true, ["signal-anything"] = true, ["signal-everything"] = true }

local function quality_name(q)
  if q == nil then return "normal" end
  if type(q) == "string" then return q end
  return q.name or "normal"
end

-- Ключ сигнала: "тип|имя|качество". Отсутствующие тип и качество приводятся
-- к значениям по умолчанию, чтобы nil и "normal" совпадали.
function M.key(sig)
  if not sig or not sig.name then return nil end
  return (sig.type or "item") .. "|" .. sig.name .. "|" .. quality_name(sig.quality)
end

-- Простая копия SignalID: в storage и тегах не должно быть LuaObject.
function M.copy(sig)
  if not sig or not sig.name then return nil end
  local q = sig.quality
  if q ~= nil and type(q) ~= "string" then q = q.name end
  return { type = sig.type, name = sig.name, quality = q }
end

function M.is_wildcard(sig)
  return sig ~= nil and sig.type == "virtual" and WILDCARDS[sig.name] == true
end

function M.clamp(v)
  if v > M.INT_MAX then return M.INT_MAX end
  if v < M.INT_MIN then return M.INT_MIN end
  return v
end

-- Добавить сигналы сети: массив { signal = SignalID, count = int }.
function M.add_signals(map, list)
  if not list then return end
  for _, s in pairs(list) do
    local k = M.key(s.signal)
    if k then map[k] = (map[k] or 0) + s.count end
  end
end

-- Добавить предметы: массив { name, count, quality } (get_contents в 2.x).
function M.add_items(map, items)
  if not items then return end
  for _, it in pairs(items) do
    local k = "item|" .. it.name .. "|" .. quality_name(it.quality)
    map[k] = (map[k] or 0) + it.count
  end
end

function M.merge(into, from)
  for k, v in pairs(from) do into[k] = (into[k] or 0) + v end
end

-- Строковое представление списка выходов: чтобы не перезаписывать
-- выход комбинатора, если ничего не изменилось.
function M.serialize(outputs)
  local parts = {}
  for i, o in ipairs(outputs) do parts[i] = M.key(o.signal) .. "=" .. o.count end
  return table.concat(parts, ";")
end

return M
