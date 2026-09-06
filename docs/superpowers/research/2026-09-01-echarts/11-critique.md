# Completeness critique of reports 01–10

An adversarial review pass over the nine survey reports and the gap analysis, run against the
ECharts source and option docs. Findings below were applied to `10-gap-analysis.md` where marked
APPLIED; the rest stand as caveats on that document.

Two items were additionally re-verified by hand after the critique (see "Maintainer verification"
at the bottom).

---

Verified all ten reports against the source. The survey is unusually strong — 16 of 16 sampled numeric claims checked out, and every series type, coordinate system, component, and doc page maps to a matrix row. Findings below are the residue.

---

## HIGH

**1. zrender is never line-counted; the effort estimate omits the whole scene-graph layer.**
*Where:* `10-gap-analysis.md` §1.1 headline row ("plus a vendored zrender scene graph"), §3 closing line ("the remaining 85 % is the 138k lines"), §4.1 Evidence 1.
*Ground truth:* I parsed `D:/Projects/echarts/dist/echarts.esm.js.map` — 583 sources, of which **96 are zrender, 17,726 lines of transpiled JS** (TS source is larger). Largest: `Element.js` 1075, `canvas/Painter.js` 743, `animation/Animator.js` 737, `core/PathProxy.js` 712, `tool/parseSVG.js` 648, `tool/morphPath.js` 594, `graphic/helper/parseText.js` 552, `graphic/Text.js` 552, `tool/color.js` 429, `graphic/Path.js` 402, `core/BoundingRect.js` 331, `graphic/Displayable.js` 330, `tool/dividePath.js` 312, `contain/path.js` 307.
None of that is BGRABitmap-replaceable. BGRA gives a rasteriser; zrender gives a *retained element tree* with per-element bounding rects, per-shape `contain()`, an Animator/Track engine, a rich-text layout engine, and morph/divide. The matrix cites every one of these as a *prerequisite* (§2.6 morphing, §2.5 rich text, §2.7 hit test) but never as line count. The 596-file/138,362-line ratio and the "85 % is the 138k lines" framing both understate the port by ~13 % of *additional, entirely-must-be-written* code — and it is the hardest 13 %.
*Matters:* HIGH. It is the number the maintainer will size the project from.

**2. "The rasteriser is not the bottleneck" conflates BGRABitmap-the-library with TTyPainter-the-house-API.**
*Where:* §1.2 point 3 and §4.1 Evidence 1 ("reachable **today, with the current drawing stack**"), sourced from report 09 §4.5.
*Ground truth:* `source/tyControls.Painter.pas` — `TTyPainter`'s entire public surface is `BeginPaint/BeginPaintOn/EndPaint`, `Scale/Unscale`, `MeasureText`, `DrawText*` (incl. Bidi + Supersampled), `FillBackground`, `StrokeBorder`, `FillPointerShape`, `BlitRegion`, `DropShadow`, `GradientEndpoints`. **No paths, arcs, polylines, per-element clip, transforms, dash arrays, or per-element alpha.** `tyControls.Chart.pas` already reaches around it — 6 `Canvas2D` references and 3 raw `P.Bitmap.FillRect`.
The claim is true of BGRABitmap and false of the stack the library actually paints through. Consequence: **Tier 0 has no "painter vector API" item**, yet every Tier 1/Tier 2 series row depends on one. Going around `TTyPainter` per-series means each renderer re-implements DPI scaling, theme colour resolution, the bidi text path, and the non-Win supersampling gate (repo memory `bgra-small-text-blur-linux`) — which is exactly the class of bug this repo has paid for before.
*Matters:* HIGH. It is a missing Tier 0 foundation, and it is upstream of ~40 roadmap rows.

---

## MEDIUM

**3. `useUTC` has no matrix row and no roadmap line.**
*Where:* dropped between reports 01 §? / 04 (one mention each) and `10` §2.2 / §2.7 / Tier 1 time-axis row.
*Ground truth:* `echarts-doc/en/option/option.md:153` — root option, default `false`, switches every time getter to its UTC variant. `src/scale/Time.ts:31-39` documents the design rationale at length.
*Matters:* MEDIUM. FPC `TDateTime` carries no timezone, so this is a whole-stack design-time decision (parse + tick + format), not a knob added later.
Two smaller siblings, also with no row: root `option.backgroundColor` (only the *export* override appears, §2.8) and root `option.textStyle` (the global default every component inherits).

**4. `registerCustomSeries` + `itemPayload` (v6.0) is missing from the matrix and roadmap.**
*Where:* §2.1.10 has `custom: renderItem(params, api) | BROWSER-BOUND as a JS API`; §2.7's registry row lists "CustomSeries" but not this API.
*Ground truth:* `echarts-doc/en/api/echarts.md` `## registerCustomSeries(Function)`, tagged `partial-version(version: '6.0.0')`; `src/chart/custom/CustomView.ts:689` reads `itemPayload`.
*Matters:* MEDIUM, and it cuts *toward* the port. This is the v6 form: a **named, registered** renderer plus a payload record, instead of an inline closure. That is precisely the `.lfm`-streamable, designtime-visible shape Q6 is asking about, and it makes `custom` considerably less blocked than "BROWSER-BOUND as a JS API" implies.

