# Runtime Layer

```text
control.lua
  -> bootstrap.lua
  -> diagnostics/logger.lua
  -> registry/*
  -> gui/*
  -> dispatcher/service.lua

dispatcher/service.lua
  -> integrations/*
  -> routing/*
  -> dispatcher/requests.lua
  -> dispatcher/reservations.lua
```

- `constants.lua` содержит общие имена, состояния и интервалы.
- `bootstrap.lua` перестраивает реестры после загрузки или миграции.
- Остальные подпапки изолируют хранение данных, планирование и Factorio API.

Направление зависимостей: orchestration вызывает доменные модули, доменные
модули не должны вызывать `control.lua`.
