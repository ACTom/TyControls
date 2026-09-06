# ECharts 6.1.0 — Core Architecture and Rendering Pipeline

Research pass for a native Object Pascal (FPC/Lazarus LCL) custom-drawn chart control rendering on
BGRABitmap. Everything below was read out of `D:/Projects/echarts` (v6.1.0 source + `dist/echarts.esm.js`,
which bundles the zrender source that is not vendored separately) and `D:/Projects/echarts-doc`
(official option reference).

Scale of the thing being surveyed: **23 series directories** under `src/chart/`, **~35 component
directories** under `src/component/`, **9 registered coordinate systems**, **4 scale types**,
**31 named easing functions**, **606 live demo pages** under `test/*.html`.

---

## 1. The zrender rendering layer

ECharts does not draw to canvas itself. It builds a retained **scene graph of zrender elements** and hands
it to a `Painter`. Everything ECharts calls "rendering" is really "produce/mutate zrender elements".
This is the single most important structural fact for a port: **ECharts is a scene-graph producer, not an
immediate-mode drawer.** A BGRABitmap port either reimplements a small retained scene graph, or
collapses the graph and draws immediately — see Porting notes.

### 1.1 Element class hierarchy

```
Eventful
 └── Transformable ─┐
 └── Element ───────┴── (x,y,rotation,scaleX,scaleY,skewX,skewY,originX/Y,anchorX/Y,
      │                  ignore, silent, draggable, cursor, name, clipPath,
      │                  textContent + textConfig, textGuideLine, states/currentStates)
      ├── Group                  (children container; `childrenRef()`; no own geometry)
      ├── Displayable            (+ z, z2, zlevel, invisible, culling, rectHover, incremental, style)
      │    ├── Path              (abstract; `buildPath(ctx, shape)` + `shape` object)
      │    │    ├── Rect, Circle, Ellipse, Sector, Ring, Polygon, Polyline, Line, Arc, BezierCurve
      │    │    ├── CompoundPath (shape.paths: Path[]; concatenates sub-path proxies)
      │    │    └── (user shapes via `Path.extend({type, shape, buildPath})` / `registerShape`)
      │    ├── ZRImage           (style.image, x, y, width, height, sx/sy/sWidth/sHeight)
      │    ├── ZRText            (rich text container; owns child TSpan displayables)
      │    │    └── TSpan        (one measured text run)
      │    └── IncrementalDisplayable
      └── (Gradient / Pattern are style values, not elements)
```

`Gradient` → `LinearGradient` (x, y, x2, y2, global?) and `RadialGradient` (x, y, r, global?).
When `global` is false the coordinates are fractions of the element's bounding rect; when true they are
absolute pixels. `Pattern` takes an image or a canvas plus `repeat`, `x`, `y`, `rotation`,
`scaleX`, `scaleY`.

### 1.2 Built-in shape primitives and their `shape` parameters

| Type | `shape` fields |
|---|---|
| `rect` | `x, y, width, height` (+ optional `r` corner radii: number or 1/2/4-array) |
| `circle` | `cx, cy, r` |
| `ellipse` | `cx, cy, rx, ry` |
| `sector` | `cx, cy, r0, r, startAngle, endAngle, clockwise, cornerRadius` |
| `ring` | `cx, cy, r, r0` |
| `polygon` | `points: [x,y][]`, `smooth` (0..1 or `'spline'`), `smoothConstraint` |
| `polyline` | `points`, `percent` (partial draw 0..1), `smooth`, `smoothConstraint` |
| `line` | `x1, y1, x2, y2, percent` |
| `arc` | `cx, cy, r, startAngle, endAngle, clockwise` |
| `bezierCurve` | `x1, y1, x2, y2, cpx1, cpy1, cpx2, cpy2` (quadratic if cp2 null), `percent` |
| `compoundPath` | `paths: Path[]` |
| `image` | (style) `image, x, y, width, height` |
| `text` | (style) `text, font, textAlign, ..., rich` |
| `group` | `children` |

These same names are exposed at option level in `graphic.elements[].type` and in
`series.custom.renderItem()` return values (`en/option/partial/zr-graphic.md`), so they are a
**user-visible API surface**, not just an internal detail. `path` accepts `shape.pathData` / `shape.d`
(an SVG path `d` string) plus `shape.layout: 'center' | 'cover'`.

`percent` on `line`/`polyline`/`bezierCurve` and `style.strokePercent` on any `Path` give partial-stroke
drawing — this is what "line grows from left to right" animation actually uses. It is implemented in
`PathProxy.rebuildPath(ctx, percent)`, which walks the recorded command buffer and truncates the last
segment by arc-length interpolation.

### 1.3 Style model

`DEFAULT_COMMON_STYLE` (all displayables):
`shadowBlur=0, shadowOffsetX=0, shadowOffsetY=0, shadowColor='#000', opacity=1, blend='source-over'`.

`DEFAULT_PATH_STYLE` adds:
`fill='#000', stroke=null, strokePercent=1, fillOpacity=1, strokeOpacity=1, lineWidth=1,
lineDash, lineDashOffset=0, lineCap='butt', lineJoin, miterLimit=10, strokeNoScale=false,
strokeFirst=false`.

`strokeNoScale` is notable: it divides `lineWidth` by the element's global scale so hairlines stay
1px through a zoom transform. `strokeFirst` reverses fill/stroke order so a thick stroke does not eat
into the fill.

Text style: `text, font (or fontStyle/fontWeight/fontSize/fontFamily), fill, stroke, lineWidth,
align, verticalAlign, lineHeight, width, height, overflow ('truncate' | 'break' | 'breakAll' | 'none'),
lineOverflow ('truncate'), ellipsis, truncateMinChar, padding, backgroundColor, borderColor, borderWidth,
borderRadius, borderDashOffset, textShadow*, rich{...}`. Rich text is a per-tag style dictionary keyed by
`{tagName|content}` markers in the string; it produces a `ZRText` group of `TSpan` children with its own
mini line-box layout (measure → wrap → stack lines → align each run).

### 1.4 Transforms

`TRANSFORMABLE_PROPS = ['x','y','originX','originY','anchorX','anchorY','rotation','scaleX','scaleY','skewX','skewY']`.
Each element composes a 2x3 affine matrix (`zrender/src/core/matrix`), multiplied down the Group chain
into `el.transform`. On canvas this becomes `ctx.setTransform(dpr*m0, dpr*m1, dpr*m2, dpr*m3, dpr*m4, dpr*m5)`.
Hit-testing goes the other way through `transformCoordToLocal`.

### 1.5 The display list, and z / zlevel / z2

`Storage.updateDisplayList()` walks the root Groups depth-first, flattens every non-Group into a linear
array, and stable-sorts it (timsort) with:

```
zlevel  (primary)  →  z  (secondary)  →  z2  (tertiary)
```

- **`zlevel`** additionally selects a **separate `<canvas>` layer** in the canvas painter. Different
  zlevels never share a canvas. This is the "put the animated stuff on its own canvas" optimization.
- **`z`** orders within a layer, no new canvas.
- **`z2`** orders within a `z`, set programmatically by chart views (per-element).

ECharts sits on top of this with `allocateZlevels(ecModel)` in `src/core/echarts.ts`: if *any* component
declares a `zlevelKey`, it re-packs zlevels so that components sort before series and each distinct key
gets its own layer, and then `updateZ()` / `traverseUpdateZ()` pushes the model's `z`/`zlevel` down the
element subtree, tracking a running `maxZ2` so labels land above glyphs.

Auxiliary elements attached to an element (`textContent`, `textGuideLine`, decal element) are appended to
the display list right after their host, inheriting its clip path stack.

### 1.6 Clipping

Clipping is per-element and **inherited**: `el.setClipPath(path)`. During display-list construction,
`Storage._updateAndAddDisplayable` accumulates `el.__clipPaths` = parent's clip stack + this element's own
chain (a clip path may itself have a clip path). `el.ignoreClip = true` opts out.

On canvas, `updateClipStatus()` replays the whole stack: for each clip path, set its transform,
`beginPath()`, `buildPath()`, `ctx.clip()`. Clip paths are arbitrary paths, not just rects. The painter
tracks `isClipPathChanged(clipPaths, prevClipPaths)` and only does `ctx.save()/restore()` + re-clip when
the stack identity actually changes between consecutive elements in the sorted list — a real
optimization, because the list is sorted so same-clip elements cluster.

