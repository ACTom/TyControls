# 17 — Generating a Pascal option catalog from `echarts-doc`

Research pass, 2026-09-01. Question: can the `TTyAdvanceChart` option catalog (every valid path, its
type, default, allowed values, since-version, EN+ZH description) be **generated** from
`D:/Projects/echarts-doc` instead of hand-written?

**Verdict: yes, and better than hoped — `echarts-doc` ships its own generator that emits a
machine-readable JSON schema.** We do not parse Markdown and do not implement their template
language. Run their build, consume the JSON, emit Pascal. Everything below was measured by running
it, not inferred.

## 0. Executive summary

| Fact | Value | Measured at |
|---|---|---|
| `echarts-doc` emits a JSON schema as a build artifact | yes — `option.json` per language | `build/build-doc.js:255` `writeSingleSchema` |
| Build ran clean here | 494 npm packages, ~40 s install, ~90 s build | run below |
| EN `option.json` | 29,154,293 bytes | generated |
| Fully expanded option paths | **58,910** | traverse |
| Distinct *structural* subtrees (the real catalog size) | **1,858** | subtree hashing |
| Distinct leaf defs `(name,type,default,uiControl)` | **1,252** | leaf hashing |
| Distinct leaf property *names* | **788** | `tool/schemaHelper.js` `extractOptionKeys` |
| Paths with a machine-readable enum | **11,248**, only **67** distinct value lists | `uiControl.type === 'enum'` |
| Extra enums recoverable from prose | +502 paths, 49 distinct lists | `<li><code class="codespan">'x'</code>` scan |
| Paths with a default | 38,772 / 58,910 | schema |
| Paths with a since-version marker | 7,212 (1,024 `v6.0.0`, 89 `v6.1.0`) | `doc-partial-version` div |
| ZH/EN path-set drift | **0** — 58,910 == 58,910, none one-sided | set diff |
| Prototype Pascal catalog compiles | 2,512 lines, **0.3 s**, 997 KB `.o` | FPC 3.2.2 |
| ECharts option text vs FPC's *stock* `fcl-json` relaxed mode | unquoted keys, `'strings'`, trailing commas, `//` + `/* */` — all OK | empirical |

**The catalog is ~1,900 nodes, not ~59,000.** That is the single most important consequence: the
emitted unit must be a shared-shape DAG, not a flat path list.

---

## 1. The shortcut: they already have a generator

`package.json` exposes `"build": "node build/build-doc.js --env asf"` and a `--env dev` variant.
`build/build-doc.js` calls `tool/md2json.js`, then `writeSingleSchema` (line 255) writes
`<releaseDestDir>/<lang>/documents/option.json`:

```
{ "$schema": "https://echarts.apache.org/doc/json-schema",
  "option": { "type": "Object", "properties": { … } } }
```

Each node carries `type` (array of strings), `default` (typed by `convertType`, `md2json.js:196`),
`description` (rendered HTML), and optionally `uiControl` / `exampleBaseOptions`.

`writeSingleSchemaPartioned` (line 268) also writes `option-parts/<component>.json` (descriptions,
split per component) and `option-outline.json` — structure only, no prose, via
`tool/schemaHelper.js` `convertToTree`. **That outline is almost exactly the shape we want**
(`{prop, type, default, isObject, isArray, arrayItemType, children[]}`) at a fraction of the size.

**Verified run:**

```
cd D:/Projects/echarts-doc
npm install                       # 494 packages, ~40 s, network required, clean
node build/build-doc.js --env dev
```

`build/helper.js:19` loads `config/env.<env>-override.js` if present, and
`/config/env.*-override.js` is gitignored — so the output directory is redirectable without touching
tracked files. That is what this pass did. Output (EN): `option.json` 29,154,293 B ·
`option-gl.json` 429,391 · `api.json` 127,986 · `tutorial.json` 268,564 · `option-parts/` ~60 MB
(56 files). The only error was `copySite()` wanting a webpack bundle — inside a `try/catch`, harmless.
`build-llms.js` also ran, producing 78 plain-Markdown docs per language (an alternative to the HTML
descriptions).

**Consequence:** our generator is a JSON → Pascal emitter, not a Markdown parser. That deletes the
whole risk class of "our expander disagrees with theirs".

---

## 2. The doc grammar (confirmed — and why not to re-implement it)

`en/option` = 127 `.md` files (`component/` 34, `series/` 24, `partial/` 67, `option.md`), 1,248
headings.

**Heading form**, `tool/md2json.js:330`:
`var parts = /(.*)\(([\w\|\*]*)\)(\s*=\s*(.*))*/.exec(text);`
— `name(type)` optionally ` = default`; nesting by `#` count (`maxDepth` 10, line 14); no `(...)`
means the whole heading text is the key and type is `'*'`.

