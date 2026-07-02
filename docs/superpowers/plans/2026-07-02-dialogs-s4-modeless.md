# Modeless Dialogs (S4) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship non-modal Find/Replace dialogs (`TTyFindDialog`/`TTyReplaceDialog` — LCL `TFindDialog` parity) and a Progress dialog (`TTyProgressDialog`), each a component that owns a reusable `TTyDialog`-derived form shown with `Show` (not `ShowModal`).

**Architecture:** Component-owns-form. Each component lazily creates a `TTyDialog` subclass (Owner = the component, so it's freed automatically), shows it modeless, and reuses it (hide-not-free). Action buttons use `AddButton(caption, mrNone)` (non-closing) + `OnClick` forwarding to public `Do…` seams. The owned form overrides `KeyDown` for Esc/Enter because the inherited modal `ModalResult` path is inert without a modal loop. Find options round-trip through pure functions; each action button stamps the LCL action flags (`frFindNext`/`frReplace`/`frReplaceAll`).

**Tech Stack:** Lazarus/FPC, LCL (`TFindOptions` from `Dialogs`, `VK_*` from `LCLType`), `tyControls.Dialogs` base (`TTyDialog`, `AddButton`, `ContentRect`, `AutoSizeToContent`, `TyDlgPad`/`TyDlgEditW`/`TyDlgEditH`), `tyControls.Edit`/`.CheckBox`/`.Button`/`.TyLabel`/`.ProgressBar`, fpcunit headless tests.

**Spec:** `docs/superpowers/specs/2026-07-02-dialogs-s4-modeless-design.md`

**Baseline (run before starting):** `lazbuild tests/tytests.lpi >/dev/null 2>&1 && ./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)"` — expect ≈**1593 run / 0 failures / 11 errors**. The 11 errors are known headless-win32 environment errors (non-regressions): keep failures at **0** and errors at **11** throughout. Record the exact starting `run` count.

**Standing constraints:** Reply to the user in Chinese. Do NOT push (user drives pushes). Do NOT touch `examples/demo/*`. Commit messages end with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`.

---

## File Structure

- **`source/tyControls.Dialogs.Find.pas`** (create) — one unit for both Find and Replace. Holds: the pure option-mapping (`TTyFindChecks`, `TyFindOptionsToChecks`, `TyChecksToFindOptions`); the shared owned form `TTyFindForm` (built in Find or Replace mode via `Build(AWithReplace)`); the components `TTyFindDialog` and `TTyReplaceDialog`. Find and Replace live together because Replace is a one-flag variation of the same form + a `TTyFindDialog` subclass — they change together.
- **`source/tyControls.Dialogs.Progress.pas`** (create) — the progress form `TTyProgressForm` + the stateful component `TTyProgressDialog` (with the `FInPump` re-entrancy guard around `Application.ProcessMessages`).
- **`source/tyControls.StrConsts.pas`** (modify) — append S4 `rsDlg…` resourcestrings.
- **`designtime/tyControls.Design.pas`** (modify) — `uses` the 2 new units + register the 3 components.
- **`tycontrols.lpk`** (modify) — 2 new `<Item>` file entries.
- **`tests/test.dialogs.find.pas`** (create), **`tests/test.dialogs.progress.pas`** (create) — headless tests.
- **`tests/tytests.lpr`** (modify) — add the 2 test units to `uses`.
- **`languages/tycontrols.strconsts.zh_CN.po`** (modify) — zh_CN translations for the new strings.
- **`docs/controls/dialogs.md`** + **`README.md`** / **`README.en.md`** (modify) — document the modeless family.

---

## Task 1: Find unit skeleton + pure option mapping

**Files:**
- Create: `source/tyControls.Dialogs.Find.pas`
- Modify: `tycontrols.lpk` (after the `tyControls.Dialogs.Font` item, before `</Files>`)
- Modify: `tests/tytests.lpr` (uses clause)
- Create: `tests/test.dialogs.find.pas`

- [ ] **Step 1: Create the minimal unit with the pure mapping**

Create `source/tyControls.Dialogs.Find.pas`:

```pascal
unit tyControls.Dialogs.Find;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Dialogs;

type
  TTyFindChecks = record
    MatchCase, WholeWord, SearchUp: Boolean;
  end;

function TyFindOptionsToChecks(AOpts: TFindOptions): TTyFindChecks;
function TyChecksToFindOptions(const AChecks: TTyFindChecks; ABase: TFindOptions): TFindOptions;

implementation

function TyFindOptionsToChecks(AOpts: TFindOptions): TTyFindChecks;
begin
  Result.MatchCase := frMatchCase in AOpts;
  Result.WholeWord := frWholeWord in AOpts;
  Result.SearchUp  := not (frDown in AOpts);
end;

function TyChecksToFindOptions(const AChecks: TTyFindChecks; ABase: TFindOptions): TFindOptions;
begin
  Result := ABase;
  if AChecks.MatchCase then Include(Result, frMatchCase) else Exclude(Result, frMatchCase);
  if AChecks.WholeWord then Include(Result, frWholeWord) else Exclude(Result, frWholeWord);
  if AChecks.SearchUp  then Exclude(Result, frDown)      else Include(Result, frDown);
end;

end.
```

- [ ] **Step 2: Register the unit in the runtime package**

In `tycontrols.lpk`, immediately after the `tyControls.Dialogs.Font` `<Item>` (the one whose `<Filename>` is `source/tyControls.Dialogs.Font.pas`) and before the closing `</Files>`, insert:

```xml
      <Item>
        <Filename Value="source/tyControls.Dialogs.Find.pas"/>
        <UnitName Value="tyControls.Dialogs.Find"/>
      </Item>
```

(There is no `<Count>` attribute on `<Files>` to bump.)

- [ ] **Step 3: Write the failing test**

Create `tests/test.dialogs.find.pas`:

```pascal
unit test.dialogs.find;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Dialogs, fpcunit, testregistry, tyControls.Dialogs.Find;

type
  TFindMapTest = class(TTestCase)
  published
    procedure TestOptionsToChecks;
    procedure TestChecksToOptionsRoundTrip;
    procedure TestBasePreserved;
  end;

implementation

procedure TFindMapTest.TestOptionsToChecks;
var ch: TTyFindChecks;
begin
  ch := TyFindOptionsToChecks([frMatchCase, frDown]);
  AssertTrue('matchcase', ch.MatchCase);
  AssertFalse('wholeword', ch.WholeWord);
  AssertFalse('searchup (frDown present)', ch.SearchUp);

  ch := TyFindOptionsToChecks([frWholeWord]);   // no frDown -> searching up
  AssertFalse('matchcase', ch.MatchCase);
  AssertTrue('wholeword', ch.WholeWord);
  AssertTrue('searchup (no frDown)', ch.SearchUp);
end;

procedure TFindMapTest.TestChecksToOptionsRoundTrip;
var ch: TTyFindChecks; opts: TFindOptions;
begin
  ch.MatchCase := True; ch.WholeWord := False; ch.SearchUp := False;
  opts := TyChecksToFindOptions(ch, []);
  AssertTrue('frMatchCase', frMatchCase in opts);
  AssertFalse('frWholeWord', frWholeWord in opts);
  AssertTrue('frDown (searchup false)', frDown in opts);

  ch := TyFindOptionsToChecks(opts);
  AssertTrue('rt matchcase', ch.MatchCase);
  AssertFalse('rt wholeword', ch.WholeWord);
  AssertFalse('rt searchup', ch.SearchUp);
end;

procedure TFindMapTest.TestBasePreserved;
var ch: TTyFindChecks; opts: TFindOptions;
begin
  ch.MatchCase := False; ch.WholeWord := True; ch.SearchUp := True;
  // untouched base flags (frReplace, frEntireScope) must survive
  opts := TyChecksToFindOptions(ch, [frReplace, frReplaceAll, frEntireScope, frDown]);
  AssertTrue('frReplace kept', frReplace in opts);
  AssertTrue('frReplaceAll kept', frReplaceAll in opts);
  AssertTrue('frEntireScope kept', frEntireScope in opts);
  AssertTrue('frWholeWord set', frWholeWord in opts);
  AssertFalse('frDown cleared (searchup true)', frDown in opts);
end;

initialization
  RegisterTest(TFindMapTest);
end.
```

- [ ] **Step 4: Register the test unit**

In `tests/tytests.lpr`, find the last line of the `uses` clause (currently `  test.dialogs.font;`). Change its terminating `;` to `,` and add the new unit:

```pascal
  test.dialogs.font,
  test.dialogs.find;
```

- [ ] **Step 5: Build + run — verify the new tests pass**

Run:
```
lazbuild tycontrols.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)"
```
Expected: build exit 0; `run` = baseline + 3; failures 0; errors 11.

- [ ] **Step 6: Commit**

```bash
git add source/tyControls.Dialogs.Find.pas tycontrols.lpk tests/test.dialogs.find.pas tests/tytests.lpr
git commit -m "feat(dialogs): S4 Find option mapping (pure TFindOptions<->checks)

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: TTyFindForm + TTyFindDialog (Find), with KeyDown/DoFindNext seams

