# Smoke Scenario

```text
on_init
  -> build_rail_line
  -> create depot/source/target
  -> create storages and train

tick 2
  -> configure stations through remote interface
  -> TRAINMODE.rebuild

every 60 ticks
  -> inspect target storage
  -> PASS when 1000 iron plates arrived
  -> FAIL at tick 3600
```

Тест проверяет регистрацию сущностей, планирование, резервации, расписание,
загрузку, движение поезда, выгрузку и закрытие доставки.
