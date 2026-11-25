-- Общие константы для data- и control-стадии.
return {
  combinator = "ns-decider-combinator",
  output = "ns-decider-output",
  tint = { r = 0.62, g = 0.78, b = 1.0, a = 1.0 },

  -- ЛЭП-реле (с 0.4.0). Видимая часть — опора, поэтому у неё один медный сокет.
  relay_item = "ns-relay-pole",        -- предмет и рецепт
  relay = "ns-relay-mast",             -- видимая опора: зона 7x7, один сокет
  relay_switch = "ns-relay-pole",      -- скрытый выключатель (в 0.3.x это была видимая часть,
                                       -- имя сохранено, чтобы старые реле дожили до миграции)
  relay_input = "ns-relay-pole-input", -- скрытая входная опора: сюда переносятся провода
  relay_tint = { r = 0.62, g = 0.78, b = 1.0, a = 1.0 },
}
