# ECharts 6.1.0 — Radial, Hierarchical, Relational and Geographic Series

Survey for a native (FPC/Lazarus + BGRABitmap) custom-drawn chart control.
Sources read: `D:/Projects/echarts` (TypeScript source, `package.json` version **6.1.0**) and
`D:/Projects/echarts-doc/en/option/**` (official option reference, `${partial}` includes resolved).

Scope: the 13 series types `pie`, `radar`, `gauge`, `funnel`, `sunburst`, `treemap`, `tree`,
`graph`, `sankey`, `chord`, `parallel`, `map`, `lines` — plus the coordinate systems / components
they depend on (`radar` component, `geo` component, `parallel` + `parallelAxis` components,
the `view` coordinate system).

ECharts 6.1.0 ships **23 series types** total (`src/export/charts.ts`): line, bar, pie, scatter,
radar, map, tree, treemap, graph, **chord (new in 6.0)**, gauge, funnel, parallel, sankey, boxplot,
candlestick, effectScatter, lines, heatmap, pictorialBar, themeRiver, sunburst, custom.
This document covers 13 of them.

---

## 0. Cross-cutting machinery these families share

Understanding these first removes ~40% of the per-series work.

### 0.1 Box layout vs. coordinate-system placement (v6 change)

Historically pie/gauge/funnel/treemap/sunburst were positioned by `center`/`radius` against the
whole canvas. In v6 they gained `coordinateSystemUsage: 'box'` (see `PieSeries.defaultOption`,
`FunnelSeries`, `TreemapSeries`, `TreeSeries`, `SankeySeries`). Meaning:

| Concept | Option | Semantics |
|---|---|---|
| Box container | `left`/`top`/`right`/`bottom`/`width`/`height` | rect the series lays out inside; may be the canvas, or **a matrix cell / calendar cell** |
| Circle layout | `center: [x, y]`, `radius: r` or `[r0, r]` | `util/layout.ts::getCircleLayout` — percentages resolve against `min(boxW, boxH)/2` |
| Coord-anchored | `coordinateSystem: 'geo' \| 'cartesian2d' \| 'calendar' \| 'matrix' \| 'none'` | e.g. a pie *per map region*, `center` is then a data coordinate |

`pie` declares `SeriesOnGeoOptionMixin` + `SeriesOnCartesianOptionMixin` +
`ComponentOnCalendarOptionMixin` + `ComponentOnMatrixOptionMixin`, and registers
`registerLayOutOnCoordSysUsage` with `getCoord2 = model.get('center')`. That is the
"small pies scattered over a map" capability, generalized.

### 0.2 The `view` coordinate system + roam

`graph`, `tree`, `treemap`, `sankey`, `map`/`geo` all sit on a pan/zoom **View** transform
(`src/coord/View.ts`, `src/component/helper/RoamController`). Shared option block
(`partial/view-coord-sys.md`):

| Option | Values | Note |
|---|---|---|
| `roam` | `false` / `true` / `'scale'` \| `'zoom'` / `'move'` \| `'pan'` | pan/zoom enable |
| `roamTrigger` | `'selfRect'` (default) / `'global'` | whether wheel/drag anywhere counts |
| `zoom` | number, `1` = fit | live-mutated by roaming |
| `center` | `[x, y]`, numbers, `'50%'` strings, or lng/lat (geo) | which data point sits at viewport center |
| `scaleLimit` | `{min, max}` | zoom clamp |
| `preserveAspect` | `false` / `true` \| `'contain'` / `'cover'` | v6 |
| `preserveAspectAlign` | `'left'\|'center'\|'right'` | v6 |
| `preserveAspectVerticalAlign` | `'top'\|'middle'\|'bottom'` | v6 |
| `nodeScaleRatio` | 0..1 (graph 0.6, tree 0.4) | how much symbols shrink when you zoom in — symbols are NOT scaled 1:1 with the view |

Roam dispatches `geoRoam` (geo/map) or a per-series roam action (`registerRoamActionSimply` is
called for tree, graph, sankey, treemap).

### 0.3 Emphasis / blur / select state model

Every series here supports 4 visual states: **normal**, `emphasis`, `blur`, `select`.
`emphasis.focus` selects what stays sharp while everything else is blurred:

| Focus value | Available on | Meaning |
|---|---|---|
| `'none'` | all | no blur |
| `'self'` | all | only the hovered item |
| `'series'` | all | whole series |
| `'descendant'` / `'ancestor'` | sunburst | subtree / path to root |
| `'relative'` | sunburst | ancestors + descendants |
| `'adjacency'` | graph, sankey, chord | node + its edges + neighbours |
| `'trajectory'` | sankey (v5.4.3+) | full upstream+downstream flow path |

`blurScope`: `'coordinateSystem'` / `'series'` / `'global'`.
`selectedMode`: `false` / `true` / `'single'` / `'multiple'` / `'series'` (v5.3+).

### 0.4 Label pipeline

Three layers, all reusable:

1. **Per-series label layout** (pie's ellipse-fitting label placer, sunburst's radial rotation,
   funnel's 10 anchor positions, treemap's `upperLabel`).
2. **`labelLayout`** (option object *or* callback) — post-layout override of
   `x/y/dx/dy/rotate/width/height/align/verticalAlign/fontSize/draggable/labelLinePoints`,
   plus `hideOverlap: boolean` and `moveOverlap: 'shiftX' | 'shiftY'`.
3. **`labelLine`** — 2-segment leader lines with `length`, `length2`, `smooth`, `minTurnAngle`,
   `maxSurfaceAngle`, `showAbove`.

`labelLayout` as a **callback** is JS-only; as an object it is portable.

---

## 1. `series.pie`

**Draws:** annular sectors (`zrender Sector`: cx, cy, r0, r, startAngle, endAngle, clockwise,
`cornerRadius[4]`) plus labels and 2-segment leader lines.
**Data:** 1-D — `number`, `[number]`, or `{name, value, selected, itemStyle, label, labelLine, ...}`.
Name-based encode (`makeSeriesEncodeForNameBased`), so it also binds to a `dataset`.

### 1.1 Geometry / layout (`pieLayout.ts`)

| Option | Default | Semantics |
|---|---|---|
| `center` | `['50%','50%']` | percentages against the box rect |
| `radius` | `[0, '50%']` | `[inner, outer]` — **this is the donut**; scalar = outer only |
| `startAngle` | `90` | degrees, 0 = 3 o'clock, CCW-positive; internally negated to canvas radians |
| `endAngle` | `'auto'` | `'auto'` ⇒ `startAngle - 2π`; a number makes a **partial/gauge-like pie** |
| `clockwise` | `true` | sweep direction |
| `padAngle` | `0` | gap in degrees between neighbouring sectors — implemented by insetting each sector's start/end by `±padAngle/2`; if `padAngle > angle` the sector collapses to a zero-width sliver |
| `minAngle` | `0` | floor on sector angle; leftover angle is redistributed over the non-clamped sectors (`restAngle / valueSumLargerThanMinAngle`), and if nothing is left, all sectors become equal |
| `roseType` | `false` / `'radius'` / `'area'` | Nightingale. `'radius'`: angle ∝ value, **radius = linearMap(value, [0,max], [r0, r])**. `'area'`: **every sector gets `angleRange/validCount`**, only radius encodes value |
| `stillShowZeroSum` | `true` | when all values are 0, still draw equal sectors |
| `showEmptyCircle` | `true` | placeholder ring when there is no data |
| `emptyCircleStyle` | `{color:'lightgray', opacity:1}` | its style |

`minAngle` and `padAngle` are combined (`minAndPadAngle = minAngle + padAngle`) before clamping —
a real subtlety if you reimplement it.

### 1.2 Labels