`scope.allClipped` short-circuits: if any clip path has zero area, the element is skipped entirely.

### 1.7 Layers, dirty rectangles, hover layer

**Layers.** `CanvasPainter` keeps a map of zlevel → `Layer` (a `<canvas>` + 2D context). `getLayer(zlevel)`
/ `_ensureLayer(zlevel, zlevel2, virtual)`. A layer carries: `clearColor`, `motionBlur` (boolean),
`lastFrameAlpha` (0.7 default — trails effect by compositing the previous frame at reduced alpha),
`maxRepaintRectCount = 5`. `zr.configLayer(zlevel, config)` exposes these.
`_singleCanvas` mode collapses everything to one canvas; `_needsManuallyCompositing` mode renders each
layer into an offscreen "virtual" canvas and blits them in order.

**Dirty rectangles.** Opt-in: `echarts.init(dom, theme, {useDirtyRect: true})`; **default `false`**.
`Layer.createRepaintRects(displayList, prevList, viewW, viewH)` implements:

1. For each element in the current list: if it was rendered and is now dirty (or should no longer be
   painted), add its **previous** paint rect; if it is dirty or newly appearing, add its **current**
   paint rect.
2. For each element in the previous list that is gone or no longer paintable, add its previous rect.
3. Merge: a new rect that intersects an existing merged rect is unioned into it. Once the pool reaches
   `maxRepaintRectCount` (5), it goes "full" and every further rect is unioned into whichever existing
   rect minimizes `area(union) - area(a) - area(b)` (a greedy min-added-area heuristic).
4. Repeat a union-pass over the pool until no two rects intersect.

Painting then clips to each rect in turn and only brushes elements whose `getPaintRect()` intersects it.
`getPaintRect()` is the bounding rect expanded for stroke width, shadow blur/offset, and transform.

**Hover layer.** `HOVER_LAYER_ZLEVEL` is a dedicated top layer. `_paintHoverList()` redraws only elements
flagged `__inHover` with their `__hoverStyle`, so a hover highlight over 100k elements does not repaint
the base. ECharts arms this automatically via `hoverLayerThreshold` (global default **3000** elements) in
`updateHoverLayerStatus()`, and also for elements inside progressive/incremental rendering.

### 1.8 The paint loop and batching

`CanvasPainter.refresh()` → `storage.getDisplayList(true)` → `_updateLayerStatus()` → `_paintList()` →
`_doPaintList()` per layer → `_paintPerCursor()` (per dirty rect, or once) → `_paintPerCursorInRect()`
which loops `brush(ctx, el, scope)`.

`brush()` per element:
1. `shouldBePainted()` culling: `ignore`, `invisible`, `style.opacity === 0`, `culling` + off-viewport,
   degenerate transform, zero-area clip.
2. If the clip stack changed → `restore()` + `save()` + replay clips.
3. If the transform changed → `setContextTransform`.
4. Bind style, but **diffed against the previous element's style** (`bindPathAndTextCommonStyle`) — only
   changed context properties are assigned.
5. Dispatch by draw type: `DRAW_TYPE_PATH | IMAGE | TEXT | INCREMENTAL`.

**Path batching.** `canPathBatch(style)` returns true when the element has exactly one of fill/stroke,
that paint is a plain string colour, no `lineDash`, `strokePercent === 1`, and no separate
fill/stroke opacity. Consecutive batchable elements with identical style accumulate into **one**
`ctx.beginPath()` … many sub-paths … single `ctx.fill()`/`ctx.stroke()` (`flushPathDrawn`). This is the
main reason a 100k-point scatter is survivable in a browser.

**Shape caching.** Each `Path` owns a `PathProxy` — a flat `Float32Array` command buffer with opcodes
`M=1, L=2, C=3, Q=4, A=5, Z=6, R=7`. `buildPath()` is only re-run when `SHAPE_CHANGED_BIT` is set;
otherwise `rebuildPath(ctx, 1)` replays the buffer. `setScale(sx, sy, segmentIgnoreThreshold)` lets the
proxy drop line segments shorter than a pixel at the current scale.

`_paintPerCursorInRect` also enforces a **15 ms budget** per frame for incremental layers; it breaks out
and continues on the next `requestAnimationFrame`.

### 1.9 Hit-testing (`contain`)

`zr.handler.findHover(x, y)` walks the display list **back to front** and calls
`el.rectHover ? el.rectContain(x,y) : el.contain(x,y)`. For each candidate it then walks up the parent
chain checking every inherited clip path (`clipPath.contain(x, y)`) and collecting `silent` flags. A
`silent` hit records `topTarget` but keeps searching for a non-silent target.

`Path.contain(x, y)`:
1. Inverse-transform the point to local space.
2. Reject on bounding rect.
3. If stroked: `containStroke(pathProxy, lineWidth/lineScale, x, y)` — per-segment distance tests
   (point-to-segment, point-to-cubic, point-to-quadratic, point-to-arc). If the path has no fill,
   `lineWidth` is widened to `strokeContainThreshold` so thin lines are still clickable.
4. If filled: `containPath()` — a **non-zero winding number** test that accumulates
   `windingLine / windingQuadratic / windingCubic / windingArc` contributions across the command buffer.

**Coarse pointer.** `useCoarsePointer` (default `'auto'` → on when touch events are supported) with
`pointerSize` (default 44 px). If nothing is hit exactly, zrender collects elements whose bounding rects
intersect a 44×44 box around the pointer, then re-probes on a **polar spiral** (`r += 4`,
`theta += π/12`) until something is hit. `el.ignoreCoarsePointer` opts out.

Click synthesis: `click` only fires if `mousedown` and `mouseup` hit the same element **and** the pointer
moved ≤ 4 px.

### 1.10 Canvas renderer vs SVG renderer

| | Canvas (`renderer: 'canvas'`, default) | SVG (`renderer: 'svg'`) |
|---|---|---|
| Output | N `<canvas>` elements, one per zlevel | one `<svg>` with a virtual-DOM diff (`patch(oldVNode, newVNode)`) |
| Layering | real, per `zlevel` | none — z-order is document order only |
| Dirty rect | yes (`useDirtyRect`) | no (vdom diff instead) |
| Hover layer | yes | no (`updateHoverLayerStatus` returns early if `painter.type !== 'canvas'`) |
| Progressive | yes (`Scheduler.restorePipelines` gates `progressive` on `painter.type === 'canvas'`) | **disabled** |
| Gradients/patterns/clips | context objects | `<defs>` entries with generated ids |
| Animation | JS-driven per frame | JS per frame, **or** emitted as CSS `@keyframes` for SSR |
| Text | measured via canvas `measureText` | `<text>`/`<tspan>` |
| SSR | `getDataURL()` | `renderToString()` / `renderToSVGString()`, with `ssr` data attributes carrying `series_index`/`data_index` |

**Consequence for the port: progressive rendering, layered canvases, dirty-rect and the hover layer are
canvas-renderer features. They are performance mechanisms, not visual features. A native port can pick
its own.**

---

## 2. Model / View / Component architecture

### 2.1 The four model classes

| Class | File | Role |
|---|---|---|
| `Model` | `src/model/Model.ts` | Base: holds an `option` object, `get(path, ignoreParent)`, `getShallow`, `getModel(path)` returning a child `Model`, plus mixins (`lineStyle`, `itemStyle`, `areaStyle`, `textStyle`, `palette`, `dataFormat`). Option inheritance walks `parentModel`. |
| `ComponentModel` | `src/model/Component.ts` | One per component instance. Carries `mainType` (`'xAxis'`), `subType` (`'category'`), `componentIndex`, `id`, `name`, `uid`, `defaultOption`, static `dependencies`, static `layoutMode` ('box' → merge left/right/top/bottom/width/height as a unit), `preventAutoZ`. |
| `SeriesModel` | `src/model/Series.ts` | `ComponentModel` + data. `getInitialData()` (the extension hook that turns option data into a `SeriesData`), `getData()/setData()`, `dataTask` (the head of its pipeline), `pipelineContext`, `coordinateSystem`, `getProgressive()`, `getProgressiveThreshold()`, `isAnimationEnabled()`, `getColorFromPalette()`. |
| `GlobalModel` | `src/model/Global.ts` | The whole `option`. Owns the component instance map, `eachSeries`, `eachComponent`, `getComponent(mainType, idx)`, `queryComponents(finder)`, `restoreData()`, the colour palette, `getUpdatePayload()`. |

