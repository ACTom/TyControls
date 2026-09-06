# ECharts 6.1.0 — The Non-Coordinate UI Components

Research pass for a native Object Pascal / BGRABitmap chart control. Sources read:
`D:/Projects/echarts` (v6.1.0 TS source, `src/component/*`, `src/visual/*`, `src/util/*`) and
`D:/Projects/echarts-doc/en/option/component/*.md` + `en/option/partial/*.md` (official option reference,
`${partial}` / `{{ use: }}` macros resolved by reading the referenced partial).

Scope: `title`, `legend`, `tooltip` (+ `axisPointer`), `toolbox`, `dataZoom`, `visualMap`, `brush`,
`timeline`, `markPoint` / `markLine` / `markArea`, `graphic`, `aria` (+ `decal`), `thumbnail`.
Coordinate systems, series and `dataset` are covered elsewhere.

---

## 0. Inventory at a glance

| Component | Sub-types | Source dir | Distinct capability, in one line |
|---|---|---|---|
| `title` | 1 (multi-instance) | `component/title/install.ts` | Main + sub text block, box-positioned, clickable hyperlinks |
| `legend` | 2 (`plain`, `scroll`) | `component/legend/` | Series/datum visibility toggler, symbol+label rows, paging, select-all/inverse buttons |
| `tooltip` | 2 render modes (`html`, `richText`) | `component/tooltip/` | Hover data readout; **`richText` is the DOM-free path** |
| `axisPointer` | 4 types (`line`,`shadow`,`cross`,`none`) | `component/axisPointer/` | Crosshair + axis value label, cross-coordinate-system linking |
| `toolbox` | 6 built-in features + `myXxx` | `component/toolbox/` | Icon strip: export, restore, data table, marquee zoom, chart-type switch, brush |
| `dataZoom` | 3 (`inside`, `slider`, `select`) | `component/dataZoom/` | Windowing of axis extents with 4 data-filtering semantics |
| `visualMap` | 2 (`continuous`, `piecewise`) | `component/visualMap/` | Value → 8 visual channels, plus an interactive range/piece selector widget |
| `brush` | 4 shapes | `component/brush/` + `component/helper/BrushController.ts` | Marquee selection → cross-series visual filtering (`brushSelected`) |
| `timeline` | 1 (`slider`) | `component/timeline/` | Play/step through an array of whole chart options |
| `markPoint` / `markLine` / `markArea` | 3 | `component/marker/` | Annotations resolved against data statistics or coordinates |
| `graphic` | 13 element types | `component/graphic/` | Free-form vector overlay with `$action` merge semantics |
| `aria` | — | `src/visual/aria.ts`, `src/util/decal.ts` | Auto screen-reader description + **decal pattern fills** |
| `thumbnail` | 1 (**new in v6.0**) | `component/thumbnail/` | Mini-map / viewport window for `series.graph` roaming |

Countable totals: **13 component families**, **2 legend types**, **3 dataZoom types**, **4 dataZoom filter
modes**, **2 visualMap types**, **8 visual channels**, **4 brush shapes**, **6 toolbox features**,
**13 graphic element types**, **4 axisPointer types**, **3 timeline axis types**, **4 marker statistic types**.

---

## 1. Cross-cutting mechanics (read this first — it is 60% of the port)

Every component in this document reuses the same six substrates. Implementing these once buys most of
the component surface.

### 1.1 Box layout (`partial-rect-layout` / `partial-rect-layout-width-height`)

`left` / `top` / `right` / `bottom` / `width` / `height`, each accepting:
- a pixel number (`20`),
- a percentage string relative to the container (`'20%'`),
- for `left`: `'left'` | `'center'` | `'right'`; for `top`: `'top'` | `'middle'` | `'bottom'`.
`width`/`height` default to `'auto'` (content-driven). Used by title, legend, toolbox, timeline, visualMap,
dataZoom-slider, thumbnail, graphic elements. `ComponentModel.layoutMode = 'box'` marks a component as
participating. Layout resolution lives in `src/util/layout.ts` (`getLayoutRect`, `createBoxLayoutReference`).

### 1.2 `coordinateSystem` on non-series components (**new in v6.0.0**)

`title`, `legend`, `toolbox`, `timeline`, `visualMap`, `dataZoom-slider`, `thumbnail` all gained
`coordinateSystem` with values `'none'` (default — laid out against the whole canvas), `'matrix'`, and
`'calendar'`. That means a legend or a title can be laid out **inside a matrix cell or a calendar cell**
rather than against the chart container. This is a real distinct capability, not a styling knob.

### 1.3 `z` / `zlevel` / `z2`

Painter ordering. `zlevel` maps to separate canvas layers in the browser; `z` and `z2` are in-layer sort
keys. For an immediate-mode painter, all three collapse to a single sort key before drawing.

### 1.4 Component chrome (`partial-component-common-style`)

`backgroundColor`, `borderColor`, `borderWidth`, `borderRadius` (number or 4-corner array),
`shadowBlur` / `shadowColor` / `shadowOffsetX` / `shadowOffsetY`, `padding` (number or `[T,R,B,L]`).
Applied to title, legend, toolbox, tooltip, visualMap.

### 1.5 Text style + rich text (`partial-text-style`)

Base: `color`, `fontStyle` (`normal`/`italic`/`oblique`), `fontWeight` (`normal`/`bold`/`bolder`/`lighter`/number),
`fontFamily`, `fontSize`, `lineHeight`, `align`, `verticalAlign`, `width`, `height`,
`overflow` (`'none'` | `'truncate'` | `'break'` | `'breakAll'`), `ellipsis` (default `'...'`),
`backgroundColor` (color **or** `{image: ...}`), `borderColor/Width/Radius`, `padding`,
`shadow*`, `textBorderColor/Width/Type/DashOffset`, `textShadow*`.

`rich: { <styleName>: { ...same properties... } }` plus the inline markup `{styleName|text}` gives
per-fragment styling inside one text block — different colors, backgrounds, images, per-fragment padding.
This is how ECharts fakes a table layout inside a canvas-drawn tooltip. **This is the mechanism the
DOM-free tooltip depends on.**

### 1.6 The symbol / icon vocabulary

Anywhere an option is called `icon`, `symbol`, `handleIcon`, `pageIcons`, `playIcon`, `itemSymbol`:
- Built-in names (from `src/util/symbol.ts` `symbolCtors`): `'circle'`, `'rect'`, `'roundRect'`,
  `'square'`, `'triangle'`, `'diamond'`, `'pin'`, `'arrow'`, `'line'`, plus `'none'`.
  *(The doc partial `partial-icon-buildin` lists only 8; the source registers 9 + `none`.)*
- `'empty'` prefix (`'emptyCircle'`, `'emptyRect'`, …) → hollow variant: white/`inheritColor` fill,
  stroke in the data color.
- `'path://<SVG PathData>'` — arbitrary vector path, auto-scaled into the slot.
- `'image://<url>'` or `'image://data:image/...;base64,...'` — raster.
Plus `symbolSize` (number or `[w,h]`), `symbolRotate` (degrees, or `'inherit'`), `symbolOffset`,
`symbolKeepAspect`.

### 1.7 Formatter conventions

Two forms everywhere:
- **String template** with `{a}` series name, `{b}` data name/category, `{c}` value, `{d}` percent,
  `{e}`; indexed variants `{a0}`, `{b1}`, `{c2}` in multi-series axis tooltips; `{value}` in axis-pointer
  and dataZoom labels; `{name}` in legend; `{current}`/`{total}` in legend paging.
- **Callback function** receiving a params object/array. Every callback form is a JS closure —
  a native port replaces these with an event/interface hook, not an option value.

---

## 2. `title`

Purpose: a text block (headline + subhead) positioned anywhere on the canvas. **Multiple title components
are allowed** in one instance (since v3) — the option is an array — which is how ECharts labels each grid
in a multi-grid layout.

