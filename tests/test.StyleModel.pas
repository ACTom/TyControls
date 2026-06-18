unit test.StyleModel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, tyControls.Types, tyControls.StyleModel,
  tyControls.Css.Values, tyControls.Css.Parser;
type
  TTestStyleMerge = class(TTestCase)
  published
    procedure TestMergeUnionPresent;
    procedure TestMergeOverlaysOnlyPresent;
    procedure TestMergeRadiusCornersOverrides;
    procedure TestMergeOutlineOverrides;
  end;

  TTestStyleLoad = class(TTestCase)
  private
    FModel: TTyStyleModel;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestLoadSolidBackgroundResolvesVar;
    procedure TestLoadGradientBackground;
    procedure TestLoadNineSliceBackgroundImage;
    procedure TestLoadPlainImageBackground;
    procedure TestLoadGlassTokens;
    procedure TestLoadFromCssParseErrorPreservesPrevious;
    procedure TestDuplicateRuleLastWins;
    procedure TestBackgroundColorAlias;
    procedure TestBackgroundColorRgb;
  end;

  { Phase 0 (theme v2): background:none keyword + merge-then-resolve unlock }
  TTestStylePhase0 = class(TTestCase)
  private
    FModel: TTyStyleModel;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestBackgroundNoneKeyword;
    procedure TestSeedOverrideReachesBaseRule;
    procedure TestBaseResolveUnchanged;
    procedure TestAdditiveLoad;
  end;

  { Phase 2 (theme v2): property cascade (A7) — base->user per-property merge behind a flag }
  TTestStylePropertyCascade = class(TTestCase)
  private
    FModel: TTyStyleModel;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDefaultFlagOff;
    procedure TestFlagOffAllOrNothing;
    procedure TestFlagOnThinThemeInheritsBase;
    procedure TestFlagOnUserOverridesPerProperty;
    procedure TestFlagOnUserLayerStillWinsLastDuplicate;
  end;

  { Phase 2 (theme v2): @import (A8) — file-level compose, cycle guard, diamond dedup }
  TTestStyleImport = class(TTestCase)
  private
    FDir: string;
    procedure WriteCss(const AName, AContent: string);
    function PathOf(const AName: string): string;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestImporterOverridesImported;
    procedure TestNestedRelativeResolution;
    procedure TestCycleRaisesNotHang;
    procedure TestDiamondLoadsBaseOnce;
    procedure TestMissingImportRaises;
  end;

  { Phase 2 (theme v2): per-instance StyleOverride (A9) — ResolveOverride layer 2 }
  TTestStyleOverride = class(TTestCase)
  private
    FModel: TTyStyleModel;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestOverrideAppliesOnlyMentionedProps;
    procedure TestOverrideWinsOverTheme;
    procedure TestOverrideVarResolvesAgainstTheme;
    procedure TestOverrideVarRebindsOnThemeSwitch;
    procedure TestOverrideBadValueDoesNotRaise;
    procedure TestOverrideEmptyIsNoOp;
  end;

  TTestStyleResolve = class(TTestCase)
  private
    FModel: TTyStyleModel;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestButtonNormal;
    procedure TestButtonPrimary;
    procedure TestButtonHover;
    procedure TestButtonDisabled;
    procedure TestPrimaryHoverCombo;
    procedure TestStateOrderDisabledWinsOverHover;
  end;

  TTestStyleShadow = class(TTestCase)
  published
    procedure TestShadowLiteralColor;
    procedure TestShadowWithVarColor;
  end;

  TTestStylePadding = class(TTestCase)
  published
    procedure TestPaddingWithVar;
    procedure TestPaddingThreeValues;
  end;

  TTestStyleBorderStyle = class(TTestCase)
  published
    procedure TestBorderStyleNoneParsed;
    procedure TestBorderStyleSolidDefault;
  end;

  TTestStyleBorderShorthand = class(TTestCase)
  published
    procedure TestBorderShorthand;
    procedure TestBorderShorthandNone;
    procedure TestBorderShorthandVarColor;
  end;

  TTestStyleBorderRadius = class(TTestCase)
  published
    procedure TestBorderRadiusSingleValueUniform;
    procedure TestBorderRadiusFourValuesTopOnly;
    procedure TestBorderRadiusFourValuesWithVar;
  end;

  TTestStyleOutline = class(TTestCase)
  published
    procedure TestOutlineParsed;
    procedure TestOutlineAbsentWhenNotFocused;
    procedure TestOutlineOffsetParsed;
  end;

implementation

procedure TTestStyleMerge.TestMergeUnionPresent;
var base, over: TTyStyleSet;
begin
  base := EmptyStyleSet;
  base.Present := [tpTextColor];
  base.TextColor := TyRGB($FF, $FF, $FF);
  over := EmptyStyleSet;
  over.Present := [tpBorderWidth];
  over.BorderWidth := 2;
  TyMergeStyleSet(base, over);
  AssertTrue('textcolor still present', tpTextColor in base.Present);
  AssertTrue('borderwidth now present', tpBorderWidth in base.Present);
  AssertEquals('borderwidth value', 2, base.BorderWidth);
  AssertEquals('textcolor preserved', Integer(TyRGB($FF, $FF, $FF)), Integer(base.TextColor));
end;

procedure TTestStyleMerge.TestMergeOverlaysOnlyPresent;
var base, over: TTyStyleSet;
begin
  base := EmptyStyleSet;
  base.Present := [tpBorderWidth];
  base.BorderWidth := 1;
  over := EmptyStyleSet;
  over.Present := [];          // nothing present -> base unchanged
  over.BorderWidth := 99;
  TyMergeStyleSet(base, over);
  AssertEquals('borderwidth unchanged', 1, base.BorderWidth);
