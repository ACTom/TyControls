unit tyControls.AdvChart.Brush;
{$mode objfpc}{$H+}
{ The brush component's covers: what ECharts 6.1's component/brush
  (BrushModel.ts, BrushView.ts, the `brush` action) and
  component/helper/BrushController.ts and BrushTargetManager.ts do between
  the option, the pointer and the areas -- held to the real dist by
  tools/advchart-oracle/brush-cover.js. [Batch 126, C17]

  THE MODEL (BrushModel.ts): a brush component's defaults (brushType rect,
  brushMode single, transformable, brushStyle a one-pixel border, the
  throttle fixRate at 0 ms, removeOnClick, z 10000) and its finder (the
  xAxis / yAxis / grid keys). The painting option takeGlobalCursor sets
  and every area the `brush` action sets are generateBrushOption's merge:
  the model's brushType, brushMode, transformable, brushStyle (as
  getItemStyle maps it), removeOnClick and z, under the keys written.

  THE CONTROLLER (BrushController.ts): enabled by a painting option with a
  brush type; its panels (a target grid's rect each, or none -- the global
  panel, the whole canvas); its covers, each a main shape and, for a rect
  or a line, resize handles (eight for a rect, w / e for lineX, n / s for
  lineY), sized by updateBaseRect and clipped to the cover's panel. A press
  in a panel not on a draggable element starts a track; once its two ends
  are more than six pixels apart a cover is drawn (single mode clearing
  the others first) whose range is the clipped track (its two ends for a
  rect or a line); the release ends it and makes it answer the pointer. A
  release that drew nothing in single mode with removeOnClick clears the
  covers when the release is in a panel. Dragging a cover's main shape
  moves it, a handle moves its edges (driftRect, formatRectRange after);
  the range is not clipped, its shapes are. Every change triggers `brush`
  with the covers' areas; a drag's end and a gesture's release trigger it
  with isEnd. updateCovers lays the covers from areas by DataDiffer, keyed
  by the id or the index and the type.

  THE TARGETS (BrushTargetManager.ts): the conversions between a pixel
  range and a data range on a cartesian (pointToData clamped or the affine
  inverse; dataToPoint; a line's axis coordToData clamped and dataToCoord),
  the round trip's offset and the size ratio that lays a kept area back
  (__rangeOffset, getScales).

  THE THROTTLE (util/throttle): fixRate and debounce, as brushSelect's
  dispatch takes them.

  THE SELECTION (visualEncoding.ts, selector.ts) [Batch 127, C18]: an
  area's bounding rect, the point and rect selectors of the four brush
  types against an item's layout (zrender's polygon contain, BoundingRect's
  contain and intersect, linePolygonIntersect), and the inBrush /
  outOfBrush visuals through the fixed mappings onto a visual row. The
  brush preprocessor's toolbox list (preprocessor.ts) is the option unit's.

  THE PARALLEL AXES' AREA SELECT (ParallelAxisView.ts) [Batch 130, C20]: a
  controller MOUNTED in an axis' frame -- its group moved to the axis' place
  and turned by its rotation (getLocalTransform, matrix.invert) -- whose one
  panel is the band along the axis (the extent widened by min(30, 10% of
  it) at both ends, areaSelectStyle.width across) and whose covers are lineX
  in that frame. The pointer comes in through the group's inverse
  (transformCoordToLocal), a drag's delta through toLocalDelta, a handle's
  cursor through transformDirection. resetCursor asks Path.contain with the
  point it already made local, and contain makes it local AGAIN -- over a
  turned axis' cover the crosshair stays; that is upstream's and it is kept.

  PURE: options and numbers in, records out. CSS px throughout; a
  conversion takes the view that maps them to the cartesian's device px. }
interface
uses SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Coord,
  tyControls.AdvChart.VisualMap;

