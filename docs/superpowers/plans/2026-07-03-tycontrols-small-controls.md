# Three Small Controls Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship tri-state `TTyCheckBox`, editable (`csDropDown`+autocomplete) `TTyComboBox`, and a new `TTyTabSet` pure tab strip — all extending existing code/engines, backward-compatible.

**Architecture:** ① and ② extend the current controls in place (opt-in, default branch unchanged). ③ is a thin `TTyCustomTabStrip` subclass. One branch `feat/small-controls` (already created; spec committed). TDD, bite-sized, per-control task groups.

**Tech Stack:** Lazarus/FPC, `TTyPainter` glyphs, LCL `StdCtrls.TCheckBoxState`, SP1 `tyControls.TabStrip` engine, theme `.tycss`, headless RenderTo + fpcunit.

**Spec:** `docs/superpowers/specs/2026-07-03-tycontrols-small-controls-design.md` (adversarially verified).

**Baseline (run first):** `lazbuild tycontrols.lpk >/dev/null 2>&1 && lazbuild tests/tytests.lpi >/dev/null 2>&1 && ./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)"` → **1622 run / 0 failures / 11 errors**. Keep failures 0, errors 11; record the exact run count.

**Standing constraints:** Reply to the user in Chinese. Do NOT push (user drives pushes). Do NOT touch `examples/demo/*` except Task 7 (and there, Edit precisely — preserve the user's uncommitted `.lfm` edits, never rewrite). Commit trailer `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

## File Structure
- **`source/tyControls.Painter.pas`** (modify) — add `tgCheckIndeterminate` glyph (enum + DrawGlyph case).
- **`source/tyControls.CheckBox.pas`** (modify) — `FState`-based tri-state.
- **`source/tyControls.ComboBox.pas`** (modify) — `Style`/embedded `TTyEdit`/`FVisibleItems`/prefix filter/re-entrancy guard + the pure `TyFilterItemsByPrefix`.
- **`source/tyControls.TabSet.pas`** (create) — `TTyTabSet`. Add to `tycontrols.lpk`.
- **`designtime/tyControls.Design.pas`** (modify) — register `TTyTabSet` on `'TyControls'`.
- **`tools/genicons/genicons.lpr`**, **`scripts/gen-icons.ps1`**, **`tests/test.paletteicons.pas`** (modify) — TabSet icon lockstep + regen `.lrs`.
- **Tests** (create/extend): `tests/test.painter.pas` auto-covers the glyph; `tests/test.checkbox.pas`, `tests/test.combobox.pas`, `tests/test.tabset.pas` (create if absent); register in `tests/tytests.lpr`.
- **`examples/demo/mainform.lfm`/`.pas`** (Task 7) — showcase the three.

---

## Task 1: Painter `tgCheckIndeterminate` glyph

**Files:** Modify `source/tyControls.Painter.pas:14` (enum) + `:431-485` (DrawGlyph case). Test: `tests/test.painter.pas` (existing `TestDrawGlyphAllKinds` auto-covers it).

- [ ] **Step 1: Add the enum member.** In `source/tyControls.Painter.pas` change the `TTyGlyphKind` declaration (line 14) to insert `tgCheckIndeterminate` right after `tgCheck`:
```pascal
  TTyGlyphKind = (tgClose, tgMinimize, tgMaximize, tgRestore, tgCheck, tgCheckIndeterminate,
    tgRadioDot, tgChevronDown, tgChevronRight, tgArrowUp, tgArrowDown, tgArrowLeft, tgArrowRight);
```

- [ ] **Step 2: Run the smoke test to confirm it now FAILS.** The exhaustive `case` (`:431-485`) has no `else`, so the new member draws nothing.
Run: `lazbuild tests/tytests.lpi >/dev/null 2>&1 && ./tests/tytests.exe --suite=TPainterTest -a --format=plain 2>&1 | grep -iE "glyph|failures"`
Expected: FAIL — `glyph 5 painted` (tgCheckIndeterminate is Ord 5) with hits=0.

- [ ] **Step 3: Add the DrawGlyph case.** In the `case AGlyph of` block (after the `tgCheck:` case at `:448-450`), add:
```pascal
    tgCheckIndeterminate:
      // centered filled square (Windows indeterminate look); m = min(w,h) from the setup vars
      FBmp.FillRectAntialias(cx - m * 0.28, cy - m * 0.28, cx + m * 0.28, cy + m * 0.28, px);
```

- [ ] **Step 4: Run the smoke test — passes.**
Run: `lazbuild tests/tytests.lpi >/dev/null 2>&1 && ./tests/tytests.exe --suite=TPainterTest -a --format=plain 2>&1 | grep -iE "failures|errors"`
Expected: `Number of failures: 0`.

- [ ] **Step 5: Commit.**
```bash
git add source/tyControls.Painter.pas
git commit -m "feat(painter): tgCheckIndeterminate glyph (centered filled square)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: tri-state `TTyCheckBox`

**Files:** Modify `source/tyControls.CheckBox.pas` (class decl `:8-35`, `CurrentStates:103-112`, `SetChecked:114-120`, `Click:122-127`, `RenderTo:185-186`). Test: create `tests/test.checkbox.pas`.

- [ ] **Step 1: Write the failing test.** Create `tests/test.checkbox.pas`:
```pascal
unit test.checkbox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, StdCtrls, fpcunit, testregistry, tyControls.CheckBox;
type
  TCheckBoxTriStateTest = class(TTestCase)
  published
    procedure TestClickCycleNoGrayed;
    procedure TestClickCycleAllowGrayed;
    procedure TestCheckedDerivedFromState;
    procedure TestSetCheckedMapsState;
  end;
implementation

procedure TCheckBoxTriStateTest.TestClickCycleNoGrayed;
var cb: TTyCheckBox;
begin
  cb := TTyCheckBox.Create(nil);
  try
    cb.AllowGrayed := False;
    AssertEquals('init', Ord(cbUnchecked), Ord(cb.State));
    cb.Click; AssertEquals('->checked', Ord(cbChecked), Ord(cb.State));
    cb.Click; AssertEquals('->unchecked', Ord(cbUnchecked), Ord(cb.State));
  finally cb.Free; end;
end;

procedure TCheckBoxTriStateTest.TestClickCycleAllowGrayed;
var cb: TTyCheckBox;
begin
  cb := TTyCheckBox.Create(nil);
  try
    cb.AllowGrayed := True;
    cb.Click; AssertEquals('->checked', Ord(cbChecked), Ord(cb.State));
    cb.Click; AssertEquals('->grayed', Ord(cbGrayed), Ord(cb.State));
    cb.Click; AssertEquals('->unchecked', Ord(cbUnchecked), Ord(cb.State));
  finally cb.Free; end;
end;

procedure TCheckBoxTriStateTest.TestCheckedDerivedFromState;
var cb: TTyCheckBox;
begin
  cb := TTyCheckBox.Create(nil);
  try
    cb.State := cbChecked;   AssertTrue('checked', cb.Checked);
    cb.State := cbGrayed;    AssertFalse('grayed not Checked', cb.Checked);
    cb.State := cbUnchecked; AssertFalse('unchecked', cb.Checked);
  finally cb.Free; end;
end;

procedure TCheckBoxTriStateTest.TestSetCheckedMapsState;
var cb: TTyCheckBox;
begin
  cb := TTyCheckBox.Create(nil);
  try
    cb.Checked := True;  AssertEquals('True->cbChecked', Ord(cbChecked), Ord(cb.State));
    cb.Checked := False; AssertEquals('False->cbUnchecked', Ord(cbUnchecked), Ord(cb.State));
  finally cb.Free; end;
end;

initialization
  RegisterTest(TCheckBoxTriStateTest);
end.
```
Register it in `tests/tytests.lpr` (append `test.checkbox` to the `uses` clause — change the prior last unit's `;` to `,` and add it).

- [ ] **Step 2: Run — fails to compile** (`State`/`AllowGrayed` don't exist yet).
Run: `lazbuild tests/tytests.lpi 2>&1 | grep -iE "error|State"`
Expected: compile error, identifier `State` not found.

- [ ] **Step 3: Implement tri-state.** In `source/tyControls.CheckBox.pas`:
  (a) Add `StdCtrls` to the interface `uses` (for `TCheckBoxState`).
  (b) Replace the private field `FChecked: Boolean;` (`:10`) with:
```pascal
    FState: TCheckBoxState;
    FAllowGrayed: Boolean;
    procedure SetState(const AValue: TCheckBoxState);
```
  (c) Replace the `SetChecked` declaration/body. New `SetState` is the sole mutator; `SetChecked` delegates:
```pascal
procedure TTyCheckBox.SetState(const AValue: TCheckBoxState);
begin
  if FState = AValue then Exit;
  FState := AValue;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyCheckBox.SetChecked(const AValue: Boolean);
begin
  if AValue then SetState(cbChecked) else SetState(cbUnchecked);
end;

function TTyCheckBox.GetChecked: Boolean;
begin
  Result := FState = cbChecked;
end;
```
  (Add `function GetChecked: Boolean;` to the private section; keep `procedure SetChecked(const AValue: Boolean);`.)
  (d) Published section (`:24-34`): change `Checked` to use the getter, and add `State`/`AllowGrayed`:
```pascal
    property State: TCheckBoxState read FState write SetState default cbUnchecked;
    property AllowGrayed: Boolean read FAllowGrayed write FAllowGrayed default False;
    property Checked: Boolean read GetChecked write SetChecked default False;
```
  (e) `Click` (`:122-127`) — the tri-state cycle:
```pascal
procedure TTyCheckBox.Click;
begin
  if not Enabled then Exit;
  if FAllowGrayed then
    case FState of
      cbUnchecked: SetState(cbChecked);
      cbChecked:   SetState(cbGrayed);
      cbGrayed:    SetState(cbUnchecked);
    end
  else
    SetChecked(FState <> cbChecked);
  inherited Click;
end;
```
  (f) `CurrentStates` (`:103-112`) — branch on FState:
```pascal
  Result := inherited CurrentStates;
  if (FState in [cbChecked, cbGrayed]) and Enabled then
    Include(Result, tysActive);
```
  (g) RenderTo glyph (`:185-186`) — replace `if FChecked then P.DrawGlyph(BoxRect, tgCheck, S.TextColor, 2);` with:
```pascal
    case FState of
      cbChecked: P.DrawGlyph(BoxRect, tgCheck, S.TextColor, 2);
      cbGrayed:  P.DrawGlyph(BoxRect, tgCheckIndeterminate, S.TextColor, 2);
    end;
```

- [ ] **Step 4: Run — passes.**
Run: `lazbuild tycontrols.lpk >/dev/null 2>&1 && lazbuild tests/tytests.lpi >/dev/null 2>&1 && ./tests/tytests.exe --suite=TCheckBoxTriStateTest -a --format=plain 2>&1 | grep -iE "run|failures|errors"`
Expected: 4 run / 0 failures / 0 errors. Then full suite: `./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of"` → run = baseline+4, failures 0, errors 11.

- [ ] **Step 5: Commit.**
```bash
git add source/tyControls.CheckBox.pas tests/test.checkbox.pas tests/tytests.lpr
git commit -m "feat(checkbox): tri-state (State/AllowGrayed) with grayed glyph

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: pure `TyFilterItemsByPrefix`

**Files:** Modify `source/tyControls.ComboBox.pas` (add an interface-level function). Test: create `tests/test.combobox.pas`.

- [ ] **Step 1: Write the failing test.** Create `tests/test.combobox.pas`:
```pascal
unit test.combobox;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.ComboBox;
type
  TComboFilterTest = class(TTestCase)
  published
    procedure TestPrefixFilter;
    procedure TestEmptyPrefixReturnsAll;
    procedure TestNoMatchReturnsEmpty;
  end;
implementation

procedure TComboFilterTest.TestPrefixFilter;
var src, dst: TStringList;
begin
  src := TStringList.Create;
  try
    src.AddStrings(['Alpha','Beta','Alubar','beacon']);
    dst := TyFilterItemsByPrefix(src, 'al');   // case-insensitive
    try
      AssertEquals('two match', 2, dst.Count);
      AssertEquals('Alpha', dst[0]); AssertEquals('Alubar', dst[1]);
    finally dst.Free; end;
  finally src.Free; end;
end;

procedure TComboFilterTest.TestEmptyPrefixReturnsAll;
var src, dst: TStringList;
begin
  src := TStringList.Create;
  try
    src.AddStrings(['a','b','c']);
    dst := TyFilterItemsByPrefix(src, '');
    try AssertEquals('all', 3, dst.Count); finally dst.Free; end;
  finally src.Free; end;
end;

procedure TComboFilterTest.TestNoMatchReturnsEmpty;
var src, dst: TStringList;
begin
  src := TStringList.Create;
  try
    src.AddStrings(['a','b']);
    dst := TyFilterItemsByPrefix(src, 'zzz');
    try AssertEquals('none', 0, dst.Count); finally dst.Free; end;
  finally src.Free; end;
end;

initialization
  RegisterTest(TComboFilterTest);
end.
```
Register `test.combobox` in `tests/tytests.lpr` uses.

- [ ] **Step 2: Run — fails to compile** (`TyFilterItemsByPrefix` undefined).
Run: `lazbuild tests/tytests.lpi 2>&1 | grep -iE "error|TyFilter"` → identifier not found.

- [ ] **Step 3: Implement.** In `source/tyControls.ComboBox.pas` interface, after the `type` block (near the class), declare, and implement in the `implementation`:
```pascal
// interface:
function TyFilterItemsByPrefix(AItems: TStrings; const APrefix: string): TStringList;

// implementation:
function TyFilterItemsByPrefix(AItems: TStrings; const APrefix: string): TStringList;
var i: Integer; p: string;
begin
  Result := TStringList.Create;
  if AItems = nil then Exit;
  p := LowerCase(APrefix);
  for i := 0 to AItems.Count - 1 do
    if (p = '') or (Copy(LowerCase(AItems[i]), 1, Length(p)) = p) then
      Result.Add(AItems[i]);
end;
```
(The caller owns the returned list.)

- [ ] **Step 4: Run — passes.**
Run: `lazbuild tycontrols.lpk >/dev/null 2>&1 && lazbuild tests/tytests.lpi >/dev/null 2>&1 && ./tests/tytests.exe --suite=TComboFilterTest -a --format=plain 2>&1 | grep -iE "run|failures"`
Expected: 3 run / 0 failures.

- [ ] **Step 5: Commit.**
```bash
git add source/tyControls.ComboBox.pas tests/test.combobox.pas tests/tytests.lpr
git commit -m "feat(combobox): pure TyFilterItemsByPrefix (case-insensitive prefix)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: editable `TTyComboBox` (csDropDown + autocomplete)

**Files:** Modify `source/tyControls.ComboBox.pas` (class decl `:10-104`, constructor `:125-141`, `DropDown:330-378`, `ResyncIndexFromText:254-271`, `Click:396-409`, `SetController:162-173`, `RenderTo:506-533`). Test: extend `tests/test.combobox.pas`.

**Context (verified):** `TyFieldButtonWidth=18` (`Types.pas:94`); the chevron zone is `BtnR=Rect(R.Right-BtnW,...)` and the field zone `TextR` is left of it (`RenderTo:519-524`). `TTyEdit.SetText` fires `OnChange` (`Edit.pas:556`) → need a `FSyncingText` guard. `ResyncIndexFromText` blanks `FText` when text∉Items (`:266-270`) — gate to `csDropDownList`. `MaxLength`/`CharCase` already published (`:93-94`, reserved for this).

- [ ] **Step 1: Write the failing tests.** Append to `tests/test.combobox.pas` a second class:
```pascal
  TComboEditableTest = class(TTestCase)
  published
    procedure TestEditorPresentOnlyInDropDown;
    procedure TestFreeTextSurvivesItemsChange;
  end;
...
procedure TComboEditableTest.TestEditorPresentOnlyInDropDown;
var c: TTyComboBox;
begin
  c := TTyComboBox.Create(nil);
  try
    AssertFalse('list-mode: no editor visible', c.EditorVisibleForTest);
    c.Style := csDropDown;
    AssertTrue('dropdown-mode: editor visible', c.EditorVisibleForTest);
  finally c.Free; end;
end;

procedure TComboEditableTest.TestFreeTextSurvivesItemsChange;
var c: TTyComboBox;
begin
  c := TTyComboBox.Create(nil);
  try
    c.Style := csDropDown;
    c.Items.AddStrings(['Alpha','Beta']);
    c.Text := 'Gam';                 // free text, not in Items
    c.Items.Add('Gamma');            // triggers ItemsChanged->ResyncIndexFromText
    AssertEquals('free text preserved', 'Gam', c.Text);
    AssertEquals('no item selected', -1, c.ItemIndex);
  finally c.Free; end;
end;
```
Add `procedure RegisterTest(TComboEditableTest);` to `initialization`. (`EditorVisibleForTest` is a public test seam added below.)

- [ ] **Step 2: Run — fails to compile** (`Style`/`EditorVisibleForTest` undefined).
Run: `lazbuild tests/tytests.lpi 2>&1 | grep -iE "error"`.

- [ ] **Step 3: Implement.** In `source/tyControls.ComboBox.pas`:
  (a) `uses` += `tyControls.Edit`.
  (b) Private fields: add `FStyle: TTyComboBoxStyle; FEditor: TTyEdit; FVisibleItems: TStringList; FSyncingText: Boolean; procedure SetStyle(AValue: TTyComboBoxStyle); procedure EditorChange(Sender: TObject);` and a type before the class: `TTyComboBoxStyle = (csDropDownList, csDropDown);`.
  (c) Public test seam: `function EditorVisibleForTest: Boolean;` → `Result := (FEditor <> nil) and FEditor.Visible;`.
  (d) Published: `property Style: TTyComboBoxStyle read FStyle write SetStyle default csDropDownList;`.
  (e) Constructor (`:125-141`): after existing init, add `FStyle := csDropDownList; FVisibleItems := TStringList.Create; FSyncingText := False; FEditor := TTyEdit.Create(Self); FEditor.Parent := Self; FEditor.Visible := False; FEditor.OnChange := @EditorChange;`. In `Destroy`, free `FVisibleItems` (FEditor is owned by Self).
  (f) `SetStyle`:
```pascal
procedure TTyComboBox.SetStyle(AValue: TTyComboBoxStyle);
begin
  if FStyle = AValue then Exit;
  FStyle := AValue;
  if FEditor <> nil then
  begin
    FEditor.Visible := (FStyle = csDropDown);
    if FStyle = csDropDown then LayoutEditor;   // position over the field zone
  end;
  Invalidate;
end;
```
  (g) `LayoutEditor` (new private): position `FEditor` at the field rect minus the chevron zone (device px, mirroring RenderTo):
```pascal
procedure TTyComboBox.LayoutEditor;
var BtnW: Integer;
begin
  if (FEditor = nil) or (FStyle <> csDropDown) then Exit;
  BtnW := MulDiv(ButtonWidthLogical, Font.PixelsPerInch, 96);
  FEditor.SetBounds(2, 2, ClientWidth - BtnW - 4, ClientHeight - 4);
end;
```
Call `LayoutEditor` from `Resize` (add an override or extend the existing one).
  (h) `EditorChange` — filter + open, mirror text back, guard re-entrancy:
```pascal
procedure TTyComboBox.EditorChange(Sender: TObject);
var filtered: TStringList;
begin
  if FSyncingText then Exit;
  FText := FEditor.Text;                    // free-input text
  FItemIndex := FItems.IndexOf(FText);      // -1 if not a member (no blanking)
  filtered := TyFilterItemsByPrefix(FItems, FText);
  try
    if filtered.Count = 0 then
      CloseUp
    else
    begin
      FVisibleItems.Assign(filtered);
      DropDownFiltered;                      // open using FVisibleItems
    end;
  finally filtered.Free; end;
  if Assigned(FOnChange) then FOnChange(Self);
end;
```
  (i) `DropDownFiltered` (new): same as `DropDown` but assign `FVisibleItems` (and size off it). Factor the shared popup-creation out; the filtered path does `FPopupList.OnChange := nil; FPopupList.Items.Assign(FVisibleItems); FPopupList.OnChange := @PopupListChange;` and sizes via a height computed from `FVisibleItems.Count`. (Reuse the existing lazy-create block from `DropDown:339-357`.)
  (j) On selecting a filtered row / Enter: set `FSyncingText := True; FEditor.Text := <picked>; FSyncingText := False;` then `FText := picked; CloseUp;` (the guard prevents the write-back re-firing EditorChange).
  (k) `ResyncIndexFromText` (`:254-271`): gate the blank-FText clause behind list-mode. Change the `else` branch (`:267-270`) to:
```pascal
  else
  begin
    FItemIndex := -1;
    if FStyle = csDropDownList then FText := '';   // editable mode keeps free text
  end;
```
  (l) `Click` (`:396-409`): in csDropDown, only toggle when the click is in the chevron zone (the FEditor child consumes field-area clicks). Add at the top of the toggle logic: `if (FStyle = csDropDown) then begin if not PointInChevron(ScreenToClient(Mouse.CursorPos)) then Exit; end;` — implement `PointInChevron` using `BtnW` like RenderTo. (Keep the existing 200ms reopen guard.)
  (m) `SetController` (`:162-173`): after propagating to `FPopupList`, also `if FEditor <> nil then FEditor.Controller := AValue;`.

- [ ] **Step 4: Run — passes.**
Run: `lazbuild tycontrols.lpk >/dev/null 2>&1 && lazbuild tests/tytests.lpi >/dev/null 2>&1 && ./tests/tytests.exe --suite=TComboEditableTest -a --format=plain 2>&1 | grep -iE "run|failures|errors"`
Expected: 2 run / 0 failures / 0 errors. Full suite: run = prior+2, failures 0, errors 11. (Live filter/open + chevron toggle are GUI — real-machine.)

- [ ] **Step 5: Commit.**
```bash
git add source/tyControls.ComboBox.pas tests/test.combobox.pas
git commit -m "feat(combobox): editable csDropDown + prefix autocomplete (embedded TTyEdit)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: `TTyTabSet`

**Files:** Create `source/tyControls.TabSet.pas`. Modify `tycontrols.lpk`. Test: create `tests/test.tabset.pas`.

**Context (verified):** `TTyCustomTabStrip` (`tyControls.TabStrip`) has abstract `GetTabCount`/`GetTabCaption` (`:92-93`) + inherited-abstract `GetStyleTypeKey` (`Base.pas:128`) — all 3 MUST be overridden. `SetTabIndex` (`:619-672`, non-virtual) is the selection entry (fires OnChanging/DoSelectTab/OnChange); publish `TabIndex read FTabIndex write SetTabIndex`. `DoCloseClick` (`:601-611`) fires `OnTabClose` then calls virtual `RemoveTabData` and nothing else — the override owns FTabIndex reconcile (copy `TTyPageControl.UnregisterPage:156-180`). `TabsClosable`/`OnTabClose`/`OnChange`/`OnChanging`/`OnReorder` are inherited-published. `RegisterClass` in `initialization` before `end.`.

- [ ] **Step 1: Write the failing test.** Create `tests/test.tabset.pas`:
```pascal
unit test.tabset;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.TabSet;
type
  TTabSetTest = class(TTestCase)
  private
    FChanged: Boolean;
    procedure OnChangeHandler(Sender: TObject);
  published
    procedure TestTabCountFromTabs;
    procedure TestSelectFiresOnChange;
    procedure TestRemoveClampsIndex;
    procedure TestStyleTypeKey;
  end;
implementation

procedure TTabSetTest.OnChangeHandler(Sender: TObject); begin FChanged := True; end;

procedure TTabSetTest.TestTabCountFromTabs;
var t: TTyTabSet;
begin
  t := TTyTabSet.Create(nil);
  try
    t.Tabs.AddStrings(['One','Two','Three']);
    AssertEquals('count', 3, t.TabCountForTest);
    AssertEquals('caption', 'Two', t.TabCaptionForTest(1));
  finally t.Free; end;
end;

procedure TTabSetTest.TestSelectFiresOnChange;
var t: TTyTabSet;
begin
  FChanged := False;
  t := TTyTabSet.Create(nil);
  try
    t.Tabs.AddStrings(['A','B']);
    t.OnChange := @OnChangeHandler;
    t.TabIndex := 1;
    AssertEquals('index', 1, t.TabIndex);
    AssertTrue('OnChange fired', FChanged);
  finally t.Free; end;
end;

procedure TTabSetTest.TestRemoveClampsIndex;
var t: TTyTabSet;
begin
  t := TTyTabSet.Create(nil);
  try
    t.Tabs.AddStrings(['A','B','C']);
    t.TabIndex := 2;              // last
    t.RemoveTabForTest(2);        // remove selected last
    AssertEquals('tabs', 2, t.Tabs.Count);
    AssertEquals('clamped', 1, t.TabIndex);
  finally t.Free; end;
end;

procedure TTabSetTest.TestStyleTypeKey;
var t: TTyTabSet;
begin
  t := TTyTabSet.Create(nil);
  try AssertEquals('TyTabControl', t.StyleTypeKeyForTest); finally t.Free; end;
end;

initialization
  RegisterTest(TTabSetTest);
end.
```
Register `test.tabset` in `tests/tytests.lpr` uses.

- [ ] **Step 2: Run — fails to compile** (`tyControls.TabSet` doesn't exist).

- [ ] **Step 3: Create the unit.** `source/tyControls.TabSet.pas`:
```pascal
unit tyControls.TabSet;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, tyControls.TabStrip;
type
  { TTyTabSet — a pure tab strip (no page container) on the SP1 TTyCustomTabStrip
    header engine. Captions live in a TStrings; selection = TabIndex + OnChange. }
  TTyTabSet = class(TTyCustomTabStrip)
  private
    FTabs: TStringList;
    procedure SetTabs(AValue: TStrings);
    procedure TabsListChanged(Sender: TObject);
  protected
    function GetStyleTypeKey: string; override;
    function GetTabCount: Integer; override;
    function GetTabCaption(AIndex: Integer): string; override;
    procedure DoSelectTab(AIndex: Integer); override;
    procedure DoReorderTabs(AFrom, ATo: Integer); override;
    procedure RemoveTabData(AIndex: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    // test seams:
    function TabCountForTest: Integer;
    function TabCaptionForTest(AIndex: Integer): string;
    procedure RemoveTabForTest(AIndex: Integer);
    function StyleTypeKeyForTest: string;
  published
    property Tabs: TStrings read FTabs write SetTabs;
    property TabIndex: Integer read FTabIndex write SetTabIndex default -1;
  end;
implementation

constructor TTyTabSet.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTabs := TStringList.Create;
  FTabs.OnChange := @TabsListChanged;
  Width := 240; Height := 32;
end;

destructor TTyTabSet.Destroy;
begin
  FTabs.Free;
  inherited Destroy;
end;

function TTyTabSet.GetStyleTypeKey: string;
begin
  Result := 'TyTabControl';   // existing themed frame key (BuiltinThemeData/DefaultTheme)
end;

function TTyTabSet.GetTabCount: Integer;
begin
  Result := FTabs.Count;
end;

function TTyTabSet.GetTabCaption(AIndex: Integer): string;
begin
  if (AIndex >= 0) and (AIndex < FTabs.Count) then Result := FTabs[AIndex] else Result := '';
end;

procedure TTyTabSet.DoSelectTab(AIndex: Integer);
begin
  Invalidate;   // repaint the selected header (SetTabIndex already fired OnChange)
end;

procedure TTyTabSet.DoReorderTabs(AFrom, ATo: Integer);
begin
  if (AFrom >= 0) and (AFrom < FTabs.Count) and (ATo >= 0) and (ATo < FTabs.Count) then
  begin
    FTabs.OnChange := nil;
    FTabs.Move(AFrom, ATo);
    FTabs.OnChange := @TabsListChanged;
    TabsChanged;   // base repaints; header geometry recomputed at paint
  end;
end;

procedure TTyTabSet.RemoveTabData(AIndex: Integer);
var want: Integer;
begin
  // Base DoCloseClick delegates ALL reconciliation here (mirror TTyPageControl.UnregisterPage).
  // FOnChange is PRIVATE on the base — do NOT touch it. Route the selection change through
  // SetTabIndex (the only OnChange-firing path, TabStrip.pas:670).
  if (AIndex < 0) or (AIndex >= FTabs.Count) then Exit;
  want := FTabIndex;
  if AIndex < FTabIndex then Dec(want);
  FTabs.OnChange := nil;
  FTabs.Delete(AIndex);
  FTabs.OnChange := @TabsListChanged;
  if FTabs.Count = 0 then want := -1
  else if want > FTabs.Count - 1 then want := FTabs.Count - 1;
  if want <> FTabIndex then
    SetTabIndex(want)   // clamps + DoSelectTab + fires OnChange
  else
    TabsChanged;        // same numeric index, tab set changed: just repaint
end;

procedure TTyTabSet.SetTabs(AValue: TStrings);
begin
  FTabs.Assign(AValue);
end;

procedure TTyTabSet.TabsListChanged(Sender: TObject);
begin
  if FTabIndex > FTabs.Count - 1 then FTabIndex := FTabs.Count - 1;
  TabsChanged;
end;

function TTyTabSet.TabCountForTest: Integer; begin Result := GetTabCount; end;
function TTyTabSet.TabCaptionForTest(AIndex: Integer): string; begin Result := GetTabCaption(AIndex); end;
procedure TTyTabSet.RemoveTabForTest(AIndex: Integer); begin RemoveTabData(AIndex); end;
function TTyTabSet.StyleTypeKeyForTest: string; begin Result := GetStyleTypeKey; end;

initialization
  RegisterClass(TTyTabSet);
end.
```
**Verified (TabStrip.pas):** the repaint hook is `TabsChanged` (protected virtual, `:102`, body `if not csLoading then Invalidate` `:264`); `FTabIndex` (`:78`) + `SetTabIndex` (`:98`) are protected (accessible); `FOnChange` is PRIVATE (`:34`, in the `private` 30-73 block) — do NOT reference it; the ONLY OnChange-firing path is `SetTabIndex` (`:670-671`). If `FTabs.Move` isn't available on this FPC, use delete-then-insert.

Add `source/tyControls.TabSet.pas` to `tycontrols.lpk` (an `<Item>` with `<Filename Value="source/tyControls.TabSet.pas"/>` + `<UnitName Value="tyControls.TabSet"/>`).

- [ ] **Step 4: Run — passes.**
Run: `lazbuild tycontrols.lpk >/dev/null 2>&1 && lazbuild tests/tytests.lpi >/dev/null 2>&1 && ./tests/tytests.exe --suite=TTabSetTest -a --format=plain 2>&1 | grep -iE "run|failures|errors"`
Expected: 4 run / 0 failures / 0 errors. Full suite: run = prior+4, failures 0, errors 11.

- [ ] **Step 5: Commit.**
```bash
git add source/tyControls.TabSet.pas tycontrols.lpk tests/test.tabset.pas tests/tytests.lpr
git commit -m "feat(tabset): TTyTabSet pure tab strip on the TabStrip engine

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: `TTyTabSet` palette icon + registration

**Files:** Modify `designtime/tyControls.Design.pas:684-692`, `tools/genicons/genicons.lpr:278`, `scripts/gen-icons.ps1:9-21`, `tests/test.paletteicons.pas:18`; regenerate `designtime/tycontrols_icons.lrs` + `designtime/icons/TTyTabSet*.png`.

- [ ] **Step 1: Register the component.** In `designtime/tyControls.Design.pas`: add `tyControls.TabSet` to the `uses`; add `TTyTabSet` to `RegisterComponents('TyControls', [...])` (`:684-692`), next to `TTyPageControl, TTyTabSheet` (line 688).

- [ ] **Step 2: Add the glyph + lists (drift-guard forces all together).**
  (a) `tools/genicons/genicons.lpr`: bump `Glyphs: array[0..39]` → `array[0..40]` (`:278`); add a comma after the last entry and append `(Name:'TTyTabSet'; Draw:@GTabSet)`; add a draw proc modeled on `GTabControl`:
```pascal
procedure GTabSet(b: TBGRABitmap); begin FillRRect(b,3,5,9,11,1.5,Acc); RRect(b,9.5,5,15.5,11,1.5,Ink); RRect(b,16,5,21,11,1.5,Ink); Line(b,3,11,21,11,Ink,1.4); end;
```
  (b) `scripts/gen-icons.ps1`: add `'TTyTabSet'` to `$classes` (`:9-21`), next to `'TTyPageControl','TTyTabSheet'`.
  (c) `tests/test.paletteicons.pas`: bump `CClasses: array[0..39]` → `array[0..40]` (`:18`); append `'TTyTabSet'`.

- [ ] **Step 3: Regenerate the icon resource.**
Run: `pwsh -File scripts/gen-icons.ps1` (or `powershell -File` if pwsh absent). The drift-guard must print `OK: 41 registered components all have icons` and pack 41×3=123 resources into `designtime/tycontrols_icons.lrs` + write `designtime/icons/TTyTabSet*.png`.

- [ ] **Step 4: Build + test.**
Run: `lazbuild tycontrols.lpk >/dev/null 2>&1 && lazbuild tycontrols_dt.lpk >/dev/null 2>&1 && lazbuild tests/tytests.lpi >/dev/null 2>&1 && ./tests/tytests.exe --suite=TPaletteIconTest -a --format=plain 2>&1 | grep -iE "failures|errors"`
Expected: dt exit 0; `TestAllResourcesPresentAndPng` 0 failures (asserts TTyTabSet ×3 PNGs). Full suite unchanged run count, failures 0, errors 11.

- [ ] **Step 5: Commit.**
```bash
git add designtime/tyControls.Design.pas tools/genicons/genicons.lpr scripts/gen-icons.ps1 tests/test.paletteicons.pas designtime/tycontrols_icons.lrs designtime/icons/
git commit -m "feat(tabset): palette icon + component registration

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 7: demo showcase + finish

**Files:** Modify `examples/demo/mainform.lfm` (+ `.pas` handlers). **CAUTION — user's design surface with uncommitted edits: Read the working-tree `.lfm`/`.pas` FIRST, use Edit for precise insertions, NEVER rewrite; do not stage `demo.lpi`.**

- [ ] **Step 1: Add the three controls to the demo.** Read `examples/demo/mainform.lfm`; insert (in a suitable existing panel, e.g. near the other simple controls) a `TTyCheckBox` with `AllowGrayed=True State=cbGrayed`, a `TTyComboBox` with `Style=csDropDown` + a few `Items`, and a `TTyTabSet` with a few `Tabs`. Add `tyControls.TabSet` to `mainform.pas` uses. Keep it minimal; handlers optional (these controls are self-demonstrating).

- [ ] **Step 2: Build the demo.**
Run: `lazbuild examples/demo/demo.lpi` → exit 0.

- [ ] **Step 3: Full clean build + test.**
Run: `lazbuild tycontrols.lpk && lazbuild tycontrols_dt.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)"`
Expected: all exit 0; run = baseline + 13 (4+3+2+4); failures 0; errors 11.

- [ ] **Step 4: Commit demo.**
```bash
git add examples/demo/mainform.lfm examples/demo/mainform.pas
git commit -m "feat(examples): demo shows tri-state CheckBox, editable ComboBox, TTyTabSet

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 5: Finish the branch.** Use `superpowers:finishing-a-development-branch` (verify tests, present merge options). Prior phases merged locally (ff) to `main`; do NOT push.

---

## Post-implementation notes (final review)
- **GUI-only (real-machine eyeball):** the grayed checkbox glyph, the editable combo's live filter/dropdown/chevron-toggle/embedded-edit focus, and the tab strip's hover/scroll/close/drag — all need a real Lafarus run.
- **Re-verify vs spec:** `FState` fully replaces `FChecked` (no stale field); `CurrentStates`/RenderTo branch on `FState`; combo re-entrancy guard (`FSyncingText`) + `ResyncIndexFromText` free-input gate + chevron-only toggle; TabSet's 3 mandatory overrides incl. `GetStyleTypeKey='TyTabControl'` + `RemoveTabData` reconcile; palette 4-way lockstep + the two `array[0..40]` bumps.
- **TabStrip access (verified, baked into Task 5):** repaint via `TabsChanged`; selection/OnChange only via `SetTabIndex` (`FOnChange` is private); `FTabIndex` is protected. No further grep needed.
