unit test.controller.styleoverride;
{$mode objfpc}{$H+}

{ TTyStyleController.StyleOverride -- a tycss patch composed on top of the active theme, the
  "tweak the system theme a little without authoring a whole theme" door. These tests pin the two
  things that make it more than a one-shot additive load: it PERSISTS across theme switches and
  density changes (re-applied whenever layer-1 reloads), and doing so does NOT drop the runtime
  accent (a REPLACE load clears the accent override -- SetDensity used to lose it; the reload path
  now saves and restores it). }

interface

uses
  Classes, SysUtils, fpcunit, testregistry;

type
  TControllerStyleOverrideTest = class(TTestCase)
  published
    procedure OverridePatchesTheResolvedStyle;
    procedure OverrideWinsOverAnExplicitlyLoadedTheme;
    procedure OverrideSurvivesADensityChange;
    procedure ClearingTheOverrideRestoresTheBase;
    { The three below name a theme that is NOT registered -- the state SetThemeName explicitly
      allows (it retries when the name appears). ReloadThemeLayer had a branch that loaded
      nothing for exactly that state, so layer-1 was never rebuilt and every patch stacked. The
      clearing test above never saw it because its controller names no theme. }
    procedure ClearingTheOverrideWorksUnderAnUnregisteredThemeName;
    procedure AReplacedOverrideDoesNotStackUnderAnUnregisteredThemeName;
    procedure DensityRoundTripDropsThePackUnderAnUnregisteredThemeName;
    { The OTHER branch that could load nothing: a ThemeFile that has gone away
      while the program runs, which is what an author gets the moment they
      rename the .tycss they are working on. }
    procedure ClearingItWorksEvenIfTheThemeFileWentAway;
    procedure AccentSurvivesADensityChange;
    procedure AccentSurvivesAnOverrideChange;
    procedure TheDefaultControllerTakesItInCode;
    { #106: an additive rule on a key the theme leaves to the built-in base layer. }
    procedure APaddingPatchKeepsTheCascadersLook;
    procedure ABorderPatchLeavesHoverAndFocusAboveIt;
    procedure AnOverrideKeepsTheButtonOnTheBareController;
    procedure EveryBuiltinThemeKeepsEveryKeyUnderAPaddingPatch;
    procedure EveryClassAndStateKeepsItsLookUnderAPaddingPatch;
    procedure AThemesOwnStateRuleStaysAboveTheCopiedBase;
    procedure APatchOnAThemedKeyBringsNoBaseBack;
  end;

implementation

uses
  tyControls.Types, tyControls.StyleModel, tyControls.Controller, tyControls.BuiltinThemes,
  tyControls.DefaultTheme, tyControls.Css.Parser;

{ The resolved border-width of TyButton -- a clean integer to watch an override land on. 7px is a
  distinctive value the base theme does not use. }
function ButtonBorderWidth(AController: TTyStyleController): Integer;
begin
  Result := AController.Model.ResolveStyle('TyButton', '', []).BorderWidth;
end;

procedure TControllerStyleOverrideTest.OverridePatchesTheResolvedStyle;
var c: TTyStyleController;
begin
  c := TTyStyleController.Create(nil);
  try
    AssertTrue('base TyButton is not already 7px (would void the test)', ButtonBorderWidth(c) <> 7);
    c.StyleOverride := 'TyButton { border-width: 7px; }';
    AssertEquals('the override patched the resolved style', 7, ButtonBorderWidth(c));
  finally
    c.Free;
  end;
end;

procedure TControllerStyleOverrideTest.OverrideWinsOverAnExplicitlyLoadedTheme;
var c: TTyStyleController;
begin
  { A REPLACE theme load clears the user layer; the override must re-compose on top and win. }
  c := TTyStyleController.Create(nil);
  try
    c.StyleOverride := 'TyButton { border-width: 7px; }';
    c.LoadThemeCss('TyButton { border-width: 3px; }');   // a "theme" that disagrees
    AssertEquals('the override still wins after a theme load', 7, ButtonBorderWidth(c));
  finally
    c.Free;
  end;
end;

procedure TControllerStyleOverrideTest.OverrideSurvivesADensityChange;
var c: TTyStyleController;
begin
  c := TTyStyleController.Create(nil);
  try
    c.StyleOverride := 'TyButton { border-width: 7px; }';
    c.Density := tdModern;   // reloads layer-1 + density pack; the override must re-apply on top
    AssertEquals('the override survived a density change', 7, ButtonBorderWidth(c));
  finally
    c.Free;
  end;
end;

procedure TControllerStyleOverrideTest.ClearingTheOverrideWorksUnderAnUnregisteredThemeName;
var c: TTyStyleController; base: Integer;
begin
  c := TTyStyleController.Create(nil);
  try
    c.ThemeName := 'ty-test-theme-that-is-not-registered';   { silent: allowed to fail and retry }
    base := ButtonBorderWidth(c);
    c.StyleOverride := 'TyButton { border-width: 7px; }';
    AssertEquals('override applied', 7, ButtonBorderWidth(c));
    c.StyleOverride := '';
    AssertEquals('clearing restored the base even though the name never resolved',
      base, ButtonBorderWidth(c));
  finally
    c.Free;
  end;
end;

procedure TControllerStyleOverrideTest.AReplacedOverrideDoesNotStackUnderAnUnregisteredThemeName;
var c: TTyStyleController; base: Integer;
begin
  c := TTyStyleController.Create(nil);
  try
    c.ThemeName := 'ty-test-theme-that-is-not-registered';
    base := ButtonBorderWidth(c);
    c.StyleOverride := 'TyButton { border-width: 7px; }';
    AssertEquals('first override applied', 7, ButtonBorderWidth(c));
    { A second patch that says nothing about border-width must REPLACE the first, not sit on
      top of it: with layer-1 never rebuilt, the 7px rule stayed in FRules underneath. A
      padding-only patch leaves the base's border-width alone, so it is back to the base (#106:
      it used to read 0, the patch having dropped the built-in TyButton rules). }
    c.StyleOverride := 'TyButton { padding: 3px; }';
    AssertTrue('sanity: the base itself is not 7', base <> 7);
    AssertEquals('the earlier border-width (7) did not survive the replacement',
      base, ButtonBorderWidth(c));
  finally
    c.Free;
  end;