Raw census of the `(type)` token over plain-identifier headings (1,209 of 1,248):

```
416 (Object)  216 (string)  183 (number)  130 (boolean)  80 (Array)  23 (Color)
22 (number|string)  18 (Object|Function)  16 (Function)  15 (number|Array)  13 (string|number)
11 (string|Function)  11 (*)  9 (boolean|string)  7 (boolean|number)  5 (Array|string)
5 (Array|number|string)  4 (number|string|Date)  4 (number|string|Array)  4 (Array|number)
3 (string|boolean)  3 (string|Array)  3 (Array|Object)  2 (number|Array|boolean)
1 each: (number|Function) (boolean|number|Array) (boolean|Array) (Object|Array) (Function|string)
        (string|HTMLElement|Function)
```

The other 39: 30 dotted component names (`# series.bar(Object)`, `# dataZoom.slider(Object)`,
`# visualMap.piecewise(Object)`, `## transform.sort(Object)`, `## transform.xxx:xxx(Object)`) and
**9 with no type at all** — `select`, `emphasis`, `blur`, three occurrences each. 517 of 1,248
headings carry `= default` (73 `true`, 62 `false`, 42 `0`, 31 `null`, 20 `10`, 17 `'auto'`,
12 `undefined`, …).

After expansion, 39 distinct type strings, by node count: `number` 24812 · `string` 8827 ·
`Color` 7928 · `Object` 3720 · `string|number|Array` 3047 · `boolean` 2336 · `number|Array` 1465 ·
`string|number` 1364 · `number|string` 1318 · `string|Object` 1121 · `Array` 750 · `string|Array` 569 ·
`string|Function` 560 · `number|Function` 336 · `Function` 244 · `*` 140 · … 23 more.
`string|number` **and** `number|string` both occur — union order is authorial, so normalise to a
sorted set.

### Edge cases

| Case | Count | Handling |
|---|---|---|
| Heading with no `(type)` | 9 raw → `'*'` | "any" |
| Explicit `(*)` | 11 raw / 140 expanded | "any" |
| Empty type `()` | 30 expanded (`*.textConfig.position`) | upstream bug: `en/option/partial/zr-graphic.md:1508` `###${prefix} position() = 'inside'` (ZH `:1489`). Patch to `string\|Array`. |
| Bogus type `(prefix)` | 3 expanded | upstream bug: `en/option/component/timeline.md:524` `#${prefix} rotate(prefix) = 0` (ZH `:884`). Patch to `number`. |
| Wildcard key `<style_name>` | 562 | rich-text style names — a *user-named* map key; model as "any key here" |
| Literal `$action` key | 13 | `graphic.elements-*.$action` — real key, and a JSON-parsing hazard (§9) |
| `Date` in a union | 12 | `number\|string\|Date` |
| `HTMLElement` | 1 | browser-bound (`tooltip.appendTo`) |

33 anomalies in 58,910 (0.06 %). The generator should assert on the anomaly count so upstream change
surfaces as a build failure, not a silently-typeless node.

---

## 3. The include/macro system

Engine is **etpl**, vendored at `dep/etpl.js`, configured `md2json.js:15-19` with `commandOpen '{{'`,
`commandClose '}}'`, `missTarget 'error'`. All 127 files are concatenated (`mdTpls.join('\n')`) and
compiled as **one** program; the entry point is the target named `option` — `en/option/option.md:1`
is `{{target: option}}` followed by 51 `{{import: …}}` lines.

Command census over `en/option`: `{{use:}}` 1911 · `{{target:}}` 286 · `{{if:}}` 265 (`{{/if}}` 265) ·
`{{import:}}` 51 · `{{else}}` 41 · `{{var:}}` 26 · `{{elif:}}` 20 · `{{/target}}` 7 · `{{for:}}` 1.
Top callees: `partial-version` 305 · `partial-item-style` 104 · `partial-label` 69 ·
`partial-emphasis-disabled` 48 · `partial-component-id` 48 · `partial-line-style` 38 ·
`partial-coord-sys` 34 · `partial-silent` 30.

What a from-scratch expander would have to do, all visible in `en/option/partial/item-style.md`:

- **Heading depth is a runtime string.** Headings read `#${prefix} color(Color) = …`; `prefix` is a
  string *expression*. Observed forms: `"#"`, `"##"`, `"###"`, `"####"`, `"#####"`, `${prefix}`,
  `"#" + ${prefix}`, `"###" + ${prefix}`, `${prefix} + '##'`, `'##'+${prefix}`. It recurses —
  `item-style.md:70` passes `prefix = '#' + ${prefix}` into `partial-decal`.
