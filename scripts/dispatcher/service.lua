local constants = require("scripts.constants")
local circuit_network = require("scripts.integrations.circuit_network")
local requests = require("scripts.dispatcher.requests")
local reservations = require("scripts.dispatcher.reservations")
local runtime_provider = require("scripts.routing.runtime_provider")
local get_ideal_routes = require("scripts.routing.get_ideal_routes")
local scheduler_module = require("scripts.routing.scheduler")
local train_api = require("scripts.integrations.train_api")
local cargo_transfer = require("scripts.integrations.cargo_transfer")

local service = {}

local function operation_budget()
  if settings and settings.global["trainmode-operation-budget"] then
    return settings.global["trainmode-operation-budget"].value
  end
  return constants.planning_operation_budget
end

local function cumulative_resources_at_station(route, station_id)
  local resources = {}
  for _, stop in ipairs(route.stops) do
    for resource, stacks in pairs(stop.resources) do
      resources[resource] = (resources[resource] or 0) + stacks
    end
    if stop.station_id == station_id then
      return resources
    end
  end
  return nil
end

local function scheduler(state)
  return scheduler_module.new(
    runtime_provider,
    function(request_id)
      return get_ideal_routes.with_provider(runtime_provider, request_id)
    end,
    state.scheduler
  )
end

local function merge_resources(first, second)
  local result = {}
  for resource, stacks in pairs(first or {}) do
    result[resource] = stacks
  end
  for resource, stacks in pairs(second or {}) do
    result[resource] = (result[resource] or 0) + stacks
  end
  return result
end

-- Refreshes source advertisements and creates requester jobs.
-- Обновляет объявления источников и создает запросы получателей.
function service.refresh_stations(state, tick)
  local planner = scheduler(state)
  for _, station in pairs(state.stations) do
    if station.entity and station.entity.valid then
      if station.mode == constants.station_modes.load then
        station.available_resources =
          circuit_network.read_red_items(station.entity)
      elseif station.mode == constants.station_modes.unload and station.enabled then
        if circuit_network.evaluate_condition(station.entity, station.condition) then
          local requested = merge_resources(
            station.manual_requests,
            circuit_network.read_green_items(station.entity)
          )
          local condition_item =
            station.condition
              and string.match(station.condition.signal or "", "^item:(.+)$")
          if condition_item and not station.manual_requests[condition_item] then
            requested[condition_item] = nil
          end
          requests.ensure_for_station(state, station, requested, tick)
        else
          for _, request in pairs(state.requests) do
            if request.station_id == station.id
              and (
                request.state == constants.request_states.open
                or request.state == constants.request_states.planning
              )
            then
              request.state = constants.request_states.cancelled
              request.critical_version = request.critical_version + 1
              planner:cancel(request.id)
            end
          end
        end
      end
    end
  end
end

local function route_uses_station(route, station_id)
  if route.request_station_id == station_id then
    return true
  end
  for _, stop in ipairs(route.stops) do
    if stop.station_id == station_id then
      return true
    end
  end
  return false
end

