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
    procedure TestAllBuiltinsDrawGapControls;
    procedure TestDraculaPalette;
    procedure TestNordPalette;
  end;

  TControllerThemeNameTest = class(TTestCase)
  published
    procedure TestThemeNameLoadsBuiltinCss;
    procedure TestModePersistsAcrossThemeSwitch;
    procedure TestLightSkinChromeBarsAreFlush;
  end;
implementation

function ThemesPath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim + AName;
end;

procedure TThemeRegistryCssTest.TestRegisterResolveCss;
var css: string;
begin
  TyUnregisterTheme('__t_css');
  AssertFalse('not registered yet', TyResolveThemeCss('__t_css', css));
  TyRegisterThemeCss('__t_css', 'TyButton { background:#010203; }');
  AssertTrue('resolves after register', TyResolveThemeCss('__T_CSS', css)); // case-insensitive
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
var n: TStringArray; i: Integer; sawDefault, sawSystem, sawOffice: Boolean;
begin
  // The compiled-in pack = the 'default'+'system' pair PLUS every structural skin (office/xp/…),
  // so an app ships them all with no themes/ folder. (The curated palettes stay as files.)
  n := TyBuiltinThemeNames;
  AssertEquals('compiled-in themes = default + system + all skins',
    2 + Length(TyBuiltinSkinNames), Length(n));
  sawDefault := False; sawSystem := False; sawOffice := False;
  for i := 0 to High(n) do
  begin
    if n[i] = 'default' then sawDefault := True;
    if n[i] = 'system'  then sawSystem := True;
    if n[i] = 'office'  then sawOffice := True;
  end;
  AssertTrue('has default', sawDefault);
  AssertTrue('has system', sawSystem);
  AssertTrue('has a structural skin (office)', sawOffice);
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

