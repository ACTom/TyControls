unit test.accent;
{ Theme-system v3 · Phase A: runtime accent (--accent) override layer. A user-picked
  accent must outrank BOTH the active @mode block AND the OS 'system-accent' sentinel
  (D1: explicit pick wins), re-derive the whole interactive palette (hover/border/etc.
  resolve from var(--accent) lazily), survive a mode switch and an additive load, but
  RESET on a REPLACE theme load (D2). Every mutator bumps ThemeVersion (the cache anchor).
  The controller facade SetAccent/ResetAccent/AccentOverride wraps it + fires Changed. }
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel, tyControls.Controller, tyControls.SystemTheme;
type
  TAccentTest = class(TTestCase)
  private
    FChangeCount: Integer;
    procedure OnThemeChanged(Sender: TObject);
    function DualModeCss(const ALightAccent, ADarkAccent: string): string;
  published
    procedure TestOverrideBeatsMode;
    procedure TestOverrideBeatsSystemAccent;
    procedure TestDerivedTokensRecolour;
    procedure TestClearRestoresThemeAccent;
    procedure TestOverrideMutatorsBumpVersion;
    procedure TestReplaceClearsButAdditiveAndSetModeKeep;
    procedure TestControllerSetAccentResetAndChanged;
  end;

implementation

function StubAccent123456: string;
begin
  Result := '#123456';
end;

function TAccentTest.DualModeCss(const ALightAccent, ADarkAccent: string): string;
begin
  Result :=
    'TyButton { background: var(--accent); }' +
    '@mode light { :root { --accent: ' + ALightAccent + '; } }' +
    '@mode dark  { :root { --accent: ' + ADarkAccent + '; } }';
end;

procedure TAccentTest.OnThemeChanged(Sender: TObject);
begin
  Inc(FChangeCount);
end;

procedure TAccentTest.TestOverrideBeatsMode;
var model: TTyStyleModel; s: TTyStyleSet;
begin
  model := TTyStyleModel.Create;
  try
    model.LoadFromCss(DualModeCss('#111111', '#222222'));
    model.SetMode('dark');
    s := model.ResolveStyle('TyButton', '', []);
    AssertEquals('dark @mode accent before override',
      Integer(TyRGB($22, $22, $22)), Integer(s.Background.Color));
    // The override is applied ABOVE the @mode overlay, so it wins even in dark.
    model.SetVarOverride('accent', '#ABCDEF');
    s := model.ResolveStyle('TyButton', '', []);
    AssertEquals('override beats the @mode dark accent',
      Integer(TyRGB($AB, $CD, $EF)), Integer(s.Background.Color));
  finally
    model.Free;
  end;
end;

procedure TAccentTest.TestOverrideBeatsSystemAccent;
var model: TTyStyleModel; s: TTyStyleSet; savedA: TTySystemAccentHook;
begin
  savedA := TySystemAccentHook;
  TySystemAccentHook := @StubAccent123456;   // 'system-accent' -> #123456
  model := TTyStyleModel.Create;
  try
    model.LoadFromCss(':root { --accent: system-accent; } TyButton { background: var(--accent); }');
    s := model.ResolveStyle('TyButton', '', []);
    AssertEquals('resolves the stubbed OS accent first',
      Integer(TyRGB($12, $34, $56)), Integer(s.Background.Color));
    // Leading '--' must be normalised away (stored key = 'accent').
    model.SetVarOverride('--accent', '#0A0B0C');
    s := model.ResolveStyle('TyButton', '', []);
    AssertEquals('override (applied after ApplySystemTokens) beats system-accent',
      Integer(TyRGB($0A, $0B, $0C)), Integer(s.Background.Color));
  finally
    model.Free;
    TySystemAccentHook := savedA;
  end;
end;

procedure TAccentTest.TestDerivedTokensRecolour;
var model: TTyStyleModel; s: TTyStyleSet; beforeBorder: TTyColor;
begin
  model := TTyStyleModel.Create;
  try
    // border-color is DERIVED from the accent via lighten(); overriding only --accent
    // must re-derive it (raw expr stored, resolved lazily by TyEvalColor).
    model.LoadFromCss(
      'TyButton { background: var(--accent); border-color: lighten(var(--accent), 20%); }' +
      '@mode light { :root { --accent: #3366CC; } }' +
      '@mode dark  { :root { --accent: #101010; } }');
    model.SetMode('light');
    s := model.ResolveStyle('TyButton', '', []);
    beforeBorder := s.BorderColor;
    model.SetVarOverride('accent', '#CC3366');
    s := model.ResolveStyle('TyButton', '', []);
    AssertEquals('base bg tracks the override',
      Integer(TyRGB($CC, $33, $66)), Integer(s.Background.Color));
    AssertTrue('derived border-color re-derived from the new accent',
      Integer(s.BorderColor) <> Integer(beforeBorder));
    AssertTrue('derived border-color is not the raw accent (lighten applied)',
      Integer(s.BorderColor) <> Integer(TyRGB($CC, $33, $66)));
  finally
    model.Free;
  end;
