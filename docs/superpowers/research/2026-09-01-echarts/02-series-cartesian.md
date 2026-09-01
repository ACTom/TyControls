# ECharts 6.1.0 — The Cartesian / Grid-Based Series Family

Research pass for a native Object Pascal (FPC/Lazarus) custom-drawn chart control rendered with
BGRABitmap. Sources read: `D:/Projects/echarts` (TS source, v6.1.0 per `package.json`) and
`D:/Projects/echarts-doc/en/option/**` (official option reference, `${partial}` includes resolved).

Scope: `line`, `bar`, `pictorialBar`, `scatter`, `effectScatter`, `candlestick`, `boxplot`,
`heatmap`, `themeRiver`, `custom` — 10 of the 24 series types in `src/chart/`.

---

## 0. Cross-cutting facts you need before reading the per-series sections

### 0.1 Which coordinate system can each series live on

From `echarts-doc/en/option/partial/coord-sys.md` (the authoritative matrix) cross-checked against
`static dependencies` and the `coordinateSystem?:` union in each `*Series.ts`.

| series | none | cartesian2d (grid) | polar | geo | singleAxis | calendar | matrix | source union |
|---|---|---|---|---|---|---|---|---|
| `line` | ❌ | ✅ | ✅ | ❌ | ❌* | indirect | indirect | `'cartesian2d' \| 'polar'` |
| `bar` | ❌ | ✅ | ✅ | ❌ | ❌ | indirect | indirect | `'cartesian2d' \| 'polar'` |
| `pictorialBar` | ❌ | ✅ | ❌† | ❌ | ❌ | indirect | indirect | `'cartesian2d'`, deps `['grid']` |
| `scatter` | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `string`, deps `['grid','polar','geo','singleAxis','calendar','matrix']` |
| `effectScatter` | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `string`, deps `['grid','polar']` (doc adds geo/single/calendar/matrix) |
| `candlestick` | ❌ | ✅ | ❌ | ❌ | ❌ | indirect | indirect | `'cartesian2d'` |
| `boxplot` | ❌ | ✅ | ❌ | ❌ | ❌ | indirect | indirect | `'cartesian2d'` |
| `heatmap` | ❌ | ✅ | ❌ | ✅ | ✅(calendar) | ✅ | ✅ | `'cartesian2d'\|'geo'\|'calendar'\|'matrix'` |
| `themeRiver` | ❌ | ❌ | ❌ | ❌ | ✅ **only** | indirect | indirect | `'singleAxis'` |
| `custom` | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | `string \| 'none'` |

\* `line.md` passes `singleAxis = true` to the coord-sys partial but `LineSeries.getInitialData()`
throws in `__DEV__` for anything other than `cartesian2d`/`polar`. Treat line as cartesian+polar.
† The big doc table shows a ✅ for pictorialBar under polar, but `pictorialBar.md` itself passes
`polar = false` and the model declares `coordinateSystem?: 'cartesian2d'` with `dependencies:
['grid']`. Source wins: **pictorialBar is cartesian2d-only.**

"indirect" = the series cannot address calendar/matrix itself, but the `grid`/`singleAxis` it sits
on can be laid out **inside** a calendar cell or matrix cell. That is the v6
`coordinateSystemUsage` mechanism (below).

**New in v6**: `series.coordinateSystemUsage` = `'data'` | `'box'`.
- `'data'` — each `series.data[i]` is positioned by the coord system. All 10 series here use this.
- `'box'` — the whole series/component gets one bounding rect from the coord system. Not applicable
  to any of these 10 series (pie/tree/treemap/sankey/graph use it). Paired with `series.coord`.

Axis selection: `xAxisIndex`/`xAxisId`, `yAxisIndex`/`yAxisId`, `polarIndex`/`polarId`,
`singleAxisIndex`/`singleAxisId`, `geoIndex`/`geoId`, `calendarIndex`/`calendarId`,
`matrixIndex`/`matrixId`. (`*Id` variants added in 6.0.0.)

### 0.2 Data formats (shared)

Resolved from `partial/2d-data.md`. Every one of these series accepts:
1. **Flat 1-D array** `[10, 20, 30]` — index maps to the category axis.
2. **2-D array** `[[3.4, 4.5, 15, 43], ...]` — each column is a "dimension".
3. **Object items** `{name, value, itemStyle, label, emphasis, blur, select, tooltip, groupId,
   childGroupId, ...}` — per-datum style override.
4. **`dataset`** — if `series.data` is absent, the series pulls from `dataset[datasetIndex]`
   (or `datasetId`), with `seriesLayoutBy: 'column' | 'row'` and `encode` for dimension mapping.
5. `series.dimensions` names dimensions; `series.encode` maps dimension → axis role
   (`encode: {x: [2,4,3], y: 1, label: 0, tooltip: [2,4,3]}`).

`groupId` / `childGroupId` on data items exist only to drive universal-transition morphing.

### 0.3 States (shared, since v5.0.0)

Four style states per series and per data item: **normal**, `emphasis`, `blur`, `select`.
- `emphasis.disabled`, `emphasis.focus` ∈ `'none' | 'self' | 'series'` (+ `'adjacency'`,
  `'ancestor'`, `'descendant'`, `'relative'` for graph/tree only).
- `emphasis.blurScope` ∈ `'coordinateSystem' | 'series' | 'global'` — the set that fades.
- `emphasis.scale` — `boolean | number` (default scale 1.1) on line/scatter/effectScatter;
  `boolean` on pictorialBar (default `false`) and boxplot (`true`).
- `select.disabled`, `selectedMode` ∈ `false | 'single' | 'multiple' | 'series'`.
- `itemStyle.color: 'inherit'` in `emphasis` disables the colour highlight (v5.2.0).
- `line.emphasis.lineStyle.width` additionally accepts the literal `'bolder'`.

### 0.4 Stacking (`line`, `bar`, `scatter` — via `SeriesStackOptionMixin`)

`processor/dataStack.ts`. Series sharing a `stack` string on the same base axis are cumulated.
- **Stacked axis** must be `type: 'value' | 'log'`.
- **Base axis** `category` → group by category value; base axis `value/time/log` → group by
  *data index* (documented caveat: the user must align indices).
- `stackStrategy` ∈ `'samesign'` (default — only stack onto a cumulate of the same sign),
  `'all'`, `'positive'`, `'negative'`.
- `stackOrder` ∈ `'seriesAsc'` (default) | `'seriesDesc'` — **new in 6.0.0**; not supported on polar.
  Implementation is literally `stackInfoList.reverse()`.
- Stacking writes two extra dimensions per datum: `stackResultDimension` and
  `stackedOverDimension` (the latter is the baseline the area/bar starts from). A NaN input
  propagates NaN to `stackedOver` so `connectNulls` areas draw correctly.

### 0.5 Down-sampling (`sampling` — `line`, `bar`)

`processor/dataSample.ts`. Active only when `count > 10`, `coordSys.type === 'cartesian2d'`, and
the computed `rate = round(count / (baseAxisPixelSpan * devicePixelRatio))` is `> 1`.

| value | algorithm |
|---|---|
| `'lttb'` | Largest-Triangle-Three-Buckets — preserves trend and extremes |
| `'minmax'` | keeps the max-absolute extremum per bucket (since 5.5.0) |
| `'average'` | arithmetic mean of the bucket, NaN-skipping |
| `'sum'` | sum of the bucket |
| `'max'` | bucket maximum |
| `'min'` | bucket minimum |
| `'nearest'` | first element of the bucket (internal, undocumented) |
| a function | user sampler `(frame: ArrayLike<number>) => number` |

The index of the survivor is always `round(frame.length / 2)` (`indexSampler`).

### 0.6 `large` / `progressive` (performance modes)

- `large: boolean`, `largeThreshold: number` — swaps the per-datum element tree for one batched
  path. Per-item styling is lost. Defaults: scatter 2000, bar 400, candlestick `large:true`/600.
