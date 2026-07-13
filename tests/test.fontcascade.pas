unit test.fontcascade;
{ Diagnostic + regression for the "skins look font-enlarged" bug. Hypothesis: a skin that
  declares its own TyButton{} rule suppresses the ENTIRE built-in base TyButton layer under
  the default all-or-nothing property cascade — INCLUDING the base's font-size — so the skin
  resolves FontSize=0 and the control falls back to the OS/LCL font (bigger). The base
  --font-size-base var, however, survives (vars merge separately), so a control CAN recover
  the intended size from it. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel, tyControls.Controller, tyControls.Base,
  tyControls.ThemeRegistry, tyControls.BuiltinThemes, tyControls.Painter;
type
  { Exposes the protected ResolveFontSize so the control-level fix can be tested. }
  TFontProbe = class(TTyCustomControl)
  public
    function CallFS(const AStyle: TTyStyleSet): Integer;
  end;

  TFontCascadeTest = class(TTestCase)
  private
    function ThemePath(const AName: string): string;
  published
    procedure TestBaseButtonHasFontSize;
    procedure TestSkinButtonSuppressesBaseFontSize;
    procedure TestSkinStillResolvesFontSizeBaseVar;
    procedure TestControlRecoversBaseFontUnderSkin;
    procedure TestExplicitControlFontStillWins;
    procedure TestSharedHelperPriority;
    procedure TestAppPathThemeNameSeededMode;
    procedure TestNilControllerFallsBackToDefault;
    procedure TestSkinFontSizeMatchesDefault;
    procedure TestControllerSyncsPainterFallback;
  end;

implementation

function TFontProbe.CallFS(const AStyle: TTyStyleSet): Integer;
begin
  Result := ResolveFontSize(AStyle);
end;

function TFontCascadeTest.ThemePath(const AName: string): string;
{ the structural skins (breeze, …) moved to themes/builtin/ when they were compiled in. }
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim
            + 'builtin' + PathDelim + AName;
end;

procedure TFontCascadeTest.TestBaseButtonHasFontSize;
{ Pure built-in base (what the app's 'default' theme resolves to): TyButton carries
  font-size: var(--font-size-base) = 9. }
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.SetMode('light');
    s := m.ResolveStyle('TyButton', '', []);
    AssertEquals('base TyButton font-size', 9, s.FontSize);
  finally m.Free; end;
end;

procedure TFontCascadeTest.TestSkinButtonSuppressesBaseFontSize;
{ A file skin (breeze) declares TyButton{} with no font-size → under all-or-nothing cascade
  the base font-size is suppressed → resolved FontSize = 0 (the bug's mechanism). }
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromFile(ThemePath('breeze.tycss'));
    m.SetMode('light');
    s := m.ResolveStyle('TyButton', '', []);
    AssertEquals('skin TyButton font-size (suppressed base)', 0, s.FontSize);
  finally m.Free; end;
end;

procedure TFontCascadeTest.TestSkinStillResolvesFontSizeBaseVar;
{ The recovery path: even though the typeKey rule suppressed font-size, the base
  --font-size-base var survives the skin load, so a control can fall back to it. }
var m: TTyStyleModel;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromFile(ThemePath('breeze.tycss'));
    m.SetMode('light');
    AssertEquals('--font-size-base survives skin load', 9, m.ResolveMetric('--font-size-base', 0));
  finally m.Free; end;
end;

procedure TFontCascadeTest.TestControlRecoversBaseFontUnderSkin;
{ The FIX: with the skin's typeKey rule suppressing font-size (AStyle.FontSize=0) AND an INHERITED
  big OS/system font (ParentFont=True — simulated by a parent with Font.Size 20, which headless is
  0 for a rootless control, hence the parent), the control must recover the theme's --font-size-base
  (9), NOT the inherited 20. OLD behaviour returned 20 (the visible "enlarged" bug); FIXED returns 9.
  A faithfulness guard asserts the inheritance actually took (else the test would be fake-green). }
var c: TTyStyleController; parent, p: TFontProbe; empty: TTyStyleSet;
begin
  c := TTyStyleController.Create(nil);
  parent := TFontProbe.Create(nil);
  try
    c.ThemeFile := ThemePath('breeze.tycss');
    c.Mode := 'light';
    parent.Font.Size := 20;            // the form/system font a real machine carries
    p := TFontProbe.Create(parent);
    p.Parent := parent;               // p inherits the big font, ParentFont stays True (not explicit)
    p.Controller := c;
    empty := Default(TTyStyleSet);     // FontSize = 0 (skin suppressed the base font-size)
    AssertTrue('probe font is inherited (ParentFont)', p.ParentFont);
    AssertEquals('probe inherited the big system font (sim faithful)', 20, p.Font.Size);
    AssertEquals('inherited OS font ignored; theme base font used', 9, p.CallFS(empty));
  finally
    parent.Free;                       // frees the owned child p too
    c.Free;
  end;
end;

procedure TFontCascadeTest.TestExplicitControlFontStillWins;
{ Contract preserved: an EXPLICITLY-set control Font.Size (ParentFont becomes False) still wins
  over the theme base var when the theme omits a font-size for that typeKey. }
var c: TTyStyleController; p: TFontProbe; empty: TTyStyleSet;
begin
  c := TTyStyleController.Create(nil);
  p := TFontProbe.Create(nil);
  try
    c.ThemeFile := ThemePath('breeze.tycss');
    c.Mode := 'light';
    p.Controller := c;
    p.Font.Size := 14;                 // explicit override → ParentFont False
    empty := Default(TTyStyleSet);
    AssertFalse('explicit font clears ParentFont', p.ParentFont);
    AssertEquals('explicit control Font.Size honoured', 14, p.CallFS(empty));
  finally
    p.Free;
    c.Free;
  end;
end;

procedure TFontCascadeTest.TestSharedHelperPriority;
{ The single shared brain every ty control (windowed + the graphic label family) delegates to.
  Covers all four priority branches directly. }
var c: TTyStyleController; sTheme, sEmpty: TTyStyleSet;
begin
  c := TTyStyleController.Create(nil);
  try
    c.ThemeFile := ThemePath('breeze.tycss');
    c.Mode := 'light';
    sEmpty := Default(TTyStyleSet);                    // FontSize 0 (skin suppressed the base rule)
    sTheme := Default(TTyStyleSet); sTheme.FontSize := 12;
    AssertEquals('1. theme font-size wins',              12, TyResolveFontSize(sTheme, True,  20, c));
    AssertEquals('2. inherited font -> theme base var',   9, TyResolveFontSize(sEmpty, True,  20, c));
    AssertEquals('3. explicit control font honoured',    14, TyResolveFontSize(sEmpty, False, 14, c));
    AssertEquals('4. no controller -> readable default',  9, TyResolveFontSize(sEmpty, True,   0, nil));
  finally c.Free; end;
end;

procedure TFontCascadeTest.TestAppPathThemeNameSeededMode;
{ Reproduce the theming example EXACTLY: register the themes/ dir, set ThemeName (not ThemeFile),
  and do NOT set an explicit mode — the controller must SEED a mode itself. Then the recovery
  var must still resolve to 9. This isolates "explicit mode (unit test) vs seeded mode (app)". }
var c: TTyStyleController;
begin
  TyRegisterBuiltinThemes;
  TyRegisterThemeDir(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim);
  c := TTyStyleController.Create(nil);
  try
    c.ThemeName := 'breeze';            // app path: pick from the combo, no explicit mode
    AssertTrue('a mode was seeded (not empty)', c.Mode <> '');
    AssertEquals('--font-size-base resolves under seeded-mode ThemeName', 9, c.Metric('--font-size-base', 0));
  finally c.Free; end;
end;

procedure TFontCascadeTest.TestNilControllerFallsBackToDefault;
{ The EXACT app path: the theming form's controls have Controller=nil and are themed by the
  GLOBAL TyDefaultController (set to a skin). ActiveController must fall back to it so the
  --font-size-base recovery still fires — else a nil AController skips the var and the control
  uses the big inherited font (the reported "其他主题字体都很大"). }
var parent, p: TFontProbe; empty: TTyStyleSet; savedTheme: string;
begin
  TyRegisterBuiltinThemes;
  TyRegisterThemeDir(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim);
  savedTheme := TyDefaultController.ThemeName;
  parent := TFontProbe.Create(nil);
  try
    TyDefaultController.ThemeName := 'breeze';   // global default = a skin, like the app
    parent.Font.Size := 20;
    p := TFontProbe.Create(parent);
    p.Parent := parent;                          // Controller stays nil → ActiveController = TyDefaultController
    empty := Default(TTyStyleSet);
    AssertTrue('probe has no explicit controller', p.Controller = nil);
    AssertEquals('nil-controller control recovers theme base font (not OS font)', 9, p.CallFS(empty));
  finally
    parent.Free;
    TyDefaultController.ThemeName := savedTheme;  // restore global state
  end;
end;

procedure TFontCascadeTest.TestSkinFontSizeMatchesDefault;
{ The direct answer to "are the skin fonts the same size as default?": resolve the effective
  font size for several controls under a SKIN (adwaita) exactly as the app does (global
  TyDefaultController, nil-controller control, a big inherited system font) and assert each
  equals default's 9px. Any skin that sets no font-size (all 13 do) matches default. }
var
  parent, p: TFontProbe;
  savedTheme: string;

  procedure ExpectNine(const AKey: string);
  var s: TTyStyleSet;
  begin
    s := TyDefaultController.Model.ResolveStyle(AKey, '', []);
    AssertEquals(AKey + ' under adwaita resolves to 9 (== default)', 9, p.CallFS(s));
  end;

begin
  TyRegisterBuiltinThemes;
  TyRegisterThemeDir(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim);
  savedTheme := TyDefaultController.ThemeName;
  parent := TFontProbe.Create(nil);
  try
    TyDefaultController.ThemeName := 'adwaita';
    parent.Font.Size := 20;                     // big inherited system font, like a real machine
    p := TFontProbe.Create(parent);
    p.Parent := parent;                         // nil controller → ActiveController = TyDefaultController
    ExpectNine('TyButton');
    ExpectNine('TyLabel');
    ExpectNine('TyCheckBox');
    ExpectNine('TyComboBox');
    ExpectNine('TyEdit');
  finally
    parent.Free;
    TyDefaultController.ThemeName := savedTheme;
  end;
end;

procedure TFontCascadeTest.TestControllerSyncsPainterFallback;
{ Safety net: applying a theme syncs the painter's zero-size text fallback to that theme's
  --font-size-base, so any draw site that slips through with a suppressed (0) font-size still
  renders at the theme size (9), not a hardcoded default. }
var c: TTyStyleController; saved: Integer;
begin
  TyRegisterBuiltinThemes;
  TyRegisterThemeDir(ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim);
  saved := TyFallbackFontSize;
  try
    c := TTyStyleController.Create(nil);
    try
      TyFallbackFontSize := 99;      // clobber to prove the sync actually writes it
      c.ThemeName := 'breeze';       // triggers Changed → sync from --font-size-base
      AssertEquals('painter fallback synced to theme base', 9, TyFallbackFontSize);
    finally c.Free; end;
  finally
    TyFallbackFontSize := saved;
  end;
end;

initialization
  RegisterTest(TFontCascadeTest);
end.
