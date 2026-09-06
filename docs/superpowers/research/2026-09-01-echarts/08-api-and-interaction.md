# ECharts 6.1.0 — Public API, Events, Actions, Interaction and Output

Research pass for a native Object Pascal / Lazarus + BGRABitmap chart control.
All statements verified against `D:/Projects/echarts` (TS source, 6.1.0) and
`D:/Projects/echarts-doc/en/api/*`, `en/option/*`. Nothing is from memory.

Key source files read:
`src/core/echarts.ts` (3434 lines — the whole public surface), `src/core/ExtensionAPI.ts`,
`src/core/lifecycle.ts`, `src/core/locale.ts`, `src/extension.ts`,
`src/export/{core,api,renderers,features}.ts` + `src/export/api/*`,
`src/util/ECEventProcessor.ts`, `src/model/OptionManager.ts`, `src/i18n/langEN.ts`,
`src/loading/default.ts`, `ssr/client/src/index.ts`, and every `registerAction` call site.

---

## 1. The shape of the whole API

ECharts is a **single declarative option tree in, one scene graph out** library. There are exactly
three ways to talk to it after creation:

| Channel | Direction | Mechanism |
|---|---|---|
| `setOption(option, opts)` | in | Full/partial declarative state, merged into a `GlobalModel` |
| `dispatchAction(payload)` | in | Imperative, typed command; goes through the same update pipeline |
| `on(eventName, [query], handler)` | out | Mouse events + one event per action type |

Everything else is bookkeeping (`resize`, `dispose`), inspection (`getOption`, `convertToPixel`),
or output (`getDataURL`, `renderToSVGString`).

**There are no per-element JS callbacks in the option tree except in `graphic` component elements**
(`onclick`, `ondrag`, …) and `series.custom.renderItem`. Series-level interactivity is entirely
event-based. This is good news for a native port: the interaction contract is a *command/event*
protocol, not a callback protocol.

---

## 2. `echarts.init(dom, theme?, opts?)`

`EChartsInitOpts` (verbatim from `src/core/echarts.ts:443`):

| Option | Type | Default | Semantics |
|---|---|---|---|
| `renderer` | `'canvas' \| 'svg'` | `'canvas'` | Which zrender painter. `renderToSVGString` requires `'svg'`; `renderToCanvas`/`getDataURL('png'/'jpeg')` require `'canvas'` (dev-mode throws otherwise). |
| `devicePixelRatio` | number | `window.devicePixelRatio` | Backing-store scale. `getDevicePixelRatio()` reads it back. |
| `width` | `number \| 'auto'` | `dom.clientWidth` | Explicit pixel width; required in SSR (no DOM to measure). |
| `height` | `number \| 'auto'` | `dom.clientHeight` | Same. |
| `locale` | `string \| LocaleOption` | auto-detected `SYSTEM_LANG` | `'EN'`/`'ZH'` built in; else a `registerLocale`d name; else an inline object. Detection reads `document.documentElement.lang \|\| navigator.language`. |
| `useDirtyRect` | boolean | `false` | Dirty-rectangle repaint instead of full clear+repaint. Pure perf. |
| `useCoarsePointer` | `boolean \| 'auto'` | `'auto'` | Expands the hit-test area of elements. `'auto'` = on for touch devices. |
| `pointerSize` | number (px) | — | Radius of that expansion. Only meaningful with `useCoarsePointer`. |
| `ssr` | boolean | `false` | Headless mode. Disables per-frame rendering (`setOption` never calls `zr.flush()`), registers an SSR data getter that stamps `ecmeta_series_index` / `ecmeta_data_index` / `ecmeta_ssr_type` attributes onto emitted SVG nodes, and makes `dom` optional. |

Notes worth carrying over:
* `init` refuses to double-init on the same DOM node — it returns the existing instance and warns.
* The instance is registered in a module-level `instances` map keyed by `'ec_' + idBase++`, and the
  id is stamped on the DOM as attribute `_echarts_instance_` — the basis of `getInstanceByDom`.
* `dom` may be a `<canvas>` directly (so the canvas can be reused as a WebGL texture).

---

## 3. Module-level API (`echarts.*`)

### 3.1 Lifecycle / registry

| Function | Semantics |
|---|---|
| `init(dom, theme?, opts?)` | See above. |
| `connect(groupId \| ECharts[])` | Marks a group as linked. Any action dispatched on one member is **replayed on every other member of the group** unless the payload sets `escapeConnect`. Implemented by `enableConnect`: it listens to every registered event type, reverses it back to an action via `connectionEventRevertMap`, and re-dispatches with a 3-state re-entrancy guard (`PENDING`/`UPDATING`/`UPDATED`). |
| `disconnect(groupId)` / alias `disConnect` | Turns the group off. |
| `dispose(chart \| dom \| id)` | |
| `getInstanceByDom(dom)` / `getInstanceById(id)` | |
| `registerTheme(name, themeOption)` | Two are pre-registered: `'default'` (empty) and `'dark'`. |
| `registerLocale(name, localeObj)` | Case-insensitive; `'EN'` and `'ZH'` pre-registered. |
| `registerMap(name, geoJSON \| {geoJSON,specialAreas} \| {svg})` | Goes through `registerImpl('registerMap')` — a no-op unless the geo/map module is `use`d. |
| `getMap(name)` | Returns `{geoJSON, specialAreas}`. SVG maps are **not** retrievable. |
| `use(installer \| installer[])` | The tree-shaking entry. Every chart/component/renderer/feature is an installer function. |
| `registerCustomSeries(type, renderItem)` | 6.0+. Names a `renderItem` so `series.renderItem: 'bubble'` works. |
| `registerTransform(externalTransform)` | Alias of `registerExternalTransform` — dataset transforms. |
| `setPlatformAPI({createCanvas, measureText, loadImage})` | The one true portability hook: it is how ECharts runs on node/miniprogram. |
| `setCanvasCreator(fn)` | Deprecated alias of the above. |
| `getCoordinateSystemDimensions(type)` | |

### 3.2 Extension registration (all also exposed on the `registers` object passed to `use` installers)

`registerPreprocessor`, `registerProcessor(priority, task)`, `registerVisual(priority, task)`,
`registerLayout(priority, task)`, `registerCoordinateSystem(type, creator)`,
`registerAction(actionInfo, handler)`, `registerLoading(name, effectCreator)`,
`registerPostInit`, `registerPostUpdate`, `registerUpdateLifecycle(phase, fn)`,
`registerComponentModel`, `registerComponentView`, `registerSeriesModel`, `registerChartView`,
`registerSubTypeDefaulter`, `registerPainter`, `registerImpl`, plus the `PRIORITY` constant table.

`registerUpdateLifecycle` phases (`src/core/lifecycle.ts`) — 7 hooks:
`afterinit`, `coordsys:aftercreate`, `series:beforeupdate`, `series:layoutlabels`,
`series:transition`, `series:afterupdate`, `afterupdate`.

Deprecated class-extension shims still exported: `extendComponentModel`, `extendComponentView`,
`extendSeriesModel`, `extendChartView`.

### 3.3 Utility namespaces exported on `echarts`