### 2.2 How `option` becomes models

```
setOption(option, {notMerge, replaceMerge, lazyUpdate, silent, transition})
  → OptionManager.setOption()
        · run every registered preprocessor (`registerPreprocessor`) — legacy option rewriting
        · split into baseOption / timelineOptions[] / media[] (+ mediaDefault)
  → OptionManager.mountOption()
        · pick timeline option by `timeline.currentIndex`, merge onto baseOption
        · evaluate media queries against (width, height, aspectRatio) → merge matching ones in order
  → GlobalModel._mergeOption()
        · for each mainType, diff incoming option array vs existing components by id/name/index
          (`mappingToExists`), then create / mergeOption / remove
        · `ComponentModel.getClass(mainType, subType)` from the registry, `new Cls(...)`, `init()`
        · topological order by static `dependencies` (`enableTopologicalTravel`)
```

**Media query** is a real, non-CSS feature: `option.media = [{query: {minWidth, maxWidth, minHeight,
maxHeight, minAspectRatio, maxAspectRatio}, option: {...}}, ...]`. `applyMediaQuery` matches
`min`/`max` prefixes against `{width, height, aspectratio}` of the chart canvas. Later matching entries
win. This is responsive layout implemented entirely inside ECharts — no CSS involved.

**Timeline** likewise: `option.options[]` swapped by index, driven by the `timeline` component.

### 2.3 The two view classes

| | `ComponentView` (`src/view/Component.ts`) | `ChartView` (`src/view/Chart.ts`) |
|---|---|---|
| Owns | `group: Group`, `uid` | `group: Group`, `uid`, **`renderTask`** |
| Lifecycle | `init, render, dispose, updateView, updateLayout, updateVisual, remove?` | `init, render, highlight, downplay, remove, dispose, updateView, updateLayout, updateVisual` |
| Optional | `updateTransform() → {update:true}`, `filterForExposedEvent`, `findHighDownDispatchers`, `focusBlurEnabled`, `toggleBlurSeries` | `incrementalPrepareRender`, `incrementalRender(params,…)`, `updateTransform`, `containPoint`, `filterForExposedEvent`, `ignoreLabelLineUpdate` |
| Traversal | `eachRendered(cb)` | `eachRendered(cb)` — in progressive mode visits only the newly added elements |

A view instance is bound to a model instance by `__viewId`; `__alive` is reset each render pass and
non-alive chart views get `remove()`d.

**`ChartView.renderTask`** is the key structural piece: a chart's `render()` is not called directly by
the framework. It is wrapped in a `Task` whose `plan` is `createRenderPlanner()` (returns `'reset'`
whenever `large` or `progressiveRender` mode flips) and whose `reset` picks the method to call:

```
progressiveRender          → 'incrementalPrepareRender'  then per-chunk 'incrementalRender'
payload declares a method  → 'updateView' | 'updateVisual' | 'updateLayout'
otherwise                  → 'render'   (run inside progress, with forceFirstProgress: true,
                                         so `chart.appendData` can keep feeding it)
```

### 2.4 The registry / extensibility contract

`src/extension.ts` exposes exactly this set to `echarts.use(installerFn)`:

| Register fn | Registers | Notes |
|---|---|---|
| `registerComponentModel(Cls)` | a `ComponentModel` subclass | keyed by `type` = `'mainType.subType'` |
| `registerComponentView(Cls)` | a `ComponentView` subclass | |
| `registerSeriesModel(Cls)` | a `SeriesModel` subclass | must implement `getInitialData` |
| `registerChartView(Cls)` | a `ChartView` subclass | must implement `render` |
| `registerCustomSeries(type, renderItem)` | a named custom series | v6 addition |
| `registerSubTypeDefaulter(mainType, fn)` | picks a subType when option omits it | e.g. xAxis → `'category'` |
| `registerCoordinateSystem(type, creator)` | `{create(ecModel, api) → masters[], dimensions?}` | |
| `registerLayout([priority], handler)` | a stage handler with `visualType: 'layout'` | default priority 1000 |
| `registerVisual([priority], handler)` | a stage handler with `visualType: 'visual'` | default priority 3000 |
| `registerProcessor([priority], handler)` | a data-processing stage handler | default priority 2000 |
| `registerPreprocessor(fn)` | raw-option rewriter, runs before models exist | |
| `registerAction(info, handler)` | an action type + emitted event + update method | |
| `registerTransform(t)` | a `dataset.transform` type | |
| `registerLoading(name, fn)` | a loading animation | |
| `registerMap(name, geoJson\|svg, specialAreas)` | map geometry | |
| `registerPostInit(fn)` / `registerPostUpdate(fn)` | global hooks | |
| `registerUpdateLifecycle(name, fn)` | hook into `lifecycle` events | |
| `registerPainter(type, Ctor)` | a zrender painter (canvas/svg) | |
| `registerImpl(name, impl)` | pluggable internal impls (v6; e.g. scale-break impl) | |

A **stage handler** (`StageHandler` in `src/util/types.ts`) is either:
- `{seriesType | getTargetSeries, reset(seriesModel, ecModel, api, payload) → progressFn | progressFn[]}`
  — becomes one `Task` per series, spliced into that series' pipeline; or
- `{overallReset(ecModel, api, payload), getTargetSeries?, createOnAllSeries?, dirtyOnOverallProgress?}`
  — one global task with per-series "stub" tasks that feed it.
Plus `performRawSeries` (run even for legend-filtered series) and `visualType: 'layout' | 'visual'`.

### 2.5 Actions and update modes

`registerAction({type, event, update, action, refineEvent, publishNonRefinedEvent}, handler)`.
`update` is a string of the form `[<componentMainType>:]<updateMethodName>`; the optional component
prefix restricts the update to that component's view (`updateDirectly`) instead of a full pass.

Update methods (`updateMethods` in `src/core/echarts.ts`):

| Name | What it re-runs |
|---|---|
| `prepareAndUpdate` | rebuild views (`prepare`) then full `update` |
| `update` | **the full pipeline** (see §3) |
| `updateTransform` | ask each view for `updateTransform()`; only re-run visual tasks for views that decline; used by roam/pan/zoom |
| `updateView` | re-run visual+layout tasks, re-render, but no data processing |
| `updateVisual` | clear all data visuals, re-run only `visualType: 'visual'` tasks, call `updateVisual` on views |
| `updateLayout` | deprecated alias for `update` |
| `none` | dispatch the event only |

Built-in actions include `highlight`, `downplay`, `select`, `unselect`, `toggleSelect`, `legendSelect`
family, `dataZoom`, `geoRoam`/`*Roam`, `brush`/`brushSelect`/`brushEnd`, `timelineChange`,
`timelinePlayChange`, `restore`, `changeMagicType`, `changeDataView`, `updateAxisPointer`,
`treeExpandAndCollapse`, `treemapZoomToNode`/`treemapRootToNode`, `sunburstRootToNode`,
`focusNodeAdjacency`, `dragNode`, `changeAxisOrder`, `takeGlobalCursor`,
`expandAxisBreak`/`collapseAxisBreak`/`toggleAxisBreak` (v6).

Actions can be **batched** (`payload.batch = [...]`) and are queued if dispatched during a cycle
(`_pendingActions`, flushed by `flushPendingActions`).

### 2.6 Lifecycle hook points

`src/core/lifecycle.ts` — an `Eventful` with exactly these events:
`afterinit`, `coordsys:aftercreate`, `series:beforeupdate`, `series:layoutlabels`,
`series:transition`, `series:afterupdate`, `afterupdate`.
Label layout and universal transition are both implemented as listeners on these, not as hard-coded steps.

---

## 3. The full render pipeline: `setOption` → pixels

`updateMethods.update()` in `src/core/echarts.ts` is the canonical sequence:

```
 0. resetCachePerECFullUpdate(ecModel); ecModel.setUpdatePayload(payload)
 1. scheduler.restoreData(ecModel, payload)
       · ecModel.restoreData() → each series recreates its SeriesData from raw source
       · mark every pipeline task dirty; mark every overall task dirty
 2. scheduler.performSeriesTasks(ecModel)     — run each series' head dataTask to completion
 3. coordSysMgr.create(ecModel, api)          — NEW coordinate system objects, every update
       · "non-series box" coord systems first (matrix, calendar) — others can lay out on top of them
       · then normal coord systems (cartesian2d/grid, polar, geo, parallel, single, radar, graphView)
    → lifecycle.trigger('coordsys:aftercreate')
 4. scheduler.performDataProcessorTasks(ecModel, payload)   — blocking (runs to the end)
 5. updateStreamModes(this, ecModel)          — decide progressive/large per series (needs filtered counts)
 6. coordSysMgr.update(ecModel, api)          — axis scale extents from the processed data
 7. clearColorPalette(ecModel)
 8. scheduler.performVisualTasks(ecModel, payload)          — layout + visual stages, chunked
 9. zr.setBackgroundColor(option.backgroundColor); zr.setDarkMode(option.darkMode)
10. render():
       allocateZlevels(ecModel)
       renderComponents():  for each ComponentView → clearStates, view.render(), updateZ, updateStates
       renderSeries():
            lifecycle.trigger('series:beforeupdate')
            for each series: clearStates → renderTask.perform(performArgs) → group.silent, updateBlend,
                             updateSeriesElementSelection
            lifecycle.trigger('series:layoutlabels')     ← global label layout / overlap resolution
            lifecycle.trigger('series:transition')       ← universal transition + morphing
            for each series: updateZ, updateStates       (after labels, so label z2 is known)
            updateHoverLayerStatus()
            lifecycle.trigger('series:afterupdate')
       remove chart views whose __alive is false
11. lifecycle.trigger('afterupdate')
12. zr.flush()   (unless lazyUpdate / ssr)
```

### 3.1 Stage priorities

`PRIORITY` (exported; extensions place themselves relative to these):

**Processors** (lower runs first)
| Priority | Name | Who |
|---|---|---|
| 800 | `SERIES_FILTER` | legend filtering out whole series |
| 900 | (`PRIORITY_PROCESSOR_DATASTACK`) | `dataStack` — computes stacked values |
| 920 | `AXIS_STATISTICS` | v6 axis statistics (e.g. min positive gap for bar width on time axes) |
| 1000 | `FILTER` | `dataZoom` `AxisProxy` filtering |
| 2000 | (default for `registerProcessor`) | |
| 5000 | `STATISTIC` / `STATISTICS` | `dataSample` etc. |

**Visual + layout** (one ordered list; `visualType` tags each entry)
| Priority | Name | Typical occupant |
|---|---|---|
| 1000 | `LAYOUT` | default for `registerLayout` — bar/pie/funnel/points/sankey/tree/treemap/… |
| 1100 | `PROGRESSIVE_LAYOUT` | layouts that must run chunk-by-chunk |
| 2000 | `GLOBAL` | `seriesStyleTask`, `seriesSymbolTask` (series-level colour/symbol) |
| 3000 | `CHART` | default for `registerVisual` |
| 4000 | `COMPONENT` | `visualMap` |
| 4500 | `CHART_ITEM` | `dataStyleTask`, `dataColorPaletteTask`, `dataSymbolTask` (per-item visuals) |
| 4600 | `POST_CHART_LAYOUT` | layouts that need per-item visuals first — graph circular, chord, scatter jitter |
| 5000 | `BRUSH` | `brush` visual, parallel visual |
| 6000 | `ARIA` | accessibility decal/label generation |
| 7000 | `DECAL` | decal (pattern) generation |

Registration order within the same priority is preserved (timsort is stable).

### 3.2 The Scheduler and pipelines

`src/core/Scheduler.ts`. **One pipeline per series**, keyed by `seriesModel.uid`:

```
Pipeline = { id, head, tail, threshold, progressiveEnabled, blockIndex, step, count, context }
```

`restorePipelines()` creates them and pipes `seriesModel.dataTask` in as the head.
`step = Math.round(series.progressive || 700)`.
`progressiveEnabled = (painter.type === 'canvas') && series.getProgressive() && !view.preventIncremental()`.

`prepareStageTasks()` then walks all registered handlers and, for each:
- `reset` handler → one `SeriesTask` per target series, `_pipe`d onto that series' pipeline;
- `overallReset` handler → one `OverallTask` **outside** the pipelines, plus a `StubTask` inside each
  target pipeline that acts as its agent (stubs run first, then the overall task).

`prepareView()` pipes each `ChartView.renderTask` onto the tail, and sets
`renderTask.__block = !view.incrementalPrepareRender`.

`plan()` walks each pipeline tail→head and records `blockIndex` = the index of the last blocking task.
Everything **after** `blockIndex` can run progressively; everything at or before it must run to completion.

`getPerformArgs(task, isBlock)` returns `{step, modBy, modDataCount}` — `step` is `null` (unlimited) for
blocking tasks and `pipeline.step` for progressive ones.

### 3.3 The frame loop

`zr.animation.on('frame', ec._onframe)`. Each frame:
1. `applyChangedStates()` — apply pending emphasis/blur/select state changes to elements.
2. If a `lazyUpdate` `setOption` is pending → run the whole `update()` then `zr.flush()`.
3. Else if `scheduler.unfinished` → run the streaming loop with a **1 ms budget**
   (`TEST_FRAME_REMAIN_TIME = 1`):
   ```
   do {
     performSeriesTasks; performDataProcessorTasks; updateStreamModes;
     performVisualTasks; renderSeries(payload='remain')
   } while (remainTime > 0 && scheduler.unfinished)
   ```
   Coordinate systems are deliberately **not** re-updated per frame — the extent is frozen at the first
   frame of a progressive render.

`zr.flush()` is throttled to 17 ms (`_throttledZrFlush`). A `'rendered'` event fires on every real paint;
`'finished'` fires when animation, pending updates, scheduler work and pending actions are all drained.

---

## 4. Progressive / incremental rendering

### 4.1 Options

| Option | Default | Meaning |
|---|---|---|
| `progressive` | 400 global; per series: bar/candlestick **3000**, parallel 300, line/effectScatter/pictorialBar/treemap **0** (disabled) | elements rendered per frame chunk |
| `progressiveThreshold` | 3000 global; candlestick 10000 | data count above which progressive turns on |
| `progressiveChunkMode` | `'sequential'`; bar & candlestick default `'mod'` | `'sequential'` slices by index; `'mod'` interleaves so each chunk is spread across the whole dataset (visually much better while streaming) |
| `large` | false; candlestick **true** | switch to a simplified, single-element bulk renderer |
| `largeThreshold` | 2000; bar 400, candlestick 600 | data count above which `large` engages |
| `hoverLayerThreshold` | 3000 | element count above which hover uses a dedicated layer |
| `animationThreshold` | 2000 | element count above which animation is skipped entirely |

`preparePipelineContext` computes, per series per cycle:
```
progressiveRender = pipeline.progressiveEnabled && view.incrementalPrepareRender && dataLen >= threshold
large             = series.large && dataLen >= series.largeThreshold
modDataCount      = (progressiveChunkMode === 'mod') ? dataLen : null
```

Only **7 views** implement `incrementalPrepareRender`/`incrementalRender`: bar, candlestick, custom,
heatmap, lines, parallel, scatter. Only **5 series** implement `large`: bar, candlestick, lines, scatter
(+ `BaseBarSeries`). In `large` mode a series draws a single custom `Path` (`LargeSymbolPath`,
`LargeLinesPath`) with its own `buildPath` over a typed-array point buffer and its own `contain()` —
per-item styling is unavailable, which is exactly what the docs warn about.

### 4.2 `src/core/task.ts` — the stream primitive

A `Task` is `{plan?, reset?, count?, onDirty?}` linked to at most one upstream and one downstream task
(`pipe`). State: `_dirty, _dueIndex, _dueEnd, _outputDueEnd, _settedOutputEnd, _modBy, _modDataCount`.

`perform({step, skip, modBy, modDataCount})`:
1. Pull `context.data = context.outputData = upstream.context.outputData` if dirty.
2. `plan()` may return `'reset'`. A change of `modBy`/`modDataCount` also forces `'reset'`.
3. On reset: `_doReset()` clears cursors, calls `reset(context)` to obtain the `progress` callback(s)
   (optionally `{forceFirstProgress, progress}`), and dirties the downstream.
