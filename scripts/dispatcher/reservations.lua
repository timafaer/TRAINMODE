local logger = require("scripts.diagnostics.logger")

local reservations = {}

-- Returns resources reserved at one source station.
-- Возвращает ресурсы, зарезервированные на станции-источнике.
function reservations.get_station_resources(state, station_id)
  return state.reservations.station_resources[station_id] or {}
end

-- Returns train-limit slots reserved at one station.
-- Возвращает места лимита, зарезервированные на станции.
function reservations.get_station_slots(state, station_id)
  return state.reservations.station_slots[station_id] or 0
end

-- Atomically reserves all resources, station slots, and trains of a plan.
-- Атомарно резервирует ресурсы, места станций и поезда плана.
function reservations.reserve_routes(state, request_id, routes)
  for _, route in ipairs(routes) do
    if state.reservations.trains[route.train_id] then
      return nil, "train-already-reserved"
    end
  end

  local delivery_ids = {}
  for _, route in ipairs(routes) do
    local delivery_id = state.next_delivery_id
    state.next_delivery_id = delivery_id + 1
    delivery_ids[#delivery_ids + 1] = delivery_id
    state.reservations.trains[route.train_id] = delivery_id
    state.reservations.station_slots[route.request_station_id] =
      (state.reservations.station_slots[route.request_station_id] or 0) + 1

    local seen_stations = {}
    for _, stop in ipairs(route.stops) do
      local station_resources =
        state.reservations.station_resources[stop.station_id] or {}
      state.reservations.station_resources[stop.station_id] = station_resources
      for resource, stacks in pairs(stop.resources) do
        station_resources[resource] =
          (station_resources[resource] or 0) + stacks
      end
      if not seen_stations[stop.station_id] then
        seen_stations[stop.station_id] = true
        state.reservations.station_slots[stop.station_id] =
          (state.reservations.station_slots[stop.station_id] or 0) + 1
      end
    end

    state.deliveries[delivery_id] = {
      id = delivery_id,
      request_id = request_id,
      train_id = route.train_id,
      route = route,
      state = "assigned",
    }
    logger.trace("delivery_reserved", {
      request_id = request_id,
      delivery_id = delivery_id,
      route = route,
    })
  end
  return delivery_ids
end

-- Releases all reservations owned by one delivery.
-- Освобождает все резервации одной доставки.
function reservations.release_delivery(state, delivery)
  local route = delivery.route
  state.reservations.trains[route.train_id] = nil
  state.reservations.station_slots[route.request_station_id] =
    math.max(
      0,
      (state.reservations.station_slots[route.request_station_id] or 0) - 1
    )
  local seen_stations = {}
  for _, stop in ipairs(route.stops) do
    local station_resources =
      state.reservations.station_resources[stop.station_id] or {}
    for resource, stacks in pairs(stop.resources) do
      station_resources[resource] =
        math.max(0, (station_resources[resource] or 0) - stacks)
    end
    if not seen_stations[stop.station_id] then
      seen_stations[stop.station_id] = true
      state.reservations.station_slots[stop.station_id] =
        math.max(0, (state.reservations.station_slots[stop.station_id] or 0) - 1)
    end
  end
  logger.trace("delivery_reservation_released", {
    request_id = delivery.request_id,
    delivery_id = delivery.id,
    train_id = delivery.train_id,
    delivery_state = delivery.state,
  })
end

return reservations
