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
  tyControls.Types, tyControls.StyleModel, tyControls.Controller, tyControls.SystemTheme,
  tyControls.Css.Values;
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
    procedure TestOnAccentContrastReDerives;
    procedure TestModeVaryingTokenFlipsWhileAccentPinned;
    procedure TestRefreshSystemTokensKeepsOverride;
    procedure TestClearRestoresThemeAccent;
    procedure TestOverrideMutatorsBumpVersion;
    procedure TestReplaceClearsButAdditiveAndSetModeKeep;
    procedure TestBadValueRejectedKeepsPriorState;
    procedure TestControllerSetAccentResetAndChanged;
    procedure TestHotReloadPreservesAccent;
  end;

implementation

function StubAccent123456: string;
begin
  Result := '#123456';
end;

function StubAccentAABBCC: string;
begin
  Result := '#AABBCC';
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
var model: TTyStyleModel; s: TTyStyleSet;
begin
  model := TTyStyleModel.Create;
  try
    // border-color (lighten) and selection (alpha) are DERIVED from the accent; overriding
    // only --accent must re-derive BOTH exactly (raw expr stored, resolved lazily). Expected
    // values are computed by evaluating the same expression on the picked colour directly.
    model.LoadFromCss(
      'TyButton { background: var(--accent); border-color: lighten(var(--accent), 20%); }' +
      'TyButton:selected { background: alpha(var(--accent), 0.30); }' +
      '@mode light { :root { --accent: #3366CC; } }' +
      '@mode dark  { :root { --accent: #101010; } }');
    model.SetMode('light');
    model.SetVarOverride('accent', '#CC3366');
    s := model.ResolveStyle('TyButton', '', []);
    AssertEquals('base bg tracks the override',
      Integer(TyRGB($CC, $33, $66)), Integer(s.Background.Color));
    AssertEquals('derived border-color == lighten(new accent, 20%) exactly',
      Integer(TyEvalColor('lighten(#CC3366, 20%)', nil)), Integer(s.BorderColor));
    // alpha() derivation (a different function) must also track the new accent.
    s := model.ResolveStyle('TyButton', '', [tysSelected]);
    AssertEquals('derived selection fill == alpha(new accent, 0.30) exactly',
      Integer(TyEvalColor('alpha(#CC3366, 0.30)', nil)), Integer(s.Background.Color));
  finally
    model.Free;
  end;
end;

procedure TAccentTest.TestOnAccentContrastReDerives;
var model: TTyStyleModel; inkDark, inkLight: TTyColor;
begin
  // on(var(--accent)) picks a readable ink for the accent. The spec's whole "recolour from
  // one seed" promise depends on this re-deriving: a picked LIGHT accent must flip the ink to
  // dark (else button text goes invisible). Assert the ink flips AND equals on(new accent).
  model := TTyStyleModel.Create;
  try
    model.LoadFromCss(
      'TyButton { background: var(--accent); color: on(var(--accent)); }' +
      '@mode light { :root { --accent: #202020; } }');   // dark seed -> light ink
    model.SetMode('light');
    inkDark := model.ResolveStyle('TyButton', '', []).TextColor;
    model.SetVarOverride('accent', '#FFEE00');            // light pick -> ink must flip dark
    inkLight := model.ResolveStyle('TyButton', '', []).TextColor;
    AssertTrue('on-accent ink flips when the accent flips dark->light',
      Integer(inkDark) <> Integer(inkLight));
    AssertEquals('on-accent ink == on(picked accent) exactly',
      Integer(TyEvalColor('on(#FFEE00)', nil)), Integer(inkLight));
  finally
    model.Free;
  end;
end;

procedure TAccentTest.TestModeVaryingTokenFlipsWhileAccentPinned;
var model: TTyStyleModel; s: TTyStyleSet;
begin
  // D1: an accent override must NOT freeze OTHER per-mode tokens. --surface varies by mode;
  // pin the accent, then flip light->dark: surface must flip while the accent stays pinned.
  model := TTyStyleModel.Create;
  try
    model.LoadFromCss(
      'TyButton { background: var(--surface); border-color: var(--accent); }' +
      '@mode light { :root { --surface: #FFFFFF; --accent: #111111; } }' +
      '@mode dark  { :root { --surface: #1E1E1E; --accent: #222222; } }');
    model.SetMode('light');
    model.SetVarOverride('accent', '#ABCDEF');
    s := model.ResolveStyle('TyButton', '', []);
    AssertEquals('light surface', Integer(TyRGB($FF, $FF, $FF)), Integer(s.Background.Color));
    AssertEquals('accent pinned in light', Integer(TyRGB($AB, $CD, $EF)), Integer(s.BorderColor));
    model.SetMode('dark');
    s := model.ResolveStyle('TyButton', '', []);
    AssertEquals('surface flipped to dark (mode-follow unaffected)',
      Integer(TyRGB($1E, $1E, $1E)), Integer(s.Background.Color));
    AssertEquals('accent STILL pinned after the mode flip',
      Integer(TyRGB($AB, $CD, $EF)), Integer(s.BorderColor));
  finally
    model.Free;
  end;
