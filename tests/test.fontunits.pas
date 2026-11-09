unit test.fontunits;
{$mode objfpc}{$H+}
{ tyControls.FontUnits: a font size in pixels carried in the Integer every text
  routine takes. The unit is core, so its tests are too -- they lived inside
  the chart's suites until the chart left the repository (the 14 px size is
  the one test.advchart.labels pinned, the 12 px one the size the chart's
  label specs are built from). Every expected value below is written out
  from the encoding's definition -- cTyFontPxBase plus hundredths of a pixel,
  a point size times 96/72 -- not read back from the functions. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, tyControls.FontUnits;
type
  TFontUnitsTest = class(TTestCase)
  published
    procedure TestTheBaseIsOneMillion;
    procedure TestAPixelSizeIsTheBasePlusHundredths;
    procedure TestNoSizeStaysNoSize;
    procedure TestATinySizeIsStillASize;
    procedure TestAHugeSizeIsCapped;
    procedure TestTheBaseItselfIsAPointSize;
    procedure TestPointsAreOnlyPointsBelowTheBase;
    procedure TestAPointSizeIsNinetySixSeventyTwoths;
    procedure TestAPixelSizeComesBackAsItWasGiven;
    procedure TestEverySizeDrawnStaysPositive;
  end;

implementation

procedure TFontUnitsTest.TestTheBaseIsOneMillion;
begin
  AssertEquals(1000000, cTyFontPxBase);
end;

procedure TFontUnitsTest.TestAPixelSizeIsTheBasePlusHundredths;
begin
  AssertEquals('14 px', 1001400, TyFontSizeFromPx(14));
  AssertEquals('12 px', 1001200, TyFontSizeFromPx(12));
  AssertEquals('10.5 px, which no whole point holds', 1001050, TyFontSizeFromPx(10.5));
  AssertEquals('a hundredth rounds to the nearest', 1001235, TyFontSizeFromPx(12.346));
  AssertTrue('it is a pixel size', TyFontSizeIsPx(TyFontSizeFromPx(14)));
end;

procedure TFontUnitsTest.TestNoSizeStaysNoSize;
begin
  AssertEquals('zero', 0, TyFontSizeFromPx(0));
  AssertEquals('negative', 0, TyFontSizeFromPx(-3));
  AssertEquals('NaN', 0, TyFontSizeFromPx(NaN));
  AssertFalse('and 0 is not a pixel size', TyFontSizeIsPx(0));
end;

procedure TFontUnitsTest.TestATinySizeIsStillASize;
var s: Integer;
begin
  { 0.004 px rounds to no hundredth at all, and would be the bare base: a
    point size. It is bumped to the first pixel size there is }
  s := TyFontSizeFromPx(0.004);
  AssertEquals(cTyFontPxBase + 1, s);
  AssertTrue('a pixel size', TyFontSizeIsPx(s));
  AssertTrue('drawn: positive', s > 0);
  AssertEquals('0.01 px', 0.01, TyFontPxOf(s), 1e-12);
end;

procedure TFontUnitsTest.TestAHugeSizeIsCapped;
begin
  AssertEquals('ten thousand px is the last size', 2000000, TyFontSizeFromPx(10000));
  AssertEquals('and every size past it is that one', 2000000, TyFontSizeFromPx(10001));
  AssertEquals('Integer overflow is no way out', 2000000, TyFontSizeFromPx(1e12));
  AssertEquals(2000000, TyFontSizeFromPx(Infinity));
  AssertEquals(10000.0, TyFontPxOf(TyFontSizeFromPx(1e12)), 1e-9);
end;

procedure TFontUnitsTest.TestTheBaseItselfIsAPointSize;
begin
  AssertFalse('the base', TyFontSizeIsPx(cTyFontPxBase));
  AssertTrue('one past it', TyFontSizeIsPx(cTyFontPxBase + 1));
  AssertEquals('read as points', cTyFontPxBase * 96 / 72, TyFontPxOf(cTyFontPxBase), 1e-6);
end;

procedure TFontUnitsTest.TestPointsAreOnlyPointsBelowTheBase;
begin
  AssertFalse('0', TyFontSizeIsPx(0));
  AssertFalse('10 pt', TyFontSizeIsPx(10));
  AssertFalse('a theme''s largest', TyFontSizeIsPx(999999));
  AssertFalse('negative (the caller''s "unset")', TyFontSizeIsPx(-1));
end;

procedure TFontUnitsTest.TestAPointSizeIsNinetySixSeventyTwoths;
begin
  AssertEquals('9 pt', 12.0, TyFontPxOf(9), 1e-12);
  AssertEquals('12 pt', 16.0, TyFontPxOf(12), 1e-12);
  AssertEquals('10 pt', 13.333333333333334, TyFontPxOf(10), 1e-9);
  AssertEquals('nothing is substituted for 0', 0.0, TyFontPxOf(0), 1e-12);
end;

procedure TFontUnitsTest.TestAPixelSizeComesBackAsItWasGiven;
begin
  AssertEquals('14 px', 14.0, TyFontPxOf(1001400), 1e-9);
  AssertEquals('14 px through the encoder', 14.0, TyFontPxOf(TyFontSizeFromPx(14)), 1e-9);
  AssertEquals('10.5 px', 10.5, TyFontPxOf(TyFontSizeFromPx(10.5)), 1e-9);
  AssertEquals('12.34 px', 12.34, TyFontPxOf(1001234), 1e-9);
  AssertEquals('12 px is not 12 pt', 12.0, TyFontPxOf(1001200), 1e-9);
end;

procedure TFontUnitsTest.TestEverySizeDrawnStaysPositive;
var
  px: Double;
  i: Integer;
begin
  { "size > 0 means drawn" has to hold for every pixel size the encoder hands out }
  for i := 1 to 400 do
  begin
    px := i / 8;
    AssertTrue(FloatToStr(px), TyFontSizeFromPx(px) > 0);
  end;
end;

initialization
  RegisterTest(TFontUnitsTest);
end.
