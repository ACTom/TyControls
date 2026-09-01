# 13 — The genuinely NEW subsystems in ECharts 6

Scope: things that exist in ECharts 6.0.0 / 6.1.0 and have **no v5 counterpart at all**. Not
"improved", not "renamed", not "new default" — new machinery. Every claim below is anchored to a
file:line in `D:/Projects/echarts` (6.1.0), `D:/Projects/echarts-doc`, or a changelog entry.

Companion reports 01–08 surveyed the whole of ECharts; 10 is the gap matrix; 11 is the critique.
This report only goes deep on the v6-only additions, because the open decision is **target v5 or v6**.

---

## 0. How large is "v6" as a delta?

Counted from the authoritative sources, not impression:

| Measure | Count | Source |
|---|---|---|
| `[Feature]` lines in the v6.0.0 changelog | 21 | `en/changelog.md:106-127` |
| `[Feature]` lines in the v6.1.0 changelog | 13 | `en/changelog.md:4-17` |
| `[Break]` bullets, v6.0.0 vs v5.6.0 | 5 | `en/changelog.md:150-155` |
| `[Break]` bullets, v6.1.0 vs v6.0.0 | 3 | `en/changelog.md:100-103` |
| `partial-version(version = "6.0.0")` markers in `en/option/**` | 66 | grep |
| `partial-version(version = "6.1.0")` markers in `en/option/**` | 10 | grep |
| v6 markers in `en/api/**` | 8 | grep |
| Doc file with the most v6 markers | `en/option/component/axis-common.md` (19) | grep |
| Deprecation markers in the whole of `en/option/**` | 5 | grep |

Two readings matter. **(1) v6 is additive, not a rewrite** — five deprecation markers total, and the
only real one in the option tree is `grid.containLabel` → `grid.outerBoundsMode`
(`en/option/component/grid.md:41`). **(2) The additions cluster** — 19 of the 66 v6.0 option markers
are on one page (axis-common: breaks + jitter), 15 more are matrix (`matrix.md` 7,
`matrix-header.md` 8), 5 thumbnail, 5 grid (`outerBounds`). The delta is *four or five subsystems*,
not 66 scattered options.

Source-line footprint of the new subsystems (`wc -l`, whole directories):

| Subsystem | Lines | Files |
|---|---|---|
| matrix coord sys + component | **2,677** | `src/coord/matrix/*` (2,219) + `src/component/matrix/*` (458) |
| axis breaks (core only) | **1,803** | `scale/break.ts`, `scale/breakImpl.ts`, `component/axis/axisBreakHelper{,Impl}.ts`, `axisAction.ts`, `installBreak.ts` |
| chord series | **1,200** | `src/chart/chord/*` (6 files) |
| thumbnail | **706** | `src/component/thumbnail/*` + `component/helper/thumbnailBridge.ts` |
| jitter | **289** | `src/util/jitter.ts` (184) + `src/chart/scatter/jitterLayout.ts` (105) |
| `registerCustomSeries` | **30** | `src/chart/custom/customSeriesRegister.ts` |
| `coordinateSystemUsage: 'box'` | ~250 (diffuse) | `src/core/CoordinateSystem.ts:109-350`, `src/util/layout.ts:460-525` |

Axis breaks understate badly at 1,803: the feature is **also** threaded through the scale layer —
`grep -c "reak"` gives 26 hits in `scale/scaleMapper.ts`, 24 in `scale/Interval.ts`, 36 in
`scale/Time.ts`, 21 in `scale/Log.ts`, 10 in `scale/minorTicks.ts`, 25 in `coord/axisHelper.ts`,
36 in `component/axis/AxisBuilder.ts`. Breaks are not a component bolted on; they are a change to
what "a scale" *is*.

---

## 1. `chord` series

**Files:** `src/chart/chord/{ChordSeries,ChordView,ChordPiece,ChordEdge,chordLayout,install}.ts`
(1,200 lines). **Doc:** `en/option/series/chord.md` (251 lines).
**Changelog:** "New chord series" — `en/changelog.md:107`.

### What it is on screen

A ring of arc segments (one per node) around a common centre, with the interior filled by **ribbons**
— closed shapes bounded by two arcs on the ring and two Bézier curves through the middle. Each ribbon
is one edge; its *width where it lands on each node's arc* is proportional to that edge's value. A
node's arc length is proportional to the sum of the values of edges touching it.

Default geometry (`ChordSeries.ts:307-317`): `center: ['50%','50%']`, `radius: ['70%','80%']` — so the
node arcs are a thin annulus at 70–80 % of the box, and the ribbons live inside `r0`. `startAngle: 90`,
`clockwise: true`, `padAngle: 3` (degrees of gap between node arcs), `minAngle: 0`,
`itemStyle.borderRadius: [0,0,5,5]` (rounded on the inner edge of each node sector).
`lineStyle: {width: 0, color: 'source', opacity: 0.2}` — ribbons are filled, unstroked, translucent,
tinted by the source node.

### How it differs from `graph` circular and from `sankey`

| | `chord` | `graph` `layout:'circular'` | `sankey` |
|---|---|---|---|
| Node glyph | arc **sector**, *length encodes value* | symbol of fixed or value-mapped size | rect in a layered column |
| Edge glyph | filled **ribbon**, width varies per end | 1-D curved line, `curveness` only | band between two columns |
| Value semantics | node value = Σ of its edges (or `data[i].value` if larger, `chordLayout.ts:87-95`) | node value independent of edges | flow conservation across layers |
| Topology | any graph, incl. cycles | any graph | DAG only |

