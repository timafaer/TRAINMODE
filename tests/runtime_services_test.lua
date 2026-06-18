local helper = require("tests.test_helper")
local storage_init = require("scripts.storage.init")
local requests = require("scripts.dispatcher.requests")
local reservations = require("scripts.dispatcher.reservations")
local scheduler_module = require("scripts.routing.scheduler")

local tests = {}

local function new_state()
  return storage_init.ensure({})
end

-- Checks that runtime storage can be initialized repeatedly without data loss.
-- Проверяет повторную инициализацию storage без потери данных.
function tests.storage_initialization_is_idempotent()
  local root = {}
  local first = storage_init.ensure(root)
  first.next_request_id = 42
  local second = storage_init.ensure(root)

  helper.assert_equal(first, second, "same state")
  helper.assert_equal(second.next_request_id, 42, "preserved counter")
end

-- Checks request deduplication per requester station.
-- Проверяет отсутствие дублирующих запросов одной станции.
function tests.request_is_not_duplicated()
  local state = new_state()
  local station = {
    id = 1,
    surface_index = 1,
    force_index = 1,
    priority = 5,
  }
  local first = requests.ensure_for_station(state, station, { iron = 10 }, 100)
  local second = requests.ensure_for_station(state, station, { iron = 20 }, 101)

  helper.assert_equal(first.id, second.id, "request id")
  helper.assert_equal(state.next_request_id, 2, "request counter")
end

-- Checks resource, slot, and train reservations for several routes.
-- Проверяет резервации ресурсов, мест и поездов нескольких маршрутов.
function tests.routes_are_reserved_and_released()
  local state = new_state()
  local routes = {
    {
      train_id = 10,
      request_station_id = 2,
      stops = {
        { station_id = 1, resources = { iron = 10 } },
      },
    },
    {
      train_id = 11,
      request_station_id = 2,
      stops = {
        { station_id = 1, resources = { iron = 5, copper = 2 } },
      },
    },
  }

  local delivery_ids = reservations.reserve_routes(state, 7, routes)
  helper.assert_equal(#delivery_ids, 2, "delivery count")
  helper.assert_equal(
    state.reservations.station_resources[1].iron,
    15,
    "reserved iron"
  )
  helper.assert_equal(state.reservations.station_slots[1], 2, "reserved slots")
  helper.assert_equal(state.reservations.station_slots[2], 2, "target slots")

  reservations.release_delivery(state, state.deliveries[delivery_ids[1]])
  helper.assert_equal(
    state.reservations.station_resources[1].iron,
    5,
    "remaining iron"
  )
  helper.assert_equal(state.reservations.station_slots[1], 1, "remaining slots")
  helper.assert_equal(state.reservations.station_slots[2], 1, "target slots left")
end

-- Checks that persisted scheduler tables survive wrapper recreation.
-- Проверяет сохранение таблиц scheduler между созданием оберток.
function tests.scheduler_uses_persisted_state()
  local persisted = { jobs = {}, results = {} }
  local provider = {}
  local first = scheduler_module.new(provider, function() return nil end, persisted)
  first:add({
    id = 1,
    request_id = 1,
    phase = "completed",
    status = "completed",
  })

  local second = scheduler_module.new(provider, function() return nil end, persisted)
  helper.assert_equal(second:get_job(1).id, 1, "persisted job")
end

return tests
