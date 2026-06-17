unit tyControls.Painter;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Graphics, LCLType, BGRABitmap, BGRABitmapTypes,
  BGRAGradientScanner,
  FPReadJPEG, FPReadPNG, FPReadBMP,  // register FPImage readers so url() jpg/png/bmp load
  tyControls.Types;

type
  TTyGlyphKind = (tgClose, tgMinimize, tgMaximize, tgRestore, tgCheck,
    tgRadioDot, tgChevronDown, tgArrowUp, tgArrowDown, tgArrowLeft, tgArrowRight);

  TTyPainter = class
  private
    FBmp: TBGRABitmap;
    FCanvas: TCanvas;
    FRect: TRect;
    FPPI: Integer;
    procedure GradientEndpoints(const ARect: TRect; AAngleDeg: Single; out P1, P2: TPointF);
    procedure BlitRegion(ASrc: TBGRABitmap; const ASrcR, ADstR: TRect);
  public
    Opacity: Single;
    procedure BeginPaint(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure EndPaint;
    function Scale(ALogical: Integer): Integer;
    procedure FillBackground(const ARect: TRect; const AFill: TTyFill; ARadiusLogical: Integer); overload;
    procedure FillBackground(const ARect: TRect; const AFill: TTyFill; const ACorners: TTyCorners); overload;
    procedure StrokeBorder(const ARect: TRect; ARadiusLogical, AWidthLogical: Integer; AColor: TTyColor); overload;
    procedure StrokeBorder(const ARect: TRect; const ACorners: TTyCorners; AWidthLogical: Integer; AColor: TTyColor); overload;
    procedure DropShadow(const ARect: TRect; ARadiusLogical: Integer; AColor: TTyColor; ABlurLogical: Integer; const AOffsetLogical: TPoint);
    procedure DrawText(const ARect: TRect; const AText, AFontName: string; AFontSizeLogical, AWeight: Integer; AColor: TTyColor; AHAlign: TAlignment; AVAlign: TTextLayout; AEllipsis: Boolean);
    procedure DrawGlyph(const ARect: TRect; AGlyph: TTyGlyphKind; AColor: TTyColor; AThicknessLogical: Integer);
    procedure NineSlice(const ARect: TRect; const AImagePath: string; const AInsets: TRect);
    procedure DrawImageFill(const ARect: TRect; const AImagePath: string; AMode: TTyImageMode; ABlurLogical: Integer);
    procedure FillGlass(const ARect: TRect; ASharp, AGlass: TBGRABitmap; const ASrcOffset: TPoint; const ATint: TTyColor; const ACorners: TTyCorners);
    procedure EraseRect(const ARect: TRect);
    property Bitmap: TBGRABitmap read FBmp;
  end;

function TyColorToBGRA(c: TTyColor): TBGRAPixel;

// Shared font setup so text measurement (in controls) matches text drawing
// (in TTyPainter.DrawText) exactly: same BGRA engine, same height semantics.
procedure TyConfigureTextFont(ABmp: TBGRABitmap; const AFontName: string;
  AFontSizeLogical, AWeight, APPI: Integer);

// Resolves the concrete font name to use: the style's font-family if set,
// otherwise the TyFallbackFontName (when non-empty). Both BGRA config and the
// few LCL-canvas caption-width measures (GroupBox/TabControl) go through this so
// measured width matches drawn glyphs even when the theme sets no font-family.
function TyEffectiveFontName(const AName: string): string;

var
  // Concrete font used when a style/theme provides no font-family.
  // When AFontName='' and this is non-empty, it is passed to BGRA instead of ''.
  // ''=leave empty (default; unchanged behavior). The controller may set this
  // from the real system font for GUI apps -- see tyControls.Controller. Passing
  // an empty name to BGRA triggers a fallback path that drops the last glyph and
  // mis-advances text in the real GUI, so substituting a concrete name fixes it.
  TyFallbackFontName: string;

implementation

function TyEffectiveFontName(const AName: string): string;
begin
  if (AName = '') and (TyFallbackFontName <> '') then
    Result := TyFallbackFontName
  else
    Result := AName;
end;

procedure TyConfigureTextFont(ABmp: TBGRABitmap; const AFontName: string;
  AFontSizeLogical, AWeight, APPI: Integer);
begin
  ABmp.FontName := TyEffectiveFontName(AFontName);
  ABmp.FontHeight := MulDiv(Round(AFontSizeLogical * 96 / 72), APPI, 96);
  ABmp.FontQuality := fqFineAntialiasing;
  if AWeight >= 600 then ABmp.FontStyle := [fsBold] else ABmp.FontStyle := [];
end;

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
  Opacity := 1.0;
  FBmp := TBGRABitmap.Create(ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
  FBmp.Fill(BGRAPixelTransparent);
end;

procedure TTyPainter.EndPaint;
begin
  if Assigned(FBmp) then
  begin
    if Assigned(FCanvas) then
    begin
      if Opacity < 1.0 then
        FBmp.ApplyGlobalOpacity(Round(Opacity * 255));
      FBmp.Draw(FCanvas, FRect.Left, FRect.Top, False);
    end;
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
begin
  FillBackground(ARect, AFill, TyUniformCorners(ARadiusLogical));
end;

procedure TTyPainter.FillBackground(const ARect: TRect; const AFill: TTyFill; const ACorners: TTyCorners);
var
  r: Integer;
  opts: TRoundRectangleOptions;
  px: TBGRAPixel;
  p1f, p2f: TPointF;
  grad: TBGRAGradientScanner;
begin
  if FBmp = nil then Exit;
  r := ACorners.TL;
  if ACorners.TR > r then r := ACorners.TR;
  if ACorners.BR > r then r := ACorners.BR;
  if ACorners.BL > r then r := ACorners.BL;
  r := Scale(r);
  opts := [];
  if ACorners.TL <= 0 then Include(opts, rrTopLeftSquare);
  if ACorners.TR <= 0 then Include(opts, rrTopRightSquare);
  if ACorners.BR <= 0 then Include(opts, rrBottomRightSquare);
  if ACorners.BL <= 0 then Include(opts, rrBottomLeftSquare);
  case AFill.Kind of
    tfkSolid:
      begin
        px := TyColorToBGRA(AFill.Color);
        if r <= 0 then
          FBmp.FillRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, px, dmDrawWithTransparency)
        else
          FBmp.FillRoundRectAntialias(ARect.Left, ARect.Top, ARect.Right - 1, ARect.Bottom - 1, r, r, px, opts);
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
            FBmp.FillRoundRectAntialias(ARect.Left, ARect.Top, ARect.Right - 1, ARect.Bottom - 1, r, r, grad, opts + [rrDefault]);
        finally
          grad.Free;
        end;
      end;
    tfkNineSlice: NineSlice(ARect, AFill.ImagePath, AFill.SliceInsets);
    tfkImage: DrawImageFill(ARect, AFill.ImagePath, AFill.ImageMode, AFill.Blur);
  end;
end;

procedure TTyPainter.StrokeBorder(const ARect: TRect; ARadiusLogical, AWidthLogical: Integer; AColor: TTyColor);
begin
  StrokeBorder(ARect, TyUniformCorners(ARadiusLogical), AWidthLogical, AColor);
end;

procedure TTyPainter.StrokeBorder(const ARect: TRect; const ACorners: TTyCorners; AWidthLogical: Integer; AColor: TTyColor);
var
  w, r: Integer;
  opts: TRoundRectangleOptions;
  half: Single;
  px: TBGRAPixel;
  l, t, rr, b: Single;
begin
  if FBmp = nil then Exit;
  w := Scale(AWidthLogical);
  if w <= 0 then Exit;
  r := ACorners.TL;
  if ACorners.TR > r then r := ACorners.TR;
  if ACorners.BR > r then r := ACorners.BR;
  if ACorners.BL > r then r := ACorners.BL;
  r := Scale(r);
  opts := [];
  if ACorners.TL <= 0 then Include(opts, rrTopLeftSquare);
  if ACorners.TR <= 0 then Include(opts, rrTopRightSquare);
  if ACorners.BR <= 0 then Include(opts, rrBottomRightSquare);
  if ACorners.BL <= 0 then Include(opts, rrBottomLeftSquare);
  px := TyColorToBGRA(AColor);
  half := w / 2;
  l := ARect.Left + half;
  t := ARect.Top + half;
  rr := ARect.Right - 1 - half;
  b := ARect.Bottom - 1 - half;
  if r <= 0 then
    FBmp.RectangleAntialias(l, t, rr, b, px, w)
  else
    FBmp.RoundRectAntialias(l, t, rr, b, r, r, px, w, opts);
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
begin
  if FBmp = nil then
    Exit;
  px := TyColorToBGRA(AColor);
  TyConfigureTextFont(FBmp, AFontName, AFontSizeLogical, AWeight, FPPI);
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
  style := Default(TTextStyle);
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
    tgArrowLeft:
      begin
        FBmp.DrawLineAntialias(r, cy, l, cy, px, th, True);
        FBmp.DrawPolyLineAntialias([PointF(l + w * 0.35, t + h * 0.25),
          PointF(l, cy), PointF(l + w * 0.35, b - h * 0.25)], px, th);
      end;
    tgArrowRight:
      begin
        FBmp.DrawLineAntialias(l, cy, r, cy, px, th, True);
        FBmp.DrawPolyLineAntialias([PointF(r - w * 0.35, t + h * 0.25),
          PointF(r, cy), PointF(r - w * 0.35, b - h * 0.25)], px, th);
      end;
  end;
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

procedure TTyPainter.FillGlass(const ARect: TRect; ASharp, AGlass: TBGRABitmap;
  const ASrcOffset: TPoint; const ATint: TTyColor; const ACorners: TTyCorners);
{ Frosted glass behind a control. First lay the SHARP backdrop slice across the
  whole rect so the corners (outside the rounded shape) read as the same photo the
  form shows — seamless, no stray solid corner. Then overlay the BLURRED slice +
  tint, round-clipped to the control's corners, as the glass pane itself. Slices
  are clamped so a control partly off the backdrop keeps the underlying fill. }
var
  w, h, ovL, ovT, ovR, ovB, r: Integer;
  opts: TRoundRectangleOptions;
  part, temp, mask: TBGRABitmap;
  oldClip: TRect;
begin
  if (FBmp = nil) or (AGlass = nil) then Exit;
  w := ARect.Right - ARect.Left;
  h := ARect.Bottom - ARect.Top;
  if (w <= 0) or (h <= 0) then Exit;
  ovL := ASrcOffset.X; if ovL < 0 then ovL := 0;
  ovT := ASrcOffset.Y; if ovT < 0 then ovT := 0;
  ovR := ASrcOffset.X + w; if ovR > AGlass.Width then ovR := AGlass.Width;
  ovB := ASrcOffset.Y + h; if ovB > AGlass.Height then ovB := AGlass.Height;
  if (ovR <= ovL) or (ovB <= ovT) then Exit;  // control entirely off the backdrop
  // 1. Sharp slice over the whole rect -> the corners blend into the form's photo.
  if ASharp <> nil then
  begin
    oldClip := FBmp.ClipRect;
    FBmp.ClipRect := ARect;
    try
      part := ASharp.GetPart(Rect(ovL, ovT, ovR, ovB)) as TBGRABitmap;
      try
        FBmp.PutImage(ARect.Left + (ovL - ASrcOffset.X),
                      ARect.Top  + (ovT - ASrcOffset.Y), part, dmSet);
      finally
        part.Free;
      end;
    finally
      FBmp.ClipRect := oldClip;
    end;
  end;
  // 2. Blurred slice + tint, round-clipped, over the centre.
  temp := TBGRABitmap.Create(w, h, BGRAPixelTransparent);
  try
    part := AGlass.GetPart(Rect(ovL, ovT, ovR, ovB)) as TBGRABitmap;
    try
      temp.PutImage(ovL - ASrcOffset.X, ovT - ASrcOffset.Y, part, dmSet);
    finally
      part.Free;
    end;
    if TyAlphaOf(ATint) > 0 then
      temp.FillRect(0, 0, w, h, TyColorToBGRA(ATint), dmDrawWithTransparency);
    // Corner radius + per-corner squaring exactly as FillBackground computes them.
    r := ACorners.TL;
    if ACorners.TR > r then r := ACorners.TR;
    if ACorners.BR > r then r := ACorners.BR;
    if ACorners.BL > r then r := ACorners.BL;
    r := Scale(r);
    if r > 0 then
    begin
      opts := [];
      if ACorners.TL <= 0 then Include(opts, rrTopLeftSquare);
      if ACorners.TR <= 0 then Include(opts, rrTopRightSquare);
      if ACorners.BR <= 0 then Include(opts, rrBottomRightSquare);
      if ACorners.BL <= 0 then Include(opts, rrBottomLeftSquare);
      mask := TBGRABitmap.Create(w, h, BGRAPixelTransparent);
      try
        mask.FillRoundRectAntialias(0, 0, w - 1, h - 1, r, r, BGRAWhite, opts);
        temp.ApplyMask(mask);
      finally
        mask.Free;
      end;
    end;
    FBmp.PutImage(ARect.Left, ARect.Top, temp, dmDrawWithTransparency);
  finally
    temp.Free;
  end;
end;

procedure TTyPainter.EraseRect(const ARect: TRect);
begin
  if FBmp = nil then Exit;
  FBmp.FillRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, BGRA(0,0,0,0), dmSet);
