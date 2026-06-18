local constants = require("scripts.constants")

local trains = {}

local function is_smart_train(train)
  for _, locomotive in ipairs(train.locomotives.front_movers) do
    if locomotive.name == constants.names.locomotive then
      return true
    end
  end
  for _, locomotive in ipairs(train.locomotives.back_movers) do
    if locomotive.name == constants.names.locomotive then
      return true
    end
  end
  return false
end

local function capacity_stacks(train)
  local capacity = 0
  for _, wagon in ipairs(train.cargo_wagons) do
    local inventory = wagon.get_inventory(defines.inventory.cargo_wagon)
    if inventory then
      capacity = capacity + #inventory
    end
  end
  return capacity
end

-- Registers or refreshes one smart train.
-- Регистрирует или обновляет один умный поезд.
function trains.refresh(state, train)
  if not train or not train.valid or not is_smart_train(train) then
    return nil
  end
  local record = state.trains[train.id] or {
    id = train.id,
    state = "idle",
    depot_id = nil,
    active_delivery_id = nil,
    base_schedule = train.schedule,
    critical_version = 1,
  }
  record.train = train
  record.surface_index = train.front_stock.surface.index
  record.force_index = train.front_stock.force.index
  record.capacity_stacks = capacity_stacks(train)
  state.trains[train.id] = record
  return record
end

-- Removes obsolete IDs created by train split or merge.
-- Удаляет устаревшие id после разделения или объединения поезда.
function trains.remove(state, train_id)
  if train_id then
    state.trains[train_id] = nil
  end
end

-- Returns true when a train has no item or fluid cargo.
-- Возвращает true, если в поезде нет предметов и жидкостей.
function trains.is_empty(train)
  return train.get_item_count() == 0 and next(train.get_fluid_contents()) == nil
end

return trains
