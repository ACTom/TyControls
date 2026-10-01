unit test.themebuilder.compare;
{ The AI comparison window and trying a version in the preview (TTbCompareTests), and the
  AI settings dialog (TTbAiSettingsFormTests) -- phase 3. The windows are built and never
  shown; the tests call what their buttons call. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, tbcompareform;

type
  TTbCompareTests = class(TTestCase)
  private
    FForm: TTbCompareForm;
    FTrials: string;            { 'T' / 'F' per OnTrial call }
    FRefuse: string;
    procedure Trial(Sender: TObject; AOn: Boolean; out AError: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheSidesLineUp;            { V1 }
    procedure TestTheRowsAreTinted;          { V2 }
    procedure TestTheSidesScrollTogether;    { V3 }
    procedure TestTheTrialIsWired;           { V4 }
    procedure TestARefusedTrial;             { V5 }
    procedure TestTheProblemsLeft;           { V6 }
    procedure TestThePreviewTrial;           { V7 }
    procedure TestATrialKeepsARefusedMode;   { V8 }
    procedure TestABadTrialEndsAtOnce;       { V9 }
  end;

{ the widgetset, once (the SynEdit completion window needs it) }
procedure TbNeedWidgetSet;

implementation

uses
  Forms, Graphics, SynEditTypes, SynEditMiscClasses, tyControls.Controller, tyControls.Types,
  tbdiff, tbeditorlook, tbaisession, tbpreview;

var
  GReady: Boolean = False;

procedure TbNeedWidgetSet;
begin
  if GReady then Exit;
  Forms.Application.Initialize;
  GReady := True;
end;

function Bars(const S: string): string;
begin
  Result := StringReplace(S, '|', LineEnding, [rfReplaceAll]) + LineEnding;
end;

procedure TTbCompareTests.SetUp;
begin
  TbNeedWidgetSet;
  FTrials := '';
  FRefuse := '';
  FForm := TTbCompareForm.Create(nil);
end;

procedure TTbCompareTests.TearDown;
begin
  FreeAndNil(FForm);
end;

procedure TTbCompareTests.Trial(Sender: TObject; AOn: Boolean; out AError: string);
begin
  if AOn then FTrials := FTrials + 'T' else FTrials := FTrials + 'F';
  if AOn then AError := FRefuse else AError := '';
end;

procedure TTbCompareTests.TestTheSidesLineUp;
begin
  FForm.Prepare(Bars('a|b|c'), Bars('a|x|c|d'), nil, TbEditorColors(TyDefaultController));
  AssertEquals('V1: rows', 4, Length(FForm.Rows));
  AssertEquals('V1: left lines', 4, FForm.LeftEdit.Lines.Count);
  AssertEquals('V1: right lines', 4, FForm.RightEdit.Lines.Count);
  AssertEquals('V1: left 2', 'b', FForm.LeftEdit.Lines[1]);
  AssertEquals('V1: right 2', 'x', FForm.RightEdit.Lines[1]);
  AssertEquals('V1: right 4', 'd', FForm.RightEdit.Lines[3]);
  AssertEquals('V1: left 4 is a filler', '', FForm.LeftEdit.Lines[3]);
  AssertTrue('V1: row 2 changed', FForm.RowKindAt(False, 2) = tdkChanged);
  AssertTrue('V1: row 4 added', FForm.RowKindAt(True, 4) = tdkAdded);
end;

procedure TTbCompareTests.TestTheRowsAreTinted;
var
  look: TTbEditorColors;
  m: TSynSelectedColor;
  special: Boolean;
begin
  look := TbEditorColors(TyDefaultController);
  AssertTrue('the added colour is not the removed one', look.AddedLine <> look.RemovedLine);
  AssertTrue('the added colour is not the ground', look.AddedLine <> look.Background);
  AssertTrue('the removed colour is not the ground', look.RemovedLine <> look.Background);
  FForm.Prepare(Bars('a|b|c'), Bars('a|x|c|d'), nil, look);
  m := TSynSelectedColor.Create;
  try
    special := False;
    FForm.EditSpecialLineMarkup(FForm.RightEdit, 4, special, m);
    AssertTrue('V2: an added line is tinted', special);
    AssertEquals('V2: green on the right', look.AddedLine, m.Background);
    special := False;
    FForm.EditSpecialLineMarkup(FForm.LeftEdit, 2, special, m);
    AssertTrue('V2: a changed line on the left', special);
    AssertEquals('V2: red on the left', look.RemovedLine, m.Background);
    special := False;
    FForm.EditSpecialLineMarkup(FForm.RightEdit, 2, special, m);
    AssertEquals('V2: green on the right of a change', look.AddedLine, m.Background);
    special := False;
    FForm.EditSpecialLineMarkup(FForm.LeftEdit, 4, special, m);
    AssertTrue('V2: a filler is tinted', special);
    AssertEquals('V2: as a filler', look.FillerLine, m.Background);
    special := False;
    FForm.EditSpecialLineMarkup(FForm.LeftEdit, 1, special, m);
    AssertFalse('V2: the same line is not', special);
  finally
    m.Free;
  end;
end;

procedure TTbCompareTests.TestTheSidesScrollTogether;
var
  s: string;
  i: Integer;
begin
  s := '';
  for i := 1 to 200 do
    s := s + 'line ' + IntToStr(i) + LineEnding;
  FForm.Prepare(s, s + 'extra' + LineEnding, nil, TbEditorColors(TyDefaultController));
  FForm.LeftEdit.TopLine := 3;
  AssertEquals('the left one moved', 3, FForm.LeftEdit.TopLine);
  FForm.EditStatusChange(FForm.LeftEdit, [scTopLine]);
  AssertEquals('V3: the right one followed', 3, FForm.RightEdit.TopLine);
end;

procedure TTbCompareTests.TestTheTrialIsWired;
begin
  FForm.Prepare(Bars('a'), Bars('b'), nil, TbEditorColors(TyDefaultController));
  FForm.OnTrial := @Trial;
  FForm.TrialCheck.Checked := True;
  AssertEquals('V4: switched on', 'T', FTrials);
  FreeAndNil(FForm);
  AssertEquals('V4: and off when the window goes', 'TF', FTrials);
end;

procedure TTbCompareTests.TestARefusedTrial;
begin
  FForm.Prepare(Bars('a'), Bars('b'), nil, TbEditorColors(TyDefaultController));
  FForm.OnTrial := @Trial;
  FRefuse := 'x';
  FForm.TrialCheck.Checked := True;
  AssertFalse('V5: the box went back', FForm.TrialCheck.Checked);
  AssertTrue('V5: the reason is shown', Pos('x', FForm.Summary.Caption) > 0);
  AssertEquals('V5: asked once', 'T', FTrials);
  FreeAndNil(FForm);
  AssertEquals('V5: nothing to end', 'T', FTrials);
end;

procedure TTbCompareTests.TestTheProblemsLeft;
var
  issues: TTbAiIssues;
begin
  SetLength(issues, 1);
  issues[0].Line := 2;
  issues[0].Col := 3;
  issues[0].IsError := True;
  issues[0].Text := 'bad';
  FForm.Prepare(Bars('a'), Bars('b'), issues, TbEditorColors(TyDefaultController));
  AssertTrue('V6: listed', FForm.IssuesList.Visible);
  AssertEquals('V6: one row', 1, FForm.IssuesList.Items.Count);
  AssertTrue('V6: the summary counts it: ' + FForm.Summary.Caption,
    Pos(Format(rsTbCompareSummary, [1, 1]), FForm.Summary.Caption) = 1);
  FForm.Prepare(Bars('a'), Bars('b'), nil, TbEditorColors(TyDefaultController));
  AssertFalse('V6: none, no list', FForm.IssuesList.Visible);
end;

function ButtonBg(AFrame: TTbPreviewFrame): Integer;
begin
  Result := Integer(Cardinal(AFrame.Controller.Model.ResolveStyle('TyButton', '', []).Background.Color)
    and $FFFFFF);
end;

procedure TTbCompareTests.TestThePreviewTrial;
var
  f: TTbPreviewFrame;
  err: string;
begin
  f := TTbPreviewFrame.Create(nil);
  try
    AssertTrue('A loads', f.LoadDocument('TyButton { background: #123456; }', '', err));
    AssertEquals('A is shown', $123456, ButtonBg(f));
    AssertTrue('V7: B is tried', f.BeginTrial('TyButton { background: #654321; }', '', err));
    AssertEquals('V7: B is shown', $654321, ButtonBg(f));
    AssertTrue('V7: in a trial', f.InTrial);
    f.EndTrial;
    AssertEquals('V7: A is back', $123456, ButtonBg(f));
    AssertFalse('V7: the trial is over', f.InTrial);
  finally
    f.Free;
  end;
end;

procedure TTbCompareTests.TestATrialKeepsARefusedMode;
const
  cA = '@mode light { :root { --only-light: #123456; } }'#10 +
    '@mode dark { :root { --x: #000000; } }'#10 +
    'TyButton { background: #123456; }'#10 +
    'TyButton:disabled { color: var(--only-light); }'#10;
var
  f: TTbPreviewFrame;
  err, before: string;
begin
  f := TTbPreviewFrame.Create(nil);
  try
    AssertTrue('A loads', f.LoadDocument(cA, '', err));
    AssertFalse('A is refused in dark', f.SetDark(True, err));
    before := f.ModeError;
    AssertTrue('the refusal is kept', before <> '');
    AssertTrue('B is tried', f.BeginTrial('TyButton { background: #654321; }', '', err));
    f.EndTrial;
    AssertEquals('V8: the refusal is back', before, f.ModeError);
  finally
    f.Free;
  end;
end;

procedure TTbCompareTests.TestABadTrialEndsAtOnce;
var
  f: TTbPreviewFrame;
  err: string;
begin
  f := TTbPreviewFrame.Create(nil);
  try
    AssertTrue('A loads', f.LoadDocument('TyButton { background: #123456; }', '', err));
    AssertFalse('V9: refused', f.BeginTrial('TyButton { color: var(--nowhere); }', '', err));
    AssertFalse('V9: no trial', f.InTrial);
    AssertEquals('V9: A is still shown', $123456, ButtonBg(f));
  finally
    f.Free;
  end;
end;

initialization
  RegisterTest(TTbCompareTests);
end.
