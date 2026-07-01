# Dialogs S2 Input-Family Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Five themed input dialogs on the S1 `TTyDialog` foundation — `TyInputDialog`, `TyPasswordDialog`, `TyTextDialog`, `TySelectValueDialog` (in `tyControls.Dialogs.pas`) and `TySelectPathDialog` (folder picker, in `tyControls.Dialogs.SelectPath.pas`) — each with `Ty`-prefixed global functions (LCL-parity) + a non-visual component.

**Architecture:** Extend the S1 build/show-separated pattern verbatim (construct-only builder → `RunDialogModal` → globals; a `TComponent` with `Execute`). One base addition: an opt-in **resizable** path (`LayoutContent` virtual + `Resize` override) for the multi-line Text and directory-tree SelectPath dialogs. Text dialogs reuse `TTyEdit`/`TTyMemo`/`TTyListBox`; SelectPath reuses `TTyTreeView` lazy loading.

**Tech Stack:** Lazarus/FPC, LCL (`TModalResult`, `TStrings`, `SysUtils` filesystem), builds on `tyControls.Dialogs` (S1), `tyControls.Edit`, `tyControls.Memo`, `tyControls.ListBox`, `tyControls.TreeView`, `tyControls.TyLabel`, `tyControls.StrConsts`. Headless fpcunit; SelectPath filesystem logic tested against a scratch temp dir.

**Branch:** `feat/dialogs-s2` (checked out). **Spec:** `docs/superpowers/specs/2026-07-02-dialogs-s2-input-family-design.md`.

**Build/test (git-bash, repo root):**
- Lib: `lazbuild tycontrols.lpk 2>&1 | grep -iE "error|fatal"; echo exit ${PIPESTATUS[0]}`
- DT: `lazbuild tycontrols_dt.lpk 2>&1 | grep -iE "error|fatal"; echo exit ${PIPESTATUS[0]}`
- Tests: `lazbuild tests/tytests.lpi >/dev/null 2>&1 && ./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)"`
- **Baseline (S1 merged to main): 1564 run / 0 failures / 11 errors.** Keep failures 0, errors 11.

## Verified control APIs (from code map — trust these)
- **`TTyEdit`** (`tyControls.Edit`): `constructor Create(AOwner)`; `property Text: string`; `property PasswordChar: string` (single UTF-8 char mask). Needs `Parent` set. Ancestor `TTyCustomControl` (windowed).
- **`TTyMemo`** (`tyControls.Memo`): `Create(AOwner)`; `property Text: string` (whole text, `LineEnding`-joined); `property Lines: TStrings`. Windowed.
- **`TTyListBox`** (`tyControls.ListBox`): `Create(AOwner)`; `property Items: TStringList`; `property ItemIndex: Integer default -1`; `property OnChange: TNotifyEvent` (fires on ItemIndex change). No published `OnDblClick`, but inherited `TControl.OnDblClick` is assignable in code. Windowed.
- **`TTyTreeView`** (`tyControls.TreeView`): `Create(AOwner)`; nodes are `PTyTreeNode`; `function AddChild(AParent: PTyTreeNode): PTyTreeNode` (nil parent → root). **No text/data field on the node.** Text via `property OnGetText: TTyTreeGetTextEvent` (`procedure(Sender; Node; var Text: string)`). Per-node data: call `SetNodeDataSize(n)` BEFORE adding nodes, then `function GetNodeData(Node): Pointer` (raw n-byte blob). Lazy: `property OnInitChildren: TTyTreeInitChildrenEvent` (`procedure(Sender; Node; var ChildCount: Cardinal)`), `property OnInitNode: TTyTreeInitNodeEvent` (`procedure(Sender; ParentNode, Node; var InitStates: TTyNodeInitStates)`); include `ivsHasChildren` in `InitStates` to mark expandable without materializing. `property Expanded[Node]: Boolean`; `property Selected[Node]: Boolean`; `property FocusedNode: PTyTreeNode`. Windowed.
- **`TTyLabel`** (`tyControls.TyLabel`): `Create(AOwner)`; `Caption`; `property WordWrap: Boolean default False`; `property Alignment`; `AutoSize`. Ancestor `TTyGraphicControl` (NON-windowed — no handle).
- **`TTyDialog`** (`tyControls.Dialogs`): `constructor CreateNew(AOwner; Num=0)`; `function ContentRect: TRect` (client minus titlebar top & button-bar bottom); `function AddButton(cap; result; default=False; cancel=False): TTyButton`; `procedure AutoSizeToContent(w,h)`; inherited `property Resizable: Boolean` (writable; `CreateNew` sets it `False`). Already overrides `Paint` + `KeyDown`.

## HARD RULES (S1 lessons — violating these breaks the headless runner)
- **NEVER call `ShowModal` in a test** (blocks).
- **NEVER call `SetDesigning` on a dialog** — a `csDesigning` `TTyForm` with WINDOWED children (edit/memo/listbox/tree) raises win32 "error 1407" headless. Construct-only tests just build → assert → `Free`.
- Dialogs are built with `CreateNew(Application)` (owner frees them) OR `CreateNew(nil)` + explicit `Free` in tests.
- **i18n**: user-facing built-in strings ('New Folder', its prompt) are resourcestrings in `tyControls.StrConsts` (converted in Task 9, used as literals earlier only if unavoidable — prefer wiring resourcestrings from the start). Buttons reuse `rsMsgBtnOK`/`rsMsgBtnCancel` (already exist from S1).

---

### Task 1: Resizable base — `LayoutContent` virtual + `Resize` override

**Files:** Modify `source/tyControls.Dialogs.pas`; Test `tests/test.dialogs.pas`.

