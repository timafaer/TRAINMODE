# Prototype Layer

Эта папка выполняется только на data-stage Factorio.

```text
data.lua
  -> entities.lua
  -> items.lua
  -> recipes.lua
  -> technologies.lua
```

- `entities.lua` копирует ванильные прототипы и объявляет игровые сущности.
- `items.lua` создает предметы для размещения сущностей.
- `recipes.lua` связывает ресурсы крафта с предметами.
- `technologies.lua` открывает рецепты исследованием.

Runtime-код из `scripts/` не должен вызываться из этого слоя.