4. `_dueEnd` = upstream's `_outputDueEnd`, or `count(context)` for a head task.
5. Run `progress({start, end, count, next}, context)` for `start = _dueIndex`,
   `end = min(_dueIndex + step, _dueEnd)`.
6. `_outputDueEnd = _settedOutputEnd ?? end`.
7. Return `unfinished()` = `_progress && _dueIndex < _dueEnd`.

The **`mod` iterator** is the interesting bit:
```
dataIndex = (current % winCount) * modBy + ceil(current / winCount)
```
with `winCount = ceil(modDataCount / modBy)` — it enumerates the same index set as `0..n-1` but in an
interleaved order, so chunk 1 already samples the whole data range.

Dirty propagates downstream. `chart.appendData({seriesIndex, data})` appends to the raw `DataStore` and
re-performs the pipeline from the append point, which is why `render` is invoked from inside `progress`
with `forceFirstProgress: true`.

`SeriesData`/`DataStore` (`src/data/DataStore.ts`) is columnar: one typed array per dimension
(`Float64Array` for float/time, `Int32Array` for int/ordinal), with per-dimension `rawExtent` maintained
incrementally, plus an optional `_indices` permutation for filtered/sorted views. That columnar,
append-friendly layout is what makes streaming cheap.

---

## 5. Scales — `src/scale/*`

Four concrete types (`Scale.registerClass`): **`ordinal`, `interval`, `time`, `log`**.
(Axis `type` values are `'category' | 'value' | 'time' | 'log'`, mapping to ordinal/interval/time/log.)

`abstract class Scale` contract:
```
parse(val) → number             // no side effects; NaN = invalid
getTicks(opt) → ScaleTick[]     // {value, level?, break?, time?, ...}
getMinorTicks(splitNumber) → number[][]
getLabel(tick) → string
getExtent() / setExtent()       // via ScaleMapper
normalize(val) / scale(t)       // value ↔ [0,1]
contain(val)
isBlank() / setBlank()          // "no data" → don't draw ticks
```
`ScaleMapper` (`src/scale/scaleMapper.ts`) sits underneath and handles the extent plumbing plus **axis
breaks**; `BreakScaleMapper` composes an extra transform layer.

### 5.1 "Nice" tick generation

`nice(val, mode)` in `src/util/number.ts` is the core rounding primitive. Decompose `val = f × 10^e`
with `1 ≤ f < 10`, then snap `f`:

| `f` range | `NICE_MODE_ROUND` (`mode` truthy) | default (`mode` falsy) |
|---|---|---|
| `< 1.5` / `< 1` | 1 | 1 |
| `< 2.5` / `< 2` | 2 | 2 |
| `< 4` / `< 3` | 3 | 3 |
| `< 7` / `< 5` | 5 | 5 |
| else | 10 | 10 |

`NICE_MODE_MIN` forces `f → 1`. So the nice-interval ladder is **1, 2, 3, 5, 10** per decade.

`intervalScaleNiceTicks(extent, spanWithBreaks, splitNumber, minInterval, maxInterval)`:
```
interval = nice(spanWithBreaks / splitNumber, ROUND)
clamp to [minInterval, maxInterval]
precision = getPrecision(interval) + 2
niceTickExtent = [ round(ceil(extent0/interval)*interval, precision),
                   round(floor(extent1/interval)*interval, precision) ]
```
`increaseInterval(niceInterval)` steps the ladder up: 1→2, 2→3, 3→5, 5→10 (used when labels collide).

`intervalScaleEnsureValidExtent` handles degenerate extents: equal min/max expand by ±|v|/2 (or to
`[-1, 1]` / `[0, 1]` at zero, depending on `containShape`); non-finite extents fall back to `[0, 1]`;
reversed extents are swapped.

### 5.2 Minor ticks

`getMinorTicks(splitNumber)` subdivides every *pair* of adjacent major ticks into `splitNumber`
sub-intervals, emitting the interior points only, dropping any that fall outside the extent, and skipping
pairs adjacent to an axis break. `minorTick.splitNumber` default **5**, valid range (0, 100).

### 5.3 The four scales

**OrdinalScale.** Backed by `OrdinalMeta` (categories array + reverse map). `parse(str)` → ordinal number;
extent is `[startOrdinal, endOrdinal]`. `ordinalScaleCreateTicks(scale, categoryInterval, addItem)` steps
by `categoryInterval + 1`, aligns the start tick to a multiple of the step (so labels don't jitter while
panning), and always force-includes the extent boundaries with `offInterval: true` so the min/max label
policy can decide separately.

**IntervalScale.** Holds `{interval, intervalPrecision, niceExtent}`. `getTicks()` walks from
`niceExtent[0]` by `interval` up to `niceExtent[1]`, optionally expanding one step beyond each end
(`expandToNicedExtent`), then appends the true extent ends. Includes a safety guard against runaway loops.
`getLabel(tick, {precision:'auto'|number, pad})`.

**TimeScale.** `scaleIntervals` (ported from d3) is a 12-entry ladder of `[unit, approxMilliseconds]`:
`second 1s · minute 1m · hour 1h · quarter-day 6h · half-day 12h · day 1.2d · half-week 3.5d ·
week 7d · month 31d · quarter 95d · half-year 182.5d · year 365d`.
`primaryTimeUnits = [year, month, day, hour, minute, second, millisecond]`;
`timeUnits` adds `half-year, quarter, week, half-week, half-day, quarter-day`.
Ticks are generated at calendar boundaries for the chosen unit, and each tick carries a **`level`**.
Level 0 = ordinary label, higher levels = "first tick of a bigger unit" and get a different template
(and by default `rich.primary` bold styling). The formatter option is a **dictionary keyed by
[lowerUnit][upperUnit][level]**, resolved by `parseTimeAxisLabelFormatterDictionary`. Tokens:
`{yyyy} {yy} {MMMM} {MMM} {MM} {M} {dd} {d} {eeee} {ee} {e} {HH} {H} {hh} {h} {mm} {m} {ss} {s} {SSS}`,
localised via `src/i18n`. `useUTC` (global default `false`) switches every getter to the UTC variant.

**LogScale.** `base` (`logBase`, default 10). Internally delegates to an `intervalStub: IntervalScale`
over `log_base(value)`, so nice ticks are computed in log space and exponentiated back
(`logScalePowTick`). It carries a **lookup table** mapping specific linear tick values back to exact
originals, because `pow(10, log10(1000))` can produce `999.9999999999999`. Negative and zero values are
excluded at the `DataStore.getDataExtent` level.

### 5.4 Axis option knobs that feed the scale

| Option | Applies to | Semantics |
|---|---|---|
| `type` | all | `'category' \| 'value' \| 'time' \| 'log'` |
| `min` / `max` | all | number, `'dataMin'`/`'dataMax'`, percent string, ordinal index (incl. negative) for category, or `function({min,max}) → number\|null` |
| `dataMin` / `dataMax` | numeric | v6: override the *data* extent before nice/boundaryGap |
| `scale` | value | `false` (default) forces zero into the extent; `true` lets the axis start away from zero |
| `splitNumber` | value/time/log | recommended tick count; **5** (time: **6**) |
| `interval` | value/log | force the tick interval (log: pass the logged value); disabled for category/time |
| `minInterval` / `maxInterval` | value/time | clamp the auto interval — `minInterval: 1` is the standard "integers only" trick |
| `logBase` | log | 10 |
| `boundaryGap` | category: boolean (default `true` = band mode); numeric: `[start, end]` as numbers or `'20%'` strings | |
| `containShape` | v6.1, bar/pictorialBar/candlestick/boxplot | adds margin so shapes don't overflow the coord system |
| `inverse` | all | reverse the pixel direction |
| `alignTicks` | multiple value/log axes on the same grid | `scaleCalcAlign()` finds an interval + extent for the second axis whose ticks land exactly on the first axis's ticks |
| `breaks[]` | value/time/log (**not** category) | v6 axis breaks: `{start, end, gap ('2%' or absolute), isExpanded}`; `breakArea` draws a zigzag band (`zigzagAmplitude 4`, `zigzagMinSpan 4`, `zigzagMaxSpan 20`, `expandOnClick true`), and `expandAxisBreak`/`collapseAxisBreak`/`toggleAxisBreak` actions animate it |
| `minorTick` / `minorSplitLine` | value/time/log | `splitNumber` 5, `length` 3 |
| `splitLine` / `splitArea` / `axisLine` / `axisTick` / `axisLabel` | all | drawing; `axisLabel.interval` `'auto' | number | fn`, `rotate`, `showMinLabel`, `showMaxLabel`, `margin`, `textMargin` |