- **Conditional types.** `item-style.md:9`:
  `#${prefix} color(Color{{ if: ${hasCallback} }}|Function{{ /if }}) = ${defaultColor|default(null)}`.
- **JS expressions as arguments.** `en/option/series/bar.md`:
  `useColorPalatte = ${topLevel} && ${state} === 'normal'`, `hasInherit = ${state} === 'emphasis'`.
- **Filters.** Two registered (`md2json.js:21,25`): `|default(x)` and `|minVersion(x)` (which runs
  `tool/helper/compareVersions.js`). Real uses: `${version|minVersion('6.0.0')}` ×3,
  `${version|default('5.3.0')}` ×2, `${option0Version|default("5.4.1")}` ×1.
- **A global-variable hack.** `md2json.js:44-49` mounts `tplEnv` on `Object.prototype` during render.

**Do not re-implement.** Run their build; the cost is one `npm install`.

### `partial-version` — the since/deprecated marker

`en/option/partial/version.md` emits `<div class="doc-partial-version">Since \`v${version}\`</div>`,
or a `Deprecated since \`v${version}\`. ${deprecated}` branch. Raw argument census over the 305 uses:
118× 5.0.0 · **61× 6.0.0** · 10× 5.5.0 · 10× 5.6.0 · **9× 6.1.0** · 9× 5.2.0 · 8× 4.4.0 · 7× 5.0 ·
6× 5.1.0 · 5× 5.3.0 · … · 30 via a `${version}` variable. `deprecated` 2, `feature` 3.

After expansion **7,212 nodes** carry the div: 5.0.0 ×5,562, **6.0.0 ×1,024**, 5.3.0 ×253,
**6.1.0 ×89**, 5.5.0 ×68, 5.2.0 ×53, 5.6.0 ×35, 5.5.1 ×26, … Only **2** deprecations exist in
`en/option`; the notable one is `en/option/component/grid.md:41`
(`grid.containLabel`, deprecated in 6.0.0 in favour of `grid.outerBoundsMode`). The div class is
stable, so `SinceVer`/`DeprecatedIn` lift cleanly into structured fields. ZH wording differs — parse
the version from EN and reuse for ZH.

---

## 4. The counts

**Expanded:** 58,910 paths, max depth 10; 67 array nodes, 3,670 object nodes, 55,173 leaves. Path
strings total 2,863,461 chars; HTML descriptions 21,520,701 chars.

73 top-level roots, by expanded path count:

```
series-graph 3915  series-line 3312  series-pictorialBar 3016  series-scatter 2987
series-effectScatter 2981  series-pie 2980  series-bar 2955  series-funnel 2942  series-lines 2801
series-map 2744  series-heatmap 2614  series-gauge 2579  series-boxplot 2274  series-treemap 2252
series-candlestick 2243  series-sankey 2166  series-custom 1419  series-sunburst 1368
graphic 1266  series-tree 1236  series-radar 967  geo 793  singleAxis 523  xAxis 478  yAxis 478
series-themeRiver 477  radiusAxis 438  matrix 433  series-chord 432  legend 384  angleAxis 368
timeline 359  parallel 343  parallelAxis 330  toolbox 327  calendar 252  radar 223
dataZoom-slider 197  grid 143  title 139  tooltip 121  polar 120  visualMap-continuous 98
series-parallel 87  axisPointer 74  visualMap-piecewise 71  thumbnail 48  aria 44
dataZoom-inside 27  dataset 21  textStyle 19  brush 18  media 6  stateAnimation 3
+ 19 scalar roots (color, backgroundColor, darkMode, animation*, blendMode, useUTC, …)
```

Five discriminated unions (`build/build-doc.js:145` `sectionsAnyOf`):
`series` → 23 types (line bar pie scatter effectScatter radar tree treemap sunburst boxplot
candlestick heatmap map parallel lines graph sankey funnel gauge pictorialBar themeRiver chord
custom) · `graphic.elements` → 13 (group image text rect circle ring sector arc polygon polyline line
bezierCurve compoundPath) · `dataZoom` → 2 (inside slider) · `visualMap` → 2 (continuous piecewise) ·
`dataset.transform` → 3 (filter sort xxx:xxx).

**Deduplicated — the number that sizes the unit.** Hashing each node's entire subtree
(name+type+default+uiControl+children, description excluded):

- **1,858 distinct structural subtrees**
- **1,252 distinct leaf definitions**, **788 distinct leaf property names** (315 occur exactly once)
- 2,502 distinct HTML descriptions / **2,051 distinct after stripping to plain text**

