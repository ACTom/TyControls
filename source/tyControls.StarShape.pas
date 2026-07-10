unit tyControls.StarShape;
{$mode objfpc}{$H+}
{ TTyStarShape — a decorative N-point vector star.

  A leaf graphic control (TTyGraphicControl, no focus / no children) that draws a
  filled + stroked star of N outer points. The star is centred; the outer radius
  is half the min(width,height) minus a small margin; the inner radius is a
  fraction (InnerRatio) of the outer. The first outer vertex points straight UP.

  Colours are theme-driven — the control reuses the resolved TyPanel style: the
  FILL is that style's background (skipped if fully transparent), the BORDER is
  its border-color at max(1, scaled border-width). No colour is ever hard-coded;
  an app recolours a star via StyleClass / StyleOverride (e.g.
  StyleOverride := 'background: #E11; border-color: #700;').

  The polygon geometry lives in the pure function TyStarPolygon so it can be
  unit-tested headless (no window handle, no painter). RenderTo calls that fn to
  get the device-px vertices, then fills + strokes them with the Canvas2D ctx. }
interface
uses
  Classes, SysUtils, Types,
  Controls, Graphics,
  BGRABitmap, BGRABitmapTypes, BGRACanvas2D,
  tyControls.Types, tyControls.Painter, tyControls.Base;

const
  { A star needs at least 3 outer points; fewer collapses to a triangle. }
  TyStarMinPoints = 3;
  { InnerRatio clamp range — the inner radius as a fraction of the outer. }
  TyStarMinInnerRatio = 0.05;
  TyStarMaxInnerRatio = 0.95;
  { Logical-px inset from the control edge to the star's outer radius. }
  TyStarMargin = 2;

type
  TTyStarShape = class(TTyGraphicControl)
  private
    FPoints: Integer;
    FInnerRatio: Single;
    procedure SetPoints(AValue: Integer);
    procedure SetInnerRatio(AValue: Single);
  protected
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    function GetStyleTypeKey: string; override;
  published
    property Points: Integer read FPoints write SetPoints default 5;
    property InnerRatio: Single read FInnerRatio write SetInnerRatio;
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
  (12 o'clock). APoints is floored to 3; AInnerRatio is clamped to
  [TyStarMinInnerRatio, TyStarMaxInnerRatio]. No control / painter state — the
  correctness of the control IS this vertex ring, so it is unit-tested directly. }
function TyStarPolygon(const ARect: TRect; APoints: Integer;
  AInnerRatio: Single): ArrayOfTPointF;

implementation

uses
  Math;

function TyStarPolygon(const ARect: TRect; APoints: Integer;
  AInnerRatio: Single): ArrayOfTPointF;
var
  n, i: Integer;
  ratio, cx, cy, outer, inner, rr, ang: Double;
begin
  Result := nil;
  n := APoints;
  if n < TyStarMinPoints then n := TyStarMinPoints;   // point-count floor

  ratio := AInnerRatio;                                // clamp inner fraction
  if ratio < TyStarMinInnerRatio then ratio := TyStarMinInnerRatio
  else if ratio > TyStarMaxInnerRatio then ratio := TyStarMaxInnerRatio;

  cx := (ARect.Left + ARect.Right) / 2;
  cy := (ARect.Top + ARect.Bottom) / 2;
  // Outer radius = half the shorter side, so the widest vertices reach the rect
  // edge and none escape it.
  outer := Min(ARect.Right - ARect.Left, ARect.Bottom - ARect.Top) / 2;
  if outer < 0 then outer := 0;
  inner := outer * ratio;

  SetLength(Result, 2 * n);
  for i := 0 to 2 * n - 1 do
  begin
    if (i mod 2) = 0 then rr := outer else rr := inner;
    // Even index = outer, odd = inner. Start at the top (-90 deg) and step
    // 180/n deg per vertex clockwise, so vertex 0 points straight up.
    ang := DegToRad(-90 + i * (180.0 / n));
    Result[i].x := cx + rr * Cos(ang);
    Result[i].y := cy + rr * Sin(ang);
  end;
end;

constructor TTyStarShape.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FPoints := 5;
  FInnerRatio := 0.42;
  Width := 96;
  Height := 96;
end;

function TTyStarShape.GetStyleTypeKey: string;
begin
  Result := 'TyPanel';   // reuse the panel typeKey — no new theme token
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

procedure TTyStarShape.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  ctx: TBGRACanvas2D;
  poly: ArrayOfTPointF;
  starRect: TRect;
  margin, bw, w, h, i: Integer;
  doFill, doStroke: Boolean;
begin
  P := TTyPainter.Create;
  try
    P.BeginPaint(ACanvas, ARect, APPI);
    S := CurrentStyle;                       // reuse TyPanel's resolved style
    w := ARect.Right - ARect.Left;
    h := ARect.Bottom - ARect.Top;
    if (w <= 0) or (h <= 0) then
    begin
      P.EndPaint;
      Exit;
    end;

    doStroke := TyBorderVisible(S);
    bw := P.Scale(S.BorderWidth);
    if bw < 1 then bw := 1;

    // Inset the star by the scaled margin PLUS half the stroke: TyStarPolygon puts the
    // outer vertices exactly on starRect's edge, and Canvas2D centres the stroke on the
    // path, so a fixed margin alone loses half a thick border off the bitmap.
    margin := P.Scale(TyStarMargin);
    if doStroke then Inc(margin, (bw + 1) div 2);
    starRect := Rect(margin, margin, w - margin, h - margin);
    if (starRect.Right <= starRect.Left) or (starRect.Bottom <= starRect.Top) then
      starRect := Rect(0, 0, w, h);

    poly := TyStarPolygon(starRect, FPoints, FInnerRatio);
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
      if doStroke then
      begin
        ctx.lineWidth := bw;
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
