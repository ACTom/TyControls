# TTyChart vs Apache ECharts 6.1.0 — Gap Analysis

Synthesis of reports 01–09 in this directory, cross-checked against `D:/Projects/echarts` (v6.1.0),
`D:/Projects/echarts-doc`, and `source/tyControls.Chart.pas` (1721 lines, read in full).

Goal under evaluation: *"ty-controls 3.1 should make TTyChart basically cover all of ECharts'
functionality."*

Porting class in every matrix below uses the surveys' vocabulary:
**NATURAL** = the BGRABitmap rasteriser already does this, it is layout + drawing work.
**HEAVY** = portable, but a named algorithm has to be implemented.
**BROWSER-BOUND** = depends on DOM/CSS/SVG/WebGL/JS semantics; needs a native re-think or is out of scope.
**API-SHAPE** = portable in substance, but the ECharts form is a JS callback/closure and the native
form is a decision (method pointer / interface / registered renderer). *Not* a blocker.

> **Corrections applied.** An adversarial review of this document is in `11-critique.md`. Two HIGH
> findings are folded in below and marked `[corrected]`; the MEDIUM/LOW findings stand as caveats
> recorded in that file — read it alongside this one. In particular: ~10 rows below are tagged
> BROWSER-BOUND merely for being function-valued and should read **API-SHAPE**; `useUTC`,
> root `backgroundColor`, root `textStyle`, `registerCustomSeries`+`itemPayload` (v6.0),
> `dataZoom.radiusAxisIndex`/`angleAxisIndex`/`singleAxisIndex`, and the `dataTool` GEXF parser have
> no matrix row; `large`-mode is classed NATURAL without measurement; `dataMin`/`dataMax` is
> HEAVY-lite, not NATURAL; and dirty-rect painting is filed in three contradictory tiers.

---

## 1. Scale of the gap, quantified

Blunt version first: **TTyChart implements roughly 1–2 % of ECharts' feature surface, and none of its
architecture.**

### 1.1 Headline counts

| Axis of comparison | ECharts 6.1.0 | TTyChart today | Ratio |
|---|---|---|---|
| Source size `[corrected]` | **596 TS files, 138,362 lines** in `echarts/src/`, **plus 31,477 lines of TypeScript in `zrender/src/`** — the retained scene graph (`Element` 2,172 · `canvas/Painter` 1,347 · `animation/Animator` 1,148 · `core/PathProxy` 1,009 · `graphic/helper/parseText` 951 · `tool/morphPath` 894 · `contain/path` 408). **True total ≈ 169,800 lines.** BGRABitmap replaces the rasteriser only; none of those seven modules has an equivalent in ty-controls | **1 file, 1,721 lines** | **~99×** |
| Series types | **23** (`src/export/charts.ts`, 23 dirs under `src/chart/`) | **3 geometries** behind a 4-value enum (`ctLine`, `ctBar`, `ctPie`, `ctDonut`; donut = pie with a hole) | 3/23 = **13 %**, and each of the three is a stripped subset |
| Coordinate systems | **9 registered** (`cartesian2d`, `polar`, `geo`, `single`, `parallel`, `radar`, `calendar`, `matrix`, `graphView`) + `'none'` + the shared `View` pan/zoom base | **0** — there is no coordinate-system object at all. `TyChartValueToY` + `TyChartBarXRange` *are* the cartesian mapping, inlined; `DrawPie`'s `ArcTan2+90°` *is* the polar mapping, inlined | 0/9 |
| Axis types (scale classes) | **4** — ordinal, interval, time, log | **1 implicit** — a linear Y with a forced zero baseline and a hard-coded target of 5 ticks, plus an implicit ordinal X that is not a scale object | 0/4 as *addressable* types |
| Axis option surface | ~120 documented keys per axis (`axis-common.md` is 1,497 lines: `axisLine`, `axisTick`, `minorTick`, `axisLabel`, `splitLine`, `minorSplitLine`, `splitArea`, `name*`, domain, position, jitter, breaks) | **`ShowGrid: Boolean`** | 1/~120 |
| Non-coordinate UI components | **13 families** across 25 source dirs (title, legend, tooltip, axisPointer, toolbox, dataZoom, visualMap, brush, timeline, markPoint/markLine/markArea, graphic, aria+decal, thumbnail) | **3 present in name only** — `Title` (a caption string), a fixed non-interactive legend strip, a fixed in-bitmap tooltip box. 10 families entirely absent | 0/13 at parity |
| Documented option paths | **~1,950** across 59 top-level component/series documents (measured by expanding `{{ use: partial-* }}` includes; the true leaf count is higher because `label`/`itemStyle`/`lineStyle` blocks recur under `emphasis`/`blur`/`select`) | **12** — 9 published properties on the control + 3 on a series item | ~0.6 % |
| Visual channels | **10** (`color`, `colorHue`, `colorSaturation`, `colorLightness`, `colorAlpha`, `decal`, `opacity`, `liftZ`, `symbol`, `symbolSize`) × 4 mapping methods (linear/category/piecewise/fixed) | **1** — one flat colour per series | 1/10 |
| Element states | **4** (normal / emphasis / blur / select) with **8** `focus` values and **3** `blurScope` values | **1** — normal. A hover hit exists but drives only the tooltip; nothing restyles on hover | 1/4 |
| Symbols | **10 built-in** + every `empty*` variant + `path://` SVG data + `image://` raster, with `symbolSize`/`Rotate`/`Offset`/`KeepAspect` and callback forms | **1** — a filled circle of hard-coded radius 3 at line vertices | 1/10 |
| Easings / animation | **31 named easings** + arbitrary `cubic-bezier(a,b,c,d)` strings; enter/update/leave phases; per-datum `animationDelay(dataIndex)`; keyframe tracks; universal-transition shape morphing | **none** — the chart has no animation at all (`tyControls.Animation`/`Transitions` exist in the library and the chart uses neither) | 0 |
| Actions / events | **~46 action types**, **9 mouse events + ~45 action-derived events + 2 render-lifecycle events**, plus query filtering on `on()` | **1 chart-specific event** (`OnGetTooltip`) + `HitTestAt` + LCL's inherited mouse events | 1/~56 |
| Public instance API | **24 methods** + `on/off/one` + ~30 module-level registries + 7 lifecycle hooks | **7 methods** — `HitTestAt` + 6 `SaveToStream`/`SaveToFile` overloads | 7/24 |
| Label engine | 13 rectangular positions + 9 sector positions + funnel's 12 + polar bar's 5 + rich text + template and callback formatters + `hideOverlap`/`moveOverlap`/`labelLine` routing | **`ShowValues: Boolean`**, drawn at a hard-coded 8/400, no rotation, no formatter, no collision handling | 1/~40 |
| Data-model layers | **4** — `Source` (immutable metadata) → `DataProvider` (6 source formats) → `DataStore` (columnar, 5 dimension types) → `SeriesData` (names/ids/visuals/layouts), plus `dataset` + a transform DAG | **1** — a comma-separated `string` per series, re-parsed on every access | 1/4 |
| Theme reach | Themes may set the palette, background, dark-mode flag, per-component defaults, **per-series-type** defaults and **per-axis-type** defaults | 3 typeKeys (`TyChart`, `TyChartTooltip`, `TyChartSeries1..8`) and 5 metric tokens, **2 of which are defined in no theme at all** (`--chart-donut-hole`, `--chart-hit-radius`) | — |
| Demonstration surface | 606 live demo pages under `test/*.html` | 1 example, 4 series, 4 toggles | — |

### 1.2 The numbers that actually matter

Three of those rows dominate everything else:

1. **20 of the 23 series types are unrepresentable in the current data model**, not merely unimplemented.
   `TTyChartSeriesItem.Values` is a `string` parsed into `array of Double` by category index. A point is
   `(categoryIndex, value)`. There are no (x, y) pairs, so scatter, bubble, effectScatter, lines, candlestick
   (OCLH quadruples), boxplot (5-number summaries), heatmap (x,y,value triples), themeRiver (time,value,name
   triples), parallel (N dimensions), radar (N indicators), graph/sankey/chord (nodes + edges), and
   tree/treemap/sunburst (hierarchies) have nowhere to put their data. Blank parts are *skipped*
   (`'1,,3'` → 2 values), so there is also no null/NaN, which blocks `connectNulls`, `dataZoom.filterMode:'empty'`,
   stacked-area baselines, and LTTB's gap preservation.

2. **There is no coordinate-system abstraction, so every additional chart family is a from-scratch
   re-implementation of both layout and hit-testing.** ECharts gets scatter on 7 coordinate systems and
   `custom` on all of them for free because `dataToPoint`/`pointToData`/`containPoint`/`getArea` is an
   interface. In TTyChart the mapping is expressions inside `DrawBars`/`DrawLine`/`DrawPie` and their
   hand-written hit-test inverses.

3. **The rasteriser is not the bottleneck.** Report 09 §4.5 is unambiguous: BGRABitmap 11.6.6 already gives
   cubic and quadratic beziers, splines, `addPath(SvgPathString)`, winding *and* even-odd fill, antialiased
   arbitrary-path clipping, full affine transforms with a separate stroke matrix, linear **and** radial
   gradients, patterns, dash arrays with caps/joins, per-vertex Gouraud fills, path shadows, `isPointInPath`,
   rotated text (`TextOutAngle`, already in production in `tyControls.Menu.pas`) and text-along-a-path
   (`TextOutCurved`). Area, stacked/percent/horizontal bars, smooth and stepped lines, scatter, radar, gauges,
   heatmaps, funnel, candlestick, rose pie, rotated and curved labels, dashed marklines, gradient fills and
   crosshairs are all reachable **today, in terms of raster capability**. What blocks them is the data model,
   the missing coordinate/scale/series abstractions, the full-rebuild paint model, and the graphic-control
   base class.

   **`[corrected]` — but "the rasteriser" is not "the drawing stack".** That list is true of *BGRABitmap*
   and false of `TTyPainter`, the API every ty-controls control actually paints through. `TTyPainter`'s
   public surface (`tyControls.Painter.pas:123-232`) is chrome-shaped — `FillBackground`, `StrokeBorder`,
   `FillPointerShape`, `DrawEdge`, `DrawGlyph*`, `DropShadow`, `NineSlice`, `DrawImageFill`, `FillGlass`,
   `DrawText*`, `MeasureText`, `Scale`/`Unscale` — with **no general path, arc, polyline, transform, clip,
   dash or per-element alpha**. It escapes only via `property Bitmap: TBGRABitmap` (line 225), which
   `tyControls.Chart.pas` already reaches around it to use (`P.Bitmap.Canvas2D` at 1407 and 1529, plus
   three raw `P.Bitmap.FillRect` calls).

   Consequence: **a vector API on `TTyPainter` is a missing Tier 0 item**, and it is upstream of roughly
   forty rows in §5. Letting each series renderer reach for `Bitmap.Canvas2D` directly means each one
   re-implements DPI scaling, theme colour resolution, the bidi text path and the non-Windows
   supersampling gate — the exact bug class this repo has already paid for (`bgra-small-text-blur-linux`,
   `painter-bgra-overwrites-canvas-gdi`). See `11-critique.md` finding 2.

   One risk retired while checking this: `bgrapath.pas:2301` accepts `L H V C S Q T A` plus `M`/`Z` and
   the relative forms, and `'A'` dispatches to a full elliptical `arcTo(rx, ry, xAngle, largeArc,
   anticlockwise, x, y)`. **The complete SVG path grammar is supported**, so `path://` custom symbols
   need no parser and no dependency — Q5 loses one of its three items.

---

## 2. The full coverage matrix

"TTyChart today" is **Yes** only when the capability is present at a usable level, **Partial** when a
degenerate or hard-coded version exists, **No** otherwise.

### 2.1 Series

#### 2.1.1 Cross-cutting series machinery

| ECharts capability | TTyChart today | Class | Notes |
|---|---|---|---|
| 23 series types | No (3 geometries) | — | line, bar, pie only; pie/donut share one path |
| Mixed series types in one chart | No | NATURAL | `ChartType` is a control-level enum; unit header states "Still NOT included: mixed chart types" |
| Per-series coordinate-system binding (`coordinateSystem`) | No | HEAVY | Requires the coord-system interface first |
| `xAxisIndex`/`yAxisIndex`/`polarIndex`/`geoIndex`/`singleAxisIndex`/`calendarIndex`/`matrixIndex` (+ `*Id` since 6.0) | No | NATURAL | Needs multiple axes to exist first |
| `coordinateSystemUsage: 'data' \| 'box'` + `series.coord` (v6 nesting) | No | HEAVY | Series/components laid out inside a matrix or calendar cell |
| Data shapes: scalar, `[x,y]`, `[x,y,z,…]`, `{value}`, `{name,id,groupId,value,…}` | Partial (scalar only) | NATURAL | `Values: string` → scalars only |
| `'-'` / `null` / `NaN` as "no data" | No | NATURAL | Blank CSV parts are dropped, not NaN'd |
| Per-datum overrides (`itemStyle`, `label`, `symbol*`, `emphasis`, `blur`, `select`, `tooltip`, `cursor`) | No | HEAVY | Needs an explicit per-point override record with Has-flags |
| Per-datum identity (`name`, `id`, `groupId`, `childGroupId`) | No | NATURAL | Prerequisite for diff-based animation |
| `dataset` + `datasetIndex`/`datasetId` | No | HEAVY | See §2.4 |
| `encode` (11 coordinate roles + 7 visual roles) | No | NATURAL | Record of `array of Integer` per role |
| `series.dimensions` (`{name,type,displayName}`) | No | NATURAL | |
| `seriesLayoutBy: 'column' \| 'row'` | No | NATURAL | Index transposition in the provider layer |
| 4 states (normal/emphasis/blur/select) | No | HEAVY | Hover changes the tooltip only |
| `emphasis.focus`: none \| self \| series \| ancestor \| descendant \| relative \| adjacency \| trajectory | No | HEAVY | 8 values; the last five need graph/tree traversal |
| `emphasis.blurScope`: coordinateSystem \| series \| global | No | NATURAL | |
| `emphasis.disabled`, `emphasis.scale` (bool \| number) | No | NATURAL | |
| `selectedMode`: false \| true \| single \| multiple \| series; `select.disabled` | No | NATURAL | 19 series expose it |
| `itemStyle.color: 'inherit'` sentinel (and `'auto'` legacy) | No | NATURAL | |
| `stack` + `stackStrategy` (samesign/all/positive/negative) + `stackOrder` (seriesAsc/seriesDesc) | No | HEAVY | Sign-aware cumulation; adds 2 calculated dimensions |
| Stack-by-category (ordinal base) vs stack-by-index (numeric base) | No | HEAVY | Needs the inverted ordinal index |
| `sampling`: lttb \| minmax \| average \| sum \| max \| min \| nearest \| callback | No | HEAVY (LTTB) | Report 06 §8 has the exact ECharts LTTB, incl. index-space x and NaN-gap preservation |
| `large` / `largeThreshold` batched single-path draw | No | NATURAL | Flat point buffer + one composite path + arithmetic hit-scan |
| `progressive` / `progressiveThreshold` / `progressiveChunkMode` (sequential \| mod) | No | HEAVY | Frame-budget streaming; the `mod` striding formula is in report 01 §4.2 |
| `animationThreshold` (2000) | No | NATURAL | |
| `hoverLayerThreshold`, `zlevel` as a separate canvas layer | No | BROWSER-BOUND | Ordering semantics port; the layering rationale does not |
| `blendMode` (per series → `globalCompositeOperation`) | No | BROWSER-BOUND | Only `'lighter'` is realistically worth it (BGRA has `TBlendOperation`) |
| `cursor` (CSS cursor name) | Partial | BROWSER-BOUND | Control-level `Cursor: TCursor` only; needs a name→TCursor table if the vocabulary is kept |
| `silent` (whole series out of hit-testing) | No | NATURAL | |
| `colorBy: 'series' \| 'data'` | Partial | NATURAL | Radial charts colour by datum, axes charts by series — hard-wired, not an option |
| `legendHoverLink` | No | NATURAL | |
| `universalTransition` (`enabled`, `seriesKey`, `divideShape`, `delay`) | No | HEAVY | Report 07 recommends deferring; cross-fade + position tween covers 80 % of the value |
| `markPoint` / `markLine` / `markArea` | No | NATURAL + light stats | Positioning modes are plumbing; min/max/average/median are trivial |
| `labelLayout` (object form): hideOverlap, moveOverlap, x/y/dx/dy/rotate/width/height/align/fontSize | No | HEAVY | |
| `labelLayout` (callback form), `formatter`/`symbolSize`/`symbol`/`color` callbacks | No | BROWSER-BOUND | Become Pascal events/method pointers |
| `labelLine` (show/showAbove/length/length2/smooth/minTurnAngle/maxSurfaceAngle) | No | NATURAL surface, HEAVY routing | |
| `decal` accessibility pattern fills | No | HEAVY | LCM tile generation + rotated pattern fill |
| Gradients (linear + radial, `global` flag) and image-pattern fills in `itemStyle.color` | No | NATURAL | BGRA has both gradient kinds and `createPattern` |
| `itemStyle` full key set (13 keys incl. dash array, dashOffset, cap, join, miterLimit) | Partial (fill only) | NATURAL | Series colour only today |
| `lineStyle` full key set (12 keys) | Partial (width 2, solid, hard-coded) | NATURAL | |
| `areaStyle` (6 keys) | No | NATURAL | |
| `z` / `z2` ordering | No | NATURAL | Draw order is code order today |

#### 2.1.2 `line`

