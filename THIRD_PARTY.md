# Сторонние компоненты и лицензии

## Fantasy Map Generator (MIT)

- Источник: https://github.com/Azgaar/Fantasy-Map-Generator
- Версия, взятая за основу порта: 1.152.2
- Лицензия: MIT, © Azgaar (см. https://github.com/Azgaar/Fantasy-Map-Generator/blob/master/LICENSE)

Перенесённые материалы: алгоритмы генерации рельефа, климата, биомов, рек, культур, городов,
государств, религий, провинций, дорог, а также таблицы
(`data/heightmap_templates.json`, `data/name_bases.json`, `data/biomes.json`).
Файлы порта: `src/core/fmg_utils.gd`, `src/core/fmg_random.gd`, `src/core/fmg_quadtree.gd`,
`src/core/fmg_path.gd`, `src/gen/*.gd`.

## Delaunator (ISC)

- Источник: https://github.com/mapbox/delaunator
- Версия: 5.0.1
- Лицензия: ISC, © Mapbox

`src/core/delaunay.gd` — порт триангулятора Delaunator (та же схема хеширования рёбер оболочки,
стек переворота рёбер, сортировка точек по расстоянию от центра описанной окружности). `voronoi.gd`
строит ячейки Вороного по half-edge рёбрам Delaunator так же, как `src/generators/voronoi.ts` в FMG.

## Alea (public domain)

- Источник: https://github.com/jcubic/alea (реализация Johannes Baagøe)
- `src/core/alea.gd` — порт PRNG Alea/Mash, которым FMG делает генерацию детерминированной.

## gdtoolkit (MIT)

Используется только как инструмент разработки (`gdparse`/`gdlint`) для проверки синтаксиса
GDScript-файлов, в поставку не входит.