| Option | Type / values | Semantics |
|---|---|---|
| `show` | boolean = true | |
| `text` | string | Main title; `\n` is an explicit line break |
| `link` / `target` | string / `'self'` \| `'blank'` | Hyperlink on the main text. Implemented as `windowOpen(link, '_'+target)` in `title/install.ts` — **browser-only** |
| `textStyle` | text style, defaults `fontSize:18`, `fontWeight:'bolder'`, `color:'#333'`; no `align`/`verticalAlign`/box | |
| `subtext` | string | Subtitle, `\n` supported |
| `sublink` / `subtarget` | string / `'self'` \| `'blank'` | Hyperlink on the subtitle |
| `subtextStyle` | text style, default color `'#aaa'` | |
| `textAlign` | `'auto'` \| `'left'` \| `'center'` \| `'right'` | Horizontal alignment **of the whole block** (text + subtext together) |
| `textVerticalAlign` | `'auto'` \| `'top'` \| `'middle'` \| `'bottom'` | Vertical alignment of the whole block |
| `itemGap` | number = 10 | Gap between text and subtext |
| `padding` | number \| `[T,R,B,L]` = 5 | |
| `triggerEvent` | boolean = false | Emits `{componentType:'title', componentIndex}` on click |
| box layout | `left/top/right/bottom` | |
| `coordinateSystem` | `'none'`(def) \| `'matrix'` \| `'calendar'` | v6 |
| chrome | `backgroundColor`, `borderColor`, `borderWidth`(def 0), `borderRadius`, `shadow*` | |

The only genuinely non-trivial part is `textAlign`/`textVerticalAlign` decoupling the *block* alignment
from the box anchor; everything else is a two-line text block with a background.

---

## 3. `legend`

Purpose: shows symbol + color + name for each series (or each pie/funnel datum) and toggles their
visibility on click. Multiple legend components allowed.

### 3.1 What a legend item targets

Legend items match **by name string**, many-to-many:
- Default target is `series.name`.
- Names can come from a `dataset` column via `series.encode.seriesName`.
- Six series types let a legend item control an individual **data item** instead of a whole series
  (`LEGEND_CONTROL_SERIES_DATA_ITEM`): **`pie`, `funnel`, `chord`, `graph`, `radar`, `themeRiver`**.
  For those, `series.data[i].name` is collected and the legend item hides that datum.
- Multiple series sharing a name are toggled by one legend item.

### 3.2 Layout / structure

| Option | Values | Notes |
|---|---|---|
| `type` | `'plain'` (def) \| `'scroll'` | |
| `orient` | `'horizontal'` (def) \| `'vertical'` | |
| `align` | `'auto'` \| `'left'` \| `'right'` | Marker-vs-text order. `'auto'` flips to `'right'` when `left:'right'` + vertical |
| `itemGap` | number = 8 (source) / 10 (doc) | Gap between items along the flow axis |
| `itemWidth` / `itemHeight` | 25 / 14 | Symbol slot size |
| `padding` | number \| `[T,R,B,L]` = 5 | |
| `data` | array of string or `{name, icon, itemStyle, lineStyle, textStyle, symbolRotate, inactiveColor, inactiveBorderColor, inactiveBorderWidth}` | Explicit item list with per-item overrides |
| — line-break token | `''` or `'\n'` as a `data` entry | Forces a wrap in the flow layout. A real layout feature |
| box layout + `width`/`height` | | Legend wraps within `width`/`height` |
| `coordinateSystem` | v6: `'none'`/`'matrix'`/`'calendar'` | |

### 3.3 Item appearance