end;

procedure TControllerStyleOverrideTest.DensityRoundTripDropsThePackUnderAnUnregisteredThemeName;
var c: TTyStyleController; classicH, modernH: Integer;
begin
  c := TTyStyleController.Create(nil);
  try
    c.ThemeName := 'ty-test-theme-that-is-not-registered';
    classicH := c.Metric('--control-height', 0);
    c.Density := tdModern;
    modernH := c.Metric('--control-height', 0);
    AssertTrue('precondition: modern really changes the token ('
      + IntToStr(classicH) + ' -> ' + IntToStr(modernH) + ')', modernH <> classicH);
    { Back to classic goes through the same reload; the additive modern pack can only be dropped
      by rebuilding layer-1, which the no-load branch skipped. }
    c.Density := tdClassic;
    AssertEquals('the modern pack is gone again', classicH, c.Metric('--control-height', 0));
  finally
    c.Free;
  end;
end;

procedure TControllerStyleOverrideTest.ClearingTheOverrideRestoresTheBase;
var c: TTyStyleController; base: Integer;
begin
  c := TTyStyleController.Create(nil);
  try
    base := ButtonBorderWidth(c);
    c.StyleOverride := 'TyButton { border-width: 7px; }';
    AssertEquals('override applied', 7, ButtonBorderWidth(c));
    c.StyleOverride := '';   // an additive layer cannot be unloaded -> the chain is rebuilt clean
    AssertEquals('clearing the override restored the base', base, ButtonBorderWidth(c));
  finally
    c.Free;
  end;
end;

procedure TControllerStyleOverrideTest.ClearingItWorksEvenIfTheThemeFileWentAway;
var
  c: TTyStyleController;
  base: Integer;
  path: string;
