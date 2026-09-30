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
  end;

const
  { a document whose one value no base theme has }
  cMarkerDoc = 'TyButton { background: #123456; }';

implementation

uses
  Controls, FileUtil, BGRABitmap, BGRABitmapTypes, tyControls.Types, tyControls.Base,
  tbtemplates;

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

initialization
  RegisterTest(TTbPreviewTests);
end.
