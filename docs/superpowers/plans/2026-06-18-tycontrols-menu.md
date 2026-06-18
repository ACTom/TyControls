# TyControls Menu System Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Themed application menu bar + context/popup menus that match the borderless `TTyForm`
chrome and `.tycss` theming, reusing the LCL `TMainMenu`/`TMenuItem`/`TPopupMenu` data model.

**Architecture:** One new unit `source/tyControls.Menu.pas` holds the row model, a themed
renderer control `TTyMenuView`, the popup-window host `TTyMenuPopup` (cascade manager), the
`TTyMenuBar` control, and `TTyPopupMenu = class(TPopupMenu)`. `TTyForm` gains a `MenuBar`
association handling the macOS-vs-Win/Linux split. All three menu surfaces (bar dropdown,
submenu cascade, context menu) render through the SAME `TTyMenuView` + `TTyMenuPopup`.

**Tech Stack:** FPC/LCL custom controls (`TTyCustomControl` base), `TTyPainter`/`TBGRABitmap`
rendering, `.tycss` tokens via `TTyStyleController`, lazy borderless `TForm` popup (the
`TTyComboBox` pattern), `Menus` unit (`TMenuItem`/`ShortCutToText`).

**Conventions (verified, follow exactly):**
- Control anatomy: `source/tyControls.ToggleSwitch.pas` — `class(TTyCustomControl)`;
  `GetStyleTypeKey: string; override`; `CurrentStates: TTyStateSet; override`; headless
  `RenderTo(ACanvas; ARect; APPI)` seam called by `Paint`; `CurrentStyle`/
  `ActiveController.Model.ResolveStyle('TySubKey','',[])`; painter idiom
  `P.BeginPaint(ACanvas,ARect,APPI) … DrawFrame(P,R,S) … P.FillBackground/DrawText … P.EndPaint`;
  published `Align; Anchors; StyleClass; Controller;`.
- Tests: `tests/test.menu.pas` (fpcunit `TTestCase` + `RegisterTest`), add the unit name to the
  `uses` clause of `tests/tytests.lpr`. Headless paint via `TCustomForm.CreateNew(nil)` +
  `RenderTo`. Baseline: **0 failures + ~11–15 env errors (1407 headless focus noise)** — never
  add new failures. Run `lazbuild tests/tytests.lpi` then `./tests/tytests.exe --suite=Name`.
- Theme: edit `themes/light.tycss` (source of truth) + `dark.tycss` + `showcase.tycss`; run
  `powershell -File gen-defaulttheme.ps1` to regenerate `source/tyControls.DefaultTheme.pas`
  (NEVER hand-edit it; `test.defaulttheme` guards byte-identity); add selectors to `GGRID` in
  `tests/test.themes.pas` and re-bootstrap `tests/golden/*.golden.txt`.
- Registration: add controls to `RegisterComponents('TyControls', [...])` in
  `designtime/tyControls.Design.pas:116`, add the unit to `tyControls.lpk` (+ its `uses` list)
  and `tyControls.Design.pas` uses; owner-only/streamed classes need `RegisterClass` (the
  `RegisterClass(TTyTitleBar)` lesson in `tyControls.Form.pas:985`).
- Popup window: mirror `tyControls.ComboBox.pas` (lazy `FPopup:TForm`; `BorderStyle:=bsNone`;
  `ShowInTaskBar:=stNever`; `FormStyle:=fsStayOnTop`; `PopupParent`/`PopupMode:=pmExplicit`;
  `KeyPreview:=True`; `OnDeactivate→CloseUp` with `OnDeactivate` DETACHED around `Hide`;
  `FCloseUpTick:=GetTickCount64` + 200ms reopen guard; `ComputePopupHeight` is a SEPARATE
  headless-testable function; `Application.RemoveAsyncCalls(Self)` in destructor).

