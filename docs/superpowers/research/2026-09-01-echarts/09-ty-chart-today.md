# TTyChart today — inventory for the ECharts comparison

Source of truth read in full: `source/tyControls.Chart.pas` (1721 lines), `docs/controls/chart.md`,
`tests/test.chart.pas` (1296 lines), `examples/chart/umain.pas` + `.lfm`, `designtime/tyControls.Design.pas`.
Context skimmed: `tyControls.Painter.pas`, `tyControls.StyleModel.pas`, `tyControls.Controller.pas`,
`tyControls.Base.pas`, `tyControls.Grid.pas`, `tyControls.Sparkline.pas`, `themes/light.tycss`,
BGRABitmap **11.6.6** (`bgracanvas2d.pas`, `bgracustombitmap.inc`).

---

## 1. What TTyChart is today

### 1.1 Class shape

| item | value |
|---|---|
| unit | `tyControls.Chart` |
| class | `TTyChart = class(TTyGraphicControl)` — **graphic control, no window handle, cannot be a parent** |
| `GetStyleTypeKey` | `'TyChart'` (own key; tooltip uses `'TyChartTooltip'`; palette uses `'TyChartSeries1'..'8'`) |
| default size | 260 × 180 logical px, set in the constructor |
| paint entry | `Paint` → `RenderTo(Canvas, ClientRect, Font.PixelsPerInch)` |
| registration | `RegisterClass(TTyChart)` in `initialization` |
| palette group | `RegisterComponents('TyControls Shapes & Charts', [TTyShape, TTyStarShape, TTyArrow, TTyChart])` |

### 1.2 Published properties (complete)

Own: `ChartType: TTyChartType` (default `ctLine`), `Series: TTyChartSeries`, `Categories: TStrings`,
`Title: TCaption`, `ShowLegend: Boolean` (True), `ShowGrid: Boolean` (True), `ShowValues: Boolean` (False),
`ShowTooltip: Boolean` (True), `OnGetTooltip: TTyChartTooltipEvent`.

Re-published from the base: `Align`, `Anchors`, `Font`, `StyleClass`, `StyleOverride`, `Controller`.
(`TTyGraphicControl` already publishes `Enabled`/`Visible`/`Hint`/`ShowHint`/`PopupMenu`/`Constraints`/
`BorderSpacing`/`Cursor`/`Action` and the full mouse/drag event set, so those come for free.)

**That is the entire published surface: 9 own properties.** There is no axis object, no per-series type,
no per-series axis, no data-zoom, no animation, no toolbox, no `Options`/JSON ingest.

### 1.3 Public methods

- `function HitTestAt(X, Y: Integer): TTyChartHit` — the same answer the tooltip uses (click-to-drill).
- Export, 6 overloads: `SaveToStream(AStream, AFormat)`, `SaveToStream(AStream, AFormat, W, H)`,
  `SaveToFile(name)`, `SaveToFile(name, W, H)`, `SaveToFile(name, AFormat)`, `SaveToFile(name, AFormat, W, H)`.
  `AFormat` is BGRABitmap's `TBGRAImageFormat` (`ifPng`/`ifJpeg`/`ifBmp`/`ifTiff`…). The unit `uses BGRAWriteTiff`
  purely to register a TIFF backend. Core is `RenderExportBitmap` → renders into a `pf32bit` `TBitmap` via
  `RenderTo`, wraps in `TBGRABitmap`, then `AlphaFill(255)` (GDI never writes the alpha plane — without this
  the PNG exports fully transparent). Size-less overloads use the control's size; sized overloads re-lay-out
  at W×H but keep the control's PPI for text.

### 1.4 Types exported by the unit

`TDoubleArray = array of Double`; `TDoubleArrayArray = array of TDoubleArray`;
`TTyChartType = (ctLine, ctBar, ctPie, ctDonut)` — `ctDonut` **appended** so streamed `.lfm` ordinals survive;
`TTyChartPieSlice = record StartDeg, SweepDeg: Double end` + `TTyChartPieSliceArray`;
`TTyChartHit = record SeriesIndex, PointIndex: Integer end` (both −1 = nothing, decided only by `TyChartHitValid`);
`TTyChartLayout = record Plot, PieArea, Legend: TRect end` (device px, control-relative);
`TTyChartSeriesItem = class(TCollectionItem)`; `TTyChartSeries = class(TCollection)`;
`TTyChartTooltipEvent = procedure(Sender; ASeries, APoint: Integer; var AText: string) of object`.

Pure interface-level functions (the headless-testable seam): `TyChartNiceRange`, `TyChartValueToY`,
`TyChartBarXRange`, `TyChartPieSweeps`, `TyChartLayoutFor`, `TyChartBarRect`, `TyChartPointCenter`,
`TyChartNoHit`, `TyChartHitValid`, `TyChartBarHitTest`, `TyChartLineHitTest`, `TyChartPieHitTest`,
`TyChartDonutHoleRadius`, `TyChartTooltipRect`, `TyChartDefaultTooltip`.

### 1.5 The data model — **this is the biggest single constraint**

`TTyChartSeriesItem` publishes exactly three properties:

```pascal
property Name: string;
property Color: TColor default clDefault;   // clDefault -> palette slot (index mod 8)
property Values: string;                    // <<< A COMMA-SEPARATED STRING
function ValueArray: TDoubleArray;          // parses it, every call, no cache
```

`Values` is a **`string`**, not a numeric collection. `ParseValues` (unit-private) does:
`TStringList` with `StrictDelimiter := True`, `Delimiter := ','`, `DelimitedText := AText`; each part is
`Trim`-ed, **blank parts are skipped entirely** (so `'1,,3'` yields 2 values, not 3 — there is **no null/NaN
representation**), and each is `StrToFloatDef(part, 0, fs)` with `fs.DecimalSeparator := '.'`,
`fs.ThousandSeparator := #0`. **Unparseable text silently becomes 0.0**, indistinguishable from a real zero.

Consequences that matter for any ECharts-style expansion:
- Categorical X only. A point is `(categoryIndex, value)`. **There are no (x, y) pairs**, so scatter,
  bubble, time axis, log axis, irregular sampling and value-typed X are all unrepresentable today.
- No missing-value token, no per-point metadata (no per-point colour, label, symbol, tooltip payload).
- `ValueArray` re-parses the string on **every** call — and `DataExtent`, `AxesData`, the paint loop, the
  hit-test and the tooltip each call it. A single mouse-move over a bar chart re-parses every series
  several times. There is no cache and no dirty flag; this is an O(n·series) allocation per frame.
- `Categories: TStrings` is a plain `TStringList` with `OnChange` wired to invalidate.
- Category count = `max(longest series length, Categories.Count)`, floored at 1 (`AxesData`).
- `DataExtent` scans every series, **but `Break`s after the first series when `ChartType in [ctPie, ctDonut]`**
  — radial charts plot series 0 only.

`TTyChartSeries` is a plain `TCollection` (owner = the chart) with `OnChange` fired from both `Notify` and
`Update`; the chart's handler clears the parked hover hit and invalidates.

### 1.6 Chart types and their geometry

- `ctLine` — one polyline per series (`ctx.lineJoin := 'round'`, `lineWidth := P.Scale(2)`) plus a filled
  `ctx.arc(..., P.Scale(3), 0, 2*Pi)` marker at each vertex. Markers sit at the **centre of the category slot**.
- `ctBar` — grouped/side-by-side multi-series. Two nested `TyChartBarXRange` splits: plot → category slot →
  one bar per series; each level insets 15 % per side (min 1 px), so groups and bars can never overlap.
  Bars span the **zero baseline** to the value; negatives hang below; a zero value gives a zero-height
  (empty) rect that draws nothing and hits nothing. **No stacking, no horizontal bars.**
- `ctPie` / `ctDonut` — one path for both (a pie is the `hole = 0` case): out along the start edge, outer
  `arc`, in along the end edge, inner `arc` reversed, `closePath`, `fill`, then a `P.Scale(1)` stroke in the
  **surface colour** as the separator (which also rims the donut hole). The hole is *not filled* — the panel
  background shows through, so image themes show the photo in the hole.

### 1.7 Layout algorithm

`LayoutFor(W, H, PPI)` scales five hard-coded logical constants with `MulDiv(x, APPI, 96)` and hands them to the
pure `TyChartLayoutFor`:

| band | logical px | note |
|---|---|---|
| outer margin | 8 | all four sides |
| title height | 20 | 0 when `Title = ''` |
| legend strip | 18 | bottom; only when `ShowLegend` |
| Y tick gutter | 38 | left of plot, axes charts only |
| X label band | 16 | under plot, axes charts only |

`TyChartLayoutFor` then: `topY = margin + titleH`; `botY = H - margin - legendH`; `contentR = W - margin`.
Radial → `PieArea = (margin, topY, contentR, botY)`. Axes → `Plot = (margin + yAxisW, topY + margin,
contentR, botY - xAxisH)` (a **second** margin under the title so the top gridline/label has air).
Legend spans the full content width for radial, starts at the plot's left edge for axes. **Any band that would
come out empty or inverted is returned as an empty rect** — the caller tests one rect instead of re-deriving
arithmetic. Both paint and hit-test call it, which is what keeps pointer and pixels agreeing.

The five band sizes are **literals in `LayoutFor`, not theme metrics** — the only part of the control that
breaks the token rule (see §3.2). There is no measurement-driven gutter: a 6-digit tick label overflows the
38 px gutter, and a long category label overflows the 16 px band.

Y scale: `TyChartNiceRange(min, max, 5, …)` — Heckbert nice-numbers, step snapped to {1,2,5}×10^k via the
private `NiceNum`, guaranteeing `niceMin <= min`, `niceMax >= max`, `step > 0`; degenerate input expands to a
unit span. `AxesData` forces the zero baseline in (`if dMin > 0 then dMin := 0; if dMax < 0 then dMax := 0`).
`TyChartValueToY` is linear only. **Target tick count is hard-coded 5. No secondary axis, no log axis,
no inverted axis, no manual min/max.**

### 1.8 Hit-testing