end;

procedure TTestStyleMerge.TestMergeRadiusCornersOverrides;
var base, over: TTyStyleSet;
begin
  base := EmptyStyleSet;
  over := EmptyStyleSet;
  over.Radius := TyCorners(6, 6, 0, 0);
  over.BorderRadius := 6;
  Include(over.Present, tpBorderRadius);
  TyMergeStyleSet(base, over);
  AssertTrue('radius present after merge', tpBorderRadius in base.Present);
  AssertEquals('tl merged', 6, base.Radius.TL);
  AssertEquals('bl merged', 0, base.Radius.BL);
end;

procedure TTestStyleMerge.TestMergeOutlineOverrides;
var base, over: TTyStyleSet;
begin
  base := EmptyStyleSet;
  over := EmptyStyleSet;
  over.OutlineColor := TyRGB($FF, $00, $00);
  over.OutlineWidth := 2;
  over.OutlineOffset := 1;
  Include(over.Present, tpOutline);
  TyMergeStyleSet(base, over);
  AssertTrue('outline present', tpOutline in base.Present);
  AssertEquals('outline width', 2, base.OutlineWidth);
  AssertEquals('outline offset', 1, base.OutlineOffset);
  AssertEquals('outline color r', $FF, TyRedOf(base.OutlineColor));
end;

const
  CSS_LOAD =
    ':root {' + LineEnding +
    '  --accent: #3B82F6;' + LineEnding +
    '  --surface: #1E1E1E;' + LineEnding +
    '}' + LineEnding +
    'TyButton {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '}' + LineEnding +
    'TyButton.primary {' + LineEnding +
    '  background: linear-gradient(90deg, #000000, #FFFFFF);' + LineEnding +
    '}' + LineEnding +
    'TyPanel {' + LineEnding +
    '  background-image: url(panel.png) slice(4 5 6 7);' + LineEnding +
    '}' + LineEnding;

procedure TTestStyleLoad.SetUp;
begin
  FModel := TTyStyleModel.Create;
  FModel.LoadFromCss(CSS_LOAD);
end;

procedure TTestStyleLoad.TearDown;
begin
  FModel.Free;
end;

procedure TTestStyleLoad.TestLoadSolidBackgroundResolvesVar;
var s: TTyStyleSet;
begin
  s := FModel.ResolveStyle('TyButton', '', []);
  AssertTrue('bg present', tpBackground in s.Present);
  AssertTrue('solid kind', s.Background.Kind = tfkSolid);
  // #1E1E1E
  AssertEquals('bg red', $1E, TyRedOf(s.Background.Color));
  AssertEquals('bg green', $1E, TyGreenOf(s.Background.Color));
  AssertEquals('bg blue', $1E, TyBlueOf(s.Background.Color));
end;

procedure TTestStyleLoad.TestLoadGradientBackground;
var s: TTyStyleSet;
begin
  s := FModel.ResolveStyle('TyButton', 'primary', []);
  AssertTrue('gradient kind', s.Background.Kind = tfkLinearGradient);
  AssertEquals('grad from red', $00, TyRedOf(s.Background.GradFrom));
  AssertEquals('grad to red', $FF, TyRedOf(s.Background.GradTo));
  AssertTrue('grad angle 90', Abs(s.Background.GradAngleDeg - 90) < 0.01);
end;

procedure TTestStyleLoad.TestLoadNineSliceBackgroundImage;
var s: TTyStyleSet;
begin
  s := FModel.ResolveStyle('TyPanel', '', []);
  AssertTrue('nineslice kind', s.Background.Kind = tfkNineSlice);
  AssertEquals('image path', 'panel.png', s.Background.ImagePath);
  AssertEquals('slice top', 4, s.Background.SliceInsets.Top);
  AssertEquals('slice right', 5, s.Background.SliceInsets.Right);
  AssertEquals('slice bottom', 6, s.Background.SliceInsets.Bottom);
  AssertEquals('slice left', 7, s.Background.SliceInsets.Left);
end;

procedure TTestStyleLoad.TestLoadPlainImageBackground;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    // url() WITHOUT slice() -> plain image fill; size/blur are separate props.
    m.LoadFromCss('TyForm { background-image: url(assets/bg.jpg);'
      + ' background-size: stretch; background-blur: 12px; }');
    s := m.ResolveStyle('TyForm', '', []);
    AssertTrue('plain image kind', s.Background.Kind = tfkImage);
    AssertEquals('image path', 'assets/bg.jpg', s.Background.ImagePath);
    AssertTrue('image mode stretch', s.Background.ImageMode = timStretch);
    AssertEquals('blur 12', 12, s.Background.Blur);
    // default size when background-size omitted is cover
    m.LoadFromCss('TyForm { background-image: url(a.png); }');
    s := m.ResolveStyle('TyForm', '', []);
    AssertTrue('default mode cover', s.Background.ImageMode = timCover);
  finally m.Free; end;
end;

