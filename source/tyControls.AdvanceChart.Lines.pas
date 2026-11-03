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
procedure TyLinesCanvasLeftovers(AList: TTyPaintList; AGround: TTyChartColor);
{ whether AList holds anything TyLinesCanvasLeftovers settles (the only
  cost a chart without one pays) }
function TyLinesCanvasLeftoversDue(AList: TTyPaintList): Boolean;

{ ---- zrender's containStroke ---- }
function TyLinesContainLine(X0, Y0, X1, Y1, ALineWidth, AX, AY: Double): Boolean;
function TyLinesContainQuad(X0, Y0, X1, Y1, X2, Y2, ALineWidth, AX, AY: Double): Boolean;
{ curve.quadraticAt / quadraticDerivativeAt as zrender writes them }
function TyLinesQuadAt(AP0, AP1, AP2, AT: Double): Double;
function TyLinesQuadDerivAt(AP0, AP1, AP2, AT: Double): Double;

implementation

uses tyControls.AdvanceChart.JsMath, tyControls.AdvanceChart.Data,
  tyControls.AdvanceChart.Scale, tyControls.AdvanceChart.Symbol,
  tyControls.AdvanceChart.ZrPath, tyControls.AdvanceChart.GfxEl;

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
  for i := 0 to High(ASolved.Geoms) do
  begin
    g := ASolved.Geoms[i];
    if not g.Drawn or (i > High(ASolved.Inks)) then Continue;
    ink := ASolved.Inks[i];
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
    AEl.Anim.Vals := TTyDoubleArray.Create(ds);
    PlaceEffect(AEl, ds, ds, 0, 0, NaN);
    Exit;
  end;
  AEl.CanvasFlags := AEl.CanvasFlags and not cTyCanvasTransformLeft;
  { the transform it leaves on the canvas: 1, then x, y, scaleX, scaleY,
    rotation }
  AEl.Anim.Vals := TTyDoubleArray.Create(ds, 1, AE.X, AE.Y, AE.ScaleX, AE.ScaleY, AE.Rotation);
  PlaceEffect(AEl, AE.ScaleX, AE.ScaleY, AE.X, AE.Y, AE.Rotation);
end;

function TyLinesCanvasLeftoversDue(AList: TTyPaintList): Boolean;
var i: Integer;
begin
  Result := False;
  if AList = nil then Exit;
  for i := 0 to AList.Count - 1 do
    if (AList.Ref(i)^.CanvasFlags and (cTyCanvasShadowLeft or cTyCanvasTransformLeft)) <> 0 then
      Exit(True);
end;

procedure TyLinesCanvasLeftovers(AList: TTyPaintList; AGround: TTyChartColor);
type
  TCanvasState = record
    Shadow: TTyChartColor;
    HasT: Boolean;
    TX, TY, TSX, TSY, TRot: Double;
  end;
var
  i, zl, cs: Integer;
  pe: PTyChartElement;
  cur, saved: TCanvasState;
  inClip, first, clipped: Boolean;
  cr: TTyRectF;
  ds: Double;
begin
  if not TyLinesCanvasLeftoversDue(AList) then Exit;
  first := True;
  zl := 0;
  cs := 0;
  inClip := False;
  cur := Default(TCanvasState);
  saved := cur;
  cr := TyRectF(0, 0, 0, 0);
  for i := 0 to AList.Count - 1 do
  begin
    pe := AList.Ref(AList.PaintOrder(i));
    { what the painter skips: ignored, held back, of no opacity }
    if pe^.Ignore or pe^.ProgHidden or not (pe^.Style.Alpha > 0) then Continue;
    if first or (pe^.ZLevel <> zl) then
    begin
      first := False;
      zl := pe^.ZLevel;
      cur := Default(TCanvasState);
      if zl = 0 then cur.Shadow := AGround;
      inClip := False;
    end;
    { a clip path: saved on entering, restored on leaving or changing (a
      series' group clip its own, whatever its rect) }
    clipped := pe^.HasClip or pe^.HasClipSector;
    if inClip and (not clipped or (pe^.Datum.SeriesIndex <> cs)
      or (pe^.ClipRect.Left <> cr.Left) or (pe^.ClipRect.Top <> cr.Top)
      or (pe^.ClipRect.Right <> cr.Right) or (pe^.ClipRect.Bottom <> cr.Bottom)) then
    begin
      cur := saved;
      inClip := False;
    end;
    if clipped and not inClip then
    begin
      saved := cur;
      inClip := True;
      cs := pe^.Datum.SeriesIndex;
      cr := pe^.ClipRect;
    end;
    { the shadowColor: refused (kept), the symbol's own, a written one, else
      zrender's '#000' }
    if (pe^.CanvasFlags and cTyCanvasShadowLeft) <> 0 then
      pe^.Style.ShadowColor := cur.Shadow
    else if (pe^.CanvasFlags and cTyCanvasOwnShadow) <> 0 then
      cur.Shadow := pe^.CanvasShadow
    else if (pe^.Style.ShadowColor shr 24) <> 0 then
      cur.Shadow := pe^.Style.ShadowColor
    else
      cur.Shadow := TTyChartColor($FF000000);
    { the transform: refused (the unit symbol under the one kept), an effect
      symbol's own, else none }
    if (pe^.CanvasFlags and cTyCanvasTransformLeft) <> 0 then
    begin
      if cur.HasT then PlaceEffect(pe^, cur.TSX, cur.TSY, cur.TX, cur.TY, cur.TRot)
      else
      begin
        ds := 1;
        if (Length(pe^.Anim.Vals) > 0) and (pe^.Anim.Vals[0] > 0) then ds := pe^.Anim.Vals[0];
        PlaceEffect(pe^, ds, ds, 0, 0, NaN);
      end;
    end
    else if (pe^.Anim.Role = carLinesEffect) and (Length(pe^.Anim.Vals) >= 7)
      and (pe^.Anim.Vals[1] = 1) then
    begin
      cur.HasT := True;
      cur.TX := pe^.Anim.Vals[2];
      cur.TY := pe^.Anim.Vals[3];
      cur.TSX := pe^.Anim.Vals[4];
      cur.TSY := pe^.Anim.Vals[5];
      cur.TRot := pe^.Anim.Vals[6];
    end
    else
      cur.HasT := False;
  end;
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
var g: TTyLinesGeom; at: TTyPointF; pd: string;
begin
  if not (APercent > 0) then
  begin
    AEl.Style.HasFill := False;
    AEl.Style.StrokeWidthLogical := 0;
    AEl.Silent := True;
    Exit;
  end;
  g := GeomOfG(AEl);
  { the start at pointAt(0), the end at pointAt(percent), both scaled by the
    percent; the turn is the tangent's at 0 and at 1 whatever the percent }
  if AEl.Anim.Role = carLinesFrom then at := TyLinesPointAt(g, 0)
  else at := TyLinesPointAt(g, APercent);
  pd := AEl.Shape.PathData;
  AEl.Shape := EndSymbolShape(TTySymbolKind(Round(AEl.Anim.G[7])), AEl.Anim.G[10] <> 0,
    pd, AEl.Anim.G[8] * APercent, AEl.Anim.G[9] * APercent, at.X, at.Y, AEl.Anim.G[11]);
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
