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
    cskRoundRect,   // Bounds + Radii
    cskCircle,      // CX, CY, R1
    cskEllipse,     // CX, CY, RX = R0, RY = R1
    cskSector,      // CX, CY, R0..R1, StartRad..EndRad -- a pie slice or a ring band
    cskPolyline,    // Points, an open stroked run
    cskPolygon,     // Points, a closed filled area
    cskPath         // PathData, an SVG path:// symbol
  );

  TTyPointFArray = array of TTyPointF;

  { A rounded rect's four corners, CLOCKWISE FROM TOP-LEFT, matching
    zrender's RectShape.r. One radius per corner rather than one for the
    shape, because `borderRadius: [8, 8, 0, 0]` -- a bar rounded only where
    it leaves the axis -- is the commonest form there is. }
  TTyCornerRadii = array[0..3] of Double;

  { One element's geometry, DEVICE px throughout. A single record for every kind
    rather than a class hierarchy: a scatter series makes one of these per datum,
    and an object per point is an allocation per point. }
  TTyChartShape = record
    Kind: TTyChartShapeKind;
    Bounds: TTyRectF;                 // rect / roundRect / path
    Radii: TTyCornerRadii;            // roundRect corners, already clamped
    { A sector's four corners, in ZRENDER'S ORDER: inner-start, inner-end,
      outer-start, outer-end -- clockwise from inside. NOT the rect's order
      and NOT the rect's short-form rules; see TySectorRadii. }
    SectorRadii: TTyCornerRadii;
    CX, CY: Double;                   // circle / ellipse / sector centre
    R0, R1: Double;                   // sector inner/outer; ellipse rx/ry; circle r in R1
    StartRad, EndRad: Double;         // sector sweep, CLOCKWISE, matching the painter
    Points: TTyPointFArray;           // polyline / polygon
    PathData: string;                 // path
  end;

{ ---- constructors, so a caller never has to remember which fields a kind uses ---- }
function TyShapeRect(const ABounds: TTyRectF): TTyChartShape;
function TyShapeRoundRect(const ABounds: TTyRectF; ARadiusPx: Double): TTyChartShape;
{ The four-corner form. ARadii is read the way zrender reads RectShape.r:
  one value is every corner, two are the diagonals, three leave the
  top-right and bottom-left sharing the middle one, four are themselves.
  More than four are ignored past the fourth; none at all is a plain rect. }
function TyShapeRoundRect(const ABounds: TTyRectF;
  const ARadii: array of Double): TTyChartShape; overload;
{ zrender's expansion rule on its own, so a caller that has to talk about
  corners before it has a shape can. }
function TyCornerRadii(const AValues: array of Double): TTyCornerRadii;
{ True when at least one corner is actually rounded. }
function TyHasCorner(const ARadii: TTyCornerRadii): Boolean;
function TyShapeCircle(ACX, ACY, AR: Double): TTyChartShape;
function TyShapeEllipse(ACX, ACY, ARX, ARY: Double): TTyChartShape;
function TyShapeSector(ACX, ACY, AR0, AR1, AStartRad, AEndRad: Double): TTyChartShape;
{ The rounded-corner form. ACorners is read the way zrender reads
  SectorShape.cornerRadius, which is NOT how it reads a rect's: see
  TySectorRadii. }
function TyShapeSector(ACX, ACY, AR0, AR1, AStartRad, AEndRad: Double;
  const ACorners: array of Double): TTyChartShape; overload;

{ zrender's normalizeCornerRadius, Sector.ts:16-24 -- and it is a DIFFERENT
  rule from the rect's, which is the whole reason it has its own function:

    5              -> [5, 5, 5, 5]
    [5]            -> [5, 5, 0, 0]   (the rect's [5] is all four)
    [5, 10]        -> [5, 5, 10, 10] (the rect's [5, 10] is the diagonals)
    [5, 10, 15]    -> [5, 10, 15, 15]

  Order is inner-start, inner-end, outer-start, outer-end. So a one-element
  array rounds the INSIDE of a doughnut and leaves the rim square -- read as
  the rect's rule it would round everything. }
function TySectorRadii(const AValues: array of Double): TTyCornerRadii;

function TyShapePolyline(const APoints: array of TTyPointF): TTyChartShape;
function TyShapePolygon(const APoints: array of TTyPointF): TTyChartShape;
function TyShapePath(const APathData: string; const ABounds: TTyRectF): TTyChartShape;

{ ---- the path a sector traces ----

  A LIST OF PRIMITIVES RATHER THAN PAINTER CALLS, so the arithmetic can be
  asserted without a bitmap. Rounding a sector's corners is a hundred lines
  of trig (zrender's roundSector, itself d3's arc) and pixels are a poor
  place to find out which of them is wrong.

  Angles here are the painter's: radians measured clockwise from +x. }
type
  TTyPathOpKind = (pokMoveTo, pokLineTo, pokArc, pokClose);
  TTyPathOp = record
    Kind: TTyPathOpKind;
    { moveTo/lineTo target, or the arc's centre. }
    X, Y: Double;
    R: Double;
    A0, A1: Double;
    Anti: Boolean;
  end;
  TTyPathOpArray = array of TTyPathOp;

{ The whole path of a sector, corners included. Empty when it draws nothing. }
function TySectorPath(const AShape: TTyChartShape): TTyPathOpArray;

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

{ A copy of AShape grown about its own centre by ARatio.

  WHAT IT IS FOR: a hovered symbol. Upstream scales the symbol's transform
  rather than its geometry, which comes to the same picture and is not
  available here -- this layer hands the renderer finished coordinates, and a
  transform would be a second place where a shape's real position is decided.

  A SECTOR IS NOT SCALED BY THIS. A hovered pie slice grows its OUTER RADIUS by
  a number of pixels; scaling it about the disc centre would move its inner
  radius too and lift it off the hole. The caller does that one itself, which
  is why it is not a case below.

  A ratio of 1 answers the shape unchanged, and so does anything that is not a
  positive finite number -- upstream's own rule for a bad `emphasis.scale`. }
function TyScaleShape(const AShape: TTyChartShape; ARatio: Double): TTyChartShape;

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

function TyCornerRadii(const AValues: array of Double): TTyCornerRadii;
var i: Integer;
begin
  { roundRect.ts:30-55. The two- and three-value forms are not truncations
    of the four-value one -- two means the DIAGONALS and three leaves the
    top-right and bottom-left sharing the middle value. Reading them as
    `fill the rest with zero` rounds the wrong corners, which on a bar looks
    like the chart is upside down. }
  case Length(AValues) of
    0: begin
         Result[0] := 0; Result[1] := 0; Result[2] := 0; Result[3] := 0;
       end;
    1: begin
         Result[0] := AValues[0]; Result[1] := AValues[0];
         Result[2] := AValues[0]; Result[3] := AValues[0];
       end;
    2: begin
         Result[0] := AValues[0]; Result[1] := AValues[1];
         Result[2] := AValues[0]; Result[3] := AValues[1];
       end;
    3: begin
         Result[0] := AValues[0]; Result[1] := AValues[1];
         Result[2] := AValues[2]; Result[3] := AValues[1];
       end;
  else
    Result[0] := AValues[0]; Result[1] := AValues[1];
    Result[2] := AValues[2]; Result[3] := AValues[3];
  end;
  for i := 0 to 3 do
    if (Result[i] < 0) or IsNan(Result[i]) then Result[i] := 0;
end;

function TyHasCorner(const ARadii: TTyCornerRadii): Boolean;
begin
  Result := (ARadii[0] > 0) or (ARadii[1] > 0) or (ARadii[2] > 0)
    or (ARadii[3] > 0);
end;

{ Shrink the corners until adjacent pairs fit the side they share.

  PROPORTIONALLY, and per PAIR -- roundRect.ts:57-76. Clamping each radius
  on its own to half the shorter side is the obvious version and it is not
  the same shape: a rect 40 wide with corners 30 and 10 keeps their 3:1
  ratio here and comes out 30:10 rather than 20:10.

  DONE IN THE CONSTRUCTOR, not in the renderer, for the same reason a
  sector's angles are normalised here: the hit test reads the record too,
  and a shape that means two things to two readers is how a pointer ends up
  answering for ink that is not there. }
procedure ClampCorners(var ARadii: TTyCornerRadii; AWidth, AHeight: Double);

  procedure Fit(var A, B: Double; ASide: Double);
  var total: Double;
  begin
    total := A + B;
    if total > ASide then
    begin
      A := A * ASide / total;
      B := B * ASide / total;
    end;
  end;

begin
  Fit(ARadii[0], ARadii[1], AWidth);
  Fit(ARadii[2], ARadii[3], AWidth);
  Fit(ARadii[1], ARadii[2], AHeight);
  Fit(ARadii[0], ARadii[3], AHeight);
end;

function TyShapeRoundRect(const ABounds: TTyRectF;
  const ARadii: array of Double): TTyChartShape;
var t: Double;
begin
  Result := EmptyShape(cskRoundRect);
  Result.Bounds := ABounds;
  { NORMALISED FIRST, like roundRect.ts:20-28: a rect given right-to-left is
    the same rect, and corner 0 has to be its top-left either way. }
  if Result.Bounds.Right < Result.Bounds.Left then
  begin
    t := Result.Bounds.Left;
    Result.Bounds.Left := Result.Bounds.Right;
    Result.Bounds.Right := t;
  end;
  if Result.Bounds.Bottom < Result.Bounds.Top then
  begin
    t := Result.Bounds.Top;
    Result.Bounds.Top := Result.Bounds.Bottom;
    Result.Bounds.Bottom := t;
  end;
  Result.Radii := TyCornerRadii(ARadii);
  ClampCorners(Result.Radii, TyRectFWidth(Result.Bounds),
    TyRectFHeight(Result.Bounds));
end;

function TyShapeRoundRect(const ABounds: TTyRectF; ARadiusPx: Double): TTyChartShape;
begin
  Result := TyShapeRoundRect(ABounds, [ARadiusPx]);
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
  { ANGLES NORMALISED TOO, for the same reason the radii are: so the record
    means one thing to everybody who reads it.

    A negative sweep names the same wedge as the positive one between the same
    two angles, and SectorContains has always read it that way. The RENDERER
    could not: it hands both angles to ArcTo, whose sweep is measured by
    wraparound rather than by reversing direction, so (Pi/2 -> 0) painted the
    270-degree complement of the 90-degree wedge that answered the pointer.
    Swapping here fixes both at once and leaves nothing to remember at the call
    sites.

    A full turn is left alone: its two ends are equal after wrapping, so
    swapping them would turn "the whole ring" into "nothing", and the sign is
    the only thing left saying which way round it goes. }
  if (AEndRad < AStartRad) and (Abs(AEndRad - AStartRad) < 2 * Pi - 1e-9) then
  begin
    Result.StartRad := AEndRad;
    Result.EndRad := AStartRad;
  end
  else
  begin
    Result.StartRad := AStartRad;
    Result.EndRad := AEndRad;
  end;
end;

function TySectorRadii(const AValues: array of Double): TTyCornerRadii;
var i: Integer;
begin
  { Sector.ts:16-24. Two things a careful reader gets wrong here. The order is
    inner-start, inner-end, outer-start, outer-end -- inside first -- and the
    short forms are NOT the rect's: a one-element array rounds only the inner
    pair, and a two-element one is inner-pair then outer-pair rather than the
    diagonals. Reading a sector with the rect's rule rounds a doughnut's rim
    when the option asked for its hole. }
  case Length(AValues) of
    0: begin
         Result[0] := 0; Result[1] := 0; Result[2] := 0; Result[3] := 0;
       end;
    1: begin
         Result[0] := AValues[0]; Result[1] := AValues[0];
         Result[2] := 0; Result[3] := 0;
       end;
    2: begin
         Result[0] := AValues[0]; Result[1] := AValues[0];
         Result[2] := AValues[1]; Result[3] := AValues[1];
       end;
    3: begin
         Result[0] := AValues[0]; Result[1] := AValues[1];
         Result[2] := AValues[2]; Result[3] := AValues[2];
       end;
  else
    Result[0] := AValues[0]; Result[1] := AValues[1];
    Result[2] := AValues[2]; Result[3] := AValues[3];
  end;
  for i := 0 to 3 do
    if (Result[i] < 0) or IsNan(Result[i]) then Result[i] := 0;
end;

function TyShapeSector(ACX, ACY, AR0, AR1, AStartRad, AEndRad: Double;
  const ACorners: array of Double): TTyChartShape;
begin
  Result := TyShapeSector(ACX, ACY, AR0, AR1, AStartRad, AEndRad);
  Result.SectorRadii := TySectorRadii(ACorners);
end;

{ ==================== a sector's path ====================
  src/graphic/helper/roundSector.ts, transcribed. The two helpers below are
  d3's, by way of zrender, and are left in their own shapes rather than tidied:
  the second is a quadratic solved in place, and every rearrangement of it is
  a chance to move a sign. }

const
  cSectorEps = 1e-4;               { roundSector.ts:14 }

{ Where two segments cross, or nothing when they are near-parallel. }
function SegmentsCross(AX0, AY0, AX1, AY1, AX2, AY2, AX3, AY3: Double;
  out AX, AY: Double): Boolean;
var
  dx10, dy10, dx32, dy32, t: Double;
begin
  AX := 0;
  AY := 0;
  dx10 := AX1 - AX0;
  dy10 := AY1 - AY0;
  dx32 := AX3 - AX2;
  dy32 := AY3 - AY2;
  t := dy32 * dx10 - dx32 * dy10;
  { SQUARED, as upstream writes it. It is a determinant, not a distance, so the
    test is scale-dependent -- but it is upstream's, and the number it guards
    is a division by that same determinant. }
  if t * t < cSectorEps then Exit(False);
  t := (dx32 * (AY0 - AY2) - dy32 * (AX0 - AX2)) / t;
  AX := AX0 + t * dx10;
  AY := AY0 + t * dy10;
  Result := True;
end;

type
  { The centre of one corner's arc and the two tangent points on it, all as
    offsets from the SECTOR's centre. }
  TTyCornerTangent = record
    CX, CY: Double;
    X0, Y0: Double;
    X1, Y1: Double;
  end;

{ NO `clockwise` PARAMETER, though upstream has one. Its only effect is the
  sign of the perpendicular offset, and the only caller here is TySectorPath,
  whose shape has already had its angles ordered forward -- so the argument
  was True at every call site and the branch was inert. A mutant that removed
  the branch changed nothing, which is how that was noticed. The direction a
  corner bulges is still expressible: pass a NEGATIVE radius, which is what
  upstream does for the inner pair. }
function CornerTangents(AX0, AY0, AX1, AY1, ARadius, ACR: Double): TTyCornerTangent;
var
  x01, y01, lo, ox, oy, x11, y11, x10, y10, x00, y00: Double;
  dx, dy, d2, r, sgn, d, cx0, cy0, cx1, cy1, dx0, dy0, dx1, dy1: Double;
begin
  x01 := AX0 - AX1;
  y01 := AY0 - AY1;
  lo := ACR / Sqrt(x01 * x01 + y01 * y01);
  ox := lo * y01;
  oy := -lo * x01;
  x11 := AX0 + ox;
  y11 := AY0 + oy;
  x10 := AX1 + ox;
  y10 := AY1 + oy;
  x00 := (x11 + x10) / 2;
  y00 := (y11 + y10) / 2;
  dx := x10 - x11;
  dy := y10 - y11;
  d2 := dx * dx + dy * dy;
  r := ARadius - ACR;
  sgn := x11 * y10 - x10 * y11;
  if dy < 0 then d := -1 else d := 1;
  d := d * Sqrt(Max(Double(0), r * r * d2 - sgn * sgn));
  cx0 := (sgn * dy - dx * d) / d2;
  cy0 := (-sgn * dx - dy * d) / d2;
  cx1 := (sgn * dy + dx * d) / d2;
  cy1 := (-sgn * dx + dy * d) / d2;
  dx0 := cx0 - x00;
  dy0 := cy0 - y00;
  dx1 := cx1 - x00;
  dy1 := cy1 - y00;
  { Two circles are tangent to both edges; take the nearer centre. }
  if dx0 * dx0 + dy0 * dy0 > dx1 * dx1 + dy1 * dy1 then
  begin
    cx0 := cx1;
    cy0 := cy1;
  end;
  Result.CX := cx0;
  Result.CY := cy0;
  Result.X0 := -ox;
  Result.Y0 := -oy;
  Result.X1 := cx0 * (ARadius / r - 1);
  Result.Y1 := cy0 * (ARadius / r - 1);
end;

function TySectorPath(const AShape: TTyChartShape): TTyPathOpArray;
var
  ops: TTyPathOpArray;
  n: Integer;
  cx, cy, radius, innerRadius, startA, endA, arc, modArc, t: Double;
  icrStart, icrEnd, ocrStart, ocrEnd, halfRd: Double;
  ocrs, ocre, icrs, icre, ocrMax, icrMax, limOcr, limIcr: Double;
  xrs, yrs, xire, yire, xre, yre, xirs, yirs: Double;
  ix, iy, ax0, ay0, ax1, ay1, a, b, crStart, crEnd: Double;
  hasArc: Boolean;
  ct0, ct1: TTyCornerTangent;

  procedure Emit(AKind: TTyPathOpKind; AX, AY, AR, AA0, AA1: Double;
    AAnti: Boolean);
  begin
    if n > High(ops) then SetLength(ops, (n + 1) * 2);
    ops[n].Kind := AKind;
    ops[n].X := AX;
    ops[n].Y := AY;
    ops[n].R := AR;
    ops[n].A0 := AA0;
    ops[n].A1 := AA1;
    ops[n].Anti := AAnti;
    Inc(n);
  end;

  procedure MoveTo(AX, AY: Double);
  begin
    Emit(pokMoveTo, AX, AY, 0, 0, 0, False);
  end;

  procedure LineTo(AX, AY: Double);
  begin
    Emit(pokLineTo, AX, AY, 0, 0, 0, False);
  end;

  procedure EmitArc(ACX, ACY, AR, AA0, AA1: Double; AAnti: Boolean);
  begin
    Emit(pokArc, ACX, ACY, AR, AA0, AA1, AAnti);
  end;

begin
  Result := nil;
  ops := nil;
  n := 0;
  if AShape.Kind <> cskSector then Exit;

  radius := Max(Double(0), AShape.R1);
  innerRadius := Max(Double(0), AShape.R0);
  if (radius <= 0) and (innerRadius <= 0) then Exit;
  { UNREACHABLE THROUGH TyShapeSector, which orders the two radii, so a zero
    outer radius means a zero inner one and the line above has already
    returned. Kept because the record is public and a caller may fill one in
    by hand, and because it is upstream's. A mutant that removes it survives
    for that reason and not for want of a test. }
  if radius <= 0 then
  begin
    radius := innerRadius;
    innerRadius := 0;
  end;
  if innerRadius > radius then
  begin
    t := radius;
    radius := innerRadius;
    innerRadius := t;
  end;

  startA := AShape.StartRad;
  endA := AShape.EndRad;
  if IsNan(startA) or IsNan(endA) then Exit;
  cx := AShape.CX;
  cy := AShape.CY;

  arc := Abs(endA - startA);
  if arc > 2 * Pi then
  begin
    modArc := arc - Int(arc / (2 * Pi)) * (2 * Pi);
    if modArc > cSectorEps then arc := modArc;
  end;

  if not (radius > cSectorEps) then
  begin
    { A point. }
    MoveTo(cx, cy);
    Emit(pokClose, 0, 0, 0, 0, 0, False);
    SetLength(ops, n);
    Exit(ops);
  end;

  if arc > 2 * Pi - cSectorEps then
  begin
    { A WHOLE RING, AND THE PORT'S OWN CONSTRUCTION rather than upstream's.
      Upstream emits two subpaths and lets the fill rule punch the hole; this
      traces one contour -- out along the rim, back along the hole -- which
      fills correctly under either rule and describes the same area the hit
      test's annulus test does. That was settled when sectors landed and the
      render tests pin it; corners do not apply to a full ring anyway, so
      nothing new argues against it. }
    MoveTo(cx + radius * Cos(startA), cy + radius * Sin(startA));
    EmitArc(cx, cy, radius, startA, endA, False);
    if innerRadius > cSectorEps then
    begin
      LineTo(cx + innerRadius * Cos(endA), cy + innerRadius * Sin(endA));
      EmitArc(cx, cy, innerRadius, endA, startA, True);
    end
    else
      LineTo(cx, cy);
    Emit(pokClose, 0, 0, 0, 0, 0, False);
    SetLength(ops, n);
    Exit(ops);
  end;

  xrs := radius * Cos(startA);
  yrs := radius * Sin(startA);
  xire := innerRadius * Cos(endA);
  yire := innerRadius * Sin(endA);
  xre := radius * Cos(endA);
  yre := radius * Sin(endA);
  xirs := innerRadius * Cos(startA);
  yirs := innerRadius * Sin(startA);

  icrStart := 0; icrEnd := 0; ocrStart := 0; ocrEnd := 0;
  ocrMax := 0; icrMax := 0; limOcr := 0; limIcr := 0;
  hasArc := arc > cSectorEps;
  if hasArc then
  begin
    icrStart := AShape.SectorRadii[0];
    icrEnd := AShape.SectorRadii[1];
    ocrStart := AShape.SectorRadii[2];
    ocrEnd := AShape.SectorRadii[3];

    { NO CORNER MAY EXCEED HALF THE RING'S THICKNESS -- roundSector.ts:209.
      That is what stops two corners on the same radial edge meeting in the
      middle and turning the wedge inside out. }
    halfRd := Abs(radius - innerRadius) / 2;
    ocrs := Min(halfRd, ocrStart);
    ocre := Min(halfRd, ocrEnd);
    icrs := Min(halfRd, icrStart);
    icre := Min(halfRd, icrEnd);
    ocrMax := Max(ocrs, ocre);
    icrMax := Max(icrs, icre);
    limOcr := ocrMax;
    limIcr := icrMax;

    { A NARROW WEDGE HAS A SECOND LIMIT. Under half a turn the two radial edges
      converge, so a corner that fits the ring's thickness can still be too big
      to fit between them. Upstream finds where the edges cross and works back
      from the angle there. }
    if ((ocrMax > cSectorEps) or (icrMax > cSectorEps)) and (arc < Pi) then
      if SegmentsCross(xrs, yrs, xirs, yirs, xre, yre, xire, yire, ix, iy) then
      begin
        ax0 := xrs - ix;
        ay0 := yrs - iy;
        ax1 := xre - ix;
        ay1 := yre - iy;
        a := 1 / Sin(ArcCos((ax0 * ax1 + ay0 * ay1)
          / (Sqrt(ax0 * ax0 + ay0 * ay0) * Sqrt(ax1 * ax1 + ay1 * ay1))) / 2);
        b := Sqrt(ix * ix + iy * iy);
        limOcr := Min(ocrMax, (radius - b) / (a + 1));
        limIcr := Min(icrMax, (innerRadius - b) / (a - 1));
      end;
  end;

  if not hasArc then
    { Collapsed to a line. }
    MoveTo(cx + xrs, cy + yrs)
  else if limOcr > cSectorEps then
  begin
    crStart := Min(ocrStart, limOcr);
    crEnd := Min(ocrEnd, limOcr);
    ct0 := CornerTangents(xirs, yirs, xrs, yrs, radius, crStart);
    ct1 := CornerTangents(xre, yre, xire, yire, radius, crEnd);
    MoveTo(cx + ct0.CX + ct0.X0, cy + ct0.CY + ct0.Y0);
    if (limOcr < ocrMax) and (crStart = crEnd) then
      { The two corners have eaten the rim between them and merged into one. }
      EmitArc(cx + ct0.CX, cy + ct0.CY, limOcr,
        ArcTan2(ct0.Y0, ct0.X0), ArcTan2(ct1.Y0, ct1.X0), False)
    else
    begin
      if crStart > 0 then
        EmitArc(cx + ct0.CX, cy + ct0.CY, crStart,
          ArcTan2(ct0.Y0, ct0.X0), ArcTan2(ct0.Y1, ct0.X1), False);
      EmitArc(cx, cy, radius,
        ArcTan2(ct0.CY + ct0.Y1, ct0.CX + ct0.X1),
        ArcTan2(ct1.CY + ct1.Y1, ct1.CX + ct1.X1), False);
      if crEnd > 0 then
        EmitArc(cx + ct1.CX, cy + ct1.CY, crEnd,
          ArcTan2(ct1.Y1, ct1.X1), ArcTan2(ct1.Y0, ct1.X0), False);
    end;
  end
  else
  begin
    MoveTo(cx + xrs, cy + yrs);
    EmitArc(cx, cy, radius, startA, endA, False);
  end;

  if (not (innerRadius > cSectorEps)) or (not hasArc) then
    LineTo(cx + xire, cy + yire)
  else if limIcr > cSectorEps then
  begin
    crStart := Min(icrStart, limIcr);
    crEnd := Min(icrEnd, limIcr);
    { NEGATIVE radii on the inner ring: the corner bulges the other way, into
      the hole rather than away from it. }
    ct0 := CornerTangents(xire, yire, xre, yre, innerRadius, -crEnd);
    ct1 := CornerTangents(xrs, yrs, xirs, yirs, innerRadius, -crStart);
    LineTo(cx + ct0.CX + ct0.X0, cy + ct0.CY + ct0.Y0);
    if (limIcr < icrMax) and (crStart = crEnd) then
      EmitArc(cx + ct0.CX, cy + ct0.CY, limIcr,
        ArcTan2(ct0.Y0, ct0.X0), ArcTan2(ct1.Y0, ct1.X0), False)
    else
    begin
      if crEnd > 0 then
        EmitArc(cx + ct0.CX, cy + ct0.CY, crEnd,
          ArcTan2(ct0.Y0, ct0.X0), ArcTan2(ct0.Y1, ct0.X1), False);
      EmitArc(cx, cy, innerRadius,
        ArcTan2(ct0.CY + ct0.Y1, ct0.CX + ct0.X1),
        ArcTan2(ct1.CY + ct1.Y1, ct1.CX + ct1.X1), True);
      if crStart > 0 then
        EmitArc(cx + ct1.CX, cy + ct1.CY, crStart,
          ArcTan2(ct1.Y1, ct1.X1), ArcTan2(ct1.Y0, ct1.X0), False);
    end;
  end
  else
  begin
    LineTo(cx + xire, cy + yire);
    EmitArc(cx, cy, innerRadius, endA, startA, True);
  end;

  Emit(pokClose, 0, 0, 0, 0, 0, False);
  SetLength(ops, n);
  Result := ops;
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

function RoundRectContains(const AR: TTyRectF; const ARadii: TTyCornerRadii;
  AX, AY, ASlop: Double): Boolean;
var
  r, cx, cy: Double;
begin
  if not RectContainsClosed(AR, AX, AY, ASlop) then Exit(False);
  { NO CLAMP HERE ANY MORE. The shape constructor clamps, so the record
    already holds the radii the renderer will use; clamping a second time,
    by a different rule than the constructor's proportional one, is how the
    pointer and the ink stopped describing the same corner. }
  if not TyHasCorner(ARadii) then Exit(True);
  { Only the four corner boxes can reject; everything else already passed.
    Each corner asks about ITS OWN radius, which is the whole point of there
    being four of them: a bar rounded only at the top must not reject a click
    at its square bottom corner. }
  r := ARadii[0];
  if (r > 0) and (AX < AR.Left + r) and (AY < AR.Top + r) then
  begin
    cx := AR.Left + r; cy := AR.Top + r;
  end
  else
  begin
    r := ARadii[1];
    if (r > 0) and (AX > AR.Right - r) and (AY < AR.Top + r) then
    begin
      cx := AR.Right - r; cy := AR.Top + r;
    end
    else
    begin
      r := ARadii[2];
      if (r > 0) and (AX > AR.Right - r) and (AY > AR.Bottom - r) then
      begin
        cx := AR.Right - r; cy := AR.Bottom - r;
      end
      else
      begin
        r := ARadii[3];
        if (r > 0) and (AX < AR.Left + r) and (AY > AR.Bottom - r) then
        begin
          cx := AR.Left + r; cy := AR.Bottom - r;
        end
        else
          Exit(True);
      end;
    end;
  end;
  Result := Sqrt(Sqr(AX - cx) + Sqr(AY - cy)) <= r + ASlop;
end;

{ WHAT THIS DOES NOT KNOW ABOUT: rounded corners. A sector with a corner
  radius is drawn slightly inside the annulus this tests, so a pointer just
  outside a cut corner is answered yes while the pixel under it is blank.

  LEFT THAT WAY ON PURPOSE. The error is bounded by the corner radius, which
  is bounded in turn by half the ring's thickness, and it always errs on the
  FORGIVING side -- the direction a hit target should err in. Testing the
  real path would mean carrying it through the hit test as well, which is a
  great deal of trig to make a hover slightly harder to land. }
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

function TyScaleShape(const AShape: TTyChartShape; ARatio: Double): TTyChartShape;
var
  b: TTyRectF;
  cx, cy: Double;
  i: Integer;
begin
  Result := AShape;
  if IsNan(ARatio) or IsInfinite(ARatio) or (ARatio <= 0) or (ARatio = 1) then
    Exit;
  case AShape.Kind of
    cskCircle:
      Result.R1 := AShape.R1 * ARatio;
    cskEllipse:
      begin
        Result.R0 := AShape.R0 * ARatio;
        Result.R1 := AShape.R1 * ARatio;
      end;
    cskRect, cskRoundRect, cskPath:
      begin
        b := AShape.Bounds;
        if not TyRectFIsValid(b) then Exit;
        cx := (b.Left + b.Right) / 2;
        cy := (b.Top + b.Bottom) / 2;
        Result.Bounds := TyRectF(
          cx + (b.Left - cx) * ARatio, cy + (b.Top - cy) * ARatio,
          cx + (b.Right - cx) * ARatio, cy + (b.Bottom - cy) * ARatio);
        { THE CORNERS GROW WITH IT. A roundRect scaled with its radii left
          alone is a different shape, not a larger one. }
        if AShape.Kind = cskRoundRect then
          for i := 0 to 3 do
            Result.Radii[i] := AShape.Radii[i] * ARatio;
      end;
    cskPolyline, cskPolygon:
      begin
        if Length(AShape.Points) = 0 then Exit;
        b := TyShapeBounds(AShape);
        cx := (b.Left + b.Right) / 2;
        cy := (b.Top + b.Bottom) / 2;
        SetLength(Result.Points, Length(AShape.Points));
        for i := 0 to High(AShape.Points) do
          Result.Points[i] := TyPointF(
            cx + (AShape.Points[i].X - cx) * ARatio,
            cy + (AShape.Points[i].Y - cy) * ARatio);
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
      Result := RoundRectContains(AShape.Bounds, AShape.Radii, AX, AY, ASlopPx);
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
