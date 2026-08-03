unit tyControls.Shape;
{$mode objfpc}{$H+}
{ TTyShape — a general vector-shape primitive for diagrams (a themed re-imagining
  of TShape).

  It draws one antialiased vector shape — rectangle, rounded rectangle, square,
  ellipse, circle, triangle, diamond, or a diagonal line — filled with the resolved
  TyPanel BACKGROUND and stroked with the TyPanel BORDER. No colour is ever
  hard-coded: the fill/border come from the resolved TyPanel style, so the shape
  follows the active theme. An app recolours a single shape via StyleClass /
  StyleOverride (e.g. StyleOverride := 'background: #E11; border-color: #700;').

  Square/Circle inset to the largest centred square of the control's rect. RoundRect
  rounds by the theme BorderRadius. Line draws a top-left -> bottom-right stroke in
  the border colour only (no fill).

  The polygon geometry for the vertex-based kinds (triangle, diamond) lives in the
  PURE function TyShapePolygon(kind, rect) so it can be unit-tested headless — the
  control's RenderTo calls it, then fills+strokes the returned path.

  HIT TESTING is shape-precise, not rectangular: a click in the empty corner of a
  circle falls through to whatever sits behind it. The test is ANALYTIC (see
  TyPointInShape) and reads the SAME TTyShapeGeometry record RenderTo builds its path
  from, so "clickable" and "visible" cannot drift apart. }
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, Forms, LCLType,
  BGRABitmap, BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base;

type
  { Which vector shape TTyShape draws. }
  TTyShapeKind = (tskRectangle, tskRoundRect, tskSquare, tskEllipse, tskCircle,
                  tskTriangle, tskDiamond, tskLine);

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
  end;

  TTyShape = class(TTyGraphicControl)
  private
    FShape: TTyShapeKind;
    procedure SetShape(AValue: TTyShapeKind);
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
    property Align;
    property Anchors;
    property StyleClass;
    property StyleOverride;
    property Controller;
  end;

{ Pure geometry: the polygon vertices (device px) for the vertex-based shape kinds.

  - tskTriangle -> 3 points: apex at the top-centre, then the bottom-right and
    bottom-left base corners (clockwise).
  - tskDiamond  -> 4 points: the four edge midpoints (top, right, bottom, left),
    i.e. a rhombus inscribed in ARect.
  - every other kind (rect / roundrect / square / ellipse / circle / line) is drawn
    directly by RenderTo and returns [] (an empty array) here.

  All returned points lie within (or on the border of) ARect. No control state /
  painter / handle involved — the value of these kinds IS this vertex map, so it is
  asserted directly by the headless test. }
function TyShapePolygon(AKind: TTyShapeKind; const ARect: TRect): ArrayOfTPointF;

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

implementation

function TyShapePolygon(AKind: TTyShapeKind; const ARect: TRect): ArrayOfTPointF;
var
  l, t, r, b, cx: Single;
begin
  Result := nil;
  l := ARect.Left;
  t := ARect.Top;
  r := ARect.Right;
  b := ARect.Bottom;
  cx := (l + r) / 2;
  case AKind of
    tskTriangle:
      begin
        // apex top-centre, then base corners bottom-right, bottom-left (clockwise)
        SetLength(Result, 3);
        Result[0] := PointF(cx, t);
        Result[1] := PointF(r, b);
        Result[2] := PointF(l, b);
      end;
    tskDiamond:
      begin
        // the four edge midpoints (top, right, bottom, left) — a rhombus in ARect
        SetLength(Result, 4);
        Result[0] := PointF(cx, t);
        Result[1] := PointF(r, (t + b) / 2);
        Result[2] := PointF(cx, b);
        Result[3] := PointF(l, (t + b) / 2);
      end;
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

  if AKind in [tskSquare, tskCircle] then
  begin
    R := TyShapeSquareRect(R);
    if (R.Right <= R.Left) or (R.Bottom <= R.Top) then Exit;
  end;
  Result.Bounds := R;

  if AKind = tskRoundRect then
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
function SegmentDistance(const AA, AB, AP: TPointF): Single;
var
  vx, vy, wx, wy, den, t: Single;
begin
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
function PointInPolygon(const APoly: ArrayOfTPointF; const APt: TPointF): Boolean;
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

{ Shortest distance from APt to the polygon's OUTLINE (edges), ignoring containment. }
function PolygonEdgeDistance(const APoly: ArrayOfTPointF; const APt: TPointF): Single;
var
  i, j: Integer;
  d: Single;
begin
  Result := MaxSingle;
  if Length(APoly) < 2 then Exit;
  j := High(APoly);
  for i := 0 to High(APoly) do
  begin
    d := SegmentDistance(APoly[j], APoly[i], APt);
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
    tskRoundRect:
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
    tskTriangle, tskDiamond:
      begin
        // The SAME vertices RenderTo builds its path from.
        poly := TyShapePolygon(AGeom.Kind, B);
        Result := PointInPolygon(poly, APt)
               or (PolygonEdgeDistance(poly, APt) <= tol + HitEps);
      end;
    tskLine:
      // A capsule around the drawn segment: the line is a stroke, so its hit band is
      // its own width. A hairline line is a hairline target — widen it with the theme's
      // border-width, which is the same number that makes it visible.
      Result := SegmentDistance(PointF(B.Left, B.Top), PointF(B.Right, B.Bottom), APt)
                <= tol + HitEps;
  else
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

function TTyShape.ResolveGeometry(const ARect: TRect; APPI: Integer): TTyShapeGeometry;
var
  S: TTyStyleSet;
  ppi: Integer;
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

  { Build the current path for the shape kind (excluding line, which is stroked
    directly). Fills use the closed path; the same path is stroked for the border. }
  procedure BuildPath;
  var
    i: Integer;   { must be local: FPC forbids an outer var as a nested for-counter }
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
      tskRoundRect:
        ctx.roundRect(R.Left, R.Top, R.Right - R.Left, R.Bottom - R.Top, G.Radius);
      tskTriangle, tskDiamond:
        begin
          poly := TyShapePolygon(G.Kind, R);
          if Length(poly) > 0 then
          begin
            ctx.moveTo(poly[0].x, poly[0].y);
            for i := 1 to High(poly) do
              ctx.lineTo(poly[i].x, poly[i].y);
            ctx.closePath;
          end;
        end;
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

    // Fill only when the resolved background is a solid, non-fully-transparent colour.
    hasFill := (S.Background.Kind = tfkSolid) and (TyAlphaOf(S.Background.Color) > 0);
    fillPx := TyColorToBGRA(S.Background.Color);

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
