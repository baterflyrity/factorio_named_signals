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

-- Обратное к key(): SignalID из ключа "тип|имя|качество".
function M.from_key(k)
  local t, n, q = k:match("^([^|]*)|(.*)|([^|]*)$")
  return { type = t, name = n, quality = q }
end

-- Ключи карты в стабильном порядке (для детерминированного выхода и GUI).
function M.sorted_keys(map)
  local keys = {}
  for k, v in pairs(map) do
    if v ~= 0 then keys[#keys + 1] = k end
  end
  table.sort(keys)
  return keys
end

-- Свернуть карты объектов группы в одну.
--   sum   — сумма;
--   min   — минимум по объектам (объект без сигнала считается за 0);
--   max   — максимум;
--   avg   — среднее по всем объектам группы, с округлением вниз;
--   count — число объектов, в которых сигнал есть (не 0).
function M.aggregate(maps, agg)
  local n = #maps
  local res = {}
  if n == 0 then return res end
  local keys = {}
  for _, m in ipairs(maps) do
    for k, v in pairs(m) do
      if v ~= 0 then keys[k] = true end
    end
  end
  for k in pairs(keys) do
    local sum, mn, mx, cnt = 0, nil, nil, 0
    for _, m in ipairs(maps) do
      local v = m[k] or 0
      sum = sum + v
      if mn == nil or v < mn then mn = v end
      if mx == nil or v > mx then mx = v end
      if v ~= 0 then cnt = cnt + 1 end
    end
    local v
    if agg == "min" then v = mn
    elseif agg == "max" then v = mx
    elseif agg == "avg" then v = math.floor(sum / n)
    elseif agg == "count" then v = cnt
    else v = sum end
    if v ~= 0 then res[k] = M.clamp(v) end
  end
  return res
end

-- Иконка сигнала для подсказок (rich text).
local RICH = {
  item = "item", fluid = "fluid", virtual = "virtual-signal", entity = "entity", recipe = "recipe",
  quality = "quality", ["space-location"] = "space-location", ["asteroid-chunk"] = "asteroid-chunk",
}
function M.rich(k)
  local s = M.from_key(k)
  local tag = RICH[s.type]
  if not tag then return s.name end
  if s.quality and s.quality ~= "normal" and (s.type == "item" or s.type == "fluid" or s.type == "virtual") then
    return "[" .. tag .. "=" .. s.name .. ",quality=" .. s.quality .. "]"
  end
  return "[" .. tag .. "=" .. s.name .. "]"
end

return M
