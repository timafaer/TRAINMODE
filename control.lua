local constants = require("scripts.constants")
local storage_init = require("scripts.storage.init")
local stations = require("scripts.registry.stations")
local trains = require("scripts.registry.trains")
local depots = require("scripts.registry.depots")
local storages = require("scripts.registry.storages")
local dispatcher = require("scripts.dispatcher.service")
local bootstrap = require("scripts.bootstrap")
local station_gui = require("scripts.gui.station")
local storage_gui = require("scripts.gui.storage")

local function storage_link_radius()
  return settings.global["trainmode-storage-link-radius"].value
end

local function state()
  return storage_init.ensure(storage)
end

local function built_entity(event)
  return event.entity or event.created_entity or event.destination
end

local function on_built(event)
  local entity = built_entity(event)
  if not entity or not entity.valid then
    return
  end
  if entity.name == constants.names.station then
    stations.register(state(), entity)
    depots.rebuild(state())
  elseif entity.name == constants.names.smart_storage
    or entity.name == constants.names.temporary_storage
  then
    storages.register(state(), entity)
    storages.relink(state(), storage_link_radius())
  elseif entity.type == "locomotive" or entity.type == "cargo-wagon" then
    trains.refresh(state(), entity.train)
    depots.rebuild(state())
  end
end

local function on_removed(event)
  local entity = event.entity
  if not entity then
    return
  end
  if entity.name == constants.names.station then
    local station_id = state().station_by_unit[entity.unit_number]
    if station_id then
      dispatcher.on_station_removed(state(), station_id)
    end
    stations.unregister(state(), entity)
    depots.rebuild(state())
  elseif entity.name == constants.names.smart_storage
    or entity.name == constants.names.temporary_storage
  then
    storages.unregister(state(), entity)
    storages.relink(state(), storage_link_radius())
  end
end

script.on_init(function()
  local runtime = state()
  bootstrap.rebuild(runtime, storage_link_radius())
end)

script.on_configuration_changed(function()
  local runtime = state()
  bootstrap.rebuild(runtime, storage_link_radius())
end)

script.on_event({
  defines.events.on_built_entity,
  defines.events.on_robot_built_entity,
  defines.events.script_raised_built,
  defines.events.script_raised_revive,
}, on_built)

script.on_event({
  defines.events.on_player_mined_entity,
  defines.events.on_robot_mined_entity,
  defines.events.on_entity_died,
  defines.events.script_raised_destroy,
}, on_removed)

script.on_event(defines.events.on_train_created, function(event)
  dispatcher.on_train_removed(state(), event.old_train_id_1)
  dispatcher.on_train_removed(state(), event.old_train_id_2)
  trains.remove(state(), event.old_train_id_1)
  trains.remove(state(), event.old_train_id_2)
  trains.refresh(state(), event.train)
  depots.rebuild(state())
end)

script.on_event(defines.events.on_train_changed_state, function(event)
  trains.refresh(state(), event.train)
  dispatcher.on_train_changed_state(state(), event.train)
  depots.rebuild(state())
end)

script.on_nth_tick(constants.station_refresh_interval, function(event)
  dispatcher.refresh_stations(state(), event.tick)
  depots.rebuild(state())
  storages.relink(state(), storage_link_radius())
end)

script.on_nth_tick(constants.dispatcher_interval, function()
  dispatcher.poll_deliveries(state())
  dispatcher.tick(state())
end)

script.on_event(defines.events.on_train_schedule_changed, function(event)
  local record = state().trains[event.train.id]
  if record and not record.active_delivery_id then
    record.base_schedule = event.train.schedule
  end
end)

script.on_event(defines.events.on_gui_opened, function(event)
  if event.entity and event.entity.valid
    and event.entity.name == constants.names.station
  then
    station_gui.open(state(), game.get_player(event.player_index), event.entity)
  elseif event.entity and event.entity.valid then
    storage_gui.open(state(), game.get_player(event.player_index), event.entity)
  end
end)

script.on_event(defines.events.on_gui_click, function(event)
  if station_gui.on_click(state(), event) then
    depots.rebuild(state())
    storages.relink(state(), storage_link_radius())
  else
    storage_gui.on_click(event)
  end
end)