- [ ] **Step 1: Write the failing test.** Add to `tests/test.dialogs.pas`:
```pascal
  // access subclass to drive protected LayoutContent + a stub content widget
  TResizeProbeDialog = class(TTyDialog)
  public
    Content: TTyPanel;   // stand-in windowed content widget
    procedure LayoutContent; override;   // fills ContentRect
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
  end;

  TDialogResizeTest = class(TTestCase)
  published
    procedure TestLayoutContentFillsContentRect;
    procedure TestReflowOnClientResize;
  end;
```
Impl:
```pascal
constructor TResizeProbeDialog.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  Resizable := True;
  Content := TTyPanel.Create(Self);
  Content.Parent := Self;
  AddButton('OK', mrOk, True, False);
  AutoSizeToContent(300, 200);
end;

procedure TResizeProbeDialog.LayoutContent;
var r: TRect;
begin
  if Content = nil then Exit;
  r := ContentRect;
  Content.SetBounds(r.Left, r.Top, r.Right - r.Left, r.Bottom - r.Top);
end;

procedure TDialogResizeTest.TestLayoutContentFillsContentRect;
var d: TResizeProbeDialog; r: TRect;
begin
  d := TResizeProbeDialog.CreateNew(nil);
  try
    d.LayoutContent;
    r := d.ContentRect;
    AssertEquals('content left', r.Left, d.Content.Left);
    AssertEquals('content width', r.Right - r.Left, d.Content.Width);
    AssertEquals('content bottom', r.Bottom, d.Content.Top + d.Content.Height);
  finally d.Free; end;
end;

procedure TDialogResizeTest.TestReflowOnClientResize;
var d: TResizeProbeDialog; w0: Integer;
begin
  d := TResizeProbeDialog.CreateNew(nil);
  try
    d.LayoutContent; w0 := d.Content.Width;
    d.ClientWidth := d.ClientWidth + 120;   // grow
    d.LayoutContent;                          // reflow (Resize would call this live)
    AssertTrue('content widened with the dialog', d.Content.Width > w0);
  finally d.Free; end;
end;
```
Add `RegisterTest(TDialogResizeTest);` and ensure `tyControls.Panel` is in the test `uses` (it is via S1 tests — verify; add if missing).

- [ ] **Step 2: Run, verify fail** (`LayoutContent` not virtual / not overridable → compile error).

- [ ] **Step 3: Implement.** In `TTyDialog` (`source/tyControls.Dialogs.pas`):
  - In the `protected` section add: `procedure LayoutContent; virtual;` and `procedure Resize; override;`
  - Implementations:
```pascal
procedure TTyDialog.LayoutContent;
begin
  // default: fixed-size dialogs position content once at build time; nothing to reflow.
end;

procedure TTyDialog.Resize;
begin
  inherited Resize;
  if FButtonBar <> nil then LayoutButtonBar;
  LayoutContent;
end;
```
(`FButtonBar` is the S1 private field; `LayoutButtonBar` is idempotent so this is safe for every dialog.)

- [ ] **Step 4: Run, verify pass.** Expected run 1566 (1564 + 2), failures 0, errors 11.

- [ ] **Step 5: Commit.**
```bash
git add source/tyControls.Dialogs.pas tests/test.dialogs.pas
git commit -m "$(printf 'feat(dialogs): TTyDialog resizable base — LayoutContent virtual + Resize reflow\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 2: `TyInputDialog` (the text-dialog template)

**Files:** Modify `source/tyControls.Dialogs.pas`; Test `tests/test.dialogs.pas`.

- [ ] **Step 1: Write the failing test.** Add:
```pascal
  TInputDialogTest = class(TTestCase)
  published
    procedure TestBuildSeedsEditAndButtons;
    procedure TestBoxReturnsDefaultOnCancelLogic;
  end;
```
Impl:
```pascal
procedure TInputDialogTest.TestBuildSeedsEditAndButtons;
var d: TTyDialog; e: TTyEdit;
begin
  d := TyBuildInputDialog('Rename', 'New name:', 'old.txt', e);
  try
    AssertTrue('edit created', e <> nil);
    AssertEquals('edit seeded', 'old.txt', e.Text);
    AssertEquals('two buttons', 2, TyDialogButtonCount(d));
    AssertEquals('ok caption', 'OK', TyDialogButton(d, 0).Caption);
  finally d.Free; end;
end;

procedure TInputDialogTest.TestBoxReturnsDefaultOnCancelLogic;
var d: TTyDialog; e: TTyEdit;
begin
  // simulate a cancel: build, set edit text, but the "extract" only applies on mrOk
  d := TyBuildInputDialog('X', 'p', 'def', e);
  try
    e.Text := 'typed';
    AssertEquals('cancel -> default kept', 'def', TyInputResult(e, 'def', mrCancel));
    AssertEquals('ok -> typed', 'typed', TyInputResult(e, 'def', mrOk));
  finally d.Free; end;
end;
```
Add `RegisterTest(TInputDialogTest);`. Add `tyControls.Edit` to the test `uses`.

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement.** In `source/tyControls.Dialogs.pas` add `tyControls.Edit` to the interface `uses`. Interface declarations:
```pascal
{ Input dialog — construct-only builder returns the dialog + its edit (out param). }
function TyBuildInputDialog(const ACaption, APrompt, ADefault: string; out AEdit: TTyEdit): TTyDialog;
function TyInputResult(AEdit: TTyEdit; const ADefault: string; AResult: TModalResult): string;
function TyInputQuery(const ACaption, APrompt: string; var AValue: string): Boolean;
function TyInputBox(const ACaption, APrompt, ADefault: string): string;
type
  TTyInputDialog = class(TComponent)
  private
    FCaption, FPrompt, FValue: string;
  public
    function Execute: Boolean;
  published
    property Caption: string read FCaption write FCaption;
    property Prompt: string read FPrompt write FPrompt;
    property Value: string read FValue write FValue;
  end;
```
Implementation — the SHARED content-layout helper (reused by Input/Password): a prompt label at top + one edit below, sized to a standard width:
```pascal
const
  TyDlgPad = 16;          // content padding
  TyDlgEditW = 320;       // default single-line input width
  TyDlgEditH = 30;

// places a wrapped prompt label + returns the y just below it (label parented to ADlg)
function TyPlacePrompt(ADlg: TTyDialog; const APrompt: string; AWidth: Integer): Integer;
var lbl: TTyLabel; r: TRect;
begin
  r := ADlg.ContentRect;
  lbl := TTyLabel.Create(ADlg);
  lbl.Parent := ADlg;
  lbl.WordWrap := True;
  lbl.Caption := APrompt;
  lbl.SetBounds(r.Left + TyDlgPad, r.Top + TyDlgPad, AWidth, 20);
  Result := r.Top + TyDlgPad + 26;
end;

function TyBuildInputDialog(const ACaption, APrompt, ADefault: string; out AEdit: TTyEdit): TTyDialog;
var y: Integer;
begin
  Result := TTyDialog.CreateNew(Application);
  Result.Caption := ACaption;
  y := TyPlacePrompt(Result, APrompt, TyDlgEditW);
  AEdit := TTyEdit.Create(Result);
  AEdit.Parent := Result;
  AEdit.Text := ADefault;
  AEdit.SetBounds(TyDlgPad, y, TyDlgEditW, TyDlgEditH);
  Result.AddButton(rsMsgBtnOK, mrOk, True, False);
  Result.AddButton(rsMsgBtnCancel, mrCancel, False, True);
  Result.AutoSizeToContent(TyDlgEditW + TyDlgPad, y + TyDlgEditH + TyDlgPad - Result.ContentRect.Top);
