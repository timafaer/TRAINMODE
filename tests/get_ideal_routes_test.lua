local helper = require("tests.test_helper")
local get_ideal_routes = require("scripts.routing.get_ideal_routes")
local route_data_provider = require("scripts.routing.route_data_provider")

local tests = {}

local function with_provider(overrides, callback)
  local original = {}
  for key, value in pairs(route_data_provider) do
    original[key] = value
  end

  for key, value in pairs(overrides) do
    route_data_provider[key] = value
  end

  local ok, err = pcall(callback)

  for key in pairs(route_data_provider) do
    route_data_provider[key] = nil
  end
  for key, value in pairs(original) do
    route_data_provider[key] = value
  end

  if not ok then
    error(err, 0)
  end
end

-- Checks that job creation only collects prefiltered ids and versions.
-- Проверяет, что создание задачи собирает только готовые id и версии.
function tests.creates_job_from_prefiltered_ids()
  local resource_reads = 0
  local distance_reads = 0

  with_provider({
    get_request = function(id)
      return { id = id, priority = 7, created_tick = 50 }
    end,
    get_requester_station_id = function()
      return 900
    end,
    get_suitable_loading_station_ids = function()
      return { 201, 202 }
    end,
    get_suitable_depot_ids = function()
      return { 301 }
    end,
    get_data_version = function(entity_type, id)
      return entity_type .. ":" .. tostring(id)
    end,
    get_station_resources = function()
      resource_reads = resource_reads + 1
      return {}
    end,
    get_station_available_train_slots = function()
      return 1
    end,
    get_distance_between_stations = function()
      distance_reads = distance_reads + 1
      return nil
    end,
  }, function()
    local job = get_ideal_routes.get_ideal_routes(77)

    helper.assert_equal(job.request_id, 77, "request id")
    helper.assert_equal(job.request_station_id, 900, "request station")
    helper.assert_equal(job.loading_station_ids[2], 202, "station selection")
    helper.assert_equal(job.depot_ids[1], 301, "depot selection")
    helper.assert_equal(job.priority, 7, "priority")
    helper.assert_equal(resource_reads, 0, "resource reads")
    helper.assert_equal(distance_reads, 0, "distance reads")
  end)
end

return tests
