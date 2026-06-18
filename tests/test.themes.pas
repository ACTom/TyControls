unit test.themes;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel;
type
  TTestThemes = class(TTestCase)
  private
    function ThemePath(const AName: string): string;
    procedure CheckTheme(const AName: string);
    procedure CheckThemeNewTypeKeys(const AName: string);
    procedure CheckThemeTabControlTypeKeys(const AName: string);
    procedure CheckThemeFormTypeKey(const AName: string);
  published
    procedure TestLightLoadsAndResolvesButton;
    procedure TestDarkLoadsAndResolvesButton;
    procedure TestShowcaseLoadsAndResolvesButton;
    { v1.1 typeKey assertions — one method per theme }
    procedure TestLightStylesNewTypeKeys;
    procedure TestDarkStylesNewTypeKeys;
    procedure TestShowcaseStylesNewTypeKeys;
    { v1.2 typeKey assertions — TabControl }
    procedure TestLightStylesTabControlTypeKeys;
    procedure TestDarkStylesTabControlTypeKeys;
    procedure TestShowcaseStylesTabControlTypeKeys;
    { v1.5.1 typeKey assertions — TyForm window background }
    procedure TestLightStylesFormTypeKey;
    procedure TestDarkStylesFormTypeKey;
    procedure TestShowcaseStylesFormTypeKey;
  end;

  { Golden resolved-style dump. Loads each shipped theme, resolves a full grid of
    (typeKey x variant x state) and serializes every TTyStyleSet field, comparing to
    a committed golden. The shipped themes have no other pixel-value test, so this is
    the guard that catches ANY value change (e.g. a Phase 1 tier substitution that is
    not value-preserving). Bootstraps the golden file on first run; writes a .actual
    alongside on mismatch for diffing. }
  TTestThemeGolden = class(TTestCase)
  private
    function ThemePath(const AName: string): string;
    function GoldenPath(const AName: string): string;
    function DumpTheme(const APath: string): string;
    procedure CheckGolden(const AThemeName: string);
  published
    procedure TestLightGolden;
    procedure TestDarkGolden;
    procedure TestShowcaseGolden;
  end;
implementation

function TTestThemes.ThemePath(const AName: string): string;
begin
  // Resolve relative to the test executable (in /tests) so the path does not
  // depend on the current working directory.
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim
    + 'themes' + PathDelim + AName;
end;

procedure TTestThemes.CheckTheme(const AName: string);
var
  model: TTyStyleModel;
  base, prim: TTyStyleSet;
begin
  model := TTyStyleModel.Create;
  try
    AssertTrue('theme file must exist: ' + AName,
      FileExists(ThemePath(AName)));
    model.LoadFromFile(ThemePath(AName));
    base := model.ResolveStyle('TyButton', '', []);
    AssertTrue('TyButton base must set Background: ' + AName,
      tpBackground in base.Present);
    AssertTrue('TyButton base must set TextColor: ' + AName,
      tpTextColor in base.Present);
    prim := model.ResolveStyle('TyButton', 'primary', [tysHover]);
    AssertTrue('TyButton.primary:hover must set Background: ' + AName,
      tpBackground in prim.Present);
  finally
    model.Free;
  end;
end;

{ v1.1: assert all 8 new typeKeys are styled correctly in the given theme }
procedure TTestThemes.CheckThemeNewTypeKeys(const AName: string);
var
  model: TTyStyleModel;
  s: TTyStyleSet;
begin
  model := TTyStyleModel.Create;
  try
    AssertTrue('theme file must exist: ' + AName,
      FileExists(ThemePath(AName)));
    model.LoadFromFile(ThemePath(AName));

    { TyListBox base: must have Background }
    s := model.ResolveStyle('TyListBox', '', []);
    AssertTrue('TyListBox base must set Background: ' + AName,
      tpBackground in s.Present);

    { TyListItem:active: must have Background (accent selection highlight) }
    s := model.ResolveStyle('TyListItem', '', [tysActive]);
    AssertTrue('TyListItem:active must set Background: ' + AName,
      tpBackground in s.Present);

    { TyProgressFill base: must have Background (the fill colour) }
    s := model.ResolveStyle('TyProgressFill', '', []);
    AssertTrue('TyProgressFill base must set Background: ' + AName,
      tpBackground in s.Present);

    { TyToggleSwitch:active: must have Background (ON-state track colour) }
    s := model.ResolveStyle('TyToggleSwitch', '', [tysActive]);
    AssertTrue('TyToggleSwitch:active must set Background: ' + AName,
      tpBackground in s.Present);

    { TyTrackThumb base: must have Background (thumb fill) }
    s := model.ResolveStyle('TyTrackThumb', '', []);
    AssertTrue('TyTrackThumb base must set Background: ' + AName,
      tpBackground in s.Present);

    { TyGroupBox base: must have BorderColor (the group border line) }
    s := model.ResolveStyle('TyGroupBox', '', []);
    AssertTrue('TyGroupBox base must set BorderColor: ' + AName,
      tpBorderColor in s.Present);

  finally
    model.Free;
  end;
