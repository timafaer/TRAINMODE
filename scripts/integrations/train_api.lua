local train_api = {}

local function item_count(resource, stacks)
  local prototype = prototypes.item[resource]
  return stacks * (prototype and prototype.stack_size or 1)
end

local function loading_wait_conditions(resources)
  local conditions = {}
  for resource, stacks in pairs(resources) do
    conditions[#conditions + 1] = {
      type = "item_count",
      compare_type = #conditions == 0 and "or" or "and",
      condition = {
        comparator = ">=",
        first_signal = { type = "item", name = resource },
        constant = item_count(resource, stacks),
      },
    }
  end
  return conditions
end

-- Assigns a delivery schedule to a real train.
-- Назначает реальному поезду расписание доставки.
function train_api.assign_route(state, delivery)
  local record = state.trains[delivery.train_id]
  local train = record and record.train
  if not train or not train.valid then
    return false, "invalid-train"
  end

  local records = {}
  local cumulative_resources = {}
  for _, stop in ipairs(delivery.route.stops) do
    local station = state.stations[stop.station_id]
    if not station or not station.entity.valid then
      return false, "invalid-source-station"
    end
    for resource, stacks in pairs(stop.resources) do
      cumulative_resources[resource] =
        (cumulative_resources[resource] or 0) + stacks
    end
    records[#records + 1] = {
      station = station.entity.backer_name,
      wait_conditions = loading_wait_conditions(cumulative_resources),
    }
  end

  local target = state.stations[delivery.route.request_station_id]
  if not target or not target.entity.valid then
    return false, "invalid-target-station"
  end
  records[#records + 1] = {
    station = target.entity.backer_name,
    wait_conditions = {
      { type = "empty", compare_type = "or" },
    },
  }

  record.base_schedule = train.schedule
  train.schedule = { current = 1, records = records }
  train.manual_mode = false
  if not train.recalculate_path(true) then
    return false, "no-rail-path"
  end

  record.state = "assigned"
  record.active_delivery_id = delivery.id
  delivery.state = "active"
  return true
end

-- Restores the train schedule saved before dispatcher assignment.
-- Восстанавливает расписание поезда до назначения диспетчером.
function train_api.restore_train(state, delivery)
  local record = state.trains[delivery.train_id]
  local train = record and record.train
  if record then
    record.state = "idle"
    record.active_delivery_id = nil
  end
  if train and train.valid then
    train.schedule = record.base_schedule
  end
end

return train_api