end;

var
  GImgCache: TStringList = nil;  // key 'path|blurDev' -> TBGRABitmap (OwnsObjects)

{ Load (and optionally blur) an image once, cached by path + device-px blur radius.
  The returned bitmap is owned by the cache — callers must not free it. }
function GetCachedImage(const APath: string; ABlurDev: Integer): TBGRABitmap;
var
  key: string;
  idx: Integer;
  raw, bl: TBGRABitmap;
begin
  Result := nil;
  if not FileExists(APath) then Exit;
  if GImgCache = nil then
  begin
    GImgCache := TStringList.Create;
    GImgCache.OwnsObjects := True;
  end;
  key := APath + '|' + IntToStr(ABlurDev);
  idx := GImgCache.IndexOf(key);
  if idx >= 0 then
    Exit(TBGRABitmap(GImgCache.Objects[idx]));
  try
    raw := TBGRABitmap.Create(APath);
  except
    Exit(nil);
  end;
  if ABlurDev > 0 then
  begin
    bl := raw.FilterBlurRadial(ABlurDev, rbFast) as TBGRABitmap;
    raw.Free;
    raw := bl;
  end;
  GImgCache.AddObject(key, raw);
  Result := raw;
end;

procedure TTyPainter.DrawImageFill(const ARect: TRect; const AImagePath: string;
  AMode: TTyImageMode; ABlurLogical: Integer);