end;

procedure TTestThemes.TestLightLoadsAndResolvesButton;
begin
  CheckTheme('light.tycss');
end;

procedure TTestThemes.TestDarkLoadsAndResolvesButton;
begin
  CheckTheme('dark.tycss');
end;

procedure TTestThemes.TestShowcaseLoadsAndResolvesButton;
begin
  CheckTheme('showcase.tycss');
end;

procedure TTestThemes.TestLightStylesNewTypeKeys;
begin
  CheckThemeNewTypeKeys('light.tycss');
end;

procedure TTestThemes.TestDarkStylesNewTypeKeys;
begin
  CheckThemeNewTypeKeys('dark.tycss');
end;

procedure TTestThemes.TestShowcaseStylesNewTypeKeys;
begin
  CheckThemeNewTypeKeys('showcase.tycss');
end;

{ v1.2: assert TyTabControl base and TyTab:active are styled in the given theme }
procedure TTestThemes.CheckThemeTabControlTypeKeys(const AName: string);
var
  model: TTyStyleModel;
  s: TTyStyleSet;
begin
  model := TTyStyleModel.Create;
  try
    AssertTrue('theme file must exist: ' + AName,
      FileExists(ThemePath(AName)));
    model.LoadFromFile(ThemePath(AName));

    { TyTabControl base: must have Background (content area surface) }
    s := model.ResolveStyle('TyTabControl', '', []);
    AssertTrue('TyTabControl base must set Background: ' + AName,
      tpBackground in s.Present);

    { TyTab:active: must have Background (selected tab highlight) }
    s := model.ResolveStyle('TyTab', '', [tysActive]);
    AssertTrue('TyTab:active must set Background: ' + AName,
      tpBackground in s.Present);

  finally
    model.Free;
  end;
end;

procedure TTestThemes.TestLightStylesTabControlTypeKeys;
begin
  CheckThemeTabControlTypeKeys('light.tycss');
end;

procedure TTestThemes.TestDarkStylesTabControlTypeKeys;
begin
  CheckThemeTabControlTypeKeys('dark.tycss');
end;

procedure TTestThemes.TestShowcaseStylesTabControlTypeKeys;
begin
  CheckThemeTabControlTypeKeys('showcase.tycss');
end;

{ v1.5.1: assert TyForm defines a solid window background in the given theme }
procedure TTestThemes.CheckThemeFormTypeKey(const AName: string);
var
  model: TTyStyleModel;
  s: TTyStyleSet;
begin
  model := TTyStyleModel.Create;
  try
    AssertTrue('theme file must exist: ' + AName,
      FileExists(ThemePath(AName)));
    model.LoadFromFile(ThemePath(AName));

    { TyForm base: must have Background (the window/form backdrop) }
    s := model.ResolveStyle('TyForm', '', []);
    AssertTrue('TyForm base must set Background: ' + AName,
      tpBackground in s.Present);
    AssertTrue('TyForm background must be solid: ' + AName,
      s.Background.Kind = tfkSolid);

  finally
    model.Free;
  end;
end;

procedure TTestThemes.TestLightStylesFormTypeKey;
begin
  CheckThemeFormTypeKey('light.tycss');
end;

procedure TTestThemes.TestDarkStylesFormTypeKey;
begin
  CheckThemeFormTypeKey('dark.tycss');
end;

procedure TTestThemes.TestShowcaseStylesFormTypeKey;
begin
  CheckThemeFormTypeKey('showcase.tycss');
end;

{ ── Golden resolved-style dump ─────────────────────────────────────────────── }

function GHex(c: TTyColor): string;
begin
  Result := IntToHex(Cardinal(c), 8);
end;

function GPresent(const p: TTyPropSet): string;
var pr: TTyProp;
begin
  Result := '';
  for pr := Low(TTyProp) to High(TTyProp) do
    if pr in p then Result := Result + IntToStr(Ord(pr)) + ',';
end;

