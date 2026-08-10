# PerMonitorV2 DPI: measured root causes, what was fixed, what is specified

Origin: Lazarus-forum report from **Antek**, PerMonitorV2 manifest, real dual-monitor
hardware. Three symptoms:

1. dragging 100% → 250% costs **2–4 s** of "recalc" (he names `TyTitleBar`, "and more");
2. `TyTitleBar` is **far too tall** at high DPI;
3. dragging back to 100% leaves the layout **broken forever**.

Everything below is measured, not inferred. Where a guess turned out wrong it is recorded
as wrong, because two of the obvious guesses **were** wrong and re-deriving them costs a day.

---

## 0. How it was reproduced without a second monitor

`scratchpad/a6256_dpiprof` (harness kept out of the repo; rebuild from this description).
It drives the exact path a real monitor change takes:

```
SendMessage(Form.Handle, WM_DPICHANGED, MAKELONG(dpi,dpi), @suggestedRect)
```

which is what `lcl/interfaces/win32/win32callback.inc:2072` maps to `LM_DPICHANGED`, which
`TCustomForm.WMDPIChanged` (`lcl/include/customform.inc:2251`) turns into

```
AutoAdjustLayout(lapAutoAdjustForDPI, PixelsPerInch, NewDpi, Width, MulDiv(Width,New,Old))
```

The harness builds a `TTyForm` + `TTyTitleBar` + N children, shows it (a real HWND — the
LCL align engine does not run without one, see `memory/headless-tests-never-run-lcl-align`),
then injects 96→240 and 240→96 and diffs every control's bounds and font.

It also plants a **plain LCL `TButton`** in the same form as a control group. That single
decision is what made the diagnosis unambiguous.

**Measurement caveat, stated up front:** QPC reports 10 MHz but every sample lands on a
64 ms multiple on this host, so individual numbers carry ±64 ms. Differences of one or two
ticks below are noise; the headline differences are 20–140 ticks and are real.

---

## 1. Manifest finding — the examples are not per-monitor aware at all

**0 of 46** example `.lpi` files declare `DpiAware`. They all set `UseXPManifest` and
`Scaled`, but `TProjectXPManifest` defaults `DpiAware := xmdaFalse`
(`ide/packages/ideproject/w32manifest.pas:251`), and the value is only written to the
`.lpi` when it differs from that default — so an absent element means **DPI-unaware**.

Consequences, both worth stating:

- Windows bitmap-stretches those apps. They never receive `WM_DPICHANGED`, so **none of the
  shipped examples exercise the per-monitor path**. This defect could not have been caught
  by running them, which is why it reached a user first.
- Antek's own app declares PMv2, so he is on a path the library had never run.

**DONE (ac2363).** `examples/containers` and `examples/demo` now declare
`<DpiAware Value="True/PM_V2"/>`, which is the value the IDE writes for PerMonitorV2 and
which emits `<dpiAwareness>PerMonitorV2, PerMonitor</dpiAwareness>` into the manifest.
Both still build and open.

One thing the flip uncovered: **`examples/containers/containers_example.lpr` had no
`{$R *.res}`**, so its project resource was never linked and `UseXPManifest = True` had
been doing nothing at all — no common-controls v6 either. The `.lpi` change alone would
have been cosmetic there. Verified the fix by searching the built `.exe` for the
`<dpiAwareness>` element: absent before, present after. Worth a sweep of the other 44
examples for the same missing line; not done here.

The remaining 44 examples are still DPI-unaware. Flipping them is a real behaviour change
per example and still belongs with whoever owns `examples/`; two are enough to make the
defect class reachable in-house.

---

## 2. The 2–4 seconds — reproduced, but NOT yet fixed. Read this section carefully.

**The transition is reproduced.** A 60-control form, injected 96 → 240, takes **1.9–3.6 s**;
180 controls takes 6–7 s. That is Antek's 2–4 s, on demand, with no second monitor.

### 2a. Measurement discipline — this host lies if you let it

This machine runs several agents at once. The same binary measured **9216 ms** under load
and **1408 ms** idle for the identical transition. Wall-clock numbers taken minutes apart
are worthless here. Every claim below comes from an **A/B in the same load window**, 3
samples each, compared on medians, with "bare full repaint" carried as a load canary.

Also: QPC advertises 10 MHz but every sample lands on a 64 ms multiple, so single readings
carry ±64 ms.

### 2b. What was fixed: the style cascade had no cache (real, but NOT the stall)

`TTyStyleModel.ResolveStyle` re-scanned both rule layers and **re-evaluated every
declaration** on every call — `var()` lookups against a linear-scan `TStringList`,
`darken()`/`lighten()`, gradient parsing. `TTyGraphicControl.CurrentStyle`
(`tyControls.Base.pas:602`) calls it on every paint. `ResolveMetric` had the same shape.

Controlled A/B, same load window (bare repaint ~256–281 ms both arms):

| | no memo | memo |
|---|---|---|
| `ResolveStyle('TyButton')` | **0.576 ms/call** | below timer floor |
| `ResolveMetric('--titlebar-height')` | 0.096 ms/call | below timer floor |
| bare full repaint, 60 controls | 256–282 ms | 243–294 ms |
| injected 96 → 240 | 1920–2368 ms | 1280–2176 ms |

