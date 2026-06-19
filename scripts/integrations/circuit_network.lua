local circuit_network = {}

local function signal_key(signal)
  return signal.type .. ":" .. signal.name
end

local function read_connector(entity, connector_id, result)
  for _, signal in ipairs(entity.get_signals(connector_id) or {}) do
    if signal.signal.type == "item" and signal.count > 0 then
      local name = signal.signal.name
      result[name] = (result[name] or 0) + signal.count
    end
  end
end

-- Reads every signal count from one connector.
-- Читает значения всех сигналов одного коннектора.
function circuit_network.read_counts(entity, connector_id)
  local result = {}
  if entity and entity.valid then
    for _, signal in ipairs(entity.get_signals(connector_id) or {}) do
      result[signal_key(signal.signal)] =
        (result[signal_key(signal.signal)] or 0) + signal.count
    end
  end
  return result
end

-- Evaluates one Factorio-style comparator against a constant.
-- Вычисляет одно условие в стиле Factorio со сравнением с константой.
function circuit_network.evaluate_condition(entity, condition)
  if not condition or not condition.signal then
    return true
  end
  local counts = circuit_network.read_counts(
    entity,
    defines.wire_connector_id.circuit_green
  )
  local left = counts[condition.signal] or 0
  local right = condition.constant or 0
  local comparator = condition.comparator or ">"

  if comparator == ">" then return left > right end
  if comparator == "<" then return left < right end
  if comparator == ">=" then return left >= right end
  if comparator == "<=" then return left <= right end
  if comparator == "=" or comparator == "==" then return left == right end
  if comparator == "!=" or comparator == "~=" then return left ~= right end
  return false
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
