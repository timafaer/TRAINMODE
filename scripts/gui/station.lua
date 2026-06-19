local stations = require("scripts.registry.stations")

local station_gui = {}

local FRAME = "trainmode_station_frame"

local modes = { "load", "unload", "depot" }
local policies = { "normal", "prefer-buffer", "only-buffer" }

local function find_child(element, name)
  if element.name == name then
    return element
  end
  for _, child in ipairs(element.children) do
    local found = find_child(child, name)
    if found then
      return found
    end
  end
  return nil
end

local function selected_index(values, selected)
  for index, value in ipairs(values) do
    if value == selected then
      return index
    end
  end
  return 1
end

local function resources_to_text(resources)
  local parts = {}
  for resource, stacks in pairs(resources or {}) do
    parts[#parts + 1] = resource .. "=" .. tostring(stacks)
  end
  table.sort(parts)
  return table.concat(parts, ",")
end

local function parse_resources(text)
  local result = {}
  for resource, stacks in string.gmatch(text or "", "([%w%-_]+)%s*=%s*(%d+)") do
    if prototypes.item[resource] then
      result[resource] = tonumber(stacks)
    end
  end
  return result
end

local function add_labeled_field(frame, caption, name, text)
  local flow = frame.add({ type = "flow", direction = "horizontal" })
  flow.add({ type = "label", caption = caption })
  flow.add({ type = "textfield", name = name, text = text or "" })
end

-- Opens the station configuration window.
-- Открывает окно настройки станции.
function station_gui.open(state, player, entity)
  local station_id = state.station_by_unit[entity.unit_number]
  local station = station_id and state.stations[station_id]
  if not station then
    return
  end

  if player.gui.screen[FRAME] then
    player.gui.screen[FRAME].destroy()
  end
  local frame = player.gui.screen.add({
    type = "frame",
    name = FRAME,
    caption = "TRAINMODE #" .. station.id,
    direction = "vertical",
  })
  frame.auto_center = true
  frame.add({
    type = "drop-down",
    name = "trainmode_mode",
    items = modes,
    selected_index = selected_index(modes, station.mode),
  })
  add_labeled_field(frame, "Priority", "trainmode_priority", tostring(station.priority))
  add_labeled_field(
    frame,
    "Depot ID",
    "trainmode_depot_id",
    station.depot_id and tostring(station.depot_id) or ""
  )
  frame.add({
    type = "drop-down",
    name = "trainmode_policy",
    items = policies,
    selected_index = selected_index(policies, station.source_policy),
  })
  frame.add({
    type = "checkbox",
    name = "trainmode_enabled",
    caption = "Enabled",
    state = station.enabled,
  })
  frame.add({
    type = "checkbox",
    name = "trainmode_buffer",
    caption = "Buffer station",
    state = station.is_buffer,
  })
  frame.add({
    type = "checkbox",
    name = "trainmode_send_only_to_buffer",
    caption = "Send only to buffer requesters",
    state = station.send_only_to_buffer,
  })
  add_labeled_field(
    frame,
    "Available (item=stacks,...)",
    "trainmode_resources",
    resources_to_text(station.manual_resources)
  )
  add_labeled_field(
    frame,
    "Requests (item=stacks,...)",
    "trainmode_requests",
    resources_to_text(station.manual_requests)
  )
  add_labeled_field(
    frame,
    "Condition signal (item:name / virtual:name)",
    "trainmode_condition_signal",
    station.condition and station.condition.signal or ""
  )
  add_labeled_field(
    frame,
    "Comparator",
    "trainmode_condition_comparator",
    station.condition and station.condition.comparator or ">"
  )
  add_labeled_field(
    frame,
    "Condition constant",
    "trainmode_condition_constant",
    station.condition and tostring(station.condition.constant or 0) or "0"
  )
  local buttons = frame.add({ type = "flow", direction = "horizontal" })
  buttons.add({ type = "button", name = "trainmode_save_station", caption = "Save" })
  buttons.add({ type = "button", name = "trainmode_close_station", caption = "Close" })

  state.gui[player.index] = { station_unit_number = entity.unit_number }
end

-- Handles save and close buttons of the station window.
-- Обрабатывает кнопки сохранения и закрытия окна станции.
function station_gui.on_click(state, event)
  local player = game.get_player(event.player_index)
  local frame = player and player.gui.screen[FRAME]
  if not frame then
    return false
  end
  if event.element.name == "trainmode_close_station" then
    frame.destroy()
    return true
  end
  if event.element.name ~= "trainmode_save_station" then
    return false
  end

  local gui_state = state.gui[player.index]
  local signal = find_child(frame, "trainmode_condition_signal").text
  local condition = nil
  if signal ~= "" then
    condition = {
      signal = signal,
      comparator = find_child(frame, "trainmode_condition_comparator").text,
      constant = tonumber(find_child(frame, "trainmode_condition_constant").text) or 0,
    }
  end
  stations.configure(state, gui_state.station_unit_number, {
    mode = modes[find_child(frame, "trainmode_mode").selected_index],
    priority = tonumber(find_child(frame, "trainmode_priority").text) or 0,
    depot_id = tonumber(find_child(frame, "trainmode_depot_id").text),
    source_policy = policies[find_child(frame, "trainmode_policy").selected_index],
    enabled = find_child(frame, "trainmode_enabled").state,
    is_buffer = find_child(frame, "trainmode_buffer").state,
    send_only_to_buffer =
      find_child(frame, "trainmode_send_only_to_buffer").state,
    manual_requests = parse_resources(find_child(frame, "trainmode_requests").text),
    manual_resources =
      parse_resources(find_child(frame, "trainmode_resources").text),
    condition = condition,
  })
  frame.destroy()
  return true
end

-- Closes the window when Factorio closes its associated GUI.
-- Закрывает окно при закрытии связанного GUI Factorio.
function station_gui.close(player)
  if player and player.gui.screen[FRAME] then
    player.gui.screen[FRAME].destroy()
  end
end

return station_gui