The distinguishing feature is that **an edge occupies angular space on both of its endpoints' arcs**
— which is why `chordLayout` allocates a sub-range of each node's arc to each incident edge, in
order, accumulating (`chordLayout.ts:196-266`, the `edgeAccAngle[]` array).

### The layout algorithm (`chordLayout.ts`, 272 lines)

Not just "normalise to 2π". In order: `getCircleLayout()` → `{cx,cy,r,r0}` (`:48-51`); accumulate
`nodeValues[i]` = Σ over incident edges (`:70-81`), with an `allZero` mode (`:66`) that gives every
link value 1 if all values are 0 so the diagram still renders; allow `data[i].value` to override
*upward*, `nodeValues[i] = max(dataValue, Σedges)` (`:86-89`), so a node can be larger than its edges
justify; guard degenerate input by shrinking `padAngle` if `padAngle·n ≥ totalAngle` and then
`minAngle` if `(padAngle+minAngle)·n ≥ totalAngle` (`:104-109`); compute
`unitAngle = (totalAngle − padAngle·n·dir) / nodeValueSum` (`:110-111`).

Then the part that will bite a porter: **`minAngle` redistribution** (`:113-198`). Nodes below
`minAngle` are inflated to it and the angle must be *borrowed* from nodes above it. The code sums
`totalDeficit` and `totalSurplus`, then either scales all surplus nodes by
`totalDeficit/totalSurplus`, or — if proportional borrowing would push some surplus node *below*
`minAngle` — flips to a `surplusAsMuchAsPossible` greedy mode (`:150-167`) draining `restDeficit`
node by node (`:170-198`). Each node stores `ratio` = post/pre span, which the edge pass applies so
ribbons stay inside the adjusted arc. Finally a node pass assigns
`{cx,cy,r0,r,startAngle,endAngle,clockwise}` (`:200-213`) and an edge pass slices `spanAngle·ratio`
off each endpoint's running cursor into four points + four angles (`:215-266`).

**Ribbon path** (`ChordEdge.ts:73-107`): `moveTo(s1)` → `arc(cx,cy,r,sStart,sEnd)` →
`bezierCurveTo` with **both control points pulled 70 % toward the centre** (`ratio = 0.7`, `:77`) →
`arc(cx,cy,r,tStart,tEnd)` → `bezierCurveTo` back → `closePath`. That is the whole ribbon; it needs
only `arc` and `cubicTo` on the path type.

### Full option surface

- **Layout:** `center`, `radius`, `left/top/right/bottom/width/height`, `clockwise`, `startAngle`,
  `endAngle` (`'auto'` allowed by the type but the layout hardcodes `start+2π`, `chordLayout.ts:57`),
  `padAngle`, `minAngle`.
- **Data:** `data`/`nodes` (alias) `{id,name,value,itemStyle,label,emphasis,blur,select}`;
  `edges`/`links` (alias) `{source,target,value,lineStyle,label,emphasis,blur,select}`.
- **Style:** `itemStyle` (+`borderRadius` accepting `(number|string)[]|number|string`), `lineStyle`
  with `color: 'source'|'target'|'gradient'` and `curveness`, `label` (`position:
  'inside'|'outside'`, `distance`), `edgeLabel`.
- **States:** `emphasis` (`focus`, default **`'adjacency'`**, plus `scale`), `blur`, `select`.
  `'adjacency'` is chord-specific (`ChordSeries.ts:52-72`): on a node it lights the node, its edges
  and their far ends; on an edge, the edge, its two nodes and everything adjacent to those.
- **Coord:** `coordinateSystem:'none'` by default; `calendar`/`matrix`/`none` allowed
  (`chord.md:74-81`) — chord participates in `coordinateSystemUsage:'box'` (§3).

**Size: M.** **Depends on:** a graph/edge data model (`createGraphFromNodeEdge`, shared with `graph`
and `sankey`), an arc sector with per-corner radius, a closed path supporting arcs + cubics, and
emphasis-focus propagation. Nothing v6-specific. The layout is ~270 lines of arithmetic with no
convergence loop — the cheapest part.

---

## 2. `matrix` coordinate system — the big one

**Files:** `src/coord/matrix/{Matrix,MatrixModel,MatrixDim,MatrixBodyCorner,matrixCoordHelper,prepareCustom}.ts`
(2,219 lines) + `src/component/matrix/{MatrixView,install}.ts` (458). **Doc:**
`en/option/component/matrix.md` (150) + partials `matrix-header.md`, `matrix-body-corner.md`,
`matrix-region.md`. **Changelog:** `en/changelog.md:108`. Registered like any other coord sys:
`registers.registerCoordinateSystem('matrix', Matrix)` (`src/component/matrix/install.ts:28`).

### What it is

**A table used as a coordinate system.** Not a chart type — a `CoordinateSystem` +
`CoordinateSystemMaster` (`Matrix.ts:55`) that implements `dataToPoint`, `dataToLayout`,
`pointToData`, `containPoint`, exactly like `cartesian2d` does. The "axes" are two *trees of header
cells*; the "coordinates" are integer row/column locators; and the thing it hands back is a **rect**,
not a point.

It also *draws itself* — the header cells, the body cell borders, the corner block, the outer border
and two divider lines are all rendered by `MatrixView` (`z: -50` by default, `MatrixModel.ts:293`,
deliberately under everything else).

