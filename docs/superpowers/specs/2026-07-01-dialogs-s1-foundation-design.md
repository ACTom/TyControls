# Dialog Foundation (Dialogs Program · S1) — Design

**Goal:** A custom-drawn, themed modal-dialog foundation — the `TTyDialog` base, a global-function
+ non-visual-component pattern, the first concrete dialog (`TyMessage`), an IDE "TyControls Dialog"
New-item, and a "TyControls Dialogs" palette group.

**Architecture:** `TTyDialog = class(TTyForm)` — a borderless, non-resizable, centered, close-only
window (Phase-1 chrome) shown via LCL `ShowModal`. It offers a code-friendly layout API: a **content
area** plus a bottom **button bar** (`AddButton` → right-aligned `TTyButton`s wired to `ModalResult`),
and auto-sizes to its content. Each concrete dialog exposes a **`Ty`-prefixed global function** (the
real API) AND a thin **non-visual `TComponent`** with `Execute` (a design-time "reminder"); both share
one internal builder. The build (construct + lay out) is separated from the show (`ShowModal`) so the
layout and result mapping are unit-testable headlessly without blocking.

**Tech stack:** Lazarus/FPC, LCL, BGRABitmap; builds on `tyControls.Form` (P1 chrome),
`tyControls.Button`, `tyControls.Painter` (glyphs), the theme Controller. New unit
`source/tyControls.Dialogs.pas`. Headless fpcunit.

**Roadmap context:** S1 of the P2–P4 dialogs sub-program (P1 form chrome DONE + merged). S2 (simple
text dialogs: Input/Password/Text/SelectValue/SelectPath) and S3/S4 (Color/Font pickers,
Find/Replace, Progress) build on this foundation in later specs. Naming is decided: `Ty`-prefixed
globals (no shadowing of LCL). Heavy dialogs (Print/PageSetup/file-preview) deferred.

---

## Current state (from code map)
- No dialog/modal units exist. The only modal precedent is `TTyAboutForm = class(TForm)` (a plain LCL
  form, `ShowModal`, design-time only) — not custom-drawn; irrelevant to this design beyond confirming
  `ShowModal` works in-repo.
- `TTyGlyphKind` (`tyControls.Painter.pas:14`) = `(tgClose, tgMinimize, tgMaximize, tgRestore, tgCheck, …)`
  — has **no** message-type icons (warning/error/info/question); S1 adds them.
- Palette has one group `'TyControls'` (`designtime/tyControls.Design.pas:540`); IDE New-items include
  `'TyControls Form'`, `'TyControls Main Form'`, `'TyControls Application'`.

## Design

### A. `TTyDialog` base (`source/tyControls.Dialogs.pas`)
- `TTyDialog = class(TTyForm)`. Constructor sets `BorderIcons := [biSystemMenu]` (close only),
  `Resizable := False`, `Position := poMainFormCenter` (fallback `poScreenCenter`), `KeyPreview := True`,
  and an auto-created top `TTyTitleBar` (P1 chrome). The title-bar close (X) sets `ModalResult := mrCancel`.
- **Layout regions:** a bottom **button bar** (fixed height = one themed button + margins) and, above it,
  a **content area** (`function ContentRect: TRect`) where a concrete dialog places its widgets.
- **Button bar API:**
  `function AddButton(const ACaption: string; AResult: TModalResult; ADefault: Boolean = False; ACancel: Boolean = False): TTyButton;`
  Buttons are `TTyButton`s parented to the bar, laid out **right-aligned, right-to-left in add order**
  (so the primary/rightmost is added last or flagged). Clicking a button sets `Self.ModalResult := AResult`.
  `ADefault` → the Enter key fires it (`TTyButton.Default`-style; via `KeyPreview`); `ACancel` → Esc fires it.
- **Auto-size:** `procedure AutoSizeToContent(AContentW, AContentH: Integer)` sets the client size to
  `max(AContentW, sum-of-button-widths) × (titlebar + content + buttonbar)` and re-centers.
- **Modal:** inherits `TForm.ShowModal`; the builder calls it. Result is whatever a button set (or
  `mrCancel` on close/Esc).
- **Pure, testable button-bar layout** (no window):
  `function TyDialogButtonBar(const ASizes: array of TSize; ABarWidth, AMargin, ASpacing: Integer): TTyRectArray;`
  right-aligns the buttons within `ABarWidth`, `AMargin` from the right edge, `ASpacing` between.

### B. Global-function + component pattern (per dialog)
- Every concrete dialog provides (a) `Ty`-prefixed **global functions** — the primary API, usable by just
  `uses tyControls.Dialogs` — and (b) a thin **non-visual component** `TTyXxx = class(TComponent)` with
  published inputs/outputs and `function Execute: Boolean`. Both call one internal builder that
  constructs a `TTyDialog`, populates it, `ShowModal`s, and maps the result. The component is a
  design-time discoverability aid ("we ship this"); the functions are the real interface.
- The builder seam is `Build… : TTyDialog` (construct-only, no show) + a `Run(dlg): TModalResult`
  (calls `ShowModal`) so tests can inspect the built dialog without blocking.

### C. `TyMessage` (S1's pattern proof, in `tyControls.Dialogs.pas`)
- **Reuse LCL enums** `TMsgDlgType` (`mtWarning/mtError/mtConfirmation/mtInformation/mtCustom`) and
  `TMsgDlgButtons`/`TMsgDlgBtn` (`mbYes/mbNo/mbOK/mbCancel/mbAbort/mbRetry/mbIgnore/mbAll/mbNoToAll/
  mbYesToAll/mbClose/mbHelp`) from `Dialogs`/`Controls` — so signatures mirror LCL's, only `Ty`-prefixed.
