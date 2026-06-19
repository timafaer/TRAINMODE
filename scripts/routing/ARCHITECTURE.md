# Routing Pipeline

## Создание задачи

```text
dispatcher
  -> get_ideal_routes.with_provider(request_id)
  -> готовые ID станций и депо
  -> PlanningJob
```

## Выполнение

```text
scheduler.step(n)
  -> выбирает задачу по phase/priority/created_tick
  -> route_optimizer.step
     -> combinator.step
     -> route_search.step
     -> validation
```

## Стадии

```text
combinatorics
  -> грузовые блоки поездов
  -> минимизация смешивания и уникальных станций
  -> учет ресурсов и лимитов

route_search
  -> обратный порядок станций от получателя
  -> выбор депо, входа и поезда
  -> кеш расстояний

validation
  -> версии сущностей
  -> остатки ресурсов
  -> лимиты
  -> доступность поездов
```

- `route_data_provider.lua` определяет абстрактный контракт данных.
- `runtime_provider.lua` реализует контракт поверх `storage` и Factorio API.
- Алгоритмические файлы не должны напрямую обращаться к `game` или `storage`.
