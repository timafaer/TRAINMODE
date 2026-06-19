local runner = {}

local SOURCE_DEFINITIONS = {
  {
    x = -50,
    name = "smelter",
    resources = { ["iron-plate"] = 60, ["copper-plate"] = 30 },
  },
  {
    x = 20,
    name = "foundry",
    resources = { ["copper-plate"] = 60, ["steel-plate"] = 30 },
  },
  {
    x = 90,
    name = "mall",
    resources = {
      ["steel-plate"] = 25,
      ["iron-gear-wheel"] = 25,
      ["electronic-circuit"] = 25,
    },
  },
  {
    x = 150,
    name = "mixed",
    resources = { ["iron-plate"] = 40, ["electronic-circuit"] = 40 },
  },
}

local REQUEST_DEFINITIONS = {
  {
    x = 200,
    name = "science",
    resources = { ["iron-plate"] = 40, ["copper-plate"] = 30 },
  },
  {
    x = 235,
    name = "mall-consumer",
    resources = {
      ["steel-plate"] = 20,
      ["iron-gear-wheel"] = 20,
      ["electronic-circuit"] = 20,
    },
  },
  {
    x = 270,
    name = "rocket",
    resources = {
      ["iron-plate"] = 40,
      ["copper-plate"] = 30,
      ["steel-plate"] = 20,
    },
  },
}

local function create_entity(parameters)
  local entity = game.surfaces.nauvis.create_entity(parameters)
  if not entity then
    error(
      "TRAINMODE_LOAD_TEST failed to create "
        .. parameters.name
        .. " at "
        .. serpent.line(parameters.position)
    )
  end
  return entity
end

local function configure_stop(entity, config)
  return remote.call(
    "TRAINMODE",
    "set_station_config",
    entity.unit_number,
    config
  )
end

local function build_rail_line()
  for x = -360, 300, 2 do
    create_entity({
      name = "straight-rail",
      position = { x = x, y = 0 },
      direction = defines.direction.east,
      force = "player",
      raise_built = true,
    })
  end
end

local function try_create_signal(position, direction)
  local surface = game.surfaces.nauvis
  if not surface.can_place_entity({
    name = "rail-signal",
    position = position,
    direction = direction,
    force = "player",
  }) then
    return false
  end
  return surface.create_entity({
    name = "rail-signal",
    position = position,
    direction = direction,
    force = "player",
    raise_built = true,
  }) ~= nil
end

local function create_signal_near(nominal_x)
  local directions = {
    defines.direction.north,
    defines.direction.east,
    defines.direction.south,
    defines.direction.west,
  }
  for x_offset = -2, 2, 0.5 do
    for y = 0.5, 2.5, 0.5 do
      for _, direction in ipairs(directions) do
        local position = { x = nominal_x + x_offset, y = y }
        if try_create_signal(position, direction) then
          return position, direction
        end
      end
    end
  end
  return nil
end

local function build_signals()
  local count = 0
  local sample
  for x = -344, 288, 16 do
    local position, direction = create_signal_near(x)
    if position then
      count = count + 1
      sample = sample or { position = position, direction = direction }
    end
  end
  log(
    "TRAINMODE_LOAD_TEST signals_created="
      .. count
      .. " sample="
      .. serpent.line(sample)
  )
end

local function paint_city_block(center_x, _label)
  local tiles = {}
  for x = center_x - 14, center_x + 14 do
    for y = 4, 24 do
      tiles[#tiles + 1] = {
        name = "refined-concrete",
        position = { x = x, y = y },
      }
    end
  end
  game.surfaces.nauvis.set_tiles(tiles, true, false, false, false)
end

local function item_count(resource, stacks)
  return stacks * prototypes.item[resource].stack_size
end

local function fill_storage(storage_entity, resources)
  local inventory = storage_entity.get_inventory(defines.inventory.chest)
  for resource, stacks in pairs(resources) do
    local inserted = inventory.insert({
      name = resource,
      count = item_count(resource, stacks),
    })
    if inserted ~= item_count(resource, stacks) then
      error("TRAINMODE_LOAD_TEST source storage capacity is too small")
    end
  end
end

local function build_source(definition)
  paint_city_block(definition.x, definition.name)
  local stop = create_entity({
    name = "smart-train-stop",
    position = { x = definition.x, y = 2 },
    direction = defines.direction.east,
    force = "player",
    raise_built = true,
  })
  stop.trains_limit = 4
  local storage_entity = create_entity({
    name = "smart-storage",
    position = { x = definition.x, y = 6 },
    force = "player",
    raise_built = true,
  })
  fill_storage(storage_entity, definition.resources)
  return {
    definition = definition,
    stop = stop,
    storage = storage_entity,
  }
end

local function build_requester(definition)
  paint_city_block(definition.x, definition.name)
  local stop = create_entity({
    name = "smart-train-stop",
    position = { x = definition.x, y = 2 },
    direction = defines.direction.east,
    force = "player",
    raise_built = true,
  })
  stop.trains_limit = 1
  local storage_entity = create_entity({
    name = "smart-storage",
    position = { x = definition.x, y = 6 },
    force = "player",
    raise_built = true,
  })
  return {
    definition = definition,
    stop = stop,
    storage = storage_entity,
  }
