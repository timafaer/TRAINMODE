local constants = require("scripts.constants")
local stations = require("scripts.registry.stations")
local trains = require("scripts.registry.trains")
local depots = require("scripts.registry.depots")
local storages = require("scripts.registry.storages")

local bootstrap = {}

-- Rebuilds registries from entities already present in a save.
-- Перестраивает реестры по сущностям, уже существующим в сохранении.
function bootstrap.rebuild(state, storage_link_radius)
  for _, surface in pairs(game.surfaces) do
    for _, entity in ipairs(surface.find_entities_filtered({
      name = constants.names.station,
    })) do
      stations.register(state, entity)
    end
    for _, entity in ipairs(surface.find_entities_filtered({
      name = {
        constants.names.smart_storage,
        constants.names.temporary_storage,
      },
    })) do
      storages.register(state, entity)
    end
  end
  for _, train in ipairs(game.train_manager.get_trains({})) do
    trains.refresh(state, train)
  end
  depots.rebuild(state)
  storages.relink(state, storage_link_radius or 12)
end

return bootstrap
