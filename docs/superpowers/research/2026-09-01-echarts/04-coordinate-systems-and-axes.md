# Apache ECharts 6.1.0 — Coordinate Systems and Axes

Survey for a Free Pascal / Lazarus custom-drawn chart control (BGRABitmap, immediate-mode canvas).
Sources read: `D:/Projects/echarts/src/coord/*`, `src/scale/*`, `src/component/axis/*`,
`src/component/axisPointer/*`, and the option reference in `D:/Projects/echarts-doc/en/option/`
(`component/grid.md`, `x-axis.md`, `y-axis.md`, `axis-common.md` (1497 lines, the master partial),
`polar.md`, `angle-axis.md`, `radius-axis.md`, `radar.md`, `single-axis.md`, `calendar.md`,
`parallel.md`, `parallel-axis.md`, `geo.md`, `geo-common.md`, `matrix.md`, `axisPointer.md`,
plus `partial/coord-sys.md`, `partial/rect-layout-width-height.md`, `partial/circular-layout.md`,
`partial/view-coord-sys.md`, `partial/axisPointer-common.md`, `partial/roam.md`).

Version confirmed from `package.json`: **6.1.0**.

---

## 1. Inventory: the coordinate systems ECharts ships

`registerCoordinateSystem` is called exactly **9 times** in `src/` (grep-verified):

| # | Registered name | Source | Master class | Data dimensions | Notes |
|---|---|---|---|---|---|
| 1 | `cartesian2d` | `coord/cartesian/Grid.ts` | `Grid` (master) -> `Cartesian2D` (per x/y pair) | `['x','y']` | The rectangular grid; N sub-cartesians per grid |
| 2 | `polar` | `coord/polar/polarCreator.ts` | `Polar` | `['radius','angle']` | |
| 3 | `geo` | `coord/geo/geoCreator.ts` | `Geo extends View` | `['lng','lat']` | GeoJSON **or** SVG source |
| 4 | `single` | `coord/single/singleCreator.ts` | `Single` | `['single']` | One axis, one strip |
| 5 | `parallel` | `coord/parallel/parallelCreator.ts` | `Parallel` | dynamic (`dim0..dimN`) | N vertical/horizontal axes |
| 6 | `radar` | `coord/radar/Radar.ts` | `Radar` | dynamic (`indicator_0..N`) | N independent radial axes |
| 7 | `calendar` | `coord/calendar/Calendar.ts` | `Calendar` | `['time','value']` | |
| 8 | `matrix` | `coord/matrix/Matrix.ts` | `Matrix` | `['x','y','value']` (x,y ordinal) | **new in v6.0** |
| 9 | `graphView` | `chart/graph/install.ts` | `View` | free 2-D | Pan/zoom viewport for force-layout graph/sankey |

Plus the pseudo-system `coordinateSystem: 'none'` / `null` (component lays itself out against the
canvas box), and `View` (`coord/View.ts`) which is the shared roam/zoom transform engine underneath
`geo` and `graphView`.

`echarts-gl` adds `grid3D`, `geo3D`, `globe`, `mapbox`, `cartesian3D` — **out of scope here and
BROWSER-BOUND (WebGL)**. Third-party `bmap`/`amap`/`leaflet` coordinate systems are tile-map
overlays — also browser-bound.

### 1.1 Which series bind to which system

Reproduced from the authoritative matrix in `partial/coord-sys.md` (rewritten for v6.0).

| Series | none | cartesian2d | polar | geo | singleAxis | radar | parallel | calendar | matrix |
|---|---|---|---|---|---|---|---|---|---|
| line | | yes | yes | | | | | via grid | via grid |
| bar | | yes | yes | | | | | via grid | via grid |
| pictorialBar | | yes | yes | | | | | via grid | via grid |
| scatter | | yes | yes | yes | yes | | | yes | yes |
| effectScatter | | yes | yes | yes | yes | | | yes | yes |
| heatmap | | yes | | yes | | | | yes | yes |
| boxplot | | yes | | | | | | via grid | via grid |
| candlestick | | yes | | | | | | via grid | via grid |
| lines | | yes | yes | yes | yes | | | via geo | via geo |
| map | yes (creates own geo) | | | yes | | | | yes | yes |
| radar | | | | | | yes | | via radar | via radar |
| parallel | | | | | | | yes | via parallel | via parallel |
| themeRiver | | | | | yes | | | via singleAxis | via singleAxis |
| graph | yes (View) | yes | yes | yes | | | | yes | yes |
| pie | yes | yes (box) | yes (box) | yes (box) | yes (box) | | | yes | yes |
| tree / treemap / sunburst / sankey / funnel / gauge | yes | | | | | | | yes | yes |
| chord | yes | yes | yes | yes | yes | | | yes | yes |
| custom | yes | yes | yes | yes | yes | | yes | yes | yes |

Confirmed against source defaults: `BaseBarSeries`/`LineSeries`/`ScatterSeries`/`HeatmapSeries`/
`BoxplotSeries`/`CandlestickSeries`/`CustomSeries` default `coordinateSystem: 'cartesian2d'`;
`LinesSeries`/`MapSeries` default `'geo'`; `ThemeRiverSeries` defaults `'singleAxis'`.
`HeatmapSeries` declares `'cartesian2d' | 'geo' | 'calendar' | 'matrix'` — **no polar heatmap**.

### 1.2 The v6 nesting model (the big architectural change)

New in 6.0, every component gets three options (`partial/coord-sys.md`):

- `coordinateSystem: 'none'|'cartesian2d'|'polar'|'geo'|'singleAxis'|'parallel'|'calendar'|'matrix'`
- `coordinateSystemUsage: 'data' | 'box'`
  - `'data'` — each `series.data[i]` is mapped through the system (the classic behaviour).
  - `'box'` — the **whole component** is laid out as a rectangle/anchor inside a cell of the host
    system. This is how a `grid` (a whole cartesian chart) can live inside one cell of a `matrix`
    or `calendar` -> sparkline grids.
