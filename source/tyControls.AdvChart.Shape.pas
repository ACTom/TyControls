unit tyControls.AdvChart.Shape;
{$mode objfpc}{$H+}
{ TTyAdvanceChart — the shape a chart element is, and whether a point is in it.

  THE POINT OF THIS UNIT is that a shape is DATA, not a pair of routines. The old
  TTyChart obeyed the TTySegmented rule by having paint and hit-test call the same
  pure functions; that works while there are three geometries and one person
  remembering. At twenty series types it does not: nothing stops a renderer from
  drawing a bar one way and the hit-test computing it another. Here the renderer
  and the hit-test are handed the SAME record, so they cannot disagree about where
  a datum went -- there is no second description to drift from.

  PURE: SysUtils, Math and AdvChart.Types only. No painter, no LCL, no handle.
  That is deliberate: hit-testing is where the bugs are, and it must be testable
  without a graphics stack. }
interface
uses SysUtils, Math, tyControls.AdvChart.Types, tyControls.SubPixel;

type
  TTyChartShapeKind = (
    cskRect,        // Bounds
    cskRoundRect,   // Bounds + RadiusPx
    cskCircle,      // CX, CY, R1
    cskEllipse,     // CX, CY, RX = R0, RY = R1
    cskSector,      // CX, CY, R0..R1, StartRad..EndRad -- a pie slice or a ring band
    cskPolyline,    // Points, an open stroked run
    cskPolygon,     // Points, a closed filled area
    cskPath         // PathData, an SVG path:// symbol
  );

  TTyPointFArray = array of TTyPointF;

  { One element's geometry, DEVICE px throughout. A single record for every kind
    rather than a class hierarchy: a scatter series makes one of these per datum,
    and an object per point is an allocation per point. }
  TTyChartShape = record
    Kind: TTyChartShapeKind;
    Bounds: TTyRectF;                 // rect / roundRect / path
    RadiusPx: Double;                 // roundRect corner
    CX, CY: Double;                   // circle / ellipse / sector centre
    R0, R1: Double;                   // sector inner/outer; ellipse rx/ry; circle r in R1
    StartRad, EndRad: Double;         // sector sweep, CLOCKWISE, matching the painter
    Points: TTyPointFArray;           // polyline / polygon
    PathData: string;                 // path
  end;

{ ---- constructors, so a caller never has to remember which fields a kind uses ---- }
function TyShapeRect(const ABounds: TTyRectF): TTyChartShape;
function TyShapeRoundRect(const ABounds: TTyRectF; ARadiusPx: Double): TTyChartShape;
function TyShapeCircle(ACX, ACY, AR: Double): TTyChartShape;
function TyShapeEllipse(ACX, ACY, ARX, ARY: Double): TTyChartShape;
function TyShapeSector(ACX, ACY, AR0, AR1, AStartRad, AEndRad: Double): TTyChartShape;
function TyShapePolyline(const APoints: array of TTyPointF): TTyChartShape;
function TyShapePolygon(const APoints: array of TTyPointF): TTyChartShape;
function TyShapePath(const APathData: string; const ABounds: TTyRectF): TTyChartShape;

{ The bounding box, DEVICE px. Invalid (all NaN) when the shape has no extent --
  an empty polyline, say -- rather than an empty rect at the origin, which is
  indistinguishable from a legitimately collapsed one. }
function TyShapeBounds(const AShape: TTyChartShape): TTyRectF;

{ Is (AX, AY) in the shape, allowing ASlopPx of tolerance outside it?

  CLOSED on every edge, unlike TyRectFContains which is half-open. The half-open
  rule exists for the CELL question -- which of two abutting bands owns a column
  of pixels -- where nothing else can break the tie. Here the paint list breaks
  ties by z order, so closed is both simpler and right; and once ASlopPx > 0 the
  distinction is meaningless anyway, because the shape has been inflated.

  For cskPolyline, ASlopPx IS the hit ribbon's half-width: a line series wants a
  forgiving band around a 1 px stroke, not the stroke itself. }
function TyShapeContains(const AShape: TTyChartShape; AX, AY, ASlopPx: Double): Boolean;

