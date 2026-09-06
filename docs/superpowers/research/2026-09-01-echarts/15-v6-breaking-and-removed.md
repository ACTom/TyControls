# ECharts 5 → 6: breaking changes, removals, deprecations

What a `TTyAdvanceChart` targeting **ECharts 6** inherits that a **v5** target would not.

Sources read: `D:/Projects/echarts` (6.1.0), `D:/Projects/echarts-doc` (both repos are shallow,
`git rev-list --count HEAD` = 1, so no cross-version diffing is possible — everything below comes
from the changelog, the option docs, and the 6.1.0 source itself).

---

## 0. Headline for the decision

**Target v6.** The v5→v6 break surface is unusually small — 5 official breaking bullets, 0 removed
series, 0 removed components, 0 removed actions/events/API methods — and every single one of them is
an *escape hatch for existing users*, not a constraint on a new implementation. A greenfield port
starts on the far side of all five and pays nothing.

The v6 delta that actually matters to a port is **additive**: a design-token theme layer, a matrix
coordinate system, axis breaks, `coordinateSystemUsage`, chord, thumbnail, scatter jitter. Those are
covered in reports 01–10; this report only covers what *changed shape or died*.

---

## 1. The migration material: there isn't any

| Expected | Found |
|---|---|
| `en/tutorial/upgrade-guide-v6.md` | **does not exist** |
| `en/tutorial/whats-new-in-echarts-v6.md` | **does not exist** |
| `zh/tutorial/upgrade-guide-v6.md` | **does not exist** |

`D:/Projects/echarts-doc/en/tutorial/` holds 26 files. The only upgrade guide is
`upgrade-guide-v5.md` (271 lines) plus `whats-new-in-echarts-v5.md`. `grep -rln "v6\|6\.0"` over
`en/tutorial/` returns **zero** files.

The **entire** official v6 breaking-change record is two `[Break]` blocks in `en/changelog.md`:

- `en/changelog.md:122-127` — 5 bullets, "Breaking changes against v5.6.0"
- `en/changelog.md:69-72` — 3 bullets, "Breaking changes against `v6.0.0`"

That is 8 bullets total for a major version bump. Compare v5, which shipped a 271-line guide plus a
`#### Break Changes` section in the 5.2.0 notes (`changelog.md:484`) and a
`[Break Change] change to default ESM package` in 5.5.0 (`changelog.md:193`).

**Implication for the port:** the changelog IS the spec for the delta. There is no prose migration
narrative to mine. This report is therefore the migration guide.

---

## 2. Breaking changes v5.6.0 → v6.0.0 (5 official bullets)

### B1 — Default theme replaced *(subsystem: theme + component default layout)*

`changelog.md:123`. The default visual style **and the default positions of components/series**
changed. Users restore via `echarts/theme/v5.js` (581 lines, 34 top-level keys, 17 explicit layout
keys).

Concrete deltas verified against source:

| Thing | v5 default | v6 default |
|---|---|---|
| legend | `top: 0` (`theme/v5.js:425-426`) | `left:'center', bottom: tokens.size.m` (`src/component/legend/LegendModel.ts:455-460`) |
| title | `left: 0, top: 0` (`theme/v5.js:525-526`) | `left:'center', top: tokens.size.m` (`src/component/title/install.ts:117-118`) |
| grid | `left:'10%', top:60, bottom:70` (`theme/v5.js:418-420`) | `left:'15%', top:65, right:'10%', bottom:80` (`src/coord/cartesian/GridModel.ts:129-132`) |
| palette[0..3] | `#5470c6 #91cc75 #fac858 #ee6666` (`theme/v5.js:44-47`) | `#5070dd #b6d634 #505372 #ff994d` (`src/visual/tokens.ts:112-115`) |

The mechanism behind this is new and **directly relevant to ty-controls' tycss token model**:
v6 introduced `src/visual/tokens.ts` (233 lines), a two-plane design-token layer —