| ECharts capability | TTyChart today | Class | Notes |
|---|---|---|---|
| Polyline + per-point symbols | Partial | NATURAL | Fixed circle marker, radius 3, no symbol option |
| `smooth: 0..1` with segment-length-ratio control points + `smoothConstraint` box clamping | No | HEAVY | Must reproduce `poly.ts drawSegment` for visual parity; BGRA `splineTo` is *not* the same curve |
| `smoothMonotone: 'x' \| 'y' \| 'none'` | No | HEAVY | Axis-aligned control points |
| `step: false \| true \| 'start' \| 'middle' \| 'end'` | No | NATURAL | `'middle'` injects two vertices |
| `areaStyle` + `origin: 'auto' \| 'start' \| 'end' \| number` | No | NATURAL | |
| Stacked area (baseline = previous series' `stackedOver` polyline) | No | HEAVY | Depends on the stacking engine |
| `connectNulls` (incl. forward search for smooth control points) | No | NATURAL | Needs NaN in the data model first |
| `clip` with per-element-kind semantics (line geometrically clipped, symbol dropped by centre) | No | NATURAL | Two different rules; easy to get wrong |
| `showSymbol`; `showAllSymbol: 'auto'` (5-point probe → axisLabel.interval fallback) | No | HEAVY-lite | |
| `endLabel` (5.0.0) + `valueAnimation` (text interpolated at the animating clip edge) | No | HEAVY | Needs `cubicRootAt` to invert the curve at the clip x |
| visualMap → screen-space `LinearGradient` along an axis (`getVisualGradient`) | No | NATURAL | One stroke, one gradient, 10 px bleed, `outerColors` head/tail |
| `triggerEvent: false \| true \| 'line' \| 'area'` (6.1.0) | No | HEAVY | Stroke hit-test = distance-to-polyline; fill = point-in-polygon |
| `emphasis.lineStyle.width: 'bolder'`; `emphasis.scale` | No | NATURAL | |
| Point-level add/remove diff animation (`lineAnimationDiff`) | No | HEAVY | |
| Symbol set + `symbolSize`/`Rotate`/`KeepAspect`/`Offset` (px or %) | No | NATURAL (`path://` HEAVY) | |
| Line on polar | No | NATURAL | No `step`, no `endLabel` there |
| Defaults: lineStyle width 2, symbol `emptyCircle`, symbolSize 6, `animationEasing: 'linear'` | Partial | NATURAL | Width 2 matches by accident |

#### 2.1.3 `bar`

| ECharts capability | TTyChart today | Class | Notes |
|---|---|---|---|
| Rect bars, orientation from axis roles, negatives across the baseline | Partial | NATURAL | Vertical only; negatives do hang below correctly |
| `calcBarWidthAndOffset` two-pass solver shared across all bar series on one axis | No | HEAVY | ~120 lines; unlocks bar, pictorialBar, candlestick, boxplot widths and `api.barLayout` |
| `barWidth` / `barMaxWidth` / `barMinWidth` (min outranks max and remainedWidth) | No | HEAVY | |
| `barGap` (`'10%'`, `'-100%'` = overlap) / `barCategoryGap` (`max(35−4n,15)%`) | No | HEAVY | TTyChart uses a fixed 15 % inset per side at two nesting levels |
| `barMinHeight`, `barMinAngle` | No | NATURAL | Zero-value bars currently draw nothing and hit nothing |
| `itemStyle.borderRadius` (number \| 4-array) | No | NATURAL | |
| Horizontal bars | No | NATURAL | |
| Polar sector bars (angle-base radial, radius-base tangential) | No | HEAVY | Sector with corner radius |
| `roundCap` (Sausage capsule shape, polar) | No | HEAVY | Forces element recreation in ECharts |
| `showBackground` + `backgroundStyle` (own borderRadius) | No | NATURAL | |
| `large` mode (`ctx.rect` over a Float32Array + throttled 30 ms hit-scan) | No | NATURAL | |
| `realtimeSort` (bar race): order re-derived per frame from *animated pixel length*, dispatched as `changeAxisOrder`, gated by in-view comparison | No | HEAVY | The axis order changes, not the data; needs animated axis labels |
| `clip` (6.1.0 geometric clipping of overflow) | No | NATURAL | |
| Polar label positions (start/insideStart/middle/insideEnd/end) | No | NATURAL | |
| `label.valueAnimation` (interpolated number text) | No | NATURAL | |
| `brushSelector` = rect containment | No | NATURAL | |
| Grouped multi-series bars | Yes | NATURAL | Two nested `TyChartBarXRange` splits |
| Stacked / percent-stacked bars | No | HEAVY | |

#### 2.1.4 `pictorialBar`

| ECharts capability | TTyChart today | Class | Notes |
|---|---|---|---|
| Invisible reference bar + glyph(s); `stack` force-disabled; `barGap` default `'-100%'`; `clip` default false | No | NATURAL | |
| Series-level **or** per-data-item cascade for every `symbol*` option | No | NATURAL | |
| `symbolSize` percent resolution (category size vs `boundingLength`, repeat-dependent) | No | HEAVY | |
| `symbolPosition` start/end/center + `symbolOffset` (px or % of symbolSize) | No | NATURAL | |
| `symbolRepeat`: false \| true \| number \| `'fixed'`, with margin re-solve then re-cut by data | No | HEAVY | The two-stage solve is the whole feature |
| `symbolMargin` incl. the `'!'` end-gap suffix and negative overlap | No | HEAVY | |
| `symbolRepeatDirection` (z-order + animationDelay index order) | No | NATURAL | |
| `symbolClip` (clip the glyph run at the data value) | No | NATURAL | |
| `symbolBoundingData` (number or `[neg,pos]`) | No | HEAVY | Drives both sizing and the repeat field |
| `symbolPatternSize` (400) + image-pattern glyph fill | No | HEAVY | Texture brush scaled by `symbolSize/symbolPatternSize` |
| `pxSign` 4-way truth table (boundingLength sign × axis inverse × x/y) | No | HEAVY | |
| `valueLineWidth` correction for `strokeNoScale` under `symbolScale` | No | HEAVY | |
| `symbolRotate` (rotates about centre, does not affect layout) | No | NATURAL | |
| Per-repeat `animationDelay(dataIndex, {index, count})` | No | NATURAL | |

#### 2.1.5 `scatter` / `effectScatter`

| ECharts capability | TTyChart today | Class | Notes |
|---|---|---|---|
| Symbols at (x, y) points | No | NATURAL | Blocked by the data model, not the drawing |
| `symbolSize` default 10, `itemStyle.opacity` 0.8 | No | NATURAL | |
| `large` / `largeThreshold` 2000 batched symbol path | No | NATURAL | |
| `clip` by symbol centre | No | NATURAL | |
| `stack` on scatter | No | HEAVY | |
| Scatter on 7 coordinate systems | No | HEAVY | Per coord system |
| Jitter, `jitterOverlap: true` (random within band, clamped by `bandWidth − 2r`) | No | NATURAL | Axis-level option (v6.0) |
| Jitter, `jitterOverlap: false` (greedy bidirectional collision packer, 1-D beeswarm, with give-up fallback) | No | HEAVY | |
| `effectType: 'ripple'`, `showEffectOn: 'render' \| 'emphasis'` | No | NATURAL | |
| `rippleEffect` (`number` 3, `period` 4 s, `scale` 2.5, `brushType`, `color`) | No | NATURAL | N clones, staggered scale+opacity loops |
| `brushSelector` = point containment | No | NATURAL | |

#### 2.1.6 `candlestick` / `boxplot`

| ECharts capability | TTyChart today | Class | Notes |
|---|---|---|---|
| candlestick: OCLH data, 8-point ends array (4 body corners + 4 whisker endpoints) | No | NATURAL | |
| candlestick: OHLC→OCLH remap via `encode: {y:[1,4,3,2]}`; `type: 'k'` alias | No | NATURAL | |
| candlestick: `layout` horizontal/vertical auto-derived from axis types, not written back | No | NATURAL | |
| candlestick: `barWidth`/`barMinWidth`/`barMaxWidth` clamping against band width | No | NATURAL | |
| candlestick: three-way colour (`color`/`borderColor` bull, `color0`/`borderColor0` bear, `borderColorDoji`) | No | NATURAL | |
| candlestick: `subPixelOptimize` for crisp 1 px lines on the category axis | No | NATURAL | Worth adopting for axis/grid lines generally |
| candlestick: `isSimpleBox` degeneration at `candleWidth ≤ 1.3` | No | NATURAL | |
| candlestick: `large: true` by default, threshold 600, packed `[sign,x,yHigh,yLow]` | No | NATURAL | |
| candlestick: `getShadowDim()` feeding the dataZoom slider sparkline | No | NATURAL | |
| boxplot: `[min,Q1,median,Q3,max]`, 12-point glyph | No | NATURAL | |
| boxplot: multi-series band packing (`avail = band·0.8−2`, `boxGap = avail/n·0.3`, `boxWidth:[7,50]`) | No | NATURAL | |
| boxplot: `visualDrawType: 'stroke'` (palette colours the outline) | No | NATURAL | |
| boxplot: the `boxplot` **dataset transform** (quantiles, `boundIQR` 1.5, dual output + outliers, `itemNameFormatter`) | No | HEAVY-lite | ~40 lines, very high value/effort ratio |
| Both: `emphasis`/`blur`/`select` with the full 3-colour itemStyle; `clip`; `brushRect` | No | NATURAL | |

#### 2.1.7 `heatmap`

| ECharts capability | TTyChart today | Class | Notes |
|---|---|---|---|
| Cartesian cells (both axes category + `onBand`, cell = `calcBandWidth + 0.5` seam fix) | No | NATURAL | |
| `itemStyle.borderRadius` on cells, per-item override, in-cell labels | No | NATURAL | |
| Hard dependency on `visualMap` for any colour at all | No | HEAVY | visualMap must exist before heatmap means anything |
| Calendar-backed cells | No | HEAVY | Needs the calendar coord system |
| Matrix-backed cells (`dataToLayout`) | No | HEAVY | Needs the matrix coord system |
| Geo density field: radial-gradient brush + additive alpha splatting + 256-entry LUT recolour + `[minOpacity,maxOpacity]` remap | No | HEAVY | BGRA has direct pixel access — *easier* natively than in the browser |
| `pointSize` (20) / `blurSize` (30) / `minOpacity` / `maxOpacity` | No | NATURAL | Geo only |

#### 2.1.8 `pie` / `sunburst` / `funnel` / `gauge` / `radar` / `chord`

| ECharts capability | TTyChart today | Class | Notes |
|---|---|---|---|
| pie: annular sector, `radius:[r0,r]` donut, `center` | Partial | NATURAL | Donut hole from `--chart-donut-hole` (55 %), a metric defined in no theme |
| pie: `startAngle` (90), `endAngle` (`'auto'` \| number = partial pie), `clockwise` | No | NATURAL | Start angle is hard-coded |
| pie: `padAngle` + `minAngle` with combined clamp and two-branch angle redistribution | No | NATURAL | Watch the `minAngle + padAngle` combined clamp |
| pie: `roseType: 'radius' \| 'area'` (Nightingale) | No | NATURAL | |
| pie: `stillShowZeroSum`, `showEmptyCircle`, `emptyCircleStyle` | No | NATURAL | |
| pie: `itemStyle.borderRadius` (number \| `[in,out]` \| 4-array, % of `\|r−r0\|`) | No | HEAVY | Arc-fillet path construction |
| pie: `percentPrecision` with largest-remainder apportionment (`getPercentSeats`) so labels sum to 100 | Partial | HEAVY | Percent is computed and shown in the tooltip, but naively rounded |
| pie: `label.position` outer/inside/center; `label.rotate` number \| radial \| tangential \| tangential-noflip | Partial | NATURAL | One hard-coded label at 60 % of ring thickness |
| pie: `avoidLabelOverlap` (half-plane split, shift layout, ellipse-implicit x re-solve, text re-wrap, elbow re-clamp) | No | HEAVY | The biggest label algorithm in the family, ~600 lines |
| pie: `label.alignTo` none/labelLine/edge + `edgeDistance` + `bleedMargin` + `distanceToLabelLine` | No | HEAVY | Coupled to the solver above |
| pie: `labelLine` length 15 / length2 30 / smooth / minTurnAngle 90 / maxSurfaceAngle 90 | No | NATURAL surface | |
| pie: `minShowLabelAngle`, `label.overflow: 'truncate'` | No | NATURAL | |
| pie: `selectedMode` + `selectedOffset` (translate along mid-angle) | No | NATURAL | |
| pie: `emphasis.scale` + `scaleSize`; `animationType` expansion/scale | No | NATURAL | |
| pie: multiple pie series / pie per map region (`coordinateSystemUsage: 'box'`) | No | HEAVY | `DataExtent` `Break`s after series 0 for radial types today |
| sunburst: recursive angular subdivision + per-depth ring radii + `minAngle` | No | NATURAL | |
| sunburst: `levels[]` indexed by depth (`levels[0]` = roll-up node), per-level `radius` override | No | NATURAL | |
| sunburst: drill-down (`nodeClick: 'rootToNode'`) + virtual roll-up ring + actions | No | NATURAL | |
| sunburst: `nodeClick: 'link'` + `data.link`/`target` | No | BROWSER-BOUND | Map to `OpenURL` or an event |
| sunburst: `sort` desc/asc/null/comparator | No | NATURAL (callback BROWSER-BOUND) | |
| sunburst: algorithmic colour ramp `lift(parent, (depth−1)/(h−1)·0.5)` | No | NATURAL | |
| sunburst: `label.rotate` radial/tangential, `position` inside/outside, `align` inner/outer edge, `label.minAngle`, `label.silent` | No | NATURAL | |
| funnel: 4-point quads, `min`/`max`, `minSize`/`maxSize`, `gap`, `orient`, `funnelAlign` | No | NATURAL | Trivially portable end-to-end |
| funnel: `sort` ascending/descending/none | No | NATURAL | Comparator form BROWSER-BOUND |
| funnel: 10+ label anchors with orient-aware fallback; per-item `itemStyle.width`/`height` | No | NATURAL | |
| gauge: `startAngle` 225 / `endAngle` −45 / `clockwise`, `min`/`max`, `splitNumber` | No | NATURAL | |
| gauge: `axisLine.lineStyle.color` as `[[stop,color],…]` multi-band arc | No | NATURAL | |
| gauge: `axisLine.roundCap` / `progress.roundCap` (Sausage) | No | NATURAL | |
| gauge: `progress` (show/width/overlap/clip/`itemStyle.color:'auto'`) with multi-series stacking | No | NATURAL | |
| gauge: `splitLine`/`axisTick` with % lengths and `distance`; `axisLabel.rotate` number/radial/tangential | No | NATURAL | |
| gauge: built-in tapered needle (4-point `PointerPath`, base offset rule at `width ≥ r/3`) | No | NATURAL | |
| gauge: `pointer.icon` as a symbol name | No | NATURAL | |
| gauge: `pointer.icon` as `path://` SVG path data | No | HEAVY | Needs the SVG path parser (shared with symbols, decal, legend icons, custom) |
| gauge: `pointer.length/width/offsetCenter/keepAspect/showAbove`; `anchor` hub | No | NATURAL | |
| gauge: `title`/`detail` text blocks with own box/border/padding/% offsets/formatter/`valueAnimation` | No | NATURAL | |
| gauge: multi-value gauges (per-data-item pointer/progress/title/detail) | No | NATURAL | |
| radar: component (coordinate system, owns grid + axes + names) vs series (polygons only) | No | NATURAL (architectural) | |
| radar: `indicator[]` with per-axis `{name,min,max,color,axisType}` and auto-normalisation | No | NATURAL | |
| radar: `shape: 'polygon' \| 'circle'`; `splitLine`/`splitArea` colour **arrays** → alternating bands | No | NATURAL | |
| radar: tick alignment across N independently-scaled axes (dummy IntervalScale + `scaleCalcAlign`) | No | HEAVY | |
| radar: `axisName` + formatter, `axisNameGap`, `startAngle`, `clockwise` (v6.1), `triggerEvent` | No | NATURAL | |
| radar: multiple radars via `radarIndex` | No | NATURAL | |
| chord (v6): ring of node arcs from a graph, `radius:['70%','80%']`, `padAngle`, `startAngle`/`endAngle` | No | NATURAL | |
| chord: `minAngle` deficit/surplus **borrowing solver** (3 passes + `surplusAsMuchAsPossible` pre-check) | No | HEAVY-lite | Get it wrong and small nodes vanish or the ring overflows |
| chord: ribbon path `arc(r0) → cubic(cp lerped 70 % to centre) → arc → cubic → close` | No | NATURAL | |
| chord: `itemStyle.borderRadius` on node arcs | No | HEAVY | Same sector-fillet work as pie |
| chord: `lineStyle.color: 'source' \| 'target' \| 'gradient'`; `edgeLabel`; `focus: 'adjacency'` | No | NATURAL | |

#### 2.1.9 Hierarchical / relational: `tree` / `treemap` / `graph` / `sankey` / `parallel` / `themeRiver`

| ECharts capability | TTyChart today | Class | Notes |
|---|---|---|---|
| tree: **Reingold–Tilford tidy tree in Buchheim linear-time form** (firstWalk/apportion/contour threading/moveSubtree/secondWalk, pluggable separation) | No | HEAVY | The canonical hard part; the naive version overlaps subtrees |
| tree: `layout: 'orthogonal' \| 'radial'`; `orient` LR/RL/TB/BT | No | NATURAL once tidy layout exists | |
| tree: `edgeShape: 'curve'` (`lineStyle.curveness` 0.5) \| `'polyline'` + `edgeForkPosition` | No | NATURAL | |
| tree: `expandAndCollapse` + `initialTreeDepth` (2) + `data.collapsed` + action | No | NATURAL | |
| tree: `emptyCircle` symbol whose inner fill encodes "has collapsed subtree" | No | NATURAL | A real semantic, not styling |
| tree: `leaves{label,itemStyle,emphasis,blur,select}` leaf-only inheritance; `nodeScaleRatio` 0.4 | No | NATURAL | |
| treemap: **squarified layout** (Bruls–Huizing–van Wijk, `worst`/`position`/row accumulation, `squareRatio` = golden ratio) | No | HEAVY | ~150 lines, well specified |
| treemap: `sort`, `visibleMin` (10 px²), `childrenVisibleMin` | No | NATURAL | |
| treemap: `leafDepth` drill-down + `zoomToNodeRatio` + 4 actions with rollUp/drillDown direction and rect-morph animation | No | HEAVY | |
| treemap: `breadcrumb` chevron strip | No | NATURAL | A small custom-drawn control — ty-controls' wheelhouse |
| treemap: `upperLabel` parent header band | No | NATURAL | |
| treemap: `itemStyle.gapWidth` vs `borderWidth`; `borderColorSaturation` (border derived from own fill) | No | NATURAL | |
| treemap: visual sub-engine (`visualDimension`, `colorMappingBy` index/value/id, `colorAlpha`, `colorSaturation`, `visualMin/Max`, parent inheritance) | No | HEAVY | A system, not a knob |
| treemap: `roam`/`roamTrigger`/`scaleLimit`, `clipWindow`, `drillDownIcon` | No | NATURAL | |
| graph: `layout: 'none'` (explicit x/y) | No | NATURAL | |
| graph: `layout: 'circular'` spaced by value or symbolSize, `circular.rotateLabel` | No | NATURAL | |
| graph: **force simulation** (spring on edges, gravity to centre, O(n²) all-pairs repulsion, friction decay 0.992, converge < 0.01; no Barnes-Hut) | No | HEAVY | Physics is ~60 lines; the timer/frame-budget/converge-and-stop plumbing is the work |
| graph: `force.repulsion` / `edgeLength` as scalar or `[min,max]` linearMap'd from value (edgeLength reversed) | No | NATURAL | |
| graph: `force.gravity/friction/initLayout/layoutAnimation`, `data.fixed`, `links.ignoreForceLayout`, position preservation by id | No | NATURAL | |
| graph: `autoCurveness` symmetric fan for parallel edges, direction-agnostic keying | No | NATURAL | |
| graph: edge trimming to node symbol boundary (curve∩circle scan + 32-step bisection) | No | HEAVY-lite | Needed or arrowheads sit under the nodes |
| graph: `edgeSymbol`/`edgeSymbolSize` end markers; `edgeLabel` (`position: 'middle'`) | No | NATURAL | |
| graph: `categories[]` with style inheritance + legend binding | No | NATURAL | |
| graph: `draggable` (force warm-up / circular snap-back); `focus: 'adjacency'` | No | NATURAL | |
| sankey: layer assignment (BFS depth) + `nodeAlign` justify/left/right + `moveSinksRight` | No | NATURAL | |
| sankey: relaxation loop (`layoutIterations` 32 × relax/resolveCollisions with decaying alpha) | No | HEAVY-lite | ~200 lines, deterministic |
| sankey: `nodeWidth`/`nodeGap`/`sort`, ribbon cubic with `curveness` 0.5 | No | NATURAL | |
| sankey: `orient: 'vertical'` (full axis swap) | No | NATURAL if axis-parameterised from the start | Painful to retrofit |
| sankey: `draggable` (`dragNode`), `levels[].depth` styling, `roam` (v6) | No | NATURAL | |
| sankey: `focus: 'trajectory'` (full upstream + downstream reachability) | No | NATURAL | Two BFS |
| sankey/chord: `lineStyle.color: 'source' \| 'target' \| 'gradient'` | No | NATURAL | |
| parallel: component + N `parallelAxis` + polyline series | No | NATURAL (architectural) | |
| parallel: `layout` horizontal/vertical; `smooth`; `parallelAxisDefault` shorthand | No | NATURAL | |
| parallel: per-axis interval **brushing** with `activeOpacity`/`inactiveOpacity` and AND combination | No | NATURAL interaction | A real drag-handle widget per axis |
| parallel: `realtime` (filter during drag vs on release) | No | NATURAL | |
| parallel: `axisExpandable` fisheye lens (`axisExpandCenter/Count/Width/TriggerOn/Rate/Debounce/SlideTriggerArea/Window`) | No | HEAVY | Arguably skippable |
| themeRiver: singleAxis-only stream graph; layout rect + `boundaryGap ['10%','10%']` | No | HEAVY (needs singleAxis) | |
| themeRiver: `fixData` zero-filling so every layer spans every time key | No | NATURAL | |
| themeRiver: `computeBaseline` symmetric centred stream (simplified Lee Byron, **not** wiggle-minimising) | No | NATURAL | |
| themeRiver: ribbons as closed `ECPolygon` with hard-coded `smooth: 0.4`, `smoothConstraint: false` | No | HEAVY | Reuses the line smoothing code |
| themeRiver: per-layer labels at the first data point; growing-rect clip reveal | No | NATURAL | |

#### 2.1.10 `map` / `lines` / `custom`

| ECharts capability | TTyChart today | Class | Notes |
|---|---|---|---|
| geo component as a coordinate system, usable with no series | No | HEAVY | |
| `registerMap(name, geoJSON, specialAreas)` → Region polygon rings, holes, centroid, point-in-polygon | No | HEAVY-lite | Parser + even-odd fill + bbox index |
| `registerMap(name, {svg})` — SVG base maps, named elements as regions, `viewBox` | No | HEAVY / BROWSER-BOUND | Needs an SVG subset parser + renderer |
| `projection: {project, unproject, stream}` (pluggable, d3-geo in the docs) | No | BROWSER-BOUND as pluggable / NATURAL with fixed projections | Ship Mercator/equirectangular/Albers behind an interface |
| Projected bounding rect by perimeter sampling | No | NATURAL | |
| `aspectScale` (0.75) latitude compensation; `boundingCoords`; `layoutCenter`/`layoutSize` | No | NATURAL | |
| `center` (lng/lat, projected, or `'%'`), `zoom`, `scaleLimit` | No | NATURAL | |
| `roam: false \| true \| 'scale'/'zoom' \| 'move'/'pan'` + `roamTrigger: 'selfRect' \| 'global'` | No | HEAVY | The `View` transform stack: raw ∘ roam = overall + inverse, synced back to center/zoom |
| `preserveAspect: false \| 'contain' \| 'cover'` + Align + VerticalAlign (v6) | No | NATURAL | `object-fit` as options |
| `nameMap`, `nameProperty`, `specialAreas` (Alaska/Hawaii insets) | No | NATURAL | |
| `regions[]` per-region overrides; `selectedMode`; geoSelect/geoUnSelect/geoToggleSelect/geoRoam actions | No | NATURAL | |
| map series: `mapValueCalculation` sum/average/max/min across co-registered series | No | NATURAL | |
| map series: `showLegendSymbol`; `labelLayout`/`labelLine` for cramped regions | No | NATURAL | |
| lines: 2-point lines with `lineStyle.curveness` quadratic bow (there is **no** great-circle mode) | No | NATURAL | True geodesics would be an improvement over ECharts |
| lines: `polyline: true` arbitrary-length tracks | No | NATURAL | |
| lines: `symbol`/`symbolSize` end caps `[start, end]` | No | NATURAL | |
| lines: `effect` flying trail (period/constantSpeed/delay/symbol/symbolSize/color/loop/roundTrip, auto-rotated to tangent) | No | NATURAL | Timer + arc-length parameterisation |
| lines: `effect.trailLength` comet tail | No | BROWSER-BOUND as implemented | Needs an offscreen accumulate + alpha fade; a re-think, not a port |
| lines: `large` (flat Float32Array segment batch + custom hit-test); `clip` | No | NATURAL | |
| custom: `renderItem(params, api)` callback contract | No | BROWSER-BOUND as a JS API | **The single highest-value concept to port** — as a Pascal event returning a shape list |
| custom: 15 element types (group/path/image/text/compoundPath/rect/circle/ring/sector/arc/polygon/polyline/line/bezierCurve/ellipse) | No | NATURAL | The painter draws all of these |
| custom: `api.coord` / `api.layout` (v6) / `api.size` (data range → pixel size, point-dependent on log/polar) | No | NATURAL | Must be exposed anyway |
| custom: `api.style` / `api.styleEmphasis` / `api.visual` (9 channels) | No | NATURAL | |
| custom: `api.barLayout` (reuse the real bar solver from a callback) | No | HEAVY | Only after the bar solver exists |
| custom: `api.currentSeriesIndices`, `api.getWidth/getHeight` | No | NATURAL | |
| custom: `api.font` (CSS font shorthand string), `api.getZr`, `api.getDevicePixelRatio` | No | BROWSER-BOUND | Return a font record; drop the rest |
| custom: `path` element with SVG `pathData`/`d` + `layout: 'center' \| 'cover'` auto-fit | No | HEAVY | SVG path parser + fit transform |
| custom: per-element `clipPath` (any path shape) | No | HEAVY | BGRA `clip` on the current path handles it (antialiased mask) |
| custom: `textContent` + `textConfig` (attached labels with auto-placement) | No | NATURAL | |
| custom: `$mergeChildren: false \| 'byName' \| 'byIndex'`, diffing by id/name | No | HEAVY | Retained-mode reconciliation |
| custom: `transition` / `enterAnimation` / `updateAnimation` / `leaveAnimation` / `during` / `keyframeAnimation` | No | HEAVY | A general property-tween engine |
| custom: `morph: true` shape morphing between path types | No | HEAVY / near-BROWSER-BOUND | |
| custom: `info` payload + `chart.on('click', {element: 'name'})` scoping | No | NATURAL | |
| custom: `coordinateSystem: 'none'` (free-floating pixel positioning) | No | NATURAL | |

### 2.2 Coordinate systems and axes

| ECharts capability | TTyChart today | Class | Notes |
|---|---|---|---|
| A coordinate-system **interface** (`dataToPoint`/`dataToLayout`/`pointToData`/`containPoint`/`getAxis`/`getAxes`/`getBaseAxis`/`getOtherAxis`/`clampData`/`getArea`/`shouldClip`/`getBoundingRect`/`getViewRect`/`getRoamTransform`) | No | NATURAL (as a design) | The single most load-bearing abstraction in ECharts |
| Master vs per-series split (one `Grid` holding N `Cartesian2D`) | No | NATURAL | |
| `cartesian2d` (grid), multiple grids per chart, axes shared across cartesians | Partial (one implicit grid) | NATURAL | |
| `polar` (`radiusAxis` + `angleAxis`) | No | NATURAL | Pie's trig exists but is not a coordinate system |
| `single` (one axis, one strip) | No | NATURAL | themeRiver's only system |
| `radar` (N independent indicator axes) | No | NATURAL | |
| `calendar` (date → week/day-of-week cell) | No | NATURAL | |
| `geo` (GeoJSON or SVG, projection, roam) | No | HEAVY | |
| `parallel` (N axes + brushing) | No | HEAVY | |
| `matrix` (v6: table/pivot with tree headers, body, corner, merged cells, locator algebra) | No | HEAVY | |
| `graphView` (`View` pan/zoom viewport) | No | HEAVY | Shared with geo |
| `'none'` pseudo-system (component lays itself out against the canvas box) | Partial | NATURAL | Everything is effectively `'none'` today |
| v6 nesting: `coordinateSystemUsage: 'box'` — a grid/polar/geo/legend/title inside a matrix or calendar cell | No | HEAVY | Cheap if designed in, expensive to retrofit |
| `convertToPixel` / `convertFromPixel` / `convertToLayout` / `containPixel` public API | No | HEAVY | One per coord system |
| grid: `show`/`backgroundColor`/`borderColor`/`borderWidth`/`opacity`/shadow | No | NATURAL | |
| grid: `left/top/right/bottom/width/height` in px, `'x%'`, `'auto'` | No | NATURAL | Five hard-coded literals today (margin 8, title 20, legend 18, Y gutter 38, X band 16) |
| grid: `containLabel` → v6 `outerBoundsMode`/`outerBounds`/`outerBoundsContain`, two-pass shrink-by-overflow layout | No | HEAVY | The fiddliest single piece of the grid; **a 6-digit tick label overflows the fixed 38 px gutter today** |
| Axis type `'value'` (Interval scale, nice ticks 1/2/5×10^k) | Partial | NATURAL | `TyChartNiceRange` is a Heckbert nice-number pass with a hard-coded target of 5 ticks |
| Axis type `'category'` (Ordinal, data from `axis.data` or auto-collected) | Partial | NATURAL | `Categories: TStrings`, but not a scale object |
| Axis type `'time'` (12-level ladder, per-level step search, level-tagged ticks) | No | HEAVY | Budget real time; 27 locale month/weekday tables |
| Axis type `'log'` (`logBase`, decade tick search, decade minor ticks) | No | NATURAL | |
| `nice()` ladder 1/2/3/5/10 per decade + two rounding modes + `NICE_MODE_MIN` | Partial (1/2/5 only) | NATURAL | |
| `increaseInterval` (1→2→3→5→10) for label-collision escalation | No | NATURAL | |
| `intervalScaleEnsureValidExtent` degenerate-extent expansion | Partial | NATURAL | `TyChartNiceRange` expands degenerate input to a unit span |
| `min` / `max` (number, `'dataMin'`/`'dataMax'`, `'x%'`, callback, category ordinal incl. negative) | No | NATURAL | |
| `dataMin` / `dataMax` (v6.1: extend the domain but keep the nice algorithm) | No | NATURAL | |
| `scale` (don't force zero into the extent) | No | NATURAL | Zero is **forced** in `AxesData` today |
| `splitNumber`, `interval`, `minInterval`, `maxInterval`, `logBase` | No | NATURAL | Tick target is a hard-coded 5 |
| `boundaryGap` — category band mode vs `['20%','20%']` domain padding | No | NATURAL | Two different meanings on one key |
| `containShape` (v6.1: margin so bar/candlestick/boxplot don't overflow) | No | HEAVY | |
| `inverse`, `startValue` | No | NATURAL | |
| `alignTicks` (v5.3, value/log): grow intervals until tick counts match across axes | No | HEAVY | |
| Multiple x/y axes, `gridIndex`, `position` (top/bottom, left/right), `offset` for 3rd+ axes | No | NATURAL | Unit header: "Still NOT included: secondary axes" |
| `axisLine`: `show:'auto'`, `onZero` true/false/`'auto'`, `onZeroAxisIndex`, arrow `symbol`/`symbolSize`/`symbolOffset`, full lineStyle, `breakLine` | Partial (a plain line) | NATURAL; onZero arbitration HEAVY | |
| `axisTick`: `show`, `alignWithLabel`, `interval`, `inside`, `length`, `lineStyle`, `customValues` | No | NATURAL | |
| `minorTick`: `show`, `splitNumber` (5), `length` (3), `lineStyle` | No | NATURAL | |
| `axisLabel`: `interval`, `inside`, `rotate` (−90..90), `margin`, `formatter`, `showMinLabel`/`showMaxLabel`, `alignMinLabel`/`alignMaxLabel`, `verticalAlignMin/MaxLabel`, `customValues`, colour callback, full text style | Partial | NATURAL | Fixed 8/400 labels, `'0.###'`, no rotation, no formatter, no ellipsis |
| `axisLabel.interval: 'auto'` — measure + 1.3× inflate + project by rotation + ±1 hysteresis cache | No | HEAVY | Without the cache labels flicker while zooming |
| `axisLabel.hideOverlap` (v5.2) — greedy priority-sorted OBB intersection | No | HEAVY | |
| `axisLabel.rich` multi-style/multi-line labels | No | HEAVY | |
| `splitLine` + `showMinLine`/`showMaxLine` + `interval` + **colour array cycling** | Partial | NATURAL | `ShowGrid: Boolean`, alpha hard-coded to 70 |
| `minorSplitLine` (v4.6) | No | NATURAL | |
| `splitArea` alternating band fill via colour array | No | NATURAL | |
| Axis `name` / `nameLocation` / `nameGap` / `nameRotate` / `nameTextStyle` / `nameTruncate` | No | NATURAL | No axis titles at all today |
| `nameMoveOverlap` (v6.0) | No | HEAVY | |
| `silent`, `triggerEvent` on axisLabel/axisName, `axis.tooltip` (v5.6) | No | NATURAL (payloads BROWSER-BOUND-shaped) | |
| Axis breaks (v6): `breaks[{start,end,gap,isExpanded}]`, cached randomised zigzag `breakArea`, tick pruning, injected boundary ticks, `expandOnClick`, 3 actions, `breakLabelLayout.moveOverlap` | No | HEAVY | A genuinely new coordinate transform layer |
| Jitter / `jitterOverlap` / `jitterMargin` (v6.0, axis-level) | No | NATURAL / HEAVY | Beeswarm packing when `jitterOverlap:false` |
| Band width from ordinal step (category) or per-axis adjacent-gap **statistics** (numeric, v6) | Partial | HEAVY | `TyChartBarXRange` is an even split with a 15 % inset |
| Renderer-facing axis API (`getTicksCoords`, `getMinorTicksCoords`, `getViewLabels`, `getBandWidth`, `dataToCoord`, `coordToData`, `containData`) | No | NATURAL | |
| `AxisBuilder` two-phase build (estimate → shrink rect → determine) | No | HEAVY | Required for `outerBounds`/`containLabel` |
| `subPixelOptimize` odd-lineWidth pixel-centre snapping | No | NATURAL | One line; **important** for crisp 1 px axis/grid lines at desktop DPI |
| polar: `center`, `radius` (n \| `'x%'` \| `[inner,outer]`), `angleAxis.startAngle`/`endAngle`/`clockwise` | Partial | NATURAL | Donut hole percentage only |
| polar: splitLine + splitArea on both axes (rings and sectors) | No | NATURAL | |
| singleAxis: box, `orient`, `position`, full axis surface | No | NATURAL | |
| calendar: `range` (year / `'2017-02'` / explicit span), `cellSize` incl. `'auto'`, `orient`, `splitLine`, `itemStyle` | No | NATURAL | |
| calendar: `dayLabel` (`firstDay`, `nameMap` EN/ZH/locale/7-array), `monthLabel` (+formatter tokens), `yearLabel` | No | NATURAL | |
| matrix: `x`/`y` header regions with flat or **tree** data, `length` (v6.1), auto-collect from series | No | HEAVY | |
| matrix: `levels[i].levelSize` / `data[i].size` in px or `%` | No | NATURAL | |
| matrix: `body`/`corner` data with `coord`, `value`, `mergeCells`, `coordClamp` | No | HEAVY | |
| matrix: locator algebra (negative locators = headers/corner, ordinal↔string↔locator mixing, ranges, non-leaf spans, `[2,null]` whole column) | No | HEAVY | Small but intricate |
| matrix: `dividerLineStyle`, `backgroundStyle`, `borderZ2`, per-cell label/itemStyle/silent/z2 | No | NATURAL | |
| axisPointer: `type` line \| shadow \| none (+ `'cross'` under `tooltip.axisPointer`) | No | NATURAL | |
| axisPointer: `snap`, `value`, `status`, `z`, `triggerTooltip`, `triggerEmphasis` | No | NATURAL | |
| axisPointer: `label` (show/precision/formatter/margin/padding/`backgroundColor:'auto'`/border/shadow/text style) | No | NATURAL | |
| axisPointer: `lineStyle` / `shadowStyle` (band width from `calcBandWidth`) / `crossStyle` (dashed) | No | NATURAL | |
| axisPointer: `link[]` groups + `mapper` callback across axis types | No | HEAVY | How a price grid and a volume grid share a crosshair |
| axisPointer: `triggerOn` (global only) | No | NATURAL | |
| axisPointer: `handle` (draggable touch puck, size 45, margin 50, throttle 40) | No | BROWSER-BOUND-ish | Touch-only; near-useless on desktop |
| axisPointer: animation (`animationDurationUpdate` 200, `exponentialOut`) — the pointer slides between snapped values | No | NATURAL | |
| `roam` (`View` transform stack) on geo/graph/tree/sankey/treemap/sunburst, `scaleLimit`, `roamTrigger`, `nodeScaleRatio` | No | HEAVY | Build once, five series get it |

### 2.3 Components (non-coordinate UI)

| ECharts capability | TTyChart today | Class | Notes |
|---|---|---|---|
| Box layout (`left/top/right/bottom/width/height`; px, `'%'`, `'left'/'center'/'right'`, `'top'/'middle'/'bottom'`) shared by 8 components | No | NATURAL | One `TRect` solver reused everywhere |
| `coordinateSystem` on non-series components (`'none'`/`'matrix'`/`'calendar'`, v6) | No | NATURAL | |
| Component chrome (`backgroundColor`, `borderColor/Width/Radius`, shadow, `padding`) | Partial (tooltip only) | NATURAL | `TyChartTooltip` has the full set |
| **title**: `text` + `subtext`, `\n` breaks, `itemGap`, `padding`, **multiple instances** | Partial | NATURAL | One `Title: TCaption`, one line, fixed 11/700 font |
| title: `textAlign`/`textVerticalAlign` decoupling block alignment from box anchor | No | NATURAL | |
| title: `link`/`sublink`/`target` | No | BROWSER-BOUND | → `OnTitleClick` / `OpenURL` |
| title: `triggerEvent` | No | NATURAL | |
| **legend**: `type: 'plain'` | Partial | NATURAL | One horizontal strip, `Break`s on overflow |
| legend: `type: 'scroll'` paging (`scrollDataIndex`, page buttons/icons/colors/size, `pageFormatter`, animated slide, snap-to-item-boundary window) | No | HEAVY | |
| legend: `orient`, `align`, `itemGap/Width/Height`, `padding`, box layout with wrap | No | NATURAL | Bottom-only, no wrap, no placement |
| legend: `data` items with per-item icon/itemStyle/lineStyle/textStyle/symbolRotate/inactive* | No | NATURAL | |
| legend: `''`/`'\n'` data entries force a line break | No | NATURAL | |
| legend: many-to-many name matching; auto-collect from `series.name` or `encode.seriesName` | Partial | NATURAL | |
| legend: per-datum legend for pie, funnel, chord, graph, radar, themeRiver | Partial | NATURAL | Radial charts list categories today — the right idea, hard-wired |
| legend: `icon` built-in \| `'inherit'` \| `path://` \| `image://`; series-supplied `getLegendIcon` (line draws line+symbol) | No | HEAVY | |
| legend: `itemStyle`/`lineStyle` with per-property `'inherit'` sentinel and `borderWidth: 'auto'` | No | HEAVY | |
| legend: `inactiveColor`/`inactiveBorderColor`/`inactiveBorderWidth`, `lineStyle.inactiveColor/inactiveWidth` | No | NATURAL | |
| legend: `selectedMode` (true/false/single/multiple), `selected` map, **click-to-toggle a series** | No | NATURAL | The most-missed legend feature |
| legend: `formatter`, `legend.tooltip` | No | NATURAL | |
| legend: `selector` (all/inverse buttons) + `selectorLabel`/`selectorPosition`/`selectorItemGap`/`selectorButtonGap` | No | NATURAL | |
| legend: `triggerEvent` payload (v6) | No | NATURAL | |
| **tooltip**: configurable at 5 levels (global / grid-polar-single / series / datum) | No | NATURAL | One control-level `ShowTooltip: Boolean` |
| tooltip: `trigger: 'item'` | Yes | NATURAL | |
| tooltip: `trigger: 'axis'` (every series' point at the hovered axis value) | No | HEAVY | Needs `findPointFromSeries` nearest-point search |
| tooltip: `trigger: 'none'` | No | NATURAL | |
| tooltip: `triggerOn` mousemove \| click \| both \| none | No | NATURAL | |
| tooltip: `showDelay`/`hideDelay`/`alwaysShowContent`/`showContent`/`enterable` | No | NATURAL (enterable BROWSER-BOUND) | |
| tooltip: `order` seriesAsc/seriesDesc/valueAsc/valueDesc | No | NATURAL | |
| tooltip: `formatter` template (`{a}{b}{c}{d}{e}`, indexed `{a0}`) | Partial | NATURAL | `OnGetTooltip` gives a var-string hook, no templates |
| tooltip: `formatter` callback with async `(params, ticket, callback)` | Partial | BROWSER-BOUND | `OnGetTooltip` is the sync half |
| tooltip: `valueFormatter` | No | NATURAL | Number format is hard-coded `'0.###'`, deliberately locale-independent |
| tooltip: `position` (`[x,y]`, `['%','%']`, inside/top/bottom/left/right, callback) | Partial | HEAVY | `TyChartTooltipRect` prefers up-right, flips then clamps |
| tooltip: `confine` (clamp to chart rect) | Yes (always) | HEAVY | The in-bitmap design confines unconditionally — **the tooltip can never leave the control** |
| tooltip: `renderMode: 'richText'` (single canvas text element + rich fragment styles) | Partial | NATURAL | Plain two-line text; no rich fragments |
| tooltip: `renderMode: 'html'` + `appendToBody`/`appendTo`/`className`/`extraCssText`/CSS transitions | No | BROWSER-BOUND | Out of scope by design |
| tooltip: the two-stage `tooltipMarkup` content model (`section`/`nameValue` blocks with gap levels, then one renderer) | No | HEAVY | **Port this design, not the strings** |
| tooltip: coloured series markers (`makeTooltipMarker` `'item'`/`'subItem'`) | Partial | NATURAL | `--chart-tooltip-swatch` exists |
| tooltip: `transitionDuration`, `displayTransition` | No | BROWSER-BOUND | |
| **toolbox**: icon strip (`orient`, `itemSize`, `itemGap`, `showTitle`, chrome, box layout, `tooltip`) | No | NATURAL | Blocked by the graphic-control base if built from real widgets |
| toolbox: per-feature `show`/`title`/`icon`/`iconStyle`/`emphasis.iconStyle` + hover-label options | No | NATURAL | |
| toolbox: `saveAsImage` (`type`, `name`, `backgroundColor`, `excludeComponents`, `pixelRatio`) | Partial | NATURAL | `SaveToFile`/`SaveToStream` exist as API, no button |
| toolbox: `saveAsImage.type: 'svg'` | No | BROWSER-BOUND | No SVG back-end |
| toolbox: `restore` | No | NATURAL | Snapshot the original option |
| toolbox: `dataView` (editable textarea overlay, `optionToContent`/`contentToOption`, `lang`) | No | BROWSER-BOUND | The *action* ports; the DOM widget must become a native dialog |
| toolbox: `dataZoom` (marquee + undo stack, `filterMode`, `xAxisIndex`/`yAxisIndex`, `brushStyle`) | No | HEAVY | |
| toolbox: `magicType` (line/bar/stack switching; rewrites series type + stack + `boundaryGap`) | No | HEAVY | Architectural, not visual |
| toolbox: `brush` buttons | No | HEAVY | |
| toolbox: custom `myXxx` buttons `{show,title,icon,onclick}` | No | NATURAL | `onclick` → an event with an identifier |
| **dataZoom**: 3 types (inside, slider, select) auto-linking when driving the same axis | No | HEAVY | Unit header: "Still NOT included: zoom" |
| dataZoom: `start`/`end` (percent) vs `startValue`/`endValue`; `rangeMode` auto-derived and auto-flipped | No | NATURAL | Pure numeric interval logic |
| dataZoom: `minSpan`/`maxSpan`, `minValueSpan`/`maxValueSpan` | No | NATURAL | |
| dataZoom: `orient`, `zoomLock`, `throttle`, `realtime` | No | NATURAL | |
| dataZoom: `filterMode: 'filter'` (drop if ANY dim outside; other axis re-fits) | No | HEAVY | |
| dataZoom: `filterMode: 'weakFilter'` (drop only if ALL dims outside on the SAME side) | No | HEAVY | For interval-shaped data (Gantt, candlestick) |
| dataZoom: `filterMode: 'empty'` (out-of-window → NaN, slot kept) | No | HEAVY | Needs NaN in the data model |
| dataZoom: `filterMode: 'none'` | No | NATURAL | |
| dataZoom: declaration order matters under `'filter'` | No | HEAVY | |
| dataZoom `inside`: `zoomOnMouseWheel`/`moveOnMouseMove`/`moveOnMouseWheel` each `true\|false\|'shift'\|'ctrl'\|'alt'`; `disabled` | No | NATURAL | `'shift'/'ctrl'/'alt'` → `TShiftState` |
| dataZoom `inside`: `preventDefaultMouseMove`; v6.1 `cursorGrab`/`cursorGrabbing` | No | BROWSER-BOUND | → `crHandPoint` / a custom cursor |
| dataZoom `inside`: pinch zoom | No | Touch-only | |
| dataZoom `slider`: track/frame chrome, `fillerColor`, two end handles + `handleIcon`/`handleSize`/`handleStyle`/`handleLabel`, move handle (`moveHandleIcon`/`Size`/`Style`) | No | NATURAL drawing / **blocked by base class if built as a real widget** | |
| dataZoom `slider`: `dataBackground` + `selectedDataBackground` silhouette (only line/bar/candlestick/scatter) + `showDataShadow` | No | HEAVY | Downsample the series into a silhouette, draw twice with clipping |
| dataZoom `slider`: `showDetail`, `labelPrecision`, `labelFormatter`, `textStyle` | No | NATURAL | |
| dataZoom `slider`: `brushSelect` + `brushStyle` (drag empty track to define a window) | No | NATURAL | |
| dataZoom `select`: `BrushController` marquee + undo stack + `takeGlobalCursor` mutex | No | HEAVY | |
| **visualMap**: 8 visual channels (color, symbol, symbolSize, opacity, colorAlpha, colorLightness, colorSaturation, colorHue) | No | NATURAL | Arithmetic + an HSL helper |
| visualMap: Linear vs Table mapping modes; inverted ranges; scalar → `[v,v]` | No | NATURAL | |
| visualMap: `dimension`, `seriesIndex`, `seriesId` (v6.0), `seriesTargets` (v6.1) | No | NATURAL | |
| visualMap: per-datum `{visualMap: false}` opt-out | No | NATURAL | |
| visualMap: `inRange` / `outOfRange` / `target.*` / `controller.*` (never merged across setOption) | No | NATURAL | |
| visualMap continuous: `min`/`max` (default `[0,200]`, not data-derived), `range`, `calculable`, `realtime`, `inverse`, `precision`, `itemWidth/Height`, `align`, `text`, `textGap`, `formatter` | No | NATURAL | |
| visualMap continuous: `handleIcon`/`handleSize`/`handleStyle`, `indicatorIcon`/`indicatorSize`/`indicatorStyle` | No | NATURAL | |
| visualMap continuous: `unboundedRange` (v6.0, default true) | No | NATURAL | |
| visualMap continuous: the bar is a **polygon whose thickness tracks the `symbolSize` channel**, gradient non-linear under `colorHue` | No | HEAVY | |
| visualMap: `hoverLink` (bidirectional, tolerance band, `'< '`/`'> '`/`'≈ '` indicator labels) | No | HEAVY | Needs a value→dataIndex reverse index |
| visualMap piecewise: 3 modes (splitNumber average / custom `pieces` with ±Inf and `{value:n}` / `categories`) | No | NATURAL | |
| visualMap piecewise: `minOpen`/`maxOpen`, `selectedMode`, `inverse`, `precision`, `itemWidth/Height/Gap`, `align`, `text`, `showLabel`, `itemSymbol`, `formatter` | No | NATURAL | |
| **brush**: 4 shapes (rect, polygon, lineX, lineY) + `keep`/`clear` toolbox buttons | No | HEAVY | |
| brush: `brushMode` single vs multiple; `transformable`; `removeOnClick`; `brushStyle` | No | NATURAL | |
| brush: scoping — global vs coordinate-bound (`geoIndex`/`xAxisIndex`/`yAxisIndex`), boxes track pan/zoom | No | HEAVY | |
| brush: `seriesIndex` (scatter, bar, candlestick) | No | NATURAL | |
| brush: `brushLink` (selection propagates **by dataIndex** across index-aligned series) | No | HEAVY | |
| brush: `inBrush`/`outOfBrush` using the 8 visualMap channels (`outOfBrush` default `#ddd`) | No | NATURAL | |
| brush: `throttleType` fixRate/debounce + `throttleDelay` | No | NATURAL | |
| brush: cover internals — rect with 8 resize handles + cursors, lineX/lineY with 2, polygon drawn open then closed, `UNSELECT_THRESHOLD` 6 px, `MIN_RESIZE_LINE_WIDTH` 6, panel clipping, `globalPan` mutex | No | HEAVY | The `designer-hittest-gesture-consistency` lesson applies verbatim: arm on down, **release on up** |
| brush: hit testing (point-in-polygon, rect∩polygon per brushType) | No | HEAVY | Needs spatial indexing above a few thousand items |
| **timeline**: `baseOption` + `options[]` per tick, index-aligned with `timeline.data` | No | HEAVY | |
| timeline: `replaceMerge` (mainType or array) vs `NORMAL_MERGE` | No | HEAVY | |
| timeline: `axisType` time/value/category; `data` values or `{value,symbol,symbolSize,tooltip}` | No | NATURAL | |
| timeline: `currentIndex`, `autoPlay`, `loop`, `rewind`, `playInterval`, `realtime` | No | NATURAL | A slider + `TTimer` |
| timeline: `orient`, `inverse`, `controlPosition`, box layout | No | NATURAL | Vertical = a transform of horizontal |
| timeline: `symbol`/`symbolSize`, `lineStyle`, `itemStyle`, `emphasis.*` | No | NATURAL | |
| timeline: `label` (show/position/interval/rotate/formatter/textStyle) | No | NATURAL | |
| timeline: `checkpointStyle` with `animation`/`animationDuration`/`animationEasing` (slides between ticks) | No | NATURAL | |
| timeline: `progress` (played portion styled separately) | No | NATURAL | |
| timeline: `controlStyle` (play/stop/prev/next icons, `itemSize`, `itemGap`, `position`) | No | NATURAL | |
| **markPoint**: `symbol` (pin), `symbolSize` (50, callback), `symbolRotate/Offset/KeepAspect`, `silent`, `label`, `itemStyle`, `emphasis`, `blur`, `z`/`z2` | No | NATURAL | |
| **markLine**: single object or `[start, end]` pair mixing position forms; per-end `symbol`/`symbolSize`/`symbolOffset`; `precision`; `lineStyle` | No | NATURAL | |
| markLine: `label.position` — 9 values (start/middle/end × inside×Top/Bottom); `label.distance` (number or `[h,v]`) | No | NATURAL | |
| **markArea**: two opposite corners, each independently pixel/coord/type/axis-scalar | No | NATURAL | |
| All three: position priority — pixel/percent (+ v6 `relativeTo`), `coord` (each dim may be a statistic string), `type` statistic + `valueIndex`/`valueDim`, bare `xAxis`/`yAxis` scalar | No | NATURAL | |
| All three: statistics min/max/average/median + nearest-datum snapping + per-datum precision rounding | No | NATURAL + light stats | |
| Category-axis rule: numeric coord = index, string coord = label | No | NATURAL | |
| **graphic**: 13 constructible element types | No | NATURAL | BGRA paths cover all of them |
| graphic: shapes (rect with 1–4 corner radii, circle, ring, sector with `cornerRadius`, arc, polygon/polyline with `smooth`, line with `percent`, bezierCurve with `percent`, image, text, group) | No | NATURAL | |
| graphic: `left/right/top/bottom` overriding `shape.x/y/cx/cy`; `bounding: 'all' \| 'raw'` | No | HEAVY | Position depends on the *transformed* bbox incl. descendants |
| graphic: transform (x/y, scaleX/Y, rotation in radians, originX/Y), nesting through groups | No | NATURAL | |
| graphic: full style (fill, stroke, lineWidth, lineDash + offset, cap, join, miterLimit, shadow*, opacity) | No | NATURAL | |
| graphic: `$action` merge/replace/remove; id-keyed or positional matching | No | NATURAL | |
| graphic: `clipPath`, `textContent` + `textConfig` | No | NATURAL / HEAVY (arbitrary clip) | |
| graphic: `silent`, `invisible`, `ignore`, `draggable` (true/horizontal/vertical), `progressive`, `z`/`zlevel`/`z2`, `name`, `info` | No | NATURAL | |
| graphic: `transition`/`enterFrom`/`leaveTo`/`enter-update-leaveAnimation`/`keyframeAnimation` | No | HEAVY | |
| graphic: 14 event handlers (`onclick`, `onmouse*`, `ondrag*`, `ondrop`) | No | BROWSER-BOUND | HTML5 drag semantics differ from LCL's |
| **aria**: `enabled`, `label.description`, template set (general/series/data with maxCount and separators), `excludeDimensionId` | No | NATURAL text gen / BROWSER-BOUND delivery | Feed MSAA/UIA or expose as a property |
| **decal**: `symbol` (name / array / nested array), `symbolSize`, `symbolKeepAspect`, `color`, `backgroundColor`, `dashArrayX` (number \| array \| per-row array), `dashArrayY`, `rotation`, `maxTileWidth/Height`, 6 built-in decals | No | HEAVY | Commensurate X/Y dash cycles → offscreen tile → rotated repeating fill |
| **thumbnail** (v6.0, graph only): mini-map + viewport window, `itemStyle`/`windowStyle`, own `RoamController` mapping pan/zoom back through the inverse matrix | No | HEAVY | |
| **loading indicator** (`showLoading`/`hideLoading` + 12 options) | No | NATURAL | Mask rect + arc + text, ~40 lines |

### 2.4 Data pipeline

| ECharts capability | TTyChart today | Class | Notes |
|---|---|---|---|
| 4-layer model (`Source` → `DataProvider` → `DataStore` → `SeriesData`) | No | NATURAL (as a design) | |
| Columnar store: one array per dimension, parsed once at fill time | No | NATURAL | `Values: string` is **re-parsed on every `ValueArray` call** — `DataExtent`, `AxesData`, paint, hit-test and tooltip each call it |
| 5 dimension types (`float`/`int`/`number`/`ordinal`/`time`) with typed backing | No | NATURAL | FPC does this better than JS |
| `parseDataValue` rules (`null`/`''`/`'-'`/object → NaN; numeric strings coerced; `time` via `parseDate`) | No | NATURAL | Today unparseable text silently becomes **0.0**, indistinguishable from a real zero |
| Index indirection (`_indices` permutation, `count` vs `_rawCount`, swapped `getRawIndex`) | No | NATURAL | |
| `indexOfRawIndex` binary search | No | NATURAL | |
| `_rawExtent` maintained during fill + `_extent` cached per (dim, sanitization filter) for log-axis positive-only extents | No | NATURAL | |
| `clone(clonedDims)` copying only named columns | No | NATURAL | |
| Bulk ops: `filter`, `selectRange` (hand-inlined 1-dim/2-dim fast paths), `map`, `modify`, `each`, `getValues` | No | NATURAL | |
| `OrdinalMeta` category interning (lazy hash, `needCollect`, `deduplication`, `ordinalOffset`) | No | NATURAL | |
| Inverted index (ordinal → dataIndex, `-1` sentinel) for stack-by-value | No | NATURAL | |
| `guessOrdinal` 3-verdict sniffing (Must/Might/Not) over 5 sampled rows | No | NATURAL | |
| Per-datum overrides via prototype-chained `Model` | No | BROWSER-BOUND | Natively: an explicit override record with Has-flags |
| `hasItemOption` / provider `pure` flag gating the object-scan path | No | NATURAL | |
| Scalar-on-category-axis completion (`[555,666]` → `[[0,555],[1,666]]`) | Yes (implicitly) | NATURAL | This is the *only* data shape TTyChart supports |
| Per-series tuple semantics (candlestick OCLH, boxplot 5-number, heatmap +value, radar N indicators, themeRiver triples, lines coord buffers, graph node+edge tables, tree/treemap/sunburst trees) | No | NATURAL/HEAVY per family | |
| 6 `sourceFormat`s (`arrayRows`, `objectRows`, `keyedColumns`, `typedArray`, `original`, `unknown`) + `detectSourceFormat` | No | NATURAL | |
| `sourceHeader` (`number` \| `true` \| `false` \| `'auto'`) with the ≤10-cell scan heuristic | No | NATURAL | ~20 lines |
| Dimension detection per format + duplicate-name suffixing | No | NATURAL | |
| `dataset.dimensions` / `series.dimensions` (`{name,type,displayName}`, `null` allowed; series wins) | No | NATURAL | |
| `seriesLayoutBy: 'column' \| 'row'` (forbidden for `appendData` and transforms) | No | NATURAL | |
| Multiple datasets, `datasetIndex`/`datasetId`, `SourceManager` DAG with recursive version-sign dirty checks | No | HEAVY | |
| Store sharing across series via schema hash | No | NATURAL | N series over one table should parse once |
| Default encode: "category way" (dim 0 shared) vs "value way" (n dims per series), per-dataset cursor | No | NATURAL | ~120 lines |
| `makeSeriesEncodeForNameBased` (pie/funnel 5-dim probe) | No | NATURAL | |
| `encode` coordinate roles (`x`,`y`,`radius`,`angle`,`lng`,`lat`,`single`,`value`, + coordSys-declared); `-1` = explicit opt-out | No | NATURAL | |
| `encode` visual roles (`tooltip`, `label`, `itemName`, `itemId`, `itemGroupId`, `itemChildGroupId`, `seriesName`) | No | NATURAL | |
| `summarizeDimensions` → `defaultedLabel`/`defaultedTooltip`/`dataDimsOnCoord`/`hasValue()`/`userOutput` | No | NATURAL | |
| `prepareSeriesDataSchema` 3-way reconciliation (coordSys dims × user encode/dimensions × data shape) | No | HEAVY | 411 lines; the most intricate file in the subsystem, load-bearing for every series |
| High-dimension omission (`dimCount > 30`) | No | HEAVY | Only for wide shared datasets |
| Transform mechanism (registry, namespaced types, `ExternalSource` sandbox, `getRawData` restricted to built-ins) | No | HEAVY | |
| `[DIMENSION_INHERIT_RULE]` (no returned `dimensions` ⇒ upstream header re-prepended) | No | HEAVY | |
| Piped transforms, `fromDatasetIndex`/`fromDatasetId`/`fromTransformResult` | No | HEAVY | |
| Built-in `filter` condition DSL (`and`/`or`/`not`, `lt/lte/gt/gte/eq/ne` + aliases, `reg`) | No | HEAVY | |
| Filter semantics: multiple ops ANDed, `[EMPTY_RULE]` (null ⇒ false, no-op ⇒ throw), fail-fast | No | HEAVY | |
| Filter/sort `parser` (`'time'`, `'trim'`, `'number'` loose parseFloat) vs strict `numericToNumber` | No | HEAVY | |
| `reg` operator (RegExp or pattern string) | No | BROWSER-BOUND-ish | Needs the FPC `RegExpr` dependency, or ship `filter` without `reg` |
| Built-in `sort` (multi-key, `order`, `incomparable: 'min'\|'max'`, 3-class comparison so `'2' < '12'`) | No | HEAVY | Easy to under-specify |
| Built-in `boxplot` transform (2 outputs, `boundIQR`, `itemNameFormatter`) | No | NATURAL | |
| External `ecStat:regression` (linear/exponential/logarithmic/polynomial + `order`, `formulaOn`) | No | HEAVY | Reimplement least-squares; not ECharts core |
| External `ecStat:clustering` (k-means, `clusterCount`, output dims) | No | HEAVY | Lloyd's algorithm |
| External `ecStat:histogram` (squareRoot/scott/freedmanDiaconis/sturges binning) | No | HEAVY | |
| Processor priorities (SERIES_FILTER 800, DATASTACK 900, AXIS_STATISTICS 920, FILTER 1000, DEFAULT 2000, STATISTIC 5000) | No | NATURAL | A sorted list of handler records |
| Legend `dataFilter` (pie/funnel/radar/themeRiver/chord) and `negativeDataFilter` (pie) | No | NATURAL | |
| `setApproximateExtent` (skip full extent recompute after zoom filtering) | No | NATURAL | |
| Stacking calc dimensions (`__ecstackresult`, `__ecstackedover`) with `addSafe` float-error-safe accumulation | No | NATURAL | |
| Samplers `average`/`sum`/`max`/`min`/`nearest` + custom callback; representative index `i + round(frame/2)` | No | NATURAL | |
| `minmax` sampling (2 points/bucket, envelope-exact, original order) | No | NATURAL | |
| **LTTB** with ECharts' two deviations (index-space x; NaN-gap preservation via first-NaN emission) | No | HEAVY | Report 06 §8 has the exact pseudocode |
| `large`/`largeThreshold` "one composite path, no per-item styling, arithmetic hit-test" contract | No | HEAVY | More natural on BGRA than in the DOM |
| `progressive`/`progressiveThreshold`/`progressiveChunkMode` frame-sliced scheduler | No | HEAVY | Optional natively; FPC is an order of magnitude faster than JS here |
| `setOption` merge modes (normalMerge id→name→index, `notMerge`, `replaceMerge` with index holes, `lazyUpdate`, `silent`) | No | HEAVY | Only relevant if an option-tree API is adopted (see §6) |
| `appendData` streaming (pre-filter only, grows typed columns, axis extents NOT recomputed) | No | NATURAL | `SetLength` + copy |
| Id derivation chain (`dataItem.id` → `encode.itemId` → `ID_PREFIX+rawIndex`); name from `dataItem.name` → `encode.itemName`; `makeIdFromName` repeat counter | No | NATURAL | |
| `DataDiffer` `'oneToOne'` (add/update/remove, FIFO duplicate-key consumption) | No | HEAVY | Prerequisite for any diff-based animation |
| `DataDiffer` `'multiple'` (updateManyToOne/OneToMany/ManyToMany) | No | HEAVY | Basis of split/merge morphs |
| `universalTransition` groupId resolution + set-intersection drill direction | No | HEAVY | |
| Internal statistics (`getSum`, `getMedian`, `getDataExtent` with sanitization filter) | Partial | NATURAL | `DataExtent` exists; **`Break`s after series 0 for pie/donut** |
| Pie `getPercentSeats` largest-remainder rounding | No | NATURAL | |
| `Graph` (node + edge dual SeriesData) and `Tree` (`children`/`viewChildren`) + `linkSeriesData` method proxying | No | HEAVY | |

### 2.5 Style and label

| ECharts capability | TTyChart today | Class | Notes |
|---|---|---|---|
| `itemStyle` 13-key map → fill/stroke/lineWidth/opacity/shadow*/lineDash/dashOffset/cap/join/miterLimit | Partial (fill only) | NATURAL | |
| `lineStyle` 12-key map | Partial | NATURAL | Width hard-coded 2, `lineJoin: 'round'` |
| `areaStyle` 6-key map (no stroke, no dash) | No | NATURAL | |
| `backgroundStyle` (itemStyle-shaped track fill) | No | NATURAL | |
| `borderType`/`type` enum + number + number[] SVG dasharray; `dashOffset` | No | NATURAL / HEAVY on curves | BGRA `lineStyle(array of single)` gives the pattern; phase on curved paths needs work |
| `cap` (butt/round/square), `join` (**bevel** default, round, miter), `miterLimit` (10) | Partial | NATURAL | Note ECharts defaults join to bevel, not miter |
| `opacity` (0 = not drawn) | No | NATURAL | `TTyPainter.Opacity` is **whole-bitmap**; per-element alpha needs `globalAlpha` or per-pixel alpha |
| `shadowBlur`/`shadowColor`/`shadowOffsetX/Y` on any element, **twice over** (box + `textShadow*` glyphs) | Partial (tooltip box) | HEAVY | Offscreen mask + gaussian blur per element is expensive; consider limiting to component boxes |
| `borderRadius` — rect 4-array clockwise from TL; sector 4-corner inner→outer with percentages; text-fragment box | Partial | NATURAL / HEAVY (sector) | |
| `z` / `zlevel` / `z2`; `Z2_EMPHASIS_LIFT` 10, `Z2_SELECT_LIFT` 9 | No | NATURAL | |
| `blendMode` → `globalCompositeOperation` | No | BROWSER-BOUND | `'lighter'` is achievable; the rest is not worth it |
| `silent`, `triggerEvent`, `cursor` | Partial | BROWSER-BOUND naming | |
| Colour parser: `#rgb`/`#rgba`/`#rrggbb`/`#rrggbbaa`/`rgb()`/`rgba()`/`hsl()`/`hsla()`/148 named, LRU-cached | Partial | NATURAL | ty-controls has `TTyColor` + the tycss parser; ECharts' string set is a superset |
| Linear gradient `{type:'linear',x,y,x2,y2,colorStops,global}` (bbox fractions vs absolute) | No | NATURAL | `TTyFill` is linear-only; Canvas2D `createLinearGradient` is richer |
| Radial gradient `{type:'radial',x,y,r,colorStops,global}` | No | NATURAL | `createRadialGradient` (two-circle form) exists in BGRA |
| Pattern `{image, repeat}` | No | BROWSER-BOUND load / NATURAL brush | Accept a loaded `TBGRABitmap`; **do not** round-trip through `TPicture` (`MakeBitmapCopy` black-image trap) |
| Callback colour `(params) => Color` | No | NATURAL as an event | Disables palette assignment for that series |
| `option.color` palette (v6 default = 9 tokens) | Yes | NATURAL | `TyChartSeries1..8` (Tableau-10 hues) + a const fallback |
| `series.color` per-series palette override | No | NATURAL | |
| `colorLayer: Color[][]` (pick the first sub-palette longer than the requested count) | No | NATURAL | |
| `colorBy: 'series' \| 'data'` with palette cursors scoped per `seriesType+colorBy` | Partial (hard-wired) | NATURAL | |
| Palette assignment memoised **by name** so legend toggling doesn't reshuffle | No | NATURAL | |
| `gradientColor` default ramp | No | NATURAL | |
| v6 design tokens (9 theme colours, 21 neutrals, 19 accents, ~20 semantic aliases, size scale) | Partial | NATURAL | ty-controls' `.tycss` token system is *richer*; the ECharts token table is the highest-value straight data port |
| `darkMode: boolean \| 'auto'` (`lum(bg,1) < 0.4`) | Partial | NATURAL | The library follows OS dark mode already |
| Automatic label contrast (inside fill `lum > 0.5 → #333`, `> 0.2 → #eee`, else `#ccc`; halo stroke rule; outside `#ccc`/`#333`) | No | NATURAL | Copy exactly |
| `'inherit'` sentinel on `color`/`backgroundColor`/`borderColor`/`textBorderColor` | No | NATURAL | |
| `lift`, `modifyHSL`, `modifyAlpha`, `lum` helpers | Partial | NATURAL | ~40 lines each |
| **decal** (see §2.3) | No | HEAVY | |
| Label: `show`, `position`, `distance` (5), `rotate` (−90..90), `offset`, `formatter` | Partial | NATURAL | `ShowValues: Boolean` only |
| Label font group (inherits global textStyle + plain label since v6): fontStyle/fontWeight/fontFamily/fontSize/textShadow* | No | NATURAL | Fixed 8/400 with the control's `Font.Name`, not the style's `font-name` |
| Label self group (never inherited): align/verticalAlign/lineHeight/width/height/ellipsis | No | NATURAL | |
| Label box group: padding, borderWidth/Radius/Type/DashOffset, backgroundColor (colour **or** `{image}`), borderColor, shadow* | No | NATURAL | |
| Glyph stroke: `textBorderColor/Width/Type/DashOffset` | No | NATURAL | BGRA can render text to a mask and stroke it |
| v6 `textMargin` (unrotated local rect, then rotate) vs `minMargin` (rotated AABB, gap = a/2+b/2) | No | NATURAL | |
| v6 `richInheritPlainLabel` | No | NATURAL | |
| 13 rectangular `position` values + `[x,y]` px/% + `'outside'` alias | No | NATURAL | A pure switch producing (x, y, align, verticalAlign) |
| Pin + inside special case (`y = rect.y + 0.4h`) | No | NATURAL | |
| 9 sector positions (startAngle/insideStartAngle/endAngle/insideEndAngle/middle/startArc/insideStartArc/endArc/insideEndArc) | No | NATURAL | Trig |
| Family-specific position sets: pie 3–4, polar bar 5, funnel 12, graph edge 3, sankey/themeRiver/map/line defaults | No | NATURAL | |
| `rotate: 'radial' \| 'tangential'` on sector labels | No | NATURAL | `TextOutAngle` exists; `TextOutCurved` gives curved arc labels |
| Template formatter `{a}{b}{c}{d}{e}{f}{g}`, per-series `{a0}`, `{@dimName}`, `{@[n]}`, `\n` | No | NATURAL | `formatTpl` is ~40 lines |
| Callback formatter with the full `CallbackDataParams` record | Partial | NATURAL as an event | `OnGetTooltip` is the only hook, tooltip-only |
| `overflow` none/truncate/break/breakAll + `ellipsis` + `width`/`height`; v6 `autoOverflowArea` | No | NATURAL surface / HEAVY impl | |
| Truncation: iterative estimate ≤2 passes, `minChar`, ellipsis dropped if it alone overflows, `isTruncated` | Partial | HEAVY | `TyEllipsisPrefix` + `DrawText(..., ellipsis)` exist but are not applied to chart labels |
| Word wrap: word = alphabetic run not in `breakCharMap`; **every non-alphabetic char incl. all CJK is a break opportunity**; `breakAll` = every char | Partial | HEAVY | `TyWrapTextCJK` already encodes the correct CJK rule — ECharts' `wrapText` is the reference |
| `lineOverflow: 'truncate'` (drop whole lines past `height`) | No | HEAVY | |
| Rich text `{name\|content}` with per-fragment full style incl. `backgroundColor:{image}` and `width:'NN%'` | No | HEAVY | A small inline layout engine; icons, `<hr>`, title bars and tables all fall out of it |
| Rich layout rules (inline-block fragments, line height = max fragment lineHeight, verticalAlign, left-run/right-run/centre-remainder, 2-pass % widths) | No | HEAVY | |
| Text measurement: per-font LRU record with `width('国')` **as the line height**, `width('a')`, lazy 128-entry ASCII table (abandoned >16 ms / after 5 slow tries), LRU(500) string cache | Partial | HEAVY | `TTyPainter.MeasureText` is cached; the per-font ASCII table and the CJK line-height convention are not |
| Font string assembly + platform default family | Partial | BROWSER-BOUND | Heed `empty-fontname-gotcha`: never pass an empty family to BGRA |
| `label.valueAnimation` + `precision: number \| 'auto'` | No | HEAVY | Numeric interpolation re-running the formatter each frame |
| `series.line.endLabel` (independent label on the last visible point, own states) | No | NATURAL | |
| `labelLine`: show/showAbove/length/length2/smooth/minTurnAngle/maxSurfaceAngle/lineStyle | No | NATURAL surface | |
| Auto guide routing (4 candidate anchors × `nearestPointOnPath` walking the path proxy: lines, arcs, sampled beziers) + `limitTurnAngle` + `limitSurfaceAngle` | No | HEAVY | |
| Guide-line draw-on via `strokePercent` 0→1 + point-set tween on update | No | HEAVY | Needs arc-length parameterisation |
| `labelLayout` object form (12 keys) | No | NATURAL | |
| `labelLayout` callback form | No | NATURAL as an event | `params.rect` lets you size the font from the shape |
| `hideOverlap` (priority sort, greedy accept, AABB fast-reject then **OBB SAT**, touchThreshold 0.05, cached OBB, hidden labels reappear in emphasis) | No | HEAVY | Needed the moment labels can rotate |
| `shiftLayoutOnXY` (sort → forward sweep → mean re-centre → `squeezeGaps` ≤80 % → `takeBoundsGap` → `squeezeWhenBailout`) | No | HEAVY | ~150 lines, well specified |
| Pie-specific label layout (per-semicircle shift + ellipse-implicit X re-solve + `constrainTextWidth` + 3 `alignTo` modes) | No | HEAVY | |
| Axis-label de-collision (`hideOverlap`, `showMinLabel`/`showMaxLabel` auto, `interval`, `nameMoveOverlap`, `nameTruncate`) | No | NATURAL / HEAVY | |
| `LabelManager` pipeline (collect → restore defaults → apply layout → shift groups → restoreIgnore + hideOverlap → guide lines → animate) | No | NATURAL as a design | Idempotency via saved `defaultAttr` is the key trick |
| Symbols: 8 documented + `line`/`square` undocumented, with exact geometry (roundRect r = min/4; pin = circle r=(3w/5)/2 tangent-joined by 2 cubics; arrow 4-point chevron dx=2w/3, notch at 3h/4) | No | NATURAL | |
| `empty*` prefix (stroke = series colour, fill = neutral00, lineWidth 2) — `emptyCircle` is line's default | No | NATURAL | |
| `'image://<url\|dataURI>'` symbols | No | BROWSER-BOUND load / NATURAL draw | |
| `'path://<SVG PathData>'` symbols with auto-fit | No | NATURAL `[corrected]` | **Verified**: `bgrapath.pas:2301` accepts `L H V C S Q T A` + `M`/`Z` + relative forms, and `'A'` (2400-2410) dispatches to full elliptical `arcTo(rx,ry,xAngle,largeArc,anticlockwise,x,y)`. The whole grammar is covered — no parser to write, no dependency. Only the viewBox auto-fit is ours |
| `symbolSize` scalar/[w,h]/callback; `symbolRotate` (negative = clockwise); `symbolOffset` px or `'%'`; `symbolKeepAspect` | No | NATURAL | |
| Directional variants (`fromSymbol`/`toSymbol` + Size/Rotate/Offset/KeepAspect) for lines/markLine | No | NATURAL | |
| Theme = a plain option-shaped object; `registerTheme`; `init(dom, nameOrObject)`; 36 shipped themes | Partial | NATURAL | ty-controls' `.tycss` system is a **richer superset** |
| `mergeTheme` rules (theme.color skipped if user set color; per-component-main-type keys deferred to component merge, enabling `theme.line`/`theme.bar`/`theme.categoryAxis`/`theme.valueAxis`) | No | NATURAL | The per-series-type and per-axis-type defaulting is the part TTyChart lacks |
| `media: [{query, option}]` — 6 keys, AND semantics, later match wins, recompute only on index-set change | No | NATURAL | ~60 lines; genuinely useful for a resizable desktop control |
| `option.options[]` + `timeline` reusing the same OptionManager | No | HEAVY | |

### 2.6 Animation and states

| ECharts capability | TTyChart today | Class | Notes |
|---|---|---|---|
| Any animation at all | **No** | — | `tyControls.Animation`/`Transitions` exist in the library; the chart uses neither |
| `animation` master switch, per-series override | No | NATURAL | |
| `animationThreshold` (2000) | No | NATURAL | |
| `animationDuration` (1000) / `animationDurationUpdate` (500), `number \| (dataIndex) => number` | No | NATURAL | |
| `animationEasing` (`cubicInOut`) / `animationEasingUpdate` | No | NATURAL | |
| `animationDelay` / `animationDelayUpdate`, `number \| (dataIndex, params) => number` — the stagger idiom | No | NATURAL | |
| 31 named easings (linear + 10 families × In/Out/InOut) | No | NATURAL | Closed-form scalars; copy them |
| Arbitrary `cubic-bezier(a,b,c,d)` easing strings (`createCubicEasingFunc`, solved by `cubicRootAt`) | No | NATURAL | **Verified present** in the shipped zrender: `easingFuncs[easing] \|\| createCubicEasingFunc(easing)`. Report 07's "no cubic-bezier" claim is wrong — it looked only at `src/`, where the animator is vendored |
| Precedence `extraOpts > payload > model` (dataZoom/resize inject `payload.animation`) | No | NATURAL | |
| Three phases enter/update/leave → `initProps`/`updateProps`/`removeElement`; removal fades `opacity → 0` then detaches | No | NATURAL | |
| `Animator`/`Track` per animated property, value types number / 1-D array / 2-D array / colour / linear+radial gradient / unknown, with gradient stop resampling | No | NATURAL | |
| `during` per-frame callback, `loop`, `setToFinal`, `aborted`/`done` | No | NATURAL | |
| Additive animation (compose onto a still-running animator) | No | HEAVY | Needed for smooth interruption of dataZoom drags |
| `keyframeAnimation` (`{duration, delay, easing, loop, keyframes:[{percent, easing, …}]}`, multiple concurrent tracks, beats `transition`) | No | HEAVY | |
| Element `transition` language (`''`/`style`/`shape`/`extra` namespaces, `'all'` or prop list, default `['x','y']`), `enterFrom`, `leaveTo`, per-phase `{duration, easing, delay}` | No | HEAVY | |
| Label animation (fade in for new; x/y/rotation tween from `oldLayout`; per-state `oldLayoutSelect`/`oldLayoutEmphasis` as the "from") | No | NATURAL | |
| `stateAnimation {duration: 300, easing: 'cubicOut'}` | No | NATURAL | |
| Morphing (`morphPath`/`combineMorph`/`separateMorph`): path → cubics, sub-path alignment with synthetic degenerates, signed-area centroid + winding reversal, `findBestRingOffset` O(n²), brute-force rotation search | No | HEAVY | Multi-week; report 07 recommends deferring |
| Shape splitting (`dividePath`): rect grid / sector angular fast paths + general `binaryDividePolygon` area-balanced bisection | No | HEAVY | |
| `universalTransition` (`enabled`, `seriesKey` string or array, `divideShape` split/clone with alpha fit `1-(1-α)^(1/n)`, `delay(i,count)`, groupId/childGroupId drill direction, `morph: false` opt-out) | No | HEAVY | |
| Targeted transition (`setOption(opt, {transition:{from:{seriesIndex,dimension},to:{…}}})`) | No | HEAVY | |
| 4 display states as a **stack** of partial styles on the element, with a synthesising `stateProxy` | No | HEAVY | |
| Default emphasis fill = `lift(normalFill, -0.1)` (gradients lifted stop-wise); stroke lifted only if fill wasn't; `fill:'inherit'` cancels | No | NATURAL | |
| Default blur = `opacity × 0.1`, guarded against double application | No | NATURAL | |
| Default select = z2 +9, no colour change | No | NATURAL | |
| `emphasis.disabled` perf escape hatch | No | NATURAL | |
| `emphasis.focus` (8 values) and `blurScope` (3 values) fan-out over the coordinate system / series / globally | No | HEAVY | Adjacency/ancestor/descendant/trajectory need graph/tree traversal |
| `emphasis.scale` bool \| number (1.1 default; pie `scaleSize`; effectScatter 2.5) | No | NATURAL | |
| `selectedMode` (5 values) across 19 series; per-datum `select.disabled`; select/unselect/toggleSelect actions + `selectchanged` | No | NATURAL | |
| 32-slot highlight-digit map so legend/tooltip/API highlights compose | No | NATURAL | |
| `highDownSilentOnTouch` | No | BROWSER-BOUND-ish | |
| Hover state changes anything visual at all | **No** | — | `FHoverHit` drives only whether a tooltip is drawn |

### 2.7 Interaction and API

| ECharts capability | TTyChart today | Class | Notes |
|---|---|---|---|
| `setOption(option, {notMerge, replaceMerge, lazyUpdate, silent, transition})` — one declarative tree in | No (published properties instead) | HEAVY | See §6 open question 2 |
| Normal Merge (id → name → positional → append; nothing removed; stable indices) | No | HEAVY | Write the doc's worked example as a test |
| Replace Merge (id-match only; unmatched removed leaving index holes) | No | HEAVY | The only way to delete a component |
| `lazyUpdate` + pending-update coalescing | No | HEAVY | |
| Re-entrancy guard (`IN_EC_CYCLE_KEY`) + `_pendingActions` queue | No | HEAVY | Actions from inside handlers must queue, not recurse |
| `setTheme(theme, {silent})` | Partial | NATURAL | The controller/`.tycss` system already does this, better |
| `getOption()` round-trip incl. interaction state | Partial | NATURAL | `.lfm` streaming is the analogue |
| `getWidth`/`getHeight`/`getDevicePixelRatio`/`getDom`/`getId` | Partial | NATURAL | LCL gives these |
| `resize({width, height, silent, animation})` re-evaluating media queries | Partial | NATURAL | `OnResize` → invalidate; no media queries |
| `dispatchAction(payload, {silent, flush})` — ~46 typed commands | No | NATURAL as methods | |
| Batch actions (`payload.batch`) fanning out into `{type, batch:[…]}` events | No | HEAVY | Decide early; retrofitting the event shape is painful |
| The 7-level update ladder (`prepareAndUpdate` / `update` / `updateTransform` / `updateView` / `updateVisual` / `updateLayout` / `none` / `'<cpt>:<method>'`) | No | HEAVY | **Adopt verbatim** — this is why ECharts stays fast |
| Staged pipeline (preprocessor → processor → coordsys → visual → layout → render) with priority ordering | No | HEAVY | "Porting it is the project" |
| 7 lifecycle hooks (`afterinit`, `coordsys:aftercreate`, `series:beforeupdate`, `series:layoutlabels`, `series:transition`, `series:afterupdate`, `afterupdate`) | No | HEAVY | Label layout and universal transition are listeners, not hard-coded steps |
| 9 mouse events (click, dblclick, mouseover, mouseout, mousemove, mousedown, mouseup, globalout, contextmenu) | Partial | NATURAL | LCL gives all of them on the control; none carry a data payload |
| Event payload record (componentType, componentIndex, seriesType/Index/Id/Name, name, dataIndex, data, dataType, value, color, info) | No | NATURAL | **The single most portable piece of the design.** Today: `HitTestAt` returns `(SeriesIndex, PointIndex)` |
| markLine/markPoint/markArea rewritten to `componentType: 'series'` for queryability | No | NATURAL | |
| Query filtering `chart.on('click', query, handler)` (string `'series.line'` or an object split into cpt/data/other buckets) | No | HEAVY | ~80 lines; what makes the event API usable at scale |
| ~45 action-derived events (all lowercased) | No | NATURAL | |
| Refined events (`selectchanged`, `axisbreakchanged` with `fromAction`/`fromActionPayload`) | No | HEAVY | |
| `rendered` ({elapsedTime}) / `finished` | No | NATURAL | |
| 5 core actions (highlight, downplay, select, unselect, toggleSelect) with a state-only fast path | No | NATURAL | |
| 6 legend actions, 2 tooltip actions (`showTip` 3 payload forms / `hideTip`) | No | NATURAL | |
| `updateAxisPointer` (broadcast to all views) | No | HEAVY | |
| `dataZoom` action + `takeGlobalCursor` gesture mutex | No | HEAVY | |
| `selectDataRange` (visualMap) | No | NATURAL | |
| `timelineChange` / `timelinePlayChange` (auto-stop at end with `loop:false`) | No | NATURAL | |
| 3 toolbox actions (`restore`, `changeDataView`, `changeMagicType`) | No | NATURAL action / BROWSER-BOUND UI | |
| 4 geo actions (geoSelect/UnSelect/ToggleSelect/geoRoam) | No | HEAVY | |
| 3 brush actions (`brush` with px `range` vs data `coordRange`, `brushEnd`, `brushSelect`) | No | HEAVY | |
| 3 axis-break actions (expand/collapse/toggle) | No | HEAVY | |
| Series actions: `changeAxisOrder` (bar race), `focusNodeAdjacency`/`unfocus`, `dragNode`, `treeExpandAndCollapse`, 4 treemap actions, `sunburstRootToNode`, `axisAreaSelect`, `parallelAxisExpand` | No | HEAVY | |
| 4 roam actions from one generator (geoRoam, graphRoam, sankeyRoam, treeRoam) | No | HEAVY | |
| `roam` (6 spellings → 4 behaviours) + `scaleLimit` + `roamTrigger` + mutating `center`/`zoom` in the live option | No | HEAVY | |
| `preserveAspect` object-fit semantics (contain/cover + 3×3 alignment) | No | NATURAL | |
| Drag: sankey nodes, graph nodes, graphic elements (`draggable: true \| 'horizontal' \| 'vertical'`) | No | HEAVY / BROWSER-BOUND for HTML5 drag semantics | |
| `silent` vs `triggerEvent` (opt-in events on non-data components: axisLabel, axisName, legend, title, matrix, line) | Partial | NATURAL | |
| `ignore` (no render, no hit) vs `invisible` (no render, still hit) | No | NATURAL | |
| `hitTest` inverse consistency between paint and pointer | **Yes** | — | The house "TTySegmented rule": paint and hit-test call the *same* pure functions. **This discipline is TTyChart's single strongest asset and must survive the rewrite** |
| `convertToPixel` / `convertFromPixel` / `convertToLayout` / `containPixel` | No | HEAVY | |
| `getVisual(finder, 'color' \| 'symbol' \| 'symbolSize')` | No | NATURAL | |
| `appendData({seriesIndex, data})` streaming | No | NATURAL | |
| `clear()` / `dispose()` / `isDisposed()` | Partial | NATURAL | Ordinary LCL lifetime |
| `makeActionFromEvent` (event → action reversal) | No | NATURAL | |
| `updateLabelLayout()` | No | HEAVY | |
| `connect(group)` cross-instance action replay with a 3-state re-entrancy guard + `escapeConnect` | No | HEAVY | Natively: an explicit controller shared by several chart controls |
| `getConnectedDataURL` compositing a group | No | HEAVY | Composite `TBGRABitmap`s **directly** (`MakeBitmapCopy` black-image trap) |
| `showLoading` / `hideLoading` (12 options) | No | NATURAL | |
| `media` responsive queries (6 keys) | No | NATURAL | |
| `registerLocale` + ~60 localisable strings (12 months, 12 abbr, 7 weekdays, 7 abbr, legend selector, 6 toolbox groups, 24 series type names, the aria templates); 26 shipped locales | No | NATURAL | `resourcestring` + per-package `.po` (en + zh_CN) is exactly this; **empty `.po` entries block app startup** |
| `echarts.time.format` 24-token vocabulary + `roundTime` (6 units) | Partial | NATURAL | Number format is `'0.###'`, deliberately locale-independent; no date tokens |
| `echarts.number` helpers (linearMap, nice, quantile, asc, getPrecision, parsePercent, parseDate, …) | Partial | NATURAL | `TyChartNiceRange` is the only one |
| `echarts.graphic` shape classes + `registerShape` | No | NATURAL | |
| Registries: ComponentModel/View, SeriesModel/ChartView, CustomSeries, SubTypeDefaulter, CoordinateSystem, Layout, Visual, Processor, Preprocessor, Action, Transform, Loading, Map, PostInit, PostUpdate, UpdateLifecycle, Painter, Impl | No | HEAVY | Pascal answer: registered classes, not function tables |
| `setPlatformAPI({createCanvas, measureText, loadImage})` | n/a | BROWSER-BOUND | Delete the seam; FPC has real text metrics |
| `init` opts `useDirtyRect` / `useCoarsePointer` / `pointerSize` / `hoverLayerThreshold` / `devicePixelRatio` | No | BROWSER-BOUND as *public options* | Keep the concepts internal; DPI already comes from `Font.PixelsPerInch` |
| Keyboard navigation / focus | No | — | Blocked by `TTyGraphicControl` (no `HWND`, no `TabStop`, no `WM_KEYDOWN`) |

### 2.8 Export and output

| ECharts capability | TTyChart today | Class | Notes |
|---|---|---|---|
| Raster export (`renderToCanvas`, `getDataURL({type:'png'\|'jpeg', pixelRatio, backgroundColor})`) | **Yes** | NATURAL | 6 `SaveToStream`/`SaveToFile` overloads, `TBGRAImageFormat` (png/jpeg/bmp/tiff), explicit W/H re-layout |
| The `AlphaFill(255)` fix (GDI never writes the alpha plane) | **Yes** | NATURAL | Already learned; keep it |
| Headless render without a window handle | **Yes** | NATURAL | `TChartExportTest` drives the real `RenderTo` off-screen — this is how the rewrite should be tested too |
| `excludeComponents` (e.g. `['toolbox']`) | No | NATURAL | Skip those views during the export render |
| `pixelRatio` / DPI-scaled export | Partial | NATURAL | Sized overloads re-lay-out but keep the control's PPI for text — that is a deliberate choice worth revisiting |
| `backgroundColor` override on export | No | NATURAL | |
| SVG string output (`renderToSVGString`, `getSvgDataURL`, `getDataURL({type:'svg'})`, `useViewBox`) | No | BROWSER-BOUND | No SVG back-end; the same display list could emit EMF/PDF if vector export is ever wanted |
| SSR mode + `ecmeta_*` attributes + `ssr/client` `hydrate()` | No | BROWSER-BOUND | Meaningless natively; "headless render" already exists |
| `getConnectedDataURL` (composite a `connect` group) | No | HEAVY | |
| Copy-to-clipboard / print | No | NATURAL | Neither library has it; a natural desktop addition |

---

## 3. What "cover all of ECharts" cannot mean

Some of ECharts' surface has no native meaning at all. These are not gaps to close; they are the DOM
branch of forks that already have a canvas branch, or they are entire ecosystems.

**1. The SVG renderer and everything hanging off it.**
`renderer: 'svg'`, the vdom `patch`, `<defs>` ids, CSS `@keyframes` emission, `renderToSVGString`,
`getSvgDataURL`, `getDataURL({type:'svg'})`, `useViewBox`, `toolbox.saveAsImage.type:'svg'`.
*Native equivalent:* none, and none is wanted. The one portable lesson is that ECharts' element model is
renderer-agnostic. If vector export is ever a requirement, it is a second back-end emitting EMF or PDF from
the same display list — a separate project, not this option.

**2. SSR / headless-in-a-browser.**
`ssr: true`, the `ecmeta_series_index`/`ecmeta_data_index`/`ecmeta_ssr_type` attributes, and the
`ssr/client` `hydrate(dom, {on})` function.
*Native equivalent:* already exists and is better. `RenderExportBitmap` renders a full chart with no window
handle, and `TChartExportTest` proves it. Keep the *idea* (render without a window), delete the machinery.

**3. The HTML tooltip.**
`renderMode: 'html'` (the ECharts **default**), `appendToBody`, `appendTo`, `className`, `extraCssText`,
`formatter` returning HTML strings or `HTMLElement[]`, the CSS `cubic-bezier` transition,
`transitionDuration`, `displayTransition`, native text selection inside the tooltip, and `enterable` with
interactive widgets inside.
*Native equivalent:* `renderMode: 'richText'` — which ECharts already ships as a first-class,
fully-featured path for DOM-free environments (WeChat mini-programs). Everything BROWSER-BOUND in the
tooltip family is the `'html'` half of a fork whose other half is exactly what a native port needs.
The `tooltipMarkup` two-stage design (structured `section`/`nameValue` blocks → one renderer) is portable
and should be copied. What genuinely cannot be reproduced without a real popup window: a tooltip that
extends beyond the control's bounds. TTyChart deliberately chose in-bitmap tooltips and documented three
reasons; escaping the bounds means `TTyPopupSurface = class(TForm)` and the GTK3/Wayland popup grab and
reposition traps this repo has already paid for once.

**4. HTML rich text.**
ECharts' `rich` is **not** HTML — it is a hand-written inline-block layout engine over canvas text runs.
That part is fully portable (and is the blueprint for the tooltip, axis labels, legend items and the
axisPointer label). What is *not* portable is `backgroundColor: {image: HTMLImageElement}` with async URL
loading, the global image LRU, and the "re-dirty the host element when the image finishes loading"
callback. *Native equivalent:* accept an already-loaded `TBGRABitmap` handle — and never round-trip it
through `TPicture` (the `MakeBitmapCopy` black-image trap).

**5. WebGL / echarts-gl.**
`scatter3D`, `bar3D`, `surface`, `lines3D`, `linesGL`, `scatterGL`, `flowGL`, `graphGL`, `polygons3D`,
`globe`, `grid3D`, `geo3D`, `mapbox`, `cartesian3D`.
*Native equivalent:* none in this pipeline. The library is CPU-rasterise-then-blit; `BGRACanvasGL` exists in
the BGRABitmap package but nothing in ty-controls uses it, and adopting it would fork the entire painter
stack. These are not even in the ECharts repo — they are a separate package. Out of scope, permanently.

**6. Tile-map coordinate systems.**
`bmap`, `amap`, `leaflet`. These are overlays on third-party JS map widgets fetching tiles over HTTP.
*Native equivalent:* none without an HTTP client, a tile cache, an attribution/licensing story and a
per-provider API key. Out of scope.

**7. The GeoJSON map ecosystem — a data burden, not a code burden.**
The *parser* is HEAVY-lite (Polygon/MultiPolygon/LineString/MultiLineString, holes, centroid,
point-in-polygon, bbox index — all CPU work, no browser needed). What is genuinely unbounded is everything
around it: ECharts ships **no** map data; users `registerMap` GeoJSON they fetched themselves, and the
ECharts gallery leans on a large ecosystem of community map files (world, every country, every Chinese
province, US states). Shipping maps means shipping megabytes of geometry with their own licences,
maintaining them as borders change, and taking a position on politically contested boundaries.
*Recommendation:* if maps are in scope at all, ship the **engine** (`registerMap` equivalent + a fixed set
of projections behind a Pascal interface: Mercator, equirectangular, conic equal-area) and ship **no map
data** — exactly ECharts' own posture. And note `geo.projection` as ECharts defines it is a *pluggable JS
callback pair* whose documented usage is "pass d3-geo in"; the native form is a closed interface with
built-in implementations, which is less flexible and more honest.

**8. SVG base maps** (`registerMap(name, {svg})`, named SVG elements as selectable regions).
Requires embedding an SVG subset parser *and* renderer (paths, transforms, `viewBox`,
`preserveAspectRatio`, element ids). BGRA's `addPath(SvgPathString)` covers path *data*, not SVG documents.
*Verdict:* out of scope unless floor-plan / seat-map / beef-cuts diagrams are an explicit requirement.

**9. Function-valued options as an API style.**
`formatter`, `labelLayout`, `min`/`max`, `animationDelay(dataIndex)`, `symbolSize(value, params)`,
`sampling`, `renderItem`, `axisPointer.link.mapper`, `sort` comparators, `projection.project`,
`graphic.onclick`. Roughly 30 of them across the surface.
*Native equivalent:* Pascal method pointers / events. This is a design decision, not a blocker — but it
changes the option shape substantially and **the callback signature convention must be settled once,
before any of them is implemented.**

**10. Browser-shaped tuning options.**
`useDirtyRect`, `hoverLayerThreshold`, `devicePixelRatio`, `useCoarsePointer`, `pointerSize`,
`zlevel`-as-a-canvas-layer, `progressive`'s rAF frame budget, `blendMode` beyond `'lighter'`,
`preventDefaultMouseMove`, CSS cursor-name strings, `env.browser.weChat` special cases,
`transform.print` (a `console.log`).
*Native equivalent:* the *concepts* survive as internal implementation details (a paint cache, an
invalidate rect, DPI from `Font.PixelsPerInch`, `TShiftState` for modifier gating, `TCursor` for cursors),
but they should not become public options. Exposing `useDirtyRect` on a Pascal control would be cargo cult.

**11. Toolbox `dataView` as specified.**
An editable `<textarea>` overlay with `optionToContent`/`contentToOption` returning HTML.
*Native equivalent:* the *action* (`changeDataView`) is portable; the widget must become a native dialog
with a grid or memo — which ty-controls has, along with the modal-drag lessons. It will not be
API-compatible, and pretending otherwise is a trap.

**12. `connect()` across chart instances.**
Portable in principle (event→action reversal + a re-entrancy guard), but ECharts' version relies on a
module-level instance registry and DOM `getBoundingClientRect` for composite export.
*Native equivalent:* an explicit shared controller object that several `TTyChart` controls register with —
cleaner than ECharts', and it should be designed that way rather than ported.

**13. Worker-thread rendering.**
Not used by ECharts core either. FPC threads cannot touch the canvas. Nothing to do.

**One honest framing for the maintainer:** removing categories 1, 2, 3(html half), 5, 6, 8 and 13 from
ECharts' surface removes roughly 10–15 % of its option count and close to none of what a desktop
application actually plots. "Cover all of ECharts" is a defensible goal *if* it is stated as **"cover all
of ECharts' charting and interaction capability, minus the browser-delivery layer, minus WebGL, minus the
map data ecosystem."** That is still an enormous target. `[corrected]` The remaining ~85 % is not "the
138k lines" — it is **~169,800 lines**: `echarts/src` at 138,362 *plus* `zrender/src` at 31,477. BGRABitmap
substitutes for zrender's *rasteriser* and for nothing else; the retained element tree (`Element.ts`,
2,172 lines), the animation track engine (`Animator.ts`, 1,148), the retained path buffer and
bounding-rect maths (`PathProxy.ts`, 1,009), the rich-text layout engine (`parseText.ts`, 951) and the
per-shape hit-test inverses (`contain/path.ts`, 408) all have to be written. That is the hardest ~18 %
of the port, and it sits underneath everything in §5.

---

## 4. Architectural verdict

**TTyChart's current shape cannot be extended to this. 3.1 needs a re-architecture.** Not a rewrite from
zero — the existing paint code, the export path, the hit-test discipline and the theme integration are all
keepers — but the *data model*, the *coordinate/scale layer*, the *series dispatch* and the *style/state
layer* have to be replaced rather than grown.

### 4.1 The argument, from the evidence

**Evidence 1 — the rasteriser is already sufficient, so the ceiling is elsewhere.**
Report 09 §4.5 is categorical: BGRABitmap 11.6.6 gives cubic and quadratic beziers, splines, SVG path
input, winding *and* even-odd fill, antialiased arbitrary-path clipping (a real grayscale mask, not a
rect region), full affine transforms with a separate stroke matrix, linear **and** radial gradients,
patterns, arbitrary dash arrays with caps/joins, per-vertex Gouraud fills, path shadows, `isPointInPath`,
rotated text (already in production in `tyControls.Menu.pas`) and text-along-a-path. Report 09 then lists
what is "physically reachable today with the current painter/BGRA stack": area charts, stacked/percent
bars, horizontal bars, smooth and stepped lines, scatter/bubble, radar, gauges, heatmaps, funnel,
candlestick, rose pie, rotated and curved labels, dashed marklines, gradient fills, crosshairs, custom
symbols. **None of those exist today.** When the drawing layer can do sixteen things the control does not
do, the constraint is not drawing.

`[corrected]` — with one qualification that changes Tier 0. All of that is true of **BGRABitmap**; none
of it is exposed by **`TTyPainter`**, the API the library actually paints through, whose public surface
has no path, arc, transform, clip or dash (`tyControls.Painter.pas:123-232`). The chart already escapes
through `P.Bitmap.Canvas2D`. Making that escape the norm across ~20 series renderers would scatter DPI
scaling, theme resolution, bidi text and the non-Windows supersampling gate across all of them, so
**a vector API on `TTyPainter` is itself a Tier 0 foundation** (added to §5). The argument survives — the
raster ceiling is genuinely high — but "already sufficient" is a statement about BGRABitmap, not about
the stack. See `11-critique.md` finding 2.

**Evidence 2 — `Values: string` is not a limitation, it is a different data model.**
A point is `(categoryIndex, value)`. Report 09 §1.5 enumerates the consequences: no (x, y) pairs, no
missing-value token, no per-point metadata, and a full re-parse on every access with no cache. Twenty of
the twenty-three ECharts series types need data shapes this cannot express. And it is not just series:
report 06 shows that per-point identity (`id`/`name`/`groupId`) is what `DataDiffer` keys on, and
`DataDiffer` is what every diff-based animation, every `universalTransition`, and ECharts' whole
"add a point and watch it fly in" behaviour rests on. Per-point *override records* are what `visualMap`,
`brush`'s `inBrush`/`outOfBrush`, `emphasis`/`select`, and per-datum tooltips all write into. Adding a
second published property (`ValuesY: string`?) does not fix this; it makes it worse. The data model must
become columnar and typed, with a per-point override side-table — which is report 06's NATURAL list
almost verbatim, and which FPC does *better* than JS.

**Evidence 3 — there is no coordinate system to extend, only inlined arithmetic.**
`TyChartValueToY`, `TyChartBarXRange` and the `ArcTan2 + 90°` inside `DrawPie`/`TyChartPieHitTest` *are*
the coordinate mapping. They are pure functions (good) but they are not an interface, they are not
swappable, and each new family would need its own pair of forward and inverse functions plus its own paint
branch. ECharts gets scatter on seven coordinate systems and `custom` on all of them because
`dataToPoint`/`pointToData`/`containPoint`/`getArea` is a contract that series are written against
(report 01 §7.1). Report 04's porting notes make the same point from the other side: "Matrix/calendar as a
*host* for other coordinate systems… architecturally this means every coordinate system must accept an
externally supplied rect instead of always measuring against the canvas. **Cheap if designed in from the
start, expensive to retrofit.**"

**Evidence 4 — the layout is five literals where ECharts has a two-phase solver.**
`LayoutFor` scales margin 8, title 20, legend 18, Y gutter 38, X band 16 by DPI. There is no measurement
pass, so a 6-digit tick label overflows the gutter and a long category label overflows the band (report 09
§1.7). ECharts' `AxisBuilder` runs `axisLine → axisTickLabelEstimate → [shrink rect] →
axisTickLabelDetermine → axisName` specifically because label sizes determine the plot rect, and that
two-pass structure is what `containLabel`/`outerBounds` requires (report 04 §17). Axis names, rotated
labels, `nameMoveOverlap`, `hideOverlap` and multi-axis offsets all live inside that pass. You cannot bolt
a measurement-driven layout onto a set of constants; the constants *are* the layout function.

**Evidence 5 — `ChartType` is a closed enum with frozen ordinals; the goal is per-series types.**
The unit header states the non-goal outright: *"Still NOT included: zoom / mixed chart types / secondary
axes."* Mixed types (a line over bars, a scatter over candlesticks, a markLine over anything) is the
single most-requested chart feature in any desktop toolkit, and it is not an enum value — it requires
`series[i].Type` plus per-series axis binding plus a renderer registry. Report 09 §3.5 additionally notes
that `.lfm` streaming has frozen the enum's ordinals (`ctDonut` was *appended* for exactly this reason), so
the enum can only ever grow at the tail, and only as a *chart-level default*.

**Evidence 6 — states, animation and interaction are all downstream of one missing substrate.**
There are no element states: hovering changes the tooltip and nothing else. The 4-state model is what
`emphasis`, `select`, legend hover, brush dimming, `visualMap` out-of-range, `axisPointer.triggerEmphasis`
and tooltip highlight *all* express themselves through (report 07 §6). Similarly, there is no animation at
all, and report 09 §4.4 explains why that is architectural rather than a to-do: a graphic control's
`Invalidate` damages the parent, which repaints its whole client area, measured at ~23 ns/px, i.e. ~14.9 ms
for a 900×700 page. Animation is not merely absent — it is *penalised by the base class*.

**Evidence 7 — the graphic/windowed fork gates a whole component tier.**
Report 09 §3.3 calls this "the single biggest fork in the road", and it is right: `TTyScrollBar` is
`TTyCustomControl` and can never be parented to a graphic control. dataZoom sliders, toolbox strips,
in-chart scrollbars, inline editors and keyboard navigation are base-class problems, not drawing problems.
(They *can* be self-drawn with hand-rolled hit-testing — ty-controls does exactly that elsewhere — but
focus and keyboard cannot.)

**What survives, and must survive.** Three things in the current design are genuinely good and should be
carried into the new architecture unchanged in spirit:

- **The pure-function seam and the TTySegmented rule.** All scale/layout/hit-test arithmetic lives in
  `interface`-level pure functions; paint and hit-test call the *same* ones, so "the datum the pointer
  reports can never drift from the datum that was drawn there." At ECharts scale this becomes: every
  coordinate system, scale and layout is a testable unit with no control/painter/handle state. Keep it.
- **The headless export test path.** `TChartExportTest` drives the real `RenderTo` through a `TBitmap`
  with no handle. That is how a 20-series engine gets regression-tested without a GUI, and it is the only
  way to make golden-image tests practical.
- **Theme-token discipline.** `ResolveStyle` + `Present` testing + `Metric` with named `…Var` constants.
  ECharts' v6 design-token table is a *subset* of what `.tycss` already does; the new chart typeKeys should
  extend the existing system, not import ECharts'.

### 4.2 Recommendation

**Re-architect behind a compatibility façade.** Concretely:

1. **Split the unit family**, following the Grid precedent (`Grid.pas` + `Grid.Layout.pas` +
   `Grid.Csv.pas`) rather than growing `Chart.pas` past 1,721 lines:
   - `tyControls.Chart.Data.pas` — columnar store, dimensions, encode, per-point overrides, ids
   - `tyControls.Chart.Scale.pas` — ordinal / interval / log / time scales, nice ticks, minor ticks
   - `tyControls.Chart.Coord.pas` — the coordinate-system interface + cartesian2d, then polar, single, …
   - `tyControls.Chart.Layout.pas` — box layout, the two-phase axis build, label de-collision
   - `tyControls.Chart.Series.pas` — the series registry and per-series renderers
   - `tyControls.Chart.pas` — the control: streaming, painting, hit-testing, events, theme
   Every one of the first four is pure and headless-testable.

2. **Decide the base class first, once.** The recommendation is **switch to `TTyCustomControl`** (windowed),
   because dataZoom, toolbox, keyboard navigation and focus are all on the far side of that line and all of
   them are Tier 1–2 features. The costs are real and documented in this repo: windowed controls cannot
   cast shadows outside themselves (`FillCornerGaps`), erase to the parent's LCL `Color` rather than the
   theme surface unless explicitly handled (`windowed-ghost-erases-to-parent-color`), and clip against
   windowed siblings. If the decision is instead to *stay* graphic, then dataZoom sliders, the toolbox and
   keyboard access must be struck from the roadmap or built as fully self-drawn widgets with hand-rolled
   hit-testing — which is possible but should be an explicit choice, not a discovery in month three.

3. **Keep `TTyChart`'s 9 published properties as a façade** over the new model (see §4.3).

4. **New theme typeKeys** (`TyChartAxis`, `TyChartGrid`, `TyChartLabel`, `TyChartLegend`, `TyChartTitle`,
   `TyChartAxisPointer`, `TyChartMark…`) plus metric tokens must land in `themes/light.tycss` **and**
   `tyControls.Css.Catalog.pas`, be regenerated into `DefaultTheme.pas`/`BuiltinThemeData.pas`, **and be
   checked against all 17 themes** — a skin that writes any rule for a typeKey suppresses the built-ins for
   that key wholesale, variants included. While there: `--chart-donut-hole` and `--chart-hit-radius` are
   read by the code but defined in no theme and absent from the catalog. Fix that in the same pass.

### 4.3 Migration and compatibility cost for existing `.lfm` files

This is the part that constrains the design, so it is worth being precise. An existing chart `.lfm` looks
like:

```
object TTyChart1: TTyChart
  ChartType = ctBar
  Title = '...'
  Categories.Strings = (...)
  Series = <
    item Name = 'Q1' Color = clFuchsia Values = '1,2,3' end
    ...>
  ShowLegend = True
  ShowGrid = True
end
```

| Existing surface | Compatibility requirement | Cost |
|---|---|---|
| `ChartType: TTyChartType` (ordinals frozen: ctLine=0, ctBar=1, ctPie=2, ctDonut=3) | Must keep the four ordinals and only ever **append**. Its new meaning: the default type for series that do not set their own | **Low** — but it permanently constrains the enum |
| `Series: TCollection` streaming as `item … end` | The collection must keep its class name and the item's published property *names* | **Low** if the item keeps `Name`/`Color`/`Values` |
| `Values: string` (CSV) | **This is the hard one.** If the store becomes typed, `Values` must remain a published `string` that reads and writes the CSV form losslessly — a projection over the first value dimension. A series that only ever had a CSV must round-trip byte-identically, or every existing `.lfm` silently loses its data | **Medium.** Add `DefineProperties`/`ReadData`/`WriteData` for the typed store; `Values` stays as the legacy text projection. Note that today `'1,,3'` yields **2** values and unparseable text becomes 0.0 — the new parser must decide whether to preserve those bugs for compatibility or emit NaN and accept a behaviour change (recommendation: emit NaN, and document it as a fix) |
| `Color: TColor default clDefault` | Keep. It becomes the series' `itemStyle.color` shorthand | **Low** |
| `Categories: TStrings` | Keep. It becomes the ordinal category list of the default x axis | **Low** |
| `Title: TCaption` | Keep as a shorthand for `Title.Text` once a title component exists | **Low** |
| `ShowLegend` / `ShowGrid` / `ShowValues` / `ShowTooltip: Boolean` | Once real sub-objects exist there are two ways to say the same thing. The safe answer for `.lfm` round-trip is **keep the boolean authoritative** and have the component's `Show` default from it; the clean answer is to deprecate them with `stored False`, which breaks old-form round-trip. **Maintainer decision** (see §6) | **Medium** — this is an API-shape decision, not a coding cost |
| `OnGetTooltip(Sender; ASeries, APoint: Integer; var AText)` | Survives for item-mode tooltips. Axis-mode tooltips have N points and need a *new* event; keep both | **Low** |
| `HitTestAt(X,Y): TTyChartHit` | Survives. Add a richer overload returning the full event-payload record | **Low** |
| The 15 exported pure functions (`TyChartNiceRange`, `TyChartBarXRange`, `TyChartLayoutFor`, `TyChartBarRect`, `TyChartPieSweeps`, `TyChart*HitTest`, `TyChartTooltipRect`, `TyChartDefaultTooltip`, …) | They are **interface-level and therefore public API**, and ~60 tests call them | **High.** Either keep the signatures as thin wrappers over the new engine, or accept a deliberate test rewrite. Several of these tests pin *current* behaviour that the rewrite intends to change — the hard-coded 5-tick target, the forced zero baseline, the 15 % bar inset, radial charts reading series 0 only. Repo memory (`tests-that-pin-the-bug`) says expect a batch to go red **on purpose**, and to check each red test asks the right question before repainting it green |
| `SaveToStream`/`SaveToFile` × 6 | Keep verbatim | **Zero** |
| Base class change (graphic → windowed) | `.lfm` names the class, not the ancestor, so streaming survives. What changes: new published properties appear (TabStop, ParentColor…), the control now clips and is clipped by windowed siblings, and it erases to the parent's LCL `Color` unless the paint path sets it to the theme surface first | **Medium**, and it needs real-machine verification on all three widgetsets — headless tests never run the LCL align engine |
| `examples/chart/` | Must keep working unchanged as the compatibility proof, then gain a second example exercising the new surface | **Low** |

**Net:** the compatibility story is workable — every existing published property can survive as a façade —
**provided `Values: string` is kept as a lossless legacy projection and the enum only ever grows at the
tail.** The genuinely expensive item is the exported pure-function API and its ~60 tests, and that cost is
unavoidable in any re-architecture.

---

## 5. Tiered capability roadmap

Grouped by (user value × cost). Sizes are relative effort per item: **S** ≈ days, **M** ≈ 1–2 weeks,
**L** ≈ 3–6 weeks, **XL** ≈ months. No schedule, no dates.

### Tier 0 — Foundations (nothing else works without these)

| Capability | Size |
|---|---|
| Unit split (`Chart.Data` / `.Scale` / `.Coord` / `.Layout` / `.Series`), all pure and headless-testable | S (organisational — do it first) |
| **`[corrected]` Vector API on `TTyPainter`** — paths (move/line/bezier/quadratic/arc/close), polylines, arbitrary-polygon fill with winding *and* even-odd, stroke with width/dash/cap/join, affine transforms, push/pop clip, per-element alpha, gradients and patterns as first-class fills, rotated text, `path://` symbol drawing, `isPointInPath`. All theme-aware and DPI-scaled like the existing entry points, so no series renderer has to reach for `Bitmap.Canvas2D` and re-derive scaling, bidi and the non-Windows supersampling gate. **Upstream of ~40 Tier 1/2 rows** — see `11-critique.md` finding 2 | L |
| **Base-class decision** and, if taken, migration to `TTyCustomControl` + real-machine verification on Win/GTK/Qt | M |
| Columnar typed data store: dimensions (float/int/ordinal/time), NaN as the no-data sentinel, per-point override side-table with Has-flags, per-point id/name, ordinal interning + inverted index | XL |
| `.lfm` compatibility layer: `Values` as a lossless CSV projection + `DefineProperties` for the typed store | M |
| Scale abstraction: ordinal / interval / log with `nice()` 1-2-3-5-10, minor ticks, `min`/`max`/`scale`/`splitNumber`/`interval`/`minInterval`/`maxInterval`/`boundaryGap`/`inverse`, degenerate-extent handling | L |
| Coordinate-system **interface** (`dataToPoint`/`pointToData`/`containPoint`/`getArea`/`getAxis`/`getBandWidth`) + `cartesian2d` with N x/y axes and a master/sub split | L |
| Box layout solver (`left/top/right/bottom/width/height`; px, `'%'`, keywords) shared by every component | M |
| Two-phase axis build (estimate labels → shrink rect → determine) — the `containLabel`/`outerBounds` substrate | L |
| Series registry: per-series `Type` + per-series axis binding (this is what unlocks mixed types and secondary axes) | M |
| Element/paint list with `z`/`z2` ordering, plus **one** shared hit-test path (the TTySegmented rule, scaled up) | M |
| Text measurement cache (per-font record, ASCII width table, string LRU) + wrap/truncate/ellipsis wired to `TyWrapTextCJK` | M |
| 4-state style model (normal/emphasis/blur/select as a stack) with `focus: none\|self\|series` and `blurScope` | M |
| Style resolution: `itemStyle`/`lineStyle`/`areaStyle` full key sets → BGRA canvas state | M |
| New chart theme typeKeys + metric tokens in `light.tycss` + `Css.Catalog.pas` + regenerated themes, verified across all 17 skins; fix the two orphan metrics | M |
| `subPixelOptimize` for crisp 1 px axis/grid/bar edges | S |

### Tier 1 — The 80 % most desktop apps actually use

| Capability | Size |
|---|---|
| line: `areaStyle` (+`origin`), `smooth` (port `poly.ts drawSegment` exactly), `smoothMonotone`, `step` start/middle/end, `connectNulls`, `clip`, `showSymbol` | M |
| Symbol library: 10 built-ins + `empty*` variants + `symbolSize`/`Rotate`/`Offset`/`KeepAspect` | M |
| bar: the shared `calcBarWidthAndOffset` solver (`barWidth`/`barMaxWidth`/`barMinWidth`/`barGap`/`barCategoryGap`/`barMinHeight`), horizontal bars, `borderRadius`, `showBackground` | M |
| Stacking: `stack` + `stackStrategy` ×4 + `stackOrder`, with the two calculated dimensions and `addSafe` | M |
| scatter / bubble (`symbolSize` from a dimension) | S |
| pie done properly: `startAngle`/`endAngle`/`clockwise`, `padAngle`, `minAngle` with redistribution, `roseType`, `selectedOffset`, `emphasis.scale`, `percentPrecision` with largest-remainder rounding | M |
| Axis anatomy: `axisLine` (+`onZero`, arrow symbols), `axisTick`, `minorTick`, `axisLabel` (rotate/formatter/margin/showMin-MaxLabel), `splitLine` (+colour cycling), `minorSplitLine`, `splitArea`, `name`/`nameLocation`/`nameGap`/`nameRotate`/`nameTruncate` | L |
| Multiple axes: `position`, `offset`, second Y axis, `gridIndex`, `alignTicks` | M |
| `axisLabel.interval: 'auto'` with the ±1 hysteresis cache | M |
| Time axis: 12-level ladder, per-level step search, calendar-boundary anchoring, level-tagged ticks, cascading per-level formatter, 24 format tokens, locale month/weekday tables | L |
| Legend as a real component: `orient`/`align`/box layout with wrap, per-item icon/style, `selectedMode` + **click-to-toggle**, inactive styling, `formatter`, `selector` buttons | M |
| Tooltip rebuilt on the `tooltipMarkup` block model: `trigger` item\|axis\|none, `triggerOn`, `formatter` templates, `valueFormatter`, `order`, `position` keywords, delays, `alwaysShowContent` | L |
| axisPointer: line \| shadow \| cross, `snap`, the value-label pill, slide animation | M |
| markPoint / markLine / markArea with all four position forms and min/max/average/median statistics | M |
| Label engine: 13 rect + 9 sector positions, `distance`/`rotate`/`offset`, template formatters (`{a}{b}{c}{d}{@dim}`), automatic inside/outside contrast colour, `overflow`/`ellipsis` | M |
| Label de-collision: `hideOverlap` (AABB + OBB SAT) and `moveOverlap` (`shiftLayoutOnXY`) | M |
| Palette machinery: `colorLayer`, `colorBy`, per-series palette, **name-keyed memoisation** so legend toggling doesn't reshuffle | S |
| Gradients (linear + radial) and pattern fills in series styles | M |
| Animation engine: 31 easings + `cubic-bezier()`, enter/update/leave, duration/delay(dataIndex)/easing (+Update variants), `animationThreshold`, `stateAnimation`, label animation from `oldLayout` | L |
| States wired end-to-end: emphasis `lift(-0.1)`, blur `×0.1`, select z2 lift, `focus`/`blurScope`, `selectedMode`, select/highlight actions + events | M |
| Event payload record + `HitTestAt` returning it; 9 mouse events carrying data context | M |
| dataZoom: `inside` gestures (modifier-gated) + `slider` widget + the window model + `filterMode` ×4 | L |
| Data plumbing: `encode` (18 roles), `dimensions`, `seriesLayoutBy`, a dataset-equivalent, default category-way/value-way encoding | L |
| Sampling: lttb (ECharts' exact variant) / minmax / average / sum / max / min / nearest | M |
| Series clipping to the plot band | S |
| `media` responsive queries (6 keys) | S |
| Export: `excludeComponents`, `backgroundColor`, explicit pixel ratio | S |
| Loading indicator | S |

### Tier 2 — Broad coverage

| Capability | Size |
|---|---|
| polar coordinate system + line/bar/scatter on polar, sector `cornerRadius`, `roundCap` (Sausage) | L |
| radar component + radar series (incl. cross-axis tick alignment) | M |
| gauge (band arc, progress, needle + `anchor`, title/detail blocks, `valueAnimation`, multi-value) | M |
| funnel | S |
| candlestick (OCLH, doji, auto layout, `large` mode, dataZoom sparkline dimension) | M |
| boxplot + the boxplot statistic transform | M |
| visualMap: continuous + piecewise, 8 channels, `inRange`/`outOfRange`, `hoverLink`, the polygon bar | L |
| heatmap on cartesian (cells, borderRadius, labels) | M |
| effectScatter ripple | S |
| pictorialBar (the repeat solve, `symbolClip`, `symbolBoundingData`, `pxSign`) | L |
| sunburst (radial subdivision, `levels`, drill-down, algorithmic colour ramp, radial/tangential labels) | M |
| treemap (squarified packing, breadcrumb, `upperLabel`, the visual sub-engine, drill-down + zoom) | L |
| tree (Buchheim tidy tree, radial, 4 orients, 2 edge shapes, expand/collapse) | L |
| sankey (layering, relaxation, ribbons, `orient`, node drag, `focus: 'trajectory'`) | L |
| graph (none/circular/force, `autoCurveness`, edge trimming, categories, `focus: 'adjacency'`, node drag) | L |
| chord (ring layout, the minAngle borrowing solver, ribbon geometry, gradient ribbons) | M |
| singleAxis + themeRiver | M |
| calendar coordinate system + calendar heatmap | M |
| `View` coordinate system + `RoamController` (pan/zoom, `scaleLimit`, `roamTrigger`, `preserveAspect`, `nodeScaleRatio`) | L |
| brush (4 shapes, cover interaction with 8 handles, `inBrush`/`outOfBrush`, `brushLink`, the `globalPan` mutex) | L |
| toolbox as a native strip (`saveAsImage`, `restore`, marquee `dataZoom`, `magicType`, `brush` toggles, custom buttons) | M |
| timeline component (option array per tick, play/pause/step, checkpoint slide, progress styling) | M |
| Rich text engine (`{name\|content}`, per-fragment box/image/percent widths, `lineOverflow`) | L |
| Decal pattern fills (LCM tiling, rotation, 6 built-ins) + `aria` description text | M |
| `graphic` overlay component (13 element types, `$action` merge, transforms, `bounding`) | M |
| SVG `path://` support `[corrected]` — **verified covered** by BGRA's path parser incl. elliptical arcs; only viewBox auto-fit is ours. Unlocks custom symbols, gauge needles, decal symbols, legend icons, `custom`'s path element | S |
| `custom` series as a Pascal event (`api.coord`/`size`/`style`/`visual`/`barLayout`, the 15 element types) | L |
| `large`-mode batched paths + arithmetic hit-scan | M |
| Progressive/chunked painting with a per-tick time budget | M |
| `appendData` streaming | S |
| lines series (2-point + polyline, end symbols, moving `effect` marker) | M |
| `convertToPixel` / `convertFromPixel` / `containPixel` public API | S |
| Axis extras: `containShape`, `dataMin`/`dataMax`, jitter (+ beeswarm packing), `customValues` | M |
| `labelLine` auto-routing (`nearestPointOnPath`, `limitTurnAngle`, `limitSurfaceAngle`) | M |
| Pie `avoidLabelOverlap` full solver (`alignTo`, `bleedMargin`, `edgeDistance`, ellipse re-solve) | L |
| `endLabel` + `label.valueAnimation` | S |
| parallel + parallelAxis + per-axis brushing | L |

### Tier 3 — The long tail

| Capability | Size |
|---|---|
| geo coordinate system: GeoJSON parsing, region hit-test, `specialAreas`, `nameMap`, `boundingCoords`, `layoutCenter`/`layoutSize`, region styling and selection | XL |
| map series (`mapValueCalculation`, `showLegendSymbol`, choropleth) + fixed projections behind an interface (Mercator, equirectangular, conic equal-area) | L |
| heatmap on geo (the density field: brush splatting + LUT recolour) | M |
| `matrix` coordinate system (tree headers, locator algebra, merged cells) | XL |
| `coordinateSystemUsage: 'box'` — coordinate systems and components nested in matrix/calendar cells | XL |
| Axis breaks (v6): piecewise domain mapping, cached randomised zigzag, tick pruning, expand/collapse actions | L |
| `realtimeSort` bar race (order from animated pixel length + ordinal-scale reorder + animated axis labels) | M |
| Universal transition + shape morphing (`morphPath`/`combineMorph`/`separateMorph`/`dividePath`, groupId direction sniffing) | XL |
| `keyframeAnimation` + the element transition mini-language on graphic/custom elements | M |
| Additive animation (compose onto a running animator) | M |
| `thumbnail` mini-map with a draggable viewport window | M |
| parallel `axisExpandable` fisheye | M |
| `axisPointer.link` + `mapper` across coordinate systems | M |
| Cross-control linkage (an explicit shared controller instead of `connect()`) + composite export | M |
| Dataset transform pipeline: registry, the filter condition DSL, the sort comparison rule, dimension inheritance, piping, multi-output | L |
| Statistical transforms: regression (4 methods), k-means clustering, histogram (4 binning rules) | L |
| `setOption`-style option-tree ingest with normal/replace merge (only if §6 Q2 says yes) | XL |
| Query filtering on events (`'series.line'`, `{seriesIndex, name, dataIndex, element}`) | S |
| Coarse-pointer hit fallback (bbox prefilter + polar spiral probe) for pen/touch | S |
| Dirty-rect / cached-surface painting (`TTyPaintCache`, remembering the `pf24bit` rule) | M |
| Batch actions + refined events | M |
| Designtime: a real series/data editor dialog, a `Values` property editor, a component editor verb (`tycontrols_dt.lpk`, compiled separately) | L |
| Keyboard navigation and MSAA/UIA accessibility (only reachable if the base class went windowed) | M |

### Tier X — Explicitly not doing

| Capability | Reason |
|---|---|
| SVG renderer, `renderToSVGString`, `getSvgDataURL`, `saveAsImage.type:'svg'`, `useViewBox` | No native analogue and no reason to want one. If vector export is ever required, it is an EMF/PDF back-end over the same display list — a separate project |
| SSR mode, `ecmeta_*` attributes, `ssr/client` `hydrate()` | Meaningless natively; headless rendering already exists via `RenderExportBitmap` |
| Tooltip `renderMode: 'html'` and everything under it (`appendToBody`, `appendTo`, `className`, `extraCssText`, HTML formatter returns, CSS transitions, `enterable` with widgets) | The `'richText'` path is the port. A tooltip that escapes the control's bounds is a *separate* decision (it needs `TTyPopupSurface` and the GTK3/Wayland popup traps) |
| echarts-gl (`scatter3D`, `bar3D`, `surface`, `lines3D`, `linesGL`, `scatterGL`, `flowGL`, `graphGL`, `polygons3D`, `globe`) and the `grid3D`/`geo3D`/`globe`/`mapbox`/`cartesian3D` coordinate systems | WebGL. Not even in the ECharts repo. The library is CPU-rasterise-then-blit; adopting `BGRACanvasGL` would fork the whole painter stack |
| `bmap` / `amap` / `leaflet` tile-map coordinate systems | Third-party JS map widgets fetching tiles over HTTP. Needs a network stack, a tile cache, API keys and an attribution story |
| Shipping GeoJSON map data | ECharts ships none either. Megabytes of geometry with their own licences, maintenance as borders change, and a position on contested boundaries. Ship the engine, not the atlas |
| SVG base maps (`registerMap(name, {svg})`) | Needs an embedded SVG document parser *and* renderer. Only reconsider if floor-plan / seat-map diagrams are an explicit requirement |
| `geo.projection` as a pluggable callback pair (d3-geo) | Ship a closed set of projections behind a Pascal interface instead |
| `toolbox.dataView` as a DOM textarea with `optionToContent`/`contentToOption` returning HTML | The action ports; the widget becomes a native dialog and will not be API-compatible |
| `setPlatformAPI({createCanvas, measureText, loadImage})` | The seam exists only because JS has no native text metrics. Delete it |
| `blendMode` beyond `'lighter'` | BGRA has `TBlendOperation`, not the full Porter-Duff + separable-blend set. Not worth it |
| `useDirtyRect`, `hoverLayerThreshold`, `devicePixelRatio`, `useCoarsePointer`, `pointerSize`, `zlevel`-as-a-canvas-layer, `preventDefaultMouseMove` as **public options** | Painter tuning tied to the DOM canvas model. Keep the concepts internal; exposing them on a Pascal control would be cargo cult |
| CSS cursor-name strings | Map to `TCursor`; do not accept CSS vocabulary |
| `transform.print` (`console.log` debugging) | Replace with a designer "dump" action or `OutputDebugString` if wanted at all |
| Worker-thread rendering | ECharts core has none; FPC threads cannot touch the canvas |
| `axisPointer.handle` (draggable touch puck) | Exists because a finger occludes the chart. Near-useless on desktop |
| The `reg` filter operator | Requires an `RegExpr` dependency for one operator. Ship `filter` without it and document the omission (revisit if §6 Q5 says dependencies are welcome) |
| HTML5 drag-and-drop semantics on graphic elements (`ondragenter`/`ondragleave`/`ondragover`/`ondrop`) | LCL drag/drop has different semantics; expose LCL's, not HTML's |

---

## 6. Open questions for the maintainer

These change the shape of the work and only the maintainer can decide them. Each is stated with the
consequence of each answer, not just the question.

**Q1 — Base class: does `TTyChart` become windowed (`TTyCustomControl`)?**
*Yes* unlocks dataZoom sliders, a toolbox strip, in-chart scrollbars, focus, keyboard navigation and
accessibility — i.e. a large slice of Tier 1 and Tier 2 — at the cost of: no shadows outside the control,
erase-to-parent-`Color` unless the paint path sets the theme surface, clipping against windowed siblings,
and a real-machine re-verification pass on Win32/GTK/Qt. *No* means those features must either be struck
from the roadmap or built as fully self-drawn widgets with hand-rolled hit-testing (possible — ty-controls
does this elsewhere) — except focus and keyboard, which are simply unreachable. **This decision gates
Tier 0 and cannot be deferred.**

**Q2 — API style: ECharts-style option objects, or Pascal published properties?**
Three coherent answers, and they are not compatible with each other:
(a) **Published properties + sub-objects** (`Chart.XAxis.Label.Rotate := 45`) — idiomatic LCL, streams to
`.lfm`, Object-Inspector-editable, discoverable. But ~1,950 ECharts option paths do not fit in an Object
Inspector, and every option must be hand-declared.
(b) **An option tree** (a `setOption`-equivalent taking a nested variant/JSON structure) — ECharts users
could paste their configs, coverage scales without hand-declaring each key, and ECharts documentation
becomes usable as-is. But it is not `.lfm`-streamable without `DefineProperties`, not
Object-Inspector-friendly, not type-checked, and it imports ECharts' merge semantics (normal merge,
replace merge, index holes) as a **hard requirement** — that alone is an XL item.
(c) **Both**: published properties for the common 80 %, an `Options: string` / `LoadFromJSON` escape hatch
for the rest.
Recommendation: **(a) as the primary surface with (c) as a later escape hatch** — it matches how every
other ty-controls control works and keeps designtime honest — but this is a genuine fork and it determines
whether §5's "option-tree ingest" item exists at all.

**Q3 — Backwards compatibility: how hard is the `.lfm` guarantee?**
Specifically: (i) must `Values = '1,,3'` keep yielding 2 values (today's behaviour) or may it become
`[1, NaN, 3]` (a behaviour change that fixes a real bug)? (ii) must unparseable text keep silently
becoming `0.0`, or may it become NaN? (iii) may `ShowLegend`/`ShowGrid`/`ShowValues`/`ShowTooltip` become
`stored False` aliases over component objects (breaking old-form round-trip) or must they stay
authoritative? (iv) are the 15 exported pure functions part of the public API contract, or may they be
replaced (and their ~60 tests rewritten)? Recommendation: fix (i) and (ii) as documented bug fixes, keep
(iii) authoritative, and treat (iv) as replaceable with a deliberate, reviewed test rewrite.

**Q4 — Are maps and GeoJSON in scope at all?**
This is the single largest Tier 3 item (XL) and it drags in a projection library, a polygon engine, and a
data-distribution question. If the answer is "engine yes, data no" the cost is bounded and the feature is
honest. If the answer is "we want a world map out of the box", the cost is unbounded and includes a
licensing and geopolitics decision. If the answer is "no", geo, map, lines-on-geo, the geo heatmap density
field and geo `roam` all leave the roadmap and Tier 3 shrinks by roughly half.

**Q5 — Dependency appetite.**
Two items are cheap with a dependency and expensive without: regular expressions for the filter DSL
(`RegExpr`), and a vetted ISO-8601/loose date parser for the time axis. What is the policy:
FPC/LCL/BGRABitmap only, or are small vetted units acceptable?

`[corrected]` The third item — an SVG path parser — **is retired**. BGRA's `addPath(string)` was verified
against `bgrapath.pas`: line 2301 accepts `L H V C S Q T A` (plus `M`/`Z` and, via `upcase(command)` at
2303, every relative form), and `'A'` at 2400-2410 dispatches to the full elliptical
`arcTo(rx, ry, xAngleRadCW, largeArc, anticlockwise, x, y)`. The complete grammar is supported.

**Q6 — Callback convention, settled once.**
Roughly 30 ECharts options are function-valued (`formatter`, `labelLayout`, `min`/`max`, `animationDelay`,
`symbolSize`, `symbol`, `color`, `sampling`, `sort`, `renderItem`, `axisPointer.link.mapper`,
`projection.project`, `graphic.on*`). Options: classic `of object` method pointers (streamable to `.lfm`,
designtime-visible), `reference to procedure` anonymous methods (ergonomic in code, **not** streamable), or
an interface per hook. They cannot be mixed arbitrarily without an ugly API. Decide before implementing the
first one.

**Q7 — Animation: how much, given the repaint model?**
A graphic control's `Invalidate` repaints the whole parent (~14.9 ms at 900×700). Even windowed, `RenderTo`
rebuilds the entire chart every paint. Full ECharts-style animation implies 60 fps redraws. Options:
(a) accept it and rely on `TTyPaintCache`/`BeginPaintOn` for a static background layer + an animated
foreground; (b) ship only entry animations and state cross-fades (the 80 % of perceived value) and skip
continuous animation (ripples, flying trails, force-layout convergence, bar races); (c) invest in
dirty-rect/layered painting up front (a Tier 0 item, not Tier 3). Recommendation: **(b) for 3.1, with (a)
as the escape hatch**, and revisit (c) only if profiling demands it.

**Q8 — Scope statement: what does "cover all of ECharts" mean on the tin?**
The honest formulation is *"all of ECharts' charting and interaction capability, minus the browser-delivery
layer, minus WebGL, minus the map data ecosystem."* Is that acceptable as the public claim, and is the
target parity with **ECharts 6.1** (matrix, chord, axis breaks, thumbnail, `coordinateSystemUsage`) or with
**ECharts 5** (a much more stable and better-documented surface, and what most users actually know)?
Targeting 5 removes four XL items from Tier 3.

**Q9 — Sequencing: breadth-first or depth-first?**
Breadth-first (many series types, each shallow) demos better and matches "cover all of ECharts". Depth-first
(cartesian done completely — axes, stacking, dataZoom, brush, states, animation — before radial/relational)
produces something people can ship a product on sooner, and the second family is then much cheaper because
the substrate exists. Report 02's own recommended build order is depth-first. Recommendation: **depth-first
through Tier 1, breadth-first through Tier 2.**

**Q10 — Test strategy at 20× the current size.**
`TChartTest` never instantiates the control; `TChartExportTest` drives the real `RenderTo` headless. That
scales to pure geometry, but not to "does a stacked polar bar with rounded caps look right". Golden-image
tests (as `test.golden` already does for themes) are the obvious answer, but they need a decision on
tolerance, on which widgetset is authoritative, and on how many are acceptable in CI. Related: headless
tests never run the LCL align engine and never see real font metrics, so anything layout- or text-driven
needs a real-machine pass — at this scale that is a standing cost, not a one-off.