{ Shortest distance from a point to a segment. Exported because the polyline hit
  test is the one piece of this that a series renderer may want to reuse (a line
  chart snapping the tooltip to the nearest point on the line). }
function TyDistanceToSegment(APX, APY, AX1, AY1, AX2, AY2: Double): Double;

{ Angle normalised into [0, 2*Pi). }
function TyNormalizeAngle(AAngleRad: Double): Double;

{ A copy of AShape with its AXIS-ALIGNED edges snapped so a stroke of
  AStrokeWidthPx lands on whole pixels (see tyControls.SubPixel).

  SNAP AT SHAPE-BUILD TIME, not at render time. Both the renderer and the hit
  test read this record, so snapping here keeps them looking at the same
  geometry; snapping inside the renderer would leave the hit test answering
  about the unsnapped shape and put a half-pixel of disagreement along every
  edge -- exactly the drift this layer is arranged to prevent.

  Only rects and axis-aligned two-point polylines are touched. A circle, a
  sector or a curve gains nothing from snapping (it has no long straight edge
  lying along the pixel grid) and would be distorted by it, so those come back
  unchanged. }
function TySnapShape(const AShape: TTyChartShape;
  AStrokeWidthPx: Double): TTyChartShape;

implementation

function TyNormalizeAngle(AAngleRad: Double): Double;
begin
  Result := AAngleRad;
  if IsNan(Result) or IsInfinite(Result) then Exit(0);
  while Result < 0 do
    Result := Result + 2 * Pi;
  while Result >= 2 * Pi do
    Result := Result - 2 * Pi;
end;

function TyDistanceToSegment(APX, APY, AX1, AY1, AX2, AY2: Double): Double;
var
  dx, dy, len2, t, qx, qy: Double;
begin
  dx := AX2 - AX1;
  dy := AY2 - AY1;
  len2 := dx * dx + dy * dy;
  if len2 <= 0 then
  begin
    { A degenerate segment is a point -- not an error, and not a divide. }
    Result := Sqrt(Sqr(APX - AX1) + Sqr(APY - AY1));
    Exit;
  end;
  t := ((APX - AX1) * dx + (APY - AY1) * dy) / len2;
  { Clamp to the SEGMENT. Without this the distance is to the infinite line, and
    a hover far past the end of a line series would report a hit. }
  if t < 0 then t := 0;
  if t > 1 then t := 1;
  qx := AX1 + t * dx;
  qy := AY1 + t * dy;
  Result := Sqrt(Sqr(APX - qx) + Sqr(APY - qy));
end;

{ ---- constructors ---- }

function EmptyShape(AKind: TTyChartShapeKind): TTyChartShape;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.Kind := AKind;
  Result.Bounds := TyInvalidRectF;
  Result.PathData := '';
  Result.Points := nil;
end;

function TyShapeRect(const ABounds: TTyRectF): TTyChartShape;
begin
  Result := EmptyShape(cskRect);
  Result.Bounds := ABounds;
end;

function TyShapeRoundRect(const ABounds: TTyRectF; ARadiusPx: Double): TTyChartShape;
begin
  Result := EmptyShape(cskRoundRect);
  Result.Bounds := ABounds;
  if ARadiusPx < 0 then ARadiusPx := 0;
  Result.RadiusPx := ARadiusPx;
end;

function TyShapeCircle(ACX, ACY, AR: Double): TTyChartShape;
begin
  Result := EmptyShape(cskCircle);
  Result.CX := ACX;
  Result.CY := ACY;
  Result.R1 := Abs(AR);
end;

function TyShapeEllipse(ACX, ACY, ARX, ARY: Double): TTyChartShape;
begin
  Result := EmptyShape(cskEllipse);
  Result.CX := ACX;
  Result.CY := ACY;
  Result.R0 := Abs(ARX);
  Result.R1 := Abs(ARY);
end;

function TyShapeSector(ACX, ACY, AR0, AR1, AStartRad, AEndRad: Double): TTyChartShape;
var
  t: Double;
