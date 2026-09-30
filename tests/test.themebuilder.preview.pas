unit test.themebuilder.preview;
{ The theme builder's preview frame (phase 1). Built headless (no parent). Its controls are
  on the frame's own style controller, not the tool's (the strip above them stays on the
  tool's); a document loads over the base the way an application loads a theme, url() from
  the document's folder; a document that does not load, or loads and does not resolve (a
  variable only one mode defines), leaves the last good version in place. The switches
  (light / dark, density, disable all) and the pop-ups follow in the second half. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, tyControls.Controller, tbpreview;

type
  TTbPreviewTests = class(TTestCase)
  private
    FFrame: TTbPreviewFrame;
    FThemeName, FMode: string;
    FDensity: TTyDensity;
    function ButtonBg(AController: TTyStyleController): Integer;
    function Load(const AText: string; const ADir: string = ''): Boolean;
    function CountTy(AParent: TObject; AController: TTyStyleController;
      out AOthers: Integer): Integer;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEightPages;
    procedure TestEveryControlIsOnThePreviewController;
    procedure TestThePreviewIsIndependent;
    procedure TestABrokenDocumentKeepsTheLastOne;
    procedure TestAVariableOfTheOtherModeIsFine;
    procedure TestAVariableMissingInTheShownModeIsRefused;
    procedure TestUrlResolvesFromTheDocumentFolder;
    procedure TestTheModeNote;
    procedure TestTheProbeTriesVariantsAndStates;
    procedure TestDarkIsRefusedWhenItDoesNotResolve;
    procedure TestDarkWithTheMinimalTemplate;
    procedure TestTheDocumentSurvivesADensityChange;
    procedure TestDisableAllAndBack;
    procedure TestTheDialogWearsThePreviewTheme;
    procedure TestTheSampleWindow;
    procedure TestTheSampleWindowFollowsTheDocument;
    procedure TestTheProbeIsQuick;
  end;

const
  { a document whose one value no base theme has }
  cMarkerDoc = 'TyButton { background: #123456; }';

implementation

uses
  Controls, Forms, FileUtil, BGRABitmap, BGRABitmapTypes, tyControls.Types, tyControls.Base,
  tyControls.Dialogs, tyControls.BuiltinThemes, tbtemplates, tbsamplewin;

procedure TTbPreviewTests.SetUp;
begin
  FThemeName := TyDefaultController.ThemeName;
  FMode := TyDefaultController.Mode;
  FDensity := TyDefaultController.Density;
  FFrame := TTbPreviewFrame.Create(nil);
end;

procedure TTbPreviewTests.TearDown;
begin
  FreeAndNil(FFrame);
  if TyDefaultController.ThemeName <> FThemeName then
    TyDefaultController.ThemeName := FThemeName;
  if TyDefaultController.Mode <> FMode then
    TyDefaultController.Mode := FMode;
  if TyDefaultController.Density <> FDensity then
    TyDefaultController.Density := FDensity;
end;

function TTbPreviewTests.ButtonBg(AController: TTyStyleController): Integer;
begin
  Result := Integer(Cardinal(AController.Model.ResolveStyle('TyButton', '', []).Background.Color)
    and $FFFFFF);
end;

function TTbPreviewTests.Load(const AText: string; const ADir: string): Boolean;
var
  err: string;
begin
  Result := FFrame.LoadDocument(AText, ADir, err);
end;

function TTbPreviewTests.CountTy(AParent: TObject; AController: TTyStyleController;
  out AOthers: Integer): Integer;

  procedure Walk(AWin: TWinControl);
  var
    i: Integer;
    c: TControl;
    ctl: TTyStyleController;
    isTy: Boolean;
  begin
    for i := 0 to AWin.ControlCount - 1 do
    begin
      c := AWin.Controls[i];
      isTy := True;
      ctl := nil;
      if c is TTyCustomControl then
        ctl := TTyCustomControl(c).Controller
      else if c is TTyGraphicControl then
        ctl := TTyGraphicControl(c).Controller
      else
        isTy := False;
      if isTy then
        if ctl = AController then Inc(Result) else Inc(AOthers);
      if c is TWinControl then
        Walk(TWinControl(c));
    end;
  end;

begin
  Result := 0;
  AOthers := 0;
  Walk(TWinControl(AParent));
end;

procedure TTbPreviewTests.TestEightPages;
const
  cTitles: array[0..7] of string = ('Basic', 'Inputs', 'Lists and trees', 'Grids',
    'Containers and tabs', 'Menus and toolbars', 'Window chrome', 'Feedback');
var
  i: Integer;
begin
  AssertEquals('V1: eight pages', 8, FFrame.Pages.PageCount);
  for i := 0 to 7 do
    AssertEquals('V1: page ' + IntToStr(i), cTitles[i], FFrame.Pages.Pages[i].Caption);
end;

procedure TTbPreviewTests.TestEveryControlIsOnThePreviewController;
var
  n, others: Integer;
begin
  n := CountTy(FFrame.Root, FFrame.Controller, others);
  AssertEquals('V2: every Ty control under Root is on the preview controller', 0, others);
  AssertTrue('V2: and there are many of them: ' + IntToStr(n), n >= 60);
  AssertEquals('V2: StyledControlCount counts them (and Root)', n + 1, FFrame.StyledControlCount);
  AssertTrue('V2: Root itself', FFrame.Root.Controller = FFrame.Controller);
  AssertTrue('V2: the strip stays on the tool (switch)', FFrame.DarkSwitch.Controller = nil);
  AssertTrue('V2: the strip stays on the tool (combo)', FFrame.DensityCombo.Controller = nil);
  AssertTrue('V2: the strip stays on the tool (check)', FFrame.DisableAllCheck.Controller = nil);
  AssertTrue('V2: the popup menu', FFrame.SamplePopup.Controller = FFrame.Controller);
  AssertTrue('V2: the notification', FFrame.SampleNotify.Controller = FFrame.Controller);
end;

procedure TTbPreviewTests.TestThePreviewIsIndependent;
var
  ver: Cardinal;
begin
  AssertTrue('the marker is not the base''s button', ButtonBg(FFrame.BtnDefault.Controller) <> $123456);
  ver := TyDefaultController.Model.ThemeVersion;
  AssertTrue('V3: the marker document loads', Load(cMarkerDoc));
  AssertEquals('V3: the preview''s button wears it', $123456, ButtonBg(FFrame.BtnDefault.Controller));
  AssertTrue('V3: the tool''s controller was not touched',
    TyDefaultController.Model.ThemeVersion = ver);
  AssertTrue('V3: nor does it resolve the marker', ButtonBg(TyDefaultController) <> $123456);
end;

procedure TTbPreviewTests.TestABrokenDocumentKeepsTheLastOne;
var
  ver: Cardinal;
  err: string;
begin
  AssertTrue(Load(cMarkerDoc));
  ver := FFrame.Controller.Model.ThemeVersion;
  AssertFalse('V4: a broken document does not load',
    FFrame.LoadDocument('TyButton { color: red', '', err));
  AssertTrue('V4: and says why', err <> '');
  AssertTrue('V4: the model was not reloaded', FFrame.Controller.Model.ThemeVersion = ver);
  AssertEquals('V4: the button still wears the marker', $123456, ButtonBg(FFrame.Controller));
end;

procedure TTbPreviewTests.TestAVariableOfTheOtherModeIsFine;
begin
  AssertTrue('V5: light uses what light defines', Load(
    '@mode light { :root { --x: #ffffff; } } @mode dark { :root { --z: #000000; } } ' +
    'TyButton { background: var(--x); }'));
end;

procedure TTbPreviewTests.TestAVariableMissingInTheShownModeIsRefused;
var
  err: string;
begin
  AssertTrue(Load(cMarkerDoc));
  AssertFalse('V6: refused', FFrame.LoadDocument(
    '@mode light { :root { --z: #ffffff; } } @mode dark { :root { --x: #000000; } } ' +
    'TyButton { background: var(--x); }', '', err));
  AssertTrue('V6: names the control: ' + err, Pos('TyButton', err) > 0);
  AssertEquals('V6: the last good version is back', $123456, ButtonBg(FFrame.Controller));
  AssertFalse('V6: not the two-mode document', FFrame.HasModes);
end;

procedure TTbPreviewTests.TestUrlResolvesFromTheDocumentFolder;
const
  cDoc = 'TyPanel { background-image: url(a.png) slice(0 0 0 0); }';
var
  dir, path: string;
  bmp: TBGRABitmap;
begin
  dir := IncludeTrailingPathDelimiter(GetTempDir(False)) + 'tb1-url-' + IntToStr(GetProcessID) + PathDelim;
  ForceDirectories(dir);
  try
    bmp := TBGRABitmap.Create(1, 1, BGRAWhite);
    try
      bmp.SaveToFile(dir + 'a.png');
    finally
      bmp.Free;
    end;
    AssertTrue('V7: loads with the folder', Load(cDoc, dir));
    path := FFrame.Controller.Model.ResolveStyle('TyPanel', '', []).Background.ImagePath;
    AssertTrue('V7: the image is the folder''s: ' + path,
      SameText(ExpandFileName(path), ExpandFileName(dir + 'a.png')));
    AssertTrue('V7: loads without one', Load(cDoc, ''));
    path := FFrame.Controller.Model.ResolveStyle('TyPanel', '', []).Background.ImagePath;
    AssertTrue('V7: then it is not the folder''s: ' + path,
      Pos(LowerCase(ExcludeTrailingPathDelimiter(dir)), LowerCase(path)) = 0);
  finally
    DeleteDirectory(ExcludeTrailingPathDelimiter(dir), False);
  end;
end;

procedure TTbPreviewTests.TestTheModeNote;
begin
  AssertTrue(Load(cMarkerDoc));
  AssertFalse('V8: one mode', FFrame.HasModes);
  AssertFalse('V8: the switch is off', FFrame.DarkSwitch.Enabled);
  AssertTrue('V8: and says why', FFrame.ModeNote.Caption <> '');
  AssertTrue(Load(TbMinimalTemplate));
  AssertTrue('V8: two modes', FFrame.HasModes);
  AssertTrue('V8: the switch is on', FFrame.DarkSwitch.Enabled);
  AssertEquals('V8: nothing to say', '', FFrame.ModeNote.Caption);
end;

procedure TTbPreviewTests.TestTheProbeTriesVariantsAndStates;
var
  err: string;
begin
  AssertFalse('V9: refused', FFrame.LoadDocument(
    '@mode light { :root { --z: #ffffff; } } @mode dark { :root { --y: #000000; } } ' +
    'TyButton.primary:hover { background: var(--y); }', '', err));
  AssertEquals('V9: it was the variant, hovered: ' + err, 1, Pos('TyButton.primary: ', err));
end;

procedure TTbPreviewTests.TestDarkIsRefusedWhenItDoesNotResolve;
var
  err, head: string;
  ok: Boolean;
begin
  AssertTrue(Load('@mode light { :root { --x: #ffffff; } } @mode dark { :root { --z: #000000; } } ' +
    'TyButton { background: var(--x); }'));
  AssertFalse('the light mode is shown', FFrame.IsDark);
  ok := FFrame.SetDark(True, err);
  AssertFalse('V10: dark is refused', ok);
  head := Format(rsTbModeFailed, [rsTbModeDark, '']);
  AssertEquals('V10: it says which mode: ' + err, 1, Pos(head, err));
  AssertTrue('V10: and which control: ' + err, Pos('TyButton', err) > 0);
  AssertFalse('V10: still light', FFrame.IsDark);
  AssertTrue('V10: the frame remembers the refusal', FFrame.ModeError <> '');
  AssertTrue('V10: light is fine', FFrame.SetDark(False, err));
end;

procedure TTbPreviewTests.TestDarkWithTheMinimalTemplate;
var
  err: string;
begin
  AssertTrue(Load(TbMinimalTemplate));
  AssertTrue('V11: dark resolves', FFrame.SetDark(True, err));
  AssertTrue('V11: dark', FFrame.IsDark);
  AssertTrue('V11: the switch shows it', FFrame.DarkSwitch.Checked);
  { a document that resolves in light only: shown in light, then refused dark }
  AssertTrue('back to light', FFrame.SetDark(False, err));
  AssertTrue(Load('@mode light { :root { --x: #ffffff; } } @mode dark { :root { --z: #000000; } } ' +
    'TyButton { background: var(--x); }'));
  FFrame.SetDark(True, err);
  AssertTrue('a refusal was remembered', FFrame.ModeError <> '');
  AssertFalse('V11: the switch sprang back', FFrame.DarkSwitch.Checked);
  AssertTrue(Load(TbMinimalTemplate));
  AssertEquals('V11: a good load clears it', '', FFrame.ModeError);
end;

procedure TTbPreviewTests.TestTheDocumentSurvivesADensityChange;
begin
  AssertTrue(Load(cMarkerDoc));
  FFrame.SetModern(True);
  AssertTrue('V12: modern', FFrame.Controller.Density = tdModern);
  AssertTrue('V12: modern', FFrame.IsModern);
  AssertEquals('V12: the combo shows it', 1, FFrame.DensityCombo.ItemIndex);
  AssertEquals('V12: the document is still loaded', $123456, ButtonBg(FFrame.Controller));
  FFrame.SetModern(False);
  AssertTrue('V12: classic', FFrame.Controller.Density = tdClassic);
  AssertEquals('V12: and still loaded', $123456, ButtonBg(FFrame.Controller));
end;

procedure TTbPreviewTests.TestDisableAllAndBack;
begin
  AssertFalse('designed disabled', FFrame.BtnDisabled.Enabled);
  AssertTrue('designed enabled', FFrame.BtnDefault.Enabled);
  FFrame.SetAllDisabled(True);
  AssertTrue('V13: all disabled', FFrame.AllDisabled);
  AssertFalse('V13: a button', FFrame.BtnDefault.Enabled);
  AssertFalse('V13: an edit', FFrame.EdtText.Enabled);
  AssertFalse('V13: a tree', FFrame.TreSample.Enabled);
  AssertFalse('V13: a nested page control', FFrame.InnerPages.Enabled);
  AssertTrue('V13: the pages still switch', FFrame.Pages.Enabled);
  AssertTrue('V13: and so do their sheets', FFrame.TabBasic.Enabled);
  FFrame.SetAllDisabled(False);
  AssertTrue('V13: back', FFrame.BtnDefault.Enabled);
  AssertTrue('V13: back', FFrame.EdtText.Enabled);
  AssertTrue('V13: back', FFrame.TreSample.Enabled);
  AssertTrue('V13: back', FFrame.InnerPages.Enabled);
  AssertFalse('V13: a designed-disabled button stays disabled', FFrame.BtnDisabled.Enabled);
  AssertFalse('V13: a designed-disabled edit stays disabled', FFrame.EdtDisabled.Enabled);
end;

procedure TTbPreviewTests.TestTheDialogWearsThePreviewTheme;
var
  d: TTyDialog;
begin
  AssertTrue('no main form in the test runner', Application.MainForm = nil);
  d := FFrame.BuildSampleDialog;
  try
    d.ApplyControllerNow;
    AssertTrue('V14: the dialog', d.Controller = FFrame.Controller);
    AssertTrue('V14: its buttons', d.Buttons[0].Controller = FFrame.Controller);
  finally
    d.Free;
  end;
  d := FFrame.BuildSampleInput;
  try
    d.ApplyControllerNow;
    AssertTrue('V14: the input dialog', d.Controller = FFrame.Controller);
  finally
    d.Free;
  end;
end;

procedure TTbPreviewTests.TestTheSampleWindow;
var
  w: TTbSampleForm;
begin
  w := FFrame.BuildSampleWindow;
  AssertTrue('V15: built once', FFrame.BuildSampleWindow = w);
  AssertTrue('V15: the window', w.Controller = FFrame.Controller);
  AssertTrue('V15: an edit in it', w.EdtName.Controller = FFrame.Controller);
  AssertTrue('V15: a button in it', w.BtnOk.Controller = FFrame.Controller);
  AssertTrue('V15: a real title bar', w.TitleBar = w.Bar);
  FreeAndNil(FFrame);   { the window goes before the controller }
end;

procedure TTbPreviewTests.TestTheSampleWindowFollowsTheDocument;
var
  w: TTbSampleForm;
  ctl: TTyStyleController;
begin
  w := FFrame.BuildSampleWindow;
  ctl := w.BtnCancel.Controller;
  AssertTrue('the window''s button has a controller', ctl <> nil);
  AssertTrue('not the marker yet', ButtonBg(ctl) <> $123456);
  AssertTrue(Load(cMarkerDoc));
  AssertEquals('V16: the window''s button wears the document', $123456,
    ButtonBg(w.BtnCancel.Controller));
end;

{ Every load and every mode switch runs the probe (every catalog typeKey x variants x six
  state sets), so it sits on the typing path. Printed for the sign-off; red only when it
  would be felt (> 200 ms), at which point the plan falls back to fewer states. }
procedure TTbPreviewTests.TestTheProbeIsQuick;

  function MedianMs(const AText: string): Double;
  var
    t: array[0..4] of QWord;
    i, j: Integer;
    start: QWord;
    err: string;
    x: QWord;
  begin
    AssertTrue('loads', Load(AText));
    for i := 0 to 4 do
    begin
      start := GetTickCount64;
      AssertTrue('resolves: ' + err, TbProbeResolve(FFrame.Controller.Model, err));
      t[i] := GetTickCount64 - start;
    end;
    for i := 0 to 3 do
      for j := i + 1 to 4 do
        if t[j] < t[i] then
        begin
          x := t[i]; t[i] := t[j]; t[j] := x;
        end;
    Result := t[2];
  end;

var
  a, b: Double;
begin
  a := MedianMs(TyBuiltinThemeCss('default'));
  b := MedianMs(TbMinimalTemplate);
  WriteLn(Format('TTbPreviewTests.TestTheProbeIsQuick: default theme %.0f ms, minimal template %.0f ms (median of 5)',
    [a, b]));
  AssertTrue('the probe is not felt while typing', (a <= 200) and (b <= 200));
end;

initialization
  RegisterTest(TTbPreviewTests);
end.