end;

function TyInputResult(AEdit: TTyEdit; const ADefault: string; AResult: TModalResult): string;
begin
  if AResult = mrOk then Result := AEdit.Text else Result := ADefault;
end;

function TyInputBox(const ACaption, APrompt, ADefault: string): string;
var d: TTyDialog; e: TTyEdit; mr: TModalResult;
begin
  d := TyBuildInputDialog(ACaption, APrompt, ADefault, e);
  mr := d.ShowModal;
  Result := TyInputResult(e, ADefault, mr);
  d.Free;
end;

function TyInputQuery(const ACaption, APrompt: string; var AValue: string): Boolean;
var d: TTyDialog; e: TTyEdit; mr: TModalResult;
begin
  d := TyBuildInputDialog(ACaption, APrompt, AValue, e);
  mr := d.ShowModal;
  Result := (mr = mrOk);
  if Result then AValue := e.Text;
  d.Free;
end;

function TTyInputDialog.Execute: Boolean;
begin Result := TyInputQuery(FCaption, FPrompt, FValue); end;
```
(Note: `rsMsgBtnOK`/`rsMsgBtnCancel` come from `tyControls.StrConsts` — already in `uses` from S1's Task-6 i18n. Verify; add if missing.)

- [ ] **Step 4: Run, verify pass.** Expected run 1568 (+2), failures 0, errors 11. Build lib exit 0.

- [ ] **Step 5: Commit.**
```bash
git add source/tyControls.Dialogs.pas tests/test.dialogs.pas
git commit -m "$(printf 'feat(dialogs): TyInputDialog — TyInputQuery/TyInputBox globals + TTyInputDialog component\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 3: `TyPasswordDialog` (masked-edit delta on Input)

**Files:** Modify `source/tyControls.Dialogs.pas`; Test `tests/test.dialogs.pas`.

- [ ] **Step 1: Write the failing test.** Add:
```pascal
  TPasswordDialogTest = class(TTestCase)
  published
    procedure TestBuildMasksEdit;
  end;
```
Impl:
```pascal
procedure TPasswordDialogTest.TestBuildMasksEdit;
var d: TTyDialog; e: TTyEdit;
begin
  d := TyBuildPasswordDialog('Login', 'Password:', '●', e);
  try
    AssertTrue('edit created', e <> nil);
    AssertEquals('masked', '●', e.PasswordChar);
    AssertEquals('two buttons', 2, TyDialogButtonCount(d));
  finally d.Free; end;
end;
```
Add `RegisterTest(TPasswordDialogTest);`.

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement.** Interface:
```pascal
const TyDefaultPasswordChar = '●';
function TyBuildPasswordDialog(const ACaption, APrompt, APasswordChar: string; out AEdit: TTyEdit): TTyDialog;
function TyPasswordBox(const ACaption, APrompt: string): string;
function TyPasswordQuery(const ACaption, APrompt: string; var AValue: string): Boolean;
type
  TTyPasswordDialog = class(TComponent)
  private
    FCaption, FPrompt, FValue, FPasswordChar: string;
  public
    constructor Create(AOwner: TComponent); override;
    function Execute: Boolean;
  published
    property Caption: string read FCaption write FCaption;
    property Prompt: string read FPrompt write FPrompt;
    property Value: string read FValue write FValue;
    property PasswordChar: string read FPasswordChar write FPasswordChar;
  end;
```
Implementation (reuses `TyPlacePrompt`):
```pascal
function TyBuildPasswordDialog(const ACaption, APrompt, APasswordChar: string; out AEdit: TTyEdit): TTyDialog;
var y: Integer;
begin
  Result := TTyDialog.CreateNew(Application);
  Result.Caption := ACaption;
  y := TyPlacePrompt(Result, APrompt, TyDlgEditW);
  AEdit := TTyEdit.Create(Result);
  AEdit.Parent := Result;
  AEdit.PasswordChar := APasswordChar;
  AEdit.SetBounds(TyDlgPad, y, TyDlgEditW, TyDlgEditH);
  Result.AddButton(rsMsgBtnOK, mrOk, True, False);
  Result.AddButton(rsMsgBtnCancel, mrCancel, False, True);
  Result.AutoSizeToContent(TyDlgEditW + TyDlgPad, y + TyDlgEditH + TyDlgPad - Result.ContentRect.Top);
end;

function TyPasswordBox(const ACaption, APrompt: string): string;
var d: TTyDialog; e: TTyEdit; mr: TModalResult;
begin
  d := TyBuildPasswordDialog(ACaption, APrompt, TyDefaultPasswordChar, e);
  mr := d.ShowModal;
  if mr = mrOk then Result := e.Text else Result := '';
  d.Free;
end;

function TyPasswordQuery(const ACaption, APrompt: string; var AValue: string): Boolean;
var d: TTyDialog; e: TTyEdit; mr: TModalResult;
begin
  d := TyBuildPasswordDialog(ACaption, APrompt, TyDefaultPasswordChar, e);
  mr := d.ShowModal;
  Result := (mr = mrOk);
  if Result then AValue := e.Text;
  d.Free;
end;

constructor TTyPasswordDialog.Create(AOwner: TComponent);
begin inherited Create(AOwner); FPasswordChar := TyDefaultPasswordChar; end;

function TTyPasswordDialog.Execute: Boolean;
var d: TTyDialog; e: TTyEdit; mr: TModalResult;
begin
  d := TyBuildPasswordDialog(FCaption, FPrompt, FPasswordChar, e);
  mr := d.ShowModal;
  Result := (mr = mrOk);
  if Result then FValue := e.Text;
  d.Free;
end;
```

- [ ] **Step 4: Run, verify pass.** Expected run 1569 (+1), failures 0, errors 11.

- [ ] **Step 5: Commit.**
```bash
git add source/tyControls.Dialogs.pas tests/test.dialogs.pas
git commit -m "$(printf 'feat(dialogs): TyPasswordDialog — TyPasswordBox/TyPasswordQuery + TTyPasswordDialog (masked edit)\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 4: `TyTextDialog` (RESIZABLE, multi-line memo)

**Files:** Modify `source/tyControls.Dialogs.pas`; Test `tests/test.dialogs.pas`.

- [ ] **Step 1: Write the failing test.** Add:
```pascal
  TTextDialogTest = class(TTestCase)
  published
    procedure TestBuildSeedsMemoResizable;
    procedure TestMemoReflowsOnResize;
  end;