begin
  Result := EmptyShape(cskSector);
  Result.CX := ACX;
  Result.CY := ACY;
  Result.R0 := Abs(AR0);
  Result.R1 := Abs(AR1);
  if Result.R0 > Result.R1 then
  begin
    t := Result.R0;
    Result.R0 := Result.R1;
    Result.R1 := t;
  end;
  Result.StartRad := AStartRad;
  Result.EndRad := AEndRad;
end;

function CopyPoints(const APoints: array of TTyPointF): TTyPointFArray;
var i: Integer;
begin
  SetLength(Result, Length(APoints));
  for i := 0 to High(APoints) do
    Result[i] := APoints[i];
end;

function TyShapePolyline(const APoints: array of TTyPointF): TTyChartShape;
begin
  Result := EmptyShape(cskPolyline);
  Result.Points := CopyPoints(APoints);
end;

function TyShapePolygon(const APoints: array of TTyPointF): TTyChartShape;
begin
  Result := EmptyShape(cskPolygon);
  Result.Points := CopyPoints(APoints);
end;

function TyShapePath(const APathData: string; const ABounds: TTyRectF): TTyChartShape;
begin
  Result := EmptyShape(cskPath);
  Result.PathData := APathData;
  Result.Bounds := ABounds;
end;

{ ---- bounds ---- }

function PointsBounds(const APoints: TTyPointFArray): TTyRectF;
var
  i: Integer;
  any: Boolean;
begin
  Result := TyInvalidRectF;
  any := False;
  for i := 0 to High(APoints) do
  begin
    if IsNan(APoints[i].X) or IsNan(APoints[i].Y) then
      Continue;                       { a NaN point is a gap, not a vertex }
    if not any then
    begin
      Result := TyRectF(APoints[i].X, APoints[i].Y, APoints[i].X, APoints[i].Y);
      any := True;
    end
    else
    begin
      if APoints[i].X < Result.Left then Result.Left := APoints[i].X;
      if APoints[i].X > Result.Right then Result.Right := APoints[i].X;
      if APoints[i].Y < Result.Top then Result.Top := APoints[i].Y;
      if APoints[i].Y > Result.Bottom then Result.Bottom := APoints[i].Y;
    end;
  end;
end;

function TyShapeBounds(const AShape: TTyChartShape): TTyRectF;
begin
  case AShape.Kind of
    cskRect, cskRoundRect, cskPath:
      Result := AShape.Bounds;
    cskCircle:
      Result := TyRectF(AShape.CX - AShape.R1, AShape.CY - AShape.R1,
                        AShape.CX + AShape.R1, AShape.CY + AShape.R1);
    cskEllipse:
      Result := TyRectF(AShape.CX - AShape.R0, AShape.CY - AShape.R1,
                        AShape.CX + AShape.R0, AShape.CY + AShape.R1);
    cskSector:
      { The outer disc, not a tight fit to the sweep. A tight bound would have to
        find which axis-crossings the sweep covers; the disc is correct (it
        contains the sector) and this is a broad-phase box, not a hit test. }
      Result := TyRectF(AShape.CX - AShape.R1, AShape.CY - AShape.R1,
                        AShape.CX + AShape.R1, AShape.CY + AShape.R1);
    cskPolyline, cskPolygon:
      Result := PointsBounds(AShape.Points);
  else
    Result := TyInvalidRectF;
  end;
end;

{ ---- containment ---- }

function RectContainsClosed(const AR: TTyRectF; AX, AY, ASlop: Double): Boolean;
begin
  if not TyRectFIsValid(AR) then Exit(False);
  Result := (AX >= AR.Left - ASlop) and (AX <= AR.Right + ASlop)
        and (AY >= AR.Top - ASlop) and (AY <= AR.Bottom + ASlop);
end;

function RoundRectContains(const AR: TTyRectF; ARadius, AX, AY, ASlop: Double): Boolean;
var
  r, cx, cy: Double;
