unit tyControls.AdvChart.Symbol;
{$mode objfpc}{$H+}
{ The symbol a datum is drawn as: ECharts' symbol / symbolSize / symbolRotate /
  symbolOffset / symbolKeepAspect.

  A PORT OF src/util/symbol.ts, read off the ECharts 6.1.0 source. Every shape
  here is the geometry that file builds, transcribed rather than eyeballed --
  a triangle whose apex is a few pixels off is the kind of thing that looks
  fine in isolation and wrong beside the chart it is copying.

  WHY NOT REUSE tyControls.Shape. That unit has a triangle and a diamond, and
  they are NOT these: it serves the classic TTyShape control, its vocabulary is
  its own (star, squared diamond, four triangle rotations), and the vertices it
  computes answer to that control rather than to ECharts. Two shape families
  that merely overlap are not one family, and sharing them would mean every
  future ECharts symbol had to be argued about in a control's vocabulary.

  EVERYTHING BECOMES A POLYGON except a circle, a rounded rect and a path.
  That is not laziness: the paint list's shape record has no rotation, and a
  polygon can simply be built rotated. One code path that always works beats a
  fast path that silently ignores symbolRotate for half the shapes.

  PURE: SysUtils, Math, fpjson and the AdvChart units. No painter, no LCL. }
interface

uses
  SysUtils, Math, fpjson,
  tyControls.AdvChart.Types, tyControls.AdvChart.Shape;

type
  { The built-in names. `tsyNone` draws nothing and is a real answer, not a
    failure -- `symbol: 'none'` is how a line asks for no markers. }
  TTySymbolKind = (tsyNone, tsyCircle, tsyRect, tsyRoundRect, tsySquare,
                   tsyTriangle, tsyDiamond, tsyPin, tsyArrow, tsyLine,
                   tsyPath);

  TTySymbolSpec = record
    Kind: TTySymbolKind;
    { The `empty` prefix. Upstream draws these stroked in the series colour and
      filled with the theme's own background token -- not with white, which is
      why the fill colour is asked of the caller rather than decided here. }
    Empty: Boolean;
    { tsyPath only: the body of `path://...`, in SVG path syntax. }
    PathData: string;
    { Device pixels. symbolSize is a number or a [w, h] pair. }
    WidthPx: Double;
    HeightPx: Double;
    { Degrees, clockwise on screen. }
    RotateDeg: Double;
    OffsetX: Double;
    OffsetY: Double;
    { A PERCENTAGE OFFSET is of the symbol's own size (parsePercent against
      symbolSize), so it is kept as a fraction and resolved once the row's
      size is known -- TySymbolResolveOffset. [Batch 71] }
    OffsetXIsPct, OffsetYIsPct: Boolean;
    OffsetXPct, OffsetYPct: Double;
    { ONLY `path://` AND `image://` CONSULT THIS. createSymbol passes it to
      makePath/makeImage as the bounding-rect fit mode and never to a built-in
      shape, so squaring a triangle's box off would be this port's invention. }
    KeepAspect: Boolean;
  end;
  TTySymbolSpecArray = array of TTySymbolSpec;

{ A spec with upstream's defaults for a series type: symbolSize is 10 for a
  scatter and 6 for a line, and neither is written down anywhere else. }
function TySymbolDefault(const ASeriesType: string): TTySymbolSpec;

{ The offset in px for the size the spec now has: a percentage is of the
  width (x) and the height (y). }
function TySymbolResolveOffset(const ASpec: TTySymbolSpec): TTySymbolSpec;

{ THE RECT A SYMBOL'S LABEL IS PLACED AGAINST, zrender's way: the symbol's
  UNIT path box (createSymbol(-1, -1, 2, 2)), grown by the stroke in unit
  space -- lineWidth over the line scale, at least 5 where nothing is filled
  -- then carried through the symbol's transform: scale to half its size,
  turn by symbolRotate, move by symbolOffset and to the point. A turned
  symbol answers the box of its turned unit rect. [Batch 73] }
function TySymbolLabelBox(const ASpec: TTySymbolSpec; APX, APY: Double;
  ALineWidth: Double; AHasStroke, AHasFill: Boolean): TTyXYWH;

