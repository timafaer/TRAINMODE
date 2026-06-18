# Planning

Каталог зарезервирован. Текущий pipeline планирования находится в
`scripts/routing/`.

Если появятся альтернативные стратегии:

```text
dispatcher
  -> planning strategy selector
  -> routing scheduler
  -> выбранный optimizer
```

До появления нескольких стратегий переносить сюда существующее ядро не нужно.