**Scope:** v1 = mouse + basic keyboard (Up/Down/Home/End/Enter/Esc/Left/Right) + shortcut
dispatch + separators/check/radio/icons/submenus + theming. v1.1 (NOT in this plan) = `Alt`
activation, mnemonic underlines (`&File`), type-ahead.

---

## File Structure

- Create: `source/tyControls.Menu.pas` — row model + `TTyMenuView` + `TTyMenuPopup` +
  `TTyMenuBar` + `TTyPopupMenu`.
- Modify: `source/tyControls.Form.pas` — `MenuBar` association + cross-platform glue + shortcut hook.
- Modify: `themes/light.tycss`, `themes/dark.tycss`, `themes/showcase.tycss` — menu tokens.
- Regenerate: `source/tyControls.DefaultTheme.pas` (via `gen-defaulttheme.ps1`).
- Modify: `designtime/tyControls.Design.pas`, `tyControls.lpk` — registration.
- Create: `tests/test.menu.pas`; Modify: `tests/tytests.lpr` (uses), `tests/test.themes.pas` (GGRID),
  `tests/golden/*.golden.txt` (re-bootstrap).
- Modify: `examples/demo/mainform.pas` + `.lfm` — a demo `TMainMenu` + `TTyMenuBar` + a `TTyPopupMenu`.

---

## Task 1: Menu row model (headless data→render mapping)

**Files:** Create `source/tyControls.Menu.pas`; Test `tests/test.menu.pas` (+ add to `tytests.lpr` uses).

The foundation: a pure function turning a `TMenuItem` (the bar/popup root) into flat render rows.
Everything else renders from these rows; this is fully headless.

- [ ] **Step 1: Write the failing test** — `tests/test.menu.pas`

```pascal
unit test.menu;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Menus, fpcunit, testregistry, tyControls.Menu;
type
  TMenuModelTest = class(TTestCase)
  published
    procedure TestBuildRowsMapsFields;
  end;
implementation

procedure TMenuModelTest.TestBuildRowsMapsFields;
var mm: TMainMenu; top, sub: TMenuItem; rows: TTyMenuRowArray;
begin
  mm := TMainMenu.Create(nil);
  try
    top := TMenuItem.Create(mm); top.Caption := 'File';        mm.Items.Add(top);
    // children of 'File': an item with a shortcut, a separator, a checked item, a submenu
    sub := TMenuItem.Create(mm); sub.Caption := 'Open'; sub.ShortCut := ShortCut(Ord('O'), [ssCtrl]);
    top.Add(sub);
    top.Add(NewLine);                                          // separator ('-')
    sub := TMenuItem.Create(mm); sub.Caption := 'Word Wrap'; sub.Checked := True; top.Add(sub);
    sub := TMenuItem.Create(mm); sub.Caption := 'Recent';
    sub.Add(NewItem('doc.txt', 0, False, True, nil, 0, ''));   // makes 'Recent' a submenu
    top.Add(sub);
    sub := TMenuItem.Create(mm); sub.Caption := 'Hidden'; sub.Visible := False; top.Add(sub);

    rows := TyBuildMenuRows(top);                              // rows for File's dropdown
    AssertEquals('visible rows', 4, Length(rows));             // Open, sep, Word Wrap, Recent (Hidden skipped)
    AssertEquals('open caption', 'Open', rows[0].Caption);
    AssertTrue ('open has shortcut text', rows[0].ShortcutText <> '');
    AssertTrue ('row1 is separator', rows[1].Kind = mrkSeparator);
    AssertTrue ('word wrap checked', rows[2].Checked);
    AssertTrue ('recent has submenu', rows[3].HasSubmenu);
  finally
    mm.Free;
  end;
end;

initialization
  RegisterTest(TMenuModelTest);
end.
```
Add `test.menu` to the `uses` clause of `tests/tytests.lpr`.

- [ ] **Step 2: Run, verify it fails** — `lazbuild tests/tytests.lpi` fails (unit `tyControls.Menu`
  / `TTyMenuRowArray` not found).

