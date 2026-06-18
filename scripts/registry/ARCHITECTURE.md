# Registry Layer

## Событийный поток

```text
control.on_built / bootstrap.rebuild
  -> stations.register
  -> trains.refresh
  -> storages.register
  -> depots.rebuild
  -> storages.relink
```

## Файлы

- `stations.lua`: регистрация, удаление и конфигурация умных станций.
- `trains.lua`: обнаружение умных локомотивов, вместимость и проверка пустоты.
- `depots.lua`: группировка depot-станций и стоящих на них поездов.
- `storages.lua`: регистрация складов, выбор ближайшей станции и фильтр
  временного хранилища.

Registry изменяет только постоянное состояние. План маршрута здесь не строится.