**5. BROWSER-BOUND is applied to ~10 of 41 rows purely for being function-valued — contradicting §3 item 9.**
*Where:* §2.1.1 L120 (labelLayout/formatter/symbolSize/symbol/color callbacks), §2.1.8 L263 (sunburst `sort` comparator), L267 (funnel), §2.1.10 L361 (renderItem), §2.3 L486 (async tooltip formatter), L569 (graphic `on*`), §2.5 L655 ("BROWSER-BOUND naming"), §2.2 L426 ("payloads BROWSER-BOUND-shaped").
§3 item 9 says these are "a design decision, not a blocker". BROWSER-BOUND is defined as DOM/CSS/SVG/WebGL-dependent, and it is the class Tier X quotes to justify exclusions — so labelling callbacks with it inflates the apparent out-of-scope surface by about a quarter of that class.
*Fix:* a fourth class (API-SHAPE) or reclassify as NATURAL-with-note.

**6. Dirty-rect / layered painting is filed in three contradictory places.**
Tier X: `useDirtyRect` / `hoverLayerThreshold` / `zlevel`-as-a-layer → not doing, "cargo cult". Tier 3: "Dirty-rect / cached-surface painting (`TTyPaintCache`, remembering the `pf24bit` rule) | M". Q7(c): floats it as a **Tier 0** item.
This is also the one axis where the native side is *worse* than the browser: report 09's own ~23 ns/px → ~14.9 ms per full 900×700 repaint means a BGRA chart cannot animate without layering, whereas canvas2d animates fine without it. Tier X's phrasing reads as a rejection of the mechanism, not just of the public option. Pick one placement.

**7. `large` mode is classed NATURAL with no measurement behind it.**
*Where:* §2.1.1, §2.1.3, §2.1.5, §2.4 ("More natural on BGRA than in the DOM").
ECharts' `large` path is N `ctx.rect` calls into one GPU-composited fill; BGRA's equivalent is a CPU antialiased polygon scan over N subpaths. Every other load-bearing claim in the document is measured (23 ns/px, 1,721 lines, 138k lines) — this one is asserted. A 20-line spike (100k rects into one `TBGRACanvas2D` path, timed) should precede sizing it.

**8. `dataZoom` matrix rows only ever name `xAxisIndex`/`yAxisIndex`.**
*Ground truth:* `src/component/dataZoom/DataZoomModel.ts:60,62,65` and `helper.ts:58` — `radiusAxisIndex`, `angleAxisIndex`, `singleAxisIndex` are first-class; documented at `en/option/component/data-zoom.md:183,191`. Report 05 has them; §2.3 and Tier 1's "dataZoom | L" dropped them, which under-scopes the item (zoom on polar and single is a different clamp path).

---

## LOW

**9. Locale count contradicts itself and the source.** §2.2 says "27 locale month/weekday tables"; §2.7 says "26 shipped locales". `ls src/i18n` = **27**; EN and ZH are pre-registered at `src/core/locale.ts:80-81`.

**10. `extension-src/` was never enumerated.** It contains exactly two shipped extensions: `bmap` (correctly excluded in Tier X) and **`dataTool`** — a GEXF graph-file parser plus `prepareBoxplotData`. The boxplot half is covered as a transform; the GEXF parser appears nowhere. Trivial in size; it is the only unaccounted item in the extension question.

**11. `scaleMapper.ts`'s two-kind extent model is never named, and `dataMin`/`dataMax` is probably misclassified.** `src/scale/scaleMapper.ts` introduces `SCALE_EXTENT_KIND_EFFECTIVE` vs `..._MAPPING` and `setExtent2`. §2.2 classes `dataMin`/`dataMax` (v6.1) as **NATURAL**, but the mechanism is a *second* extent that interacts with dataZoom-controlled ends, `clampData` and breaks. HEAVY-lite, not NATURAL.

**12. Jitter row overstates scope.** §2.2 lists `jitter`/`jitterOverlap`/`jitterMargin` as axis-level (correct — `axis-common.md:47-67`), but only **scatter** registers the layout (`src/chart/scatter/install.ts:39`, `jitterLayout.ts`; `src/util/jitter.ts` is generic but unused elsewhere). The item is smaller than the row implies.

---

## Genuinely well covered — no findings

