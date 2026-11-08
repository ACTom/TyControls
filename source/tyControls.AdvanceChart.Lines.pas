unit tyControls.AdvanceChart.Lines;
{$mode objfpc}{$H+}
{ THE LINES SERIES [Batch 121, C12]: what ECharts 6.1's chart/lines and the
  line helpers it draws with (LineDraw, Line, LinePath, Polyline, EffectLine,
  EffectPolyline, LargeLineDraw) compute, as numbers -- the control draws and
  the paint list holds the result.

  THE DATA. One row per item, whatever the item is written as:
    an object with `coords: [[x, y], ...]`, value, name, fromName, toName --
      the ordinary form; `value` is the row's one dimension;
    [[x, y], [x, y], ...] -- a bare coords array: the value is not a number,
      and the raw value a label and a tooltip read is the array itself;
    [count, x, y, x, y, count, ...] -- the flat typed form: every row's
      value is 0 (the series' data becomes a Float32Array of zeros);
    a pair of objects with `coord` and `name` -- ECharts 2's pairs (compatEc2): the
      first point's name names the row, its keys win over the second's.
  A coordinate written as one string (a region's name, say) is two
  characters by the time it is projected: getLineCoords copies each
  coordinate's [0] and [1], and a geo's string branch is never reached
  [spec 242].

  THE COORDINATE HOOK. A row's coordinates go through TTyLinesProject, one
  pair at a time -- the coordinate system's dataToPoint. A cartesian, a polar
  and a calendar answer it now; a geo too [Batch 152: the geo's dataToPoint
  of the pair, the control's GeoLinesPoint].
  Nothing here knows which system it is.

  THE CONTROL POINT IS NOT THE GRAPH'S. linesLayout puts it at the chord's
  middle minus the perpendicular times the curveness:
    cp = ((x0 + x1) / 2 - (y0 - y1) c, (y0 + y1) / 2 - (x1 - x0) c)
  when `+curveness` is truthy (a string '0.5' curves, 0 and not-a-number do
  not).

  THE EFFECT is a symbol riding the line on a looping clip of its own
  (`__t` 0 -> 1, or 2 with roundTrip): EffectLine moves it along the
  quadratic -- a straight line uses its chord's middle as the control point
  -- and turns it with the derivative; 'line', 'rect' and 'roundRect' stretch
  along the path between frames (the trail). EffectPolyline walks the
  polyline by the cumulative lengths, its frame search starting where the
  last one stopped. TTyLinesEffect is one symbol's run state; the control's
  animation proxy steps it from the clip's during.

  THE COLOUR MAY BE A GRADIENT [spec 242]: the line strokes it over its own
  path's rect (grown by the pen), the end symbols and the effect symbol fill
  it in their own frames, carried by their transforms (TyLinesPlacedGradient,
  every frame for what moves). The label is not the line's colour: Line's
  textConfig asks for the outside ink unless the label wrote a colour
  ('inherit' is the line's). Its `rotate` and `offset` lie over what
  Line.beforeUpdate sets, as zrender's updateInnerText lays them.

  LARGE LINES are in AdvanceChart.Large (lgkLines); their segs come from here.

  PURE: SysUtils, Math, fpjson and the AdvanceChart value units. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvanceChart.Types, tyControls.AdvanceChart.Shape,
  tyControls.AdvanceChart.Paint, tyControls.AdvanceChart.Large;

const
  TyLinesSeriesTypeName = 'lines';
  { the row's one dimension }
  TyLinesValueDim = 'value';
  { upstream's default effect symbol z2 (EffectLine: symbol.z2 = 100) }
  TyLinesEffectZ2 = 100;

type
  { lvkName [spec 242]: a coordinate written as one string (a region's
    name, say); Str is the string, and both halves of the pair carry it --
    the projection splits it as getLineCoords does }
  TTyLinesValueKind = (lvkNumber, lvkString, lvkNull, lvkOther, lvkName);
  { one data coordinate as written }
  TTyLinesValue = record
    Kind: TTyLinesValueKind;
    Num: Double;
    Str: string;
  end;
  TTyLinesValueArray = array of TTyLinesValue;

  { THE COORDINATE HOOK: one written pair to a point, not-a-number where it
    has none. AClamp is the large layout's `dataToPoint(coords, false)`
    asking for no clamp; the ordinary layout passes True (the default). }
  TTyLinesProject = function(const AX, AY: TTyLinesValue; AClamp: Boolean): TTyPointF of object;

  { What the row's raw value is to a label's default text and a tooltip }
  TTyLinesRaw = record
    { the item's own options: nil for a bare array and the flat form; the
      ec2 pair's two points (Item first, Item2 after it) }
    Item, Item2: TJSONObject;
    { the coordinates, x then y per point }
    XY: TTyLinesValueArray;
    { the row's `value` dimension }
    Value: Double;
    { getRawValue: none (undefined), or the JSON it is (the coords array of
      a bare row, `value` of an object); the flat form's [0] }
    RawNone: Boolean;
    RawJson: TJSONData;
    RawIsFlat: Boolean;
    { the data name, and the names a tooltip reads }
    Name: string;
    HasName: Boolean;
    FromName, ToName: string;
    HasFromName, HasToName: Boolean;
  end;
  TTyLinesRawArray = array of TTyLinesRaw;

  { One row laid out (linesLayout): the points -- two for a line, every
    point for a polyline -- and a line's control point. Drawn is
    lineNeedsDraw: the first two points are numbers. }
  TTyLinesGeom = record
    Row: Integer;
    Pts: TTyPointFArray;
    Curved: Boolean;
    CP: TTyPointF;
    Drawn: Boolean;
  end;
  TTyLinesGeomArray = array of TTyLinesGeom;

  { Line.beforeUpdate's label positions }
  TTyLinesLabelPos = (llpMiddle, llpStart, llpEnd, llpInsideStart,
    llpInsideStartTop, llpInsideStartBottom, llpInsideMiddle,
    llpInsideMiddleTop, llpInsideMiddleBottom, llpInsideEnd,
    llpInsideEndTop, llpInsideEndBottom);

  { ONE EFFECT SYMBOL'S RUN: the path it rides and what the last frame left
    (EffectLine's __p1 / __p2 / __cp1, __lastT and the symbol's x / y;
    EffectPolyline's _points / _offsets / _length / _lastFrame /
    _lastFramePercent). }
  TTyLinesEffect = record
    Poly: Boolean;
    P1, P2, CP1: TTyPointF;
    Points: TTyPointFArray;
    Offsets: TTyDoubleArray;
    HasOffsets: Boolean;
    PolyLength: Double;
    { 'line', 'rect' and 'roundRect' leave a trail (scaleY over the step) }
    Trail: Boolean;
    ScaleW, ScaleH: Double;
    { the clip's value now, and the frame before }
    T: Double;
    HasLastT: Boolean;
    LastT: Double;
    { the symbol now: hidden until the first during }
    X, Y, Rotation, ScaleX, ScaleY: Double;
    Ignore: Boolean;
    LastFrame: Integer;
    LastFramePercent: Double;
    { [spec 242] the delay was a string that is no number (a '@Name' nobody
      registered): the clip's start time is a string upstream, every
      percent not a number -- the symbol is never anywhere }
    Poisoned: Boolean;
    { [R7-W] the last transform a step left that is a number (x, y, scaleX,
      scaleY, rotation): what the symbol's invTransform keeps once its
      transform is none (matrix.invert fails) -- an update's own frame
      among them }
    HasInv: Boolean;
    InvX, InvY, InvSX, InvSY, InvRot: Double;
  end;

  { ONE ROW'S LOOK, as the visual and the view resolve it: the line's
    style (its own lineStyle over the series'), the two end symbols, the
    label and the effect symbol }
  TTyLinesSym = record
    Name: string;
    W, H: Double;
  end;
  TTyLinesInk = record
    Stroke: TTyChartColor;
    Width, Opacity: Double;
    Dash: TTyDoubleArray;
    { [R2-I5] the word the dash is written as (TTyChartStyle.DashWord) }
    DashWord: Byte;
    { [R2-I2] lineStyle.dashOffset, px }
    DashOffset: Double;
    Sym: array[0..1] of TTyLinesSym;
    { the label: shown, its words, where (Line.beforeUpdate), how far, the
      alignment the author wrote (1 horizontal, 2 vertical) and its spec in
      the expansion's per-row table (ItemSpec, 1-based) }
    LabelShow: Boolean;
    LabelText: string;
    LabelPos: TTyLinesLabelPos;
    DistX, DistY: Double;
    AlignFlags: Integer;
    AlignH: TTyTextAnchorH;
    AlignV: TTyTextAnchorV;
    LabelSpec: Integer;
    { the effect symbol: its type and size, its colour (effect.color or the
      line's), its opacity, the period and the delay in ms as the clip runs
      them (constantSpeed already turned into a period), loop and roundTrip }
    EffName: string;
    EffW, EffH: Double;
    EffColor: TTyChartColor;
    EffOpacity: Double;
    EffPeriod, EffDelay: Double;
    EffLoop, EffRoundTrip: Boolean;
    { [spec 242] see TTyLinesEffect.Poisoned }
    EffPoisoned: Boolean;
    { [spec 242] THE VISUAL COLOUR AS A GRADIENT (Kind cgkNone: a plain
      colour, Stroke): the line's pen, the end symbols' and -- unless
      effect.color is written -- the effect symbol's colour (EffGrad).
      Stroke and EffColor hold the first stop then, what a tooltip marker
      reads (convertToColorString) }
    StrokeGrad: TTyChartGradient;
    EffGrad: TTyChartGradient;
    { [R7-R] THE EFFECT SYMBOL'S OWN STYLE, effect.getItemStyle(['color'])
      set over it (each key the row's effect, else the series'): its border
      (EffStrokeSet where a colour or a gradient is written -- 'none' and
      what does not parse stroke nothing), its width in the symbol's own
      frame (EffLineWidth; not-a-number where unwritten: zrender's 1), the
      dash (EffDash in that frame, EffDashWord the word it was written as),
      its phase, cap, join and miter limit (0: the canvas' defaults), the
      shadow (EffShadowSet where any of its keys is written; its colour the
      effect's colour unless shadowColor is) }
    EffStrokeSet: Boolean;
    EffStroke: TTyChartColor;
    EffStrokeGrad: TTyChartGradient;
    EffLineWidth: Double;
    EffDash: TTyDoubleArray;
    EffDashWord: Byte;
    EffDashOffset: Double;
    EffCap, EffJoin: Byte;
    EffMiter: Double;
    EffShadowSet: Boolean;
    EffShadow: TTyChartShadow;
    { [R7-S] the shadowColor the symbol hands the canvas (zrender assigns it
      whether or not anything is cast): its written one, else its colour;
      EffShadowLeft where that is no colour the canvas takes (a gradient,
      'none') -- the canvas keeps what it had }
    EffShadowLeft: Boolean;
    EffCanvasShadow: TTyChartColor;
    { [R7-R] effect.color written 'none': truthy, so it is the colour --
      setColor fills (or strokes) with 'none', which is none }
    EffColorNone: Boolean;
    { [spec 242] the label's textConfig: `rotate` (degrees, as radians) and
      `offset` where written -- applied over what Line.beforeUpdate sets }
    LabelHasRot: Boolean;
    LabelRot: Double;
    LabelHasOff: Boolean;
    LabelOffX, LabelOffY: Double;
  end;
  TTyLinesInkArray = array of TTyLinesInk;

  { ONE SERIES SOLVED: its rows, how they are drawn, its clip (a rect on a
    cartesian, a sector on a polar, none on a calendar), its z, the effect,
    the trail's lastFrameAlpha (0: no trail), and -- in large mode -- the
    batch }
  TTyLinesSolved = record
    Valid: Boolean;
    SeriesIndex: Integer;
    Poly, Effect, IsLarge: Boolean;
    HasClip, HasClipSector: Boolean;
    Clip: TTyRectF;
    ClipCX, ClipCY, ClipR0, ClipR1, ClipSA, ClipEA: Double;
    ClipCW: Boolean;
    Z, Z2: Integer;
    TrailAlpha: Double;
    Raws: TTyLinesRawArray;
    Geoms: TTyLinesGeomArray;
    Inks: TTyLinesInkArray;
    Large: TTyLargeGeom;
    LargeStroke: TTyChartColor;
    LargeWidth, LargeOpacity: Double;
    LargeDash: TTyDoubleArray;
    { [spec 242] the large batch's colour as a gradient (cgkNone: none) }
    LargeGrad: TTyChartGradient;
    { [spec 242] PROGRESSIVE LARGE: the rows of each planned chunk (none:
      one batch of every row) -- LargeLineDraw.incrementalUpdate's path a
      chunk }
    LargeChunks: array of TTyIntegerArray;
    { [spec 242] device px per CSS px, what the build measured with }
    Scale: Double;
  end;
  TTyLinesSolvedArray = array of TTyLinesSolved;

{ ---- the data ---- }

{ The rows of a lines series as written (compatEc2, the flat form, bare
  arrays). The JSON references stay the option's. }
function TyLinesRawsOf(ASeries: TJSONObject): TTyLinesRawArray;
{ The first of the row's own options, the ec2 pair's second point, then the
  series that writes APath -- a null falls through. ASeries may be nil. }
function TyLinesFind(const ARaw: TTyLinesRaw; ASeries: TJSONObject;
  const APath: array of string): TJSONData;
{ The row's own options only. }
function TyLinesItemFind(const ARaw: TTyLinesRaw;
  const APath: array of string): TJSONData;

{ JavaScript's +x of an option value (null 0, a string by ToNumber, an
  array by its one element), not-a-number for anything else }
function TyLinesJsNum(AData: TJSONData): Double;
function TyLinesJsTruthy(AData: TJSONData): Boolean;

{ ---- the layout ---- }

{ `+itemModel.get(['lineStyle', 'curveness'])`, 0 where it is falsy }
function TyLinesCurvenessOf(const ARaw: TTyLinesRaw; ASeries: TJSONObject): Double;
{ linesLayout's ordinary branch for one row }
function TyLinesLayoutRow(const ARaw: TTyLinesRaw; ARow: Integer;
  APolyline: Boolean; ACurveness: Double; AProject: TTyLinesProject): TTyLinesGeom;
{ linesLayout's large branch: the Float32 segs, [x0, y0, x1, y1] per row,
  or [count, x, y, ...] per row on a polyline }
function TyLinesLargeSegs(const ARaws: TTyLinesRawArray; APolyline: Boolean;
  AProject: TTyLinesProject): TTyDoubleArray;

{ ---- Line.ts geometry ---- }

{ ECLinePath.pointAt: the straight line's x1 (1 - p) + x2 p, the curve's
  quadraticAt }
function TyLinesPointAt(const AG: TTyLinesGeom; AT: Double): TTyPointF;
{ ECLinePath.tangentAt: normalised -- twice for a curve (BezierCurve's
  tangentAt normalises, then LinePath again) }
function TyLinesTangentAt(const AG: TTyLinesGeom; AT: Double): TTyPointF;
{ The end symbols' turn, radians: `(percent === 1 ? -1 : 1) * PI / 2 -
  atan2(tangent)` with the tangent at 0 for the start, at 1 for the end --
  whatever the line's own percent. }
function TyLinesSymbolRotation(const AG: TTyLinesGeom; AAtEnd: Boolean): Double;
{ The label at a percent (Line.beforeUpdate): its x / y, origin, rotation
  and alignment as upstream sets them, and the point the text hangs from --
  the label's own transform composed as zrender composes it (origin,
  rotation, position) }
procedure TyLinesLabelPlace(const AG: TTyLinesGeom; APercent: Double;
  APos: TTyLinesLabelPos; ADistX, ADistY: Double;
  out AX, AY, AOX, AOY, ARot, AAnchorX, AAnchorY: Double;
  out AAH: TTyTextAnchorH; out AAV: TTyTextAnchorV);
{ [spec 242] the same with the label's textConfig over it -- zrender's
  updateInnerText: the rotation where `rotate` is written (ARot then out of
  it, `rotation && rotate`: a not-a-number turns nothing), the offset added
  to x / y with the origin at minus the offset; AX .. ARot are then the
  text's innerTransformable }
procedure TyLinesLabelPlace(const AG: TTyLinesGeom; APercent: Double;
  APos: TTyLinesLabelPos; ADistX, ADistY: Double; AHasRot: Boolean;
  ARotate: Double; AHasOff: Boolean; AOffX, AOffY: Double;
  out AX, AY, AOX, AOY, ARot, AAnchorX, AAnchorY: Double;
  out AAH: TTyTextAnchorH; out AAV: TTyTextAnchorV); overload;
function TyLinesLabelPosOf(const AWord: string): TTyLinesLabelPos;
{ [spec 242] a gradient in an element's own frame put on its style: ALocal
  resolved against ABox (getBoundingRect in that frame), carried by
  scale / turn / move as Transformable composes them -- the painter's
  coordinates. The radius scales by the root of the determinant. }
function TyLinesPlacedGradient(const ALocal: TTyChartGradient; const ABox: TTyXYWH;
  ASX, ASY, ARot, AX, AY: Double): TTyChartGradient;
{ [spec 242] PathProxy.getBoundingRect of a lines row's line (moveTo, then
  lineTo or quadraticCurveTo), grown by its pen as Path.getBoundingRect grows
  it (no fill: by at least strokeContainThreshold) }
function TyLinesLineBox(const AG: TTyLinesGeom; ALineWidth: Double): TTyXYWH;
{ The line from its start to percent: the straight segment, or the curve's
  first part (quadraticSubdivide) as ASteps + 1 points }
function TyLinesPartPoints(const AG: TTyLinesGeom; APercent: Double;
  ASteps: Integer; ASnapWidth: Double = 0): TTyPointFArray;

{ ---- the effect ---- }

{ _updateAnimationPoints: the path the symbol rides }
procedure TyLinesEffectInit(var AE: TTyLinesEffect; const AG: TTyLinesGeom;
  APolyline: Boolean; const ASymbolType: string; AScaleW, AScaleH: Double);
{ _getLineLength: the two legs of the control polygon (EffectLine, "not so
  accurate"), the polyline's own length }
function TyLinesEffectLength(const AE: TTyLinesEffect): Double;
{ _updateSymbolPosition for the clip's value AT }
procedure TyLinesEffectStep(var AE: TTyLinesEffect; AT: Double);
{ lastFrameAlpha: max(min(trailLength / 10 + 0.9, 1), 0) }
function TyLinesTrailAlpha(ATrailLength: Double): Double;

{ ---- the paint list ---- }

{ The series' elements: per drawn row the line (its label as the line's
  caption, placed by Line.beforeUpdate), the two end symbols after it and
  the effect symbol last -- or, in large mode, the one batch. The empty
  symbol's fill is AEmptyFill. }
function TyBuildLinesMarks(const ASolved: TTyLinesSolved; AEmptyFill: TTyChartColor;
  AList: TTyPaintList): Integer;

{ ---- one frame of the animation ---- }

{ the line, an end symbol, the label at shape.percent APercent (the line's
  proxy) }
procedure TyLinesFrameLine(var AEl: TTyChartElement; APercent: Double);
procedure TyLinesFrameSymbol(var AEl: TTyChartElement; APercent: Double);
procedure TyLinesFrameLabel(var AEl: TTyChartElement; APercent: Double);
{ [R6-A] a lines row's label under a state's rotation / offset }
function TyLinesLabelState(const AEl: TTyChartElement; AHasRot: Boolean;
  ARot: Double; AHasOff: Boolean; AOffX, AOffY: Double;
  out AX, AY, ARotOut, ABuX, ABuY: Double): Boolean;
{ the effect symbol where its run left it; AGone: its clip finished and the
  symbol was removed }
procedure TyLinesFrameEffect(var AEl: TTyChartElement; const AE: TTyLinesEffect;
  AGone: Boolean);
{ the run an effect element starts from (its G, Pts and Mono) }
procedure TyLinesEffectOfElement(const AEl: TTyChartElement; out AE: TTyLinesEffect);
{ [R7-S] WHAT THE CANVAS IS LEFT WITH, in AList's paint order: an effect
  symbol whose shadowColor the canvas refuses (a gradient) is cast in the
  shadowColor the element brushed before it left -- zrender's '#000' after
  one that writes none, a solid effect symbol's colour, a written one --
  and one whose transform is not a number (a one-number symbolSize: scaleY
  undefined) is the unit symbol under the transform the canvas had -- the
  effect symbol's before it, else none (the css px frame). A clip's
  restore returns both to what the canvas had when the clip began
  (zrender saves the context per clip path, a series' group each its own),
  a new zlevel starts from AGround (the shadowColor what the chart drew
  first on it leaves: '#000' under shown axes, the canvas' transparent
  default under nothing). }
procedure TyLinesCanvasLeftovers(AList: TTyPaintList; AGround: TTyChartColor); overload;
{ whether AList holds anything TyLinesCanvasLeftovers settles (the only
  cost a chart without one pays) }
function TyLinesCanvasLeftoversDue(AList: TTyPaintList): Boolean;

type
  { [R7-W] WHAT A ZLEVEL'S CANVAS HOLDS when the list starts on it: the
    shadowColor, fill, stroke, lineWidth (the canvas' own units) and the
    transform (device px) the components drawn first left -- the canvas'
    defaults ('#000000' fill and stroke, a width of 1, no transform) where
    nothing was }
  TTyCanvasGround = record
    Shadow: TTyChartColor;
    Fill, Stroke: TTyChartColor;
    LineWidth: Double;
    HasT: Boolean;
    M: TTyMat2D;
    { [R7-Z] and the rest of what the components drawn first leave: the
      blur, cap, join, miterLimit (10 where nothing set one), the dash's
      phase, a gradient fill or stroke }
    Blur: Double;
    Cap, Join: Byte;
    Miter, Phase: Double;
    FillGrad, StrokeGrad: TTyChartGradient;
    { [R7-Y] the font the last text left (HasFont False: the canvas' own
      '10px sans-serif') }
    HasFont: Boolean;
    FontFamily: string;
    FontPx: Double;
    FontWeight: Integer;
  end;

  { [R7-W] the canvas state the paint order carries }
  TTyCanvasState = record
    Shadow: TTyChartColor;
    Blur: Double;
    Cap, Join: Byte;
    Miter: Double;
    HasT: Boolean;
    M: TTyMat2D;
    Fill, Stroke: TTyChartColor;
    FillGrad, StrokeGrad: TTyChartGradient;
    LineWidth, Phase: Double;
    { [R7-Y] the transform (device px) a held gradient was made under -- a
      CanvasGradient's points are in the frame of the element that made it,
      and land under the transform of whichever fills with it; and a held
      pattern (FillPat.Present), its own matrix in the frame of whichever
      fills with it }
    FillGradHasT, StrokeGradHasT: Boolean;
    FillGradM, StrokeGradM: TTyMat2D;
    FillPat: TTyChartPattern;
    { [R7-Y] the shadow's offsets (css px) and the composite operation ('':
      source-over) }
    OffX, OffY: Double;
    Blend: string;
    { [R7-Y] the font (HasFont False: the canvas' own) }
    HasFont: Boolean;
    FontFamily: string;
    FontPx: Double;
    FontWeight: Integer;
  end;

  { [R7-W] ONE RUN OF THE PAINT ORDER: TyCanvasRunStart, then
    TyCanvasRunStep for each element in paint order -- the whole list
    (TyLinesCanvasLeftovers), or a dirty rect's block, whose elements are
    the ones that meet it and which starts from the canvas' own state }
  TTyCanvasRun = record
    Cur, Saved: TTyCanvasState;
    InClip, First: Boolean;
    ZLevel, ClipSeries: Integer;
    ClipRect: TTyRectF;
    Ground: TTyCanvasGround;
    Ds: Double;
  end;

{ the canvas' own defaults, and AShadow's shadowColor }
function TyCanvasGroundOf(AShadow: TTyChartColor): TTyCanvasGround;
{ [R7-Z] what a run leaves the canvas holding: the ground of what is drawn
  after it on the same canvas }
function TyCanvasGroundOfRun(const ARun: TTyCanvasRun): TTyCanvasGround;
procedure TyCanvasRunStart(out ARun: TTyCanvasRun; const AGround: TTyCanvasGround;
  APPI: Integer);
procedure TyCanvasRunStep(var ARun: TTyCanvasRun; var AEl: TTyChartElement);
procedure TyLinesCanvasLeftovers(AList: TTyPaintList; const AGround: TTyCanvasGround;
  APPI: Integer); overload;
{ [R7-W] whether AEl holds a value the canvas refuses (a dirty rect's block
  must settle it afresh) }
function TyCanvasElementCarries(const AEl: TTyChartElement): Boolean;
{ [R7-Y] THE TRANSFORM AN ELEMENT HANDS THE CANVAS (device px), False for
  none: a lines effect symbol's place, a caption's anchor and turn, one
  handed over (CanvasM), a symbol's frame (HitM), an own-frame path's (the
  inverse of ZrHit.ToLocal) -- what setContextTransform sets for it, and
  the frame its fill's pattern lies in }
function TyElementCanvasTransform(const AEl: TTyChartElement; out AM: TTyMat2D): Boolean;
{ [R7-Y] A PATTERN IN AN ELEMENT'S FRAME: APm (pattern px to css px) put
  under the transform AM (device px, ADs device px per css px) }
procedure TyPatternUnder(const AM: TTyMat2D; ADs: Double; var APm: TTyDoubleArray);

{ ---- zrender's containStroke ---- }
function TyLinesContainLine(X0, Y0, X1, Y1, ALineWidth, AX, AY: Double): Boolean;
function TyLinesContainQuad(X0, Y0, X1, Y1, X2, Y2, ALineWidth, AX, AY: Double): Boolean;
{ curve.quadraticAt / quadraticDerivativeAt as zrender writes them }
function TyLinesQuadAt(AP0, AP1, AP2, AT: Double): Double;
function TyLinesQuadDerivAt(AP0, AP1, AP2, AT: Double): Double;

implementation

uses tyControls.AdvanceChart.JsMath, tyControls.AdvanceChart.Data,
  tyControls.AdvanceChart.Scale, tyControls.AdvanceChart.Symbol,
  tyControls.AdvanceChart.ZrPath, tyControls.AdvanceChart.GfxEl, tyControls.FontUnits;

const
  cPi: Double = 3.141592653589793;

procedure PlaceLocalGrad(var AEl: TTyChartElement; ASX, ASY, ARot, AX, AY: Double); forward;

{ ==================== JSON ==================== }

function TyLinesJsNum(AData: TJSONData): Double;
begin
  Result := NaN;
  if AData = nil then Exit;
  case AData.JSONType of
    jtNumber: Result := AData.AsFloat;
    jtBoolean: if AData.AsBoolean then Result := 1 else Result := 0;
    jtString: Result := TyJsToNumber(AData.AsString);
    jtNull: Result := 0;
    jtArray:
      if AData.Count = 0 then Result := 0
      else if AData.Count = 1 then Result := TyLinesJsNum(AData.Items[0]);
  end;
end;

function TyLinesJsTruthy(AData: TJSONData): Boolean;
var v: Double;
begin
  Result := False;
  if AData = nil then Exit;
  case AData.JSONType of
    jtNull: Result := False;
    jtBoolean: Result := AData.AsBoolean;
    jtNumber:
      begin
        v := AData.AsFloat;
        Result := not IsNan(v) and (v <> 0);
      end;
    jtString: Result := AData.AsString <> '';
  else
    Result := True;
  end;
end;

function ValueOf(AData: TJSONData): TTyLinesValue;
begin
  Result := Default(TTyLinesValue);
  Result.Num := NaN;
  if AData = nil then
  begin
    Result.Kind := lvkNull;
    Exit;
  end;
  case AData.JSONType of
    jtNumber:
      begin
        Result.Kind := lvkNumber;
        Result.Num := AData.AsFloat;
      end;
    jtString:
      begin
        Result.Kind := lvkString;
        Result.Str := AData.AsString;
      end;
    jtNull: Result.Kind := lvkNull;
  else
    Result.Kind := lvkOther;
  end;
end;

function NumValue(AValue: Double): TTyLinesValue;
begin
  Result := Default(TTyLinesValue);
  Result.Kind := lvkNumber;
  Result.Num := AValue;
end;

function FindIn(ANode: TJSONObject; const APath: array of string): TJSONData;
var i: Integer; d: TJSONData;
begin
  Result := nil;
  d := ANode;
  for i := 0 to High(APath) do
  begin
    if not (d is TJSONObject) then Exit;
    d := TJSONObject(d).Find(APath[i]);
    if d = nil then Exit;
  end;
  if (d <> nil) and (d.JSONType = jtNull) then Exit;
  Result := d;
end;

function TyLinesItemFind(const ARaw: TTyLinesRaw;
  const APath: array of string): TJSONData;
begin
  Result := nil;
  if ARaw.Item <> nil then Result := FindIn(ARaw.Item, APath);
  if (Result = nil) and (ARaw.Item2 <> nil) then Result := FindIn(ARaw.Item2, APath);
end;

function TyLinesFind(const ARaw: TTyLinesRaw; ASeries: TJSONObject;
  const APath: array of string): TJSONData;
begin
  Result := TyLinesItemFind(ARaw, APath);
  if (Result = nil) and (ASeries <> nil) then Result := FindIn(ASeries, APath);
end;

function StrOf(AData: TJSONData; out AHas: Boolean): string;
begin
  Result := '';
  AHas := False;
  if AData = nil then Exit;
  case AData.JSONType of
    jtString: Result := AData.AsString;
    jtNumber: Result := TyJsNumberToString(AData.AsFloat);
    jtBoolean: if AData.AsBoolean then Result := 'true' else Result := 'false';
  else
    Exit;
  end;
  AHas := True;
end;

{ the coordinates of an item's `coords` or a bare array: [[x, y], ...] }
function NameValue(const AName: string): TTyLinesValue;
begin
  Result := Default(TTyLinesValue);
  Result.Kind := lvkName;
  Result.Num := NaN;
  Result.Str := AName;
end;

procedure ReadCoords(AData: TJSONData; var ARaw: TTyLinesRaw);
var i, n: Integer; p: TJSONData;
begin
  ARaw.XY := nil;
  if not (AData is TJSONArray) then Exit;
  n := AData.Count;
  SetLength(ARaw.XY, n * 2);
  for i := 0 to n - 1 do
  begin
    p := TJSONArray(AData).Items[i];
    { [spec 242] a coordinate that is one string }
    if (p <> nil) and (p.JSONType = jtString) then
    begin
      ARaw.XY[i * 2] := NameValue(p.AsString);
      ARaw.XY[i * 2 + 1] := NameValue(p.AsString);
      Continue;
    end;
    if (p is TJSONArray) and (p.Count >= 1) then ARaw.XY[i * 2] := ValueOf(p.Items[0])
    else ARaw.XY[i * 2] := ValueOf(nil);
    if (p is TJSONArray) and (p.Count >= 2) then ARaw.XY[i * 2 + 1] := ValueOf(p.Items[1])
    else ARaw.XY[i * 2 + 1] := ValueOf(nil);
  end;
end;

function TyLinesRawsOf(ASeries: TJSONObject): TTyLinesRawArray;
var
  data, it, v, c0, c1: TJSONData;
  i, k, n, cnt, at: Integer;
  r: TTyLinesRaw;
  flat, ec2: Boolean;
  has: Boolean;

  procedure Names(var AR: TTyLinesRaw);
  var h: Boolean; s: string;
  begin
    s := StrOf(TyLinesItemFind(AR, ['name']), h);
    AR.Name := s;
    AR.HasName := h;
    s := StrOf(TyLinesItemFind(AR, ['fromName']), h);
    AR.FromName := s;
    AR.HasFromName := h;
    s := StrOf(TyLinesItemFind(AR, ['toName']), h);
    AR.ToName := s;
    AR.HasToName := h;
  end;

begin
  Result := nil;
  if ASeries = nil then Exit;
  data := ASeries.Find('data');
  if not (data is TJSONArray) then Exit;
  n := data.Count;
  if n = 0 then Exit;
  { THE FLAT FORM: a number first (_processFlatCoordsArray) }
  flat := TJSONArray(data).Items[0].JSONType = jtNumber;
  if flat then
  begin
    i := 0;
    while i < n do
    begin
      r := Default(TTyLinesRaw);
      r.RawIsFlat := True;
      r.Value := 0;
      cnt := 0;
      if TJSONArray(data).Items[i].JSONType = jtNumber then
        cnt := Trunc(TJSONArray(data).Items[i].AsFloat);
      Inc(i);
      if cnt < 0 then cnt := 0;
      SetLength(r.XY, cnt * 2);
      for k := 0 to cnt * 2 - 1 do
      begin
        if i < n then r.XY[k] := ValueOf(TJSONArray(data).Items[i])
        else r.XY[k] := NumValue(NaN);
        Inc(i);
      end;
      at := Length(Result);
      SetLength(Result, at + 1);
      Result[at] := r;
    end;
    Exit;
  end;
  { ECHARTS 2's PAIRS: data[0][0].coord }
  it := TJSONArray(data).Items[0];
  ec2 := (it is TJSONArray) and (it.Count > 0) and (TJSONArray(it).Items[0] is TJSONObject)
    and (TJSONObject(TJSONArray(it).Items[0]).Find('coord') <> nil)
    and (TJSONObject(TJSONArray(it).Items[0]).Find('coord').JSONType <> jtNull);
  SetLength(Result, n);
  for i := 0 to n - 1 do
  begin
    r := Default(TTyLinesRaw);
    r.Value := NaN;
    it := TJSONArray(data).Items[i];
    if ec2 then
    begin
      { coords from the two points' `coord`, the names from their `name`s,
        the rest merged without overwriting: the first point's keys win }
      if (it is TJSONArray) and (it.Count > 0) and (TJSONArray(it).Items[0] is TJSONObject) then
        r.Item := TJSONObject(TJSONArray(it).Items[0]);
      if (it is TJSONArray) and (it.Count > 1) and (TJSONArray(it).Items[1] is TJSONObject) then
        r.Item2 := TJSONObject(TJSONArray(it).Items[1]);
      SetLength(r.XY, 4);
      c0 := nil;
      c1 := nil;
      if r.Item <> nil then c0 := r.Item.Find('coord');
      if r.Item2 <> nil then c1 := r.Item2.Find('coord');
      for k := 0 to 1 do
      begin
        if (c0 is TJSONArray) and (c0.Count > k) then r.XY[k] := ValueOf(TJSONArray(c0).Items[k])
        else if (c0 <> nil) and (c0.JSONType = jtString) then r.XY[k] := NameValue(c0.AsString)
        else r.XY[k] := ValueOf(nil);
        if (c1 is TJSONArray) and (c1.Count > k) then r.XY[2 + k] := ValueOf(TJSONArray(c1).Items[k])
        else if (c1 <> nil) and (c1.JSONType = jtString) then r.XY[2 + k] := NameValue(c1.AsString)
        else r.XY[2 + k] := ValueOf(nil);
      end;
      { `fromName` / `toName` are the two points' names; the merged item's
        `name` is the first one's (mergeAll does not overwrite) }
      Names(r);
      if (r.Item <> nil) then
      begin
        r.FromName := StrOf(FindIn(r.Item, ['name']), has);
        r.HasFromName := has;
      end;
      if (r.Item2 <> nil) then
      begin
        r.ToName := StrOf(FindIn(r.Item2, ['name']), has);
        r.HasToName := has;
      end;
    end
    else if it is TJSONArray then
    begin
      { a bare coords array: no options, the value not a number, the raw
        value the array }
      ReadCoords(it, r);
      r.RawJson := it;
    end
    else if it is TJSONObject then
    begin
      r.Item := TJSONObject(it);
      ReadCoords(r.Item.Find('coords'), r);
      Names(r);
    end;
    if r.Item <> nil then
    begin
      v := TyLinesItemFind(r, ['value']);
      if v = nil then r.RawNone := True
      else
      begin
        r.RawJson := v;
        if v is TJSONArray then
        begin
          if v.Count > 0 then r.Value := TyLinesJsNum(TJSONArray(v).Items[0]);
        end
        else r.Value := TyLinesJsNum(v);
        if v.JSONType = jtBoolean then r.Value := NaN;
      end;
    end
    else if not (it is TJSONArray) then
      r.RawNone := True;
    Result[i] := r;
  end;
end;

{ ==================== the layout ==================== }

function TyLinesCurvenessOf(const ARaw: TTyLinesRaw; ASeries: TJSONObject): Double;
var d: TJSONData;
begin
  d := TyLinesFind(ARaw, ASeries, ['lineStyle', 'curveness']);
  if d = nil then Exit(0);
  Result := TyLinesJsNum(d);
  if d.JSONType = jtNull then Result := 0;
  if IsNan(Result) then Result := 0;
end;

function TyLinesLayoutRow(const ARaw: TTyLinesRaw; ARow: Integer;
  APolyline: Boolean; ACurveness: Double; AProject: TTyLinesProject): TTyLinesGeom;
var j, n: Integer; p0, p1: TTyPointF; mask: TFPUExceptionMask;
begin
  Result := Default(TTyLinesGeom);
  Result.Row := ARow;
  n := Length(ARaw.XY) div 2;
  mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
    if APolyline then
    begin
      SetLength(Result.Pts, n);
      for j := 0 to n - 1 do
        Result.Pts[j] := AProject(ARaw.XY[j * 2], ARaw.XY[j * 2 + 1], True);
    end
    else
    begin
      SetLength(Result.Pts, 2);
      if n >= 1 then Result.Pts[0] := AProject(ARaw.XY[0], ARaw.XY[1], True)
      else Result.Pts[0] := TyPointF(NaN, NaN);
      if n >= 2 then Result.Pts[1] := AProject(ARaw.XY[2], ARaw.XY[3], True)
      else Result.Pts[1] := TyPointF(NaN, NaN);
      { `if (+curveness)` }
      if (ACurveness <> 0) and not IsNan(ACurveness) then
      begin
        p0 := Result.Pts[0];
        p1 := Result.Pts[1];
        Result.Curved := True;
        Result.CP := TyPointF(
          (p0.X + p1.X) / 2 - (p0.Y - p1.Y) * ACurveness,
          (p0.Y + p1.Y) / 2 - (p1.X - p0.X) * ACurveness);
      end;
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
  { lineNeedsDraw: the first two points are numbers }
  Result.Drawn := (Length(Result.Pts) >= 2)
    and not (IsNan(Result.Pts[0].X) or IsNan(Result.Pts[0].Y)
      or IsNan(Result.Pts[1].X) or IsNan(Result.Pts[1].Y));
end;

function TyLinesLargeSegs(const ARaws: TTyLinesRawArray; APolyline: Boolean;
  AProject: TTyLinesProject): TTyDoubleArray;
var i, k, n, at, total: Integer; p: TTyPointF;
begin
  Result := nil;
  if APolyline then
  begin
    total := 0;
    for i := 0 to High(ARaws) do Inc(total, 1 + (Length(ARaws[i].XY) div 2) * 2);
    SetLength(Result, total);
  end
  else
    SetLength(Result, Length(ARaws) * 4);
  at := 0;
  for i := 0 to High(ARaws) do
  begin
    n := Length(ARaws[i].XY) div 2;
    if APolyline then
    begin
      Result[at] := n;
      Inc(at);
    end
    else
      n := Min(n, 2);
    for k := 0 to n - 1 do
    begin
      p := AProject(ARaws[i].XY[k * 2], ARaws[i].XY[k * 2 + 1], False);
      Result[at] := TyLargeF32(p.X);
      Result[at + 1] := TyLargeF32(p.Y);
      Inc(at, 2);
    end;
    { a line of fewer than two points leaves its Float32 zeros }
    if not APolyline then
      while at < (i + 1) * 4 do
      begin
        Result[at] := 0;
        Inc(at);
      end;
  end;
end;

{ ==================== Line.ts geometry ==================== }

function TyLinesQuadAt(AP0, AP1, AP2, AT: Double): Double;
var onet: Double;
begin
  onet := 1 - AT;
  Result := onet * (onet * AP0 + 2 * AT * AP1) + AT * AT * AP2;
end;

function TyLinesQuadDerivAt(AP0, AP1, AP2, AT: Double): Double;
begin
  Result := 2 * ((1 - AT) * (AP1 - AP0) + AT * (AP2 - AP1));
end;

{ vec2.normalize: a zero length is (0, 0) }
function Normalize(AX, AY: Double): TTyPointF;
var d: Double;
begin
  d := Sqrt(AX * AX + AY * AY);
  if d = 0 then Exit(TyPointF(0, 0));
  Result := TyPointF(AX / d, AY / d);
end;

function TyLinesPointAt(const AG: TTyLinesGeom; AT: Double): TTyPointF;
begin
  if Length(AG.Pts) < 2 then Exit(TyPointF(NaN, NaN));
  if not AG.Curved then
    Exit(TyPointF(AG.Pts[0].X * (1 - AT) + AG.Pts[1].X * AT,
      AG.Pts[0].Y * (1 - AT) + AG.Pts[1].Y * AT));
  Result := TyPointF(TyLinesQuadAt(AG.Pts[0].X, AG.CP.X, AG.Pts[1].X, AT),
    TyLinesQuadAt(AG.Pts[0].Y, AG.CP.Y, AG.Pts[1].Y, AT));
end;

function TyLinesTangentAt(const AG: TTyLinesGeom; AT: Double): TTyPointF;
var p: TTyPointF;
begin
  if Length(AG.Pts) < 2 then Exit(TyPointF(NaN, NaN));
  if not AG.Curved then
    Exit(Normalize(AG.Pts[1].X - AG.Pts[0].X, AG.Pts[1].Y - AG.Pts[0].Y));
  p := Normalize(TyLinesQuadDerivAt(AG.Pts[0].X, AG.CP.X, AG.Pts[1].X, AT),
    TyLinesQuadDerivAt(AG.Pts[0].Y, AG.CP.Y, AG.Pts[1].Y, AT));
  Result := Normalize(p.X, p.Y);
end;

function TyLinesSymbolRotation(const AG: TTyLinesGeom; AAtEnd: Boolean): Double;
var tg: TTyPointF; sign: Double; mask: TFPUExceptionMask;
begin
  mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
    if AAtEnd then
    begin
      tg := TyLinesTangentAt(AG, 1);
      sign := -1;
    end
    else
    begin
      tg := TyLinesTangentAt(AG, 0);
      sign := 1;
    end;
    Result := sign * cPi / 2 - TyJsAtan2(tg.Y, tg.X);
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

function TyLinesLabelPosOf(const AWord: string): TTyLinesLabelPos;
begin
  if AWord = 'start' then Exit(llpStart);
  if AWord = 'end' then Exit(llpEnd);
  if AWord = 'insideStart' then Exit(llpInsideStart);
  if AWord = 'insideStartTop' then Exit(llpInsideStartTop);
  if AWord = 'insideStartBottom' then Exit(llpInsideStartBottom);
  if AWord = 'insideMiddle' then Exit(llpInsideMiddle);
  if AWord = 'insideMiddleTop' then Exit(llpInsideMiddleTop);
  if AWord = 'insideMiddleBottom' then Exit(llpInsideMiddleBottom);
  if AWord = 'insideEnd' then Exit(llpInsideEnd);
  if AWord = 'insideEndTop' then Exit(llpInsideEndTop);
  if AWord = 'insideEndBottom' then Exit(llpInsideEndBottom);
  { `position || 'middle'`, and any other word falls through every case:
    the label stays at the origin it was reset to }
  Result := llpMiddle;
end;

procedure TyLinesLabelPlace(const AG: TTyLinesGeom; APercent: Double;
  APos: TTyLinesLabelPos; ADistX, ADistY: Double;
  out AX, AY, AOX, AOY, ARot, AAnchorX, AAnchorY: Double;
  out AAH: TTyTextAnchorH; out AAV: TTyTextAnchorV);
begin
  TyLinesLabelPlace(AG, APercent, APos, ADistX, ADistY, False, 0, False, 0, 0,
    AX, AY, AOX, AOY, ARot, AAnchorX, AAnchorY, AAH, AAV);
end;

procedure TyLinesLabelPlace(const AG: TTyLinesGeom; APercent: Double;
  APos: TTyLinesLabelPos; ADistX, ADistY: Double; AHasRot: Boolean;
  ARotate: Double; AHasOff: Boolean; AOffX, AOffY: Double;
  out AX, AY, AOX, AOY, ARot, AAnchorX, AAnchorY: Double;
  out AAH: TTyTextAnchorH; out AAV: TTyTextAnchorV);
var
  fromP, toP, d, tg, cp: TTyPointF;
  half, dy, x, y, ox, oy, dir, st, ct, l4, l5, aa, ab, ac, ad, atx, aty: Double;
  L: array[0..5] of Double;
  mask: TFPUExceptionMask;
begin
  mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
    fromP := TyLinesPointAt(AG, 0);
    toP := TyLinesPointAt(AG, APercent);
    d := Normalize(toP.X - fromP.X, toP.Y - fromP.Y);
    half := APercent / 2;
    tg := TyLinesTangentAt(AG, half);
    cp := TyLinesPointAt(AG, half);
    if tg.X < 0 then dir := -1 else dir := 1;
    ARot := 0;
    if not (APos in [llpStart, llpEnd]) then
    begin
      ARot := -TyJsAtan2(tg.Y, tg.X);
      if toP.X < fromP.X then ARot := cPi + ARot;
    end;
    case APos of
      llpInsideStartTop, llpInsideMiddleTop, llpInsideEndTop, llpMiddle:
        begin
          dy := -ADistY;
          AAV := tavBottom;
        end;
      llpInsideStartBottom, llpInsideMiddleBottom, llpInsideEndBottom:
        begin
          dy := ADistY;
          AAV := tavTop;
        end;
    else
      dy := 0;
      AAV := tavMiddle;
    end;
    x := 0;
    y := 0;
    ox := 0;
    oy := 0;
    AAH := tahLeft;
    case APos of
      llpEnd:
        begin
          x := d.X * ADistX + toP.X;
          y := d.Y * ADistY + toP.Y;
          if d.X > 0.8 then AAH := tahLeft
          else if d.X < -0.8 then AAH := tahRight
          else AAH := tahCentre;
          if d.Y > 0.8 then AAV := tavTop
          else if d.Y < -0.8 then AAV := tavBottom
          else AAV := tavMiddle;
        end;
      llpStart:
        begin
          x := -d.X * ADistX + fromP.X;
          y := -d.Y * ADistY + fromP.Y;
          if d.X > 0.8 then AAH := tahRight
          else if d.X < -0.8 then AAH := tahLeft
          else AAH := tahCentre;
          if d.Y > 0.8 then AAV := tavBottom
          else if d.Y < -0.8 then AAV := tavTop
          else AAV := tavMiddle;
        end;
      llpInsideStartTop, llpInsideStart, llpInsideStartBottom:
        begin
          x := ADistX * dir + fromP.X;
          y := fromP.Y + dy;
          if tg.X < 0 then AAH := tahRight else AAH := tahLeft;
          ox := -ADistX * dir;
          oy := -dy;
        end;
      llpInsideMiddleTop, llpInsideMiddle, llpInsideMiddleBottom, llpMiddle:
        begin
          x := cp.X;
          y := cp.Y + dy;
          AAH := tahCentre;
          oy := -dy;
        end;
      llpInsideEndTop, llpInsideEnd, llpInsideEndBottom:
        begin
          x := -ADistX * dir + toP.X;
          y := toP.Y + dy;
          if tg.X >= 0 then AAH := tahRight else AAH := tahLeft;
          ox := ADistX * dir;
          oy := -dy;
        end;
    end;
    { [spec 242] textConfig over beforeUpdate's: the rotation where it is
      written, the offset onto the position with the origin at minus it
      (`if (textOffset)`; no textConfig.origin here) }
    if AHasRot then ARot := ARotate;
    if AHasOff then
    begin
      x := x + AOffX;
      y := y + AOffY;
      ox := -AOffX;
      oy := -AOffY;
    end;
    AX := x;
    AY := y;
    AOX := ox;
    AOY := oy;
    { getLocalTransform with scale 1: the origin's translation, the
      rotation, then the position -- every zero term kept, as zrender keeps
      it (a rotation of the origin's offset is what moves an inside label);
      `originX || 0`, `rotation && rotate`: a not-a-number is nought }
    if IsNan(ox) then ox := 0;
    if IsNan(oy) then oy := 0;
    if (ox <> 0) or (oy <> 0) then
    begin
      L[4] := -ox * 1 - 0 * oy * 1;
      L[5] := -oy * 1 - 0 * ox * 1;
    end
    else
    begin
      L[4] := 0;
      L[5] := 0;
    end;
    L[0] := 1;
    L[3] := 1;
    L[1] := 0;
    L[2] := 0;
    if (ARot <> 0) and not IsNan(ARot) then
    begin
      aa := L[0]; ac := L[2]; atx := L[4];
      ab := L[1]; ad := L[3]; aty := L[5];
      st := TyJsSin(ARot);
      ct := TyJsCos(ARot);
      L[0] := aa * ct + ab * st;
      L[1] := -aa * st + ab * ct;
      L[2] := ac * ct + ad * st;
      L[3] := -ac * st + ct * ad;
      { matrix.rotate about the pivot [0, 0]: (atx - 0) ... + 0 }
      L[4] := ct * (atx - 0) + st * (aty - 0) + 0;
      L[5] := ct * (aty - 0) - st * (atx - 0) + 0;
    end;
    l4 := L[4] + (ox + x);
    l5 := L[5] + (oy + y);
    AAnchorX := l4;
    AAnchorY := l5;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

function TyLinesPartPoints(const AG: TTyLinesGeom; APercent: Double;
  ASteps: Integer; ASnapWidth: Double): TTyPointFArray;
var
  k: Integer;
  p0, p1, p2, q0, q1: TTyPointF;
  t, u, x1, y1, x2, y2: Double;
begin
  Result := nil;
  if Length(AG.Pts) < 2 then Exit;
  if not AG.Curved then
  begin
    { [R7-G] Line.buildPath with subPixelOptimize (createLine): the shape
      first, both ends, by the line's width -- then the percent }
    x1 := AG.Pts[0].X;
    y1 := AG.Pts[0].Y;
    x2 := AG.Pts[1].X;
    y2 := AG.Pts[1].Y;
    TyZrSubPixelOptimizeLine(x1, y1, x2, y2, ASnapWidth);
    { Line.buildPath: x1 * (1 - p) + x2 * p }
    SetLength(Result, 2);
    Result[0] := TyPointF(x1, y1);
    if APercent < 1 then
      Result[1] := TyPointF(x1 * (1 - APercent) + x2 * APercent,
        y1 * (1 - APercent) + y2 * APercent)
    else
      Result[1] := TyPointF(x2, y2);
    Exit;
  end;
  { BezierCurve.buildPath under 1: quadraticSubdivide at percent, the first
    part -- a quadratic of its own, sampled }
  p0 := AG.Pts[0];
  p1 := AG.CP;
  p2 := AG.Pts[1];
  t := APercent;
  if t > 1 then t := 1;
  q0 := TyPointF((p1.X - p0.X) * t + p0.X, (p1.Y - p0.Y) * t + p0.Y);
  q1 := TyPointF(TyLinesQuadAt(p0.X, p1.X, p2.X, t), TyLinesQuadAt(p0.Y, p1.Y, p2.Y, t));
  if ASteps < 1 then ASteps := 1;
  SetLength(Result, ASteps + 1);
  for k := 0 to ASteps do
  begin
    u := k / ASteps;
    Result[k] := TyPointF(TyLinesQuadAt(p0.X, q0.X, q1.X, u),
      TyLinesQuadAt(p0.Y, q0.Y, q1.Y, u));
  end;
end;

{ ==================== the effect ==================== }

function Dist(const A, B: TTyPointF): Double;
begin
  Result := Sqrt((A.X - B.X) * (A.X - B.X) + (A.Y - B.Y) * (A.Y - B.Y));
end;

procedure TyLinesEffectInit(var AE: TTyLinesEffect; const AG: TTyLinesGeom;
  APolyline: Boolean; const ASymbolType: string; AScaleW, AScaleH: Double);
var i: Integer; len: Double; acc: TTyDoubleArray;
begin
  AE.Poly := APolyline;
  { createSymbol at the origin, hidden until its clip's first during }
  AE.X := 0;
  AE.Y := 0;
  AE.Rotation := 0;
  AE.Ignore := True;
  AE.HasLastT := False;
  AE.LastT := 0;
  AE.T := 0;
  AE.LastFrame := 0;
  AE.LastFramePercent := 0;
  AE.Trail := (ASymbolType = 'line') or (ASymbolType = 'rect')
    or (ASymbolType = 'roundRect');
  AE.ScaleW := AScaleW;
  AE.ScaleH := AScaleH;
  AE.ScaleX := AScaleW;
  AE.ScaleY := AScaleH;
  if not APolyline then
  begin
    if Length(AG.Pts) >= 2 then
    begin
      AE.P1 := AG.Pts[0];
      AE.P2 := AG.Pts[1];
    end;
    if AG.Curved then AE.CP1 := AG.CP
    else AE.CP1 := TyPointF((AE.P1.X + AE.P2.X) / 2, (AE.P1.Y + AE.P2.Y) / 2);
    Exit;
  end;
  { EffectPolyline: the cumulative lengths over the total; a polyline of no
    length keeps the offsets it had (none: the symbol never shows) }
  AE.Points := Copy(AG.Pts, 0, Length(AG.Pts));
  SetLength(acc, 1);
  acc[0] := 0;
  len := 0;
  for i := 1 to High(AG.Pts) do
  begin
    len := len + Dist(AG.Pts[i - 1], AG.Pts[i]);
    SetLength(acc, Length(acc) + 1);
    acc[High(acc)] := len;
  end;
  if len = 0 then
  begin
    AE.PolyLength := 0;
    Exit;
  end;
  for i := 0 to High(acc) do acc[i] := acc[i] / len;
  AE.Offsets := acc;
  AE.HasOffsets := True;
  AE.PolyLength := len;
end;

function TyLinesEffectLength(const AE: TTyLinesEffect): Double;
begin
  if AE.Poly then Result := AE.PolyLength
  else Result := Dist(AE.P1, AE.CP1) + Dist(AE.CP1, AE.P2);
end;

procedure StepLine(var AE: TTyLinesEffect; ABigT: Double);
var
  t, px, py, tx, ty, lastX, lastY: Double;
begin
  if ABigT <= 1 then t := ABigT else t := 2 - ABigT;
  lastX := AE.X;
  lastY := AE.Y;
  px := TyLinesQuadAt(AE.P1.X, AE.CP1.X, AE.P2.X, t);
  py := TyLinesQuadAt(AE.P1.Y, AE.CP1.Y, AE.P2.Y, t);
  if ABigT <= 1 then
  begin
    tx := TyLinesQuadDerivAt(AE.P1.X, AE.CP1.X, AE.P2.X, t);
    ty := TyLinesQuadDerivAt(AE.P1.Y, AE.CP1.Y, AE.P2.Y, t);
  end
  else
  begin
    tx := TyLinesQuadDerivAt(AE.P2.X, AE.CP1.X, AE.P1.X, 1 - t);
    ty := TyLinesQuadDerivAt(AE.P2.Y, AE.CP1.Y, AE.P1.Y, 1 - t);
  end;
  AE.Rotation := -TyJsAtan2(ty, tx) - cPi / 2;
  { the continuity trail for 'line', 'rect' and 'roundRect' }
  if AE.Trail then
  begin
    if AE.HasLastT and (AE.LastT < ABigT) then
    begin
      AE.ScaleY := Dist(TyPointF(lastX, lastY), TyPointF(px, py)) * 1.05;
      { the last segment stays inside the end point }
      if t = 1 then
      begin
        px := lastX + (px - lastX) / 2;
        py := lastY + (py - lastY) / 2;
      end;
    end
    else if AE.HasLastT and (AE.LastT = 1) then
      { after the first loop __t does not start at 0: p1 to the point }
      AE.ScaleY := 2 * Dist(AE.P1, TyPointF(px, py))
    else
      AE.ScaleY := AE.ScaleH;
  end;
  AE.HasLastT := True;
  AE.LastT := ABigT;
  AE.Ignore := False;
  AE.X := px;
  AE.Y := py;
end;

procedure StepPoly(var AE: TTyLinesEffect; ABigT: Double);
var
  t, p, tx, ty: Double;
  n, frame, start: Integer;
  p0, p1: TTyPointF;

  function Off(AIndex: Integer): Double;
  begin
    if (AIndex < 0) or (AIndex > High(AE.Offsets)) then Result := NaN
    else Result := AE.Offsets[AIndex];
  end;

  function Pt(AIndex: Integer): TTyPointF;
  begin
    if (AIndex < 0) or (AIndex > High(AE.Points)) then Result := TyPointF(NaN, NaN)
    else Result := AE.Points[AIndex];
  end;

begin
  if ABigT <= 1 then t := ABigT else t := 2 - ABigT;
  n := Length(AE.Points);
  { a polyline of no length: no offsets, the symbol stays hidden }
  if not AE.HasOffsets then Exit;
  if t < AE.LastFramePercent then
  begin
    { start from the next frame, back down to the first offset not past t }
    start := Min(AE.LastFrame + 1, n - 1);
    frame := start;
    while frame >= 0 do
    begin
      if Off(frame) <= t then Break;
      Dec(frame);
    end;
    frame := Min(frame, n - 2);
  end
  else
  begin
    frame := AE.LastFrame;
    while frame < n do
    begin
      if Off(frame) > t then Break;
      Inc(frame);
    end;
    frame := Min(frame - 1, n - 2);
  end;
  p := (t - Off(frame)) / (Off(frame + 1) - Off(frame));
  p0 := Pt(frame);
  p1 := Pt(frame + 1);
  AE.X := p0.X * (1 - p) + p * p1.X;
  AE.Y := p0.Y * (1 - p) + p * p1.Y;
  if ABigT <= 1 then
  begin
    tx := p1.X - p0.X;
    ty := p1.Y - p0.Y;
  end
  else
  begin
    tx := p0.X - p1.X;
    ty := p0.Y - p1.Y;
  end;
  AE.Rotation := -TyJsAtan2(ty, tx) - cPi / 2;
  AE.LastFrame := frame;
  AE.LastFramePercent := t;
  AE.Ignore := False;
end;

procedure TyLinesEffectStep(var AE: TTyLinesEffect; AT: Double);
var mask: TFPUExceptionMask;
begin
  if AE.Poisoned then AT := NaN;
  AE.T := AT;
  mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
    if AE.Poly then StepPoly(AE, AT)
    else StepLine(AE, AT);
    { [R7-W] a transform that inverts: the inverse the hit keeps }
    if not (AE.Ignore or IsNan(AE.X) or IsNan(AE.Y) or IsNan(AE.ScaleX) or IsNan(AE.ScaleY)
      or IsNan(AE.Rotation) or IsInfinite(AE.ScaleX) or IsInfinite(AE.ScaleY))
      and (AE.ScaleX <> 0) and (AE.ScaleY <> 0) then
    begin
      AE.HasInv := True;
      AE.InvX := AE.X;
      AE.InvY := AE.Y;
      AE.InvSX := AE.ScaleX;
      AE.InvSY := AE.ScaleY;
      AE.InvRot := AE.Rotation;
    end;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

function TyLinesTrailAlpha(ATrailLength: Double): Double;
begin
  Result := ATrailLength / 10 + 0.9;
  if IsNan(Result) then Exit(NaN);
  if Result > 1 then Result := 1;
  if Result < 0 then Result := 0;
end;

{ ==================== the paint list ==================== }

const
  { a curve's points for the hit ribbon and the drawing }
  cLinesCurveSteps = 32;

{ the geometry an element carries in G[0..6] }
function GeomOfG(const AEl: TTyChartElement): TTyLinesGeom;
begin
  Result := Default(TTyLinesGeom);
  SetLength(Result.Pts, 2);
  Result.Pts[0] := TyPointF(AEl.Anim.G[0], AEl.Anim.G[1]);
  Result.Pts[1] := TyPointF(AEl.Anim.G[2], AEl.Anim.G[3]);
  Result.Curved := AEl.Anim.G[6] <> 0;
  Result.CP := TyPointF(AEl.Anim.G[4], AEl.Anim.G[5]);
  Result.Drawn := True;
end;

procedure PutGeom(var AEl: TTyChartElement; const AG: TTyLinesGeom);
begin
  if Length(AG.Pts) >= 2 then
  begin
    AEl.Anim.G[0] := AG.Pts[0].X;
    AEl.Anim.G[1] := AG.Pts[0].Y;
    AEl.Anim.G[2] := AG.Pts[1].X;
    AEl.Anim.G[3] := AG.Pts[1].Y;
  end;
  if AG.Curved then
  begin
    AEl.Anim.G[4] := AG.CP.X;
    AEl.Anim.G[5] := AG.CP.Y;
    AEl.Anim.G[6] := 1;
  end
  else
  begin
    AEl.Anim.G[4] := NaN;
    AEl.Anim.G[5] := NaN;
    AEl.Anim.G[6] := 0;
  end;
  { [spec 242] a Line's updateProps of its shape in an update: the line,
    its end symbols and its label follow it }
  if (AEl.Anim.Role in [carLinesLine, carLinesFrom, carLinesTo, carLinesLabel])
    and (Length(AG.Pts) = 2) then
  begin
    AEl.Anim.TwKind := 5;
    AEl.Anim.TwRow := AEl.Anim.Index;
    AEl.Anim.TwVals := TTyDoubleArray.Create(AEl.Anim.G[0], AEl.Anim.G[1], AEl.Anim.G[2],
      AEl.Anim.G[3], AEl.Anim.G[4], AEl.Anim.G[5]);
    { a straight line's control point is undefined upstream (not tweened):
      0 here, so an unchanged line is the same values }
    if not AG.Curved then
    begin
      AEl.Anim.TwVals[4] := 0;
      AEl.Anim.TwVals[5] := 0;
    end;
  end;
end;

{ [R7-S] createSymbol's path without keepAspect: a path:// one covers the
  box (makePath 'cover'), the rest symbol.ts' own [was: TyZrSymbol's
  path:// fitted to its aspect -- a gradient's box off for an oblong one] }
function CoverSymbolPath(const AType: string; AX, AY, AW, AH: Double): TTyZrPath;
begin
  if Copy(AType, 1, 7) = 'path://' then
    Result := TyZrMakePathCover(Copy(AType, 8, MaxInt), TyXYWH(AX, AY, AW, AH))
  else
    Result := TyZrSymbol(AType, AX, AY, AW, AH);
end;

{ An end symbol: createSymbol(type, -w / 2, -h / 2, w, h) at the end, turned
  -- a circle is the real box's (min(w, h) / 2), the rest are the same
  picture either way and take the turn }
function EndSymbolShape(AKind: TTySymbolKind; AEmpty: Boolean; const APath: string;
  AW, AH, AX, AY, ARotRad: Double): TTyChartShape;
var
  spec: TTySymbolSpec;
  rot: Double;
  zp: TTyZrPath;
  cmds: TTyPathCmdArray;
  pts: TTyPointFArray;
  nm: string;
begin
  { [R7-S] A BOX WITH A SIDE OF NOUGHT (a one-number size, normalizeSymbolSize's
    [w, 0]): symbol.ts' own path in that collapsed box, turned and placed --
    nothing to fill, though a pen still draws its edge and a pin its head
    of the width [was: never this small -- a missing height took the width] }
  if not ((AW > 0) and (AH > 0)) and not IsNan(AW) and not IsNan(AH)
    and not (AKind in [tsyNone, tsyImage]) then
  begin
    if IsNan(ARotRad) then rot := 0 else rot := ARotRad;
    case AKind of
      tsyCircle: nm := 'circle';
      tsyRect: nm := 'rect';
      tsyRoundRect: nm := 'roundRect';
      tsySquare: nm := 'square';
      tsyTriangle: nm := 'triangle';
      tsyDiamond: nm := 'diamond';
      tsyPin: nm := 'pin';
      tsyArrow: nm := 'arrow';
      tsyLine: nm := 'line';
    else
      nm := '';
    end;
    if AKind = tsyPath then zp := TyZrMakePathCover(APath, TyXYWH(-AW / 2, -AH / 2, AW, AH))
    else zp := TyZrSymbol(nm, -AW / 2, -AH / 2, AW, AH);
    TyGfxPathCmds(zp, TyZrLocal(1, 1, rot, AX, AY), cmds, pts);
    if AKind = tsyLine then Result := TyShapePolyline(pts) else Result := TyShapePolygon(pts);
    Result.Cmds := cmds;
    Result.HitNonZero := True;
    Exit;
  end;
  spec := TySymbolDefault('scatter');
  spec.Kind := AKind;
  spec.Empty := AEmpty;
  spec.PathData := APath;
  spec.WidthPx := AW;
  spec.HeightPx := AH;
  spec.OffsetX := 0;
  spec.OffsetY := 0;
  if AKind = tsyCircle then
    Exit(TyBuildSymbolInBox(spec, TyRectF(AX - AW / 2, AY - AH / 2,
      AX - AW / 2 + AW, AY - AH / 2 + AH)));
  { [R7-R] AN OBLONG BOX IS ANOTHER PICTURE for a square (its side min(w,
    h) from the box's corner), a roundRect (corners of min(w, h) / 4) and a
    pin (a head three fifths of the width): the real box's path, turned
    [was: the unit box's, stretched] }
  if (AW <> AH) and (AKind in [tsySquare, tsyRoundRect, tsyPin]) then
  begin
    if IsNan(ARotRad) then rot := 0 else rot := ARotRad;
    Exit(TyBuildSymbolMappedBox(spec, AX, AY, TyZrLocal(1, 1, rot, 0, 0)));
  end;
  if not IsNan(ARotRad) then spec.RotateDeg := RadToDeg(ARotRad);
  { [R7-R] a path:// one stretched over its box (no keepAspect) }
  Result := TyBuildSymbolUnit(spec, AX, AY);
end;

{ [R7-Y] A LINES END SYMBOL'S HIT IN ITS OWN FRAME: Path.contain takes the
  point back through the symbol's transform (placed, turned, scaled by
  AScale -- the line's enter percent) and tests the path createSymbol made
  in the box (-w / 2, -h / 2, w, h), its pen there too -- a point exactly on
  a vertex or an edge as upstream's arithmetic has it [was: the drawn
  shape] }
procedure EndSymbolHitFrame(var AEl: TTyChartElement; AKind: TTySymbolKind;
  AW, AH, AScale, ARotRad, AX, AY: Double);
var nm: string; lm: TTyMat2D;
begin
  case AKind of
    tsyCircle: nm := 'circle';
    tsyRect: nm := 'rect';
    tsyRoundRect: nm := 'roundRect';
    tsySquare: nm := 'square';
    tsyTriangle: nm := 'triangle';
    tsyDiamond: nm := 'diamond';
    tsyPin: nm := 'pin';
    tsyArrow: nm := 'arrow';
  else
    Exit;
  end;
  if IsNan(AW) or IsNan(AH) or (AW < 0) or (AH < 0) or not ((AW > 0) or (AH > 0)) then Exit;
  if IsNan(ARotRad) then ARotRad := 0;
  lm := TyZrLocal(AScale, AScale, ARotRad, AX, AY);
  AEl.Shape.HitSym := nm;
  AEl.Shape.HitM := lm;
  AEl.Shape.HitBoxW := AW;
  AEl.Shape.HitBoxH := AH;
  AEl.Shape.HitPenInFrame := True;
end;

{ The effect symbol: createSymbol(type, -0.5, -0.5, 1, 1) scaled by (sx, sy),
  turned and placed -- the unit box's picture }
function EffectShape(const AName: string; ASX, ASY, AX, AY, ARotRad: Double): TTyChartShape;
var spec: TTySymbolSpec; em: Boolean; pd: string;
begin
  spec := TySymbolDefault('scatter');
  spec.Kind := TySymbolKindOf(AName, em, pd);
  spec.Empty := em;
  spec.PathData := pd;
  spec.WidthPx := ASX;
  spec.HeightPx := ASY;
  spec.OffsetX := 0;
  spec.OffsetY := 0;
  if not IsNan(ARotRad) then spec.RotateDeg := RadToDeg(ARotRad);
  { [R7-R] a path:// one stretched over its box (no keepAspect) }
  Result := TyBuildSymbolUnit(spec, AX, AY);
end;

function LinePoints(const AG: TTyLinesGeom; APoly: Boolean; APercent: Double;
  ASnapWidth: Double): TTyPointFArray;
begin
  if APoly then Exit(Copy(AG.Pts, 0, Length(AG.Pts)));
  Result := TyLinesPartPoints(AG, APercent, cLinesCurveSteps, ASnapWidth);
end;

function TyBuildLinesMarks(const ASolved: TTyLinesSolved; AEmptyFill: TTyChartColor;
  AList: TTyPaintList): Integer;
var
  i, e: Integer;
  g: TTyLinesGeom;
  ink: TTyLinesInk;
  el, sym: TTyChartElement;
  pts: TTyPointFArray;
  kind: TTySymbolKind;
  em: Boolean;
  pd: string;
  lm: TTyMat2D;
  mz2: Integer;
  at: TTyPointF;
  rot, ax, ay, ox, oy, lrot, anx, any: Double;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
  eff: TTyLinesEffect;
  flags: Integer;
  part, cg: TTyLargeGeom;
  k0, j, pat: Integer;

  procedure SetClip(var AEl: TTyChartElement);
  begin
    { [R7-I] LinesView's group clipPath: isHover asks it for every element
      of the group }
    AEl.ClipHits := ASolved.HasClip or ASolved.HasClipSector;
    if ASolved.HasClip then
    begin
      AEl.HasClip := True;
      AEl.ClipRect := ASolved.Clip;
    end;
    if ASolved.HasClipSector then
    begin
      AEl.HasClipSector := True;
      AEl.ClipCX := ASolved.ClipCX;
      AEl.ClipCY := ASolved.ClipCY;
      AEl.ClipR0 := ASolved.ClipR0;
      AEl.ClipR1 := ASolved.ClipR1;
      AEl.ClipSA := ASolved.ClipSA;
      AEl.ClipEA := ASolved.ClipEA;
      AEl.ClipCW := ASolved.ClipCW;
    end;
  end;

  { one LargeLinesPath of AGeom (AChunk: the progressive chunk that draws
    it, 0 none) }
  function AddLarge(const AGeom: TTyLargeGeom; AChunk: Integer): Integer;
  var lel: TTyChartElement;
  begin
    lel := TyChartElement(TyShapeRect(TyRectF(0, 0, 0, 0)));
    lel.Shape.Kind := cskLarge;
    lel.Shape.Large := AGeom;
    lel.Shape.Bounds := TyLargeBounds(AGeom);
    lel.Style.HasFill := False;
    lel.Style.StrokeColor := ASolved.LargeStroke;
    { [spec 242] a gradient over the batch's own bounding rect (the
      LargeLinesPath's, no pen) }
    if ASolved.LargeGrad.Kind <> cgkNone then
    begin
      lel.Style.StrokeGradient := ASolved.LargeGrad;
      lel.Style.GradBoxSet := True;
      lel.Style.GradBox := TyRectToXYWH(lel.Shape.Bounds);
    end;
    lel.Style.StrokeWidthLogical := ASolved.LargeWidth;
    lel.Style.Alpha := ASolved.LargeOpacity;
    lel.Style.DashLogical := ASolved.LargeDash;
    lel.Z := ASolved.Z;
    lel.Z2 := ASolved.Z2;
    lel.Silent := False;
    lel.Datum := TyChartDatum(ASolved.SeriesIndex, -1, -1);
    lel.ProgChunk := AChunk;
    SetClip(lel);
    AList.Add(lel);
    Result := 1;
  end;

  { [spec 242] the batch of the rows ARows: linesLayout's progress writes
    the chunk's own linesPoints (each row's floats, in the chunk's order) }
  function ChunkGeom(const ARows: TTyIntegerArray): TTyLargeGeom;
  var
    j, r, a, b, k, at: Integer;
    src: TTyDoubleArray;
  begin
    Result := ASolved.Large;
    src := ASolved.Large.Pts;
    Result.Pts := nil;
    at := 0;
    for j := 0 to High(ARows) do
    begin
      r := ARows[j];
      if (r < 0) or (r > High(ASolved.Large.Idx)) then Continue;
      a := ASolved.Large.Idx[r];
      if r < High(ASolved.Large.Idx) then b := ASolved.Large.Idx[r + 1]
      else b := Length(src);
      SetLength(Result.Pts, at + b - a);
      for k := a to b - 1 do Result.Pts[at + k - a] := src[k];
      Inc(at, b - a);
    end;
    TyLargeLinesIndex(Result);
    TyLargeSetBox(Result);
  end;

  { a batch as its first chunk shows it (the frames grow it) }
  function Grown(const AGeom: TTyLargeGeom): TTyLargeGeom;
  begin
    Result := AGeom;
    if Length(Result.ChunkEnds) > 1 then Result.Shown := Result.ChunkEnds[0]
    else Result.Shown := 0;
    TyLargeSetBox(Result);
  end;

begin
  Result := 0;
  if (AList = nil) or not ASolved.Valid then Exit;
  { LARGE: LargeLineDraw's one path, silent to nothing but its own scan;
    [spec 242] progressive, a path a chunk }
  if ASolved.IsLarge then
  begin
    if Length(ASolved.LargeChunks) = 0 then Exit(AddLarge(ASolved.Large, 0));
    { LargeLineDraw.incrementalUpdate concatenates a chunk's segs onto the
      batch added last while that holds under 2e4 numbers (its
      __startIndex stays), else starts a batch at the chunk's start: a
      batch grows a chunk at a time (ChunkEnds, as a scatter's) }
    k0 := -1;
    part := ASolved.Large;
    for e := 0 to High(ASolved.LargeChunks) do
    begin
      cg := ChunkGeom(ASolved.LargeChunks[e]);
      if (k0 >= 0) and (Length(part.Pts) < 20000) then
      begin
        pat := Length(part.Pts);
        SetLength(part.Pts, pat + Length(cg.Pts));
        for j := 0 to High(cg.Pts) do part.Pts[pat + j] := cg.Pts[j];
        TyLargeLinesIndex(part);
        SetLength(part.ChunkEnds, Length(part.ChunkEnds) + 1);
        part.ChunkEnds[High(part.ChunkEnds)] := Length(part.Idx);
        Continue;
      end;
      if k0 >= 0 then Inc(Result, AddLarge(Grown(part), k0 + 1));
      k0 := e;
      part := cg;
      part.ChunkFirst := e;
      if Length(ASolved.LargeChunks[e]) > 0 then part.Start := ASolved.LargeChunks[e][0]
      else part.Start := 0;
      SetLength(part.ChunkEnds, 1);
      part.ChunkEnds[0] := Length(part.Idx);
    end;
    if k0 >= 0 then Inc(Result, AddLarge(Grown(part), k0 + 1));
    Exit;
  end;
  { [R7-V] doUpdateZ's running maximum over the series' group: each Line's
    label sits 2 above every z2 traversed before it -- its line and end
    symbols, and every earlier row's, the effect symbol's 100 among them }
  mz2 := Low(Integer) div 2;
  for i := 0 to High(ASolved.Geoms) do
  begin
    g := ASolved.Geoms[i];
    if not g.Drawn or (i > High(ASolved.Inks)) then Continue;
    ink := ASolved.Inks[i];
    mz2 := Max(mz2, ASolved.Z2);
    { THE LINE: a polyline's points, a line's segment, a curve sampled }
    { [R7-G] a straight line on the half pixel of its width (device px) }
    pts := LinePoints(g, ASolved.Poly, 1, ink.Width * ASolved.Scale);
    el := TyChartElement(TyShapePolyline(pts));
    { [R7-F] the pointer tests the quadratic itself (BezierCurve), not the
      points it is drawn as }
    if not ASolved.Poly and g.Curved and (Length(pts) >= 2) then
    begin
      el.Shape.HitQuad := True;
      el.Shape.HitCP := g.CP;
    end;
    el.Style.HasFill := False;
    { [spec 242] the visual colour a label's `color: 'inherit'` reads
      (inheritColor); no fill is painted }
    el.Style.FillColor := ink.Stroke;
    el.Style.StrokeColor := ink.Stroke;
    { [spec 242] a gradient over the line path's own rect, grown by the pen
      (the polyline's samples would cut a curve's bulge short) }
    if ink.StrokeGrad.Kind <> cgkNone then
    begin
      el.Style.StrokeGradient := ink.StrokeGrad;
      el.Style.GradBoxSet := True;
      if ASolved.Poly then
        el.Style.GradBox := TyZrStrokeRect(TyZrBBox(TyZrPolyPath(g.Pts, False)),
          TyZrDataLength(TyZrPolyPath(g.Pts, False)), True, False, ink.Width * ASolved.Scale, 1)
      else
        el.Style.GradBox := TyLinesLineBox(g, ink.Width * ASolved.Scale);
    end;
    el.Style.StrokeWidthLogical := ink.Width;
    { [R7-F] A PEN OF +INFINITY: the canvas draws none (the document's note),
      and its stroked rect is not-a-number -- never hit }
    if IsInfinite(ink.Width) then
    begin
      el.Style.StrokeWidthLogical := 0;
      el.HitNone := ink.Width > 0;
      { [R7-W] the canvas refuses it and strokes at the lineWidth it had
        (TyLinesCanvasLeftovers) -- a word's dash, Infinity long, it refuses
        too: solid [was: no pen] }
      if ink.Width > 0 then
      begin
        el.CanvasFlags := el.CanvasFlags or cTyCanvasWidthLeft;
        if ink.DashWord <> 0 then
        begin
          ink.Dash := nil;
          ink.DashWord := 0;
        end;
      end;
    end;
    el.Style.Alpha := ink.Opacity;
    el.Style.DashLogical := ink.Dash;
    el.Style.DashWord := ink.DashWord;
    el.Style.DashOffsetLogical := ink.DashOffset;
    el.Z := ASolved.Z;
    el.Z2 := ASolved.Z2;
    el.Silent := False;
    el.Datum := TyChartDatum(ASolved.SeriesIndex, g.Row, g.Row);
    { Path.contain: the stroke at max(lineWidth, strokeContainThreshold 5) }
    el.HitSlopLogical := Max(ink.Width, 5) / 2;
    SetClip(el);
    el.Anim.Series := ASolved.SeriesIndex;
    el.Anim.Index := g.Row;
    if not ASolved.Poly then
    begin
      el.Anim.Role := carLinesLine;
      PutGeom(el, g);
      el.Anim.G[7] := Ord(ink.LabelPos);
      el.Anim.G[8] := ink.DistX;
      el.Anim.G[9] := ink.DistY;
      el.Anim.G[10] := ink.AlignFlags;
      { [R7-G] the width its frames snap by (device px) }
      el.Anim.G[11] := ink.Width * ASolved.Scale;
      { THE LABEL, where Line.beforeUpdate puts it at percent 1; a polyline
        has none }
      { [spec 242] the label's textConfig rides with the line: [has turn,
        turn, has offset, x, y] }
      el.Anim.Vals := nil;
      if ink.LabelHasRot or ink.LabelHasOff then
      begin
        SetLength(el.Anim.Vals, 5);
        el.Anim.Vals[0] := Ord(ink.LabelHasRot);
        el.Anim.Vals[1] := ink.LabelRot;
        el.Anim.Vals[2] := Ord(ink.LabelHasOff);
        el.Anim.Vals[3] := ink.LabelOffX;
        el.Anim.Vals[4] := ink.LabelOffY;
      end;
      if ink.LabelShow and (ink.LabelText <> '') then
      begin
        TyLinesLabelPlace(g, 1, ink.LabelPos, ink.DistX, ink.DistY, ink.LabelHasRot,
          ink.LabelRot, ink.LabelHasOff, ink.LabelOffX, ink.LabelOffY, ax, ay, ox, oy,
          lrot, anx, any, ah, av);
        if not (IsNan(anx) or IsNan(any) or IsInfinite(anx) or IsInfinite(any)) then
        begin
          el.Caption.Text := ink.LabelText;
          el.Caption.ItemSpec := ink.LabelSpec;
          el.Caption.HasFixedAnchor := True;
          el.Caption.FixedX := anx;
          el.Caption.FixedY := any;
          el.Caption.FixedInside := False;
          if (ink.AlignFlags and 1) <> 0 then ah := ink.AlignH;
          if (ink.AlignFlags and 2) <> 0 then av := ink.AlignV;
          el.Caption.FixedAH := ah;
          el.Caption.FixedAV := av;
          el.Caption.FixedRotationRad := lrot;
          { [R7-V] its z2 the running maximum's plus 2 (102 after a row's
            effect symbol) [was: its line's plus 2] }
          el.Caption.HasFixedZ2 := True;
          el.Caption.FixedZ2 := mz2 + 2;
        end;
      end;
    end
    else if Length(g.Pts) >= 2 then
    begin
      { [R2-D] A POLYLINE'S ONE PATH for the universal transition: the
        Polyline Polyline.ts makes (moveTo, lineTo, no smooth), its fill
        an own key of null and strokeNoScale -- UtBase [4] says so }
      el.Anim.UtTag := 1;
      el.Anim.UtRow := g.Row;
      el.Anim.UtOrder := 0;
      SetLength(el.Anim.UtData, Length(g.Pts) * 3);
      for e := 0 to High(g.Pts) do
      begin
        if e = 0 then el.Anim.UtData[0] := 1 else el.Anim.UtData[e * 3] := 2;
        el.Anim.UtData[e * 3 + 1] := g.Pts[e].X;
        el.Anim.UtData[e * 3 + 2] := g.Pts[e].Y;
      end;
      el.Anim.UtBase := TTyDoubleArray.Create(4);
      el.Anim.UtNoScale := True;
    end;
    AList.Add(el);
    Inc(Result);
    { THE END SYMBOLS, after the line: Line adds them second and third }
    if not ASolved.Poly then
      for e := 0 to 1 do
      begin
        if (ink.Sym[e].Name = '') or (ink.Sym[e].Name = 'none') then Continue;
        kind := TySymbolKindOf(ink.Sym[e].Name, em, pd);
        if kind = tsyNone then Continue;
        if e = 0 then at := TyLinesPointAt(g, 0) else at := TyLinesPointAt(g, 1);
        rot := TyLinesSymbolRotation(g, e = 1);
        sym := TyChartElement(EndSymbolShape(kind, em, pd, ink.Sym[e].W, ink.Sym[e].H,
          at.X, at.Y, rot));
        { [R7-V] the transform it hands the canvas: placed and turned }
        if IsNan(rot) then lm := TyZrLocal(1, 1, 0, at.X, at.Y)
        else lm := TyZrLocal(1, 1, rot, at.X, at.Y);
        sym.CanvasM := TTyDoubleArray.Create(lm[0], lm[1], lm[2], lm[3], lm[4], lm[5]);
        { setColor: the line's colour; an empty one is stroked in it at
          two wide (symbolPathSetColor) and filled with the ground [R7-O:
          was one wide] }
        if em then
        begin
          sym.Style.HasFill := True;
          sym.Style.FillColor := AEmptyFill;
          sym.Style.StrokeColor := ink.Stroke;
          sym.Style.StrokeWidthLogical := 2;
        end
        else if kind = tsyLine then
        begin
          { a 'line' is stroked in the colour; its fill stays zrender's
            default '#000' (nothing to fill on a line, but the pointer's
            pen then has no strokeContainThreshold) [R7-O: was none] }
          sym.Style.HasFill := True;
          sym.Style.FillColor := TTyChartColor($FF000000);
          sym.Style.StrokeColor := ink.Stroke;
          sym.Style.StrokeWidthLogical := 1;
        end
        else
        begin
          sym.Style.HasFill := True;
          sym.Style.FillColor := ink.Stroke;
        end;
        { [spec 242] the line's gradient in the symbol's own frame:
          createSymbol(-w / 2, -h / 2, w, h), turned and placed }
        if ink.StrokeGrad.Kind <> cgkNone then
        begin
          sym.Anim.LGrad := ink.StrokeGrad;
          sym.Anim.LGradBox := TyZrBBox(CoverSymbolPath(ink.Sym[e].Name,
            -ink.Sym[e].W / 2, -ink.Sym[e].H / 2, ink.Sym[e].W, ink.Sym[e].H));
          sym.Anim.LGradStroke := em or (kind = tsyLine);
          PlaceLocalGrad(sym, 1, 1, rot, at.X, at.Y);
        end;
        sym.Style.Alpha := ink.Opacity;
        sym.Z := ASolved.Z;
        sym.Z2 := ASolved.Z2;
        { a hover on an end symbol is the row's (its group's data) }
        sym.Silent := False;
        sym.Datum := TyChartDatum(ASolved.SeriesIndex, g.Row, g.Row);
        sym.HitSlopLogical := 0;
        EndSymbolHitFrame(sym, kind, ink.Sym[e].W, ink.Sym[e].H, 1, rot, at.X, at.Y);
        SetClip(sym);
        sym.Anim.Series := ASolved.SeriesIndex;
        sym.Anim.Index := g.Row;
        if e = 0 then sym.Anim.Role := carLinesFrom else sym.Anim.Role := carLinesTo;
        { [F3c] the symbol createSymbol makes, for the universal transition }
        sym.Caption.LgSymbol := ink.Sym[e].Name;
        sym.Caption.LgKeepAspect := False;
        PutGeom(sym, g);
        sym.Anim.G[7] := Ord(kind);
        sym.Anim.G[8] := ink.Sym[e].W;
        sym.Anim.G[9] := ink.Sym[e].H;
        if em then sym.Anim.G[10] := 1 else sym.Anim.G[10] := 0;
        sym.Anim.G[11] := rot;
        AList.Add(sym);
        Inc(Result);
      end;
    { THE EFFECT SYMBOL, z2 100: where its clip's first step puts it (__t 0),
      or nowhere when the period is not above 0 (no clip, never shown) }
    if ASolved.Effect then
    begin
      sym := TyChartElement(TyShapeRect(TyRectF(0, 0, 0, 0)));
      sym.Anim.Role := carLinesEffect;
      sym.Anim.Series := ASolved.SeriesIndex;
      sym.Anim.Index := g.Row;
      PutGeom(sym, g);
      sym.Anim.G[7] := ink.EffPeriod;
      sym.Anim.G[8] := ink.EffDelay;
      flags := 0;
      if ink.EffLoop then flags := flags or 1;
      if ink.EffRoundTrip then flags := flags or 2;
      if ASolved.Poly then flags := flags or 4;
      if ink.EffPoisoned then flags := flags or 8;
      sym.Anim.G[9] := flags;
      sym.Anim.G[10] := ink.EffW;
      sym.Anim.G[11] := ink.EffH;
      sym.Anim.Mono := ink.EffName;
      if ASolved.Poly then
      begin
        SetLength(sym.Anim.Pts, Length(g.Pts) * 2);
        for e := 0 to High(g.Pts) do
        begin
          sym.Anim.Pts[e * 2] := g.Pts[e].X;
          sym.Anim.Pts[e * 2 + 1] := g.Pts[e].Y;
        end;
      end;
      { [R7-R] ITS OWN STYLE: effect.getItemStyle(['color']) over
        createSymbol's -- the border, its width, dash, phase, cap, join and
        miter limit, the shadow (in the effect's colour unless written),
        the opacity -- then symbolPathSetColor: an empty one stroked in the
        colour at 2 over the ground (its border overridden), a 'line'
        stroked in the colour at the border's width (zrender's 1 where none
        is written; its fill stays zrender's '#000'), the rest filled with
        the colour and stroked by the border. The pen is in the symbol's own
        frame, scaled with it (TyLinesFrameEffect) [was: a 'line' stroked 1
        px on the canvas, an empty one filled, every border dropped] }
      kind := TySymbolKindOf(ink.EffName, em, pd);
      if ink.EffStrokeSet then
      begin
        sym.Style.StrokeColor := ink.EffStroke;
        sym.Style.StrokeGradient := ink.EffStrokeGrad;
        if IsNan(ink.EffLineWidth) then sym.Style.StrokeWidthLogical := 1
        else sym.Style.StrokeWidthLogical := ink.EffLineWidth;
      end;
      if em then
      begin
        sym.Style.HasFill := True;
        sym.Style.FillColor := AEmptyFill;
        sym.Style.StrokeColor := ink.EffColor;
        sym.Style.StrokeGradient := Default(TTyChartGradient);
        sym.Style.StrokeWidthLogical := 2;
      end
      else if kind = tsyLine then
      begin
        sym.Style.HasFill := True;
        sym.Style.FillColor := TTyChartColor($FF000000);
        sym.Style.StrokeColor := ink.EffColor;
        sym.Style.StrokeGradient := Default(TTyChartGradient);
        if IsNan(ink.EffLineWidth) then sym.Style.StrokeWidthLogical := 1
        else sym.Style.StrokeWidthLogical := ink.EffLineWidth;
      end
      else
      begin
        sym.Style.HasFill := True;
        sym.Style.FillColor := ink.EffColor;
      end;
      { a colour of 'none': no fill where it fills, no pen where it strokes }
      if ink.EffColorNone then
      begin
        if em or (kind = tsyLine) then sym.Style.StrokeWidthLogical := 0
        else
        begin
          sym.Style.HasFill := False;
          sym.Style.HitNoFill := True;
        end;
      end;
      if not (sym.Style.StrokeWidthLogical > 0) then sym.Style.StrokeWidthLogical := 0;
      if sym.Style.StrokeWidthLogical > 0 then
      begin
        sym.Style.DashLogical := Copy(ink.EffDash, 0, Length(ink.EffDash));
        sym.Style.DashWord := ink.EffDashWord;
        if sym.Style.DashWord <> 0 then
          sym.Style.DashLogical := TyDashOfWord(sym.Style.DashWord, sym.Style.StrokeWidthLogical);
        sym.Style.DashOffsetLogical := ink.EffDashOffset;
        sym.Style.LineCap := ink.EffCap;
        sym.Style.LineJoin := ink.EffJoin;
        sym.Style.MiterLimit := ink.EffMiter;
      end;
      if ink.EffShadowSet then TyStyleSetShadow(sym.Style, ink.EffShadow);
      { [R7-S] the canvas' shadowColor it leaves, or takes }
      if ink.EffShadowLeft then sym.CanvasFlags := cTyCanvasShadowLeft
      else
      begin
        sym.CanvasFlags := cTyCanvasOwnShadow;
        sym.CanvasShadow := ink.EffCanvasShadow;
      end;
      { the frame's device px per css px: the pen's own frame is css px }
      sym.Anim.Vals := TTyDoubleArray.Create(ASolved.Scale);
      sym.Style.Alpha := ink.EffOpacity;
      sym.Z := ASolved.Z;
      sym.Z2 := TyLinesEffectZ2;
      mz2 := Max(mz2, TyLinesEffectZ2);
      { [spec 242] its colour as a gradient, in the unit symbol's frame }
      if ink.EffGrad.Kind <> cgkNone then
      begin
        sym.Anim.LGrad := ink.EffGrad;
        sym.Anim.LGradBox := TyZrBBox(CoverSymbolPath(ink.EffName, -0.5, -0.5, 1, 1));
        { [R7-R] an empty one's pen too }
        sym.Anim.LGradStroke := em or (TySymbolKindOf(ink.EffName, em, pd) = tsyLine);
      end;
      { [spec 242] A POINTER TARGET: setItemGraphicEl writes the row onto
        every element of the item's group, the effect symbol too -- its
        row's events, tooltip and click-to-select; it is no highDown
        dispatcher, so no emphasis (the control's hit kind says so) }
      sym.Silent := False;
      sym.HitSlopLogical := 0;
      sym.Datum := TyChartDatum(ASolved.SeriesIndex, g.Row, g.Row);
      SetClip(sym);
      TyLinesEffectOfElement(sym, eff);
      if ink.EffPeriod > 0 then TyLinesEffectStep(eff, 0);
      TyLinesFrameEffect(sym, eff, False);
      AList.Add(sym);
      Inc(Result);
    end;
  end;
end;

procedure TyLinesEffectOfElement(const AEl: TTyChartElement; out AE: TTyLinesEffect);
var g: TTyLinesGeom; k, flags: Integer;
begin
  AE := Default(TTyLinesEffect);
  flags := Round(AEl.Anim.G[9]);
  if (flags and 4) <> 0 then
  begin
    g := Default(TTyLinesGeom);
    SetLength(g.Pts, Length(AEl.Anim.Pts) div 2);
    for k := 0 to High(g.Pts) do
      g.Pts[k] := TyPointF(AEl.Anim.Pts[k * 2], AEl.Anim.Pts[k * 2 + 1]);
    g.Drawn := True;
  end
  else
    g := GeomOfG(AEl);
  TyLinesEffectInit(AE, g, (flags and 4) <> 0, AEl.Anim.Mono, AEl.Anim.G[10],
    AEl.Anim.G[11]);
  AE.Poisoned := (flags and 8) <> 0;
end;

{ the effect symbol under the transform (ASX, ASY, ARot, AX, AY), device px }
procedure PlaceEffect(var AEl: TTyChartElement; ASX, ASY, AX, AY, ARot: Double);
var L: TTyMat2D; ds: Double;
begin
  AEl.Shape := EffectShape(AEl.Anim.Mono, ASX, ASY, AX, AY, ARot);
  AEl.Ignore := False;
  { [R7-R] THE PEN IN THE SYMBOL'S OWN FRAME: its scale (the trail's
    scaleY too) and its turn, not strokeNoScale -- the root of the scale's
    determinant its size, the map over that root its shape, frame by frame }
  if AEl.Style.StrokeWidthLogical > 0 then
  begin
    ds := 1;
    if (Length(AEl.Anim.Vals) > 0) and (AEl.Anim.Vals[0] > 0) then ds := AEl.Anim.Vals[0];
    if IsNan(ARot) then L := TyZrLocal(ASX / ds, ASY / ds, 0, 0, 0)
    else L := TyZrLocal(ASX / ds, ASY / ds, ARot, 0, 0);
    AEl.Style.PenScale := Sqrt(Abs(L[0] * L[3] - L[1] * L[2]));
    TyStyleSetPenShape(AEl.Style, L);
  end;
  { [spec 242] its gradient where the symbol is now }
  if IsNan(ARot) then PlaceLocalGrad(AEl, ASX, ASY, 0, AX, AY)
  else PlaceLocalGrad(AEl, ASX, ASY, ARot, AX, AY);
end;

{ [R7-V] AN EFFECT SYMBOL WHOSE TRANSFORM IS NO NUMBER IS HIT where its
  invTransform says, not where it is drawn: matrix.invert fails and the
  inverse it was made with stays, the identity in css px -- Path.contain
  then asks createSymbol(type, -0.5, -0.5, 1, 1) at the canvas' top left
  [was: where the canvas drew it]. (A trail's frame of no number follows
  one that is a number only across an update, which builds the symbol's
  state afresh here: upstream's inverse is then the one setOption's own
  frame left -- not modelled.) }
procedure NanEffectHit(var AEl: TTyChartElement);
var
  em: Boolean;
  pd, nm: string;
  m: TTyMat2D;
  ds: Double;
begin
  case TySymbolKindOf(AEl.Anim.Mono, em, pd) of
    tsyCircle: nm := 'circle';
    tsyRect: nm := 'rect';
    tsyRoundRect: nm := 'roundRect';
    tsySquare: nm := 'square';
    tsyTriangle: nm := 'triangle';
    tsyDiamond: nm := 'diamond';
    tsyPin: nm := 'pin';
    tsyArrow: nm := 'arrow';
    tsyLine: nm := 'line';
  else
    Exit;
  end;
  ds := 1;
  if (Length(AEl.Anim.Vals) > 0) and (AEl.Anim.Vals[0] > 0) then ds := AEl.Anim.Vals[0];
  m := TyZrLocal(ds, ds, 0, 0, 0);
  { [R7-W] the inverse a frame that was a number left: its transform (an
    update's own frame -- setOption's flush steps the clip once more)
    [was: the identity always] }
  if (Length(AEl.Anim.Vals) >= 7) and (AEl.Anim.Vals[1] = 2) then
    m := TyZrLocal(AEl.Anim.Vals[4], AEl.Anim.Vals[5], AEl.Anim.Vals[6],
      AEl.Anim.Vals[2], AEl.Anim.Vals[3]);
  { the symbol's unit box (-1 .. 1) is twice the effect's (-0.5 .. 0.5) }
  AEl.Shape.HitM[0] := m[0] * 0.5;
  AEl.Shape.HitM[1] := m[1] * 0.5;
  AEl.Shape.HitM[2] := m[2] * 0.5;
  AEl.Shape.HitM[3] := m[3] * 0.5;
  AEl.Shape.HitM[4] := m[4];
  AEl.Shape.HitM[5] := m[5];
  AEl.Shape.HitBoxW := 0;
  AEl.Shape.HitBoxH := 0;
  AEl.Shape.HitSym := nm;
  AEl.Shape.HitPenInFrame := True;
end;

{ [R7-V] the effect symbol under a transform the canvas kept (device px): its
  place, scale and turn where it has no shear, else the unit symbol mapped }
procedure PlaceEffectM(var AEl: TTyChartElement; const AM: TTyMat2D);
var
  sx, sy, r, ds: Double;
  spec: TTySymbolSpec;
  em: Boolean;
  pd: string;
  L: TTyMat2D;
begin
  sx := Sqrt(AM[0] * AM[0] + AM[1] * AM[1]);
  if sx > 0 then
  begin
    r := ArcTan2(-AM[1], AM[0]);
    sy := AM[2] * Sin(r) + AM[3] * Cos(r);
    if (Abs(AM[2] - sy * Sin(r)) <= 1e-9 * (1 + Abs(sy)))
      and (Abs(AM[3] - sy * Cos(r)) <= 1e-9 * (1 + Abs(sy))) then
    begin
      PlaceEffect(AEl, sx, sy, AM[4], AM[5], r);
      Exit;
    end;
  end;
  spec := TySymbolDefault('scatter');
  spec.Kind := TySymbolKindOf(AEl.Anim.Mono, em, pd);
  spec.Empty := em;
  spec.PathData := pd;
  spec.WidthPx := 1;
  spec.HeightPx := 1;
  spec.OffsetX := 0;
  spec.OffsetY := 0;
  L := AM;
  L[4] := 0;
  L[5] := 0;
  AEl.Shape := TyBuildSymbolMapped(spec, AM[4], AM[5], L);
  AEl.Ignore := False;
  if AEl.Style.StrokeWidthLogical > 0 then
  begin
    ds := 1;
    if (Length(AEl.Anim.Vals) > 0) and (AEl.Anim.Vals[0] > 0) then ds := AEl.Anim.Vals[0];
    L[0] := L[0] / ds; L[1] := L[1] / ds; L[2] := L[2] / ds; L[3] := L[3] / ds;
    AEl.Style.PenScale := Sqrt(Abs(L[0] * L[3] - L[1] * L[2]));
    TyStyleSetPenShape(AEl.Style, L);
  end;
end;

procedure TyLinesFrameEffect(var AEl: TTyChartElement; const AE: TTyLinesEffect;
  AGone: Boolean);
var ds: Double;
begin
  if AGone or AE.Ignore or IsNan(AE.X) or IsNan(AE.Y) then
  begin
    AEl.Shape := TyShapeRect(TyRectF(0, 0, 0, 0));
    AEl.Ignore := True;
    Exit;
  end;
  ds := 1;
  if (Length(AEl.Anim.Vals) > 0) and (AEl.Anim.Vals[0] > 0) then ds := AEl.Anim.Vals[0];
  { [R7-S] A SCALE THAT IS NOT A NUMBER (`symbolSize: [12]`: scaleY
    undefined): the canvas refuses the transform and keeps the one it had
    -- the unit symbol in the css px frame until TyLinesCanvasLeftovers says
    which [was: a square of the width]. A new array, not the list's: the
    frame's copy shares it }
  if IsNan(AE.ScaleX) or IsNan(AE.ScaleY) then
  begin
    AEl.CanvasFlags := AEl.CanvasFlags or cTyCanvasTransformLeft;
    { [R7-W] and the transform its invTransform keeps, where a frame had one
      (2: for the hit only) }
    if AE.HasInv then
      AEl.Anim.Vals := TTyDoubleArray.Create(ds, 2, AE.InvX, AE.InvY, AE.InvSX, AE.InvSY, AE.InvRot)
    else
      AEl.Anim.Vals := TTyDoubleArray.Create(ds);
    PlaceEffect(AEl, ds, ds, 0, 0, NaN);
    { (its hit: TyLinesCanvasLeftovers, NanEffectHit) }
    Exit;
  end;
  AEl.CanvasFlags := AEl.CanvasFlags and not cTyCanvasTransformLeft;
  { the transform it leaves on the canvas: 1, then x, y, scaleX, scaleY,
    rotation }
  AEl.Anim.Vals := TTyDoubleArray.Create(ds, 1, AE.X, AE.Y, AE.ScaleX, AE.ScaleY, AE.Rotation);
  PlaceEffect(AEl, AE.ScaleX, AE.ScaleY, AE.X, AE.Y, AE.Rotation);
end;

function TyLinesCanvasLeftoversDue(AList: TTyPaintList): Boolean;
var i: Integer; pe: PTyChartElement;
begin
  Result := False;
  if AList = nil then Exit;
  for i := 0 to AList.Count - 1 do
  begin
    pe := AList.Ref(i);
    if TyCanvasElementCarries(pe^) then Exit(True);
  end;
end;

function TyCanvasElementCarries(const AEl: TTyChartElement): Boolean;
var k: Integer;
begin
  Result := ((AEl.CanvasFlags and not cTyCanvasOwnShadow) <> 0)
    { [R7-V] a value the canvas refuses, not yet settled }
    or (AEl.Style.ShadowColor = cTyCanvasColourLeft) or (AEl.Style.ShadowBlur < 0)
    or (AEl.Style.LineCap = cTyCanvasWordLeft) or (AEl.Style.LineJoin = cTyCanvasWordLeft)
    or (AEl.Style.MiterLimit < 0)
    { [R7-W] a fill / stroke colour, a dash phase, a caption's colours }
    or (AEl.Style.HasFill and (AEl.Style.FillColor = cTyCanvasColourLeft))
    or (AEl.Style.StrokeColor = cTyCanvasColourLeft)
    or TyPhaseLeft(AEl.Style.DashOffsetLogical)
    or (AEl.Caption.Colour = cTyCanvasColourLeft)
    or (AEl.Caption.StrokeColour = cTyCanvasColourLeft)
    { [R7-Y] a shadow offset, a blend word }
    or TyPhaseLeft(AEl.Style.ShadowOffsetX) or TyPhaseLeft(AEl.Style.ShadowOffsetY)
    or ((AEl.Style.Blend <> '') and not TyBlendWordKnown(AEl.Style.Blend));
  if Result then Exit;
  for k := 0 to High(AEl.Caption.RtPieces) do
    if (AEl.Caption.RtPieces[k].CanvasLeft <> 0)
      or (AEl.Caption.RtPieces[k].HasFill and (AEl.Caption.RtPieces[k].Fill = cTyCanvasColourLeft))
      or (AEl.Caption.RtPieces[k].HasStroke and (AEl.Caption.RtPieces[k].Stroke = cTyCanvasColourLeft)) then
      Exit(True);
end;

function TyElementCanvasTransform(const AEl: TTyChartElement; out AM: TTyMat2D): Boolean;
var d, r: Double;
begin
  Result := False;
  AM := Default(TTyMat2D);
  if (AEl.Anim.Role = carLinesEffect) and (Length(AEl.Anim.Vals) >= 7)
    and (AEl.Anim.Vals[1] = 1) then
  begin
    AM := TyZrLocal(AEl.Anim.Vals[4], AEl.Anim.Vals[5], AEl.Anim.Vals[6],
      AEl.Anim.Vals[2], AEl.Anim.Vals[3]);
    Exit(True);
  end;
  { [R7-Z] a transform the element carries (an end symbol's, a component
    part's) before a caption's }
  if Length(AEl.CanvasM) = 6 then
  begin
    AM[0] := AEl.CanvasM[0]; AM[1] := AEl.CanvasM[1]; AM[2] := AEl.CanvasM[2];
    AM[3] := AEl.CanvasM[3]; AM[4] := AEl.CanvasM[4]; AM[5] := AEl.CanvasM[5];
    Exit(True);
  end;
  if AEl.Caption.FontSizeLogical <> 0 then
  begin
    if AEl.Caption.HasFixedAnchor then
      AM := TyZrLocal(1, 1, AEl.Caption.FixedRotationRad, AEl.Caption.FixedX, AEl.Caption.FixedY)
    else
      AM := TyZrLocal(1, 1, AEl.Caption.RotationRad, AEl.Caption.X, AEl.Caption.Y);
    Exit(not (IsNan(AM[0]) or IsNan(AM[4]) or IsNan(AM[5])));
  end;
  if AEl.Shape.HitSym <> '' then
  begin
    { the unit box's frame is half the symbol's size: the symbol's own
      scale is that, its path the unit one }
    AM := AEl.Shape.HitM;
    Exit(True);
  end;
  if AEl.ZrHit.Active then
  begin
    { the inverse of the way back }
    d := AEl.ZrHit.ToLocal[0] * AEl.ZrHit.ToLocal[3] - AEl.ZrHit.ToLocal[1] * AEl.ZrHit.ToLocal[2];
    if not ((d = 0) or IsNan(d) or IsInfinite(d)) then
    begin
      r := 1 / d;
      AM[0] := AEl.ZrHit.ToLocal[3] * r;
      AM[1] := -AEl.ZrHit.ToLocal[1] * r;
      AM[2] := -AEl.ZrHit.ToLocal[2] * r;
      AM[3] := AEl.ZrHit.ToLocal[0] * r;
      AM[4] := (AEl.ZrHit.ToLocal[2] * AEl.ZrHit.ToLocal[5] - AEl.ZrHit.ToLocal[3] * AEl.ZrHit.ToLocal[4]) * r;
      AM[5] := (AEl.ZrHit.ToLocal[1] * AEl.ZrHit.ToLocal[4] - AEl.ZrHit.ToLocal[0] * AEl.ZrHit.ToLocal[5]) * r;
      Exit(True);
    end;
  end;
end;

procedure TyPatternUnder(const AM: TTyMat2D; ADs: Double; var APm: TTyDoubleArray);
var m: array[0..5] of Double; k: Integer; p: array[0..5] of Double;
begin
  if Length(APm) <> 6 then Exit;
  if not (ADs > 0) then ADs := 1;
  for k := 0 to 5 do
  begin
    m[k] := AM[k] / ADs;
    p[k] := APm[k];
  end;
  APm[0] := m[0] * p[0] + m[2] * p[1];
  APm[1] := m[1] * p[0] + m[3] * p[1];
  APm[2] := m[0] * p[2] + m[2] * p[3];
  APm[3] := m[1] * p[2] + m[3] * p[3];
  APm[4] := m[0] * p[4] + m[2] * p[5] + m[4];
  APm[5] := m[1] * p[4] + m[3] * p[5] + m[5];
end;

{ [R7-Y] A HELD CANVASGRADIENT UNDER ANOTHER TRANSFORM: its points were made
  in the frame of the element that made it (AHasA / AA, else the css px
  frame), and land under the one filling with it -- device px both; a
  radius by the scales' ratio }
function GradUnder(const AGrad: TTyChartGradient; AHasA: Boolean; const AA: TTyMat2D;
  AHasB: Boolean; const AB: TTyMat2D; ADs: Double): TTyChartGradient;
var
  ma, mb: TTyMat2D;
  d, r, lx, ly, sa, sb: Double;

  procedure Map(var AX, AY: Double);
  var u, v: Double;
  begin
    { back into the frame it was made in, then under mb }
    u := (ma[3] * (AX - ma[4]) - ma[2] * (AY - ma[5])) * r;
    v := (-ma[1] * (AX - ma[4]) + ma[0] * (AY - ma[5])) * r;
    lx := mb[0] * u + mb[2] * v + mb[4];
    ly := mb[1] * u + mb[3] * v + mb[5];
    AX := lx;
    AY := ly;
  end;

begin
  Result := AGrad;
  if AGrad.Kind = cgkNone then Exit;
  if AHasA then ma := AA
  else
  begin
    ma := Default(TTyMat2D);
    ma[0] := ADs;
    ma[3] := ADs;
  end;
  if AHasB then mb := AB
  else
  begin
    mb := Default(TTyMat2D);
    mb[0] := ADs;
    mb[3] := ADs;
  end;
  if (ma[0] = mb[0]) and (ma[1] = mb[1]) and (ma[2] = mb[2]) and (ma[3] = mb[3])
    and (ma[4] = mb[4]) and (ma[5] = mb[5]) then Exit;
  d := ma[0] * ma[3] - ma[1] * ma[2];
  { (a frame of no area: no way back -- held as it is) }
  if (d = 0) or IsNan(d) or IsInfinite(d) then Exit;
  r := 1 / d;
  Map(Result.X, Result.Y);
  if Result.Kind = cgkLinear then Map(Result.X2, Result.Y2)
  else
  begin
    sa := Sqrt(Abs(d));
    sb := Sqrt(Abs(mb[0] * mb[3] - mb[1] * mb[2]));
    Result.R := AGrad.R / sa * sb;
  end;
end;

{ [R7-V] what a label's last text span hands the canvas: its textShadowColor
  ('transparent' where none) and blur where it blurs, else zrender's '#000'
  and none -- Text.ts sets a TSpan's shadow only for a textShadowBlur above
  nought }
procedure CaptionShadowOf(const AEl: TTyChartElement; out AColour: TTyChartColor;
  out ABlur, AOffX, AOffY: Double);
var k: Integer;
begin
  AColour := TTyChartColor($FF000000);
  ABlur := 0;
  AOffX := 0;
  AOffY := 0;
  for k := High(AEl.Caption.RtPieces) downto 0 do
  begin
    if AEl.Caption.RtPieces[k].Text = '' then Continue;
    if AEl.Caption.RtPieces[k].HasShadow and (AEl.Caption.RtPieces[k].ShadowBlur > 0) then
    begin
      AColour := AEl.Caption.RtPieces[k].ShadowColor;
      ABlur := AEl.Caption.RtPieces[k].ShadowBlur;
      { [R7-Y] and its offsets (`textShadowOffsetX || 0`) }
      if not (IsNan(AEl.Caption.RtPieces[k].ShadowOffsetX) or IsInfinite(AEl.Caption.RtPieces[k].ShadowOffsetX)) then
        AOffX := AEl.Caption.RtPieces[k].ShadowOffsetX;
      if not (IsNan(AEl.Caption.RtPieces[k].ShadowOffsetY) or IsInfinite(AEl.Caption.RtPieces[k].ShadowOffsetY)) then
        AOffY := AEl.Caption.RtPieces[k].ShadowOffsetY;
    end;
    Exit;
  end;
end;

function TyCanvasGroundOf(AShadow: TTyChartColor): TTyCanvasGround;
begin
  Result := Default(TTyCanvasGround);
  Result.Shadow := AShadow;
  Result.Fill := TTyChartColor($FF000000);
  Result.Stroke := TTyChartColor($FF000000);
  Result.LineWidth := 1;
  Result.Miter := 10;
end;

function TyCanvasGroundOfRun(const ARun: TTyCanvasRun): TTyCanvasGround;
begin
  Result := Default(TTyCanvasGround);
  Result.Shadow := ARun.Cur.Shadow;
  Result.Fill := ARun.Cur.Fill;
  Result.Stroke := ARun.Cur.Stroke;
  Result.LineWidth := ARun.Cur.LineWidth;
  Result.HasT := ARun.Cur.HasT;
  Result.M := ARun.Cur.M;
  Result.Blur := ARun.Cur.Blur;
  Result.Cap := ARun.Cur.Cap;
  Result.Join := ARun.Cur.Join;
  Result.Miter := ARun.Cur.Miter;
  Result.Phase := ARun.Cur.Phase;
  Result.FillGrad := ARun.Cur.FillGrad;
  Result.StrokeGrad := ARun.Cur.StrokeGrad;
end;

{ the canvas' own state at the start of a zlevel's paint: its defaults, the
  ground on the components' zlevel }
procedure GroundState(var ARun: TTyCanvasRun);
begin
  ARun.Cur := Default(TTyCanvasState);
  ARun.Cur.Miter := 10;
  ARun.Cur.Fill := TTyChartColor($FF000000);
  ARun.Cur.Stroke := TTyChartColor($FF000000);
  ARun.Cur.LineWidth := 1;
  if ARun.ZLevel = 0 then
  begin
    ARun.Cur.Shadow := ARun.Ground.Shadow;
    ARun.Cur.Fill := ARun.Ground.Fill;
    ARun.Cur.Stroke := ARun.Ground.Stroke;
    ARun.Cur.LineWidth := ARun.Ground.LineWidth;
    ARun.Cur.HasT := ARun.Ground.HasT;
    ARun.Cur.M := ARun.Ground.M;
    { [R7-Z] the rest of it [was: the canvas' defaults] }
    ARun.Cur.Blur := ARun.Ground.Blur;
    ARun.Cur.Cap := ARun.Ground.Cap;
    ARun.Cur.Join := ARun.Ground.Join;
    if ARun.Ground.Miter > 0 then ARun.Cur.Miter := ARun.Ground.Miter;
    ARun.Cur.Phase := ARun.Ground.Phase;
    ARun.Cur.FillGrad := ARun.Ground.FillGrad;
    ARun.Cur.StrokeGrad := ARun.Ground.StrokeGrad;
    ARun.Cur.HasFont := ARun.Ground.HasFont;
    ARun.Cur.FontFamily := ARun.Ground.FontFamily;
    ARun.Cur.FontPx := ARun.Ground.FontPx;
    ARun.Cur.FontWeight := ARun.Ground.FontWeight;
  end;
end;

procedure TyCanvasRunStart(out ARun: TTyCanvasRun; const AGround: TTyCanvasGround;
  APPI: Integer);
begin
  ARun := Default(TTyCanvasRun);
  ARun.First := True;
  ARun.Ground := AGround;
  if APPI > 0 then ARun.Ds := APPI / 96 else ARun.Ds := 1;
  ARun.ZLevel := 0;
  GroundState(ARun);
  ARun.Saved := ARun.Cur;
  ARun.ClipRect := TyRectF(0, 0, 0, 0);
end;

{ [R7-W] a gradient as the canvas holds it once an element filled or
  stroked with it: in the frame it was made for, the element's box (the
  canvas keeps that CanvasGradient, not the element's spec) }
function CanvasGradOf(const AGrad: TTyChartGradient; const AEl: TTyChartElement;
  ADs: Double): TTyChartGradient;
var box: TTyXYWH; x1, y1, x2, y2, r: Double;
begin
  Result := AGrad;
  if (AGrad.Kind = cgkNone) or AGrad.Global then Exit;
  if AEl.Style.GradBoxSet then box := AEl.Style.GradBox
  else
  begin
    box := TyRectToXYWH(TyShapeBounds(AEl.Shape));
    { [R7-Y] the renderer's box (TyElementGradientBox): Path.getBoundingRect
      grows by the stroke when there is one [was: the shape's alone, a
      stroke's gradient held off by half its width] }
    if (AEl.Style.StrokeWidthLogical > 0)
      and (((AEl.Style.StrokeColor shr 24) > 0) or (AEl.Style.StrokeGradient.Kind <> cgkNone)) then
      box := TyGrowByStroke(box, AEl.Style.HasFill, AEl.Style.StrokeWidthLogical * ADs);
  end;
  TyResolveGradientXYWH(AGrad, box, x1, y1, x2, y2, r);
  Result.Global := True;
  Result.X := x1;
  Result.Y := y1;
  Result.X2 := x2;
  Result.Y2 := y2;
  Result.R := r;
end;

procedure TyCanvasRunStep(var ARun: TTyCanvasRun; var AEl: TTyChartElement);
var
  clipped, cap, strokes, dashed: Boolean;
  ds, blur, sEl, ps, ox, oy: Double;
  pm: TTyDoubleArray;
  colour: TTyChartColor;
  elHasT: Boolean;
  elM: TTyMat2D;
  k: Integer;
  pc: ^TTyRtPiece;
begin
  { what the painter skips: ignored, held back, of an opacity of nought
    ([R7-V] shouldBePainted's `opacity === 0`: a negative one is brushed,
    at the clamped nought, and hands the canvas its state [was: any
    opacity not above nought skipped]) }
  if AEl.Ignore or AEl.ProgHidden or (AEl.Style.Alpha = 0) then Exit;
  { [R7-Y] and shouldBePainted's `m && !m[0] && !m[3]`: a transform scaled
    to nought is not brushed (a symbol of size nought, an end symbol at the
    start of its line's enter animation) [was: brushed, its transform and
    colours handed on] }
  if ((AEl.CanvasFlags and cTyCanvasTransformLeft) = 0)
    and TyElementCanvasTransform(AEl, elM) and (elM[0] = 0) and (elM[3] = 0) then Exit;
  if ARun.First or (AEl.ZLevel <> ARun.ZLevel) then
  begin
    ARun.First := False;
    ARun.ZLevel := AEl.ZLevel;
    GroundState(ARun);
    ARun.InClip := False;
  end;
  { a clip path: saved on entering, restored on leaving or changing (a
    series' group clip its own, whatever its rect) }
  clipped := AEl.HasClip or AEl.HasClipSector;
  if ARun.InClip and (not clipped or (AEl.Datum.SeriesIndex <> ARun.ClipSeries)
    or (AEl.ClipRect.Left <> ARun.ClipRect.Left) or (AEl.ClipRect.Top <> ARun.ClipRect.Top)
    or (AEl.ClipRect.Right <> ARun.ClipRect.Right) or (AEl.ClipRect.Bottom <> ARun.ClipRect.Bottom)) then
  begin
    ARun.Cur := ARun.Saved;
    ARun.InClip := False;
  end;
  if clipped and not ARun.InClip then
  begin
    ARun.Saved := ARun.Cur;
    ARun.InClip := True;
    ARun.ClipSeries := AEl.Datum.SeriesIndex;
    ARun.ClipRect := AEl.ClipRect;
    { [R7-V] updateClipStatus sets the clip path's transform (a series
      group's clip has none) }
    ARun.Cur.HasT := False;
  end;
  cap := AEl.Caption.FontSizeLogical <> 0;
  { [R7-V] a value the canvas refuses, first seen: marked, so the next
    pass settles it again }
  if AEl.Style.ShadowColor = cTyCanvasColourLeft then
    AEl.CanvasFlags := AEl.CanvasFlags or cTyCanvasShadowLeft;
  if AEl.Style.ShadowBlur < 0 then AEl.CanvasFlags := AEl.CanvasFlags or cTyCanvasBlurLeft;
  if AEl.Style.LineCap = cTyCanvasWordLeft then AEl.CanvasFlags := AEl.CanvasFlags or cTyCanvasCapLeft;
  if AEl.Style.LineJoin = cTyCanvasWordLeft then AEl.CanvasFlags := AEl.CanvasFlags or cTyCanvasJoinLeft;
  if AEl.Style.MiterLimit < 0 then AEl.CanvasFlags := AEl.CanvasFlags or cTyCanvasMiterLeft;
  { [R7-Y] a shadow offset, a blend word }
  if TyPhaseLeft(AEl.Style.ShadowOffsetX) then AEl.CanvasFlags := AEl.CanvasFlags or cTyCanvasOffXLeft;
  if TyPhaseLeft(AEl.Style.ShadowOffsetY) then AEl.CanvasFlags := AEl.CanvasFlags or cTyCanvasOffYLeft;
  if (AEl.Style.Blend <> '') and not TyBlendWordKnown(AEl.Style.Blend) then
    AEl.CanvasFlags := AEl.CanvasFlags or cTyCanvasBlendLeft;
  { [R7-W] and a fill / stroke colour, a dash phase, a caption's colours }
  if not cap then
  begin
    if AEl.Style.HasFill and (AEl.Style.FillColor = cTyCanvasColourLeft)
      and (AEl.Style.FillGradient.Kind = cgkNone) and not AEl.Style.FillPattern.Present then
      AEl.CanvasFlags := AEl.CanvasFlags or cTyCanvasFillLeft;
    if (AEl.Style.StrokeColor = cTyCanvasColourLeft) and (AEl.Style.StrokeGradient.Kind = cgkNone) then
      AEl.CanvasFlags := AEl.CanvasFlags or cTyCanvasStrokeLeft;
    if TyPhaseLeft(AEl.Style.DashOffsetLogical) then
      AEl.CanvasFlags := AEl.CanvasFlags or cTyCanvasPhaseLeftFlag;
  end
  else
  begin
    if AEl.Caption.Colour = cTyCanvasColourLeft then
      AEl.CanvasFlags := AEl.CanvasFlags or cTyCanvasTextFillLeft;
    if AEl.Caption.StrokeColour = cTyCanvasColourLeft then
      AEl.CanvasFlags := AEl.CanvasFlags or cTyCanvasTextStrokeLeft;
    for k := 0 to High(AEl.Caption.RtPieces) do
    begin
      if AEl.Caption.RtPieces[k].HasFill and (AEl.Caption.RtPieces[k].Fill = cTyCanvasColourLeft) then
        AEl.Caption.RtPieces[k].CanvasLeft := AEl.Caption.RtPieces[k].CanvasLeft or 1;
      if AEl.Caption.RtPieces[k].HasStroke and (AEl.Caption.RtPieces[k].Stroke = cTyCanvasColourLeft) then
        AEl.Caption.RtPieces[k].CanvasLeft := AEl.Caption.RtPieces[k].CanvasLeft or 2;
    end;
  end;
  { the shadowColor: refused (kept), the symbol's own, [R7-V] a label's
    text span's, a written one, else zrender's '#000' }
  if (AEl.CanvasFlags and cTyCanvasShadowLeft) <> 0 then
    AEl.Style.ShadowColor := ARun.Cur.Shadow
  else if (AEl.CanvasFlags and cTyCanvasOwnShadow) <> 0 then
    ARun.Cur.Shadow := AEl.CanvasShadow
  else if cap then
  begin
    CaptionShadowOf(AEl, colour, blur, ox, oy);
    ARun.Cur.Shadow := colour;
  end
  else if (AEl.Style.ShadowColor shr 24) <> 0 then
    ARun.Cur.Shadow := AEl.Style.ShadowColor
  else
    ARun.Cur.Shadow := TTyChartColor($FF000000);
  { [R7-V] the shadowBlur: refused below nought (kept), else its own }
  if (AEl.CanvasFlags and cTyCanvasBlurLeft) <> 0 then
    AEl.Style.ShadowBlur := ARun.Cur.Blur
  else if cap then
  begin
    CaptionShadowOf(AEl, colour, blur, ox, oy);
    ARun.Cur.Blur := blur;
  end
  else if AEl.Style.ShadowBlur > 0 then ARun.Cur.Blur := AEl.Style.ShadowBlur
  else ARun.Cur.Blur := 0;
  { [R7-Y] the shadow's offsets: `dpr * (value || 0)`, refused (kept) where
    that is no finite number; a text span's only where it blurs }
  if cap then
  begin
    CaptionShadowOf(AEl, colour, blur, ox, oy);
    ARun.Cur.OffX := ox;
    ARun.Cur.OffY := oy;
  end
  else
  begin
    if (AEl.CanvasFlags and cTyCanvasOffXLeft) <> 0 then AEl.Style.ShadowOffsetX := ARun.Cur.OffX
    else if IsNan(AEl.Style.ShadowOffsetX) or IsInfinite(AEl.Style.ShadowOffsetX) then ARun.Cur.OffX := 0
    else ARun.Cur.OffX := AEl.Style.ShadowOffsetX;
    if (AEl.CanvasFlags and cTyCanvasOffYLeft) <> 0 then AEl.Style.ShadowOffsetY := ARun.Cur.OffY
    else if IsNan(AEl.Style.ShadowOffsetY) or IsInfinite(AEl.Style.ShadowOffsetY) then ARun.Cur.OffY := 0
    else ARun.Cur.OffY := AEl.Style.ShadowOffsetY;
  end;
  { [R7-Y] the composite operation: `style.blend || 'source-over'`, a word
    the canvas does not know refused (kept); a label carries none }
  if (AEl.CanvasFlags and cTyCanvasBlendLeft) <> 0 then AEl.Style.Blend := ARun.Cur.Blend
  else if cap then ARun.Cur.Blend := ''
  else if AEl.Style.Blend = 'source-over' then ARun.Cur.Blend := ''
  else ARun.Cur.Blend := AEl.Style.Blend;
  { [R7-V] the pen's cap, join and miterLimit: every path and text sets
    them (a text its defaults); a word the canvas does not take, or a
    miterLimit below nought, keeps the one it had }
  if (AEl.CanvasFlags and cTyCanvasCapLeft) <> 0 then AEl.Style.LineCap := ARun.Cur.Cap
  else if cap then ARun.Cur.Cap := 0
  else ARun.Cur.Cap := AEl.Style.LineCap;
  if (AEl.CanvasFlags and cTyCanvasJoinLeft) <> 0 then AEl.Style.LineJoin := ARun.Cur.Join
  else if cap then ARun.Cur.Join := 0
  else ARun.Cur.Join := AEl.Style.LineJoin;
  { ([R7-Z] a text span's own default is 2 -- TSpan's DEFAULT_TSPAN_STYLE
    [was: 10]) }
  if (AEl.CanvasFlags and cTyCanvasMiterLeft) <> 0 then AEl.Style.MiterLimit := ARun.Cur.Miter
  else if cap then ARun.Cur.Miter := 2
  else if not (AEl.Style.MiterLimit > 0) then ARun.Cur.Miter := 10
  else ARun.Cur.Miter := AEl.Style.MiterLimit;
  { the transform: refused (the unit symbol under the one kept), else the
    element's own -- [R7-V] an effect symbol's place, a caption's anchor
    and turn, one handed over (CanvasM), a symbol's frame, an own-frame
    path's, else none [was: only an effect symbol's] }
  elHasT := False;
  elM := Default(TTyMat2D);
  if (AEl.CanvasFlags and cTyCanvasTransformLeft) <> 0 then
  begin
    if ARun.Cur.HasT then PlaceEffectM(AEl, ARun.Cur.M)
    else
    begin
      ds := 1;
      if (Length(AEl.Anim.Vals) > 0) and (AEl.Anim.Vals[0] > 0) then ds := AEl.Anim.Vals[0];
      PlaceEffect(AEl, ds, ds, 0, 0, NaN);
    end;
    NanEffectHit(AEl);
    { (what the canvas keeps is what it had) }
    elHasT := ARun.Cur.HasT;
    elM := ARun.Cur.M;
  end
  else
    elHasT := TyElementCanvasTransform(AEl, elM);
  ARun.Cur.HasT := elHasT;
  if elHasT then ARun.Cur.M := elM;
  { [R7-W] THE LINE SCALE OF ITS TRANSFORM (css px): the canvas' lineWidth
    and lineDashOffset are in the element's frame -- a strokeNoScale
    symbol's width over its scale, a path's own under its pen scale }
  sEl := 1;
  if elHasT then
  begin
    sEl := Sqrt(Abs(elM[0] * elM[3] - elM[1] * elM[2])) / ARun.Ds;
    if IsNan(sEl) or IsInfinite(sEl) or not (sEl > 1e-12) then sEl := 1;
  end;
  ps := 1;
  if (not IsNan(AEl.Style.PenScale)) and (AEl.Style.PenScale > 0) then ps := AEl.Style.PenScale;
  { [R7-W] THE FILL AND THE PEN'S COLOUR: bindPathAndTextCommonStyle assigns
    every string fill / stroke (the canvas refuses one no parser reads,
    keeping the one it had), brushPath a gradient's CanvasGradient; a text
    its spans' (a plate's first) }
  { [R7-Y] THE FONT: a text sets `style.font || DEFAULT_FONT`, refused where
    the canvas does not parse it (the font it had: the last text's, else
    '10px sans-serif'); each piece of a rich text its own [was: the
    label's own fallback] }
  if cap then
  begin
    if (Length(AEl.Caption.RtPieces) = 0) and ((AEl.CanvasFlags and cTyCanvasFontLeft) <> 0) then
    begin
      if ARun.Cur.HasFont then
      begin
        AEl.Caption.FontName := ARun.Cur.FontFamily;
        AEl.Caption.FontSizeLogical := TyFontSizeFromPx(ARun.Cur.FontPx);
        AEl.Caption.FontWeight := ARun.Cur.FontWeight;
      end
      else
      begin
        AEl.Caption.FontName := 'sans-serif';
        AEl.Caption.FontSizeLogical := TyFontSizeFromPx(10);
        AEl.Caption.FontWeight := 400;
      end;
    end
    else if Length(AEl.Caption.RtPieces) = 0 then
    begin
      ARun.Cur.HasFont := True;
      ARun.Cur.FontFamily := AEl.Caption.FontName;
      { (a theme's size is points, an author's px: TyOptFontSize) }
      if TyFontSizeIsPx(AEl.Caption.FontSizeLogical) then
        ARun.Cur.FontPx := TyFontPxOf(AEl.Caption.FontSizeLogical)
      else
        ARun.Cur.FontPx := AEl.Caption.FontSizeLogical * 96 / 72;
      ARun.Cur.FontWeight := AEl.Caption.FontWeight;
    end
    else
      for k := 0 to High(AEl.Caption.RtPieces) do
        if (AEl.Caption.RtPieces[k].Kind = rpkText) and (AEl.Caption.RtPieces[k].Text <> '') then
        begin
          ARun.Cur.HasFont := True;
          ARun.Cur.FontFamily := AEl.Caption.RtPieces[k].FontFamily;
          ARun.Cur.FontPx := AEl.Caption.RtPieces[k].FontSizePx;
          ARun.Cur.FontWeight := AEl.Caption.RtPieces[k].FontWeight;
        end;
  end;
  if cap then
  begin
    if Length(AEl.Caption.RtPieces) = 0 then
    begin
      if (AEl.CanvasFlags and cTyCanvasTextFillLeft) <> 0 then AEl.Caption.Colour := ARun.Cur.Fill
      else
      begin
        ARun.Cur.Fill := AEl.Caption.Colour;
        ARun.Cur.FillGrad := Default(TTyChartGradient);
        ARun.Cur.FillPat := Default(TTyChartPattern);
      end;
      if (AEl.CanvasFlags and cTyCanvasTextStrokeLeft) <> 0 then
        AEl.Caption.StrokeColour := ARun.Cur.Stroke
      else if AEl.Caption.StrokeWidthLogical > 0 then
      begin
        ARun.Cur.Stroke := AEl.Caption.StrokeColour;
        ARun.Cur.StrokeGrad := Default(TTyChartGradient);
      end;
      if AEl.Caption.StrokeWidthLogical > 0 then ARun.Cur.LineWidth := AEl.Caption.StrokeWidthLogical;
    end
    else
      for k := 0 to High(AEl.Caption.RtPieces) do
      begin
        pc := @AEl.Caption.RtPieces[k];
        if (pc^.Kind = rpkText) and (pc^.Text = '') then Continue;
        if pc^.HasFill then
        begin
          if (pc^.CanvasLeft and 1) <> 0 then pc^.Fill := ARun.Cur.Fill
          else
          begin
            ARun.Cur.Fill := pc^.Fill;
            ARun.Cur.FillGrad := Default(TTyChartGradient);
            ARun.Cur.FillPat := Default(TTyChartPattern);
          end;
        end;
        if pc^.HasStroke then
        begin
          if (pc^.CanvasLeft and 2) <> 0 then pc^.Stroke := ARun.Cur.Stroke
          else
          begin
            ARun.Cur.Stroke := pc^.Stroke;
            ARun.Cur.StrokeGrad := Default(TTyChartGradient);
          end;
          if pc^.LineWidth > 0 then ARun.Cur.LineWidth := pc^.LineWidth;
        end;
      end;
  end
  else
  begin
    if (AEl.CanvasFlags and cTyCanvasFillLeft) <> 0 then
    begin
      AEl.Style.FillColor := ARun.Cur.Fill;
      { [R7-Y] a held gradient's points under this element's transform, a
        held pattern in this element's frame [was: the gradient where the
        element before had it, a pattern none] }
      AEl.Style.FillGradient := GradUnder(ARun.Cur.FillGrad, ARun.Cur.FillGradHasT,
        ARun.Cur.FillGradM, elHasT, elM, ARun.Ds);
      AEl.Style.FillPattern := Default(TTyChartPattern);
      if ARun.Cur.FillPat.Present then
      begin
        AEl.Style.FillPattern := ARun.Cur.FillPat;
        TyPatternMatrix(ARun.Cur.FillPat, pm);
        if elHasT then TyPatternUnder(elM, ARun.Ds, pm);
        AEl.Style.FillPattern.HasMatrix := True;
        AEl.Style.FillPattern.UnitImage := False;
        AEl.Style.FillPattern.HasCrop := False;
        for k := 0 to 5 do AEl.Style.FillPattern.Matrix[k] := pm[k];
      end;
    end
    else if AEl.Style.HasFill then
    begin
      if AEl.Style.FillPattern.Present then
      begin
        { [R7-Y] an image (drawImage) sets no fillStyle; a pattern the
          canvas keeps, its matrix taken in the frame of whichever fills
          with it [was: none kept] }
        if not AEl.Style.FillPattern.UnitImage then
        begin
          ARun.Cur.Fill := 0;
          ARun.Cur.FillGrad := Default(TTyChartGradient);
          ARun.Cur.FillPat := AEl.Style.FillPattern;
        end;
      end
      else
      begin
        ARun.Cur.Fill := AEl.Style.FillColor;
        ARun.Cur.FillGrad := CanvasGradOf(AEl.Style.FillGradient, AEl, ARun.Ds);
        ARun.Cur.FillGradHasT := elHasT;
        ARun.Cur.FillGradM := elM;
        ARun.Cur.FillPat := Default(TTyChartPattern);
      end;
    end;
    { the pen's width: [R7-W] 'Infinity' refused (kept) }
    if (AEl.CanvasFlags and cTyCanvasWidthLeft) <> 0 then
      AEl.Style.StrokeWidthLogical := ARun.Cur.LineWidth * sEl / ps;
    strokes := AEl.Style.StrokeWidthLogical > 0;
    if (AEl.CanvasFlags and cTyCanvasStrokeLeft) <> 0 then
    begin
      AEl.Style.StrokeColor := ARun.Cur.Stroke;
      AEl.Style.StrokeGradient := GradUnder(ARun.Cur.StrokeGrad, ARun.Cur.StrokeGradHasT,
        ARun.Cur.StrokeGradM, elHasT, elM, ARun.Ds);
    end
    else if strokes then
    begin
      ARun.Cur.Stroke := AEl.Style.StrokeColor;
      ARun.Cur.StrokeGrad := CanvasGradOf(AEl.Style.StrokeGradient, AEl, ARun.Ds);
      ARun.Cur.StrokeGradHasT := elHasT;
      ARun.Cur.StrokeGradM := elM;
    end
    { [R7-Y] A COLOUR OF NO WIDTH: bindPathAndTextCommonStyle assigns every
      string stroke, whatever the width (a gradient only where it strokes)
      [was: only where it strokes] }
    else if (AEl.Style.StrokeGradient.Kind = cgkNone) and ((AEl.Style.StrokeColor shr 24) <> 0) then
    begin
      ARun.Cur.Stroke := AEl.Style.StrokeColor;
      ARun.Cur.StrokeGrad := Default(TTyChartGradient);
    end;
    if strokes and ((AEl.CanvasFlags and cTyCanvasWidthLeft) = 0) then
      ARun.Cur.LineWidth := AEl.Style.StrokeWidthLogical * ps / sEl;
    { the dash's phase: [R7-W] no number refused (kept); a dashed pen sets
      it, a solid one leaves it }
    dashed := strokes and ((Length(AEl.Style.DashLogical) > 0) or (AEl.Style.DashWord <> 0));
    if (AEl.CanvasFlags and cTyCanvasPhaseLeftFlag) <> 0 then
      AEl.Style.DashOffsetLogical := ARun.Cur.Phase * sEl / ps
    else if dashed then
      ARun.Cur.Phase := AEl.Style.DashOffsetLogical * ps / sEl;
  end;
end;

procedure TyLinesCanvasLeftovers(AList: TTyPaintList; const AGround: TTyCanvasGround;
  APPI: Integer);
var
  i: Integer;
  run: TTyCanvasRun;
begin
  if not TyLinesCanvasLeftoversDue(AList) then Exit;
  TyCanvasRunStart(run, AGround, APPI);
  for i := 0 to AList.Count - 1 do
    TyCanvasRunStep(run, AList.Ref(AList.PaintOrder(i))^);
end;

procedure TyLinesCanvasLeftovers(AList: TTyPaintList; AGround: TTyChartColor);
begin
  TyLinesCanvasLeftovers(AList, TyCanvasGroundOf(AGround), 96);
end;

procedure TyLinesFrameLine(var AEl: TTyChartElement; APercent: Double);
var g: TTyLinesGeom;
begin
  g := GeomOfG(AEl);
  if not (APercent > 0) then
  begin
    AEl.Style.StrokeWidthLogical := 0;
    AEl.Silent := True;
    Exit;
  end;
  AEl.Shape.Points := LinePoints(g, False, APercent, AEl.Anim.G[11]);
  { [R7-F] the quadratic the pointer tests: the first part's control point
    (quadraticSubdivide at the percent), as the points are drawn }
  if AEl.Shape.HitQuad and g.Curved then
    if APercent < 1 then
      AEl.Shape.HitCP := TyPointF((g.CP.X - g.Pts[0].X) * APercent + g.Pts[0].X,
        (g.CP.Y - g.Pts[0].Y) * APercent + g.Pts[0].Y)
    else AEl.Shape.HitCP := g.CP;
end;

procedure TyLinesFrameSymbol(var AEl: TTyChartElement; APercent: Double);
var g: TTyLinesGeom; at: TTyPointF; pd: string; lm: TTyMat2D; rot: Double;
begin
  if not (APercent > 0) then
  begin
    AEl.Style.HasFill := False;
    AEl.Style.StrokeWidthLogical := 0;
    AEl.Silent := True;
    { [R7-Y] scaled to nought: shouldBePainted's `!m[0] && !m[3]`, not
      brushed, nothing handed to the canvas }
    AEl.CanvasM := TTyDoubleArray.Create(0, 0, 0, 0, 0, 0);
    Exit;
  end;
  g := GeomOfG(AEl);
  { the start at pointAt(0), the end at pointAt(percent), both scaled by the
    percent; the turn is the tangent's at 0 and at 1 whatever the percent }
  if AEl.Anim.Role = carLinesFrom then at := TyLinesPointAt(g, 0)
  else at := TyLinesPointAt(g, APercent);
  { [R7-Y] the transform it hands the canvas now: placed there, scaled by the
    percent (a new array: the frame's copy shares the list's) [was: the one
    at rest] }
  rot := AEl.Anim.G[11];
  if IsNan(rot) then rot := 0;
  lm := TyZrLocal(APercent, APercent, rot, at.X, at.Y);
  AEl.CanvasM := TTyDoubleArray.Create(lm[0], lm[1], lm[2], lm[3], lm[4], lm[5]);
  pd := AEl.Shape.PathData;
  AEl.Shape := EndSymbolShape(TTySymbolKind(Round(AEl.Anim.G[7])), AEl.Anim.G[10] <> 0,
    pd, AEl.Anim.G[8] * APercent, AEl.Anim.G[9] * APercent, at.X, at.Y, AEl.Anim.G[11]);
  { [R7-Y] its hit in its frame, scaled by the percent }
  EndSymbolHitFrame(AEl, TTySymbolKind(Round(AEl.Anim.G[7])), AEl.Anim.G[8], AEl.Anim.G[9],
    APercent, AEl.Anim.G[11], at.X, at.Y);
  { [spec 242] the symbol is scaled by the percent: its gradient too }
  PlaceLocalGrad(AEl, APercent, APercent, AEl.Anim.G[11], at.X, at.Y);
end;

{ [R6-A] A LINES ROW'S LABEL UNDER A STATE'S rotation / offset (where
  AHasRot / AHasOff, else its own), at percent 1: where it is drawn, its
  turn, and label.x / y before the offset }
function TyLinesLabelState(const AEl: TTyChartElement; AHasRot: Boolean;
  ARot: Double; AHasOff: Boolean; AOffX, AOffY: Double;
  out AX, AY, ARotOut, ABuX, ABuY: Double): Boolean;
var
  g: TTyLinesGeom;
  x, y, ox, oy, lr, lox, loy: Double;
  hasRot, hasOff: Boolean;
  ah: TTyTextAnchorH;
  av: TTyTextAnchorV;
begin
  g := GeomOfG(AEl);
  hasRot := (Length(AEl.Anim.Vals) >= 5) and (AEl.Anim.Vals[0] <> 0);
  hasOff := (Length(AEl.Anim.Vals) >= 5) and (AEl.Anim.Vals[2] <> 0);
  lr := 0;
  lox := 0;
  loy := 0;
  if Length(AEl.Anim.Vals) >= 5 then
  begin
    lr := AEl.Anim.Vals[1];
    lox := AEl.Anim.Vals[3];
    loy := AEl.Anim.Vals[4];
  end;
  if AHasRot then
  begin
    hasRot := True;
    lr := ARot;
  end;
  if AHasOff then
  begin
    hasOff := True;
    lox := AOffX;
    loy := AOffY;
  end;
  TyLinesLabelPlace(g, 1, TTyLinesLabelPos(Round(AEl.Anim.G[7])), AEl.Anim.G[8],
    AEl.Anim.G[9], hasRot, lr, hasOff, lox, loy, x, y, ox, oy, ARotOut, AX, AY, ah, av);
  ABuX := x;
  ABuY := y;
  if hasOff then
  begin
    ABuX := x - lox;
    ABuY := y - loy;
  end;
  Result := not (IsNan(AX) or IsNan(AY) or IsNan(ABuX) or IsNan(ABuY));
end;

procedure TyLinesFrameLabel(var AEl: TTyChartElement; APercent: Double);
var
  g: TTyLinesGeom;
  x, y, ox, oy, rot, ax, ay, x1, y1, rot1, ax1, ay1, dx, dy, lr, lox, loy: Double;
  hasRot, hasOff: Boolean;
  ah, ah1: TTyTextAnchorH;
  av, av1: TTyTextAnchorV;
  flags: Integer;
  pos: TTyLinesLabelPos;
begin
  if not (APercent > 0) then
  begin
    AEl.Caption.Text := '';
    AEl.Silent := True;
    AEl.Style.Alpha := 0;
    Exit;
  end;
  g := GeomOfG(AEl);
  pos := TTyLinesLabelPos(Round(AEl.Anim.G[7]));
  { [spec 242] the textConfig the line carried over: every frame }
  hasRot := (Length(AEl.Anim.Vals) >= 5) and (AEl.Anim.Vals[0] <> 0);
  hasOff := (Length(AEl.Anim.Vals) >= 5) and (AEl.Anim.Vals[2] <> 0);
  if Length(AEl.Anim.Vals) >= 5 then
  begin
    lr := AEl.Anim.Vals[1];
    lox := AEl.Anim.Vals[3];
    loy := AEl.Anim.Vals[4];
  end
  else
  begin
    lr := 0;
    lox := 0;
    loy := 0;
  end;
  TyLinesLabelPlace(g, APercent, pos, AEl.Anim.G[8], AEl.Anim.G[9], hasRot, lr,
    hasOff, lox, loy, x, y, ox, oy, rot, ax, ay, ah, av);
  TyLinesLabelPlace(g, 1, pos, AEl.Anim.G[8], AEl.Anim.G[9], hasRot, lr,
    hasOff, lox, loy, x1, y1, ox, oy, rot1, ax1, ay1, ah1, av1);
  { where the line puts it now (the rest is where it puts it at 1), the box
    moved with it; turned and aligned anew where the author did not align
    it }
  if not (IsNan(ax) or IsNan(ay) or IsNan(ax1) or IsNan(ay1)) then
  begin
    dx := ax - AEl.Caption.X;
    dy := ay - AEl.Caption.Y;
    AEl.Caption.X := ax;
    AEl.Caption.Y := ay;
    AEl.Shape.Bounds := TyRectF(AEl.Shape.Bounds.Left + dx, AEl.Shape.Bounds.Top + dy,
      AEl.Shape.Bounds.Right + dx, AEl.Shape.Bounds.Bottom + dy);
  end;
  flags := Round(AEl.Anim.G[10]);
  if (flags and 1) = 0 then AEl.Caption.AnchorH := ah;
  if (flags and 2) = 0 then AEl.Caption.AnchorV := av;
  AEl.Caption.RotationRad := rot;
  { LabelManager's fade on the series' timing: the rest opacity times the
    eased percent, to the bit }
  AEl.Style.Alpha := AEl.Style.Alpha * APercent;
end;

{ ==================== gradients in an element's frame [spec 242] ==================== }

function TyLinesPlacedGradient(const ALocal: TTyChartGradient; const ABox: TTyXYWH;
  ASX, ASY, ARot, AX, AY: Double): TTyChartGradient;
var
  m: TTyMat2D;
  x1, y1, x2, y2, r: Double;
begin
  Result := ALocal;
  if ALocal.Kind = cgkNone then Exit;
  m := TyZrLocal(ASX, ASY, ARot, AX, AY);
  TyResolveGradientXYWH(ALocal, ABox, x1, y1, x2, y2, r);
  Result.Global := True;
  TyZrApply(m, x1, y1, Result.X, Result.Y);
  TyZrApply(m, x2, y2, Result.X2, Result.Y2);
  Result.R := r * Sqrt(Abs(m[0] * m[3] - m[1] * m[2]));
end;

function TyLinesLineBox(const AG: TTyLinesGeom; ALineWidth: Double): TTyXYWH;
var p: TTyZrPath;
begin
  p := nil;
  if Length(AG.Pts) < 2 then Exit(TyXYWH(0, 0, 0, 0));
  TyZrMoveTo(p, AG.Pts[0].X, AG.Pts[0].Y);
  if AG.Curved then
  begin
    SetLength(p, 2);
    p[1] := Default(TTyZrSeg);
    p[1].Cmd := zrQ;
    p[1].V[0] := AG.CP.X;
    p[1].V[1] := AG.CP.Y;
    p[1].V[2] := AG.Pts[1].X;
    p[1].V[3] := AG.Pts[1].Y;
  end
  else
    TyZrLineTo(p, AG.Pts[1].X, AG.Pts[1].Y);
  Result := TyZrStrokeRect(TyZrBBox(p), TyZrDataLength(p), True, False, ALineWidth, 1);
end;

{ the local gradient of an end symbol or an effect symbol onto its style,
  for the transform it has now }
procedure PlaceLocalGrad(var AEl: TTyChartElement; ASX, ASY, ARot, AX, AY: Double);
var g: TTyChartGradient;
begin
  if AEl.Anim.LGrad.Kind = cgkNone then Exit;
  g := TyLinesPlacedGradient(AEl.Anim.LGrad, AEl.Anim.LGradBox, ASX, ASY, ARot, AX, AY);
  if AEl.Anim.LGradStroke then AEl.Style.StrokeGradient := g
  else AEl.Style.FillGradient := g;
end;

{ ==================== containStroke ==================== }

function TyLinesContainLine(X0, Y0, X1, Y1, ALineWidth, AX, AY: Double): Boolean;
var l, a, b, tmp, s: Double;
begin
  Result := False;
  if ALineWidth = 0 then Exit;
  l := ALineWidth;
  if ((AY > Y0 + l) and (AY > Y1 + l)) or ((AY < Y0 - l) and (AY < Y1 - l))
    or ((AX > X0 + l) and (AX > X1 + l)) or ((AX < X0 - l) and (AX < X1 - l)) then
    Exit;
  if X0 = X1 then Exit(Abs(AX - X0) <= l / 2);
  a := (Y0 - Y1) / (X0 - X1);
  b := (X0 * Y1 - X1 * Y0) / (X0 - X1);
  tmp := a * AX - AY + b;
  s := tmp * tmp / (a * a + 1);
  Result := s <= l / 2 * l / 2;
end;

{ curve.quadraticProjectPoint: a coarse pass by 0.05, then at most 32
  halvings from 0.005 }
function QuadProject(X0, Y0, X1, Y1, X2, Y2, AX, AY: Double): Double;
var
  t, tt, interval, d, d1, d2, prev, next, qx, qy: Double;
  i: Integer;
begin
  t := NaN;
  interval := 0.005;
  d := Infinity;
  tt := 0;
  while tt < 1 do
  begin
    qx := TyLinesQuadAt(X0, X1, X2, tt);
    qy := TyLinesQuadAt(Y0, Y1, Y2, tt);
    d1 := (AX - qx) * (AX - qx) + (AY - qy) * (AY - qy);
    if d1 < d then
    begin
      t := tt;
      d := d1;
    end;
    tt := tt + 0.05;
  end;
  d := Infinity;
  for i := 0 to 31 do
  begin
    if interval < 1e-4 then Break;
    prev := t - interval;
    next := t + interval;
    qx := TyLinesQuadAt(X0, X1, X2, prev);
    qy := TyLinesQuadAt(Y0, Y1, Y2, prev);
    d1 := (qx - AX) * (qx - AX) + (qy - AY) * (qy - AY);
    if (prev >= 0) and (d1 < d) then
    begin
      t := prev;
      d := d1;
    end
    else
    begin
      qx := TyLinesQuadAt(X0, X1, X2, next);
      qy := TyLinesQuadAt(Y0, Y1, Y2, next);
      d2 := (qx - AX) * (qx - AX) + (qy - AY) * (qy - AY);
      if (next <= 1) and (d2 < d) then
      begin
        t := next;
        d := d2;
      end
      else
        interval := interval * 0.5;
    end;
  end;
  Result := Sqrt(d);
end;

function TyLinesContainQuad(X0, Y0, X1, Y1, X2, Y2, ALineWidth, AX, AY: Double): Boolean;
var l: Double; mask: TFPUExceptionMask;
begin
  Result := False;
  if ALineWidth = 0 then Exit;
  l := ALineWidth;
  if ((AY > Y0 + l) and (AY > Y1 + l) and (AY > Y2 + l))
    or ((AY < Y0 - l) and (AY < Y1 - l) and (AY < Y2 - l))
    or ((AX > X0 + l) and (AX > X1 + l) and (AX > X2 + l))
    or ((AX < X0 - l) and (AX < X1 - l) and (AX < X2 - l)) then
    Exit;
  mask := SetExceptionMask([exInvalidOp, exDenormalized, exZeroDivide,
    exOverflow, exUnderflow, exPrecision]);
  try
    Result := QuadProject(X0, Y0, X1, Y1, X2, Y2, AX, AY) <= l / 2;
  finally
    ClearExceptions(False);
    SetExceptionMask(mask);
  end;
end;

end.
