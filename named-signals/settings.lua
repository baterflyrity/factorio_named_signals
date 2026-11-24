data:extend({
  {
    type = "int-setting",
    name = "ns-update-interval",
    setting_type = "runtime-global",
    default_value = 1,
    minimum_value = 1,
    maximum_value = 60,
    order = "a",
  },
  {
    type = "int-setting",
    name = "ns-topology-interval",
    setting_type = "runtime-global",
    default_value = 60,
    minimum_value = 10,
    maximum_value = 600,
    order = "b",
  },
})