Three distinct uses, all documented on `matrix.md:9-11`: **(1) cell-per-datum** —
`series.heatmap/scatter/custom` with `coordinateSystem:'matrix'`, each `series.data[i]` in one cell
(correlation matrix, confusion matrix); **(2) chart-per-cell** — a whole `grid`+`xAxis`+`yAxis`+
`line` inside one cell via `coordinateSystemUsage:'box'` (§3) — the sparkline table / CSS-grid case;
**(3) pure table** — no series, just `matrix.body.data[i].value` text (`matrix_application2.html`
builds a spreadsheet with selection and inline editing this way).

### The layout model, precisely

The source comment at `MatrixModel.ts:57-113` is the normative spec; the doc reproduces it at
`matrix-body-corner.md:29-45`. Given

```
matrix: { x: [{value:'Xa0', children:['Xb0','Xb1']}, 'Xa1'],
          y: [{value:'Ya0', children:['Yb0','Yb1']}] }
```

the surface is divided into four regions:

```
 -----------------------------------------
 |       |       |     Xa0       |       |
 |-------+-------+---------------|  Xa1  |   <- x header (2 levels)
 |cornerQ|cornerP|  Xb0  |  Xb1  |       |
 |-------+-------+-------+-------+--------
 |       |  Yb0  | bodyR | bodyS |       |
 |  Ya0  |-------+-------+---------------|
 |       |  Yb1  |       |     bodyT     |
 |---------------|------------------------
   ^ y header (2 levels)      ^ body
```

- **`matrix.x` / `matrix.y`** are the two headers, each a *forest* — `data[i]` may carry `children`
  recursively; forest depth = header levels; leaves = columns (x) or rows (y); a non-leaf spans all
  of its leaves. **body** = the rect right/below both headers; **corner** = the block above-left.
- **`MatrixXYLocator`** (`MatrixDim.ts:64`): a signed integer, origin `(0,0)` at the **top-left body
  cell**. Non-negative → body, right/down; negative → header/corner, left/up. So `[-2,-1]` is
  `cornerQ`, `[-2,'Ya0']` the centre of the `Ya0` header cell.
- **`OrdinalNumber`**: leaves numbered first (0…n−1), then non-leaves — here
  `'Xb0','Xb1','Xa1','Xa0'` → `0,1,2,3`. For a leaf, locator == ordinal; for a non-leaf they differ,
  the one genuinely confusing part of the model.
- A coordinate is a **pair of `MatrixCoordRangeOption`**, each a locator int, an ordinal int, the
  header's `value` string, or a **2-element array** meaning a range (`MatrixModel.ts:118-136`):
  `[[2,5],8]` is a 4×1 block, `['aNonLeaf',8]` the block under a non-leaf header, `[2,null]` a whole
  column (only with `coordClamp:true`).

`dataToLayout()` (`Matrix.ts:181-229`) takes such a pair and returns `{rect, matrixXYLocatorRange}`;
`dataToPoint()` (`:152-164`) is `dataToLayout` then the rect's centre; `pointToData()` (`:250-280`)
inverts, returning negative locators for header/corner hits. `Matrix.ts:176-180` explains why
`dataToLayout` refuses a `contentRect`: a range coord can span multiple *unmerged* cells, so there is
no single padding/border to subtract.

### Cell sizing — the rule (`matrix-region.md:57-108`)

Two orthogonal knobs, both accepting *unspecified* | `number` (px) | `'33%'` (of **the matrix rect**,
not the canvas). **`size`** on `matrix.x/y.data[i].size` — for `x` a column width, for `y` a row
height; only meaningful on leaves (`MatrixModel.ts:174-177`). **`levelSize`** on `matrix.levelSize`
(all levels) or `matrix.x/y.levels[i].levelSize` (one level) — for `x` the *height* of a header row,
for `y` the *width* of a header column; `levels[0]` is the topmost (x) / leftmost (y), entries may be
`null` for default (`levels: [null, null, {levelSize: 10}]`).

Anything unspecified is **evenly distributed** over the remainder. `_resize()` (`Matrix.ts:125-142`)
runs `layOutUnitsOnDimension` per dim (specified sizes first, `layOutUnspecified` shares the rest),
then `layOutDimCellsRestInfoByUnit` derives each header cell's rect from its leaf span, then
`layOutBodyCornerCellMerge` resolves merged blocks.

### The rest of the option surface

**`matrix.x/y.length` (v6.1)** — `matrix-header.md:79-85`, changelog `:15`. If `data` is absent but
`length` is given, `MatrixDim`'s constructor synthesises `Array(length)` of `null`
(`MatrixDim.ts:165-172`). Purpose: a **headless matrix** — `show:false` + `length:5` is a 5-column
layout container with no header text. Ignored whenever `data` is present. Third path: if *neither* is
given, `_initBySeriesData()` (`MatrixDim.ts:301`) **collects categories from `series.data` /
`dataset.source`**, honouring `series.encode` (`matrix-header.md:47-73`) — a real data-pipeline
dependency, not a layout detail.

**`triggerEvent` (v6.1)** — `matrix.md:135-150`, changelog `:16`, impl `MatrixView.ts:370-395`,
default `false`. When true, cells become non-silent and emit `{componentType:'matrix',
componentIndex, matrixIndex, targetType:'x'|'y'|'body'|'corner', name, value, coord}`. Note
`MatrixView.ts:373-386`: silence is *auto-decided* from `triggerEvent` **and** whether a tooltip is
configured, and label-level `silent` still overrides.

