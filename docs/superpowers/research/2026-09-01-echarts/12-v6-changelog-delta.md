# 12 — The exhaustive ECharts v5 → v6 feature delta

Research pass for `TTyAdvanceChart`. Question answered: **should the port target ECharts 5 or ECharts 6?**
This file is the *evidence base* — the delta itself. Sources are the locally cloned
`D:/Projects/echarts` (6.1.0), `D:/Projects/echarts-doc`, `D:/Projects/zrender` (6.1.0).

---

## 0. Bounding the delta

| Release | Date | changelog.md line |
|---|---|---|
| **v5.6.0** — last v5 release | 2024-12-28 | `en/changelog.md:129-130` |
| **v6.0.0** | 2025-07-30 | `en/changelog.md:74-75` |
| **v6.1.0** | 2026-05-18 | `en/changelog.md:1-2` |

`grep -n '^## ' en/changelog.md` returns **no 6.0.x patch entries** — the v6 line is exactly two
releases. The whole delta is therefore ~19 months of work in 128 changelog lines.

Package versions confirmed: `D:/Projects/echarts/package.json` → `"version": "6.1.0"`,
`"zrender": "6.1.0"`; `D:/Projects/zrender/package.json` → `"version": "6.1.0"`.
zrender ships **no changelog file** (`find . -maxdepth 1 -iname "*change*"` → empty), so zrender
deltas are only visible through the ECharts changelog's `zrender#NNNN` back-references.

### Method

1. Full read of `en/changelog.md:1-128` (both v6 sections), every bullet classified.
2. Independent machine cross-check: a parser over `en/option/**` + `en/api/**` that matches
   multi-line `{{ use: partial-version(...) }}` blocks and walks back the `#`/`##`/`###` chain —
   including the templated `#${prefix} name(Type)` headings used inside partials — to reconstruct
   the option path. **320 markers total; 81 carry a literal `version = "6.x"`; 39 more are
   templated (`${version}` / `${version|minVersion('6.0.0')}`) and were resolved by finding their
   callers; 2 carry `deprecated`.**
3. Partial-call expansion: a second scan for `{{ use: partial-XXX(... version = '6.x' ...) }}`
   found **30 caller sites** that stamp a 6.x version onto a shared partial.
4. Spot-verification against the TypeScript source for anything the docs left ambiguous.

---

## 1. v6.0.0 — classified

`en/changelog.md:74-128`. Counts by prefix: **23 `[Feature]`, 22 `[Fix]`, 5 `[Break]` sub-bullets.**

### NEW CAPABILITY (23 bullets, grouped by subsystem)

**Whole new subsystems (3)**

| # | Subsystem | Entry | Line |
|---|---|---|---|
| 1 | `series-chord` | New chord series. PR #20522 | 77 |
| 2 | `matrix` + `calendar` | New **matrix coordinate system**. *All* series and components — including other coordinate systems (`grid`, `geo`, `polar`) — can be declaratively laid out inside matrix/calendar cells. #19807, #21093, #21005, #21108 | 78 |
| 3 | `thumbnail` | New thumbnail component (minimap), initially for the `graph` series. #17471 | 84 |

**Axis / cartesian (3)**

| # | Entry | Line |
|---|---|---|
| 4 | `[axis]` **Axis break** — collapsed/skipped ranges on an axis, with zigzag break markers and click-to-expand. #19459, #20857 | 80 |
| 5 | `[cartesian]` New layout mechanism preventing axis labels *and axis names* from overflowing the canvas, and preventing name/label overlap. **Enabled by default.** #21059, #19534, #16825 | 79 |
| 6 | `[axis]` Tooltip on `angleAxis` label. #20986 | 90 |

**Coordinate-system / roaming (2)**

| # | Entry | Line |
|---|---|---|
| 7 | `[roam]` Roaming infrastructure: `roamTrigger`, `clip` on `geo`/`series-map`, cursor change over the roam area, `preserveAspect` on `geo`/`map`/`graph`, corrected percent base for `center`, better overlap behaviour | 83 |
| 8 | `[theme]` Dynamic theme registration + switching (`registerTheme` / `setTheme`). #20705 | 82 |

**Series-level (4)**

| # | Entry | Line |
|---|---|---|
| 9 | `[scatter]` Jittering (`jitter`, `jitterOverlap`, `jitterMargin`). #19941, #21067 | 81 |
| 10 | `[stack]` Reverse stack order (`stackOrder`). #20998 | 87 |
| 11 | `[sankey]` Roaming for sankey. #20321 | 88 |
| 12 | `[custom]` Reusable custom series (`echarts.registerCustomSeries`, `renderItem` as a string). #20226 | 79 |

