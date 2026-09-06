# The ECharts 6 visual overhaul — tokens, palette, chrome, dark mode

Sources read: `D:/Projects/echarts` @ 6.1.0 (`package.json:version`), `D:/Projects/zrender` @ 6.1.0,
`D:/Projects/echarts-doc` @ `94fdd2f`. Every claim below cites `file:line` or a changelog entry.
Prior reports 01–11 are assumed read; this one does not repeat the capability survey.

---

## 0. Verdict up front

1. **ECharts 6's "design token system" is a source-code de-duplication refactor, not a theming API.**
   `src/visual/tokens.ts` is a plain module-level constant. It is not exported from any public entry
   (`grep tokens src/export/*.ts` → 0 hits), `ThemeOption` is `Dictionary<any>`
   (`src/util/types.ts:926`), and `mergeTheme` (`src/model/Global.ts:1018-1040`) merges a theme *option
   tree* over the defaults. **A theme cannot set a token.** It must still restate every value, per
   component, exactly as in v5. `theme/v5.js` — the officially shipped "restore the old look" theme —
   is 581 lines, 34 top-level sections, 110 hex literals, and proves it.
2. **ty-controls' `.tycss` is the strictly more capable model** on the axis that matters: it is a
   *runtime, user-authorable, seed→derive* system. ECharts 6 has a *compile-time, closed, fully
   enumerated ramp*. Do not adopt. **Mirror one specific idea** (the neutral/accent ramp as a
   derivation source) and **ignore the rest**. Argued in §9.
3. **The v6 look is a real, silent break.** New 9-colour palette, new default layout (legend at the
   bottom, title centred, wider grid margins), visible tooltip border where v5 had none, softer axis
   furniture. Changelog v6.0.0 `[Break]` block, `en/changelog.md:124`.
4. **Do not trust `echarts-doc` for default values.** At doc HEAD, `en/option/option.md:69` still
   documents the *v5* palette as the default, `en/option/component/legend.md:92` still says
   `itemGap = 10` (source says 8), and `en/option/partial/tooltip-common.md:433` still carries the
   *v4* tooltip background `rgba(50,50,50,0.7)`. Read the source.

---

## 1. `src/visual/tokens.ts` — full anatomy

233 lines total, ~110 of them declarations. Three top-level groups (`interface Tokens`, lines 90-103):
`color`, `darkColor`, `size`. **That is the whole vocabulary.** There is no typography group, no
radius group, no motion group, no elevation group, no stroke-width group.

### 1.1 The colour ramps (lines 111-169)

| group | count | values |
|---|---|---|
| `theme` | 9 | the categorical palette — see §2 |
| `neutral00…neutral99` | 21 | `#fff`, `#f4f7fd`, `#e8ebf0`, `#dbdee4`, `#cfd2d7`, `#c3c5cb`, `#b7b9be`, `#aaacb2`, `#9ea0a5`, `#929399`, `#86878c`, `#797b7f`, `#6d6e73`, `#616266`, `#54555a`, `#48494d`, `#3c3c41`, `#303034`, `#232328`, `#17171b`, `#000` |
| `accent05…accent95` | 19 | `#eff1f9`, `#e0e4f2`, `#d0d6ec`, `#c0c9e6`, `#b1bbdf`, `#a1aed9`, `#91a0d3`, `#8292cc`, `#7285c6`, `#6578ba`, `#5c6da9`, `#536298`, `#4a5787`, `#404c76`, `#374165`, `#2e3654`, `#252b43`, `#1b2032`, `#121521` |

Naming is `<family><lightness×100>`, ascending = darker (`neutral00` = white, `neutral99` = black).
The neutral ramp is a *blue-tinted* grey (hue drifts from `#f4f7fd` at the top to a neutral black),
not a pure grey. The accent ramp is a desaturated indigo, hue-locked to the first palette colour.

**The steps are hand-written literals, not computed.** There is no `lighten()`/`darken()` function
generating them — 40 hex strings are typed out.

### 1.2 The semantic aliases (lines 171-197, assigned via `extend`)

25 names, every one of them a pointer into a ramp or a literal `rgba()`:

| token | = | resolved light value |
|---|---|---|
| `primary` | `neutral80` | `#3c3c41` |
| `secondary` | `neutral70` | `#54555a` |
| `tertiary` | `neutral60` | `#6d6e73` |
| `quaternary` | `neutral50` | `#86878c` |
| `disabled` | `neutral20` | `#cfd2d7` |
| `border` | `neutral30` | `#b7b9be` |
| `borderTint` | `neutral20` | `#cfd2d7` |
| `borderShade` | `neutral40` | `#9ea0a5` |
| `background` | `neutral05` | `#f4f7fd` |
| `backgroundShade` | `neutral10` | `#e8ebf0` |
| `axisLine` | `neutral70` | `#54555a` |
| `axisLineTint` | `neutral40` | `#9ea0a5` |
| `axisTick` | `neutral70` | `#54555a` |
| `axisTickMinor` | `neutral60` | `#6d6e73` |
| `axisLabel` | `neutral70` | `#54555a` |
| `axisSplitLine` | `neutral15` | `#dbdee4` |
| `axisMinorSplitLine` | `neutral05` | `#f4f7fd` |

