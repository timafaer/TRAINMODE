# Dispatcher Layer

## Создание запроса

```text
service.refresh_stations
  -> circuit_network.read_*
  -> circuit_network.evaluate_condition
  -> requests.ensure_for_station
  -> requests.create
```

## Планирование

```text
service.tick
  -> accept_one_result
  -> enqueue_open_request
  -> get_ideal_routes.with_provider
  -> scheduler.step
```

## Назначение

```text
scheduler result
  -> reservations.reserve_routes
  -> train_api.assign_route
  -> delivery.state = active
```

## Завершение

```text
service.poll_deliveries / on_train_changed_state
  -> cargo_transfer.load_stop или unload_route
  -> reservations.release_delivery
  -> train_api.restore_train
  -> requests.apply_delivery
```

- `requests.lua` владеет жизненным циклом запроса.
- `reservations.lua` атомарно учитывает ресурсы, слоты и поезда.
- `service.lua` является orchestration-слоем и не реализует поиск маршрута.
