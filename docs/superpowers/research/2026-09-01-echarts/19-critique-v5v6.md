# Completeness critique of reports 12–18

Adversarial review of the ECharts 5-vs-6 research pass, run against `D:/Projects/echarts` (6.1.0),
`D:/Projects/echarts-doc` and `D:/Projects/zrender`. Findings marked APPLIED were folded into
`18-v5-vs-v6-decision.md`; the rest stand as caveats on that file.

---

## Prioritized findings — reports 12–18

### HIGH

**1. The same quantity is counted three different ways and never reconciled.** "v6 version markers in the docs": report 12 §3 says **81** (74@6.0.0 / 7@6.1.0); report 15 §7 says **102 across 39 files**; report 16 §0 says **65** (60/5, 17 files). Ground truth (my parse of all `{{ use: partial-version(...) }}` calls in `en/option`+`en/api`, handling both the `version =` and the undocumented `version:` colon form at `mark-point.md:180`, `rich-inherit-plain-label.md:5`, `zr-graphic.md:1102`, `api/echarts.md:278`): **81 literal markers total — but split 72@6.0.0 / 9@6.1.0**, not 74/7. Raw `grep -rnE "version *[=:] *[\"']6"` = **113 hits / 45 files** (81 markers + partial-caller args). So 12's total is right and its split is wrong; 15's 102/39 is wrong; **16's 65 is badly wrong**, and 16 derived it independently *because it believed report 12 did not exist* (16 §0: "Note on report 12: it does not exist" — 12's mtime is 13:41, 16's is 13:44). 18 quietly adopts 12's numbers without noting that 16, its own cited input, disagrees by 20%.

**2. Report 18 straw-mans option (ii), which is the only reason (iii) reads as a finding.** §4(ii) costs "target ECharts 6 fully" as "+2 XL + 1 L + 2 M **pulled into the early schedule**… before cartesian is finished". But 18 itself establishes twice (§1.1 "all five are Tier 2 or Tier 3"; §5-(iii)-1 "nothing has to be pulled forward") that targeting v6 implies no such schedule. (ii) and (iii) are the same option with a schedule assumption invented for one and denied for the other. The recommendation survives on its two-contracts argument, but the "three options, costed" framing is not fair costing.

**3. `sankey.roam` / `.roamTrigger` "undocumented" is false, and 18 inherited it.** 12 §4 series table: "*present in `SankeySeries.ts:328-329` but UNDOCUMENTED in `en/option/series/sankey.md`*"; 18 §2 gives it a row on that basis. Actual: `sankey.md:95-100` calls `partial-view-coord-sys-common(componentSubType='sankey', roamTriggerDefault="'global'")`, and `view-coord-sys.md:120,126` declare `roam` and `roamTrigger`. **12 §3a lists that exact caller site (`series/sankey.md:95`) two pages earlier** — internal contradiction. Same table also gives `'selfRect'` as `roamTrigger`'s default for all five hosts; sankey's is `'global'` (`SankeySeries.ts:329`).

### MEDIUM

**4. 18 silently resizes 16's measured line counts, always upward.** Axis breaks **1,656 → 1,803**; thumbnail **615 → 706**; box-usage `CoordinateSystem.ts` **360 → "~250, diffuse"**. `wc -l`: `scale/break.ts` 178 + `breakImpl.ts` 785 + `axisBreakHelper.ts` 91 + `axisBreakHelperImpl.ts` 572 + `installBreak.ts` 30 = **1,656** (16 is right); `src/component/thumbnail/*` = **615** (16 is right). Neither report's "~6,100 dedicated lines" matches its own table (18 sums to 6,636; 16 to 6,508).

**5. `coordinateSystemUsage:'box'` is costed three incompatible ways inside report 18.** §1.1 "~250 lines, diffuse"; §2 capability table "**S** mechanism / **L** consequence"; §4(i) and §5 count it as one of the "**2 XL**" savings from targeting v5. Report 10 Tier 3 has it XL. The headline "the real saving is two XL" — the correction 18 asks to be carried back to Q8 — rests on the XL reading its own table contradicts.

