# Input-Family Dialogs (Dialogs Program · S2) — Design

**Goal:** Five custom-drawn, themed input dialogs built on the S1 `TTyDialog` foundation —
`TyInputDialog`, `TyPasswordDialog`, `TyTextDialog`, `TySelectValueDialog` (all in
`tyControls.Dialogs.pas`), and `TySelectPathDialog` (a lazy directory-tree folder picker in its own
unit `tyControls.Dialogs.SelectPath.pas`). Each ships `Ty`-prefixed global functions (the primary
API, LCL-parity) plus a non-visual `TComponent`.

**Architecture:** Extend the S1 pattern verbatim — `TTyDialog` base (borderless close-only centered
modal, content area + bottom button bar via `AddButton`), a build/show-separated construct-only
builder per dialog (headless-testable), a `Ty`-prefixed global-function API, and a thin non-visual
component. S2 adds ONE base capability: **opt-in resizable dialogs** with a content-reflow hook (for
the multi-line Text dialog and the directory-tree SelectPath dialog). The four text dialogs reuse
existing controls (`TTyEdit`, `TTyMemo`, `TTyListBox`); SelectPath reuses `TTyTreeView`'s
VirtualTree-style lazy loading (`OnInitChildren` / `nsHasChildren`).

**Tech stack:** Lazarus/FPC, LCL (`TModalResult`, `TStrings`, `SysUtils` filesystem), BGRABitmap;
builds on `tyControls.Dialogs` (S1), `tyControls.Edit`, `tyControls.Memo`, `tyControls.ListBox`,
`tyControls.TreeView`, `tyControls.TyLabel`, `tyControls.StrConsts`. Headless fpcunit; SelectPath's
filesystem logic tested against a real temp directory.

**Roadmap context:** S2 of the P2–P4 dialogs sub-program (S1 foundation DONE + merged to main).
S3 (Color/Font pickers) and S4 (Find/Replace/Progress) follow in later specs. Naming: `Ty`-prefixed
globals mirroring LCL's `InputQuery`/`InputBox`/`PasswordBox`/`SelectDirectory` (no shadowing).

---

## Current state (from S1 + code map)
- `tyControls.Dialogs.pas` (S1, on main) provides `TTyDialog = class(TTyForm)`: `AddButton` (buttons
  carry their own `TTyButton.ModalResult`), `LayoutButtonBar`, `ContentRect` (client minus titlebar
  top and button-bar bottom), `AutoSizeToContent(w,h)` (one-shot client sizing + re-center),
  `CancelDialog`, `KeyDown` (Enter→default / Esc→cancel), and the message-dialog machinery. The
  builder+globals+component pattern (`TyBuildMessageDialog` → `RunDialogModal` → globals; `TTyMessage`
  component) is the template every S2 dialog copies.
- `TTyDialog` is **non-resizable** (`CreateNew` sets `Resizable := False`). `AutoSizeToContent` sizes
  once; there is no resize-reflow. S2 adds this.
- `TTyEdit` (`tyControls.Edit.pas`) has a published `PasswordChar: string` (masks display + width
  measurement) — the password dialog reuses it directly, no new masking code.
- `TTyMemo` (`tyControls.Memo.pas`) is the multi-line editor (per-line content cache; vertical scroll).
- `TTyListBox` (`tyControls.ListBox.pas`) — single-selection item list.
- `TTyTreeView` (`tyControls.TreeView.pas`) exposes VirtualTree-style lazy hooks: `OnInitChildren`
  (materialize a node's children), `OnInitNode`/`ivsHasChildren` (declare a node expandable without
  materializing), `nsHasChildren` state, per-node data. SelectPath uses these to populate directories
  on demand.
- `tyControls.StrConsts.pas` holds runtime resourcestrings (`rsMsgBtnOK`/`rsMsgBtnCancel` from S1 are
  reused for the dialog buttons). Design-time registration + New-item descriptors live in
  `designtime/tyControls.Design.pas` ("TyControls Dialogs" palette group from S1).

## Design

