# ECharts 6.1.0 — The data model, `dataset`, and the data-processing pipeline

Research pass for a native (Free Pascal / Lazarus / BGRABitmap) custom-drawn chart control.
Everything below was read out of `D:/Projects/echarts` (TS source) and `D:/Projects/echarts-doc`
(official option reference). Line references are to the 6.1.0 tree.

Files that define this subsystem:

| File | Role |
|---|---|
| `src/data/Source.ts` | Immutable description of *raw* user data: format, header offset, dimension defs |
| `src/data/helper/dataProvider.ts` | Format-specific readers (`getItem`/`count`/`appendData`) over a `Source` |
| `src/data/DataStore.ts` | The actual **columnar** store (typed arrays), plus all bulk operations |
| `src/data/SeriesData.ts` | Per-series view over a store: names, ids, visuals, layouts, graphic els |
| `src/data/SeriesDimensionDefine.ts` | One dimension's metadata (`coordDim`, `otherDims`, `storeDimIndex`, type) |
| `src/data/OrdinalMeta.ts` | Category ↔ integer interning table |
| `src/data/helper/createDimensions.ts` | Resolves *coordSys needs* × *user `encode`/`dimensions`* × *data shape* |
| `src/data/helper/SeriesDataSchema.ts` | Store-sharing hash + high-dimension omission |
| `src/data/helper/sourceHelper.ts` | Default-encode strategies, `guessOrdinal` |
| `src/data/helper/sourceManager.ts` | dataset↔dataset↔series dependency graph, transform driving, store cache |
| `src/data/helper/transform.ts` | External transform registry + `ExternalSource` sandbox |
| `src/component/transform/{filter,sort}Transform.ts` | The two built-in transforms |
| `src/util/conditionalExpression.ts` | The filter condition DSL |
| `src/data/helper/dataValueHelper.ts` | Value parsing, comparators, sort rules, extent sanitization |
| `src/data/DataDiffer.ts` | Old↔new data matching for animation |
| `src/processor/{dataFilter,negativeDataFilter,dataSample,dataStack}.ts` | Registered pipeline stages |
| `src/core/Scheduler.ts` | Task pipeline, progressive chunking |

---

## 1. Architecture: four layers, not one

```
user option  ──► Source ──► DataProvider ──► DataStore ──► SeriesData ──► view
 (raw JS)      (metadata)   (format reader)  (columns)    (per-series)
```