**Honest reading: the per-call win is 20×+ and unambiguous; the effect on the DPI
transition and on repaint is NOT resolvable above the noise.** An earlier draft of this
document claimed "9216 ms → 1344 ms" for this change. That was wrong — it compared a
loaded baseline against an idle after. The memo is kept because 0.576 ms for a style lookup
is indefensible on any path that does many of them (theme switching, first paint, layout
arithmetic), not because it was shown to cure the stall. It was not.

Why it does not dominate: `TTyPaintCache` already blits unchanged controls instead of
re-rendering, so a steady-state repaint does not hit the cascade nearly as often as the
call-site count suggests.

### 2c. Where the time actually goes — measured

Splitting the injected transition into the synchronous `SendMessage` (the whole
`AutoAdjustLayout` recursion) and the deferred repaints that follow:

| 60 controls, 96 → 240 | synchronous pass | deferred repaints |
|---|---|---|
| median of 3 | **~1.8 s (≈73%)** | ~0.4–0.8 s |

So the stall is **inside LCL's synchronous per-control pass**, not in painting afterwards.

### 2d. A fix that was tried and REJECTED on the evidence

Bracketing `TTyForm.AutoAdjustLayout` in `DisableAlign`/`EnableAlign` — the obvious
"collapse the realign storm" move, and the one the brief suggested. Implemented, measured
3-vs-3 in one load window, then **removed**:

| synchronous pass, 60 controls | median |
|---|---|
| unbracketed | 1856 ms |
| bracketed | 1728 ms |

Indistinguishable against a canary that itself ranged 320–614 ms. LCL already wraps that
recursion in `DisableAutoSizing`/`EnableAutoSizing`, so there was little left to collapse.
**Do not re-add it without a measurement that clears the noise floor.**

### 2e. The next lever — CONFIRMED, and half of it is already gone (ac2363)

The suspect was the controls' own re-fit work running *inside* the synchronous pass:
`TTyButton.Invalidate` triggers an AutoSize re-fit (note the `FRefitting` re-entry guard at
`tyControls.Button.pas:28`) and that re-fit **measures the caption** through BGRA. Same
family as `memory/memo-text-perf`.

Measured, without touching the library: both measuring methods (`CalculatePreferredSize`
and the new `DoUpdateSizeConstraints`) are virtual, so a probe subclass wraps them with QPC.
60 controls, 96 → 240, injected exactly as §0 describes. Both arms built and run
**alternately in the same load window**, 3 samples each; the per-call cost is carried as the
canary and is identical across arms, so the difference is call COUNT and not machine load.

| 60 controls, 96 → 240 | synchronous pass (median) | inside caption measurement |
|---|---|---|
| before the §4 fix (guard removed) | **1070 ms** | 791 ms in **1120** calls — 74% |
| after the §4 fix | **622 ms** | 362 ms in **480** calls — 57% |
| per measuring call, both arms | — | 0.70–0.76 ms (the canary) |

Two readings, both honest:

1. **The suspicion was right.** Caption re-measurement is 57–74% of the synchronous pass —
   i.e. the majority of the ~73% of the transition that §2c located there. Nothing else in
   the pass comes close.
2. **Roughly half of that work was redundant** and the §4 correctness fix removed it as a
   side effect: suppressing the mid-pass floor recompute takes the measuring calls from
   1120 to 480 and the synchronous pass from ~1.07 s to ~0.62 s, a **42% cut**, with no
   optimisation work at all. The double measurement and the double scaling were the same
   defect seen from two sides.

**The remaining calls are genuine first-time measurements at the new PPI.** Killing them
needs a measurement memo, and the risk is not performance but *staleness*: every one of
these controls re-measures precisely because a theme switch arrives as a bare `Invalidate`,
and a memo keyed on the wrong tuple silently keeps the old theme's width — which is the
ellipsised-toolbar-button bug those `Invalidate` overrides were written to fix. **BUILT in
§2f**, with the enumeration that makes the key safe.

**Hypotheses from the brief that did NOT hold** — do not re-test these:

- *"fonts recreated per control"* — LCL's `ScaleFontsPPI` does it and it is cheap.
- *"the controller broadcasts a full re-apply per control (N× full merge)"* — no.
  `TTyStyleController.Changed` only calls `Invalidate` per control.
- *"no `DisableAlign`/`BeginUpdate` bracket"* — tried; no measurable effect (§2d).
- *"the whole style cascade with no per-PPI cache"* — the cascade was indeed uncached and is
  now memoised, but it is **not** where the seconds are (§2b). Note the memo needs no PPI in
  its key: `ResolveStyle` returns logical values and every call site scales with `MulDiv`.

### 2f. The caption-measurement memo — BUILT (af881)

`TyMeasureTextBlock` and `TyMeasureRenderedTextWidth` (`source/tyControls.Painter.pas`) are
memoised. They are the chokepoint: every size floor in the library reaches the font engine
through one of the two, so no caller changed.

**Where it went, and why not in the control base.** §2e's specification said "a measurement
memo in the control base". It is in the *painter* instead, because the base is not where the
measuring happens — `TTyButton.MeasureCaption` and `TTyLabel.MeasureCaption` both delegate
to these two functions, and a memo one level up would have to be added to each control that
grows a floor and would drift the moment a seventh control appeared. One memo at the
chokepoint covers all of them and cost zero lines in any control.

#### The enumeration — every input, and where it is keyed

