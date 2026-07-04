# Phase 1 — Graphics & Instruments — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. This is the **phase-level** plan for Phase 1 of [the controls-expansion roadmap](../specs/2026-07-05-controls-expansion-roadmap.md). It covers the whole graphics/instrument batch; each control is a task built on the shared approach below (we write ONE plan per phase, not per control).

**Goal:** Ship a family of custom-drawn, `.tycss`-themed **graphic/instrument controls** — value gauges, meters, dials, clock, circular/activity indicators — playing to BGRABitmap's anti-aliased arc/needle strengths and rendering pixel-identical on Windows/Linux/macOS (the axis where ty-controls beats the GDI+-only reference suites).

**Shared architecture (established by TTyGauge, the reference impl):**
- Leaf `TTyGraphicControl` (no focus/children); interactive ones (Dial) use `TTyCustomControl`.
- Painted via `TTyPainter`: arcs/needles via the public `Painter.Bitmap.Canvas2D` (BGRABitmap — `arc`/`lineWidth`/`lineCap`/`strokeStyle`/`beginPath`/`stroke`); bars via `FillBackground`. No new painter primitives needed.
- **Two-typeKey colour split** where a control has "track vs value": `TyXxx` (track/text/thickness) + `TyXxxFill` (value fill), mirroring `TyProgressBar`/`TyProgressFill` — no style-model change, fully theme-customizable. Resolve track via `CurrentStyle`, fill via `ActiveController.Model.ResolveStyle('TyXxxFill', StyleClass, [])`.
- Value changes ease via the animation kernel (`TTyAnimator` + lazy `TTimer`), **snapping headless** (no parent handle) so render/golden tests stay pixel-stable.
- Pure geometry (fraction/angle/needle math) lives in free functions, unit-tested without a GUI.

**Per-control checklist (the "done" definition, same every time):** control unit + pure-geometry tests · `.tycss` rules in all 6 themes + regenerate compiled themes (`gen-defaulttheme.ps1` for light, `gen-builtinthemes.ps1` for auto+system) + add typeKeys to `GGRID` and regenerate the light/dark/showcase goldens (a **text** resolved-style dump — run the theme test, review the `.actual` diff shows ONLY the new keys, copy over `.golden.txt`) · palette registration + generated icon (genicons glyph + `$classes`/`CClasses` sync + regenerate `.lrs`) · `.lpk` unit entry · `docs/controls/<name>.md` + index row · an `examples/` showcase. (No CHANGELOG per control — the changelog is written at RELEASE time only.)

**Tech Stack:** FPC/Lazarus, BGRABitmap (`Canvas2D`), `.tycss`, fpcunit.

---

## Task 1 — TTyGauge  ✅ DONE (reference implementation)

Value gauge: `gsLinearH/gsLinearV/gsArc/gsRing` over `Min/Max/Value: Double`, `Thickness/StartAngle/SweepAngle/ShowValue/ValueFormat`, eased animation. typeKeys `TyGauge`+`TyGaugeFill`. Unit `source/tyControls.Gauge.pas`; tests `test.gauge`; docs `docs/controls/gauge.md`; example `examples/gauge/`. Commits c4aeb7f · b682955 · dc4c114 · c55f03a. Suite 1654/0/11. **This is the template every task below copies.**

## Task 2 — TTyCircularProgress

- [ ] Determinate ring progress (essentially `TTyGauge` in `gsRing` with a fixed style + a simpler API: `Position/Min/Max`, no needle). May subclass or wrap the gauge arc renderer. typeKeys `TyCircularProgress`/`TyCircularProgressFill` (or reuse gauge tokens). Geometry reuses `TyGaugeFraction`. Full per-control checklist. Commit.

## Task 3 — TTyActivityIndicator

- [ ] Indeterminate spinner: a rotating arc gap (or dot ring) animated by the kernel on a continuous `TTimer` (no value). `Active: Boolean` starts/stops. typeKey `TyActivityIndicator`. Headless: no animation (handle-less) so it's render-stable. Checklist. Commit.

## Task 4 — TTyMeter

- [ ] Analog needle meter over a scaled arc: `Min/Max/Value`, `StartAngle/SweepAngle` (covers 90°/120°/270° variants), tick marks + optional numeric tick labels, a needle from the hub. Pure `needle-angle(value)` helper unit-tested. typeKeys `TyMeter` (dial face/ticks/text) + `TyMeterNeedle`. Checklist. Commit.

## Task 5 — TTyLevelMeter

- [ ] VU / level bar: horizontal or vertical, segmented or gradient fill, optional peak-hold marker. `Value/Min/Max/Orientation/Segments`. typeKeys `TyLevelMeter`/`TyLevelMeterFill`. Checklist. Commit.

## Task 6 — TTyDial (interactive)

- [ ] Rotary knob — drag / mouse-wheel rotates the needle to set `Value` (so `TTyCustomControl` with MouseDown/Move/Up + wheel + focus). `Min/Max/Value/StartAngle/SweepAngle`, optional detents. Reuses the meter needle math. typeKeys `TyDial`/`TyDialNeedle`. Checklist. Commit.

## Task 7 — TTyAnalogClock

- [ ] Hour/minute/second needles from `Time` (or a `Time` property), driven by a 1s `TTimer`. Pure `hand-angle(h,m,s)` helpers unit-tested. typeKey `TyClock` (+ hand colours via variants or fixed tokens). Checklist. Commit.

## Task 8 — TTyGearDial / TTyGearActivityIndicator  (decorative variants, optional)

- [ ] Gear-styled dial + gear spinner if time allows — decorative siblings of Dial/ActivityIndicator sharing their engines. Checklist each. Commit.

## Task 9 — Phase review + wrap

- [ ] Adversarial review across the batch (angle math at edges, animation cleanup on destroy, no hard-coded colours, HiDPI via `Scale`). Fix findings.
- [ ] Update [[controls-expansion-program]] memory (Phase 1 done). Decide Phase 2 vs continue (per the roadmap's decision gate). At release time, write the CHANGELOG for the whole batch.

## Self-review notes
- One plan per PHASE (this doc), not per control — each task above is a control built by copying the TTyGauge template.
- Sparkline / Rating / Switch / UpDown from the roadmap's Phase-1 list are folded in as optional later tasks or deferred; the core instrument family (gauge/meter/dial/clock/indicators) is the spine.
- Golden regeneration is headless (text dump); the only "gotcha" is remembering to run both theme generators before the sync tests.
