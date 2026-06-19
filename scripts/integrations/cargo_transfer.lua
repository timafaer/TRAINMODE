local cargo_transfer = {}

local function item_count(resource, stacks)
  local prototype = prototypes.item[resource]
  return stacks * (prototype and prototype.stack_size or 1)
end

local function storage_inventories(state, station_id)
  local inventories = {}
  for _, storage_id in ipairs(state.storages_by_station[station_id] or {}) do
    local record = state.storages[storage_id]
    local entity = record and record.entity
    if entity and entity.valid then
      local inventory = entity.get_inventory(defines.inventory.chest)
      if inventory then
        inventories[#inventories + 1] = inventory
      end
    end
  end
  return inventories
end

local function train_inventories(train)
  local inventories = {}
  for _, wagon in ipairs(train.cargo_wagons) do
    local inventory = wagon.get_inventory(defines.inventory.cargo_wagon)
    if inventory then
      inventories[#inventories + 1] = inventory
    end
  end
  return inventories
end

local function move_item(from_inventories, to_inventories, resource, wanted)
  local moved = 0
  for _, from in ipairs(from_inventories) do
    if moved >= wanted then
      break
    end
    local available = from.get_item_count(resource)
    local remaining = math.min(available, wanted - moved)
    for _, to in ipairs(to_inventories) do
      if remaining <= 0 then
        break
      end
      local inserted = to.insert({ name = resource, count = remaining })
      if inserted > 0 then
        from.remove({ name = resource, count = inserted })
        moved = moved + inserted
        remaining = remaining - inserted
      end
    end
  end
  return moved
end

-- Moves one delivery's required items from linked storages into the train.
-- Перемещает требуемые предметы из связанных хранилищ в поезд.
function cargo_transfer.load_stop(state, train, station_id, resources)
  local complete = true
  local storages = storage_inventories(state, station_id)
  local wagons = train_inventories(train)

  for resource, stacks in pairs(resources) do
    local required = item_count(resource, stacks)
    local current = train.get_item_count(resource)
    if current < required then
      move_item(storages, wagons, resource, required - current)
      current = train.get_item_count(resource)
    end
    if current < required then
      complete = false
    end
  end
  return complete
end

-- Moves delivery items from the train into requester-linked storages.
-- Перемещает предметы доставки из поезда в хранилища получателя.
function cargo_transfer.unload_route(state, train, route)
  local storages = storage_inventories(state, route.request_station_id)
  local wagons = train_inventories(train)
  local complete = true

  for resource in pairs(route.resources) do
    local remaining = train.get_item_count(resource)
    if remaining > 0 then
      move_item(wagons, storages, resource, remaining)
    end
    if train.get_item_count(resource) > 0 then
      complete = false
    end
  end
  return complete
end

return cargo_transfer