- `progressive: number` (elements per ~16 ms frame), `progressiveThreshold`,
  `progressiveChunkMode` ∈ `'sequential' | 'mod'` (`'mod'` interleaves so the partial render looks
  representative). `progressive: 0` disables. **This whole family is a browser-frame-budget
  concept**: it exists because the JS main thread blocks the UI.
- `line` and `pictorialBar` set `progressive: 0` (disabled).
- `hoverLayerThreshold` (line sets `Infinity`) is a canvas-layer trick, browser-specific.

### 0.7 Shared style vocabulary (every series)

`itemStyle`: `color` (solid / **linear gradient** / **radial gradient** / **image pattern**),
`borderColor`, `borderWidth`, `borderType` (`'solid'|'dashed'|'dotted'` **or a number/number[]
dash array**, since 5.0.0), `borderDashOffset`, `borderCap`, `borderJoin`, `borderMiterLimit`,
`opacity`, `shadowBlur`, `shadowColor`, `shadowOffsetX/Y`, `decal`.

`lineStyle`: `color`, `width`, `type`/`dashOffset`/`cap`/`join`/`miterLimit`, `opacity`, shadows.

`areaStyle`: `color`, `origin`, `opacity` (default 0.7 on line), shadows.

`decal` (accessibility pattern fill, gated on `aria.enabled && aria.decal.show`): `symbol`,
`symbolSize`, `symbolKeepAspect`, `color`, `backgroundColor`, `dashArrayX`, `dashArrayY`
(each `number | number[] | (number|number[])[]`), `rotation`, `maxTileWidth/Height`.

`label`: `show`, `position` (14 named positions + `[x, y]` absolute/percent), `distance`, `rotate`,
`offset`, `formatter` (string template `{a} {b} {c} {d} {@dim} {@[n]}` or callback), `textMargin`,
`minMargin`, plus the whole `textStyle` family (`color`, `fontStyle`, `fontWeight`, `fontFamily`,
`fontSize`, `align`, `verticalAlign`, `lineHeight`, `backgroundColor`, `borderColor/Width/Radius`,
`padding`, `shadow*`, `width`, `height`, `textBorder*`, `textShadow*`, `overflow`, `ellipsis`,
`rich` named style fragments).

`labelLine`: `show`, `showAbove`, `length2`, `smooth`, `minTurnAngle`, `lineStyle`.

`labelLayout` (object or callback): `hideOverlap`, `moveOverlap` (`'shiftX'|'shiftY'`), `x`, `y`,
`dx`, `dy`, `rotate`, `width`, `height`, `align`, `verticalAlign`, `fontSize`, `draggable`,
`labelLinePoints`. **`draggable` is pointer-interaction; `hideOverlap`/`moveOverlap` are real
layout algorithms.**

`markPoint` / `markLine` / `markArea` attach to all 10 series except themeRiver (which omits the
marker partial). Data items address positions by `coord: [x, y]`, by `xAxis`/`yAxis` value, by
pixel `x`/`y`, or by **statistical `type` ∈ `'min' | 'max' | 'average' | 'median'`** with
`valueIndex` / `valueDim` selecting the dimension. markLine gets `symbol` at both ends and
`label.position ∈ 'start'|'middle'|'end'|'insideStart'|...`.

`universalTransition`: `enabled`, `seriesKey` (string or array — many-to-one merge),
`divideShape` ∈ `'split' | 'clone'`, `delay(index, count)`. Cross-series morphing animation.
Line/scatter/effectScatter default to `divideShape: 'clone'`.

`animation*`: `animation`, `animationThreshold`, `animationDuration(Update)`,
`animationEasing(Update)` (~30 named easings), `animationDelay(Update)` (number or
`(dataIndex, params) => number`), plus `stateAnimation` for state transitions.

`z` / `zlevel` (zlevel = a separate canvas layer — browser concept), `silent`, `cursor`
(**CSS cursor name — browser-bound**), `tooltip` per-series and per-datum, `colorBy` ∈
`'series' | 'data'`, `legendHoverLink`, `name`, `id`.

---

## 1. `series.line` — polyline / area / step / smooth

`src/chart/line/{LineSeries,LineView,poly,helper,lineAnimationDiff}.ts` (LineView is 53 KB — the
most feature-dense view in the family).

**Draws**: one `ECPolyline` for the trend, optionally one `ECPolygon` for the filled area
(polyline + a "stackedOn" baseline polyline), plus one `Symbol` element per datum, plus one
optional `endLabel` text.

### 1.1 Curve shape

- **`smooth: boolean | number`** — `0..1` smoothness. Not a Catmull-Rom: `poly.ts drawSegment()`
  computes per-vertex Bézier control points from the *previous→next* chord vector `v`, scaled by
  `smooth`, split by the segment-length ratio `lenNext / (lenNext + lenPrev)`, then **clamped**
  (`smoothConstraint`) so a control point never leaves the `[min(prev,cur), max(prev,cur)]` box in
  either axis — this is the anti-overshoot guard. It then *re-derives* cp1 from the clamped cp0 to
  keep C1 continuity. Reproducing this exactly matters if you want visual parity.
- **`smoothMonotone: 'x' | 'y' | 'none'`** — replaces the chord-vector control points with
  axis-aligned ones (`cpx1 = x − dir·|dx0|·smooth, cpy1 = y`), which forces monotonicity along that
  axis. Documented use: dual value axes.
- **`step: false | true | 'start' | 'middle' | 'end'`** — `turnPointsIntoStep()` injects one extra
  vertex (`'start'`/`'end'`) or **two** extra vertices (`'middle'`, at the midpoint of the base
  axis) between every pair. `'start'` = the value changes at the left edge of the interval;
  `'end'` = at the right edge; `'middle'` = halfway. Interacts with `connectNulls` (nulls are
  skipped before stepping) and with the area baseline (`stackedOnPoints` gets the same treatment).
  **Not supported on polar** (`// FIXME step not support polar`).
- `smooth` is ignored when `step` is set.

### 1.2 Area

- **`areaStyle`** presence alone turns the line into an area chart.
- **`areaStyle.origin`** ∈ `'auto'` (fill between the axis line, i.e. value 0 / axis start, and the
  data) | `'start'` (fill from the axis minimum) | `'end'` (from the axis maximum) | **`number`**
  (fill from an arbitrary data value, since 5.3.2).
- When stacked, the area's lower boundary is the previous series' `stackedOver` polyline, not a
  flat baseline.
- `areaStyle.color` accepts a gradient object (`type:'linear'|'radial'`, `colorStops`,
  `global`), so vertical fade-outs are a plain option, not a hack.

### 1.3 Segmented colour from `visualMap` (`getVisualGradient`)

A genuinely distinct capability: when a `visualMap` targets a dimension mapped to x or y, LineView
converts the visualMap's piecewise/continuous stops into a **`LinearGradient` in screen space along
that axis**, clipped to the viewport with a 10 px bleed and `outerColors` for the out-of-range
head/tail. That is how the "AQI line that changes colour by value band" demo works — one stroke,
one gradient, no path splitting. Only works on `cartesian2d`, only on the x or y dimension.

### 1.4 Symbols

`partial-symbol` resolved:
- **`symbol`** — built-in `'circle' | 'rect' | 'roundRect' | 'triangle' | 'diamond' | 'pin' |
  'arrow' | 'none'` (+ internal `'line'`, `'square'`; + every name prefixed `'empty'`, e.g.
  `'emptyCircle'` = white fill + coloured 2 px stroke, which is line's **default**), or
  `'image://<url|dataURI>'`, or `'path://<SVG path data>'`. Also a **callback**
  `(value, params) => string`.
- **`symbolSize`** — `number | [w, h] | (value, params) => number|[w,h]`.
- **`symbolRotate`** — degrees, negative = clockwise; also a callback (since 4.8.0).
- **`symbolKeepAspect`** — only meaningful for `path://` symbols.
- **`symbolOffset`** — `[x, y]`, absolute px or `'%'` of symbol size.
- **`showSymbol: boolean`** (default `true`) — when false, symbols still appear on hover.
- **`showAllSymbol: 'auto' | true | false`** — category axis only. `'auto'` probes 5 sampled
  points; if the symbol size fits the band width it shows all, otherwise it falls back to
  `axisLabel.interval`'s visible-tick set (`getIsIgnoreFunc` builds a `{tickValue: true}` map from
  `categoryAxis.getViewLabels()`).