- `TyChartBarHitTest` — literally scans `TyChartBarRect`'s own rects, half-open on both axes, first
  containing rect wins (bars never overlap). Zero-value bars are unhittable by construction.
- `TyChartLineHitTest` — Euclidean grab radius (squared-distance compare, no `Sqrt`), nearest marker wins,
  ties go to the **lower** series index (stable). Tolerance ≤ 0 grabs nothing. Radius from
  `--chart-hit-radius` (default 12 logical px), scaled by PPI.
- `TyChartPieHitTest` — exact inverse of `DrawPie`: `ArcTan2(dy,dx)` in screen space + 90°, normalised to
  [0,360). Returns −1 outside the disc, **inside the donut hole**, or in a zero-sweep slice.
- `HitTestAt` re-derives the layout from `ClientWidth/ClientHeight` and `Font.PixelsPerInch` and dispatches.
  Radial always answers `SeriesIndex = 0` (one series per pie).

Hover state: `FHoverHit`, set only from `MouseMove`/`MouseLeave`. `MouseMove` repaints **only when the datum
changes**, not per pixel (the whole chart re-renders from scratch each paint). `ClearHover` runs on
`ChartType`/`Series`/`Categories` change. The paint path **re-validates** the parked hit against live data
before drawing, because a series can shrink under a stationary pointer.

### 1.9 Tooltip

Painted **into the chart's own bitmap** as the last layer — deliberately *not* an LCL `THintWindow` (docs §9
gives three reasons: per-datum text the hint timer can't express; a separate top-level window that shadows
outside the chart, steals activation and hits the Wayland popup traps; and an in-bitmap box gets themed and
clamped with the chart). Cost: **the tooltip can never leave the control's bounds.**

- Text from `TyChartDefaultTooltip(category, seriesName, value, percent)` — line 0 = category (omitted if
  empty), line 1 = `'<series>: <value>'` (prefix omitted if the name is empty), `' (NN.N%)'` appended when
  `percent >= 0`. Format `'0.###'` with `'.'` separator, no thousands grouping — **deliberately the same
  format as the axis tick labels and deliberately not locale-following.** Pie/donut pass a real percent,
  axes charts pass −1.
- `OnGetTooltip` fires **last**; clearing `AText` suppresses that one datum's tooltip.
- Anchor: bar → top-centre of the bar rect; line → the marker centre; pie/donut → the slice's mid-arc at
  `hole + (radius-hole)/2` (middle of the ring).
- `TyChartTooltipRect` — prefers up-and-right by `gap`; **flips first, clamps second**; an oversized box is
  pinned inside, never hidden (`TestTooltipRectOversizedIsPinnedNotHidden`).
- `DrawTooltip` resolves `'TyChartTooltip'` with the **chart's** `StyleClass` so `TyChartTooltip.compact`
  follows `TyChart.compact`. It paints its own surface with `DropShadow`/`FillBackground`/`StrokeBorder`
  and **must not call `DrawFrame`** — `DrawFrame` pushes `tpOpacity` onto the painter and `EndPaint` applies
  that to the *whole* bitmap, so a tooltip opacity would fade the entire chart.
- Line height comes from measuring the reference glyph `'Ag'` so every line is the same height.

### 1.10 Legend

`DrawLegend` — single horizontal strip, left-to-right, 10 px swatch + 4 px gap + measured text + 14+6 px
trailing gap, `Break`s when `x > ARect.Right`. Radial legends list **categories** (= slices); axes legends
list **series**. Font is a literal `9/400` with the control's `Font.Name`.
**No wrapping, no scrolling, no positioning (top/left/right), no click-to-toggle-series, no selection state.**

### 1.11 Theming tokens actually in play

| key / token | where | note |
|---|---|---|
| `TyChart` | frame, title, legend text, tick labels, axis lines, gridlines | own typeKey; joined into the shared `TyPanel, TyScrollBox, TyExPanel, TyChart, …` rule block in every theme + `DefaultTheme.pas` |
| `TyChartTooltip` | tooltip box | `background`/`border-*`/`color`/`padding`/`font-*`/`shadow`; **absent background = no box drawn** (graceful, never a hard-coded colour) |
| `TyChartSeries1..8` | series/slice ink | **these exist now** in `themes/light.tycss` (Tableau-10 hues) — `docs/controls/chart.md` §2 still says they are "deliberately deferred / do not exist"; **the doc is stale** |
| `--chart-tooltip-gap` (10), `--chart-tooltip-swatch` (8), `--chart-tooltip-swatch-gap` (5) | tooltip metrics | defined in `themes/light.tycss` **and** listed in `tyControls.Css.Catalog.pas`, guarded by `tests/test.themes.pas` |
| `--chart-donut-hole` (55 **percent**), `--chart-hit-radius` (12) | donut hole, line grab radius | read via `ActiveController.Metric` **but defined in no theme and absent from the CSS catalog** — code-only fallbacks. Donut hole is the library's only non-length metric (clamped to `TyChartDonutHoleMaxPercent = 90`). |

