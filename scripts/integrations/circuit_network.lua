local circuit_network = {}

local function read_connector(entity, connector_id, result)
  for _, signal in ipairs(entity.get_signals(connector_id) or {}) do
    if signal.signal.type == "item" and signal.count > 0 then
      local name = signal.signal.name
      result[name] = (result[name] or 0) + signal.count
    end
  end
end

-- Reads positive item signals from the red circuit network.
-- Читает положительные предметные сигналы красной логической сети.
function circuit_network.read_red_items(entity)
  local result = {}
  if entity and entity.valid then
    read_connector(
      entity,
      defines.wire_connector_id.circuit_red,
      result
    )
  end
  return result
end

-- Reads positive item signals from the green circuit network.
-- Читает положительные предметные сигналы зеленой логической сети.
function circuit_network.read_green_items(entity)
  local result = {}
  if entity and entity.valid then
    read_connector(
      entity,
      defines.wire_connector_id.circuit_green,
      result
    )
  end
  return result
end

return circuit_network
