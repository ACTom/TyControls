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

Not changed here: flipping the examples to `PerMonitorV2` is a real behaviour change for
every example and belongs with whoever owns `examples/`. It is, however, the only way this
class of bug gets caught in-house. **Recommended: set `DpiAware = True/PM` on at least
`examples/containers` and `examples/demo` and re-shoot their screenshots.**

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

### 2e. The next lever, and why it is not mine

The remaining suspect is the controls' own re-fit work, which runs *inside* that synchronous
pass: `TTyButton.Invalidate` triggers an AutoSize re-fit (note the `FRefitting` re-entry
guard at `tyControls.Button.pas:28`), and that re-fit **measures the caption** through BGRA.
The DPI pass changes the font and the bounds of every control, so every control re-measures
its text, repeatedly. That is the same family as the already-known
`memory/memo-text-perf` (uncached text measurement) finding.

To confirm: instrument `MeasureCaption`/`CalculatePreferredSize` with a call counter and a
QPC total, run the injected transition, and compare against the 1.8 s. If it lands, the fix
is a per-(text, font, PPI) measurement memo, and it belongs in the control base.

**Hypotheses from the brief that did NOT hold** — do not re-test these:

- *"fonts recreated per control"* — LCL's `ScaleFontsPPI` does it and it is cheap.
- *"the controller broadcasts a full re-apply per control (N× full merge)"* — no.
  `TTyStyleController.Changed` only calls `Invalidate` per control.
- *"no `DisableAlign`/`BeginUpdate` bracket"* — tried; no measurable effect (§2d).
- *"the whole style cascade with no per-PPI cache"* — the cascade was indeed uncached and is
  now memoised, but it is **not** where the seconds are (§2b). Note the memo needs no PPI in
  its key: `ResolveStyle` returns logical values and every call site scales with `MulDiv`.

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

## 4. "Broken forever" — NOT the chrome. It is the controls' `Constraints` floor.

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

**NOT FIXED HERE: those files belong to other agents this round.**

### Specification for whoever picks it up

The invariant to restore is the one the chrome now obeys: *PPI-derived state must be a pure
function of (PPI-independent input, current PPI) — never `X := f(X)`.*

Concretely, in `tyControls.Base.pas` (shared base, so it is one change rather than five):

1. Add a protected `procedure ApplyMetricFloor(AMinW, AMinH: Integer)` that records the
   **logical** floor and the PPI it was computed at, and writes `Constraints` from that pair.
2. Override `TControl.DoAutoAdjustLayout` (currently overridden **nowhere** in the entire
   library — `grep` for it returns zero hits, which is the deeper finding) in the TyControls
   windowed and graphic bases so that the control re-derives its floor at the new PPI
   **instead of** letting LCL multiply the recorded one. LCL's `ScaleConstraints` must not
   also run on a value the control re-derives.
3. Pin it with the same three shapes used for the title bar:
   *scales with PPI*, *idempotent at one PPI*, *exact across three 96→240→96 trips*.

Verification cannot be headless: `AutoSizeDelayedHandle` means the align engine never runs
without a shown window (`memory/headless-tests-never-run-lcl-align`). Use the harness in §0
— a shown form plus a bounds dump — and keep the plain-LCL control group in it, because
that control group is the only reason the ownership question was answerable in one run.
