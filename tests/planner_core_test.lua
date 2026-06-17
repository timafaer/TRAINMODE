local helper = require("tests.test_helper")
local planner = require("scripts.core.planner_core")

local tests = {}

-- Verifies the example case: keep copper together and use spare space for circuits.
-- Проверяет пример: медь едет цельной группой, а свободное место добивается платами.
function tests.multi_resource_prefers_compact_whole_groups()
  local result = planner.plan(
    {
      items = {
        copper = 800,
        iron = 800,
        circuits = 200,
      },
    },
    {
      { id = "train-a", capacity = 1000 },
      { id = "train-b", capacity = 1000 },
    },
    {
      { id = "station-a", items = { copper = 800, circuits = 200 } },
      { id = "station-b", items = { iron = 800 } },
    }
  )

  helper.assert_true(result.ok, result.reason)
  helper.assert_equal(#result.deliveries, 2, "delivery count")
  helper.assert_table_contains_items(result.deliveries[1].items, { copper = 800, circuits = 200 }, "first delivery")
  helper.assert_table_contains_items(result.deliveries[2].items, { iron = 800 }, "second delivery")
  helper.assert_equal(result.cost.extra_resource_types, 1, "mixing penalty")
end

-- Verifies that one station providing multiple resources is preferred over split loading.
-- Проверяет, что одна станция с несколькими ресурсами предпочтительнее раздельной погрузки.
function tests.single_station_can_supply_multiple_resources()
  local result = planner.plan(
    {
      items = {
        copper = 300,
        iron = 300,
      },
    },
    {
      { id = "train-a", capacity = 1000 },
    },
    {
      { id = "station-a", items = { copper = 300, iron = 300 } },
      { id = "station-b", items = { copper = 300 } },
    }
  )

  helper.assert_true(result.ok, result.reason)
  helper.assert_equal(#result.deliveries, 1, "delivery count")
  helper.assert_equal(#result.deliveries[1].stops, 1, "stop count")
  helper.assert_equal(result.deliveries[1].stops[1].station_id, "station-a", "source station")
end

-- Verifies that one delivery may visit multiple loading stations when needed.
-- Проверяет, что одна доставка может посетить несколько станций погрузки, если это нужно.
function tests.delivery_can_use_multiple_loading_stations()
  local result = planner.plan(
    {
      items = {
        copper = 300,
        iron = 300,
      },
    },
    {
      { id = "train-a", capacity = 1000 },
    },
    {
      { id = "station-a", items = { copper = 300 } },
      { id = "station-b", items = { iron = 300 } },
    }
  )

  helper.assert_true(result.ok, result.reason)
  helper.assert_equal(#result.deliveries, 1, "delivery count")
  helper.assert_equal(#result.deliveries[1].stops, 2, "stop count")
end

-- Verifies that the cost model can prefer less mixed trains over fewer trains.
-- Проверяет, что модель стоимости может предпочесть меньшее смешивание меньшему числу поездов.
function tests.prefers_less_mixing_over_fewer_trains_when_weights_say_so()
  local result = planner.plan(
    {
      items = {
        copper = 900,
        iron = 900,
      },
    },
    {
      { id = "train-a", capacity = 2000 },
      { id = "train-b", capacity = 1000 },
      { id = "train-c", capacity = 1000 },
    },
    {
      { id = "station-a", items = { copper = 900, iron = 900 } },
    },
    {
      weights = {
        mixing = 1000,
        train = 500,
        station = 100,
        empty_space = 1,
      },
    }
  )

  helper.assert_true(result.ok, result.reason)
  helper.assert_equal(#result.deliveries, 2, "delivery count")
  helper.assert_equal(result.cost.extra_resource_types, 0, "mixing penalty")
end

-- Verifies planning fails when available source signals cannot cover the request.
-- Проверяет отказ планирования, если сигналы источников не покрывают запрос.
function tests.fails_when_sources_cannot_cover_request()
  local result = planner.plan(
    {
      items = {
        copper = 1000,
      },
    },
    {
      { id = "train-a", capacity = 1000 },
    },
    {
      { id = "station-a", items = { copper = 500 } },
    }
  )

  helper.assert_false(result.ok, "plan should fail")
  helper.assert_equal(result.reason, "not-enough-source-items", "failure reason")
end

-- Verifies planning fails when the available train fleet cannot carry the request.
-- Проверяет отказ планирования, если доступные поезда не могут увезти запрос.
function tests.fails_when_train_capacity_is_not_enough()
  local result = planner.plan(
    {
      items = {
        copper = 1500,
      },
    },
    {
      { id = "train-a", capacity = 1000 },
    },
    {
      { id = "station-a", items = { copper = 1500 } },
    }
  )

  helper.assert_false(result.ok, "plan should fail")
  helper.assert_equal(result.reason, "not-enough-train-capacity", "failure reason")
end

return tests