**`backgroundStyle` / `borderZ2` / dividers** — `backgroundStyle` (`matrix.md:95-107`) styles the
whole matrix rect and is explicitly *not* inherited by x/y/body/corner (`MatrixModel.ts:43`); default
`{color:'none', borderColor: tokens.color.axisLine, borderWidth:1}`. It is drawn as **two elements**
(`MatrixView.ts:92-108`) — fill-only at `Z2_BACKGROUND` (below everything), stroke-only at
`outerBorderZ2` (above normal cell borders) — because users overstroke individual cells to highlight
them and those must still win; hence `borderZ2` as an escape hatch (`matrix.md:130-133`).
**Divider** is exactly two lines (`MatrixView.ts:110-137`): one horizontal below the x header, one
vertical right of the y header, styled by `matrix.x/y.dividerLineStyle` (default `{width:1, color:
tokens.color.border}`) at `outerBorderZ2 − 1`. Header/body separator, nothing more.

**Cell merging** — `matrix.body/corner.data[i]` with `coord: [[xmin,xmax],[ymin,ymax]]` and
`mergeCells: true` (`matrix-body-corner.md:96-100`). `MatrixBodyCorner` (292 lines) keeps a sparse
`_cellMap` plus `_cellMergeOwnerList`; each cell records `inSpanOf` (the top-left cell of its area),
merge owners additionally carry `span`, `locatorRange`, `spanRect` (`MatrixBodyCorner.ts:48-71`).
`dataToLayout` calls `expandRangeByCellMerge` on both body and corner (`Matrix.ts:219-227`) so
addressing *any* cell of a merged block returns the whole block, unless `ignoreMergeCells:true`.
Overlapping merge declarations are silently ignored (`test/matrix2.html:104,114`).

**Which series live on it** — being a full coord sys it supports `custom` via `prepareCustom.ts`,
exposing `api.coord()` → point and **`api.layout()`** → rect (`:36-45`). `coordinateSystem:'matrix'`
appears **70 times** in `test/*.html`. Per the compat table (`coord-sys.md:100-140`) the *data*-usage
series on matrix are `scatter`, `effectScatter`, `heatmap`, `graph`, `custom`; everything else that
lists ✅ gets there via `coordinateSystemUsage:'box'` (§3).

### Machinery a native port needs

Two header forests with span/level/ordinal/locator bookkeeping; a size solver mixing fixed, percent
and even-distribution over two axes; a sparse merged-cell map; a signed-locator ↔ ordinal ↔ raw-value
resolver accepting five input shapes; forward and inverse hit-testing across four regions; a renderer
for header + body + corner + outer border + 2 dividers with four-way z-order; per-cell label
truncation; category auto-collection from series data; plus the `custom` bridge for confusion
matrices.

**Size: XL** — the single largest new thing in v6 (~2.7 kloc) and *foundational*: the box feature
(§3), thumbnail placement and the whole small-multiples story hang off it.
**Depends on:** an ordinal/category scale, a box-layout (`left/top/right/bottom/width/height`) engine,
per-cell text truncation, and — for use 2 — §3.

---

## 3. `coordinateSystemUsage: 'box'` — nested coordinate systems

**Source:** `src/core/CoordinateSystem.ts:109-350` (the decision logic and injection),
`src/util/layout.ts:460-525` (`createBoxLayoutReference`).
**Doc:** `en/option/partial/coord-sys.md:144-190`, plus the ✅/❌ table at `:100-140`.
**Changelog:** part of the matrix entry, `en/changelog.md:108` — "all series and components
(including other coordinate systems, such as grid, geo, polar) are supported to be declaratively
laid out in the cells of matrix and calendar".

### The idea

Every model naming a `coordinateSystem` is classified into one of three *usage kinds*
(`CoordinateSystem.ts:177-183`): `COORD_SYS_USAGE_KIND_DATA` (each `series.data[i]` is positioned by
the coord sys — v5 behaviour), `COORD_SYS_USAGE_KIND_BOX` (**the whole series/component's bounding
rect or anchor point is positioned by the coord sys**), or `..._NONE`. Defaults (`:200-203`): a
**series** → `'data'` (backward compatible); a **non-series component** → `'box'`, because `'data'`
is meaningless for it.

The mechanism is short. `createBoxLayoutReference` (`layout.ts:476-525`) asks the host coord sys for
a rect via `dataToLayout(coord)`, falls back to a point via `dataToPoint(coord)` if the host only
offers that, and falls back to the viewport rect if there is no host. The returned rect is the
*container* against which the guest's own `left/top/right/bottom/width/height` are resolved. That is
the whole feature — and **it is cheap only if `dataToLayout`-returns-a-rect is in the
coordinate-system interface from day one**, exactly what report 04 flagged.

### What can host, what can be hosted

**For non-series components there are exactly two hosts, hardcoded:** `CoordinateSystem.ts:96` —
`if (type === 'matrix' || type === 'calendar')`, with the comment "FIXME: hardcode". So `grid`,
`polar`, `geo`, `legend`, `dataZoom`, `visualMap`, `toolbox`, `timeline`, `title` and `thumbnail`
can be placed **only** inside matrix or calendar cells. **For series** the compat table
(`coord-sys.md:100-140`) additionally allows `grid`(cartesian2d), `polar`, `geo`, `singleAxis` —
that is how "pie on a map" works.

**Series defaulting to `'box'`** (5 hits for `coordinateSystemUsage: 'box'` in `src/`): `pie`
(`PieSeries.ts:256`), `funnel` (`:156`), `sankey` (`:310`), `tree` (`:257`), `treemap` (`:252`);
plus `gauge`, `sunburst`, `chord` per the doc table. **Series supporting BOTH kinds at once: only
`graph` and `map`** (`CoordinateSystem.ts:239-244`, cases enumerated at `:255-280`). `graph` on
matrix with `usage:'data'` puts *each node* in a cell; with `usage:'box'` it creates an **internal
`view` coord sys** and puts the whole graph in one cell. `map` on matrix works only in `'box'` mode,
creating an internal `geo`.