local function cancel_delivery(state, delivery, reason)
  delivery.state = "cancelled"
  delivery.last_error = reason
  reservations.release_delivery(state, delivery)
  train_api.restore_train(state, delivery)
  local request = state.requests[delivery.request_id]
  if request and not delivery.started_loading then
    request.state = constants.request_states.open
    state.pending_requests[#state.pending_requests + 1] = request.id
  elseif request then
    request.state = constants.request_states.error
    request.last_error = reason
  end
end

-- Cancels or errors deliveries affected by station removal.
-- Отменяет доставки, затронутые удалением станции.
function service.on_station_removed(state, station_id)
  local planner = scheduler(state)
  for _, request in pairs(state.requests) do
    if request.station_id == station_id
      and request.state ~= constants.request_states.complete
    then
      request.state = constants.request_states.cancelled
      request.critical_version = request.critical_version + 1
      planner:cancel(request.id)
    end
  end
  for _, delivery in pairs(state.deliveries) do
    if (delivery.state == "assigned" or delivery.state == "active")
      and route_uses_station(delivery.route, station_id)
    then
      cancel_delivery(state, delivery, "station-removed")
    end
  end
end

-- Releases a delivery whose train was removed or rebuilt.
-- Освобождает доставку удаленного или перестроенного поезда.
function service.on_train_removed(state, train_id)
  local record = state.trains[train_id]
  local delivery =
    record and record.active_delivery_id
      and state.deliveries[record.active_delivery_id]
  if delivery then
    cancel_delivery(state, delivery, "train-removed")
  end
end

local function enqueue_open_request(state, planner)
  local pending = {}
  local seen = {}
  for _, request_id in ipairs(state.pending_requests) do
    local request = state.requests[request_id]
    if request and request.state == constants.request_states.open
      and not seen[request_id]
    then
      seen[request_id] = true
      pending[#pending + 1] = request_id
    end
  end
  state.pending_requests = pending
  table.sort(state.pending_requests, function(left_id, right_id)
    local left = state.requests[left_id]
    local right = state.requests[right_id]
    if left.priority ~= right.priority then
      return left.priority > right.priority
    end
    return left.created_tick < right.created_tick
  end)

  for _, request_id in ipairs(state.pending_requests) do
    local request = state.requests[request_id]
    if request and request.state == constants.request_states.open
      and not planner:get_job(request_id)
    then
      local job = get_ideal_routes.with_provider(runtime_provider, request_id)
      if job then
        planner:add(job)
        request.state = constants.request_states.planning
      end
      return
    end
  end
end

local function accept_one_result(state, planner)
  for request_id, request in pairs(state.requests) do
    local routes = planner:get_result(request_id)
    if routes then
      planner:take_result(request_id)
      if routes.error or #routes == 0 then
        request.state = constants.request_states.open
        return
      end

      local target = state.stations[request.station_id]
      local available_target_slots = 0
      if target and target.entity and target.entity.valid then
        local occupied = math.max(
          target.entity.trains_count,
          reservations.get_station_slots(state, target.id)
        )
        available_target_slots = math.max(
          0,
          target.entity.trains_limit - occupied
        )
      end
      local accepted_routes = {}
      for index = 1, math.min(#routes, available_target_slots) do
        accepted_routes[#accepted_routes + 1] = routes[index]
      end
      if #accepted_routes == 0 then
        request.state = constants.request_states.open
        return
      end

      local delivery_ids, err =
        reservations.reserve_routes(state, request_id, accepted_routes)
      if not delivery_ids then
        request.state = constants.request_states.open
        request.last_error = err
        return
      end

      request.delivery_ids = delivery_ids
      request.state = constants.request_states.assigned
      local assigned_count = 0
      for _, delivery_id in ipairs(delivery_ids) do
        local delivery = state.deliveries[delivery_id]
        local ok, assign_error = train_api.assign_route(state, delivery)
        if not ok then
          delivery.state = "cancelled"
          delivery.last_error = assign_error
          reservations.release_delivery(state, delivery)
          train_api.restore_train(state, delivery)
        else
          assigned_count = assigned_count + 1
        end
      end
      if assigned_count == 0 then
        request.state = constants.request_states.open
      else
        request.state = constants.request_states.assigned
      end
      return
    end
  end
end

-- Executes one dispatcher slice. Results are reserved before another request starts.
-- Выполняет один проход диспетчера; результат резервируется до следующего запроса.
function service.tick(state)
  local planner = scheduler(state)
  accept_one_result(state, planner)
  enqueue_open_request(state, planner)
  planner:step(operation_budget())
end

-- Completes a delivery when its train is empty at the requester station.
-- Завершает доставку, когда поезд пуст на станции-получателе.
local function try_complete_train(state, train)
  local record = state.trains[train.id]
  local delivery =
    record and record.active_delivery_id
      and state.deliveries[record.active_delivery_id]
  if not delivery or delivery.state ~= "active" then
    return
  end

  local station_id =
    train.station and state.station_by_unit[train.station.unit_number]
  if not station_id then
    return
  end

  local target = state.stations[delivery.route.request_station_id]
  if target and station_id == target.id then
    cargo_transfer.unload_route(state, train, delivery.route)
  else
    local cumulative =
      cumulative_resources_at_station(delivery.route, station_id)
    if cumulative then
      delivery.started_loading = true
      cargo_transfer.load_stop(state, train, station_id, cumulative)
    end
  end

  if target and station_id == target.id and train.get_item_count() == 0 then
    delivery.state = "complete"
    reservations.release_delivery(state, delivery)
    train_api.restore_train(state, delivery)
    local request = state.requests[delivery.request_id]
    requests.apply_delivery(request, delivery.route.resources)
    if request.state == constants.request_states.partial then
      local has_active_delivery = false
      for _, delivery_id in ipairs(request.delivery_ids) do
        local other = state.deliveries[delivery_id]
        if other and (other.state == "assigned" or other.state == "active") then
          has_active_delivery = true
          break
        end
      end
      if not has_active_delivery then
        request.state = constants.request_states.open
        state.pending_requests[#state.pending_requests + 1] = request.id
      end
    end
  end
end

-- Checks one train immediately after a state transition.
-- Проверяет один поезд сразу после смены его состояния.
function service.on_train_changed_state(state, train)
  if train.state == defines.train_state.no_path
    or train.state == defines.train_state.path_lost
  then
    local record = state.trains[train.id]
    local delivery =
      record and record.active_delivery_id
        and state.deliveries[record.active_delivery_id]
    if delivery and not delivery.started_loading then
      delivery.state = "cancelled"
      delivery.last_error = "no-path"
      reservations.release_delivery(state, delivery)
      train_api.restore_train(state, delivery)
      local request = state.requests[delivery.request_id]
      request.state = constants.request_states.open
      state.pending_requests[#state.pending_requests + 1] = request.id
      return
    elseif delivery then
      delivery.last_error = "no-path-after-loading"
      return
    end
  end
  try_complete_train(state, train)
end

-- Polls active deliveries because cargo changes do not always change train state.
-- Проверяет доставки, поскольку изменение груза не всегда меняет состояние поезда.
function service.poll_deliveries(state)
  for _, delivery in pairs(state.deliveries) do
    if delivery.state == "active" then
      local record = state.trains[delivery.train_id]
      if record and record.train and record.train.valid then
        try_complete_train(state, record.train)
      end
    end
  end
end

return service