`Axis` (`src/coord/Axis.ts`) is the pixel binding: `dataToCoord(v, clamp)`, `coordToData(px, clamp)`,
`getTicksCoords({tickModel, clamp, breakTicks})`, `getMinorTicksCoords()`, `getBandWidth()`,
`calculateCategoryInterval()` (auto label thinning based on measured label sizes), `onBand`, `inverse`.
`fixOnBandTicksCoords` shifts category tick coords by half a band when `boundaryGap: true` and
`alignWithLabel: false`.

---

## 6. Animation engine — `src/animation/*` + zrender

### 6.1 Easing functions (all 31)

`linear`,
`quadraticIn/Out/InOut`, `cubicIn/Out/InOut`, `quarticIn/Out/InOut`, `quinticIn/Out/InOut`,
`sinusoidalIn/Out/InOut`, `exponentialIn/Out/InOut`, `circularIn/Out/InOut`,
`elasticIn/Out/InOut`, `backIn/Out/InOut`, `bounceIn/Out/InOut`.

Plus **arbitrary CSS-style cubic-bezier strings**: `createCubicEasingFunc('cubic-bezier(0.4, 0, 0.2, 1)')`
solves `x(t) = p` by `cubicRootAt` and evaluates `y`. Any easing option accepts either a registered name
or such a string.

### 6.2 Option knobs

| Option | Default | Notes |
|---|---|---|
| `animation` | `'auto'` (→ true in browser, false in node unless `ssr`) | |
| `animationThreshold` | 2000 | element/data count above which animation is turned off wholesale |
| `animationDuration` | 1000 | initial; `number \| (dataIndex) => number` |
| `animationEasing` | `'cubicInOut'` | initial |
| `animationDelay` | 0 | `number \| (dataIndex, params) => number` — the standard stagger trick |
| `animationDurationUpdate` | 500 (docs quote 300 for some components) | |
| `animationEasingUpdate` | `'cubicInOut'` | |
| `animationDelayUpdate` | 0 | |
| `stateAnimation` | `{duration: 300, easing: 'cubicOut'}` | emphasis/blur/select transitions |

All of these exist at global, series, and (for many components) component level; `getAnimationConfig`
resolves global → model → `extraOpts` → **payload override** (an action can dictate the animation, which
is how dataZoom/resize suppress or shorten animation).

Three animation *phases* are distinguished: `enter` (initProps), `update` (updateProps), `leave`
(removeElement / removeElementWithFadeOut). `saveOldStyle`/`getOldStyle` let a view animate style
changes across a re-render.

### 6.3 The Animator

zrender's `Animator` holds one **`Track` per animated property key**. Each track holds keyframes
`{time, value, easing?, percent}` and a detected value type:
`VALUE_TYPE_NUMBER | 1D_ARRAY | 2D_ARRAY | COLOR | LINEAR_GRADIENT | RADIAL_GRADIENT | UNKNOWN`.
Interpolators: `interpolateNumber`, `interpolate1DArray`, `interpolate2DArray`, RGBA colour lerp, and
`fillColorStops` which resamples two gradients to a common stop count so gradients can tween.
`UNKNOWN` types snap at the keyframe boundary.

Features: `when(time, props, easing)`, `whenWithKeys`, `during(cb)` (per-frame callback),
`done`, `aborted`, `loop`, `delay`, **`additive` animation** (`_additiveAnimators` — a new animator
composes on top of a still-running one instead of fighting it; `test/animation-additive.html`),
and `setToFinal` (jump to the end state immediately then animate backwards from the saved start, which is
why `_onframe` calls `zr.flush()` right after a pending update).

`Animation` is the frame driver: `requestAnimationFrame` loop → step all animators → `trigger('frame')`
→ painter flush. It sleeps when idle (`wakeUp()`).

### 6.4 Keyframe animation (custom series / graphic component)

```
keyframeAnimation: [{ duration, delay, easing, loop, keyframes: [{percent, easing, ...props}, ...] }, ...]
```
Multiple concurrent keyframe animations per element are allowed (one per property group). Keyframe
animation **overrides** `transition` for the same property.
`transition` itself: `'all'`, or a property list from
`x, y, scaleX, scaleY, rotation, originX, originY`, or the group shorthands `'shape'`, `'style'`, `'extra'`.
`enterFrom` / `leaveTo` give explicit start/end states; `enterAnimation` / `updateAnimation` /
`leaveAnimation` give per-phase `{duration, easing, delay}`.

### 6.5 Morphing

`zrender/src/tool/morphPath` — `morphPath(fromPath, toPath, opts)`, `combineMorph(fromList, toPath)`,
`separateMorph(fromPath, toPathList)`. Algorithm:

1. **Path → cubic bezier arrays.** Every sub-path is converted to a uniform list of cubic segments
   (`pathToBezierCurves`), lines and arcs promoted to cubics.
2. **`alignSubpath` / `alignBezierCurves`.** The two paths are padded to the same sub-path count (missing
   sub-paths are synthesised as degenerate copies of a neighbour) and each pair of sub-paths is
   subdivided so both have the same number of cubic segments.
3. **`centroid` (signed-area polygon centroid)** per sub-path, which also yields winding direction; if the
   windings differ, one path is reversed.
4. **`findBestRingOffset`** — try every rotation of the ring's start vertex, pick the one minimising
   Σ|p_from − p_to|² about the centroids. O(n²) in segment count.
5. **`findBestMorphingRotation(searchAngleIteration, searchAngleRange)`** — additionally search a rotation
   angle by brute force over `searchAngleIteration` samples.
6. Animate the aligned control-point arrays plus the centroid translation and rotation.

`split(path, count)` (one-to-many divide) has fast paths for `rect` (grid slice), `sector`/`circle`
(angular slice), and a general path: convert to polygons, then `binaryDivideRecursive` /
`binaryDividePolygon` — recursively bisect the polygon by area along its longer axis.

### 6.6 Universal transition

`src/animation/universalTransition.ts` (785 lines), wired as a `series:transition` lifecycle listener.

```
series.universalTransition: {
  enabled: false,
  seriesKey: string | string[],   // default = series id; array = "these series merge into me"
  divideShape: 'split' | 'clone', // default varies: scatter → clone, bar → split
  delay: (index, count) => number
}
```

Mechanism:
1. `findTransitionSeriesBatches` groups old and new series by `seriesKey` (arrays are sorted+joined).
2. Within a batch, data items are diffed by **`groupId` / `childGroupId`** rather than index.
   `groupId` can come from `data[i].groupId`, from `series.dataGroupId`, or from an encoded dimension
   (`encode.itemGroupId` / `itemChildGroupId`). The direction (parent→child = drill-down, child→parent =
   roll-up) is auto-detected by checking whether old `childGroupId`s intersect new `groupId`s or vice
   versa.
3. Many-to-one → `combineMorph`; one-to-many → `split()` the source shape (or `clone` it) then
   `separateMorph`; one-to-one → `morphPath`.
4. Items with no counterpart fade in/out (`fadeInElement`, `removeElement`).
5. Styles are cross-faded separately (`animateElementStyles`).

There is also a **targeted** form: `setOption(opt, {transition: {from: {seriesIndex, dimension}, to: {...}}})`,
which drives the transition by a data *dimension* instead of by group id.

---

## 7. Coordinate-system abstraction

### 7.1 The contract

Two interfaces (`src/coord/CoordinateSystem.ts`):

**`CoordinateSystemMaster`** — what the manager holds (e.g. one `Grid`):
```
dimensions: string[]
update?(ecModel, api)                  // recompute axis extents from processed data
containPoint(point) → boolean
convertToPixel?(ecModel, finder, value) / convertFromPixel? / convertToLayout?
getAxes?() → Axis[]         axisPointerEnabled?: boolean
getTooltipAxes?(dim) → {baseAxes, otherAxes}
getRect?() → RectLike
```

