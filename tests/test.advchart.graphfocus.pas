unit test.advchart.graphfocus;
{$mode objfpc}{$H+}
{ A hovered graph: what rises, what dims, and what stays.

  `emphasis.focus: 'adjacency'` raises the hovered node and dims everything in
  the series that is not one of its edges or at the far end of one -- a node
  with no edges dims the whole rest of the series. A hovered edge spares only
  its two ends. 'self' dims every other element; 'series' dims nothing of its
  own series.

  THE HOVER IS DRAWN IN THE STATIC LAYER, in place. The overlay every other
  series uses would draw a translucent edge twice -- darker than the colour it
  means -- and would lay the lifted edge over the nodes it joins. These tests
  read pixels for exactly those two things, on top of what the paint list
  says. }
interface
uses Classes, SysUtils, Math, Controls, Graphics, Forms, fpcunit, testregistry,
     fpjson, jsonparser, BGRABitmap, BGRABitmapTypes,
     tyControls.Controller,
     tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
     tyControls.AdvChart.Paint, tyControls.AdvChart.Style,
     tyControls.AdvChart.Color, tyControls.AdvChart.Graph,
     tyControls.AdvanceChart;
type
  TGraphFocusProbe = class(TTyAdvanceChart)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    function List: TTyPaintList;
    procedure Hover(AX, AY: Integer);
    procedure Leave;
    procedure Cached(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TAdvChartGraphFocusTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGraphFocusProbe;
    FBmp: TBGRABitmap;
    procedure Show(const AOption: string);
    procedure RenderNow;
    function NodeAt(AIndex: Integer): TPoint;
    function Alpha(ASeries, ARow: Integer; AEdge: Boolean): Double;
    function Px(AX, AY: Integer): TBGRAPixel;
    procedure AssertPixel(const AWhat: string; AWant, AGot: TBGRAPixel);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAdjacencySparesTheNodesEdgesAndTheirEnds;
    procedure TestANodeWithNoEdgesDimsTheRest;
    procedure TestAnEdgeSparesOnlyItsEnds;
    procedure TestABlurredNodeIsItsFillAtATenth;
    procedure TestAHoveredEdgeStaysUnderItsNodes;
    procedure TestATranslucentEdgeIsDrawnOnce;
    procedure TestLeavingPutsEverythingBack;
    procedure TestALabelIsItsNode;
    procedure TestADeclaredBlurOpacityStandsAsWritten;
    procedure TestTheResolverKeepsADeclaredBlurOpacity;
    procedure TestTheCachedPictureFollowsTheHover;
    procedure TestASecondHoverBeforeARepaintStillLands;
  end;

  { Upstream's own answers: tools/advchart-oracle/focus-adjacency.js hovers
    the real ECharts 6.1 build at integer points and records, at rest and
    after every step, what the pointer hit and every node's and edge's state
    and ink -- opacity, fill, stroke, width, half-extents, z2, the label's
    opacity and each arrowhead's. The port is driven through the control's own
    MouseMove and MouseLeave and read back from the list it painted.

    Opacities, colours, half-extents and widths are exact. z2 is compared as
    ORDER -- the port's numbers are its own -- node against node, edge
    against edge, every edge against every node, and a label above its
    node. }
  TAdvChartGraphFocusOracleTest = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FChart: TGraphFocusProbe;
    FBmp: TBGRABitmap;
    FRoot: TJSONData;
    FBad, FCompared, FCases, FSteps: Integer;
    FReport, FName: string;
    procedure Miss(const AWhat: string);
    procedure SameNum(const AWhat: string; AGot: Double; AObj: TJSONObject;
      const AKey: string; AIndex: Integer = -1);
    procedure SameBytes(const AWhat: string; AGot: TTyChartColor;
      AObj: TJSONObject; const AKey: string);
    procedure RenderNow;
    procedure CheckHit(AHit: TJSONData; AX, AY: Integer);
    procedure CheckRecord(ARecord: TJSONObject; AStep: Integer);
    procedure CheckSeries(ASeries: TJSONObject);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEveryHoverLooksAsUpstreamDrawsIt;
  end;

implementation

const
  { A-B, A-C, C-D, and E on its own. }
  cGraph = '{animation:false, tooltip:{show:false}, series:[{type:"graph",'
    + ' layout:"none", symbolSize:20, itemStyle:{color:"#5070dd"},'
    + ' lineStyle:{color:"#336699", width:3, opacity:%s},'
    + ' emphasis:{focus:"adjacency"}%s,'
    + ' data:[{name:"A",x:0,y:0},{name:"B",x:100,y:0},{name:"C",x:0,y:80},'
    + '{name:"D",x:100,y:80},{name:"E",x:200,y:40}],'
    + ' links:[{source:"A",target:"B"},{source:"A",target:"C"},'
    + '{source:"C",target:"D"}]}]}';

procedure TGraphFocusProbe.Render(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

function TGraphFocusProbe.List: TTyPaintList;
begin
  Result := SeriesList;
end;

procedure TGraphFocusProbe.Hover(AX, AY: Integer);
begin
  MouseMove([], AX, AY);
end;

procedure TGraphFocusProbe.Leave;
begin
  MouseLeave;
end;

procedure TGraphFocusProbe.Cached(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer);
begin
  RenderCached(ACanvas, ARect, APPI);
end;

procedure TAdvChartGraphFocusTest.SetUp;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TGraphFocusProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FChart.SetBounds(0, 0, 400, 300);
  FBmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
end;

procedure TAdvChartGraphFocusTest.TearDown;
begin
  FreeAndNil(FBmp);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartGraphFocusTest.RenderNow;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, 400, 300), 96);
