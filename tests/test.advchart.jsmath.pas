unit test.advchart.jsmath;
{$mode objfpc}{$H+}
{ JavaScript's Math.sin, cos, atan and atan2, held to V8's own answers.

  tools/advchart-oracle/js-math.js draws arguments from a seeded generator
  over every size from 1e-12 to 823,550 radians, and the ones a quarter turn
  leaves behind -- pi, pi/2, the 6.1e-17 a cosine of pi/2 is -- and records
  what node's Math answers. TyJsSin, TyJsCos, TyJsAtan and TyJsAtan2 must
  give every one of them bit for bit; a NaN matches any NaN.

  AND THE RUN-TIME LIBRARY DOES NOT, which is the reason the unit exists:
  the last test pins that, so the day FPC's Sin and ArcTan2 agree with V8
  this one says so and the port can drop its own. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     tyControls.AdvChart.JsMath;
type
  TAdvChartJsMathTest = class(TTestCase)
  private
    FRoot: TJSONData;
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestSinAndCosAreV8sToTheBit;
    procedure TestTanIsV8sToTheBit;
    procedure TestAtanIsV8sToTheBit;
    procedure TestAtan2IsV8sToTheBit;
    procedure TestTheRunTimeLibraryIsNot;
    procedure TestFroundIsMathFround;
    procedure TestPowAndLogAreV8sToTheBit;
    procedure TestPowFollowsV8NotTheTextbook;
  end;

implementation

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-js-math.json';
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Hex(A: Double): string;
var q: QWord;
begin
  Move(A, q, SizeOf(q));
  Result := LowerCase(IntToHex(q, 16));
end;

{ bit for bit, and any NaN for a NaN }
function Same(AGot: Double; const AWant: string): Boolean;
var w: Double;
begin
  w := FromHex(AWant);
  if IsNan(w) then Exit(IsNan(AGot));
  Result := Hex(AGot) = LowerCase(AWant);
end;

procedure TAdvChartJsMathTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
end;

procedure TAdvChartJsMathTest.TearDown;
begin
  FreeAndNil(FRoot);
  inherited TearDown;
end;

procedure TAdvChartJsMathTest.TestSinAndCosAreV8sToTheBit;
var
  rows, r: TJSONArray;
  i, bad: Integer;
  x: Double;
  report: string;
begin
  rows := TJSONObject(FRoot).Arrays['unary'];
  bad := 0;
  report := '';
  for i := 0 to rows.Count - 1 do
  begin
    r := rows.Arrays[i];
    x := FromHex(r.Strings[0]);
    if not (Same(TyJsSin(x), r.Strings[1]) and Same(TyJsCos(x), r.Strings[2])) then
    begin
      Inc(bad);
      if bad <= 10 then
        report := report + LineEnding + Format('  %s: sin %s cos %s, V8 %s %s',
          [r.Strings[4], Hex(TyJsSin(x)), Hex(TyJsCos(x)), r.Strings[1], r.Strings[2]]);
    end;
  end;
  AssertTrue('enough arguments', rows.Count >= 3000);
  AssertEquals(IntToStr(bad) + ' of ' + IntToStr(rows.Count) + ' differ:' + report, 0, bad);
end;

procedure TAdvChartJsMathTest.TestAtanIsV8sToTheBit;
var
  rows, r: TJSONArray;
  i, bad: Integer;
  x: Double;
  report: string;
begin
  bad := 0;
  report := '';
  rows := TJSONObject(FRoot).Arrays['unary'];
  for i := 0 to rows.Count - 1 do
  begin
    r := rows.Arrays[i];
    x := FromHex(r.Strings[0]);
    if not Same(TyJsAtan(x), r.Strings[3]) then
    begin
      Inc(bad);
      if bad <= 10 then
        report := report + LineEnding + Format('  %s: %s, V8 %s',
          [r.Strings[4], Hex(TyJsAtan(x)), r.Strings[3]]);
    end;
  end;
  rows := TJSONObject(FRoot).Arrays['atanOnly'];
  AssertTrue('and some past the reach of sin', rows.Count >= 2);
  for i := 0 to rows.Count - 1 do
  begin
    r := rows.Arrays[i];
    x := FromHex(r.Strings[0]);
    if not Same(TyJsAtan(x), r.Strings[1]) then
    begin
      Inc(bad);
      report := report + LineEnding + Format('  %s: %s, V8 %s',
        [r.Strings[2], Hex(TyJsAtan(x)), r.Strings[1]]);
    end;
  end;
  AssertEquals(IntToStr(bad) + ' differ:' + report, 0, bad);
end;

procedure TAdvChartJsMathTest.TestAtan2IsV8sToTheBit;
var
  rows, r: TJSONArray;
  i, bad: Integer;
  y, x: Double;
  report: string;
begin
  rows := TJSONObject(FRoot).Arrays['atan2'];
  bad := 0;
  report := '';
  for i := 0 to rows.Count - 1 do
  begin
    r := rows.Arrays[i];
    y := FromHex(r.Strings[0]);
    x := FromHex(r.Strings[1]);
    if not Same(TyJsAtan2(y, x), r.Strings[2]) then
    begin
      Inc(bad);
      if bad <= 10 then
        report := report + LineEnding + Format('  (%s): %s, V8 %s',
          [r.Strings[3], Hex(TyJsAtan2(y, x)), r.Strings[2]]);
    end;
  end;
  AssertTrue('enough pairs', rows.Count >= 3000);
  AssertEquals(IntToStr(bad) + ' of ' + IntToStr(rows.Count) + ' differ:' + report, 0, bad);
end;

procedure TAdvChartJsMathTest.TestTanIsV8sToTheBit;
var
  rows, r: TJSONArray;
  i, bad: Integer;
  x: Double;
  report: string;
begin
  rows := TJSONObject(FRoot).Arrays['tan'];
  bad := 0;
  report := '';
  for i := 0 to rows.Count - 1 do
  begin
    r := rows.Arrays[i];
    x := FromHex(r.Strings[0]);
    if not Same(TyJsTan(x), r.Strings[1]) then
    begin
      Inc(bad);
      if bad <= 10 then
        report := report + LineEnding + Format('  %s: tan %s, V8 %s',
          [r.Strings[2], Hex(TyJsTan(x)), r.Strings[1]]);
    end;
  end;
  AssertTrue('enough arguments', rows.Count >= 3000);
  AssertEquals(IntToStr(bad) + ' of ' + IntToStr(rows.Count) + ' differ:' + report, 0, bad);
end;

procedure TAdvChartJsMathTest.TestTheRunTimeLibraryIsNot;
var y, x, a: Double;
begin
  { THE REASON FOR THE UNIT. A y axis' move direction is (-1, -6.1e-17):
    V8 turns that into minus pi, the run-time library into plus pi. And the
    sine of 2 is one unit in the last place apart. If this goes red the
    library has caught up -- and the port's own copies can go. }
  y := -6.123233995736766e-17;
  x := -1;
  AssertTrue('V8: minus pi', Hex(TyJsAtan2(y, x)) = 'c00921fb54442d18');
  AssertTrue('the run-time library: not', Hex(ArcTan2(y, x)) <> 'c00921fb54442d18');
  a := 2;
  AssertTrue('V8: sin 2', Hex(TyJsSin(a)) = '3fed18f6ead1b446');
  AssertTrue('the run-time library: not', Hex(Sin(a)) <> '3fed18f6ead1b446');
  { tan 2 pi: the skew a label turned past a quarter is recomposed with }
  a := FromHex('401921fb54442d18');
  AssertTrue('V8: tan 2 pi', Hex(TyJsTan(a)) = 'bcb1a62633145c07');
  AssertTrue('the run-time library: not', Hex(Tan(a)) <> 'bcb1a62633145c07');
end;

function PowLogPath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-js-powlog.json';
end;

procedure TAdvChartJsMathTest.TestPowAndLogAreV8sToTheBit;
var
  root: TJSONData;
  rows, r: TJSONArray;
  sl: TStringList;
  i, bad: Integer;
  got: Double;
  report: string;
begin
  { tools/advchart-oracle/js-pow-log.js: node's Math.pow and Math.log over
    the shapes a log axis asks for -- 10 and 2 to fractional powers, the
    decades, the ends of a mapping extent -- random arguments over the whole
    range, the specials, and every row where fdlibm as printed and V8 part }
  AssertTrue('the fixture is where the suite expects it', FileExists(PowLogPath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(PowLogPath);
    root := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  try
    bad := 0;
    report := '';
    rows := TJSONObject(root).Arrays['pow'];
    for i := 0 to rows.Count - 1 do
    begin
      r := rows.Arrays[i];
      got := TyJsPow(FromHex(r.Strings[0]), FromHex(r.Strings[1]));
      if not Same(got, r.Strings[2]) then
      begin
        Inc(bad);
        if bad <= 10 then
          report := report + LineEnding + Format('  pow %s: %s, V8 %s',
            [r.Strings[3], Hex(got), r.Strings[2]]);
      end;
    end;
    AssertTrue('enough powers', rows.Count >= 3000);
    rows := TJSONObject(root).Arrays['log'];
    for i := 0 to rows.Count - 1 do
    begin
      r := rows.Arrays[i];
      got := TyJsLog(FromHex(r.Strings[0]));
      if not Same(got, r.Strings[1]) then
      begin
        Inc(bad);
        if bad <= 10 then
          report := report + LineEnding + Format('  log %s: %s, V8 %s',
            [r.Strings[2], Hex(got), r.Strings[1]]);
      end;
    end;
    AssertTrue('enough logarithms', rows.Count >= 2500);
    AssertEquals(IntToStr(bad) + ' differ:' + report, 0, bad);
  finally
    root.Free;
  end;
end;

procedure TAdvChartJsMathTest.TestPowFollowsV8NotTheTextbook;
begin
  { V8'S ONE CHANGED LINE, ieee754.cc:2894, the correction inside the
    divisor: these three are where it and fdlibm as printed part. 10^2.5
    and 2^27.5 are not -- they tell V8 from FPC's Power, not from fdlibm. }
  AssertEquals('10^-4', '3f1a36e2eb1c432c', Hex(TyJsPow(10, -4)));
  AssertEquals('10^-307', '0031fa182c40c60e', Hex(TyJsPow(10, -307)));
  AssertEquals('1.5^1025', '656806d222b7eba6', Hex(TyJsPow(1.5, 1025)));
  AssertTrue('and FPC''s Power is not it', Hex(Power(10, -4)) <> '3f1a36e2eb1c432c');
end;

procedure TAdvChartJsMathTest.TestFroundIsMathFround;
const
  { Math.fround in node, argument and answer as bit patterns: a vertex, the
    largest single, the tie just past it that goes to the infinity, below
    half the smallest subnormal, and -0 }
  Cases: array[0..11, 0..1] of string = (
    ('3ff199999999999a', '3ff19999a0000000'),
    ('406faaaaaaaaaaab', '406faaaaa0000000'),
    ('c05f276276276800', 'c05f276280000000'),
    ('47efffffe0000000', '47efffffe0000000'),
    ('47efffffefffffff', '47efffffe0000000'),
    ('47effffff0000000', '7ff0000000000000'),
    ('c7effffff0000000', 'fff0000000000000'),
    ('48078287f49c4a1d', '7ff0000000000000'),
    ('36a0000000000000', '36a0000000000000'),
    ('368ff868bf4d956a', '0000000000000000'),
    ('3fe0000000000000', '3fe0000000000000'),
    ('8000000000000000', '8000000000000000'));
var
  i: Integer;
  x, want, got: Double;
  q: QWord;
begin
  for i := 0 to High(Cases) do
  begin
    q := StrToQWord('$' + Cases[i, 0]);
    Move(q, x, 8);
    q := StrToQWord('$' + Cases[i, 1]);
    Move(q, want, 8);
    got := TyJsFround(x);
    Move(got, q, 8);
    AssertEquals('fround of ' + Cases[i, 0], LowerCase(Cases[i, 1]),
      LowerCase(IntToHex(q, 16)));
  end;
  AssertTrue('and a gap stays one', IsNan(TyJsFround(NaN)));
end;

initialization
  RegisterTest(TAdvChartJsMathTest);
end.