{ Read `symbol`, `symbolSize`, `symbolRotate`, `symbolOffset` and
  `symbolKeepAspect` off a series node, over the given defaults. }
function TySymbolSpecOf(ANode: TJSONObject;
  const ADefault: TTySymbolSpec): TTySymbolSpec;

{ The name ECharts uses, parsed.

  AN UNRECOGNISED NAME IS A RECT, not nothing. SymbolClz.buildPath looks the
  name up in symbolBuildProxies and, finding nothing, sets symbolType to
  'rect' and draws that -- so `symbol: 'blah'` and `legend.icon: 'inherit'`
  on a series that has no icon of its own both come out as sharp-cornered
  boxes. This port used to answer tsyNone there, which drew nothing.

  THREE NAMES REALLY ARE NOTHING: the empty string, 'none', and an
  `image://` URL -- the first two because upstream tests symbolType !== 'none'
  before it ever reaches the proxy table, the third because upstream draws a
  picture and a pure unit has nowhere to put one. A grey box would be a worse
  answer than no box. }
function TySymbolKindOf(const AName: string; out AEmpty: Boolean;
  out APath: string): TTySymbolKind;

{ The shape for one datum, centred on (ACX, ACY) and already offset and
  rotated. Answers a shape of kind cskRect with an invalid Bounds when the spec
  draws nothing -- callers test TyRectFIsValid, or simply skip tsyNone. }
function TyBuildSymbol(const ASpec: TTySymbolSpec;
  ACX, ACY: Double): TTyChartShape;

{ THE SAME SYMBOL IN A GIVEN BOX, which is a DIFFERENT PICTURE for two of the
  kinds -- and the difference is upstream's, not a simplification here.

  A DATUM's symbol is built in the UNIT box (-1, -1, 2, 2) and the element is
  then scaled by (symbolSize[0] / 2, symbolSize[1] / 2). A LEGEND ICON is built
  in a real 25 x 14 box and never scaled. The shape makers read w and h either
  way, so the unit box hides what they do with them:

    circle -- r = min(w, h) / 2. In the unit box min(2, 2) is a no-op and the
              non-uniform scale afterwards turns the circle into an ELLIPSE; in
              a real 25 x 14 box it is a circle of radius 7.
    square -- side = min(w, h), KEEPING THE BOX'S TOP-LEFT. In the unit box that
              is indistinguishable from rect; in a 25 x 14 box it is a 14 x 14
              square flush with the left edge.

  Everything else centres on the box and uses both extents, so it is the same
  shape either way and is delegated. }
function TyBuildSymbolInBox(const ASpec: TTySymbolSpec;
  const ABox: TTyRectF): TTyChartShape;

implementation

uses tyControls.AdvChart.ZrPath;

const
  { ScatterSeries.defaultOption.symbolSize / LineSeries.defaultOption.symbolSize. }
  cScatterSymbolSize = 10;
  cLineSymbolSize = 6;
  { How finely a curved symbol is sampled. Pin is the only one with curves, and
    it is a marker a few pixels across: 12 steps per arc is already finer than
    the pixels it lands on. }
  cCurveSteps = 12;

function TySymbolDefault(const ASeriesType: string): TTySymbolSpec;
begin
  { EVERY FIELD FROM ZERO FIRST. The record is filled field by field below,
    and a field added to it later and not named here is whatever the stack
    held -- [Batch 73: the percentage offsets were, and an offset resolved
    against garbage moved a symbol by garbage] }
  Result := Default(TTySymbolSpec);
  Result.Kind := tsyCircle;
  Result.PathData := '';
  if (ASeriesType = 'scatter') or (ASeriesType = 'effectScatter') then
  begin
    { ScatterSeries and EffectScatterSeries: symbol 'circle', symbolSize 10,
      solid. }
    Result.Empty := False;
    Result.WidthPx := cScatterSymbolSize;
    Result.HeightPx := cScatterSymbolSize;
  end
  else if ASeriesType = 'tree' then
  begin
    { TreeSeries: symbol 'emptyCircle', symbolSize 7 [Batch 73] }
    Result.Empty := True;
    Result.WidthPx := 7;
    Result.HeightPx := 7;
  end
  else if ASeriesType = 'radar' then
  begin
    { RadarSeries writes NO symbol, only symbolSize 8, and RadarView falls
      back to a solid 'circle'. [Batch 57: a radar took the line's hollow
      six-pixel ring.] }
    Result.Empty := False;
    Result.WidthPx := 8;
    Result.HeightPx := 8;
  end
  else
  begin
    { LineSeries: symbol 'emptyCircle', symbolSize 6. EMPTY, which is why an
      ECharts line has rings on its points rather than dots -- a detail easy to
      miss because both are circles, and wrong in a way that only shows against
      the original. }
    Result.Empty := True;
    Result.WidthPx := cLineSymbolSize;
    Result.HeightPx := cLineSymbolSize;
  end;
  Result.RotateDeg := 0;
  Result.OffsetX := 0;
  Result.OffsetY := 0;
  Result.KeepAspect := False;