end;

procedure TAdvChartGraphFocusTest.Show(const AOption: string);
begin
  FChart.Option := AOption;
  RenderNow;
end;

function TAdvChartGraphFocusTest.NodeAt(AIndex: Integer): TPoint;
var
  nodes: TTyGraphNodeArray;
  edges: TTyGraphEdgeArray;
  fills: TTyChartColorArray;
begin
  AssertTrue(FChart.GraphLayout(0, nodes, edges, fills));
  Result := Point(Round(nodes[AIndex].PX), Round(nodes[AIndex].PY));
end;

{ The opacity the mark for a datum was drawn with -- the symbol or the line,
  not a caption and not an arrowhead. }
function TAdvChartGraphFocusTest.Alpha(ASeries, ARow: Integer;
  AEdge: Boolean): Double;
var i: Integer; el: TTyChartElement;
begin
  for i := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(i);
    if (el.Datum.SeriesIndex = ASeries) and (el.Datum.DataIndex = ARow)
      and (el.Datum.IsEdge = AEdge) and (el.Caption.FontSizeLogical = 0)
      and not el.Silent then
      Exit(el.Style.Alpha);
  end;
  Fail(Format('no mark for %d/%d', [ASeries, ARow]));
  Result := NaN;
end;

function TAdvChartGraphFocusTest.Px(AX, AY: Integer): TBGRAPixel;
begin
  Result := FBmp.GetPixel(AX, AY);
end;

procedure TAdvChartGraphFocusTest.AssertPixel(const AWhat: string;
  AWant, AGot: TBGRAPixel);
begin
  AssertTrue(Format('%s: want (%d,%d,%d), got (%d,%d,%d)', [AWhat,
    AWant.red, AWant.green, AWant.blue, AGot.red, AGot.green, AGot.blue]),
    (Abs(AWant.red - AGot.red) <= 2) and (Abs(AWant.green - AGot.green) <= 2)
    and (Abs(AWant.blue - AGot.blue) <= 2));
end;