Colour resolution: `PaletteColor(i)` resolves `'TyChartSeries' + IntToStr(i mod 8 + 1)` and falls back to the
const `TyChartPalette` (Tableau-10, `$00BBGGRR`) only if the resolved style has no background or alpha 0.
`SeriesColor` = the item's `Color` unless `clDefault`. `SliceColor` = palette-by-slice. Legend, tooltip swatch,
bars, lines and slices all go through these two, so they cannot disagree.

**Hard-coded visual values that are NOT tokens** (the real theming gaps): grid line alpha `70`;
title `11/700`; legend `9/400`; tick and value labels `8/400`; all of them use `Font.Name`, not the style's
`font-name`; the five layout band sizes; the bar inset 15 %; the marker radius 3; the line width 2; the
label offsets (`Scale(14)`, `Scale(16)`…); the pie label at 60 % of ring thickness.

### 1.12 Tests

`tests/test.chart.pas` — 2 fixtures, ~60 published cases, registered in `tests/tytests.lpr` (console
`consoletestrunner`; 284 test units in the suite).
- `TChartTest` **never instantiates TTyChart** — it exercises only the interface-exported pure functions.
  Hit-test cases are written as **round trips through the paint's own geometry** (probe the centre of the rect
  `TyChartBarRect` drew, the exact `TyChartPointCenter` point, the mid-arc of the `TyChartPieSweeps` sweep)
  rather than hand-computed pixels.
- `TChartExportTest` **does** instantiate (`TTyChart.Create(nil)`, `Font.PixelsPerInch := 96`,
  `SetBounds(0,0,320,200)`) and drives the real `RenderTo` off-screen through `SaveToFile`/`SaveToStream`
  — proof that headless rendering to a `TBitmap.Canvas` works without a handle.

### 1.13 Designtime