**Custom / graphic (2)**

| # | Entry | Line |
|---|---|---|
| 13 | `[custom]` `compoundPath` in `renderItem`. #20402, #21040 | 89 |
| 14 | `[custom]` `tooltipDisabled` on returned elements. #20447 | 94 |

**Markers (3)**

| # | Entry | Line |
|---|---|---|
| 15 | `[marker]` `z` on markPoint/markLine/markArea. #21117 | 85 |
| 16 | `[marker]` `z2` on markPoint/markLine/markArea. #20782 | 86 |
| 17 | `[marker]` `relativeTo` — relative target of a marker position. #20166, #21042 | 90 |

**UI components (3)**

| # | Entry | Line |
|---|---|---|
| 18 | `[tooltip]` `displayTransition`. #20966 | 91 |
| 19 | `[visualMap]` `unboundedRange`. #21113 | 92 |
| 20 | `[legend]` `triggerEvent`. #18164, #20907 | 93 |

**Theme (1) + I18N (2)**

| # | Entry | Line |
|---|---|---|
| 21 | `[theme]` **New default theme for ECharts 6.** #20865, #21097, #21114 | 76 |
| 22 | `[i18n]` Norwegian Bokmal (nb-NO). #20792 | 95 |
| 23 | `[i18n]` Greek (EL). #21119 | 96 |

### BREAKING (5) — `en/changelog.md:122-127`

| # | Break | Escape hatch |
|---|---|---|
| B1 | Default theme changed: visual style **and default component/series positions** (e.g. legend now defaults to the *bottom*). | `echarts/theme/v5.js` (confirmed present: `D:/Projects/echarts/theme/v5.js`) |
| B2 | v5 `src/theme/light.ts` migrated to `theme/rainbow.js`. | — (rename) |
| B3 | Cartesian axis positions may shift because anti-overflow + anti-overlap are default-on. | `grid.outerBoundsMode: 'none'`, `axisLabel.nameMoveOverlap: false` |
| B4 | Percent base of `center` on `geo`, `series-map`, `series-graph`, `series-tree` corrected (was wrong). | root flag `legacyViewCoordSysCenterBase: true` — verified `src/coord/View.ts:841` |
| B5 | Label **rich styles now inherit plain label styles** (`fontStyle`, `fontWeight`, `fontSize`, `fontFamily`, `textShadow*`). | root or label-level `richInheritPlainLabel: false` — verified `src/label/labelStyle.ts:428-445,631-632` |

### DEPRECATION (1)

- `grid.containLabel` — `option/component/grid.md:41` carries
  `partial-version(version = "6.0.0", deprecated = 'See [grid.outerBoundsMode](~grid.outerBoundsMode).')`.
  Source confirms: `src/coord/cartesian/GridModel.ts:48` "@deprecated Use `grid.outerBounds` instead",
  and `:65` states `containLabel: true` is equivalent to
  `{outerBoundsMode: 'same', outerBoundsContain: 'axisLabel'}`.
  **A port should implement `outerBounds*` and skip `containLabel`.**

### DEFAULT CHANGED (v6.0.0)

