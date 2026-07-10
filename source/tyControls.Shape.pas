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
  control's RenderTo calls it, then fills+strokes the returned path. }
interface
uses
  Classes, SysUtils, Types, Controls, Graphics,
  BGRABitmap, BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base;

type
  { Which vector shape TTyShape draws. }
  TTyShapeKind = (tskRectangle, tskRoundRect, tskSquare, tskEllipse, tskCircle,
                  tskTriangle, tskDiamond, tskLine);

  TTyShape = class(TTyGraphicControl)
  private
    FShape: TTyShapeKind;
    procedure SetShape(AValue: TTyShapeKind);
  protected
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    function GetStyleTypeKey: string; override;
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

constructor TTyShape.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FShape := tskRectangle;
  Width := 120;
  Height := 80;
end;

function TTyShape.GetStyleTypeKey: string;
begin
  Result := 'TyPanel';   // reuse the panel typeKey (no new theme token this batch)
end;

procedure TTyShape.SetShape(AValue: TTyShapeKind);
begin
  if FShape = AValue then Exit;
  FShape := AValue;
  Invalidate;
end;

procedure TTyShape.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  ctx: TBGRACanvas2D;
  R, sq: TRect;
  poly: ArrayOfTPointF;
  bw, hw, rad, w, h: Integer;
  hasFill, hasBorder: Boolean;
  fillPx, strokePx: TBGRAPixel;

  { Build the current path for the shape kind (excluding line, which is stroked
    directly). Fills use the closed path; the same path is stroked for the border. }
  procedure BuildPath;
  var
    rr: Single;
    i: Integer;   { must be local: FPC forbids an outer var as a nested for-counter }
  begin
    ctx.beginPath;
    case FShape of
      tskEllipse:
        ctx.ellipse((R.Left + R.Right) / 2, (R.Top + R.Bottom) / 2,
                    (R.Right - R.Left) / 2, (R.Bottom - R.Top) / 2);
      tskCircle:
        begin
          sq := TyShapeSquareRect(R);
          ctx.arc((sq.Left + sq.Right) / 2, (sq.Top + sq.Bottom) / 2,
                  (sq.Right - sq.Left) / 2, 0, 2 * Pi, False);
        end;
      tskSquare:
        begin
          sq := TyShapeSquareRect(R);
          ctx.rect(sq.Left, sq.Top, sq.Right - sq.Left, sq.Bottom - sq.Top);
        end;
      tskRoundRect:
        begin
          // theme BorderRadius, DPI-scaled, capped at half the shorter side
          rad := P.Scale(TyEffectiveCorners(S).TL);
          if rad < 0 then rad := 0;
          w := R.Right - R.Left;
          h := R.Bottom - R.Top;
          rr := rad;
          if rr > w / 2 then rr := w / 2;
          if rr > h / 2 then rr := h / 2;
          if rr < 0 then rr := 0;
          ctx.roundRect(R.Left, R.Top, w, h, rr);
        end;
      tskTriangle, tskDiamond:
        begin
          poly := TyShapePolygon(FShape, R);
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
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    if (R.Right <= R.Left) or (R.Bottom <= R.Top) then
    begin
      P.EndPaint;
      Exit;   // degenerate
    end;

    ctx := P.Bitmap.Canvas2D;
    bw := P.Scale(S.BorderWidth);
    if bw < 1 then bw := 1;
    strokePx := TyColorToBGRA(S.BorderColor);
    // tskLine's stroke IS the shape, not chrome around it, so it draws regardless of
    // border-style/border-width; every other kind gates on the theme like the rest of
    // the library (tyControls.Base.pas).
    hasBorder := TyBorderVisible(S) or (FShape = tskLine);

    // Canvas2D centres a stroke on its path, so a path on the rect edge loses its outer
    // half. Inset by ceil(bw/2) on EVERY side — an asymmetric inset clips the near edges
    // (bw div 2 = 0 for the common 1px border). With no border the shape fills the rect.
    if hasBorder then
    begin
      hw := (bw + 1) div 2;
      R := Rect(R.Left + hw, R.Top + hw, R.Right - hw, R.Bottom - hw);
      if (R.Right <= R.Left) or (R.Bottom <= R.Top) then
      begin
        P.EndPaint;
        Exit;
      end;
    end;

    if FShape = tskLine then
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
    if hasBorder then
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