script.on_event(defines.events.on_gui_elem_changed, function(event)
  storage_gui.on_elem_changed(state(), event)
end)

script.on_event(defines.events.on_gui_closed, function(event)
  station_gui.close(game.get_player(event.player_index))
  storage_gui.close(game.get_player(event.player_index))
end)

script.on_nth_tick(30, function()
  storages.enforce_filters(state())
end)

commands.add_command("trainmode-status", "Print TRAINMODE runtime status", function(event)
  local player = event.player_index and game.get_player(event.player_index)
  if not player then
    return
  end
  local runtime = state()
  local function count(values)
    local result = 0
    for _ in pairs(values) do result = result + 1 end
    return result
  end
  player.print(
    "TRAINMODE stations=" .. count(runtime.stations)
      .. " trains=" .. count(runtime.trains)
      .. " depots=" .. count(runtime.depots)
      .. " requests=" .. count(runtime.requests)
      .. " deliveries=" .. count(runtime.deliveries)
  )
end)

remote.add_interface("TRAINMODE", {
  set_debug_logging = function(enabled)
    state().debug_logging = enabled == true
  end,
  set_station_config = function(unit_number, config)
    local result = stations.configure(state(), unit_number, config or {})
    depots.rebuild(state())
    return result and result.id or nil
  end,
  get_station = function(unit_number)
    local runtime = state()
    local id = runtime.station_by_unit[unit_number]
    return id and runtime.stations[id] or nil
  end,
  rebuild = function()
    bootstrap.rebuild(state(), storage_link_radius())
  end,
  get_status = function()
    local runtime = state()
    local result = {
      station_count = 0,
      train_count = 0,
      depot_count = 0,
      requests = {},
      deliveries = {},
      trains = {},
      jobs = {},
      results = {},
      stations = {},
      depots = {},
    }
    for _ in pairs(runtime.stations) do
      result.station_count = result.station_count + 1
    end
    for train_id, record in pairs(runtime.trains) do
      result.train_count = result.train_count + 1
      result.trains[train_id] = {
        state = record.state,
        depot_id = record.depot_id,
        delivery_id = record.active_delivery_id,
        train_state =
          record.train and record.train.valid and record.train.state or nil,
        station_name =
          record.train and record.train.valid and record.train.station
            and record.train.station.backer_name or nil,
        capacity_stacks = record.capacity_stacks,
        cargo_wagon_count =
          record.train and record.train.valid and #record.train.cargo_wagons or 0,
      }
    end
    for depot_id, depot in pairs(runtime.depots) do
      result.depot_count = result.depot_count + 1
      result.depots[depot_id] = {
        stations = depot.station_ids,
        trains = depot.train_ids,
      }
    end
    for station_id, station in pairs(runtime.stations) do
      result.stations[station_id] = {
        mode = station.mode,
        resources = station.available_resources,
        train_limit =
          station.entity and station.entity.valid and station.entity.trains_limit,
        trains_count =
          station.entity and station.entity.valid and station.entity.trains_count,
        connected_rail =
          station.entity and station.entity.valid
            and station.entity.connected_rail ~= nil,
      }
    end
    for request_id, request in pairs(runtime.requests) do
      result.requests[request_id] = {
        state = request.state,
        station_id = request.station_id,
        last_error = request.last_error,
        created_tick = request.created_tick,
        requested_resources = request.requested_resources,
        remaining_resources = request.remaining_resources,
        delivery_ids = request.delivery_ids,
      }
    end
    for delivery_id, delivery in pairs(runtime.deliveries) do
      result.deliveries[delivery_id] = {
        state = delivery.state,
        train_id = delivery.train_id,
        last_error = delivery.last_error,
        started_loading = delivery.started_loading,
        route = delivery.route,
      }
    end
    for job_id, job in pairs(runtime.scheduler.jobs) do
      result.jobs[job_id] = {
        phase = job.phase,
        status = job.status,
        combinator_phase =
          job.combinator_state and job.combinator_state.phase,
        route_phase = job.route_state and job.route_state.phase,
      }
    end
    for result_id, routes in pairs(runtime.scheduler.results) do
      result.results[result_id] = {
        route_count = #routes,
        error = routes.error,
      }
    end
    return result
  end,
})