**Files:**
- Modify: `source/tyControls.Dialogs.Find.pas` (grow to the full unit below)
- Modify: `source/tyControls.StrConsts.pas` (append Find resourcestrings)
- Modify: `tests/test.dialogs.find.pas` (add wiring test)

- [ ] **Step 1: Append Find resourcestrings**

In `source/tyControls.StrConsts.pas`, inside the single `resourcestring` block, immediately before the `implementation` line (currently line ~105, right after the `rsDlgFontSample` line), add:

```pascal
  // --- Find/Replace dialog (S4) — user-facing, translated ---
  rsDlgFindWhat        = 'Find what:';
  rsDlgReplaceWith     = 'Replace with:';
  rsDlgMatchCase       = 'Match case';
  rsDlgWholeWord       = 'Whole word';
  rsDlgSearchUp        = 'Search up';
  rsDlgFindNext        = 'Find Next';
  rsDlgReplace         = 'Replace';
  rsDlgReplaceAll      = 'Replace All';
  rsDlgFindClose       = 'Close';
```

(`rsDlgReplaceWith`/`rsDlgReplace`/`rsDlgReplaceAll` are added now too so the whole form compiles; the Replace component that uses them arrives in Task 3.)

- [ ] **Step 2: Replace the unit body with the full Find form + component**

Overwrite `source/tyControls.Dialogs.Find.pas` with the complete unit (the pure functions from Task 1 are unchanged; the form + components are new):