### A. Resizable-dialog extension to `TTyDialog` (`tyControls.Dialogs.pas`)
S1's `TTyDialog` is fixed-size. Add an opt-in resize path so Text and SelectPath can grow:
- A protected virtual `procedure LayoutContent; virtual;` — the single place a dialog positions its
  content widget(s) within `ContentRect`. The default implementation does nothing (fixed-size dialogs
  place widgets once at build time, as today). Resizable dialogs override it to stretch their primary
  widget (memo / tree) to fill `ContentRect`.
- Override `Resize` (LCL `TWinControl.Resize`) in `TTyDialog` to call `LayoutButtonBar` + `LayoutContent`
  so a resizable dialog reflows on every size change. (For fixed-size dialogs `LayoutContent` is a
  no-op and `LayoutButtonBar` is idempotent, so this is safe for all dialogs.)
- `Constraints.MinWidth`/`MinHeight`: resizable dialogs set sensible minimums in their builder so the
  content can't be shrunk to nothing.
- Resizable dialogs set `Resizable := True` in their builder (after `inherited CreateNew`) but KEEP
  `BorderIcons = [biSystemMenu]` (close-only). P1 gates edge-resize on `Resizable` and the maximize
  button on `biMaximize` **and** `Resizable` independently — so this yields drag-edge-resize with NO
  min/max buttons (maximizing a small input dialog is unusual and unwanted). Fixed dialogs stay
  `Resizable := False`. Enter/Esc/close semantics are unchanged.

This is the only base change; the four fixed-size dialogs use `TTyDialog` exactly as S1 left it.

### B. The four text dialogs (`tyControls.Dialogs.pas`)
Each follows the S1 seam: `TyBuild…Dialog(...) : TTyDialog` (construct-only) → `RunDialogModal` →
globals; plus a `TTyXxxDialog = class(TComponent)` with `Execute`. All place a wrapped prompt
`TTyLabel` above their input widget in the content area, with `[OK][Cancel]` on the bar (OK = default,
Cancel = the Esc/X dismiss → `mrCancel`, per S1). `Execute`/globals return the entered value only when
OK (mrOk); Cancel/Esc/X → the "unchanged"/empty result.

1. **`TyInputDialog`** — content = prompt label + a single-line `TTyEdit` seeded with the default.
   - `function TyInputQuery(const ACaption, APrompt: string; var AValue: string): Boolean;`
     (mirror LCL `InputQuery`; returns True + writes `AValue` on OK, False on cancel).
   - `function TyInputBox(const ACaption, APrompt, ADefault: string): string;`
     (mirror LCL `InputBox`; returns the entered text on OK, `ADefault` on cancel).
   - `TTyInputDialog`: published `Caption`, `Prompt`, `Value`; `function Execute: Boolean` (updates
     `Value` on OK).

2. **`TyPasswordDialog`** — content = prompt label + a `TTyEdit` with `PasswordChar` set (default the
   bullet `'●'`; the component exposes `PasswordChar` so a caller can change it).
   - `function TyPasswordBox(const ACaption, APrompt: string): string;` (mirror LCL `PasswordBox`;
     returns the password on OK, `''` on cancel).
   - `function TyPasswordQuery(const ACaption, APrompt: string; var AValue: string): Boolean;`
   - `TTyPasswordDialog`: published `Caption`, `Prompt`, `Value`, `PasswordChar`; `Execute: Boolean`.

