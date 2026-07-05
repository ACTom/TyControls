unit test.rating;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, tyControls.Rating;
type
  TRatingTest = class(TTestCase)
  published
    procedure TestWholeStarsAcrossStrip;
    procedure TestLeftEdgeFirstStar;
    procedure TestRightEdgeClampsToCount;
    procedure TestHalfSteps;
    procedure TestPastRightClamps;
    procedure TestNegativeXFloorsToFirst;
    procedure TestDegenerate;
  end;
implementation

const
  W = 100;    // 100-px strip, 5 cells of 20 px each
  N = 5;

procedure TRatingTest.TestWholeStarsAcrossStrip;
begin
  // A click inside cell i (0-based) selects star i+1 in whole-star mode.
  AssertEquals('cell 0 -> 1', 1.0, TyRatingValueFromX(10, W, N, False), 1e-9);
  AssertEquals('cell 1 -> 2', 2.0, TyRatingValueFromX(30, W, N, False), 1e-9);
  AssertEquals('cell 2 -> 3', 3.0, TyRatingValueFromX(50, W, N, False), 1e-9);
  AssertEquals('cell 4 -> 5', 5.0, TyRatingValueFromX(90, W, N, False), 1e-9);
end;

procedure TRatingTest.TestLeftEdgeFirstStar;
begin
  // The very left edge (x=0) already selects the first whole star, never 0.
  AssertEquals('x=0 -> 1', 1.0, TyRatingValueFromX(0, W, N, False), 1e-9);
  // In half mode the left edge selects the first half step.
  AssertEquals('x=0 half -> 0.5', 0.5, TyRatingValueFromX(0, W, N, True), 1e-9);
end;

procedure TRatingTest.TestRightEdgeClampsToCount;
begin
  // The right edge maps to the last star (whole and half modes).
  AssertEquals('x=W -> N', 5.0, TyRatingValueFromX(W, W, N, False), 1e-9);
  AssertEquals('x=W half -> N', 5.0, TyRatingValueFromX(W, W, N, True), 1e-9);
end;

procedure TRatingTest.TestHalfSteps;
begin
  // With half steps: left half of a cell -> x.5, right half -> whole star.
  // Cell 2 spans x in [40,60): 40..49 -> 2.5, 50..59 -> 3.0.
  AssertEquals('left half of cell 2 -> 2.5', 2.5, TyRatingValueFromX(45, W, N, True), 1e-9);
  AssertEquals('right half of cell 2 -> 3.0', 3.0, TyRatingValueFromX(55, W, N, True), 1e-9);
  // A whole-step request on the same x rounds up to the whole star.
  AssertEquals('cell 2 whole -> 3', 3.0, TyRatingValueFromX(45, W, N, False), 1e-9);
end;

procedure TRatingTest.TestPastRightClamps;
begin
  // A position past the strip clamps to Count (no read past the range).
  AssertEquals('past right whole', 5.0, TyRatingValueFromX(999, W, N, False), 1e-9);
  AssertEquals('past right half', 5.0, TyRatingValueFromX(999, W, N, True), 1e-9);
end;

procedure TRatingTest.TestNegativeXFloorsToFirst;
begin
  // A negative x (shouldn't happen from a real click, but be safe) -> first step.
  AssertEquals('neg x whole -> 1', 1.0, TyRatingValueFromX(-20, W, N, False), 1e-9);
  AssertEquals('neg x half -> 0.5', 0.5, TyRatingValueFromX(-20, W, N, True), 1e-9);
end;

procedure TRatingTest.TestDegenerate;
begin
  // Zero/negative count or width -> 0 (no div by zero, no crash).
  AssertEquals('zero count', 0.0, TyRatingValueFromX(10, W, 0, False), 1e-9);
  AssertEquals('zero width', 0.0, TyRatingValueFromX(10, 0, N, False), 1e-9);
  AssertEquals('negative width', 0.0, TyRatingValueFromX(10, -5, N, True), 1e-9);
end;

initialization
  RegisterTest(TRatingTest);
end.