```pascal
unit tyControls.Dialogs.Find;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Dialogs, LCLType,
  tyControls.Dialogs, tyControls.Edit, tyControls.CheckBox, tyControls.Button,
  tyControls.TyLabel, tyControls.StrConsts;

type
  TTyFindChecks = record
    MatchCase, WholeWord, SearchUp: Boolean;
  end;

function TyFindOptionsToChecks(AOpts: TFindOptions): TTyFindChecks;
function TyChecksToFindOptions(const AChecks: TTyFindChecks; ABase: TFindOptions): TFindOptions;

type
  TTyFindDialog = class;

  { TTyFindForm — the reusable modeless form owned by a TTyFindDialog. Built in
    Find mode (Build(False)) or Find+Replace mode (Build(True)). All state lives on
    the owning component (FDlg); the form is pure UI + the Do* action seams. }
  TTyFindForm = class(TTyDialog)
  private
    FDlg: TTyFindDialog;
    FWithReplace: Boolean;
    FFindEdit: TTyEdit;
    FReplaceEdit: TTyEdit;        // nil unless FWithReplace
    FMatchCase, FWholeWord, FSearchUp: TTyCheckBox;
    procedure FindNextClick(Sender: TObject);
    procedure ReplaceClick(Sender: TObject);
    procedure ReplaceAllClick(Sender: TObject);
    procedure CloseClick(Sender: TObject);
    procedure WriteBack;
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    procedure Build(AWithReplace: Boolean);
    procedure SyncFrom(const AFindText, AReplaceText: string; AOptions: TFindOptions);
    procedure DoFindNext;
    procedure DoReplace;
    procedure DoReplaceAll;
    // test seams:
    function FindEdit: TTyEdit;
    function ReplaceEdit: TTyEdit;
    function MatchCaseCheck: TTyCheckBox;
    function WholeWordCheck: TTyCheckBox;
    function SearchUpCheck: TTyCheckBox;
    property WithReplace: Boolean read FWithReplace;
  end;

  { TTyFindDialog — non-visual, modeless. Owns a TTyFindForm; fires OnFind when the
    user clicks Find Next (or presses Enter). LCL TFindDialog parity. }
  TTyFindDialog = class(TComponent)
  private
    FFindText: string;
    FReplaceText: string;        // populated by TTyReplaceDialog
    FOptions: TFindOptions;
    FPosition: TPosition;
    FOnFind: TNotifyEvent;
    FOnReplace: TNotifyEvent;    // used by TTyReplaceDialog
    FForm: TTyFindForm;
  protected
    function WantReplace: Boolean; virtual;
  public
    constructor Create(AOwner: TComponent); override;
    function BuildForm: TTyFindForm;   // test seam: lazy build + sync, NO Show
    function Execute: Boolean;
    procedure CloseDialog;
  published
    property FindText: string read FFindText write FFindText;
    property Options: TFindOptions read FOptions write FOptions default [frDown];
    property Position: TPosition read FPosition write FPosition default poScreenCenter;
    property OnFind: TNotifyEvent read FOnFind write FOnFind;
  end;

implementation

function TyFindOptionsToChecks(AOpts: TFindOptions): TTyFindChecks;
begin
  Result.MatchCase := frMatchCase in AOpts;
  Result.WholeWord := frWholeWord in AOpts;
  Result.SearchUp  := not (frDown in AOpts);
end;

function TyChecksToFindOptions(const AChecks: TTyFindChecks; ABase: TFindOptions): TFindOptions;
begin
  Result := ABase;
  if AChecks.MatchCase then Include(Result, frMatchCase) else Exclude(Result, frMatchCase);
  if AChecks.WholeWord then Include(Result, frWholeWord) else Exclude(Result, frWholeWord);
  if AChecks.SearchUp  then Exclude(Result, frDown)      else Include(Result, frDown);
end;

{ TTyFindForm }

procedure TTyFindForm.Build(AWithReplace: Boolean);
var
  r: TRect;
  x0, y, editX, editW: Integer;
  b: TTyButton;

  function MkLabel(const ACaption: string; ALeft, ATop, AWidth: Integer): TTyLabel;
  begin
    Result := TTyLabel.Create(Self);
    Result.Parent := Self;
    Result.Caption := ACaption;
    Result.SetBounds(ALeft, ATop, AWidth, 20);
  end;

  function MkCheck(const ACaption: string; ALeft, ATop: Integer): TTyCheckBox;
  begin
    Result := TTyCheckBox.Create(Self);
    Result.Parent := Self;
    Result.Caption := ACaption;
    Result.SetBounds(ALeft, ATop, 160, 22);
  end;

begin
  FWithReplace := AWithReplace;
  r := ContentRect;
  x0 := r.Left + TyDlgPad;
  y := r.Top + TyDlgPad;
  editX := x0 + 100;
  editW := TyDlgEditW;

  MkLabel(rsDlgFindWhat, x0, y + 4, 96);
  FFindEdit := TTyEdit.Create(Self);
  FFindEdit.Parent := Self;
  FFindEdit.SetBounds(editX, y, editW, TyDlgEditH);
  Inc(y, TyDlgEditH + 8);

  if AWithReplace then
  begin
    MkLabel(rsDlgReplaceWith, x0, y + 4, 96);
    FReplaceEdit := TTyEdit.Create(Self);
    FReplaceEdit.Parent := Self;
    FReplaceEdit.SetBounds(editX, y, editW, TyDlgEditH);
    Inc(y, TyDlgEditH + 8);
  end;

  FMatchCase := MkCheck(rsDlgMatchCase, x0, y); Inc(y, 26);
  FWholeWord := MkCheck(rsDlgWholeWord, x0, y); Inc(y, 26);
  FSearchUp  := MkCheck(rsDlgSearchUp,  x0, y); Inc(y, 26);

  // Action buttons: AddButton(caption, mrNone) is non-closing (mrNone never sets
  // Form.ModalResult) yet still lands on the auto-laid-out button bar. OnClick
  // forwards to the public Do* seams.
  b := AddButton(rsDlgFindNext, mrNone); b.OnClick := @FindNextClick;
  if AWithReplace then
  begin
    b := AddButton(rsDlgReplace, mrNone);    b.OnClick := @ReplaceClick;
    b := AddButton(rsDlgReplaceAll, mrNone); b.OnClick := @ReplaceAllClick;
  end;
  b := AddButton(rsDlgFindClose, mrNone); b.OnClick := @CloseClick;

  AutoSizeToContent((editX - r.Left) + editW + TyDlgPad, (y - r.Top) + TyDlgPad);
end;

procedure TTyFindForm.SyncFrom(const AFindText, AReplaceText: string; AOptions: TFindOptions);
var ch: TTyFindChecks;
begin
  if FFindEdit = nil then Exit;
  FFindEdit.Text := AFindText;
  if FWithReplace and (FReplaceEdit <> nil) then FReplaceEdit.Text := AReplaceText;
  ch := TyFindOptionsToChecks(AOptions);
  FMatchCase.Checked := ch.MatchCase;
  FWholeWord.Checked := ch.WholeWord;
  FSearchUp.Checked  := ch.SearchUp;
end;

procedure TTyFindForm.WriteBack;
var ch: TTyFindChecks;
begin
  if FDlg = nil then Exit;
  FDlg.FFindText := FFindEdit.Text;
  if FWithReplace and (FReplaceEdit <> nil) then FDlg.FReplaceText := FReplaceEdit.Text;
  ch.MatchCase := FMatchCase.Checked;
  ch.WholeWord := FWholeWord.Checked;
  ch.SearchUp  := FSearchUp.Checked;
  FDlg.FOptions := TyChecksToFindOptions(ch, FDlg.FOptions);
end;

procedure TTyFindForm.DoFindNext;
begin
  WriteBack;
  if FDlg = nil then Exit;
  FDlg.FOptions := FDlg.FOptions - [frReplace, frReplaceAll] + [frFindNext];
  if Assigned(FDlg.FOnFind) then FDlg.FOnFind(FDlg);
end;

procedure TTyFindForm.DoReplace;
begin
  WriteBack;
  if FDlg = nil then Exit;
  FDlg.FOptions := FDlg.FOptions + [frReplace] - [frReplaceAll, frFindNext];
  if Assigned(FDlg.FOnReplace) then FDlg.FOnReplace(FDlg);
end;

procedure TTyFindForm.DoReplaceAll;
begin
  WriteBack;
  if FDlg = nil then Exit;
  FDlg.FOptions := FDlg.FOptions + [frReplaceAll] - [frFindNext, frReplace];
  if Assigned(FDlg.FOnReplace) then FDlg.FOnReplace(FDlg);
end;

procedure TTyFindForm.FindNextClick(Sender: TObject);   begin DoFindNext; end;
procedure TTyFindForm.ReplaceClick(Sender: TObject);    begin DoReplace; end;
procedure TTyFindForm.ReplaceAllClick(Sender: TObject); begin DoReplaceAll; end;
procedure TTyFindForm.CloseClick(Sender: TObject);      begin Hide; end;

procedure TTyFindForm.KeyDown(var Key: Word; Shift: TShiftState);
begin
  // The inherited (modal) Enter/Esc path sets ModalResult, which is inert on a
  // modeless form. Handle Enter/Esc here instead.
  if Key = VK_RETURN then
  begin
    if FWithReplace then DoReplace else DoFindNext;
    Key := 0; Exit;
  end;
  if Key = VK_ESCAPE then
  begin
    Hide;
    Key := 0; Exit;
  end;
  inherited KeyDown(Key, Shift);
end;

function TTyFindForm.FindEdit: TTyEdit;         begin Result := FFindEdit; end;
function TTyFindForm.ReplaceEdit: TTyEdit;      begin Result := FReplaceEdit; end;
function TTyFindForm.MatchCaseCheck: TTyCheckBox; begin Result := FMatchCase; end;
function TTyFindForm.WholeWordCheck: TTyCheckBox; begin Result := FWholeWord; end;
function TTyFindForm.SearchUpCheck: TTyCheckBox;  begin Result := FSearchUp; end;

{ TTyFindDialog }

constructor TTyFindDialog.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FOptions := [frDown];
  FPosition := poScreenCenter;
end;

function TTyFindDialog.WantReplace: Boolean;
begin
  Result := False;
end;

function TTyFindDialog.BuildForm: TTyFindForm;
begin
  if FForm = nil then
  begin
    FForm := TTyFindForm.CreateNew(Self, 0);   // Owner = Self -> freed with the component
    FForm.FDlg := Self;
    FForm.Build(WantReplace);
  end;
  FForm.SyncFrom(FFindText, FReplaceText, FOptions);
  Result := FForm;
end;

function TTyFindDialog.Execute: Boolean;
begin
  if csDesigning in ComponentState then Exit(False);
  BuildForm;
  FForm.Position := FPosition;
  FForm.Show;
  Result := True;
end;

procedure TTyFindDialog.CloseDialog;
begin
  if FForm <> nil then FForm.Hide;
end;

end.
```

