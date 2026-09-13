# Порт генератора карт Fantasy Map Generator в Godot 4.7

Документ описывает, как генерация карт из [Azgaar/Fantasy-Map-Generator](https://github.com/Azgaar/Fantasy-Map-Generator)
(далее FMG) перенесена в этот проект: что именно портировано, как это устроено, чем отличается от
оригинала и как проверялось.

## 1. Что портировано

Порядок стадий повторяет `src/generators/generation-pipeline.ts`:

```
сетка → рельеф → берега/озёра → координаты → температура → осадки → упакованный граф →
реки → биомы → население → культуры → города → государства → дороги → религии →
провинции → детали (льды, товары, зоны, маркеры, формы правления)
```

| FMG (TypeScript) | Наш порт (GDScript) |
| --- | --- |
| `src/generators/grid-generator.ts`, `voronoi.ts` | `src/gen/gen_grid.gd`, `src/core/voronoi.gd` |
| `src/generators/heightmap-generator.ts` | `src/gen/gen_heightmap.gd` |
| `src/generators/features.ts` (разметка сетки и графа) | `src/gen/gen_features.gd` |
| `src/generators/coordinates.ts` | `src/gen/gen_coordinates.gd` |
| `src/generators/temperature-generator.ts`, `precipitation-generator.ts` | `src/gen/gen_climate.gd` |
| `src/generators/pack-generator.ts` | `src/gen/gen_pack.gd` |
| `src/generators/river-generator.ts` | `src/gen/gen_rivers.gd` |
| `src/generators/lakes.ts` | `src/gen/gen_lakes.gd` |
| `src/generators/biomes-generator.ts` | `src/gen/gen_biomes.gd` |
| `src/generators/population-generator.ts` (rankCells + население городов) | `src/gen/gen_population.gd` |
| `src/generators/cultures-generator.ts` | `src/gen/gen_cultures.gd` |
| `src/generators/burgs-generator.ts` (капиталы, города, порты) | `src/gen/gen_burgs.gd` |
| `src/generators/states-generator.ts` | `src/gen/gen_states.gd` |
| `src/generators/routes-generator.ts` (граф Уркварта + морские пути) | `src/gen/gen_routes.gd` |
| `src/generators/religions-generator.ts`, `provinces-generator.ts` | `src/gen/gen_religions.gd` |
| `src/generators/names-generator.ts` + `src/data/name-bases.ts` | `src/gen/gen_names.gd` + `data/name_bases.json` |
| `src/generators/ice-generator.ts`, `markers-generator.ts`, `zones-generator.ts`, `goods-generator.ts` | `src/gen/gen_extras.gd` |
| `src/generators/generation-pipeline.ts` | `src/gen/gen_pipeline.gd` |
| `src/generators/options.ts` (часть настроек) | `src/gen/gen_options.gd` |
| `src/utils/numberUtils.ts`, `probabilityUtils.ts`, `languageUtils.ts`, `colorUtils.ts` | `src/core/fmg_utils.gd`, `src/core/fmg_random.gd` |
| `alea` (PRNG) | `src/core/alea.gd` |
| `delaunator` (триангуляция) | `src/core/delaunay.gd` |
| `d3.quadtree`, `utils/pathUtils.ts` | `src/core/fmg_quadtree.gd`, `src/core/fmg_path.gd` |

Точки входа:

* `src/gen/gen_pipeline.gd` — весь конвейер (`GenPipeline.generate_map(map)` или постадийно
  `GenPipeline.run_stage(map, "grid")`).
* `src/view/world_map.gd` + `world_map.tscn` — экран генерации: сид, прогресс, слои карты
  (природа / государства / религии / зоны), реки, города, названия, зум и панорама.
  Открывается из мини-карты клавишей **M** или кнопкой «КАРТА МИРА».
* `tests/test_generation.gd` — автотест инвариантов: `godot --headless --path . --script res://tests/test_generation.gd`.

## 2. Архитектура

* **Один объект вместо глобалов.** В FMG генерация общается через глобальные `options`, `grid`,
  `pack`, `window.Biomes` и т.п. Здесь всё живёт в `MapData` (`src/model/map_data.gd`):
  `options` (словарь настроек), `grid` (высокодетальный граф), `pack` (граф карты), `biomes`,
  кеши поиска (`find_grid_cell`, `find_pack_cell`, полигоны). Генераторы — статические классы с
  сигнатурой `generate(map: MapData)`, поэтому карту можно сгенерировать для нескольких миров
  внутри одной сцены.
* **Детерминизм.** Как и в FMG, каждый этап пересеивает PRNG (`FmgRandom.seed_with`) значением
  `map.seed_text`; `alea.gd` — прямой порт генератора Alea (включая `Mash`-хеширование сида),
  поэтому одинаковый сид даёт одинаковую карту. Тест проверяет это явно.
* **Числа как в оригинале.** Сохранены «магические» константы FMG: `SEA_LEVEL = 20`, пороги
  flux/ширины рек, матрица биомов, стоимости экспансии культур и государств, формула осадков и
  температур (включая экспоненту высоты `1.8`).
* **Массивы.** `Uint8Array`/`Uint16Array` → `PackedByteArray`/`PackedInt32Array`.
  Важно: в GDScript упакованные массивы — значимые типы, поэтому изменённые копии записываются
  назад в словарь графа (`cells["h"] = h` и т.п.).
* **Данные вместо кода.** Таблицы, которые в FMG лежат в `.ts`, вынесены в JSON и читаются через
  `FmgUtils.load_json_array`: `data/heightmap_templates.json`, `data/name_bases.json`,
  `data/biomes.json`. Перегенерировать: `python3 tools/extract_fmg_data.py /path/to/FMG`.
* **Триангуляция.** `src/core/delaunay.gd` — порт Delaunator: те же хеш-таблицы рёбер, обход
  выпуклой оболочки, стек переворота рёбер и сортировка точек по расстоянию от центра описанной
  окружности, поэтому результат совпадает с библиотекой, на которой построена карта в FMG.
  `voronoi.gd` собирает ячейки и вершины по half-edge рёбрам, как `generators/voronoi.ts`.

## 3. Упрощения относительно веб-приложения

Портирована генерация карты, но не редактор. Осознанные упрощения:

* Меандрирование рек: путь реки — полилиния по центрам ячеек (в FMG добавляется сплайн
  Catmull–Rom), эрозия не реализована.
* `GenExtras` (льды, товары, зоны, маркеры, формы правления) переносит данные, нужные отрисовке и
  игровым системам, но без полного набора из редактора (геральдика, заметки, экономика городов,
  рынки, производство, налоги, военные кампании, путешествия и т.п.).
* Культуры и государства используют наши наборы культур (`CULTURE_SETS`) и имена из `data/name_bases.json`
  вместо «европейских» предустановок FMG; при этом все формулы выбора центров, типов и стоимостей
  роста сохранены.
* `GenOptions` содержит только генеративные настройки (карта, климат, культуры, государства, города).

## 4. Как проверялось

* Синтаксис и стиль всех `.gd`: `gdparse` + `gdlint` (gdtoolkit), конфигурация — `gdlintrc`.
* Алгоритмы, критичные для качества карты, проверялись прототипами на Node в песочнице:
  * Delaunay/Voronoi: совпадение набора рёбер и оболочек с `delaunator@5.0.1`, а также совпадение
    ячеек (соседство и вершины) на реальных точках FMG (до 10 000 точек, `missingCells = missingAdj =
    extraAdj = badPolys = 0`);
  * PRNG: значения `alea` совпадают с npm-пакетом `alea` для набора сидов;
  * разбор таблиц из FMG: `tools/extract_fmg_data.py`.
* В песочнице нет исполняемого Godot, поэтому автотест `tests/test_generation.gd` нужно запустить
  локально (`godot --headless --path . --script res://tests/test_generation.gd`); в нём — проверка
  инвариантов графа, климата, биомов, культур, городов, государств, дорог и детерминизма по сиду.

## 5. Лицензии и атрибуция

* Fantasy Map Generator — MIT, © Azgaar. Все перенесённые формулы, таблицы и структуры данных
  сохраняют эту лицензию; см. `THIRD_PARTY.md`.
* Delaunator — ISC, © Mapbox: `src/core/delaunay.gd` является портом алгоритма.
* Данные `data/*.json` извлечены из исходников FMG скриптом `tools/extract_fmg_data.py`.
