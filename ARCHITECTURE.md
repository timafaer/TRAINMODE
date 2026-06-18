# Пайплайн проекта

## Точки входа

```text
settings.lua
  -> объявляет runtime-настройки

data.lua
  -> prototypes/entities.lua
  -> prototypes/items.lua
  -> prototypes/recipes.lua
  -> prototypes/technologies.lua

control.lua
  -> регистрирует события Factorio
  -> вызывает registry, dispatcher, GUI и bootstrap
```

## Основной runtime-поток

```text
событие Factorio
  -> control.lua
  -> registry/* обновляет storage
  -> dispatcher/service.lua
  -> routing/get_ideal_routes.lua
  -> routing/scheduler.lua
  -> routing/route_optimizer.lua
  -> combinator.lua
  -> route_search.lua
  -> validation
  -> dispatcher/reservations.lua
  -> integrations/train_api.lua
  -> реальный LuaTrain
```

## Доставка

```text
станция-источник, красный провод
  -> circuit_network.read_red_items
  -> station.available_resources
  -> комбинаторика
  -> маршрут и резервации
  -> train_api.assign_route
  -> cargo_transfer.load_stop
  -> cargo_transfer.unload_route
  -> requests.apply_delivery
```

Подробности каждого слоя находятся в `ARCHITECTURE.md` соответствующей папки.