- [ ] **Step 3: Write the failing wiring test**

In `tests/test.dialogs.find.pas`, add `Controls, tyControls.Dialogs.Find` are already imported. Add the wiring test class. Change the `uses` to add `tyControls.CheckBox`:

```pascal
uses
  Classes, SysUtils, Dialogs, fpcunit, testregistry,
  tyControls.CheckBox, tyControls.Dialogs.Find;
```

Add a second test class + its OnFind handler. Insert before `implementation`:

```pascal
  TFindWiringTest = class(TTestCase)
  private
    FFired: Boolean;
    FLastOptions: TFindOptions;
    FLastFindText: string;
    procedure HandleFind(Sender: TObject);
  published
    procedure TestFindNextFiresWithActionFlags;
  end;
```

And the implementations (before `initialization`):

```pascal
procedure TFindWiringTest.HandleFind(Sender: TObject);
begin
  FFired := True;
  FLastOptions := (Sender as TTyFindDialog).Options;
  FLastFindText := (Sender as TTyFindDialog).FindText;
end;

procedure TFindWiringTest.TestFindNextFiresWithActionFlags;
var dlg: TTyFindDialog; frm: TTyFindForm;
begin
  FFired := False;
  dlg := TTyFindDialog.Create(nil);
  try
    dlg.OnFind := @HandleFind;
    frm := dlg.BuildForm;                 // builds the form, does NOT Show it
    frm.FindEdit.Text := 'hello';
    frm.MatchCaseCheck.Checked := True;
    frm.SearchUpCheck.Checked := False;   // -> frDown set
    frm.DoFindNext;
    AssertTrue('OnFind fired', FFired);
    AssertEquals('FindText written back', 'hello', FLastFindText);
    AssertTrue('frFindNext stamped', frFindNext in FLastOptions);
    AssertFalse('frReplace cleared', frReplace in FLastOptions);
    AssertFalse('frReplaceAll cleared', frReplaceAll in FLastOptions);
    AssertTrue('frMatchCase from check', frMatchCase in FLastOptions);
    AssertTrue('frDown (searchup off)', frDown in FLastOptions);
  finally dlg.Free; end;
end;
```

Register it — change the `initialization` block to:

```pascal
initialization
  RegisterTest(TFindMapTest);
  RegisterTest(TFindWiringTest);
end.
```

- [ ] **Step 4: Build + run**

Run:
```
lazbuild tycontrols.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)"
```
Expected: build exit 0; `run` = baseline + 4; failures 0; errors 11. If the wiring test throws (e.g. an EInvalidOperation on child construction), the form built a handle-requiring path — re-check that no `SetDesigning`/`Show` is called and that children are only `Create(Self)` + `Parent := Self` + `SetBounds`.

- [ ] **Step 5: Commit**

```bash
git add source/tyControls.Dialogs.Find.pas source/tyControls.StrConsts.pas tests/test.dialogs.find.pas
git commit -m "feat(dialogs): S4 TTyFindDialog — modeless Find, KeyDown/DoFindNext seams

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: TTyReplaceDialog (Replace/Replace All share OnReplace)

**Files:**
- Modify: `source/tyControls.Dialogs.Find.pas` (add the `TTyReplaceDialog` subclass)
- Modify: `tests/test.dialogs.find.pas` (add replace wiring test)

- [ ] **Step 1: Add the `TTyReplaceDialog` declaration**

In `source/tyControls.Dialogs.Find.pas`, in the `interface`, immediately after the `TTyFindDialog` class declaration (after its `end;`, before `implementation`), add:

```pascal
  { TTyReplaceDialog — adds the Replace row + Replace/Replace All buttons. Replace
    and Replace All both fire OnReplace; the app distinguishes them via
    (frReplaceAll in Options). }
  TTyReplaceDialog = class(TTyFindDialog)
  protected
    function WantReplace: Boolean; override;
  public
    constructor Create(AOwner: TComponent); override;
  published
    property ReplaceText: string read FReplaceText write FReplaceText;
    property OnReplace: TNotifyEvent read FOnReplace write FOnReplace;
  end;
