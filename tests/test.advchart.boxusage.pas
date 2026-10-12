unit test.advchart.boxusage;
{$mode objfpc}{$H+}
{ COORDINATESYSTEMUSAGE 'BOX', part one (D13 BX1, batch 151), held to what
  ECharts 6.1 answers.

  tools/advchart-oracle/box-usage.js runs the real dist and records, for
  components and series laid out in a matrix cell or a calendar day through
  createBoxLayoutReference:

    the grids     each grid's rect after its outer bounds, and
                  convertToPixel through it;
    the polars    each polar's centre and radius extent, and convertToPixel;
    the titles    the group's place, the background, the align;
    the legends   the group's place and every item's place and box;
    the series    a pie's and a chord's sectors, a funnel's trapezoids, a
                  sankey's, a tree's and a treemap's box and nodes (and the
                  treemap's breadcrumb), a graph's view and its nodes, and
                  the gauge and the sunburst that stay on the canvas;
    the gallery   matrix-stock: five grids and four titles in its cells.

  This replays each through the control, bit for bit. }
interface
uses Classes, SysUtils, Math, fpcunit, testregistry, fpjson, jsonparser,
     Controls, Graphics, Forms, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Option,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Shape, tyControls.AdvChart.Color,
     tyControls.AdvChart.Coord, tyControls.AdvChart.Convert,
     tyControls.AdvChart.Builder, tyControls.AdvChart.Series,
     tyControls.AdvChart.Polar, tyControls.AdvChart.Title,
     tyControls.AdvChart.Legend, tyControls.AdvChart.Sankey,
     tyControls.AdvChart.Tree, tyControls.AdvChart.Treemap,
     tyControls.AdvChart.Graph, tyControls.AdvChart.Chord,
     tyControls.AdvChart.Sunburst,
     tyControls.AdvanceChart,
     test.advchart.gridbounds, test.advchart.categoryminmax;
type
  TBoxUsageProbe = class(TTyAdvanceChart)
  protected
    function NewTextMeasurer(APPI: Integer): ITyTextMeasurer; override;
  public
    Measurer: ITyTextMeasurer;
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
  end;

  TAdvChartBoxUsageOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TBoxUsageProbe;
    FBmp: TBGRABitmap;
    FRoot: TJSONData;
    FBad, FCompared, FCount: Integer;
    FName, FReport: string;
    procedure Miss(const AWhat: string);
    procedure SameH(const AWhat: string; AGot: Double; AWant: TJSONData);
    procedure SameRect(const AWhat: string; const R: TTyXYWH; AObj: TJSONData);
    procedure SameX(const AWhat: string; AGot, AWant: Double);
    procedure Draw(ACase: TJSONObject);
    procedure Verdict(AMinCount: Integer);
    procedure CheckGrids(ACase: TJSONObject);
    procedure CheckCalls(ACase: TJSONObject);
    procedure CheckPolars(ACase: TJSONObject);
    procedure CheckTitles(ACase: TJSONObject);
    procedure CheckLegends(ACase: TJSONObject);
    procedure CheckSeries(ACase: TJSONObject);
    procedure CheckPie(ASeries: TJSONObject);
    procedure CheckFunnel(ASeries: TJSONObject);
    procedure EachCase(AKind: Integer);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTheGridsAsUpstream;
    procedure TestTheConversionsAsUpstream;
    procedure TestThePolarsAsUpstream;
    procedure TestTheTitlesAsUpstream;
    procedure TestTheLegendsAsUpstream;
    procedure TestTheSeriesAsUpstream;
    procedure TestTheFallbacksAreOnTheCanvas;
    procedure TestACoordNamingNoCellDoesNotRaise;
    procedure TestTheComponentUsageRule;
  end;

implementation

const
  cW = 800;
  cH = 600;
  ckGrids = 0;
  ckCalls = 1;
  ckPolars = 2;
  ckTitles = 3;
  ckLegends = 4;
  ckSeries = 5;

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-box-usage.json';
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

function TBoxUsageProbe.NewTextMeasurer(APPI: Integer): ITyTextMeasurer;
begin
  if Measurer <> nil then Result := Measurer
  else Result := inherited NewTextMeasurer(APPI);
end;

procedure TBoxUsageProbe.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TBoxUsageProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

{ ==================== the oracle ==================== }

