data:extend({
  {
    type = "int-setting",
    name = "trainmode-operation-budget",
    setting_type = "runtime-global",
    default_value = 100,
    minimum_value = 1,
    maximum_value = 10000,
    order = "a",
  },
  {
    type = "int-setting",
    name = "trainmode-storage-link-radius",
    setting_type = "runtime-global",
    default_value = 12,
    minimum_value = 2,
    maximum_value = 64,
    order = "b",
  },
})