procedure TTestStyleLoad.TestLoadGlassTokens;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(
      'TyForm { background-image: url(a.jpg); background-under-titlebar: true; }'
      + ' TyPanel { background: #FFFFFF; glass-blur: 14px; glass-tint: alpha(#FFFFFF, 0.5); }'
      + ' TyPanel:hover { glass-tint: alpha(#000000, 0.2); }'
      + ' TyButton { glass-blur: 20px; }');
    s := m.ResolveStyle('TyForm', '', []);
    AssertTrue('under-titlebar parsed true', s.BackgroundUnderTitlebar);
    AssertTrue('bgUnderTitle present', tpBgUnderTitle in s.Present);
    s := m.ResolveStyle('TyPanel', '', []);
    AssertTrue('glass present', tpGlass in s.Present);
    AssertEquals('glass-blur 14', 14, s.Background.GlassBlur);
    AssertTrue('panel bg still solid white', s.Background.Kind = tfkSolid);
    AssertEquals('panel bg red FF (not blanked)', $FF, TyRedOf(s.Background.Color));
    // hover merges glass-tint NARROWLY — must not blank the base background
    s := m.ResolveStyle('TyPanel', '', [tysHover]);
    AssertEquals('hover keeps bg solid white', $FF, TyRedOf(s.Background.Color));
    AssertTrue('hover bg still solid', s.Background.Kind = tfkSolid);
    AssertEquals('MaxGlassBlur = largest (20)', 20, m.MaxGlassBlur);
  finally m.Free; end;
end;

procedure TTestStyleLoad.TestLoadFromCssParseErrorPreservesPrevious;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('TyButton { color: #112233; border-width: 9px; }');
    try m.LoadFromCss('TyButton { @@@ broken'); except on ETyCssError do ; end;
    s := m.ResolveStyle('TyButton','',[]);
    AssertEquals('previous color preserved', $11, TyRedOf(s.TextColor));
    AssertEquals('previous border-width preserved', 9, s.BorderWidth);
  finally m.Free; end;
end;

procedure TTestStyleLoad.TestDuplicateRuleLastWins;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('TyButton { color:#111111; } TyButton { color:#222222; }');
    s := m.ResolveStyle('TyButton','',[]);
    AssertEquals('later duplicate wins', $22, TyRedOf(s.TextColor));
  finally m.Free; end;
end;

procedure TTestStyleLoad.TestBackgroundColorAlias;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('T { background-color: #FF0000; }');
    s := m.ResolveStyle('T','',[]);
    AssertTrue('bg present', tpBackground in s.Present);
    AssertTrue('solid', s.Background.Kind = tfkSolid);
    AssertEquals('r', $FF, TyRedOf(s.Background.Color));
  finally m.Free; end;
end;

procedure TTestStyleLoad.TestBackgroundColorRgb;   // alias + rgb together
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('T { background-color: rgb(0, 128, 255); }');
    s := m.ResolveStyle('T','',[]);
    AssertEquals('g', 128, TyGreenOf(s.Background.Color));
    AssertEquals('b', 255, TyBlueOf(s.Background.Color));
  finally m.Free; end;
end;

const
  CSS_RESOLVE =
    ':root {' + LineEnding +
    '  --accent: #3B82F6;' + LineEnding +
    '  --surface: #404040;' + LineEnding +
    '}' + LineEnding +
    'TyButton {' + LineEnding +
    '  background: var(--surface);' + LineEnding +
    '  color: #FFFFFF;' + LineEnding +
    '  border-width: 1px;' + LineEnding +
    '  border-radius: 6px;' + LineEnding +
    '}' + LineEnding +
    'TyButton.primary {' + LineEnding +
    '  background: var(--accent);' + LineEnding +
    '}' + LineEnding +
    'TyButton:hover {' + LineEnding +
    '  background: lighten(var(--surface), 50%);' + LineEnding +
    '}' + LineEnding +
    'TyButton.primary:hover {' + LineEnding +
    '  border-width: 3px;' + LineEnding +
    '}' + LineEnding +
    'TyButton:disabled {' + LineEnding +
    '  opacity: 0.5;' + LineEnding +
    '  background: #111111;' + LineEnding +
    '}' + LineEnding;

{ ── property cascade (A7) ───────────────────────────────────────────────────── }

procedure TTestStylePropertyCascade.SetUp;
begin
  FModel := TTyStyleModel.Create;   // built-in base layer seeded (TyButton has bg+border+...)
end;

procedure TTestStylePropertyCascade.TearDown;
begin
  FModel.Free;
end;

procedure TTestStylePropertyCascade.TestDefaultFlagOff;
begin
  // The flag defaults OFF so the golden baseline (all-or-nothing) is preserved.
  AssertFalse('PropertyCascade defaults False', FModel.PropertyCascade);
end;

procedure TTestStylePropertyCascade.TestFlagOffAllOrNothing;
var s: TTyStyleSet;
begin
  // Flag OFF (default): a thin user TyButton rule touching only color SUPPRESSES the
  // entire built-in base TyButton layer for that typeKey — base background/border do
  // NOT bleed in. This is the unchanged pre-A7 behavior the golden depends on.
  FModel.LoadFromCss('TyButton { color: #FF0000; }');
  s := FModel.ResolveStyle('TyButton', '', []);
  AssertEquals('user color applied', $FF, TyRedOf(s.TextColor));
  AssertFalse('base background suppressed (all-or-nothing)', tpBackground in s.Present);
  AssertFalse('base border-color suppressed (all-or-nothing)', tpBorderColor in s.Present);
  AssertFalse('base border-width suppressed (all-or-nothing)', tpBorderWidth in s.Present);
end;

procedure TTestStylePropertyCascade.TestFlagOnThinThemeInheritsBase;
var s: TTyStyleSet;
begin
  // Flag ON: a thin theme that sets ONLY color on TyButton inherits the base's other
  // properties (background + border-color + border-width + border-radius), the
  // headline A7 win (省略=继承, D4). Built-in base TyButton supplies all of these.
  FModel.PropertyCascade := True;
  FModel.LoadFromCss('TyButton { color: #FF0000; }');
  s := FModel.ResolveStyle('TyButton', '', []);
  AssertEquals('user color wins', $FF, TyRedOf(s.TextColor));
  AssertTrue('base background inherited', tpBackground in s.Present);
  AssertTrue('base border-color inherited', tpBorderColor in s.Present);
  AssertTrue('base border-width inherited', tpBorderWidth in s.Present);
  AssertTrue('base border-radius inherited', tpBorderRadius in s.Present);