The 31× collapse is because `itemStyle`, `label`, `textStyle`, `emphasis`, `markPoint`, `markLine`,
`tooltip` are literally the same subtree pasted into every series by the same partial: `color`
occurs 2,010 times; `shadowBlur`/`shadowOffsetX`/`shadowOffsetY`/`shadowColor` 1,929 each;
`fontStyle`/`fontWeight`/`fontFamily`/`lineHeight` 1,193 each.

**Siblings:** `option-gl.json` = 1,306 paths, zero `uiControl` — that is echarts-gl, WebGL,
browser-bound, out of scope, excluded free. `api.json` = 126 paths — the JS instance API
(`echarts.init`, `setOption`, events), which maps to Pascal methods, not to the catalog.

---

## 5. Enumerations — where completion lists come from

**Structural.** Option pages carry inline pseudo-tags parsed at `md2json.js:242-296`; recognised
types at line 254 are `boolean color number vector enum angle percent percentvector text icon`.
They land as `node.uiControl`. **46,567 of 58,910 nodes (79 %)** have one:
`number` 21496 · `enum` 11248 · `color` 8997 · `vector` 2813 · `boolean` 1185 · `angle` 467 ·
`percent` 160 · `icon` 93 · `text` 63 · `percentvector` 45.
Attribute frequency: `type` 46567 · `default` 27116 · `step` 22160 · `min` 17998 · `options` 11249 ·
`dims` 2843 · `max` 2644 · `separate` 439 · `value` 325 · `clean` 300. So the catalog gets 11,248
enum sites **and** 17,998 numeric lower bounds / 2,644 upper bounds for free — a validator, not just
completion.

Every enum node has `options` (0 missing), and there are only **67 distinct value lists** across
11,248 sites on 63 leaf names (only 9 names carry more than one list):

```
3012 solid,dashed,dotted        1193 normal,italic,oblique
1193 normal,bold,bolder,lighter 1193 sans-serif,serif,monospace,Arial,Courier New
 982 left,center,right           975 top,middle,bottom
 684 butt,round,square           684 bevel,round,miter        631 truncate,break,breakAll
 350 label position (14 values)  146 easing (31 values)        40 min,max,average
  24 auto,pointer,move,grab,grabbing
```

Raw markers: 544 in `en/option`, 545 in `zh/option` (93 vs 94 `ExampleUIControlEnum`).
`build/build-doc.js:290` `copyUIControlConfigs` back-fills EN from ZH — **build ZH first** (their
`run()` loop already does `zh` then `en`; do not reorder) or the extra enum is lost.

**Prose-only — and it holds the important ones.** No `uiControl` on: `xAxis.type`
(`value, category, time, log`), `series-*.coordinateSystem`, `series-line.sampling`
(`lttb, average, min, max, minmax, sum`); `series-*.type` has an empty description entirely — its
value list is structural (`items.anyOf[*].properties.type.default`).

5,777 string-typed nodes lack an enum `uiControl`. Their prose is regular:

```html
<p>Option:</p><ul><li><p><code class="codespan">&#39;value&#39;</code> Numerical axis, …</p></li>
```

Scanning `<li>[<p>]<code class="codespan">'x'</code>` with ≥2 hits recovers **502 more nodes / 49
distinct lists** — `xAxis.type`, `brush.brushType`, `brush.brushMode`, `legend.pageButtonPosition`,
`geo.preserveAspect`, `grid.outerBoundsMode`, `timeline.axisType`, `graphic.elements-group.$action`.
It is not clean: `brush.seriesIndex` yields `all, Array, number` (two are type names). So those 49
lists need **one human pass**, then get pinned as a hand-maintained override table. 233 nodes say
`Options:` and 160 say `Optional values:`, so ~250-400 sites is the ceiling — 502/49 is close to it.

---

## 6. The ZH tree

**Path-for-path identical.** `diff` of `en/option/**/*.md` vs `zh/option/**/*.md` filenames →
identical (127 each). 286 `{{target:}}` names in each, `diff` empty. Expanded schemas: **58,910
paths each; 0 in EN only, 0 in ZH only.**

Drift is attribute-level and systematic. **Type drift — 1,185 nodes, 7 patterns:**

```
1123× borderRadius  EN number       ZH number|Array          (ZH is right)
  53× position      EN string|Array ZH string|Array|Function
   3× textStyle EN * ZH Object    2× dimension EN string ZH number
   2× symbolBoundingData EN number ZH number|Array
   1× itemGap EN * ZH number      1× config EN * ZH Object
```