| Option | Default | Semantics |
|---|---|---|
| `label.position` | `'outer'` | `'outer'`/`'outside'`, `'inside'`/`'inner'`, `'center'` (donut hole) |
| `label.rotate` | `0` | `number` (−90..90), `true`/`'radial'`, `'tangential'`, **`'tangential-noflip'` (new in 6.1.0)** |
| `label.alignTo` | `'none'` | `'none'` (fixed leader lengths), `'labelLine'` (align text to a common x, extend segment 2), `'edge'` (flush to viewport edge) |
| `label.edgeDistance` | `'25%'` | only for `alignTo:'edge'` |
| `label.bleedMargin` | auto (10 if `min(w,h) > 200` else 2) | clearance from viewport for `alignTo` none/labelLine; text past it is ellipsised |
| `label.distanceToLabelLine` | `5` | text↔line gap |
| `label.overflow` | `'truncate'` | |
| `minShowLabelAngle` | `0` | hide label if sector narrower than this |
| `avoidLabelOverlap` | `true` | the shift-and-refit solver |
| `percentPrecision` | `2` | `{d}` percentage digits; uses **largest-remainder ("seats") apportionment** (`getPercentSeats`) so displayed percentages sum to 100 |
| `labelLine.length` / `.length2` | `15` / `30` | radial segment / horizontal segment |
| `labelLine.smooth` | `false` | boolean or 0..1 curvature |
| `labelLine.minTurnAngle` | `90` | clamp elbow angle (`limitTurnAngle`) |
| `labelLine.maxSurfaceAngle` | `90` | keep leader from grazing the arc (`limitSurfaceAngle`) |
| `labelLayout.hideOverlap` | `true` (pie default) | final overlap cull |

**`avoidLabelOverlap` is a real algorithm**, not a flag (`pie/labelLayout.ts`, ~600 lines):
split labels into left/right half, `shiftLayoutOnXY` to de-overlap vertically inside the view rect,
then `recalculateXOnSemiToAlignOnEllipseCurve` — re-solve each label's x from the **ellipse implicit
equation** `(dx/rA)² + (dy/rB)² = 1` so the shifted labels still sit on a smooth curve, then
`constrainTextWidth` re-wraps/ellipsises text for the new available width, then leader elbows are
re-clamped by turn/surface angle.

### 1.3 Style / interaction

- `itemStyle.borderRadius`: `number | string | [in, out] | [4 values]`; percentages resolve against
  `|r − r0|` (`sectorHelper.getSectorCornerRadius`). This is the rounded-Nightingale look.
- `itemStyle.borderWidth` 1, `borderJoin: 'round'`, `borderColor`, `decal` (pattern fill), shadows.
- `selectedMode` + `selectedOffset` (default `10`): selected sector translates outward along its
  mid-angle by that many px.
- `emphasis.scale` (true) + `emphasis.scaleSize` (code default `5`; docs say `10`): grows `r` on hover.
- Animations: `animationType: 'expansion' | 'scale'` (initial), `animationTypeUpdate:
  'transition' | 'expansion'`; `animationEasing: 'cubicInOut'`, 1000 ms / 500 ms update.
- `cursor` (CSS cursor string — browser-bound), `legendHoverLink`, `colorBy: 'data'`.

---

## 2. `radar` — component vs. series

**The split matters.** `radar` is *both*:

- **`radar` component** (`src/coord/radar/RadarModel.ts` + `Radar.ts` + `IndicatorAxis.ts`,
  drawn by `src/component/radar/RadarView.ts`) — it *is* a coordinate system, registered as
  `'radar'`. It owns the grid, the axes and the axis names.
- **`series.radar`** (`src/chart/radar/`) — only the polygons/lines/symbols on top.
  Options: `radarIndex` (default 0 → **multiple radar components on one canvas**, each with its own
  indicators, referenced by index), `symbol`/`symbolSize` (8), `lineStyle` (width 2, `join:'round'`),
  `areaStyle`, `itemStyle`, `label` (`position:'top'`), `colorBy: 'data'`.

Data is one row per polygon: `{name, value: [v0, v1, ... vN]}` — one number per indicator.
Dimensions are auto-generated `indicator_0..N` (`generateCoordCount: Infinity`).

### 2.1 Radar component options

| Option | Default | Semantics |
|---|---|---|
| `indicator` | `[]` | `[{name, min, max, color, axisType:'value'\|'log'}]` — **each indicator is its own axis with its own scale** |
| `shape` | `'polygon'` | `'polygon'` \| `'circle'` — grid rings drawn as `Polyline`/`Polygon` vs `Circle`/`Ring` |
| `center` / `radius` | `['50%','50%']` / `'50%'` | |
| `startAngle` | `90` | angle of the first indicator axis |
| `clockwise` | `false` | axis ordering direction (note: opposite of pie) |
| `splitNumber` | `5` | rings; ticks are aligned across all indicator axes via a dummy `IntervalScale` + `scaleCalcAlign` |
| `scale` | `false` | don't force 0 into the extent |
| `boundaryGap` | `[0, 0]` | |
| `splitLine` | shown | `lineStyle.color` may be an **array → alternating ring colors** |
| `splitArea` | shown | `areaStyle.color` array → alternating banded rings (the classic radar zebra) |
| `axisLine` | shown | the spokes |
| `axisTick` | hidden | |
| `axisLabel` | hidden | per-ring value labels |
| `axisName` | `{show:true, formatter}` | indicator name text; `formatter` is `'{value}'` template or callback |
| `axisNameGap` | `15` | |
| `triggerEvent` | – | make axis names hit-testable |

Coordinate math: `Radar.coordToPoint(coordOnAxis, indicatorIndex)` = polar → cartesian on that
spoke; `pointToData` inverts by nearest spoke. Indicator auto-normalization: if `max > 0` and no
`min`, `min` is forced to 0 (and mirrored for negative `min`).

---

## 3. `series.gauge`

**Draws:** an arc track (optionally split into colored bands), tick marks, tick labels, a progress
arc, one or more needles, a hub, and two text blocks. Fully self-contained — no coordinate system.

| Option | Default | Semantics |
|---|---|---|
| `center` / `radius` | `['50%','50%']` / `'75%'` | |
| `startAngle` / `endAngle` | `225` / `-45` | degrees; 0 = right, CCW-positive. Sweeps 270° by default |
| `clockwise` | `true` | direction of increasing value |
| `min` / `max` | `0` / `100` | value domain |
| `splitNumber` | `10` | major divisions |
| `axisLine.show` | `true` | the track |
| `axisLine.roundCap` | `false` | rounded track ends — drawn with a **`Sausage`** path (capsule) instead of `Sector` |
| **`axisLine.lineStyle.color`** | `[[1, neutral10]]` | **array of `[stopPercent, color]`** → the multi-band arc. Each entry paints from the previous stop to this stop. Also the source of `'auto'` colors for pointer/detail |
| `axisLine.lineStyle.width` | `10` | track thickness |
| `progress.show` | `false` | value-filled arc |
| `progress.width` | `10` | |
| `progress.roundCap` | `false` | Sausage again |
| `progress.overlap` | `true` | with multiple data items, progress arcs overlap vs. stack side-by-side |
| `progress.clip` | `true` | clip to track |
| `progress.itemStyle.color` | `'auto'` (v6.1) | inherit band color |
| `splitLine` | `{show, length:10, distance:10, lineStyle}` | major ticks; `length` may be `'x%'` of radius |
| `axisTick` | `{show, splitNumber:5, length:6, distance:10}` | minor ticks per major division |
| `axisLabel` | `{show, distance:15, formatter, rotate}` | `rotate` accepts `number`, `'radial'`, `'tangential'` (v5.4) |
| `pointer.show` | `true` | |
| `pointer.icon` | `null` | **`null` = the built-in tapered needle** (`PointerPath.ts`: a 4-point kite whose base offset depends on `width >= r/3`). Any value = a **symbol name or an SVG `path://` string** — arbitrary needle art |
| `pointer.length` / `.width` | `'60%'` / `6` | length may be % of radius |
| `pointer.offsetCenter` | `[0,0]` | px or % of radius |
| `pointer.keepAspect` | `false` | for custom icons |
| `pointer.showAbove` | `true` | z-order vs title/detail |
| `pointer.itemStyle` | – | |
| `anchor` | `{show:false, size:6, icon:'circle', offsetCenter, keepAspect, itemStyle}` | the hub cap |
| `title` | `{show, offsetCenter:[0,'20%'], formatter, valueAnimation, textStyle}` | the name label |
| `detail` | `{show, offsetCenter:[0,'40%'], width:100, height:null, padding:[5,10], backgroundColor, borderWidth, borderColor, formatter, valueAnimation, fontSize:30, fontWeight:'bold'}` | the big number, with its own box |