- [ ] **Step 3: Implement** — create `source/tyControls.Menu.pas` interface + `TyBuildMenuRows`:

```pascal
unit tyControls.Menu;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, Graphics, Forms, ExtCtrls, LCLType, Menus,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Controller;

type
  TTyMenuRowKind = (mrkItem, mrkSeparator);
  TTyMenuRow = record
    Kind: TTyMenuRowKind;
    Item: TMenuItem;        // source item (for activation / submenu)
    Caption: string;
    ShortcutText: string;   // ShortCutToText(Item.ShortCut)
    Enabled: Boolean;
    Checked: Boolean;
    RadioItem: Boolean;
    HasSubmenu: Boolean;
    DefaultItem: Boolean;   // render bold
  end;
  TTyMenuRowArray = array of TTyMenuRow;

{ Flatten a root TMenuItem's visible children into render rows. Caption '-' => separator. }
function TyBuildMenuRows(ARoot: TMenuItem): TTyMenuRowArray;

implementation

function TyBuildMenuRows(ARoot: TMenuItem): TTyMenuRowArray;
var i, n: Integer; mi: TMenuItem;
begin
  SetLength(Result, 0);
  if ARoot = nil then Exit;
  n := 0;
  SetLength(Result, ARoot.Count);
  for i := 0 to ARoot.Count - 1 do
  begin
    mi := ARoot.Items[i];
    if not mi.Visible then Continue;
    Result[n].Item := mi;
    if mi.IsLine then
      Result[n].Kind := mrkSeparator
    else
    begin
      Result[n].Kind := mrkItem;
      Result[n].Caption := mi.Caption;
      Result[n].ShortcutText := ShortCutToText(mi.ShortCut);
      Result[n].Enabled := mi.Enabled;
      Result[n].Checked := mi.Checked;
      Result[n].RadioItem := mi.RadioItem;
      Result[n].HasSubmenu := mi.Count > 0;
      Result[n].DefaultItem := mi.Default;
    end;
    Inc(n);
  end;
  SetLength(Result, n);
end;
end.
```

- [ ] **Step 4: Run, verify pass** — `./tests/tytests.exe --suite=TMenuModelTest` → OK.

- [ ] **Step 5: Commit** — `feat(tycontrols): menu row model (TMenuItem -> render rows)`.

---

## Task 2: `TTyMenuView` — themed row renderer + geometry (headless)

**Files:** Modify `source/tyControls.Menu.pas`; `tests/test.menu.pas`.

`TTyMenuView = class(TTyCustomControl)` renders a `TTyMenuRowArray` and exposes pure geometry
seams (`MeasureHeight`, `RowAtY`) that are headless-testable, following the `TToggleSwitch`
`RenderTo` + `TTyComboBox.ComputePopupHeight` patterns.

- [ ] **Step 1: Failing test** — add to `tests/test.menu.pas`:

```pascal
procedure TMenuViewTest.TestMeasureAndHitTest;
var v: TTyMenuViewAccess; mm: TMainMenu; top: TMenuItem;
begin
  mm := TMainMenu.Create(nil);
  try
    top := TMenuItem.Create(mm); top.Caption := 'Edit'; mm.Items.Add(top);
    top.Add(NewItem('Cut',  0, False, True, nil, 0, ''));
    top.Add(NewLine);
    top.Add(NewItem('Copy', 0, False, True, nil, 0, ''));
    v := TTyMenuViewAccess.Create(nil);
    try
      v.SetRows(TyBuildMenuRows(top));
      AssertEquals('3 rows', 3, v.RowCount);
      // height = item rows * itemH + separators * sepH (+ vertical padding); just assert > 0 + monotonic
      AssertTrue('height positive', v.MeasureHeight(96) > 0);
      // hit-test: y inside row 0 maps to 0; the separator row reports -1 (not selectable)
      AssertEquals('row 0 hit', 0, v.RowAtY(v.RowTop(0, 96) + 1, 96));
      AssertEquals('separator not selectable', -1, v.RowAtY(v.RowTop(1, 96) + 1, 96));
    finally v.Free; end;
  finally mm.Free; end;
end;
```
(`TTyMenuViewAccess = class(TTyMenuView)` in the test exposes the protected geometry seams.)

