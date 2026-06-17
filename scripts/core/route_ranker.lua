local route_ranker = {}

-- Reads route cost from a flexible test-friendly route cost table.
-- Читает стоимость маршрута из гибкой таблицы стоимостей, удобной для тестов.
local function read_route_cost(route_costs, train_id, source_id, target_id)
  if not route_costs then
    return 0
  end

  local by_train = route_costs[train_id] or route_costs[tostring(train_id)]
  if by_train then
    local by_source = by_train[source_id] or by_train[tostring(source_id)]
    if type(by_source) == "table" then
      return by_source[target_id] or by_source[tostring(target_id)]
    end
    if type(by_source) == "number" then
      return by_source
    end
  end

  local by_source = route_costs[source_id] or route_costs[tostring(source_id)]
  if type(by_source) == "table" then
    return by_source[target_id] or by_source[tostring(target_id)]
  end
  if type(by_source) == "number" then
    return by_source
  end

  return nil
end

-- Finds the cheapest reachable route from any available train to one candidate source.
-- Находит самый дешевый достижимый маршрут от любого доступного поезда до одного кандидата-источника.
local function best_route_for_candidate(request, candidate, trains, route_costs)
  local best_cost = nil
  local best_train_id = nil

  for _, train in ipairs(trains or {}) do
    local cost = read_route_cost(route_costs, train.id, candidate.station_id, request.target_station_id)
    if cost ~= nil and (best_cost == nil or cost < best_cost) then
      best_cost = cost
      best_train_id = train.id
    end
  end

  if best_cost == nil then
    return nil
  end

  return best_cost, best_train_id
end

-- Ranks candidates by route cost and source priority, dropping unreachable sources.
-- Ранжирует кандидатов по стоимости пути и приоритету источника, убирая недостижимые источники.
function route_ranker.rank(request, candidates, trains, route_costs, options)
  options = options or {}
  local priority_weight = options.priority_weight or 10
  local ranked = {}

  for _, candidate in ipairs(candidates or {}) do
    local route_cost, train_id = best_route_for_candidate(request, candidate, trains, route_costs)
    if route_cost ~= nil then
      local copy = {}
      for key, value in pairs(candidate) do
        copy[key] = value
      end

      copy.route_cost = route_cost
      copy.best_train_id = train_id
      copy.penalty = route_cost - (copy.priority or 0) * priority_weight
      ranked[#ranked + 1] = copy
    end
  end

  table.sort(ranked, function(left, right)
    if left.penalty == right.penalty then
      return tostring(left.station_id) < tostring(right.station_id)
    end
    return left.penalty < right.penalty
  end)

  return ranked
end

return route_ranker
