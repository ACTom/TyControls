unit test.systemtheme;
{ P4 (D8 / §3.7) tests. What is verifiable HEADLESS on this Windows box (the registry
  is readable in-process): OS scheme/accent detection never raises and returns plausible
  values; system.tycss resolves TyButton.primary to the detected accent (system-accent
  substitution works); SetMode flips the surface palette; the Controller follow policy
  pulls the detected scheme into Mode. The LIVE WM_SETTINGCHANGE follow path is NOT
  tested here — it needs a real OS light/dark toggle (see the FLAG in tyControls.Form). }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.SystemTheme, tyControls.StyleModel,
  tyControls.Controller;
type
  TSystemThemeTest = class(TTestCase)
  private
    function ThemePath(const AName: string): string;
  published
    procedure TestDetectSchemeNeverRaisesAndConcreteOnWindows;
    procedure TestDetectAccentNeverRaisesAlphaFF;
    procedure TestSchemeToMode;
    procedure TestSystemThemeResolvesAccent;
    procedure TestSystemThemeSetModeFlipsSurface;
    procedure TestControllerFollowSetsModeFromScheme;
  end;

implementation

{ Deterministic stubs so the accent/mode assertions do not depend on the live OS
  state (which differs box-to-box). The TestSystemThemeResolvesAccent test installs
  these, asserts, then restores the live hooks in a finally. }
function StubAccentHook: string;
begin
  Result := '#123456';
end;

function StubModeHookLight: string;
begin
  Result := 'light';
end;

function StubModeHookDark: string;
begin
  Result := 'dark';
end;

function TSystemThemeTest.ThemePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim + AName;
end;

procedure TSystemThemeTest.TestDetectSchemeNeverRaisesAndConcreteOnWindows;
var s: TTySystemScheme;
begin
  // Must not raise on any platform.
  s := TyDetectSystemScheme;
  {$IFDEF WINDOWS}
  // On this Windows box the Personalize key exists, so it must be a CONCRETE answer.
  AssertTrue('Windows scheme must be light or dark (not unknown)',
    (s = tssLight) or (s = tssDark));
  {$ELSE}
  AssertTrue('scheme is a valid enum', s in [tssLight, tssDark, tssUnknown]);
  {$ENDIF}
end;

procedure TSystemThemeTest.TestDetectAccentNeverRaisesAlphaFF;
var c: TTyColor; ok: Boolean;
begin
  // Must not raise; whether True or False, the returned colour must have alpha forced
  // to $FF (a fully-opaque swatch is the contract — see TyDetectSystemAccent).
  ok := TyDetectSystemAccent(c);
  AssertEquals('accent alpha forced to FF', $FF, TyAlphaOf(c));
  {$IFDEF WINDOWS}
  // This box has DWM\AccentColor or ColorizationColor, so detection should succeed.
  AssertTrue('Windows accent detection should succeed on a normal box', ok);
  {$ENDIF}
end;

procedure TSystemThemeTest.TestSchemeToMode;
begin
  AssertEquals('light', TySchemeToMode(tssLight));
  AssertEquals('dark', TySchemeToMode(tssDark));
  AssertEquals('', TySchemeToMode(tssUnknown));
end;

procedure TSystemThemeTest.TestSystemThemeResolvesAccent;
var
  model: TTyStyleModel;
  s: TTyStyleSet;
  savedAccent: TTySystemAccentHook;
  savedMode: TTySystemModeHook;
begin
  // Pin the dynamic tokens to deterministic values so the assertion is box-independent.
  savedAccent := TySystemAccentHook;
  savedMode := TySystemModeHook;
  TySystemAccentHook := @StubAccentHook;   // 'system-accent' -> #123456
  TySystemModeHook := @StubModeHookLight;  // 'system-mode'   -> light
  model := TTyStyleModel.Create;
  try
    AssertTrue('system.tycss must exist', FileExists(ThemePath('system.tycss')));
    model.LoadFromFile(ThemePath('system.tycss'));
    model.SetMode('light');
    // TyButton.primary background = var(--accent) = system-accent = the stubbed #123456.
    s := model.ResolveStyle('TyButton', 'primary', []);
    AssertTrue('TyButton.primary sets Background', tpBackground in s.Present);
    AssertEquals('TyButton.primary bg == detected (stub) accent',
      Integer(TyRGB($12, $34, $56)), Integer(s.Background.Color));
  finally
    model.Free;
    TySystemAccentHook := savedAccent;
    TySystemModeHook := savedMode;
  end;
end;

procedure TSystemThemeTest.TestSystemThemeSetModeFlipsSurface;
var
  model: TTyStyleModel;
  lightBg, darkBg: TTyColor;
  savedAccent: TTySystemAccentHook;
  savedMode: TTySystemModeHook;
begin
  savedAccent := TySystemAccentHook;
  savedMode := TySystemModeHook;
  TySystemAccentHook := @StubAccentHook;
  TySystemModeHook := @StubModeHookLight;
  model := TTyStyleModel.Create;
  try
    model.LoadFromFile(ThemePath('system.tycss'));
    // TyButton base background = var(--surface): light surface is #FFFFFF.
    model.SetMode('light');
    lightBg := model.ResolveStyle('TyButton', '', []).Background.Color;
    AssertEquals('light surface == #FFFFFF',
      Integer(TyRGB($FF, $FF, $FF)), Integer(lightBg));
    // Flip to dark: the surface palette must change (dark surface is #1E1E1E).
    model.SetMode('dark');
    darkBg := model.ResolveStyle('TyButton', '', []).Background.Color;
    AssertEquals('dark surface == #1E1E1E',
      Integer(TyRGB($1E, $1E, $1E)), Integer(darkBg));
    AssertTrue('SetMode flips the surface palette', lightBg <> darkBg);
  finally
    model.Free;
    TySystemAccentHook := savedAccent;
    TySystemModeHook := savedMode;
  end;
end;

procedure TSystemThemeTest.TestControllerFollowSetsModeFromScheme;
var
  c: TTyStyleController;
  savedMode: TTySystemModeHook;
  expectedMode: string;
begin
  // Force the detected scheme to a known value via the mode hook so the assertion is
  // box-independent, but exercise the REAL Controller follow path (Follow := tfFollowSystem
  // -> RefreshFromSystem -> detect scheme -> SetMode). The scheme itself comes from the
  // real TyDetectSystemScheme; we assert the controller's Mode tracks TySchemeToMode of it.
  savedMode := TySystemModeHook;
  c := TTyStyleController.Create(nil);
  try
    c.LoadThemeCss(
      'TyButton { background: var(--accent); }' +
      '@mode light { :root { --accent: #111111; } }' +
      '@mode dark  { :root { --accent: #222222; } }');
    expectedMode := TySchemeToMode(TyDetectSystemScheme);
    c.Follow := tfFollowSystem;
    if expectedMode <> '' then
      AssertEquals('controller Mode follows the detected OS scheme',
        expectedMode, c.Mode)
    else
      // tssUnknown -> follow must NOT blank the mode (leaves it as-is, here '').
      AssertEquals('unknown scheme leaves mode unchanged', '', c.Mode);
    // And follow re-detection is idempotent / inert when set back to manual.
    c.Follow := tfManual;
    AssertEquals('manual keeps the last-followed mode', expectedMode, c.Mode);
  finally
    c.Free;
    TySystemModeHook := savedMode;
  end;
end;

initialization
  RegisterTest(TSystemThemeTest);
end.
