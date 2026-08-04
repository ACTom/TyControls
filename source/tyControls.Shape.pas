unit tyControls.Shape;
{$mode objfpc}{$H+}
{ TTyShape — a general vector-shape primitive for diagrams (a themed re-imagining
  of TShape).

  It draws one antialiased vector shape — rectangle, rounded rectangle, square,
  rounded square, ellipse, circle, the four triangles, diamond, squared diamond,
  5-point star (up or down), a diagonal line, or an app-supplied polygon — filled with
  the resolved TyPanel BACKGROUND and stroked with the TyPanel BORDER. No colour is
  ever hard-coded: the fill/border come from the resolved TyPanel style, so the shape
  follows the active theme. An app recolours a single shape via StyleClass /
  StyleOverride (e.g. StyleOverride := 'background: #E11; border-color: #700;').

  Square/Circle/RoundSquare/SquaredDiamond inset to the largest centred square of the
  control's rect. RoundRect and RoundSquare round by the theme BorderRadius. Line draws
  a top-left -> bottom-right stroke in the border colour only (no fill).

  tskPolygon asks the APP for its vertices through OnShapePoints — the escape hatch for
  every outline the enum does not name, and the only one that also works in the
  designer.

  The polygon geometry for the vertex-based kinds (the triangles, the diamonds, the
  stars) lives in the PURE function TyShapePolygon(kind, rect) so it can be unit-tested
  headless — the control's RenderTo calls it, then fills+strokes the returned path.

  HIT TESTING is shape-precise, not rectangular: a click in the empty corner of a
  circle falls through to whatever sits behind it. The test is ANALYTIC (see
  TyPointInShape) and reads the SAME TTyShapeGeometry record RenderTo builds its path
  from, so "clickable" and "visible" cannot drift apart. }
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, Forms, LCLType, GraphType,
  BGRABitmap, BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base;

type
  { Which vector shape TTyShape draws.

    The last eight are additions and are APPENDED deliberately: an enum value's
    ORDINAL is what a .lfm streams back for a designer that wrote one, so inserting
    tskTriangleLeft next to tskTriangle would have silently re-shaped every existing
    form. The reading order below is therefore historical, not thematic. }
  TTyShapeKind = (tskRectangle, tskRoundRect, tskSquare, tskEllipse, tskCircle,
                  tskTriangle, tskDiamond, tskLine,
                  { square-locked variants of the two kinds that had none }
                  tskRoundSquare, tskSquaredDiamond,
                  { the three non-upward triangles: flow markers, play/back glyphs }
                  tskTriangleLeft, tskTriangleRight, tskTriangleDown,
                  { the 5-point star, point-up and point-down }
                  tskStar, tskStarDown,
                  { vertices supplied by the app through OnShapePoints }
                  tskPolygon);

  { The vertices for tskPolygon, plus the fill rule.

    Deliberately LCL's TShapePointsEvent shape (extctrls.pp:271-272) down to the
    TPointArray: a handler ported from TShape compiles here unchanged. Winding=True
    is the non-zero winding rule, False the even-odd one -- which is what decides
    whether a self-intersecting outline has a hole in it. }
  TTyShapePointsEvent = procedure(Sender: TObject; var Points: TPointArray;
    var Winding: Boolean) of object;

const
  { LCL's stStar is a 5-point star whose inner radius is RadiusBig*57/150
    (shape.inc:187). Reused so a ported stStar looks like the one it replaced. }
  TyShapeStarPoints = 5;
  TyShapeStarInnerRatio = 57 / 150;