var
  src: TBGRABitmap;
  iw, ih, dw, dh, sw, sh, ox, oy: Integer;
  sc, scW, scH: Double;
  oldClip: TRect;
begin
  if FBmp = nil then Exit;
  src := GetCachedImage(AImagePath, Scale(ABlurLogical));
  if src = nil then Exit;
  iw := src.Width; ih := src.Height;
  dw := ARect.Right - ARect.Left; dh := ARect.Bottom - ARect.Top;
  if (iw <= 0) or (ih <= 0) or (dw <= 0) or (dh <= 0) then Exit;
  oldClip := FBmp.ClipRect;
  FBmp.ClipRect := ARect;
  try
    case AMode of
      timStretch:
        FBmp.StretchPutImage(ARect, src, dmDrawWithTransparency);
      timCenter:
        FBmp.PutImage(ARect.Left + (dw - iw) div 2, ARect.Top + (dh - ih) div 2,
          src, dmDrawWithTransparency);
      timCover:
        begin
          scW := dw / iw; scH := dh / ih;
          if scW > scH then sc := scW else sc := scH;
          sw := Round(iw * sc); sh := Round(ih * sc);
          ox := ARect.Left + (dw - sw) div 2;
          oy := ARect.Top + (dh - sh) div 2;
          FBmp.StretchPutImage(Rect(ox, oy, ox + sw, oy + sh), src, dmDrawWithTransparency);
        end;
    end;
  finally
    FBmp.ClipRect := oldClip;
  end;
end;

initialization
  // Default: leave font name empty when no font-family is themed (unchanged
  // behavior). The controller opts into a concrete system-font fallback for
  // real GUI apps; headless contexts (tests) keep this empty for determinism.
  TyFallbackFontName := '';

finalization
  FreeAndNil(GImgCache);  // OwnsObjects frees the cached bitmaps

end.
