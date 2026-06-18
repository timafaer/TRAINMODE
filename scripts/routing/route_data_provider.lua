local route_data_provider = {}

-- Returns the request record by request id.
-- Возвращает запись запроса по id запроса.
function route_data_provider.get_request(request_id)
  return nil
end

-- Returns the requester station id for a request.
-- Возвращает id станции-заявителя для запроса.
function route_data_provider.get_requester_station_id(request_id)
  return nil
end

-- Returns requested resources as resource -> stacks.
-- Возвращает запрошенные ресурсы в формате resource -> stacks.
function route_data_provider.get_requested_resources(request_id)
  return {}
end

-- Returns stations from the highest priority tier able to contribute to the request.
-- Возвращает станции максимального приоритета, способные участвовать в запросе.
function route_data_provider.get_suitable_loading_station_ids(request_id)
  return {}
end

-- Returns ids of depots compatible with the request and requester station.
-- Возвращает id депо, совместимых с запросом и станцией-заявителем.
function route_data_provider.get_suitable_depot_ids(request_id)
  return {}
end

-- Returns immutable planning parameters shared by all trains in a depot.
-- Возвращает неизменяемые параметры планирования, общие для поездов депо.
function route_data_provider.get_depot_train_class(depot_id)
  return nil
end

-- Returns station ids that may be used as exits from a depot.
-- Возвращает id станций, которые могут использоваться как выходы из депо.
function route_data_provider.get_depot_station_ids(depot_id)
  return {}
end

-- Returns currently free train ids in a depot.
-- Возвращает id поездов, которые сейчас свободны в депо.
function route_data_provider.get_free_train_ids(depot_id)
  return {}
end

-- Returns available station resources as resource -> stacks.
-- Возвращает доступные ресурсы станции в формате resource -> stacks.
function route_data_provider.get_station_resources(station_id)
  return {}
end

-- Returns currently available train-limit slots including active reservations.
-- Возвращает свободные места лимита поездов с учетом активных резерваций.
function route_data_provider.get_station_available_train_slots(station_id)
  return 0
end

-- Returns path length between any two stations, or nil when no path exists.
-- Возвращает длину пути между любыми двумя станциями или nil, если пути нет.
function route_data_provider.get_distance_between_stations(from_station_id, to_station_id)
  return nil
end

-- Returns a version changed only by planning-critical structural updates.
-- Resource stack counts must not change this version.
-- Возвращает версию, меняющуюся только при критичных структурных изменениях.
-- Количество стаков ресурсов не должно изменять эту версию.
function route_data_provider.get_data_version(entity_type, entity_id)
  return nil
end

return route_data_provider
