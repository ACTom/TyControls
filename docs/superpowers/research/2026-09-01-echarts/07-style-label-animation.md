# ECharts 6.1.0 — Visual/style system, labels, states, animation

Research pass for a native Object Pascal / BGRABitmap chart control. Everything below was read out of
`D:/Projects/echarts` (TS source + `dist/echarts.esm.js` for the vendored zrender internals, which are not
checked out separately) and `D:/Projects/echarts-doc` (official option reference, `${partial}` macros resolved).

Scope: `src/util/{states,symbol,decal,format,styleCompat,graphic,animation}.ts`, `src/label/*`, `src/visual/*`,
`src/animation/*`, `src/theme/dark.ts`, `theme/*.js`, `src/model/globalDefault.ts`, `src/model/mixin/{itemStyle,
lineStyle,areaStyle,palette}.ts`, `en/option/partial/*.md`, `en/option/component/aria.md`, `en/tutorial/{rich-text,
style-overview,media-query,renderer}.md`.

---

## 1. The style primitive model

### 1.1 How a style reaches the canvas

ECharts option-level style objects are **key-renamed** into zrender `PathStyleProps`, which are then applied
1:1 to Canvas2D state. The rename tables are literal arrays in the source:

`ITEM_STYLE_KEY_MAP` (`src/model/mixin/itemStyle.ts`) — 13 entries:

| option key (`itemStyle.*`) | canvas/zrender prop | Canvas2D equivalent |
|---|---|---|
| `color` | `fill` | `fillStyle` |
| `borderColor` | `stroke` | `strokeStyle` |
| `borderWidth` | `lineWidth` | `lineWidth` |
| `opacity` | `opacity` | multiplies both fill and stroke alpha |
| `shadowBlur` | `shadowBlur` | `shadowBlur` |
| `shadowOffsetX` / `shadowOffsetY` | same | `shadowOffsetX/Y` |
| `shadowColor` | `shadowColor` | `shadowColor` |
| `borderType` | `lineDash` | `setLineDash()` |
| `borderDashOffset` | `lineDashOffset` | `lineDashOffset` |
| `borderCap` | `lineCap` | `lineCap` |
| `borderJoin` | `lineJoin` | `lineJoin` |
| `borderMiterLimit` | `miterLimit` | `miterLimit` |

`LINE_STYLE_KEY_MAP` (`src/model/mixin/lineStyle.ts`) — 12 entries, same targets, different option names:
`width`→`lineWidth`, `color`→`stroke`, `opacity`, `shadow*`, `type`→`lineDash`, `dashOffset`→`lineDashOffset`,
`cap`→`lineCap`, `join`→`lineJoin`, `miterLimit`.

`AREA_STYLE_KEY_MAP` (`src/model/mixin/areaStyle.ts`) — 6 entries only: `color`→`fill`, `shadowBlur`,
`shadowOffsetX`, `shadowOffsetY`, `opacity`, `shadowColor`. **No stroke, no dash on areaStyle.**

`backgroundStyle` is not a fourth primitive: it is an `itemStyle`-shaped object reused where a "track" is drawn
behind the data (`series.bar.backgroundStyle` with `showBackground: true`, default fill
`rgba(180,180,180,0.2)`; `matrix.backgroundStyle`). Same key map as itemStyle.

`decal` is deliberately **not** transferred by the key mappers (comment in all three files): the option is a
`DecalObject`, the style prop is a resolved `PatternObject`. Conversion happens in a separate visual stage
(`src/visual/decal.ts`).

### 1.2 The line/border sub-style block (`partial-line-border-style`)

Shared by `itemStyle` (prefix `border`), `lineStyle` (no prefix), and text stroke (prefix `textBorder`):

| Option | Type | Values / semantics |
|---|---|---|
| `borderType` / `type` / `textBorderType` | `string \| number \| number[]` | `'solid'`, `'dashed'`, `'dotted'`; since v5.0 also a number (`n` ⇒ dash `[n,n]`) or a number array = SVG `stroke-dasharray` |
| `borderDashOffset` / `dashOffset` / `textBorderDashOffset` | `number` = 0 | phase offset into the dash pattern |
| `borderCap` / `cap` | `'butt'` (default) \| `'round'` \| `'square'` | line caps |
| `borderJoin` / `join` | `'bevel'` (default!) \| `'round'` \| `'miter'` | note: ECharts defaults to **bevel**, Canvas2D defaults to miter |
| `borderMiterLimit` / `miterLimit` | `number` = 10 | only with `join: 'miter'`; ≤0, Infinity, NaN ignored |

`cap`/`join`/`miterLimit` are **not** exposed on text stroke (`noCap/noJoin/noMiterLimit` are forced).

### 1.3 Shadow + opacity block (`partial-style-shadow-opacity`)

`shadowBlur` (number, 0), `shadowColor` (Color), `shadowOffsetX` (0), `shadowOffsetY` (0), `opacity` (0..1;
element not drawn at 0). Identical block on itemStyle, lineStyle, areaStyle, component boxes, and text boxes.
Note the text element carries **two independent shadow sets**: `shadowBlur/Color/OffsetX/OffsetY` for the text
*box*, and `textShadowBlur/Color/OffsetX/OffsetY` for the *glyphs*.

### 1.4 `borderRadius` — three different things

`borderRadius` is **not** a `PathStyleProps` key. It is a *shape* parameter, resolved per-series:

1. **Rect (bar, matrix cell, text box)** — scalar or 4-array `[topLeft, topRight, bottomRight, bottomLeft]`,
   clockwise from top-left (`BarView.ts` sets `Rect.shape.r`). Also `graphic.rect.shape.r`.
2. **Sector (pie, sunburst, gauge, polar bar)** — `number | string | Array`, percentages allowed.
   Pre-5.3: `[inner, outer]`. Since 5.3: `[innerStart, innerEnd, outerStart, outerEnd]` clockwise from the
   inside; a percentage is relative to `(outerR - innerR)`.
3. **Text fragment box** — 4-array like the rect case, on `label.borderRadius` and on each `rich.<name>`.

### 1.5 Z-ordering primitives

| Option | Semantics |
|---|---|
| `zlevel` (0) | Separate canvas **layer**. Bigger `zlevel` paints over smaller. Browser-motivated (one `<canvas>` per level for partial repaint). |
| `z` (2) | Draw order within a zlevel; no new canvas. |
| `z2` | Per-element order inside a component; used heavily by state lifts (see §7). |
| `Z2_EMPHASIS_LIFT` = 10, `Z2_SELECT_LIFT` = 9 | Constants in `src/util/states.ts`: entering emphasis raises `z2` by 10, select by 9, unless the element sets `z2EmphasisLift` / `z2SelectLift`. |

`blendMode` (global, per-series override; `src/core/echarts.ts:2639`) maps directly to
`globalCompositeOperation`. Default `'source-over'`; `'lighter'` is the documented interesting one (additive
glow for dense line/scatter). Full enum is the CSS/Canvas composite operation list.

---

## 2. Colour

### 2.1 Accepted colour forms (parser at `dist/echarts.esm.js:3969 parse()`)

| Form | Example | Note |
|---|---|---|
| named CSS colour | `'red'`, `'steelblue'`, `'transparent'` | **148 entries** in the built-in `kCSSColorTable`; whitespace stripped, lowercased |
| `#rgb` | `'#f0a'` | 3-digit expanded by nibble duplication |
| `#rgba` | `'#f0a8'` | 4-digit, alpha nibble / 15 |
| `#rrggbb` | `'#ff00aa'` | |
| `#rrggbbaa` | `'#ff00aa80'` | alpha byte / 255 |
| `rgb(r,g,b)` | ints or `%` | `parseCssInt` accepts `'50%'` |
| `rgba(r,g,b,a)` | | |
| `hsl(h,s,l)` | `hsla2rgba` converts | h wrapped mod 360, s/l accept `%` |
| `hsla(h,s,l,a)` | | |
| anything else | falls back to opaque black `[0,0,0,1]` | silent |

Parsed results are LRU-cached. `'none'` is accepted as a *fill/stroke* sentinel meaning "do not paint".

### 2.2 Gradient objects

```
{ type: 'linear', x: 0, y: 0, x2: 0, y2: 1, colorStops: [{offset, color}, ...], global: false }
{ type: 'radial', x: 0.5, y: 0.5, r: 0.5,  colorStops: [{offset, color}, ...], global: false }
```

