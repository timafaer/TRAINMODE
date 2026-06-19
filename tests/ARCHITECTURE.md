# Test Pipeline

```text
lua tests/run.lua
  -> get_ideal_routes_test.lua
  -> planning_test.lua
  -> runtime_services_test.lua
```

- `get_ideal_routes_test.lua` проверяет создание задачи только из готовых ID.
- `planning_test.lua` проверяет комбинаторику, маршруты, лимиты, версии, бюджет
  и частичные планы.
- `runtime_services_test.lua` проверяет storage, запросы, резервации, scheduler
  и перенос груза.
- `test_helper.lua` содержит минимальные assertion-функции.

Factorio API заменяется fake-provider и fake-inventory. Игровой data-stage этими
тестами не запускается.
