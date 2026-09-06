# 18 — Decision memo: should `TTyAdvanceChart` target ECharts 5 or ECharts 6?

Audience: the ty-controls maintainer. Question as asked: *"5 和 6 有什么区别？或者说 6 增加了什么？
你帮我对比下"* — so §1 explains the difference first, and the recommendation comes after.

Evidence base: reports `12`–`17` in this directory (the v6 research pass), plus `10-gap-analysis.md`
and `11-critique.md`. Sources are the local clones `D:/Projects/echarts` (6.1.0),
`D:/Projects/echarts-doc`, `D:/Projects/zrender` (6.1.0).

Decisions already taken by the maintainer, assumed throughout: **new control** (no `.lfm`
compatibility with `TTyChart`), **windowed base class**, **option-tree API with a validating
design-time editor**, **maps/GeoJSON in scope and important**, **depth-first build order**.

> Note for future readers: `16-port-impact-5-vs-6.md` opens with "report 12 does not exist". It was
> written in parallel with `12`; `12` exists — but its numbers do **not** all agree with `16`'s; see
> the corrections below.

> ## Corrections applied `[corrected]`
>
> An adversarial review of this memo is in `19-critique-v5v6.md`. The recommendation in §5 survives it,
> but these numbers and one framing do not. Read them before quoting anything from this file.
>
> 1. **§4's "three options" is really two.** (ii) "target v6 fully" was costed as pulling the v6-only
>    subsystems into the early schedule — but §1.1 and §5 both establish that targeting v6 implies no
>    such thing, because every v6-only item is already Tier 2/3. (ii) and (iii) are the same option with
>    a schedule assumption invented for one and denied for the other. **The real choice is: target v5,
>    or target v6.** The recommendation rests on the two-contracts argument in §5, which is unaffected.
> 2. **The "2 XL saving" from targeting v5 is overstated.** `matrix` is a solid XL.
>    `coordinateSystemUsage:'box'` is costed three incompatible ways inside this memo (§1.1 "~250 lines
>    diffuse", §2 "S mechanism / L consequence", §4 "XL"). Its *mechanism* is small; its *consequence*
>    — every coordinate system supporting nesting — is what is large, and that is precisely why it is
>    a Tier-0 **contract** rather than a Tier-3 feature. State the saving as **1 XL + 1 L + 2 M plus one
>    contract**, not "2 XL".
> 3. **Line counts, measured.** Axis breaks = **1,656** (`scale/break.ts` 178 + `breakImpl.ts` 785 +
>    `axisBreakHelper.ts` 91 + `axisBreakHelperImpl.ts` 572 + `installBreak.ts` 30), not 1,803.
>    `thumbnail` = **615**, not 706. `matrix` = 2,677 and `chord` = 1,200 are correct.
> 4. **`sankey.roam` / `roamTrigger` are documented** (`sankey.md:95-100` calls
>    `partial-view-coord-sys-common`; `view-coord-sys.md:120,126`). Delete the "undocumented" row.
>    Sankey's `roamTrigger` default is `'global'` (`SankeySeries.ts:329`), not `'selfRect'`.
> 5. **v6 is three releases, not two.** 6.0.1 exists — `LineSeries.ts:125,132` mark
>    `triggerLineEvent` deprecated and `triggerEvent` added "since v6.0.1", so §3.4's "pin to 6.1" list
>    wrongly files `line.triggerEvent` as 6.1-only.
> 6. **Version-marker counts.** Ground truth across `en/option` + `en/api`, including the undocumented
>    `version:` colon form: **81 markers, split 72 @ 6.0.0 / 9 @ 6.1.0.** Report 12's total is right and
>    its split is wrong; 15's "102 across 39 files" and 16's "65" are both wrong.
> 7. **v5's own record** is **111 `[Feature]` / 321 `[Fix]`** across 20 releases (`changelog.md:129-838`),
>    not 118/329. Direction of the argument is unchanged.
> 8. **§2 silently re-tiered `containShape` / `dataMin`/`dataMax` / jitter / `customValues` from
>    `10-gap-analysis.md`'s single Tier-2 M row into four rows, three of them Tier 1**, and invented an
>    `axisStatistics + cycleCache | M | Tier 1` row present in neither `10` nor `16`. §6.1's net-change
>    tally does not include that ~2.5 M. Treat those as Tier 2 until re-argued.
> 9. **Two corrections that change §6.1's own rows** — see `19-critique-v5v6.md` "Maintainer follow-up":
>    the function-valued surface is **1,212 nodes** (244 Function-only + 968 unions; `formatter` = 539),
>    not "~30"; and relaxed JSON alone parses **39.6 % of literals / 52.8 % of files** in the real
>    corpus, with **534 of 643 failures being JavaScript, not JSON laxity**. Both make the
>    named-handler + template-string row load-bearing rather than incidental.
> 10. **The generated schema is preserved.** `option.json` (EN + ZH) and the partitioned form are now at
>    `D:/Projects/echarts-schema/`; the spike's generator scripts and the compiled Pascal catalog
>    prototype are in `spike/` beside this file. §6.1's catalog row rests on a prototype that *compiled*,
>    not on an estimate.

---

## 1. What ECharts 6 is, relative to ECharts 5

### 1.0 The shape of it, in one paragraph

ECharts 6 is not a rewrite and not a new API. It is **ECharts 5 plus five new subsystems, one repaint
of the default look, and about 119 new option paths**, delivered in **two releases over 19 months**
(6.0.0 on 2025-07-30, 6.1.0 on 2026-05-18) totalling **128 changelog lines**: 37 `[Feature]`,
59 `[Fix]`, 8 `[Break]` bullets, 2 deprecations. Nothing was removed — 0 series, 0 components,
0 actions, 0 events, 0 API methods. The v5 option vocabulary is a **verified strict subset** of the
v6 one. There is no official v6 upgrade guide, because there is almost nothing to migrate.

Five groups, with their real sizes:

### 1.1 (a) Genuinely new subsystems — the biggest group, ~6,100 dedicated source lines (~4 % of `echarts/src`)

Five things exist in 6.x that have no v5 counterpart at all:

| Subsystem | Dedicated lines | What it is |
|---|---|---|
| **`matrix` coordinate system** | 2,677 | A **table used as a coordinate system**. Two header *forests* (nested, multi-level), a body, a corner; a signed-integer locator algebra where `(0,0)` is the top-left body cell and negatives address headers; merged cells; a size solver mixing px / `'%'` / even distribution. It implements `dataToPoint` / `dataToLayout` / `pointToData` exactly like `cartesian2d` does, and it renders itself. |
| **Axis breaks** | 1,803 dedicated, plus threading through the whole scale layer | A **discontinuous axis**: value ranges `[start,end]` collapse to a small `gap`, drawn as a band with a torn-paper zigzag, click-to-expand. Not a component — a change to what "a scale" *is*. |
| **`chord` series** | 1,200 | A ring of arc sectors whose *length* encodes node value, with ribbons between them whose width at each end encodes the edge value. The layout has a genuine algorithm (a `minAngle` deficit/surplus borrowing solver with a greedy fallback); the drawing needs only `arc` + `cubicTo`. |
| **`coordinateSystemUsage: 'box'`** | ~250, diffuse | The generalisation that makes matrix worth having: **any component or coordinate system can be laid out inside a matrix or calendar cell**. `grid`+`xAxis`+`yAxis`+`line` per cell = a sparkline table; `map` per cell; `graph` per cell. |
| **`thumbnail`** | 706 | A minimap: a scaled copy of a roamable series with a draggable viewport rect. Graph-only, confirmed in source (`ThumbnailModel.ts:145`). |

Two smaller ones sit alongside: **jitter** (289 lines, scatter-only — random or greedy circle-packed
beeswarm displacement) and **`registerCustomSeries` + `itemPayload`** (30 lines — a named-renderer
registry that lets `series.renderItem` be a *string*).

**Reading:** the entire v6-only subsystem surface is five items, and **all five are Tier 2 or Tier 3**
in the roadmap `10-gap-analysis.md` §5 already wrote. None is in Tier 0 or Tier 1. Demo coverage
agrees: of 606 `test/*.html` demos, **16 (2.6 %)** exercise v6-only features.

### 1.2 (b) The visual / design-token overhaul — medium size, high visibility, low porting cost

`src/visual/tokens.ts` (233 lines, new in v6) replaced v5's scattered hex literals with **64 colour
tokens + 8 size tokens**, referenced at **191 sites in 55 files**: a 9-colour `theme[]` palette,
`neutral00…neutral99` (21 steps), `accent05…accent95` (19 steps), 25 semantic aliases
(`primary/secondary/tertiary/quaternary`, `border/borderTint/borderShade`, `background*`,
`axisLine/axisTick/axisTickMinor/axisLabel/axisSplitLine/axisMinorSplitLine`), and a `darkColor`
plane **generated by HSL transform** (`l → 1 − l^1.5`).

Three things must be said plainly about it:

- **It is a source de-duplication refactor, not a theming API.** Tokens are not exported
  (`grep tokens src/export/*.ts` → 0 hits); a theme still merges an *option tree* and restates every
  value per component, exactly as in v5. `theme/v5.js` — the shipped "restore the old look" theme —
  is 581 lines with 110 hex literals, and proves it. `.tycss` is strictly more capable: runtime,
  seed→derive, `base → .variant → :state → .variant:state`, plus typography, radius and a density
  axis. **Do not adopt ECharts' mechanism** — mirror two ideas (a dense *derived* ramp; the ~8-12
  axis-domain token names) and ignore the rest.