end;

procedure TTestStylePropertyCascade.TestFlagOnUserOverridesPerProperty;
var sBase, s: TTyStyleSet;
begin
  // Flag ON: the user layer still overwrites the properties it DOES set, per-property.
  // background is set by both base and the thin theme -> user value (#123456) wins;
  // border-width is set only by base -> inherited unchanged.
  sBase := FModel.ResolveStyle('TyButton', '', []);   // base-only (no user theme yet)
  FModel.PropertyCascade := True;
  FModel.LoadFromCss('TyButton { background: #123456; }');
  s := FModel.ResolveStyle('TyButton', '', []);
  AssertTrue('background present', tpBackground in s.Present);
  AssertTrue('user background solid', s.Background.Kind = tfkSolid);
  AssertEquals('user background red', $12, TyRedOf(s.Background.Color));
  AssertEquals('user background green', $34, TyGreenOf(s.Background.Color));
  AssertEquals('user background blue', $56, TyBlueOf(s.Background.Color));
  AssertTrue('base border-width still inherited', tpBorderWidth in s.Present);
  AssertEquals('inherited border-width matches base', sBase.BorderWidth, s.BorderWidth);
end;

procedure TTestStylePropertyCascade.TestFlagOnUserLayerStillWinsLastDuplicate;
var s: TTyStyleSet;
begin
  // Flag ON: the user layer is applied AFTER the base layer, so a user color overrides
  // the base color; and within the user layer apply-all-forward keeps last-duplicate-wins.
  FModel.PropertyCascade := True;
  FModel.LoadFromCss('TyButton { color: #111111; } TyButton { color: #222222; }');
  s := FModel.ResolveStyle('TyButton', '', []);
  AssertEquals('user last-duplicate color wins over base', $22, TyRedOf(s.TextColor));
  AssertTrue('base background still inherited under cascade', tpBackground in s.Present);
end;

{ ── @import (A8) ──────────────────────────────────────────────────────────── }

procedure TTestStyleImport.SetUp;
begin
  FDir := IncludeTrailingPathDelimiter(GetTempDir) +
    'tyimport_' + IntToStr(PtrUInt(Self)) + '_' + IntToStr(Random(1 shl 30)) + PathDelim;
  ForceDirectories(FDir);
  ForceDirectories(FDir + 'sub' + PathDelim);
end;

procedure TTestStyleImport.TearDown;
begin
  // best-effort cleanup; leaving temp files behind is harmless if deletion fails
  DeleteFile(PathOf('a.tycss'));
  DeleteFile(PathOf('b.tycss'));
  DeleteFile(PathOf('base.tycss'));
  DeleteFile(PathOf('top.tycss'));
  DeleteFile(FDir + 'sub' + PathDelim + 'b.tycss');
  DeleteFile(FDir + 'sub' + PathDelim + 'c.tycss');
  RemoveDir(FDir + 'sub' + PathDelim);
  RemoveDir(FDir);
end;

function TTestStyleImport.PathOf(const AName: string): string;
begin
  Result := FDir + AName;
end;

procedure TTestStyleImport.WriteCss(const AName, AContent: string);
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.Text := AContent;
    sl.SaveToFile(FDir + AName);
  finally
    sl.Free;
  end;
end;

procedure TTestStyleImport.TestImporterOverridesImported;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  // a.tycss imports b.tycss then restates color. The importer's color wins, but b's
  // background SURVIVES (per-property merge: imported spliced FIRST, importer last).
  WriteCss('b.tycss', 'TyButton { color: #111111; background: #999999; }');
  WriteCss('a.tycss', '@import "b.tycss"; TyButton { color: #222222; }');
  m := TTyStyleModel.Create;
  try
    m.LoadFromFile(PathOf('a.tycss'));
    s := m.ResolveStyle('TyButton', '', []);
    AssertEquals('importer color wins', $22, TyRedOf(s.TextColor));
    AssertTrue('imported background survives', tpBackground in s.Present);
    AssertEquals('imported background value', $99, TyRedOf(s.Background.Color));
  finally m.Free; end;
end;

procedure TTestStyleImport.TestNestedRelativeResolution;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  // a imports sub/b; b imports c (relative to sub/, NOT a's dir). Proves the base-dir
  // stack: c resolves relative to the importing file's own directory.
  WriteCss('a.tycss', '@import "sub/b.tycss"; TyButton { color: #333333; }');
  WriteCss('sub' + PathDelim + 'b.tycss', '@import "c.tycss"; TyButton { border-width: 5px; }');
  WriteCss('sub' + PathDelim + 'c.tycss', 'TyButton { background: #777777; }');
  m := TTyStyleModel.Create;
  try
    m.LoadFromFile(PathOf('a.tycss'));
    s := m.ResolveStyle('TyButton', '', []);
    AssertEquals('top-level color', $33, TyRedOf(s.TextColor));
    AssertEquals('nested b border', 5, s.BorderWidth);
    AssertTrue('deepest c background present', tpBackground in s.Present);
    AssertEquals('deepest c background value', $77, TyRedOf(s.Background.Color));
  finally m.Free; end;
end;

procedure TTestStyleImport.TestCycleRaisesNotHang;
var m: TTyStyleModel; raised: Boolean;
begin
  // a -> b -> a is a cycle: must RAISE (ETyCssError), never infinite-loop/hang.
  WriteCss('a.tycss', '@import "b.tycss"; TyButton { color: #111111; }');
  WriteCss('b.tycss', '@import "a.tycss"; TyButton { color: #222222; }');
  m := TTyStyleModel.Create;
  raised := False;
  try
    try
      m.LoadFromFile(PathOf('a.tycss'));
    except
      on E: ETyCssError do
        raised := True;
    end;
    AssertTrue('@import cycle raises ETyCssError (no hang)', raised);
  finally m.Free; end;
