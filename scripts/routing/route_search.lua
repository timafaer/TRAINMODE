local route_search = {}

-- Produces a stable pseudo-random one-based index.
-- Получает стабильный псевдослучайный индекс, начинающийся с единицы.
local function deterministic_index(request_id, depot_id, version, count, salt)
  if count == 0 then
    return nil
  end

  local value =
    (request_id * 1103515245 + depot_id * 12345 + (version or 0) * 97 + salt)
      % 2147483647
  return (value % count) + 1
end

-- Builds a directional cache key for two stations.
-- Строит направленный ключ кеша для двух станций.
local function distance_key(from_station_id, to_station_id)
  return tostring(from_station_id) .. ":" .. tostring(to_station_id)
end

-- Returns a cached distance or lazily requests and stores it.
-- Возвращает расстояние из кеша либо лениво получает и сохраняет его.
local function get_cached_distance(job, provider, from_station_id, to_station_id)
  local key = distance_key(from_station_id, to_station_id)
  local cached = job.distance_cache[key]
  if cached ~= nil then
    return cached == false and nil or cached
  end

  -- Вычисляет расстояние только для одной реально рассматриваемой пары станций.
  local distance =
    provider.get_distance_between_stations(from_station_id, to_station_id)
  job.distance_cache[key] = distance or false
  return distance
end

