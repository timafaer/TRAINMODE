local depots = {}

local function same_array(left, right)
  if #left ~= #right then
    return false
  end
  for index, value in ipairs(left) do
    if right[index] ~= value then
      return false
    end
  end
  return true
end

-- Rebuilds depot membership from depot-mode stations and idle trains.
-- Перестраивает состав депо по станциям и свободным поездам.
function depots.rebuild(state)
  local previous = state.depots
  local rebuilt = {}
  for station_id, station in pairs(state.stations) do
    if station.enabled and station.mode == "depot" and station.depot_id then
      local depot = rebuilt[station.depot_id] or {
        id = station.depot_id,
        station_ids = {},
        train_ids = {},
      }
      depot.station_ids[#depot.station_ids + 1] = station_id
      rebuilt[station.depot_id] = depot
    end
  end

  for train_id, train_record in pairs(state.trains) do
    local train = train_record.train
    if train and train.valid and train.station and train.station.valid then
      local station_id = state.station_by_unit[train.station.unit_number]
      local station = station_id and state.stations[station_id]
      if station and station.mode == "depot" and station.depot_id then
        train_record.depot_id = station.depot_id
        local depot = rebuilt[station.depot_id]
        if depot then
          depot.train_ids[#depot.train_ids + 1] = train_id
        end
      end
    end
  end

  for depot_id, depot in pairs(rebuilt) do
    table.sort(depot.station_ids)
    table.sort(depot.train_ids)
    local old = previous[depot_id]
    depot.critical_version =
      old
      and old.critical_version
        + (same_array(old.station_ids, depot.station_ids)
          and same_array(old.train_ids, depot.train_ids) and 0 or 1)
      or 1
  end
  state.depots = rebuilt
end

return depots