end;

procedure TTestStyleImport.TestDiamondLoadsBaseOnce;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  // top -> a -> base and top -> b -> base. base loads ONCE: the splice order is
  // base, a, b, top. base sets color #aaaaaa, a sets #bbbbbb. If base re-applied after
  // a (double load) the final color would be #aa; with single load it stays a's #bb.
  WriteCss('base.tycss', 'TyButton { color: #aaaaaa; background: #555555; }');
  WriteCss('a.tycss', '@import "base.tycss"; TyButton { color: #bbbbbb; }');
  WriteCss('b.tycss', '@import "base.tycss"; TyButton { border-width: 4px; }');
  WriteCss('top.tycss', '@import "a.tycss"; @import "b.tycss"; TyButton { border-radius: 7px; }');
  m := TTyStyleModel.Create;
  try
    m.LoadFromFile(PathOf('top.tycss'));
    s := m.ResolveStyle('TyButton', '', []);
    AssertEquals('base loaded once -> a color survives (not re-overwritten by base)',
      $BB, TyRedOf(s.TextColor));
    AssertTrue('base background present', tpBackground in s.Present);
    AssertEquals('base background value', $55, TyRedOf(s.Background.Color));
    AssertEquals('b border applied', 4, s.BorderWidth);
    AssertEquals('top radius applied', 7, s.BorderRadius);
  finally m.Free; end;
end;

procedure TTestStyleImport.TestMissingImportRaises;
var m: TTyStyleModel; raised: Boolean;
begin
  // a relative @import target that does not exist is a load-time fail-fast (no silent skip).
  WriteCss('a.tycss', '@import "nope.tycss"; TyButton { color: #111111; }');
  m := TTyStyleModel.Create;
  raised := False;
  try
    try
      m.LoadFromFile(PathOf('a.tycss'));
    except
      on E: ETyCssError do
        raised := True;
    end;
    AssertTrue('missing @import target raises ETyCssError', raised);
  finally m.Free; end;
end;

{ ── per-instance StyleOverride (A9) ─────────────────────────────────────────── }

procedure TTestStyleOverride.SetUp;
begin
  FModel := TTyStyleModel.Create;   // built-in base layer seeded (--accent = #3B82F6)
end;

procedure TTestStyleOverride.TearDown;
begin
  FModel.Free;
end;

procedure TTestStyleOverride.TestOverrideAppliesOnlyMentionedProps;
var ovr: TTyStyleSet;
begin
  // ResolveOverride sets Present flags ONLY for the properties the fragment mentions,
  // so TyMergeStyleSet overlays just those on top of the resolved theme style.
  ovr := FModel.ResolveOverride('background:#FF0000; border-width:5px');
  AssertTrue('background present', tpBackground in ovr.Present);
  AssertTrue('border-width present', tpBorderWidth in ovr.Present);
  AssertEquals('override bg red', $FF, TyRedOf(ovr.Background.Color));
  AssertEquals('override border-width', 5, ovr.BorderWidth);
  AssertFalse('unmentioned text-color not present', tpTextColor in ovr.Present);
  AssertFalse('unmentioned border-color not present', tpBorderColor in ovr.Present);
end;

procedure TTestStyleOverride.TestOverrideWinsOverTheme;
var themed, ovr, merged: TTyStyleSet;
begin
  // An override property overlaid (per-Present) on top of a theme style wins for that
  // property while leaving the theme's other properties intact — the layer-2 semantics
  // CurrentStyle uses (here exercised directly via TyMergeStyleSet).
  FModel.LoadFromCss('TyButton { color:#FFFFFF; background:#101010; border-width:2px; }');
  themed := FModel.ResolveStyle('TyButton', '', []);
  ovr := FModel.ResolveOverride('background:#00FF00');
  merged := themed;
  TyMergeStyleSet(merged, ovr);
  AssertEquals('override background wins', $00, TyRedOf(merged.Background.Color));
  AssertEquals('override background green', $FF, TyGreenOf(merged.Background.Color));
  AssertEquals('theme text-color survives', $FF, TyRedOf(merged.TextColor));
  AssertEquals('theme border-width survives', 2, merged.BorderWidth);
end;

procedure TTestStyleOverride.TestOverrideVarResolvesAgainstTheme;
var ovr: TTyStyleSet;
begin
  // var(--accent) in an override resolves through the LIVE merged var set, NOT a literal.
  // A user theme redefines --accent to pure green; the override must pick that up.
  FModel.LoadFromCss(':root { --accent: #00FF00; }');
  ovr := FModel.ResolveOverride('border-color: var(--accent)');
  AssertTrue('border-color present', tpBorderColor in ovr.Present);
  AssertEquals('var(--accent) resolves to themed green (r)', $00, TyRedOf(ovr.BorderColor));
  AssertEquals('var(--accent) resolves to themed green (g)', $FF, TyGreenOf(ovr.BorderColor));
  AssertEquals('var(--accent) resolves to themed green (b)', $00, TyBlueOf(ovr.BorderColor));
end;

