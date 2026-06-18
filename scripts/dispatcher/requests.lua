local constants = require("scripts.constants")

local requests = {}

local function copy_positive(values)
  local result = {}
  for name, count in pairs(values or {}) do
    local known_item =
      not prototypes or not prototypes.item or prototypes.item[name]
    if count > 0 and known_item then
      result[name] = count
    end
  end
  return result
end

-- Creates one open request from a requester station.
-- Создает один открытый запрос станции-получателя.
function requests.create(state, station, resources, tick)
  local id = state.next_request_id
  state.next_request_id = id + 1
  local request = {
    id = id,
    station_id = station.id,
    surface_index = station.surface_index,
    force_index = station.force_index,
    priority = station.priority,
    created_tick = tick,
    state = constants.request_states.open,
    requested_resources = copy_positive(resources),
    remaining_resources = copy_positive(resources),
    critical_version = 1,
    delivery_ids = {},
  }
  state.requests[id] = request
  state.pending_requests[#state.pending_requests + 1] = id
  return request
end

-- Creates a request only when the station has no unfinished request.
-- Создает запрос, только если у станции нет незавершенного запроса.
function requests.ensure_for_station(state, station, resources, tick)
  for _, request in pairs(state.requests) do
    if request.station_id == station.id
      and request.state ~= constants.request_states.complete
      and request.state ~= constants.request_states.cancelled
    then
      return request
    end
  end
  if next(resources or {}) then
    return requests.create(state, station, resources, tick)
  end
  return nil
end

-- Applies delivered stacks and closes a fully satisfied request.
-- Учитывает доставленные стаки и закрывает выполненный запрос.
function requests.apply_delivery(request, resources)
  for resource, stacks in pairs(resources) do
    request.remaining_resources[resource] =
      math.max(0, (request.remaining_resources[resource] or 0) - stacks)
  end
  for _, remaining in pairs(request.remaining_resources) do
    if remaining > 0 then
      request.state = constants.request_states.partial
      request.critical_version = request.critical_version + 1
      return false
    end
  end
  request.state = constants.request_states.complete
  request.critical_version = request.critical_version + 1
  return true
end

return requests