**6. 18 silently re-tiers report 10's roadmap without declaring it.** Report 10 Tier 2 has one row: "Axis extras: `containShape`, `dataMin`/`dataMax`, jitter, `customValues` | **M**". Report 16 §1.3 correctly treats these as sub-items shrinking that one M row. Report 18 §2 splits them into four rows and moves three to **Tier 1** — including `axisStatistics + cycleCache | M | Tier 1`, a row that exists in neither 10 nor 16. That is ~2.5 M of new Tier-1 work, and 18 §6.1's explicit "net change" tally (−1 M, +1 XL, +1 L, +1 M, +2 S) does not include it.

**7. `customSeriesRegister.ts` is 30 lines, not 12.** Report 16 says "a **12-line registry**" three times and leans on it for "v6 makes the custom-series/callback problem cheaper" (§1.3, §2.3, §4.4). `wc -l src/chart/custom/customSeriesRegister.ts` = **30**. 18 says 30 — so the two files disagree on a number used as a headline.

**8. "~30 function-valued options" (16 §2.3) vs 1,212 (17 §7.3, 18 §6.2).** 17 measures 244 Function-only + 968 union nodes = **1,212**, `formatter` alone 539. 16 sizes Q6 ("callbacks-as-strings becomes load-bearing") off a number ~40× too small.

**9. "40–50 % of real option literals paste verbatim" is true but the framing hides the real blocker.** I re-ran the pass's own harness (`scratchpad/extract.js` over `echarts/test/*.html`): **1,065 literals from 606 demos, 643 parse failures across 286 files** → 39.6% of literals / 52.8% of files pass. In range. But **534 of 643 failures are "Unexpected token"** and **238 of 1,065 literals contain `function(`/`=>`** — the dominant failure is JavaScript, not JSON laxity. `joComments`/`joIgnoreTrailingComma` fixes none of it. Neither 17 §0 nor 18 §6.1 names the corpus or this caveat, and "users can paste ECharts configs" is a supporting argument for the decision.

**10. A real undocumented v6 grid option that 12 and 16 both miss.** `grid.outerBoundsClampWidth` / `outerBoundsClampHeight` — live in `GridModel.ts:139-140`, consumed at `Grid.ts:249,822,858,1005`, **zero hits in `echarts-doc/en/`**. 12's "Grid / cartesian layout (9 shapes)" table omits them. 18 §3.4 catches them but cites `GridModel.ts:137-138`, which are `outerBounds` and `outerBoundsContain`.

**11. Report 12's v6.0.0 changelog line numbers are systematically wrong.** It cites 76–96 for the 23 `[Feature]` bullets; actual is **77–99**. Line 79 is used for two different bullets (cartesian layout, reusable custom series), as is 90 (`marker.relativeTo`, angleAxis tooltip). The v6.1.0 `[Break]` sub-bullets are cited `:70-73`; actual **:69-71**. v6.1.0 feature lines (4–17) are correct, as is `:122-127` for the v6.0.0 break block.

**12. "The v6 line is exactly two releases" is wrong.** 12 §0 asserts no 6.0.x patch exists. `src/chart/line/LineSeries.ts:125` says "deprecated since **v6.0.1**" and `:132` `@since v6.0.1`. Report 15 §6a is the only file that catches it. 18 §3.4's "Pin to 6.1" list treats `line.triggerEvent` as 6.1-only when source says 6.0.1.

### LOW

**13.** `tokens.ts` semantic aliases: 12 lists 20, 16 says 24, 18 says 25. The `extend(color, {…})` block at `tokens.ts:171-197` has **21**; all three miss `backgroundTransparent`. Token reference sites: 16 says 198, 18 says 191 — actual **191 in 55 files** (18 right).

**14.** 12's v6.1.0 fix distribution sums to 42 against 37 top-level bullets (axis is **5**, not 6). Its demo census says `matrix*` 9; `ls test | grep '^matrix'` = **8** (16's "16 v6-only demos" is likewise 15).

**15.** 16 §3.2 / 18 §4(i): "v5 = 118 features / 329 fixes". Actual top-level bullets in `changelog.md:129-838` = **111 `[Feature]` / 321 `[Fix]`**. (20 releases ✓, 1 `[Break]` block at line 727 ✓.)