```
Impl:
```pascal
procedure TTextDialogTest.TestBuildSeedsMemoResizable;
var d: TTyTextDialogForm; m: TTyMemo;
begin
  d := TyBuildTextDialog('Notes', 'Enter notes:', 'line1' + LineEnding + 'line2', m);
  try
    AssertTrue('memo created', m <> nil);
    AssertEquals('memo seeded', 'line1' + LineEnding + 'line2', m.Text);
    AssertTrue('resizable', d.Resizable);
    AssertEquals('two buttons', 2, TyDialogButtonCount(d));
  finally d.Free; end;
end;

procedure TTextDialogTest.TestMemoReflowsOnResize;
var d: TTyTextDialogForm; m: TTyMemo; w0: Integer;
begin
  d := TyBuildTextDialog('T', 'p', '', m);
  try
    d.LayoutContent; w0 := m.Width;
    d.ClientWidth := d.ClientWidth + 100;
    d.LayoutContent;
    AssertTrue('memo widened', m.Width > w0);
  finally d.Free; end;
end;
```
Add `RegisterTest(TTextDialogTest);`. Add `tyControls.Memo` to the test `uses`.

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement.** The Text dialog needs a dedicated `TTyDialog` subclass so `LayoutContent` can stretch the memo. Add `tyControls.Memo` to the interface `uses`. Interface:
```pascal
type
  TTyTextDialogForm = class(TTyDialog)   // the resizable text-input dialog window
  private
    FMemo: TTyMemo;
    FPromptBottom: Integer;   // y where the memo starts (below prompt)
  protected
    procedure LayoutContent; override;
  public
    property Memo: TTyMemo read FMemo;
  end;
function TyBuildTextDialog(const ACaption, APrompt, ADefault: string; out AMemo: TTyMemo): TTyTextDialogForm;
function TyTextQuery(const ACaption, APrompt: string; var AValue: string): Boolean;
type
  TTyTextDialog = class(TComponent)
  private
    FCaption, FPrompt, FValue: string;
  public
    function Execute: Boolean;
  published
    property Caption: string read FCaption write FCaption;
    property Prompt: string read FPrompt write FPrompt;
    property Value: string read FValue write FValue;
  end;
```
Implementation:
```pascal
procedure TTyTextDialogForm.LayoutContent;
var r: TRect;
begin
  if FMemo = nil then Exit;
  r := ContentRect;
  FMemo.SetBounds(r.Left + TyDlgPad, FPromptBottom,
    (r.Right - r.Left) - 2*TyDlgPad, r.Bottom - FPromptBottom - TyDlgPad);
end;

function TyBuildTextDialog(const ACaption, APrompt, ADefault: string; out AMemo: TTyMemo): TTyTextDialogForm;
var y: Integer;
begin
  Result := TTyTextDialogForm.CreateNew(Application);
  Result.Resizable := True;
  Result.Caption := ACaption;
  Result.Constraints.MinWidth := 320;
  Result.Constraints.MinHeight := 220;
  y := TyPlacePrompt(Result, APrompt, 380);
  Result.FPromptBottom := y;
  AMemo := TTyMemo.Create(Result);
  AMemo.Parent := Result;
  AMemo.Text := ADefault;
  Result.FMemo := AMemo;
  Result.AddButton(rsMsgBtnOK, mrOk, True, False);
  Result.AddButton(rsMsgBtnCancel, mrCancel, False, True);
  Result.AutoSizeToContent(420, 260 - (Result.ContentRect.Top));  // roomy default
  Result.LayoutContent;   // place the memo into the content area
end;

function TyTextQuery(const ACaption, APrompt: string; var AValue: string): Boolean;
var d: TTyTextDialogForm; m: TTyMemo; mr: TModalResult;
begin
  d := TyBuildTextDialog(ACaption, APrompt, AValue, m);
  mr := d.ShowModal;
  Result := (mr = mrOk);
  if Result then AValue := m.Text;
  d.Free;
end;

function TTyTextDialog.Execute: Boolean;
begin Result := TyTextQuery(FCaption, FPrompt, FValue); end;
```
Notes for the implementer: `AutoSizeToContent`'s exact height math is approximate — the goal is a roomy initial size; `LayoutContent` is what actually positions the memo, and it re-runs on resize. If `Constraints`/`MinWidth` aren't on `TTyForm`, they're inherited from LCL `TControl` — verify they compile.

- [ ] **Step 4: Run, verify pass.** Expected run 1571 (+2), failures 0, errors 11.

- [ ] **Step 5: Commit.**
```bash
git add source/tyControls.Dialogs.pas tests/test.dialogs.pas
git commit -m "$(printf 'feat(dialogs): TyTextDialog — resizable multi-line TyTextQuery + TTyTextDialog\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 5: `TySelectValueDialog` (single-select listbox)

**Files:** Modify `source/tyControls.Dialogs.pas`; Test `tests/test.dialogs.pas`.