begin
  { THE OTHER BRANCH THAT COULD LOAD NOTHING. A ThemeFile that has been moved,
    renamed or deleted while the program runs is the file-shaped version of a
    theme name that does not resolve, and it used to fail the same way: nothing
    was loaded, so nothing was cleared, so the override was stuck.

    A deleted theme file is not an exotic state -- it is what an author gets
    the moment they rename the .tycss they are working on. }
  path := GetTempFileName('', 'tycss');
  c := TTyStyleController.Create(nil);
  try
    with TStringList.Create do
    try
      Text := 'TyButton { border-width: 2px; }';
      SaveToFile(path);
    finally
      Free;
    end;
    c.ThemeFile := path;
    base := ButtonBorderWidth(c);
    AssertEquals('the file was loaded to begin with', 2, base);

    c.StyleOverride := 'TyButton { border-width: 7px; }';
    AssertEquals('override applied', 7, ButtonBorderWidth(c));

    DeleteFile(path);
    c.StyleOverride := '';
    { The file is gone, so the base it falls back to is the built-in one rather
      than the 2px the file used to say. What matters is that the 7px patch is
      GONE: a stuck override is unrecoverable, a fallback is not. }
    AssertTrue('the patch did not survive the file going away',
      ButtonBorderWidth(c) <> 7);
  finally
    c.Free;
    DeleteFile(path);
  end;
end;

procedure TControllerStyleOverrideTest.AccentSurvivesADensityChange;
var c: TTyStyleController;
begin
  { The bug this feature exposed: SetDensity -> ReloadThemeLayer -> REPLACE load cleared the
    accent override. The reload now saves/restores it. }
  c := TTyStyleController.Create(nil);
  try
    c.SetAccent('#123456');
    AssertEquals('accent is set', '#123456', c.AccentOverride);
    c.Density := tdModern;
    AssertEquals('accent survived the density change', '#123456', c.AccentOverride);
  finally
    c.Free;
  end;
end;

procedure TControllerStyleOverrideTest.AccentSurvivesAnOverrideChange;
var c: TTyStyleController;
begin
  c := TTyStyleController.Create(nil);
  try
    c.SetAccent('#123456');
    c.StyleOverride := 'TyButton { border-width: 7px; }';   // rebuilds the chain
    AssertEquals('accent survived setting an override', '#123456', c.AccentOverride);
  finally
    c.Free;
  end;
end;

procedure TControllerStyleOverrideTest.TheDefaultControllerTakesItInCode;
var saved: string;
begin
  { The default controller has no editor popup -- it is set in code. Same effect. }
  saved := TyDefaultController.StyleOverride;
  try
    TyDefaultController.StyleOverride := 'TyButton { border-width: 7px; }';
    AssertEquals('default controller applied the override', 7,
      ButtonBorderWidth(TyDefaultController));
  finally
    TyDefaultController.StyleOverride := saved;   { leave the shared singleton as we found it }
  end;
end;

{ ===== #106: an additive rule on a key the theme leaves to the base layer =====
  'default' is themes/auto.tycss. It dresses TyEdit itself but has no TyCascader rule, so the
  cascader is drawn by the built-in base layer (themes/light.tycss). A patch went into the user
  layer, and a plain rule there counted as the theme taking the key over: the base rules for it
  were dropped and the cascader lost everything the patch did not say. The same one-property
  patch has to behave the same way on both keys. }

{ Everything a resolved style carries except AProp, which the patch under test is allowed to move. }
function LookWithout(const S: TTyStyleSet; AProp: TTyProp): string;
var p: TTyProp;
begin
  Result := 'P[';
  for p := Low(TTyProp) to High(TTyProp) do
    if (p <> AProp) and (p in S.Present) then Result := Result + IntToStr(Ord(p)) + ',';
  Result := Result + '] bg=' + IntToStr(Ord(S.Background.Kind));
  case S.Background.Kind of
    tfkSolid: Result := Result + ':' + IntToHex(S.Background.Color, 8);
    tfkLinearGradient: Result := Result + ':' + IntToHex(S.Background.GradFrom, 8) + '>'
      + IntToHex(S.Background.GradTo, 8);
    tfkImage, tfkNineSlice: Result := Result + ':' + S.Background.ImagePath;
  end;
  Result := Result + ' fg=' + IntToHex(S.TextColor, 8);
  if AProp <> tpBorderColor then Result := Result + ' bc=' + IntToHex(S.BorderColor, 8);
  if AProp <> tpBorderWidth then Result := Result + ' bw=' + IntToStr(S.BorderWidth);
  if AProp <> tpPadding then
    Result := Result + ' pad=' + IntToStr(S.Padding.Left) + ',' + IntToStr(S.Padding.Top) + ','
      + IntToStr(S.Padding.Right) + ',' + IntToStr(S.Padding.Bottom);
  Result := Result + ' bs=' + IntToStr(Ord(S.BorderStyle)) + ' rs=' + IntToStr(Ord(S.RenderStyle))
    + ' r=' + IntToStr(S.BorderRadius) + ' f=' + S.FontName + '/' + IntToStr(S.FontSize) + '/'
    + IntToStr(S.FontWeight) + ' op=' + IntToStr(Round(S.Opacity * 1000))
    + ' sh=' + IntToHex(S.ShadowColor, 8) + '/' + IntToStr(S.ShadowBlur)
    + ' ol=' + IntToHex(S.OutlineColor, 8) + '/' + IntToStr(S.OutlineWidth);
