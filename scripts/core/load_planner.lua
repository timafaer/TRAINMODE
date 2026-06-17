local combinator = require("scripts.core.combinator")
local cost_model = require("scripts.core.cost_model")
local table_utils = require("scripts.core.table_utils")

local load_planner = {}

-- Keeps only positive item amounts; zero and negative signals are ignored.
-- Оставляет только положительные количества предметов; нули и отрицательные сигналы игнорируются.
local function normalize_positive_map(source)
  local result = {}
  for key, value in pairs(source or {}) do
    if value and value > 0 then
      result[key] = value
    end
  end
  return result
end

-- Copies source candidate inventories into mutable maps keyed by source id.
-- Копирует запасы кандидатов-источников в изменяемые таблицы по id источника.
local function copy_source_items(sources)
  local result = {}
  for _, source in ipairs(sources or {}) do
    result[source.id] = normalize_positive_map(source.items)
  end
  return result
end

-- Orders source candidates by route/filter penalty first, then by id for deterministic plans.
-- Сортирует кандидатов-источников по штрафу маршрута/фильтра, затем по id для стабильного результата.
local function sorted_sources(sources)
  local result = {}
  for index = 1, #(sources or {}) do
    result[index] = sources[index]
  end

  table.sort(result, function(left, right)
    local left_penalty = left.penalty or 0
    local right_penalty = right.penalty or 0
    if left_penalty == right_penalty then
      return tostring(left.id) < tostring(right.id)
    end
    return left_penalty < right_penalty
  end)

  return result
end

-- Returns true when a delivery has at least one assigned item.
-- Возвращает true, если в доставку назначен хотя бы один предмет.
local function delivery_has_items(delivery)
  return table_utils.has_positive(delivery.items)
end

-- Finds remaining item groups that fully fit in the current free train capacity.
-- Находит оставшиеся группы предметов, которые целиком помещаются в свободное место поезда.
local function complete_item_fit_candidates(remaining, free_capacity, order)
  local candidates = {}

  for _, item_name in ipairs(order) do
    local amount = remaining[item_name] or 0
    if amount > 0 and amount <= free_capacity then
      candidates[#candidates + 1] = {
        item = item_name,
        amount = amount,
      }
    end
  end

  table.sort(candidates, function(left, right)
    if left.amount == right.amount then
      return tostring(left.item) < tostring(right.item)
    end
    return left.amount > right.amount
  end)

  return candidates
end

-- Adds items to a delivery and subtracts them from the remaining request amount.
-- Добавляет предметы в доставку и вычитает их из оставшегося объема запроса.
local function add_item_to_delivery(delivery, remaining, item_name, amount)
  if amount <= 0 then
    return
  end

  delivery.items[item_name] = (delivery.items[item_name] or 0) + amount
  remaining[item_name] = (remaining[item_name] or 0) - amount
end

-- Chooses the next primary item to pack according to the current item order.
-- Выбирает следующий основной предмет для упаковки по текущему порядку предметов.
local function choose_primary_item(remaining, order)
  for _, item_name in ipairs(order) do
    if (remaining[item_name] or 0) > 0 then
      return item_name
    end
  end

  return nil
end

