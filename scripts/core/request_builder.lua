local table_utils = require("scripts.core.table_utils")

local request_builder = {}

-- Keeps only positive requested item amounts from station data.
-- Оставляет только положительные количества запрошенных предметов из данных станции.
local function positive_items(items)
  local result = {}
  for item_name, amount in pairs(items or {}) do
    if amount and amount > 0 then
      result[item_name] = amount
    end
  end
  return result
end

-- Reads the request item map from known station fields.
-- Читает карту запрошенных предметов из поддерживаемых полей станции.
local function get_station_request_items(station)
  return positive_items(station.request_items or station.manual_requests or station.items)
end

-- Builds one isolated request DTO from an unload station.
-- Собирает один изолированный DTO запроса из станции разгрузки.
function request_builder.from_station(station, created_tick)
  if not station or station.enabled == false or station.mode ~= "unload" then
    return nil
  end

  if station.condition_met == false then
    return nil
  end

  local items = get_station_request_items(station)
  if not table_utils.has_positive(items) then
    return nil
  end

  return {
    id = station.request_id or ("request:" .. tostring(station.id) .. ":" .. tostring(created_tick or 0)),
    station_id = station.id,
    target_station_id = station.id,
    surface_id = station.surface_id,
    force_id = station.force_id,
    priority = station.priority or 0,
    created_tick = created_tick or 0,
    items = items,
    source_policy = station.request_mode or "normal",
    filters = station.filters or {},
  }
end

-- Builds all request DTOs from station tables and sorts them by dispatch priority.
-- Собирает все DTO запросов из таблиц станций и сортирует их по диспетчерскому приоритету.
function request_builder.build_many(stations, created_tick)
  local requests = {}

  for _, station in pairs(stations or {}) do
    local request = request_builder.from_station(station, created_tick)
    if request then
      requests[#requests + 1] = request
    end
  end

  table.sort(requests, function(left, right)
    if left.priority == right.priority then
      if left.created_tick == right.created_tick then
        return tostring(left.station_id) < tostring(right.station_id)
      end
      return left.created_tick < right.created_tick
    end
    return left.priority > right.priority
  end)

  return requests
end

return request_builder
