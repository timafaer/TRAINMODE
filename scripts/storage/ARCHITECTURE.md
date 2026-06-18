# Storage

```text
control.lua:state()
  -> storage_init.ensure(storage)
  -> storage.trainmode
```

`init.lua` создает сериализуемые таблицы для станций, поездов, депо, запросов,
доставок, резерваций, GUI и состояния scheduler.

Все runtime-модули получают одну и ту же таблицу `storage.trainmode`. Здесь не
должны храниться функции, metatable или временные объекты планировщика.