end;

function TySymbolKindOf(const AName: string; out AEmpty: Boolean;
  out APath: string): TTySymbolKind;
var s: string;
begin
  AEmpty := False;
  APath := '';
  s := Trim(AName);
  if s = '' then Exit(tsyNone);

  { `path://` and `image://` are prefixes, not names. Only the first is
    supported: the shape record can carry SVG path data, and there is nowhere
    for an image to live in a pure unit. }
  if Copy(s, 1, 7) = 'path://' then
  begin
    APath := Copy(s, 8, MaxInt);
    Exit(tsyPath);
  end;
  if Copy(s, 1, 8) = 'image://' then Exit(tsyNone);

  { The `empty` prefix is stripped and the rest lower-cased at its first
    letter, exactly as upstream does it: emptyCircle -> circle. }
  if (Length(s) > 5) and (Copy(s, 1, 5) = 'empty') then
  begin
    AEmpty := True;
    s := LowerCase(Copy(s, 6, 1)) + Copy(s, 7, MaxInt);
  end;

  if s = 'none' then Exit(tsyNone);
  if s = 'circle' then Exit(tsyCircle);
  if s = 'rect' then Exit(tsyRect);
  if s = 'roundRect' then Exit(tsyRoundRect);
  if s = 'square' then Exit(tsySquare);
  if s = 'triangle' then Exit(tsyTriangle);
  if s = 'diamond' then Exit(tsyDiamond);
  if s = 'pin' then Exit(tsyPin);
  if s = 'arrow' then Exit(tsyArrow);
  if s = 'line' then Exit(tsyLine);
  { symbol.ts:296-301 -- `if (!proxySymbol) { symbolType = 'rect'; ... }`. }
  Result := tsyRect;
end;

function PctNum(const S: string): Double;
var fs: TFormatSettings;
begin
  fs := DefaultFormatSettings;
  fs.DecimalSeparator := '.';
  Result := StrToFloatDef(Trim(S), NaN, fs);
end;

{ symbolSize is a number or a two-element array; a callback cannot survive the
  trip through JSON and is simply absent. }
procedure ReadSize(ANode: TJSONObject; var ASpec: TTySymbolSpec);
var
  d: TJSONData;
  a: TJSONArray;
begin
  d := ANode.Find('symbolSize');
  if d = nil then Exit;
  if d.JSONType = jtNumber then
  begin
    ASpec.WidthPx := d.AsFloat;
    ASpec.HeightPx := d.AsFloat;
    Exit;
  end;
  { `+symbolSize`: a numeric string is its number [Batch 71] }
  if (d.JSONType = jtString) and not IsNan(PctNum(d.AsString)) then
  begin
    ASpec.WidthPx := PctNum(d.AsString);
    ASpec.HeightPx := ASpec.WidthPx;
    Exit;
  end;
  if not (d is TJSONArray) then Exit;
  a := TJSONArray(d);
  { EACH ELEMENT TYPE-CHECKED, because `Floats[]` COERCES: handed the string
    `'80%'` it does not return zero, it RAISES -- and a paint that raises
    takes the host's window, which is a worse outcome than any wrong number.

    And the percentage is not a typo. `symbolSize: ['80%', '60%']` is how a
    pictorialBar is written, against the band width rather than in pixels,
    and two of the gallery's own entries carry it. Until that series type
    draws, the value has no consumer; it is LEFT AT THE DEFAULT rather than
    guessed at, which is what ReadOffset just below already did. }
  if (a.Count > 0) and (a.Items[0].JSONType = jtNumber) then
    ASpec.WidthPx := a.Floats[0];
  { normalizeSymbolSize: `[w, h]` taken as written, a missing height is
    `undefined || 0` -- so `[8]` is eight wide and nothing tall, not a
    square [Batch 71: it was doubled] }
  if (a.Count > 1) and (a.Items[1].JSONType = jtNumber) then
    ASpec.HeightPx := a.Floats[1]
  else if a.Count <= 1 then
    ASpec.HeightPx := 0;
