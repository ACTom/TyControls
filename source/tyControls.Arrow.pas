unit tyControls.Arrow;
{$mode objfpc}{$H+}
{ TTyArrow — a directional block arrow (a themed vector shape).

  It draws the classic 7-point block arrow — a rectangular shaft that widens into a
  triangular head pointing in one of four directions (right / left / up / down). The
  head length (as a fraction of the total length) and the shaft thickness (as a
  fraction of the breadth) are adjustable via HeadRatio / ShaftRatio.

  No new theme token: the control reuses the resolved TyPanel style — the FILL is the
  TyPanel background colour, the BORDER is its border-color at its border-width. An app
  recolours a particular arrow via StyleClass / StyleOverride
  (e.g. StyleOverride := 'background: #E11; border-color: #700;'). No colour is ever
  hard-coded in control code.

  The 7 vertices live in the pure, unit-testable free function TyArrowPolygon so the
  geometry can be asserted headless (vertex count, in-rect containment, the tip landing
  on the correct edge midpoint, and ratio clamping). RenderTo just fills+strokes it. }
interface
uses
  Classes, SysUtils, Types, Controls, Graphics,
  BGRABitmap, BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base;

type
  { Which way the arrow points. }
  { NOT interchangeable with LCL's TArrow, in two ways that no compiler will tell you
    about, because a form ported either direction compiles and just looks wrong:

      SHAPE.  TArrow draws a three-point TRIANGLE (TTrianglePoints = array[ptA..ptC],
      arrow.pp). TTyArrow draws a seven-point BLOCK arrow -- a shaft with a head. Same
      component name, different glyph.

      DEFAULT DIRECTION.  TArrow.ArrowType defaults to atLeft (arrow.pp). This defaults
      to tadRight. So an arrow you never configured points the opposite way.

    Both are deliberate -- a block arrow is what this library's look wants -- but they
    are recorded here rather than left to be discovered on screen. The property is also
    named Direction, not ArrowType. }
  TTyArrowDirection = (tadRight, tadLeft, tadUp, tadDown);

  TTyArrow = class(TTyGraphicControl)
  private
    FDirection: TTyArrowDirection;
    FHeadRatio: Single;
    FShaftRatio: Single;
    procedure SetDirection(AValue: TTyArrowDirection);
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

const
  TyArrowDefHeadRatio  = 0.45;
  TyArrowDefShaftRatio = 0.5;
  TyArrowMinRatio      = 0.1;
  TyArrowMaxRatio      = 0.9;

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

constructor TTyArrow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FDirection := tadRight;
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
