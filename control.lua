local constants = require("scripts.constants")
local storage_init = require("scripts.storage.init")
local stations = require("scripts.registry.stations")
local trains = require("scripts.registry.trains")
local depots = require("scripts.registry.depots")
local dispatcher = require("scripts.dispatcher.service")
local bootstrap = require("scripts.bootstrap")

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
    stations.unregister(state(), entity)
    depots.rebuild(state())
  end
end

script.on_init(function()
  local runtime = state()
  bootstrap.rebuild(runtime)
end)

script.on_configuration_changed(function()
  local runtime = state()
  bootstrap.rebuild(runtime)
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
    bootstrap.rebuild(state())
  end,
})