```

- [ ] **Step 2: Add the `TTyReplaceDialog` implementation**

In the `implementation`, after the `TTyFindDialog` methods (before the final `end.`), add:

```pascal
{ TTyReplaceDialog }

constructor TTyReplaceDialog.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FOptions := FOptions + [frReplace, frReplaceAll];   // LCL Replace defaults
end;

function TTyReplaceDialog.WantReplace: Boolean;
begin
  Result := True;
end;
```

- [ ] **Step 3: Write the failing replace wiring test**

In `tests/test.dialogs.find.pas`, add a third test class + its OnReplace handler. Insert before `implementation`:

```pascal
  TReplaceWiringTest = class(TTestCase)
  private
    FReplaceFired: Boolean;
    FLastOptions: TFindOptions;
    FLastReplaceText: string;
    procedure HandleReplace(Sender: TObject);
  published
    procedure TestReplaceStampsReplaceFlag;
    procedure TestReplaceAllStampsReplaceAllFlag;
    procedure TestReplaceDefaultsHaveReplaceFlags;
  end;
```

Implementations (before `initialization`):

```pascal
procedure TReplaceWiringTest.HandleReplace(Sender: TObject);
begin
  FReplaceFired := True;
  FLastOptions := (Sender as TTyReplaceDialog).Options;
  FLastReplaceText := (Sender as TTyReplaceDialog).ReplaceText;
end;

procedure TReplaceWiringTest.TestReplaceStampsReplaceFlag;
var dlg: TTyReplaceDialog; frm: TTyFindForm;
begin
  FReplaceFired := False;
  dlg := TTyReplaceDialog.Create(nil);
  try
    dlg.OnReplace := @HandleReplace;
    frm := dlg.BuildForm;
    frm.FindEdit.Text := 'a';
    frm.ReplaceEdit.Text := 'b';
    frm.DoReplace;
    AssertTrue('OnReplace fired', FReplaceFired);
    AssertEquals('ReplaceText written back', 'b', FLastReplaceText);
    AssertTrue('frReplace set', frReplace in FLastOptions);
    AssertFalse('frReplaceAll clear', frReplaceAll in FLastOptions);
    AssertFalse('frFindNext clear', frFindNext in FLastOptions);
  finally dlg.Free; end;
end;

procedure TReplaceWiringTest.TestReplaceAllStampsReplaceAllFlag;
var dlg: TTyReplaceDialog; frm: TTyFindForm;
begin
  FReplaceFired := False;
  dlg := TTyReplaceDialog.Create(nil);
  try
    dlg.OnReplace := @HandleReplace;
    frm := dlg.BuildForm;
    frm.DoReplaceAll;
    AssertTrue('OnReplace fired', FReplaceFired);
    AssertTrue('frReplaceAll set', frReplaceAll in FLastOptions);
    AssertFalse('frFindNext clear', frFindNext in FLastOptions);
    AssertFalse('frReplace clear', frReplace in FLastOptions);
  finally dlg.Free; end;
end;

procedure TReplaceWiringTest.TestReplaceDefaultsHaveReplaceFlags;
var dlg: TTyReplaceDialog;
begin
  dlg := TTyReplaceDialog.Create(nil);
  try
    AssertTrue('frDown default', frDown in dlg.Options);
    AssertTrue('frReplace default', frReplace in dlg.Options);
    AssertTrue('frReplaceAll default', frReplaceAll in dlg.Options);
  finally dlg.Free; end;
end;
```

Register — update `initialization`:

```pascal
initialization
  RegisterTest(TFindMapTest);
  RegisterTest(TFindWiringTest);
  RegisterTest(TReplaceWiringTest);
end.
```

- [ ] **Step 4: Build + run**

Run:
```
lazbuild tycontrols.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)"
```
Expected: build exit 0; `run` = baseline + 7; failures 0; errors 11.

- [ ] **Step 5: Commit**

```bash
git add source/tyControls.Dialogs.Find.pas tests/test.dialogs.find.pas
git commit -m "feat(dialogs): S4 TTyReplaceDialog — Replace/Replace All share OnReplace

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: TTyProgressDialog + progress form

**Files:**
- Create: `source/tyControls.Dialogs.Progress.pas`
- Modify: `source/tyControls.StrConsts.pas` (append `rsDlgProgressCancel`)
- Modify: `tycontrols.lpk` (new `<Item>`)
- Create: `tests/test.dialogs.progress.pas`
- Modify: `tests/tytests.lpr` (uses clause)

- [ ] **Step 1: Append the Cancel resourcestring**

In `source/tyControls.StrConsts.pas`, in the `resourcestring` block just below the S4 Find strings added in Task 2 (still before `implementation`), add:

```pascal
  rsDlgProgressCancel  = 'Cancel';
```

- [ ] **Step 2: Create the Progress unit**

Create `source/tyControls.Dialogs.Progress.pas`:

```pascal
unit tyControls.Dialogs.Progress;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Controls, Forms, LCLType,
  tyControls.Dialogs, tyControls.ProgressBar, tyControls.TyLabel,
  tyControls.Button, tyControls.StrConsts;

type
  TTyProgressDialog = class;

  { TTyProgressForm — the reusable modeless progress window owned by a
    TTyProgressDialog. Pure UI + the DoCancel seam. }
  TTyProgressForm = class(TTyDialog)
  private
    FDlg: TTyProgressDialog;
    FBar: TTyProgressBar;
    FLabel: TTyLabel;
    FCancelBtn: TTyButton;        // nil unless cancelable
    procedure CancelClick(Sender: TObject);
  protected
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
  public
    procedure Build(ACancelable: Boolean);
    procedure UpdateView(APos, AMin, AMax: Integer; const AText: string);
    // test seams:
    function Bar: TTyProgressBar;
    function StatusLabel: TTyLabel;
  end;

  { TTyProgressDialog — stateful, app-driven, modeless. The app updates it in a
    loop and calls SetProgress; SetProgress pumps the message loop so the bar
    repaints and a Cancel click is seen. OnCancel MUST NOT Free this component. }
  TTyProgressDialog = class(TComponent)
  private
    FCaption: string;
    FText: string;
    FMin, FMax, FPosition: Integer;
    FCancelable, FCancelled: Boolean;
    FOnCancel: TNotifyEvent;
    FForm: TTyProgressForm;
    FInPump: Boolean;
  public
    constructor Create(AOwner: TComponent); override;
    function BuildForm: TTyProgressForm;   // test seam: lazy build, NO Show
    procedure Show;
    procedure SetProgress(APos: Integer; const AText: string = '');
    procedure Step(ADelta: Integer = 1);
    procedure Close;
    procedure DoCancel;                    // seam: fired by the Cancel button / Esc
    property Cancelled: Boolean read FCancelled;
  published
    property Caption: string read FCaption write FCaption;
    property Text: string read FText write FText;
    property Min: Integer read FMin write FMin default 0;
    property Max: Integer read FMax write FMax default 100;
    property Position: Integer read FPosition write FPosition default 0;
    property Cancelable: Boolean read FCancelable write FCancelable default False;
    property OnCancel: TNotifyEvent read FOnCancel write FOnCancel;
  end;

implementation

{ TTyProgressForm }

procedure TTyProgressForm.Build(ACancelable: Boolean);
var r: TRect; x0, y, contentW: Integer;
begin
  r := ContentRect;
  x0 := r.Left + TyDlgPad;
  y := r.Top + TyDlgPad;
  contentW := 360;

  FLabel := TTyLabel.Create(Self);
  FLabel.Parent := Self;
  FLabel.SetBounds(x0, y, contentW, 20);
  Inc(y, 28);

  FBar := TTyProgressBar.Create(Self);
  FBar.Parent := Self;
  FBar.SetBounds(x0, y, contentW, 20);
  Inc(y, 28);

  if ACancelable then
  begin
    FCancelBtn := AddButton(rsDlgProgressCancel, mrNone);
    FCancelBtn.OnClick := @CancelClick;
  end;

  AutoSizeToContent(contentW + TyDlgPad, (y - r.Top) + TyDlgPad);
end;

procedure TTyProgressForm.UpdateView(APos, AMin, AMax: Integer; const AText: string);
begin
  if FBar = nil then Exit;
  FBar.Min := AMin;
  FBar.Max := AMax;
  FBar.Position := APos;
  FLabel.Caption := AText;
end;

procedure TTyProgressForm.CancelClick(Sender: TObject);
begin
  if FDlg <> nil then FDlg.DoCancel;
end;

procedure TTyProgressForm.KeyDown(var Key: Word; Shift: TShiftState);
begin
  if Key = VK_ESCAPE then
  begin
    if (FDlg <> nil) and FDlg.Cancelable then FDlg.DoCancel;
    Key := 0; Exit;                 // never let Esc close a progress dialog
  end;
  if Key = VK_RETURN then begin Key := 0; Exit; end;   // ignore Enter
  inherited KeyDown(Key, Shift);
end;

function TTyProgressForm.Bar: TTyProgressBar; begin Result := FBar; end;
function TTyProgressForm.StatusLabel: TTyLabel; begin Result := FLabel; end;

{ TTyProgressDialog }

constructor TTyProgressDialog.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMin := 0;
  FMax := 100;
  FPosition := 0;
end;

function TTyProgressDialog.BuildForm: TTyProgressForm;
begin
  if FForm = nil then
  begin
    FForm := TTyProgressForm.CreateNew(Self, 0);   // Owner = Self
    FForm.FDlg := Self;
    FForm.Build(FCancelable);
  end;
  FForm.Caption := FCaption;
  FForm.UpdateView(FPosition, FMin, FMax, FText);
  Result := FForm;
end;

procedure TTyProgressDialog.Show;
begin
  if csDesigning in ComponentState then Exit;
  FCancelled := False;
  BuildForm;
  FForm.Show;
end;

procedure TTyProgressDialog.SetProgress(APos: Integer; const AText: string);
begin
  if APos < FMin then APos := FMin;
  if APos > FMax then APos := FMax;
  FPosition := APos;
  if AText <> '' then FText := AText;
  // Only touch the view + pump when the form actually exists and is on screen —
  // headless (unshown) callers just clamp state, so tests never pump.
  if (FForm <> nil) and FForm.Visible then
  begin
    FForm.UpdateView(FPosition, FMin, FMax, FText);
    if not FInPump then
    begin
      FInPump := True;
      try
        Application.ProcessMessages;
      finally
        FInPump := False;
      end;
    end;
  end;
end;

procedure TTyProgressDialog.Step(ADelta: Integer);
begin
  SetProgress(FPosition + ADelta);
end;

procedure TTyProgressDialog.Close;
begin
  FCancelled := False;
  if FForm <> nil then FForm.Hide;
end;

procedure TTyProgressDialog.DoCancel;
begin
  FCancelled := True;
  if Assigned(FOnCancel) then FOnCancel(Self);
end;

end.
```

- [ ] **Step 3: Register the unit in the package**

In `tycontrols.lpk`, after the `tyControls.Dialogs.Find` `<Item>` added in Task 1 (before `</Files>`), add:

```xml
      <Item>
        <Filename Value="source/tyControls.Dialogs.Progress.pas"/>
        <UnitName Value="tyControls.Dialogs.Progress"/>
      </Item>
```

- [ ] **Step 4: Write the failing tests**

Create `tests/test.dialogs.progress.pas`:

```pascal
unit test.dialogs.progress;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, fpcunit, testregistry,
  tyControls.ProgressBar, tyControls.Dialogs.Progress;

type
  TProgressLogicTest = class(TTestCase)
  private
    FCancelFired: Boolean;
    procedure HandleCancel(Sender: TObject);
  published
    procedure TestSetProgressClamps;
    procedure TestStepAccumulates;
    procedure TestDoCancelSetsFlagAndFires;
    procedure TestCloseResetsCancelled;
    procedure TestFillRectGeometry;
  end;

implementation

procedure TProgressLogicTest.HandleCancel(Sender: TObject);
begin
  FCancelFired := True;
end;

procedure TProgressLogicTest.TestSetProgressClamps;
var dlg: TTyProgressDialog;
begin
  dlg := TTyProgressDialog.Create(nil);
  try
    dlg.Min := 0; dlg.Max := 100;
    dlg.SetProgress(150);
    AssertEquals('clamp high', 100, dlg.Position);
    dlg.SetProgress(-20);
    AssertEquals('clamp low', 0, dlg.Position);
    dlg.SetProgress(42);
    AssertEquals('in range', 42, dlg.Position);
  finally dlg.Free; end;
end;

procedure TProgressLogicTest.TestStepAccumulates;
var dlg: TTyProgressDialog;
begin
  dlg := TTyProgressDialog.Create(nil);
  try
    dlg.Min := 0; dlg.Max := 100;
    dlg.SetProgress(10);
    dlg.Step;          // +1
    dlg.Step(4);       // +4
    AssertEquals('accumulated', 15, dlg.Position);
  finally dlg.Free; end;
end;

procedure TProgressLogicTest.TestDoCancelSetsFlagAndFires;
var dlg: TTyProgressDialog;
begin
  FCancelFired := False;
  dlg := TTyProgressDialog.Create(nil);
  try
    dlg.OnCancel := @HandleCancel;
    AssertFalse('not cancelled yet', dlg.Cancelled);
    dlg.DoCancel;
    AssertTrue('cancelled flag', dlg.Cancelled);
    AssertTrue('OnCancel fired', FCancelFired);
  finally dlg.Free; end;
end;

procedure TProgressLogicTest.TestCloseResetsCancelled;
var dlg: TTyProgressDialog;
begin
  dlg := TTyProgressDialog.Create(nil);
  try
    dlg.DoCancel;
    AssertTrue('cancelled', dlg.Cancelled);
    dlg.Close;
    AssertFalse('reset by Close', dlg.Cancelled);
  finally dlg.Free; end;
end;

procedure TProgressLogicTest.TestFillRectGeometry;
var track: TRect;
begin
  track := Rect(0, 0, 100, 10);
  AssertEquals('empty at min', 0, TyProgressFillRect(track, 0, 100, 0).Right);
  AssertEquals('full at max', 100, TyProgressFillRect(track, 0, 100, 100).Right);
  AssertEquals('half at mid', 50, TyProgressFillRect(track, 0, 100, 50).Right);
end;

initialization
  RegisterTest(TProgressLogicTest);
end.
```

- [ ] **Step 5: Register the test unit**

In `tests/tytests.lpr`, change the last `uses` line (now `  test.dialogs.find;`) — replace the `;` with `,` and add:

```pascal
  test.dialogs.find,
  test.dialogs.progress;
```

- [ ] **Step 6: Build + run**

Run:
```
lazbuild tycontrols.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)"
```
Expected: build exit 0; `run` = baseline + 12; failures 0; errors 11.

- [ ] **Step 7: Commit**

```bash
git add source/tyControls.Dialogs.Progress.pas source/tyControls.StrConsts.pas tycontrols.lpk tests/test.dialogs.progress.pas tests/tytests.lpr
git commit -m "feat(dialogs): S4 TTyProgressDialog — app-driven modeless progress + Cancel

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Design-time registration

**Files:**
- Modify: `designtime/tyControls.Design.pas` (uses + RegisterComponents)

- [ ] **Step 1: Add the units to the design-time `uses`**

In `designtime/tyControls.Design.pas`, find the `uses` line ending `  tyControls.Dialogs.Color, tyControls.Dialogs.Font;`. Change the trailing `;` to `,` and append:

```pascal
  tyControls.Dialogs.Color, tyControls.Dialogs.Font,
  tyControls.Dialogs.Find, tyControls.Dialogs.Progress;
```

- [ ] **Step 2: Register the 3 components**

In the `RegisterComponents('TyControls Dialogs', [...])` call, add the new classes to the array (after `TTyFontDialog`, before the `])`):

```pascal
  RegisterComponents('TyControls Dialogs',
    [TTyMessage, TTyInputDialog, TTyPasswordDialog, TTyTextDialog,
     TTySelectValueDialog, TTySelectPathDialog,
     TTyColorDialog, TTyFontDialog,
     TTyFindDialog, TTyReplaceDialog, TTyProgressDialog]);
```

- [ ] **Step 3: Build the design-time package**

Run:
```
lazbuild tycontrols.lpk && lazbuild tycontrols_dt.lpk
```
Expected: both exit 0. (No new `<Item>` in `tycontrols_dt.lpk` — the runtime units reach it via the `tycontrols` dependency.)

- [ ] **Step 4: Run the tests (guard against a regression)**

Run:
```
./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)"
```
Expected: unchanged `run` = baseline + 12; failures 0; errors 11.

- [ ] **Step 5: Commit**

```bash
git add designtime/tyControls.Design.pas
git commit -m "feat(dialogs): S4 register Find/Replace/Progress on the Dialogs palette

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 6: i18n — zh_CN translations

**Files:**
- Modify: `languages/tycontrols.strconsts.zh_CN.po`

- [ ] **Step 1: Append zh_CN entries**

In `languages/tycontrols.strconsts.zh_CN.po`, at the end of the file, add one entry per new resourcestring (reference id is the fully-lowercased `tycontrols.strconsts.<rsname>`; separate entries with a blank line):

```po
#: tycontrols.strconsts.rsdlgfindwhat
msgid "Find what:"
msgstr "查找内容："

#: tycontrols.strconsts.rsdlgreplacewith
msgid "Replace with:"
msgstr "替换为："

#: tycontrols.strconsts.rsdlgmatchcase
msgid "Match case"
msgstr "区分大小写"

#: tycontrols.strconsts.rsdlgwholeword
msgid "Whole word"
msgstr "全字匹配"

#: tycontrols.strconsts.rsdlgsearchup
msgid "Search up"
msgstr "向上查找"

#: tycontrols.strconsts.rsdlgfindnext
msgid "Find Next"
msgstr "查找下一个"

#: tycontrols.strconsts.rsdlgreplace
msgid "Replace"
msgstr "替换"

#: tycontrols.strconsts.rsdlgreplaceall
msgid "Replace All"
msgstr "全部替换"

#: tycontrols.strconsts.rsdlgfindclose
msgid "Close"
msgstr "关闭"

#: tycontrols.strconsts.rsdlgprogresscancel
msgid "Cancel"
msgstr "取消"
```

- [ ] **Step 2: Regenerate the base `.pot` if the project workflow requires it**