### What it looks like in practice

`test/matrix_application2.html:712-739` — the sparkline-per-cell pattern. Per cell you register
**one `grid` + one `xAxis` + one `yAxis` + one `series`**, wired by explicit ids:

```js
grid:   { id: gridId, coordinateSystem: 'matrix', coord: <cellCoord>,
          top: 2, left: 2, right: 2, bottom: 2, containLabel: true },
xAxis:  { id: xAxisId, gridId, data: [...] },
yAxis:  { id: yAxisId, gridId },
series: { type: 'line', xAxisId, yAxisId, data: [...] }
```

Note that `top/left/right/bottom` here are **insets inside the cell**, not page coordinates.

`test/matrix3.html:569-590` puts a whole roamable `graph` in one cell (`{type:'graph',
coordinateSystem:'matrix', coordinateSystemUsage:'box', matrixId:'matrix1', coord:['T','A1'],
roam:true}`); `:618-640` puts a `map` in one cell with `roam`, `roamTrigger:'global'`, `clip:true`,
`preserveAspect:true` and per-cell insets (`preserveAspect` and `roamTrigger` are themselves v6
additions, `en/changelog.md:114`). `test/calendar-other-coord-sys.html:393,442,545` does the same
against a calendar — a chart per day.

`coordinateSystemUsage` appears in the whole 606-file test suite only **7 times** — the default is
almost always right; you only write it for `graph`/`map`, where both kinds are legal.

### Machinery a native port needs

Small *if* designed in: `ICoordSystem` needs `DataToLayout(coord): TRect` alongside `DataToPoint`,
components need a `CoordSys`/`CoordSysUsage`/`Coord` triple in their option schema, and the
box-layout resolver must take an arbitrary container rect instead of assuming the canvas. The
expensive part is not the mechanism but the **plurality**: N cells means N grids, N axis pairs, N
series — the model tree, the id/index finder and the render loop must all scale to hundreds of
component instances without going quadratic.

**Size: S** as a mechanism, **L** as a consequence. **Depends on:** matrix and/or calendar existing
first (nothing else can host a non-series box), and a box-layout resolver parameterised by container
rect.

---

## 4. `thumbnail` component

**Files:** `src/component/thumbnail/{ThumbnailModel,ThumbnailView,ThumbnailBridgeImpl,install}.ts`
(573) + `src/component/helper/thumbnailBridge.ts`. **Doc:** `en/option/component/thumbnail.md`.
**Changelog:** `en/changelog.md:115`.

A **minimap**. It renders a scaled-down copy of a roamable series' element group in a corner box,
overlaid with a translucent rectangle showing the current viewport, and it is itself a roam
controller — dragging in the thumbnail pans the main view.

**Report 11's claim is confirmed: graph-only.** `ThumbnailModel.ts:145` —
`if (series.subType !== 'graph') { series = null; error('series.… is not supported in thumbnail.') }`,
and the source comment at `:37-38` says "TODO: currently only graph supports thumbnail." The doc
agrees (`thumbnail.md:9`: "Currently it only supports series.graph"). `ThumbnailModel.dependencies`
lists `['series','geo']` (`:67`) and the comment at `:32-34` explains the intent — a single thumbnail
serving geo and its related series — but geo is not wired.

Option surface is tiny: `show`, `left/top/right/bottom/width/height` (defaults `right:1, bottom:1,
width:'25%', height:'25%'`), `itemStyle` (frame), `windowStyle` (viewport rect, default
`opacity: 0.3`), `seriesIndex`/`seriesId`, plus `coordinateSystem`/`coordinateSystemUsage`/`coord`
so the thumbnail itself can sit in a matrix or calendar cell.

Mechanically it is a **bridge**: the graph view on render calls
`bridge.renderContent({group, targetTrans, viewportRect, roamType, …})`
(`ThumbnailBridgeImpl.ts:55-75`); the thumbnail view re-parents/clips that group, computes a scale
and adds a `Rect` for the window (`ThumbnailView.ts:133-186`); on roam it calls only `updateWindow`
(`:188-220`). A `renderVersion` counter exists because the graph's **force layout renders
asynchronously** and the two views' render order is not guaranteed (`ThumbnailBridgeImpl.ts:35-38`).

Architecturally it works by **re-rendering the same retained element group at a different
transform** — nearly free in a retained scene graph, but in an immediate-mode custom-drawn control
it means either re-running the whole graph draw into a second transform or blitting a scaled bitmap.

**Size: S** (given a retained group + a roam controller). **Depends on:** graph series with roam;
a roam controller; a group-with-transform primitive.

---

## 5. Axis breaks

**Files:** `src/scale/break.ts` (178, façade only — its header forbids importing the impl),
`breakImpl.ts` (785), `component/axis/axisBreakHelper.ts` (91), `axisBreakHelperImpl.ts` (572),
`axisAction.ts` (147), `installBreak.ts` (30). **Doc:** `en/option/component/axis-common.md:73-270`.
**Changelog:** `en/changelog.md:112`. **Opt-in**, not default — `export {installAxisBreak as
AxisBreak}` in `src/export/features.ts:24`; tree-shaken builds must `echarts.use([AxisBreak])`
(`axis-common.md:97-125`).

### What it is

