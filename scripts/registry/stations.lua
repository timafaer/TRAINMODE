local constants = require("scripts.constants")

local stations = {}

local function default_record(id, entity)
  return {
    id = id,
    unit_number = entity.unit_number,
    entity = entity,
    surface_index = entity.surface.index,
    force_index = entity.force.index,
    mode = constants.station_modes.load,
    priority = 0,
    enabled = true,
    is_buffer = false,
    send_only_to_buffer = false,
    source_policy = "normal",
    depot_id = nil,
    manual_resources = {},
    manual_requests = {},
    condition = nil,
    available_resources = {},
    critical_version = 1,
  }
end

-- Registers a smart train stop and gives it an unambiguous schedule name.
-- Регистрирует умную станцию и задает ей однозначное имя расписания.
function stations.register(state, entity)
  if not entity or not entity.valid or not entity.unit_number then
    return nil
  end
  local existing_id = state.station_by_unit[entity.unit_number]
  if existing_id then
    return state.stations[existing_id]
  end

  local id = state.next_station_id
  state.next_station_id = id + 1
  local record = default_record(id, entity)
  state.stations[id] = record
  state.station_by_unit[entity.unit_number] = id
  entity.backer_name = "[TRAINMODE] " .. tostring(id)
  return record
end

-- Removes a station and invalidates structural users of its id.
-- Удаляет станцию и инвалидирует пользователей ее id.
function stations.unregister(state, entity)
  if not entity or not entity.unit_number then
    return
  end
  local id = state.station_by_unit[entity.unit_number]
  if id then
    state.stations[id] = nil
    state.station_by_unit[entity.unit_number] = nil
  end
end

-- Updates player-configurable structural station parameters.
-- Обновляет настраиваемые структурные параметры станции.
function stations.configure(state, unit_number, config)
  local id = state.station_by_unit[unit_number]
  local station = id and state.stations[id]
  if not station then
    return nil
  end

  local structural_change = false
  for _, key in ipairs({
    "mode", "priority", "enabled", "is_buffer", "send_only_to_buffer",
    "source_policy", "depot_id",
  }) do
    if config[key] ~= nil and station[key] ~= config[key] then
      station[key] = config[key]
      structural_change = true
    end
  end
  if config.manual_requests then
    station.manual_requests = config.manual_requests
  end
  if config.manual_resources then
    station.manual_resources = config.manual_resources
  end
  if config.condition ~= nil then
    station.condition = config.condition
  end
  if structural_change then
    station.critical_version = station.critical_version + 1
  end
  return station
end

return stations