- `tokens.color` and `tokens.darkColor`, each a `ColorToken` with **67 named slots**: `theme[]`
  (the categorical palette), `neutral00…neutral99` (21 steps), `accent05…accent95` (19 steps),
  `primary/secondary/tertiary/quaternary`, `disabled`, `highlight`, `border/borderTint/borderShade`,
  `background/backgroundTint/backgroundShade/backgroundTransparent`, `shadow/shadowTint`,
  `axisLine/axisLineTint/axisTick/axisTickMinor/axisLabel/axisSplitLine/axisMinorSplitLine`
  (`src/visual/tokens.ts:23-87`)
- `tokens.size` — 8 steps `xxs, xs, s, m, l, xl, xxl, xxxl` (`src/visual/tokens.ts:92-101`)

`src/model/globalDefault.ts:21,31,41` consumes it (`color: tokens.color.theme`). In v5 there was no
such layer; defaults were hard-coded hex.

> **Port note:** this is the single most useful v6-only structure for ty-controls. The token names map
> almost 1:1 onto tycss custom properties, and `light`/`dark` maps onto `@mode`. A v5 target would have
> to invent this layer; a v6 target can transcribe it.

### B2 — `src/theme/light.ts` removed *(subsystem: theme packaging)*

`changelog.md:124`: "The v5 `echarts/src/theme/light.ts` is now migrated to `echarts/theme/rainbow.js`."

Verified: `ls src/theme/` returns **only `dark.ts`**. `ls theme/` returns 38 entries including
`rainbow.js` (63 lines) and `v5.js` (581 lines). This is a rename + relocation, not a capability loss.

### B3 — Cartesian anti-overflow / anti-overlap layout is now default *(subsystem: grid/axis layout)*

`changelog.md:125`. Axis labels and axis names no longer overflow the canvas, and axis names no
longer overlap axis labels. Escape hatches: `grid.outerBoundsMode:'none'` and
`xAxis/yAxis.axisLabel.nameMoveOverlap:false`.

This is **the** substantive v6 layout change and the one a port has to decide about, because it
brought a new option cluster (`outerBounds`, `outerBoundsMode`, `outerBoundsContain`,
`outerBoundsClampWidth/Height`) and **deprecated `grid.containLabel`** (see §6).

Note the mechanism `containLabel` was demoted to: in a tree-shaken build the legacy implementation is
an **opt-in feature module** (`use(LegacyGridContainLabel)`, `src/export/features.ts:25`). The full
build installs it automatically (`src/echarts.all.ts:373`). Without it, setting `grid.containLabel`
logs a dev warning and **silently substitutes the outerBounds layout**
(`src/coord/cartesian/Grid.ts:236-240`). So it is not merely deprecated — in the modular build path
it is already gone.

### B4 — `center` percent base changed *(subsystem: view coordinate systems)*

`changelog.md:126`. Affects `geo`, `series.map`, `series.graph`, `series.tree`. The changelog states
plainly "The previous percent base is incorrect" — i.e. this is a **bug fix promoted to a break**,
not a redesign. Escape hatch: root-level `legacyViewCoordSysCenterBase: true`
(`src/coord/View.ts:841`, type at `src/util/types.ts:806`).

**A fresh port implements the v6 base and never implements the flag.**

### B5 — `label.rich.*` now inherits plain label style *(subsystem: labels)*

`changelog.md:127`. Eight props now inherit: `fontStyle`, `fontWeight`, `fontSize`, `fontFamily`,
`textShadowColor`, `textShadowBlur`, `textShadowOffsetX`, `textShadowOffsetY`. Escape hatch:
`richInheritPlainLabel: false`, settable at the root level **or** at the same level as the label style
(`src/label/labelStyle.ts:428-431, 539, 631-632`).

Again a defensible-defaults change; a port implements inheritance and skips the flag.

---

## 3. Breaking changes v6.0.0 → v6.1.0 (3 official bullets)

`changelog.md:69-72`. **Minor versions in the v6 line do carry breaking changes.** This matters for
pinning: "target v6" should mean "target 6.1.x", not "target 6.x".