- **The look really did change, silently.** New palette (`#5070dd #b6d634 #505372 #ff994d #0ca8df
  #ffd10a #fb628b #785db0 #3fbe95` — note slot 3 is a dark slate); legend moved `top:0` → bottom
  centre; title moved to centre; grid `10%/60/10%/70` → `15%/65/10%/80`; the tooltip gained a
  **visible** border (`#fff` → `#b7b9be`); toolbox/timeline/visualMap padding 5 → 15; line
  `symbolSize` 4 → 6; pie radius 75 % → 50 %; bar gap 20 % → 10 %; the axisPointer label chip is now
  a fixed indigo instead of taking the axis colour, and lost its drop shadow.
- **For a port this group is nearly free.** It is a table of constants and some arithmetic. And "the
  v5 look" is therefore **one `.tycss` skin**, not a version target.

### 1.3 (c) Accumulated option-level additions — ~119 new option paths, ~25 standalone features

Outside `matrix` / `thumbnail` / `chord` (which add ~35 / ~14 / ~150 paths of their own), v6 adds
**119 distinct new option-path shapes**, clustered rather than scattered:

- **axis (22)** — the `breaks` / `breakArea` / `breakLabelLayout` tree, `jitter*`, `nameMoveOverlap`
  (6.0); `containShape`, `dataMin`, `dataMax`, `axisLine.onZero:'auto'` (6.1).
- **grid (9)** — `outerBoundsMode` / `outerBounds` / `outerBoundsContain`, the anti-overflow layout
  pass that **deprecates `containLabel`**.
- **coordinate-system placement (7 shapes × 19 hosts)** — `coordinateSystem`,
  `coordinateSystemUsage`, `coord`, `matrixIndex/Id`, `calendarIndex/Id` stamped onto 12 components
  and 7 series. Structurally the biggest change in v6.
- **roam / view (5 × 5 hosts)** — `roamTrigger`, `preserveAspect` ×3, `geo.clip` / `map.clip`.
- **markers (7)**, **label (2)** (`textMargin`, 30 call sites; `richInheritPlainLabel`),
  **series (13)**, **components (8)**.

Plus ~25 single-option features, each S: `stackOrder`, `legend/line/matrix.triggerEvent`,
`radar.clockwise`, `visualMap.seriesTargets` / `unboundedRange`, `dataZoom.cursorGrab`,
`marker.relativeTo`, pie `'tangential-noflip'`, `gauge.progress.color:'auto'`, sankey roam,
`custom.compoundPath` / `tooltipDisabled` / `api.layout()`, `convertToLayout`, `setTheme`, and the
three axis-break actions plus the `axisbreakchanged` event.

**Reading:** a v5-shaped option parser is a v6-shaped option parser minus ~119 paths. This group
changes no architecture.

### 1.4 (d) Breaking changes and deprecations — very small: 8 bullets, 2 deprecations

The **entire** official record is two `[Break]` blocks: `en/changelog.md:122-127` (5 bullets, v6.0.0)
and `:69-72` (3 bullets, v6.1.0). There is no `upgrade-guide-v6.md` in either language. Detail and
the actionable list are in §3.

Deprecated **in** v6: exactly two — `grid.containLabel` (→ `outerBoundsMode`) and
`series-line.triggerLineEvent` (→ `triggerEvent`). The ~64 older deprecated names
(`itemStyle.normal`, `hoverAnimation`, `mapType`, `clipOverflow`, the 18 zrender `text*` props, …)
are **v5-era and identical under either target** — all still functional in 6.1.0. ECharts has never
deleted a compat shim; live 6.1.0 code still translates ECharts 2's `geoCoord`.