**16.** 12 §6 heads its table "Every `deprecated =` marker … (3 total)". There are exactly **2** in `en/` (`grid.md:41`, `line.md:114`); `tooltip.appendToBody` is prose at `tooltip.md:202` under a `version = "4.7.0"` marker. 15 §6a/6b states this correctly — so 12 overstates its own completeness claim.

**17.** 15 §5: "32 `deprecateLog`/`deprecateReplaceLog` sites across 10 files" → actual **33 across 9**; "122 lines across 42 files" → **122 across 43**.

**18.** No report mines the **47 `@deprecated` annotations across 43 files in `echarts/src`** as an independent source for the "do not implement" list; 15 §6b samples ten of them and 12/16/18 rely on the doc markers only.

### Genuinely well covered — not padding

**Report 17's central claim is verified, not guessed, and it is the strongest file in the set.** The build artifact exists on disk and I found it: `config/env.dev-override.js` (gitignored, written by this pass) redirects `releaseDestDir`; `build/build-doc.js:255 writeSingleSchema` emits `<releaseDestDir>/<lang>/documents/option.json` and `:268 writeSingleSchemaPartioned` emits `option-parts/option-outline.json`. Files are at `…/scratchpad/out/en/documents/` at **exactly** the claimed sizes (`option.json` 29,154,293 B; `api.json` 127,986; `option-gl.json` 429,391; `tutorial.json` 268,564), as are the FPC prototypes (`TyEChartsCatalog.pas` 683,223 / `.o` 996,552 / `.ppu` 2,067,679; Full `.pas` 2,664,513 / `.o` 2,673,516 / `.ppu` 20,298,609). Re-derived from the artifact myself: **58,910 paths exact** (once array `items` are not double-counted), 67 array nodes exact, `uiControl` total **46,567 exact**, enum **11,248 sites / 67 distinct lists exact**, number 21,496 / color 8,997 / vector 2,813 / boolean 1,185 / angle 467 all exact, `5.0.0` version-divs 5,562 exact; subtree dedup 1,846 vs claimed 1,858 (0.6%). Citation spot-checks all hold (`helper.js:19`, `md2json.js:196`/`:330`, `sectionsAnyOf` 5 entries). **One caveat:** 17 never says the artifact lives in a session-scoped scratchpad that will be deleted, nor that regenerating it needs network + `npm install`; §8 pins the commit but the deliverable is not durably stored.

**The `src/chart` / `src/component` / `src/coord` sweep is complete.** The only v6-only directories are `chart/chord`, `component/matrix`, `component/thumbnail`, `coord/matrix` — all four described. Every non-directory v6 module is named somewhere across 13/15/16/18: `scale/break*.ts`, `component/axis/axisBreak*`+`installBreak.ts`, `util/jitter.ts`, `chart/scatter/jitterLayout.ts`, `visual/tokens.ts`, `coord/axisStatistics*.ts`, `coord/axisBand.ts`, `chart/custom/customSeriesRegister.ts`, `coord/cartesian/legacyContainLabel.ts`.

**Report 15's breaking/deprecation coverage is accurate** and is the only file to catch the `triggerLineEvent` doc-vs-source (6.1.0 vs 6.0.1) disagreement.

### Facts I verified true (beyond the 8 asked)

`tokens.ts` 233 lines; the 9 palette hexes `#5070dd #b6d634 #505372 #ff994d #0ca8df #ffd10a #fb628b #785db0 #3fbe95`; size scale `xxs:2 … xxxl:50`; `GridModel.ts:48` `@deprecated`, `:65` containLabel-equivalence note, `:136` `outerBoundsMode:'auto'`, `:138` `outerBoundsContain:'all'`; `View.ts:841` `legacyViewCoordSysCenterBase`; `labelStyle.ts:428` `richInheritPlainLabel`; `SankeySeries.ts:328-329`; `ChordSeries.ts` 88 option members; `test/*.html` = 606; `theme/v5.js` 581 lines; `legacyContainLabel.ts` 120; matrix 2,190+487=2,677; chord 1,200; dates 2024-12-28 / 2025-07-30 / 2026-05-18; 20 v5 releases; zrender ships no changelog; chord `padAngle` doc 0 vs source 3 (`chord.md:70` / `ChordSeries.ts:317`); `legend.itemGap` doc 10 vs source 8 (`legend.md:92` / `LegendModel.ts:469`); `tests/test.chart.pas` 1,296 lines / **67** test procs, `tyControls.Chart.pas` 1,721 lines / **15** interface `Ty*` functions — 16's correction of report 10's "~60" is right.
---