The full version, with file:line, is the comment block at `TyInvalidateTextMeasureCache`.
The conclusion:

| # | input | how it is handled |
|---|---|---|
| 1 | caption | in the key |
| 2 | font family | in the key, **as the effective name** — see (8) |
| 3 | font size | in the key, **as the effective size** — see (9) |
| 4 | font weight | in the key, RAW |
| 5 | PPI | in the key |
| 6 | wrap width | in the key (block measure only) |
| 7 | line height | in the key (block measure only) |
| 8 | `TyFallbackFontName` (global) | **folded** into the key via `TyEffectiveFontName` |
| 9 | `TyFallbackFontSize` (global) | **folded** via the new `TyEffectiveFontSizeLogical` |
| 10 | the process font registry | **not keyable** — `TyInvalidateTextMeasureCache` |
| 11 | the widgetset text engine | compile-time; constant per binary |
| 12 | `Screen.PixelsPerInch` | LCL samples it once at startup; process constant |

Two of these decide whether the memo is safe at all:

**(9) is the one that would have shipped the bug.** `TyFallbackFontSize` is rewritten from
the theme's `--font-size-base` on **every** theme apply (`Controller.pas:602`). A control
whose style rule omits `font-size` passes **0** down to the measurement, so the *parameter*
is byte-identical before and after a theme switch and only the global moves. A key built
from the raw parameter therefore hits, and hands back the previous theme's width. That is
the ellipsised-toolbar-button defect arriving through a cache instead of through a stale
`Constraints` floor. Folding the effective value in is what closes it; mutant M10 below is
that hole, and it goes red.

**The theme version is deliberately NOT in the key**, against what the brief proposed. It
would be redundant: items 2,3,4,6,7 *are* the theme's font decision, passed by value by the
caller that already resolved it, and 8/9 are folded. Keying the resolved font tuple is also
strictly *stronger* than keying `ThemeVersion` — a per-control font override moves the tuple
without moving any version counter. The controller drops the memo on `Changed` anyway (one
line, belt and braces, so a *future* theme input to text measurement cannot go stale merely
because nobody extended the key), and the test pins that wiring by entry count rather than
by value, since a value assertion cannot tell "dropped and recomputed" from "the key made it
miss anyway".

**The one dependency that is not observable at measure time is (10).** Registering a font
file makes a family that previously fell back to a default suddenly real, and nothing in the
key can see it coming. So it is handled by explicit invalidation rather than by keying, and
`TyInvalidateTextMeasureCache` is public for exactly that. **Follow-up, not done here
because the file belongs to another agent's scope:** `TTyIconFont.LoadFontFile` and
`UnloadFontFile` (`source/tyControls.IconFont.pas:240`) should each call it — one line each.
Today this is only reachable by a theme naming an icon font as a control's `font-family`,
and `FontFile` is normally set before any control measures, so it is a latent hole rather
than a live defect.

#### Measured — A/B, one binary, one load window

`TyTextMeasureCacheEnabled` is a runtime switch, added so the arms alternate inside one
process rather than across two builds (two builds vary more than the effect). Harness:
`scratchpad/af881_dpiprof`, derived from `ac2363_dpiprof` so the numbers are comparable —
same probe subclasses, same injection, **a fresh form per sample**. That last part matters:
a form re-crossed in a loop asks for **120** measuring calls where a newly shown one asks
for **360**, and 360 is what a real first monitor crossing produces.

**A correction to §2e's call count, since it will not reproduce.** `ac2363_dpiprof`, copied
byte-for-byte and rebuilt against the current tip, reports **360** measuring calls for 60
controls, not the 480 in §2e's table — and a synchronous pass of 438–574 ms against the
622 ms recorded there, at 0.44–0.80 ms per call. The *shape* of §2e's finding is intact
(caption measurement is the majority of the pass and is linear in control count); the two
absolute numbers are not reproducible on today's code and should not be quoted further.

60 controls, 96 → 240, medians of 3, alternating arms, repeated over four runs:

| | memo off | memo on | |
|---|---|---|---|
| canary (bare repaint) | 205–227 ms | 210–228 ms | agree within 5% — the run is valid |
| **cold** synchronous pass | 548–582 ms | 439–502 ms | **76–86%** of it |
| **cold** inside measuring | 288–303 ms | 186–195 ms | **63–66%** of it |
| **cold** hit rate | — | **60%** (180 hits / 120 misses) | |
| **warm** synchronous pass | 555–579 ms | 391–396 ms | **68–71%** of it |
| **warm** inside measuring | 293–297 ms | 118–126 ms | **40–42%** of it |
| **warm** hit rate | — | **100%** (300 / 0) | |

At 180 controls the ratios are identical (cold 1617→1324 ms pass, 914→616 ms measuring), so
it is linear in control count as §2e said.

**Honest reading.** *Cold* is the headline — a first-ever crossing to a new PPI, which is
what a user dragging a window across a monitor boundary for the first time gets. Its 60% hit
rate is **intra-pass** duplication: one pass measures the same caption several times
(360 measuring calls resolve to 120 distinct keys), which is real work removed but is not
the whole prize. *Warm* — crossing back to a PPI already measured, i.e. dragging to and fro,
which Antek's report describes — hits 100% and takes the measuring cost down to 40%.

