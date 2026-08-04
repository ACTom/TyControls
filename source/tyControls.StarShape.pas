unit tyControls.StarShape;
{$mode objfpc}{$H+}
{ TTyStarShape — a decorative N-point vector star.

  A leaf graphic control (TTyGraphicControl, no focus / no children) that draws a
  filled + stroked star of N outer points. The star is centred; the outer radius
  is half the min(width,height) minus a small margin; the inner radius is a
  fraction (InnerRatio) of the outer. The first outer vertex points straight UP,
  or straight DOWN when PointDown is set.

  Colours are theme-driven — the control reuses the resolved TyPanel style: the
  FILL is that style's background (skipped if fully transparent), the BORDER is
  its border-color at max(1, scaled border-width). No colour is ever hard-coded;
  an app recolours a star via StyleClass / StyleOverride (e.g.
  StyleOverride := 'background: #E11; border-color: #700;').

  The polygon geometry lives in the pure function TyStarPolygon so it can be
  unit-tested headless (no window handle, no painter). RenderTo calls that fn to
  get the device-px vertices, then fills + strokes them with the Canvas2D ctx.

  HIT TESTING is shape-precise, not rectangular. A star is the extreme case: five
  points and five deep concave notches, so a bounding-box answer claims a great deal
  of canvas the control never draws on — and a control BEHIND those notches could not
  be reached at all. The test is analytic (TyPointInStar) and reads the SAME
  TTyStarGeometry record RenderTo builds its path from, so "clickable" and "visible"
  cannot drift apart. }
interface
uses
  Classes, SysUtils, Types,
  Controls, Graphics, Forms, LCLType,
  BGRABitmap, BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Shape;