## Maintainer follow-up (hand-checked, 2026-09-01)

### The generated schema is real, and it is now stored durably

The critique's one caveat on report 17 — that the build artifact lived in a session scratchpad that
would be deleted — is resolved. The artifact was copied out before the scratchpad expired:

| What | Where it lives now | Size |
|---|---|---|
| `option.json` (EN) — the full option schema | `D:/Projects/echarts-schema/en/documents/option.json` | 29,154,293 B |
| `option.json` (ZH) | `D:/Projects/echarts-schema/zh/documents/option.json` | — |
| `api.json` / `option-gl.json` / `tutorial.json`, EN + ZH | same tree | 128 KB / 429 KB / 269 KB |
| `option-parts/`, `api-parts/`, … the partitioned form | same tree | (278 MB total tree) |
| Generator + analysis scripts from the spike | `docs/superpowers/research/2026-09-01-echarts/spike/emit.js`, `emit_full.js`, `extract.js` | 4 KB / 4 KB / 1.3 KB |
| The compiled Pascal catalog prototype | `docs/superpowers/research/2026-09-01-echarts/spike/TyEChartsCatalog.pas` | 683,223 B |

**Regenerating it** needs network plus `npm install` in `D:/Projects/echarts-doc`, then the documented
`build/build-doc.js` path (`writeSingleSchema` at :255 emits `<releaseDestDir>/<lang>/documents/option.json`;
`writeSingleSchemaPartioned` at :268 emits `option-parts/option-outline.json`), with
`config/env.dev-override.js` redirecting `releaseDestDir`. Since that file is gitignored, the copied tree
above is the durable record — do not delete it without regenerating first.

**The Pascal prototype is not a sketch — it compiled.** `TyEChartsCatalog.pas` is a deduplicated DAG
(root node index 2426, 68 enum lists, EN + ZH descriptions per node) at 683 KB of source, and the
scratchpad also held its `.o` (996,552 B) and `.ppu` (2,067,679 B). The un-deduplicated "Full" variant
compiled too, at 2,664,513 B source to a 20,298,609 B `.ppu` — which is the measurement that says
**dedup is mandatory, not optional**: 58,910 paths flattened is a 20 MB compiler artifact; the shared
subtree DAG is 2 MB.

### Two corrections that change advice already given to the maintainer

**A. "~30 function-valued options" is wrong by about 40x.** Report 17 measures the expanded tree:
**244 Function-only nodes + 968 unions containing `Function` = 1,212 nodes**, of which `formatter`
alone accounts for **539**. (These are node occurrences across the expanded tree — the number of
*distinct* function-valued option kinds is far smaller, because `formatter` recurs under nearly every
series and component — but the surface an option parser must classify is the 1,212.) Consequence: the
named-handler + template-string mechanism is not a detail to settle later; it is load-bearing, and
`'{b}: {c}'` template strings alone cover 539 of the 1,212.

**B. "Relaxed JSON makes ECharts examples paste verbatim" is only 40 % true, and JSON laxity is not
the blocker.** Measured over the real corpus (`echarts/test/*.html`, 606 demos, 1,065 extracted option
literals): **643 parse failures across 286 files, so 39.6 % of literals and 52.8 % of files parse.**
Of the 643 failures, **534 are "Unexpected token"** and **238 of the 1,065 literals contain
`function(` or `=>`**. So the dominant blocker is **JavaScript**, not unquoted keys or trailing commas;
`joComments` / `joIgnoreTrailingComma` fix none of it.

Caveat on the corpus in the other direction: `test/*.html` are *developer* test pages, which are far
heavier on callbacks than an ordinary user config. The honest claim is therefore: relaxed JSON gets a
config that is pure data to paste verbatim; anything with a callback needs the named-handler or
template-string rewrite, and that is roughly a fifth to a quarter of real-world examples.
