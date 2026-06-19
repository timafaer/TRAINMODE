# Diagnostics pipeline

```text
dispatcher / runtime_provider
  -> logger.trace(event_name, data)
     -> runtime setting trainmode-debug-logging
     -> Factorio log()
```

- `logger.lua` формирует однострочные события `TRAINMODE_TRACE`.
- Алгоритмическое ядро вызывает логирование только через `provider.trace`, поэтому
  не зависит от Factorio API.