- [ ] **Step 2: Run → fails** (`TTyMenuView` undefined).

- [ ] **Step 3: Implement** `TTyMenuView` in `tyControls.Menu.pas`. Geometry from theme tokens
  (`CurrentStyle.Padding`, font size); rows: item height = text height + padding, separator height
  = a small fixed dev metric. `MeasureHeight`/`RowTop`/`RowAtY` are pure (take APPI). `RenderTo`
  paints background (`TyMenuPopup` style for the popup, `TyMenuBar` for the bar — see Task 5),
  then each row via `TyMenuItem` style: highlight bg when `index = FHighlight`, disabled color
  when `not Enabled`, `DrawText` caption left + shortcut right, a checkmark/▸ arrow drawn from
  `TyMenuItem` tokens, separators as a 1px themed line. Follow `ToggleSwitch.RenderTo` painter
  idiom exactly. `GetStyleTypeKey` returns `'TyMenuView'` (or the owning surface sets the typeKey).

- [ ] **Step 4: Run → pass.**
- [ ] **Step 5: Commit** — `feat(tycontrols): TTyMenuView row geometry + themed rendering`.

---

## Task 3: `TTyMenuView` input — highlight navigation + mouse + activation events

**Files:** Modify `source/tyControls.Menu.pas`; `tests/test.menu.pas`.

- [ ] **Step 1: Failing test** — navigation index logic is pure (no window):

```pascal
procedure TMenuViewTest.TestKeyboardHighlightSkipsSeparatorsAndDisabled;
var v: TTyMenuViewAccess; mm: TMainMenu; top: TMenuItem;
begin
  mm := TMainMenu.Create(nil);
  try
    top := TMenuItem.Create(mm); mm.Items.Add(top);
    top.Add(NewItem('A', 0, False, True,  nil, 0, ''));
    top.Add(NewLine);
    top.Add(NewItem('B', 0, False, False, nil, 0, ''));  // disabled (Enabled=False)
    top.Add(NewItem('C', 0, False, True,  nil, 0, ''));
    v := TTyMenuViewAccess.Create(nil);
    try
      v.SetRows(TyBuildMenuRows(top));
      v.SetHighlight(-1);
      v.MoveHighlight(+1); AssertEquals('first selectable A', 0, v.Highlight);
      v.MoveHighlight(+1); AssertEquals('skip sep+disabled to C', 3, v.Highlight);
      v.MoveHighlight(+1); AssertEquals('wraps to A', 0, v.Highlight);
      v.MoveHighlight(-1); AssertEquals('prev wraps to C', 3, v.Highlight);
    finally v.Free; end;
  finally mm.Free; end;
end;
```

- [ ] **Step 2: Run → fails.**
- [ ] **Step 3: Implement** `MoveHighlight(ADelta)` (skips separators + disabled, wraps),
  `SetHighlight`, `Highlight`. Wire `MouseMove` → `RowAtY` → highlight + `Invalidate`; `Click`/
  `MouseDown` → if highlighted row enabled: fire `OnActivateRow(row)` (leaf) or `OnOpenSubmenu(row)`
  (HasSubmenu); `KeyDown` Up/Down→`MoveHighlight`, Home/End→first/last selectable, Enter/Space→
  activate highlighted, Right→`OnOpenSubmenu`, Left/Esc→`OnCloseRequested`. Events are
  `property OnActivateRow / OnOpenSubmenu / OnCloseRequested / OnNavigateAdjacentBar`.
- [ ] **Step 4: Run → pass.**
- [ ] **Step 5: Commit** — `feat(tycontrols): TTyMenuView keyboard/mouse navigation + activation events`.

---

## Task 4: `TTyMenuPopup` — borderless TForm host + cascade

