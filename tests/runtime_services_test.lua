local helper = require("tests.test_helper")
local storage_init = require("scripts.storage.init")
local requests = require("scripts.dispatcher.requests")
local reservations = require("scripts.dispatcher.reservations")
local scheduler_module = require("scripts.routing.scheduler")
local cargo_transfer = require("scripts.integrations.cargo_transfer")

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

local function fake_inventory(initial)
  local contents = {}
  for name, count in pairs(initial or {}) do
    contents[name] = count
  end
  return {
    get_item_count = function(name)
      return contents[name] or 0
    end,
    insert = function(stack)
      contents[stack.name] = (contents[stack.name] or 0) + stack.count
      return stack.count
    end,
    remove = function(stack)
      local removed = math.min(contents[stack.name] or 0, stack.count)
      contents[stack.name] = (contents[stack.name] or 0) - removed
      return removed
    end,
    contents = contents,
  }
end

-- Checks direct physical transfer between linked storage and cargo wagon.
-- Проверяет физический перенос между хранилищем и грузовым вагоном.
function tests.cargo_transfer_loads_and_unloads_train()
  local original_prototypes = _G.prototypes
  local original_defines = _G.defines
  _G.prototypes = { item = { iron = { stack_size = 1 } } }
  _G.defines = { inventory = { chest = 1, cargo_wagon = 2 } }

  local source_inventory = fake_inventory({ iron = 10 })
  local target_inventory = fake_inventory({})
  local wagon_inventory = fake_inventory({})
  local state = {
    storages_by_station = {
      [1] = { 101 },
      [2] = { 102 },
    },
    storages = {
      [101] = {
        entity = {
          valid = true,
          get_inventory = function() return source_inventory end,
        },
      },
      [102] = {
        entity = {
          valid = true,
          get_inventory = function() return target_inventory end,
        },
      },
    },
  }
  local train = {
    cargo_wagons = {
      {
        get_inventory = function() return wagon_inventory end,
      },
    },
    get_item_count = function(name)
      return wagon_inventory.get_item_count(name)
    end,
  }

  local loaded = cargo_transfer.load_stop(state, train, 1, { iron = 10 })
  local unloaded = cargo_transfer.unload_route(state, train, {
    request_station_id = 2,
    resources = { iron = 10 },
  })

  _G.prototypes = original_prototypes
  _G.defines = original_defines

  helper.assert_equal(loaded, true, "loaded")
  helper.assert_equal(unloaded, true, "unloaded")
  helper.assert_equal(source_inventory.contents.iron, 0, "source iron")
  helper.assert_equal(target_inventory.contents.iron, 10, "target iron")
  helper.assert_equal(wagon_inventory.contents.iron, 0, "wagon iron")
end

return tests