| Namespace | Contents (exhaustive, from `src/export/api/*`) |
|---|---|
| `echarts.graphic` | `extendShape`, `extendPath`, `makePath`, `makeImage`, `mergePath`, `resizePath`, `createIcon`, `updateProps`, `initProps`, `getTransform`, `clipPointsByRect`, `clipRectByRect`, `registerShape`, `getShapeClass`, and the shape classes `Group, Image, Text, Circle, Ellipse, Sector, Ring, Polygon, Polyline, Rect, Line, BezierCurve, Arc, IncrementalDisplayable, CompoundPath, LinearGradient, RadialGradient, BoundingRect`. Built-in registered shape names: `circle, sector, ring, polygon, polyline, rect, line, bezierCurve, arc`. |
| `echarts.format` | `addCommas`, `toCamelCase`, `normalizeCssArray`, `encodeHTML`, `formatTpl`, `getTooltipMarker`, `formatTime` (deprecated), `capitalFirst`, `truncateText`, `getTextRect` |
| `echarts.number` | `linearMap`, `round`, `asc`, `getPrecision`, `getPrecisionSafe`, `getPixelPrecision`, `getPercentWithPrecision`, `parsePercent`, `MAX_SAFE_INTEGER`, `remRadian`, `isRadianAroundZero`, `parseDate`, `quantity`, `quantityExponent`, `nice`, `quantile`, `reformIntervals`, `isNumeric`, `numericToNumber` |
| `echarts.time` | `parse` (= `parseDate`), `format(time, template, isUTC, lang?)`, `roundTime(date, unit, isUTC)` |
| `echarts.matrix`, `echarts.vector` | zrender's 2×3 affine matrix and 2-vector math |
| `echarts.color` | zrender colour tool (parse/lift/lerp/modifyAlpha/…) |
| `echarts.util` | `map, each, indexOf, inherits, reduce, filter, bind, curry, isArray, isString, isObject, isFunction, extend, defaults, clone, merge` |
| `echarts.helper` | `createList`, `createDimensions`, `getLayoutRect`, `dataStack.{isDimensionStacked,enableDataStack,getStackedDimension}`, `createSymbol`, `createScale`, `mixinAxisModelCommonMethods`, `getECData`, `enableHoverEmphasis`, `createTextStyle` |
| `echarts.env` | Feature/platform detection object |
| `echarts.zrender` | The raw zrender module |
| misc | `throttle`, `parseGeoJSON`/`parseGeoJson`, `setPlatformAPI`, `innerDrawElementOnCanvas` (GL only), `Model`, `Axis`, `SeriesData`/`List`, `ComponentModel`, `ComponentView`, `SeriesModel`, `ChartView` |

**Date/time token vocabulary** (`echarts.time.format`, the same tokens the time axis uses) — 24 tokens:
`{a} {A}` (am/pm), `{yyyy} {yy}`, `{Q}` (quarter), `{MMMM} {MMM} {MM} {M}`, `{dd} {d}`,
`{eeee} {ee} {e}` (weekday long/abbr/index), `{HH} {H}` (24h), `{hh} {h}` (12h),
`{mm} {m}`, `{ss} {s}`, `{SSS} {S}`.
The month/weekday names come from the **locale model**, so time formatting is i18n-aware.
`roundTime(date, unit, isUTC)` truncates to `year|month|day|hour|minute|second` by fall-through.

The legacy `echarts.format.formatTime` uses a different, non-braced token set
(`yyyy yy MM M dd d hh h mm m ss s SSS`) and is deprecated.

---

## 4. `echartsInstance` — the complete method list

Verified by enumerating class members in `src/core/echarts.ts`. Public methods (24 + `on/off/one` + 2 props):

| Member | Signature / result | Notes |
|---|---|---|
| `id` / `group` | string | `group` is what `connect` keys off. |
| `setOption(option, notMerge?, lazyUpdate?)` or `setOption(option, opts)` | void | See §5. |
| `setTheme(theme, {silent?})` | void | **New in 6.0.** Re-runs a full `prepare + update`. Documented caveat: it discards all but the last `setOption` unless every call used `notMerge`. |
| `getOption()` | full merged option | Every component type comes back as an **array**, regardless of how it was set. Includes interaction state (legend selection, dataZoom window, …), so it round-trips a live chart. |
| `getWidth()` / `getHeight()` / `getDevicePixelRatio()` | number | |
| `getDom()` / `getId()` / `getZr()` | | `getZr()` escapes to the raw scene graph. |
| `isSSR()` / `isDisposed()` | boolean | |
| `resize({width?, height?, silent?, animation?{duration,easing}})` | void | Re-evaluates `media` queries (`ecModel.resetOption('media')`), then a full update with `animation.duration: 0` by default. Bound to the instance in the constructor so `window.onresize = chart.resize` works. |
| `dispatchAction(payload, opt?)` | void | `opt` = `boolean` (silent) or `{silent?, flush?}`. `flush:true` forces an immediate `zr.flush()` so pixels can be read back synchronously. Actions dispatched *during* the update cycle are queued in `_pendingActions` and flushed after. |
| `on(name, handler, ctx?)` / `on(name, query, handler, ctx?)` | | Event names are lowercased on both `on` and `off`. |
| `off(name?, handler?)` | | No args = unbind everything. |
| `one(name, cb, ctx?)` | | Auto-unbinding single-shot. |
| `isSilent(eventName)` / `trigger(...)` | | Inherited from zrender `Eventful`. |
| `convertToPixel(finder, coord, opt?)` | `number \| number[]` | See §8.1. |
| `convertFromPixel(finder, px, opt?)` | `number \| number[]` | Inverse. |
| `convertToLayout(finder, coord, opt?)` | `{rect, contentRect?, matrixXYLocatorRange?}` | **New in 6.0.** Only `calendar` and `matrix`. Returns a *rectangle*, not a point — the cell box. |
| `containPixel(finder, [x,y])` | boolean | Supported by grid, polar, geo, matrix, series-map, series-graph, series-pie. |
| `getVisual(finder, visualType)` | any | `visualType` ∈ `'color'`, `'symbol'`, `'symbolSize'` (and any registered visual). Reads series-level or item-level visual. |
| `renderToCanvas({backgroundColor?, pixelRatio?})` | `HTMLCanvasElement` | canvas renderer only. `getRenderedCanvas` is the deprecated alias. |
| `renderToSVGString({useViewBox?})` | string | svg renderer only. Mandatory in SSR mode. |
| `getSvgDataURL()` | data-URI | Stops all animations first (`el.stopAnimation(null, true)`). |
| `getDataURL({type?, pixelRatio?, backgroundColor?, excludeComponents?})` | data-URI | `type` ∈ `'png' \| 'jpeg' \| 'svg'`. `excludeComponents` temporarily sets `view.group.ignore = true` on the named component types (typical: `['toolbox']`). |
| `getConnectedDataURL({…, connectedBackgroundColor?})` | data-URI | Composites *every chart in the same `connect` group* into one image, positioned by each container's `getBoundingClientRect()`. Falls back to `getDataURL` if the group is not connected. |
| `showLoading(name?, cfg?)` / `hideLoading()` | void | See §12. |
| `appendData({seriesIndex, data})` | void | Streaming append; does not clear already-rendered elements. Only `scatter` and `lines` support it in core ECharts (plus GL series). Explicitly **not supported with `dataset`**, and it does **not** re-derive axis extents — you must pin `min`/`max` or `axis.data`. |
| `clear()` | void | Implemented as `setOption({series: []}, true)`. |
| `dispose()` | void | Disposes all views, then `zr.dispose()`, then nulls every field. |
| `makeActionFromEvent(eventObj)` | Payload | Reverses an event back into the action that would produce it (this is the `connect` machinery, exposed). |
| `updateLabelLayout()` | void | Re-runs the label-layout lifecycle hook only. |