**`CoordinateSystem`** — what a series binds to (e.g. one `Cartesian2D` inside a `Grid`):
```
type: string
dimensions: string[]
master?: CoordinateSystemMaster
dataToPoint(data, opt?, out?) → number[]              // invalid ⇒ [NaN, NaN], never null
dataToLayout?(data, opt?, out?) → {x, y, width, height}
pointToData?(point, opt?, out?) → number | number[]
containPoint(point) → boolean
getAxis?(dim) / getAxes?() / getBaseAxis?() / getOtherAxis?(baseAxis) / getAxesByScale?(type)
clampData?(data, out?)
getArea?(tolerance?) → {x, y, width, height, contain(x, y)}
shouldClip?() → boolean
getBoundingRect?() / getViewRect?() / getRoamTransform?()   // geo-like only
prepareCustoms?                                            // for custom series
```

A `CoordinateSystemCreator` is `{create(ecModel, api) → masters[], dimensions?, getDimensionsInfo?}`.
Registration: `registerCoordinateSystem(type, creator)`.

v6 adds a **two-tier** notion: `matrix` and `calendar` are "non-series box" coordinate systems, created
first, and other coordinate systems (or components like `pie`) can lay their **box** out on top of them
(`coordinateSystemUsage: 'data' | 'box'`). Only one level of dependency is supported today.

### 7.2 The nine built-in coordinate systems

| type | Registered by | Dimensions | Notes |
|---|---|---|---|
| `cartesian2d` | `component/grid` | `['x','y']` | master = `Grid`, holds N `Cartesian2D`s (one per x/y axis pair). Supports multiple x and y axes, `alignTicks`, `containLabel`. |
| `polar` | `component/polar` | `['radius','angle']` | `AngleAxis` + `RadiusAxis`; `startAngle`, `clockwise`, `endAngle`. |
| `radar` | `component/radar` | n indicators | N radial `IndicatorAxis`es sharing a centre. |
| `geo` | `component/geo` | `['lng','lat']` | GeoJSON/SVG regions + projection + roam transform; extends `View`. |
| `parallel` | `component/parallel` | n axes | N stacked `ParallelAxis`es; has no `pointToData`. |
| `single` | `component/singleAxis` | one | a single horizontal/vertical axis (themeRiver, single-axis scatter). |
| `calendar` | `component/calendar` | `['time','value']` | month/week grid; **non-series box** capable. |
| `matrix` | `component/matrix` | `['x','y']` | v6: a table/matrix layout with header + body + corner cells; **non-series box** capable. |
| `graphView` | `chart/graph` | — | the pan/zoom view space for force/circular graph layouts; extends `View`. |

`src/coord/View.ts` (918 lines) is the shared pan/zoom base: it holds a raw bounding rect, a view rect,
and a roam transform (`getRoamTransform`), converting between "raw" data space and screen space.

`convertToPixel` / `convertFromPixel` / `convertToLayout` on the ECharts instance simply try every
registered master in turn until one claims the `finder`.

---

## 8. Miscellaneous facts worth carrying over

- **Element states.** Each element has `states: {emphasis, blur, select, ...}` and a `currentStates`
  stack. `useStates(names)` merges the named state objects over the saved normal state, with an optional
  `stateTransition` animation. ECharts drives this from `hoverState`/`selected` flags in
  `applyChangedStates`, once per frame, not per event. Option-level: `emphasis.focus`
  (`'none' | 'self' | 'series'`, plus chart-specific `'ancestor' | 'descendant' | 'relative'`) and
  `emphasis.blurScope` (`'coordinateSystem' | 'series' | 'global'`).
- **`silent`** on a series/component sets `group.silent`, removing the whole subtree from hit testing.
- **`blendMode`** per series maps straight onto canvas `globalCompositeOperation`; heatmap-ish effects
  use `'lighter'`.
- **Sub-pixel optimisation.** `subPixelOptimize(position, lineWidth, positiveOrNegative)` snaps a
  coordinate so an odd-width stroke lands on a pixel centre. Used for axis lines, split lines, bar edges.
- **Decals** (`src/util/decal.ts`, `visual/decal.ts`) generate a repeating symbol pattern as a canvas
  `Pattern`, driven by `aria.decal` — the accessibility "distinguish series without colour" feature.
  Default decal set: 6 entries with `dashArrayX/dashArrayY/symbol/symbolSize/rotation`.
- **`connect(group)`** synchronises tooltip/dataZoom/restore across multiple chart instances by
  replaying actions; `getConnectedDataURL()` composites their canvases.
- **`echarts.init` options**: `renderer ('canvas'|'svg')`, `devicePixelRatio`, `useDirtyRect` (false),
  `useCoarsePointer` ('auto'), `pointerSize` (44), `ssr`, `width`, `height`, `locale`.
- **Data sampling** (`processor/dataSample.ts`): `series.sampling` ∈
  `'lttb' | 'minmax' | 'average' | 'sum' | 'max' | 'min' | 'nearest' | fn` — applied when the data count
  exceeds the pixel width of the axis. `lttb` = Largest-Triangle-Three-Buckets.

---

## Porting notes

Classification for an Object Pascal / BGRABitmap immediate-mode desktop control.

### NATURAL — maps cleanly onto an immediate-mode antialiased canvas

| Capability | Note |
|---|---|
| All 12 shape primitives (rect w/ per-corner radii, circle, ellipse, sector w/ cornerRadius, ring, polygon, polyline, line, arc, bezierCurve, image, text) | BGRABitmap has paths, arcs, rounded rects, gradients, and AA fills/strokes for all of these. `sector` with `cornerRadius` needs a small custom path builder. |
| Path style model (fill, stroke, lineWidth, lineCap, lineJoin, miterLimit, lineDash + offset, opacity, fill/strokeOpacity, strokeFirst) | direct BGRABitmap analogues; `strokeNoScale` is a divide-by-scale. |
| Linear + radial gradients, image/pattern fills | BGRABitmap `TBGRAGradientScanner` / texture brushes. |
| Affine transforms (x/y/scale/rotation/skew/origin/anchor), composed down a Group tree | 3×2 matrix multiply + `TBGRACanvas2D` transform, or transform points yourself. |
| `z / z2` ordering within a surface | one stable sort before drawing. |
| Rect and path clipping, **inherited down the tree** | BGRABitmap clip rect is easy; arbitrary path clip needs a mask (see HEAVY). |
| `percent` partial stroke on line/polyline/bezier; `strokePercent` | arc-length truncation of a recorded path. |
| Text: font, align/verticalAlign, lineHeight, background box, border, padding, border radius, shadow | already present in the ty-controls painter stack. |
| All 31 easing functions + cubic-bezier easing | trivial to port; pure scalar math. |
| `animationDuration/Easing/Delay` (+ `*Update` variants, callback forms) | a per-element track list with a timer. |
| `stateAnimation` (emphasis/blur/select cross-fade, 300 ms cubicOut) | |
| The 4 scale types and their nice-tick generation (`nice()` 1/2/3/5/10 ladder, `increaseInterval`, `intervalScaleNiceTicks`, minor ticks) | pure arithmetic, ~200 lines. |
| Axis knobs `min/max/scale/splitNumber/interval/minInterval/maxInterval/logBase/boundaryGap/inverse` | |
| `alignTicks` across two value axes | `scaleCalcAlign` is self-contained arithmetic. |
| Coordinate-system contract (`dataToPoint`, `pointToData`, `containPoint`, `getAxis`) | an interface with 4–8 methods; cartesian2d/polar/single are straightforward. |
| Model → View split, per-series view objects with `render/remove/updateView`, view group ownership | maps onto Pascal classes + an owned element list, or onto direct paint methods. |
| The `PRIORITY` ordering idea (processors → layout → visual → render) | a sorted list of handler records. |
| Media-query-style responsive option (`option.media`, min/max width/height/aspectRatio) | just a size test at layout time; no CSS needed. |
| Timeline option swapping | |
| Data sampling (`average/sum/max/min/nearest`, LTTB, minmax) | |
| Columnar data store (one typed array per dimension + incremental extents + index permutation) | `array of Double` / `array of Int32`, better in Pascal than in JS. |
| `subPixelOptimize` crisp-line snapping | one line of code; **important** for 1px axis/grid lines on a desktop DPI. |
| `silent` subtrees, `ignore`, `invisible`, `culling` | |
| Decal patterns (6 built-in dash/symbol decals) | render a tile bitmap once, tile it. |

### HEAVY — doable, but algorithmically substantial