`x/y/x2/y2/r` are **fractions of the element's bounding box** by default (0..1). With `global: true` (docs also
call it `globalCoord`) they are absolute pixel coordinates in the chart's coordinate space. `colorStops` is an
ordered list of `{offset: 0..1, color: <any colour form>}`. Gradients are legal anywhere a Color is legal,
including `option.color` palette entries, `backgroundColor`, label `color`, `textBorderColor`, and label
`backgroundColor`.

`option.gradientColor` (global default `[lightThemeColor, themeColor]`, derived by
`modifyHSL(theme[0], null, null, 0.9)`) is the implicit ramp used by heatmap-ish visuals when no explicit
`inRange.color` is given.

### 2.3 Pattern (texture) objects

```
{ image: <HTMLImageElement|HTMLCanvasElement|dataURI|url>, repeat: 'repeat'|'repeat-x'|'repeat-y'|'no-repeat' }
```
Plus internal `PatternObject` fields used by decal: `rotation` (radians), `scaleX`, `scaleY`, `x`, `y`.
The docs explicitly say an SVG *path string* is **not** accepted here — it must be a raster source. This is a
DOM-image dependency.

### 2.4 Callback colours

`itemStyle.color`, `lineStyle.color`, `areaStyle.color` accept `(params) => Color` on the series types where
`hasCallback` is set (line, bar, scatter, effectScatter, pictorialBar, graph, custom, …). `params` is the
standard `CallbackDataParams` (seriesIndex, seriesName, dataIndex, name, value, data, encode, dimensionNames,
color, …). Implementation: `src/visual/style.ts` `seriesStyleTask` — if the colour is a function, the series
gets `colorFromPalette: false` and the callback is evaluated per datum in a `dataEach` pass.

### 2.5 The palette

- `option.color: Color[]` — the palette. v6 default is `tokens.color.theme`:
  `['#5070dd','#b6d634','#505372','#ff994d','#0ca8df','#ffd10a','#fb628b','#785db0','#3fbe95']` (9 colours).
  The doc page still lists the v5 palette `['#5470c6','#91cc75','#fac858','#ee6666','#73c0de','#3ba272',
  '#fc8452','#9a60b4','#ea7ccc']` — the doc is stale relative to 6.1 source.
- `series.color: Color[]` — a palette scoped to one series (overrides the global list for that series only).
- `option.colorLayer: Color[][]` — *layered* palettes. `getNearestPalette()` picks the first sub-palette whose
  length exceeds the requested colour count, else the last. Lets a theme ship a 5-colour set for small charts
  and a 20-colour set for large ones.
- `colorBy: 'series' | 'data'` (v5.2+) — `'series'`: one palette colour per series; `'data'`: one palette
  colour per datum. Pie/funnel default to `'data'`. Palette cursors are **scoped**: a shared scope object per
  `seriesType + '-' + colorBy` so two pie series continue the same rotation while a bar series has its own.
- Assignment is *by name*, not by index: `getFromPalette` memoises `name → colour` in `paletteNameMap`, so
  toggling a legend entry does not reshuffle colours (`src/model/mixin/palette.ts`).
