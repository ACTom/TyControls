unit test.builtinthemes;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel, tyControls.Controller,
  tyControls.ThemeRegistry, tyControls.BuiltinThemes, tyControls.BuiltinThemeData;
type
  TThemeRegistryCssTest = class(TTestCase)
  published
    procedure TestRegisterResolveCss;
    procedure TestNamesMergeFileAndCss;
    procedure TestUnregisterCss;
  end;

  TBuiltinSyncTest = class(TTestCase)
  private
    function ThemePath(const AName: string): string;
    function NormalizeCss(const S: string): string;
  published
    procedure TestDualBaseMatchesAuto;
    procedure TestSystemMatchesSystem;
  end;

  TBuiltinThemesTest = class(TTestCase)
  published
    procedure TestNamesCountAndContents;
    procedure TestAllBuiltinsLoad;
    procedure TestDraculaPalette;
    procedure TestNordPalette;
  end;

  TControllerThemeNameTest = class(TTestCase)
  published
    procedure TestThemeNameLoadsBuiltinCss;
    procedure TestModePersistsAcrossThemeSwitch;
  end;
implementation

procedure TThemeRegistryCssTest.TestRegisterResolveCss;
var css: string;
begin
  TyUnregisterTheme('__t_css');
  AssertFalse('not registered yet', TyResolveThemeCss('__t_css', css));
  TyRegisterThemeCss('__t_css', 'TyButton { background:#010203; }');
  AssertTrue('resolves after register', TyResolveThemeCss('__T_CSS', css)); // 大小写不敏感
  AssertTrue('css round-trips', Pos('#010203', css) > 0);
  AssertTrue('registered flag', TyThemeRegistered('__t_css'));
  TyUnregisterTheme('__t_css');
end;

procedure TThemeRegistryCssTest.TestNamesMergeFileAndCss;
var names: TStringArray; i: Integer; sawFile, sawCss: Boolean;
begin
  TyRegisterThemeFile('__t_file', 'x.tycss');
  TyRegisterThemeCss('__t_css2', 'TyButton{background:#000000;}');
  names := TyThemeNames;
  sawFile := False; sawCss := False;
  for i := 0 to High(names) do
  begin
    if SameText(names[i], '__t_file') then sawFile := True;
    if SameText(names[i], '__t_css2') then sawCss := True;
  end;
  AssertTrue('file source name listed', sawFile);
  AssertTrue('css source name listed', sawCss);
  TyUnregisterTheme('__t_file'); TyUnregisterTheme('__t_css2');
end;

procedure TThemeRegistryCssTest.TestUnregisterCss;
var css: string;
begin
  TyRegisterThemeCss('__t_css3', 'TyButton{background:#000000;}');
  TyUnregisterTheme('__t_css3');
  AssertFalse('gone after unregister', TyResolveThemeCss('__t_css3', css));
  AssertFalse('not registered', TyThemeRegistered('__t_css3'));
end;

function TBuiltinSyncTest.ThemePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim + AName;
end;

function TBuiltinSyncTest.NormalizeCss(const S: string): string;
var sl: TStringList; i: Integer;
begin
  sl := TStringList.Create;
  try
    sl.Text := S;
    for i := 0 to sl.Count - 1 do sl[i] := TrimRight(sl[i]);
    Result := Trim(sl.Text);
  finally sl.Free; end;
end;

procedure TBuiltinSyncTest.TestDualBaseMatchesAuto;
var f: TStringList;
begin
  f := TStringList.Create;
  try
    f.LoadFromFile(ThemePath('auto.tycss'));
    AssertEquals('dual base == auto.tycss', NormalizeCss(f.Text), NormalizeCss(TyBuiltinDualBaseCss));
  finally f.Free; end;
end;

procedure TBuiltinSyncTest.TestSystemMatchesSystem;
var f: TStringList;
begin
  f := TStringList.Create;
  try
    f.LoadFromFile(ThemePath('system.tycss'));
    AssertEquals('system css == system.tycss', NormalizeCss(f.Text), NormalizeCss(TyBuiltinSystemCss));
  finally f.Free; end;
end;

