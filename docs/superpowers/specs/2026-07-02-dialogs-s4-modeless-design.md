# Modeless Dialogs (Dialogs Program · S4) — Design

**Goal:** Non-modal Find/Replace dialogs (`TTyFindDialog`/`TTyReplaceDialog` — component + events, LCL
`TFindDialog` parity) and a Progress dialog (`TTyProgressDialog` — a stateful, app-driven object with
optional Cancel), on the existing `TTyDialog` base.

**Architecture:** These are **modeless** — they call `Show` (not `ShowModal`) and stay open, driving
work through events/callbacks rather than returning a modal result. Each is a **component that owns a
`TTyDialog`-derived form** (lazy-created with the component as `Owner`, reused across invocations, hidden
— not freed — on close, and freed automatically with the component). Action buttons use
`ModalResult = mrNone` (verified to NOT close the dialog) + an `OnClick` that fires the component's event.
Because the inherited modal `KeyDown` is inert without a modal loop (see below), each owned form overrides
`KeyDown` for Esc/Enter. No global functions (a one-shot global can't carry the modeless "stay open + call
back" lifecycle) — components-only, matching LCL.

**Tech Stack:** Lazarus/FPC, LCL (`TFindOptions`/`TFindOption` from `Dialogs`, `TCloseAction`), builds on
`tyControls.Dialogs` (S1–S3: `TTyDialog`, `AddButton`, `ContentRect`, `AutoSizeToContent`, `TyPlacePrompt`,
`TyDlgPad`), `tyControls.Edit`, `tyControls.CheckBox`, `tyControls.Button`, `tyControls.TyLabel`,
`tyControls.ProgressBar` (`TTyProgressBar`: `Min`/`Max`/`Position` + pure `TyProgressFillRect`). Reuses the
`FClosing` re-entrant-close guard idiom from `TTyDropdownPopup` (`tyControls.Popup.pas:214`). Headless
fpcunit.

**Roadmap context:** S4 of the P2–P4 dialogs sub-program (P1 chrome, S1 foundation, S2 input family,
S3 pickers all DONE + merged). After S4, only the deferred heavy dialogs (Print/PageSetup/file-preview)
remain. This is the first **modeless** family — all prior dialogs were modal `ShowModal`.

---

## Current state (from S1–S3 + adversarial verification)
- `TTyDialog(TTyForm)` is a `TForm` descendant, so `Show` works and it stays interactive modeless.
  `ContentRect`/`AddButton`/`AutoSizeToContent`/`TyPlacePrompt`/`TyDlgPad` are all reusable. But:
- **⚠ The inherited `KeyDown` is MODAL-ONLY.** `TTyDialog.KeyDown` handles Enter → `ModalResult := FDefaultResult`
  and Esc → `CancelDialog` (→ `ModalResult := FCancelResult`), then sets `Key := 0`
  (`tyControls.Dialogs.pas:361–373`). `TCustomForm.SetModalResult` only stores the field
  (`customform.inc:1740`); the code that turns a non-zero `ModalResult` into a close lives ONLY inside
  `ShowModal`'s loop (`customform.inc:3047`). **On a modeless (`Show`-n) form there is no such loop, so
  Enter/Esc do nothing** — and `Key := 0` even swallows Esc so it can't fall through. **Therefore each
  owned modeless form MUST override `KeyDown` for Esc/Enter** (below); it must not rely on the inherited
  `ModalResult` path.
- **`mrNone` button = non-closing** (`TTyButton.Click`, `tyControls.Button.pas`): only sets the host
  `ModalResult` when `FModalResult <> mrNone`; otherwise `inherited Click` fires `OnClick` and the dialog
  stays open. The S1 New-Folder idiom — reused for Find Next / Replace / Replace All.
- **Hide-not-free reuse rests on `TForm` close mechanics, not on `TTyDropdownPopup`.** `caHide` is already
  the LCL default `CloseAction` for a **non-main** modeless form (`customform.inc:2156`); the X routes
  through `TTyForm.DoCloseClick → Close → OnClose` (`tyControls.Form.pas:1223`). So the only hard
  requirements are (a) the owned form is never the application main form, and (b) the component frees it.
  With `Owner = <the component>` (`CreateNew(Self)`, mirroring the S1–S3 `CreateNew(Application)` owner
  pattern at `tyControls.Dialogs.pas:458`), the form is freed automatically when the component is; the
  destructor only nils the cached reference. `TTyDropdownPopup` is cited ONLY for its `FClosing`
  re-entrant-close guard (`tyControls.Popup.pas:214`) — it hides via a direct `FForm.Hide`
  (`Popup.pas:221`), wraps a `bsNone` `CreateNew(nil)` popup, and is a `TObject` (not a `TComponent`), so
  it is not a lifecycle model for these titled, reusable dialogs.
- **`TTyProgressBar`** (`tyControls.ProgressBar.pas`, a `TTyGraphicControl` — no handle, headless-safe):
  `Min`/`Max`/`Position: Integer`, determinate only (no marquee), theme-rendered; public pure
  `TyProgressFillRect(ATrack, AMin, AMax, APos): TRect`; animation snaps headless. Embed via `SetBounds`.
- **LCL `TFindOptions`** = `set of TFindOption` (in the **`Dialogs`** unit): `frDown, frFindNext,
  frMatchCase, frWholeWord, frReplace, frReplaceAll, frEntireScope, frHideMatchCase, frHideWholeWord,
  frHideUpDown, frHideReplace, frDisable*`, etc. S4 reuses the type wholesale; the UI drives the common
  subset (`frMatchCase`, `frWholeWord`, `frDown`) and the buttons stamp the action flags (`frFindNext`,
  `frReplace`, `frReplaceAll`) — see §B. LCL defaults: `TFindDialog.Options default [frDown]` (constructor
  seeds `[frDown]`, `finddialog.inc:605`); `TReplaceDialog` adds `[frReplace, frReplaceAll]`
  (`replacedialog.inc:650`).

## Design

### A. Modeless base pattern (shared by all three)
Each component owns a `TTyDialog`-derived form:
- **Design-time guard (REQUIRED):** every public entry point (`Execute`/`Show`) begins with
  `if csDesigning in ComponentState then Exit(...);` — the component must NEVER create or show a real
  chrome window inside the IDE designer. (Contrast `tyControls.Form.pas:1062/1110`, which guards
  `csDesigning` before arming live window behaviour.)
- **Lazy create, owned by the component:** on first run, `FForm := TTy<X>Form.CreateNew(Self)` (Owner =
  the component), built once (widgets + buttons + `KeyDown` override), and cached. Owner = the component ⇒
  the form is freed automatically when the component is destroyed; the destructor just nils `FForm`.
- **Modeless show:** `FForm.Show` (never `ShowModal`).
- **Reuse, don't free, on close:** the form is not the main form, so its default `CloseAction` is `caHide`
  — the X button / `Close` hides it and it is reused next run. (An explicit `OnClose`
  `CloseAction := caHide` is added as a defensive assertion only, not because it is load-bearing.) A
  `FClosing` flag guards re-entrant close (mirror `tyControls.Popup.pas:214`).
- **KeyDown override (REQUIRED — the inherited one is inert modeless):** the owned form overrides
  `KeyDown`:
  - `VK_ESCAPE` → the Escape action (Find/Replace: `Hide`; Progress: fire Cancel iff `Cancelable`, else
    ignore), `Key := 0`.
  - `VK_RETURN` → the default action (Find: `DoFindNext`; Replace: `DoReplace`; Progress: ignore),
    `Key := 0`.
  - any other key → `inherited KeyDown` (so normal editing in the edits still works).
  It does NOT call the inherited Enter/Esc `ModalResult` branches.
- **Action buttons:** added via `TTyDialog.AddButton(caption, mrNone)` (mrNone ⇒ non-closing) + an
  `OnClick` that forwards to a **public** `Do…` method (so tests can invoke it headless — see §E); a
  dedicated **Close** button calls `Hide`.

### B. Find / Replace — `source/tyControls.Dialogs.Find.pas`
- **Components** (registered on the "TyControls Dialogs" palette):
  `TTyFindDialog = class(TComponent)` and `TTyReplaceDialog = class(TTyFindDialog)` (Replace extends Find).
- **Published props (LCL parity):**
  - `TTyFindDialog`: `FindText: string`, `Options: TFindOptions read FOptions write SetOptions default [frDown]`,
    `Position: TPosition` (default `poScreenCenter`), `OnFind: TNotifyEvent`. Constructor seeds
    `FOptions := [frDown]` (so the dialog defaults to searching **down**, matching LCL — an empty set
    would silently default to searching up).
  - `TTyReplaceDialog` adds `ReplaceText: string`, `OnReplace: TNotifyEvent`; its constructor adds
    `FOptions := FOptions + [frReplace, frReplaceAll]` (LCL Replace defaults).
  - `function Execute: Boolean;` — `if csDesigning in ComponentState then Exit(False);` then build (lazy) +
    sync the form from the props + `Show` modeless (returns True = shown).
  - `procedure CloseDialog;` — `FForm.Hide`.
- **The owned form** `TTyFindForm = class(TTyDialog)` (Replace variant adds the replace row + buttons):
  `TTyLabel`+`TTyEdit` for Find (and Replace), `TTyCheckBox` **Match case** + **Whole word**, a **Search
  up** `TTyCheckBox` (checked ⇒ `frDown` cleared), and buttons **Find Next** / (**Replace** / **Replace
  All** for Replace) / **Close** (action buttons `mrNone` + `OnClick`).
- **Public action seams** (the `OnClick` handlers forward to these; tests invoke them directly):
  - `procedure DoFindNext;` — write the editors back to the component (`FindText`, `Options` via the pure
    mapping below), then **stamp the Find-Next action flags** `Options := Options - [frReplace, frReplaceAll] + [frFindNext]`,
    then fire the component's `OnFind`.
  - `procedure DoReplace;` (Replace form) — write back (incl. `ReplaceText`), stamp
    `Options := Options + [frReplace] - [frReplaceAll, frFindNext]`, fire `OnReplace`.
  - `procedure DoReplaceAll;` (Replace form) — write back, stamp
    `Options := Options + [frReplaceAll] - [frFindNext, frReplace]`, fire `OnReplace`.
  - **Replace and Replace All fire the SAME `OnReplace`;** the app tells them apart via
    `frReplaceAll in Options` (LCL contract — `replacedialog.inc:535`). The app's handler reads
    `FindText`/`ReplaceText`/`Options` and searches/replaces in its own text control.
- **Pure, testable option mapping** (the UI-independent checkbox round-trip):
  ```pascal
  type TTyFindChecks = record MatchCase, WholeWord, SearchUp: Boolean; end;
  function TyFindOptionsToChecks(AOpts: TFindOptions): TTyFindChecks;   // frMatchCase/frWholeWord/(not frDown)
  function TyChecksToFindOptions(const AChecks: TTyFindChecks; ABase: TFindOptions): TFindOptions;
  ```
  `frDown` set ⇔ `SearchUp` False. `ABase` preserves flags the checkboxes don't touch (`frReplace`,
  `frReplaceAll`, `frEntireScope`, the `frHide*`/`frDisable*` UI gates); the action-flag stamping above is
  applied AFTER this mapping, in each `Do…` method.