**Default drift — 1,474 nodes, 56 patterns:**

```
706× opacity  EN (none) ZH 1           344× color EN (none) ZH '自适应'  ← prose, not a value
234× width    EN 0      ZH 1            67× animationEasingUpdate EN 'cubicOut' ZH 'cubicInOut'
 27× transition EN ['x','y'] ZH (none)  14× animation EN true ZH false
plus legitimately-localised toolbox strings: title 'save as image'/'保存为图片',
     lang ['data view','turn off','refresh']/['数据视图','关闭','刷新']
```

**Rule:** structure and identity from EN; `type` = **union** of EN and ZH; `default` prefers EN
except a short allow-list of genuinely localised toolbox strings (`title`/`lang`/`back`). Keep both
descriptions. Any drift outside the recorded patterns should fail the build.

Description volume, plain text, distinct only: EN 2,051 distinct / 869,155 B raw / **161,787 gzip**;
ZH 2,048 distinct / 832,446 B raw / **174,322 gzip**. Empty-description nodes: 1,802 EN / 1,800 ZH.

---

## 7. What CANNOT be generated

1. **Cross-field constraints.** Expanded EN descriptions contain, by phrase (overlapping):
   `Only works` 1,082 · `only when` 533 · `valid only when` 393 · `works/effective/available only
   when|if|in` 111 · `only valid when` 55 · `It is valid when` 25 · `not supported` 82. Order of
   magnitude: ~1,000 expanded nodes = low hundreds of *distinct* nodes. Examples:
   `legend.itemStyle.borderMiterLimit` "Only works when `borderJoin` is set as `miter`";
   `grid.tooltip.axisPointer.lineStyle` "It is valid when `axisPointer.type` is `'line'`";
   `title.shadowBlur` "works only if `show: true` … and `backgroundColor` is defined other than
   transparent"; `tooltip.position` `'top'` "only valid when `trigger` is `'item'`".
2. **Series × coordinate-system applicability.** `series-bar.coordinateSystem` prose says some series
   "can not be laid out directly based on matrix coordinate system or calendar coordinate system".
   Nothing structural encodes that matrix, nor which axis/grid options go dead once
   `coordinateSystem` changes. For a depth-first cartesian build only the cartesian slice is needed
   at first — write it as the build proceeds.
3. **Function-valued options — 1,212 nodes** (244 Function-only, 968 unions). Unions by leaf:
   `formatter` 539 · `animationDelay` 75 · `animationDuration` 74 · `animationDelayUpdate` 72 ·
   `animationDurationUpdate` 71 · `interval` 24 · `symbol`/`symbolSize`/`symbolRotate` 19 each ·
   `labelLayout` 18 · `color` 17 · `min`/`max` 7 each · `sort` 2 · `pageFormatter` 1 · `renderItem` 1.
   Function-only: `during` 27, then 13 DOM-style handlers × 13 graphic element types (`onclick`,
   `ondrag`, …), `project`/`unproject`/`stream` 2 each, `optionToContent`/`contentToOption` 1 each.
   Signatures are prose-only (`(params: Object) => Color`, in fenced `ts` blocks).
4. **Browser-bound options.** 231 nodes mention DOM/HTMLElement/CSS/canvas: `tooltip.appendTo`
   (`string|HTMLElement|Function`), `tooltip.className`, `tooltip.renderMode: 'html'|'richText'`,
   `toolbox.feature.saveAsImage`, and all of `option-gl`. For a Pascal host `renderMode` is always
   `'richText'`; mark the `'html'` half **unsupported**, not merely absent.
5. **Prose-stated defaults.** ZH writes `自适应` ("adaptive") as the default for 344 `color` nodes and
   2 `barWidth` nodes. Documentation, not a value — must not reach `DefVal`.
6. **The upstream authoring bugs** of §2.

---

## 8. Design sketch

### Pipeline

```
echarts-doc (pinned commit)
 └─ npm install; node build/build-doc.js --env dev        [their code, unmodified]
     └─ out/{en,zh}/documents/option.json
         └─ scripts/gen-echarts-catalog.js                [ours, ~300 lines of node]
             ├─ merge EN+ZH; union types; resolve default drift by rule
             ├─ lift SinceVer/DeprecatedIn out of the doc-partial-version div
             ├─ intern enums (67 structural + ~49 curated prose lists)
             ├─ strip HTML → plain text; keep first paragraph as the editor summary
             ├─ hash subtrees → shared-node DAG (~1,900 nodes)
             ├─ apply overrides.json (anomaly patches, prose enums, cross-field
             │                        constraints, unsupported flags, function table)
             └─ emit source/tyControls.AdvChart.Catalog.pas
                    + source/tyControls.AdvChart.Catalog.Desc.<lang>  (resource blob)
```