**Not present in 6.1.0**, despite older docs/tutorials: `setCurrentTimelineIndex` (grep of `src/` and
`test/` finds zero hits). Use `dispatchAction({type: 'timelineChange', currentIndex})`.

`ExtensionAPI` (what components/series see internally) is a strict subset:
`getDom, getZr, getWidth, getHeight, getDevicePixelRatio, dispatchAction, isSSR, isDisposed, on, off,
getDataURL, getConnectedDataURL, getOption, getId, updateLabelLayout` plus internal
`enterEmphasis/leaveEmphasis/enterBlur/leaveBlur/enterSelect/leaveSelect`, `getComponentByElement`,
`getCoordinateSystems`, `usingTHL`.

---

## 5. `setOption` merge modes — the single most important semantic

Four independent knobs on `SetOptionOpts`:

| Knob | Effect |
|---|---|
| `notMerge: true` | Throw away the whole `GlobalModel` and build a new one. Everything (highlight state, dataZoom window, legend selection, animation state) is lost. |
| `replaceMerge: 'series' \| string[]` | Per-component-main-type "replace" semantics. |
| `lazyUpdate: true` | Stash `{silent, updateParams}` in `PENDING_UPDATE` and do the real update on the next animation frame (`_onframe`). Coalesces bursty `setOption` calls. |
| `silent: true` | Suppress the events that the update would otherwise fire. |
| `transition: {from?, to}` | Declares an explicit series↔series morph mapping for `UniversalTransition`. |

**Normal Merge** (default). Within one main type:
1. descriptions with `id` or `name` merge onto the existing component with the same `id`/`name`;
2. remaining descriptions merge positionally onto remaining existing components;
3. leftovers are appended.
Nothing is ever removed; `componentIndex` never changes.

**Replace Merge**. Within a main type listed in `replaceMerge`:
1. match by `id` only;
2. **remove** every unmatched existing component (its slot is set to `null` so indices are stable —
   holes are expected and legal);
3. create new components into the freed slots / at the tail.
This is the only way to *delete* a component without nuking everything.

Guard rails in the source: `setOption`, `setTheme` and `resize` all refuse to run re-entrantly
(`IN_EC_CYCLE_KEY`), logging `"should not be called during main process"`.

### 5.1 The update pipeline and partial-update levels

Every action declares `update:` which selects how much of the pipeline re-runs. This is the
performance contract of the whole library and is directly portable:

| `update` value | What runs |
|---|---|
| `'prepareAndUpdate'` | Rebuild views + full update (used by timeline, restore, dataView, magicType) |
| `'update'` | Full: process data → coord systems → visual → layout → render |
| `'updateTransform'` | Only coord-system transform + re-position (geoRoam) |
| `'updateView'` | Re-render views, keep data/visual (treemap/sunburst navigation) |
| `'updateVisual'` | Re-run only visual encoding (brush) |
| `'updateLayout'` | Re-run only layout |
| `'none'` | Nothing re-computed; the action handler mutated state directly (roam, brushSelect, brushEnd) |
| `'<cptType>:<method>'` | Call a named method directly on one component's view, e.g. `'tooltip:manuallyShowTip'`, `'geo:updateSelectStatus'`, `'series:focusNodeAdjacency'`, `':updateAxisPointer'` (broadcast to all views) |

There is also a per-frame **progressive/streaming** loop in `_onframe`: while `scheduler.unfinished`,
it runs series tasks / data-processor tasks / visual tasks / `renderSeries` in a `do…while` bounded by
`TEST_FRAME_REMAIN_TIME` ms, so huge datasets render across frames without blocking.

---

## 6. Events

### 6.1 Mouse events — exactly 9

From `MOUSE_EVENT_NAMES` (`src/core/echarts.ts:2864`):

`click`, `dblclick`, `mouseover`, `mouseout`, `mousemove`, `mousedown`, `mouseup`,
`globalout`, `contextmenu`.

Touch is unified into these same names by zrender — there is no separate touch event surface.
`globalout` is the "pointer left the whole chart" event and has an empty payload.

### 6.2 Payload shape

For a hit on a data element, the payload is `seriesModel.getDataParams(dataIndex, dataType, el)` plus
`type` and `event`:

```
componentType   'series' | 'markLine' | 'markPoint' | 'markArea' | 'xAxis' | 'legend' | 'geo' | ...
componentIndex  number                (contract: componentType + componentIndex must always be present)
componentSubType/seriesType   'line' | 'bar' | 'pie' | ...
seriesIndex, seriesId, seriesName
name            data/category name
dataIndex       index into the raw data array
data            the raw data item object
dataType        'node' | 'edge' for graph/sankey; absent for single-data series
value           number | any[]
color           resolved item colour
info            user payload from graphic component / custom series element `info`
type            the event name
event           the underlying zrender ElementEvent (which wraps the DOM event)
```

Special case in `_initEvents`: for `markLine`/`markPoint`/`markArea` the `componentType` is rewritten
to `'series'` and `componentIndex` to `seriesIndex`, so those are queryable by series.

Components that are not data-bearing attach an arbitrary `ecData.eventData` object to their elements,
which becomes the payload directly.

### 6.3 Query filtering — `chart.on('click', query, handler)`

Implemented in `src/util/ECEventProcessor.ts`. Two forms:

**String form** — `'mainType'` or `'mainType.subType'`:
`'series'`, `'series.line'`, `'xAxis'`, `'xAxis.category'`, `'yAxis.category'`.

**Object form** — the keys are split into three buckets by suffix matching:
* component query: any key ending in `Index` / `Name` / `Id` where the prefix isn't `data`
  → `{seriesIndex, seriesName, seriesId, xAxisIndex, geoId, legendName, …}`
* data query: exactly `name`, `dataIndex`, `dataType`
* other query: everything else, forwarded to `view.filterForExposedEvent(...)`.
  The only implementation is `CustomView.filterForExposedEvent`, which matches
  `query.element` against `targetEl.name`, walking up `__hostTarget`/`parent` to the series group —
  so `chart.on('click', {element: 'my_el'}, …)` works on named sub-elements of a custom series.

Matching is `query[prop] == null || host[prop] === query[prop]` — i.e. all specified keys must match,
unspecified keys are wildcards.

### 6.4 Non-mouse events — the complete list

Every event below is produced by dispatching (or by the built-in view code dispatching) the
corresponding action. **Event names are always lowercased.** Grouped by owning module:

| Event | Action that emits it | Payload highlights |
|---|---|---|
| `highlight` | `highlight` | the action payload |
| `downplay` | `downplay` | the action payload |
| `selectchanged` | `select`, `unselect`, `toggleSelect` | `{fromAction, isFromClick, selected: [{seriesIndex, dataIndex[]}]}` — a **refined** event built by `makeSelectChangedEvent` |
| `select` / `unselect` / `toggleselect` | same three | deprecated non-refined duplicates, still published |
| `legendselectchanged` | `legendToggleSelect` | `{name, selected: {[name]: boolean}}` |
| `legendselected` | `legendSelect` | |
| `legendunselected` | `legendUnSelect` | |
| `legendselectall` | `legendAllSelect` | |
| `legendinverseselect` | `legendInverseSelect` | |
| `legendscroll` | `legendScroll` | `{scrollDataIndex, legendId}` |
| `axisbreakchanged` | `expandAxisBreak`, `collapseAxisBreak`, `toggleAxisBreak` | refined: `{fromAction, fromActionPayload, breaks:[{start,end,isExpanded,old:{isExpanded},xAxisIndex?…}]}`. **Not** fired by `setOption`. 6.0+ |
| `datazoom` | `dataZoom` | `{start, end, startValue?, endValue?}` |
| `datarangeselected` | `selectDataRange` | `{selected}` (array for continuous visualMap, index→bool map for piecewise) |
| `graphroam` | `graphRoam` | `{seriesId, zoom, originX, originY}` |
| `sankeyroam` | `sankeyRoam` | same shape |
| `treeroam` | `treeRoam` | pan form `{seriesId,dx,dy}` or zoom form `{seriesId,zoom,originX,originY}` |
| `georoam` | `geoRoam` | `{componentType:'geo'\|'series', seriesId, zoom, totalZoom, originX, originY}` |
| `geoselectchanged` / `geoselected` / `geounselected` | `geoToggleSelect` / `geoSelect` / `geoUnSelect` | `{name, allSelected:[{geoIndex,name[]}], selected}` |
| `timelinechanged` | `timelineChange` | `{currentIndex}` |
| `timelineplaychanged` | `timelinePlayChange` | `{playState}` |
| `restore` | `restore` | `{}` |
| `dataviewchanged` | `changeDataView` | `{}` |
| `magictypechanged` | `changeMagicType` | `{currentType}` |
| `brush` | `brush` | the areas array |
| `brushend` | `brushEnd` | same |
| `brushselected` | `brushSelect` | `{batch:[{brushId,brushIndex,brushName, areas:[{range,coordRange,coordRanges}], selected:[{seriesIndex,dataIndex[]}]}]}` |
| `globalcursortaken` | `takeGlobalCursor` | `{key, brushOption?/dataZoomSelectActive?}` |
| `axisareaselected` | `axisAreaSelect` | parallel-axis range selection |
| `parallelaxisexpand` | `parallelAxisExpand` | |
| `updateaxispointer` | `updateAxisPointer` | |
| `showtip` / `hidetip` | `showTip` / `hideTip` | |
| `changeaxisorder` | `changeAxisOrder` | bar-race axis reordering |
| `dragnode` | `dragNode` | `{dataIndex, localX, localY}` (sankey) |
| `treeexpandandcollapse` | `treeExpandAndCollapse` | `{dataIndex}` |
| `focusnodeadjacency` / `unfocusnodeadjacency` | same-named actions | graph |
| `treemapzoomtonode`, `treemaprender`, `treemapmove`, `treemaprootonode` | same-named actions | derived event names (type lowercased) |
| `sunburstrootonode`, `sunbursthighlight`, `sunburstunhighlight` | same-named actions | last two deprecated |
| `pieselectchanged`/`pieselected`/`pieunselected`, `mapselectchanged`/`mapselected`/`mapunselected` | legacy `pieSelect`/`mapSelect`/… | deprecated legacy shims, emitted from `handleLegacySelectEvents` |

Two events are **not** action-derived:

| Event | Payload | Meaning |
|---|---|---|
| `rendered` | `{elapsedTime}` | one zrender frame painted. Does **not** mean animation is done. |
| `finished` | none | animation finished **and** progressive rendering finished. Docs warn to register it *before* `setOption` when `animation: false`, or the timing may miss it. |

**Count:** 9 mouse events + ~45 distinct action-derived events + 2 render-lifecycle events.

### 6.5 Batch

`dispatchAction({type, batch: [...]})` fans the payload out: each batch item is `defaults(item, payload)`,
the action handler runs per item, and the resulting event is
`{type, batch: [eventObj…], escapeConnect}` instead of a flat object. Handlers must cope with both shapes.

---

## 7. Actions — the complete `dispatchAction` catalogue

Compiled from every `registerAction` call site in `src/`. **~46 action types.**
`update` is the pipeline level from §5.1.

### 7.1 Core (always available)

| Action | Event | update | Query keys |
|---|---|---|---|
| `highlight` | `highlight` | `highlight` | `seriesIndex/Id/Name` (arrays ok) + `dataIndex`/`name`; also `geoIndex/Id/Name` + `name` since 5.1 |
| `downplay` | `downplay` | `downplay` | same |
| `select` | `selectchanged` (+`select`) | `select` | series + data |
| `unselect` | `selectchanged` (+`unselect`) | `unselect` | series + data |
| `toggleSelect` | `selectchanged` (+`toggleselect`) | `toggleSelect` | series + data |

`highlight`/`downplay` take a fast path (`updateDirectly`) that skips data processing, layout and
visual encoding entirely — they only flip element states. Multi-batch `highlight` calls
`allLeaveBlur` once up front.

### 7.2 Axis (6.0+, needs the `AxisBreak` feature installed)

| Action | Event | update |
|---|---|---|
| `expandAxisBreak` | `axisbreakchanged` | `update` |
| `collapseAxisBreak` | `axisbreakchanged` | `update` |
| `toggleAxisBreak` | `axisbreakchanged` | `update` |

Payload: axis query (`xAxisIndex \| 'all'`, `yAxis*`, `singleAxis*`) plus
`breaks: [{start, end}]` identifying existing break items. Cannot create new breaks.

### 7.3 Legend

`legendSelect` → `legendselected` · `legendUnSelect` → `legendunselected` ·
`legendToggleSelect` → `legendselectchanged` · `legendAllSelect` → `legendselectall` ·
`legendInverseSelect` → `legendinverseselect` · `legendScroll` → `legendscroll`
(the last only for `legend.type: 'scroll'`; payload `{scrollDataIndex, legendId?, legendIndex?}`).
`legendAllSelect`/`legendInverseSelect` accept `legendId`/`legendIndex` since 5.6.

### 7.4 Tooltip

| Action | update | Payload |
|---|---|---|
| `showTip` | `tooltip:manuallyShowTip` | three forms: (a) `{x, y, position?}` screen coords; (b) `{seriesIndex?, dataIndex \| name, position?}`; (c) `{geoIndex/Id/Name, name, position?}` (5.1+) |
| `hideTip` | `tooltip:manuallyHideTip` | `{}` |

### 7.5 axisPointer

`updateAxisPointer` → event `updateaxispointer`, update `':updateAxisPointer'` (broadcast to all views).

### 7.6 dataZoom / global cursor

| Action | Event | Payload |
|---|---|---|
| `dataZoom` | `datazoom` | `{dataZoomIndex?, start?, end?, startValue?, endValue?}` (percent 0–100 or data values) |
| `takeGlobalCursor` | `globalcursortaken` | `{key: 'dataZoomSelect' \| 'brush' \| …, dataZoomSelectActive?: bool, brushOption?: {brushType, brushMode}}` — a **mutex**: only one global-cursor consumer at a time; no `key` releases it |

### 7.7 visualMap

`selectDataRange` → `datarangeselected`, update `update`.
Payload `{visualMapIndex?, selected}` where `selected` is `[min,max]` for continuous or
`{pieceIndexOrCategory: boolean}` for piecewise.

### 7.8 Timeline

`timelineChange` → `timelinechanged`, update `prepareAndUpdate`, payload `{currentIndex}`.
Auto-stops playback and re-dispatches `timelinePlayChange{playState:false}` when it hits the end with
`loop:false`. Also triggers `ecModel.resetOption('timeline', {replaceMerge})`.
`timelinePlayChange` → `timelineplaychanged`, update `update`, payload `{playState: boolean}`.

