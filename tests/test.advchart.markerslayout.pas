unit test.advchart.markerslayout;
{$mode objfpc}{$H+}
{ Series markers as numbers -- which markPoint / markLine / markArea items
  survive, what the transform made of each (coords, stored values, value,
  name), where each end and corner lands, and what the item visuals read
  from the model chain -- held to what ECharts 6.1 builds.

  tools/advchart-oracle/markers-layout.js records every series whose own
  option carries a marker `data`: the block's z / zlevel / silent / count
  (and markLine's precision), then one row per ORIGINAL data element. The
  port's MarkerLayout read-out is compared field by field.

  EXACT: bit for bit, -0 and 0 one. A gallery series whose grid lands
  elsewhere here (axis labels measure differently) is counted and passed
  over; the synthetic cases must all line up. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Coord, tyControls.AdvChart.Scale,
     tyControls.AdvChart.Paint,
     tyControls.AdvChart.Marker, tyControls.AdvanceChart;
type
  TMlProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartMarkersLayoutOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TMlProbe;
    FRoot: TJSONData;
    FBmp: TBGRABitmap;
    FBad, FCompared, FSkipped, FSeriesSeen: Integer;
    FReport, FName, FSkipNames: string;
    procedure Miss(const AWhat: string);
    procedure CheckVal(const AWhat: string; const AV: TTyMkVal; AFx: TJSONData);
    procedure CheckPair(const AWhat: string; const AV: TTyMkPair; AFx: TJSONData);
    procedure CheckPoint(const AWhat: string; const AP: TTyPointF; AFx: TJSONData);
    procedure CheckJson(const AWhat: string; AV, AFx: TJSONData);
    procedure CheckBlock(const AWhat: string; const B: TTyMkBlock; AFx: TJSONObject);
    function AxesAgree(const B: TTyMkBlock; AAxes: TJSONArray): Boolean;
    procedure CheckScales(const B: TTyMkBlock; AAxes: TJSONArray);
    procedure RunCases(AGallery: Boolean);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestMarkersAsUpstreamLaysThemOut;
    procedure TestGalleryMarkersAsUpstream;
    procedure TestAnElementUpstreamCannotHandleIsSkipped;
    procedure TestTheOptionIsNotMutated;
    procedure TestTheMedianCountsTheGaps;
    procedure TestASeriesSitsAtUpstreamsZ;
  end;

implementation

procedure TMlProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TMlProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-markers-layout.json';
end;

function GalleryPath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'examples'
    + PathDelim + 'advchart' + PathDelim + 'gallery' + PathDelim + AName + '.json';
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function Bits(A: Double): QWord;
begin
  Move(A, Result, SizeOf(Result));
end;

function Fmt(A: Double): string;
begin
  if IsNan(A) then Exit('NaN');
  if IsInfinite(A) then
    if A > 0 then Exit('Infinity') else Exit('-Infinity');
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function SameNum(A: Double; const AHex: string): Boolean;
var b: Double;
begin
  b := FromHex(AHex);
  if IsNan(A) or IsNan(b) then Exit(IsNan(A) and IsNan(b));
  if (A = 0) and (b = 0) then Exit(True);
  Result := Bits(A) = Bits(b);
end;

function ValText(const AV: TTyMkVal): string;
begin
  case AV.Kind of
    mvkUndef: Result := 'undefined';
    mvkNull: Result := 'null';
    mvkNum: Result := Fmt(AV.Num);
    mvkStr: Result := '''' + AV.Str + '''';
  else
    Result := 'other ' + Fmt(AV.Num);
  end;
end;

function IsNull(A: TJSONData): Boolean;
begin
  Result := (A = nil) or (A.JSONType = jtNull);
end;

procedure TAdvChartMarkersLayoutOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TMlProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(800, 600, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  sl := TStringList.Create;
  try
    sl.LoadFromFile(FixturePath);
    FRoot := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
  FBad := 0;
  FCompared := 0;
  FSkipped := 0;
  FSeriesSeen := 0;
  FReport := '';
end;

procedure TAdvChartMarkersLayoutOracleTest.TearDown;
begin
  FRoot.Free;
  FBmp.Free;
  FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartMarkersLayoutOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartMarkersLayoutOracleTest.CheckVal(const AWhat: string;
  const AV: TTyMkVal; AFx: TJSONData);
var
  o: TJSONObject;
  ok: Boolean;
  want: string;
begin
  Inc(FCompared);
  if IsNull(AFx) then
  begin
    if not (AV.Kind in [mvkUndef, mvkNull]) then
      Miss(Format('%s: null upstream, %s here', [AWhat, ValText(AV)]));
    Exit;
  end;
  o := TJSONObject(AFx);
  if o.Find('n') <> nil then
  begin
    ok := (AV.Kind = mvkNum) and SameNum(AV.Num, o.Strings['n']);
    want := o.Strings['t'];
  end
  else if o.Find('s') <> nil then
  begin
    ok := (AV.Kind = mvkStr) and (AV.Str = o.Strings['s']);
    want := '''' + o.Strings['s'] + '''';
  end
  else
  begin
    want := o.Find('j').AsJSON;
    ok := (AV.Kind = mvkOther) and (o.Find('j').JSONType = jtBoolean)
      and ((AV.Num <> 0) = o.Find('j').AsBoolean);
  end;
  if not ok then
    Miss(Format('%s: %s upstream, %s here', [AWhat, want, ValText(AV)]));
end;

procedure TAdvChartMarkersLayoutOracleTest.CheckPair(const AWhat: string;
  const AV: TTyMkPair; AFx: TJSONData);
begin
  CheckVal(AWhat + '[0]', AV[0], TJSONArray(AFx).Items[0]);
  CheckVal(AWhat + '[1]', AV[1], TJSONArray(AFx).Items[1]);
end;

procedure TAdvChartMarkersLayoutOracleTest.CheckPoint(const AWhat: string;
  const AP: TTyPointF; AFx: TJSONData);
var a: TJSONArray;
begin
  Inc(FCompared);
  if IsNull(AFx) then
  begin
    if not (IsNan(AP.X) and IsNan(AP.Y)) then
      Miss(Format('%s: no point upstream, (%s, %s) here', [AWhat, Fmt(AP.X), Fmt(AP.Y)]));
    Exit;
  end;
  a := TJSONArray(AFx);
  if not (SameNum(AP.X, a.Strings[0]) and SameNum(AP.Y, a.Strings[1])) then
    Miss(Format('%s: (%s, %s) upstream, (%s, %s) here', [AWhat,
      Fmt(FromHex(a.Strings[0])), Fmt(FromHex(a.Strings[1])), Fmt(AP.X), Fmt(AP.Y)]));
end;

function SameJson(A, B: TJSONData): Boolean;
var i: Integer;
begin
  if IsNull(A) or IsNull(B) then Exit(IsNull(A) and IsNull(B));
  if A.JSONType <> B.JSONType then Exit(False);
  case A.JSONType of
    jtNumber: Result := A.AsFloat = B.AsFloat;
    jtString: Result := A.AsString = B.AsString;
    jtBoolean: Result := A.AsBoolean = B.AsBoolean;
    jtArray:
      begin
        if A.Count <> B.Count then Exit(False);
        for i := 0 to A.Count - 1 do
          if not SameJson(A.Items[i], B.Items[i]) then Exit(False);
        Result := True;
      end;
  else
    Result := A.AsJSON = B.AsJSON;
  end;
end;

procedure TAdvChartMarkersLayoutOracleTest.CheckJson(const AWhat: string;
  AV, AFx: TJSONData);
var got: string;
begin
  Inc(FCompared);
  if not SameJson(AV, AFx) then
  begin
    if AV = nil then got := 'null' else got := AV.AsJSON;
    if AFx = nil then Miss(AWhat + ': null upstream, ' + got + ' here')
    else Miss(AWhat + ': ' + AFx.AsJSON + ' upstream, ' + got + ' here');
  end;
end;

function TAdvChartMarkersLayoutOracleTest.AxesAgree(const B: TTyMkBlock;
  AAxes: TJSONArray): Boolean;
var
  k: Integer;
  ax: TTyAxis;
  s0, s1: Double;
  g: TJSONArray;
begin
  Result := True;
  for k := 0 to 1 do
  begin
    if k = 0 then ax := B.XAxis else ax := B.YAxis;
    if ax = nil then Exit(False);
    ax.LocalExtent(s0, s1);
    g := AAxes.Objects[k].Arrays['global'];
    if not (SameNum(ax.ToGlobal(s0), g.Strings[0]) and SameNum(ax.ToGlobal(s1), g.Strings[1])) then
      Exit(False);
  end;
end;

{ the scales the transform reads: the EFFECTIVE extent (clamp, allClipped)
  and the MAPPING one (containData, and every pixel) }
procedure TAdvChartMarkersLayoutOracleTest.CheckScales(const B: TTyMkBlock;
  AAxes: TJSONArray);
var
  k: Integer;
  ax: TTyAxis;
  e: TTyRange;
  a: TJSONArray;
  o: TJSONObject;
begin
  for k := 0 to 1 do
  begin
    if k = 0 then ax := B.XAxis else ax := B.YAxis;
    o := AAxes.Objects[k];
    e := ax.Scale.GetExtent;
    a := o.Arrays['effective'];
    Inc(FCompared);
    if not (SameNum(e.Start, a.Strings[0]) and SameNum(e.Stop, a.Strings[1])) then
      Miss(Format('%s axis effective extent: [%s, %s] upstream, [%s, %s] here',
        [o.Strings['dim'], Fmt(FromHex(a.Strings[0])), Fmt(FromHex(a.Strings[1])),
        Fmt(e.Start), Fmt(e.Stop)]));
    if IsNull(o.Find('mapping')) then Continue;
    e := ax.Scale.GetExtent2(sekMapping);
    a := o.Arrays['mapping'];
    Inc(FCompared);
    if not (SameNum(e.Start, a.Strings[0]) and SameNum(e.Stop, a.Strings[1])) then
      Miss(Format('%s axis mapping extent: [%s, %s] upstream, [%s, %s] here',
        [o.Strings['dim'], Fmt(FromHex(a.Strings[0])), Fmt(FromHex(a.Strings[1])),
        Fmt(e.Start), Fmt(e.Stop)]));
  end;
end;

procedure TAdvChartMarkersLayoutOracleTest.CheckBlock(const AWhat: string;
  const B: TTyMkBlock; AFx: TJSONObject);
const
  cVis: array[0..4] of string = ('symbol', 'symbolSize', 'symbolRotate',
    'symbolOffset', 'symbolKeepAspect');
var
  items: TJSONArray;
  it, en: TJSONObject;
  i, k, j, di: Integer;
  w: string;
  sv: Boolean;

  procedure CheckEnd(const AW: string; const E: TTyMkEnd; AE: TJSONObject;
    AIdx: Integer; AIsFrom: Boolean);
  var q: Integer;
  begin
    CheckPair(AW + ' coord', E.Coord, AE.Find('coord'));
    CheckPair(AW + ' values', E.Values, AE.Find('values'));
    CheckPoint(AW + ' point', E.Point, AE.Find('point'));
    for q := 0 to High(cVis) do
      if B.Kind = mkPoint then
        CheckJson(AW + ' ' + cVis[q], TyMkPointVisual(B, AIdx, cVis[q]), AE.Find(cVis[q]))
      else
        CheckJson(AW + ' ' + cVis[q], TyMkLineVisual(B, AIdx, AIsFrom, cVis[q]),
          AE.Find(cVis[q]));
  end;

begin
  Inc(FCompared);
  if not B.Present then
  begin
    Miss(AWhat + ': a block upstream, none here');
    Exit;
  end;
  Inc(FCompared, 4);
  if not SameNum(B.Z, IntToHex(Bits(AFx.Floats['z']), 16)) then
    Miss(Format('%s z: %s upstream, %s here', [AWhat, AFx.Find('z').AsJSON, Fmt(B.Z)]));
  if not SameNum(B.ZLevel, IntToHex(Bits(AFx.Floats['zlevel']), 16)) then
    Miss(Format('%s zlevel: %s upstream, %s here', [AWhat, AFx.Find('zlevel').AsJSON,
      Fmt(B.ZLevel)]));
  if B.Silent <> AFx.Booleans['silent'] then
    Miss(Format('%s silent: %s upstream, %s here', [AWhat,
      BoolToStr(AFx.Booleans['silent'], True), BoolToStr(B.Silent, True)]));
  if B.Count <> AFx.Integers['count'] then
    Miss(Format('%s count: %d upstream, %d here', [AWhat, AFx.Integers['count'], B.Count]));
  if B.Kind = mkLine then
    CheckJson(AWhat + ' precision', TyMkChainGet(nil, B.Own, B.Top, mkLine,
      'precision'), AFx.Find('precision'));
  items := AFx.Arrays['items'];
  case B.Kind of
    mkPoint: k := Length(B.Points);
    mkLine: k := Length(B.Lines);
  else
    k := Length(B.Areas);
  end;
  Inc(FCompared);
  if k <> items.Count then
  begin
    Miss(Format('%s: %d items upstream, %d here', [AWhat, items.Count, k]));
    Exit;
  end;
  for i := 0 to items.Count - 1 do
  begin
    it := items.Objects[i];
    w := Format('%s #%d', [AWhat, i]);
    case B.Kind of
      mkPoint:
        begin
          sv := B.Points[i].Survived;
          di := B.Points[i].DataIndex;
        end;
      mkLine:
        begin
          sv := B.Lines[i].Survived;
          di := B.Lines[i].DataIndex;
        end;
    else
      sv := B.Areas[i].Survived;
      di := B.Areas[i].DataIndex;
    end;
    Inc(FCompared);
    if sv <> it.Booleans['survived'] then
    begin
      Miss(Format('%s: survived %s upstream, %s here', [w,
        BoolToStr(it.Booleans['survived'], True), BoolToStr(sv, True)]));
      Continue;
    end;
    if not sv then Continue;
    Inc(FCompared);
    if di <> it.Integers['dataIndex'] then
      Miss(Format('%s: data index %d upstream, %d here', [w, it.Integers['dataIndex'], di]));
    case B.Kind of
      mkPoint:
        begin
          CheckEnd(w, B.Points[i].E, it, i, True);
          CheckVal(w + ' value', B.Points[i].E.Value, it.Find('value'));
          CheckVal(w + ' name', B.Points[i].E.Name, it.Find('name'));
        end;
      mkLine:
        begin
          CheckEnd(w + ' from', B.Lines[i].From, it.Objects['from'], i, True);
          CheckEnd(w + ' to', B.Lines[i].To_, it.Objects['to'], i, False);
          en := it.Objects['line'];
          CheckVal(w + ' line type', B.Lines[i].LineType, en.Find('type'));
          CheckVal(w + ' line value', B.Lines[i].LineValue, en.Find('value'));
          CheckVal(w + ' line name', B.Lines[i].LineName, en.Find('name'));
        end;
    else
      CheckPair(w + ' lt', B.Areas[i].Lt, it.Find('lt'));
      CheckPair(w + ' rb', B.Areas[i].Rb, it.Find('rb'));
      for j := 0 to 3 do
      begin
        CheckVal(Format('%s value %d', [w, j]), B.Areas[i].Values[j],
          it.Arrays['values'].Items[j]);
        CheckPoint(Format('%s corner %d', [w, j]), B.Areas[i].Points[j],
          it.Arrays['points'].Items[j]);
      end;
      CheckVal(w + ' name', B.Areas[i].Name, it.Find('name'));
      Inc(FCompared);
      if B.Areas[i].AllClipped <> it.Booleans['allClipped'] then
        Miss(Format('%s: allClipped %s upstream, %s here', [w,
          BoolToStr(it.Booleans['allClipped'], True),
          BoolToStr(B.Areas[i].AllClipped, True)]));
    end;
  end;
end;

procedure TAdvChartMarkersLayoutOracleTest.RunCases(AGallery: Boolean);
var
  cases, series: TJSONArray;
  cs, opt, se: TJSONObject;
  sl: TStringList;
  c, s, si: Integer;
  kind: TTyMarkerKind;
  b: TTyMkBlock;
  d: TJSONData;
  first: Boolean;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    d := cs.Find('gallery');
    if AGallery <> ((d <> nil) and (d.JSONType = jtString)) then Continue;
    { the cases upstream throws on have their own test }
    if not IsNull(cs.Find('error')) then Continue;
    FName := cs.Strings['id'];
    if not AGallery then
      opt := TJSONObject(cs.Objects['option'].Clone)
    else
    begin
      sl := TStringList.Create;
      try
        sl.LoadFromFile(GalleryPath(cs.Strings['gallery']));
        opt := TJSONObject(GetJSON(sl.Text));
      finally
        sl.Free;
      end;
    end;
    try
      FChart.Option := '{}';
      FChart.Option := opt.AsJSON;
      FChart.SetBounds(0, 0, cs.Integers['width'], cs.Integers['height']);
      try
        FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, cs.Integers['width'],
          cs.Integers['height']), 96);
      except
        on E: Exception do
        begin
          Miss(E.ClassName + ': ' + E.Message);
          Continue;
        end;
      end;
      series := cs.Arrays['series'];
      for s := 0 to series.Count - 1 do
      begin
        se := series.Objects[s];
        si := se.Integers['seriesIndex'];
        FName := Format('%s series %d', [cs.Strings['id'], si]);
        Inc(FSeriesSeen);
        first := True;
        for kind := Low(TTyMarkerKind) to High(TTyMarkerKind) do
        begin
          b := FChart.MarkerLayout(si, kind);
          d := se.Find(TyMarkerKey[kind]);
          if IsNull(d) then
          begin
            Inc(FCompared);
            if b.Present then Miss(TyMarkerKey[kind] + ': none upstream, a block here');
            Continue;
          end;
          { A GRID THAT LANDED ELSEWHERE moves every point with it: a gallery
            series whose axes disagree is counted and passed over }
          if first and b.Present and not AxesAgree(b, se.Arrays['axes']) then
          begin
            if AGallery then
            begin
              Inc(FSkipped);
              FSkipNames := FSkipNames + ' ' + FName;
              Break;
            end;
            Miss('the axes are not where upstream put them');
          end;
          if first and b.Present then CheckScales(b, se.Arrays['axes']);
          first := False;
          CheckBlock(TyMarkerKey[kind], b, TJSONObject(d));
        end;
      end;
    finally
      opt.Free;
    end;
  end;
end;

procedure TAdvChartMarkersLayoutOracleTest.TestMarkersAsUpstreamLaysThemOut;
begin
  RunCases(False);
  AssertTrue('the synthetic cases were run', FSeriesSeen >= 30);
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
end;

procedure TAdvChartMarkersLayoutOracleTest.TestGalleryMarkersAsUpstream;
begin
  RunCases(True);
  AssertTrue('the gallery cases were run', FSeriesSeen >= 15);
  { a gallery grid that holds its labels (containLabel) measures them
  differently here: scatter-weight's two series, '{value} kg' }
  AssertTrue(Format('%d of %d gallery series passed over:%s', [FSkipped, FSeriesSeen,
    FSkipNames]), FSkipped <= 3);
  AssertTrue(Format('%d of %d comparisons differ from upstream (%d series passed over):%s',
    [FBad, FCompared, FSkipped, FReport]), FBad = 0);
end;

procedure TAdvChartMarkersLayoutOracleTest.TestAnElementUpstreamCannotHandleIsSkipped;
var
  b: TTyMkBlock;
begin
  { a 1D markLine item with no type, xAxis or yAxis, a markArea element that
    is not a pair, a null markPoint: upstream throws out of its render; here
    each is skipped and its neighbours are kept }
  FChart.Option := '{"xAxis":{"type":"category","data":["a","b","c"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"line","data":[1,3,2],'
    + '"markPoint":{"data":[null,{"type":"max"}]},'
    + '"markLine":{"data":[{"name":"bad"},{"type":"min"},[{"type":"min"}]]},'
    + '"markArea":{"data":[{"xAxis":"a"},[{"xAxis":"a"},{"xAxis":"b"}]]}}]}';
  FChart.SetBounds(0, 0, 800, 600);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
  b := FChart.MarkerLayout(0, mkPoint);
  AssertEquals('markPoint items', 2, Length(b.Points));
  AssertFalse('a null markPoint is skipped', b.Points[0].Survived);
  AssertEquals('its neighbour is the first datum', 0, b.Points[1].DataIndex);
  b := FChart.MarkerLayout(0, mkLine);
  AssertEquals('markLine items', 3, Length(b.Lines));
  AssertFalse('a 1D line of nothing is skipped', b.Lines[0].Survived);
  AssertTrue('a min line is kept', b.Lines[1].Survived);
  AssertEquals('as the first datum', 0, b.Lines[1].DataIndex);
  AssertFalse('a pair of one is skipped', b.Lines[2].Survived);
  AssertEquals('one line', 1, b.Count);
  b := FChart.MarkerLayout(0, mkArea);
  AssertFalse('an area that is not a pair is skipped', b.Areas[0].Survived);
  AssertTrue('a pair is kept', b.Areas[1].Survived);
  AssertEquals('as the first datum', 0, b.Areas[1].DataIndex);
end;

procedure TAdvChartMarkersLayoutOracleTest.TestTheOptionIsNotMutated;
var
  before: string;
  b1, b2: TTyMkBlock;
begin
  { upstream writes into the option it is handed -- a coord for an item
    placed in pixels, numbers over 'min' / 'max' in a coord -- and a second
    render sees numbers. Here the option is read, and two renders agree. }
  FChart.Option := '{"xAxis":{"type":"value"},"yAxis":{"type":"value"},'
    + '"series":[{"type":"scatter","data":[[1,3],[4,8],[6,1]],'
    + '"markPoint":{"data":[{"x":100,"y":80},{"coord":["min","max"]}]},'
    + '"markArea":{"data":[[{"xAxis":"min"},{"xAxis":"max"}]]}}]}';
  before := FChart.Option;
  FChart.SetBounds(0, 0, 800, 600);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
  b1 := FChart.MarkerLayout(0, mkPoint);
  AssertEquals('the coord statistics', 1, b1.Points[1].E.Coord[0].Num);
  AssertEquals('the coord statistics', 8, b1.Points[1].E.Coord[1].Num);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
  b2 := FChart.MarkerLayout(0, mkPoint);
  AssertEquals('the option text is as it was', before, FChart.Option);
  AssertTrue('the second render agrees', (b1.Points[1].E.Point.X = b2.Points[1].E.Point.X)
    and (b1.Points[1].E.Point.Y = b2.Points[1].E.Point.Y));
  AssertEquals('an x / y item keeps no coord', Ord(mvkUndef),
    Ord(b2.Points[0].E.Coord[0].Kind));
end;

procedure TAdvChartMarkersLayoutOracleTest.TestTheMedianCountsTheGaps;
var b: TTyMkBlock;
begin
  { DataStore.getMedian indexes the sorted numbers by count() -- the gaps
    included: [-, 10, 20, 30, 40] has 5 rows, so the median is element 2 of
    [10, 20, 30, 40], 30, not 25 }
  FChart.Option := '{"xAxis":{"type":"category","data":["a","b","c","d","e"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"line","data":[null,10,20,30,40],'
    + '"markLine":{"data":[{"type":"median"}]}}]}';
  FChart.SetBounds(0, 0, 800, 600);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
  b := FChart.MarkerLayout(0, mkLine);
  AssertEquals('the median', 30, b.Lines[0].LineValue.Num);
end;

procedure TAdvChartMarkersLayoutOracleTest.TestASeriesSitsAtUpstreamsZ;
var
  lst: TTyPaintList;
  k, seen: Integer;
  e: TTyChartElement;
begin
  { upstream's scale, which the markers are placed on: a series at 2 (a line
    at 3), a markArea at 1 UNDER it, markPoint / markLine at 5 over it. A
    series that sat at 0 would put every markArea on top of its series. }
  FChart.Option := '{"xAxis":{"type":"category","data":["a","b","c"]},'
    + '"yAxis":{"type":"value"},"series":[{"type":"line","data":[1,3,2]},'
    + '{"type":"bar","data":[2,1,3]},{"type":"scatter","data":[1,2,3],"z":7}]}';
  FChart.SetBounds(0, 0, 800, 600);
  FChart.Render(FBmp.Canvas, Classes.Rect(0, 0, 800, 600), 96);
  lst := FChart.List;
  seen := 0;
  for k := 0 to lst.Count - 1 do
  begin
    e := lst.Element(k);
    if (e.Datum.SeriesIndex < 0) or (e.Datum.SeriesIndex > 2) then Continue;
    Inc(seen);
    if e.Datum.SeriesIndex = 2 then
      AssertEquals('an authored z', 7, e.Z)
    else if e.Datum.SeriesIndex = 0 then
      { [Batch 68: a line's default is 3 -- LineSeries.ts:161 -- and this
        asserted 2, pinning the port's mistake.] }
      AssertEquals('a line at its default z', 3, e.Z)
    else
      AssertEquals('a bar at its default z', 2, e.Z);
  end;
  AssertTrue('the series drew', seen >= 9);
end;

initialization
  RegisterTest(TAdvChartMarkersLayoutOracleTest);
end.