| Option | v5 | v6.0.0 | Evidence |
|---|---|---|---|
| whole default theme (palette, legend position, spacing) | v5 theme | token-driven v6 theme | changelog:122; `src/visual/tokens.ts` |
| `grid.outerBoundsMode` | n/a | `'auto'` (anti-overflow on) | `src/coord/cartesian/GridModel.ts:136` |
| `grid.outerBoundsContain` | n/a | `'all'` | `GridModel.ts:138` |
| `xAxis/yAxis.nameMoveOverlap` | n/a | `true` | `option/component/axis-common.md:882` |
| `richInheritPlainLabel` | effectively `false` | `true` | changelog:127 |
| `dataZoom` moveHandler cursor | (grab-ish) | `default` | changelog:114 (#20304) |

### BUG FIX (22, aggregate)

Distribution by subsystem: label 2, dataZoom 3, tooltip 3, axis/log 2, pie 1, bar 2, sankey 1,
custom 1, heatmap 1, series 1, visualMap 1, radar 1, roam 1, svg 1, title 1.
None of these describe capability a port must reproduce — they describe correctness in code the port
will write from scratch. Two are worth reading as *specification* rather than fix:
`[label] Fix label layout margin` (#21103) and `[axis][log] incorrect rounding` (#21107, #21120).

### PERF / INTERNAL

None flagged in v6.0.0.

---

## 2. v6.1.0 — classified

`en/changelog.md:1-73`. Counts: **14 `[Feature]`, 37 `[Fix]`, 5 `[Chore]`, 3 `[Break]` sub-bullets.**

### NEW CAPABILITY (14)

| # | Subsystem | Entry | Line |
|---|---|---|---|
| 1 | axis | `dataMin` / `dataMax` for computing a nice axis extent. #20838 | 4 |
| 2 | axis | **All four axis types** (`value`/`time`/`category`/`log`) render `bar`/`pictorialBar`/`candlestick`/`boxplot` **without overflow**, including `category` + `boundaryGap:false`; new `containShape`; corresponding `clip`. #21511 | 5 |
| 3 | axis | Non-positive series values auto-excluded on a `log` axis. | 6 |
| 4 | axis | `axisLabel.formatter` receives its **index**, to work with `customValues`. #21220, #21432 | 7 |
| 5 | line | `triggerEvent` (replaces `triggerLineEvent`). #21001 | 8 |
| 6 | pie | `'tangential-noflip'` label rotation mode. #21258 | 9 |
| 7 | gauge | `progress.color` accepts `'auto'`. #21224 | 10 |
| 8 | radar | `clockwise` option. #21143 | 11 |
| 9 | candlestick + dataZoom | `candlestick.cursor`; `dataZoom-inside.cursorGrab` + `.cursorGrabbing`. #21558 | 12 |
| 10 | scatter/effectScatter/geo | `clip` now works for `scatter`/`effectScatter` **on `geo`**. | 13 |
| 11 | visualMap | `seriesTargets` — multiple series-dimension mappings. #20703 | 14 |
| 12 | matrix | `matrix.x/y.length` — headless matrix without composing a `data` array. #21191 | 15 |
| 13 | matrix | `matrix.triggerEvent` — events on matrix cells. #21390 | 16 |
| 14 | i18n | Latvian (LV). #21546 | 17 |

### BREAKING (3) — `en/changelog.md:70-73`

| # | Break |
|---|---|
| B6 | `tooltip.valueFormatter` 2nd param changed from `dataIndex` (post-dataZoom-filter) to **`rawDataIndex`** (index into the original input data). |
| B7 | `axis.startValue` **decoupled from `axis.min`**. Previously `startValue` also acted as `min`; now you must set both. (`option/component/axis-common.md:1106`) |
| B8 | `bar`/`pictorialBar`/`candlestick`/`boxplot` no longer overflow the grid rect at the edges. Restore via `axis.containShape: false`. |

### DEPRECATION (1)

- `series-line.triggerLineEvent` — `option/series/line.md:113-114`,
  `partial-version(version = "6.1.0", deprecated = "Use triggerEvent instead.")`.

### DEFAULT CHANGED (v6.1.0)

| Option | Change | Evidence |
|---|---|---|
| `axis.containShape` | new, defaults **`true`** — edge shapes get extra margin by default | `axis-common.md:919` |
| `axisLine.onZero` | value set gains `'auto'`, which is the new default | `axis-common.md:291-293` |
| `series-bar/pictorialBar.clip` semantics | now clips *partially* overflowing bars (previously all-or-nothing) | `option/partial/clip.md:19-20` |
| `series-candlestick.clip` semantics | same change | `option/partial/clip.md:28-29` |

### BUG FIX (37, aggregate)

By subsystem: axis 6, dataZoom 4, tooltip 2, axisPointer 2, lines 2, typescript 5 (sub-bullets),
map/geo 1, matrix 1, toolbox 2, pie 1, treemap 1, sunburst 1, parallel 1, candlestick 1, bar 1,
scatter 1, marker 1, labelLine 1, areaStyle 1, hoverLayer 1, progressive 1, graphic 1, svg 1,
core 1, chord 1, i18n 1. One is a **security fix**: `[Fix][lines]` tooltip XSS (#21608, line 32) —
browser-bound (HTML tooltip injection), irrelevant to a canvas/LCL port.

### PERF

`[Fix][progressive]` (91a60fc76, line 51) and `[Fix][scatter]` jitter+progressive freeze (#21436,
line 23) are the only perf-shaped entries.

### INTERNAL

`[Chore][refactor]` (lines 60-63): axis scale implementation rewritten, series data union unified,
**roaming implementation unified**. `[Chore]` x4 more (security PR template, `unpkg` entry, doc typo,
test fixture). Zero porting relevance except as a hint that v6.1's axis-scale code is the cleanest
reference implementation to read.

---

## 3. Independent cross-check: the inline version markers

Parser output: **320 `partial-version` markers**; **81 literal `6.x`** (74 at `6.0.0`, 7 at `6.1.0`);
**39 templated**; **2 `deprecated`**.

### 3a. Markers on *shared partials* and where they expand to

The 81 literal markers under-count because many sit in partial files that are included many
times. Resolution (`grep -rln "use: <partial>("`):

| Partial file:line | Option added | Expands to |
|---|---|---|
| `axis-common.md:49,57,65` | `jitter`, `jitterOverlap`, `jitterMargin` | gated by `hasJitter` → **`xAxis`, `yAxis` only** (`x-axis.md:55`, `y-axis.md:55`) |
| `axis-common.md:75-265` (15 markers) | `breaks`, `breakArea`, `breakLabelLayout` trees | gated by `hasBreakAxis` → **`xAxis`, `yAxis` only** (`x-axis.md:56`, `y-axis.md:56`) |
| `axis-common.md:886` | `nameMoveOverlap` | gated `componentType === 'xAxis' or 'yAxis'` (`axis-common.md:880`) |
| `axis-common.md:917,976,1006` | `containShape`, `dataMin`, `dataMax` | ungated → **all 7 axis-common consumers**: `xAxis`, `yAxis`, `angleAxis`, `radiusAxis`, `singleAxis`, `parallelAxis`, `parallel.parallelAxisDefault` |
| `geo-common.md:348` | `clip` | `geo.md:36` + `series/map.md:22` → **`geo.clip`, `series-map.clip`** |
| `view-coord-sys.md:128,157,188,202` | `roamTrigger`, `preserveAspect`, `preserveAspectAlign`, `preserveAspectVerticalAlign` | `geo-common.md:167`, `series/graph.md:114`, `series/sankey.md:95`, `series/tree.md:48` → **`geo`, `series-map`, `series-graph`, `series-sankey`, `series-tree`** |
| `label.md:96` | `textMargin` | gated by `${labelMargin}`; **30 caller sites** pass `labelMargin = true` |
| `stack.md:87` | `stackOrder` | `series/bar.md`, `series/line.md` |
| `mark-area.md:239`, `mark-line.md:299`, `mark-point.md:172` | `data[].z2` | via `partial/marker.md` → every series with markers |
| `mark-point.md:180` | `data[].relativeTo` | idem |
| `matrix-header.md` (8 markers) | `show`, `data`, `data.value/children/size`, `length` (6.1), `levels`, `dividerLineStyle` | `matrix.x`, `matrix.y` |
| `matrix-body-corner.md:5`, `matrix-region.md:5,19,50` | `data`, `label`, `itemStyle`, `levelSize` | `matrix.body`, `matrix.corner`, and the header cells |
| `rich-inherit-plain-label.md:5` | `richInheritPlainLabel` | via `text-style.md` → root + every text style |
| `zr-graphic.md:1102` | `compoundPath` graphic type | `graphic` component + custom `renderItem` |
| `zr-graphic.md:2094` | `tooltipDisabled` | custom-series returned elements |

### 3b. Templated markers resolved via caller args (30 caller sites, all 6.x)

`partial-coord-sys` stamped `version = '6.0.0'` at **18 sites**, each of which newly gains
`coordinateSystem` / `coordinateSystemUsage` / `coord` / `matrixIndex` / `matrixId` /
`calendarIndex` / `calendarId`:

- components: `dataZoom-slider` (`data-zoom-slider.md:245`), `geo` (`geo.md:40`), `grid`
  (`grid.md:131`), `legend` (`legend.md:54`), `parallel` (`parallel.md:23`), `polar` (`polar.md:21`),
  `radar` (`radar.md:23`), `thumbnail` (`thumbnail.md:28`), `timeline` (`timeline.md:184`),
  `title` (`title.md:137`), `toolbox` (`toolbox.md:549`), `visualMap` (`visual-map.md:431`)
- series: `chord` (`chord.md:76`), `funnel` (`funnel.md:23`), `gauge` (`gauge.md:25`),
  `sankey` (`sankey.md:39`), `sunburst` (`sunburst.md:154`), `tree` (`tree.md:38`),
  `treemap` (`treemap.md:62`)

That single flag is the biggest structural change in v6: **any component or series can be positioned
by a coordinate system**, not just by `left/top/width/height`. `coordinateSystemUsage: 'box'` places
the *whole* component in a cell; `'data'` places each datum (`coord-sys.md:144-176`).

Other templated 6.x sites: `partial-rect-layout-width-height` for `grid.outerBounds`
(`grid.md:89`); `partial-z` for the three markers (`mark-*.md`); `partial-cursor` for
`data-zoom-inside.md:81,89` and `candlestick.md:314`; `partial-clip` for `boxplot.md:264`;
`partial-trigger-event-common-content` for `legend.md:599` (6.0.0), `matrix.md:127` (6.1.0),
`line.md:82` (6.1.0).

### 3c. Prose-only version notes the markers miss

`grep -rn "v6\.0\.0|v6\.1\.0" en/option en/api | grep -v partial-version` → 10 hits, all already
covered above except: `option/series/custom.md:511` (`renderItem` as a **string** naming a
registered custom series, since 6.0.0) and `option/partial/view-coord-sys.md:91` (percentage string
for `center` re-based on the bounding rect since 6.0.0 — this is B4).

### 3d. API surface (`en/api/**`, 8 markers)

| Path | Version | What |
|---|---|---|
| `echarts.registerCustomSeries` | 6.0.0 | register a named `renderItem`, reusable across charts (`api/echarts.md:278`) |
| `echarts.registerTheme` | 6.0.0 marker | **caveat: not actually new** — existed since v3; the marker was added when dynamic theming was documented (`api/echarts.md:267`) |
| `echartsInstance.setTheme(theme, {silent})` | 6.0.0 | switch theme at runtime (`api/echarts-instance.md:243`) |
| `echartsInstance.convertToLayout(finder, coord, opt)` | 6.0.0 | convert a `matrix`/`calendar` coord to a pixel **rect** (`api/echarts-instance.md:714`) |
| `action: expandAxisBreak` | 6.0.0 | `api/action.md:166` |
| `action: collapseAxisBreak` | 6.0.0 | `api/action.md:176` |
| `action: toggleAxisBreak` | 6.0.0 | `api/action.md:186` |
| `event: axisbreakchanged` | 6.0.0 | `api/events.md:207` |

---

## 4. Consolidated table — option paths that exist in 6.x and did not exist in 5.x

Path shapes, not per-host instances (`xAxis.breaks[].start` counted once, applies to `xAxis` + `yAxis`).

### Axis (22 shapes)

| Path | Ver | Hosts | What |
|---|---|---|---|
| `<axis>.jitter` | 6.0 | x,y | random positional noise, px, to de-overlap scatter |
| `<axis>.jitterOverlap` | 6.0 | x,y | `false` = try to avoid overlap instead of pure random |
| `<axis>.jitterMargin` | 6.0 | x,y | min distance between jittered symbols |
| `<axis>.breaks` | 6.0 | x,y | array of collapsed axis ranges |
| `<axis>.breaks[].start` / `.end` | 6.0 | x,y | break range bounds (value/Date/string) |
| `<axis>.breaks[].gap` | 6.0 | x,y | pixel or % gap rendered in place of the range |
| `<axis>.breaks[].isExpanded` | 6.0 | x,y | initial expanded state |
| `<axis>.breakArea` | 6.0 | x,y | break-marker visuals container |
| `<axis>.breakArea.show` | 6.0 | x,y | draw the break marker |
| `<axis>.breakArea.itemStyle` | 6.0 | x,y | fill/stroke of the break marker |
| `<axis>.breakArea.zigzagAmplitude` | 6.0 | x,y | zigzag height (default 4) |
| `<axis>.breakArea.zigzagMinSpan` / `.zigzagMaxSpan` | 6.0 | x,y | zigzag wavelength bounds (4 / 20) |
| `<axis>.breakArea.zigzagZ` | 6.0 | x,y | z of the break marker (100) |
| `<axis>.breakArea.expandOnClick` | 6.0 | x,y | click a break to expand it |
| `<axis>.breakLabelLayout` | 6.0 | x,y | layout of labels around breaks |
| `<axis>.breakLabelLayout.moveOverlap` | 6.0 | x,y | `'auto'` — nudge overlapping break labels |
| `<axis>.nameMoveOverlap` | 6.0 | x,y | move axis *name* to avoid the labels (default `true`) |
| `<axis>.containShape` | 6.1 | 7 axes | reserve edge margin so bar/candlestick shapes never overflow |
| `<axis>.dataMin` / `.dataMax` | 6.1 | 7 axes | seed the "nice" extent computation from data bounds |
| `<axis>.axisLine.onZero: 'auto'` | 6.1 | axis-line axes | *new enum value*, now the default |

### Grid / cartesian layout (9 shapes)

| Path | Ver | What |
|---|---|---|
| `grid.outerBoundsMode` | 6.0 | `'auto'` / `'same'` / `'none'` — how the anti-overflow bound is derived |
| `grid.outerBounds` | 6.0 | explicit outer rect the grid + labels + names must fit inside |
| `grid.outerBounds.{left,top,right,bottom,width,height}` | 6.0 | 6 sub-paths |
| `grid.outerBoundsContain` | 6.0 | `'all'` / `'axisLabel'` / `'auto'` — what must fit |

### Matrix coordinate system — entirely new (~35 shapes)

`matrix`, `matrix.id`, `matrix.{left,top,right,bottom,width,height}`, `matrix.z/zlevel`,
`matrix.backgroundStyle`, `matrix.tooltip`, `matrix.triggerEvent` (6.1);
`matrix.x` and `matrix.y` each: `.show`, `.data`, `.data[].value`, `.data[].children` (nested
headers), `.data[].size`, `.data[].itemStyle`, `.data[].label`, `.length` (6.1), `.levels`,
`.levels[].itemStyle/.label`, `.levelSize`, `.dividerLineStyle`, `.itemStyle`, `.label`;
`matrix.body` and `matrix.corner` each: `.data`, `.data[].coord`, `.data[].value`,
`.data[].itemStyle`, `.data[].label`, `.itemStyle`, `.label`.
Sources: `option/component/matrix.md`, `option/partial/matrix-header.md`,
`option/partial/matrix-body-corner.md`, `option/partial/matrix-region.md`.

### Thumbnail component — entirely new (~14 shapes)

`thumbnail`, `.id`, `.show`, `.{left,top,right,bottom,width,height}`, `.z/.zlevel`, `.itemStyle`,
`.windowStyle`, `.seriesIndex`, `.seriesId` + the full coord-sys block.
Source: `option/component/thumbnail.md:5,39,51,65,71`.

### series-chord — entirely new (~150 resolved paths)

`option/series/chord.md` has 25 direct headings but pulls in `label`, `labelLine`, `itemStyle`,
`lineStyle`, `emphasis`/`blur`/`select`, `markPoint/Line/Area`, `universalTransition` etc.
`src/chart/chord/ChordSeries.ts` declares **88** option members.

### Universal coordinate-system placement (7 shapes x 19 hosts)

| Path | Ver | What |
|---|---|---|
| `<host>.coordinateSystem` | 6.0 | which coord sys lays this host out (now incl. `'matrix'`, `'calendar'`) |
| `<host>.coordinateSystemUsage` | 6.0 | `'data'` (per-datum) vs `'box'` (whole component) |
| `<host>.coord` | 6.0 | the coordinate input when usage is `'box'` |
| `<host>.matrixIndex` / `.matrixId` | 6.0 | bind to a matrix instance |
| `<host>.calendarIndex` / `.calendarId` | 6.0 | newly exposed on the 19 hosts above |

Hosts (18 stamped `version='6.0.0'` + `matrix.md` itself): `dataZoom-slider`, `geo`, `grid`,
`legend`, `parallel`, `polar`, `radar`, `thumbnail`, `timeline`, `title`, `toolbox`, `visualMap`,
`series-chord`, `series-funnel`, `series-gauge`, `series-sankey`, `series-sunburst`, `series-tree`,
`series-treemap`.

### Roaming / view coordinate systems (5 shapes x 5 hosts)

| Path | Ver | Hosts | What |
|---|---|---|---|
| `<h>.roamTrigger` | 6.0 | geo, map, graph, sankey, tree | `'selfRect'` default — where the roam gesture is captured |
| `<h>.preserveAspect` | 6.0 | idem | keep aspect ratio inside the allocated rect |
| `<h>.preserveAspectAlign` | 6.0 | idem | `'left'` / `'center'` / `'right'` |
| `<h>.preserveAspectVerticalAlign` | 6.0 | idem | `'top'` / `'middle'` / `'bottom'` |
| `geo.clip`, `series-map.clip` | 6.0 | geo, map | hide the part of the map outside the allocated rect (default `false`) |

### Markers (7 shapes)

`markPoint.z`, `markLine.z`, `markArea.z` (6.0); `markPoint.data[].z2`, `markLine.data[].z2`,
`markArea.data[].z2` (6.0); `markPoint.data[].relativeTo` (6.0).

### Label / text (2 shapes, wide reach)

`<label>.textMargin` (6.0, number|Array, applied to the label's *unrotated* local bounding rect —
`option/partial/label.md:90-98`; 30 caller sites) and `richInheritPlainLabel` (6.0, root level *and*
alongside any label style).

### Series options (13 shapes)

| Path | Ver | What |
|---|---|---|
| `series-bar.stackOrder`, `series-line.stackOrder` | 6.0 | `'seriesAsc'` default; reverse the stack |
| `series-custom.renderItem` accepts a `string` | 6.0 | name of a series registered via `registerCustomSeries` |
| `series-custom.renderItem` `api.layout(...)` | 6.0 | resolve a matrix/calendar cell rect inside `renderItem` |
| returned element `.tooltipDisabled` | 6.0 | suppress tooltip per element |
| graphic type `compoundPath` | 6.0 | union of multiple sub-elements, morph-capable |
| `series-line.triggerEvent` | 6.1 | replaces `triggerLineEvent` |
| `series-candlestick.cursor` | 6.1 | cursor over candles |
| `series-boxplot.clip` | 6.1 | boxplot gains `clip` |
| `series-pie.label.rotate: 'tangential-noflip'` | 6.1 | *new enum value* |
| `series-gauge.progress.color: 'auto'` | 6.1 | *new enum value* |
| `radar.clockwise` | 6.1 | reverse indicator direction |
| `series-scatter/effectScatter.clip` **on geo** | 6.1 | previously cartesian-only |
| `series-sankey.roam`, `.roamTrigger` | 6.0 | **present in `src/chart/sankey/SankeySeries.ts:328-329` but UNDOCUMENTED in `en/option/series/sankey.md`** |

### Components (8 shapes)

| Path | Ver | What |
|---|---|---|
| `legend.triggerEvent` | 6.0 | dispatch mouse events from legend items |
| `tooltip.displayTransition` | 6.0 | enable/disable the show/hide transition |
| `visualMap.seriesId` | 6.0 | target series by id (companion to `seriesIndex`) |
| `visualMap.continuous.unboundedRange` | 6.0 | allow the selected range to extend past min/max |
| `visualMap.seriesTargets` | 6.1 | array of series+dimension mappings — one visualMap, many series/dims |
| `dataZoom-inside.cursorGrab` / `.cursorGrabbing` | 6.1 | cursor while hovering / dragging |
| `matrix.triggerEvent` | 6.1 | cell events |
| `matrix.x.length` / `matrix.y.length` | 6.1 | headless matrix by count |

### Root-level compatibility flags (2 shapes)

`legacyViewCoordSysCenterBase` (6.0, `src/coord/View.ts:841`) and `richInheritPlainLabel`
(6.0, `src/label/labelStyle.ts:428`). Both exist only to restore v5 behaviour; **a greenfield port
should not implement either.**

### Totals for the table

- **119 distinct new option-path shapes** outside the two brand-new component/series trees
  (22 axis + 9 grid + 7 coord-sys + 5 roam + 35 matrix + 14 thumbnail + 7 marker + 2 label +
  13 series + 8 components, deduped conservatively).
- **+ ~150** more inside `series-chord`.
- ~ **270 new option paths** total in 6.x vs 5.6.0.

---

## 5. The undocumented-but-real v6 change: the token system

Not in the changelog as a bullet, but the single most porting-relevant v6 internal change:
`D:/Projects/echarts/src/visual/tokens.ts` (233 lines, **new in v6**) replaces v5's hardcoded theme
constants with a **design-token table**:

- `color.theme[]` — the 9-colour default palette (`#5070dd`, `#b6d634`, `#505372`, `#ff994d`,
  `#0ca8df`, `#ffd10a`, `#fb628b`, `#785db0`, `#3fbe95`) — `tokens.ts:106-121`
- `neutral00` to `neutral99` (21 steps) and `accent05` to `accent95` (19 steps) — `tokens.ts:124-166`
- **semantic** tokens derived from the ramps: `primary`, `secondary`, `tertiary`, `quaternary`,
  `disabled`, `border`/`borderTint`/`borderShade`, `background`/`backgroundTint`/`backgroundShade`,
  `shadow`/`shadowTint`, `axisLine`/`axisLineTint`/`axisTick`/`axisTickMinor`/`axisLabel`/
  `axisSplitLine`/`axisMinorSplitLine` — `tokens.ts:172-197`
- **`darkColor` is generated, not authored**: every token is HSL-transformed
  (l becomes `1 - l^1.5`, s becomes `s*0.9`; accents s becomes `s*0.5`, l becomes `min(1, 1.3-l)`) — `tokens.ts:199-220`
- `size` scale: `xxs:2, xs:5, s:10, m:15, l:20, xl:30, xxl:40, xxxl:50` — `tokens.ts:222-231`

This is architecturally the same shape as ty-controls' own `.tycss` tiered-token model, which makes
v6 the *easier* target to theme against, not the harder one.

---

## 6. Deprecations — the "do not implement" list

Every `deprecated =` marker in `en/option` + `en/api`, all versions (3 total):

| Path | Deprecated since | Replacement |
|---|---|---|
| `grid.containLabel` | 6.0.0 | `grid.outerBoundsMode` / `grid.outerBounds` / `grid.outerBoundsContain` (`grid.md:41,71`) |
| `series-line.triggerLineEvent` | 6.1.0 | `series-line.triggerEvent` (`line.md:113-114`) |
| `tooltip.appendToBody` | 5.5.0 | `tooltip.appendTo` (`tooltip.md:202`) — **browser-bound anyway** (DOM parent of the HTML tooltip); irrelevant to an LCL port |

Also worth skipping, though not formally deprecated: the two v5-compat root flags in section 4, and
`echarts/theme/v5.js` (a compatibility theme, not a feature).

---

## 7. What is browser-bound in this delta

| Item | Why it does not port |
|---|---|
| `tooltip.displayTransition` (6.0) | controls a **CSS transition** on the DOM tooltip; meaningless in `renderMode: 'richText'` — a Pascal port would reimplement as its own animation |
| `tooltip.appendTo` / `appendToBody` | DOM parent element |
| `[Fix][lines]` tooltip XSS (6.1, #21608) | HTML string injection into the DOM tooltip |
| `[Fix][toolbox] dataView dark mode` (6.1, #21176) | dataView is a DOM textarea overlay |
| `[Fix][svg] encodeBase64` in Worker/NodeJS/Bun (6.1, zrender#1145) | JS runtime |
| `[Fix][core] mark instance as raw in Vue` (6.1, #21293) | framework |
| `[Fix][typescript]` x5 (6.1) | build-time types |
| `[Chore] unpkg entry` (6.1) | npm packaging |
| `getSvgDataURL` SVG-support check removed (6.0, #20760) | SVG renderer |

Everything else — axis break, matrix, chord, thumbnail, jitter, roam, tokens, `outerBounds`,
`preserveAspect`, `stackOrder`, markers, `textMargin` — is **pure geometry + paint** and ports
directly onto a custom-drawn canvas.

---

## 8. Totals

| Class | v6.0.0 | v6.1.0 | Total |
|---|---|---|---|
| **NEW CAPABILITY** (changelog `[Feature]` bullets) | 23 | 14 | **37** |
| **BREAKING** (changelog `[Break]` sub-bullets) | 5 | 3 | **8** |
| **DEPRECATION** | 1 | 1 | **2** (3 counting the 5.5.0 one) |
| **DEFAULT CHANGED** | 6 | 4 | **10** |
| **BUG FIX** | 22 | 37 | **59** |
| **PERF** | 0 | 2 | **2** |
| **I18N** | 2 | 1 | **3** |
| **INTERNAL / chore** | 0 | 5 (+3 refactor) | **8** |

Marker-derived: **81 literal `6.x` version markers** + **30 partial-call sites** stamping 6.x,
resolving to ~ **270 new option paths**, of which ~ **119** live outside `matrix`/`thumbnail`/`chord`.

New top-level option keys that simply do not exist in a v5 option tree: **`matrix`**,
**`thumbnail`**, **`series.type: 'chord'`**, **`legacyViewCoordSysCenterBase`**,
**`richInheritPlainLabel`** — 5.

Demo coverage in `D:/Projects/echarts/test` (606 `.html` files): `matrix*` 9, `axis-break*` 4,
`chord` 1, `thumbnail` 1, `jitter` 1 — i.e. the v6 features are demo-backed and testable locally.

---

## 9. Bearing on the v5-vs-v6 decision

Stated plainly, from the evidence above — not as advocacy:

1. **v6 is not a rewrite of the option tree.** 8 breaking changes across 19 months, 5 of which are
   "the default theme moved" or "a wrong percent base got fixed". A v5-shaped option parser is a
   v6-shaped option parser plus ~119 paths.
2. **Three of the v6 additions are load-bearing for the stated scope.** Maps/GeoJSON are declared
   in scope, and v6 is where `geo` gained `clip`, `roamTrigger`, `preserveAspect*` and a corrected
   `center` percent base (B4) — targeting v5 means shipping the acknowledged-wrong base.
   Cartesian-first build order runs straight into `grid.outerBounds*`, which v6 made the default
   and which supersedes `containLabel`; implementing `containLabel` first is implementing a
   deprecated option.
3. **The matrix coordinate system generalises component layout.** `coordinateSystemUsage: 'box'`
   turns "where does this component go" from 18 bespoke `left/top/width/height` implementations into
   one. Retrofitting that later is an option-tree-wide change; adopting it up front is free.
4. **Token-based theming (`src/visual/tokens.ts`) is v6-only** and mirrors the project's existing
   `.tycss` tiered-token architecture.
5. The costs of v6 are the two brand-new trees (`matrix` ~35 paths, `chord` ~150 paths) and
   `thumbnail` (~14) — all three are *optional leaves* under a depth-first cartesian-first plan and
   can be deferred without contaminating anything else.
6. **Nothing in the v6 delta is browser-bound except the DOM tooltip and build/type plumbing.**