end;

procedure TAccentTest.TestClearRestoresThemeAccent;
var model: TTyStyleModel; s: TTyStyleSet;
begin
  model := TTyStyleModel.Create;
  try
    model.LoadFromCss(DualModeCss('#111111', '#222222'));
    model.SetMode('light');
    model.SetVarOverride('accent', '#ABCDEF');
    AssertEquals('VarOverride returns the set value', '#ABCDEF', model.VarOverride('accent'));
    model.ClearVarOverride('accent');
    s := model.ResolveStyle('TyButton', '', []);
    AssertEquals('cleared -> back to the theme light accent',
      Integer(TyRGB($11, $11, $11)), Integer(s.Background.Color));
    AssertEquals('VarOverride empty after clear', '', model.VarOverride('accent'));
  finally
    model.Free;
  end;
end;

procedure TAccentTest.TestOverrideMutatorsBumpVersion;
var model: TTyStyleModel; v0, v1, v2: Cardinal;
begin
  model := TTyStyleModel.Create;
  try
    model.LoadFromCss(DualModeCss('#111111', '#222222'));
    model.SetMode('light');
    v0 := model.ThemeVersion;
    model.SetVarOverride('accent', '#ABCDEF');
    AssertTrue('SetVarOverride bumps ThemeVersion', model.ThemeVersion > v0);
    v1 := model.ThemeVersion;
    model.ClearVarOverride('accent');
    AssertTrue('ClearVarOverride bumps ThemeVersion', model.ThemeVersion > v1);
    model.SetVarOverride('accent', '#111111');
    model.SetVarOverride('surface', '#222222');
    v2 := model.ThemeVersion;   // capture right BEFORE ClearVarOverrides to isolate its bump
    model.ClearVarOverrides;
    AssertTrue('ClearVarOverrides bumps ThemeVersion', model.ThemeVersion > v2);
  finally
    model.Free;
  end;
end;

procedure TAccentTest.TestReplaceClearsButAdditiveAndSetModeKeep;
var model: TTyStyleModel; s: TTyStyleSet;
begin
  model := TTyStyleModel.Create;
  try
    model.LoadFromCss(DualModeCss('#111111', '#222222'));
    model.SetMode('light');
    model.SetVarOverride('accent', '#ABCDEF');
    // A mode switch KEEPS the override (D1: survives light/dark flip).
    model.SetMode('dark');
    AssertEquals('override survives a mode switch', '#ABCDEF', model.VarOverride('accent'));
    s := model.ResolveStyle('TyButton', '', []);
    AssertEquals('override still applied after the mode switch',
      Integer(TyRGB($AB, $CD, $EF)), Integer(s.Background.Color));
    // An ADDITIVE load KEEPS the override (compose, not a theme switch).
    model.LoadFromCssAdditive('TyButton { border-width: 2px; }');
    AssertEquals('override survives an additive load', '#ABCDEF', model.VarOverride('accent'));
    // A REPLACE load CLEARS the override (D2: a new theme is a curated whole).
    model.LoadFromCss(DualModeCss('#333333', '#444444'));
    model.SetMode('light');
    AssertEquals('replace load clears the override', '', model.VarOverride('accent'));
    s := model.ResolveStyle('TyButton', '', []);
    AssertEquals('the new theme''s own accent applies after replace',
      Integer(TyRGB($33, $33, $33)), Integer(s.Background.Color));
  finally
    model.Free;
  end;
end;

procedure TAccentTest.TestControllerSetAccentResetAndChanged;
var c: TTyStyleController; s: TTyStyleSet;
begin
  c := TTyStyleController.Create(nil);
  try
    c.AddChangeListener(@OnThemeChanged);
    c.LoadThemeCss(DualModeCss('#111111', '#222222'));  // auto-seeds default mode (light)
    FChangeCount := 0;
    c.SetAccent('#ABCDEF');
    AssertTrue('SetAccent fires Changed', FChangeCount > 0);
    AssertEquals('AccentOverride reflects the pick', '#ABCDEF', c.AccentOverride);
    s := c.Model.ResolveStyle('TyButton', '', []);
    AssertEquals('SetAccent recolours via the override',
      Integer(TyRGB($AB, $CD, $EF)), Integer(s.Background.Color));
    FChangeCount := 0;
    c.ResetAccent;
    AssertTrue('ResetAccent fires Changed', FChangeCount > 0);
    AssertEquals('AccentOverride cleared after reset', '', c.AccentOverride);
    s := c.Model.ResolveStyle('TyButton', '', []);
    AssertEquals('reset restores the theme''s own accent',
      Integer(TyRGB($11, $11, $11)), Integer(s.Background.Color));
  finally
    c.RemoveChangeListener(@OnThemeChanged);
    c.Free;
  end;
end;

initialization
  RegisterTest(TAccentTest);
end.