procedure TAdvChartBoxUsageOracleTest.SetUp;
var m: TJSONObject;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TBoxUsageProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(cW, cH, BGRA(255, 255, 255, 255));
  AssertTrue('the fixture is where the suite expects it', FileExists(FixturePath));
  FRoot := LoadJson(FixturePath);
  m := TJSONObject(FRoot).Objects['measure'];
  FChart.Measurer := TPtToPxMeasurer.Create(TZrSsrMeasurer.Create(m.Arrays['ratio'],
    m.Integers['firstCode']));
  FBad := 0;
  FCompared := 0;
  FCount := 0;
  FReport := '';
end;

procedure TAdvChartBoxUsageOracleTest.TearDown;
begin
  if FChart <> nil then FChart.Measurer := nil;
  FreeAndNil(FRoot);
  FBmp.Free;
  FChart.Controller := nil;
  FForm.Free;
  FCtl.Free;
  inherited TearDown;
end;

procedure TAdvChartBoxUsageOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartBoxUsageOracleTest.SameH(const AWhat: string; AGot: Double;
  AWant: TJSONData);
begin
  Inc(FCompared);
  if not SameBits(AGot, H(AWant)) then
    Miss(Format('%s: %s here, %s upstream', [AWhat, Fmt(AGot), Fmt(H(AWant))]));
end;

procedure TAdvChartBoxUsageOracleTest.SameX(const AWhat: string; AGot, AWant: Double);
begin
  Inc(FCompared);
  if not SameBits(AGot, AWant) then
    Miss(Format('%s: %s here, %s upstream', [AWhat, Fmt(AGot), Fmt(AWant)]));
end;

