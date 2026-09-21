unit test.advchart.valueaxis;
{$mode objfpc}{$H+}
{ A value axis' extent, step and ticks, held to upstream's own output.

  tools/advchart-oracle/value-axis.js runs the real ECharts 6.1 build over the
  cases in tests/fixtures/advchart-value-axis.json -- a scatter (or a bar) on
  yAxis[0], with every option that moves the axis -- and records the extent it
  settled on, the step, every tick, every minor tick, and whether the axis
  was turned round. The first test puts each case through the control and
  compares EXACTLY: every one of those numbers is a short decimal rounded the
  way upstream rounds it, and a port that rounds the same way lands on the
  same Double. A log axis too -- its decades come back through the powers of
  ten V8 itself answers, which FPC's Power does not (1e-10 was eight units in
  the last place away). The one case upstream's development build asserts on
  was recorded from its production build, and the fixture says which. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types,
     tyControls.AdvChart.Scale, tyControls.AdvChart.Coord,
     tyControls.AdvChart.Builder,
     tyControls.AdvanceChart, test.advancechart;
type
  TAdvChartValueAxisOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TChartProbe;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryCaseMatchesUpstream;
  end;

  TAdvChartNiceNumberTest = class(TTestCase)
  published
    procedure TestTheNiceLadderIsUpstreams;
    procedure TestToFixedRoundsTheWayJavaScriptDoes;
    procedure TestPrecisionCountsTheDecimals;
    procedure TestTheSplitNumberIsRoundedAndDefaulted;
    procedure TestJsRoundIsHalfUpAndDoesNotWrap;
    procedure TestTheLogMapperGivesTheEnginesPowers;
  end;

implementation

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-value-axis.json';
end;

procedure TAdvChartValueAxisOracleTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TChartProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
end;

procedure TAdvChartValueAxisOracleTest.TearDown;
begin
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartValueAxisOracleTest.TestEveryCaseMatchesUpstream;
var
  sl: TStringList;
  root: TJSONData;
  cases, arr, grp: TJSONArray;
  cs: TJSONObject;
  c, i, j, k, compared, bad, nMaj, nMin: Integer;
  bmp: TBGRABitmap;
  ax: TTyAxis;
  e: TTyRange;
  ticks: TTyScaleTickArray;
  majors, minors: array of Double;
  report: string;

  procedure Miss(const AWhat: string);
  begin
    Inc(bad);
    if bad <= 16 then
      report := report + LineEnding + '  ' + cs.Strings['name'] + ': ' + AWhat;
  end;

  function Same(AWant, AGot: Double): Boolean;
  begin
    if IsNan(AGot) then Exit(False);
    Result := AWant = AGot;
  end;

  { Seventeen digits: two Doubles a unit in the last place apart print the
    same at fifteen, and a miss would read "3 upstream, 3 here". }
  function G(AValue: Double): string;
  begin
    Result := FloatToStrF(AValue, ffGeneral, 17, 0);
  end;

  function Show(const AValues: array of Double): string;
  var k: Integer;
  begin
    Result := '';
    for k := 0 to Min(High(AValues), 9) do
      Result := Result + G(AValues[k]) + ' ';
    if Length(AValues) > 10 then Result := Result + '...';
  end;

