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
    procedure TestEveryBuiltinCarriesTheEmbeddedEditVariant;
    procedure TestDraculaPalette;
    procedure TestNordPalette;
  end;

  TControllerThemeNameTest = class(TTestCase)
  published
    procedure TestThemeNameLoadsBuiltinCss;
    procedure TestModePersistsAcrossThemeSwitch;
    procedure TestLightSkinChromeBarsAreFlush;
    procedure TestChromeKeysKeepTheirBaseProperties;
    procedure TestTrackBarShowValueHasVisibleInk;
    procedure TestOnTitleBarInkReadsOnTheBar;
    procedure TestAntDesignGhostIsAFlatTextButton;
    procedure TestAeroTabRampIsOneColdFamilyInBothModes;
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

procedure TBuiltinThemesTest.TestEveryBuiltinCarriesTheEmbeddedEditVariant;
{ A VARIANT does not survive a skin's base rule. Writing ANY TyEdit rule suppresses the whole
  built-in rule set for that typeKey -- variants included -- so TyEdit.embedded, defined once in
  light.tycss, reached exactly ONE of the seventeen built-in themes (classic, and only because
  its plain TyEdit happens to have border-width 0 anyway). The editable combo box went on drawing
  its second frame under every other theme, and the headless suite was perfectly green, because
  nothing resolved the variant.

  So this asserts the property that actually matters: under EVERY built-in theme, an embedded
  edit has no frame. It is also the guard for the next skin someone adds -- copy a skin, forget
  these three lines, and this goes red instead of the defect coming back six months later. }
var
  n: TStringArray;
  i, md: Integer;
  m: TTyStyleModel;
  base, emb: TTyStyleSet;
  bad: string;
begin
  n := TyBuiltinThemeNames;
  bad := '';
  for i := 0 to High(n) do
  begin
    m := TTyStyleModel.Create;
    try
      m.LoadFromCss(TyBuiltinThemeCss(n[i]));
      { A dual-mode theme leaves its @mode-only vars undefined until a mode is seeded, and
        resolving without one RAISES rather than returning a default -- see the sibling
        TestAllBuiltinsDrawGapControls, which walks both modes for the same reason. }
      for md := 0 to 1 do
      begin
        if md = 0 then m.SetMode('light') else m.SetMode('dark');
        base := m.ResolveStyle('TyEdit', '', []);
        emb  := m.ResolveStyle('TyEdit', 'embedded', []);
        if emb.BorderWidth <> 0 then
          bad := bad + LineEnding + '  ' + n[i] + ' (' + BoolToStr(md = 0, 'light', 'dark') +
                 '): TyEdit.embedded border-width = ' + IntToStr(emb.BorderWidth) +
                 ' (plain TyEdit is ' + IntToStr(base.BorderWidth) + ')';
      end;
    finally m.Free; end;
  end;
  AssertEquals('themes whose embedded edit still draws a frame, so an editable combo box shows' +
    ' two:' + bad, '', bad);
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

procedure TControllerThemeNameTest.TestOnTitleBarInkReadsOnTheBar;
{ A title bar is a CONTAINER, and several skins paint it in a strong colour -- xp and classic
  a blue gradient, office the accent, showcase an accent gradient. A control dropped on one
  used to resolve the ordinary surface-tuned ink, and its caption then sat nearly invisible
  there, while the bar's own caption stayed readable because TyTitleBar carries its own
  contrasting ink that a child had no way to reach.

  TyStyleClassFor now appends an 'on-titlebar' variant to any control hosted on a bar, and
  every theme answers it. The contract is CONTRAST, not equality: a skin may legitimately
  give its caption a different ink from a button's (antdesign's bar ink is pure black at 88%
  alpha where its surface ink is #1F2937), so what has to hold is that the ink a control gets
  ON the bar is readable ON the bar. }
var
  c: TTyStyleController;
  names: TStringArray;
  bar, onbar: TTyStyleSet;
  i, m: Integer;
  mode: string;

  function Luma(AColor: TTyColor): Double;
  begin   // Rec. 601, 0..255
    Result := 0.299 * TyRedOf(AColor) + 0.587 * TyGreenOf(AColor)
            + 0.114 * TyBlueOf(AColor);
  end;

  { A gradient bar leaves Fill.Color unset, so the caption sits on the gradient itself. Judge
    against the MEAN of its ends: the text spans the whole band, so neither end alone is what
    it reads against, and taking the worst end alone fails skins whose gradient merely
    brightens at one edge -- classic runs from the accent up to a pale tint and its white
    caption is perfectly readable. }
  function BarLuma(const AFill: TTyFill): Double;
  begin
    if AFill.Kind = tfkLinearGradient then
      Result := (Luma(AFill.GradFrom) + Luma(AFill.GradTo)) / 2
    else
      Result := Luma(AFill.Color);
  end;

