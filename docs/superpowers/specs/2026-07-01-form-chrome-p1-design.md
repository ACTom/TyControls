# Form Chrome — BorderIcons-driven caption buttons (Dialogs Program · Phase 1) — Design

**Goal:** Make `TTyForm`'s caption buttons follow the standard LCL `BorderIcons`, lock the
form to borderless (`bsNone`), gate maximize/resize via `Resizable`, give `TTyTitleBar` its own
per-button switches for standalone use, and guard TitleBar association to the owning form.

**Architecture:** `TTyForm` is a borderless (`bsNone`) custom-chrome form; a `TTyTitleBar`
control draws the caption + minimize/maximize/close buttons. Which buttons show is resolved by a
**pure function** of `(BorderIcons, Resizable)`. When a TitleBar is associated with a `TTyForm`,
the form drives the TitleBar's `Show*` switches from `BorderIcons`/`Resizable` live; a standalone
TitleBar (dropped on a panel, no owning `TTyForm`) uses its own `Show*` switches.

**Tech stack:** Lazarus/FPC, LCL; existing `source/tyControls.Form.pas`
(`TTyForm` / `TTyTitleBar` / `TTyCaptionButton`); headless fpcunit tests.

**Roadmap context:** Phase 1 of a dialogs program. Later, one combined effort delivers the
`TTyDialog` base + IDE "TyControls Dialog" New-item + custom-drawn dialogs (Message with global
`ShowMessage`/`MessageDlg`, Input, Password, Text, SelectValue, SelectPath, Color, Font, Find,
Replace, Progress). Heavy dialogs (Print family, PageSetup, file Open/Save preview) are deferred to
a later discussion. This spec covers **Phase 1 only**.

---

## Current state (from code map)

- `TTyTitleBar` owns `FMinButton` / `FMaxButton` / `FCloseButton`; today their visibility is driven
  by `TTyForm.ShowMinimize` / `ShowMaximize` (there is **no** `ShowClose`; close is always shown),
  and it does **not** read `BorderIcons`.
- `TTyForm.SetTitleBar` has **no** cross-form ownership check.
- `TTyForm` is already borderless with `WindowEffects` rounded corners; `Resizable` gates edge-drag
  resize; `Resizable=False` today *disables* (not hides) the max button.

## Design

### A. `TTyForm` property model

1. **`BorderStyle` → locked `bsNone`, hidden from the Object Inspector.**
   - Constructor sets `bsNone`; a redeclared setter coerces any assigned value back to `bsNone`
     (silent, no exception — the property is simply locked).
   - Design-time: register a hidden property editor for `TTyForm.BorderStyle` so it does not appear
     in the Object Inspector.
2. **`BorderIcons` → source of truth for the caption buttons.**
   - `biSystemMenu` → Close, `biMinimize` → Minimize, `biMaximize` → Maximize.
   - Redeclared/hooked setter re-syncs the associated TitleBar and relayouts on change.
   - Default stays the LCL `TForm` default `[biSystemMenu, biMinimize, biMaximize]`.
3. **`Resizable: Boolean` (kept, writable).** Gates edge-drag resize **and** the maximize button:
   the max button shows only when `biMaximize ∈ BorderIcons` **and** `Resizable`. Setter re-syncs
   the TitleBar.
4. **Remove `TTyForm.ShowMinimize` / `ShowMaximize`** (hard delete — fields, setters, published
   props). All repo usages (demo `.lfm`, showcase, IDE templates, tests) are cleaned in this phase.
   Breaking change: an old `.lfm` that set these props will fail to load; acceptable, we own the
   repo and bump the minor version.

### B. Button-visibility resolution — pure function

```pascal
type
  TTyCaptionButtonFlag  = (cbfMinimize, cbfMaximize, cbfClose);
  TTyCaptionButtonFlags = set of TTyCaptionButtonFlag;

function TyResolveCaptionButtons(ABorderIcons: TBorderIcons;
  AResizable: Boolean): TTyCaptionButtonFlags;
// cbfClose    in Result  <=>  biSystemMenu in ABorderIcons
// cbfMinimize in Result  <=>  biMinimize   in ABorderIcons
// cbfMaximize in Result  <=>  (biMaximize  in ABorderIcons) and AResizable
```

