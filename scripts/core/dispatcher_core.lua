local candidate_filter = require("scripts.core.candidate_filter")
local load_planner = require("scripts.core.load_planner")
local offer_builder = require("scripts.core.offer_builder")
local request_builder = require("scripts.core.request_builder")
local route_ranker = require("scripts.core.route_ranker")

local dispatcher_core = {}

-- Builds the request/offer/candidate pipeline for one request and returns a load plan.
-- Собирает цепочку request/offer/candidate для одного запроса и возвращает план загрузки.
function dispatcher_core.plan_request(request, offers, trains, route_costs, options)
  options = options or {}

  local candidates = candidate_filter.filter(request, offers, {
    reservations = options.reservations,
  })
  if #candidates == 0 then
    return {
      ok = false,
      reason = "no-candidates",
      request = request,
      candidates = candidates,
    }
  end

  local ranked_candidates = route_ranker.rank(request, candidates, trains, route_costs, options.route)
  if #ranked_candidates == 0 then
    return {
      ok = false,
      reason = "no-route",
      request = request,
      candidates = candidates,
      ranked_candidates = ranked_candidates,
    }
  end

  local plan = load_planner.plan(request, trains, ranked_candidates, {
    weights = options.weights,
    order_limit = options.order_limit,
    train_order_limit = options.train_order_limit,
  })

  plan.request = request
  plan.candidates = candidates
  plan.ranked_candidates = ranked_candidates
  return plan
end

-- Plans the first feasible request from raw station tables.
-- Планирует первый выполнимый запрос из сырых таблиц станций.
function dispatcher_core.plan_from_stations(stations, trains, route_costs, options)
  options = options or {}

  local requests = request_builder.build_many(stations, options.created_tick)
  local offers = offer_builder.build_many(stations)
  local last_failure = nil

  for _, request in ipairs(requests) do
    local plan = dispatcher_core.plan_request(request, offers, trains, route_costs, options)
    if plan.ok then
      plan.requests = requests
      plan.offers = offers
      return plan
    end
    last_failure = plan
  end

  return last_failure or {
    ok = false,
    reason = "no-requests",
    requests = requests,
    offers = offers,
  }
end

return dispatcher_core
