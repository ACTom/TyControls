unit test.advchart.boxusage2;
{$mode objfpc}{$H+}
{ COORDINATESYSTEMUSAGE 'BOX', part two (D13 BX2, batch 154), held to what
  ECharts 6.1 answers.

  tools/advchart-oracle/box-usage2.js runs the real dist and records:

    the components  a visualMap's group, a slider's location and size, a
                    toolbox's group, a timeline's two groups, a thumbnail's
                    box and content rect, a radar's centre and radii, a
                    single axis' and a parallel's rect (and the parallel's
                    axes), a geo's view and roam -- each laid out in a
                    matrix cell or a calendar day through
                    createBoxLayoutReference, and the ones whose host is not
                    there on the canvas;
    the series      a pie and a chord centred on a cartesian's or a geo's
                    point of their coord, the axes their coords widen, a map
                    series' own geo in a cell, and convertToPixel through
                    the series a matrix is the unused coordinate system of;
    the interaction a grid in a cell under updateAxisPointer, findHover,
                    convertFromPixel and containPixel; a graph's and a geo's
                    roam in cells by action and by the wheel;
    the gallery     matrix-mini-bar-geo: twenty grids and ten geos in cells.

  This replays each through the control, bit for bit. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Convert,
     tyControls.AdvChart.Builder, tyControls.AdvChart.Series,
     tyControls.AdvChart.Data, tyControls.AdvChart.Chord,
     tyControls.AdvChart.Graph, tyControls.AdvChart.Geo,
     tyControls.AdvChart.Radar, tyControls.AdvChart.Single,
     tyControls.AdvChart.Parallel, tyControls.AdvChart.Thumbnail,
     tyControls.AdvChart.Timeline, tyControls.AdvChart.Toolbox,
     tyControls.AdvChart.DataZoomView, tyControls.AdvChart.VisualMapView,
     tyControls.AdvChart.Scale, tyControls.AdvChart.Color,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TBoxUsage2Probe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    procedure Wheel(AX, AY, ADelta: Integer);
    function Hits: TTyAxisHitArray;
    function PointerValueOf(const AHit: TTyAxisHit): Double;
    function RowsText(const AHit: TTyAxisHit): string;
    function Which: string;
  end;

  TAdvChartBoxUsage2OracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TBoxUsage2Probe;
    FBmp: TBGRABitmap;
    FRoot: TJSONData;
    FBad, FCompared, FCount: Integer;
    FName, FReport: string;
    procedure Miss(const AWhat: string);
    procedure SameH(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameRect(const AWhat: string; const R: TTyXYWH; AObj: TJSONData);
    procedure SamePair(const AWhat: string; AX, AY: Double; AArr: TJSONData);
    procedure RegisterMaps;
    procedure Paint;
    procedure Draw(ACase: TJSONObject);
    procedure Step(AStep: TJSONObject);
    procedure Verdict(AMinCount: Integer);
    procedure CheckGrids(AState: TJSONObject);
    procedure CheckComponents(AState: TJSONObject);
    procedure CheckGeos(AState: TJSONObject);
    procedure CheckSeries(AState: TJSONObject);
    procedure CheckExtents(AState: TJSONObject);
    procedure CheckCalls(AState: TJSONObject; const AKey: string; AFrom: Boolean);
    procedure CheckContains(AState: TJSONObject);
    procedure CheckHovers(AState: TJSONObject);
    procedure CheckAxes(AState: TJSONObject);
    procedure CheckTip(AState: TJSONObject);
    procedure RunGroup(const AGroup: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheComponentsAsUpstream;
    procedure TestTheSeriesAsUpstream;
    procedure TestTheInteractionAsUpstream;
    procedure TestTheGalleryAsUpstream;
    procedure TestTheBindings;
    procedure TestACoordNamingNoCellDoesNotRaise;
  end;

implementation

const
  cW = 800;
  cH = 600;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-box-usage2.json';
end;

function GalleryPath(const AName: string): string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + 'examples'
    + PathDelim + 'advchart' + PathDelim + 'gallery' + PathDelim + AName + '.json';
end;

function LoadJson(const APath: string): TJSONData;
var sl: TStringList;
begin
  sl := TStringList.Create;
  try
    sl.LoadFromFile(APath);
    Result := GetJSON(sl.Text);
  finally
    sl.Free;
  end;
end;

function FromHex(const AHex: string): Double;
var q: QWord;
begin
  Result := 0;
  q := StrToQWord('$' + AHex);
  Move(q, Result, SizeOf(Result));
end;

function H(A: TJSONData): Double;
begin
  if (A = nil) or (A.JSONType <> jtString) then Exit(NaN);
  Result := FromHex(A.AsString);
end;

function Bits(A: Double): QWord;
begin
  Move(A, Result, SizeOf(Result));
end;

function SameBits(A, B: Double): Boolean;
begin
  if IsNan(A) or IsNan(B) then Exit(IsNan(A) and IsNan(B));
  Result := Bits(A) = Bits(B);
end;

function Fmt(A: Double): string;
begin
  if IsNan(A) then Exit('NaN');
  Result := FloatToStrF(A, ffGeneral, 17, 0, DefaultFormatSettings);
end;

function IsNull(A: TJSONData): Boolean;
begin
  Result := (A = nil) or (A.JSONType = jtNull);
end;

{ ==================== the probe ==================== }

function TBoxUsage2Probe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TBoxUsage2Probe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TBoxUsage2Probe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TBoxUsage2Probe.Wheel(AX, AY, ADelta: Integer);
begin
  DoMouseWheel([], ADelta, Point(AX, AY));
end;

function TBoxUsage2Probe.Hits: TTyAxisHitArray;
begin
  Result := TipHits;
end;

function TBoxUsage2Probe.PointerValueOf(const AHit: TTyAxisHit): Double;
begin
  Result := PointerValue(AHit);
end;

function TBoxUsage2Probe.RowsText(const AHit: TTyAxisHit): string;
var
  k, s: Integer;
  st: TTyDataStore;
begin
  Result := '';
  for k := 0 to High(AHit.Slots) do
  begin
    s := SlotSeriesIndex(AHit.Slots[k]);
    st := SeriesStore(s);
    if k > 0 then Result := Result + ';';
    Result := Result + IntToStr(s) + ',' + IntToStr(st.GetRawIndex(AHit.Rows[k]))
      + ',' + IntToStr(AHit.Rows[k]);
  end;
end;

{ what the box shows, as box-usage2.js writes it (tooltip-actions' Which) }
function TBoxUsage2Probe.Which: string;
var
  snap: TTyTipSnap;
  i, k, s: Integer;
  first: Boolean;
  st: TTyDataStore;
begin
  snap := TipSnapShown;
  if Length(snap.Hits) > 0 then
  begin
    Result := 'axis:';
    first := True;
    for i := 0 to High(snap.Hits) do
    begin
      if snap.Hits[i].Cross or (snap.Hits[i].Axis = nil) then Continue;
      for k := 0 to High(snap.Hits[i].Slots) do
      begin
        s := SlotSeriesIndex(snap.Hits[i].Slots[k]);
        st := SeriesStore(s);
        if not first then Result := Result + ',';
        first := False;
        Result := Result + IntToStr(s) + '/' + IntToStr(st.GetRawIndex(snap.Hits[i].Rows[k]))
          + '@' + snap.Hits[i].Axis.Dim + IntToStr(snap.Hits[i].Axis.ComponentIndex);
      end;
    end;
    Exit;
  end;
  if snap.Datum.Kind = ctkSeries then
    Result := 'item:' + IntToStr(snap.Datum.SeriesIndex) + ':'
      + IntToStr(snap.Datum.RawDataIndex)
  else
    Result := 'other';
end;

{ ==================== the oracle ==================== }

procedure TAdvChartBoxUsage2OracleTest.SetUp;
var m: TJSONObject;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TBoxUsage2Probe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  FRoot := LoadJson(FixturePath);
  m := TJSONObject(FRoot).Objects['measure'];
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(m.Arrays['ratio'],
    m.Integers['firstCode']));
  RegisterMaps;
  FBad := 0;
  FCompared := 0;
  FCount := 0;
  FReport := '';
end;

procedure TAdvChartBoxUsage2OracleTest.TearDown;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FRoot);
  FBmp.Free;
  FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  TyChartClearMaps;
  inherited TearDown;
end;

procedure TAdvChartBoxUsage2OracleTest.RegisterMaps;
var
  maps: TJSONArray;
  i: Integer;
begin
  TyChartClearMaps;
  maps := TJSONObject(FRoot).Arrays['maps'];
  for i := 0 to maps.Count - 1 do
    AssertTrue('registered ' + maps.Objects[i].Strings['name'],
      TyChartRegisterMap(maps.Objects[i].Strings['name'], maps.Objects[i].Strings['text']));
end;

procedure TAdvChartBoxUsage2OracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartBoxUsage2OracleTest.SameH(const AWhat: string; AGot: Double;
  AWant: TJSONData);
begin
  Inc(FCompared);
  if not SameBits(AGot, H(AWant)) then
    Miss(Format('%s: %s here, %s upstream', [AWhat, Fmt(AGot), Fmt(H(AWant))]));
end;

procedure TAdvChartBoxUsage2OracleTest.SameRect(const AWhat: string; const R: TTyXYWH;
  AObj: TJSONData);
begin
  if not (AObj is TJSONObject) then
  begin
    Inc(FCompared);
    Miss(AWhat + ': no rect upstream');
    Exit;
  end;
  SameH(AWhat + ' x', R.X, TJSONObject(AObj).Find('x'));
  SameH(AWhat + ' y', R.Y, TJSONObject(AObj).Find('y'));
  SameH(AWhat + ' width', R.W, TJSONObject(AObj).Find('width'));
  SameH(AWhat + ' height', R.H, TJSONObject(AObj).Find('height'));
end;

procedure TAdvChartBoxUsage2OracleTest.SamePair(const AWhat: string; AX, AY: Double;
  AArr: TJSONData);
begin
  if not (AArr is TJSONArray) or (AArr.Count < 2) then
  begin
    Inc(FCompared);
    Miss(AWhat + ': no pair upstream');
    Exit;
  end;
  SameH(AWhat + ' [0]', AX, AArr.Items[0]);
  SameH(AWhat + ' [1]', AY, AArr.Items[1]);
end;

procedure TAdvChartBoxUsage2OracleTest.Paint;
begin
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
end;

procedure TAdvChartBoxUsage2OracleTest.Draw(ACase: TJSONObject);
var
  opt: TJSONObject;
  d: TJSONData;
begin
  FName := ACase.Strings['id'];
  d := ACase.Find('gallery');
  if (d <> nil) and (d.JSONType = jtString) then
    opt := TJSONObject(LoadJson(GalleryPath(d.AsString)))
  else
    opt := TJSONObject(ACase.Objects['option'].Clone);
  try
    opt.Booleans['animation'] := False;
    FChart.SetBounds(0, 0, cW, cH);
    FChart.Option := '{}';
    FChart.Option := opt.AsJSON;
    Paint;
  finally
    opt.Free;
  end;
end;

procedure TAdvChartBoxUsage2OracleTest.Step(AStep: TJSONObject);
var w: TJSONArray;
begin
  if AStep.Find('action') is TJSONObject then
    FChart.DispatchAction(AStep.Objects['action'].AsJSON)
  else if AStep.Find('wheel') is TJSONArray then
  begin
    w := AStep.Arrays['wheel'];
    FChart.Wheel(w.Integers[0], w.Integers[1], w.Integers[2]);
  end;
  Paint;
end;

procedure TAdvChartBoxUsage2OracleTest.Verdict(AMinCount: Integer);
begin
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('enough was compared (%d of at least %d)', [FCount, AMinCount]),
    FCount >= AMinCount);
end;

{ ---- the grids ---- }

procedure TAdvChartBoxUsage2OracleTest.CheckGrids(AState: TJSONObject);
var
  arr: TJSONArray;
  g: TJSONObject;
  k, q: Integer;
  gb: TTyGridBuild;
begin
  arr := AState.Arrays['grids'];
  for k := 0 to arr.Count - 1 do
  begin
    g := arr.Objects[k];
    gb := nil;
    for q := 0 to FChart.Build.GridCount - 1 do
      if FChart.Build.Grid(q).ComponentIndex = g.Integers['index'] then gb := FChart.Build.Grid(q);
    Inc(FCompared);
    if gb = nil then
    begin
      Miss(Format('no grid %d here', [g.Integers['index']]));
      Continue;
    end;
    Inc(FCount);
    if gb.Boxed <> g.Booleans['boxed'] then
      Miss(Format('grid %d boxed %s here', [g.Integers['index'], BoolToStr(gb.Boxed, True)]));
    SameRect(Format('grid %d rect', [g.Integers['index']]), gb.PlotXYWH, g.Find('rect'));
  end;
end;

{ ---- the components ---- }

procedure TAdvChartBoxUsage2OracleTest.CheckComponents(AState: TJSONObject);
var
  arr, axes: TJSONArray;
  o: TJSONObject;
  k, idx, a: Integer;
  w: string;
  vm: TTyVisualMapLayout;
  dz: TTyDzSliderLayout;
  tb: TTyToolboxLayout;
  tl: TTyTimelineView;
  th: TTyThumbState;
  rd: TTyRadar;
  sg: TTySingle;
  pr: TTyParallel;
begin
  arr := AState.Arrays['visualMaps'];
  for k := 0 to arr.Count - 1 do
  begin
    o := arr.Objects[k];
    idx := o.Integers['index'];
    w := Format('visualMap %d', [idx]);
    vm := FChart.VisualMapLayout(idx);
    Inc(FCompared);
    if not vm.Valid then begin Miss(w + ': not laid out here'); Continue; end;
    Inc(FCount);
    SamePair(w + ' group', vm.GroupX, vm.GroupY, o.Find('group'));
  end;
  arr := AState.Arrays['sliders'];
  for k := 0 to arr.Count - 1 do
  begin
    o := arr.Objects[k];
    idx := o.Integers['index'];
    w := Format('slider %d', [idx]);
    dz := FChart.DataZoomSliderLayout(idx);
    Inc(FCompared);
    if not dz.Valid then begin Miss(w + ': not laid out here'); Continue; end;
    Inc(FCount);
    SamePair(w + ' location', dz.LocX, dz.LocY, o.Find('location'));
    SamePair(w + ' size', dz.L, dz.T, o.Find('size'));
  end;
  arr := AState.Arrays['toolboxes'];
  for k := 0 to arr.Count - 1 do
  begin
    o := arr.Objects[k];
    idx := o.Integers['index'];
    w := Format('toolbox %d', [idx]);
    tb := FChart.ToolboxLayout(idx);
    Inc(FCompared);
    if not tb.Valid then begin Miss(w + ': not laid out here'); Continue; end;
    Inc(FCount);
    SamePair(w + ' group', tb.GroupX, tb.GroupY, o.Find('group'));
  end;
  arr := AState.Arrays['timelines'];
  for k := 0 to arr.Count - 1 do
  begin
    o := arr.Objects[k];
    w := 'timeline';
    tl := FChart.TimelineView;
    Inc(FCompared);
    if (tl = nil) or (tl.MainGroup = nil) or (tl.LabelGroup = nil) then
    begin
      Miss(w + ': no view here');
      Continue;
    end;
    Inc(FCount);
    SamePair(w + ' main', tl.MainGroup.X, tl.MainGroup.Y, o.Find('main'));
    SamePair(w + ' label', tl.LabelGroup.X, tl.LabelGroup.Y, o.Find('label'));
  end;
  arr := AState.Arrays['thumbnails'];
  for k := 0 to arr.Count - 1 do
  begin
    o := arr.Objects[k];
    idx := o.Integers['index'];
    w := Format('thumbnail %d', [idx]);
    th := FChart.ThumbnailState(idx);
    Inc(FCompared);
    if not th.Enabled then begin Miss(w + ': not enabled here'); Continue; end;
    Inc(FCount);
    SameRect(w + ' box', th.Box, o.Find('box'));
    SameRect(w + ' content', th.Content, o.Find('content'));
  end;
  arr := AState.Arrays['radars'];
  for k := 0 to arr.Count - 1 do
  begin
    o := arr.Objects[k];
    idx := o.Integers['index'];
    w := Format('radar %d', [idx]);
    rd := FChart.RadarLayout(idx);
    Inc(FCompared);
    if (rd = nil) or not rd.Valid then begin Miss(w + ': not laid out here'); Continue; end;
    Inc(FCount);
    SameH(w + ' cx', rd.CX, o.Find('cx'));
    SameH(w + ' cy', rd.CY, o.Find('cy'));
    SameH(w + ' r0', rd.R0, o.Find('r0'));
    SameH(w + ' r', rd.R1, o.Find('r'));
  end;
  arr := AState.Arrays['singles'];
  for k := 0 to arr.Count - 1 do
  begin
    o := arr.Objects[k];
    idx := o.Integers['index'];
    w := Format('singleAxis %d', [idx]);
    sg := FChart.SingleLayout(idx);
    Inc(FCompared);
    if sg = nil then begin Miss(w + ': not built here'); Continue; end;
    Inc(FCount);
    SameRect(w + ' rect', sg.Rect, o.Find('rect'));
  end;
  arr := AState.Arrays['parallels'];
  for k := 0 to arr.Count - 1 do
  begin
    o := arr.Objects[k];
    idx := o.Integers['index'];
    w := Format('parallel %d', [idx]);
    pr := FChart.ParallelLayout(idx);
    Inc(FCompared);
    if pr = nil then begin Miss(w + ': not built here'); Continue; end;
    Inc(FCount);
    SameRect(w + ' rect', pr.Rect, o.Find('rect'));
    axes := o.Arrays['axes'];
    Inc(FCompared);
    if Length(pr.Layouts) <> axes.Count then
    begin
      Miss(Format('%s: %d axes here, %d upstream', [w, Length(pr.Layouts), axes.Count]));
      Continue;
    end;
    for a := 0 to axes.Count - 1 do
      SamePair(Format('%s axis %d', [w, a]), pr.Layouts[a].PosX, pr.Layouts[a].PosY,
        axes.Objects[a].Find('position'));
  end;
end;

procedure TAdvChartBoxUsage2OracleTest.CheckGeos(AState: TJSONObject);
var
  arr, roam: TJSONArray;
  o: TJSONObject;
  k, idx: Integer;
  geo: TTyGeo;
  w: string;
begin
  arr := AState.Arrays['geos'];
  for k := 0 to arr.Count - 1 do
  begin
    o := arr.Objects[k];
    idx := o.Integers['index'];
    w := Format('geo %d', [idx]);
    geo := FChart.GeoLayout(idx);
    Inc(FCompared);
    if (geo = nil) or not geo.Valid then begin Miss(w + ': not laid out here'); Continue; end;
    Inc(FCount);
    SameRect(w + ' view', geo.ViewRect, o.Find('view'));
    { getRoamTransform: [scaleX, 0, 0, scaleY, x, y] }
    roam := o.Arrays['roam'];
    SameH(w + ' roam scaleX', geo.RoamTrans.ScaleX, roam.Items[0]);
    SameH(w + ' roam scaleY', geo.RoamTrans.ScaleY, roam.Items[3]);
    SameH(w + ' roam x', geo.RoamTrans.X, roam.Items[4]);
    SameH(w + ' roam y', geo.RoamTrans.Y, roam.Items[5]);
  end;
end;

{ ---- the series ---- }

procedure TAdvChartBoxUsage2OracleTest.CheckSeries(AState: TJSONObject);
var
  arr, secs, nodes: TJSONArray;
  s, sj, nd: TJSONObject;
  k, j, q, i, si: Integer;
  t, w: string;
  lst: TTyPaintList;
  e: TTyChartElement;
  found: Boolean;
  ch: TTyChordSolved;
  geo: TTyGeo;
  gv: TTyGraphView;
  gn: TTyGraphNodeArray;
  ge: TTyGraphEdgeArray;
  gf: TTyChartColorArray;
  pt: TTyPointF;
begin
  arr := AState.Arrays['series'];
  lst := FChart.List;
  for k := 0 to arr.Count - 1 do
  begin
    s := arr.Objects[k];
    si := s.Integers['seriesIndex'];
    t := s.Strings['type'];
    w := Format('series %d (%s)', [si, t]);
    if t = 'pie' then
    begin
      secs := s.Arrays['sectors'];
      for j := 0 to secs.Count - 1 do
      begin
        sj := secs.Objects[j];
        found := False;
        for q := 0 to lst.Count - 1 do
        begin
          e := lst.Element(q);
          if (e.Datum.SeriesIndex <> si) or (e.Shape.Kind <> cskSector)
            or (e.Datum.RawDataIndex <> sj.Integers['i']) then Continue;
          found := True;
          Inc(FCount);
          SameH(Format('%s sector %d cx', [w, j]), e.Shape.CX, sj.Find('cx'));
          SameH(Format('%s sector %d cy', [w, j]), e.Shape.CY, sj.Find('cy'));
          SameH(Format('%s sector %d r0', [w, j]), e.Shape.R0, sj.Find('r0'));
          SameH(Format('%s sector %d r', [w, j]), e.Shape.R1, sj.Find('r'));
          Break;
        end;
        Inc(FCompared);
        if not found then Miss(Format('%s sector %d: none here', [w, j]));
      end;
    end
    else if t = 'chord' then
    begin
      ch := FChart.ChordSolved(si);
      secs := s.Arrays['sectors'];
      Inc(FCompared);
      if secs.Count = 0 then
      begin
        if ch.Valid and (Length(ch.Nodes) > 0) then Miss(w + ': drawn here, not upstream');
        Continue;
      end;
      if not ch.Valid then begin Miss(w + ': not solved here'); Continue; end;
      Inc(FCount);
      sj := secs.Objects[0];
      SameH(w + ' cx', ch.CX, sj.Find('cx'));
      SameH(w + ' cy', ch.CY, sj.Find('cy'));
      SameH(w + ' r0', ch.R0, sj.Find('r0'));
      SameH(w + ' r', ch.R, sj.Find('r'));
    end
    else if t = 'map' then
    begin
      geo := FChart.MapGeoOf(si);
      Inc(FCompared);
      if (geo = nil) or not geo.Valid then begin Miss(w + ': no geo here'); Continue; end;
      Inc(FCount);
      SameRect(w + ' view', geo.ViewRect, s.Find('view'));
    end
    else if t = 'graph' then
    begin
      gv := FChart.GraphView(si);
      Inc(FCompared);
      if (gv = nil) or not FChart.GraphLayout(si, gn, ge, gf) then
      begin
        Miss(w + ': no view here');
        Continue;
      end;
      Inc(FCount);
      SameRect(w + ' view', gv.ViewXYWH, s.Find('view'));
      nodes := s.Arrays['nodes'];
      for j := 0 to nodes.Count - 1 do
      begin
        nd := nodes.Objects[j];
        i := nd.Integers['i'];
        Inc(FCompared);
        if i > High(gn) then begin Miss(Format('%s: no node %d', [w, i])); Continue; end;
        pt := gv.DataToPoint([gn[i].X, gn[i].Y]);
        SameH(Format('%s node %d x', [w, i]), pt.X, nd.Find('x'));
        SameH(Format('%s node %d y', [w, i]), pt.Y, nd.Find('y'));
      end;
    end;
  end;
end;

procedure TAdvChartBoxUsage2OracleTest.CheckExtents(AState: TJSONObject);
var
  arr: TJSONArray;
  o: TJSONObject;
  k: Integer;
  ax: TTyAxis;
  r: TTyRange;
  w: string;
begin
  arr := AState.Arrays['extents'];
  for k := 0 to arr.Count - 1 do
  begin
    o := arr.Objects[k];
    w := Format('%s %d extent', [o.Strings['dim'], o.Integers['index']]);
    ax := FChart.Build.Axis(o.Strings['dim'], o.Integers['index']);
    Inc(FCompared);
    if ax = nil then begin Miss(w + ': no axis here'); Continue; end;
    Inc(FCount);
    r := ax.Scale.GetExtent;
    SameH(w + ' lo', r.Start, o.Arrays['extent'].Items[0]);
    SameH(w + ' hi', r.Stop, o.Arrays['extent'].Items[1]);
  end;
end;

procedure TAdvChartBoxUsage2OracleTest.CheckCalls(AState: TJSONObject;
  const AKey: string; AFrom: Boolean);
var
  arr: TJSONArray;
  c: TJSONObject;
  k, j: Integer;
  cv: TTyConvertResult;
  ret: TJSONData;
  w: string;
begin
  arr := AState.Arrays[AKey];
  for k := 0 to arr.Count - 1 do
  begin
    c := arr.Objects[k];
    w := Format('%s %s %s', [AKey, c.Find('finder').AsJSON, c.Find('value').AsJSON]);
    if AFrom then cv := FChart.ConvertFromPixelData(c.Find('finder'), c.Find('value'))
    else cv := FChart.ConvertToPixelData(c.Find('finder'), c.Find('value'));
    ret := c.Find('ret');
    Inc(FCount);
    Inc(FCompared);
    if IsNull(ret) then
    begin
      if cv.Kind <> cvkNone then Miss(w + ': an answer here, none upstream');
      Continue;
    end;
    if (cv.Kind <> cvkArray) or (Length(cv.Values) <> ret.Count) then
    begin
      Miss(Format('%s: kind %d, %d values here', [w, Ord(cv.Kind), Length(cv.Values)]));
      Continue;
    end;
    for j := 0 to ret.Count - 1 do
      SameH(Format('%s [%d]', [w, j]), cv.Values[j], TJSONArray(ret).Items[j]);
  end;
end;

procedure TAdvChartBoxUsage2OracleTest.CheckContains(AState: TJSONObject);
var
  arr: TJSONArray;
  c: TJSONObject;
  k: Integer;
  got: Boolean;
begin
  arr := AState.Arrays['contains'];
  for k := 0 to arr.Count - 1 do
  begin
    c := arr.Objects[k];
    got := FChart.ContainPixelData(c.Find('finder'), c.Find('value'));
    Inc(FCount);
    Inc(FCompared);
    if got <> c.Booleans['ret'] then
      Miss(Format('containPixel %s %s: %s here', [c.Find('finder').AsJSON,
        c.Find('value').AsJSON, BoolToStr(got, True)]));
  end;
end;

procedure TAdvChartBoxUsage2OracleTest.CheckHovers(AState: TJSONObject);
var
  arr: TJSONArray;
  c: TJSONObject;
  k: Integer;
  d: TTyChartDatumRef;
  hit: TJSONData;
  w: string;
begin
  arr := AState.Arrays['hovers'];
  for k := 0 to arr.Count - 1 do
  begin
    c := arr.Objects[k];
    w := 'findHover ' + c.Find('at').AsJSON;
    d := FChart.HitTestAt(c.Arrays['at'].Integers[0], c.Arrays['at'].Integers[1]);
    hit := c.Find('hit');
    Inc(FCount);
    Inc(FCompared);
    if IsNull(hit) then
    begin
      if (d.Kind = ctkSeries) and (d.SeriesIndex >= 0) then
        Miss(Format('%s: series %d row %d here, nothing upstream', [w, d.SeriesIndex, d.RawDataIndex]));
      Continue;
    end;
    if (d.Kind <> ctkSeries) or (d.SeriesIndex <> TJSONObject(hit).Integers['seriesIndex'])
      or (d.RawDataIndex <> TJSONObject(hit).Integers['dataIndex']) then
      Miss(Format('%s: series %d row %d here, upstream %s', [w, d.SeriesIndex,
        d.RawDataIndex, hit.AsJSON]));
  end;
end;

procedure TAdvChartBoxUsage2OracleTest.CheckAxes(AState: TJSONObject);
var
  axes, sdi: TJSONArray;
  ax: TJSONObject;
  hits: TTyAxisHitArray;
  k, c, h, n, j: Integer;
  key, want: string;
begin
  hits := FChart.Hits;
  axes := AState.Arrays['axes'];
  n := 0;
  for k := 0 to axes.Count - 1 do
  begin
    ax := axes.Objects[k];
    key := ax.Strings['dim'] + IntToStr(ax.Integers['index']);
    h := -1;
    for c := 0 to High(hits) do
      if (hits[c].Axis.Dim = ax.Strings['dim'])
        and (hits[c].Axis.ComponentIndex = ax.Integers['index']) then h := c;
    Inc(FCompared);
    Inc(FCount);
    if (ax.Strings['status'] = 'show') <> (h >= 0) then
    begin
      Miss(Format('pointer %s: shown %s here, upstream %s', [key,
        BoolToStr(h >= 0, True), ax.Strings['status']]));
      Continue;
    end;
    if h < 0 then Continue;
    Inc(n);
    SameH('pointer ' + key + ' value', FChart.PointerValueOf(hits[h]), ax.Find('value'));
    sdi := ax.Arrays['sdi'];
    want := '';
    for j := 0 to sdi.Count - 1 do
    begin
      if j > 0 then want := want + ';';
      want := want + Format('%d,%d,%d', [sdi.Arrays[j].Integers[0], sdi.Arrays[j].Integers[1],
        sdi.Arrays[j].Integers[2]]);
    end;
    Inc(FCompared);
    if FChart.RowsText(hits[h]) <> want then
      Miss(Format('pointer %s rows %s here, upstream %s', [key, FChart.RowsText(hits[h]), want]));
  end;
  Inc(FCompared);
  if n <> Length(hits) then
    Miss(Format('%d pointers here, upstream %d', [Length(hits), n]));
end;

procedure TAdvChartBoxUsage2OracleTest.CheckTip(AState: TJSONObject);
var
  tip: TJSONObject;
  shown: Boolean;
  at: TTyPointF;
begin
  if not (AState.Find('tip') is TJSONObject) then Exit;
  tip := AState.Objects['tip'];
  shown := FChart.TooltipShown;
  Inc(FCount);
  Inc(FCompared);
  if shown <> tip.Booleans['visible'] then
  begin
    Miss(Format('the box shown %s here', [BoolToStr(shown, True)]));
    Exit;
  end;
  Inc(FCompared);
  if FChart.TooltipShowFlag <> tip.Booleans['show'] then
    Miss(Format('_show %s here', [BoolToStr(FChart.TooltipShowFlag, True)]));
  if not shown then Exit;
  Inc(FCompared);
  if FChart.Which <> tip.Strings['which'] then
    Miss(Format('the box shows %s here, upstream %s', [FChart.Which, tip.Strings['which']]));
  at := FChart.TooltipAnchorF;
  SamePair('the anchor', at.X, at.Y, tip.Find('anchor'));
end;

procedure TAdvChartBoxUsage2OracleTest.RunGroup(const AGroup: string);
var
  cases, steps, states: TJSONArray;
  cs, st: TJSONObject;
  c, k: Integer;
  base: string;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if cs.Strings['group'] <> AGroup then Continue;
    Draw(cs);
    base := FName;
    steps := cs.Arrays['steps'];
    states := cs.Arrays['states'];
    for k := 0 to states.Count - 1 do
    begin
      if k > 0 then Step(steps.Objects[k - 1]);
      FName := Format('%s state %d', [base, k]);
      st := states.Objects[k];
      CheckGrids(st);
      CheckComponents(st);
      CheckGeos(st);
      CheckSeries(st);
      CheckExtents(st);
      CheckCalls(st, 'calls', False);
      CheckCalls(st, 'backs', True);
      CheckContains(st);
      CheckHovers(st);
      CheckAxes(st);
      CheckTip(st);
    end;
  end;
end;

procedure TAdvChartBoxUsage2OracleTest.TestTheComponentsAsUpstream;
begin
  RunGroup('component');
  Verdict(35);
end;

procedure TAdvChartBoxUsage2OracleTest.TestTheSeriesAsUpstream;
begin
  RunGroup('series');
  Verdict(30);
end;

procedure TAdvChartBoxUsage2OracleTest.TestTheInteractionAsUpstream;
begin
  RunGroup('interact');
  Verdict(40);
end;

procedure TAdvChartBoxUsage2OracleTest.TestTheGalleryAsUpstream;
begin
  RunGroup('gallery');
  Verdict(30);
end;

{ ---- around the oracle ---- }

{ a box usage on a host of only a dataToPoint: on no coordinate system, the
  pair or the geo only its point's; usage 'data' on a cartesian is the
  cartesian's; a canvas type with usage 'data' on a matrix keeps the matrix
  for conversions, one with 'box' does not }
procedure TAdvChartBoxUsage2OracleTest.TestTheBindings;
var
  b: TTySeriesBindingArray;
  opt: TTyChartOption;
  build: TTyChartBuild;
begin
  opt := TTyChartOption.Create;
  try
    AssertTrue('parses', opt.SetOptionText('{"matrix": {"x": {"data": ["a"]}, "y": {"data": ["p"]}},'
      + ' "geo": {"map": "bx2sq"}, "xAxis": {}, "yAxis": {}, "series": ['
      + '{"type": "pie", "coordinateSystem": "cartesian2d", "coord": [1, 2]},'
      + '{"type": "chord", "coordinateSystem": "cartesian2d", "coordinateSystemUsage": "box", "coord": [1, 2]},'
      + '{"type": "chord", "coordinateSystem": "cartesian2d"},'
      + '{"type": "pie", "coordinateSystem": "geo", "coordinateSystemUsage": "data"},'
      + '{"type": "gauge", "coordinateSystem": "matrix"},'
      + '{"type": "sunburst", "coordinateSystem": "matrix", "coordinateSystemUsage": "box"},'
      + '{"type": "funnel", "coordinateSystem": "cartesian2d", "coord": [3, 4]},'
      + '{"type": "pie", "coordinateSystem": "geo", "geoIndex": 4}]}'));
    build := TyBuildGrids(opt, TyRectF(0, 0, cW, cH));
    try
      b := TyBindSeries(opt, build);
      AssertTrue('a pie on a cartesian resolves', b[0].Resolved);
      AssertTrue('it takes a point', b[0].BoxPoint);
      AssertTrue('from the pair', b[0].BoxCart <> nil);
      AssertTrue('and is on no cartesian', (b[0].Cart = nil) and (b[0].XAxis = nil));
      AssertTrue('its coord widens x and y', (b[0].BoxXAxis <> nil) and (b[0].BoxYAxis <> nil));
      AssertTrue('a chord that says box takes a point', b[1].BoxPoint and (b[1].BoxCart <> nil));
      AssertTrue('a chord with usage data is on the cartesian, with no point',
        (b[2].Cart <> nil) and not b[2].BoxPoint and (b[2].BoxCart = nil));
      AssertTrue('a pie with usage data on a geo takes no point', (b[3].GeoIndex = 0) and not b[3].BoxPoint);
      AssertTrue('a gauge with usage data keeps the matrix to convert through',
        b[4].HasDataMatrix and (b[4].DataMatrix = 0));
      AssertFalse('a sunburst with usage box does not', b[5].HasDataMatrix);
      AssertTrue('a funnel with box on a cartesian lays itself out on the canvas, its coord on the axes',
        b[6].Resolved and not b[6].BoxPoint and (b[6].BoxCart <> nil) and (b[6].Cart = nil));
      AssertTrue('a pie whose geo is not there is on the canvas',
        b[7].Resolved and not b[7].BoxPoint and (b[7].GeoIndex = -1));
    finally
      build.Free;
    end;
  finally
    opt.Free;
  end;
end;

{ every component this batch puts in cells, with a coord that names no cell
  (no size) and one on a day off the calendar (a size and no place): laid
  out twice without raising }
procedure TAdvChartBoxUsage2OracleTest.TestACoordNamingNoCellDoesNotRaise;
var k: Integer;
begin
  FChart.SetBounds(0, 0, cW, cH);
  for k := 0 to 1 do
  begin
    if k = 0 then
      FChart.Option := '{"animation": false, "matrix": {"x": {"data": ["a", "b"]}, "y": {"data": ["p"]}},'
        + ' "visualMap": {"min": 0, "max": 1, "coordinateSystem": "matrix", "coord": ["zz", "p"]},'
        + ' "grid": {}, "xAxis": {}, "yAxis": {},'
        + ' "dataZoom": {"type": "slider", "coordinateSystem": "matrix", "coord": ["zz", "p"]},'
        + ' "toolbox": {"coordinateSystem": "matrix", "coord": ["zz", "zz"], "feature": {"restore": {}}},'
        + ' "timeline": {"coordinateSystem": "matrix", "coord": ["zz", "p"], "axisType": "category", "data": ["x", "y"]},'
        + ' "radar": {"coordinateSystem": "matrix", "coord": ["zz", "p"], "indicator": [{"max": 1}, {"max": 1}, {"max": 1}]},'
        + ' "singleAxis": {"coordinateSystem": "matrix", "coord": ["zz", "p"]},'
        + ' "parallel": {"coordinateSystem": "matrix", "coord": ["zz", "p"]}, "parallelAxis": [{"dim": 0}, {"dim": 1}],'
        + ' "geo": {"map": "bx2sq", "coordinateSystem": "matrix", "coord": ["zz", "p"]},'
        + ' "series": [{"type": "line", "data": [[0, 0], [1, 1]]},'
        + '  {"type": "radar", "data": [{"value": [1, 1, 1]}]},'
        + '  {"type": "scatter", "coordinateSystem": "singleAxis", "data": [1]},'
        + '  {"type": "parallel", "data": [[1, 2]]},'
        + '  {"type": "map", "map": "bx2sq", "coordinateSystem": "matrix", "coordinateSystemUsage": "box", "coord": ["zz", "p"]},'
        + '  {"type": "pie", "coordinateSystem": "geo", "coord": [1, 1], "data": [1]}]}'
    else
      FChart.Option := '{"animation": false, "calendar": {"range": "2017-02"},'
        + ' "radar": {"coordinateSystem": "calendar", "coord": "2019-01-01", "indicator": [{"max": 1}, {"max": 1}, {"max": 1}]},'
        + ' "singleAxis": {"coordinateSystem": "calendar", "coord": "2019-01-01"},'
        + ' "geo": {"map": "bx2sq", "coordinateSystem": "calendar", "coord": "2019-01-01"},'
        + ' "toolbox": {"coordinateSystem": "calendar", "coord": "2019-01-01", "feature": {"restore": {}}},'
        + ' "series": [{"type": "radar", "data": [{"value": [1, 1, 1]}]},'
        + '  {"type": "scatter", "coordinateSystem": "singleAxis", "data": [1]}]}';
    FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
    FChart.Render(FBmp.Canvas, Rect(0, 0, cW - 100, cH - 100), 96);
  end;
  { the geo of no cell is out of sight; the single axis is far off the
    canvas -- upstream's not-a-number rects draw nothing }
  AssertTrue('the single axis on a day of no place keeps a size', FChart.SingleLayout(0) <> nil);
end;

initialization
  RegisterTest(TAdvChartBoxUsage2OracleTest);
end.
