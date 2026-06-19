# City-block load-test pipeline

```text
scenario control
  -> runner.register(train_count)
     -> build rail, signals, city blocks, stations, storages, depots and trains
     -> configure TRAINMODE through remote interface
     -> wait for three independent multi-resource requests
     -> recycle completed trains into their depot test slots
     -> write periodic status and final PASS/FAIL
```

- `runner.lua` содержит общий параметризованный стенд.
- Сценарии `city-block-load-{1,2,4,8}` задают только количество поездов.
- Пересоздание состава после доставки заменяет разворотную петлю тестового
  полигона; сама доставка от депо до получателя остаётся физической.