procedure TTestStyleOverride.TestOverrideVarRebindsOnThemeSwitch;
var ovr: TTyStyleSet;
begin
  // The same override text re-resolves against whatever theme is active. Switching the
  // theme (a REPLACE load that bumps ThemeVersion) re-binds var(--accent) to the new
  // value — the §3.8 promise that overrides persist but their var() re-bind on switch.
  FModel.LoadFromCss(':root { --accent: #FF0000; }');   // theme A: red accent
  ovr := FModel.ResolveOverride('border-color: var(--accent)');
  AssertEquals('theme A accent red', $FF, TyRedOf(ovr.BorderColor));
  AssertEquals('theme A accent not green', $00, TyGreenOf(ovr.BorderColor));

  FModel.LoadFromCss(':root { --accent: #00FF00; }');   // switch to theme B: green accent
  ovr := FModel.ResolveOverride('border-color: var(--accent)');
  AssertEquals('theme B accent now green (r)', $00, TyRedOf(ovr.BorderColor));
  AssertEquals('theme B accent now green (g)', $FF, TyGreenOf(ovr.BorderColor));
end;

procedure TTestStyleOverride.TestOverrideBadValueDoesNotRaise;
var ovr: TTyStyleSet; raised: Boolean;
begin
  // A malformed/undefined-var override must NOT raise (unlike a theme load): one bad
  // declaration is skipped while a good sibling declaration still applies.
  raised := False;
  try
    ovr := FModel.ResolveOverride('border-color: var(--no-such-var); background:#123456');
  except
    on E: Exception do raised := True;
  end;
  AssertFalse('malformed override does not raise', raised);
  // the good declaration still landed
  AssertTrue('good background still applied', tpBackground in ovr.Present);
  AssertEquals('good background value', $12, TyRedOf(ovr.Background.Color));

  // A grossly malformed fragment (unparseable) also must not raise -> empty result.
  raised := False;
  try
    ovr := FModel.ResolveOverride('@@@ not css ;;;');
  except
    on E: Exception do raised := True;
  end;
  AssertFalse('unparseable override does not raise', raised);
  AssertTrue('unparseable override yields empty present set', ovr.Present = []);
end;

procedure TTestStyleOverride.TestOverrideEmptyIsNoOp;
var ovr: TTyStyleSet;
begin
  // An empty/blank override is valid and contributes nothing (no Present flags).
  ovr := FModel.ResolveOverride('');
  AssertTrue('empty override has no present flags', ovr.Present = []);
  ovr := FModel.ResolveOverride('   ');
  AssertTrue('blank override has no present flags', ovr.Present = []);
end;

procedure TTestStyleResolve.SetUp;
begin
  FModel := TTyStyleModel.Create;
  FModel.LoadFromCss(CSS_RESOLVE);
end;

procedure TTestStyleResolve.TearDown;
begin
  FModel.Free;
end;

procedure TTestStyleResolve.TestButtonNormal;
var s: TTyStyleSet;
begin
  s := FModel.ResolveStyle('TyButton', '', []);
  AssertTrue('bg present', tpBackground in s.Present);
  AssertTrue('color present', tpTextColor in s.Present);
  AssertTrue('borderwidth present', tpBorderWidth in s.Present);
  AssertTrue('radius present', tpBorderRadius in s.Present);
  // surface #404040
  AssertEquals('bg red', $40, TyRedOf(s.Background.Color));
  AssertEquals('text white', $FF, TyRedOf(s.TextColor));
  AssertEquals('borderwidth', 1, s.BorderWidth);
  AssertEquals('radius', 6, s.BorderRadius);
end;

procedure TTestStyleResolve.TestButtonPrimary;
var s: TTyStyleSet;
begin
  s := FModel.ResolveStyle('TyButton', 'primary', []);
  // variant overrides background to accent #3B82F6 but keeps base color/border
  AssertEquals('bg red accent', $3B, TyRedOf(s.Background.Color));
  AssertEquals('bg green accent', $82, TyGreenOf(s.Background.Color));
  AssertEquals('bg blue accent', $F6, TyBlueOf(s.Background.Color));
  AssertEquals('inherited text white', $FF, TyRedOf(s.TextColor));
  AssertEquals('inherited borderwidth', 1, s.BorderWidth);
end;

procedure TTestStyleResolve.TestButtonHover;
var s: TTyStyleSet;
begin
  s := FModel.ResolveStyle('TyButton', '', [tysHover]);
  // hover overrides bg to lighten(#404040,50%) = 160
  AssertEquals('hover bg', 160, TyRedOf(s.Background.Color));
  // base props still present
  AssertEquals('text still white', $FF, TyRedOf(s.TextColor));
end;

procedure TTestStyleResolve.TestButtonDisabled;
var s: TTyStyleSet;
begin
  s := FModel.ResolveStyle('TyButton', '', [tysDisabled]);
  AssertTrue('opacity present', tpOpacity in s.Present);
  AssertTrue('opacity 0.5', Abs(s.Opacity - 0.5) < 0.0001);
  // disabled bg #111111
  AssertEquals('disabled bg', $11, TyRedOf(s.Background.Color));
end;

procedure TTestStyleResolve.TestPrimaryHoverCombo;
var s: TTyStyleSet;
begin
  s := FModel.ResolveStyle('TyButton', 'primary', [tysHover]);
  // TyButton.primary sets bg=accent; TyButton:hover overrides bg to lighten(surface,50%)=160;
  // TyButton.primary:hover then sets borderwidth=3 (no bg override there)
  AssertEquals('combo borderwidth', 3, s.BorderWidth);
  // TyButton:hover applies bg=lighten(#404040,50%)=160 AFTER TyButton.primary's accent bg
  AssertEquals('combo hover bg red', 160, TyRedOf(s.Background.Color));
end;

procedure TTestStyleResolve.TestStateOrderDisabledWinsOverHover;
var s: TTyStyleSet;
begin
  // both hover and disabled active: disabled is applied last -> bg #111111
  s := FModel.ResolveStyle('TyButton', '', [tysHover, tysDisabled]);
  AssertEquals('disabled bg wins', $11, TyRedOf(s.Background.Color));
  AssertTrue('opacity from disabled', Abs(s.Opacity - 0.5) < 0.0001);