- [ ] **Step 1: Write the failing test.** Add:
```pascal
  TSelectValueTest = class(TTestCase)
  published
    procedure TestBuildSeedsListAndSelection;
    procedure TestResultIndexLogic;
  end;
```
Impl:
```pascal
procedure TSelectValueTest.TestBuildSeedsListAndSelection;
var d: TTyDialog; lb: TTyListBox; items: TStringList;
begin
  items := TStringList.Create;
  try
    items.Add('Red'); items.Add('Green'); items.Add('Blue');
    d := TyBuildSelectValueDialog('Pick', 'Colour:', items, 1, lb);
    try
      AssertTrue('list created', lb <> nil);
      AssertEquals('items copied', 3, lb.Items.Count);
      AssertEquals('seeded selection', 1, lb.ItemIndex);
    finally d.Free; end;
  finally items.Free; end;
end;

procedure TSelectValueTest.TestResultIndexLogic;
var d: TTyDialog; lb: TTyListBox; items: TStringList;
begin
  items := TStringList.Create;
  try
    items.Add('A'); items.Add('B');
    d := TyBuildSelectValueDialog('X', 'p', items, 0, lb);
    try
      lb.ItemIndex := 1;
      AssertEquals('ok -> chosen', 1, TySelectValueResult(lb, 0, mrOk));
      AssertEquals('cancel -> initial', 0, TySelectValueResult(lb, 0, mrCancel));
    finally d.Free; end;
  finally items.Free; end;
end;
```
Add `RegisterTest(TSelectValueTest);`. Add `tyControls.ListBox` to the test `uses`.

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement.** Add `tyControls.ListBox` to the interface `uses`. Interface:
```pascal
function TyBuildSelectValueDialog(const ACaption, APrompt: string; AItems: TStrings; AInitialIndex: Integer; out AList: TTyListBox): TTyDialog;
function TySelectValueResult(AList: TTyListBox; AInitialIndex: Integer; AResult: TModalResult): Integer;
function TySelectValue(const ACaption, APrompt: string; AItems: TStrings; var AIndex: Integer): Boolean;
type
  TTySelectValueDialog = class(TComponent)
  private
    FCaption, FPrompt: string;
    FItems: TStrings;
    FItemIndex: Integer;
    procedure SetItems(AValue: TStrings);
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function Execute: Boolean;
    function SelectedText: string;
  published
    property Caption: string read FCaption write FCaption;
    property Prompt: string read FPrompt write FPrompt;
    property Items: TStrings read FItems write SetItems;
    property ItemIndex: Integer read FItemIndex write FItemIndex default -1;
  end;
```
Implementation:
```pascal
function TyBuildSelectValueDialog(const ACaption, APrompt: string; AItems: TStrings; AInitialIndex: Integer; out AList: TTyListBox): TTyDialog;
var y, listH: Integer; r: TRect;
begin
  Result := TTyDialog.CreateNew(Application);
  Result.Caption := ACaption;
  y := TyPlacePrompt(Result, APrompt, TyDlgEditW);
  AList := TTyListBox.Create(Result);
  AList.Parent := Result;
  if AItems <> nil then AList.Items.Assign(AItems);
  if (AInitialIndex >= 0) and (AInitialIndex < AList.Items.Count) then
    AList.ItemIndex := AInitialIndex;
  listH := 160;
  AList.SetBounds(TyDlgPad, y, TyDlgEditW, listH);
  // double-click a row confirms
  AList.OnDblClick := @TyDlgListDblClickOK;   // shared handler, sets ModalResult := mrOk
  Result.AddButton(rsMsgBtnOK, mrOk, True, False);
  Result.AddButton(rsMsgBtnCancel, mrCancel, False, True);
  r := Result.ContentRect;
  Result.AutoSizeToContent(TyDlgEditW + TyDlgPad, y + listH + TyDlgPad - r.Top);
end;

function TySelectValueResult(AList: TTyListBox; AInitialIndex: Integer; AResult: TModalResult): Integer;
begin
  if AResult = mrOk then Result := AList.ItemIndex else Result := AInitialIndex;
end;

function TySelectValue(const ACaption, APrompt: string; AItems: TStrings; var AIndex: Integer): Boolean;
var d: TTyDialog; lb: TTyListBox; mr: TModalResult;
begin
  d := TyBuildSelectValueDialog(ACaption, APrompt, AItems, AIndex, lb);
  mr := d.ShowModal;
  Result := (mr = mrOk);
  if Result then AIndex := lb.ItemIndex;
  d.Free;
end;
```
`TyDlgListDblClickOK` is a unit-level handler that needs the dialog. Since `OnDblClick` is `TNotifyEvent(Sender: TObject)` and `Sender` is the listbox, walk to its parent form:
```pascal
procedure TyDlgListDblClickOK(Sender: TObject);
var f: TCustomForm;
begin
  f := GetParentForm(TControl(Sender));
  if (f <> nil) and (TTyListBox(Sender).ItemIndex >= 0) then f.ModalResult := mrOk;
end;
```
(`TyDlgListDblClickOK` must be a plain `procedure`, not a method — assign with `@`. Verify `GetParentForm` is reachable via `Forms` in uses; it is.)
Component impl:
```pascal
constructor TTySelectValueDialog.Create(AOwner: TComponent);
begin inherited Create(AOwner); FItems := TStringList.Create; FItemIndex := -1; end;
destructor TTySelectValueDialog.Destroy;
begin FItems.Free; inherited Destroy; end;
procedure TTySelectValueDialog.SetItems(AValue: TStrings);
begin FItems.Assign(AValue); end;
function TTySelectValueDialog.SelectedText: string;
begin
  if (FItemIndex >= 0) and (FItemIndex < FItems.Count) then Result := FItems[FItemIndex] else Result := '';
end;
function TTySelectValueDialog.Execute: Boolean;
begin Result := TySelectValue(FCaption, FPrompt, FItems, FItemIndex); end;
```

- [ ] **Step 4: Run, verify pass.** Expected run 1573 (+2), failures 0, errors 11. Build lib exit 0.

- [ ] **Step 5: Commit.**
```bash
git add source/tyControls.Dialogs.pas tests/test.dialogs.pas
git commit -m "$(printf 'feat(dialogs): TySelectValueDialog — TySelectValue list picker + TTySelectValueDialog\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 6: SelectPath filesystem helpers (new unit, pure/testable)

**Files:** Create `source/tyControls.Dialogs.SelectPath.pas`; add to `tycontrols.lpk`; Create `tests/test.dialogs.selectpath.pas`; add to `tests/tytests.lpr`.

- [ ] **Step 1: Write the failing test.** Create `tests/test.dialogs.selectpath.pas`:
```pascal
unit test.dialogs.selectpath;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.Dialogs.SelectPath;
type
  TSelectPathFsTest = class(TTestCase)
  private
    FRoot: string;
    procedure MakeTree;
  published
    procedure TestSubdirectoriesSortedFilesExcluded;
    procedure TestPathHasSubdir;
  end;
implementation

procedure TSelectPathFsTest.MakeTree;
begin
  FRoot := IncludeTrailingPathDelimiter(GetTempDir) + 'tyselpath_' + IntToStr(PtrUInt(Self));
  ForceDirectories(FRoot + PathDelim + 'beta');
  ForceDirectories(FRoot + PathDelim + 'alpha' + PathDelim + 'child');
  with TStringList.Create do try Add('x'); SaveToFile(FRoot + PathDelim + 'note.txt'); finally Free; end;
end;

procedure TSelectPathFsTest.TestSubdirectoriesSortedFilesExcluded;
var a: TStringArray;
begin
  MakeTree;
  try
    a := TySubdirectories(FRoot);
    AssertEquals('two subdirs', 2, Length(a));
    AssertEquals('sorted 0', 'alpha', a[0]);
    AssertEquals('sorted 1', 'beta', a[1]);   // file 'note.txt' excluded
  finally RemoveDir(FRoot + PathDelim + 'alpha' + PathDelim + 'child');
    RemoveDir(FRoot + PathDelim + 'alpha'); RemoveDir(FRoot + PathDelim + 'beta');
    DeleteFile(FRoot + PathDelim + 'note.txt'); RemoveDir(FRoot); end;