end;

{ Every typeKey the built-in base layer has a rule for, sorted and unique. }
function BaseKeys: TStringList;
var parser: TTyCssParser; sheet: TTyCssStylesheet; i, j: Integer;
begin
  Result := TStringList.Create;
  Result.Sorted := True;
  Result.Duplicates := dupIgnore;
  parser := TTyCssParser.Create(tyControls.DefaultTheme.TyBuiltinThemeCss);
  try
    sheet := parser.Parse;
    try
      for i := 0 to sheet.Rules.Count - 1 do
        for j := 0 to High(TTyCssRule(sheet.Rules[i]).Selectors) do
          Result.Add(TTyCssRule(sheet.Rules[i]).Selectors[j].TypeName);
    finally
      sheet.Free;
    end;
  finally
    parser.Free;
  end;
end;

{ One padding-only rule for every key in AKeys. }
function PaddingPatch(AKeys: TStrings): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to AKeys.Count - 1 do
    Result := Result + AKeys[i] + ' { padding: 6px 13px; }' + LineEnding;
end;

procedure TControllerStyleOverrideTest.APaddingPatchKeepsTheCascadersLook;
var c: TTyStyleController; s0, s1: TTyStyleSet; k: Integer;
const Keys: array[0..1] of string = ('TyEdit', 'TyCascader');
begin
  TyRegisterBuiltinThemes;
  for k := 0 to High(Keys) do
  begin
    c := TTyStyleController.Create(nil);
    try
      c.ThemeName := 'default';
      c.Mode := 'light';
      s0 := c.Model.ResolveStyle(Keys[k], '', []);
      AssertTrue(Keys[k] + ': precondition, it has a fill', tpBackground in s0.Present);
      AssertTrue(Keys[k] + ': precondition, the patch moves the padding', s0.Padding.Left <> 13);
      c.LoadThemeCssAdditive(Keys[k] + ' { padding: 6px 13px; }');
      s1 := c.Model.ResolveStyle(Keys[k], '', []);
      AssertEquals(Keys[k] + ': the padding landed', 13, s1.Padding.Left);
      AssertEquals(Keys[k] + ': everything but the padding is unchanged',
        LookWithout(s0, tpPadding), LookWithout(s1, tpPadding));
    finally
      c.Free;
    end;
  end;
end;

procedure TControllerStyleOverrideTest.ABorderPatchLeavesHoverAndFocusAboveIt;
{ The patch is a plain rule, so the base's :hover and :focus rules still apply over it, as the
  theme's own do over the same patch on TyEdit. Copying the base rules ABOVE the patch would lose
  the patch; letting the patch sit above every base rule would paint the focused field red. }
var c: TTyStyleController; h0, f0, h1, f1: TTyStyleSet; k: Integer;
const Keys: array[0..1] of string = ('TyEdit', 'TyCascader');
begin
  TyRegisterBuiltinThemes;
  for k := 0 to High(Keys) do
  begin
    c := TTyStyleController.Create(nil);
    try
      c.ThemeName := 'default';
      c.Mode := 'light';
      h0 := c.Model.ResolveStyle(Keys[k], '', [tysHover]);
      f0 := c.Model.ResolveStyle(Keys[k], '', [tysFocused]);
      AssertTrue(Keys[k] + ': precondition, the focused border is not the patch colour',
        f0.BorderColor <> TTyColor($FFFF0000));
      c.LoadThemeCssAdditive(Keys[k] + ' { border-color: #FF0000; }');
      AssertEquals(Keys[k] + ': the resting border is the patch', IntToHex($FFFF0000, 8),
        IntToHex(c.Model.ResolveStyle(Keys[k], '', []).BorderColor, 8));
      h1 := c.Model.ResolveStyle(Keys[k], '', [tysHover]);
      f1 := c.Model.ResolveStyle(Keys[k], '', [tysFocused]);
      AssertEquals(Keys[k] + ': the hovered look is unchanged', LookWithout(h0, tpPadding),
        LookWithout(h1, tpPadding));
      AssertEquals(Keys[k] + ': the focused look is unchanged', LookWithout(f0, tpPadding),
        LookWithout(f1, tpPadding));
    finally
      c.Free;
    end;
  end;