-- Packs request items into trains for one candidate item/train ordering.
-- Раскладывает предметы запроса по поездам для одного варианта порядка предметов и поездов.
local function pack_for_order(request_items, trains, order)
  local remaining = table_utils.copy_map(request_items)
  local deliveries = {}

  for _, train in ipairs(trains) do
    if not table_utils.has_positive(remaining) then
      break
    end

    local capacity = train.capacity or 0
    if capacity > 0 then
      local delivery = {
        train_id = train.id,
        capacity = capacity,
        items = {},
        stops = {},
      }

      local primary_item = choose_primary_item(remaining, order)
      if primary_item then
        add_item_to_delivery(delivery, remaining, primary_item, math.min(remaining[primary_item], capacity))
      end

      local used_capacity = table_utils.map_sum(delivery.items)
      local free_capacity = capacity - used_capacity

      while free_capacity > 0 do
        local candidates = complete_item_fit_candidates(remaining, free_capacity, order)
        if #candidates == 0 then
          break
        end

        local candidate = candidates[1]
        add_item_to_delivery(delivery, remaining, candidate.item, candidate.amount)
        used_capacity = table_utils.map_sum(delivery.items)
        free_capacity = capacity - used_capacity
      end

      if delivery_has_items(delivery) then
        deliveries[#deliveries + 1] = delivery
      end
    end
  end

  if table_utils.has_positive(remaining) then
    return nil, "not-enough-train-capacity"
  end

  return deliveries, nil
end

-- Checks whether one source can cover every item in a delivery by itself.
-- Проверяет, может ли один источник сам закрыть все предметы доставки.
local function can_source_cover(source_items, items)
  for item_name, amount in pairs(items) do
    if (source_items[item_name] or 0) < amount then
      return false
    end
  end

  return true
end

-- Subtracts item amounts from a mutable inventory/reservation map.
-- Вычитает количества предметов из изменяемой таблицы запасов или резерваций.
local function subtract_items(source_items, items)
  for item_name, amount in pairs(items) do
    source_items[item_name] = (source_items[item_name] or 0) - amount
  end
end

-- Calculates how much a source can contribute to an unfinished delivery.
-- Считает, сколько источник может дать для еще не закрытой части доставки.
local function source_contribution(source_items, remaining)
  local contribution = {}
  local total = 0
  local type_count = 0

  for item_name, amount in pairs(remaining) do
    local take = math.min(amount, source_items[item_name] or 0)
    if take > 0 then
      contribution[item_name] = take
      total = total + take
      type_count = type_count + 1
    end
  end

  return contribution, total, type_count
end

-- Picks the source that covers the largest useful part of the remaining delivery.
-- Выбирает источник, который закрывает самую большую полезную часть остатка доставки.
local function choose_best_partial_source(sources, source_items_by_id, remaining)
  local best = nil

  for _, source in ipairs(sources) do
    local contribution, total, type_count = source_contribution(source_items_by_id[source.id] or {}, remaining)
    if total > 0 then
      local candidate = {
        source = source,
        contribution = contribution,
        total = total,
        type_count = type_count,
      }

      if not best then
        best = candidate
      elseif candidate.total > best.total then
        best = candidate
      elseif candidate.total == best.total and candidate.type_count > best.type_count then
        best = candidate
      elseif candidate.total == best.total and candidate.type_count == best.type_count then
        if tostring(candidate.source.id) < tostring(best.source.id) then
          best = candidate
        end
      end
    end
  end

  return best
end

-- Assigns one delivery to one or more loading stations and reserves their items.
-- Назначает одну доставку на одну или несколько станций погрузки и резервирует предметы.
local function allocate_sources_for_delivery(delivery, sources, source_items_by_id)
  local ordered_sources = sorted_sources(sources)

  for _, source in ipairs(ordered_sources) do
    local source_items = source_items_by_id[source.id] or {}
    if can_source_cover(source_items, delivery.items) then
      subtract_items(source_items, delivery.items)
      delivery.stops = {
        {
          station_id = source.id,
          items = table_utils.copy_map(delivery.items),
        },
      }
      return true
    end
  end

  local remaining = table_utils.copy_map(delivery.items)
  local stops = {}

  while table_utils.has_positive(remaining) do
    local best = choose_best_partial_source(ordered_sources, source_items_by_id, remaining)
    if not best then
      return false, "not-enough-source-items"
    end

    subtract_items(source_items_by_id[best.source.id], best.contribution)
    subtract_items(remaining, best.contribution)
    stops[#stops + 1] = {
      station_id = best.source.id,
      items = best.contribution,
    }
  end

  delivery.stops = stops
  return true
end

-- Assigns every packed delivery to available sources, mutating a local source copy.
-- Назначает все упакованные доставки на доступные источники, меняя только локальную копию запасов.
local function allocate_sources(deliveries, sources)
  local source_items_by_id = copy_source_items(sources)

  for _, delivery in ipairs(deliveries) do
    local ok, reason = allocate_sources_for_delivery(delivery, sources, source_items_by_id)
    if not ok then
      return false, reason
    end
  end

  return true, nil
end

-- Builds and scores one complete candidate plan for a specific item/train order.
-- Собирает и оценивает один полный кандидат плана для конкретного порядка предметов и поездов.
local function build_candidate(request_items, trains, sources, order, weights)
  local deliveries, pack_error = pack_for_order(request_items, trains, order)
  if not deliveries then
    return nil, pack_error
  end

  local ok, allocation_error = allocate_sources(deliveries, sources)
  if not ok then
    return nil, allocation_error
  end

  local plan = {
    deliveries = deliveries,
  }
  plan.cost = cost_model.score_plan(plan, weights)

  return plan, nil
end

-- Public load-planner entry point. Works only with isolated request/source/train DTOs.
-- Публичная точка входа планировщика загрузки. Работает только с изолированными DTO запроса, источников и поездов.
function load_planner.plan(request, trains, sources, options)
  options = options or {}

  local request_items = normalize_positive_map(request and request.items)
  if not table_utils.has_positive(request_items) then
    return {
      ok = false,
      reason = "empty-request",
    }
  end

  if #(trains or {}) == 0 then
    return {
      ok = false,
      reason = "no-trains",
    }
  end

  if #(sources or {}) == 0 then
    return {
      ok = false,
      reason = "no-sources",
    }
  end

  local orders = combinator.generate_item_orders(request_items, {
    limit = options.order_limit or 120,
    max_permuted_items = options.max_permuted_items or 6,
  })
  local train_orders = combinator.generate_train_orders(trains, {
    limit = options.train_order_limit or 60,
    max_permuted_trains = options.max_permuted_trains or 5,
  })

  local best_plan = nil
  local last_error = nil

  for _, order in ipairs(orders) do
    for _, train_order in ipairs(train_orders) do
      local candidate, reason = build_candidate(request_items, train_order, sources, order, options.weights)
      if candidate then
        if cost_model.is_better(candidate, best_plan) then
          best_plan = candidate
        end
      else
        last_error = reason
      end
    end
  end

  if not best_plan then
    return {
      ok = false,
      reason = last_error or "no-plan",
    }
  end

  best_plan.ok = true
  return best_plan
end

return load_planner