**Files:** Modify `source/tyControls.Menu.pas`; `tests/test.menu.pas`.

`TTyMenuPopup` wraps a `TTyMenuView` in a lazy borderless `TForm`, shows it at an anchor, closes
on deactivate (with the 200ms guard), and cascades submenus as child `TTyMenuPopup`s. Mirrors
`TTyComboBox` popup management. The window itself needs a GUI loop, so tests cover the
headless seams: `ComputeBounds` (anchor → screen rect with screen-edge flipping) and that
activating a leaf calls the item's `OnClick`.

- [ ] **Step 1: Failing test**:

```pascal
procedure TMenuPopupTest.TestActivateLeafFiresItemOnClick;
var pop: TTyMenuPopup; mm: TMainMenu; top, leaf: TMenuItem; fired: Boolean;
begin
  fired := False;
  mm := TMainMenu.Create(nil);
  try
    top := TMenuItem.Create(mm); mm.Items.Add(top);
    leaf := TMenuItem.Create(mm); leaf.Caption := 'Go';
    leaf.OnClick := TNotifyEventStub(@fired);   // helper sets fired := True
    top.Add(leaf);
    pop := TTyMenuPopup.Create(nil);
    try
      pop.SetRoot(top);
      pop.ActivateRowForTest(0);     // test seam: activate row 0 as if clicked
      AssertTrue('leaf OnClick fired', fired);
    finally pop.Free; end;
  finally mm.Free; end;
end;
```
(Use a tiny stub object whose method sets a boolean, or assert via a counter field — keep it a
real `TNotifyEvent`.)

- [ ] **Step 2: Run → fails.**
- [ ] **Step 3: Implement** `TTyMenuPopup`:
  - Fields `FForm: TForm; FView: TTyMenuView; FChild: TTyMenuPopup; FCloseTick: QWord;`.
  - `SetRoot(AItem)` → `FView.SetRows(TyBuildMenuRows(AItem))`.
  - `Popup(AAnchor: TRect; AController)` → lazy-create `FForm` (bsNone/stNever/fsStayOnTop/
    PopupParent/pmExplicit/KeyPreview), parent `FView` `alClient`, set `FView.Controller`,
    `ComputeBounds(AAnchor, FView.MeasureHeight(ppi))` (flip above/left near screen edges),
    `FForm.Show`.
  - `FView.OnActivateRow` → call `Row.Item.Click`, then `CloseAll`. `OnOpenSubmenu` → create
    `FChild`, `FChild.Popup(submenu anchor at the row, to the right)`. `OnCloseRequested` →
    close this level (free `FChild` first). `FForm.OnDeactivate` → `CloseAll` with the detach-
    around-Hide + `FCloseTick := GetTickCount64` guard (ComboBox pattern). Destructor:
    `Application.RemoveAsyncCalls(Self)` + free child + form.
  - `ActivateRowForTest(i)` test seam calls the same activation path as a click.
- [ ] **Step 4: Run → pass.**
- [ ] **Step 5: Commit** — `feat(tycontrols): TTyMenuPopup borderless host + submenu cascade`.

---

## Task 5: `TTyMenuBar` — associate TMainMenu, render top bar, open dropdowns

**Files:** Modify `source/tyControls.Menu.pas`; `tests/test.menu.pas`.

- [ ] **Step 1: Failing test** (top-cell geometry + which top item a click opens — headless):

```pascal
procedure TMenuBarTest.TestTopCellsAndHitTest;
var bar: TTyMenuBarAccess; mm: TMainMenu;
begin
  mm := TMainMenu.Create(nil);
  try
    mm.Items.Add(NewSubMenu('File', 0, NewItem('New',0,False,True,nil,0,''), nil));
    mm.Items.Add(NewSubMenu('Edit', 0, NewItem('Cut',0,False,True,nil,0,''), nil));
    bar := TTyMenuBarAccess.Create(nil);
    try
      bar.Menu := mm;
      AssertEquals('2 top cells', 2, bar.TopCount);
      AssertEquals('cell0 caption', 'File', bar.TopCaption(0));
      AssertEquals('hit inside cell1 -> 1', 1, bar.TopAtX(bar.TopLeft(1, 96) + 1, 96));
    finally bar.Free; end;
  finally mm.Free; end;
end;
```

