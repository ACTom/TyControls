unit test.systemtheme;
{ P4 (D8 / §3.7) tests. What is verifiable HEADLESS on this Windows box (the registry
  is readable in-process): OS scheme/accent detection never raises and returns plausible
  values; system.tycss resolves TyButton.primary to the detected accent (system-accent
  substitution works); SetMode flips the surface palette; the Controller follow policy
  pulls the detected scheme into Mode; and the live-follow POLL (Controller.PollSystemTheme,
  the seam TTyForm's follow timer drives) re-applies a simulated OS light/dark + accent flip.
  Only the TIMER tick and a real registry toggle need a live GUI/OS; the change-detect+apply
  logic is fully headless (LCL never delivers WM_SETTINGCHANGE to a WndProc — hence the poll). }
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
    procedure TestFollowAdoptsDefaultModeWhenOSUnreadable;
    procedure TestPollSystemThemeAppliesLiveFlip;
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

function StubModeHookUnreadable: string;   // OS scheme not probeable (e.g. Linux: no registry)
begin
  Result := '';
end;

function StubAccentHookB: string;
begin
  Result := '#654321';
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
      // tssUnknown (OS scheme unreadable): follow adopts the theme's DEFAULT mode so a dual-mode
      // theme isn't left mode-less (its @mode-only vars would be undefined). Default here = 'light'.
      AssertEquals('unknown scheme adopts the theme default mode', 'light', c.Mode);
    // And follow re-detection is idempotent / inert when set back to manual.
    c.Follow := tfManual;
    if expectedMode <> '' then
      AssertEquals('manual keeps the last-followed mode', expectedMode, c.Mode)
    else
      AssertEquals('manual keeps the default-adopted mode', 'light', c.Mode);
  finally
    c.Free;
    TySystemModeHook := savedMode;
  end;
end;

procedure TSystemThemeTest.TestFollowAdoptsDefaultModeWhenOSUnreadable;
var c: TTyStyleController; savedMode: TTySystemModeHook; raised: Boolean;
begin
  // Linux repro: the OS-scheme hook returns '' (no registry to probe). A dual-mode theme whose
  // body uses a @mode-only var must NOT be left mode-less — follow adopts the theme's default mode
  // ('light') so the var resolves instead of raising "Undefined variable: --transparent-fill".
  savedMode := TySystemModeHook;
  c := TTyStyleController.Create(nil);
  try
    TySystemModeHook := @StubModeHookUnreadable;
    c.LoadThemeCss(
      'TyButton { background: var(--transparent-fill); }' +
      '@mode light { :root { --transparent-fill: alpha(#FFFFFF, 0); } }' +
      '@mode dark  { :root { --transparent-fill: alpha(#000000, 0); } }');
    // A dual-mode theme now auto-seeds its default mode at LOAD (SeedModeIfDual in
    // Changed) so it is NEVER mode-less and resolve never raises — the fix is no longer
    // deferred to follow. This is the showcase crash scenario: load + paint before any follow.
    AssertEquals('dual-mode load auto-seeds the default mode', 'light', c.Mode);
    raised := False;
    try c.Model.ResolveStyle('TyButton', '', []); except raised := True; end;
    AssertFalse('@mode-only var resolves right after load, before any follow (showcase scenario)', raised);
    c.Follow := tfFollowSystem;
    AssertEquals('unreadable OS -> still the theme default (light)', 'light', c.Mode);
  finally
    c.Free;
    TySystemModeHook := savedMode;
  end;
end;

procedure TSystemThemeTest.TestPollSystemThemeAppliesLiveFlip;
var
  c: TTyStyleController;
  savedMode: TTySystemModeHook;
  savedAccent: TTySystemAccentHook;
begin
  // Exercise the REAL live-follow path (Controller.PollSystemTheme — what TTyForm's follow
  // timer calls each tick) with stubbed OS hooks so a light/dark + accent flip is deterministic
  // and headless. This is the leg the old WM_SETTINGCHANGE WndProc could NEVER reach, because
  // LCL-Win32 swallows that message before it is delivered to any control's WndProc.
  savedMode := TySystemModeHook;
  savedAccent := TySystemAccentHook;
  c := TTyStyleController.Create(nil);
  try
    TySystemModeHook := @StubModeHookLight;
    TySystemAccentHook := @StubAccentHook;        // '#123456'
    c.LoadThemeCss(
      'TyButton { background: var(--accent); }' +
      '@mode light { :root { --accent: #111111; } }' +
      '@mode dark  { :root { --accent: #222222; } }');
    c.Follow := tfFollowSystem;                    // snapshots light/#123456 and applies
    AssertEquals('initial followed mode is light', 'light', c.Mode);
    // No OS change yet -> the poll must be a no-op (cheap to call every tick).
    AssertFalse('poll no-ops when the OS has not changed', c.PollSystemTheme);
    // Simulate the user flipping Windows to Dark.
    TySystemModeHook := @StubModeHookDark;
    AssertTrue('poll detects + applies the dark flip', c.PollSystemTheme);
    AssertEquals('mode followed to dark', 'dark', c.Mode);
    // Idempotent: nothing new -> no-op again.
    AssertFalse('poll no-ops after the flip is applied', c.PollSystemTheme);
    // An accent-only change (same dark mode) is also caught by the change-detect.
    TySystemAccentHook := @StubAccentHookB;         // '#654321'
    AssertTrue('poll detects + applies an accent-only change', c.PollSystemTheme);
    AssertEquals('still dark after the accent-only change', 'dark', c.Mode);
    // Flip back to light.
    TySystemModeHook := @StubModeHookLight;
    AssertTrue('poll applies the flip back to light', c.PollSystemTheme);
    AssertEquals('mode followed back to light', 'light', c.Mode);
    // Inert under manual: an explicit app choice wins, the poll does nothing.
    c.Follow := tfManual;
    TySystemModeHook := @StubModeHookDark;
    AssertFalse('poll is inert under tfManual', c.PollSystemTheme);
    AssertEquals('manual keeps the last applied mode', 'light', c.Mode);
  finally
    c.Free;
    TySystemModeHook := savedMode;
    TySystemAccentHook := savedAccent;
  end;
end;

initialization
  RegisterTest(TSystemThemeTest);
end.
