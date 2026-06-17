local combinator = require("scripts.core.combinator")
local cost_model = require("scripts.core.cost_model")
local table_utils = require("scripts.core.table_utils")

local planner = {}

local function normalize_positive_map(source)
  local result = {}
  for key, value in pairs(source or {}) do
    if value and value > 0 then
      result[key] = value
    end
  end
  return result
end

local function copy_source_items(sources)
  local result = {}
  for _, source in ipairs(sources or {}) do
    result[source.id] = normalize_positive_map(source.items)
  end
  return result
end

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

local function delivery_has_items(delivery)
  return table_utils.has_positive(delivery.items)
end

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

local function add_item_to_delivery(delivery, remaining, item_name, amount)
  if amount <= 0 then
    return
  end

  delivery.items[item_name] = (delivery.items[item_name] or 0) + amount
  remaining[item_name] = (remaining[item_name] or 0) - amount
end

local function choose_primary_item(remaining, order)
  for _, item_name in ipairs(order) do
    if (remaining[item_name] or 0) > 0 then
      return item_name
    end
  end

  return nil
end

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

local function can_source_cover(source_items, items)
  for item_name, amount in pairs(items) do
    if (source_items[item_name] or 0) < amount then
      return false
    end
  end

  return true
end

local function subtract_items(source_items, items)
  for item_name, amount in pairs(items) do
    source_items[item_name] = (source_items[item_name] or 0) - amount
  end
end

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

function planner.plan(request, trains, sources, options)
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

return planner
