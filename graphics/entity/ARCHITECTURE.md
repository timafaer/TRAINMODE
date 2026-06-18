# Entity Graphics

Каталог зарезервирован для будущих спрайтов сущностей.

Сейчас pipeline использует ванильную графику скопированных прототипов:

```text
data.raw vanilla entity
  -> table.deepcopy
  -> TRAINMODE prototype
```

Будущие sprite definitions подключаются только через `prototypes/entities.lua`.
