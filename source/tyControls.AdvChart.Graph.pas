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

  { `force.initLayout`: where the solver's nodes START. Null and 'none' start
    from the positions the author wrote and 'circular' from a ring -- and
    ANYTHING ELSE from nothing at all, not even the written positions: upstream
    tests for the two words it knows and leaves every other string with no
    layout, which the solver then fills at random. }
  TTyGraphInitLayout = (gilNone, gilCircular, gilOther);

  { `force`, as written. The two ranges are kept the way the author wrote them;
    `edgeLength` is turned round only where it is used, which is the one place
    upstream turns it round. }
  TTyGraphForceSpec = record
    InitLayout: TTyGraphInitLayout;
    RepulsionLo, RepulsionHi: Double;
    EdgeLengthLo, EdgeLengthHi: Double;
    Gravity: Double;
    Friction: Double;
    { Read and not honoured: there are no frames here to animate the settling
      over, so the layout is always run to the end before anything is drawn --
      which is what upstream does when this is false. }
    LayoutAnimation: Boolean;
  end;

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
    { THE CATEGORY AS A MODEL PARENT, which is not the same thing. Colour
      resolves a category written as a NAME; the option chain that `fixed`
      climbs does not -- upstream indexes its category models with whatever
      the node wrote, and an array indexed by a name finds nothing. -1 unless
      the node wrote an index. }
    ModelCategory: Integer;
    X, Y: Double;
    { THE DRAG'S `fixed`, which the RING honours: upstream's circular layout
      skips a node whose LAYOUT says fixed, and only a drag ever writes that.
      There is no drag yet, so this is always false. }
    Fixed: Boolean;
    { THE OPTION'S `fixed`, which the FORCE layout honours -- a different word
      in a different place. The node's own, if it wrote one, and resolved by
      TyGraphResolvePins into Pinned through the category and then the series,
      the way an item model's parent chain runs. }
    HasOwnFixed: Boolean;
    OwnFixed: Boolean;
    Pinned: Boolean;
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
    { `ignoreForceLayout`: the spring leaves this edge out. It is still drawn,
      and its two ends still push each other apart like any other pair. }
    HasOwnIgnore: Boolean;
    IgnoreForce: Boolean;
    { THE CONTROL POINT, IN PIXELS, authored by the layout pass the way upstream
      authors it -- in DATA space, from the laid-out positions, and only then
      carried through the view. Filled in by TyGraphEdgeGeometry. }
    Curved: Boolean;
    CPX, CPY: Double;
    { A control point that is not a point anybody can draw -- infinite, or a
      thousand screens away -- takes its edge with it. Upstream hands such a
      point to the canvas, which refuses the segment. }
    Hidden: Boolean;
    Row: Integer;
  end;
  TTyGraphEdgeArray = array of TTyGraphEdge;

  TTyGraphCategory = record
    Name_: string;
    SymbolName: string;
    HasColour: Boolean;
    Colour: TTyChartColor;
    { A category is a MODEL PARENT of the nodes that name it by index, so a
      `fixed` written here holds every one of them that did not say otherwise. }
    HasFixed: Boolean;
    Fixed: Boolean;
  end;
  TTyGraphCategoryArray = array of TTyGraphCategory;

  { ONE BOX VALUE, the way upstream's parsePositionOption leaves it: a pixel
    count, a percentage still waiting for its base, or not-a-number -- which is
    what `null`, `''`, `'auto'`, `'Center'` and every other word it does not
    know turn into, and what every step of getLayoutRect then treats as "not
    written". The shared box reader in AdvChart.Layout is kinder than that --
    it lower-cases, trims and takes `centre` -- and the graph's box is the one
    place where the difference moves a picture. }
  TTyGraphPosKind = (gpkNaN, gpkPx, gpkPct);
  TTyGraphPos = record
    Kind: TTyGraphPosKind;
    V: Double;
  end;

  { `preserveAspect`: falsy is off, 'cover' is cover, and every other truthy
    value -- `true`, 'contain', a typo -- is contain. }
  TTyGraphPreserve = (gpaOff, gpaContain, gpaCover);

  { The series' own options, minus the ones that belong to a later batch. }
  TTyGraphSpec = record
    PosLeft, PosTop, PosRight, PosBottom, PosWidth, PosHeight: TTyGraphPos;
    PreserveAspect: TTyGraphPreserve;
    PreserveAlign, PreserveVAlign: string;
    { THE WORDS THE BOX IS ALIGNED BY, which are not the positions. Upstream
      reads `left || right` and `top || bottom` a second time, as the raw
      option values, after the rectangle is solved -- so `left: 'center'` is
      50% first and a centring instruction second, and a position that was a
      NUMBER is no instruction at all. '' when the value that won was not a
      string. }
    AlignH, AlignV: string;
    Layout: TTyGraphLayout;
    Force: TTyGraphForceSpec;
    { The series' own `fixed` and `ignoreForceLayout` -- the last parent every
      node's and every edge's option chain reaches. Undocumented, and not in
      the defaults, and honoured all the same. }
    HasFixed: Boolean;
    Fixed: Boolean;
    HasIgnoreForce: Boolean;
    IgnoreForce: Boolean;
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

{ THE STORE A GRAPH IS READ FROM, built the one way the control and the suite
  both build it: one value column, filled from `data` -- or from `nodes`, the
  node list's other name, when `data` is not there. `data || nodes`, so an
  empty `data` array still wins. The store must be new and empty. }
procedure TyGraphFillStore(AOption: TTyChartOption; ASeriesIndex: Integer;
  AStore: TTyDataStore);

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

{ Every node's `fixed`, resolved the way an item model resolves an option: the
  node's own if it wrote one, else its category's, else the series'. And every
  edge's `ignoreForceLayout` the same way, minus the category. }
procedure TyGraphResolvePins(var ANodes: TTyGraphNodeArray;
  var AEdges: TTyGraphEdgeArray; const ACategories: TTyGraphCategoryArray;
  const ASpec: TTyGraphSpec);

{ Upstream's linearMap with no clamp: a flat domain answers the middle of the
  range (or its one end, when the range is flat too), and a value on either end
  of the domain answers that end of the range EXACTLY, rather than whatever the
  division would have rounded to. }
function TyGraphLinearMap(AValue, ADomain0, ADomain1, ARange0,
  ARange1: Double): Double;

{ THE RANDOM NUMBERS, which are not random. Upstream seeds nothing and draws
  from Math.random, so no two renders of a force graph agree; a control that
  lays out again on every resize cannot do that without the picture jumping.
  So this is a xorshift32 -- tiny, and exactly reproducible in JavaScript,
  which is what lets tools/advchart-oracle hold the port to upstream's own
  output by giving upstream THESE numbers. }
function TyGraphForceSeed(ASeriesIndex: Integer): LongWord;
function TyGraphRandom(var AState: LongWord): Double;

type
  { WHAT A FORCE LAYOUT LEAVES FOR THE NEXT PASS over the same option --
    upstream's `preservedPoints`. Every node's position in the space the
    solver ran in, and the rectangle it ran in.

    Upstream keeps these on the series model, which a merged setOption keeps
    and a replacing one throws away. The control replaces its option whole, so
    it clears this when the option changes and keeps it otherwise: a resize
    continues the layout from where it stood instead of starting again from
    nothing, and a pass that changed nothing the solver can see -- a theme, a
    focus change -- gets the same picture back without running a step. }
  TTyGraphForceState = record
    Valid: Boolean;
    Rect: TTyRectF;
    X, Y: TTyDoubleArray;
  end;

{ How many steps upstream's driver runs from a given starting friction: until
  the friction, shrunk by 0.992 a step, is under a hundredth -- and never fewer
  than TWO, because the layout stage takes one step and the view then steps at
  least once more before it looks at the answer. Capped, because the friction
  is the author's and upstream's loop has no ceiling. }
function TyGraphForceSteps(AFriction: Double): Integer;

{ `layout: 'force'`. The nodes start where `initLayout` (or the previous pass)
  says, fill in at random where it says nothing, and are stepped to rest; the
  answer lands in X and Y, in the solver's space -- the DATA rectangle, which is
  the pixel box whenever any node is unplaced -- and is then carried through
  the view into PX and PY. }
procedure TyGraphLayoutForce(var ANodes: TTyGraphNodeArray;
  const AEdges: TTyGraphEdgeArray; AView: TTyGraphView;
  const ASpec: TTyGraphSpec; ASeed: LongWord;
  var AState: TTyGraphForceState);

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

  TWO FAMILIES. The ring reads the automatic table as it is; every other
  layout -- `none`, `force`, and a graph on axes -- NEGATES what it reads and
  asks for the reversed variant, which turns some of the opposite-direction
  answers round again. ACircular picks which.

  KEYED ON NODE INDICES, NOT ON A JOINED STRING. Upstream builds a key out of
  the node ids and a three-character delimiter and produces the opposite key by
  splitting that string -- so a node whose id contains the delimiter silently
  loses its direction pairing for ever. Two integers cannot do that, and the
  divergence is deliberate. }
procedure TyGraphSolveCurveness(var AEdges: TTyGraphEdgeArray;
  const ASpec: TTyGraphSpec; ACircular: Boolean);

{ Every edge's control point, from the laid-out positions, in DATA space and
  then through the view -- the ring's pulled towards the ring's own centre,
  every other layout's pushed out along the perpendicular. }
procedure TyGraphEdgeGeometry(var AEdges: TTyGraphEdgeArray;
  const ANodes: TTyGraphNodeArray; AView: TTyGraphView; ACircular: Boolean);

{ Every node whose pixel position is not a point anybody can draw becomes
  unplaced. See cTyGraphFarPx. }
procedure TyGraphSanitise(var ANodes: TTyGraphNodeArray);

const
  { A THOUSAND SCREENS. A layout that is the author's arithmetic from end to end
    -- a friction of fifty, a repulsion of a million -- can put a node anywhere
    a Double reaches, and everything downstream squares distances. Past this a
    node is treated as gone, and its edges with it, where upstream would have
    drawn them running off the canvas. }
  cTyGraphFarPx = 1e6;

type
  { One graph series, solved: everything the builder and the ink need. The
    VIEW is the caller's to free. }
  TTyGraphSolved = record
    Spec: TTyGraphSpec;
    Cats: TTyGraphCategoryArray;
    Nodes: TTyGraphNodeArray;
    Edges: TTyGraphEdgeArray;
    View: TTyGraphView;
  end;

{ THE WHOLE LAYOUT PASS FOR ONE GRAPH ON A VIEW, in upstream's order: read the
  three collections, fit the data rectangle, solve the box, lay the nodes out,
  settle the curveness, author the edges' control points.

  THE ARITHMETIC RUNS WITH THE FLOATING-POINT TRAPS OFF, and that is the port,
  not a workaround. Every multiplier in a force layout is the author's, so a
  layout that runs off to infinity is a legal outcome rather than a defect --
  upstream computes it silently and draws what is left. Here an overflow, an
  infinity minus an infinity and even an EQUALITY test against a not-a-number
  raise by default; with the traps off they answer what JavaScript answers,
  which is the thing being ported. The answers are sanitised on the way out,
  so nothing downstream ever sees an infinity. }
function TyGraphSolve(AOption: TTyChartOption; ASeriesIndex: Integer;
  AStore: TTyDataStore; const AContainer: TTyRectF;
  var AForce: TTyGraphForceState): TTyGraphSolved;

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

uses tyControls.AdvChart.Builder;

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
  { `left: 'center'`, `top: 'center'`, and NO width or height. The commented-out
    `width: '80%'` in the source is not dead documentation -- the 0.8 is
    reproduced inside the box solver, but only because both sizes are absent
    and an aspect is supplied. `center` is parsed to 50% before anything reads
    it. }
  Result.PosLeft.Kind := gpkPct;
  Result.PosLeft.V := 50;
  Result.PosTop := Result.PosLeft;
  Result.PosRight.Kind := gpkNaN;
  Result.PosRight.V := NaN;
  Result.PosBottom := Result.PosRight;
  Result.PosWidth := Result.PosRight;
  Result.PosHeight := Result.PosRight;
  Result.PreserveAspect := gpaOff;
  Result.AlignH := 'center';
  Result.AlignV := 'center';
  Result.Layout := glNone;
  { defaultOption.force, transcribed. `repulsion` defaults to a PAIR and
    `edgeLength` to a scalar, which is why the first is a range from nothing to
    fifty and the second is the same thirty at both ends. }
  Result.Force.InitLayout := gilNone;
  Result.Force.RepulsionLo := 0;
  Result.Force.RepulsionHi := 50;
  Result.Force.EdgeLengthLo := 30;
  Result.Force.EdgeLengthHi := 30;
  Result.Force.Gravity := 0.1;
  Result.Force.Friction := 0.6;
  Result.Force.LayoutAnimation := True;
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
{ A SIZE NOBODY CAN DRAW IS A THOUSAND SCREENS. The builder halves, averages
  and squares node and arrow sizes with the traps on, and a symbol a thousand
  screens across covers the canvas exactly as one a googol across does -- so
  the clamp changes nothing anybody sees and nothing downstream overflows. }
function SaneSize(AValue: Double): Double;
begin
  Result := AValue;
  if IsNan(Result) then Exit;
  if Result > cTyGraphFarPx then Result := cTyGraphFarPx
  else if Result < -cTyGraphFarPx then Result := -cTyGraphFarPx;
end;

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

{ JavaScript's truthiness, for an option value that is tested rather than used.
  Null is falsy here and absent is the caller's business -- the two differ in
  where the option chain goes next, not in this answer. }
function JsTruthy(AData: TJSONData): Boolean;
var v: Double;
begin
  Result := False;
  if AData = nil then Exit;
  case AData.JSONType of
    jtBoolean: Result := AData.AsBoolean;
    jtNumber:
      begin
        v := AData.AsFloat;
        Result := (not IsNan(v)) and (v <> 0);
      end;
    jtString: Result := AData.AsString <> '';
    jtArray, jtObject: Result := True;
  end;
end;

{ A value used in ARITHMETIC, the way JavaScript coerces one: a number is
  itself, null is nothing, a boolean is nought or one. Anything else -- a
  string, an object -- is not a number here. Upstream would coerce a numeric
  string and CONCATENATE two of them in `(r0 + r1) / 2`; neither is worth
  reproducing for a value the option's type says is a number. }
function JsNum(AData: TJSONData): Double;
begin
  Result := NaN;
  if AData = nil then Exit;
  case AData.JSONType of
    jtNumber: Result := AData.AsFloat;
    jtNull: Result := 0;
    jtBoolean: if AData.AsBoolean then Result := 1 else Result := 0;
  end;
end;

{ A range, read the way upstream reads `repulsion` and `edgeLength`: an ARRAY is
  taken as it is -- a missing second entry is `undefined`, not a copy of the
  first, so `[30]` makes every length not-a-number -- and anything else stands
  for both ends. Absent leaves the default. }
procedure ReadRange(AData: TJSONData; var ALo, AHi: Double);
var a: TJSONArray;
begin
  if AData = nil then Exit;
  if AData is TJSONArray then
  begin
    a := TJSONArray(AData);
    ALo := NaN;
    AHi := NaN;
    if a.Count > 0 then ALo := JsNum(a.Items[0]);
    if a.Count > 1 then AHi := JsNum(a.Items[1]);
    Exit;
  end;
  ALo := JsNum(AData);
  AHi := ALo;
end;

procedure ReadForce(ANode: TJSONObject; var ASpec: TTyGraphSpec);
var sub: TJSONObject; d: TJSONData;
begin
  sub := SubObj(ANode, 'force');
  if sub = nil then Exit;
  d := sub.Find('initLayout');
  { TWO WORDS, TESTED IN THIS ORDER: anything falsy or 'none' starts from the
    written positions, 'circular' from a ring, and everything else falls
    through both tests and starts from nothing. }
  if (d = nil) or not JsTruthy(d) then ASpec.Force.InitLayout := gilNone
  else if (d.JSONType = jtString) and (d.AsString = 'none') then
    ASpec.Force.InitLayout := gilNone
  else if (d.JSONType = jtString) and (d.AsString = 'circular') then
    ASpec.Force.InitLayout := gilCircular
  else
    ASpec.Force.InitLayout := gilOther;
  ReadRange(sub.Find('repulsion'), ASpec.Force.RepulsionLo,
    ASpec.Force.RepulsionHi);
  ReadRange(sub.Find('edgeLength'), ASpec.Force.EdgeLengthLo,
    ASpec.Force.EdgeLengthHi);
  { `== null ? 0.1 : gravity` IN THE SOLVER, not in the defaults -- so a written
    null is the default again, where every other null in this reader is a
    zero. }
  d := sub.Find('gravity');
  if (d <> nil) and (d.JSONType <> jtNull) then ASpec.Force.Gravity := JsNum(d);
  d := sub.Find('friction');
  if (d <> nil) and (d.JSONType <> jtNull) then ASpec.Force.Friction := JsNum(d);
  d := sub.Find('layoutAnimation');
  if d <> nil then ASpec.Force.LayoutAnimation := JsTruthy(d);
end;

{ The alignment word on one axis: `left || right`, as the raw option values. The
  near side has a default -- 'center' -- and so only loses to the far side when
  the author wrote something falsy there, a zero or a null. }
{ `getShallow(key)` ON A SERIES: its own value, unless that is null or absent --
  and then the ROOT's, because a series model's parent is the global one. So an
  undocumented `fixed: true` at the top of the option pins every node of every
  graph, and a stray top-level `width` sizes a graph's box. Upstream's answer
  in both cases, by the same route. }
function ShallowOf(ANode, ARoot: TJSONObject; const AKey: string): TJSONData;
var d: TJSONData;
begin
  Result := nil;
  if ANode <> nil then
  begin
    d := ANode.Find(AKey);
    if (d <> nil) and (d.JSONType <> jtNull) then Exit(d);
  end;
  if ARoot <> nil then
  begin
    d := ARoot.Find(AKey);
    if (d <> nil) and (d.JSONType <> jtNull) then Exit(d);
  end;
end;

{ JavaScript's parseFloat: leading white space skipped, then the longest prefix
  that reads as a decimal number -- sign, digits, a point, an exponent -- or
  `Infinity`. Nothing readable is not-a-number. }
function JsParseFloat(const S: string): Double;
var
  i, n, start, digits: Integer;
  fs: TFormatSettings;
  neg: Boolean;
  body: string;
begin
  Result := NaN;
  n := Length(S);
  i := 1;
  while (i <= n) and (S[i] in [' ', #9, #10, #11, #12, #13]) do Inc(i);
  start := i;
  neg := False;
  if (i <= n) and (S[i] in ['+', '-']) then
  begin
    neg := S[i] = '-';
    Inc(i);
  end;
  if Copy(S, i, 8) = 'Infinity' then
  begin
    if neg then Exit(NegInfinity) else Exit(Infinity);
  end;
  digits := 0;
  while (i <= n) and (S[i] in ['0'..'9']) do
  begin
    Inc(i);
    Inc(digits);
  end;
  if (i <= n) and (S[i] = '.') then
  begin
    Inc(i);
    while (i <= n) and (S[i] in ['0'..'9']) do
    begin
      Inc(i);
      Inc(digits);
    end;
  end;
  if digits = 0 then Exit;
  body := Copy(S, start, i - start);
  { AN EXPONENT ONLY IF IT HAS DIGITS: in `1e` the `e` is not read. }
  if (i <= n) and (S[i] in ['e', 'E']) then
  begin
    n := i + 1;
    if (n <= Length(S)) and (S[n] in ['+', '-']) then Inc(n);
    if (n <= Length(S)) and (S[n] in ['0'..'9']) then
    begin
      while (n <= Length(S)) and (S[n] in ['0'..'9']) do Inc(n);
      body := Copy(S, start, n - start);
    end;
  end;
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  if not TryStrToFloat(body, Result, fs) then Result := NaN;
end;

{ Upstream's parsePositionOption, on one raw option value. The four words are
  matched EXACTLY -- `Center` and `centre` are not words here, they are strings
  parseFloat cannot read -- and a string is a percentage when its trimmed form
  ENDS in a percent sign. Everything that is not a string goes through a unary
  plus: null is not-a-number, false is nought, true is one. }
function GraphPosOf(AData: TJSONData): TTyGraphPos;
var s, trimmed: string; a: TJSONArray;
begin
  Result.Kind := gpkNaN;
  Result.V := NaN;
  if AData = nil then Exit;
  case AData.JSONType of
    jtNumber:
      begin
        Result.Kind := gpkPx;
        Result.V := AData.AsFloat;
      end;
    jtBoolean:
      begin
        Result.Kind := gpkPx;
        if AData.AsBoolean then Result.V := 1 else Result.V := 0;
      end;
    jtString:
      begin
        s := AData.AsString;
        if (s = 'center') or (s = 'middle') then s := '50%'
        else if (s = 'left') or (s = 'top') then s := '0%'
        else if (s = 'right') or (s = 'bottom') then s := '100%';
        trimmed := Trim(s);
        if (trimmed <> '') and (trimmed[Length(trimmed)] = '%') then
          Result.Kind := gpkPct
        else
          Result.Kind := gpkPx;
        Result.V := JsParseFloat(s);
        if IsNan(Result.V) then Result.Kind := gpkNaN;
      end;
    jtArray:
      begin
        { A unary plus on an array: an empty one is nought and one of one
          number is that number; anything longer is not a number. }
        a := TJSONArray(AData);
        if a.Count = 0 then
        begin
          Result.Kind := gpkPx;
          Result.V := 0;
        end
        else if (a.Count = 1) and (a.Items[0].JSONType = jtNumber) then
        begin
          Result.Kind := gpkPx;
          Result.V := a.Items[0].AsFloat;
        end;
      end;
  end;
end;

{ One box value against its base: a percentage of it, a pixel count, or
  not-a-number. }
function ResolvePos(const APos: TTyGraphPos; ABase: Double): Double;
begin
  case APos.Kind of
    gpkPx: Result := APos.V;
    gpkPct: Result := APos.V / 100 * ABase;
  else
    Result := NaN;
  end;
end;

function PosPx(AValue: Double): TTyGraphPos;
begin
  Result.Kind := gpkPx;
  Result.V := AValue;
end;

function PosNaN: TTyGraphPos;
begin
  Result.Kind := gpkNaN;
  Result.V := NaN;
end;

{ The alignment word on one axis: `left || right`, as the raw values the
  option chain answers. The near side has a default -- 'center' -- that a
  series which never wrote it always carries, so it only loses to the far side
  when the author wrote something falsy there: a zero, a false, a null. }
function AlignWord(ANode, ARoot: TJSONObject; const ANear, AFar,
  ADefault: string): string;
var d: TJSONData;
begin
  Result := '';
  if ANode.Find(ANear) = nil then Exit(ADefault);
  d := ShallowOf(ANode, ARoot, ANear);
  if not JsTruthy(d) then d := ShallowOf(ANode, ARoot, AFar);
  if (d <> nil) and (d.JSONType = jtString) then Result := d.AsString;
end;

{ A near side's position: its default 50% when the series never wrote it,
  otherwise whatever the option chain answers -- which for a written null is
  the root's value, and usually nothing at all. }
function NearPos(ANode, ARoot: TJSONObject; const AKey: string;
  const ADefault: TTyGraphPos): TTyGraphPos;
begin
  if ANode.Find(AKey) = nil then Exit(ADefault);
  Result := GraphPosOf(ShallowOf(ANode, ARoot, AKey));
end;

procedure ReadAutoCurveness(ANode: TJSONObject; var ASpec: TTyGraphSpec);
var d: TJSONData; a: TJSONArray; i: Integer;
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
        { EVERY ENTRY KEEPS ITS PLACE. An entry that is not a number is looked up
          by position like any other and draws its edge straight; dropping it
          would slide every later entry down onto the wrong edge. }
        SetLength(ASpec.AutoList, a.Count);
        for i := 0 to a.Count - 1 do
          if a.Items[i].JSONType = jtNumber then
            ASpec.AutoList[i] := a.Items[i].AsFloat
          else
            ASpec.AutoList[i] := NaN;
      end;
  end;
end;

function TyGraphSpecOf(AOption: TTyChartOption; ASlot: Integer): TTyGraphSpec;
var
  node, sub, root: TJSONObject;
  d: TJSONData;
  s: string;
  c: TTyChartColor;
  empty: Boolean;
  path: string;
begin
  Result := TyGraphSpecDefault;
  node := NodeAt(AOption, ASlot);
  if node = nil then Exit;

  root := nil;
  if (AOption <> nil) and (AOption.Root is TJSONObject) then
    root := TJSONObject(AOption.Root);
  Result.PosLeft := NearPos(node, root, 'left', Result.PosLeft);
  Result.PosTop := NearPos(node, root, 'top', Result.PosTop);
  Result.PosRight := GraphPosOf(ShallowOf(node, root, 'right'));
  Result.PosBottom := GraphPosOf(ShallowOf(node, root, 'bottom'));
  Result.PosWidth := GraphPosOf(ShallowOf(node, root, 'width'));
  Result.PosHeight := GraphPosOf(ShallowOf(node, root, 'height'));
  Result.AlignH := AlignWord(node, root, 'left', 'right', Result.AlignH);
  Result.AlignV := AlignWord(node, root, 'top', 'bottom', Result.AlignV);
  { getShallow(key, TRUE): the series' own and nothing above it. }
  d := node.Find('preserveAspect');
  if JsTruthy(d) then
  begin
    if (d.JSONType = jtString) and (d.AsString = 'cover') then
      Result.PreserveAspect := gpaCover
    else
      Result.PreserveAspect := gpaContain;
  end;
  Result.PreserveAlign := StrIn(node, 'preserveAspectAlign', '');
  Result.PreserveVAlign := StrIn(node, 'preserveAspectVerticalAlign', '');

  ReadForce(node, Result);
  d := ShallowOf(node, root, 'fixed');
  if d <> nil then
  begin
    Result.HasFixed := True;
    Result.Fixed := JsTruthy(d);
  end;
  d := ShallowOf(node, root, 'ignoreForceLayout');
  if d <> nil then
  begin
    Result.HasIgnoreForce := True;
    Result.IgnoreForce := JsTruthy(d);
  end;


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
  Result.Symbol.WidthPx := SaneSize(Result.Symbol.WidthPx);
  Result.Symbol.HeightPx := SaneSize(Result.Symbol.HeightPx);
  Result.EdgeSizeFrom := SaneSize(Result.EdgeSizeFrom);
  Result.EdgeSizeTo := SaneSize(Result.EdgeSizeTo);

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
    d := item.Find('fixed');
    if (d <> nil) and (d.JSONType <> jtNull) then
    begin
      Result[i].HasFixed := True;
      Result[i].Fixed := JsTruthy(d);
    end;
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

{ One row's scalar leaf tested for truth, and whether the row wrote it at all --
  the two things an option chain needs to know before it goes to the parent. }
function RowTruthy(AStore: TTyDataStore; ARow: Integer; const AKey: string;
  out AWritten: Boolean): Boolean;
var v: TTyDataValue; k: Integer;
begin
  Result := False;
  AWritten := False;
  if AStore = nil then Exit;
  k := TyOverrideKey(AKey);
  if not AStore.HasOverride(ARow, k) then Exit;
  v := AStore.GetOverride(ARow, k);
  case v.Kind of
    dvkBool: begin AWritten := True; Result := v.Num <> 0; end;
    dvkNumber:
      begin
        AWritten := True;
        Result := (not IsNan(v.Num)) and (v.Num <> 0);
      end;
    dvkText: begin AWritten := True; Result := v.Text <> ''; end;
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
  written: Boolean;
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
    { TWO `fixed`s, IN TWO PLACES, FOR TWO LAYOUTS. The RING honours the one a
      drag writes onto the node's LAYOUT, and there is no drag here yet, so
      that one is always false. The FORCE solver honours the one written in
      the OPTION -- `nodeData.getItemModel(idx).get('fixed')` -- which is read
      here and resolved through the category and the series afterwards.

      AND A WRITTEN x AND y IS NEITHER. It says where a node goes under `none`
      and feeds the data rectangle, but it does not stop the ring laying the
      node out, and reading it as a pin draws every positioned dataset as if
      no layout had been asked for. }
    Result[i].Fixed := False;
    Result[i].OwnFixed := RowTruthy(AStore, i, 'fixed', written);
    Result[i].HasOwnFixed := written;
    Result[i].ModelCategory := -1;
    Result[i].PX := NaN;
    Result[i].PY := NaN;

    Result[i].SymbolName := RowText(AStore, i, 'symbol');
    if RowNum(AStore, i, 'symbolSize', v) then
    begin
      Result[i].HasSize := True;
      Result[i].SizeW := SaneSize(v);
      Result[i].SizeH := Result[i].SizeW;
    end;

    { `category` IS READ THREE DIFFERENT WAYS UPSTREAM -- as an index, as a
      name, and as neither. An index that is out of range and a name nobody
      declared both come to the same thing here: no category. }
    if RowNum(AStore, i, 'category', v) then
    begin
      if (v >= 0) and (v < Length(ACategories)) and (Frac(v) = 0) then
      begin
        Result[i].Category := Trunc(v);
        Result[i].ModelCategory := Result[i].Category;
      end;
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
      { A NUMBER WRITTEN AS A STRING IS STILL AN INDEX to the option chain:
        upstream indexes an ARRAY with it, and `categories['1']` is element
        one. Only the canonical spelling -- '01', '1.0' and ' 1' are property
        names that array does not have. }
      if (s <> '') and (Length(s) <= 9) and ((s = '0') or (s[1] in ['1'..'9']))
        and TryStrToInt(s, j) and (IntToStr(j) = s)
        and (j <= High(ACategories)) then
        Result[i].ModelCategory := j;
    end;
  end;
end;

procedure TyGraphFillStore(AOption: TTyChartOption; ASeriesIndex: Integer;
  AStore: TTyDataStore);
var
  node: TJSONObject;
  d: TJSONData;
  dims: TTySeriesDimArray;
  key: string;
begin
  if AStore = nil then Exit;
  { ONE VALUE COLUMN, and everything else a node carries -- x, y, category,
    symbol, fixed -- arrives as an override under its own name, the way every
    per-datum option in this port does. }
  AStore.AddDimension('value', ddtFloat);
  SetLength(dims, 1);
  dims[0] := Default(TTySeriesDim);
  dims[0].Name := 'value';
  dims[0].Kind := ddtFloat;
  node := NodeAt(AOption, ASeriesIndex);
  if node = nil then Exit;
  { `data || nodes`: the second name is read only when the first is falsy --
    absent or null. An empty `data` array is truthy and wins. }
  key := 'data';
  d := node.Find('data');
  if (d = nil) or not JsTruthy(d) then key := 'nodes';
  TyFillSeriesStore(AOption, ASeriesIndex, dims, AStore, key);
end;

{ An endpoint, which the author may have written as a name or as an index. }
{ The one key a node is filed under: `retrieve(id, name, index)` -- its id if it
  has one, else its name, else its position spelled as a string. ONE key, not
  three: a node that has an id cannot be reached by its name, and a node with
  neither is reached by '0', '1', ... }
function NodeKey(const ANode: TTyGraphNode; AIndex: Integer): string;
begin
  if ANode.Id <> '' then Result := ANode.Id
  else if ANode.Name_ <> '' then Result := ANode.Name_
  else Result := IntToStr(AIndex);
end;

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
  { BY KEY, AND THE FIRST NODE FILED UNDER IT. A second node with the same key
    is refused by upstream's graph -- it says so in the console -- so the
    first is the only one there is to find. }
  for i := 0 to High(ANodes) do
    if NodeKey(ANodes[i], i) = AData.AsString then Exit(i);
end;

{ An edge's `value` the way the edge data reads it: an array gives its first
  entry, and then upstream's parseDataValue -- nothing, null and the empty
  string are not numbers, and everything else goes through Number(), so '4' is
  four and true is one. }
function EdgeValueOf(AData: TJSONData): Double;
var fs: TFormatSettings; s: string;
begin
  Result := NaN;
  if AData = nil then Exit;
  if AData is TJSONArray then
  begin
    if TJSONArray(AData).Count = 0 then Exit;
    AData := TJSONArray(AData).Items[0];
  end;
  case AData.JSONType of
    jtNumber: Result := AData.AsFloat;
    jtBoolean: if AData.AsBoolean then Result := 1 else Result := 0;
    jtString:
      begin
        s := Trim(AData.AsString);
        if s = '' then Exit;
        fs := DefaultFormatSettings;
        fs.DecimalSeparator := '.';
        if s = 'Infinity' then Result := Infinity
        else if s = '-Infinity' then Result := NegInfinity
        else if not TryStrToFloat(s, Result, fs) then Result := NaN;
      end;
  end;
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
  { `edges || links`: TWO NAMES FOR ONE LIST, and `edges` is read first --
    `links` only when `edges` is falsy. An empty `edges` array is truthy and
    wins; a truthy value that is not a list is no edges at all. }
  d := node.Find('edges');
  if (d = nil) or not JsTruthy(d) then d := node.Find('links');
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
    Result[n].Value := EdgeValueOf(item.Find('value'));
    Result[n].Name_ := StrIn(item, 'name', '');
    d := item.Find('ignoreForceLayout');
    if (d <> nil) and (d.JSONType <> jtNull) then
    begin
      Result[n].HasOwnIgnore := True;
      Result[n].IgnoreForce := JsTruthy(d);
    end;
    Result[n].CPX := NaN;
    Result[n].CPY := NaN;
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

type
  { getLayoutRect's input, already read: six positions, the two alignment words,
    and an aspect when there is one. }
  TGraphBoxIn = record
    Left, Top, Right, Bottom, Width, Height: TTyGraphPos;
    AlignH, AlignV: string;
    HasAspect: Boolean;
    Aspect: Double;
  end;

{ `x || 0`: a zero and a not-a-number are both falsy. }
function OrZero(AV: Double): Double;
begin
  if IsNan(AV) then Result := 0 else Result := AV;
end;

{ UPSTREAM'S getLayoutRect, LINE FOR LINE, with no margin -- a graph's box has
  none. The container is given as an origin and a size rather than as a
  rectangle, because the second call preserveAspect makes passes the first
  call's WIDTH, and a width recovered as right minus left is not always the
  same Double.

  Every step is written the way upstream writes it, including the ones whose
  only job is to launder a not-a-number an earlier step made: on a graph with
  no positions the aspect IS a not-a-number, and those steps are what produce
  the box. }
procedure GraphLayoutRect(const AIn: TGraphBoxIn; AX, AY, ACW, ACH: Double;
  out ARect: TTyRectF; out AW, AH: Double);
var left, top, right, bottom, w, h: Double;
begin
  left := ResolvePos(AIn.Left, ACW);
  top := ResolvePos(AIn.Top, ACH);
  right := ResolvePos(AIn.Right, ACW);
  bottom := ResolvePos(AIn.Bottom, ACH);
  w := ResolvePos(AIn.Width, ACW);
  h := ResolvePos(AIn.Height, ACH);

  { A SIZE FROM THE TWO SIDES, which is not-a-number the moment either side is
    -- and on a graph `right` is almost never written, so this is almost always
    not-a-number in, not-a-number out. }
  if IsNan(w) then w := ACW - right - left;
  if IsNan(h) then h := ACH - bottom - top;

  if AIn.HasAspect then
  begin
    { THE ASPECT BRANCH, and it is the only reason a graph is 80% of anything.
      With neither size written, ONE axis takes four fifths of the container
      -- whichever one the aspect says will then fit -- and the other follows.

      A NOT-A-NUMBER ASPECT DOES NOT SKIP THIS, and that is the ordinary case:
      a graph with no positions has no aspect. `NaN > x` is false, so it is
      the HEIGHT that takes four fifths; the width then comes out
      not-a-number from the aspect and is filled in from the container at the
      very end. So the box of a circular or force graph is the full width and
      four fifths of the height -- not the whole container. }
    if IsNan(w) and IsNan(h) then
    begin
      if (not IsNan(AIn.Aspect)) and (AIn.Aspect > ACW / ACH) then
        w := ACW * 0.8
      else
        h := ACH * 0.8;
    end;
    if IsNan(w) then w := AIn.Aspect * h;
    if IsNan(h) and (not IsNan(AIn.Aspect)) and (AIn.Aspect <> 0) then
      h := w / AIn.Aspect;
  end;

  { A MISSING SIDE FROM THE OTHER ONE. }
  if IsNan(left) then left := ACW - right - w;
  if IsNan(top) then top := ACH - bottom - h;

  { AND NOW THE WORDS ARE READ AGAIN, AS AN ALIGNMENT. The same `center` does
    two jobs in one function: it was a position above and it is a centring
    instruction here, and the second reading overwrites the first. With the
    width still not-a-number this makes `left` not-a-number too -- which the
    next line turns into a zero. }
  if AIn.AlignH = 'center' then left := ACW / 2 - w / 2
  else if AIn.AlignH = 'right' then left := ACW - w;
  if (AIn.AlignV = 'middle') or (AIn.AlignV = 'center') then
    top := ACH / 2 - h / 2
  else if AIn.AlignV = 'bottom' then top := ACH - h;

  { `left = left || 0`. Reached on every graph that has no positions. }
  left := OrZero(left);
  top := OrZero(top);
  if IsNan(w) then w := ACW - left - OrZero(right);
  if IsNan(h) then h := ACH - top - OrZero(bottom);

  AW := w;
  AH := h;
  ARect := TyRectF(OrZero(AX) + left, OrZero(AY) + top,
                   OrZero(AX) + left + w, OrZero(AY) + top + h);
end;

function TyGraphViewRect(const ASpec: TTyGraphSpec; const AContainer: TTyRectF;
  AAspect: Double): TTyRectF;
var
  cw, ch, w, h, actual: Double;
  box, inner: TGraphBoxIn;
  wide, narrow, cover: Boolean;
begin
  Result := TyInvalidRectF;
  if not TyRectFIsValid(AContainer) then Exit;
  cw := AContainer.Right - AContainer.Left;
  ch := AContainer.Bottom - AContainer.Top;
  if (cw <= 0) or (ch <= 0) then Exit;

  box.Left := ASpec.PosLeft;
  box.Top := ASpec.PosTop;
  box.Right := ASpec.PosRight;
  box.Bottom := ASpec.PosBottom;
  box.Width := ASpec.PosWidth;
  box.Height := ASpec.PosHeight;
  box.AlignH := ASpec.AlignH;
  box.AlignV := ASpec.AlignV;
  { A GRAPH ALWAYS PASSES AN ASPECT -- a not-a-number one when nothing was
    placed -- so the aspect branch always runs. }
  box.HasAspect := True;
  box.Aspect := AAspect;
  GraphLayoutRect(box, AContainer.Left, AContainer.Top, cw, ch, Result, w, h);
  if ASpec.PreserveAspect = gpaOff then Exit;

  { applyPreserveAspect: the box is laid out again INSIDE ITSELF with one side
    shortened to the data's aspect -- which side depends on which way the two
    aspects disagree and on `cover` -- and aligned by the two preserve words,
    centred when they say nothing. Two aspects within a billionth of a radian
    of each other leave the box alone. }
  actual := w / h;
  { A MUTANT THAT DROPS THIS SURVIVES: laying the box out again when the two
    aspects already agree moves it by rounding alone, far under a millionth of
    a pixel. It is upstream's guard and it stays. }
  if (not IsNan(AAspect)) and (not IsNan(actual))
    and (Abs(ArcTan(AAspect) - ArcTan(actual)) < 1e-9) then Exit;
  inner.Left := PosNaN;
  inner.Top := PosNaN;
  inner.Right := PosNaN;
  inner.Bottom := PosNaN;
  inner.Width := PosPx(w);
  inner.Height := PosPx(h);
  inner.AlignH := '';
  inner.AlignV := '';
  inner.HasAspect := False;
  inner.Aspect := NaN;
  cover := ASpec.PreserveAspect = gpaCover;
  wide := (not IsNan(actual)) and (not IsNan(AAspect)) and (actual > AAspect);
  narrow := (not IsNan(actual)) and (not IsNan(AAspect)) and (actual < AAspect);
  if (wide and not cover) or (narrow and cover) then
  begin
    inner.Width := PosPx(h * AAspect);
    if ASpec.PreserveAlign = 'left' then inner.Left := PosPx(0)
    else if ASpec.PreserveAlign = 'right' then inner.Right := PosPx(0)
    else
    begin
      inner.Left.Kind := gpkPct;
      inner.Left.V := 50;
      inner.AlignH := 'center';
    end;
  end
  else
  begin
    inner.Height := PosPx(w / AAspect);
    if ASpec.PreserveVAlign = 'top' then inner.Top := PosPx(0)
    else if ASpec.PreserveVAlign = 'bottom' then inner.Bottom := PosPx(0)
    else
    begin
      inner.Top.Kind := gpkPct;
      inner.Top.V := 50;
      inner.AlignV := 'middle';
    end;
  end;
  GraphLayoutRect(inner, Result.Left, Result.Top, w, h, Result, w, h);
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

{ ==================== the force layout ==================== }

{ THE TRAPS OFF, for a stretch of arithmetic that is the author's from end to
  end. The pending flags are cleared before the old mask goes back, so nothing
  computed in here can surface as an exception somewhere else later. }
function MaskFP: TFPUExceptionMask;
begin
  Result := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
end;

procedure UnmaskFP(const AMask: TFPUExceptionMask);
begin
  ClearExceptions(False);
  {$IFDEF CPUX86_64}
  { AND THE SSE FLAGS, which ClearExceptions does not touch on this CPU -- it
    clears the x87 status word and nothing else, and a Double here is SSE. Left
    standing, the invalid-operation flag the masked arithmetic raised stays
    sticky, and the NEXT trap anywhere in the host -- a plain division by zero
    -- is reported as an invalid operation instead. }
  SetMXCSR(GetMXCSR and not LongWord($3F));
  {$ENDIF}
  SetExceptionMask(AMask);
end;


procedure TyGraphResolvePins(var ANodes: TTyGraphNodeArray;
  var AEdges: TTyGraphEdgeArray; const ACategories: TTyGraphCategoryArray;
  const ASpec: TTyGraphSpec);
var i, c: Integer;
begin
  for i := 0 to High(ANodes) do
  begin
    { NEAREST FIRST, and a written FALSE stops the climb as surely as a true:
      the chain moves on only when a level said nothing at all. }
    if ANodes[i].HasOwnFixed then
      ANodes[i].Pinned := ANodes[i].OwnFixed
    else
    begin
      c := ANodes[i].ModelCategory;
      if (c >= 0) and (c <= High(ACategories)) and ACategories[c].HasFixed then
        ANodes[i].Pinned := ACategories[c].Fixed
      else
        ANodes[i].Pinned := ASpec.HasFixed and ASpec.Fixed;
    end;
  end;
  { AN EDGE'S PARENT IS THE SERIES and nothing between: there are no edge
    categories. }
  for i := 0 to High(AEdges) do
    if not AEdges[i].HasOwnIgnore then
      AEdges[i].IgnoreForce := ASpec.HasIgnoreForce and ASpec.IgnoreForce;
end;

function TyGraphLinearMap(AValue, ADomain0, ADomain1, ARange0,
  ARange1: Double): Double;
var subDomain, subRange: Double; mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    subDomain := ADomain1 - ADomain0;
    subRange := ARange1 - ARange0;
    { A FLAT DOMAIN IS THE MIDDLE OF THE RANGE -- so with the default
      repulsion of [0, 50] and every node the same value, every node repels at
      twenty-five, which is neither end. }
    if subDomain = 0 then
    begin
      if subRange = 0 then Result := ARange0
      else Result := (ARange0 + ARange1) / 2;
      Exit;
    end;
    { THE TWO ENDS EXACTLY. The division below would land on them to within a
      rounding, and upstream does not leave it to the rounding. }
    if AValue = ADomain0 then Exit(ARange0);
    if AValue = ADomain1 then Exit(ARange1);
    Result := (AValue - ADomain0) / subDomain * subRange + ARange0;
  finally
    UnmaskFP(mask);
  end;
end;

function TyGraphForceSeed(ASeriesIndex: Integer): LongWord;
begin
  {$push}{$R-}{$Q-}
  Result := LongWord(2463534242 + LongWord(ASeriesIndex) * 2654435769);
  {$pop}
  { xorshift has one state it can never leave. }
  if Result = 0 then Result := 2463534242;
end;

const
  cTwo32: Double = 4294967296.0;

function TyGraphRandom(var AState: LongWord): Double;
var x: LongWord;
begin
  {$push}{$R-}{$Q-}
  x := AState;
  x := x xor LongWord(x shl 13);
  x := x xor (x shr 17);
  x := x xor LongWord(x shl 5);
  {$pop}
  AState := x;
  { A TYPED CONSTANT, so the division is a Double one. An untyped real constant
    here is a Single, and so is the arithmetic it takes part in. }
  Result := x / cTwo32;
end;

const
  { Where the driver stops trying. The friction is the author's, the loop
    stops only when it has cooled below a hundredth, and upstream has no
    ceiling: an infinite friction never cools, and a friction of a million
    takes three thousand steps to. This many covers every friction under
    ninety thousand. }
  cForceMaxSteps = 2000;

function TyGraphForceSteps(AFriction: Double): Integer;
var f: Double; mask: TFPUExceptionMask;
begin
  mask := MaskFP;
  try
    { A FRICTION THAT CAN NEVER COOL runs until the ceiling. }
    if IsNan(AFriction) or IsInfinite(AFriction) then Exit(cForceMaxSteps);
    f := AFriction;
    Result := 0;
    repeat
      f := f * 0.992;
      Inc(Result);
    until ((f < 0.01) and (Result >= 2)) or (Result >= cForceMaxSteps);
  finally
    UnmaskFP(mask);
  end;
end;

{ `initLayout: 'circular'` -- the OTHER ring. Not the one `layout: 'circular'`
  draws: this one shares the turn out by VALUE, not by symbol width, and it
  honours no `fixed` of any kind. A node with no value makes its own share
  not-a-number, and every node after it with it -- the angle is a running sum --
  and the solver then starts all of those at random. }
procedure RingByValue(const ANodes: TTyGraphNodeArray; const ARect: TTyRectF;
  var AX, AY: TTyDoubleArray);
var
  i, count: Integer;
  cx, cy, r, sum, unitAngle, angle, half, v, share: Double;
begin
  count := Length(ANodes);
  if count = 0 then Exit;
  cx := (ARect.Right - ARect.Left) / 2 + ARect.Left;
  cy := (ARect.Bottom - ARect.Top) / 2 + ARect.Top;
  r := Min(ARect.Right - ARect.Left, ARect.Bottom - ARect.Top) / 2;
  { THE SUM SKIPS WHAT IS NOT A NUMBER, and a sum of nothing -- or of values
    that cancel -- shares the turn out evenly instead: `sum || count`. }
  sum := 0;
  for i := 0 to count - 1 do
    if not IsNan(ANodes[i].Value) then sum := sum + ANodes[i].Value;
  if IsNan(sum) or (sum = 0) then unitAngle := Pi * 2 / count
  else unitAngle := Pi * 2 / sum;
  angle := 0;
  for i := 0 to count - 1 do
  begin
    v := ANodes[i].Value;
    if IsNan(sum) or (sum = 0) then share := 1 else share := v;
    half := unitAngle * share / 2;
    angle := angle + half;
    AX[i] := r * Cos(angle) + cx;
    AY[i] := r * Sin(angle) + cy;
    angle := angle + half;
  end;
end;

procedure TyGraphLayoutForce(var ANodes: TTyGraphNodeArray;
  const AEdges: TTyGraphEdgeArray; AView: TTyGraphView;
  const ASpec: TTyGraphSpec; ASeed: LongWord;
  var AState: TTyGraphForceState);
var
  n, ne, i, j, k, a, b, steps, total: Integer;
  rect: TTyRectF;
  width, height, cx, cy, gravity, friction, lo, hi, d, w, len_, repFact,
    vx, vy, s, g, xi, yi, ri, ax, ay: Double;
  fi: Boolean;
  ox, oy, px, py, ppx, ppy, rep, elen: TTyDoubleArray;
  qx, qy, qpx, qpy, qr: PDouble;
  fixed_, eign: array of Boolean;
  e1, e2: array of Integer;
  rng: LongWord;
  mask: TFPUExceptionMask;
begin
  if AView = nil then Exit;
  n := Length(ANodes);
  rect := AView.GetDataRect;
  mask := MaskFP;
  try
    if (n = 0) or not TyRectFIsValid(rect) then
    begin
      TyGraphLayoutNone(ANodes, AView);
      Exit;
    end;

    { NOTHING THE SOLVER CAN SEE HAS MOVED, so the answer is the last one. A
      theme change or a focus change lays the chart out again; upstream would
      never have laid it out for those, and running five hundred steps from
      where the last run stopped would nudge every node for no reason. }
    if AState.Valid and (Length(AState.X) = n) and (Length(AState.Y) = n)
      and (AState.Rect.Left = rect.Left) and (AState.Rect.Top = rect.Top)
      and (AState.Rect.Right = rect.Right)
      and (AState.Rect.Bottom = rect.Bottom) then
    begin
      for i := 0 to n - 1 do
      begin
        ANodes[i].X := AState.X[i];
        ANodes[i].Y := AState.Y[i];
      end;
      TyGraphLayoutNone(ANodes, AView);
      Exit;
    end;

    { WHERE EVERY NODE STARTS -- its LAYOUT, in upstream's word, which is also
      where a pinned node stays. Three sources, and the previous pass beats
      both init layouts. }
    SetLength(ox, n);
    SetLength(oy, n);
    if AState.Valid and (Length(AState.X) = n) and (Length(AState.Y) = n) then
      for i := 0 to n - 1 do
      begin
        ox[i] := AState.X[i];
        oy[i] := AState.Y[i];
      end
    else
      case ASpec.Force.InitLayout of
        gilNone:
          for i := 0 to n - 1 do
          begin
            ox[i] := ANodes[i].X;
            oy[i] := ANodes[i].Y;
          end;
        gilCircular:
          RingByValue(ANodes, rect, ox, oy);
      else
        for i := 0 to n - 1 do
        begin
          ox[i] := NaN;
          oy[i] := NaN;
        end;
      end;

    { THE NODE RECORDS. The repulsion comes out of the node's VALUE, mapped from
      the values' own extent onto the range -- not reversed. An extent of no
      values at all is [+inf, -inf], which maps every value to not-a-number,
      which lands on the middle of the range. }
    lo := Infinity;
    hi := NegInfinity;
    for i := 0 to n - 1 do
      if not IsNan(ANodes[i].Value) then
      begin
        if ANodes[i].Value < lo then lo := ANodes[i].Value;
        if ANodes[i].Value > hi then hi := ANodes[i].Value;
      end;
    SetLength(rep, n);
    SetLength(fixed_, n);
    SetLength(px, n);
    SetLength(py, n);
    SetLength(ppx, n);
    SetLength(ppy, n);
    for i := 0 to n - 1 do
    begin
      rep[i] := TyGraphLinearMap(ANodes[i].Value, lo, hi,
        ASpec.Force.RepulsionLo, ASpec.Force.RepulsionHi);
      if IsNan(rep[i]) then
        rep[i] := (ASpec.Force.RepulsionLo + ASpec.Force.RepulsionHi) / 2;
      fixed_[i] := ANodes[i].Pinned;
      px[i] := ox[i];
      py[i] := oy[i];
    end;

    { THE EDGE RECORDS. The rest length comes out of the edge's value -- and
      the range IS reversed, `[edgeLength[1], edgeLength[0]]`, so a heavier
      edge is a SHORTER one. }
    ne := Length(AEdges);
    lo := Infinity;
    hi := NegInfinity;
    for k := 0 to ne - 1 do
      if not IsNan(AEdges[k].Value) then
      begin
        if AEdges[k].Value < lo then lo := AEdges[k].Value;
        if AEdges[k].Value > hi then hi := AEdges[k].Value;
      end;
    SetLength(elen, ne);
    SetLength(eign, ne);
    SetLength(e1, ne);
    SetLength(e2, ne);
    for k := 0 to ne - 1 do
    begin
      elen[k] := TyGraphLinearMap(AEdges[k].Value, lo, hi,
        ASpec.Force.EdgeLengthHi, ASpec.Force.EdgeLengthLo);
      if IsNan(elen[k]) then
        elen[k] := (ASpec.Force.EdgeLengthHi + ASpec.Force.EdgeLengthLo) / 2;
      eign[k] := AEdges[k].IgnoreForce;
      e1[k] := AEdges[k].Source;
      e2[k] := AEdges[k].Target;
    end;

    { THE RANDOM START, for every node with no position: a uniform box exactly
      the size of the rectangle, centred on it, x and then y, node by node.

      A PINNED node with no position draws too, as upstream's does, and its
      draw is thrown away by the line below. Whether it draws CANNOT BE SEEN:
      that node is pinned at not-a-number, which turns every free node into
      not-a-number in the first step, so no position a later draw would have
      decided survives to be looked at. Kept because it is upstream's line; a
      mutant that skips it survives, and that is why. }
    width := rect.Right - rect.Left;
    height := rect.Bottom - rect.Top;
    cx := rect.Left + width / 2;
    cy := rect.Top + height / 2;
    rng := ASeed;
    for i := 0 to n - 1 do
    begin
      if IsNan(px[i]) or IsNan(py[i]) then
      begin
        px[i] := width * (TyGraphRandom(rng) - 0.5) + cx;
        py[i] := height * (TyGraphRandom(rng) - 0.5) + cy;
      end;
      ppx[i] := px[i];
      ppy[i] := py[i];
    end;
    { A PINNED NODE IS WHERE ITS LAYOUT IS, re-read at the top of every step
      upstream so a drag can move it mid-settle. Nothing moves it here, so once
      is every time -- and a pinned node with no layout is pinned at
      not-a-number, which the repulsion then spreads to every free node. That
      is upstream's answer, and the chart draws nothing but the pins. }
    for i := 0 to n - 1 do
      if fixed_[i] then
      begin
        px[i] := ox[i];
        py[i] := oy[i];
      end;

    { The arrays are not resized from here on, so their storage stays put. }
    qx := PDouble(px);
    qy := PDouble(py);
    qpx := PDouble(ppx);
    qpy := PDouble(ppy);
    qr := PDouble(rep);

    gravity := ASpec.Force.Gravity;
    friction := ASpec.Force.Friction;
    total := TyGraphForceSteps(friction);
    { A FRICTION THAT CAN NEVER COOL is a loop upstream never leaves, and the
      only picture it ever shows is the one after its first steps: every free
      node multiplied by something that is not a number. Two steps reach it.

      THIS LINE IS ABOUT THE COST, NOT THE PICTURE: two thousand steps land on
      the same not-a-numbers, only slower. A mutant that deletes it survives,
      and that is the reason. }
    if IsNan(friction) or IsInfinite(friction) then total := 2;

    for steps := 1 to total do
    begin
      { THE SPRINGS, edge by edge and IN PLACE: each edge moves its two ends
        before the next edge reads them. The weight is the far end's share of
        the pair's repulsion, and 0/0 -- two nodes that repel at nothing -- is
        the only way it is not a number. }
      for k := 0 to ne - 1 do
      begin
        if eign[k] then Continue;
        a := e1[k];
        b := e2[k];
        vx := px[b] - px[a];
        vy := py[b] - py[a];
        d := Sqrt(vx * vx + vy * vy) - elen[k];
        w := rep[b] / (rep[a] + rep[b]);
        if IsNan(w) then w := 0;
        len_ := Sqrt(vx * vx + vy * vy);
        if len_ = 0 then
        begin
          vx := 0;
          vy := 0;
        end
        else
        begin
          vx := vx / len_;
          vy := vy / len_;
        end;
        if not fixed_[a] then
        begin
          s := w * d * friction;
          px[a] := px[a] + vx * s;
          py[a] := py[a] + vy * s;
        end;
        if not fixed_[b] then
        begin
          s := -(1 - w) * d * friction;
          px[b] := px[b] + vx * s;
          py[b] := py[b] + vy * s;
        end;
      end;

      { GRAVITY: a LINEAR spring to the centre, not a pull that fades. The
        normalising lines are in upstream's source, commented out. }
      g := gravity * friction;
      for i := 0 to n - 1 do
        if not fixed_[i] then
        begin
          vx := cx - px[i];
          vy := cy - py[i];
          px[i] := px[i] + vx * g;
          py[i] := py[i] + vy * g;
        end;

      { REPULSION, every pair, and it writes the PREVIOUS position, not the
        current one. The sign looks like attraction and is not: the far node's
        previous position is pulled TOWARDS this one, and the next pass moves
        each node along (current - previous) -- which is away. "Fixing" the
        sign turns the layout inside out.

        Two nodes on one point are pushed apart in a random direction -- two
        more draws, x and then y, taken even when both of them are pinned. }
      { THE HOT LOOP -- n squared over two, five hundred times -- so the near
        node's figures are held in locals and its own previous position is
        summed in one. That is the SAME additions in the same order: nothing
        else writes that node's previous position while its row runs, and
        every column before it has already added its share. }
      for i := 0 to n - 1 do
      begin
        xi := qx[i];
        yi := qy[i];
        ri := qr[i];
        fi := fixed_[i];
        ax := qpx[i];
        ay := qpy[i];
        for j := i + 1 to n - 1 do
        begin
          vx := qx[j] - xi;
          vy := qy[j] - yi;
          d := Sqrt(vx * vx + vy * vy);
          if d = 0 then
          begin
            vx := TyGraphRandom(rng) - 0.5;
            vy := TyGraphRandom(rng) - 0.5;
            d := 1;
          end;
          repFact := (ri + qr[j]) / d / d;
          if not fi then
          begin
            ax := ax + vx * repFact;
            ay := ay + vy * repFact;
          end;
          if not fixed_[j] then
          begin
            qpx[j] := qpx[j] + vx * (-repFact);
            qpy[j] := qpy[j] + vy * (-repFact);
          end;
        end;
        qpx[i] := ax;
        qpy[i] := ay;
      end;

      { AND THE STEP ITSELF: along (current - previous), by the friction. }
      for i := 0 to n - 1 do
        if not fixed_[i] then
        begin
          vx := px[i] - ppx[i];
          vy := py[i] - ppy[i];
          px[i] := px[i] + vx * friction;
          py[i] := py[i] + vy * friction;
          ppx[i] := px[i];
          ppy[i] := py[i];
        end;

      friction := friction * 0.992;
    end;

    { THE ANSWER. A free node takes where the solver left it; a pinned one keeps
      its layout, which the solver never writes back. What the next pass starts
      from is every node's solver position, pinned ones included. }
    SetLength(AState.X, n);
    SetLength(AState.Y, n);
    for i := 0 to n - 1 do
    begin
      if fixed_[i] then
      begin
        ANodes[i].X := ox[i];
        ANodes[i].Y := oy[i];
      end
      else
      begin
        ANodes[i].X := px[i];
        ANodes[i].Y := py[i];
      end;
      AState.X[i] := px[i];
      AState.Y[i] := py[i];
    end;
    AState.Rect := rect;
    AState.Valid := True;

    TyGraphLayoutNone(ANodes, AView);
  finally
    UnmaskFP(mask);
  end;
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

{ ONE EDGE, FILED UNDER ITS ORDERED PAIR. Sorting these by pair and then by
  edge gives upstream's edge map without a hash: each run of equal pairs is one
  key, its members in the order they were listed. }
type
  TPairRef = record
    S, T, Edge: Integer;
  end;
  TPairRefArray = array of TPairRef;

function PairLess(const A, B: TPairRef): Boolean;
begin
  if A.S <> B.S then Exit(A.S < B.S);
  if A.T <> B.T then Exit(A.T < B.T);
  Result := A.Edge < B.Edge;
end;

procedure SortPairs(var A: TPairRefArray);
var
  tmp: TPairRefArray;
  n, width, lo, mid, hi, i, j, k: Integer;
begin
  n := Length(A);
  SetLength(tmp, n);
  width := 1;
  while width < n do
  begin
    lo := 0;
    while lo < n do
    begin
      mid := Min(lo + width, n);
      hi := Min(lo + 2 * width, n);
      i := lo;
      j := mid;
      k := lo;
      while (i < mid) and (j < hi) do
      begin
        if PairLess(A[j], A[i]) then
        begin
          tmp[k] := A[j];
          Inc(j);
        end
        else
        begin
          tmp[k] := A[i];
          Inc(i);
        end;
        Inc(k);
      end;
      while i < mid do
      begin
        tmp[k] := A[i];
        Inc(i);
        Inc(k);
      end;
      while j < hi do
      begin
        tmp[k] := A[j];
        Inc(j);
        Inc(k);
      end;
      lo := hi;
    end;
    for k := 0 to n - 1 do A[k] := tmp[k];
    width := width * 2;
  end;
end;

{ The key a pair is filed under, or -1 when no edge runs that way. }
function FindPair(const ASorted: TPairRefArray; const AGroupOf: array of Integer;
  ASrc, ATgt: Integer): Integer;
var lo, hi, mid: Integer;
begin
  Result := -1;
  lo := 0;
  hi := High(ASorted);
  while lo <= hi do
  begin
    mid := (lo + hi) div 2;
    if (ASorted[mid].S < ASrc)
      or ((ASorted[mid].S = ASrc) and (ASorted[mid].T < ATgt)) then
      lo := mid + 1
    else if (ASorted[mid].S = ASrc) and (ASorted[mid].T = ATgt) then
      Exit(AGroupOf[mid])
    else
      hi := mid - 1;
  end;
end;

procedure TyGraphSolveCurveness(var AEdges: TTyGraphEdgeArray;
  const ASpec: TTyGraphSpec; ACircular: Boolean);
var
  n, i, k, g, o, ng, own, opp, total, parity, tableLen: Integer;
  sorted: TPairRefArray;
  groupOf, grp, rank, firstOf, countOf, forwardOf, oppOf: array of Integer;
  res: Double;
  isArray, ledByZero, keep, exists, oppExists: Boolean;

  { One entry of the table in force, or upstream's `undefined` -- here a
    not-a-number -- past its end. }
  function ListAt(AAt: Integer): Double;
  begin
    Result := NaN;
    if AAt < 0 then Exit;
    if isArray then
    begin
      if AAt <= High(ASpec.AutoList) then Result := ASpec.AutoList[AAt];
    end
    else if AAt < tableLen then
      Result := TyGraphCurvenessAt(AAt);
  end;

begin
  n := Length(AEdges);
  { THREE SOURCES, NEAREST FIRST, and each of them counts a written zero: the
    edge's own, then the series', then the table. The written ones are used
    AS WRITTEN under every layout -- the negation below is applied to what the
    table answers and to nothing else. }
  for i := 0 to n - 1 do
    if AEdges[i].HasCurveness then
      AEdges[i].SolvedCurveness := AEdges[i].Curveness
    else if ASpec.HasCurveness then
      AEdges[i].SolvedCurveness := ASpec.Curveness
    else
      AEdges[i].SolvedCurveness := 0;
  if (not ASpec.AutoCurveness) or (n = 0) then Exit;

  { UPSTREAM'S EDGE MAP. Every ordered pair is a key; its members are the
    edges that run that way, in the order they were listed. }
  SetLength(sorted, n);
  for i := 0 to n - 1 do
  begin
    sorted[i].S := AEdges[i].Source;
    sorted[i].T := AEdges[i].Target;
    sorted[i].Edge := i;
  end;
  SortPairs(sorted);
  SetLength(groupOf, n);
  SetLength(grp, n);
  SetLength(rank, n);
  SetLength(firstOf, n);
  SetLength(countOf, n);
  SetLength(forwardOf, n);
  ng := -1;
  for k := 0 to n - 1 do
  begin
    if (k = 0) or (sorted[k].S <> sorted[k - 1].S)
      or (sorted[k].T <> sorted[k - 1].T) then
    begin
      Inc(ng);
      firstOf[ng] := sorted[k].Edge;
      countOf[ng] := 0;
      forwardOf[ng] := 0;
    end;
    groupOf[k] := ng;
    grp[sorted[k].Edge] := ng;
    rank[sorted[k].Edge] := countOf[ng];
    Inc(countOf[ng]);
  end;
  { A SELF-LOOP IS ITS OWN OPPOSITE: the key and the reversed key are the same
    pair, so this finds the loop's own key. }
  SetLength(oppOf, n);
  for i := 0 to n - 1 do
    oppOf[i] := FindPair(sorted, groupOf, AEdges[i].Target, AEdges[i].Source);

  { WHICH WAY IS FORWARD, and it is not "whichever came first". Upstream sets
    the flag as each edge is FILED, looking only at what was filed before it:
    a key that already had members and no opposite becomes forward; a key and
    an opposite that both already had members make the OPPOSITE forward and
    this one not. Nothing else ever sets it -- so a lone edge, and both halves
    of a single there-and-back pair, are never flagged at all, and an unset
    flag reads as NOT forward. A self-loop takes the second branch on its
    second copy and ends up not forward, the two assignments landing on one
    key. Five states of the same small graph disagree with any tidier rule. }
  for i := 0 to n - 1 do
  begin
    g := grp[i];
    o := oppOf[i];
    exists := firstOf[g] < i;
    oppExists := (o >= 0) and (firstOf[o] < i);
    if exists and not oppExists then
      forwardOf[g] := 1
    else if oppExists and exists then
    begin
      forwardOf[o] := 1;
      forwardOf[g] := 2;
    end;
  end;

  isArray := ASpec.HasAutoList;
  { `autoCurvenessParams[0] === 0`, strictly: the NUMBER zero leads the list. }
  ledByZero := isArray and (Length(ASpec.AutoList) > 0)
    and (not IsNan(ASpec.AutoList[0])) and (ASpec.AutoList[0] = 0);

  for i := 0 to n - 1 do
  begin
    if AEdges[i].HasCurveness or ASpec.HasCurveness then Continue;
    g := grp[i];
    o := oppOf[i];
    own := countOf[g];
    if o >= 0 then opp := countOf[o] else opp := 0;
    { BOTH DIRECTIONS, and a self-loop's own count twice over -- both lookups
      find the same key. }
    total := own + opp;
    if isArray then tableLen := Length(ASpec.AutoList)
    else tableLen := TyGraphCurvenessLength(ASpec, total);
    { THE PARITY CORRECTION, and a written list opts out of it. }
    if isArray or Odd(total) then parity := 0 else parity := 1;

    if forwardOf[g] <> 1 then
    begin
      { THE FAR SIDE: this pair's entries start after the opposite pair's. }
      res := ListAt(rank[i] + opp + parity);
      if not ACircular then
      begin
        { AND EVERY LAYOUT BUT THE RING TURNS SOME OF THEM ROUND AGAIN, by a
          parity rule that itself depends on whether a written list starts
          with a zero. `cond ? value : -value`. }
        if isArray and not ledByZero then
        begin
          if Odd(opp) then keep := Odd(parity) else keep := not Odd(parity);
        end
        else
          keep := Odd(opp + parity);
        if not keep then res := -res;
      end;
    end
    else
      res := ListAt(parity + rank[i]);

    if ACircular then
    begin
      { `retrieve3(written, table, 0)`: an entry that is not there falls through
        to the zero. }
      if IsNan(res) then res := 0;
    end
    else
      { `-getCurvenessForEdge(...)`, UNCONDITIONALLY, on top of the turning
        round above -- so a forward edge under `none` or `force` bows the
        opposite way to the same edge on a ring. And `-undefined` is not a
        number: a straight line. }
      res := -res;
    AEdges[i].SolvedCurveness := res;
  end;
end;

{ A point a canvas can take. }
function Drawable(AX, AY: Double): Boolean;
begin
  Result := not (IsNan(AX) or IsNan(AY) or IsInfinite(AX) or IsInfinite(AY))
    and (Abs(AX) <= cTyGraphFarPx) and (Abs(AY) <= cTyGraphFarPx);
end;

procedure TyGraphEdgeGeometry(var AEdges: TTyGraphEdgeArray;
  const ANodes: TTyGraphNodeArray; AView: TTyGraphView; ACircular: Boolean);
var
  i, a, b: Integer;
  c, x1, y1, x2, y2, x12, y12, qx, qy, cx, cy: Double;
  rect: TTyRectF;
  p: TTyPointF;
  mask: TFPUExceptionMask;
begin
  if AView = nil then Exit;
  mask := MaskFP;
  try
    { THE RING'S OWN CENTRE, in data space: the centre of the DATA rectangle
      the ring was laid out in, which is not the pixel box's centre whenever
      the author placed the nodes. }
    rect := AView.GetDataRect;
    cx := (rect.Right - rect.Left) / 2 + rect.Left;
    cy := (rect.Bottom - rect.Top) / 2 + rect.Top;
    for i := 0 to High(AEdges) do
    begin
      AEdges[i].Curved := False;
      AEdges[i].Hidden := False;
      AEdges[i].CPX := NaN;
      AEdges[i].CPY := NaN;
      a := AEdges[i].Source;
      b := AEdges[i].Target;
      if (a < 0) or (a > High(ANodes)) or (b < 0) or (b > High(ANodes)) then
        Continue;
      c := AEdges[i].SolvedCurveness;
      { `+curveness`: zero and not-a-number are falsy and draw a straight line.
        Infinity is not falsy -- it makes a point that cannot be drawn. }
      if IsNan(c) or (c = 0) then Continue;
      { IN DATA SPACE, from the laid-out positions -- where upstream authors
        the point, before the view's transform carries the whole group. Done
        in pixels instead, the ring's control point would be pulled towards a
        centre measured in the wrong units, and every chord of a positioned
        ring would bow off towards one corner. }
      x1 := ANodes[a].X;
      y1 := ANodes[a].Y;
      x2 := ANodes[b].X;
      y2 := ANodes[b].Y;
      x12 := (x1 + x2) / 2;
      y12 := (y1 + y2) / 2;
      if ACircular then
      begin
        { A COMPLETELY DIFFERENT CONTROL POINT. The ring does not offset the
          midpoint perpendicularly -- it multiplies the curveness by three and
          slides the midpoint towards the ring's own centre, so a third puts
          the control point exactly on that centre and more overshoots past
          it. Every edge therefore bows INWARD, which is what makes a chord
          diagram look like one. }
        c := c * 3;
        qx := cx * c + x12 * (1 - c);
        qy := cy * c + y12 * (1 - c);
      end
      else
      begin
        { AND THE OPERAND ORDERS ARE NOT THE SAME ON THE TWO AXES: x subtracts
          (p1.y - p2.y) and y subtracts (p2.x - p1.x). That is the midpoint
          plus curveness times the perpendicular, written out by hand, and
          copying one line onto the other mirrors every curve. }
        qx := x12 - (y1 - y2) * c;
        qy := y12 - (x2 - x1) * c;
      end;
      p := AView.DataToPoint([qx, qy]);
      if Drawable(p.X, p.Y) then
      begin
        AEdges[i].Curved := True;
        AEdges[i].CPX := p.X;
        AEdges[i].CPY := p.Y;
      end
      else
        AEdges[i].Hidden := True;
    end;
  finally
    UnmaskFP(mask);
  end;
end;

procedure TyGraphSanitise(var ANodes: TTyGraphNodeArray);
var i: Integer;
begin
  for i := 0 to High(ANodes) do
    if not Drawable(ANodes[i].PX, ANodes[i].PY) then
    begin
      ANodes[i].PX := NaN;
      ANodes[i].PY := NaN;
    end;
end;

function TyGraphSolve(AOption: TTyChartOption; ASeriesIndex: Integer;
  AStore: TTyDataStore; const AContainer: TTyRectF;
  var AForce: TTyGraphForceState): TTyGraphSolved;
var
  dataRect, viewRect: TTyRectF;
  aspect: Double;
  hasData, circ: Boolean;
  mask: TFPUExceptionMask;
begin
  Result := Default(TTyGraphSolved);
  Result.Spec := TyGraphSpecOf(AOption, ASeriesIndex);
  Result.Cats := TyGraphCategoriesOf(AOption, ASeriesIndex);
  Result.Nodes := TyGraphNodesOf(AStore, Result.Cats);
  Result.Edges := TyGraphEdgesOf(AOption, ASeriesIndex, Result.Nodes);
  TyGraphResolvePins(Result.Nodes, Result.Edges, Result.Cats, Result.Spec);

  mask := MaskFP;
  try
    { THE ORDER IS UPSTREAM'S AND IT MATTERS. The data rectangle is taken from
      the positions the author wrote, the box is solved with the aspect that
      came out of it -- and only THEN, if there were no positions at all, is
      the data rectangle replaced by the box. So the box has already been
      solved by the time anyone notices there was nothing to fit. }
    hasData := TyGraphDataRect(Result.Nodes, dataRect, aspect);
    viewRect := TyGraphViewRect(Result.Spec, AContainer, aspect);
    if not hasData then dataRect := viewRect;
    Result.View := TTyGraphView.Create(dataRect, viewRect);

    case Result.Spec.Layout of
      glCircular:
        TyGraphLayoutCircular(Result.Nodes, Result.View, Result.Spec);
      glForce:
        TyGraphLayoutForce(Result.Nodes, Result.Edges, Result.View,
          Result.Spec, TyGraphForceSeed(ASeriesIndex), AForce);
    else
      TyGraphLayoutNone(Result.Nodes, Result.View);
    end;

    { THE EDGES AFTER THE NODES, because their control points are made of the
      nodes' final positions -- and the ring is the only layout that reads the
      curveness table without turning it round. }
    circ := Result.Spec.Layout = glCircular;
    TyGraphSolveCurveness(Result.Edges, Result.Spec, circ);
    TyGraphEdgeGeometry(Result.Edges, Result.Nodes, Result.View, circ);
    TyGraphSanitise(Result.Nodes);
  finally
    UnmaskFP(mask);
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
  sz: Double;
  pts: TTyPointFArray;
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

  for i := 0 to High(AEdges) do
  begin
    if (AEdges[i].Source < 0) or (AEdges[i].Source > High(ANodes)) then Continue;
    if (AEdges[i].Target < 0) or (AEdges[i].Target > High(ANodes)) then Continue;
    p1 := TyPointF(ANodes[AEdges[i].Source].PX, ANodes[AEdges[i].Source].PY);
    p2 := TyPointF(ANodes[AEdges[i].Target].PX, ANodes[AEdges[i].Target].PY);
    if IsNan(p1.X) or IsNan(p1.Y) or IsNan(p2.X) or IsNan(p2.Y) then Continue;
    if AEdges[i].Hidden then Continue;

    { THE CONTROL POINT IS THE LAYOUT'S, not this function's. Upstream authors
      it in the layout pass, in data space, and the view only ever shortens
      what the layout produced -- see TyGraphEdgeGeometry. Nothing here
      multiplies by a curveness, which is the author's number and could be
      anything a Double holds. }
    curved := AEdges[i].Curved;
    if curved then cp := TyPointF(AEdges[i].CPX, AEdges[i].CPY)
    else cp := TyPointF(0, 0);

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
