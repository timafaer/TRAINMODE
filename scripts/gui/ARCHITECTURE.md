# GUI Layer

```text
control.on_gui_opened
  -> station_gui.open или storage_gui.open

control.on_gui_click
  -> station_gui.on_click
     -> stations.configure
     -> depots.rebuild
     -> storages.relink

control.on_gui_elem_changed
  -> storage_gui.on_elem_changed
  -> storage.selected_resource
```

- `station.lua` редактирует режим, приоритет, депо, буферные политики, запрос и
  условие.
- `storage.lua` задает разрешенный предмет временного склада.

GUI меняет модели через registry, но не вызывает планировщик напрямую.
