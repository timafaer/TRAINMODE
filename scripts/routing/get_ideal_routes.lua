local route_data_provider = require("scripts.routing.route_data_provider")

local get_ideal_routes = {}

-- Builds the initial serializable state using the selected data provider.
-- Собирает начальное сериализуемое состояние через выбранный провайдер данных.
local function create_job(provider, request_id)
  local request = provider.get_request(request_id)
  if not request then
    return nil
  end

  local request_station_id =
    provider.get_requester_station_id(request_id)
  local loading_station_ids =
    provider.get_suitable_loading_station_ids(request_id)
  local depot_ids =
    provider.get_suitable_depot_ids(request_id)
  local versions = {
    request = provider.get_data_version("request", request_id),
    stations = {},
    depots = {},
  }

  for _, station_id in ipairs(loading_station_ids) do
    versions.stations[station_id] =
      provider.get_data_version("station", station_id)
  end

  for _, depot_id in ipairs(depot_ids) do
    versions.depots[depot_id] =
      provider.get_data_version("depot", depot_id)
  end

  return {
    id = request_id,
    request_id = request_id,
    phase = "combinatorics",
    priority = request.priority or 0,
    created_tick = request.created_tick or 0,
    status = "running",

    request_station_id = request_station_id,
    loading_station_ids = loading_station_ids,
    depot_ids = depot_ids,
    versions = versions,

    combinator_state = {},
    load_plans = {},
    route_state = {},
    routes = {},
    distance_cache = {},
    used_train_ids = {},
  }
end

-- Creates a serializable planning job without calculating routes immediately.
-- Создает сериализуемую задачу планирования без немедленного расчета маршрутов.
function get_ideal_routes.get_ideal_routes(request_id)
  -- Проверяет, что запрос существует и еще может быть запланирован.
  return create_job(route_data_provider, request_id)
end

-- Creates a job with an explicit provider for isolated schedulers and tests.
-- Создает задачу с явным провайдером для изолированных планировщиков и тестов.
function get_ideal_routes.with_provider(provider, request_id)
  return create_job(provider, request_id)
end

-- Alias kept for callers using the shorter constructor name.
-- Алиас оставлен для вызывающего кода, использующего короткое имя конструктора.
get_ideal_routes.create = get_ideal_routes.get_ideal_routes

return get_ideal_routes
