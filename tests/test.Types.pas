unit test.Types;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, fpcunit, testregistry, Graphics, tyControls.Types;

type
  TTestTypes = class(TTestCase)
  published
    procedure TestTyRGB;
    procedure TestTyRGBA;
    procedure TestTyAlphaOf;
    procedure TestTyChannelOf;
    procedure TestTransparentConst;
    procedure TestEmptyStyleSet;
    procedure TestColorToLCL;
    procedure TestUniformCornersAllEqual;
    procedure TestEffectiveCornersFromRadiusField;
    procedure TestEffectiveCornersFallsBackToUniformBorderRadius;
    procedure TestClampRadius;
    procedure TestSpacingConstants;
  end;

implementation

procedure TTestTypes.TestTyRGB;
begin
  AssertEquals('opaque red', TTyColor($FFFF0000), TyRGB(255, 0, 0));
  AssertEquals('opaque green', TTyColor($FF00FF00), TyRGB(0, 255, 0));
end;

procedure TTestTypes.TestTyRGBA;
begin
  AssertEquals('half-alpha blue', TTyColor($800000FF), TyRGBA(0, 0, 255, $80));
end;

procedure TTestTypes.TestTyAlphaOf;
begin
  AssertEquals('alpha byte', Byte($80), TyAlphaOf(TTyColor($80112233)));
end;

procedure TTestTypes.TestTyChannelOf;
begin
  AssertEquals('red', Byte($11), TyRedOf(TTyColor($FF112233)));
  AssertEquals('green', Byte($22), TyGreenOf(TTyColor($FF112233)));
  AssertEquals('blue', Byte($33), TyBlueOf(TTyColor($FF112233)));
end;

procedure TTestTypes.TestTransparentConst;
begin
  AssertEquals('transparent', TTyColor($00000000), tyTransparent);
end;

procedure TTestTypes.TestEmptyStyleSet;
var
  s: TTyStyleSet;
begin
  s := EmptyStyleSet;
  AssertTrue('present empty', s.Present = []);
  AssertEquals('opacity default', Single(1.0), s.Opacity, 0.0001);
  AssertTrue('bg none', s.Background.Kind = tfkNone);
end;

procedure TTestTypes.TestColorToLCL;
begin
  AssertEquals('TyColorToLCL drops alpha, maps RGB',
    Integer(RGBToColor($11, $22, $33)), Integer(TyColorToLCL(TTyColor($FF112233))));
end;

procedure TTestTypes.TestUniformCornersAllEqual;
var c: TTyCorners;
begin
  c := TyUniformCorners(6);
  AssertEquals('tl', 6, c.TL);
  AssertEquals('tr', 6, c.TR);
  AssertEquals('br', 6, c.BR);
  AssertEquals('bl', 6, c.BL);
end;

procedure TTestTypes.TestEffectiveCornersFromRadiusField;
var s: TTyStyleSet; c: TTyCorners;
begin
  s := EmptyStyleSet;
  s.Radius := TyCorners(6, 6, 0, 0);
  c := TyEffectiveCorners(s);
  AssertEquals('tl', 6, c.TL);
  AssertEquals('bl', 0, c.BL);
end;

procedure TTestTypes.TestEffectiveCornersFallsBackToUniformBorderRadius;
{ Styles built in CODE (e.g. ToggleSwitch track) set only BorderRadius and leave
  Radius all-zero. TyEffectiveCorners must then derive uniform corners from it. }
var s: TTyStyleSet; c: TTyCorners;
begin
  s := EmptyStyleSet;
  s.BorderRadius := 12;          // Radius stays (0,0,0,0)
  c := TyEffectiveCorners(s);
  AssertEquals('tl', 12, c.TL);
  AssertEquals('tr', 12, c.TR);
  AssertEquals('br', 12, c.BR);
  AssertEquals('bl', 12, c.BL);
end;

procedure TTestTypes.TestClampRadius;
{ TyClampRadius caps a token border-radius at the sub-element's half-side so a
  smaller theme radius wins but the geometry can never exceed a perfect circle.
  Default-circle cases (radio 8/8, toggle 12/9) must return the half unchanged,
  guaranteeing zero pixel change under the default theme. }
begin
  AssertEquals('default radio circle: 8 capped at half 8', 8, TyClampRadius(8, 8));
  AssertEquals('default toggle circle: token 12 capped at half 9', 9, TyClampRadius(12, 9));
  AssertEquals('small theme radius wins', 2, TyClampRadius(2, 8));
  AssertEquals('oversize token capped at half', 8, TyClampRadius(20, 8));
  AssertEquals('negative result floored to 0', 0, TyClampRadius(-3, 8));
end;

procedure TTestTypes.TestSpacingConstants;
{ Guards the shared spacing/size constants against silent drift after the
  duplicated-literal dedupe. Values MUST match the original hard-coded literals
  (zero behavior change). }
begin
  AssertEquals(18, TyFieldButtonWidth);
  AssertEquals(12, TyScrollbarSize);
  AssertEquals(16, TyCheckBoxBox);
  AssertEquals(6,  TyCheckBoxGap);
  AssertEquals(14, TyTabCloseSize);
  AssertEquals(48, TyTabMinWidth);
  AssertEquals(16, TyTabArrowBand);
  AssertEquals(12, TyTabPad);
  AssertEquals(6,  TyTabGap);
  AssertEquals(6,  TyTabMargin);
  AssertEquals(8,  TyTitleBarPad);
  AssertEquals(46, TyTitleButtonWidth);
end;

initialization
  RegisterTest(TTestTypes);
end.