begin
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  c := TTyStyleController.Create(nil);
  try
    for i := 0 to High(names) do
      for m := 0 to 1 do
      begin
        if m = 0 then mode := 'light' else mode := 'dark';
        c.ThemeName := names[i];
        c.Mode := mode;
        bar := c.Model.ResolveStyle('TyTitleBar', '', []);
        onbar := c.Model.ResolveStyle('TyButton', 'on-titlebar', []);
        AssertTrue(Format('%s/%s: a button on the title bar has an ink', [names[i], mode]),
          tpTextColor in onbar.Present);
        AssertTrue(Format('%s/%s: that ink is not fully transparent', [names[i], mode]),
          TyAlphaOf(onbar.TextColor) > 0);
        AssertTrue(Format('%s/%s: the title bar has a background to judge against',
          [names[i], mode]), tpBackground in bar.Present);
        AssertTrue(Format('%s/%s: the on-titlebar ink reads on the bar (ink luma %.0f, '
          + 'bar luma %.0f)', [names[i], mode, Luma(onbar.TextColor),
          BarLuma(bar.Background)]),
          Abs(Luma(onbar.TextColor) - BarLuma(bar.Background)) >= 60);
      end;
  finally
    c.Free;
  end;
end;

procedure TControllerThemeNameTest.TestTrackBarShowValueHasVisibleInk;
{ TTyTrackBar.ShowValue paints its number with the control's OWN style TextColor. No theme
  in the repo ever set one, so TextColor resolved to the unset default $00000000 -- alpha 0
  -- and the readout was invisible in every skin, in both modes, since the property shipped.
  It reserved the strip and shortened the track, so the layout moved and the number did not
  appear: exactly the shape that makes a feature look absent rather than broken. (The
  trackbar example had hand-rolled a readout out of a separate label to compensate.)

  Same failure mode as the chrome keys above, so the same shape of guard: assert the ink is
  present, opaque, and distinguishable from the track it is drawn over -- for every built-in
  skin and both modes, since a skin that writes its own TyTrackBar rule suppresses the base
  one and has to carry the colour itself. }
var
  c: TTyStyleController;
  names: TStringArray;
  s: TTyStyleSet;
  i, m: Integer;
  mode: string;
begin
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  c := TTyStyleController.Create(nil);
  try
    for i := 0 to High(names) do
      for m := 0 to 1 do
      begin
        if m = 0 then mode := 'light' else mode := 'dark';
        c.ThemeName := names[i];
        c.Mode := mode;
        s := c.Model.ResolveStyle('TyTrackBar', '', []);
        AssertTrue(Format('%s/%s: track bar has an ink colour at all', [names[i], mode]),
          tpTextColor in s.Present);
        AssertTrue(Format('%s/%s: track bar ink is not fully transparent', [names[i], mode]),
          TyAlphaOf(s.TextColor) > 0);
        AssertTrue(Format('%s/%s: track bar ink differs from its own track fill',
          [names[i], mode]),
          (TyRedOf(s.TextColor) <> TyRedOf(s.Background.Color)) or
          (TyGreenOf(s.TextColor) <> TyGreenOf(s.Background.Color)) or
          (TyBlueOf(s.TextColor) <> TyBlueOf(s.Background.Color)));
      end;
  finally
    c.Free;
  end;
end;

procedure TControllerThemeNameTest.TestChromeKeysKeepTheirBaseProperties;
{ THE guard the previous round was missing. A skin that writes ANY rule for a typeKey
  suppresses the base layer's ENTIRE rule for it (TTyStyleModel.UserHasTypeKey) — so making
  the chrome bars flush by adding `TyStatusBar { background: ... }` silently threw away the
  base's `color`, border and font as well. The status bar then drew its text in an unset
  colour ($00000000, fully transparent): a completely blank status bar.

  The bars are flush via the --chrome-bar-bg TOKEN precisely so no skin needs such a rule.
  Assert the consequence directly: across every built-in skin and BOTH modes, the chrome
  keys must still resolve a usable ink — present, opaque, and not equal to their own fill. }
var
  c: TTyStyleController;
  names: TStringArray;
  s: TTyStyleSet;
  i, m: Integer;
  mode: string;