- `coord` — the locator handed to the host system when usage is `'box'` (same format as
  `chart.convertToPixel`'s second argument).

Consequence: `grid`, `polar`, `geo`, `singleAxis`, `parallel`, `radar`, and *any* plain component
(`legend`, `dataZoom`, `title`, `toolbox`, `timeline`, `visualMap`, `thumbnail`) can be laid out
**inside** a `matrix` or `calendar` cell. Coordinate systems became composable containers.
`calendar` and `matrix` themselves can only be hosted by `'none'`.

---

## 2. Grid — the cartesian2d container

`grid` is the rectangle; `xAxis` + `yAxis` pairs inside it form `Cartesian2D` instances.
**Multiple grids per chart are allowed** (no limit since ECharts 3). One axis can be shared by
several cartesians (1 xAxis + 2 yAxis = 2 cartesians).

| Option | Type / values | Semantics |
|---|---|---|
| `grid.show` | boolean = `false` | Paint the grid background/border at all |
| `grid.left/right/top/bottom` | number px, `'x%'`, `'auto'` | defaults `'10%'`, `'10%'`, `60`, `60` |
| `grid.width/height` | number px, `'x%'`, `'auto'` | derived if omitted |
| `grid.backgroundColor` | Color = `'transparent'` | needs `show:true` |
| `grid.borderColor` | Color = `'#ccc'` | needs `show:true` |
| `grid.borderWidth` | number = 1 | |
| `grid.shadowBlur/Color/OffsetX/OffsetY` | | needs `show:true` |
| `grid.opacity` | 0..1 = 1 | background + border only |
| `grid.z` / `zlevel` | number | z-order; `zlevel` = separate canvas layer (browser concept) |
| `grid.containLabel` | boolean = `false` | **deprecated in 6.0** |
| `grid.outerBoundsMode` | `'auto'` \| `'none'` \| `'same'` | v6.0 replacement |
| `grid.outerBounds` | `{left,top,right,bottom,width,height}` | the constraint rect (defaults 0 all round) |
| `grid.outerBoundsContain` | `'auto'` \| `'all'` \| `'axisLabel'` | whether the axis *name* is constrained too |
| `grid.tooltip` | tooltip config | per-grid tooltip |
| `grid.coordinateSystem` | `'none'`\|`'calendar'`\|`'matrix'` (v6) | grid-in-a-cell |

### 2.1 containLabel -> outerBounds (v6 layout algorithm)

Two-pass layout, from `Grid.ts` (`_updateScale`, `layOutGridByOuterBounds`):

1. Lay out the axis lines from `left/top/right/bottom/width/height`. This pass alone lets multiple
   grids share axis-line alignment.
2. Build the axis label + axis name geometry, measure the overflow past the "outer bounds" rect,
   and **shrink** the grid rect by that overflow, proportionally per side
   (`fillLabelNameOverflowOnOneDimension` / `fillMarginOnOneDimension` / `applyProportion` /
   `expandOrShrinkRect`).

`outerBoundsMode: 'same'` + `outerBoundsContain: 'axisLabel'` is exactly the old
`containLabel: true`. `'none'` = infinite bounds = never shrink. Default `'auto'` = shrink to the
canvas (or to the assigned cell if the grid is boxed inside a matrix/calendar).

The legacy `containLabel` implementation still exists but must be explicitly registered
(`use([LegacyGridContainLabel])`) — a tree-shaking artefact, irrelevant to a native port.

---

## 3. Axis types — exactly four

`type` applies to `xAxis`, `yAxis`, `radiusAxis`, `angleAxis`, `singleAxis`, `parallelAxis`.
Internally these map to four scale classes (`src/scale/`):

| `type` | Scale class | Semantics |
|---|---|---|
| `'value'` | `Interval` (345 lines) | Continuous linear, nice-tick algorithm. Default for yAxis, radiusAxis, singleAxis, parallelAxis |
| `'category'` | `Ordinal` (338 lines) | Discrete. Data from `axis.data`, or auto-collected from `series.data`/`dataset.source`. Default for xAxis, angleAxis |
| `'time'` | `Time` (789 lines) | Continuous ms timestamps + calendar-aware tick levels + per-level formatters |
| `'log'` | `Log` (276 lines) | Logarithmic, `logBase` default 10; internally wraps an `Interval` "intervalStub" in log space |

`determineAxisType` (`axisHelper.ts`): if `type` is absent but `axis.data` is present, the type is
inferred as `'category'`.

`radar` is special: its indicator axes are always `IntervalScale` (a `log` branch exists but is
commented out).

---

## 4. Axis anatomy — the complete option surface

All of the following come from `axis-common.md`, which is `{{ use: axis-common(...) }}`-included by
`xAxis`, `yAxis`, `radiusAxis`, `angleAxis`, `singleAxis`, `parallelAxis`, and (partially) `radar`.
Include flags control which sub-blocks exist per axis (noted below).

### 4.1 Domain / scale

| Option | Values | Semantics |
|---|---|---|
| `min` | number \| `'dataMin'` \| `'x%'` \| `Function(({min,max}) => number\|null)` \| category ordinal (may be negative) | Hard-fix the low end; disables nice rounding on that end |
| `max` | same, plus `'dataMax'` | Hard-fix the high end |
| `dataMin` / `dataMax` | number, **v6.1** | Virtual data point: extends the domain but **keeps** the nice algorithm. `value`/`log`/`time` only |
| `scale` | boolean = false | For `value`: do not force-include zero |
| `boundaryGap` | category: boolean (default `true`) = band mode; non-category: `[low, high]`, each number or `'x%'` (default `[0,0]`) | Two entirely different meanings on one key |
| `containShape` | boolean = true, **v6.1** | Extra domain margin so bar/pictorialBar/candlestick/boxplot shapes do not overflow the coord rect |
| `splitNumber` | number = 5 (6 for time; 10 used internally for log) | *Recommendation* for tick count |
| `interval` | number | Force the tick step. Not for `category`/`time`. For `log`, pass the **logged** value |
| `minInterval` | number = 0 | Floor for the auto step (e.g. `1` -> integer labels). `value`/`time` only |
| `maxInterval` | number | Ceiling for the auto step (e.g. `86400000` -> at most one day) |
| `logBase` | number = 10 | `log` only |
| `inverse` | boolean = false | Flip axis direction (not on `angleAxis`) |
| `startValue` | number = 0, v5.5.1 | Baseline for bar/pictorialBar shapes; since v6.1 decoupled from `min` |
| `data` | array of string or `{value, textStyle}` | Category domain |
| `alignTicks` | boolean = false, v5.3.0 | Align ticks of multiple numeric axes (see section 7) |
| `deduplication` | (category, internal) | Skip dedup for faster category collection |

`Interval` nice-tick algorithm (`axisNiceTicks.ts::intervalScaleCalcNiceTicks`):
`interval = nice(span / splitNumber, true)`, clamped by `minInterval`/`maxInterval`; precision from
`getIntervalPrecision`; then the extent is floored/ceiled to multiples of `interval` on the ends
that are not user-fixed. `nice()` snaps to 1 / 2 / 5 x 10^k.

`Log` nice-tick (`logScaleCalcNiceTicks`): works in log space,
`interval = max(quantity(span), 1)`; if `splitNumber / span * interval <= 0.5` then
`interval *= 10`. Integer log steps only — decades and multiples of decades.

`minorTick` on a log axis produces the classic 2,3,...,9 sub-decade ticks
(`scale/minorTicks.ts`).

### 4.2 axisLine

| Option | Values | Semantics |
|---|---|---|
| `axisLine.show` | boolean \| `'auto'` (default `'auto'`) | On `value`/`log` axes in cartesian the default resolves to hidden since v5.0 |
| `axisLine.onZero` | `true` \| `false` \| `'auto'` (default `'auto'` since **v6.1**) | Draw this axis at the orthogonal axis's zero. Only if that axis is `value`/`log` **and** its domain contains 0. Never for `category`/`time` orthogonal axes. `'auto'` additionally suppresses onZero when `containShape` is active, so the axis line does not cut through bars |
| `axisLine.onZeroAxisIndex` | number | Pick *which* orthogonal axis to sit on when several exist. Without it, `fixAxisOnZero` takes the first eligible axis not already claimed |
| `axisLine.symbol` | `'none'` \| `'arrow'` \| symbol name \| `[start, end]` | Arrow heads. Default `['none','none']` |
| `axisLine.symbolSize` | `[perpendicular, along]` = `[10, 15]` | |
| `axisLine.symbolOffset` | number \| `[start, end]` = `[0,0]` | |
| `axisLine.lineStyle` | color / width / type (`'solid'\|'dashed'\|'dotted'\|number\|number[]`) / dashOffset / cap / join / miterLimit / shadow* / opacity | |
| `axisLine.breakLine` | boolean = true (internal default) | Whether the axis line is itself interrupted at axis breaks |

### 4.3 axisTick / minorTick

| Option | Values | Semantics |
|---|---|---|
| `axisTick.show` | boolean \| `'auto'` | |
| `axisTick.alignWithLabel` | boolean = false | Category + `boundaryGap:true`: move ticks to the label centre instead of the band boundary |
| `axisTick.interval` | `'auto'` \| number \| `(index, value) => boolean` | Category only. `0` = show all |
| `axisTick.inside` | boolean = false | Draw ticks into the plot area |
| `axisTick.length` | number = 5 | |
| `axisTick.lineStyle` | full line style | Inherits `axisLine.lineStyle.color` |
| `axisTick.customValues` | number[], v5.5.1 | Explicit tick positions, bypassing the algorithm |
| `minorTick.show` | boolean = false, v4.6 | **Not available on `category`** |
| `minorTick.splitNumber` | number = 5 | Sub-divisions per major interval |
| `minorTick.length` | number = 3 | |
| `minorTick.lineStyle` | | |

### 4.4 axisLabel

| Option | Values | Semantics |
|---|---|---|
| `axisLabel.show` | boolean | |
| `axisLabel.interval` | `'auto'` \| number \| `(index, value) => boolean` | Category only; `'auto'` runs the overlap-avoidance search (section 6) |
| `axisLabel.inside` | boolean = false | |
| `axisLabel.rotate` | -90..90 degrees = 0 | Not available on `angleAxis` |
| `axisLabel.margin` | number = 8 | Gap from the axis line |
| `axisLabel.formatter` | string template `'{value} kg'` \| `(value, index, extra) => string` \| **cascading object for time axes** | see section 5 |
| `axisLabel.showMinLabel` / `showMaxLabel` | `true` \| `false` \| `null` (auto) | Auto = hide the end label if it would collide |
| `axisLabel.alignMinLabel` / `alignMaxLabel` | `'left'\|'center'\|'right'\|null`, v5.5 | xAxis only |
| `axisLabel.verticalAlignMinLabel` / `verticalAlignMaxLabel` | `'top'\|'middle'\|'bottom'\|null`, v5.5 | yAxis only |
| `axisLabel.hideOverlap` | boolean, v5.2 | Greedy overlap suppression across the whole label set |
| `axisLabel.customValues` | array, v5.5.1 | Explicit label positions |
| `axisLabel.color` | Color \| `(value, index) => Color` | Per-label callback colour |
| `axisLabel.rich` | rich-text style map | Multi-style labels via `{styleName\|text}` |
| full text style block | fontStyle / fontWeight / fontFamily / fontSize (12) / align / verticalAlign / lineHeight / backgroundColor / borderColor / borderWidth / borderType / borderRadius / padding / shadow* / width / height / textBorder* / textShadow* / overflow / ellipsis / lineOverflow / textMargin (`[0,3]` default) | |

### 4.5 splitLine / minorSplitLine / splitArea

Present only when the include passes `hasSplitLineAndArea` — true for `xAxis`, `yAxis`,
`radiusAxis`, `angleAxis`, `singleAxis`, `radar`; **absent for `parallelAxis`**.

| Option | Values | Semantics |
|---|---|---|
| `splitLine.show` | boolean | default `true` for `value`, `false` for `category` and `time` |
| `splitLine.showMinLine` / `showMaxLine` | boolean = true, v5.6 | Suppress the boundary grid lines |
| `splitLine.interval` | `'auto'` \| number \| fn | |
| `splitLine.lineStyle.color` | Color \| **Color[]** = `['#ccc']` | Array = colours cycle line by line |
| `minorSplitLine.show` | boolean = false, v4.6 | Aligned to `minorTick`, default colour `#eee` |
| `splitArea.show` | boolean = false | |
| `splitArea.interval` | `'auto'` \| number \| fn | |
| `splitArea.areaStyle.color` | Color[] = `['rgba(250,250,250,0.3)','rgba(200,200,200,0.3)']` | Alternating band fill |
| `splitArea.areaStyle.opacity` / `shadow*` | | |

### 4.6 Axis name

Not available on `angleAxis` (the `componentType !== 'angleAxis'` guard covers `name` through
`inverse`).

| Option | Values |
|---|---|
| `name` | string |
| `nameLocation` | `'start'` \| `'middle'`/`'center'` \| `'end'` (default `'end'`) |
| `nameGap` | number = 15 |
| `nameRotate` | degrees, `null` = auto from `nameLocation` |
| `nameTextStyle` | full text style (+ `textMargin`, auto-defaulted per `nameLocation`) |
| `nameTruncate.maxWidth` / `.ellipsis` (`'...'`) / `.placeholder` (`'.'`) | Ellipsis truncation of the name |
| `nameMoveOverlap` | boolean = true, **v6.0**, xAxis/yAxis only — push the name aside when it collides with labels |

### 4.7 Position / index / interaction

| Option | Values | Applies to |
|---|---|---|
| `position` | `'top'\|'bottom'` (xAxis), `'left'\|'right'` (yAxis) | First axis defaults to bottom/left, second to the opposite side. **Requires `axisLine.onZero:false` to take effect** |
| `offset` | number = 0 | Pixel offset from the default position — the mechanism for a 3rd/4th parallel axis. Also requires `onZero:false` |
| `gridIndex` | number = 0 | Which grid this axis belongs to |
| `polarIndex` / `parallelIndex` / `singleAxisIndex` | number = 0 | Host system index |
| `silent` | boolean = false | Disable axis interaction |
| `triggerEvent` | boolean = false | Emit events for `axisLabel` / `axisName` hits (payload has `targetType`, `value`, `name`, and `break` info) |
| `axis.tooltip` | v5.6 | Tooltip on axis labels/names; needs `triggerEvent:true` |
| `z` / `zlevel` | number, default z=0 | |

### 4.8 Jitter (v6.0, cartesian + single only)

| Option | Values |
|---|---|
| `jitter` | number px = 0 — random positional noise for overlapping scatter points on a category/single axis |
| `jitterOverlap` | boolean = true — `false` runs collision-avoidance placement instead of pure random |
| `jitterMargin` | number = 2 — minimum separation when `jitterOverlap:false` |

This is a **beeswarm / strip-plot** capability, not a styling knob.

---

## 5. Time axis specifics

`src/scale/Time.ts` (789 lines). Level table (`scaleIntervals`, ported from d3):

```
second        1s
minute        60s
hour          3600s
quarter-day   6h
half-day      12h
day           1.2d
half-week     3.5d
week          7d
month         31d
quarter       95d
half-year     ~182d
year          365d
```

The chosen level then gets a per-level *step* search:

- day: 16 / 7 / 4 / 2 / 1 days (`getDateInterval`)
- month: 6 / 3 / 2 / 1 (`getMonthInterval`)
- hour: 12 / 6 / 4 / 2 / 1 (`getHourInterval`)
- minute and second: 30 / 20 / 15 / 10 / 5 / 2 / 1 (`getMinutesAndSecondsInterval`)
- millisecond: `nice(approxInterval, true)` clamped to >= 1
- year: `max(1, round(approxInterval / ONE_DAY / 365))`

Ticks are anchored to the *start of the enclosing larger unit* (`getFirstTimestampOfUnit`), so day
ticks begin on the 1st of the month, hour ticks on the hour of the day, etc. Each generated tick
carries a level (`lowerTimeUnit` / `upperTimeUnit`), which drives the cascading formatter and the
bold "primary" style for level-boundary labels (`axisDefault.ts`: the `time` axis default sets
`axisLabel.rich.primary.fontWeight = 'bold'`).

### 5.1 Formatter forms

1. **String template.** Tokens (from `axis-common.md`):
   `{yyyy} {yy} {Q} {MMMM} {MMM} {MM} {M} {dd} {d} {eeee} {ee} {e} {HH} {H} {hh} {h} {mm} {m}`
   `{ss} {s} {SSS} {S} {A} {a}` — year / 2-digit year / quarter / full and abbreviated month /
   day-of-month / full and abbreviated day-of-week / week-of-year / 24h and 12h hour / minute /
   second / millisecond / AM-PM (`{A}` since v5.5.1).
2. **Callback** `(value, index) => string` (`index` provided for `customValues` since v6.1).
3. **Cascading object** — a different template per level. Defaults:

```
year:        '{yyyy}'
month:       '{MMM}'
day:         '{d}'
hour:        '{HH}:{mm}'
minute:      '{HH}:{mm}'
second:      '{HH}:{mm}:{ss}'
millisecond: '{hh}:{mm}:{ss} {SSS}'
none:        '{yyyy}-{MM}-{dd} {hh}:{mm}:{ss} {SSS}'
```

`none` is used for tick values that do not land on any clean unit boundary.

All three forms accept rich-text markup, so the canonical "year in bold on the first tick of the
year, month below it" two-line label is expressible declaratively.

### 5.2 Locale and UTC

- Global `useUTC` (boolean = false) switches *tick computation and display* to UTC. Parsing is
  unaffected.
- **27 built-in locale packs** in `src/i18n/` (AR CS DE EL EN ES FA FI FR HU IT JA KO LV NL PL
  PT-br RO RU SI SV TH TR UK VI ZH nb-NO). Each supplies `time.month[12]`, `time.monthAbbr[12]`,
  `time.dayOfWeek[7]`, `time.dayOfWeekAbbr[7]` plus component strings.
- `echarts.registerLocale` adds more; `echarts.time.format(value, template, isUTC)` and
  `echarts.time.parse` are the public helpers.

---

## 6. Category label thinning (the `interval: 'auto'` algorithm)

`axisTickLabelBuilder.ts::calculateCategoryInterval` — worth porting faithfully, it is what makes
category axes readable:

1. `rotation = (axisRotate - labelRotate)` in radians (axisRotate is 90 for a vertical axis).
2. `unitSpan = dataToCoord(v+1) - dataToCoord(v)`; project to `unitW = |unitSpan * cos(theta)|`,
   `unitH = |unitSpan * sin(theta)|`.
3. Walk the categories (stepping by `max(1, floor(count/40))` for large data), measure each
   formatted label's bounding rect, inflate by **1.3x**, keep `maxW`, `maxH` (floor 7px).
4. `interval = max(0, floor(min(maxW/unitW, maxH/unitH)))`.
5. **Hysteresis cache** (`calculateCategoryIntervalDealCache`): if the newly computed interval is
   within +/-1 of the last one, the tick count is within +/-1, the axis pixel extent is unchanged,
   and the old interval was larger — reuse the old one. This exists explicitly to stop labels
   flickering between `a,d,g` and `a,c,e` while dragging a dataZoom window. The cache is bypassed
   when the axis extent changed (chart resize), so hidden labels can reappear.

`AngleAxis` overrides this with a simpler height-only variant (labels around a circle are
constrained by height, not width) — same hysteresis cache.

There is also a two-phase compute (`AxisTickLabelComputingKind.estimate` vs `determine`) because
the grid rect can shrink after label measurement; the estimate pass is not cached.

`axisLabel.hideOverlap` is a separate, later pass (`label/labelLayoutHelper.ts::hideOverlap`):
sort by `suggestIgnore` then `priority`, then greedily accept labels whose oriented bounding rect
does not intersect any already-accepted one. Rejected labels get `ignore = true` but are
un-ignored in the emphasis state, so hovering still reveals them.

---

## 7. Multiple axes and `alignTicks`

- Any number of `xAxis` / `yAxis` entries; each carries `gridIndex`. Series select via
  `xAxisIndex`/`yAxisIndex` or `xAxisId`/`yAxisId`.
- A secondary axis on the opposite side is automatic for axis #2; #3 and beyond need `offset`
  (plus `axisLine.onZero:false`).
- `alignTicks: true` (v5.3, `value`/`log` only) makes several numeric axes share a tick *count* so
  their grid lines coincide. `Grid.ts::prepareAlignToInCoordSysCreate` picks an "alignTo" axis
  (the last axis that did **not** request alignment, else the first requester), and
  `axisAlignTicks.ts::scaleCalcAlign` re-runs the nice algorithm on the others, growing their
  interval until tick counts match. Axes with an explicit `interval`, or with axis breaks, are
  excluded (`incapableOfAlignNeedFallback`).
- `onZero` bookkeeping (`fixAxisOnZero`) prevents two y-axes from both landing on the same x=0
  line — the first claimant wins, recorded by key `dim + '_' + index`.

---

## 8. Axis breaks (new in v6.0) — `xAxis.breaks`

A genuinely new capability: collapse ranges of the domain. Requires registering the `AxisBreak`
feature. **Not available on `category` axes.**

| Option | Values | Semantics |
|---|---|---|
| `breaks[i].start` / `.end` | number \| date string \| Date | The collapsed domain range. Also the identity key of the break for `setOption` updates |
| `breaks[i].gap` | `'x%'` of axis length, **or** an absolute value in data units | Visual size of the gap. Percent keeps a stable pixel gap under `min`/`max`/dataZoom changes; absolute does not. The two forms must not be mixed within one array |
| `breaks[i].isExpanded` | boolean = false | Break is currently expanded (un-collapsed) |
| `breakArea.show` | boolean = true | |
| `breakArea.itemStyle` | fill `#fff`, border `#b7b9be`, borderWidth 1, borderType `[3,3]`, opacity 0.6 | |
| `breakArea.zigzagAmplitude` | number px = 4 | Perpendicular amplitude; `0` degenerates to a straight line |
| `breakArea.zigzagMinSpan` / `zigzagMaxSpan` | 4 / 20 px | Tooth size is **randomised** between them to fake a torn-paper edge |
| `breakArea.zigzagZ` | number = 100 | |
| `breakArea.expandOnClick` | boolean = true | Clicking the break area expands it (animated) |
| `breakLabelLayout.moveOverlap` | `'auto'` \| true \| false | Shift break labels apart |

Implementation notes worth stealing: `pruneTicksByBreak` deletes normal ticks that would collide
with the zigzag; `addBreaksToTicks` injects the break start/end as labelled ticks; the label
formatter receives `extra.break = {type:'start'|'end', start, end}`. The randomised zigzag point
list is **cached per break** (`zigzagRandomList` in `axisBreakHelperImpl.ts`) so the torn edge does
not re-randomise on every repaint — an immediate-mode renderer must replicate this or the edge
will crawl.

---

## 9. axisPointer

Three configuration sites: global `axisPointer`, per-axis `someAxis.axisPointer`, and the sugar
`tooltip.axisPointer` (lowest priority).

| Option | Values | Semantics |
|---|---|---|
| `type` | `'line'` \| `'shadow'` \| `'none'`; plus `'cross'` **only** under `tooltip.axisPointer` | `'cross'` is sugar for enabling both orthogonal axes' pointers |
| `axis` (tooltip form) | `'auto'` \| `'x'` \| `'y'` \| `'radius'` \| `'angle'` | Which axis owns the pointer; auto picks the category/time axis |
| `snap` | boolean, auto-determined | Snap to the nearest data point. Meaningful on `value`/`time` |
| `triggerOn` | `'mousemove'` \| `'click'` \| `'mousemove\|click'` \| `'none'` | **Global only** |
| `link` | array of link groups | **Global only.** Sync pointers across grids/systems |
| `link[i].{x,y,radius,angle,single}AxisIndex/Name/Id` | array \| value \| `'all'` | Group membership |
| `link[i].mapper` | `(sourceVal, sourceAxisInfo, targetAxisInfo) => number` | Value translation between axes of different `type` (e.g. category <-> time) |
| `triggerTooltip` | boolean = true | |
| `triggerEmphasis` | boolean = true, v5.4.3 | Also highlight the series |
| `value` | number | Current / initial pointer value (used with `handle`) |
| `status` | `'show'` \| `'hide'` | Programmatic visibility |
| `z` | number | |
| `label.show` | boolean = false (auto-true for `'cross'`) | The value flag drawn on the axis |
| `label.precision` | `'auto'` \| number | |
| `label.formatter` | string with `{value}` \| `(params) => string` with `params.value`, `.seriesData[]`, `.axisDimension`, `.axisIndex` | |
| `label.margin` | number = 3 | |
| `label.padding` | `[5,7,5,7]` | |
| `label.backgroundColor` | `'auto'` (= axis line colour) | |
| `label.borderColor` / `borderWidth` / `shadow*` + text style | | |
| `lineStyle` | valid for `type:'line'`; default `#555`, width 1, solid | |
| `shadowStyle` | valid for `type:'shadow'`; default `rgba(150,150,150,0.3)` | Band width from `calcBandWidth` |
| `crossStyle` | valid for `type:'cross'`; default `#555`, width 1, **dashed** | |
| `handle.show` | boolean = false | The **draggable touch handle** |
| `handle.icon` | symbol name \| `image://url` \| `path://d` | |
| `handle.size` | number \| `[w,h]` = 45 | |
| `handle.margin` | number = 50 | Distance from handle centre to the axis |
| `handle.color` | `'#333'` | |
| `handle.throttle` | ms = 40 | Redraw throttle while dragging |
| `handle.shadowBlur` / `Color` / `OffsetX` | 3 / `#aaa` / 2 | |

Availability: cartesian, polar and single each give every axis its own axisPointer. Pointers are
hidden by default; they appear when `someAxis.axisPointer.show:true`, or when
`tooltip.trigger:'axis'`, or when `tooltip.axisPointer.type:'cross'`. `handle` is **not supported
on polar**.

Coordination with tooltip: `axisTrigger.ts` finds the nearest point per series
(`findPointFromSeries.ts`), sets each participating axis's pointer value, dispatches
`updateAxisPointer`, and hands the collected `seriesData` to the tooltip. `axis.axisPointer`
overrides `tooltip.axisPointer`.

Pointer shapes are built by `viewHelper.ts`: `makeLineShape`, `makeRectShape` (shadow band),
`makeSectorShape` (polar shadow), plus `calcAxisPointerShadowBandWidth`.

---

## 10. Polar

`Polar` = `radiusAxis` (dim `radius`) + `angleAxis` (dim `angle`).
`dataToPoint([r, a])` -> `coordToPoint` -> `cx + r*cos(-a*pi/180)`, `cy + r*sin(-a*pi/180)`.

| Option | Values |
|---|---|
| `polar.center` | `['50%','50%']` — px or % of container (x -> width, y -> height) |
| `polar.radius` | number \| `'x%'` \| `[inner, outer]` — % is of `min(width, height)` |
| `polar.coordinateSystem` | `'none'`\|`'calendar'`\|`'matrix'` (v6) |
| `polar.tooltip` | |
| `angleAxis.startAngle` | degrees = 90 (12 o'clock); 0 = 3 o'clock |
| `angleAxis.endAngle` | degrees, `null` = full circle (v5.5) — enables gauge-like arcs |
| `angleAxis.clockwise` | boolean = true |
| `angleAxis.polarIndex` / `radiusAxis.polarIndex` | number = 0 |
| `angleAxis.type` | default `'category'` |
| `radiusAxis.type` | default `'value'` |

Both polar axes take the full axis-common surface **including** `splitLine` / `splitArea`
(concentric rings for radiusAxis; radial spokes and sectors for angleAxis). `angleAxis` has **no**
`name` / `nameLocation` / `nameGap` / `nameRotate` / `inverse` and **no** `axisLabel.rotate`.

Series on polar: line, bar (stacked/grouped rose bars), scatter, effectScatter, pictorialBar,
lines, graph, pie (box), chord, custom. `getArea()` returns
`{cx, cy, r0, r, startAngle, endAngle, clockwise}` for clipping.

---

## 11. Radar

Not polar: **each indicator is its own independent axis** with its own `min`/`max`.

| Option | Values |
|---|---|
| `radar.center` / `radar.radius` | as polar; radius default `'75%'` |
| `radar.startAngle` | degrees = 90 |
| `radar.clockwise` | boolean = false, **v6.1** |
| `radar.shape` | `'polygon'` (default) \| `'circle'` |
| `radar.splitNumber` | number = 5 |
| `radar.scale` | boolean = false |
| `radar.indicator[]` | `{name, min (default 0), max, color}` |
| `radar.axisName` | `{show, formatter (string `'[{value}]'` or `(value, indicator) => string`), + text style}` |
| `radar.axisNameGap` | number = 15 |
| `radar.axisLine` / `axisTick` / `axisLabel` / `splitLine` / `splitArea` (default **show:true**) | the common blocks, minus `minorTick`, minus label `interval` / `inside` |
| `radar.coordinateSystem` | `'none'`\|`'calendar'`\|`'matrix'` (v6) |

`coordToPoint(coord, i)` = `cx + coord*cos(angle_i)`, `cy - coord*sin(angle_i)`.
`pointToData` finds the nearest indicator by angular distance. `scaleCalcAlign` is applied so all
indicator axes get the same tick count, which is what makes the rings regular.

Only `series-radar` uses it.

---

## 12. singleAxis

One axis laid out in a rectangle. `orient: 'horizontal' | 'vertical'` (default horizontal),
`position: 'top'|'bottom'|'left'|'right'` (default `'bottom'`), plus the full
`left/top/right/bottom/width/height` box (defaults `'5%'` all round), plus the whole axis-common
surface including `splitLine` / `splitArea`. Default `type` is `'value'`, `axisTick.length` is 6,
and `tooltip.show` defaults to `true` (unusual — the single-axis model doubles as the coordinate
system model).

Consumers: **themeRiver** (its only coordinate system), scatter, effectScatter, lines, pie (box),
chord, custom. The canonical use is the "one strip per category, stacked vertically" layout —
several `singleAxis` components in one chart.

---

## 13. Calendar

`Calendar` maps a date to a (week, day-of-week) cell.

| Option | Values | Semantics |
|---|---|---|
| `calendar.range` | `2017` \| `'2017-02'` \| `['2017-01-02','2017-02-23']` \| `['2017-01','2017-02']` | **Required.** Year, month, or explicit span; month strings expand to whole months |
| `calendar.cellSize` | number \| `[w,h]` \| `'auto'` \| `['auto', 40]` = 20 | Setting `width` forces `cellSize[0]='auto'`; `height` forces `cellSize[1]='auto'` |
| `calendar.left/top/right/bottom/width/height` | px / % / `'auto'` | defaults left 80, top 60 |
| `calendar.orient` | `'horizontal'` (default) \| `'vertical'` | Weeks run along x or y |
| `calendar.splitLine.show` / `.lineStyle` | default `#000`, width 1, solid | Month boundary polyline |
| `calendar.itemStyle` | color `#fff`, borderWidth 1, borderColor `#ccc` | Per-cell rect |
| `calendar.dayLabel` | `show`, `firstDay` (0..6, 0=Sunday), `margin` (0), `position` (`'start'\|'end'`), `nameMap`, text style, `silent` | `nameMap`: `'EN'` / `'ZH'` / any registered locale / custom 7-array (index 0 = Sunday) |
| `calendar.monthLabel` | `show`, `align` (`'center'\|'left'`), `margin` (5), `position`, `nameMap`, `formatter`, text style, `silent` | formatter tokens `{nameMap} {yyyy} {yy} {MM} {M}` or callback |
| `calendar.yearLabel` | `show`, `margin` (30), `position` (`'top'\|'bottom'\|'left'\|'right'`), `formatter`, text style, `silent` | default position: left when horizontal, top when vertical; tokens `{nameMap} {start} {end}` |
| `calendar.silent` | boolean | |

`dataToPoint`: `nthWeek` from the range start along the primary axis, `dayOfWeek` along the other;
returns `[NaN, NaN]` when out of range (with `clamp`). `pointToData` inverts it.
Series on calendar: heatmap, scatter, effectScatter, graph, plus (v6, box usage) pie, grid, polar,
geo, and any plain component.

---

## 14. Matrix (new in v6.0) — verified in source

`src/coord/matrix/` (Matrix.ts 631, MatrixDim.ts 480, matrixCoordHelper.ts 378, MatrixModel.ts 361,
MatrixBodyCorner.ts 292). Registered as `'matrix'`. Dimensions `['x','y','value']`, x and y both
**ordinal**.

Conceptually a **table**: a header region on x (columns), a header region on y (rows), a body of
cells, and a corner region at their intersection. Headers can be **trees** (multi-level column
groups), which makes it a pivot-table layout engine rather than just a grid.

| Option | Values | Semantics |
|---|---|---|
| `matrix.left/top/right/bottom/width/height` | px / % | default left `'10%'`, top `'10%'` |
| `matrix.x` / `matrix.y` | header region objects | |
| `matrix.x.show` | boolean = true | Headless matrix = pure layout grid |
| `matrix.x.data` | `['A','B',...]` or tree `[{value, children:[...], size}]` | Auto-collected from `series.data`/`dataset.source` when omitted (respecting `series.encode`) |
| `matrix.x.length` | number, **v6.1** | Column/row count without naming them |
| `matrix.x.levels[i].levelSize` | number px \| `'x%'` | Height of header row *i* (for `matrix.x`) / width of header column *i* (for `matrix.y`) |
| `matrix.x.data[i].size` | number \| `'x%'` | Width of one column (x) / height of one row (y) |
| `matrix.x.dividerLineStyle` | default `#aaa`, 1px solid | |
| `matrix.x.label` / `.itemStyle` / `.silent` / `.cursor` / `.z2` | cell text and rect style | `cursor` is a CSS cursor name — browser-bound |
| `matrix.body` / `matrix.corner` | `{data[], label, itemStyle, silent, cursor, z2}` | |
| `...data[i].coord` | see the locator rules below | |
| `...data[i].value` | string \| number | Cell text |
| `...data[i].mergeCells` | boolean = false | **Cell merging (rowspan/colspan)** |
| `...data[i].coordClamp` | boolean | Allow `[2, null]` = whole column |
| `matrix.backgroundStyle` | itemStyle for the whole area, default border `#ccc` | |
| `matrix.borderZ2` | number | z2 of the outer border and dividers |
| `matrix.tooltip` | disabled by default — intended for truncated cell text | |
| `matrix.triggerEvent` | boolean = false, v6.1 — payload `{targetType:'x'\|'y'\|'body'\|'corner', name, value, coord}` | |

**Cell locator algebra** (the interesting part; also used by `dataToPoint` / `dataToLayout` and by
every boxed component's `coord`):

- The body's top-left cell is origin `(0,0)`. Non-negative locators go right/down into the body;
  **negative locators index into the header/corner** (`[-2,-1]` = a specific corner cell).
- Leaf header cells also carry an *ordinal number*, so `['Xb1', 0]` and `[1, 0]` are the same
  cell; string values, ordinals and locators can be mixed in one coord.
- Ranges: `[[2,5], 8]` = a horizontal band; `[[2,5],[7,8]]` = a rect of cells;
  `['aNonLeafHeaderNode', 8]` = the span of that header subtree; `[2, null]` (with `coordClamp`)
  = the entire column.
- `dataToPoint` returns the cell centre; `dataToLayout` returns the full rect.

What it enables: correlation heatmaps and confusion matrices with real row/column headers,
CSS-grid-style dashboards, and — via `coordinateSystemUsage:'box'` — **a full sub-chart per cell**
(sparkline grids, small multiples, a mini bar/geo/pie per cell).

---

## 15. Geo

`Geo extends View` (`coord/View.ts` supplies the raw-transform plus roam-transform matrix stack).

### Map registration
`echarts.registerMap(name, {geoJSON})` or `echarts.registerMap(name, {svg})`.

- GeoJSON path: `parseGeoJson.ts` handles `Polygon`, `MultiPolygon`, `LineString`,
  `MultiLineString`. Each region becomes a `GeoJSONRegion` with exterior plus interior (hole)
  rings. `contain()` = bounding-rect reject, then point-in-polygon on the exterior with hole
  exclusion. `calcCenter()` picks the centroid of the largest ring; `properties.cp` overrides it.
- SVG path: `GeoSVGResource.ts` parses the SVG, honours `width`/`height`/`viewBox`, and turns
  named/`id` elements into selectable regions. This is how the seat-map / beef-cuts / floor-plan
  examples work.

| Option | Values | Semantics |
|---|---|---|
| `geo.map` | registered map name | |
| `geo.projection.project` / `.unproject` | `[lng,lat] <-> [x,y]` functions | **JS callbacks** — arbitrary projections (d3-geo etc.). GeoJSON only |
| `geo.projection.stream` | d3 stream interface | Enables antimeridian clipping plus adaptive resampling |
| `geo.aspectScale` | number = 0.75 | Used only when no `projection`: `pxW/pxH = lngSpan/latSpan * aspectScale`. A cheap sinusoidal-ish correction (`~= cos(centre latitude)`) |
| `geo.boundingCoords` | `[[lng,lat] topLeft, [lng,lat] bottomRight]` | Force the visible geographic window |
| `geo.center` | `[lng,lat]` (or projected coords), or `['30%','50%']` — % of the **bounding rect** since v6.0 | Which map point sits at the viewport centre |
| `geo.zoom` | number = 1 | <1 zooms out, >1 zooms in |
| `geo.scaleLimit` | `{min, max}` | |
| `geo.roam` | `false` \| `true` \| `'scale'`/`'zoom'` \| `'move'`/`'pan'` | Mouse/touch pan plus wheel zoom |
| `geo.roamTrigger` | `'selfRect'` (default) \| `'global'`, **v6.0** | Where roam gestures are accepted |
| `geo.clip` | boolean = false, **v6.0** | Clip the map to its allocated rect |
| `geo.left/top/right/bottom/width/height` | px / % | |
| `geo.layoutCenter` / `geo.layoutSize` | `['30%','30%']` / number or % | Alternative sizing that **always preserves aspect**; overrides left/top/... |
| `geo.preserveAspect` | `false` \| `true`/`'contain'` \| `'cover'`, **v6.0** | |
| `geo.preserveAspectAlign` | `'left'\|'center'\|'right'` | |
| `geo.preserveAspectVerticalAlign` | `'top'\|'middle'\|'bottom'` | |
| `geo.nameMap` | `{'China':'CN name'}` | Rename regions |
| `geo.nameProperty` | string = `'name'` | Which GeoJSON feature property is the key |
| `geo.selectedMode` | `false` \| `'single'` \| `'multiple'` | |
| `geo.itemStyle.areaColor` (`'#eee'`) plus full item style | | Region fill and border |
| `geo.label` (+ `formatter`) | | Region label |
| `geo.emphasis` / `.select` / `.blur` (v5.1) | each with `itemStyle` + `label` | Interaction states; `focus` / `blurScope` for focus dimming |
| `geo.regions[]` | `{name, selected, itemStyle, label, emphasis, select, blur, tooltip, silent}` | Per-region overrides |
| `geo.tooltip` | | |
| `geo.coordinateSystem` | `'none'`\|`'calendar'`\|`'matrix'` (v6) | Geo inside a table cell |

`View`'s transform stack: `mtRaw` (data bounding rect -> view rect, aspect-corrected) composed with
`roamTrans` (pan/zoom) = `mtOverall`, with `mtOverallInv` for hit-testing. Roam state is synced
back into the `center` / `zoom` model options after each gesture
(`viewCoordSysSyncBack`).

---

## 16. Parallel coordinates

`parallel` (the system) + `parallelAxis[]` (the axes) + `series-parallel` (the polylines).

| Option | Values | Semantics |
|---|---|---|
| `parallel.left/top/right/bottom/width/height` | defaults 80 / 60 / 80 / 60 | |
| `parallel.layout` | `'horizontal'` (default) \| `'vertical'` | Axis orientation |
| `parallel.parallelAxisDefault` | a full axis-common option object | Merged into every `parallelAxis` before init — the way to avoid repeating 50 axis configs |
| `parallel.axisExpandable` | boolean = false | The "50+ dimensions" fisheye mode |
| `parallel.axisExpandCenter` | number, no default | Index at the centre of the expanded window |
| `parallel.axisExpandCount` | number = 0 | How many axes are expanded |
| `parallel.axisExpandWidth` | px = 50 | Spacing between expanded axes |
| `parallel.axisExpandTriggerOn` | `'click'` (default) \| `'mousemove'` | |
| `parallel.axisExpandSlideTriggerArea` | (internal) | Drag zones for sliding the expand window |
| `parallel.coordinateSystem` | `'none'`\|`'calendar'`\|`'matrix'` (v6) | |
| `parallelAxis.dim` | number | Which data dimension (column) this axis shows |
| `parallelAxis.parallelIndex` | number = 0 | Which parallel system |
| `parallelAxis.realtime` | boolean = true | Update the view continuously while brushing |
| `parallelAxis.areaSelectStyle` | `{width:20, borderWidth:1, borderColor:'rgba(160,197,232)', color:'rgba(160,197,232)', opacity:0.3}` | The on-axis brush box |
| full axis-common surface | | **without** `splitLine` / `splitArea` and **without** `axisPointer` |

Expand algorithm (`Parallel.ts::_layoutAxes`): the axis strip is divided into an expanded window of
`axisExpandCount` axes at `axisExpandWidth` spacing, and the remaining axes are collapsed to
`axisCollapseWidth = (layoutLength - winSize) / (axisCount - axisExpandCount)`. Dragging inside
the window slides it; the reported `behavior` is one of `'jump' | 'slide' | 'none'`.

Brushing on an axis (`parallelAxisAction.ts`) filters the polylines — the primary interaction of
the whole chart type.

---

## 17. Cross-cutting mechanics worth naming

- **Box layout model.** Every component shares `left/right/top/bottom/width/height` where each is
  a pixel number, an `'x%'` string, or `'auto'`; `'center'`/`'middle'` are accepted for
  `left`/`top` on some components. Two of the three per axis determine the third.
- **Circular layout model.** `center: [x, y]` (px or %) plus `radius: n | '75%' | [inner, outer]`,
  where `%` is relative to `min(containerW, containerH)`.
- **Band width.** `coord/axisBand.ts` computes the bar/candlestick/boxplot band and the
  `axisPointer` shadow width. On a category axis it is the ordinal step; on a **numeric** axis
  (v6) it is derived from per-axis statistics collected in `axisStatistics.ts` — effectively the
  minimum gap between adjacent data values — so bars on a time axis get a sensible width. Fallback
  ratio 0.8 of the available span.
- **`dataToPoint` / `pointToData` / `dataToLayout`** are the uniform coordinate-system contract
  (`coord/CoordinateSystem.ts`); `convertToPixel` / `convertFromPixel` / `convertToLayout` are the
  public API wrappers. `containPoint` is the hit-test entry. `getArea()` returns the clip region.
- **Renderer-facing axis API**: `axis.getTicksCoords()`, `getMinorTicksCoords()`, `getViewLabels()`,
  `getBandWidth()`, `dataToCoord()`, `coordToData()`, `containData()`.
- **AxisBuilder parts.** `component/axis/AxisBuilder.ts` builds an axis in the fixed dependency
  order `axisLine -> axisTickLabelEstimate -> axisTickLabelDetermine -> axisName`. The two-phase
  tick/label build exists because the grid rect may shrink after label measurement: an estimate
  pass computes label sizes, layout shrinks the rect, a determine pass re-lays them out. A native
  port needs the same two passes to support `outerBounds`.

---

## Porting notes

Classification for an Object Pascal / BGRABitmap immediate-mode renderer.

### NATURAL — direct canvas work, no exotic algorithms

- **Grid rectangle**: `left/top/right/bottom/width/height` with px and `%`; `show`,
  `backgroundColor`, `borderColor`, `borderWidth`, `opacity`, shadow. Multiple grids per chart.
- **Axis line** including `symbol` arrow heads (`symbolSize`, `symbolOffset`) and all line styles
  (solid / dashed / dotted / custom dash arrays, cap, join, dashOffset).
- **axisTick / minorTick**: `length`, `inside`, `lineStyle`, `alignWithLabel`, `customValues`.
- **splitLine / minorSplitLine / splitArea**, including **colour arrays that cycle per line/band**
  and `showMinLine` / `showMaxLine`.
- **axisLabel basics**: `margin`, `inside`, `rotate` (-90..90), `showMinLabel`/`showMaxLabel`,
  `align` / `verticalAlign` including the min/max-specific variants, string-template `formatter`,
  per-label colour callback.
- **Axis name**: `nameLocation` (start/middle/end), `nameGap`, `nameRotate`, `nameTruncate`
  (ellipsis at `maxWidth`).
- **`position`**, **`offset`**, **`inverse`**, **`gridIndex`**, multiple x/y axes, secondary axis.
- **`boundaryGap`** in both forms (category band vs. `['20%','20%']` domain padding).
- **Linear (`value`) scale plus nice ticks**: `nice(span/splitNumber)` snapping to 1/2/5 x 10^k,
  `min` / `max` / `'dataMin'` / `'dataMax'` / percent / callback, `scale`, `splitNumber`,
  `minInterval` / `maxInterval` / `interval`, `dataMin` / `dataMax` (v6.1).
- **Log scale** with `logBase` and decade minor ticks.
- **Category (ordinal) scale**, `axis.data` with per-item `textStyle`.
- **Polar**: `center`, `radius` (including inner radius), `startAngle`, `endAngle`, `clockwise`,
  `dataToPoint` / `pointToCoord`, concentric split lines and sector split areas.
- **Radar**: independent indicator axes, `shape: 'polygon'|'circle'`, `startAngle`, `clockwise`,
  `axisName` + `axisNameGap`, ring split lines/areas.
- **singleAxis**: box + `orient` + `position`; everything else is the common axis surface.
- **Calendar**: `range` parsing (year / month / explicit span), `cellSize` including `'auto'`,
  `orient`, cell `itemStyle`, `dayLabel` / `monthLabel` / `yearLabel` with `firstDay`, `position`,
  `nameMap` and template formatters, month-boundary `splitLine`.
- **axisPointer line/shadow drawing**, `label` box with padding/background/border,
  `lineStyle` / `shadowStyle` / `crossStyle`, `snap`, `value`, `status`, `triggerTooltip`.
- **Parallel axis layout** (equal spacing, horizontal/vertical), `parallelAxisDefault` merge,
  the `areaSelectStyle` brush box.
- **Geo `layoutCenter`/`layoutSize`, `preserveAspect`/`Align`/`VerticalAlign`, `aspectScale`,
  `boundingCoords`** — pure rectangle math.
- **Matrix cell geometry**: even distribution, `levelSize` / `size` in px or `%`, header divider
  lines, cell `itemStyle` / `label`, `mergeCells` rendering.

### HEAVY — doable, but named algorithms you must actually implement

- **Category label auto-interval with hysteresis** (`calculateCategoryInterval`): measure every
  formatted label, inflate 1.3x, project onto the axis direction with the rotation angle, take
  `floor(min(maxW/unitW, maxH/unitH))`, and cache with the +/-1 stability rule. Without the cache
  labels flicker while zooming.
- **`axisLabel.hideOverlap`**: greedy priority-sorted oriented-bounding-box intersection test over
  the label set (`labelLayoutHelper.hideOverlap`). Needs rotated-rectangle overlap (SAT).
- **`outerBounds` two-pass layout** (`layOutGridByOuterBounds`): estimate labels and name geometry,
  compute per-side overflow against the constraint rect, shrink proportionally, re-lay out. Plus
  the `nameMoveOverlap` name-displacement pass. The fiddliest single piece of the grid.
- **Time scale**: the 12-entry level table, per-level step search (day 16/7/4/2/1, month 6/3/2/1,
  hour 12/6/4/2/1, min/sec 30/20/15/10/5/2/1), anchoring ticks to the start of the enclosing unit,
  tagging each tick with its level, and the cascading per-level formatter with a bold primary
  level. Plus DST-safe date arithmetic and a 27-locale month/weekday name table. Budget real time.
- **`alignTicks`**: pick an alignTo axis, then grow the other axes' intervals until tick counts
  match (`axisAlignTicks.scaleCalcAlign`), with fallbacks when breaks or explicit intervals exist.
- **`axisLine.onZero` arbitration** across multiple orthogonal axes (`fixAxisOnZero`), including
  the v6.1 `'auto'` rule that disables onZero when `containShape` is active.
- **Axis breaks (v6)**: domain remapping with collapsed intervals (percent vs. absolute `gap`),
  tick pruning near the break, injecting break-boundary ticks, the **cached randomised zigzag**
  polyline, the expand/collapse animation, and break-aware label formatting.
- **`containShape` and band width from statistics**: per-axis minimum-adjacent-gap statistics on
  numeric axes to size bars and to pad the domain.
- **Jitter with overlap avoidance** (`jitterOverlap:false`, `jitterMargin`): a 1-D beeswarm
  packing pass.
- **axisPointer `link` + `mapper`**: cross-coordinate-system value synchronisation with a
  user-supplied conversion function, plus `findPointFromSeries` nearest-point search and `snap`.
- **Parallel `axisExpandable`**: the fisheye window layout (expanded window at `axisExpandWidth`,
  remainder at `axisCollapseWidth`), plus the slide/jump drag behaviour.
- **Geo GeoJSON pipeline**: parse `Polygon` / `MultiPolygon` / `LineString` / `MultiLineString`,
  ring orientation, hole handling, per-region bounding rect and centroid, point-in-polygon
  hit-testing with hole exclusion, and the fit-to-rect transform. All CPU work, no browser needed —
  but a real amount of code, and it needs even-odd fill for holes.
- **Roam (View transform stack)**: raw transform (data rect -> view rect) composed with a pan/zoom
  transform, inverse for hit-testing, `scaleLimit` clamping, `roamTrigger` hit region, and syncing
  `center` / `zoom` back to the model.
- **Matrix locator algebra**: negative locators addressing headers, ordinal/string/locator
  equivalence, tree headers with non-leaf spans, range locators, `coordClamp` whole-row/column,
  and cell merging. Small but genuinely intricate index system.
- **Matrix/calendar as a *host* for other coordinate systems** (`coordinateSystemUsage:'box'`).
  Architecturally this means every coordinate system must accept an externally supplied rect
  instead of always measuring against the canvas. Cheap if designed in from the start, expensive
  to retrofit.
- **Rich-text axis labels** (`{style|text}` segments, per-segment font/colour/background/border,
  multi-line): a mini layout engine over BGRABitmap text measurement. The existing CJK word-wrap
  trap in this codebase applies here.

### BROWSER-BOUND — needs a native re-think, or out of scope

- **`zlevel`** — maps to separate `<canvas>` layers in the browser. On a single BGRABitmap surface
  only `z` (paint order) is meaningful. Keep `z`, drop `zlevel` or alias it to `z`.
- **`geo.projection.project/unproject/stream`** — arbitrary JS projection callbacks; the `stream`
  hook exists specifically to plug in d3-geo's antimeridian clipping and adaptive resampling. A
  native port should ship a fixed set of projections (Mercator, equirectangular, conic equal-area,
  ...) behind a Pascal interface instead of "any function".
- **`geo.map` with `{svg: ...}`** — the SVG base-map path parses a DOM SVG tree, honours `viewBox`,
  and turns named SVG elements into interactive regions. Porting it means embedding an SVG parser
  and renderer. Out of scope unless SVG floor-plan maps are a requirement.
- **`matrix.*.cursor`** — a CSS cursor name string. Map to LCL `TCursor` or ignore.
- **`axisPointer.handle`** — designed for touch devices (drag a puck below the axis because the
  finger occludes the chart); `throttle` exists purely for browser repaint cost. Near-useless on
  desktop; low priority.
- **`axisPointer.triggerOn` / `axis.triggerEvent`** — the semantics port fine, but the payload
  shapes are DOM-event-shaped; re-model as Pascal events.
- **Tooltip coordination** — the tooltip itself is a DOM floating layer by default
  (`tooltip.renderMode: 'html'`); only the axisPointer half is canvas. The axis-side contract
  (which axis triggers, what `seriesData` is collected) ports fine; the tooltip rendering does not.
- **`grid` / `geo` / `matrix` `tooltip` sub-options, and `aria`** — DOM tooltip surface and
  accessibility.
- **Function-valued options generally** (`min`/`max` callbacks, `axisLabel.formatter` callback,
  `axisLabel.interval` callback, `axisLabel.color` callback, `axisPointer.link.mapper`,
  `monthLabel.formatter`, `yearLabel.formatter`, `radar.axisName.formatter`,
  `axisTick.interval` callback) — semantically fine, but each becomes a published event/callback
  type in the Pascal API. There are roughly ten of them in this topic; settle the callback
  signature convention once.
- **`echarts-gl` systems** (`grid3D`, `geo3D`, `globe`, `mapbox`, `cartesian3D`) and tile-map
  coordinate systems (`bmap` / `amap` / `leaflet`) — WebGL and external map services. Out of scope.
- **Progressive / large-mode rendering hooks and worker threads** — not part of this topic, but
  they shape how `axisStatistics` samples data; ignore for the port.