### 1.5 (e) Bug fixes and internals — 59 fixes, 3 refactors, and the fact that decides the argument

59 `[Fix]` entries and three `[Chore][refactor]` entries in 6.1.0: **axis scale implementation
rewritten**, series data union unified, **roaming implementation unified**. New invisible machinery:
`axisStatistics.ts` + `axisStatisticsMetricsImpl.ts` (672 lines) and `cycleCache.ts` (85) — a
per-update-cycle ⟨axis, series⟩ cache underpinning `alignTicks`, bar layout and the v6.1 uniform
`bandWidth`; and `axisBand.ts` (209), which lets bar-like series sit on `value` / `time` / `log` axes.

**The fact that decides the argument:** ECharts 6.1.0 *contains* all 20 v5 releases' 118 features and
329 fixes. There is no separate, more-settled v5 codebase to port from. Targeting v5 means porting
from the same 6.1.0 source and deliberately skipping parts of it.

### 1.6 Group sizes, side by side

| Group | Size | Cost to a fresh port |
|---|---|---|
| (a) New subsystems | 5 items, ~6,100 lines, 2 XL + 1 L + 2 M | All Tier 2/3 — deferrable, **except two design contracts** (§4) |
| (b) Visual / token overhaul | 233-line token file, ~40 changed defaults | Near-zero — a constants table; the mechanism is worse than `.tycss` |
| (c) Option-level additions | ~119 paths + ~25 S features | ~25 S items, plus ~150 lines in one Tier-0 L |
| (d) Breaks + deprecations | 8 bullets, 2 deprecations | Almost entirely free (§3) |
| (e) Fixes + internals | 59 fixes, 3 refactors | Free — and only obtainable by targeting 6.1 |

---

## 2. The complete table of v6-only capability

One row per capability. **Size** is effort for our port (S ≈ days, M ≈ 1–2 weeks, L ≈ 3–6 weeks,
XL ≈ months). **Tier** is where it lands in the `10-gap-analysis.md` §5 roadmap as revised by §6.

