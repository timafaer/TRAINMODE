local combinator = {}

-- Copies a flat map or array into an independent table.
-- Копирует плоскую карту или массив в независимую таблицу.
local function copy_map(source)
  local result = {}
  for key, value in pairs(source or {}) do
    result[key] = value
  end
  return result
end

-- Returns resource names sorted by descending requested amount and stable name.
-- Возвращает ресурсы по убыванию объема и стабильному имени.
local function sorted_resource_names(resources)
  local names = {}
  for resource, stacks in pairs(resources) do
    if stacks > 0 then
      names[#names + 1] = resource
    end
  end
  table.sort(names, function(left, right)
    if resources[left] == resources[right] then
      return left < right
    end
    return resources[left] > resources[right]
  end)
  return names
end

-- Checks whether a train class may carry a resource.
-- Проверяет, может ли класс поезда перевозить ресурс.
local function class_allows_resource(train_class, resource)
  local allowed = train_class.allowed_resources
  return not allowed or allowed[resource] == true
end

-- Checks whether two depots expose the same planning-relevant train class.
-- Проверяет совпадение значимых для планирования классов двух депо.
local function classes_are_compatible(left, right)
  if left.id ~= nil and right.id ~= nil then
    return left.id == right.id
  end
  return left.capacity_stacks == right.capacity_stacks
    and left.cargo_type == right.cargo_type
    and left.length == right.length
end

-- Packs one resource remainder into the tightest suitable cargo bin.
-- Укладывает остаток ресурса в наиболее плотно подходящий грузовой блок.
local function add_to_best_bin(bins, resource, stacks, capacity)
  local best_index
  local best_space

  for index, bin in ipairs(bins) do
    local space = capacity - bin.total_stacks
    if space >= stacks and (not best_space or space < best_space) then
      best_index = index
      best_space = space
    end
  end

  if not best_index then
    bins[#bins + 1] = {
      resources = { [resource] = stacks },
      total_stacks = stacks,
    }
    return
  end

  local bin = bins[best_index]
  bin.resources[resource] = (bin.resources[resource] or 0) + stacks
  bin.total_stacks = bin.total_stacks + stacks
end

-- Adds resource stacks to a station stop, creating the stop when necessary.
-- Добавляет стаки ресурса в остановку, при необходимости создавая ее.
local function add_stop(load_plan, station_id, resource, stacks)
  local stop = load_plan.stops_by_id[station_id]
  local created = false
  if not stop then
    stop = {
      station_id = station_id,
      resources = {},
    }
    load_plan.stops_by_id[station_id] = stop
    load_plan.stops[#load_plan.stops + 1] = stop
    created = true
  end
  stop.resources[resource] = (stop.resources[resource] or 0) + stacks
  load_plan.resources[resource] =
    (load_plan.resources[resource] or 0) + stacks
  load_plan.total_stacks = load_plan.total_stacks + stacks
  return created
end

-- Consumes resource stacks shared by all routes of the current request.
-- Списывает стаки из общего остатка станции для всех маршрутов запроса.
local function consume_station_resource(state, station_id, resource, stacks)
  local station_resources = state.remaining_station_resources[station_id]
  local available = station_resources[resource] or 0

  if stacks > available then
    error("planned station resource consumption exceeds available stacks")
  end

  station_resources[resource] = available - stacks
  state.remaining_request_resources[resource] =
    math.max(
      0,
      (state.remaining_request_resources[resource] or 0) - stacks
    )
end

-- Measures how much of the whole remaining request a station can still cover.
-- Измеряет, какую часть всего оставшегося запроса еще покрывает станция.
local function get_global_station_coverage(state, station_id)
  local station_resources = state.remaining_station_resources[station_id]
  local useful_types = 0
  local useful_stacks = 0

  for resource, remaining in pairs(state.remaining_request_resources) do
    local available = station_resources[resource] or 0
    if remaining > 0 and available > 0 then
      useful_types = useful_types + 1
      useful_stacks = useful_stacks + math.min(remaining, available)
    end
  end

  return useful_types, useful_stacks
end

-- Initializes the resumable state of the combinatorial stage.
-- Инициализирует возобновляемое состояние комбинаторной стадии.
local function initialize(job, provider)
  local state = job.combinator_state

  -- Получает ресурсы запроса только при начале комбинаторной стадии.
  state.requested_resources =
    copy_map(provider.get_requested_resources(job.request_id))
  state.station_resources = {}
  state.remaining_station_resources = {}
  state.remaining_station_slots = {}
  state.station_index = 1
  state.depot_index = 1
  state.depot_classes = {}
  state.request_resource_names =
    sorted_resource_names(state.requested_resources)
  state.phase = "collect_stations"
end

-- Reads and snapshots resources of one loading station.
-- Читает и сохраняет ресурсы одной станции загрузки.
local function collect_one_station(job, provider)
  local state = job.combinator_state
  local station_id = job.loading_station_ids[state.station_index]

  if not station_id then
    state.phase = "collect_depots"
    return
  end

  -- Лениво получает ресурсы и свободные места лимита одной станции.
  local resources = copy_map(provider.get_station_resources(station_id))
  state.station_resources[station_id] = resources
  state.remaining_station_resources[station_id] = copy_map(resources)
  state.remaining_station_slots[station_id] =
    math.max(
      0,
      provider.get_station_available_train_slots(station_id) or 0
    )
  state.station_index = state.station_index + 1
end

-- Reads the common train class of one depot.
-- Читает общий класс поездов одного депо.
local function collect_one_depot(job, provider)
  local state = job.combinator_state
  local depot_id = job.depot_ids[state.depot_index]

  if not depot_id then
    state.available_request = {}
    state.total_available_stacks = 0
    state.availability_resource_index = 1
    state.availability_station_index = 1
    state.current_available_stacks = 0
    state.phase = "calculate_availability"
    return
  end

  -- Лениво получает параметры общего класса поездов одного депо.
  local train_class = provider.get_depot_train_class(depot_id)
  if train_class then
    state.depot_classes[#state.depot_classes + 1] = {
      depot_id = depot_id,
      train_class = train_class,
    }
  end
  state.depot_index = state.depot_index + 1
end

-- Accumulates availability for one resource-station pair.
-- Накапливает доступность для одной пары ресурс-станция.
local function calculate_one_availability_part(job)
  local state = job.combinator_state
  local resource =
    state.request_resource_names[state.availability_resource_index]

  if not resource then
    state.select_depot_index = 1
    state.selected_depot = nil
    state.phase = "select_depot"
    return
  end

  local station_id =
    job.loading_station_ids[state.availability_station_index]
  if station_id then
    if state.remaining_station_slots[station_id] > 0 then
      state.current_available_stacks =
        state.current_available_stacks
        + (state.station_resources[station_id][resource] or 0)
    end
    state.availability_station_index =
      state.availability_station_index + 1
    return
  end

  local available = math.min(
    state.requested_resources[resource],
    state.current_available_stacks
  )
  state.available_request[resource] = available
  state.total_available_stacks =
    state.total_available_stacks + available
  state.availability_resource_index =
    state.availability_resource_index + 1
  state.availability_station_index = 1
  state.current_available_stacks = 0
end

-- Evaluates one depot class and selects the class requiring fewer trains.
-- Оценивает один класс депо и выбирает класс с меньшим числом поездов.
local function select_one_depot(job)
  local state = job.combinator_state
  local candidate = state.depot_classes[state.select_depot_index]

  if not candidate then
    if not state.selected_depot or state.total_available_stacks == 0 then
      job.phase = "completed"
      job.status = "completed"
      return
    end

    state.selected_depot_id = state.selected_depot.depot_id
    state.selected_train_class = state.selected_depot.train_class
    state.remaining_request_resources = copy_map(state.available_request)
    state.used_station_ids = {}
    state.compatible_depot_ids = {}
    state.compatible_depot_index = 1
    state.phase = "collect_compatible_depots"
    return
  end

  local capacity = candidate.train_class.capacity_stacks or 0
  if capacity > 0 then
    local train_count = math.ceil(state.total_available_stacks / capacity)
    local selected = state.selected_depot
    if not selected
      or train_count < selected.train_count
      or (
        train_count == selected.train_count
        and candidate.depot_id < selected.depot_id
      )
    then
      state.selected_depot = {
        depot_id = candidate.depot_id,
        train_class = candidate.train_class,
        train_count = train_count,
      }
    end
  end
  state.select_depot_index = state.select_depot_index + 1
end

-- Adds one depot compatible with the selected train class.
-- Добавляет одно депо, совместимое с выбранным классом поезда.
local function collect_one_compatible_depot(state)
  local candidate = state.depot_classes[state.compatible_depot_index]

  if not candidate then
    state.bin_resource_names =
      sorted_resource_names(state.available_request)
    state.bin_resource_index = 1
    state.bin_resource_remaining = nil
    state.cargo_bins = {}
    state.remainders = {}
    state.phase = "build_full_bins"
    return
  end

  if classes_are_compatible(
    state.selected_train_class,
    candidate.train_class
  ) then
    state.compatible_depot_ids[#state.compatible_depot_ids + 1] =
      candidate.depot_id
  end
  state.compatible_depot_index = state.compatible_depot_index + 1
end

-- Creates one full single-resource bin or records one remainder.
-- Создает один полный одноресурсный блок или сохраняет один остаток.
local function build_one_full_bin(state)
  local resource = state.bin_resource_names[state.bin_resource_index]
  if not resource then
    table.sort(state.remainders, function(left, right)
      if left.stacks == right.stacks then
        return left.resource < right.resource
      end
      return left.stacks > right.stacks
    end)
    state.remainder_index = 1
    state.phase = "pack_remainders"
    return
  end

  if state.bin_resource_remaining == nil then
    if not class_allows_resource(state.selected_train_class, resource) then
      state.bin_resource_index = state.bin_resource_index + 1
      return
    end
    state.bin_resource_remaining = state.available_request[resource]
  end

  local capacity = state.selected_train_class.capacity_stacks
  if state.bin_resource_remaining >= capacity then
    state.cargo_bins[#state.cargo_bins + 1] = {
      resources = { [resource] = capacity },
      total_stacks = capacity,
    }
    state.bin_resource_remaining =
      state.bin_resource_remaining - capacity
    return
  end

  if state.bin_resource_remaining > 0 then
    state.remainders[#state.remainders + 1] = {
      resource = resource,
      stacks = state.bin_resource_remaining,
    }
  end
  state.bin_resource_index = state.bin_resource_index + 1
  state.bin_resource_remaining = nil
end

-- Packs one resource remainder after all pure full bins are created.
-- Упаковывает один остаток после создания чистых полных блоков.
local function pack_one_remainder(state)
  local remainder = state.remainders[state.remainder_index]
  if not remainder then
    state.bin_index = 1
    state.phase = "start_bin"
    return
  end

  add_to_best_bin(
    state.cargo_bins,
    remainder.resource,
    remainder.stacks,
    state.selected_train_class.capacity_stacks
  )
  state.remainder_index = state.remainder_index + 1
end

-- Starts assigning one cargo bin to loading stations.
-- Начинает распределение одного грузового блока по станциям загрузки.
local function start_one_bin(state)
  local bin = state.cargo_bins[state.bin_index]
  if not bin then
    state.phase = "done"
    return
  end

  state.current_bin = bin
  state.current_resource_names = sorted_resource_names(bin.resources)
  state.current_resource_index = 1
  state.current_resource_remaining =
    bin.resources[state.current_resource_names[1]]
  state.station_scan_index = 1
  state.best_station_id = nil
  state.best_station_amount = 0
  state.best_station_useful_types = 0
  state.best_station_current_route = false
  state.best_station_globally_used = false
  state.best_station_global_useful_types = 0
  state.best_station_global_useful_stacks = 0
  state.current_load_plan = {
    depot_ids = copy_map(state.compatible_depot_ids),
    train_class_id = state.selected_train_class.id,
    capacity_stacks = state.selected_train_class.capacity_stacks,
    resources = {},
    total_stacks = 0,
    stops = {},
    stops_by_id = {},
  }
  state.phase = "assign_resource"
end

-- Compares station candidates by unique-station and stop minimization goals.
-- Сравнивает станции по целям минимизации уникальных станций и остановок.
local function is_better_station_candidate(candidate, best)
  if not best then
    return true
  end
  if candidate.current_route ~= best.current_route then
    return candidate.current_route
  end
  if candidate.globally_used ~= best.globally_used then
    return candidate.globally_used
  end
  if candidate.global_useful_types ~= best.global_useful_types then
    return candidate.global_useful_types > best.global_useful_types
  end
  if candidate.global_useful_stacks ~= best.global_useful_stacks then
    return candidate.global_useful_stacks > best.global_useful_stacks
  end
  if candidate.current_bin_useful_types ~= best.current_bin_useful_types then
    return candidate.current_bin_useful_types > best.current_bin_useful_types
  end
  if candidate.amount ~= best.amount then
    return candidate.amount > best.amount
  end
  return candidate.station_id < best.station_id
end

-- Evaluates one station or commits one selected resource chunk.
-- Оценивает одну станцию или фиксирует один выбранный фрагмент ресурса.
local function assign_one_resource_chunk(job)
  local state = job.combinator_state
  local resource = state.current_resource_names[state.current_resource_index]

  if not resource then
    state.current_load_plan.stops_by_id = nil
    if state.current_load_plan.total_stacks > 0 then
      job.load_plans[#job.load_plans + 1] = state.current_load_plan
    end
    state.bin_index = state.bin_index + 1
    state.phase = "start_bin"
    return
  end

  local station_id = job.loading_station_ids[state.station_scan_index]
  if station_id then
    local resources = state.remaining_station_resources[station_id]
    local already_used =
      state.current_load_plan.stops_by_id[station_id] ~= nil
    local globally_used = state.used_station_ids[station_id] == true
    local has_slot =
      already_used or state.remaining_station_slots[station_id] > 0
    local amount = 0
    if has_slot then
      amount =
        math.min(resources[resource] or 0, state.current_resource_remaining)
    end
    local useful_types = 0
    local global_useful_types = 0
    local global_useful_stacks = 0

    if amount > 0 then
      for useful_resource in pairs(state.current_bin.resources) do
        if (resources[useful_resource] or 0) > 0 then
          useful_types = useful_types + 1
        end
      end
      global_useful_types, global_useful_stacks =
        get_global_station_coverage(state, station_id)

      local candidate = {
        station_id = station_id,
        current_route = already_used,
        globally_used = globally_used,
        global_useful_types = global_useful_types,
        global_useful_stacks = global_useful_stacks,
        current_bin_useful_types = useful_types,
        amount = amount,
      }
      local best = state.best_station_id and {
        station_id = state.best_station_id,
        current_route = state.best_station_current_route,
        globally_used = state.best_station_globally_used,
        global_useful_types = state.best_station_global_useful_types,
        global_useful_stacks = state.best_station_global_useful_stacks,
        current_bin_useful_types = state.best_station_useful_types,
        amount = state.best_station_amount,
      } or nil

      if is_better_station_candidate(candidate, best) then
        state.best_station_id = station_id
        state.best_station_amount = amount
        state.best_station_useful_types = useful_types
        state.best_station_current_route = already_used
        state.best_station_globally_used = globally_used
        state.best_station_global_useful_types = global_useful_types
        state.best_station_global_useful_stacks = global_useful_stacks
      end
    end

    state.station_scan_index = state.station_scan_index + 1
    return
  end

  if not state.best_station_id then
    state.current_resource_index = state.current_resource_index + 1
    local next_resource =
      state.current_resource_names[state.current_resource_index]
    state.current_resource_remaining =
      next_resource and state.current_bin.resources[next_resource] or nil
    state.station_scan_index = 1
    return
  end

  local created = add_stop(
    state.current_load_plan,
    state.best_station_id,
    resource,
    state.best_station_amount
  )
  if created then
    state.remaining_station_slots[state.best_station_id] =
      state.remaining_station_slots[state.best_station_id] - 1
  end
  state.used_station_ids[state.best_station_id] = true
  consume_station_resource(
    state,
    state.best_station_id,
    resource,
    state.best_station_amount
  )
  state.current_resource_remaining =
    state.current_resource_remaining - state.best_station_amount
  state.station_scan_index = 1
  state.best_station_id = nil
  state.best_station_amount = 0
  state.best_station_useful_types = 0
  state.best_station_current_route = false
  state.best_station_globally_used = false
  state.best_station_global_useful_types = 0
  state.best_station_global_useful_stacks = 0

  if state.current_resource_remaining == 0 then
    state.current_resource_index = state.current_resource_index + 1
    local next_resource =
      state.current_resource_names[state.current_resource_index]
    state.current_resource_remaining =
      next_resource and state.current_bin.resources[next_resource] or nil
  end
end

-- Performs one resumable combinatorial planning operation.
-- Выполняет одну возобновляемую операцию комбинаторного планирования.
function combinator.step(job, provider)
  local state = job.combinator_state

  if not state.phase then
    initialize(job, provider)
  elseif state.phase == "collect_stations" then
    collect_one_station(job, provider)
  elseif state.phase == "collect_depots" then
    collect_one_depot(job, provider)
  elseif state.phase == "calculate_availability" then
    calculate_one_availability_part(job)
  elseif state.phase == "select_depot" then
    select_one_depot(job)
  elseif state.phase == "collect_compatible_depots" then
    collect_one_compatible_depot(state)
  elseif state.phase == "build_full_bins" then
    build_one_full_bin(state)
  elseif state.phase == "pack_remainders" then
    pack_one_remainder(state)
  elseif state.phase == "start_bin" then
    start_one_bin(state)
  elseif state.phase == "assign_resource" then
    assign_one_resource_chunk(job)
  elseif state.phase == "done" then
    job.phase = "route_search"
    job.route_state = {
      plan_index = 1,
      phase = "start_plan",
    }
  end
end

return combinator