### B6 — `tooltip.valueFormatter` 2nd param semantics
`dataIndex` (post-dataZoom-filter index) → `rawDataIndex` (index into the original `series.data`).
A silent semantic change on an existing parameter — the worst kind to inherit from a v5 port later.

### B7 — `axis.startValue` decoupled from `axis.min`
Previously `startValue` doubled as `min` when `min` was absent. Now they are independent; the old
behavior needs both set explicitly.

### B8 — Series no longer overflow the grid rect
`bar`, `pictorialBar`, `candlestick`, `boxplot` edge shapes used to bleed outside the Cartesian
rectangle. Fixed; restore via `axis.containShape: false` (`src/coord/axisCommonTypes.ts:148`).

### Unflagged behavior change in 6.1.0: `clip` semantics
Not in the `[Break]` list but documented in `en/option/partial/clip.md:17-29`. Before 6.1.0 an
element was removed only if *fully* outside the coordinate system; from 6.1.0 the rule differs per
mark type (symbols: center-based; bars: partial-overflow-aware). Worth knowing because it silently
changes rendered output.

---

## 4. Removals: essentially none

I checked for removed series, components, actions, events, and public API methods.

| Category | v6.1.0 inventory | Removed 5→6 |
|---|---|---|
| Series (`src/chart/*.ts`) | 23 — bar boxplot candlestick **chord** custom effectScatter funnel gauge graph heatmap line lines map parallel pictorialBar pie radar sankey scatter sunburst themeRiver tree treemap | **0** (chord added) |
| Component installers (`src/component/*.ts`) | 33 — incl. **matrix**, **thumbnail** | **0** (2 added) |
| Actions / events | legacy select actions still register (`src/legacy/dataSelectAction.ts:45-61`) | **0** |
| Public API methods | `getRenderedCanvas`, `one`, `setCanvasCreator`, `coordDimToDataDim`, `getBandWidth` all still present, deprecated only | **0** |

What *was* actually removed:

1. `src/theme/light.ts` — relocated to `theme/rainbow.js` (B2).
2. `BarSeriesOption.startValue` — **TypeScript type only**, the option was never functional
   (`changelog.md:118`, "Remove unused `startValue` option from the `BarSeriesOption` interface").
   TS-bound; irrelevant to a Pascal port.
3. The internal SVG-support check inside `getSvgDataURL` (`changelog.md:121`). Browser-bound.
4. `grid.containLabel`'s implementation, from the tree-shaken build path only (B3).

**The big removals happened in v5, not v6** (`upgrade-guide-v5.md:118-121`): built-in geoJSON (the
`echarts/map` folder) and IE8/VML renderer support. A v5 target inherits those removals identically —
they are not a v6 differentiator. Note for the maps-in-scope decision: **neither v5 nor v6 ships
geoJSON data**; both require the host to register maps. That is a wash between the two targets.

---

## 5. `src/legacy/` and the real compat map

`src/legacy/` is tiny — **2 files, 160 lines**:

| File | Lines | Shims |
|---|---|---|
| `dataSelectAction.ts` | 114 | actions `pieSelect`/`pieUnSelect`/`pieToggleSelect` + `map*` → `select`/`unselect`/`toggleSelect`; events `pieselected`/`pieunselected`/`pieselectchanged` + `map*` → `selected`/`unselected`/`selectchanged` |
| `getTextRect.ts` | 46 | `echarts.format.getTextRect` |

The directory name is misleading. The actual historical-shape map is **6 files elsewhere**:

| File | Era it bridges | What changed shape |
|---|---|---|
| `src/preprocessor/helper/compatStyle.ts` | **EC3 → EC4** (~2018) | `itemStyle.normal.*` → `*` (:45); `itemStyle.emphasis.*` → `emphasis.*` (:58); `'normal'` hierarchy removed since 4.0 (:80); `<x>.emphasis` → `emphasis.<x>` since 4.0 (:93); `textStyle` hierarchy removed since 4.0 (:129); radar `name`→`axisName` (:300), `nameGap`→`axisNameGap` (:307), `indicator.text`→`indicator.name` (:313) |
| `src/preprocessor/backwardCompat.ts` | **EC3/EC4 → EC5** | `x/y/x2/y2` → `left/top/right/bottom` on 9 components (`grid geo parallel legend toolbox title visualMap dataZoom timeline`, :66-72); `barBorderRadius/Color/Width` → `borderRadius/Color/Width` (:74-78); pie `label.margin`→`edgeDistance` (:102); sunburst `downplay`→`blur` (:115), `highlightPolicy`→`emphasis.focus` (:216); graph/sankey `focusNodeAdjacency`→`emphasis.focus:'adjacency'` (:128); line `clipOverflow`→`clip` (:161); `clockWise`→`clockwise` (:169); `hoverOffset`→`emphasis.scaleSize` (:184); map `mapType`→`map` (:232), `mapLocation` dropped (:238); `hoverAnimation`→`emphasis.scale` (:248) |
| `src/util/styleCompat.ts` | **v4 → v5** (zrender text) | the 18-name text-prop rename table (`textFill`→`fill`, …) |
| `src/chart/radar/backwardCompat.ts` | v4 → v5 | radar indicator shape |
| `src/coord/geo/fix/geoCoord.ts` | **EC2 → EC3** | `geoCoord` (`src/chart/map/MapSeries.ts:106`: "Only for echarts2 backward compat") |
| `src/coord/cartesian/legacyContainLabel.ts` | **v5 → v6** | `grid.containLabel` |

**Reading of this map:** ECharts has *never deleted a compat shim*. Live code in 6.1.0 still
translates ECharts 2 `geoCoord` and ECharts 3 `itemStyle.normal`. The newest layer
(`legacyContainLabel`) is the v5→v6 one, and it is already the first shim ever gated behind an opt-in
module rather than being always-on — a mild signal that the maintainers are starting to charge for
backward compat.

Runtime deprecation wiring in 6.1.0: **32 `deprecateLog`/`deprecateReplaceLog` call sites** across
10 files; `grep -ri deprecat src/` matches **122 lines across 42 files**.

---

## 6. Deprecations still live in 6.1.0 — the actionable skip-list

A fresh port implements the right-hand column and never implements the left.

### 6a. Deprecated **in** v6 (only 2 in the option reference)

| Deprecated | Since | Replacement | Evidence |
|---|---|---|---|
| `grid.containLabel` | 6.0.0 | `grid.outerBoundsMode:'same'` + `grid.outerBoundsContain:'axisLabel'` | `en/option/component/grid.md:41,71` |
| `series-line.triggerLineEvent` | 6.1.0 *(docs)* / **6.0.1** *(source)* | `triggerEvent: true \| 'line' \| 'area'` | `en/option/series/line.md:112-115` vs `src/chart/line/LineSeries.ts:125,132` |

That second row is a **doc/source version disagreement** — see §7.

### 6b. Older deprecations still carried into 6.1.0

`tooltip.appendToBody` → `tooltip.appendTo` (deprecated 5.5.0; `en/option/component/tooltip.md:202`,
`src/component/tooltip/TooltipModel.ts:63-66`). Browser/DOM-bound — irrelevant to a Pascal port,
which has no DOM to append to.

The full v5-era list (`upgrade-guide-v5.md:147-251`) is **all still functional in 6.1.0**. Grouped,
with counts, as a skip-list:

| Group | Skip these | Implement instead |
|---|---|---|
| graphic transform (3) | `position`, `scale`, `origin` (array form) | `x`/`y`, `scaleX`/`scaleY`, `originX`/`originY` |
| graphic attached text (5) | `style.text` on non-Text elements; `textPosition`, `textOffset`, `textRotation`, `textDistance` | `textContent` + `textConfig.{position,offset,rotation,distance}` |
| zrender text style (18) | `textFill textStroke textFont textStrokeWidth textAlign textVerticalAlign textLineHeight textWidth textHeight textBackgroundColor textPadding textBorderColor textBorderWidth textBorderRadius textBoxShadowColor textBoxShadowBlur textBoxShadowOffsetX textBoxShadowOffsetY` | `fill stroke font lineWidth align verticalAlign lineHeight width height backgroundColor padding borderColor borderWidth borderRadius shadowColor shadowBlur shadowOffsetX shadowOffsetY` — **note** `textShadow*` (4) are NOT renamed |
| label colors (4) | value `'auto'` on `color`, `textBorderColor`, `backgroundColor`, `borderColor` | value `'inherit'` |
| emphasis (4) | `series.hoverAnimation`, `series.downplay`, `series.highlightPolicy`, `series.focusNodeAdjacency` | `emphasis.scale`, `series.blur`, `emphasis.focus`, `emphasis.focus:'adjacency'` |
| line (1) | `series.clipOverflow` | `series.clip` |
| pie/gauge (4) | `label.margin`, `clockWise`, `hoverOffset` (×2 series) | `label.edgeDistance`, `clockwise`, `emphasis.scaleSize` |
| map (2) | `series.mapType`, `series.mapLocation` | `series.map`; `mapLocation` has **no** replacement ("is not used anymore", `backwardCompat.ts:238`) |
| radar (2) | `radar.name`, `radar.nameGap` | `radar.axisName`, `radar.axisNameGap` |
| select actions (6) | `pieSelect pieUnSelect pieToggleSelect mapSelect mapUnSelect mapToggleSelect` | `select unselect toggleSelect` |
| select events (6) | `pieselected pieunselected pieselectchanged mapselected mapunselected mapselectchanged` | `selected unselected selectchanged` |
| sunburst actions (2) | `highlight`, `downplay` (sunburst-scoped) | `sunburstHighlight`, `sunburstUnhighlight` |
| custom renderItem (2) | `api.style()`, `api.styleEmphasis()` | `api.visual()` |
| format API (3) | `echarts.format.formatTime`, `echarts.number.parseDate`, `echarts.format.getTextRect` | `echarts.time.format`, `echarts.time.parse`, — |
| instance API (1) | `chart.one()` | `chart.on()` |
| dataZoom (1) | bare SVG path in `handleIcon` | `path://`-prefixed |
| treemap (2) | `colorMappingBy`, `treePathInfo` | `colorBy`, — |
| sunburst geometry (2) | `r`, `r0` | `radius` |
| misc (5) | `title.textBaseline`; `legend.symbolKeepAspect`; `dataZoom.dataBackgroundColor`; `dataZoom.handleColor`; `visualMap.color` (v2 form) | `textVerticalAlign`; —; `borderColor`; `handleStyle`; `inRange.color` |

**~64 distinct deprecated names.** A v5-targeted port would face exactly the same list — these are
all v5-era deprecations. **This is not a v5-vs-v6 differentiator**; it is a "don't copy from Stack
Overflow" list either way. If anything, a v5 target is *worse*: it would implement
`grid.containLabel` (deprecated in 6.0.0) as a first-class feature and have to unwind it later.

Source evidence for the still-live `@deprecated` option declarations (spot sample):
`src/chart/graph/GraphSeries.ts:171-173` (`focusNodeAdjacency`),
`src/chart/pie/PieSeries.ts:75-77` (`margin`),
`src/chart/sankey/SankeySeries.ts:133-135`,
`src/chart/sunburst/SunburstSeries.ts:103-109` (`r`, `r0`),
`src/chart/treemap/TreemapSeries.ts:83-111` (`treePathInfo`, `colorMappingBy`),
`src/component/legend/LegendModel.ts:123-125` (`symbolKeepAspect`),
`src/component/title/install.ts:71-73` (`textBaseline`),
`src/component/visualMap/VisualMapModel.ts:154-157` (`color`, "Option from version 2"),
`src/coord/radar/RadarModel.ts:57-59` (indicator `text`),
`src/chart/map/MapSeries.ts:106-107` (`geoCoord`).

### 6c. Internal API deprecations added in the 6.1.0 refactor