- `icon`: any value from §1.6, or `'inherit'` (take the series' own symbol). If the series implements
  `getLegendIcon` (pie, line-with-symbol, etc.) and `icon` is unset/`'inherit'`, the **series draws its own
  legend glyph** — e.g. the line series draws a horizontal line with the symbol on it, not just a dot.
  Default fallback is `'roundRect'`.
- `itemStyle` (fill/stroke/opacity/borderWidth/borderType/…/**`decal`**) and `lineStyle`
  (width/color/type/cap/join/dashOffset/…), both with the sentinel value `'inherit'` per-property,
  meaning "copy from the series visual". `borderWidth: 'auto'` → 2 if the series has a border else 0.
- Inactive (deselected) rendering: `inactiveColor` (def `#ccc`), `inactiveBorderColor`,
  `inactiveBorderWidth` (`'auto'` \| `'inherit'` \| number), `lineStyle.inactiveColor`,
  `lineStyle.inactiveWidth` (def 2). Text also drops to `inactiveColor`.
- `symbolRotate`: number or `'inherit'`.
- `formatter`: `'Legend {name}'` template or `(name) => string`.
- `textStyle` with full rich-text support.
- `tooltip`: a per-legend tooltip config (same shape as global `tooltip`).

### 3.4 Selection

- `selectedMode`: `true` (def, multi) | `false` (no toggling) | `'single'` | `'multiple'`.
- `selected`: `{ '<name>': boolean }` initial state map.
- `selector` (v4.4): `true` | `['all','inverse']` | `[{type:'all', title:'All'}, {type:'inverse', title:'Inv'}]`
  → renders **Select-All / Invert-Selection buttons**. Styled by `selectorLabel` (a label option),
  `emphasis.selectorLabel`, `selectorPosition` (`'auto'`|`'start'`|`'end'`), `selectorItemGap` (7),
  `selectorButtonGap` (10).
- Series side: `series.legendHoverLink` (bool, def true) — hovering a legend item highlights the series.
- `triggerEvent` (v6): emits `{componentType, componentIndex, value(name), dataIndex, seriesIndex}`.

### 3.5 Scroll legend (`type:'scroll'`) — the paging machinery

A genuinely separate view class (`ScrollableLegendView`): items are laid out into a content group, clipped
to the available box, and translated by page. Options only meaningful here:

| Option | Default | Meaning |
|---|---|---|
| `scrollDataIndex` | 0 | dataIndex of the top-left visible item (prefer the `legendScroll` action over `setOption`) |
| `pageButtonItemGap` | 5 | Gap between the page buttons and the "1/3" text |
| `pageButtonGap` | null | Gap between the button cluster and the legend items |
| `pageButtonPosition` | `'end'` \| `'start'` | Button cluster before or after the items |
| `pageFormatter` | `'{current}/{total}'` or `({current,total}) => string` | |
| `pageIcons.horizontal` | `['M0,0L12,-10L12,10z','M0,0L-12,-10L-12,10z']` | `[prev, next]` path strings |
| `pageIcons.vertical` | `['M0,0L20,0L10,-20z','M0,0L20,0L10,20z']` | |
| `pageIconColor` / `pageIconInactiveColor` | `#2f4554` / `#aaa` | Inactive = at first/last page |
| `pageIconSize` | 15, or `[w,h]` | |
| `pageTextStyle` | text style | |
| `animation` / `animationDurationUpdate` | true / 800 | The page slide is animated |

The page-boundary computation is non-obvious: it walks the child items, finds which item straddles the
window edge, and snaps the translation so no item is drawn half-cut (`_getPageInfo`, `intersect`,
`getItemInfo` in `ScrollableLegendView.ts`).

---

## 4. `tooltip` (+ `axisPointer`)

### 4.1 Where it can be configured

Five levels, merged by specificity: global `tooltip`; per coordinate system `grid.tooltip` /
`polar.tooltip` / `single.tooltip` (v5.1); per series `series.tooltip`; per datum `series.data[i].tooltip`.
Plus `legend.tooltip` and `toolbox.tooltip` for those components' own hover text.
`series.tooltip` and `series.data.tooltip` only apply when `trigger` is `'item'`.

### 4.2 Trigger and content

| Option | Values | Semantics |
|---|---|---|
| `trigger` | `'item'` \| `'axis'` \| `'none'` (series level also accepts `false`) | item = hovered graphic element; axis = every series' point at the hovered axis value |
| `triggerOn` | `'mousemove'` \| `'click'` \| `'mousemove\|click'` (def) \| `'none'` | `'none'` → only `showTip`/`hideTip` actions or an axisPointer drag handle |
| `showDelay` / `hideDelay` | 0 / 100 ms | `showDelay` only meaningful for `'mousemove'` |
| `alwaysShowContent` | false | Pin it open; disables `hideDelay` |
| `showContent` | true | `false` = fire events / show axisPointer but paint no box |
| `enterable` | false | Allow the pointer into the tooltip (needed for links/buttons inside) |
| `order` | `'seriesAsc'`(def) \| `'seriesDesc'` \| `'valueAsc'` \| `'valueDesc'` | Row order in an axis tooltip |
| `formatter` | template or `(params, ticket, callback) => string \| HTMLElement[]` | Template vars `{a}{b}{c}{d}{e}`, indexed `{a0}`… . The callback's 3rd arg supports **async content** |
| `valueFormatter` | `(value, dataIndex) => string` (v5.3; `dataIndex` fixed to pre-dataZoom index in 6.1) | Formats only the value column; return is HTML-escaped |
| `transitionDuration` | 0.4 s | 0 = tooltip glued to the cursor |
| `displayTransition` | true (v6.0) | Fade vs. hard hide |
| `confine` | false | Clamp the tooltip inside the chart rect |
| `position` | `[x,y]` \| `['50%','50%']` \| `'inside'` \| `'top'` \| `'bottom'` \| `'left'` \| `'right'` \| `(point, params, dom, rect, size) => [x,y] \| {left,top,right,bottom}` | The five keyword values are anchored to the hovered element's bounding box and only work with `trigger:'item'` |
| chrome | `backgroundColor` (`rgba(50,50,50,0.7)`), `borderColor` `#333`, `borderWidth` 0, `padding` 5, `textStyle` (def `#fff`, 14px) | |

### 4.3 `renderMode` — the option that decides the whole port

- `renderMode: 'html'` (default): a real `<div>` overlaid on the chart. Everything DOM-specific hangs off
  this: `appendToBody` (deprecated 5.5), `appendTo` (v5.5, `HTMLElement` or `(container)=>HTMLElement`),
  `className`, `extraCssText`, HTML in `formatter` return values, CSS transitions, native text selection.
- `renderMode: 'richText'`: the tooltip is drawn as **a single zrender `Text` element on the canvas**
  (`TooltipRichContent.ts`), using the rich-text fragment styles built by `TooltipMarkupStyleCreator`.
  Explicitly intended for DOM-free environments (the doc names WeChat mini-programs).
  **This is the path a native port should mirror.** Consequences the source makes visible:
  - `setContent` throws if given DOM nodes.
  - Padding default differs (`[8,10]` rich vs `10` html) — deliberate optical compensation.
  - Shadow is not in the bounding rect, so `getSize()` manually adds `calcShadowOuterSize`.
  - `enterable` still works because the Text element gets `mouseover`/`mouseout` handlers.

Internally the content is **not** a string until the last step: `tooltipMarkup.ts` builds a tree of
`section` and `nameValue` blocks with gap levels, then `buildTooltipMarkup` emits either HTML
(`wrapBlockHTML` / `wrapInlineNameHTML` / `wrapInlineValueHTML`) or rich-text markup
(`wrapInlineNameRichText` / `wrapInlineValueRichText`). A native port should copy this two-stage design:
a structured markup model, then one renderer.

The colored series marker (the little dot before each row) is `makeTooltipMarker(markerType, colorStr,
renderMode)` — `'item'` (round dot) or `'subItem'` (smaller), which in richText mode becomes a generated
rich-text style name with a background color and border-radius.

### 4.4 `axisPointer`

Configured globally (`axisPointer`), per axis (`xAxis.axisPointer`, `angleAxis.axisPointer`, …), or as
sugar under `tooltip.axisPointer` (lower priority than the per-axis form).

| Option | Values |
|---|---|
| `type` | `'line'` \| `'shadow'` \| `'none'`; **`'cross'` only via `tooltip.axisPointer.type`** (it is shorthand for enabling two orthogonal axis pointers) |
| `axis` | `'auto'` \| `'x'` \| `'y'` \| `'radius'` \| `'angle'` |
| `snap` | boolean, auto-determined — snap to the nearest data point (value/time axes) |
| `triggerTooltip` / `triggerEmphasis` (5.4.3) | boolean = true |
| `value`, `status` (`'show'`/`'hide'`) | Programmatic control |
| `label` | `show`, `precision` (`'auto'` or digits), `formatter` (template `{value}` or callback with `params.seriesData`, `axisDimension`, `axisIndex`), `margin` 3, `padding` `[5,7,5,7]`, `backgroundColor` (`'auto'` = axis line color), `borderColor/Width`, text style, `shadow*` |
| `lineStyle` | when `type:'line'` |
| `shadowStyle` | when `type:'shadow'` (default `rgba(150,150,150,0.3)`) |
| `crossStyle` | when `type:'cross'` (default dashed `#555`) |
| `handle` | Touch drag handle: `show`, `icon`, `size` (45 or `[w,h]`), `margin` 50, `color` `#333`, `throttle` 40 ms, `shadow*` |
| `animation` | `animationDurationUpdate` 200, easing `exponentialOut` — the pointer *slides* between snapped values |

**`axisPointer.link`** (global only) is a real capability: an array of link groups, each selecting axes by
`someAxisIndex` / `someAxisName` / `someAxisId` (value, array, or `'all'`, where `some` ∈
`x`/`y`/`radius`/`angle`/`single`). Axes in one group move together. A `mapper(sourceVal, sourceAxisInfo,
targetAxisInfo)` callback converts values between axes of different `type` (e.g. category ↔ time).
This is how a candlestick chart's price and volume grids share a crosshair.
`axisPointer.triggerOn` is also global-only.

---

## 5. `toolbox`

An icon strip. Container options: `show`, `orient` (`'horizontal'`/`'vertical'`), `itemSize` (15),
`itemGap` (10), `showTitle` (hover text under the icon), `backgroundColor`, `borderColor/Width/Radius`,
`padding` (15), box layout, `coordinateSystem` (v6), `tooltip` (use a real tooltip instead of `showTitle`).

Every feature shares: `show`, `title` (string or per-sub-icon map), `icon` (path/image string or map),
`iconStyle` (item style, default `borderColor '#6578ba'`, `color 'none'`, `borderWidth 1`), and
`emphasis.iconStyle` — which additionally carries the hover-label options
`textPosition` (`left/right/top/bottom`), `textFill`, `textAlign`, `textBackgroundColor`,
`textBorderRadius`, `textPadding`, `textFont*`.

### 5.1 The six built-ins (`component/toolbox/feature/`)

| Feature | Options | What it does |
|---|---|---|
| `saveAsImage` | `type` (`'png'`/`'jpg'`, or `'svg'` with the SVG renderer), `name` (file stem), `backgroundColor` (`'auto'`), `connectedBackgroundColor` (`#fff`, for `echarts.connect`ed charts), `excludeComponents` (def `['toolbox']`), `pixelRatio` (1) | Rasterizes the chart and triggers a download via a synthetic `<a download>` (or `msSaveOrOpenBlob` / iframe fallback) |
| `restore` | — | Re-applies the original option, clearing all interactive state |
| `dataView` | `readOnly`, `optionToContent(option)=>HTML`, `contentToOption(container, option)=>option`, `lang` (`['data view','turn off','refresh']`), `backgroundColor`, `textareaColor`, `textareaBorderColor`, `textColor`, `buttonColor`, `buttonTextColor` | Opens a **DOM overlay panel** with an editable `<textarea>` of the tab-separated data; "refresh" parses it back into the option |
| `dataZoom` (a.k.a. **dataZoomSelect**) | `filterMode`, `xAxisIndex` / `yAxisIndex` (number \| array \| `false`), `icon.{zoom,back}`, `title.{zoom,back}`, `brushStyle` | Marquee-to-zoom. Uses `BrushController` to draw a rect/lineX/lineY, converts it to axis ranges, pushes onto an undo stack (`dataZoom/history.ts`) so the `back` icon pops one level |
| `magicType` | `type: ['line'\|'bar'\|'stack']`, `icon.{line,bar,stack}`, `title.{line,bar,stack,tiled}`, `option.{line,bar,stack}`, `seriesIndex.{line,bar}` | Rewrites the series type / stacking in-place and re-renders. Also flips the category axis `boundaryGap` |
| `brush` | `type: ['rect','polygon','lineX','lineY','keep','clear']`, `icon.*`, `title.*` | Enables the `brush` component's modes. Equivalent to `brush.toolbox` |

### 5.2 Custom buttons

Any key beginning with `my` (`myTool1`, `myExport`, …) becomes a button:
`{show, title, icon, onclick: function(){}}`. The `onclick` is a JS callback — in a native port this is
just an `OnClick` event with an identifier.

---

## 6. `dataZoom`

Three types, all sharing the same windowing model; a chart may hold several, and those controlling the
same axis auto-link.

### 6.1 Shared surface (`partial-data-zoom-common`)

| Option | Values / default | Semantics |
|---|---|---|
| `xAxisIndex` / `yAxisIndex` / `radiusAxisIndex` / `angleAxisIndex` | number \| array | Which axes this zoom drives |
| `start` / `end` | 0 / 100 (percent) | Window as a percentage of the data extent |
| `startValue` / `endValue` | number \| string \| Date | Window in absolute values; for category axes, an index **or** the category string. Ignored if `start`/`end` set |
| `rangeMode` | `['percent'\|'value', 'percent'\|'value']` | Auto-derived from which pair you set; auto-flipped by user gestures (`select` → `'value'`, inside/slider → `'percent'`) |
| `minSpan` / `maxSpan` | 0–100 | Window size limits in percent |
| `minValueSpan` / `maxValueSpan` | value | Window size limits in data units (e.g. `5` categories, `5*86400000` ms). Overrides the percent form |
| `orient` | `'horizontal'` \| `'vertical'` | Also picks the default controlled axis |
| `zoomLock` | false | Pan allowed, resize forbidden |
| `throttle` | 100 ms | View refresh rate while dragging |
| `filterMode` | see below | |

### 6.2 `filterMode` — four precisely different semantics

| Value | Behaviour |
|---|---|
| `'filter'` (default) | Data outside the window is **removed from the dataset**. A data item is dropped if **any** relevant dimension is outside. Because items vanish, the *other* axis re-computes its extent to fit what is left |
| `'weakFilter'` | Same removal, but an item is dropped only if **all** relevant dimensions are outside the window **on the same side**. Designed for interval-shaped data (e.g. Gantt bars) that straddle the window edge |
| `'empty'` | Out-of-window values are **replaced with NaN**, not removed. The element disappears but its slot and the other axis' extent are untouched |
| `'none'` | No filtering; only the axis extent changes |

The documented recipe: single-axis zoom → `'filter'`; both axes on a scatter → both `'empty'`;
main/auxiliary pair (bar chart) → main axis `'filter'`, auxiliary `'empty'`.
Ordering matters: with `'filter'`, dataZoom components are applied in declaration order, so a later
component's percentages are relative to the already-filtered data.

### 6.3 `type: 'inside'` — gestures, no chrome

`disabled` (bool) plus four gesture switches, each `true` | `false` | `'shift'` | `'ctrl'` | `'alt'`
(the string values mean "only with that modifier held"):
- `zoomOnMouseWheel` (def `true`)
- `moveOnMouseMove` (def `true`) — drag inside the coordinate system pans the window
- `moveOnMouseWheel` (def `false`) — wheel scrolls instead of zooming
- `preventDefaultMouseMove` (def `true`) — suppresses browser text selection during drag
- v6.1 adds `cursorGrab` (def `'grab'`) and `cursorGrabbing` (def `'grabbing'`) — **CSS cursor names**,
  browser-bound as literal strings but semantically "map to a native grab cursor".
Touch: two-finger pinch (`RoamController._pinchHandler`, scale steps of 1.1).

### 6.4 `type: 'slider'` — full widget anatomy

From `SliderZoomView.ts` (constants `DEFAULT_FILLER_SIZE = 30`, `DEFAULT_MOVE_HANDLE_SIZE = 7`,
`DEFAULT_FRAME_BORDER_WIDTH = 1`, `LABEL_GAP = 5`) and the doc:

| Part | Options |
|---|---|
| Frame / track | `backgroundColor` (`rgba(47,69,84,0)`), `borderColor` `#d2dbee`, `borderRadius` 3, `width`/`height` (def 30 on the short axis; overrides `left/right` resp. `top/bottom`) |
| **Data shadow** (silhouette of the series inside the track) | `dataBackground.lineStyle` (w 0.5, `#d2dbee`), `dataBackground.areaStyle` (opacity 0.2), `showDataShadow` (`'auto'`) — drawn only for series of type **line, bar, candlestick, scatter** (`SHOW_DATA_SHADOW_SERIES_TYPE`) |
| **Selected data shadow** (v5) | `selectedDataBackground.lineStyle` / `.areaStyle` (`#8fb0f7`) — the same silhouette re-drawn inside the window |
| Window fill | `fillerColor` `rgba(47,69,84,0.25)` |
| Two end handles | `handleIcon` (default is a bespoke "grip" path), `handleSize` (`'100%'` of the bar thickness, or px), `handleStyle` (fill `#fff`, border `#ACB8D1`), `handleLabel.show` (v5.6) |
| Move handle (v5) | `moveHandleIcon` (3-bar grip path), `moveHandleSize` 7, `moveHandleStyle` (`#D2DBEE`, opacity 0.7) — the bar you grab to pan without resizing |
| Drag readout | `showDetail` (true), `labelPrecision` (`'auto'`), `labelFormatter` (`'aaa{value}bbb'` or `(value, valueStr) => string`; for category axes `value` is the index), `textStyle` |
| Brush-select (v5) | `brushSelect` (true) — drag on empty track to define a new window; `brushStyle` (`rgba(135,175,274,0.15)`) |
| Live update | `realtime` (true) — update while dragging vs. only on release |
| Hover states | `emphasis.handleStyle`, `emphasis.handleLabel`, `emphasis.moveHandleStyle` |

### 6.5 `type: 'select'` (dataZoomSelect)

Not declarable directly — it is created by `toolbox.feature.dataZoom`. It is a marquee (`BrushController`
with `brushType:'auto'` resolving to rect/lineX/lineY depending on which axes are targeted) plus an undo
stack. `takeGlobalCursor` with key `'dataZoomSelect'` arbitrates the exclusive drag cursor against `brush`.

---

## 7. `visualMap`

Two roles in one component: (a) a **visual encoder** mapping a data dimension to visual channels, and
(b) an interactive **widget** for choosing which values are "in range". Multiple instances allowed.

### 7.1 The eight visual channels (`partial-visual-map-visual-type`)

| Channel | Range | Note |
|---|---|---|
| `color` | array of colors → interpolated ribbon | `min` → first stop, `max` → last stop, piecewise-linear between |
| `symbol` | array of symbol names | Nearest-stop lookup, not interpolated |
| `symbolSize` | `[minPx, maxPx]` | Linear |
| `opacity` | `[0,1]` | Affects the element **and its label** |
| `colorAlpha` | `[0,1]` | Affects only the element fill |
| `colorLightness` | `[0,1]` | HSL |
| `colorSaturation` | `[0,1]` | HSL |
| `colorHue` | `[0,360]` | HSL |

Ranges may be inverted (`opacity: [1, 0.4]`). A scalar is normalized to `[v, v]`.
Two mapping modes: **Linear** (continuous, or piecewise without `categories`) and
**Table** (piecewise with `categories`, where a channel value can be an object keyed by category, an
array parallel to `categories`, or a single value; `''` key = catch-all).

### 7.2 Targeting

`dimension` (which column of `series.data`; default = last), `seriesIndex` (number | array | `'all'`),
`seriesId` (v6.0), and **`seriesTargets` (v6.1)** — an array of `{seriesIndex|seriesId, dimension}` letting
one visualMap drive *different dimensions of different series*; it overrides the three above.
A datum can opt out with `{value: …, visualMap: false}`.

### 7.3 Where the channels apply: `inRange` / `outOfRange` / `target` / `controller`

- `inRange` / `outOfRange` at the top level apply to **both** the chart and the widget.
- `target.inRange` / `target.outOfRange` → chart only.
- `controller.inRange` / `controller.outOfRange` → widget only (and override the shared ones per-property).
- Default `inRange.color` is `['#f6efa6','#d88273','#bf444c']`; set `inRange:{color:null}` to kill it.
- **These four keys do not merge across `setOption` calls** — they are wholesale replaced. Explicitly
  documented as a deliberate simplification.

### 7.4 `type: 'continuous'`

`min` / `max` (default `[0,200]`, **not** derived from data), `range: [lo, hi]` (the two handle values;
auto-adapts to `[min,max]` when unset or nulled), `calculable` (show draggable handles),
`realtime`, `inverse`, `precision`, `itemWidth` 20 / `itemHeight` 140, `align`
(`'auto'|'left'|'right'|'top'|'bottom'` — which side handles+labels sit on),
`text: ['High','Low']` (end captions), `textGap` 10, `formatter` (template `{value}` or callback),
`handleIcon` / `handleSize` (`'120%'`) / `handleStyle`, `indicatorIcon` (`'circle'`) / `indicatorSize`
(`'50%'`) / `indicatorStyle`, `hoverLink` (true).

**`unboundedRange` (v6.0, default `true`)**: when `range[0] <= min` the effective lower bound becomes
`-Infinity`, and symmetrically for the upper. Set `false` to make outliers permanently out-of-range.

**`hoverLink` is bidirectional and is a real feature, not a knob**: hovering the bar highlights the
matching chart elements (`_doHoverLinkToSeries`, with a `halfHoverLinkSize` tolerance producing
`'< '`, `'> '`, `'≈ '` prefixed indicator labels), and hovering a chart element pops the indicator dot
onto the bar at that value (`_hoverLinkFromSeriesMouseOver`).

The bar itself is not a plain rectangle: `_createBarPoints` builds a **polygon whose width tracks the
`symbolSize` channel**, so the widget visually previews size mapping as well as color
(`_makeColorGradient` handles the special case where `colorHue` mapping makes the ramp non-linear).

### 7.5 `type: 'piecewise'`

Three modes:
1. **CONTINUOUS-AVERAGE** — `splitNumber` (def 5) even slices of `[min,max]`.
2. **CONTINUOUS-CUSTOMIZED** — `pieces: [{min,max,label,color,...channels}]`; omitted `min`/`max` mean
   ±Infinity; `{value: 123}` matches an exact value.
3. **CATEGORY** — `categories: ['a','b',...]` with table mapping.

Plus: `minOpen` / `maxOpen` (add an extra `"< min"` / `"> max"` piece), `selectedMode`
(`'multiple'` def | `'single'` | `true` | `false` since 5.3.3), `inverse`, `precision`,
`itemWidth` 20 / `itemHeight` 14 / `itemGap` 10, `align` (`'auto'|'left'|'right'`),
`text` end captions (suppresses per-item labels for ECharts-2 compat), `textGap`, `showLabel`,
`itemSymbol` (def `'roundRect'`, any built-in symbol) — the swatch shape when the `symbol` channel is
not itself mapped, `formatter` (`'{value} to {value2}'` or `(v, v2) => string`).

Shared container options: `show`, `orient` (`'vertical'` def), `padding` 5, `backgroundColor`,
`borderColor` / `borderWidth`, `textStyle`, `color` (legacy ECharts-2 alias, reversed order), box layout
(`left:0, bottom:0` by default), `coordinateSystem` (v6), `z` 4.

---

## 8. `brush`

Marquee selection that drives **cross-filtering**: selected items keep their normal visuals, unselected
ones are dimmed. Supported by `scatter`, `bar`, `candlestick` (and `parallel` has its own built-in brush).

| Option | Values | Semantics |
|---|---|---|
| `toolbox` | subset of `['rect','polygon','lineX','lineY','keep','clear']` (def `['rect','polygon','keep','clear']`) | Which buttons appear |
| `brushType` | `'rect'` \| `'polygon'` \| `'lineX'` \| `'lineY'` | Default shape |
| `brushMode` | `'single'` (def) \| `'multiple'` | Single = one box, cleared by clicking blank space; multiple = accumulate, cleared only by the `clear` button. The `keep` toolbar button toggles this |
| `transformable` | true | Selected boxes can be dragged and resized |
| `removeOnClick` | true | In `'single'` mode, a click on empty space clears |
| `brushStyle` | `{borderWidth:1, color:'rgba(120,140,180,0.3)', borderColor:'rgba(120,140,180,0.8)'}` | |
| `seriesIndex` | `'all'` (def) \| number \| array | Which series are brushable |
| `geoIndex` / `xAxisIndex` / `yAxisIndex` | `'all'` \| number \| array \| `'none'` | **Scoping**: global brush (default) vs. coordinate-bound brush. A coordinate-bound box tracks the coordinate system when it is panned or zoomed |
| `brushLink` | `'all'` \| array of seriesIndex \| `'none'` | Links selection **by dataIndex** across series — selecting point 3 in a scatter also selects row 3 in a parallel plot. Requires the series' data arrays to be index-aligned |
| `inBrush` / `outOfBrush` | any of the 8 visualMap channels | Visual encoding of selected / unselected. `outOfBrush` defaults to `color:'#ddd'` |
| `throttleType` | `'fixRate'` (def) \| `'debounce'` | How often `brushSelected` fires |
| `throttleDelay` | 0 (= no throttle) ms | |
| `z` | 10000 | Cover box paints above everything |

Interaction internals worth copying (`component/helper/BrushController.ts`):
- Cover shapes: `rect` gets **8 resize handles** (`w,e,n,s,se,sw,ne,nw`) with matching resize cursors
  (`ew`, `ns`, `nesw`, `nwse`); `lineX`/`lineY` get 2 (`w,e` resp. `n,s`); `polygon` is drawn as a
  `Polyline` while dragging (open border reads better) and converted to a closed `Polygon` on release.
- `UNSELECT_THRESHOLD = 6` px — a drag shorter than this counts as a click, not a selection.
- `MIN_RESIZE_LINE_WIDTH = 6` — minimum hit width of an edge handle.
- `MUTEX_RESOURCE_KEY = 'globalPan'` — a global cursor mutex so brush, dataZoom-select and roam do not
  fight over the drag.
- Covers are clipped to their panel (`clipByPanel`).
- Hit testing per element kind: `selector.point(itemLayout)` and `selector.rect(itemLayout)` for each of
  `lineX` / `lineY` / `rect` / `polygon` — i.e. **point-in-polygon and rect-vs-polygon intersection**.

Events: `brushSelected` (throttled, carries the selected dataIndices per series), `brush`, `brushEnd`.
Programmatic control via `dispatchAction({type:'brush', areas:[{geoIndex, brushType, coordRange}]})`.

---

## 9. `timeline`

Purpose: step or play through **an array of whole chart options**.

Option structure: the root of the option is `baseOption` (an `ECUnitOption`); `options: [...]` holds one
`switchableOption` per tick, index-aligned with `timeline.data`. On each tick the switchable option is
merged into the base to produce the final option. Two merge strategies: `NORMAL_MERGE` (default) and
`REPLACE_MERGE` when `replaceMerge` names a component mainType (`'series'`, `['xAxis','series']`) — used
when the tick should *replace* rather than deep-merge (e.g. a different number of series per tick).
The v4 nesting `{baseOption: {...}, options: [...]}` is still accepted.

| Option | Values | Semantics |
|---|---|---|
| `type` | `'slider'` (only value) | |
| `axisType` | `'time'` (def) \| `'value'` \| `'category'` | Governs tick placement and label formatting |
| `data` | array of values, or `{value, symbol, symbolSize, tooltip}` objects | The ticks |
| `currentIndex` | 0 | Which tick is active |
| `autoPlay` / `loop` / `rewind` / `playInterval` | false / true / false / 2000 ms | Playback control; `rewind` plays backwards |
| `realtime` | true | Update while dragging the checkpoint |
| `orient` / `inverse` | `'horizontal'` def / false | |
| `controlPosition` | `'left'` \| `'right'` | Where the button cluster sits |
| `symbol` / `symbolSize` | `'emptyCircle'` / 10 | Tick markers |
| `lineStyle` | `show`, width 2, color `#DAE1F5` | The axis line |
| `label` | `show`, `position` (`'auto'|'left'|'right'|'top'|'bottom'|number`), `interval` (`'auto'` or every-N), `rotate`, `formatter`, text style | Tick labels |
| `itemStyle` / `emphasis.itemStyle` | | Tick marker style |
| `checkpointStyle` | `symbol` `'circle'`, `symbolSize` 13, item style (`#316bf3` on white, shadowed), **`animation`** (true), `animationDuration` (300), `animationEasing` (`'quinticInOut'`) | The current-position marker *slides* between ticks |
| `progress` | `lineStyle`, `itemStyle`, `label` (all `#316BF3`) | The already-played portion is styled separately |
| `controlStyle` | `show`, `showPlayBtn`, `showPrevBtn`, `showNextBtn`, `itemSize` 22, `itemGap` 12, `position` (`'left'|'right'|'top'|'bottom'`), `playIcon`, `stopIcon`, `prevIcon`, `nextIcon`, item style | Play/pause + prev/next |
| `emphasis.{label,itemStyle,checkpointStyle,controlStyle}` | | Hover states |

`SliderTimelineView` overrides `scale.getTicks` so the axis has exactly one tick per data item, then
positions/rotates the whole group via `_position` (`setOrigin`, `toBound`) — the vertical orientation is
implemented as a transform of the horizontal layout, not a second layout path.

---

## 10. `markPoint` / `markLine` / `markArea`

These live on a **series** (`series.markPoint`, etc.), not at the option root, but they are UI overlays.
All three share the data-item resolution machinery in `component/marker/markerHelper.ts`.

### 10.1 Position resolution (priority order)

1. **Pixel/percent**: `x`, `y` (number = px, string = `'90%'`). v6.0 adds
   `relativeTo: 'container'` (def) | `'coordinate'` — whether x/y are relative to the whole chart or to
   the grid rect.
2. **Data coordinate**: `coord: [xVal, yVal]` (or `[radius, angle]` on polar). **Each dimension of `coord`
   may itself be a statistic string** `'min'` / `'max'` / `'average'` / `'median'`
   (e.g. `coord: ['average','max']`).
3. **Statistic type**: `type: 'min' | 'max' | 'average' | 'median'` with `valueIndex` (0 = x/radius,
   1 = y/angle) or `valueDim` (a named dimension: `'x'`, `'angle'`, `'open'`, `'close'`, …).
   *(The `markPoint` doc lists only min/max/average, but `markerTypeCalculator` in the source registers
   all four including `median` — it works for all three markers.)*
4. **Axis-parallel** (markLine / markArea, cartesian only): a bare `xAxis: 100` or `yAxis: '2020-01-01'`
   draws a line/band spanning the coordinate system at that axis value.

Category-axis gotcha, documented explicitly: a numeric `coord` value is the **index** into `axis.data`,
a string value is the **category label** — so `xAxis.data` must be strings if you want to address by label.

### 10.2 `markPoint`

Single points. `symbol` (def `'pin'`), `symbolSize` (def 50, may be a callback), `symbolRotate`,
`symbolOffset`, `symbolKeepAspect`, `silent`, `label` (def shown, `position:'inside'`, `formatter`),
`itemStyle`, `emphasis.{label,itemStyle}`, `blur.{label,itemStyle}`, `z` (def 5, v6), animation options.
Per-datum: `name` (the `{b}` template var), `value` (the `{c}` var), `z2` (v6), plus per-item
`symbol*` / `itemStyle` / `label` / `emphasis` / `blur`.

### 10.3 `markLine`

Each `data` entry is **either a single object** (an axis-parallel or statistic line) **or a two-element
array** `[startPointDef, endPointDef]` (an arbitrary segment). Both endpoints use the resolution rules
above and can mix forms — the documented example draws an arrow from a fixed pixel x to the data maximum.

Options: `symbol` (`[startSymbol, endSymbol]`, default arrow at the end), `symbolSize`
(single value per end — width/height cannot be split), `symbolOffset` (per end, and a 2-d array per end
for x/y), `precision` (2, for the computed statistic label), `lineStyle`, `label`, `emphasis.*`, `blur.*`,
`z`, animation.
`markLine.label.position`: `'start'` | `'middle'` | `'end'` plus (v4.7)
`'insideStartTop'`, `'insideStartBottom'`, `'insideMiddleTop'`, `'insideMiddleBottom'`,
`'insideEndTop'`, `'insideEndBottom'` — 9 positions. `label.distance` (number or `[h, v]`).

### 10.4 `markArea`

Each `data` entry is a two-element array giving opposite corners of a rectangle; either corner may be a
pixel position, a `coord` (with statistic strings), a `type` statistic, or a bare `xAxis`/`yAxis` value —
so `[{yAxis: 60}, {yAxis: 80}]` is a full-width horizontal band, and `[{coord:['min','min']},
{coord:['max','max']}]` covers the data. `silent`, `itemStyle`, `label` (def `position:'top'`),
`emphasis.*`, `blur.*`.

---

## 11. `graphic`

A free-form vector overlay. Declarable as a single object, a bare array, or `{elements: [...]}`.

### 11.1 Element types (13 actually constructible)

From `GraphicView.ts` `nonShapeGraphicElements` + `src/util/graphic.ts` `registerShape`:

`group`, `image`, `text`, `circle`, **`ellipse`**, `sector`, `ring`, `polygon`, `polyline`, `rect`,
`line`, `bezierCurve`, `arc`.

**Accuracy note:** the doc's type list also names `path` and `compoundPath`, but the source comments them
as *"Reserved but not supported in graphic component"* — they exist only for `custom` series render items.
Conversely `ellipse` is registered but not in the doc list.

Shapes:
- `rect`: `{x, y, width, height, r}` where `r` is a number or a 1–4 element corner-radius array.
- `circle`: `{cx, cy, r}`; `ring`: `{cx, cy, r, r0}`;
  `sector`: `{cx, cy, r, r0, startAngle, endAngle, clockwise, cornerRadius}`;
  `arc`: `{cx, cy, r, r0, startAngle, endAngle, clockwise}`.
- `polygon`/`polyline`: `{points: [[x,y],…], smooth, smoothConstraint}`.
- `line`: `{x1,y1,x2,y2, percent}` — `percent` draws a partial line (used for grow-in animation).
- `bezierCurve`: `{x1,y1,x2,y2, cpx1,cpy1, cpx2,cpy2, percent}` — quadratic if cp2 omitted, cubic if given.
- `image`: `style.{image, x, y, width, height}`.
- `text`: `style.{text, x, y, font, textAlign, textVerticalAlign, width, overflow, ellipsis, rich}`.
- `group`: `{width, height, children, diffChildrenByName}`.

### 11.2 Common element props

- **Positioning**: `left`/`right`/`top`/`bottom` (px, `'%'`, `'center'`/`'middle'`) — these override
  `shape.x/y/cx/cy`. `bounding: 'all'` (default; the transformed bbox including children is confined) vs
  `'raw'` (only the untransformed self bbox is used, allowing overflow).
- **Transform**: `x`/`y` (or legacy `position: [x,y]`), `scaleX`/`scaleY`, `rotation` (radians, negative =
  clockwise), `originX`/`originY`. Applied as: translate(−origin) → scale → rotate → translate(+origin) →
  translate(position). Transforms nest through groups.
- **Style**: `fill`, `stroke`, `lineWidth`, `lineDash` (number | array | `'solid'`/`'dashed'`/`'dotted'`),
  `lineDashOffset`, `lineCap` (`butt`/`round`/`square`), `lineJoin` (`bevel`/`round`/`miter`),
  `miterLimit`, `shadowBlur/OffsetX/OffsetY/Color`, `opacity`.
- **Merge semantics** — `$action`: `'merge'` (default; deep-merges into the element with the same `id`),
  `'replace'` (destroy and recreate), `'remove'` (delete). With no `id`, elements are matched **by
  position in the array**, which the doc warns against.
- **Attachments**: `clipPath` (another element definition used as a clip), `textContent` +
  `textConfig` (`position`, `rotation`, `layoutRect`, `offset`, `origin`, `distance` 5, `local`,
  `insideFill`/`insideStroke`/`outsideFill`/`outsideStroke`, `inside`) — a label bound to the element.
- **Flags**: `silent` (ignore pointer), `invisible`, `ignore`, `draggable` (`true` | `'horizontal'` |
  `'vertical'`), `progressive`, `z`, `zlevel`, `z2`, `name`, `info` (arbitrary user payload surfaced in
  events).
- **Animation**: `transition` (`'all'`, a prop name, or an array; also the shortcuts `'shape'`, `'style'`,
  `'extra'`; transform props `x,y,scaleX,scaleY,rotation,originX,originY`), `enterFrom`, `leaveTo`,
  `enterAnimation` / `updateAnimation` / `leaveAnimation` (each `{duration, easing, delay}`), and
  `keyframeAnimation` — an array of `{duration, delay, easing, loop, keyframes:[{percent, easing, ...props}]}`,
  supporting several simultaneous named animations per element. Keyframes win over transitions on the
  same property.
- **Event handlers**: `onclick`, `onmouseover`, `onmouseout`, `onmousemove`, `onmousewheel`,
  `onmousedown`, `onmouseup`, `ondrag`, `ondragstart`, `ondragend`, `ondragenter`, `ondragleave`,
  `ondragover`, `ondrop` (14).

---

## 12. `aria` and `decal`

### 12.1 `aria.label` — auto-generated description

`aria.enabled` (def false) gates everything. When on, `aria.label.enabled` (def true) generates a prose
description and writes it to the container as `role="img"` + `aria-label` (`src/visual/aria.ts`).
`aria.label.description` overrides the whole thing with a literal string.

Otherwise the description is assembled from a template set — all of them user-overridable and
locale-provided:
- `general.withTitle` (`'This is a chart about "{title}".'`) / `general.withoutTitle`.
- `series.maxCount` (10), `series.single.{prefix, withName, withoutName}`,
  `series.multiple.{prefix, withName, withoutName}`, `series.multiple.separator.{middle, end}`.
  Template vars: `{seriesCount}`, `{seriesName}`, `{seriesType}`, `{seriesId}`.
- `data.maxCount` (10), `data.allData`, `data.partialData` (`{displayCnt}`), `data.withName`
  (`{name}`, `{value}`), `data.withoutName`, `data.separator.{middle,end}`,
  `data.excludeDimensionId` (v5.6).

The `aria-label` write is DOM-only, but **the text generation itself is pure string assembly** and maps
directly to an `Accessible.Name`/`TCustomControl` accessibility description or a "describe this chart"
text export.

### 12.2 `decal` — pattern fills (the genuinely portable half)

`aria.decal.show: true` (requires `aria.enabled`) turns on pattern fills as a colour-independent
differentiator. `aria.decal.decals` is one style object or an array cycled over the data.
Decals can also be set per-series/per-item as `itemStyle.decal`, and `legend.itemStyle.decal` inherits.
Supported on line/bar/pie/radar/treemap/sunburst/boxplot/sankey/funnel/gauge/pictorialBar/themeRiver/custom
(the ones with no default fill — line, radar, boxplot — only when `areaStyle` is set).

| Option | Default | Semantics |
|---|---|---|
| `symbol` | `'rect'` | Any built-in symbol name, or `path://`/`image://`. **An array cycles symbols; a nested array cycles per row** |
| `symbolSize` | 1 | 0–1, symbol size relative to its cell |
| `symbolKeepAspect` | true | |
| `color` | `rgba(0,0,0,0.2)` | Pattern ink — translucent so the series colour shows through |
| `backgroundColor` | null | Painted over the series colour, under the pattern |
| `dashArrayX` | 5 | Horizontal `mark-gap-mark-gap…` cycle. `number` → equal mark and gap; `number[]` → the cycle `[mark, gap, mark, gap…]`; `(number\|number[])[]` → **a different cycle per row**, e.g. `[10,[2,5]]` |
| `dashArrayY` | 5 | Vertical cycle: `number` or `number[]` |
| `rotation` | 0 | Whole-pattern rotation in radians |
| `maxTileWidth` / `maxTileHeight` | 512 / 512 | Cap on the generated tile before it repeats; raise if seams appear |

Implementation (`src/util/decal.ts`): normalize the dash arrays, compute a tile size that makes the X and
Y cycles commensurate (LCM-ish via `getLineBlockLengthX`/`Y`), render one tile into an offscreen canvas,
then use it as a repeating pattern with a rotation applied to the pattern transform. **This is a real
algorithm, not a knob** — and it is the single most reusable piece of the `aria` component for a native
control.

---

## 13. `thumbnail` (new in v6.0.0) — verified against source

`ThumbnailModel.ts` / `ThumbnailView.ts` / `ThumbnailBridgeImpl.ts`.

Purpose: a **mini-map with a viewport window** for a roamable component. In 6.1 it **only supports
`series.graph`** — `ThumbnailModel.getTarget()` errors in dev builds for any other subType and otherwise
picks the first `graph` series. `static dependencies = ['series','geo']` and the code comments say geo is
the intended next target, so treat this as an early feature.

| Option | Default | Notes |
|---|---|---|
| `show` | true | |
| `left`/`top`/`right`/`bottom`/`width`/`height` | `right:1, bottom:1, width:'25%', height:'25%'` (source; doc says `left/top:'25%'`) | Box layout |
| `itemStyle` | fill = `option.backgroundColor` or neutral00; `borderColor` `#b7b9be`, `borderWidth` 2, `borderRadius` | The frame + background |
| `windowStyle` | fill neutral30, border neutral40, `borderWidth` 1, `opacity` 0.3 | The viewport rectangle |
| `seriesIndex` / `seriesId` | first graph series | Which series to mirror |
| `coordinateSystem` | v6: `'none'`/`'matrix'`/`'calendar'` | |
| `z` | 10 | |

Mechanism worth copying:
1. The target series pushes its rendered element group through a **bridge** (`injectThumbnailBridge`),
   including its bounding rect, z2 range, roam type and current transform.
2. The view re-parents that same element group into a clipped group and applies a `View` coordinate
   transform that fits the content bbox into the thumbnail box, aspect-preserved
   (`getLayoutRect({left:'center', top:'center', aspect})`).
3. The viewport window rect is the main chart's viewport transformed by
   `mul(thumbnailMatrix, invert(targetMatrix))`.
4. Its own `RoamController` converts thumbnail-space pan/zoom back into `graphRoam`/`geoRoam` actions
   using the inverse transform, so dragging the mini-map roams the main view.
Note: roam *animation* is explicitly not supported in the thumbnail.

---

## 14. The action / event surface these components rely on

For a native port these become methods and events rather than `dispatchAction` payloads, but the list
defines the required API:

`legendSelect` / `legendUnSelect` / `legendToggleSelect` / `legendAllSelect` / `legendInverseSelect` /
`legendScroll`; `showTip` / `hideTip`; `dataZoom` (with start/end or startValue/endValue);
`takeGlobalCursor` (drag-mode mutex, key `'dataZoomSelect'` or `'brush'`); `brush` (set areas
programmatically); `selectDataRange` (visualMap range); `timelineChange` / `timelinePlayChange`;
`restore`; `graphRoam` / `geoRoam` (thumbnail).
Emitted events include `legendselectchanged`, `datazoom`, `brushSelected` (the cross-filter payload),
`timelinechanged`, `timelineplaychanged`, `dataviewchanged`, `magictypechanged`, `globalcursortaken`.

---

## Porting notes

Classification for an immediate-mode, antialiased 2D canvas on a desktop window (BGRABitmap / LCL),
no DOM, no CSS, no WebGL, no JS callbacks.

### NATURAL — maps cleanly

| Capability | Note |
|---|---|
| Box layout (`left/top/right/bottom/width/height`, px + `%` + keywords) | One `TRect` solver reused by every component |
| `z` / `zlevel` / `z2` ordering | Collapse to one integer sort key before painting |
| Component chrome (bg, border, border-radius, shadow, padding) | `RoundRectAntialias` + shadow blit |
| `title`: text + subtext, `textAlign`/`textVerticalAlign`, `itemGap`, multiple instances | Two text blocks in a box |
| `legend` plain: item flow layout, `orient`, `align`, `itemGap/Width/Height`, `formatter`, `selectedMode`, `selected`, `inactiveColor`, per-item overrides, `data` line-break tokens | Ordinary flow layout + hit testing |
| `legend.selector` (all / inverse buttons) | Two more clickable cells |
| Built-in symbol set (circle, rect, roundRect, square, triangle, diamond, pin, arrow, line, none + `empty*`) | ~10 hand-drawn paths |
| `visualMap` piecewise widget: swatch rows, labels, `itemSymbol`, selection modes | Rows of coloured rects + hit test |
| `visualMap` linear/table channel mapping (color ramp, opacity, colorAlpha, HSL H/S/L, symbolSize, symbol) | Arithmetic + an HSL↔RGB helper you already have |
| `dataZoom` window model: `start/end`, `startValue/endValue`, `minSpan/maxSpan`, `minValueSpan/maxValueSpan`, `zoomLock`, `orient`, `throttle`, `realtime` | Pure numeric interval logic |
| `dataZoom` slider chrome: track, filler, two handles, move handle, labels, `labelFormatter`, `brushSelect`, emphasis states | A custom scrollbar-like widget; ty-controls already has the scrollbar geometry lessons |
| `dataZoom` inside gestures (wheel zoom, drag pan, modifier gating, wheel-move) | Mouse handlers; the modifier strings `shift/ctrl/alt` map to `Shift` in `TShiftState` |
| `timeline`: axis line, tick symbols, labels, checkpoint, play/prev/next buttons, `playInterval` via a timer, `loop`, `rewind`, `progress` styling | A slider + `TTimer`; the option-swap is a callback into the host |
| `markPoint` / `markLine` / `markArea` rendering: symbols, lines with end symbols, bands, labels at 9 positions | Straight drawing once positions are resolved |
| `graphic`: rect(+corner radii), circle, ellipse, ring, sector, arc, polygon, polyline, line, bezierCurve, image, text, group; fill/stroke/dash/cap/join/shadow; nested transforms; `$action` merge/replace/remove | BGRABitmap paths cover all of it; `$action` is a dictionary diff |
| `axisPointer` line / shadow / cross rendering + value label pill | Trivial drawing; the snap logic is a binary search |
| `toolbox` icon strip, hover titles, custom `myXxx` buttons | An icon toolbar with an `OnClick(name)` event |
| `saveAsImage` | Native file save of the already-rendered bitmap — *easier* than the browser path |
| `aria.label` text generation | Pure string templating; feed it to the accessibility name or a "copy description" action |
| `tooltip` with `renderMode:'richText'` — box, border, shadow, padding, position keywords, delays, `confine`, `alwaysShowContent`, `enterable` | **Use this as the model.** It is already DOM-free by design |

### HEAVY — doable, but a real algorithm

| Capability | Algorithm to implement |
|---|---|
| Rich text (`rich` + `{style\|text}` markup) | Tokenize the markup, measure per-fragment, line-break and align a **grid of styled runs** with per-fragment padding/background/border/image. This is a mini text-layout engine; note the ty-controls CJK word-wrap trap (space-only breaking destroys Chinese layout) |
| `tooltip` content model | Port the two-stage `tooltipMarkup` design: build `section`/`nameValue` blocks with gap levels, then render. Do **not** build strings directly |
| `tooltip` positioning with `confine` + the `position` keywords | Anchor-box resolution against the hovered element's bbox with viewport clamping and flip-on-overflow |
| Scroll legend paging | Item measurement, window intersection, snap-to-item-boundary page computation (`_getPageInfo`), plus an animated slide |
| `legend` icon inheritance (`'inherit'` per property, series-supplied `getLegendIcon`) | Requires a visual-state channel from the series layer to the legend; the sentinel-value merge is fiddly |
| `dataZoom` `filterMode` semantics (filter / weakFilter / empty / none) | Four distinct dataset transforms with cross-axis extent recomputation and order-dependence between components. Easy to get subtly wrong; write tests per mode |
| `dataZoom` slider data shadow | Downsample the target series into a silhouette polyline+area, drawn twice (full + selected) with clipping |
| `visualMap` continuous bar | The bar is a **polygon whose thickness follows the `symbolSize` channel**, filled with a multi-stop gradient that goes non-linear under `colorHue` mapping. Plus handle drag with `minSpan`-style clamping |
| `visualMap` `hoverLink` (bidirectional) | Hover→highlight requires a value→dataIndex reverse index with a tolerance band; element-hover→indicator requires the forward map |
| `brush` cover interaction | Rect with 8 resize handles + cursor mapping, polygon draw/close, drag-vs-click threshold, panel clipping, and a **global drag-mode mutex** shared with dataZoom-select and roam |
| `brush` hit testing | Point-in-polygon and rect/polygon intersection per data element, per frame, throttled (`fixRate` / `debounce`) |
| `brushLink` cross-filtering | Index-aligned selection propagation across series + re-running the `inBrush`/`outOfBrush` visual encoding |
| `axisPointer.link` with `mapper` | Multi-coordinate-system synchronization with a type-converting mapper hook |
| `decal` pattern fills | Generate a tile (commensurate X/Y dash cycles, symbol stamping at `symbolSize`), then tile it with a rotation. BGRABitmap has texture brushes, but the rotated-tile seam handling (`maxTileWidth/Height`) is on you |
| `graphic` keyframe + transition animations (`transition`, `enterFrom`, `leaveTo`, `keyframeAnimation` with `loop`, per-keyframe easing, multiple concurrent tracks) | A small property-animation engine with ~30 easing curves. Only worth it if the control wants animated overlays |
| `graphic` relative positioning with `bounding:'all'` | Position depends on the *transformed* bbox of the element and its descendants — a fixed-point-ish measure-then-place pass |
| `thumbnail` | Re-render (or re-transform) the target's element tree into a fitted, clipped box, then map pan/zoom back through the inverse matrix. Needs a "render this component into an arbitrary rect" capability the painter may not have; ty-controls has learned that `RenderTo` is the reliable path for windowed controls |
| `magicType` chart-type switching | Requires a re-specification path (rewrite series type + stacking + axis `boundaryGap`, then full re-layout) — architectural, not visual |
| `timeline` option merge (`NORMAL_MERGE` vs `REPLACE_MERGE`) | A structured deep-merge with id-keyed component matching. If the native control has no "option tree", this becomes a different design entirely |

### BROWSER-BOUND — needs a native re-think or is out of scope

| Capability | Why, and what the native answer is |
|---|---|
| `tooltip.renderMode:'html'` and everything hanging off it: `appendToBody`, `appendTo`, `className`, `extraCssText`, HTML strings from `formatter`, `formatter` returning `HTMLElement[]`, CSS `transitionDuration`, `displayTransition`, native text selection inside the tooltip | The whole DOM overlay path. Native answer: a borderless popup window (or canvas-drawn box) with the `richText` content model. Note ty-controls' GTK3/Wayland popup and Qt6 mask lessons if a real window is used |
| `tooltip.enterable` in HTML mode with links/buttons inside | Requires interactive child widgets in the tooltip. Native answer: a real popup form, or drop the feature |
| `tooltip.formatter` async `callback(ticket, html)` | JS closure + async. Native answer: an `OnTooltipContent` event with a "content ready" call-back |
| `toolbox.dataView` panel (editable `<textarea>`, `optionToContent`/`contentToOption` returning HTML) | A DOM overlay with an HTML editor. Native answer: a modal dialog with a grid or memo; ty-controls has both, plus the modal-drag lessons |
| `saveAsImage` download mechanics (`<a download>`, `msSaveOrOpenBlob`, iframe fallback, `pixelRatio`, `connectedBackgroundColor` for `echarts.connect`) | Browser download plumbing. Native answer: `TSaveDialog` + bitmap write. `pixelRatio` becomes a DPI-scaled offscreen render |
| `saveAsImage.type:'svg'` (requires the SVG renderer) | There is no SVG renderer in a BGRABitmap control unless one is written |
| `title.link` / `sublink` / `target` (`windowOpen`) | Native answer: an `OnTitleClick` event, or `OpenURL` from `LCLIntf` |
| `aria` `role="img"` / `aria-label` DOM attributes | Native answer: platform accessibility API, or expose the generated text as a property |
| `dataZoom-inside.cursorGrab` / `cursorGrabbing` (v6.1), `preventDefaultMouseMove` | CSS cursor name strings and browser default-event suppression. Native answer: `crHandPoint` / a custom cursor; `preventDefault` has no analogue |
| `graphic` event handlers `onmousewheel`, `ondragenter/leave/over/drop` (HTML5 drag-and-drop semantics) | Native answer: LCL drag/drop, which has different semantics; wheel is fine |
| `zlevel` as separate canvas layers (progressive rendering, per-layer clearing) | An optimization tied to multi-canvas compositing. Native answer: one surface + a dirty-rect cache (`TTyPaintCache`, remembering the `pf24bit` rule for non-composited blits) |
| Touch gestures: pinch-zoom (`RoamController._pinchHandler`), `axisPointer.handle` drag button | Desktop-only control; keep the API but the handle is only useful on touch displays |
| `echarts.connect` cross-instance linkage (`connectedBackgroundColor`) | Multi-instance browser feature; a native equivalent would be an explicit controller shared by several chart controls |

### One design instruction that falls out of this survey

The single highest-leverage decision is to **treat `renderMode:'richText'` as the reference
implementation for every text-bearing overlay** — tooltip, axis-pointer label, dataZoom handle label,
legend item, visualMap label. ECharts already proved that the whole component set can be drawn on a bare
canvas with no DOM; the `richText` path plus the `tooltipMarkup` block model is the blueprint. Everything
classified BROWSER-BOUND above is the `'html'` branch of a fork that already has a canvas branch.
