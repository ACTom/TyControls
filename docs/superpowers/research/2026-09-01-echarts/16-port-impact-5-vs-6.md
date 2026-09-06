# TTyAdvanceChart: what targeting ECharts 6 instead of ECharts 5 costs and buys

Scope: this report answers **only** the version-target question, given the maintainer's settled
decisions (new control, no `.lfm` compatibility, windowed `TTyCustomControl` base, option-tree API
with a validating design-time editor, maps in scope, depth-first build order).

Inputs read: `10-gap-analysis.md` §5 (the tiered roadmap) and §6 (Q1–Q10), `11-critique.md` in full,
`D:/Projects/echarts` 6.1.0 source, `D:/Projects/echarts-doc` (`en/changelog.md`, `en/option/**`,
`en/api/**`, `build/`), `D:/Projects/zrender` 6.1.0, and the ty-controls tree itself.

**Note on report 12:** it does not exist. The research directory contains `01`–`11` only, verified by
`ls` at the time of this pass. Nothing here depends on it; the v6-only inventory below was derived
from source and the doc version markers directly.

---

## 0. Method for "what is v6-only"

Three independent measurements, cross-checked:

1. **Version markers in the docs.** `{{ use: partial-version(version = "6.x") }}` appears **65 times**
   in `en/` — 60 at `6.0.0`, 5 at `6.1.0` — spread over 17 files. These are the individually-tagged
   v6 options.
2. **Whole documents that exist only in v6**: `en/option/component/matrix.md` (150 lines),
   `en/option/component/thumbnail.md` (76), `en/option/series/chord.md` (251), plus three matrix
   partials (`matrix-header.md` 144, `matrix-body-corner.md` 103, `matrix-region.md` 117).
   617 lines of option documentation, 58 own headings, before partial expansion.
3. **Changelog deltas.** v6.0.0 (2025-07-30) = 23 `[Feature]` + 22 `[Fix]` + a 5-item `[Break]` block.
   v6.1.0 (2026-05-18) = 14 `[Feature]` + 37 `[Fix]` + a 3-item `[Break]` block.
   Total v6 line: **37 features, 59 fixes, 2 breaking blocks over 2 releases**.

Source-side sizes are `wc -l` on `echarts/src`.

---

## 1. The v6-only roadmap delta

### 1.1 Whole roadmap items that vanish if you target v5

| Roadmap item | Tier (per §5) | Size | Dedicated v6 source | Evidence |
|---|---|---|---|---|
| `matrix` coordinate system (tree headers, locator algebra, merged cells) | 3 | **XL** | 2,677 lines — `src/coord/matrix/*` 2,190 (`Matrix.ts` 631, `MatrixDim.ts` 480, `matrixCoordHelper.ts` 378, `MatrixModel.ts` 361, `MatrixBodyCorner.ts` 292) + `src/component/matrix/*` 487 | changelog v6.0.0, "New matrix coordinate system" |
| `coordinateSystemUsage: 'box'` — coord systems and components nested in matrix/calendar cells | 3 | **XL** | `src/core/CoordinateSystem.ts` 360 (the two-kind resolution) + a changed rect contract at 19+ call sites | `CoordinateSystem.ts:174-278`; changelog v6.0.0, same entry |
| Axis breaks (piecewise domain, zigzag break area, expand/collapse actions) | 3 | **L** | 1,656 dedicated — `scale/breakImpl.ts` 785, `component/axis/axisBreakHelperImpl.ts` 572, `scale/break.ts` 178, `axisBreakHelper.ts` 91, `installBreak.ts` 30 — plus intrusions into `Time.ts`, `Interval.ts`, `Log.ts`, `AxisBuilder.ts`, `scaleMapper.ts` | changelog v6.0.0, "Support break on the axis"; 14 of `axis-common.md`'s 21 v6 markers |
| `thumbnail` mini-map with draggable viewport | 3 | **M** | 615 — `ThumbnailView.ts` 330, `ThumbnailModel.ts` 165, `ThumbnailBridgeImpl.ts` 93 | changelog v6.0.0; graph-only per `ThumbnailModel.ts:38` |
| `chord` series (ring layout, minAngle borrowing, ribbon geometry) | 2 | **M** | 1,200 — `ChordSeries.ts` 344, `chordLayout.ts` 272, `ChordEdge.ts` 211, `ChordPiece.ts` 188, `ChordView.ts` 153 | changelog v6.0.0, "New chord series" |