begin
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  root := nil;
  bmp := TBGRABitmap.Create(600, 400, BGRA(255, 255, 255, 255));
  try
    sl.LoadFromFile(FixturePath);
    root := GetJSON(sl.Text);
    cases := TJSONObject(root).Arrays['cases'];
    AssertTrue('the fixture carries its cases', cases.Count >= 400);
    compared := 0;
    bad := 0;
    report := '';
    for c := 0 to cases.Count - 1 do
    begin
      cs := cases.Objects[c];
      FChart.Option := cs.Objects['option'].AsJSON;
      AssertEquals(cs.Strings['name'] + ' parses', '', FChart.OptionError);
      FChart.SetBounds(0, 0, 600, 400);
      FChart.Render(bmp.Canvas, Rect(0, 0, 600, 400), 96);
      if cs.Strings['axis'] = 'x' then
        ax := FChart.Build.Grid(0).XAxis(0)
      else
        ax := FChart.Build.Grid(0).YAxis(0);
      e := ax.Scale.GetExtent;
      arr := cs.Arrays['extent'];
      Inc(compared, 2);
      if not (Same(arr.Floats[0], e.Start) and Same(arr.Floats[1], e.Stop)) then
        Miss(Format('extent [%s, %s] upstream, [%s, %s] here',
          [G(arr.Floats[0]), G(arr.Floats[1]), G(e.Start), G(e.Stop)]));
      { A time axis has no one step: upstream records none, and this one's
        Interval is not read. }
      Inc(compared);
      if (ax.Scale is TTyIntervalScale) and not (ax.Scale is TTyTimeScale)
        and (cs.Find('interval') <> nil)
        and (cs.Find('interval').JSONType = jtNumber)
        and (cs.Floats['interval'] <> TTyIntervalScale(ax.Scale).Interval) then
        Miss(Format('step %s upstream, %s here', [G(cs.Floats['interval']),
          G(TTyIntervalScale(ax.Scale).Interval)]));
      Inc(compared);
      if cs.Booleans['inverse'] <> ax.Inverse then
        Miss(Format('inverse is %s upstream', [BoolToStr(cs.Booleans['inverse'], True)]));
      { Blank: nothing to go on, so labels, ticks and split lines are not
        drawn -- though the ticks below still exist, as upstream's do. }
      Inc(compared);
      if cs.Booleans['blank'] <> ax.Scale.Blank then
        Miss(Format('blank is %s upstream', [BoolToStr(cs.Booleans['blank'], True)]));

      ticks := ax.Scale.GetTicks;
      nMaj := 0;
      nMin := 0;
      SetLength(majors, Length(ticks));
      SetLength(minors, Length(ticks));
      for i := 0 to High(ticks) do
        if ticks[i].Level = 0 then
        begin
          majors[nMaj] := ticks[i].Value;
          Inc(nMaj);
        end
        else
        begin
          minors[nMin] := ticks[i].Value;
          Inc(nMin);
        end;
      SetLength(majors, nMaj);
      SetLength(minors, nMin);
      arr := cs.Arrays['ticks'];
      Inc(compared);
      if arr.Count <> nMaj then
        Miss(Format('%d ticks upstream, %d here: %s', [arr.Count, nMaj, Show(majors)]))
      else
        for i := 0 to arr.Count - 1 do
        begin
          Inc(compared);
          if not Same(arr.Floats[i], majors[i]) then
          begin
            Miss(Format('tick %d is %s upstream, %s here',
              [i, G(arr.Floats[i]), G(majors[i])]));
            Break;
          end;
        end;

      if cs.Find('minor').JSONType = jtArray then
      begin
        { upstream groups its minors by gap; this port lists them in one
          array between the majors. The values, in order, are the claim. }
        j := 0;
        grp := cs.Arrays['minor'];
        Inc(compared);
        for i := 0 to grp.Count - 1 do
          Inc(j, TJSONArray(grp.Items[i]).Count);
        if j <> nMin then
          Miss(Format('%d minor ticks upstream, %d here: %s', [j, nMin, Show(minors)]))
        else
        begin
          j := 0;
          for i := 0 to grp.Count - 1 do
            for k := 0 to TJSONArray(grp.Items[i]).Count - 1 do
            begin
              Inc(compared);
              if not Same(TJSONArray(grp.Items[i]).Floats[k], minors[j]) then
                Miss(Format('minor %d is %s upstream, %s here', [j,
                  G(TJSONArray(grp.Items[i]).Floats[k]), G(minors[j])]));
              Inc(j);
            end;
        end;
      end;
    end;
    AssertTrue('a great deal of it was compared (' + IntToStr(compared) + ')',
      compared > 3000);
    AssertEquals(IntToStr(bad) + ' of ' + IntToStr(compared)
      + ' disagree with upstream:' + report, 0, bad);
  finally
    bmp.Free;
    root.Free;
    sl.Free;
  end;
end;

{ ==================== the numbers ==================== }

{ Exactly: every one of these is a Double upstream computes exactly. }
procedure Eq(const AMsg: string; AWant, AGot: Double);
begin
  if not (AWant = AGot) then
    raise EAssertionFailedError.CreateFmt('%s: expected %s but was %s',
      [AMsg, FloatToStr(AWant), FloatToStr(AGot)]);
end;

{ A Double from its bits, as node printed them: a decimal literal would be
  read by FPC's own conversion, which is not always the nearest Double. }
function FromBits(ABits: QWord): Double;
begin
  Move(ABits, Result, SizeOf(Result));
end;

procedure TAdvChartNiceNumberTest.TestTheNiceLadderIsUpstreams;
begin
  { nice(v, round): 1, 2, 3, 5 or 10 of a power of ten, at 1.5 / 2.5 / 4 / 7,
    snapped to the decimal. Every threshold both sides, and the one the
    engine's own arithmetic moves: 0.15 over 0.1 is 1.4999999999999998. }
  Eq('', 1, TyNice(1.4, True));
  Eq('', 2, TyNice(1.5, True));
  Eq('', 2, TyNice(2.4, True));
  Eq('', 3, TyNice(2.5, True));
  Eq('', 3, TyNice(3.9, True));
  Eq('', 5, TyNice(4, True));
  Eq('', 5, TyNice(6.9, True));
  Eq('', 10, TyNice(7, True));
  Eq('', 1000, TyNice(1234, True));
  Eq('', 0.1, TyNice(0.15, True));
  Eq('', 0.3, TyNice(0.25, True));
  Eq('snapped, not 3 x 0.1', 0.3, TyNice(0.28, True));
  Eq('', 1, TyNice(0, True));
  { and the other mode: strictly below 1, 2, 3, 5 }
  Eq('', 2, TyNice(1, False));
  Eq('', 3, TyNice(2, False));
  Eq('', 10, TyNice(5, False));
  Eq('', 1, TyNice(0.9, False));
  { AN EXACT POWER IS NOT BELOW ITSELF. log(1000)/LN10 is
    2.9999999999999996 in both engines, and upstream corrects the floor
    (#11249). From 1e26 up the rounded ladder can see it too: ten times
    1e26 is a unit in the last place under 1e27, and toFixed keeps it. }
  AssertEquals('the exponent of 1000', 3, TyQuantityExponent(1000));
  Eq('1000 is a one, so the other ladder says two', 2000, TyNice(1000, False));
  Eq('a step of 1e27 is that Double', 1e27, TyNice(1e27, True));
end;

procedure TAdvChartNiceNumberTest.TestToFixedRoundsTheWayJavaScriptDoes;
const cBig: Double = 7.01501654007976e301;
begin
  Eq('', 0.3, TyJsToFixed(0.30000000000000004, 3));
  Eq('', 0.9, TyJsToFixed(0.8999999999999999, 3));
  Eq('half away from zero on the magnitude', 3, TyJsToFixed(2.5, 0));
  Eq('', -3, TyJsToFixed(-2.5, 0));
  Eq('precision is clamped to 0..20', 3, TyJsToFixed(2.5, -4));
  Eq('a huge value is given back', 1e22, TyJsToFixed(1e22, 2));
  { and one too long to print in fixed notation, which Str writes with two
    significant digits instead: 7.0E+301. }
  Eq('a value past printing is given back too', cBig, TyJsToFixed(cBig, 2));
  Eq('and past twenty places it rounds at twenty', 0, TyJsToFixed(1e-25, 28));
  { ON THE BINARY VALUE, as the specification rounds: 1.005 is a hair under
    it and 2.675 a hair under 2.675. FPC's Str rounds its own decimal and
    said 1.01 and 2.68. }
  Eq('1.005 to two places', 1, TyJsToFixed(1.005, 2));
  Eq('2.675 to two places', 2.67, TyJsToFixed(2.675, 2));
  Eq('a negative is its magnitude with the sign back', -1, TyJsToFixed(-1.005, 2));
  Eq('a real half goes up', 3, TyJsToFixed(2.5, 0));
  Eq('and a long answer is read back whole', 123.456, TyJsToFixed(123.456, 20));
  { NOT THROUGH Val EITHER. Read back as text, these three came out a unit
    in the last place from what Number() gives the same digits -- 22 of
    276,712 vectors did. Bits from node. }
  Eq('0.4307565 to six', FromBits($3FDB91819D2391D5),
    TyJsToFixed(FromBits($3FDB9183B60285EC), 6));
  Eq('0.0830725 to six', FromBits($3FB54434E3369B9D),
    TyJsToFixed(FromBits($3FB5443D46B26BF8), 6));
  Eq('0.235615 to five', FromBits($3FCE2877EE4E26D5),
    TyJsToFixed(FromBits($3FCE28A1DFB9389B), 5));
  { A LONG ANSWER -- x times 10^p past 2^53 -- is divided out to 64 bits and
    rounded, and it lands back on x: 1490471576.329515457153 is x's own
    decimal. Cutting the quotient off instead of rounding it lost a unit in
    the last place on 39 in every hundred of two million of these. }
  Eq('a long answer, twelve places', FromBits($41D635B2A61516C8),
    TyJsToFixed(FromBits($41D635B2A61516C8), 12));
  Eq('sixteen places', FromBits($403A1897A4CF6C4C),
    TyJsToFixed(FromBits($403A1897A4CF6C4C), 16));
  Eq('eight places', FromBits($41BA1FE32D68F23D),
    TyJsToFixed(FromBits($41BA1FE32D68F23D), 8));
  AssertTrue('not-a-number stays', IsNan(TyJsToFixed(NaN, 2)));
end;

procedure TAdvChartNiceNumberTest.TestPrecisionCountsTheDecimals;
begin
  AssertEquals(0, TyGetPrecision(20));
  AssertEquals(1, TyGetPrecision(0.2));
  AssertEquals(2, TyGetPrecision(0.05));
  AssertEquals(4, TyGetPrecision(0.0003));
  AssertEquals('a big value in the counting loop', 0, TyGetPrecision(393370));
  AssertEquals(17, TyGetPrecision(0.30000000000000004));
  AssertEquals('a negative takes the string path', 1, TyGetPrecision(-0.5));
  AssertEquals(9, TyGetPrecision(1e-9));
  AssertEquals('the step''s decimals plus two', 3, TyIntervalPrecision(0.2));
end;

procedure TAdvChartNiceNumberTest.TestTheSplitNumberIsRoundedAndDefaulted;
begin
  AssertEquals('zero is the default', 5, TyValidSplitNumber(0, 5));
  AssertEquals('so is not-a-number', 10, TyValidSplitNumber(NaN, 10));
  AssertEquals('two and a half is three', 3, TyValidSplitNumber(2.5, 5));
  AssertEquals(2, TyValidSplitNumber(2.4, 5));
  AssertEquals('below one is one', 1, TyValidSplitNumber(0.4, 5));
  AssertEquals(1, TyValidSplitNumber(-3, 5));
end;

procedure TAdvChartNiceNumberTest.TestJsRoundIsHalfUpAndDoesNotWrap;
begin
  Eq('', 3, TyJsRound(2.5));
  Eq('', -2, TyJsRound(-2.5));
  AssertEquals('not 1: the sum rounds, the test does not', 0,
    TyJsRound(0.49999999999999994));
  Eq('past two thousand million, still itself', 5e12, TyJsRound(5e12));
  Eq('', -5e12, TyJsRound(-5e12));
end;

procedure TAdvChartNiceNumberTest.TestTheLogMapperGivesTheEnginesPowers;
var m: ITyScaleMapper;
begin
  { Whole decades come back as Math.pow gives them in V8 -- including where
    that is not the nearest Double (10^-4) and where FPC's Power is not
    either (10^-10, eight units in the last place off). }
  m := TTyLogScaleMapper.Create(10);
  Eq('ten to the minus ten', FromBits($3DDB7CDFD9D7BDBB), m.TransformOut(-10));
  Eq('which is the nearest Double to 1e-10', 1e-10, m.TransformOut(-10));
  Eq('ten to the minus four, V8''s way', FromBits($3F1A36E2EB1C432C),
    m.TransformOut(-4));
  Eq('', 0.01, m.TransformOut(-2));
  Eq('', 1000, m.TransformOut(3));
  Eq('the table''s far end', FromBits($7FE1CCF385EBC8A0), TyJsPow10(308));
  AssertTrue('past it, infinity', IsInfinite(TyJsPow10(309)));
  Eq('and under the smallest, zero', 0, TyJsPow10(-324));
  { A fraction of a power still goes through Power. }
  Eq('', Power(10, 0.5), m.TransformOut(0.5));
end;

initialization
  RegisterTest(TAdvChartValueAxisOracleTest);
  RegisterTest(TAdvChartNiceNumberTest);
end.
