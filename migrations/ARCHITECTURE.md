# Migrations

```text
Factorio обнаруживает новую версию мода
  -> выполняет migrations/<version>.lua
  -> дополняет storage.trainmode
  -> on_configuration_changed
  -> bootstrap.rebuild
```

Каждая миграция должна быть идемпотентной и только добавлять/преобразовывать
сериализуемые данные. Удалять игровые сущности из миграции нельзя без отдельного
обоснования.