**Multi-value gauges are first-class**: `data` is an array; each item may carry its own
`pointer`, `progress`, `title`, `detail`, `itemStyle`. So N needles + N labelled progress arcs
on one dial (`GaugeView._renderPointer` / `createProgress` iterate `data`).
`valueAnimation: true` tweens the *number text* itself (interpolated + re-formatted per frame).

---

## 4. `series.funnel`

**Draws:** a stack of quadrilaterals (4 points each), never trapezoid-only — each band is defined
by 4 corner points, so `orient:'horizontal'` produces sideways funnels.

| Option | Default | Semantics |
|---|---|---|
| `left/top/right/bottom` | `80/60/80/65` | box |
| `min` / `max` | data extent | value→width mapping domain |
| `minSize` / `maxSize` | `'0%'` / `'100%'` | band width at `min` / at `max`; `'0%'` gives the classic point |
| `sort` | `'descending'` | `'ascending'` \| `'descending'` \| `'none'` \| **comparator function** |
| `gap` | `0` | px between bands |
| `orient` | `'vertical'` | `'vertical'` \| `'horizontal'` |
| `funnelAlign` | `'center'` | `'left'`/`'center'`/`'right'` (vertical) or `'top'`/`'middle'`/`'bottom'` (horizontal) — pyramid vs. right-aligned staircase |
| `label.position` | `'outer'` | `'outer'`/`'left'`/`'right'`/`'top'`/`'bottom'`, inside variants `'inside'`/`'inner'`/`'center'`/`'insideLeft'`/`'insideRight'`, and corner anchors `'leftTop'`, `'leftBottom'`, `'rightTop'`, `'rightBottom'` — **10 distinct anchors**, with orient-aware fallbacks (asking for `'top'` on a vertical funnel warns and falls back to `'left'`) |
| `labelLine.length` | `20` | single-segment leader |
| `itemStyle` | `borderColor` white, `borderWidth` 1 | per-item `itemStyle.width` / `.height` can override a single band's size |
| `percent` | derived | `params.percent` = value/sum×100, 2 dp |

Layout is trivially portable: sort → map value to width via `linearMap` → stack with gaps.

---

## 5. `series.sunburst`

**Draws:** nested annular sectors from a tree. Same `Sector` primitive as pie, plus per-level radii.

**Data:** recursive `{name, value, children[], itemStyle, label, link, target, collapsed, nodeClick}`.
Values are rolled up bottom-up (`completeTreeValue`) if a parent has no explicit value.
Backed by the shared `src/data/Tree.ts`.

### 5.1 Layout (`sunburstLayout.ts`)

- Angle: `unitRadian = 2π / sum`; each node's sweep = `value × unitRadian`, clamped by `minAngle`.
  Children are laid inside the parent's angular span, in order, by recursive `renderNode`.
- Radius: `rPerLevel = (r − r0) / levelCount`; node ring = `[r0 + rPerLevel·d, r0 + rPerLevel·(d+1)]`
  where `d` is depth relative to the current view root. **`levels[i].radius: [r0, r]` overrides a
  specific ring's radii** (v5.2+), which does not reflow the other rings.
- Drill-down: when the view root is not the true root, a **roll-up node** (full 2π ring) is drawn at
  the innermost radius as the "back" target.

| Option | Default | Semantics |
|---|---|---|
| `center`/`radius` | `['50%','50%']` / `[0,'75%']` | |
| `startAngle` | `90` | |
| `clockwise` | `true` | |
| `minAngle` | `0` | |
| `sort` | `'desc'` | `'desc'` \| `'asc'` \| `null` (data order) \| comparator `(a,b)` over `{dataIndex, depth, height, getValue()}` |
| `nodeClick` | `'rootToNode'` | `'rootToNode'` (drill), `'link'` (open `data.link` in `data.target`), `false` |
| `renderLabelForZeroData` | `false` | |
| `stillShowZeroSum` | `true` | |
| `levels` | `[]` | **array indexed by depth; `levels[0]` is the roll-up/back node**, `levels[1]` the innermost real ring. Each entry can carry `radius`, `itemStyle`, `label`, `emphasis`, `blur`, `select` |
| `label.rotate` | `'radial'` | `'radial'` \| `'tangential'` \| `number` \| `0` |
| `label.position` | `'inside'` | `'inside'` \| `'outside'` |
| `label.align` | `'center'` | `'left'` = toward the inner edge, `'right'` = outer |
| `label.minAngle` | – | hide label under this sweep |
| `label.silent` | `true` | labels not hit-testable |
| `itemStyle.borderRadius` | – | same 4-corner sector rounding as pie |
| `emphasis.focus` | `'descendant'` | `'descendant'` / `'ancestor'` / `'relative'` / `'self'` / `'none'` |
| `blur` | `{itemStyle.opacity:0.2, label.opacity:0.1}` | |
| `animationType` | `'expansion'` | \| `'scale'` |

**Default color strategy is algorithmic** (`sunburstVisual.ts`): the root gets a neutral grey;
each *first-level* node takes a palette color; deeper descendants get
`lift(parentColor, (depth−1)/(treeHeight−1) × 0.5)` — a programmatic lightening ramp down the tree.

**Actions:** `sunburstRootToNode`, `sunburstHighlight`, `sunburstUnhighlight`.

---

## 6. `series.treemap`

The heaviest of the family. Rectangle packing + drill-down + its own visual-mapping mini-engine.

### 6.1 Layout: squarified treemap (`treemapLayout.ts`)

`squarify()` implements Bruls–Huizing–van Wijk **squarified treemap**:
accumulate children into a *row*, score the row with `worst(row, rowFixedLength, squareRatio)`
(the max aspect ratio in the row, using `f = rowFixedLength² × ratio`), keep adding while the
score improves, then `position()` the row along the shorter side, shrink the rect, and recurse
(`squarify(child, depth+1)`).

| Option | Default | Semantics |
|---|---|---|
| `squareRatio` | `0.5·(1+√5)` (golden ratio) | target aspect ratio the packer approaches |
| `sort` | `true` (=desc) | `true`/`false`/`'asc'`/`'desc'` — feeding the packer sorted is what makes it look squarified |
| `leafDepth` | `null` | **enables drill-down**: only this many levels are shown at once; clicking a parent re-roots |
| `drillDownIcon` | `'▶'` | marker glyph on drillable nodes |
| `nodeClick` | `'zoomToNode'` | `'zoomToNode'` / `'link'` / `false` |
| `zoomToNodeRatio` | `0.32²` | target fraction of viewport the clicked node zooms to |
| `clipWindow` | `'origin'` | `'origin'` \| `'fullscreen'` |
| `roam` / `roamTrigger` / `scaleLimit` | `true` / `'global'` / `{min:0.2,max:5}` | pan-zoom |
| `breadcrumb` | `{show:true, height:22, left:'center', bottom, emptyItemWidth:25, itemStyle{...}, emphasis{...}}` | the drill path strip — chevron-shaped buttons drawn by `Breadcrumb.ts` |
| `label` | inside, `overflow:'truncate'`, padding 5 | leaf labels |
| `upperLabel` | `{show:false, position:[0,'50%'], height:20, verticalAlign:'middle'}` | **parent-node header band** — the label drawn in a strip at the top of a non-leaf rect (this is what makes nested treemaps readable) |
| `itemStyle.gapWidth` | `0` | gap between siblings (distinct from `borderWidth`) |
| `itemStyle.borderColorSaturation` | `null` | if set, border color = derived from the node's own fill at this saturation, overriding `borderColor` |
| `visibleMin` | `10` | drop nodes whose area < N px² |
| `childrenVisibleMin` | `null` | if a node's area < N px², don't draw its grandchildren |
| `animationDurationUpdate` | `900`, easing `quinticInOut` | rect morphing between drill states |

### 6.2 Treemap's visual-mapping sub-engine

Independent of the global `visualMap` component. Per-level (`levels[]`) or per-node:

| Option | Values | Semantics |
|---|---|---|
| `visualDimension` | `0..n` or dim name | which array element of `value: [a,b,c]` drives the visual (area always uses dim 0) |
| `colorMappingBy` | `'index'` (default) \| `'value'` \| `'id'` | how a node picks from `color[]` — round-robin, value-interpolated, or hashed by id (stable across data updates) |
| `color` | `ColorString[]` \| `'none'` | per-level palette |
| `colorAlpha` | `[lo, hi]` \| `'none'` | alpha range mapped from `visualDimension` |
| `colorSaturation` | `[lo, hi]` \| `'none'` | saturation range, composed onto the **inherited parent color** |
| `visualMin` / `visualMax` | numbers | manual extent for `'value'` mapping |
| `decal` | `DecalObject[]` \| `'none'` | pattern fills |

The documented inheritance rule: a node inherits its parent's computed visual unless it defines its
own; so "top level picks hue from `color[]`, child levels modulate `colorSaturation`" is the idiom.

**Actions:** `treemapZoomToNode`, `treemapRender`, `treemapMove`, `treemapRootToNode`
(with `direction: 'rollUp' | 'drillDown'`).

---

## 7. `series.tree`

**Draws:** node symbols + parent→child edges. On a roam-able `view` coordinate system.

| Option | Default | Semantics |
|---|---|---|
| `layout` | `'orthogonal'` | \| `'radial'` |
| `orient` | `'LR'` | `'LR'`, `'RL'`, `'TB'`, `'BT'` (legacy `'horizontal'`≡LR, `'vertical'`≡TB). Only for orthogonal |
| `edgeShape` | `'curve'` | \| `'polyline'` — **polyline is orthogonal-only** (radial + polyline errors in dev builds) |
| `edgeForkPosition` | `'50%'` | where the polyline elbow branches, as % of the parent→child gap |
| `lineStyle.curveness` | `0.5` | bezier bow for `'curve'` |
| `expandAndCollapse` | `true` | click a node to fold/unfold its subtree |
| `initialTreeDepth` | `2` | levels expanded at start; `-1`/`null` = all |
| `symbol` / `symbolSize` | `'emptyCircle'` / `7` | **the hollow symbol's inner fill encodes "has collapsed subtree"** — a documented semantic, not just styling. A custom image symbol loses that affordance |
| `roam` / `roamTrigger` / `zoom` / `center` / `scaleLimit` | `false` / `'global'` / 1 | |
| `nodeScaleRatio` | `0.4` | symbol shrink factor under zoom |
| `leaves` | `{label, itemStyle, emphasis, blur, select}` | a style block that applies **only to leaf nodes** (implemented as a parent Model injected into leaf item models) |
| `itemStyle` | color `lightsteelblue`, borderWidth 1.5 | |
| `label` | shown | |
| `left/top/right/bottom` | `12%` each | box |
| `animationDuration` | 700 / 500 update, easing `linear` | |

### 7.1 Layout algorithm

`treeLayout.ts` + `layoutHelper.ts` implement the **Reingold–Tilford tidy tree in the Buchheim–Jünger–Leipert
linear-time form**: `firstWalk` (post-order, `prelim` + `apportion` with `nextLeft`/`nextRight`/
`nextAncestor` threading and `moveSubtree`/`executeShifts`), then `secondWalk` (pre-order, apply
accumulated `modifier`). `separation(node1,node2)` is pluggable; for radial layout the separation
callback divides by depth so rings don't crowd. Radial mode maps `(x=angle, y=radius)` through
`radialCoordinate(rad, r)`.

**Action:** `treeExpandAndCollapse` (event `treeExpandAndCollapse`).

---

## 8. `series.graph`

**Draws:** nodes (symbols), edges (straight/quadratic-bezier/polyline), optional edge end-symbols,
node labels, edge labels. Coordinate system: `'view'` (own pan/zoom) **or** `'cartesian2d'`,
`'polar'`, `'geo'`, `'calendar'`, `'matrix'` — i.e. a network drawn on top of a map or grid.

**Data:** `data`/`nodes` = `[{id, name, x, y, fixed, value, category, symbol, symbolSize,
itemStyle, label, ...}]`; `links`/`edges` = `[{source, target, value, lineStyle{curveness},
label, symbol, symbolSize, ignoreForceLayout}]`. Backed by `src/data/Graph.ts` (two `SeriesData`
tables: node data + edge data).

### 8.1 The three layouts

| `layout` | Behaviour |
|---|---|
| `'none'` (default `null`) | use `data[i].x` / `.y` verbatim (`simpleLayout`) |
| `'circular'` | nodes evenly around a circle (`circularLayout`, two variants: spacing by `'value'` or by `'symbolSize'` so big nodes get more arc). `circular.rotateLabel: false` → rotate each label to the radius |
| `'force'` | iterative force simulation |

### 8.2 Force simulation (`forceHelper.ts`, d3-derived, BSD-3)

Per `step()`:
1. **Spring**: for each edge, `d = |p2−p1| − e.d`; move both endpoints along the unit vector by
   `w·d·friction` / `−(1−w)·d·friction`, where `w = n2.w/(n1.w+n2.w)` (mass = node weight).
2. **Gravity**: pull every node toward the rect center by `gravity·friction`.
3. **Repulsion**: O(n²) all-pairs, `repFact = (n1.rep + n2.rep)/d²`, applied to a shadow position `pp`.
   Zero distance → random jitter. **No Barnes-Hut quadtree** — plain N².
4. Integrate: `p += (p − pp)·friction`, then `friction *= 0.992`. Converged when `friction < 0.01`.

| Option | Default | Semantics |
|---|---|---|
| `force.initLayout` | `null` | `'circular'` \| `'none'` — seeding |
| `force.repulsion` | `[0, 50]` | scalar or `[min,max]` **mapped from node `value`** via `linearMap` |
| `force.gravity` | `0.1` | |
| `force.edgeLength` | `30` | scalar or `[min,max]` mapped from edge `value` (note: **reversed**, high value ⇒ short edge) |
| `force.friction` | `0.6` | initial damping |
| `force.layoutAnimation` | `true` | animate the convergence (and, when true, disables normal element transition animation) |
| `data[i].fixed` | – | pin a node |
| `links[i].ignoreForceLayout` | `false` | edge exerts no spring force |
| `preservedPoints` | internal | node positions persist across `setOption` by node id |

### 8.3 Edges

- `lineStyle.curveness` 0..1 → quadratic bezier. In circular layout the control point is pulled
  toward the circle center (`curveness *= 3`, lerp between center and midpoint) giving the classic
  arc-diagram bow.
- **`autoCurveness`**: `false` \| `true` \| `number` \| `number[]`. For parallel edges between the
  same node pair, generates a symmetric fan of curvatures
  (`[0, −0.2, 0.2, −0.4, 0.4, ...]`, default list length 20; a `number` sets the list length, an
  array supplies it directly). Keyed by `uid-->source-->target` with opposite-direction lookup, so
  A→B and B→A share the fan. Overridden by an explicit `lineStyle.curveness`.
- `edgeSymbol: ['none','none']` / `edgeSymbolSize: 10` — arrowheads etc. at each end.
- `adjustEdge.ts` trims each curve back to the node symbol's boundary by solving
  **curve ∩ circle numerically**: coarse scan of `t ∈ [0.1, 0.9]` then ≤32 bisection steps.
- `edgeLabel` (`position:'middle'`, `distance:5`) — a separate label model from node `label`,
  wired via a `resolveParentPath` hack that rewrites `label` → `edgeLabel` for edge items.

### 8.4 Categories & interaction

- `categories: [{name, symbol, symbolSize, itemStyle, label, emphasis, ...}]` — nodes reference by
  `data[i].category`; the category model becomes the node model's parent, and categories feed the
  legend (`LegendVisualProvider` over `_categoriesData`).
- `draggable` (default `false`): drag a node; in force layout the node is temporarily fixed and the
  simulation is warmed up; in circular layout the node snaps back onto the circle.
- `roam`, `roamTrigger`, `zoom`, `center`, `scaleLimit`, `nodeScaleRatio: 0.6`.
- `emphasis.focus: 'adjacency'` — highlight node + incident edges + neighbours.
  Legacy actions `focusNodeAdjacency` / `unfocusNodeAdjacency` still registered.
- `emphasis.scale: true | number`.

---

## 9. `series.sankey`

**Draws:** node rectangles + ribbon links whose thickness ∝ value. Layered DAG.

**Data:** `data`/`nodes` `[{name, value, depth, itemStyle, label}]`, `links`/`edges`
`[{source, target, value}]`. `levels: [{depth, itemStyle, lineStyle, label, emphasis, blur, select}]`
— per-depth styling; `depth` is mandatory in each level entry.

