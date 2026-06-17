local candidate_filter = require("scripts.core.candidate_filter")
local dispatcher_core = require("scripts.core.dispatcher_core")
local helper = require("tests.test_helper")
local offer_builder = require("scripts.core.offer_builder")
local request_builder = require("scripts.core.request_builder")
local route_ranker = require("scripts.core.route_ranker")

local tests = {}

-- Verifies that unload stations emit isolated request DTOs with id and res[].
-- Проверяет, что станции разгрузки создают изолированные DTO запроса с id и res[].
function tests.request_builder_reads_unload_station()
  local request = request_builder.from_station({
    id = 10,
    mode = "unload",
    enabled = true,
    surface_id = 1,
    force_id = 1,
    priority = 5,
    request_items = {
      copper = 800,
      iron = 0,
      circuits = -1,
    },
  }, 123)

  helper.assert_true(request ~= nil, "request should exist")
  helper.assert_equal(request.station_id, 10, "station id")
  helper.assert_equal(request.items.copper, 800, "copper request")
  helper.assert_equal(request.items.iron, nil, "zero item ignored")
  helper.assert_equal(request.items.circuits, nil, "negative item ignored")
end

-- Verifies that load stations emit isolated offer DTOs with id and res[].
-- Проверяет, что станции погрузки создают изолированные DTO предложения с id и res[].
function tests.offer_builder_reads_load_station()
  local offer = offer_builder.from_station({
    id = 20,
    mode = "load",
    enabled = true,
    available_items = {
      copper = 500,
      iron = 300,
    },
  })

  helper.assert_true(offer ~= nil, "offer should exist")
  helper.assert_equal(offer.station_id, 20, "station id")
  helper.assert_equal(offer.items.copper, 500, "copper offer")
  helper.assert_equal(offer.items.iron, 300, "iron offer")
end

-- Verifies multi-resource requests include any source that has at least one requested resource.
-- Проверяет, что для мульти-ресурсного запроса в выборку попадает любой источник хотя бы с одним нужным ресурсом.
function tests.candidate_filter_keeps_partial_resource_matches()
  local request = {
    target_station_id = 10,
    surface_id = 1,
    force_id = 1,
    source_policy = "normal",
    items = {
      copper = 800,
      iron = 800,
    },
  }
  local offers = {
    {
      station_id = 20,
      surface_id = 1,
      force_id = 1,
      items = { copper = 800 },
    },
    {
      station_id = 30,
      surface_id = 1,
      force_id = 1,
      items = { circuits = 500 },
    },
    {
      station_id = 40,
      surface_id = 1,
      force_id = 1,
      items = { iron = 800 },
    },
    {
      station_id = 50,
      surface_id = 1,
      force_id = 1,
      train_limit = 1,
      assigned_train_count = 1,
      items = { copper = 800 },
    },
  }

  local candidates = candidate_filter.filter(request, offers)

  helper.assert_equal(#candidates, 2, "candidate count")
  helper.assert_equal(candidates[1].station_id, 20, "first source")
  helper.assert_equal(candidates[2].station_id, 40, "second source")
end

-- Verifies route ranking removes unreachable sources and applies route cost ordering.
-- Проверяет, что ранжирование маршрутов убирает недостижимые источники и сортирует по стоимости пути.
function tests.route_ranker_filters_and_sorts_by_path_cost()
  local request = {
    target_station_id = 10,
  }
  local trains = {
    { id = "train-a", capacity = 1000 },
  }
  local candidates = {
    { station_id = 20, id = 20, priority = 0, items = { copper = 100 } },
    { station_id = 30, id = 30, priority = 0, items = { copper = 100 } },
    { station_id = 40, id = 40, priority = 0, items = { copper = 100 } },
  }
  local route_costs = {
    ["train-a"] = {
      [20] = { [10] = 50 },
      [30] = { [10] = 10 },
    },
  }

  local ranked = route_ranker.rank(request, candidates, trains, route_costs)

  helper.assert_equal(#ranked, 2, "reachable candidate count")
  helper.assert_equal(ranked[1].station_id, 30, "cheapest source first")
  helper.assert_equal(ranked[2].station_id, 20, "expensive source second")
end

-- Verifies the full dispatcher pipeline chooses sources through request/offer/candidate/routing layers.
-- Проверяет, что полный pipeline диспетчера выбирает источники через слои request/offer/candidate/routing.
function tests.dispatcher_plans_from_raw_station_table()
  local stations = {
    [10] = {
      id = 10,
      mode = "unload",
      enabled = true,
      surface_id = 1,
      force_id = 1,
      priority = 10,
      request_items = {
        copper = 800,
        iron = 800,
      },
    },
    [20] = {
      id = 20,
      mode = "load",
      enabled = true,
      surface_id = 1,
      force_id = 1,
      available_items = {
        copper = 800,
      },
    },
    [30] = {
      id = 30,
      mode = "load",
      enabled = true,
      surface_id = 1,
      force_id = 1,
      available_items = {
        iron = 800,
      },
    },
  }
  local trains = {
    { id = "train-a", capacity = 1000 },
    { id = "train-b", capacity = 1000 },
  }
  local route_costs = {
    ["train-a"] = {
      [20] = { [10] = 10 },
      [30] = { [10] = 20 },
    },
    ["train-b"] = {
      [20] = { [10] = 10 },
      [30] = { [10] = 20 },
    },
  }

  local plan = dispatcher_core.plan_from_stations(stations, trains, route_costs)

  helper.assert_true(plan.ok, plan.reason)
  helper.assert_equal(plan.request.target_station_id, 10, "target station")
  helper.assert_equal(#plan.candidates, 2, "candidate count")
  helper.assert_equal(#plan.deliveries, 2, "delivery count")
end

return tests