A **discontinuous axis**: one or more `[start, end]` value ranges collapse to a small visual `gap`,
so outliers or dead zones don't dominate the scale. On screen the collapsed range is a band across
the plot with a **torn-paper zigzag** on each side. The doc is unusually prescriptive about when to
use it (`axis-common.md:86-91`). **Not available on category axes** (`:93`), and documented only on
`xAxis`/`yAxis` (`hasBreakAxis = true` appears in exactly two files, `x-axis.md:56`, `y-axis.md:56`),
though the action payload also accepts `singleAxisIndex` (`axisAction.ts:38-40`).

### Option surface

- `axis.breaks[]` = `{start, end, gap, isExpanded}`. `start`/`end` are in the **data domain**, not
  pixels (`axis-common.md:134-160`). `gap` is either `'5%'` (fraction of axis length — recommended,
  stable under `min`/`max`/dataZoom changes) or a **number in data units**, remapping `[start,end]`
  to `[start, start+gap]` (`:163-175`); mixing the two forms within one array is disallowed.
  `isExpanded` (default `false`) means the break is currently opened back up.
- `axis.breakArea` = `show` (true), `itemStyle` (default `#fff` fill, `#b7b9be` dashed `[3,3]`
  border, opacity 0.6), `zigzagAmplitude` (4 px; `0` degenerates to a straight line),
  `zigzagMinSpan` (4), `zigzagMaxSpan` (20), `zigzagZ` (100), `expandOnClick` (**true**).
- `axis.breakLabelLayout.moveOverlap` — `'auto'|true|false`, separates break-boundary labels.
- `axisLabel.formatter` gains `extra.break = {type:'start'|'end', start, end}` for the two labels
  sitting on a break boundary (`axis-common.md:1255-1275`).

**Zigzag** (`axisBreakHelperImpl.ts:196-300`): tooth size is `random()·(maxSpan−minSpan) + minSpan`,
randomised to simulate torn paper, with the draws **cached per break** in
`CacheBreakVisual.zigzagRandomList` (`:59-90`) so teeth don't reshuffle on re-render. Amplitude
alternates ±`zigzagAmplitude` perpendicular to the axis, with sub-pixel snapping (`:216`) and
first/last-point clamping so it meets the plot edges cleanly.

**Interaction:** three registered actions (`axisAction.ts:121-124`) — `expandAxisBreak`,
`collapseAxisBreak`, `toggleAxisBreak` — each carrying
`{x/y/singleAxisIndex|Id|Name, breaks:[{start,end}]}` and firing one refined `axisbreakchanged` event
with old and new `isExpanded` per break (`:56-75`). `expandOnClick` wires a click on the break group
(`axisBreakHelperImpl.ts:175-188`; group is `silent` when false, `:188`) and on the break label
(`AxisBuilder.ts:1596`). **There is no bespoke expand animation** — the actions declare
`update: 'update'` (`axisAction.ts:114-120`), so the smooth open/close is just the standard series
transition reacting to a changed scale. You get it free if you have generic property transitions,
and not at all otherwise.

### Why this is not a component

Breaks live in the **scale**. `Scale` gained `brk: BreakScaleMapper` (`scale/break.ts:39-52`) with
`breaks`, `hasBreaks()`, `calcNiceTickMultiple()`, and every scale had to learn about them: 24
`break` references in `Interval.ts`, 36 in `Time.ts`, 21 in `Log.ts`, 26 in `scaleMapper.ts`, 10 in
`minorTicks.ts`. Tick generation gained `addBreaksToTicks` and `pruneTicksByBreak` with a
three-valued policy `'auto'|'no'|'preserve_extent_bound'` (`break.ts:65-82`) — because a tick on the
extent boundary inside a break must be kept for splitLine but dropped for the label. `Log` needs the
gap logarithmically transformed (`ParsedAxisBreak.gapParsed`, `types.ts:592-599`). The whole thing
sits behind a register-an-impl indirection (`registerScaleBreakHelperImpl`, `break.ts:141-147`)
purely to keep it out of the default bundle.

**Size: L.** **Depends on:** a scale abstraction you are willing to make non-monotonic-mapping;
tick generation you can intercept; a dashed/patterned fill; the action/event dispatch loop. This is
the one v6 feature you cannot bolt on later without touching your scale core — if you build a v5-
shaped scale and add breaks in year two, you rewrite `Interval`, `Log` and `Time`.

---

## 6. Jitter

**Files:** `src/util/jitter.ts` (184, generic), `src/chart/scatter/jitterLayout.ts` (105).
**Doc:** `en/option/component/axis-common.md:47-68`. **Changelog:** `en/changelog.md:111`.
**Opt-in:** `export {installScatterJitter as ScatterJitter}` — `src/export/features.ts:26`.

Displaces overlapping points perpendicular to the category axis so a strip/beeswarm plot reads.
Three axis-level options: `jitter` (px, default 0 = off), `jitterOverlap` (default `true`),
`jitterMargin` (default 2 px, only meaningful when `jitterOverlap:false`).

Two algorithms (`jitter.ts:88-183`). **`jitterOverlap: true`** is pure random —
`coord + (random()−0.5)·jitter`, clamped so total spread ≤ `bandWidth − 2·radius` on a category axis,
unclamped on a single axis (`:88-102`). **`jitterOverlap: false`** is a **greedy circle-packing**:
it keeps a per-axis list of placed `{fixedCoord, floatCoord, r}` (`inner(fixedAxis).items`), tries
both ±1 directions for each new point, scans all placed items for overlap (`d² < (r₁+r₂+margin)²`),
pushes to the required offset and **restarts the scan** (`i = -1`, `:174-177`), picks the smaller
displacement, and gives up to random jitter if the result exceeds `jitter/2` or half the band
(`:126-132`). That is **O(n²) worst case** and the restart makes it worse — v6.1 had to fix it for
progressive rendering (`en/changelog.md:24`).