### 7.9 Toolbox

`restore` → `restore`, `prepareAndUpdate` (calls `ecModel.resetOption('recreate')`).
`changeDataView` → `dataviewchanged`, `prepareAndUpdate`, payload `{newOption}`.
`changeMagicType` → `magictypechanged`, `prepareAndUpdate`, payload `{newOption, currentType}`.

### 7.10 Geo

`geoSelect` → `geoselected` · `geoUnSelect` → `geounselected` · `geoToggleSelect` → `geoselectchanged`
(all update `'geo:updateSelectStatus'`, payload `{geoIndex/Id/Name, name}`).
`geoRoam` → `georoam`, update `updateTransform`, payload `{componentType?, geoIndex?, dx, dy, zoom, originX, originY}`;
it also serves `series.map` (historical naming).

### 7.11 Brush

`brush` → `brush`, update `updateVisual`, payload `{areas: [...]}`. Each area:
`{brushType: 'rect'|'polygon'|'lineX'|'lineY', geoIndex?|xAxisIndex?|yAxisIndex?, range?|coordRange?}`.
`range` is in pixels for a "global area"; `coordRange` is in data/geo coordinates for a
"coordinate system area" (and then the box translates and scales with the coord system).
Geometry: rect → `[[minX,maxX],[minY,maxY]]`; lineX/lineY → `[min,max]`; polygon → `[[x,y],…]`.
`brushEnd` → `brushend`, update `none` (fired when the gesture completes).
`brushSelect` → `brushselected`, update `none` (fired continuously with the hit indices).
Empty `areas: []` clears all boxes.

### 7.12 Series-specific

| Series | Action | Event | update |
|---|---|---|---|
| bar | `changeAxisOrder` | `changeaxisorder` | `update` — payload `{componentType?, sortInfo}`; the bar-race primitive |
| graph | `focusNodeAdjacency` | `focusnodeadjacency` | `series:focusNodeAdjacency` |
| graph | `unfocusNodeAdjacency` | `unfocusnodeadjacency` | `series:unfocusNodeAdjacency` |
| graph | `graphRoam` | `graphroam` | `none` |
| sankey | `dragNode` | `dragnode` | `update` — payload `{dataIndex, localX, localY}` |
| sankey | `sankeyRoam` | `sankeyroam` | `none` |
| tree | `treeExpandAndCollapse` | `treeexpandandcollapse` | `update` |
| tree | `treeRoam` | `treeroam` | `none` |
| treemap | `treemapZoomToNode` | | `updateView` |
| treemap | `treemapRender` | | `updateView` |
| treemap | `treemapMove` | | `updateView` — payload `{rootRect}` |
| treemap | `treemapRootToNode` | | `updateView` — payload `{targetNodeId \| targetNode, direction: 'rollUp'\|'drillDown'}` |
| sunburst | `sunburstRootToNode` | | `updateView` |
| sunburst | `sunburstHighlight` / `sunburstUnhighlight` | | deprecated → `highlight`/`downplay` |
| parallel | `axisAreaSelect` | `axisareaselected` | payload `{parallelAxisId, intervals}` |
| parallel | `parallelAxisExpand` | `parallelaxisexpand` | payload `{axisExpandWindow}` |
| pie/map (legacy) | `pieSelect/pieUnSelect/pieToggleSelect`, `mapSelect/mapUnSelect/mapToggleSelect` | legacy `*selected/*unselected/*selectchanged` | deprecated shims that re-dispatch `select/unselect/toggleSelect` |

Roam actions are all generated by one helper (`registerRoamActionSimply`) that names them
`<mainType or seriesSubType>Roam`. There are **4 roam actions**: `geoRoam`, `graphRoam`,
`sankeyRoam`, `treeRoam`.

---

## 8. Interaction primitives

### 8.1 Coordinate conversion (`convertToPixel` / `convertFromPixel` / `convertToLayout`)

The `finder` accepts `{xAxis|yAxis|grid|polar|geo|singleAxis|calendar|matrix|series}{Index|Id|Name}`.
A bare string like `'geo'` means `{geoIndex: 0}`.

Per-coordinate-system input formats:
* **cartesian2d**: `[xValue, yValue]`; `value`/`log` axes take numbers, `category` axes take the
  original string *or* its ordinal integer, `time` axes take timestamp/string/`Date`.
* **single axis**: a scalar, returns a scalar pixel.
* **polar**: like cartesian, queried only by `polarIndex/Id/Name`.
* **geo / series-map**: `[lng, lat]` for GeoJSON, `[x, y]` for SVG maps, **or a region name string**
  (returns the region centre pixel).
* **calendar**: a date (timestamp/string/`Date`).
* **matrix** (6.0): `['AA','NN']` cell locators or `[[x0,x1], y]` spans or ordinal numbers.
  `opt.clamp` ∈ `0|1|2|3` (none / whole matrix / body / corner) and `opt.ignoreMergeCells`.
* **series-graph**: the graph's own layout coordinate space.

`convertToLayout` returns `{rect, contentRect}` for calendar (cell box vs. box minus border) and
`{rect, matrixXYLocatorRange}` for matrix.

The source carries an explicit performance warning: these do a component lookup per call and are
unsuitable for hot loops over massive data.

### 8.2 Roam (pan/zoom)

`roam` is offered on every "view coordinate system": `geo`, `series.map`, `series.graph`,
`series.tree`, `series.sankey`, `series.treemap` (its own variant), `series.sunburst`.

* `roam: false | true | 'scale' | 'zoom' | 'move' | 'pan'` — 4 distinct behaviours from 6 spellings.
* `scaleLimit: {min, max}` — zoom clamp (`<1` = zoomed out, `>1` = zoomed in).
* `roamTrigger: 'selfRect' | 'global'` (6.0+) — whether wheel/drag is captured only over the
  content's bounding rect, or anywhere on the canvas (respecting `clip`).
* Roam mutates `center` and `zoom` in the live option, so `getOption()` round-trips the viewport.
* `preserveAspect: false|'contain'|true|'cover'` + `preserveAspectAlign: left|right|center` +
  `preserveAspectVerticalAlign: top|bottom|middle` (6.0+) — how content is fitted into its
  allocated rect. This is `object-fit` semantics, expressed as options.
* The `thumbnail` component (6.0, **graph only**) renders a mini-map with a draggable window rect
  (`itemStyle`, `windowStyle`) that drives the roam viewport.

### 8.3 Inside dataZoom — modifier-gated gestures

`dataZoom.type: 'inside'` exposes an unusually explicit gesture-binding vocabulary:

| Option | Values |
|---|---|
| `zoomOnMouseWheel` | `true \| false \| 'shift' \| 'ctrl' \| 'alt'` |
| `moveOnMouseMove` | `true \| false \| 'shift' \| 'ctrl' \| 'alt'` |
| `moveOnMouseWheel` | `true \| false \| 'shift' \| 'ctrl' \| 'alt'` |
| `preventDefaultMouseMove` | boolean, default `true` |
| `disabled` | boolean |

Plus `dataZoom.type: 'slider'` (drag handles, brush-inside-slider) and the toolbox
`dataZoom` feature (marquee zoom + "zoom reset" button), which drives the same actions.
**3 dataZoom mechanisms total**: inside, slider, toolbox-select.