Two properties to copy from `scripts/gen-tycss-catalog.ps1` (84 lines): **deterministic ordering**
(that script sorts *ordinally* precisely because a culture-aware sort would break the Pascal-side
assertion — same discipline here, so a regeneration diffs reviewably) and **a drift test**
(`tests/test.css.catalog.pas` asserts the generated unit still matches its source; the equivalent
here re-derives node/enum/per-root counts from a checked-in fingerprint and fails when the emitted
unit and the pinned `echarts-doc` commit disagree).

### The record

```
TTyOptNode = record
  Name        : string;      // 'itemStyle'; '' for an anyOf variant; '*' for a wildcard key
  Kind        : TTyOptKinds; // set of (okObject, okArray, okString, okNumber, okBool,
                             //         okColor, okFunc, okDate, okAny)
  DefVal      : string;      // verbatim doc default; '' absent; 'undefined' kept distinct
  UiKind      : TTyOptUi;    // uiNone/uiNumber/uiEnum/uiColor/uiVector/uiBool/uiAngle/
                             //   uiPercent/uiPercentVector/uiIcon/uiText
  EnumIdx     : Integer;     // -1, else index into TyOptEnums (~115 lists)
  NumMin, NumMax, NumStep : Double;   // from uiControl; NaN when absent
  SinceVer    : string;      // '6.0.0'; '' when unversioned
  Flags       : TTyOptFlags; // ofDeprecated, ofUnsupported, ofBrowserOnly, ofWildcardKey,
                             //   ofFunctionOnly, ofTemplateString
  DescEnIdx, DescZhIdx   : Integer;   // into the description blob
  FirstChild, ChildCount : Integer;   // slice of TyOptChildren (flat Integer array)
  Discriminator : string;    // 'type' on the 5 anyOf parents; '' otherwise
end;
```

Plus `TyOptNodes[0..~1900]`, `TyOptChildren[0..~11000]`, `TyOptEnums[0..~115]`, and a separate
hand-authored cross-field-constraint table keyed on node index.

### Measured size — a prototype was built and compiled

A prototype emitter ran against the real merged EN+ZH `option.json`; output compiled with FPC 3.2.2
(Win64):

| Variant | Source | Lines | Compile | `.o` | `.ppu` |
|---|---|---|---|---|---|
| Descriptions truncated to first paragraph / 200 chars (2,427 nodes) | 683,223 B | 2,512 | **0.3 s** | 996,552 B | 2,067,679 B |
| Full descriptions inline (2,608 nodes) | 2,664,513 B | 2,693 | 1.1 s | 2,673,516 B | **20,298,609 B** |

(The prototype's node count exceeds the 1,858 structural figure because its dedup key also included
description text, which splits otherwise-identical shapes; interning descriptions separately brings
it back down.)

Two hard lessons from doing it:

- **A Pascal string literal cannot span a line.** The first full-description attempt died with
  `Fatal: String exceeds line` at line 86. Descriptions must be emitted as `'…'+#10+'…'`. Literal
  *length* is not the problem — the longest emitted literal was 10,714 chars and FPC took it.
- **The `.ppu` is what hurts**, not the `.o`: 20 MB for inline full descriptions, paid by every unit
  that `uses` the catalog on every rebuild.

**Recommendation.** Compile in the structure (nodes, children, enums, ranges, since-version, flags)
plus a short EN+ZH *summary* line per node — the 2,512-line / 0.3 s / 1 MB `.o` variant, which is
what completion, validation and the reference tree actually need. It is the same design as
`tyControls.Css.Catalog.pas` (411 lines / 10,438 B for 385 strings) one order of magnitude up. Put
**full descriptions in a resource**, one blob per language, loaded on demand by the design-time
dialog: 869 KB + 832 KB raw, **162 KB + 174 KB gzip**, and `zipper` is already a repo dependency
(`source/tyControls.ThemeBundle.pas` uses `fpjson, jsonparser, zipper`). Keep the catalog in
**`source/`** (runtime, headless-testable) with the dialog a thin `designtime/` shell — exactly the
`Css.Catalog` / `Css.Complete` / `Design.Css.Editor` split. There is a runtime use too: a `Validate`
the user can call on their own option text.

### Scaling the editor from ~190 tokens to ~1,900 nodes

