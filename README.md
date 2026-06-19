# TRAINMODE

MVP диспетчера умных поездов для Factorio 2.0 Space Age.

## Быстрый запуск

1. Построить `Умную железнодорожную станцию`.
2. Открыть станцию и выбрать режим `load`, `unload` или `depot`.
3. Подключить красный провод источника: положительные предметные сигналы
   трактуются как доступное количество в стаках.
4. Подключить зеленый провод получателя либо задать `manual_requests`.
5. Поставить умный локомотив с грузовыми вагонами на станцию депо.

GUI поддерживает приоритет, режим буферной станции, политику источников, ручные
ресурсы, запросы и условие вида `item:iron-plate < 40` или
`virtual:signal-A > 0`.

Remote-интерфейс также доступен для автоматизации:

```lua
/c remote.call("TRAINMODE", "set_station_config", UNIT, {
  mode = "load",
  priority = 10
})
```

```lua
/c remote.call("TRAINMODE", "set_station_config", UNIT, {
  mode = "unload",
  priority = 5,
  manual_requests = { ["iron-plate"] = 40 }
})
```

```lua
/c remote.call("TRAINMODE", "set_station_config", UNIT, {
  mode = "depot",
  depot_id = 1
})
```

`UNIT` — `unit_number` выбранной станции. Его можно получить командой:

```lua
/c game.player.print(game.player.selected.unit_number)
```

## Структура

- `scripts/routing/` — чистое алгоритмическое ядро.
- `scripts/dispatcher/` — запросы, резервации и runtime-диспетчер.
- `scripts/registry/` — станции, поезда и депо.
- `scripts/integrations/` — границы Factorio API.
- `scripts/storage/` — схема постоянного состояния.
- `prototypes/` — игровые сущности, предметы, рецепты и технология.

В каждой папке находится `ARCHITECTURE.md` с локальным pipeline: какие функции
являются точками входа, кого они вызывают и какие данные передают дальше.

## Работа хранилищ

Умное или временное хранилище автоматически связывается с ближайшей умной
станцией в настраиваемом радиусе. При прибытии поезда мод переносит нужные
предметы между связанными хранилищами и грузовыми вагонами. Если предметов нет
или получатель заполнен, поезд продолжает ждать.

Временное хранилище допускает только один выбранный предмет. Фильтр задается при
открытии хранилища.

## Диагностика

Команда `/trainmode-status` выводит число станций, поездов, депо, запросов и
доставок.

Настройка `trainmode-debug-logging` включает структурированные строки
`TRAINMODE_TRACE` для запросов, стадий планировщика, маршрутов, резерваций,
загрузки, разгрузки и завершения доставки.

## Headless smoke test

Встроенный сценарий `scenarios/smoke` строит минимальную железную дорогу и
проверяет полную доставку 1000 железных плит.

```bash
factorio --mod-directory <mods> --scenario2map TRAINMODE/smoke
factorio --mod-directory <mods> \
  --benchmark <write-data>/saves/TRAINMODE/smoke.zip \
  --benchmark-ticks 3660 --benchmark-runs 1
```

Успешный прогон содержит строку:

```text
TRAINMODE_SMOKE PASS delivered=1000
```

## City-block load test

Сценарии `city-block-load-1`, `city-block-load-2`, `city-block-load-4` и
`city-block-load-8` строят четыре блока поставщиков, три блока получателей и
прогоняют один workload с разным количеством умных поездов.

```bash
factorio --mod-directory <mods> --scenario2map TRAINMODE/city-block-load-8
factorio --mod-directory <mods> \
  --benchmark <write-data>/saves/TRAINMODE/city-block-load-8.zip \
  --benchmark-ticks 20000 --benchmark-runs 1
```

Эталонные результаты и полные логи находятся в
`test-results/city-block-load-test/`.

## Ограничения

- Сигналы задаются в стаках, не в штуках.
- Оценка порядка станций использует расстояние по координатам; реальная
  достижимость проверяется поездом при назначении расписания.
- Модули конвейера используют механику быстрого ванильного манипулятора.
- Для всех новых объектов временно используется один тестовый значок.