- **No global functions** (modeless + event-driven — matches LCL, which also has no `Find(...)` global).

### C. Progress — `source/tyControls.Dialogs.Progress.pas`
- **Stateful component** `TTyProgressDialog = class(TComponent)`:
  - Published: `Caption: string`, `Text: string` (the status line), `Min`/`Max`/`Position: Integer`,
    `Cancelable: Boolean`, `OnCancel: TNotifyEvent`. Read-only `Cancelled: Boolean`.
  - Methods: `procedure Show;` (`if csDesigning… then Exit;` then build lazy + `Show` modeless),
    `procedure Step(ADelta: Integer = 1);`, `procedure SetProgress(APos: Integer; const AText: string = '');`
    (clamps to `Min..Max`, updates the bar + label, then pumps `Application.ProcessMessages` so the bar
    repaints and a Cancel click is processed), `procedure Close;` (Hide + reset `Cancelled`).
  - **Re-entrancy guard (REQUIRED):** `SetProgress` is guarded by an `FInPump` flag — if a pumped message
    re-enters `SetProgress`, the nested call skips its own `ProcessMessages`. (`ProcessMessages` is the
    **first use in the whole `source/` tree**; the guard + the `OnCancel` constraint below make it safe.)
- **The owned form** embeds a `TTyProgressBar` (`Min`/`Max`/`Position` mirrored from the component) + a
  `TTyLabel` (the `Text`), and — when `Cancelable` — a **Cancel** button (`mrNone` + `OnClick` →
  `DoCancel`: `FCancelled := True` + fire `OnCancel`). Esc, when `Cancelable`, routes to the same
  `DoCancel`.