end

local function create_train(slot)
  local stop_x = -320 + (slot - 1) * 30
  local locomotive = create_entity({
    name = "smart-locomotive",
    position = { x = stop_x - 17, y = 0 },
    direction = defines.direction.east,
    force = "player",
    raise_built = true,
  })
  locomotive.get_fuel_inventory().insert({
    name = "nuclear-fuel",
    count = 3,
  })
  create_entity({
    name = "cargo-wagon",
    position = { x = stop_x - 10, y = 0 },
    direction = defines.direction.east,
    force = "player",
    raise_built = true,
  })
  local train = locomotive.train
  storage.load_test.train_slots[train.id] = slot
  storage.load_test.slot_train_ids[slot] = train.id
  return locomotive
end

local function build_depot(slot)
  local stop_x = -320 + (slot - 1) * 30
  local stop = create_entity({
    name = "smart-train-stop",
    position = { x = stop_x, y = 2 },
    direction = defines.direction.east,
    force = "player",
    raise_built = true,
  })
  stop.trains_limit = 1
  storage.load_test.depot_stops[slot] = stop
  create_train(slot)
end

local function park_train(slot)
  local train_id = storage.load_test.slot_train_ids[slot]
  local train
  for _, candidate in ipairs(game.train_manager.get_trains({})) do
    if candidate.id == train_id then
      train = candidate
      break
    end
  end
  if not train or not train.valid then
    return
  end
  local stop = storage.load_test.depot_stops[slot]
  train.schedule = {
    current = 1,
    records = {
      {
        station = stop.backer_name,
        wait_conditions = {
          { type = "time", compare_type = "or", ticks = 36000 },
        },
      },
    },
  }
  train.manual_mode = false
end

