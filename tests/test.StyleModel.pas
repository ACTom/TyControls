unit test.StyleModel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, tyControls.Types, tyControls.StyleModel;
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

initialization
  RegisterTest(TTestStyleMerge);
  RegisterTest(TTestStyleLoad);
end.
