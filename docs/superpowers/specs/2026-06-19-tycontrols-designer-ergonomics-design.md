# TyControls Designer Ergonomics — Design

**Date:** 2026-06-19
**Status:** Approved (design) — awaiting spec review → plan

## Goal

Two independent "designer ergonomics" improvements, shipped under one spec/plan:

1. **Sensible default sizes** for the four controls that currently fall back to LCL's tiny default when dropped on a form.
2. **A full component-palette icon set** — a distinct 24×24 icon for every registered TyControls component, so the IDE palette and form show real glyphs instead of the default blank/placeholder icon.

Both are design-time-facing. Neither changes runtime rendering.

---

## Sub-project ① — Default control sizes

### Problem

When a control is dropped on a form, the IDE uses the size set in the control's constructor. Audit of every control constructor:

| Already sized (leave untouched) | W×H |
|---|---|
| TyPanel | 185×41 |
| TyGroupBox | 185×105 |
| TyComboBox | 145×26 |
| TyScrollBar | 16×160 |
| TyListBox | 160×120 |
| TyProgressBar | 200×20 |
| TyToggleSwitch | 44×24 |
| TyTrackBar | 160×24 |
| TyTabControl | 300×200 |
| TySpinEdit | 120×28 |
| TyMemo | 200×120 |

`TyLabel` intentionally auto-sizes to its caption (has `DoSetBounds`/`PreferredWidth`) — leave it.

The four with **no** constructor size fall back to the LCL `TCustomControl` default (~tiny), which is the reported "默认大小有点小":

### Fix

Set a default `Width`/`Height` in each of the four constructors (96-dpi logical px, scaled per DPI by the LCL exactly like the existing sizes above):

| Control | File | Default W×H |
|---|---|---|
| `TTyButton` | `source/tyControls.Button.pas` | 88 × 30 |
| `TTyEdit` | `source/tyControls.Edit.pas` | 140 × 28 |
| `TTyCheckBox` | `source/tyControls.CheckBox.pas` | 130 × 22 |
| `TTyRadioButton` | `source/tyControls.CheckBox.pas` (same unit) | 130 × 22 |

Values chosen to comfortably hold a typical caption plus the control's own chrome (box/circle/padding), matching the look of the controls that already have defaults. The user can still resize freely; this only sets the drop default.

### Tests

`tests/test.*.pas` for each control: after `Create`, assert `Width`/`Height` equal the chosen defaults. TDD: write the failing assertion, set the default, green. (Existing per-control test units already exist for all four.)

---

## Sub-project ② — Component-palette icon set

### Style (approved)

**Line + accent**, 24×24 RGBA, transparent background:

- Monochrome outline glyph in a single foreground color.
- One **accent** color on each control's "value / active" element (the check, the radio dot, the toggle knob, the progress fill, the active tab, etc.). Controls with no obvious active element stay monochrome.
- Foreground: a near-neutral dark ink (`#3C3C3C`). Static PNGs can't adapt to IDE theme, so we target the **default light component palette** (the common case, and what stock LCL icons assume); on a dark-themed IDE palette the neutral lines will read faintly — accepted trade-off, revisitable later via `_dark` resource variants if anyone asks.
- Accent: the default theme's light accent, **`#3B82F6`** (fixed — palette icons are static PNGs and cannot follow the live theme).
- Stroke ~1.7px (scaled into the 24px raster), round caps/joins.

Scope: **all 20 registered components** (`designtime/tyControls.Design.pas` `RegisterComponents` list), including the non-visual `TTyStyleController` and `TTyPopupMenu`.

HiDPI: **24px only** for now. The SVG/geometry source means 150%/200% variants can be added later without rework. (Out of scope here.)

### Generation pipeline

Mirrors the existing `gen-*.ps1` "generate from source, commit the artifact" pattern (e.g. `tyControls.BuiltinThemeData.pas`). All in the project's own FPC + BGRABitmap stack — no external image editor, no SVG-parser dependency:

```
glyph geometry (Pascal, in the generator)
        │  draw each glyph with BGRABitmap primitives (lines/rects/circles/polylines)
        ▼
  20 × 24×24 RGBA PNG   (tools/genicons output)
        │  lazres.exe  (C:\lazarus\tools\lazres.exe, confirmed present)
        ▼
  designtime/tycontrols_icons.lrs   (LazarusResources.Add('TTyButton','PNG',[...]) per class)
        │  {$I tycontrols_icons.lrs} immediately before RegisterComponents
        ▼
  IDE palette shows each icon, looked up by class name
```

Why draw with BGRA primitives rather than rasterize SVG: the glyphs are simple geometric shapes (the geometry is fully specified in the Appendix), BGRABitmap is already a hard dependency, and this avoids relying on `TBGRASVG` being available. The geometry is the editable source of truth; regenerating is one script run.

Why `lazres` for packing: it produces exactly the `.lrs` format stock Lazarus packages use (verified against `components/anchordocking/anchordockpanel_icon.lrs`: `LazarusResources.Add('<ClassName>','PNG',[<bytes>])`). Resource name = the PNG filename stem, so PNGs are named `TTyButton.png`, …

### File structure

- **Create** `tools/genicons/genicons.lpi` + `genicons.pas` — FPC console app. Uses `BGRABitmap`, `BGRABitmapTypes`. Contains the 20 glyph-draw routines (geometry in Appendix) and a table mapping class name → draw routine. Renders each to a 24×24 transparent `TBGRABitmap`, `SaveToFile('<out>/<ClassName>.png')`.
- **Create** `scripts/gen-icons.ps1` — orchestrator: `lazbuild tools/genicons/genicons.lpi` → run `genicons.exe <pngdir>` → `lazres designtime/tycontrols_icons.lrs <pngdir>/*.png` (resource names come from filenames). Echoes the 20 class names packed.
- **Create** `designtime/tycontrols_icons.lrs` — generated artifact, committed (like `BuiltinThemeData.pas`).
- **Modify** `designtime/tyControls.Design.pas` — add `LResources` to `uses`; add `{$I tycontrols_icons.lrs}` in `Register` immediately before the `RegisterComponents('TyControls', [...])` call.
- **Create** `tests/test.paletteicons.pas` — see Testing.

### Wiring detail (Design.pas)

```pascal
uses
  Classes, Controls, ... , LResources, ... ;   // + LResources

procedure Register;
begin
  {$I tycontrols_icons.lrs}      // LazarusResources.Add('TTyButton','PNG',[...]) × 20
  RegisterComponents('TyControls', [ ...the existing 20 classes... ]);
  // ...existing property/component editor registrations unchanged...
end;
```

### Testing

Icons are visual IDE resources, so the meaningful automated guard is **pipeline correctness**, not pixels:

`tests/test.paletteicons.pas` — a fpcunit test unit that `{$I}`-includes `designtime/tycontrols_icons.lrs` in its own `initialization` (the test binary does not link the dt package, so there is no duplicate-resource clash), then for each of the 20 class names asserts:
- `LazarusResources.Find('<ClassName>') <> nil` (resource present), and
- its `ValueType = 'PNG'`.

This fails loudly if the generator/`lazres` step drops a class, renames one, or emits the wrong format. Add the test to the test project so the existing `lazbuild tests/tytests.lpi && tytests -a` run covers it.

A second lightweight check belongs in the generator itself (not fpcunit): after drawing, assert each bitmap is exactly 24×24 before saving.

### Out of scope

- HiDPI (`_150`/`_200`) icon variants — deferred; SVG/geometry source makes them additive later.
- Live-themed icons — palette icons are static resources; the accent is the fixed `#3B82F6`.
- Any runtime rendering change.

---

## Verification (manual, post-merge)

