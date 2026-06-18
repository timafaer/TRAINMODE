local helper = require("tests.test_helper")
local get_ideal_routes = require("scripts.routing.get_ideal_routes")
local route_optimizer = require("scripts.routing.route_optimizer")
local scheduler_module = require("scripts.routing.scheduler")

local tests = {}

local function contains(list, expected)
  for _, value in ipairs(list) do
    if value == expected then
      return true
    end
  end
  return false
end

local function count_unique_route_stations(routes)
  local stations = {}
  local count = 0

  for _, route in ipairs(routes) do
    for _, stop in ipairs(route.stops) do
      if not stations[stop.station_id] then
        stations[stop.station_id] = true
        count = count + 1
      end
    end
  end

  return count
end

local function make_provider(options)
  options = options or {}
  local versions = options.versions or {
    request = 1,
    station = 1,
    depot = 1,
  }

  local provider = {
    distance_calls = 0,
    distance_call_keys = {},
    resource_calls = 0,
  }

  function provider.get_request(id)
    return {
      id = id,
      priority = options.priority or 0,
      created_tick = options.created_tick or id,
    }
  end

  function provider.get_requester_station_id()
    return 900
  end

  function provider.get_requested_resources()
    return options.requested_resources or {
      iron = 8,
      copper = 2,
    }
  end

  function provider.get_suitable_loading_station_ids()
    return options.loading_station_ids or { 201, 202 }
  end

  function provider.get_suitable_depot_ids()
    return options.depot_ids or { 301 }
  end

  function provider.get_depot_train_class()
    return {
      id = 1,
      capacity_stacks = options.capacity_stacks or 10,
    }
  end

  function provider.get_depot_station_ids()
    return options.depot_station_ids or { 401, 402 }
  end

  function provider.get_free_train_ids(depot_id)
    if options.free_trains_by_depot then
      return options.free_trains_by_depot[depot_id] or {}
    end
    return options.free_train_ids or { 501, 502, 503 }
  end

  function provider.get_station_resources(station_id)
    provider.resource_calls = provider.resource_calls + 1
    local resources = options.station_resources or {
      [201] = { iron = 8, copper = 2 },
      [202] = { iron = 8, copper = 2 },
    }
    return resources[station_id] or {}
  end

  function provider.get_station_available_train_slots(station_id)
    if options.station_available_slots then
      return options.station_available_slots[station_id] or 0
    end
    return 100
  end

  function provider.get_distance_between_stations(from_id, to_id)
    provider.distance_calls = provider.distance_calls + 1
    local key = tostring(from_id) .. ":" .. tostring(to_id)
    provider.distance_call_keys[key] =
      (provider.distance_call_keys[key] or 0) + 1
    local distances = options.distances or {
      ["900:201"] = 30,
      ["900:202"] = 10,
      ["202:201"] = 5,
      ["201:202"] = 5,
      ["401:201"] = 12,
      ["402:201"] = 14,
      ["401:202"] = 16,
      ["402:202"] = 18,
    }
    return distances[key]
  end

  function provider.get_data_version(entity_type, entity_id)
    local entity_versions = versions[entity_type]
    if type(entity_versions) == "table" then
      return entity_versions[entity_id] or entity_versions.default
    end
    return entity_versions
  end

  return provider
end

local function create_job(provider, request_id)
  local loading_station_ids =
    provider.get_suitable_loading_station_ids(request_id)
  local depot_ids = provider.get_suitable_depot_ids(request_id)
  local station_versions = {}
  local depot_versions = {}

  for _, station_id in ipairs(loading_station_ids) do
    station_versions[station_id] =
      provider.get_data_version("station", station_id)
  end
  for _, depot_id in ipairs(depot_ids) do
    depot_versions[depot_id] =
      provider.get_data_version("depot", depot_id)
  end

  return {
    id = request_id,
    request_id = request_id,
    phase = "combinatorics",
    priority = provider.get_request(request_id).priority,
    created_tick = provider.get_request(request_id).created_tick,
    status = "running",
    request_station_id = provider.get_requester_station_id(request_id),
    loading_station_ids = loading_station_ids,
    depot_ids = depot_ids,
    versions = {
      request = provider.get_data_version("request", request_id),
      stations = station_versions,
      depots = depot_versions,
    },
    combinator_state = {},
    load_plans = {},
    route_state = {},
    routes = {},
    distance_cache = {},
    used_train_ids = {},
  }
