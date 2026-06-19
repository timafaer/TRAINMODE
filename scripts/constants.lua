local constants = {
  names = {
    station = "smart-train-stop",
    locomotive = "smart-locomotive",
    smart_storage = "smart-storage",
    temporary_storage = "temporary-storage",
    belt_input = "smart-belt-input",
    belt_output = "smart-belt-output",
  },
  station_modes = {
    load = "load",
    unload = "unload",
    depot = "depot",
  },
  request_states = {
    open = "open",
    planning = "planning",
    assigned = "assigned",
    partial = "partial",
    complete = "complete",
    cancelled = "cancelled",
    error = "error",
  },
  delivery_states = {
    assigned = "assigned",
    active = "active",
    complete = "complete",
    cancelled = "cancelled",
  },
  planning_operation_budget = 100,
  station_refresh_interval = 60,
  dispatcher_interval = 15,
}

return constants
