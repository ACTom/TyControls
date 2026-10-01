unit test.themebuilder.compare;
{ The AI comparison window and trying a version in the preview (TTbCompareTests), and the
  AI settings dialog (TTbAiSettingsFormTests) -- phase 3. The windows are built and never
  shown; the tests call what their buttons call. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Graphics, fpcunit, testregistry, tbcompareform, tbaisettings, tbaisettingsform;

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
    { the last batch before the merge }
    procedure TestTintedRowsAreReadable;     { V10 }
    procedure TestTheTrialBoxIsNotCut;       { V11 }
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
    procedure TestOkChecksBeforeItChanges;      { G10 }
    { the last batch before the merge }
    procedure TestTheOllamaHintIsWhole;         { G11 }
    procedure TestAddIsOneMenuButton;           { G12 }
  end;

{ the contrast of two LCL colours (WCAG, 1..21) }
function TbContrast(AFg, ABg: TColor): Double;

{ the widgetset, once (the SynEdit completion window needs it) }
procedure TbNeedWidgetSet;

implementation

uses
  Types, LCLType, Forms, Controls, SynEditTypes, SynEditMiscClasses, tyControls.Controller, tyControls.Types,
  tyControls.Base, tyControls.Painter, tyControls.TyLabel, tyControls.Terminal.Core,
  tyControls.Terminal.Render, tyControls.DropButtons,
  tbdiff, tbeditorlook, tbaisession, tbpreview, tbaiformat, tbaiclient, tbaichecks, tbfakehttp;

type
  TTyControlAccess = class(TTyCustomControl);
  TWinControlAccess = class(TWinControl);
  TControlAccess = class(TControl);

function TbContrast(AFg, ABg: TColor): Double;

  function Rgb(C: TColor): Cardinal;
  begin
    C := ColorToRGB(C);       { $00BBGGRR }
    Result := (Cardinal(C and $FF) shl 16) or Cardinal(C and $FF00) or Cardinal((C shr 16) and $FF);
  end;

begin
  Result := TyTermContrastRatio(TyTermRelativeLuminance(Rgb(AFg)), TyTermRelativeLuminance(Rgb(ABg)));
end;

{ What LCL does to an AutoSize control on the screen and cannot do here (a window never
  shown delays all auto-sizing): the control takes its preferred size -- the width of a
  check box, the height of a wrapping label (a label's preferred width is not its wrap
  width: its width stays). }
procedure AutoSized(AControl: TControl);
var
  w, h: Integer;
begin
  if not AControl.AutoSize then Exit;
  w := 0;
  h := 0;
  TControlAccess(AControl).CalculatePreferredSize(w, h, True);
  if (AControl is TTyLabel) and TTyLabel(AControl).WordWrap then
  begin
    if h > 0 then AControl.Height := h;
  end
  else if w > 0 then
    AControl.Width := w;
end;

{ the anchors and aligns of AParent's children, as a shown window would place them }
procedure LayOut(AParent: TWinControl);
var
  r: TRect;
begin
  r := Rect(0, 0, AParent.Width, AParent.Height);
  TWinControlAccess(AParent).AlignControls(nil, r);
end;

function Overlap(A, B: TControl): Boolean;
var
  r: TRect;
begin
  Result := A.Visible and B.Visible and IntersectRect(r, A.BoundsRect, B.BoundsRect);
end;

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

{ V10: a tinted row -- changed, added, removed, a filler -- is written in a colour of its own
  that reads on its tint (4.5:1), in the tool's light and in its dark appearance. SynEdit
  hands the markup over with clHighlightText, a near white, and that is what the rows were
  written in. }
procedure TTbCompareTests.TestTintedRowsAreReadable;
const
  cModes: array[0..1] of string = ('light', 'dark');
var
  oldTheme, oldMode: string;
  look: TTbEditorColors;
  m: TSynSelectedColor;
  special: Boolean;
  i: Integer;

  procedure Check(AEdit: TObject; ALine: Integer; const AWhat: string);
  begin
    special := False;
    m.Foreground := clHighlightText;      { as SynEdit hands it over }
    m.Background := clHighlight;
    FForm.EditSpecialLineMarkup(AEdit, ALine, special, m);
    AssertTrue(AWhat + ' is tinted', special);
    AssertTrue('V10: ' + AWhat + ' has a text colour of its own (' + cModes[i] + ')',
      (m.Foreground <> clHighlightText) and (m.Foreground <> clNone));
    AssertTrue(Format('V10: %s reads on its tint (%s): %.2f', [AWhat, cModes[i],
      TbContrast(m.Foreground, m.Background)]), TbContrast(m.Foreground, m.Background) >= 4.5);
  end;

begin
  oldTheme := TyDefaultController.ThemeName;
  oldMode := TyDefaultController.Mode;
  m := TSynSelectedColor.Create;
  try
    for i := 0 to High(cModes) do
    begin
      TyDefaultController.ThemeName := 'default';
      TyDefaultController.Mode := cModes[i];
      look := TbEditorColors(TyDefaultController);
      FForm.Prepare(Bars('a|b|c'), Bars('a|x|c|d'), nil, look);
      Check(FForm.LeftEdit, 2, 'a changed line, left');
      Check(FForm.RightEdit, 2, 'a changed line, right');
      Check(FForm.RightEdit, 4, 'an added line');
      Check(FForm.LeftEdit, 4, 'a filler');
      FForm.Prepare(Bars('a|b|c|r'), Bars('a|b|c'), nil, look);
      Check(FForm.LeftEdit, 4, 'a removed line');
    end;
  finally
    m.Free;
    if TyDefaultController.ThemeName <> oldTheme then
      TyDefaultController.ThemeName := oldTheme;
    if TyDefaultController.Mode <> oldMode then
      TyDefaultController.Mode := oldMode;
  end;
end;

{ V11: "Try it in the preview" is not cut short, in English or in Chinese: the box is as
  wide as the painter needs for padding, indicator, gap and caption -- the caption measured
  the way the painter decides to cut it -- and it takes the room the buttons leave. An
  AutoSize check box sized itself by the canvas's measure of the caption, a few pixels short
  of the renderer's with some fonts: "Try it in the previ...". The fonts are the real
  program's (the system font as the fallback: the tests leave it empty, and an empty name
  measures the same both ways). }
procedure TTbCompareTests.TestTheTrialBoxIsNotCut;
const
  cCaptions: array[0..1] of string = ('Try it in the preview', #$E5#$9C#$A8#$E9#$A2#$84#$E8#$A7#$88#$E9#$87#$8C#$E8#$AF#$95#$E7#$9C#$8B);
var
  c: TTyControlAccess;
  s: TTyStyleSet;
  i, ppi, need: Integer;
  oldFallback: string;
begin
  oldFallback := TyFallbackFontName;
  TyFallbackFontName := Screen.SystemFont.Name;
  try
    c := TTyControlAccess(FForm.TrialCheck);
    for i := 0 to High(cCaptions) do
    begin
      c.Caption := cCaptions[i];
      c.Invalidate;           { the floor and the AutoSize width follow the font, as on a theme change }
      AutoSized(c);
      LayOut(FForm.Buttons);
      s := c.CurrentStyle;
      ppi := c.Font.PixelsPerInch;
      if ppi <= 0 then ppi := 96;
      need := MulDiv(s.Padding.Left + s.Padding.Right, ppi, 96) +
        MulDiv(c.ActiveController.Metric('--checkbox-size', TyCheckBoxBox), ppi, 96) +
        MulDiv(c.ActiveController.Metric('--checkbox-gap', TyCheckBoxGap), ppi, 96) +
        TyMeasureRenderedTextWidth(cCaptions[i], s.FontName, c.ResolveFontSize(s), s.FontWeight, ppi);
      AssertTrue(Format('V11: "%s" is whole: %d px for %d', [cCaptions[i], c.Width, need]),
        c.Width >= need);
      AssertTrue(Format('V11: the box takes the room left of the buttons (to %d, Accept at %d)',
        [c.Left + c.Width, FForm.BtnAccept.Left]), c.Left + c.Width >= FForm.BtnAccept.Left - 20);
      AssertFalse('V11: clear of Accept', Overlap(c, FForm.BtnAccept));
    end;
  finally
    TyFallbackFontName := oldFallback;
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

{ G10: a key pasted with a tab and a line break is cleaned as it comes in (the settings
  would refuse it, half way through OK); a save that fails leaves the window open, says so,
  and the settings as they are on disk }
procedure TTbAiSettingsFormTests.TestOkChecksBeforeItChanges;
var
  blocker: string;
  s: TTbAiSettings;
  f: TTbAiSettingsForm;
  fs: TFileStream;
begin
  FForm.AddPreset(tapDeepSeek);
  FForm.EdtKey.Text := 'sk-test'#9'0000-g10'#13#10;
  AssertEquals('G10: the pasted key is cleaned', 'sk-test0000-g10', FForm.EdtKey.Text);
  FForm.BtnOk.Click;
  AssertEquals('G10: OK closes', Ord(mrOk), Ord(FForm.ModalResult));
  AssertEquals('G10: kept', 1, FSettings.Count);
  AssertEquals('G10: the clean key', 'sk-test0000-g10', FSettings.GetKey(FSettings.Profile(0).Id));
  { a settings file that cannot be written: a folder under a file }
  blocker := FDir + 'blocker';
  fs := TFileStream.Create(blocker, fmCreate);
  fs.Free;
  s := TTbAiSettings.Create(blocker + PathDelim + 'sub' + PathDelim + 'themebuilder-ai.ini',
    blocker + PathDelim + 'sub' + PathDelim + 'themebuilder-ai.keys');
  f := TTbAiSettingsForm.Create(nil);
  try
    s.Load;
    f.Prepare(s);
    f.AddPreset(tapOllama);
    f.BtnOk.Click;
    AssertEquals('G10: a failed save keeps the window', Ord(mrNone), Ord(f.ModalResult));
    AssertEquals('G10: and says so', Format(rsTbAiSaveFailed, [s.IniFile]), f.TestText);
    AssertEquals('G10: the settings are what the disk has', 0, s.Count);
    AssertEquals('G10: the window still has the change', 1, f.ProfileList.Items.Count);
  finally
    f.Free;
    s.Free;
  end;
end;

{ G11: the Ollama hint is whole (three lines in English here) and what is under it moves
  down for it: the hint had a fixed height, its third line was cut and "Test connection"
  sat where it would have been. The http warning, the other note that shows there, too.
  The fonts are the real program's (see V11). }
procedure TTbAiSettingsFormTests.TestTheOllamaHintIsWhole;
var
  w, h: Integer;
  oldFallback, hint: string;
begin
  oldFallback := TyFallbackFontName;
  TyFallbackFontName := Screen.SystemFont.Name;
  try
    FForm.AddPreset(tapOllama);
    AssertTrue('the hint shows', FForm.LblHint.Visible);
    AssertTrue('G11: the hint sizes itself', FForm.LblHint.AutoSize);
    FForm.LblHint.Invalidate;      { the floor follows the font, as on a theme change }
    AutoSized(FForm.LblHint);
    LayOut(FForm.Fields);
    w := 0;
    h := 0;
    TControlAccess(FForm.LblHint).CalculatePreferredSize(w, h, True);
    AssertTrue(Format('G11: all of the hint (%d px of %d)', [FForm.LblHint.Height, h]),
      FForm.LblHint.Height >= h);
    AssertTrue('G11: the hint under the timeout',
      FForm.LblHint.Top >= FForm.SpnTimeout.Top + FForm.SpnTimeout.Height);
    AssertTrue(Format('G11: Test connection under the hint (at %d, the hint ends at %d)',
      [FForm.BtnTest.Top, FForm.LblHint.Top + FForm.LblHint.Height]),
      FForm.BtnTest.Top >= FForm.LblHint.Top + FForm.LblHint.Height);
    AssertFalse('G11: the button clear of the privacy note', Overlap(FForm.BtnTest, FForm.LblPrivacy));
    AssertFalse('G11: the result clear of the privacy note', Overlap(FForm.LblTest, FForm.LblPrivacy));
    { a much longer hint (a translation, a bigger font): the button goes down with it }
    hint := FForm.LblHint.Caption;
    FForm.LblHint.Caption := hint + ' ' + hint + ' ' + hint + ' ' + hint;
    AutoSized(FForm.LblHint);
    LayOut(FForm.Fields);
    AssertTrue('a longer hint is taller', FForm.LblHint.Height > h);
    AssertTrue(Format('G11: Test connection under a longer hint (at %d, the hint ends at %d)',
      [FForm.BtnTest.Top, FForm.LblHint.Top + FForm.LblHint.Height]),
      FForm.BtnTest.Top >= FForm.LblHint.Top + FForm.LblHint.Height);
    AssertEquals('G11: the result line beside the button', FForm.BtnTest.Top, FForm.LblTest.Top);
    { the warning instead of the hint }
    FForm.EdtUrl.Text := 'http://192.0.2.10:11434/v1';
    AssertTrue('the warning shows', FForm.PlainHttpAlert.Visible);
    AssertFalse('and not the hint', FForm.LblHint.Visible);
    LayOut(FForm.Fields);
    AssertTrue('G11: Test connection under the warning',
      FForm.BtnTest.Top >= FForm.PlainHttpAlert.Top + FForm.PlainHttpAlert.Height);
    AssertFalse('G11: the button clear of the privacy note (warning)',
      Overlap(FForm.BtnTest, FForm.LblPrivacy));
    FForm.PlainHttpAlert.Height := FForm.PlainHttpAlert.Height * 2;   { a longer warning }
    LayOut(FForm.Fields);
    AssertTrue('G11: Test connection under a longer warning',
      FForm.BtnTest.Top >= FForm.PlainHttpAlert.Top + FForm.PlainHttpAlert.Height);
    { neither: right under the fields }
    FForm.EdtUrl.Text := 'https://api.openai.com/v1';
    LayOut(FForm.Fields);
    AssertTrue('G11: Test connection under the timeout',
      FForm.BtnTest.Top >= FForm.SpnTimeout.Top + FForm.SpnTimeout.Height);
  finally
    TyFallbackFontName := oldFallback;
  end;
end;

{ G12: "Add" only opens the list of presets: one menu button, a click anywhere on it opens
  the list -- on the split button the caption half did nothing, and its divider ran against
  the caption ("Add|"); sized to its caption, clear of "Remove" }
procedure TTbAiSettingsFormTests.TestAddIsOneMenuButton;
begin
  { never a real menu here: PopUp would wait for the user }
  AssertFalse('no window behind the button', FForm.BtnAdd.HandleAllocated);
  FForm.BtnAdd.Click;
  AssertTrue('G12: a click on Add opens the presets', FForm.BtnAdd.RequestedPopup);
  AssertTrue('G12: the presets', FForm.BtnAdd.DropDownMenu = FForm.PresetMenu);
  AssertTrue('G12: it sizes itself', FForm.BtnAdd.AutoSize);
  AutoSized(FForm.BtnAdd);
  AutoSized(FForm.BtnRemove);
  LayOut(FForm.PaneButtons);
  AssertFalse('G12: clear of Remove', Overlap(FForm.BtnAdd, FForm.BtnRemove));
end;

initialization
  RegisterTest(TTbCompareTests);
  RegisterTest(TTbAiSettingsFormTests);
end.
