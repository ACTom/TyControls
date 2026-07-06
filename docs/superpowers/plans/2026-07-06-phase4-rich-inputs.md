# Phase 4 — Rich Inputs & Pickers — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development. This is the **phase-level** plan for Phase 4 of [the controls-expansion roadmap](../specs/2026-07-05-controls-expansion-roadmap.md). One plan per phase; each control below is a task built on the shared approach. Ship **one control (or a small sibling batch) per merge**.

**Goal:** The "cheap long tail" — ~26 specialized inputs and pickers, each a thin **subclass of an existing control** (`TTyEdit` / `TTyComboBox` / `TTyListBox`) plus a small amount of format/parse/validation or custom item-draw. Low individual risk; the value is breadth + parity with the reference suites.

**Shared architecture:**
- **Formatted edits subclass `TTyEdit`** — no base refactor needed; it already exposes the hooks: override `UTF8KeyPress` (filter keystrokes), `DoEnter`/`DoExit` (toggle raw↔formatted so the caret never fights a live-formatted string — edit RAW, display FORMATTED on blur), `DoChange` (re-parse), and add a typed `Value`/`AsInteger`/`AsFloat` property over the public `Text`. Reuse the `'TyEdit'` typeKey (+ a trailing button drawn like `TTySpinEdit`'s where a picker/drop is needed). No new `.tycss` for the plain ones.
- **Pickers subclass `TTyComboBox` / `TTyListBox`** — prefill items, add a **custom per-item paint** (colour swatch, font-rendered name, checkbox) via the existing item-draw path, reuse `'TyComboBox'`/`'TyListBox'`/`'TyListItem'` typeKeys.
- **Colour/font data is theme-neutral** — named-colour tables and `Screen.Fonts` are data, not style; only the swatch/selection chrome is themed.
- Pure logic (parse/format/mask-apply/clamp) lives in **free functions, unit-tested headlessly** (the Phase-1/2 discipline). No GUI needed to test the hard part.

**Per-control checklist (same as Phase 1/2):** control unit + pure-logic tests · reuse an existing typeKey (or add `.tycss` in all 6 themes + compiled + `GGRID` golden ONLY if a genuinely new surface) · palette registration in a **`TyControls` sub-group** (Phase-4 inputs → the **`TyControls`** standard tab or **`TyControls Buttons`**/a new **`TyControls Pickers`** tab; colours/fonts → a **`TyControls Pickers`** tab) + generated icon (genicons glyph + `array[0..N]` bound + `$classes`/`CClasses` drift-guards + regen `.lrs`) · `.lpk` unit entry · `docs/controls/<name>.md` + index row · headless tests · an `examples/inputs/` showcase (new, grows per control) · NO changelog per control (release-time only).

**Tech Stack:** FPC/Lazarus, BGRABitmap, `.tycss`, fpcunit.

---

## Build order (reference impl first per sub-family, then its cheap siblings)

### A. Formatted edits (subclass TTyEdit)
- [ ] **TTyNumericEdit** — REFERENCE IMPL. Float/int edit: `Value: Double`, `DecimalPlaces`, `ThousandsSeparator`, `MinValue`/`MaxValue`, edit-raw/display-grouped on blur. Pure `TyFormatNumber`/`TyParseNumber` unit-tested. Establishes the subclass pattern every edit below copies.
- [ ] **TTyCurrencyEdit** — NumericEdit + a currency symbol + default 2 dp (mostly config).
- [ ] **TTyMaskEdit** — input mask (`##/##/####`, `(###) ###-####`). Pure `TyMaskApply(mask, raw)` + `TyMaskIsComplete` unit-tested; override `UTF8KeyPress` to route through the mask.
- [ ] **TTyURLEdit** — edit that renders its text as an accent hyperlink + a trailing "open" button (reuse `TTyLinkLabel` cursor/colour + `OpenURL`).
- [ ] **TTyTrackEdit** — edit paired with an inline `TTyTrackBar` (compose, not subclass): the bar sets the number, the edit echoes it.
- [ ] **TTyComboEdit** — edit + a generic drop-down button firing `OnDropDown` to an arbitrary popup (base for Calc/Colour combos).
- [ ] **TTyCalcEdit / TTyCalcCurrencyEdit / TTyCalculator** — a drop-down calculator (Calculator is the standalone; the edits embed it in a `TTyDropdownPopup`). Bigger; do last in A.

### B. Colour pickers (subclass TTyComboBox / TTyListBox / new small surfaces)
- [ ] **TTyColorBox** — REFERENCE IMPL for pickers. Combo of named colours, each item a swatch + name (custom item paint). Establishes the "subclass combo + per-item draw" pattern.
- [ ] **TTyColorComboBox** — ColorBox + a "more…" row opening the existing `TTyColorDialog`.
- [ ] **TTyColorListBox** — the list-box form of ColorBox.
- [ ] **TTyColorGrid** — a palette grid of swatches (extract the grid from `TTyColorDialog`).
- [ ] **TTyHSColorPicker / TTyLColorPicker** — hue/sat square + luminance bar (extract from `TTyColorDialog`'s internals into reusable controls).

### C. Font pickers (subclass TTyComboBox / TTyListBox)
- [ ] **TTyFontComboBox** — REFERENCE for font pickers: `Screen.Fonts` combo, each item drawn IN its own font. Pure nothing; the item-paint sets the font name.
- [ ] **TTyFontListBox** — the list form.
- [ ] **TTyFontSizeComboBox** — a size combo (6..72 presets, editable).

### D. Enhanced lists & combos (subclass TTyListBox / TTyComboBox)
- [ ] **TTyCheckListBox** — list with a checkbox per row (`Checked[i]`, custom item paint + hit-test on the box).
- [ ] **TTyCheckComboBox** — combo whose drop-down is a CheckListBox; the field shows a comma summary.
- [ ] **TTyMRUComboBox** — most-recently-used history combo (push/dedupe/cap).
- [ ] **TTyComboBoxEx** — combo with a per-item image/indent (icon-font aware).
- [ ] **TTyHorzListBox** — horizontally scrolling list.
- [ ] **TTyOfficeListBox / TTyOfficeComboBox / TTyAdvancedListBox / TTyAdvancedComboBox** — grouped/headered list/combo variants (do last; most involved).

### E. Property editor
- [ ] **TTyValueListEditor** — two-column name/value editor (a light inspector; a focused mini-grid — do last in the phase, may borrow layout ideas we'll reuse for the Phase-8 Grid).

## Palette note
Phase-4 controls register into the **`TyControls`** standard tab (the plain edits) or a **new `TyControls Pickers`** tab (colour/font/value pickers) — keep the drift-guard happy (group-description comments on their own line before each `RegisterComponents`).

## Phase review + wrap
- [ ] Adversarial review across the phase (parse/format edge cases: empty, sign, overflow, locale separators; mask completeness; item hit-testing; no hard-coded colours; HiDPI).
- [ ] Update [[controls-expansion-program]] memory. Decide Phase 5 vs continue. Changelog at release time.

## Self-review notes
- The genuinely hard bit is **format/parse and caret behaviour** — solve it once in TTyNumericEdit (edit-raw / display-formatted-on-blur) and copy. Do NOT live-format while typing (caret hell).
- Reuse existing controls/dialogs: `TTyColorDialog` (colour internals), `TTyTrackBar`, `TTyLinkLabel`, `TTyDropdownPopup`, `TTySpinEdit`'s trailing-button geometry.
- Most controls add NO new typeKey (reuse TyEdit/TyComboBox/TyListBox/TyListItem) → no golden churn; only a genuinely new surface (e.g. the HS colour square) needs theme rules.