- [ ] **Step 2: Run → fails.**
- [ ] **Step 3: Implement** `TTyMenuBar = class(TTyCustomControl)`:
  - `property Menu: TMainMenu` (+ `FreeNotification`/`Notification` to nil it on free);
    `GetStyleTypeKey='TyMenuBar'`. Render visible top-level `Menu.Items` as horizontal cells
    (`TyMenuBar` bg + `TyMenuItem`-style cells with hover/active states). `TopCount/TopCaption/
    TopLeft/TopAtX` pure geometry seams.
  - Click / Down on a top cell → open a `TTyMenuPopup.Popup(cellRect)` rooted at that top item;
    track the open index for the active state; Left/Right move to the adjacent top while open
    (via `TTyMenuView.OnNavigateAdjacentBar`). Published `Align; Anchors; StyleClass; Controller;`.
- [ ] **Step 4: Run → pass.**
- [ ] **Step 5: Commit** — `feat(tycontrols): TTyMenuBar (renders an associated TMainMenu)`.

---

## Task 6: `TTyForm.MenuBar` association + cross-platform glue + shortcut dispatch

**Files:** Modify `source/tyControls.Form.pas`; `tests/test.menu.pas` (or `tests/test.form.pas`).

- [ ] **Step 1: Failing test** — the non-mac shortcut path is testable headlessly via `IsShortCut`:

```pascal
procedure TMenuFormTest.TestPrimaryMenuBarDispatchesShortcut;
var frm: TTyFormAccess; bar: TTyMenuBar; mm: TMainMenu; it: TMenuItem;
    fired: Boolean; msg: TLMKey;
begin
  fired := False;
  frm := TTyFormAccess.CreateNew(nil);
  try
    mm := TMainMenu.Create(frm);
    it := TMenuItem.Create(mm); it.Caption := 'Save'; it.ShortCut := ShortCut(Ord('S'), [ssCtrl]);
    it.OnClick := ...set fired; mm.Items.Add(it);
    bar := TTyMenuBar.Create(frm); bar.Parent := frm; bar.Menu := mm;
    frm.MenuBar := bar;                          // designate primary
    FillChar(msg, SizeOf(msg), 0);
    msg.CharCode := Ord('S');                    // Ctrl+S (shift state via the key message)
    AssertTrue('form routes Ctrl+S to the menu', frm.TestIsShortCut(Ord('S'), [ssCtrl]));
    AssertTrue('item fired', fired);
  finally frm.Free; end;
end;
```
(`TTyFormAccess.TestIsShortCut` builds a `TLMKey` and calls the same path the override uses, then
returns whether the menu consumed it.)

- [ ] **Step 2: Run → fails.**
- [ ] **Step 3: Implement** in `tyControls.Form.pas`:
  - `property MenuBar: TTyMenuBar read FMenuBar write SetMenuBar;` (+ `FreeNotification`).
  - `SetMenuBar`: `{$IFDEF DARWIN}` set `Menu := AValue.Menu` (the inherited `TForm.Menu` →
    global bar) and `AValue.Visible := False` (configurable); `{$ELSE}` leave `Menu` nil and keep
    `AValue` visible — it owns shortcut dispatch.
  - Override `function IsShortCut(var Message: TLMKey): Boolean; override;` — `{$IFNDEF DARWIN}`
    if `FMenuBar <> nil` and `FMenuBar.Menu <> nil` and `FMenuBar.Menu.IsShortCut(Message)` then
    `Exit(True)`; `{$ENDIF}` then `Result := inherited`.
  - Add `tyControls.Menu` to the uses; `RegisterClass(TTyMenuBar)` in the unit initialization (the
    associated-component streaming lesson).