end

local function advance_to_phase(job, provider, expected_phase, max_steps)
  for _ = 1, max_steps or 300 do
    if job.phase == expected_phase or job.status ~= "running" then
      return job
    end
    route_optimizer.step(job, provider)
  end
  error("job did not reach phase " .. expected_phase)
end

local function run_job(provider, request_id, max_steps)
  local job = create_job(provider, request_id)
  for _ = 1, max_steps or 200 do
    if job.status ~= "running" then
      return job
    end
    route_optimizer.step(job, provider)
  end
  error("job did not finish")
end

local function run_scheduler(scheduler, job_id, max_steps)
  for _ = 1, max_steps or 500 do
    if scheduler:get_result(job_id) then
      return scheduler:get_result(job_id)
    end
    scheduler:step(1)
  end
  error("scheduler did not finish job")
end

-- Checks that combinatorics never requests path distances.
-- Проверяет, что комбинаторика никогда не запрашивает расстояния.
function tests.combinatorics_does_not_read_distances()
  local provider = make_provider()
  local job = create_job(provider, 1)

  while job.phase == "combinatorics" do
    route_optimizer.step(job, provider)
  end

  helper.assert_equal(provider.distance_calls, 0, "distance calls")
  helper.assert_equal(#job.load_plans, 1, "load plan count")
  helper.assert_equal(job.load_plans[1].resources.iron, 8, "planned iron")
  helper.assert_equal(job.load_plans[1].resources.copper, 2, "planned copper")
end

-- Checks backward nearest-neighbour construction and final route reversal.
-- Проверяет обратное построение по ближайшим станциям и разворот маршрута.
function tests.builds_and_reverses_route()
  local provider = make_provider({
    station_resources = {
      [201] = { iron = 8 },
      [202] = { copper = 2 },
    },
  })
  local job = run_job(provider, 2)

  helper.assert_equal(job.status, "completed", "job status")
  helper.assert_equal(#job.routes, 1, "route count")
  helper.assert_equal(job.routes[1].stops[1].station_id, 201, "first stop")
  helper.assert_equal(job.routes[1].stops[2].station_id, 202, "last load stop")
  helper.assert_equal(job.routes[1].request_station_id, 900, "request stop")
end

-- Checks that route-search work receives scheduler budget first.
-- Проверяет, что поиск маршрута первым получает бюджет планировщика.
function tests.route_search_has_scheduler_priority()
  local provider = make_provider()
  local combinator_job = create_job(provider, 10)
  local route_job = create_job(provider, 11)
  route_job.phase = "route_search"
  route_job.route_state = {
    plan_index = 1,
    phase = "start_plan",
  }
  route_job.load_plans = {
    {
      depot_ids = { 301 },
      train_class_id = 1,
      resources = { iron = 1 },
      stops = {
        { station_id = 201, resources = { iron = 1 } },
      },
    },
  }

  local scheduler = scheduler_module.new(provider)
  scheduler:add(combinator_job)
  scheduler:add(route_job)
  helper.assert_equal(scheduler:step(1), 1, "performed operations")

  helper.assert_equal(route_job.route_state.phase, "evaluate_station", "route phase")
  helper.assert_equal(combinator_job.combinator_state.phase, nil, "combinator phase")
end

-- Checks that a one-operation budget preserves resumable state.
-- Проверяет, что бюджет в одну операцию сохраняет возобновляемое состояние.
function tests.continues_from_saved_state()
  local provider = make_provider()
  local job = create_job(provider, 20)
  local scheduler = scheduler_module.new(provider)
  scheduler:add(job)

  scheduler:step(1)
  helper.assert_equal(job.combinator_state.phase, "collect_stations", "first phase")
  helper.assert_equal(job.combinator_state.station_index, 1, "first station index")

  scheduler:step(1)
  helper.assert_equal(job.combinator_state.station_index, 2, "continued station index")
  helper.assert_equal(provider.resource_calls, 1, "one resource read")
end

-- Checks that stale source data requests a fresh job.
-- Проверяет, что устаревшие исходные данные запускают новую задачу.
function tests.restarts_when_version_changes()
  local versions = {
    request = 1,
    station = 1,
    depot = 1,
  }
  local provider = make_provider({ versions = versions })
  local created = 0
  local function factory(request_id)
    created = created + 1
    return create_job(provider, request_id)
  end

  local job = create_job(provider, 30)
  job.phase = "validation"
  job.validation_state = nil
  versions.request = 2

  local scheduler = scheduler_module.new(provider, factory)
  scheduler:add(job)
  scheduler:step(1)
  scheduler:step(1)

  helper.assert_equal(created, 1, "replacement count")
  helper.assert_equal(
    scheduler:get_job(30).versions.request,
    2,
    "replacement version"
  )
end

-- Checks that jobs keep independent mutable planning state.
-- Проверяет, что задачи хранят независимое изменяемое состояние.
function tests.jobs_do_not_share_state()
  local provider = make_provider()
  local first = create_job(provider, 40)
  local second = create_job(provider, 41)

  route_optimizer.step(first, provider)
  first.combinator_state.requested_resources.iron = 0

  helper.assert_equal(second.combinator_state.phase, nil, "second phase")
  helper.assert_equal(
    second.combinator_state.requested_resources,
    nil,
    "second resources"
  )
end

-- Checks repeatable pseudo-random depot station and train selection.
-- Проверяет повторяемый псевдослучайный выбор станции депо и поезда.
function tests.selection_is_deterministic()
  local first = run_job(make_provider(), 50)
  local second = run_job(make_provider(), 50)

  helper.assert_equal(
    first.routes[1].depot_station_id,
    second.routes[1].depot_station_id,
    "depot station"
  )
  helper.assert_equal(
    first.routes[1].train_id,
    second.routes[1].train_id,
    "train id"
  )
  helper.assert_equal(
    contains({ 501, 502, 503 }, first.routes[1].train_id),
    true,
    "known train"
  )
end

-- Checks the preferred packing: pure full loads before mixing remainders.
-- Проверяет предпочтительную упаковку: полные чистые грузы до смешивания остатков.
function tests.minimizes_mixed_resource_trains()
  local provider = make_provider({
    requested_resources = {
      copper = 8,
      iron = 8,
      plastic = 2,
    },
    station_resources = {
      [201] = {
        copper = 8,
        iron = 8,
        plastic = 2,
      },
      [202] = {},
    },
    free_train_ids = { 501, 502 },
  })
  local job = create_job(provider, 60)

  while job.phase == "combinatorics" do
    route_optimizer.step(job, provider)
  end

  helper.assert_equal(#job.load_plans, 2, "train count")
  helper.assert_equal(job.load_plans[1].resources.copper, 8, "first copper")
  helper.assert_equal(job.load_plans[1].resources.plastic, 2, "first plastic")
  helper.assert_equal(job.load_plans[1].resources.iron, nil, "first iron")
  helper.assert_equal(job.load_plans[2].resources.iron, 8, "second iron")
end

-- Checks that several compatible depots can supply separate routes.
-- Проверяет, что несколько совместимых депо выдают поезда разным маршрутам.
function tests.distributes_routes_between_compatible_depots()
  local provider = make_provider({
    requested_resources = { iron = 20 },
    station_resources = {
      [201] = { iron = 20 },
      [202] = {},
    },
    depot_ids = { 301, 302 },
    depot_station_ids = { 401 },
    free_trains_by_depot = {
      [301] = { 501 },
      [302] = { 502 },
    },
  })

  local original_get_depot_train_class = provider.get_depot_train_class
  provider.get_depot_train_class = function(depot_id)
    local train_class = original_get_depot_train_class(depot_id)
    train_class.id = 1
    return train_class
  end
  local original_get_version = provider.get_data_version
  provider.get_data_version = function(entity_type, id)
    return original_get_version(entity_type, id)
  end

  local job = run_job(provider, 70)

  helper.assert_equal(#job.routes, 2, "route count")
  helper.assert_equal(job.routes[1].depot_id ~= job.routes[2].depot_id, true, "depots")
  helper.assert_equal(job.routes[1].train_id ~= job.routes[2].train_id, true, "trains")
end

-- Checks that increased station stock does not invalidate an existing route.
-- Проверяет, что рост запаса станции не инвалидирует готовый маршрут.
function tests.stock_increase_does_not_restart_route()
  local station_resources = {
    [201] = { iron = 8, copper = 2 },
    [202] = {},
  }
  local provider = make_provider({ station_resources = station_resources })
  local job = create_job(provider, 80)
  advance_to_phase(job, provider, "validation")
  station_resources[201].iron = 100

  local restarts = 0
  local scheduler = scheduler_module.new(provider, function(request_id)
    restarts = restarts + 1
    return create_job(provider, request_id)
  end)
  scheduler:add(job)
  local result = run_scheduler(scheduler, 80)

  helper.assert_equal(restarts, 0, "restart count")
  helper.assert_equal(result[1].train_id, job.routes[1].train_id, "same route")
end

-- Checks that a decrease remains non-critical while planned stacks still exist.
-- Проверяет, что уменьшение некритично, пока запланированные стаки доступны.
function tests.safe_stock_decrease_does_not_restart_route()
  local station_resources = {
    [201] = { iron = 20, copper = 10 },
    [202] = {},
  }
  local provider = make_provider({ station_resources = station_resources })
  local job = create_job(provider, 81)
  advance_to_phase(job, provider, "validation")
  station_resources[201].iron = 8
  station_resources[201].copper = 2

  local restarts = 0
  local scheduler = scheduler_module.new(provider, function(request_id)
    restarts = restarts + 1
    return create_job(provider, request_id)
  end)
  scheduler:add(job)
  run_scheduler(scheduler, 81)

  helper.assert_equal(restarts, 0, "restart count")
end

-- Checks that unrelated resource changes at a used station are non-critical.
-- Проверяет, что изменение постороннего ресурса используемой станции некритично.
function tests.unrequested_stock_change_does_not_restart_route()
  local station_resources = {
    [201] = { iron = 8, copper = 2, coal = 100 },
    [202] = {},
  }
  local provider = make_provider({ station_resources = station_resources })
  local job = create_job(provider, 811)
  advance_to_phase(job, provider, "validation")
  station_resources[201].coal = 0

  local restarts = 0
  local scheduler = scheduler_module.new(provider, function(request_id)
    restarts = restarts + 1
    return create_job(provider, request_id)
  end)
  scheduler:add(job)
  run_scheduler(scheduler, 811)

  helper.assert_equal(restarts, 0, "restart count")
end

-- Checks that stock below the planned amount requires recalculation.
-- Проверяет, что запас ниже плана требует перерасчета.
function tests.insufficient_stock_restarts_route()
  local station_resources = {
    [201] = { iron = 8, copper = 2 },
    [202] = {},
  }
  local provider = make_provider({ station_resources = station_resources })
  local job = create_job(provider, 82)
  advance_to_phase(job, provider, "validation")
  station_resources[201].iron = 7

  local restarts = 0
  local scheduler = scheduler_module.new(provider, function(request_id)
    restarts = restarts + 1
    return create_job(provider, request_id)
  end)
  scheduler:add(job)
  run_scheduler(scheduler, 82)

  helper.assert_equal(restarts, 1, "restart count")
end

-- Checks that changes at unused candidate stations do not invalidate a route.
-- Проверяет, что изменения неиспользованной станции не инвалидируют маршрут.
function tests.unused_station_change_does_not_restart_route()
  local versions = {
    request = 1,
    station = {
      [201] = 1,
      [202] = 1,
    },
    depot = 1,
  }
  local provider = make_provider({
    versions = versions,
    station_resources = {
      [201] = { iron = 8, copper = 2 },
      [202] = {},
    },
  })
  local job = create_job(provider, 83)
  advance_to_phase(job, provider, "validation")
  versions.station[202] = 2

  local scheduler = scheduler_module.new(provider)
  scheduler:add(job)
  run_scheduler(scheduler, 83)

  helper.assert_equal(job.status, "completed", "job status")
end

-- Checks that a critical structural change of a used station restarts planning.
-- Проверяет перезапуск при критичном изменении используемой станции.
function tests.used_station_critical_change_restarts_route()
  local versions = {
    request = 1,
    station = {
      [201] = 1,
      [202] = 1,
    },
    depot = 1,
  }
  local provider = make_provider({
    versions = versions,
    station_resources = {
      [201] = { iron = 8, copper = 2 },
      [202] = {},
    },
  })
  local job = create_job(provider, 84)
  advance_to_phase(job, provider, "validation")
  versions.station[201] = 2

  route_optimizer.step(job, provider)
  route_optimizer.step(job, provider)

  helper.assert_equal(job.status, "restart_required", "job status")
end

-- Checks that a critical change of the selected depot restarts planning.
-- Проверяет перезапуск при критичном изменении выбранного депо.
function tests.selected_depot_critical_change_restarts_route()
  local versions = {
    request = 1,
    station = 1,
    depot = { [301] = 1 },
  }
  local provider = make_provider({ versions = versions })
  local job = create_job(provider, 85)
  advance_to_phase(job, provider, "validation")
  versions.depot[301] = 2

  for _ = 1, 20 do
    if job.status ~= "running" then
      break
    end
    route_optimizer.step(job, provider)
  end

  helper.assert_equal(job.status, "restart_required", "job status")
end

-- Checks that losing the selected free train invalidates the result.
-- Проверяет, что исчезновение выбранного свободного поезда инвалидирует результат.
function tests.selected_train_becoming_busy_restarts_route()
  local free_train_ids = { 501, 502, 503 }
  local provider = make_provider({ free_train_ids = free_train_ids })
  local job = create_job(provider, 86)
  advance_to_phase(job, provider, "validation")
  local selected_train_id = job.routes[1].train_id

  for index, train_id in ipairs(free_train_ids) do
    if train_id == selected_train_id then
      table.remove(free_train_ids, index)
      break
    end
  end

  for _ = 1, 30 do
    if job.status ~= "running" then
      break
    end
    route_optimizer.step(job, provider)
  end

  helper.assert_equal(job.status, "restart_required", "job status")
end

-- Checks that unavailable request volume produces the best partial load plan.
-- Проверяет, что нехватка ресурсов дает лучший частичный план.
function tests.returns_partial_plan_for_available_stock()
  local provider = make_provider({
    requested_resources = { iron = 15 },
    station_resources = {
      [201] = { iron = 7 },
      [202] = {},
    },
  })
  local job = run_job(provider, 87)

  helper.assert_equal(#job.routes, 1, "route count")
  helper.assert_equal(job.routes[1].resources.iron, 7, "planned iron")
end

-- Checks that route search fails cleanly when every compatible depot is empty.
-- Проверяет корректный отказ, когда во всех совместимых депо нет поездов.
function tests.fails_when_compatible_depots_have_no_free_train()
  local provider = make_provider({ free_train_ids = {} })
  local job = run_job(provider, 88)

  helper.assert_equal(job.status, "failed", "job status")
  helper.assert_equal(
    job.error,
    "no_compatible_depot_has_free_train",
    "job error"
  )
end

-- Checks that repeated route edges use the per-job distance cache.
-- Проверяет использование кеша расстояний для повторяющихся ребер.
function tests.reuses_distance_cache_between_routes()
  local provider = make_provider({
    requested_resources = { iron = 20 },
    station_resources = {
      [201] = { iron = 20 },
      [202] = {},
    },
    free_train_ids = { 501, 502 },
    depot_station_ids = { 401 },
  })
  local job = run_job(provider, 89)

  helper.assert_equal(#job.routes, 2, "route count")
  helper.assert_equal(provider.distance_call_keys["900:201"], 1, "target edge")
  helper.assert_equal(provider.distance_call_keys["401:201"], 1, "depot edge")
end

-- Checks that scheduler never exceeds the requested operation count.
-- Проверяет, что scheduler не превышает заданное число операций.
function tests.scheduler_respects_exact_operation_budget()
  local provider = make_provider()
  local scheduler = scheduler_module.new(provider)
  local first = create_job(provider, 90)
  local second = create_job(provider, 91)
  scheduler:add(first)
  scheduler:add(second)

  helper.assert_equal(scheduler:step(5), 5, "performed operations")
  helper.assert_equal(provider.resource_calls, 2, "bounded resource reads")
end

-- Checks that one free station slot can be assigned to only one train route.
-- Проверяет, что одно свободное место станции получает только один маршрут.
function tests.station_limit_caps_number_of_routes()
  local provider = make_provider({
    requested_resources = { iron = 20 },
    station_resources = {
      [201] = { iron = 20 },
      [202] = {},
    },
    station_available_slots = {
      [201] = 1,
      [202] = 0,
    },
    free_train_ids = { 501, 502 },
  })
  local job = run_job(provider, 92)

  helper.assert_equal(#job.routes, 1, "route count")
  helper.assert_equal(job.routes[1].resources.iron, 10, "planned iron")
end

-- Checks that several resources on one route consume one station slot.
-- Проверяет, что несколько ресурсов одного маршрута занимают одно место станции.
function tests.multiple_resources_share_one_station_slot()
  local provider = make_provider({
    station_resources = {
      [201] = { iron = 8, copper = 2 },
      [202] = {},
    },
    station_available_slots = {
      [201] = 1,
      [202] = 0,
    },
  })
  local job = run_job(provider, 93)

  helper.assert_equal(#job.routes, 1, "route count")
  helper.assert_equal(job.routes[1].resources.iron, 8, "planned iron")
  helper.assert_equal(job.routes[1].resources.copper, 2, "planned copper")
  helper.assert_equal(#job.routes[1].stops, 1, "stop count")
end

-- Checks that a station with no free train-limit slots is not used.
-- Проверяет, что станция без свободного лимита поездов не используется.
function tests.station_with_zero_limit_is_skipped()
  local provider = make_provider({
    station_resources = {
      [201] = { iron = 8, copper = 2 },
      [202] = { iron = 5 },
    },
    station_available_slots = {
      [201] = 0,
      [202] = 1,
    },
  })
  local job = run_job(provider, 94)

  helper.assert_equal(#job.routes, 1, "route count")
  helper.assert_equal(job.routes[1].resources.iron, 5, "planned iron")
  helper.assert_equal(job.routes[1].resources.copper, nil, "planned copper")
  helper.assert_equal(job.routes[1].stops[1].station_id, 202, "station id")
end

-- Checks that a newly occupied station slot invalidates an unreserved result.
-- Проверяет, что занятый до резервации слот инвалидирует готовый результат.
function tests.station_limit_decrease_restarts_route()
  local station_available_slots = {
    [201] = 1,
    [202] = 0,
  }
  local provider = make_provider({
    station_resources = {
      [201] = { iron = 8, copper = 2 },
      [202] = {},
    },
    station_available_slots = station_available_slots,
  })
  local job = create_job(provider, 95)
  advance_to_phase(job, provider, "validation")
  station_available_slots[201] = 0

  for _ = 1, 20 do
    if job.status ~= "running" then
      break
    end
    route_optimizer.step(job, provider)
  end

  helper.assert_equal(job.status, "restart_required", "job status")
end

-- Checks that two trains may consume separate shares of one station stock.
-- Проверяет, что два поезда могут забрать разные доли запаса одной станции.
function tests.two_trains_share_one_station_stock()
  local provider = make_provider({
    requested_resources = { iron = 20 },
    station_resources = {
      [201] = { iron = 20 },
      [202] = {},
    },
    station_available_slots = {
      [201] = 2,
      [202] = 0,
    },
    free_train_ids = { 501, 502 },
  })
  local job = run_job(provider, 96)

  helper.assert_equal(#job.routes, 2, "route count")
  helper.assert_equal(job.routes[1].resources.iron, 10, "first train iron")
  helper.assert_equal(job.routes[2].resources.iron, 10, "second train iron")
  helper.assert_equal(job.routes[1].stops[1].station_id, 201, "first station")
  helper.assert_equal(job.routes[2].stops[1].station_id, 201, "second station")
end

-- Checks that the second train sees the stock left by the first train.
-- Проверяет, что второй поезд видит остаток после первого поезда.
function tests.second_train_uses_only_remaining_station_stock()
  local provider = make_provider({
    requested_resources = { iron = 20 },
    station_resources = {
      [201] = { iron = 15 },
      [202] = {},
    },
    station_available_slots = {
      [201] = 2,
      [202] = 0,
    },
    free_train_ids = { 501, 502 },
  })
  local job = run_job(provider, 97)

  helper.assert_equal(#job.routes, 2, "route count")
  helper.assert_equal(job.routes[1].resources.iron, 10, "first train iron")
  helper.assert_equal(job.routes[2].resources.iron, 5, "second train iron")
  helper.assert_equal(
    job.routes[1].resources.iron + job.routes[2].resources.iron,
    15,
    "total station consumption"
  )
end

-- Checks that a later train switches station after the first stock is consumed.
-- Проверяет переход следующего поезда на другую станцию после исчерпания первой.
function tests.next_train_switches_to_station_with_remaining_stock()
  local provider = make_provider({
    requested_resources = { iron = 20 },
    station_resources = {
      [201] = { iron = 10 },
      [202] = { iron = 10 },
    },
    station_available_slots = {
      [201] = 2,
      [202] = 2,
    },
    free_train_ids = { 501, 502 },
  })
  local job = run_job(provider, 98)

  helper.assert_equal(#job.routes, 2, "route count")
  helper.assert_equal(job.routes[1].stops[1].station_id, 201, "first station")
  helper.assert_equal(job.routes[2].stops[1].station_id, 202, "second station")
end

-- Checks shared per-resource stock accounting across mixed train loads.
-- Проверяет общий учет каждого ресурса между смешанными грузами поездов.
function tests.mixed_trains_do_not_overbook_station_resources()
  local provider = make_provider({
    requested_resources = {
      copper = 8,
      iron = 12,
    },
    station_resources = {
      [201] = {
        copper = 8,
        iron = 12,
      },
      [202] = {},
    },
    station_available_slots = {
      [201] = 2,
      [202] = 0,
    },
    free_train_ids = { 501, 502 },
  })
  local job = run_job(provider, 99)
  local totals = {}

  for _, route in ipairs(job.routes) do
    for resource, stacks in pairs(route.resources) do
      totals[resource] = (totals[resource] or 0) + stacks
    end
  end

  helper.assert_equal(#job.routes, 2, "route count")
  helper.assert_equal(totals.iron, 12, "total iron")
  helper.assert_equal(totals.copper, 8, "total copper")
end

-- Checks that a multi-resource station is preferred for the whole request.
-- Проверяет предпочтение мультиресурсной станции для всего запроса.
function tests.minimizes_unique_stations_across_all_routes()
  local provider = make_provider({
    requested_resources = {
      iron = 12,
      copper = 8,
    },
    station_resources = {
      [201] = {
        iron = 12,
      },
      [202] = {
        iron = 12,
        copper = 8,
      },
    },
    station_available_slots = {
      [201] = 2,
      [202] = 2,
    },
    free_train_ids = { 501, 502 },
  })
  local job = run_job(provider, 100)

  helper.assert_equal(#job.routes, 2, "route count")
  helper.assert_equal(
    count_unique_route_stations(job.routes),
    1,
    "unique station count"
  )
  helper.assert_equal(job.routes[1].stops[1].station_id, 202, "first station")
  helper.assert_equal(job.routes[2].stops[1].station_id, 202, "second station")
end

-- Checks that station limits may force the otherwise avoided extra station.
-- Проверяет, что лимит станции может вынудить использовать дополнительную станцию.
function tests.station_limit_can_force_additional_unique_station()
  local provider = make_provider({
    requested_resources = {
      iron = 12,
      copper = 8,
    },
    station_resources = {
      [201] = {
        iron = 12,
      },
      [202] = {
        iron = 12,
        copper = 8,
      },
    },
    station_available_slots = {
      [201] = 1,
      [202] = 1,
    },
    free_train_ids = { 501, 502 },
  })
  local job = run_job(provider, 101)

  helper.assert_equal(#job.routes, 2, "route count")
  helper.assert_equal(
    count_unique_route_stations(job.routes),
    2,
    "unique station count"
  )
end

-- Checks that lack of trains returns already planned routes as a partial plan.
-- Проверяет частичный результат при нехватке свободных поездов.
function tests.limited_train_count_returns_partial_routes()
  local provider = make_provider({
    requested_resources = { iron = 20 },
    station_resources = {
      [201] = { iron = 20 },
      [202] = {},
    },
    station_available_slots = {
      [201] = 2,
      [202] = 0,
    },
    free_train_ids = { 501 },
  })
  local job = run_job(provider, 102)

  helper.assert_equal(job.status, "completed", "job status")
  helper.assert_equal(#job.routes, 1, "route count")
  helper.assert_equal(job.routes[1].resources.iron, 10, "planned iron")
end

return tests
