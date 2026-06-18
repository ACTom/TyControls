unit test.themeregistry;
{$mode objfpc}{$H+}
{ B — Named theme registry tests (theme-system v2, Phase 2).

  Covers: register / resolve / case-insensitivity / unregister / names listing, and the
  load-bearing SWITCH-NOT-STACK regression: switching Controller.ThemeName from A to B
  must REPLACE layer-1 (not stack), so a property A set but B does NOT set resolves to the
  BASE value, never A's residual value (§3.8 / §7 risk 6). }
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel, tyControls.Controller,
  tyControls.ThemeRegistry;
type
  TThemeRegistryTest = class(TTestCase)
  private
    FDir: string;
    FFileA, FFileB: string;
    procedure WriteFile(const APath, AContent: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    // registry API
    procedure TestRegisterResolveFile;
    procedure TestResolveCaseInsensitive;
    procedure TestRegisterLastWins;
    procedure TestUnregister;
    procedure TestResolveUnknownReturnsFalse;
    procedure TestThemeNamesListsRegistered;
    procedure TestRegisterEmptyNameIgnored;
    // controller switch path
    procedure TestThemeNameLoadsViaReplacePath;
    procedure TestThemeNameClearsThemeFile;
    procedure TestThemeVersionBumpsOnSwitch;
    // the anti-residual regression
    procedure TestSwitchReplacesNotStacks_CascadeOn;
    procedure TestSwitchReplacesNotStacks_CascadeOff;
  end;

implementation

const
  // Theme A sets a DISTINCT TyButton background (not the base #FFFFFF/var(--surface)).
  cThemeA =
    'TyButton {' + LineEnding +
    '  background: #AB1234;' + LineEnding +
    '  color: #111111;' + LineEnding +
    '}' + LineEnding;
  // Theme B sets a TyButton rule but DOES NOT touch background — the regression hinge.
  cThemeB =
    'TyButton {' + LineEnding +
    '  color: #0000FF;' + LineEnding +
    '}' + LineEnding;

procedure TThemeRegistryTest.WriteFile(const APath, AContent: string);
var
  sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.Text := AContent;
    sl.SaveToFile(APath);
  finally
    sl.Free;
  end;
end;

procedure TThemeRegistryTest.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) + 'tyreg_' +
    IntToStr(PtrUInt(Self)) + PathDelim;
  ForceDirectories(FDir);
  FFileA := FDir + 'themeA.tycss';
  FFileB := FDir + 'themeB.tycss';
  WriteFile(FFileA, cThemeA);
  WriteFile(FFileB, cThemeB);
  // Clean slate: these names must not leak between tests.
  TyUnregisterTheme('regA');
  TyUnregisterTheme('regB');
  TyUnregisterTheme('OnLy');
end;

procedure TThemeRegistryTest.TearDown;
begin
  TyUnregisterTheme('regA');
  TyUnregisterTheme('regB');
  TyUnregisterTheme('OnLy');
  if FileExists(FFileA) then DeleteFile(FFileA);
  if FileExists(FFileB) then DeleteFile(FFileB);
  RemoveDir(FDir);
end;

procedure TThemeRegistryTest.TestRegisterResolveFile;
var
  src: string;
begin
  TyRegisterThemeFile('regA', FFileA);
  AssertTrue('regA resolves', TyResolveTheme('regA', src));
  AssertEquals('regA -> file path', FFileA, src);
  AssertTrue('regA registered', TyThemeRegistered('regA'));
end;

procedure TThemeRegistryTest.TestResolveCaseInsensitive;
var
  src: string;
begin
  TyRegisterThemeFile('regA', FFileA);
  AssertTrue('lower resolves', TyResolveTheme('rega', src));
  AssertEquals('lower -> same file', FFileA, src);
  AssertTrue('upper resolves', TyResolveTheme('REGA', src));
  AssertEquals('upper -> same file', FFileA, src);
  AssertTrue('mixed registered', TyThemeRegistered('ReGa'));
end;

procedure TThemeRegistryTest.TestRegisterLastWins;
var
  src: string;
begin
  TyRegisterThemeFile('regA', FFileA);
  // Re-register the same name (different case) with a new path -> last wins, no dup.
  TyRegisterThemeFile('REGA', FFileB);
  AssertTrue('resolves', TyResolveTheme('regA', src));
  AssertEquals('last registration wins', FFileB, src);
end;

procedure TThemeRegistryTest.TestUnregister;
var
  src: string;
begin
  TyRegisterThemeFile('regA', FFileA);
  AssertTrue('registered before', TyThemeRegistered('regA'));
  TyUnregisterTheme('REGA');   // case-insensitive removal
  AssertFalse('not registered after', TyThemeRegistered('regA'));
  AssertFalse('resolve fails after unregister', TyResolveTheme('regA', src));
  AssertEquals('source cleared', '', src);
end;

procedure TThemeRegistryTest.TestResolveUnknownReturnsFalse;
var
  src: string;
begin
  AssertFalse('unknown name', TyResolveTheme('no-such-theme-xyz', src));
  AssertEquals('source empty', '', src);
end;

procedure TThemeRegistryTest.TestThemeNamesListsRegistered;
var
  names: TStringArray;
  i: Integer;
  foundA, foundB: Boolean;
begin
  TyRegisterThemeFile('regA', FFileA);
  TyRegisterThemeFile('regB', FFileB);
  names := TyThemeNames;
  foundA := False; foundB := False;
  for i := 0 to High(names) do
  begin
    if SameText(names[i], 'regA') then foundA := True;
    if SameText(names[i], 'regB') then foundB := True;
  end;
  AssertTrue('regA listed', foundA);
  AssertTrue('regB listed', foundB);
end;

procedure TThemeRegistryTest.TestRegisterEmptyNameIgnored;
var
  src: string;
begin
  TyRegisterThemeFile('', FFileA);
  AssertFalse('empty name not registered', TyResolveTheme('', src));
end;

procedure TThemeRegistryTest.TestThemeNameLoadsViaReplacePath;
var
  c: TTyStyleController;
  s: TTyStyleSet;
begin
  TyRegisterThemeFile('regA', FFileA);
  c := TTyStyleController.Create(nil);
  try
    c.ThemeName := 'regA';
    s := c.Model.ResolveStyle('TyButton', '', []);
    AssertTrue('background present after ThemeName load', tpBackground in s.Present);
    AssertEquals('bg red is A''s #AB', $AB, TyRedOf(s.Background.Color));
    AssertEquals('bg green is A''s #12', $12, TyGreenOf(s.Background.Color));
    AssertEquals('bg blue is A''s #34', $34, TyBlueOf(s.Background.Color));
    AssertEquals('stored ThemeName', 'regA', c.ThemeName);
  finally
    c.Free;
  end;
end;

procedure TThemeRegistryTest.TestThemeNameClearsThemeFile;
var
  c: TTyStyleController;
begin
  TyRegisterThemeFile('regA', FFileA);
  c := TTyStyleController.Create(nil);
  try
    c.ThemeFile := FFileB;
    AssertEquals('ThemeFile set', FFileB, c.ThemeFile);
    c.ThemeName := 'regA';
    // Mutually exclusive: setting ThemeName clears the stored ThemeFile.
    AssertEquals('ThemeFile cleared by ThemeName', '', c.ThemeFile);
    AssertEquals('ThemeName stored', 'regA', c.ThemeName);
    // And the reverse: setting ThemeFile clears ThemeName.
    c.ThemeFile := FFileB;
    AssertEquals('ThemeName cleared by ThemeFile', '', c.ThemeName);
  finally
    c.Free;
  end;
end;

procedure TThemeRegistryTest.TestThemeVersionBumpsOnSwitch;
var
  c: TTyStyleController;
  v0, v1: Cardinal;
begin
  TyRegisterThemeFile('regA', FFileA);
  TyRegisterThemeFile('regB', FFileB);
  c := TTyStyleController.Create(nil);
  try
    c.ThemeName := 'regA';
    v0 := c.Model.ThemeVersion;
    c.ThemeName := 'regB';
    v1 := c.Model.ThemeVersion;
    AssertTrue('ThemeVersion bumps on switch', v1 > v0);
  finally
    c.Free;
  end;
end;

procedure TThemeRegistryTest.TestSwitchReplacesNotStacks_CascadeOn;
{ THE regression (§7 risk 6). With property cascade ON, after A->B the TyButton
  background (set by A, NOT set by B) must resolve to the BASE value var(--surface)
  = #FFFFFF, never A's residual #AB1234. Proves switch=REPLACE-layer-1, not stack. }
var
  c: TTyStyleController;
  s: TTyStyleSet;
begin
  TyRegisterThemeFile('regA', FFileA);
  TyRegisterThemeFile('regB', FFileB);
  c := TTyStyleController.Create(nil);
  try
    c.Model.PropertyCascade := True;   // base bleeds through where user omits
    c.ThemeName := 'regA';
    // sanity: A's background is in effect
    s := c.Model.ResolveStyle('TyButton', '', []);
    AssertEquals('precondition: A bg red', $AB, TyRedOf(s.Background.Color));

    c.ThemeName := 'regB';             // switch — B does NOT set background
    s := c.Model.ResolveStyle('TyButton', '', []);
    AssertTrue('background still present (from base under cascade)',
      tpBackground in s.Present);
    // Must be the BASE value (#FFFFFF), NOT A's residual #AB1234.
    AssertEquals('bg is BASE white red', $FF, TyRedOf(s.Background.Color));
    AssertEquals('bg is BASE white green', $FF, TyGreenOf(s.Background.Color));
    AssertEquals('bg is BASE white blue', $FF, TyBlueOf(s.Background.Color));
    // And B's own color did apply (sanity that B is the active theme).
    AssertEquals('B color blue', $FF, TyBlueOf(s.TextColor));
  finally
    c.Free;
  end;
end;

procedure TThemeRegistryTest.TestSwitchReplacesNotStacks_CascadeOff;
{ Same regression with the DEFAULT all-or-nothing cascade (PropertyCascade=False):
  B's TyButton rule suppresses the entire base layer for TyButton, so after A->B the
  background is simply ABSENT — and in particular NOT A's residual #AB1234. Locks the
  anti-residual invariant under the default (golden) cascade mode too. }
var
  c: TTyStyleController;
  s: TTyStyleSet;
begin
  TyRegisterThemeFile('regA', FFileA);
  TyRegisterThemeFile('regB', FFileB);
  c := TTyStyleController.Create(nil);
  try
    // PropertyCascade stays False (default).
    c.ThemeName := 'regA';
    s := c.Model.ResolveStyle('TyButton', '', []);
    AssertEquals('precondition: A bg red', $AB, TyRedOf(s.Background.Color));

    c.ThemeName := 'regB';             // switch
    s := c.Model.ResolveStyle('TyButton', '', []);
    // Default cascade: B suppresses base for TyButton -> background absent, NOT residual A.
    if tpBackground in s.Present then
      AssertTrue('if present, bg must NOT be A''s residual #AB1234',
        TyRedOf(s.Background.Color) <> $AB);
    // B's own color applied.
    AssertEquals('B color blue', $FF, TyBlueOf(s.TextColor));
  finally
    c.Free;
  end;
end;

initialization
  RegisterTest(TThemeRegistryTest);
end.
