unit test.advchart.brushstyle;
{$mode objfpc}{$H+}
{ A BRUSH COVER'S LINE STYLE AND ITS z, HELD TO UPSTREAM [R5-D].

  tools/advchart-oracle/brush-style.js runs the real ECharts 6.1 build in
  node: covers laid down by the `brush` action (pixel ranges, the global
  panel) or drawn by a drag after takeGlobalCursor, the component's
  brushStyle carrying borderType / borderDashOffset / borderCap /
  borderJoin / borderMiterLimit (getItemStyle's line keys), an area's own
  brushStyle (zrender's keys) over it, the component's and an area's z. Per
  cover it records the main shape's style (lineDash as written, its offset,
  cap, join, miter limit, line width, opacity), z, z2 and how many series
  elements lie above it.

  This replays the options and steps through TTyAdvanceChart and reads the
  covers BrushCoversForTest builds: the dash as zrender's normalizeLineDash
  makes it of the written value against the cover's width (strokeNoScale),
  the phase, the cap and join, the miter limit, the width, the alpha, z and
  z2, and the series elements of the paint list that sort above it. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Paint,
     tyControls.AdvanceChart;
type
  TBsProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { the series elements of the paint list that sort above (Z, Z2) }
    function SeriesAbove(AZ, AZ2: Integer): Integer;
  end;

  TAdvChartBrushStyleOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared: Integer;
    FReport, FWhere: string;
    procedure Bad(const AWhat: string);
    procedure RunCase(const AId: string);
    procedure CompareCover(AChart: TBsProbe; const AEl: TTyChartElement; AWant: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheWordsAsUpstream;
    procedure TestListsAsUpstream;
    procedure TestSolidAsUpstream;
    procedure TestADrawnCoverAsUpstream;
    procedure TestALowZAsUpstream;
    procedure TestAnAreasZAsUpstream;
  end;

implementation

const
  cW = 600;
  cH = 400;

function FixturePath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim + AName;
end;

procedure TBsProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TBsProbe.SeriesAbove(AZ, AZ2: Integer): Integer;
var
  i: Integer;
  el: TTyChartElement;
begin
  Result := 0;
  if SeriesList = nil then Exit;
  for i := 0 to SeriesList.Count - 1 do
  begin
    el := SeriesList.Element(i);
    if (el.Datum.Kind <> ctkSeries) or (el.Datum.SeriesIndex < 0) then Continue;
    if (el.Z > AZ) or ((el.Z = AZ) and (el.Z2 > AZ2)) then Inc(Result);
  end;
end;

{ zrender's normalizeLineDash of a written lineDash against a width }
function NormalizedDash(AType: TJSONData; AWidth: Double): string;
var i: Integer;
begin
  Result := '';
  if (AType = nil) or (AType.JSONType = jtNull) or not (AWidth > 0) then Exit;
  case AType.JSONType of
    jtString:
      if AType.AsString = 'dashed' then
        Result := FloatToStr(4 * AWidth) + ',' + FloatToStr(2 * AWidth)
      else if AType.AsString = 'dotted' then
        Result := FloatToStr(AWidth);
    jtNumber:
      if AType.AsFloat <> 0 then Result := FloatToStr(AType.AsFloat);
    jtArray:
      for i := 0 to AType.Count - 1 do
      begin
        if i > 0 then Result := Result + ',';
        Result := Result + FloatToStr(AType.Items[i].AsFloat);
      end;
  end;
end;

function DashText(const A: TTyDoubleArray): string;
var i: Integer;
begin
  Result := '';
  for i := 0 to High(A) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + FloatToStr(A[i]);
  end;
end;

procedure TAdvChartBrushStyleOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath('advchart-brush-style.json'));
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FReport := '';
end;

procedure TAdvChartBrushStyleOracleTest.TearDown;
begin
  FRoot.Free;
  FBmp.Free;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartBrushStyleOracleTest.Bad(const AWhat: string);
begin
  Inc(FBad);
  if Length(FReport) < 20000 then
    FReport := FReport + LineEnding + FWhere + ': ' + AWhat;
end;

procedure TAdvChartBrushStyleOracleTest.CompareCover(AChart: TBsProbe;
  const AEl: TTyChartElement; AWant: TJSONObject);
var
  st: TJSONObject;
  lw, want: Double;
  s, cap, join: string;
  d: TJSONData;
begin
  st := AWant.Objects['style'];
  lw := st.Floats['lineWidth'];
  Inc(FCompared);
  if AEl.Style.StrokeWidthLogical <> lw then
    Bad(Format('width %g, upstream %g', [AEl.Style.StrokeWidthLogical, lw]));
  s := NormalizedDash(st.Find('lineDash'), lw);
  Inc(FCompared);
  if DashText(AEl.Style.DashLogical) <> s then
    Bad(Format('dash [%s], upstream [%s] (%s)', [DashText(AEl.Style.DashLogical), s,
      st.Find('lineDash').AsJSON]));
  want := 0;
  d := st.Find('lineDashOffset');
  if (d <> nil) and (d.JSONType = jtNumber) then want := d.AsFloat;
  Inc(FCompared);
  if AEl.Style.DashOffsetLogical <> want then
    Bad(Format('dash offset %g, upstream %g', [AEl.Style.DashOffsetLogical, want]));
  case AEl.Style.LineCap of
    1: cap := 'round';
    2: cap := 'square';
  else
    cap := 'butt';
  end;
  Inc(FCompared);
  if (st.Find('lineCap').JSONType = jtString) and (cap <> st.Strings['lineCap']) then
    Bad(Format('cap %s, upstream %s', [cap, st.Strings['lineCap']]));
  case AEl.Style.LineJoin of
    1: join := 'round';
    2: join := 'bevel';
  else
    join := 'miter';
  end;
  s := 'miter';
  if st.Find('lineJoin').JSONType = jtString then s := st.Strings['lineJoin'];
  Inc(FCompared);
  if join <> s then Bad(Format('join %s, upstream %s', [join, s]));
  want := 10;
  if AEl.Style.MiterLimit > 0 then want := AEl.Style.MiterLimit;
  Inc(FCompared);
  if want <> st.Floats['miterLimit'] then
    Bad(Format('miter limit %g, upstream %g', [want, st.Floats['miterLimit']]));
  Inc(FCompared);
  if AEl.Style.Alpha <> st.Floats['opacity'] then
    Bad(Format('alpha %g, upstream %g', [AEl.Style.Alpha, st.Floats['opacity']]));
  Inc(FCompared);
  if (AEl.Z <> AWant.Integers['z']) or (AEl.Z2 <> AWant.Integers['z2']) then
    Bad(Format('z %d / %d, upstream %d / %d', [AEl.Z, AEl.Z2, AWant.Integers['z'],
      AWant.Integers['z2']]));
  Inc(FCompared);
  if AChart.SeriesAbove(AEl.Z, AEl.Z2) <> AWant.Integers['below'] then
    Bad(Format('%d series elements above, upstream %d', [AChart.SeriesAbove(AEl.Z, AEl.Z2),
      AWant.Integers['below']]));
end;

procedure TAdvChartBrushStyleOracleTest.RunCase(const AId: string);
var
  cases, steps, pts, covers: TJSONArray;
  cs, st: TJSONObject;
  chart: TBsProbe;
  i, j, k: Integer;
  op: string;
  list: TTyPaintList;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  cs := nil;
  for i := 0 to cases.Count - 1 do
    if cases.Objects[i].Strings['id'] = AId then cs := cases.Objects[i];
  AssertTrue('no case ' + AId, cs <> nil);
  chart := TBsProbe.Create(FForm);
  try
    chart.Parent := FForm;
    chart.Controller := FCtl;
    chart.SetBounds(0, 0, cW, cH);
    chart.Option := cs.Objects['option'].AsJSON;
    chart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
    steps := cs.Arrays['steps'];
    for j := 0 to steps.Count - 1 do
    begin
      st := steps.Objects[j];
      op := st.Strings['op'];
      FWhere := Format('%s step %d (%s)', [AId, j, op]);
      if op = 'action' then
        chart.DispatchAction(st.Objects['payload'].AsJSON)
      else
      begin
        pts := st.Arrays['points'];
        chart.MouseMove([], pts.Arrays[0].Integers[0], pts.Arrays[0].Integers[1]);
        chart.MouseDown(mbLeft, [], pts.Arrays[0].Integers[0], pts.Arrays[0].Integers[1]);
        for k := 1 to pts.Count - 1 do
          chart.MouseMove([], pts.Arrays[k].Integers[0], pts.Arrays[k].Integers[1]);
        k := pts.Count - 1;
        chart.MouseUp(mbLeft, [], pts.Arrays[k].Integers[0], pts.Arrays[k].Integers[1]);
      end;
      chart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
      covers := st.Objects['record'].Arrays['covers'];
      list := chart.BrushCoversForTest;
      try
        Inc(FCompared);
        if list.Count <> covers.Count then
        begin
          Bad(Format('%d covers, upstream %d', [list.Count, covers.Count]));
          Continue;
        end;
        for k := 0 to covers.Count - 1 do
        begin
          FWhere := Format('%s step %d cover %d', [AId, j, k]);
          CompareCover(chart, list.Element(k), covers.Objects[k]);
        end;
      finally
        list.Free;
      end;
    end;
  finally
    chart.Free;
  end;
  AssertTrue(AId + ': nothing compared', FCompared > 0);
  AssertEquals(Format('%s: %d of %d comparisons differ:%s',
    [AId, FBad, FCompared, FReport]), 0, FBad);
end;

procedure TAdvChartBrushStyleOracleTest.TestTheWordsAsUpstream;
begin
  RunCase('words');
end;

procedure TAdvChartBrushStyleOracleTest.TestListsAsUpstream;
begin
  RunCase('lists');
end;

procedure TAdvChartBrushStyleOracleTest.TestSolidAsUpstream;
begin
  RunCase('solid');
end;

procedure TAdvChartBrushStyleOracleTest.TestADrawnCoverAsUpstream;
begin
  RunCase('drag');
end;

procedure TAdvChartBrushStyleOracleTest.TestALowZAsUpstream;
begin
  RunCase('z-low');
end;

procedure TAdvChartBrushStyleOracleTest.TestAnAreasZAsUpstream;
begin
  RunCase('z-area');
end;

initialization
  RegisterTest(TAdvChartBrushStyleOracleTest);
end.