procedure TAdvChartBoxUsageOracleTest.SameRect(const AWhat: string; const R: TTyXYWH;
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

procedure TAdvChartBoxUsageOracleTest.Draw(ACase: TJSONObject);
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
    FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
  finally
    opt.Free;
  end;
end;

procedure TAdvChartBoxUsageOracleTest.Verdict(AMinCount: Integer);
begin
  AssertTrue(Format('%d of %d comparisons differ from upstream:%s',
    [FBad, FCompared, FReport]), FBad = 0);
  AssertTrue(Format('enough was compared (%d of at least %d)', [FCount, AMinCount]),
    FCount >= AMinCount);
end;

{ ---- the grids: the rect after the outer bounds ---- }

procedure TAdvChartBoxUsageOracleTest.CheckGrids(ACase: TJSONObject);
var
  arr: TJSONArray;
  g: TJSONObject;
  k, q: Integer;
  gb: TTyGridBuild;
begin
  arr := ACase.Arrays['grids'];
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
    if gb.Boxed then SameRect(Format('grid %d ref', [g.Integers['index']]), gb.RefXYWH, g.Find('ref'));
    SameRect(Format('grid %d rect', [g.Integers['index']]), gb.PlotXYWH, g.Find('rect'));
  end;
end;

procedure TAdvChartBoxUsageOracleTest.CheckCalls(ACase: TJSONObject);
var
  arr: TJSONArray;
  c: TJSONObject;
  k, j: Integer;
  cv: TTyConvertResult;
  ret: TJSONData;
  w: string;
begin
  arr := ACase.Arrays['calls'];
  for k := 0 to arr.Count - 1 do
  begin
    c := arr.Objects[k];
    w := Format('convertToPixel %s %s', [c.Find('finder').AsJSON, c.Find('value').AsJSON]);
    cv := FChart.ConvertToPixelData(c.Find('finder'), c.Find('value'));
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

procedure TAdvChartBoxUsageOracleTest.CheckPolars(ACase: TJSONObject);
var
  arr: TJSONArray;
  p: TJSONObject;
  k: Integer;
  pl: TTyPolar;
  a0, a1: Double;
begin
  arr := ACase.Arrays['polars'];
  for k := 0 to arr.Count - 1 do
  begin
    p := arr.Objects[k];
    pl := FChart.PolarLayout(p.Integers['index']);
    Inc(FCompared);
    if pl = nil then
    begin
      Miss(Format('no polar %d here', [p.Integers['index']]));
      Continue;
    end;
    Inc(FCount);
    SameH(Format('polar %d cx', [p.Integers['index']]), pl.CX, p.Find('cx'));
    SameH(Format('polar %d cy', [p.Integers['index']]), pl.CY, p.Find('cy'));
    pl.AxisExtent(pl.RadiusAxis, a0, a1);
    SameH(Format('polar %d r0', [p.Integers['index']]), a0, p.Arrays['r'].Items[0]);
    SameH(Format('polar %d r1', [p.Integers['index']]), a1, p.Arrays['r'].Items[1]);
  end;
end;

function AlignWord(A: TTyTitleAlign): string;
begin
  case A of
    ttaCentre: Result := 'center';
    ttaRight: Result := 'right';
  else
    Result := 'left';
  end;
end;

function VAlignWord(A: TTyTitleVAlign): string;
begin
  case A of
    ttvMiddle: Result := 'middle';
    ttvBottom: Result := 'bottom';
  else
    Result := 'top';
  end;
end;

procedure TAdvChartBoxUsageOracleTest.CheckTitles(ACase: TJSONObject);
var
  arr: TJSONArray;
  t: TJSONObject;
  k, idx: Integer;
  lay: TTyTitleLayout;
  want: string;
  bg: TJSONData;
begin
  arr := ACase.Arrays['titles'];
  for k := 0 to arr.Count - 1 do
  begin
    t := arr.Objects[k];
    idx := t.Integers['index'];
    lay := FChart.TitleLayoutOf(idx);
    Inc(FCompared);
    if not lay.Valid then
    begin
      Miss(Format('title %d is not laid out here', [idx]));
      Continue;
    end;
    Inc(FCount);
    SameH(Format('title %d x', [idx]), lay.TextX, t.Arrays['group'].Items[0]);
    SameH(Format('title %d y', [idx]), lay.TextY, t.Arrays['group'].Items[1]);
    want := 'left';
    if t.Find('align').JSONType = jtString then want := t.Strings['align'];
    if (want <> 'center') and (want <> 'right') then want := 'left';
    Inc(FCompared);
    if AlignWord(lay.Align) <> want then
      Miss(Format('title %d align %s, upstream %s', [idx, AlignWord(lay.Align), want]));
    want := 'top';
    if t.Find('verticalAlign').JSONType = jtString then want := t.Strings['verticalAlign'];
    if (want <> 'middle') and (want <> 'bottom') then want := 'top';
    Inc(FCompared);
    if VAlignWord(lay.VAlign) <> want then
      Miss(Format('title %d verticalAlign %s, upstream %s', [idx, VAlignWord(lay.VAlign), want]));
    { the background, where the block is aligned as a whole (see
      test.advchart.boxmerge: upstream aligns each line by itself for
      middle and bottom) }
    bg := t.Find('bg');
    if bg is TJSONObject then
    begin
      SameH(Format('title %d bg x', [idx]), lay.FrameX, TJSONObject(bg).Find('x'));
      SameH(Format('title %d bg width', [idx]), lay.FrameW, TJSONObject(bg).Find('width'));
      if want = 'top' then
      begin
        SameH(Format('title %d bg y', [idx]), lay.FrameY, TJSONObject(bg).Find('y'));
        SameH(Format('title %d bg height', [idx]), lay.FrameH, TJSONObject(bg).Find('height'));
      end;
    end;
  end;
end;

procedure TAdvChartBoxUsageOracleTest.CheckLegends(ACase: TJSONObject);
var
  arr, items, tt, rr: TJSONArray;
  l, it: TJSONObject;
  k, j, i, idx, cnt: Integer;
  lay: TTyLegendLayout;
  tx, ty, rx, ry, rw, rh: Double;
begin
  arr := ACase.Arrays['legends'];
  for k := 0 to arr.Count - 1 do
  begin
    l := arr.Objects[k];
    idx := l.Integers['index'];
    lay := FChart.LegendLayout(idx);
    Inc(FCompared);
    if not lay.Valid then
    begin
      Miss(Format('legend %d is not laid out here', [idx]));
      Continue;
    end;
    Inc(FCount);
    { the group's own place is kept by the selector's and the pager's path
      only (LayoutRich); a plain legend's items carry it, globally }
    if lay.IsScroll then
    begin
      SameH(Format('legend %d group x', [idx]), lay.GroupX, l.Arrays['group'].Items[0]);
      SameH(Format('legend %d group y', [idx]), lay.GroupY, l.Arrays['group'].Items[1]);
    end;
    items := l.Arrays['items'];
    cnt := 0;
    for i := 0 to High(lay.Items) do
      if TyRectFIsValid(lay.Items[i].Bounds)
        and (lay.Items[i].Bounds.Right > lay.Items[i].Bounds.Left) then Inc(cnt);
    Inc(FCompared);
    if cnt <> items.Count then
      Miss(Format('legend %d: %d items placed, upstream %d', [idx, cnt, items.Count]));
    for j := 0 to items.Count - 1 do
    begin
      it := items.Objects[j];
      i := it.Integers['i'];
      Inc(FCompared);
      if i > High(lay.Items) then
      begin
        Miss(Format('legend %d: no item %d', [idx, i]));
        Continue;
      end;
      if lay.Items[i].Text <> it.Strings['name'] then
        Miss(Format('legend %d item %d says %s, upstream %s', [idx, i, lay.Items[i].Text,
          it.Strings['name']]));
      tt := it.Arrays['t'];
      rr := it.Arrays['r'];
      tx := H(tt.Items[0]);
      ty := H(tt.Items[1]);
      rx := H(rr.Items[0]);
      ry := H(rr.Items[1]);
      rw := H(rr.Items[2]);
      rh := H(rr.Items[3]);
      SameH(Format('legend %d item %d x', [idx, i]), lay.Items[i].IconBox.Left, tt.Items[0]);
      SameH(Format('legend %d item %d y', [idx, i]), lay.Items[i].IconBox.Top, tt.Items[1]);
      SameX(Format('legend %d item %d left', [idx, i]), lay.Items[i].Bounds.Left, tx + rx);
      SameX(Format('legend %d item %d top', [idx, i]), lay.Items[i].Bounds.Top, ty + ry);
      { the far edges are the port's own sums (the item's box is a rect
        here): its size to a billionth }
      Inc(FCompared);
      if (Abs(lay.Items[i].Bounds.Right - lay.Items[i].Bounds.Left - rw) > 1e-9)
        or (Abs(lay.Items[i].Bounds.Bottom - lay.Items[i].Bounds.Top - rh) > 1e-9) then
        Miss(Format('legend %d item %d: the size differs', [idx, i]));
    end;
  end;
end;

procedure TAdvChartBoxUsageOracleTest.CheckPie(ASeries: TJSONObject);
var
  secs: TJSONArray;
  sj: TJSONObject;
  j, q, si: Integer;
  lst: TTyPaintList;
  e: TTyChartElement;
  found: Boolean;
  w: string;
begin
  lst := FChart.List;
  si := ASeries.Integers['seriesIndex'];
  secs := ASeries.Arrays['sectors'];
  for j := 0 to secs.Count - 1 do
  begin
    sj := secs.Objects[j];
    w := Format('series %d sector %d', [si, sj.Integers['i']]);
    found := False;
    for q := 0 to lst.Count - 1 do
    begin
      e := lst.Element(q);
      if (e.Datum.SeriesIndex <> si) or (e.Shape.Kind <> cskSector)
        or (e.Datum.RawDataIndex <> sj.Integers['i']) then Continue;
      found := True;
      Inc(FCount);
      SameH(w + ' cx', e.Shape.CX, sj.Find('cx'));
      SameH(w + ' cy', e.Shape.CY, sj.Find('cy'));
      SameH(w + ' r0', e.Shape.R0, sj.Find('r0'));
      SameH(w + ' r', e.Shape.R1, sj.Find('r'));
      Break;
    end;
    Inc(FCompared);
    if not found then Miss(w + ': no sector here');
  end;
end;

procedure TAdvChartBoxUsageOracleTest.CheckFunnel(ASeries: TJSONObject);
var
  items, pts: TJSONArray;
  ij: TJSONObject;
  j, q, p, si: Integer;
  lst: TTyPaintList;
  e: TTyChartElement;
  found: Boolean;
  w: string;
begin
  lst := FChart.List;
  si := ASeries.Integers['seriesIndex'];
  items := ASeries.Arrays['items'];
  for j := 0 to items.Count - 1 do
  begin
    ij := items.Objects[j];
    w := Format('series %d item %d', [si, ij.Integers['i']]);
    pts := ij.Arrays['points'];
    found := False;
    for q := 0 to lst.Count - 1 do
    begin
      e := lst.Element(q);
      if (e.Datum.SeriesIndex <> si) or (e.Shape.Kind <> cskPolygon)
        or (e.Datum.RawDataIndex <> ij.Integers['i']) then Continue;
      found := True;
      Inc(FCount);
      Inc(FCompared);
      if Length(e.Shape.Points) <> pts.Count then
      begin
        Miss(w + ': the point count differs');
        Break;
      end;
      for p := 0 to pts.Count - 1 do
      begin
        SameH(Format('%s point %d x', [w, p]), e.Shape.Points[p].X, pts.Arrays[p].Items[0]);
        SameH(Format('%s point %d y', [w, p]), e.Shape.Points[p].Y, pts.Arrays[p].Items[1]);
      end;
      Break;
    end;
    Inc(FCompared);
    if not found then Miss(w + ': no trapezoid here');
  end;
end;

procedure TAdvChartBoxUsageOracleTest.CheckSeries(ACase: TJSONObject);
var
  arr, nodes, crumbs, pts: TJSONArray;
  s, nd: TJSONObject;
  k, j, i, p, q, si: Integer;
  t, w: string;
  sk: TTySankeySolved;
  tr: TTyTreeSolved;
  tm: TTyTreemapSolved;
  ch: TTyChordSolved;
  sb: TTySunburstSolved;
  gv: TTyGraphView;
  gn: TTyGraphNodeArray;
  ge: TTyGraphEdgeArray;
  gf: TTyChartColorArray;
  pt: TTyPointF;
  lst: TTyPaintList;
  e: TTyChartElement;
  found: Boolean;
begin
  arr := ACase.Arrays['series'];
  for k := 0 to arr.Count - 1 do
  begin
    s := arr.Objects[k];
    si := s.Integers['seriesIndex'];
    t := s.Strings['type'];
    w := Format('series %d (%s)', [si, t]);
    if t = 'pie' then CheckPie(s)
    else if t = 'funnel' then CheckFunnel(s)
    else if t = 'chord' then
    begin
      ch := FChart.ChordSolved(si);
      Inc(FCompared);
      if not ch.Valid then begin Miss(w + ': not solved here'); Continue; end;
      Inc(FCount);
      nd := s.Arrays['sectors'].Objects[0];
      SameH(w + ' cx', ch.CX, nd.Find('cx'));
      SameH(w + ' cy', ch.CY, nd.Find('cy'));
      SameH(w + ' r0', ch.R0, nd.Find('r0'));
      SameH(w + ' r', ch.R, nd.Find('r'));
    end
    else if t = 'sunburst' then
    begin
      sb := FChart.SunburstSolved(si);
      Inc(FCompared);
      if not sb.Valid then begin Miss(w + ': not solved here'); Continue; end;
      Inc(FCount);
      nd := s.Arrays['sectors'].Objects[0];
      SameH(w + ' cx', sb.CX, nd.Find('cx'));
      SameH(w + ' cy', sb.CY, nd.Find('cy'));
    end
    else if t = 'sankey' then
    begin
      sk := FChart.SankeySolved(si);
      Inc(FCompared);
      if not sk.Valid then begin Miss(w + ': not solved here'); Continue; end;
      Inc(FCount);
      SameRect(w + ' box', sk.Box, s.Find('layoutInfo'));
      nodes := s.Arrays['nodes'];
      for j := 0 to nodes.Count - 1 do
      begin
        nd := nodes.Objects[j];
        i := nd.Integers['i'];
        Inc(FCompared);
        if i > High(sk.Nodes) then begin Miss(Format('%s: no node %d', [w, i])); Continue; end;
        SameH(Format('%s node %d x', [w, i]), sk.Nodes[i].X, nd.Find('x'));
        SameH(Format('%s node %d y', [w, i]), sk.Nodes[i].Y, nd.Find('y'));
        SameH(Format('%s node %d dx', [w, i]), sk.Nodes[i].DX, nd.Find('dx'));
        SameH(Format('%s node %d dy', [w, i]), sk.Nodes[i].DY, nd.Find('dy'));
      end;
    end
    else if t = 'tree' then
    begin
      tr := FChart.TreeSolved(si);
      Inc(FCompared);
      if not tr.Valid then begin Miss(w + ': not solved here'); Continue; end;
      Inc(FCount);
      SameRect(w + ' box', tr.Box, s.Find('layoutInfo'));
      nodes := s.Arrays['nodes'];
      for j := 0 to nodes.Count - 1 do
      begin
        nd := nodes.Objects[j];
        i := nd.Integers['i'];
        Inc(FCompared);
        if (i > High(tr.Pos)) or not tr.Pos[i].Placed then
        begin
          Miss(Format('%s: row %d not placed here', [w, i]));
          Continue;
        end;
        SameH(Format('%s row %d x', [w, i]), tr.Pos[i].X, nd.Find('x'));
        SameH(Format('%s row %d y', [w, i]), tr.Pos[i].Y, nd.Find('y'));
      end;
    end
    else if t = 'treemap' then
    begin
      tm := FChart.TreemapSolved(si);
      Inc(FCompared);
      if not tm.Valid then begin Miss(w + ': not solved here'); Continue; end;
      Inc(FCount);
      SameRect(w + ' box', tm.Box, s.Find('layoutInfo'));
      nodes := s.Arrays['nodes'];
      for j := 0 to nodes.Count - 1 do
      begin
        nd := nodes.Objects[j];
        i := nd.Integers['i'];
        Inc(FCompared);
        if (i > High(tm.Nodes)) or not tm.Nodes[i].HasLayout then
        begin
          Miss(Format('%s: row %d not laid out here', [w, i]));
          Continue;
        end;
        SameH(Format('%s row %d x', [w, i]), tm.Nodes[i].X, nd.Find('x'));
        SameH(Format('%s row %d y', [w, i]), tm.Nodes[i].Y, nd.Find('y'));
        SameH(Format('%s row %d w', [w, i]), tm.Nodes[i].W, nd.Find('width'));
        SameH(Format('%s row %d h', [w, i]), tm.Nodes[i].H, nd.Find('height'));
      end;
      crumbs := s.Arrays['crumbs'];
      Inc(FCompared);
      if Length(tm.Crumbs) <> crumbs.Count then
        Miss(Format('%s: %d crumbs here, upstream %d', [w, Length(tm.Crumbs), crumbs.Count]))
      else
        for j := 0 to crumbs.Count - 1 do
        begin
          pts := crumbs.Arrays[j];
          Inc(FCompared);
          if Length(tm.Crumbs[j].Points) <> pts.Count then
          begin
            Miss(Format('%s crumb %d: the point count differs', [w, j]));
            Continue;
          end;
          for p := 0 to pts.Count - 1 do
          begin
            SameH(Format('%s crumb %d point %d x', [w, j, p]), tm.Crumbs[j].Points[p].X,
              pts.Arrays[p].Items[0]);
            SameH(Format('%s crumb %d point %d y', [w, j, p]), tm.Crumbs[j].Points[p].Y,
              pts.Arrays[p].Items[1]);
          end;
        end;
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
      SameRect(w + ' view', gv.ViewXYWH, s.Find('viewRect'));
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
    end
    else if t = 'gauge' then
    begin
      lst := FChart.List;
      found := False;
      for q := 0 to lst.Count - 1 do
      begin
        e := lst.Element(q);
        if (e.Datum.SeriesIndex <> si) or (e.Shape.Kind <> cskSector) then Continue;
        found := True;
        Inc(FCount);
        SameH(w + ' cx', e.Shape.CX, s.Arrays['centre'].Items[0]);
        SameH(w + ' cy', e.Shape.CY, s.Arrays['centre'].Items[1]);
        Break;
      end;
      Inc(FCompared);
      if not found then Miss(w + ': no sector here');
    end;
  end;
end;

procedure TAdvChartBoxUsageOracleTest.EachCase(AKind: Integer);
var
  cases: TJSONArray;
  cs: TJSONObject;
  c: Integer;
  key: string;
begin
  case AKind of
    ckGrids: key := 'grids';
    ckCalls: key := 'calls';
    ckPolars: key := 'polars';
    ckTitles: key := 'titles';
    ckLegends: key := 'legends';
  else
    key := 'series';
  end;
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := cases.Objects[c];
    if cs.Arrays[key].Count = 0 then Continue;
    Draw(cs);
    case AKind of
      ckGrids: CheckGrids(cs);
      ckCalls: CheckCalls(cs);
      ckPolars: CheckPolars(cs);
      ckTitles: CheckTitles(cs);
      ckLegends: CheckLegends(cs);
    else
      CheckSeries(cs);
    end;
  end;
end;

procedure TAdvChartBoxUsageOracleTest.TestTheGridsAsUpstream;
begin
  EachCase(ckGrids);
  Verdict(20);
end;

procedure TAdvChartBoxUsageOracleTest.TestTheConversionsAsUpstream;
begin
  EachCase(ckCalls);
  Verdict(20);
end;

procedure TAdvChartBoxUsageOracleTest.TestThePolarsAsUpstream;
begin
  EachCase(ckPolars);
  Verdict(3);
end;

procedure TAdvChartBoxUsageOracleTest.TestTheTitlesAsUpstream;
begin
  EachCase(ckTitles);
  Verdict(13);
end;

procedure TAdvChartBoxUsageOracleTest.TestTheLegendsAsUpstream;
begin
  EachCase(ckLegends);
  Verdict(3);
end;

procedure TAdvChartBoxUsageOracleTest.TestTheSeriesAsUpstream;
begin
  EachCase(ckSeries);
  Verdict(30);
end;

{ ---- around the oracle ---- }

{ a box type whose host is not there, a gauge and a sunburst naming a cell,
  a chord with no usage: resolved, on no coordinate system, drawn on the
  canvas -- upstream's createBoxLayoutReference with no boxCoordinateSystem }
procedure TAdvChartBoxUsageOracleTest.TestTheFallbacksAreOnTheCanvas;
var
  b: TTySeriesBindingArray;
  opt: TTyChartOption;
  build: TTyChartBuild;
  i: Integer;
begin
  opt := TTyChartOption.Create;
  try
    AssertTrue('parses', opt.SetOptionText('{"matrix": {"x": {"data": ["a"]}, "y": {"data": ["p"]}},'
      + ' "calendar": {"range": "2017-02"}, "series": ['
      + '{"type": "gauge", "coordinateSystem": "matrix", "coord": ["a", "p"]},'
      + '{"type": "sunburst", "coordinateSystem": "matrix", "coordinateSystemUsage": "box", "coord": ["a", "p"]},'
      + '{"type": "chord", "coordinateSystem": "matrix", "coord": ["a", "p"]},'
      + '{"type": "sankey", "coordinateSystem": "calendar", "calendarIndex": 3, "coord": "2017-02-01"},'
      + '{"type": "pie", "coordinateSystem": "matrix", "matrixIndex": 2},'
      + '{"type": "sankey", "coordinateSystem": "matrix", "coord": ["a", "p"]},'
      + '{"type": "graph", "coordinateSystem": "calendar", "coordinateSystemUsage": "box", "coord": "2017-02-01"},'
      + '{"type": "heatmap", "coordinateSystem": "matrix", "coordinateSystemUsage": "box"}]}'));
    build := TyBuildGrids(opt, TyRectF(0, 0, cW, cH));
    try
      b := TyBindSeries(opt, build);
      for i := 0 to 4 do
      begin
        AssertTrue(Format('series %d resolves', [i]), b[i].Resolved);
        AssertEquals(Format('series %d: no matrix', [i]), -1, b[i].MatrixIndex);
        AssertEquals(Format('series %d: no calendar', [i]), -1, b[i].CalendarIndex);
        AssertEquals(Format('series %d: no calendar box', [i]), -1, b[i].CalendarBoxIndex);
        AssertFalse(Format('series %d: no matrix box', [i]), b[i].MatrixBox);
      end;
      AssertTrue('a sankey on a matrix is in a cell', b[5].Resolved and b[5].MatrixBox
        and (b[5].MatrixIndex = 0));
      AssertTrue('a graph with box on a calendar is in a day, on no calendar of its own',
        b[6].Resolved and (b[6].CalendarBoxIndex = 0) and (b[6].CalendarIndex = -1));
      AssertFalse('a heatmap cannot be laid out in a box', b[7].Resolved);
    finally
      build.Free;
    end;
  finally
    opt.Free;
  end;
end;

{ a coord naming no cell: a grid, a polar, a legend, a sankey, a treemap, a
  graph and a chord laid out on a rect of no position -- nothing raises }
procedure TAdvChartBoxUsageOracleTest.TestACoordNamingNoCellDoesNotRaise;
begin
  FChart.SetBounds(0, 0, cW, cH);
  FChart.Option := '{"animation": false, "matrix": {"x": {"data": ["a", "b"]}, "y": {"data": ["p"]}},'
    + ' "calendar": {"range": "2017-02"},'
    + ' "grid": [{"coordinateSystem": "matrix", "coord": ["zz", "p"]},'
    + '  {"coordinateSystem": "calendar", "coord": "2019-01-01"}],'
    + ' "xAxis": [{"gridIndex": 0}, {"gridIndex": 1}], "yAxis": [{"gridIndex": 0}, {"gridIndex": 1}],'
    + ' "polar": {"coordinateSystem": "matrix", "coord": ["a", "zz"]}, "angleAxis": {}, "radiusAxis": {},'
    + ' "legend": {"coordinateSystem": "matrix", "coord": ["zz", "zz"]},'
    + ' "title": {"text": "T", "coordinateSystem": "calendar", "coord": "2019-01-01"},'
    + ' "series": [{"type": "line", "name": "L", "data": [[1, 2], [3, 4]]},'
    + '  {"type": "bar", "xAxisIndex": 1, "yAxisIndex": 1, "data": [[1, 2]]},'
    + '  {"type": "bar", "coordinateSystem": "polar", "data": [1, 2]},'
    + '  {"type": "sankey", "coordinateSystem": "matrix", "coord": ["zz", "p"],'
    + '   "data": [{"name": "A"}, {"name": "B"}], "links": [{"source": "A", "target": "B", "value": 1}]},'
    + '  {"type": "treemap", "coordinateSystem": "calendar", "coord": "2019-01-01", "data": [{"name": "x", "value": 1}]},'
    + '  {"type": "graph", "coordinateSystem": "matrix", "coordinateSystemUsage": "box", "coord": ["zz", "p"],'
    + '   "data": [{"name": "A", "x": 0, "y": 0}, {"name": "B", "x": 1, "y": 1}]},'
    + '  {"type": "chord", "coordinateSystem": "matrix", "coordinateSystemUsage": "box", "coord": ["zz", "p"],'
    + '   "data": [{"name": "A"}, {"name": "B"}], "links": [{"source": "A", "target": "B", "value": 1}]},'
    + '  {"type": "pie", "coordinateSystem": "calendar", "coord": "2019-01-01", "data": [1, 2]}]}';
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW, cH), 96);
  AssertFalse('the sankey in no cell is not drawn', FChart.SankeySolved(3).Valid);
  { a day off the calendar's range has a size (19 x 19, the default
    cellSize less the line) and no place: the treemap is laid out at the
    canvas' edge (getLayoutRect's `containerRect.x || 0`) -- upstream's
    layoutInfo there is {x: -1, y: -31, width: 21, height: 81} }
  AssertTrue('the treemap in a day of no place is laid out', FChart.TreemapSolved(4).Valid);
  AssertEquals('its x as upstream', -1, FChart.TreemapSolved(4).Box.X, 0);
  AssertEquals('its y as upstream', -31, FChart.TreemapSolved(4).Box.Y, 0);
  AssertEquals('its width as upstream', 21, FChart.TreemapSolved(4).Box.W, 0);
  AssertEquals('its height as upstream', 81, FChart.TreemapSolved(4).Box.H, 0);
  AssertFalse('the chord in no cell is not drawn', FChart.ChordSolved(6).Valid);
  { the title off the range: the content rect is not a number at all, and
    getLayoutRect's `|| 0` puts it at the canvas' left top }
  AssertTrue('the title off the range is laid out', FChart.TitleLayoutOf(0).Valid);
  { and again, the hosts relaid out by a resize }
  FChart.Render(FBmp.Canvas, Rect(0, 0, cW - 100, cH - 100), 96);
