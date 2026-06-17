local table_utils = require("scripts.core.table_utils")

local candidate_filter = {}

-- Returns reserved item amounts for one source station.
-- Возвращает зарезервированные количества предметов для одной станции-источника.
local function reserved_for_station(reservations, station_id)
  if not reservations then
    return {}
  end

  return reservations[station_id] or reservations[tostring(station_id)] or {}
end

-- Subtracts reservations from an offer item map without mutating the original offer.
-- Вычитает резервации из карты предметов предложения, не меняя исходное предложение.
local function available_after_reservations(offer, reservations)
  local reserved = reserved_for_station(reservations, offer.station_id)
  local result = {}

  for item_name, amount in pairs(offer.items or {}) do
    local available = amount - (reserved[item_name] or 0)
    if available > 0 then
      result[item_name] = available
    end
  end

  return result
end

-- Keeps only resources that are requested by the target request.
-- Оставляет только ресурсы, которые нужны целевому запросу.
local function intersect_requested_items(request_items, available_items)
  local result = {}

  for item_name, requested_amount in pairs(request_items or {}) do
    local available = available_items[item_name] or 0
    if requested_amount > 0 and available > 0 then
      result[item_name] = available
    end
  end

  return result
end

-- Checks request source policy against offer station flags.
-- Проверяет режим источников запроса относительно флагов станции-предложения.
local function source_policy_allows(request, offer)
  local policy = request.source_policy or "normal"
  if policy == "only-buffer" then
    return offer.buffer_mode == true
  end
  return true
end

-- Checks whether the source still has free train-limit capacity.
-- Проверяет, остался ли у источника свободный лимит поездов.
local function train_limit_allows(offer)
  if offer.train_limit == nil then
    return true
  end

  return (offer.assigned_train_count or 0) < offer.train_limit
end

-- Checks basic station compatibility: surface, force, enabled DTO and source policy.
-- Проверяет базовую совместимость станций: поверхность, force, DTO и режим источника.
local function base_offer_allows_request(request, offer)
  if request.surface_id ~= nil and offer.surface_id ~= nil and request.surface_id ~= offer.surface_id then
    return false
  end

  if request.force_id ~= nil and offer.force_id ~= nil and request.force_id ~= offer.force_id then
    return false
  end

  return source_policy_allows(request, offer) and train_limit_allows(offer)
end

-- Checks optional whitelist/blacklist filters stored on request and offer DTOs.
-- Проверяет необязательные whitelist/blacklist-фильтры из DTO запроса и предложения.
local function filters_allow(request, offer)
  local request_filters = request.filters or {}
  local offer_filters = offer.filters or {}

  if request_filters.allowed_source_ids and not request_filters.allowed_source_ids[offer.station_id] then
    return false
  end

  if request_filters.blocked_source_ids and request_filters.blocked_source_ids[offer.station_id] then
    return false
  end

  if offer_filters.allowed_target_ids and not offer_filters.allowed_target_ids[request.target_station_id] then
    return false
  end

  if offer_filters.blocked_target_ids and offer_filters.blocked_target_ids[request.target_station_id] then
    return false
  end

  return true
end

-- Converts one matching offer into a source candidate for the route/load planner.
-- Превращает одно подходящее предложение в кандидата источника для маршрута и загрузки.
local function build_candidate(request, offer, reservations)
  if not base_offer_allows_request(request, offer) or not filters_allow(request, offer) then
    return nil
  end

  local available_items = available_after_reservations(offer, reservations)
  local requested_items = intersect_requested_items(request.items, available_items)
  if not table_utils.has_positive(requested_items) then
    return nil
  end

  return {
    id = offer.station_id,
    station_id = offer.station_id,
    source_station_id = offer.station_id,
    surface_id = offer.surface_id,
    force_id = offer.force_id,
    priority = offer.priority or 0,
    items = requested_items,
    all_items = available_items,
    buffer_mode = offer.buffer_mode == true,
    train_limit = offer.train_limit,
    assigned_train_count = offer.assigned_train_count or 0,
    filters = offer.filters or {},
  }
end

-- Builds source candidates; for multi-resource requests, any source with at least one requested item is included.
-- Собирает кандидатов источников; для запроса из нескольких ресурсов включается любая станция хотя бы с одним нужным ресурсом.
function candidate_filter.filter(request, offers, options)
  options = options or {}
  local candidates = {}

  for _, offer in ipairs(offers or {}) do
    local candidate = build_candidate(request, offer, options.reservations)
    if candidate then
      candidates[#candidates + 1] = candidate
    end
  end

  return candidates
end

return candidate_filter
