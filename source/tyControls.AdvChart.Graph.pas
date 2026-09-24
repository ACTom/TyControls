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
  tyControls.AdvChart.Symbol, tyControls.AdvChart.Color,
  { For TTySeriesDimArray: a graph on axes fills the axes' own columns. The
    builder uses none of this unit, so the dependency stays one-way. }
  tyControls.AdvChart.Builder;

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
    ended up, in device pixels, after a layout ran and the view mapped it.
    On AXES X and Y are the node's two coordinates as the axes read them -- a
    bare number on a category axis is its row and its value -- and PX and PY
    are where the axes put them. }
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
    { `draggable`, resolved along the same chain as `fixed`. There is no node
      dragging here; a draggable node is one a press does not PAN from. }
    HasOwnDraggable: Boolean;
    OwnDraggable: Boolean;
    Draggable: Boolean;
    PX, PY: Double;
    { '' means the series' own symbol. }
    SymbolName: string;
    HasSize: Boolean;
    SizeW, SizeH: Double;
    { THE RING MEASURES A SIZE IT DOES NOT DRAW: upstream's getSymbolSize
      averages a [w, h] pair, and a pair missing a number -- a one-element
      array above all -- averages to not-a-number, which the ring then reads
      as two. True for exactly that case; the zero value is the ordinary
      average of SizeW and SizeH. }
    RingSizeNaN: Boolean;
    { WHICH ROW, IN TWO NUMBERINGS. Row is the position in the store's VIEW --
      what labels, overrides and the ink read by -- and -1 for a node the
      legend filtered out. RawRow is the position in what the author wrote,
      which is what a datum reports and what an edge's `source: 3` means. }
    Row: Integer;
    RawRow: Integer;
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
    { The edge's position among every edge that resolved -- upstream's edge
      dataIndex before any filter, which the automatic curveness table is keyed
      on. }
    RawIndex: Integer;
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
    { A CURVE WHOSE CONTROL POINT HAS A NOT-A-NUMBER HALF. Upstream's
      isStraightLine draws it straight -- unless an end carries a symbol:
      adjustEdge then cuts the CURVE at the node's rim, the arithmetic turns
      both ends into not-a-number, and nothing is drawn at all. }
    NaNCurve: Boolean;
    { A CONTROL POINT LEFT OVER, in data space, used only when the layout's own
      curveness is falsy. The force layout overwrites an edge's third point
      only when its curveness is truthy, so a point the initial layout's edge
      pass wrote survives -- made from the INITIAL positions. }
    HasStale: Boolean;
    StaleX, StaleY: Double;
    Row: Integer;
    { ON A VIEW, the control point in DATA space as well -- what the ends are
      trimmed against -- and the trimmed edge itself, in data space (T*) and
      carried through the view (E*). CPX/CPY stay the untrimmed point.
      HasEnds says the builder is to draw these rather than trim
      the edge in pixels itself. }
    DCPX, DCPY: Double;
    HasEnds: Boolean;
    TX1, TY1, TX2, TY2, TCPX, TCPY: Double;
    EX1, EY1, EX2, EY2, ECPX, ECPY: Double;
  end;
  TTyGraphEdgeArray = array of TTyGraphEdge;

  TTyGraphCategory = record
    { `''` for a category that has no name -- including one written as a bare
      string, which upstream reads as an object with no `name`. }
    Name_: string;
    { The category's `symbol` and `symbolSize`, which its nodes inherit when
      they say nothing of their own. The legend chip does NOT use them. }
    SymbolName: string;
    HasSize: Boolean;
    SizeW, SizeH: Double;
    { See TTyGraphNode.RingSizeNaN. }
    RingSizeNaN: Boolean;
    { A category is a MODEL PARENT of the nodes that name it by index, so a
      `fixed` written here holds every one of them that did not say otherwise. }
    HasFixed: Boolean;
    Fixed: Boolean;
    HasDraggable: Boolean;
    Draggable: Boolean;
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

  { `center`, the point of the DATA rectangle that sits in the middle of the
    box. Has is False when the option is falsy -- null, absent, 0, '' -- and
    the box's own centre is used. Each half is parsed the way the box's
    positions are, except that a percentage is of the DATA rectangle's size
    and is offset by its corner. Pct says the half was WRITTEN as a string
    ending in a percent sign -- not a keyword -- because that is the one form a
    roam writes back as a percentage. }
  TTyGraphCentre = record
    Has: Boolean;
    X, Y: TTyGraphPos;
    PctX, PctY: Boolean;
  end;

  { `roam`: which of the two gestures it switches on. }
  TTyGraphRoamMode = (grmOff, grmPan, grmZoom, grmBoth);

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
    { The series' `symbolSize` as the ring measures it; see
      TTyGraphNode.RingSizeNaN. }
    RingSizeNaN: Boolean;
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
    ZLevel: Integer;
    Draggable: Boolean;
    { THE VIEW'S OWN OPTIONS. `center` and `scaleLimit` climb to the option
      root when the series leaves them null -- neither has a series default --
      while `zoom` (default 1) and `nodeScaleRatio` (read with the climb
      switched off) never do. Zoom is the option as written, NOT clamped;
      not-a-number where it is falsy. }
    Centre: TTyGraphCentre;
    Zoom: Double;
    HasLimit: Boolean;
    LimitMin, LimitMax: Double;
    NodeScaleRatio: Double;
    Roam: TTyGraphRoamMode;
    RoamGlobal: Boolean;
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
    { The two rectangles as upstream's BoundingRects hold them -- a corner and
      a size -- because a size recovered as right minus left is not always
      the same Double. }
    FData, FView: TTyXYWH;
    { THE RAW TRANSFORM, the data rectangle fitted to the box, and its
      inverse, both as zrender's matrix arithmetic leaves them. }
    FSX, FSY, FRX, FRY: Double;
    FRI0, FRI3, FRI4, FRI5: Double;
    { THE ROAM: a zoom and a centre, and the limit the zoom is clamped by. }
    FZoom: Double;
    FCentre: TTyGraphCentre;
    FHasLimit: Boolean;
    FLimitMin, FLimitMax: Double;
    { THE OVERALL TRANSFORM, roam times raw, and its inverse. }
    FOSX, FOSY, FOX, FOY: Double;
    FOI0, FOI3, FOI4, FOI5: Double;
    FRoamX, FRoamY: Double;
    procedure Rebuild;
  public
    constructor Create(const ADataRect, AViewRect: TTyRectF);
    constructor CreateXYWH(const AData, AView: TTyXYWH);
    { The zoom and the centre, as the option or a roam left them. The zoom is
      `clamp(AZoom || 1) || 1` -- a zero or a not-a-number is one, before and
      after the clamp. }
    procedure SetRoam(const ACentre: TTyGraphCentre; AZoom: Double;
      AHasLimit: Boolean; ALimitMin, ALimitMax: Double);
    function Zoom: Double;
    function Centre: TTyGraphCentre;
    { The overall scale on each axis: the zoom times the raw fit. }
    function OverallScaleX: Double;
    function OverallScaleY: Double;
    { WHERE A POINT OF DATA WOULD LAND WITH NO ROAM, which is what decides
      whether it is too far away to draw -- a node a roam carried off to
      the far side of the screen is still a node. }
    function RawToPoint(AX, AY: Double): TTyPointF;
    { THE COMPENSATION SCALE: how much a node's symbol is scaled so that a
      zoom enlarges it by only ARatio of the zoom. `ARatio || 1`. }
    function NodeScale(ARatio: Double): Double;
    { A roam action on this view -- a pan by (ADX, ADY) when AHasPan, a zoom by
      AScale about (AOX, AOY) when AHasZoom -- answering the centre and zoom
      it leaves. The view is not changed; SetRoam them to apply. }
    procedure ApplyRoam(AHasPan: Boolean; ADX, ADY: Double;
      AHasZoom: Boolean; AScale, AOX, AOY: Double;
      out ACentre: TTyGraphCentre; out AZoom: Double);
    { The trigger area: the data rectangle carried through the overall
      transform, which shrinks when the view is zoomed out. }
    function TriggerRect: TTyXYWH;
    function ContainTrigger(AX, AY: Double): Boolean;
    function RawSX: Double;
    function RawSY: Double;
    function RawX: Double;
    function RawY: Double;
    function RawInv(AIndex: Integer): Double;
    function OverallX: Double;
    function OverallY: Double;
    function OverallInv(AIndex: Integer): Double;
    function RoamX: Double;
    function RoamY: Double;
    function DataXYWH: TTyXYWH;
    function ViewXYWH: TTyXYWH;
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

{ EVERY node the author wrote, in the order they wrote them, whether or not the
  legend kept it: Row is the view position or -1. The data rectangle is fitted
  to these and edges resolve their ends against these -- upstream builds both
  before the legend filter runs. }
function TyGraphAllNodesOf(AStore: TTyDataStore;
  const ACategories: TTyGraphCategoryArray): TTyGraphNodeArray;

type
  { One graph series' category colours. Known is False where no colour could be
    found -- a declared but empty palette, a pick past the end of one, a
    `color: 'none'` -- and for every category of a graph the legend switched
    off by its series name, which upstream never colours. Such a category's
    nodes get NO fill.

    Base is the third answer: a colour was written but it is not one anybody
    can paint -- 'auto', a word no parser knows, `true`. Upstream hands it to
    the canvas, which ignores it; here the node keeps the series colour, the
    port's usual answer to a colour it cannot read. It took no palette slot
    either way. }
  TTyGraphCatColours = record
    Known: array of Boolean;
    Base: array of Boolean;
    Colours: TTyChartColorArray;
  end;
  TTyGraphCatColourTable = array of TTyGraphCatColours;

{ EVERY GRAPH'S CATEGORY COLOURS, in one pass -- upstream's categoryVisual. One
  cursor and one name memo run across every graph series that is drawn, in
  series order. The colour is `itemStyle.color` along the model chain -- the
  category's, else the series', else the chart root's, the first that is not
  null -- and only when THAT is falsy is a palette asked: the series' own
  `color`, then the chart's with the same cursor, and AFallback, the theme's
  colours, when the chart declares none.

  AShown is per SERIES index; a graph that is not shown takes no slots, so
  switching an earlier graph off re-colours the ones after it. Indexed by
  series index; a series that is not a graph has an empty entry. }
function TyGraphCategoryColours(AOption: TTyChartOption;
  const AShown: array of Boolean;
  const AFallback: TTyChartColorArray): TTyGraphCatColourTable;

{ ONE NODE'S FILL, the way the visual pipeline builds it: the series colour,
  the node's category laid over it -- only when the series declares at least
  one category and the node resolves to one -- and then the node's own
  `itemStyle.color`. AEdgeEnd is the fill BEFORE the node's own colour, which
  is what an edge coloured by 'source' or 'target' takes. }
function TyGraphNodeFill(const ANode: TTyGraphNode;
  const ACats: TTyGraphCatColours; ACategoryCount: Integer;
  ABase: TTyChartColor; AStore: TTyDataStore;
  out AEdgeEnd: TTyChartColor): TTyChartColor;

{ THE STORE A GRAPH IS READ FROM, built the one way the control and the suite
  both build it: one value column, filled from `data` -- or from `nodes`, the
  node list's other name, when `data` is not there. `data || nodes`, so an
  empty `data` array still wins. The store must be new and empty. }
procedure TyGraphFillStore(AOption: TTyChartOption; ASeriesIndex: Integer;
  AStore: TTyDataStore);

{ THE SAME FILL INTO COLUMNS ALREADY THERE -- a graph on axes, whose store
  carries the axes' x and y and no value column at all, because upstream
  builds its nodes the way it builds a scatter's points. Still `data || nodes`,
  still the series' and the root's `category`, and never a dataset: a graph
  reads its own nodes or none. }
procedure TyGraphFillNodes(AOption: TTyChartOption; ASeriesIndex: Integer;
  const ADims: TTySeriesDimArray; AStore: TTyDataStore);

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
{ THE SAME BOX, as a corner and a size -- the form the view is built from. }
function TyGraphViewXYWH(const ASpec: TTyGraphSpec; const AContainer: TTyRectF;
  AAspect: Double): TTyXYWH;

{ `layout: 'none'`: every node is where the author put it, and a node the author
  did not place has no position at all. }
procedure TyGraphLayoutNone(var ANodes: TTyGraphNodeArray; AView: TTyGraphView);

{ `layout: 'circular'`: a ring inside the DATA rectangle, each node given an
  angular share of the turn in proportion to how wide its own symbol is. }
procedure TyGraphLayoutCircular(var ANodes: TTyGraphNodeArray;
  AView: TTyGraphView; const ASpec: TTyGraphSpec; ANodeScale: Double = 1);

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
    { AND THE PIXEL BOX it was drawn into. A resize leaves the DATA rectangle
      alone whenever every node wrote a position -- but upstream lays the chart
      out again on every resize all the same, so an unchanged data rectangle
      alone is not "nothing changed". }
    ViewRect: TTyRectF;
    X, Y: TTyDoubleArray;
    { A STALE CONTROL POINT per surviving edge, in data space, where Stale
      says there is one -- and it can be not-a-number and still be one, which
      is an edge drawn straight rather than an edge with no point. See
      TyGraphSolve: the first pass after an option can leave one behind, and a
      pass that reuses the answer must show it again, while a pass that
      continues from it starts on fresh edges. }
    Stale: array of Boolean;
    StaleX, StaleY: TTyDoubleArray;
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
  every other layout's pushed out along the perpendicular.

  WITHOUT A VIEW the positions are already pixels -- a graph on axes, whose
  layout IS dataToPoint -- and the point is authored from PX and PY and kept
  as it comes out. There is no ring there, so ACircular is not asked. }
procedure TyGraphEdgeGeometry(var AEdges: TTyGraphEdgeArray;
  const ANodes: TTyGraphNodeArray; AView: TTyGraphView; ACircular: Boolean);

{ Every node whose pixel position is not a point anybody can draw becomes
  unplaced. See cTyGraphFarPx. }
procedure TyGraphSanitise(var ANodes: TTyGraphNodeArray);

{ THE SAME ON A VIEW, asked of where the node would land with NO roam: a zoom
  that carries a node a thousand screens away has not made it undrawable. }
procedure TyGraphSanitiseView(var ANodes: TTyGraphNodeArray; AView: TTyGraphView);

{ adjustEdge ON A VIEW: every edge pulled off the nodes whose end carries a
  symbol, in DATA space, by the node's symbol size times half ANodeScale --
  the compensation scale, which turns a pixel size into data units. From the
  untrimmed edge every time. }
procedure TyGraphTrimInView(var AEdges: TTyGraphEdgeArray;
  const ANodes: TTyGraphNodeArray; const ASpec: TTyGraphSpec;
  ANodeScale: Double);

{ The trimmed edges through the view, into E* and the control point. }
procedure TyGraphMapEdges(var AEdges: TTyGraphEdgeArray; AView: TTyGraphView);

{ A ROAM STEP'S REDRAW, with no layout: every node through the view again,
  sanitised, and every edge's trimmed ends mapped. AZoomed is a step that
  carried a zoom -- the only kind that recomputes the compensation scale and
  trims the edges again; a pan leaves both where the last one put them. }
procedure TyGraphRemap(var ANodes: TTyGraphNodeArray;
  var AEdges: TTyGraphEdgeArray; const ASpec: TTyGraphSpec;
  AView: TTyGraphView; AZoomed: Boolean; var ANodeScale: Double);

const
  { HOW FAR ABOVE ITS EDGES A NODE IS PAINTED: upstream's z2 of a node symbol
    is 100 and of a line 0, so a hovered edge (lifted by ten) still passes
    under every node. }
  cTyGraphNodeZ2 = 100;
  { A THOUSAND SCREENS. A layout that is the author's arithmetic from end to end
    -- a friction of fifty, a repulsion of a million -- can put a node anywhere
    a Double reaches, and everything downstream squares distances. Past this a
    node is treated as gone, and its edges with it, where upstream would have
    drawn them running off the canvas. }
  cTyGraphFarPx = 1e6;

type
  { One graph series, solved: everything the builder and the ink need. The
    VIEW is the caller's to free, and nil for a graph on axes. }
  TTyGraphSolved = record
    Spec: TTyGraphSpec;
    Cats: TTyGraphCategoryArray;
    Nodes: TTyGraphNodeArray;
    Edges: TTyGraphEdgeArray;
    View: TTyGraphView;
    { The compensation scale the pass laid out with -- see
      TTyGraphView.NodeScale. One on axes. }
    NodeScale: Double;
  end;

  { WHAT A ROAM LEFT, which outlives every relayout until the option is
    replaced: upstream writes the centre and the zoom back into the series'
    option. Valid is False until the first roam; then these beat the
    option's own `center` and `zoom`. }
  TTyGraphRoamState = record
    Valid: Boolean;
    Centre: TTyGraphCentre;
    Zoom: Double;
  end;

  { ONE `graphroam` ACTION: a pan, a zoom about a point, or both. SeriesIndex
    is -1 for an action that names no series, which moves every graph on a
    view. A gesture produces exactly these, and the picture a gesture leaves
    is the picture its actions leave when dispatched one by one. }
  TTyGraphRoamPayload = record
    SeriesIndex: Integer;
    HasPan: Boolean;
    DX, DY: Double;
    HasZoom: Boolean;
    Zoom, OriginX, OriginY: Double;
  end;

{ ==================== focus ==================== }

type
  { What a hover leaves each element of a graph in. }
  TTyGraphHoverState = (ghsNormal, ghsBlur, ghsEmphasis);
  TTyGraphHoverStateArray = array of TTyGraphHoverState;

{ UPSTREAM'S ecFocus SETS for one hovered element, as indices into ANodes and
  AEdges -- which are upstream's dataIndex, the survivors in order. A node's
  are its edges (a self-loop once) and both ends of each, so a node with no
  edges has neither -- not even itself. An edge's are itself and its two
  ends. }
procedure TyGraphFocusSets(const ANodes: TTyGraphNodeArray;
  const AEdges: TTyGraphEdgeArray; AHoverIsEdge: Boolean; AHoverIndex: Integer;
  out ANodeSet, AEdgeSet: TTyIntegerArray);

{ ONE GRAPH'S STATES under a hover: every element blurred when ABlur, then
  the adjacency sets spared when AAdjacency -- the SETS of the graph that was
  hovered, applied by index even to another graph, which is upstream's index
  leak. The hovered element itself is the caller's to raise. }
procedure TyGraphBlurStates(ANodeCount, AEdgeCount: Integer; ABlur,
  AAdjacency: Boolean; const ANodeSet, AEdgeSet: TTyIntegerArray;
  out ANodeStates, AEdgeStates: TTyGraphHoverStateArray);

{ The view after one action: the centre and zoom it leaves, written into
  AState and applied to AView. Nothing is laid out -- see TyGraphRemap. }
procedure TyGraphRoamStep(AView: TTyGraphView; const ASpec: TTyGraphSpec;
  const APayload: TTyGraphRoamPayload; var AState: TTyGraphRoamState);

{ The wheel's zoom factor for an LCL WheelDelta: zrender's delta is a
  notch per 120, and 1.1, 1.2 or 1.4 by how far it went -- inverted for a
  turn the other way. Nought for a delta of nothing. }
function TyGraphWheelScale(AWheelDelta: Integer): Double;

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
function TyGraphSolve(AOption: TTyChartOption; ASeriesIndex: Integer;
  AStore: TTyDataStore; const AContainer: TTyRectF;
  var AForce: TTyGraphForceState;
  const ARoam: TTyGraphRoamState): TTyGraphSolved;

{ THE SAME PASS FOR A GRAPH ON AXES, and most of it is not there. Upstream
  lays such a graph out in one place for every coordinate system that is not
  a view: each node goes to dataToPoint of its two coordinates, read from
  AColX and AColY at the node's view row, and that is the whole layout --
  `layout: 'force'` and `'circular'` both return before they start, and no
  box, zoom, centre or aspect is ever read. A node with a not-a-number
  coordinate is unplaced, and its links go with it.

  THE EDGES ARE AUTHORED IN PIXELS, from those positions, with the curveness
  a `none` layout asks for -- the negated family, by raw index. On axes whose
  two scales differ, a control point made in data space and then mapped would
  bow the other way. }
function TyGraphSolveOnCoordSys(AOption: TTyChartOption; ASeriesIndex: Integer;
  AStore: TTyDataStore; const ACoordSys: ITyCoordSys;
  AColX, AColY: Integer): TTyGraphSolved;

type
  { Everything the builder needs a THEME to answer. This unit never asks what
    colour anything is -- the control resolves the palette, the category
    colours and the label ink and hands them over, which is the same contract
    the pie, the funnel, the gauge and the radar work under. }
  TTyGraphInk = record
    { One per node, already resolved: the category's colour, or the node's own
      itemStyle, or the series' palette entry. }
    NodeFills: TTyChartColorArray;
    { One per node, BEFORE the node's own itemStyle: what an edge coloured by
      'source' or 'target' takes. Upstream resolves those two words after the
      category colour and before the node's own, so an edge leaving a node that
      painted itself red still takes the category's colour. Empty means
      "the same as NodeFills". }
    EdgeEndFills: TTyChartColorArray;
    EdgeColour: TTyChartColor;
    { The label the author asked for, and the ink to draw it in. }
    Label_: TTyLabelSpec;
    LabelValueDim: Integer;
    SeriesName: string;
  end;

{ WHAT ONE EDGE IS DRAWN IN -- the builder's own answer, and the one the
  suite reads back. The series' line colour, or for `'source'` and
  `'target'` that end node's fill from BEFORE its own `itemStyle.color`:
  upstream's edge visual reads the node's style while categoryVisual is done
  with it and before the node's own colour is laid over it. }
function TyGraphEdgeStroke(const ASpec: TTyGraphSpec;
  const AEdges: TTyGraphEdgeArray; const AInk: TTyGraphInk;
  AAt: Integer): TTyChartColor;

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
function TyBuildGraphMarks(ASeriesIndex: Integer;
  const ASpec: TTyGraphSpec; const ANodes: TTyGraphNodeArray;
  const AEdges: TTyGraphEdgeArray; const AInk: TTyGraphInk;
  AStore: TTyDataStore; AList: TTyPaintList): Integer;
{ ON A VIEW: every node's symbol scaled by ASymX across and ASymY down -- the
  overall scale times the compensation scale, which is one only when the
  view maps one data unit to one pixel. }
function TyBuildGraphMarks(ASeriesIndex: Integer;
  const ASpec: TTyGraphSpec; const ANodes: TTyGraphNodeArray;
  const AEdges: TTyGraphEdgeArray; const AInk: TTyGraphInk;
  AStore: TTyDataStore; AList: TTyPaintList;
  ASymX, ASymY: Double): Integer;

implementation

{ ==================== the view ==================== }

constructor TTyGraphView.Create(const ADataRect, AViewRect: TTyRectF);
begin
  CreateXYWH(TyXYWHOfRect(ADataRect), TyXYWHOfRect(AViewRect));
end;

constructor TTyGraphView.CreateXYWH(const AData, AView: TTyXYWH);
begin
  inherited Create;
  FData := AData;
  FView := AView;
  FDataRect := TyRectOfXYWH(AData);
  FViewRect := TyRectOfXYWH(AView);
  FZoom := 1;
  FCentre := Default(TTyGraphCentre);
  FHasLimit := False;
  FLimitMin := 0;
  FLimitMax := Infinity;
  Rebuild;
end;

{ zrender's matrix.invert on the diagonal matrix [a, 0, 0, d, x, y], one
  rounding per operation in upstream's order. The `0 * y` terms upstream also
  computes only ever decide the sign of a zero, and are left out. }
procedure InvertDiag(A, D, X, Y: Double; out I0, I3, I4, I5: Double);
var det: Double;
begin
  det := A * D;
  det := 1.0 / det;
  I0 := D * det;
  I3 := A * det;
  I4 := (-(D * X)) * det;
  I5 := (-(A * Y)) * det;
end;

function GraphClampZoom(AZoom: Double; AHasLimit: Boolean;
  AMin, AMax: Double): Double;
begin
  Result := AZoom;
  if AHasLimit then
    Result := Math.Max(Math.Min(AMax, Result), AMin);
end;

{ One half of the centre, in the data rectangle's own units:
  parsePositionOption against the rectangle's size, offset by its corner. }
function CentreHalf(const APos: TTyGraphPos; ABase, AOffset: Double): Double;
begin
  case APos.Kind of
    gpkPx: Result := APos.V;
    gpkPct: Result := APos.V / 100 * ABase + AOffset;
  else
    Result := NaN;
  end;
end;

procedure TTyGraphView.Rebuild;
var
  vcx, vcy, rcx, rcy, tx, ty, px, py, z: Double;
  mask: TFPUExceptionMask;
begin
  mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
    { calculateTransform(dataRect, viewRect), decomposed: a scale on each axis
      and the translate that carries the data corner to the box's corner. }
    FSX := FView.W / FData.W;
    FSY := FView.H / FData.H;
    FRX := (-FData.X) * FSX + FView.X;
    FRY := (-FData.Y) * FSY + FView.Y;
    InvertDiag(FSX, FSY, FRX, FRY, FRI0, FRI3, FRI4, FRI5);

    { THE ROAM: the centre carried into pixels by the raw transform, then
      moved to the box's centre and scaled about it. }
    vcx := FView.X + FView.W / 2;
    vcy := FView.Y + FView.H / 2;
    rcx := vcx;
    rcy := vcy;
    if FCentre.Has then
    begin
      px := CentreHalf(FCentre.X, FData.W, FData.X);
      py := CentreHalf(FCentre.Y, FData.H, FData.Y);
      rcx := FSX * px + FRX;
      rcy := FSY * py + FRY;
      { THE ZERO TERMS ARE NOT ALWAYS ZERO. zrender applies the full matrix,
        `m[0]*x + m[2]*y + m[4]`, and nought times a half that is not finite
        is not-a-number -- so one bad half takes BOTH with it. }
      if IsNan(py) or IsInfinite(py) then rcx := NaN;
      if IsNan(px) or IsInfinite(px) then rcy := NaN;
    end;
    z := FZoom;
    tx := vcx - z * rcx;
    ty := vcy - z * rcy;
    FRoamX := tx;
    FRoamY := ty;

    { OVERALL = ROAM x RAW. }
    FOSX := z * FSX;
    FOSY := z * FSY;
    FOX := z * FRX + tx;
    FOY := z * FRY + ty;
    InvertDiag(FOSX, FOSY, FOX, FOY, FOI0, FOI3, FOI4, FOI5);
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

procedure TTyGraphView.SetRoam(const ACentre: TTyGraphCentre; AZoom: Double;
  AHasLimit: Boolean; ALimitMin, ALimitMax: Double);
var z: Double;
begin
  FCentre := ACentre;
  FHasLimit := AHasLimit;
  FLimitMin := ALimitMin;
  FLimitMax := ALimitMax;
  { `clamp(zoom || 1, limit) || 1`. }
  z := AZoom;
  if IsNan(z) or (z = 0) then z := 1;
  z := GraphClampZoom(z, AHasLimit, ALimitMin, ALimitMax);
  if IsNan(z) or (z = 0) then z := 1;
  FZoom := z;
  Rebuild;
end;

function TTyGraphView.Zoom: Double;
begin
  Result := FZoom;
end;

function TTyGraphView.Centre: TTyGraphCentre;
begin
  Result := FCentre;
end;

function TTyGraphView.OverallScaleX: Double;
begin
  Result := FOSX;
end;

function TTyGraphView.OverallScaleY: Double;
begin
  Result := FOSY;
end;

function TTyGraphView.RawToPoint(AX, AY: Double): TTyPointF;
begin
  Result := TyPointF(FSX * AX + FRX, FSY * AY + FRY);
end;

function TTyGraphView.NodeScale(ARatio: Double): Double;
var r, s: Double;
begin
  { `nodeScaleRatio || 1` and `scaleX || 1`: a zero or a not-a-number is
    one. }
  r := ARatio;
  if IsNan(r) or (r = 0) then r := 1;
  s := FOSX;
  if IsNan(s) or (s = 0) then s := 1;
  Result := ((FZoom - 1) * r + 1) / s;
end;

procedure TTyGraphView.ApplyRoam(AHasPan: Boolean; ADX, ADY: Double;
  AHasZoom: Boolean; AScale, AOX, AOY: Double;
  out ACentre: TTyGraphCentre; out AZoom: Double);
var
  bx, by, bsx, bsy, oldZ, newZ, k, rsx, rx_, ry_, c0, c1, d0, d1: Double;
  vcx, vcy: Double;
  mask: TFPUExceptionMask;
const
  { Typed, so the comparison is against the Double upstream writes. }
  cZoomEps: Double = 1e-6;

  { toRoam: the overall transform times the raw inverse, decomposed. }
  procedure ToRoam(ASX, ASY, AX, AY: Double; out RSX, RX, RY: Double);
  begin
    RSX := ASX * FRI0;
    RX := ASX * FRI4 + AX;
    RY := ASY * FRI5 + AY;
  end;

  { THE WRITE-BACK. A half last written as a percentage string goes back as
    a percentage of the data rectangle; everything else -- a keyword, a
    numeric string, a number -- goes back as a number. }
  procedure Half(APct: Boolean; AV, AOff, AW: Double; out APos: TTyGraphPos;
    out AIsPct: Boolean);
  begin
    AIsPct := APct and not (IsNan(AW) or (AW = 0));
    if AIsPct then
    begin
      APos.Kind := gpkPct;
      APos.V := (AV - AOff) / AW * 100;
    end
    else
    begin
      APos.Kind := gpkPx;
      APos.V := AV;
    end;
  end;

begin
  mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
    bx := FOX;
    by := FOY;
    bsx := FOSX;
    bsy := FOSY;
    { THE ZOOM BEFORE THIS STEP, as the overall transform says it -- which is
      the stored zoom only up to a rounding. }
    oldZ := bsx * FRI0;
    { A PAN ONLY WHEN BOTH HALVES ARE THERE. }
    if AHasPan then
    begin
      bx := bx + ADX;
      by := by + ADY;
    end;
    if AHasZoom then
    begin
      newZ := GraphClampZoom(oldZ * AScale, FHasLimit, FLimitMin, FLimitMax);
      k := newZ / oldZ;
      bx := bx - (AOX - bx) * (k - 1);
      by := by - (AOY - by) * (k - 1);
      bsx := bsx * k;
      bsy := bsy * k;
    end;
    ToRoam(bsx, bsy, bx, by, rsx, rx_, ry_);
    AZoom := rsx;
    vcx := FView.X + FView.W / 2;
    vcy := FView.Y + FView.H / 2;
    if Abs(AZoom) > cZoomEps then
    begin
      c0 := (vcx - rx_) / AZoom;
      c1 := (vcy - ry_) / AZoom;
    end
    else
    begin
      c0 := vcx;
      c1 := vcy;
    end;
    d0 := FRI0 * c0 + FRI4;
    d1 := FRI3 * c1 + FRI5;
    ACentre.Has := True;
    if FCentre.Has then
    begin
      Half(FCentre.PctX, d0, FData.X, FData.W, ACentre.X, ACentre.PctX);
      Half(FCentre.PctY, d1, FData.Y, FData.H, ACentre.Y, ACentre.PctY);
    end
    else
    begin
      Half(False, d0, FData.X, FData.W, ACentre.X, ACentre.PctX);
      Half(False, d1, FData.Y, FData.H, ACentre.Y, ACentre.PctY);
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

function TTyGraphView.TriggerRect: TTyXYWH;
begin
  Result.X := FData.X * FOSX + FOX;
  Result.Y := FData.Y * FOSY + FOY;
  Result.W := FData.W * FOSX;
  Result.H := FData.H * FOSY;
  { BoundingRect.applyTransform turns a negative size round. }
  if IsNan(Result.W) or IsNan(Result.H) then Exit;
  if Result.W < 0 then
  begin
    Result.X := Result.X + Result.W;
    Result.W := -Result.W;
  end;
  if Result.H < 0 then
  begin
    Result.Y := Result.Y + Result.H;
    Result.H := -Result.H;
  end;
end;

function TTyGraphView.ContainTrigger(AX, AY: Double): Boolean;
var r: TTyXYWH;
begin
  r := TriggerRect;
  { A VIEW MADE OF NOT-A-NUMBER CONTAINS NOTHING -- every comparison upstream
    makes against it is false. }
  if IsNan(r.X) or IsNan(r.Y) or IsNan(r.W) or IsNan(r.H) or IsNan(AX)
    or IsNan(AY) then Exit(False);
  Result := (AX >= r.X) and (AX <= r.X + r.W)
        and (AY >= r.Y) and (AY <= r.Y + r.H);
end;

function TTyGraphView.RawSX: Double;
begin
  Result := FSX;
end;

function TTyGraphView.RawSY: Double;
begin
  Result := FSY;
end;

function TTyGraphView.RawX: Double;
begin
  Result := FRX;
end;

function TTyGraphView.RawY: Double;
begin
  Result := FRY;
end;

function TTyGraphView.RawInv(AIndex: Integer): Double;
begin
  case AIndex of
    0: Result := FRI0;
    3: Result := FRI3;
    4: Result := FRI4;
    5: Result := FRI5;
  else
    Result := 0;
  end;
end;

function TTyGraphView.RoamX: Double;
begin
  Result := FRoamX;
end;

function TTyGraphView.RoamY: Double;
begin
  Result := FRoamY;
end;

function TTyGraphView.DataXYWH: TTyXYWH;
begin
  Result := FData;
end;

function TTyGraphView.ViewXYWH: TTyXYWH;
begin
  Result := FView;
end;

function TTyGraphView.OverallX: Double;
begin
  Result := FOX;
end;

function TTyGraphView.OverallY: Double;
begin
  Result := FOY;
end;

function TTyGraphView.OverallInv(AIndex: Integer): Double;
begin
  case AIndex of
    0: Result := FOI0;
    3: Result := FOI3;
    4: Result := FOI4;
    5: Result := FOI5;
  else
    Result := 0;
  end;
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
  { THROUGH THE OVERALL MATRIX, one multiply and one add per axis -- the way
    zrender carries a point through a group's transform. The two axes scale
    INDEPENDENTLY: upstream fits the data rect to the view rect with
    `sx = b.width / a.width` and `sy = b.height / a.height`. [Revised in batch
    45: this was `(d - left) * scale + viewLeft`, which rounds differently in
    about a third of all coordinates.] }
  Result := TyPointF(FOSX * AData[0] + FOX, FOSY * AData[1] + FOY);
  { And the full matrix's zero terms: see Rebuild. }
  if IsNan(AData[1]) or IsInfinite(AData[1]) then Result.X := NaN;
  if IsNan(AData[0]) or IsInfinite(AData[0]) then Result.Y := NaN;
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
begin
  { THROUGH THE INVERTED MATRIX, not by dividing the forward map back out. }
  AData := nil;
  if (FOSX = 0) or (FOSY = 0) or IsNan(FOI0) or IsNan(FOI3) then Exit(False);
  SetLength(AData, 2);
  AData[0] := FOI0 * APoint.X + FOI4;
  AData[1] := FOI3 * APoint.Y + FOI5;
  Result := True;
end;

function TTyGraphView.ContainPoint(const APoint: TTyPointF): Boolean;
begin
  { THE DATA RECTANGLE WHERE THE ROAM HAS PUT IT, not the box: zoomed out,
    the area that answers shrinks with the picture. }
  Result := ContainTrigger(APoint.X, APoint.Y);
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

function ObjOf(AData: TJSONData): TJSONObject;
begin
  if AData is TJSONObject then Result := TJSONObject(AData)
  else Result := nil;
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
  Result.ZLevel := 0;
  { `center: null`, `zoom: 1`, `nodeScaleRatio: 0.6`, `roam: false`. }
  Result.Centre := Default(TTyGraphCentre);
  Result.Zoom := 1;
  Result.HasLimit := False;
  Result.LimitMin := 0;
  Result.LimitMax := Infinity;
  Result.NodeScaleRatio := 0.6;
  Result.Roam := grmOff;
  Result.RoamGlobal := False;
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

{ Whether upstream's getSymbolSize comes out not-a-number for this
  `symbolSize`: an array without a number in both of its first two places --
  `(size[0] + size[1]) / 2` with an undefined in it. }
function RingSizeNaNOf(AData: TJSONData): Boolean;
var a: TJSONArray;
begin
  Result := False;
  if not (AData is TJSONArray) then Exit;
  a := TJSONArray(AData);
  Result := (a.Count < 2) or (a.Items[0].JSONType <> jtNumber)
    or (a.Items[1].JSONType <> jtNumber);
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
  ASpec.RingSizeNaN := RingSizeNaNOf(d);
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

{ ONE HALF OF `center`: `centerOption[i]`, which on a string is its i-th
  character and on anything that is not an array or a string is undefined. }
function CentreItem(AData: TJSONData; AIndex: Integer;
  out AWasPct: Boolean): TTyGraphPos;
var item: TJSONData; s, t: string; owned: TJSONString;
begin
  AWasPct := False;
  item := nil;
  owned := nil;
  if AData is TJSONArray then
  begin
    if AIndex < TJSONArray(AData).Count then item := TJSONArray(AData).Items[AIndex];
  end
  else if AData.JSONType = jtString then
  begin
    s := AData.AsString;
    if AIndex < Length(s) then
    begin
      owned := TJSONString.Create(s[AIndex + 1]);
      item := owned;
    end;
  end;
  try
    Result := GraphPosOf(item);
    if (item <> nil) and (item.JSONType = jtString) then
    begin
      t := Trim(item.AsString);
      AWasPct := (t <> '') and (t[Length(t)] = '%');
    end;
  finally
    owned.Free;
  end;
end;

{ The view's own options -- see TTyGraphSpec.Centre. }
procedure ReadRoamOptions(ANode, ARoot: TJSONObject; var ASpec: TTyGraphSpec);
var d, lim: TJSONData; v: Double; s: string;

  function ModeOf(AValue: TJSONData): TTyGraphRoamMode;
  begin
    Result := grmOff;
    if AValue = nil then Exit;
    case AValue.JSONType of
      { `controlType === true` -- a one is not true. }
      jtBoolean: if AValue.AsBoolean then Result := grmBoth;
      jtString:
        begin
          s := AValue.AsString;
          if (s = 'move') or (s = 'pan') then Result := grmPan
          else if (s = 'scale') or (s = 'zoom') then Result := grmZoom;
        end;
    end;
  end;

begin
  { `center`: null climbs to the root, and a falsy answer is no centre. }
  d := ShallowOf(ANode, ARoot, 'center');
  if (d <> nil) and JsTruthy(d) then
  begin
    ASpec.Centre.Has := True;
    ASpec.Centre.X := CentreItem(d, 0, ASpec.Centre.PctX);
    ASpec.Centre.Y := CentreItem(d, 1, ASpec.Centre.PctY);
  end;

  { `zoom || 1`: a number or a boolean; anything falsy is one, and so is
    anything this cannot read as a number. }
  d := ANode.Find('zoom');
  if d <> nil then
  begin
    v := JsNum(d);
    if d.JSONType = jtNull then v := NaN;
    ASpec.Zoom := v;
  end;

  { `scaleLimit`: any truthy value clamps, with `min || 0` and
    `max || Infinity`. }
  lim := ShallowOf(ANode, ARoot, 'scaleLimit');
  if (lim <> nil) and JsTruthy(lim) then
  begin
    ASpec.HasLimit := True;
    ASpec.LimitMin := 0;
    ASpec.LimitMax := Infinity;
    if lim is TJSONObject then
    begin
      v := JsNum(TJSONObject(lim).Find('min'));
      if not (IsNan(v) or (v = 0)) then ASpec.LimitMin := v;
      v := JsNum(TJSONObject(lim).Find('max'));
      if not (IsNan(v) or (v = 0)) then ASpec.LimitMax := v;
    end;
  end;

  { `nodeScaleRatio`, the series' own: a written null is read as nought, and
    nought is one where it is used. }
  d := ANode.Find('nodeScaleRatio');
  if d <> nil then ASpec.NodeScaleRatio := JsNum(d);

  { `roam`: absent is the default, false. A written null is `get`'s cue to
    climb -- and nothing at the root either is `true`. }
  d := ANode.Find('roam');
  if d = nil then ASpec.Roam := grmOff
  else if d.JSONType <> jtNull then ASpec.Roam := ModeOf(d)
  else
  begin
    d := nil;
    if ARoot <> nil then d := ARoot.Find('roam');
    if (d = nil) or (d.JSONType = jtNull) then ASpec.Roam := grmBoth
    else ASpec.Roam := ModeOf(d);
  end;

  d := ShallowOf(ANode, ARoot, 'roamTrigger');
  ASpec.RoamGlobal := (d <> nil) and (d.JSONType = jtString)
    and (d.AsString = 'global');
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
  { `draggable: false` is a series default, so only a written null climbs --
    and that climb is not followed here. }
  d := node.Find('draggable');
  Result.Draggable := (d <> nil) and JsTruthy(d);
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
  { (Sizes below are clamped; see SaneSize.) }

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
  d := node.Find('zlevel');
  if (d <> nil) and (d.JSONType = jtNumber) then
    Result.ZLevel := TyRoundOpt(d.AsFloat, Result.ZLevel);

  ReadRoamOptions(node, root, Result);
end;

{ ==================== the three collections ==================== }

function TyGraphCategoriesOf(AOption: TTyChartOption;
  ASlot: Integer): TTyGraphCategoryArray;
var
  node: TJSONObject;
  d: TJSONData;
  a: TJSONArray;
  item: TJSONObject;
  i: Integer;
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
    { A BARE STRING IS NOT A NAME. Upstream extends an object of `value: 0` with it,
      which copies a string's index keys and no `name` -- so the category is
      nameless, its chip is a line break, and a node naming it by that string
      finds nothing. }
    if not (a.Items[i] is TJSONObject) then Continue;
    item := TJSONObject(a.Items[i]);
    { A NUMBER IS A NAME TOO -- `name: 5` is the category '5'. }
    d := item.Find('name');
    if d <> nil then
      case d.JSONType of
        jtString: Result[i].Name_ := d.AsString;
        jtNumber: Result[i].Name_ := TyLabelNumToStr(d.AsFloat);
      end;
    Result[i].SymbolName := StrIn(item, 'symbol', '');
    d := item.Find('symbolSize');
    Result[i].RingSizeNaN := RingSizeNaNOf(d);
    if (d <> nil) and (d.JSONType = jtNumber) then
    begin
      Result[i].HasSize := True;
      Result[i].SizeW := SaneSize(d.AsFloat);
      Result[i].SizeH := Result[i].SizeW;
    end
    else if (d is TJSONArray) and (TJSONArray(d).Count > 0)
      and (TJSONArray(d).Items[0].JSONType = jtNumber) then
    begin
      Result[i].HasSize := True;
      Result[i].SizeW := SaneSize(TJSONArray(d).Items[0].AsFloat);
      Result[i].SizeH := Result[i].SizeW;
      if (TJSONArray(d).Count > 1)
        and (TJSONArray(d).Items[1].JSONType = jtNumber) then
        Result[i].SizeH := SaneSize(TJSONArray(d).Items[1].AsFloat);
    end;
    d := item.Find('fixed');
    if (d <> nil) and (d.JSONType <> jtNull) then
    begin
      Result[i].HasFixed := True;
      Result[i].Fixed := JsTruthy(d);
    end;
    d := item.Find('draggable');
    if (d <> nil) and (d.JSONType <> jtNull) then
    begin
      Result[i].HasDraggable := True;
      Result[i].Draggable := JsTruthy(d);
    end;
  end;
end;

{ One row's scalar leaf as text, '' when the row did not write that key. ARow is
  a RAW row: a node the legend filtered out is still read, because the data
  rectangle and the edges are built from every node. }
function RowText(AStore: TTyDataStore; ARow: Integer; const AKey: string): string;
var v: TTyDataValue; k: Integer;
begin
  Result := '';
  if AStore = nil then Exit;
  k := TyOverrideKey(AKey);
  if not AStore.HasOverrideByRaw(ARow, k) then Exit;
  v := AStore.GetOverrideByRaw(ARow, k);
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
  if not AStore.HasOverrideByRaw(ARow, k) then Exit;
  v := AStore.GetOverrideByRaw(ARow, k);
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

{ One row's leaf when it is a STRING -- '' included, which RowText cannot tell
  apart from nothing written. }
function RowIsText(AStore: TTyDataStore; ARow: Integer; const AKey: string;
  out AText: string): Boolean;
var v: TTyDataValue; k: Integer;
begin
  AText := '';
  Result := False;
  if AStore = nil then Exit;
  k := TyOverrideKey(AKey);
  if not AStore.HasOverrideByRaw(ARow, k) then Exit;
  v := AStore.GetOverrideByRaw(ARow, k);
  if v.Kind <> dvkText then Exit;
  AText := v.Text;
  Result := True;
end;

function RowNum(AStore: TTyDataStore; ARow: Integer; const AKey: string;
  out AValue: Double): Boolean;
var v: TTyDataValue; k: Integer;
begin
  AValue := NaN;
  Result := False;
  if AStore = nil then Exit;
  k := TyOverrideKey(AKey);
  if not AStore.HasOverrideByRaw(ARow, k) then Exit;
  v := AStore.GetOverrideByRaw(ARow, k);
  if v.Kind <> dvkNumber then Exit;
  AValue := v.Num;
  Result := True;
end;

{ Every node (AAll) or only the ones the store's view kept, in RAW order either
  way -- a filter keeps order, so the view position of a kept node is its
  position among the kept ones. }
function ReadNodes(AStore: TTyDataStore;
  const ACategories: TTyGraphCategoryArray; AAll: Boolean): TTyGraphNodeArray;
var
  i, j, valCol, n, raw: Integer;
  s: string;
  v: Double;
  written: Boolean;
  viewOf: array of Integer;
begin
  Result := nil;
  if AStore = nil then Exit;
  valCol := AStore.DimIndexOf('value');
  SetLength(viewOf, AStore.RawCount);
  for i := 0 to High(viewOf) do viewOf[i] := -1;
  for i := 0 to AStore.Count - 1 do
  begin
    raw := AStore.GetRawIndex(i);
    if (raw >= 0) and (raw <= High(viewOf)) then viewOf[raw] := i;
  end;
  if AAll then n := AStore.RawCount else n := AStore.Count;
  SetLength(Result, n);
  for i := 0 to n - 1 do
  begin
    if AAll then raw := i else raw := AStore.GetRawIndex(i);
    Result[i] := Default(TTyGraphNode);
    Result[i].Row := viewOf[raw];
    Result[i].RawRow := raw;
    Result[i].Name_ := AStore.GetNameByRaw(raw);
    { THE ID IS NOT AN OVERRIDE. The store keeps `value`, `name` and `id` out of
      the override table on purpose -- they are the datum's identity rather
      than options written on it -- so it has to be asked for by name. And an
      edge NAMES its endpoints: the gallery's own Les Miserables graph joins
      `"1"` to `"0"`, which are ids, while every node's name is a person. }
    Result[i].Id := AStore.GetIdByRaw(raw);
    Result[i].Category := -1;
    if valCol >= 0 then Result[i].Value := AStore.GetByRaw(valCol, raw)
    else Result[i].Value := NaN;

    { A NODE WITH NO x IS NOT A NODE AT ZERO. Upstream coerces whatever the
      option model answers with a unary plus, and `+undefined` is not a number
      -- which is the whole reason the view has a second branch. }
    Result[i].X := NaN;
    Result[i].Y := NaN;
    if RowNum(AStore, raw, 'x', v) then Result[i].X := v;
    if RowNum(AStore, raw, 'y', v) then Result[i].Y := v;
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
    Result[i].OwnFixed := RowTruthy(AStore, raw, 'fixed', written);
    Result[i].HasOwnFixed := written;
    Result[i].OwnDraggable := RowTruthy(AStore, raw, 'draggable', written);
    Result[i].HasOwnDraggable := written;
    Result[i].Draggable := False;
    Result[i].ModelCategory := -1;
    Result[i].PX := NaN;
    Result[i].PY := NaN;

    Result[i].SymbolName := RowText(AStore, raw, 'symbol');
    if RowNum(AStore, raw, 'symbolSize', v) then
    begin
      Result[i].HasSize := True;
      Result[i].SizeW := SaneSize(v);
      Result[i].SizeH := Result[i].SizeW;
    end;

    { `category` IS READ THREE DIFFERENT WAYS UPSTREAM -- as an index, as a
      name, and as neither. An index that is out of range and a name nobody
      declared both come to the same thing here: no category. }
    if RowNum(AStore, raw, 'category', v) then
    begin
      if (v >= 0) and (v < Length(ACategories)) and (Frac(v) = 0) then
      begin
        Result[i].Category := Trunc(v);
        Result[i].ModelCategory := Result[i].Category;
      end;
    end
    else if RowIsText(AStore, raw, 'category', s) then
    begin
      { BY NAME, AND THE LAST OF THAT NAME. Upstream builds a name-to-index map
        by walking the categories in order, so a repeated name ends up pointing
        at its last category -- while the legend's chip takes the FIRST. Two
        answers for one name, both upstream's.

        THE EMPTY STRING IS A NAME TOO: every nameless category is filed under
        it, so `category: ''` finds the last of them. A boolean is neither an
        index nor a name and finds nothing. }
      for j := 0 to High(ACategories) do
        if ACategories[j].Name_ = s then
          Result[i].Category := j;
      { A NUMBER WRITTEN AS A STRING IS STILL AN INDEX to the option chain:
        upstream indexes an ARRAY with it, and `categories['1']` is element
        one. Only the canonical spelling -- '01', '1.0' and ' 1' are property
        names that array does not have. }
      if (s <> '') and (Length(s) <= 9) and ((s = '0') or (s[1] in ['1'..'9']))
        and TryStrToInt(s, j) and (IntToStr(j) = s)
        and (j <= High(ACategories)) then
        Result[i].ModelCategory := j;
    end;

    { THE CATEGORY'S SYMBOL AND SIZE, for a node that wrote none of its own --
      upstream's categoryVisual, which runs before the ring lays anything out,
      so a category of big symbols takes a bigger share of the ring. }
    j := Result[i].Category;
    if (j >= 0) and (j <= High(ACategories)) then
    begin
      if (Result[i].SymbolName = '') and (ACategories[j].SymbolName <> '') then
        Result[i].SymbolName := ACategories[j].SymbolName;
      if (not Result[i].HasSize) and ACategories[j].HasSize then
      begin
        Result[i].HasSize := True;
        Result[i].SizeW := ACategories[j].SizeW;
        Result[i].SizeH := ACategories[j].SizeH;
        Result[i].RingSizeNaN := ACategories[j].RingSizeNaN;
      end;
    end;
  end;
end;

function TyGraphNodesOf(AStore: TTyDataStore;
  const ACategories: TTyGraphCategoryArray): TTyGraphNodeArray;
begin
  Result := ReadNodes(AStore, ACategories, False);
end;

function TyGraphAllNodesOf(AStore: TTyDataStore;
  const ACategories: TTyGraphCategoryArray): TTyGraphNodeArray;
begin
  Result := ReadNodes(AStore, ACategories, True);
end;

type
  { categoryVisual's `paletteScope`: one cursor and one name memo, shared by
    every graph and by BOTH palettes a graph asks. The memo remembers a pick
    that found NOTHING as well -- upstream stores `palette[idx]` whatever it
    is -- so a name whose first pick fell past a short palette's end stays
    uncoloured for the rest of the chart. }
  TGraphPaletteScope = record
    Idx: Integer;
    Names: array of string;
    Found: array of Boolean;
    Colours: TTyChartColorArray;
  end;

{ upstream's getFromPalette, LITERALLY, over one palette: the memo is checked
  first, an empty palette answers nothing and touches nothing, and the colour
  picked is `palette[idx]` WITHOUT a modulo -- the cursor wraps by the length
  of whatever palette advanced it last, so a long palette followed by a short
  one can land past the short one's end and find nothing. The shared palette
  cursor in AdvChart.Color wraps at the pick instead; that is right for the
  series it serves and wrong here. }
function PaletteTakeOne(var AScope: TGraphPaletteScope;
  const APalette: TTyChartColorArray; const AName: string;
  out AColour: TTyChartColor): Boolean;
var i: Integer;
begin
  AColour := 0;
  for i := 0 to High(AScope.Names) do
    if AScope.Names[i] = AName then
    begin
      AColour := AScope.Colours[i];
      Exit(AScope.Found[i]);
    end;
  if Length(APalette) = 0 then Exit(False);
  Result := (AScope.Idx >= 0) and (AScope.Idx <= High(APalette));
  if Result then AColour := APalette[AScope.Idx];
  if AName <> '' then
  begin
    i := Length(AScope.Names);
    SetLength(AScope.Names, i + 1);
    SetLength(AScope.Found, i + 1);
    SetLength(AScope.Colours, i + 1);
    AScope.Names[i] := AName;
    AScope.Found[i] := Result;
    AScope.Colours[i] := AColour;
  end;
  AScope.Idx := (AScope.Idx + 1) mod Length(APalette);
end;

{ SeriesModel.getColorFromPalette: the series' own palette, and when that
  finds nothing -- none declared, an empty one, a pick past its end -- the
  chart's, WITH THE SAME SCOPE. A named pick that failed was memoised on the
  way, so the second ask finds that failure and gives up too; only a
  nameless one really reaches the chart's palette. }
function GraphPaletteTake(var AScope: TGraphPaletteScope;
  const AOwn, AGlobal: TTyChartColorArray; const AName: string;
  out AColour: TTyChartColor): Boolean;
begin
  Result := PaletteTakeOne(AScope, AOwn, AName, AColour);
  if not Result then
    Result := PaletteTakeOne(AScope, AGlobal, AName, AColour);
end;

type
  TGraphCatFill = (gcfPalette, gcfColour, gcfNone, gcfBase);

{ ONE LINK OF THE `itemStyle.color` CHAIN. False when this level says nothing
  -- no itemStyle object, no colour, a null one -- and the parent is asked.
  Anything else ENDS the chain, whatever it is: a falsy value sends the
  category to the palette, a gradient or a colour is the category's own,
  'none' paints nothing, and every other truthy thing takes no slot and
  leaves the node the series colour (see TTyGraphCatColours.Base). }
function CatFillAt(ANode: TJSONObject; out AFill: TGraphCatFill;
  out AColour: TTyChartColor): Boolean;
var
  style: TJSONObject;
  d: TJSONData;
  g: TTyChartGradient;
begin
  AFill := gcfPalette;
  AColour := 0;
  Result := False;
  style := SubObj(ANode, 'itemStyle');
  if style = nil then Exit;
  d := style.Find('color');
  if (d = nil) or (d.JSONType = jtNull) then Exit;
  Result := True;
  if not JsTruthy(d) then Exit;
  if TyTryReadGradient(d, g) then
  begin
    AFill := gcfColour;
    AColour := TyGradientSolid(g);
  end
  else if (d.JSONType = jtString) and (LowerCase(Trim(d.AsString)) = 'none') then
    AFill := gcfNone
  else if (d.JSONType = jtString) and TyTryParseChartColor(d.AsString, AColour) then
    AFill := gcfColour
  else
    AFill := gcfBase;
end;

function TyGraphCategoryColours(AOption: TTyChartOption;
  const AShown: array of Boolean;
  const AFallback: TTyChartColorArray): TTyGraphCatColourTable;
var
  n, i, k: Integer;
  node, root, item: TJSONObject;
  cats: TTyGraphCategoryArray;
  d: TJSONData;
  scope: TGraphPaletteScope;
  own, glob: TTyChartColorArray;
  ownDecl, globDecl, hasSeries, hasRoot: Boolean;
  seriesFill, rootFill, fill: TGraphCatFill;
  seriesColour, rootColour, c: TTyChartColor;
begin
  Result := nil;
  if AOption = nil then Exit;
  n := AOption.ComponentCount('series');
  SetLength(Result, n);
  { THE CHART'S PALETTE, or the theme's when the chart declares none -- the
    theme's nine colours stand where upstream's default palette stands. A
    DECLARED empty palette stays empty: `color: []` is truthy upstream and
    colours nothing. }
  glob := TyChartPaletteOf(AOption, -1, globDecl);
  if not globDecl then glob := AFallback;
  scope := Default(TGraphPaletteScope);
  { THE LAST PARENT: the chart root's own `itemStyle`, which every series'
    item model reaches when its own says nothing. }
  root := ObjOf(AOption.Root);
  hasRoot := CatFillAt(root, rootFill, rootColour);
  for i := 0 to n - 1 do
  begin
    node := NodeAt(AOption, i);
    if node = nil then Continue;
    if StrIn(node, 'type', '') <> TyGraphSeriesTypeName then Continue;
    cats := TyGraphCategoriesOf(AOption, i);
    SetLength(Result[i].Known, Length(cats));
    SetLength(Result[i].Base, Length(cats));
    SetLength(Result[i].Colours, Length(cats));
    { A GRAPH THE LEGEND SWITCHED OFF IS NOT VISITED, so it takes no slot and
      the graphs after it start where it would have started. }
    if (i <= High(AShown)) and not AShown[i] then Continue;
    own := TyChartPaletteOf(AOption, i, ownDecl);
    { The category's itemStyle has the SERIES' itemStyle as its parent, and
      that one the root's -- so a colour written on either colours every
      category and the palette is never asked. }
    hasSeries := CatFillAt(node, seriesFill, seriesColour);
    d := node.Find('categories');
    for k := 0 to High(cats) do
    begin
      { A bare-string category is not an object and has no itemStyle. }
      item := nil;
      if (d is TJSONArray) and (k < TJSONArray(d).Count) then
        item := ObjOf(TJSONArray(d).Items[k]);
      if not CatFillAt(item, fill, c) then
      begin
        if hasSeries then
        begin
          fill := seriesFill;
          c := seriesColour;
        end
        else if hasRoot then
        begin
          fill := rootFill;
          c := rootColour;
        end
        else
          fill := gcfPalette;
      end;
      case fill of
        gcfColour:
          begin
            Result[i].Known[k] := True;
            Result[i].Colours[k] := c;
          end;
        gcfBase:
          Result[i].Base[k] := True;
        gcfPalette:
          if GraphPaletteTake(scope, own, glob, cats[k].Name_, c) then
          begin
            Result[i].Known[k] := True;
            Result[i].Colours[k] := c;
          end;
      end;
    end;
  end;
end;

function TyGraphNodeFill(const ANode: TTyGraphNode;
  const ACats: TTyGraphCatColours; ACategoryCount: Integer;
  ABase: TTyChartColor; AStore: TTyDataStore;
  out AEdgeEnd: TTyChartColor): TTyChartColor;
var
  cat, k: Integer;
  v: TTyDataValue;
  own: TTyChartColor;
begin
  Result := ABase;
  cat := ANode.Category;
  { ONLY WHEN THE SERIES HAS CATEGORIES AT ALL, and only when the node's
    reference finds one: an index out of range or a name nobody declared
    leaves the series colour. A category that found no colour -- a declared
    empty palette -- gives the node none either: upstream lays an undefined
    fill over the series one. }
  if (ACategoryCount > 0) and (cat >= 0) and (cat < ACategoryCount) then
  begin
    if (cat <= High(ACats.Known)) and ACats.Known[cat] then
      Result := ACats.Colours[cat]
    else if (cat <= High(ACats.Base)) and ACats.Base[cat] then
      { A colour nobody can paint: the series' stays. }
    else
      Result := 0;
  end;

  AEdgeEnd := Result;
  { AND THE NODE'S OWN, LAST. }
  if AStore = nil then Exit;
  k := TyOverrideKey('itemStyle.color');
  if (ANode.RawRow >= 0) and AStore.HasOverrideByRaw(ANode.RawRow, k) then
  begin
    v := AStore.GetOverrideByRaw(ANode.RawRow, k);
    if (v.Kind = dvkText) and TyTryParseChartColor(v.Text, own) then
      Result := own;
  end;
end;

procedure TyGraphFillStore(AOption: TTyChartOption; ASeriesIndex: Integer;
  AStore: TTyDataStore);
var
  dims: TTySeriesDimArray;
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
  TyGraphFillNodes(AOption, ASeriesIndex, dims, AStore);
end;

procedure TyGraphFillNodes(AOption: TTyChartOption; ASeriesIndex: Integer;
  const ADims: TTySeriesDimArray; AStore: TTyDataStore);
var
  node: TJSONObject;
  d: TJSONData;
  key: string;
  i, k: Integer;
  v: TTyDataValue;
begin
  if AStore = nil then Exit;
  node := NodeAt(AOption, ASeriesIndex);
  if node = nil then Exit;
  { `data || nodes`: the second name is read only when the first is falsy --
    absent or null. An empty `data` array is truthy and wins. }
  key := 'data';
  d := node.Find('data');
  if (d = nil) or not JsTruthy(d) then key := 'nodes';
  TyFillSeriesStore(AOption, ASeriesIndex, ADims, AStore, key);

  { A NODE'S `category` HAS PARENTS. Upstream reads it with getShallow, which
    walks the item model's chain -- the node, then the series, then the chart
    root -- so a `category` written on the series is every silent node's
    category, and the legend filters them by it. Filed here, into the rows
    that wrote none, so every reader downstream sees one answer. A node that
    wrote null wrote none: null is never filed as an override. }
  d := node.Find('category');
  if (d = nil) or (d.JSONType = jtNull) then
  begin
    d := nil;
    if (AOption.Root is TJSONObject) then
      d := TJSONObject(AOption.Root).Find('category');
  end;
  if (d = nil) or not (d.JSONType in [jtNumber, jtString, jtBoolean]) then Exit;
  k := TyOverrideKey('category');
  v := TyDataNone;
  case d.JSONType of
    jtNumber: v := TyDataNum(d.AsFloat);
    jtString: v := TyDataText(d.AsString);
    jtBoolean: v := TyDataBool(d.AsBoolean);
  end;
  for i := 0 to AStore.RawCount - 1 do
    if not AStore.HasOverrideByRaw(i, k) then
      AStore.SetOverride(i, k, v);
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
    { parseDataValue's rule, the store's own: '' is NaN, else Number(). }
    jtString: Result := TyParseNumberText(AData.AsString);
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
    Result[n].RawIndex := n;
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
  out ARect: TTyXYWH; out AW, AH: Double);
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
  ARect := TyXYWH(OrZero(AX) + left, OrZero(AY) + top, w, h);
end;

function TyGraphViewRect(const ASpec: TTyGraphSpec; const AContainer: TTyRectF;
  AAspect: Double): TTyRectF;
begin
  Result := TyRectOfXYWH(TyGraphViewXYWH(ASpec, AContainer, AAspect));
end;

function TyGraphViewXYWH(const ASpec: TTyGraphSpec; const AContainer: TTyRectF;
  AAspect: Double): TTyXYWH;
var
  cw, ch, w, h, actual: Double;
  box, inner: TGraphBoxIn;
  wide, narrow, cover: Boolean;
begin
  Result := TyXYWHOfRect(TyInvalidRectF);
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
  GraphLayoutRect(inner, Result.X, Result.Y, w, h, Result, w, h);
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
  AView: TTyGraphView; const ASpec: TTyGraphSpec; ANodeScale: Double);
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
    { THE AVERAGE OF THE PAIR, upstream's getSymbolSize -- a [40, 10] symbol
      takes the share of a 25. }
    if ANodes[i].HasSize then
    begin
      if ANodes[i].RingSizeNaN then sz := NaN
      else sz := (ANodes[i].SizeW + ANodes[i].SizeH) / 2;
    end
    else if ASpec.RingSizeNaN then sz := NaN
    else sz := (ASpec.Symbol.WidthPx + ASpec.Symbol.HeightPx) / 2;

    { TWO DEFENSIVE LINES, IN THIS ORDER. A size that is not a number becomes
      two -- an arbitrary value, and upstream says so -- and only then is a
      negative one flattened to zero. The order matters: after the first line
      the comparison can no longer see a not-a-number, which is what makes it
      safe on a compiler where comparing against one raises. }
    if IsNan(sz) then sz := 2;
    if sz < 0 then sz := 0;
    { AND THEN SCALED INTO DATA UNITS by the compensation scale, because the
      ring is laid out in data space and the symbol is drawn at a size that
      does not follow the zoom. At zoom one on a box the data already fills,
      this is one. }
    sz := sz * ANodeScale;
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
    if ANodes[i].HasOwnDraggable then
      ANodes[i].Draggable := ANodes[i].OwnDraggable
    else
    begin
      c := ANodes[i].ModelCategory;
      if (c >= 0) and (c <= High(ACategories)) and ACategories[c].HasDraggable then
        ANodes[i].Draggable := ACategories[c].Draggable
      else
        ANodes[i].Draggable := ASpec.Draggable;
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
      and (AState.Rect.Bottom = rect.Bottom)
      and (AState.ViewRect.Left = AView.GetRect.Left)
      and (AState.ViewRect.Top = AView.GetRect.Top)
      and (AState.ViewRect.Right = AView.GetRect.Right)
      and (AState.ViewRect.Bottom = AView.GetRect.Bottom) then
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
    AState.ViewRect := AView.GetRect;
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

{ THE CURVENESS OF SOME EDGES OF AAll, asked the way upstream asks.

  The edge map is built over EVERY edge in AAll -- upstream builds it once,
  over every edge that resolved, before any legend filter -- and each query
  then names three things: which edge of AAll it is (AQRaw), the index upstream
  LOOKS IT UP BY (AQLookup), and whether its key still matches (AQKeyOk).
  Without a filter the three agree and this is the plain solve. With one they
  need not: upstream's key carries each end's data index, which a filter
  renumbers, so an edge whose end moved down misses the map and is drawn
  straight; and the force layout looks up by the edge's FILTERED position
  while the map holds raw ones, so an edge after a removed one finds another
  edge's slot, or none. Both are upstream's, and both are copied. }
procedure SolveCurvenessQueries(const AAll: TTyGraphEdgeArray;
  const ASpec: TTyGraphSpec; ACircular: Boolean;
  const AQRaw, AQLookup: array of Integer; const AQKeyOk: array of Boolean;
  out AOut: TTyDoubleArray);
var
  n, i, k, q, r, g, o, ng, own, opp, total, parity, tableLen, rank: Integer;
  sorted: TPairRefArray;
  groupOf, grp, firstOf, countOf, forwardOf, oppOf, startOf: array of Integer;
  res: Double;
  isArray, ledByZero, keep, exists, oppExists: Boolean;

  { One entry of the table in force, or upstream's `undefined` -- here a
    not-a-number -- past its end, and before its start. }
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
  SetLength(AOut, Length(AQRaw));
  n := Length(AAll);
  { THREE SOURCES, NEAREST FIRST, and each of them counts a written zero: the
    edge's own, then the series', then the table. The written ones are used
    AS WRITTEN under every layout -- the negation below is applied to what the
    table answers and to nothing else -- and the map has no say in them. }
  for q := 0 to High(AQRaw) do
  begin
    r := AQRaw[q];
    if (r >= 0) and (r < n) and AAll[r].HasCurveness then
      AOut[q] := AAll[r].Curveness
    else if ASpec.HasCurveness then
      AOut[q] := ASpec.Curveness
    else
      AOut[q] := 0;
  end;
  if (not ASpec.AutoCurveness) or (n = 0) then Exit;

  { UPSTREAM'S EDGE MAP. Every ordered pair is a key; its members are the
    edges that run that way, in the order they were listed. }
  SetLength(sorted, n);
  for i := 0 to n - 1 do
  begin
    sorted[i].S := AAll[i].Source;
    sorted[i].T := AAll[i].Target;
    sorted[i].Edge := i;
  end;
  SortPairs(sorted);
  SetLength(groupOf, n);
  SetLength(grp, n);
  SetLength(firstOf, n);
  SetLength(countOf, n);
  SetLength(forwardOf, n);
  SetLength(startOf, n);
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
      startOf[ng] := k;
    end;
    groupOf[k] := ng;
    grp[sorted[k].Edge] := ng;
    Inc(countOf[ng]);
  end;
  { A SELF-LOOP IS ITS OWN OPPOSITE: the key and the reversed key are the same
    pair, so this finds the loop's own key. }
  SetLength(oppOf, n);
  for i := 0 to n - 1 do
    oppOf[i] := FindPair(sorted, groupOf, AAll[i].Target, AAll[i].Source);

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

  for q := 0 to High(AQRaw) do
  begin
    r := AQRaw[q];
    if (r < 0) or (r >= n) then Continue;
    if AAll[r].HasCurveness or ASpec.HasCurveness then Continue;
    { A KEY THAT NO LONGER MATCHES finds nothing in the map: `null`, which
      every layout turns into a straight line. }
    if not AQKeyOk[q] then
    begin
      AOut[q] := 0;
      Continue;
    end;
    g := grp[r];
    o := oppOf[r];
    own := countOf[g];
    if o >= 0 then opp := countOf[o] else opp := 0;
    { BOTH DIRECTIONS, and a self-loop's own count twice over -- both lookups
      find the same key. }
    total := own + opp;
    if isArray then tableLen := Length(ASpec.AutoList)
    else tableLen := TyGraphCurvenessLength(ASpec, total);
    { THE PARITY CORRECTION, and a written list opts out of it. }
    if isArray or Odd(total) then parity := 0 else parity := 1;
    { WHERE THE LOOKUP INDEX SITS AMONG THE KEY'S MEMBERS, or -1 -- which the
      arithmetic below then carries on with, exactly as upstream's does. }
    rank := -1;
    for k := startOf[g] to startOf[g] + countOf[g] - 1 do
      if sorted[k].Edge = AQLookup[q] then
      begin
        rank := k - startOf[g];
        Break;
      end;

    if forwardOf[g] <> 1 then
    begin
      { THE FAR SIDE: this pair's entries start after the opposite pair's. }
      res := ListAt(rank + opp + parity);
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
      res := ListAt(parity + rank);

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
    AOut[q] := res;
  end;
end;

procedure TyGraphSolveCurveness(var AEdges: TTyGraphEdgeArray;
  const ASpec: TTyGraphSpec; ACircular: Boolean);
var
  i: Integer;
  qr: array of Integer;
  ok: array of Boolean;
  res: TTyDoubleArray;
begin
  { NO FILTER: every edge is asked about as itself. }
  SetLength(qr, Length(AEdges));
  SetLength(ok, Length(AEdges));
  for i := 0 to High(AEdges) do
  begin
    qr[i] := i;
    ok[i] := True;
  end;
  SolveCurvenessQueries(AEdges, ASpec, ACircular, qr, qr, ok, res);
  for i := 0 to High(AEdges) do
    AEdges[i].SolvedCurveness := res[i];
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
  mask: TFPUExceptionMask;

  { WHERE ONE CONTROL POINT GOES, given in data space. A point with a
    not-a-number half is not a curve at all: upstream's isStraightLine asks
    exactly that and draws the edge straight -- which is what an unplaced
    node's leftover point, or a level edge bowed by an infinite curveness,
    comes to. Only a point that IS a number but cannot be drawn takes the
    edge with it. }
  procedure Place(AI: Integer; AQX, AQY: Double);
  var p, raw: TTyPointF;
  begin
    if IsNan(AQX) or IsNan(AQY) then
    begin
      AEdges[AI].NaNCurve := True;
      Exit;
    end;
    if AView = nil then
    begin
      p := TyPointF(AQX, AQY);
      raw := p;
    end
    else
    begin
      p := AView.DataToPoint([AQX, AQY]);
      raw := AView.RawToPoint(AQX, AQY);
    end;
    if Drawable(raw.X, raw.Y) then
    begin
      AEdges[AI].Curved := True;
      AEdges[AI].CPX := p.X;
      AEdges[AI].CPY := p.Y;
      AEdges[AI].DCPX := AQX;
      AEdges[AI].DCPY := AQY;
    end
    else
      AEdges[AI].Hidden := True;
  end;

begin
  mask := MaskFP;
  try
    { THE RING'S OWN CENTRE, in data space: the centre of the DATA rectangle
      the ring was laid out in, which is not the pixel box's centre whenever
      the author placed the nodes. No view, no ring. }
    cx := NaN;
    cy := NaN;
    if AView = nil then
      ACircular := False
    else
    begin
      rect := AView.GetDataRect;
      cx := (rect.Right - rect.Left) / 2 + rect.Left;
      cy := (rect.Bottom - rect.Top) / 2 + rect.Top;
    end;
    for i := 0 to High(AEdges) do
    begin
      AEdges[i].Curved := False;
      AEdges[i].Hidden := False;
      AEdges[i].NaNCurve := False;
      AEdges[i].CPX := NaN;
      AEdges[i].CPY := NaN;
      AEdges[i].DCPX := NaN;
      AEdges[i].DCPY := NaN;
      AEdges[i].HasEnds := False;
      a := AEdges[i].Source;
      b := AEdges[i].Target;
      if (a < 0) or (a > High(ANodes)) or (b < 0) or (b > High(ANodes)) then
        Continue;
      c := AEdges[i].SolvedCurveness;
      { `+curveness`: zero and not-a-number are falsy and draw a straight line.
        Infinity is not falsy -- it makes a point that cannot be drawn.

        UNLESS AN OLDER POINT IS STILL THERE: then the edge runs from its final
        ends through that point. }
      if IsNan(c) or (c = 0) then
      begin
        if AEdges[i].HasStale then
          Place(i, AEdges[i].StaleX, AEdges[i].StaleY);
        Continue;
      end;
      { IN DATA SPACE, from the laid-out positions -- where upstream authors
        the point, before the view's transform carries the whole group. Done
        in pixels instead, the ring's control point would be pulled towards a
        centre measured in the wrong units, and every chord of a positioned
        ring would bow off towards one corner. }
      if AView = nil then
      begin
        x1 := ANodes[a].PX;
        y1 := ANodes[a].PY;
        x2 := ANodes[b].PX;
        y2 := ANodes[b].PY;
      end
      else
      begin
        x1 := ANodes[a].X;
        y1 := ANodes[a].Y;
        x2 := ANodes[b].X;
        y2 := ANodes[b].Y;
      end;
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
      Place(i, qx, qy);
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

procedure TyGraphSanitiseView(var ANodes: TTyGraphNodeArray; AView: TTyGraphView);
var i: Integer; raw: TTyPointF; mask: TFPUExceptionMask;
begin
  if AView = nil then
  begin
    TyGraphSanitise(ANodes);
    Exit;
  end;
  mask := MaskFP;
  try
    for i := 0 to High(ANodes) do
    begin
      raw := AView.RawToPoint(ANodes[i].X, ANodes[i].Y);
      { Near enough unroamed, and a finite point after the roam. }
      if not Drawable(raw.X, raw.Y) or IsNan(ANodes[i].PX)
        or IsNan(ANodes[i].PY) or IsInfinite(ANodes[i].PX)
        or IsInfinite(ANodes[i].PY) then
      begin
        ANodes[i].PX := NaN;
        ANodes[i].PY := NaN;
      end;
    end;
  finally
    UnmaskFP(mask);
  end;
end;

{ A node's `symbolSize` as adjustEdge reads it -- getSymbolSize, the pair
  averaged -- or nought when it is not a number. }
function GraphNodeSymbolSize(const ASpec: TTyGraphSpec;
  const ANodes: TTyGraphNodeArray; AIndex: Integer): Double;
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
  Result := (w + h) / 2;
end;

procedure TyGraphTrimInView(var AEdges: TTyGraphEdgeArray;
  const ANodes: TTyGraphNodeArray; const ASpec: TTyGraphSpec;
  ANodeScale: Double);
var
  i, a, b: Integer;
  p1, p2, cp: TTyPointF;
  half: Double;
  mask: TFPUExceptionMask;
begin
  { `scale /= 2`, once, and every distance is a size times that. }
  half := ANodeScale / 2;
  mask := MaskFP;
  try
    for i := 0 to High(AEdges) do
    begin
      AEdges[i].HasEnds := False;
      a := AEdges[i].Source;
      b := AEdges[i].Target;
      if (a < 0) or (a > High(ANodes)) or (b < 0) or (b > High(ANodes)) then
        Continue;
      p1 := TyPointF(ANodes[a].X, ANodes[a].Y);
      p2 := TyPointF(ANodes[b].X, ANodes[b].Y);
      if AEdges[i].Curved then cp := TyPointF(AEdges[i].DCPX, AEdges[i].DCPY)
      else cp := TyPointF(0, 0);
      TyGraphTrimEdge(p1, p2, cp, AEdges[i].Curved,
        GraphNodeSymbolSize(ASpec, ANodes, a) * half,
        GraphNodeSymbolSize(ASpec, ANodes, b) * half,
        (ASpec.EdgeSymbolFrom <> '') and (ASpec.EdgeSymbolFrom <> 'none'),
        (ASpec.EdgeSymbolTo <> '') and (ASpec.EdgeSymbolTo <> 'none'));
      AEdges[i].TX1 := p1.X;
      AEdges[i].TY1 := p1.Y;
      AEdges[i].TX2 := p2.X;
      AEdges[i].TY2 := p2.Y;
      AEdges[i].TCPX := cp.X;
      AEdges[i].TCPY := cp.Y;
      AEdges[i].HasEnds := True;
    end;
  finally
    UnmaskFP(mask);
  end;
end;

procedure TyGraphMapEdges(var AEdges: TTyGraphEdgeArray; AView: TTyGraphView);
var i: Integer; p: TTyPointF; mask: TFPUExceptionMask;
begin
  if AView = nil then Exit;
  mask := MaskFP;
  try
    for i := 0 to High(AEdges) do
    begin
      if not AEdges[i].HasEnds then Continue;
      p := AView.DataToPoint([AEdges[i].TX1, AEdges[i].TY1]);
      AEdges[i].EX1 := p.X;
      AEdges[i].EY1 := p.Y;
      p := AView.DataToPoint([AEdges[i].TX2, AEdges[i].TY2]);
      AEdges[i].EX2 := p.X;
      AEdges[i].EY2 := p.Y;
      if AEdges[i].Curved then
      begin
        p := AView.DataToPoint([AEdges[i].TCPX, AEdges[i].TCPY]);
        AEdges[i].ECPX := p.X;
        AEdges[i].ECPY := p.Y;
      end;
    end;
  finally
    UnmaskFP(mask);
  end;
end;

procedure TyGraphFocusSets(const ANodes: TTyGraphNodeArray;
  const AEdges: TTyGraphEdgeArray; AHoverIsEdge: Boolean; AHoverIndex: Integer;
  out ANodeSet, AEdgeSet: TTyIntegerArray);
var j, n, m: Integer;

  procedure AddNode(AI: Integer);
  begin
    SetLength(ANodeSet, n + 1);
    ANodeSet[n] := AI;
    Inc(n);
  end;

  procedure AddEdge(AI: Integer);
  begin
    SetLength(AEdgeSet, m + 1);
    AEdgeSet[m] := AI;
    Inc(m);
  end;

begin
  ANodeSet := nil;
  AEdgeSet := nil;
  n := 0;
  m := 0;
  if AHoverIsEdge then
  begin
    if (AHoverIndex < 0) or (AHoverIndex > High(AEdges)) then Exit;
    AddEdge(AHoverIndex);
    AddNode(AEdges[AHoverIndex].Source);
    AddNode(AEdges[AHoverIndex].Target);
    Exit;
  end;
  if (AHoverIndex < 0) or (AHoverIndex > High(ANodes)) then Exit;
  { EVERY EDGE THAT TOUCHES THE NODE, a self-loop once; the node itself
    arrives only as an end of one of them. }
  for j := 0 to High(AEdges) do
    if (AEdges[j].Source = AHoverIndex) or (AEdges[j].Target = AHoverIndex) then
    begin
      AddEdge(j);
      AddNode(AEdges[j].Source);
      AddNode(AEdges[j].Target);
    end;
end;

procedure TyGraphBlurStates(ANodeCount, AEdgeCount: Integer; ABlur,
  AAdjacency: Boolean; const ANodeSet, AEdgeSet: TTyIntegerArray;
  out ANodeStates, AEdgeStates: TTyGraphHoverStateArray);
var i: Integer; s: TTyGraphHoverState;
begin
  SetLength(ANodeStates, ANodeCount);
  SetLength(AEdgeStates, AEdgeCount);
  if ABlur then s := ghsBlur else s := ghsNormal;
  for i := 0 to ANodeCount - 1 do ANodeStates[i] := s;
  for i := 0 to AEdgeCount - 1 do AEdgeStates[i] := s;
  if not (ABlur and AAdjacency) then Exit;
  for i := 0 to High(ANodeSet) do
    if (ANodeSet[i] >= 0) and (ANodeSet[i] < ANodeCount) then
      ANodeStates[ANodeSet[i]] := ghsNormal;
  for i := 0 to High(AEdgeSet) do
    if (AEdgeSet[i] >= 0) and (AEdgeSet[i] < AEdgeCount) then
      AEdgeStates[AEdgeSet[i]] := ghsNormal;
end;

procedure TyGraphRoamStep(AView: TTyGraphView; const ASpec: TTyGraphSpec;
  const APayload: TTyGraphRoamPayload; var AState: TTyGraphRoamState);
var c: TTyGraphCentre; z: Double;
begin
  if AView = nil then Exit;
  AView.ApplyRoam(APayload.HasPan, APayload.DX, APayload.DY,
    APayload.HasZoom, APayload.Zoom, APayload.OriginX, APayload.OriginY, c, z);
  AState.Valid := True;
  AState.Centre := c;
  AState.Zoom := z;
  AView.SetRoam(c, z, ASpec.HasLimit, ASpec.LimitMin, ASpec.LimitMax);
end;

function TyGraphWheelScale(AWheelDelta: Integer): Double;
const
  { Typed: an untyped 1.1 is a Single here. }
  cSmall: Double = 1.1;
  cMid: Double = 1.2;
  cBig: Double = 1.4;
var d, a, f: Double;
begin
  d := AWheelDelta / 120;
  if d = 0 then Exit(0);
  a := Abs(d);
  if a > 3 then f := cBig
  else if a > 1 then f := cMid
  else f := cSmall;
  if d > 0 then Result := f else Result := 1 / f;
end;

procedure TyGraphRemap(var ANodes: TTyGraphNodeArray;
  var AEdges: TTyGraphEdgeArray; const ASpec: TTyGraphSpec;
  AView: TTyGraphView; AZoomed: Boolean; var ANodeScale: Double);
begin
  if AView = nil then Exit;
  TyGraphLayoutNone(ANodes, AView);
  TyGraphSanitiseView(ANodes, AView);
  if AZoomed then
  begin
    ANodeScale := AView.NodeScale(ASpec.NodeScaleRatio);
    TyGraphTrimInView(AEdges, ANodes, ASpec, ANodeScale);
  end;
  TyGraphMapEdges(AEdges, AView);
end;

{ WHAT EVERY PASS STARTS FROM, whatever the graph is laid out on: the spec,
  the categories, every node and edge the author wrote -- pins resolved -- and
  the legend's survivors, renumbered.

  EVERY NODE FIRST, WHATEVER THE LEGEND SAYS. Upstream builds the graph --
  nodes, the edges between them, the curveness map -- from everything the
  author wrote, and only then does the legend filter run over the NODE data;
  each edge that lost an end goes with it. Edges resolve `source: 3` against
  the full list for the same reason: the fourth node is the fourth node the
  author wrote, not the fourth one that survived. }
procedure GatherGraph(AOption: TTyChartOption; ASeriesIndex: Integer;
  AStore: TTyDataStore; var ASolved: TTyGraphSolved;
  out AAll: TTyGraphNodeArray; out AAllEdges: TTyGraphEdgeArray);
var i, n, a, b: Integer;
begin
  ASolved.Spec := TyGraphSpecOf(AOption, ASeriesIndex);
  ASolved.Cats := TyGraphCategoriesOf(AOption, ASeriesIndex);
  AAll := TyGraphAllNodesOf(AStore, ASolved.Cats);
  AAllEdges := TyGraphEdgesOf(AOption, ASeriesIndex, AAll);
  TyGraphResolvePins(AAll, AAllEdges, ASolved.Cats, ASolved.Spec);
  { THE SURVIVORS, in the order they were written; a kept node's view position
    IS its position among the kept, so Row is where it lands. }
  n := 0;
  SetLength(ASolved.Nodes, Length(AAll));
  for i := 0 to High(AAll) do
    if AAll[i].Row >= 0 then
    begin
      ASolved.Nodes[n] := AAll[i];
      Inc(n);
    end;
  SetLength(ASolved.Nodes, n);
  n := 0;
  SetLength(ASolved.Edges, Length(AAllEdges));
  for i := 0 to High(AAllEdges) do
  begin
    a := AAll[AAllEdges[i].Source].Row;
    b := AAll[AAllEdges[i].Target].Row;
    if (a < 0) or (b < 0) then Continue;
    ASolved.Edges[n] := AAllEdges[i];
    ASolved.Edges[n].Source := a;
    ASolved.Edges[n].Target := b;
    Inc(n);
  end;
  SetLength(ASolved.Edges, n);
end;

{ Every survivor's curveness. ASKED OF THE MAP BUILT OVER EVERY EDGE. A
  survivor's key still matches only if neither of its ends was renumbered by
  the filter -- a node before either end taken out shifts it -- and the force
  layout looks the edge up by its SURVIVING position (AByPosition) where the
  others use the one it was filed under. Without a filter every answer is the
  plain one. }
procedure SolveSurvivorCurveness(var ASolved: TTyGraphSolved;
  const AAll: TTyGraphNodeArray; const AAllEdges: TTyGraphEdgeArray;
  ACircular, AByPosition: Boolean);
var
  i, a, b: Integer;
  qr, ql: array of Integer;
  ok: array of Boolean;
  res: TTyDoubleArray;
begin
  SetLength(qr, Length(ASolved.Edges));
  SetLength(ql, Length(ASolved.Edges));
  SetLength(ok, Length(ASolved.Edges));
  for i := 0 to High(ASolved.Edges) do
  begin
    qr[i] := ASolved.Edges[i].RawIndex;
    if AByPosition then ql[i] := i else ql[i] := qr[i];
    a := AAllEdges[qr[i]].Source;
    b := AAllEdges[qr[i]].Target;
    ok[i] := (AAll[a].Row = a) and (AAll[b].Row = b);
  end;
  SolveCurvenessQueries(AAllEdges, ASolved.Spec, ACircular, qr, ql, ok, res);
  for i := 0 to High(ASolved.Edges) do
    ASolved.Edges[i].SolvedCurveness := res[i];
end;

function TyGraphSolve(AOption: TTyChartOption; ASeriesIndex: Integer;
  AStore: TTyDataStore; const AContainer: TTyRectF;
  var AForce: TTyGraphForceState): TTyGraphSolved;
begin
  Result := TyGraphSolve(AOption, ASeriesIndex, AStore, AContainer, AForce,
    Default(TTyGraphRoamState));
end;

function TyGraphSolve(AOption: TTyChartOption; ASeriesIndex: Integer;
  AStore: TTyDataStore; const AContainer: TTyRectF;
  var AForce: TTyGraphForceState;
  const ARoam: TTyGraphRoamState): TTyGraphSolved;
var
  dataRect, viewRect: TTyRectF;
  viewBox: TTyXYWH;
  aspect: Double;
  hasData, circ: Boolean;
  mask: TFPUExceptionMask;
  all: TTyGraphNodeArray;
  allEdges: TTyGraphEdgeArray;
  i: Integer;
  initX, initY: TTyDoubleArray;
  kind: Integer;

  { Which pass this force layout is: 0 fresh, 1 reusing the answer, 2
    continuing from it -- the same test TyGraphLayoutForce makes. }
  function ForcePassKind(const ARect, AViewRect: TTyRectF;
    ACount: Integer): Integer;
  begin
    if not (AForce.Valid and (Length(AForce.X) = ACount)
      and (Length(AForce.Y) = ACount)) then Exit(0);
    if (AForce.Rect.Left = ARect.Left) and (AForce.Rect.Top = ARect.Top)
      and (AForce.Rect.Right = ARect.Right)
      and (AForce.Rect.Bottom = ARect.Bottom)
      and (AForce.ViewRect.Left = AViewRect.Left)
      and (AForce.ViewRect.Top = AViewRect.Top)
      and (AForce.ViewRect.Right = AViewRect.Right)
      and (AForce.ViewRect.Bottom = AViewRect.Bottom) then Exit(1);
    Result := 2;
  end;

  procedure ApplyStalePoints;
  var j, s, t: Integer; c, cx, cy, x12, y12: Double; initRes: TTyDoubleArray;
      rect: TTyRectF; circInit: Boolean; qi, ql2: array of Integer;
      oki: array of Boolean;
  begin
    if kind = 1 then
    begin
      for j := 0 to High(Result.Edges) do
        if (j <= High(AForce.Stale)) and AForce.Stale[j] then
        begin
          Result.Edges[j].HasStale := True;
          Result.Edges[j].StaleX := AForce.StaleX[j];
          Result.Edges[j].StaleY := AForce.StaleY[j];
        end;
      Exit;
    end;
    SetLength(AForce.Stale, Length(Result.Edges));
    SetLength(AForce.StaleX, Length(Result.Edges));
    SetLength(AForce.StaleY, Length(Result.Edges));
    for j := 0 to High(Result.Edges) do
    begin
      AForce.Stale[j] := False;
      AForce.StaleX[j] := NaN;
      AForce.StaleY[j] := NaN;
    end;
    if (kind <> 0) or (Result.Spec.Force.InitLayout = gilOther) then Exit;
    { THE INITIAL LAYOUT'S EDGE PASS: `none` asks the negated, reversed
      family and the ring the plain one -- both by the edge's RAW index. }
    circInit := Result.Spec.Force.InitLayout = gilCircular;
    SetLength(qi, Length(Result.Edges));
    SetLength(ql2, Length(Result.Edges));
    SetLength(oki, Length(Result.Edges));
    for j := 0 to High(Result.Edges) do
    begin
      qi[j] := Result.Edges[j].RawIndex;
      ql2[j] := qi[j];
      s := allEdges[qi[j]].Source;
      t := allEdges[qi[j]].Target;
      oki[j] := (all[s].Row = s) and (all[t].Row = t);
    end;
    SolveCurvenessQueries(allEdges, Result.Spec, circInit, qi, ql2, oki, initRes);
    rect := Result.View.GetDataRect;
    cx := (rect.Right - rect.Left) / 2 + rect.Left;
    cy := (rect.Bottom - rect.Top) / 2 + rect.Top;
    for j := 0 to High(Result.Edges) do
    begin
      c := initRes[j];
      if IsNan(c) or (c = 0) then Continue;
      s := Result.Edges[j].Source;
      t := Result.Edges[j].Target;
      x12 := (initX[s] + initX[t]) / 2;
      y12 := (initY[s] + initY[t]) / 2;
      if circInit then
      begin
        c := c * 3;
        AForce.StaleX[j] := cx * c + x12 * (1 - c);
        AForce.StaleY[j] := cy * c + y12 * (1 - c);
      end
      else
      begin
        AForce.StaleX[j] := x12 - (initY[s] - initY[t]) * c;
        AForce.StaleY[j] := y12 - (initX[t] - initX[s]) * c;
      end;
      AForce.Stale[j] := True;
      Result.Edges[j].HasStale := True;
      Result.Edges[j].StaleX := AForce.StaleX[j];
      Result.Edges[j].StaleY := AForce.StaleY[j];
    end;
  end;

begin
  Result := Default(TTyGraphSolved);
  GatherGraph(AOption, ASeriesIndex, AStore, Result, all, allEdges);

  mask := MaskFP;
  try
    { THE ORDER IS UPSTREAM'S AND IT MATTERS. The data rectangle is taken from
      the positions the author wrote, the box is solved with the aspect that
      came out of it -- and only THEN, if there were no positions at all, is
      the data rectangle replaced by the box. So the box has already been
      solved by the time anyone notices there was nothing to fit.

      AND FROM EVERY NODE, the switched-off ones included: upstream creates the
      view before the legend filter runs (its own comment asks whether it
      should not be after). So switching the outermost category off does not
      re-fit the rest, and the force layout's random box and its centre of
      gravity still span the nodes nobody can see. }
    hasData := TyGraphDataRect(all, dataRect, aspect);
    viewBox := TyGraphViewXYWH(Result.Spec, AContainer, aspect);
    viewRect := TyRectOfXYWH(viewBox);
    if hasData then
      Result.View := TTyGraphView.CreateXYWH(TyXYWHOfRect(dataRect), viewBox)
    else
    begin
      dataRect := viewRect;
      Result.View := TTyGraphView.CreateXYWH(viewBox, viewBox);
    end;
    { THE ROAM, before any layout: the ring sizes its shares by the
      compensation scale the zoom makes. A roam's own centre and zoom beat
      the option's -- upstream wrote them back into it. }
    if ARoam.Valid then
      Result.View.SetRoam(ARoam.Centre, ARoam.Zoom, Result.Spec.HasLimit,
        Result.Spec.LimitMin, Result.Spec.LimitMax)
    else
      Result.View.SetRoam(Result.Spec.Centre, Result.Spec.Zoom,
        Result.Spec.HasLimit, Result.Spec.LimitMin, Result.Spec.LimitMax);
    Result.NodeScale := Result.View.NodeScale(Result.Spec.NodeScaleRatio);

    case Result.Spec.Layout of
      glCircular:
        TyGraphLayoutCircular(Result.Nodes, Result.View, Result.Spec,
          Result.NodeScale);
      glForce:
        begin
          { WHERE THE INITIAL LAYOUT PUT EVERY SURVIVOR, taken before the
            solver moves them: the written positions, or the ring by value. }
          kind := ForcePassKind(dataRect, viewRect, Length(Result.Nodes));
          SetLength(initX, Length(Result.Nodes));
          SetLength(initY, Length(Result.Nodes));
          for i := 0 to High(Result.Nodes) do
          begin
            initX[i] := Result.Nodes[i].X;
            initY[i] := Result.Nodes[i].Y;
          end;
          if Result.Spec.Force.InitLayout = gilCircular then
            RingByValue(Result.Nodes, dataRect, initX, initY);
          TyGraphLayoutForce(Result.Nodes, Result.Edges, Result.View,
            Result.Spec, TyGraphForceSeed(ASeriesIndex), AForce);
        end;

    else
      TyGraphLayoutNone(Result.Nodes, Result.View);
    end;

    { THE EDGES AFTER THE NODES, because their control points are made of the
      nodes' final positions -- and the ring is the only layout that reads the
      curveness table without turning it round. }
    { THE FORCE LAYOUT'S LEFTOVERS. Upstream's force pass rewrites an edge's
      control point only when its OWN curveness is truthy, and its lookup by
      the filtered edge index can come out falsy where the initial layout's
      lookup by the raw index did not -- so the point the initial layout's edge
      pass wrote, from the INITIAL positions, is what gets drawn. Only on the
      pass that ran an initial layout: a later pass starts from fresh edge
      data with no points on it, and one that reuses the answer shows what the
      first one showed. }
    if Result.Spec.Layout = glForce then
      ApplyStalePoints;
    circ := Result.Spec.Layout = glCircular;
    SolveSurvivorCurveness(Result, all, allEdges, circ,
      Result.Spec.Layout = glForce);
    TyGraphEdgeGeometry(Result.Edges, Result.Nodes, Result.View, circ);
    TyGraphSanitiseView(Result.Nodes, Result.View);
    TyGraphTrimInView(Result.Edges, Result.Nodes, Result.Spec, Result.NodeScale);
    TyGraphMapEdges(Result.Edges, Result.View);
  finally
    UnmaskFP(mask);
  end;
end;

function TyGraphSolveOnCoordSys(AOption: TTyChartOption; ASeriesIndex: Integer;
  AStore: TTyDataStore; const ACoordSys: ITyCoordSys;
  AColX, AColY: Integer): TTyGraphSolved;
var
  mask: TFPUExceptionMask;
  all: TTyGraphNodeArray;
  allEdges: TTyGraphEdgeArray;
  i, row: Integer;
  x, y: Double;
  p: TTyPointF;
begin
  Result := Default(TTyGraphSolved);
  GatherGraph(AOption, ASeriesIndex, AStore, Result, all, allEdges);
  mask := MaskFP;
  try
    for i := 0 to High(Result.Nodes) do
    begin
      { THE TWO COORDINATES FROM THE COLUMNS, at the node's VIEW row -- the
        legend's category filter is a view, and a column read by raw row
        would hand a survivor the value of the node before it. The x and y
        the author may have written on the item are the view layout's words
        and mean nothing here. }
      row := Result.Nodes[i].Row;
      x := NaN;
      y := NaN;
      if (AStore <> nil) and (row >= 0) and (row < AStore.Count) then
      begin
        if (AColX >= 0) and (AColX < AStore.DimCount) then
          x := AStore.Get(AColX, row);
        if (AColY >= 0) and (AColY < AStore.DimCount) then
          y := AStore.Get(AColY, row);
      end;
      Result.Nodes[i].X := x;
      Result.Nodes[i].Y := y;
      Result.Nodes[i].PX := NaN;
      Result.Nodes[i].PY := NaN;
      { A HALF IS NOT A PLACE. Upstream keeps one half of a point whose other
        half is not-a-number, and draws neither the node nor its links; the
        port keeps no halves at all, which draws the same nothing. A value
        off the axis is placed off the grid, unclamped: nothing about a graph
        is clipped. }
      if IsNan(x) or IsNan(y) or (ACoordSys = nil) then Continue;
      p := ACoordSys.DataToPoint([x, y]);
      Result.Nodes[i].PX := p.X;
      Result.Nodes[i].PY := p.Y;
    end;
    { THE `none` FAMILY, by raw index, whatever `layout` says: upstream's
      one layout for a graph off a view is simpleLayoutEdge. }
    SolveSurvivorCurveness(Result, all, allEdges, False, False);
    TyGraphEdgeGeometry(Result.Edges, Result.Nodes, nil, False);
    TyGraphSanitise(Result.Nodes);
    Result.NodeScale := 1;
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

function TyGraphEdgeStroke(const ASpec: TTyGraphSpec;
  const AEdges: TTyGraphEdgeArray; const AInk: TTyGraphInk;
  AAt: Integer): TTyChartColor;
var at: Integer;
begin
  Result := AInk.EdgeColour;
  if ASpec.ColourBy = gecFixed then Exit;
  if (AAt < 0) or (AAt > High(AEdges)) then Exit;
  if ASpec.ColourBy = gecSource then at := AEdges[AAt].Source
  else at := AEdges[AAt].Target;
  if (at >= 0) and (at <= High(AInk.EdgeEndFills)) then
    Result := AInk.EdgeEndFills[at]
  else if (at >= 0) and (at <= High(AInk.NodeFills)) then
    Result := AInk.NodeFills[at];
end;

function TyBuildGraphMarks(ASeriesIndex: Integer;
  const ASpec: TTyGraphSpec; const ANodes: TTyGraphNodeArray;
  const AEdges: TTyGraphEdgeArray; const AInk: TTyGraphInk;
  AStore: TTyDataStore; AList: TTyPaintList): Integer;
begin
  Result := TyBuildGraphMarks(ASeriesIndex, ASpec, ANodes, AEdges, AInk,
    AStore, AList, 1, 1);
end;

function TyBuildGraphMarks(ASeriesIndex: Integer;
  const ASpec: TTyGraphSpec; const ANodes: TTyGraphNodeArray;
  const AEdges: TTyGraphEdgeArray; const AInk: TTyGraphInk;
  AStore: TTyDataStore; AList: TTyPaintList;
  ASymX, ASymY: Double): Integer;
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

  function EdgeColour(AAt: Integer): TTyChartColor;
  begin
    Result := TyGraphEdgeStroke(ASpec, AEdges, AInk, AAt);
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
    { THE EDGE'S DATUM, and still silent: a hover never lands on an
      arrowhead, but a blur or an emphasis of the edge takes its arrowheads
      with it. [Revised in batch 46: the datum was (series, -1).] }
    e.Datum := TyChartEdgeDatum(ASeriesIndex, AEdges[edgeAt].Row);
    AList.Add(e);
    Inc(Result);
  end;

begin
  Result := 0;
  { NO COORDINATE SYSTEM IS ASKED HERE. Every position this draws was solved
    into pixels already -- by a view or by a pair of axes -- so the one
    builder serves both. }
  if AList = nil then Exit;

  for i := 0 to High(AEdges) do
  begin
    if (AEdges[i].Source < 0) or (AEdges[i].Source > High(ANodes)) then Continue;
    if (AEdges[i].Target < 0) or (AEdges[i].Target > High(ANodes)) then Continue;
    p1 := TyPointF(ANodes[AEdges[i].Source].PX, ANodes[AEdges[i].Source].PY);
    p2 := TyPointF(ANodes[AEdges[i].Target].PX, ANodes[AEdges[i].Target].PY);
    if IsNan(p1.X) or IsNan(p1.Y) or IsNan(p2.X) or IsNan(p2.Y) then Continue;
    if AEdges[i].Hidden then Continue;
    if AEdges[i].NaNCurve
      and (((ASpec.EdgeSymbolFrom <> '') and (ASpec.EdgeSymbolFrom <> 'none'))
        or ((ASpec.EdgeSymbolTo <> '') and (ASpec.EdgeSymbolTo <> 'none'))) then
      Continue;

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
    { ON A VIEW THE LAYOUT PASS HAS DONE IT ALREADY, in data space -- the
      only place a zoom can be undone -- and these are its ends. }
    if AEdges[i].HasEnds then
    begin
      p1 := TyPointF(AEdges[i].EX1, AEdges[i].EY1);
      p2 := TyPointF(AEdges[i].EX2, AEdges[i].EY2);
      if curved then cp := TyPointF(AEdges[i].ECPX, AEdges[i].ECPY);
      if IsNan(p1.X) or IsNan(p1.Y) or IsNan(p2.X) or IsNan(p2.Y) then Continue;
    end
    else
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
    el.Datum := TyChartEdgeDatum(ASeriesIndex, AEdges[i].Row);
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
    { THE SYMBOL'S HALF-EXTENTS as zrender composes them: the group's scale
      times the compensation scale, then times the half size. }
    if (ASymX <> 1) or (ASymY <> 1) then
    begin
      sym.WidthPx := ASymX * (sym.WidthPx / 2) * 2;
      sym.HeightPx := ASymY * (sym.HeightPx / 2) * 2;
    end;

    shape := TyBuildSymbol(sym, ANodes[i].PX, ANodes[i].PY);
    if (shape.Kind = cskRect) and not TyRectFIsValid(shape.Bounds) then Continue;
    fill := 0;
    if (i >= 0) and (i <= High(AInk.NodeFills)) then fill := AInk.NodeFills[i];
    el := TyChartElement(shape);
    el.Style.HasFill := fill <> 0;
    el.Style.FillColor := fill;
    el.Style.Alpha := 1;
    el.Z := ASpec.Z;
    { ABOVE ITS OWN EDGES, by upstream's hundred -- far enough that a hovered
      edge, lifted by ten, still passes under every node. [Revised in batch
      46: by one, which a lifted edge overtook.] }
    el.Z2 := ASpec.Z2 + cTyGraphNodeZ2;
    el.Silent := False;
    { THE ROW IT WAS WRITTEN AT AS WELL: under a legend filter the two differ,
      and what a datum reports is the author's numbering. }
    el.Datum := TyChartDatum(ASeriesIndex, ANodes[i].Row, ANodes[i].RawRow);
    el.HitSlopLogical := 4;
    if AInk.Label_.Show and (AInk.Label_.Position <> tlpNone) then
      el.Caption.Text := TyLabelText(AInk.Label_.Formatter,
        AInk.Label_.HasFormatter, AInk.Label_.DefaultText, AStore,
        ANodes[i].Row, AInk.SeriesName, AInk.LabelValueDim, 0, False);
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
