# Factorio Integrations

Эта папка является границей между доменной логикой и Factorio API.

```text
dispatcher/service.lua
  -> circuit_network.lua
     -> LuaEntity.get_signals

  -> train_api.lua
     -> LuaTrain.schedule
     -> LuaTrain.recalculate_path

  -> cargo_transfer.lua
     -> LuaInventory
     -> связанные хранилища и грузовые вагоны
```

- `circuit_network.lua` читает сигналы и вычисляет условия.
- `train_api.lua` назначает и восстанавливает расписание.
- `cargo_transfer.lua` физически перемещает предметы.

Другие слои не должны размазывать прямые вызовы этих API по проекту.