end;

{ One offset: a number as px, a string ending in '%' as a fraction of the
  size, any other string parseFloat'd as px. }
procedure ReadOffsetOne(AData: TJSONData; var APx: Double; var AIsPct: Boolean;
  var APct: Double);
var
  s: string;
  v: Double;
begin
  AIsPct := False;
  APx := 0;
  if AData = nil then Exit;
  if AData.JSONType = jtNumber then
    APx := AData.AsFloat
  else if AData.JSONType = jtString then
  begin
    s := Trim(AData.AsString);
    if (s <> '') and (s[Length(s)] = '%') then
    begin
      v := PctNum(Copy(s, 1, Length(s) - 1));
      if not IsNan(v) then
      begin
        AIsPct := True;
        APct := v / 100;
      end;
    end
    else
    begin
      v := PctNum(s);
      if not IsNan(v) then APx := v;
    end;
  end;
end;

procedure ReadOffset(ANode: TJSONObject; var ASpec: TTySymbolSpec);
var
  d: TJSONData;
  a: TJSONArray;
begin
  d := ANode.Find('symbolOffset');
  if d = nil then Exit;
  { normalizeSymbolOffset: a single value is both offsets }
  if not (d is TJSONArray) then
  begin
    ReadOffsetOne(d, ASpec.OffsetX, ASpec.OffsetXIsPct, ASpec.OffsetXPct);
    ReadOffsetOne(d, ASpec.OffsetY, ASpec.OffsetYIsPct, ASpec.OffsetYPct);
    Exit;
  end;
  a := TJSONArray(d);
  if a.Count > 0 then
    ReadOffsetOne(a.Items[0], ASpec.OffsetX, ASpec.OffsetXIsPct, ASpec.OffsetXPct);
  if a.Count > 1 then
    ReadOffsetOne(a.Items[1], ASpec.OffsetY, ASpec.OffsetYIsPct, ASpec.OffsetYPct)
  else
    ReadOffsetOne(nil, ASpec.OffsetY, ASpec.OffsetYIsPct, ASpec.OffsetYPct);
end;

function TySymbolLabelBox(const ASpec: TTySymbolSpec; APX, APY: Double;
  ALineWidth: Double; AHasStroke, AHasFill: Boolean): TTyXYWH;
var
  lx, ly, lw, lh, m0, m1, m2, m3, m4, m5, r, st, ct, ls, w: Double;
  ub: TTyXYWH;
  xs, ys: array[0..3] of Double;
  k: Integer;
begin
  { the unit path's own box: every built-in shape fills -1..1 but the pin,
  the arrow (its tip at the centre, its body a whole height below) and the
  line (across the middle) [Batch 112: the arrow's and the line's] }
  lx := -1; ly := -1; lw := 2; lh := 2;
  if ASpec.Kind = tsyPin then
  begin
    lx := -0.6000000000000001;
    ly := -1.7428571428571429;
    lw := 1.2000000000000002;
    lh := 1.7428571428571429;
  end
  else if ASpec.Kind = tsyArrow then
  begin
    { px -/+ w / 3 * 2 about px = 0; py = 0 down to py + h }
    w := 2 / 3 * 2;
    lx := 0 - w;
    lw := (0 + w) - (0 - w);
    ly := 0;
    lh := 2;
  end
  else if ASpec.Kind = tsyLine then
  begin
    ly := 0;
    lh := 0;
  end
  else if ASpec.Kind = tsyPath then
  begin
    { an icon is fitted into the unit box -- stretched over it, or keeping
      its aspect -- and stored in single precision: its own box }
    if ASpec.KeepAspect then
      ub := TyZrBBox(TyZrMakePathCenter(ASpec.PathData, TyXYWH(-1, -1, 2, 2)))
    else
      ub := TyZrBBox(TyZrMakePathCover(ASpec.PathData, TyXYWH(-1, -1, 2, 2)));
    lx := ub.X;
    ly := ub.Y;
    lw := ub.W;
    lh := ub.H;
  end;
  { scale, rotate, translate (Transformable.getLocalTransform), then the
    group's move to the point }
  r := ASpec.RotateDeg * Pi / 180;
  st := Sin(r);
  ct := Cos(r);
  m0 := ASpec.WidthPx / 2 * ct;
  m1 := -(ASpec.WidthPx / 2) * st;
  m2 := ASpec.HeightPx / 2 * st;
  m3 := ASpec.HeightPx / 2 * ct;
  if r = 0 then
  begin
    m0 := ASpec.WidthPx / 2;
    m1 := 0;
    m2 := 0;
    m3 := ASpec.HeightPx / 2;
  end;
  m4 := ASpec.OffsetX + APX;
  m5 := ASpec.OffsetY + APY;
  { the stroke, in unit space: strokeNoScale divides by the line scale }
  if AHasStroke then
  begin
    w := ALineWidth;
    if not AHasFill then w := Max(w, 5.0);
    if (Abs(m0 - 1) > 1e-10) and (Abs(m3 - 1) > 1e-10) then
      ls := Sqrt(Abs(m0 * m3 - m2 * m1))
    else
      ls := 1;
    if ls > 1e-10 then
    begin
      lw := lw + w / ls;
      lh := lh + w / ls;
      lx := lx - w / ls / 2;
      ly := ly - w / ls / 2;
    end;
  end;
  { BoundingRect.applyTransform: a fast path when nothing turns }
  if (m1 < 1e-5) and (m1 > -1e-5) and (m2 < 1e-5) and (m2 > -1e-5) then
  begin
    Result.X := lx * m0 + m4;
    Result.Y := ly * m3 + m5;
    Result.W := lw * m0;
    Result.H := lh * m3;
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
    Exit;
  end;
  xs[0] := m0 * lx + m2 * ly + m4;               ys[0] := m1 * lx + m3 * ly + m5;
  xs[1] := m0 * (lx + lw) + m2 * (ly + lh) + m4; ys[1] := m1 * (lx + lw) + m3 * (ly + lh) + m5;
  xs[2] := m0 * lx + m2 * (ly + lh) + m4;        ys[2] := m1 * lx + m3 * (ly + lh) + m5;
  xs[3] := m0 * (lx + lw) + m2 * ly + m4;        ys[3] := m1 * (lx + lw) + m3 * ly + m5;
  Result.X := xs[0];
  Result.Y := ys[0];
  for k := 1 to 3 do
  begin
    if xs[k] < Result.X then Result.X := xs[k];
    if ys[k] < Result.Y then Result.Y := ys[k];
  end;
  Result.W := Max(Max(xs[0], xs[1]), Max(xs[2], xs[3])) - Result.X;
  Result.H := Max(Max(ys[0], ys[1]), Max(ys[2], ys[3])) - Result.Y;
end;

function TySymbolResolveOffset(const ASpec: TTySymbolSpec): TTySymbolSpec;
begin
  Result := ASpec;
  if ASpec.OffsetXIsPct then Result.OffsetX := ASpec.OffsetXPct * ASpec.WidthPx;
  if ASpec.OffsetYIsPct then Result.OffsetY := ASpec.OffsetYPct * ASpec.HeightPx;
end;

function TySymbolSpecOf(ANode: TJSONObject;
  const ADefault: TTySymbolSpec): TTySymbolSpec;
var
  d: TJSONData;
  empty: Boolean;
  path: string;
begin
  Result := ADefault;
  if ANode = nil then Exit;

  d := ANode.Find('symbol');
  if (d <> nil) and (d.JSONType = jtString) then
  begin
    Result.Kind := TySymbolKindOf(d.AsString, empty, path);
    Result.Empty := empty;
    Result.PathData := path;
  end;

  ReadSize(ANode, Result);
  ReadOffset(ANode, Result);

  d := ANode.Find('symbolRotate');
  if (d <> nil) and (d.JSONType = jtNumber) then Result.RotateDeg := d.AsFloat;

  d := ANode.Find('symbolKeepAspect');
  if (d <> nil) and (d.JSONType = jtBoolean) then
    Result.KeepAspect := d.AsBoolean;
end;

{ ---- geometry ---- }

type
  TPointList = record
    Pts: TTyPointFArray;
    N: Integer;
  end;

procedure Push(var AL: TPointList; AX, AY: Double);
begin
  if AL.N > High(AL.Pts) then SetLength(AL.Pts, Max(8, AL.N * 2));
  AL.Pts[AL.N].X := AX;
  AL.Pts[AL.N].Y := AY;
  Inc(AL.N);
end;

{ One cubic bezier, sampled. Upstream draws pin's shoulders with two of these;
  the paint list has no curve, so they are sampled into the same polygon as the
  rest of the outline rather than approximated with straight shoulders. }
procedure PushBezier(var AL: TPointList;
  AX0, AY0, ACX1, ACY1, ACX2, ACY2, AX1, AY1: Double);
var
  i: Integer;
  t, mt, a, b, c, d: Double;
begin
  for i := 1 to cCurveSteps do
  begin
    t := i / cCurveSteps;
    mt := 1 - t;
    a := mt * mt * mt;
    b := 3 * mt * mt * t;
    c := 3 * mt * t * t;
    d := t * t * t;
    Push(AL, a * AX0 + b * ACX1 + c * ACX2 + d * AX1,
             a * AY0 + b * ACY1 + c * ACY2 + d * AY1);
  end;
end;

procedure PushArc(var AL: TPointList; ACX, ACY, AR, AFrom, ATo: Double);
var
  i: Integer;
  t: Double;
begin
  for i := 0 to cCurveSteps do
  begin
    t := AFrom + (ATo - AFrom) * i / cCurveSteps;
    Push(AL, ACX + AR * Cos(t), ACY + AR * Sin(t));
  end;
end;

{ Rotate every point about the centre, then move by the offset. Rotation first:
  symbolOffset shifts the symbol on SCREEN, so rotating after it would swing
  the offset around too. }
procedure Place(var AL: TPointList; ACX, ACY: Double;
  const ASpec: TTySymbolSpec);
var
  i: Integer;
  s, c, dx, dy: Double;
begin
  if ASpec.RotateDeg <> 0 then
  begin
    { ANTICLOCKWISE FOR A POSITIVE ANGLE, which is zrender's and not the
      canvas'. Its local transform is built with matrix.rotate, whose first
      row is (cos, -sin) in a frame where y grows downward -- so the point
      (1, 0) at +90 degrees lands straight UP. The canvas' own rotate turns
      the other way, and taking it drew every rotated symbol mirrored about
      the axis the author pointed along. A half turn cannot show it, which is
      how the sign survived this long. }
    s := Sin(-DegToRad(ASpec.RotateDeg));
    c := Cos(-DegToRad(ASpec.RotateDeg));
    for i := 0 to AL.N - 1 do
    begin
      dx := AL.Pts[i].X - ACX;
      dy := AL.Pts[i].Y - ACY;
      AL.Pts[i].X := ACX + dx * c - dy * s;
      AL.Pts[i].Y := ACY + dx * s + dy * c;
    end;
  end;
  if (ASpec.OffsetX <> 0) or (ASpec.OffsetY <> 0) then
    for i := 0 to AL.N - 1 do
    begin
      AL.Pts[i].X := AL.Pts[i].X + ASpec.OffsetX;
      AL.Pts[i].Y := AL.Pts[i].Y + ASpec.OffsetY;
    end;
end;

function TyBuildSymbol(const ASpec: TTySymbolSpec;
  ACX, ACY: Double): TTyChartShape;
var
  w, h, side, r, x, y, ph, pr, dy, ang, dx, tanX, tanY, cpLen, cy: Double;
  L: TPointList;
  box: TTyRectF;
begin
  Result := TyShapeRect(TyInvalidRectF);
  { An EQUIVALENT MUTANT lives on this line and is recorded rather than
    chased: removing it changes nothing, because tsyNone has no branch in
    the case below, so the point list stays empty and the same invalid
    rect is returned two screens down. The early exit is here to say the
    rule out loud -- 'none' is an instruction, not a shape that failed. }
  if ASpec.Kind = tsyNone then Exit;
  w := ASpec.WidthPx;
  h := ASpec.HeightPx;
  if (w <= 0) or (h <= 0) then Exit;

  { NO keepAspect HERE. It reaches makePath and makeImage only; a built-in
    symbol never sees it. Squaring the box off for a triangle would be a
    invention of this port's, and an invisible one -- it only shows when
    symbolSize is written as a pair. }

  L.Pts := nil;
  L.N := 0;
  box := TyRectF(ACX - w / 2, ACY - h / 2, ACX + w / 2, ACY + h / 2);

  case ASpec.Kind of
    tsyCircle:
      begin
        { AN OBLONG symbolSize GIVES AN ELLIPSE, and this is the item the port
          got wrong first. The shape is built in the UNIT box and the element is
          then scaled by (symbolSize[0]/2, symbolSize[1]/2) -- a non-uniform
          scale -- so `symbolSize: [20, 8]` is a 20x8 ellipse on screen, not the
          radius-4 circle that Math.min(w, h) / 2 would suggest. }
        if w = h then
          Result := TyShapeCircle(ACX + ASpec.OffsetX, ACY + ASpec.OffsetY,
                                  w / 2)
        else
          Result := TyShapeEllipse(ACX + ASpec.OffsetX, ACY + ASpec.OffsetY,
                                   w / 2, h / 2);
        Exit;
      end;
    tsyRoundRect:
      begin
        if ASpec.RotateDeg = 0 then
        begin
          { r = min(w, h) / 4. Exact while the symbol is square, which is the
            only shape symbolSize usually has: upstream's corner is 0.5 in the
            unit box and is then scaled by each axis, so an oblong symbol really
            has an ELLIPTICAL corner (w/4 by h/4) that one radius cannot spell.
            The scalar is the closer of the two available wrong answers, and it
            is exactly right whenever w = h. }
          Result := TyShapeRoundRect(
            TyRectF(box.Left + ASpec.OffsetX, box.Top + ASpec.OffsetY,
                    box.Right + ASpec.OffsetX, box.Bottom + ASpec.OffsetY),
            Min(w, h) / 4);
          Exit;
        end;
        { A ROTATED ROUND RECT LOSES ITS CORNERS. The shape record cannot carry
          a rotation, so the choice is a square-cornered polygon at the right
          angle or a rounded one at the wrong angle. The angle is the thing the
          author asked for. }
        Push(L, box.Left, box.Top);
        Push(L, box.Right, box.Top);
        Push(L, box.Right, box.Bottom);
        Push(L, box.Left, box.Bottom);
      end;
    tsyPath:
      begin
        { A PATH TURNS AT DRAW TIME. Every other kind is built already turned,
          because its geometry is points; a path's is a string fitted to a box
          by the painter, so the angle has to travel with the shape. The
          painter's own rotation is the canvas' -- clockwise -- hence the
          negation, which is the same correction Place makes. }
        Result := TyShapePath(ASpec.PathData,
          TyRectF(box.Left + ASpec.OffsetX, box.Top + ASpec.OffsetY,
                  box.Right + ASpec.OffsetX, box.Bottom + ASpec.OffsetY),
          -DegToRad(ASpec.RotateDeg),
          ACX + ASpec.OffsetX, ACY + ASpec.OffsetY);
        Exit;
      end;
    tsyRect:
      begin
        Push(L, box.Left, box.Top);
        Push(L, box.Right, box.Top);
        Push(L, box.Right, box.Bottom);
        Push(L, box.Left, box.Bottom);
      end;
    tsySquare:
      begin
        { THE SAME AS rect FOR A SERIES SYMBOL. Upstream's square shape-maker
          takes Math.min(w, h) and keeps the box's top-left -- but the box it
          gets is the UNIT box, where min(2, 2) is a no-op, so the squaring and
          the top-left anchoring never bite. The difference only appears where
          createSymbol is handed a real box, which is legend icons and
          markPoint, not a datum. }
        Push(L, box.Left, box.Top);
        Push(L, box.Right, box.Top);
        Push(L, box.Right, box.Bottom);
        Push(L, box.Left, box.Bottom);
      end;
    tsyTriangle:
      begin
        Push(L, ACX, ACY - h / 2);
        Push(L, ACX + w / 2, ACY + h / 2);
        Push(L, ACX - w / 2, ACY + h / 2);
      end;
    tsyDiamond:
      begin
        Push(L, ACX, ACY - h / 2);
        Push(L, ACX + w / 2, ACY);
        Push(L, ACX, ACY + h / 2);
        Push(L, ACX - w / 2, ACY);
      end;
    tsyArrow:
      begin
        { x, y sit on the CUSP, which upstream places at the box centre -- so
          an arrow hangs below its own point. Transcribed, not tidied. }
        x := ACX;
        y := ACY;
        dx := w / 3 * 2;
        Push(L, x, y);
        Push(L, x + dx, y + h);
        Push(L, x, y + h / 4 * 3);
        Push(L, x - dx, y + h);
      end;
    tsyLine:
      begin
        { A horizontal stroke through the middle: the one symbol upstream
          strokes rather than fills. }
        Push(L, box.Left, ACY);
        Push(L, box.Right, ACY);
      end;
    tsyPin:
      begin
        { The one curved symbol. x, y are the cusp at the box centre and the
          head sits ABOVE it, so a pin points at its datum from above. }
        x := ACX;
        y := ACY;
        pr := w / 5 * 3 / 2;              { r = (width/5*3) / 2 }
        ph := Max(w / 5 * 3, h);          { height must exceed the width }
        if ph - pr <= 0 then Exit;
        dy := pr * pr / (ph - pr);
        cy := y - ph + pr + dy;
        if Abs(dy / pr) > 1 then Exit;
        ang := ArcSin(dy / pr);
        dx := Cos(ang) * pr;
        tanX := Sin(ang);
        tanY := Cos(ang);
        cpLen := pr * 0.6;
        PushArc(L, x, cy, pr, Pi - ang, 2 * Pi + ang);
        PushBezier(L,
          x + dx, cy + dy,
          x + dx - tanX * cpLen, cy + dy + tanY * cpLen,
          x + pr * 0.6, y - pr * 0.6,
          x, y);
        PushBezier(L,
          x, y,
          x - pr * 0.6, y - pr * 0.6,
          x - dx + tanX * cpLen, cy + dy + tanY * cpLen,
          x - dx, cy + dy);
      end;
  end;

  if L.N < 2 then Exit;
  Place(L, ACX, ACY, ASpec);
  SetLength(L.Pts, L.N);
  if ASpec.Kind = tsyLine then
    Result := TyShapePolyline(L.Pts)
  else
    Result := TyShapePolygon(L.Pts);
end;

function TyBuildSymbolInBox(const ASpec: TTySymbolSpec;
  const ABox: TTyRectF): TTyChartShape;
var
  spec: TTySymbolSpec;
  w, h, side: Double;
begin
  Result := TyShapeRect(TyInvalidRectF);
  if ASpec.Kind = tsyNone then Exit;
  if not TyRectFIsValid(ABox) then Exit;
  w := TyRectFWidth(ABox);
  h := TyRectFHeight(ABox);
  if (w <= 0) or (h <= 0) then Exit;

  case ASpec.Kind of
    tsyCircle:
      Exit(TyShapeCircle(ABox.Left + w / 2 + ASpec.OffsetX,
                         ABox.Top + h / 2 + ASpec.OffsetY,
                         Min(w, h) / 2));
    tsySquare:
      begin
        { TOP-LEFT, not centred: `shape.x = x` after `size = Math.min(w, h)`
          leaves the square flush with the box's near corner rather than in
          the middle of it. }
        side := Min(w, h);
        Exit(TyShapeRect(
          TyRectF(ABox.Left + ASpec.OffsetX, ABox.Top + ASpec.OffsetY,
                  ABox.Left + side + ASpec.OffsetX,
                  ABox.Top + side + ASpec.OffsetY)));
      end;
  end;

  spec := ASpec;
  spec.WidthPx := w;
  spec.HeightPx := h;
  Result := TyBuildSymbol(spec, ABox.Left + w / 2, ABox.Top + h / 2);
end;

end.