**None.** `grep Chart designtime/` finds only `designtime/tyControls.Design.pas:196` (palette registration)
and three icon resources in `tycontrols_icons.lrs` (`TTyChart`, `TTyChart_150`, `TTyChart_200`).
There is **no property editor for `Values`** (you type a CSV string into the Object Inspector), **no series
collection editor beyond the stock LCL `TCollection` editor**, and **no component editor** (no "Edit
series…" verb, no design-time preview data). Compare: `TTyTreeView`/`TTyCascader` have structure editors in
`tyControls.Design.CompEditors` + `tyControls.Dialogs.StructureEditor`.

### 1.14 Example

`examples/chart/` — `.lfm`-authored (house rule), `TTyForm` + `TTyTitleBar` + built-in-theme switcher +
dark toggle. Data model (Title, Categories, 4 series incl. one explicit `Color = clFuchsia` and one with
negative values) all lives in the `.lfm`. Code only wires the 4 type buttons, 4 checkboxes, `OnGetTooltip`
(appends `(series N, point M)`) and `OnMouseDown` → `HitTestAt` for click-to-drill. Strings are
`resourcestring`s.

---

## 2. Explicit non-goals / known gaps

**Stated in the unit header (`tyControls.Chart.pas:24`):**
> `Still NOT included: zoom / mixed chart types / secondary axes.`

**Stated in `docs/controls/chart.md`:**
- One chart = one type; no mixing.
- Sub-element typeKeys (`TyChartTitle`/`TyChartLegend`/`TyChartAxis`/`TyChartGrid`/`TyChartLabel`) were
  "deliberately deferred"; only `TyChartTooltip` (+ the now-shipped `TyChartSeries1..8`) exist.
- Series palette is deliberately **not** derived from the theme's 5-seed accent palette — qualitative
  distinguishable hues are a data-viz constraint, not a skin's aesthetic choice.
- The tooltip cannot leave the control's bounds (accepted cost of the in-bitmap design).
- Zero-value bars are intentionally unhittable.
- Graphic control ⇒ not a container.
- `'Series N'` is intentionally **not** a `resourcestring` (it is a stand-in for missing *data* and the
  legend and tooltip must say the same thing).
- Tooltip/tick number formatting deliberately does **not** follow locale.

**Gaps not written down anywhere but true of the code:**
no stacking, no horizontal/inverted bars, no area fill, no smooth/step lines, no scatter/bubble/radar/gauge/
heatmap/candlestick/funnel/treemap/sankey/graph, no per-point styling, no null/NaN handling, no data zoom /
brush / pan, no axis min/max/interval/log/time, no axis titles, no second Y axis, no legend placement or
interaction, no animation or transitions (`tyControls.Animation`/`Transitions` exist in the library and the
chart uses neither), no keyboard/accessibility path, no crosshair/axis-pointer, no multi-series ("axis")
tooltip mode, no marklines/markareas, no value-label collision avoidance, no rotated tick labels, no
label ellipsis on tick/category labels, no clipping of series to the plot band, no `Values` parse cache.

---

## 3. Architectural constraints any 3.1 expansion must respect

### 3.1 Pure-function + headless-test discipline

The house pattern, stated in the unit header and enforced by the test file: **all scale / layout / hit-test
arithmetic lives in `interface`-level pure functions** taking plain rects and numbers, with no control,
painter or handle state, so it is unit-testable without a GUI. `RenderTo` is the only real-machine path and
it *calls those same functions* — "the datum the pointer reports can never drift from the datum that was
drawn there — **the TTySegmented rule**."

For a big expansion the precedent to copy is the Grid: `tyControls.Grid.pas` (control) +
**`tyControls.Grid.Layout.pas`** (pure geometry) + `tyControls.Grid.Csv.pas`. A 3.1 chart should almost
certainly gain a `tyControls.Chart.Layout.pas` (and possibly `.Data`/`.Series`) rather than growing
`Chart.pas` past 1700 lines with the geometry inline.

Headless caveat from repo history: headless tests never run the LCL align engine and never see real font
metric differences; anything depending on `Show`n layout or GUI text rendering must be verified on a real
machine. Export tests (`TChartExportTest`) are the trick for exercising the real paint path headless.

### 3.2 Theme-token rule (hard rule)

*Visual values must come from theme tokens; never hard-coded in control code.* Two mechanisms:

- **Style properties** — `ActiveController.Model.ResolveStyle(typeKey, StyleClass, states)` → `TTyStyleSet`
  with a `Present: TTyPropSet` set. **Always test `Present`**; an absent property must degrade to *drawing
  nothing*, never to a literal colour (`if tpBackground in tipS.Present then …`).
- **Metric tokens** — `ActiveController.Metric('--name', ADefault)` → Integer, with a named `…Var` constant
  beside a named default constant (the v3/C convention) so a typo cannot silently strand a call site.
  New tokens must be added to `themes/light.tycss` (the base layer every theme inherits), to
  `source/tyControls.Css.Catalog.pas` (completion/lint), and re-generated into `source/tyControls.DefaultTheme.pas`
  and `source/tyControls.BuiltinThemeData.pas` via `scripts/gen-defaulttheme.ps1` / `gen-builtinthemes.ps1`.
- Always go through `ActiveController` (nil-safe fallback to `TyDefaultController`), never raw `Controller`.
- **Theme layering trap**: a skin that writes *any* rule for a typeKey suppresses the built-in rules for that
  key wholesale — including variants. New chart typeKeys must be added to the base layer *and* checked
  against all 17 themes, or a skin that already styles `TyChart` will erase them.
- Every colour goes through `TTyColor` ($AARRGGBB) → `TyColorToBGRA`/`TyColorToLCL`; check
  `TyAlphaOf(c) > 0` before treating a token as present.

### 3.3 Graphic vs windowed control — what it costs

`TTyChart` is `TTyGraphicControl` (from `TGraphicControl`): no `HWND`, so

- **It cannot have child controls.** A real `TTyScrollBar` is `TTyCustomControl` (windowed) and can never be
  parented to the chart. ECharts' dataZoom slider, an inside-the-chart scrollbar, an inline edit field, or an
  embedded toolbox all need *either* a switch to `TTyCustomControl`, *or* fully self-drawn widgets with
  hand-rolled hit-testing inside the chart's own bitmap.
- It cannot receive focus or keyboard input as-is (no `TabStop`, no `WM_KEYDOWN` path) — keyboard navigation
  of data points needs the windowed base.
- Its `Invalidate` damages the **parent**, which repaints its whole client area. That is why
  `TTyPaintCache` exists for containers, and why the chart repaints only on datum change. A 60 fps animated
  chart as a graphic control would force whole-parent re-renders — measured in `Base.pas` at ~23 ns/px,
  i.e. ~14.9 ms for a 900×700 page.
- Conversely, windowed controls **cannot** cast shadows outside themselves and hit the corner/clipping traps
  documented in repo history (`FillCornerGaps`, ghost erase-to-parent-colour, sibling clipping).
- Pop-out overlays (a tooltip that escapes the control, a legend flyout) would need `TTyPopupSurface`
  (`= class(TForm)`), which drags in the GTK3/Wayland popup grab/reposition traps.

**This is the single biggest fork in the road for a 3.1 expansion** and should be decided explicitly.

### 3.4 Designtime package split

`tycontrols.lpk` (runtime) and `tycontrols_dt.lpk` (designtime) are separate packages. Editors live under
`designtime/` (`tyControls.Design.PropEditors`, `tyControls.Design.CompEditors`, plus dialogs in
`source/tyControls.Dialogs.*Editor.pas`). Repo history: **changes under `designtime/` are not covered by the
test build — `tycontrols_dt.lpk` must be compiled separately**, and `TPropertyEditor` has a zero-arg
`GetPropInfo` that shadows `TypInfo`'s. Also: a `published` write-only property makes the IDE report
"Cannot read property" — every published property needs a real getter.

Any richer chart data model (a real point collection, an editor dialog for series/axes) means new designtime
work in that second package, and icons in `designtime/tycontrols_icons.lrs` (generated, HiDPI 100/150/200).

### 3.5 `.lfm` streaming rules

- `Series` streams as a standard `TCollection` (`Series = < item … end >`); `Categories` as `TStrings`.
  Both work today with **no `DefineProperties`** because `Values` is a plain `string`. A binary or
  array-typed value store would need `DefineProperties`/`ReadData`/`WriteData` to stream at all.
- Enum ordinals are frozen by streamed forms: `ctDonut` was **appended**, not slotted next to `ctPie`,
  precisely for this. Any new `TTyChartType` member must also be appended.
- FPC/LCL streaming traps from repo history: `csLoading` doubling for designer-created sub-objects,
  `Arr[F()]` where `F` calls `SetLength` gives a dangling pointer, code-created same-align siblings display
  in reverse creation order, and a `.lfm` `TTyForm` must explicitly set `TitleBar =`.

### 3.6 i18n

`resourcestring` + per-package `.po` under `languages/` (en + zh_CN). **`tyControls.Chart.pas` contributes
nothing today** — its only user-visible literal is `'Series ' + IntToStr(i+1)`, deliberately not localised.
Numbers are deliberately locale-independent (`'.'` separator, `'0.###'`). Any new chart UI text (an axis
title default, an empty-state message, a legend "all/none") must go through
`source/tyControls.StrConsts.pas` + the `.po` pair, and the example's captions must stay English-fit
(`tests/test.englishfit.pas` scans them). Repo history: an **empty `.po` entry blocks app startup**.

### 3.7 Other house rules that bind

- **Pre-merge checklist**: check i18n (control + demo) and both READMEs (`README.md`, `README.en.md`) before
  merging; CHANGELOG entries are user-facing impact only, one line each, grouped 新增/变更/修复.
- **No native LCL controls inside self-drawn UI** (no bare `TPanel`/`TScrollBar` in a chart's chrome).
- **Every example is `.lfm`-authored, carries a `TTyTitleBar`, and supports runtime skin switching.**
- Examples teach usage / cover what tests can't reach; member coverage is explicitly *not* the goal.
- Changing `source/` requires `lazbuild -B` for examples (stale-lib trap).
- Design docs go in `docs/superpowers/specs/YYYY-MM-DD-*.md`, progress in `docs/superpowers/plans/`.
- Skins legitimately change fonts and padding — never hard-code widths that a skin can overflow
  (`tests/test.skinfit.pas` guards this).
- CJK word-wrap must not break on spaces only (`TyWrapTextCJK` / `TyIsCJKCodepoint` exist for this).

---

## 4. RENDERING CAPABILITY CEILING

Two layers are available: `TTyPainter` (house API, theme-aware, DPI-scaling) and — as `TTyChart` already
does — the raw `P.Bitmap` (`TBGRABitmap`) and `P.Bitmap.Canvas2D` (`TBGRACanvas2D`) underneath it.
BGRABitmap **11.6.6**.

### 4.1 `TTyPainter` public API (`source/tyControls.Painter.pas`) — what the house layer gives

`BeginPaint(ACanvas, ARect, APPI, ARightToLeft=False)` allocates a transparent `TBGRABitmap` the size of
`ARect`; `BeginPaintOn(…, ABmp, …)` paints onto a caller-owned bitmap **without clearing** (frame reuse);
`EndPaint` applies `Opacity` (whole-bitmap!) and blits with `FBmp.Draw(FCanvas, …)`.
`Scale(logical): Integer` / `Unscale(device)`; `property PPI`; `property Bitmap: TBGRABitmap`;
`property RightToLeft`.

Drawing: `FillBackground(rect, TTyFill, radius | TTyCorners)` (solid / linear gradient / nine-slice / image /
frosted glass, per-corner radii), `StrokeBorder(rect, radius|corners, width, color)`,
`FillPointerShape` (callout with a tail), `DrawEdge(rect, width, tlColor, brColor)` (3-D bevel),
`DropShadow(rect, radius, color, blur, offset)`, `FillCornerGaps`, `EraseRect`, `NineSlice`,
`DrawImageFill(rect, path, mode, blur)`, `FillImageSlice`, `FillGlass`, `BlitRegion`, `DrawGlyphBitmap`,
`DrawGlyph(rect, TTyGlyphKind, color, thickness, pad)` (~20 built-in glyphs), `DrawDropChevron`,
`StarPath(cx, cy, outer, inner)` + `DrawStar`.

Text: `DrawText(rect, text, fontName, sizeLogical, weight, color, hAlign, vAlign, ellipsis, mnemonicPos=0,
smallCrisp=False, multiLine=False, lineHeightLogical=0)` — **axis-aligned only, no angle parameter**;
`MeasureText(text, fontName, size, weight): TSize` (cached; `TyInvalidateTextMeasureCache`,
`TyTextMeasureCacheStats`); `TextCaretX` / `TextCharIndexAtX` (bidi-correct, per-click cost, unused so far);
unit-level `TyMeasureTextBlock`, `TyMeasureRenderedTextWidth`, `TyWrapTextCJK`, `TySplitTextLines`,
`TyNaturalLineHeight`, `TyEllipsisPrefix`, `TyClampRadiusPx`, `TyTextHasRTL`, `TyColorToBGRA`,
`TyConfigureTextFont`. `DrawTextSupersampled` (private) does manual 3× supersampling for small bold text on
non-Windows.

**Painter gaps relevant to charts:** no arbitrary path API, no polygon/polyline entry point, no clip
push/pop, no transform, no dashed line, no rotated text, no radial gradient (`TTyFill` gradients are
**linear only**, `tfkLinearGradient` with `GradAngleDeg` + multi-stop `GradStops`). All of that is reachable
one level down.

### 4.2 What IS available one level down — `P.Bitmap.Canvas2D` (`TBGRACanvas2D`)

Verified in `bgracanvas2d.pas` 11.6.6. **This is an HTML5-Canvas-shaped API and it is nearly complete.**

- **Paths**: `beginPath`, `closePath`, `moveTo`, `lineTo`, `polylineTo`, **`quadraticCurveTo`**,
  **`bezierCurveTo`** (cubic), `rect`, `roundRect(x,y,w,h,radius | rx,ry)`, `arc` (circular *and*
  **elliptical** with x-rotation, cw/ccw), `arcTo` (both tangent and SVG-elliptical forms), `circle`,
  `ellipse`, **`spline`/`splineTo`/`openedSpline`/`closedSpline`/`toSpline` with `TSplineStyle`** (this is
  the smooth-line primitive an ECharts `smooth: true` needs — no manual Catmull-Rom required),
  **`addPath(ASvgPath: string)` / `path(ASvgPath: string)`** (raw SVG path data — arbitrary symbol shapes,
  map outlines, custom markers all become one string), `clearPath`, `currentPath: ArrayOfTPointF`.
- **Arbitrary polygons**: yes — any `moveTo`+`lineTo`* + `fill`. `fillMode: TFillMode` selects
  **winding vs alternate (even-odd)** — which is exactly how the donut hole works today.
- **Fill / stroke**: `fill`, `stroke`, `fillOverStroke`, `strokeOverFill`, `fillRect`, `strokeRect`,
  `clearRect`; `fillStyle`/`strokeStyle` accept `TBGRAPixel`, `TColor`, a CSS colour **string**, an
  `IBGRAScanner` **texture**, or an `IBGRACanvasTextureProvider2D`.
- **Gradients**: **`createLinearGradient`** and **`createRadialGradient`** (two-circle form
  `x0,y0,r0,x1,y1,r1`, plus a `flipGradient` flag), each with `addColorStop(pos, colour)` (n stops),
  `gammaCorrection`, and `repetition: TBGRAGradientRepetition`. `createPattern(image, repetition)` for
  tiled fills. So: gradient-filled areas, radial gauge sweeps and pattern fills are all reachable.
- **Clipping**: **`clip`** (clips to the *current path* — arbitrary shape, implemented as a grayscale mask,
  so it is **antialiased**, not a rect region) and `unclip`; plus `save`/`restore` of the whole state stack
  (`copyStateFrom` too). Rect-only clipping is also available directly as `P.Bitmap.ClipRect: TRect`
  (used across the library, e.g. `BlitRegion`, `DrawTextLine`).
- **Transforms**: **full 2-D affine** — `scale`, `rotate(angleRadCW)`, `translate`, `skewx`, `skewy`,
  `transform(m11…m23 | TAffineMatrix)`, `setTransform`, `resetTransform`, plus a **separate stroke matrix**
  (`strokeScale`/`strokeSkewx`/`strokeSkewy`/`strokeResetTransform`, `strokeMatrix`) so a shape can be
  transformed while its outline keeps a constant device width.
- **Line style**: `lineWidth: single`, `lineCap` (`'butt'|'round'|'square'`, or `lineCapLCL: TPenEndCap`),
  `lineJoin` (`'round'|'bevel'|'miter'`, or `lineJoinLCL`), `miterLimit`, and **`lineStyle(const AValue:
  array of single)` / `lineStyle(AStyle: TPenStyle)` — i.e. arbitrary dash patterns** (`getLineStyle:
  TBGRAPenStyle`). Dashed grid lines and dashed marklines are reachable.
- **Alpha & compositing**: `globalAlpha: single`; every colour is RGBA `TBGRAPixel`; `TDrawMode`
  (`dmSet`, `dmDrawWithTransparency`, …) on the bitmap primitives.
- **Shadows**: `shadowColor`, `shadowOffsetX/Y`, `shadowBlur`, `shadowFastest`, `shadowNone`, `hasShadow`
  — a real canvas shadow on any path, independent of the painter's rect-only `DropShadow`.
- **Images**: `drawImage(bitmap, dx,dy[,dw,dh], AFilter: TResampleFilter)` and `mask(...)`.
- **Text on the 2-D context**: `fillText`, `strokeText`, `text` (adds glyph outlines to the path — so text
  can be **filled with a gradient or clipped**), **`measureText(AText): TCanvas2dTextSize`**, `fontName`,
  `fontEmHeight`, `fontStyle`, `font` (CSS string), `textAlign`/`textAlignLCL`, `textBaseline`,
  `direction: TFontBidiMode`, `fontRenderer`. Because text can go through the path, the **transform applies
  to it** — rotated/skewed labels are reachable this way as well.
- **Hit testing**: `isPointInPath(x,y)` — a path-accurate hit test straight from the drawing code
  (relevant if the chart ever draws non-rectangular marks).
- `toDataURL('image/png')` exists but is irrelevant here.

### 4.3 What IS available on `P.Bitmap` (`TBGRABitmap` / `TBGRACustomBitmap`) directly

- **Rotated text**: **`TextOutAngle(x, y, orientationTenthDegCCW, sUTF8, colour, align [, ARightToLeft])`**
  — tenths of a degree, CCW. Already used in production by `tyControls.Menu.pas` for the Office-style side
  banner (`P.Bitmap.TextOutAngle(x, y, 900, caption, colour, taLeftJustify)`). **Rotated axis tick labels
  are therefore physically reachable today**, at the cost of measuring the rotated bounding box yourself.
- Text: `TextRect(rect, x, y, s, TTextStyle, colour)` (clips, aligns), `TextOut`, `TextMultiline`,
  `TextSize(s [, maxWidth [, rtl]])`, `TextSizeMultiline`, **`TextOutCurved(path/cursor, s, …)`**
  (text along an arbitrary path — pie slice labels curved around the ring are reachable).
- Antialiased primitives: `DrawPolyLineAntialias`, `DrawPolygonAntialias`, `EllipseAntialias`,
  `DrawPath(IBGRAPath [, AMatrix], strokeColour|texture, width, fillColour|texture)`,
  `Arc(cx,cy,rx,ry, start,end, colour, w, chord, fill)`, `FillChord`, `FillChordInRect`, `Pie(...)`
  (native pie/arc/chord primitives), `FillRect`, `DrawHorizLine`/`DrawVertLine`, `DrawPixel`.
- **Gouraud / gradient meshes**: `FillPolyLinearColor`, `FillTriangleLinearColor(Antialias)`,
  `FillQuadLinearColor(Antialias)`, `FillEllipseLinearColorAntialias`, plus perspective and texture-mapped
  variants — per-vertex colour interpolation, i.e. heat-map cells and continuous colour scales are cheap.
- `ClipRect: TRect` (rectangular hard clip), `ApplyGlobalOpacity`, `Fill`, `AlphaFill`, blur/filter units
  (`BGRAFilterBlur`, `BGRAGradientScanner` — the latter is already a painter dependency).
- Export: `SaveToFile`, `SaveToStreamAs(stream, TBGRAImageFormat)`.

### 4.4 What is NOT available / genuinely out of reach

- **No GPU / OpenGL path in this rendering pipeline.** `BGRACanvasGL` exists in the package but the whole
  library renders CPU-side into a `TBGRABitmap` and blits once per paint. Everything is software rasterised.
- **No retained scene graph, no invalidation regions, no partial redraw** — `RenderTo` rebuilds the entire
  chart from scratch on every paint, and a graphic control's invalidate repaints the parent's whole client
  area. Any ECharts feature that assumes cheap incremental redraw (60 fps animation, live streaming data,
  drag-brush with instant feedback) must be re-costed against this. `TTyPaintCache` and `BeginPaintOn`
  (paint onto a reused bitmap without clearing) are the two escape hatches the library already has.
- **No animation/tweening in the chart** — `tyControls.Animation.pas` / `tyControls.Transitions.pas` exist
  and are used by other controls, but they drive LCL timers and would collide with the repaint cost above.
- **No text-on-a-rotated-rect convenience in the painter** — rotated labels mean `TextOutAngle` plus your own
  bounding-box maths; `MeasureText` measures the unrotated string only.
- **`TTyPainter.Opacity` is whole-bitmap** (applied in `EndPaint`) — there is no per-element opacity in the
  house API. Per-element alpha must go through `globalAlpha` on the Canvas2D or per-pixel alpha in the colour.
  (This is exactly why `DrawTooltip` must not call `DrawFrame`.)
- **No hardware text shaping control beyond the widgetset**; small bold text is blurry on Linux/macOS unless
  routed through `DrawTextSupersampled` (Windows-gated in the painter).
- **No child windows in a graphic control** (§3.3) — sliders, scrollbars, inline editors and pop-out
  overlays are not "drawing" problems, they are base-class problems.
- **No SVG *output*** (SVG path *input* is available via `addPath(string)`); export is raster only
  (`TBGRAImageFormat`: png/jpeg/bmp/tiff…).
- Gradient text/pattern text works only via the `text` → path route, not via `TTyPainter.DrawText`.

### 4.5 Verdict on reachability

Ceiling is set by **architecture and data model, not by the rasteriser.** Bezier + splines + arbitrary SVG
paths + even-odd/winding fill + antialiased arbitrary-shape clipping + full affine transforms + linear and
radial gradients + per-vertex colour interpolation + dash patterns + line caps/joins + rotated and
path-following text + text measurement + path-accurate hit testing are all present.

Physically reachable with the current painter/BGRA stack (drawing-only work): area charts, stacked/percent
bars, horizontal bars, smooth and stepped lines, scatter/bubble, radar, gauges, heatmaps, funnel, candlestick,
rose/nightingale pie, rotated + curved labels, dashed marklines, gradient series fills, axis pointers and
crosshairs, custom symbol shapes.

Blocked on something other than drawing: **anything needing (x, y) or typed data** (blocked by
`Values: string` — §1.5), **anything needing a child widget or focus** (blocked by `TTyGraphicControl` —
§3.3), **anything needing cheap incremental repaint** (blocked by the full-rebuild paint model — §4.4),
and **anything needing per-element opacity through the house API** (§4.4).