| Option | Default | Semantics |
|---|---|---|
| `orient` | `'horizontal'` | \| `'vertical'` |
| `nodeWidth` | `20` | rect thickness |
| `nodeGap` | `8` | gap between nodes in a layer |
| `nodeAlign` | `'justify'` | `'left'` (sources flush left), `'right'` (sinks flush right), `'justify'` (both) |
| `layoutIterations` | `32` | relaxation passes; `0` preserves input order |
| `sort` | `'desc'` | within-layer ordering |
| `draggable` | `true` | drag a node along the cross axis (action `dragNode`, event `dragnode`) |
| `lineStyle.curveness` | `0.5` | ribbon bow |
| `lineStyle.color` | neutral, opacity 0.2 | also accepts `'source'`/`'target'`/`'gradient'` (see sankeyVisual) |
| `label.position` | `'right'` | |
| `edgeLabel` | `{show:false}` | |
| `roam` / `roamTrigger` / `zoom` / `center` | `false` / `'global'` / 1 | v6 |
| `emphasis.focus` | – | `'adjacency'`, **`'trajectory'`** (v5.4.3 — whole upstream+downstream path) |
| `left/top/right/bottom` | `5%/5%/20%/5%` | |

### 9.1 Layout (`sankeyLayout.ts`) — the classic d3-sankey pipeline

1. `computeNodeValues` — node value = max(sum in, sum out).
2. `computeNodeBreadths` — BFS assign `depth` (layer index) by longest path from sources;
   then `adjustNodeWithNodeAlign` (`'right'` pushes sinks to `maxDepth`, `'justify'` = `moveSinksRight`),
   then `scaleNodeBreadths` to pixels.
3. `computeNodeDepths` — `initializeNodeDepth` (proportional initial y), then `layoutIterations`
   rounds of `relaxRightToLeft` (pull each node toward the weighted center of its targets) /
   `resolveCollisions` (push apart to honour `nodeGap`, clamp to the box) / `relaxLeftToRight` /
   `resolveCollisions`, with `alpha` decaying each pass.
4. `computeEdgeDepths` — stack the ribbon endpoints on each node's face in sorted order.

---

## 10. `series.chord` — NEW in ECharts 6.0

Verified in source: `src/chart/chord/{ChordSeries, ChordView, ChordPiece, ChordEdge, chordLayout}.ts`,
exported as `ChordChart` in `src/export/charts.ts`. Doc `chord.md` tagged `version 6.0.0`.

**What it is:** a circular chord diagram — nodes become arcs on a ring, links become ribbons
(arc–bezier–arc–bezier closed paths) drawn inside it. Data is a graph
(`data`/`nodes` + `links`/`edges`), the same shape as `graph`/`sankey`.

| Option | Default | Semantics |
|---|---|---|
| `center` / `radius` | `['50%','50%']` / `['70%','80%']` | **ring, not disc** — `r0` is where ribbons attach |
| `startAngle` | `90` | |
| `endAngle` | `'auto'` | |
| `clockwise` | `true` | |
| `padAngle` | `3` | gap between node arcs |
| `minAngle` | `0` | with a **borrow/redistribute solver** (below) |
| `itemStyle.borderRadius` | `[0,0,5,5]` | rounded node arcs |
| `lineStyle.color` | `'source'` | **`'source'` \| `'target'` \| `'gradient'` \| explicit color** — `'gradient'` builds a `LinearGradient` from the source arc's midpoint to the target arc's midpoint |
| `lineStyle.width` / `.opacity` | `0` / `0.2` | ribbons are filled, not stroked |
| `label` | `{show:true, position:'outside', distance:5}` | `'outside'` \| standard positions; `silent` supported |
| `edgeLabel` | – | per-ribbon labels |
| `emphasis.focus` | `'adjacency'` | node → its ribbons + neighbours; ribbon → its endpoints |
| `emphasis.scale` | bool \| number | |
| `coordinateSystem` | `'none'` | can also sit in matrix/calendar cells |

**Layout (`chordLayout.ts`)** is more careful than a naive "angle ∝ value":
- Node value = sum of incident edge values, overridable by an explicit `data.value` (max of the two).
- Handles the all-zero case by weighting nodes by *link count*.
- If `padAngle × nodeCount` exceeds the circle, `padAngle` shrinks; `minAngle` wins over `padAngle`.
- Then a **deficit/surplus borrowing pass**: nodes below `minAngle` are inflated; the needed angle is
  borrowed proportionally from nodes above `minAngle`, with a pre-check (`surplusAsMuchAsPossible`)
  for the case where proportional borrowing would push a donor below `minAngle`.
- Ribbon geometry (`ChordEdge.buildPath`): `moveTo(s1)` → `arc` along `r0` from `sStartAngle` to
  `sEndAngle` → `bezierCurveTo` with both control points lerped 70% toward the center → `arc` on the
  target side → `bezierCurveTo` back → `closePath`. So: **two arcs and two cubics, filled**.

---

## 11. `series.parallel` + the `parallel` / `parallelAxis` components

Again a component/series split:

- **`parallel` component** (`src/coord/parallel/`) — the coordinate system: N axes laid out evenly
  across the box.
- **`parallelAxis` component** (`parallel-axis.md`, `AxisModel.ts`) — one per dimension.
- **`series.parallel`** — the polylines.

### 11.1 Series options

| Option | Default | Semantics |
|---|---|---|
| `parallelIndex` | `0` | which parallel coord system (multiple allowed) |
| `smooth` | `false` | `true` \| `false` \| number 0..1 — bezier smoothing of the polylines |
| `lineStyle` | width 1, opacity 0.45 | |
| `inactiveOpacity` | `0.05` | opacity of lines filtered *out* by brushing |
| `activeOpacity` | `1` | opacity of lines that pass the brush |
| `progressive` | `300` | incremental render chunk (browser frame-budget concept) |
| `realtime` | (on the axis) | see below |
| `parallelAxisDefault` | – | shorthand: define axis defaults on the series instead of N `parallelAxis` entries |
| `label` | hidden | |

### 11.2 Coordinate-system options (`parallel`)

| Option | Default | Semantics |
|---|---|---|
| `layout` | `'horizontal'` | \| `'vertical'` — axes are vertical lines spread horizontally, or vice versa |
| `axisExpandable` | `false` | **axis-zoom mode**: show only a window of axes at expanded spacing, the rest compressed to the sides |
| `axisExpandCenter` | `null` | index at the center of the expanded window |
| `axisExpandCount` | `0` | how many axes are expanded |
| `axisExpandWidth` | `50` | px spacing inside the expanded window |
| `axisExpandTriggerOn` | `'click'` | \| `'mousemove'` |
| `axisExpandRate` | `17` | slide throttling |
| `axisExpandDebounce` | `50` | ms |
| `axisExpandSlideTriggerArea` | `[-0.15, 0.05, 0.4]` | hit zones for dragging the expanded window |
| `axisExpandWindow` | – | explicit `[start, end]` window |

Action: `parallelAxisExpand`.

### 11.3 Brushing (per `parallelAxis`)

Each axis carries an interval brush (`areaSelect`):

| Option | Default |
|---|---|
| `realtime` | `true` — re-filter lines while dragging vs. on release |
| `areaSelectStyle.width` | `20` |
| `areaSelectStyle.borderWidth` / `.borderColor` | `1` / `rgba(160,197,232)` |
| `areaSelectStyle.color` / `.opacity` | `rgba(160,197,232)` / `0.3` |
| `dim` | which data dimension this axis binds |
| `parallelIndex` | which coord system |

Brushed-out lines get `inactiveOpacity`; brushed-in get `activeOpacity`. Multiple axis brushes AND
together. This is the defining interaction of the chart type.

---

## 12. `series.map` + the `geo` component

### 12.1 The relationship (important)

- **`geo`** is the coordinate system/component. It owns the map source, projection, view transform,
  region geometry, region styling (`geo.regions[]`), region selection and roaming. It can be shown
  **without any series**.
- **`series.map`** is a choropleth *on top of* a geo. If `geoIndex` is given it *reuses* that geo
  component; otherwise it silently **creates an exclusive geo of its own** (`geoCreator.ts`) and the
  series' `map`, `center`, `zoom`, `roam`, `aspectScale`, `boundingCoords` etc. configure that
  hidden geo.
