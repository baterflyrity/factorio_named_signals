-- Стоимость рецептов мода относительно оригиналов игры.
-- Ингредиенты берутся из рецептов игры и умножаются на коэффициент, поэтому
-- наценка сохраняется, даже если другой мод или новая версия игры изменит оригинал.
local M = {}

M.COMBINATOR = 1.5 -- комбинатор: +50% к сравнивающему комбинатору
M.RELAY = 1.3      -- ЛЭП-реле: +30% к средней опоре + выключателю питания

-- Умножить ингредиенты. Предметы бывают только целыми: округляем ВВЕРХ,
-- чтобы наценка не оказалась меньше заявленной. Жидкости — точно.
function M.scale(ingredients, factor)
  local res = {}
  for i, ing in ipairs(ingredients or {}) do
    local amount = (ing.amount or 1) * factor
    if (ing.type or "item") == "item" then
      amount = math.ceil(amount - 1e-9) -- 1e-9: 2 × 1.5 = 3, а не 4 из-за погрешности
    end
    res[i] = { type = ing.type or "item", name = ing.name, amount = amount }
  end
  return res
end

return M
