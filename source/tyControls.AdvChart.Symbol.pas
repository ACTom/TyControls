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
    { ONLY `path://` AND `image://` CONSULT THIS. createSymbol passes it to
      makePath/makeImage as the bounding-rect fit mode and never to a built-in
      shape, so squaring a triangle's box off would be this port's invention. }
    KeepAspect: Boolean;
  end;

{ A spec with upstream's defaults for a series type: symbolSize is 10 for a
  scatter and 6 for a line, and neither is written down anywhere else. }
function TySymbolDefault(const ASeriesType: string): TTySymbolSpec;

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
  Result.Kind := tsyCircle;
  Result.PathData := '';
  if ASeriesType = 'scatter' then
  begin
    { ScatterSeries: symbol 'circle', symbolSize 10, solid. }
    Result.Empty := False;
    Result.WidthPx := cScatterSymbolSize;
    Result.HeightPx := cScatterSymbolSize;
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
  if (a.Count > 1) and (a.Items[1].JSONType = jtNumber) then
    ASpec.HeightPx := a.Floats[1]
  else if a.Count <= 1 then
    ASpec.HeightPx := ASpec.WidthPx;
end;

procedure ReadOffset(ANode: TJSONObject; var ASpec: TTySymbolSpec);
var
  d: TJSONData;
  a: TJSONArray;
begin
  d := ANode.Find('symbolOffset');
  if (d = nil) or not (d is TJSONArray) then Exit;
  a := TJSONArray(d);
  { A percentage offset is of the symbol's own size. Only the numeric form is
    read here; a '50%' string is left at zero rather than guessed at. }
  if (a.Count > 0) and (a.Items[0].JSONType = jtNumber) then
    ASpec.OffsetX := a.Floats[0];
  if (a.Count > 1) and (a.Items[1].JSONType = jtNumber) then
    ASpec.OffsetY := a.Floats[1];
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
    s := Sin(DegToRad(ASpec.RotateDeg));
    c := Cos(DegToRad(ASpec.RotateDeg));
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
        Result := TyShapePath(ASpec.PathData,
          TyRectF(box.Left + ASpec.OffsetX, box.Top + ASpec.OffsetY,
                  box.Right + ASpec.OffsetX, box.Bottom + ASpec.OffsetY));
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
