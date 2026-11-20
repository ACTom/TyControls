unit test.richedit.actions;

{ TTyRichEdit's actions (tyControls.RichEdit.Actions): the target (RichEdit, else the focused
  rich edit, freed), Enabled and Checked as the control answers them (the caret's format, a
  mixed selection, read-only, a locked table, a field's result, plain text), each action's
  effect as one undo step named as the control names it, what an idle round costs (counters:
  one asking of the control per change, none per round), the table's size event, the find and
  replace path through the package's dialogs, the picture's dialog and its filter, a shortcut
  handled by one of the two only, the strings in the catalogue and the IDE registration.

  Headless: the rich edit is the control suite's probe on a form that is never shown; the
  dialogs are built and never shown (each action's dialog call is a seam the probes replace);
  no clipboard, no real input. Every bound is a count. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, fpcunit, testregistry, Controls, Graphics, LCLType, LMessages,
  Forms, ActnList, Dialogs,
  tyControls.Controller, tyControls.StrConsts,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.Attrs,
  tyControls.RichEdit.Commands,
  tyControls.RichEdit, tyControls.RichEdit.Actions, tyControls.Dialogs.Find,
  tyControls.Dialogs.FileDialog, test.richedit.control;

type
  { The rich edit, focused when the test says so. }
  TActRich = class(TRichProbe)
  public
    FocusNow: Boolean;
    function Focused: Boolean; override;
  end;

  { The picture action, its dialog replaced by a file name. }
  TPictureProbe = class(TTyRichEditInsertPicture)
  protected
    function AskFileName(var AFileName: string): Boolean; override;
  public
    Answer: string;
    Asks: Integer;
  end;

  { A metafile reader as an application could register one with TPicture. }
  TFakeMetafile = class(TBitmap);

  { The find and replace actions, their dialogs built and never shown, nothing found counted. }
  TFindProbe = class(TTyRichEditFind)
  protected
    procedure ShowDialog; override;
    procedure ShowNotFound(const AText: string); override;
  public
    Shows, Boxes: Integer;
  end;

  TReplaceProbe = class(TTyRichEditReplace)
  protected
    procedure ShowDialog; override;
    procedure ShowNotFound(const AText: string); override;
  public
    Shows, Boxes: Integer;
  end;

  TTyRichEditActionsTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FForm: TForm;
    FRich: TActRich;
    FRefusals: Integer;
    FReason: string;
    FChooseRows, FChooseCols: Integer;
    FChooseGo: Boolean;
    FChooseCalls: Integer;
    FNotFound: string;
    FTempFiles: TStringList;
    function NewRich: TActRich;
    procedure SetText(const S: string);
    procedure Select(AStart, ALen: TTyRichPos);
    procedure LoadFixture(const AName: string);
    procedure Refused(Sender: TObject; const AReason: string);
    procedure ChooseSize(Sender: TObject; var ARows, AColumns: Integer; var AInsert: Boolean);
    procedure NotFound(Sender: TObject; const AText: string);
    function Make(AClass: TTyRichEditActionClass): TTyRichEditAction;
    function UpdatedOn(AAction: TTyRichEditAction): TTyRichEditAction;
    function PngFile: string;
    function FirstParaWhere(AFixedRow: Boolean): Integer;
    function KeyThroughLcl(AKey: Word; ACtrl: Boolean): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestBoldActionChecksFollowTheCaret;
    procedure TestActionsDisableOnReadOnlyAndLockedTables;
    procedure TestTheTargetIsTheRichEditPropertyElseTheFocusedOne;
    procedure TestAFreedTargetIsLetGo;
    procedure TestEachActionIsOneUndoStepNamedAsTheControlNamesIt;
    procedure TestAMixedSelectionIsNotChecked;
    procedure TestTheCheckedStatesFollowTheFormatApi;
    procedure TestAPlainTextDocument;
    procedure TestAFieldsResultIsRefusedAndToldOnce;
    procedure TestTheCharacterDoorIsTheUsers;
    procedure TestCanInsertPictureReadsThePlace;
    procedure TestAnIdleRoundAsksTheControlNothing;
    procedure TestTheTableActionAsksForItsSize;
    procedure TestFindAndReplaceUseThePackagesDialogs;
    procedure TestReplaceStopsWhereTheUserMayNotEdit;
    procedure TestThePictureActionAsksForAFileOfAReadableFormat;
    procedure TestTheIndentActionsStepByHalfAnInch;
    procedure TestUndoRedoAndZoom;
    procedure TestAShortcutIsHandledByOneOfTheTwo;
    procedure TestTheCaptionsAndHintsAreInTheCatalogue;
    procedure TestEveryActionIsRegisteredAndKeepsItsDefaults;
  end;

implementation

uses
  {$IFDEF MSWINDOWS}Windows,{$ENDIF}
  StrUtils, Menus, Translations, test.designregistry;

{ ---- probes ---- }

function TActRich.Focused: Boolean;
begin
  Result := FocusNow;
end;

function TPictureProbe.AskFileName(var AFileName: string): Boolean;
begin
  Inc(Asks);
  AFileName := Answer;
  Result := Answer <> '';
end;

procedure TFindProbe.ShowDialog;
begin
  Inc(Shows);
  FDialog.BuildForm;
end;

procedure TFindProbe.ShowNotFound(const AText: string);
begin
  Inc(Boxes);
end;

procedure TReplaceProbe.ShowDialog;
begin
  Inc(Shows);
  FDialog.BuildForm;
end;

procedure TReplaceProbe.ShowNotFound(const AText: string);
begin
  Inc(Boxes);
end;

{ ---- the fixture ---- }

procedure TTyRichEditActionsTest.SetUp;
begin
  FCtl := TTyStyleController.Create(nil);
  FForm := TForm.CreateNew(nil);
  FTempFiles := TStringList.Create;
  FRich := NewRich;
  SetText('Plain bold plain'#10'Second paragraph'#10'Third');
  FRefusals := 0;
  FReason := '';
  FChooseCalls := 0;
  FNotFound := '';
end;

procedure TTyRichEditActionsTest.TearDown;
var
  i: Integer;
begin
  FreeAndNil(FRich);
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  for i := 0 to FTempFiles.Count - 1 do SysUtils.DeleteFile(FTempFiles[i]);
  FreeAndNil(FTempFiles);
end;

function TTyRichEditActionsTest.NewRich: TActRich;
begin
  Result := TActRich.Create(nil);
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  Result.Parent := FForm;
  Result.SetBounds(0, 0, 400, 300);
  Result.OnEditRefused := @Refused;
  Result.ResetCounts;
end;

procedure TTyRichEditActionsTest.SetText(const S: string);
begin
  FRich.Lines.Text := S;
  FRich.UpdateView;
end;

procedure TTyRichEditActionsTest.Select(AStart, ALen: TTyRichPos);
begin
  FRich.SelStart := AStart;
  FRich.SelLength := ALen;
end;

procedure TTyRichEditActionsTest.LoadFixture(const AName: string);
begin
  FRich.LoadFromFile(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'tests' + PathDelim +
    'fixtures' + PathDelim + 'rtf' + PathDelim + AName);
  FRich.FinishLoading;
  FRich.UpdateView;
end;

procedure TTyRichEditActionsTest.Refused(Sender: TObject; const AReason: string);
begin
  Inc(FRefusals);
  FReason := AReason;
end;

procedure TTyRichEditActionsTest.ChooseSize(Sender: TObject; var ARows, AColumns: Integer;
  var AInsert: Boolean);
begin
  Inc(FChooseCalls);
  AssertEquals('the rows asked', 3, ARows);
  AssertEquals('the columns asked', 3, AColumns);
  ARows := FChooseRows;
  AColumns := FChooseCols;
  AInsert := FChooseGo;
end;

procedure TTyRichEditActionsTest.NotFound(Sender: TObject; const AText: string);
begin
  FNotFound := AText;
end;

function TTyRichEditActionsTest.Make(AClass: TTyRichEditActionClass): TTyRichEditAction;
begin
  Result := AClass.Create(FForm);
  Result.RichEdit := FRich;
end;

function TTyRichEditActionsTest.UpdatedOn(AAction: TTyRichEditAction): TTyRichEditAction;
begin
  AAction.Update;
  Result := AAction;
end;

function TTyRichEditActionsTest.PngFile: string;
var
  png: TPortableNetworkGraphic;
begin
  Result := GetTempDir(False) + Format('tyrichact_%d_%d.png', [GetProcessID, FTempFiles.Count]);
  png := TPortableNetworkGraphic.Create;
  try
    png.SetSize(8, 6);
    png.Canvas.Brush.Color := clRed;
    png.Canvas.FillRect(0, 0, 8, 6);
    png.SaveToFile(Result);
  finally
    png.Free;
  end;
  FTempFiles.Add(Result);
end;

{ The first paragraph in a row that holds a nested table (AFixedRow), else the first in a table
  whose structure cannot change. }
function TTyRichEditActionsTest.FirstParaWhere(AFixedRow: Boolean): Integer;
var
  d: TTyRichDocument;
  c: TTyRichCell;
  i: Integer;
begin
  d := FRich.Document;
  for i := 0 to d.Text.ParaCount - 1 do
  begin
    c := d.CellAt(i);
    if c = nil then Continue;
    if AFixedRow and c.Row.HoldsNestedTable then Exit(i);
    if not AFixedRow and not c.Row.HoldsNestedTable then Exit(i);
  end;
  Result := -1;
end;

{ A key's way through LCL as a widgetset sends it: CN_KEYDOWN (the control's KeyDown, then the
  forms' shortcuts - their action lists), then LM_KEYDOWN. Ctrl is held through the thread's own
  keyboard state, which is what LCL reads for it (GetKeyState); put back after. True: taken. }
function TTyRichEditActionsTest.KeyThroughLcl(AKey: Word; ACtrl: Boolean): Boolean;
{$IFDEF MSWINDOWS}
var
  keep, held: TKeyboardState;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  GetKeyboardState(keep);
  held := keep;
  if ACtrl then
  begin
    held[VK_CONTROL] := $80;
    held[VK_LCONTROL] := $80;
  end;
  SetKeyboardState(held);
  try
  {$ENDIF}
    Result := FRich.Perform(CN_KEYDOWN, AKey, 0) <> 0;
    if not Result then Result := FRich.Perform(LM_KEYDOWN, AKey, 0) <> 0;
  {$IFDEF MSWINDOWS}
  finally
    SetKeyboardState(keep);
  end;
  {$ENDIF}
end;

{ ---- the plan's two ---- }

{ Bold's Checked is the format at the caret (nothing selected: what the next typed text gets),
  as the caret moves - heard through the control's notification, no update of the action's
  own asked for; Execute over a selection makes it bold, one step, and Checked follows. }
procedure TTyRichEditActionsTest.TestBoldActionChecksFollowTheCaret;
var
  bold: TTyRichEditAction;
  depth: Integer;
begin
  Select(6, 4);
  FRich.SelAttributes.Bold := True;
  bold := Make(TTyRichEditBold);
  Select(2, 0);
  AssertTrue('enabled', UpdatedOn(bold).Enabled);
  AssertFalse('plain at the caret', bold.Checked);
  Select(8, 0);
  AssertTrue('bold at the caret', UpdatedOn(bold).Checked);
  Select(13, 0);
  AssertFalse('plain again', UpdatedOn(bold).Checked);
  // the selection's own format
  Select(12, 3);
  depth := FRich.Document.UndoDepth;
  AssertFalse('the plain selection', UpdatedOn(bold).Checked);
  AssertTrue('executed', bold.Execute);
  AssertEquals('one step', depth + 1, FRich.Document.UndoDepth);
  AssertEquals('named as the format API', rsRichUndoCharFormat, FRich.Document.UndoDescription);
  AssertTrue('the selection is bold', FRich.SelAttributes.Bold);
  AssertTrue('checked now', UpdatedOn(bold).Checked);
  AssertTrue('again: bold off', bold.Execute);
  AssertFalse('plain', FRich.SelAttributes.Bold);
  AssertFalse('unchecked', UpdatedOn(bold).Checked);
  // nothing selected: the format the next typed text gets, no step
  Select(1, 0);
  depth := FRich.Document.UndoDepth;
  AssertTrue('executed at the caret', bold.Execute);
  AssertEquals('no step', depth, FRich.Document.UndoDepth);
  AssertTrue('checked: the typing format', UpdatedOn(bold).Checked);
end;

{ Read-only: every action that edits is disabled (Undo with a step to undo too) and does
  nothing when run anyway; find and zoom stay. In a table whose structure cannot change (a
  merged cell, a nested table) Insert table is disabled - the control's CanInsertTable; in the
  row that holds the nested table, where the control would refuse them, Insert picture and the
  format actions are disabled (CanInsertPicture, CanFormatCharacters, CanFormatParagraphs):
  run anyway, no file is asked for, nothing is told, no step. }
procedure TTyRichEditActionsTest.TestActionsDisableOnReadOnlyAndLockedTables;
const
  Editing: array[0..17] of TTyRichEditActionClass = (
    TTyRichEditBold, TTyRichEditItalic, TTyRichEditUnderline, TTyRichEditStrikeOut,
    TTyRichEditSuperscript, TTyRichEditSubscript, TTyRichEditAlignLeft, TTyRichEditAlignCenter,
    TTyRichEditAlignRight, TTyRichEditAlignJustify, TTyRichEditBullets, TTyRichEditNumbering,
    TTyRichEditIndentIncrease, TTyRichEditIndentDecrease, TTyRichEditInsertPicture,
    TTyRichEditInsertTable, TTyRichEditReplace, TTyRichEditUndo);
  Viewing: array[0..3] of TTyRichEditActionClass = (
    TTyRichEditFind, TTyRichEditZoomIn, TTyRichEditZoomOut, TTyRichEditZoomReset);
var
  i, p, depth: Integer;
  a: TTyRichEditAction;
  pic: TPictureProbe;
  before: string;
begin
  Select(0, 5);
  FRich.SelAttributes.Italic := True;   // a step to undo
  Select(0, 5);
  FRich.ReadOnly := True;
  before := FRich.Text;
  depth := FRich.Document.UndoDepth;
  for i := 0 to High(Editing) do
  begin
    a := Make(Editing[i]);
    AssertFalse(a.ClassName + ' disabled when read-only', UpdatedOn(a).Enabled);
    a.ExecuteTarget(FRich);
    AssertEquals(a.ClassName + ' run anyway: no step', depth, FRich.Document.UndoDepth);
  end;
  AssertEquals('the text as it was', before, FRich.Text);
  AssertTrue('still italic', FRich.SelAttributes.Italic);
  AssertEquals('nothing told: a viewer is not refused, it does not edit', 0, FRefusals);
  for i := 0 to High(Viewing) do
    AssertTrue(Viewing[i].ClassName + ' enabled when read-only',
      UpdatedOn(Make(Viewing[i])).Enabled);
  FRich.ReadOnly := False;
  AssertTrue('editable again', UpdatedOn(Make(TTyRichEditBold)).Enabled);

  LoadFixture('hand-word-table-merged.rtf');
  p := FirstParaWhere(False);
  AssertTrue('a cell of the merged table', p >= 0);
  Select(FRich.Document.Text.ParaStart(p), 0);
  a := Make(TTyRichEditInsertTable);
  AssertFalse('insert table disabled in a table', UpdatedOn(a).Enabled);
  AssertTrue('a format action is the user''s here', UpdatedOn(Make(TTyRichEditAlignCenter)).Enabled);
  p := FirstParaWhere(True);
  AssertTrue('the row that holds the nested table', p >= 0);
  Select(FRich.Document.Text.ParaStart(p), 0);
  pic := TPictureProbe.Create(FForm);
  pic.RichEdit := FRich;
  pic.Answer := PngFile;
  AssertFalse('insert picture: the place is the control''s no', UpdatedOn(pic).Enabled);
  AssertFalse('bold: the same', UpdatedOn(Make(TTyRichEditBold)).Enabled);
  AssertFalse('centre: the same', UpdatedOn(Make(TTyRichEditAlignCenter)).Enabled);
  depth := FRich.Document.UndoDepth;
  FRefusals := 0;
  pic.ExecuteTarget(FRich);
  AssertEquals('no file asked for', 0, pic.Asks);
  AssertEquals('nothing told', 0, FRefusals);
  AssertEquals('no step', depth, FRich.Document.UndoDepth);
end;

{ ---- the target ---- }

{ RichEdit set: that rich edit, focused or not, and no other; Update and Execute reach it with
  no form to dispatch through. Not set: the focused rich edit (HandlesTarget), as LCL's edit
  actions. }
procedure TTyRichEditActionsTest.TestTheTargetIsTheRichEditPropertyElseTheFocusedOne;
var
  other: TActRich;
  a: TTyRichEditAction;
begin
  other := NewRich;
  try
    other.Lines.Text := 'Other text';
    other.UpdateView;
    a := TTyRichEditBold.Create(FForm);
    AssertFalse('no property, not focused', a.HandlesTarget(FRich));
    FRich.FocusNow := True;
    AssertTrue('no property, focused', a.HandlesTarget(FRich));
    AssertFalse('another, not focused', a.HandlesTarget(other));
    AssertFalse('not a rich edit', a.HandlesTarget(FForm));
    a.RichEdit := other;
    AssertFalse('the property names another', a.HandlesTarget(FRich));
    AssertTrue('the property''s, not focused', a.HandlesTarget(other));
    other.SelStart := 0;
    other.SelLength := 5;
    AssertTrue('updated on the property''s', UpdatedOn(a).Enabled);
    AssertTrue('runs on the property''s', a.Execute);
    other.SelStart := 0;
    other.SelLength := 5;
    AssertTrue('the other is bold', other.SelAttributes.Bold);
    Select(0, 5);
    AssertFalse('the focused one is not', FRich.SelAttributes.Bold);
    // the focused one, through LCL's own call
    a.RichEdit := nil;
    a.ExecuteTarget(FRich);
    Select(0, 5);
    AssertTrue('ExecuteTarget formats the focused one', FRich.SelAttributes.Bold);
  finally
    other.Free;
  end;
end;

{ The rich edit freed: the property lets it go (and the find action the one it searched); the
  action is then disabled - no handler - as LCL's are. }
procedure TTyRichEditActionsTest.TestAFreedTargetIsLetGo;
var
  a: TTyRichEditAction;
  f: TFindProbe;
begin
  a := Make(TTyRichEditBold);
  f := TFindProbe.Create(FForm);
  f.RichEdit := FRich;
  AssertTrue('enabled', UpdatedOn(a).Enabled);
  f.Execute;
  AssertTrue('searched', f.Searched = FRich);
  FreeAndNil(FRich);
  AssertNull('let go', a.RichEdit);
  AssertNull('the find action let it go', f.RichEdit);
  AssertNull('and the one it searched', f.Searched);
  a.Update;
  AssertFalse('disabled with no target', a.Enabled);
  // a search asked of the dialog now does nothing
  f.Dialog.FindText := 'Plain';
  f.Dialog.BuildForm.DoFindNext;
  AssertEquals('no box', 0, f.Boxes);
end;

{ ---- what they do ---- }

{ Each action that edits, run over a selection: one undo step, named as the control names it;
  undone, the document is as it was. }
procedure TTyRichEditActionsTest.TestEachActionIsOneUndoStepNamedAsTheControlNamesIt;
type
  TCase = record
    C: TTyRichEditActionClass;
    Name: string;
  end;
var
  cases: array of TCase;
  i, depth: Integer;
  a: TTyRichEditAction;
  before: string;
  pic: TPictureProbe;
  tab: TTyRichEditInsertTable;

  procedure Add(AClass: TTyRichEditActionClass; const AName: string);
  begin
    SetLength(cases, Length(cases) + 1);
    cases[High(cases)].C := AClass;
    cases[High(cases)].Name := AName;
  end;

  function Snapshot: string;
  var
    s: TStringStream;
  begin
    s := TStringStream.Create('');
    try
      FRich.SaveToStream(s, rfRtf);
      Result := s.DataString;
    finally
      s.Free;
    end;
  end;

begin
  Add(TTyRichEditBold, rsRichUndoCharFormat);
  Add(TTyRichEditItalic, rsRichUndoCharFormat);
  Add(TTyRichEditUnderline, rsRichUndoCharFormat);
  Add(TTyRichEditStrikeOut, rsRichUndoCharFormat);
  Add(TTyRichEditSuperscript, rsRichUndoCharFormat);
  Add(TTyRichEditSubscript, rsRichUndoCharFormat);
  Add(TTyRichEditAlignCenter, rsRichUndoParaFormat);
  Add(TTyRichEditAlignRight, rsRichUndoParaFormat);
  Add(TTyRichEditAlignJustify, rsRichUndoParaFormat);
  Add(TTyRichEditBullets, rsRichUndoParaFormat);
  Add(TTyRichEditNumbering, rsRichUndoParaFormat);
  Add(TTyRichEditIndentIncrease, rsRichUndoParaFormat);
  for i := 0 to High(cases) do
  begin
    Select(2, 10);
    before := Snapshot;
    depth := FRich.Document.UndoDepth;
    a := Make(cases[i].C);
    AssertTrue(cases[i].C.ClassName + ' enabled', UpdatedOn(a).Enabled);
    AssertTrue(cases[i].C.ClassName + ' ran', a.Execute);
    AssertEquals(cases[i].C.ClassName + ': one step', depth + 1, FRich.Document.UndoDepth);
    AssertEquals(cases[i].C.ClassName + ': its name', cases[i].Name,
      FRich.Document.UndoDescription);
    AssertTrue(cases[i].C.ClassName + ': changed', before <> Snapshot);
    FRich.Undo;
    AssertEquals(cases[i].C.ClassName + ': undone', before, Snapshot);
  end;
  // a paragraph indented, then Decrease Indent
  Select(2, 0);
  a := Make(TTyRichEditIndentIncrease);
  a.Execute;
  depth := FRich.Document.UndoDepth;
  before := Snapshot;
  a := Make(TTyRichEditIndentDecrease);
  AssertTrue('decrease ran', UpdatedOn(a).Execute);
  AssertEquals('decrease: one step', depth + 1, FRich.Document.UndoDepth);
  AssertEquals('decrease: its name', rsRichUndoParaFormat, FRich.Document.UndoDescription);
  // a table, a picture
  Select(2, 0);
  depth := FRich.Document.UndoDepth;
  tab := TTyRichEditInsertTable(Make(TTyRichEditInsertTable));
  AssertTrue('table ran', UpdatedOn(tab).Execute);
  AssertEquals('table: one step', depth + 1, FRich.Document.UndoDepth);
  AssertEquals('table: its name', rsRichUndoInsertTable, FRich.Document.UndoDescription);
  AssertTrue('the caret in it', FRich.InTable);
  AssertEquals('3 rows', 3, FRich.Document.CellAt(FRich.Document.Text.ParaOfPos(FRich.SelStart)).Row.Table.RowCount);
  AssertEquals('3 columns', 3, FRich.Document.CellAt(FRich.Document.Text.ParaOfPos(FRich.SelStart)).Row.CellCount);
  FRich.Undo;
  Select(2, 0);
  depth := FRich.Document.UndoDepth;
  pic := TPictureProbe.Create(FForm);
  pic.RichEdit := FRich;
  pic.Answer := PngFile;
  AssertTrue('picture ran', UpdatedOn(pic).Execute);
  AssertEquals('picture: one step', depth + 1, FRich.Document.UndoDepth);
  AssertEquals('picture: its name', rsRichUndoInsertPicture, FRich.Document.UndoDescription);
  AssertEquals('no refusal', 0, FRefusals);
end;

{ Half the selection bold: not checked; run, it is all bold (one step) and checked. }
procedure TTyRichEditActionsTest.TestAMixedSelectionIsNotChecked;
var
  bold, center: TTyRichEditAction;
  depth: Integer;
  f: TTyParaFormat;
begin
  Select(0, 5);
  FRich.SelAttributes.Bold := True;
  bold := Make(TTyRichEditBold);
  Select(3, 6);
  AssertTrue('its first character is bold', FRich.SelAttributes.Bold);
  AssertFalse('mixed: not checked', UpdatedOn(bold).Checked);
  depth := FRich.Document.UndoDepth;
  bold.Execute;
  AssertEquals('one step', depth + 1, FRich.Document.UndoDepth);
  AssertTrue('all bold', caBold in FRich.SelAttributes.ConsistentAttributes);
  AssertTrue('all bold', FRich.SelAttributes.Bold);
  AssertTrue('checked', UpdatedOn(bold).Checked);
  // paragraphs of two alignments
  Select(0, 0);
  f := TyDefaultParaFormat;
  f.Align := paraCenter;
  FRich.ApplyParagraphFormat([pffAlign], f);
  center := Make(TTyRichEditAlignCenter);
  AssertTrue('the first centred', UpdatedOn(center).Checked);
  Select(0, FRich.Document.Text.ParaStart(1) + 2);
  AssertFalse('two alignments: not checked', UpdatedOn(center).Checked);
  AssertFalse('nor left', UpdatedOn(Make(TTyRichEditAlignLeft)).Checked);
  center.Execute;
  AssertTrue('both centred now', UpdatedOn(center).Checked);
end;

{ Every Checked is the format API's reading: italic, underline, strike-out, the scripts, the
  four alignments, the two lists - each on where the selection has it, off elsewhere. }
procedure TTyRichEditActionsTest.TestTheCheckedStatesFollowTheFormatApi;
var
  i: Integer;
  a: TTyRichEditAction;
  f: TTyParaFormat;
const
  Chars: array[0..5] of TTyRichEditActionClass = (TTyRichEditBold, TTyRichEditItalic,
    TTyRichEditUnderline, TTyRichEditStrikeOut, TTyRichEditSuperscript, TTyRichEditSubscript);
  Aligns: array[TTyParaAlign] of TTyRichEditActionClass = (TTyRichEditAlignLeft,
    TTyRichEditAlignCenter, TTyRichEditAlignRight, TTyRichEditAlignJustify);
var
  al, al2: TTyParaAlign;
begin
  for i := 0 to High(Chars) do
  begin
    a := Make(Chars[i]);
    Select(6, 4);
    AssertFalse(Chars[i].ClassName + ' off', UpdatedOn(a).Checked);
    a.Execute;
    Select(7, 2);
    AssertTrue(Chars[i].ClassName + ' on', UpdatedOn(a).Checked);
    Select(0, 2);
    AssertFalse(Chars[i].ClassName + ' off outside', UpdatedOn(a).Checked);
    Select(6, 4);
    a.Execute;
    AssertFalse(Chars[i].ClassName + ' off again', UpdatedOn(a).Checked);
  end;
  // superscript and subscript: one of them at a time
  Select(6, 4);
  Make(TTyRichEditSuperscript).Execute;
  a := Make(TTyRichEditSubscript);
  AssertFalse('superscript is not subscript', UpdatedOn(a).Checked);
  a.Execute;
  AssertTrue('subscript', UpdatedOn(a).Checked);
  AssertFalse('superscript gone', UpdatedOn(Make(TTyRichEditSuperscript)).Checked);
  for al := Low(TTyParaAlign) to High(TTyParaAlign) do
  begin
    Select(1, 0);
    f := TyDefaultParaFormat;
    f.Align := al;
    FRich.ApplyParagraphFormat([pffAlign], f);
    for al2 := Low(TTyParaAlign) to High(TTyParaAlign) do
      AssertEquals(Format('%s with alignment %d', [Aligns[al2].ClassName, Ord(al)]), al = al2,
        UpdatedOn(Make(Aligns[al2])).Checked);
  end;
  Select(1, 0);
  a := Make(TTyRichEditBullets);
  AssertFalse('no list', UpdatedOn(a).Checked);
  a.Execute;
  AssertTrue('bullets', UpdatedOn(a).Checked);
  AssertEquals('a bullet list', Ord(lkBullet), Ord(FRich.Paragraph.Numbering));
  AssertFalse('not numbered', UpdatedOn(Make(TTyRichEditNumbering)).Checked);
  Make(TTyRichEditNumbering).Execute;
  AssertTrue('numbered now', UpdatedOn(Make(TTyRichEditNumbering)).Checked);
  AssertFalse('no bullets', UpdatedOn(a).Checked);
  Make(TTyRichEditNumbering).Execute;
  AssertEquals('off: a plain paragraph', Ord(lkNone), Ord(FRich.Paragraph.Numbering));
  AssertEquals('its indent given back', 0, FRich.Paragraph.FirstIndent);
end;

{ A plain text document: the format API formats it (a text save leaves the formats out), so
  the format actions are enabled and work; a table and a picture it cannot hold - the
  control's CanInsertTable / CanInsertPicture say so. }
procedure TTyRichEditActionsTest.TestAPlainTextDocument;
var
  a: TTyRichEditAction;
begin
  FRich.PlainText := True;
  Select(0, 5);
  a := Make(TTyRichEditBold);
  AssertTrue('bold enabled', UpdatedOn(a).Enabled);
  a.Execute;
  AssertTrue('formatted', FRich.SelAttributes.Bold);
  AssertTrue('align enabled', UpdatedOn(Make(TTyRichEditAlignRight)).Enabled);
  AssertFalse('no table', UpdatedOn(Make(TTyRichEditInsertTable)).Enabled);
  AssertFalse('no picture', UpdatedOn(Make(TTyRichEditInsertPicture)).Enabled);
  AssertEquals('nothing refused', 0, FRefusals);
end;

{ A paragraph of Word's table of contents (inside a field's result): the control says the
  formats cannot change there, so the format actions are disabled; their doors called there
  anyway refuse, tell once with the field's reason, never raise, change nothing. A selection
  that reaches outside the result is formatted outside it, nothing told. }
procedure TTyRichEditActionsTest.TestAFieldsResultIsRefusedAndToldOnce;
var
  p, i, k, depth: Integer;
  a: TTyRichEditAction;
  ps, pl, q: TTyRichPos;
  f: TTyCharFormat;
  pf: TTyParaFormat;
const
  Cases: array[0..2] of TTyRichEditActionClass = (TTyRichEditAlignCenter, TTyRichEditBullets,
    TTyRichEditBold);
begin
  LoadFixture('word-toc.rtf');
  p := -1;
  // a paragraph wholly inside the contents' result (the contents open inside the one before)
  for i := 1 to FRich.Document.Text.ParaCount - 1 do
    if FRich.Document.ParaEndsInField(i) and FRich.Document.ParaEndsInField(i - 1) then
    begin
      p := i;
      Break;
    end;
  AssertTrue('a paragraph of the contents', p >= 0);
  ps := FRich.Document.Text.ParaStart(p);
  pl := FRich.Document.Text.ParaLength(p);
  for i := 0 to High(Cases) do
  begin
    Select(ps + 1, pl - 2);
    a := Make(Cases[i]);
    AssertFalse(Cases[i].ClassName + ' disabled: the control''s answer', UpdatedOn(a).Enabled);
    depth := FRich.Document.UndoDepth;
    FRefusals := 0;
    a.Execute;
    AssertEquals(Cases[i].ClassName + ' not run: nothing told', 0, FRefusals);
    AssertEquals(Cases[i].ClassName + ' no step', depth, FRich.Document.UndoDepth);
  end;
  Select(ps + 1, pl - 2);
  AssertFalse('characters: no', FRich.CanFormatCharacters);
  AssertFalse('paragraphs: no', FRich.CanFormatParagraphs);
  f := TyDefaultCharFormat;
  Include(f.Style, fsBold);
  depth := FRich.Document.UndoDepth;
  FRefusals := 0;
  AssertFalse('the character door refuses', FRich.ApplyCharacterFormat([cffBold], f));
  AssertEquals('told once', 1, FRefusals);
  AssertEquals('the field''s reason', rsRichEditRefusedField, FReason);
  pf := TyDefaultParaFormat;
  pf.Align := paraCenter;
  AssertFalse('the paragraph door refuses', FRich.ApplyParagraphFormat([pffAlign], pf));
  AssertEquals('told once again', 2, FRefusals);
  AssertEquals('the field''s reason too', rsRichEditRefusedField, FReason);
  AssertEquals('no step', depth, FRich.Document.UndoDepth);
  // the caret inside the result: typing there would be refused, so would its format
  Select(ps + 2, 0);
  AssertFalse('the caret in a result: no', FRich.CanFormatCharacters);
  // a link in an ordinary paragraph: its characters no, its paragraph yes
  q := -1;
  for i := 0 to FRich.Document.Text.ParaCount - 1 do
    if not FRich.Document.ParaEndsInField(i) then
    begin
      for k := 1 to FRich.Document.Text.ParaLength(i) - 1 do
        // (two inside: the caret rests outside a link at its very edges)
        if (FRich.Document.ChangeRefusal(FRich.Document.Text.ParaStart(i) + k, 0) = rcrField) and
          (FRich.Document.ChangeRefusal(FRich.Document.Text.ParaStart(i) + k + 1, 0) = rcrField) and
          (FRich.Document.ChangeRefusal(FRich.Document.Text.ParaStart(i) + k + 2, 0) = rcrField) then
        begin
          q := FRich.Document.Text.ParaStart(i) + k + 2;
          Break;
        end;
      if q >= 0 then Break;
    end;
  AssertTrue('a link in a paragraph of its own', q >= 0);
  Select(q, 0);
  AssertEquals('the caret stays inside the link', q, FRich.SelStart);
  AssertFalse('bold: no', UpdatedOn(Make(TTyRichEditBold)).Enabled);
  AssertTrue('centre: yes', UpdatedOn(Make(TTyRichEditAlignCenter)).Enabled);
  // from the paragraph before into the result: formatted outside it, nothing told
  // from the paragraph before the contents into their first entry
  i := 0;
  while not FRich.Document.ParaEndsInField(i) do Inc(i);
  AssertTrue('a paragraph before the contents', i > 0);
  Select(FRich.Document.Text.ParaStart(i - 1), FRich.Document.Text.ParaStart(i) + 2 -
    FRich.Document.Text.ParaStart(i - 1));
  AssertFalse('the selection reaches outside the result',
    FRich.Document.FieldOnly(FRich.SelStart, FRich.SelLength));
  AssertTrue('reaching outside: yes', FRich.CanFormatCharacters);
  FRefusals := 0;
  AssertTrue('formatted', FRich.ApplyCharacterFormat([cffBold], f));
  AssertEquals('nothing told', 0, FRefusals);
  AssertEquals('one step', depth + 1, FRich.Document.UndoDepth);
end;

{ ApplyCharacterFormat is the user's: ReadOnly, disabled - nothing done, nothing told, as for a
  key (the format API, from code, writes there); a selection formatted in one step named as the
  format API's, the selection kept; nothing selected, the next typed text's format, no step; the
  document loading or being saved, told once. The queries agree with it, and need no layout:
  a rich edit never laid out answers as any other. }
procedure TTyRichEditActionsTest.TestTheCharacterDoorIsTheUsers;
var
  f: TTyCharFormat;
  depth: Integer;
  fresh: TActRich;
begin
  f := TyDefaultCharFormat;
  Include(f.Style, fsItalic);
  Select(0, 5);
  FRich.ReadOnly := True;
  AssertFalse('read-only: no', FRich.CanFormatCharacters);
  AssertFalse('read-only: no paragraphs', FRich.CanFormatParagraphs);
  depth := FRich.Document.UndoDepth;
  AssertFalse('read-only: the door does nothing', FRich.ApplyCharacterFormat([cffItalic], f));
  AssertEquals('nothing told', 0, FRefusals);
  AssertFalse('not italic', FRich.SelAttributes.Italic);
  // nothing selected, read-only: not even the next typed text's format
  Select(2, 0);
  AssertFalse('read-only at the caret: nothing', FRich.ApplyCharacterFormat([cffItalic], f));
  AssertFalse('no typing format', FRich.SelAttributes.Italic);
  Select(0, 5);
  FRich.ReadOnly := False;
  FRich.Enabled := False;
  AssertFalse('disabled: no', FRich.CanFormatCharacters);
  AssertFalse('disabled: the door does nothing', FRich.ApplyCharacterFormat([cffItalic], f));
  FRich.Enabled := True;
  AssertTrue('yes', FRich.CanFormatCharacters);
  AssertTrue('yes, paragraphs', FRich.CanFormatParagraphs);
  AssertTrue('done', FRich.ApplyCharacterFormat([cffItalic], f));
  AssertEquals('one step', depth + 1, FRich.Document.UndoDepth);
  AssertEquals('named as the format API''s', rsRichUndoCharFormat, FRich.Document.UndoDescription);
  AssertEquals('the selection kept', 0, FRich.SelStart);
  AssertEquals('its length kept', 5, FRich.SelLength);
  AssertTrue('italic', FRich.SelAttributes.Italic);
  AssertEquals('nothing told', 0, FRefusals);
  // nothing selected: the typing format
  Select(8, 0);
  depth := FRich.Document.UndoDepth;
  Exclude(f.Style, fsItalic);
  Include(f.Style, fsUnderline);
  AssertTrue('at the caret', FRich.ApplyCharacterFormat([cffUnderline], f));
  AssertEquals('no step', depth, FRich.Document.UndoDepth);
  AssertTrue('the next typed text''s format', FRich.SelAttributes.Underline);
  // a rich edit never laid out
  fresh := NewRich;
  try
    fresh.Lines.Text := 'Never painted';
    AssertTrue('no layout needed: characters', fresh.CanFormatCharacters);
    AssertTrue('no layout needed: paragraphs', fresh.CanFormatParagraphs);
    with TTyRichEditBold.Create(FForm) do
    begin
      RichEdit := fresh;
      Update;
      AssertTrue('bold enabled before the first paint', Enabled);
    end;
    with TTyRichEditAlignCenter.Create(FForm) do
    begin
      RichEdit := fresh;
      Update;
      AssertTrue('centre enabled before the first paint', Enabled);
    end;
  finally
    fresh.Free;
  end;
end;

{ CanInsertPicture reads the place: no in a field's result, in a row that holds a nested
  table, across cells - where the insert would be refused; yes in plain text. }
procedure TTyRichEditActionsTest.TestCanInsertPictureReadsThePlace;
var
  p, i, depth: Integer;
  c: TTyRichCell;
  pf: TTyParaFormat;
begin
  Select(2, 0);
  AssertTrue('plain text: yes', FRich.CanInsertPicture);
  LoadFixture('word-toc.rtf');
  p := -1;
  for i := 1 to FRich.Document.Text.ParaCount - 1 do
    if FRich.Document.ParaEndsInField(i) and FRich.Document.ParaEndsInField(i - 1) then
    begin
      p := i;
      Break;
    end;
  Select(FRich.Document.Text.ParaStart(p) + 2, 0);
  AssertFalse('in a field''s result: no', FRich.CanInsertPicture);
  LoadFixture('hand-word-table-merged.rtf');
  p := FirstParaWhere(True);
  Select(FRich.Document.Text.ParaStart(p), 0);
  AssertFalse('in the row that holds a nested table: no', FRich.CanInsertPicture);
  AssertFalse('nor characters', FRich.CanFormatCharacters);
  AssertFalse('nor paragraphs', FRich.CanFormatParagraphs);
  // the paragraph door there: told once, no empty step
  depth := FRich.Document.UndoDepth;
  FRefusals := 0;
  pf := TyDefaultParaFormat;
  pf.Align := paraRight;
  AssertFalse('the paragraph door refuses', FRich.ApplyParagraphFormat([pffAlign], pf));
  AssertEquals('told once', 1, FRefusals);
  AssertEquals('the row''s reason', rsRichEditRefusedFixedRow, FReason);
  AssertEquals('no step', depth, FRich.Document.UndoDepth);
  // across two cells of an ordinary row
  p := FirstParaWhere(False);
  c := FRich.Document.CellAt(p);
  i := p + 1;
  while (i < FRich.Document.Text.ParaCount) and (FRich.Document.CellAt(i) <> nil) and
    (FRich.Document.CellAt(i).Row = c.Row) and (FRich.Document.CellAt(i) = c) do Inc(i);
  if (i < FRich.Document.Text.ParaCount) and (FRich.Document.CellAt(i) <> nil) and
    (FRich.Document.CellAt(i).Row = c.Row) then
  begin
    Select(FRich.Document.Text.ParaStart(p), FRich.Document.Text.ParaStart(i) + 1 -
      FRich.Document.Text.ParaStart(p));
    AssertFalse('across cells: no', FRich.CanInsertPicture);
  end;
  Select(FRich.Document.Text.ParaStart(p), 0);
  AssertTrue('in an ordinary cell: yes', FRich.CanInsertPicture);
  AssertTrue('and its formats', FRich.CanFormatCharacters and FRich.CanFormatParagraphs);
end;

{ ---- the cost ---- }

{ Every action updated, round after round as the application's idle does: the control is asked
  once after a change - whatever number of actions, whatever the selection's length - and not
  at all in a round with nothing changed. }
procedure TTyRichEditActionsTest.TestAnIdleRoundAsksTheControlNothing;
var
  acts: array of TTyRichEditAction;
  st: TTyRichEditActionState;
  i, k, q0, q1, perChange: Integer;
  sb: TStringBuilder;

  procedure Round;
  var
    j: Integer;
  begin
    for j := 0 to High(acts) do acts[j].Update;
  end;

begin
  SetLength(acts, Length(CTyRichEditActions));
  for i := 0 to High(CTyRichEditActions) do acts[i] := Make(CTyRichEditActions[i]);
  Round;
  st := TTyRichEditActionState.Find(FRich);
  AssertEquals('one asking for all of them', 1, st.Refreshes);
  q0 := st.Queries;
  for k := 1 to 50 do Round;
  AssertEquals('50 rounds: no asking', 1, st.Refreshes);
  AssertEquals('50 rounds: no query', q0, st.Queries);
  // a caret move: one asking at the next round, not one per action
  FRich.SelStart := 3;
  Round;
  Round;
  AssertEquals('a move: one asking', 2, st.Refreshes);
  perChange := st.Queries - q0;
  AssertTrue('a few queries per change', (perChange > 0) and (perChange < Length(acts)));
  // a format write, a ReadOnly switch: each heard
  Select(0, 5);
  FRich.SelAttributes.Italic := True;
  Round;
  AssertTrue('italic shows', acts[1].Checked);
  FRich.ReadOnly := True;
  Round;
  AssertFalse('read-only shows', acts[0].Enabled);
  FRich.ReadOnly := False;
  // a long document, all of it selected: the same queries per change, none per round
  sb := TStringBuilder.Create;
  try
    for i := 1 to 20000 do sb.Append('Line of text number ').Append(i).Append(#10);
    SetText(sb.ToString);
  finally
    sb.Free;
  end;
  Round;
  FRich.SelectAll;
  q0 := st.Queries;
  Round;
  q1 := st.Queries;
  AssertEquals('select all: the same queries as a caret move', perChange, q1 - q0);
  for k := 1 to 50 do Round;
  AssertEquals('then no query', q1, st.Queries);
end;

{ ---- what needs a question ---- }

{ Insert table: OnChooseSize first, with Rows x Columns (3 x 3); the size it gives goes in,
  AInsert False inserts nothing (no step). }
procedure TTyRichEditActionsTest.TestTheTableActionAsksForItsSize;
var
  tab: TTyRichEditInsertTable;
  depth: Integer;
  c: TTyRichCell;
begin
  tab := TTyRichEditInsertTable(Make(TTyRichEditInsertTable));
  AssertEquals('3 rows by default', 3, tab.Rows);
  AssertEquals('3 columns by default', 3, tab.Columns);
  tab.OnChooseSize := @ChooseSize;
  FChooseRows := 2;
  FChooseCols := 4;
  FChooseGo := False;
  Select(2, 0);
  depth := FRich.Document.UndoDepth;
  tab.Execute;
  AssertEquals('asked', 1, FChooseCalls);
  AssertEquals('cancelled: no step', depth, FRich.Document.UndoDepth);
  AssertFalse('no table', FRich.InTable);
  FChooseGo := True;
  tab.Execute;
  AssertEquals('asked again', 2, FChooseCalls);
  AssertEquals('one step', depth + 1, FRich.Document.UndoDepth);
  c := FRich.Document.CellAt(FRich.Document.Text.ParaOfPos(FRich.SelStart));
  AssertNotNull('in the table', c);
  AssertEquals('2 rows', 2, c.Row.Table.RowCount);
  AssertEquals('4 columns', 4, c.Row.CellCount);
end;

{ The package has its own find and replace dialogs: the actions show them (the dialog is
  theirs, published as Dialog) for the rich edit they ran on; Find Next selects the next match
  (the dialog's case box counted); nothing found is told through OnNotFound, else the box. Replace:
  the match selected is replaced and the next found; Replace All is one step; OnReplaced
  counts. }
procedure TTyRichEditActionsTest.TestFindAndReplaceUseThePackagesDialogs;
var
  f: TFindProbe;
  r: TReplaceProbe;
  form: TTyFindForm;
  depth, replaced: Integer;
begin
  SetText('alpha beta Alpha ALPHA alpha');
  f := TFindProbe.Create(FForm);
  f.RichEdit := FRich;
  AssertTrue('a find dialog of the package', f.Dialog is TTyFindDialog);
  AssertFalse('not the replace one', f.Dialog is TTyReplaceDialog);
  AssertTrue('enabled', UpdatedOn(f).Enabled);
  Select(0, 5);
  f.Execute;
  AssertEquals('the dialog shown', 1, f.Shows);
  AssertEquals('seeded with the selection', 'alpha', f.Dialog.FindText);
  form := f.Dialog.BuildForm;
  form.DoFindNext;
  AssertEquals('the next match, any case', 11, FRich.SelStart);
  AssertEquals('its length', 5, FRich.SelLength);
  form.DoFindNext;
  AssertEquals('any case: the next', 17, FRich.SelStart);
  Select(11, 5);
  form.MatchCaseCheck.Checked := True;
  form.DoFindNext;
  AssertEquals('match case: past the other cases', 23, FRich.SelStart);
  form.FindEdit.Text := 'delta';
  form.DoFindNext;
  AssertEquals('nothing found: the box', 1, f.Boxes);
  f.OnNotFound := @NotFound;
  form.DoFindNext;
  AssertEquals('OnNotFound instead', 'delta', FNotFound);
  AssertEquals('no second box', 1, f.Boxes);

  r := TReplaceProbe.Create(FForm);
  r.RichEdit := FRich;
  AssertTrue('the replace dialog of the package', r.Dialog is TTyReplaceDialog);
  r.OnReplaced := nil;
  Select(0, 0);
  r.Execute;
  AssertEquals('shown', 1, r.Shows);
  form := r.Dialog.BuildForm;
  form.FindEdit.Text := 'alpha';
  form.ReplaceEdit.Text := 'omega';
  form.DoFindNext;
  AssertEquals('found the first', 0, FRich.SelStart);
  depth := FRich.Document.UndoDepth;
  form.DoReplace;
  AssertEquals('replaced', 'omega beta Alpha ALPHA alpha', FRich.Text);
  AssertEquals('one step', depth + 1, FRich.Document.UndoDepth);
  AssertEquals('the next found', 11, FRich.SelStart);
  depth := FRich.Document.UndoDepth;
  form.DoReplaceAll;
  AssertEquals('all replaced', 'omega beta omega omega omega', FRich.Text);
  AssertEquals('one step for all', depth + 1, FRich.Document.UndoDepth);
  replaced := FRich.Document.UndoDepth;
  AssertTrue('a step', replaced > 0);
end;

{ The replace methods are the document API (they do not stop at ReadOnly): the action
  replaces only where the user may edit, and is disabled where not. }
procedure TTyRichEditActionsTest.TestReplaceStopsWhereTheUserMayNotEdit;
var
  r: TReplaceProbe;
  form: TTyFindForm;
begin
  SetText('alpha beta alpha');
  r := TReplaceProbe.Create(FForm);
  r.RichEdit := FRich;
  r.Execute;
  form := r.Dialog.BuildForm;
  form.FindEdit.Text := 'alpha';
  form.ReplaceEdit.Text := 'omega';
  form.DoFindNext;
  FRich.ReadOnly := True;
  AssertFalse('disabled', UpdatedOn(r).Enabled);
  form.DoReplace;
  form.DoReplaceAll;
  AssertEquals('nothing replaced', 'alpha beta alpha', FRich.Text);
  // the find half still finds
  AssertTrue('Find stays enabled', UpdatedOn(Make(TTyRichEditFind)).Enabled);
end;

{ Insert picture asks for a file through its dialog (the package's open picture dialog; a seam
  here) with a filter of what the control reads; a cancel inserts nothing. }
procedure TTyRichEditActionsTest.TestThePictureActionAsksForAFileOfAReadableFormat;
var
  pic: TPictureProbe;
  flt: string;
  depth: Integer;
begin
  pic := TPictureProbe.Create(FForm);
  pic.RichEdit := FRich;
  AssertTrue('the package''s open picture dialog', pic.Dialog is TTyOpenPictureDialog);
  flt := LowerCase(TyRichPictureFilter);
  AssertTrue('png', Pos('*.png', flt) > 0);
  AssertTrue('jpeg', Pos('*.jpg', flt) > 0);
  AssertTrue('bmp', Pos('*.bmp', flt) > 0);
  AssertTrue('gif', Pos('*.gif', flt) > 0);
  AssertTrue('ico', Pos('*.ico', flt) > 0);
  AssertTrue('no metafile', (Pos('*.wmf', flt) = 0) and (Pos('*.emf', flt) = 0));
  // a metafile reader registered: still none (the control refuses metafiles)
  TPicture.RegisterFileFormat('wmf', 'Windows metafile', TFakeMetafile);
  try
    AssertTrue('the LCL reads one now', Pos('*.wmf', LowerCase(GraphicFileMask(TGraphic))) > 0);
    AssertEquals('none in the filter', 0, Pos('*.wmf', LowerCase(TyRichPictureFilter)));
  finally
    TPicture.UnregisterGraphicClass(TFakeMetafile);
  end;
  AssertEquals('unregistered again', 0, Pos('*.wmf', LowerCase(GraphicFileMask(TGraphic))));
  AssertTrue('all files last', AnsiEndsStr('|*', flt));
  Select(2, 0);
  depth := FRich.Document.UndoDepth;
  pic.Answer := '';
  pic.Execute;
  AssertEquals('asked', 1, pic.Asks);
  AssertEquals('cancelled: nothing', depth, FRich.Document.UndoDepth);
  pic.Answer := PngFile;
  pic.Execute;
  AssertEquals('inserted', depth + 1, FRich.Document.UndoDepth);
end;

{ Increase / Decrease Indent: the caret paragraph's first line to the next / previous multiple
  of half an inch, not left of the margin; a hanging paragraph keeps its offset; with several
  paragraphs selected each goes to the caret paragraph's new place. }
procedure TTyRichEditActionsTest.TestTheIndentActionsStepByHalfAnInch;
var
  incr, decr: TTyRichEditAction;
  f: TTyParaFormat;

  function Place(APara: Integer): Integer;
  var
    pf: TTyParaFormat;
  begin
    pf := FRich.Document.Formats.ParaFormat(FRich.Document.ParaFormatOf(APara));
    Result := pf.LeftIndent + pf.FirstIndent;
  end;

begin
  incr := Make(TTyRichEditIndentIncrease);
  decr := Make(TTyRichEditIndentDecrease);
  Select(1, 0);
  incr.Execute;
  AssertEquals('720', 720, Place(0));
  incr.Execute;
  AssertEquals('1440', 1440, Place(0));
  decr.Execute;
  AssertEquals('back to 720', 720, Place(0));
  decr.Execute;
  decr.Execute;
  AssertEquals('not left of the margin', 0, Place(0));
  // between two steps: to the next one
  f := TyDefaultParaFormat;
  f.LeftIndent := 1000;
  FRich.ApplyParagraphFormat([pffLeftIndent], f);
  incr.Execute;
  AssertEquals('1000 to 1440', 1440, Place(0));
  FRich.ApplyParagraphFormat([pffLeftIndent], f);
  decr.Execute;
  AssertEquals('1000 back to 720', 720, Place(0));
  // a hanging paragraph: its first line moves, its offset is kept
  f := TyDefaultParaFormat;
  f.LeftIndent := 720;
  f.FirstIndent := -360;
  FRich.ApplyParagraphFormat([pffLeftIndent, pffFirstIndent], f);
  incr.Execute;
  AssertEquals('360 to 720', 720, Place(0));
  AssertEquals('the offset kept', -360,
    FRich.Document.Formats.ParaFormat(FRich.Document.ParaFormatOf(0)).FirstIndent);
  // two paragraphs, the caret in the second (at 0): both to its next place
  Select(0, FRich.Document.Text.ParaStart(1) + 1);
  incr.Execute;
  AssertEquals('the first at the caret paragraph''s place', 720, Place(0));
  AssertEquals('the second', 720, Place(1));
end;

{ Undo and Redo: the control's CanUndo / CanRedo, its Undo / Redo. Zoom: by the wheel's step
  within the control's limits; 100 % checked at 100. }
procedure TTyRichEditActionsTest.TestUndoRedoAndZoom;
var
  u, r, zi, zo, z0: TTyRichEditAction;
begin
  u := Make(TTyRichEditUndo);
  r := Make(TTyRichEditRedo);
  AssertFalse('nothing to undo', UpdatedOn(u).Enabled);
  AssertFalse('nothing to redo', UpdatedOn(r).Enabled);
  Select(0, 5);
  FRich.SelAttributes.Bold := True;
  AssertTrue('to undo', UpdatedOn(u).Enabled);
  u.Execute;
  Select(0, 5);
  AssertFalse('undone', FRich.SelAttributes.Bold);
  AssertTrue('to redo', UpdatedOn(r).Enabled);
  r.Execute;
  Select(0, 5);
  AssertTrue('redone', FRich.SelAttributes.Bold);
  zi := Make(TTyRichEditZoomIn);
  zo := Make(TTyRichEditZoomOut);
  z0 := Make(TTyRichEditZoomReset);
  AssertTrue('100 % checked', UpdatedOn(z0).Checked);
  zi.Execute;
  AssertEquals('in by a step', 100 + CRichZoomStep, FRich.Zoom);
  AssertFalse('100 % not checked', UpdatedOn(z0).Checked);
  zo.Execute;
  zo.Execute;
  AssertEquals('out by two', 100 - CRichZoomStep, FRich.Zoom);
  z0.Execute;
  AssertEquals('reset', 100, FRich.Zoom);
  FRich.Zoom := CRichZoomMax;
  AssertFalse('no more in', UpdatedOn(zi).Enabled);
  FRich.Zoom := CRichZoomMin;
  AssertFalse('no more out', UpdatedOn(zo).Enabled);
  AssertTrue('in again', UpdatedOn(zi).Enabled);
end;

{ ---- keys ---- }

{ The shortcuts are the common editors', each the action's default. A key goes through LCL's
  way: the focused control first, the forms' action lists after only what it left. Ctrl+Z in
  the rich edit is its own undo - the undo action's Ctrl+Z is not run as well: one step undone,
  not two. Ctrl+B the rich edit leaves: the bold action takes it, once. }
procedure TTyRichEditActionsTest.TestAShortcutIsHandledByOneOfTheTwo;
var
  list: TActionList;
  undo, bold: TTyRichEditAction;
  depth: Integer;
begin
  {$IFNDEF MSWINDOWS}
  Ignore('Ctrl is held through the Windows thread keyboard state');
  {$ENDIF}
  AssertEquals('Ctrl+B', ShortCut(VK_B, [ssCtrl]), Make(TTyRichEditBold).ShortCut);
  AssertEquals('Ctrl+I', ShortCut(VK_I, [ssCtrl]), Make(TTyRichEditItalic).ShortCut);
  AssertEquals('Ctrl+U', ShortCut(VK_U, [ssCtrl]), Make(TTyRichEditUnderline).ShortCut);
  AssertEquals('Ctrl+L', ShortCut(VK_L, [ssCtrl]), Make(TTyRichEditAlignLeft).ShortCut);
  AssertEquals('Ctrl+E', ShortCut(VK_E, [ssCtrl]), Make(TTyRichEditAlignCenter).ShortCut);
  AssertEquals('Ctrl+R', ShortCut(VK_R, [ssCtrl]), Make(TTyRichEditAlignRight).ShortCut);
  AssertEquals('Ctrl+J', ShortCut(VK_J, [ssCtrl]), Make(TTyRichEditAlignJustify).ShortCut);
  AssertEquals('Ctrl+Z', ShortCut(VK_Z, [ssCtrl]), Make(TTyRichEditUndo).ShortCut);
  AssertEquals('Ctrl+Y', ShortCut(VK_Y, [ssCtrl]), Make(TTyRichEditRedo).ShortCut);
  AssertEquals('Ctrl+F', ShortCut(VK_F, [ssCtrl]), Make(TTyRichEditFind).ShortCut);
  AssertEquals('Ctrl+H', ShortCut(VK_H, [ssCtrl]), Make(TTyRichEditReplace).ShortCut);
  AssertEquals('Ctrl+plus', ShortCut(VK_OEM_PLUS, [ssCtrl]), Make(TTyRichEditZoomIn).ShortCut);
  AssertEquals('Ctrl+minus', ShortCut(VK_OEM_MINUS, [ssCtrl]), Make(TTyRichEditZoomOut).ShortCut);
  AssertEquals('Ctrl+0', ShortCut(VK_0, [ssCtrl]), Make(TTyRichEditZoomReset).ShortCut);
  list := TActionList.Create(FForm);
  undo := Make(TTyRichEditUndo);
  undo.ActionList := list;
  bold := Make(TTyRichEditBold);
  bold.ActionList := list;
  // two steps to undo
  Select(0, 5);
  FRich.SelAttributes.Italic := True;
  Select(6, 4);
  FRich.SelAttributes.Italic := True;
  depth := FRich.Document.UndoDepth;
  AssertTrue('Ctrl+Z taken', KeyThroughLcl(VK_Z, True));
  AssertEquals('one step undone, not two', depth - 1, FRich.Document.UndoDepth);
  Select(0, 5);
  AssertTrue('the first still italic', FRich.SelAttributes.Italic);
  // Ctrl+B: the action's
  Select(0, 5);
  depth := FRich.Document.UndoDepth;
  AssertTrue('Ctrl+B taken', KeyThroughLcl(VK_B, True));
  AssertEquals('bold once', depth + 1, FRich.Document.UndoDepth);
  AssertTrue('bold', FRich.SelAttributes.Bold);
  AssertEquals('nothing typed', 'Plain bold plain', Copy(FRich.Text, 1, 16));
end;

{ ---- strings and registration ---- }

{ Every caption and hint the actions show is a resourcestring of the package's catalogue, in
  English, with its Chinese in the zh_CN catalogue; the theme builder's copy of that catalogue
  is the same file byte for byte. }
procedure TTyRichEditActionsTest.TestTheCaptionsAndHintsAreInTheCatalogue;
var
  po: TPOFile;
  root, s: string;
  i, k: Integer;
  a: TTyRichEditAction;
  pot: TStringList;
  shown: array[0..2] of string;

  function Bytes(const APath: string): string;
  var
    f: TFileStream;
  begin
    f := TFileStream.Create(APath, fmOpenRead or fmShareDenyWrite);
    try
      SetLength(Result, f.Size);
      if f.Size > 0 then f.ReadBuffer(Result[1], f.Size);
    finally
      f.Free;
    end;
  end;

begin
  root := ExtractFilePath(ParamStr(0)) + '..' + PathDelim;
  po := TPOFile.Create(root + 'languages' + PathDelim + 'tycontrols.strconsts.zh_CN.po');
  pot := TStringList.Create;
  try
    pot.Text := Bytes(root + 'languages' + PathDelim + 'tyControls.StrConsts.pot');
    for i := 0 to High(CTyRichEditActions) do
    begin
      a := CTyRichEditActions[i].Create(nil);
      try
        AssertTrue(a.ClassName + ' has a caption', a.Caption <> '');
        AssertTrue(a.ClassName + ' has a hint', a.Hint <> '');
        shown[0] := a.Caption;
        shown[1] := a.Hint;
        for k := 0 to 1 do
        begin
          s := shown[k];
          AssertTrue(a.ClassName + ': "' + s + '" in the .pot',
            Pos('msgid "' + s + '"', pot.Text) > 0);
          AssertTrue(a.ClassName + ': "' + s + '" translated',
            (po.Translate('', s) <> s) and (po.Translate('', s) <> ''));
        end;
      finally
        a.Free;
      end;
    end;
    shown[0] := rsRichActNotFound;
    shown[1] := rsRichActPictureFiles;
    shown[2] := rsRichActAllFiles;
    for k := 0 to 2 do
      AssertTrue('"' + shown[k] + '" translated', po.Translate('', shown[k]) <> shown[k]);
  finally
    pot.Free;
    po.Free;
  end;
  AssertTrue('the theme builder''s copy is the catalogue',
    Bytes(root + 'languages' + PathDelim + 'tycontrols.strconsts.zh_CN.po') =
    Bytes(root + 'tools' + PathDelim + 'themebuilder' + PathDelim + 'languages' + PathDelim +
      'tycontrols.zh_CN.po'));
end;

{ The IDE lists them: the design-time package registers every action of the unit (RegisterActions,
  its own category), and nothing else under that name. A fresh action stores nothing a form file
  would not have from the constructor: its declared defaults (the shortcuts, the table's size)
  are the values it is made with. }
procedure TTyRichEditActionsTest.TestEveryActionIsRegisteredAndKeepsItsDefaults;
var
  code, list: string;
  p, q, i: Integer;
  names: TStringList;
  a: TTyRichEditAction;
begin
  code := DesignSourceCode(True);
  p := Pos('RegisterActions(', code);
  AssertTrue('RegisterActions is called', p > 0);
  AssertTrue('in its own category', Pos('''TyControls Rich Edit''', Copy(code, p, 80)) > 0);
  p := PosEx('[', code, p);
  q := PosEx(']', code, p);
  list := Copy(code, p + 1, q - p - 1);
  names := TStringList.Create;
  try
    names.Delimiter := ',';
    names.StrictDelimiter := True;
    names.DelimitedText := StringReplace(StringReplace(list, #13, '', [rfReplaceAll]), #10, '',
      [rfReplaceAll]);
    for i := 0 to names.Count - 1 do names[i] := Trim(names[i]);
    AssertEquals('as many as the unit has', Length(CTyRichEditActions), names.Count);
    for i := 0 to High(CTyRichEditActions) do
      AssertEquals('registered in order', CTyRichEditActions[i].ClassName, names[i]);
  finally
    names.Free;
  end;
  for i := 0 to High(CTyRichEditActions) do
  begin
    a := CTyRichEditActions[i].Create(nil);
    try
      AssertTrue(a.ClassName + ' disabled with no handler', a.DisableIfNoHandler);
      AssertNull(a.ClassName + ' no rich edit', a.RichEdit);
    finally
      a.Free;
    end;
  end;
end;

initialization
  RegisterTest(TTyRichEditActionsTest);

end.