### 1.5 Nulls, clipping, events

- **`connectNulls: boolean`** — bridge across non-finite values. `drawSegment` skips illegal points
  and, in smooth mode, searches forward for the next legal point to build control points from.
- **`clip: boolean`** (default `true`, since 4.4.0). Semantics differ per element:
  *the line/area is geometrically clipped to the coord rect*; *a symbol is dropped only if its
  centre is outside* — never half-clipped. The clip rect is inflated by 0.1 px (cartesian) or
  0.5 px on r0/r (polar) to avoid edge artefacts.
- **`triggerEvent: false | true | 'line' | 'area'`** (**new in 6.1.0**) — makes the stroke and/or
  the fill hit-testable, emitting `selfType: 'line' | 'area'`. Supersedes
  **`triggerLineEvent`** (5.2.2, deprecated 6.1.0).

### 1.6 `endLabel` (5.0.0)

A label pinned to the last non-null point of the line, drawn as the polyline's `textContent` with
`ignoreClip = true`. Options: the full label set minus `position` (auto-derived from axis
direction/inverse: `align`/`verticalAlign` computed in `getEndLabelStateSpecified`), plus
**`valueAnimation: boolean`** — during the reveal animation the label's *text* is interpolated to
the value under the moving clip edge (`_endLabelOnDuring` uses `getIndexRange` + `cubicRootAt` to
find the data value at the animating clip boundary). Has its own `emphasis`/`blur`/`select`
variants. **Explicitly warns and no-ops on polar.**

### 1.7 Other line specifics

- `lineStyle` default `{width: 2, type: 'solid'}`; `emphasis.lineStyle.width: 'bolder'`.
- `animationEasing: 'linear'`, `progressive: 0`, `hoverLayerThreshold: Infinity`.
- `getLegendIcon()` composes a line glyph + a scaled (80 %) symbol glyph for the legend.
- `lineAnimationDiff.ts` computes a point-level diff (old vs new point arrays, `getBoundingDiff`,
  `isPointsSame`) so that adding/removing data animates the polyline rather than redrawing it.
- Data item value may itself be an array (`LineDataValue = OptionDataValue | OptionDataValue[]`).

---

## 2. `series.bar` — rect / polar sector bars

`src/chart/bar/{BaseBarSeries,BarSeries,BarView}.ts` + `src/layout/{barGrid,barPolar,barCommon}.ts`.

**Draws**: one `Rect` per datum on cartesian2d; one `Sector` (or `Sausage` when `roundCap`) per
datum on polar. Optionally one background `Rect`/`Sector` per datum behind it.

### 2.1 The width/offset layout algorithm (`calcBarWidthAndOffset`)

This is a real algorithm, not a knob. Per base axis, over *all* bar series on it:
1. `bandWidth` from the axis (category band, or a computed band for value/time/log axes).
2. Each distinct `stack` id counts as one column. `barWidth` (px or `'%'` of band) reserves width
   immediately and subtracts from `remainedWidth`.
3. `barCategoryGap` default is **`max(35 − stackCount·4, 15) + '%'`** — gaps shrink as the series
   count grows. `barGap` default `'10%'` (the private `defaultBarGap`; docs say `'20%'`).
   `barGap: '-100%'` makes columns fully overlap — the documented way to build a background bar.
4. `autoWidth = (remainedWidth − categoryGap) / (autoCount + (autoCount−1)·barGapPercent)`.
5. Two clamping passes apply `barMaxWidth` then `barMinWidth`. **`barMinWidth` outranks
   `barMaxWidth` and `remainedWidth`** — bars may deliberately overlap rather than vanish.
   `barMinWidth` defaults to 1 on cartesian, null elsewhere.
6. Final `offset = −widthSum/2`, then each column advances by `width·(1 + barGapPercent)`.

Note: these five options are **shared across all bar series on one axis**; the doc says to set them
on the *last* bar series in that coordinate system.

Additional sizing: `barMinHeight` (px floor so tiny values stay clickable), `barMinAngle` (polar
equivalent).

### 2.2 Cartesian vs polar vs orientation

- Horizontal vs vertical is not an option — it falls out of which axis is `category` (or which is
  the base axis). `data.getLayout('valueAxisHorizontal')` drives the large-mode packing.
- Polar bars: `barLayoutPolar` produces sectors. Base axis `angle` → radial bars; base axis
  `radius` → tangential (ring-segment) bars.
- **`roundCap: boolean`** (4.5.0, polar only) — swaps `Sector` for the custom `Sausage` shape
  (rounded caps at both ends of the arc). Changing it forces element re-creation (no morph path
  between sector and sausage).
- Negative values simply produce bars on the other side of the axis' zero/start coordinate
  (`getStartValue(baseAxis)` from `rawExtentInfo.makeRenderInfo().startValue`, which is what makes
  `axis.startValue` / log axes behave).

### 2.3 Rounded corners

`itemStyle.borderRadius` — `number | number[]` (`[LT, RT, RB, LB]`) on cartesian rects;
`(number|string)[] | number | string` on polar, where it becomes the **sector corner radius**
(`sectorHelper`). Background bars have their own `backgroundStyle.borderRadius`.

### 2.4 `showBackground` (4.7.0)

`showBackground: boolean` + `backgroundStyle` (`color` default `rgba(180,180,180,0.2)`,
`borderColor/Width/Type/Radius`, shadows, `opacity`). Draws a full-band-height ghost bar behind
each datum, in its own `_backgroundGroup`. In `large` mode there is a parallel
`largeBackgroundPoints` batched path.

### 2.5 `large` mode

`createLarge()` builds a single `LargePath` whose `buildPath` issues `ctx.rect()` per datum from a
flat `Float32Array` (`[x, y, size]` triples). Hit-testing is a throttled (30 ms) linear scan
(`largePathFindDataIndex`). Per-item styling is unavailable; only the series-level style applies.
Stroke is nulled on the batched path to avoid overlap artefacts.

### 2.6 `realtimeSort` — the bar-race feature

The distinctive one. `shouldRealtimeSort()` requires `coordSys === 'cartesian2d'` **and** a
`category` base axis (it warns otherwise). Mechanism:
1. On the first frame, `_dispatchInitSort` sorts data items by their *value* and dispatches a
   `changeAxisOrder` action carrying `sortInfo.ordinalNumbers` — i.e. **it reorders the ordinal
   scale of the axis, not the data**.
2. On subsequent frames it hooks zrender's `'rendered'` event and, per frame, re-derives the order
   from the *current animated pixel length* of each bar (`shape.height` / `shape.width`), not from
   the target value. That is what makes bars visibly overtake each other mid-animation.