- **Series inventory.** All 23 (`src/export/charts.ts` = 23 installs; 22 dirs + `pictorialBar.ts`) have matrix rows, including all v6 additions.
- **Coordinate systems and scales.** All 9 registered systems (verified by `grep registerCoordinateSystem`: cartesian2d, polar, geo, single, parallel, radar, calendar, matrix, graphView) and 4/4 scale classes covered; `View`, breaks, `axisAlignTicks`, `axisStatistics` all present.
- **Components.** All 24 dirs under `src/component`, all 35 pages in `en/option/component`, all 24 in `en/option/series` map to rows.
- **API.** All 24 `echarts-instance` methods and 12/12 global `echarts.*` covered, except finding #4.
- **v6 specifics.** chord, matrix, thumbnail (correctly noted graph-only per `ThumbnailModel.ts:38`), axis breaks, jitter, design tokens (`src/visual/tokens.ts`, report 07 §2.6), `coordinateSystemUsage:'box'`, `outerBounds`, `nameMoveOverlap`, `unboundedRange`, `preserveAspect`, `*Id` finders, `containShape`, `radar.clockwise`, `matrix.length`, `cursorGrab` — all present.
- **Fact-check, 16/16 correct.** 596 files / 138,362 lines; 606 `test/*.html`; 31 easings (extracted from the bundled `animation/easing.js`); 12-entry `scaleIntervals` (`Time.ts:285-300`); `axis-common.md` = 1,497 lines; visualMap `[0,200]` (`VisualMapModel.ts:678`); `barCategoryGap max(35−4n,15)%` (`barGrid.ts:262`); minorTick 5/3 (`axisDefault.ts:192-194`); line symbolSize 6 / scatter 10 + opacity 0.8 / markPoint 50; `Z2_EMPHASIS_LIFT` 10, `Z2_SELECT_LIFT` 9 (`states.ts:85`); squareRatio = golden ratio; `nodeScaleRatio` 0.4; `layoutIterations` 32; friction `×0.992`, converge `<0.01` (`forceHelper.ts:218,220`); 8 `focus` values (3 default + adjacency/trajectory/ancestor/descendant/relative); 9-colour v6 palette; 24 instance methods.
- **ty-controls side.** Verified 5-tick target, `'0.###'`, 8/400 labels, margin 8, `TyChartDonutHolePercent = 55`, and that `--chart-donut-hole` / `--chart-hit-radius` really are declared in `tyControls.Chart.pas:86-87` and defined in **no** `.tycss` and no catalog entry — §4.2 item 4 is correct.
---

## Maintainer verification (hand-checked, 2026-09-01)

**Finding 1 — zrender line count. CONFIRMED, and now measurable at source level.**
`git clone --depth 1 https://github.com/ecomfe/zrender` → `D:/Projects/zrender`.
`find src -name '*.ts' | xargs wc -l` = **31,477 lines of TypeScript** (the critique's 17,726 is the
*transpiled* JS in the bundle, so it understates). Key modules by size:

| module | lines | why it matters for a native port |
|---|---|---|
| `src/Element.ts` | 2,172 | the retained element tree — transforms, states, per-element animation |
| `src/canvas/Painter.ts` | 1,347 | layer management, dirty rect, repaint scheduling |
| `src/animation/Animator.ts` | 1,148 | the track/keyframe engine every animation option rests on |
| `src/core/PathProxy.ts` | 1,009 | the retained path command buffer + bounding-rect computation |
| `src/tool/parseSVG.ts` | 965 | SVG *document* parsing (Tier X) |
| `src/graphic/helper/parseText.ts` | 951 | the rich-text layout engine |
| `src/tool/morphPath.ts` | 894 | shape morphing for universal transition |
| `src/contain/path.ts` | 408 | per-shape `contain()` — the hit-test inverse |

**True total for the stack: 138,362 (echarts/src) + 31,477 (zrender/src) = ~169,800 lines of TS.**
BGRABitmap replaces the *rasteriser* only; `Element` / `PathProxy` / `Animator` / `parseText` /
`contain` have no equivalent anywhere in ty-controls and must be written.

**Finding 2 — TTyPainter vs BGRABitmap. CONFIRMED.**
`TTyPainter`'s public surface (`source/tyControls.Painter.pas:123-232`) is chrome-shaped:
`BeginPaint`/`BeginPaintOn`/`EndPaint`, `Scale`/`Unscale`, `MeasureText`, `DrawText`/`DrawTextLine`/
`DrawTextLineBidi`/`DrawTextSupersampled`, `FillBackground`, `StrokeBorder`, `FillPointerShape`,
`DrawEdge`, `DrawGlyph*`, `DropShadow`, `NineSlice`, `DrawImageFill`, `FillGlass`, `FillCornerGaps`,
`EraseRect`, `StarPath`/`DrawStar`. **No general path, arc, polyline, transform, clip, dash or
per-element alpha.** It escapes only through `property Bitmap: TBGRABitmap` (line 225), which
`tyControls.Chart.pas` already uses (`P.Bitmap.Canvas2D`, lines 1407 and 1529).

So the *capability* claim is true and the *stack* claim was not: a vector API on `TTyPainter` is a
missing **Tier 0** item, upstream of roughly forty roadmap rows.

**Bonus — Q5's SVG-path risk is resolved, and the answer is favourable.**
`bgrapath.pas:2301` accepts `['L','H','V','C','S','Q','T','A']` (plus `M`/`m` and `Z`/`z`, relative
forms handled by `upcase(command)` at 2303), and `'A'` at 2400-2410 dispatches to the full elliptical
`arcTo(rx, ry, xAngleRadCW, largeArc, anticlockwise, x, y)`. **The complete SVG path grammar is
supported**, so `path://` custom symbols need no parser of our own, and no dependency. Q5 loses one of
its three items.
