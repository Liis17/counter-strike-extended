# de_dust2 — исходник карты

Parent: [[cse-structure]]

## Файлы

- `src/cse/maps/de_dust2.map` — source-only `.map`, полученный из `runtime/cstrike/maps/de_dust2.bsp`.
- `src/cse/maps/de_dust2_generated.wad` — WAD3 с 15 текстурами, которые были встроены в BSP и отсутствовали в исходных WAD.

Исходный BSP в `runtime/` не изменён. `de_dust2` намеренно отсутствует в
`src/cse/maps/build-list.txt`, поэтому её исходник и WAD не компилируются и не
устанавливаются автоматически.

## Декомпиляция

Использован Half-Life Unified SDK Map Decompiler 1.0.0.0, стратегия `Tree`:

- `--apply-null`
- `--generate-origin-brushes`
- `--merge-brushes`
- `--brush-optimization BestTextureMatch`
- wildcard `trigger_*` для `AAATRIGGER`

Результат: 1667 map-brushes, 30 clip-brushes и 101 entity.

## Ограничения

GoldSrc BSP не хранит исходные brush-примитивы, поэтому декомпиляция приблизительная: геометрию,
clip/NULL-грани, освещение и отдельные entity нужно проверить и при необходимости восстановить
в Hammer или J.A.C.K. Перед публикацией изменённой карты её следует скомпилировать во внешний BSP
и протестировать отдельно, не перезаписывая штатный `de_dust2.bsp`.

В worldspawn прописаны относительные пути к WAD из `runtime/` и к `de_dust2_generated.wad` рядом
с исходником.