| Capability | Subsystem | What it does | Size | Tier |
|---|---|---|---|---|
| `matrix` coordinate system | matrix | Table as a coord sys: header forests, signed locator algebra, ordinal-vs-locator numbering, merged cells, px/%/even size solver, self-rendered headers + dividers + corner | **XL** | 3 |
| `coordinateSystemUsage: 'box'` | core layout | Any component or coord sys positioned *inside* a matrix/calendar cell — sparkline tables, chart-per-cell, map-in-cell | **S** mechanism / **L** consequence | 3 — but the **rect contract is Tier 0** |
| Axis breaks | scale | Discontinuous axis: collapsed `[start,end]` ranges, `gap` in % of axis or in data units, cached randomised zigzag `breakArea`, tick pruning with a 3-valued policy, `expandOnClick`, 3 actions + 1 event | **L** | 3 — but the **piecewise-scale assumption is Tier 0** |
| `chord` series | series | Ring of value-proportional node arcs plus inter-node ribbons; `minAngle` deficit/surplus borrowing solver; `focus:'adjacency'` | **M** | 2 |
| `thumbnail` | component | Minimap of a roamable graph with a draggable viewport rect and its own roam controller | **S–M** | 3 |
| `jitter` / `jitterOverlap` / `jitterMargin` | axis + scatter | Random or greedy circle-packed (beeswarm) displacement across the band; O(n²) in the packing path | **S** | 2 |
| `registerCustomSeries` + `renderItem` as string + `itemPayload` | custom | Named, registered renderers with a data payload — **what makes `custom` expressible in a serialisable option tree at all** | **S** | 2 — **adopt the shape in Tier 0** |
| `grid.outerBounds*` + `nameMoveOverlap` | grid / axis layout | Iterative pass shrinking the plot rect until axis labels *and names* fit; supersedes and deprecates `containLabel` | **M** (≈ +150 lines over the v5 `containLabel` path) | **0** |
| Design tokens (`tokens.ts`) | theme | 64 colour + 8 size tokens, semantic aliases, formula-derived dark plane | **S** (shape only — `.tycss` already does more) | **0** |
| The v6 default look | defaults | 9-colour palette, legend bottom-centre, title centred, grid `15%/65/10%/80`, tooltip border, `symbolSize` 6, pie 50 %, `barGap` 10 % | **S** (a constants table) | **0** |
| `setTheme` / `registerTheme` | API | Runtime theme registration and switching | **free** — `TyController` already does this | 0 |
| `containShape` + universal no-overflow (6.1) | axis | `bar` / `pictorialBar` / `candlestick` / `boxplot` never bleed outside the plot rect, on all four axis types | **M** (needs the `axisStatistics` machinery) | 1 |
| `dataMin` / `dataMax` (6.1) | scale | Extend the domain from data bounds while keeping the nice-tick algorithm; a *second* extent kind interacting with dataZoom and `clampData` | **S–M** (HEAVY-lite, per critique #11) | 1 |
| Uniform `bandWidth` on `value`/`time`/`log` (6.1, `axisBand.ts`) | axis | Bar-like series on non-category axes | **S** | 2 |
| `axisStatistics` + `cycleCache` | internal | Per-update-cycle ⟨axis, series⟩ statistics behind `alignTicks`, bar layout, `bandWidth` | **M** | 1 (invisible, unavoidable) |
| `roamTrigger`, `preserveAspect` ×3, `geo.clip`, `map.clip`, corrected `center` percent base, unified roam | geo / map / graph / sankey / tree | The roam and view-fitting surface — **directly on the maps-in-scope path** | absorbed into "View + RoamController \| L"; ≈ **1 M of avoided rework** | 2 |
| `sankey.roam` / `.roamTrigger` | series-sankey | Roaming for sankey — **present in source, undocumented** in `en/option/series/sankey.md` | **S** | 2 |
| `label.textMargin` | label | Margin applied to the label's *unrotated* box; 30 call sites | **S** | 1 |
| Rich labels inherit plain label style | label | 8 props inherit (`fontStyle`, `fontWeight`, `fontSize`, `fontFamily`, 4 × `textShadow*`) | **S** | 1 |
| `axisLine.onZero: 'auto'` (6.1) | axis | New enum value, and the new default | **S** | 1 |
| `axisLabel.formatter` receives its index (6.1) | axis | Works with `customValues` | **S** | 1 |
| Log axis auto-excludes non-positive values (6.1) | scale | | **S** | 1 |
| `stackOrder` | series bar/line | `'seriesAsc'` / `'seriesDesc'` | **S** | 1 |
| `markPoint/markLine/markArea.z`, `data[].z2`, `data[].relativeTo` | markers | Ordering, and a relative positioning target | **S** | 1 |
| `legend.triggerEvent`, `line.triggerEvent` (6.1), `matrix.triggerEvent` (6.1) | components | Mouse events from legend items / line stroke or area / matrix cells | **S** each | 1–3 |
| `visualMap.unboundedRange`, `.seriesId`, `.seriesTargets` (6.1) | visualMap | Range past min/max; target by id; one visualMap over many series and dimensions | **S** each | 2 |
| `dataZoom-inside.cursorGrab` / `.cursorGrabbing`, `candlestick.cursor` (6.1) | components | Cursor feedback (maps to `TCursor`, not CSS names) | **S** | 1–2 |
| `pie.label.rotate: 'tangential-noflip'` (6.1) | pie | New enum value | **S** | 2 |
| `gauge.progress.color: 'auto'` (6.1) | gauge | New enum value | **S** | 2 |
| `radar.clockwise` (6.1) | radar | Reverse indicator direction | **S** | 2 |
| `boxplot.clip` (6.1); scatter / effectScatter `clip` on geo (6.1) | series | Previously cartesian-only | **S** | 2 |
| `custom.compoundPath`, element `tooltipDisabled`, `api.layout()` | custom | Union path element; per-element tooltip suppression; resolve a cell rect inside `renderItem` | **S** | 2 |
| `matrix.x/y.length` (6.1) | matrix | Headless matrix — a pure grid container with no header text | **S** | 3 |
| `convertToLayout` API; `expandAxisBreak` / `collapseAxisBreak` / `toggleAxisBreak`; `axisbreakchanged` | API | Coord → rect; break interaction | **S** | 3 |
| `tooltip.displayTransition` | tooltip | **Browser-bound** — a CSS transition on the DOM tooltip | — | X |
| `legacyViewCoordSysCenterBase`, `richInheritPlainLabel:false`, `grid.containLabel`, `outerBoundsMode:'none'`, `containShape:false` | compat | v5-restore switches | — | **never implement** |

---

## 3. Breaking changes and deprecations — what a fresh port should do

The whole point: **a greenfield port pays almost nothing for a "breaking change".** A break is a cost
for someone who has existing charts. We have none. For six of the eight, the correct action is simply
*implement the v6 form and never build the v5 form*. Two are not free, and it is worth being exact
about which.

### 3.1 Genuinely free — implement the v6 form, never the v5 form, never the escape hatch

| # | Break | What to build | Why it is free |
|---|---|---|---|
| B1 | Default theme and default component positions changed (legend to the bottom, title centred, grid `15%/65/10%/80`, new 9-colour palette) | The v6 defaults | It is a table of constants; either target needs one. And "the v5 look" is one `.tycss` skin — ECharts' own compat shim (`theme/v5.js`) *is* a theme file |
| B2 | `src/theme/light.ts` → `theme/rainbow.js` | Nothing | A rename inside someone else's package layout |
| B4 | `center` percent base corrected on `geo` / `map` / `graph` / `tree` — the changelog says "the previous percent base is incorrect" | The corrected base | A bug fix promoted to a break. **Targeting v5 means deliberately shipping the acknowledged-wrong base**, on the maps path that is explicitly in scope |
| B5 | `label.rich.*` now inherits the plain label style (8 props) | The inheritance | Strictly better behaviour. Never implement `richInheritPlainLabel` |
| — | `grid.containLabel` deprecated | `outerBoundsMode` / `outerBounds` / `outerBoundsContain` | A v5 target would build `containLabel` as a *first-class* feature and unwind it later |
| — | `series-line.triggerLineEvent` deprecated | `triggerEvent: true \| 'line' \| 'area'` | Same shape, better name; the v5 name never gets written |
| — | `tooltip.appendToBody` (5.5.0) | Nothing | DOM-bound; there is no DOM |

### 3.2 Free in compatibility, but real work — budget it

| # | Break | What to build | The honest cost |
|---|---|---|---|
| B3 | Cartesian anti-overflow and anti-name-overlap on by default | `outerBounds*` + `nameMoveOverlap`, inside the two-phase axis build | **≈ +150 lines** over the v5 path. Measured: ECharts keeps the whole v5 implementation as `legacyContainLabel.ts` = **120 lines**; the v6 solver is ~276. The *structure* (estimate labels → shrink rect → determine) is identical under both targets and is a Tier-0 **L** either way |
| B8 | `bar` / `pictorialBar` / `candlestick` / `boxplot` no longer overflow the grid rect; `containShape` defaults true (6.1) | The margin computation on all four axis types | **M.** It rests on the v6.1 `axisStatistics` (501 + 171 lines) + `axisBand` (209) machinery with 14 consumers. Not free — but a v5-structured scale layer has to grow this later anyway |

### 3.3 NOT free — contract decisions that must be taken on day one

| # | Break | Why it is different |
|---|---|---|
| B6 | `tooltip.valueFormatter`'s 2nd parameter: `dataIndex` (post-dataZoom-filter) → **`rawDataIndex`** (index into the original data) | A *silent semantic change on a callback parameter*. Under an option-tree API with a named-handler registry, this parameter lives in a record shared by every registered formatter. Adopting it on day one costs nothing; migrating it once handlers exist in user code is the most expensive kind of change to absorb |
| B7 | `axis.startValue` decoupled from `axis.min` (previously `startValue` doubled as `min`) | It is a statement about the **scale's extent model**, not an option. Build the extent model with them independent, or rework the scale later |

### 3.4 The skip-list, verbatim

**Never implement:** `grid.containLabel` · `series-line.triggerLineEvent` · `tooltip.appendToBody` ·
`legacyViewCoordSysCenterBase` · `richInheritPlainLabel: false` · `grid.outerBoundsMode: 'none'` ·
`axis.containShape: false` · `theme/v5.js`'s palette and layout · all ~64 v5-era deprecated names
(`itemStyle.normal`, `hoverAnimation`, `downplay`, `highlightPolicy`, `focusNodeAdjacency`,
`clipOverflow`, `mapType`, `mapLocation`, `radar.name` / `nameGap`, the 6 `pie*` / `map*` select
actions and their 6 events, the 18 zrender `text*` style props, `api.style` / `styleEmphasis`,
`chart.one`, `colorMappingBy`, sunburst `r` / `r0`, `title.textBaseline`,
`dataZoom.dataBackgroundColor` / `handleColor`).

**That ~64-name list is identical under either target** — it is v5-era. It is not a differentiator.
If anything a v5 target is worse: it would implement `containLabel` first-class and unwind it later.

**Read source, not docs**, for: `series/chord.md` (6 defects — `padAngle` documented `0`, source
default **3**; `endAngle`, `edgeLabel`, `legendHoverLink`, `center`, `colorBy` undocumented);
`grid`'s default geometry (docs still carry v5's `10%/60/10%/60`); `grid.outerBoundsClampWidth/Height`
(undocumented, `GridModel.ts:137-138`); the axis scale math (refactored in 6.1.0 *after* the docs
were written); the palette (`option.md:69` still documents the v5 one); `legend.itemGap` (doc 10,
source 8); tooltip defaults (docs still carry **v4** values).