type

  { The ONE geometry derivation the painter and the hit-test share.

    Two derivations that can disagree is exactly how a control ends up clickable
    where it is not visible, so RenderTo does not compute a single number of its own:
    it calls TyShapeGeometry, draws the record, and TyPointInShape reads the same
    record back. Everything is in DEVICE px relative to the control's own origin. }
  TTyShapeGeometry = record
    Kind: TTyShapeKind;
    { The box the shape is inscribed in, already inset for the centred stroke — and
      already reduced to the largest centred square for tskSquare / tskCircle. }
    Bounds: TRect;
    { tskRoundRect only: the corner radius, capped at half the shorter side. }
    Radius: Single;
    { Always >= 1: a sub-pixel border still paints one pixel. }
    StrokeWidth: Integer;
    { Whether the border is stroked — which is also what decides the inset. }
    Stroked: Boolean;
    { False for a degenerate box: nothing is drawn, so nothing can be hit. }
    Valid: Boolean;
    { tskPolygon only: the vertices the app handed back through OnShapePoints, in the
      same device-px space as Bounds. Empty (or under 3 long) means the app supplied
      nothing, so there is no ink and nothing to hit. The pure TyShapeGeometry cannot
      know these — TTyShape.ResolveGeometry fires the event and fills them in, which
      is why they live on the record the painter and the hit test both read. }
    Polygon: ArrayOfTPointF;
    { tskPolygon only: True = non-zero winding, False = even-odd. }
    Winding: Boolean;
  end;

  TTyShape = class(TTyGraphicControl)
  private
    FShape: TTyShapeKind;
    FOnShapeClick: TNotifyEvent;
    FOnShapePoints: TTyShapePointsEvent;
    procedure SetShape(AValue: TTyShapeKind);
    procedure SetOnShapePoints(AValue: TTyShapePointsEvent);
    { Runtime: TWinControl.ControlAtPos asks this while routing a mouse message
      (lcl/include/wincontrol.inc:5239) and SKIPS a control that answers 0, so the
      message reaches whatever is behind the shape's empty corners. }
    procedure CMHitTest(var Message: TCMHitTest); message CM_HITTEST;
    { Design time: the Lazarus form designer asks this before adding a control to the
      selection candidates (designer/designer.pp:501). LCL's own TShape answers it the
      same way (lcl/include/shape.inc:313). }
    procedure CMMaskHitTest(var Message: TCMHitTest); message CM_MASKHITTEST;
  protected
    { The geometry ARect/APPI would be painted with: CurrentStyle's border width and
      corner radius, DPI-scaled exactly as TTyPainter.Scale scales them. }
    function ResolveGeometry(const ARect: TRect; APPI: Integer): TTyShapeGeometry;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    { The CLIENT-space point a click is judged against. LCL's TCustomShape.Click reads
      the live cursor (shape.inc:307 ScreenToClient(Mouse.CursorPos)) and so does this,
      but behind a seam: a headless guard cannot move the real mouse, and a test that
      needs to would be moving the USER's pointer. }
    function ShapeClickPoint: TPoint; virtual;
    { LCL order (shape.inc:305-310): the plain OnClick first, then OnShapeClick only if
      the pointer is on the ink. Note that on THIS control CM_HITTEST is already
      shape-precise, so OnClick cannot fire off the ink either -- OnShapeClick is here
      so a form ported from TShape keeps its handler, and so app code can state the
      intent without depending on that. }
    procedure Click; override;
  public
    constructor Create(AOwner: TComponent); override;
    function GetStyleTypeKey: string; override;
    { The geometry the next Paint will draw. Public because an app that wants to
      hit-test the shape itself must be able to reach the numbers the paint used —
      re-deriving them from Width/Height and the theme is how the two drift apart. }
    function ShapeGeometry: TTyShapeGeometry;
    { True when the CLIENT-space pixel APt is on the drawn shape rather than merely
      inside the control's rectangle — LCL's TShape.PtInShape (lcl/include/shape.inc:31),
      minus its per-call monochrome re-render.

      APt is a pixel CELL, not a mathematical point: the test uses the cell's centre.
      Without that half-pixel a 1px-bordered rectangle would lose its outermost pixel
      row and column, because the stroke is centred on a path inset by ceil(width/2). }
    function PtInShape(const APt: TPoint): Boolean;
  published
    property Shape: TTyShapeKind read FShape write SetShape default tskRectangle;
    { Fires on a click that landed on the drawn shape rather than merely inside the
      control's rectangle. LCL: extctrls.pp:343. }
    property OnShapeClick: TNotifyEvent read FOnShapeClick write FOnShapeClick;
    { Supplies the vertices for Shape = tskPolygon. This is the extensibility escape
      hatch for every outline the enum does not name — hexagons, callouts, chevrons —
      and it is what makes those reachable from the DESIGNER rather than only from a
      hand-written TTyGraphicControl descendant. LCL: extctrls.pp:344. }
    property OnShapePoints: TTyShapePointsEvent read FOnShapePoints write SetOnShapePoints;
    property Align;
    property Anchors;
    property StyleClass;
    property StyleOverride;
    property Controller;
  end;

const
  { Kinds whose ink is a closed vertex ring from TyShapePolygon (as opposed to a rect,
    an arc, a line, or the app-supplied tskPolygon). Named once so the painter, the
    hit test and the geometry cannot disagree about the membership. }
  TyShapeVertexKinds = [tskTriangle, tskDiamond, tskSquaredDiamond,
                        tskTriangleLeft, tskTriangleRight, tskTriangleDown,
                        tskStar, tskStarDown];
  { Kinds inscribed in the largest centred SQUARE rather than the full rect. }
  TyShapeSquaredKinds = [tskSquare, tskCircle, tskRoundSquare, tskSquaredDiamond];
  { Kinds that round their corners by the theme radius. }
  TyShapeRoundedKinds = [tskRoundRect, tskRoundSquare];

{ Pure geometry: the polygon vertices (device px) for the vertex-based shape kinds.

  - tskTriangle      -> 3 points: apex top-centre, then the bottom-right and
    bottom-left base corners (clockwise).
  - tskTriangleDown  -> apex bottom-centre; tskTriangleLeft / tskTriangleRight the
    same triangle turned a quarter turn, apex on the left / right edge midpoint.
  - tskDiamond / tskSquaredDiamond -> 4 points: the four edge midpoints (top, right,
    bottom, left), i.e. a rhombus inscribed in ARect.
  - tskStar / tskStarDown -> the 10-vertex 5-point star ring, point-up / point-down.
  - every other kind (rect / roundrect / square / ellipse / circle / line, and the
    app-supplied tskPolygon) is drawn directly by RenderTo and returns [] here.

  All returned points lie within (or on the border of) ARect. No control state /
  painter / handle involved — the value of these kinds IS this vertex map, so it is
  asserted directly by the headless test. }
function TyShapePolygon(AKind: TTyShapeKind; const ARect: TRect): ArrayOfTPointF;

{ Pure geometry: the 2*N vertex ring of an N-point star inscribed in ARect.

  Alternates outer / inner radius about the centre of ARect; the outer radius is half
  the shorter side, so the extreme vertices sit ON the rect edge and none escape it.
  APointDown flips the ring so vertex 0 points at 6 o'clock instead of 12.

  This lives HERE rather than in tyControls.StarShape because two units need it —
  TTyShape's tskStar/tskStarDown and the TTyStarShape control — and a star drawn from
  two different vertex tables is a star whose ink and hit area drift apart.
  TyStarPolygon in tyControls.StarShape is a thin call into this. }
function TyStarRingPolygon(const ARect: TRect; APoints: Integer;
  AInnerRatio: Single; APointDown: Boolean): ArrayOfTPointF;

{ Convert LCL-shaped integer vertices (what OnShapePoints hands back) to the TPointF
  space the geometry and the painter work in. }
function TyPointsToF(const APts: TPointArray): ArrayOfTPointF;

{ Pure geometry: the largest centred square inside ARect (used by tskSquare /
  tskCircle). If ARect is degenerate the result is empty (Right<=Left). }
function TyShapeSquareRect(const ARect: TRect): TRect;

{ Pure geometry: everything AKind needs to be both DRAWN and HIT-TESTED inside ARect.

  ARect is the control's box in DEVICE px (origin-relative). AStrokeWidth and
  ACornerRadius are DEVICE px too — already DPI-scaled by the caller, because the
  scale factor belongs to the painter, not to geometry. ABorderVisible is the theme's
  answer (TyBorderVisible); tskLine overrides it, since its stroke IS the shape rather
  than chrome around one and must draw even under `border-style: none`.

  No control state, no painter, no handle — asserted directly by the headless test. }
function TyShapeGeometry(AKind: TTyShapeKind; const ARect: TRect;
  AStrokeWidth, ACornerRadius: Integer; ABorderVisible: Boolean): TTyShapeGeometry;

{ Pure geometry: is APt on the shape AGeom describes (its fill OR its stroke band)?

  ANALYTIC, not a rendered mask: every kind here has a closed form, and the paint path
  is antialiased — a mask would have to pick an alpha cut-off, and LCL's version
  re-renders the whole shape into a monochrome bitmap on EVERY call
  (lcl/include/shape.inc:31-38 calls UpdateMask unconditionally).

  The ink extends half the stroke width beyond the path, so the test is widened by
  StrokeWidth/2 when the shape is stroked. APt is a mathematical point in the same
  device-px space as AGeom.Bounds; TTyShape.PtInShape is what converts a pixel cell
  into one. }
function TyPointInShape(const AGeom: TTyShapeGeometry; const APt: TPointF): Boolean;

{ The two hit-test protocols answer with OPPOSITE polarity, and getting them backwards
  compiles cleanly and silently inverts the control — so each one is named exactly
  once, here, and pinned by a test.

  CM_HITTEST      lcl/include/wincontrol.inc:5239 — `Perform(...) <> 0` is a HIT, and
                  TControl.CMHitTest answers 1 (control.inc:1171).
  CM_MASKHITTEST  designer/designer.pp:501 — `Perform(...) > 0` makes the designer SKIP
                  the control, and TControl has no handler at all (so an unmasked
                  control answers 0). Zero means "on the shape". }
function TyShapeHitTestAnswer(AOnShape: Boolean): Integer;
function TyShapeMaskHitTestAnswer(AOnShape: Boolean): Integer;

{ Shared polygon primitives, exported so tyControls.StarShape hit-tests with exactly
  the same maths rather than a second copy of it. }

{ Shortest distance from APt to the SEGMENT AA..AB (not the infinite line). }
function TySegmentDistance(const AA, AB, APt: TPointF): Single;
{ Crossing-number containment. Works for any SIMPLE polygon, concave included — which
  is what a star needs, and what a bounding box cannot express. }
function TyPointInPolygon(const APoly: ArrayOfTPointF; const APt: TPointF): Boolean;
{ Shortest distance from APt to the polygon's OUTLINE, ignoring containment. }
function TyPolygonEdgeDistance(const APoly: ArrayOfTPointF; const APt: TPointF): Single;

implementation

function TyStarRingPolygon(const ARect: TRect; APoints: Integer;
  AInnerRatio: Single; APointDown: Boolean): ArrayOfTPointF;
var
  n, i: Integer;
  cx, cy, outer, inner, rr, ang, start: Double;
begin
  Result := nil;
  n := APoints;
  if n < 3 then n := 3;             // fewer than 3 outer points is not a star

  cx := (ARect.Left + ARect.Right) / 2;
  cy := (ARect.Top + ARect.Bottom) / 2;
  outer := Min(ARect.Right - ARect.Left, ARect.Bottom - ARect.Top) / 2;
  if outer < 0 then outer := 0;
  inner := outer * AInnerRatio;

  // -90 deg = 12 o'clock; +90 = 6 o'clock. The whole ring rotates, so a point-down
  // star is the same polygon reflected, not a second vertex table.
  if APointDown then start := 90 else start := -90;

  SetLength(Result, 2 * n);
  for i := 0 to 2 * n - 1 do
  begin
    if (i mod 2) = 0 then rr := outer else rr := inner;
    ang := DegToRad(start + i * (180.0 / n));
    Result[i].x := cx + rr * Cos(ang);
    Result[i].y := cy + rr * Sin(ang);
  end;
end;

function TyPointsToF(const APts: TPointArray): ArrayOfTPointF;
var
  i: Integer;
begin
  SetLength(Result, Length(APts));
  for i := 0 to High(APts) do
    Result[i] := PointF(APts[i].x, APts[i].y);
end;

function TyShapePolygon(AKind: TTyShapeKind; const ARect: TRect): ArrayOfTPointF;
var
  l, t, r, b, cx, cy: Single;
begin
  Result := nil;
  l := ARect.Left;
  t := ARect.Top;
  r := ARect.Right;
  b := ARect.Bottom;
  cx := (l + r) / 2;
  cy := (t + b) / 2;
  case AKind of
    tskTriangle:
      begin
        // apex top-centre, then base corners bottom-right, bottom-left (clockwise)
        SetLength(Result, 3);
        Result[0] := PointF(cx, t);
        Result[1] := PointF(r, b);
        Result[2] := PointF(l, b);
      end;
    tskTriangleDown:
      begin
        // apex bottom-centre, base along the TOP edge (clockwise from the apex)
        SetLength(Result, 3);
        Result[0] := PointF(cx, b);
        Result[1] := PointF(l, t);
        Result[2] := PointF(r, t);
      end;
    tskTriangleLeft:
      begin
        // apex on the left edge midpoint, base along the RIGHT edge
        SetLength(Result, 3);
        Result[0] := PointF(l, cy);
        Result[1] := PointF(r, t);
        Result[2] := PointF(r, b);
      end;
    tskTriangleRight:
      begin
        // apex on the right edge midpoint, base along the LEFT edge
        SetLength(Result, 3);
        Result[0] := PointF(r, cy);
        Result[1] := PointF(l, b);
        Result[2] := PointF(l, t);
      end;
    tskDiamond, tskSquaredDiamond:
      begin
        // the four edge midpoints (top, right, bottom, left) — a rhombus in ARect.
        // tskSquaredDiamond differs only in that ARect has already been squared.
        SetLength(Result, 4);
        Result[0] := PointF(cx, t);
        Result[1] := PointF(r, cy);
        Result[2] := PointF(cx, b);
        Result[3] := PointF(l, cy);
      end;
    tskStar, tskStarDown:
      Result := TyStarRingPolygon(ARect, TyShapeStarPoints, TyShapeStarInnerRatio,
                                  AKind = tskStarDown);
  else
    SetLength(Result, 0);   // non-polygon kinds are drawn directly by RenderTo
  end;
end;

function TyShapeSquareRect(const ARect: TRect): TRect;
var
  w, h, side, ox, oy: Integer;
begin
  w := ARect.Right - ARect.Left;
  h := ARect.Bottom - ARect.Top;
  if (w <= 0) or (h <= 0) then
  begin
    Result := Rect(ARect.Left, ARect.Top, ARect.Left, ARect.Top);   // degenerate
    Exit;
  end;
  if w < h then side := w else side := h;
  ox := (w - side) div 2;
  oy := (h - side) div 2;
  Result := Rect(ARect.Left + ox, ARect.Top + oy,
                 ARect.Left + ox + side, ARect.Top + oy + side);
end;

function TyShapeGeometry(AKind: TTyShapeKind; const ARect: TRect;
  AStrokeWidth, ACornerRadius: Integer; ABorderVisible: Boolean): TTyShapeGeometry;
var
  R: TRect;
  hw, w, h: Integer;
  rr: Single;
begin
  Result := Default(TTyShapeGeometry);   // Valid stays False on every early exit
  Result.Kind := AKind;
  Result.Stroked := ABorderVisible or (AKind = tskLine);
  Result.StrokeWidth := AStrokeWidth;
  if Result.StrokeWidth < 1 then Result.StrokeWidth := 1;

  R := ARect;
  if (R.Right <= R.Left) or (R.Bottom <= R.Top) then Exit;

  // Canvas2D centres a stroke on its path, so a path on the rect edge loses its outer
  // half. Inset by ceil(bw/2) on EVERY side — an asymmetric inset clips the near edges
  // (bw div 2 = 0 for the common 1px border). With no border the shape fills the rect.
  if Result.Stroked then
  begin
    hw := (Result.StrokeWidth + 1) div 2;
    R := Rect(R.Left + hw, R.Top + hw, R.Right - hw, R.Bottom - hw);
    if (R.Right <= R.Left) or (R.Bottom <= R.Top) then Exit;
  end;

  if AKind in TyShapeSquaredKinds then
  begin
    R := TyShapeSquareRect(R);
    if (R.Right <= R.Left) or (R.Bottom <= R.Top) then Exit;
  end;
  Result.Bounds := R;

  if AKind in TyShapeRoundedKinds then
  begin
    // theme BorderRadius (already DPI-scaled), capped at half the shorter side
    w := R.Right - R.Left;
    h := R.Bottom - R.Top;
    rr := ACornerRadius;
    if rr > w / 2 then rr := w / 2;
    if rr > h / 2 then rr := h / 2;
    if rr < 0 then rr := 0;
    Result.Radius := rr;
  end;

  Result.Valid := True;
end;

{ Tolerances are compared inclusively: a hit test that rejects its own boundary loses
  the outermost pixel of every shape. }
const
  HitEps = 0.001;

{ Shortest distance from AP to the SEGMENT AA..AB (not the infinite line): the
  parameter is clamped to the segment, so the stroke's round cap is modelled too. }
function TySegmentDistance(const AA, AB, APt: TPointF): Single;
var
  vx, vy, wx, wy, den, t: Single;
  AP: TPointF;
begin
  AP := APt;
  vx := AB.x - AA.x;
  vy := AB.y - AA.y;
  wx := AP.x - AA.x;
  wy := AP.y - AA.y;
  den := vx * vx + vy * vy;
  if den <= 0 then
    t := 0                                   // degenerate segment: distance to the point
  else
  begin
    t := (vx * wx + vy * wy) / den;
    if t < 0 then t := 0 else if t > 1 then t := 1;
  end;
  Result := Sqrt(Sqr(AP.x - (AA.x + t * vx)) + Sqr(AP.y - (AA.y + t * vy)));
end;

{ Crossing-number containment. Half-open on Y (`>` on one end, not `>=`) so a vertex
  exactly at APt.y is counted once rather than twice — the classic double-count that
  makes a horizontal ray through a vertex report "outside". }
function TyPointInPolygon(const APoly: ArrayOfTPointF; const APt: TPointF): Boolean;
var
  i, j: Integer;
  inside: Boolean;
begin
  Result := False;
  if Length(APoly) < 3 then Exit;
  inside := False;
  j := High(APoly);
  for i := 0 to High(APoly) do
  begin
    if ((APoly[i].y > APt.y) <> (APoly[j].y > APt.y)) and
       (APt.x < (APoly[j].x - APoly[i].x) * (APt.y - APoly[i].y) /
                (APoly[j].y - APoly[i].y) + APoly[i].x) then
      inside := not inside;
    j := i;
  end;
  Result := inside;
end;

{ NON-ZERO winding containment, the other of the two fill rules. It differs from the
  crossing-number test above only for a SELF-INTERSECTING outline: even-odd punches a
  hole where the outline crosses itself, winding fills it. tskPolygon lets the app hand
  back any outline at all, so both rules have to exist or a pentagram's centre would be
  clickable exactly when it is not painted. }
function TyPointInPolygonWinding(const APoly: ArrayOfTPointF; const APt: TPointF): Boolean;
var
  i, j, wind: Integer;
  side: Single;
begin
  Result := False;
  if Length(APoly) < 3 then Exit;
  wind := 0;
  j := High(APoly);
  for i := 0 to High(APoly) do
  begin
    // Cross product sign: which side of the edge j->i the point falls on.
    side := (APoly[i].x - APoly[j].x) * (APt.y - APoly[j].y)
          - (APt.x - APoly[j].x) * (APoly[i].y - APoly[j].y);
    if APoly[j].y <= APt.y then
    begin
      if (APoly[i].y > APt.y) and (side > 0) then Inc(wind);   // upward crossing
    end
    else
      if (APoly[i].y <= APt.y) and (side < 0) then Dec(wind);  // downward crossing
    j := i;
  end;
  Result := wind <> 0;
end;

{ Shortest distance from APt to the polygon's OUTLINE (edges), ignoring containment. }
function TyPolygonEdgeDistance(const APoly: ArrayOfTPointF; const APt: TPointF): Single;
var
  i, j: Integer;
  d: Single;
begin
  Result := MaxSingle;
  if Length(APoly) < 2 then Exit;
  j := High(APoly);
  for i := 0 to High(APoly) do
  begin
    d := TySegmentDistance(APoly[j], APoly[i], APt);
    if d < Result then Result := d;
    j := i;
  end;
end;

function TyPointInShape(const AGeom: TTyShapeGeometry; const APt: TPointF): Boolean;
var
  B: TRect;
  tol, cx, cy, rx, ry, nx, ny: Single;
  bl, bt, br, bb, rr, dx, dy: Single;   { the stroke-widened box, as floats }
  poly: ArrayOfTPointF;
begin
  Result := False;
  if not AGeom.Valid then Exit;   // degenerate: nothing drawn, nothing hit
  B := AGeom.Bounds;
  if AGeom.Stroked then tol := AGeom.StrokeWidth / 2 else tol := 0;

  case AGeom.Kind of
    tskEllipse, tskCircle:
      begin
        // tskCircle's Bounds is already the centred square, so rx = ry falls out.
        cx := (B.Left + B.Right) / 2;
        cy := (B.Top + B.Bottom) / 2;
        rx := (B.Right - B.Left) / 2 + tol;
        ry := (B.Bottom - B.Top) / 2 + tol;
        if (rx <= 0) or (ry <= 0) then Exit;
        nx := (APt.x - cx) / rx;
        ny := (APt.y - cy) / ry;
        Result := nx * nx + ny * ny <= 1 + HitEps;
      end;
    tskRoundRect, tskRoundSquare:
      begin
        // The stroke band widens the box AND its corner arcs by the same tol.
        bl := B.Left - tol;  bt := B.Top - tol;
        br := B.Right + tol; bb := B.Bottom + tol;
        if (APt.x < bl - HitEps) or (APt.x > br + HitEps) or
           (APt.y < bt - HitEps) or (APt.y > bb + HitEps) then Exit;
        rr := AGeom.Radius + tol;
        if rr <= 0 then Exit(True);            // square corners: the box test was enough
        if rr > (br - bl) / 2 then rr := (br - bl) / 2;
        if rr > (bb - bt) / 2 then rr := (bb - bt) / 2;
        dx := 0;
        dy := 0;
        if APt.x < bl + rr then dx := (bl + rr) - APt.x
        else if APt.x > br - rr then dx := APt.x - (br - rr);
        if APt.y < bt + rr then dy := (bt + rr) - APt.y
        else if APt.y > bb - rr then dy := APt.y - (bb - rr);
        Result := dx * dx + dy * dy <= rr * rr + HitEps;
      end;
    tskPolygon:
      begin
        // The app's own vertices, carried on the record so the paint path and this
        // read the identical list — including the fill rule, which decides whether a
        // self-intersecting outline has a hole a click should fall through.
        if TyPolygonEdgeDistance(AGeom.Polygon, APt) <= tol + HitEps then
          Exit(True);
        if AGeom.Winding then
          Result := TyPointInPolygonWinding(AGeom.Polygon, APt)
        else
          Result := TyPointInPolygon(AGeom.Polygon, APt);
      end;
    tskLine:
      // A capsule around the drawn segment: the line is a stroke, so its hit band is
      // its own width. A hairline line is a hairline target — widen it with the theme's
      // border-width, which is the same number that makes it visible.
      Result := TySegmentDistance(PointF(B.Left, B.Top), PointF(B.Right, B.Bottom), APt)
                <= tol + HitEps;
  else
    if AGeom.Kind in TyShapeVertexKinds then
    begin
      // The SAME vertices RenderTo builds its path from — for a star that is the whole
      // point: a bounding box would claim the five concave notches nothing is drawn in.
      poly := TyShapePolygon(AGeom.Kind, B);
      Exit(TyPointInPolygon(poly, APt)
        or (TyPolygonEdgeDistance(poly, APt) <= tol + HitEps));
    end;
    // tskRectangle / tskSquare — the box itself, widened by the stroke band.
    Result := (APt.x >= B.Left - tol - HitEps) and (APt.x <= B.Right + tol + HitEps)
          and (APt.y >= B.Top - tol - HitEps) and (APt.y <= B.Bottom + tol + HitEps);
  end;
end;

function TyShapeHitTestAnswer(AOnShape: Boolean): Integer;
begin
  if AOnShape then Result := 1 else Result := 0;
end;

function TyShapeMaskHitTestAnswer(AOnShape: Boolean): Integer;
begin
  if AOnShape then Result := 0 else Result := 1;   // deliberately the inverse
end;

constructor TTyShape.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShape := tskRectangle;
  Width := 120;
  Height := 80;
end;

function TTyShape.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyPanel': a filled vector path is not a panel surface; a skin that restyles panels must not repaint every diagram shape.
    Added to 'TyPanel's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TyShape';
end;

procedure TTyShape.SetShape(AValue: TTyShapeKind);
begin
  if FShape = AValue then Exit;
  FShape := AValue;
  Invalidate;
end;

procedure TTyShape.SetOnShapePoints(AValue: TTyShapePointsEvent);
begin
  if FOnShapePoints = AValue then Exit;
  FOnShapePoints := AValue;
  // A tskPolygon's whole outline comes from the handler, so swapping the handler
  // changes what is drawn — nothing else would have said so.
  if FShape = tskPolygon then Invalidate;
end;

function TTyShape.ResolveGeometry(const ARect: TRect; APPI: Integer): TTyShapeGeometry;
var
  S: TTyStyleSet;
  ppi: Integer;
  pts: TPointArray;
  wind: Boolean;
begin
  S := CurrentStyle;
  // TTyPainter.BeginPaint's own clamp, then its own Scale (MulDiv by PPI/96): the
  // painter and this must scale identically or the ink and the hit band diverge.
  if APPI <= 0 then ppi := 96 else ppi := APPI;
  Result := TyShapeGeometry(FShape,
    Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top),
    MulDiv(S.BorderWidth, ppi, 96),
    MulDiv(TyEffectiveCorners(S).TL, ppi, 96),
    TyBorderVisible(S));

  if (FShape = tskPolygon) and Result.Valid and Assigned(FOnShapePoints) then
  begin
    { The vertices are asked for HERE, once, and travel on the record — so the paint
      path and the hit test cannot get different answers out of a handler that is free
      to return whatever it likes. LCL re-renders its whole mask on every PtInShape
      call for the same reason; this is that guarantee without the bitmap. }
    pts := nil;
    wind := True;                     // LCL's own default (shape.inc:206)
    FOnShapePoints(Self, pts, wind);
    Result.Polygon := TyPointsToF(pts);
    Result.Winding := wind;
  end;
end;

function TTyShape.ShapeClickPoint: TPoint;
begin
  Result := ScreenToClient(Mouse.CursorPos);
end;

procedure TTyShape.Click;
begin
  inherited Click;
  if Assigned(FOnShapeClick) and PtInShape(ShapeClickPoint) then
    FOnShapeClick(Self);
end;

function TTyShape.ShapeGeometry: TTyShapeGeometry;
begin
  Result := ResolveGeometry(ClientRect, Font.PixelsPerInch);
end;

function TTyShape.PtInShape(const APt: TPoint): Boolean;
begin
  // +0.5 = the pixel CELL's centre. See the declaration for why the half matters.
  Result := TyPointInShape(ShapeGeometry, PointF(APt.X + 0.5, APt.Y + 0.5));
end;

procedure TTyShape.CMHitTest(var Message: TCMHitTest);
begin
  // The coordinates arrive control-relative (wincontrol.inc:5239 passes
  // Point(P.X - Left, P.Y - Top)), which for a graphic control is already client space.
  Message.Result := TyShapeHitTestAnswer(PtInShape(Point(Message.XPos, Message.YPos)));
end;

procedure TTyShape.CMMaskHitTest(var Message: TCMHitTest);
var
  Frm: TCustomForm;
  P: TPoint;
begin
  // NOTE THE POLARITY: 0 = "the point is on me". That is the inverse of CM_HITTEST
  // above, and it is also the answer TControl gives by having no handler — so it is
  // the right fallback when the point cannot be translated.
  Message.Result := TyShapeMaskHitTestAnswer(True);
  // The designer sends DESIGNER-FORM-relative coordinates, not client ones. The
  // TControl overload of GetDesignerForm walks Parent (the TPersistent one walks Owner
  // and would answer for a different chain), so the cast is not decoration.
  Frm := GetDesignerForm(TControl(Self));
  if Frm = nil then Exit;
  P := ScreenToClient(Frm.ClientToScreen(Point(Message.XPos, Message.YPos)));
  Message.Result := TyShapeMaskHitTestAnswer(PtInShape(P));
end;

procedure TTyShape.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  ctx: TBGRACanvas2D;
  G: TTyShapeGeometry;
  R: TRect;
  poly: ArrayOfTPointF;
  bw: Integer;
  hasFill: Boolean;
  fillPx, strokePx: TBGRAPixel;

  { Trace APoly as a closed path. }
  procedure TracePoly(const APoly: ArrayOfTPointF);
  var
    i: Integer;   { must be local: FPC forbids an outer var as a nested for-counter }
  begin
    if Length(APoly) < 2 then Exit;
    ctx.moveTo(APoly[0].x, APoly[0].y);
    for i := 1 to High(APoly) do
      ctx.lineTo(APoly[i].x, APoly[i].y);
    ctx.closePath;
  end;

  { Build the current path for the shape kind (excluding line, which is stroked
    directly). Fills use the closed path; the same path is stroked for the border. }
  procedure BuildPath;
  begin
    ctx.beginPath;
    case G.Kind of
      tskEllipse:
        ctx.ellipse((R.Left + R.Right) / 2, (R.Top + R.Bottom) / 2,
                    (R.Right - R.Left) / 2, (R.Bottom - R.Top) / 2);
      tskCircle:
        // G.Bounds is already the largest centred square, so this is a true circle.
        ctx.arc((R.Left + R.Right) / 2, (R.Top + R.Bottom) / 2,
                (R.Right - R.Left) / 2, 0, 2 * Pi, False);
      tskSquare:
        ctx.rect(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top);
      tskRoundRect, tskRoundSquare:
        ctx.roundRect(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top, G.Radius);
      tskPolygon:
        // The app's vertices, taken off the record ResolveGeometry filled — NOT a
        // second call to the handler, which is free to answer differently each time.
        TracePoly(G.Polygon);
    else
      if G.Kind in TyShapeVertexKinds then
      begin
        poly := TyShapePolygon(G.Kind, R);
        TracePoly(poly);
      end
      else
        // tskRectangle (and any fallthrough) — the full rect
        ctx.rect(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top);
    end;
  end;

begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    // ONE derivation, shared with PtInShape: RenderTo computes no geometry of its own.
    G := ResolveGeometry(ARect, APPI);
    if not G.Valid then
    begin
      P.EndPaint;
      Exit;   // degenerate
    end;
    R := G.Bounds;

    ctx := P.Bitmap.Canvas2D;
    bw := G.StrokeWidth;
    strokePx := TyColorToBGRA(S.BorderColor);

    if G.Kind = tskLine then
    begin
      // A diagonal top-left -> bottom-right stroke in the border colour (no fill).
      ctx.lineCap := 'round';
      ctx.lineWidth := bw;
      ctx.strokeStyle(strokePx);
      ctx.beginPath;
      ctx.moveTo(R.Left, R.Top);
      ctx.lineTo(R.Right, R.Bottom);
      ctx.stroke;
      P.EndPaint;
      Exit;
    end;

    if (G.Kind = tskPolygon) and (Length(G.Polygon) < 3) then
    begin
      { No handler, or fewer than three vertices: there is no outline to draw. At DESIGN
        time outline the control anyway, or a tskPolygon whose handler is not written yet
        is an invisible, unclickable rectangle on the form. At run time it must stay
        invisible — a placeholder frame in a shipped app is a defect. }
      if csDesigning in ComponentState then
        P.StrokeBorder(Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top),
          0, 1, TyRGBA(128, 128, 128, 160));
      P.EndPaint;
      Exit;
    end;

    // Fill only when the resolved background is a solid, non-fully-transparent colour.
    hasFill := (S.Background.Kind = tfkSolid) and (TyAlphaOf(S.Background.Color) > 0);
    fillPx := TyColorToBGRA(S.Background.Color);

    // The app's fill rule, for tskPolygon only: an outline that crosses itself is a
    // different SHAPE under the two rules, so the ink has to honour what the hit test
    // was told. fmWinding is Canvas2D's default and LCL's.
    if G.Kind = tskPolygon then
    begin
      if G.Winding then ctx.fillMode := fmWinding else ctx.fillMode := fmAlternate;
    end;

    BuildPath;
    if hasFill then
    begin
      ctx.fillStyle(fillPx);
      ctx.fill;
    end;
    if G.Stroked then
    begin
      ctx.lineJoin := 'miter';
      ctx.lineWidth := bw;
      ctx.strokeStyle(strokePx);
      ctx.stroke;
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyShape.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
