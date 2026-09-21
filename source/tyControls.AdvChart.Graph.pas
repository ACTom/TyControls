unit tyControls.AdvChart.Graph;
{$mode objfpc}{$H+}
{ The graph: nodes, the edges between them, and the box they are laid out in.

  THREE COLLECTIONS WHERE EVERY OTHER SERIES HAS ONE. A node list, an edge list
  and a category list, and only the first of them is a data store: the edges
  name their endpoints by NAME or by INDEX and carry their own values, and the
  categories exist to give a node a colour and a legend entry it does not have
  of its own. So this unit reads the store for the nodes and the option tree for
  the other two, the way the radar reads its indicators.

  DATA SPACE AND PIXEL SPACE ARE THE SAME PLACE, USUALLY. The coordinate system
  is a `view`: a data rectangle fitted to a pixel rectangle. The data rectangle
  is the bounding box of the nodes' own written x and y -- and when no node
  writes one, which is every `circular` chart and every `force` chart, that box
  is not a box at all, so upstream REPLACES it with the pixel rectangle and the
  fit becomes the identity. A port that treats the fit as the interesting case
  has it backwards: the interesting case is that there is usually nothing to
  fit, and the layouts therefore work directly in pixels.

  PURE: SysUtils, Math, fpjson and the AdvChart units. No painter, no LCL. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Option,
  tyControls.AdvChart.Coord, tyControls.AdvChart.Data,
  tyControls.AdvChart.Layout, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Labels,
  tyControls.AdvChart.LabelOpt,
  tyControls.AdvChart.Symbol, tyControls.AdvChart.Color;

const
  TyGraphSeriesTypeName = 'graph';

type
  { `layout`, whose default is `null` and whose null means `none`. }
  TTyGraphLayout = (glNone, glCircular, glForce);

  { `lineStyle.color` TAKES TWO WORDS THAT ARE NOT COLOURS. `'source'` and
    `'target'` mean "whatever the node at that end came out", and they are the
    only reason a chord diagram reads as anything but a grey smudge. Every
    other value is a colour, and an unparseable one leaves the theme's. }
  TTyGraphEdgeColourBy = (gecFixed, gecSource, gecTarget);

  { ONE NODE. Positions are kept twice on purpose: X and Y are what the author
    wrote, in DATA space, and may be not-a-number; PX and PY are where the node
    ended up, in device pixels, after a layout ran and the view mapped it. }
  TTyGraphNode = record
    Name_: string;
    Id: string;
    { -1 for a node in no category. }
    Category: Integer;
    X, Y: Double;
    { A node the author placed is not moved by a layout that would have placed
      it -- and `fixed` is written by the DRAG, not by the option, so a port
      with no drag still has to honour it for a node that carries x and y. }
    Fixed: Boolean;
    PX, PY: Double;
    { '' means the series' own symbol. }
    SymbolName: string;
    HasSize: Boolean;
    SizeW, SizeH: Double;
    { The store row this came from, so a mark can name its datum. }
    Row: Integer;
    Value: Double;
  end;
  TTyGraphNodeArray = array of TTyGraphNode;

  { ONE EDGE. The endpoints are resolved to node INDICES here; upstream keeps
    them as names until the graph is built and then resolves them the same way,
    and an edge naming a node that is not there is dropped rather than drawn to
    nowhere. }
  TTyGraphEdge = record
    Source, Target: Integer;
    Value: Double;
    Name_: string;
    { `lineStyle.curveness` on the edge itself, which beats the automatic
      table -- INCLUDING when it is zero. }
    HasCurveness: Boolean;
    Curveness: Double;
    { What the curveness solver settled on, filled in by TyGraphSolveCurveness. }
    SolvedCurveness: Double;
    Row: Integer;
  end;
  TTyGraphEdgeArray = array of TTyGraphEdge;

  TTyGraphCategory = record
    Name_: string;
    SymbolName: string;
    HasColour: Boolean;
    Colour: TTyChartColor;
  end;
  TTyGraphCategoryArray = array of TTyGraphCategory;

  { The series' own options, minus the ones that belong to a later batch. }
  TTyGraphSpec = record
    Box: TTyBoxSpec;
    Layout: TTyGraphLayout;
    RotateLabel: Boolean;
    { The node symbol every node falls back on. }
    Symbol: TTySymbolSpec;
    { The two ends' arrowheads and their sizes. `['none','none']` and 10. }
    EdgeSymbolFrom, EdgeSymbolTo: string;
    EdgeSizeFrom, EdgeSizeTo: Double;
    { `lineStyle.curveness` at the series level. Beats the table, zero
      included. }
    HasCurveness: Boolean;
    Curveness: Double;
    { `autoCurveness`. Absent, false, 0, '' and not-a-number all mean OFF --
      upstream launders the read through `|| null` and every one of those is
      falsy. `true` is not a mode of its own: it falls through to the numeric
      default of twenty. }
    AutoCurveness: Boolean;
    AutoLength: Double;
    { The array form, which replaces the table outright and is never padded. }
    HasAutoList: Boolean;
    AutoList: TTyDoubleArray;
    LineWidthLogical: Double;
    LineOpacity: Double;
    HasLineColour: Boolean;
    LineColour: TTyChartColor;
    ColourBy: TTyGraphEdgeColourBy;
    Z, Z2: Integer;
  end;

  { A DATA RECTANGLE FITTED TO A PIXEL RECTANGLE, and nothing else.

    NOT AN AXIS PAIR. A graph has no scales, no ticks and no extent to nice --
    the numbers a node carries are positions, not measurements, so there is
    nothing here for TTyAxis to do. Answering DimCount 2 and AxisCount 0 is the
    honest shape, and it is what the radar does for the same reason.

    Non-refcounted, like every coordinate system here: the chart owns it and a
    box container holding it is a temporary. }
  TTyGraphView = class(TTyNonRefCountedObject, ITyCoordSys)
  private
    FDataRect: TTyRectF;
    FViewRect: TTyRectF;
    function ScaleX: Double;
    function ScaleY: Double;
  public
    constructor Create(const ADataRect, AViewRect: TTyRectF);
    function CoordSysName: string;
    function DimCount: Integer;
    function GetRect: TTyRectF;
    { THE DATA RECTANGLE, which is what upstream's getBoundingRect answers --
      and the circular layout lays its ring out inside THAT, not inside the
      pixel rect. On the ordinary chart the two are the same rectangle, which
      is exactly why the distinction is easy to lose. }
    function GetDataRect: TTyRectF;
    function DataToPoint(const AData: array of Double): TTyPointF;
    function DataToLayout(const AData: array of Double): TTyCoordLayout;
    function PointToData(const APoint: TTyPointF; out AData: TTyDoubleArray): Boolean;
    function ContainPoint(const APoint: TTyPointF): Boolean;
    function AxisCount: Integer;
    function GetAxis(AIndex: Integer): TTyAxis;
  end;

function TyGraphSpecDefault: TTyGraphSpec;
function TyGraphSpecOf(AOption: TTyChartOption; ASlot: Integer): TTyGraphSpec;

{ The nodes, out of the series' own store. Names, values and every scalar leaf
  the author wrote on a data item are already in there; this turns them into the
  record the layouts and the builder work on. }
function TyGraphNodesOf(AStore: TTyDataStore;
  const ACategories: TTyGraphCategoryArray): TTyGraphNodeArray;

{ The edges, out of the option tree. `links` and `edges` are the same key under
  two names and upstream reads whichever is there, preferring neither. }
function TyGraphEdgesOf(AOption: TTyChartOption; ASlot: Integer;
  const ANodes: TTyGraphNodeArray): TTyGraphEdgeArray;

function TyGraphCategoriesOf(AOption: TTyChartOption;
  ASlot: Integer): TTyGraphCategoryArray;

{ THE DATA RECTANGLE, and the aspect the box solver needs.

  Upstream's own order, which matters: the bounding box is taken from the
  written positions, a degenerate axis is widened by exactly one on each side,
  and the aspect is computed AFTER that widening. Only then is the box solved --
  and only then, if the aspect turned out to be not-a-number, is the data
  rectangle thrown away and replaced by the box.

  Answers False when no node wrote a position, which is the case the caller has
  to handle by using the view rectangle for both. }
function TyGraphDataRect(const ANodes: TTyGraphNodeArray;
  out ARect: TTyRectF; out AAspect: Double): Boolean;

{ The box, with upstream's aspect rule folded in: when neither width nor height
  was written, ONE of them takes 80% of the container -- whichever keeps the
  aspect inside it -- and the other follows from the aspect. }
function TyGraphViewRect(const ASpec: TTyGraphSpec; const AContainer: TTyRectF;
  AAspect: Double): TTyRectF;

{ `layout: 'none'`: every node is where the author put it, and a node the author
  did not place has no position at all. }
procedure TyGraphLayoutNone(var ANodes: TTyGraphNodeArray; AView: TTyGraphView);

{ `layout: 'circular'`: a ring inside the DATA rectangle, each node given an
  angular share of the turn in proportion to how wide its own symbol is. }
procedure TyGraphLayoutCircular(var ANodes: TTyGraphNodeArray;
  AView: TTyGraphView; const ASpec: TTyGraphSpec);

{ Entry i of upstream's curveness table.

  `odd(i)` is `-(i + 1) / 10` and `even(i)` is `i / 10`, so the table runs
  0, -0.2, 0.2, -0.4, 0.4 ... -- note the numerator differs between the two
  branches, and index 0 is the only entry that is exactly zero. }
function TyGraphCurvenessAt(AIndex: Integer): Double;

{ How long the table is, from the option and from how many edges share a pair.

  The comment upstream calls this "make sure the length is even" and it is not:
  `length mod 2 ? length + 2 : length + 3` is ODD for every integer input, so
  the documented twenty-entry table is really twenty-three. }
function TyGraphCurvenessLength(const ASpec: TTyGraphSpec;
  AAppend: Integer): Integer;

{ Fill in every edge's SolvedCurveness.

  KEYED ON NODE INDICES, NOT ON A JOINED STRING. Upstream builds a key out of
  the node ids and a three-character delimiter and produces the opposite key by
  splitting that string -- so a node whose id contains the delimiter silently
  loses its direction pairing for ever. Two integers cannot do that, and the
  divergence is deliberate. }
procedure TyGraphSolveCurveness(var AEdges: TTyGraphEdgeArray;
  const ASpec: TTyGraphSpec);

type
  { Everything the builder needs a THEME to answer. This unit never asks what
    colour anything is -- the control resolves the palette, the category
    colours and the label ink and hands them over, which is the same contract
    the pie, the funnel, the gauge and the radar work under. }
  TTyGraphInk = record
    { One per node, already resolved: the category's colour, or the node's own
      itemStyle, or the series' palette entry. }
    NodeFills: TTyChartColorArray;
    EdgeColour: TTyChartColor;
    { The label the author asked for, and the ink to draw it in. }
    Label_: TTyLabelSpec;
    LabelValueDim: Integer;
    SeriesName: string;
  end;

{ The point on a straight line or a quadratic at t, and the tangent there.

  SAMPLED, NOT DRAWN AS A CURVE. The shape record has no bezier: a curved edge
  becomes a polyline, the way the pie's arcs and the pin symbol already do.
  But the arrowheads still need the real tangent at the two ends, and a
  polyline's first segment is not it once the sampling is coarse -- so the
  tangent comes from the curve's own derivative rather than from the points. }
function TyGraphPointAt(const AP1, AP2, ACP: TTyPointF;
  ACurved: Boolean; AT: Double): TTyPointF;
function TyGraphTangentAt(const AP1, AP2, ACP: TTyPointF;
  ACurved: Boolean; AT: Double): TTyPointF;

{ Pull an edge's two ends back off the node symbols they run into.

  AN ARROWHEAD ON A NODE'S CENTRE IS AN ARROWHEAD NOBODY SEES. Upstream trims
  the edge by the node's own radius whenever that end carries a symbol -- and
  only then, so a plain line still runs centre to centre and is covered at both
  ends by the discs it joins.

  ASIZE1 AND ASIZE2 ARE ALREADY HALVED. Upstream halves its scale parameter
  once, at the top of the function, so the distance really is the symbol's
  radius; passing the diameter here trims twice as far as it should. }
procedure TyGraphTrimEdge(var AP1, AP2, ACP: TTyPointF; ACurved: Boolean;
  ASize1, ASize2: Double; AFrom, ATo: Boolean);

{ The rotation an end's arrowhead takes, in DEGREES anticlockwise -- which is
  the port's symbol convention and zrender's.

  AAtEnd is which end: the tail's arrow and the head's arrow differ by the sign
  of the quarter turn and by nothing else. }
function TyGraphArrowRotation(const ATangent: TTyPointF;
  AAtEnd: Boolean): Double;

{ Append the series' edges and nodes to AList and answer how many landed.

  EDGES FIRST. Upstream keeps them in a group below the nodes, and a node drawn
  under its own edges reads as a line crossing it rather than as a thing the
  lines join. }
function TyBuildGraphMarks(ASeriesIndex: Integer; AView: TTyGraphView;
  const ASpec: TTyGraphSpec; const ANodes: TTyGraphNodeArray;
  const AEdges: TTyGraphEdgeArray; const AInk: TTyGraphInk;
  AStore: TTyDataStore; AList: TTyPaintList): Integer;

implementation

{ ==================== the view ==================== }

constructor TTyGraphView.Create(const ADataRect, AViewRect: TTyRectF);
begin
  inherited Create;
  FDataRect := ADataRect;
  FViewRect := AViewRect;
end;

function TTyGraphView.ScaleX: Double;
var w: Double;
begin
  w := FDataRect.Right - FDataRect.Left;
  if (w = 0) or IsNan(w) or IsInfinite(w) then Exit(1);
  Result := (FViewRect.Right - FViewRect.Left) / w;
end;

function TTyGraphView.ScaleY: Double;
var h: Double;
begin
  h := FDataRect.Bottom - FDataRect.Top;
  if (h = 0) or IsNan(h) or IsInfinite(h) then Exit(1);
  Result := (FViewRect.Bottom - FViewRect.Top) / h;
end;

function TTyGraphView.CoordSysName: string;
begin
  Result := 'view';
end;

function TTyGraphView.DimCount: Integer;
begin
  Result := 2;
end;

function TTyGraphView.GetRect: TTyRectF;
begin
  Result := FViewRect;
end;

function TTyGraphView.GetDataRect: TTyRectF;
begin
  Result := FDataRect;
end;

function TTyGraphView.DataToPoint(const AData: array of Double): TTyPointF;
begin
  Result := TyPointF(NaN, NaN);
  if Length(AData) < 2 then Exit;
  { A PURE SCALE AND TRANSLATE, and the two axes scale INDEPENDENTLY. Upstream
    fits the data rect to the view rect with `sx = b.width / a.width` and
    `sy = b.height / a.height` and does not preserve the aspect here; keeping
    it is a separate option nobody sets. }
  Result := TyPointF(
    (AData[0] - FDataRect.Left) * ScaleX + FViewRect.Left,
    (AData[1] - FDataRect.Top) * ScaleY + FViewRect.Top);
end;

function TTyGraphView.DataToLayout(const AData: array of Double): TTyCoordLayout;
var p: TTyPointF;
begin
  Result.Rect := TyInvalidRectF;
  Result.ContentRect := TyInvalidRectF;
  p := DataToPoint(AData);
  if IsNan(p.X) or IsNan(p.Y) then Exit;
  { A NODE HAS NO CELL. There is no band to divide and no baseline to measure
    from, so the datum's rectangle collapses onto the point -- which is the same
    answer a continuous axis gives, for the same reason. }
  Result.Rect := TyRectF(p.X, p.Y, p.X, p.Y);
  Result.ContentRect := Result.Rect;
end;

function TTyGraphView.PointToData(const APoint: TTyPointF;
  out AData: TTyDoubleArray): Boolean;
var sx, sy: Double;
begin
  AData := nil;
  sx := ScaleX;
  sy := ScaleY;
  if (sx = 0) or (sy = 0) then Exit(False);
  SetLength(AData, 2);
  AData[0] := (APoint.X - FViewRect.Left) / sx + FDataRect.Left;
  AData[1] := (APoint.Y - FViewRect.Top) / sy + FDataRect.Top;
  Result := True;
end;

function TTyGraphView.ContainPoint(const APoint: TTyPointF): Boolean;
begin
  Result := (APoint.X >= FViewRect.Left) and (APoint.X <= FViewRect.Right)
        and (APoint.Y >= FViewRect.Top) and (APoint.Y <= FViewRect.Bottom);
end;

function TTyGraphView.AxisCount: Integer;
begin
  Result := 0;
end;

function TTyGraphView.GetAxis(AIndex: Integer): TTyAxis;
begin
  if AIndex < 0 then ;
  Result := nil;
end;

{ ==================== the option ==================== }

function NodeAt(AOption: TTyChartOption; ASlot: Integer): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  if AOption = nil then Exit;
  d := AOption.ComponentAt('series', ASlot);
  if d is TJSONObject then Result := TJSONObject(d);
end;

function NumIn(ANode: TJSONObject; const AKey: string; ADefault: Double): Double;
var d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d <> nil) and (d.JSONType = jtNumber) then Result := d.AsFloat;
end;

function StrIn(ANode: TJSONObject; const AKey: string;
  const ADefault: string): string;
var d: TJSONData;
begin
  Result := ADefault;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if (d <> nil) and (d.JSONType = jtString) then Result := d.AsString;
end;

function SubObj(ANode: TJSONObject; const AKey: string): TJSONObject;
var d: TJSONData;
begin
  Result := nil;
  if ANode = nil then Exit;
  d := ANode.Find(AKey);
  if d is TJSONObject then Result := TJSONObject(d);
end;

function TyGraphSpecDefault: TTyGraphSpec;
begin
  Result := Default(TTyGraphSpec);
  Result.Box := TyBoxSpec;
  { `left: 'center'`, `top: 'center'`, and NO width or height. The commented-out
    `width: '80%'` in the source is not dead documentation -- the 0.8 is
    reproduced inside the box solver, but only because both sizes are absent
    and an aspect is supplied. }
  Result.Box.Left := TyBoxCentre;
  Result.Box.Top := TyBoxCentre;
  Result.Layout := glNone;
  Result.RotateLabel := False;
  Result.Symbol := TySymbolDefault('');
  Result.Symbol.Kind := tsyCircle;
  Result.Symbol.Empty := False;
  Result.Symbol.WidthPx := 10;
  Result.Symbol.HeightPx := 10;
  Result.EdgeSymbolFrom := 'none';
  Result.EdgeSymbolTo := 'none';
  Result.EdgeSizeFrom := 10;
  Result.EdgeSizeTo := 10;
  Result.HasCurveness := False;
  Result.Curveness := 0;
  Result.AutoCurveness := False;
  Result.AutoLength := 20;
  Result.HasAutoList := False;
  Result.LineWidthLogical := 1;
  Result.LineOpacity := 0.5;
  Result.HasLineColour := False;
  Result.ColourBy := gecFixed;
  { tokens.color.neutral50. Named here rather than themed because it is the
    value the option tree carries; the control replaces it with a theme colour
    before the builder ever sees it. }
  Result.LineColour := TTyChartColor($FF86878C);
  Result.Z := 2;
  Result.Z2 := 0;
end;

{ `symbolSize` in either of its two forms, as pixels. A graph's is not a box
  value -- there is no band to take a percentage of. }
procedure ReadNodeSize(ANode: TJSONObject; var ASpec: TTyGraphSpec);
var d: TJSONData; a: TJSONArray;
begin
  d := ANode.Find('symbolSize');
  if d = nil then Exit;
  if d.JSONType = jtNumber then
  begin
    ASpec.Symbol.WidthPx := d.AsFloat;
    ASpec.Symbol.HeightPx := d.AsFloat;
    Exit;
  end;
  if not (d is TJSONArray) then Exit;
  a := TJSONArray(d);
  if (a.Count > 0) and (a.Items[0].JSONType = jtNumber) then
    ASpec.Symbol.WidthPx := a.Items[0].AsFloat;
  if (a.Count > 1) and (a.Items[1].JSONType = jtNumber) then
    ASpec.Symbol.HeightPx := a.Items[1].AsFloat
  else if a.Count = 1 then
    ASpec.Symbol.HeightPx := ASpec.Symbol.WidthPx;
end;

procedure ReadEdgeSymbol(ANode: TJSONObject; var ASpec: TTyGraphSpec);
var d: TJSONData; a: TJSONArray;
begin
  d := ANode.Find('edgeSymbol');
  if d <> nil then
  begin
    if d.JSONType = jtString then
    begin
      { A SCALAR NAMES BOTH ENDS. }
      ASpec.EdgeSymbolFrom := d.AsString;
      ASpec.EdgeSymbolTo := d.AsString;
    end
    else if d is TJSONArray then
    begin
      a := TJSONArray(d);
      if (a.Count > 0) and (a.Items[0].JSONType = jtString) then
        ASpec.EdgeSymbolFrom := a.Items[0].AsString;
      if (a.Count > 1) and (a.Items[1].JSONType = jtString) then
        ASpec.EdgeSymbolTo := a.Items[1].AsString;
    end;
  end;
  d := ANode.Find('edgeSymbolSize');
  if d = nil then Exit;
  if d.JSONType = jtNumber then
  begin
    ASpec.EdgeSizeFrom := d.AsFloat;
    ASpec.EdgeSizeTo := d.AsFloat;
    Exit;
  end;
  if not (d is TJSONArray) then Exit;
  a := TJSONArray(d);
  if (a.Count > 0) and (a.Items[0].JSONType = jtNumber) then
    ASpec.EdgeSizeFrom := a.Items[0].AsFloat;
  if (a.Count > 1) and (a.Items[1].JSONType = jtNumber) then
    ASpec.EdgeSizeTo := a.Items[1].AsFloat;
end;

procedure ReadAutoCurveness(ANode: TJSONObject; var ASpec: TTyGraphSpec);
var d: TJSONData; a: TJSONArray; i, n: Integer;
begin
  d := ANode.Find('autoCurveness');
  if d = nil then Exit;
  case d.JSONType of
    jtBoolean:
      { `true` IS NOT A MODE OF ITS OWN. Neither the number branch nor the array
        branch fires for it, so the table keeps its default length of twenty. }
      ASpec.AutoCurveness := d.AsBoolean;
    jtNumber:
      begin
        { ZERO TURNS IT OFF. The read is laundered through `|| null` and zero is
          falsy, so an author computing this from a possibly-empty array gets
          the feature disabled rather than a table of no entries. }
        ASpec.AutoCurveness := d.AsFloat <> 0;
        if ASpec.AutoCurveness then ASpec.AutoLength := d.AsFloat;
      end;
    jtArray:
      begin
        { AN EMPTY ARRAY DOES NOT TURN IT OFF -- `[] || null` is the array, and
          the array replaces the table outright. It is never padded, so a
          lookup past its end finds nothing. }
        a := TJSONArray(d);
        ASpec.AutoCurveness := True;
        ASpec.HasAutoList := True;
        n := 0;
        SetLength(ASpec.AutoList, a.Count);
        for i := 0 to a.Count - 1 do
          if a.Items[i].JSONType = jtNumber then
          begin
            ASpec.AutoList[n] := a.Items[i].AsFloat;
            Inc(n);
          end;
        SetLength(ASpec.AutoList, n);
      end;
  end;
end;

function TyGraphSpecOf(AOption: TTyChartOption; ASlot: Integer): TTyGraphSpec;
var
  node, sub: TJSONObject;
  d: TJSONData;
  s: string;
  c: TTyChartColor;
  empty: Boolean;
  path: string;
begin
  Result := TyGraphSpecDefault;
  node := NodeAt(AOption, ASlot);
  if node = nil then Exit;

  Result.Box.Left := TyBoxValueOf(node, 'left', Result.Box.Left);
  Result.Box.Top := TyBoxValueOf(node, 'top', Result.Box.Top);
  Result.Box.Right := TyBoxValueOf(node, 'right', Result.Box.Right);
  Result.Box.Bottom := TyBoxValueOf(node, 'bottom', Result.Box.Bottom);
  Result.Box.Width := TyBoxValueOf(node, 'width', Result.Box.Width);
  Result.Box.Height := TyBoxValueOf(node, 'height', Result.Box.Height);

  { `layout: null` IS THE DEFAULT AND IT MEANS `none`. }
  s := StrIn(node, 'layout', '');
  if s = 'circular' then Result.Layout := glCircular
  else if s = 'force' then Result.Layout := glForce
  else Result.Layout := glNone;

  sub := SubObj(node, 'circular');
  if sub <> nil then
  begin
    d := sub.Find('rotateLabel');
    if (d <> nil) and (d.JSONType = jtBoolean) then
      Result.RotateLabel := d.AsBoolean;
  end;

  d := node.Find('symbol');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    Result.Symbol.Kind := TySymbolKindOf(d.AsString, empty, path);
    Result.Symbol.Empty := empty;
    Result.Symbol.PathData := path;
  end;
  ReadNodeSize(node, Result);
  d := node.Find('symbolRotate');
  if (d <> nil) and (d.JSONType = jtNumber) then
    Result.Symbol.RotateDeg := Max(Double(-360), Min(Double(360), d.AsFloat));
  d := node.Find('symbolKeepAspect');
  if (d <> nil) and (d.JSONType = jtBoolean) then
    Result.Symbol.KeepAspect := d.AsBoolean;

  ReadEdgeSymbol(node, Result);

  sub := SubObj(node, 'lineStyle');
  if sub <> nil then
  begin
    d := sub.Find('curveness');
    if (d <> nil) and (d.JSONType = jtNumber) then
    begin
      { ZERO COUNTS. The three consumers all test `<> nil` and nothing else, so
        a written zero beats the automatic table and kills every curve in the
        series -- which is what the option's own comment says it does. }
      Result.HasCurveness := True;
      Result.Curveness := d.AsFloat;
    end;
    Result.LineWidthLogical := NumIn(sub, 'width', Result.LineWidthLogical);
    Result.LineOpacity := NumIn(sub, 'opacity', Result.LineOpacity);
    s := StrIn(sub, 'color', '');
    if s = 'source' then Result.ColourBy := gecSource
    else if s = 'target' then Result.ColourBy := gecTarget
    else if (s <> '') and TyTryParseChartColor(s, c) then
    begin
      Result.HasLineColour := True;
      Result.LineColour := c;
    end;
  end;

  ReadAutoCurveness(node, Result);

  d := node.Find('z');
  if (d <> nil) and (d.JSONType = jtNumber) then
    Result.Z := TyRoundOpt(d.AsFloat, Result.Z);
  d := node.Find('z2');
  if (d <> nil) and (d.JSONType = jtNumber) then
    Result.Z2 := TyRoundOpt(d.AsFloat, Result.Z2);
end;

{ ==================== the three collections ==================== }

function TyGraphCategoriesOf(AOption: TTyChartOption;
  ASlot: Integer): TTyGraphCategoryArray;
var
  node: TJSONObject;
  d: TJSONData;
  a: TJSONArray;
  item: TJSONObject;
  style: TJSONObject;
  i: Integer;
  s: string;
  c: TTyChartColor;
begin
  Result := nil;
  node := NodeAt(AOption, ASlot);
  if node = nil then Exit;
  d := node.Find('categories');
  if not (d is TJSONArray) then Exit;
  a := TJSONArray(d);
  SetLength(Result, a.Count);
  for i := 0 to a.Count - 1 do
  begin
    Result[i] := Default(TTyGraphCategory);
    if a.Items[i].JSONType = jtString then
    begin
      { A BARE STRING IS A NAME. }
      Result[i].Name_ := a.Items[i].AsString;
      Continue;
    end;
    if not (a.Items[i] is TJSONObject) then Continue;
    item := TJSONObject(a.Items[i]);
    Result[i].Name_ := StrIn(item, 'name', '');
    Result[i].SymbolName := StrIn(item, 'symbol', '');
    style := SubObj(item, 'itemStyle');
    if style <> nil then
    begin
      s := StrIn(style, 'color', '');
      if (s <> '') and TyTryParseChartColor(s, c) then
      begin
        Result[i].HasColour := True;
        Result[i].Colour := c;
      end;
    end;
  end;
end;

{ One row's scalar leaf as text, '' when the row did not write that key. }
function RowText(AStore: TTyDataStore; ARow: Integer; const AKey: string): string;
var v: TTyDataValue; k: Integer;
begin
  Result := '';
  if AStore = nil then Exit;
  k := TyOverrideKey(AKey);
  if not AStore.HasOverride(ARow, k) then Exit;
  v := AStore.GetOverride(ARow, k);
  case v.Kind of
    dvkText: Result := v.Text;
    dvkNumber: Result := FloatToStr(v.Num);
    dvkBool: if v.Num <> 0 then Result := 'true' else Result := 'false';
  end;
end;

function RowNum(AStore: TTyDataStore; ARow: Integer; const AKey: string;
  out AValue: Double): Boolean;
var v: TTyDataValue; k: Integer;
begin
  AValue := NaN;
  Result := False;
  if AStore = nil then Exit;
  k := TyOverrideKey(AKey);
  if not AStore.HasOverride(ARow, k) then Exit;
  v := AStore.GetOverride(ARow, k);
  if v.Kind <> dvkNumber then Exit;
  AValue := v.Num;
  Result := True;
end;

function TyGraphNodesOf(AStore: TTyDataStore;
  const ACategories: TTyGraphCategoryArray): TTyGraphNodeArray;
var
  i, j, valCol: Integer;
  s: string;
  v: Double;
begin
  Result := nil;
  if AStore = nil then Exit;
  valCol := AStore.DimIndexOf('value');
  SetLength(Result, AStore.Count);
  for i := 0 to AStore.Count - 1 do
  begin
    Result[i] := Default(TTyGraphNode);
    Result[i].Row := i;
    Result[i].Name_ := AStore.GetName(i);
    { THE ID IS NOT AN OVERRIDE. The store keeps `value`, `name` and `id` out of
      the override table on purpose -- they are the datum's identity rather
      than options written on it -- so it has to be asked for by name. And an
      edge NAMES its endpoints: the gallery's own Les Miserables graph joins
      `"1"` to `"0"`, which are ids, while every node's name is a person. }
    Result[i].Id := AStore.GetId(i);
    Result[i].Category := -1;
    if valCol >= 0 then Result[i].Value := AStore.Get(valCol, i)
    else Result[i].Value := NaN;

    { A NODE WITH NO x IS NOT A NODE AT ZERO. Upstream coerces whatever the
      option model answers with a unary plus, and `+undefined` is not a number
      -- which is the whole reason the view has a second branch. }
    Result[i].X := NaN;
    Result[i].Y := NaN;
    if RowNum(AStore, i, 'x', v) then Result[i].X := v;
    if RowNum(AStore, i, 'y', v) then Result[i].Y := v;
    { `fixed` IS THE DRAG'S WORD, NOT THE OPTION'S. Upstream writes it onto the
      LAYOUT when a drag ends, and the layouts then leave that node where the
      hand put it. A written x and y is a different thing entirely: it says
      where the node goes under `layout: 'none'`, and it feeds the data
      rectangle -- but it does not stop `circular` laying the node out, and
      treating it as a pin leaves every positioned dataset drawn as if no
      layout had been asked for. There is no drag here yet, so this is always
      false and the field is what the drag will set. }
    Result[i].Fixed := False;
    Result[i].PX := NaN;
    Result[i].PY := NaN;

    Result[i].SymbolName := RowText(AStore, i, 'symbol');
    if RowNum(AStore, i, 'symbolSize', v) then
    begin
      Result[i].HasSize := True;
      Result[i].SizeW := v;
      Result[i].SizeH := v;
    end;

    { `category` IS READ THREE DIFFERENT WAYS UPSTREAM -- as an index, as a
      name, and as neither. An index that is out of range and a name nobody
      declared both come to the same thing here: no category. }
    if RowNum(AStore, i, 'category', v) then
    begin
      if (v >= 0) and (v < Length(ACategories)) and (Frac(v) = 0) then
        Result[i].Category := Trunc(v);
    end
    else
    begin
      s := RowText(AStore, i, 'category');
      if s <> '' then
        for j := 0 to High(ACategories) do
          if ACategories[j].Name_ = s then
          begin
            Result[i].Category := j;
            Break;
          end;
    end;
  end;
end;

{ An endpoint, which the author may have written as a name or as an index. }
function ResolveEnd(AData: TJSONData;
  const ANodes: TTyGraphNodeArray): Integer;
var i: Integer; v: Double;
begin
  Result := -1;
  if AData = nil then Exit;
  if AData.JSONType = jtNumber then
  begin
    { AN INDEX IS AN INDEX INTO THE NODE LIST, not a name that happens to be a
      number -- upstream looks the number up in the node list's index map, and
      a node whose NAME is '3' is not what `source: 3` means. }
    v := AData.AsFloat;
    if IsNan(v) or IsInfinite(v) or (Frac(v) <> 0) then Exit;
    if (v < 0) or (v > High(ANodes)) then Exit;
    Exit(Trunc(v));
  end;
  if AData.JSONType <> jtString then Exit;
  for i := 0 to High(ANodes) do
    if ANodes[i].Name_ = AData.AsString then Exit(i);
  for i := 0 to High(ANodes) do
    if (ANodes[i].Id <> '') and (ANodes[i].Id = AData.AsString) then Exit(i);
end;

function TyGraphEdgesOf(AOption: TTyChartOption; ASlot: Integer;
  const ANodes: TTyGraphNodeArray): TTyGraphEdgeArray;
var
  node, item, style: TJSONObject;
  d: TJSONData;
  a: TJSONArray;
  i, n: Integer;
begin
  Result := nil;
  node := NodeAt(AOption, ASlot);
  if node = nil then Exit;
  { `links` AND `edges` ARE ONE KEY UNDER TWO NAMES, and upstream prefers
    neither: it reads `links` and falls back to `edges`. }
  d := node.Find('links');
  if not (d is TJSONArray) then d := node.Find('edges');
  if not (d is TJSONArray) then Exit;
  a := TJSONArray(d);
  SetLength(Result, a.Count);
  n := 0;
  for i := 0 to a.Count - 1 do
  begin
    if not (a.Items[i] is TJSONObject) then Continue;
    item := TJSONObject(a.Items[i]);
    Result[n] := Default(TTyGraphEdge);
    Result[n].Row := i;
    Result[n].Source := ResolveEnd(item.Find('source'), ANodes);
    Result[n].Target := ResolveEnd(item.Find('target'), ANodes);
    { AN EDGE TO A NODE THAT IS NOT THERE IS DROPPED. Drawing it would need a
      point, and there is no point to draw it to. }
    if (Result[n].Source < 0) or (Result[n].Target < 0) then Continue;
    Result[n].Value := NumIn(item, 'value', NaN);
    Result[n].Name_ := StrIn(item, 'name', '');
    style := SubObj(item, 'lineStyle');
    if style <> nil then
    begin
      d := style.Find('curveness');
      if (d <> nil) and (d.JSONType = jtNumber) then
      begin
        Result[n].HasCurveness := True;
        Result[n].Curveness := d.AsFloat;
      end;
    end;
    Inc(n);
  end;
  SetLength(Result, n);
end;

{ ==================== the box ==================== }

function TyGraphDataRect(const ANodes: TTyGraphNodeArray;
  out ARect: TTyRectF; out AAspect: Double): Boolean;
var
  i: Integer;
  l, t, r, b: Double;
begin
  ARect := TyInvalidRectF;
  AAspect := NaN;
  Result := False;
  if Length(ANodes) = 0 then Exit;
  { ONE UNPLACED NODE AND THERE IS NO BOX AT ALL, and that is not a defect to
    route around: upstream folds the positions through Math.min and Math.max, so
    one not-a-number makes every bound not-a-number -- which is exactly what
    sends the whole chart down the "there is nothing to fit" branch, where the
    data rectangle becomes the box and the map becomes the identity. A port that
    skipped the unplaced nodes would fit the ONE node somebody placed to the
    whole canvas and park it in the middle.

    ASKED ONCE, BEFORE THE FOLD. Upstream reaches the same answer by letting the
    not-a-number travel through four separate min/max folds, and a port written
    that way says the rule four times over -- each of the four then shadowing
    the other three, so breaking any one of them is not observable. The rule is
    about the SET of nodes, so it is asked about the set. }
  for i := 0 to High(ANodes) do
    if IsNan(ANodes[i].X) or IsNan(ANodes[i].Y) then Exit;
  l := ANodes[0].X;
  r := ANodes[0].X;
  t := ANodes[0].Y;
  b := ANodes[0].Y;
  for i := 1 to High(ANodes) do
  begin
    l := Min(l, ANodes[i].X);
    r := Max(r, ANodes[i].X);
    t := Min(t, ANodes[i].Y);
    b := Max(b, ANodes[i].Y);
  end;
  { A FLAT AXIS IS WIDENED BY EXACTLY ONE ON EACH SIDE -- so the span becomes
    two, never nothing -- and the aspect is taken AFTER that. Without it a
    single node, or a row of nodes sharing a y, divides by zero. }
  if r - l = 0 then
  begin
    r := r + 1;
    l := l - 1;
  end;
  if b - t = 0 then
  begin
    b := b + 1;
    t := t - 1;
  end;
  ARect := TyRectF(l, t, r, b);
  AAspect := (r - l) / (b - t);
  Result := True;
end;

function TyGraphViewRect(const ASpec: TTyGraphSpec; const AContainer: TTyRectF;
  AAspect: Double): TTyRectF;
var
  cw, ch, w, h, left, top: Double;
  spec: TTyBoxSpec;
begin
  Result := TyInvalidRectF;
  if not TyRectFIsValid(AContainer) then Exit;
  cw := AContainer.Right - AContainer.Left;
  ch := AContainer.Bottom - AContainer.Top;
  if (cw <= 0) or (ch <= 0) then Exit;
  spec := ASpec.Box;

  { THE TWO SIDES FIRST, and `center` is a POSITION here, not a keyword: it is
    rewritten to 50% before it is parsed, so `left` arrives as half the
    container and only a written `right` can turn it into a width. }
  left := TyBoxResolve(spec.Left, cw);
  top := TyBoxResolve(spec.Top, ch);
  if spec.Left.Kind = buAuto then left := NaN;
  if spec.Top.Kind = buAuto then top := NaN;

  w := NaN;
  h := NaN;
  if spec.Width.Kind <> buAuto then w := TyBoxResolve(spec.Width, cw);
  if spec.Height.Kind <> buAuto then h := TyBoxResolve(spec.Height, ch);
  if IsNan(w) and (spec.Right.Kind <> buAuto) and not IsNan(left) then
    w := cw - TyBoxResolve(spec.Right, cw) - left;
  if IsNan(h) and (spec.Bottom.Kind <> buAuto) and not IsNan(top) then
    h := ch - TyBoxResolve(spec.Bottom, ch) - top;

  { THE ASPECT BRANCH, and it is the only reason a graph is 80% of anything.
    With neither size written, ONE axis takes four fifths of the container --
    whichever one the aspect says will then fit -- and the other follows. }
  if not (IsNan(AAspect) or IsInfinite(AAspect) or (AAspect = 0)) then
  begin
    if IsNan(w) and IsNan(h) then
    begin
      if AAspect > cw / ch then w := cw * 0.8 else h := ch * 0.8;
    end;
    if IsNan(w) and not IsNan(h) then w := AAspect * h;
    if IsNan(h) and not IsNan(w) then h := w / AAspect;
  end;
  if IsNan(w) then w := cw;
  if IsNan(h) then h := ch;

  { AND NOW `center` IS READ AGAIN, AS AN ALIGNMENT. The same word does two
    jobs in one function: it was a position three lines ago and it is a
    centring instruction here, and the second reading overwrites the first. }
  if spec.Left.Kind = buCentre then left := cw / 2 - w / 2;
  if spec.Top.Kind = buCentre then top := ch / 2 - h / 2;
  { A FINAL LAUNDERING. Upstream's `left = left || 0` is the only thing that
    turns a not-a-number into a zero.

    A MUTANT OF IT SURVIVES, and the reason is worth writing down rather than
    chasing: a GRAPH cannot reach it. Its own default is `left: 'center'`, and
    nothing an author can write makes that absent -- an unparseable value
    falls back to the default, not to nothing -- so `left` is always a number
    by the time it gets here. Upstream's own derivation of a missing side
    from the opposite one is unreachable for the same reason and is not
    written out. The guard stays because the rule belongs at this step; it is
    not, today, guarding anything. }
  if IsNan(left) or IsInfinite(left) then left := 0;
  if IsNan(top) or IsInfinite(top) then top := 0;

  Result := TyRectF(AContainer.Left + left, AContainer.Top + top,
                    AContainer.Left + left + w, AContainer.Top + top + h);
end;

{ ==================== the layouts ==================== }

procedure TyGraphLayoutNone(var ANodes: TTyGraphNodeArray; AView: TTyGraphView);
var i: Integer; p: TTyPointF;
begin
  if AView = nil then Exit;
  for i := 0 to High(ANodes) do
  begin
    p := AView.DataToPoint([ANodes[i].X, ANodes[i].Y]);
    ANodes[i].PX := p.X;
    ANodes[i].PY := p.Y;
  end;
end;

procedure TyGraphLayoutCircular(var ANodes: TTyGraphNodeArray;
  AView: TTyGraphView; const ASpec: TTyGraphSpec);
var
  rect: TTyRectF;
  cx, cy, r, sumRadian, halfRemain, angle, sz, half: Double;
  halves: array of Double;
  i, count: Integer;
begin
  if AView = nil then Exit;
  count := Length(ANodes);
  if count = 0 then Exit;
  { THE RING IS LAID OUT IN THE DATA RECTANGLE, not in the pixel one. On the
    ordinary circular chart nobody wrote an x, so the two ARE the same rect --
    which is precisely why this is easy to get wrong and impossible to see. }
  rect := AView.GetDataRect;
  if not TyRectFIsValid(rect) then Exit;
  cx := (rect.Right - rect.Left) / 2 + rect.Left;
  cy := (rect.Bottom - rect.Top) / 2 + rect.Top;
  r := Min(rect.Right - rect.Left, rect.Bottom - rect.Top) / 2;
  if (r <= 0) or IsNan(r) or IsInfinite(r) then Exit;

  { PASS ONE: how much of the turn each node's own symbol takes up. }
  SetLength(halves, count);
  sumRadian := 0;
  for i := 0 to count - 1 do
  begin
    if ANodes[i].HasSize then sz := ANodes[i].SizeW
    else sz := ASpec.Symbol.WidthPx;
    { TWO DEFENSIVE LINES, IN THIS ORDER. A size that is not a number becomes
      two -- an arbitrary value, and upstream says so -- and only then is a
      negative one flattened to zero. The order matters: after the first line
      the comparison can no longer see a not-a-number, which is what makes it
      safe on a compiler where comparing against one raises. }
    if IsNan(sz) then sz := 2;
    if sz < 0 then sz := 0;
    half := ArcSin(Min(Double(1), sz / 2 / r));
    { A SYMBOL WIDER THAN THE RING takes a quarter turn to itself. Upstream
      reaches this by asking for the arcsine of something over one and getting
      a not-a-number back; asking for the arcsine of a clamped one is the same
      answer without the trip through not-a-number. }
    if IsNan(half) then half := Pi / 2;
    halves[i] := half;
    sumRadian := sumRadian + half * 2;
  end;

  halfRemain := (2 * Pi - sumRadian) / count / 2;

  { PASS TWO. The angle advances by the node's own half-share before the node
    is placed and by the same half-share after -- so a node sits in the MIDDLE
    of its share rather than at its edge. }
  angle := 0;
  for i := 0 to count - 1 do
  begin
    half := halfRemain + halves[i];
    angle := angle + half;
    if not ANodes[i].Fixed then
    begin
      ANodes[i].X := r * Cos(angle) + cx;
      ANodes[i].Y := r * Sin(angle) + cy;
    end;
    angle := angle + half;
  end;

  { AND THEN THROUGH THE VIEW, because the ring was laid out in data space. }
  TyGraphLayoutNone(ANodes, AView);
end;

{ ==================== curveness ==================== }

function TyGraphCurvenessAt(AIndex: Integer): Double;
begin
  if AIndex < 0 then Exit(0);
  { THE NUMERATOR DIFFERS BETWEEN THE TWO BRANCHES and that is not a typo:
    `(i mod 2 ? i + 1 : i) / 10 * (i mod 2 ? -1 : 1)`. So the table is
    0, -0.2, 0.2, -0.4, 0.4 ... and index zero is the only entry that is
    exactly nothing. }
  if Odd(AIndex) then Result := -(AIndex + 1) / 10
  else Result := AIndex / 10;
end;

function TyGraphCurvenessLength(const ASpec: TTyGraphSpec;
  AAppend: Integer): Integer;
var len: Double;
begin
  if ASpec.HasAutoList then Exit(Length(ASpec.AutoList));
  len := ASpec.AutoLength;
  { THE FIRST CALL HAS NOTHING TO APPEND, and upstream reaches that state by
    comparing against a missing argument -- `undefined > 20` is false in
    JavaScript and an ordered comparison against a not-a-number RAISES here.
    So absence is a negative count rather than a not-a-number. }
  if AAppend > len then len := AAppend;
  { CLAMPED BEFORE THE LOOP. Upstream has no ceiling at all: `autoCurveness` of
    ten million builds a ten-million-entry array, and of infinity never
    terminates. }
  if IsNan(len) then Exit(0);
  len := Max(Double(-1), Min(Double(100000), len));
  { "MAKE SURE THE LENGTH IS EVEN", says the comment, and it does the opposite:
    this is odd for every integer input, so the documented twenty-entry table
    is really twenty-three. }
  if Frac(len) <> 0 then
  begin
    { A FRACTIONAL OPTION REALLY IS FRACTIONAL. JavaScript's remainder is a
      floating-point one, so 2.5 leaves 0.5 -- truthy -- and the loop then runs
      while i is under 4.5, which is five times. }
    len := len + 2;
    Result := Ceil(len);
  end
  else if Odd(Trunc(len)) then Result := Trunc(len) + 2
  else Result := Trunc(len) + 3;
  if Result < 0 then Result := 0;
end;

{ How many edges join the same ordered pair, and where this one sits among
  them. }
procedure PairPosition(const AEdges: TTyGraphEdgeArray; AAt: Integer;
  out AIndex, ACount, AOpposite: Integer; out AForward: Boolean);
var i, firstFwd, firstBack: Integer;
begin
  AIndex := 0;
  ACount := 0;
  AOpposite := 0;
  firstFwd := -1;
  firstBack := -1;
  for i := 0 to High(AEdges) do
  begin
    if (AEdges[i].Source = AEdges[AAt].Source)
      and (AEdges[i].Target = AEdges[AAt].Target) then
    begin
      if i = AAt then AIndex := ACount;
      Inc(ACount);
      if firstFwd < 0 then firstFwd := i;
    end
    else if (AEdges[i].Source = AEdges[AAt].Target)
      and (AEdges[i].Target = AEdges[AAt].Source) then
    begin
      Inc(AOpposite);
      if firstBack < 0 then firstBack := i;
    end;
  end;
  { WHICHEVER PAIR WAS SEEN FIRST IS THE FORWARD ONE, and the other is drawn on
    the far side. With no opposite at all the pair is forward by default.

    A SELF-LOOP IS ITS OWN OPPOSITE upstream -- the key and the opposite key are
    the same string -- so it is always forward and its opposite count is its own
    count. Keyed on two integers, a self-loop falls into the first branch above
    and never the second, which comes to the same answer without the aliasing. }
  AForward := (firstBack < 0) or (firstFwd <= firstBack);
end;

procedure TyGraphSolveCurveness(var AEdges: TTyGraphEdgeArray;
  const ASpec: TTyGraphSpec);
var
  i, idx, total, opp, parity, at, len: Integer;
  isFwd: Boolean;
begin
  for i := 0 to High(AEdges) do
  begin
    { THREE SOURCES, IN THIS ORDER, and each of them counts a written zero: the
      edge's own, then the series', then the table. }
    if AEdges[i].HasCurveness then
    begin
      AEdges[i].SolvedCurveness := AEdges[i].Curveness;
      Continue;
    end;
    if ASpec.HasCurveness then
    begin
      AEdges[i].SolvedCurveness := ASpec.Curveness;
      Continue;
    end;
    if not ASpec.AutoCurveness then
    begin
      AEdges[i].SolvedCurveness := 0;
      Continue;
    end;

    PairPosition(AEdges, i, idx, total, opp, isFwd);
    len := TyGraphCurvenessLength(ASpec, total);
    { THE PARITY CORRECTION, and the array form opts out of it: with a written
      table the author's own entries are used as given. }
    if ASpec.HasAutoList then parity := 0
    else if Odd(total) then parity := 0
    else parity := 1;

    if isFwd then at := parity + idx
    else at := idx + opp + parity;

    if ASpec.HasAutoList then
    begin
      { A WRITTEN TABLE IS NEVER PADDED. Reading past its end finds nothing,
        and nothing becomes a straight line. }
      if (at >= 0) and (at <= High(ASpec.AutoList)) then
        AEdges[i].SolvedCurveness := ASpec.AutoList[at]
      else
        AEdges[i].SolvedCurveness := 0;
    end
    else if at < len then
      AEdges[i].SolvedCurveness := TyGraphCurvenessAt(at)
    else
      AEdges[i].SolvedCurveness := 0;
  end;
end;

{ ==================== the marks ==================== }

{ How finely a curved edge is sampled. An edge is a few hundred pixels at most
  and a quadratic over that span is nearly straight; sixteen steps puts the
  worst-case error well under a pixel, and the port already samples the pie's
  arcs at a comparable rate. }
const
  cEdgeSteps = 16;

function TyGraphPointAt(const AP1, AP2, ACP: TTyPointF;
  ACurved: Boolean; AT: Double): TTyPointF;
var u: Double;
begin
  if not ACurved then
    Exit(TyPointF(AP1.X + (AP2.X - AP1.X) * AT,
                  AP1.Y + (AP2.Y - AP1.Y) * AT));
  u := 1 - AT;
  Result := TyPointF(
    u * u * AP1.X + 2 * u * AT * ACP.X + AT * AT * AP2.X,
    u * u * AP1.Y + 2 * u * AT * ACP.Y + AT * AT * AP2.Y);
end;

function TyGraphTangentAt(const AP1, AP2, ACP: TTyPointF;
  ACurved: Boolean; AT: Double): TTyPointF;
begin
  if not ACurved then
    Exit(TyPointF(AP2.X - AP1.X, AP2.Y - AP1.Y));
  { THE DERIVATIVE, not the chord. At the two ends it collapses to the leg of
    the control polygon -- (cp - p1) at the start and (p2 - cp) at the end --
    which is why an arrowhead on a curved edge points along the curve rather
    than at the other node. }
  Result := TyPointF(
    2 * (1 - AT) * (ACP.X - AP1.X) + 2 * AT * (AP2.X - ACP.X),
    2 * (1 - AT) * (ACP.Y - AP1.Y) + 2 * AT * (AP2.Y - ACP.Y));
end;

{ One coordinate of a quadratic at t. }
function QuadAt(AP0, AP1, AP2, AT: Double): Double;
var u: Double;
begin
  u := 1 - AT;
  Result := u * u * AP0 + 2 * u * AT * AP1 + AT * AT * AP2;
end;

{ THE CURVE CUT AT t, BOTH HALVES. Slots 0..2 are the piece before the cut and
  3..5 the piece after, and the two share the point at the cut. }
procedure QuadSplit(AP0, AP1, AP2, AT: Double; out A0, A1, A2, A3, A4, A5: Double);
var p01, p12, p012: Double;
begin
  p01 := (AP1 - AP0) * AT + AP0;
  p12 := (AP2 - AP1) * AT + AP1;
  p012 := (p12 - p01) * AT + p01;
  A0 := AP0;
  A1 := p01;
  A2 := p012;
  A3 := p012;
  A4 := p12;
  A5 := AP2;
end;

{ Where a quadratic crosses a circle, as a parameter.

  A COARSE SCAN AND THEN A BISECTION, exactly upstream's: nine samples a tenth
  apart pick the nearest, then thirty-two halvings close in. Not an analytic
  solve -- and the comment beside it says why, that the segment is ASSUMED
  monotone in distance from the centre, which for the near end of an edge it
  is. }
function CurveCircleT(const AP0, ACP, AP2, ACentre: TTyPointF;
  ARadius: Double): Double;
var
  i: Integer;
  tt, best, d, diff, nextDiff, interval, r2, nx, ny, px, py: Double;
begin
  r2 := ARadius * ARadius;
  d := Infinity;
  best := 0.1;
  interval := 0.1;
  tt := 0.1;
  while tt <= 0.9 + 1e-9 do
  begin
    px := QuadAt(AP0.X, ACP.X, AP2.X, tt);
    py := QuadAt(AP0.Y, ACP.Y, AP2.Y, tt);
    diff := Abs(Sqr(px - ACentre.X) + Sqr(py - ACentre.Y) - r2);
    if diff < d then
    begin
      d := diff;
      best := tt;
    end;
    tt := tt + 0.1;
  end;

  tt := best;
  for i := 0 to 31 do
  begin
    px := QuadAt(AP0.X, ACP.X, AP2.X, tt);
    py := QuadAt(AP0.Y, ACP.Y, AP2.Y, tt);
    diff := Sqr(px - ACentre.X) + Sqr(py - ACentre.Y) - r2;
    if Abs(diff) < 1e-2 then Break;
    nx := QuadAt(AP0.X, ACP.X, AP2.X, tt + interval);
    ny := QuadAt(AP0.Y, ACP.Y, AP2.Y, tt + interval);
    nextDiff := Sqr(nx - ACentre.X) + Sqr(ny - ACentre.Y) - r2;
    interval := interval / 2;
    if diff < 0 then
    begin
      if nextDiff >= 0 then tt := tt + interval else tt := tt - interval;
    end
    else
    begin
      if nextDiff >= 0 then tt := tt - interval else tt := tt + interval;
    end;
  end;
  Result := tt;
end;

procedure TyGraphTrimEdge(var AP1, AP2, ACP: TTyPointF; ACurved: Boolean;
  ASize1, ASize2: Double; AFrom, ATo: Boolean);
var
  o1, o2: TTyPointF;
  vx, vy, len, tt: Double;
  a0, a1, a2, a3, a4, a5: Double;
  p0, pc, p2: TTyPointF;
begin
  if not (AFrom or ATo) then Exit;
  o1 := AP1;
  o2 := AP2;
  if not ACurved then
  begin
    { THE DIRECTION IS TAKEN ONCE, FROM THE ORIGINAL ENDS, so both trims run
      along the same axis -- and the far end's distance is NEGATED rather than
      the direction being recomputed backwards. }
    vx := o2.X - o1.X;
    vy := o2.Y - o1.Y;
    len := Sqrt(vx * vx + vy * vy);
    { A SELF-LOOP HAS NO DIRECTION AT ALL, so neither end moves -- which is
      upstream's answer too, reached by normalising a zero vector to zero. }
    if len = 0 then Exit;
    vx := vx / len;
    vy := vy / len;
    if AFrom then
    begin
      AP1.X := o1.X + vx * ASize1;
      AP1.Y := o1.Y + vy * ASize1;
    end;
    if ATo then
    begin
      AP2.X := o2.X - vx * ASize2;
      AP2.Y := o2.Y - vy * ASize2;
    end;
    Exit;
  end;

  { THE CURVE'S OWN ORDER IS NOT THE LAYOUT'S. The layout keeps start, end,
    control; the bezier maths wants start, control, end -- and the swap happens
    on the way in and again on the way out. A symmetric graph looks right
    either way, which is what makes this the easiest thing to get backwards. }
  p0 := AP1;
  pc := ACP;
  p2 := AP2;
  if AFrom then
  begin
    tt := CurveCircleT(p0, pc, p2, o1, ASize1);
    QuadSplit(p0.X, pc.X, p2.X, tt, a0, a1, a2, a3, a4, a5);
    p0.X := a3;
    pc.X := a4;
    QuadSplit(p0.Y, pc.Y, p2.Y, tt, a0, a1, a2, a3, a4, a5);
    p0.Y := a3;
    pc.Y := a4;
  end;
  if ATo then
  begin
    { THE FAR END MEASURES AGAINST THE CURVE THE NEAR END ALREADY TRIMMED, but
      against the circle round the ORIGINAL far endpoint. Upstream does it in
      this order and a port that tidies it up moves the far arrowhead. }
    tt := CurveCircleT(p0, pc, p2, o2, ASize2);
    QuadSplit(p0.X, pc.X, p2.X, tt, a0, a1, a2, a3, a4, a5);
    pc.X := a1;
    p2.X := a2;
    QuadSplit(p0.Y, pc.Y, p2.Y, tt, a0, a1, a2, a3, a4, a5);
    pc.Y := a1;
    p2.Y := a2;
  end;
  AP1 := p0;
  ACP := pc;
  AP2 := p2;
end;

function TyGraphArrowRotation(const ATangent: TTyPointF;
  AAtEnd: Boolean): Double;
var sign: Double;
begin
  { A QUARTER TURN EITHER WAY, MINUS THE TANGENT'S OWN ANGLE. The sign selector
    is the only thing that tells the tail's arrow from the head's, and it is
    upstream's `(percent === 1 ? -1 : 1)` written out. }
  if AAtEnd then sign := -1 else sign := 1;
  if (ATangent.X = 0) and (ATangent.Y = 0) then Exit(0);
  Result := RadToDeg(sign * Pi / 2 - ArcTan2(ATangent.Y, ATangent.X));
end;

function TyBuildGraphMarks(ASeriesIndex: Integer; AView: TTyGraphView;
  const ASpec: TTyGraphSpec; const ANodes: TTyGraphNodeArray;
  const AEdges: TTyGraphEdgeArray; const AInk: TTyGraphInk;
  AStore: TTyDataStore; AList: TTyPaintList): Integer;
var
  i, k, edgeAt: Integer;
  p1, p2, cp, pt, tan_: TTyPointF;
  curved: Boolean;
  c, cx, cy, x12, y12, sz: Double;
  pts: TTyPointFArray;
  rect: TTyRectF;
  sym: TTySymbolSpec;
  el: TTyChartElement;
  shape: TTyChartShape;
  empty: Boolean;
  path: string;
  fill: TTyChartColor;

  { WHAT ONE EDGE IS DRAWN IN. `'source'` and `'target'` take the node's own
    colour, which is already resolved and sitting in the ink. }
  function EdgeColour(AAt: Integer): TTyChartColor;
  var at: Integer;
  begin
    Result := AInk.EdgeColour;
    if ASpec.ColourBy = gecFixed then Exit;
    if (AAt < 0) or (AAt > High(AEdges)) then Exit;
    if ASpec.ColourBy = gecSource then at := AEdges[AAt].Source
    else at := AEdges[AAt].Target;
    if (at >= 0) and (at <= High(AInk.NodeFills)) then Result := AInk.NodeFills[at];
  end;

  { HALF THE NODE'S SIZE -- its radius -- and an oblong symbol is AVERAGED to
    one number first. A node written as [20, 4] is pulled back by twelve
    halved, not by ten and not by two. }
  function NodeRadius(AIndex: Integer): Double;
  var w, h: Double;
  begin
    Result := 0;
    if (AIndex < 0) or (AIndex > High(ANodes)) then Exit;
    if ANodes[AIndex].HasSize then
    begin
      w := ANodes[AIndex].SizeW;
      h := ANodes[AIndex].SizeH;
    end
    else
    begin
      w := ASpec.Symbol.WidthPx;
      h := ASpec.Symbol.HeightPx;
    end;
    if IsNan(w) or IsNan(h) then Exit;
    Result := (w + h) / 2 / 2;
  end;

  { The arrowhead at one end of the edge just built. }
  procedure Arrow(const AName: string; ASize: Double; AAtEnd: Boolean);
  var s: TTySymbolSpec; e: TTyChartElement; sh: TTyChartShape;
      at: TTyPointF; tg: TTyPointF; em: Boolean; pd: string;
  begin
    if (AName = '') or (AName = 'none') or (ASize <= 0) then Exit;
    s := Default(TTySymbolSpec);
    s.Kind := TySymbolKindOf(AName, em, pd);
    if s.Kind = tsyNone then Exit;
    s.Empty := em;
    s.PathData := pd;
    s.WidthPx := ASize;
    s.HeightPx := ASize;
    if AAtEnd then at := TyGraphPointAt(p1, p2, cp, curved, 1)
    else at := TyGraphPointAt(p1, p2, cp, curved, 0);
    if AAtEnd then tg := TyGraphTangentAt(p1, p2, cp, curved, 1)
    else tg := TyGraphTangentAt(p1, p2, cp, curved, 0);
    s.RotateDeg := TyGraphArrowRotation(tg, AAtEnd);
    sh := TyBuildSymbol(s, at.X, at.Y);
    if (sh.Kind = cskRect) and not TyRectFIsValid(sh.Bounds) then Exit;
    e := TyChartElement(sh);
    e.Style.HasFill := True;
    e.Style.FillColor := EdgeColour(edgeAt);
    e.Style.Alpha := ASpec.LineOpacity;
    e.Z := ASpec.Z;
    e.Z2 := ASpec.Z2;
    { SILENT, like the edge it belongs to: an arrowhead is part of the line's
      picture, not a second thing to point at. }
    e.Silent := True;
    e.Datum := TyChartDatum(ASeriesIndex, -1);
    AList.Add(e);
    Inc(Result);
  end;

begin
  Result := 0;
  if (AList = nil) or (AView = nil) then Exit;
  rect := AView.GetDataRect;
  cx := (rect.Right - rect.Left) / 2 + rect.Left;
  cy := (rect.Bottom - rect.Top) / 2 + rect.Top;

  for i := 0 to High(AEdges) do
  begin
    if (AEdges[i].Source < 0) or (AEdges[i].Source > High(ANodes)) then Continue;
    if (AEdges[i].Target < 0) or (AEdges[i].Target > High(ANodes)) then Continue;
    p1 := TyPointF(ANodes[AEdges[i].Source].PX, ANodes[AEdges[i].Source].PY);
    p2 := TyPointF(ANodes[AEdges[i].Target].PX, ANodes[AEdges[i].Target].PY);
    if IsNan(p1.X) or IsNan(p1.Y) or IsNan(p2.X) or IsNan(p2.Y) then Continue;

    c := AEdges[i].SolvedCurveness;
    { A CURVENESS THAT IS NOT A NUMBER DRAWS A STRAIGHT LINE. Upstream tests it
      with a unary plus rather than against zero, and not-a-number is falsy --
      which is the one place in the whole edge pipeline where a NaN is
      laundered rather than propagated. }
    curved := (not IsNan(c)) and (not IsInfinite(c)) and (c <> 0);
    cp := TyPointF(0, 0);
    if curved then
    begin
      x12 := (p1.X + p2.X) / 2;
      y12 := (p1.Y + p2.Y) / 2;
      if ASpec.Layout = glCircular then
      begin
        { A COMPLETELY DIFFERENT CONTROL POINT. The ring does not offset the
          midpoint perpendicularly -- it multiplies the curveness by three and
          slides the midpoint towards the ring's own centre, so a third puts
          the control point exactly on that centre and more overshoots past
          it. Every edge therefore bows INWARD, which is what makes a chord
          diagram look like one. }
        c := c * 3;
        cp := TyPointF(cx * c + x12 * (1 - c), cy * c + y12 * (1 - c));
      end
      else
      begin
        { AND THE OPERAND ORDERS ARE NOT THE SAME ON THE TWO AXES: x subtracts
          (p1.y - p2.y) and y subtracts (p2.x - p1.x). That is the midpoint
          plus curveness times the perpendicular, written out by hand, and
          copying one line onto the other mirrors every curve. }
        cp := TyPointF(x12 - (p1.Y - p2.Y) * c, y12 - (p2.X - p1.X) * c);
      end;
      if IsNan(cp.X) or IsNan(cp.Y) then curved := False;
    end;

    { AND NOW PULL THE ENDS OFF THE NODES, but only the ends that carry a
      symbol. An arrowhead placed on a node's centre is an arrowhead under a
      fifty-pixel disc, which is what this looked like before. }
    TyGraphTrimEdge(p1, p2, cp, curved,
      NodeRadius(AEdges[i].Source), NodeRadius(AEdges[i].Target),
      (ASpec.EdgeSymbolFrom <> '') and (ASpec.EdgeSymbolFrom <> 'none'),
      (ASpec.EdgeSymbolTo <> '') and (ASpec.EdgeSymbolTo <> 'none'));

    if curved then
    begin
      SetLength(pts, cEdgeSteps + 1);
      for k := 0 to cEdgeSteps do
        pts[k] := TyGraphPointAt(p1, p2, cp, True, k / cEdgeSteps);
    end
    else
    begin
      { A STRAIGHT EDGE OF NO LENGTH IS NOT DRAWN. Two nodes on the same point
        and a self-loop with no curveness both land here, and a polyline from
        a point to itself is a stroke with nowhere to go. }
      if (p1.X = p2.X) and (p1.Y = p2.Y) then Continue;
      SetLength(pts, 2);
      pts[0] := p1;
      pts[1] := p2;
    end;

    el := TyChartElement(TyShapePolyline(pts));
    el.Style.HasFill := False;
    el.Style.StrokeColor := EdgeColour(i);
    el.Style.StrokeWidthLogical := ASpec.LineWidthLogical;
    el.Style.Alpha := ASpec.LineOpacity;
    el.Z := ASpec.Z;
    el.Z2 := ASpec.Z2;
    el.Silent := False;
    { AN EDGE IS ITS OWN DATUM, and it is numbered in the EDGE list -- a
      tooltip that read it as a node index would name whichever node happened
      to share the number. }
    el.Datum := TyChartDatum(ASeriesIndex, AEdges[i].Row);
    el.HitSlopLogical := 4;
    AList.Add(el);
    Inc(Result);

    edgeAt := i;
    Arrow(ASpec.EdgeSymbolFrom, ASpec.EdgeSizeFrom, False);
    Arrow(ASpec.EdgeSymbolTo, ASpec.EdgeSizeTo, True);
  end;

  for i := 0 to High(ANodes) do
  begin
    if IsNan(ANodes[i].PX) or IsNan(ANodes[i].PY) then Continue;
    sym := ASpec.Symbol;
    if ANodes[i].SymbolName <> '' then
    begin
      sym.Kind := TySymbolKindOf(ANodes[i].SymbolName, empty, path);
      sym.Empty := empty;
      sym.PathData := path;
    end;
    if sym.Kind = tsyNone then Continue;
    if ANodes[i].HasSize then
    begin
      sym.WidthPx := ANodes[i].SizeW;
      sym.HeightPx := ANodes[i].SizeH;
    end;
    sz := Min(sym.WidthPx, sym.HeightPx);
    if IsNan(sz) or (sz <= 0) then Continue;

    shape := TyBuildSymbol(sym, ANodes[i].PX, ANodes[i].PY);
    if (shape.Kind = cskRect) and not TyRectFIsValid(shape.Bounds) then Continue;
    fill := 0;
    if (i >= 0) and (i <= High(AInk.NodeFills)) then fill := AInk.NodeFills[i];
    el := TyChartElement(shape);
    el.Style.HasFill := fill <> 0;
    el.Style.FillColor := fill;
    el.Style.Alpha := 1;
    el.Z := ASpec.Z;
    { ABOVE ITS OWN EDGES, by one. They share a z and the list breaks the tie
      by insertion, so the nodes would win anyway -- saying it here is what
      keeps that true the day an edge is appended after a node. }
    el.Z2 := ASpec.Z2 + 1;
    el.Silent := False;
    el.Datum := TyChartDatum(ASeriesIndex, ANodes[i].Row);
    el.HitSlopLogical := 4;
    if AInk.Label_.Show and (AInk.Label_.Position <> tlpNone) then
      el.Caption.Text := TyLabelText(AInk.Label_.Formatter,
        AInk.Label_.DefaultText, AStore, ANodes[i].Row, AInk.SeriesName,
        AInk.LabelValueDim, 0, False);
    AList.Add(el);
    Inc(Result);
  end;
  { Named so the signature is the one the control calls; the point and the
    tangent are read by the nested routine above. }
  pt := TyPointF(0, 0);
  tan_ := pt;
  if (pt.X < -1) and (tan_.X < -1) then ;
end;

end.
