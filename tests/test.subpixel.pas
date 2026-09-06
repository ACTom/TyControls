unit test.subpixel;
{$mode objfpc}{$H+}
{ Sub-pixel alignment. Pure arithmetic, so every assertion is an exact number.

  The invariant every case below really tests is one thing: after snapping,
  (coordinate + width/2) is a whole number. That is what makes a thin stroke
  cover one row of pixels fully instead of two rows at half alpha. The pixels
  themselves are checked in test.advchart.render. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, tyControls.SubPixel;
type
  TSubPixelTest = class(TTestCase)
  private
    { The property the whole unit exists for. }
    procedure AssertEdgeIsWhole(const AMsg: string; APos, AWidth: Double);
  published
    procedure TestOddWidthWantsAHalfInteger;
    procedure TestEvenWidthWantsAnInteger;
    procedure TestAlreadyAlignedIsLeftAlone;
    procedure TestZeroWidthChangesNothing;
    procedure TestNegativeWidthChangesNothing;
    procedure TestNaNPositionSurvives;
    procedure TestDirectionDecidesWhichWayItMoves;
    procedure TestEdgeIsWholeAcrossManyPositionsAndWidths;
    procedure TestVerticalLineSnapsOnlyX;
    procedure TestHorizontalLineSnapsOnlyY;
    procedure TestDiagonalLineIsLeftAlone;
    procedure TestRectSnapsAllFourEdges;
    procedure TestRectBiasesInwardSoItDoesNotCreep;
    procedure TestThinRectKeepsAtLeastOnePixel;
    procedure TestEmptyRectStaysEmpty;
  end;
implementation

const
  Eps = 1e-9;

procedure TSubPixelTest.AssertEdgeIsWhole(const AMsg: string; APos, AWidth: Double);
var
  snapped, edge: Double;
begin
  snapped := TySubPixelSnap(APos, AWidth);
  edge := snapped + AWidth / 2;
  AssertEquals(AMsg + ' (pos=' + FloatToStr(APos) + ' w=' + FloatToStr(AWidth)
               + ' -> ' + FloatToStr(snapped) + ', edge=' + FloatToStr(edge) + ')',
               0.0, Abs(edge - Round(edge)), 1e-9);
end;

procedure TSubPixelTest.TestOddWidthWantsAHalfInteger;
begin
  { A 1 px stroke centred at 10 covers half of row 9 and half of row 10. Centred
    at 10.5 it covers row 10 completely. }
  AssertEquals('1 px at 10', 10.5, TySubPixelSnap(10, 1), Eps);
  AssertEquals('3 px at 10', 10.5, TySubPixelSnap(10, 3), Eps);
end;

procedure TSubPixelTest.TestEvenWidthWantsAnInteger;
begin
  { Both 10 and 11 are integers and both put the outer edge on a whole pixel;
    which one you get is the direction argument's job, and the default nudges
    towards positive. Asserting 10 here was the test being wrong about the
    default, not the snap being wrong about the parity. }
  AssertEquals('2 px at 10.5, default direction', 11.0, TySubPixelSnap(10.5, 2), Eps);
  AssertEquals('...and the other way', 10.0, TySubPixelSnap(10.5, 2, False), Eps);
  AssertEquals('2 px at 10 is already right', 10.0, TySubPixelSnap(10, 2), Eps);
end;

procedure TSubPixelTest.TestAlreadyAlignedIsLeftAlone;
begin
  { Snapping must be idempotent, or a value that goes through layout twice
    walks half a pixel per pass. }
  AssertEquals('1 px at 10.5', 10.5, TySubPixelSnap(10.5, 1), Eps);
  AssertEquals('and again', 10.5, TySubPixelSnap(TySubPixelSnap(10.5, 1), 1), Eps);
end;

procedure TSubPixelTest.TestZeroWidthChangesNothing;
begin
  { Nothing is being stroked, so there is no edge to align. }
  AssertEquals('untouched', 10.37, TySubPixelSnap(10.37, 0), Eps);
end;

procedure TSubPixelTest.TestNegativeWidthChangesNothing;
begin
  AssertEquals('untouched', 10.37, TySubPixelSnap(10.37, -2), Eps);
end;

procedure TSubPixelTest.TestNaNPositionSurvives;
begin
  { NaN is the no-data sentinel. Rounding it would turn "no value" into a real
    coordinate, and the datum would silently appear at the origin. }
  AssertTrue('still NaN', IsNan(TySubPixelSnap(NaN, 1)));
end;

procedure TSubPixelTest.TestDirectionDecidesWhichWayItMoves;
begin
  { Both land on a valid half-integer; which one is the caller's choice, and it
    is what lets a rect bias inward instead of creeping outward. }
  AssertEquals('towards positive', 10.5, TySubPixelSnap(10.2, 1, True), Eps);
  AssertEquals('towards negative', 9.5, TySubPixelSnap(10.2, 1, False), Eps);
end;

procedure TSubPixelTest.TestEdgeIsWholeAcrossManyPositionsAndWidths;
var
  i, w: Integer;
begin
  { The invariant, swept. Individual expected values above are readable; this is
    the one that would catch a parity slip at some width nobody thought to try. }
  for w := 1 to 6 do
    for i := 0 to 40 do
      AssertEdgeIsWhole('outer edge lands whole', i * 0.25, w);
end;

procedure TSubPixelTest.TestVerticalLineSnapsOnlyX;
var x1, y1, x2, y2: Double;
begin
  x1 := 10; y1 := 5; x2 := 10; y2 := 95;
  TySubPixelLine(x1, y1, x2, y2, 1);
  AssertEquals('x snapped', 10.5, x1, Eps);
  AssertEquals('and both ends agree', x1, x2, Eps);
  AssertEquals('y1 left alone', 5.0, y1, Eps);
  AssertEquals('y2 left alone', 95.0, y2, Eps);
end;

procedure TSubPixelTest.TestHorizontalLineSnapsOnlyY;
var x1, y1, x2, y2: Double;
begin
  x1 := 5; y1 := 20; x2 := 95; y2 := 20;
  TySubPixelLine(x1, y1, x2, y2, 1);
  AssertEquals('y snapped', 20.5, y1, Eps);
  AssertEquals('and both ends agree', y1, y2, Eps);
  AssertEquals('x1 left alone', 5.0, x1, Eps);
  AssertEquals('x2 left alone', 95.0, x2, Eps);
end;

procedure TSubPixelTest.TestDiagonalLineIsLeftAlone;
var x1, y1, x2, y2: Double;
begin
  { Moving either end of a diagonal changes its angle, and a diagonal is not the
    case that looks fuzzy in the first place. }
  x1 := 5; y1 := 5; x2 := 95; y2 := 60;
  TySubPixelLine(x1, y1, x2, y2, 1);
  AssertEquals('x1', 5.0, x1, Eps);
  AssertEquals('y1', 5.0, y1, Eps);
  AssertEquals('x2', 95.0, x2, Eps);
  AssertEquals('y2', 60.0, y2, Eps);
end;

procedure TSubPixelTest.TestRectSnapsAllFourEdges;
var l, t, r, b: Double;
begin
  l := 10; t := 20; r := 60; b := 70;
  TySubPixelRect(l, t, r, b, 1);
  AssertEquals('left', 10.5, l, Eps);
  AssertEquals('top', 20.5, t, Eps);
  AssertEquals('right', 59.5, r, Eps);
  AssertEquals('bottom', 69.5, b, Eps);
end;

procedure TSubPixelTest.TestRectBiasesInwardSoItDoesNotCreep;
var l, t, r, b, w0, w1, w2: Double;
begin
  { Snapping outward on both edges would grow the rect by a pixel every time it
    passed through layout. Inward, it converges. }
  l := 10; t := 20; r := 60; b := 70;
  w0 := r - l;
  TySubPixelRect(l, t, r, b, 1);
  w1 := r - l;
  TySubPixelRect(l, t, r, b, 1);
  w2 := r - l;
  AssertTrue('did not grow', w1 <= w0);
  AssertEquals('and a second pass is a no-op', w1, w2, Eps);
end;

procedure TSubPixelTest.TestThinRectKeepsAtLeastOnePixel;
var l, t, r, b: Double;
begin
  { A 0.4 px bar is a real datum with a tiny value. Snapping it away to nothing
    would make it disappear from the chart entirely, which is worse than drawing
    it one pixel fat. }
  l := 10; t := 20; r := 10.4; b := 70;
  TySubPixelRect(l, t, r, b, 1);
  AssertTrue('at least a pixel wide, got ' + FloatToStr(r - l), r - l >= 1 - Eps);
end;

procedure TSubPixelTest.TestEmptyRectStaysEmpty;
var l, t, r, b: Double;
begin
  { Zero is different from tiny. A genuinely empty rect means "nothing here" and
    must not be inflated into a stray mark. }
  l := 10; t := 20; r := 10; b := 70;
  TySubPixelRect(l, t, r, b, 1);
  AssertEquals('still empty', 0.0, r - l, Eps);
  { And specifically NOT inverted. The two edges snap in opposite directions, so
    the natural result of a zero-width rect is -1 -- which survives a later
    Min/Max swap and reappears as a phantom band somewhere else. }
  AssertTrue('and not inverted', r >= l);
end;

initialization
  RegisterTest(TSubPixelTest);
end.
