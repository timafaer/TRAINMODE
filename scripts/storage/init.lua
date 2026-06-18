local storage_init = {}

-- Creates every persistent table used by the runtime.
-- Создает все постоянные таблицы runtime-части.
function storage_init.ensure(root)
  root.trainmode = root.trainmode or {}
  local state = root.trainmode

  state.version = state.version or 1
  state.next_station_id = state.next_station_id or 1
  state.next_request_id = state.next_request_id or 1
  state.next_delivery_id = state.next_delivery_id or 1
  state.stations = state.stations or {}
  state.station_by_unit = state.station_by_unit or {}
  state.trains = state.trains or {}
  state.depots = state.depots or {}
  state.storages = state.storages or {}
  state.storages_by_station = state.storages_by_station or {}
  state.requests = state.requests or {}
  state.deliveries = state.deliveries or {}
  state.reservations = state.reservations or {
    station_resources = {},
    station_slots = {},
    trains = {},
  }
  state.scheduler = state.scheduler or { jobs = {}, results = {} }
  state.pending_requests = state.pending_requests or {}
  state.gui = state.gui or {}
  return state
end

return storage_init