{ One colour laid ONCE over another at an opacity -- by BGRABitmap's own
  blend, which is the painter's, gamma and all. }
function Over(AGround: TBGRAPixel; AColour: TTyChartColor;
  AAlpha: Double): TBGRAPixel;
var tmp: TBGRABitmap;
begin
  tmp := TBGRABitmap.Create(1, 1, AGround);
  try
    tmp.DrawPixel(0, 0, BGRA((AColour shr 16) and $FF, (AColour shr 8) and $FF,
      AColour and $FF, Round(AAlpha * 255)));
    Result := tmp.GetPixel(0, 0);
  finally
    tmp.Free;
  end;
end;

procedure TAdvChartGraphFocusTest.TestAdjacencySparesTheNodesEdgesAndTheirEnds;
var p: TPoint;
begin
  Show(Format(cGraph, ['0.5', '']));
  p := NodeAt(2);
  FChart.Hover(p.X, p.Y);
  RenderNow;
  { C's edges are A-C and C-D: A and D are at their far ends. }
  AssertEquals('A is at the end of A-C', 1, Alpha(0, 0, False), 0);
  AssertEquals('B is not next to C', 0.1, Alpha(0, 1, False), 0);
  AssertEquals('D is at the end of C-D', 1, Alpha(0, 3, False), 0);
  AssertEquals('E is not next to anything', 0.1, Alpha(0, 4, False), 0);
  AssertEquals('A-B does not touch C', 0.05, Alpha(0, 0, True), 0);
  AssertEquals('A-C touches C', 0.5, Alpha(0, 1, True), 0);
  AssertEquals('C-D touches C', 0.5, Alpha(0, 2, True), 0);
end;

procedure TAdvChartGraphFocusTest.TestANodeWithNoEdgesDimsTheRest;
var p: TPoint; i: Integer;
begin
  Show(Format(cGraph, ['0.5', '']));
  p := NodeAt(4);
  FChart.Hover(p.X, p.Y);
  RenderNow;
  for i := 0 to 3 do
    AssertEquals(Format('node %d dims', [i]), 0.1, Alpha(0, i, False), 0);
  for i := 0 to 2 do
    AssertEquals(Format('edge %d dims', [i]), 0.05, Alpha(0, i, True), 0);
  AssertEquals('and E itself does not', 1, Alpha(0, 4, False), 0);
end;

procedure TAdvChartGraphFocusTest.TestAnEdgeSparesOnlyItsEnds;
var a, b: TPoint;
begin
  Show(Format(cGraph, ['0.5', '']));
  a := NodeAt(2);
  b := NodeAt(3);
  FChart.Hover((a.X + b.X) div 2, (a.Y + b.Y) div 2);
  RenderNow;
  AssertEquals('C is an end', 1, Alpha(0, 2, False), 0);
  AssertEquals('D is an end', 1, Alpha(0, 3, False), 0);
  AssertEquals('A is not', 0.1, Alpha(0, 0, False), 0);
  AssertEquals('A-C shares an end and still dims', 0.05, Alpha(0, 1, True), 0);
end;

procedure TAdvChartGraphFocusTest.TestABlurredNodeIsItsFillAtATenth;
var p, e: TPoint; ground: TBGRAPixel;
begin
  Show(Format(cGraph, ['0.5', '']));
  e := NodeAt(4);
  ground := Px(e.X, e.Y + 40);
  p := NodeAt(1);
  FChart.Hover(p.X + 0, p.Y);
  { B's edge is A-B only: E, off by itself, dims. }
  RenderNow;
  AssertPixel('E''s centre', Over(ground, $FF5070DD, 0.1), Px(e.X, e.Y));
end;

procedure TAdvChartGraphFocusTest.TestAHoveredEdgeStaysUnderItsNodes;
var c, d: TPoint; inside, restPx: TBGRAPixel;
begin
  Show(Format(cGraph, ['1', '']));
  c := NodeAt(2);
  d := NodeAt(3);
  { On the line, inside C's disc. }
  restPx := Px(c.X + 6, c.Y);
  FChart.Hover((c.X + d.X) div 2, (c.Y + d.Y) div 2);
  RenderNow;
  inside := Px(c.X + 6, c.Y);
  AssertPixel('C covers the lifted line', restPx, inside);
end;

procedure TAdvChartGraphFocusTest.TestATranslucentEdgeIsDrawnOnce;
var c, d, m: TPoint; ground: TBGRAPixel;
begin
  Show(Format(cGraph, ['0.5', '']));
  c := NodeAt(2);
  d := NodeAt(3);
  m := Point((c.X + d.X) div 2, (c.Y + d.Y) div 2);
  ground := Px(m.X, m.Y - 30);
  FChart.Hover(m.X, m.Y);
  RenderNow;
  AssertPixel('the midpoint is ONE layer of the lifted stroke',
    Over(ground, TyChartLiftColor($FF336699), 0.5), Px(m.X, m.Y));
end;

procedure TAdvChartGraphFocusTest.TestLeavingPutsEverythingBack;
var rest: TBGRABitmap; p: TPoint; x, y, diff: Integer;
begin
  Show(Format(cGraph, ['0.5', '']));
  rest := FBmp.Duplicate as TBGRABitmap;
  try
    p := NodeAt(0);
    FChart.Hover(p.X, p.Y);
    RenderNow;
    AssertEquals('the hover dimmed something', 0.1, Alpha(0, 4, False), 0);
    FChart.Leave;
    RenderNow;
    diff := 0;
    for y := 0 to 299 do
      for x := 0 to 399 do
        if rest.GetPixel(x, y) <> FBmp.GetPixel(x, y) then Inc(diff);
    AssertEquals('the picture is the one at rest', 0, diff);
  finally
    rest.Free;
  end;
end;

procedure TAdvChartGraphFocusTest.TestALabelIsItsNode;
var i: Integer; el: TTyChartElement; hit: Boolean; cx, cy: Integer;
begin
  Show(Format(cGraph, ['0.5', ', label:{show:true, position:"right"}']));
  { THE WORDS OF E, which sit beside its symbol. }
  hit := False;
  cx := 0;
  cy := 0;
  for i := 0 to FChart.List.Count - 1 do
  begin
    el := FChart.List.Element(i);
    if (el.Datum.DataIndex = 4) and not el.Datum.IsEdge
      and (el.Caption.FontSizeLogical > 0) then
    begin
      cx := Round((el.Shape.Bounds.Left + el.Shape.Bounds.Right) / 2);
      cy := Round((el.Shape.Bounds.Top + el.Shape.Bounds.Bottom) / 2);
      hit := True;
    end;
  end;
  AssertTrue('E has a label', hit);
  AssertTrue('beside the symbol, not on it', cx > NodeAt(4).X + 10);
  FChart.Hover(cx, cy);
  RenderNow;
  AssertEquals('the rest dims as for E', 0.1, Alpha(0, 0, False), 0);
  AssertEquals('and E does not', 1, Alpha(0, 4, False), 0);
end;

procedure TAdvChartGraphFocusTest.TestADeclaredBlurOpacityStandsAsWritten;
var p: TPoint;
begin
  Show(Format(cGraph, ['0.5',
    ', blur:{itemStyle:{opacity:0.3}, lineStyle:{opacity:0.2}}']));
  p := NodeAt(4);
  FChart.Hover(p.X, p.Y);
  RenderNow;
  AssertEquals('a node at its declared blur', 0.3, Alpha(0, 0, False), 0);
  AssertEquals('an edge at its declared blur', 0.2, Alpha(0, 0, True), 0);
end;

{ ==================== the oracle ==================== }

function FixturePath: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + 'fixtures' + PathDelim
    + 'advchart-graph-focus.json';
end;

function HexNum(AData: TJSONData): Double;
var q: QWord;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(NaN);
  if AData.JSONType = jtNumber then Exit(AData.AsFloat);
  q := StrToQWord('$' + AData.AsString);
  Result := 0;
  Move(q, Result, SizeOf(Result));
end;

function NumAt(AObj: TJSONObject; const AKey: string;
  AIndex: Integer = -1): Double;
var d: TJSONData;
begin
  d := AObj.Find(AKey);
  if AIndex >= 0 then
  begin
    if (d is TJSONArray) and (AIndex < TJSONArray(d).Count) then
      d := TJSONArray(d).Items[AIndex]
    else
      d := nil;
  end;
  Result := HexNum(d);
end;

function Fmt(A: Double): string;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := FloatToStrF(A, ffGeneral, 17, 0, fs);
end;

procedure TAdvChartGraphFocusOracleTest.SetUp;
var sl: TStringList;
begin
  inherited SetUp;
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(nil);
  FCtl.Mode := 'light';
  FCtl.ThemeName := 'default';
  FChart := TGraphFocusProbe.Create(FForm);
  FChart.Parent := FForm;
  FChart.Controller := FCtl;
  FBmp := TBGRABitmap.Create(400, 300, BGRA(255, 255, 255, 255));
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
  FCases := 0;
  FSteps := 0;
  FReport := '';
end;

procedure TAdvChartGraphFocusOracleTest.TearDown;
begin
  FreeAndNil(FRoot);
  FreeAndNil(FBmp);
  FChart := nil;
  FreeAndNil(FForm);
  FreeAndNil(FCtl);
  inherited TearDown;
end;

procedure TAdvChartGraphFocusOracleTest.Miss(const AWhat: string);
begin
  Inc(FBad);
  if FBad <= 40 then
    FReport := FReport + LineEnding + '  ' + FName + ': ' + AWhat;
end;

procedure TAdvChartGraphFocusOracleTest.SameNum(const AWhat: string;
  AGot: Double; AObj: TJSONObject; const AKey: string; AIndex: Integer);
var want: Double;
begin
  Inc(FCompared);
  want := NumAt(AObj, AKey, AIndex);
  if IsNan(want) and IsNan(AGot) then Exit;
  if IsNan(want) or IsNan(AGot) or (AGot <> want) then
    Miss(Format('%s is %s upstream, %s here', [AWhat, Fmt(want), Fmt(AGot)]));
end;

procedure TAdvChartGraphFocusOracleTest.SameBytes(const AWhat: string;
  AGot: TTyChartColor; AObj: TJSONObject; const AKey: string);
var b: TJSONArray; r, g, bl: Integer;
begin
  if not (AObj.Find(AKey) is TJSONArray) then Exit;
  b := AObj.Arrays[AKey];
  Inc(FCompared);
  r := (AGot shr 16) and $FF;
  g := (AGot shr 8) and $FF;
  bl := AGot and $FF;
  if (r <> b.Integers[0]) or (g <> b.Integers[1]) or (bl <> b.Integers[2]) then
    Miss(Format('%s is (%d,%d,%d) upstream, (%d,%d,%d) here', [AWhat,
      b.Integers[0], b.Integers[1], b.Integers[2], r, g, bl]));
end;

procedure TAdvChartGraphFocusOracleTest.RenderNow;
begin
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Render(FBmp.Canvas, Rect(0, 0, 400, 300), 96);
end;

procedure TAdvChartGraphFocusOracleTest.CheckHit(AHit: TJSONData; AX, AY: Integer);
var
  d: TTyChartDatumRef;
  h: TJSONObject;
  kind: string;
begin
  if not (AHit is TJSONObject) then Exit;
  h := TJSONObject(AHit);
  kind := h.Strings['kind'];
  d := FChart.HitTestAt(AX, AY);
  Inc(FCompared);
  if kind = 'node' then
  begin
    if (d.SeriesIndex <> h.Integers['series']) or d.IsEdge then
      Miss(Format('(%d, %d) is node %s upstream, not here', [AX, AY,
        h.Strings['name']]));
  end
  else if kind = 'edge' then
  begin
    if (d.SeriesIndex <> h.Integers['series']) or not d.IsEdge
      or (d.DataIndex <> h.Integers['link']) then
      Miss(Format('(%d, %d) is link %d upstream, not here', [AX, AY,
        h.Integers['link']]));
  end
  else if TyChartDatumValid(d) then
    Miss(Format('(%d, %d) hits nothing upstream, something here', [AX, AY]));
end;

type
  TMarkSet = record
    Symbol, Caption, Line: Integer;
    Arrows: array of Integer;
  end;

{ The elements one datum was painted as. }
function MarksOf(AList: TTyPaintList; ASeries, ARow: Integer;
  AEdge: Boolean): TMarkSet;
var i: Integer; el: TTyChartElement;
begin
  Result.Symbol := -1;
  Result.Caption := -1;
  Result.Line := -1;
  Result.Arrows := nil;
  for i := 0 to AList.Count - 1 do
  begin
    el := AList.Element(i);
    if (el.Datum.SeriesIndex <> ASeries) or (el.Datum.DataIndex <> ARow)
      or (el.Datum.IsEdge <> AEdge) then Continue;
    if el.Caption.FontSizeLogical > 0 then Result.Caption := i
    else if AEdge and (el.Shape.Kind = cskPolyline) then Result.Line := i
    else if AEdge then
    begin
      SetLength(Result.Arrows, Length(Result.Arrows) + 1);
      Result.Arrows[High(Result.Arrows)] := i;
    end
    else Result.Symbol := i;
  end;
end;

procedure TAdvChartGraphFocusOracleTest.CheckSeries(ASeries: TJSONObject);
const
  cSides: array[0..1] of string = ('fromArrow', 'toArrow');
var
  si, i, j, k, row, s: Integer;
  nodes, edges: TJSONArray;
  o, lab, arr: TJSONObject;
  m: TMarkSet;
  el: TTyChartElement;
  tag, nm: string;
  nz, ez, nupz, eupz: array of Integer;
  nOk, eOk: array of Boolean;
  arrowAt: Integer;

  function Sign(A: Integer): Integer;
  begin
    if A > 0 then Result := 1 else if A < 0 then Result := -1 else Result := 0;
  end;

begin
  si := ASeries.Integers['index'];
  tag := 's' + IntToStr(si);
  nodes := ASeries.Arrays['nodes'];
  edges := ASeries.Arrays['edges'];
  SetLength(nz, nodes.Count);
  SetLength(nupz, nodes.Count);
  SetLength(nOk, nodes.Count);
  SetLength(ez, edges.Count);
  SetLength(eupz, edges.Count);
  SetLength(eOk, edges.Count);

  for i := 0 to nodes.Count - 1 do
  begin
    o := TJSONObject(nodes.Items[i]);
    nm := o.Strings['name'];
    row := o.Integers['row'];
    m := MarksOf(FChart.List, si, row, False);
    Inc(FCompared);
    if m.Symbol < 0 then
    begin
      Miss(Format('%s node %s has no symbol here', [tag, nm]));
      Continue;
    end;
    el := FChart.List.Element(m.Symbol);
    SameNum(Format('%s node %s opacity', [tag, nm]), el.Style.Alpha, o, 'opacity');
    SameBytes(Format('%s node %s fill', [tag, nm]), el.Style.FillColor, o,
      'fillBytes');
    if o.Find('strokeBytes') is TJSONArray then
    begin
      SameBytes(Format('%s node %s border', [tag, nm]), el.Style.StrokeColor, o,
        'strokeBytes');
      SameNum(Format('%s node %s border width', [tag, nm]),
        el.Style.StrokeWidthLogical, o, 'lineWidth');
    end
    else
    begin
      { NO BORDER UPSTREAM, so none here -- a node never borrows the line's
        emphasis. }
      Inc(FCompared);
      if el.Style.StrokeWidthLogical > 0 then
        Miss(Format('%s node %s has a border here', [tag, nm]));
    end;
    if el.Shape.Kind = cskEllipse then
    begin
      SameNum(Format('%s node %s half x', [tag, nm]), el.Shape.R0, o, 'half', 0);
      SameNum(Format('%s node %s half y', [tag, nm]), el.Shape.R1, o, 'half', 1);
    end
    else
    begin
      SameNum(Format('%s node %s half x', [tag, nm]), el.Shape.R1, o, 'half', 0);
      SameNum(Format('%s node %s half y', [tag, nm]), el.Shape.R1, o, 'half', 1);
    end;
    nz[i] := el.Z2;
    nupz[i] := o.Integers['z2'];
    nOk[i] := True;
    if o.Find('label') is TJSONObject then
    begin
      lab := o.Objects['label'];
      if not lab.Booleans['ignore'] then
      begin
        Inc(FCompared);
        if m.Caption < 0 then
          Miss(Format('%s node %s has no label here', [tag, nm]))
        else
        begin
          SameNum(Format('%s node %s label opacity', [tag, nm]),
            FChart.List.Element(m.Caption).Style.Alpha, lab, 'opacity');
          Inc(FCompared);
          if FChart.List.Element(m.Caption).Z2 <= el.Z2 then
            Miss(Format('%s node %s covers its label', [tag, nm]));
        end;
      end;
    end;
  end;

  for j := 0 to edges.Count - 1 do
  begin
    o := TJSONObject(edges.Items[j]);
    if o.Get('zeroLength', False) then Continue;
    k := o.Integers['link'];
    m := MarksOf(FChart.List, si, k, True);
    Inc(FCompared);
    if m.Line < 0 then
    begin
      Miss(Format('%s link %d has no line here', [tag, k]));
      Continue;
    end;
    el := FChart.List.Element(m.Line);
    SameNum(Format('%s link %d opacity', [tag, k]), el.Style.Alpha, o, 'opacity');
    SameBytes(Format('%s link %d stroke', [tag, k]), el.Style.StrokeColor, o,
      'strokeBytes');
    SameNum(Format('%s link %d width', [tag, k]), el.Style.StrokeWidthLogical,
      o, 'lineWidth');
    ez[j] := el.Z2;
    eupz[j] := o.Integers['z2'];
    eOk[j] := True;
    { THE ARROWHEADS, from then to, as the builder adds them. }
    arrowAt := 0;
    for s := 0 to 1 do
      if o.Find(cSides[s]) is TJSONObject then
      begin
        arr := o.Objects[cSides[s]];
        Inc(FCompared);
        if arrowAt > High(m.Arrows) then
        begin
          Miss(Format('%s link %d has no %s here', [tag, k, cSides[s]]));
          Continue;
        end;
        el := FChart.List.Element(m.Arrows[arrowAt]);
        Inc(arrowAt);
        SameNum(Format('%s link %d %s opacity', [tag, k, cSides[s]]),
          el.Style.Alpha, arr, 'opacity');
        SameBytes(Format('%s link %d %s fill', [tag, k, cSides[s]]),
          el.Style.FillColor, arr, 'fillBytes');
      end;
  end;

  { THE ORDER, pair by pair. }
  for i := 0 to High(nz) do
    for k := i + 1 to High(nz) do
      if nOk[i] and nOk[k] then
      begin
        Inc(FCompared);
        if Sign(nz[i] - nz[k]) <> Sign(nupz[i] - nupz[k]) then
          Miss(Format('%s nodes %d and %d are ordered otherwise', [tag, i, k]));
      end;
  for j := 0 to High(ez) do
  begin
    for k := j + 1 to High(ez) do
      if eOk[j] and eOk[k] then
      begin
        Inc(FCompared);
        if Sign(ez[j] - ez[k]) <> Sign(eupz[j] - eupz[k]) then
          Miss(Format('%s edges %d and %d are ordered otherwise', [tag, j, k]));
      end;
    for i := 0 to High(nz) do
      if eOk[j] and nOk[i] then
      begin
        Inc(FCompared);
        if Sign(ez[j] - nz[i]) <> Sign(eupz[j] - nupz[i]) then
          Miss(Format('%s edge %d and node %d are ordered otherwise', [tag, j, i]));
      end;
  end;
end;

procedure TAdvChartGraphFocusOracleTest.CheckRecord(ARecord: TJSONObject;
  AStep: Integer);
var arr: TJSONArray; i: Integer; keep: string;
begin
  keep := FName;
  FName := keep + ' @' + IntToStr(AStep);
  try
    arr := ARecord.Arrays['series'];
    for i := 0 to arr.Count - 1 do
      CheckSeries(TJSONObject(arr.Items[i]));
  finally
    FName := keep;
  end;
end;

procedure TAdvChartGraphFocusOracleTest.TestEveryHoverLooksAsUpstreamDrawsIt;
var
  cases, steps, records, pt: TJSONArray;
  cs, st: TJSONObject;
  c, k: Integer;
begin
  cases := TJSONObject(FRoot).Arrays['cases'];
  for c := 0 to cases.Count - 1 do
  begin
    cs := TJSONObject(cases.Items[c]);
    FName := cs.Strings['name'];
    if cs.Get('documentary', False) or cs.Get('deferred', False) then Continue;
    Inc(FCases);
    FChart.Option := '';
    FChart.Option := cs.Objects['option'].AsJSON;
    FChart.SetBounds(0, 0, cs.Integers['W'], cs.Integers['H']);
    FChart.Leave;
    RenderNow;
    steps := cs.Arrays['steps'];
    records := cs.Arrays['records'];
    CheckRecord(TJSONObject(records.Items[0]), 0);
    for k := 0 to steps.Count - 1 do
    begin
      st := TJSONObject(steps.Items[k]);
      Inc(FSteps);
      if st.Find('hover') is TJSONArray then
      begin
        pt := st.Arrays['hover'];
        { WHAT IS UNDER THE POINTER, against the list the last paint left. }
        CheckHit(TJSONObject(records.Items[k + 1]).Find('hit'),
          pt.Integers[0], pt.Integers[1]);
        FChart.Hover(pt.Integers[0], pt.Integers[1]);
      end
      else if st.Find('leave') <> nil then
        FChart.Leave
      else
        Miss('a step this test does not know: ' + st.AsJSON);
      RenderNow;
      CheckRecord(TJSONObject(records.Items[k + 1]), k + 1);
    end;
  end;
  AssertTrue(Format('every case ran (%d)', [FCases]), FCases >= 40);
  AssertTrue(Format('the steps ran (%d)', [FSteps]), FSteps >= 100);
  AssertTrue(Format('and a great deal was compared (%d)', [FCompared]),
    FCompared > 5000);
  AssertEquals(IntToStr(FBad) + ' of ' + IntToStr(FCompared)
    + ' disagree with upstream:' + FReport, 0, FBad);
end;

procedure TAdvChartGraphFocusTest.TestTheResolverKeepsADeclaredBlurOpacity;
var normal, state, res: TTyChartStyle; states: TTyChartStateList;
begin
  normal := TyChartNoStyle;
  TyChartSetNum(normal, cskOpacity, 0.8);
  states := Default(TTyChartStateList);
  states.Blur := True;
  res := TyChartResolveStyle(normal, TyChartNoStyle, states);
  AssertTrue('nothing declared: the normal one at a tenth',
    res.Num[cskOpacity] = 0.8 * TyChartBlurOpacityFactor);
  state := TyChartNoStyle;
  TyChartSetNum(state, cskOpacity, 0.3);
  res := TyChartResolveStyle(normal, state, states);
  AssertTrue('declared: as written', res.Num[cskOpacity] = 0.3);
end;

procedure TAdvChartGraphFocusTest.TestTheCachedPictureFollowsTheHover;
var a, e: TPoint; rest: TBGRAPixel;
begin
  FChart.Option := Format(cGraph, ['0.5', '']);
  { THROUGH THE CACHE, the way a window paints: a hover and a leave must
    each throw the cached picture away. }
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Cached(FBmp.Canvas, Rect(0, 0, 400, 300), 96);
  a := NodeAt(0);
  e := NodeAt(4);
  rest := Px(a.X, a.Y);
  FChart.Hover(e.X, e.Y);
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Cached(FBmp.Canvas, Rect(0, 0, 400, 300), 96);
  AssertFalse('the hover dims A', Px(a.X, a.Y) = rest);
  FChart.Leave;
  FBmp.Fill(BGRA(255, 255, 255, 255));
  FChart.Cached(FBmp.Canvas, Rect(0, 0, 400, 300), 96);
  AssertTrue('and leaving brings it back', Px(a.X, a.Y) = rest);
end;

procedure TAdvChartGraphFocusTest.TestASecondHoverBeforeARepaintStillLands;
var a, e: TPoint;
begin
  Show(Format(cGraph, ['0.5', '']));
  a := NodeAt(0);
  e := NodeAt(4);
  { TWO MOVES AND NO PAINT BETWEEN: the second is tested against the list
    the first one left, which a restyle must not throw away. }
  FChart.Hover(a.X, a.Y);
  FChart.Hover(e.X, e.Y);
  RenderNow;
  AssertEquals('E is the one hovered', 1, Alpha(0, 4, False), 0);
  AssertEquals('so A dims', 0.1, Alpha(0, 0, False), 0);
end;

initialization
  RegisterTest(TAdvChartGraphFocusTest);
  RegisterTest(TAdvChartGraphFocusOracleTest);
end.