const
  { A star needs at least 3 outer points; fewer collapses to a triangle. }
  TyStarMinPoints = 3;
  { InnerRatio clamp range — the inner radius as a fraction of the outer. }
  TyStarMinInnerRatio = 0.05;
  TyStarMaxInnerRatio = 0.95;
  { Logical-px inset from the control edge to the star's outer radius. }
  TyStarMargin = 2;

type
  { The ONE geometry derivation the painter and the hit-test share — the same contract
    as TTyShapeGeometry, and for the same reason: two derivations that can disagree is
    exactly how a control ends up clickable where it is not visible. Everything is in
    DEVICE px relative to the control's own origin. }
  TTyStarGeometry = record
    { The box the star ring is inscribed in: already inset by the scaled margin and,
      when stroked, by half the stroke width. }
    Bounds: TRect;
    { Already floored to TyStarMinPoints. }
    Points: Integer;
    { Already clamped to [TyStarMinInnerRatio, TyStarMaxInnerRatio]. }
    InnerRatio: Single;
    PointDown: Boolean;
    { Always >= 1: a sub-pixel border still paints one pixel. }
    StrokeWidth: Integer;
    Stroked: Boolean;
    { False for a degenerate box: nothing is drawn, so nothing can be hit. }
    Valid: Boolean;
  end;

  TTyStarShape = class(TTyGraphicControl)
  private
    FPoints: Integer;
    FInnerRatio: Single;
    FPointDown: Boolean;
    FOnShapeClick: TNotifyEvent;
    procedure SetPoints(AValue: Integer);
    procedure SetInnerRatio(AValue: Single);
    procedure SetPointDown(AValue: Boolean);
    { Runtime: TWinControl.ControlAtPos asks this while routing a mouse message
      (lcl/include/wincontrol.inc:5239) and SKIPS a control that answers 0, so the
      message reaches whatever is behind the star's notches and corners. }
    procedure CMHitTest(var Message: TCMHitTest); message CM_HITTEST;
    { Design time: the Lazarus form designer asks this before adding a control to the
      selection candidates (designer/designer.pp:501). NOTE THE OPPOSITE POLARITY —
      see TyShapeMaskHitTestAnswer. }
    procedure CMMaskHitTest(var Message: TCMHitTest); message CM_MASKHITTEST;
  protected
    { The geometry ARect/APPI would be painted with: the scaled margin, and the
      CurrentStyle border width, scaled exactly as TTyPainter.Scale scales it. }
    function ResolveGeometry(const ARect: TRect; APPI: Integer): TTyStarGeometry;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    { See TTyShape.ShapeClickPoint: LCL reads the live cursor, and a headless guard
      must not have to move the user's pointer to exercise this. }
    function ShapeClickPoint: TPoint; virtual;
    procedure Click; override;
  public
    constructor Create(AOwner: TComponent); override;
    function GetStyleTypeKey: string; override;
    { The geometry the next Paint will draw. Public because an app that wants to
      hit-test the star itself must be able to reach the numbers the paint used —
      re-deriving them from Width/Height and the theme is how the two drift apart. }
    function StarGeometry: TTyStarGeometry;
    { True when the CLIENT-space pixel APt is on the drawn star rather than merely
      inside the control's rectangle.

      APt is a pixel CELL, not a mathematical point: the test uses the cell's centre.
      Without that half-pixel the outermost inked row and column would be lost,
      because the stroke is centred on a path inset by ceil(width/2). }
    function PtInShape(const APt: TPoint): Boolean;
  published
    property Points: Integer read FPoints write SetPoints default 5;
    property InnerRatio: Single read FInnerRatio write SetInnerRatio;
    { Turns the ring a half-step so vertex 0 points at 6 o'clock. This is LCL's
      stStarDown, which was unreachable here at any property setting: TyStarPolygon
      always started at 12 o'clock and no rotation existed. }
    property PointDown: Boolean read FPointDown write SetPointDown default False;
    { Fires on a click that landed on the drawn star rather than merely inside the
      control's rectangle — TShape.OnShapeClick's contract, on the control this
      library uses in place of Shape = stStar. }
    property OnShapeClick: TNotifyEvent read FOnShapeClick write FOnShapeClick;
    property Align;
    property Anchors;
    property StyleClass;
    property StyleOverride;
    property Controller;
  end;

{ Pure geometry: the vertices of an N-point star inscribed in ARect.

  Returns 2*max(3,APoints) points in device px, alternating outer / inner radius
  around the centre of ARect. The centre is the rect midpoint; the outer radius
  is half the smaller side (so every vertex sits within — and the extreme ones
  at — ARect). The FIRST vertex (index 0) is an OUTER point pointing straight UP
  (12 o'clock), or straight DOWN when APointDown. APoints is floored to 3;
  AInnerRatio is clamped to [TyStarMinInnerRatio, TyStarMaxInnerRatio]. No control /
  painter state — the correctness of the control IS this vertex ring, so it is
  unit-tested directly.

  The ring itself is TyStarRingPolygon in tyControls.Shape: TTyShape's tskStar /
  tskStarDown need the identical vertices, and a star drawn from two vertex tables is
  a star whose two drawings drift. What stays here is the CLAMPING — this control's
  published Points / InnerRatio range. }
function TyStarPolygon(const ARect: TRect; APoints: Integer;
  AInnerRatio: Single): ArrayOfTPointF; overload;
function TyStarPolygon(const ARect: TRect; APoints: Integer;
  AInnerRatio: Single; APointDown: Boolean): ArrayOfTPointF; overload;

{ Pure geometry: everything a star needs to be both DRAWN and HIT-TESTED inside ARect.

  ARect is the control's box in DEVICE px (origin-relative). AStrokeWidth and AMargin
  are DEVICE px too — already DPI-scaled by the caller, because the scale factor
  belongs to the painter, not to geometry. ABorderVisible is the theme's answer
  (TyBorderVisible). No control state, no painter, no handle. }
function TyStarGeometry(const ARect: TRect; APoints: Integer; AInnerRatio: Single;
  APointDown: Boolean; AStrokeWidth, AMargin: Integer;
  ABorderVisible: Boolean): TTyStarGeometry;

{ Pure geometry: is APt on the star AGeom describes (its fill OR its stroke band)?

  ANALYTIC, not a rendered mask, for the same reasons as TyPointInShape. The ink
  extends half the stroke width beyond the path, so the test is widened by
  StrokeWidth/2 when the star is stroked. }
function TyPointInStar(const AGeom: TTyStarGeometry; const APt: TPointF): Boolean;

implementation

uses
  Math;

{ Tolerances are compared inclusively: a hit test that rejects its own boundary loses
  the outermost pixel of the shape. }
const
  HitEps = 0.001;

function TyStarPolygon(const ARect: TRect; APoints: Integer;
  AInnerRatio: Single): ArrayOfTPointF;
begin
  Result := TyStarPolygon(ARect, APoints, AInnerRatio, False);
end;

function TyStarPolygon(const ARect: TRect; APoints: Integer;
  AInnerRatio: Single; APointDown: Boolean): ArrayOfTPointF;
var
  n: Integer;
  ratio: Single;
begin
  n := APoints;
  if n < TyStarMinPoints then n := TyStarMinPoints;   // point-count floor

  ratio := AInnerRatio;                                // clamp inner fraction
  if ratio < TyStarMinInnerRatio then ratio := TyStarMinInnerRatio
  else if ratio > TyStarMaxInnerRatio then ratio := TyStarMaxInnerRatio;

  Result := TyStarRingPolygon(ARect, n, ratio, APointDown);
end;

function TyStarGeometry(const ARect: TRect; APoints: Integer; AInnerRatio: Single;
  APointDown: Boolean; AStrokeWidth, AMargin: Integer;
  ABorderVisible: Boolean): TTyStarGeometry;
var
  w, h, margin: Integer;
  R: TRect;
begin
  Result := Default(TTyStarGeometry);   // Valid stays False on every early exit
  Result.Points := APoints;
  if Result.Points < TyStarMinPoints then Result.Points := TyStarMinPoints;
  Result.InnerRatio := AInnerRatio;
  if Result.InnerRatio < TyStarMinInnerRatio then
    Result.InnerRatio := TyStarMinInnerRatio
  else if Result.InnerRatio > TyStarMaxInnerRatio then
    Result.InnerRatio := TyStarMaxInnerRatio;
  Result.PointDown := APointDown;
  Result.Stroked := ABorderVisible;
  Result.StrokeWidth := AStrokeWidth;
  if Result.StrokeWidth < 1 then Result.StrokeWidth := 1;

  w := ARect.Right - ARect.Left;
  h := ARect.Bottom - ARect.Top;
  if (w <= 0) or (h <= 0) then Exit;

  // Inset by the scaled margin PLUS half the stroke: the ring's outer vertices sit
  // exactly on Bounds' edge and Canvas2D centres a stroke on its path, so a fixed
  // margin alone would lose half a thick border off the bitmap.
  margin := AMargin;
  if margin < 0 then margin := 0;
  if Result.Stroked then Inc(margin, (Result.StrokeWidth + 1) div 2);
  R := Rect(ARect.Left + margin, ARect.Top + margin,
            ARect.Right - margin, ARect.Bottom - margin);
  // A control too small for the margin still draws a star rather than nothing: fall
  // back to the whole rect, exactly as the paint path always has.
  if (R.Right <= R.Left) or (R.Bottom <= R.Top) then
    R := ARect;
  Result.Bounds := R;
  Result.Valid := True;
end;

function TyPointInStar(const AGeom: TTyStarGeometry; const APt: TPointF): Boolean;
var
  poly: ArrayOfTPointF;
  tol: Single;
begin
  Result := False;
  if not AGeom.Valid then Exit;   // degenerate: nothing drawn, nothing hit
  if AGeom.Stroked then tol := AGeom.StrokeWidth / 2 else tol := 0;
  // The SAME vertices RenderTo builds its path from. A crossing-number containment
  // test handles the concave ring directly; the edge distance adds the stroke band,
  // which is the only ink outside the ring.
  poly := TyStarPolygon(AGeom.Bounds, AGeom.Points, AGeom.InnerRatio, AGeom.PointDown);
  Result := TyPointInPolygon(poly, APt)
         or (TyPolygonEdgeDistance(poly, APt) <= tol + HitEps);
end;

constructor TTyStarShape.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPoints := 5;
  FInnerRatio := 0.42;
  FPointDown := False;
  Width := 96;
  Height := 96;
end;

function TTyStarShape.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyPanel': a decorative star is not a panel surface.
    Added to 'TyPanel's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TyStarShape';
end;

procedure TTyStarShape.SetPoints(AValue: Integer);
begin
  if AValue < TyStarMinPoints then AValue := TyStarMinPoints;
  if FPoints = AValue then Exit;
  FPoints := AValue;
  Invalidate;
end;

procedure TTyStarShape.SetInnerRatio(AValue: Single);
begin
  if AValue < TyStarMinInnerRatio then AValue := TyStarMinInnerRatio
  else if AValue > TyStarMaxInnerRatio then AValue := TyStarMaxInnerRatio;
  if FInnerRatio = AValue then Exit;
  FInnerRatio := AValue;
  Invalidate;
end;

procedure TTyStarShape.SetPointDown(AValue: Boolean);
begin
  if FPointDown = AValue then Exit;
  FPointDown := AValue;
  Invalidate;
end;

function TTyStarShape.ResolveGeometry(const ARect: TRect; APPI: Integer): TTyStarGeometry;
var
  S: TTyStyleSet;
  ppi: Integer;
begin
  S := CurrentStyle;                       // reuse TyPanel's resolved style
  // TTyPainter.BeginPaint's own clamp, then its own Scale (MulDiv by PPI/96): the
  // painter and this must scale identically or the ink and the hit band diverge.
  if APPI <= 0 then ppi := 96 else ppi := APPI;
  Result := TyStarGeometry(
    Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top),
    FPoints, FInnerRatio, FPointDown,
    MulDiv(S.BorderWidth, ppi, 96),
    MulDiv(TyStarMargin, ppi, 96),
    TyBorderVisible(S));
end;

function TTyStarShape.StarGeometry: TTyStarGeometry;
begin
  Result := ResolveGeometry(ClientRect, Font.PixelsPerInch);
end;

function TTyStarShape.PtInShape(const APt: TPoint): Boolean;
begin
  // +0.5 = the pixel CELL's centre. See the declaration for why the half matters.
  Result := TyPointInStar(StarGeometry, PointF(APt.X + 0.5, APt.Y + 0.5));
end;

procedure TTyStarShape.CMHitTest(var Message: TCMHitTest);
begin
  // The coordinates arrive control-relative (wincontrol.inc:5239 passes
  // Point(P.X - Left, P.Y - Top)), which for a graphic control is already client space.
  Message.Result := TyShapeHitTestAnswer(PtInShape(Point(Message.XPos, Message.YPos)));
end;

procedure TTyStarShape.CMMaskHitTest(var Message: TCMHitTest);
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

function TTyStarShape.ShapeClickPoint: TPoint;
begin
  Result := ScreenToClient(Mouse.CursorPos);
end;

procedure TTyStarShape.Click;
begin
  inherited Click;
  if Assigned(FOnShapeClick) and PtInShape(ShapeClickPoint) then
    FOnShapeClick(Self);
end;

procedure TTyStarShape.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  ctx: TBGRACanvas2D;
  G: TTyStarGeometry;
  poly: ArrayOfTPointF;
  i: Integer;
  doFill: Boolean;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;                       // reuse TyPanel's resolved style
    // ONE derivation, shared with PtInShape: RenderTo computes no geometry of its own.
    G := ResolveGeometry(ARect, APPI);
    if not G.Valid then
    begin
      P.EndPaint;
      Exit;
    end;

    poly := TyStarPolygon(G.Bounds, G.Points, G.InnerRatio, G.PointDown);
    if Length(poly) >= 3 then
    begin
      ctx := P.Bitmap.Canvas2D;
      ctx.lineJoin := 'round';

      // Trace the closed star path once; fill then stroke reuse it.
      ctx.beginPath;
      ctx.moveTo(poly[0].x, poly[0].y);
      for i := 1 to High(poly) do
        ctx.lineTo(poly[i].x, poly[i].y);
      ctx.closePath;

      // FILL: the resolved background, unless it is absent or fully transparent.
      doFill := (tpBackground in S.Present) and (S.Background.Kind = tfkSolid)
        and (TyAlphaOf(S.Background.Color) > 0);
      if doFill then
      begin
        ctx.fillStyle(TyColorToBGRA(S.Background.Color));
        ctx.fill;
      end;

      // BORDER: the resolved border colour at max(1, scaled border-width). Gated on the
      // library-wide predicate so border-style:none / border-width:0 hide it, exactly as
      // they do on every other TyControls control.
      if G.Stroked then
      begin
        ctx.lineWidth := G.StrokeWidth;
        ctx.strokeStyle(TyColorToBGRA(S.BorderColor));
        ctx.stroke;
      end;
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyStarShape.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