end;

{ decideCoordSysUsageKind for a component that is no series: a matrix or a
  calendar with usage 'box', unwritten or a written null }
procedure TAdvChartBoxUsageOracleTest.TestTheComponentUsageRule;

  function U(const AJson: string): string;
  var d: TJSONData;
  begin
    d := GetJSON(AJson);
    try
      Result := TyComponentBoxSysOf(d);
    finally
      d.Free;
    end;
  end;

begin
  AssertEquals('matrix', U('{"coordinateSystem": "matrix"}'));
  AssertEquals('calendar', U('{"coordinateSystem": "calendar"}'));
  AssertEquals('matrix', U('{"coordinateSystem": "matrix", "coordinateSystemUsage": "box"}'));
  AssertEquals('a written null is a component''s default', 'matrix',
    U('{"coordinateSystem": "matrix", "coordinateSystemUsage": null}'));
  AssertEquals('data is no usage for a component', '',
    U('{"coordinateSystem": "matrix", "coordinateSystemUsage": "data"}'));
  AssertEquals('nor is another word', '',
    U('{"coordinateSystem": "matrix", "coordinateSystemUsage": "Box"}'));
  AssertEquals('a polar hosts no component', '', U('{"coordinateSystem": "polar"}'));
  AssertEquals('a cartesian hosts no component', '', U('{"coordinateSystem": "cartesian2d"}'));
  AssertEquals('no coordinate system', '', U('{"coord": [0, 0]}'));
  AssertEquals('not a string', '', U('{"coordinateSystem": 1}'));
  AssertEquals('not an object', '', U('[1]'));
end;

initialization
  RegisterTest(TAdvChartBoxUsageOracleTest);
end.