begin
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  c := TTyStyleController.Create(nil);
  try
    for i := 0 to High(names) do
      for m := 0 to 1 do
      begin
        if m = 0 then mode := 'light' else mode := 'dark';
        c.ThemeName := names[i];
        c.Mode := mode;
        s := c.Model.ResolveStyle('TyStatusBar', '', []);
        AssertTrue(Format('%s/%s: status bar has an ink colour at all', [names[i], mode]),
          tpTextColor in s.Present);
        AssertTrue(Format('%s/%s: status bar ink is not fully transparent', [names[i], mode]),
          TyAlphaOf(s.TextColor) > 0);
        AssertTrue(Format('%s/%s: status bar ink differs from its own fill', [names[i], mode]),
          (TyRedOf(s.TextColor) <> TyRedOf(s.Background.Color)) or
          (TyGreenOf(s.TextColor) <> TyGreenOf(s.Background.Color)) or
          (TyBlueOf(s.TextColor) <> TyBlueOf(s.Background.Color)));
        // The scroll track's handle colour rides the same rule and vanished the same way.
        s := c.Model.ResolveStyle('TyScrollBar', '', []);
        AssertTrue(Format('%s/%s: scrollbar keeps its handle colour', [names[i], mode]),
          (tpTextColor in s.Present) and (TyAlphaOf(s.TextColor) > 0));
      end;
  finally c.Free; end;
end;

procedure TControllerThemeNameTest.TestAntDesignGhostIsAFlatTextButton;
{ 'ghost' is wired by library CODE to Ant's type="text" role, not type="link": TTyToolBar
  forces every flat button to it (tyControls.ToolBar.pas), as do the calculator keypad and the
  dialog button bar, and no 'link' StyleClass exists anywhere. Two things follow, and both
  were wrong under antdesign:
    - the ink is colorText (--ink), NOT the brand blue (Ant reserves colorPrimary for links);
    - a text button carries NO shadow. A variant inherits the base TyButton rule inside the
      same layer, so ghost was picking up 'shadow: 0 1 0 var(--shadow-soft)'. On a transparent
      button that whisper washes the whole face — measured #F9F9F9 on the white tool bar, the
      "grey pill" a flat button must not have. }
var
  c: TTyStyleController;
  ghost, plain: TTyStyleSet;
  m: Integer;
  mode: string;
begin
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  try
    for m := 0 to 1 do
    begin
      if m = 0 then mode := 'light' else mode := 'dark';
      c.ThemeName := 'antdesign';
      c.Mode := mode;
      ghost := c.Model.ResolveStyle('TyButton', 'ghost', []);
      plain := c.Model.ResolveStyle('TyButton', '', []);

      // Flat: nothing painted behind it, and no shadow washing the face.
      AssertEquals(mode + ': ghost rests fully transparent', 0, TyAlphaOf(ghost.Background.Color));
      AssertEquals(mode + ': a text button casts no shadow', 0, TyAlphaOf(ghost.ShadowColor));

      // Text ink, not link blue: it matches the ordinary button's ink.
      AssertEquals(mode + ': ghost ink R = the text ink', TyRedOf(plain.TextColor), TyRedOf(ghost.TextColor));
      AssertEquals(mode + ': ghost ink G = the text ink', TyGreenOf(plain.TextColor), TyGreenOf(ghost.TextColor));
      AssertEquals(mode + ': ghost ink B = the text ink', TyBlueOf(plain.TextColor), TyBlueOf(ghost.TextColor));
    end;
  finally c.Free; end;
end;