Pure and side-effect-free (lives in `tyControls.Form.pas`), so the mapping is unit-tested in
isolation without constructing a window.

### C. `TTyTitleBar` per-button switches

- Published `ShowMinimize` / `ShowMaximize` / `ShowClose: Boolean` (default `True`). Each setter
  sets the matching button's `Visible` and calls `LayoutButtons`.
- **Standalone** (no owning `TTyForm`): these are the configuration.
- **Associated**: the owning form is authoritative — it pushes
  `ShowMinimize/ShowMaximize/ShowClose` from `TyResolveCaptionButtons(BorderIcons, Resizable)`
  whenever `BorderIcons` / `Resizable` change or the bar is (re)associated. Manual edits on an
  associated bar are overwritten on the next form-driven sync (documented).
- The max button keeps its existing behavior of switching to the restore glyph (`cbkRestore`) while
  the form is maximized.

### D. Own-form association guard (item ②)

- `TTyForm.SetTitleBar(AValue)`: if `AValue <> nil` and `GetParentForm(AValue) <> Self`, raise
  `EInvalidOperation` with a clear message
  (`'TTyTitleBar can only be associated with the form it belongs to'`). Applies both design-time and
  runtime.
- The existing auto-association via `Notification(opInsert)` only ever associates own-form bars, so
  the guard's job is to reject **manual** cross-form assignment.

### E. Sync flow

On any of {`BorderIcons` set, `Resizable` set, TitleBar (re)associated, form maximize/restore}:
recompute `TyResolveCaptionButtons`, push the three `Show*` onto the associated TitleBar,
`LayoutButtons`, `Invalidate`.

## Error handling

- Cross-form TitleBar assignment → `EInvalidOperation` (fail-fast, visible in the IDE too).
- `BorderStyle` assigned anything other than `bsNone` → silently coerced to `bsNone` (locked).

## Testing (headless fpcunit)

1. **`TyResolveCaptionButtons`** — table of `(BorderIcons, Resizable)` → expected flags: all-icons +
   resizable → min/max/close; `biMaximize` without `Resizable` → no max; empty set → no buttons;
   `[biSystemMenu]` only → close only.
2. **Form drives bar** — headless `TTyForm` + associated `TTyTitleBar`: set `BorderIcons`, assert the
   three buttons' `Visible` match.
3. **Resizable gates max** — `Resizable := False` hides the max button even with `biMaximize`.
4. **Association guard** — `SetTitleBar` with a bar whose `GetParentForm <> Self` raises
   `EInvalidOperation`; a same-form bar succeeds.
5. **BorderStyle locked** — assigning `bsSizeable` leaves `BorderStyle = bsNone`.
6. **Standalone switches** — a TitleBar with no owning form: toggling `ShowMinimize/Maximize/Close`
   toggles the corresponding button `Visible`.

## Non-goals

- `biHelp` / a help caption button (YAGNI; add later if needed).
- Any dialog work (P2–P4) — separate spec.
- Changing the minimize/maximize/close **actions** (already wired via
  `DoMinimizeClick`/`DoMaxRestoreClick`/`DoCloseClick`).

## Files

- **Modify** `source/tyControls.Form.pas` — `TyResolveCaptionButtons` pure fn; `TTyForm`
  `BorderStyle` lock + `BorderIcons`/`Resizable` sync + remove `ShowMinimize/ShowMaximize` + the
  association guard; `TTyTitleBar` `ShowMinimize/ShowMaximize/ShowClose` switches.
- **Modify** `designtime/tyControls.Design.pas` — hidden property editor for `TTyForm.BorderStyle`;
  drop any `ShowMinimize/ShowMaximize` references in the New-item templates.
- **Modify** `examples/demo/*.lfm`, other `examples/**`, and tests — remove `ShowMinimize`/
  `ShowMaximize` usages.
- **Add** `tests/test.formchrome.pas` (or extend `tests/test.form.pas`) with the six tests above,
  registered in the test runner.
