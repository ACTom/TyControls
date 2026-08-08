unit test.themes;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel, tyControls.Controller,
  tyControls.BuiltinThemes, tyControls.ToolBar;
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
    { a pressed column header must RESOLVE differently from a resting one }
    procedure TestPressedGridHeaderSectionIsNotInert;
    { --tool-rule-alpha: the token now HAS a home, and must agree with the constant }
    procedure TestToolRuleAlphaTokenMatchesTheControlDefault;
    procedure TestToolRuleAlphaReachesEveryBuiltinInBothModes;
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
    procedure CheckAlias(AModel: TTyStyleModel; const ATheme, ANew, ADonor,
      AVariant: string; ABaseStateOnly: Boolean);
    procedure CheckAliasExemptionsWellFormed;
  published
    procedure TestLightGolden;
    procedure TestDarkGolden;
    procedure TestShowcaseGolden;
    { The exemption table itself is under test: every row must name a shipped theme, a
      known alias pair, and a NON-EMPTY reason. An exemption without a reason is
      indistinguishable from an accident, which is the exact thing the alias guard exists
      to prevent — so a blank one fails here AND in the sweep (which validates before it
      skips anything). }
    procedure TestAliasExemptionsAreDeliberate;
    { 3.0 themability pass: every key minted by splitting a borrowed one must still
      resolve BYTE-IDENTICALLY to the key it was split from, in EVERY shipped theme —
      the five under themes/ and all fifteen skins. This is the test that proves the
      split moved no pixel anywhere, not just in the three themes the golden covers.
      It also proves the base-layer claim honestly: a skin that overrides the donor key
      does NOT automatically pass, because base-layer inheritance would hand the new key
      light.tycss's values instead of the skin's. That is precisely why the new selectors
      had to be added to the skins' own rules and not left to inherit.
      DELIBERATE divergence is possible but rationed: a (theme, key) pair listed in
      ALIAS_EXEMPTIONS (with a mandatory reason) is skipped here — and only here; the
      example-theme check below never consults the table. The guard's failure message
      prints the table so the next person extends it instead of blunting the guard. }
    procedure TestNewKeysMatchTheirDonorInEveryTheme;
    { The same check, aimed at the two HAND-WRITTEN example themes under examples/theming/.
      Nothing else in the suite loads them, and that blind spot is not cosmetic: they are the
      worked examples a user copies to start their own theme, and they are the closest thing
      in the repo to a third-party stylesheet. When a borrowed key is split, base-layer
      resolution is all-or-nothing PER TYPEKEY — so a theme that styles the donor and has
      never heard of the new key silently drops back to the built-in light values for it,
      which on the image theme shows up as an opaque grey block on a photo. This test is what
      makes that failure loud instead of a bug report six months later. }
    procedure TestExampleThemesCoverTheNewKeys;
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
  if not FileExists(Result) then      // structural skins (showcase, …) live in themes/builtin/
    Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim
      + 'themes' + PathDelim + 'builtin' + PathDelim + AName;
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

procedure TTestThemes.TestPressedGridHeaderSectionIsNotInert;
{ `TyGridHeaderSection:active` — the PRESSED column header.

  Why this test exists. docs/controls/grid.md records LCL's goHeaderPushedLook as a
  REFUSED flag ("不收"), and the stated reason was this rule's absence: with no :active
  rule, a pressed header resolved straight back to the base's `background: none`, i.e.
  looked exactly like a resting one. Publishing a set member the control cannot honour is
  the defect class TTyGridOption's 21-of-32 census exists to prevent, so the flag was
  correctly withheld until the theme layer could express the state. This rule is that
  half; it must therefore be provably NOT inert, or withholding was pointless.

  The assertion is comparative, not a colour: a pressed header must resolve a background
  that is actually PAINTABLE and that DIFFERS from the resting resolve. Pinning a literal
  colour here would just duplicate the golden and would break on every legitimate reskin.

  Swept over every BUILT-IN theme, which is also the skin-follows guard: the rule lives in
  the base layer (light.tycss) and no shipped skin restyles TyGridHeaderSection today, so
  all of them inherit it. A future skin that takes the key over WITHOUT restating :active
  loses the pressed look, and this sweep is what reports that rather than letting it ship
  as a silently inert flag a second time. }
var
  c: TTyStyleController;
  names: TStringArray;
  i, m: Integer;
  mode: string;
  rest, down: TTyStyleSet;
