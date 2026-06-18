local station = table.deepcopy(data.raw["train-stop"]["train-stop"])
station.name = "smart-train-stop"
station.minable.result = "smart-train-stop"
station.localised_name = { "entity-name.smart-train-stop" }
station.icon = "__TRAINMODE__/graphics/icons/trainmode-universal-256.png"
station.icon_size = 256

local locomotive = table.deepcopy(data.raw.locomotive.locomotive)
locomotive.name = "smart-locomotive"
locomotive.minable.result = "smart-locomotive"
locomotive.localised_name = { "entity-name.smart-locomotive" }
locomotive.icon = "__TRAINMODE__/graphics/icons/trainmode-universal-256.png"
locomotive.icon_size = 256
locomotive.color = { r = 0.1, g = 0.65, b = 0.85, a = 1 }

local smart_storage = table.deepcopy(data.raw.container["steel-chest"])
smart_storage.name = "smart-storage"
smart_storage.minable.result = "smart-storage"
smart_storage.inventory_size = 96
smart_storage.localised_name = { "entity-name.smart-storage" }
smart_storage.icon = "__TRAINMODE__/graphics/icons/trainmode-universal-256.png"
smart_storage.icon_size = 256

local temporary_storage = table.deepcopy(data.raw.container["steel-chest"])
temporary_storage.name = "temporary-storage"
temporary_storage.minable.result = "temporary-storage"
temporary_storage.inventory_size = 240
temporary_storage.localised_name = { "entity-name.temporary-storage" }
temporary_storage.icon = "__TRAINMODE__/graphics/icons/trainmode-universal-256.png"
temporary_storage.icon_size = 256

local belt_input = table.deepcopy(data.raw.inserter["stack-inserter"])
belt_input.name = "smart-belt-input"
belt_input.minable.result = "smart-belt-input"
belt_input.localised_name = { "entity-name.smart-belt-input" }
belt_input.icon = "__TRAINMODE__/graphics/icons/trainmode-universal-256.png"
belt_input.icon_size = 256

local belt_output = table.deepcopy(data.raw.inserter["stack-inserter"])
belt_output.name = "smart-belt-output"
belt_output.minable.result = "smart-belt-output"
belt_output.localised_name = { "entity-name.smart-belt-output" }
belt_output.icon = "__TRAINMODE__/graphics/icons/trainmode-universal-256.png"
belt_output.icon_size = 256

data:extend({
  station,
  locomotive,
  smart_storage,
  temporary_storage,
  belt_input,
  belt_output,
})