**Confirms report 11's finding #12: scatter only.** `needFixJitter` (`jitter.ts:31-42`) requires
`cartesian2d` with an **ordinal** base axis, or `single`; `jitterLayout.ts` declares
`seriesType: 'scatter'` (`:32`) and is the sole registration. `src/util/jitter.ts` is written
generically but has exactly one caller.

**Size: S.** **Depends on:** scatter with a category or single axis; symbol size known at layout time.
The greedy path also needs per-axis layout state that survives across the data pass.

---

## 7. `registerCustomSeries` + `itemPayload`

**Doc:** `en/api/echarts.md:276-320` (`partial-version(version: '6.0.0')`).
**Source:** `src/chart/custom/customSeriesRegister.ts` (30 lines — a `{[type]: renderItem}` map with
a setter and a getter), `src/core/echarts.ts:3211` (the public export),
`src/chart/custom/CustomView.ts:633-643` (resolution), `:689` (`itemPayload` injection),
`src/chart/custom/CustomSeries.ts:351,378-379` (types).
**Changelog:** `en/changelog.md:109` — "Support reusable custom series."

### The shape

```js
echarts.registerCustomSeries('bubble', (params, api) => ({ type:'circle', shape:{…},
    style:{ opacity: params.itemPayload.opacity() || 1 } }));

series: { type: 'custom', renderItem: 'bubble',
          itemPayload: { scale: 2, opacity: () => Math.random()*0.5+0.5 },
          data: [[11,22,20], …] }
```

`series.renderItem` may now be a **string naming a registered renderer** instead of a closure.
`CustomView.makeRenderItem` (`:633-643`) checks `typeof renderItem === 'string'`, looks it up, and
warns in dev if missing. `series.itemPayload` (a plain `Dictionary<unknown>`) is passed through into
`params.itemPayload` (`:689`, defaulting to `{}`) — it is how the option tree parameterises a
renderer it cannot inline.

### Why this matters for a non-JS host — more than it looks

This is the mechanism that makes `custom` **expressible in a declarative option tree**. In v5,
`series.custom` required a function value in the option object, so an option tree that must be
serialisable — a `.lfm`, a JSON config, a design-time property editor — simply could not carry one.
v6 splits it: the *behaviour* is registered once in host code under a name; the *option tree* carries
only `renderItem: 'bubble'` (a string) plus `itemPayload` (data).

That maps cleanly onto Pascal: `TyRegisterCustomSeries('bubble', @MyRenderProc)` at unit init, option
tree stores a string, and the design-time validator can check `renderItem` against the registry and
offer a dropdown. **One caveat:** `itemPayload` values may themselves be callables in JS (the
official example passes `opacity: () => …`); a Pascal option tree would restrict that to data.

`custom` also gained `compoundPath` (`CustomSeries.ts:191,249`, `CustomView.ts:366-371`, changelog
`:118`) and `tooltipDisabled` (changelog `:124`) in v6.

**Size: S** — a named-callback registry and one extra option field. **Depends on:** a custom-series
renderer existing at all, which is itself L and is v5 territory, not v6.

---

## 8. Other genuinely-new-in-v6 machinery worth naming

Verified as having no v5 counterpart, in decreasing order of relevance to a port:

**a. `grid.outerBounds*` — the anti-overflow layout pass.** `src/coord/cartesian/GridModel.ts:48-137`,
doc `en/option/component/grid.md:52-113`, changelog `:110`. Four options —
`outerBoundsMode: 'auto'|'same'|'none'`, `outerBounds` (a rect), `outerBoundsContain:
'all'|'axisLabel'|'auto'`, `outerBoundsClampWidth/Height` — driving a pass that **shrinks the plot
rect until axis labels and axis names fit inside a constraint rect**, on by default. It subsumes and
deprecates `containLabel` (`grid.md:41,71`: `containLabel:true` ≡ `{outerBoundsMode:'same',
outerBoundsContain:'axisLabel'}`) and is one of the five v6.0 breaking changes, because plot rects
now shift slightly. Companion: `axisLabel.nameMoveOverlap` (default on) nudges the axis *name* off
the axis *labels*. Together a real iterative-layout subsystem, not a tweak. **Size: M**, depends on
measuring rotated text before committing the plot rect.

**b. `src/visual/tokens.ts` (233 lines) — a design-token layer.** Two 20+-step ramps (`neutral00`…
`neutral99`, `accent05`…`accent95`) plus semantic aliases (`primary`, `secondary`, `border`,
`borderTint`, `borderShade`, `background`, `backgroundTint`, `shadow`, `highlight`, `disabled`) and a
`size` group, with a parallel `darkColor` set. Every v6 default reaches for these
(`tokens.color.borderTint` in `MatrixModel.ts:236`, `tokens.color.border` in `ThumbnailModel.ts:79`).
**Architecturally the same idea as ty-controls' own theme tokens** — a working example of a chart
library whose defaults are all token references, worth reading before designing the chart's theme
surface.

**c. `chart.setTheme()` — runtime theme switching.** `src/core/echarts.ts:827-865`, doc
`en/api/echarts-instance.md:241-300`, changelog `:113`. v5 could only pick a theme at `init`. Caveat
at `echarts-instance.md:281-299`: after `setTheme` the previously merged options are **discarded** —
merge-mode `setOption` + `setTheme` is unsupported.