- [ ] **Step 4: Run → pass.**
- [ ] **Step 5: Commit** — `feat(tycontrols): TTyForm.MenuBar association + cross-platform Form.Menu + shortcut dispatch`.

---

## Task 7: `TTyPopupMenu` — themed context menu over the LCL model

**Files:** Modify `source/tyControls.Menu.pas`; `tests/test.menu.pas`.

- [ ] **Step 0: Verify the override seam** — read `C:\lazarus\lcl\menus.pp`: confirm whether
  `TPopupMenu.PopUp(X, Y)` (or `DoPopup` / `Popup`) is `virtual`. Use the virtual one; if none is
  virtual, override the host control's `DoContextPopup` instead. Record the finding in the commit.

- [ ] **Step 1: Failing test** — popping shows our renderer + a leaf click fires `OnClick`:

```pascal
procedure TPopupMenuTest.TestPopupRoutesToThemedRendererAndFires;
var pm: TTyPopupMenu; it: TMenuItem; fired: Boolean;
begin
  fired := False;
  pm := TTyPopupMenu.Create(nil);
  try
    it := TMenuItem.Create(pm); it.Caption := 'Paste'; it.OnClick := ...set fired;
    pm.Items.Add(it);
    pm.ActivateRowForTest(0);     // test seam mirrors choosing the row in the themed popup
    AssertTrue('paste fired', fired);
  finally pm.Free; end;
end;
```

- [ ] **Step 2: Run → fails.**
- [ ] **Step 3: Implement** `TTyPopupMenu = class(TPopupMenu)`: hold a `TTyMenuPopup`; override the
  verified seam so `PopUp(X,Y)` calls `FRenderer.SetRoot(Items); FRenderer.Popup(Rect(X,Y,X,Y),
  Controller)` instead of the native menu. Expose `Controller` (so it themes) + `ActivateRowForTest`.
  Assigning a `TTyPopupMenu` to any control's `PopupMenu` makes right-click show it (LCL
  `DoContextPopup` calls `PopupMenu.PopUp`).
- [ ] **Step 4: Run → pass.**
- [ ] **Step 5: Commit** — `feat(tycontrols): TTyPopupMenu (themed context menu over TPopupMenu)`.

---

## Task 8: Theme tokens + golden grid

**Files:** Modify `themes/light.tycss`, `dark.tycss`, `showcase.tycss`; regenerate
`source/tyControls.DefaultTheme.pas`; modify `tests/test.themes.pas`; re-bootstrap `tests/golden/*`.

- [ ] **Step 1:** Add `TyMenuBar` / `TyMenuItem` / `TyMenuView` / `TyMenuPopup` blocks to
  `light.tycss` using existing ALIAS tokens (verify names against the file), e.g.:

```tycss
TyMenuBar  { background: var(--surface-chrome); color: var(--on-surface); padding: 2px; }
TyMenuPopup{ background: var(--surface-chrome); border-color: var(--border);
             border-width: var(--input-border-width); border-radius: var(--radius); padding: 2px; }
TyMenuItem        { background: alpha(#FFFFFF,0); color: var(--on-surface); padding: 4px; }
TyMenuItem:hover  { background: var(--surface-hover); }
TyMenuItem:active { background: var(--accent); color: var(--on-accent); }
TyMenuItem:disabled { color: var(--muted); }
```
  Mirror into `dark.tycss` (same selectors, dark token values) and `showcase.tycss`.

- [ ] **Step 2:** `powershell -File gen-defaulttheme.ps1` (regenerate `DefaultTheme.pas`).
- [ ] **Step 3:** Add `'TyMenuBar|'`, `'TyMenuItem|'`, `'TyMenuPopup|'` to `GGRID` in
  `tests/test.themes.pas`; delete the three `tests/golden/*.golden.txt` (or run with the bootstrap
  path) and re-run so they regenerate; eyeball the new rows, then keep the regenerated goldens.