- **`Source`** (immutable) holds `data` (the user's array/object *by reference*, never copied),
  `sourceFormat`, `seriesLayoutBy`, `dimensionsDefine`, `startIndex` (header row count),
  `dimensionsDetectedCount`, and `metaRawOption` (the raw `dimensions`/`sourceHeader`/`seriesLayoutBy`).
- **`DataProvider`** is a set of closures bound to `(sourceFormat, seriesLayoutBy)` that know how to
  `count()` and `getItem(idx)` on that raw shape. Providers advertise two flags:
  `pure` (all values primitive → no per-item option objects) and `persistent` (raw data survives; false
  for typed arrays, which are consumed and released via `clean()`).
- **`DataStore`** parses each raw item once, column by column, into per-dimension chunks. Immutable by
  convention: `filter`/`selectRange`/`map`/`downSample` all **clone** and return a new store.
- **`SeriesData`** is the object every series/view talks to. It owns dimension *names*, `_nameList`,
  `_idList`, per-item visual/layout/graphic-element side tables, and delegates all value access to the store.

### Why columnar

`DataStore._chunks[dimIdx][rawIdx]` — one flat array per dimension, not one object/array per datum.
Consequences that matter for a port:

- A dimension declared `float`/`time` is a `Float64Array`; `int` is `Int32Array`; `ordinal`/`number`
  stay plain `Array` (ordinal values are interned integers but the array may hold strings pre-interning).
- Index vectors are `Uint16Array` when `rawCount <= 65535`, else `Uint32Array`
  (`getIndicesCtor`, `DataStore.ts`).
- Filtering never moves values. It builds a new `_indices` vector of *raw* indices and swaps
  `getRawIndex` between an identity function and an indirection function (`_updateGetRawIdx`).
  So `count()` (filtered) and `_rawCount` (unfiltered) diverge.
- `clone(clonedDims?)` copies **only the named columns** and shares the rest by reference. Down-sampling
  clones only the value dimension.
- Extents are cached per `(dimension, sanitizationFilterKey)` in `_extent`, and a *raw* extent
  (`_rawExtent`) is maintained incrementally during the initial fill so that the unfiltered case
  is O(1).

### `getRawIndex` / `indexOfRawIndex`

`getRawIndex(i)` maps a *current* (post-filter, post-sample) index to the original row index.
`indexOfRawIndex(raw)` inverts it — it first guesses identity, then falls back to **binary search**
over the ascending `_indices` vector. This is the identity used by tooltip/highlight round-trips.

---

## 2. Dimension types (5)

`dataCtors` in `DataStore.ts`:

| `type` | Backing store | Parse rule (`parseDataValue`) |
|---|---|---|
| `'float'` (default) | `Float64Array` | `null`/`''` → `NaN`; otherwise `Number(value)` (so `'-'`, objects → `NaN`) |
| `'int'` | `Int32Array` | same numeric parse, truncated by the typed array |
| `'number'` | plain `Array` | same numeric parse, no typed-array coercion |
| `'ordinal'` | plain `Array` | value passed through **verbatim**, then interned by `OrdinalMeta` |
| `'time'` | `Float64Array` | if not already a number and not `null`/`'-'`: `+parseDate(value)` → epoch ms |

Type is chosen by: explicit `dimensions[i].type` > coordinate-system axis type
(`getDimensionTypeByAxis`: `category`→`ordinal`, `time`→`time`, else `float`) > `guessOrdinal` sniffing.

### `guessOrdinal` (`sourceHelper.ts`)

Returns one of three verdicts, sampling at most **5** rows:

| Verdict | Meaning |
|---|---|
| `BE_ORDINAL.Must` (1) | Saw a string that is not `'-'` and not numeric-like → definitely categorical |
| `BE_ORDINAL.Might` (2) | Saw a *numeric string* (`'12'`) → ambiguous |
| `BE_ORDINAL.Not` (3) | Everything numeric / typed array / declared type |

Also: a dimension that is an "extra coord" and is encoded as `itemName`/`seriesName` is forced to
`ordinal` even if `guessOrdinal` says otherwise (handles `[['2001', 123], ['The others', 987]]` for pie).

### `OrdinalMeta` — category interning

- `categories: OrdinalRawValue[]` plus a lazily built hash map (never built until a lookup is needed —
  a deliberate large-data optimization).
- `parseAndCollect(category)`: if `needCollect && !deduplication`, blindly append and return the new index
  (O(1), no map). Otherwise look up; if `needCollect`, append and register; else return `NaN`.
- Constructed from an axis: `categories = axis.data.map(getName)`, `needCollect = !categories`,
  `deduplication = option.deduplication !== false`.
- `DataStore.collectOrdinalMeta(dimIdx, meta)` rewrites the whole column *in place* from raw values to
  ordinal integers, resets the raw extent, and forces `dim.type = 'ordinal'`. It tracks `ordinalOffset`
  so `appendData` only interns the new tail.
- **Inverted index**: a dimension with `createInvertedIndices` gets an `Int32Array` of length
  `categories.length` mapping ordinal → data index (`INDEX_NOT_FOUND` = -1 sentinel). Used by
  stack-by-value to avoid a hash lookup per datum.

---

## 3. `series.data` — accepted shapes

`sourceFormat: 'original'` is the format used for `series.data` (as opposed to `dataset.source`).
The `original` dim-value getter is:

```
value = dataItem && (dataItem.value == null ? dataItem : dataItem.value)
result = Array.isArray(value) ? value[dimIndex] : value
```

So all of these are legal in one array:

| Shape | Meaning |
|---|---|
| `12` | Scalar. On a category axis the *index* supplies the other coordinate (see below) |
| `[x, y]` | Tuple; position → dimension index |
| `[x, y, z, …]` | Extra dims available to `visualMap`, `symbolSize` callbacks, tooltip, label |
| `{ value: 12 }` | Object with scalar value |
| `{ value: [x, y] }` | Object with tuple value |
| `{ name, id, groupId, childGroupId, value, selected, … }` | Identity + per-datum overrides |
| `'-'`, `null`, `undefined`, `NaN` | **No data** — all parse to `NaN` |

Per-datum override keys recognised on a data-item object (via `data.getItemModel(idx)`, which wraps the
raw item in a `Model` whose parent is the series model — so *any* series-level style key can be overridden
per datum): `itemStyle`, `lineStyle`, `areaStyle`, `label`, `labelLine`, `emphasis`, `blur`, `select`,
`symbol`, `symbolSize`, `symbolRotate`, `symbolOffset`, `symbolKeepAspect`, `tooltip`, `cursor`, `selected`,
plus series-specific ones (`fromName`/`toName`/`coord` for `lines`, `children` for tree/treemap/sunburst,
`source`/`target` for graph & sankey links, `xAxis`/`yAxis`/`type`/`valueIndex` for markers).

`SeriesData.hasItemOption` is set to `true` the first time a non-array object is seen; it gates the
(expensive) per-item model path. Providers report `pure: true` for every format except `original`,
which lets the store skip the object scan entirely.

### The scalar-on-category-axis completion

`createSeriesData` installs a custom `dimValueGetter` when (a) a category axis exists and (b) the first
non-null data item's value is **not** an array. That getter returns `dataIndex` for the category dimension:

```
xAxis: { data: ['a','b','c'] }, series: { data: [555, 666, 777] }
    →  effectively  [[0,555],[1,666],[2,777]]
```

### Per-series interpretation of tuple positions

Dimensions come from the coordinate system (`coordSysDimDefs`) unless the series overrides them:

| Series | Dimensions in order | Source |
|---|---|---|
| `line`, `bar`, `scatter`, `effectScatter`, `heatmap`, `pictorialBar`, `custom` | coordSys dims (`x,y` / `radius,angle` / `lng,lat` / `single`), then generated `value`, `value0`, … | `createSeriesData` |
| `heatmap` | coordSys dims + `generateCoord: 'value'` (3rd dim is the heat value) | `HeatmapSeries.ts:95` |
| `candlestick` | `base` + `open`, `close`, `lowest`, `highest` (all `defaultTooltip: true`) | `CandlestickSeries.ts:99` |
| `boxplot` | `base` + `min`, `Q1`, `median`, `Q3`, `max` | `BoxplotSeries.ts:96` |
| `pie`, `funnel` | single `value` dim; name from `encode.itemName` via `makeSeriesEncodeForNameBased` | `PieSeries.ts:181` |
| `gauge` | single `value` dim | `GaugeSeries.ts:199` |
| `radar` | `generateCoord: 'indicator_'`, `generateCoordCount: Infinity` — one dim per indicator | `RadarSeries.ts:99` |
| `themeRiver` | `coordDimensions: ['single']`, dims `time` (axis type), `value` (float), `name` (ordinal) | `ThemeRiverSeries.ts:190` |
| `parallel` | one dim per parallel axis, via a custom encode defaulter | `ParallelSeries.ts:103` |
| `lines` | a single `value` dim; the *geometry* lives outside the store as `coords`, optionally flattened into `flatCoords: Float64Array` + `flatCoordsOffset: Uint32Array` when `polyline`/`large` | `LinesSeries.ts:306` |
| `graph`, `sankey`, `chord` | **two** `SeriesData`s (`node` + `edge`) linked by a `Graph` (`src/data/Graph.ts`) | `linkSeriesData.ts` |
| `tree`, `treemap`, `sunburst` | one `SeriesData` plus a `Tree` of `TreeNode` (`dataIndex`, `children`, `viewChildren`) | `src/data/Tree.ts` |
| `map` | `value` dim keyed by region `name` | `MapSeries.ts:134` |

`linkSeriesData` proxies `TRANSFERABLE_METHODS` (`cloneShallow`, `map`, all three down-samplers) and
`CHANGABLE_METHODS` (`filterSelf`, `selectRange`) so an operation on node data keeps edge data consistent.

---

## 4. `dataset`

`DatasetModel` (`src/component/dataset/install.ts`) is a component with essentially no view. Options:

| Option | Type | Semantics |
|---|---|---|
| `source` | 2D array / object array / keyed columns / typed array | The table |
| `dimensions` | `(string \| {name,type,displayName})[]` | Explicit dimension defs; wins over detection |
| `sourceHeader` | `boolean \| 'auto' \| number` | Header row/column count |
| `seriesLayoutBy` | `'column'` (default) \| `'row'` | Is a dimension a column or a row? |
| `transform` | `TransformOption \| TransformOption[]` | Derive this dataset from an upstream one |
| `fromDatasetIndex` / `fromDatasetId` | number / string | Which upstream dataset (default index 0) |
| `fromTransformResult` | number | Which of a multi-output transform's results (default 0) |
| `id`, `name` | | Referencing |

Series-side: `datasetIndex` (default 0), `datasetId`, plus series-local `dimensions`, `sourceHeader`,
`seriesLayoutBy`, `encode`. **A series uses a dataset only if `series.data` is absent** —
`querySeriesUpstreamDatasetModel` returns nothing as soon as `series.get('data')` is truthy.

### The 6 `sourceFormat`s (`detectSourceFormat`)

| Format | Detected when | Example |
|---|---|---|
| `'arrayRows'` | top-level array whose first non-null item is an array (also: empty array) | `[['p','2015'],['Latte',43.3]]` |
| `'objectRows'` | top-level array whose first non-null item is a non-array object | `[{product:'Latte', score:89.3}]` |
| `'keyedColumns'` | plain object whose values are array-likes | `{product:[…], count:[…]}` |
| `'typedArray'` | `isTypedArray(data)` | `new Float32Array(…)` — `dimensions` is **mandatory** |
| `'original'` | `series.data` (never `dataset.source`) | `[12, {value:[1,2], itemStyle:{}}]` |
| `'unknown'` | fallback | |

### Header detection (`determineSourceDimensions`, `arrayRows` only)

- `sourceHeader: number n` → `startIndex = n` (first `n` rows/cols are header).
- `true` → 1, `false` → 0.
- `'auto'`/absent → scan the first row (or first column when `seriesLayoutBy:'row'`), **max 10 cells**:
  any non-`null`, non-`'-'` cell that is a **string** tentatively sets `startIndex = 1`; any non-string
  cell sets `startIndex = 0` unconditionally. Net effect: a header is inferred only when *every*
  inspected non-empty cell is a non-numeric string.
- If a header is inferred and no `dimensions` given, the header row/column becomes `dimensionsDefine`
  (traversed with no 10-cell cap).

Dimension name normalization (`normalizeDimensionsOption`): strings become `{name}`; `displayName`
defaults to `name`; **duplicate names get suffixed** `name-1`, `name-2`, …; names are coerced to strings.
(Note the *other* de-duplication, in `createDimensions` via `removeDuplicates`, suffixes with `0`,`1`,….)

For `objectRows`, dimensions are the **union of keys across all rows**, in first-seen order.
For `keyedColumns`, dimensions are the object's own keys in insertion order.
For `original`, only `dimensionsDetectedCount` is derived (`value0.length || 1`).

### Multiple datasets & the dependency graph

`SourceManager` (one per dataset model and per series model) resolves upstreams lazily:

- A **series**' upstream is its `datasetIndex`/`datasetId` dataset (or none).
- A **dataset**'s upstream is its `fromDatasetIndex`/`fromDatasetId` — but only if it declares
  `transform` or `fromTransformResult`; otherwise it is a root dataset.
- Dirtiness propagates by a `uid + '_' + versionCounter` sign compared recursively, so transforms are
  not re-run on `setOption` calls that do not touch the data.
- **Store sharing**: `getSharedDataStore(schema)` hashes
  `seriesLayoutBy $$ startIndex $$ (property|index, typeShortCode, ordinalMetaUid)*` and caches one
  `DataStore` per hash *on the dataset's* manager, so N series over one dataset parse the table once.

### Default dimension→series mapping (when no `encode`)

`makeSeriesEncodeForAxisCoordSys` — only applied when a dataset is in use:

- **"category way"** — at least one coord dimension has `type: 'ordinal'`: dimension **0** is bound to
  that category axis and *shared by every series*; each series then consumes one further dimension for
  its value axis, walking a per-dataset cursor (`categoryWayDim`).
  Layout: `| shared_x | ser0_y | ser1_y | ser2_y |`
- **"value way"** — no category axis: each series consumes `coordSysDims.length` consecutive dimensions.
  Layout: `| ser0_x | ser0_y | ser1_x | ser1_y |`
- `encode.itemName` is set to the shared category dim (category way); `encode.seriesName` to the series'
  own value dims.

`makeSeriesEncodeForNameBased` (pie, funnel) — inspects at most **5** dimensions with `guessOrdinal`:
picks the first purely-numeric dimension as `value`, and a "name" dimension preferring
`Must|Might` ordinal > any other dim > the value dim itself. A dimension literally named `'name'`
(objectRows/keyedColumns only) always wins as the name dim.

---

## 5. `encode` — the full surface

`encode` maps *coordinate/visual roles* → *dimension indices or names*. Values may be a single
index/name or an array. `-1` (as a single value) means **explicitly unmapped** — used by `custom` series
to opt out of an axis (the series then does not contribute to that axis' extent and is not filtered by
that axis' `dataZoom`).

### Coordinate roles (become `coordDim` + `coordDimIndex`)

| Role | Coordinate system |
|---|---|
| `x`, `y` | cartesian2d (grid) |
| `radius`, `angle` | polar |
| `lng`, `lat` | geo |
| `single` | singleAxis |
| `value` | no coordinate system (pie, funnel, gauge, treemap, …) |
| arbitrary names | whatever `coordSys.dimensions` declares (parallel: one per axis; radar: `indicator_0…`) |

### Visual / non-coordinate roles (`VISUAL_DIMENSIONS`, 7 of them)

`src/util/types.ts:705`: `tooltip`, `label`, `itemName`, `itemId`, `itemGroupId`, `itemChildGroupId`,
`seriesName`. These land in `SeriesDimensionDefine.otherDims` as `{role: coordDimIndex}`.

| Role | Effect |
|---|---|
| `tooltip` | Which dimensions the default tooltip lists (`false` suppresses one) |
| `label` | Which dimensions feed the default label content |
| `itemName` | Datum name → `SeriesData.getName`, legend items for pie/funnel, default label/tooltip name |
| `itemId` | Datum id → `SeriesData.getId`, the key for `DataDiffer` |
| `itemGroupId` | `universalTransition` matching key |
| `itemChildGroupId` | `universalTransition` drill-down child key (since 5.5.0) |
| `seriesName` | Auto-derived series name from dimension name(s) |

`summarizeDimensions` (`dimensionHelper.ts`) folds all of this into a `DimensionSummary`:
`encode[coordDim] = [dimName…]`, `defaultedLabel` (the last non-extra coord dim whose type is neither
`ordinal` nor `time`), `defaultedTooltip`, `dataDimsOnCoord` / `dataDimIndicesOnCoord`
(used by `hasValue(idx)` — a datum is "present" only if every on-coord dimension is non-NaN), and
`userOutput` (what callbacks see).

### `dimensions`

Array of `string | null | {name, type, displayName}`. `null` = "don't name this one".
Declarable on `dataset` **and** on `series` (series wins). Types: `number | float | int | ordinal | time`.
Naming a dimension also switches the default tooltip to a **vertical** name:value listing.

### `seriesLayoutBy`

`'column'` (default) — a dimension is a column, a datum is a row.
`'row'` — a dimension is a row, a datum is a column. Only meaningful for `arrayRows`.
Note: `appendData` throws for `arrayRows` + `seriesLayoutBy: 'row'`, and **data transforms only accept
`'column'`** (they hard-error otherwise, `transform.ts`).

---

## 6. Data transforms

### Mechanism

`dataset.transform` is a declarative function application `outSources = f(inSources, config)`.
`applyDataTransform` normalizes to an array (pipe), then for each stage:

1. Wraps every upstream `Source` in an **`ExternalSource`** — a deliberately narrow sandbox exposing
   `sourceFormat`, `count()`, `retrieveValue(dataIndex, dimIndex)`, `retrieveValueFromItem(item, dimIndex)`,
   `getDimensionInfo(dimNameOrIndex)`, `cloneAllDimensionInfo()`, `cloneRawData()`, `convertValue()`.
   `getRawData()`/`getRawDataItem()` are **only available to built-in transforms** (`__isBuiltIn`), which
   is how `filter`/`sort`/`boxplot` avoid copying.
2. Calls `transform({upstream, upstreamList, config})`, expecting
   `{data, dimensions?} | Array<{data, dimensions?}>`. Result `data` must be `arrayRows` or `objectRows`.
3. **[DIMENSION_INHERIT_RULE]**: if the transform returns no `dimensions` and this is result index 0,
   the upstream's header rows are *prepended back* onto the result and the upstream `dimensions` are
   inherited. If it does return `dimensions`, nothing is inherited.
4. Piping: results are chained; only the first stage may take multiple inputs, only the last may emit
   multiple outputs.

`registerTransform` requires a namespaced `type` (`'ns:name'`). The namespace `'echarts'` is stripped and
marks the transform built-in — hence `type: 'filter'` vs `type: 'ecStat:regression'`.

`transform.print: true` (dev builds only) `console.log`s the resulting data and dimensions per stage —
a pure debugging affordance, browser-console-bound.

### Built-in `filter`

`config` is a **conditional expression** (`src/util/conditionalExpression.ts`). Grammar:

```
Conditional := true | false | Relational | Logical
Logical     := { and: Conditional[] } | { or: Conditional[] } | { not: Conditional }
Relational  := { dimension: name|index, parser?: 'time'|'trim'|'number', <op>: value, … }
```

Relational operators (all aliases resolve to 6 canonical ops + `reg`):

| Canonical | Aliases | Rule |
|---|---|---|
| `lt` | `<` | right value **must be a number**; left coerced via `numericToNumber` |
| `lte` | `<=` | idem |
| `gt` | `>` | idem |
| `gte` | `>=` | idem |
| `eq` | `=`, `value` | `===` if same type; if either side is a number, compare numerically; else false |
| `ne` | `!=`, `<>` | `!eq` |
| `reg` | — | `RegExp` or serializable pattern string; tests strings and stringified numbers |

Semantics worth copying exactly:

- **Multiple operators in one object are ANDed**: `{dimension:'Price', '>=':20, '<':30}`.
- **[EMPTY_RULE]**: a relational op whose value is `null`/`undefined` evaluates **false** (not "match all").
  A relational object with *no* operator throws. An empty `and: []`/`or: []` throws.
  Use literal `true`/`false` for constant conditions.
- **Fail-fast**: the filter never returns the whole upstream when the condition is malformed.
- `parser` (applied to the *left* value before comparison):
  `'number'` = loose `parseFloat` (so `'120px'`→120, `'14%'`→14);
  `'time'` = `+parseDate(v)` (Date instance, epoch ms, or ISO-ish string);
  `'trim'` = trim if string.
- Default (no parser) numeric coercion is `numericToNumber`, which is *strict*: it deliberately rejects
  the JS traps `null <= 0`, `[] <= 0`, `' ' <= 0`.

### Built-in `sort`

`config` = `{dimension, order:'asc'|'desc', parser?, incomparable?:'min'|'max'}` or an **array** of those
(multi-key: keys applied in order until a non-zero comparison).

**[SORT_COMPARISON_RULE]** — three value classes:

| left vs right | result |
|---|---|
| numeric vs numeric (incl. numeric strings) | numeric order — so `'2' < '12'`, *not* lexical |
| non-numeric-string vs non-numeric-string | JS relational string order |
| anything vs "others" (null/NaN/object) | the other side is **incomparable** |
| numeric vs non-numeric-string | the string is **incomparable** |

"Incomparable" is substituted with `-Infinity` (`incomparable: 'min'`) or `+Infinity`
(`incomparable: 'max'`). Default: `'max'` for `asc`, `'min'` for `desc` — i.e. empties go to the tail.
Only `arrayRows`/`objectRows` upstreams are supported. The sort is JS `Array.sort` (unstable in spec,
stable in practice on modern engines) over materialized raw items.

### Built-in `boxplot` transform

`type: 'boxplot'`, `config: {boundIQR?: number|'none', itemNameFormatter?: string|fn}`.
Input must be `arrayRows` (`number[][]`, one row per box). It emits **two** results:

- result 0: `dimensions: ['ItemName','Low','Q1','Q2','Q3','High']`, rows `[name, low, Q1, Q2, Q3, high]`
- result 1: outliers, rows `[name, value]`

Algorithm (`prepareBoxplotData.ts`): sort ascending; `Q1/Q2/Q3 = quantile(.25/.5/.75)`;
`bound = (boundIQR ?? 1.5) * (Q3 - Q1)`; `low = max(min, Q1 - bound)`, `high = min(max, Q3 + bound)`;
`boundIQR === 'none' || 0` → use the true extremes; every value outside `[low, high]` is emitted as an
outlier. `itemNameFormatter` supports the `'{value}'` token or a callback.

### External transforms (`ecStat`, shipped separately)

Registered via `echarts.registerTransform(ecStatTransform(ecStat).xxx)`. The bundled
`test/lib/ecStat.min.js` exposes exactly three:

| Type | `config` keys observed | Output |
|---|---|---|
| `ecStat:regression` | `method: 'linear' \| 'exponential' \| 'logarithmic' \| 'polynomial'`, `order` (polynomial), `formulaOn` | result 0 = fitted points; result 1 = the formula string |
| `ecStat:clustering` | `clusterCount`, `outputClusterIndexDimension`, `outputCentroidDimensions` | k-means; appends a cluster-index dimension (and optionally centroid dims) |
| `ecStat:histogram` | `method: 'squareRoot' \| 'scott' \| 'freedmanDiaconis' \| 'sturges'` | binned counts; typically result 0 = bars, result 1 = bin boundaries |

An "aggregate" transform is discussed in the docs as TODO and does **not** exist in 6.1.0.

---

## 7. The processing pipeline

Processors are registered with a numeric priority (`src/core/echarts.ts`):

| Priority | Constant | Registered stage(s) |
|---|---|---|
| 800 | `PROCESSOR.SERIES_FILTER` | legend series-level filtering |
| 900 | `PROCESSOR.DATASTACK` | `dataStackStageHandler` (stack accumulation) |
| 920 | `PROCESSOR.AXIS_STATISTICS` | axis-level statistics (`coord/axisStatistics.ts`) |
| 1000 | `PROCESSOR.FILTER` | **dataZoom** (`dataZoomProcessor`) |
| 2000 | `PROCESSOR.DEFAULT` | `dataFilter(seriesType)` (legend item filtering: pie, funnel, radar, themeRiver, chord), `negativeDataFilter('pie')`, graph category filter |
| 5000 | `PROCESSOR.STATISTIC` | **sampling** (`dataSample('line'|'bar')`), map data statistics, axisPointer |

All data-processor tasks run in **block** mode (never progressive) — see
`Scheduler.performDataProcessorTasks`.

Legend filtering (`processor/dataFilter.ts`) calls `data.filterSelf(idx => every legend selects getName(idx))`.
`negativeDataFilter` drops data items whose `value` dim is a negative number (pie only).

### dataZoom as a data-pipeline stage

`AxisProxy.filterData` mutates the *series data view*, not the raw data. Four `filterMode`s:

| `filterMode` | Implementation | Effect |
|---|---|---|
| `'filter'` (default for most) | `seriesData.selectRange({dim: [min,max]})` per mapped dimension | Rows outside the window are removed from the index vector → **other axes re-fit** to the surviving data. `NaN` is *not* filtered (so line breaks survive). |
| `'weakFilter'` | `filterSelf` with a custom predicate | A row is dropped only if **all** relevant dims are out of the window **on the same side**; if it straddles (left-out and right-out), it is kept. Designed for candlestick/interval data. |
| `'empty'` | `seriesData.map(dim, v => inWindow ? v : NaN)` | Values are blanked, row count unchanged → other axes do **not** re-fit. |
| `'none'` | early return | No data-level effect; only the axis window changes. |

In all filtering modes `setApproximateExtent(window, dim)` is called so the zoomed axis does not pay for
a full extent recomputation.

`selectRange` is hand-inlined for the 1-dim and 2-dim unfiltered cases ("about 2× faster in chrome",
"supports 5 million data filtering in data zoom" per the source comments) — a real hot loop.

### Stacking as a data stage

`enableDataStack` (at data-creation time) appends **two calculated dimensions** to the schema:
`__\0ecstackresult_<seriesId>` (cumulative value) and `__\0ecstackedover_<seriesId>` (the base to draw from).
`ensureCalculationDimension` allocates the extra columns on a possibly shared store.

`dataStack` processor (priority 900) groups series by `series.stack`, honours
`stackOrder: 'seriesAsc' | 'seriesDesc'`, then for each series walks *backwards* through earlier series in
the group to find a base:

| `stackStrategy` | Accept a lower series' value `val` when |
|---|---|
| `'samesign'` (default) | `sum >= 0 && val > 0`, or `sum <= 0 && val < 0` |
| `'all'` | always |
| `'positive'` | `val > 0` |
| `'negative'` | `val < 0` |

`sum = addSafe(sum, val)` (float-error-safe addition, so axis min/max are not corrupted).
Stack-by-value uses the inverted index on the category dimension; stack-by-index is used when
no ordinal dimension is available (and is faster — no hash map).
`NaN` propagates: a `NaN` value yields `[NaN, NaN]` so `connectNulls` area belts render correctly.

---

## 8. Sampling — `series.sampling`

Registered for **`line` and `bar` only**, at priority 5000 (after dataZoom filtering).
Guards in `dataSample`: `count > 10`, `coordSys.type === 'cartesian2d'`, and

```
size = |baseAxis.extent[1] - baseAxis.extent[0]| * devicePixelRatio
rate = round(count / size)          // data points per device pixel
if (isFinite(rate) && rate > 1) …   // frameSize = rate
```

| Value | Path | Behaviour |
|---|---|---|
| `'lttb'` | `DataStore.lttbDownSample` | Largest-Triangle-Three-Buckets (below) |
| `'minmax'` | `DataStore.minmaxDownSample` | 2 points per bucket (the min and the max), emitted in their original relative order. Preserves the visual envelope exactly. Since 5.5.0. |
| `'average'` | generic `downSample` | mean of non-NaN in bucket (`NaN` if bucket all-NaN) |
| `'sum'` | generic | sum, treating NaN as 0 |
| `'max'` | generic | max, `NaN` if non-finite |
| `'min'` | generic | min, `NaN` if non-finite |
| `'nearest'` | generic (undocumented) | `frame[0]` |
| `function(frame) → number` | generic | user sampler |

The **generic** `downSample` writes the computed value back into the (cloned) column at the
*representative* raw index `i + round(frameSize/2)` and keeps only those indices, recomputing the raw
extent as it goes. So it produces exactly `ceil(len/frameSize)` points.

### LTTB, precisely as ECharts implements it

Input: value column `dimStore`, `len = count()`, `frameSize = floor(1/rate)`.
Output: a new index vector of length ≈ `2*(ceil(len/frameSize)+2)` capped at `len`.

```
sampled[0] = rawIndex(0)                      // always keep the first point
current = rawIndex(0)
for (i = 1; i < len-1; i += frameSize):
    nextFrameStart = min(i + frameSize,   len-1)
    nextFrameEnd   = min(i + 2*frameSize, len)
    avgX = (nextFrameEnd + nextFrameStart) / 2          // NOTE: index space, not data x
    avgY = mean of non-NaN y over [nextFrameStart, nextFrameEnd)

    frameStart = i;  frameEnd = min(i + frameSize, len)
    pointAX = i - 1                                     // index space again
    pointAY = dimStore[current]

    maxArea = -1;  best = frameStart;  firstNaN = -1;  countNaN = 0
    for (idx in [frameStart, frameEnd)):
        y = dimStore[rawIndex(idx)]
        if isNaN(y): countNaN++; if firstNaN<0: firstNaN = rawIndex(idx); continue
        area = |(pointAX - avgX)*(y - pointAY) - (pointAX - idx)*(avgY - pointAY)|
        if area > maxArea: maxArea = area; best = rawIndex(idx)

    if 0 < countNaN < (frameEnd - frameStart):          // bucket is partly empty
        emit min(firstNaN, best)                        // keep index order monotone
        best = max(firstNaN, best)
    emit best
    current = best
emit rawIndex(len-1)                                    // always keep the last point
```

Two deviations from textbook LTTB worth knowing before porting: **x is the array index**, not the x
*value* (so the triangle areas are correct only for uniformly-sampled x — which is the intended use), and
**NaN gaps are explicitly preserved** by emitting the first NaN of a partially-empty bucket, so line
breaks survive down-sampling.

---

## 9. Large-data paths

### `large` / `largeThreshold`

`pipelineContext.large = series.get('large') && dataLen >= series.get('largeThreshold')`.

| Series | `large` default | `largeThreshold` default |
|---|---|---|
| `bar` / `pictorialBar` | `false` | 400 |
| `candlestick` | **`true`** | 600 |
| `scatter` / `effectScatter` | `false` | 2000 |
| `lines` | `false` | 2000 |

What the "large" renderers actually do differently:

- Layout emits a **flat `Float32Array` of points** (`data.getLayout('points')`) instead of one element
  per datum.
- Rendering collapses to **one `Path` element** for the whole series (`LargeSymbolPath`,
  `LargePath` for bars, `LargeLineDraw` for lines) whose `buildPath` walks the point array and
  emits primitives directly. No per-datum `Displayable`, no per-datum style, no per-datum hit region.
- Hit-testing is replaced by a **manual arithmetic search** over the point array
  (`largePathFindDataIndex`) driven by a throttled `mousemove`.
- Consequence, stated in the docs: *"when the optimization enabled, the style of single data item can't
  be customized any more"*.

### `progressive` / `progressiveThreshold` / `progressiveChunkMode`

Globals: `progressive: 400`, `progressiveThreshold: 3000`, `hoverLayerThreshold: 3000`
(`src/model/globalDefault.ts`). Series overrides: `bar` and `candlestick` use `progressive: 3000`;
`line`, `treemap`, `pictorialBar`, `effectScatter` set `progressive: 0` (disabled); `parallel` uses 300.

`progressiveRender = progressiveEnabled && view.incrementalPrepareRender && dataLen >= threshold`,
where `progressiveEnabled` additionally requires `zr.painter.type === 'canvas'` — **progressive
rendering is disabled under the SVG renderer**. `progressive: 0` disables it permanently.
The chunk size is `Math.round(progressive || 700)`.

`progressiveChunkMode` (`'sequential'` default, `'mod'`; supported by `bar` and `candlestick`):
`'mod'` sets `modDataCount = data.count()` and the scheduler computes `modBy = ceil(modDataCount/step)`,
so each frame's chunk is a *strided* sample spread across the whole dataset rather than a contiguous
prefix — the chart "fills in" uniformly instead of sweeping left-to-right.

### High-dimension omission

`shouldOmitUnusedDimensions(dimCount) = dimCount > 30`. Above that, `SeriesData` only materializes the
dimensions actually used by the coordinate system and `encode`; `SeriesDataSchema` keeps a name→index map
so user queries by name still resolve. Store-sharing hashes also relax their escaping above this
threshold for speed.

---

## 10. Data update semantics

### `setOption` merge modes

`chart.setOption(option, {notMerge?, replaceMerge?, lazyUpdate?, silent?, transition?})`:

| Mode | Component mapping (`mappingToExists`) |
|---|---|
| default | `'normalMerge'` — match by `id`, then by `name`, then by index; unmatched *existing* components are kept |
| `notMerge: true` | option is discarded and rebuilt (`'replaceAll'`) |
| `replaceMerge: 'series'` (or an array of main types) | `'replaceMerge'` — for the listed main types, only `id`-matched components survive; everything else in that main type is **removed** (leaving index "holes") |
| `lazyUpdate: true` | model is updated immediately, but the render is deferred to the next animation frame |
| `silent: true` | suppresses `finished`/`rendered` events |

### `chart.appendData({seriesIndex, data})`

Appends to the raw provider and re-initializes only the new `[start, end)` range in the store
(`_initDataFromProvider(start, end, append=true)`, which grows each typed-array column and copies the old
content). Hard constraints from the source:

- Only legal **before any filtering** — `assert(!this._indices, 'appendData can only be called on raw data.')`.
- For `typedArray` sources the provider *replaces* its buffer and `clean()`s it after ingestion
  (`persistent: false`), so `end` is offset by `start`.
- `arrayRows` + `seriesLayoutBy: 'row'` throws.
- Axis extents are **not** recomputed — the docs require `xAxis.data` or explicit `min`/`max`.
- `SeriesData.appendValues(values, names?)` is the lower-level variant that adds parsed values without
  touching the raw provider.

### `DataDiffer` — id/name based matching

`SeriesData.diff(other)` builds a `DataDiffer` keyed on `getId(rawIndex)`:

```
id = _idList[raw]                      // from dataItem.id, or encode.itemId dimension
   ?? category value at _idDimIdx
   ?? ID_PREFIX + rawIndex             // fallback: positional
```

`_nameList` is filled from `dataItem.name` or the `encode.itemName` dimension; when no id dimension
exists, `makeIdFromName` derives an id from the name, appending a repeat counter for duplicates.

Two diff modes:

- `'oneToOne'` (default): callbacks `add(newIdx)`, `update(newIdx, oldIdx)`, `remove(oldIdx)`.
  Duplicate keys are consumed FIFO so every old and new item is visited exactly once.
- `'multiple'`: additionally `updateManyToOne(newIdx, oldIdx[])`, `updateOneToMany(newIdx[], oldIdx)`,
  `updateManyToMany(newIdx[], oldIdx[])` — the basis of merge/split morphing animations.

Keys are prefixed `'_ec_'` to avoid `Object.prototype` collisions (a JS-object-as-hashmap artifact).

### `universalTransition` — `groupId` / `childGroupId`

Key resolution order per datum (`src/animation/universalTransition.ts`):
`encode.itemGroupId` dimension value → `dataItem.groupId` → `series.dataGroupId` → the datum's **id**.
Same for `childGroupId` via `encode.itemChildGroupId`.

The transition direction is decided by *set intersection*: if old `childGroupId`s intersect new
`groupId`s → parent-to-child (drill-down); if old `groupId`s intersect new `childGroupId`s →
child-to-parent (roll-up). The chosen field is then used as the `DataDiffer` key in `'multiple'` mode,
so one-to-many / many-to-one produce split / merge morphs.

---

## 11. Statistics ECharts computes internally

| Where | Statistic |
|---|---|
| `DataStore.getSum(dim)` | sum ignoring NaN |
| `DataStore.getMedian(dim)` | collects non-NaN, `asc()` sorts, takes middle (or mean of two middles). **Bug-compatible note:** it divides by `this.count()` (all rows) rather than the number of non-NaN collected |
| `DataStore.getDataExtent(dim, filter)` | min/max with optional sanitization filter `{g, ge, l, le}` — used to exclude non-positive values for log axes; results cached per filter key |
| `markPoint`/`markLine` `type` | `'min'`, `'max'`, `'average'`, `'median'` (`markerHelper.ts`). `average` = mean of non-NaN over the value dimension; `median` = `data.getMedian`; `min`/`max` = `getDataExtent`. After computing the value, `indicesOfNearest` locates the *actual datum* nearest that value and the marker snaps to its coordinates, with the display value rounded to that datum's decimal precision (capped at 20). Stacked series use `stackResultDimension`. |
| `markLine` `valueIndex` / `valueDim` | which dimension the statistic runs on |
| boxplot transform | quartiles + IQR fences (§6) |
| pie | `getPercentSeats` — largest-remainder percentage rounding so labels sum to 100% |

---

## 12. Explicitly browser-bound in this subsystem

- `transform.print` → `console.log`; dev-build only.
- Progressive rendering requires `zr.painter.type === 'canvas'`; it is off under the SVG renderer.
- `hoverLayerThreshold` is a canvas-layer optimization (separate hover layer).
- `devicePixelRatio` feeds the sampling rate calculation.
- Typed arrays (`Float64Array`/`Int32Array`/`Uint32Array`/`Uint16Array`) with graceful `Array` fallback
  when the constructor is `undefined` — a legacy-browser accommodation, irrelevant natively.
- `regexp` filter values may be `RegExp` instances **or** serializable pattern strings.
- `Date` instances are accepted as data values anywhere a time value is accepted.
- No worker threads anywhere in the pipeline; "progressive" is frame-sliced on the main thread only.
- `echarts-gl` (WebGL) is out of tree and adds nothing to this data model beyond extra coordDims.

---

## Porting notes

Classification for a Free Pascal / BGRABitmap immediate-mode desktop chart control.

### NATURAL — maps cleanly

| Capability | Note |
|---|---|
| Columnar store: one dynamic array per dimension | `array of Double` / `array of Int32` / `array of string`; FPC has this natively and better than JS |
| 5 dimension types (`float`/`int`/`number`/`ordinal`/`time`) | `time` = `TDateTime` or Int64 epoch-ms; keep one canonical numeric representation |
| `NaN` as the universal "no data" sentinel | FPC `NaN` from `Math`; parse `'-'`/`''`/`nil` → `NaN` exactly as `parseDataValue` does |
| `rawCount` vs `count` + an index-indirection vector | `array of LongWord`; `GetRawIndex` as a method pointer swapped between identity and indirection |
| `indexOfRawIndex` binary search | trivial |
| Raw-extent maintained during fill; extent cache keyed by dimension | trivial |
| `selectRange` / `filterSelf` / `map` / `each` bulk ops | direct loops; specialize the 1-dim and 2-dim cases like ECharts does |
| `OrdinalMeta` interning (categories + lazy hash) | `TDictionary<string, Integer>` built lazily |
| Inverted index for stack-by-value | `array of Int32` sized to category count, `-1` sentinel |
| `series.data` shape polymorphism (scalar / tuple / record with overrides) | needs a variant/record union in Pascal, but is structurally simple |
| `dataset.source` in all 4 shapes + `sourceHeader` + header auto-detection | the 10-cell heuristic is 20 lines |
| `seriesLayoutBy: 'column'|'row'` | index transposition in the provider layer |
| `encode` (all 11+7 roles) | a record of `array of Integer` per role |
| `dimensions` declaration incl. `displayName`, duplicate-name suffixing | |
| Default encode: "category way" / "value way" / name-based | ~120 lines; the per-dataset cursor is the only subtlety |
| Stacking (`stack`, `stackOrder`, `stackStrategy` ×4) with two appended calc dimensions | |
| dataZoom `filterMode` ×4 as a data stage | `'filter'` = range select, `'empty'` = value blanking, `'weakFilter'` = straddle predicate, `'none'` = no-op |
| Sampling: `average`/`sum`/`min`/`max`/`nearest` + custom callback | generic bucket loop |
| `minmax` down-sampling | 2 points per bucket, order-preserving |
| `getSum` / `getMedian` / `getDataExtent` with the log-axis sanitization filter | |
| `markPoint`/`markLine` `'min'|'max'|'average'|'median'` + nearest-datum snapping + precision rounding | |
| boxplot statistic (quartiles, IQR fences, outlier split) | ~40 lines |
| `appendData` with column growth (no filtering active) | `SetLength` + copy; cheaper in FPC than in JS |
| Store sharing across series via a schema hash | worth doing: N series over one table should parse once |

### HEAVY — doable but algorithmically substantial

| Capability | Algorithm / cost |
|---|---|
| **LTTB down-sampling** | Largest-Triangle-Three-Buckets, with ECharts' two twists (index-space x; NaN-gap preservation). Pseudocode reproduced verbatim in §8 — port that, not the textbook version, or gaps and endpoints will differ |
| **`DataDiffer`** | Key-hash diff with 4 cardinality outcomes (1:1, N:1, 1:N, N:N) driving add/update/remove callbacks. `'multiple'` mode is what enables split/merge morphs; the FIFO consumption of duplicate keys is easy to get wrong |
| **`universalTransition` group matching** | Two `DataDiffer` passes plus a set-intersection test to pick the drill direction. Only worth it if you want drill-down animation |
| **The transform pipeline as an extensible mechanism** | Registry + a sandboxed `ExternalSource` façade + the dimension-inheritance rule + header re-prepending + multi-output (`fromTransformResult`) + piping. The individual transforms are easy; the *plumbing* and its invalidation/versioning (`SourceManager._isDirty` walking the dataset DAG recursively) is the substantial part |
| **The filter condition DSL** | A small recursive expression tree (`and`/`or`/`not`/relational), plus 7 operators × 3 parsers × the strict `numericToNumber` coercion and the [EMPTY_RULE]. Needs a parsed/compiled representation for performance, exactly as ECharts precompiles comparators per condition node |
| **Sort comparison rule** | Three-class comparison (numeric / non-numeric-string / other) with configurable "incomparable" polarity; multi-key. Easy to under-specify and produce `'2' > '12'` bugs |
| **Dimension resolution (`prepareSeriesDataSchema`)** | The three-way reconciliation of coordSys requirements × user `encode`/`dimensions` × detected data shape, including `-1` opt-out, `dimsDef` templates, generated coord names (`value`, `value0`, `indicator_0`…), extra-coord marking, and duplicate removal. This is the single most intricate file in the subsystem (411 lines) and is load-bearing for every series |
| **Time value parsing** | ISO-8601 subset + a pile of loose formats + timezone handling + UTC flag. Use a vetted parser; do not hand-roll |
| **Store-sharing hash + high-dimension omission (>30 dims)** | Only needed if you support wide datasets shared by many series |
| **Progressive/chunked processing** | Frame-sliced task pipeline with per-stage dirty tracking and `'mod'` striding. On a desktop native control this is *optional* — FPC will chew through data an order of magnitude faster than JS — but for >1M points on a resizing window it still buys responsiveness. If implemented, it is a scheduler, not a data structure |
| **Graph / Tree companion structures** | `Graph` (nodes+edges as two linked `SeriesData`s) and `Tree` (with `viewChildren` for treemap/sunburst layout) plus the method-proxying that keeps linked datas in sync under filter/sample |
| **`large` render path** | Flat point buffers + one composite path + arithmetic hit-testing. On BGRABitmap this is *more* natural than in the DOM (you are already immediate-mode), but the hit-test replacement and the "no per-item styling" contract must be designed in |

### BROWSER-BOUND — needs a native re-think or is out of scope

| Capability | Why / what to do instead |
|---|---|
| `transform.print` | `console.log` debugging. Native equivalent: write to a log/`OutputDebugString`, or expose a "dump transform result" designer action |
| Progressive rendering gated on `painter.type === 'canvas'` | The SVG-renderer exclusion is meaningless natively; drop the gate |
| `hoverLayerThreshold` (separate canvas hover layer) | Native equivalent is your own paint-cache / dirty-rect strategy; not a data-pipeline concern |
| `devicePixelRatio` in the sampling rate | Replace with your DPI scale factor; the *formula* (points per device pixel) still applies |
| Typed-array-vs-`Array` fallback branches | Delete; FPC always has real typed arrays |
| `RegExp` in the filter DSL | FPC needs a regex unit (`RegExpr`); if you don't want the dependency, ship `filter` without `reg` and document it |
| JS-object-as-hashmap artifacts (`'_ec_'` key prefix, `hasOwn` checks, `Object.prototype` collisions) | Non-issues with a real dictionary |
| Accepting JS `Date` instances / functions as option values | Replace with `TDateTime` and method pointers respectively |
| External transform *registration by third-party JS* (`ecStat`) | Regression / k-means clustering / histogram must be reimplemented natively if wanted. They are ordinary numeric algorithms (least-squares fits, Lloyd's algorithm, Sturges/Scott/Freedman-Diaconis binning) — HEAVY, not impossible, but they are *not* part of ECharts core and can be deferred |
| `series.data` items carrying arbitrary nested style option objects resolved through a prototype-chained `Model` | The `getItemModel` mechanism relies on JS prototype fallback to the series model. Natively: an explicit per-datum override record with `HasX` flags, or a small property-bag with fallback lookup |
| Worker threads | ECharts has none here; nothing to port |
| `echarts-gl` | Out of scope entirely |