- **Global functions:**
  - `procedure TyShowMessage(const AMsg: string);`
  - `function TyMessageDlg(const AMsg: string; ADlgType: TMsgDlgType; AButtons: TMsgDlgButtons; AHelpCtx: Longint = 0): TModalResult;`
  - `function TyMessageDlgPos(...; X, Y: Integer): TModalResult;` and `TyMessageFmt(const AMsg: string; const Args: array of const; …)`.
- **Layout:** type icon (left) + wrapped message text (right) in the content area; standard buttons on
  the bar. `TyShowMessage` = information + `[mbOK]`.
- **Type icons:** add `tgDialogInfo, tgDialogWarning, tgDialogError, tgDialogQuestion` to `TTyGlyphKind`
  and `TTyPainter.DrawGlyph`, drawn in a **semantic color** (info/question = accent, warning = amber,
  error = red) taken from theme tokens where available, else fixed fallbacks.
- **Pure, testable mappings:**
  - `function TyMsgButtonCaption(ABtn: TMsgDlgBtn): string;` (mbYes→'Yes', …; resourcestring-backed).
  - `function TyMsgButtonResult(ABtn: TMsgDlgBtn): TModalResult;` (mbYes→mrYes, mbOK→mrOk, …).
  - `function TyMsgOrderedButtons(AButtons: TMsgDlgButtons): TMsgDlgBtnArray;` (stable display order).
  - `function TyMsgTypeGlyph(ADlgType: TMsgDlgType): TTyGlyphKind;` and `TyMsgDefaultCancel/Default(AButtons)`.
- **Component** `TTyMessage = class(TComponent)`: published `Title`, `Msg`, `DlgType`, `Buttons`;
  `function Execute: TModalResult` delegating to `TyMessageDlg`. A "reminder" component.

### D. IDE integration (`designtime/tyControls.Design.pas`)
- Register `TTyDialog` as a designer base class (`FormEditingHook.RegisterDesignerBaseClass`) and add a
  New-item **"TyControls Dialog"** file descriptor: a unit whose form `= class(TTyDialog)`, pre-fitted
  with a top `TTyTitleBar` (`BorderIcons=[biSystemMenu]`, non-resizable), for users to design their own
  dialogs.
- **Remove "TyControls Main Form" from the New-item list** (stop calling `RegisterProjectFileDescriptor`
  for it) — but KEEP the `TTyMainFormFileDescriptor` class, since the "TyControls Application" descriptor
  uses it internally to spawn the app's main form.
- Add a second palette group **`RegisterComponents('TyControls Dialogs', [TTyMessage])`** (S2–S4 append
  their components here).

### E. Theming
- `TTyDialog` reuses `TyForm` (surface/backdrop) and `TTyButton` (`TyButton`) theme tokens — a dialog is
  a form. The button bar draws no separate fill (transparent over the form surface). No new required
  token; a `TyDialog` surface token may be added later if a dialog needs to differ from a plain form.
- Message type-icon semantic colors read from theme tokens if present (`--error`, `--warning`, `--info`),
  else fixed fallbacks; documented as a follow-up to add explicit semantic tokens.

## Error handling
- Title-bar close / Esc → `ModalResult := mrCancel` (dialog returns cancel).
- No main form (console/early) → `poScreenCenter`.
- `TyMessageDlg` with `AButtons = []` → defaults to `[mbOK]` (never a button-less dialog).

## Testing (headless fpcunit, `tests/test.dialogs.pas`)
1. **Button-bar layout** `TyDialogButtonBar`: right-alignment, order, spacing, margin; single vs several.
2. **Message mappings** (pure): `TyMsgButtonCaption`, `TyMsgButtonResult`, `TyMsgOrderedButtons`
   (order stable + complete over a full `TMsgDlgButtons`), `TyMsgTypeGlyph`, default/cancel selection.
3. **Builder (construct-only, no ShowModal)**: `BuildMessageDialog(msg, mtConfirmation, [mbYes,mbNo])`
   returns a `TTyDialog` whose button bar has 2 buttons with captions 'Yes'/'No' and `ModalResult`
   `mrYes`/`mrNo`, a default (Yes) and a cancel (No), and a content area holding the message — asserted
   without showing. (Uses `SetDesigning` where needed to avoid engine-arming, per P1.)
4. **`TTyMessage.Execute`** wiring: the component delegates to the same builder (verify via the
   construct-only seam, not a real modal).
5. **Glyphs**: `DrawGlyph` renders each new `tgDialog*` kind without exception (render-to-bitmap).

## Non-goals (S1)
- S2–S4 dialogs (Input/Password/Text/SelectValue/SelectPath/Color/Font/Find/Replace/Progress).
- Explicit semantic theme tokens (`--error/--warning/--info`) — fixed fallbacks for now, noted.
- Non-modal dialogs (Find/Replace are S4).

## Files
- **Create** `source/tyControls.Dialogs.pas` — `TTyDialog` base + button-bar (incl. `TyDialogButtonBar`),
  builder seam, `TyMessage` globals + mappings + `TTyMessage` component. Add to `tycontrols.lpk`.
- **Modify** `source/tyControls.Painter.pas` — 4 `tgDialog*` glyph kinds + `DrawGlyph` cases.
- **Modify** `designtime/tyControls.Design.pas` — register `TTyDialog` base class + "TyControls Dialog"
  New-item; drop "TyControls Main Form" from the New list; `RegisterComponents('TyControls Dialogs', …)`.
  Add the descriptor + icon.
- **Create** `tests/test.dialogs.pas` (registered in the runner) — the tests above.
- **Modify** the runtime package + design-time package unit lists as needed.