end;

procedure TSelectPathFsTest.TestPathHasSubdir;
begin
  MakeTree;
  try
    AssertTrue('root has subdir', TyPathHasSubdir(FRoot));
    AssertTrue('alpha has child', TyPathHasSubdir(FRoot + PathDelim + 'alpha'));
    AssertFalse('beta empty', TyPathHasSubdir(FRoot + PathDelim + 'beta'));
  finally RemoveDir(FRoot + PathDelim + 'alpha' + PathDelim + 'child');
    RemoveDir(FRoot + PathDelim + 'alpha'); RemoveDir(FRoot + PathDelim + 'beta');
    DeleteFile(FRoot + PathDelim + 'note.txt'); RemoveDir(FRoot); end;
end;

initialization
  RegisterTest(TSelectPathFsTest);
end.
```
Create `source/tyControls.Dialogs.SelectPath.pas` with just the helper signatures + stub bodies (so it compiles + tests fail):
```pascal
unit tyControls.Dialogs.SelectPath;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils;
function TySubdirectories(const APath: string): TStringArray;
function TyPathHasSubdir(const APath: string): Boolean;
function TyDriveRoots: TStringArray;
implementation
function TySubdirectories(const APath: string): TStringArray; begin Result := nil; end;
function TyPathHasSubdir(const APath: string): Boolean; begin Result := False; end;
function TyDriveRoots: TStringArray; begin Result := nil; end;
end.
```
Add the unit to `tycontrols.lpk` (copy an existing runtime `<Item>`, set `Filename`/`UnitName` to `source/tyControls.Dialogs.SelectPath.pas` / `tyControls.Dialogs.SelectPath`). Add `test.dialogs.selectpath` to `tests/tytests.lpr` uses.

- [ ] **Step 2: Run, verify fail** (4 asserts fail).

- [ ] **Step 3: Implement the helpers:**
```pascal
function TySubdirectories(const APath: string): TStringArray;
var sr: TSearchRec; list: TStringList; base: string;
begin
  list := TStringList.Create;
  try
    list.Sort; list.CaseSensitive := False;
    base := IncludeTrailingPathDelimiter(APath);
    if FindFirst(base + '*', faDirectory, sr) = 0 then
    try
      repeat
        if ((sr.Attr and faDirectory) <> 0) and (sr.Name <> '.') and (sr.Name <> '..')
           {$IFDEF UNIX} and (sr.Name = '') = False {$ENDIF} then
          list.Add(sr.Name);
      until FindNext(sr) <> 0;
    finally FindClose(sr); end;
    list.Sort;
    Result := list.ToStringArray;   // FPC 3.2+; else copy manually
  finally list.Free; end;
end;

function TyPathHasSubdir(const APath: string): Boolean;
begin
  Result := Length(TySubdirectories(APath)) > 0;
end;