local function destroy_train(train)
  local carriages = {}
  for _, carriage in ipairs(train.carriages) do
    carriages[#carriages + 1] = carriage
  end
  for _, carriage in ipairs(carriages) do
    if carriage.valid then
      carriage.destroy({ raise_destroy = true })
    end
  end
end

local function clear_completed_trains(status)
  for delivery_id, delivery in pairs(status.deliveries) do
    if delivery.state == "complete"
      and not storage.load_test.recycled_deliveries[delivery_id]
    then
      storage.load_test.recycled_deliveries[delivery_id] = true
      local slot = storage.load_test.train_slots[delivery.train_id]
      if slot then
        for _, train in ipairs(game.train_manager.get_trains({})) do
          if train.id == delivery.train_id then
            destroy_train(train)
            break
          end
        end
        storage.load_test.train_slots[delivery.train_id] = nil
        storage.load_test.slot_train_ids[slot] = nil
        storage.load_test.pending_recycle_slots[slot] = true
        storage.load_test.recycled_deliveries[delivery_id] = true
        log(
          "TRAINMODE_LOAD_TEST train_cleared delivery_id="
            .. delivery_id
            .. " old_train_id="
            .. delivery.train_id
            .. " slot="
            .. slot
        )
      end
    end
  end
end

local function recreate_wave_trains(status)
  for _, delivery in pairs(status.deliveries) do
    if delivery.state == "active" or delivery.state == "assigned" then
      return
    end
  end

  for slot in pairs(storage.load_test.pending_recycle_slots) do
    local locomotive = create_train(slot)
    park_train(slot)
    storage.load_test.pending_recycle_slots[slot] = nil
    log(
      "TRAINMODE_LOAD_TEST train_recreated new_train_id="
        .. locomotive.train.id
        .. " slot="
        .. slot
    )
  end
end

local function all_initial_requests_complete(status)
  if #storage.load_test.request_ids ~= #REQUEST_DEFINITIONS then
    return false
  end
  for _, request_id in ipairs(storage.load_test.request_ids) do
    local request = status.requests[request_id]
    if not request or request.state ~= "complete" then
      return false
    end
  end
  return true
end

local function collect_initial_request_ids(status)
  local ids = {}
  for request_id, request in pairs(status.requests) do
    if request.created_tick <= 300 then
      ids[#ids + 1] = request_id
    end
  end
  table.sort(ids)
  storage.load_test.request_ids = ids
end

local function clear_requester_configuration()
  for _, requester in ipairs(storage.load_test.requesters) do
    configure_stop(requester.stop, {
      manual_requests = {},
    })
  end
end

local function refresh_source_advertisements()
  for _, source in ipairs(storage.load_test.sources) do
    local inventory =
      source.storage.get_inventory(defines.inventory.chest)
    local resources = {}
    for resource in pairs(source.definition.resources) do
      resources[resource] =
        math.floor(
          inventory.get_item_count(resource)
            / prototypes.item[resource].stack_size
        )
    end
    configure_stop(source.stop, {
      manual_resources = resources,
    })
  end
end

local function remove_unused_depot_trains(status)
  for _, request_id in ipairs(storage.load_test.request_ids) do
    local request = status.requests[request_id]
    if not request
      or (request.state ~= "assigned" and request.state ~= "complete")
    then
      return
    end
  end

  local removed = 0
  for _, train in ipairs(game.train_manager.get_trains({})) do
    local record = status.trains[train.id]
    if record and not record.delivery_id then
      local slot = storage.load_test.train_slots[train.id]
      if slot then
        storage.load_test.train_slots[train.id] = nil
        storage.load_test.slot_train_ids[slot] = nil
        destroy_train(train)
        removed = removed + 1
      end
    end
  end
  if removed > 0 then
    log(
      "TRAINMODE_LOAD_TEST unused_depot_trains_removed="
        .. removed
        .. " reason=test-track-has-no-depot-sidings"
    )
  end
end

local function summarize(status, event_tick, final)
  local states = {}
  for _, request_id in ipairs(storage.load_test.request_ids) do
    local request = status.requests[request_id]
    states[request_id] = request and {
      state = request.state,
      remaining_resources = request.remaining_resources,
      delivery_ids = request.delivery_ids,
      last_error = request.last_error,
    } or nil
  end
  log(
    "TRAINMODE_LOAD_TEST " .. (final and "PASS" or "STATUS")
      .. " trains=" .. storage.load_test.train_count
      .. " tick=" .. event_tick
      .. " elapsed=" .. (event_tick - storage.load_test.requests_started_tick)
      .. " request_states=" .. serpent.line(states)
      .. " deliveries=" .. serpent.line(status.deliveries)
      .. " trains_state=" .. serpent.line(status.trains)
      .. " jobs=" .. serpent.line(status.jobs)
  )
end

function runner.register(train_count)
  script.on_init(function()
    settings.global["trainmode-debug-logging"].value = true
    storage.load_test = {
      train_count = train_count,
      depot_stops = {},
      train_slots = {},
      slot_train_ids = {},
      recycled_deliveries = {},
      pending_recycle_slots = {},
      request_ids = {},
      sources = {},
      requesters = {},
    }
    local surface = game.surfaces.nauvis
    surface.request_to_generate_chunks({ 0, 0 }, 12)
    surface.force_generate_chunk_requests()
    build_rail_line()
    build_signals()
    for _, definition in ipairs(SOURCE_DEFINITIONS) do
      storage.load_test.sources[#storage.load_test.sources + 1] =
        build_source(definition)
    end
    for _, definition in ipairs(REQUEST_DEFINITIONS) do
      storage.load_test.requesters[#storage.load_test.requesters + 1] =
        build_requester(definition)
    end
    for slot = 1, train_count do
      build_depot(slot)
    end
    log(
      "TRAINMODE_LOAD_TEST initialized trains=" .. train_count
        .. " sources=" .. #SOURCE_DEFINITIONS
        .. " requesters=" .. #REQUEST_DEFINITIONS
    )
  end)

  script.on_event(defines.events.on_tick, function(event)
    local state = storage.load_test
    if not state then
      return
    end

    if event.tick == 2 then
      remote.call("TRAINMODE", "set_debug_logging", true)
      for slot, stop in ipairs(state.depot_stops) do
        configure_stop(stop, { mode = "depot", depot_id = slot })
      end
      for _, source in ipairs(state.sources) do
        configure_stop(source.stop, {
          mode = "load",
          priority = 10,
          manual_resources = source.definition.resources,
        })
      end
      remote.call("TRAINMODE", "rebuild")
      for slot = 1, state.train_count do
        park_train(slot)
      end
    elseif event.tick == 180 then
      for index, requester in ipairs(state.requesters) do
        configure_stop(requester.stop, {
          mode = "unload",
          priority = 10 - index,
          manual_requests = requester.definition.resources,
        })
      end
      state.requests_started_tick = event.tick
      remote.call("TRAINMODE", "rebuild")
      log(
        "TRAINMODE_LOAD_TEST requests_enabled tick="
          .. event.tick
          .. " definitions="
          .. serpent.line(REQUEST_DEFINITIONS)
      )
    elseif event.tick == 300 then
      local status = remote.call("TRAINMODE", "get_status")
      collect_initial_request_ids(status)
      clear_requester_configuration()
      log(
        "TRAINMODE_LOAD_TEST requests_frozen ids="
          .. serpent.line(state.request_ids)
      )
    end

    if event.tick % 60 == 59 then
      refresh_source_advertisements()
    end

    if event.tick >= 300 and event.tick % 30 == 0 then
      local status = remote.call("TRAINMODE", "get_status")
      if state.train_count >= 2 then
        remove_unused_depot_trains(status)
      end
      clear_completed_trains(status)
      if all_initial_requests_complete(status) then
        summarize(status, event.tick, true)
        game.set_game_state({
          game_finished = true,
          player_won = true,
          can_continue = false,
        })
        return
      end
      recreate_wave_trains(status)
      if event.tick % 600 == 0 then
        summarize(status, event.tick, false)
      end
      if event.tick >= 36000 then
        summarize(status, event.tick, false)
        log(
          "TRAINMODE_LOAD_TEST FAIL trains="
            .. state.train_count
            .. " tick="
            .. event.tick
        )
        error("TRAINMODE_LOAD_TEST delivery timeout")
      end
    end
  end)
end

return runner
