# Scenarios

```text
Factorio --start-server-load-scenario TRAINMODE/smoke
  -> scenarios/smoke/control.lua
  -> строит железную дорогу и сущности
  -> remote.call("TRAINMODE", ...)
  -> ожидает физическую доставку
  -> пишет TRAINMODE_SMOKE PASS/FAIL

Factorio --scenario2map TRAINMODE/city-block-load-N
  -> scenarios/city-block-load-N/control.lua
  -> city-block-load-test/runner.register(N)
  -> строит поставщиков, получателей, депо и N поездов
  -> пишет TRAINMODE_TRACE и TRAINMODE_LOAD_TEST PASS/FAIL
```

Сценарии предназначены только для интеграционных тестов и не вызываются в
обычной игре.