- Precedence: explicit `itemStyle.color` > `visualMap` encoding > palette. A series with an explicit colour
  does **not** consume a palette slot (deliberate, so background/ghost series don't shift the palette).

### 2.6 The v6 design-token layer (`src/visual/tokens.ts`) — new, and structurally important

ECharts 6 introduced a token table that all built-in defaults now reference instead of hard-coded hexes:

- `tokens.color.theme` — the 9-colour palette.
- 21 neutral steps `neutral00 … neutral99` (00 = `#fff`, 99 = `#000`).
- 19 accent steps `accent05 … accent95`.
- Semantic aliases: `primary`(=neutral80), `secondary`(70), `tertiary`(60), `quaternary`(50), `disabled`(20),
  `border`/`borderTint`/`borderShade`, `background`/`backgroundTint`/`backgroundTransparent`/`backgroundShade`,
  `shadow`/`shadowTint`, `axisLine`, `axisLineTint`, `axisTick`, `axisTickMinor`, `axisLabel`, `axisSplitLine`,
  `axisMinorSplitLine`, `highlight` (`rgba(255,231,130,0.8)`), `transparent`.
- `tokens.darkColor` is **derived programmatically**: for accent keys `modifyHSL(hex, null, s=>s*0.5,
  l=>min(1, 1.3-l))`; for everything else `modifyHSL(hex, null, s=>s*0.9, l=>1-l^1.5)`; theme palette and
  `highlight` are special-cased.
- `tokens.size = {xxs:2, xs:5, s:10, m:15, l:20, xl:30, xxl:40, xxxl:50}` — a spacing scale.

This is exactly the "theme token" architecture a native control wants; it is a straight data port.

### 2.7 darkMode and automatic contrast

- `option.darkMode: boolean | 'auto'` (default `'auto'`). Auto-detection: `isDarkMode(backgroundColor)` =
  `lum(color, 1) < 0.4`, where `lum = (0.299R + 0.587G + 0.114B) * a/255 + (1-a)*bgLum`. Gradients average
  the stop luminances.
- **Automatic label colour** (this is a real algorithm, not a knob). When a label's `position` contains
  `'inside'` and the host is a `Path`:
  - `getInsideTextFill()` — inspect the host's `style.fill`. `lum > 0.5` ⇒ `#333`; `0.2 < lum ≤ 0.5` ⇒ `#eee`;
    else `#ccc`. Non-string fill (gradient/pattern) ⇒ `#ccc`. `fill === 'none'` ⇒ `#333`.
  - `getInsideTextStroke(textFill)` — if the chart dark-mode flag equals `lum(textFill) < 0.4`, stroke the
    glyphs with the host fill (halo so the text separates from its own background); else no stroke.
  - Outside labels: `getOutsideFill()` = `#ccc` in dark mode, `#333` otherwise; `getOutsideStroke()` composites
    the chart background over white/black to produce an opaque halo colour.
- `color: 'inherit'` (and legacy `'auto'`) on any text style means "take the visual colour of the host series
  datum". Same for `backgroundColor: 'inherit'`, `borderColor: 'inherit'`, `textBorderColor: 'inherit'`.

### 2.8 Visual channels (`src/visual/VisualMapping.ts`)

Ten mappable visual channels, each with `linear` / `category` / `piecewise` / `fixed` mapping methods:
`color`, `colorHue`, `colorSaturation`, `colorLightness`, `colorAlpha`, `decal`, `opacity`, `liftZ`,
`symbol`, `symbolSize`. Colour interpolation is `fastLerp` in RGBA space; hue/sat/lightness go through
`modifyHSL`; alpha through `modifyAlpha`.

---

## 3. `decal` — pattern fill

Enabled only when `aria.enabled: true` **and** `aria.decal.show: true` (accessibility feature: give colour-blind
users a second channel). Set `decal: 'none'` on a series/datum to opt out. For series with no fill by default
(line, radar, boxplot) decal only shows if `areaStyle` is set.

### 3.1 Option surface (`itemStyle.decal`, `aria.decal.decals[]`)

| Key | Default | Meaning |
|---|---|---|
| `symbol` | `'rect'` | symbol name, or `string[]`, or `string[][]` (used row by row / column by column) |
| `symbolSize` | `1` | 0..1, symbol size relative to its dash cell |
| `symbolKeepAspect` | `true` | |
| `color` | `'rgba(0,0,0,0.2)'` | pattern ink; translucent so it composites over the series colour |
| `backgroundColor` | `null` | painted under the pattern, over the series colour |
| `dashArrayX` | `5` | `number` \| `number[]` \| `(number\|number[])[]` — SVG-dasharray-like horizontal rhythm; the outer array indexes *rows* |
| `dashArrayY` | `5` | `number` \| `number[]` — vertical rhythm |
| `rotation` | `0` | radians, applied to the whole tile |
| `maxTileWidth` | `512` | clamp on generated tile size |
| `maxTileHeight` | `512` | |

### 3.2 How the tile is generated (`src/util/decal.ts`)

1. Normalise `dashArrayX` to `number[][]`, `dashArrayY` to `number[]`, `symbol` to `string[][]`.
   Odd-length arrays are doubled (`[4,2,1]` → `[4,2,1,4,2,1]`) so that dash/gap alternation is well-defined.
2. Per-row block length = sum of that row's dash array (doubled if odd length).
3. **Tile width = LCM of all row block lengths × LCM of all symbol-row lengths.** Tile height =
   `blockLengthY × rowCount × symbolRowCount`. Clamped to `maxTileWidth/Height` (with a dev warning when the
   clamp introduces a visible seam).
4. Draw onto an offscreen canvas at `dpr`: for each even Y band and each even X segment, place a symbol inset
   by `(1 - symbolSize) * 0.5` of the cell, sized `cellW*symbolSize × cellH*symbolSize`.
5. Wrap as `PatternObject {repeat:'repeat', rotation, scaleX=scaleY=1/dpr}` and LRU-cache (100 entries) keyed
   by the 9 decal keys plus dpr.

The 6 built-in decals (`src/model/globalDefault.ts`) are: vertical hatch rotated 30°, dotted circles,
hatch rotated −45°, dashed grid, cross-hatch rotated 45°, and triangles.

---

## 4. Labels

### 4.1 The `label` option surface

`show` (bool), `position`, `distance` (5), `rotate` (−90..90 deg, positive = anticlockwise), `offset` `[dx,dy]`,
`formatter`, plus the whole text-style block. `label.emphasis` / `.blur` / `.select` mirror it.

Text style keys, grouped exactly as `src/label/labelStyle.ts` groups them:

- **`TEXT_PROPS_WITH_GLOBAL`** (inherit from `option.textStyle`, and — since v6 — from the plain label into
  `rich` items): `fontStyle` (`'normal'|'italic'|'oblique'`), `fontWeight`
  (`'normal'|'bold'|'bolder'|'lighter'|100..900`), `fontSize` (12), `fontFamily` (`'sans-serif'`, but
  `'Microsoft YaHei'` when `navigator.platform` starts with `Win`), `textShadowColor`, `textShadowBlur`,
  `textShadowOffsetX`, `textShadowOffsetY`.
- **`TEXT_PROPS_SELF`** (never inherited): `align` (`left|center|right`), `verticalAlign`
  (`top|middle|bottom`), `lineHeight`, `width`, `height`, `tag`, `ellipsis`.
- **`TEXT_PROPS_BOX`** (the label's box): `padding` (scalar, `[v,h]`, or `[t,r,b,l]`), `borderWidth`,
  `borderRadius`, `borderDashOffset`, `backgroundColor`, `borderColor`, `shadowColor`, `shadowBlur`,
  `shadowOffsetX`, `shadowOffsetY`. Plus `borderType` → `borderDash`.
- **Glyph fill/stroke**: `color`, `textBorderColor`, `textBorderWidth`, `textBorderType`,
  `textBorderDashOffset`, `opacity`.
- **Overflow**: `width`, `height`, `overflow` (`'none'|'truncate'|'break'|'breakAll'`), `ellipsis` (`'...'`).
- **v6 additions**: `textMargin` (number or CSS-style 1/2/4 array, applied to the *unrotated* local rect, then
  rotated), `minMargin` (number only, applied to the *rotated* AABB; effective gap between two labels is
  `a.minMargin/2 + b.minMargin/2`), `richInheritPlainLabel` (bool, default true — v6 changed rich fragments to
  inherit the plain label's font props; set false for v5 behaviour).

`label.backgroundColor` may also be `{image: <src>}`, in which case `width`/`height` auto-fit the image aspect.

### 4.2 `position` — enumerated per series family

**Rectangular hosts** (bar on cartesian, pictorialBar, scatter, effectScatter, heatmap, line symbols, graph
nodes, map, tree nodes, treemap, custom, graphic) — 13 named values plus a coordinate pair. Implemented in
`calculateTextPosition` (`dist/echarts.esm.js:5940`), which resolves each to `(x, y, align, verticalAlign)`
relative to the host bounding rect with `distance` applied:

| Value | x | y | align | verticalAlign |
|---|---|---|---|---|
| `'left'` | `x - d` | `y + h/2` | right | middle |
| `'right'` | `x + w + d` | `y + h/2` | left | middle |
| `'top'` | `x + w/2` | `y - d` | center | bottom |
| `'bottom'` | `x + w/2` | `y + h + d` | center | top |
| `'inside'` | `x + w/2` | `y + h/2` | center | middle |
| `'insideLeft'` | `x + d` | `y + h/2` | left | middle |
| `'insideRight'` | `x + w - d` | `y + h/2` | right | middle |
| `'insideTop'` | `x + w/2` | `y + d` | center | top |
| `'insideBottom'` | `x + w/2` | `y + h - d` | center | bottom |
| `'insideTopLeft'` | `x + d` | `y + d` | left | top |
| `'insideTopRight'` | `x + w - d` | `y + d` | right | top |
| `'insideBottomLeft'` | `x + d` | `y + h - d` | left | bottom |
| `'insideBottomRight'` | `x + w - d` | `y + h - d` | right | bottom |
| `[x, y]` | pixel or `'50%'` strings relative to the rect's top-left | — | null | null |
| `'outside'` | not a zrender value; bar maps it to `defaultOutsidePosition` (`'top'`) | | | |

Special case in `SymbolClz.calculateTextPosition`: for `symbol: 'pin'` with `position: 'inside'`, y is pushed
to `rect.y + 0.4*h` so the label sits in the pin's head.

**Sector hosts** (pie, sunburst, gauge, polar bar) add 9 sector-relative positions
(`src/label/sectorLabel.ts`, `SectorTextPosition`): `'startAngle'`, `'insideStartAngle'`, `'endAngle'`,
`'insideEndAngle'`, `'middle'`, `'startArc'`, `'insideStartArc'`, `'endArc'`, `'insideEndArc'`, resolved
against `(cx, cy, r0, r, startAngle, endAngle, clockwise)`.

**Pie** exposes only `'outside'` (default), `'inside'` / `'inner'`, `'center'`.
**Bar on polar** adds `start`, `insideStart`, `middle`, `insideEnd`, `end` (v5.2+).
**Funnel** has 12: `left`, `right`, `top`, `bottom`, `inside`, `insideLeft`, `insideRight`, `leftTop`,
`leftBottom`, `rightTop`, `rightBottom`, plus `inner`/`center` aliases of `inside`.
**Graph edge label** has 3: `start`, `middle` (default), `end`.
**Sankey** default `'right'`. **themeRiver** default `'left'`. **map** default `'bottom'`.
**Line** default `'top'`. **Bar/scatter/heatmap/graph/pictorialBar/sunburst/treemap** default `'inside'`.

**Radial rotation**: `sunburst.label.rotate` (and the `partial-label-rotate-tangential` block) accepts, besides
a number, the strings `'radial'` and `'tangential'`.

### 4.3 `formatter`

Two forms; `'\n'` always means newline.

**String template.** `formatTpl` (`src/util/format.ts`) substitutes up to 7 positional aliases
`{a} {b} {c} {d} {e} {f} {g}` mapped in order from the params object's `$vars` list; per-series indexing
(`{a0}`, `{c1}`) is used in multi-series tooltips.

- 2-D data series: `{a}` series name, `{b}` datum name, `{c}` datum value.
- 1-D data series (pie, funnel, gauge, radar, map): additionally `{d}` = percentage.
- `{@dimName}` — value of a named dimension, e.g. `{@score}`.
- `{@[n]}` — value at dimension index `n`, e.g. `{@[3]}`.
- Rich-text fragment markup `{styleName|content}` is a *different* grammar layered on the same braces
  (see §4.5) — the regex is `/\{([a-zA-Z0-9_]+)\|([^}]*)\}/g`, so it only fires when a `|` is present.

**Callback.** `(params) => string`, where params is the `CallbackDataParams` record: `componentType`,
`seriesType`, `seriesIndex`, `seriesName`, `name`, `dataIndex`, `data`, `value`, `encode`, `dimensionNames`,
`dimensionIndex` (radar only), `color`, plus per-series extras (`percent` for pie, etc.).

Related helpers a port would need: `addCommas` (thousands separator), `formatTime` with `{yyyy}{MM}{dd}{hh}{mm}{ss}{SSS}`
placeholders, `makeValueReadable` (null/NaN → `'-'`).

### 4.4 Overflow, truncation, wrapping

`overflow` only takes effect when `width` is set (or, for labels attached to a host, when
`textConfig.autoOverflowArea` derives a width from the host rect — used by the v6 matrix component).

- `'none'` (default) — draw past the box.
- `'truncate'` — clip each line and append `ellipsis` (default `'...'`).
- `'break'` — wrap at word boundaries.
- `'breakAll'` — wrap at any character.

`truncateSingleLine` (`dist:9674`) is an iterative estimate: measure the line; if it fits, done. Otherwise
estimate a character count by accumulating per-character widths, cut, re-measure, repeat at most
`maxIterations` (2), then append the ellipsis. If the ellipsis itself doesn't fit, the ellipsis is dropped.
`minChar` reserves room for N ASCII characters. Result reports `isTruncated`.

`wrapText` (`dist:10027`) is a single-pass greedy wrapper. A "word" is a run of characters for which
`isWordBreakChar(ch)` is false — i.e. alphabetic letters that are not in `breakCharMap`. **Every non-alphabetic
character (including CJK) is a break opportunity**, which is why CJK wraps correctly without a dictionary.
`breakAll` forces every character to be a break opportunity.

Additionally, rich text supports `lineOverflow: 'truncate'` — drop whole lines once `height` is exceeded.

### 4.5 Rich text — the mini-language

Grammar: inside a label's `formatter` output, `{styleName|text content}` applies the style object
`label.rich[styleName]` to that fragment. `styleName` matches `[a-zA-Z0-9_]+`. `\n` starts a new line.
Text outside any marker uses the plain label style. An empty content (`{bg|}`) is legal and is the idiom for a
pure background/rule block.

Each `rich.<name>` accepts the **full text-style-base-item set**: `color`, `fontStyle`, `fontWeight`,
`fontFamily`, `fontSize`, `align`, `verticalAlign`, `lineHeight`, `backgroundColor` (colour **or**
`{image: src}`), `borderColor`, `borderWidth`, `borderType`, `borderRadius`, `padding`, `shadowColor`,
`shadowBlur`, `shadowOffsetX`, `shadowOffsetY`, `width` (number or `'NN%'` of the block content width),
`height`, `textBorderColor`, `textBorderWidth`, `textShadow*`.

Layout rules (from `parseRichText`, `dist:9817`, and the rich-text tutorial):

1. Every fragment behaves like a CSS `inline-block`.
2. Fragment content box defaults to its measured text size; `width`/`height` override it; `padding` is added
   outside the content box.
3. Line height = max of the fragments' `lineHeight` (fragment `lineHeight` → parent `lineHeight` → fragment
   box height).
4. Vertical placement inside the line by `verticalAlign`: `'top'` sticks to line top, `'bottom'` to line
   bottom, `'middle'` (default for fragments) centres.
5. Horizontal placement: first all `align:'left'` fragments left-to-right, then all `align:'right'` fragments
   right-to-left, then the remainder is centred in the leftover space.
6. Block width = explicit `width` else the longest line. Percentage fragment widths are resolved in a second
   pass against the finished block content width.
7. `backgroundColor.image` fragments auto-size width from `imageW * tokenHeight / imageH` when width is unset.

Documented idioms built purely from these rules: **icons** (`backgroundColor.image` + `height`), **horizontal
rules** (`width:'100%'`, `height:0`, `borderWidth:0.5`), **title bars** (`backgroundColor` + `width:'100%'` +
`borderRadius:[5,5,0,0]`), and **simple tables** (equal `width` on same-column fragments across lines).

### 4.6 Text measurement (this is the load-bearing detail for a port)

`ensureFontMeasureInfo(font)` builds, per font string, an LRU-cached record:

- `stWideCharWidth` = measured width of `'国'` — **and `getLineHeight(font)` returns exactly this value**.
  ECharts' line height is the width of a CJK ideograph in that font, not a font metric.
- `asciiCharWidth` = width of `'a'`.
- `asciiWidthMap[0..127]` — built lazily by measuring all 128 ASCII chars once; abandoned if the batch takes
  >16 ms, and permanently abandoned after 5 slow attempts (`GET_ASCII_WIDTH_LONG_COUNT_MAX`).
- `strWidthCache` — LRU(500) of whole-string widths.

`measureCharWidth(code)` = ASCII map entry if available, else `asciiCharWidth` for 0..127, else
`stWideCharWidth` for everything ≥128. So all non-ASCII characters are assumed full-width. Whole strings go
through the real `measureText`.

Bounding rect: split on `\n`, measure each line, union; then `adjustTextX/adjustTextY` shift by
align/verticalAlign (`right` ⇒ `-w`, `center` ⇒ `-w/2`; `bottom` ⇒ `-h`, `middle` ⇒ `-h/2`).

Font string assembly (`getFont`): `"<fontStyle> <fontWeight> <fontSize>px <fontFamily>"` with global
`textStyle` fallbacks.

### 4.7 Label value animation

`label.valueAnimation: true` + `label.precision` (`number | 'auto'`) makes the label text interpolate
numerically during an update instead of snapping. Implementation: `animateLabelValue` in
`src/label/labelStyle.ts` animates a dummy `percent` prop 0→1 and, in the `during` callback, calls
`interpolateRawValues(data, precision, from, to, percent)` and re-runs the formatter. Used by bar-race demos,
`series.line.endLabel.valueAnimation`, gauge detail, etc.

### 4.8 Line `endLabel`

`series.line.endLabel` — a second, independent label attached to the last visible point of the line, with the
full label option surface (no `position`), `valueAnimation`, and its own emphasis/blur states. Distinct
capability, not a styling knob.

---

## 5. `labelLine` and `labelLayout` — the de-collision system

### 5.1 `labelLine`

| Key | Meaning |
|---|---|
| `show` | |
| `showAbove` | draw the guide line above the host element instead of below |
| `length` | first segment length (radial leg for pie) |
| `length2` | second segment length (horizontal leg) |
| `smooth` | `false` \| `true` \| 0..1 — bezier smoothing factor |
| `minTurnAngle` | 0..180 deg; the elbow is nudged so the two segments never form too sharp an angle |
| `maxSurfaceAngle` | (pie) limit the angle between the leg and the sector surface |
| `lineStyle` | full lineStyle block |

**Automatic routing** (`src/label/labelGuideHelper.ts` `updateLabelLinePoints`): for each of 4 candidate
anchors on the label rect (`['top','right','bottom','left']`, overridable via `textGuideLineConfig.candidates`),
extend outward by `length2` to get `pt1`, transform into the host's local space, then find the nearest point on
the host — `nearestPointOnPath` for a `Path` (walks the `PathProxy` command list, projecting onto lines, arcs
and sampling beziers) or `nearestPointOnRect` otherwise. The candidate with the smallest distance wins, giving
a 3-point polyline `[hostAnchor, elbow, labelAnchor]`. Then `limitTurnAngle` and, where used,
`limitSurfaceAngle` post-process it.

The guide line animates in via a `strokePercent` 0→1 draw-on, and animates between old and new point sets on
update (`LabelManager._animateLabels`).

### 5.2 `labelLayout`

Available on 18 series/components. Two forms: a static object, or a **callback**
`(params) => Partial<LabelLayoutOption>` receiving `{dataIndex, dataType, seriesIndex, text, labelRect,
align, verticalAlign, rect, labelLinePoints}` — `rect` being the host element's bounding rect, which lets you
size the font from the shape (`fontSize: max(rect.width/10, 5)`).

| Key | Meaning |
|---|---|
| `hideOverlap` (bool) | greedy overlap suppression |
| `moveOverlap` (`'shiftX'` \| `'shiftY'`) | 1-D sequential de-collision |
| `x`, `y` | absolute px or `'20%'` of chart size — overrides the series-computed position |
| `dx`, `dy` | pixel offset on top of `x`/`y` |
| `rotate` | degrees |
| `width`, `height` | with `overflow` to constrain |
| `align`, `verticalAlign` | |
| `fontSize` | |
| `draggable` (bool) | user can drag the label; the guide line re-routes live (`cursor: 'move'`) |
| `labelLinePoints` | `[[x,y],[x,y],[x,y]]` manual override of the guide polyline |

### 5.3 The algorithms

**`hideOverlap(labelList)`** (`src/label/labelLayoutHelper.ts:522`): sort by `suggestIgnore` then `priority`
descending; walk the list keeping a `displayedLabels` accumulator; a candidate that intersects any accepted
label is hidden (`el.ignore = true`, but its `emphasis` state gets `ignore: false` so it reappears on hover).
Intersection is two-stage: AABB fast reject, then — only if either label has a non-axis-aligned transform —
an **oriented bounding box (OBB) SAT test** with a `touchThreshold` of 0.05. OBBs are lazily built and cached
with a dirty bit.

**`shiftLayoutOnXY(list, dim, minBound, maxBound)`** (`:324`): the `moveOverlap` engine, and also what pie
uses internally. Sort by position on the axis; sweep forward pushing each label past the previous one's end;
optionally re-centre by the mean shift (`balanceShift`); then, if the run overflows either bound, `squeezeGaps`
compresses the inter-label gaps by up to 80 %, then `takeBoundsGap` borrows slack from the opposite end, then
a final `squeezeWhenBailout` allows overlap rather than exceeding the bounds (deliberately handing the problem
to `hideOverlap`).

**Pie-specific** (`src/chart/pie/labelLayout.ts`): a separate, richer pass — split labels into left/right
semicircles, `shiftLayoutOnXY` each on Y, `recalculateXOnSemiToAlignOnEllipseCurve` re-solves X from the
ellipse implicit equation so the elbows stay on a smooth arc, `constrainTextWidth` truncates against
`bleedMargin`/`edgeDistance`, and `avoidOverlap` handles the `alignTo: 'none' | 'labelLine' | 'edge'` modes.

**Axis labels** have their own, simpler de-collision: `axisLabel.hideOverlap` (v5.2+), plus
`showMinLabel`/`showMaxLabel` (`null` = auto-hide when overlapped), `axisLabel.interval`, and v6's
`axisName.nameMoveOverlap`.

The whole pass is orchestrated by `LabelManager` (`src/label/LabelManager.ts`): collect labels → apply
`labelLayout` per label (restoring saved `defaultAttr` first, so the pass is idempotent) → `shiftLayoutOnXY`
for shiftX/shiftY groups → `restoreIgnore` + `hideOverlap` for the hideOverlap group → update guide lines →
animate.

---

## 6. States

### 6.1 The model

Four display states (`DISPLAY_STATES`): `'normal'`, `'emphasis'`, `'blur'`, `'select'`; the last three are
`SPECIAL_STATES`. States are **stacks** on the element (`el.currentStates`), each contributing a partial style
that is merged over normal. A `stateProxy` function synthesises missing states.

Hover state is tracked as an integer per element: `HOVER_STATE_NORMAL=0`, `HOVER_STATE_BLUR=1`,
`HOVER_STATE_EMPHASIS=2`.

### 6.2 Default (synthesised) state styles — `elementStateProxy`

- **emphasis**: if the user gave no `emphasis.itemStyle.color`, the fill is auto-derived as
  `liftColor(normalFill)` = `lift(color, -0.1)` — i.e. each RGB channel × 1.1, clamped, cached. Gradients are
  lifted stop by stop. If the fill was lifted, the stroke is **not** also lifted. `fill: 'inherit'` (v5.2+)
  disables the lift and keeps the normal colour. `z2` is raised by `Z2_EMPHASIS_LIFT` (10).
- **blur**: if no explicit blur opacity, `opacity = normalOpacity * 0.1`. Guards against multiplying twice
  when already blurred.
- **select**: `z2` raised by `Z2_SELECT_LIFT` (9). No automatic colour change.
- The proxy is installed on the element *and* on its attached text content and text guide line, so labels and
  leader lines follow the state.

### 6.3 Emphasis options

| Option | Values |
|---|---|
| `emphasis.disabled` (v5.3+) | bool — kill hover/highlight entirely for this element (perf escape hatch) |
| `emphasis.focus` | `'none'` (default), `'self'`, `'series'`; `'adjacency'` on **graph**; `'ancestor'` / `'descendant'` on **tree/treemap/sunburst**; `'relative'` (ancestors+descendants) on tree/sunburst; `'trajectory'` on **sankey**. `geo` supports only `'none'`/`'self'`. |
| `emphasis.blurScope` | `'coordinateSystem'` (default), `'series'`, `'global'` — how far the fade-out reaches |
| `emphasis.scale` | bool or number (default 1.1, v5.3.2+) — symbol/sector grow on hover. `pie.emphasis.scale` + `scaleSize` (10 px). `effectScatter.emphasis.scale` default 2.5. |
| `emphasis.itemStyle` / `.lineStyle` / `.areaStyle` / `.label` / `.labelLine` / `.endLabel` | full style blocks |

20 series/components declare `focus`/`blurScope`. `blurSeries()` walks every series, decides
`sameSeries`/`sameCoordSys`, and calls `enterBlur` on the group traversal of the non-focused views. Focus can
also be an index array or a `{dataType: indices}` map internally (used by graph adjacency).

### 6.4 Select

`selectedMode`: `false` (default) | `true` | `'single'` | `'multiple'` | `'series'` (v5.3+). 19 series expose
it. Per-datum `select.disabled` (v5.3+) opts a datum out. Actions: `select`, `unselect`, `toggleSelect`;
event `selectchanged`. `select.itemStyle` / `select.label` etc. supply the styling.

`stateAnimation: {duration: 300, easing: 'cubicOut'}` — global and per-series — controls the tween used when
crossing a state boundary. `duration: 0` disables it.

### 6.5 Hover/highlight dispatch

`enableHoverEmphasis` marks an element a "highDownDispatcher"; mouseover enters emphasis on it and blurs
according to `focus`/`blurScope`. A 32-slot digit map (`getHighlightDigit`) lets several sources (legend hover,
tooltip, `dispatchAction({type:'highlight'})`, axisPointer) hold the highlight simultaneously; the element only
returns to normal when all are released. `highDownSilentOnTouch` suppresses hover-emphasis on touch devices
where select is also in play.

---

## 7. Animation

### 7.1 Global / per-series options

| Option | Default | Notes |
|---|---|---|
| `animation` | `'auto'` (truthy) | master switch, also per-series |
| `animationThreshold` | 2000 | animation is skipped when the element count exceeds this |
| `animationDuration` | 1000 | `number \| (dataIndex) => number` |
| `animationEasing` | `'cubicInOut'` (global default) / `'cubicOut'` (partial default) | |
| `animationDelay` | 0 | `number \| (dataIndex, extraParams) => number` — per-datum stagger |
| `animationDurationUpdate` | 500 (global) / 300 (partial) | callback form supported |
| `animationEasingUpdate` | `'cubicInOut'` | |
| `animationDelayUpdate` | 0 | callback form supported |
| `stateAnimation.duration/easing` | 300 / `'cubicOut'` | state crossfades |
| `progressive` / `progressiveThreshold` / `progressiveChunkMode` | 400 / 3000 / `'sequential'` \| `'mod'` | chunked rendering, not animation, but it interacts (animation is off for progressive chunks) |

Precedence in `getAnimationConfig`: explicit `extraOpts` > values from the current update **payload**
(`dataZoom`/`resize` inject `payload.animation`) > model options. Three animation *kinds* are distinguished:
`'enter'`, `'update'`, `'leave'` — `initProps`, `updateProps`, `removeElement`.

Removal animates `style.opacity → 0` then detaches (`removeElementWithFadeOut`), after removing the label and
guide line.

### 7.2 The 31 built-in easings

All are closed-form, all in `dist/echarts.esm.js:3095-3260`, all trivially portable:

`linear`; `quadraticIn/Out/InOut`; `cubicIn/Out/InOut`; `quarticIn/Out/InOut`; `quinticIn/Out/InOut`;
`sinusoidalIn/Out/InOut`; `exponentialIn/Out/InOut`; `circularIn/Out/InOut`; `elasticIn/Out/InOut`
(amplitude a=0.1→1, period p=0.4); `backIn/Out/InOut` (s=1.70158, ×1.525 for InOut); `bounceIn/Out/InOut`.

= 1 + 10 families × 3 = **31 names**. No CSS `cubic-bezier()` support in the animation system (the only
`cubic-bezier` in the codebase is the DOM tooltip's CSS transition).

### 7.3 Element-level transition mini-language (custom series + `graphic` component)

`ELEMENT_ANIMATABLE_PROPS = ['', 'style', 'shape', 'extra']` — four namespaces that can be tweened.

- `transition: 'x' | ['x','y'] | 'all'` — which props tween on update (default `['x','y']`).
- `enterFrom: {...}` — starting values for a newly created element (`el.animateFrom`).
- `leaveTo: {...}` — target values before removal.
- `enterAnimation` / `updateAnimation` / `leaveAnimation`: `{duration, easing, delay}` per phase.
- `keyframeAnimation: Object | Object[]` — real keyframes:
  `{duration, delay, easing, loop, keyframes: [{percent, easing, ...props}]}`. Multiple concurrent keyframe
  tracks are allowed (one for `scaleX/Y`, one for `x`, …). Keyframes are sorted by `percent`; a keyframe track
  stops any non-keyframe animator on the same props; original values are saved so
  `stopPreviousKeyframeAnimationAndRestore` can rewind. Keyframe animation wins over `transition` for a
  contested prop. Dev warning if no `percent: 1` frame exists.

### 7.4 `universalTransition` — cross-series morphing

Opt-in feature module (`echarts.use([UniversalTransition])`); documented on 13 series types
(bar, boxplot, candlestick, custom, funnel, heatmap, line, lines, map, pictorialBar, pie, radar, scatter).

| Option | Meaning |
|---|---|
| `universalTransition: true` or `{enabled: true}` | enable |
| `seriesKey: string \| string[]` | which series are considered "the same thing" across `setOption` calls; defaults to `series.id`. An **array** means "all these series merge into this one" (many-to-one) |
| `divideShape: 'split' \| 'clone'` | how one shape becomes many. `'split'` cuts the path geometry; `'clone'` duplicates the path and fits the alpha so N stacked clones read as the original opacity (`1 - (1-α)^(1/n)`). Defaults differ per series: scatter (small, complex symbols) uses `clone`, bar uses `split`. |
| `delay: (index, count) => number` | per-shape stagger for one-to-many/many-to-one |
| datum `groupId` / `childGroupId`, series `dataGroupId` | build the parent/child relation that drives drill-down and aggregation. The engine sniffs which direction (`TRANSITION_P2C` vs `TRANSITION_C2P`) by checking whether old `childGroupId`s intersect new `groupId`s or vice versa. |
| `graphic`/custom element `morph: false` | opt one element out of morphing |

**What it looks like**: when you `setOption` from, say, a bar chart to a pie chart with the same `seriesKey`,
every bar rectangle continuously deforms into its corresponding pie sector — position, shape *and* style —
instead of the old series fading out and the new fading in. Drill-down: one bar splits into the N bars of its
child group, each fragment flying to its new position. Aggregation: N shapes combine into one.

**Mechanism** (`src/animation/morphTransitionHelper.ts` + zrender `morphPath`): collect the flat list of
`Path`s under each element (skipping `disableMorphing`, invisible and ignored ones); pair them into batches
(`prepareMorphBatches` distributes the "many" side round-robin across the "one" side, then rebalances so no
batch is empty); then per batch either `morphPath` (1:1 — resample both paths to a common command count and
lerp), `separateMorph` (1:N — `dividePath` splits the source path into N sub-paths, each morphs to a target)
or `combineMorph` (N:1). `animateOtherProps` tweens style/transform alongside. If no `id` match exists, the
engine falls back to matching by data `id`, which the source calls "more robust than groupId".

### 7.5 Label animation specifics

`LabelManager._animateLabels`: labels are animated separately from their host. A brand-new label fades in
(`style.opacity 0→1`) unless `valueAnimation` is on; an existing label tweens `x`, `y`, `rotation` from its
stored `oldLayout`. If the host was previously in `select`/`emphasis`, the stored per-state layouts
(`oldLayoutSelect` / `oldLayoutEmphasis`) are used as the "from" so the tween starts from what was on screen.
`disableLabelAnimation` / `forceLabelAnimation` flags override.

---

## 8. Symbols

### 8.1 Built-in names

Documented set (`partial-icon-buildin`): **`'circle'`, `'rect'`, `'roundRect'`, `'triangle'`, `'diamond'`,
`'pin'`, `'arrow'`, `'none'`** — 8 values. The source (`src/util/symbol.ts` `symbolCtors` /
`symbolShapeMakers`) also implements two undocumented ones: **`'line'`** (a horizontal segment, used by legend
and by line-symbol rendering) and **`'square'`** (min(w,h) square).

Geometry as implemented:

| Name | Construction |
|---|---|
| `circle` | centre `(x+w/2, y+h/2)`, r = `min(w,h)/2` |
| `rect` | the box as-is |
| `roundRect` | rect with corner r = `min(w,h)/4` |
| `square` | `min(w,h)` square anchored top-left |
| `line` | segment from `(x, y+h/2)` to `(x+w, y+h/2)` (stroke-coloured, not filled) |
| `triangle` | apex up, isoceles in the box |
| `diamond` | 4 points at box edge midpoints |
| `pin` | teardrop: circle of r = `(3w/5)/2`, tangent-joined to a cusp at the bottom via two cubic beziers; height forced ≥ width |
| `arrow` | 4-point chevron, `dx = 2w/3`, notch at `y + 3h/4` |
| `none` | nothing drawn |

**`empty`-prefixed variants**: any name may be prefixed with `empty` (`'emptyCircle'`, `'emptyRect'`,
`'emptyTriangle'`, …). `createSymbol` strips the prefix, lowercases the next char, and flags
`__isEmptyBrush`, which makes `setColor` stroke with the series colour and fill with `tokens.color.neutral00`
(white) at `lineWidth: 2` — the classic hollow line-chart marker. `series.line.symbol` defaults to
`'emptyCircle'`.

### 8.2 Custom symbol forms

- `'image://<url>'` or `'image://<dataURI>'` — raster. `makeImage(src, rect, keepAspect ? 'center' : 'cover')`.
- `'path://<SVG path data>'` — arbitrary vector path (`makePath`), auto-fitted to the symbol box; `'center'`
  layout when `symbolKeepAspect`, else `'cover'` (non-uniform stretch). This is a **full SVG PathData parser**
  requirement: `MmLlHhVvCcSsQqTtAaZz`, absolute and relative, with elliptical arcs.

### 8.3 Symbol modifiers

| Option | Type | Semantics |
|---|---|---|
| `symbol` | `string \| (value, params) => string` | callback per datum where supported |
| `symbolSize` | `number \| [w,h] \| (value, params) => number\|number[]` | `normalizeSymbolSize` broadcasts a scalar to `[n,n]` |
| `symbolRotate` | `number \| callback` (v4.8+ for callback) | degrees; **negative = clockwise**. Ignored for `markLine` `'arrow'`, which is forced to the tangent angle. |
| `symbolOffset` | `[x, y]`, each `number` or `'NN%'` of the symbol size | e.g. `[0, '-50%']` puts a pin's tip on the data point. `normalizeSymbolOffset` broadcasts a scalar and defaults y to x. |
| `symbolKeepAspect` | bool, default false | only meaningful for `path://` and `image://` |

Line series adds directional variants: `showSymbol`, `showAllSymbol`, `symbolKeepAspect`; `lines`/`markLine`
add `fromSymbol`/`toSymbol` with matching `*Size`, `*Rotate`, `*Offset`, `*KeepAspect`.

---

## 9. Themes

### 9.1 What a theme is

A theme is a **plain option-shaped object** registered by name:

```js
echarts.registerTheme('vintage', { color: [...], backgroundColor: '#fef8ef', graph: {color: [...]} });
const chart = echarts.init(dom, 'vintage');   // or init(dom, themeObjectDirectly)
```

`registerTheme(name, theme)` just writes into a module-level `themeStorage` map (`src/core/echarts.ts:3051`).
Two themes are registered by the core itself: `'default'` (empty) and `'dark'` (`src/theme/dark.ts`).
The repo's `theme/` directory ships **36 additional themes** as UMD `.js` files that self-register (azul,
bee-inspired, blue, caravan, carp, cool, dark-blue, dark-bold, dark-digerati, dark-fresh-cut, dark-mushroom,
dark, eduardo, forest, fresh-cut, fruit, gray, green, helianthus, infographic, inspired, jazz, london,
macarons, macarons2, mint, rainbow, red-velvet, red, roma, royal, sakura, shine, tech-blue, v5, vintage).
They can also be shipped as raw JSON and registered manually.

Themes range from trivial (`vintage.js`: 3 keys) to comprehensive (`dark.js`: ~180 lines covering
`axisPointer`, `legend`, `textStyle`, `title`, `toolbox`, `dataZoom`, `tooltip`, `timeline`, `visualMap`,
`markPoint`, per-axis-type `categoryAxis`/`valueAxis`/`logAxis`/`timeAxis`, `radar`, `treemap`, `sunburst`,
`map`, `geo`, and `darkMode: true`).

### 9.2 Merge rules — what a theme can and cannot override (`mergeTheme`, `src/model/Global.ts:1018`)

1. `theme.color` is **skipped** if the user's option has its own `color`.
2. `theme.colorLayer` is **skipped** if the user's option has `color` but no `colorLayer`.
3. For any key that is *not* a registered component main type (e.g. `textStyle`, `animation*`,
   `backgroundColor`, `darkMode`, `stateAnimation`): deep-merge as a *low-priority* source
   (`merge(userOption[name], themeItem, false)` — user wins), or plain assignment when the user value is null.
4. For keys that **are** component main types (`series`, `xAxis`, `legend`, `tooltip`, …), the theme value is
   left for the ComponentModel's own merge to handle later — this is how a theme can style
   `series` *by type* (`theme.line`, `theme.bar`, `theme.pie`, …) and per-axis-type
   (`theme.categoryAxis`, `theme.valueAxis`, `theme.logAxis`, `theme.timeAxis`).
5. Then `merge(baseOption, globalDefault, false)` fills anything still missing.

So: a theme **can** set the palette, background, dark-mode flag, every component's default styling, per-series
defaults keyed by series type, per-axis defaults keyed by axis type, and animation defaults. A theme **cannot**
change data, layout logic, or override anything the user explicitly set in `option`; and it cannot introduce
new behaviour — only defaults.

### 9.3 Media queries (responsive option)

```js
option = {
  /* baseOption props */,
  media: [
    { query: {minWidth: 500}, option: {legend: {orient: 'vertical', right: 0}} },
    { query: {maxAspectRatio: 1}, option: {...} },
    { option: {...} }               // no query = default fallback
  ]
}
```

`query` keys are `min|max` × `Width|Height|AspectRatio` (regex `QUERY_REG` splits the prefix; attr is
lower-cased). `aspectRatio = width / height`. Multiple keys in one query = logical AND. Every matching media
unit is applied in declaration order (later wins); if none match, the query-less `mediaDefault` applies. Each
matched `option` is merged with `mergeOption` semantics. Re-evaluated on resize; only re-applied when the set
of matched indices actually changes.

There is also `option.options[]` + `timeline` (the timeline's per-frame option array), which uses the same
OptionManager machinery.

---

## 10. Things that exist only because of the browser

| Item | Why |
|---|---|
| `renderer: 'canvas' \| 'svg'` at `echarts.init` | two zrender back-ends; SVG also enables `ssr` mode and `renderToSVGString`. Decal generates an SVG `<g>` vnode instead of a canvas tile when the SVG painter is active. |
| `zlevel` | one `<canvas>` element per level; the whole "extra canvas is cheap but memory-heavy on mobile" warning is DOM-specific. |
| `hoverLayerThreshold` (3000) | promotes hovered elements to a separate canvas layer to avoid a full repaint. |
| `useDirtyRect`, `devicePixelRatio`, `useCoarsePointer`, `pointerSize` | init opts, painter/hit-test concerns. |
| `blendMode` | `globalCompositeOperation`; only `source-over` and `lighter` are actually documented as useful. |
| `cursor` (`'auto'|'pointer'|'move'|'grab'|'grabbing'|…`) | CSS cursor names. |
| `backgroundColor: {image: HTMLImageElement \| HTMLCanvasElement}` on text/pattern | DOM image objects. |
| `symbol: 'image://<url>'` | asynchronous image loading with an LRU cache and a dirty-flag callback. |
| `aria.label` | writes an `aria-label` attribute on the container DOM. (`aria.decal` is *not* browser-bound.) |
| `tooltip` DOM rendering (`TooltipHTMLContent`, `cubic-bezier` CSS transition, `extraCssText`) | separate topic, but note tooltip has a `renderMode: 'richText'` fallback that reuses the rich-text engine — relevant if a native port wants tooltips. |
| `progressive` chunking tied to rAF (~16 ms budget) | frame-scheduling model. |
| WebGL / `echarts-gl` | not in this repo at all. |
| Worker threads | not used by ECharts core. |

---

## Porting notes

### NATURAL — maps directly onto an immediate-mode antialiased 2D canvas (BGRABitmap)

- **All of `itemStyle` / `lineStyle` / `areaStyle` / `backgroundStyle`**: fill, stroke, width, opacity.
  BGRABitmap has direct equivalents for every key except shadows and dashes (see HEAVY).
- **Colour parsing**: `#rgb`/`#rgba`/`#rrggbb`/`#rrggbbaa`/`rgb()`/`rgba()`/`hsl()`/`hsla()`/148 named colours.
  Pure string→RGBA function, plus an LRU. Port verbatim.
- **`lift`, `modifyHSL`, `modifyAlpha`, `lum`** — the colour math behind emphasis lift, dark-token derivation,
  and auto-contrast labels. ~40 lines each.
- **Linear and radial gradients** — BGRABitmap has `TBGRAGradientScanner` / `CreateGradient`. The only work is
  mapping fractional bbox coordinates (and the `global: true` absolute mode) to device space.
- **Palette machinery**: `color[]`, `colorLayer[][]` with `getNearestPalette`, `colorBy: 'series'|'data'`,
  name-keyed memoisation, per-`(seriesType, colorBy)` scopes. Pure bookkeeping.
- **Design tokens** (`tokens.color.*`, `tokens.size.*`) and the derived dark variants — a constant table plus
  one HSL transform. This is the single highest-value thing to copy wholesale.
- **`borderRadius`** on rects (4-corner) — BGRABitmap `RoundRectAntialias` or a manual path.
- **`cap` / `join` / `miterLimit`** — BGRABitmap pen has `LineCap` and `JoinStyle`; note ECharts' join default
  is `bevel`, not `miter`.
- **All 31 easing functions** — closed-form scalars, copy them.
- **Animation timing model** (enter/update/leave, duration/easing/delay incl. per-datum callback, threshold,
  payload override precedence) — a straightforward tween engine over named properties.
- **State model** (normal/emphasis/blur/select as a stack of partial styles, `z2` lifts of 10/9, default
  emphasis = `lift(fill, -0.1)`, default blur = `opacity × 0.1`, `'inherit'` colour semantics) — pure logic.
- **`focus` / `blurScope` / `disabled` / `selectedMode`** — set membership and traversal.
- **Symbol geometry** for circle, rect, roundRect, square, line, triangle, diamond, arrow, pin (the pin needs
  the tangent/bezier construction, ~20 lines of trig) and the `empty*` hollow variants.
- **`symbolSize` / `symbolRotate` / `symbolOffset` / `symbolKeepAspect`** normalisation.
- **Label `position` resolution** — the 13-value table in §4.2 is a pure switch producing
  `(x, y, align, verticalAlign)`; the 9 sector positions are trig.
- **Label box** — background fill, border (with dash), border radius, padding, box shadow.
- **`textBorderColor`/`textBorderWidth`** glyph outline — BGRABitmap can render text to a mask and
  stroke/fill it; or draw the text N times offset for a cheap outline.
- **Automatic inside/outside label colour** (`lum` thresholds at 0.5 / 0.2, halo stroke rule) — copy exactly.
- **Theme model**: a theme is an option-shaped record merged as a low-priority source, with the two `color` /
  `colorLayer` exceptions. Maps naturally onto ty-controls' existing theme-token architecture.
- **Media queries** — evaluate `min/max` × `width/height/aspectRatio` against the control's client size on
  resize; apply the matching option overlays in order. Trivial and genuinely useful for a resizable control.
- **`formatTpl` string templates** (`{a}{b}{c}{d}`, `{@dim}`, `{@[n]}`) and `addCommas` / `formatTime`.
- **`aria.decal` palette rotation** — the 6 default decal descriptors and the name-keyed rotation.

### HEAVY — doable, but a named algorithm has to be implemented

- **Text measurement + the `ensureFontMeasureInfo` cache.** Algorithm: per-font record holding
  `width('国')` (which *is* ECharts' line height), `width('a')`, a lazily-built 128-entry ASCII width table
  (abandoned after >16 ms, permanently after 5 slow attempts), and an LRU(500) string-width cache. On LCL,
  `TCanvas.TextWidth`/BGRABitmap `TextSize` per call is far too slow for thousands of labels — the cache is
  not optional. Note the existing ty-controls trap: CJK width assumptions and space-only word wrapping.
- **Greedy line-breaking (`wrapText`).** Word = run of alphabetic chars not in `breakCharMap`; *every other
  character, including all CJK, is a break opportunity*. This is exactly the CJK-wrap rule ty-controls already
  learned the hard way — ECharts' version is the correct reference.
- **Iterative truncation with ellipsis (`truncateSingleLine`).** Estimate character count by accumulating
  per-char widths, cut, re-measure, ≤2 iterations, append ellipsis, drop the ellipsis if it alone overflows.
  Plus `minChar` and the `isTruncated` report.
- **Rich-text engine.** Tokenise `{name|content}` with `/\{([a-zA-Z0-9_]+)\|([^}]*)\}/g`; build lines of
  inline-block tokens; line height = max token lineHeight; vertical align per token; horizontal placement =
  left-run, then right-run, then centre the remainder; two-pass percentage widths; per-token background
  (colour *or* image), border, radius, padding, shadow; `lineOverflow: 'truncate'` drops whole lines. This is a
  small inline layout engine — budget it as such. High payoff (icons, rules, title bars, tables all fall out
  of it for free).
- **`hideOverlap`.** Priority sort, greedy accept, AABB fast-reject then **OBB separating-axis test** for
  rotated labels, with a 0.05 touch threshold and a lazily-cached OBB per label. Needed the moment labels can
  rotate.
- **`shiftLayoutOnXY` (`moveOverlap: 'shiftX'|'shiftY'`).** Sort → forward sweep → optional mean re-centre →
  `squeezeGaps` (≤80 %) → `takeBoundsGap` (borrow slack from the other end) → `squeezeWhenBailout` (allow
  overlap rather than exceed bounds). ~150 lines, well specified.
- **Pie label layout.** `shiftLayoutOnXY` per semicircle + re-solving X from the ellipse implicit equation +
  `constrainTextWidth` against `bleedMargin`/`edgeDistance` + the three `alignTo` modes. A distinct,
  substantial routine on top of the generic one.
- **`labelLine` auto-routing.** 4 candidate anchors × nearest-point-on-shape. `nearestPointOnPath` must walk a
  path command list projecting onto lines and arcs and sampling beziers; `limitTurnAngle` and
  `limitSurfaceAngle` post-process the elbow. Plus the `strokePercent` draw-on animation.
- **Decal tile generation.** Normalise dash arrays (double odd-length ones), compute tile size as the
  **LCM of row block lengths × LCM of symbol-row lengths**, render symbols into an offscreen tile, cache by
  key, then tile with rotation. BGRABitmap can tile a bitmap brush, but rotation of a repeating pattern needs
  either a pre-rotated oversized tile or a custom scanner. Clamp at 512×512 like ECharts does.
- **Shadows (`shadowBlur`/`shadowColor`/`shadowOffsetX/Y`).** No Canvas2D-equivalent primitive in BGRABitmap:
  render the shape to an offscreen alpha mask, Gaussian-blur it, tint, offset, composite under. ty-controls
  already has shadow experience (`windowed-control-shadow-corners`) — same technique, but here it must work
  per graphic element, which is expensive if used liberally. Consider limiting shadows to component boxes.
- **Dashed strokes with `dashOffset`.** BGRABitmap pens support dash patterns but the offset/phase and
  arbitrary `number[]` patterns may need a manual path-splitting pass.
- **Line dash on curved paths + `strokePercent`** (partial stroke, used by guide-line draw-on and
  `graphic.line.percent`) — requires arc-length parameterisation of the path.
- **`path://` custom symbols.** A full SVG PathData parser (all of `MmLlHhVvCcSsQqTtAaZz`, including
  elliptical-arc → bezier conversion) plus bbox-fit in `'center'` / `'cover'` modes.
- **`universalTransition` shape morphing.** The heaviest single item. Requires: path flattening to a common
  command vocabulary, **resampling two paths to an equal segment count with matched winding and start-point
  alignment**, then per-vertex lerp; plus `dividePath` (split a path into N area-balanced sub-paths) for
  one-to-many, and the inverse for many-to-one; plus the batch pairing/rebalancing
  (`prepareMorphBatches`) and the groupId/childGroupId direction sniffing. Visually spectacular, but this is a
  multi-week item on its own. Recommend deferring; a cross-fade + position tween covers 80 % of the value.
- **`keyframeAnimation`.** Multi-track keyframe animator with per-keyframe easing, looping, save/restore of
  original values, and precedence over `transition`. Moderate.
- **Label `valueAnimation`.** Needs numeric interpolation of the *raw* value plus re-running the formatter each
  frame, with `precision: 'auto'` deriving decimal places from the data.
- **`animationThreshold` / `progressive` / `progressiveThreshold` / `progressiveChunkMode`.** The concept
  (bail out of animation and chunk the render above N elements) is worth porting; in a native control the
  chunking maps to painting in slices across timer ticks rather than to rAF.

### BROWSER-BOUND — needs a native re-think, or is out of scope

- **`renderer: 'canvas' | 'svg'`, `ssr`, `renderToSVGString`.** No analogue; a native control has one painter.
  Consequence: the decal SVG-vnode branch is dead code for a port.
- **`zlevel` as "one canvas per level".** Port the *ordering* semantics; drop the layering rationale. A native
  control may still want a cached background surface, but not N of them.
- **`hoverLayerThreshold`, `useDirtyRect`, `devicePixelRatio`, `useCoarsePointer`, `pointerSize`.** Painter and
  hit-test tuning tied to the DOM canvas model. The dirty-rect idea maps onto an offscreen cache
  (ty-controls' `TTyPaintCache`), but with the known `pf24bit` caveat for opaque blits.
- **`blendMode` / `globalCompositeOperation`.** BGRABitmap has blend operations (`TBlendOperation`) but not the
  full Porter-Duff + separable-blend set; `'lighter'` (additive) is achievable, the rest are not worth it.
- **`cursor`** — CSS cursor names; map to LCL `TCursor` (`crDefault`, `crHandPoint`, `crSizeAll`, …). Trivial
  but the enum does not correspond 1:1.
- **`backgroundColor: {image: HTMLImageElement|HTMLCanvasElement}` and `symbol: 'image://<url>'`.** The
  *raster pattern* concept ports fine (BGRABitmap texture brush); the async URL/dataURI loading, the global
  image LRU, and the "re-dirty the host element when the image finishes loading" callback need a native
  image-cache design. Recommend accepting only already-loaded `TBGRABitmap` handles (this repo has already been
  bitten by `MakeBitmapCopy` on BGRA — use a direct `AssignBitmap`-style API).
- **`aria.label`** — generates an `aria-label` string on the container DOM. The *description-generation
  templates* (`aria.label.general.withTitle`, `.series.single/multiple.withName/withoutName`, `.data.allData/
  partialData/withName/withoutName`, `maxCount`, separators, `excludeDimensionId`) are pure string assembly and
  could feed an MSAA/UIAutomation accessible name — but the delivery mechanism is entirely different.
  `aria.decal`, by contrast, is fully portable.
- **DOM tooltip** (`TooltipHTMLContent`, `extraCssText`, CSS `cubic-bezier` transition, HTML in the formatter,
  `encodeHTML`, `getTooltipMarker` emitting a `<span style="...">`). A native port must use the
  `renderMode: 'richText'` path, which reuses the rich-text engine — plan for that, and note that
  `formatter` callbacks returning HTML will simply not work.
- **Web fonts / `fontFamily: 'sans-serif' | 'serif' | 'monospace'` generic families.** Need mapping to LCL font
  names; note the existing `empty-fontname-gotcha` — never pass an empty family through to BGRA text.
- **`navigator.platform`-based default font** (`'Microsoft YaHei'` on Windows) — replace with a proper
  per-platform fallback list.
- **Worker threads / WebGL / `echarts-gl`** — absent from this repo; out of scope.