- **Usage (app-driven loop):**
  ```pascal
  Prog.Min := 0; Prog.Max := N; Prog.Cancelable := True; Prog.Show;
  for i := 0 to N-1 do begin
    if Prog.Cancelled then Break;
    DoWork(i);
    Prog.SetProgress(i+1, Format('Processing %d/%d', [i+1, N]));
  end;
  Prog.Close;
  ```
- **v1 = determinate + optional Cancel.** Indeterminate/marquee is a NON-GOAL (the bar has no marquee
  style; deferred).

### D. IDE + i18n
- Register `TTyFindDialog`, `TTyReplaceDialog`, `TTyProgressDialog` on the existing
  `RegisterComponents('TyControls Dialogs', …)` (`designtime/tyControls.Design.pas`); add the 2 new units
  to its `uses` + `tycontrols.lpk`. Default palette glyphs.
- New built-in text → `tyControls.StrConsts` + zh_CN: `rsDlgFindNext = 'Find Next'`, `rsDlgReplace = 'Replace'`,
  `rsDlgReplaceAll = 'Replace All'`, `rsDlgClose = 'Close'`, `rsDlgFindWhat = 'Find what:'`,
  `rsDlgReplaceWith = 'Replace with:'`, `rsDlgMatchCase = 'Match case'`, `rsDlgWholeWord = 'Whole word'`,
  `rsDlgSearchUp = 'Search up'`, `rsDlgCancel = 'Cancel'`. (Caller-supplied `Caption`/`Text` are not
  translated.)

