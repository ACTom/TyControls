unit tyControls.AdvChart.Lines;
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

  THE COORDINATE HOOK. A row's coordinates go through TTyLinesProject, one
  pair at a time -- the coordinate system's dataToPoint. A cartesian, a polar
  and a calendar answer it now; a geo (D14) plugs in by answering it too.
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

  LARGE LINES are in AdvChart.Large (lgkLines); their segs come from here.

  PURE: SysUtils, Math, fpjson and the AdvChart value units. }
interface
uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Shape,
  tyControls.AdvChart.Paint, tyControls.AdvChart.Large;

const
  TyLinesSeriesTypeName = 'lines';
  { the row's one dimension }
  TyLinesValueDim = 'value';
  { upstream's default effect symbol z2 (EffectLine: symbol.z2 = 100) }
  TyLinesEffectZ2 = 100;

type
  TTyLinesValueKind = (lvkNumber, lvkString, lvkNull, lvkOther);
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
function TyLinesLabelPosOf(const AWord: string): TTyLinesLabelPos;
{ The line from its start to percent: the straight segment, or the curve's
  first part (quadraticSubdivide) as ASteps + 1 points }
function TyLinesPartPoints(const AG: TTyLinesGeom; APercent: Double;
  ASteps: Integer): TTyPointFArray;

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
{ the effect symbol where its run left it; AGone: its clip finished and the
  symbol was removed }
procedure TyLinesFrameEffect(var AEl: TTyChartElement; const AE: TTyLinesEffect;
  AGone: Boolean);
{ the run an effect element starts from (its G, Pts and Mono) }
procedure TyLinesEffectOfElement(const AEl: TTyChartElement; out AE: TTyLinesEffect);

{ ---- zrender's containStroke ---- }
function TyLinesContainLine(X0, Y0, X1, Y1, ALineWidth, AX, AY: Double): Boolean;
function TyLinesContainQuad(X0, Y0, X1, Y1, X2, Y2, ALineWidth, AX, AY: Double): Boolean;
{ curve.quadraticAt / quadraticDerivativeAt as zrender writes them }
function TyLinesQuadAt(AP0, AP1, AP2, AT: Double): Double;
function TyLinesQuadDerivAt(AP0, AP1, AP2, AT: Double): Double;

implementation

uses tyControls.AdvChart.JsMath, tyControls.AdvChart.Data,
  tyControls.AdvChart.Scale, tyControls.AdvChart.Symbol;

const
  cPi: Double = 3.141592653589793;

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
        else r.XY[k] := ValueOf(nil);
        if (c1 is TJSONArray) and (c1.Count > k) then r.XY[2 + k] := ValueOf(TJSONArray(c1).Items[k])
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
  ASteps: Integer): TTyPointFArray;
var
  k: Integer;
  p0, p1, p2, q0, q1: TTyPointF;
  t, u: Double;
begin
  Result := nil;
  if Length(AG.Pts) < 2 then Exit;
  if not AG.Curved then
  begin
    { Line.buildPath: x1 * (1 - p) + x2 * p }
    SetLength(Result, 2);
    Result[0] := AG.Pts[0];
    Result[1] := TyPointF(AG.Pts[0].X * (1 - APercent) + AG.Pts[1].X * APercent,
      AG.Pts[0].Y * (1 - APercent) + AG.Pts[1].Y * APercent);
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
end;

{ An end symbol: createSymbol(type, -w / 2, -h / 2, w, h) at the end, turned
  -- a circle is the real box's (min(w, h) / 2), the rest are the same
  picture either way and take the turn }
function EndSymbolShape(AKind: TTySymbolKind; AEmpty: Boolean; const APath: string;
  AW, AH, AX, AY, ARotRad: Double): TTyChartShape;
var spec: TTySymbolSpec;
begin
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
  if not IsNan(ARotRad) then spec.RotateDeg := RadToDeg(ARotRad);
  Result := TyBuildSymbol(spec, AX, AY);
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
  Result := TyBuildSymbol(spec, AX, AY);
end;

function LinePoints(const AG: TTyLinesGeom; APoly: Boolean; APercent: Double): TTyPointFArray;
begin
  if APoly then Exit(Copy(AG.Pts, 0, Length(AG.Pts)));
  Result := TyLinesPartPoints(AG, APercent, cLinesCurveSteps);
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

  procedure SetClip(var AEl: TTyChartElement);
  begin
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

begin
  Result := 0;
  if (AList = nil) or not ASolved.Valid then Exit;
  { LARGE: LargeLineDraw's one path, silent to nothing but its own scan }
  if ASolved.IsLarge then
  begin
    el := TyChartElement(TyShapeRect(TyRectF(0, 0, 0, 0)));
    el.Shape.Kind := cskLarge;
    el.Shape.Large := ASolved.Large;
    el.Shape.Bounds := TyLargeBounds(ASolved.Large);
    el.Style.HasFill := False;
    el.Style.StrokeColor := ASolved.LargeStroke;
    el.Style.StrokeWidthLogical := ASolved.LargeWidth;
    el.Style.Alpha := ASolved.LargeOpacity;
    el.Style.DashLogical := ASolved.LargeDash;
    el.Z := ASolved.Z;
    el.Z2 := ASolved.Z2;
    el.Silent := False;
    el.Datum := TyChartDatum(ASolved.SeriesIndex, -1, -1);
    SetClip(el);
    AList.Add(el);
    Exit(1);
  end;
  for i := 0 to High(ASolved.Geoms) do
  begin
    g := ASolved.Geoms[i];
    if not g.Drawn or (i > High(ASolved.Inks)) then Continue;
    ink := ASolved.Inks[i];
    { THE LINE: a polyline's points, a line's segment, a curve sampled }
    pts := LinePoints(g, ASolved.Poly, 1);
    el := TyChartElement(TyShapePolyline(pts));
    el.Style.HasFill := False;
    el.Style.StrokeColor := ink.Stroke;
    el.Style.StrokeWidthLogical := ink.Width;
    el.Style.Alpha := ink.Opacity;
    el.Style.DashLogical := ink.Dash;
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
      { THE LABEL, where Line.beforeUpdate puts it at percent 1; a polyline
        has none }
      if ink.LabelShow and (ink.LabelText <> '') then
      begin
        TyLinesLabelPlace(g, 1, ink.LabelPos, ink.DistX, ink.DistY, ax, ay, ox, oy,
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
        { setColor: the line's colour; an empty one is stroked in it and
          filled with the ground }
        if em then
        begin
          sym.Style.HasFill := True;
          sym.Style.FillColor := AEmptyFill;
          sym.Style.StrokeColor := ink.Stroke;
          sym.Style.StrokeWidthLogical := 1;
        end
        else if kind = tsyLine then
        begin
          { a 'line' is stroked in the colour }
          sym.Style.HasFill := False;
          sym.Style.StrokeColor := ink.Stroke;
          sym.Style.StrokeWidthLogical := 1;
        end
        else
        begin
          sym.Style.HasFill := True;
          sym.Style.FillColor := ink.Stroke;
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
      { symbolPathSetColor: a 'line' stroked in the colour, the rest filled }
      if TySymbolKindOf(ink.EffName, em, pd) = tsyLine then
      begin
        sym.Style.HasFill := False;
        sym.Style.StrokeColor := ink.EffColor;
        sym.Style.StrokeWidthLogical := 1;
      end
      else
      begin
        sym.Style.HasFill := True;
        sym.Style.FillColor := ink.EffColor;
      end;
      sym.Style.Alpha := ink.EffOpacity;
      sym.Z := ASolved.Z;
      sym.Z2 := TyLinesEffectZ2;
      { NOT A POINTER TARGET here (see the spec's deviations) }
      sym.Silent := True;
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
end;

procedure TyLinesFrameEffect(var AEl: TTyChartElement; const AE: TTyLinesEffect;
  AGone: Boolean);
var sh: TTyChartShape;
begin
  if AGone or AE.Ignore or IsNan(AE.X) or IsNan(AE.Y) then
  begin
    AEl.Shape := TyShapeRect(TyRectF(0, 0, 0, 0));
    AEl.Ignore := True;
    Exit;
  end;
  sh := EffectShape(AEl.Anim.Mono, AE.ScaleX, AE.ScaleY, AE.X, AE.Y, AE.Rotation);
  AEl.Shape := sh;
  AEl.Ignore := False;
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
  AEl.Shape.Points := LinePoints(g, False, APercent);
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
end;

procedure TyLinesFrameLabel(var AEl: TTyChartElement; APercent: Double);
var
  g: TTyLinesGeom;
  x, y, ox, oy, rot, ax, ay, x1, y1, rot1, ax1, ay1, dx, dy: Double;
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
  TyLinesLabelPlace(g, APercent, pos, AEl.Anim.G[8], AEl.Anim.G[9], x, y, ox, oy, rot,
    ax, ay, ah, av);
  TyLinesLabelPlace(g, 1, pos, AEl.Anim.G[8], AEl.Anim.G[9], x1, y1, ox, oy, rot1,
    ax1, ay1, ah1, av1);
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