### 8.4 Drag

Only two things are draggable: `sankey` nodes (via the `dragNode` action) and
`graphic` component elements (`draggable: true | 'horizontal' | 'vertical'`, with
`ondragstart/ondrag/ondragend/ondragenter/ondragleave/ondragover` callbacks).
Graph nodes are draggable via `series.graph.draggable`.

### 8.5 Hit-testing switches

| Option | Where | Semantics |
|---|---|---|
| `silent: boolean` | most series, geo, calendar, graphic, markPoint/Line/Area, matrix regions, axes | `true` = element ignores pointer entirely: no tooltip, no emphasis, no hover-link, and **no dispatch to user listeners** |
| `triggerEvent: boolean` | axis (`axisLabel`/`axisName`), legend, title, matrix, line series | Opt *in* to emitting the 9 mouse events from a non-data component. Requires `silent` falsy. |
| `cursor: string` | bar, line, scatter, effectScatter, pie, graph, candlestick, pictorialBar, treemap, matrix cells, graphic elements; also `dataZoom.cursorGrab`/`cursorGrabbing` | CSS cursor name, default `'pointer'` |
| `ignore` | graphic elements | neither rendered nor hit-tested |
| `invisible` | graphic elements | not rendered but **still hit-tested** |
| `z` / `zlevel` | every component and series | see below |

### 8.6 z / zlevel and hit ordering

`zlevel` selects a separate painting layer (in canvas mode, a separate `<canvas>`; in a native port,
a separate cached surface); `z` orders within a layer. `allocateZlevels` in `core/echarts.ts`
auto-assigns zlevels when any component declares a `getZLevelKey()` (used to isolate blend-mode or
animation-heavy series), sorting components before series. `updateZ` then walks each view's rendered
elements and stamps `z`/`zlevel` unless the model sets `preventAutoZ`.

Related: `series.blendMode` (`updateBlend`), and a `hoverLayerThreshold` that promotes hovered
elements to a dedicated hover layer past a size threshold (`usingTHL`).

### 8.7 Element states

Four states drive all visual interaction: `normal`, `emphasis`, `blur`, `select`.
The `ExtensionAPI` exposes `enterEmphasis/leaveEmphasis`, `enterBlur/leaveBlur`,
`enterSelect/leaveSelect`. `emphasis.focus: 'none'|'self'|'series'|'ancestor'|'descendant'|'adjacency'`
plus `emphasis.blurScope: 'coordinateSystem'|'series'|'global'` decide *what else* gets blurred.
`stateAnimation: {duration, easing}` animates state transitions.

---

## 9. Responsive: the `media` option

`OptionManager` implements a CSS-media-query analogue entirely inside the option tree:

```
option = {
  baseOption: { ... },
  media: [
    { option: {...} },                        // the default (no `query`)
    { query: {maxWidth: 320}, option: {...} },
    { query: {minWidth: 320, maxWidth: 720}, option: {...} }
  ]
}
```

Query keys — **6 total**: `minWidth`, `maxWidth`, `minHeight`, `maxHeight`,
`minAspectRatio`, `maxAspectRatio`. `aspectRatio = width / height`.
The matcher (`applyMediaQuery`) parses each key with a regex into (operator, attribute),
looks the attribute up in `{width, height, aspectratio}` and ANDs the comparisons.

Selection rules:
* **All** matching media units are applied, in declaration order — later declarations win.
* If none match, the unit with no `query` (the "media default") is applied.
* The result is only recomputed when the matching index set actually changes
  (`indicesEquals(indices, this._currentMediaIndices)`), so resizing within a band is free.
* Re-evaluated from `resize()` via `ecModel.resetOption('media')`.

Media and timeline options are **not merged** with each other — each unit's option is cloned and
applied on top of `baseOption`.

---

## 10. Chart linkage (`connect`)

`connect(groupId | charts[])` sets `chart.group` and flips `connectedGroups[groupId] = true`.
`enableConnect` subscribes each instance to **every registered event type**; when one fires and the
instance is in an active group and not already updating, it converts the event back to an action via
`connectionEventRevertMap` (built by `registerAction`, one entry per action) and re-dispatches it to
every sibling with a `CONNECT_STATUS_*` re-entrancy guard.
`payload.escapeConnect = true` opts an action out of propagation (refined events set it automatically).
`getConnectedDataURL` composites the group into one bitmap.

This is why `registerAction` asserts that no two actions share an event name unless `refineEvent` is used.

---

## 11. i18n

`registerLocale(name, obj)` — name is upper-cased. Built-ins: `EN`, `ZH` (+24 more shipped in
`src/i18n/`: AR, CS, DE, EL, ES, FA, FI, FR, HU, IT, JA, KO, LV, NL, PL, PT-br, RO, RU, SI, SV, TH,
TR, UK, VI, nb-NO — **26 locale files total**). A non-built-in locale is merged over `EN` so gaps
fall back to English.

The localisable surface is small and completely enumerable (`src/i18n/langEN.ts`):

| Section | Strings |
|---|---|
| `time` | `month[12]`, `monthAbbr[12]`, `dayOfWeek[7]`, `dayOfWeekAbbr[7]` |
| `legend.selector` | `all`, `inverse` |
| `toolbox.brush.title` | `rect`, `polygon`, `lineX`, `lineY`, `keep`, `clear` |
| `toolbox.dataView` | `title`, `lang[3]` |
| `toolbox.dataZoom.title` | `zoom`, `back` |
| `toolbox.magicType.title` | `line`, `bar`, `stack`, `tiled` |
| `toolbox.restore.title` | 1 |
| `toolbox.saveAsImage` | `title`, `lang[1]` |
| `series.typeNames` | 24 readable series names (`pie`→"Pie chart", `k`→"K line chart", …) |
| `aria.general` | `withTitle` / `withoutTitle` templates |
| `aria.series.single` / `.multiple` | prefix / withName / withoutName / separators |
| `aria.data` | `allData`, `partialData`, `withName`, `withoutName`, separators |

Locale detection when none is given: `document.documentElement.lang || navigator.language`, upper-cased,
`'ZH'` if it contains ZH else `'EN'`. In a non-DOM environment it is hard-coded to `EN`.

Note the time-axis formatter and `echarts.time.format` both take the locale model, so month/weekday
names on axes are localised automatically.

---

## 12. Loading indicator

`showLoading(name?, cfg?)` / `hideLoading()`. Only **one** effect is registered by default: `'default'`
(`registerLoading('default', loadingDefault)`); `registerLoading(name, fn)` adds more.
`showLoading` calls `hideLoading` first, so it is idempotent.

Default effect options (`src/loading/default.ts`) — a full-canvas mask rect + optional spinning arc + text:

| Option | Default |
|---|---|
| `text` | `'loading'` |
| `color` | theme token `color.theme[0]` (spinner arc) |
| `textColor` | token `color.primary` |
| `maskColor` | `'rgba(255,255,255,0.8)'` |
| `zlevel` | `0` (mask is drawn at `z: 10000`) |
| `showSpinner` | `true` |
| `spinnerRadius` | `10` |
| `lineWidth` | `5` |
| `fontSize` / `fontWeight` / `fontStyle` / `fontFamily` | `12` / `'normal'` / `'normal'` / `'sans-serif'` |

The effect object exposes `resize()`, which `chart.resize()` calls.

---

## 13. SSR / headless / image output

Three distinct output paths:

1. **Canvas raster** — `renderToCanvas({backgroundColor, pixelRatio}) → HTMLCanvasElement`, and
   `getDataURL({type:'png'|'jpeg', pixelRatio, backgroundColor, excludeComponents})`.
2. **SVG string** — `renderToSVGString({useViewBox})`, `getSvgDataURL()`, and
   `getDataURL({type:'svg'})`. `getSvgDataURL` stops all animations first so the snapshot is final.
3. **Connected composite** — `getConnectedDataURL`, which lays out every group member by DOM
   bounding-rect and paints `connectedBackgroundColor` between them. In SVG mode it splices each
   chart's `<svg>` innerHTML into `<g transform="translate(x,y)">` wrappers.

**True SSR mode** (`init(null, null, {ssr: true, width, height, renderer: 'svg'})`):
* no per-frame rendering; `setOption` skips `zr.flush()`;
* you must call `renderToSVGString()`;
* zrender is given an SSR data getter that emits `ecmeta_series_index`, `ecmeta_data_index`,
  `ecmeta_ssr_type` (`'chart' | 'legend'`) and `ecmeta_silent` attributes onto SVG nodes;
* the companion package `ssr/client` exports **one function**, `hydrate(dom, {on: {mouseover, mouseout, click}})`,
  which attaches three DOM listeners to the `<svg>` root and reads those `ecmeta_*` attributes back
  to synthesise `{type, ssrType, seriesIndex, dataIndex, event}`. That is the *entire* SSR interaction
  model — no ECharts runtime on the client.

`setPlatformAPI({createCanvas, measureText, loadImage})` is the portability seam that makes node
rendering work at all — `measureText` in particular.

---

## 14. Accessibility (`aria`)

`aria.enabled: false` by default. When enabled ECharts generates a natural-language description of
the chart and puts it in an `aria-label` on the container. Option tree:

* `aria.label.enabled`, `aria.label.description` (a hand-written override)
* `aria.label.general.withTitle` / `.withoutTitle` — templates with `{title}`
* `aria.label.series.maxCount` (10), `.single.{prefix,withName,withoutName}`,
  `.multiple.{prefix,withName,withoutName,separator.{middle,end}}` — templates with
  `{seriesCount} {seriesId} {seriesType} {seriesName}`
* `aria.label.data.maxCount` (10), `.allData`, `.partialData` (`{displayCnt}`),
  `.withName` (`{name}`, `{value}`), `.withoutName`, `.excludeDimensionId`, `.separator.{middle,end}`
* `aria.decal.show` + `aria.decal.decals` — **a genuinely non-textual accessibility feature**:
  auto-assigns hatch/dot/pattern decals per series so colour-blind users can distinguish them.
  This one is a real rendering capability, not a DOM attribute.

---

## 15. Things that are browser-shaped

Flagging explicitly, because these do not survive a port unchanged:

* **`renderer: 'svg'`, `renderToSVGString`, `getSvgDataURL`, the whole SSR client, and
  `ecmeta_*` attributes** — SVG/DOM specific. A native control has one renderer.
* **Tooltip `renderMode: 'html'`** (default) with `appendToBody`, `appendTo`, `className`,
  `extraCssText`, `transitionDuration`, `enterable` — the default tooltip is a positioned `<div>`
  styled with CSS, capable of overflowing the chart. `renderMode: 'richText'` is the canvas-drawn
  fallback and is the only mode a native port can mirror. `confine: true` and `enterable` only make
  sense in the DOM mode.
* **`cursor`** — CSS cursor names. Maps to `TCursor` in LCL, but the vocabulary differs.
* **`getDataURL` returning a base64 data-URI** — a native port returns a bitmap object.
* **`devicePixelRatio` defaulting to `window.devicePixelRatio`** — replace with the LCL/Windows
  DPI scale.
* **`locale` auto-detection from `navigator.language`** — replace with OS locale.
* **Toolbox `saveAsImage`** triggers a browser download (`windowOpen`/anchor `download`); `dataView`
  opens a `<textarea>` overlay — both need native re-thinks (file dialog, native memo).
* **`echarts-gl` series** (scatterGL, linesGL, polygons3D, all `*3D`) — WebGL, entirely out of scope.
  Only `appendData`'s doc mentions them; they are not in this repo.
* **`graphic` element `on*` callbacks** — JS function values inside the option tree. A native option
  tree would use event handlers / method pointers instead.
* **`useDirtyRect`** — a canvas-layer optimisation; the native analogue is invalidate-rect painting,
  which the LCL already gives you, but the *layer* concept (`zlevel` → separate canvas) has to be
  built by hand.

---

## Porting notes

Classification for a Free Pascal / Lazarus + BGRABitmap immediate-mode control.

### NATURAL — maps cleanly

| Capability | Note |
|---|---|
| `init` opts `width`/`height`/`devicePixelRatio` | Control bounds + DPI scale. |
| `renderer: 'canvas'` only | One renderer; drop the SVG axis entirely. |
| The 9 mouse events (`click, dblclick, mouseover, mouseout, mousemove, mousedown, mouseup, globalout, contextmenu`) | LCL gives all of these; `globalout` = `OnMouseLeave`. Publish as `TNotifyEvent`-style with a payload record. |
| Event payload record (`componentType, componentIndex, seriesIndex, seriesName, dataIndex, dataType, name, value, color, info`) | A plain Pascal record. This is the single most portable piece of the design. |
| `on/off/one`, event names lowercased | `TxxxEvent` properties, or a small multicast list. |
| `dispatchAction` as a typed command | A Pascal method or a variant record dispatch. Far cleaner than JS objects. |
| Action `update:` levels (`prepareAndUpdate / update / updateTransform / updateView / updateVisual / updateLayout / none`) | Adopt verbatim — this is a well-designed invalidation ladder and it is the reason ECharts stays fast. |
| `highlight` / `downplay` / `select` / `unselect` / `toggleSelect` + 4 element states | State machine over drawn elements; repaint only. |
| Legend actions (6) | Trivial state + repaint. |
| `showTip` / `hideTip` (with `renderMode: 'richText'` semantics) | Draw the tooltip on the canvas or in a borderless popup window. |
| `dataZoom` action, `datazoom` event | Window over the axis extent. |
| `timelineChange` / `timelinePlayChange` | A timer + index. |
| `restore` | Snapshot the original option. |
| `takeGlobalCursor` mutex | One "active gesture owner" field. |
| `silent`, `triggerEvent`, `cursor`, `ignore`, `invisible` | Direct analogues; `cursor` needs a name→`TCursor` table. |
| `z` / `zlevel` ordering | Sort the display list. `zlevel` → separate cached `TBGRABitmap` layers (you already have `TTyPaintCache` for exactly this — note the `pf24bit` rule for opaque layers). |
| `showLoading` default effect | Mask rect + arc + text; ~40 lines of BGRABitmap. |
| `resize` (+ `resize.animation`) | `OnResize` → recompute layout. |
| `clear` / `dispose` / `isDisposed` | Ordinary lifetime. |
| `getOption()` round-trip | If your option model is a component tree, serialising it back is natural (and is how `.lfm` already works). |
| `registerTheme` / `setTheme` | You already have a richer theme system (`.tycss`); the ECharts analogue is a strict subset. |
| `registerLocale` + the ~60 localisable strings | `resourcestring` + per-package `.po`, exactly your existing i18n setup. Note month/weekday arrays must be locale-driven, not hard-coded. |
| `echarts.time.format` 24-token vocabulary + `roundTime` | Pure date math. Worth copying token-for-token so users' format strings port. |
| `echarts.number` helpers (`linearMap, nice, quantile, getPrecision, parsePercent, …`) | Pure math, ~200 lines. |
| `media` queries (6 keys, AND-of-comparisons, last-match-wins, recompute only on index-set change) | ~60 lines. Genuinely useful for a resizable desktop chart. |
| `aria.decal` patterns | A real rendering feature: hatch/dot fills. BGRABitmap does textures/patterns fine. |
| `useCoarsePointer` / `pointerSize` | Hit-test inflation — useful on touch-enabled Windows tablets. |
| `getDataURL` → return a `TBGRABitmap`/`TBitmap` instead of a data-URI | Straight substitution. Honour `excludeComponents` by skipping those views. |