Six more are `rgba()` literals rather than ramp pointers: `backgroundTint rgba(234,237,245,0.5)`,
`backgroundTransparent rgba(255,255,255,0)`, `transparent rgba(0,0,0,0)`, `shadow rgba(0,0,0,0.2)`,
`shadowTint rgba(129,130,136,0.2)`, `highlight rgba(255,231,130,0.8)`.

Note the layering: a **generic tier** (`primary`…`disabled`) plus a **domain tier** (`axis*`). The
domain tier exists only for axes — there is no `legend*`, `tooltip*`, `grid*` tier. Everything else
reaches into the generic tier or straight into a ramp step.

**64 colour tokens are declared; 37 distinct names are actually referenced anywhere in `src/`.**
27 declared tokens (mostly mid-ramp steps and `axisLineTint`) have zero call sites — they exist as a
palette for future/3rd-party use, not because anything consumes them.

### 1.3 The size scale (lines 222-231)

```
xxs 2   xs 5   s 10   m 15   l 20   xl 30   xxl 40   xxxl 50
```

Eight steps, roughly 2→5→×2→×1.5. **Used in exactly 14 places** in the whole codebase: treemap layout
inset ×5 (`TreemapSeries.ts:254-257,285`), `legend.bottom` (`LegendModel.ts:460`), `title.top`
(`title/install.ts:118`), `timeline.padding` (`TimelineModel.ts:320`), `toolbox.padding`+`itemGap`
(`ToolboxModel.ts:168,172`), `visualMap.padding` (`VisualMapModel.ts:696`), calendar day/month/year
label margins (`CalendarModel.ts:231,241,256`).

Every other spacing number in the codebase — `legend.itemGap: 8`, `legend.padding: 5`,
`axisLabel.margin: 8`, `axis.nameGap: 15`, `grid.top: 65`, `tooltip padding 10` — is still a bare
literal. **The size scale covers ~10 % of the spacing surface.**

### 1.4 What is *not* tokenized

- **Typography.** No token holds a font family, size, or weight. `globalDefault.textStyle`
  (`globalDefault.ts:86-95`) hard-codes `fontSize: 12` / `normal` / `normal` and picks the family by
  sniffing `navigator.platform` (`'Microsoft YaHei'` on Windows else `'sans-serif'`) — **browser-bound**,
  no Pascal analogue. Per-component sizes are literals: title 18/bold (`title/install.ts:130-131`),
  subtitle 12, tooltip 14 (`TooltipModel.ts:161`), axis label 12 (`axisDefault.ts:95`), calendar year
  label 20/bolder (`CalendarModel.ts:258-260`), legend selectorLabel 12 (`LegendModel.ts:517`).
- **Corner radius.** 7 literals, 0 tokens: tooltip 4 (`TooltipModel.ts:140`), axisPointer.label 3
  (`AxisPointerModel.ts:124`), legend.selectorLabel 10 (`LegendModel.ts:512`), legend 0 (`:466`),
  toolbox 0 (`ToolboxModel.ts:164`), dataZoom 0 (`SliderZoomModel.ts:166`), bar 0 (`BarSeries.ts:157`).
- **Shadow/elevation.** Tooltip shadow is 4 literals (`TooltipModel.ts:133-136`). `tokens.color.shadow`
  exists but has 3 call sites.
- **Line widths, opacities, animation.** All literal.

### 1.5 How components consume tokens

**55 source files import `../visual/tokens`** (`grep -rl "visual/tokens" src/`). The pattern is
uniform and shallow: a `static defaultOption` object assigns `tokens.color.X` at *module evaluation
time*.

```
LegendModel.ts:463    backgroundColor: tokens.color.transparent,
LegendModel.ts:464    borderColor: tokens.color.border,
```

Three consequences that matter for a port. **(1) Resolution is at import time, not paint time** — the
token graph freezes when the bundle loads; `echarts.setTheme()` (`src/core/echarts.ts:827`) re-merges
the option tree, it does not re-resolve tokens. **(2) There is no cascade** — no selector, no state, no
variant; `emphasis` is a hand-written nested option naming a *different ramp step* (toolbox icon
`accent50` rest → `accent70` emphasis, `ToolboxModel.ts:175,180`). **(3) Reference frequency is heavily
skewed** — `neutral00` 25×, `primary` 16×, `border` 13×, `secondary`/`neutral99` 10× each, long tail;
177 colour + 14 size references = **191 call sites** for a 64+8-token vocabulary.

### 1.6 vs. v5's per-component defaults

In v5 every component default carried its own hex literal. v6 replaced those literals with named
references into one ramp file *and* **retuned** them — the new values are not the old values
renamed, which is why `theme/v5.js` has to exist. Honest one-line summary:

> v5: 200-odd scattered hex literals. v6: 191 references into 64 named colours + 8 sizes, all still
> resolved statically at build time, still not reachable from a theme.

---

## 2. The default palette

v5: `theme/v5.js:44-53` (still documented as current at `echarts-doc/en/option/option.md:69`).
v6: `src/visual/tokens.ts:112-122`, wired at `src/model/globalDefault.ts:41`.

| # | v5 hex | v5 | v6 hex | v6 |
|---|---|---|---|---|
| 1 | `#5470c6` | indigo | `#5070dd` | indigo (near-identical, more saturated) |
| 2 | `#91cc75` | green | `#b6d634` | lime |
| 3 | `#fac858` | yellow | `#505372` | **slate** — a dark neutral-violet, a new kind of entry for a categorical palette |
| 4 | `#ee6666` | red | `#ff994d` | orange |
| 5 | `#73c0de` | sky | `#0ca8df` | cyan |
| 6 | `#3ba272` | teal-green | `#ffd10a` | amber |
| 7 | `#fc8452` | orange | `#fb628b` | rose |
| 8 | `#9a60b4` | purple | `#785db0` | violet |
| 9 | `#ea7ccc` | pink | `#3fbe95` | mint |

Both are 9 colours. The v6 set is markedly **higher-chroma** (`#ffd10a`, `#b6d634`, `#0ca8df` are
near-pure) with one deliberately dark, low-chroma anchor at position 3. Series 1 is the only slot
that survives essentially unchanged.

