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
    procedure BlitRegion(ASrc: TBGRABitmap; const ASrcR, ADstR: TRect);
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
    tfkNineSlice: NineSlice(ARect, AFill.ImagePath, AFill.SliceInsets);
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
var
  style: TTextStyle;
  s: string;
  sz: TSize;
  px: TBGRAPixel;
  fh: Integer;
begin
  if FBmp = nil then
    Exit;
  px := TyColorToBGRA(AColor);
  FBmp.FontName := AFontName;
  fh := Scale(Round(AFontSizeLogical * 96 / 72));
  FBmp.FontHeight := fh;
  FBmp.FontQuality := fqFineAntialiasing;
  if AWeight >= 600 then
    FBmp.FontStyle := [fsBold]
  else
    FBmp.FontStyle := [];
  s := AText;
  if AEllipsis then
  begin
    sz := FBmp.TextSize(s);
    while (Length(s) > 1) and (sz.cx > (ARect.Right - ARect.Left)) do
    begin
      Delete(s, Length(s), 1);
      sz := FBmp.TextSize(s + '...');
    end;
    if s <> AText then
      s := s + '...';
  end;
  FillChar(style, SizeOf(style), 0);
  style.Alignment := AHAlign;
  style.Layout := AVAlign;
  style.SingleLine := True;
  style.Clipping := True;
  FBmp.TextRect(ARect, ARect.Left, ARect.Top, s, style, px);
end;

procedure TTyPainter.DrawGlyph(const ARect: TRect; AGlyph: TTyGlyphKind; AColor: TTyColor; AThicknessLogical: Integer);
var
  px: TBGRAPixel;
  th: Single;
  pad: Integer;
  l, t, r, b, cx, cy, w, h, m: Single;
  pts: array of TPointF;
begin
  if FBmp = nil then
    Exit;
  px := TyColorToBGRA(AColor);
  th := Scale(AThicknessLogical);
  if th < 1 then
    th := 1;
  pad := Scale(4);
  l := ARect.Left + pad;
  t := ARect.Top + pad;
  r := ARect.Right - 1 - pad;
  b := ARect.Bottom - 1 - pad;
  cx := (l + r) / 2;
  cy := (t + b) / 2;
  w := r - l;
  h := b - t;
  m := w;
  if h < m then
    m := h;
  case AGlyph of
    tgClose:
      begin
        FBmp.DrawLineAntialias(l, t, r, b, px, th, True);
        FBmp.DrawLineAntialias(r, t, l, b, px, th, True);
      end;
    tgMinimize:
      FBmp.DrawLineAntialias(l, cy, r, cy, px, th, True);
    tgMaximize:
      FBmp.RectangleAntialias(l, t, r, b, px, th);
    tgRestore:
      begin
        FBmp.RectangleAntialias(l, t + h * 0.25, r - w * 0.25, b, px, th);
        FBmp.DrawPolyLineAntialias([PointF(l + w * 0.25, t + h * 0.25),
          PointF(l + w * 0.25, t), PointF(r, t), PointF(r, b - h * 0.25),
          PointF(r - w * 0.25, b - h * 0.25)], px, th);
      end;
    tgCheck:
      FBmp.DrawPolyLineAntialias([PointF(l, cy), PointF(l + w * 0.35, b),
        PointF(r, t)], px, th);
    tgRadioDot:
      FBmp.FillEllipseAntialias(cx, cy, m * 0.3, m * 0.3, px);
    tgChevronDown:
      FBmp.DrawPolyLineAntialias([PointF(l, t + h * 0.3),
        PointF(cx, b - h * 0.2), PointF(r, t + h * 0.3)], px, th);
    tgArrowUp:
      begin
        FBmp.DrawLineAntialias(cx, b, cx, t, px, th, True);
        FBmp.DrawPolyLineAntialias([PointF(l + w * 0.25, t + h * 0.35),
          PointF(cx, t), PointF(r - w * 0.25, t + h * 0.35)], px, th);
      end;
    tgArrowDown:
      begin
        FBmp.DrawLineAntialias(cx, t, cx, b, px, th, True);
        FBmp.DrawPolyLineAntialias([PointF(l + w * 0.25, b - h * 0.35),
          PointF(cx, b), PointF(r - w * 0.25, b - h * 0.35)], px, th);
      end;
  end;
  pts := nil;
end;

procedure TTyPainter.BlitRegion(ASrc: TBGRABitmap; const ASrcR, ADstR: TRect);
var
  part: TBGRABitmap;
begin
  if (ASrcR.Right <= ASrcR.Left) or (ASrcR.Bottom <= ASrcR.Top) then
    Exit;
  if (ADstR.Right <= ADstR.Left) or (ADstR.Bottom <= ADstR.Top) then
    Exit;
  part := ASrc.GetPart(ASrcR) as TBGRABitmap;
  try
    FBmp.StretchPutImage(ADstR, part, dmDrawWithTransparency);
  finally
    part.Free;
  end;
end;

procedure TTyPainter.NineSlice(const ARect: TRect; const AImagePath: string; const AInsets: TRect);
var
  src: TBGRABitmap;
  iw, ih: Integer;
  sl, st, sr, sb: Integer;
  dl, dt, dr, db: Integer;
  sxL, sxR, syT, syB: Integer;
begin
  if FBmp = nil then
    Exit;
  if not FileExists(AImagePath) then
    Exit;
  src := TBGRABitmap.Create(AImagePath);
  try
    iw := src.Width;
    ih := src.Height;
    sl := AInsets.Left;
    st := AInsets.Top;
    sr := AInsets.Right;
    sb := AInsets.Bottom;
    sxL := sl;
    sxR := iw - sr;
    syT := st;
    syB := ih - sb;
    dl := ARect.Left;
    dt := ARect.Top;
    dr := ARect.Right;
    db := ARect.Bottom;
    BlitRegion(src, Rect(0, 0, sxL, syT), Rect(dl, dt, dl + sl, dt + st));
    BlitRegion(src, Rect(sxL, 0, sxR, syT), Rect(dl + sl, dt, dr - sr, dt + st));
    BlitRegion(src, Rect(sxR, 0, iw, syT), Rect(dr - sr, dt, dr, dt + st));
    BlitRegion(src, Rect(0, syT, sxL, syB), Rect(dl, dt + st, dl + sl, db - sb));
    BlitRegion(src, Rect(sxL, syT, sxR, syB), Rect(dl + sl, dt + st, dr - sr, db - sb));
    BlitRegion(src, Rect(sxR, syT, iw, syB), Rect(dr - sr, dt + st, dr, db - sb));
    BlitRegion(src, Rect(0, syB, sxL, ih), Rect(dl, db - sb, dl + sl, db));
    BlitRegion(src, Rect(sxL, syB, sxR, ih), Rect(dl + sl, db - sb, dr - sr, db));
    BlitRegion(src, Rect(sxR, syB, iw, ih), Rect(dr - sr, db - sb, dr, db));
  finally
    src.Free;
  end;
end;

end.