function GDumpStyle(const ts: TTyStyleSet): string;
begin
  Result :=
    'pres[' + GPresent(ts.Present) + ']' +
    ' bg=' + IntToStr(Ord(ts.Background.Kind)) + '/' + GHex(ts.Background.Color) +
      '/' + GHex(ts.Background.GradFrom) + '/' + GHex(ts.Background.GradTo) +
      '/a' + IntToStr(Round(ts.Background.GradAngleDeg * 100)) +
      '/' + ts.Background.ImagePath + '/m' + IntToStr(Ord(ts.Background.ImageMode)) +
      '/bl' + IntToStr(ts.Background.Blur) + '/gb' + IntToStr(ts.Background.GlassBlur) +
      '/gt' + GHex(ts.Background.GlassTint) +
    ' ut=' + IntToStr(Ord(ts.BackgroundUnderTitlebar)) +
    ' txt=' + GHex(ts.TextColor) +
    ' bd=' + GHex(ts.BorderColor) + '/' + IntToStr(ts.BorderWidth) + '/' + IntToStr(Ord(ts.BorderStyle)) +
    ' rad=' + IntToStr(ts.BorderRadius) + '/' + IntToStr(ts.Radius.TL) + ',' + IntToStr(ts.Radius.TR) +
      ',' + IntToStr(ts.Radius.BR) + ',' + IntToStr(ts.Radius.BL) +
    ' pad=' + IntToStr(ts.Padding.Left) + ',' + IntToStr(ts.Padding.Top) + ',' +
      IntToStr(ts.Padding.Right) + ',' + IntToStr(ts.Padding.Bottom) +
    ' fnt=' + ts.FontName + '/' + IntToStr(ts.FontSize) + '/' + IntToStr(ts.FontWeight) +
    ' op=' + IntToStr(Round(ts.Opacity * 1000)) +
    ' sh=' + GHex(ts.ShadowColor) + '/' + IntToStr(ts.ShadowBlur) + '/' +
      IntToStr(ts.ShadowOffset.X) + ',' + IntToStr(ts.ShadowOffset.Y) +
    ' ol=' + GHex(ts.OutlineColor) + '/' + IntToStr(ts.OutlineWidth) + '/' + IntToStr(ts.OutlineOffset);
end;

const
  GGRID: array[0..32] of string = (
    'TyForm|', 'TyButton|', 'TyButton|primary', 'TyButton|danger', 'TyLabel|',
    'TyEdit|', 'TyCheckBox|', 'TyRadioButton|', 'TyPanel|', 'TyComboBox|',
    'TyScrollBar|', 'TyScrollThumb|', 'TyTitleBar|', 'TyCaptionButton|',
    'TyCaptionButton|close', 'TyCaptionButton|min', 'TyCaptionButton|max',
    'TyListBox|', 'TyListItem|', 'TyProgressBar|', 'TyProgressFill|',
    'TyToggleSwitch|', 'TyToggleKnob|', 'TyTrackBar|', 'TyTrackThumb|',
    'TyGroupBox|', 'TyTabControl|', 'TyTab|', 'TyTabClose|', 'TySpinEdit|',
    'TyMemo|', 'TyTextSelection|', 'TyTextHint|');

function TTestThemeGolden.ThemePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim + AName;
end;

function TTestThemeGolden.GoldenPath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'golden' + PathDelim + AName;
end;

function TTestThemeGolden.DumpTheme(const APath: string): string;
const
  STATES: array[0..4] of TTyStateSet = ([], [tysHover], [tysActive], [tysFocused], [tysDisabled]);
var
  model: TTyStyleModel;
  sl: TStringList;
  i, si, bar: Integer;
  key, variant: string;
begin
  model := TTyStyleModel.Create;
  sl := TStringList.Create;
  try
    model.LoadFromFile(APath);
    for i := 0 to High(GGRID) do
    begin
      bar := Pos('|', GGRID[i]);
      key := Copy(GGRID[i], 1, bar - 1);
      variant := Copy(GGRID[i], bar + 1, MaxInt);
      for si := 0 to High(STATES) do
        sl.Add(key + '|' + variant + '|' + IntToStr(si) + ' => ' +
          GDumpStyle(model.ResolveStyle(key, variant, STATES[si])));
    end;
    Result := sl.Text;
  finally
    sl.Free;
    model.Free;
  end;
end;

procedure TTestThemeGolden.CheckGolden(const AThemeName: string);
var
  dump, gpath: string;
  sl: TStringList;
begin
  dump := DumpTheme(ThemePath(AThemeName + '.tycss'));
  gpath := GoldenPath(AThemeName + '.golden.txt');
  if FileExists(gpath) then
  begin
    sl := TStringList.Create;
    try
      sl.LoadFromFile(gpath);
      if sl.Text <> dump then
      begin
        sl.Text := dump;
        sl.SaveToFile(gpath + '.actual');
        Fail('Theme ' + AThemeName + ' resolved styles changed vs golden. Diff ' +
          gpath + ' against ' + gpath + '.actual; if intended, update the golden.');
      end;
    finally
      sl.Free;
    end;
  end
  else
  begin
    ForceDirectories(ExtractFilePath(gpath));
    sl := TStringList.Create;
    try
      sl.Text := dump;
      sl.SaveToFile(gpath);
    finally
      sl.Free;
    end;
    // bootstrap: golden created this run, nothing to assert
  end;
end;

procedure TTestThemeGolden.TestLightGolden;
begin
  CheckGolden('light');
end;

procedure TTestThemeGolden.TestDarkGolden;
begin
  CheckGolden('dark');
end;

procedure TTestThemeGolden.TestShowcaseGolden;
begin
  CheckGolden('showcase');
end;

initialization
  RegisterTest(TTestThemes);
  RegisterTest(TTestThemeGolden);
end.