**Derived palette values:**
- `gradientColor` (the default continuous `visualMap` ramp): v5 `['#f6efa6','#d88273','#bf444c']`
  (`theme/v5.js:82`) → v6 `[modifyHSL(theme[0], l=0.9), theme[0]]` = **`['#d4dcf7', '#5070dd']`**
  (`globalDefault.ts:31-43`; second value computed with zrender's own HSL math). Three-stop
  yellow→red becomes two-stop pale-blue→indigo.
- `visualMap.contentColor` = `tokens.color.theme[0]` (`VisualMapModel.ts:693`), v5 `#5793f3`
  (`theme/v5.js:577`).
- Dark-theme palette is a **different, hand-written set**: `#4992ff #7cffb2 #fddd60 #ff6e76 #58d9f9
  #05c091 #ff8a45 #8d48e3 #dd79ff` in the legacy `theme/dark.js:70-79`, but the built-in
  `src/theme/dark.ts:71` uses `tokens.darkColor.theme` which is `color.theme.slice()` — i.e. **the
  light palette unchanged** (`tokens.ts:202-204` explicitly comments *"Don't modify theme colors."*).

---

## 3. Typography and default sizing

| what | v5 | v6 | source |
|---|---|---|---|
| title color | `#464646` | `tokens.color.primary` `#3c3c41` | `v5.js:528` vs `install.ts:132` |
| subtitle | 12 / `#6E7079` | 12 / `quaternary` `#86878c` | `v5.js:530` vs `install.ts:135-136` |
| axisLabel fontSize | (inherit 12) | **12, now pinned explicitly** | `axisDefault.ts:95` |
| axisLabel color | `null` = inherit global | `tokens.color.axisLabel` `#54555a` | `v5.js:64` vs `axisDefault.ts:96` |
| axisLabel textMargin | — | **new `[0, 3]`** | `axisDefault.ts:102` |
| legend textStyle color | `#333` | `secondary` `#54555a` | `v5.js:452` vs `LegendModel.ts:485` |
| legend itemGap | 10 | **8** | `v5.js:429` vs `LegendModel.ts:469` |
| tooltip text color | `#666` | `tertiary` `#6d6e73` | `v5.js:550` vs `TooltipModel.ts:160` |
| toolbox itemGap | 8 | **10** (`size.s`) | `v5.js:540` vs `ToolboxModel.ts:172` |
| toolbox padding | 5 | **15** (`size.m`) | `v5.js:539` vs `ToolboxModel.ts:168` |
| timeline padding | 5 | **15** (`size.m`) | `v5.js:466` vs `TimelineModel.ts:320` |
| visualMap padding | 5 | **15** (`size.m`) | `v5.js:575` vs `VisualMapModel.ts:696` |
| line series symbolSize | 4 | **6** | `v5.js:180` vs `LineSeries.ts:202` |
| bar `defaultBarGap` | `'20%'` | **`'10%'`** | `v5.js:95` vs `BaseBarSeries.ts:220` |
| pie radius | `[0,'75%']` | **`[0,'50%']`** | `v5.js:193` vs `PieSeries.ts:229` |
| pie labelLine length2 | 15 | **30** | `v5.js:195` vs `PieSeries.ts:293` |

Unchanged: global 12px/normal/normal (`globalDefault.ts:90-94`, family still platform-sniffed and
**browser-bound**), title 18/bold (`title/install.ts:130-131`), tooltip 14 (`TooltipModel.ts:161`),
axisLabel margin 8 / axis nameGap 15 (`axisDefault.ts:93,47`), legend item 25×14 (`LegendModel.ts:470`).

**Reading:** typography barely moved. What moved is **spacing** — every component that got a
`size.*` token got *three times* the padding it had. That, plus the layout changes in §5, is what
makes a v6 chart "look airier" at a glance.

---

## 4. Component chrome, v5 → v6

Values on the left are what `theme/v5.js` restores (therefore what v5 had); values on the right are
read from v6 source, with the resolved hex in brackets.

### Tooltip (`TooltipModel.ts:129-162` vs `v5.js:551-563`)
- background `#fff` → `neutral00` `#fff` — unchanged.
- `borderWidth: 1` in both, but **`defaultBorderColor` `#fff` → `tokens.color.border` `#b7b9be`**.
  In v5 the border existed and was invisible; in v6 **the tooltip has a visible grey outline**.
- shadow unchanged (blur 10, `rgba(0,0,0,.2)`, offset 1/2) — `TooltipModel.ts:133-136`.
- radius 4 unchanged.
- `padding: null` resolving to **10** (html) / **[8,10]** (richText) —
  `tooltipMarkup.ts:497-508`. Doc still claims 5 (`tooltip-common.md:461`).
- `axisPointer.crossStyle.color` `#999` → `borderShade` `#9ea0a5`, still `dashed`.
- new option `displayTransition` (changelog v6.0.0, browser-bound CSS transition on the DOM tooltip).

### Legend (`LegendModel.ts:456-540` vs `v5.js:424-463`)
- **position: `top: 0` → `bottom: tokens.size.m` (15), `left: 'center'`.** This is the single most
  visible v6 change and is called out by name in the changelog (`en/changelog.md:124`).
- `itemGap` 10 → 8; `padding` 5 unchanged; `borderRadius` 0 unchanged; `borderWidth` 0 unchanged.
- `inactiveColor`/`inactiveBorderColor` `#ccc` → `disabled` `#cfd2d7`.
- `lineStyle.inactiveWidth: 2`, `inactiveBorderWidth: 'auto'` — v6 additions.
- `selectorLabel` radius 10 / padding `[3,5,3,5]` / fontSize 12 / `tertiary` on `border` (`:510-518`),
  v5 was flat `#666` with `#eee`-on-`#666` emphasis (`v5.js:454-461`); page icons v5 `#2f4554`/`#aaa`
  (`v5.js:461-462`) → `neutral00` fill in the view (`LegendView.ts:702`).

### Axes (`axisDefault.ts` vs `v5.js:55-78, 271-289`)
| | v5 | v6 |
|---|---|---|
| axisLine color | `#6E7079` | `axisLine` `#54555a` (darker) |
| axisLabel color | `null` (inherit) | `axisLabel` `#54555a` (pinned) |
| splitLine color | `#E0E6F1` | `axisSplitLine` `#dbdee4` (warmer/darker) |
| minorSplitLine | `#F4F7FD` | `axisMinorSplitLine` `#f4f7fd` (same value, now named) |
| splitArea | `['rgba(250,250,250,0.2)','rgba(210,219,238,0.2)']` | `[backgroundTint rgba(234,237,245,0.5), backgroundTransparent rgba(255,255,255,0)]` |
| categoryAxis axisTick.show | `true` | **`'auto'`** (`axisDefault.ts:164`) |
| radar axisName / axisLine | `#bbb` | `axisLabel` `#54555a` / `neutral20` `#cfd2d7` (`RadarModel.ts:213,232`) |

Plus a wholly new axis-furniture family with its own defaults: **axis break** —
`breakArea` (`axisDefault.ts:123-139`: white fill, `border` dashed `[3,3]`, opacity .6, zigzag
amplitude 4 / span 4-20) and `breakLabelLayout`. No v5 analogue.

### Grid (`GridModel.ts:130-142` vs `v5.js:417-422`)
- `left '10%' → '15%'`, `top 60 → 65`, `bottom 70 → 80`, `right '10%'` unchanged.
- `borderColor` `#ccc` → `neutral30` `#b7b9be`.
- **new**: `outerBoundsMode: 'auto'`, `outerBounds {0,0,0,0}`, `outerBoundsContain: 'all'`,
  `outerBoundsClampWidth/Height '25%'` (`GridModel.ts:34-35,133-140`). This is the anti-overflow
  layout engine — it *moves the plot rect* whenever labels or axis names would clip, so a v6 chart's
  grid rect is data-dependent in a way v5's was not. Changelog v6.0.0 lists it as a break; opt out
  with `grid.outerBoundsMode: 'none'`.
- `containLabel` is deprecated in favour of it (`echarts-doc/en/option/component/grid.md:41`).

### dataZoom slider (`SliderZoomModel.ts:159-233` vs `v5.js:341-389`)
- `borderRadius 3 → 0`; `borderColor #d2dbee → accent10 #e0e4f2`.
- data shadow: `#d2dbee` → `accent30 #a1aed9` line / `accent20 #c0c9e6` area (opacity .2 unchanged).
- selected shadow: `#8fb0f7` → `accent40 #8292cc` / `accent20`, area opacity **.2 → .3**.
- handles: fill `#fff` → `neutral00`, border `#ACB8D1` → `accent20 #c0c9e6`, emphasis `#8FB0F7` →
  `accent40`; move handle `#D2DBEE` @ .7 → `accent40 #8292cc` @ **.5** (emphasis .8).
- brush select fill `rgba(135,175,274,0.15)` → `accent30 #a1aed9` @ .3.
- **`defaultLocationEdgeGap 7 → 15`** — the slider sits twice as far from the plot.
- v6.0.0 also changed the move-handle cursor to `default` (changelog `[Fix]`), and 6.1.0 added
  `cursorGrab`/`cursorGrabbing` for inside-zoom.

### axisPointer (`AxisPointerModel.ts:103-155` vs `v5.js:290-309`)
- line `#B9BEC9` → `border #b7b9be` (near-identical), still 1px dashed.
- shadow band `rgba(210,219,238,0.2)` → `shadowTint rgba(129,130,136,0.2)` — greyer, no blue.
- **label chip: background `'auto'` (= axis line colour) → fixed `accent60` `#536298`**, text
  `neutral00` white, radius 3, padding `[5,7,5,7]`. In v5 the chip took the axis colour; in v6 it is
  always indigo.
- handle: `#333` → `accent40 #8292cc`, and **the v5 drop shadow (blur 3, `#aaa`, offset 0/2) is
  gone** — v6 declares no shadow on the handle.

### Toolbox / brush / timeline / calendar / visualMap
- toolbox icon rest `#666` → `accent50 #6578ba`; emphasis `#3E98C5` → `accent70 #404c76`
  (`ToolboxModel.ts:175,180`). 6.1.0 `[Fix]` notes emphasis had collided with the rest colour.
- brush fill `rgba(210,219,238,0.3)` / border `#D2DBEE` → `backgroundTint` / `borderTint #cfd2d7`;
  `defaultOutOfBrushColor #ddd` → `disabled #cfd2d7` (`BrushModel.ts:143-150`).
- timeline: control/checkpoint colours move onto the accent ramp (`SliderTimelineModel.ts:57-140`);
  v5's `#316bf3` checkpoint with a 2px white ring and a drop shadow (`v5.js:481-489`) is gone.
- calendar: `dayLabel.margin '50%' → 10`, `monthLabel.margin 5 → 10`, splitLine `#000` →
  `axisLine #54555a`, item border `#ccc` → `neutral10 #e8ebf0` (`CalendarModel.ts:210-260`).
- visualMap: border `#ccc` → `borderTint`, content `#5793f3` → `theme[0] #5070dd`, inactive `#aaa` →
  `disabled`, text `#333` → `secondary` (`VisualMapModel.ts:691-703`).

### Map / geo — relevant because maps are in scope
| | v5 (`v5.js:199-249, 391-416`) | v6 (`MapSeries.ts:342-368`, `GeoModel.ts:208-254`) |
|---|---|---|
| area fill | `#eee` | `background` `#f4f7fd` (map) / `backgroundTint` (geo default item) |
| region border | `#444` | `border` `#b7b9be` — **much lighter** |
| label | `#000` | `tertiary` `#6d6e73` |
| emphasis label | `rgb(100,0,0)` | `primary` `#3c3c41` |
| emphasis area | `rgba(255,215,0,0.8)` gold | `highlight` `rgba(255,231,130,0.8)` — paler, warmer |
| select | same as emphasis | same as emphasis |

### Other series worth noting
- `select.itemStyle.borderColor` `#212121` on 8 series (bar/boxplot/funnel/graph/heatmap/pictorialBar/
  sankey/scatter) → `primary #3c3c41`.
- graph link `#aaa` → `neutral50 #86878c`; sankey `#314656` → `neutral50`; tree `#ccc` → `borderTint`.
- gauge: axisLine `#E6EBF8` → `neutral10`; ticks `#63677A` → `axisTick #54555a`; anchor ring `#5470c6`
  → `theme[0] #5070dd`; detail border `#ccc` → `neutral40` (`GaugeSeries.ts:225-320`).
- treemap: v5 `center/middle, 80%×80%` (`v5.js:252-256`) → fixed insets `left/right 20, top/bottom 50`
  (`TreemapSeries.ts:254-257`), breadcrumb `top:'bottom'` → `bottom: 15`. Funnel box `bottom 60 → 65`.

---

## 5. The layout changes are the real "new look"

Aggregate the position deltas and the v6 default chart is a different composition:

```
v5:  title  left:0    top:0        legend  top:0            grid  10% / 60 / 10% / 70
v6:  title  center    top:15       legend  center bottom:15  grid  15% / 65 / 10% / 80
```

Plus `grid.outerBoundsMode: 'auto'` shifting the plot rect to prevent label/name overflow, and
`axisLabel.nameMoveOverlap` preventing name↔label collision. Both are on by default and both are
listed as breaks (`en/changelog.md:126`). For a Pascal port this is the most *portable* part of the
overhaul — it is arithmetic, not rendering.

---

## 6. Dark mode

Three separate mechanisms, easily confused:

**(a) `option.darkMode`** — `'auto' | true | false`, default `'auto'`
(`globalDefault.ts:36`, typed `src/util/types.ts:801`). If not `'auto'` it is forwarded to
`zr.setDarkMode()` (`src/core/echarts.ts:1930-1932`). In `'auto'`, zrender infers it from the
canvas background luminance: `lum(backgroundColor, 1) < 0.4`
(`zrender/src/zrender.ts:43-60`, `DARK_MODE_THRESHOLD` at `zrender/src/config.ts:26`; gradients are
averaged over their stops).

**What it actually controls is tiny.** `zr.isDarkMode()` has exactly three consumers:
`Element.getOutsideFill()` picks `LIGHT_LABEL_COLOR '#ccc'` vs `DARK_LABEL_COLOR '#333'`
(`zrender/src/Element.ts:782`, constants at `zrender/src/config.ts:31,36`);
`Element.getOutsideStroke()` composites the halo against black instead of white (`:786-798`); and
`Path.ts:294-297` decides whether an auto label needs a contrast stroke. **`darkMode` does not flip
any token and does not restyle any component.** It is an auto-label-contrast switch.

**(b) `tokens.darkColor`** — a *build-time* mirror of the whole ramp, computed once by a loop at
`tokens.ts:199-219` using `modifyHSL`:

- `theme` (the 9 palette colours): copied verbatim, no transform (`:202-204`).
- `highlight`: special-cased, alpha .8 → .4 (`:206-207`).
- `accent*`: `s → s × 0.5`, `l → min(1, 1.3 − l)` (`:209-212`).
- everything else: `s → s × 0.9`, `l → 1 − l^1.5` (`:214-217`).

Computed values (replicating zrender's `rgba2hsla`/`hsla2rgba`, `zrender/src/tool/color.ts:281-364`):

| token | light | dark |
|---|---|---|
| `neutral00` | `#ffffff` | `#000000` |
| `neutral05` (= `background`) | `#f4f7fd` | `#040810` |
| `neutral15` (= `axisSplitLine`) | `#dbdee4` | `#282c34` |
| `neutral20` (= `disabled`,`borderTint`) | `#cfd2d7` | `#3a3e44` |
| `neutral30` (= `border`) | `#b7b9be` | `#5b5e64` |
| `neutral40` (= `borderShade`) | `#9ea0a5` | `#7a7d83` |
| `neutral60` (= `tertiary`) | `#6d6e73` | `#b3b4b7` |
| `neutral70` (= `secondary`,`axisLine`,`axisLabel`) | `#54555a` | `#cbcbce` |
| `neutral80` (= `primary`) | `#3c3c41` | `#dfdfe1` |
| `neutral99` | `#000000` | `#ffffff` |
| `accent10` / `accent50` / `accent70` | `#e0e4f2` / `#6578ba` / `#404c76` | `#4e5777` / `#afb5c9` / `#eeeff3` |
| `shadow` | `rgba(0,0,0,0.2)` | **`rgba(255,255,255,0.2)`** (a white glow) |
| `shadowTint` | `rgba(129,130,136,0.2)` | `rgba(157,158,162,0.2)` |
| `backgroundTint` | `rgba(234,237,245,0.5)` | `rgba(16,20,30,0.5)` |
| `highlight` | `rgba(255,231,130,0.8)` | `rgba(255,231,130,0.4)` |

Two flaws worth naming, because they are the kind of thing a naive "invert the ramp" port
reproduces: **`accent80`, `accent85`, `accent90`, `accent95` all collapse to `#ffffff`** (the
`min(1, 1.3 − l)` clamp saturates for any `l ≤ 0.3`) — 4 of 19 dark accent steps are
indistinguishable. And the `1 − l^1.5` curve is not symmetric, so the dark ramp is *not* the light
ramp reversed: `neutral05` → `#040810` is near-black while `neutral95` → `#f7f7f8` is near-white,
which is fine, but `neutral45`↔`neutral50` (`#898a90`/`#98999d`) nearly collide in the middle.

**(c) The `dark` theme** (`src/theme/dark.ts`, 320+ lines, registered at
`src/core/echarts.ts:3428`). This is the only thing that actually consumes `darkColor`: it is a
hand-written option tree that reads `tokens.darkColor` and restates ~90 component values
(`darkMode: true`, `backgroundColor: color.background` = `#040810`, then legend/title/tooltip/
dataZoom/visualMap/timeline/calendar/matrix/axes/gauge/candlestick/funnel/radar/treemap/sunburst/
map/geo). **Token flipping does not happen automatically — someone wrote the mirror theme by hand,
and it is exactly as long as any other theme.**

Note the collision: the standalone `theme/dark.js:223` also registers the name `'dark'`, but with
the *legacy* v5 dark theme (`#100C2A` purple background, `#B9B8CE` text, a different 9-colour
palette at `theme/dark.js:70-79`). Loading that file silently replaces the built-in.

---

## 7. The shipped themes in `D:/Projects/echarts/theme/`

**36 `.js` files.** Classification by content, not by name:

| class | count | files | evidence |
|---|---|---|---|
| **v6-era, purpose-built** | 1 | `v5.js` | 581 lines, references v6-only keys (`defaultBorderColor`, `defaultItemStyleColor`, `defaultLocationEdgeGap`, `minorSplitLine`, `breadcrumb`), registers `'v5'` (`:84`) |
| **v5-era, migrated** | 2 | `rainbow.js` (63 ln), `vintage.js` (63 ln) | palette + `colorLayer` only; changelog v6.0.0 says v5's `src/theme/light.ts` became `theme/rainbow.js` (`en/changelog.md:125`) |
| **v5-era dark** | 1 | `dark.js` (224 ln) | uses current keys (`minorSplitLine.lineStyle`, `darkMode: true`) but v5 palette/colours |
| **legacy (ECharts 2/3 shaped)** | 32 | everything else | still emit removed option keys |

The legacy verdict is testable: 32 of the 36 files still write at least one option key that no longer
exists in v6 — `dataZoom.dataBackgroundColor`, `dataZoom.handleColor`, `graph.linkStyle`, `toolbox.color`
(an ECharts-2 icon-colour array). `azul.js:93-97` sets `dataZoom: { dataBackgroundColor, fillerColor,
handleColor }` and only `fillerColor` still does anything. Per file: 3 such keys in 22 files, 2 in 7,
1 in `roma.js`/`v5.js`, 0 in `dark.js`/`rainbow.js`/`vintage.js`.

**None of the 36 theme files reference tokens.** They cannot — tokens are not exported. Conclusion:
**the token refactor did not reach the shipped theme pack at all.** It changed the built-in defaults
and `src/theme/dark.ts`, and nothing else.

---

## 8. Changelog: default-value changes and silent visual breaks

The changelog carries only **3 `[Break]` blocks** in 2166 lines. The v6.0.0 one
(`en/changelog.md:123-128`) is the visual one, and every bullet is a silent break — nothing throws,
nothing warns, the chart just looks different:

| # | break | escape hatch |
|---|---|---|
| 1 | "The default theme has been changed, including the visual style and the default location settings of components and series. For example, the default legend position is now at the bottom" | load `echarts/theme/v5.js` |
| 2 | v5's `src/theme/light.ts` moved to `theme/rainbow.js` | rename in user code |
| 3 | Cartesian axes shift because anti-overflow + anti-label/name-overlap are on | `grid.outerBoundsMode: 'none'`, `axisLabel.nameMoveOverlap: false` |
| 4 | percent base of `center` on `geo`/`map`/`graph`/`tree` changed | `legacyViewCoordSysCenterBase: true` |
| 5 | label `rich` styles now inherit the plain label style (fontStyle/Weight/Size/Family + 4 textShadow props) | `richInheritPlainLabel: false` |

The v6.1.0 block (`en/changelog.md:68-72`) adds three more, one of which is visual: bar/pictorialBar/
candlestick/boxplot no longer overflow the grid rect at the edges — restore with
`axis.containShape: false`.

**Classification of the whole v6.0.0 delta** by the report's own tags: 23 `[Feature]`, 22 `[Fix]`,
1 `[Break]` block with 5 bullets (`en/changelog.md:74-128`). Of the visual differences enumerated in
§3–§4, essentially none are documented individually — they are all folded into break #1. The only
way to enumerate them is to diff `theme/v5.js` against the source defaults, which is what §3–§4 did.

Renames vs. new capability, for the record: `light.ts → rainbow.js` is a **rename**;
`outerBounds*`, `breakArea`, `textMargin`, `displayTransition`, `inactiveBorderWidth`,
`lineStyle.inactiveWidth`, `triggerEvent` on legend/line/matrix are **new options**; everything in
§4's tables is a **default value change**.

---

## 9. For the ty-controls maintainer: adopt, mirror, or ignore?

`.tycss` today (`themes/light.tycss`, 193 distinct `--*` names; 15 skins in `themes/builtin/` plus
`light`/`dark`/`green`/`auto`/`system`) is a **seed → derive** system: 7 colour seeds + `--radius`
(`light.tycss:4-10`) → a MAP tier of `darken()/lighten()` derivations (`--surface-hover`,
`--border-hover`, `--accent-active`, …, `:12-40`) → an ALIAS tier of `var()/alpha()/on()` semantics
(`--focus-ring`, `--muted`, `--on-accent`, `--info`, `:42-58`) → a COMPONENT tier of role-named scalars
(`--pad-button`, `--radius-pill`, `--font-size-base`, `:60-110`).

ECharts 6 is a **closed enumerated ramp**: 40 hand-typed hex steps + 25 aliases, resolved at build
time, with no derivation functions, no cascade, no states, no user reach.

### Where the two align

| concept | ECharts 6 | ty-controls `.tycss` |
|---|---|---|
| semantic text tiers | `primary/secondary/tertiary/quaternary/disabled` | `--on-surface` + `--muted` + `--disabled-opacity` |
| border tiers | `border/borderTint/borderShade` | `--border` + `--border-hover` (derived) |
| surface tiers | `background/backgroundTint/backgroundShade/backgroundTransparent` | `--surface` + 12 derived `--surface-*` |
| accent family | `accent05…accent95` | `--accent`, `--accent-hover`, `--accent-active` |
| spacing scale | `size.xxs…xxxl` (8 steps, 14 uses) | deliberately **no** `--space-*` numeric scale; 19 **role-named** `--pad-*` tokens |
| categorical series palette | `tokens.color.theme[9]` | `TyChartSeries1..8` typeKeys (Tableau-10) |

### Where they do not

1. **Reachability.** `.tycss` tokens are *the* theming surface; ECharts tokens are unreachable from
   a theme. Adopting ECharts' model would be a regression.
2. **Derivation.** ty-controls computes `--surface-hover: darken(--surface, 4%)`, so a skin author
   changes one seed and 30 values follow. ECharts types out 40 steps and then, for dark mode, runs a
   different formula on them — with the `accent80..95 → #ffffff` collapse in §6 as the price.
3. **States and variants.** `.tycss` resolves `base → .variant → :state → .variant:state`. ECharts
   has none; `emphasis` is a hand-written option subtree naming a different ramp step.
4. **Coverage.** ECharts tokens cover colour + a thin slice of spacing: **zero** typography, **zero**
   radius, **zero** elevation. `.tycss` already covers all three.
5. **Density.** ty-controls has a density axis (`density-modern.tycss` overriding the size tokens
   without touching rules). ECharts has no density concept at all — `size.m` is 15px, full stop.

### Recommendation

**Ignore the token *mechanism*. Mirror exactly two things. Copy the *look* only as an option.**

- **Mirror #1 — the neutral/accent ramp as a derivation target, not a literal table.** The one idea
  ECharts 6 has that `.tycss` lacks is a *dense, indexable* ramp. A chart draws five greys (grid line,
  minor grid line, axis line, tick, label); declaring five independent seeds is worse than picking
  `neutral15 / neutral30 / neutral40` out of one ramp. **But derive the ramp** with `.tycss`'s existing
  `darken()/lighten()/alpha()` from `--surface` and `--on-surface`, so all 17 themes get a coherent ramp
  for free and no skin enumerates 40 hexes. Do **not** hard-code `#b7b9be`.
- **Mirror #2 — the domain-tier alias idea.** `axisLine/axisTick/axisTickMinor/axisLabel/
  axisSplitLine/axisMinorSplitLine` is a good, small, honest vocabulary for chart furniture: 6 names
  that map 1:1 onto things a chart draws. Adopt those *names* (as `--chart-axis-line`,
  `--chart-split-line`, …) pointing at ramp steps. That is ~8-12 new tokens, not 64.
- **Do not adopt** `size.xxs…xxxl`. The repo already decided against a numeric spacing scale on the
  classic side (`themes/light.tycss:95` — the comment is explicit that forcing multiples of 4 would
  drift classic by 1px) and ECharts' own scale reaches only 10 % of its spacing anyway. Role-named
  `--pad-*` is the better model and is already in place.
- **Do not adopt** the dark-flip formula. `1 − l^1.5` with an `accent` clamp that eats 4 steps is
  worse than `@mode dark` in `.tycss`, which lets each skin state its own dark values and has
  already been proven across 17 themes.
- **The palette is a separate decision from the model.** If `TTyAdvanceChart` wants to look like
  ECharts 6 out of the box, ship the 9 v6 hexes as the default `TyChartSeries1..9` in
  `themes/light.tycss` and let skins override — that costs nothing and is the part users will
  actually recognise. Note it is 9 colours, not the current 8; and note that v6's #3 `#505372` is a
  dark slate, which will read as "one series is greyed out" against a light surface unless the whole
  ramp is adopted together.
- **Layout defaults are worth copying wholesale** (§5). Legend at the bottom centred, title centred,
  15 %/65/10 %/80 grid insets, `symbolSize 6`, `pie radius 50 %`, `bar gap 10 %`. These are free —
  pure arithmetic, no rendering dependency, and they are the difference between "looks like a 2015
  chart" and "looks current".

**One structural caution carried over from repo history:** whatever chart tokens are added must go
into `themes/light.tycss` (the base layer), into `source/tyControls.Css.Catalog.pas`, and be
re-generated into `tyControls.DefaultTheme.pas` / `tyControls.BuiltinThemeData.pas` — and be checked
against all 17 themes, because a skin that writes *any* rule for a new `TTyAdvanceChart` typeKey
suppresses the whole base layer for that key. A 12-token chart vocabulary is checkable. A 64-token
one, across 17 themes, is not.