end;

procedure TAccentTest.TestRefreshSystemTokensKeepsOverride;
var model: TTyStyleModel; s: TTyStyleSet; savedA: TTySystemAccentHook;
begin
  // The live OS-accent-change path is RefreshSystemTokens (re-merge, re-resolve system-accent).
  // With an override set, an OS accent change must NOT clobber the user's pick (D1, live path).
  savedA := TySystemAccentHook;
  model := TTyStyleModel.Create;
  try
    TySystemAccentHook := @StubAccent123456;   // OS accent #123456
    model.LoadFromCss(':root { --accent: system-accent; } TyButton { background: var(--accent); }');
    model.SetVarOverride('accent', '#0A0B0C');
    // Simulate the OS accent changing to another colour, then a live refresh.
    TySystemAccentHook := @StubAccentAABBCC;
    model.RefreshSystemTokens;
    s := model.ResolveStyle('TyButton', '', []);
    AssertEquals('override survives a live OS-accent change (RefreshSystemTokens)',
      Integer(TyRGB($0A, $0B, $0C)), Integer(s.Background.Color));
  finally
    model.Free;
    TySystemAccentHook := savedA;
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
    // An ADDITIVE load KEEPS the override (compose, not a theme switch) — check it is still
    // both stored AND applied (a merge that dropped it would slip past a string-only check).
    model.LoadFromCssAdditive('TyButton { border-width: 2px; }');
    AssertEquals('override survives an additive load', '#ABCDEF', model.VarOverride('accent'));
    s := model.ResolveStyle('TyButton', '', []);
    AssertEquals('override still APPLIED (resolved) after an additive load',
      Integer(TyRGB($AB, $CD, $EF)), Integer(s.Background.Color));
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

procedure TAccentTest.TestBadValueRejectedKeepsPriorState;
var model: TTyStyleModel; s: TTyStyleSet; v1: Cardinal; raised: Boolean;
begin
  // A bad override value must be REJECTED at the SetVarOverride call (fail-fast), leaving the
  // prior state intact — NOT committed to then throw on every subsequent paint (the resolve
  // path is unguarded). Mirrors the engine's load-time fail-fast-keeps-previous contract.
  model := TTyStyleModel.Create;
  try
    model.LoadFromCss(DualModeCss('#111111', '#222222'));
    model.SetMode('light');
    model.SetVarOverride('accent', '#ABCDEF');   // a good pick first
    v1 := model.ThemeVersion;
    raised := False;
    try
      model.SetVarOverride('accent', '#12');     // invalid hex -> must raise
    except
      raised := True;
    end;
    AssertTrue('a bad override value raises at the call site', raised);
    AssertEquals('rejected -> ThemeVersion unchanged (no commit)', v1, model.ThemeVersion);
    AssertEquals('rejected -> prior override intact', '#ABCDEF', model.VarOverride('accent'));
    s := model.ResolveStyle('TyButton', '', []);  // must NOT raise; still the good pick
    AssertEquals('rejected -> resolve still yields the prior good accent',
      Integer(TyRGB($AB, $CD, $EF)), Integer(s.Background.Color));
    // An empty value is not an error — it folds into a reset (delete-on-empty made explicit).
    model.SetVarOverride('accent', '');
    AssertEquals('empty value clears the override', '', model.VarOverride('accent'));
  finally
    model.Free;
  end;
end;

procedure TAccentTest.TestHotReloadPreservesAccent;
var c: TTyStyleController; fn: string; sl: TStringList; s: TTyStyleSet;
begin
  // A same-file HOT-RELOAD is not a theme switch, so D2 must NOT reset the accent pick.
  // Process-unique: two test binaries run concurrently (CI shards, a probe build) must not
  // race on one shared path — GetProcessID keeps each run on its own file.
  fn := GetTempDir(False) + 'ty_accent_hotreload_' + IntToStr(GetProcessID) + '.tycss';
  sl := TStringList.Create;
  try
    sl.Text := DualModeCss('#111111', '#222222');
    sl.SaveToFile(fn);
    c := TTyStyleController.Create(nil);
    try
      c.ThemeFile := fn;                 // loads + auto-seeds the default mode
      c.HotReload := True;
      c.SetAccent('#ABCDEF');
      AssertEquals('accent set before reload', '#ABCDEF', c.AccentOverride);
      // Edit the SAME file (different length -> the size stamp changes -> a reload fires).
      sl.Text := DualModeCss('#111111', '#222222') + ' TyLabel { color: #010203; } /* edit */';
      sl.SaveToFile(fn);
      AssertTrue('hot-reload detects the edit', c.PollThemeFile);
      AssertEquals('accent override SURVIVES a same-file hot-reload', '#ABCDEF', c.AccentOverride);
      s := c.Model.ResolveStyle('TyButton', '', []);
      AssertEquals('override still applied after hot-reload',
        Integer(TyRGB($AB, $CD, $EF)), Integer(s.Background.Color));
    finally
      c.Free;
    end;
  finally
    sl.Free;
    if FileExists(fn) then DeleteFile(fn);
  end;
end;

initialization
  RegisterTest(TAccentTest);
end.