| Capability | Algorithm you must implement |
|---|---|
| **Retained scene graph + display list** | Depth-first flatten + **stable** sort by (zlevel, z, z2), with clip-path stacks accumulated during the walk. Needed if you want ECharts' layering semantics rather than draw-order-is-code-order. |
| **Hit-testing `contain()`** | Non-zero **winding number** accumulation over a path command buffer (`windingLine`, `windingQuadratic`, `windingCubic`, `windingArc`) for fills; per-segment **point-to-curve distance** tests for strokes (line, quadratic, cubic, arc), with a `strokeContainThreshold` widening for unfilled paths. Plus inverse-transform to local space and an inherited clip test up the parent chain. ~600 lines. |
| **Coarse-pointer hit fallback** | Bounding-rect prefilter against a 44×44 box, then a polar spiral probe (`r += 4`, `θ += π/12`). Optional on desktop (mouse is precise); worth it for touch/pen. |
| **Arbitrary path clipping** | BGRABitmap has no `ctx.clip()` for arbitrary paths. Requires rendering the clip path to an 8-bit mask and compositing, or restricting to rect/rounded-rect clips (which covers ~95% of ECharts' actual usage: grid rect clipping, `series.clip`). |
| **Dirty-rectangle repaint** | The 4-step merge in §1.7: prev-rect + cur-rect collection, greedy min-added-area union capped at 5 rects, then an intersection-fixpoint pass; plus per-element `getPaintRect()` (bounds expanded by stroke, shadow, transform) and prev/current rect bookkeeping. Only worth it if you have a persistent offscreen surface — on a Windows/GTK control with a `TTyPaintCache`-style offscreen this is a genuine win for hover/tooltip repaints. |
| **Path batching** | The "one `beginPath` + many subpaths + one fill" trick relies on a mutable path object with deferred fill. In BGRABitmap you'd accumulate into a single `TBGRAPath`/point array and fill once. Requires the same `canPathBatch` predicate (single paint, plain colour, no dash, full stroke percent). |
| **Progressive / streaming render** | The `Task` pipeline: dirty propagation, `_dueIndex`/`_dueEnd` cursors, `plan/reset/progress/count` callbacks, upstream/downstream piping, and the `mod` interleaving index formula. On desktop you'd drive it from a timer with a per-tick time budget instead of `requestAnimationFrame`. Only justified for ≥100k-point series. |
| **`large` mode bulk primitives** | Custom path types over a flat point buffer with their own `buildPath` and `contain` (`LargeSymbolPath`, `LargeLinesPath`). Straightforward but a separate render path per series type. |
| **Path morphing (`morph`, `universalTransition` one-to-one)** | Path→cubic-bezier conversion, sub-path count alignment with synthetic degenerate sub-paths, per-sub-path segment-count equalisation, signed-area centroid + winding reversal, `findBestRingOffset` (O(n²) rotational alignment), and an optional brute-force rotation search. This is the single most expensive thing in the animation layer. |
| **Shape splitting (`divideShape: 'split'`)** | Fast paths for rect (grid) and sector (angular); general case = path→polygons + `binaryDividePolygon` recursive area-balanced bisection. |
| **Universal transition group matching** | groupId/childGroupId diff with automatic drill-down/roll-up direction detection, batching by `seriesKey`, then dispatch to combine/separate/1:1 morph. |
| **Rich text layout** | Tag parsing (`{style|content}`), per-run measurement, line boxes, per-run background/border, `overflow: 'break' \| 'breakAll' \| 'truncate'`, `lineOverflow: 'truncate'`, ellipsis with `truncateMinChar`. **Note the CJK trap already documented in this repo**: ECharts' `wrapText` breaks on spaces *and* per-character when `breakAll`; a straight port that only breaks on spaces will overflow on pure-CJK strings. |
| **Time scale tick generation** | The 12-level `scaleIntervals` ladder, calendar-boundary snapping per unit, tick `level` assignment, and the `[lowerUnit][upperUnit][level]` formatter dictionary with `{yyyy}`-style tokens and locale month/weekday names. |
| **Axis breaks (v6)** | Piecewise scale mapping through break ranges, tick pruning near breaks, zigzag break-area drawing, and expand/collapse animation. A genuinely new coordinate transform layer, not just drawing. |
| **Additive animation** | Composing a new animator on top of a running one (needed for smooth interrupt of dataZoom drags); requires tracking the residual delta of the previous animator rather than restarting. |
| **Auto category-label thinning** (`axisLabel.interval: 'auto'`, `calculateCategoryInterval`) | Measure labels, estimate how many fit, pick a step; interacts with rotation and with `showMinLabel`/`showMaxLabel`. |
| **`option` merge semantics** | Component identity matching by id/name/index (`mappingToExists`), `notMerge` / `replaceMerge` / `$action: merge\|replace\|remove`, topological ordering by `dependencies`, and default-option inheritance through `parentModel` chains. Doable in Pascal but needs a deliberate design (published properties vs a dynamic option tree). |

### BROWSER-BOUND — depends on DOM/CSS/WebGL/JS; needs a native re-think or is out of scope

| Capability | Why, and what the native answer is |
|---|---|
| **Layered `<canvas>` per `zlevel`** | The entire point is browser canvas compositing. Native answer: either ignore `zlevel` (treat it as a coarser `z`) or back it with N offscreen `TBGRABitmap`s blitted in order. Note `zlevel` still has *ordering* meaning that must be preserved even if the layering optimisation is dropped. |
| **The hover layer** (`hoverLayerThreshold`) | Same — a canvas-compositing optimisation. Native answer: repaint the dirty rect of the hovered element from the cached offscreen. |
| **SVG renderer** (`renderer: 'svg'`, vdom `patch`, `<defs>` ids, CSS `@keyframes` emission) | No native analogue and no reason to want one. Out of scope. Its *only* portable lesson is that ECharts' element model is renderer-agnostic. |
| **SSR** (`ssr: true`, `renderToString`, `renderToSVGString`, `ssr` data attributes) | Out of scope. If you need "render to image file", that's just painting to an offscreen bitmap. |
| **`useDirtyRect` defaulting off / `requestAnimationFrame` scheduling** | The frame budget constants (1 ms scheduler budget, 15 ms incremental paint budget, 17 ms flush throttle) assume rAF. Native answer: a `TTimer` at the monitor refresh rate, or an idle handler. |
| **`useCoarsePointer` auto-detection via `env.touchEventsSupported`** | Detect pen/touch through LCL input messages instead. |
| **`cursor` style on elements** | Maps to `TControl.Cursor` / `Screen.Cursor` — trivially portable in concept, but the per-element CSS-cursor string set is browser-specific; pick an LCL `TCursor` mapping. |
| **DOM tooltip** (`tooltip.renderMode: 'html'`, `tooltip.formatter` returning HTML, `appendToBody`, `className`, `extraCssText`) | The `'richText'` render mode is the portable one — same content model, drawn as a zrender `ZRText` with rich tags. A native port should implement `renderMode: 'richText'` semantics and treat the HTML mode as unavailable. |
| **`toolbox.feature.saveAsImage`** (canvas `toDataURL` + `<a download>`) | Native answer: a save dialog + PNG encode from the offscreen bitmap. |
| **`toolbox.feature.dataView`** (a DOM `<textarea>` overlay) | Would need a native modal editor. |
| **`aria` output** (generated `aria-label` on the container DOM node) | Native answer: MSAA/UIA accessibility, or drop it. The `aria.decal` half (pattern fills) is NATURAL and worth keeping. |
| **`echarts-gl` / WebGL series** (scatter3D, surface, globe, graphGL, flowGL, linesGL) | Entirely out of scope; not in this repo. |
| **Worker-thread rendering** (`env.worker` guards) | Not applicable; FPC threads can't touch the canvas anyway. |
| **`media` query on *device* pixel ratio / CSS units** | Only the width/height/aspect-ratio form is used, which is NATURAL. No CSS involvement. |
| **Function-valued options** (`formatter`, `animationDelay(idx)`, `min(value)`, `renderItem`, `labelLayout`, `sampling` as a function) | JS callbacks. Native answer: Pascal method pointers / anonymous methods on the control — a straight `TFunc` per hook. Design decision, not a blocker, but it changes the option-object shape substantially. |
| **`dataset.transform` external transforms & `registerTransform`** | The mechanism is portable (a filter/sort/aggregate pipeline over the store), but the "register a JS function by name" contract needs to become a registered Pascal class. |
