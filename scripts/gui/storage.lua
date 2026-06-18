local constants = require("scripts.constants")

local storage_gui = {}
local FRAME = "trainmode_storage_frame"

-- Opens the temporary-storage item selector.
-- Открывает выбор предмета временного хранилища.
function storage_gui.open(state, player, entity)
  if entity.name ~= constants.names.temporary_storage then
    return
  end
  if player.gui.screen[FRAME] then
    player.gui.screen[FRAME].destroy()
  end
  local record = state.storages[entity.unit_number]
  local frame = player.gui.screen.add({
    type = "frame",
    name = FRAME,
    caption = "Temporary storage filter",
    direction = "vertical",
  })
  frame.auto_center = true
  frame.add({
    type = "choose-elem-button",
    name = "trainmode_storage_resource",
    elem_type = "item",
    elem_value = record and record.selected_resource or nil,
  })
  frame.add({
    type = "button",
    name = "trainmode_close_storage",
    caption = "Close",
  })
  state.gui[player.index] = { storage_unit_number = entity.unit_number }
end

-- Applies the selected temporary-storage item.
-- Применяет выбранный предмет временного хранилища.
function storage_gui.on_elem_changed(state, event)
  if event.element.name ~= "trainmode_storage_resource" then
    return false
  end
  local gui_state = state.gui[event.player_index]
  local record =
    gui_state and state.storages[gui_state.storage_unit_number]
  if record then
    record.selected_resource = event.element.elem_value
  end
  return true
end

-- Handles the storage close button.
-- Обрабатывает кнопку закрытия окна хранилища.
function storage_gui.on_click(event)
  if event.element.name ~= "trainmode_close_storage" then
    return false
  end
  local player = game.get_player(event.player_index)
  if player and player.gui.screen[FRAME] then
    player.gui.screen[FRAME].destroy()
  end
  return true
end

-- Closes the temporary-storage window.
-- Закрывает окно временного хранилища.
function storage_gui.close(player)
  if player and player.gui.screen[FRAME] then
    player.gui.screen[FRAME].destroy()
  end
end

return storage_gui