function TyDriveRoots: TStringArray;
{$IFDEF MSWINDOWS}
var c: Char; n: Integer;
begin
  SetLength(Result, 0); n := 0;
  for c := 'A' to 'Z' do
    if DirectoryExists(c + ':\') then begin SetLength(Result, n+1); Result[n] := c + ':\'; Inc(n); end;
end;
{$ELSE}
begin
  SetLength(Result, 1); Result[0] := '/';
end;
{$ENDIF}
```
(If `TStringList.ToStringArray` is unavailable in the target FPC, replace with a manual `SetLength(Result, list.Count)` + copy loop — the implementer verifies and adapts. `list.Sort` gives case-insensitive-when-`CaseSensitive:=False` ordering.)

- [ ] **Step 4: Run, verify pass.** Expected run 1575 (+2), failures 0, errors 11. Lib exit 0.

- [ ] **Step 5: Commit.**
```bash
git add source/tyControls.Dialogs.SelectPath.pas tests/test.dialogs.selectpath.pas tycontrols.lpk tests/tytests.lpr
git commit -m "$(printf 'feat(dialogs): SelectPath filesystem helpers (TySubdirectories/TyPathHasSubdir/TyDriveRoots)\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 7: `TySelectPathDialog` — directory-tree folder picker (INTEGRATION)

**Files:** Modify `source/tyControls.Dialogs.SelectPath.pas`; Test `tests/test.dialogs.selectpath.pas`. Add resourcestrings for "New Folder".

**This is the one integration-heavy task: wiring `TTyTreeView`'s lazy callbacks. The plan gives the exact structure + API facts + a construct-only test gate. The implementer MUST wire the lazy callbacks against the live `tyControls.TreeView` API and make the gate test pass — do NOT assume the callback sequence compiles without checking the tree source.**

- [ ] **Step 1: Write the failing (construct-only) test.** Add to `tests/test.dialogs.selectpath.pas`:
```pascal
  TSelectPathBuildTest = class(TTestCase)
  published
    procedure TestBuildRootedTreeHasButtons;
  end;
```
Impl (build against a temp dir; assert structure, no ShowModal):
```pascal
procedure TSelectPathBuildTest.TestBuildRootedTreeHasButtons;
var d: TTySelectPathForm; root: string;
begin
  root := IncludeTrailingPathDelimiter(GetTempDir) + 'tyselpath_build';
  ForceDirectories(root + PathDelim + 'sub');
  try
    d := TyBuildSelectPathDialog('Choose folder', root);
    try
      AssertTrue('tree created', d.Tree <> nil);
      AssertTrue('resizable', d.Resizable);
      AssertTrue('at least 3 buttons (New Folder + OK + Cancel)', TyDialogButtonCount(d) >= 3);
    finally d.Free; end;
  finally RemoveDir(root + PathDelim + 'sub'); RemoveDir(root); end;
end;
```
Add `RegisterTest(TSelectPathBuildTest);` and `tyControls.Dialogs, tyControls.TreeView` to the test `uses` (for `TyDialogButtonCount`, `TTySelectPathForm`).

- [ ] **Step 2: Run, verify fail** (`TTySelectPathForm`/`TyBuildSelectPathDialog` undefined).

- [ ] **Step 3: Implement.** In `source/tyControls.Dialogs.SelectPath.pas`:
  - Add to `uses`: `Forms, tyControls.Dialogs, tyControls.TreeView, tyControls.StrConsts`.
  - Add resourcestrings (Task 9 moves the pattern; declare here now):
    `resourcestring rsDlgNewFolder = 'New Folder'; rsDlgNewFolderPrompt = 'Folder name:';`
    (These go into `tyControls.StrConsts` in Task 9; for now declare them locally OR — cleaner — add them to StrConsts now and `uses` it. Prefer adding to StrConsts now to avoid a move later.)
  - Declare the dialog window subclass + API:
```pascal
type
  TTySelectPathForm = class(TTyDialog)
  private
    FTree: TTyTreeView;
    FPaths: TStringList;                 // node-data index -> absolute path
    FRoot: string;
    procedure TreeGetText(Sender: TTyTreeView; Node: PTyTreeNode; var AText: string);
    procedure TreeInitChildren(Sender: TTyTreeView; Node: PTyTreeNode; var ChildCount: Cardinal);
    procedure TreeInitNode(Sender: TTyTreeView; ParentNode, Node: PTyTreeNode; var InitStates: TTyNodeInitStates);
    procedure NewFolderClick(Sender: TObject);
    function NodePath(Node: PTyTreeNode): string;
    function AddPathNode(AParent: PTyTreeNode; const AFullPath: string): PTyTreeNode;
    procedure PopulateRoots;
  protected
    procedure LayoutContent; override;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    destructor Destroy; override;
    property Tree: TTyTreeView read FTree;
    function SelectedPath: string;
  end;
function TyBuildSelectPathDialog(const ACaption, ARoot: string): TTySelectPathForm;
function TySelectDirectory(const ACaption, ARoot: string; var ADir: string): Boolean;
type
  TTySelectPathDialog = class(TComponent)
  private
    FCaption, FRoot, FDirectory: string;
  public
    function Execute: Boolean;
  published
    property Caption: string read FCaption write FCaption;
    property Root: string read FRoot write FRoot;
    property Directory: string read FDirectory write FDirectory;
  end;
```
  - **Node-data scheme** (avoids managed-memory-in-raw-node-data): `SetNodeDataSize(SizeOf(Integer))`; each node stores an index into `FPaths`. `AddPathNode` adds a node and stores `FPaths.Add(fullpath)` as its data:
```pascal
function TTySelectPathForm.AddPathNode(AParent: PTyTreeNode; const AFullPath: string): PTyTreeNode;
begin
  Result := FTree.AddChild(AParent);
  PInteger(FTree.GetNodeData(Result))^ := FPaths.Add(AFullPath);
end;

function TTySelectPathForm.NodePath(Node: PTyTreeNode): string;
begin
  if Node = nil then Result := '' else Result := FPaths[PInteger(FTree.GetNodeData(Node))^];
end;

procedure TTySelectPathForm.TreeGetText(Sender: TTyTreeView; Node: PTyTreeNode; var AText: string);
var p: string;
begin
  p := NodePath(Node);
  AText := ExtractFileName(ExcludeTrailingPathDelimiter(p));
  if AText = '' then AText := p;   // drive root like 'C:\' -> show as-is
end;
```
  - **Lazy population** — the exact wiring depends on the tree's InitChildren/InitNode contract; the RECOMMENDED structure (verify against `tyControls.TreeView` and adjust):
    - `CreateNew`: create `FPaths`; create `FTree` (parented, filling content); `FTree.SetNodeDataSize(SizeOf(Integer))`; assign `OnGetText`/`OnInitChildren`/`OnInitNode`; `Resizable := True`; add the **New Folder** button (`AddButton(rsDlgNewFolder, mrNone)` and set its `OnClick := @NewFolderClick` so it does NOT close the dialog — check that an `mrNone` button leaves the dialog open) + `AddButton(rsMsgBtnOK, mrOk, True)` + `AddButton(rsMsgBtnCancel, mrCancel, False, True)`.
    - `PopulateRoots`: if `FRoot <> ''` and `DirectoryExists(FRoot)` → `AddPathNode(nil, FRoot)`; else for each `TyDriveRoots` → `AddPathNode(nil, drive)`. After adding a root, if `TyPathHasSubdir(path)` mark it expandable (either by including `ivsHasChildren` when that node inits, or the tree's API for setting has-children).
    - `TreeInitNode`: when a node is (re)initialized, `if TyPathHasSubdir(NodePath(Node)) then Include(InitStates, ivsHasChildren);` — so the expand arrow shows without loading children.
    - `TreeInitChildren`: `subs := TySubdirectories(NodePath(Node)); ChildCount := Length(subs);` then materialize — **HOW children get their path depends on the tree's model**: if the tree calls `OnInitNode` per allocated child with the child `Node` and its `Node^.Index`, set that child's data there via `AddPathNode`-equivalent using `NodePath(ParentNode) + subs[Node^.Index]`. If instead you must `AddChild` imperatively inside `OnInitChildren`, do that and set `ChildCount` to 0. **Pick whichever the tree actually supports; the gate is: expanding a node shows its subdirectories with correct names.** (Add a follow-up integration test for expand if feasible without a handle; otherwise this is GUI-verified — note it.)
  - `NewFolderClick`: 
```pascal
procedure TTySelectPathForm.NewFolderClick(Sender: TObject);
var parent: PTyTreeNode; base, name, full: string;
begin
  parent := FTree.FocusedNode;
  if parent = nil then Exit;
  base := IncludeTrailingPathDelimiter(NodePath(parent));
  name := '';
  if TyInputQuery(rsDlgNewFolder, rsDlgNewFolderPrompt, name) and (name <> '') then
  begin
    full := base + name;
    if CreateDir(full) then
    begin
      // re-init the parent's children so the new folder shows, then select it
      FTree.ReInitNode(parent);   // or the tree's re-init API; verify name
    end
    else
      TyMessageDlg('Could not create folder: ' + full, mtError, [mbOK]);
  end;
end;
```
    (`TyInputQuery`/`TyMessageDlg` come from `tyControls.Dialogs` — reuse. Verify the tree's re-init method name; if none, remove+repopulate the node's children.)
  - `LayoutContent`: stretch `FTree` to `ContentRect` (minus padding), same shape as `TTyTextDialogForm.LayoutContent`.
  - `SelectedPath`: `Result := NodePath(FTree.FocusedNode);`
  - `TyBuildSelectPathDialog`: `Result := TTySelectPathForm.CreateNew(Application); Result.Caption := ACaption; Result.FRoot := ARoot; Result.PopulateRoots; Result.AutoSizeToContent(360, 420 - Result.ContentRect.Top); Result.LayoutContent;`
  - `TySelectDirectory`: build → `ShowModal` → if `mrOk` write `ADir := d.SelectedPath` → Free.
  - `TTySelectPathDialog.Execute`: `Result := TySelectDirectory(FCaption, FRoot, FDirectory);`

- [ ] **Step 4: Run, verify pass** (the construct-only build test). Expected run 1576 (+1), failures 0, errors 11. Lib exit 0. **If the lazy-callback wiring can't be fully exercised headlessly, the construct-only test (tree exists + buttons present) is the gate; note the expand/populate path as GUI-verified.**

- [ ] **Step 5: Commit.**
```bash
git add source/tyControls.Dialogs.SelectPath.pas tests/test.dialogs.selectpath.pas source/tyControls.StrConsts.pas
git commit -m "$(printf 'feat(dialogs): TySelectPathDialog — lazy directory-tree folder picker + New Folder\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 8: Design-time registration (5 components)

**Files:** Modify `designtime/tyControls.Design.pas`; `tycontrols_dt.lpk` (if the SelectPath unit needs adding).

- [ ] **Step 1: Register.** In `Register` (Design.pas), change the S1 line
`RegisterComponents('TyControls Dialogs', [TTyMessage]);` to include the five new ones:
```pascal
  RegisterComponents('TyControls Dialogs',
    [TTyMessage, TTyInputDialog, TTyPasswordDialog, TTyTextDialog,
     TTySelectValueDialog, TTySelectPathDialog]);
```
Add `tyControls.Dialogs.SelectPath` to the `uses` clause of `tyControls.Design.pas` (for `TTySelectPathDialog`). Ensure `tycontrols_dt.lpk` references the runtime package (it does) so the new unit is visible; no dt-package item change is needed if the component comes from the runtime package (it does).

- [ ] **Step 2: Build the dt package.**
Run: `lazbuild tycontrols_dt.lpk 2>&1 | grep -iE "error|fatal"; echo exit ${PIPESTATUS[0]}`
Expected: exit 0. Also confirm runtime suite unchanged (Design.pas isn't in the test build): 1576/0/11.

- [ ] **Step 3: Commit.**
```bash
git add designtime/tyControls.Design.pas
git commit -m "$(printf 'feat(design): register the S2 input dialogs in the TyControls Dialogs palette\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

---

### Task 9: i18n + docs + README + final verify

**Files:** `source/tyControls.StrConsts.pas`, `languages/*`, `docs/controls/dialogs.md`, `README.md`, `README.en.md`.

- [ ] **Step 1: Resourcestrings.** Ensure the built-in strings live in `tyControls.StrConsts.pas` (if Task 7 declared `rsDlgNewFolder`/`rsDlgNewFolderPrompt` locally, MOVE them here and `uses tyControls.StrConsts`):
```pascal
  // --- Input-family dialogs (built-in text) ---
  rsDlgNewFolder       = 'New Folder';
  rsDlgNewFolderPrompt = 'Folder name:';
  rsDlgCreateFolderErr = 'Could not create folder: %s';
```
Update the SelectPath error message to `Format(rsDlgCreateFolderErr, [full])`.

- [ ] **Step 2: Regenerate .pot + zh_CN .po.** Build the runtime + dt packages (auto-regenerates `languages/tyControls.StrConsts.pot`). Add zh_CN entries to `languages/tycontrols.strconsts.zh_CN.po` (match existing format; keys `tycontrols.strconsts.rsdlgnewfolder` etc.):
```
#: tycontrols.strconsts.rsdlgnewfolder
msgid "New Folder"
msgstr "新建文件夹"

#: tycontrols.strconsts.rsdlgnewfolderprompt
msgid "Folder name:"
msgstr "文件夹名称："

#: tycontrols.strconsts.rsdlgcreatefoldererr
#, object-pascal-format
msgid "Could not create folder: %s"
msgstr "无法创建文件夹：%s"
```

- [ ] **Step 3: Docs.** Extend `docs/controls/dialogs.md` with an "输入类对话框" section: `TyInputQuery`/`TyInputBox`, `TyPasswordBox`/`TyPasswordQuery`, `TyTextQuery` (resizable), `TySelectValue`, `TySelectDirectory` (folder picker with New Folder), + the five components; a short code example each. Match the existing file's Chinese style.

- [ ] **Step 4: README.** Add the input dialogs to the existing "Dialogs / 对话框" entry in `README.md` + `README.en.md` (extend, don't duplicate the S1 bullet).

- [ ] **Step 5: Final sweep.**
```bash
lazbuild tycontrols.lpk 2>&1 | grep -iE "error|fatal"; echo lib ${PIPESTATUS[0]}
lazbuild tycontrols_dt.lpk 2>&1 | grep -iE "error|fatal"; echo dt ${PIPESTATUS[0]}
lazbuild tests/tytests.lpi >/dev/null 2>&1 && ./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)"
```
Expected: lib/dt exit 0; failures 0; errors 11; run ~1576.

- [ ] **Step 6: Commit.**
```bash
git add source/tyControls.StrConsts.pas languages/ docs/controls/dialogs.md README.md README.en.md
git commit -m "$(printf 'docs+i18n(dialogs): S2 input family — docs, README, resourcestrings + zh_CN\n\nCo-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>')"
```

- [ ] **Step 7: Finish the branch.** Use superpowers:finishing-a-development-branch (run the pre-merge checklist: i18n done here; README done here). Then a final whole-branch adversarial review before merge.

---

## Notes for the implementer
- **Resourcestrings first.** Button captions reuse `rsMsgBtnOK`/`rsMsgBtnCancel` (S1). New built-in text ('New Folder' etc.) → `tyControls.StrConsts` (Task 9). Caller-supplied caption/prompt text is NOT translated (it's the app's).
- **Never `ShowModal`/`SetDesigning` in tests** (S1 lessons). Builders take `Application` as owner; tests `Free` explicitly.
- **`out` params** (`AEdit`/`AMemo`/`AList`) let the construct-only builders hand the embedded widget back for assertions without exposing internals.
- **Task 7 is integration work.** The tree's lazy-callback contract (InitChildren/InitNode/per-child materialization) must be wired against the live `tyControls.TreeView` source; the construct-only test is the compile+structure gate, and the expand/populate + New Folder refresh are GUI-verified (note them for the real-machine eyeball, like S1's icon paint).
- **Resizable dialogs** set `Resizable := True` + keep `BorderIcons = [biSystemMenu]` (edge-resize, no max button) and override `LayoutContent`.
- **Baseline** 1564/0/11; each task's expected run count is cumulative (+2/+2/+1/+2/+2/+2/+1 = ~1576). Keep failures 0, errors 11.
