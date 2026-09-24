unit test.advchart.parsevalue;
{$mode objfpc}{$H+}
{ A data cell read into the store -- held to upstream to the bit.

  tools/advchart-oracle/parse-value.js reads ECharts 6.1's own store: each
  input is a bar's value (a float dimension) and a line's x on a time axis,
  and the record is what the store holds for it.

  THE RULES IT HOLDS THE PORT TO: parseDataValue is Number() of anything
  but the exact empty string -- '   ' is nought, '0x10' sixteen, 'Infinity'
  infinite, 'Inf' and '5e+' not numbers; a time is a number as written, a
  boolean as 0 or 1, and text through the date parser untrimmed.

  And what an infinity then does downstream, where upstream's JavaScript
  carries on and FPC would raise: a pie with an infinite slice, a funnel
  with an infinite band. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     tyControls.AdvChart.Types, tyControls.AdvChart.Data,
     tyControls.AdvChart.Pie, tyControls.AdvChart.Funnel;
type
  TAdvChartParseValueOracleTest = class(TTestCase)
  published
    procedure TestEveryCellReadsAsUpstreamsStoreHoldsIt;
    procedure TestAnInfiniteSliceDoesNotRaise;
    procedure TestBlankAndHexSlicesAreSharedAsUpstreamShares;
    procedure TestAnInfiniteFunnelBandIsTheWholeWidth;
  end;

implementation

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-parse-value.json';
end;

function HexNum(AData: TJSONData): Double;
var q: QWord;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(NaN);
  q := StrToQWord('$' + AData.AsString);
  Result := 0;
  Move(q, Result, SizeOf(Result));
end;

function Bits(A: Double): QWord;
begin
  Result := 0;
  Move(A, Result, SizeOf(Result));
end;

{ The JSON cell as the store's builder hands it over. }
function CellOf(AData: TJSONData): TTyDataValue;
begin
  if AData = nil then Exit(TyDataNone);
  case AData.JSONType of
    jtNumber: Result := TyDataNum(AData.AsFloat);
    jtString: Result := TyDataText(AData.AsString);
    jtBoolean: Result := TyDataBool(AData.AsBoolean);
  else
    Result := TyDataNone;
  end;
end;

procedure TAdvChartParseValueOracleTest.TestEveryCellReadsAsUpstreamsStoreHoldsIt;
var
  sl: TStringList;
  root: TJSONData;
  recs: TJSONArray;
  r: TJSONObject;
  i, bad, times: Integer;
  got, want: Double;
  report, what: string;
  mask: TFPUExceptionMask;

  procedure Check(const AKind: string; AGot: Double; AWant: TJSONData);
  begin
    want := HexNum(AWant);
    if (IsNan(want) and IsNan(AGot)) or (Bits(AGot) = Bits(want)) then Exit;
    Inc(bad);
    if bad <= 25 then
      report := report + LineEnding + Format('  %s %s: %s, upstream %s',
        [AKind, what, FloatToStr(AGot), FloatToStr(want)]);
  end;

begin
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    root := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  mask := GetExceptionMask;
  SetExceptionMask(mask + [exInvalidOp, exOverflow, exZeroDivide, exPrecision]);
  try
    recs := TJSONObject(root).Arrays['records'];
    bad := 0;
    times := 0;
    report := '';
    for i := 0 to recs.Count - 1 do
    begin
      r := recs.Objects[i];
      what := r.Find('in').AsJSON;
      got := TyParseDataValue(CellOf(r.Find('in')), ddtFloat);
      Check('float', got, r.Find('float'));
      if (r.Find('time') <> nil) and (r.Find('time').JSONType <> jtNull) then
      begin
        Inc(times);
        got := TyParseDataValue(CellOf(r.Find('in')), ddtTime);
        Check('time', got, r.Find('time'));
      end;
    end;
    AssertTrue('enough records', recs.Count >= 500);
    AssertTrue('enough times', times >= 20);
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
    root.Free;
  end;
  AssertEquals(IntToStr(bad) + ' cells differ from upstream:' + report, 0, bad);
end;

function PieStore(const ACells: array of TTyDataValue): TTyDataStore;
var i: Integer;
begin
  Result := TTyDataStore.Create;
  Result.AddDimension(TyPieValueDim, ddtFloat);
  for i := 0 to High(ACells) do Result.AppendRow([ACells[i]]);
end;

{ upstream (wf53 a1 4a): a pie of [Infinity, 5] -- sectors 4.712..NaN and
  NaN..NaN, percentages 0 and 0. FPC would raise on Infinity * 0. }
procedure TAdvChartParseValueOracleTest.TestAnInfiniteSliceDoesNotRaise;
var
  st: TTyDataStore;
  lay: TTyPieLayout;
  pct: TTyDoubleArray;
begin
  st := PieStore([TyDataText('Infinity'), TyDataNum(5)]);
  try
    lay := TyPieLayoutOf(TyPieSpecDefault, TyRectF(0, 0, 400, 300), st, 0);
    AssertEquals('two sectors', 2, Length(lay.Sectors));
    AssertTrue('the infinite one reads as infinite', IsInfinite(lay.Sectors[0].Value));
    AssertTrue('it ends nowhere', IsNan(lay.Sectors[0].EndRad));
    AssertTrue('and the next starts nowhere', IsNan(lay.Sectors[1].StartRad));
    pct := TyPieSectorPercents(lay, 2);
    AssertEquals('no share', 0, pct[0], 0);
    AssertEquals('none either', 0, pct[1], 0);
  finally
    st.Free;
  end;
end;

{ upstream (wf53 a1): a pie of ['   ', '0x10', 5] is 0, 16 and 5 --
  0%, 76.19% and 23.81%. }
procedure TAdvChartParseValueOracleTest.TestBlankAndHexSlicesAreSharedAsUpstreamShares;
var
  st: TTyDataStore;
  lay: TTyPieLayout;
  pct: TTyDoubleArray;
begin
  st := PieStore([TyDataText('   '), TyDataText('0x10'), TyDataNum(5)]);
  try
    lay := TyPieLayoutOf(TyPieSpecDefault, TyRectF(0, 0, 400, 300), st, 0);
    pct := TyPieSectorPercents(lay, 2);
    AssertEquals('three sectors', 3, Length(pct));
    AssertEquals('blanks are nought', 0, pct[0], 0);
    AssertEquals('hex is sixteen', 76.19, pct[1], 1e-9);
    AssertEquals('and five', 23.81, pct[2], 1e-9);
  finally
    st.Free;
  end;
end;

{ upstream (wf53 a1 4d): a funnel of [Infinity, 5, 3] -- percentages NaN, 0,
  0; the infinite band spans the whole width and the other two map to
  nought. }
procedure TAdvChartParseValueOracleTest.TestAnInfiniteFunnelBandIsTheWholeWidth;
var
  st: TTyDataStore;
  lay: TTyFunnelLayout;
  pct: TTyDoubleArray;
  full, w0, w1: Double;
  i: Integer;
begin
  st := TTyDataStore.Create;
  try
    st.AddDimension('value', ddtFloat);
    st.AppendRow([TyDataText('Infinity')]);
    st.AppendRow([TyDataNum(5)]);
    st.AppendRow([TyDataNum(3)]);
    lay := TyFunnelLayoutOf(TyFunnelSpecDefault, TyRectF(0, 0, 600, 400), st, 0);
    AssertTrue('it laid out', lay.Valid);
    pct := TyFunnelPercents(lay);
    for i := 0 to High(lay.Items) do
      if IsInfinite(lay.Items[i].Value) then
      begin
        AssertTrue('the infinite share is not a number', IsNan(pct[i]));
        full := lay.ViewRect.Right - lay.ViewRect.Left;
        w0 := lay.Items[i].Points[1].X - lay.Items[i].Points[0].X;
        AssertEquals('the infinite band is the whole width', full, w0, 1e-9);
      end
      else
      begin
        AssertEquals('a finite share of infinity is nought', 0, pct[i], 0);
        w1 := lay.Items[i].Points[1].X - lay.Items[i].Points[0].X;
        AssertEquals('and its band has no width', 0, w1, 1e-9);
      end;
  finally
    st.Free;
  end;
end;

initialization
  RegisterTest(TAdvChartParseValueOracleTest);
end.