Not user-facing options, but they mark where the 6.1.0 axis-scale refactor moved:
`Axis.getBandWidth()` → `calcBandWidth()` (`src/coord/Axis.ts:250-252`); the number-precision helper
→ `getAcceptableTickPrecision` (`src/util/number.ts:311`); `axisCommonTypes.ts:296` `level` →
`time.level`. If the port transcribes axis math from 6.0.0 source it will transcribe the superseded
versions.

---

## 7. Doc quality of the v6-only subsystems

Measured, not impressionistic.

**Parity and hygiene**
- `en/option` = 127 `.md` files; `zh/option` = 127. Full translation parity.
- **0** `TODO`/`FIXME` markers across `en/option` + `en/api`.
- 102 `version = "6.x"` markers across 39 files (vs 210 `version = "5.x"` markers).

**Coverage spot-check.** I took 20 option keys named in the v6.0.0/v6.1.0 changelog entries and
grepped `en/option` for each: `jitter jitterOverlap jitterMargin containShape dataMin dataMax
outerBoundsMode outerBoundsContain outerBounds nameMoveOverlap roamTrigger preserveAspect relativeTo
unboundedRange displayTransition seriesTargets tangential-noflip cursorGrab stackOrder
coordinateSystemUsage` → **20/20 documented**. (The changelog's phrase "reversing the stack order"
resolves to `stackOrder`, `en/option/partial/stack.md:85`.)

**Per-subsystem, source-field vs documented-field:**

| Subsystem | Source fields | Documented | Page(s) |
|---|---|---|---|
| matrix | 8 top-level (`MatrixModel.ts:37-47`) + 5 dimension + 3 cell | **8/8, 5/5, 3/3** | `component/matrix.md` 150 lines + 3 partials 364 lines = 514 effective |
| axis breaks | `breaks` 4 sub-opts, `breakArea` 7, `breakLabelLayout` 1 (`axisCommonTypes.ts:132-144`) | **4/4, 7/7, 1/1** | ~250 lines inside `component/axis-common.md` (1497 lines, templated into every axis page) |
| thumbnail | 5 (`ThumbnailModel.ts:45-53`) | **5/5** | `component/thumbnail.md` 76 lines — the component genuinely only has 5 options |
| coordinateSystemUsage | — | 2 usage modes + per-series support matrix | `partial/coord-sys.md` 348 lines, included at **35 sites** |
| **chord** | see below | **6 defects** | `series/chord.md` 251 lines / 24 headings |
| *(reference)* line | — | — | `series/line.md` 519 lines / 41 headings |

**chord is the one weak page.** Six defects, verified field by field:

| Option | Source | Doc | Defect |
|---|---|---|---|
| `padAngle` | default **3** (`ChordSeries.ts:317`) | `## padAngle(number) = 0` (`chord.md:70`) | **wrong documented default** |
| `endAngle` | `ChordSeries.ts:135,315`, default `'auto'` | 0 mentions | undocumented |
| `edgeLabel` | `ChordSeries.ts:145` | 0 mentions | undocumented |
| `legendHoverLink` | `ChordSeries.ts:131,300` | 0 mentions | undocumented |
| `center` | `ChordSeries.ts:310`, default `['50%','50%']` | 0 mentions | undocumented |
| `colorBy` | `ChordSeries.ts:301` = `'data'` (global default is `'series'`, `globalDefault.ts:39`) | 0 mentions | undocumented series-specific override |

**Two more doc/source mismatches found outside chord** (both would bite a port that trusts the docs):

1. **`grid` default geometry is stale.** `en/option/component/grid.md:30-36` documents
   `left:'10%', top:60, right:'10%', bottom:60`. Source `GridModel.ts:129-132` is
   `left:'15%', top:65, right:'10%', bottom:80`. The docs still carry v5 grid geometry through the
   v6 default-layout change (B1).
2. **`grid.outerBoundsClampWidth` / `outerBoundsClampHeight` are undocumented.** Present at
   `GridModel.ts:137-138`; **0** files in `en/option` mention either.

