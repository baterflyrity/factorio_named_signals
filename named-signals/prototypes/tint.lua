-- Подкраска спрайтов: красим обычные слои, тени и свечение не трогаем.
return function(node, tint)
  local function walk(n)
    if type(n) ~= "table" then return end
    if n.filename and not n.draw_as_shadow and not n.draw_as_glow and n.blend_mode ~= "additive" then
      n.tint = tint
    end
    for _, v in pairs(n) do
      if type(v) == "table" then walk(v) end
    end
  end
  walk(node)
end