end;

procedure TTestStyleShadow.TestShadowLiteralColor;
var
  model: TTyStyleModel;
  s: TTyStyleSet;
  expected: TTyColor;
begin
  model := TTyStyleModel.Create;
  try
    model.LoadFromCss('T { shadow: 2px 4px 8px #00000080; }');
    s := model.ResolveStyle('T', '', []);
    AssertTrue('shadow present', tpShadow in s.Present);
    AssertEquals('shadow offset X', 2, s.ShadowOffset.X);
    AssertEquals('shadow offset Y', 4, s.ShadowOffset.Y);
    AssertEquals('shadow blur', 8, s.ShadowBlur);
    expected := TyParseColor('#00000080');
    AssertEquals('shadow color', Integer(expected), Integer(s.ShadowColor));
  finally
    model.Free;
  end;
end;

procedure TTestStyleShadow.TestShadowWithVarColor;
var
  model: TTyStyleModel;
  s: TTyStyleSet;
  expected: TTyColor;
begin
  model := TTyStyleModel.Create;
  try
    model.LoadFromCss(
      ':root { --shadow-color: #00000080; }' + LineEnding +
      'T { shadow: 2px 4px 8px var(--shadow-color); }');
    s := model.ResolveStyle('T', '', []);
    AssertTrue('shadow present', tpShadow in s.Present);
    AssertEquals('shadow offset X', 2, s.ShadowOffset.X);
    AssertEquals('shadow offset Y', 4, s.ShadowOffset.Y);
    AssertEquals('shadow blur', 8, s.ShadowBlur);
    expected := TyParseColor('#00000080');
    AssertEquals('shadow color via var', Integer(expected), Integer(s.ShadowColor));
  finally
    model.Free;
  end;
end;

procedure TTestStylePadding.TestPaddingWithVar;
var
  model: TTyStyleModel;
  s: TTyStyleSet;
begin
  model := TTyStyleModel.Create;
  try
    // 2-value padding: top/bottom=4, left/right=var(--gap)=10
    // ParsePadding maps parts[0]=top/bottom=4, parts[1]=left/right=10
    // Result = Rect(Left=10, Top=4, Right=10, Bottom=4)
    model.LoadFromCss(
      ':root { --gap: 10px; }' + LineEnding +
      'T { padding: 4px var(--gap); }');
    s := model.ResolveStyle('T', '', []);
    AssertTrue('padding present', tpPadding in s.Present);
    AssertEquals('padding top',    4,  s.Padding.Top);
    AssertEquals('padding bottom', 4,  s.Padding.Bottom);
    AssertEquals('padding left',   10, s.Padding.Left);
    AssertEquals('padding right',  10, s.Padding.Right);
  finally
    model.Free;
  end;
end;

procedure TTestStylePadding.TestPaddingThreeValues;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('T { padding: 1px 2px 3px; }');
    s := m.ResolveStyle('T','',[]);
    AssertEquals('top',1,s.Padding.Top); AssertEquals('right',2,s.Padding.Right);
    AssertEquals('bottom',3,s.Padding.Bottom); AssertEquals('left',2,s.Padding.Left);
  finally m.Free; end;
end;

procedure TTestStyleBorderStyle.TestBorderStyleNoneParsed;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('T { border-style: none; border-width: 2px; border-color: #FF0000; }');
    s := m.ResolveStyle('T','',[]);
    AssertTrue('border-style present', tpBorderStyle in s.Present);
    AssertTrue('border-style none', s.BorderStyle = tbsNone);
  finally m.Free; end;
end;

procedure TTestStyleBorderStyle.TestBorderStyleSolidDefault;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('T { border-style: solid; }');
    s := m.ResolveStyle('T','',[]);
    AssertTrue('border-style solid', s.BorderStyle = tbsSolid);
  finally m.Free; end;
end;

procedure TTestStyleBorderShorthand.TestBorderShorthand;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('T { border: 2px solid #3B82F6; }');
    s := m.ResolveStyle('T','',[]);
    AssertEquals('width', 2, s.BorderWidth);
    AssertTrue('width present', tpBorderWidth in s.Present);
    AssertTrue('color present', tpBorderColor in s.Present);
    AssertEquals('color r', $3B, TyRedOf(s.BorderColor));
    AssertEquals('color g', $82, TyGreenOf(s.BorderColor));
    AssertTrue('style present', tpBorderStyle in s.Present);
    AssertTrue('style solid', s.BorderStyle = tbsSolid);
  finally m.Free; end;
end;

procedure TTestStyleBorderShorthand.TestBorderShorthandNone;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('T { border: 1px none #000000; }');
    s := m.ResolveStyle('T','',[]);
    AssertEquals('width', 1, s.BorderWidth);
    AssertTrue('color present', tpBorderColor in s.Present);
    AssertTrue('style none', s.BorderStyle = tbsNone);
    AssertTrue('style present', tpBorderStyle in s.Present);
  finally m.Free; end;
end;