### E. Theming
All reuse `TyForm` + `TyButton` + the embedded controls' tokens; the progress bar uses its existing
`TyProgressFill` token. No new required token.

## Error handling
- Modeless `Execute`/`Show` returns immediately; there is no "cancel result" — dismissal is the Close
  button / X / Esc (→ `Hide`, form reused). `Execute`/`Show` return False (or no-op) at design time.
- A Find with an empty `FindText` still fires `OnFind` (the app decides) — no forced validation.
- `SetProgress` clamps out-of-range to `Min..Max`. `Cancelled` is read-only (set only by `DoCancel`);
  `Close` resets it for the next run.
- **`OnCancel` / `OnFind` / `OnReplace` handlers MUST NOT `Free` the dialog component or its owned form**
  (they may fire synchronously from inside `SetProgress`'s pumped `ProcessMessages`, so freeing would be a
  use-after-free). They should only set state / call `Close`/`CloseDialog`. Documented in the unit header +
  the demo.
- Re-entrant close guarded by `FClosing`; `SetProgress` re-entrancy guarded by `FInPump`.
- The owned form is freed with the component (Owner = the component); the destructor nils the cached ref.
- No main form (console/early) → `poScreenCenter`.

## Testing (headless fpcunit)
`tests/test.dialogs.find.pas` (new) + `tests/test.dialogs.progress.pas` (new), registered in `tytests.lpr`:
1. **Find option mapping (pure):** `TyFindOptionsToChecks`/`TyChecksToFindOptions` round-trip over the
   relevant `TFindOptions` subsets; `frDown`⇔`SearchUp=False`; `ABase` preserves untouched flags
   (`frReplace`/`frEntireScope`). Default `Options = [frDown]` (Find) / `[frDown,frReplace,frReplaceAll]`
   (Replace).
