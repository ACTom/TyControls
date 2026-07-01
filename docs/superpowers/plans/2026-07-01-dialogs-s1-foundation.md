# Dialogs S1 Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A custom-drawn modal-dialog foundation: `TTyDialog` base + a build/show-separated builder + the `TyMessage` dialog (global `TyShowMessage`/`TyMessageDlg` + `TTyMessage` component) + IDE "TyControls Dialog" New-item + a "TyControls Dialogs" palette group.

**Architecture:** New unit `source/tyControls.Dialogs.pas`. `TTyDialog = class(TTyForm)` (P1 chrome: borderless, close-only, non-resizable, centered), with a content area + a bottom button bar (`AddButton` → `TTyButton`s whose `Tag` holds a `TModalResult`; one shared OnClick sets the dialog's `ModalResult`; Enter/Esc fire the default/cancel buttons via `KeyPreview`). Pure functions (`TyDialogButtonBar`, the `TyMsg*` mappings) carry the testable logic; a construct-only builder lets tests inspect a built dialog without the blocking `ShowModal`.

**Tech Stack:** Lazarus/FPC, LCL (`TModalResult`, `TMsgDlgType`/`TMsgDlgButtons` from `Controls`/`Dialogs`), `tyControls.Form` (P1), `tyControls.Button`, `tyControls.TyLabel`, `tyControls.Painter`, `tyControls.Base`. Headless fpcunit.

**Branch:** `feat/dialogs-s1` (checked out). **Spec:** `docs/superpowers/specs/2026-07-01-dialogs-s1-foundation-design.md`.

**Build/test (git-bash, from repo root):**
- Lib: `lazbuild tycontrols.lpk 2>&1 | grep -iE "error|fatal"; echo exit ${PIPESTATUS[0]}`
- DT: `lazbuild tycontrols_dt.lpk 2>&1 | grep -iE "error|fatal"; echo exit ${PIPESTATUS[0]}`
- Tests: `lazbuild tests/tytests.lpi >/dev/null 2>&1 && ./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)"`
- **Baseline: 1549 run / 0 failures / 11 errors** (post-P1-merge). Keep failures 0, errors 11.

**Refinement vs spec:** message-type icons are drawn as a **filled circle in a semantic color + a symbol glyph char** in the dialog unit (legible for all four incl. "?"), rather than adding line-art kinds to `TTyGlyphKind`. Painter is untouched. Everything else follows the spec.

---

### Task 1: Create `tyControls.Dialogs.pas` with `TyDialogButtonBar` pure fn + tests

**Files:**
- Create: `source/tyControls.Dialogs.pas`
- Create: `tests/test.dialogs.pas`
- Modify: `tycontrols.lpk` (add the unit), `tests/tytests.lpr` (add the test unit)

- [ ] **Step 1: Write the failing test.** Create `tests/test.dialogs.pas`:

```pascal
unit test.dialogs;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Dialogs, fpcunit, testregistry,
  tyControls.Dialogs;
type
  TDialogButtonBarTest = class(TTestCase)
  published
    procedure TestSingleButtonRightAligned;
    procedure TestTwoButtonsOrderedRightToLeft;
    procedure TestMarginAndSpacing;
  end;
implementation

procedure TDialogButtonBarTest.TestSingleButtonRightAligned;
var r: TTyRectArray;
begin
  // one 80-wide button in a 300 bar, margin 12 -> right edge at 300-12=288, left at 208
  r := TyDialogButtonBar([Size(80, 28)], 300, 12, 8);
  AssertEquals('count', 1, Length(r));
  AssertEquals('right', 288, r[0].Right);
  AssertEquals('left', 208, r[0].Left);
end;

procedure TDialogButtonBarTest.TestTwoButtonsOrderedRightToLeft;
var r: TTyRectArray;
begin
  // buttons[0]=60, buttons[1]=80; index 0 is the RIGHTMOST (primary). margin 12, spacing 8.
  // r[0] right=288 left=228 ; r[1] right=228-8=220 left=140
  r := TyDialogButtonBar([Size(60, 28), Size(80, 28)], 300, 12, 8);
  AssertEquals('r0.right', 288, r[0].Right);
  AssertEquals('r0.left', 228, r[0].Left);
  AssertEquals('r1.right', 220, r[1].Right);
  AssertEquals('r1.left', 140, r[1].Left);
end;

procedure TDialogButtonBarTest.TestMarginAndSpacing;
var r: TTyRectArray;
begin
  r := TyDialogButtonBar([Size(50, 24), Size(50, 24)], 200, 10, 6);
  AssertEquals('r0.right', 190, r[0].Right);   // 200-10
  AssertEquals('r1.right', 134, r[1].Right);   // 190-50-6
end;

initialization
  RegisterTest(TDialogButtonBarTest);
end.
```

Create `source/tyControls.Dialogs.pas` with just enough to compile the type + fn signature (interface only for now; empty impl will fail the assertions):

```pascal
unit tyControls.Dialogs;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls,
  tyControls.Types;
{ Right-aligns caption buttons in a bar: index 0 is the RIGHTMOST (primary), each successive
  button sits to its left, ASpacing apart, AMargin from the right edge. Pure. }
function TyDialogButtonBar(const ASizes: array of TSize; ABarWidth, AMargin, ASpacing: Integer): TTyRectArray;
implementation
function TyDialogButtonBar(const ASizes: array of TSize; ABarWidth, AMargin, ASpacing: Integer): TTyRectArray;
begin
  SetLength(Result, 0);   // stub -> tests fail
end;
end.
```

Add the unit to `tycontrols.lpk`: find the `<Files ...>` section, copy an existing runtime `<Item>` (e.g. the `tyControls.Types.pas` one), set `<Filename Value="source/tyControls.Dialogs.pas"/>` and `<UnitName Value="tyControls.Dialogs"/>`, and increment the `Count` attribute on the enclosing `<Files Count="NN">` (or `<Units Count>`) by 1. Add `test.dialogs,` to the `uses` clause of `tests/tytests.lpr` (next to `test.form,`).

- [ ] **Step 2: Run tests, verify fail.**

Run: `lazbuild tests/tytests.lpi >/dev/null 2>&1 && ./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)"`
Expected: failures = 3 (the button-bar asserts).

- [ ] **Step 3: Implement `TyDialogButtonBar`.** Replace the stub body:

```pascal
function TyDialogButtonBar(const ASizes: array of TSize; ABarWidth, AMargin, ASpacing: Integer): TTyRectArray;
var i, x: Integer;
begin
  SetLength(Result, Length(ASizes));
  x := ABarWidth - AMargin;                 // right edge of the next (rightmost-first) button
  for i := 0 to High(ASizes) do
  begin
    Result[i].Right := x;
    Result[i].Left := x - ASizes[i].cx;
    Result[i].Top := 0;
    Result[i].Bottom := ASizes[i].cy;
    x := Result[i].Left - ASpacing;
  end;
end;
```

- [ ] **Step 4: Run tests, verify pass.** (failures 0, errors 11, run +3.)

- [ ] **Step 5: Commit.**

```bash
git add source/tyControls.Dialogs.pas tests/test.dialogs.pas tycontrols.lpk tests/tytests.lpr
git commit -m "feat(dialogs): tyControls.Dialogs unit + TyDialogButtonBar pure layout fn"
```
(append `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` to every commit in this plan.)

---

### Task 2: `TyMessage` pure mappings + tests

**Files:** Modify `source/tyControls.Dialogs.pas`; Test `tests/test.dialogs.pas`.

- [ ] **Step 1: Write the failing test.** Add to `tests/test.dialogs.pas` type section:

```pascal
  TMsgMappingTest = class(TTestCase)
  published
    procedure TestButtonResult;
    procedure TestButtonCaptionNonEmpty;
    procedure TestOrderedButtonsCompleteAndStable;
    procedure TestTypeSymbol;
    procedure TestEmptyButtonsDefaultsOK;
  end;
```
Impl:
```pascal
procedure TMsgMappingTest.TestButtonResult;
begin
  AssertEquals('yes', Ord(mrYes), Ord(TyMsgButtonResult(mbYes)));
  AssertEquals('no', Ord(mrNo), Ord(TyMsgButtonResult(mbNo)));
  AssertEquals('ok', Ord(mrOK), Ord(TyMsgButtonResult(mbOK)));
  AssertEquals('cancel', Ord(mrCancel), Ord(TyMsgButtonResult(mbCancel)));
end;

procedure TMsgMappingTest.TestButtonCaptionNonEmpty;
var b: TMsgDlgBtn;
begin
  for b := Low(TMsgDlgBtn) to High(TMsgDlgBtn) do
    AssertTrue('caption for '+IntToStr(Ord(b)), TyMsgButtonCaption(b) <> '');
end;

procedure TMsgMappingTest.TestOrderedButtonsCompleteAndStable;
var a: TMsgDlgBtnArray;
begin
  a := TyMsgOrderedButtons([mbYes, mbNo, mbCancel]);
  AssertEquals('n', 3, Length(a));
  AssertTrue('yes first', a[0] = mbYes);
  AssertTrue('no second', a[1] = mbNo);
  AssertTrue('cancel third', a[2] = mbCancel);
end;

procedure TMsgMappingTest.TestTypeSymbol;
begin
  AssertTrue('warning symbol', TyMsgTypeSymbol(mtWarning) <> '');
  AssertTrue('error symbol', TyMsgTypeSymbol(mtError) <> '');
  AssertTrue('confirmation symbol', TyMsgTypeSymbol(mtConfirmation) <> '');
end;

procedure TMsgMappingTest.TestEmptyButtonsDefaultsOK;
var a: TMsgDlgBtnArray;
begin
  a := TyMsgOrderedButtons([]);
  AssertEquals('empty -> OK', 1, Length(a));
  AssertTrue('is OK', a[0] = mbOK);
end;
```
Add `RegisterTest(TMsgMappingTest);` to `initialization`. Add `Dialogs` to the unit `uses` in `tyControls.Dialogs.pas` interface (for `TMsgDlgType`/`TMsgDlgBtn`/`TMsgDlgButtons`).

- [ ] **Step 2: Run, verify fail** (identifiers not found).

- [ ] **Step 3: Implement.** In `tyControls.Dialogs.pas` interface add:

```pascal
type
  TMsgDlgBtnArray = array of TMsgDlgBtn;
function TyMsgButtonCaption(ABtn: TMsgDlgBtn): string;
function TyMsgButtonResult(ABtn: TMsgDlgBtn): TModalResult;
function TyMsgOrderedButtons(AButtons: TMsgDlgButtons): TMsgDlgBtnArray;
function TyMsgTypeSymbol(ADlgType: TMsgDlgType): string;
```
Implementation:
```pascal
function TyMsgButtonCaption(ABtn: TMsgDlgBtn): string;
begin
  case ABtn of
    mbYes: Result := 'Yes';           mbNo: Result := 'No';
    mbOK: Result := 'OK';             mbCancel: Result := 'Cancel';
    mbAbort: Result := 'Abort';       mbRetry: Result := 'Retry';
    mbIgnore: Result := 'Ignore';     mbAll: Result := 'All';
    mbNoToAll: Result := 'No to All'; mbYesToAll: Result := 'Yes to All';
    mbHelp: Result := 'Help';         mbClose: Result := 'Close';
  else Result := '';
  end;
end;

function TyMsgButtonResult(ABtn: TMsgDlgBtn): TModalResult;
begin
  case ABtn of
    mbYes: Result := mrYes;           mbNo: Result := mrNo;
    mbOK: Result := mrOK;             mbCancel: Result := mrCancel;
    mbAbort: Result := mrAbort;       mbRetry: Result := mrRetry;
    mbIgnore: Result := mrIgnore;     mbAll: Result := mrAll;
    mbNoToAll: Result := mrNoToAll;   mbYesToAll: Result := mrYesToAll;
    mbClose: Result := mrClose;       mbHelp: Result := 0;
  else Result := mrNone;
  end;
end;

function TyMsgOrderedButtons(AButtons: TMsgDlgButtons): TMsgDlgBtnArray;
const ORDER: array[0..11] of TMsgDlgBtn =
  (mbYes, mbYesToAll, mbNo, mbNoToAll, mbAll, mbOK, mbRetry, mbIgnore, mbAbort, mbCancel, mbClose, mbHelp);
var b: TMsgDlgBtn; n: Integer;
begin
  if AButtons = [] then begin SetLength(Result, 1); Result[0] := mbOK; Exit; end;
  SetLength(Result, 0); n := 0;
  for b in ORDER do
    if b in AButtons then begin SetLength(Result, n + 1); Result[n] := b; Inc(n); end;
end;

function TyMsgTypeSymbol(ADlgType: TMsgDlgType): string;
begin
  case ADlgType of
    mtWarning: Result := '!';        mtError: Result := #$C3#$97; // × (U+00D7 UTF-8)
    mtConfirmation: Result := '?';   mtInformation: Result := 'i';
  else Result := '';
  end;
end;
```
(Note `for b in ORDER` needs `{$mode objfpc}` set-in support — it does; iterating a const array is fine.)

- [ ] **Step 4: Run, verify pass.** (failures 0, errors 11, run +5.)

- [ ] **Step 5: Commit.**
```bash
git add source/tyControls.Dialogs.pas tests/test.dialogs.pas
git commit -m "feat(dialogs): TyMessage pure mappings (button caption/result/order + type symbol)"
```

---

### Task 3: `TTyDialog` base class + construct-only test

**Files:** Modify `source/tyControls.Dialogs.pas`; Test `tests/test.dialogs.pas`.

- [ ] **Step 1: Write the failing test.** Add:
```pascal
  TTyDialogAccess = class(TTyDialog);   // same-unit access to protected if needed
  TDialogBaseTest = class(TTestCase)
  published
    procedure TestAddButtonWiresModalResult;
    procedure TestCloseGivesCancel;
  end;
```
Impl:
```pascal
procedure TDialogBaseTest.TestAddButtonWiresModalResult;
var d: TTyDialog; b: TTyButton;
begin
  d := TTyDialog.CreateNew(nil);
  d.SetDesigning(True, False);   // no engine arming (P1)
  try
    b := d.AddButton('OK', mrOk, True, False);
    AssertTrue('button created', b <> nil);
    AssertEquals('caption', 'OK', b.Caption);
    b.Click;                     // simulate press
    AssertEquals('modal result set', Ord(mrOk), Ord(d.ModalResult));
  finally d.Free; end;
end;

procedure TDialogBaseTest.TestCloseGivesCancel;
var d: TTyDialog;
begin
  d := TTyDialog.CreateNew(nil);
  d.SetDesigning(True, False);
  try
    d.AddButton('Cancel', mrCancel, False, True);
    d.CancelDialog;              // the Esc/close path
    AssertEquals('cancel', Ord(mrCancel), Ord(d.ModalResult));
  finally d.Free; end;
end;
```
(Needs `tyControls.Button` in the test `uses` for `TTyButton`.) Add `RegisterTest(TDialogBaseTest);`.

- [ ] **Step 2: Run, verify fail** (`TTyDialog` undefined).

- [ ] **Step 3: Implement `TTyDialog`.** In `tyControls.Dialogs.pas` add `tyControls.Form, tyControls.Button, tyControls.Base` to the interface `uses`, and:
```pascal
type
  TTyDialog = class(TTyForm)
  private
    FButtonBar: TTyPanel;          // strip host for the buttons (transparent)
    FButtons: array of TTyButton;
    FResults: array of TModalResult;
    FDefaultResult, FCancelResult: TModalResult;
    procedure ButtonClicked(Sender: TObject);
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    constructor CreateNew(AOwner: TComponent; Num: Integer = 0); override;
    function AddButton(const ACaption: string; AResult: TModalResult;
      ADefault: Boolean = False; ACancel: Boolean = False): TTyButton;
    procedure LayoutButtonBar;
    function ContentRect: TRect;
    procedure AutoSizeToContent(AContentW, AContentH: Integer);
    procedure CancelDialog;       // title-bar close / Esc -> mrCancel-style
  end;
```
Implementation (use existing consts for metrics; `TTyPanel` is `tyControls.Panel`, add it to uses):
```pascal
constructor TTyDialog.CreateNew(AOwner: TComponent; Num: Integer);
begin
  inherited CreateNew(AOwner, Num);
  BorderIcons := [biSystemMenu];      // close only (P1 chrome)
  Resizable := False;
  Position := poMainFormCenter;
  KeyPreview := True;
  FDefaultResult := mrNone; FCancelResult := mrCancel;
  FButtonBar := TTyPanel.Create(Self);
  FButtonBar.Parent := Self;
  FButtonBar.Align := alBottom;
  FButtonBar.Height := 44;
  FButtonBar.StyleClass := 'ghost';   // transparent-ish; refine in theming
end;

procedure TTyDialog.ButtonClicked(Sender: TObject);
begin
  ModalResult := TModalResult(TComponent(Sender).Tag);
end;

function TTyDialog.AddButton(const ACaption: string; AResult: TModalResult;
  ADefault, ACancel: Boolean): TTyButton;
begin
  Result := TTyButton.Create(Self);
  Result.Parent := FButtonBar;
  Result.Caption := ACaption;
  Result.Tag := AResult;
  Result.OnClick := @ButtonClicked;
  SetLength(FButtons, Length(FButtons) + 1); FButtons[High(FButtons)] := Result;
  SetLength(FResults, Length(FResults) + 1); FResults[High(FResults)] := AResult;
  if ADefault then FDefaultResult := AResult;
  if ACancel then FCancelResult := AResult;
  LayoutButtonBar;
end;

procedure TTyDialog.LayoutButtonBar;
var sizes: array of TSize; rects: TTyRectArray; i, y: Integer;
begin
  if Length(FButtons) = 0 then Exit;
  SetLength(sizes, Length(FButtons));
  for i := 0 to High(FButtons) do sizes[i] := Size(88, 30);   // fixed dialog-button size
  rects := TyDialogButtonBar(sizes, FButtonBar.ClientWidth, 12, 8);
  y := (FButtonBar.ClientHeight - 30) div 2;
  for i := 0 to High(FButtons) do
    FButtons[i].SetBounds(rects[i].Left, y, 88, 30);
end;

function TTyDialog.ContentRect: TRect;
begin
  Result := ClientRect;
  Inc(Result.Top, TitleHeight);
  Dec(Result.Bottom, FButtonBar.Height);
end;

procedure TTyDialog.AutoSizeToContent(AContentW, AContentH: Integer);
var totalBtn, i, w: Integer;
begin
  totalBtn := 12; for i := 0 to High(FButtons) do totalBtn := totalBtn + 88 + 8;
  w := AContentW; if totalBtn > w then w := totalBtn;
  ClientWidth := w + 32;
  ClientHeight := TitleHeight + AContentH + FButtonBar.Height + 16;
  LayoutButtonBar;
end;

procedure TTyDialog.CancelDialog;
begin
  ModalResult := FCancelResult;
end;

procedure TTyDialog.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if (Key = 13) and (FDefaultResult <> mrNone) then begin ModalResult := FDefaultResult; Key := 0; Exit; end;
  if Key = 27 then begin CancelDialog; Key := 0; Exit; end;
  inherited KeyDown(Key, Shift);
end;
```
Wire the title-bar close → `CancelDialog`: after `inherited CreateNew`, the P1 title-bar close currently calls `Close`; for a dialog we want `mrCancel`. Add to `CreateNew` end: nothing extra needed if closing a modal with `ModalResult=mrNone` returns `mrCancel` — but to be explicit, override `DoClose`/set `ModalResult` on close. Simplest: in `CreateNew`, set the form's `OnCloseQuery` is overkill; instead rely on LCL: a modal form closed via the system/close returns `mrCancel`. Keep `CancelDialog` for the Esc path (tested). (If a GUI check later shows the X returns mrNone, add a `CloseQuery`-time `ModalResult := mrCancel`.)

- [ ] **Step 4: Run, verify pass.** (failures 0, errors 11, run +2.)

- [ ] **Step 5: Commit.**
```bash
git add source/tyControls.Dialogs.pas tests/test.dialogs.pas
git commit -m "feat(dialogs): TTyDialog base — content area + button bar + Enter/Esc wiring"
```

---

### Task 4: `TyMessage` builder + globals + component + construct-only test

**Files:** Modify `source/tyControls.Dialogs.pas`; Test `tests/test.dialogs.pas`.

- [ ] **Step 1: Write the failing test.** Add:
```pascal
  TMessageBuildTest = class(TTestCase)
  published
    procedure TestBuildConfirmationHasYesNo;
    procedure TestBuildInformationHasOK;
  end;
```
Impl:
```pascal
procedure TMessageBuildTest.TestBuildConfirmationHasYesNo;
var d: TTyDialog;
begin
  d := TyBuildMessageDialog('Delete it?', mtConfirmation, [mbYes, mbNo]);
  d.SetDesigning(True, False);
  try
    AssertEquals('two buttons', 2, TyDialogButtonCount(d));
    AssertEquals('btn0 caption', 'Yes', TyDialogButton(d, 0).Caption);
    AssertEquals('btn0 result', Ord(mrYes), TyDialogButton(d, 0).Tag);
    AssertEquals('btn1 caption', 'No', TyDialogButton(d, 1).Caption);
  finally d.Free; end;
end;

procedure TMessageBuildTest.TestBuildInformationHasOK;
var d: TTyDialog;
begin
  d := TyBuildMessageDialog('Saved.', mtInformation, []);
  d.SetDesigning(True, False);
  try
    AssertEquals('one button', 1, TyDialogButtonCount(d));
    AssertEquals('OK', 'OK', TyDialogButton(d, 0).Caption);
  finally d.Free; end;
end;
```
Add `RegisterTest(TMessageBuildTest);`. (These need read access to the built buttons — expose two helpers, below.)

- [ ] **Step 2: Run, verify fail.**

- [ ] **Step 3: Implement.** In `tyControls.Dialogs.pas` add to interface:
```pascal
{ Test/introspection helpers (construct-only seam). }
function TyDialogButtonCount(ADlg: TTyDialog): Integer;
function TyDialogButton(ADlg: TTyDialog; AIndex: Integer): TTyButton;
{ Build a message dialog WITHOUT showing it (the show is TyMessageDlg). }
function TyBuildMessageDialog(const AMsg: string; ADlgType: TMsgDlgType; AButtons: TMsgDlgButtons): TTyDialog;
{ Globals — the primary API. }
procedure TyShowMessage(const AMsg: string);
function TyMessageDlg(const AMsg: string; ADlgType: TMsgDlgType; AButtons: TMsgDlgButtons; AHelpCtx: Longint = 0): TModalResult;
function TyMessageDlgPos(const AMsg: string; ADlgType: TMsgDlgType; AButtons: TMsgDlgButtons; AHelpCtx: Longint; X, Y: Integer): TModalResult;
type
  TTyMessage = class(TComponent)
  private
    FTitle, FMsg: string;
    FDlgType: TMsgDlgType;
    FButtons: TMsgDlgButtons;
  public
    function Execute: TModalResult;
  published
    property Title: string read FTitle write FTitle;
    property Msg: string read FMsg write FMsg;
    property DlgType: TMsgDlgType read FDlgType write FDlgType default mtInformation;
    property Buttons: TMsgDlgButtons read FButtons write FButtons default [mbOK];
  end;
```
Expose the button arrays for the helpers — add `public` read to `TTyDialog`:
```pascal
    property ButtonCount: Integer read GetButtonCount;   // add GetButtonCount returning Length(FButtons)
    property Buttons[AIndex: Integer]: TTyButton read GetButton;   // returns FButtons[AIndex]
```
Implementation:
```pascal
function TyDialogButtonCount(ADlg: TTyDialog): Integer;
begin Result := ADlg.ButtonCount; end;
function TyDialogButton(ADlg: TTyDialog; AIndex: Integer): TTyButton;
begin Result := ADlg.Buttons[AIndex]; end;

function TyBuildMessageDialog(const AMsg: string; ADlgType: TMsgDlgType; AButtons: TMsgDlgButtons): TTyDialog;
var lbl: TTyLabel; ordered: TMsgDlgBtnArray; i: Integer; def, can: TMsgDlgBtn;
begin
  Result := TTyDialog.CreateNew(Application);
  Result.Caption := TyMsgTypeSymbol(ADlgType);   // placeholder title; real title set by caller/Fmt
  ordered := TyMsgOrderedButtons(AButtons);
  lbl := TTyLabel.Create(Result);
  lbl.Parent := Result;
  lbl.Caption := AMsg;
  lbl.WordWrap := True;
  lbl.SetBounds(56, Result.TitleHeight + 12, 260, 40);   // right of the 44px icon column
  // default = first button; cancel = mbCancel/mbNo/last
  def := ordered[0]; can := ordered[High(ordered)];
  for i := 0 to High(ordered) do
    Result.AddButton(TyMsgButtonCaption(ordered[i]), TyMsgButtonResult(ordered[i]),
      ordered[i] = def, ordered[i] = can);
  Result.AutoSizeToContent(320, 56);
end;

function TyMessageDlg(const AMsg: string; ADlgType: TMsgDlgType; AButtons: TMsgDlgButtons; AHelpCtx: Longint): TModalResult;
var d: TTyDialog;
begin
  d := TyBuildMessageDialog(AMsg, ADlgType, AButtons);
  try Result := d.ShowModal; finally d.Free; end;
end;

function TyMessageDlgPos(const AMsg: string; ADlgType: TMsgDlgType; AButtons: TMsgDlgButtons; AHelpCtx: Longint; X, Y: Integer): TModalResult;
var d: TTyDialog;
begin
  d := TyBuildMessageDialog(AMsg, ADlgType, AButtons);
  try d.Position := poDesigned; d.Left := X; d.Top := Y; Result := d.ShowModal; finally d.Free; end;
end;

procedure TyShowMessage(const AMsg: string);
begin TyMessageDlg(AMsg, mtInformation, [mbOK]); end;

function TTyMessage.Execute: TModalResult;
begin
  if FButtons = [] then FButtons := [mbOK];
  Result := TyMessageDlg(FMsg, FDlgType, FButtons);
end;
```
The **message icon** is drawn in `TTyDialog.Paint` (or a small content-paint): fill a circle at the icon column in a semantic color and draw `TyMsgTypeSymbol` centered — implement a `DrawMessageIcon` only when a type is set (store `FMsgType`/`FMsgSymbol` on the dialog when building; a plain `TTyDialog` draws no icon). Minimal, non-tested-pixel (render smoke only). Keep it simple: fill `TTyPainter.FillEllipse` + `DrawText` in semantic color (info/question=accent, warning=amber $FF8C00, error=red $E53935).

- [ ] **Step 4: Run, verify pass.** (failures 0, errors 11, run +2.) Also build the lib: `lazbuild tycontrols.lpk ...` exit 0.

- [ ] **Step 5: Commit.**
```bash
git add source/tyControls.Dialogs.pas tests/test.dialogs.pas
git commit -m "feat(dialogs): TyMessage builder + TyShowMessage/TyMessageDlg globals + TTyMessage component"
```

---

### Task 5: Palette group + IDE "TyControls Dialog" New-item + remove "Main Form" from the New list

**Files:** Modify `designtime/tyControls.Design.pas`, `tycontrols_dt.lpk` (if the descriptor needs a new source — it lives in Design.pas).

- [ ] **Step 1: Register the component group + designer base class.** In `Register` (Design.pas ~line 540), after the existing `RegisterComponents('TyControls', [...])`, add:
```pascal
  RegisterComponents('TyControls Dialogs', [TTyMessage]);
  if FormEditingHook <> nil then
    FormEditingHook.RegisterDesignerBaseClass(TTyDialog);
```
Add `tyControls.Dialogs` to the `uses` clause of `tyControls.Design.pas`.

- [ ] **Step 2: Remove "TyControls Main Form" from the New-item list.** At Design.pas line ~573, DELETE the line `RegisterProjectFileDescriptor(TyMainFormDescriptor);` — but KEEP line ~572 `TyMainFormDescriptor := TTyMainFormFileDescriptor.Create;` (the App descriptor still uses `TyMainFormDescriptor`).

- [ ] **Step 3: Add the "TyControls Dialog" New-item descriptor.** Add a `TTyDialogFileDescriptor` class modeled on `TTyFormFileDescriptor` (Design.pas ~lines 50-60, 330-426): `GetLocalizedName` → `'TyControls Dialog'`; `GetInterfaceSource` declaring `TyTitleBar1: TTyTitleBar;` and the form `= class(TTyDialog)`; `GetResourceSource` producing an `.lfm` with a top `TyTitleBar1` and the form's `BorderIcons = [biSystemMenu]`. Register it in `Register`: `RegisterProjectFileDescriptor(TTyDialogFileDescriptor.Create);`. (Copy the `TTyFormFileDescriptor` body; change the ancestor to `TTyDialog`, the name, and add `BorderIcons = [biSystemMenu]` to the form resource.)

- [ ] **Step 4: Build the dt package.**
Run: `lazbuild tycontrols_dt.lpk 2>&1 | grep -iE "error|fatal"; echo exit ${PIPESTATUS[0]}`
Expected: exit 0.

- [ ] **Step 5: Commit.**
```bash
git add designtime/tyControls.Design.pas
git commit -m "feat(design): TyControls Dialogs palette group + TyControls Dialog New-item; drop Main Form from New list"
```

---

### Task 6: Final verification + docs

- [ ] **Step 1: Full sweep.**
```bash
lazbuild tycontrols.lpk 2>&1 | grep -iE "error|fatal"; echo lib ${PIPESTATUS[0]}
lazbuild tycontrols_dt.lpk 2>&1 | grep -iE "error|fatal"; echo dt ${PIPESTATUS[0]}
lazbuild tests/tytests.lpi >/dev/null 2>&1 && ./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)"
```
Expected: lib/dt exit 0; failures 0; errors 11; run ~1568 (baseline 1549 + 3 + 5 + 2 + 2 + 2 = 1563 — verify the exact delta).

- [ ] **Step 2: Add `docs/controls/dialogs.md`** documenting `TyShowMessage`/`TyMessageDlg`, the `TTyMessage` component, `TTyDialog` as a base for custom dialogs, and the global-function pattern (Chinese, matching the other `docs/controls/*.md`).

- [ ] **Step 3: Commit.**
```bash
git add docs/controls/dialogs.md
git commit -m "docs: dialogs S1 — TTyDialog + TyMessage global functions"
```

- [ ] **Step 4: Finish the branch.** Use superpowers:finishing-a-development-branch (run the pre-merge checklist: i18n + README — this DID add public API + user-facing button captions; see note below).

---

## Notes for the implementer
- **i18n**: the message button captions ('Yes'/'No'/…) and any user-visible dialog text SHOULD be resourcestrings (`tyControls.StrConsts` pattern) so they can be translated — this is the first control-family with genuine user-facing text. Per the pre-merge checklist, wire `TyMsgButtonCaption` onto resourcestrings and regenerate the `.pot` + zh_CN `.po` before merge. (The plan uses literals for clarity; convert to resourcestrings in Task 2's implementation or a follow-up step, and update the catalogs in Task 6.)
- **README**: S1 adds a dialog subsystem — add a short "Dialogs" line to `README.md` + `README.en.md` in Task 6.
- **Do not run a real GUI.** All tests are construct-only / pure; never call `ShowModal` in a test (it blocks). Use `SetDesigning(True, False)` when building a dialog headlessly (P1 lesson: avoids chrome-engine arming).
- **`TTyPanel`** for the button bar is in `tyControls.Panel`; **`TTyLabel`** in `tyControls.TyLabel`; add both to `uses`.
- **Baseline** 1549/0/11; keep failures 0, errors 11.
