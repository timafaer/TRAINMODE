local table_utils = require("scripts.core.table_utils")

local offer_builder = {}

-- Keeps only positive offered item amounts from station data.
-- Оставляет только положительные количества предлагаемых предметов из данных станции.
local function positive_items(items)
  local result = {}
  for item_name, amount in pairs(items or {}) do
    if amount and amount > 0 then
      result[item_name] = amount
    end
  end
  return result
end

-- Reads the source item map from known station fields.
-- Читает карту доступных предметов из поддерживаемых полей станции.
local function get_station_offer_items(station)
  return positive_items(station.available_items or station.offered_items or station.items)
end

-- Builds one isolated offer DTO from a load station.
-- Собирает один изолированный DTO предложения из станции погрузки.
function offer_builder.from_station(station)
  if not station or station.enabled == false or station.mode ~= "load" then
    return nil
  end

  local items = get_station_offer_items(station)
  if not table_utils.has_positive(items) then
    return nil
  end

  return {
    id = "offer:" .. tostring(station.id),
    station_id = station.id,
    source_station_id = station.id,
    surface_id = station.surface_id,
    force_id = station.force_id,
    priority = station.priority or 0,
    items = items,
    buffer_mode = station.buffer_mode == true,
    send_only_to_buffer = station.send_only_to_buffer == true,
    filters = station.filters or {},
    train_limit = station.train_limit,
    assigned_train_count = station.assigned_train_count or 0,
  }
end

-- Builds all offer DTOs from station tables.
-- Собирает все DTO предложений из таблиц станций.
function offer_builder.build_many(stations)
  local offers = {}

  for _, station in pairs(stations or {}) do
    local offer = offer_builder.from_station(station)
    if offer then
      offers[#offers + 1] = offer
    end
  end

  return offers
end

return offer_builder
