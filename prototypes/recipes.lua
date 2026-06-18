data:extend({
  {
    type = "recipe",
    name = "smart-train-stop",
    enabled = false,
    ingredients = {
      { type = "item", name = "train-stop", amount = 1 },
      { type = "item", name = "radar", amount = 1 },
      { type = "item", name = "processing-unit", amount = 5 },
    },
    results = { { type = "item", name = "smart-train-stop", amount = 1 } },
  },
  {
    type = "recipe",
    name = "smart-locomotive",
    enabled = false,
    ingredients = {
      { type = "item", name = "locomotive", amount = 1 },
      { type = "item", name = "processing-unit", amount = 20 },
      { type = "item", name = "radar", amount = 1 },
    },
    results = { { type = "item", name = "smart-locomotive", amount = 1 } },
  },
  {
    type = "recipe",
    name = "smart-storage",
    enabled = false,
    ingredients = {
      { type = "item", name = "steel-chest", amount = 2 },
      { type = "item", name = "processing-unit", amount = 5 },
    },
    results = { { type = "item", name = "smart-storage", amount = 1 } },
  },
  {
    type = "recipe",
    name = "temporary-storage",
    enabled = false,
    ingredients = {
      { type = "item", name = "steel-chest", amount = 5 },
      { type = "item", name = "assembling-machine-3", amount = 1 },
      { type = "item", name = "processing-unit", amount = 10 },
    },
    results = { { type = "item", name = "temporary-storage", amount = 1 } },
  },
  {
    type = "recipe",
    name = "smart-belt-input",
    enabled = false,
    ingredients = {
      { type = "item", name = "stack-inserter", amount = 1 },
      { type = "item", name = "processing-unit", amount = 2 },
    },
    results = { { type = "item", name = "smart-belt-input", amount = 1 } },
  },
  {
    type = "recipe",
    name = "smart-belt-output",
    enabled = false,
    ingredients = {
      { type = "item", name = "stack-inserter", amount = 1 },
      { type = "item", name = "processing-unit", amount = 2 },
    },
    results = { { type = "item", name = "smart-belt-output", amount = 1 } },
  },
})