procedure TControllerThemeNameTest.TestAeroTabRampIsOneColdFamilyInBothModes;
{ aero's tab HOVER step shipped unverified -- it was reasoned about in the stylesheet
  comment and never looked at. The reasoning is sound (hover aliases --surface-chrome, the
  same cold family the chrome band is cut from) but "likely fine" is not a check, and the
  one thing that could have gone wrong is cheap to measure: aero does not restyle TyTab at
  all, it only re-seats two TOKENS per mode, so a token typo or a plain-:root slip would
  leave the strip resolving the BASE layer's neutral greys (darken(white, 5%/2%)) on a cold
  blue window -- the exact second-design-system look the chrome fix removed everywhere else.

  What is checkable headlessly is the whole of that claim:
    - hover resolves to --surface-chrome and rest to --chrome-bar-bg, i.e. the strip is cut
      from the chrome family and not from the base MAP. Pinned by comparing against the
      keys that own those tokens (TyToolBar's fill is --chrome-bar-bg) rather than against
      hex literals, so a legitimate retune of the family carries the test with it.
    - hover is NOT inert: a hovered tab must resolve a different fill from a resting one.
      This is the goHeaderPushedLook defect class -- a state that resolves identically to
      rest is a state the user cannot see. It is worth pinning here precisely because the
      step is SUBTLE by design (7 luma in light, 5 in dark, Win7's own restraint); subtle
      is one typo away from zero, and zero looks like "no hover at all".
    - the ramp stays inside one luminance class in each mode, which is what makes it a
      family rather than two designs. Direction differs by mode and that is deliberate:
      light steps DOWN from the white page (rest 221 < hover 228 < selected 255), dark
      steps UP off the wash (selected 30 < rest 46 < hover 51), because the selected tab
      connects to the page sheet in both.

  What this does NOT do is put it on a screen. The remaining risk after this test is a
  painting risk (does TTyTabSet actually consult :hover for the strip), not a theme risk,
  and it needs a real window. Recorded so the next person does not read a green test as
  more than it is. }
var
  c: TTyStyleController;
  m: Integer;
  mode: string;
  rest, hover, sel, bar, chromeHost: TTyStyleSet;

  function L(const AFill: TTyFill): Double;
  begin
    if AFill.Kind = tfkLinearGradient then
      Result := (0.299 * TyRedOf(AFill.GradFrom) + 0.587 * TyGreenOf(AFill.GradFrom)
               + 0.114 * TyBlueOf(AFill.GradFrom)
               + 0.299 * TyRedOf(AFill.GradTo) + 0.587 * TyGreenOf(AFill.GradTo)
               + 0.114 * TyBlueOf(AFill.GradTo)) / 2
    else
      Result := 0.299 * TyRedOf(AFill.Color) + 0.587 * TyGreenOf(AFill.Color)
              + 0.114 * TyBlueOf(AFill.Color);
  end;

begin
  TyRegisterBuiltinThemes;
  c := TTyStyleController.Create(nil);
  try
    c.ThemeName := 'aero';
    for m := 0 to 1 do
    begin
      if m = 0 then mode := 'light' else mode := 'dark';
      c.Mode := mode;

      rest  := c.Model.ResolveStyle('TyTab', '', []);
      hover := c.Model.ResolveStyle('TyTab', '', [tysHover]);
      sel   := c.Model.ResolveStyle('TyTab', '', [tysActive]);
      { The two keys that OWN the chrome tokens the strip is supposed to alias:
        TyToolBar fills from --chrome-bar-bg, TyTreeHeader from --surface-chrome. }
      bar         := c.Model.ResolveStyle('TyToolBar', '', []);
      chromeHost  := c.Model.ResolveStyle('TyTreeHeader', '', []);

      AssertEquals(Format('aero/%s: a resting tab must BE the command band '
        + '(--chrome-bar-bg), not the base MAP''s neutral darken(surface,5%%)', [mode]),
        Int64(bar.Background.Color), Int64(rest.Background.Color));
      AssertEquals(Format('aero/%s: a hovered tab must lift to the header steel '
        + '(--surface-chrome) -- the token the stylesheet claims, measured against the key '
        + 'that owns it rather than a hex literal', [mode]),
        Int64(chromeHost.Background.Color), Int64(hover.Background.Color));

      AssertTrue(Format('aero/%s: hover resolves IDENTICALLY to rest — the state is '
        + 'invisible (tab %.0f vs %.0f)', [mode, L(hover.Background), L(rest.Background)]),
        hover.Background.Color <> rest.Background.Color);

      { One family, not two designs: rest and hover must sit on the same side of the
        light/dark cut as each other. The SELECTED tab is deliberately excluded — it is the
        page sheet, and in dark mode it sits below both by design. }
      AssertEquals(Format('aero/%s: rest (%.0f) and hover (%.0f) must be one luminance '
        + 'class', [mode, L(rest.Background), L(hover.Background)]),
        L(rest.Background) >= 128.0, L(hover.Background) >= 128.0);

      { Direction, per mode, exactly as the stylesheet documents it. }
      if m = 0 then
        AssertTrue(Format('aero/light: the cold ramp must climb rest(%.0f) < hover(%.0f) '
          + '< selected(%.0f)', [L(rest.Background), L(hover.Background), L(sel.Background)]),
          (L(rest.Background) < L(hover.Background))
          and (L(hover.Background) < L(sel.Background)))
      else
        AssertTrue(Format('aero/dark: chrome lifts OFF the wash — selected(%.0f) < '
          + 'rest(%.0f) < hover(%.0f)',
          [L(sel.Background), L(rest.Background), L(hover.Background)]),
          (L(sel.Background) < L(rest.Background))
          and (L(rest.Background) < L(hover.Background)));
    end;
  finally
    c.Free;
  end;
end;

initialization
  RegisterTest(TThemeRegistryCssTest);
  RegisterTest(TBuiltinSyncTest);
  RegisterTest(TBuiltinThemesTest);
  RegisterTest(TControllerThemeNameTest);
end.
