unit tyControls.Painter;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Graphics, LCLType, LazUTF8, BGRABitmap, BGRABitmapTypes,
  BGRAGradientScanner, BGRACanvas2D,
  FPReadJPEG, FPReadPNG, FPReadBMP,  // register FPImage readers so url() jpg/png/bmp load
  tyControls.Types;

type
  TTyGlyphKind = (tgClose, tgMinimize, tgMaximize, tgRestore, tgCheck, tgCheckIndeterminate,
    tgRadioDot, tgChevronDown, tgChevronRight, tgArrowUp, tgArrowDown, tgArrowLeft, tgArrowRight,
    tgDialogLauncher,
    // Semantic status marks (TTyAlert / TTyNotification). Drawn in ONE ink like every glyph
    // here, so they are outlines (ring + mark), not AntD's filled discs — a filled disc needs
    // two colours and would not tint with the caller's single AColor.
    tgInfo, tgSuccess, tgWarning, tgError);

  TTyPainter = class
  private
    FBmp: TBGRABitmap;
    FCanvas: TCanvas;
    FRect: TRect;
    FPPI: Integer;
    FOwnsBmp: Boolean;
    procedure GradientEndpoints(const ARect: TRect; AAngleDeg: Single; out P1, P2: TPointF);
    procedure BlitRegion(ASrc: TBGRABitmap; const ASrcR, ADstR: TRect; ATile: Boolean = False);
    {$IF defined(LINUX) or defined(DARWIN)}
    procedure DrawTextSupersampled(const ARect: TRect; const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AColor: TTyColor; AHAlign: TAlignment; AVAlign: TTextLayout);
    {$ENDIF}
  public
    Opacity: Single;
    OpacityBase: TTyColor;   // when Opacity<1, dim TOWARD this opaque colour (0 = old alpha-reduce)
    procedure BeginPaint(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { 画到**调用方提供**的位图上,EndPaint 只 blit 不释放,也不预先清空。
      给需要跨帧复用表面的调用方用(网格的滚动脏区重绘)。 }
    procedure BeginPaintOn(ACanvas: TCanvas; const ARect: TRect; APPI: Integer;
      ABmp: TBGRABitmap);
    procedure EndPaint;
    function Scale(ALogical: Integer): Integer;
    function Unscale(ADevice: Integer): Integer;
    function MeasureText(const AText, AFontName: string; AFontSizeLogical, AWeight: Integer): TSize;
    procedure FillBackground(const ARect: TRect; const AFill: TTyFill; ARadiusLogical: Integer); overload;
    procedure FillBackground(const ARect: TRect; const AFill: TTyFill; const ACorners: TTyCorners); overload;
    procedure StrokeBorder(const ARect: TRect; ARadiusLogical, AWidthLogical: Integer; AColor: TTyColor); overload;
    procedure StrokeBorder(const ARect: TRect; const ACorners: TTyCorners; AWidthLogical: Integer; AColor: TTyColor); overload;
    { v3/B2: a crisp, square, two-tone 3D bevel. The top+left edges get ATLColor and the
      bottom+right get ABRColor (light/dark for outset; swapped for inset). Corners: the
      light L-shape wins the shared corners. AWidthLogical is the (logical-px) edge width. }
    procedure DrawEdge(const ARect: TRect; AWidthLogical: Integer; ATLColor, ABRColor: TTyColor);
    { v3/C5: blit a pre-rendered glyph bitmap centered in ARect (used for icon-font glyph
      overrides; a nil/empty bitmap draws nothing). }
    procedure DrawGlyphBitmap(const ARect: TRect; ABmp: TBGRABitmap);
    procedure DropShadow(const ARect: TRect; ARadiusLogical: Integer; AColor: TTyColor; ABlurLogical: Integer; const AOffsetLogical: TPoint);
    procedure DrawText(const ARect: TRect; const AText, AFontName: string; AFontSizeLogical, AWeight: Integer; AColor: TTyColor; AHAlign: TAlignment; AVAlign: TTextLayout; AEllipsis: Boolean; AMnemonicPos: Integer = 0; ASmallCrisp: Boolean = False);
    procedure DrawGlyph(const ARect: TRect; AGlyph: TTyGlyphKind; AColor: TTyColor; AThicknessLogical: Integer; APadLogical: Integer = 4);
    { A FIXED-SIZE dropdown chevron (a shallow wide "v"), centered in AZoneRect and NOT
      stretched to the zone height — so a tall combo/button keeps a small clean chevron
      instead of a big ugly V. ASizeLogical is the chevron width (height ≈ 0.55x). }
    procedure DrawDropChevron(const AZoneRect: TRect; AColor: TTyColor; ASizeLogical: Integer = 9);
    procedure NineSlice(const ARect: TRect; const AImagePath: string; const AInsets: TRect; ATile: Boolean = False);
    procedure DrawImageFill(const ARect: TRect; const AImagePath: string; AMode: TTyImageMode; ABlurLogical: Integer);
    procedure FillImageSlice(const ARect: TRect; ASrc: TBGRABitmap; const ASrcOffset: TPoint);
    procedure FillGlass(const ARect: TRect; AGlass: TBGRABitmap; const ASrcOffset: TPoint; const ATint: TTyColor; const ACorners: TTyCorners);
    { Paint AColor into the area OUTSIDE the rounded rectangle (the 4 corner gaps).
      Used to re-establish a clean parent background in a windowed control's corners
      after a drop shadow bled into them. No-op when there are no rounded corners. }
    procedure FillCornerGaps(const ARect: TRect; const ACorners: TTyCorners; AColor: TTyColor);
    procedure EraseRect(const ARect: TRect);
    property Bitmap: TBGRABitmap read FBmp;
    { 五角星:10 个内外交替的顶点,第一个顶点在正上方。只描路径、不填不描边 ——
      填法交给调用方(整颗填 / 只描边 / 裁一半做半星)。
      **抽出来是为了让评分控件与网格的星级单元格用同一份几何** ——
      两边各画一套的话,同一个值在两处会长得不一样。 }
    procedure StarPath(ACx, ACy, AOuter, AInner: Double);
    { 在 ARect 内画一颗星:AFilled 为真则实心填 AColor,否则只用 AColor 描边。 }
    procedure DrawStar(const ARect: TRect; AColor: TTyColor; AFilled: Boolean);
    { 本次绘制的 PPI。调用方要自己往别的位图上排文字时(网格的单元格文本缓存)
      必须用同一个 PPI 配字体,否则缓存出来的字号与直接画的不一致。 }
    property PPI: Integer read FPPI;
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
{ Greedy line wrap that understands both scripts. Western words break at spaces (runs
  collapse to one space); CJK text carries no spaces, so each ideograph / kana / hangul
  syllable is its own break opportunity — without this a Chinese run is one unbreakable
  word and overflows a narrow box instead of wrapping. Walks UTF-8 by codepoint so a
  multi-byte glyph is never split. ACanvas must already carry the target font so TextWidth
  measures the drawn glyphs. Shared by TTyLabel and TTyNotification. }
procedure TyWrapTextCJK(const AText: string; AMaxWidthPx: Integer;
  ACanvas: TCanvas; ALines: TStrings);
{ The prefix the ellipsis fitter uses when it has narrowed the text to ACharCount CHARACTERS.
  A named function purely so the invariant is testable: the version this replaced shortened by
  one BYTE, which cuts a three-byte CJK character in half. The headless BGRA path silently
  swallows the stray byte, so a pixel comparison cannot see it -- the real GUI draws a
  replacement glyph, which is what the maintainer saw. Assert the string, not the pixels. }
function TyEllipsisPrefix(const AText: string; ACharCount: Integer): string;
{ Clamp a device-px corner radius to half the shorter side of a WxH rect, so an oversized
  "pill" radius (e.g. border-radius:100 on a short progress track) renders as a rounded pill
  instead of overshooting the corner arcs into a pointed lens. Exposed for tests. }
function TyClampRadiusPx(ARadiusPx, AWidthPx, AHeightPx: Integer): Integer;

var
  // Concrete font used when a style/theme provides no font-family.
  // When AFontName='' and this is non-empty, it is passed to BGRA instead of ''.
  // ''=leave empty (default; unchanged behavior). The controller may set this
  // from the real system font for GUI apps -- see tyControls.Controller. Passing
  // an empty name to BGRA triggers a fallback path that drops the last glyph and
  // mis-advances text in the real GUI, so substituting a concrete name fixes it.
  TyFallbackFontName: string;

  // Fallback font size (logical px) used when a resolved style has font-size <= 0 — i.e.
  // a theme rule that forgot to set font-size (which would otherwise render size-0 = INVISIBLE
  // text, as green.tycss's TyRibbonGroup did). Applied at the single text chokepoint
  // (TyConfigureTextFont), so every draw + measure gets a visible size without each control
  // guarding or each theme repeating font-size on every rule. Apps may lower/raise it.
  TyFallbackFontSize: Integer = 13;

implementation

function TyEffectiveFontName(const AName: string): string;
begin
  if (AName = '') and (TyFallbackFontName <> '') then
    Result := TyFallbackFontName
  else
    Result := AName;
end;

{ Wraps ONE authored line (no CR/LF inside). ABase is ALines.Count at entry, so the
  "never return nothing" guard below is about THIS segment and not about lines an earlier
  segment already contributed. }
function TyEllipsisPrefix(const AText: string; ACharCount: Integer): string;
begin
  if ACharCount <= 0 then Exit('');
  Result := UTF8Copy(AText, 1, ACharCount);
end;

procedure TyWrapSegmentCJK(const AText: string; AMaxWidthPx: Integer;
  ACanvas: TCanvas; ALines: TStrings; ABase: Integer);
var
  cur, buf: string;
  bufSpaceBefore, pendingSpace, firstAtom: Boolean;
  i, cpLen: Integer;
  cp: Cardinal;
  s: string;

  { Decode one UTF-8 codepoint at 1-based p; returns its byte length. Malformed
    lead/truncated tail degrades to a single raw byte so we never loop forever. }
  function DecodeCP(p: Integer; out AValue: Cardinal): Integer;
  var k, len: Integer; bb: Byte;
  begin
    bb := Byte(AText[p]);
    if bb < $80 then begin AValue := bb; Exit(1); end
    else if (bb and $E0) = $C0 then begin AValue := bb and $1F; len := 2; end
    else if (bb and $F0) = $E0 then begin AValue := bb and $0F; len := 3; end
    else if (bb and $F8) = $F0 then begin AValue := bb and $07; len := 4; end
    else begin AValue := bb; Exit(1); end;
    if p + len - 1 > Length(AText) then begin AValue := bb; Exit(1); end;
    for k := 1 to len - 1 do
      AValue := (AValue shl 6) or (Byte(AText[p + k]) and $3F);
    Result := len;
  end;

  { A codepoint that participates in inter-character line breaking: Han, kana,
    hangul, bopomofo, CJK symbols/punctuation and the fullwidth forms. }
  function IsCJKChar(AValue: Cardinal): Boolean;
  begin
    Result :=
      ((AValue >= $1100) and (AValue <= $11FF)) or   // Hangul Jamo
      ((AValue >= $2E80) and (AValue <= $A4CF)) or   // radicals..CJK punct..kana..Ext-A..Yi
      ((AValue >= $AC00) and (AValue <= $D7A3)) or   // Hangul syllables
      ((AValue >= $F900) and (AValue <= $FAFF)) or   // CJK compat ideographs
      ((AValue >= $FE30) and (AValue <= $FE4F)) or   // CJK compat forms
      ((AValue >= $FF00) and (AValue <= $FF60)) or   // fullwidth forms
      ((AValue >= $FFE0) and (AValue <= $FFE6)) or   // fullwidth signs
      ((AValue >= $20000) and (AValue <= $2FA1F));   // CJK Ext B-F (SMP)
  end;

  { Greedily append one atom (a western word or a single CJK glyph) to the
    current line, starting a new line when it would overflow AMaxWidthPx. }
  procedure PlaceAtom(const AAtom: string; ASpaceBefore: Boolean);
  var t: string;
  begin
    if cur = '' then
      t := AAtom
    else if ASpaceBefore then
      t := cur + ' ' + AAtom
    else
      t := cur + AAtom;
    if (AMaxWidthPx > 0) and (cur <> '') and (ACanvas.TextWidth(t) > AMaxWidthPx) then
    begin
      ALines.Add(cur);
      cur := AAtom;
    end
    else
      cur := t;
  end;

  procedure FlushBuf;
  begin
    if buf <> '' then
    begin
      PlaceAtom(buf, bufSpaceBefore);
      buf := '';
    end;
  end;

begin
  { NO Clear here. This is called once per authored line now, so clearing would wipe the
    segments already wrapped -- which is exactly what it did: every caption came out as its
    LAST line only. Emptying the list is the public entry point's job, once. }
  if AText = '' then
  begin
    ALines.Add('');
    Exit;
  end;
  cur := '';
  buf := '';
  bufSpaceBefore := False;
  pendingSpace := False;
  firstAtom := True;
  i := 1;
  while i <= Length(AText) do
  begin
    cpLen := DecodeCP(i, cp);
    s := Copy(AText, i, cpLen);
    Inc(i, cpLen);
    if (cp = Ord(' ')) or (cp = 9) then          // ASCII space / tab: a break point
    begin
      FlushBuf;
      pendingSpace := True;
    end
    else if IsCJKChar(cp) then                   // each CJK glyph is its own atom
    begin
      FlushBuf;
      PlaceAtom(s, pendingSpace and not firstAtom);
      pendingSpace := False;
      firstAtom := False;
    end
    else                                         // grow the current western word
    begin
      if buf = '' then
        bufSpaceBefore := pendingSpace and not firstAtom;
      buf := buf + s;
      pendingSpace := False;
      firstAtom := False;
    end;
  end;
  FlushBuf;
  if cur <> '' then
    ALines.Add(cur);
  if ALines.Count = ABase then
    ALines.Add(AText);
end;

{ Greedy CJK-aware wrap of a whole caption.

  Authored line breaks come FIRST. The wrapper only ever knew about spaces and CJK codepoints,
  so a caption written with an explicit #13#10 in it came out as one run: TTyLabel with
  WordWrap on silently swallowed every line the author put there. TTyNotification looked
  correct only because its caller split the message on CR/LF before calling in -- doing it
  here makes that pre-split redundant rather than load-bearing, and fixes every other caller
  at the same time.

  An empty segment is kept as an empty line: a blank line between paragraphs is content. }
procedure TyWrapTextCJK(const AText: string; AMaxWidthPx: Integer;
  ACanvas: TCanvas; ALines: TStrings);
var
  seg: TStringList;
  i: Integer;
begin
  ALines.Clear;
  if Pos(#10, AText) + Pos(#13, AText) = 0 then
  begin
    TyWrapSegmentCJK(AText, AMaxWidthPx, ACanvas, ALines, ALines.Count);
    Exit;
  end;
  seg := TStringList.Create;
  try
    seg.Text := AText;          // splits on CR, LF and CRLF alike
    for i := 0 to seg.Count - 1 do
      if seg[i] = '' then
        ALines.Add('')
      else
        TyWrapSegmentCJK(seg[i], AMaxWidthPx, ACanvas, ALines, ALines.Count);
  finally
    seg.Free;
  end;
end;

procedure TyConfigureTextFont(ABmp: TBGRABitmap; const AFontName: string;
  AFontSizeLogical, AWeight, APPI: Integer);
begin
  // A missing font-size (0) would render invisible text; fall back to a visible default.
  if AFontSizeLogical <= 0 then AFontSizeLogical := TyFallbackFontSize;
  ABmp.FontName := TyEffectiveFontName(AFontName);
  ABmp.FontHeight := MulDiv(Round(AFontSizeLogical * 96 / 72), APPI, 96);
  // Text quality is a WIDGETSET choice, not a platform one. BGRABitmap's fqFineAntialiasing
  // renders BLANK on the Qt/GTK LCL font renderer (its fine-AA path expects the Win32/Cocoa
  // system renderer; diagnostic on Windows+Qt6: fqFine=0 px vs fqSystemClearType=621). Use the
  // widgetset's native text (fqSystemClearType) there; keep crisp fqFineAntialiasing on Win32/Cocoa.
  {$IF DEFINED(LCLQt5) or DEFINED(LCLQt6) or DEFINED(LCLGtk2) or DEFINED(LCLGtk3)}
  ABmp.FontQuality := fqSystemClearType;
  {$ELSE}
  ABmp.FontQuality := fqFineAntialiasing;
  {$ENDIF}
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
  OpacityBase := 0;   // 0 alpha = "not set" -> EndPaint uses the old alpha-reduce path
  FBmp := TBGRABitmap.Create(ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
  FOwnsBmp := True;
  FBmp.Fill(BGRAPixelTransparent);
end;

procedure TTyPainter.BeginPaintOn(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer; ABmp: TBGRABitmap);
begin
  FCanvas := ACanvas;
  FRect := ARect;
  if APPI <= 0 then FPPI := 96 else FPPI := APPI;
  Opacity := 1.0;
  OpacityBase := 0;
  FBmp := ABmp;
  { **不清空** —— 上一帧的像素正是要复用的东西;清哪一块由调用方决定。 }
  FOwnsBmp := False;
end;

procedure TTyPainter.EndPaint;
var
  baseBmp: TBGRABitmap;
  c: TBGRAPixel;
begin
  if Assigned(FBmp) then
  begin
    if Assigned(FCanvas) then
    begin
      if (Opacity < 1.0) and (TyAlphaOf(OpacityBase) > 0) then
      begin
        // Dim the control TOWARD an opaque base colour (its themed parent/surface background)
        // rather than reducing the whole bitmap's alpha. A disabled control on the Win10 DWM
        // sheet-of-glass window would otherwise go semi-transparent and the glass shows through
        // (text looks blurry, background washes white, turns fully white on deactivate). Lay the
        // OPAQUE base onto the canvas first, then draw the faded content over it with the SAME
        // (non-gamma) blend as the normal path — so the dimmed pixels match the old look but the
        // result stays alpha-255, and untouched areas show the opaque base, never glass.
        c := TyColorToBGRA(OpacityBase);
        c.alpha := 255;
        baseBmp := TBGRABitmap.Create(FBmp.Width, FBmp.Height, c);
        try
          baseBmp.Draw(FCanvas, FRect.Left, FRect.Top, True);
        finally
          baseBmp.Free;
        end;
        FBmp.ApplyGlobalOpacity(Round(Opacity * 255));
        FBmp.Draw(FCanvas, FRect.Left, FRect.Top, False);
        if FOwnsBmp then FreeAndNil(FBmp) else FBmp := nil;
        Exit;
      end;
      if Opacity < 1.0 then
        FBmp.ApplyGlobalOpacity(Round(Opacity * 255));
      FBmp.Draw(FCanvas, FRect.Left, FRect.Top, False);
    end;
    if FOwnsBmp then FreeAndNil(FBmp) else FBmp := nil;
  end;
end;

function TTyPainter.Scale(ALogical: Integer): Integer;
begin
  Result := MulDiv(ALogical, FPPI, 96);
end;

function TTyPainter.Unscale(ADevice: Integer): Integer;
begin
  // Inverse of Scale: device px -> logical px. Used when a caller has device-space
  // geometry but must hand a LOGICAL radius to FillBackground (which Scales it again).
  Result := MulDiv(ADevice, 96, FPPI);
end;

function TTyPainter.MeasureText(const AText, AFontName: string; AFontSizeLogical, AWeight: Integer): TSize;
begin
  Result := Size(0, 0);
  if FBmp = nil then Exit;
  // Same font configuration as DrawText, so measured size matches drawn glyphs.
  TyConfigureTextFont(FBmp, AFontName, AFontSizeLogical, AWeight, FPPI);
  Result := FBmp.TextSize(AText);
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

{ Clamp a device-px corner radius to half the shorter side of its target rect. A large radius
  (e.g. a "pill" progress bar with border-radius:100 on an 18px-tall track) would otherwise
  overshoot the corner arcs into a pointed LENS shape; clamping makes it a proper rounded pill. }
function TyClampRadiusPx(ARadiusPx, AWidthPx, AHeightPx: Integer): Integer;
var m: Integer;
begin
  Result := ARadiusPx;
  if Result < 0 then Result := 0;
  m := AWidthPx;
  if AHeightPx < m then m := AHeightPx;
  m := m div 2;
  if Result > m then Result := m;
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
  multi: TBGRAMultiGradient;
  cols: array of TBGRAPixel;
  poss: array of Single;
  i: Integer;
begin
  if FBmp = nil then Exit;
  r := ACorners.TL;
  if ACorners.TR > r then r := ACorners.TR;
  if ACorners.BR > r then r := ACorners.BR;
  if ACorners.BL > r then r := ACorners.BL;
  r := Scale(r);
  r := TyClampRadiusPx(r, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
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
        if Length(AFill.GradStops) > 2 then
        begin
          // v3/B1 multi-stop: build a BGRA multi-gradient from the N stops. (2-stop keeps the
          // exact 2-colour scanner below, so existing themes / the golden are byte-identical.)
          SetLength(cols, Length(AFill.GradStops));
          SetLength(poss, Length(AFill.GradStops));
          for i := 0 to High(AFill.GradStops) do
          begin
            cols[i] := TyColorToBGRA(AFill.GradStops[i].Color);
            poss[i] := AFill.GradStops[i].Pos;
          end;
          multi := TBGRAMultiGradient.Create(cols, poss, False, False);
          grad := TBGRAGradientScanner.Create(multi, gtLinear, p1f, p2f);
          try
            if r <= 0 then
              FBmp.FillRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, grad, dmDrawWithTransparency, daNearestNeighbor)
            else
              FBmp.FillRoundRectAntialias(ARect.Left, ARect.Top, ARect.Right - 1, ARect.Bottom - 1, r, r, grad, opts + [rrDefault]);
          finally
            grad.Free;
            multi.Free;
          end;
        end
        else
        begin
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
      end;
    tfkNineSlice: NineSlice(ARect, AFill.ImagePath, AFill.SliceInsets, AFill.SliceRepeat);
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
  r := TyClampRadiusPx(r, Round(rr - l), Round(b - t));   // hug the fill's clamped corner (no lens)
  if r <= 0 then
    FBmp.RectangleAntialias(l, t, rr, b, px, w)
  else
    FBmp.RoundRectAntialias(l, t, rr, b, r, r, px, w, opts);
end;

procedure TTyPainter.DrawEdge(const ARect: TRect; AWidthLogical: Integer; ATLColor, ABRColor: TTyColor);
var w: Integer; tl, br: TBGRAPixel;
begin
  if FBmp = nil then Exit;
  w := Scale(AWidthLogical);
  if w <= 0 then Exit;
  tl := TyColorToBGRA(ATLColor);
  br := TyColorToBGRA(ABRColor);
  // Bottom + right edges first (the dark side of a raised bevel)...
  FBmp.FillRect(ARect.Left, ARect.Bottom - w, ARect.Right, ARect.Bottom, br, dmDrawWithTransparency);
  FBmp.FillRect(ARect.Right - w, ARect.Top, ARect.Right, ARect.Bottom, br, dmDrawWithTransparency);
  // ...then top + left on top, so the light L wins the shared (TR/BL) corners.
  FBmp.FillRect(ARect.Left, ARect.Top, ARect.Right, ARect.Top + w, tl, dmDrawWithTransparency);
  FBmp.FillRect(ARect.Left, ARect.Top, ARect.Left + w, ARect.Bottom, tl, dmDrawWithTransparency);
end;

procedure TTyPainter.DrawGlyphBitmap(const ARect: TRect; ABmp: TBGRABitmap);
var x, y: Integer;
begin
  if (FBmp = nil) or (ABmp = nil) then Exit;
  x := ARect.Left + ((ARect.Right - ARect.Left) - ABmp.Width) div 2;
  y := ARect.Top + ((ARect.Bottom - ARect.Top) - ABmp.Height) div 2;
  FBmp.PutImage(x, y, ABmp, dmDrawWithTransparency);
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
  r := TyClampRadiusPx(r, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
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

procedure TTyPainter.StarPath(ACx, ACy, AOuter, AInner: Double);
var
  ctx: TBGRACanvas2D;
  k: Integer;
  ang, rr: Double;
begin
  if FBmp = nil then Exit;
  ctx := FBmp.Canvas2D;
  ctx.beginPath;
  for k := 0 to 9 do
  begin
    if (k mod 2) = 0 then rr := AOuter else rr := AInner;
    { 从正上方(-90 度)起,每个顶点转 36 度,顺时针。 }
    ang := DegToRad(-90 + k * 36);
    if k = 0 then
      ctx.moveTo(ACx + rr * Cos(ang), ACy + rr * Sin(ang))
    else
      ctx.lineTo(ACx + rr * Cos(ang), ACy + rr * Sin(ang));
  end;
  ctx.closePath;
end;

procedure TTyPainter.DrawStar(const ARect: TRect; AColor: TTyColor; AFilled: Boolean);
var
  ctx: TBGRACanvas2D;
  cx, cy, outer: Double;
begin
  if FBmp = nil then Exit;
  outer := Math.Min(ARect.Right - ARect.Left, ARect.Bottom - ARect.Top) / 2;
  if outer < 2 then Exit;
  cx := (ARect.Left + ARect.Right) / 2;
  cy := (ARect.Top + ARect.Bottom) / 2;

  ctx := FBmp.Canvas2D;
  ctx.lineJoin := 'round';
  { 内半径取外半径的一半 —— 与评分控件同一比例。 }
  StarPath(cx, cy, outer, outer * 0.5);
  if AFilled then
  begin
    ctx.fillStyle(TyColorToBGRA(AColor));
    ctx.fill;
  end
  else
  begin
    ctx.lineWidth := Math.Max(1, Scale(1));
    ctx.strokeStyle(TyColorToBGRA(AColor));
    ctx.stroke;
  end;
end;

procedure TTyPainter.DrawText(const ARect: TRect; const AText, AFontName: string; AFontSizeLogical, AWeight: Integer; AColor: TTyColor; AHAlign: TAlignment; AVAlign: TTextLayout; AEllipsis: Boolean; AMnemonicPos: Integer = 0; ASmallCrisp: Boolean = False);
var
  n: Integer;
  style: TTextStyle;
  s: string;
  sz, full: TSize;
  px: TBGRAPixel;
  beforeW, charW, ux, uy, uth: Integer;
begin
  if FBmp = nil then
    Exit;
  {$IF defined(LINUX) or defined(DARWIN)}
  // On Linux/macOS, BGRABitmap's LCL renderer drops fqFineAntialiasing to single-pass
  // fqSystem for text taller than ~13px (bgratext.pas SYSTEM_RENDERER_IS_FINE), so small
  // bold glyphs come out soft/blurry -- unlike Windows, where it always supersamples. For
  // callers that ask for crisp small text (the button badge) we supersample ourselves. Skips
  // the ellipsis/mnemonic features (the badge uses neither); only compiled where it's needed,
  // so Windows/headless keep the exact original path (and the pixel goldens stay byte-identical).
  if ASmallCrisp and not AEllipsis and (AMnemonicPos = 0) then
  begin
    DrawTextSupersampled(ARect, AText, AFontName, AFontSizeLogical, AWeight, AColor, AHAlign, AVAlign);
    Exit;
  end;
  {$ENDIF}
  px := TyColorToBGRA(AColor);
  TyConfigureTextFont(FBmp, AFontName, AFontSizeLogical, AWeight, FPPI);
  s := AText;
  if AEllipsis then
  begin
    { Shorten by one CODEPOINT at a time. Delete(s, Length(s), 1) took one BYTE, which for
      any non-ASCII text cuts a UTF-8 sequence in half: every CJK character is three bytes, so
      an ellipsised Chinese caption ended in a broken sequence and the renderer drew a '?'.
      That is the one path nearly every control's text goes through -- title-bar captions,
      button labels, list rows, tab headers -- so it showed up everywhere at once. }
    n := UTF8Length(s);
    sz := FBmp.TextSize(s);
    while (n > 1) and (sz.cx > (ARect.Right - ARect.Left)) do
    begin
      Dec(n);
      s := TyEllipsisPrefix(AText, n);
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
  // Mnemonic underline: a thin line under the AMnemonicPos-th char (1-based), placed by
  // reusing the same alignment the text was drawn with. Skipped when the text was ellipsis-
  // truncated (s <> AText), so the underline never lands on a '.' or a shifted glyph.
  if (AMnemonicPos >= 1) and (AMnemonicPos <= Length(s)) and (s = AText) then
  begin
    full := FBmp.TextSize(s);
    beforeW := FBmp.TextSize(Copy(s, 1, AMnemonicPos - 1)).cx;
    charW := FBmp.TextSize(Copy(s, AMnemonicPos, 1)).cx;
    case AHAlign of
      taCenter:       ux := ARect.Left + ((ARect.Right - ARect.Left) - full.cx) div 2;
      taRightJustify: ux := ARect.Right - full.cx;
    else
      ux := ARect.Left;
    end;
    Inc(ux, beforeW);
    case AVAlign of
      tlTop:    uy := ARect.Top + full.cy;
      tlBottom: uy := ARect.Bottom;
    else
      uy := ARect.Top + ((ARect.Bottom - ARect.Top) + full.cy) div 2;
    end;
    uth := Scale(1);
    if uth < 1 then uth := 1;
    Dec(uy, uth);
    FBmp.FillRect(ux, uy, ux + charW, uy + uth, px, dmDrawWithTransparency);
  end;
end;

{$IF defined(LINUX) or defined(DARWIN)}
procedure TTyPainter.DrawTextSupersampled(const ARect: TRect; const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AColor: TTyColor; AHAlign: TAlignment; AVAlign: TTextLayout);
const
  FACTOR = 3;  // matches BGRA's own Windows supersample factor
var
  w, h: Integer;
  hi: TBGRABitmap;
  lo: TBGRACustomBitmap;
  style: TTextStyle;
  px: TBGRAPixel;
begin
  if (FBmp = nil) or (AText = '') then Exit;
  w := ARect.Right - ARect.Left;
  h := ARect.Bottom - ARect.Top;
  if (w <= 0) or (h <= 0) then Exit;
  px := TyColorToBGRA(AColor);
  // Rasterize the glyphs at FACTOR x the device size: even after BGRA downgrades to fqSystem,
  // big glyphs come out crisp; downscaling them yields smooth grayscale AA (no ClearType colour
  // fringe on the accent pill) -- exactly the supersample BGRA itself applies on Windows.
  hi := TBGRABitmap.Create(w * FACTOR, h * FACTOR);
  try
    hi.Fill(BGRAPixelTransparent);
    TyConfigureTextFont(hi, AFontName, AFontSizeLogical, AWeight, FPPI * FACTOR);
    style := Default(TTextStyle);
    style.Alignment := AHAlign;
    style.Layout := AVAlign;
    style.SingleLine := True;
    style.Clipping := False;
    hi.TextRect(Rect(0, 0, hi.Width, hi.Height), 0, 0, AText, style, px);
    hi.ResampleFilter := rfBestQuality;
    lo := hi.Resample(w, h, rmFineResample);
    try
      FBmp.PutImage(ARect.Left, ARect.Top, lo, dmDrawWithTransparency);
    finally
      lo.Free;
    end;
  finally
    hi.Free;
  end;
end;
{$ENDIF}

procedure TTyPainter.DrawGlyph(const ARect: TRect; AGlyph: TTyGlyphKind; AColor: TTyColor; AThicknessLogical: Integer; APadLogical: Integer = 4);
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
  pad := Scale(APadLogical);
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
    tgCheckIndeterminate:
      // centered filled square (Windows indeterminate look); m = min(w,h) from the setup vars
      FBmp.FillRectAntialias(cx - m * 0.28, cy - m * 0.28, cx + m * 0.28, cy + m * 0.28, px);
    tgRadioDot:
      FBmp.FillEllipseAntialias(cx, cy, m * 0.3, m * 0.3, px);
    tgChevronDown:
      FBmp.DrawPolyLineAntialias([PointF(l, t + h * 0.3),
        PointF(cx, b - h * 0.2), PointF(r, t + h * 0.3)], px, th);
    tgChevronRight:
      { Right-pointing chevron (>) — apex on the right, arms going up-left and
        down-left from the vertical centre. Mirrors tgChevronDown rotated 90°. }
      FBmp.DrawPolyLineAntialias([PointF(l + w * 0.3, t),
        PointF(r - w * 0.2, cy), PointF(l + w * 0.3, b)], px, th);
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
    tgDialogLauncher:
      begin
        // Office group dialog-launcher: a diagonal arrow into the bottom-right corner.
        FBmp.DrawLineAntialias(l, t, r, b, px, th, True);
        FBmp.DrawPolyLineAntialias([PointF(r - w * 0.5, b), PointF(r, b),
          PointF(r, b - h * 0.5)], px, th);
      end;
    { Status marks. All four sit on the SAME m-based circle/triangle so a row of alerts lines up
      optically whatever the type. Closed outlines are drawn as poly-LINES with the first point
      repeated (the painter has no closed-polygon stroke). }
    tgInfo:
      begin
        FBmp.EllipseAntialias(cx, cy, m * 0.5, m * 0.5, px, th);
        FBmp.FillEllipseAntialias(cx, cy - m * 0.26, th * 0.6, th * 0.6, px);   // the tittle
        FBmp.DrawLineAntialias(cx, cy - m * 0.06, cx, cy + m * 0.27, px, th, True);
      end;
    tgSuccess:
      begin
        FBmp.EllipseAntialias(cx, cy, m * 0.5, m * 0.5, px, th);
        FBmp.DrawPolyLineAntialias([PointF(cx - m * 0.23, cy + m * 0.02),
          PointF(cx - m * 0.06, cy + m * 0.19), PointF(cx + m * 0.24, cy - m * 0.19)], px, th);
      end;
    tgWarning:
      begin
        // A triangle, not a ring — the one shape that reads as "warning" at 16px without colour.
        FBmp.DrawPolyLineAntialias([PointF(cx, t), PointF(r, b), PointF(l, b), PointF(cx, t)], px, th);
        FBmp.DrawLineAntialias(cx, t + h * 0.34, cx, t + h * 0.66, px, th, True);
        FBmp.FillEllipseAntialias(cx, t + h * 0.82, th * 0.6, th * 0.6, px);
      end;
    tgError:
      begin
        FBmp.EllipseAntialias(cx, cy, m * 0.5, m * 0.5, px, th);
        FBmp.DrawLineAntialias(cx - m * 0.19, cy - m * 0.19, cx + m * 0.19, cy + m * 0.19, px, th, True);
        FBmp.DrawLineAntialias(cx + m * 0.19, cy - m * 0.19, cx - m * 0.19, cy + m * 0.19, px, th, True);
      end;
  end;
end;

procedure TTyPainter.DrawDropChevron(const AZoneRect: TRect; AColor: TTyColor; ASizeLogical: Integer);
var
  w, h, cx, cy, l, r, top, bot, th: Single;
  px: TBGRAPixel;
begin
  if FBmp = nil then Exit;
  px := TyColorToBGRA(AColor);
  w := Scale(ASizeLogical);
  if w < 4 then w := 4;
  h := w * 0.5;                 // a clean, not-too-flat V
  // A THIN stroke (~w/6.5) — the old fixed 2px looked chubby on a small chevron.
  th := w / 6.5;
  if th < 1.1 then th := 1.1;
  cx := (AZoneRect.Left + AZoneRect.Right) / 2;
  cy := (AZoneRect.Top + AZoneRect.Bottom) / 2;
  l := cx - w / 2; r := cx + w / 2;
  top := cy - h / 2; bot := cy + h / 2;
  // Drawn directly (not via DrawGlyph) so the stroke width is fractional, not a chunky int.
  FBmp.DrawPolyLineAntialias([PointF(l, top), PointF(cx, bot), PointF(r, top)], px, th, False);
end;

procedure TTyPainter.BlitRegion(ASrc: TBGRABitmap; const ASrcR, ADstR: TRect; ATile: Boolean = False);
var
  part: TBGRABitmap;
  x, y: Integer;
  oldClip: TRect;
begin
  if (ASrcR.Right <= ASrcR.Left) or (ASrcR.Bottom <= ASrcR.Top) then
    Exit;
  if (ADstR.Right <= ADstR.Left) or (ADstR.Bottom <= ADstR.Top) then
    Exit;
  part := ASrc.GetPart(ASrcR) as TBGRABitmap;
  try
    // v3/B3: TILE the region at 1:1 (repeat) when it must EXPAND and tiling is asked; clip to
    // the region so tiles can't bleed into neighbouring nine-slice cells. Otherwise stretch
    // (also the path for corners, whose dst == src size, so tiling would be a no-op anyway).
    if ATile and (part.Width > 0) and (part.Height > 0)
       and ((ADstR.Right - ADstR.Left > part.Width) or (ADstR.Bottom - ADstR.Top > part.Height)) then
    begin
      oldClip := FBmp.ClipRect;
      FBmp.ClipRect := ADstR;
      try
        y := ADstR.Top;
        while y < ADstR.Bottom do
        begin
          x := ADstR.Left;
          while x < ADstR.Right do
          begin
            FBmp.PutImage(x, y, part, dmDrawWithTransparency);
            Inc(x, part.Width);
          end;
          Inc(y, part.Height);
        end;
      finally
        FBmp.ClipRect := oldClip;
      end;
    end
    else
      FBmp.StretchPutImage(ADstR, part, dmDrawWithTransparency);
  finally
    part.Free;
  end;
end;

procedure TTyPainter.NineSlice(const ARect: TRect; const AImagePath: string; const AInsets: TRect; ATile: Boolean);
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
    // corners (0/2/6/8) stay 1:1; edges (1/3/5/7) + center (4) tile when ATile (else stretch).
    BlitRegion(src, Rect(0, 0, sxL, syT), Rect(dl, dt, dl + sl, dt + st));
    BlitRegion(src, Rect(sxL, 0, sxR, syT), Rect(dl + sl, dt, dr - sr, dt + st), ATile);
    BlitRegion(src, Rect(sxR, 0, iw, syT), Rect(dr - sr, dt, dr, dt + st));
    BlitRegion(src, Rect(0, syT, sxL, syB), Rect(dl, dt + st, dl + sl, db - sb), ATile);
    BlitRegion(src, Rect(sxL, syT, sxR, syB), Rect(dl + sl, dt + st, dr - sr, db - sb), ATile);
    BlitRegion(src, Rect(sxR, syT, iw, syB), Rect(dr - sr, dt + st, dr, db - sb), ATile);
    BlitRegion(src, Rect(0, syB, sxL, ih), Rect(dl, db - sb, dl + sl, db));
    BlitRegion(src, Rect(sxL, syB, sxR, ih), Rect(dl + sl, db - sb, dr - sr, db), ATile);
    BlitRegion(src, Rect(sxR, syB, iw, ih), Rect(dr - sr, db - sb, dr, db));
  finally
    src.Free;
  end;
end;

procedure TTyPainter.FillImageSlice(const ARect: TRect; ASrc: TBGRABitmap;
  const ASrcOffset: TPoint);
{ Blit a (clamped) slice of a backdrop bitmap 1:1 into ARect — used as the opaque
  base behind ANY control on an image-backed form, so its corners read as the same
  photo the form shows instead of a flat solid fill. }
var
  w, h, ovL, ovT, ovR, ovB: Integer;
  part: TBGRABitmap;
  oldClip: TRect;
begin
  if (FBmp = nil) or (ASrc = nil) then Exit;
  w := ARect.Right - ARect.Left;
  h := ARect.Bottom - ARect.Top;
  if (w <= 0) or (h <= 0) then Exit;
  ovL := ASrcOffset.X; if ovL < 0 then ovL := 0;
  ovT := ASrcOffset.Y; if ovT < 0 then ovT := 0;
  ovR := ASrcOffset.X + w; if ovR > ASrc.Width then ovR := ASrc.Width;
  ovB := ASrcOffset.Y + h; if ovB > ASrc.Height then ovB := ASrc.Height;
  if (ovR <= ovL) or (ovB <= ovT) then Exit;
  oldClip := FBmp.ClipRect;
  FBmp.ClipRect := ARect;
  try
    part := ASrc.GetPart(Rect(ovL, ovT, ovR, ovB)) as TBGRABitmap;
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

procedure TTyPainter.FillGlass(const ARect: TRect; AGlass: TBGRABitmap;
  const ASrcOffset: TPoint; const ATint: TTyColor; const ACorners: TTyCorners);
{ The glass pane itself: the BLURRED backdrop slice + tint, round-clipped to the
  control's corners and laid over the sharp base FillImageSlice already painted. }
var
  w, h, ovL, ovT, ovR, ovB, r: Integer;
  opts: TRoundRectangleOptions;
  part, temp, mask: TBGRABitmap;
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
    r := TyClampRadiusPx(r, w, h);
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

procedure TTyPainter.FillCornerGaps(const ARect: TRect; const ACorners: TTyCorners; AColor: TTyColor);
var
  temp: TBGRABitmap;
  w, h, r: Integer;
  opts: TRoundRectangleOptions;
begin
  if FBmp = nil then Exit;
  w := ARect.Right - ARect.Left;
  h := ARect.Bottom - ARect.Top;
  if (w <= 0) or (h <= 0) then Exit;
  // Max corner radius + per-corner squaring, exactly as FillBackground/FillGlass compute.
  r := ACorners.TL;
  if ACorners.TR > r then r := ACorners.TR;
  if ACorners.BR > r then r := ACorners.BR;
  if ACorners.BL > r then r := ACorners.BL;
  r := Scale(r);
  r := TyClampRadiusPx(r, w, h);
  if r <= 0 then Exit;   // square control -> no corner gaps to clean
  opts := [];
  if ACorners.TL <= 0 then Include(opts, rrTopLeftSquare);
  if ACorners.TR <= 0 then Include(opts, rrTopRightSquare);
  if ACorners.BR <= 0 then Include(opts, rrBottomRightSquare);
  if ACorners.BL <= 0 then Include(opts, rrBottomLeftSquare);
  // Build AColor everywhere, then erase the rounded interior (AA) so only the corner
  // gaps remain; composite that over FBmp to overwrite whatever (shadow) was there.
  temp := TBGRABitmap.Create(w, h, TyColorToBGRA(AColor));
  try
    temp.EraseRoundRectAntialias(0, 0, w - 1, h - 1, r, r, 255, opts);
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