3. `_isOrderChangedWithinSameData` (cheap monotonicity check over the ordinal scale) and
   `_isOrderDifferentInView` (only compares ticks inside the current axis extent, so off-screen
   swaps don't churn) gate the dispatch.
4. `getInitialData` sets `createInvertedIndices: true` when realtimeSort is on.

Requires `createInvertedIndices`, a category axis with animation, and cooperating axis animation
(`updateRealtimeAnimation` animates the axis label positions too).

### 2.7 Rest of bar

- `stack` / `stackStrategy` / `stackOrder` (§0.4), `sampling` (§0.5), `large`/`largeThreshold`
  (400), `progressive` 3000 / `progressiveChunkMode: 'mod'`.
- **`clip: boolean`** default `true`; since **6.1.0** overflowing parts of a bar are *geometrically
  clipped* (before 6.1.0 a bar was only dropped if wholly outside). Matters with
  `boundaryGap: false` or numeric axes.
- `label.position` gains 5 polar-only values: `'start' | 'insideStart' | 'middle' |
  'insideEnd' | 'end'` (5.2.0); `label.valueAnimation` interpolates the printed number.
- `select.itemStyle` defaults to a 2 px primary-colour border.
- `brushSelector` = rect containment (for the brush component).

---

## 3. `series.pictorialBar` — glyph bars (a whole layout algorithm)

`src/chart/bar/{PictorialBarSeries,PictorialBarView}.ts` (33 KB view).

**Concept**: bar layout produces an invisible **reference bar** per datum; the drawn thing is one
symbol, or a *repeated stack* of symbols, positioned relative to that reference bar. Stacking is
force-disabled (`getInitialData` sets `option.stack = null`). `barGap` defaults to `'-100%'` so
series overlap by default (background + foreground pattern). `clip` defaults to **`false`**
(pictorial charts usually hide their axes). `progressive: 0`. `emphasis.scale: false`.

Every symbol option below can be set **at series level or per data item** — that cascade is part of
the design.

### 3.1 The options and their exact semantics

| option | type | semantics |
|---|---|---|
| `symbol` | string | built-in name, `path://`, or `image://`. Default `'circle'` (class default `roundRect`). |
| `symbolSize` | `number \| string \| [w,h]` | default `['100%','100%']`. Percent resolves against **category size** on the category axis; on the value axis it resolves against `categorySize` when repeating, else against `abs(boundingLength)`. |
| `symbolPosition` | `'start' \| 'end' \| 'center'` | which edge of the glyph inscribes which end of the reference bar. |
| `symbolOffset` | `[x,y]`, px or `%` of symbolSize | final translate, applied last. |
| `symbolRotate` | number (deg) | rotates about the glyph centre; **does not affect layout**. |
| `symbolRepeat` | `false \| true \| number \| 'fixed'` | `true` = repeat count derived from data; `number` = fixed count, not cut by data; `'fixed'` = count derived from `symbolBoundingData` (data-independent — used for backgrounds). |
| `symbolRepeatDirection` | `'start' \| 'end'` | z-order of overlapping repeats and the index order for `animationDelay`. |
| `symbolMargin` | `number \| '%'`, optionally suffixed `'!'` | gap between repeats; default `'15%'`. Negative = overlap. `'!'` suffix means *also* add margin at both ends (otherwise the end glyphs touch the boundary). Ignored when `symbolRepeat` is a number. |
| `symbolClip` | boolean | clip the glyph (or the repeat run) at the data value, so the *clipped extent* encodes the value while the full glyph shows the total. |
| `symbolBoundingData` | `number \| [neg, pos]` | a **data value** converted to a pixel bound. Without repeat: it replaces the reference-bar length used to resolve percentage `symbolSize`. With repeat: it defines the repeat field. Array form gives separate negative/positive bounds. |
| `symbolPatternSize` | number, default 400 | the nominal px size of an image pattern used as `itemStyle.color.image`; the glyph is scaled `symbolSize / symbolPatternSize`. |

### 3.2 The layout math (`prepareBarLength` → `prepareSymbolSize` → `prepareLineWidth` → `prepareLayoutInfo`)

1. `boundingLength` = from `symbolBoundingData` (single or `[a,b]` picked by the sign of the bar),
   else the coord-system extent when repeating, else the reference bar's own length.
2. `pxSign` = ±1 derived from `boundingLength`'s sign **combined with** the axis' `inverse` flag
   and whether the value axis is x or y. This is the sign that flips glyphs for negative values.
3. `symbolScale = symbolSize / symbolPatternSize`, with the value-axis component multiplied by
   `(isHorizontal ? −1 : 1) · pxSign` so the glyph mirrors correctly.
4. `valueLineWidth`: because symbols are drawn with a scale transform and `strokeNoScale`, the
   border width is divided by `path.getLineScale()` then re-multiplied by the value-axis scale.
5. **Repeat solve** (the interesting part):
   - `unitLength = symbolSize[valueDim] + valueLineWidth`
   - `uLenWithMargin = unitLength + 2·margin`; `endFix = hasEndGap ? 0 : 2·margin`
   - `repeatTimes = floor((|boundingLength| + endFix) / uLenWithMargin)` unless a number was given
   - **then the margin is re-solved** so the run fills the field exactly:
     `margin = (|boundingLength| − repeatTimes·unitLength) / 2 / (hasEndGap ? repeatTimes : max(repeatTimes−1, 1))`
   - if `symbolRepeat` is `true` (not a number, not `'fixed'`), `repeatTimes` is then **re-cut** by
     `repeatCutLength` (the actual bar length) so the visible count encodes the data value
   - `pathLen = repeatTimes · uLenWithMargin − endFix`
6. `pathPosition[valueDim]` = `sizeFix` (`'start'`), `boundingLength − sizeFix` (`'end'`), or
   `boundingLength / 2` (`'center'`), where `sizeFix = pxSign · pathLen / 2`; then `symbolOffset`
   is added.
7. `barRectShape` (the invisible hit/marker rect) is stretched to cover whichever is longer, the
   reference bar or the glyph run. `clipShape` clips along the value axis at the bar length and is
   left wide open along the category axis.

Animation: per-glyph `animationDelay(dataIndex, params)` where `params.index` / `params.count` are
the *repeat* index/count — that's how the staggered fill-up demos are built.

---

## 4. `series.scatter` — symbols at points

`src/chart/scatter/{ScatterSeries,ScatterView,jitterLayout}.ts`.

**Draws**: one `Symbol` per datum (`SymbolDraw`), or one batched `LargeSymbolPath` in `large` mode.

- Full symbol option set as §1.4 (`symbol`, `symbolSize` default **10**, `symbolRotate`,
  `symbolKeepAspect`, `symbolOffset`, all with callbacks).
- `itemStyle.opacity` default `0.8`.
- **`large: boolean` / `largeThreshold: 2000`** — batched draw; `getProgressive()` returns 5000 and
  `getProgressiveThreshold()` 10000 when large. `getZLevelKey()` puts a big scatter on its own
  canvas layer (browser concept).
- **`clip: boolean`** default `true` — a symbol is removed only if its **centre** is outside; never
  half-drawn.
- `stack` is supported (`SeriesStackOptionMixin` on the option type).
- `brushSelector` = point containment.
- `progressive` / `progressiveThreshold` from the shared partial.
- Works on 7 coordinate systems (§0.1) — the widest reach of the family besides `custom`.

### 4.1 Jitter (new in **6.0.0**)

Configured **on the axis**, not the series: `xAxis/yAxis/singleAxis.jitter` (px, default 0),
`.jitterOverlap` (default `true`), `.jitterMargin` (default 2). Applies only to `scatter`, only on
a cartesian **ordinal/category** base axis or a `singleAxis`.

- `jitterOverlap: true` → `floatCoord + (rand − 0.5) · clamp(jitter, 0, bandWidth − 2r)`.
- `jitterOverlap: false` → a **greedy collision-avoidance packer**: for the fixed coordinate it
  keeps a list of already-placed `{fixedCoord, floatCoord, r}`, tries to place the new point in both
  the `+` and `−` direction (`placeJitterOnDirection`) respecting `2r + margin` separation, takes
  the smaller displacement; if the result moves more than `jitter/2` or beyond `bandWidth/2 − r`,
  it gives up and falls back to random jitter. Effectively a 1-D beeswarm.
- Runs as a `StageHandler` with `plan: createRenderPlanner()` and writes back into the
  `Float32Array` point buffer, so it is progressive-render aware (a 6.1.0 bug fix).

---

## 5. `series.effectScatter` — scatter with animated ripples

`src/chart/effectScatter/*` + `src/chart/helper/EffectSymbol.ts`.

Same data/coordinate/symbol surface as scatter, plus:

- **`effectType: 'ripple'`** — the only value.
- **`showEffectOn: 'render' | 'emphasis'`** — always animating vs. only on hover.
- **`rippleEffect`**:
  - `number` (default 3, since 5.2.0) — how many concentric rings
  - `period` (default 4, seconds) — one ring's full cycle
  - `scale` (default 2.5) — maximum ring radius as a multiple of the symbol
  - `brushType: 'fill' | 'stroke'`
  - `color` (4.4.0) — defaults to the symbol colour
  - implementation: `number` clones of the symbol path, each animating `scaleX/scaleY` from 0.5 to
    `scale/2` and `opacity` 1→0, with staggered delay `−i/number · period + effectOffset`, looping.
- `progressive: 0` (no progressive rendering), `clip: true`, `symbolSize` default 10.
- Changing `symbolType`, `period`, `rippleScale` or `rippleNumber` forces a rebuild
  (`DIFFICULT_PROPS`).
- No `large` mode.

---

## 6. `series.candlestick` (alias `series.k`) — OHLC boxes

`src/chart/candlestick/{CandlestickSeries,CandlestickView,candlestickLayout,candlestickVisual,preprocessor}.ts`
+ `chart/helper/whiskerBoxCommon.ts`.

**Data**: 2-D array, dimension order **OCLH** = `[open, close, lowest, highest]` (plus an optional
leading category/time dimension). Docs explicitly show remapping OHLC→OCLH with
`encode: {x: 0, y: [1, 4, 3, 2]}` rather than reordering the source.
`defaultValueDimensions = [open, close, lowest, highest]`, all `defaultTooltip: true`.

**Draws**: one `Path` per datum whose `ends[]` array holds 4 body corners + 4 whisker endpoints
(`[highest, ocHigh, lowest, ocLow]`), all `subPixelOptimize`d on the category axis so 1 px lines
stay crisp. Below a computed `candleWidth ≤ 1.3` the layout flags `isSimpleBox` and the view
degenerates to a bare vertical line.

### 6.1 Options

- **`layout: 'horizontal' | 'vertical'`** (`LayoutOrient`). Auto-derived by
  `whiskerBoxCommon.getInitialData`: a `category` axis forces the orientation; with two value axes
  it defaults to `'horizontal'` unless yAxis is `time` (then `'vertical'`). The computed value is
  deliberately **not** written back to `option.layout` (idempotency).
- **`barWidth` / `barMinWidth` / `barMaxWidth`** — px or `'%'` of band width. `calculateCandleWidth`
  clamps: `barMaxWidth` default = bandWidth, `barMinWidth` default = 1. (No `barGap`/
  `barCategoryGap`; candlesticks don't share a band with each other.)
- **Colours** (`candlestickVisual.ts`) — a genuine three-way switch on
  `sign = getSign(open, close)`:
  - `itemStyle.color` (default `#eb5454`) / `borderColor` (same) → bullish, `close > open`
  - `itemStyle.color0` (default `#47b262`) / `borderColor0` → bearish
  - **`itemStyle.borderColorDoji`** → `close === open`; when set, the layout computes a `sign === 0`
    class. `stroke` falls back to `fill` when the border colour is null.
  - `borderWidth` default 1, emphasis 2.
- `emphasis` / `blur` (5.6.0) and `select` (5.0.0) each carry the full 3-colour itemStyle set.
- **`large: true` by default**, `largeThreshold: 600`. The large path packs
  `[sign, x, yHigh, yLow]` per datum into a `Float32Array` and draws lines.
- `progressive: 3000`, `progressiveThreshold: 10000`, `progressiveChunkMode: 'mod'`.
- **`clip: boolean`** default `true`; since 6.1.0 overflow is geometrically clipped.
- `animationEasing: 'linear'`, `animationDuration: 300`.
- `brushSelector` uses a precomputed `brushRect` per datum (low→high × candleWidth).
- `getShadowDim() === 'open'` — that is the dimension a `dataZoom` slider draws as its background
  sparkline.
- `preprocessor.ts` rewrites `type: 'k'` → `'candlestick'`.

---

## 7. `series.boxplot` — five-number summary

`src/chart/boxplot/{BoxplotSeries,BoxplotView,boxplotLayout,boxplotTransform,prepareBoxplotData}.ts`.

**Data**: `[min, Q1, median, Q3, max]` per item (`defaultValueDimensions` names them exactly that,
and the doc notes that what "min/max" *mean* is up to the user — usually the whisker bounds).

**Draws**: one `Path` per datum from a 12-point `ends` array = 4 box corners + 4 whisker verticals
+ 3 horizontal cross-bars (min cap, max cap, median line). `visualDrawType: 'stroke'` (the palette
colour goes to the outline, not the fill); default `itemStyle` is `{color: neutral00 (white),
borderWidth: 1}`.

### 7.1 Layout (`boxplotLayout.ts`)

Per base axis, across all boxplot series on it:
- `availableWidth = bandWidth · 0.8 − 2`
- `boxGap = availableWidth / seriesCount · 0.3`
- `boxWidth = (availableWidth − boxGap·(seriesCount−1)) / seriesCount`
- each series' final width is `clamp(boxWidth, boxWidth[0], boxWidth[1])` where
  **`boxWidth: [min, max]`** (default `[7, 50]`, each entry px or `'%'` of band)
- offsets march left-to-right from `boxWidth/2 − availableWidth/2`

Other options: `layout: 'horizontal' | 'vertical'` (same auto-derivation as candlestick),
`clip: true` (overflow geometrically clipped), `emphasis.scale: true` with a default shadow,
`animationDuration: 800`.

### 7.2 The `boxplot` dataset transform

`dataset: [{source: number[][]}, {transform: {type: 'boxplot', config: {...}}}]` produces **two**
outputs from one raw array-of-arrays:
1. `{dimensions: ['ItemName','Low','Q1','Q2','Q3','High'], data: boxData}` → feeds the boxplot series
2. `{data: outliers}` → `[itemName, value]` pairs, conventionally fed to a `scatter` series

`config`:
- **`boundIQR`** — default `1.5`. `low = max(min, Q1 − boundIQR·IQR)`,
  `high = min(max, Q3 + boundIQR·IQR)`. `'none'` or `0` → use the raw extremes and emit no outliers.
- **`itemNameFormatter`** — `'expr{value}'` template or `({value}) => string`; default is the index.

Quantiles come from `util/number.quantile` on a sorted copy (`asc`). Requires
`sourceFormat === 'array_rows'` or it throws.

---

## 8. `series.heatmap` — three genuinely different renderers

`src/chart/heatmap/{HeatmapSeries,HeatmapView,HeatmapLayer}.ts`.

Heatmap **requires a `visualMap`** to colour anything. Which renderer runs depends entirely on the
coordinate system.

### 8.1 Cartesian2d / calendar / matrix — cell rectangles

`_renderOnGridLike()`. One `graphic.Rect` per datum.
- Cartesian requires **both axes to be `type: 'category'` with `boundaryGap: true` (`onBand`)** —
  `__DEV__` throws otherwise. Cell size = `calcBandWidth(axis).w + 0.5` per axis (the +0.5 hides
  seams), centred on `dataToPoint`.
- Data outside the axis scale extent is skipped, NaN values skipped.
- Calendar: dimensions are `[time, value]`; the calendar coord system supplies the cell rect.
- Matrix: `coordSys.dataToLayout([x, y])` supplies the rect.
- `itemStyle` applies fully here, including **`borderRadius`** (5.3.1) — per-item override
  supported. `label` applies here. `emphasis` / `blur` / `select` apply.
- Progressive/incremental rendering supported on grid-like systems.

### 8.2 Geo — a real density heat field

`_renderOnGeo()` + `HeatmapLayer.ts`. This is **not** vector drawing:
1. Build an offscreen canvas the size of the geo view rect.
2. Pre-render a **radial-gradient circular brush** of radius `pointSize + blurSize` (black,
   alpha falling off over `blurSize`).
3. `drawImage` the brush once per point with `globalAlpha = normalize(value)` — accumulating
   alpha is the density estimate.
4. `getImageData`, then **per-pixel** map `alpha` → a 256-entry precomputed gradient LUT
   (separate LUTs for `inRange` and `outOfRange` per the visualMap), and remap alpha into
   `[minOpacity, maxOpacity]`.
5. `putImageData`, and blit the canvas as an image element.

Options that only apply here: **`pointSize`** (20), **`blurSize`** (30), **`minOpacity`** (0),
**`maxOpacity`** (1). `itemStyle` and `label` do **not** apply. `preventIncremental()` returns true
for lng/lat coord systems.

---

## 9. `series.themeRiver` — stream graph

`src/chart/themeRiver/{ThemeRiverSeries,ThemeRiverView,themeRiverLayout}.ts`.

**Only** coordinate system: `singleAxis` (usually a time axis). Layout rect is borrowed from the
single axis, adjusted by `left`/`top`/`right`/`bottom`/`width`/`height` (defaults `5%`) and
**`boundaryGap: ['10%','10%']`** in the axis-orthogonal direction.

**Data**: flat triples `[date, value, name]`. `name` is the layer identity.

### 9.1 Data conditioning (`fixData`)

Every layer must have a datum at every time key, or the stacked baseline breaks. `fixData` groups
by `name`, collects the union of time keys, and **synthesises `[time, 0, name]` rows** for gaps.
Docs warn that the "main river" must span the full time range.

### 9.2 The stream layout (`computeBaseline`)

Explicitly "inspired by Lee Byron's *Stacked Graphs — Geometry & Aesthetics*", but implemented as
the simple symmetric variant, **not** the full wiggle minimisation:
- `sums[i] = Σ_layers value(layer, i)`; `max = max(sums)`
- `y0[i] = (max − sums[i]) / 2` — i.e. each time slice is **centred** on the band
- `ky = height / max` (a second pass recomputes `max` as `max(sums[i] + y0[i])`)
- layers then stack upward from `y0`, each item storing `{layerIndex, x, y0, y}`

**Drawing**: one `ECPolygon` (the same class the line-area uses) per layer, with a hard-coded
`smooth: 0.4` and `smoothConstraint: false` — that is where the organic ribbon shape comes from.
Reveal animation is a growing rect clip path.

**Labels**: one per layer, placed at the layer's first data point, offset left by `label.margin`
and vertically centred in the ribbon (`y0 + y/2`). The code comments "TODO More label position
options" — there is no `label.position` here.

`colorBy` defaults to `'data'`; legend selection works per layer via `LegendVisualProvider`.
No `markPoint`/`markLine`/`markArea`.

---

## 10. `series.custom` — the universal escape hatch

`src/chart/custom/{CustomSeries,CustomView}.ts` (57 KB view).

**The single most important series to understand for a port**, because it is how ECharts users
build gantt charts, x-range charts, hexbins, error bars, violin plots, bullet charts, funnel-ish
shapes and anything else the built-ins don't cover. It is a *retained-mode scene-graph description
returned from a callback*.

```
renderItem(params, api) -> element descriptor | undefined
```
called once per data item (plus once per item on update).

### 10.1 `params` (first argument)

`context` (a scratch object with per-render lifetime), `seriesId`, `seriesName`, `seriesIndex`,
`dataIndex`, **`dataIndexInside`** (index within the current dataZoom window — the one you pass
back to `api.*`), `dataInsideLength`, `actionType`, `encode` (dimension→index map), `itemPayload`,
and **`coordSys`** — whose shape varies by system:
- `cartesian2d`: `{type, x, y, width, height}` (the grid rect)
- `calendar`: `{type, x, y, width, height, cellWidth, cellHeight, rangeInfo: {start, end, weeks, dayCount}}`
- `matrix`: `{type, x, y, width, height}`
- `geo`: `{type, x, y, width, height, zoom}`
- `polar`: `{type, cx, cy, r, r0}`
- `singleAxis`: `{type, x, y, width, height}`

`prepareCustoms` is registered for exactly six systems: `cartesian2d`, `geo`, `single`, `polar`,
`calendar`, `matrix` (plus an extension hook `coordSys.prepareCustoms` for third-party systems
like bmap).

### 10.2 `api` (second argument) — the whole bridge

| method | returns |
|---|---|
| `api.value(dim, dataIndexInside?)` | parsed numeric value of a dimension |
| `api.ordinalRawValue(dim, idx?)` | the raw category string behind an ordinal value |
| `api.coord(data, opt?)` | **data → pixel**, same contract as `chart.convertToPixel` |
| `api.layout(data, opt?)` | **new in 6.0.0** — data → a full layout rect/anchor, same as `chart.convertToLayout` (this is what makes matrix/calendar cells usable) |
| `api.size(dataSize, dataItem?)` | **a data *range* → a pixel size**; second arg needed for non-linear (log, polar) axes where size varies by position |
| `api.style(extra?, idx?)` | resolved `itemStyle` + visual-mapped colour, ready to assign to `style` |
| `api.styleEmphasis(extra?, idx?)` | same for the emphasis state |
| `api.visual(visualType, idx?)` | one visual channel: `'color'`, `'borderColor'`, `'symbol'`, `'symbolSize'`, `'symbolKeepAspect'`, `'legendIcon'`, `'visualMeta'`, `'liftZ'`, `'decal'` |
| `api.barLayout({count, barWidth, barMaxWidth, barMinWidth, barGap, barCategoryGap})` | `[{width, offset, offsetCenter}, ...]` — reuses the real bar layout solver (§2.1) so custom glyphs align with real bars |
| `api.currentSeriesIndices()` | series indices surviving legend filtering |
| `api.font({fontStyle, fontWeight, fontSize, fontFamily})` | a CSS font shorthand string |
| `api.getWidth()` / `api.getHeight()` | container size |
| `api.getZr()` | the zrender instance — **browser-bound escape hatch** |
| `api.getDevicePixelRatio()` | DPR — browser-bound |

### 10.3 What `renderItem` may return

A single element descriptor, or a `group` with `children`. Element `type` values:

`'group'`, `'path'` (SVG `pathData`/`d` + `layout: 'center' | 'cover'` + `x/y/width/height`
auto-fit), `'image'`, `'text'`, `'compoundPath'`, and the built-in shapes: `'rect'`, `'circle'`,
`'ring'`, `'sector'`, `'arc'`, `'polygon'`, `'polyline'`, `'line'`, `'bezierCurve'`, `'ellipse'`.
**15 element types.**

Per element: `id`, `name`, `info` (arbitrary payload surfaced in click events), `shape` (type
specific), `style`, `x`/`y`/`scaleX`/`scaleY`/`rotation`/`originX`/`originY`/`skewX`/`skewY`,
`z`/`z2`/`zlevel`, `invisible`, `ignore`, `silent`, `textConfig` + `textContent` (an attached text
element, or `false` to remove), `clipPath` (any path element, or `false`), `emphasis`/`blur`/
`select` state overrides (`style: false` removes the state), `focus` (`'none'|'self'|'series'|
number[]`), `blurScope`, `emphasisDisabled`, `tooltipDisabled`, `autoBatch`, `extra` (custom
animatable props), `morph` (shape-morphing on type change), `$mergeChildren` (`false | 'byName' |
'byIndex'`).

Animation control per element: `transition` (which props tween; defaults to `['x','y']`),
`enterAnimation` / `updateAnimation` / `leaveAnimation`, `during(api)` callback, and
`keyframeAnimation` (arrays of `{duration, delay, easing, loop, keyframes: [{percent, easing,
...props}]}`).

### 10.4 Series-level custom options

`renderItem` (function **or a registered string name** via `customSeriesRegister.ts`),
`itemPayload` (extra data handed to renderItem), `coordinateSystem` including **`'none'`**
(free-floating, positioned in raw pixels), `clip: boolean` (cartesian2d & polar only), `encode`,
`dimensions`, `dataZoom` co-operation (docs recommend `dataZoom.filterMode: 'weakFilter'` so a
datum isn't dropped when only one of its dimensions leaves the window). `itemStyle`, `label`,
`emphasis.itemStyle/label` are all marked **deprecated** at series level — use `api.style()`.

Events can be scoped to a named sub-element: `chart.on('click', {element: 'aaa'}, handler)`.

---

## Porting notes

Classification for an immediate-mode BGRABitmap canvas on a desktop window.
**NATURAL** = draws with paths/fills/strokes/text you already have.
**HEAVY** = portable but you must implement a named algorithm.
**BROWSER-BOUND** = depends on DOM/CSS/canvas-imperative/JS semantics; needs a native rethink or is
out of scope.

### Cross-cutting

| capability | class | note |
|---|---|---|
| Cartesian2d data→pixel mapping, 10 series on it | NATURAL | |
| Polar layout for line/bar/scatter | NATURAL | sector + arc paths |
| singleAxis (themeRiver), calendar, matrix, geo backings | HEAVY | each is a separate coord-system implementation; matrix/calendar-hosted grids (`coordinateSystemUsage: 'box'`) are a nested-layout feature |
| Data formats: 1-D, 2-D, object items, dataset + `encode` + `seriesLayoutBy` | NATURAL | plain data plumbing; `encode` is the piece people forget |
| 4 states (normal/emphasis/blur/select) + `focus`/`blurScope` fan-out | HEAVY | requires a per-element state machine and a "who else fades" query over the coordinate system |
| `stack` + `stackStrategy` (4 modes) + `stackOrder` | HEAVY | sign-aware cumulation with per-index/per-category grouping; adds 2 derived dimensions |
| `sampling`: lttb / minmax / average / min / max / sum + custom fn | HEAVY | **LTTB** is the only non-trivial one (bucketed largest-triangle area) |
| `large` batched paths, `progressive`, `progressiveChunkMode` | BROWSER-BOUND (motivation) / NATURAL (technique) | the *frame-budget streaming* is a JS-main-thread concern; the batched single-path draw is a legitimate perf technique to keep |
| `zlevel` = separate canvas layer, `hoverLayerThreshold`, `getZLevelKey` | BROWSER-BOUND | map to your own cache/back-buffer strategy or drop |
| `cursor` (CSS cursor name) | BROWSER-BOUND | map to LCL `TCursor` |
| Gradients (linear/radial, `global`), image pattern fills | NATURAL | BGRABitmap has gradients; image patterns need a texture brush |
| `decal` accessibility patterns (dashArrayX/Y matrices, rotation, tiling) | HEAVY | it is a procedural tile generator, then a pattern fill |
| Label engine: 14 positions, `formatter` templates, `rich` fragments, `overflow`/`ellipsis` | HEAVY | `rich` (per-fragment font/box/background) is a mini text-layout engine |
| `labelLayout.hideOverlap` / `moveOverlap` | HEAVY | greedy rect-overlap resolution over all labels |
| `labelLayout.draggable` | BROWSER-BOUND-ish | pointer interaction, doable natively but it's an interaction feature not a drawing one |
| `markPoint` / `markLine` / `markArea` incl. `type: min/max/average/median` | NATURAL + light stats | the statistics are trivial; the positioning modes (coord / axis value / pixel) are plumbing |
| `universalTransition` (cross-series morph, `divideShape: split/clone`) | HEAVY | needs shape-splitting + path correspondence; realistically out of scope for v1 |
| Easing library, per-item `animationDelay(index, count)` | NATURAL | timer-driven interpolation |
| `formatter` / `symbolSize` / `symbol` / `color` **callbacks** | BROWSER-BOUND (as written) | JS closures; the native analogue is a Pascal event/anonymous method — design equivalents deliberately |
| `dataset` transforms as a pipeline | HEAVY | a small ETL layer |

### `line`

| capability | class | note |
|---|---|---|
| Polyline + per-point symbols | NATURAL | |
| `smooth` (0..1) with segment-ratio control points + `smoothConstraint` clamping | HEAVY | reimplement `poly.ts drawSegment` exactly or curves will differ visibly |
| `smoothMonotone: 'x' \| 'y'` | HEAVY | same code path, axis-aligned control points |
| `step: start / middle / end` | NATURAL | point-list expansion (1 or 2 injected vertices) |
| `areaStyle` + `origin: auto/start/end/number` | NATURAL | close the path to a baseline |
| Stacked area (baseline = previous series' `stackedOver` polyline) | HEAVY | depends on the stacking engine |
| `connectNulls` | NATURAL | segment splitting / bridging |
| `clip` with *per-element-kind* semantics (line clipped, symbol dropped-by-centre) | NATURAL | two different rules, easy to get wrong |
| `showSymbol`, `showAllSymbol: auto` interval strategy | HEAVY(light) | `'auto'` samples 5 points then falls back to the axis label interval set |
| `endLabel` + `valueAnimation` (value interpolated at the animating clip edge) | HEAVY | needs `cubicRootAt` to invert the curve at the clip x |
| visualMap → screen-space `LinearGradient` along an axis (`getVisualGradient`) | NATURAL | one stroke with a gradient; BGRABitmap can do this |
| `triggerEvent: line/area` hit-testing on stroke and fill | HEAVY | stroke hit-test needs distance-to-polyline; fill needs point-in-polygon |
| `emphasis.lineStyle.width: 'bolder'` | NATURAL | |
| Point-level add/remove diff animation (`lineAnimationDiff`) | HEAVY | |
| Polar line (no `step`, no `endLabel`) | NATURAL | |

### `bar`

| capability | class | note |
|---|---|---|
| Rect bars, horizontal/vertical by axis role, negative values | NATURAL | |
| `calcBarWidthAndOffset`: bandWidth → per-stack widths/offsets with `barWidth`/`barMaxWidth`/`barMinWidth`/`barGap`/`barCategoryGap`, min-outranks-max, adaptive default categoryGap | HEAVY | ~120 lines of two-pass solving; **cross-series, shared per axis** |
| `barMinHeight`, `barMinAngle` | NATURAL | |
| `itemStyle.borderRadius` (4 corners) on rects | NATURAL | |
| Polar sector bars + sector `borderRadius` | HEAVY | sector-with-rounded-corners path construction |
| `roundCap` (Sausage shape) | HEAVY | custom arc-with-round-caps path |
| `showBackground` + `backgroundStyle` | NATURAL | |
| `large` batched rect path + throttled linear hit-scan | NATURAL | |
| **`realtimeSort` (bar race)**: order derived from *animated pixel length* each frame, dispatched as an ordinal-scale reorder, gated by in-view-only comparison | HEAVY | the trick is that the axis order changes, not the data; needs a per-frame hook and animated axis labels |
| `clip` (6.1.0 geometric clipping) | NATURAL | |
| Polar label positions (`start/insideStart/middle/insideEnd/end`) | NATURAL | |
| `label.valueAnimation` (interpolated number text) | NATURAL | |

### `pictorialBar`

| capability | class | note |
|---|---|---|
| Glyph instead of rect, reference-bar layout | NATURAL | |
| `symbolSize` percent resolution (category size vs boundingLength, repeat-dependent) | HEAVY | |
| `symbolPosition` start/end/center + `symbolOffset` | NATURAL | |
| `symbolRepeat` (true / number / `'fixed'`) with **margin re-solve** then **cut by data** | HEAVY | the two-stage solve in `prepareLayoutInfo` is the whole feature |
| `symbolMargin` incl. the `'!'` end-gap suffix and negative overlap | HEAVY | part of the same solve |
| `symbolRepeatDirection` (z-order + animation index order) | NATURAL | |
| `symbolClip` (clip the glyph run at the data value) | NATURAL | rect clip on the value axis |
| `symbolBoundingData` incl. `[neg, pos]` array form | HEAVY | drives both sizing and the repeat field |
| `symbolPatternSize` + image-pattern glyph fill | HEAVY | texture brush scaled by `symbolSize/patternSize` |
| `pxSign` derivation (axis inverse × x/y × sign) for negative-value mirroring | HEAVY | easy to get wrong; it's a 4-way truth table |
| `symbolRotate` (rotate without affecting layout) | NATURAL | |
| Per-repeat `animationDelay(index, count)` | NATURAL | |
| `path://` / `image://` glyphs | HEAVY | needs an SVG path-data parser (worth building once — `symbol`, `custom`, `markPoint`, `decal` and legend icons all use it) |

### `scatter` / `effectScatter`

| capability | class | note |
|---|---|---|
| Symbols at points, 8 built-in shapes + `empty*` variants | NATURAL | |
| `symbolSize`/`symbol`/`symbolRotate` callbacks | BROWSER-BOUND (as JS) → native event equivalent | |
| `large` batched symbol path | NATURAL | |
| `clip` by symbol centre | NATURAL | |
| Scatter on 7 coordinate systems | HEAVY | per coord system |
| **Jitter, `jitterOverlap: true`** (random within band, clamped by `bandWidth − 2r`) | NATURAL | |
| **Jitter, `jitterOverlap: false`** (greedy bidirectional collision packer + give-up fallback) | HEAVY | 1-D beeswarm; the fallback rule matters for parity |
| Ripple effect: N clones, staggered `scale`+`opacity` loops, `period`/`scale`/`number`/`brushType`/`color` | NATURAL | pure timer + redraw; cheap on an immediate-mode canvas |
| `showEffectOn: 'emphasis'` | NATURAL | |

### `candlestick`

| capability | class | note |
|---|---|---|
| OCLH box + two whiskers from an 8-point `ends` array | NATURAL | |
| `layout: horizontal/vertical` auto-derivation from axis types | NATURAL | |
| `barWidth`/`barMinWidth`/`barMaxWidth` + band width clamping | NATURAL | |
| Up/down/**doji** three-way colour switch (`color`, `color0`, `borderColor`, `borderColor0`, `borderColorDoji`) | NATURAL | |
| `subPixelOptimize` on the category axis (crisp 1 px lines) | NATURAL | worth copying — your `TTyPainter` will need the same half-pixel discipline |
| `isSimpleBox` degeneration at `candleWidth ≤ 1.3` | NATURAL | |
| `large` mode `[sign, x, yHigh, yLow]` packed lines | NATURAL | |
| OHLC→OCLH remap via `encode` | NATURAL | |
| `getShadowDim()` feeding a dataZoom sparkline | NATURAL | |

### `boxplot`

| capability | class | note |
|---|---|---|
| 12-point 5-number glyph (box + whiskers + 3 cross-bars) | NATURAL | |
| Multi-series band packing (`availableWidth = band·0.8 − 2`, `boxGap = avail/n·0.3`, clamp by `boxWidth: [min,max]`) | NATURAL | small closed-form solve |
| `layout: horizontal/vertical` | NATURAL | |
| `visualDrawType: 'stroke'` (palette colours the outline) | NATURAL | |
| **`boxplot` dataset transform**: quantiles, `boundIQR` whisker rule, dual output (boxData + outliers), `itemNameFormatter` | HEAVY(light) | ~40 lines: sort, `quantile`, IQR bounds, outlier partition. Very high value/effort ratio. |

### `heatmap`

| capability | class | note |
|---|---|---|
| Cartesian cell rects (`bandWidth + 0.5` seam fix), category-axis + `onBand` requirement | NATURAL | |
| `itemStyle.borderRadius` on cells, per-item override, labels in cells | NATURAL | |
| Calendar-backed and matrix-backed cells | HEAVY | needs those coord systems |
| **Geo density field**: radial-gradient brush accumulation + `getImageData` per-pixel LUT recolour + alpha remap | HEAVY | this is *exactly* the kind of thing BGRABitmap is good at — direct pixel access, no `getImageData` needed. Algorithm: additive alpha splatting then a 256-entry gradient LUT. |
| `pointSize` / `blurSize` / `minOpacity` / `maxOpacity` | NATURAL (within the above) | |
| Hard dependency on `visualMap` for colour | HEAVY | you need the visualMap component (continuous + piecewise, inRange/outOfRange) before heatmap means anything |

### `themeRiver`

| capability | class | note |
|---|---|---|
| `fixData` zero-filling so every layer spans every time key | NATURAL | |
| Symmetric centred baseline (`y0[i] = (max − sums[i])/2`) — the simplified Byron stream layout | NATURAL | genuinely simple; **not** the wiggle-minimising variant |
| Ribbon drawn as a closed smooth polygon (`smooth: 0.4`, `smoothConstraint: false`) | HEAVY | reuses the line smoothing code — build that once |
| singleAxis dependency (incl. time axis) | HEAVY | needs the singleAxis coord system |
| Per-layer left-anchored labels, vertically centred | NATURAL | |
| Growing-rect reveal animation | NATURAL | |

### `custom`

| capability | class | note |
|---|---|---|
| The `renderItem(params, api)` callback contract itself | BROWSER-BOUND *as a JS API*, but the **concept is the single highest-value thing to port** — expose it as a Pascal event `TTyRenderItemEvent(const AParams; const AApi): ITyShapeList` | |
| 15 element descriptors (group/path/image/text/compoundPath/rect/circle/ring/sector/arc/polygon/polyline/line/bezierCurve/ellipse) | NATURAL | you already draw all of these |
| `api.coord` / `api.layout` / `api.size` (data↔pixel, incl. non-linear axes) | NATURAL | you must expose them anyway |
| `api.style` / `api.styleEmphasis` / `api.visual` | NATURAL | once the visual-mapping pipeline exists |
| `api.barLayout` (reuse the real bar solver from a callback) | HEAVY | only after §2.1 exists |
| `api.font` (CSS font shorthand string) | BROWSER-BOUND | return a font record, not a string |
| `api.getZr()` / `api.getDevicePixelRatio()` | BROWSER-BOUND | drop / replace with canvas + scaling factor |
| `path://` SVG path data with `layout: 'center' \| 'cover'` auto-fit | HEAVY | SVG path parser + fit transform |
| `clipPath` per element (any path shape) | HEAVY | arbitrary-path clipping on BGRABitmap needs a mask |
| `textContent` + `textConfig` (attached labels with auto-placement) | NATURAL | |
| `$mergeChildren: 'byName' \| 'byIndex'`, element diffing by `id`/`name` | HEAVY | retained-mode reconciliation |
| `transition` / `enterAnimation` / `updateAnimation` / `leaveAnimation` / `during` / `keyframeAnimation` | HEAVY | a general property-tween engine over arbitrary element props |
| `morph: true` shape morphing between path types | BROWSER-BOUND-ish / HEAVY | path-correspondence morphing; realistically out of scope |
| `info` payload surfaced in events, `chart.on('click', {element: 'name'})` | NATURAL | |
| `autoBatch`, `silent`, `ignore`, `invisible`, `z2` | NATURAL | |

### Recommended build order implied by the above

1. Cartesian2d + category/value axes + `dataToPoint` + the label engine (everything needs it).
2. `line` (polyline, symbols, `step`, `areaStyle`, `connectNulls`, `clip`) and `bar` **without**
   the shared width solver — then add `calcBarWidthAndOffset`, since it unlocks bar, pictorialBar,
   candlestick and boxplot widths and `api.barLayout`.
3. `smooth`/`smoothMonotone` from `poly.ts` — reused by line-area **and** themeRiver.
4. The stacking engine — unlocks stacked line/area/bar/scatter.
5. `scatter` (+ ripple ⇒ `effectScatter` almost free), then the SVG `path://` parser, which unlocks
   custom symbols, `pictorialBar`, `decal` and `custom`'s `path` element in one go.
6. `candlestick` + `boxplot` (+ the boxplot dataset transform — tiny, high value).
7. `visualMap`, then `heatmap` (cartesian first; the geo density field is a separate, self-contained
   pixel-splatting job well suited to BGRABitmap).
8. `custom` last, as the escape hatch, once `api.coord`/`api.size`/`api.style` already exist for
   internal reasons.
9. `themeRiver` only if `singleAxis` is on the roadmap.