- [ ] **Step 4:** `lazbuild tests/tytests.lpi` + `./tests/tytests.exe --all` → 0 failures; the
  `test.defaulttheme` sync test + all goldens green.
- [ ] **Step 5: Commit** — `feat(tycontrols): menu theme tokens (light/dark/showcase) + golden`.

---

## Task 9: Package + designer registration

**Files:** Modify `designtime/tyControls.Design.pas`, `tyControls.lpk` (+ its file/uses list).

- [ ] **Step 1:** Add `tyControls.Menu` to `tyControls.lpk` `<Files>` and to the runtime uses where
  controls are aggregated. Add `tyControls.Menu` to `tyControls.Design.pas` uses.
- [ ] **Step 2:** Add `TTyMenuBar, TTyPopupMenu` to the `RegisterComponents('TyControls', [...])`
  array (`tyControls.Design.pas:116`). `TTyPopupMenu` is non-visual (palette like `TPopupMenu`);
  `TTyMenuBar` is visual.
- [ ] **Step 3:** `lazbuild tyControls.lpk` and `lazbuild tycontrols_dt.lpk` → both compile clean.
- [ ] **Step 4: Commit** — `feat(tycontrols): register TTyMenuBar + TTyPopupMenu (palette + streaming)`.

---

## Task 10: Demo integration (visual verification)

**Files:** Modify `examples/demo/mainform.pas` + `.lfm`.

- [ ] **Step 1:** Drop a `TMainMenu` (with File/Edit/View + a separator, a checked item, a submenu,
  shortcuts) and a `TTyMenuBar` (`Align=alTop`, `Menu=` the TMainMenu, `Controller=Controller`)
  below the title bar; set `DemoMainForm.MenuBar := TyMenuBar1`. Add a `TTyPopupMenu` and assign it
  to one control's `PopupMenu`. Wire a couple of `OnClick`s (e.g. toggle a label).
- [ ] **Step 2:** `lazbuild examples/demo/demo.lpi` → links clean.
- [ ] **Step 3: Commit** — `feat(examples): demo menu bar + context menu`.

- [ ] **Manual (real GUI, user):** menu bar opens dropdowns, submenu cascades, checkmarks/icons/
  separators render themed, keyboard nav + `Ctrl+S` shortcut fire, right-click shows the themed
  context menu, theme switch (Light/Dark/Green) restyles the menus, and (real mac) the menu appears
  at the top of the screen instead of in-window.

---

## Final review

After all tasks: dispatch a code-review pass over the full diff (spec compliance + quality),
run `./tests/tytests.exe --all` (0 failures, goldens green), confirm the demo links, then use
superpowers:finishing-a-development-branch.

## Self-review notes (author)

- **Spec coverage:** §2.1 `TTyMenuPopup`→T4; §2.2 `TTyMenuBar`→T5; §2.3 `TTyPopupMenu`→T7;
  §2.4 `TTyForm.MenuBar`+cross-platform→T6; §3 data model→T1; §4 shortcuts→T6; §5 tokens→T8;
  §7 testing→per-task headless seams + T8 golden + T10 manual. `TTyMenuView` (the shared renderer
  inside the popup) is T2/T3 — an implementation split of §2.1 not named in the spec; noted here.
- **Deferred-by-design (v1.1, NOT here):** `Alt` activation, mnemonic underlines, type-ahead (§6).
- **Genuinely uncertain (flagged, not guessed):** the `TPopupMenu` virtual override seam (T7 Step 0
  verifies it in `menus.pp`); macOS `Form.Menu`/global-bar behavior (T10 manual on real mac).
- **Type consistency:** `TyBuildMenuRows`/`TTyMenuRowArray`/`TTyMenuRow` (T1) consumed verbatim by
  `TTyMenuView.SetRows` (T2) and `TTyMenuPopup.SetRoot` (T4); `MeasureHeight(APPI)`/`RowAtY` seam
  names stable across T2/T4.
