data:extend({
  {
    type = "technology",
    name = "smart-train-logistics",
    icon = "__base__/graphics/technology/automated-rail-transportation.png",
    icon_size = 256,
    prerequisites = { "automated-rail-transportation", "advanced-circuit" },
    unit = {
      count = 300,
      ingredients = {
        { "automation-science-pack", 1 },
        { "logistic-science-pack", 1 },
        { "chemical-science-pack", 1 },
      },
      time = 30,
    },
    effects = {
      { type = "unlock-recipe", recipe = "smart-train-stop" },
      { type = "unlock-recipe", recipe = "smart-locomotive" },
      { type = "unlock-recipe", recipe = "smart-storage" },
      { type = "unlock-recipe", recipe = "temporary-storage" },
      { type = "unlock-recipe", recipe = "smart-belt-input" },
      { type = "unlock-recipe", recipe = "smart-belt-output" },
    },
  },
})
