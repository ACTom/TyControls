unit test.advchart.scale.break;
{$mode objfpc}{$H+}
{ CONTRACT 2 ACCEPTANCE (Tier 0 spec §8 item 5).

  The point of these tests is not that breaks work — it is that they were added
  WITHOUT touching TTyIntervalScale, TTyLinearScaleMapper or TTyLogScaleMapper,
  and without changing a single assertion in test.advchart.scale. If a future
  change to breaks forces an edit in those files, the decorator design has failed
  and the retrofit cost this spike was run to avoid has arrived anyway.

  [Revised in batch 132: the decorator now carries upstream's model -- a gap
  in data units or a percent of the linear span, worked out when the
  effective extent is set, and no expanded state (an expanded break is not
  parsed). A percent gap still comes out as that share of the axis, so the
  assertions below kept their numbers; the expanded test became `no break is
  the inner mapper`. The interval scale learned the nice step on the span
  the breaks leave and the steps over a break (upstream's own code in
  Interval.ts), which is batch 132's and not this contract's.] }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Scale;
type
  TAdvChartBreakTest = class(TTestCase)
  private
    function LinearWithBreak: ITyScaleMapper;
    function MkBrk(AMin, AMax: Double; AKind: TTyBreakGapKind; AVal: Double): TTyAxisBreak;
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

function TAdvChartBreakTest.MkBrk(AMin, AMax: Double; AKind: TTyBreakGapKind;
  AVal: Double): TTyAxisBreak;
begin
  Result := Default(TTyAxisBreak);
  Result.VMin := AMin;
  Result.VMax := AMax;
  Result.GapKind := AKind;
  Result.GapVal := AVal;
  Result.Id := FloatToStr(AMin) + '_'#0'_' + FloatToStr(AMax);
end;

function TAdvChartBreakTest.LinearWithBreak: ITyScaleMapper;
begin
  { Collapse 20..80 — 60 % of the axis — down to 5 % of the visual span. }
  Result := TTyBreakScaleMapper.Create(TTyLinearScaleMapper.Create,
    [MkBrk(20, 80, bgkPrct, 0.05)]);
  Result.SetExtent(sekEffective, TyRange(0, 100));
end;

procedure TAdvChartBreakTest.TestNoBreaksIsIdenticalToInner;
var inner, brk: ITyScaleMapper; i: Integer; v: Double;
begin
  inner := TTyLinearScaleMapper.Create;
  inner.SetExtent(sekEffective, TyRange(0, 100));
  brk := TTyBreakScaleMapper.Create(TTyLinearScaleMapper.Create, nil);
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
var m: ITyScaleMapper;
begin
  m := TTyBreakScaleMapper.Create(TTyLinearScaleMapper.Create,
    [MkBrk(10, 30, bgkPrct, 0.02), MkBrk(60, 90, bgkPrct, 0.02)]);
  m.SetExtent(sekEffective, TyRange(0, 100));
  AssertEquals('start', 0.0, m.Normalize(0), Eps);
  AssertEquals('stop', 1.0, m.Normalize(100), Eps);
  AssertEquals('first gap', 0.02, m.Normalize(30) - m.Normalize(10), Eps);
  AssertEquals('second gap', 0.02, m.Normalize(90) - m.Normalize(60), Eps);
end;

procedure TAdvChartBreakTest.TestBreakOnLogInnerMapper;
var inner: ITyScaleMapper; m: ITyScaleMapper;
begin
  { Breaks compose with ANY inner mapper — that is the whole point of the
    TransformIn/TransformOut chain. On a log axis the break collapses a decade. }
  inner := TTyLogScaleMapper.Create(10);
  m := TTyBreakScaleMapper.Create(inner, [MkBrk(10, 100, bgkPrct, 0.05)]);
  m.SetExtent(sekEffective, TyRange(1, 10000));
  AssertEquals('start', 0.0, m.Normalize(1), Eps);
  AssertEquals('stop', 1.0, m.Normalize(10000), Eps);
  AssertEquals('one collapsed decade', 0.05, m.Normalize(100) - m.Normalize(10), Eps);
end;

procedure TAdvChartBreakTest.TestScaleAcceptsBreakDecoratorWithoutKnowingIt;
var s: TTyIntervalScale; ticks: TTyScaleTickArray; i: Integer;
begin
  s := TTyIntervalScale.Create;
  try
    s.Mapper := TTyBreakScaleMapper.Create(s.Mapper, [MkBrk(20, 80, bgkPrct, 0.05)]);
    s.SetExtent(TyRange(0, 100));
    s.Niceify(5);
    { TTyIntervalScale contains no reference to breaks whatsoever, yet: }
    AssertEquals('collapsed', 0.05, s.Normalize(80) - s.Normalize(20), Eps);
    ticks := s.GetTicks;
    AssertTrue('ticks still generate', Length(ticks) >= 3);
    { [Batch 33] And they are still VALUES, in order and inside the extent.
      The step walked the decorator's collapsed space as if it were a log
      axis' decades for a while: 0, 20, 97.89, 117.89, 137.89, 100. }
    for i := 1 to High(ticks) do
      AssertTrue(Format('tick %d follows tick %d', [i, i - 1]),
        ticks[i].Value > ticks[i - 1].Value);
    AssertTrue('the first is the extent''s start', ticks[0].Value >= 0);
    AssertTrue('the last is inside it', ticks[High(ticks)].Value <= 100);
  finally
    s.Free;
  end;
end;

procedure TAdvChartBreakTest.TestExpandedBreakBehavesLikeNoBreak;
var m: ITyScaleMapper;
begin
  { A break the user clicked open must map exactly as if it were absent —
    otherwise the expand animation would not land where the expanded axis draws.
    [Batch 132] Upstream does not parse an expanded break at all: the
    decorator is handed none, and maps as its inner mapper does. }
  m := TTyBreakScaleMapper.Create(TTyLinearScaleMapper.Create, nil);
  m.SetExtent(sekEffective, TyRange(0, 100));
  AssertEquals('expanded midpoint', 0.5, m.Normalize(50), Eps);
  AssertEquals('expanded quarter', 0.2, m.Normalize(20), Eps);
end;

initialization
  RegisterTest(TAdvChartBreakTest);
end.