The measuring-time cut (63–66% cold, 40–42% warm) is the tight, reproducible number; the
whole-pass cut is noisier because the pass contains other work. Both clear the canary's
spread comfortably. **What this does NOT claim:** the pass is not made fast, only shorter.
Caption measurement was 51–57% of it, so removing a third of that is a bounded win, and the
remaining pass is still LCL's per-control recursion.

#### Tests

`tests/test.measurecache.pas`, 17 tests. The staleness half is the load-bearing half:
each keyed input gets a test that measures under configuration A (which *populates* the
memo), changes exactly that one input, measures again and demands a **different** answer —
so an omitted key component makes the second call a hit and the assertion fires. Asserting
the second number alone would pass with or without the memo, which is the fake-green version.

Two things worth knowing before editing them:

- The magnitudes were measured with `scratchpad/af881_probe` **before** the assertions were
  written. Where two configurations happened to measure the same the pair was replaced, not
  the assertion weakened: Arial and Courier New are **both 50 px** wide for the sample
  caption on the LCL canvas, so the family tests use Times New Roman (46) instead. An
  assertion against Courier New would have been green with a completely broken key.
- `ThemeChangeChangesTheMeasuredFontSize` is weaker than it looks and says so at the test:
  **every theme this repo ships declares `--font-size-base: 9`**, so a genuine switch cannot
  currently move the measured number. What the switch proves is that an apply *rewrites* the
  global; the second half stands in for the first theme that disagrees.

#### Mutants — 14, all killed, no survivors

Driver: `scratchpad/af881_mutate.py`. Per `memory/crlf-mutation-phantom-survivor` every
mutant asserts its search-string **hit count** before building (the files are CRLF), and the
source is compared byte-for-byte against a pristine snapshot after each revert — a
replacement that did not land is reported BROKEN, never SURVIVED.

| # | what was broken | killed by |
|---|---|---|
| M1 | key drops the caption | `CaptionChange…` — "a different caption must measure differently" |
| M2 | key drops the font family | `FontFamilyChange…` — "block: a different family must re-measure (50 vs 50)" |
| M3 | key drops the font size | `FontSizeChange…` — "(50 vs 50)" |
| M4 | key drops the weight | `FontWeightChange…` — "block: bold must re-measure (50 vs 50)" |
| M5 | key drops the PPI | `PPIChange…` — "96 vs 144 must differ (50 vs 50)" |
| M6 | key drops the wrap width | `WrapWidthChange…` — "wrapping to 40px must re-measure taller (12 vs 12)" |
| M7 | key drops the line height | `LineHeightChange…` — "a themed line box must re-measure (24 vs 24)" |
| M8 | key drops the font-name LENGTH PREFIX | `FontNameAndCaptionCannotRunTogetherInTheKey` — "(10 vs 10)" |
| M9 | key un-folds `TyFallbackFontName` | `FallbackFontNameChange…` — "(50 vs 50)" |
| M10 | key un-folds `TyFallbackFontSize` | `FallbackFontSizeChange…` — "(50 vs 50)" |
| M11 | controller's invalidation deleted | `TyTextMeasureCacheDropsOnThemeChange` — "expected: \<0\> but was: \<2\>" |
| M12 | the entry cap removed | `CacheIsBounded…` — "5000 distinct captions must not all be retained (kept 5000)" |
| M13 | a hit returns the width as the height | `MemoNeverChangesAnAnswer` — "block height, memo HIT vs memo off, expected: \<12\> but was: \<50\>" |
| M14 | the memo stores but never reads | `RepeatedIdenticalMeasurement…` — "repeats add no misses, expected: \<1\> but was: \<3\>" |

M8 is the one worth keeping: the key ends with the font name followed by the caption, so
concatenated naively family `'A'` + caption `'BC'` and family `'AB'` + caption `'C'` are the
**same string** and the second question is served the first one's answer —
`memory/index-keyed-string-sort-trap` in a different costume. The name is length-prefixed so
the encoding is injective.

**No mutant survived, and nothing in the key is untested.** The only input without a guard is
(10), the process font registry, and that is because it is not in the key by design: there is
no observable hook to key on, so it is handled by explicit invalidation and the missing piece
is the `IconFont` wiring named above, which is one line in a file outside this change's scope.

#### Bounds, and what is NOT done

- The cache is **capped at 4096 entries per cache** and CLEARED (not LRU-evicted) on
  overflow, because the key contains the caption and a caller measuring a stream of distinct
  strings would otherwise grow it for the life of the process. Clearing keeps the only
  invariant that matters — every live entry was computed under the current globals —
  trivially true. `CacheIsBoundedAndNeverGrowsWithoutLimit` asserts the bound, not the
  constant.
- **Not thread-safe**, exactly like `TTyStyleModel`'s resolve cache, and for the same reason:
  both are reached only from control layout and paint, which are main-thread by LCL contract.
- Not attempted: memoising `TTyPainter.MeasureText` (the per-frame painter method, 36 call
  sites). It is on the PAINT path, not the size-floor path, and `TTyPaintCache` already
  blits unchanged controls — the same reason §2b gives for the cascade memo not curing the
  stall. Measure before assuming it is worth a key.

---

## 3. "Far too tall" — double application, and rounding was innocent

`TTyChromeEngine.HandleChangeBounds` used to do:

```pascal
FTitleBar.Height       := TyRescaleChromeMetric(FTitleBar.Height, FInstalledPPI, CurPPI);
FTitleBar.FButtonWidth := TyRescaleChromeMetric(FTitleBar.FButtonWidth, FInstalledPPI, CurPPI);
```