Plus the `triggerLineEvent` version disagreement from §6a (docs 6.1.0, source 6.0.1).

**Verdict on doc quality:** matrix, axis breaks, thumbnail and `coordinateSystemUsage` are
production-grade — complete, exampled, and translated. Chord is a first-release page with one wrong
default and five missing options. **Read chord from `src/chart/chord/ChordSeries.ts`, not from the
docs.** That is the only v6 subsystem where the source must override the docs.

**Live demo coverage** (`D:/Projects/echarts/test/*.html`, 606 files): matrix **9**
(`matrix.html matrix2-4 matrix_application matrix_application2 matrix-label-formatter matrix-mbti scatterMatrix`),
axis-break **4**, chord **1**, thumbnail **1** (`graph-thumbnail.html`), scatter-jitter **1**.
The demo count tracks the doc quality — chord and thumbnail are the thin ones.

---

## 8. Is 6.x settled or moving?

| Release | Date | Gap |
|---|---|---|
| 5.0.0 | 2020-12-03 | — |
| 5.2.0 | 2021-09-01 | |
| 5.4.0 | 2022-09-25 | |
| 5.5.0 | 2024-02-18 | |
| 5.6.0 | 2024-12-28 | 314 d |
| **6.0.0** | **2025-07-30** | 214 d after 5.6.0 |
| **6.1.0** | **2026-05-18** | **292 d after 6.0.0** |

Today is 2026-09-01. **6.1.0 is ~3.5 months old and is the current head** (`package.json` = 6.1.0,
`zrender` dependency pinned to exactly `6.1.0`, and the local zrender checkout is also 6.1.0).

Three observations that qualify "settled":

1. **The changelog is not a complete release record.** It documents only 6.0.0 and 6.1.0 — no 6.0.x
   sections at all. But `src/chart/line/LineSeries.ts:132` carries `@since v6.0.1`, so at least one
   6.0.x patch shipped with a new option and never got a changelog section. Do not treat
   `en/changelog.md` as authoritative for patch-level behavior.
2. **v6 minors carry breaking changes** — 6.1.0 shipped 3 of them (§3), including a silent
   parameter-semantics change (`tooltip.valueFormatter`). This is not new: v5 minors did the same
   (5.2.0 has a `#### Break Changes` section at `changelog.md:484`; 5.5.0 has
   `[Break Change] change to default ESM package` at `changelog.md:193`). It is the project's normal
   cadence, not v6 instability.
3. **6.1.0 is unusually refactor-heavy.** Three `[Chore] [refactor]` entries (`changelog.md:64-67`):
   "Refactor axis scale implementation", "Unify series data union implementation", "Unify the roaming
   implementation". Axis math and roaming are still moving in the v6 line.
   **Transcribe axis scale code from 6.1.0, not 6.0.0.**

The 6.1.0 notes also carry a large `[Feature] [axis]` block — `dataMin`/`dataMax`, universal
no-overflow rendering, `containShape`, log-axis non-positive filtering, `axisLabel.formatter` index —
which is where the depth-first "finish cartesian properly" build order will spend most of its time.
That block is 6.1-only. A 6.0-based reading of cartesian would miss it.

---

## 9. Bottom line for `TTyAdvanceChart`

**Target ECharts 6.1.x specifically.** Reasons, ranked:

1. **The break surface costs a greenfield port nothing.** All 5 v6.0.0 breaks are compatibility
   escape hatches (`theme/v5.js`, `LegacyGridContainLabel`, `legacyViewCoordSysCenterBase`,
   `richInheritPlainLabel:false`, `outerBoundsMode:'none'`). Implement none of them. All 3 v6.1.0
   breaks are strictly-better behavior.
2. **Nothing was removed.** 0 series, 0 components, 0 actions, 0 events, 0 API methods. There is no
   capability a v5 target would have that a v6 target lacks.
3. **`src/visual/tokens.ts` is a gift.** A v6 target gets a 67-slot named-color + 8-step size token
   system with a paired dark plane, which is exactly ty-controls' tycss / `@mode` model. A v5 target
   gets hard-coded hex and would have to invent the mapping.