2. **Find/Replace event + action-flag wiring (construct-only, NO Show):** build the owned form (a public
   builder/seam), set the Find edit's text + toggle Match-case, call the **public `DoFindNext`** seam
   (NOT `TTyButton.Click` — avoids the `GetParentForm` walk), and assert (a) `OnFind` fired, (b) `FindText`
   reflects the edit, (c) `Options` reflects the checks AND `frFindNext in Options` and
   `frReplace/frReplaceAll not in Options`. For Replace: `DoReplace` → `OnReplace` fired, `frReplace in
   Options`, `frReplaceAll not in Options`, `ReplaceText` set; `DoReplaceAll` → `OnReplace` fired,
   `frReplaceAll in Options`, `frFindNext not in Options`.
3. **Progress logic (construct + pure):** `SetProgress` clamps to `Min..Max`; `Step` accumulates; the
   public **`DoCancel`** seam sets `Cancelled` + fires `OnCancel`; `Close` resets `Cancelled`;
   `TyProgressFillRect` fill geometry (min/max/mid).
- **Do NOT** call `Show`/`ShowModal`/`SetDesigning` or `Application.ProcessMessages` in tests. The modeless
  `Show`, the live repaint, the app loop, and the real Enter/Esc keystrokes are GUI (real-machine eyeball)
  — the option mappings, the construct-only builders, and the `Do…`-seam→event/flag wiring are the
  headless-tested surface. NOTE: unlike the S3 dialogs (whose handlers call modal `TySelectColor` and are
  GUI-only), these `Do…` handlers read handle-free fields (`TTyEdit.Text`, `TTyCheckBox.Checked`) and fire
  an event — so they ARE headless-invocable; that is why they are exposed as public methods.
- **Baseline after S3 merge: 1593 run / 0 failures / 11 errors** — keep failures 0, errors 11.

## Non-goals (S4)
- Global convenience functions for Find/Replace/Progress (components-only, per LCL).
- Indeterminate/marquee progress; nested/stacked progress; a built-in search engine (the app searches in
  `OnFind`/`OnReplace` — the dialog only gathers input + fires events).
- `frPromptOnReplace` interactive per-match prompting UI (the app can implement it via `OnReplace`).
- Custom palette icons for the 3 components (default glyph).

## Files
- **Create** `source/tyControls.Dialogs.Find.pas` — `TTyFindForm` (+ `DoFindNext`/`DoReplace`/`DoReplaceAll`
  + `KeyDown` override) + `TTyFindDialog` + `TTyReplaceDialog` + the option-mapping pure fns. Add to
  `tycontrols.lpk`.
- **Create** `source/tyControls.Dialogs.Progress.pas` — the progress form (+ `DoCancel` + `KeyDown`
  override) + `TTyProgressDialog` (+ `FInPump` guard). Add to `tycontrols.lpk`.
- **Modify** `source/tyControls.StrConsts.pas` — the new resourcestrings (+ zh_CN pre-merge).
- **Modify** `designtime/tyControls.Design.pas` — register the 3 components + `uses` the 2 units.
- **Create** `tests/test.dialogs.find.pas`, `tests/test.dialogs.progress.pas`; register in `tests/tytests.lpr`.
- **Modify** `docs/controls/dialogs.md` (§10 modeless) + README (extend the Dialogs bullet); regenerate
  `.pot` + zh_CN `.po` pre-merge.