**Pin the validator to `6.1`, not `6`.** Chord `padAngle` = 3, `valueFormatter`'s `rawDataIndex` and
`startValue` ⊥ `min` are all 6.1-specific — the three places where a v6 mental model built from 6.0.0
material would be wrong.

---

## 4. The three options, costed

Sizes are the roadmap's: S ≈ days, M ≈ 1–2 weeks, L ≈ 3–6 weeks, XL ≈ months.

### (i) Target ECharts 5

**Ships:** everything the v6 target ships except the five v6-only subsystems. Milestone 1
(Tier 0 + cartesian Tier 1) is **the same shape** — this is the key measurement: no v6-only *row* is
in Tier 0 or Tier 1.

**Deferred:** nothing. The v6-only items simply leave the roadmap.

**Saves:** `matrix` (**XL**), `coordinateSystemUsage:'box'` (**XL**), axis breaks (**L**),
`thumbnail` (**M**), `chord` (**M**) — **2 XL + 1 L + 2 M, all Tier 2/3**. It also shrinks three
Tier-2 rows, trims ~150 lines from one Tier-0 L, and drops ~25 S-sized options.
*(This corrects `10-gap-analysis.md` §6 Q8, which says "four XL": universal transition/morphing is
**v5.0.0**, geo is v2-era, and the option-tree XL is target-independent. The real saving is two XL.)*

**Permanently harder:**
- `coordinateSystemUsage:'box'` becomes a retrofit: in ECharts the seam is `createBoxLayoutReference`
  called from **19+ sites**, plus every coordinate system's rect derivation, plus the usage-kind
  injection path. Designed in it is one parameter; retrofitted it is XL **plus** a 19-site refactor —
  and calendar-hosted charts go with it.
- Axis breaks become unreachable without rewriting `Interval`, `Log`, `Time`, `minorTicks`,
  `scaleMapper`, `axisHelper` and `AxisBuilder` (24/21/36/10/26/25/36 break references respectively).
- `containLabel` gets built as a first-class feature, then unwound.
- Roaming gets built per-consumer, then unified — exactly the work v6.1 did.
- The two v6.1 semantic contracts (B6, B7) get set to the v5 form and migrated later.
- The default look is the 2020 one.

**The honest case for v5, and why it does not survive contact.**
v5 was current for **4 years 8 months / 20 releases / 118 features / 329 fixes / 1 `[Break]`**;
v6 is 13 months old with **2 releases and a `[Break]` block in each** — one of them a callback
contract change. At least 8 of v6.1's 37 fixes land on v6.0-new surface, so that surface is still
moving. And 590 of 606 demos exercise v5-era features. The strongest argument is **ecosystem**: four
years of Stack Overflow answers, blog posts and corporate templates are v5-shaped, so anyone pasting
a config into `TTyAdvanceChart` in 2026 is more likely pasting v5.

**But that argument is answered by the target itself.** v5's option vocabulary is a **verified strict
subset** of v6's — zero options removed, two deprecated but still working. A v5 config pasted into a
v6-shaped control **parses and renders**. What differs is defaults (a `.tycss` skin) and two callback
contracts. The ecosystem argument is an argument for *accepting* v5 configs, which v6 gives free —
not for targeting v5.

And v5 is **not** a code-maturity argument: 6.1.0 contains all 329 v5 fixes. There is no settled v5
implementation to obtain; there is only a decision to skip parts of the same source.

**Delta:** −2 XL, −1 L, −2 M of Tier 2/3 work. Two Tier-0 contracts set wrong.

### (ii) Target ECharts 6 fully — build the v6-only subsystems on schedule

**Ships:** everything, including `matrix`, box-usage, axis breaks, `thumbnail` and `chord`.

**Deferred:** nothing.

