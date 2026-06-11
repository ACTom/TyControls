unit tyControls.Painter;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics, LCLType, BGRABitmap, BGRABitmapTypes,
  BGRAGradientScanner, tyControls.Types;

type
  TTyGlyphKind = (tgClose, tgMinimize, tgMaximize, tgRestore, tgCheck,
    tgRadioDot, tgChevronDown, tgArrowUp, tgArrowDown);

  TTyPainter = class
  private
    FBmp: TBGRABitmap;
    FCanvas: TCanvas;
    FRect: TRect;
    FPPI: Integer;
    procedure GradientEndpoints(const ARect: TRect; AAngleDeg: Single; out P1, P2: TPointF);
  public
    procedure BeginPaint(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure EndPaint;
    function Scale(ALogical: Integer): Integer;
    procedure FillBackground(const ARect: TRect; const AFill: TTyFill; ARadiusLogical: Integer);
    procedure StrokeBorder(const ARect: TRect; ARadiusLogical, AWidthLogical: Integer; AColor: TTyColor);
    procedure DropShadow(const ARect: TRect; ARadiusLogical: Integer; AColor: TTyColor; ABlurLogical: Integer; const AOffsetLogical: TPoint);
    procedure DrawText(const ARect: TRect; const AText, AFontName: string; AFontSizeLogical, AWeight: Integer; AColor: TTyColor; AHAlign: TAlignment; AVAlign: TTextLayout; AEllipsis: Boolean);
    procedure DrawGlyph(const ARect: TRect; AGlyph: TTyGlyphKind; AColor: TTyColor; AThicknessLogical: Integer);
    procedure NineSlice(const ARect: TRect; const AImagePath: string; const AInsets: TRect);
    property Bitmap: TBGRABitmap read FBmp;
  end;

function TyColorToBGRA(c: TTyColor): TBGRAPixel;

implementation

function TyColorToBGRA(c: TTyColor): TBGRAPixel;
begin
  Result := BGRA(TyRedOf(c), TyGreenOf(c), TyBlueOf(c), TyAlphaOf(c));
end;

procedure TTyPainter.BeginPaint(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  FCanvas := ACanvas;
  FRect := ARect;
  if APPI <= 0 then
    FPPI := 96
  else
    FPPI := APPI;
  FBmp := TBGRABitmap.Create(ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
  FBmp.Fill(BGRAPixelTransparent);
end;

procedure TTyPainter.EndPaint;
begin
  if Assigned(FBmp) then
  begin
    if Assigned(FCanvas) then
      FBmp.Draw(FCanvas, FRect.Left, FRect.Top, False);
    FreeAndNil(FBmp);
  end;
end;

function TTyPainter.Scale(ALogical: Integer): Integer;
begin
  Result := MulDiv(ALogical, FPPI, 96);
end;

procedure TTyPainter.GradientEndpoints(const ARect: TRect; AAngleDeg: Single; out P1, P2: TPointF);
var
  rad, dx, dy, cx, cy, hw, hh, t: Single;
begin
  rad := AAngleDeg * Pi / 180;
  dx := Cos(rad);
  dy := Sin(rad);
  cx := (ARect.Left + ARect.Right) / 2;
  cy := (ARect.Top + ARect.Bottom) / 2;
  hw := (ARect.Right - ARect.Left) / 2;
  hh := (ARect.Bottom - ARect.Top) / 2;
  t := Abs(dx) * hw + Abs(dy) * hh;
  P1.x := cx - dx * t;
  P1.y := cy - dy * t;
  P2.x := cx + dx * t;
  P2.y := cy + dy * t;
end;

procedure TTyPainter.FillBackground(const ARect: TRect; const AFill: TTyFill; ARadiusLogical: Integer);
var
  r: Integer;
  px: TBGRAPixel;
  p1f, p2f: TPointF;
  grad: TBGRAGradientScanner;
begin
  if FBmp = nil then
    Exit;
  r := Scale(ARadiusLogical);
  case AFill.Kind of
    tfkSolid:
      begin
        px := TyColorToBGRA(AFill.Color);
        if r <= 0 then
          FBmp.FillRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, px, dmDrawWithTransparency)
        else
          FBmp.FillRoundRectAntialias(ARect.Left, ARect.Top, ARect.Right - 1, ARect.Bottom - 1, r, r, px, []);
      end;
    tfkNone: ;
    tfkLinearGradient:
      begin
        GradientEndpoints(ARect, AFill.GradAngleDeg, p1f, p2f);
        grad := TBGRAGradientScanner.Create(TyColorToBGRA(AFill.GradFrom), TyColorToBGRA(AFill.GradTo), gtLinear, p1f, p2f);
        try
          if r <= 0 then
            FBmp.FillRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, grad, dmDrawWithTransparency, daNearestNeighbor)
          else
            FBmp.FillRoundRectAntialias(ARect.Left, ARect.Top, ARect.Right - 1, ARect.Bottom - 1, r, r, grad, [rrDefault]);
        finally
          grad.Free;
        end;
      end;
    tfkNineSlice: ;
  end;
end;

procedure TTyPainter.StrokeBorder(const ARect: TRect; ARadiusLogical, AWidthLogical: Integer; AColor: TTyColor);
var
  w, r: Integer;
  half: Single;
  px: TBGRAPixel;
  l, t, rr, b: Single;
begin
  if FBmp = nil then
    Exit;
  w := Scale(AWidthLogical);
  if w <= 0 then
    Exit;
  r := Scale(ARadiusLogical);
  px := TyColorToBGRA(AColor);
  half := w / 2;
  l := ARect.Left + half;
  t := ARect.Top + half;
  rr := ARect.Right - 1 - half;
  b := ARect.Bottom - 1 - half;
  if r <= 0 then
    FBmp.RectangleAntialias(l, t, rr, b, px, w)
  else
    FBmp.RoundRectAntialias(l, t, rr, b, r, r, px, w);
end;

procedure TTyPainter.DropShadow(const ARect: TRect; ARadiusLogical: Integer; AColor: TTyColor; ABlurLogical: Integer; const AOffsetLogical: TPoint);
var
  r, blur, ox, oy: Integer;
  shadow, blurred: TBGRABitmap;
  px: TBGRAPixel;
begin
  if FBmp = nil then
    Exit;
  r := Scale(ARadiusLogical);
  blur := Scale(ABlurLogical);
  ox := Scale(AOffsetLogical.X);
  oy := Scale(AOffsetLogical.Y);
  px := TyColorToBGRA(AColor);
  shadow := TBGRABitmap.Create(FBmp.Width, FBmp.Height, BGRAPixelTransparent);
  try
    if r <= 0 then
      shadow.FillRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, px, dmSet)
    else
      shadow.FillRoundRectAntialias(ARect.Left, ARect.Top, ARect.Right - 1, ARect.Bottom - 1, r, r, px, [rrDefault]);
    if blur > 0 then
    begin
      blurred := shadow.FilterBlurRadial(blur, rbFast) as TBGRABitmap;
      try
        FBmp.PutImage(ox, oy, blurred, dmDrawWithTransparency);
      finally
        blurred.Free;
      end;
    end
    else
      FBmp.PutImage(ox, oy, shadow, dmDrawWithTransparency);
  finally
    shadow.Free;
  end;
end;

procedure TTyPainter.DrawText(const ARect: TRect; const AText, AFontName: string; AFontSizeLogical, AWeight: Integer; AColor: TTyColor; AHAlign: TAlignment; AVAlign: TTextLayout; AEllipsis: Boolean);
begin
end;

procedure TTyPainter.DrawGlyph(const ARect: TRect; AGlyph: TTyGlyphKind; AColor: TTyColor; AThicknessLogical: Integer);
begin
end;

procedure TTyPainter.NineSlice(const ARect: TRect; const AImagePath: string; const AInsets: TRect);
begin
end;

end.
