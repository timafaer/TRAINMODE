local constants = require("scripts.constants")

local storages = {}

local supported_names = {
  [constants.names.smart_storage] = true,
  [constants.names.temporary_storage] = true,
}

-- Registers a smart storage entity.
-- Регистрирует сущность умного хранилища.
function storages.register(state, entity)
  if not entity or not entity.valid or not supported_names[entity.name] then
    return nil
  end
  state.storages[entity.unit_number] = {
    id = entity.unit_number,
    entity = entity,
    surface_index = entity.surface.index,
    force_index = entity.force.index,
    selected_resource = nil,
  }
  return state.storages[entity.unit_number]
end

-- Enforces the single-item rule of temporary storage.
-- Соблюдает правило одного предмета для временного хранилища.
function storages.enforce_filters(state)
  for _, record in pairs(state.storages) do
    local entity = record.entity
    if entity and entity.valid and entity.name == constants.names.temporary_storage then
      local inventory = entity.get_inventory(defines.inventory.chest)
      if inventory then
        for index = 1, #inventory do
          local stack = inventory[index]
          if stack.valid_for_read then
            if not record.selected_resource then
              record.selected_resource = stack.name
            elseif stack.name ~= record.selected_resource then
              entity.surface.spill_item_stack({
                position = entity.position,
                stack = { name = stack.name, count = stack.count },
                enable_looted = true,
                force = entity.force,
              })
              stack.clear()
            end
          end
        end
      end
    end
  end
end

-- Removes a smart storage entity.
-- Удаляет сущность умного хранилища.
function storages.unregister(state, entity)
  if entity and entity.unit_number then
    state.storages[entity.unit_number] = nil
  end
end

-- Rebuilds station-to-storage links by proximity.
-- Перестраивает связи станций с хранилищами по расстоянию.
function storages.relink(state, radius)
  state.storages_by_station = {}
  local radius_squared = radius * radius

  for station_id, station in pairs(state.stations) do
    state.storages_by_station[station_id] = {}
  end

  for storage_id, storage_record in pairs(state.storages) do
    local entity = storage_record.entity
    local best_station_id
    local best_distance
    if entity and entity.valid then
      for station_id, station in pairs(state.stations) do
        if station.entity and station.entity.valid
          and storage_record.surface_index == station.surface_index
          and storage_record.force_index == station.force_index
        then
          local dx = entity.position.x - station.entity.position.x
          local dy = entity.position.y - station.entity.position.y
          local distance = dx * dx + dy * dy
          if distance <= radius_squared
            and (
              not best_distance
              or distance < best_distance
              or (distance == best_distance and station_id < best_station_id)
            )
          then
            best_station_id = station_id
            best_distance = distance
          end
        end
      end
    end
    storage_record.station_id = best_station_id
    if best_station_id then
      local linked = state.storages_by_station[best_station_id]
      linked[#linked + 1] = storage_id
    end
  end

  for _, linked in pairs(state.storages_by_station) do
    table.sort(linked)
  end
end

return storages
