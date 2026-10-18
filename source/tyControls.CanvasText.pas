unit tyControls.CanvasText;

{$mode objfpc}{$H+}

{ TEXT ON AN LCL CANVAS, IN THE INK'S POLARITY (#91).

  BGRABitmap's system renderer draws every straight run white on black on an LCL bitmap and
  uses the result as the mask, whatever the colour of the ink. Where the canvas smooths or
  hints by polarity, that mask is the weight of LIGHT text, and dark text drawn from it
  carries it. macOS font smoothing is the case that shows: it thickens light-on-dark far more
  than dark-on-light. Measured on macOS 15.3, PingFang SC 13 px, against LCL's own text in
  the same window: the same line white on black and inverted laid down 25% more ink than
  black on white, and BGRA's dark text on a transparent surface 26% more than LCL's -- heavy
  and soft on a 1x screen.

  This renderer draws the run on the same kind of bitmap with the same canvas call BGRA uses
  (BitmapTextOut, or BitmapTextRect for a mnemonic or a right-to-left run), in the ink's
  polarity: dark ink black on white, light ink white on black -- the weight the system gives
  that ink. The coverage is laid down in the ink colour, one grey per pixel. It is the rule
  tyControls.Painter's Windows renderer follows for the same reason (ClearType weighs the two
  polarities differently too); that one also lays ClearType's subpixels down on opaque
  pixels, which macOS since 10.14 does not draw.

  Installed by TyUseTextRenderer on Cocoa. Nothing in it is Cocoa's, so it compiles
  everywhere and the tests run it on the canvas they have. Rotated, textured and
  self-underlined runs go to BGRA's own path. }

interface

uses
  Classes, SysUtils, Math, Graphics, BGRABitmap, BGRABitmapTypes, BGRAText;

type
  TTyCanvasTextRenderer = class(TLCLFontRenderer)
  protected
    procedure InternalTextOutAngle(ADest: TBGRACustomBitmap; x, y: single;
      AOrientation: integer; sUTF8: string; c: TBGRAPixel; texture: IBGRAScanner;
      align: TAlignment; AShowPrefix: boolean = false; ARightToLeft: boolean = false); override;
  end;

implementation

uses
  BGRAUTF8, BGRAUnicode;

procedure TTyCanvasTextRenderer.InternalTextOutAngle(ADest: TBGRACustomBitmap; x, y: single;
  AOrientation: integer; sUTF8: string; c: TBGRAPixel; texture: IBGRAScanner;
  align: TAlignment; AShowPrefix: boolean; ARightToLeft: boolean);
var
  st: TTextStyle;
  sz: TSize;
  ofsX: Single;
  ox, oy, mx, my, w, h, px, py, dy, cov, a: Integer;
  tmp: TBitmap;
  shot: TBGRABitmap;
  row: PBGRAPixel;
  ink: TBGRAPixel;
  lightInk, plain: Boolean;
begin
  if sUTF8 = '' then Exit;
  if (AOrientation mod 3600 <> 0) or (texture <> nil) or FOwnUnderline then
  begin
    inherited InternalTextOutAngle(ADest, x, y, AOrientation, sUTF8, c, texture, align,
      AShowPrefix, ARightToLeft);
    Exit;
  end;
  if c.alpha = 0 then Exit;
  {$IF defined(LINUX) or defined(DARWIN)}
  { BGRA's hint to the system about the run's direction (TBGRASystemFontRenderer) }
  case GetFirstStrongBidiClassUTF8(sUTF8) of
    ubcRightToLeft, ubcArabicLetter:
      if not ARightToLeft then sUTF8 := UnicodeCharToUTF8(UNICODE_LEFT_TO_RIGHT_MARK) + sUTF8;
  else
    if ARightToLeft then sUTF8 := UnicodeCharToUTF8(UNICODE_RIGHT_TO_LEFT_MARK) + sUTF8;
  end;
  {$ENDIF}
  lightInk := (c.red * 30 + c.green * 59 + c.blue * 11) div 100 > 128;
  UpdateFont;
  { BGRA's run style (BGRADefaultTextOutStyle, which the unit does not export) }
  FillChar(st, SizeOf(st), 0);
  st.SingleLine := True;
  st.Alignment := taLeftJustify;
  st.Layout := tlTop;
  st.RightToLeft := ARightToLeft;
  st.ShowPrefix := AShowPrefix;
  { BGRA sizes a plain run as it measures one (TextSize), a mnemonic or right-to-left one
    by its style }
  plain := not AShowPrefix and not ARightToLeft;
  if plain then
    sz := InternalTextSize(sUTF8, False)
  else
    sz := InternalTextSizeStyle(sUTF8, st, MaxLongint);
  if (sz.cx <= 0) or (sz.cy <= 0) then Exit;
  case align of
    taCenter: ofsX := sz.cx / 2;
    taRightJustify: ofsX := sz.cx;
  else
    ofsX := 0;
  end;
  { Rounded half up, where BGRA's own path puts a run. }
  ox := Floor(x - ofsX + 0.5);
  oy := Floor(y + 0.5);
  { Room for what overhangs the line box: an italic's lean, and a fallback font's taller
    glyphs -- a CJK run in a Latin UI font is drawn in one whose descent the line box of
    the first does not hold (BGRA's one pixel of margin cut them off). }
  mx := sz.cy div 2 + 2;
  my := sz.cy div 4 + 2;
  w := sz.cx + 2 * mx;
  h := sz.cy + 2 * my;
  tmp := TBitmap.Create;
  shot := nil;
  try
    tmp.Width := w;
    tmp.Height := h;
    if lightInk then
      BitmapFillRect(tmp, Rect(0, 0, w, h), clBlack)
    else
      BitmapFillRect(tmp, Rect(0, 0, w, h), clWhite);
    tmp.Canvas.Font := FFont;
    tmp.Canvas.Font.Orientation := 0;
    tmp.Canvas.Font.Height := FFont.Height;
    if lightInk then tmp.Canvas.Font.Color := clWhite else tmp.Canvas.Font.Color := clBlack;
    if plain then
      BitmapTextOut(tmp, Point(mx, my), sUTF8)
    else
      BitmapTextRect(tmp, Rect(mx, my, w, h), Point(mx, my), sUTF8, st);
    shot := TBGRABitmap.Create(tmp, False);
    ink := c;
    for py := 0 to h - 1 do
    begin
      dy := oy - my + py;
      if (dy < ADest.ClipRect.Top) or (dy >= ADest.ClipRect.Bottom) then Continue;
      row := shot.ScanLine[py];
      for px := 0 to w - 1 do
      begin
        cov := (row[px].red + row[px].green + row[px].blue) div 3;
        if not lightInk then cov := 255 - cov;
        if cov > 0 then
        begin
          a := cov * c.alpha div 255;
          if a > 0 then
          begin
            ink.alpha := a;
            ADest.FastBlendPixel(ox - mx + px, dy, ink);   // clipped against ClipRect there
          end;
        end;
      end;
    end;
  finally
    shot.Free;
    tmp.Free;
  end;
end;

end.