### HEAVY — doable, but real algorithms

| Capability | The algorithm you actually have to write |
|---|---|
| **`setOption` Normal Merge** | Two-pass id/name-then-positional mapping with stable `componentIndex`. Not hard, but the *rules* must be exact or user options silently land on the wrong component. Write the doc's worked example as a test. |
| **`setOption` Replace Merge** | Same, plus "remove unmatched, leave index holes, refill freed slots". The hole-preserving requirement is what makes `xAxisIndex: 2` references survive. |
| **`lazyUpdate` + pending-update coalescing** | A "dirty, update next frame" queue with correct interaction against `resize` and `dispatchAction` (ECharts has explicit code merging a pending update into a subsequent resize/action). |
| **Re-entrancy guard** (`IN_EC_CYCLE_KEY`, `_pendingActions`) | Actions dispatched from inside event handlers must queue, not recurse. ECharts learned this the hard way; copy it. |
| **The staged pipeline** (preprocessor → processor → coordsys → visual → layout → render, priority-sorted) | This is the architecture. Porting it is the project. |
| **Progressive / streaming render** (`_onframe` time-budgeted `do…while`, `appendData`) | Time-sliced rendering with a per-frame budget. Needs an idle/timer pump and incremental display lists. |
| **`convertToPixel` / `convertFromPixel` / `containPixel`** per coordinate system | One `dataToPoint`/`pointToData`/`containPoint` per coord system (cartesian, polar, geo, single, calendar, matrix, graph). Individually easy, collectively substantial. Note the source's own warning that the component-lookup makes them unsuitable for hot loops — expose a cheaper direct-axis path. |
| **`convertToLayout`** (calendar/matrix cell rects, merged-cell expansion, 4 clamp modes) | Cell-locator arithmetic plus merge-span resolution. |
| **Roam** (pan/zoom on geo/graph/tree/sankey/treemap) | Affine viewport transform + `scaleLimit` clamping + `roamTrigger` hit region + `preserveAspect` (`contain`/`cover` + 3×3 alignment). This is `object-fit` + a pan/zoom controller. |
| **`thumbnail` mini-map** | A second render of the same scene at reduced scale with a draggable viewport rect. |
| **Brush** (`rect`/`polygon`/`lineX`/`lineY`, global vs coord-system areas, `range` vs `coordRange`, boxes that move/scale with the coord system) | Polygon point-in-shape testing (even-odd or winding) plus per-series index collection, plus the throttled `brushselected` batch. The polygon lasso over N points is the expensive part — needs spatial indexing above a few thousand items. |
| **Inside-dataZoom gesture grammar** (wheel/move × `true/false/shift/ctrl/alt`) | Modifier-aware gesture arbitration; also has to cooperate with roam and brush through the global-cursor mutex. Your `designer-hittest-gesture-consistency` lesson applies directly: arm on down, **release on up**. |
| **`connect` group replay** | Event→action reversal table plus a 3-state re-entrancy guard per instance. Straightforward once the action table exists, but the guard is essential or you get infinite ping-pong. |
| **`getConnectedDataURL`** | Composite N control bitmaps by screen position. Easy once you can screenshot one control — but remember the `BGRA MakeBitmapCopy` black-image trap: composite `TBGRABitmap`s directly, don't round-trip through `TPicture`. |
| **`aria` description generation** | Template interpolation over series/data with `maxCount` truncation and separator rules. Cheap code, fiddly text. |
| **Query filtering on `on()`** (`'series.line'`, `{seriesIndex, name, dataIndex, dataType, element}`) | Suffix-splitting a property bag into component/data/other buckets, then a wildcard match. ~80 lines but it is what makes the event API usable at scale. |
| **`emphasis.focus: 'adjacency'` / `'ancestor'` / `'descendant'` + `blurScope`** | Graph/tree traversal to decide the blur set on every hover. Needs adjacency structures kept alongside the data. |
| **Batch actions** (`payload.batch`) | Fan-out plus a differently-shaped event object. Decide early whether you support it; retrofitting the event shape is painful. |

### BROWSER-BOUND — needs a native re-think or is out of scope

| Capability | Verdict |
|---|---|
| `renderer: 'svg'`, `renderToSVGString`, `getSvgDataURL`, `getDataURL({type:'svg'})`, `useViewBox` | Out of scope. If vector export is ever wanted, emit EMF/PDF from the same display list — a separate back-end, not this option. |
| SSR mode (`ssr: true`) + `ssr/client` `hydrate()` + `ecmeta_*` attributes | Meaningless natively. The equivalent "headless render" is just rendering to an offscreen `TBGRABitmap` — which you get for free. Keep the *idea* (render without a window) and drop the machinery. |
| Tooltip `renderMode: 'html'`, `appendToBody`, `appendTo`, `className`, `extraCssText`, `transitionDuration`, `enterable`, `confine` | DOM/CSS. Native equivalent: a borderless top-level popup (you already have `TTyForm` chrome + `WindowEffects`); `confine` becomes "clamp to control rect", `enterable` becomes "popup accepts mouse". Re-think, don't port. |
| `devicePixelRatio` from `window.devicePixelRatio`; `locale` from `navigator.language`; `document.documentElement.lang` | Replace with LCL DPI and OS locale. |
| Toolbox `saveAsImage` (browser download), `dataView` (`<textarea>` overlay), `restore`'s reliance on them | Re-think as a native save dialog and a native grid/memo. The *actions* (`restore`, `changeDataView`, `changeMagicType`) are portable; their UI is not. |
| `cursor` as CSS strings | Needs a name→`TCursor` mapping table; unmapped names must degrade, not crash. |
| `setPlatformAPI({createCanvas, measureText, loadImage})` | The whole abstraction exists because JS has no native text metrics. You have `TCanvas.TextExtent` / BGRABitmap measurement — delete the seam. (But heed your own `Empty FontName` and `BGRA small-text blur` lessons: text measurement is where cross-platform charts actually break.) |
| `echarts-gl` (`scatterGL`, `linesGL`, `polygons3D`, all `*3D`) | WebGL. Out of scope, and not even in this repo. |
| `graphic` component `onclick`/`ondrag`/… function-valued options | Function values inside a declarative tree. Natively these become published event properties on a graphic-element object. |
| `useDirtyRect` | The concept survives (invalidate-rect), but as an implementation detail of your painting, not a public option. Note that `zlevel` → "separate canvas layer" *is* worth porting as cached surfaces. |
| `windowOpen` / anchor-download used by image export | Native file dialog. |
| `env.browser.weChat` special-casing in `dispatchAction` flush throttling | Delete. |
