local function create_entity(parameters)
  local surface = game.surfaces.nauvis
  local entity = surface.create_entity(parameters)
  if not entity then
    error("TRAINMODE_SMOKE failed to create " .. parameters.name)
  end
  return entity
end

local function build_rail_line()
  for x = -40, 40, 2 do
    create_entity({
      name = "straight-rail",
      position = { x = x, y = 0 },
      direction = defines.direction.east,
      force = "player",
      raise_built = true,
    })
  end
end

local function configure_stop(entity, config)
  remote.call("TRAINMODE", "set_station_config", entity.unit_number, config)
end

local function log_status(tick)
  local status = remote.call("TRAINMODE", "get_status")
  log(
    "TRAINMODE_SMOKE STATUS tick=" .. tick
      .. " stations=" .. status.station_count
      .. " trains=" .. status.train_count
      .. " depots=" .. status.depot_count
      .. " requests=" .. serpent.line(status.requests)
      .. " deliveries=" .. serpent.line(status.deliveries)
      .. " train_state=" .. serpent.line(status.trains)
      .. " jobs=" .. serpent.line(status.jobs)
      .. " results=" .. serpent.line(status.results)
      .. " stations_state=" .. serpent.line(status.stations)
      .. " depots_state=" .. serpent.line(status.depots)
  )
end

script.on_init(function()
  storage.smoke = {}
  local surface = game.surfaces.nauvis
  surface.request_to_generate_chunks({ 0, 0 }, 3)
  surface.force_generate_chunk_requests()
  build_rail_line()

  storage.smoke.depot_stop = create_entity({
    name = "smart-train-stop",
    position = { x = -10, y = 2 },
    direction = defines.direction.east,
    force = "player",
    raise_built = true,
  })
  storage.smoke.source_stop = create_entity({
    name = "smart-train-stop",
    position = { x = 10, y = 2 },
    direction = defines.direction.east,
    force = "player",
    raise_built = true,
  })
  storage.smoke.target_stop = create_entity({
    name = "smart-train-stop",
    position = { x = 30, y = 2 },
    direction = defines.direction.east,
    force = "player",
    raise_built = true,
  })

  storage.smoke.source_storage = create_entity({
    name = "smart-storage",
    position = { x = 10, y = 6 },
    force = "player",
    raise_built = true,
  })
  storage.smoke.target_storage = create_entity({
    name = "smart-storage",
    position = { x = 30, y = 6 },
    force = "player",
    raise_built = true,
  })
  storage.smoke.source_storage.get_inventory(defines.inventory.chest).insert({
    name = "iron-plate",
    count = 1000,
  })

  storage.smoke.locomotive = create_entity({
    name = "smart-locomotive",
    position = { x = -27, y = 0 },
    direction = defines.direction.east,
    force = "player",
    raise_built = true,
  })
  storage.smoke.locomotive.get_fuel_inventory().insert({
    name = "rocket-fuel",
    count = 10,
  })
  create_entity({
    name = "cargo-wagon",
    position = { x = -20, y = 0 },
    direction = defines.direction.east,
    force = "player",
    raise_built = true,
  })
end)

script.on_event(defines.events.on_tick, function(event)
  local smoke = storage.smoke
  if not smoke then
    return
  end
  if event.tick == 2 then
    configure_stop(smoke.depot_stop, { mode = "depot", depot_id = 1 })
    configure_stop(smoke.source_stop, {
      mode = "load",
      priority = 10,
      manual_resources = { ["iron-plate"] = 10 },
    })
    configure_stop(smoke.target_stop, {
      mode = "unload",
      priority = 5,
      manual_requests = { ["iron-plate"] = 10 },
    })
    remote.call("TRAINMODE", "rebuild")
    smoke.locomotive.train.schedule = {
      current = 1,
      records = {
        {
          station = smoke.depot_stop.backer_name,
          wait_conditions = {
            { type = "time", compare_type = "or", ticks = 300 },
          },
        },
      },
    }
    smoke.locomotive.train.manual_mode = false
  elseif event.tick % 60 == 0 then
    local count =
      smoke.target_storage.get_inventory(defines.inventory.chest)
        .get_item_count("iron-plate")
    if count >= 1000 then
      log("TRAINMODE_SMOKE PASS delivered=" .. count .. " tick=" .. event.tick)
      game.set_game_state({
        game_finished = true,
        player_won = true,
        can_continue = false,
      })
    elseif event.tick % 600 == 0 then
      log_status(event.tick)
    end
    if event.tick >= 3600 then
      log("TRAINMODE_SMOKE FAIL delivered=" .. count)
      error("TRAINMODE_SMOKE delivery timeout")
    end
  end
end)
