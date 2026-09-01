unit test.advchart.types;
{$mode objfpc}{$H+}
{ Headless tests for the AdvChart geometry primitives. Everything here is pure
  arithmetic on records — no control, no handle, no painter. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, tyControls.AdvChart.Types;
type
  TAdvChartTypesTest = class(TTestCase)
  published
    procedure TestRangeNormalisesReversedInput;
    procedure TestRangeSpanIsNonNegative;
    procedure TestRangeContainsBothEnds;
    procedure TestRectFWidthHeight;
    procedure TestRectFContainsIsHalfOpen;
    procedure TestInvalidPointIsNaN;
    procedure TestInvalidRectIsNotValid;
    procedure TestValidRectIsValid;
    procedure TestRectWithNaNIsNotValid;
  end;
implementation

procedure TAdvChartTypesTest.TestRangeNormalisesReversedInput;
var r: TTyRange;
begin
  r := TyRange(10, 2);
  AssertEquals('start', 2.0, r.Start, 1e-12);
  AssertEquals('stop', 10.0, r.Stop, 1e-12);
end;

procedure TAdvChartTypesTest.TestRangeSpanIsNonNegative;
begin
  AssertEquals('reversed span', 8.0, TyRangeSpan(TyRange(10, 2)), 1e-12);
  AssertEquals('degenerate span', 0.0, TyRangeSpan(TyRange(5, 5)), 1e-12);
end;

procedure TAdvChartTypesTest.TestRangeContainsBothEnds;
var r: TTyRange;
begin
  r := TyRange(2, 10);
  AssertTrue('low end', TyRangeContains(r, 2));
  AssertTrue('high end', TyRangeContains(r, 10));
  AssertTrue('middle', TyRangeContains(r, 6));
  AssertFalse('below', TyRangeContains(r, 1.999));
  AssertFalse('above', TyRangeContains(r, 10.001));
end;

procedure TAdvChartTypesTest.TestRectFWidthHeight;
var r: TTyRectF;
begin
  r := TyRectF(10, 20, 110, 70);
  AssertEquals('width', 100.0, TyRectFWidth(r), 1e-12);
  AssertEquals('height', 50.0, TyRectFHeight(r), 1e-12);
end;

procedure TAdvChartTypesTest.TestRectFContainsIsHalfOpen;
var r: TTyRectF;
begin
  r := TyRectF(0, 0, 10, 10);
  AssertTrue('top-left corner is in', TyRectFContains(r, TyPointF(0, 0)));
  AssertTrue('inside', TyRectFContains(r, TyPointF(5, 5)));
  { Half-open on the far edges so adjacent bands never both claim a pixel --
    the rule the datum hit-test relies on when bars sit shoulder to shoulder. }
  AssertFalse('right edge is out', TyRectFContains(r, TyPointF(10, 5)));
  AssertFalse('bottom edge is out', TyRectFContains(r, TyPointF(5, 10)));
end;

procedure TAdvChartTypesTest.TestInvalidPointIsNaN;
var p: TTyPointF;
begin
  p := TyInvalidPointF;
  AssertTrue('x is NaN', IsNan(p.X));
  AssertTrue('y is NaN', IsNan(p.Y));
end;

procedure TAdvChartTypesTest.TestInvalidRectIsNotValid;
begin
  AssertFalse('invalid rect', TyRectFIsValid(TyInvalidRectF));
end;

procedure TAdvChartTypesTest.TestValidRectIsValid;
begin
  AssertTrue('ordinary rect', TyRectFIsValid(TyRectF(0, 0, 10, 10)));
  AssertTrue('zero-area rect is still valid', TyRectFIsValid(TyRectF(5, 5, 5, 5)));
  AssertFalse('reversed rect is not valid', TyRectFIsValid(TyRectF(10, 0, 0, 10)));
end;

procedure TAdvChartTypesTest.TestRectWithNaNIsNotValid;
var r: TTyRectF;
begin
  r := TyRectF(0, 0, 10, 10);
  r.Right := NaN;
  AssertFalse('NaN edge', TyRectFIsValid(r));
end;

initialization
  RegisterTest(TAdvChartTypesTest);
end.