4. **The deprecation skip-list is v5-era and identical either way** (~64 names, all still shimmed in
   6.1.0). Targeting v5 would not shrink it; it would enlarge it.
5. **Maps are a wash on removals, a win on capability.** Neither version ships geoJSON
   (`upgrade-guide-v5.md:118`). But v6 adds `roamTrigger`, `preserveAspect`, `clip` on geo/map, the
   corrected `center` percent base, and the unified roaming implementation — all pure additions to
   the maps-in-scope path.

**Explicit skip-list for implementation (do not build these):**

`grid.containLabel` · `series-line.triggerLineEvent` · `tooltip.appendToBody` (DOM-bound anyway) ·
`legacyViewCoordSysCenterBase` · `richInheritPlainLabel` · `grid.outerBoundsMode:'none'` ·
`axis.containShape:false` · every name in the §6b left-hand column · the `theme/v5.js` palette
and layout.

**Explicit read-source-not-docs list:** `series/chord.md` (6 defects), `grid` default geometry
(`GridModel.ts:129-132`), `grid.outerBoundsClamp*` (undocumented), axis scale math (refactored in
6.1.0 after the docs were written).

**Pin the target version in the design-time editor's validator as `6.1`,** not `6`. The validator has
to encode chord `padAngle` default 3 (not the documented 0), `tooltip.valueFormatter`'s
`rawDataIndex` semantics, and `startValue`/`min` as independent — all three are 6.1-specific, and all
three are places where a "v6" mental model built from 6.0.0 material would be wrong.

---

## Appendix: evidence index

| Claim | Location |
|---|---|
| v6.0.0 `[Break]` block, 5 bullets | `echarts-doc/en/changelog.md:122-127` |
| v6.1.0 `[Break]` block, 3 bullets | `echarts-doc/en/changelog.md:69-72` |
| Release dates | `changelog.md:1-2` (6.1.0, 2026-05-18), `:74-75` (6.0.0, 2025-07-30), `:129-130` (5.6.0, 2024-12-28) |
| No v6 upgrade guide | `ls echarts-doc/en/tutorial/` = 26 files, only `upgrade-guide-v5.md` |
| v5 deprecation list | `echarts-doc/en/tutorial/upgrade-guide-v5.md:147-251` |
| Design tokens | `echarts/src/visual/tokens.ts:23-101` |
| v6 grid defaults | `echarts/src/coord/cartesian/GridModel.ts:129-138` |
| v6 legend defaults | `echarts/src/component/legend/LegendModel.ts:455-460` |
| v6 title defaults | `echarts/src/component/title/install.ts:117-118` |
| `containLabel` demotion | `echarts/src/coord/cartesian/Grid.ts:236-240`, `src/export/features.ts:25`, `src/echarts.all.ts:373` |
| `legacyViewCoordSysCenterBase` | `echarts/src/coord/View.ts:841`, `src/util/types.ts:806` |
| `richInheritPlainLabel` | `echarts/src/label/labelStyle.ts:428-431,539,631-632` |
| `containShape` | `echarts/src/coord/axisCommonTypes.ts:148` |
| Axis break option shape | `echarts/src/coord/axisCommonTypes.ts:132-144` |
| Chord defaults | `echarts/src/chart/chord/ChordSeries.ts:296-345` |
| Chord doc | `echarts-doc/en/option/series/chord.md:50-243` |
| `src/legacy/` | 2 files, 160 lines |
| Compat shims | `src/preprocessor/backwardCompat.ts`, `src/preprocessor/helper/compatStyle.ts`, `src/util/styleCompat.ts`, `src/chart/radar/backwardCompat.ts`, `src/coord/geo/fix/geoCoord.ts`, `src/coord/cartesian/legacyContainLabel.ts` |
| `@since v6.0.1` (undocumented patch) | `echarts/src/chart/line/LineSeries.ts:132` |
| Version pins | `echarts/package.json:3` = 6.1.0, `:77` zrender 6.1.0 |