3. **`TyTextDialog`** (RESIZABLE) — content = prompt label + a multi-line `TTyMemo` filling the rest of
   the content area; overrides `LayoutContent` to stretch the memo to `ContentRect` on resize. Larger
   default size (e.g. 420×280); `MinWidth/MinHeight` set.
   - `function TyTextQuery(const ACaption, APrompt: string; var AValue: string): Boolean;` (multi-line;
     `AValue` may contain line breaks).
   - `TTyTextDialog`: published `Caption`, `Prompt`, `Value` (`TStrings`? — no, keep `string` with
     embedded `LineEnding`s for a simple API; the memo's `Lines.Text` round-trips it); `Execute: Boolean`.

4. **`TySelectValueDialog`** — content = prompt label + a single-select `TTyListBox` populated from a
   caller-supplied item list; double-click a row = OK. Returns the chosen index (value = items[index]).
   - `function TySelectValue(const ACaption, APrompt: string; AItems: TStrings; var AIndex: Integer): Boolean;`
     (`AIndex` in = initial selection, out = chosen; True on OK). OK is disabled semantics are YAGNI —
     if nothing is selected, OK returns the current `AIndex` (may be -1); callers check `>= 0`.
   - `TTySelectValueDialog`: published `Caption`, `Prompt`, `Items: TStrings`, `ItemIndex: Integer`;
     read-only `SelectedText: string`; `function Execute: Boolean`.

### C. `TySelectPathDialog` — folder picker (`tyControls.Dialogs.SelectPath.pas`, RESIZABLE)
A directory-tree folder picker in its own unit (the one "complex" S2 dialog).
- **Content:** a `TTyTreeView` (dirs only) filling the content area (stretched via `LayoutContent`),
  plus a **"New Folder"** button on the button bar (left of `[OK][Cancel]`). Resizable; larger default
  size (e.g. 380×440); `MinWidth/MinHeight` set.
- **Lazy population:** each tree node carries its absolute directory path (node data / a parallel map
  keyed by node). `OnInitNode` sets `ivsHasChildren` when the directory contains at least one subdir
  (a cheap "any subdir?" probe). `OnInitChildren` enumerates immediate subdirectories
  (`FindFirst`/`FindNext`, `faDirectory`, skipping `.`/`..` and — by default — hidden/system entries)
  sorted case-insensitively, adding a child node per subdir. This is the VirtualTree lazy pattern the
  tree was built for; nothing is read until a node expands.
- **Root:** `ARoot` parameter — if non-empty, the tree is rooted at that single directory; if empty,
  the roots are the available drive letters (Windows) / `'/'` (POSIX). (Drive enumeration is a small
  platform-gated helper.)
- **New Folder:** creates a subdirectory under the currently-selected node — prompt for the name via
  `TyInputQuery` (reuse!), `CreateDir(parentPath + name)`, on success re-init the parent node's
  children (so the new folder appears) and select it. Errors (invalid name / exists / permission) →
  a `TyMessageDlg(..., mtError, [mbOK])`.
- **Result:** the selected node's directory path.
- **Global:** `function TySelectDirectory(const ACaption: string; const ARoot: string; var ADir: string): Boolean;`
  (mirror LCL `SelectDirectory`; `ADir` in = initial selection to expand-and-highlight, out = chosen;
  True on OK). `TTySelectPathDialog`: published `Caption`, `Root`, `Directory`; `Execute: Boolean`.
- **Pure/testable seam:** the filesystem-facing logic is factored into small testable helpers —
  `TySubdirectories(const APath: string): TStringArray` (sorted immediate subdirs; testable against a
  scratch temp dir), `TyPathHasSubdir(const APath: string): Boolean`, and `TyDriveRoots: TStringArray`
  (platform-gated). The tree wiring calls these; tests exercise the helpers directly + the builder
  (construct-only) without a real modal.

### D. IDE integration (`designtime/tyControls.Design.pas`)
- Add the five components to the existing S1 palette group:
  `RegisterComponents('TyControls Dialogs', [TTyInputDialog, TTyPasswordDialog, TTyTextDialog, TTySelectValueDialog, TTySelectPathDialog]);`
  (`TTySelectPathDialog` comes from the new unit; add `tyControls.Dialogs.SelectPath` to the Design.pas
  `uses` and the dt package).
- No new New-item descriptors (S1's "TyControls Dialog" base covers custom dialogs). Palette icons for
  the five components are deferred (default glyph), consistent with S1's `TTyMessage`.

### E. Theming
All five reuse `TyForm` + `TyButton` tokens and the existing input controls' own tokens
(`TTyEdit`/`TTyMemo`/`TTyListBox`/`TTyTreeView` are already themed). No new required token. The prompt
label uses the standard label token. Resizable dialogs paint no differently — the chrome/maximize
button is P1's existing themed caption button.

## Error handling
- Cancel / Esc / title-bar X → the "unchanged" result: `TyInputQuery`/`TyPasswordQuery`/`TyTextQuery`/
  `TySelectValue`/`TySelectDirectory` return **False** (and leave the `var` argument untouched);
  `TyInputBox` returns `ADefault`, `TyPasswordBox` returns `''`.
- `TySelectValue` with an empty item list → an enabled dialog with an empty list; OK returns index -1
  (caller checks). No crash.
- SelectPath: unreadable/permission-denied directory on expand → that node simply shows no children
  (the `FindFirst` helper swallows the error and returns empty); New Folder failure → `mtError` message.
- SelectPath with a non-existent `ARoot` → falls back to drive/root enumeration (empty-root behavior).
- No main form (console/early) → `poScreenCenter` (inherited S1 behavior).

## Testing (headless fpcunit)
`tests/test.dialogs.pas` (extend) + `tests/test.dialogs.selectpath.pas` (new, registered in the runner):
1. **Resizable base:** build a resizable dialog, change its client size, assert `LayoutContent`
   stretched the content widget to `ContentRect` and the button bar stayed `alBottom`. (Construct-only;
   no Show.)
2. **Each text dialog builder (construct-only):** `TyBuildInputDialog`/…/`TyBuildSelectValueDialog`
   returns a `TTyDialog` whose content has the expected widget (edit/memo/listbox) seeded with the
   default/items, an `[OK]` default + `[Cancel]` cancel bar, prompt label present — asserted without
   `ShowModal`. Password dialog: assert the edit's `PasswordChar` is set. SelectValue: assert the
   listbox items match and `ItemIndex` seeds the selection.
3. **Value round-trip (logic, no modal):** simulate OK by setting the widget's value then calling the
   builder's result-extraction helper; assert the returned string/index matches. Simulate cancel →
   the unchanged/default result.
4. **SelectPath filesystem helpers (against a scratch temp dir):** create a temp tree
   (`dirA/`, `dirA/sub1`, `dirA/sub2`, `dirA/file.txt`); assert `TySubdirectories(dirA)` = `[sub1, sub2]`
   (sorted, file excluded), `TyPathHasSubdir(dirA)` = True, `TyPathHasSubdir(dirA/sub1)` = False. Assert
   the New-Folder path logic (`CreateDir` under a node + re-enumerate shows it).
5. **SelectPath builder (construct-only):** build with a temp root; assert the tree exists, is rooted
   correctly, and the "New Folder" + `[OK][Cancel]` buttons are present.
- **Do NOT** call `ShowModal` or `SetDesigning` (S1 lessons: no blocking; windowed children + csDesigning
  → win32 1407 headless). All tests are construct-only / pure / filesystem-against-temp.
- **Baseline** after S1 merge: 1564 run / 0 failures / 11 errors — keep failures 0, errors 11.

## Non-goals (S2)
- S3/S4 dialogs (Color/Font pickers, Find/Replace, Progress).
- Input validation callbacks / masks beyond password char (YAGNI; add later if asked).
- SelectPath: showing files, multi-select, drag-drop, network/UNC browsing, file filters — dirs-only,
  single-select, "New Folder" is the only mutation.
- Custom palette icons for the five components (default glyph; a `gen-icons` pass is a later chore).
- A generic "form builder" or native-dialog wrapping.

## Files
- **Modify** `source/tyControls.Dialogs.pas` — the `LayoutContent`/`Resize` base extension; the four
  text dialogs (builders + globals + `TTyInputDialog`/`TTyPasswordDialog`/`TTyTextDialog`/
  `TTySelectValueDialog`).
- **Create** `source/tyControls.Dialogs.SelectPath.pas` — `TySelectDirectory` + `TTySelectPathDialog`
  + the filesystem helpers (`TySubdirectories`/`TyPathHasSubdir`/`TyDriveRoots`). Add to `tycontrols.lpk`.
- **Modify** `source/tyControls.StrConsts.pas` — new resourcestrings for built-in text ("New Folder"
  button + its input prompt/caption, and any default dialog captions). zh_CN catalog updated pre-merge.
- **Modify** `designtime/tyControls.Design.pas` — register the five components in "TyControls Dialogs";
  add the SelectPath unit to `uses`. Add the unit to `tycontrols_dt.lpk` if needed.
- **Modify** `tests/test.dialogs.pas`; **Create** `tests/test.dialogs.selectpath.pas` — the tests above;
  register in `tests/tytests.lpr`.
- **Modify** `docs/controls/dialogs.md` (+ a SelectPath section) and README (mention the input family)
  pre-merge; regenerate `.pot` + zh_CN `.po`.