procedure TBuiltinThemesTest.TestNamesCountAndContents;
var n: TStringArray; i: Integer; sawDefault, sawSystem, sawDracula: Boolean;
begin
  n := TyBuiltinThemeNames;
  AssertEquals('12 built-in themes', 12, Length(n));
  sawDefault := False; sawSystem := False; sawDracula := False;
  for i := 0 to High(n) do
  begin
    if n[i] = 'default' then sawDefault := True;
    if n[i] = 'system'  then sawSystem := True;
    if n[i] = 'dracula' then sawDracula := True;
  end;
  AssertTrue('has default', sawDefault);
  AssertTrue('has system', sawSystem);
  AssertTrue('has dracula', sawDracula);
end;

procedure TBuiltinThemesTest.TestAllBuiltinsLoad;
var n: TStringArray; i: Integer; m: TTyStyleModel; s: TTyStyleSet;
begin
  n := TyBuiltinThemeNames;
  for i := 0 to High(n) do
  begin
    m := TTyStyleModel.Create;
    try
      m.LoadFromCss(TyBuiltinThemeCss(n[i]));
      m.SetMode('light');
      s := m.ResolveStyle('TyButton', '', []);
      AssertTrue(n[i] + ' light has bg', tpBackground in s.Present);
      m.SetMode('dark');
      s := m.ResolveStyle('TyButton', '', []);
      AssertTrue(n[i] + ' dark has bg', tpBackground in s.Present);
    finally m.Free; end;
  end;
end;

procedure TBuiltinThemesTest.TestDraculaPalette;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(TyBuiltinThemeCss('dracula'));
    m.SetMode('light');
    s := m.ResolveStyle('TyButton', 'primary', []);   // primary bg = var(--accent)
    AssertEquals('dracula light accent R', $64, TyRedOf(s.Background.Color));
    AssertEquals('dracula light accent G', $4A, TyGreenOf(s.Background.Color));
    AssertEquals('dracula light accent B', $C9, TyBlueOf(s.Background.Color));
    m.SetMode('dark');
    s := m.ResolveStyle('TyButton', 'primary', []);
    AssertEquals('dracula dark accent R', $BD, TyRedOf(s.Background.Color));
    AssertEquals('dracula dark surface R', $28,
      TyRedOf(m.ResolveStyle('TyButton', '', []).Background.Color));
  finally m.Free; end;
end;

procedure TBuiltinThemesTest.TestNordPalette;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(TyBuiltinThemeCss('nord'));
    m.SetMode('dark');
    s := m.ResolveStyle('TyButton', '', []);
    AssertEquals('nord dark surface R', $2E, TyRedOf(s.Background.Color));
    m.SetMode('light');
    s := m.ResolveStyle('TyButton', '', []);
    AssertEquals('nord light surface R', $EC, TyRedOf(s.Background.Color));
  finally m.Free; end;
end;

procedure TControllerThemeNameTest.TestThemeNameLoadsBuiltinCss;
var c: TTyStyleController; s: TTyStyleSet;
begin
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  try
    c.ThemeName := 'gruvbox';
    c.Mode := 'dark';
    s := c.Model.ResolveStyle('TyButton', 'primary', []);   // gruvbox dark accent #FE8019
    AssertEquals('gruvbox dark accent R', $FE, TyRedOf(s.Background.Color));
    AssertEquals('gruvbox dark accent G', $80, TyGreenOf(s.Background.Color));
  finally c.Free; end;
end;

procedure TControllerThemeNameTest.TestModePersistsAcrossThemeSwitch;
var c: TTyStyleController;
begin
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  try
    c.Mode := 'dark';
    c.ThemeName := 'nord';
    AssertEquals('mode persists after theme switch', 'dark', c.Mode);
    AssertEquals('nord dark surface R', $2E,
      TyRedOf(c.Model.ResolveStyle('TyButton', '', []).Background.Color));
  finally c.Free; end;
end;

initialization
  RegisterTest(TThemeRegistryCssTest);
  RegisterTest(TBuiltinSyncTest);
  RegisterTest(TBuiltinThemesTest);
  RegisterTest(TControllerThemeNameTest);
end.
