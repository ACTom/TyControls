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
    { Phase 1 on-accent fix }
    procedure TestDarkOnAccentReadable;
    { green = the image-background + frosted-glass theme; guard its resolution }
    procedure TestGreenImageAndGlass;
    { the demo's real path: switch FROM another theme INTO green (REPLACE) }
    procedure TestGreenAfterLightSwitch;
    { every bundled theme ships the ghost variant + TyBadge tokens }
    procedure TestAllThemesHaveGhostAndBadge;
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
    function DumpThemeMode(const APath, AMode: string): string;
    procedure CheckGolden(const AThemeName: string);
  published
    procedure TestLightGolden;
    procedure TestDarkGolden;
    procedure TestShowcaseGolden;
    { P3 (D7) single-file dual-mode fidelity (§7 risk-3 zero-pixel route): auto.tycss in
      'light' mode resolves byte-identically to light.tycss, and in 'dark' mode to
      dark.tycss, across the full (typeKey x variant x state) grid. This is the proof that
      @mode carries both modes pixel-faithfully. }
    procedure TestAutoLightEqualsLight;
    procedure TestAutoDarkEqualsDark;
  end;
implementation

function TTestThemes.ThemePath(const AName: string): string;
begin
  // Resolve relative to the test executable (in /tests) so the path does not
  // depend on the current working directory.
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim
    + 'themes' + PathDelim + AName;
end;

procedure TTestThemes.TestAllThemesHaveGhostAndBadge;
const
  Names: array[0..5] of string = ('light', 'dark', 'green', 'showcase', 'system', 'auto');
var
  i: Integer;
  m: TTyStyleModel;
  g, b: TTyStyleSet;
begin
  for i := 0 to High(Names) do
  begin
    m := TTyStyleModel.Create;
    try
      m.LoadFromFile(ThemePath(Names[i] + '.tycss'));
      m.Mode := 'light';   // dual-mode (system/auto) need an active mode; no-op for single-mode themes
      g := m.ResolveStyle('TyButton', 'ghost', []);
      AssertTrue(Names[i] + ': ghost has background', tpBackground in g.Present);
      AssertTrue(Names[i] + ': ghost base transparent (alpha 0)',
        TyAlphaOf(g.Background.Color) = 0);
      b := m.ResolveStyle('TyBadge', '', []);
      AssertTrue(Names[i] + ': TyBadge has background', tpBackground in b.Present);
    finally
      m.Free;
    end;
  end;
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

procedure TTestThemes.TestDarkOnAccentReadable;
var model: TTyStyleModel; s: TTyStyleSet;
begin
  // on-accent fix: dark TyCheckBox:active / TyRadioButton:active ink must be the dark
  // #0B1120 (was #FFFFFF — low-contrast white on the light-blue dark accent). on() unifies.
  model := TTyStyleModel.Create;
  try
    model.LoadFromFile(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' +
      PathDelim + 'dark.tycss');
    s := model.ResolveStyle('TyCheckBox', '', [tysActive]);
    AssertEquals('dark checkbox:active ink = 0B1120', TTyColor($FF0B1120), s.TextColor);
    s := model.ResolveStyle('TyRadioButton', '', [tysActive]);
    AssertEquals('dark radio:active ink = 0B1120', TTyColor($FF0B1120), s.TextColor);
  finally
    model.Free;
  end;
end;

procedure TTestThemes.TestGreenImageAndGlass;
var model: TTyStyleModel; s: TTyStyleSet;
begin
  // Regression guard: green is the image-background + frosted-glass demo theme.
  // After the v2 engine refactor it must STILL resolve TyForm to an image fill and
  // expose glass on its panels (the demo's whole point).
  model := TTyStyleModel.Create;
  try
    model.LoadFromFile(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' +
      PathDelim + 'green.tycss');
    s := model.ResolveStyle('TyForm', '', []);
    AssertEquals('green TyForm background kind', Ord(tfkImage), Ord(s.Background.Kind));
    AssertTrue('green TyForm image path set', s.Background.ImagePath <> '');
    // The resolved path must be LOADABLE — the painter loads this file at paint time,
    // long after GThemeBaseDir was cleared, so resolve-time eval must still find it.
    AssertTrue('green TyForm image is a real file: ' + s.Background.ImagePath,
      FileExists(s.Background.ImagePath));
    AssertEquals('green MaxGlassBlur', 16, model.MaxGlassBlur);
    s := model.ResolveStyle('TyPanel', '', []);
    AssertTrue('green TyPanel has glass', tpGlass in s.Present);
    AssertEquals('green TyPanel glass-blur', 16, s.Background.GlassBlur);
  finally
    model.Free;
  end;
end;

procedure TTestThemes.TestGreenAfterLightSwitch;
var model: TTyStyleModel; s: TTyStyleSet; base: string;
begin
  // Reproduce the demo EXACTLY: load light first (FormCreate), then switch to green
  // (Btn click). §3.8 switch = REPLACE; green's image+glass must survive the swap.
  base := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim;
  model := TTyStyleModel.Create;
  try
    model.LoadFromFile(base + 'light.tycss');   // FormCreate
    model.LoadFromFile(base + 'green.tycss');   // BtnGreenClick (REPLACE)
    s := model.ResolveStyle('TyForm', '', []);
    AssertTrue('switched TyForm background present', tpBackground in s.Present);
    AssertEquals('switched TyForm background kind', Ord(tfkImage), Ord(s.Background.Kind));
    AssertTrue('switched TyForm image path set', s.Background.ImagePath <> '');
    AssertTrue('switched TyForm image is a real file: ' + s.Background.ImagePath,
      FileExists(s.Background.ImagePath));
    AssertEquals('switched MaxGlassBlur', 16, model.MaxGlassBlur);
    s := model.ResolveStyle('TyPanel', '', []);
    AssertTrue('switched TyPanel has glass', tpGlass in s.Present);
    AssertEquals('switched TyPanel glass-blur', 16, s.Background.GlassBlur);
  finally
    model.Free;
  end;
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
var bg: string;
begin
  // Kind-aware: only dump fields the fill Kind actually sets. Gradient/solid fills
  // leave the image/glass fields uninitialized (ParseLinearGradient does not
  // Default()-init), so dumping them unconditionally is non-deterministic.
  bg := 'k' + IntToStr(Ord(ts.Background.Kind));
  case ts.Background.Kind of
    tfkSolid: bg := bg + '/' + GHex(ts.Background.Color);
    tfkLinearGradient: bg := bg + '/' + GHex(ts.Background.GradFrom) + '>' +
      GHex(ts.Background.GradTo) + '@' + IntToStr(Round(ts.Background.GradAngleDeg * 100));
    tfkImage: bg := bg + '/' + ts.Background.ImagePath + '/m' +
      IntToStr(Ord(ts.Background.ImageMode)) + '/bl' + IntToStr(ts.Background.Blur);
    tfkNineSlice: bg := bg + '/' + ts.Background.ImagePath;
  end;
  if tpGlass in ts.Present then
    bg := bg + '/glass' + IntToStr(ts.Background.GlassBlur) + ':' + GHex(ts.Background.GlassTint);
  Result :=
    'pres[' + GPresent(ts.Present) + '] bg=' + bg +
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
  GGRID: array[0..36] of string = (
    'TyForm|', 'TyButton|', 'TyButton|primary', 'TyButton|danger', 'TyLabel|',
    'TyEdit|', 'TyCheckBox|', 'TyRadioButton|', 'TyPanel|', 'TyComboBox|',
    'TyScrollBar|', 'TyScrollThumb|', 'TyTitleBar|', 'TyCaptionButton|',
    'TyCaptionButton|close', 'TyCaptionButton|min', 'TyCaptionButton|max',
    'TyListBox|', 'TyListItem|', 'TyProgressBar|', 'TyProgressFill|',
    'TyToggleSwitch|', 'TyToggleKnob|', 'TyTrackBar|', 'TyTrackThumb|',
    'TyGroupBox|', 'TyTabControl|', 'TyTab|', 'TyTabClose|', 'TySpinEdit|',
    'TyMemo|', 'TyTextSelection|', 'TyTextHint|',
    'TyMenuBar|', 'TyMenuItem|', 'TyMenuPopup|', 'TyMenuView|');

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

function TTestThemeGolden.DumpThemeMode(const APath, AMode: string): string;
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
    model.SetMode(AMode);   // P3: select the active @mode block before resolving
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

procedure TTestThemeGolden.TestAutoLightEqualsLight;
var autoDump, lightDump: string;
begin
  autoDump := DumpThemeMode(ThemePath('auto.tycss'), 'light');
  lightDump := DumpTheme(ThemePath('light.tycss'));
  AssertEquals('auto.tycss in light mode must resolve byte-identically to light.tycss',
    lightDump, autoDump);
end;

procedure TTestThemeGolden.TestAutoDarkEqualsDark;
var autoDump, darkDump: string;
begin
  autoDump := DumpThemeMode(ThemePath('auto.tycss'), 'dark');
  darkDump := DumpTheme(ThemePath('dark.tycss'));
  AssertEquals('auto.tycss in dark mode must resolve byte-identically to dark.tycss',
    darkDump, autoDump);
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
