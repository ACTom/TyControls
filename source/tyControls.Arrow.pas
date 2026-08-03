unit tyControls.Arrow;
{$mode objfpc}{$H+}
{ TTyArrow — a directional arrow (a themed vector shape) in one of two glyphs.

  Shape = tasBlock (the default) draws the classic 7-point block arrow — a rectangular
  shaft that widens into a triangular head pointing in one of four directions (right /
  left / up / down). The head length (as a fraction of the total length) and the shaft
  thickness (as a fraction of the breadth) are adjustable via HeadRatio / ShaftRatio.

  Shape = tasTriangle draws LCL TArrow's glyph instead: a bare 3-point triangle whose
  apex angle is ArrowPointerAngle degrees, scaled to fit the client rect. That glyph
  was previously unreachable from this control at any property setting, and nothing
  else in the library draws a directional triangle.

  No new theme token: the control reuses the resolved TyPanel style — the FILL is the
  TyPanel background colour, the BORDER is its border-color at its border-width. An app
  recolours a particular arrow via StyleClass / StyleOverride
  (e.g. StyleOverride := 'background: #E11; border-color: #700;'). No colour is ever
  hard-coded in control code.

  The vertices of both glyphs live in pure, unit-testable free functions —
  TyArrowPolygon (7 points) and TyArrowTrianglePolygon (3 points) — so the geometry can
  be asserted headless (vertex count, in-rect containment, the tip landing on the
  correct edge, ratio/angle clamping). RenderTo just fills+strokes whichever it gets. }
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics,
  BGRABitmap, BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base;

const
  { Block-arrow proportions. Geometry, not paint: like HeadRatio / ShaftRatio these are
    unit constants and published properties, NOT theme tokens — a skin recolours an
    arrow, it does not redesign it. }
  TyArrowDefHeadRatio  = 0.45;
  TyArrowDefShaftRatio = 0.5;
  TyArrowMinRatio      = 0.1;
  TyArrowMaxRatio      = 0.9;
  { Triangle apex angle, in degrees. Verbatim from LCL TArrow (arrow.pp): 60 is the
    equilateral default, 20..160 its cMinAngle/cMaxAngle. }
  TyArrowDefPointerAngle = 60;
  TyArrowMinPointerAngle = 20;
  TyArrowMaxPointerAngle = 160;

