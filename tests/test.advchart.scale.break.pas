unit test.advchart.scale.break;
{$mode objfpc}{$H+}
{ CONTRACT 2 ACCEPTANCE (Tier 0 spec §8 item 5).

  The point of these tests is not that breaks work — it is that they were added
  WITHOUT touching TTyIntervalScale, TTyLinearScaleMapper or TTyLogScaleMapper,
  and without changing a single assertion in test.advchart.scale. If a future
  change to breaks forces an edit in those files, the decorator design has failed
  and the retrofit cost this spike was run to avoid has arrived anyway. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry,
     tyControls.AdvChart.Types, tyControls.AdvChart.Scale;
type
  TAdvChartBreakTest = class(TTestCase)
  private
    function LinearWithBreak: ITyScaleMapper;
  published
    procedure TestNoBreaksIsIdenticalToInner;
    procedure TestBreakCollapsesItsRange;
    procedure TestOutsideBreakIsStillMonotonic;
    procedure TestEndsStillNormalizeToZeroAndOne;
    procedure TestRoundTripOutsideBreak;
    procedure TestValueInsideBreakLandsInTheGap;
    procedure TestTwoBreaksAccumulate;
    procedure TestBreakOnLogInnerMapper;
    procedure TestScaleAcceptsBreakDecoratorWithoutKnowingIt;
    procedure TestExpandedBreakBehavesLikeNoBreak;
  end;
implementation

const
  Eps = 1e-9;

function TAdvChartBreakTest.LinearWithBreak: ITyScaleMapper;
var
  inner: ITyScaleMapper;
  brk: TTyBreakScaleMapper;
begin
  inner := TTyLinearScaleMapper.Create;
  inner.SetExtent(sekEffective, TyRange(0, 100));
  brk := TTyBreakScaleMapper.Create(inner);
  { Collapse 20..80 — 60 % of the axis — down to 5 % of the visual span. }
  brk.AddBreak(TyRange(20, 80), 0.05);
  Result := brk;
end;

procedure TAdvChartBreakTest.TestNoBreaksIsIdenticalToInner;
var inner, brk: ITyScaleMapper; i: Integer; v: Double;
begin
  inner := TTyLinearScaleMapper.Create;
  inner.SetExtent(sekEffective, TyRange(0, 100));
  brk := TTyBreakScaleMapper.Create(TTyLinearScaleMapper.Create);
  brk.SetExtent(sekEffective, TyRange(0, 100));
  for i := 0 to 20 do
  begin
    v := i * 5;
    AssertEquals('a break-free decorator is transparent at ' + FloatToStr(v),
                 inner.Normalize(v), brk.Normalize(v), Eps);
  end;
end;

procedure TAdvChartBreakTest.TestBreakCollapsesItsRange;
var m: ITyScaleMapper; lo, hi: Double;
begin
  m := LinearWithBreak;
  lo := m.Normalize(20);
  hi := m.Normalize(80);
  { 60 real units now occupy 5 % of the axis. }
  AssertEquals('collapsed span', 0.05, hi - lo, Eps);
end;

procedure TAdvChartBreakTest.TestOutsideBreakIsStillMonotonic;
var m: ITyScaleMapper; i: Integer; prev, cur: Double;
begin
  m := LinearWithBreak;
  prev := -1;
  for i := 0 to 100 do
  begin
    cur := m.Normalize(i);
    AssertTrue('monotonic at ' + IntToStr(i), cur >= prev - Eps);
    prev := cur;
  end;
end;

procedure TAdvChartBreakTest.TestEndsStillNormalizeToZeroAndOne;
var m: ITyScaleMapper;
begin
  m := LinearWithBreak;
  AssertEquals('start', 0.0, m.Normalize(0), Eps);
  AssertEquals('stop', 1.0, m.Normalize(100), Eps);
end;

procedure TAdvChartBreakTest.TestRoundTripOutsideBreak;
var m: ITyScaleMapper; i: Integer; v: Double;
begin
  m := LinearWithBreak;
  for i := 0 to 19 do
  begin
    v := i;
    AssertEquals('low side round trip', v, m.Denormalize(m.Normalize(v)), 1e-7);
  end;
  for i := 81 to 100 do
  begin
    v := i;
    AssertEquals('high side round trip', v, m.Denormalize(m.Normalize(v)), 1e-7);
  end;
end;

procedure TAdvChartBreakTest.TestValueInsideBreakLandsInTheGap;
var m: ITyScaleMapper; n: Double;
begin
  m := LinearWithBreak;
  n := m.Normalize(50);
  AssertTrue('inside the gap, above its start', n >= m.Normalize(20) - Eps);
  AssertTrue('inside the gap, below its end', n <= m.Normalize(80) + Eps);
end;

procedure TAdvChartBreakTest.TestTwoBreaksAccumulate;
var inner: ITyScaleMapper; brk: TTyBreakScaleMapper; m: ITyScaleMapper;
begin
  inner := TTyLinearScaleMapper.Create;
  inner.SetExtent(sekEffective, TyRange(0, 100));
  brk := TTyBreakScaleMapper.Create(inner);
  brk.AddBreak(TyRange(10, 30), 0.02);
  brk.AddBreak(TyRange(60, 90), 0.02);
  m := brk;
  AssertEquals('start', 0.0, m.Normalize(0), Eps);
  AssertEquals('stop', 1.0, m.Normalize(100), Eps);
  AssertEquals('first gap', 0.02, m.Normalize(30) - m.Normalize(10), Eps);
  AssertEquals('second gap', 0.02, m.Normalize(90) - m.Normalize(60), Eps);
end;

procedure TAdvChartBreakTest.TestBreakOnLogInnerMapper;
var inner: ITyScaleMapper; brk: TTyBreakScaleMapper; m: ITyScaleMapper;
begin
  { Breaks compose with ANY inner mapper — that is the whole point of the
    TransformIn/TransformOut chain. On a log axis the break collapses a decade. }
  inner := TTyLogScaleMapper.Create(10);
  inner.SetExtent(sekEffective, TyRange(1, 10000));
  brk := TTyBreakScaleMapper.Create(inner);
  brk.AddBreak(TyRange(10, 100), 0.05);
  m := brk;
  AssertEquals('start', 0.0, m.Normalize(1), Eps);
  AssertEquals('stop', 1.0, m.Normalize(10000), Eps);
  AssertEquals('one collapsed decade', 0.05, m.Normalize(100) - m.Normalize(10), Eps);
end;

procedure TAdvChartBreakTest.TestScaleAcceptsBreakDecoratorWithoutKnowingIt;
var s: TTyIntervalScale; brk: TTyBreakScaleMapper;
begin
  s := TTyIntervalScale.Create;
  try
    s.SetExtent(TyRange(0, 100));
    s.Niceify(5);
    brk := TTyBreakScaleMapper.Create(s.Mapper);
    brk.AddBreak(TyRange(20, 80), 0.05);
    s.Mapper := brk;
    { TTyIntervalScale contains no reference to breaks whatsoever, yet: }
    AssertEquals('collapsed', 0.05, s.Normalize(80) - s.Normalize(20), Eps);
    AssertTrue('ticks still generate', Length(s.GetTicks) >= 3);
  finally
    s.Free;
  end;
end;

procedure TAdvChartBreakTest.TestExpandedBreakBehavesLikeNoBreak;
var inner: ITyScaleMapper; brk: TTyBreakScaleMapper; m: ITyScaleMapper;
begin
  { A break the user clicked open must map exactly as if it were absent —
    otherwise the expand animation would not land where the expanded axis draws. }
  inner := TTyLinearScaleMapper.Create;
  inner.SetExtent(sekEffective, TyRange(0, 100));
  brk := TTyBreakScaleMapper.Create(inner);
  brk.AddBreak(TyRange(20, 80), 0.05);
  brk.SetBreakExpanded(0, True);
  m := brk;
  AssertEquals('expanded midpoint', 0.5, m.Normalize(50), Eps);
  AssertEquals('expanded quarter', 0.2, m.Normalize(20), Eps);
end;

initialization
  RegisterTest(TAdvChartBreakTest);
end.
