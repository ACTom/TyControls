unit test.colormath;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Graphics, fpcunit, testregistry, tyControls.Types, tyControls.Css.Values, tyControls.ColorMath;
type
  TColorMathTest = class(TTestCase)
  private
    procedure AssertChan(const AMsg: string; AExpected, AActual: Byte; ATol: Integer);
  published
    procedure TestHSVAnchorsExact;
    procedure TestHSVRoundTripSpread;
    procedure TestCMYKRoundTrip;
    procedure TestHexRoundTrip;
    procedure TestColorFromLCLSystemColor;
    procedure TestAreaAndHueMaps;
  end;
implementation

procedure TColorMathTest.AssertChan(const AMsg: string; AExpected, AActual: Byte; ATol: Integer);
begin
  AssertTrue(AMsg + Format(' exp=%d act=%d tol=%d', [AExpected, AActual, ATol]),
    Abs(Integer(AExpected) - Integer(AActual)) <= ATol);
end;

procedure TColorMathTest.TestHSVAnchorsExact;
var h,s,v: Single; c: TTyColor;
begin
  TyRGBToHSV(TyRGB(255,0,0), h,s,v);
  AssertEquals('red H', 0.0, h, 0.5); AssertEquals('red S', 1.0, s, 0.001); AssertEquals('red V', 1.0, v, 0.001);
  c := TyHSVToRGB(0, 1, 1);
  AssertEquals('red r', 255, TyRedOf(c)); AssertEquals('red g', 0, TyGreenOf(c)); AssertEquals('red b', 0, TyBlueOf(c));
  c := TyHSVToRGB(120, 1, 1); AssertEquals('grn', Integer(TyRGB(0,255,0)) and $FFFFFF, Integer(c) and $FFFFFF);
  c := TyHSVToRGB(240, 1, 1); AssertEquals('blu', Integer(TyRGB(0,0,255)) and $FFFFFF, Integer(c) and $FFFFFF);
  c := TyHSVToRGB(0, 0, 1); AssertEquals('white', $FFFFFF, Integer(c) and $FFFFFF);
  c := TyHSVToRGB(0, 0, 0); AssertEquals('black', $000000, Integer(c) and $FFFFFF);
end;

procedure TColorMathTest.TestHSVRoundTripSpread;
var i: Integer; c, c2: TTyColor; h,s,v: Single;
const SAMPLES: array[0..5] of TTyColor = ($FF3399CC, $FF808080, $FF12A4E7, $FFDE2A5B, $FF7F00FF, $FF00C864);
begin
  for i := 0 to High(SAMPLES) do
  begin
    c := SAMPLES[i];
    TyRGBToHSV(c, h, s, v);
    c2 := TyHSVToRGB(h, s, v);
    AssertChan('r', TyRedOf(c), TyRedOf(c2), 1);
    AssertChan('g', TyGreenOf(c), TyGreenOf(c2), 1);
    AssertChan('b', TyBlueOf(c), TyBlueOf(c2), 1);
  end;
end;

procedure TColorMathTest.TestCMYKRoundTrip;
var cc,mm,yy,kk: Single; c, c2: TTyColor;
begin
  c := TyRGB(31,122,224);
  TyRGBToCMYK(c, cc,mm,yy,kk);
  c2 := TyCMYKToRGB(cc,mm,yy,kk);
  AssertChan('r', 31, TyRedOf(c2), 1); AssertChan('g', 122, TyGreenOf(c2), 1); AssertChan('b', 224, TyBlueOf(c2), 1);
  TyRGBToCMYK(TyRGB(0,0,0), cc,mm,yy,kk);
  AssertEquals('K=1', 1.0, kk, 0.001); AssertEquals('C0', 0.0, cc, 0.001);
end;

procedure TColorMathTest.TestHexRoundTrip;
begin
  AssertEquals('rgb', '#3399cc', LowerCase(TyColorToHex(TyRGB($33,$99,$CC), False)));
  AssertEquals('rgba->color', Integer(TyRGBA($33,$99,$CC,$80)),
    Integer(TyParseColor(TyColorToHex(TyRGBA($33,$99,$CC,$80), True))));
end;

procedure TColorMathTest.TestColorFromLCLSystemColor;
var c: TTyColor;
begin
  c := TyColorFromLCL(clWindowText, 255);
  AssertEquals('alpha', 255, TyAlphaOf(c));
  AssertEquals('rt', Integer(clRed), Integer(TyColorToLCL(TyColorFromLCL(clRed, 255))));
end;

procedure TColorMathTest.TestAreaAndHueMaps;
var sv: TPointF; r: TRect;
begin
  r := Rect(0,0,100,100);
  sv := TyHSVAreaToSV(Point(0,0), r);     AssertEquals('S@topleft',0.0,sv.X,0.001); AssertEquals('V@topleft',1.0,sv.Y,0.001);
  sv := TyHSVAreaToSV(Point(100,100), r); AssertEquals('S@botright',1.0,sv.X,0.001); AssertEquals('V@botright',0.0,sv.Y,0.001);
  AssertEquals('hue top', 0.0, TyHueBarToH(0, r), 0.5);
  AssertEquals('hue bottom', 360.0, TyHueBarToH(100, r), 0.5);
end;

initialization
  RegisterTest(TColorMathTest);
end.