-- Extracts unique loading station ids in stable order.
-- Извлекает уникальные id станций загрузки в стабильном порядке.
local function unique_station_ids(stops)
  local result = {}
  local seen = {}

  for _, stop in ipairs(stops) do
    if not seen[stop.station_id] then
      seen[stop.station_id] = true
      result[#result + 1] = stop.station_id
    end
  end

  table.sort(result)
  return result
end

-- Finds the resource stop of a load plan by station id.
-- Находит остановку плана загрузки по id станции.
local function find_stop(load_plan, station_id)
  for _, stop in ipairs(load_plan.stops) do
    if stop.station_id == station_id then
      return stop
    end
  end
  return nil
end

-- Converts the backward station sequence into the forward stop sequence.
-- Преобразует обратную последовательность станций в прямые остановки.
local function reverse_stops(load_plan, reverse_station_ids)
  local stops = {}
  for index = #reverse_station_ids, 1, -1 do
    stops[#stops + 1] =
      find_stop(load_plan, reverse_station_ids[index])
  end
  return stops
end

-- Returns sorted ids that have not been consumed by this job.
-- Возвращает отсортированные id, еще не использованные этой задачей.
local function copy_without_used(ids, used_ids)
  local result = {}
  for _, id in ipairs(ids) do
    if not used_ids[id] then
      result[#result + 1] = id
    end
  end
  table.sort(result)
  return result
end

-- Initializes backward search for one load plan.
-- Инициализирует обратный поиск для одного плана загрузки.
local function start_plan(job)
  local state = job.route_state
  local load_plan = job.load_plans[state.plan_index]

  if not load_plan then
    job.phase = "validation"
    return
  end

  state.load_plan = load_plan
  state.remaining_station_ids = unique_station_ids(load_plan.stops)
  state.reverse_station_ids = {}
  state.current_station_id = job.request_station_id
  state.candidate_index = 1
  state.best_station_id = nil
  state.best_distance = nil
  state.total_distance = 0
  state.phase = "evaluate_station"
end

-- Evaluates one possible previous station in the backward route.
-- Оценивает одну возможную предыдущую станцию обратного маршрута.
local function evaluate_one_station(job, provider)
  local state = job.route_state
  local candidate_id = state.remaining_station_ids[state.candidate_index]

  if not candidate_id then
    if not state.best_station_id then
      job.status = "failed"
      job.error = "no_path_to_loading_station"
      return
    end

    state.reverse_station_ids[#state.reverse_station_ids + 1] =
      state.best_station_id
    state.current_station_id = state.best_station_id
    state.total_distance = state.total_distance + state.best_distance

    for index, station_id in ipairs(state.remaining_station_ids) do
      if station_id == state.best_station_id then
        table.remove(state.remaining_station_ids, index)
        break
      end
    end

    if #state.remaining_station_ids == 0 then
      state.depot_candidate_index = 1
      state.viable_depots = {}
      state.phase = "select_depot"
    else
      state.candidate_index = 1
      state.best_station_id = nil
      state.best_distance = nil
    end
    return
  end

  local distance =
    get_cached_distance(job, provider, state.current_station_id, candidate_id)

  if distance
    and (
      not state.best_distance
      or distance < state.best_distance
      or (distance == state.best_distance and candidate_id < state.best_station_id)
    )
  then
    state.best_station_id = candidate_id
    state.best_distance = distance
  end

  state.candidate_index = state.candidate_index + 1
end

-- Evaluates one compatible depot or commits a deterministic depot choice.
-- Оценивает одно совместимое депо или фиксирует детерминированный выбор.
local function select_depot(job, provider)
  local state = job.route_state
  local depot_id =
    state.load_plan.depot_ids[state.depot_candidate_index]

  if depot_id then
    -- Проверяет одно совместимое депо и его свободные поезда за операцию.
    local available_train_ids = copy_without_used(
      provider.get_free_train_ids(depot_id),
      job.used_train_ids
    )
    if #available_train_ids > 0 then
      state.viable_depots[#state.viable_depots + 1] = {
        depot_id = depot_id,
        train_ids = available_train_ids,
      }
    end
    state.depot_candidate_index = state.depot_candidate_index + 1
    return
  end

  local index = deterministic_index(
    job.request_id,
    state.load_plan.train_class_id or 0,
    state.plan_index,
    #state.viable_depots,
    17
  )
  if not index then
    job.status = "failed"
    job.error = "no_compatible_depot_has_free_train"
    return
  end

  local selected = state.viable_depots[index]
  state.depot_id = selected.depot_id
  state.available_train_ids = selected.train_ids
  state.phase = "select_depot_station"
end

-- Selects a stable pseudo-random entrance station of the chosen depot.
-- Выбирает стабильную псевдослучайную входную станцию выбранного депо.
local function select_depot_station(job, provider)
  local state = job.route_state
  local depot_id = state.depot_id

  -- Получает станции выбранного депо только после построения загрузочной части.
  local depot_station_ids = {}
  for _, station_id in ipairs(provider.get_depot_station_ids(depot_id)) do
    depot_station_ids[#depot_station_ids + 1] = station_id
  end
  table.sort(depot_station_ids)

  local index = deterministic_index(
    job.request_id,
    depot_id,
    job.versions.depots[depot_id],
    #depot_station_ids,
    state.plan_index
  )

  if not index then
    job.status = "failed"
    job.error = "depot_has_no_station"
    return
  end

  state.depot_station_id = depot_station_ids[index]
  state.phase = "validate_depot_path"
end

-- Checks the path from the selected depot entrance to the first load stop.
-- Проверяет путь от выбранного входа депо до первой станции загрузки.
local function validate_depot_path(job, provider)
  local state = job.route_state
  local first_loading_station_id =
    state.reverse_station_ids[#state.reverse_station_ids]

  local distance = get_cached_distance(
    job,
    provider,
    state.depot_station_id,
    first_loading_station_id
  )
  if not distance then
    job.status = "failed"
    job.error = "no_path_from_depot"
    return
  end

  state.total_distance = state.total_distance + distance
  state.phase = "select_train"
end

-- Selects one stable pseudo-random free train without reusing job trains.
-- Выбирает один стабильный псевдослучайный поезд без повторов внутри задачи.
local function select_train(job, provider)
  local state = job.route_state
  local depot_id = state.depot_id

  local index = deterministic_index(
    job.request_id,
    depot_id,
    job.versions.depots[depot_id],
    #state.available_train_ids,
    state.plan_index * 31
  )

  if not index then
    job.status = "failed"
    job.error = "depot_has_no_free_train"
    return
  end

  state.train_id = state.available_train_ids[index]
  job.used_train_ids[state.train_id] = true
  state.phase = "finish_plan"
end

-- Emits one dispatcher-ready route and advances to the next load plan.
-- Формирует один готовый маршрут и переходит к следующему плану загрузки.
local function finish_plan(job)
  local state = job.route_state
  local stops = reverse_stops(
    state.load_plan,
    state.reverse_station_ids
  )

  job.routes[#job.routes + 1] = {
    train_id = state.train_id,
    depot_id = state.depot_id,
    depot_station_id = state.depot_station_id,
    request_station_id = job.request_station_id,
    stops = stops,
    resources = state.load_plan.resources,
    estimated_path_length = state.total_distance,
  }

  state.plan_index = state.plan_index + 1
  state.phase = "start_plan"
end

-- Performs one resumable reverse route-search operation.
-- Выполняет одну возобновляемую операцию обратного поиска маршрута.
function route_search.step(job, provider)
  local state = job.route_state

  if state.phase == "start_plan" then
    start_plan(job)
  elseif state.phase == "evaluate_station" then
    evaluate_one_station(job, provider)
  elseif state.phase == "select_depot" then
    select_depot(job, provider)
  elseif state.phase == "select_depot_station" then
    select_depot_station(job, provider)
  elseif state.phase == "validate_depot_path" then
    validate_depot_path(job, provider)
  elseif state.phase == "select_train" then
    select_train(job, provider)
  elseif state.phase == "finish_plan" then
    finish_plan(job)
  end
end

return route_search
