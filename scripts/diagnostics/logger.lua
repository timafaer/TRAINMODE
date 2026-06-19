local logger = {}

local function enabled()
  local runtime_enabled =
    storage
      and storage.trainmode
      and storage.trainmode.debug_logging == true
  local setting_enabled =
    settings
      and settings.global
      and settings.global["trainmode-debug-logging"]
      and settings.global["trainmode-debug-logging"].value
  return runtime_enabled or setting_enabled
end

local function serialize(value)
  if serpent then
    return serpent.line(value, {
      comment = false,
      nocode = true,
      sparse = true,
      sortkeys = true,
    })
  end
  return tostring(value)
end

-- Writes one structured diagnostic event when runtime tracing is enabled.
-- Записывает одно структурированное событие, если runtime-логирование включено.
function logger.trace(event_name, data)
  if not enabled() or not log then
    return
  end
  local tick = game and game.tick or -1
  log(
    "TRAINMODE_TRACE tick=" .. tostring(tick)
      .. " event=" .. tostring(event_name)
      .. " data=" .. serialize(data or {})
  )
end

return logger