- `series.scatter`, `series.lines`, `series.effectScatter`, `series.graph`, `series.pie` can all set
  `coordinateSystem: 'geo'` and be positioned by lng/lat.

### 12.2 Map sources — `echarts.registerMap(name, def, specialAreas?)`

Two source kinds (`geoSourceManager.ts`):

| Kind | Registration | Resource |
|---|---|---|
| **GeoJSON** | `registerMap('USA', geoJsonObject, specialAreas)` or `{geoJSON: ..., specialAreas: ...}` | `GeoJSONResource` — parses Feature/Geometry into `Region` polygon rings |
| **SVG** | `registerMap('airport', {svg: svgStringOrXML})` | `GeoSVGResource` — parses SVG via `zrender/tool/parseSVG`, named elements become regions, honours `viewBox` (`preserveAspectRatio 'xMidYMid'` only) |

`specialAreas` lets you relocate/rescale sub-regions (the classic "Alaska + Hawaii inset").

### 12.3 Geo options

| Option | Default | Semantics |
|---|---|---|
| `map` | `''` | registered map name |
| **`projection`** | none (raw linear lng/lat) | v5.3+. `{project(pt)->pt, unproject(pt)->pt, stream?}` — a **user-supplied projection function pair**. Documented usage is d3-geo (`d3.geoConicEqualArea()`). Optional `stream` for adaptive resampling of long segments. **GeoJSON only — SVG sources reject it with a warning** |
| `aspectScale` | 0.75 (GeoJSON) / 1 (SVG) | crude latitude compensation when no projection; final `pixelW/pixelH = lngSpan/latSpan × aspectScale`. **Ignored when `projection` is set** |
| `boundingCoords` | `null` | `[[lng0,lat0],[lng1,lat1]]` — explicit view bounds, higher priority than center/zoom |
| `layoutCenter` / `layoutSize` | – | alternative placement that always preserves aspect |
| `nameMap` | – | `{ 'GeoJSON name' : 'display/data name' }` — rename regions (**not supported for SVG sources**; code path is commented out) |
| `nameProperty` | `'name'` | which GeoJSON `properties` key identifies a region |
| `regions[]` | `[]` | per-region `{name, selected, itemStyle{areaColor,...}, label, emphasis, select, blur, tooltip, silent}` |
| `itemStyle.areaColor` | background token | region fill (distinct from `color`) |
| `roam` / `roamTrigger` / `zoom` / `center` / `scaleLimit` | `false` / … / 1 | pan/zoom |
| `preserveAspect*` | v6 | see §0.2 |
| `selectedMode` | – | region selection |
| `label` | hidden; emphasis shows | region names |
| `silent` | `false` | |

Coordinate conversion: `Geo.dataToPoint(lngLat)` = `projection.project(pt)` (if any) → View transform;
`pointToData` inverts. Bounding rect with a projection is computed by **sampling the lng/lat rect
perimeter and projecting the samples** (`geoCreator.ts`) because projected bounds are not affine.

### 12.4 Map series options

| Option | Default | Semantics |
|---|---|---|
| `map` | `''` | map name (if not delegating via `geoIndex`) |
| `geoIndex` | – | attach to an existing geo component instead of creating one |
| **`mapValueCalculation`** | `'sum'` | when several `map` series share the same map name, how their per-region values combine: `'sum'` \| `'average'` \| `'max'` \| `'min'` (`mapDataStatistic.ts`) |
| `showLegendSymbol` | `true` | draw a small symbol in the region for legend correspondence (`mapSymbolLayout.ts`) |
| `selectedMode` | `true` | |
| `nameProperty` / `nameMap` | `'name'` | |
| `aspectScale`, `boundingCoords`, `layoutCenter`, `layoutSize`, `center`, `zoom`, `scaleLimit`, `roam` | – | forwarded to the implicit geo |
| `data` | `[{name, value, selected, itemStyle, label, emphasis, select}]` | keyed by **region name** |
| `itemStyle.areaColor` / `borderWidth 0.5` / `borderColor` | – | |
| `labelLayout`, `labelLine` | – | leader lines for cramped regions |

**Actions/events:** `geoRoam`, `geoSelect`/`geoUnSelect`/`geoToggleSelect` (events
`geoselected`/`geounselected`/`geoselectchanged`), plus legacy `mapToggleSelect` via
`createLegacyDataSelectAction`.

---

## 13. `series.lines`

**Draws:** flight-path style lines between coordinate pairs, optionally animated with a moving
"comet" symbol.

| Option | Default | Semantics |
|---|---|---|
| `coordinateSystem` | `'geo'` | \| `'cartesian2d'` \| `'singleAxis'` \| `'geo'`. **There is no built-in great-circle mode** — the "flight arc" look comes from `lineStyle.curveness` on a quadratic bezier in projected space |
| `polyline` | `false` | `false` = each datum is a 2-point line (`coords: [[x0,y0],[x1,y1]]`); `true` = arbitrary-length polyline (GPS tracks). **Polyline mode disables curveness, labels and the per-line animation semantics** |
| `lineStyle.curveness` | `0` | 0..1 bow of the quadratic bezier |
| `symbol` / `symbolSize` | `['none','none']` / `[10,10]` | end-cap symbols (start, end) |
| `effect.show` | `false` | the flying-trail animation |
| `effect.period` | `4` | seconds per traversal |
| `effect.constantSpeed` | `0` | px/s; if > 0 it **overrides `period`** (period computed from measured line length) |
| `effect.delay` | – | number or per-item callback (stagger) |
| `effect.symbol` / `.symbolSize` | `'circle'` / `3` | the moving marker; may be `path://` (a plane icon). **Auto-rotated to the path tangent** — custom paths must point "up" |
| `effect.color` | inherits `lineStyle.color` | |
| `effect.trailLength` | `0.2` | 0..1 comet tail |
| `effect.loop` | `true` | |
| `effect.roundTrip` | `false` | v5.4 — animate back along the path (`__t` runs 0→2 over `2×period`) |
| `large` | `false` | switch to the batched renderer |
| `largeThreshold` | `2000` | |
| `clip` | `true` | clip to cartesian/polar bounds |
| `progressive` / `progressiveThreshold` | 1e4 / 2e4 when `large` | incremental rendering |
| `label` | hidden, `position:'end'` | **not available when `polyline: true`** |

**Trail implementation is browser-specific**: `trailLength` works by *not clearing* that zlevel's
canvas fully between frames (`getZLevelKey` returns the trail length so trailed series get their own
layer with a motion-blur clear). The docs explicitly tell you to put trail series on a separate
`zlevel` with `animation:false` elsewhere. On an immediate-mode canvas you would instead accumulate
into an offscreen buffer and fade it.

**`large: true`** replaces one `Path` per line with a single `LargeLinesPath` holding a flat
`Float32Array` of segments (`segs`), drawn in one `buildPath` loop, with a custom `findDataIndex`
hit-test that walks the array. That is a batching optimization, directly portable in spirit.

---

## 14. Quantified summary

| Family | Series | Distinct layout algorithms | Distinct interaction modes |
|---|---|---|---|
| Radial | pie, radar, gauge, funnel, sunburst, chord | pie angular + rose, radar spokes, gauge arc/band, funnel stack, sunburst radial tree, chord ring+borrow | select-offset, rose, drill (sunburst), multi-needle |
| Hierarchical | sunburst, treemap, tree | squarified packing, Reingold–Tilford/Buchheim, radial tree | drill-down + breadcrumb, expand/collapse, roam |
| Relational | graph, sankey, chord, parallel | force (spring+gravity+N² repulsion), circular, sankey relaxation, parallel axes | node drag, roam, adjacency/trajectory focus, axis brushing, axis expand |
| Geographic | map, lines (+ geo) | GeoJSON/SVG region tessellation, pluggable projection | roam, region select, trail animation |

- **Coordinate systems touched:** cartesian2d, polar, geo, view, radar, parallel, single, calendar,
  matrix, none = 10.
