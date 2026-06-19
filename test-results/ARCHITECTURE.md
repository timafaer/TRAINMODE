# Test results pipeline

```text
Factorio scenario2map
  -> city-block-load-{1,2,4,8}.zip
  -> headless benchmark
     -> city-block-load-N.full.log
     -> filter TRAINMODE_TRACE / TRAINMODE_LOAD_TEST
     -> city-block-load-N.key.log
     -> city-block-load-test-report.md
```

Каталог содержит воспроизводимые результаты headless-прогонов, а не runtime-код
мода.
