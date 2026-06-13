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
    procedure TestLoadFromCssParseErrorPreservesPrevious;
    procedure TestDuplicateRuleLastWins;
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

initialization
  RegisterTest(TTestStyleMerge);
  RegisterTest(TTestStyleLoad);
  RegisterTest(TTestStyleResolve);
  RegisterTest(TTestStyleShadow);
  RegisterTest(TTestStylePadding);
end.