- **Axis-bearing components in this set:** `radar` (N indicator axes), `parallelAxis` (N).
- **Layout modes enumerated:** graph 3 (`none`/`circular`/`force`), tree 2 × 4 orients ×
  2 edge shapes, sankey 3 `nodeAlign` × 2 `orient`, funnel 3 `funnelAlign` × 2 `orient` ×
  4 `sort` modes, pie 3 rose modes (off/radius/area), radar 2 shapes.
- **Roam modes:** 4 (`false`/`true`/`'move'|'pan'`/`'scale'|'zoom'`) × 2 `roamTrigger`.
- **Emphasis focus values across this set:** 8 distinct (`none`, `self`, `series`, `descendant`,
  `ancestor`, `relative`, `adjacency`, `trajectory`).

---

## Porting notes

Classification for an immediate-mode, antialiased BGRABitmap canvas on a desktop window.
**NATURAL** = geometry + fills you already do. **HEAVY** = real algorithm to implement/port.
**BROWSER-BOUND** = depends on DOM/CSS/SVG/WebGL/JS-callbacks/canvas-layer tricks.

### Pie
- Annular sector with `startAngle`/`endAngle`/`clockwise`, `radius:[r0,r]` donut — **NATURAL** (arc + arc + close).
- `padAngle`, `minAngle` with angle redistribution — **NATURAL** (arithmetic; watch the `minAngle+padAngle` combined clamp and the two redistribution branches).
- `roseType:'radius'` / `'area'` — **NATURAL** (`linearMap` on radius).
- `itemStyle.borderRadius` 4-corner sector rounding (inner/outer independently) — **HEAVY** — arc-fillet path construction: you must build the sector as `arc → line → arc → line` with four tangent-circle fillets; percentages resolve against `|r−r0|`.
- `percentPrecision` with sum-to-100 display — **HEAVY** — largest-remainder (Hare quota) apportionment, not naive rounding.
- Label `position` outside/inside/center + 2-segment `labelLine` — **NATURAL**.
- `avoidLabelOverlap` — **HEAVY** — half-plane split, vertical shift-layout with view-rect clamping, **ellipse-implicit x re-solve**, text re-wrap/ellipsis under the new width, then `minTurnAngle`/`maxSurfaceAngle` elbow clamping. This is the single biggest label algorithm in the family.
- `label.alignTo: 'labelLine' | 'edge'` + `edgeDistance` / `bleedMargin` — **HEAVY** (coupled to the above solver).
- `label.rotate: 'radial' | 'tangential' | 'tangential-noflip'` — **NATURAL** (rotated text draw; BGRA can rotate text).
- `selectedMode` + `selectedOffset` translate-out — **NATURAL**.
- `emphasis.scale`/`scaleSize`, `animationType expansion|scale` — **NATURAL** (timer-driven redraw).
- `labelLayout` as a **callback** — **BROWSER-BOUND** (JS function); as an object (`hideOverlap`, `moveOverlap`, dx/dy/rotate/width) — **NATURAL**.
- `cursor` (CSS cursor string) — **BROWSER-BOUND** in spelling; map to LCL `TCursor`.

### Radar
- Component/series split (radar is a coordinate system) — architectural, **NATURAL** but decide it up front.
- `indicator[]` with per-axis min/max/`axisType:'value'|'log'` — **NATURAL**.
- `shape: 'polygon' | 'circle'` grid — **NATURAL** (polyline rings vs. circle/ring).
- `splitArea` / `splitLine` with **color arrays → alternating bands** — **NATURAL** (ring polygons or `Ring` fills).
- Tick alignment across N differently-scaled axes (dummy interval scale + `scaleCalcAlign`) — **HEAVY** (nice-number tick alignment shared across axes).
- `axisName` + `formatter` string template — **NATURAL**; `formatter` as callback — **BROWSER-BOUND**.
- Multiple radars via `radarIndex` — **NATURAL**.

### Gauge
- `startAngle`/`endAngle`/`clockwise` arc track — **NATURAL**.
- `axisLine.lineStyle.color` as `[[stop, color], ...]` band segments — **NATURAL** (N arcs).
- `roundCap` (Sausage/capsule shape) — **NATURAL** (arc + semicircular caps).
- `progress` with `overlap`/`clip`, multi-data — **NATURAL**.
- Built-in tapered pointer path — **NATURAL** (4-point polygon, width-dependent base offset).
- `pointer.icon` as **symbol name** — **NATURAL**; as `path://` **SVG path data** — **HEAVY** (need an SVG path-data parser → BGRA path; worth building once, it recurs in `symbol`, `effect.symbol`, `anchor.icon`).
- `splitLine`/`axisTick` with `%` lengths, `distance` — **NATURAL**.
- `axisLabel.rotate: 'tangential'|'radial'|number` — **NATURAL**.
- `title`/`detail` text blocks with own box/border/padding, `%` offsets — **NATURAL**.
- `valueAnimation` (tween the number, re-run the formatter each frame) — **NATURAL**.

### Funnel
- 4-point quad bands, `minSize`/`maxSize`, `gap`, `sort`, `orient`, `funnelAlign` — **NATURAL** end-to-end.
- 10 label anchor positions with orient-aware fallback — **NATURAL** (verbose but mechanical).
- `sort` as comparator callback — **BROWSER-BOUND** (expose an event/comparator interface instead).

### Sunburst
- Recursive angular subdivision + per-depth ring radii — **NATURAL**.
- `levels[i].radius` overriding one ring — **NATURAL**.
- Roll-up virtual root ring when drilled in — **NATURAL**.
- Drill-down (`nodeClick:'rootToNode'`) with re-layout + animation — **NATURAL** (state + redraw).
- `nodeClick:'link'` (open URL in `target`) — **BROWSER-BOUND** (map to `ShellExecute`/`OpenURL` or an event).
- Default color ramp `lift(parentColor, depthFactor)` — **NATURAL** (HSL lightening).
- Radial/tangential label rotation with flip handling — **NATURAL**.
- `emphasis.focus: 'descendant'|'ancestor'|'relative'` — **NATURAL** (tree walks + opacity).

### Treemap
- **Squarified layout** (Bruls–Huizing–van Wijk, `worst`/`position`/row accumulation, `squareRatio`) — **HEAVY** — but self-contained and well-specified; ~150 lines.
- `sort`, `visibleMin`, `childrenVisibleMin` pruning — **NATURAL**.
- `leafDepth` drill-down + `treemapRootToNode`/`treemapZoomToNode` + `zoomToNodeRatio` — **HEAVY** (view-rect solving for "make this node occupy X% of the viewport", plus rollUp/drillDown direction detection and matched rect morph animation).
- `breadcrumb` (chevron strip, `emptyItemWidth`, own box layout, hover state) — **NATURAL** (it is a small custom-drawn control — exactly your wheelhouse).
- `upperLabel` (parent header band) — **NATURAL**.
- `itemStyle.gapWidth` + `borderWidth` + `borderColorSaturation` (border derived from own fill) — **NATURAL** (HSL math).
- `visualDimension` / `colorMappingBy: 'index'|'value'|'id'` / `colorAlpha` / `colorSaturation` ranges with **parent inheritance** — **HEAVY** (a small visual-mapping engine with an inheritance rule; not hard, but it is a system, not a knob).
- `roam` + `scaleLimit` — **NATURAL**.
- `decal` pattern fills — **NATURAL** (BGRA can tile/hatch), moderate work.

### Tree
- **Reingold–Tilford / Buchheim tidy tree** (`firstWalk`/`apportion` with left/right contour threading, `secondWalk`) — **HEAVY** — this is the canonical hard part; port it faithfully, the naive version produces overlapping subtrees.
- `layout:'radial'` via `radialCoordinate` + depth-scaled separation — **NATURAL** once the tidy layout exists.
- `orient` LR/RL/TB/BT — **NATURAL** (axis swap/mirror).
- `edgeShape:'curve'` (cubic with `curveness`) — **NATURAL**; `'polyline'` with `edgeForkPosition` — **NATURAL**.
- `expandAndCollapse` + `initialTreeDepth` + `collapsed` — **NATURAL** (tree state + relayout).
- `emptyCircle` symbol whose **inner fill encodes collapsed state** — **NATURAL** but a real semantic to preserve.
- `leaves` style block (leaf-only inheritance) — **NATURAL** (style resolution order).
- `roam` + `nodeScaleRatio` (symbols shrink sublinearly with zoom) — **NATURAL**.