end;

procedure TControllerStyleOverrideTest.AnOverrideKeepsTheButtonOnTheBareController;
{ A controller that names no theme sits on the base layer for EVERY key, and StyleOverride is the
  same additive load. OverridePatchesTheResolvedStyle only looks at the border width, so it stayed
  green while the button lost its fill and its ink. }
var c: TTyStyleController; s0, s1: TTyStyleSet;
begin
  c := TTyStyleController.Create(nil);
  try
    s0 := c.Model.ResolveStyle('TyButton', '', []);
    AssertTrue('precondition: the button has a fill and ink',
      (tpBackground in s0.Present) and (tpTextColor in s0.Present));
    c.StyleOverride := 'TyButton { border-width: 7px; }';
    s1 := c.Model.ResolveStyle('TyButton', '', []);
    AssertEquals('the override landed', 7, s1.BorderWidth);
    AssertEquals('everything but the border width is unchanged',
      LookWithout(s0, tpBorderWidth), LookWithout(s1, tpBorderWidth));
  finally
    c.Free;
  end;
end;

procedure TControllerStyleOverrideTest.EveryBuiltinThemeKeepsEveryKeyUnderAPaddingPatch;
{ The whole matrix at rest: every built-in theme in both modes and the bare base, every key the
  base layer styles. A padding-only patch may move the padding and nothing else. The model is
  reused across themes -- each LoadFromCss is a REPLACE, the path ThemeName takes. }
var
  m: TTyStyleModel;
  keys, bad: TStringList;
  names: TStringArray;
  before: array of string;
  css, nm: string;
  i, n, md, moved: Integer;
const Modes: array[0..1] of string = ('light', 'dark');
begin
  keys := BaseKeys;
  bad := TStringList.Create;
  m := TTyStyleModel.Create;
  try
    AssertTrue('precondition: the base layer has its keys', keys.Count > 150);
    css := PaddingPatch(keys);
    names := TyBuiltinThemeNames;
    SetLength(before, keys.Count);
    for n := -1 to High(names) do
      for md := 0 to High(Modes) do
      begin
        if (n < 0) and (md > 0) then Continue;
        if n < 0 then
        begin
          m.LoadFromCss('');
          nm := '(no theme)';
        end
        else
        begin
          m.LoadFromCss(tyControls.BuiltinThemes.TyBuiltinThemeCss(names[n]));
          m.SetMode(Modes[md]);
          nm := names[n] + '/' + Modes[md];
        end;
        for i := 0 to keys.Count - 1 do
          before[i] := LookWithout(m.ResolveStyle(keys[i], '', []), tpPadding);
        m.LoadFromCssAdditive(css);
        moved := 0;
        for i := 0 to keys.Count - 1 do
          if LookWithout(m.ResolveStyle(keys[i], '', []), tpPadding) <> before[i] then
          begin
            Inc(moved);
            if moved <= 3 then nm := nm + ' ' + keys[i];
          end;
        if moved > 0 then bad.Add(nm + ' (' + IntToStr(moved) + ' keys)');
      end;
    AssertEquals('themes where a padding patch erased a key:' + LineEnding + bad.Text, 0, bad.Count);
  finally
    m.Free;
    bad.Free;
    keys.Free;
  end;
end;

procedure TControllerStyleOverrideTest.EveryClassAndStateKeepsItsLookUnderAPaddingPatch;
{ The same patch on 'default' and the bare base, across every class the key defines and every
  state. A fix that brought back only the plain base rule would pass the matrix above and lose the
  hover, focus and variant looks here. }
var
  m: TTyStyleModel;
  keys, classes, bad: TStringList;
  before: TStringList;
  css, tag: string;
  i, t, ci, si, idx, moved: Integer;
const
  Themes: array[0..1] of string = ('', 'default');
  States: array[0..5] of TTyStateSet = ([], [tysHover], [tysFocused], [tysActive], [tysDisabled],
    [tysSelected]);