1. Run `scripts/gen-icons.ps1` → regenerates `designtime/tycontrols_icons.lrs`.
2. `lazbuild tycontrols_dt.lpk`, reinstall the design-time package, restart Lazarus.
3. Component palette → "TyControls" tab shows a distinct icon per control; dropping any control shows the icon on the form's tree and a sensible default size.

---

## Appendix — glyph geometry (24×24 coordinate space)

Foreground stroke `#3C3C3C` (class `g`), accent `#3B82F6` (fill = `af`, stroke = `a`); stroke-width ~1.7 unless noted. These are the exact shapes from the approved mockup, plus the eight not shown there.

| Class | Geometry |
|---|---|
| `TTyButton` | rounded rect (3,7,18,10,r3); accent label line (8,12)→(16,12) w2.4 |
| `TTyLabel` | "A": polyline (6,18)(12,6)(18,18); crossbar (8.6,13.2)→(15.4,13.2) — monochrome |
| `TTyEdit` | rect (3,7,18,10,r2); accent caret (7,9.5)→(7,14.5) w2; faint text line (10,12)→(16,12) w1.3 op.55 |
| `TTyCheckBox` | rounded square (4,4,16,16,r3); accent check polyline (8,12.4)(11,15.4)(16,8.6) w2.2 |
| `TTyRadioButton` | circle (12,12,r8); accent dot circle (12,12,r3.1) filled |
| `TTyComboBox` | rect (3,7,18,10,r2); chevron polyline (13.5,10.8)(16,13.4)(18.5,10.8) — monochrome |
| `TTyToggleSwitch` | pill rect (3,8,18,8,r4); accent knob circle (16.5,12,r2.7) filled |
| `TTyTrackBar` | line (3,12)→(21,12); ticks (6,10.4-13.6),(18,10.4-13.6); accent thumb (12,12,r3) filled |
| `TTyProgressBar` | track rect (3,9,18,6,r3); accent fill rect (3,9,10,6,r3) filled |
| `TTyListBox` | rect (3,4,18,16,r2); rows (6,9)→(18,9) accent w2, (6,13)→(18,13), (6,17)→(15,17) |
| `TTyTabControl` | accent active tab rect (3.5,5,8,5.5,r1.5) filled; inactive tab rect (12.5,6.2,7.5,4.3,r1.5); body rect (3,10,18,10,r2) |
| `TTyGroupBox` | rect (4,7,16,13,r2); accent caption line (6.5,7)→(11.5,7) w2.6 |
| `TTyPanel` | plain rounded rect (3,5,18,14,r2) — monochrome |
| `TTyScrollBar` | track rect (9,3,6,18,r3); up chevron (10.5,7)(12,5.5)(13.5,7); down chevron (10.5,17)(12,18.5)(13.5,17); accent thumb rect (9.5,10,5,5,r1.5) filled |
| `TTySpinEdit` | field rect (3,7,12,10,r2); accent caret (6,9.5)→(6,14.5) w2; divider (15,7)→(15,17); up chevron (16.5,11)(18,9.5)(19.5,11); down chevron (16.5,13)(18,14.5)(19.5,13) |
| `TTyMemo` | page rect (3,3,18,18,r2); text lines (6,8)→(17,8), (6,12)→(17,12), (6,16)→(13,16) — monochrome |
| `TTyTitleBar` | window rect (3,4,18,16,r2); title divider (3,9)→(21,9); control dots (15,6.5)(17,6.5) primary r0.9, (19,6.5) accent r0.9 filled |
| `TTyMenuBar` | bar rect (3,6,18,6,r2); segments (6,9)→(8,9) accent, (10,9)→(12,9), (14,9)→(16,9) |
| `TTyStyleController` | rounded square (4,4,16,16,r3); accent lower-left triangle (5,19)(19,19)(5,5) filled (theme light/dark split) |
| `TTyPopupMenu` | panel rect (4,3,15,18,r2); rows (7,7)→(16,7), (7,11)→(16,11) accent, (7,15)→(16,15) |