### Graph
- `layout:'none'` (explicit x/y) — **NATURAL**.
- `layout:'circular'` with `'value'`/`'symbolSize'` arc spacing + `rotateLabel` — **NATURAL**.
- **Force simulation** (`repulsion`/`gravity`/`edgeLength`/`friction`, friction decay 0.992, converge at <0.01) — **HEAVY** — the physics is ~60 lines and easy, but it is **O(n²) per step** and must be driven by a timer with incremental redraws; you need a frame budget and a "converged, stop the timer" path. Value→repulsion / value→edgeLength `linearMap` mapping included. A Barnes-Hut quadtree is an *optional improvement* ECharts itself does not have.
- `force.initLayout` seeding, `data.fixed`, `links.ignoreForceLayout`, position preservation across data updates — **NATURAL**.
- `autoCurveness` fan for parallel edges (symmetric curvature list, direction-agnostic keying) — **NATURAL** (pure bookkeeping).
- Edge trimming to symbol boundary (curve∩circle by scan + 32-step bisection) — **HEAVY**-lite; numerically simple, but needed or arrowheads sit under the nodes.
- `edgeSymbol` end markers, `edgeLabel` with `position:'middle'` — **NATURAL**.
- `categories[]` feeding legend + style inheritance — **NATURAL**.
- `draggable` node drag (with force warm-up / circular snap-back) — **NATURAL**.
- `emphasis.focus:'adjacency'` — **NATURAL** (adjacency set + blur pass).
- Graph on `geo`/`cartesian2d`/`polar`/`calendar`/`matrix` — **NATURAL** if your coordinate systems are pluggable; architectural decision.

### Sankey
- Layer assignment (BFS depth) + `nodeAlign` justify/left/right + `moveSinksRight` — **NATURAL**.
- **Relaxation loop** (`layoutIterations` × relaxRightToLeft / resolveCollisions / relaxLeftToRight / resolveCollisions with decaying alpha) — **HEAVY**-lite; ~200 lines, deterministic, no numerics beyond weighted means.
- Ribbon path (cubic between stacked endpoints, thickness ∝ value, `curveness`) — **NATURAL**.
- `orient:'vertical'` (whole layout axis-swapped) — **NATURAL** if you parameterize the axis from the start; painful to retrofit.
- `draggable` node with re-stacked ribbons — **NATURAL**.
- `levels[].depth` styling — **NATURAL**.
- `emphasis.focus:'trajectory'` (full upstream+downstream traversal) — **NATURAL** (graph reachability, two BFS).
- `lineStyle.color: 'source'|'target'|'gradient'` — **NATURAL** (BGRA linear gradient along the ribbon).

### Chord (v6)
- Ring of node arcs from a graph, angle ∝ summed edge value — **NATURAL**.
- `minAngle`/`padAngle` **deficit-borrowing solver** — **HEAVY**-lite (three passes with a surplus pre-check; get it wrong and small nodes vanish or the ring overflows).
- Ribbon path `arc → cubic(70% toward center) → arc → cubic → close` — **NATURAL**.
- `itemStyle.borderRadius` on node arcs — **HEAVY** (same sector-fillet work as pie).
- `lineStyle.color:'gradient'` — **NATURAL** (linear gradient between arc midpoints).
- `emphasis.focus:'adjacency'` for both nodes and ribbons — **NATURAL**.

### Parallel
- N evenly spaced axes with independent scales — **NATURAL**.
- Polylines across axes, `smooth` bezier — **NATURAL**.
- Per-axis interval **brushing** with `activeOpacity`/`inactiveOpacity` and AND-combination — **NATURAL** interaction, but it is a real drag-handle widget (create/move/resize/clear an interval per axis).
- `realtime:false` (defer filtering to drag end) — **NATURAL**.
- `layout:'vertical'` — **NATURAL**.
- **`axisExpandable` / `axisExpandWindow` / `axisExpandCount` / slide-trigger areas** — **HEAVY** — a fisheye/lens interaction over axis positions with debounce, rate limiting and three hit zones; genuinely fiddly, and arguably skippable for v1.
- `progressive: 300` incremental rendering — **BROWSER-BOUND** in motivation (JS frame budget); on native you can usually just draw N polylines, or reuse the idea as a paint-chunking guard for huge datasets.

### Map / geo
- GeoJSON parsing → polygon rings with holes, non-zero fill, per-region hit-test — **HEAVY**-lite (parser + point-in-polygon + bbox index).
- **SVG map sources** (`registerMap({svg})`) — **HEAVY** — needs an SVG subset parser (paths, transforms, `viewBox`, `preserveAspectRatio 'xMidYMid'`, named elements → regions). Reuses the `path://` parser from gauge/symbols.
- **`projection: {project, unproject, stream}`** — the *pluggable* form is **BROWSER-BOUND** (it is a JS callback pair, and the documented usage is "pass d3-geo in"). The *capability* is NATURAL if you ship a fixed set of projections (Mercator, equirectangular, Albers/conic-equal-area, Robinson) behind an interface. `stream` (adaptive great-circle resampling of long segments) is **HEAVY** if you want curved graticules/borders.
- Bounding rect under projection via perimeter sampling — **NATURAL**.
- `aspectScale` latitude compensation — **NATURAL**.
- `nameMap`, `nameProperty`, `boundingCoords`, `layoutCenter`/`layoutSize` — **NATURAL**.
- `regions[]` per-region styling + `selectedMode` + select/emphasis/blur — **NATURAL**.
- `mapValueCalculation: sum|average|max|min` across co-registered series — **NATURAL**.
- `showLegendSymbol` region symbols — **NATURAL**.
- `roam` with `scaleLimit`, `preserveAspect*` — **NATURAL**.
- `specialAreas` (inset relocation of sub-regions) — **NATURAL** (extra affine per region).

### Lines
- 2-point lines with `curveness` quadratic bow — **NATURAL**. (Note: **no true great-circle mode exists**; the arc look is bezier-in-projected-space. If you want real geodesics you'd add them — **HEAVY**, and a genuine improvement over ECharts.)
- `polyline: true` multi-point tracks — **NATURAL**.
- End `symbol`/`symbolSize` — **NATURAL**.
- `effect` moving marker: position along the path by arc-length, **auto-rotate to tangent**, `period`, `constantSpeed`, `delay`, `loop`, `roundTrip` — **NATURAL** (timer + curve parameterization; you already have redraw loops).
- `effect.trailLength` comet tail — **BROWSER-BOUND as implemented** (it relies on ECharts giving trailed series their own canvas layer and partially clearing it). Native equivalent: keep an offscreen BGRA buffer per trail layer, alpha-fade it each frame, composite. That is a real re-think, not a port.
- `large: true` (flat `Float32Array` segment batch + custom hit-test) — **NATURAL** in spirit (batch your path building; skip per-line objects).
- `progressive`/`progressiveThreshold` — **BROWSER-BOUND** motivation, see parallel.

### Cross-cutting
- Box layout (`left/top/right/bottom/width/height`, `%` and keywords) — **NATURAL**; you have this.
- `coordinateSystemUsage:'box'` (series inside matrix/calendar cells) — architectural; **NATURAL** but only if coordinate systems are pluggable containers from day one.
- `view` coord system + `RoamController` (drag/wheel, `roamTrigger`, `scaleLimit`, `nodeScaleRatio`) — **NATURAL**; build once, five series get it.
- 4-state style resolution (normal/emphasis/blur/select) with `focus` and `blurScope` — **NATURAL**; build once.
- `decal` pattern fills — **NATURAL** (moderate).
- `labelLayout` object form (`hideOverlap`, `moveOverlap:'shiftX'|'shiftY'`) — **HEAVY**-lite (rect overlap resolution), reusable across every series here.
- All `formatter` / `sort` / `projection` / `labelLayout` **callback** forms — **BROWSER-BOUND** as literal API; expose as Pascal events/interfaces.
- `link` + `target` (hyperlink on click) — **BROWSER-BOUND**; map to an `OnItemClick` event.
- `tooltip` (DOM-rendered by default, `renderMode:'richText'` for canvas) — **BROWSER-BOUND** in its default form; native = a custom-drawn hint window.
- `aria` / decal accessibility layer — **BROWSER-BOUND**.