begin
  keys := BaseKeys;
  classes := TStringList.Create;
  before := TStringList.Create;
  bad := TStringList.Create;
  m := TTyStyleModel.Create;
  try
    css := PaddingPatch(keys);
    moved := 0;
    for t := 0 to High(Themes) do
    begin
      if Themes[t] = '' then
        m.LoadFromCss('')
      else
      begin
        m.LoadFromCss(tyControls.BuiltinThemes.TyBuiltinThemeCss(Themes[t]));
        m.SetMode('light');
      end;
      before.Clear;
      for i := 0 to keys.Count - 1 do
      begin
        classes.Clear;
        classes.Add('');
        m.GetVariantsForType(keys[i], classes);
        for ci := 0 to classes.Count - 1 do
          for si := 0 to High(States) do
            before.Add(keys[i] + '.' + classes[ci] + ':' + IntToStr(si) + '='
              + LookWithout(m.ResolveStyle(keys[i], classes[ci], States[si]), tpPadding));
      end;
      AssertTrue('precondition: some keys define classes', before.Count > keys.Count * 6);
      m.LoadFromCssAdditive(css);
      idx := 0;
      for i := 0 to keys.Count - 1 do
      begin
        classes.Clear;
        classes.Add('');
        m.GetVariantsForType(keys[i], classes);
        for ci := 0 to classes.Count - 1 do
          for si := 0 to High(States) do
          begin
            tag := keys[i] + '.' + classes[ci] + ':' + IntToStr(si) + '='
              + LookWithout(m.ResolveStyle(keys[i], classes[ci], States[si]), tpPadding);
            if before[idx] <> tag then
            begin
              Inc(moved);
              if moved <= 3 then
                bad.Add('[' + Themes[t] + '] ' + before[idx] + LineEnding + '    now ' + tag);
            end;
            Inc(idx);
          end;
      end;
    end;
    AssertEquals('looks a padding patch moved, the first three:' + LineEnding + bad.Text, 0, moved);
  finally
    m.Free;
    bad.Free;
    before.Free;
    classes.Free;
    keys.Free;
  end;
end;

procedure TControllerStyleOverrideTest.AThemesOwnStateRuleStaysAboveTheCopiedBase;
{ A theme that only tweaks the cascader's hover leaves the key to the base layer and lays its
  :hover over the base's. The base rules a patch brings in go BELOW the theme's own rules, so the
  theme's hover still wins; appended after them, the base's :hover would take it back. }
var c: TTyStyleController; h0, h1: TTyStyleSet;
begin
  c := TTyStyleController.Create(nil);
  try
    c.LoadThemeCss('TyCascader:hover { border-color: #123456; }');
    h0 := c.Model.ResolveStyle('TyCascader', '', [tysHover]);
    AssertEquals('precondition: the theme''s hover is on top', IntToHex($FF123456, 8),
      IntToHex(h0.BorderColor, 8));
    AssertTrue('precondition: the base dresses the rest', tpBackground in h0.Present);
    c.LoadThemeCssAdditive('TyCascader { padding: 6px 13px; }');
    h1 := c.Model.ResolveStyle('TyCascader', '', [tysHover]);
    AssertEquals('the hovered look is unchanged', LookWithout(h0, tpPadding),
      LookWithout(h1, tpPadding));
  finally
    c.Free;
  end;
end;

procedure TControllerStyleOverrideTest.APatchOnAThemedKeyBringsNoBaseBack;
{ The other side: a key the theme does dress stays the theme's alone. A patch on it must not bring
  the base rules in, or every property the theme left out would come back from the base. }
var c: TTyStyleController; s0, s1: TTyStyleSet;
begin
  c := TTyStyleController.Create(nil);
  try
    c.LoadThemeCss('TyButton { background: #123456; }');
    s0 := c.Model.ResolveStyle('TyButton', '', []);
    AssertFalse('precondition: the theme owns the key, no base border', tpBorderWidth in s0.Present);
    c.LoadThemeCssAdditive('TyButton { padding: 6px 13px; }');
    s1 := c.Model.ResolveStyle('TyButton', '', []);
    AssertEquals('the padding landed', 13, s1.Padding.Left);
    AssertEquals('everything but the padding is unchanged', LookWithout(s0, tpPadding),
      LookWithout(s1, tpPadding));
  finally
    c.Free;
  end;
end;

initialization
  RegisterTest(TControllerStyleOverrideTest);

end.