**d. `src/coord/axisStatistics.ts` + `axisStatisticsMetricsImpl.ts` (672 lines).** A per-update-cycle
cache of ⟨axis, series⟩ pairs and derived statistics, keyed by client, backed by
`src/util/cycleCache.ts` (85 lines, also new). It is what makes `axisAlignTicks`, bar layout and the
v6.1 uniform `bandWidth` work across multiple series sharing an axis. Invisible to users; unavoidable
if you want the same correctness.

**e. `src/coord/axisBand.ts` (209 lines).** v6.1's "uniform `bandWidth` calculation in numeric axis
(`value`/`time`/`log`)" (changelog `:20`). Consumed by jitter (`calcBandWidth`, `jitter.ts:80`).
Lets bar-like series sit on a *non-category* axis with a sane width — new capability, not a fix.

**f. `containShape` + overflow elimination (v6.1).** Changelog `:5` and the breaking-change bullet at
`:103`: `bar`/`pictorialBar`/`candlestick`/`boxplot` no longer overflow the plot rect at the edges;
`axis.containShape: false` restores v6.0 behaviour. New option, changed default, real geometry work.

**g. Single-option additions — each S, none structural.** `visualMap.seriesTargets` (v6.1,
changelog `:14`), `axis.dataMin`/`dataMax` (v6.1, `:4`), `visualMap.unboundedRange`
(`en/option/component/visual-map.md:86`), `marker.relativeTo: 'container'|'coordinate'`
(`MarkerModel.ts:56`), `stackOrder: 'seriesAsc'|'seriesDesc'` (`processor/dataStack.ts:86-88`),
`legend.triggerEvent`, `line.triggerEvent` (v6.1), `radar.clockwise` (v6.1),
`dataZoom.inside.cursorGrab`/`cursorGrabbing` (v6.1), sankey roaming,
`markPoint/markLine/markArea.z` and `.z2`, `tooltip.displayTransition`,
`custom.compoundPath` and `custom.tooltipDisabled`, `pie.label` rotation mode
`'tangential-noflip'` (v6.1), `gauge.progress.color: 'auto'` (v6.1).

**h. The `features` opt-in bundle (`src/export/features.ts`).** New in shape: `UniversalTransition`,
`LabelLayout`, **`AxisBreak`**, **`ScatterJitter`**, `LegacyGridContainLabel`. Signals which v6
subsystems the ECharts team themselves considered heavy enough to keep out of the default build —
breaks and jitter. A native port can use the same triage.

**i. Browser-bound, therefore not portable.** Nothing in §1–§7 is DOM/CSS/WebGL-bound — chord,
matrix, box, thumbnail, breaks, jitter and `registerCustomSeries` are all pure geometry + model
work over zrender's canvas/SVG abstraction. The browser-bound v6 items are: `tooltip` DOM rendering
and `tooltip.displayTransition` (a CSS transition), `toolbox.dataView` (an HTML textarea — v6.1 fixed
its dark mode, changelog `:57`), `getSvgDataURL`/`encodeBase64`, and `setPlatformAPI`. `itemPayload`
carrying **JS closures** (`opacity: () => …` in the official example) is JS-bound by nature and would
be data-only in a Pascal host.

---

## 9. Port sizing, consolidated

| Subsystem | Size | Hard prerequisite | Can it be added later? |
|---|---|---|---|
| `chord` series | **M** | graph/edge data model; arc sector w/ corner radius; emphasis-focus propagation | Yes, cleanly |
| `matrix` coord sys | **XL** | ordinal scale; box-layout engine; per-cell text truncation | Yes, but it is the base for the next two rows |
| `coordinateSystemUsage:'box'` | **S** mechanism / **L** consequence | `DataToLayout(coord):TRect` on the coord-sys interface **from day one**; matrix or calendar as host | Mechanism yes; retrofitting `DataToLayout` into a shipped interface, no |
| `thumbnail` | **S** | graph + roam controller; retained group with transform | Yes |
| axis breaks | **L** | a scale core you can make non-monotonic; interceptable tick generation | **No — this one must be designed in.** It touches `Interval`, `Log`, `Time`, `minorTicks`, `scaleMapper`, `axisHelper`, `AxisBuilder` |
| jitter | **S** | scatter on category/single axis | Yes |
| `registerCustomSeries` + `itemPayload` | **S** | a custom-series renderer (L, and that is v5 work) | Yes — but adopt the *string + payload* shape immediately; it is what makes `custom` serialisable |
| `grid.outerBounds*` | **M** | text measurement before plot-rect commit | Yes, but it changes layout output |
| design tokens | **S** | — | Yes; ty-controls already has the concept |

### The one-line answer to "v5 or v6"

Target **v6**, but the reason is narrow and specific: of the seven new subsystems, six are cleanly
additive and can be scheduled whenever. **Two decisions cannot be deferred** —
(1) the coordinate-system interface must expose `DataToLayout(coord): TRect` alongside
`DataToPoint`, or `coordinateSystemUsage:'box'` becomes a rewrite instead of a feature; and
(2) the scale core must be built knowing that value→coord mapping may be piecewise-discontinuous,
or axis breaks are permanently off the table. Everything else in v6 — chord, matrix, thumbnail,
jitter, `registerCustomSeries` — is work you can take or leave later at the same cost.

Corollary for the depth-first build order: those two decisions land in **phase 1 (cartesian)**, not
in a later "v6 features" phase.