Precedent: `source/tyControls.Css.Catalog.pas` (411 lines, two flat arrays — 188 tokens, 197
typeKeys) → `source/tyControls.Css.Complete.pas` (360 lines, pure logic: `TyCssCompletionItems`,
`TyCssUnknownProps`, `TyCssPropertyTemplate`, `TyCssValidate`, `TyCssFormat`, `TyCssFormatLine`,
`TyCssPropertyDefault`; its header says *"Kept in a runtime unit — no SynEdit, no PropEdits — so it
is unit-tested headless"*) → `designtime/tyControls.Design.Css.Editor.pas` (351 lines: `TSynEdit` +
`TSynCompletion` on Ctrl+Space, a `TTreeView` reference list from `BuildRefList`, Validate/Format
buttons, format-on-line-leave, double-click-to-insert seeded with the theme's actual value).

| Aspect | tycss today | option tree |
|---|---|---|
| Completion source | one flat array per context (≤197 items) | **path-dependent**: walk the DAG from document root to caret, offer that node's children. The caret's containing path is an input `TyCssCompletionItems` never needed. |
| Value hints | `TyStyleValueHints(prop)`, closed keyword sets | `EnumIdx` → 1 of ~115 lists; numeric nodes offer `min/max/step` as a range, not a list |
| Reference list | 5 flat categories, ≤197 leaves | same `TTreeView`, **lazy-populated from the DAG**: 73 roots, children on expand. Never materialise 58,910 paths. Add a filter box — 788 leaf names is past scroll-ability. |
| Unions | none | 5. Under `series[i]` the child set depends on the sibling `type`, so the walker must read `type` from a *partially typed* document — the parser must tolerate incomplete input, unlike `TyCssValidate`. |
| Unknown-name check | over a 197-name set | "not a child of the resolved parent" — a better error, and it needs the path walk |
| Validation | parse + resolve values | parse + type check + enum membership + numeric range + the hand-authored constraints |
| Seeded default | resolved from the live theme | `DefVal` from the catalog (38,772 of 58,910 nodes have one) |

The architecture survives the 10× unchanged; only `Complete.pas` grows a path walker and a tolerant
parser. Estimate: `AdvChart.Catalog.pas` generated ~2,500 lines; `AdvChart.Complete.pas` ~700-900
hand-written; `Design.AdvChart.Editor.pas` ~450-550.

---

## 9. The option-text syntax

### Strict JSON is the wrong target — and FPC already ships the right one

ECharts config in the wild is a JS object literal: unquoted keys, `'single quotes'`, trailing commas,
`// comments`, functions. Strict JSON rejects all five. **Measured here**, FPC 3.2.2's stock
`fcl-json` with `TJSONParser.Create(s, [joUTF8, joComments, joIgnoreTrailingComma])` — i.e. *without*
`joStrict`:

```
OK   {"a":1}   {a:1}   {'a':1}   {a:'x'}   {"a":1,}   {/*c*/"a":1}   {a:1 // line\n}
OK   {a:[1,2,],b:'s',/*k*/c:{d:true}}      {a:'it\'s'}   {a:"multi\nline"}   {a:'\u4e2d\u6587'}
OK   {a:.5}   {formatter:'{b}: {c}'}   {a:'#fff',b:[0,'50%']}   {"rich":{"<style>":{}}}
FAIL {$action:'merge'}   Invalid character at line 1, pos 1: '$'
FAIL {a:undefined}       Unexpected token (undefined) encountered
FAIL {a:+1}   {a:0x10}   {a:NaN}
FAIL {a:function(x){return x;}}   Error at line 1, Pos 11: Unexpected token (function)
```

The scanner already emits `tkIdentifier` for JS identifiers (`jsonscanner.pp:47,552`) and accepts `'`
unless `joStrict` (`jsonscanner.pp:314-317`); the reader takes `tkIdentifier` as a key
(`jsonreader.pp:219,354`). Errors carry line and position.

**So no custom JSON5 lexer is needed for reading.** Three shallow gaps: `$action` (a *real* key, 13
sites — either patch `jsonscanner.pp` to admit `$` in an identifier, or require it quoted, which
parses today, and say so in the error); `undefined` (12 doc defaults are literally that — map to
null in a pre-pass or patch); `NaN`/`Infinity`/`+1`/`0x10` (never appear in real option text; reject
with a clear message). A hand-written lexer is still worth having *for the editor* (token positions,
brace matching, highlighting) — `tyControls.Css.Lexer` (260 lines, line/col tracking, `Peek`/`Next`)
is the right shape and size estimate — but the runtime loader can be `fcl-json`.

### What relaxed JSON buys — measured on 606 real demos

1,065 `option = { … }` literals were extracted from `D:/Projects/echarts/test/*.html` (606 files) by
brace matching and fed to the relaxed parser:

```
all 1,065 literals             422 parsed (39.6 %)   643 failed
827 with no function at all    420 parsed (50.8 %)   407 failed
```

Failure census: `function` 94 · bare identifier `data` 78 · `(` 35 · `xAxisData` 24 · `.` 24 ·
`_ctx` 14 · `renderItem` 11 · `new` 10.

Read honestly: the residual failures are **not syntax sugar we are missing** — they are JS *program*
content (`data`, `xAxisData`, `Math.max(...)`, `new Date(...)`, `echarts.util.map(...)`). The test
suite computes its data in JavaScript; no config format can accept that. What relaxed JSON buys is
that the 40-50 % of real option text that *is* a literal pastes verbatim, and the rest fails with a
pointing error rather than a wall of quote-fixing. Doc-site and gallery examples skew far more
literal than the test suite, so 40 % is a floor. Cost: it is a **superset**, so nothing a browser
would accept gets falsely rejected. The real cost is on the *serialiser* — write strict-ish JSON out
(quoted keys, double quotes, no trailing commas) so round-trips are stable and diffs clean, while
accepting everything on read.

### Function-valued options in a host with no JS

1,212 nodes accept a function. Three mechanisms, by coverage:

1. **Template strings — covers the big one.** `formatter` alone is 539 of the 968 function-unions
   (56 %), and its *string* form is the documented idiom already: `'{b}: {c}'`,
   `'{a} <br/>{b}: {c} ({d}%)'`, `'{value} °C'`, plus `rich` tags `'{name|{b}}'`. Set
   `ofTemplateString` on these nodes; the editor completes the placeholder set per context
   (`{a} {b} {c} {d} {e}` for series, `{value}` for axis labels). A first-class feature, not a
   fallback — it is what ECharts users write anyway.
2. **Named Pascal callbacks referenced by name.** `{ formatter: '@MyTooltipFormatter' }` (or a `$fn:`
   prefix) resolved against a registry the host populates via
   `RegisterChartCallback('MyTooltipFormatter', @Handler)`. The honest answer for `renderItem`,
   `labelLayout`, `symbolSize`, `color`-as-function, `animationDelay`, `sort`, `interval`. The editor
   completes from registered names; an unregistered name is a validation error, not a silent no-op.
   Same "name → registered thing" pattern the theme registry already uses.
3. **Reject a literal `function(...)` with a pointing error.** `fcl-json` already gives
   `Error at line 1, Pos 11: Unexpected token (function)`. Upgrade it to a catalog-aware message —
   *"`tooltip.formatter` accepts a function in ECharts. This host cannot run JavaScript — use a
   template string (`'{b}: {c}'`) or a registered callback name (`'@Name'`)."* Because the catalog
   knows *which* nodes are function-valued, that message is specific at all 1,212 sites without one
   hand-written string.

The 169 DOM-style handlers (`onclick`, `ondrag`, … 13 each × 13 graphic element types) should be
flagged `ofUnsupported` — they are the zrender DOM event surface and map to Pascal events on the
control, not to option text.

---

## 10. Risks and open items

1. **Upstream churn.** 58,910 paths regenerate on every `echarts-doc` commit. Pin a commit hash in
   the generator; fail the build when anomaly count, drift-pattern set, or per-root path counts leave
   a checked-in fingerprint. `tests/test.css.catalog.pas` already established that discipline.
2. **`copyUIControlConfigs` direction** (`build/build-doc.js:290`) back-fills EN from ZH — build ZH
   first or lose one enum.
3. **The 49 prose-derived enum lists need one human pass** (`brush.seriesIndex → all, Array, number`
   is a known false positive).
4. **The cross-field constraint table is genuinely hand-written**, low hundreds of entries. It is the
   only real authorship here, and the part that makes the editor feel intelligent rather than merely
   complete.
5. **Series × coordinate-system applicability is not machine-readable anywhere.** Write the cartesian
   slice as the depth-first build proceeds.
6. **`option-gl` is WebGL** — 1,306 paths, excluded. Say so in the catalog header so a future reader
   does not think it was forgotten.

## Appendix — artifacts left on disk

- `D:/Projects/echarts-doc/node_modules/` — 494 packages installed to run their build. Gitignored.
  Delete if unwanted; reinstall costs ~40 s.
- `D:/Projects/echarts-doc/config/env.dev-override.js` — three lines redirecting `releaseDestDir` and
  `ecWWWGeneratedDir` into the scratchpad so the build wrote nothing into the clone.
  `/config/env.*-override.js` is gitignored (`.gitignore`, last line).
- Generated JSON, the prototype Pascal units and the measurement scripts are in this session's
  scratchpad, not in the repo.
