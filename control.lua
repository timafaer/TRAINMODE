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
})