{ A control whose typeKey no theme defines renders NOTHING: every one of these bails out of its paint
  when the resolved style has no background (as TTyButton.DrawBadge does). That is not a loud
  failure, it is an invisible control — which is exactly how TyCard/TyTag shipped unnoticed with ZERO
  coverage across all 20 themes. This guard is the missing alarm: every compiled-in theme must leave
  every one of the 14 Ant Design-gap controls drawable in BOTH modes.
  Only the SURFACE key of each control is required. The secondary keys (TyCardHeader/TyCardActions/
  TyTagClose/TyAlertClose/TyPaginationItem/TyStepsConnector/TyCascaderItem/...) are documented as
  optional and degrade gracefully (no background => no band/chip; no colour => the parent's ink), so
  demanding a background of them would enforce a look the contract deliberately leaves to the skin.
  NOTE it can only fail when the BASE layer and the skin BOTH lack the key — the compiled-in base
  (generated from themes/light.tycss) backs every theme, so asserting "each skin defines X" through
  ResolveStyle would be fake-green. What this really guards is the original bug: a key defined
  nowhere at all. }
procedure TBuiltinThemesTest.TestAllBuiltinsDrawGapControls;
const
  // Only the SURFACE keys of each control — the ones whose absence means "paints nothing".
  cKeys: array[0..12] of string = (
    'TyCard', 'TyTag', 'TyBadge',                                    // batch 1, first group
    'TyAlert', 'TyNotification', 'TyEmpty', 'TySegmented',           // batch 1, second group
    'TyPagination', 'TySteps', 'TyBreadcrumb',                       // batch 2
    'TyTransfer', 'TyCascader', 'TyPopover');                        // batch 3
    // NOT TTyTreeSelect: it has no key of its own by design — GetStyleTypeKey returns
    // 'TyComboBox' (it IS a combo field), so demanding a 'TyTreeSelect' background here
    // would only force every theme to carry a rule nothing ever resolves.

  procedure CheckMode(m: TTyStyleModel; const AName, AMode: string);
  var k: Integer; s: TTyStyleSet;
  begin
    m.SetMode(AMode);
    for k := 0 to High(cKeys) do
    begin
      s := m.ResolveStyle(cKeys[k], '', []);
      AssertTrue(Format('%s (%s): %s has no background -> the control would paint nothing',
        [AName, AMode, cKeys[k]]), tpBackground in s.Present);
    end;
  end;

var n: TStringArray; i: Integer; m: TTyStyleModel;
begin
  n := TyBuiltinThemeNames;
  for i := 0 to High(n) do
  begin
    m := TTyStyleModel.Create;
    try
      m.LoadFromCss(TyBuiltinThemeCss(n[i]));
      CheckMode(m, n[i], 'light');
      CheckMode(m, n[i], 'dark');
    finally m.Free; end;
  end;
end;

procedure TBuiltinThemesTest.TestDraculaPalette;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromFile(ThemesPath('palettes' + PathDelim + 'dracula.tycss'));   // curated palettes archived in themes/palettes/
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
    m.LoadFromFile(ThemesPath('palettes' + PathDelim + 'nord.tycss'));
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
  TyRegisterThemeDir(ThemesPath('palettes' + PathDelim));   // curated palettes now resolve by name from themes/ files
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
  TyRegisterThemeDir(ThemesPath('palettes' + PathDelim));
  c := TTyStyleController.Create(nil);
  try
    c.Mode := 'dark';
    c.ThemeName := 'nord';
    AssertEquals('mode persists after theme switch', 'dark', c.Mode);
    AssertEquals('nord dark surface R', $2E,
      TyRedOf(c.Model.ResolveStyle('TyButton', '', []).Background.Color));
  finally c.Free; end;
end;

procedure TControllerThemeNameTest.TestLightSkinChromeBarsAreFlush;
{ A skin that sets a light --surface but no --surface-chrome inherits the BASE layer's
  darken(--surface,6%). On a white/near-white skin that tinted band turns the tool bar,
  status bar and scroll tracks into a grey frame around the content — the reported bug
  ("工具条很突兀" + "四周灰色边框"). The four light skins now pin those BARS flush to the
  surface. Headers deliberately keep a tint, so assert that too: flush bars must not have
  been achieved by flattening --surface-chrome itself. }
const
  { skin, and the --surface it declares (the value the bars must sit flush with). Not read off
    another control: a skin may give buttons/panels their own fill (bootstrap does), so the
    surface is asserted against the documented token value. }
  SKINS: array[0..3] of string = ('antdesign', 'bootstrap', 'material3', 'ubuntu');
  SURF:  array[0..3] of Integer = ($FFFFFF, $FFFFFF, $FAFAFA, $FAFAFA);
var
  c: TTyStyleController;
  s, hdr: TTyStyleSet;
  i, k: Integer;
  surfR, surfG, surfB: Integer;
begin
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  try
    for i := Low(SKINS) to High(SKINS) do
    begin
      c.ThemeName := SKINS[i];
      c.Mode := 'light';
      surfR := (SURF[i] shr 16) and $FF;
      surfG := (SURF[i] shr 8) and $FF;
      surfB := SURF[i] and $FF;

      for k := 0 to 2 do
      begin
        case k of
          0: s := c.Model.ResolveStyle('TyToolBar', '', []);
          1: s := c.Model.ResolveStyle('TyStatusBar', '', []);
        else s := c.Model.ResolveStyle('TyScrollBar', '', []);
        end;
        AssertEquals(SKINS[i] + ': chrome bar ' + IntToStr(k) + ' R is flush with the surface',
          surfR, TyRedOf(s.Background.Color));
        AssertEquals(SKINS[i] + ': chrome bar ' + IntToStr(k) + ' G is flush with the surface',
          surfG, TyGreenOf(s.Background.Color));
        AssertEquals(SKINS[i] + ': chrome bar ' + IntToStr(k) + ' B is flush with the surface',
          surfB, TyBlueOf(s.Background.Color));
      end;

      // ...but a grid header still reads as a header: it keeps --surface-chrome's tint.
      hdr := c.Model.ResolveStyle('TyGridHeader', '', []);
      AssertTrue(SKINS[i] + ': the grid header keeps a tint distinct from the surface',
        (TyRedOf(hdr.Background.Color) <> surfR) or
        (TyGreenOf(hdr.Background.Color) <> surfG) or
        (TyBlueOf(hdr.Background.Color) <> surfB));
    end;
  finally c.Free; end;
end;

initialization
  RegisterTest(TThemeRegistryCssTest);
  RegisterTest(TBuiltinSyncTest);
  RegisterTest(TBuiltinThemesTest);
  RegisterTest(TControllerThemeNameTest);
end.