type
  { Which way the arrow points.

    ONE divergence from LCL's TArrow survives, and no compiler will tell you about it
    because a form ported either direction compiles and just looks wrong:

      DEFAULT DIRECTION.  TArrow.ArrowType defaults to atLeft (arrow.pp). This defaults
      to tadRight. So an arrow you never configured points the opposite way.

    It stays. Flipping the default would silently rotate every arrow on every existing
    form, and the property is not even spelled ArrowType, so nobody ports it by name.
    Recorded here rather than left to be discovered on screen.

    The other divergence used to be the GLYPH -- see TTyArrowShape, which now reaches
    TArrow's triangle instead of merely documenting its absence. }
  TTyArrowDirection = (tadRight, tadLeft, tadUp, tadDown);

  { Which glyph the arrow draws.

    tasBlock is the default and stays the default: it is what this library's look wants,
    and changing it would redraw every arrow on every form already built. tasTriangle is
    LCL TArrow's glyph (TTrianglePoints = array[ptA..ptC], arrow.pp) -- three points, no
    shaft, sized by an apex angle -- reachable now for a ported form or a plain pointer. }
  TTyArrowShape = (tasBlock, tasTriangle);

  TTyArrow = class(TTyGraphicControl)
  private
    FDirection: TTyArrowDirection;
    FShape: TTyArrowShape;
    FPointerAngle: Integer;
    FHeadRatio: Single;
    FShaftRatio: Single;
    procedure SetDirection(AValue: TTyArrowDirection);
    procedure SetShape(AValue: TTyArrowShape);
    procedure SetPointerAngle(AValue: Integer);
    procedure SetHeadRatio(AValue: Single);
    procedure SetShaftRatio(AValue: Single);
  protected
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    function GetStyleTypeKey: string; override;
  published
    property Direction: TTyArrowDirection read FDirection write SetDirection default tadRight;
    { Which of the two glyphs to draw. HeadRatio / ShaftRatio shape the block arrow only;
      ArrowPointerAngle shapes the triangle only. Each is inert in the other mode. }
    property Shape: TTyArrowShape read FShape write SetShape default tasBlock;
    { The triangle's APEX angle in degrees, clamped 20..160 — LCL TArrow's own name,
      default and limits (arrow.pp: ArrowPointerAngle, cMinAngle, cMaxAngle). Kept
      spelled exactly as LCL spells it so a ported form's assignment still compiles;
      Direction is the one name that could not be kept, because it shipped first. }
    property ArrowPointerAngle: Integer read FPointerAngle write SetPointerAngle
      default TyArrowDefPointerAngle;
    property HeadRatio: Single read FHeadRatio write SetHeadRatio;
    property ShaftRatio: Single read FShaftRatio write SetShaftRatio;
    property Align;
    property Anchors;
    property StyleClass;
    property StyleOverride;
    property Controller;
  end;

{ Pure geometry: the 7 vertices of a block arrow inscribed in ARect, pointing ADir.

  AHeadRatio is the fraction of the arrow's LENGTH (the extent along the pointing axis)
  taken by the triangular head; AShaftRatio is the shaft thickness as a fraction of the
  BREADTH (the extent across the pointing axis). Both are clamped to 0.1..0.9.

  The result is always exactly 7 TPointF in device px, all inside ARect, wound in a
  consistent order starting at the tip. The tip sits on the midpoint of the edge the
  arrow points at. No control state, no painter, no handle — unit-testable directly. }
function TyArrowPolygon(const ARect: TRect; ADir: TTyArrowDirection;
  AHeadRatio, AShaftRatio: Single): ArrayOfTPointF;

{ Pure geometry: the 3 vertices of LCL TArrow's triangle inscribed in ARect, pointing
  ADir, with an APEX angle of AAngleDeg degrees (clamped 20..160).

  The apex angle fixes the triangle's base:height ratio at 2*tan(angle/2), so the
  triangle is scaled down on whichever axis would otherwise break that ratio and then
  CENTRED in ARect — LCL's CalcTrianglePoints (arrow.pp) does the same fit. Two
  deliberate departures from it: the arithmetic stays in floats (LCL truncates to
  integers, which is why it needs a special case at exactly 90 degrees), and there is
  no 2px inner offset (that offset only exists to make room for TArrow's drop shadow,
  which this control does not draw).

  The result is always exactly 3 TPointF in device px, all inside ARect, wound from the
  TIP in the same order as TyArrowPolygon's. The tip lies on the pointing axis' centre
  line but is only ON the pointing edge when the angle happens to fill ARect — an angle
  narrower than the rect leaves the whole triangle centred and short of that edge. }
function TyArrowTrianglePolygon(const ARect: TRect; ADir: TTyArrowDirection;
  AAngleDeg: Integer): ArrayOfTPointF;

implementation

function ClampRatio(A: Single): Single;
begin
  if A < TyArrowMinRatio then Result := TyArrowMinRatio
  else if A > TyArrowMaxRatio then Result := TyArrowMaxRatio
  else Result := A;
end;

function TyArrowPolygon(const ARect: TRect; ADir: TTyArrowDirection;
  AHeadRatio, AShaftRatio: Single): ArrayOfTPointF;
var
  hr, sr: Single;
  L, T, R, B: Single;
  w, h: Single;
  headLen, shaftHalf: Single;
  midX, midY, headBase: Single;
begin
  Result := nil;
  hr := ClampRatio(AHeadRatio);
  sr := ClampRatio(AShaftRatio);

  L := ARect.Left;
  T := ARect.Top;
  R := ARect.Right;
  B := ARect.Bottom;
  w := R - L;
  h := B - T;

  SetLength(Result, 7);

  { The 7 points are wound starting at the TIP, then around the head barbs and along
    one shaft side, across the shaft tail, and back up the other shaft side. For the
    horizontal directions the "length" axis is X and the "breadth" axis is Y; for the
    vertical directions they swap. }
  case ADir of
    tadRight:
      begin
        headLen   := w * hr;
        shaftHalf := (h * sr) / 2;
        midY      := (T + B) / 2;
        headBase  := R - headLen;                 // where head meets shaft
        Result[0] := PointF(R, midY);             // tip (right edge midpoint)
        Result[1] := PointF(headBase, T);         // upper barb
        Result[2] := PointF(headBase, midY - shaftHalf);
        Result[3] := PointF(L, midY - shaftHalf); // shaft tail, top
        Result[4] := PointF(L, midY + shaftHalf); // shaft tail, bottom
        Result[5] := PointF(headBase, midY + shaftHalf);
        Result[6] := PointF(headBase, B);         // lower barb
      end;
    tadLeft:
      begin
        headLen   := w * hr;
        shaftHalf := (h * sr) / 2;
        midY      := (T + B) / 2;
        headBase  := L + headLen;
        Result[0] := PointF(L, midY);             // tip (left edge midpoint)
        Result[1] := PointF(headBase, B);         // lower barb
        Result[2] := PointF(headBase, midY + shaftHalf);
        Result[3] := PointF(R, midY + shaftHalf); // shaft tail, bottom
        Result[4] := PointF(R, midY - shaftHalf); // shaft tail, top
        Result[5] := PointF(headBase, midY - shaftHalf);
        Result[6] := PointF(headBase, T);         // upper barb
      end;
    tadUp:
      begin
        headLen   := h * hr;
        shaftHalf := (w * sr) / 2;
        midX      := (L + R) / 2;
        headBase  := T + headLen;
        Result[0] := PointF(midX, T);             // tip (top edge midpoint)
        Result[1] := PointF(L, headBase);         // left barb
        Result[2] := PointF(midX - shaftHalf, headBase);
        Result[3] := PointF(midX - shaftHalf, B); // shaft tail, left
        Result[4] := PointF(midX + shaftHalf, B); // shaft tail, right
        Result[5] := PointF(midX + shaftHalf, headBase);
        Result[6] := PointF(R, headBase);         // right barb
      end;
  else // tadDown
    begin
      headLen   := h * hr;
      shaftHalf := (w * sr) / 2;
      midX      := (L + R) / 2;
      headBase  := B - headLen;
      Result[0] := PointF(midX, B);               // tip (bottom edge midpoint)
      Result[1] := PointF(R, headBase);           // right barb
      Result[2] := PointF(midX + shaftHalf, headBase);
      Result[3] := PointF(midX + shaftHalf, T);   // shaft tail, right
      Result[4] := PointF(midX - shaftHalf, T);   // shaft tail, left
      Result[5] := PointF(midX - shaftHalf, headBase);
      Result[6] := PointF(L, headBase);           // left barb
    end;
  end;
end;

function ClampPointerAngle(A: Integer): Integer;
begin
  if A < TyArrowMinPointerAngle then Result := TyArrowMinPointerAngle
  else if A > TyArrowMaxPointerAngle then Result := TyArrowMaxPointerAngle
  else Result := A;
end;

function TyArrowTrianglePolygon(const ARect: TRect; ADir: TTyArrowDirection;
  AAngleDeg: Integer): ArrayOfTPointF;
var
  ang: Integer;
  ratioNeed, ratioThis: Single;
  w, h, tw, th: Single;
  midX, midY, L, T, R, B: Single;
begin
  Result := nil;
  SetLength(Result, 3);
  ang := ClampPointerAngle(AAngleDeg);

  w := ARect.Right - ARect.Left;
  h := ARect.Bottom - ARect.Top;
  midX := (ARect.Left + ARect.Right) / 2;
  midY := (ARect.Top + ARect.Bottom) / 2;
  if (w <= 0) or (h <= 0) then
  begin
    // Degenerate box: collapse to the centre rather than divide by zero. Callers that
    // paint bail out earlier; this keeps the pure function total.
    Result[0] := PointF(midX, midY);
    Result[1] := Result[0];
    Result[2] := Result[0];
    Exit;
  end;

  { base : height for an isosceles triangle of apex angle `ang`. The pointing axis is Y
    for up/down, so the ratio applies as-is there and INVERTED for left/right. }
  ratioNeed := 2 * Tan(ang * Pi / 360);
  if ADir in [tadLeft, tadRight] then ratioNeed := 1 / ratioNeed;

  ratioThis := w / h;
  tw := w;
  th := h;
  if ratioThis >= ratioNeed then
    tw := h * ratioNeed     // too wide for the angle: shrink across
  else
    th := w / ratioNeed;    // too tall for the angle: shrink along

  L := midX - tw / 2;
  R := L + tw;
  T := midY - th / 2;
  B := T + th;

  { Wound from the TIP, then the two base corners in the same rotational order
    TyArrowPolygon uses (right: upper then lower; left: lower then upper; up: left then
    right; down: right then left) so both glyphs stroke identically. }
  case ADir of
    tadRight:
      begin
        Result[0] := PointF(R, midY);
        Result[1] := PointF(L, T);
        Result[2] := PointF(L, B);
      end;
    tadLeft:
      begin
        Result[0] := PointF(L, midY);
        Result[1] := PointF(R, B);
        Result[2] := PointF(R, T);
      end;
    tadUp:
      begin
        Result[0] := PointF(midX, T);
        Result[1] := PointF(L, B);
        Result[2] := PointF(R, B);
      end;
  else // tadDown
    begin
      Result[0] := PointF(midX, B);
      Result[1] := PointF(R, T);
      Result[2] := PointF(L, T);
    end;
  end;
end;

constructor TTyArrow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDirection := tadRight;
  FShape := tasBlock;
  FPointerAngle := TyArrowDefPointerAngle;
  FHeadRatio := TyArrowDefHeadRatio;
  FShaftRatio := TyArrowDefShaftRatio;
  Width := 120;
  Height := 64;
end;

function TTyArrow.GetStyleTypeKey: string;
begin
  { Own key rather than the borrowed 'TyPanel': a directional marker on a diagram is not a panel surface.
    Added to 'TyPanel's rule block as an extra selector, so every resolved value is
    unchanged — this opens a hook, it does not restyle anything. }
  Result := 'TyArrow';
end;

procedure TTyArrow.SetDirection(AValue: TTyArrowDirection);
begin
  if FDirection = AValue then Exit;
  FDirection := AValue;
  Invalidate;
end;

procedure TTyArrow.SetShape(AValue: TTyArrowShape);
begin
  if FShape = AValue then Exit;
  FShape := AValue;
  Invalidate;
end;

procedure TTyArrow.SetPointerAngle(AValue: Integer);
begin
  // Clamp on assignment for the same reason the ratios do: otherwise the property reads
  // back (and streams to .lfm) an angle the arrow never draws.
  AValue := ClampPointerAngle(AValue);
  if FPointerAngle = AValue then Exit;
  FPointerAngle := AValue;
  Invalidate;
end;

procedure TTyArrow.SetHeadRatio(AValue: Single);
begin
  // Clamp on assignment, not just at render time: otherwise the property reads back (and
  // streams to .lfm) a value the arrow never draws.
  AValue := ClampRatio(AValue);
  if FHeadRatio = AValue then Exit;
  FHeadRatio := AValue;
  Invalidate;
end;

procedure TTyArrow.SetShaftRatio(AValue: Single);
begin
  AValue := ClampRatio(AValue);
  if FShaftRatio = AValue then Exit;
  FShaftRatio := AValue;
  Invalidate;
end;

procedure TTyArrow.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R: TRect;
  ctx: TBGRACanvas2D;
  pts: ArrayOfTPointF;
  i, bw, hw: Integer;
  w, h: Integer;
  doStroke: Boolean;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    w := R.Right - R.Left;
    h := R.Bottom - R.Top;
    if (w <= 0) or (h <= 0) then
    begin
      P.EndPaint;
      Exit;
    end;

    doStroke := TyBorderVisible(S);
    bw := P.Scale(S.BorderWidth);
    if bw < 1 then bw := 1;
    { Inset by ceil(half the stroke width) so the centred border stays fully inside the
      client rect. With no border the arrow fills the whole rect. }
    if doStroke then hw := (bw + 1) div 2 else hw := 0;
    InflateRect(R, -hw, -hw);
    if (R.Right - R.Left <= 0) or (R.Bottom - R.Top <= 0) then
      R := Rect(0, 0, w, h);

    if FShape = tasTriangle then
      pts := TyArrowTrianglePolygon(R, FDirection, FPointerAngle)
    else
      pts := TyArrowPolygon(R, FDirection, FHeadRatio, FShaftRatio);

    ctx := P.Bitmap.Canvas2D;
    ctx.beginPath;
    ctx.moveTo(pts[0].x, pts[0].y);
    for i := 1 to High(pts) do
      ctx.lineTo(pts[i].x, pts[i].y);
    ctx.closePath;

    // FILL: the resolved TyPanel background (skip when there is no solid, visible fill).
    if (S.Background.Kind = tfkSolid) and (TyAlphaOf(S.Background.Color) > 0) then
    begin
      ctx.fillStyle(TyColorToBGRA(S.Background.Color));
      ctx.fill;
    end;

    // BORDER: the resolved border colour at (scaled) border width, when visible.
    if doStroke then
    begin
      ctx.lineWidth := bw;
      ctx.lineJoin := 'miter';
      ctx.strokeStyle(TyColorToBGRA(S.BorderColor));
      ctx.stroke;
    end;

    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyArrow.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

end.