begin
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  try
    names := TyBuiltinThemeNames;
    AssertTrue('there are built-in themes to check', Length(names) > 0);
    for i := 0 to High(names) do
      for m := 0 to 1 do
      begin
        if m = 0 then mode := 'light' else mode := 'dark';
        c.ThemeName := names[i];
        c.Mode := mode;

        rest := c.Model.ResolveStyle('TyGridHeaderSection', '', []);
        down := c.Model.ResolveStyle('TyGridHeaderSection', '', [tysActive]);

        AssertTrue(Format('%s/%s: TyGridHeaderSection:active must declare a background',
          [names[i], mode]), tpBackground in down.Present);
        AssertTrue(Format('%s/%s: TyGridHeaderSection:active must be a PAINTABLE fill — '
          + 'resolving to `none` is what made the pressed look inert', [names[i], mode]),
          down.Background.Kind <> tfkNone);
        { The inertness assertion proper: pressed must not look like resting. Compare the
          whole fill, not just the colour — a skin could legally move from a solid to a
          gradient here. }
        AssertFalse(Format('%s/%s: a pressed column header resolves IDENTICALLY to a '
          + 'resting one — goHeaderPushedLook would be visually inert again',
          [names[i], mode]),
          (rest.Background.Kind = down.Background.Kind)
          and (rest.Background.Color = down.Background.Color)
          and (rest.Background.GradFrom = down.Background.GradFrom)
          and (rest.Background.GradTo = down.Background.GradTo));
      end;
  finally
    c.Free;
  end;
end;

