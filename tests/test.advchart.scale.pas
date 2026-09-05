unit test.advchart.scale;
{$mode objfpc}{$H+}
{ Headless tests for the scale mapper chain and the two-kind extent.

  These tests must keep passing UNCHANGED after the break decorator lands in
  test.advchart.scale.break — that is the acceptance criterion for contract 2
  (Tier 0 spec §8 item 5). If a break change ever forces an edit in this file,
  the decorator design has failed. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry,
     tyControls.AdvChart.Types, tyControls.AdvChart.Scale;
type
  TAdvChartMapperTest = class(TTestCase)
  published
    procedure TestLinearNormalizeEnds;
    procedure TestLinearNormalizeMidpoint;
    procedure TestLinearRoundTrip;
    procedure TestLinearDegenerateExtentIsHalf;
    procedure TestLinearNeedsNoTransform;
    procedure TestLogNormalizeEnds;
    procedure TestLogNormalizeIsLogarithmic;
    procedure TestLogRoundTrip;
    procedure TestLogNeedsTransform;
    procedure TestContainRespectsEffectiveExtent;
    procedure TestMappingExtentAbsentByDefault;
    procedure TestMappingExtentDrivesNormalize;
    procedure TestEffectiveExtentStillDrivesContain;
  end;

  TAdvChartIntervalScaleTest = class(TTestCase)
  private
    function StepMantissaIsNice(AStep: Double): Boolean;
  published
    procedure TestNiceContainsData;
    procedure TestNiceStepMantissa;
    procedure TestNiceTickCountNearSplitNumber;
    procedure TestNiceFlatExtentDoesNotDivide;
    procedure TestTicksAreAscendingAndUnique;
    procedure TestFixedMinIsRespected;
    procedure TestStartValueIsIndependentOfMin;
    procedure TestScaleUsesItsMapper;
    procedure TestMinorTicksAreOffUntilAskedFor;
    procedure TestALogAxisNicesInLogSpace;
    procedure TestALogAxisMapsItsDataAcrossTheWholeAxis;
    procedure TestALogAxisSurvivesAnImpossibleLowEnd;
  end;

implementation

const
  Eps = 1e-9;

{ ---------------------- TAdvChartMapperTest ---------------------- }

procedure TAdvChartMapperTest.TestLinearNormalizeEnds;
var m: ITyScaleMapper;
begin
  m := TTyLinearScaleMapper.Create;
  m.SetExtent(sekEffective, TyRange(0, 100));
  AssertEquals('start', 0.0, m.Normalize(0), Eps);
  AssertEquals('stop', 1.0, m.Normalize(100), Eps);
end;

procedure TAdvChartMapperTest.TestLinearNormalizeMidpoint;
var m: ITyScaleMapper;
begin
  m := TTyLinearScaleMapper.Create;
  m.SetExtent(sekEffective, TyRange(-50, 50));
  AssertEquals('midpoint', 0.5, m.Normalize(0), Eps);
end;

procedure TAdvChartMapperTest.TestLinearRoundTrip;
var m: ITyScaleMapper; i: Integer; v: Double;
begin
  m := TTyLinearScaleMapper.Create;
  m.SetExtent(sekEffective, TyRange(-13.5, 987.25));
  for i := 0 to 20 do
  begin
    v := -13.5 + (987.25 + 13.5) * i / 20;
    AssertEquals('round trip', v, m.Denormalize(m.Normalize(v)), 1e-9);
  end;
end;

procedure TAdvChartMapperTest.TestLinearDegenerateExtentIsHalf;
var m: ITyScaleMapper;
begin
  m := TTyLinearScaleMapper.Create;
  m.SetExtent(sekEffective, TyRange(7, 7));
  { A zero span must not divide. 0.5 (the band centre) is the only answer that
    keeps a single-datum chart drawing in the middle instead of at an edge. }
  AssertEquals('degenerate', 0.5, m.Normalize(7), Eps);
  AssertEquals('degenerate off-value', 0.5, m.Normalize(99), Eps);
end;

procedure TAdvChartMapperTest.TestLinearNeedsNoTransform;
var m: ITyScaleMapper;
begin
  m := TTyLinearScaleMapper.Create;
  AssertFalse('linear is identity', m.NeedTransform);
end;

procedure TAdvChartMapperTest.TestLogNormalizeEnds;
var m: ITyScaleMapper;
begin
  m := TTyLogScaleMapper.Create(10);
  m.SetExtent(sekEffective, TyRange(1, 1000));
  AssertEquals('start', 0.0, m.Normalize(1), Eps);
  AssertEquals('stop', 1.0, m.Normalize(1000), Eps);
end;

procedure TAdvChartMapperTest.TestLogNormalizeIsLogarithmic;
var m: ITyScaleMapper;
begin
  m := TTyLogScaleMapper.Create(10);
  m.SetExtent(sekEffective, TyRange(1, 1000));
  { 10 is one decade of three -> exactly a third of the way along. }
  AssertEquals('one decade', 1/3, m.Normalize(10), 1e-9);
  AssertEquals('two decades', 2/3, m.Normalize(100), 1e-9);
end;

procedure TAdvChartMapperTest.TestLogRoundTrip;
var m: ITyScaleMapper; i: Integer; v: Double;
begin
  m := TTyLogScaleMapper.Create(10);
  m.SetExtent(sekEffective, TyRange(0.5, 5000));
  for i := 0 to 20 do
  begin
    v := 0.5 * Power(10000, i / 20);
    AssertEquals('round trip', v, m.Denormalize(m.Normalize(v)), Abs(v) * 1e-9 + 1e-12);
  end;
end;

procedure TAdvChartMapperTest.TestLogNeedsTransform;
var m: ITyScaleMapper;
begin
  m := TTyLogScaleMapper.Create(10);
  AssertTrue('log is not identity', m.NeedTransform);
end;

procedure TAdvChartMapperTest.TestContainRespectsEffectiveExtent;
var m: ITyScaleMapper;
begin
  m := TTyLinearScaleMapper.Create;
  m.SetExtent(sekEffective, TyRange(0, 10));
  AssertTrue('inside', m.Contain(5));
  AssertTrue('on the low end', m.Contain(0));
  AssertTrue('on the high end', m.Contain(10));
  AssertFalse('outside', m.Contain(10.5));
end;

procedure TAdvChartMapperTest.TestMappingExtentAbsentByDefault;
var m: ITyScaleMapper;
begin
  m := TTyLinearScaleMapper.Create;
  m.SetExtent(sekEffective, TyRange(0, 10));
  AssertFalse('no mapping extent yet', m.HasExtent(sekMapping));
end;

procedure TAdvChartMapperTest.TestMappingExtentDrivesNormalize;
var m: ITyScaleMapper;
begin
  m := TTyLinearScaleMapper.Create;
  m.SetExtent(sekEffective, TyRange(0, 10));
  { containShape: widen the MAPPING extent so a bar at value 10 keeps its half
    width inside the plot band. Normalize must follow the wider one... }
  m.SetExtent(sekMapping, TyRange(-1, 11));
  AssertTrue('mapping extent present', m.HasExtent(sekMapping));
  AssertEquals('0 is no longer at the start', 1/12, m.Normalize(0), Eps);
  AssertEquals('10 is no longer at the stop', 11/12, m.Normalize(10), Eps);
end;

procedure TAdvChartMapperTest.TestEffectiveExtentStillDrivesContain;
var m: ITyScaleMapper;
begin
  m := TTyLinearScaleMapper.Create;
  m.SetExtent(sekEffective, TyRange(0, 10));
  m.SetExtent(sekMapping, TyRange(-1, 11));
  { ...but ticks, labels, splitLines and hit-testing stay on the EFFECTIVE
    extent, or a widened axis grows phantom ticks at -1 and 11. }
  AssertFalse('below effective', m.Contain(-0.5));
  AssertFalse('above effective', m.Contain(10.5));
  AssertTrue('effective end', m.Contain(10));
end;

{ ---------------------- TAdvChartIntervalScaleTest ---------------------- }

function TAdvChartIntervalScaleTest.StepMantissaIsNice(AStep: Double): Boolean;
var m: Double;
begin
  if AStep <= 0 then Exit(False);
  m := AStep / Power(10, Floor(Log10(AStep)));
  Result := (Abs(m - 1) < 1e-9) or (Abs(m - 2) < 1e-9)
         or (Abs(m - 2.5) < 1e-9) or (Abs(m - 5) < 1e-9);
end;

procedure TAdvChartIntervalScaleTest.TestNiceContainsData;
var s: TTyIntervalScale; e: TTyRange;
begin
  s := TTyIntervalScale.Create;
  try
    s.SetExtent(TyRange(3.7, 91.2));
    s.Niceify(5);
    e := s.GetExtent;
    AssertTrue('nice min <= data min', e.Start <= 3.7 + 1e-9);
    AssertTrue('nice max >= data max', e.Stop >= 91.2 - 1e-9);
  finally
    s.Free;
  end;
end;

procedure TAdvChartIntervalScaleTest.TestNiceStepMantissa;
var s: TTyIntervalScale; i: Integer;
begin
  for i := 1 to 40 do
  begin
    s := TTyIntervalScale.Create;
    try
      s.SetExtent(TyRange(0, i * 3.3));
      s.Niceify(5);
      AssertTrue('step mantissa for i=' + IntToStr(i) + ' step=' + FloatToStr(s.Interval),
                 StepMantissaIsNice(s.Interval));
    finally
      s.Free;
    end;
  end;
end;

procedure TAdvChartIntervalScaleTest.TestNiceTickCountNearSplitNumber;
var s: TTyIntervalScale; n: Integer;
begin
  s := TTyIntervalScale.Create;
  try
    s.SetExtent(TyRange(0, 100));
    s.Niceify(5);
    n := Length(s.GetTicks);
    { A "nice" range trades exactness for round numbers, so the count is
      approximate by design -- but it must stay in a band a reader would call
      five-ish, not collapse to 2 or explode to 20. }
    AssertTrue('tick count ' + IntToStr(n) + ' is in [3,9]', (n >= 3) and (n <= 9));
  finally
    s.Free;
  end;
end;

procedure TAdvChartIntervalScaleTest.TestNiceFlatExtentDoesNotDivide;
var s: TTyIntervalScale; e: TTyRange;
begin
  s := TTyIntervalScale.Create;
  try
    s.SetExtent(TyRange(42, 42));
    s.Niceify(5);
    e := s.GetExtent;
    AssertTrue('flat extent was expanded', TyRangeSpan(e) > 0);
    AssertTrue('interval is positive', s.Interval > 0);
    AssertTrue('the value is still inside', TyRangeContains(e, 42));
  finally
    s.Free;
  end;
end;

procedure TAdvChartIntervalScaleTest.TestTicksAreAscendingAndUnique;
var s: TTyIntervalScale; t: TTyScaleTickArray; i: Integer;
begin
  s := TTyIntervalScale.Create;
  try
    s.SetExtent(TyRange(-17.3, 4.9));
    s.Niceify(6);
    t := s.GetTicks;
    AssertTrue('at least two ticks', Length(t) >= 2);
    for i := 1 to High(t) do
      AssertTrue('strictly ascending at ' + IntToStr(i), t[i].Value > t[i - 1].Value);
  finally
    s.Free;
  end;
end;

procedure TAdvChartIntervalScaleTest.TestFixedMinIsRespected;
var s: TTyIntervalScale;
begin
  s := TTyIntervalScale.Create;
  try
    s.SetExtent(TyRange(3.7, 91.2));
    s.FixMin := True;
    s.Niceify(5);
    AssertEquals('a pinned min is not rounded away', 3.7, s.GetExtent.Start, 1e-9);
  finally
    s.Free;
  end;
end;

procedure TAdvChartIntervalScaleTest.TestStartValueIsIndependentOfMin;
var s: TTyIntervalScale;
begin
  { ECharts 6.1 decoupled startValue from min (break B7). Build the extent model
    with them independent from day one, or the scale gets reworked later. }
  s := TTyIntervalScale.Create;
  try
    s.SetExtent(TyRange(0, 100));
    s.StartValue := 20;
    AssertEquals('extent start is untouched', 0.0, s.GetExtent.Start, 1e-12);
    AssertEquals('startValue stands on its own', 20.0, s.StartValue, 1e-12);
    AssertTrue('and it is flagged as set', s.HasStartValue);
  finally
    s.Free;
  end;
end;

procedure TAdvChartIntervalScaleTest.TestScaleUsesItsMapper;
var s: TTyIntervalScale;
begin
  { The scale must go THROUGH its mapper, never normalise itself -- this is what
    lets the break decorator be swapped in without touching it. }
  s := TTyIntervalScale.Create;
  try
    s.SetExtent(TyRange(0, 100));
    AssertEquals('midpoint via mapper', 0.5, s.Normalize(50), 1e-12);
    s.Mapper := TTyLogScaleMapper.Create(10);
    s.SetExtent(TyRange(1, 1000));
    AssertEquals('one decade after the swap', 1/3, s.Normalize(10), 1e-9);
  finally
    s.Free;
  end;
end;

procedure TAdvChartIntervalScaleTest.TestMinorTicksAreOffUntilAskedFor;
var
  sc: TTyIntervalScale;
  t: TTyScaleTickArray;
  i, majors, minors: Integer;
begin
  sc := TTyIntervalScale.Create;
  try
    sc.SetExtent(TyRange(0, 4));
    sc.Niceify(4);
    t := sc.GetTicks;
    for i := 0 to High(t) do
      AssertEquals('nothing is minor until minorTick is asked for', 0, t[i].Level);

    { LEVEL 1 HAD NEVER BEEN WRITTEN BY ANY GENERATOR, though the record's own
      comment has documented it since the scale was written and two theme keys
      have been waiting for it since item 18. }
    sc.MinorSplitNumber := 5;
    t := sc.GetTicks;
    majors := 0;
    minors := 0;
    for i := 0 to High(t) do
      if t[i].Level = 0 then Inc(majors) else Inc(minors);
    AssertTrue('the majors are unchanged', majors >= 2);
    { Four minor ticks in each gap between majors, and NONE after the last one:
      a minor tick belongs to the interval before the next major, and after the
      last major there is no next. }
    AssertEquals('four per gap, no tail', (majors - 1) * 4, minors);

    { One array, in value order. Two arrays would let the two drift out of
      order, and the order is what a renderer walks. }
    for i := 1 to High(t) do
      AssertTrue('ticks are ordered', t[i].Value > t[i - 1].Value);
  finally
    sc.Free;
  end;
end;

{ ============ a log axis ============ }

function LogScale(ALo, AHi: Double; ASplit: Integer = 5): TTyIntervalScale;
begin
  Result := TTyIntervalScale.Create;
  Result.Mapper := TTyLogScaleMapper.Create(10);
  Result.SetExtent(TyRange(ALo, AHi));
  Result.Niceify(ASplit);
end;

procedure TAdvChartIntervalScaleTest.TestALogAxisNicesInLogSpace;
var
  sc: TTyIntervalScale;
  e: TTyRange;
  ticks: TTyScaleTickArray;
  i, majors: Integer;
begin
  { A log axis is TTyIntervalScale carrying a log mapper, and Niceify used to
    work in RAW VALUE space: the step came out bigger than the low end, so
    Floor(start/step)*step drove the low end to 0 -- which TransformIn turns
    into NaN. 1..10000 nicied to [0, 10000] with ticks 0/2000/4000/6000/8000,
    linear numbers on a logarithmic axis. }
  sc := LogScale(1, 10000);
  try
    e := sc.GetExtent;
    AssertEquals('the low end is not floored to zero', 1.0, e.Start, 1e-9);
    AssertEquals('and the top is a power of the base', 10000.0, e.Stop, 1e-6);

    ticks := sc.GetTicks;
    majors := 0;
    for i := 0 to High(ticks) do
      if ticks[i].Level = 0 then Inc(majors);
    AssertEquals('one major per decade: 1, 10, 100, 1000, 10000', 5, majors);

    majors := 0;
    for i := 0 to High(ticks) do
      if ticks[i].Level = 0 then
      begin
        Inc(majors);
        AssertEquals(Format('decade %d', [majors]),
          Power(10.0, majors - 1), ticks[i].Value, ticks[i].Value * 1e-9 + 1e-9);
      end;
  finally
    sc.Free;
  end;
end;

procedure TAdvChartIntervalScaleTest.TestALogAxisMapsItsDataAcrossTheWholeAxis;
var
  sc: TTyIntervalScale;
begin
  { The symptom the arithmetic produced: once either end of the extent
    transformed to NaN, Normalize returned 0.5 for EVERYTHING, so every datum
    and every tick sat on the exact middle of the plot. Where floating-point
    exceptions are unmasked it raised EInvalidOp out of the paint path instead.

    Asserting the ENDS as well as the middle is deliberate: a mapper stuck on
    0.5 satisfies any single check at the centre. }
  sc := LogScale(1, 10000);
  try
    AssertEquals('the bottom of the axis', 0.0, sc.Normalize(1), 1e-9);
    AssertEquals('the top', 1.0, sc.Normalize(10000), 1e-9);
    AssertEquals('and 100 sits halfway, because it is halfway in DECADES',
      0.5, sc.Normalize(100), 1e-9);
    AssertEquals('10 is a quarter up', 0.25, sc.Normalize(10), 1e-9);
    AssertEquals('1000 is three quarters', 0.75, sc.Normalize(1000), 1e-9);
  finally
    sc.Free;
  end;
end;

procedure TAdvChartIntervalScaleTest.TestALogAxisSurvivesAnImpossibleLowEnd;
var
  sc: TTyIntervalScale;
  e: TTyRange;
begin
  { `min: 0` on a log axis asks for something that does not exist. Leaving it
    as NaN is what broke the whole mapper, so the low end is pulled up to one
    decade below the top instead -- an axis that is drawable and honest about
    its range, rather than one that silently reports 0.5 everywhere. }
  sc := TTyIntervalScale.Create;
  try
    sc.Mapper := TTyLogScaleMapper.Create(10);
    sc.SetExtent(TyRange(0, 1000));
    sc.Niceify(5);
    e := sc.GetExtent;
    AssertTrue('the low end is positive', e.Start > 0);
    AssertFalse('and nothing is NaN', IsNan(e.Start) or IsNan(e.Stop));
    AssertFalse('the mapper answers a real number',
      IsNan(sc.Normalize(e.Stop)));
    AssertTrue('and the two ends do not map to the same place',
      Abs(sc.Normalize(e.Stop) - sc.Normalize(e.Start)) > 0.5);
  finally
    sc.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartMapperTest);
  RegisterTest(TAdvChartIntervalScaleTest);
end.