const
  TyBrushCoverZ = 10000;
  TyBrushUnselectThreshold = 6;
  TyBrushMinResizeLineWidth = 6;
  { the brush index a parallel axis' controller answers to: this plus its
    parallelAxis component index [Batch 130] }
  TyParallelBrushBase = 64;
  { a parallelAxis' areaSelectStyle defaults (component/parallel/install.ts):
    the band's width, the border's, the opacity; the colours are the skin's }
  TyParallelSelectWidth = 20;
  TyParallelSelectBorderWidth = 1;
  TyParallelSelectOpacity = 0.3;
  { the skin key of the areaSelectStyle colours' defaults }
  TyParallelSelectSkin = 'TyAdvChartParallelSelect';

type
  TTyBrushType = (btNone, btRect, btPolygon, btLineX, btLineY);
  { a range as upstream nests it: a line's [min, max] is one pair, a rect's
    [[xmin, xmax], [ymin, ymax]] two, a polygon's points one each }
  TTyBrushPair = array[0..1] of Double;
  TTyBrushRange = array of TTyBrushPair;
  TTyBrushRangeArray = array of TTyBrushRange;

  { a colour as written, or the skin's own (upstream's tokens) }
  TTyBrushInk = record
    Written: Boolean;
    Text: string;
    { not written: the skin key that stands in for a default the option
      set (a parallel axis' areaSelectStyle colours); '' the brush's own
      [Batch 130] }
    Skin: string;
  end;

  { the cover's style: fill, stroke, lineWidth, opacity -- NaN where not set }
  TTyBrushStyle = record
    Fill, Stroke: TTyBrushInk;
    LineWidth: Double;
    Opacity: Double;
  end;

  { BrushCoverConfig: what a cover is drawn from }
  TTyBrushOpt = record
    BrushType: TTyBrushType;
    { brushMode is anything but 'single' }
    Multiple: Boolean;
    Transformable, RemoveOnClick: Boolean;
    { NaN: unset (COVER_Z) }
    Z: Double;
    Style: TTyBrushStyle;
    HasId: Boolean;
    Id: string;
    { no panel: the global one }
    HasPanel: Boolean;
    PanelId: string;
    HasRange: Boolean;
    Range: TTyBrushRange;
  end;
  TTyBrushOptArray = array of TTyBrushOpt;

  { BrushAreaParamInternal: an area the model keeps, or one the controller
    outputs }
  TTyBrushArea = record
    Opt: TTyBrushOpt;
    HasCoordRange: Boolean;
    CoordRange: TTyBrushRange;
    HasCoordRanges: Boolean;
    CoordRanges: TTyBrushRangeArray;
    { __rangeOffset }
    HasOffset: Boolean;
    Offset, OffsetXY: TTyBrushRange;
    { the area's own finder keys (xAxisIndex, yAxisId, gridName ...) as a
      JSON object, '' for none }
    Finder: string;
  end;
  TTyBrushAreaArray = array of TTyBrushArea;

  TTyBrushThrottleKind = (btkNone, btkFixRate, btkDebounce);

  { a brush component's model, as its option gives it }
  TTyBrushSpec = record
    { generateBrushOption's base }
    Base: TTyBrushOpt;
    { the throttle createOrUpdate is asked for: none (null delay or a falsy
      type), else the type's word and the delay }
    ThrottleKind: TTyBrushThrottleKind;
    ThrottleType: string;
    ThrottleDelay: Double;
    { the component's finder keys as a JSON object }
    Finder: string;
  end;

  TTyBrushPiece = (bpMain, bpW, bpE, bpN, bpS, bpSE, bpSW, bpNE, bpNW);

  TTyBrushCover = record
    { the order it was added to the controller's group: what is over what }
    Serial: Integer;
    Opt: TTyBrushOpt;
    { updateCommon ran: the pieces answer the pointer as transformable says
      (a cover being drawn is silent) }
    Live: Boolean;
    { a polygon's endCreating ran: a Polygon, not the Polyline drawn while
      the track grew }
    Closed: Boolean;
    Main: TTyXYWH;
    Points: array of TTyPointF;
    { the handles' rects (bpMain unused); zero until updateBaseRect sizes
      them -- a cover that is not transformable never does }
    Handle: array[TTyBrushPiece] of TTyXYWH;
  end;
  TTyBrushCoverArray = array of TTyBrushCover;

  TTyBrushPanel = record
    Id: string;
    Rect: TTyXYWH;
    { the type a brush of type 'auto' draws in this panel (the toolbox's
      dataZoom select: lineX, lineY or rect) [Batch 127] }
    DefaultType: TTyBrushType;
    { the grid component the panel is (targetInfo.coordSysModel), -1 none
      [Batch 127] }
    GridComponent: Integer;
  end;

  { isTargetByCursor's second half: onIrrelevantElement -- True when what the
    pointer is over at (AX, AY), CSS px, belongs to another coordinate
    system drawn over the panel [Batch 127] }
  TTyBrushPanelFilter = function(const APanel: TTyBrushPanel; AX, AY: Double): Boolean of object;

  { a group's transform, zrender's six numbers [Batch 130] }
  TTyBrushMat = array[0..5] of Double;

  { the controller's `brush` event }
  TTyBrushTrigger = record
    Fired, IsEnd, RemoveOnClick: Boolean;
    Areas: TTyBrushAreaArray;
  end;

  { BrushController }
  TTyBrushController = class
  private
    FNextSerial: Integer;
    function NewCover(const AOpt: TTyBrushOpt): Integer;
    { getPanelByCover: -2 the global panel, -1 none (a panel id no panel
      has), else the panel's index }
    function PanelOfCover(AIndex: Integer): Integer;
    { getPanelByPoint: the same answers }
    function PanelAt(AX, AY: Double): Integer;
    function ClipByPanel(AIndex: Integer; const APoints: TTyBrushRange): TTyBrushRange;
    procedure UpdateShape(AIndex: Integer);
    procedure UpdateCommon(AIndex: Integer);
    procedure EndCreating(AIndex: Integer);
    function ClearCovers: Boolean;
    function Trigger(AIsEnd, ARemoveOnClick: Boolean): TTyBrushTrigger;
    function ShouldShowCover: Boolean;
    function UpdateByMouse(AX, AY: Double; AIsEnd: Boolean): TTyBrushTrigger;
    function HandleDragEnd(AX, AY: Double): TTyBrushTrigger;
    { toLocalDelta [Batch 130] }
    procedure ToLocalDelta(ADX, ADY: Double; out LX, LY: Double);
  public
    { _brushType: drawing is on }
    Enabled: Boolean;
    { _brushOption: the painting option merged over DEFAULT_BRUSH_OPT }
    Opt: TTyBrushOpt;
    HasPanels: Boolean;
    Panels: array of TTyBrushPanel;
    { _covers, in their own order (the group's is the serials') }
    Covers: TTyBrushCoverArray;
    { the cover being drawn (its serial), -1 }
    Creating: Integer;
    { _creatingPanel: -1 none, -2 global, else the panel's index }
    CreatingPanel: Integer;
    Track: array of TTyPointF;
    Dragging: Boolean;
    { the canvas, CSS px: the global panel's extent }
    CanvasW, CanvasH: Double;
    { brushType 'auto': each new cover takes its panel's DefaultType
      [Batch 127] }
    Auto: Boolean;
    { the controller's own uid: whose globalPan the mutex holds [Batch 127] }
    Uid: Integer;
    { onIrrelevantElement, asked of every panel a point is in (nil: none)
      [Batch 127] }
    IsIrrelevant: TTyBrushPanelFilter;
    { THE GROUP'S TRANSFORM (mount) [Batch 130]: Xf the local transform
      (the identity until mounted), Inv its inverse when the group needs a
      transform at all (needLocalTransform) -- the pointer comes in through
      it; without one a point is already local }
    Xf: TTyBrushMat;
    HasInv: Boolean;
    Inv: TTyBrushMat;
    constructor Create;
    { mount with x, y and rotation }
    procedure Mount(AX, AY, ARotation: Double);
    { transformCoordToLocal }
    procedure ToLocal(AX, AY: Double; out LX, LY: Double);
    { a piece's cursor: 'move' for the main shape, a handle's through the
      group's transform (getGlobalDirection, CURSOR_MAP) }
    function PieceCursor(APiece: TTyBrushPiece; ATransformable: Boolean): string;
    { enableBrush: a type turns drawing on with the option merged over the
      defaults; btNone turns it off }
    procedure EnableBrush(const AOpt: TTyBrushOpt);
    { enableBrush with brushType 'auto': on, each cover typed by its
      panel [Batch 127] }
    procedure EnableAuto(const AOpt: TTyBrushOpt);
    procedure SetPanels(const APanels: array of TTyBrushPanel; AHasPanels: Boolean);
    procedure UpdateCovers(const AConfigs: array of TTyBrushOpt);
    { the pointer handlers (only while Enabled); ATargetDraggable: the press
      is on a draggable element. The pointer is the canvas' (CSS px); a
      mounted controller turns it local [Batch 130] }
    function MouseDown(AX, AY: Double; ATargetDraggable: Boolean): TTyBrushTrigger;
    function MouseMove(AX, AY: Double): TTyBrushTrigger;
    function MouseUp(AX, AY: Double): TTyBrushTrigger;
    { resetCursor: True where it sets the crosshair }
    function Crosshair(AX, AY: Double): Boolean;
    { a piece under zrender's Draggable: drift, and its dragend }
    function Drift(ASerial: Integer; APiece: TTyBrushPiece; ADX, ADY: Double): TTyBrushTrigger;
    function DragEnd(ASerial: Integer): TTyBrushTrigger;
    function IndexOf(ASerial: Integer): Integer;
    { the topmost piece that answers the pointer at (AX, AY) }
    function PieceAt(AX, AY: Double; out AIndex: Integer; out APiece: TTyBrushPiece): Boolean;
    function PieceSilent(AIndex: Integer; APiece: TTyBrushPiece): Boolean;
    { the main shape's Path.contain, silent or not }
    function MainContains(AIndex: Integer; AX, AY: Double): Boolean;
    { the cover indices in the group's order }
    function GroupOrder: TTyIntegerArray;
  end;

  { device px = O + css * S }
  TTyBrushView = record
    OX, OY, S: Double;
  end;

  { a BrushTargetManager target: a grid the finder reaches, with the
    cartesians on it whose x or y axis the finder names (the first is the
    representative one) }
  TTyBrushTarget = record
    PanelId: string;
    { the grid's component index and its index in the build }
    GridComponent, Grid: Integer;
    Rect: TTyXYWH;
    Carts: array of TTyCartesian2D;
  end;
  TTyBrushTargetArray = array of TTyBrushTarget;

  { one series in a brushSelect batch item: the raw indices it selected
    [Batch 127] }
  TTyBrushSelSeries = record
    SeriesIndex: Integer;
    SeriesId, SeriesName: string;
    DataIndex: TTyIntegerArray;
  end;
  TTyBrushSelSeriesArray = array of TTyBrushSelSeries;

  { one brush component in a brushSelect batch }
  TTyBrushSelectItem = record
    BrushIndex: Integer;
    BrushId, BrushName: string;
    Areas: TTyBrushAreaArray;
    { every series the visual stage visited, in series order [Batch 127] }
    Selected: TTyBrushSelSeriesArray;
  end;
  TTyBrushSelectBatch = array of TTyBrushSelectItem;
  { a brushSelect dispatch that ran: when (ms), and what it carried }
  TTyBrushSelectRec = record
    Time: Double;
    Batch: TTyBrushSelectBatch;
  end;
  { a brush / brushend event: its brush, whether the brush's own controller
    sent it ($from), its areas, the payload as emitted }
  TTyBrushEventRec = record
    EventType: string;
    Brush: Integer;
    FromSelf: Boolean;
    Areas: TTyBrushAreaArray;
    Payload: string;
  end;
  { a brushSelect waiting on the throttle's timer }
  TTyBrushPending = record
    Id: Integer;
    Due: Double;
    Gen: Integer;
    Batch: TTyBrushSelectBatch;
  end;

  { an item's layout as its series' brushSelector reads it: a point
    (scatter, effectScatter), a rect (a bar's layout, a candle's brushRect),
    or none (large mode, a gap) [Batch 127] }
  TTyBrushLayoutKind = (blkNone, blkPoint, blkRect);
  TTyBrushItemLayout = record
    Kind: TTyBrushLayoutKind;
    X, Y, W, H: Double;
  end;
  TTyBrushItemLayoutArray = array of TTyBrushItemLayout;

  { BrushSelectableArea: an area with its boundingRect (rect and polygon) }
  TTyBrushSelArea = record
    BrushType: TTyBrushType;
    Range: TTyBrushRange;
    HasBR: Boolean;
    BR: TTyXYWH;
  end;
  TTyBrushSelAreaArray = array of TTyBrushSelArea;

  { the inBrush / outOfBrush visuals of a brush model: per state (True in
    the brush) the fixed visuals in prepareVisualTypes' order }
  TTyBrushVisual = record
    States: array[Boolean] of TTyVisualPieceVisualArray;
    { outOfBrush is the default (its colour defaultOutOfBrushColor) and the
      option writes no defaultOutOfBrushColor: the skin's colour }
    OutIsSkin: Boolean;
  end;

  { brushLink }
  TTyBrushLinkKind = (blnNone, blnAll, blnList);

  { what a brush model selects beyond its areas: brushLink and seriesIndex }
  TTyBrushReach = record
    Link: TTyBrushLinkKind;
    LinkList: TTyIntegerArray;
    { seriesIndex null / 'all': every series }
    AllSeries: Boolean;
    SeriesList: TTyIntegerArray;
  end;

{ ---- names ---- }

function TyBrushTypeName(AType: TTyBrushType): string;
function TyBrushTypeOf(const AName: string): TTyBrushType;
function TyBrushPieceName(APiece: TTyBrushPiece): string;
{ the pieces a cover of the type has (main first, then the handles in the
  order the cover adds them) }
function TyBrushHasPiece(AType: TTyBrushType; APiece: TTyBrushPiece): Boolean;
{ the cursor a piece shows: 'move' / '<dir>-resize' when transformable,
  'default' / '' when not (a handle's null) }
function TyBrushPieceCursor(APiece: TTyBrushPiece; ATransformable: Boolean): string;

{ ---- the model ---- }

{ DEFAULT_BRUSH_OPT }
function TyBrushDefaultOpt: TTyBrushOpt;
{ a brush component's option node -> its model }
function TyBrushSpecOf(ANode: TJSONData): TTyBrushSpec;
{ merge(clone(ABase), AObj, true) over a cover config's keys: brushType,
  brushMode, transformable, removeOnClick, z, brushStyle (fill, stroke,
  lineWidth, opacity), id, panelId, range. False: a brushType that is not
  one of the four (nor false) }
function TyBrushMergeJson(var AOpt: TTyBrushOpt; AObj: TJSONObject): Boolean;
{ merge(clone(ABase), AOver, true) of two configs: the style's set values,
  and the identity and range of AOver when it has them }
function TyBrushMergeOpt(const ABase, AOver: TTyBrushOpt): TTyBrushOpt;
{ setBrushOption: generateBrushOption over the takeGlobalCursor payload's
  brushOption (nil: none) }
function TyBrushPaintOpt(const ASpec: TTyBrushSpec; ABrushOption: TJSONData): TTyBrushOpt;
{ setAreas: an action's area. False: no usable brushType }
function TyBrushAreaOfJson(const ASpec: TTyBrushSpec; AObj: TJSONObject;
  out AArea: TTyBrushArea): Boolean;
{ an output area (the controller's) as the model keeps it: generateBrushOption
  over it }
function TyBrushAreaOfOutput(const ASpec: TTyBrushSpec; const AOut: TTyBrushArea): TTyBrushArea;
{ a range read as the type nests it (nil when it is not an array) }
function TyBrushRangeOfJson(AType: TTyBrushType; AData: TJSONData): TTyBrushRange;
function TyBrushRangeCopy(const A: TTyBrushRange): TTyBrushRange;
{ the areas of an event payload: brushType, panelId, range and what
  setOutputRanges added (coordRanges, coordRange, __rangeOffset) }
function TyBrushAreasJson(const AAreas: TTyBrushAreaArray): string;
function TyBrushRangeJson(const A: TTyBrushRange; ALine: Boolean): string;
{ JSON.stringify of a string }
function TyBrushJsonStr(const S: string): string;

{ ---- the geometry ---- }

{ clipPointsByRect }
function TyBrushClip(const APoints: TTyBrushRange; const ARect: TTyXYWH): TTyBrushRange;
{ getCreatingRange of a clipped track }
function TyBrushCreatingRange(AType: TTyBrushType; const ATrack: TTyBrushRange): TTyBrushRange;
{ driftRect / driftPolygon on a range }
function TyBrushDrift(AType: TTyBrushType; const ARange: TTyBrushRange;
  APiece: TTyBrushPiece; ADX, ADY: Double): TTyBrushRange;
{ windingLine and line.containStroke, as zrender has them }
function TyBrushWindingLine(AX0, AY0, AX1, AY1, AX, AY: Double): Double;
function TyBrushLineContainStroke(AX0, AY0, AX1, AY1, ALineWidth, AX, AY: Double): Boolean;

{ ---- the coordinates (BrushTargetManager.coordConvert) ---- }

{ AToData: pixel -> data (with AClamp), else data -> pixel. AXYMinMax two
  pairs, NaN on a line's other side. False: no axis to convert on }
function TyBrushConvert(AType: TTyBrushType; AToData: Boolean; ACart: TTyCartesian2D;
  const AView: TTyBrushView; const ARange: TTyBrushRange; AClamp: Boolean;
  out AValues, AXYMinMax: TTyBrushRange): Boolean;
{ diffProcessor }
function TyBrushDiff(AType: TTyBrushType; const AValues, ARefer: TTyBrushRange;
  ASX, ASY: Double): TTyBrushRange;
{ getScales }
procedure TyBrushScales(const ACur, AOrig: TTyBrushRange; out ASX, ASY: Double);

{ ---- the selection [Batch 127] ---- }

{ boundingRectBuilders: the area's rect (a rect's range, a polygon's
  extent) }
function TyBrushSelAreaOf(const AArea: TTyBrushArea): TTyBrushSelArea;
{ selector[brushType].point / .rect against an item's layout }
function TyBrushSelects(const AArea: TTyBrushSelArea; const ALayout: TTyBrushItemLayout): Boolean;
{ zrender's contain/polygon.ts }
function TyBrushPolygonContain(const APoints: TTyBrushRange; AX, AY: Double): Boolean;
{ graphic.linePolygonIntersect }
function TyBrushLinePolygonIntersect(A1X, A1Y, A2X, A2Y: Double;
  const APoints: TTyBrushRange): Boolean;
{ BoundingRect.intersect (touching counts; negative sizes normalised; a
  NaN compares false as JavaScript's does) }
function TyBrushRectIntersect(const A, B: TTyXYWH): Boolean;
{ the model's inBrush / outOfBrush after optionUpdated: inBrush its own or
  an empty one, liftZ 5 unless written; outOfBrush its own or the default
  colour }
function TyBrushVisualOf(ANode: TJSONData): TTyBrushVisual;
{ brushLink and seriesIndex }
function TyBrushReachOf(ANode: TJSONData): TTyBrushReach;
function TyBrushLinks(const AReach: TTyBrushReach; ASeriesIndex: Integer): Boolean;
function TyBrushControls(const AReach: TTyBrushReach; ASeriesIndex: Integer): Boolean;
{ applyVisual of one state's fixed mappings onto a row. AOutColor: the
  skin's out-of-brush colour, for the default (ASkinColor). A colour or an
  opacity it writes is marked late: it comes after the item's own style. }
procedure TyBrushApplyVisual(const AVisuals: TTyVisualPieceVisualArray;
  ASkinColor: Boolean; const AOutColor: TTyVisualColor; var ARow: TTyVisualRow);

{ ---- the parallel axes' area select (ParallelAxisView.ts) [Batch 130] ---- }

type
  { getAreaSelectStyle: the band's width across the axis, the covers' style
    (color -> fill, borderColor -> stroke, borderWidth -> lineWidth,
    opacity) }
  TTyParallelSelectStyle = record
    Width: Double;
    Style: TTyBrushStyle;
  end;

  { an axisAreaSelect a parallel axis' view dispatched: the axis (its
    component index and model id) and the intervals its covers gave }
  TTyParallelBrushAction = record
    Axis: Integer;
    AxisId: string;
    Intervals: array of TTyBrushPair;
  end;

{ A parallelAxis option's areaSelectStyle over the defaults: a key not
  written is the default, one written as a number (a colour as a string) is
  that; null or anything else leaves the cover's default (the brush's). }
function TyParallelSelectStyleOf(AAxis: TJSONData): TTyParallelSelectStyle;
{ The panel along an axis of extent [AE0, AE1]: the extent as a rect AWidth
  across (BoundingRect.create turns a negative size over), min(30, 10%)
  more at both ends }
function TyParallelBrushPanelRect(AE0, AE1, AWidth: Double): TTyXYWH;
{ enableBrush with brushType 'lineX', the areaSelectStyle as brushStyle,
  removeOnClick true }
function TyParallelBrushOpt(const AStyle: TTyParallelSelectStyle): TTyBrushOpt;

{ ---- the throttle (util/throttle.ts) ---- }

type
  TTyBrushThrottle = record
    { a throttled function exists (createOrUpdate made one) }
    Active: Boolean;
    TypeText: string;
    Rate: Double;
    Debounce: Boolean;
    LastCall, LastExec: Double;
    { the pending timer's id, 0 none }
    Timer: Integer;
    { which throttle this is: a pending timer of an older one runs as that
      one's }
    Gen: Integer;
  end;

{ createOrUpdate: True when a call goes through the throttle; False: the
  function itself (a null delay or a falsy type) }
function TyBrushThrottleConfigure(var T: TTyBrushThrottle; AKind: TTyBrushThrottleKind;
  const ATypeText: string; ARate: Double): Boolean;
{ the throttled function's call at ANow: AExecNow, or a timer due at ADue
  (the caller clears T.Timer first, as the call's clearTimeout does) }
procedure TyBrushThrottleCall(var T: TTyBrushThrottle; ANow: Double;
  out AExecNow: Boolean; out ADue: Double);

implementation

uses tyControls.AdvChart.Scale, tyControls.AdvChart.JsMath;

var
  GBrushUid: Integer = 0;

function MaskFP: TFPUExceptionMask;
begin
  Result := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
end;

procedure UnmaskFP(const AMask: TFPUExceptionMask);
begin
  ClearExceptions(False);
  {$IFDEF CPUX86_64}
  SetMXCSR(GetMXCSR and not LongWord($3F));
  {$ENDIF}
  SetExceptionMask(AMask);
end;

{ Math.min / Math.max: NaN wins }
function JMin(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if B < A then Result := B else Result := A;
end;

function JMax(A, B: Double): Double;
begin
  if IsNan(A) or IsNan(B) then Exit(NaN);
  if B > A then Result := B else Result := A;
end;

function Pair(A, B: Double): TTyBrushPair;
begin
  Result[0] := A;
  Result[1] := B;
end;

{ ==================== names ==================== }

function TyBrushTypeName(AType: TTyBrushType): string;
begin
  case AType of
    btRect: Result := 'rect';
    btPolygon: Result := 'polygon';
    btLineX: Result := 'lineX';
    btLineY: Result := 'lineY';
  else
    Result := '';
  end;
end;

function TyBrushTypeOf(const AName: string): TTyBrushType;
begin
  if AName = 'rect' then Result := btRect
  else if AName = 'polygon' then Result := btPolygon
  else if AName = 'lineX' then Result := btLineX
  else if AName = 'lineY' then Result := btLineY
  else Result := btNone;
end;

function TyBrushPieceName(APiece: TTyBrushPiece): string;
const cNames: array[TTyBrushPiece] of string = ('main', 'w', 'e', 'n', 's',
  'se', 'sw', 'ne', 'nw');
begin
  Result := cNames[APiece];
end;

function TyBrushHasPiece(AType: TTyBrushType; APiece: TTyBrushPiece): Boolean;
begin
  if APiece = bpMain then Exit(AType <> btNone);
  case AType of
    btRect: Result := True;
    btLineX: Result := APiece in [bpW, bpE];
    btLineY: Result := APiece in [bpN, bpS];
  else
    Result := False;
  end;
end;

function TyBrushPieceCursor(APiece: TTyBrushPiece; ATransformable: Boolean): string;
begin
  if APiece = bpMain then
  begin
    if ATransformable then Exit('move');
    Exit('default');
  end;
  if not ATransformable then Exit('');
  { CURSOR_MAP through the group's transform -- the identity here }
  case APiece of
    bpW, bpE: Result := 'ew-resize';
    bpN, bpS: Result := 'ns-resize';
    bpNE, bpSW: Result := 'nesw-resize';
  else
    Result := 'nwse-resize';
  end;
end;

{ ==================== the model ==================== }

function NoStyle: TTyBrushStyle;
begin
  Result := Default(TTyBrushStyle);
  Result.LineWidth := NaN;
  Result.Opacity := NaN;
end;

function TyBrushDefaultOpt: TTyBrushOpt;
begin
  Result := Default(TTyBrushOpt);
  Result.BrushType := btNone;
  Result.Multiple := False;
  Result.Transformable := True;
  Result.RemoveOnClick := False;
  Result.Z := NaN;
  Result.Style := NoStyle;
  { lineWidth 2, the stroke and fill tokens (the skin's) }
  Result.Style.LineWidth := 2;
end;

function JsTruthy(AData: TJSONData): Boolean;
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit(False);
  case AData.JSONType of
    jtBoolean: Result := AData.AsBoolean;
    jtNumber: Result := (AData.AsFloat <> 0) and not IsNan(AData.AsFloat);
    jtString: Result := AData.AsString <> '';
  else
    Result := True;
  end;
end;

function NumOf(AData: TJSONData): Double;
begin
  if (AData <> nil) and (AData.JSONType = jtNumber) then Result := AData.AsFloat
  else Result := NaN;
end;

{ String(v) of an id: a string as itself, a number as JavaScript prints it }
function IdText(AData: TJSONData; out AText: string): Boolean;
begin
  AText := '';
  Result := False;
  if (AData = nil) or (AData.JSONType = jtNull) then Exit;
  case AData.JSONType of
    jtString: AText := AData.AsString;
    jtNumber: AText := TyJsNumberToString(AData.AsFloat);
    jtBoolean: if AData.AsBoolean then AText := 'true' else AText := 'false';
  else
    Exit;
  end;
  Result := True;
end;

procedure InkOf(AData: TJSONData; var AInk: TTyBrushInk);
begin
  if (AData = nil) or (AData.JSONType = jtNull) then Exit;
  if AData.JSONType <> jtString then Exit;
  AInk.Written := True;
  AInk.Text := AData.AsString;
end;

{ the zrender style keys a cover config's brushStyle writes }
procedure MergeStyleJson(var AStyle: TTyBrushStyle; AObj: TJSONObject);
var d: TJSONData;
begin
  InkOf(AObj.Find('fill'), AStyle.Fill);
  InkOf(AObj.Find('stroke'), AStyle.Stroke);
  d := AObj.Find('lineWidth');
  if (d <> nil) and (d.JSONType = jtNumber) then AStyle.LineWidth := d.AsFloat;
  d := AObj.Find('opacity');
  if (d <> nil) and (d.JSONType = jtNumber) then AStyle.Opacity := d.AsFloat;
end;

function TyBrushRangeOfJson(AType: TTyBrushType; AData: TJSONData): TTyBrushRange;
var
  i: Integer;
  it: TJSONData;
begin
  Result := nil;
  if not (AData is TJSONArray) then Exit;
  if AType in [btLineX, btLineY] then
  begin
    SetLength(Result, 1);
    Result[0][0] := NaN;
    Result[0][1] := NaN;
    if AData.Count > 0 then Result[0][0] := NumOf(AData.Items[0]);
    if AData.Count > 1 then Result[0][1] := NumOf(AData.Items[1]);
    Exit;
  end;
  SetLength(Result, AData.Count);
  for i := 0 to AData.Count - 1 do
  begin
    Result[i][0] := NaN;
    Result[i][1] := NaN;
    it := AData.Items[i];
    if not (it is TJSONArray) then Continue;
    if it.Count > 0 then Result[i][0] := NumOf(it.Items[0]);
    if it.Count > 1 then Result[i][1] := NumOf(it.Items[1]);
  end;
end;

function TyBrushRangeCopy(const A: TTyBrushRange): TTyBrushRange;
begin
  Result := Copy(A);
end;

function TyBrushMergeJson(var AOpt: TTyBrushOpt; AObj: TJSONObject): Boolean;
var d: TJSONData; s: string;
begin
  Result := True;
  d := AObj.Find('brushType');
  if d <> nil then
  begin
    if d.JSONType = jtString then
    begin
      AOpt.BrushType := TyBrushTypeOf(d.AsString);
      { 'auto' and any other word: no renderer upstream; nothing here }
      if AOpt.BrushType = btNone then Result := False;
    end
    else if not JsTruthy(d) then AOpt.BrushType := btNone
    else Result := False;
  end;
  d := AObj.Find('brushMode');
  if d <> nil then AOpt.Multiple := not ((d.JSONType = jtString) and (d.AsString = 'single'));
  d := AObj.Find('transformable');
  if d <> nil then AOpt.Transformable := JsTruthy(d);
  d := AObj.Find('removeOnClick');
  if d <> nil then AOpt.RemoveOnClick := JsTruthy(d);
  d := AObj.Find('z');
  if d <> nil then AOpt.Z := NumOf(d);
  d := AObj.Find('brushStyle');
  if d is TJSONObject then MergeStyleJson(AOpt.Style, TJSONObject(d));
  d := AObj.Find('id');
  if (d <> nil) and IdText(d, s) then
  begin
    AOpt.HasId := True;
    AOpt.Id := s;
  end;
  d := AObj.Find('panelId');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    AOpt.HasPanel := True;
    AOpt.PanelId := d.AsString;
  end;
  d := AObj.Find('range');
  if d is TJSONArray then
  begin
    AOpt.HasRange := True;
    AOpt.Range := TyBrushRangeOfJson(AOpt.BrushType, d);
  end;
end;

function MergeStyle(const ABase, AOver: TTyBrushStyle): TTyBrushStyle;
begin
  Result := ABase;
  { a default the option set (Skin) is a value too [Batch 130] }
  if AOver.Fill.Written or (AOver.Fill.Skin <> '') then Result.Fill := AOver.Fill;
  if AOver.Stroke.Written or (AOver.Stroke.Skin <> '') then Result.Stroke := AOver.Stroke;
  if not IsNan(AOver.LineWidth) then Result.LineWidth := AOver.LineWidth;
  if not IsNan(AOver.Opacity) then Result.Opacity := AOver.Opacity;
end;

function TyBrushMergeOpt(const ABase, AOver: TTyBrushOpt): TTyBrushOpt;
begin
  Result := AOver;
  Result.Style := MergeStyle(ABase.Style, AOver.Style);
  if IsNan(AOver.Z) then Result.Z := ABase.Z;
  if not AOver.HasId then
  begin
    Result.HasId := ABase.HasId;
    Result.Id := ABase.Id;
  end;
  if not AOver.HasPanel then
  begin
    Result.HasPanel := ABase.HasPanel;
    Result.PanelId := ABase.PanelId;
  end;
  if not AOver.HasRange then
  begin
    Result.HasRange := ABase.HasRange;
    Result.Range := Copy(ABase.Range);
  end
  else
    Result.Range := Copy(AOver.Range);
end;

{ the keys a finder reads: <mainType>Index / Id / Name }
function FinderJsonOf(AObj: TJSONObject): string;
var
  o: TJSONObject;
  i: Integer;
  k: string;

  function EndsWith(const S, ATail: string): Boolean;
  begin
    Result := (Length(S) > Length(ATail))
      and (Copy(S, Length(S) - Length(ATail) + 1, Length(ATail)) = ATail);
  end;

begin
  Result := '';
  if AObj = nil then Exit;
  o := TJSONObject.Create;
  try
    for i := 0 to AObj.Count - 1 do
    begin
      k := AObj.Names[i];
      if k = 'panelId' then Continue;
      if EndsWith(k, 'Index') or EndsWith(k, 'Id') or EndsWith(k, 'Name') then
        o.Add(k, AObj.Items[i].Clone);
    end;
    if o.Count > 0 then Result := o.AsJSON;
  finally
    o.Free;
  end;
end;

function TyBrushSpecOf(ANode: TJSONData): TTyBrushSpec;
var
  o, st: TJSONObject;
  d: TJSONData;
  w: Double;
begin
  Result := Default(TTyBrushSpec);
  { BrushModel.defaultOption }
  Result.Base := Default(TTyBrushOpt);
  Result.Base.BrushType := btRect;
  Result.Base.Multiple := False;
  Result.Base.Transformable := True;
  Result.Base.RemoveOnClick := True;
  Result.Base.Z := 10000;
  { getItemStyle of (borderWidth 1, color, borderColor): fill, stroke,
    lineWidth -- the colours the skin's }
  Result.Base.Style := NoStyle;
  Result.Base.Style.LineWidth := 1;
  Result.ThrottleKind := btkFixRate;
  Result.ThrottleType := 'fixRate';
  Result.ThrottleDelay := 0;
  if not (ANode is TJSONObject) then Exit;
  o := TJSONObject(ANode);
  d := o.Find('brushType');
  if d <> nil then
  begin
    if d.JSONType = jtString then Result.Base.BrushType := TyBrushTypeOf(d.AsString)
    else if not JsTruthy(d) then Result.Base.BrushType := btNone;
  end;
  d := o.Find('brushMode');
  if (d <> nil) and (d.JSONType <> jtNull) then
    Result.Base.Multiple := not ((d.JSONType = jtString) and (d.AsString = 'single'));
  d := o.Find('transformable');
  if (d <> nil) and (d.JSONType <> jtNull) then Result.Base.Transformable := JsTruthy(d);
  d := o.Find('removeOnClick');
  if (d <> nil) and (d.JSONType <> jtNull) then Result.Base.RemoveOnClick := JsTruthy(d);
  d := o.Find('z');
  if (d <> nil) and (d.JSONType = jtNumber) then Result.Base.Z := d.AsFloat;
  d := o.Find('brushStyle');
  if d is TJSONObject then
  begin
    st := TJSONObject(d);
    InkOf(st.Find('color'), Result.Base.Style.Fill);
    InkOf(st.Find('borderColor'), Result.Base.Style.Stroke);
    d := st.Find('borderWidth');
    if d <> nil then
    begin
      w := NumOf(d);
      { getItemStyle leaves out a null; a non-number is no width }
      if d.JSONType <> jtNull then Result.Base.Style.LineWidth := w;
    end;
    d := st.Find('opacity');
    if (d <> nil) and (d.JSONType = jtNumber) then Result.Base.Style.Opacity := d.AsFloat;
  end;
  d := o.Find('throttleType');
  if d <> nil then
  begin
    if not JsTruthy(d) then
    begin
      Result.ThrottleKind := btkNone;
      Result.ThrottleType := '';
    end
    else
    begin
      if d.JSONType = jtString then Result.ThrottleType := d.AsString
      else Result.ThrottleType := '?';
      if Result.ThrottleType = 'debounce' then Result.ThrottleKind := btkDebounce
      else Result.ThrottleKind := btkFixRate;
    end;
  end;
  d := o.Find('throttleDelay');
  if d <> nil then
  begin
    if d.JSONType = jtNull then Result.ThrottleDelay := NaN
    else Result.ThrottleDelay := NumOf(d);
  end;
  Result.Finder := FinderJsonOf(o);
end;

{ generateBrushOption's base from the model }
function GenBase(const ASpec: TTyBrushSpec): TTyBrushOpt;
begin
  Result := ASpec.Base;
  Result.HasId := False;
  Result.Id := '';
  Result.HasPanel := False;
  Result.PanelId := '';
  Result.HasRange := False;
  Result.Range := nil;
end;

function TyBrushPaintOpt(const ASpec: TTyBrushSpec; ABrushOption: TJSONData): TTyBrushOpt;
begin
  Result := GenBase(ASpec);
  if ABrushOption is TJSONObject then
    TyBrushMergeJson(Result, TJSONObject(ABrushOption));
end;

procedure RangesOfJson(AType: TTyBrushType; AData: TJSONData; out ARanges: TTyBrushRangeArray);
var i: Integer;
begin
  ARanges := nil;
  if not (AData is TJSONArray) then Exit;
  SetLength(ARanges, AData.Count);
  for i := 0 to AData.Count - 1 do ARanges[i] := TyBrushRangeOfJson(AType, AData.Items[i]);
end;

function TyBrushAreaOfJson(const ASpec: TTyBrushSpec; AObj: TJSONObject;
  out AArea: TTyBrushArea): Boolean;
var d, e: TJSONData;
begin
  AArea := Default(TTyBrushArea);
  AArea.Opt := GenBase(ASpec);
  d := AObj.Find('brushType');
  { an area names its type (upstream asserts it) }
  if (d = nil) or (d.JSONType <> jtString) then Exit(False);
  if not TyBrushMergeJson(AArea.Opt, AObj) then Exit(False);
  if AArea.Opt.BrushType = btNone then Exit(False);
  d := AObj.Find('coordRange');
  if d is TJSONArray then
  begin
    AArea.HasCoordRange := True;
    AArea.CoordRange := TyBrushRangeOfJson(AArea.Opt.BrushType, d);
  end;
  d := AObj.Find('coordRanges');
  if d is TJSONArray then
  begin
    AArea.HasCoordRanges := True;
    RangesOfJson(AArea.Opt.BrushType, d, AArea.CoordRanges);
  end;
  d := AObj.Find('__rangeOffset');
  if d is TJSONObject then
  begin
    e := TJSONObject(d).Find('offset');
    AArea.HasOffset := e is TJSONArray;
    AArea.Offset := TyBrushRangeOfJson(AArea.Opt.BrushType, e);
    AArea.OffsetXY := TyBrushRangeOfJson(btRect, TJSONObject(d).Find('xyMinMax'));
  end;
  AArea.Finder := FinderJsonOf(AObj);
  Result := True;
end;

function TyBrushAreaOfOutput(const ASpec: TTyBrushSpec; const AOut: TTyBrushArea): TTyBrushArea;
var base: TTyBrushOpt;
begin
  Result := AOut;
  base := GenBase(ASpec);
  { merge(base, area): the output area writes brushType, panelId, range }
  Result.Opt := base;
  Result.Opt.BrushType := AOut.Opt.BrushType;
  Result.Opt.HasPanel := AOut.Opt.HasPanel;
  Result.Opt.PanelId := AOut.Opt.PanelId;
  Result.Opt.HasRange := AOut.Opt.HasRange;
  Result.Opt.Range := Copy(AOut.Opt.Range);
  Result.CoordRange := Copy(AOut.CoordRange);
  Result.Offset := Copy(AOut.Offset);
  Result.OffsetXY := Copy(AOut.OffsetXY);
end;

{ JSON.stringify of a number: NaN and the infinities are null }
function NumJson(A: Double): string;
begin
  if IsNan(A) or IsInfinite(A) then Result := 'null'
  else Result := TyJsNumberToString(A);
end;

function TyBrushRangeJson(const A: TTyBrushRange; ALine: Boolean): string;
var i: Integer;
begin
  if ALine then
  begin
    if Length(A) = 0 then Exit('[]');
    Exit('[' + NumJson(A[0][0]) + ',' + NumJson(A[0][1]) + ']');
  end;
  Result := '[';
  for i := 0 to High(A) do
  begin
    if i > 0 then Result := Result + ',';
    Result := Result + '[' + NumJson(A[i][0]) + ',' + NumJson(A[i][1]) + ']';
  end;
  Result := Result + ']';
end;

function JsonStr(const S: string): string;
var
  i: Integer;
  c: Char;
begin
  Result := '"';
  for i := 1 to Length(S) do
  begin
    c := S[i];
    case c of
      '"': Result := Result + '\"';
      '\': Result := Result + '\\';
      #8: Result := Result + '\b';
      #9: Result := Result + '\t';
      #10: Result := Result + '\n';
      #12: Result := Result + '\f';
      #13: Result := Result + '\r';
    else
      if Ord(c) < $20 then Result := Result + '\u' + LowerCase(IntToHex(Ord(c), 4))
      else Result := Result + c;
    end;
  end;
  Result := Result + '"';
end;

function TyBrushJsonStr(const S: string): string;
begin
  Result := JsonStr(S);
end;

function TyBrushAreasJson(const AAreas: TTyBrushAreaArray): string;
var
  i, k: Integer;
  ln: Boolean;
  a: TTyBrushArea;
begin
  Result := '[';
  for i := 0 to High(AAreas) do
  begin
    a := AAreas[i];
    ln := a.Opt.BrushType in [btLineX, btLineY];
    if i > 0 then Result := Result + ',';
    Result := Result + '{"brushType":' + JsonStr(TyBrushTypeName(a.Opt.BrushType));
    if a.Opt.HasPanel then Result := Result + ',"panelId":' + JsonStr(a.Opt.PanelId)
    else Result := Result + ',"panelId":null';
    Result := Result + ',"range":' + TyBrushRangeJson(a.Opt.Range, ln);
    if a.HasCoordRanges then
    begin
      Result := Result + ',"coordRanges":[';
      for k := 0 to High(a.CoordRanges) do
      begin
        if k > 0 then Result := Result + ',';
        Result := Result + TyBrushRangeJson(a.CoordRanges[k], ln);
      end;
      Result := Result + ']';
    end;
    if a.HasCoordRange then Result := Result + ',"coordRange":' + TyBrushRangeJson(a.CoordRange, ln);
    if a.HasOffset then
      Result := Result + ',"__rangeOffset":{"offset":' + TyBrushRangeJson(a.Offset, ln)
        + ',"xyMinMax":' + TyBrushRangeJson(a.OffsetXY, False) + '}';
    Result := Result + '}';
  end;
  Result := Result + ']';
end;

{ ==================== the geometry ==================== }

function TyBrushClip(const APoints: TTyBrushRange; const ARect: TTyXYWH): TTyBrushRange;
var
  i: Integer;
  x, y: Double;
begin
  SetLength(Result, Length(APoints));
  for i := 0 to High(APoints) do
  begin
    x := JMax(APoints[i][0], ARect.X);
    x := JMin(x, ARect.X + ARect.W);
    y := JMax(APoints[i][1], ARect.Y);
    y := JMin(y, ARect.Y + ARect.H);
    Result[i][0] := x;
    Result[i][1] := y;
  end;
end;

{ pointsToRect }
function PointsToRect(const APts: TTyBrushRange): TTyXYWH;
var xmin, ymin, xmax, ymax: Double;
begin
  xmin := JMin(APts[0][0], APts[1][0]);
  ymin := JMin(APts[0][1], APts[1][1]);
  xmax := JMax(APts[0][0], APts[1][0]);
  ymax := JMax(APts[0][1], APts[1][1]);
  Result.X := xmin;
  Result.Y := ymin;
  Result.W := xmax - xmin;
  Result.H := ymax - ymin;
end;

{ formatRectRange(x, y, x2, y2) }
function FormatRectRange(AX, AY, AX2, AY2: Double): TTyBrushRange;
begin
  SetLength(Result, 2);
  Result[0][0] := JMin(AX, AX2);
  Result[0][1] := JMax(AX, AX2);
  Result[1][0] := JMin(AY, AY2);
  Result[1][1] := JMax(AY, AY2);
end;

function TyBrushCreatingRange(AType: TTyBrushType; const ATrack: TTyBrushRange): TTyBrushRange;
var
  a, b: TTyBrushPair;
  i: Integer;
begin
  Result := nil;
  if Length(ATrack) = 0 then Exit;
  if AType = btPolygon then Exit(Copy(ATrack));
  { getTrackEnds }
  a := ATrack[0];
  b := ATrack[High(ATrack)];
  if AType = btRect then Exit(FormatRectRange(b[0], b[1], a[0], a[1]));
  if AType = btLineX then i := 0 else i := 1;
  SetLength(Result, 1);
  Result[0][0] := JMin(a[i], b[i]);
  Result[0][1] := JMax(a[i], b[i]);
end;

function TyBrushDrift(AType: TTyBrushType; const ARange: TTyBrushRange;
  APiece: TTyBrushPiece; ADX, ADY: Double): TTyBrushRange;
var
  rr: TTyBrushRange;
  seq: string;
  i: Integer;
  d: array[0..1] of Double;
begin
  if AType = btPolygon then
  begin
    Result := Copy(ARange);
    for i := 0 to High(Result) do
    begin
      Result[i][0] := Result[i][0] + ADX;
      Result[i][1] := Result[i][1] + ADY;
    end;
    Exit;
  end;
  { toRectRange }
  SetLength(rr, 2);
  case AType of
    btRect:
      begin
        if Length(ARange) < 2 then Exit(Copy(ARange));
        rr[0] := ARange[0];
        rr[1] := ARange[1];
      end;
    btLineX:
      begin
        if Length(ARange) < 1 then Exit(Copy(ARange));
        rr[0] := ARange[0];
        rr[1] := Pair(0, 100);
      end;
  else
    begin
      if Length(ARange) < 1 then Exit(Copy(ARange));
      rr[0] := Pair(0, 100);
      rr[1] := ARange[0];
    end;
  end;
  case APiece of
    bpMain: seq := 'nswe';
    bpW: seq := 'w';
    bpE: seq := 'e';
    bpN: seq := 'n';
    bpS: seq := 's';
    bpSE: seq := 'se';
    bpSW: seq := 'sw';
    bpNE: seq := 'ne';
  else
    seq := 'nw';
  end;
  d[0] := ADX;
  d[1] := ADY;
  { DIRECTION_MAP: w [0, 0], e [0, 1], n [1, 0], s [1, 1] }
  for i := 1 to Length(seq) do
    case seq[i] of
      'w': rr[0][0] := rr[0][0] + d[0];
      'e': rr[0][1] := rr[0][1] + d[0];
      'n': rr[1][0] := rr[1][0] + d[1];
      's': rr[1][1] := rr[1][1] + d[1];
    end;
  rr := FormatRectRange(rr[0][0], rr[1][0], rr[0][1], rr[1][1]);
  { fromRectRange }
  case AType of
    btRect: Result := rr;
    btLineX:
      begin
        SetLength(Result, 1);
        Result[0] := rr[0];
      end;
  else
    begin
      SetLength(Result, 1);
      Result[0] := rr[1];
    end;
  end;
end;

{ ==================== containment (zrender contain/) ==================== }

function TyBrushWindingLine(AX0, AY0, AX1, AY1, AX, AY: Double): Double;
var t, dir, xx: Double;
begin
  if ((AY > AY0) and (AY > AY1)) or ((AY < AY0) and (AY < AY1)) then Exit(0);
  if AY1 = AY0 then Exit(0);
  t := (AY - AY0) / (AY1 - AY0);
  if AY1 < AY0 then dir := 1 else dir := -1;
  if (t = 1) or (t = 0) then
  begin
    if AY1 < AY0 then dir := 0.5 else dir := -0.5;
  end;
  xx := t * (AX1 - AX0) + AX0;
  if xx = AX then Exit(Infinity);
  if xx > AX then Result := dir else Result := 0;
end;

function TyBrushLineContainStroke(AX0, AY0, AX1, AY1, ALineWidth, AX, AY: Double): Boolean;
var l, a, b, tmp, s: Double;
begin
  if ALineWidth = 0 then Exit(False);
  l := ALineWidth;
  if ((AY > AY0 + l) and (AY > AY1 + l)) or ((AY < AY0 - l) and (AY < AY1 - l))
    or ((AX > AX0 + l) and (AX > AX1 + l)) or ((AX < AX0 - l) and (AX < AX1 - l)) then
    Exit(False);
  if AX0 <> AX1 then
  begin
    a := (AY0 - AY1) / (AX0 - AX1);
    b := (AX0 * AY1 - AX1 * AY0) / (AX0 - AX1);
  end
  else
    Exit(Abs(AX - AX0) <= l / 2);
  tmp := a * AX - AY + b;
  s := tmp * tmp / (a * a + 1);
  Result := s <= l / 2 * l / 2;
end;

{ `|| 0`: NaN (and 0) is nought }
function OrZero(A: Double): Double;
begin
  if IsNan(A) then Result := 0 else Result := A;
end;

{ containPath over a rect's R command }
function RectPathContain(const R: TTyXYWH; AStroke: Boolean; ALineWidth, AX, AY: Double): Boolean;
var x0, y0, x1, y1, w: Double;
begin
  x0 := R.X;
  y0 := R.Y;
  x1 := x0 + R.W;
  y1 := y0 + R.H;
  if AStroke then
    Exit(TyBrushLineContainStroke(x0, y0, x1, y0, ALineWidth, AX, AY)
      or TyBrushLineContainStroke(x1, y0, x1, y1, ALineWidth, AX, AY)
      or TyBrushLineContainStroke(x1, y1, x0, y1, ALineWidth, AX, AY)
      or TyBrushLineContainStroke(x0, y1, x0, y0, ALineWidth, AX, AY));
  w := 0;
  w := w + TyBrushWindingLine(x1, y0, x1, y1, AX, AY);
  w := w + TyBrushWindingLine(x0, y1, x0, y0, AX, AY);
  Result := w <> 0;
end;

{ containPath over a polygon's M, L ... Z }
function PolyPathContain(const P: array of TTyPointF; AStroke: Boolean;
  ALineWidth, AX, AY: Double): Boolean;
var
  i: Integer;
  w, xi, yi, x0, y0: Double;
begin
  Result := False;
  if Length(P) < 2 then Exit;
  w := 0;
  x0 := P[0].X;
  y0 := P[0].Y;
  xi := x0;
  yi := y0;
  for i := 1 to High(P) do
  begin
    if AStroke then
    begin
      if TyBrushLineContainStroke(xi, yi, P[i].X, P[i].Y, ALineWidth, AX, AY) then Exit(True);
    end
    else
      w := w + OrZero(TyBrushWindingLine(xi, yi, P[i].X, P[i].Y, AX, AY));
    xi := P[i].X;
    yi := P[i].Y;
  end;
  { Z }
  if AStroke then
  begin
    if TyBrushLineContainStroke(xi, yi, x0, y0, ALineWidth, AX, AY) then Exit(True);
  end
  else
    w := w + TyBrushWindingLine(xi, yi, x0, y0, AX, AY);
  if AStroke then Exit(False);
  Result := w <> 0;
end;

{ BoundingRect.contain }
function BoxContain(AX, AY, AW, AH, PX, PY: Double): Boolean;
begin
  Result := (PX >= AX) and (PX <= AX + AW) and (PY >= AY) and (PY <= AY + AH);
end;

{ ==================== the controller ==================== }

constructor TTyBrushController.Create;
begin
  inherited Create;
  Opt := TyBrushDefaultOpt;
  Creating := -1;
  CreatingPanel := -1;
  Inc(GBrushUid);
  Uid := GBrushUid;
  Xf[0] := 1;
  Xf[1] := 0;
  Xf[2] := 0;
  Xf[3] := 1;
  Xf[4] := 0;
  Xf[5] := 0;
  HasInv := False;
end;

{ isNotAroundZero }
function NotAroundZero(A: Double): Boolean;
const cEps = 5e-5;
begin
  Result := (A > cEps) or (A < -cEps);
end;

procedure TTyBrushController.Mount(AX, AY, ARotation: Double);
var
  st, ct, aa, ac, atx, ab, ad, aty, det: Double;
  m: TFPUExceptionMask;
begin
  m := MaskFP;
  try
    { getLocalTransform: the scale (1), no skew, no origin; then
      `rotation && matrix.rotate(m, m, rotation)`; then the translation }
    Xf[0] := 1;
    Xf[1] := 0;
    Xf[2] := 0;
    Xf[3] := 1;
    Xf[4] := 0;
    Xf[5] := 0;
    if (ARotation <> 0) and not IsNan(ARotation) then
    begin
      aa := Xf[0];
      ac := Xf[2];
      atx := Xf[4];
      ab := Xf[1];
      ad := Xf[3];
      aty := Xf[5];
      st := TyJsSin(ARotation);
      ct := TyJsCos(ARotation);
      Xf[0] := aa * ct + ab * st;
      Xf[1] := -aa * st + ab * ct;
      Xf[2] := ac * ct + ad * st;
      Xf[3] := -ac * st + ct * ad;
      Xf[4] := ct * (atx - 0) + st * (aty - 0) + 0;
      Xf[5] := ct * (aty - 0) - st * (atx - 0) + 0;
    end;
    Xf[4] := Xf[4] + (0 + AX);
    Xf[5] := Xf[5] + (0 + AY);
    { updateTransform: a group that needs no transform has no inverse; one
      that does inverts it (matrix.invert; a singular one keeps the
      identity matrix.create gave) }
    HasInv := NotAroundZero(ARotation) or NotAroundZero(AX) or NotAroundZero(AY);
    if HasInv then
    begin
      Inv[0] := 1;
      Inv[1] := 0;
      Inv[2] := 0;
      Inv[3] := 1;
      Inv[4] := 0;
      Inv[5] := 0;
      aa := Xf[0];
      ac := Xf[2];
      atx := Xf[4];
      ab := Xf[1];
      ad := Xf[3];
      aty := Xf[5];
      det := aa * ad - ab * ac;
      if (det <> 0) and not IsNan(det) then
      begin
        det := 1.0 / det;
        Inv[0] := ad * det;
        Inv[1] := -ab * det;
        Inv[2] := -ac * det;
        Inv[3] := aa * det;
        Inv[4] := (ac * aty - ad * atx) * det;
        Inv[5] := (ab * atx - aa * aty) * det;
      end;
    end;
  finally
    UnmaskFP(m);
  end;
end;

procedure TTyBrushController.ToLocal(AX, AY: Double; out LX, LY: Double);
var m: TFPUExceptionMask;
begin
  if not HasInv then
  begin
    LX := AX;
    LY := AY;
    Exit;
  end;
  m := MaskFP;
  try
    { vector.applyTransform }
    LX := Inv[0] * AX + Inv[2] * AY + Inv[4];
    LY := Inv[1] * AX + Inv[3] * AY + Inv[5];
  finally
    UnmaskFP(m);
  end;
end;

procedure TTyBrushController.ToLocalDelta(ADX, ADY: Double; out LX, LY: Double);
var dx, dy, zx, zy: Double;
begin
  ToLocal(ADX, ADY, dx, dy);
  ToLocal(0, 0, zx, zy);
  LX := dx - zx;
  LY := dy - zy;
end;

function TTyBrushController.PieceCursor(APiece: TTyBrushPiece; ATransformable: Boolean): string;
var
  t: TTyBrushMat;
  m: TFPUExceptionMask;

  { graphic.transformDirection }
  function Dir(const ADir: string): string;
  var hBase, vBase, vx, vy, gx, gy: Double;
  begin
    if (t[4] = 0) or (t[5] = 0) or (t[0] = 0) then hBase := 1
    else hBase := Abs(2 * t[4] / t[0]);
    if (t[4] = 0) or (t[5] = 0) or (t[2] = 0) then vBase := 1
    else vBase := Abs(2 * t[4] / t[2]);
    vx := 0;
    vy := 0;
    if ADir = 'left' then vx := -hBase else if ADir = 'right' then vx := hBase;
    if ADir = 'top' then vy := -vBase else if ADir = 'bottom' then vy := vBase;
    gx := t[0] * vx + t[2] * vy + t[4];
    gy := t[1] * vx + t[3] * vy + t[5];
    if Abs(gx) > Abs(gy) then
    begin
      if gx > 0 then Result := 'right' else Result := 'left';
    end
    else if gy > 0 then Result := 'bottom'
    else Result := 'top';
  end;

  { getGlobalDirection1: w e n s through the transform }
  function G1(ALocal: Char): Char;
  var d: string;
  begin
    case ALocal of
      'w': d := Dir('left');
      'e': d := Dir('right');
      'n': d := Dir('top');
    else
      d := Dir('bottom');
    end;
    if d = 'left' then Result := 'w'
    else if d = 'right' then Result := 'e'
    else if d = 'top' then Result := 'n'
    else Result := 's';
  end;

  { CURSOR_MAP; a pair upstream's map does not hold reads 'undefined' }
  function CursorOf(const AName: string): string;
  begin
    if (AName = 'w') or (AName = 'e') then Result := 'ew'
    else if (AName = 'n') or (AName = 's') then Result := 'ns'
    else if (AName = 'ne') or (AName = 'sw') then Result := 'nesw'
    else if (AName = 'nw') or (AName = 'se') then Result := 'nwse'
    else Result := 'undefined';
    Result := Result + '-resize';
  end;

var
  seq, g: string;
  c: Char;
begin
  if APiece = bpMain then
  begin
    if ATransformable then Exit('move');
    Exit('default');
  end;
  if not ATransformable then Exit('');
  m := MaskFP;
  try
    { graphic.getTransform(group): the identity times the local transform }
    t[0] := Xf[0] * 1 + Xf[2] * 0;
    t[1] := Xf[1] * 1 + Xf[3] * 0;
    t[2] := Xf[0] * 0 + Xf[2] * 1;
    t[3] := Xf[1] * 0 + Xf[3] * 1;
    t[4] := Xf[0] * 0 + Xf[2] * 0 + Xf[4];
    t[5] := Xf[1] * 0 + Xf[3] * 0 + Xf[5];
    seq := TyBrushPieceName(APiece);
    if Length(seq) = 1 then Exit(CursorOf(G1(seq[1])));
    { getGlobalDirection2: an east or west first is turned round }
    g := G1(seq[1]) + G1(seq[2]);
    if (g[1] = 'e') or (g[1] = 'w') then
    begin
      c := g[1];
      g[1] := g[2];
      g[2] := c;
    end;
    Result := CursorOf(g);
  finally
    UnmaskFP(m);
  end;
end;

function TTyBrushController.IndexOf(ASerial: Integer): Integer;
var i: Integer;
begin
  for i := 0 to High(Covers) do
    if Covers[i].Serial = ASerial then Exit(i);
  Result := -1;
end;

function TTyBrushController.GroupOrder: TTyIntegerArray;
var
  i, j, t: Integer;
begin
  SetLength(Result, Length(Covers));
  for i := 0 to High(Covers) do Result[i] := i;
  { by serial: the order the group holds them }
  for i := 1 to High(Result) do
  begin
    t := Result[i];
    j := i - 1;
    while (j >= 0) and (Covers[Result[j]].Serial > Covers[t].Serial) do
    begin
      Result[j + 1] := Result[j];
      Dec(j);
    end;
    Result[j + 1] := t;
  end;
end;

procedure TTyBrushController.EnableBrush(const AOpt: TTyBrushOpt);
begin
  { this._brushType && _doDisableBrush }
  if Enabled then
  begin
    Enabled := False;
    Auto := False;
    Opt := TyBrushDefaultOpt;
  end;
  if AOpt.BrushType = btNone then Exit;
  Enabled := True;
  { merge(clone(DEFAULT_BRUSH_OPT), brushOption, true) }
  Opt := TyBrushMergeOpt(TyBrushDefaultOpt, AOpt);
end;

procedure TTyBrushController.EnableAuto(const AOpt: TTyBrushOpt);
var o: TTyBrushOpt;
begin
  o := AOpt;
  { any type turns it on; the covers take their panels' }
  o.BrushType := btRect;
  EnableBrush(o);
  Auto := True;
end;

procedure TTyBrushController.SetPanels(const APanels: array of TTyBrushPanel;
  AHasPanels: Boolean);
var i: Integer;
begin
  HasPanels := AHasPanels and (Length(APanels) > 0);
  SetLength(Panels, 0);
  if not HasPanels then Exit;
  SetLength(Panels, Length(APanels));
  for i := 0 to High(APanels) do Panels[i] := APanels[i];
end;

function TTyBrushController.PanelOfCover(AIndex: Integer): Integer;
var i: Integer;
begin
  if not HasPanels then Exit(-2);
  if not Covers[AIndex].Opt.HasPanel then Exit(-2);
  { panels[panelId]: the dictionary's entry -- the last of a repeated id }
  Result := -1;
  for i := 0 to High(Panels) do
    if Panels[i].Id = Covers[AIndex].Opt.PanelId then Result := i;
end;

function TTyBrushController.PanelAt(AX, AY: Double): Integer;
var i: Integer;
begin
  if not HasPanels then Exit(-2);
  Result := -1;
  { each panel asked; the last that takes the point -- unless what the
    pointer is over is another coordinate system's (isTargetByCursor's
    onIrrelevantElement) [Batch 127] }
  for i := 0 to High(Panels) do
    if BoxContain(Panels[i].Rect.X, Panels[i].Rect.Y, Panels[i].Rect.W,
      Panels[i].Rect.H, AX, AY)
      and not (Assigned(IsIrrelevant) and IsIrrelevant(Panels[i], AX, AY)) then Result := i;
end;

function TTyBrushController.ClipByPanel(AIndex: Integer;
  const APoints: TTyBrushRange): TTyBrushRange;
var p: Integer;
begin
  p := PanelOfCover(AIndex);
  if p >= 0 then Result := TyBrushClip(APoints, Panels[p].Rect)
  else Result := Copy(APoints);
end;

function TTyBrushController.NewCover(const AOpt: TTyBrushOpt): Integer;
var c: TTyBrushCover;
begin
  c := Default(TTyBrushCover);
  c.Serial := FNextSerial;
  Inc(FNextSerial);
  c.Opt := AOpt;
  c.Live := False;
  c.Closed := False;
  Result := Length(Covers);
  SetLength(Covers, Result + 1);
  Covers[Result] := c;
end;

procedure TTyBrushController.EndCreating(AIndex: Integer);
begin
  { a polygon's Polyline becomes a Polygon (draggable) }
  if Covers[AIndex].Opt.BrushType = btPolygon then Covers[AIndex].Closed := True;
end;

procedure TTyBrushController.UpdateCommon(AIndex: Integer);
begin
  Covers[AIndex].Live := True;
end;

procedure TTyBrushController.UpdateShape(AIndex: Integer);
var
  o: TTyBrushOpt;
  rr, pts: TTyBrushRange;
  lw, hs, x, y, xa, ya, x2, y2, x2a, y2a, w, h, wa, ha: Double;
  p, i: Integer;
  other: TTyBrushPair;

  procedure Put(APiece: TTyBrushPiece; AX, AY, AW, AH: Double);
  var q: TTyBrushRange; r: TTyXYWH;
  begin
    if not TyBrushHasPiece(o.BrushType, APiece) then Exit;
    SetLength(q, 2);
    q[0] := Pair(AX, AY);
    q[1] := Pair(AX + AW, AY + AH);
    r := PointsToRect(ClipByPanel(AIndex, q));
    if APiece = bpMain then Covers[AIndex].Main := r
    else Covers[AIndex].Handle[APiece] := r;
  end;

begin
  o := Covers[AIndex].Opt;
  if o.BrushType = btPolygon then
  begin
    pts := ClipByPanel(AIndex, o.Range);
    SetLength(Covers[AIndex].Points, Length(pts));
    for i := 0 to High(pts) do
    begin
      Covers[AIndex].Points[i].X := pts[i][0];
      Covers[AIndex].Points[i].Y := pts[i][1];
    end;
    Exit;
  end;
  if o.BrushType = btRect then
  begin
    if Length(o.Range) < 2 then Exit;
    rr := Copy(o.Range, 0, 2);
  end
  else
  begin
    if Length(o.Range) < 1 then Exit;
    { the line's other extent: the panel's, or the canvas' }
    p := PanelOfCover(AIndex);
    if o.BrushType = btLineX then i := 0 else i := 1;
    if p >= 0 then
    begin
      if i = 1 then other := Pair(Panels[p].Rect.X, Panels[p].Rect.X + Panels[p].Rect.W)
      else other := Pair(Panels[p].Rect.Y, Panels[p].Rect.Y + Panels[p].Rect.H);
    end
    else if i = 0 then other := Pair(0, CanvasH)
    else other := Pair(0, CanvasW);
    SetLength(rr, 2);
    if i = 0 then
    begin
      rr[0] := o.Range[0];
      rr[1] := other;
    end
    else
    begin
      rr[0] := other;
      rr[1] := o.Range[0];
    end;
  end;
  { updateBaseRect }
  lw := o.Style.LineWidth;
  if IsNan(lw) or (lw = 0) then lw := 0;
  hs := JMax(lw, TyBrushMinResizeLineWidth);
  x := rr[0][0];
  y := rr[1][0];
  xa := x - lw / 2;
  ya := y - lw / 2;
  x2 := rr[0][1];
  y2 := rr[1][1];
  x2a := x2 - hs + lw / 2;
  y2a := y2 - hs + lw / 2;
  w := x2 - x;
  h := y2 - y;
  wa := w + lw;
  ha := h + lw;
  Put(bpMain, x, y, w, h);
  if o.Transformable then
  begin
    Put(bpW, xa, ya, hs, ha);
    Put(bpE, x2a, ya, hs, ha);
    Put(bpN, xa, ya, wa, hs);
    Put(bpS, xa, y2a, wa, hs);
    Put(bpNW, xa, ya, hs, hs);
    Put(bpNE, x2a, ya, hs, hs);
    Put(bpSW, xa, y2a, hs, hs);
    Put(bpSE, x2a, y2a, hs, hs);
  end;
end;

procedure TTyBrushController.UpdateCovers(const AConfigs: array of TTyBrushOpt);
var
  base: TTyBrushOpt;
  cfg: TTyBrushOptArray;
  oldC, newC: TTyBrushCoverArray;
  newKeys: array of string;
  newMap: array of array of Integer;
  keyList: array of string;
  i, j, k, n, oldIdx: Integer;
  have: array of Boolean;
  key: string;
  m: TFPUExceptionMask;

  function KeyOf(const AO: TTyBrushOpt; AIndex: Integer): string;
  begin
    if AO.HasId then Result := AO.Id
    else Result := #0'-brush-index-' + IntToStr(AIndex);
    Result := Result + '-' + TyBrushTypeName(AO.BrushType);
  end;

  function KeyIndex(const AKey: string): Integer;
  var q: Integer;
  begin
    for q := 0 to High(keyList) do
      if keyList[q] = AKey then Exit(q);
    Result := -1;
  end;

  procedure Place(ANew, AOld: Integer);
  var ci: Integer;
  begin
    { the cover being drawn is not touched }
    if (AOld >= 0) and (oldC[AOld].Serial = Creating) and (Creating >= 0) then
    begin
      newC[ANew] := oldC[AOld];
      have[ANew] := True;
      Exit;
    end;
    if AOld >= 0 then
    begin
      newC[ANew] := oldC[AOld];
      newC[ANew].Opt := cfg[ANew];
    end
    else
    begin
      newC[ANew] := Default(TTyBrushCover);
      newC[ANew].Serial := FNextSerial;
      Inc(FNextSerial);
      newC[ANew].Opt := cfg[ANew];
      { endCreating }
      if cfg[ANew].BrushType = btPolygon then newC[ANew].Closed := True;
    end;
    have[ANew] := True;
    { updateCoverAfterCreation, on the new list }
    Covers := newC;
    ci := ANew;
    UpdateCommon(ci);
    UpdateShape(ci);
    newC := Covers;
  end;

begin
  m := MaskFP;
  try
    { the 6.1 dist merges every config over DEFAULT_BRUSH_OPT, not over the
      painting option (the source has since taken this._brushOption first):
      a cover laid from a bare config -- a parallel axis' from its
      intervals -- takes the default style [Batch 130] }
    base := TyBrushDefaultOpt;
    SetLength(cfg, Length(AConfigs));
    for i := 0 to High(AConfigs) do cfg[i] := TyBrushMergeOpt(base, AConfigs[i]);
    oldC := Covers;
    SetLength(newC, Length(cfg));
    SetLength(have, Length(cfg));
    { DataDiffer: the new keys' index lists, in first-seen order }
    SetLength(newKeys, Length(cfg));
    keyList := nil;
    newMap := nil;
    for i := 0 to High(cfg) do
    begin
      newKeys[i] := KeyOf(cfg[i], i);
      k := KeyIndex(newKeys[i]);
      if k < 0 then
      begin
        k := Length(keyList);
        SetLength(keyList, k + 1);
        SetLength(newMap, k + 1);
        keyList[k] := newKeys[i];
        newMap[k] := nil;
      end;
      n := Length(newMap[k]);
      SetLength(newMap[k], n + 1);
      newMap[k][n] := i;
    end;
    { the old ones in order: an update, or a removal }
    for oldIdx := 0 to High(oldC) do
    begin
      key := KeyOf(oldC[oldIdx].Opt, oldIdx);
      k := KeyIndex(key);
      if (k >= 0) and (Length(newMap[k]) > 0) then
      begin
        j := newMap[k][0];
        newMap[k] := Copy(newMap[k], 1, MaxInt);
        Place(j, oldIdx);
      end;
      { a removed cover leaves the group (the one being drawn stays) }
    end;
    { the rest added, in the new keys' order }
    for k := 0 to High(keyList) do
      for j := 0 to High(newMap[k]) do
        Place(newMap[k][j], -1);
    Covers := newC;
    { the cover being drawn, if the diff kept it, is still it }
    if (Creating >= 0) and (IndexOf(Creating) < 0) then Creating := -1;
  finally
    UnmaskFP(m);
  end;
end;

function TTyBrushController.ClearCovers: Boolean;
begin
  Result := Length(Covers) > 0;
  Covers := nil;
end;

function TTyBrushController.Trigger(AIsEnd, ARemoveOnClick: Boolean): TTyBrushTrigger;
var i: Integer;
begin
  Result := Default(TTyBrushTrigger);
  Result.Fired := True;
  Result.IsEnd := AIsEnd;
  Result.RemoveOnClick := ARemoveOnClick;
  SetLength(Result.Areas, Length(Covers));
  for i := 0 to High(Covers) do
  begin
    Result.Areas[i] := Default(TTyBrushArea);
    Result.Areas[i].Opt.BrushType := Covers[i].Opt.BrushType;
    { panelId: null for the global panel }
    Result.Areas[i].Opt.HasPanel := Covers[i].Opt.HasPanel;
    Result.Areas[i].Opt.PanelId := Covers[i].Opt.PanelId;
    Result.Areas[i].Opt.HasRange := True;
    Result.Areas[i].Opt.Range := Copy(Covers[i].Opt.Range);
    Result.Areas[i].Opt.Z := NaN;
    Result.Areas[i].Opt.Style := NoStyle;
  end;
end;

function TTyBrushController.ShouldShowCover: Boolean;
var dx, dy: Double;
begin
  if Length(Track) = 0 then Exit(False);
  dx := Track[High(Track)].X - Track[0].X;
  dy := Track[High(Track)].Y - Track[0].Y;
  Result := Power(dx * dx + dy * dy, 0.5) > TyBrushUnselectThreshold;
end;

function TTyBrushController.UpdateByMouse(AX, AY: Double; AIsEnd: Boolean): TTyBrushTrigger;
var
  ci, n, i: Integer;
  o: TTyBrushOpt;
  tr: TTyBrushRange;
begin
  Result := Default(TTyBrushTrigger);
  n := Length(Track);
  SetLength(Track, n + 1);
  Track[n].X := AX;
  Track[n].Y := AY;
  ci := -1;
  if Creating >= 0 then ci := IndexOf(Creating);
  if ShouldShowCover or (Creating >= 0) then
  begin
    if (CreatingPanel <> -1) and (Creating < 0) then
    begin
      if not Opt.Multiple then ClearCovers;
      o := Opt;
      o.HasId := False;
      o.Id := '';
      o.HasRange := False;
      o.Range := nil;
      o.HasPanel := CreatingPanel >= 0;
      if o.HasPanel then o.PanelId := Panels[CreatingPanel].Id
      else o.PanelId := '';
      { determineBrushType: 'auto' is the panel's default [Batch 127] }
      if Auto and o.HasPanel then o.BrushType := Panels[CreatingPanel].DefaultType;
      ci := NewCover(o);
      Creating := Covers[ci].Serial;
    end;
    if (Creating >= 0) and (ci >= 0) then
    begin
      SetLength(tr, Length(Track));
      for i := 0 to High(Track) do
      begin
        tr[i][0] := Track[i].X;
        tr[i][1] := Track[i].Y;
      end;
      Covers[ci].Opt.Range := TyBrushCreatingRange(Covers[ci].Opt.BrushType,
        ClipByPanel(ci, tr));
      Covers[ci].Opt.HasRange := True;
      if AIsEnd then
      begin
        EndCreating(ci);
        UpdateCommon(ci);
      end;
      UpdateShape(ci);
      Result := Trigger(AIsEnd, False);
    end;
  end
  else if AIsEnd and not Opt.Multiple and Opt.RemoveOnClick then
  begin
    { a tiny drag in a panel clears the covers -- when there were some }
    if (PanelAt(AX, AY) <> -1) and ClearCovers then Result := Trigger(True, True);
  end;
end;

function TTyBrushController.HandleDragEnd(AX, AY: Double): TTyBrushTrigger;
begin
  Result := Default(TTyBrushTrigger);
  if not Dragging then Exit;
  Result := UpdateByMouse(AX, AY, True);
  Dragging := False;
  Track := nil;
  Creating := -1;
end;

function TTyBrushController.MouseDown(AX, AY: Double; ATargetDraggable: Boolean): TTyBrushTrigger;
var m: TFPUExceptionMask;
begin
  Result := Default(TTyBrushTrigger);
  if not Enabled then Exit;
  { transformCoordToLocal [Batch 130] }
  ToLocal(AX, AY, AX, AY);
  m := MaskFP;
  try
    if Dragging then
    begin
      { a press while drawing: the release was lost }
      Result := HandleDragEnd(AX, AY);
      Exit;
    end;
    if ATargetDraggable then Exit;
    Creating := -1;
    CreatingPanel := PanelAt(AX, AY);
    if CreatingPanel <> -1 then
    begin
      Dragging := True;
      SetLength(Track, 1);
      Track[0].X := AX;
      Track[0].Y := AY;
    end;
  finally
    UnmaskFP(m);
  end;
end;

function TTyBrushController.MouseMove(AX, AY: Double): TTyBrushTrigger;
var m: TFPUExceptionMask;
begin
  Result := Default(TTyBrushTrigger);
  if not Enabled or not Dragging then Exit;
  ToLocal(AX, AY, AX, AY);
  m := MaskFP;
  try
    Result := UpdateByMouse(AX, AY, False);
  finally
    UnmaskFP(m);
  end;
end;

function TTyBrushController.MouseUp(AX, AY: Double): TTyBrushTrigger;
var m: TFPUExceptionMask;
begin
  Result := Default(TTyBrushTrigger);
  if not Enabled then Exit;
  ToLocal(AX, AY, AX, AY);
  m := MaskFP;
  try
    Result := HandleDragEnd(AX, AY);
  finally
    UnmaskFP(m);
  end;
end;

function TTyBrushController.Crosshair(AX, AY: Double): Boolean;
var
  p, i: Integer;
  lx, ly, cx, cy: Double;
  m: TFPUExceptionMask;
begin
  Result := False;
  if not Enabled then Exit;
  { not outside the canvas }
  if (AX < 0) or (AX > CanvasW) or (AY < 0) or (AY > CanvasH) then Exit;
  { the local point [Batch 130]; Path.contain turns the point it is given
    local once more -- the local one, here }
  ToLocal(AX, AY, lx, ly);
  ToLocal(lx, ly, cx, cy);
  m := MaskFP;
  try
    p := PanelAt(lx, ly);
    if not Dragging then
      for i := 0 to High(Covers) do
        if (p <> -1) and ((p = -2) or (Covers[i].Opt.HasPanel
          and (Covers[i].Opt.PanelId = Panels[p].Id)))
          and MainContains(i, cx, cy) then
          Exit(False);
    Result := p <> -1;
  finally
    UnmaskFP(m);
  end;
end;

function TTyBrushController.Drift(ASerial: Integer; APiece: TTyBrushPiece;
  ADX, ADY: Double): TTyBrushTrigger;
var
  i: Integer;
  m: TFPUExceptionMask;
begin
  Result := Default(TTyBrushTrigger);
  i := IndexOf(ASerial);
  if i < 0 then Exit;
  { toLocalDelta [Batch 130] }
  if HasInv then ToLocalDelta(ADX, ADY, ADX, ADY);
  m := MaskFP;
  try
    Covers[i].Opt.Range := TyBrushDrift(Covers[i].Opt.BrushType, Covers[i].Opt.Range,
      APiece, ADX, ADY);
    UpdateCommon(i);
    UpdateShape(i);
    Result := Trigger(False, False);
  finally
    UnmaskFP(m);
  end;
end;

function TTyBrushController.DragEnd(ASerial: Integer): TTyBrushTrigger;
begin
  Result := Default(TTyBrushTrigger);
  if IndexOf(ASerial) < 0 then Exit;
  Result := Trigger(True, False);
end;

function TTyBrushController.PieceSilent(AIndex: Integer; APiece: TTyBrushPiece): Boolean;
begin
  { created silent; updateCommon: silent when not transformable }
  Result := not Covers[AIndex].Live or not Covers[AIndex].Opt.Transformable;
  if APiece <> bpMain then
    Result := Result or not TyBrushHasPiece(Covers[AIndex].Opt.BrushType, APiece);
end;

{ the style's own reading: a stroke that is not 'none' with a width over
  nought; a fill that is not 'none'; Path's defaults where unset (width 1) }
procedure StyleFlags(const AStyle: TTyBrushStyle; out AStroke, AFill: Boolean;
  out ALineWidth: Double);
begin
  ALineWidth := AStyle.LineWidth;
  if IsNan(ALineWidth) then ALineWidth := 1;
  AStroke := not (AStyle.Stroke.Written and (AStyle.Stroke.Text = 'none')) and (ALineWidth > 0);
  AFill := not (AStyle.Fill.Written and (AStyle.Fill.Text = 'none'));
end;

function TTyBrushController.MainContains(AIndex: Integer; AX, AY: Double): Boolean;
const cThreshold = 5;
var
  stroke, fill: Boolean;
  lw, w, bx, by, bw, bh, x1, y1: Double;
  i: Integer;
  c: TTyBrushCover;
  m: TFPUExceptionMask;
begin
  Result := False;
  c := Covers[AIndex];
  m := MaskFP;
  try
    StyleFlags(c.Opt.Style, stroke, fill, lw);
    { the path's own rect }
    if c.Opt.BrushType = btPolygon then
    begin
      if Length(c.Points) = 0 then Exit;
      bx := c.Points[0].X;
      by := c.Points[0].Y;
      x1 := bx;
      y1 := by;
      for i := 1 to High(c.Points) do
      begin
        bx := Math.Min(bx, c.Points[i].X);
        by := Math.Min(by, c.Points[i].Y);
        x1 := Math.Max(x1, c.Points[i].X);
        y1 := Math.Max(y1, c.Points[i].Y);
      end;
      bw := x1 - bx;
      bh := y1 - by;
    end
    else
    begin
      bx := Math.Min(c.Main.X, c.Main.X + c.Main.W);
      by := Math.Min(c.Main.Y, c.Main.Y + c.Main.H);
      bw := Math.Max(c.Main.X, c.Main.X + c.Main.W) - bx;
      bh := Math.Max(c.Main.Y, c.Main.Y + c.Main.H) - by;
    end;
    { grown by the stroke }
    if stroke then
    begin
      w := lw;
      if not fill then w := Math.Max(w, cThreshold);
      bw := bw + w / 1;
      bh := bh + w / 1;
      bx := bx - w / 1 / 2;
      by := by - w / 1 / 2;
    end;
    if not BoxContain(bx, by, bw, bh, AX, AY) then Exit;
    if stroke then
    begin
      w := lw;
      if not fill then w := Math.Max(w, cThreshold);
      if c.Opt.BrushType = btPolygon then
      begin
        if PolyPathContain(c.Points, True, w / 1, AX, AY) then Exit(True);
      end
      else if RectPathContain(c.Main, True, w / 1, AX, AY) then Exit(True);
    end;
    if fill then
    begin
      if c.Opt.BrushType = btPolygon then Result := PolyPathContain(c.Points, False, 0, AX, AY)
      else Result := RectPathContain(c.Main, False, 0, AX, AY);
    end;
  finally
    UnmaskFP(m);
  end;
end;

function TTyBrushController.PieceAt(AX, AY: Double; out AIndex: Integer;
  out APiece: TTyBrushPiece): Boolean;
var
  ord_: TTyIntegerArray;
  q, i: Integer;
  p: TTyBrushPiece;
  r: TTyXYWH;
  bx, by, bw, bh: Double;
  m: TFPUExceptionMask;
begin
  Result := False;
  AIndex := -1;
  APiece := bpMain;
  ord_ := GroupOrder;
  { the pieces' own inverse is the group's [Batch 130] }
  ToLocal(AX, AY, AX, AY);
  m := MaskFP;
  try
    for q := High(ord_) downto 0 do
    begin
      i := ord_[q];
      { the children over the main shape: the last added on top }
      for p := bpNW downto bpW do
      begin
        if PieceSilent(i, p) then Continue;
        r := Covers[i].Handle[p];
        { no stroke, the default fill: the path's rect, then its winding }
        bx := Math.Min(r.X, r.X + r.W);
        by := Math.Min(r.Y, r.Y + r.H);
        bw := Math.Max(r.X, r.X + r.W) - bx;
        bh := Math.Max(r.Y, r.Y + r.H) - by;
        if BoxContain(bx, by, bw, bh, AX, AY) and RectPathContain(r, False, 0, AX, AY) then
        begin
          AIndex := i;
          APiece := p;
          Exit(True);
        end;
      end;
      if not PieceSilent(i, bpMain) and MainContains(i, AX, AY) then
      begin
        AIndex := i;
        APiece := bpMain;
        Exit(True);
      end;
    end;
  finally
    UnmaskFP(m);
  end;
end;

{ ==================== the parallel axes' area select [Batch 130] ==================== }

function TyParallelSelectStyleOf(AAxis: TJSONData): TTyParallelSelectStyle;
var
  o: TJSONObject;
  d: TJSONData;

  { a key written: a number (or, for a colour, a string) is taken; null or
    another type leaves the cover's default }
  function Num(const AKey: string; ADefault: Double): Double;
  var v: TJSONData;
  begin
    if o = nil then Exit(ADefault);
    v := o.Find(AKey);
    if v = nil then Exit(ADefault);
    if v.JSONType = jtNumber then Result := v.AsFloat
    else Result := NaN;
  end;

  procedure Ink(const AKey: string; var AInk: TTyBrushInk);
  var v: TJSONData;
  begin
    if o = nil then Exit;
    v := o.Find(AKey);
    if (v <> nil) and (v.JSONType = jtString) then
    begin
      AInk.Written := True;
      AInk.Text := v.AsString;
    end;
  end;

begin
  Result := Default(TTyParallelSelectStyle);
  Result.Style := NoStyle;
  o := nil;
  if AAxis is TJSONObject then
  begin
    d := TJSONObject(AAxis).Find('areaSelectStyle');
    if d is TJSONObject then o := TJSONObject(d);
  end;
  Result.Width := Num('width', TyParallelSelectWidth);
  if IsNan(Result.Width) then Result.Width := TyParallelSelectWidth;
  Result.Style.LineWidth := Num('borderWidth', TyParallelSelectBorderWidth);
  Result.Style.Opacity := Num('opacity', TyParallelSelectOpacity);
  Ink('color', Result.Style.Fill);
  Ink('borderColor', Result.Style.Stroke);
end;

function TyParallelBrushPanelRect(AE0, AE1, AWidth: Double): TTyXYWH;
const cTenth: Double = 0.1;
var
  len, extra: Double;
  m: TFPUExceptionMask;

  { new BoundingRect: a negative size turned over }
  procedure Norm(var R: TTyXYWH);
  begin
    if R.W < 0 then
    begin
      R.X := R.X + R.W;
      R.W := -R.W;
    end;
    if R.H < 0 then
    begin
      R.Y := R.Y + R.H;
      R.H := -R.H;
    end;
  end;

begin
  m := MaskFP;
  try
    len := AE1 - AE0;
    extra := JMin(30, Abs(len) * cTenth);
    Result.X := AE0;
    Result.Y := -AWidth / 2;
    Result.W := len;
    Result.H := AWidth;
    Norm(Result);
    Result.X := Result.X - extra;
    Result.W := Result.W + 2 * extra;
    { makeRectPanelClipPath / makeRectIsTargetByCursor normalise again }
    Norm(Result);
  finally
    UnmaskFP(m);
  end;
end;

function TyParallelBrushOpt(const AStyle: TTyParallelSelectStyle): TTyBrushOpt;
begin
  Result := TyBrushDefaultOpt;
  Result.BrushType := btLineX;
  Result.RemoveOnClick := True;
  { brushStyle merged over the default's: what areaSelectStyle has -- the
    colours it does not write are its defaults, the skin's }
  if AStyle.Style.Fill.Written then Result.Style.Fill := AStyle.Style.Fill
  else Result.Style.Fill.Skin := TyParallelSelectSkin;
  if AStyle.Style.Stroke.Written then Result.Style.Stroke := AStyle.Style.Stroke
  else Result.Style.Stroke.Skin := TyParallelSelectSkin;
  if not IsNan(AStyle.Style.LineWidth) then Result.Style.LineWidth := AStyle.Style.LineWidth;
  if not IsNan(AStyle.Style.Opacity) then Result.Style.Opacity := AStyle.Style.Opacity;
end;

{ ==================== the selection [Batch 127] ====================

  Comparisons go through Lt / Le, false on a NaN as JavaScript's are. }

function Lt(A, B: Double): Boolean;
begin
  Result := not IsNan(A) and not IsNan(B) and (A < B);
end;

function Le(A, B: Double): Boolean;
begin
  Result := not IsNan(A) and not IsNan(B) and (A <= B);
end;

{ new BoundingRect(x, y, w, h): a negative size flipped }
function NormRect(AX, AY, AW, AH: Double): TTyXYWH;
begin
  if Lt(AW, 0) then
  begin
    AX := AX + AW;
    AW := -AW;
  end;
  if Lt(AH, 0) then
  begin
    AY := AY + AH;
    AH := -AH;
  end;
  Result.X := AX;
  Result.Y := AY;
  Result.W := AW;
  Result.H := AH;
end;

{ BoundingRect.contain }
function RectContain(const R: TTyXYWH; AX, AY: Double): Boolean;
begin
  Result := Le(R.X, AX) and Le(AX, R.X + R.W) and Le(R.Y, AY) and Le(AY, R.Y + R.H);
end;

function TyBrushRectIntersect(const A, B: TTyXYWH): Boolean;
var
  na, nb: TTyXYWH;
  ax0, ax1, ay0, ay1, bx0, bx1, by0, by1: Double;
  m: TFPUExceptionMask;
begin
  m := MaskFP;
  try
    na := NormRect(A.X, A.Y, A.W, A.H);
    nb := NormRect(B.X, B.Y, B.W, B.H);
    ax0 := na.X;
    ax1 := na.X + na.W;
    ay0 := na.Y;
    ay1 := na.Y + na.H;
    bx0 := nb.X;
    bx1 := nb.X + nb.W;
    by0 := nb.Y;
    by1 := nb.Y + nb.H;
    if Lt(ax1, ax0) or Lt(ay1, ay0) or Lt(bx1, bx0) or Lt(by1, by0) then Exit(False);
    Result := not (Lt(ax1, bx0) or Lt(bx1, ax0) or Lt(ay1, by0) or Lt(by1, ay0));
  finally
    UnmaskFP(m);
  end;
end;

function TyBrushSelAreaOf(const AArea: TTyBrushArea): TTyBrushSelArea;
var
  i: Integer;
  x0, x1, y0, y1: Double;
  m: TFPUExceptionMask;
begin
  Result := Default(TTyBrushSelArea);
  Result.BrushType := AArea.Opt.BrushType;
  Result.Range := Copy(AArea.Opt.Range);
  m := MaskFP;
  try
    if Result.BrushType = btRect then
    begin
      if Length(Result.Range) < 2 then Exit;
      Result.HasBR := True;
      Result.BR := NormRect(Result.Range[0][0], Result.Range[1][0],
        Result.Range[0][1] - Result.Range[0][0], Result.Range[1][1] - Result.Range[1][0]);
    end
    else if Result.BrushType = btPolygon then
    begin
      if Length(Result.Range) = 0 then Exit;
      { initExtentForUnion, then the strict comparisons }
      x0 := Infinity;
      x1 := NegInfinity;
      y0 := Infinity;
      y1 := NegInfinity;
      for i := 0 to High(Result.Range) do
      begin
        if Lt(Result.Range[i][0], x0) then x0 := Result.Range[i][0];
        if Lt(x1, Result.Range[i][0]) then x1 := Result.Range[i][0];
        if Lt(Result.Range[i][1], y0) then y0 := Result.Range[i][1];
        if Lt(y1, Result.Range[i][1]) then y1 := Result.Range[i][1];
      end;
      Result.HasBR := True;
      Result.BR := NormRect(x0, y0, x1 - x0, y1 - y0);
    end;
  finally
    UnmaskFP(m);
  end;
end;

function TyBrushPolygonContain(const APoints: TTyBrushRange; AX, AY: Double): Boolean;
const cEps = 1e-8;
var
  w: Double;
  i: Integer;
  p, p2, p0: TTyBrushPair;
  m: TFPUExceptionMask;
begin
  if Length(APoints) = 0 then Exit(False);
  m := MaskFP;
  try
    w := 0;
    p := APoints[0];
    for i := 1 to High(APoints) do
    begin
      p2 := APoints[i];
      w := w + TyBrushWindingLine(p[0], p[1], p2[0], p2[1], AX, AY);
      p := p2;
    end;
    { close the polygon }
    p0 := APoints[0];
    if not (Abs(p[0] - p0[0]) < cEps) or not (Abs(p[1] - p0[1]) < cEps) then
      w := w + TyBrushWindingLine(p[0], p[1], p0[0], p0[1], AX, AY);
    Result := w <> 0;
  finally
    UnmaskFP(m);
  end;
end;

{ lineLineIntersect: crossProduct2d and nearZero (1e-6); colinear is none }
function LineLineIntersect(A1X, A1Y, A2X, A2Y, B1X, B1Y, B2X, B2Y: Double): Boolean;
var mx, my, nx, ny, nm, bx, by, q, p: Double;
begin
  mx := A2X - A1X;
  my := A2Y - A1Y;
  nx := B2X - B1X;
  ny := B2Y - B1Y;
  nm := nx * my - mx * ny;
  if Le(nm, 1e-6) and Le(-1e-6, nm) then Exit(False);
  bx := A1X - B1X;
  by := A1Y - B1Y;
  q := (bx * my - mx * by) / nm;
  if Lt(q, 0) or Lt(1, q) then Exit(False);
  p := (bx * ny - nx * by) / nm;
  if Lt(p, 0) or Lt(1, p) then Exit(False);
  Result := True;
end;

function TyBrushLinePolygonIntersect(A1X, A1Y, A2X, A2Y: Double;
  const APoints: TTyBrushRange): Boolean;
var
  i: Integer;
  p, p2: TTyBrushPair;
  m: TFPUExceptionMask;
begin
  Result := False;
  if Length(APoints) = 0 then Exit;
  m := MaskFP;
  try
    p2 := APoints[High(APoints)];
    for i := 0 to High(APoints) do
    begin
      p := APoints[i];
      if LineLineIntersect(A1X, A1Y, A2X, A2Y, p[0], p[1], p2[0], p2[1]) then Exit(True);
      p2 := p;
    end;
  finally
    UnmaskFP(m);
  end;
end;

{ inLineRange }
function InLine(AP, A0, A1: Double): Boolean;
begin
  Result := Le(A0, AP) and Le(AP, A1);
end;

function TyBrushSelects(const AArea: TTyBrushSelArea; const ALayout: TTyBrushItemLayout): Boolean;
var
  x, y, w, h, l0, l1, t, r0, r1: Double;
  pts: TTyBrushRange;
  m: TFPUExceptionMask;
begin
  Result := False;
  if ALayout.Kind = blkNone then Exit;
  m := MaskFP;
  try
    case AArea.BrushType of
      btRect:
        begin
          if not AArea.HasBR then Exit;
          if ALayout.Kind = blkPoint then Result := RectContain(AArea.BR, ALayout.X, ALayout.Y)
          else Result := TyBrushRectIntersect(AArea.BR, NormRect(ALayout.X, ALayout.Y,
            ALayout.W, ALayout.H));
        end;
      btPolygon:
        begin
          pts := AArea.Range;
          if ALayout.Kind = blkPoint then
          begin
            Result := AArea.HasBR and RectContain(AArea.BR, ALayout.X, ALayout.Y)
              and TyBrushPolygonContain(pts, ALayout.X, ALayout.Y);
            Exit;
          end;
          if Length(pts) <= 1 then Exit;
          x := ALayout.X;
          y := ALayout.Y;
          w := ALayout.W;
          h := ALayout.H;
          Result := TyBrushPolygonContain(pts, x, y)
            or TyBrushPolygonContain(pts, x + w, y)
            or TyBrushPolygonContain(pts, x, y + h)
            or TyBrushPolygonContain(pts, x + w, y + h)
            or RectContain(NormRect(x, y, w, h), pts[0][0], pts[0][1])
            or TyBrushLinePolygonIntersect(x, y, x + w, y, pts)
            or TyBrushLinePolygonIntersect(x, y, x, y + h, pts)
            or TyBrushLinePolygonIntersect(x + w, y, x + w, y + h, pts)
            or TyBrushLinePolygonIntersect(x, y + h, x + w, y + h, pts);
        end;
      btLineX, btLineY:
        begin
          if Length(AArea.Range) < 1 then Exit;
          r0 := AArea.Range[0][0];
          r1 := AArea.Range[0][1];
          if ALayout.Kind = blkPoint then
          begin
            if AArea.BrushType = btLineX then t := ALayout.X else t := ALayout.Y;
            Exit(InLine(t, r0, r1));
          end;
          if AArea.BrushType = btLineX then
          begin
            l0 := ALayout.X;
            l1 := ALayout.X + ALayout.W;
          end
          else
          begin
            l0 := ALayout.Y;
            l1 := ALayout.Y + ALayout.H;
          end;
          { layoutRange.reverse() when its end is below its start }
          if Lt(l1, l0) then
          begin
            t := l0;
            l0 := l1;
            l1 := t;
          end;
          Result := InLine(l0, r0, r1) or InLine(l1, r0, r1)
            or InLine(r0, l0, l1) or InLine(r1, l0, l1);
        end;
    end;
  finally
    UnmaskFP(m);
  end;
end;

{ one fixed visual: the first of a list, the value itself otherwise }
function FixedVisualOf(const AKind: string; AData: TJSONData): TTyVisualPieceVisual;
begin
  Result := Default(TTyVisualPieceVisual);
  Result.Kind := AKind;
  if AData is TJSONArray then
  begin
    if AData.Count = 0 then Exit;
    AData := AData.Items[0];
  end;
  if (AData = nil) or (AData.JSONType = jtNull) then Exit;
  case AData.JSONType of
    jtNumber:
      begin
        Result.Defined := True;
        Result.IsNum := True;
        Result.Num := AData.AsFloat;
      end;
    jtString:
      begin
        Result.Defined := True;
        Result.Str := AData.AsString;
        Result.Num := NaN;
      end;
    jtBoolean:
      begin
        Result.Defined := True;
        Result.IsNum := True;
        if AData.AsBoolean then Result.Num := 1 else Result.Num := 0;
      end;
  end;
end;

{ createVisualMappings of one state: its valid visual types, in
  prepareVisualTypes' order. AAddLift: optionUpdated's `liftZ = 5`, the
  object's last key }
function StateVisuals(AObj: TJSONObject; AAddLift: Boolean): TTyVisualPieceVisualArray;
var
  keys, ordered: TTyStringArray;
  i, k: Integer;
begin
  Result := nil;
  keys := nil;
  if AObj <> nil then
    for i := 0 to AObj.Count - 1 do
      if TyVisualIsValidType(AObj.Names[i]) then
      begin
        SetLength(keys, Length(keys) + 1);
        keys[High(keys)] := AObj.Names[i];
      end;
  if AAddLift then
  begin
    SetLength(keys, Length(keys) + 1);
    keys[High(keys)] := 'liftZ';
  end;
  ordered := TyPrepareVisualTypes(keys);
  SetLength(Result, Length(ordered));
  for k := 0 to High(ordered) do
    if AAddLift and (ordered[k] = 'liftZ') then
    begin
      Result[k] := Default(TTyVisualPieceVisual);
      Result[k].Kind := 'liftZ';
      Result[k].Defined := True;
      Result[k].IsNum := True;
      Result[k].Num := 5;
    end
    else
      Result[k] := FixedVisualOf(ordered[k], AObj.Find(ordered[k]));
end;

function JsTruthyData(AData: TJSONData): Boolean;
begin
  Result := JsTruthy(AData);
end;

function TyBrushVisualOf(ANode: TJSONData): TTyBrushVisual;
var
  o, inB, outB: TJSONObject;
  d: TJSONData;
  defOut: TJSONData;
begin
  Result := Default(TTyBrushVisual);
  o := nil;
  if ANode is TJSONObject then o := TJSONObject(ANode);
  inB := nil;
  outB := nil;
  defOut := nil;
  if o <> nil then
  begin
    d := o.Find('inBrush');
    if JsTruthyData(d) and (d is TJSONObject) then inB := TJSONObject(d);
    d := o.Find('outOfBrush');
    if JsTruthyData(d) and (d is TJSONObject) then outB := TJSONObject(d);
    defOut := o.Find('defaultOutOfBrushColor');
  end;
  { liftZ 5 unless the option has its own (null included) }
  Result.States[True] := StateVisuals(inB, (inB = nil) or (inB.IndexOfName('liftZ') < 0));
  if outB <> nil then
    Result.States[False] := StateVisuals(outB, False)
  else
  begin
    SetLength(Result.States[False], 1);
    Result.States[False][0] := FixedVisualOf('color', defOut);
    Result.States[False][0].Kind := 'color';
    { the model's defaultOutOfBrushColor: the token, the skin's here }
    Result.OutIsSkin := (defOut = nil);
  end;
end;

function TyBrushReachOf(ANode: TJSONData): TTyBrushReach;
var
  d: TJSONData;
  i: Integer;

  procedure AddTo(var A: TTyIntegerArray; AData: TJSONData);
  begin
    if (AData = nil) or (AData.JSONType <> jtNumber) then Exit;
    if Frac(AData.AsFloat) <> 0 then Exit;
    SetLength(A, Length(A) + 1);
    A[High(A)] := Trunc(AData.AsFloat);
  end;

begin
  Result := Default(TTyBrushReach);
  { seriesIndex: 'all' by default }
  Result.AllSeries := True;
  if not (ANode is TJSONObject) then Exit;
  d := TJSONObject(ANode).Find('brushLink');
  if d <> nil then
  begin
    if (d.JSONType = jtString) and (d.AsString = 'all') then Result.Link := blnAll
    else if d is TJSONArray then
    begin
      Result.Link := blnList;
      for i := 0 to d.Count - 1 do AddTo(Result.LinkList, d.Items[i]);
    end;
  end;
  d := TJSONObject(ANode).Find('seriesIndex');
  if (d <> nil) and (d.JSONType <> jtNull)
    and not ((d.JSONType = jtString) and (d.AsString = 'all')) then
  begin
    Result.AllSeries := False;
    if d is TJSONArray then
      for i := 0 to d.Count - 1 do AddTo(Result.SeriesList, d.Items[i])
    else
      AddTo(Result.SeriesList, d);
  end;
end;

function InList(const A: TTyIntegerArray; V: Integer): Boolean;
var i: Integer;
begin
  for i := 0 to High(A) do
    if A[i] = V then Exit(True);
  Result := False;
end;

function TyBrushLinks(const AReach: TTyBrushReach; ASeriesIndex: Integer): Boolean;
begin
  case AReach.Link of
    blnAll: Result := True;
    blnList: Result := InList(AReach.LinkList, ASeriesIndex);
  else
    Result := False;
  end;
end;

function TyBrushControls(const AReach: TTyBrushReach; ASeriesIndex: Integer): Boolean;
begin
  Result := AReach.AllSeries or InList(AReach.SeriesList, ASeriesIndex);
end;

procedure TyBrushApplyVisual(const AVisuals: TTyVisualPieceVisualArray;
  ASkinColor: Boolean; const AOutColor: TTyVisualColor; var ARow: TTyVisualRow);
var
  i: Integer;
  v: TTyVisualPieceVisual;
  c: TTyVisualColor;
  m: TFPUExceptionMask;
begin
  m := MaskFP;
  try
    for i := 0 to High(AVisuals) do
    begin
      v := AVisuals[i];
      if v.Kind = 'color' then
      begin
        { setItemVisual(style[drawType], visual[0]) }
        if ASkinColor and not v.Defined then c := AOutColor
        else if not v.Defined or v.IsNum or not TyVisualTryParse(v.Str, c) then
          c := TyVisualUndefined;
        ARow.Color := c;
        ARow.ColorSet := True;
        ARow.LateColor := True;
      end
      else if v.Kind = 'opacity' then
      begin
        { undefined is still written: the element draws at 1 }
        if v.Defined and not IsNan(v.Num) then ARow.Opacity := v.Num
        else ARow.Opacity := 1;
        ARow.OpacitySet := True;
        ARow.LateOpacity := True;
      end
      else if (v.Kind = 'colorAlpha') or (v.Kind = 'colorHue')
        or (v.Kind = 'colorSaturation') or (v.Kind = 'colorLightness') then
      begin
        if not v.Defined or IsNan(v.Num) then Continue;
        if v.Kind = 'colorAlpha' then ARow.Color := TyVisualModifyAlpha(ARow.Color, v.Num)
        else if v.Kind = 'colorHue' then
          ARow.Color := TyVisualModifyHSL(ARow.Color, v.Num, 0, 0, True, False, False)
        else if v.Kind = 'colorSaturation' then
          ARow.Color := TyVisualModifyHSL(ARow.Color, 0, v.Num, 0, False, True, False)
        else
          ARow.Color := TyVisualModifyHSL(ARow.Color, 0, 0, v.Num, False, False, True);
        ARow.ColorSet := True;
        ARow.LateColor := True;
      end
      else if v.Kind = 'symbol' then
      begin
        ARow.SymbolSet := v.Defined;
        if v.IsNum then ARow.Symbol := TyJsNumberToString(v.Num) else ARow.Symbol := v.Str;
      end
      else if v.Kind = 'symbolSize' then
      begin
        ARow.Size := v.Num;
        if not v.Defined then ARow.Size := NaN;
        ARow.SizeSet := not IsNan(ARow.Size);
      end
      else if v.Kind = 'liftZ' then
      begin
        ARow.LiftZ := v.Num;
        if not v.Defined then ARow.LiftZ := NaN;
        ARow.LiftZSet := not IsNan(ARow.LiftZ);
      end;
    end;
  finally
    UnmaskFP(m);
  end;
end;

{ ==================== the coordinates ==================== }

{ formatMinMax }
function FmtMM(A, B: Double): TTyBrushPair;
begin
  if A > B then
  begin
    Result[0] := B;
    Result[1] := A;
  end
  else
  begin
    Result[0] := A;
    Result[1] := B;
  end;
end;

function TyBrushConvert(AType: TTyBrushType; AToData: Boolean; ACart: TTyCartesian2D;
  const AView: TTyBrushView; const ARange: TTyBrushRange; AClamp: Boolean;
  out AValues, AXYMinMax: TTyBrushRange): Boolean;
var
  ax: TTyAxis;
  i, k: Integer;
  v: array[0..1] of Double;
  d: TTyDoubleArray;
  pt: TTyPointF;
  m: TTyMat2D;
  a, b: TTyBrushPair;
  mk: TFPUExceptionMask;

  function Dev(AV: Double; AYDim: Boolean): Double;
  begin
    if AYDim then Result := AView.OY + AV * AView.S
    else Result := AView.OX + AV * AView.S;
  end;

  function Css(AV: Double; AYDim: Boolean): Double;
  begin
    if AYDim then Result := (AV - AView.OY) / AView.S
    else Result := (AV - AView.OX) / AView.S;
  end;

  { Cartesian2D.pointToData(p, clamp): the inverse matrix (no clamp), else
    each axis' coordToData }
  function ToData(AX, AY: Double): TTyBrushPair;
  begin
    if ACart.InvTransform(m) then
    begin
      ACart.PointToData(TyPointF(Dev(AX, False), Dev(AY, True)), d);
      Result[0] := d[0];
      Result[1] := d[1];
      Exit;
    end;
    Result[0] := ACart.AxisByDim('x').CoordToData(Dev(AX, False), AClamp);
    Result[1] := ACart.AxisByDim('y').CoordToData(Dev(AY, True), AClamp);
  end;

  function ToPixel(AX, AY: Double): TTyBrushPair;
  begin
    pt := ACart.DataToPointClamped([AX, AY], AClamp);
    Result[0] := Css(pt.X, False);
    Result[1] := Css(pt.Y, True);
  end;

begin
  AValues := nil;
  AXYMinMax := nil;
  Result := False;
  if (ACart = nil) or (ACart.AxisByDim('x') = nil) or (ACart.AxisByDim('y') = nil) then Exit;
  mk := MaskFP;
  try
    case AType of
      btLineX, btLineY:
        begin
          if Length(ARange) < 1 then Exit;
          if AType = btLineX then ax := ACart.AxisByDim('x') else ax := ACart.AxisByDim('y');
          for k := 0 to 1 do
            if AToData then v[k] := ax.CoordToData(Dev(ARange[0][k], AType = btLineY), True)
            else v[k] := Css(ax.DataToCoord(ARange[0][k]), AType = btLineY);
          SetLength(AValues, 1);
          AValues[0] := FmtMM(v[0], v[1]);
          SetLength(AXYMinMax, 2);
          if AType = btLineX then
          begin
            AXYMinMax[0] := AValues[0];
            AXYMinMax[1] := Pair(NaN, NaN);
          end
          else
          begin
            AXYMinMax[0] := Pair(NaN, NaN);
            AXYMinMax[1] := AValues[0];
          end;
        end;
      btRect:
        begin
          if Length(ARange) < 2 then Exit;
          if AToData then
          begin
            a := ToData(ARange[0][0], ARange[1][0]);
            b := ToData(ARange[0][1], ARange[1][1]);
          end
          else
          begin
            a := ToPixel(ARange[0][0], ARange[1][0]);
            b := ToPixel(ARange[0][1], ARange[1][1]);
          end;
          SetLength(AValues, 2);
          AValues[0] := FmtMM(a[0], b[0]);
          AValues[1] := FmtMM(a[1], b[1]);
          AXYMinMax := Copy(AValues);
        end;
      btPolygon:
        begin
          SetLength(AValues, Length(ARange));
          SetLength(AXYMinMax, 2);
          AXYMinMax[0] := Pair(Infinity, NegInfinity);
          AXYMinMax[1] := Pair(Infinity, NegInfinity);
          for i := 0 to High(ARange) do
          begin
            if AToData then a := ToData(ARange[i][0], ARange[i][1])
            else a := ToPixel(ARange[i][0], ARange[i][1]);
            AXYMinMax[0][0] := JMin(AXYMinMax[0][0], a[0]);
            AXYMinMax[1][0] := JMin(AXYMinMax[1][0], a[1]);
            AXYMinMax[0][1] := JMax(AXYMinMax[0][1], a[0]);
            AXYMinMax[1][1] := JMax(AXYMinMax[1][1], a[1]);
            AValues[i] := a;
          end;
        end;
    else
      Exit;
    end;
    Result := True;
  finally
    UnmaskFP(mk);
  end;
end;

function TyBrushDiff(AType: TTyBrushType; const AValues, ARefer: TTyBrushRange;
  ASX, ASY: Double): TTyBrushRange;
var
  i: Integer;
  s: Double;
  m: TFPUExceptionMask;
begin
  Result := nil;
  m := MaskFP;
  try
    case AType of
      btLineX, btLineY:
        begin
          if (Length(AValues) < 1) or (Length(ARefer) < 1) then Exit;
          if AType = btLineX then s := ASX else s := ASY;
          SetLength(Result, 1);
          Result[0][0] := AValues[0][0] - s * ARefer[0][0];
          Result[0][1] := AValues[0][1] - s * ARefer[0][1];
        end;
      btRect:
        begin
          if (Length(AValues) < 2) or (Length(ARefer) < 2) then Exit;
          SetLength(Result, 2);
          Result[0][0] := AValues[0][0] - ASX * ARefer[0][0];
          Result[0][1] := AValues[0][1] - ASX * ARefer[0][1];
          Result[1][0] := AValues[1][0] - ASY * ARefer[1][0];
          Result[1][1] := AValues[1][1] - ASY * ARefer[1][1];
        end;
      btPolygon:
        begin
          SetLength(Result, Length(AValues));
          for i := 0 to High(AValues) do
            if i <= High(ARefer) then
            begin
              Result[i][0] := AValues[i][0] - ASX * ARefer[i][0];
              Result[i][1] := AValues[i][1] - ASY * ARefer[i][1];
            end
            else
            begin
              { refer[idx] undefined: a TypeError upstream; NaN here }
              Result[i][0] := NaN;
              Result[i][1] := NaN;
            end;
        end;
    end;
  finally
    UnmaskFP(m);
  end;
end;

procedure TyBrushScales(const ACur, AOrig: TTyBrushRange; out ASX, ASY: Double);
var
  c0, c1, o0, o1: Double;
  m: TFPUExceptionMask;
begin
  m := MaskFP;
  try
    if Length(ACur) >= 2 then
    begin
      c0 := ACur[0][1] - ACur[0][0];
      c1 := ACur[1][1] - ACur[1][0];
    end
    else
    begin
      c0 := NaN;
      c1 := NaN;
    end;
    if Length(AOrig) >= 2 then
    begin
      o0 := AOrig[0][1] - AOrig[0][0];
      o1 := AOrig[1][1] - AOrig[1][0];
    end
    else
    begin
      o0 := NaN;
      o1 := NaN;
    end;
    ASX := c0 / o0;
    ASY := c1 / o1;
    if IsNan(ASX) then ASX := 1;
    if IsNan(ASY) then ASY := 1;
  finally
    UnmaskFP(m);
  end;
end;

{ ==================== the throttle ==================== }

function TyBrushThrottleConfigure(var T: TTyBrushThrottle; AKind: TTyBrushThrottleKind;
  const ATypeText: string; ARate: Double): Boolean;
var changed: Boolean;
begin
  { the function as it stands: throttled with a type and a rate, or the
    original (whose rate and type are undefined: any request differs) }
  if not T.Active then changed := True
  else changed := (T.TypeText <> ATypeText) or (IsNan(ARate) <> IsNan(T.Rate))
    or (not IsNan(ARate) and (ARate <> T.Rate));
  if changed then
  begin
    if IsNan(ARate) or (AKind = btkNone) then
    begin
      T.Active := False;
      Exit(False);
    end;
    { a new throttle: its own state from the epoch }
    T.Active := True;
    T.TypeText := ATypeText;
    T.Rate := ARate;
    T.Debounce := AKind = btkDebounce;
    T.LastCall := 0;
    T.LastExec := 0;
    T.Timer := 0;
    Inc(T.Gen);
  end;
  Result := T.Active;
end;

procedure TyBrushThrottleCall(var T: TTyBrushThrottle; ANow: Double;
  out AExecNow: Boolean; out ADue: Double);
var diff, base: Double;
begin
  AExecNow := False;
  ADue := NaN;
  if T.Debounce then base := T.LastCall else base := T.LastExec;
  diff := ANow - base - T.Rate;
  if T.Debounce then ADue := ANow + T.Rate
  else if diff >= 0 then AExecNow := True
  else ADue := ANow + -diff;
  T.LastCall := ANow;
end;

end.