procedure TTestThemes.TestToolRuleAlphaTokenMatchesTheControlDefault;
{ '--tool-rule-alpha' was PLUMBED before it was DECLARED: TyToolRuleInk read it through
  ActiveController.Metric with a documented default (TyToolRuleGhostAlpha), and no theme
  anywhere defined it. That works, but it puts a visual value in control code rather than
  in the theme layer, which is the one hard rule the theme system has. Declaring it in
  light.tycss's :root moves it — and the base layer is inherited by every theme, so one
  declaration serves all of them.

  Adding it is only SAFE if it agrees with the constant. A token of, say, 60 against a
  documented default of 50 would retune every default flat tool bar's divider with no
  control-code change and no other test in the suite comparing the two — precisely the
  silent drift the golden cannot see, because no RULE references this token so no resolved
  style changes.

  The sentinel is a value no caller would ever pass and no theme could legally hold, so
  "the token is missing" cannot masquerade as agreement: ResolveMetric hands back the
  caller's default when the var is absent or unparseable. }
const
  cSentinel = -12345;
var
  m: TTyStyleModel;
  got: Integer;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromFile(ThemePath('light.tycss'));
    got := m.ResolveMetric(TyToolRuleAlphaVar, cSentinel);
    AssertTrue(Format('light.tycss :root must DEFINE %s — got the sentinel back, which '
      + 'means the token is absent or does not parse as a length',
      [TyToolRuleAlphaVar]), got <> cSentinel);
    AssertEquals(Format('%s and the control''s documented default (TyToolRuleGhostAlpha) '
      + 'must agree, or shipping the token silently retunes every default flat tool bar''s '
      + 'divider', [TyToolRuleAlphaVar]), TyToolRuleGhostAlpha, got);
  finally
    m.Free;
  end;
end;

procedure TTestThemes.TestToolRuleAlphaReachesEveryBuiltinInBothModes;
{ The declaration is worth nothing to a SKIN unless the skin can see it. It is declared in
  the base :root ONLY, and RebuildMergedVars seeds the merged set from the base layer before
  the user :root and the active @mode overlay it — so every built-in should read the same 50
  in both modes without restating it. This sweep proves that inheritance instead of assuming
  it; without it, "a skin can retune the rule" would be a claim about a code path nothing
  exercises across the shipped skins.

  It pins TODAY'S truth: no shipped skin overrides the token, so all 17 x 2 inherit 50. That
  is deliberate rather than lazy — the first skin to retune it SHOULD have to come here, the
  way a deliberate alias divergence has to enter ALIAS_EXEMPTIONS. What must not happen is a
  retune landing by accident, or a theme setting a value the length parser cannot read (which
  fails SILENTLY back to the control constant and looks like nothing happened).

  If you are that first skin: docs/controls/toolbar.md names office/macos/aero/ubuntu as the
  four whose dark fallback is thin and explains what they would each need. Relax this to a
  range check for the overriding theme; do not delete it. }
var
  c: TTyStyleController;
  names: TStringArray;
  i, m: Integer;
  mode: string;
begin
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  try
    names := TyBuiltinThemeNames;
    AssertTrue('there are built-in themes to check', Length(names) > 0);
    for i := 0 to High(names) do
      for m := 0 to 1 do
      begin
        if m = 0 then mode := 'light' else mode := 'dark';
        c.ThemeName := names[i];
        c.Mode := mode;
        AssertEquals(Format('%s/%s: %s must reach this theme through the base layer at the '
          + 'base value. Got something else: either the base declaration was lost (an '
          + 'unparseable value falls back SILENTLY to the control constant), or this skin is '
          + 'the first to retune the token deliberately — if the latter, see the comment '
          + 'above rather than deleting this line.',
          [names[i], mode, TyToolRuleAlphaVar]),
          TyToolRuleGhostAlpha, c.Metric(TyToolRuleAlphaVar, -12345));
      end;
  finally
    c.Free;
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
  // Regression guard: green is the image-background demo theme. It must resolve TyForm to an
  // image fill; its CONTAINERS are intentionally clean (no glass) so the sharp photo shows
  // through, while glass remains on the input controls (TyEdit etc.).
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
    AssertEquals('green MaxGlassBlur (glass still used by input controls)', 16, model.MaxGlassBlur);
    { Containers are CLEAN (no glass) so the sharp photo shows through; glass stays on inputs. }
    s := model.ResolveStyle('TyPanel', '', []);
    AssertFalse('green TyPanel is clean (no glass)', tpGlass in s.Present);
    s := model.ResolveStyle('TyEdit', '', []);
    AssertTrue('green TyEdit still has glass', tpGlass in s.Present);
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
    AssertFalse('switched TyPanel is clean (no glass)', tpGlass in s.Present);
    s := model.ResolveStyle('TyEdit', '', []);
    AssertTrue('switched TyEdit still has glass', tpGlass in s.Present);
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
  GGRID: array[0..204] of string = (
    'TyForm|', 'TyButton|', 'TyButton|primary', 'TyButton|danger', 'TyLabel|',
    'TyEdit|', 'TyCheckBox|', 'TyRadioButton|', 'TyPanel|', 'TyComboBox|',
    'TyScrollBar|', 'TyScrollThumb|', 'TyTitleBar|', 'TyCaptionButton|',
    'TyCaptionButton|close', 'TyCaptionButton|min', 'TyCaptionButton|max',
    'TyListBox|', 'TyListItem|', 'TyProgressBar|', 'TyProgressFill|',
    'TyGauge|', 'TyGaugeFill|', 'TyHint|', 'TyRibbon|', 'TyRibbonGroup|',
    'TyToggleSwitch|', 'TyToggleKnob|', 'TyTrackBar|', 'TyTrackGroove|', 'TyTrackThumb|', 'TyLinkLabelLink|',
    { the explicit-borrow population — see docs/superpowers/plans/2026-07-23-typekey-explicit-borrowers.md }
    'TyHtmlLabel|', 'TyLinkLabel|', 'TyShadowLabel|', 'TyGlowLabel|', 'TyDivider|', 'TyCharImage|', 'TyButtonGroup|', 'TyUpDown|', 'TyChart|', 'TyCalculator|', 'TyBevel|', 'TySizeBox|', 'TyControlBar|', 'TyCoolBar|', 'TyColorGrid|', 'TyShape|', 'TyStarShape|', 'TyArrow|', 'TyImageView|', 'TyImage|', 'TyPreviewBox|', 'TyListGroupPanel|', 'TyRibbonBackstage|', 'TyRibbonQuickAccess|', 'TyRibbonGallery|', 'TyTabSet|', 'TyHeaderControl|',
    'TyGroupBox|', 'TyTabControl|', 'TyPageControl|', 'TyTabSheet|',
    'TyTab|', 'TyTabClose|', 'TySpinEdit|',
    'TyMemo|', 'TyTextSelection|', 'TyTextHint|',
    'TyMenuBar|', 'TyMenuItem|', 'TyMenuPopup|', 'TyMenuView|',
    'TySplitter|', 'TyStatusBar|', 'TyToolBar|',
    'TyCalendar|', 'TyCalendarTitle|', 'TyCalendarWeekday|', 'TyCalendarCell|',
    'TyDateTimePicker|', 'TyDateTimeButton|',
    'TyTreeView|', 'TyTreeNode|',
    'TyTreeHeader|', 'TyTreeHeaderSection|',
    'TyTreeCheckBox|',
    { 下面这批一直在册外 —— GGRID 停在 TyTreeCheckBox,于是 AntD 那批控件、
      整个 Grid、Card/Popover/Steps 全都没有任何像素守卫。补齐到与
      light.tycss 的 typeKey 一一对应。 }
    'TyAlert|', 'TyAlertClose|', 'TyBadge|', 'TyBreadcrumb|',
    'TyBreadcrumbItem|', 'TyCard|', 'TyCardActions|', 'TyCardHeader|',
    'TyCascader|', 'TyCascaderItem|', 'TyCascaderPanel|', 'TyChartTooltip|',
    'TyChartSeries1|', 'TyChartSeries2|', 'TyChartSeries3|', 'TyChartSeries4|',
    'TyChartSeries5|', 'TyChartSeries6|', 'TyChartSeries7|', 'TyChartSeries8|',
    'TyEmpty|', 'TyEmptyImage|', 'TyGrid|', 'TyGridActiveCell|',
    'TyGridButton|', 'TyGridCell|', 'TyGridCellAlt|', 'TyGridCellMarked|',
    'TyGridCellSelectedInactive|', 'TyGridCheckBox|', 'TyGridCommentMark|', 'TyGridFilterRow|',
    'TyGridFixed|', 'TyGridHeader|', 'TyGridHeaderGroup|', 'TyGridHeaderSection|',
    'TyGridHyperlink|', 'TyGridIndicator|', 'TyGridLine|', 'TyGridProgress|',
    'TyGridProgressFill|', 'TyGridRating|', 'TyGridRatingEmpty|', 'TyGridSelection|',
    'TyGridSelectionFrame|', 'TyListGroupHeader|', 'TyListGroupItem|', 'TyNotification|',
    'TyNotificationClose|', 'TyPagination|', 'TyPaginationItem|', 'TyPopover|',
    'TyPopoverTitle|', 'TySegmented|', 'TySegmentedItem|', 'TySteps|',
    'TyStepsConnector|', 'TyStepsItem|', 'TyTag|', 'TyTagClose|',
    'TyTransfer|', 'TyTransferTitle|',
    { 3.0 themability pass. These keys all EXISTED in code and resolved someone else's
      rule (13 instruments hardcoded 'TyGauge'; the list view wore the tree's clothes;
      speed/ribbon buttons wore TyButton). Splitting them is a pure hook addition, so
      every line they add here must be byte-identical to the line their old key already
      dumps — that is exactly what this grid is here to prove.
      The six that dump EMPTY (TyListViewLine/Marquee, the four TyValueListEditor part
      keys) are guarded on purpose: their painters fall back to a state-dependent value,
      so "still undefined" is the assertion. }
    'TyMeter|', 'TyMeterTick|', 'TyMeterNeedle|',
    'TyLevelMeter|', 'TyLevelMeterFill|', 'TyLevelMeterPeak|',
    'TyDial|', 'TyDialPointer|',
    'TyGearDial|', 'TyGearDialTeeth|', 'TyGearDialPointer|',
    'TyAnalogClock|', 'TyAnalogClockHand|', 'TyAnalogClockSecondHand|',
    'TyCircularProgress|', 'TyCircularProgressFill|',
    'TyActivityIndicator|', 'TyActivityIndicatorFill|',
    'TyActivityBar|', 'TyActivityBarFill|',
    'TyGearActivityIndicator|', 'TyGearActivityIndicatorFill|',
    'TySparkline|', 'TySparklineFill|', 'TySparklineDot|',
    'TyRating|', 'TyRatingStar|',
    'TyLColorPicker|', 'TyHSColorPicker|', 'TyColorArea|',
    { TyScrollContent joined in the aero-dark residue pass. The key had no rule in ANY
      layer and no guard anywhere, so the scroll viewport painted nothing and showed the
      host's erase colour — a light well in a dark window. Its five rows here pin the
      resolved surface per theme; test.modecoherence additionally holds it OPAQUE in both
      modes across every built-in skin (an absent resolve is the defect, not a style). }
    'TyScrollBox|', 'TyScrollContent|', 'TyExPanel|', 'TyExPanelHeader|',
    'TyToolGroupPanel|', 'TyToolSeparator|',
    'TySpeedButton|', 'TyGlyphContainerButton|',
    'TyRibbonAppMenu|', 'TyRibbonAppMenu|primary',
    { NOT guarded here: the 'ghost' variant. Adding 'TySpeedButton|ghost' immediately red
      the auto-vs-light/dark equality tests, and the cause is NOT this refactor —
      light.tycss and dark.tycss give TyButton.ghost a rest background of
      alpha(var(--surface-hover), 0) while auto.tycss uses var(--transparent-fill)
      (alpha-0 white / alpha-0 black). Both are invisible at rest, but the RGB of an
      alpha-0 fill is load-bearing: TTyButton cross-fades rest -> hover, so the ramp
      differs. Aligning auto.tycss would MOVE PIXELS mid-fade, which this pass may not do.
      Fix that first, then guard the variant. }
    'TyListView|', 'TyListViewItem|', 'TyListViewHeader|',
    'TyListViewHeaderSection|', 'TyListViewGroupHeader|', 'TyListViewCheckBox|',
    'TyListViewLine|', 'TyListViewMarquee|',
    'TyValueListEditor|', 'TyValueListEditorRow|', 'TyValueListEditorKey|',
    'TyValueListEditorValue|', 'TyValueListEditorDivider|', 'TyValueListEditorExpander|',
    'TyGridGroupRow|', 'TyGridSummaryRow|');

  GMETRICS: array[0..110] of string = (
    '--alert-close-gap',
    '--alert-close-size',
    '--alert-icon-gap',
    '--alert-icon-size',
    '--alert-text-gap',
    '--backstage-back-height',
    '--backstage-icon-size',
    '--backstage-icon-x',
    '--backstage-row-height',
    '--backstage-sidebar-width',
    '--backstage-text-inset',
    '--badge-dot-size',
    '--badge-inset',
    '--breadcrumb-separator-gap',
    '--breadcrumb-separator-size',
    '--caption-button-width',
    '--card-actions-height',
    '--card-header-height',
    '--cascader-column-width',
    '--cascader-expand-gap',
    '--cascader-expand-size',
    '--cascader-row-height',
    '--chart-tooltip-gap',
    '--chart-tooltip-swatch',
    '--chart-tooltip-swatch-gap',
    '--checkbox-gap',
    '--checkbox-size',
    '--control-height',
    '--dialog-edit-width',
    '--dialog-padding',
    '--drop-arrow-width',
    '--empty-action-height',
    '--empty-gap',
    '--empty-image-size',
    '--expander-header-height',
    '--field-button-width',
    '--font-size-sm',
    '--gallery-arrow-width',
    '--gallery-cell-width',
    '--gallery-glyph-pad',
    '--gallery-grid-cell-height',
    '--glyph-button-gap',
    '--grid-comment-mark-size',
    '--header-control-height',
    '--header-height',
    '--header-section-width',
    '--icon-size',
    '--item-height',
    '--listgroup-chevron-size',
    '--listgroup-header-height',
    '--listgroup-icon-gap',
    '--listgroup-icon-size',
    '--listgroup-item-height',
    '--listgroup-item-indent',
    '--listgroup-item-inset',
    '--listview-cell-padding',
    '--listview-check-size',
    '--listview-group-header-height',
    '--listview-hgap',
    '--listview-icon-label-width',
    '--listview-label-height',
    '--listview-large-icon-size',
    '--listview-small-icon-size',
    '--listview-small-label-width',
    '--listview-text-margin',
    '--listview-tile-label-width',
    '--listview-vgap',
    '--menu-arrow-slot',
    '--menu-check-slot',
    '--menu-separator-height',
    '--menu-shortcut-gap',
    '--notification-close-size',
    '--notification-gap',
    '--notification-icon-size',
    '--notification-margin',
    '--notification-stack-gap',
    '--notification-width',
    '--pagination-gap',
    '--pagination-glyph-size',
    '--popover-arrow-size',
    '--popover-offset',
    '--popover-title-gap',
    '--qat-height',
    '--qat-width',
    '--ribbon-appmenu-height',
    '--ribbon-appmenu-width',
    '--ribbon-caption-band-height',
    '--row-height',
    '--scrollbar-size',
    '--segmented-pad',
    '--steps-connector-gap',
    '--steps-connector-length',
    '--steps-gap',
    '--steps-marker-size',
    '--tab-arrow-band',
    '--tab-close-size',
    '--tab-gap',
    '--tab-margin',
    '--tab-min-width',
    '--tab-padding',
    '--tag-close-size',
    '--tag-gap',
    '--titlebar-padding',
    '--transfer-arrow-margin',
    '--transfer-arrow-size',
    '--transfer-button-gap',
    '--transfer-button-height',
    '--transfer-button-width',
    '--transfer-rail-width',
    '--transfer-title-height',
    '--treeselect-drop-height');

function TTestThemeGolden.ThemePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim + AName;
  if not FileExists(Result) then      // structural skins (showcase, …) live in themes/builtin/
    Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'themes' + PathDelim
      + 'builtin' + PathDelim + AName;
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
    { 尺寸令牌(密度第三期):运行期几何原先在 golden 之外,令牌抄错或漏定义
      只会静默回退、无守卫。把每个令牌的解析值也 dump 进来,-1 = 未定义。 }
    for i := 0 to High(GMETRICS) do
      sl.Add('metric ' + GMETRICS[i] + ' => ' +
        IntToStr(model.ResolveMetric(GMETRICS[i], -1)));
    Result := sl.Text;
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
    { 尺寸令牌(密度第三期):运行期几何原先在 golden 之外,令牌抄错或漏定义
      只会静默回退、无守卫。把每个令牌的解析值也 dump 进来,-1 = 未定义。 }
    for i := 0 to High(GMETRICS) do
      sl.Add('metric ' + GMETRICS[i] + ' => ' +
        IntToStr(model.ResolveMetric(GMETRICS[i], -1)));
    Result := sl.Text;
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

type
  { One key that USED to be someone else's, plus the key it was taken from. }
  TTyAliasPair = record
    NewKey: string;
    Donor: string;
    BaseStateOnly: Boolean;   { the sub-part is resolved with an EMPTY state set, so it
                                deliberately joined only the donor's stateless rule }
    Variants: string;         { extra StyleClass values to check, comma separated }
  end;

const
  { Every shipped theme: themes/*.tycss plus all fifteen skins under themes/builtin/. }
  ALIAS_THEMES: array[0..19] of string = (
    'light', 'dark', 'auto', 'green', 'system',
    'adwaita', 'aero', 'antdesign', 'bootstrap', 'breeze', 'classic', 'fluent',
    'macos', 'material3', 'office', 'showcase', 'ubuntu', 'win10', 'win11', 'xp');

  ALIAS_PAIRS: array[0..71] of TTyAliasPair = (
    { The instrument family: thirteen controls that hardcoded 'TyGauge' + 'TyGaugeFill'. }
    (NewKey: 'TyMeter';                   Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyLevelMeter';              Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyDial';                    Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyGearDial';                Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyAnalogClock';             Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyCircularProgress';        Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyActivityIndicator';       Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyActivityBar';             Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyGearActivityIndicator';   Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TySparkline';               Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyRating';                  Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyLColorPicker';            Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyHSColorPicker';           Donor: 'TyGauge';     BaseStateOnly: False; Variants: ''),
    { Sub-parts that read the FACE, not the fill — stateless, hence base-state only. }
    (NewKey: 'TyMeterTick';               Donor: 'TyGauge';     BaseStateOnly: True;  Variants: ''),
    (NewKey: 'TyAnalogClockHand';         Donor: 'TyGauge';     BaseStateOnly: True;  Variants: ''),
    (NewKey: 'TyGearDialTeeth';           Donor: 'TyGauge';     BaseStateOnly: True;  Variants: ''),
    (NewKey: 'TyColorArea';               Donor: 'TyGauge';     BaseStateOnly: True;  Variants: ''),
    { Sub-parts that read the accent fill. }
    (NewKey: 'TyMeterNeedle';             Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyLevelMeterFill';          Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyLevelMeterPeak';          Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyDialPointer';             Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyGearDialPointer';         Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyAnalogClockSecondHand';   Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyCircularProgressFill';    Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyActivityIndicatorFill';   Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyActivityBarFill';         Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyGearActivityIndicatorFill'; Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TySparklineFill';           Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TySparklineDot';            Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyRatingStar';              Donor: 'TyGaugeFill'; BaseStateOnly: False; Variants: ''),
    { Containers + toolbar. }
    (NewKey: 'TyScrollBox';               Donor: 'TyPanel';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyExPanel';                 Donor: 'TyPanel';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyToolGroupPanel';          Donor: 'TyGroupBox';  BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyToolSeparator';           Donor: 'TyToolBar';   BaseStateOnly: False; Variants: ''),
    { Buttons. The variants matter: a toolbar stamps 'ghost' on its children and the
      ribbon's File tab ships with 'primary', so those are the DEFAULT renderings. }
    (NewKey: 'TySpeedButton';             Donor: 'TyButton';    BaseStateOnly: False; Variants: 'primary,danger,ghost'),
    (NewKey: 'TyGlyphContainerButton';    Donor: 'TyButton';    BaseStateOnly: False; Variants: 'primary,danger,ghost'),
    (NewKey: 'TyRibbonAppMenu';           Donor: 'TyButton';    BaseStateOnly: False; Variants: 'primary,danger,ghost'),
    { The list view, which wore the tree's clothes entirely. }
    (NewKey: 'TyListView';                Donor: 'TyTreeView';  BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyListViewItem';            Donor: 'TyTreeNode';  BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyListViewHeader';          Donor: 'TyTreeHeader'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyListViewGroupHeader';     Donor: 'TyTreeHeader'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyListViewHeaderSection';   Donor: 'TyTreeHeaderSection'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyListViewCheckBox';        Donor: 'TyTreeCheckBox'; BaseStateOnly: False; Variants: ''),
    { The property grid built on the list box. }
    (NewKey: 'TyValueListEditor';         Donor: 'TyListBox';   BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyValueListEditorRow';      Donor: 'TyListItem';  BaseStateOnly: False; Variants: ''),
    { The explicit-borrow population (d58eada): controls that DECLARED their own
      GetStyleTypeKey but returned a key naming a different control. }
    (NewKey: 'TyHtmlLabel';               Donor: 'TyLabel';      BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyLinkLabel';               Donor: 'TyLabel';      BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyShadowLabel';             Donor: 'TyLabel';      BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyGlowLabel';               Donor: 'TyLabel';      BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyDivider';                 Donor: 'TyLabel';      BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyCharImage';               Donor: 'TyLabel';      BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyButtonGroup';             Donor: 'TyButton';     BaseStateOnly: False; Variants: 'danger,ghost,primary'),
    (NewKey: 'TyUpDown';                  Donor: 'TyButton';     BaseStateOnly: False; Variants: 'danger,ghost,primary'),
    (NewKey: 'TyChart';                   Donor: 'TyPanel';      BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyCalculator';              Donor: 'TyPanel';      BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyBevel';                   Donor: 'TyPanel';      BaseStateOnly: False; Variants: ''),
    (NewKey: 'TySizeBox';                 Donor: 'TyPanel';      BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyControlBar';              Donor: 'TyPanel';      BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyCoolBar';                 Donor: 'TyPanel';      BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyColorGrid';               Donor: 'TyPanel';      BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyShape';                   Donor: 'TyPanel';      BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyStarShape';               Donor: 'TyPanel';      BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyArrow';                   Donor: 'TyPanel';      BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyImageView';               Donor: 'TyPanel';      BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyImage';                   Donor: 'TyPanel';      BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyPreviewBox';              Donor: 'TyPanel';      BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyListGroupPanel';          Donor: 'TyPanel';      BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyRibbonBackstage';         Donor: 'TyRibbon';     BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyRibbonQuickAccess';       Donor: 'TyTitleBar';   BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyRibbonGallery';           Donor: 'TyListBox';    BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyTabSet';                  Donor: 'TyTabControl'; BaseStateOnly: False; Variants: ''),
    (NewKey: 'TyHeaderControl';           Donor: 'TyTreeHeader'; BaseStateOnly: False; Variants: '')
  );

type
  { One DELIBERATE divergence: a (theme, key) pair TestNewKeysMatchTheirDonorInEveryTheme
    skips. The alias guard exists to stop borrowed typeKeys drifting from their donor BY
    ACCIDENT — a skin author touches a rule and silently forks a key nobody meant to fork.
    This table is the only sanctioned way to diverge ON PURPOSE: name the theme, name the
    key, and write down WHY. The reason is not decoration — an exemption with a blank
    reason fails TestAliasExemptionsAreDeliberate AND the sweep itself, because a
    reason-less exemption is indistinguishable from the accident the guard prevents. }
  TTyAliasExemption = record
    Theme: string;     { a name from ALIAS_THEMES }
    NewKey: string;    { a NewKey from ALIAS_PAIRS }
    Reason: string;    { REQUIRED: why this theme deliberately forks the key }
  end;

const
  ALIAS_EXEMPTIONS: array[0..1] of TTyAliasExemption = (
    (Theme: 'aero'; NewKey: 'TyCoolBar';
     Reason: 'Win7 rebar is command-band chrome: the cold --chrome-bar-bg band (per-mode), '
       + 'not TyPanel''s white content sheet around the cold toolbar bands it hosts'),
    (Theme: 'aero'; NewKey: 'TyControlBar';
     Reason: 'the second rebar host: same Win7 command-band chrome as TyCoolBar')
  );

{ -1 when (theme, key) is not exempted; otherwise the row index. }
function AliasExemptionIndex(const ATheme, ANewKey: string): Integer;
var i: Integer;
begin
  for i := 0 to High(ALIAS_EXEMPTIONS) do
    if (ALIAS_EXEMPTIONS[i].Theme = ATheme) and (ALIAS_EXEMPTIONS[i].NewKey = ANewKey) then
      Exit(i);
  Result := -1;
end;

{ Rendered into every alias-guard failure so the next deliberate divergence is a table row,
  not a weakened guard. }
function AliasExemptionTableText: string;
var i: Integer;
begin
  Result := 'The alias guard pins borrowed typeKeys to their donor so a theme cannot fork '
    + 'them BY ACCIDENT. If THIS divergence is deliberate, add a (Theme, NewKey, Reason) '
    + 'row to ALIAS_EXEMPTIONS in tests/test.themes.pas — the reason is mandatory. '
    + 'Current exemptions:';
  for i := 0 to High(ALIAS_EXEMPTIONS) do
    Result := Result + LineEnding + Format('  (%s, %s): %s',
      [ALIAS_EXEMPTIONS[i].Theme, ALIAS_EXEMPTIONS[i].NewKey, ALIAS_EXEMPTIONS[i].Reason]);
end;

procedure TTestThemeGolden.CheckAliasExemptionsWellFormed;
var
  i, j: Integer;
  known: Boolean;
begin
  for i := 0 to High(ALIAS_EXEMPTIONS) do
  begin
    if Trim(ALIAS_EXEMPTIONS[i].Reason) = '' then
      Fail(Format('ALIAS_EXEMPTIONS[%d] (%s, %s) has an EMPTY reason. An exemption without '
        + 'a reason is indistinguishable from the accident the alias guard exists to stop '
        + '— write down why this theme deliberately forks the key.',
        [i, ALIAS_EXEMPTIONS[i].Theme, ALIAS_EXEMPTIONS[i].NewKey]));
    known := False;
    for j := 0 to High(ALIAS_THEMES) do
      if ALIAS_THEMES[j] = ALIAS_EXEMPTIONS[i].Theme then known := True;
    if not known then
      Fail(Format('ALIAS_EXEMPTIONS[%d] names theme ''%s'', which is not in ALIAS_THEMES '
        + '— a stale exemption exempts nothing and misleads the reader.',
        [i, ALIAS_EXEMPTIONS[i].Theme]));
    known := False;
    for j := 0 to High(ALIAS_PAIRS) do
      if ALIAS_PAIRS[j].NewKey = ALIAS_EXEMPTIONS[i].NewKey then known := True;
    if not known then
      Fail(Format('ALIAS_EXEMPTIONS[%d] names key ''%s'', which is not in ALIAS_PAIRS '
        + '— a stale exemption exempts nothing and misleads the reader.',
        [i, ALIAS_EXEMPTIONS[i].NewKey]));
  end;
end;

procedure TTestThemeGolden.TestAliasExemptionsAreDeliberate;
begin
  CheckAliasExemptionsWellFormed;
end;

procedure TTestThemeGolden.CheckAlias(AModel: TTyStyleModel; const ATheme, ANew,
  ADonor, AVariant: string; ABaseStateOnly: Boolean);
const
  STATES: array[0..4] of TTyStateSet = ([], [tysHover], [tysActive], [tysFocused], [tysDisabled]);
var
  si, last: Integer;
  tag, donorDump, newDump: string;
begin
  if ABaseStateOnly then last := 0 else last := High(STATES);
  for si := 0 to last do
  begin
    tag := ATheme + ': ' + ANew;
    if AVariant <> '' then tag := tag + '.' + AVariant;
    tag := tag + ' state#' + IntToStr(si) + ' must resolve exactly like ' + ADonor;
    donorDump := GDumpStyle(AModel.ResolveStyle(ADonor, AVariant, STATES[si]));
    newDump := GDumpStyle(AModel.ResolveStyle(ANew, AVariant, STATES[si]));
    if donorDump <> newDump then
      Fail(tag + LineEnding
        + 'donor (' + ADonor + ') resolved: ' + donorDump + LineEnding
        + 'key (' + ANew + ') resolved: ' + newDump + LineEnding
        + AliasExemptionTableText);
  end;
end;

{ examples/theming/*.tycss — outside themes/, so ThemePath cannot reach them. }
function ExampleThemePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'examples' + PathDelim
    + 'theming' + PathDelim + AName + '.tycss';
end;

procedure TTestThemeGolden.TestExampleThemesCoverTheNewKeys;
const
  CExampleThemes: array[0..1] of string = ('custom', 'green');
var
  ti, pi: Integer;
  m: TTyStyleModel;
begin
  for ti := 0 to High(CExampleThemes) do
  begin
    m := TTyStyleModel.Create;
    try
      AssertTrue('example theme must exist: ' + CExampleThemes[ti],
        FileExists(ExampleThemePath(CExampleThemes[ti])));
      m.LoadFromFile(ExampleThemePath(CExampleThemes[ti]));
      m.Mode := 'light';
      for pi := 0 to High(ALIAS_PAIRS) do
        CheckAlias(m, 'examples/theming/' + CExampleThemes[ti], ALIAS_PAIRS[pi].NewKey,
          ALIAS_PAIRS[pi].Donor, '', ALIAS_PAIRS[pi].BaseStateOnly);
    finally
      m.Free;
    end;
  end;
end;

procedure TTestThemeGolden.TestNewKeysMatchTheirDonorInEveryTheme;
var
  ti, pi: Integer;
  m: TTyStyleModel;
  variants: TStringList;
  vi: Integer;
begin
  { Validate the table BEFORE honouring it: a malformed row (blank reason, stale name)
    must never buy its exemption. }
  CheckAliasExemptionsWellFormed;
  for ti := 0 to High(ALIAS_THEMES) do
  begin
    m := TTyStyleModel.Create;
    variants := TStringList.Create;
    try
      AssertTrue('theme file must exist: ' + ALIAS_THEMES[ti],
        FileExists(ThemePath(ALIAS_THEMES[ti] + '.tycss')));
      m.LoadFromFile(ThemePath(ALIAS_THEMES[ti] + '.tycss'));
      m.Mode := 'light';   // dual-mode files need an active mode; no-op for single-mode
      for pi := 0 to High(ALIAS_PAIRS) do
      begin
        if AliasExemptionIndex(ALIAS_THEMES[ti], ALIAS_PAIRS[pi].NewKey) >= 0 then
          Continue;   { deliberately diverged; the reason lives in ALIAS_EXEMPTIONS }
        CheckAlias(m, ALIAS_THEMES[ti], ALIAS_PAIRS[pi].NewKey,
          ALIAS_PAIRS[pi].Donor, '', ALIAS_PAIRS[pi].BaseStateOnly);
        if ALIAS_PAIRS[pi].Variants = '' then Continue;
        variants.Clear;
        variants.Delimiter := ',';
        variants.StrictDelimiter := True;
        variants.DelimitedText := ALIAS_PAIRS[pi].Variants;
        for vi := 0 to variants.Count - 1 do
          CheckAlias(m, ALIAS_THEMES[ti], ALIAS_PAIRS[pi].NewKey,
            ALIAS_PAIRS[pi].Donor, variants[vi], ALIAS_PAIRS[pi].BaseStateOnly);
      end;
    finally
      variants.Free;
      m.Free;
    end;
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
