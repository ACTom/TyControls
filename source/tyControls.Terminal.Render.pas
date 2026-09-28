unit tyControls.Terminal.Render;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

{ The terminal's rendering parts, kept apart from the control so they can be tested on
  their own: the cell metrics, the 256-colour table, how a cell's colours resolve,
  the glyph masks and their cache, the box-drawing and block glyphs drawn by hand,
  and the painter of one row. No control, no Forms, no Controls.

  Our own code, following xterm.js 6.0.0 (commit c58ea3637f39) where it says so:
    the colours     src/browser/renderer/dom/DomRendererRowFactory.ts:313-320, :342-460
                    Copyright (c) 2018, 2023 The xterm.js authors
    the 256 colours src/browser/Types.ts:183-227
    drawn glyphs    addons/addon-webgl/src/customGlyphs/CustomGlyphRasterizer.ts
                    (drawBlockVectorChar :129-151, drawPatternChar :462-529,
                    drawPathFunctionCharacter :531-588, translateArgs :734-768);
                    Copyright (c) 2021 The xterm.js authors; the data is in
                    tyControls.Terminal.CustomGlyphs.inc, dumped from the addon
  MIT; the full text is in THIRD-PARTY-NOTICES.md.

  WHAT DIFFERS IN SHAPE FROM UPSTREAM:

  - A glyph is cached as a coverage mask with no colour in it and tinted wherever it
    lands (phase 3 plan, experiment E2, route (c)): the library's own text path draws
    the cluster black on white at 1x, coverage = 255 - the grey. On Windows that path
    is TTyGdiTextRenderer, which itself lays text down as coverage x ink with a
    non-gamma blend -- so tinting the mask with the same blend (FastBlendPixelInline,
    BlendMask below) is the library's text, pixel for pixel (measured: 0.2-0.4 of 255
    mean difference on inked pixels). NOT BGRA's FillMask in dmDrawWithTransparency:
    that blend is gamma-corrected and was 18-27 off. Our own loop rather than FillMask
    in dmLinearBlend (same result) because it is twice as fast on a full screen.
  - Underline, strikethrough and overline are drawn as whole runs and the patterns
    of the dotted, dashed and curly underlines are phased by the absolute x, so they
    run on across cells (upstream's underlineVariantOffset does that job for its
    per-cell atlas; we do not need it). The shade patterns are phased the same way.
  - Custom-glyph paths are not clamped to the cell after rounding; they are clipped
    to it (upstream passes clampToCell = false for these, translateArgs :734). }

interface

uses
  SysUtils, Classes, Math, Types, Graphics, LCLType, Generics.Collections,
  BGRABitmap, BGRABitmapTypes, BGRAGrayscaleMask, BGRABlend, BGRACanvas2D,
  tyControls.Painter, tyControls.Terminal.Buffer;

