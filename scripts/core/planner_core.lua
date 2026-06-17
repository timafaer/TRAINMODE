local dispatcher_core = require("scripts.core.dispatcher_core")
local load_planner = require("scripts.core.load_planner")

local planner_core = {}

-- Backward-compatible load planning entry point for isolated DTOs.
-- Обратная совместимость: планирование загрузки по уже изолированным DTO.
function planner_core.plan(request, trains, sources, options)
  return load_planner.plan(request, trains, sources, options)
end

-- Full dispatcher entry point for raw station tables.
-- Полная точка входа диспетчера для сырых таблиц станций.
function planner_core.plan_from_stations(stations, trains, route_costs, options)
  return dispatcher_core.plan_from_stations(stations, trains, route_costs, options)
end

return planner_core