**Permanently harder:** nothing structural — the *schedule* is the problem. You spend
**2 XL + 1 L + 2 M** on the 2.6 % of ECharts that has 16 demos to validate against, before cartesian
is finished. That contradicts the depth-first decision outright, and `matrix` + box-usage — the two
XLs — are the least likely things a first desktop release needs. It also front-loads exactly the
surface that is still churning (8 of v6.1's 37 fixes landed there).

**Delta:** +2 XL + 1 L + 2 M pulled into the early schedule, against no user-visible return.

### (iii) v6 option surface and foundations; v6-only subsystems deferred to a late tier

**Ships (milestone 1):** Tier 0 plus the cartesian slice of Tier 1, v6-shaped throughout — v6 option
names, v6 defaults, the v6 token vocabulary, the v6.1 callback semantics, `outerBounds` instead of
`containLabel`, the corrected `center` base.

**Deferred:** `matrix`, `coordinateSystemUsage:'box'`, axis breaks, `thumbnail`, `chord` — **exactly
where `10-gap-analysis.md` §5 already put them.** Nothing is pulled forward or pushed back. This is
not a compromise between (i) and (ii); it is the existing roadmap plus one Tier-0 design constraint.

**Permanently harder:** nothing — **provided two Tier-0 contracts are honoured**, and this is the
entire content of the decision:

1. **The coordinate-system interface must expose `DataToLayout(coord): TRect` alongside
   `DataToPoint`, and the box-layout solver must take a container-rect provider rather than the
   control's client rect.** Cost now: one parameter. Cost later: 19 call sites, every coord system's
   rect derivation, and the usage-kind injection path.
2. **The scale core must be built assuming value→coord may be piecewise-discontinuous.** Cost now: a
   break hook on the scale plus an interceptable tick generator. Cost later: rewrite `Interval`,
   `Log`, `Time`, `minorTicks`, `scaleMapper`, `axisHelper`, `AxisBuilder`.

Also adopt now at zero cost: the `registerCustomSeries` **string + `itemPayload`** shape (it is what
makes `custom` expressible in an option tree at all), and the two v6.1 semantic contracts (B6, B7).

**Extra cost over targeting v5, measured:** ~150 lines in one Tier-0 L, ~25 S-sized options, and a
different table of default constants. **Zero XL delta at milestone 1.**

**Precedent that the phasing works:** ECharts itself keeps `legacyContainLabel.ts` (120 lines) alive
*beside* the `outerBounds` solver. The two-phase structure is the same; the refinement can land later.

**Risks, stated honestly:**
- It buys the "ECharts 6" label without the v6 features for a long time. The honest public
  formulation is Q8's, versioned: *"the ECharts 6.1 option surface; matrix, chord, thumbnail and axis
  breaks are roadmap."*
- The v6-only surface is the least-demoed part of ECharts (16 of 606). When those items finally come
  up there is less to check against — and v6.2/6.3 may have changed them.
- B6 and B7 must be absorbed on day one, not later.

---

## 5. Recommendation

**Target the ECharts 6.1 option surface. Take the v6 defaults, the v6 token vocabulary and the v6.1
callback semantics from day one; honour the two Tier-0 contracts — a rect-returning coordinate-system
interface, and a scale core that tolerates piecewise-discontinuous mapping — and leave `matrix`,
`coordinateSystemUsage:'box'`, axis breaks, `thumbnail` and `chord` exactly where the roadmap already
put them, in Tiers 2 and 3.** That is option (iii). It rests on three facts. **First, v5's option
vocabulary is a verified strict subset of v6's** — zero options removed across both releases, two
deprecated but still working, and four of the five v6.0 breaks carry restore switches — so targeting
v6 costs no v5 compatibility, a pasted v5 config still parses and renders, and the "everyone knows
v5" argument (the only strong one for v5) is answered by the target itself; the look difference is
one `.tycss` skin, which is exactly what ECharts' own v5 compat shim is. **Second, every v6-only
*item* is Tier 2 or Tier 3** — the price of v6 inside the first shippable milestone is about 150
lines in one Tier-0 L (`outerBounds` instead of the deprecated `containLabel`), ~25 S-sized options
and one table of constants, while the saving from v5 is 2 XL + 1 L + 2 M of work nobody would start
this year. **Third, exactly two things in v6 cannot be retrofitted, and both land in phase 1 under
depth-first**: the `DataToLayout` rect contract (ECharts' own equivalent touches 19 call sites) and a
break-capable scale. Set those two right and everything else in v6 is take-it-or-leave-it later; set
them wrong and two capabilities are permanently priced out. Two supporting facts, not load-bearing
but real: maps are in scope, and v6 is precisely where `geo` got the corrected `center` percent base
(a v5 target ships the acknowledged-wrong one), `clip`, `roamTrigger`, `preserveAspect` and a unified
roam; and the option-tree API needs a named-handler shape for its ~30 function-valued options, which
`registerCustomSeries` + `itemPayload` supplies and v5 does not.

**Pin `6.1`, not `6`.** Transcribe axis math from 6.1.0 source — 6.1 refactored it.

### What would change this recommendation

- **A prototype showing the two contracts are expensive.** The whole recommendation rests on "one
  parameter now versus a 19-site refactor later". If the first spike — `cartesian2d` with
  `DataToLayout`, plus an `Interval` scale carrying a break-mapper stub — costs more than an L, the
  economics invert and (i) becomes right. **Test this before committing**, not after.
- **Evidence that pasted-config fidelity is the primary user need *and* that v6 defaults break it.**
  If real users paste v5 configs and the result reads wrong because the legend moved, the fix is a
  shipped `v5` skin plus a defaults switch — not a different target. Only if that proved impossible
  would the target itself move.
- **A v6.2 with another `[Break]` block on the cartesian surface.** Two breaking blocks in two
  releases is v6's base rate, and v5's minors did the same (5.2.0, 5.5.0), so it is cadence rather
  than instability. The response is to re-pin the validator, not to re-target — but if the axis-scale
  and roam refactors continue, delay transcribing that math until a release settles.
- **Maps leaving scope.** That removes the geo/roam argument. The two structural contracts still
  stand, so the recommendation survives — weakened, not reversed.
- **The option tree being abandoned for published properties.** That removes the
  `registerCustomSeries` argument and changes far more than the version target. Revisit the whole
  memo, not just this line.

---

## 6. What this changes in the roadmap

### 6.1 The revised Tier 0

`10-gap-analysis.md` §5's Tier 0 had 16 rows (2 S + 8 M + 4 L + 1 XL, after `11-critique.md` added
the painter vector API). The four decisions change it as follows: **`.lfm` compatibility is deleted**;
**the option tree, its catalog and its editor move in from Tier 3**; **three existing rows gain a
v6-shaped constraint**; and **two new S rows appear** (the callback registry, and the v6.1 semantics).

| Capability | Size | Why it is Tier 0 |
|---|---|---|
| Unit split — `AdvChart.Data` / `.Scale` / `.Coord` / `.Layout` / `.Series` / `.Catalog` / `.Complete`, all pure and headless-testable | **S** | Organisational, and it has to be first or `Chart.pas` repeats its own history at 1,721 lines |
| **Vector API on `TTyPainter`** — paths, arcs, polylines, winding and even-odd fill, dash/cap/join, affine transforms, push/pop clip, per-element alpha, gradients and patterns as first-class fills, rotated text, `path://`, `isPointInPath`; theme-aware and DPI-scaled | **L** | `11-critique.md` finding 2: `TTyPainter`'s public surface is chrome-shaped, with no path, arc, transform, clip or dash. Upstream of ~40 Tier 1/2 rows. Without it every series renderer reaches for `Bitmap.Canvas2D` and re-derives DPI scaling, theme resolution, the bidi text path and the non-Windows supersampling gate — the exact bug class this repo has already paid for |
| Windowed base (`TTyCustomControl`) plus real-machine verification on Win32/GTK/Qt | **M** | Decision settled; the verification half is not free. Repo memory: shadow corners, erase-to-parent `Color`, windowed-sibling clipping (invisible to `RenderTo`), swallowed `CM_*` |
| **Option tree: relaxed-JSON reader + model tree + merge semantics** — `normalMerge` / `replaceMerge` / `replaceAll`, id/name matching, index holes | **XL** | Q2 answered "option tree", so **this is the API**. ECharts spends ~3,729 lines on it (`Global` 1,100 + `OptionManager` 530 + `util/model` 1,444 + `Component` 396 + `Model` 259), with `replaceMerge` at 36 sites. FPC's stock `fcl-json` in relaxed mode (`joUTF8, joComments, joIgnoreTrailingComma`) already accepts unquoted keys, single quotes, trailing commas and comments — 40–50 % of real option literals paste verbatim, so no custom JSON5 lexer is needed for reading |
| **Generated option catalog** — `echarts-doc`'s own `build-doc.js` emits `option.json`; we emit a shared-shape Pascal DAG (~1,900 structural nodes, not 58,910 paths) carrying type, default, enum, numeric range, since-version and flags | **M** | Validation and completion are ours now that the compiler no longer type-checks the API. Generated, not hand-written: 79 % of nodes carry a `uiControl`, giving 11,248 enum sites (67 distinct lists), 17,998 numeric minima and 2,644 maxima for free. Precedent in-tree: `Css.Catalog.pas` 411 lines — the same machine one order of magnitude up |
| **Validating design-time editor** — path-dependent DAG completion, lazy reference tree (73 roots, expand on demand), a parser tolerant enough to read the `type` discriminator under `series[i]`, catalog-aware errors | **L** | The maintainer named it as part of the API decision. Precedent: `Design.Css.Editor` 351 + `Css.Complete` 360 + `Css.Catalog` 411 = 1,122 lines already deliver this over the `.tycss` vocabulary |
| **Named-handler registry + template strings** for the ~30 function-valued options | **S** | Q6 is load-bearing once the API is a tree: a closure cannot live in serialised text. Shape it like v6's `registerCustomSeries` + `itemPayload` (a 30-line registry): `renderItem: 'bubble'`, `formatter: '@MyFormatter'`, plus first-class `'{b}: {c}'` template strings — which alone cover 539 of the 968 function-unions |
| Columnar typed data store — dimensions (float/int/ordinal/time), **NaN as the no-data sentinel**, a per-point override side-table with Has-flags, per-point id/name, ordinal interning plus an inverted index | **XL** | 20 of 23 series types are unrepresentable without it. With no `.lfm` constraint, `'1,,3'` → `[1, NaN, 3]` by construction — Q3(i)/(ii) vanish |
| **Scale abstraction, break-capable** — ordinal / interval / log with `nice()` 1-2-3-5-10, minor ticks, `min`/`max`/`scale`/`splitNumber`/`interval`/`minInterval`/`maxInterval`/`boundaryGap`/`inverse`, degenerate extents, **`startValue` independent of `min`**, and a break hook so value→coord may be piecewise | **L** | The break hook is contract #2 from §4: retrofitting it means rewriting `Interval`, `Log`, `Time`, `minorTicks`, `scaleMapper`, `axisHelper`, `AxisBuilder` |
| **Coordinate-system interface with `DataToPoint` *and* `DataToLayout(coord): TRect`**, plus `cartesian2d` with N x/y axes and a master/sub split | **L** | Contract #1 from §4. `DataToLayout` is what `coordinateSystemUsage:'box'`, calendar-hosted charts, `custom`'s `api.layout()` and matrix all rest on. One signature now; ECharts' own equivalent touches 19 call sites |
| **Box layout solver taking a container-rect provider** (`left/top/right/bottom/width/height`; px, `'%'`, keywords), shared by every component | **M** | The other half of the same contract. If it is written against "the control's client rect", nesting is a rewrite |
| Two-phase axis build (estimate labels → shrink rect → determine), shaped as **`outerBounds` / `outerBoundsContain` / `nameMoveOverlap`** rather than `containLabel` | **L** | The substrate for label fitting under either target; ~150 lines more in the v6 form, and `containLabel` is the deprecated spelling |
| Series registry — per-series `Type` plus per-series axis binding | **M** | What unlocks mixed types and secondary axes; both are absent today by design |
| Element/paint list with `z`/`z2` ordering plus **one** shared hit-test path | **M** | Draw order is code order today; the TTySegmented single-hit-test-path rule, scaled up |
| Text measurement cache (per-font record, ASCII width table, string LRU) plus wrap/truncate/ellipsis wired to `TyWrapTextCJK` | **M** | Every layout pass measures text before it can commit a rect — and repo memory `cjk-wordwrap-space-only-trap` says a space-only wrap silently fails on CJK |
| 4-state style model (normal / emphasis / blur / select as a stack) with `focus: none\|self\|series` and `blurScope` | **M** | Retrofitting states into renderers written for one state means touching all of them |
| Style resolution — `itemStyle` / `lineStyle` / `areaStyle` full key sets → BGRA canvas state | **M** | Every series row consumes it |
| Chart theme typeKeys plus a **derived** chart ramp and the ~8-12 axis-domain tokens, in `themes/light.tycss` **and** `Css.Catalog.pas`, regenerated into `DefaultTheme.pas` / `BuiltinThemeData.pas`, **verified across all 17 skins**; fix the two orphan metrics (`--chart-donut-hole`, `--chart-hit-radius`) | **M** | Repo memory `variant-dies-under-skin-base-rule`: a skin writing *any* rule for a typeKey suppresses the whole base layer for it. A 12-token chart vocabulary is checkable across 17 themes; a 64-token one is not. Derive the ramp with the existing `darken()/lighten()/alpha()` — do **not** hard-code `#b7b9be` |
| `subPixelOptimize` — odd-line-width pixel-centre snapping | **S** | One helper, and it is the difference between crisp and fuzzy 1 px axis, grid and bar edges at desktop DPI |
| **v6.1 semantics baked into the contracts** — the callback parameter record carries `rawDataIndex`; the extent model keeps `startValue` independent of `min` | **S** | §3.3. Free on day one; a migration once handlers exist in user code |

**Totals: 2 XL + 5 L + 9 M + 4 S = 20 rows** (was 16). Net change from the four decisions: **−1 M**
(the `.lfm` layer, deleted), **+1 XL** (merge semantics, from Tier 3), **+1 L** (editor), **+1 M**
(catalog), **+2 S** (callback registry; v6.1 semantics), and **three rows re-specified** (coord
interface, box solver, scale) to carry the two contracts.

Also worth recording, since it is now settled: the ~1,950 hand-declared published properties implied
by Q2(a) **disappear**. Coverage scales by writing a resolver and generating a catalog, not by
declaring options one at a time.

### 6.2 §6 open questions — closed and still open

**CLOSED by the maintainer's decisions:**

| Q | Answer | Consequence now folded into the roadmap |
|---|---|---|
| **Q1** base class | **Windowed (`TTyCustomControl`)** | Unlocks dataZoom sliders, toolbox, focus, keyboard, MSAA. Makes Tier 1 dataZoom L, Tier 2 toolbox/brush/timeline, and Tier 3 thumbnail/designtime/dirty-rect all cheaper. The new real-machine costs are documented and target-neutral |
| **Q2** API style | **(b) Option tree**, with a validating design-time editor | Merge semantics move Tier 3 → Tier 0, still XL, and *are* the API. Validation is new: M (catalog) + L (editor). Q6 becomes load-bearing |
| **Q3** `.lfm` compatibility | **None — new control** | All four sub-questions collapse. `'1,,3'` → `[1, NaN, 3]` by construction; unparseable text → NaN; `ShowLegend` / `ShowGrid` / `ShowValues` / `ShowTooltip` need not exist; the 15 exported pure functions and the **67** tests in `tests/test.chart.pas` (§6 Q3(iv) says "~60"; the real count is 67) are not a contract. **This saving is identical under both version targets** |
| **Q4** maps | **In scope and important** | The geo XL, map-series L, View + RoamController L, lines M and geo-heatmap M all stay. *Sub-question still open — below* |
| **Q8** (second half) target version | **ECharts 6.1** — this memo | *Correction to carry back: Q8's "targeting 5 removes four XL items" is wrong. It removes **two** (matrix, `coordinateSystemUsage:'box'`). Universal transition/morphing is v5.0.0; geo is v2-era; the option-tree XL is target-independent* |
| **Q9** sequencing | **Depth-first** | Confirmed by report 02's own recommended build order. The two v6 contracts land in phase 1 (cartesian), not in a later "v6 features" phase |

**STILL OPEN:**

| Q | What remains |
|---|---|
| **Q4b** maps: engine or atlas? | "In scope" does not answer "do we ship map data". Recommendation: **engine yes, atlas no** — ECharts ships none either. Shipping an atlas means owning `src/coord/geo/fix/`'s **118 lines of territorial-dispute special-casing** (`nanhai.ts` 73 + `diaoyuIsland.ts` 45) and maintaining it as borders move. Mitigate the "the editor cannot preview a map" cost with a `registerMap` equivalent plus one small demo geometry — **S** |
| **Q5** dependency appetite | The SVG-path item is **retired** (BGRA's `addPath` handles the full grammar, elliptical arcs included). Two remain: `RegExpr` for the filter DSL's `reg` operator, and a vetted ISO-8601 / loose date parser for the time axis. **New third item:** node + npm as a *build-time* dependency for the catalog generator — not a runtime dependency, but a dependency of the build, needing a pinned `echarts-doc` commit and a drift test |
| **Q6** callback convention | The option tree forces the *shape* (named handlers in a registry, template strings, and a catalog-aware rejection message for a literal `function(...)`), but not the API: registry key naming, the parameter record's exact fields, and whether an `itemPayload`-style data record is supported. **~1,212 nodes accept a function**; `formatter` alone is 539 of them, and its template-string form covers those |
| **Q7** animation versus the repaint model | Untouched by the version decision. The windowed base makes options (a) and (c) cheaper — `Invalidate` no longer damages the parent's whole client area, which was the ~14.9 ms figure driving the question. `11-critique.md` finding 6 still stands: dirty-rect painting is filed in three contradictory tiers and needs one placement |
| **Q8** (first half) the public claim | Still open, and it now needs a version in it. Recommended: *"all of ECharts 6.1's charting and interaction capability, minus the browser-delivery layer, minus WebGL, minus the map-data ecosystem — with matrix, chord, thumbnail and axis breaks on the roadmap."* |
| **Q10** test strategy | Untouched, and now larger. Golden images still need a tolerance, an authoritative widgetset and a CI budget. **New:** the catalog needs a drift test in the shape of `tests/test.css.catalog.pas` — re-derive node, enum and per-root counts from a checked-in fingerprint, and fail when the emitted unit and the pinned `echarts-doc` commit disagree |
| **New — merge semantics detail** | `normalMerge` / `replaceMerge` / `replaceAll`, id/name matching, and the deliberate **index holes** left after replace-merge removal. XL, and it is the API. Decide before the first component model is written |
| **New — catalog scope** | Does the generated catalog emit the full v6 tree, or a filtered subset? The `partial-version` markers survive into the generated JSON (1,024 nodes at `6.0.0`, 89 at `6.1.0`), so one generator can emit either. Filtering to what is implemented gives honest completion; emitting everything with an `ofUnimplemented` flag gives honest documentation |
| **New — ship the v6 palette as the default series colours?** | Free, and it is the part users recognise. Two caveats: it is **9** colours, not the current 8; and slot 3 `#505372` is a dark slate that reads as "one series is greyed out" unless the whole ramp is adopted together |

---

## Appendix — the numbers this memo rests on

| Claim | Value | Source |
|---|---|---|
| v6 line length | 2 releases, 19 months, 128 changelog lines | `en/changelog.md:1-128` |
| v6 features / fixes / breaks | 37 / 59 / 8 | reports 12 §8, 15 §0 |
| Options removed 5 → 6 | **0** (0 series, 0 components, 0 actions, 0 events, 0 API methods) | report 15 §4 |
| Deprecations introduced in v6 | **2** (`grid.containLabel`, `line.triggerLineEvent`) | report 15 §6a |
| New option-path shapes outside matrix/thumbnail/chord | **119** (~270 including them) | report 12 §4 |
| v6-only dedicated source | ~6,100 lines: matrix 2,677 · breaks 1,803 · chord 1,200 · thumbnail 706 · box ~250 · jitter 289 · registry 30 | reports 13 §0, 16 §1.1 |
| v6-only demo coverage | **16 of 606** `test/*.html` (2.6 %) | reports 12 §8, 16 §3 |
| Token file | 233 lines, 64 colour + 8 size tokens, 191 call sites in 55 files | report 14 §1 |
| `theme/v5.js` (the "v5 look") | 581 lines, 33–34 top-level keys, 110 hex literals | reports 14 §7, 15 §2 |
| `containLabel` versus `outerBounds` | 120 lines (`legacyContainLabel.ts`) versus ~276 | report 16 §2.5 |
| `createBoxLayoutReference` call sites | **19+** | report 16 §4.3 |
| Break references in the scale layer | `Time` 36 · `AxisBuilder` 36 · `scaleMapper` 26 · `axisHelper` 25 · `Interval` 24 · `Log` 21 · `minorTicks` 10 | report 13 §0 |
| Option catalog size | 58,910 expanded paths → **1,858 distinct structural subtrees** | report 17 §4 |
| Prototype catalog unit | 2,512 lines, 0.3 s compile, 997 KB `.o` (FPC 3.2.2) | report 17 §8 |
| Real option literals parsed by stock relaxed `fcl-json` | 422 / 1,065 (39.6 %); 420 / 827 (50.8 %) of the function-free ones | report 17 §9 |
| Tests in `tests/test.chart.pas` | **67** unique procedures, 1,296 lines | report 16 §2.1 |
| ECharts + zrender true size | 138,362 + 31,477 ≈ **169,800** lines of TypeScript | `11-critique.md` finding 1 |