procedure TTestStyleBorderShorthand.TestBorderShorthandVarColor;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(':root { --a: #112233; }'#10'T { border: 1px solid var(--a); }');
    s := m.ResolveStyle('T','',[]);
    AssertEquals('var color r', $11, TyRedOf(s.BorderColor));
    AssertEquals('width', 1, s.BorderWidth);
  finally m.Free; end;
end;

procedure TTestStyleBorderRadius.TestBorderRadiusSingleValueUniform;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('T { border-radius: 6px; }');
    s := m.ResolveStyle('T', '', []);
    AssertTrue('present', tpBorderRadius in s.Present);
    AssertEquals('uniform border-radius', 6, s.BorderRadius);
    AssertEquals('corner tl', 6, s.Radius.TL);
    AssertEquals('corner tr', 6, s.Radius.TR);
    AssertEquals('corner br', 6, s.Radius.BR);
    AssertEquals('corner bl', 6, s.Radius.BL);
  finally m.Free; end;
end;

procedure TTestStyleBorderRadius.TestBorderRadiusFourValuesTopOnly;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('T { border-radius: 6px 6px 0 0; }');
    s := m.ResolveStyle('T', '', []);
    AssertEquals('tl', 6, s.Radius.TL);
    AssertEquals('tr', 6, s.Radius.TR);
    AssertEquals('br', 0, s.Radius.BR);
    AssertEquals('bl', 0, s.Radius.BL);
  finally m.Free; end;
end;

procedure TTestStyleBorderRadius.TestBorderRadiusFourValuesWithVar;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss(':root{--r:8px;} T { border-radius: var(--r) var(--r) 0 0; }');
    s := m.ResolveStyle('T', '', []);
    AssertEquals('tl from var', 8, s.Radius.TL);
    AssertEquals('br', 0, s.Radius.BR);
  finally m.Free; end;
end;

procedure TTestStyleOutline.TestOutlineParsed;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('T:focus { outline: 2px #FF0000; }');
    s := m.ResolveStyle('T', '', [tysFocused]);
    AssertTrue('outline present on focus', tpOutline in s.Present);
    AssertEquals('outline width', 2, s.OutlineWidth);
    AssertEquals('outline color r', $FF, TyRedOf(s.OutlineColor));
  finally m.Free; end;
end;

procedure TTestStyleOutline.TestOutlineAbsentWhenNotFocused;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('T:focus { outline: 2px #FF0000; }');
    s := m.ResolveStyle('T', '', []);   // no focus state
    AssertFalse('outline absent without focus', tpOutline in s.Present);
  finally m.Free; end;
end;

procedure TTestStyleOutline.TestOutlineOffsetParsed;
var m: TTyStyleModel; s: TTyStyleSet;
begin
  m := TTyStyleModel.Create;
  try
    m.LoadFromCss('T:focus { outline: 2px #FF0000; outline-offset: 3px; }');
    s := m.ResolveStyle('T', '', [tysFocused]);
    AssertEquals('outline offset', 3, s.OutlineOffset);
  finally m.Free; end;
end;

procedure TTestStylePhase0.SetUp;
begin
  FModel := TTyStyleModel.Create;
end;

procedure TTestStylePhase0.TearDown;
begin
  FModel.Free;
end;

procedure TTestStylePhase0.TestBackgroundNoneKeyword;
var st: TTyStyleSet;
begin
  FModel.LoadFromCss('TyPanel { background: none; }');
  st := FModel.ResolveStyle('TyPanel', '', []);
  AssertTrue('tpBackground present', tpBackground in st.Present);
  AssertTrue('Kind = tfkNone', st.Background.Kind = tfkNone);
end;

procedure TTestStylePhase0.TestSeedOverrideReachesBaseRule;
var st: TTyStyleSet;
begin
  // thin user theme overriding ONLY --accent, with no TyButton rule. The built-in
  // base TyButton.primary = var(--accent) must pick up the MERGED seed (red).
  // Eager bake gives the built-in accent (#3B82F6); merge-then-resolve gives red.
  FModel.LoadFromCss(':root { --accent: #FF0000; }');
  st := FModel.ResolveStyle('TyButton', 'primary', []);
  AssertTrue('background present', tpBackground in st.Present);
  AssertEquals('base primary picks up merged seed = red',
    TTyColor($FFFF0000), st.Background.Color);
end;

procedure TTestStylePhase0.TestBaseResolveUnchanged;
var st, ed: TTyStyleSet;
begin
  // No user theme: the built-in base resolves to its own seeds (baseline guard,
  // passes both before and after the refactor).
  st := FModel.ResolveStyle('TyButton', 'primary', []);
  AssertEquals('base primary = built-in accent', TTyColor($FF3B82F6), st.Background.Color);
  ed := FModel.ResolveStyle('TyEdit', '', [tysFocused]);
  AssertTrue('focus outline present', tpOutline in ed.Present);
end;

procedure TTestStylePhase0.TestAdditiveLoad;
var st: TTyStyleSet;
begin
  // additive load composes: the override's color wins, the base background SURVIVES
  // (per-property merge across the two appended entries via apply-all-forward).
  FModel.LoadFromCss('TyButton { background: #111111; color: #222222; }');
  FModel.LoadFromCssAdditive('TyButton { color: #FF0000; }');
  st := FModel.ResolveStyle('TyButton', '', []);
  AssertEquals('additive override color wins', TTyColor($FFFF0000), st.TextColor);
  AssertTrue('additive base background survives', tpBackground in st.Present);
  AssertEquals('additive base background value', TTyColor($FF111111), st.Background.Color);
end;

initialization
  RegisterTest(TTestStyleMerge);
  RegisterTest(TTestStylePhase0);
  RegisterTest(TTestStyleLoad);
  RegisterTest(TTestStylePropertyCascade);
  RegisterTest(TTestStyleImport);
  RegisterTest(TTestStyleOverride);
  RegisterTest(TTestStyleResolve);
  RegisterTest(TTestStyleShadow);
  RegisterTest(TTestStylePadding);
  RegisterTest(TTestStyleBorderStyle);
  RegisterTest(TTestStyleBorderShorthand);
  RegisterTest(TTestStyleBorderRadius);
  RegisterTest(TTestStyleOutline);
end.
