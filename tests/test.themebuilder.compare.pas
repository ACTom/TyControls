unit test.themebuilder.compare;
{ The AI comparison window and trying a version in the preview (TTbCompareTests), and the
  AI settings dialog (TTbAiSettingsFormTests) -- phase 3. The windows are built and never
  shown; the tests call what their buttons call. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, tbcompareform, tbaisettings, tbaisettingsform;

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

  TTbAiSettingsFormTests = class(TTestCase)
  private
    FDir, FIni, FKeys: string;
    FSettings: TTbAiSettings;
    FForm: TTbAiSettingsForm;
    function WaitTest(AMs: Integer): Boolean;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAPreset;                   { G1 }
    procedure TestOkKeepsCancelDoesNot;      { G2 }
    procedure TestTheLocalHint;              { G3 }
    procedure TestAnthropicNeedsAMaximum;    { G4 }
    procedure TestTheConnectionTest;         { G5 }
    procedure TestAFailedConnectionTest;     { G6 }
    procedure TestThePrivacyNote;            { G7 }
    procedure TestClosingDuringATest;        { G8 }
    { after the phase 3 reviews }
    procedure TestPlainHttpToAnotherComputer;   { G9 }
  end;

{ the widgetset, once (the SynEdit completion window needs it) }
procedure TbNeedWidgetSet;

implementation

uses
  Forms, Graphics, SynEditTypes, SynEditMiscClasses, tyControls.Controller, tyControls.Types,
  tbdiff, tbeditorlook, tbaisession, tbpreview, tbaiformat, tbaiclient, tbaichecks, tbfakehttp;

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

{ ---- TTbAiSettingsFormTests ---- }

const
  cFormKey = 'sk-test-0000-settings';

procedure TTbAiSettingsFormTests.SetUp;
begin
  TbNeedWidgetSet;
  FDir := TbAiTempDir;
  TbAiFilesFor(FDir + 'themebuilder.ini', FIni, FKeys);
  FSettings := TTbAiSettings.Create(FIni, FKeys);
  FSettings.Load;
  FForm := TTbAiSettingsForm.Create(nil);
  FForm.Prepare(FSettings);
end;

procedure TTbAiSettingsFormTests.TearDown;
begin
  FreeAndNil(FForm);
  FreeAndNil(FSettings);
  CheckSynchronize(20);
  TbAiRemoveDir(FDir);
end;

function TTbAiSettingsFormTests.WaitTest(AMs: Integer): Boolean;
var
  t0: QWord;
begin
  t0 := GetTickCount64;
  while FForm.Testing and (GetTickCount64 - t0 < QWord(AMs)) do
    CheckSynchronize(10);
  Result := not FForm.Testing;
end;

procedure TTbAiSettingsFormTests.TestAPreset;
begin
  AssertEquals('nothing yet', 0, FForm.ProfileList.Items.Count);
  FForm.AddPreset(tapAnthropic);
  AssertEquals('G1: one more', 1, FForm.ProfileList.Items.Count);
  AssertEquals('G1: selected', 0, FForm.ProfileList.ItemIndex);
  AssertEquals('G1: the format', 1, FForm.CmbFormat.ItemIndex);
  AssertEquals('G1: the address', 'https://api.anthropic.com/v1', FForm.EdtUrl.Text);
  AssertEquals('G1: the maximum', 32000, FForm.SpnMaxOutput.Value);
end;

procedure TTbAiSettingsFormTests.TestOkKeepsCancelDoesNot;
var
  other: TTbAiSettings;
  f2: TTbAiSettingsForm;
  p: TTbAiProfile;
begin
  FForm.AddPreset(tapDeepSeek);
  FForm.EdtName.Text := 'Mine';
  FForm.EdtModel.Text := 'deepseek-reasoner';
  FForm.EdtKey.Text := cFormKey;
  FForm.SpnTimeout.Value := 90;
  AssertTrue('G2: committed', FForm.Commit);
  other := TTbAiSettings.Create(FIni, FKeys);
  try
    other.Load;
    AssertEquals('G2: one profile', 1, other.Count);
    p := other.Profile(0);
    AssertEquals('G2: the name', 'Mine', p.Name);
    AssertEquals('G2: the model', 'deepseek-reasoner', p.Model);
    AssertEquals('G2: the timeout', 90, p.TimeoutSec);
    AssertTrue('G2: the key', other.GetKey(p.Id) = cFormKey);
  finally
    other.Free;
  end;
  { a second dialog: changed, then closed without OK }
  f2 := TTbAiSettingsForm.Create(nil);
  try
    f2.Prepare(FSettings);
    f2.EdtName.Text := 'Changed';
    AssertEquals('the copy changed', 'Changed', f2.ProfileList.Items[0]);
  finally
    f2.Free;
  end;
  other := TTbAiSettings.Create(FIni, FKeys);
  try
    other.Load;
    AssertEquals('G2: Cancel keeps the file', 'Mine', other.Profile(0).Name);
    AssertEquals('G2: and the settings', 'Mine', FSettings.Profile(0).Name);
  finally
    other.Free;
  end;
end;

procedure TTbAiSettingsFormTests.TestTheLocalHint;
begin
  FForm.AddPreset(tapCustom);
  FForm.EdtUrl.Text := 'http://localhost:11434/v1';
  AssertTrue('G3: the Ollama hint', FForm.LblHint.Visible);
  FForm.EdtUrl.Text := 'https://api.openai.com/v1';
  AssertFalse('G3: not for a remote service', FForm.LblHint.Visible);
end;

procedure TTbAiSettingsFormTests.TestAnthropicNeedsAMaximum;
begin
  FForm.AddPreset(tapCustom);
  AssertEquals('starts at 0', 0, FForm.SpnMaxOutput.Value);
  FForm.CmbFormat.ItemIndex := 1;
  AssertEquals('G4: filled in', 32000, FForm.SpnMaxOutput.Value);
  FForm.SpnMaxOutput.Value := 0;
  AssertFalse('G4: refused', FForm.Commit);
  AssertEquals('G4: the settings did not change', 0, FSettings.Count);
  AssertEquals('G4: says why', rsTbAiNeedMaxOutput, FForm.TestText);
end;

function TestServerStream: RawByteString;
begin
  Result := 'data: {"id":"x","object":"chat.completion.chunk","choices":[{"index":0,' +
    '"delta":{"content":"OK"},"finish_reason":null}]}'#10#10;
end;

procedure TTbAiSettingsFormTests.TestTheConnectionTest;
var
  srv: TTbFakeHttpServer;
  t0: QWord;
begin
  srv := TTbFakeHttpServer.Create;
  try
    srv.Script([FakeSend(FakeHead(200, 'text/event-stream', True)),
      FakeSend(FakeChunk(TestServerStream)), FakeHold]);
    FForm.AddPreset(tapCustom);
    FForm.EdtUrl.Text := srv.Url('/v1');
    FForm.EdtModel.Text := 'tiny';
    AssertTrue('G5: started', FForm.StartTest);
    AssertTrue('G5: answered within 5 s', WaitTest(5000));
    AssertTrue('G5: connected: ' + FForm.TestText, Pos('Connected', FForm.TestText) = 1);
    AssertTrue('G5: the ping went out', Pos('"ping"', srv.LastRequest.Body) > 0);
    { the test stopped the request once it knew: the server's held line goes }
    t0 := GetTickCount64;
    while (srv.ClosedByPeer = 0) and (GetTickCount64 - t0 < 5000) do
      CheckSynchronize(10);
    AssertTrue('G5: the request was stopped', srv.ClosedByPeer > 0);
  finally
    FreeAndNil(FForm);
    srv.Free;
  end;
end;

procedure TTbAiSettingsFormTests.TestAFailedConnectionTest;
var
  srv: TTbFakeHttpServer;
begin
  srv := TTbFakeHttpServer.Create;
  try
    srv.Script([FakeSend(FakeHead(401, 'application/json', False,
      '{"error":{"message":"bad key ' + cFormKey + '"}}'))]);
    FForm.AddPreset(tapCustom);
    FForm.EdtUrl.Text := srv.Url('/v1');
    FForm.EdtKey.Text := cFormKey;
    AssertTrue('G6: started', FForm.StartTest);
    AssertTrue('G6: answered within 5 s', WaitTest(5000));
    AssertTrue('G6: the key was refused: ' + FForm.TestText,
      Pos(Format(rsTbAiAuth, [401]), FForm.TestText) = 1);
    AssertTrue('G6: the key is not in the sentence', Pos(cFormKey, FForm.TestText) = 0);
  finally
    FreeAndNil(FForm);
    srv.Free;
  end;
end;

procedure TTbAiSettingsFormTests.TestThePrivacyNote;
begin
  AssertTrue('G7: what is sent where', Pos(rsTbAiPrivacy, FForm.LblPrivacy.Caption) > 0);
  {$IFDEF MSWINDOWS}
  AssertTrue('G7: how keys are kept', Pos(rsTbAiKeyStoreWin, FForm.LblPrivacy.Caption) > 0);
  {$ELSE}
  AssertTrue('G7: how keys are kept', Pos(rsTbAiKeyStoreUnix, FForm.LblPrivacy.Caption) > 0);
  {$ENDIF}
end;

procedure TTbAiSettingsFormTests.TestClosingDuringATest;
var
  srv: TTbFakeHttpServer;
  t0: QWord;
begin
  srv := TTbFakeHttpServer.Create;
  try
    srv.Script([FakeHold]);
    FForm.AddPreset(tapCustom);
    FForm.EdtUrl.Text := srv.Url('/v1');
    AssertTrue('G8: started', FForm.StartTest);
    t0 := GetTickCount64;
    FreeAndNil(FForm);
    AssertTrue('G8: closing did not hang', GetTickCount64 - t0 < 5000);
    CheckSynchronize(50);
  finally
    srv.Free;
  end;
end;

{ G9: http:// to another computer -- a warning, and no key: OK refuses, Test connection says
  it was not sent (recording transports: nothing reaches the network either way) }
procedure TTbAiSettingsFormTests.TestPlainHttpToAnotherComputer;
begin
  FForm.AddPreset(tapCustom);
  FForm.EdtUrl.Text := 'https://192.0.2.10/v1';
  AssertFalse('G9: https, no warning', FForm.PlainHttpAlert.Visible);
  FForm.EdtUrl.Text := 'http://localhost:11434/v1';
  AssertFalse('G9: this computer, no warning', FForm.PlainHttpAlert.Visible);
  FForm.EdtUrl.Text := 'http://192.0.2.10:11434/v1';
  AssertTrue('G9: http to another computer, warned', FForm.PlainHttpAlert.Visible);
  AssertEquals('G9: the warning says it', rsTbAiPlainHttp, FForm.PlainHttpAlert.Message);
  FForm.EdtKey.Text := cFormKey;
  AssertFalse('G9: with a key, OK refuses', FForm.Commit);
  AssertEquals('G9: nothing was kept', 0, FSettings.Count);
  AssertEquals('G9: says why', Format(rsTbAiPlainHttpKey, ['192.0.2.10']), FForm.TestText);
  AssertTrue('G9: the key is not in it', Pos(cFormKey, FForm.TestText) = 0);
  TbRecordTransports(True);
  try
    AssertTrue('G9: the test starts', FForm.StartTest);
    AssertTrue('G9: answered within 5 s', WaitTest(5000));
    AssertEquals('G9: the test says it was not sent', Format(rsTbAiInsecureKey, ['192.0.2.10']),
      FForm.TestText);
    AssertEquals('G9: nothing was asked of a transport', 0, TbRecordedRequests);
  finally
    TbRecordTransports(False);
  end;
  FForm.EdtKey.Text := '';
  AssertTrue('G9: without a key it is kept', FForm.Commit);
  AssertEquals('G9: kept', 1, FSettings.Count);
end;

initialization
  RegisterTest(TTbCompareTests);
  RegisterTest(TTbAiSettingsFormTests);
end.