begin
  if not RectContainsClosed(AR, AX, AY, ASlop) then Exit(False);
  r := ARadius;
  { Clamp the same way a renderer would, so the hit area cannot be a shape the
    painter never draws. }
  if r > TyRectFWidth(AR) / 2 then r := TyRectFWidth(AR) / 2;
  if r > TyRectFHeight(AR) / 2 then r := TyRectFHeight(AR) / 2;
  if r <= 0 then Exit(True);
  { Only the four corner boxes can reject; everything else already passed. }
  if (AX < AR.Left + r) and (AY < AR.Top + r) then
  begin
    cx := AR.Left + r; cy := AR.Top + r;
  end
  else if (AX > AR.Right - r) and (AY < AR.Top + r) then
  begin
    cx := AR.Right - r; cy := AR.Top + r;
  end
  else if (AX < AR.Left + r) and (AY > AR.Bottom - r) then
  begin
    cx := AR.Left + r; cy := AR.Bottom - r;
  end
  else if (AX > AR.Right - r) and (AY > AR.Bottom - r) then
  begin
    cx := AR.Right - r; cy := AR.Bottom - r;
  end
  else
    Exit(True);
  Result := Sqrt(Sqr(AX - cx) + Sqr(AY - cy)) <= r + ASlop;
end;

function SectorContains(const AShape: TTyChartShape; AX, AY, ASlop: Double): Boolean;
var
  dx, dy, dist, ang, s, e, sweep, rel: Double;
begin
  dx := AX - AShape.CX;
  dy := AY - AShape.CY;
  dist := Sqrt(dx * dx + dy * dy);
  if (dist < AShape.R0 - ASlop) or (dist > AShape.R1 + ASlop) then
    Exit(False);
  sweep := AShape.EndRad - AShape.StartRad;
  { A full turn (or more) covers every angle. Testing it through the normalised
    comparison below would wrap to zero and reject everything -- which is how a
    single-slice pie ends up un-hittable. }
  if Abs(sweep) >= 2 * Pi - 1e-9 then
    Exit(True);
  if sweep < 0 then
  begin
    s := AShape.EndRad;
    e := AShape.StartRad;
  end
  else
  begin
    s := AShape.StartRad;
    e := AShape.EndRad;
  end;
  ang := TyNormalizeAngle(ArcTan2(dy, dx));
  { Measure both the point and the end relative to the start, so a sweep that
    crosses the 0/2pi seam needs no special case. }
  rel := TyNormalizeAngle(ang - TyNormalizeAngle(s));
  Result := rel <= TyNormalizeAngle(e - s) + 1e-12;
end;

function PolylineNear(const APoints: TTyPointFArray; AX, AY, ASlop: Double): Boolean;
var
  i: Integer;
begin
  { A polyline describes a STROKE, so it hits only near a segment that was
    actually stroked. Fewer than two consecutive valid vertices means nothing
    was drawn, and claiming a hit there would break the one invariant this layer
    is built on -- that the pointer and the pixels agree.

    That is not a hole in the chart: an isolated datum is hoverable through its
    SYMBOL, which is its own element with its own circular shape in the paint
    list. If the series draws no symbol either, then nothing was drawn and
    nothing should answer. }
  Result := False;
  if Length(APoints) < 2 then Exit;
  for i := 1 to High(APoints) do
  begin
    { A NaN vertex is a gap in the series -- connectNulls off. The segments on
      either side of it do not exist and must not be hittable. }
    if IsNan(APoints[i - 1].X) or IsNan(APoints[i - 1].Y)
    or IsNan(APoints[i].X) or IsNan(APoints[i].Y) then
      Continue;
    if TyDistanceToSegment(AX, AY, APoints[i - 1].X, APoints[i - 1].Y,
                           APoints[i].X, APoints[i].Y) <= ASlop then
      Exit(True);
  end;
end;

function PolygonContains(const APoints: TTyPointFArray; AX, AY: Double): Boolean;
var
  i, j: Integer;
begin
  { Even-odd ray casting. Even-odd rather than winding for the same reason the
    painter defaults a ring to it: a shape with a hole must report the hole as
    outside. }
  Result := False;
  j := High(APoints);
  for i := 0 to High(APoints) do
  begin
    if ((APoints[i].Y > AY) <> (APoints[j].Y > AY))
    and (AX < (APoints[j].X - APoints[i].X) * (AY - APoints[i].Y)
              / (APoints[j].Y - APoints[i].Y) + APoints[i].X) then
      Result := not Result;
    j := i;
  end;
end;

function TySnapShape(const AShape: TTyChartShape;
  AStrokeWidthPx: Double): TTyChartShape;