**Total removed by a v5 target: 2 XL + 1 L + 2 M — five items, ~6,100 dedicated source lines.**
All five are Tier 2 or Tier 3. **None is in Tier 0 or Tier 1.**

### 1.2 Correction to `10-gap-analysis.md` Q8

Q8 states: *"Targeting 5 removes four XL items from Tier 3."* It removes **two**. Tier 3's XL rows
are geo, matrix, `coordinateSystemUsage:'box'`, universal transition + shape morphing, and
`setOption`-style option-tree ingest. Of those:

- **geo** is v2-era, not v6.
- **universal transition + morphing** is **v5.0.0** — that changelog section (2020-12-03) lists
  "Support morphing/combining/separating by setting property `morph` on elements definitions",
  alongside `decal`, `labelLayout`, data transforms and `realtimeSort`. Both targets carry it.
- **option-tree ingest** is target-independent; it is an API-shape decision, now settled as yes.

Q8 over-counts the v5 saving by 2 XL.

### 1.3 v6-only sub-items that shrink an existing row rather than deleting it

| Sub-item | Row it lives in | Effect on that row | v6 source |
|---|---|---|---|
| `jitter` / `jitterOverlap` / `jitterMargin` (scatter only — critique #12) | Tier 2 "Axis extras \| M" | M, smaller | `util/jitter.ts` 184 + `chart/scatter/jitterLayout.ts` 105 |
| `dataMin` / `dataMax` (v6.1) — HEAVY-lite per critique #11 | Tier 2 "Axis extras \| M" | M, smaller | `scale/scaleMapper.ts` 506 (two-kind extent, `setExtent2`) |
| `containShape` + the matching `clip` options (v6.1) | Tier 2 "Axis extras \| M" | M, smaller | `coord/axisStatistics.ts` 501 + `axisStatisticsMetricsImpl.ts` 171 + `axisBand.ts` 209, consumed by 14 modules |
| `outerBounds` / `outerBoundsMode` / `outerBoundsContain` / `nameMoveOverlap` | **Tier 0** "Two-phase axis build \| L" | L stays L, +~276 lines of solver. v5's entire equivalent is `containLabel`, which v6 keeps as `legacyContainLabel.ts` — **120 lines** | 55 `outerBounds` references across 6 files |
| Design tokens (`src/visual/tokens.ts`) | **Tier 0** "New chart theme typeKeys + metric tokens \| M" | **no size change — a shape change** (see §4.2) | 233 lines, 64 colour keys + 8 size keys, 198 reference sites in 55 files |
| `registerCustomSeries` + `itemPayload` (critique #4, missing from §5) | Tier 2 "custom series as a Pascal event \| L" | **makes it cheaper** | `customSeriesRegister.ts` is a **12-line registry** |
| `roamTrigger`, `preserveAspect` ×3, `geo.clip`, scatter/effectScatter clip on geo | Tier 2 "View + RoamController \| L" | L stays L | part of `View.ts` 918 + `RoamController.ts` 588 + `roamHelper.ts` 212 |
| `visualMap.seriesTargets` (6.1), `unboundedRange` (6.0) | Tier 2 "visualMap \| L" | L stays L | — |
| `setTheme` / `registerTheme` dynamic theme switching (6.0) | — | **already free**: `TyController` does exactly this | `echarts.ts:827, 3051` |

### 1.4 The residue: ~25 S-sized option additions

Of the 37 v6 `[Feature]` entries, 5 are the whole subsystems above, 3 are infrastructure
(theme/tokens, roam unification, the cartesian anti-overflow layout), 3 are i18n translations
(Norwegian, Greek, Latvian — irrelevant to a native port), 1 is reusable custom series, 1 is dynamic
themes. The remaining **~25 are single-option additions**, each S, each absorbed into a row that
exists under both targets: `radar.clockwise`, `matrix.length`, `triggerEvent` on line/legend/matrix,
marker `z`/`z2`/`relativeTo`, reversible `stackOrder`, sankey roam, custom `compoundPath` /
`tooltipDisabled` / `layout`, `tooltip.displayTransition`, `gauge.progress.color:'auto'`,
pie `tangential-noflip`, `convertToLayout`, angleAxis label tooltip, `axisLabel.formatter` index,
`dataZoom.cursorGrab`/`cursorGrabbing`, candlestick `cursor`, and the three axis-break actions
(`expandAxisBreak` / `collapseAxisBreak` / `toggleAxisBreak`) + the `axisbreakchanged` event.

### 1.5 Bottom line on §1

**A v5 target removes 5 roadmap items (2 XL, 1 L, 2 M), shrinks 3 Tier-2 rows, trims one Tier-0 L by
roughly 150 lines of solver, and drops ~25 S-sized options. It removes nothing from Tier 0 or Tier 1
as a row.**

---

## 2. Items whose size changes because of the decisions already taken

### 2.1 No `.lfm` compatibility

**Deleted outright:**

- Tier 0 row *".lfm compatibility layer: `Values` as a lossless CSV projection + `DefineProperties`
  for the typed store"* — **M, gone.** With an option tree the persisted form is a JSON/text
  property. `TStrings` and `string` stream natively; `DefineProperties` is not needed at all.
  Precedent for the JSON side already exists in-tree: `source/tyControls.ThemeBundle.pas` uses
  `fpjson`, so no new dependency and no Q5 exposure.
- **Q3(i)–(iv) all collapse.** `'1,,3'` becomes `[1, NaN, 3]` by construction; unparseable text
  becomes NaN; `ShowLegend` / `ShowGrid` / `ShowValues` / `ShowTooltip` need not exist.
- **The 15 exported pure functions stop being a contract.** Verified count: the interface section of
  `source/tyControls.Chart.pas` declares exactly 15 — `TyChartNiceRange`, `TyChartValueToY`,
  `TyChartBarXRange`, `TyChartPieSweeps`, `TyChartLayoutFor`, `TyChartBarRect`, `TyChartPointCenter`,
  `TyChartNoHit`, `TyChartHitValid`, `TyChartBarHitTest`, `TyChartLineHitTest`, `TyChartPieHitTest`,
  `TyChartDonutHoleRadius`, `TyChartTooltipRect`, `TyChartDefaultTooltip`.
- **The test suite is not a constraint.** `tests/test.chart.pas` is 1,296 lines with **67** unique
  test procedures across `TChartTest` (line 21) and `TChartExportTest` (line 1119). §6 Q3 says "~60";
  the real number is 67. They do not have to be preserved, only re-derived — and repo memory
  `tests-that-pin-the-bug` applies: several pin present behaviour the new control deliberately
  changes.

**Saving: one Tier-0 M item, plus the four-part Q3 decision, plus the standing obligation to keep 15
signatures and 67 tests alive across a rewrite.** This saving is **identical under both version
targets**; it is not an argument either way.

### 2.2 Windowed base (`TTyCustomControl`)

Q1 is answered "yes", so:

- **Tier 0 row "Base-class decision and, if taken, migration + real-machine verification" — M,
  retained but de-risked.** The decision half is free; the cross-widgetset verification half is not.
- **Becomes possible at all** (§6 Q1: "focus and keyboard are simply unreachable" otherwise):
  Tier 3 "Keyboard navigation and MSAA/UIA accessibility | M".
- **Becomes cheaper** — these can now host or reuse real `TTyCustomControl` widgets instead of being
  self-drawn with hand-rolled hit-testing: Tier 1 "dataZoom: inside + slider widget | L", Tier 2
  "toolbox as a native strip | M", Tier 2 "brush … globalPan mutex | L", Tier 2 "timeline component
  | M", Tier 3 "thumbnail mini-map | M", Tier 3 "designtime editor dialog | L". `TTyScrollBar` is
  `TTyCustomControl` and can now be parented (report 10 §4.1 Evidence 7).
- **Becomes cheaper for a different reason** — Tier 3 "Dirty-rect / cached-surface painting | M":
  a windowed control's `Invalidate` no longer damages the parent's whole client area, which is the
  ~14.9 ms-per-repaint figure that drives Q7 and critique #6.
- **New costs, all real-machine, none target-dependent** (repo memory):
  `windowed-control-shadow-corners` (no shadows outside the control; `FillCornerGaps`),
  `windowed-ghost-erases-to-parent-color` (set `Color` to the theme surface in the paint path),
  `windowed-sibling-clipping-overhang` (overlap with windowed siblings is bitten flat, and `RenderTo`
  cannot detect it), `swallowed-cm-message-inherited` (any overridden `CM_*` must call `inherited`
  or a disabled-at-birth control never re-enables).

**None of this moves with the version target.**

### 2.3 Option-tree API

**Gets cheaper:**

- The implicit cost of Q2(a) — hand-declaring ~1,950 documented option paths as published properties
  and `TPersistent` sub-objects — **disappears entirely**. It was never a numbered roadmap row; it
  was the reason Q2 existed. Coverage now scales by writing a resolver and a catalog, not by writing
  1,950 declarations and their Object Inspector editors.
- ECharts documentation becomes usable as-is, and users can paste configs.
- **The validating editor has a working precedent in-tree.**
  `designtime/tyControls.Design.Css.Editor.pas` (351 lines, SynEdit) +
  `source/tyControls.Css.Complete.pas` (360) + `source/tyControls.Css.Catalog.pas` (411) =
  **1,122 lines** already deliver completion, reference lookup, warnings and syntax highlighting over
  the `.tycss` vocabulary. The chart-option editor is the same machine pointed at a different catalog.
- **The catalog can be generated, not hand-written.** `echarts-doc/build/build-doc.js:256-284` emits
  `documents/option.json` plus `option-outline.json` — a machine-readable option schema — and the
  docs carry **544 `<ExampleUIControl*>` annotations** across 10 widget types (Number 172,
  Boolean 138, Enum 93, Color 54, Percent 21, Angle 19, Vector 18, Icon 12, PercentVector 11,
  Text 6). Those are exactly the property-editor widget hints a validating editor needs. **And the
  `partial-version` markers survive into the generated doc** (`en/option/partial/version.md` renders
  "Since `v6.0.0`"), so one generator can emit either a v5-filtered or a full-v6 catalog.

**Gets more expensive:**

- **Merge semantics move from Tier 3 to Tier 0 and stay XL.** §5 lists "`setOption`-style option-tree
  ingest with normal/replace merge (only if §6 Q2 says yes) | XL" in Tier 3. Q2 now says yes, so it
  *is* the API and must exist first. ECharts' machinery: `src/model/Global.ts` 1,100 +
  `OptionManager.ts` 530 + `util/model.ts` 1,444 + `Component.ts` 396 + `Model.ts` 259 ≈ **3,729
  lines**, with `mappingToExists` (`util/model.ts:233-287`) carrying the three modes `normalMerge` /
  `replaceMerge` / `replaceAll`, id/name matching, and the deliberate **index holes** left after
  replace-merge removal. `replaceMerge` appears at 36 sites.
- **Validation is a new item, not a free one.** Type, enum, path and did-you-mean checking now have
  to be done by us at design time, because the compiler no longer does it. On the evidence of the
  1,122-line `.tycss` precedent scaled to ~1,950 paths: **M for the generated catalog, L for the
  editor.**
- **Callbacks-as-strings (Q6) becomes load-bearing rather than optional.** ~30 options are
  function-valued. In an option tree they cannot be `of object` pointers inline; they must be named
  handlers resolved through a registry. **This is where v6 helps**: `registerCustomSeries` (v6.0)
  plus `itemPayload` is exactly that shape — a *named, registered* renderer with a payload record
  instead of an inline closure — and it is a 12-line registry
  (`src/chart/custom/customSeriesRegister.ts`; `CustomView.ts:689` reads `itemPayload`).
  Critique #4 makes the same point from the other side.

**Net: the option-tree decision adds one XL (merge), one L (editor) and one M (catalog) to Tier 0,
and deletes an unbounded hand-declaration cost. Target-neutral, except that v6 supplies the one
registry shape the string-callback problem needs.**

### 2.4 Maps in scope

Q4 answered "in scope, important". §5's geo rows restated with sizes and source weight:

| Item | Tier | Size | v6 source |
|---|---|---|---|
| geo coordinate system: GeoJSON parse, region hit-test with holes, `nameMap`, `specialAreas`, `boundingCoords`, `layoutCenter`/`layoutSize`, region styling + selection | 3 | **XL** | `src/coord/geo/*` 2,590 **minus** `GeoSVGResource.ts` 373 (Tier X) **minus** `fix/*` 201 = 2,016, **plus** `src/component/geo/*` 272 → **2,288**. Core parse + region: `parseGeoJson.ts` 161 + `Region.ts` 337 |
| `map` series (`mapValueCalculation`, `showLegendSymbol`, choropleth) + a closed set of projections behind a Pascal interface | 3 | **L** | `src/chart/map/*` 839 |
| `View` coordinate system + `RoamController` (pan/zoom, `scaleLimit`, `roamTrigger`, `preserveAspect`, `nodeScaleRatio`) | 2 | **L** | 1,718 — `View.ts` 918, `RoamController.ts` 588, `roamHelper.ts` 212 |
| `lines` series (2-point + polyline, end symbols, moving `effect` marker) — the lines-on-geo case | 2 | **M** | `src/chart/lines/*` 866 |
| heatmap on geo (the density field: brush splatting + LUT recolour) | 3 | **M** | — |

**"Engine yes, atlas no" versus shipping data.** ECharts ships **zero** map geometry; §5 Tier X is
correct on that. Concretely:

- *Engine only*: cost is bounded by the table above. The price is that nothing renders out of the
  box, and the **design-time editor cannot preview a map** without a user-supplied GeoJSON.
  Mitigation is a `registerMap` equivalent plus one small demo geometry for the example — S.
- *Ship an atlas*: unbounded, and not merely a licensing question. `src/coord/geo/fix/` contains
  **118 lines of territorial-dispute special-casing** — `nanhai.ts` 73 and `diaoyuIsland.ts` 45 —
  plus `geoCoord.ts` 41 and `textCoord.ts` 42 of per-region label nudges. Shipping data means owning
  that file and the position it encodes, and maintaining it as borders move. Recommend: engine yes,
  atlas no, and say so on the tin.

**Version-target interaction — small but not zero.** v6 added `geo.clip` (6.1), scatter and
effectScatter `clip` on geo (6.1), `roamTrigger`, `preserveAspect` / `preserveAspectAlign` /
`preserveAspectVerticalAlign` (6.0), sankey roam (6.0), and changed the percent base of `center` on
`geo` / `map` / `graph` / `tree` (v6.0 `[Break]`, restorable via `legacyViewCoordSysCenterBase`,
present at `src/coord/View.ts:841`). The v6.1 changelog also records "Unify the roaming
implementation" as a refactor. A fresh port adopting the **unified** v6 roam contract is cheaper than
adopting v5's per-consumer roaming and unifying later. Worth roughly **one M of avoided rework**,
not more.

### 2.5 Depth-first: the first shippable milestone under each target

Milestone 1 depth-first = **Tier 0 + the cartesian slice of Tier 1**: line/bar/scatter, stacking, the
shared bar-width solver, axis anatomy, multiple axes, `interval:'auto'`, the time axis, legend,
tooltip, axisPointer, mark*, the label engine + de-collision, palette, animation, states, the event
payload record, dataZoom, `encode`/dataset, sampling, series clipping, export, loading.

Under the decisions, Tier 0 is **2 S + 8 M + 4 L + 1 XL** (the 16 §5 rows minus the deleted `.lfm` M),
**plus** the option-tree XL, the editor L and the catalog M.

Difference between targets inside that milestone:

| | v5 target | v6 target |
|---|---|---|
| Two-phase axis build | `containLabel` only — v6 keeps that whole path as `legacyContainLabel.ts`, **120 lines** | plus `outerBounds` / `outerBoundsMode` / `outerBoundsContain` (~276 lines in `Grid.ts`) and `nameMoveOverlap` (11 refs across `AxisBuilder.ts`, `axisCommonTypes.ts`, `Grid.ts`) |
| Theme tokens | per-component literal colours; the theme is an option-override tree | 64 colour + 8 size tokens with a semantic alias layer |
| Defaults | v5 defaults | v6 defaults — the diff is exactly `echarts/theme/v5.js`, **581 lines, 33 top-level keys** |
| Bar/candlestick edge overflow | allowed (v5 behaviour) | eliminated; `containShape` defaults true (v6.1 `[Break]`) |
| Scale extras | — | `dataMin` / `dataMax` (S–M), scatter `jitter` (S) |

**Every v6-only whole item is Tier 2 or Tier 3, so milestone 1 is target-insensitive in shape**: one
Tier-0 L grows modestly, three S's are added, and one table of default constants differs. That single
fact is what makes §5's third option viable.

---

## 3. The honest argument for v5

1. **Fewer XL items — but two, not four.** §1.2 corrects Q8. The saving is `matrix` and
   `coordinateSystemUsage:'box'`, plus 1 L (breaks) and 2 M (thumbnail, chord).
2. **v5 was the current version for 4 years 8 months** (v5.0.0 2020-12-03 → v6.0.0 2025-07-30) across
   **20 releases**, accumulating **118 features and 329 fixes**. v6 is **13 months old** at the date
   of this report, with **2 releases, 37 features, 59 fixes**.
3. **The v6 surface has broken in every release so far.** v6.0.0 carries a 5-item `[Break]` block
   against v5.6.0; v6.1.0 carries a 3-item `[Break]` block against v6.0.0 — and one of those
   (`tooltip.valueFormatter`'s 2nd parameter changing from `dataIndex` to `rawDataIndex`) is a
   *callback contract* change, the class most expensive to absorb in a port with a named-handler
   registry. The v5 line had **1** `[Break]` in 20 releases (v5.0.0 itself).
   **Ratio: 2 breaking blocks over 2 releases (v6) versus 1 over 20 (v5).**
4. **The v6-only subsystems are still churning.** Of v6.1.0's 37 fixes, at least 8 land on
   v6.0-introduced surface: matrix label formatter, chord's missing export entry, jitter vs
   progressive rendering plus an NPE, geo roaming sync and visual artifacts (the v6 roam
   unification), and the axis cluster — "Refactor axis scale implementation", "Fix and clarify
   `alignTick` strategy", uniform `bandWidth`, `axisPointer` shadow clipping. Porting a spec that is
   still moving means re-porting.
5. **Ecosystem.** This is the real v5 argument and it is not measurable from the local clones: four
   years and eight months of Stack Overflow answers, blog posts, corporate templates and third-party
   wrappers were written against v5. Anyone pasting a config into `TTyAdvanceChart` in 2026 is, on
   balance, more likely to be pasting v5.
6. **Demo surface.** Of the **606** `test/*.html` demos, only **16** exercise v6-only features
   (matrix 9, axis-break 4, chord 1, thumbnail 1, scatter-jitter 1) = **2.6 %**. Under a v5 target you
   still have 590 reference implementations to validate against; under a v6 target those 16 are your
   *only* reference for the five hardest new items.

**What the v5 argument is not.** It is not a code-maturity argument. ECharts 6.1.0 **contains** all
329 v5 fixes; v6 is v5 plus 37 features and 59 fixes. There is no "settled implementation" you obtain
by targeting v5 — you would be porting the same 6.1.0 source and choosing to skip parts of it.

---

## 4. The honest argument for v6

### 4.1 v5's option vocabulary is a strict subset — verified, not assumed

I looked for removals and found **none**. Across both v6 releases:

- **Zero options removed.** Two deprecations, both still functional: `grid.containLabel`
  (`grid.md:41`, deprecated in favour of `outerBoundsMode`, and v6 keeps the entire v5 code path as
  `src/coord/cartesian/legacyContainLabel.ts`, 120 lines) and `line.triggerLineEvent`
  (`line.md:105-116`, deprecated in 6.1 in favour of `triggerEvent`). Those are the only two
  `deprecated =` markers anywhere in `en/`.
- **The v6.0 `[Break]` block is 5 items and 4 carry an explicit restore switch**: the theme
  (`echarts/theme/v5.js`), `grid.outerBoundsMode: 'none'`, `axisLabel.nameMoveOverlap: false`,
  `legacyViewCoordSysCenterBase: true` (`src/coord/View.ts:841`), and `richInheritPlainLabel: false`
  (`src/label/labelStyle.ts:428-443`).
- **The v6.1 `[Break]` block is 3 items, 1 with a restore switch** (`axis.containShape: false`). The
  other two are semantic: `tooltip.valueFormatter`'s 2nd parameter, and `startValue` no longer
  implying `min`.

**Therefore targeting v6 does not cost you v5 option compatibility.** A v5 config pasted into a
v6-shaped control parses and renders. What differs is defaults and two callback contracts.

**And ECharts' own v5-compat shim is a theme.** `echarts/theme/v5.js` is 581 lines with 33 top-level
component/series keys. ty-controls has themes. "Give me the v5 look" is therefore **one `.tycss` skin
file**, not a target decision — and it lands in a mechanism the repo already has, already regenerates
(`gen-builtinthemes.ps1`) and already golden-tests across 15 built-in skins plus light and dark.

### 4.2 The design-token model maps onto `.tycss` structurally, not loosely

`src/visual/tokens.ts` (233 lines) is: a 9-colour `theme` palette, a 21-step `neutral00…neutral99`
ramp, a 19-step `accent05…accent95` ramp, then **24 semantic aliases** assigned by
`extend(color, {primary: neutral80, border: neutral30, background: neutral05, axisLine: neutral70,
axisSplitLine: neutral15, …})`, then **dark mode derived by formula** —
`modifyHSL(hex, null, s => s*0.9, l => 1 - l**1.5)` for neutrals, `s => s*0.5, l => min(1, 1.3 - l)`
for accents — plus 8 `size` tokens (xxs 2 … xxxl 50). 64 colour keys + 8 size keys, referenced at
**198 sites across 55 files**. Component defaults now read tokens rather than literals
(`src/coord/axisDefault.ts:65, 96, 109, 118-119, 126, 129, 206`).

`themes/light.tycss` is: 7 colour seeds + 1 metric, then a MAP layer of directional
`darken()`/`lighten()` derivations, then an ALIAS layer of `var()`/`alpha()`/`on()` semantics —
**176 tokens declared in `:root`, 192 distinct referenced** — with `@mode` for light/dark.

Same architecture: seeds → ramp → semantic alias → dark derived by transform. Adopting v6's names is
~72 additions to a 176-token vocabulary plus the matching `Css.Catalog.pas` entries — the Tier-0
"theme typeKeys + metric tokens | M" row, **unchanged in size**. Adopting v5's model instead makes
the chart's theme surface a per-component option-override tree, which is exactly the shape this repo
has been burned by three times (`variant-dies-under-skin-base-rule`,
`variant-only-rule-erases-control`, `skin-must-define-derived-tokens`). Report 10 §4.1 already says
the right thing — *"ECharts' v6 design-token table is a subset of what `.tycss` already does; the new
chart typeKeys should extend the existing system"* — and that sentence only parses against v6.

### 4.3 `coordinateSystemUsage` is the report-04 warning, and it is one function signature

Report 04 (lines 829-830): *"every coordinate system must accept an externally supplied rect instead
of always measuring against the canvas. **Cheap if designed in from the start, expensive to
retrofit.**"*

That is now measurable. In v6 the seam is `createBoxLayoutReference(model, api) → {refContainer, …}`
in `src/util/layout.ts` (776 lines), called from **19+ sites**: `title`, `legend`, `toolbox`,
`visualMap`, `dataZoom` slider, `timeline`, `thumbnail`, `Grid`, `treemap` (layout + breadcrumb),
`funnel`, `graph`'s `createView`, `sankey`, `tree`. In v5 every one of those measured against
`api.getWidth()` / `api.getHeight()`. The retrofit is: change all 19 call sites, plus each coordinate
system's rect derivation, plus the injection path (`src/core/CoordinateSystem.ts:196-278`, the
`COORD_SYS_USAGE_KIND_DATA` vs `_BOX` resolution and `injectCoordSysByOption`).

Designed in from the start it is: **the Tier-0 box-layout solver takes a rect provider instead of the
control's client rect.** One parameter. Near-zero.

### 4.4 The other v6 items that cut toward the port

- **`registerCustomSeries` + `itemPayload`** — a 12-line registry giving named, registered renderers
  with a payload record. That is the streamable, design-time-visible, catalogable shape Q6's
  string-callback problem needs. Under v5, `custom` is an inline `renderItem` closure and nothing
  else.
- **`setTheme` / `registerTheme`** (v6.0) — dynamic theme registration and switching. ty-controls
  already does this; under v5 there is no such API to be compatible with.
- **The v6.1 axis refactor** — `axisStatistics.ts` (501) + `axisStatisticsMetricsImpl.ts` (171) +
  `axisBand.ts` (209), consumed by 14 modules (boxplot, candlestick, bar on grid/polar, parallel,
  polar, radar, single, `scaleRawExtentInfo`), is what makes `containShape` and a uniform `bandWidth`
  across `value` / `time` / `log` axes possible. Building the port's scale layer on the v5 structure
  means rebuilding it later.
- **v6 is what will be current for the life of this port.** v5 ran over 4 years; on that cadence v7
  is not near. A control shipped in 2026 against a spec superseded in 2025 starts behind.

---

## 5. The third option: target the v6 option surface, phase the v6-only subsystems late

**Proposal:** build v6-shaped foundations — v6 tokens, v6 defaults, a coordinate-system and
box-layout interface that can nest, the v6 option names and the v6.1 callback semantics — and ship
matrix, chord, thumbnail and axis breaks last.

**Assessment: this is not a compromise. It is what §5's tiering already says, plus one Tier-0 design
constraint.** Evidence:

1. **All five v6-only whole items are already Tier 2 or Tier 3** (§1.1). Nothing has to be pulled
   forward and nothing has to be deferred beyond where the roadmap put it. chord (Tier 2 M) is the
   earliest, and it is a relational series that only makes sense after the Tier-2 substrate exists
   anyway.
2. **The v6 foundations are free or near-free at design time.** Tokens: same Tier-0 M row either way
   (§4.2). Defaults: a table of constants either way, and the diff becomes a `.tycss` skin (§4.1).
   Option names: identical work, since v5's names are a subset. The nestable rect contract: one
   parameter on the Tier-0 box-layout solver (§4.3).
3. **ECharts itself proves the phasing works.** It keeps the v5 `containLabel` path alive as
   `legacyContainLabel.ts` (120 lines) *beside* the v6 `outerBounds` solver. A port can implement the
   simpler `containLabel` clamp in Tier 0 and add the `outerBounds` refinement later without changing
   the two-phase structure — the structure is what matters, and it is the same one.
4. **The one thing that must not be phased** is §4.3's rect contract. If the Tier-0 box-layout solver
   and the coordinate-system interface are written against "the control's client rect",
   `coordinateSystemUsage:'box'` goes from XL to XL-plus-a-19-site-refactor, and calendar-hosted
   charts go with it.

**Risks, stated honestly:**

- **It buys the v6 label without the v6 features for a long time.** "Targets ECharts 6" while matrix,
  chord, thumbnail and breaks are all Tier 2/3 is a claim that will be tested. The honest public
  formulation is Q8's, versioned: *"the ECharts 6 option surface; matrix, chord, thumbnail and axis
  breaks are roadmap."*
- **The v6-only surface is the least-demoed part of ECharts** (16 of 606 demos, §3 item 6). When
  those items finally come up there is less to check against — and by then v6.2/v6.3 may have changed
  them, given 2 breaking blocks in 2 releases.
- **The two v6.1 semantic breaks must be absorbed now, not later**, because both touch contracts the
  option tree freezes: `tooltip.valueFormatter`'s `rawDataIndex` (the callback registry's parameter
  record) and `startValue`/`min` decoupling (the scale's extent model). Pick the v6.1 semantics on
  day one; they are far cheaper to adopt than to migrate.

---

## 6. Recommendation

**Target the ECharts 6.1 option surface. Take the v6 defaults, the v6 token model and the v6.1
callback semantics from day one. Leave matrix, `coordinateSystemUsage:'box'`, axis breaks, thumbnail
and chord exactly where §5 already put them (Tier 2/3).**

One line each:

- Targeting v5 saves **2 XL + 1 L + 2 M**, all Tier 2/3 — nothing you would build this year.
- Targeting v6 costs **~150 extra lines in one Tier-0 L** (`outerBounds` over `containLabel`),
  ~25 S-sized options, and one different table of default constants.
- v6 does not cost v5 compatibility: **zero options removed, two deprecated-but-working, and 4 of the
  5 v6.0 breaks carry restore switches.**
- The "v5 look" is **one `.tycss` skin** (581 lines / 33 keys in ECharts' own shim), not a target.
- v6's token model *is* `.tycss`'s model; v5's is the per-component override tree this repo has
  already been bitten by three times.
- `coordinateSystemUsage` is the report-04 retrofit warning made concrete: **one parameter now, a
  19-call-site refactor later.**

**Two things to decide alongside this, because the option-tree decision moved them into Tier 0:**

1. The merge semantics — `normalMerge` / `replaceMerge` / `replaceAll`, id/name matching, index
   holes. XL, and it is the API. ECharts spends ~3,729 lines on it.
2. The named-handler registry for the ~30 function-valued options (Q6), shaped like
   `registerCustomSeries` + `itemPayload`.

**Two corrections to carry back into `10-gap-analysis.md`:**

- §6 Q8: "removes four XL items" → **two** (matrix, `coordinateSystemUsage:'box'`). Universal
  transition/morphing is v5.0.0; geo is v2-era; the option-tree XL is target-independent.
- §6 Q3(iv): "~60 tests" → **67** unique test procedures in `tests/test.chart.pas` (1,296 lines),
  across `TChartTest` (line 21) and `TChartExportTest` (line 1119).