If a `languages/tycontrols.strconsts.pot` exists, rebuild it so the new msgids are present (the runtime package's i18n is enabled). Run:
```
lazbuild tycontrols.lpk
```
Lazbuild regenerates the package `.pot` from `resourcestring` when i18n is on. Verify the new ids appear:
```
grep -i "rsdlgfindwhat\|rsdlgprogresscancel" languages/tycontrols.strconsts.pot
```
Expected: both ids present. (If there is no `.pot` under `languages/`, skip — the `.po` edit is sufficient.)

- [ ] **Step 3: Commit**

```bash
git add languages/tycontrols.strconsts.zh_CN.po languages/tycontrols.strconsts.pot
git commit -m "i18n(dialogs): S4 zh_CN strings for Find/Replace/Progress

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```
(If no `.pot` was regenerated, drop it from the `git add`.)

---

## Task 7: Docs, README, final verification, finish

**Files:**
- Modify: `docs/controls/dialogs.md`
- Modify: `README.md`, `README.en.md`

- [ ] **Step 1: Document the modeless family in `docs/controls/dialogs.md`**

Append a new section (adjust the heading number to follow the last existing section):

````markdown
## Modeless dialogs — Find / Replace / Progress (S4)

Unlike the modal dialogs above, these are **non-modal**: they show with `Show`, stay open, and drive
work through events. Each is a non-visual component that owns and reuses its window.

### Find / Replace

```pascal
uses tyControls.Dialogs.Find;

// once, e.g. in FormCreate:
FindDlg := TTyFindDialog.Create(Self);
FindDlg.OnFind := @DoFind;

procedure TForm1.DoFind(Sender: TObject);
var d: TTyFindDialog;
begin
  d := Sender as TTyFindDialog;
  // search Memo1 for d.FindText using d.Options (frMatchCase, frWholeWord, frDown, ...)
end;

// to open it (modeless — returns immediately):
FindDlg.Execute;
```

`TTyReplaceDialog` adds `ReplaceText` + `OnReplace`. **Replace and Replace All both fire `OnReplace`** —
tell them apart with `frReplaceAll in d.Options`. `Options` defaults to `[frDown]` (search down);
`TTyReplaceDialog` also defaults `frReplace, frReplaceAll`.

### Progress

```pascal
uses tyControls.Dialogs.Progress;

Prog := TTyProgressDialog.Create(Self);
Prog.Caption := 'Working…';
Prog.Min := 0; Prog.Max := N; Prog.Cancelable := True;
Prog.OnCancel := @HandleCancel;   // MUST NOT Free Prog — just set a flag / call Close
Prog.Show;
try
  for i := 0 to N - 1 do
  begin
    if Prog.Cancelled then Break;
    DoWork(i);
    Prog.SetProgress(i + 1, Format('Item %d of %d', [i + 1, N]));  // repaints + pumps
  end;
finally
  Prog.Close;
end;
```

`SetProgress` pumps the message loop so the bar repaints and a Cancel click is seen. It is determinate
only (no marquee).
````

- [ ] **Step 2: Extend the README Dialogs bullet**

In `README.en.md`, find the Dialogs feature bullet (the S3 one mentioning color + font pickers) and extend it to mention the modeless family, e.g. append:

```
 modeless Find/Replace (`TTyFindDialog`/`TTyReplaceDialog`, LCL `TFindDialog` parity) and a
Progress dialog (`TTyProgressDialog`).
```

Make the equivalent edit to the corresponding bullet in `README.md` (Chinese):

```
以及非模态查找/替换（`TTyFindDialog`/`TTyReplaceDialog`，对齐 LCL `TFindDialog`）和进度对话框（`TTyProgressDialog`）。
```

(Match the exact surrounding wording/format of the existing bullet in each file.)

- [ ] **Step 3: Full clean build + test run**

Run:
```
lazbuild tycontrols.lpk && lazbuild tycontrols_dt.lpk && lazbuild tests/tytests.lpi && ./tests/tytests.exe -a --format=plain 2>&1 | grep -iE "Number of (run|failures|errors)"
```
Expected: all builds exit 0; `run` = baseline + 12; **failures 0; errors 11**. If failures > 0, use `superpowers:systematic-debugging` — do NOT paper over it.

- [ ] **Step 4: Confirm the demo still builds (do NOT edit demo files)**

Run:
```
lazbuild examples/demo/demo.lpi
```
Expected: exit 0. (S4 adds no demo changes; this only guards against an accidental package break.)

- [ ] **Step 5: Commit docs**

```bash
git add docs/controls/dialogs.md README.md README.en.md
git commit -m "docs(dialogs): S4 modeless Find/Replace + Progress usage

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

- [ ] **Step 6: Finish the branch**

Use `superpowers:finishing-a-development-branch`. Verify tests pass (Step 3), then present the merge options. The prior S-phases merged locally (fast-forward) to `main`; do NOT push (the user drives pushes).

---

## Post-implementation notes (for the final adversarial review)

- **GUI-only (real-machine eyeball, not headless):** the modeless `Show`, live bar repaint under the
  `SetProgress` loop, real Enter/Esc keystrokes, button-bar layout/spacing, and the `Application.ProcessMessages`
  Cancel path. Flag these as needing a real Lazarus run.
- **Re-verify against the spec:** action-flag stamping (`frFindNext`/`frReplace`/`frReplaceAll`), `Options`
  defaults (`[frDown]` / `+[frReplace,frReplaceAll]`), csDesigning guards on `Execute`/`Show`, the
  `FInPump` guard, and the "`OnCancel`/`OnFind`/`OnReplace` must not `Free`" documentation.
- **i18n / README pre-merge checklist** (memory `pre-merge-checklist`): confirm both README variants + the
  zh_CN `.po` were updated (Tasks 6–7). No demo strings are added, so `examples/demo/languages/` is untouched.
- **Deliberate deviation from spec §A — `FClosing` guard omitted (YAGNI):** the spec lists a `FClosing`
  re-entrant-close guard (mirroring `TTyDropdownPopup`) and an optional defensive `OnClose CloseAction := caHide`.
  In this design the only close paths are the explicit `Hide` (Close button / Esc) and the title-bar X
  (→ `TForm.Close` → default `caHide`, since the owned form is never the main form). There is **no
  `OnDeactivate`-driven auto-close** (which is what makes `TTyDropdownPopup` need `FClosing`), so there is
  no re-entrancy source — the guard and the explicit `OnClose` are omitted as dead defense. Reuse still
  works: the form hides and is re-shown on the next `Execute`/`Show`. If a future change adds an auto-close
  trigger, add the `FClosing` guard then. The reviewer should confirm this reasoning holds, not treat the
  omission as an oversight.
```