type
  TTyTermFontKind = (tfkMain, tfkWide);

  { Device pixels; every length already scaled by the PPI. }
  TTyTermCellMetrics = record
    CellW, CellH: Integer;          { the cell, letter spacing and line height included }
    CharW, CharH: Integer;          { the glyph box, without them }
    TextTop: Integer;               { glyph box top below the cell top (half the extra line height) }
    Baseline: Integer;              { below the cell top }
    LineW: Integer;                 { underline / strikethrough / outline cursor width, >= 1 }
    UnderlineY, StrikeY, OverlineY: Integer;   { below the cell top }
  end;

  { What the metrics and the glyph cache depend on (their key). }
  TTyTermFontSpec = record
    MainName, WideName: string;     { WideName '' = wide clusters in MainName too }
    SizeLogical, PPI, LetterSpacingLogical, LineHeightPercent: Integer;
    UnderlineWidthLogical, CursorWidthLogical: Integer;
    class operator = (const A, B: TTyTermFontSpec): Boolean;
  end;

  { 0..258 -> $RRGGBB; the control passes Core.ResolveColor }
  TTyTermColorResolver = function(AIndex: Integer): Cardinal of object;

  TTyTermCellColors = record
    Fg, Bg, Underline: Cardinal;    { $RRGGBB }
    Dim, Invisible: Boolean;
  end;

  TTyTermGlyphKey = record
    Text: string;
    Bold, Italic: Boolean;
    Cells: Integer;
    Font: TTyTermFontKind;
  end;

  { An 8-bit coverage mask and where its top left sits from the cell's top left.
    Mask nil: the cluster has no ink (kept in the cache all the same). }
  TTyTermGlyph = class
  private
    class var GLiveCount: Integer;
  public
    Mask: TGrayscaleMask;
    OffsetX, OffsetY: Integer;
    constructor Create;
    destructor Destroy; override;
    { FOR THE TESTS (a pure query): glyphs alive in the process }
    class function LiveCount: Integer;
  end;

  { The glyph cache: 4096 entries by default, least recently used dropped first
    (design spec 10.4). Keyed by text, weight, slant, width and font -- no colour. }
  TTyTermGlyphCache = class
  private type
    TNode = class
      Key: string;
      Glyph: TTyTermGlyph;
      Prev, Next: TNode;
      Ascii: Integer;                { slot in FAscii, -1 = none }
    end;
  private
    FMap: specialize TDictionary<string, TNode>;
    { printable ASCII, one cell, the main font: the bulk of any screen, looked up without
      building a key string (the same entries as FMap, never more) }
    FAscii: array[0..95 * 4 - 1] of TNode;
    FHead, FTail: TNode;             { head = most recently used }
    FCapacity: Integer;
    FHits, FMisses: Integer;
    procedure Unlink(ANode: TNode);
    procedure PushFront(ANode: TNode);
    function GetCount: Integer;
  public
    constructor Create(ACapacity: Integer = 4096);
    destructor Destroy; override;
    { nil = not cached; a hit moves the entry to the front }
    function Find(const AKey: TTyTermGlyphKey): TTyTermGlyph;
    { Find for a one-cell printable ASCII character in the main font (32..126); the same
      counting and the same recency as Find }
    function FindAscii(ACode: Integer; ABold, AItalic: Boolean): TTyTermGlyph;
    { takes ownership; an entry for the same key is replaced }
    procedure Add(const AKey: TTyTermGlyphKey; AGlyph: TTyTermGlyph);
    procedure Clear;
    property Count: Integer read GetCount;
    property Capacity: Integer read FCapacity;
    { FOR THE TESTS and the probes }
    property Hits: Integer read FHits;
    property Misses: Integer read FMisses;
  end;

  { Draws a cluster into a coverage mask through the library's text path. }
  TTyTermGlyphRasterizer = class
  private
    FScratch: TBGRABitmap;
    function Scratch(AW, AH: Integer): TBGRABitmap;
  public
    destructor Destroy; override;
    function Rasterize(const AKey: TTyTermGlyphKey; const ASpec: TTyTermFontSpec;
      const AMetrics: TTyTermCellMetrics): TTyTermGlyph;
  end;

  TTyTermCursorShape = (tcpNone, tcpBlock, tcpOutline, tcpUnderline, tcpBar);

  { One row: backgrounds, glyphs, lines, cursor (design spec 10.1's order). }
  TTyTermRowPainter = class
  private
    FRowsPainted: Integer;
    procedure DrawGlyphAt(ABmp: TBGRABitmap; ALine: TTyTerminalLine; ACol, AX, AY: Integer;
      AInk: Cardinal; const AClip: TRect);
    procedure DrawLineRun(ABmp: TBGRABitmap; AStyle, AX0, AX1, AY: Integer; AColor: Cardinal;
      const AClip: TRect);
  public
    Metrics: TTyTermCellMetrics;
    Spec: TTyTermFontSpec;
    Resolver: TTyTermColorResolver;
    GlyphCache: TTyTermGlyphCache;
    Rasterizer: TTyTermGlyphRasterizer;
    DrawBoldBright: Boolean;
    CursorColor, CursorInk: Cardinal;
    CursorWidthPx: Integer;
    { ACursorCol -1: no cursor on this row. ALine nil: an empty row. }
    procedure PaintRow(ABmp: TBGRABitmap; AX, AY: Integer; ALine: TTyTerminalLine; ACols: Integer;
      ACursorCol: Integer; ACursorShape: TTyTermCursorShape);
    { FOR THE TESTS: rows painted so far }
    property RowsPainted: Integer read FRowsPainted;
  end;

{ The cell for a font (design spec 10.2); not cached here -- the caller keys it. }
function TyTermMeasureCell(const ASpec: TTyTermFontSpec): TTyTermCellMetrics;
{ 0..15 Tango (only for tests and a missing theme), 16..231 the cube, 232..255 the
  greys -- src/browser/Types.ts:183-227 }
function TyTermDefaultPaletteColor(AIndex: Integer): Cardinal;
{ $RRGGBB -> an opaque pixel: the one conversion between the two }
function TyTermRgbToPixel(ARgb: Cardinal): TBGRAPixel;
{ DomRendererRowFactory.ts:313-320, :342-460, the colour part: inverse swaps modes
  and values; default colours read 256 / 257; bold brightens palette colours below 8
  (P16 and P256, after the swap); dim mixes the foreground halfway to the background;
  a default underline colour is the final foreground. }
function TyTermResolveCellColors(AFg, ABg: Cardinal; const AExt: TTyTerminalExtAttrs;
  AResolve: TTyTermColorResolver; ADrawBoldBright: Boolean): TTyTermCellColors;
{ U+2500-259F, the range the control draws itself in phase 3 }
function TyTermIsCustomGlyph(ACodepoint: Cardinal): Boolean;
{ One drawn glyph, filling ACellRect's cell in AColor. APPI scales the stroke width
  as upstream's devicePixelRatio. }
procedure TyTermDrawCustomGlyph(ABmp: TBGRABitmap; const ACellRect: TRect; ACodepoint: Cardinal;
  AColor: TBGRAPixel; const AMetrics: TTyTermCellMetrics; APPI: Integer);
{ Tints a coverage mask onto ABmp at (AX, AY), clipped to AClip; the non-gamma blend
  the library's text is laid down with. Does not call InvalidateBitmap. }
procedure TyTermBlendMask(ABmp: TBGRABitmap; AX, AY: Integer; AMask: TGrayscaleMask;
  AColor: Cardinal; const AClip: TRect);

implementation

{$I tyControls.Terminal.CustomGlyphs.inc}

{ ---- spec, metrics --------------------------------------------------------------- }

class operator TTyTermFontSpec.=(const A, B: TTyTermFontSpec): Boolean;
begin
  Result := (A.MainName = B.MainName) and (A.WideName = B.WideName)
    and (A.SizeLogical = B.SizeLogical) and (A.PPI = B.PPI)
    and (A.LetterSpacingLogical = B.LetterSpacingLogical)
    and (A.LineHeightPercent = B.LineHeightPercent)
    and (A.UnderlineWidthLogical = B.UnderlineWidthLogical)
    and (A.CursorWidthLogical = B.CursorWidthLogical);
end;

function TyTermMeasureCell(const ASpec: TTyTermFontSpec): TTyTermCellMetrics;
var
  bmp: TBGRABitmap;
  m: TFontPixelMetric;
  ppi, pct, xLine, base: Integer;
begin
  Result := Default(TTyTermCellMetrics);
  ppi := ASpec.PPI;
  if ppi <= 0 then ppi := 96;
  pct := ASpec.LineHeightPercent;
  if pct < 100 then pct := 100;
  bmp := TBGRABitmap.Create(1, 1);
  try
    TyConfigureTextFont(bmp, ASpec.MainName, ASpec.SizeLogical, 400, ppi);
    Result.CharW := Ceil(bmp.TextSize(StringOfChar('W', 32)).cx / 32);
    m := bmp.FontPixelMetric;
    { The cell is the font's line height (design spec 10.2). Measured on Windows
      (Consolas 9/12 pt at 96/144 PPI, plan experiment E1): Lineheight = TextSize('Ag').cy
      = TextSize of a CJK character, 14 / 22 / 19 / 28 px, and the CJK glyphs ink
      inside it; where the metric is undefined, TextSize('Ag') stands in. }
    if m.Defined and (m.Lineheight > 0) then
    begin
      Result.CharH := m.Lineheight;
      base := m.Baseline;
      xLine := m.xLine;
    end
    else
    begin
      Result.CharH := bmp.TextSize('Ag').cy;
      base := Result.CharH * 4 div 5;
      xLine := Result.CharH * 2 div 5;
    end;
  finally
    bmp.Free;
  end;
  if Result.CharW < 1 then Result.CharW := 1;
  if Result.CharH < 1 then Result.CharH := 1;
  Result.CellW := Max(1, Result.CharW + MulDiv(ASpec.LetterSpacingLogical, ppi, 96));
  Result.CellH := Max(Result.CharH, Ceil(Result.CharH * pct / 100));
  Result.TextTop := (Result.CellH - Result.CharH) div 2;
  Result.Baseline := Result.TextTop + base;
  Result.LineW := Max(1, MulDiv(ASpec.UnderlineWidthLogical, ppi, 96));
  Result.UnderlineY := Min(Result.CellH - Result.LineW, Result.Baseline + Result.LineW);
  Result.StrikeY := Result.TextTop + (xLine + base) div 2 - Result.LineW div 2;
  Result.OverlineY := Result.TextTop;
end;

{ ---- colours --------------------------------------------------------------------- }

const
  TangoColors: array[0..15] of Cardinal = (
    $2E3436, $CC0000, $4E9A06, $C4A000, $3465A4, $75507B, $06989A, $D3D7CF,
    $555753, $EF2929, $8AE234, $FCE94F, $729FCF, $AD7FA8, $34E2E2, $EEEEEC);
  CubeLevels: array[0..5] of Cardinal = ($00, $5F, $87, $AF, $D7, $FF);

function TyTermDefaultPaletteColor(AIndex: Integer): Cardinal;
var
  i, g: Integer;
begin
  if (AIndex >= 0) and (AIndex <= 15) then
    Exit(TangoColors[AIndex]);
  if (AIndex >= 16) and (AIndex <= 231) then
  begin
    i := AIndex - 16;
    Exit((CubeLevels[(i div 36) mod 6] shl 16) or (CubeLevels[(i div 6) mod 6] shl 8) or CubeLevels[i mod 6]);
  end;
  if (AIndex >= 232) and (AIndex <= 255) then
  begin
    g := 8 + 10 * (AIndex - 232);
    Exit((Cardinal(g) shl 16) or (Cardinal(g) shl 8) or Cardinal(g));
  end;
  Result := 0;
end;

function TyTermRgbToPixel(ARgb: Cardinal): TBGRAPixel;
begin
  Result := BGRA((ARgb shr 16) and $FF, (ARgb shr 8) and $FF, ARgb and $FF, 255);
end;

function TyTermResolveCellColors(AFg, ABg: Cardinal; const AExt: TTyTerminalExtAttrs;
  AResolve: TTyTermColorResolver; ADrawBoldBright: Boolean): TTyTermCellColors;
var
  attr: TTyTerminalAttrData;
  fg, bg, fgMode, bgMode, t, ulMode: Cardinal;
  inverse, bold: Boolean;
  ul: Integer;
begin
  attr.Fg := AFg;
  attr.Bg := ABg;
  attr.Extended := AExt;
  Result := Default(TTyTermCellColors);
  bold := attr.IsBold;
  fg := attr.Fg and TyTermAttrRgbMask;
  bg := attr.Bg and TyTermAttrRgbMask;
  fgMode := attr.GetFgColorMode;
  bgMode := attr.GetBgColorMode;
  inverse := attr.IsInverse;
  if inverse then
  begin
    t := fg; fg := bg; bg := t;
    t := fgMode; fgMode := bgMode; bgMode := t;
  end;
  { background }
  case bgMode of
    TyTermAttrCmP16, TyTermAttrCmP256: Result.Bg := AResolve(bg and $FF);
    TyTermAttrCmRgb: Result.Bg := bg;
  else
    if inverse then Result.Bg := AResolve(256) else Result.Bg := AResolve(257);
  end;
  { foreground: bold brightens palette colours below 8, after the swap }
  case fgMode of
    TyTermAttrCmP16, TyTermAttrCmP256:
      begin
        fg := fg and $FF;
        if bold and (fg < 8) and ADrawBoldBright then Inc(fg, 8);
        Result.Fg := AResolve(fg);
      end;
    TyTermAttrCmRgb: Result.Fg := fg;
  else
    if inverse then Result.Fg := AResolve(257) else Result.Fg := AResolve(256);
  end;
  { dim: the foreground at half opacity over the background }
  if attr.IsDim then
  begin
    Result.Fg := (((((Result.Fg shr 16) and $FF) + ((Result.Bg shr 16) and $FF) + 1) div 2) shl 16)
      or (((((Result.Fg shr 8) and $FF) + ((Result.Bg shr 8) and $FF) + 1) div 2) shl 8)
      or (((Result.Fg and $FF) + (Result.Bg and $FF) + 1) div 2);
    Result.Dim := True;
  end;
  Result.Invisible := attr.IsInvisible;
  { the underline colour (:313-320): default = the text colour }
  Result.Underline := Result.Fg;
  if attr.HasExtendedAttrs then
  begin
    ulMode := attr.GetUnderlineColorMode;
    ul := attr.GetUnderlineColor;
    case ulMode of
      TyTermAttrCmP16, TyTermAttrCmP256:
        begin
          if bold and (ul < 8) and ADrawBoldBright then Inc(ul, 8);
          Result.Underline := AResolve(ul and $FF);
        end;
      TyTermAttrCmRgb: Result.Underline := Cardinal(ul) and TyTermAttrRgbMask;
    end;
  end;
end;

{ ---- glyph cache ----------------------------------------------------------------- }

constructor TTyTermGlyph.Create;
begin
  inherited Create;
  Inc(GLiveCount);
end;

destructor TTyTermGlyph.Destroy;
begin
  Mask.Free;
  Dec(GLiveCount);
  inherited Destroy;
end;

class function TTyTermGlyph.LiveCount: Integer;
begin
  Result := GLiveCount;
end;

function GlyphKeyText(const AKey: TTyTermGlyphKey): string;
begin
  Result := Chr(Ord(AKey.Bold) or (Ord(AKey.Italic) shl 1) or (Ord(AKey.Font) shl 2)
    or ((AKey.Cells and $F) shl 3) or $80) + AKey.Text;
end;

constructor TTyTermGlyphCache.Create(ACapacity: Integer);
begin
  inherited Create;
  if ACapacity < 1 then ACapacity := 1;
  FCapacity := ACapacity;
  FMap := specialize TDictionary<string, TNode>.Create;
end;

destructor TTyTermGlyphCache.Destroy;
begin
  Clear;
  FMap.Free;
  inherited Destroy;
end;

procedure TTyTermGlyphCache.Unlink(ANode: TNode);
begin
  if ANode.Prev <> nil then ANode.Prev.Next := ANode.Next else FHead := ANode.Next;
  if ANode.Next <> nil then ANode.Next.Prev := ANode.Prev else FTail := ANode.Prev;
  ANode.Prev := nil;
  ANode.Next := nil;
end;

procedure TTyTermGlyphCache.PushFront(ANode: TNode);
begin
  ANode.Prev := nil;
  ANode.Next := FHead;
  if FHead <> nil then FHead.Prev := ANode;
  FHead := ANode;
  if FTail = nil then FTail := ANode;
end;

function TTyTermGlyphCache.GetCount: Integer;
begin
  Result := FMap.Count;
end;

function AsciiSlot(const AKey: TTyTermGlyphKey): Integer;
begin
  Result := -1;
  if (Length(AKey.Text) = 1) and (AKey.Text[1] >= #32) and (AKey.Text[1] <= #126)
    and (AKey.Cells = 1) and (AKey.Font = tfkMain) then
    Result := (Ord(AKey.Text[1]) - 32) * 4 + Ord(AKey.Bold) + 2 * Ord(AKey.Italic);
end;

function TTyTermGlyphCache.FindAscii(ACode: Integer; ABold, AItalic: Boolean): TTyTermGlyph;
var
  node: TNode;
begin
  node := nil;
  if (ACode >= 32) and (ACode <= 126) then
    node := FAscii[(ACode - 32) * 4 + Ord(ABold) + 2 * Ord(AItalic)];
  if node = nil then
  begin
    Inc(FMisses);
    Exit(nil);
  end;
  Inc(FHits);
  if node <> FHead then
  begin
    Unlink(node);
    PushFront(node);
  end;
  Result := node.Glyph;
end;

function TTyTermGlyphCache.Find(const AKey: TTyTermGlyphKey): TTyTermGlyph;
var
  node: TNode;
begin
  if FMap.TryGetValue(GlyphKeyText(AKey), node) then
  begin
    Inc(FHits);
    if node <> FHead then
    begin
      Unlink(node);
      PushFront(node);
    end;
    Result := node.Glyph;
  end
  else
  begin
    Inc(FMisses);
    Result := nil;
  end;
end;

procedure TTyTermGlyphCache.Add(const AKey: TTyTermGlyphKey; AGlyph: TTyTermGlyph);
var
  k: string;
  node, old: TNode;
begin
  k := GlyphKeyText(AKey);
  if FMap.TryGetValue(k, node) then
  begin
    if node.Glyph <> AGlyph then node.Glyph.Free;
    node.Glyph := AGlyph;
    Unlink(node);
    PushFront(node);
    Exit;
  end;
  while (FMap.Count >= FCapacity) and (FTail <> nil) do
  begin
    old := FTail;
    Unlink(old);
    FMap.Remove(old.Key);
    if old.Ascii >= 0 then FAscii[old.Ascii] := nil;
    old.Glyph.Free;
    old.Free;
  end;
  node := TNode.Create;
  node.Key := k;
  node.Glyph := AGlyph;
  node.Ascii := AsciiSlot(AKey);
  if node.Ascii >= 0 then FAscii[node.Ascii] := node;
  FMap.Add(k, node);
  PushFront(node);
end;

procedure TTyTermGlyphCache.Clear;
var
  node, next: TNode;
begin
  node := FHead;
  while node <> nil do
  begin
    next := node.Next;
    node.Glyph.Free;
    node.Free;
    node := next;
  end;
  FHead := nil;
  FTail := nil;
  FMap.Clear;
  FillChar(FAscii, SizeOf(FAscii), 0);
end;

{ ---- rasterizer ------------------------------------------------------------------ }

destructor TTyTermGlyphRasterizer.Destroy;
begin
  FScratch.Free;
  inherited Destroy;
end;

function TTyTermGlyphRasterizer.Scratch(AW, AH: Integer): TBGRABitmap;
begin
  if (FScratch = nil) or (FScratch.Width < AW) or (FScratch.Height < AH) then
  begin
    FreeAndNil(FScratch);
    FScratch := TBGRABitmap.Create(Max(AW, 64), Max(AH, 32));
  end;
  FScratch.FillRect(0, 0, AW, AH, BGRAWhite, dmSet);
  Result := FScratch;
end;

function TTyTermGlyphRasterizer.Rasterize(const AKey: TTyTermGlyphKey; const ASpec: TTyTermFontSpec;
  const AMetrics: TTyTermCellMetrics): TTyTermGlyph;
var
  tmp: TBGRABitmap;
  full: TGrayscaleMask;
  name: string;
  pad, cells, target, adv, w, h, x, y, l, t, r, b, nw: Integer;
  p: PBGRAPixel;
  q: PByte;
begin
  Result := TTyTermGlyph.Create;
  cells := Max(1, AKey.Cells);
  target := cells * AMetrics.CellW;
  pad := AMetrics.CellH;
  if (AKey.Font = tfkWide) and (ASpec.WideName <> '') then name := ASpec.WideName else name := ASpec.MainName;
  { the advance first, on the scratch surface configured for the font }
  tmp := Scratch(1, 1);
  TyConfigureTextFont(tmp, name, ASpec.SizeLogical, IfThen(AKey.Bold, 700, 400), ASpec.PPI);
  if AKey.Italic then tmp.FontStyle := tmp.FontStyle + [fsItalic];
  adv := tmp.TextSize(AKey.Text).cx;
  w := Max(adv, target) + 2 * pad;
  h := AMetrics.CellH + 2 * pad;
  tmp := Scratch(w, h);
  TyConfigureTextFont(tmp, name, ASpec.SizeLogical, IfThen(AKey.Bold, 700, 400), ASpec.PPI);
  if AKey.Italic then tmp.FontStyle := tmp.FontStyle + [fsItalic];
  tmp.TextOut(pad, pad + AMetrics.TextTop, AKey.Text, BGRABlack);
  { coverage, clipped to the cell's rows: a neighbouring row repaints over ink that
    leaves the row, so ink kept there would come and go }
  l := MaxInt; t := MaxInt; r := -1; b := -1;
  full := TGrayscaleMask.Create(w, AMetrics.CellH, 0);
  try
    for y := 0 to AMetrics.CellH - 1 do
    begin
      p := tmp.ScanLine[pad + y];
      q := full.ScanLine[y];
      for x := 0 to w - 1 do
      begin
        q^ := 255 - (p^.red + p^.green + p^.blue) div 3;
        if q^ <> 0 then
        begin
          if x < l then l := x;
          if x > r then r := x;
          if y < t then t := y;
          if y > b then b := y;
        end;
        Inc(p);
        Inc(q);
      end;
    end;
    if r < 0 then
      Exit;                                        { no ink: an empty glyph, cached all the same }
    if adv > target + 1 then
    begin
      { wider than its cells: squeezed to fit (upstream's rescaleOverlappingGlyphs idea) }
      nw := Max(1, Round((r - l + 1) * target / adv));
      Result.Mask := TGrayscaleMask.CreateDownSample(full, nw, b - t + 1, Rect(l, t, r + 1, b + 1));
      Result.OffsetX := Round((l - pad) * target / adv);
    end
    else
    begin
      Result.Mask := full.GetPart(Rect(l, t, r + 1, b + 1));
      Result.OffsetX := l - pad;
    end;
    Result.OffsetY := t;
  finally
    full.Free;
  end;
end;

{ ---- drawn glyphs ---------------------------------------------------------------- }

function TyTermIsCustomGlyph(ACodepoint: Cardinal): Boolean;
begin
  Result := (ACodepoint >= TyTermGlyphFirst) and (ACodepoint <= TyTermGlyphLast)
    and (TyTermGlyphIndex[ACodepoint, 1] > 0);
end;

{ translateArgs: cell units to pixels, rounded to the nearest half pixel unless 0
  (Math.round is half up: Floor(v + 0.5)), then the cell offset. }
function TranslateArg(AValue: Double; ASize: Integer; AOffset: Integer): Single;
var
  v: Double;
begin
  v := AValue * ASize;
  if v <> 0 then
    v := Floor(v + 0.5 + 0.5) - 0.5;
  Result := v + AOffset;
end;

procedure DrawPathPart(ABmp: TBGRABitmap; APart: Integer; const ACellRect: TRect; AColor: TBGRAPixel;
  APPI: Integer);
var
  c2d: TBGRACanvas2D;
  W, H, k, last, cmd, n, j: Integer;
  yp: Double;
  v: array[0..5] of Single;
begin
  W := ACellRect.Right - ACellRect.Left;
  H := ACellRect.Bottom - ACellRect.Top;
  yp := 0.15 / H * W;
  c2d := ABmp.Canvas2D;
  c2d.save;
  try
    c2d.beginPath;
    c2d.rect(ACellRect.Left, ACellRect.Top, W, H);
    c2d.clip;
    c2d.beginPath;
    k := TyTermGlyphParts[APart, 2];
    last := k + TyTermGlyphParts[APart, 3];
    while k < last do
    begin
      cmd := Round(TyTermGlyphData[k]);
      n := Round(TyTermGlyphData[k + 1]);
      Inc(k, 2);
      for j := 0 to n - 1 do
      begin
        if j mod 2 = 0 then
          v[j] := TranslateArg(TyTermGlyphData[k] + TyTermGlyphData[k + 1] * yp, W, ACellRect.Left)
        else
          v[j] := TranslateArg(TyTermGlyphData[k] + TyTermGlyphData[k + 1] * yp, H, ACellRect.Top);
        Inc(k, 2);
      end;
      case cmd of
        1: c2d.moveTo(v[0], v[1]);
        2: c2d.lineTo(v[0], v[1]);
        3: c2d.bezierCurveTo(v[0], v[1], v[2], v[3], v[4], v[5]);
      end;
    end;
    if TyTermGlyphParts[APart, 1] > 0 then
    begin
      c2d.strokeStyle(AColor);
      c2d.lineWidth := APPI / 96 * TyTermGlyphParts[APart, 1];
      c2d.stroke;
    end
    else
    begin
      c2d.fillStyle(AColor);
      c2d.fill;
    end;
  finally
    c2d.restore;
  end;
end;

procedure DrawBlockPart(ABmp: TBGRABitmap; APart: Integer; const ACellRect: TRect; AColor: TBGRAPixel);
var
  c2d: TBGRACanvas2D;
  k, last: Integer;
  xe, ye: Single;
begin
  xe := (ACellRect.Right - ACellRect.Left) / 8;
  ye := (ACellRect.Bottom - ACellRect.Top) / 8;
  c2d := ABmp.Canvas2D;
  c2d.save;
  try
    c2d.fillStyle(AColor);
    k := TyTermGlyphParts[APart, 2];
    last := k + TyTermGlyphParts[APart, 3];
    while k < last do
    begin
      c2d.fillRect(ACellRect.Left + TyTermGlyphData[k] * xe, ACellRect.Top + TyTermGlyphData[k + 1] * ye,
        TyTermGlyphData[k + 2] * xe, TyTermGlyphData[k + 3] * ye);
      Inc(k, 4);
    end;
  finally
    c2d.restore;
  end;
end;

procedure DrawPatternPart(ABmp: TBGRABitmap; APart: Integer; const ACellRect: TRect; AColor: TBGRAPixel);
var
  k, rows, cols, x, y: Integer;
  r: TRect;
  p: PBGRAPixel;
begin
  k := TyTermGlyphParts[APart, 2];
  rows := Round(TyTermGlyphData[k]);
  cols := Round(TyTermGlyphData[k + 1]);
  Inc(k, 2);
  r := ACellRect;
  if r.Left < 0 then r.Left := 0;
  if r.Top < 0 then r.Top := 0;
  if r.Right > ABmp.Width then r.Right := ABmp.Width;
  if r.Bottom > ABmp.Height then r.Bottom := ABmp.Height;
  { tiled from the surface's origin, so neighbouring cells run on seamlessly }
  for y := r.Top to r.Bottom - 1 do
  begin
    p := ABmp.ScanLine[y] + r.Left;
    for x := r.Left to r.Right - 1 do
    begin
      if TyTermGlyphData[k + (y mod rows) * cols + (x mod cols)] <> 0 then
        p^ := AColor;
      Inc(p);
    end;
  end;
  ABmp.InvalidateBitmap;
end;

procedure TyTermDrawCustomGlyph(ABmp: TBGRABitmap; const ACellRect: TRect; ACodepoint: Cardinal;
  AColor: TBGRAPixel; const AMetrics: TTyTermCellMetrics; APPI: Integer);
var
  first, n, p: Integer;
begin
  if not TyTermIsCustomGlyph(ACodepoint) then Exit;
  if (ACellRect.Right <= ACellRect.Left) or (ACellRect.Bottom <= ACellRect.Top) then Exit;
  if APPI <= 0 then APPI := 96;
  first := TyTermGlyphIndex[ACodepoint, 0];
  n := TyTermGlyphIndex[ACodepoint, 1];
  for p := first to first + n - 1 do
    case TyTermGlyphParts[p, 0] of
      0: DrawBlockPart(ABmp, p, ACellRect, AColor);
      1: DrawPatternPart(ABmp, p, ACellRect, AColor);
      2: DrawPathPart(ABmp, p, ACellRect, AColor, APPI);
    end;
end;

procedure TyTermBlendMask(ABmp: TBGRABitmap; AX, AY: Integer; AMask: TGrayscaleMask;
  AColor: Cardinal; const AClip: TRect);
var
  x, y, x0, x1, y0, y1: Integer;
  src: PByte;
  dst: PBGRAPixel;
  c: TBGRAPixel;
begin
  if AMask = nil then Exit;
  c := TyTermRgbToPixel(AColor);
  x0 := Max(AX, Max(AClip.Left, 0));
  x1 := Min(AX + AMask.Width, Min(AClip.Right, ABmp.Width));
  y0 := Max(AY, Max(AClip.Top, 0));
  y1 := Min(AY + AMask.Height, Min(AClip.Bottom, ABmp.Height));
  if (x1 <= x0) or (y1 <= y0) then Exit;
  for y := y0 to y1 - 1 do
  begin
    src := AMask.ScanLine[y - AY] + (x0 - AX);
    dst := ABmp.ScanLine[y] + x0;
    for x := x0 to x1 - 1 do
    begin
      if src^ <> 0 then
      begin
        c.alpha := src^;
        FastBlendPixelInline(dst, c);
      end;
      Inc(src);
      Inc(dst);
    end;
  end;
end;

{ ---- row painter ----------------------------------------------------------------- }

procedure TTyTermRowPainter.DrawGlyphAt(ABmp: TBGRABitmap; ALine: TTyTerminalLine; ACol, AX,
  AY: Integer; AInk: Cardinal; const AClip: TRect);
var
  key: TTyTermGlyphKey;
  glyph: TTyTermGlyph;
  cp: Cardinal;
  w: Integer;
  attr: TTyTerminalAttrData;
  asciiMissed: Boolean;
begin
  asciiMissed := False;
  if not ALine.HasContent(ACol) then Exit;
  w := ALine.GetWidth(ACol);
  if w <= 0 then Exit;
  cp := ALine.GetCodePoint(ACol);
  if (not ALine.IsCombined(ACol)) and TyTermIsCustomGlyph(cp) then
  begin
    TyTermDrawCustomGlyph(ABmp, Rect(AX, AY, AX + w * Metrics.CellW, AY + Metrics.CellH), cp,
      TyTermRgbToPixel(AInk), Metrics, Spec.PPI);
    Exit;
  end;
  attr := Default(TTyTerminalAttrData);
  attr.Fg := ALine.GetFg(ACol);
  attr.Bg := ALine.GetBg(ACol);
  if (cp = 32) and not ALine.IsCombined(ACol) then Exit;
  if (w = 1) and (cp > 32) and (cp <= 126) and not ALine.IsCombined(ACol) then
  begin
    { the common case, without a key string }
    glyph := GlyphCache.FindAscii(cp, attr.IsBold, attr.IsItalic);
    if glyph <> nil then
    begin
      TyTermBlendMask(ABmp, AX + glyph.OffsetX, AY + glyph.OffsetY, glyph.Mask, AInk, AClip);
      Exit;
    end;
    key.Text := Chr(cp);
    asciiMissed := True;
  end
  else
  begin
    key.Text := ALine.GetChars(ACol);
    if (key.Text = '') or (key.Text = ' ') then Exit;
  end;
  key.Bold := attr.IsBold;
  key.Italic := attr.IsItalic;
  key.Cells := w;
  if (w >= 2) and (Spec.WideName <> '') then key.Font := tfkWide else key.Font := tfkMain;
  if asciiMissed then
    glyph := nil                     { FindAscii already counted the miss }
  else
    glyph := GlyphCache.Find(key);
  if glyph = nil then
  begin
    glyph := Rasterizer.Rasterize(key, Spec, Metrics);
    GlyphCache.Add(key, glyph);
  end;
  TyTermBlendMask(ABmp, AX + glyph.OffsetX, AY + glyph.OffsetY, glyph.Mask, AInk, AClip);
end;

{ One run of one line style (1..5 underline styles, 6 strikethrough, 7 overline). }
procedure TTyTermRowPainter.DrawLineRun(ABmp: TBGRABitmap; AStyle, AX0, AX1, AY: Integer;
  AColor: Cardinal; const AClip: TRect);
var
  lw, y, x, t, tri, per: Integer;
  px: TBGRAPixel;

  procedure Bar(AL, AT, AR, AB: Integer);
  begin
    AL := Max(AL, AClip.Left);
    AR := Min(AR, AClip.Right);
    AT := Max(AT, AClip.Top);
    AB := Min(AB, AClip.Bottom);
    if (AR > AL) and (AB > AT) then
      ABmp.FillRect(AL, AT, AR, AB, px, dmSet);
  end;

begin
  lw := Metrics.LineW;
  px := TyTermRgbToPixel(AColor);
  case AStyle of
    6: Bar(AX0, AY + Metrics.StrikeY, AX1, AY + Metrics.StrikeY + lw);
    7: Bar(AX0, AY + Metrics.OverlineY, AX1, AY + Metrics.OverlineY + lw);
    Ord(tusSingle):
      Bar(AX0, AY + Metrics.UnderlineY, AX1, AY + Metrics.UnderlineY + lw);
    Ord(tusDouble):
      begin
        y := AY + Metrics.UnderlineY;
        Bar(AX0, y, AX1, y + lw);
        Bar(AX0, Max(AY, y - 2 * lw), AX1, Max(AY, y - 2 * lw) + lw);
      end;
    Ord(tusCurly):
      begin
        { a zigzag, period 4 x LineW, amplitude LineW, phased by the absolute x }
        per := 4 * lw;
        for x := AX0 to AX1 - 1 do
        begin
          t := x mod per;
          if t < 2 * lw then tri := t div 2 else tri := (per - t) div 2;
          y := AY + Metrics.UnderlineY - lw + tri;
          if y < AY then y := AY;
          Bar(x, y, x + 1, y + lw);
        end;
      end;
    Ord(tusDotted):
      for x := AX0 to AX1 - 1 do
        if (x div lw) mod 2 = 0 then
          Bar(x, AY + Metrics.UnderlineY, x + 1, AY + Metrics.UnderlineY + lw);
    Ord(tusDashed):
      for x := AX0 to AX1 - 1 do
        if x mod (5 * lw) < 3 * lw then
          Bar(x, AY + Metrics.UnderlineY, x + 1, AY + Metrics.UnderlineY + lw);
  end;
end;

procedure TTyTermRowPainter.PaintRow(ABmp: TBGRABitmap; AX, AY: Integer; ALine: TTyTerminalLine;
  ACols: Integer; ACursorCol: Integer; ACursorShape: TTyTermCursorShape);
type
  TCellInfo = record
    C: TTyTermCellColors;
    Ul: Integer;                 { underline style, 0 none }
    Strike, Over: Boolean;
  end;
var
  info: array of TCellInfo;
  c, runStart, x0, n, w, cw, cy, lw, kind: Integer;
  clip, cell: TRect;
  attr: TTyTerminalAttrData;
  ext: TTyTerminalExtAttrs;
  px: TBGRAPixel;
  runColor: Cardinal;

  function LineStyleOf(ACol, AKind: Integer): Integer;
  begin
    case AKind of
      0: Result := info[ACol].Ul;
      1: if info[ACol].Strike then Result := 6 else Result := 0;
    else
      if info[ACol].Over then Result := 7 else Result := 0;
    end;
  end;

  function LineColorOf(ACol, AKind: Integer): Cardinal;
  begin
    if AKind = 0 then Result := info[ACol].C.Underline else Result := info[ACol].C.Fg;
  end;

begin
  if ACols <= 0 then Exit;
  clip := Rect(AX, AY, AX + ACols * Metrics.CellW, AY + Metrics.CellH);
  SetLength(info, ACols);
  { 1. resolve every cell; backgrounds in runs of one colour }
  for c := 0 to ACols - 1 do
  begin
    if (ALine = nil) or (c >= ALine.Length) then
    begin
      info[c].C := TyTermResolveCellColors(0, 0, Default(TTyTerminalExtAttrs), Resolver, DrawBoldBright);
      info[c].Ul := 0;
      info[c].Strike := False;
      info[c].Over := False;
      Continue;
    end;
    if (c > 0) and (ALine.GetWidth(c) = 0) then
    begin
      { the second half of a wide character: the first half's colours }
      info[c] := info[c - 1];
      Continue;
    end;
    attr.Fg := ALine.GetFg(c);
    attr.Bg := ALine.GetBg(c);
    if not ALine.ExtendedEntry(c, ext) then ext := Default(TTyTerminalExtAttrs);
    attr.Extended := ext;
    info[c].C := TyTermResolveCellColors(attr.Fg, attr.Bg, ext, Resolver, DrawBoldBright);
    if attr.IsUnderline then
    begin
      info[c].Ul := attr.GetUnderlineStyle;
      if (info[c].Ul < Ord(tusSingle)) or (info[c].Ul > Ord(tusDashed)) then info[c].Ul := Ord(tusSingle);
    end
    else
      info[c].Ul := 0;
    info[c].Strike := attr.IsStrikethrough;
    info[c].Over := attr.IsOverline;
  end;
  runStart := 0;
  for c := 1 to ACols do
    if (c = ACols) or (info[c].C.Bg <> info[runStart].C.Bg) then
    begin
      ABmp.FillRect(AX + runStart * Metrics.CellW, AY, AX + c * Metrics.CellW, AY + Metrics.CellH,
        TyTermRgbToPixel(info[runStart].C.Bg), dmSet);
      runStart := c;
    end;
  { 2. glyphs }
  if ALine <> nil then
    for c := 0 to Min(ACols, ALine.Length) - 1 do
      if not info[c].C.Invisible then
        DrawGlyphAt(ABmp, ALine, c, AX + c * Metrics.CellW, AY, info[c].C.Fg, clip);
  { 3. lines: underline, strikethrough, overline, each in runs of one style and colour }
  for kind := 0 to 2 do
  begin
    runStart := 0;
    for c := 1 to ACols do
      if (c = ACols) or (LineStyleOf(c, kind) <> LineStyleOf(runStart, kind))
        or (LineColorOf(c, kind) <> LineColorOf(runStart, kind)) then
      begin
        if LineStyleOf(runStart, kind) <> 0 then
        begin
          runColor := LineColorOf(runStart, kind);
          DrawLineRun(ABmp, LineStyleOf(runStart, kind), AX + runStart * Metrics.CellW,
            AX + c * Metrics.CellW, AY, runColor, clip);
        end;
        runStart := c;
      end;
  end;
  { 4. the cursor }
  if (ACursorCol >= 0) and (ACursorCol < ACols) and (ACursorShape <> tcpNone) then
  begin
    w := 1;
    if (ALine <> nil) and (ACursorCol < ALine.Length) and (ALine.GetWidth(ACursorCol) = 2) then w := 2;
    cw := Min(w, ACols - ACursorCol) * Metrics.CellW;
    x0 := AX + ACursorCol * Metrics.CellW;
    cell := Rect(x0, AY, x0 + cw, AY + Metrics.CellH);
    px := TyTermRgbToPixel(CursorColor);
    lw := Max(1, Metrics.LineW);
    n := Max(1, CursorWidthPx);
    case ACursorShape of
      tcpBlock:
        begin
          ABmp.FillRect(cell, px, dmSet);
          if (ALine <> nil) and (ACursorCol < ALine.Length) then
            DrawGlyphAt(ABmp, ALine, ACursorCol, x0, AY, CursorInk, cell);
        end;
      tcpOutline:
        begin
          ABmp.FillRect(cell.Left, cell.Top, cell.Right, cell.Top + lw, px, dmSet);
          ABmp.FillRect(cell.Left, cell.Bottom - lw, cell.Right, cell.Bottom, px, dmSet);
          ABmp.FillRect(cell.Left, cell.Top, cell.Left + lw, cell.Bottom, px, dmSet);
          ABmp.FillRect(cell.Right - lw, cell.Top, cell.Right, cell.Bottom, px, dmSet);
        end;
      tcpUnderline:
        begin
          cy := Min(n, Metrics.CellH);
          ABmp.FillRect(cell.Left, cell.Bottom - cy, cell.Right, cell.Bottom, px, dmSet);
        end;
      tcpBar:
        ABmp.FillRect(cell.Left, cell.Top, cell.Left + Min(n, cw), cell.Bottom, px, dmSet);
    end;
  end;
  ABmp.InvalidateBitmap;
  Inc(FRowsPainted);
end;

end.