LCL has **already** scaled that bar by the same factor (`TControl.DoAutoAdjustLayout`,
`control.inc:3168`, scales every `alTop`/`AutoSize=False` child). So one monitor crossing
applied the factor twice: a 32 px bar at 100% → 250% came out **216 px instead of 83 px**
(6.75× instead of 2.6×).

**The rounding hypothesis was wrong.** `TyRescaleChromeMetric` rounds half-up, and over
heights 16..120 px against 120/144/240/250 PPI, **three** there-and-back trips return the
exact starting value for **every** height — zero drift. The "×2.5 then ×0.4 loses pixels"
story does not apply to this helper. Pinned in
`TTitleBarDpiTest.TestAccumulatingRescaleSquares`.

**Fixed** in `source/tyControls.Form.pas`: new pure function

```pascal
function TyTitleBarDeviceHeight(AForm; ABar; APPI): Integer;   // MulDiv(logical, APPI, 96)
```

derived from PPI-independent inputs only (a pinned `TitleHeight`, now remembered in
**logical** px, or the theme's `--titlebar-height`). Being a pure function of
`(pin-or-metric, PPI)` it is idempotent, so it cannot compose with LCL's pass into a
squared factor, and a round trip is exact. `FButtonWidth` is no longer rescaled at all: it
now carries the PPI it was pinned at and `EffectiveButtonWidthPx` derives from that pair —
identity at the pinning PPI (so `ButtonWidth := 50` still measures 50, which
`TTitleBarTest.TestExplicitButtonWidthOverridesMetric` pins) and reversible elsewhere.

Verified by the harness: **`FORM` and `TITLEBAR` bounds now round-trip byte-identically.**

---

## 4. "Broken forever" — NOT the chrome. It is the controls' `Constraints` floor. FIXED.

Harness output after the chrome fix, 96 → 240 → 96:

| control | start | at 240 | back at 96 |
|---|---|---|---|
| `TButton` (plain LCL, control group) | H=26 | 65 | **26 — exact** |
| `TTyEdit` | H=26 | 65 | **26 — exact** |
| `TTyButton` | H=29 | 175 | **70** |
| `TTyLabel` | H=26 | 100 | **40** |
| `TTyCheckBox` | H=26, W=120 | 150 | **60, W=150** |

The plain LCL button in the *same form* is perfect, so this is ours, and it is confined to
the controls that write a **device-px floor into `Constraints`**:

- `tyControls.Button.pas:696-697`
- `tyControls.CheckBox.pas:418-419`, `:709-710`
- `tyControls.ToggleSwitch.pas:301,304`
- `tyControls.ButtonGroup.pas:469-470`

Each computes `Constraints.MinWidth/MinHeight` in device px from the live
`Font.PixelsPerInch`. LCL independently scales **both** `Constraints` (via
`TControl.ChangeScale` → `ScaleConstraints`) and the bounds. The two compose exactly the
way the title bar's did — the observed 29 → 175 is `floor(240dpi) × 2.5` — except this one
does not come back, because the floor re-clamps `Height` on the way down.

**FIXED (ac2363).** What follows is what was built, what the original specification got
wrong, and what is still true and not fixed.

### 4a. Two corrections to the diagnosis above

**`ChangeScale`/`ScaleConstraints` are not on this path.** The composition is
`TControl.DoAutoAdjustLayout` → `Constraints.AutoAdjustLayout` (`control.inc:3232` →
`sizeconstraints.inc:267`), which multiplies `MinWidth/MinHeight` by the proportion.
`ScaleConstraints` is only reached from `ChangeScale`, which the per-monitor path never
calls. The arithmetic is the same either way, so the conclusion stands; the file:line does
not.

**The trigger is LCL's own font scaling, not a stray repaint.** `TControl.AutoAdjustLayout`
calls `ScaleFontsPPI` **before** `DoAutoAdjustLayout` (`control.inc:4224`); that sets
`Font.PixelsPerInch` to the new value, `TControl.FontChanged` calls `Invalidate`
(`control.inc:623`), and every one of these controls recomputes its floor from its
`Invalidate` override. So by the time LCL scales `Constraints`, the control has *already*
re-derived them at the new PPI. That is the second application, and knowing it is what
makes the fix one line rather than a redesign.

### 4b. What was built

`tyControls.Base.pas`, twice — the two bases descend from `TGraphicControl` and
`TCustomControl` and share no ancestor below `TControl`:

- `UpdateSizeConstraints` becomes a **guarded entry point** that no-ops while the DPI pass
  is running on this control; the work moves to a new virtual `DoUpdateSizeConstraints`.
  Every existing call site is unchanged, so the guard cannot be forgotten at one of them.
  **This is the fix**; everything else here is secondary.
- `AutoAdjustLayout` is overridden (**it was overridden nowhere in the library before** —
  that part of the finding was exactly right) to raise the flag around `inherited` and then,
  with the flag clear, re-derive the floor once at the settled PPI.

**A third correction, and the one that cost the most: `ParentFont`.** The re-derivation
above must NOT run when the control's font has not yet reached the new PPI, and for the LCL
default (`ParentFont = True`) it has not. `TControl.AutoAdjustLayout` brackets the pass with
`savedParentFont := ParentFont … finally ParentFont := savedParentFont`
(`control.inc:4221/4228`), and restoring `ParentFont` **re-copies the parent's font**, which
is still at the old PPI because `TWinControl.AutoAdjustLayout` walks the children *before*
itself (`wincontrol.inc:3932`). So a ParentFont child leaves its own pass with the font it
started with; the new one arrives later, through the parent's pass and
`CM_PARENTFONTCHANGED`, which reaches `Invalidate` and re-derives the floor correctly with
the guard already down.

Hence the `Font.PixelsPerInch = AToPPI` test on the post-pass call. Without it, the first
version of this fix measured the caption at the OLD PPI and (via a bounds-clamping step
since removed) left `TTyButton` at **175x70 having started at 100x29** — the crossing looked
right and the return was still "broken forever", by a different route. The unit tests all
passed while that was true, because pinning a control's own font to make the harness
host-independent sets `ParentFont := False`. Caught by the §0 probe, which uses the LCL
default. `TestRoundTripsWithTheLclDefaultParentFontToo` now covers it.

The six controls that own a floor rename their method to `DoUpdateSizeConstraints; override`
and change nothing else: `TTyButton`, `TTyCheckBox`, `TTyRadioButton`, `TTyToggleSwitch`,
`TTyButtonGroup`, `TTyLabel`. A sweep of `source/` for device-px `Constraints` writes found
no others — the remaining writes are one-shot LOGICAL values in dialog constructors
(`Dialogs.FileDialog.pas:297`, `Dialogs.Font.pas:133`, `Dialogs.SelectPath.pas:157`,
`Dialogs.pas:877`), which LCL scales correctly and reversibly, exactly like a plain
`TButton`'s. `TTyToolButton` inherits `TTyButton`'s and needs nothing.

Note the shape of the cure, because it is NOT what the specification above proposed. The
floor is **not** converted to a stored logical value scaled by `MulDiv`. It stays MEASURED
at the live PPI, because a measured floor is the only kind that cannot drift from what the
control actually draws — that is what those long comments in the controls are defending,
and a `MulDiv`-scaled floor would re-introduce the clipping they exist to prevent. It is
already a pure function of PPI; the defect was only that it was being applied twice.

### 4c. Verification — and it IS headless

The whole defect reproduces without a window handle. `memory/headless-tests-never-run-lcl-align`
is about the ALIGN engine; `AutoAdjustLayout` is a direct recursion over `Controls[]` that
never asks the align engine for anything. Confirmed identical with a shown window.

`TControlDpiRoundTripTest` in `tests/test.form.pas`, 7 tests, keeping the plain-LCL control
group in the form for exactly the reason given above. Before/after on the §0 probe (a shown
window, LCL-default `ParentFont`):

| control | before: 96 → 240 → 96 | after |
|---|---|---|
| `TButton` (plain LCL) | 26 → 65 → **26** | unchanged |
| `TTyEdit` | 26 → 65 → **26** | unchanged |
| `TTyButton` | 29 → 175 → **70** | 29 → 72 → **29** |
| `TTyLabel` | 26 → 100 → **40** | 26 → 65 → **26** |
| `TTyCheckBox` | 26 → 150 → **60** | 26 → 65 → **26** |
| `TTyToggleSwitch` | w 120 → 488 → 195 → **219** (3 trips) | 120 → 300 → **120** |
| `TTyButtonGroup` | 28 → 98 → **39** | 28 → 70 → **28** |

### 4d. Two limits this fix does NOT remove — read before "improving" the test

**A control sitting exactly on its floor ratchets.** LCL scales bounds and `Constraints`
**proportionally**; a measured floor is **not** exactly proportional to PPI (a caption's ink
is quantised per glyph, and how far from linear depends on the font). A control with no
slack therefore grows at the high PPI — correctly, it needs the pixels — and the
proportional return cannot know to undo it. Measured: with an unpinned system font,
`TTyCheckBox` at exactly its floor came back 4 px wider, `TTyToggleSwitch` 10 px. It
converges after one trip rather than diverging, but it is not byte-exact. That is why
`TControlDpiRoundTripTest` keeps `TySlack` = 4 logical px above each floor, with both bounds
on that number stated at the constant. Closing the gap for real would mean scaling bounds
from LCL's remembered `FBaseBounds` rather than from the current ones — changing what LCL
does — and was not attempted.

**A control can be ~1 px under its floor immediately after a crossing.** `Round(21 × 2.5)`
is 52 (FPC's `Round` is half-to-even) against a re-derived floor of 53. It is corrected by
the next `SetBounds` of any kind, since that is where `Constraints` are applied.

A version of this fix DID push the bounds up at the end of the pass (`ApplySizeFloorToBounds`)
and it was **built, measured and removed**: it does not survive the parent's own pass, which
ends in `EnableAutoSizing` whose deferred autosize restores the child from `FBaseBounds` and
puts the pixel straight back. It worked in the configuration it was written against and
silently did nothing in others, which is worse than a documented tolerance. Do not re-add it
without a test that shows it holding after the FORM's pass, not just the control's.

### 4e. Mutants — including two that SURVIVED, and why they are kept anyway

| # | what was broken | result |
|---|---|---|
| M1a | guard removed from `TTyCustomControl.UpdateSizeConstraints` | **killed** — `TTyButton: 96->240 should scale by about 240/96, got 30 -> 162` + 3 more |
| M1b | guard removed from `TTyGraphicControl.UpdateSizeConstraints` only | **killed** — `TTyLabel: one 96->240 crossing applied the factor TWICE (18 -> 88)` |
| M3 | `TTyButton.Invalidate` calls `DoUpdateSizeConstraints` directly, bypassing the guard (the brief's required mutant: a control mutating its own Constraints) | **killed** — `TTyButton: width after three 96->240->96 trips expected <70> but was <165>` |
| M2 | post-pass re-derivation deleted (LCL's proportional rescale left as the final floor) | **SURVIVED** |
| M5 | the `Font.PixelsPerInch = AToPPI` condition deleted | **SURVIVED** |

M1b is worth its own line: it survived the FIRST version of this test class, because
`TTyLabel` was 26 px tall against a 9 px floor and even a doubly-scaled floor still fitted
inside the box — a textbook centre probe. Sizing every control off its own floor instead of
off a designer's round number is what turned the class into an edge probe.

**M2 and M5 survive, and the code is kept.** Both are first-suspected weak guards, and that
is the right suspicion — here is what was tried and what the evidence is:

- **M2.** Two harsher probes were built and both still passed it: crossing to 137 rather
  than 240 (a non-round ratio), and comparing the crossed floor against a control *born* at
  that PPI (`TestFloorAfterCrossingEqualsFloorBornAtThatPPI`). The reason is that with the
  harness's pinned 9 pt font every floor rescales to exactly the value a fresh measurement
  gives, so "re-derived" and "rescaled" are the same number. They separate only where a
  caption's ink is non-linear in PPI, and the clean font is not. Kept because it is what
  makes the floor `F(current PPI)` rather than a product of round-off factors — the
  invariant the whole document is about — and because deleting it would leave the floor
  provisional until the next repaint.
- **M5.** Made observable, once: adding an `AutoSize` control to the harness killed it
  (100 -> 165), because an AutoSize control resizes the instant `Constraints` move, through
  `DoConstraintsChange -> AdjustSize`, so a floor computed at the wrong PPI shows up in its
  bounds immediately. That control was then **removed** from the harness — AutoSize does not
  run headless (`AutoSizeDelayedHandle`, `memory/headless-tests-never-run-lcl-align`), so it
  drifted 100 -> 165 -> 165 even with correct code and would have been a false red. The
  condition is kept on that evidence plus the direct measurement in §4b.

Both survivors want the same thing to become observable: **a shown-window test**. The §0
probe is exactly that and it catches both; it is not in the suite because the suite is
headless. If someone builds a GUI test target, port the probe into it first.

### 5. A SECOND latch, found by this work — FIXED on the controls, still open on TTyForm

`Font.Height` defaults to 0, meaning "the widgetset default". LCL's DPI pass **replaces**
that 0 with an explicit value on the FIRST crossing, deliberately, so that the font scales
at all — `DoScaleFontPPI`, `control.inc:1972-1973`:

```pascal
if (AFont.Height = 0) and not (csDesigning in ComponentState) then
  AFont.Height := MulDiv(GetFontData(AFont.Reference.Handle).Height,
                         AFont.PixelsPerInch, Screen.PixelsPerInch);
```

The reference is **`Screen.PixelsPerInch`**, not the form's. Those agree on the machine that
drew the form and disagree everywhere else, and the ratio is applied ONCE and never undone.
So a form whose `Font.PixelsPerInch` is 96 (which is what `Application.Scaled` gives it,
`customdesigncontrol.inc:21`) running with a 144-DPI *primary* monitor has every caption
permanently rescaled by 96/144 the first time the window crosses a monitor boundary — before
any of the library's own code runs.

Measured here in the console runner, which reports `Screen.PixelsPerInch` = 72 against fonts
at 96, so the factor is 96/72 = 1.33: across one 96→240→96 trip `TTyCheckBox`'s floor goes
70x17 → 78x20 and `TTyToggleSwitch`'s width floor 108 → 126, and neither comes back. Same
family as everything above — PPI-derived state latched instead of derived — but it happens
one layer below this library and a control cannot see it coming.

The original write-up called this "not guard-shaped" and said the interesting machine could
not be reached from here. **Both of those were wrong, and the corrections are what made the
fix a six-line one.** Recorded in full, because each one was a day saved.

#### 5a. Three corrections to the paragraph above

**It IS guard-shaped, because there is a virtual seam.** `DoScaleFontPPI` is not virtual
(`controls.pp:1561`) so it cannot be replaced — but its only caller,
`TControl.ScaleFontsPPI` (`controls.pp:1695`, `control.inc:872`, invoked from
`AutoAdjustLayout` at `control.inc:4224`), **is** public virtual. That is the boundary, and
overriding it is enough: remember whether `Font.Height` was 0 before `inherited`, put the 0
back after.

**The latch is NOT host-dependent; only its DAMAGE is.** `GetFontData` of a realized font is
never 0, so the `Height = 0 -> Height <> 0` transition fires on **every** machine, at every
crossing, whatever `Screen.PixelsPerInch` says. What needs a non-96 primary is the written
value being *wrong* (by `96/primaryDPI`). So the defect reproduces headless, right here,
and the guard has a real test — which is the opposite of what this section originally
concluded. (This host's `Screen.PixelsPerInch = 72` makes it a non-96-primary case anyway.)

**The blast radius is one function argument, not "every control's font resolution".** A
sweep of `source/` finds `Font.Height` read **nowhere**, and `Font.Size` read **only** as
`TyResolveFontSize`'s `AControlFontSize` (every other hit is a `Canvas.Font.Size` write on a
measuring bitmap). So "unset" has exactly one meaning to defend, and defending it costs the
drawn text nothing: controls scale by `MulDiv(ResolveFontSize(style), Font.PixelsPerInch, 96)`
and `Font.PixelsPerInch` is still set by `inherited`.

Why `Height = 0` is the right representation rather than a remembered flag: `TFont.SetPixelsPerInch`
rescales `Height` only `if Height<>0` (`font.inc:860`), so 0 is **PPI-invariant by
construction** and survives every later crossing with no bookkeeping.

**The other candidate is REJECTED, on a reason worth keeping.** Teaching `TyResolveFontSize`
to prefer the theme over a height it did not author cannot work: after the pass an authored
14 pt and a latched 14 pt are the same bytes, so it would have to demote *both*, breaking
the explicit-`Font.Size` contract that `TFontCascadeTest.TestExplicitControlFontStillWins`
pins. Guarding the representation keeps both cases expressible; guarding the consumer cannot.

#### 5b. What was built

`TTyGraphicControl.ScaleFontsPPI` and `TTyCustomControl.ScaleFontsPPI` in
`tyControls.Base.pas` — twice, same reason as the size floor (no common ancestor below
`TControl`). Rationale lives on the `TTyGraphicControl` declaration.

`tests/test.dpi.fontlatch.pas`, 11 tests, carrying a plain LCL `TButton` as the control
group so that "LCL still latches" is asserted rather than assumed.

#### 5c. Mutants

| # | what was broken | result |
|---|---|---|
| M1 | guard removed from `TTyCustomControl.ScaleFontsPPI` | **killed**, 5 tests — incl. `the THEME must still decide the font size after a round trip ... expected <9> but was <12>` and `TTyCheckBox width floor ... expected <68> but was <76>` |
| M2 | guard removed from `TTyGraphicControl.ScaleFontsPPI` only | **killed**, 2 — `TTyLabel: unset font size after a crossing expected <0> but was <-40>` |
| M3 | guard made unconditional (blanks an authored height too) | **killed**, 2 — `an AUTHORED font size must come back exactly ... expected <14> but was <0>` |
| M4 | guard restores the whole font, not just the marker | **killed** — `the font must still arrive at the new monitor PPI ... expected <240> but was <96>` |

**M3 survived the first version of the test, and that is the entry to read.**
`TestAnAuthoredNegativeHeightIsNotTouched` wrote `Font.Height := -12` — which is exactly
`Font.Size = 9` at 96 PPI, i.e. the value the probe had **already** inherited from the form.
`TFont.SetHeight` exits without firing `Changed` when the value is unchanged, so `ParentFont`
was never cleared, nothing was ever authored, and the `-30` the test saw after the crossing
came from the form's font being copied down afterwards. A textbook centre probe, and
invisible: every number in it looked right. Found only by instrumenting the run. The test now
authors `-20` (differs from the inherited value, and round-trips exactly through `MulDiv`)
and asserts `ParentFont = False` as a precondition, which is the line that stops it
regressing.

Instrumenting that also settled a scope question for free: **for a `ParentFont = True` child
the guard is irrelevant either way.** `TWinControl.AutoAdjustLayout` walks children before
itself (`wincontrol.inc:3932-3935`), so the parent's font arrives afterwards through
`CM_PARENTFONTCHANGED` and overwrites whatever the child's own pass left. The guard earns its
keep on `ParentFont = False` controls — which is exactly where `TyResolveFontSize` consults
`Font.Size` at all.

#### 5d. What is NOT fixed: TTyForm's own font

`TTyForm` is neither of the two guarded bases, and `tyControls.Form.pas` was out of scope.
A form's `Font.Height` is 0 by default, so it still latches, and the latched height still
reaches every `ParentFont = True` child. Today that is harmless to font RESOLUTION —
`TyResolveFontSize` ignores `Font.Size` entirely while `ParentFont` is True — but it is not
harmless to the size floors, and it is why `TControlDpiRoundTripTest` still pins
`FForm.Font.Size := 9`.

Measured, both directions, so the next person does not have to:

- delete the pin, keep everything else: **six of seven tests stay green**, and
  `TestRoundTripsWithTheLclDefaultParentFontToo` — the only one running the LCL-default
  `ParentFont = True` — fails with `TTyToggleSwitch: width after three 96->240->96 trips
  expected <120> but was <126>`. That 126 is the same number this section recorded above.
- delete the pin **and** add the identical six-line override to `TTyForm.ScaleFontsPPI`:
  **all seven pass.**

That is the whole of the follow-up: the same guard, on `TTyForm`, in `tyControls.Form.pas`,
after which the pin in `TControlDpiRoundTripTest.Build` (both the form's and the per-control
`FCtls[i].Font.Size := 9`) can go and the class becomes an unpinned round-trip test. The pin
says all of this, at the pin.

Still genuinely unreachable from here: whether the value LCL writes is *correct*. That needs
a machine whose primary monitor is not 96 DPI. The guard makes the question moot for ty
controls — an unset size never becomes a written one — but a plain LCL control in a ty form
is still subject to it, and that is LCL's behaviour, not ours.
