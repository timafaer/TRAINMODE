local reservations = require("scripts.dispatcher.reservations")
local train_registry = require("scripts.registry.trains")

local runtime_provider = {}

local function state()
  return storage.trainmode
end

local function valid_station(id)
  local station = state().stations[id]
  return station and station.entity and station.entity.valid and station
end

function runtime_provider.get_request(request_id)
  return state().requests[request_id]
end

function runtime_provider.get_requester_station_id(request_id)
  local request = state().requests[request_id]
  return request and request.station_id
end

function runtime_provider.get_requested_resources(request_id)
  local request = state().requests[request_id]
  return request and request.remaining_resources or {}
end

function runtime_provider.get_suitable_loading_station_ids(request_id)
  local request = state().requests[request_id]
  if not request then
    return {}
  end

  local tiers = {}
  for id, station in pairs(state().stations) do
    if station.enabled
      and station.mode == "load"
      and station.surface_index == request.surface_index
      and station.force_index == request.force_index
      and next(station.available_resources or {})
    then
      tiers[station.priority] = tiers[station.priority] or {}
      tiers[station.priority][#tiers[station.priority] + 1] = id
    end
  end
  local priorities = {}
  for priority in pairs(tiers) do
    priorities[#priorities + 1] = priority
  end
  table.sort(priorities, function(a, b) return a > b end)
  for _, priority in ipairs(priorities) do
    local ids = tiers[priority]
    local useful = false
    for _, station_id in ipairs(ids) do
      local station = state().stations[station_id]
      for resource in pairs(request.remaining_resources) do
        if (station.available_resources[resource] or 0) > 0 then
          useful = true
          break
        end
      end
    end
    if useful then
      table.sort(ids)
      return ids
    end
  end
  return {}
end

function runtime_provider.get_suitable_depot_ids(request_id)
  local request = state().requests[request_id]
  local ids = {}
  for id, depot in pairs(state().depots) do
    local station = valid_station(depot.station_ids[1])
    if station
      and station.surface_index == request.surface_index
      and station.force_index == request.force_index
      and #depot.train_ids > 0
    then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  return ids
end

function runtime_provider.get_depot_train_class(depot_id)
  local depot = state().depots[depot_id]
  local train_record = depot and state().trains[depot.train_ids[1]]
  return train_record and {
    id = train_record.capacity_stacks,
    capacity_stacks = train_record.capacity_stacks,
    cargo_type = "item",
  } or nil
end

function runtime_provider.get_depot_station_ids(depot_id)
  local depot = state().depots[depot_id]
  return depot and depot.station_ids or {}
end

function runtime_provider.get_free_train_ids(depot_id)
  local depot = state().depots[depot_id]
  local ids = {}
  for _, train_id in ipairs(depot and depot.train_ids or {}) do
    local record = state().trains[train_id]
    if record and record.train and record.train.valid
      and not state().reservations.trains[train_id]
      and train_registry.is_empty(record.train)
    then
      ids[#ids + 1] = train_id
    end
  end
  table.sort(ids)
  return ids
end

function runtime_provider.get_station_resources(station_id)
  local station = valid_station(station_id)
  local result = {}
  local reserved = reservations.get_station_resources(state(), station_id)
  for resource, stacks in pairs(station and station.available_resources or {}) do
    result[resource] = math.max(0, stacks - (reserved[resource] or 0))
  end
  return result
end

function runtime_provider.get_station_available_train_slots(station_id)
  local station = valid_station(station_id)
  if not station then
    return 0
  end
  local entity = station.entity
  local vanilla_available = math.max(0, entity.trains_limit - entity.trains_count)
  return math.max(
    0,
    vanilla_available - reservations.get_station_slots(state(), station_id)
  )
end

function runtime_provider.get_distance_between_stations(from_id, to_id)
  local from = valid_station(from_id)
  local to = valid_station(to_id)
  if not from or not to or from.surface_index ~= to.surface_index then
    return nil
  end
  local dx = from.entity.position.x - to.entity.position.x
  local dy = from.entity.position.y - to.entity.position.y
  return math.sqrt(dx * dx + dy * dy)
end

function runtime_provider.get_data_version(entity_type, entity_id)
  if entity_type == "request" then
    local value = state().requests[entity_id]
    return value and value.critical_version
  elseif entity_type == "station" then
    local value = state().stations[entity_id]
    return value and value.critical_version
  elseif entity_type == "depot" then
    local value = state().depots[entity_id]
    return value and value.critical_version
  end
end

return runtime_provider
