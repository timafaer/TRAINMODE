local combinator = require("scripts.routing.combinator")
local route_search = require("scripts.routing.route_search")

local route_optimizer = {}

-- Compares saved and current entity versions.
-- Сравнивает сохраненную и текущую версии сущности.
local function values_equal(left, right)
  return left == right
end

-- Builds resource requirements grouped by stations used in final routes.
-- Собирает требования ресурсов по станциям итоговых маршрутов.
local function collect_route_requirements(job)
  local station_ids = {}
  local station_seen = {}
  local depot_ids = {}
  local depot_seen = {}
  local required_resources = {}
  local required_station_slots = {}

  for _, route in ipairs(job.routes) do
    if not depot_seen[route.depot_id] then
      depot_seen[route.depot_id] = true
      depot_ids[#depot_ids + 1] = route.depot_id
    end

    for _, stop in ipairs(route.stops) do
      local station_id = stop.station_id
      if not station_seen[station_id] then
        station_seen[station_id] = true
        station_ids[#station_ids + 1] = station_id
        required_resources[station_id] = {}
        required_station_slots[station_id] = 0
      end
      required_station_slots[station_id] =
        required_station_slots[station_id] + 1

      for resource, stacks in pairs(stop.resources) do
        local requirements = required_resources[station_id]
        requirements[resource] = (requirements[resource] or 0) + stacks
      end
    end
  end

  table.sort(station_ids)
  table.sort(depot_ids)
  return station_ids, depot_ids, required_resources, required_station_slots
end

-- Returns stable resource names for incremental validation.
-- Возвращает стабильный список ресурсов для пошаговой проверки.
local function sorted_resource_names(resources)
  local names = {}
  for resource in pairs(resources) do
    names[#names + 1] = resource
  end
  table.sort(names)
  return names
end

-- Checks one saved entity version per operation.
-- Проверяет одну сохраненную версию сущности за одну операцию.
local function step_validation(job, provider)
  local state = job.validation_state

  if not state then
    local station_ids, depot_ids, required_resources, required_station_slots =
      collect_route_requirements(job)
    state = {
      phase = "request",
      station_index = 1,
      depot_index = 1,
      route_index = 1,
      station_ids = station_ids,
      depot_ids = depot_ids,
      required_resources = required_resources,
      required_station_slots = required_station_slots,
      resource_station_index = 1,
      resource_index = 1,
      limit_station_index = 1,
    }
    job.validation_state = state
  end

  if state.phase == "request" then
    -- Повторно читает версию запроса перед выдачей рассчитанных маршрутов.
    local current = provider.get_data_version("request", job.request_id)
    if not values_equal(current, job.versions.request) then
      job.status = "restart_required"
      return
    end
    state.phase = "stations"
    return
  end

  if state.phase == "stations" then
    local station_id = state.station_ids[state.station_index]
    if station_id then
      -- Проверяет критичную структурную версию используемой станции.
      local current = provider.get_data_version("station", station_id)
      if not values_equal(current, job.versions.stations[station_id]) then
        job.status = "restart_required"
        return
      end
      state.station_index = state.station_index + 1
      return
    end
    state.phase = "station_limits"
  end

  if state.phase == "station_limits" then
    local station_id = state.station_ids[state.limit_station_index]
    if station_id then
      -- Проверяет, что станция еще может принять все назначенные ей маршруты.
      local available =
        provider.get_station_available_train_slots(station_id) or 0
      if available < state.required_station_slots[station_id] then
        job.status = "restart_required"
        return
      end
      state.limit_station_index = state.limit_station_index + 1
      return
    end
    state.phase = "station_resources"
  end

  if state.phase == "station_resources" then
    local station_id = state.station_ids[state.resource_station_index]
    if not station_id then
      state.phase = "depots"
    elseif not state.current_station_resources then
      -- Читает актуальные ресурсы одной используемой станции.
      state.current_station_resources =
        provider.get_station_resources(station_id)
      state.current_resource_names =
        sorted_resource_names(state.required_resources[station_id])
      state.resource_index = 1
      return
    else
      local resource = state.current_resource_names[state.resource_index]
      if resource then
        local required = state.required_resources[station_id][resource]
        local available = state.current_station_resources[resource] or 0
        if available < required then
          job.status = "restart_required"
          return
        end
        state.resource_index = state.resource_index + 1
        return
      end

      state.resource_station_index = state.resource_station_index + 1
      state.current_station_resources = nil
      state.current_resource_names = nil
      return
    end
  end

  if state.phase == "depots" then
    local depot_id = state.depot_ids[state.depot_index]
    if depot_id then
      -- Повторно читает версию одного подходящего депо.
      local current = provider.get_data_version("depot", depot_id)
      if not values_equal(current, job.versions.depots[depot_id]) then
        job.status = "restart_required"
        return
      end
      state.depot_index = state.depot_index + 1
      return
    end
    state.phase = "trains"
  end

  if state.phase == "trains" then
    local route = job.routes[state.route_index]
    if route then
      -- Получает актуальную выборку поездов для проверки одного маршрута.
      local free_train_ids = provider.get_free_train_ids(route.depot_id)
      local free_train_set = {}
      for _, train_id in ipairs(free_train_ids) do
        free_train_set[train_id] = true
      end
      if not free_train_set[route.train_id] then
        job.status = "restart_required"
        return
      end
      state.route_index = state.route_index + 1
      return
    end

    job.phase = "completed"
    job.status = "completed"
  end
end

-- Performs exactly one resumable planning operation.
-- Выполняет ровно одну возобновляемую операцию планирования.
function route_optimizer.step(job, provider)
  if not job or job.status ~= "running" then
    return job
  end

  if job.phase == "combinatorics" then
    combinator.step(job, provider)
  elseif job.phase == "route_search" then
    route_search.step(job, provider)
  elseif job.phase == "validation" then
    step_validation(job, provider)
  end

  return job
end

return route_optimizer
