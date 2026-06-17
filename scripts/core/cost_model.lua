local table_utils = require("scripts.core.table_utils")

local cost_model = {}

cost_model.default_weights = {
  mixing = 1000,
  train = 500,
  station = 100,
  empty_space = 1,
}

-- Overlays caller-provided weights on top of the default cost model weights.
-- Накладывает переданные веса поверх стандартных весов модели стоимости.
local function merge_weights(weights)
  local merged = table_utils.copy_map(cost_model.default_weights)
  for key, value in pairs(weights or {}) do
    merged[key] = value
  end
  return merged
end

-- Counts distinct loading stations used by one delivery.
-- Считает уникальные станции погрузки, использованные одной доставкой.
local function count_unique_stations(delivery)
  local seen = {}
  local count = 0

  for _, stop in ipairs(delivery.stops or {}) do
    if not seen[stop.station_id] then
      seen[stop.station_id] = true
      count = count + 1
    end
  end

  return count
end

-- Calculates the weighted score and diagnostic metrics for a complete delivery plan.
-- Считает взвешенную стоимость и диагностические метрики полного плана доставок.
function cost_model.score_plan(plan, weights)
  weights = merge_weights(weights)

  local train_count = #(plan.deliveries or {})
  local extra_resource_types = 0
  local load_station_count = 0
  local empty_capacity = 0

  for _, delivery in ipairs(plan.deliveries or {}) do
    local type_count = table_utils.map_count_positive(delivery.items)
    if type_count > 1 then
      extra_resource_types = extra_resource_types + type_count - 1
    end

    load_station_count = load_station_count + count_unique_stations(delivery)
    empty_capacity = empty_capacity + math.max(0, (delivery.capacity or 0) - table_utils.map_sum(delivery.items))
  end

  local total =
    weights.mixing * extra_resource_types +
    weights.train * train_count +
    weights.station * load_station_count +
    weights.empty_space * empty_capacity

  return {
    total = total,
    train_count = train_count,
    extra_resource_types = extra_resource_types,
    load_station_count = load_station_count,
    empty_capacity = empty_capacity,
    weights = weights,
  }
end

-- Compares two scored plans using total cost first, then deterministic tie-breakers.
-- Сравнивает два оцененных плана: сначала по полной стоимости, потом по стабильным правилам.
function cost_model.is_better(left, right)
  if not right then
    return true
  end

  if left.cost.total ~= right.cost.total then
    return left.cost.total < right.cost.total
  end

  if left.cost.extra_resource_types ~= right.cost.extra_resource_types then
    return left.cost.extra_resource_types < right.cost.extra_resource_types
  end

  if left.cost.train_count ~= right.cost.train_count then
    return left.cost.train_count < right.cost.train_count
  end

  if left.cost.load_station_count ~= right.cost.load_station_count then
    return left.cost.load_station_count < right.cost.load_station_count
  end

  return left.cost.empty_capacity < right.cost.empty_capacity
end

return cost_model