var
  l, t, r, b, x1, y1, x2, y2: Double;
begin
  Result := AShape;
  if AStrokeWidthPx <= 0 then Exit;
  case AShape.Kind of
    cskRect, cskRoundRect:
      begin
        if not TyRectFIsValid(AShape.Bounds) then Exit;
        l := AShape.Bounds.Left;
        t := AShape.Bounds.Top;
        r := AShape.Bounds.Right;
        b := AShape.Bounds.Bottom;
        TySubPixelRect(l, t, r, b, AStrokeWidthPx);
        Result.Bounds := TyRectF(l, t, r, b);
      end;
    cskPolyline:
      begin
        { Only a two-point run, and only the axis it is straight on. Snapping a
          vertex in the middle of a data line would move a datum, which is a far
          worse crime than a soft edge. }
        if Length(AShape.Points) <> 2 then Exit;
        x1 := AShape.Points[0].X;
        y1 := AShape.Points[0].Y;
        x2 := AShape.Points[1].X;
        y2 := AShape.Points[1].Y;
        if IsNan(x1) or IsNan(y1) or IsNan(x2) or IsNan(y2) then Exit;
        TySubPixelLine(x1, y1, x2, y2, AStrokeWidthPx);
        SetLength(Result.Points, 2);
        Result.Points[0] := TyPointF(x1, y1);
        Result.Points[1] := TyPointF(x2, y2);
      end;
  end;
end;

function TyShapeContains(const AShape: TTyChartShape; AX, AY, ASlopPx: Double): Boolean;
var
  ndx, ndy, rx, ry: Double;
  closed: TTyPointFArray;
  n: Integer;
begin
  if IsNan(AX) or IsNan(AY) then Exit(False);
  if ASlopPx < 0 then ASlopPx := 0;
  case AShape.Kind of
    cskRect:
      Result := RectContainsClosed(AShape.Bounds, AX, AY, ASlopPx);
    cskRoundRect:
      Result := RoundRectContains(AShape.Bounds, AShape.RadiusPx, AX, AY, ASlopPx);
    cskCircle:
      Result := Sqrt(Sqr(AX - AShape.CX) + Sqr(AY - AShape.CY))
                <= AShape.R1 + ASlopPx;
    cskEllipse:
      begin
        rx := AShape.R0 + ASlopPx;
        ry := AShape.R1 + ASlopPx;
        if (rx <= 0) or (ry <= 0) then Exit(False);
        ndx := (AX - AShape.CX) / rx;
        ndy := (AY - AShape.CY) / ry;
        Result := ndx * ndx + ndy * ndy <= 1;
      end;
    cskSector:
      Result := SectorContains(AShape, AX, AY, ASlopPx);
    cskPolyline:
      Result := PolylineNear(AShape.Points, AX, AY, ASlopPx);
    cskPolygon:
      begin
        n := Length(AShape.Points);
        if n < 3 then Exit(PolylineNear(AShape.Points, AX, AY, ASlopPx));
        Result := PolygonContains(AShape.Points, AX, AY);
        { Also accept a point near the OUTLINE, so a polygon squeezed to a
          sliver -- a near-zero-height area band -- is still hittable at all.
          Closing the ring first, because the outline includes the last edge. }
        if (not Result) and (ASlopPx > 0) then
        begin
          SetLength(closed, n + 1);
          Move(AShape.Points[0], closed[0], n * SizeOf(TTyPointF));
          closed[n] := AShape.Points[0];
          Result := PolylineNear(closed, AX, AY, ASlopPx);
        end;
      end;
    cskPath:
      { Bounds, not the path itself: resolving arbitrary SVG path data exactly
        needs a rasteriser, which this layer deliberately has no access to. For
        what cskPath is FOR -- a path:// custom symbol, typically six to twenty
        pixels across -- a bounds hit is not a compromise but the better answer,
        because a pixel-exact target on a small glyph is one the pointer keeps
        missing. A caller wanting exactness has TTyPainter.PathContains. }
      Result := RectContainsClosed(AShape.Bounds, AX, AY, ASlopPx);
  else
    Result := False;
  end;
end;

end.
