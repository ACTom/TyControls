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
    minimum contrast  src/common/Color.ts:230-384 (Copyright (c) 2017 The xterm.js
                    authors), src/browser/renderer/shared/RendererUtils.ts:15-65,
                    src/browser/ColorContrastCache.ts; the luminance goes through
                    TyTermRelativeLuminance (Core), a table of V8's own results
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
    to it (upstream passes clampToCell = false for these, translateArgs :734). The
    clip is the cell's: a drawn glyph is rasterized once, white on a transparent
    bitmap a little larger than the cell, into a coverage mask kept in the glyph cache (by
    code point, cells, cell size, PPI and, for the shades, the pattern's phase), and
    tinted wherever it lands with the gamma-corrected blend Canvas2D draws with -- the
    same pixels as drawing it straight onto the surface, without a surface-sized clip
    mask (two of them) per drawn cell.
  - Single code points are cached under a 64-bit key; only clusters of several code
    points (and the IME's marked text) build a string key. }

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
    (design spec 10.4). Keyed by text, weight, slant, width and font -- no colour.
    Two key spaces share the one recency list and capacity: strings (clusters of
    several code points, marked text) and 64-bit codes (a single code point, see
    TyTermCodeKey; a drawn glyph, see TyTermCustomGlyphKey). }
  TTyTermGlyphCache = class
  private type
    TNode = class
      Key: string;
      Code: UInt64;
      IsCode: Boolean;
      Glyph: TTyTermGlyph;
      Prev, Next: TNode;
      Ascii: Integer;                { slot in FAscii, -1 = none }
    end;
  private
    FMap: specialize TDictionary<string, TNode>;
    FCodes: specialize TDictionary<UInt64, TNode>;
    { printable ASCII, one cell, the main font: the bulk of any screen, looked up without
      building a key string (the same entries as FMap, never more) }
    FAscii: array[0..95 * 4 - 1] of TNode;
    FHead, FTail: TNode;             { head = most recently used }
    FCapacity: Integer;
    FHits, FMisses, FEvictions: Integer;
    procedure Unlink(ANode: TNode);
    procedure PushFront(ANode: TNode);
    function GetCount: Integer;
    procedure MakeRoom;
    procedure Hit(ANode: TNode);
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
    { the same under a 64-bit code (TyTermCodeKey, TyTermCustomGlyphKey) }
    function FindCode(ACode: UInt64): TTyTermGlyph;
    procedure AddCode(ACode: UInt64; AGlyph: TTyTermGlyph);
    procedure Clear;
    { the three counters back to 0 (Clear keeps them: they add up over the cache's life) }
    procedure ResetStats;
    property Count: Integer read GetCount;
    property Capacity: Integer read FCapacity;
    { FOR THE TESTS and the probes }
    property Hits: Integer read FHits;
    property Misses: Integer read FMisses;
    { entries dropped to make room (least recently used first) }
    property Evictions: Integer read FEvictions;
  end;

  { Draws a cluster into a coverage mask through the library's text path. The scratch
    surface is made once, big enough for four cells, and keeps its font between calls:
    the font is configured only when the name, weight, slant, size or PPI differ from
    the last glyph's. What a glyph still costs (about 1 ms on Win32, phase 5) is the
    library's text renderer itself (TTyGdiTextRenderer, Painter.pas), which is why the
    row painter spreads new glyphs over frames (RasterBudgetMs). }
  TTyTermGlyphRasterizer = class
  private
    FScratch: TBGRABitmap;
    FFontName: string;
    FFontSize, FFontPPI, FFontWeight: Integer;
    FFontItalic, FFontSet: Boolean;
    FConfigured: Integer;
    procedure Reserve(AW, AH: Integer);
    procedure Configure(const AName: string; ASize, AWeight, APPI: Integer; AItalic: Boolean);
  public
    destructor Destroy; override;
    function Rasterize(const AKey: TTyTermGlyphKey; const ASpec: TTyTermFontSpec;
      const AMetrics: TTyTermCellMetrics): TTyTermGlyph;
    { FOR THE TESTS and the probes: how many times a font was configured }
    property FontsConfigured: Integer read FConfigured;
  end;

  { ColorContrastCache.ts: (background, foreground) -> the adjusted foreground, or "no
    adjustment needed". The key is ordered (background first); both $RRGGBB. }
  TTyTermContrastCache = class
  private
    FMap: specialize TDictionary<UInt64, Cardinal>;
    function GetCount: Integer;
  public
    constructor Create;
    destructor Destroy; override;
    { False = not cached. AAdjusted False: the pair already holds the ratio (upstream's
      null), AResult is then AFg. }
    function Find(ABg, AFg: Cardinal; out AResult: Cardinal; out AAdjusted: Boolean): Boolean;
    procedure Put(ABg, AFg, AResult: Cardinal; AAdjusted: Boolean);
    procedure Clear;
    property Count: Integer read GetCount;
  end;

  TTyTermCursorShape = (tcpNone, tcpBlock, tcpOutline, tcpUnderline, tcpBar);
  { milliseconds; the control passes its own clock (the Core's, injectable) }
  TTyTermClock = function: Double of object;

  { One row: backgrounds, glyphs, lines, cursor (design spec 10.1's order). }
  TTyTermRowPainter = class
  private type
    TCellInfo = record
      C: TTyTermCellColors;
      Ul: Integer;                 { underline style, 0 none }
      Strike, Over: Boolean;
      Sel: Boolean;                { in the selection (a wide character: its first column) }
    end;
  private
    FRowsPainted: Integer;
    FInfo: array of TCellInfo;     { reused row to row }
    FFrameStart: Double;
    FRasterized: Integer;
    FRowComplete: Boolean;
    FRowUsesYPhase: Boolean;
    function MayRasterize: Boolean;
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
    { How long one frame may spend drawing glyphs it has not cached (ms); <= 0 or no
      Clock = no limit. Once over, a glyph not in the cache is left out and its row
      reported incomplete (PaintRow returns False): the caller keeps the row dirty and
      paints it again, whole, next frame. At least one glyph is drawn every frame. }
    RasterBudgetMs: Double;
    Clock: TTyTermClock;
    { Set by the caller before every row (PaintRow does not clear them). A cell in the
      selected columns [SelFrom, SelTo) (SelFrom >= SelTo: none) -- a wide character by
      its first column, both halves together (DomRendererRowFactory.ts:112, :160) -- has
      its background REPLACED by SelBg ($RRGGBB, the selection colour already made opaque
      on the theme's background: DomRendererRowFactory.ts:380-386), whatever its own was
      (inverse, a bright background); when SelHasInk, SelInk ($RRGGBB) is its text colour.
      The hovered link's columns [LinkFrom, LinkTo) get a single underline in LinkColor,
      over the cells' own lines. }
    SelFrom, SelTo: Integer;
    SelBg: Cardinal;
    SelInk: Cardinal;
    SelHasInk: Boolean;
    LinkFrom, LinkTo: Integer;
    LinkColor: Cardinal;
    { the budget runs from here }
    procedure BeginFrame;
    { ACursorCol -1: no cursor on this row. ALine nil: an empty row. False: a glyph was
      left out for the budget, paint the row again. }
    function PaintRow(ABmp: TBGRABitmap; AX, AY: Integer; ALine: TTyTerminalLine; ACols: Integer;
      ACursorCol: Integer; ACursorShape: TTyTermCursorShape): Boolean;
    { FOR THE TESTS: rows painted so far; glyphs rasterized this frame }
    property RowsPainted: Integer read FRowsPainted;
    property RasterizedThisFrame: Integer read FRasterized;
    { the last row painted drew a shade (a pattern tiled from the surface's origin):
      its pixels hold only where its phase comes out the same (phase 5, the view's row
      reuse; TyTermGlyphPeriodY) }
    property RowUsesYPhase: Boolean read FRowUsesYPhase;
  end;

{ The cell for a font (design spec 10.2); not cached here -- the caller keys it. }
function TyTermMeasureCell(const ASpec: TTyTermFontSpec): TTyTermCellMetrics;
{ 0..15 Tango (only for tests and a missing theme), 16..231 the cube, 232..255 the
  greys -- src/browser/Types.ts:183-227 }
function TyTermDefaultPaletteColor(AIndex: Integer): Cardinal;
{ $RRGGBB -> an opaque pixel: the one conversion between the two }
function TyTermRgbToPixel(ARgb: Cardinal): TBGRAPixel;
{ AOver laid on the opaque ABg ($RRGGBB): per channel (bg x (255 - a) + over x a + 127)
  div 255. The view makes the theme's selection colour opaque with it, on the theme's
  background, once per frame -- upstream's selectionBackgroundOpaque /
  selectionInactiveBackgroundOpaque (ThemeService.ts:87-90) -- and the row painter puts
  that in place of a selected cell's background (SelBg), never over it. }
function TyTermBlendOver(ABg: Cardinal; const AOver: TBGRAPixel): Cardinal;
{ DomRendererRowFactory.ts:313-320, :342-460, the colour part: inverse swaps modes
  and values; default colours read 256 / 257; bold brightens palette colours below 8
  (P16 and P256, after the swap); dim mixes the foreground halfway to the background;
  a default underline colour is the final foreground. }
function TyTermResolveCellColors(AFg, ABg: Cardinal; const AExt: TTyTerminalExtAttrs;
  AResolve: TTyTermColorResolver; ADrawBoldBright: Boolean): TTyTermCellColors;
{ U+2500-259F, the range the control draws itself in phase 3 }
function TyTermIsCustomGlyph(ACodepoint: Cardinal): Boolean;
{ The least common multiple of the shade patterns' heights (CustomGlyphs.inc): a row
  of pixels holding a shade keeps its look when moved by a multiple of it. }
function TyTermGlyphPeriodY: Integer;
{ One drawn glyph, filling ACellRect's cell in AColor. APPI scales the stroke width
  as upstream's devicePixelRatio. Through the mask (TyTermRasterizeCustomGlyph +
  TyTermBlendMaskGamma), uncached: a fresh mask each call. }
procedure TyTermDrawCustomGlyph(ABmp: TBGRABitmap; const ACellRect: TRect; ACodepoint: Cardinal;
  AColor: TBGRAPixel; const AMetrics: TTyTermCellMetrics; APPI: Integer);
{ FOR THE TESTS: the same glyph drawn straight onto ABmp through Canvas2D with the cell
  as its clip -- how it was drawn before the mask; the reference the mask is held to. }
procedure TyTermDrawCustomGlyphDirect(ABmp: TBGRABitmap; const ACellRect: TRect; ACodepoint: Cardinal;
  AColor: TBGRAPixel; APPI: Integer);
{ A drawn glyph's coverage mask for an AW x AH cell whose top left sits at (APhaseX,
  APhaseY) modulo the shade pattern's period (TyTermCustomGlyphPhase); offset 0, 0.
  Mask nil = no ink. }
function TyTermRasterizeCustomGlyph(ACodepoint: Cardinal; AW, AH, APhaseX, APhaseY,
  APPI: Integer): TTyTermGlyph;
{ The shade pattern's phase for a cell whose top left is at (AX, AY) on the surface
  (the pattern is tiled from the surface's origin); 0, 0 for a glyph without a pattern. }
procedure TyTermCustomGlyphPhase(ACodepoint: Cardinal; AX, AY: Integer; out APhaseX, APhaseY: Integer);
{ Cache keys (TTyTermGlyphCache.FindCode / AddCode). A drawn glyph: code point, cells,
  phase, cell size and PPI. A single code point through the font: code point, weight,
  slant, cells and font. Bit 63 keeps the two apart. }
function TyTermCustomGlyphKey(ACodepoint: Cardinal; ACells, APhaseX, APhaseY, ACellW, ACellH,
  APPI: Integer): UInt64;
function TyTermCodeKey(ACodepoint: Cardinal; ABold, AItalic: Boolean; ACells: Integer;
  AFont: TTyTermFontKind): UInt64;
{ Tints a coverage mask onto ABmp at (AX, AY), clipped to AClip; the non-gamma blend
  the library's text is laid down with. Does not call InvalidateBitmap. }
procedure TyTermBlendMask(ABmp: TBGRABitmap; AX, AY: Integer; AMask: TGrayscaleMask;
  AColor: Cardinal; const AClip: TRect);
{ The same with the gamma-corrected blend Canvas2D draws shapes with (full coverage is
  the colour itself): a drawn glyph's mask lands exactly where drawing it would have. }
procedure TyTermBlendMaskGamma(ABmp: TBGRABitmap; AX, AY: Integer; AMask: TGrayscaleMask;
  AColor: Cardinal; const AClip: TRect);

{ ---- minimum contrast (Color.ts, bit for bit against terminal-contrast.json) ---------- }

{ Color.ts:377-382 contrastRatio: the lighter over the darker, each + 0.05. }
function TyTermContrastRatio(AL1, AL2: Double): Double;
{ Color.ts:296-321 rgba.ensureContrastRatio, on $RRGGBB. False = the ratio already
  holds (upstream's undefined; AResult is then AFg). A foreground darker than the
  ground is darkened first, then lightened if darkening cannot reach the ratio -- the
  one with the higher ratio wins; a lighter one the other way round. }
function TyTermEnsureContrastRatio(ABg, AFg: Cardinal; ARatio: Double; out AResult: Cardinal): Boolean;
{ Color.ts:323-341: each channel less ceil(10 %) a step until the ratio holds or black }
function TyTermReduceLuminance(ABg, AFg: Cardinal; ARatio: Double): Cardinal;
{ Color.ts:343-361: each channel plus ceil(10 % of what is left to 255) a step }
function TyTermIncreaseLuminance(ABg, AFg: Cardinal; ARatio: Double): Cardinal;
{ OptionsService.ts:188-190: Math.max(1, Math.min(21, Math.round(v * 10) / 10)). NaN
  and the infinities answer 1 (upstream would store NaN: design spec 15). }
function TyTermClampContrastRatio(AValue: Double): Double;
{ RendererUtils.ts:63-65 treatGlyphAsBackgroundColor: powerline U+E0A4-E0D6 and the box
  and block glyphs U+2500-259F keep their colour whatever the ratio. }
function TyTermExcludedFromContrast(ACodepoint: Cardinal): Boolean;

implementation

uses
  tyControls.Terminal.Core;

{$I tyControls.Terminal.CustomGlyphs.inc}

{ ---- minimum contrast ---------------------------------------------------------------- }

const
  KContrastOffset: Double = 0.05;
  KTenth: Double = 0.1;

function Lum3(R, G, B: Integer): Double; inline;
begin
  Result := TyTermRelativeLuminance((Cardinal(R) shl 16) or (Cardinal(G) shl 8) or Cardinal(B));
end;

function TyTermContrastRatio(AL1, AL2: Double): Double;
begin
  if AL1 < AL2 then
    Result := (AL2 + KContrastOffset) / (AL1 + KContrastOffset)
  else
    Result := (AL1 + KContrastOffset) / (AL2 + KContrastOffset);
end;

function TyTermReduceLuminance(ABg, AFg: Cardinal; ARatio: Double): Cardinal;
var
  bgR, bgG, bgB, fgR, fgG, fgB: Integer;
  cr: Double;
begin
  bgR := (ABg shr 16) and $FF;
  bgG := (ABg shr 8) and $FF;
  bgB := ABg and $FF;
  fgR := (AFg shr 16) and $FF;
  fgG := (AFg shr 8) and $FF;
  fgB := AFg and $FF;
  cr := TyTermContrastRatio(Lum3(fgR, fgG, fgB), Lum3(bgR, bgG, bgB));
  while (cr < ARatio) and ((fgR > 0) or (fgG > 0) or (fgB > 0)) do
  begin
    Dec(fgR, Max(0, Ceil(fgR * KTenth)));
    Dec(fgG, Max(0, Ceil(fgG * KTenth)));
    Dec(fgB, Max(0, Ceil(fgB * KTenth)));
    cr := TyTermContrastRatio(Lum3(fgR, fgG, fgB), Lum3(bgR, bgG, bgB));
  end;
  Result := (Cardinal(fgR) shl 16) or (Cardinal(fgG) shl 8) or Cardinal(fgB);
end;

function TyTermIncreaseLuminance(ABg, AFg: Cardinal; ARatio: Double): Cardinal;
var
  bgR, bgG, bgB, fgR, fgG, fgB: Integer;
  cr: Double;
begin
  bgR := (ABg shr 16) and $FF;
  bgG := (ABg shr 8) and $FF;
  bgB := ABg and $FF;
  fgR := (AFg shr 16) and $FF;
  fgG := (AFg shr 8) and $FF;
  fgB := AFg and $FF;
  cr := TyTermContrastRatio(Lum3(fgR, fgG, fgB), Lum3(bgR, bgG, bgB));
  while (cr < ARatio) and ((fgR < $FF) or (fgG < $FF) or (fgB < $FF)) do
  begin
    fgR := Min($FF, fgR + Ceil((255 - fgR) * KTenth));
    fgG := Min($FF, fgG + Ceil((255 - fgG) * KTenth));
    fgB := Min($FF, fgB + Ceil((255 - fgB) * KTenth));
    cr := TyTermContrastRatio(Lum3(fgR, fgG, fgB), Lum3(bgR, bgG, bgB));
  end;
  Result := (Cardinal(fgR) shl 16) or (Cardinal(fgG) shl 8) or Cardinal(fgB);
end;

function TyTermEnsureContrastRatio(ABg, AFg: Cardinal; ARatio: Double; out AResult: Cardinal): Boolean;
var
  bgL, fgL, ratioA, ratioB: Double;
  a, b: Cardinal;
begin
  AResult := AFg and $FFFFFF;
  bgL := TyTermRelativeLuminance(ABg and $FFFFFF);
  fgL := TyTermRelativeLuminance(AFg and $FFFFFF);
  if not (TyTermContrastRatio(bgL, fgL) < ARatio) then Exit(False);
  if fgL < bgL then
  begin
    a := TyTermReduceLuminance(ABg, AFg, ARatio);
    ratioA := TyTermContrastRatio(bgL, TyTermRelativeLuminance(a));
    if ratioA < ARatio then
    begin
      b := TyTermIncreaseLuminance(ABg, AFg, ARatio);
      ratioB := TyTermContrastRatio(bgL, TyTermRelativeLuminance(b));
      if ratioA > ratioB then AResult := a else AResult := b;
    end
    else
      AResult := a;
    Exit(True);
  end;
  a := TyTermIncreaseLuminance(ABg, AFg, ARatio);
  ratioA := TyTermContrastRatio(bgL, TyTermRelativeLuminance(a));
  if ratioA < ARatio then
  begin
    b := TyTermReduceLuminance(ABg, AFg, ARatio);
    ratioB := TyTermContrastRatio(bgL, TyTermRelativeLuminance(b));
    if ratioA > ratioB then AResult := a else AResult := b;
  end
  else
    AResult := a;
  Result := True;
end;

function TyTermClampContrastRatio(AValue: Double): Double;
begin
  if IsNan(AValue) or IsInfinite(AValue) then Exit(1);
  { the answer is 1 at or below 1 and 21 at or above 21 whatever the rounding; between,
    v * 10 + 0.5 lies in [10.5, 210.5), where it is exact and Floor is Math.round }
  if AValue <= 1 then Exit(1);
  if AValue >= 21 then Exit(21);
  Result := Floor(AValue * 10 + 0.5) / 10;
  if Result < 1 then Result := 1;
  if Result > 21 then Result := 21;
end;

function TyTermExcludedFromContrast(ACodepoint: Cardinal): Boolean;
begin
  Result := ((ACodepoint >= $E0A4) and (ACodepoint <= $E0D6))
    or ((ACodepoint >= $2500) and (ACodepoint <= $259F));
end;

constructor TTyTermContrastCache.Create;
begin
  inherited Create;
  FMap := specialize TDictionary<UInt64, Cardinal>.Create;
end;

destructor TTyTermContrastCache.Destroy;
begin
  FMap.Free;
  inherited Destroy;
end;

function TTyTermContrastCache.GetCount: Integer;
begin
  Result := FMap.Count;
end;

function TTyTermContrastCache.Find(ABg, AFg: Cardinal; out AResult: Cardinal; out AAdjusted: Boolean): Boolean;
var
  v: Cardinal;
begin
  Result := FMap.TryGetValue((UInt64(ABg and $FFFFFF) shl 24) or UInt64(AFg and $FFFFFF), v);
  if Result then
  begin
    AResult := v and $FFFFFF;
    AAdjusted := (v and $1000000) <> 0;
  end
  else
  begin
    AResult := AFg and $FFFFFF;
    AAdjusted := False;
  end;
end;

procedure TTyTermContrastCache.Put(ABg, AFg, AResult: Cardinal; AAdjusted: Boolean);
var
  v: Cardinal;
begin
  if AAdjusted then
    v := (AResult and $FFFFFF) or $1000000
  else
    v := AFg and $FFFFFF;
  FMap.AddOrSetValue((UInt64(ABg and $FFFFFF) shl 24) or UInt64(AFg and $FFFFFF), v);
end;

procedure TTyTermContrastCache.Clear;
begin
  FMap.Clear;
end;

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

{ flags, then the cell count in two bytes of its own (the IME's marked text can span
  more cells than a nibble holds), then the text }
function GlyphKeyText(const AKey: TTyTermGlyphKey): string;
var
  cells: Integer;
begin
  cells := EnsureRange(AKey.Cells, 0, $FFFF);
  Result := Chr(Ord(AKey.Bold) or (Ord(AKey.Italic) shl 1) or (Ord(AKey.Font) shl 2) or $80)
    + Chr(cells and $FF) + Chr(cells shr 8) + AKey.Text;
end;

function TyTermCodeKey(ACodepoint: Cardinal; ABold, AItalic: Boolean; ACells: Integer;
  AFont: TTyTermFontKind): UInt64;
begin
  Result := UInt64(ACodepoint and $1FFFFF)
    or (UInt64(Ord(ABold)) shl 21) or (UInt64(Ord(AItalic)) shl 22) or (UInt64(Ord(AFont)) shl 23)
    or (UInt64(EnsureRange(ACells, 0, 255)) shl 24);
end;

function TyTermCustomGlyphKey(ACodepoint: Cardinal; ACells, APhaseX, APhaseY, ACellW, ACellH,
  APPI: Integer): UInt64;
begin
  Result := (UInt64(1) shl 63)
    or UInt64((ACodepoint - TyTermGlyphFirst) and $FF)
    or (UInt64(EnsureRange(ACells, 0, 15)) shl 8)
    or (UInt64(APhaseX and $F) shl 12)
    or (UInt64(APhaseY and $F) shl 16)
    or (UInt64(EnsureRange(ACellW, 0, $FFF)) shl 20)
    or (UInt64(EnsureRange(ACellH, 0, $FFF)) shl 32)
    or (UInt64(EnsureRange(APPI, 0, $FFF)) shl 44);
end;

constructor TTyTermGlyphCache.Create(ACapacity: Integer);
begin
  inherited Create;
  if ACapacity < 1 then ACapacity := 1;
  FCapacity := ACapacity;
  FMap := specialize TDictionary<string, TNode>.Create;
  FCodes := specialize TDictionary<UInt64, TNode>.Create;
end;

destructor TTyTermGlyphCache.Destroy;
begin
  Clear;
  FMap.Free;
  FCodes.Free;
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
  Result := FMap.Count + FCodes.Count;
end;

procedure TTyTermGlyphCache.Hit(ANode: TNode);
begin
  Inc(FHits);
  if ANode <> FHead then
  begin
    Unlink(ANode);
    PushFront(ANode);
  end;
end;

{ evict the least recently used until one more fits }
procedure TTyTermGlyphCache.MakeRoom;
var
  old: TNode;
begin
  while (GetCount >= FCapacity) and (FTail <> nil) do
  begin
    old := FTail;
    Unlink(old);
    if old.IsCode then
      FCodes.Remove(old.Code)
    else
      FMap.Remove(old.Key);
    if old.Ascii >= 0 then FAscii[old.Ascii] := nil;
    old.Glyph.Free;
    old.Free;
    Inc(FEvictions);
  end;
end;

procedure TTyTermGlyphCache.ResetStats;
begin
  FHits := 0;
  FMisses := 0;
  FEvictions := 0;
end;

function TTyTermGlyphCache.FindCode(ACode: UInt64): TTyTermGlyph;
var
  node: TNode;
begin
  if FCodes.TryGetValue(ACode, node) then
  begin
    Hit(node);
    Result := node.Glyph;
  end
  else
  begin
    Inc(FMisses);
    Result := nil;
  end;
end;

procedure TTyTermGlyphCache.AddCode(ACode: UInt64; AGlyph: TTyTermGlyph);
var
  node: TNode;
begin
  if FCodes.TryGetValue(ACode, node) then
  begin
    if node.Glyph <> AGlyph then node.Glyph.Free;
    node.Glyph := AGlyph;
    Unlink(node);
    PushFront(node);
    Exit;
  end;
  MakeRoom;
  node := TNode.Create;
  node.Code := ACode;
  node.IsCode := True;
  node.Glyph := AGlyph;
  node.Ascii := -1;
  FCodes.Add(ACode, node);
  PushFront(node);
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
  Hit(node);
  Result := node.Glyph;
end;

function TTyTermGlyphCache.Find(const AKey: TTyTermGlyphKey): TTyTermGlyph;
var
  node: TNode;
begin
  if FMap.TryGetValue(GlyphKeyText(AKey), node) then
  begin
    Hit(node);
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
  node: TNode;
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
  MakeRoom;
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
  FCodes.Clear;
  FillChar(FAscii, SizeOf(FAscii), 0);
end;

{ ---- rasterizer ------------------------------------------------------------------ }

destructor TTyTermGlyphRasterizer.Destroy;
begin
  FScratch.Free;
  inherited Destroy;
end;

{ The scratch surface grows, never shrinks; a new one has no font, so the next
  Configure sets it up again. }
procedure TTyTermGlyphRasterizer.Reserve(AW, AH: Integer);
begin
  if (FScratch <> nil) and (FScratch.Width >= AW) and (FScratch.Height >= AH) then Exit;
  if FScratch <> nil then
  begin
    AW := Max(AW, FScratch.Width);
    AH := Max(AH, FScratch.Height);
  end;
  FreeAndNil(FScratch);
  FScratch := TBGRABitmap.Create(Max(AW, 64), Max(AH, 32));
  FFontSet := False;
end;

procedure TTyTermGlyphRasterizer.Configure(const AName: string; ASize, AWeight, APPI: Integer;
  AItalic: Boolean);
begin
  if FFontSet and (FFontName = AName) and (FFontSize = ASize) and (FFontWeight = AWeight)
    and (FFontPPI = APPI) and (FFontItalic = AItalic) then
    Exit;
  TyConfigureTextFont(FScratch, AName, ASize, AWeight, APPI);
  if AItalic then FScratch.FontStyle := FScratch.FontStyle + [fsItalic];
  FFontName := AName;
  FFontSize := ASize;
  FFontWeight := AWeight;
  FFontPPI := APPI;
  FFontItalic := AItalic;
  FFontSet := True;
  Inc(FConfigured);
end;

function TTyTermGlyphRasterizer.Rasterize(const AKey: TTyTermGlyphKey; const ASpec: TTyTermFontSpec;
  const AMetrics: TTyTermCellMetrics): TTyTermGlyph;
var
  tmp: TBGRABitmap;
  full: TGrayscaleMask;
  name: string;
  pad, cells, target, adv, w, h, x, y, l, t, r, b, nw, weight: Integer;
  p: PBGRAPixel;
  q: PByte;
begin
  Result := TTyTermGlyph.Create;
  cells := Max(1, AKey.Cells);
  target := cells * AMetrics.CellW;
  pad := AMetrics.CellH;
  if (AKey.Font = tfkWide) and (ASpec.WideName <> '') then name := ASpec.WideName else name := ASpec.MainName;
  weight := IfThen(AKey.Bold, 700, 400);
  { room for four cells and the padding up front, so the font is not lost to a regrowth }
  Reserve(4 * AMetrics.CellW + 2 * pad, AMetrics.CellH + 2 * pad);
  Configure(name, ASpec.SizeLogical, weight, ASpec.PPI, AKey.Italic);
  adv := FScratch.TextSize(AKey.Text).cx;
  w := Max(adv, target) + 2 * pad;
  h := AMetrics.CellH + 2 * pad;
  if (w > FScratch.Width) or (h > FScratch.Height) then
  begin
    Reserve(w, h);
    Configure(name, ASpec.SizeLogical, weight, ASpec.PPI, AKey.Italic);
  end;
  tmp := FScratch;
  tmp.FillRect(0, 0, w, h, BGRAWhite, dmSet);
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

function TyTermGlyphPeriodY: Integer;
begin
  Result := TyTermGlyphPatternPeriodY;
end;

{ a drawn glyph with a pattern part: its pixels depend on the cell's place }
function GlyphHasPattern(ACodepoint: Cardinal): Boolean;
var
  first, p: Integer;
begin
  Result := False;
  if not TyTermIsCustomGlyph(ACodepoint) then Exit;
  first := TyTermGlyphIndex[ACodepoint, 0];
  for p := first to first + TyTermGlyphIndex[ACodepoint, 1] - 1 do
    if TyTermGlyphParts[p, 0] = 1 then
      Exit(True);
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

{ AClip: clip Canvas2D to the cell -- only for drawing straight onto a surface (the
  reference); on a cell-sized bitmap the bitmap's own edge is the clip. }
procedure DrawPathPart(ABmp: TBGRABitmap; APart: Integer; const ACellRect: TRect; AColor: TBGRAPixel;
  APPI: Integer; AClip: Boolean);
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
    if AClip then
    begin
      c2d.beginPath;
      c2d.rect(ACellRect.Left, ACellRect.Top, W, H);
      c2d.clip;
    end;
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

{ Tiled from the surface's origin, so neighbouring cells run on seamlessly: pixel (x, y)
  of ABmp takes the pattern's cell ((y + AOrgY) mod rows, (x + AOrgX) mod cols). On the
  surface AOrg is 0, 0; on a cell-sized bitmap it is the cell's phase. }
procedure DrawPatternPart(ABmp: TBGRABitmap; APart: Integer; const ACellRect: TRect; AColor: TBGRAPixel;
  AOrgX, AOrgY: Integer);
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
  for y := r.Top to r.Bottom - 1 do
  begin
    p := ABmp.ScanLine[y] + r.Left;
    for x := r.Left to r.Right - 1 do
    begin
      if TyTermGlyphData[k + ((y + AOrgY) mod rows) * cols + ((x + AOrgX) mod cols)] <> 0 then
        p^ := AColor;
      Inc(p);
    end;
  end;
  ABmp.InvalidateBitmap;
end;

procedure TyTermCustomGlyphPhase(ACodepoint: Cardinal; AX, AY: Integer; out APhaseX, APhaseY: Integer);
var
  first, p, k: Integer;
begin
  APhaseX := 0;
  APhaseY := 0;
  if not TyTermIsCustomGlyph(ACodepoint) then Exit;
  first := TyTermGlyphIndex[ACodepoint, 0];
  for p := first to first + TyTermGlyphIndex[ACodepoint, 1] - 1 do
    if TyTermGlyphParts[p, 0] = 1 then
    begin
      k := TyTermGlyphParts[p, 2];
      { AX, AY are never negative on the surface; the mod stays in range for them }
      APhaseY := AY mod Round(TyTermGlyphData[k]);
      APhaseX := AX mod Round(TyTermGlyphData[k + 1]);
      Exit;
    end;
end;

procedure DrawCustomParts(ABmp: TBGRABitmap; const ACellRect: TRect; ACodepoint: Cardinal;
  AColor: TBGRAPixel; APPI, AOrgX, AOrgY: Integer; AClip: Boolean);
var
  first, n, p: Integer;
begin
  first := TyTermGlyphIndex[ACodepoint, 0];
  n := TyTermGlyphIndex[ACodepoint, 1];
  for p := first to first + n - 1 do
    case TyTermGlyphParts[p, 0] of
      0: DrawBlockPart(ABmp, p, ACellRect, AColor);
      1: DrawPatternPart(ABmp, p, ACellRect, AColor, AOrgX, AOrgY);
      2: DrawPathPart(ABmp, p, ACellRect, AColor, APPI, AClip);
    end;
end;

function TyTermRasterizeCustomGlyph(ACodepoint: Cardinal; AW, AH, APhaseX, APhaseY,
  APPI: Integer): TTyTermGlyph;
const
  Margin = 2;
var
  bmp: TBGRABitmap;
  x, y: Integer;
  p: PBGRAPixel;
  q: PByte;
  ink: Boolean;
begin
  Result := TTyTermGlyph.Create;
  if not TyTermIsCustomGlyph(ACodepoint) or (AW <= 0) or (AH <= 0) then Exit;
  if APPI <= 0 then APPI := 96;
  { White on transparent: every pixel keeps exactly the alpha Canvas2D would have
    blended the colour with (a transparent pixel takes the colour and that alpha). The
    cell sits Margin pixels inside the bitmap and Canvas2D clips to it, as drawing on
    the surface does: at the bitmap's own edge the polygon filler rounds the last row
    and column differently (up to 21 of 255 on a diagonal's ends). The clip mask is
    the size of this small bitmap, made once per glyph. }
  bmp := TBGRABitmap.Create(AW + 2 * Margin, AH + 2 * Margin);
  try
    DrawCustomParts(bmp, Rect(Margin, Margin, Margin + AW, Margin + AH), ACodepoint, BGRAWhite, APPI,
      APhaseX - Margin, APhaseY - Margin, True);
    Result.Mask := TGrayscaleMask.Create(AW, AH, 0);
    ink := False;
    for y := 0 to AH - 1 do
    begin
      p := bmp.ScanLine[y + Margin] + Margin;
      q := Result.Mask.ScanLine[y];
      for x := 0 to AW - 1 do
      begin
        q^ := p^.alpha;
        if q^ <> 0 then ink := True;
        Inc(p);
        Inc(q);
      end;
    end;
    if not ink then
      FreeAndNil(Result.Mask);
  finally
    bmp.Free;
  end;
end;

procedure TyTermDrawCustomGlyph(ABmp: TBGRABitmap; const ACellRect: TRect; ACodepoint: Cardinal;
  AColor: TBGRAPixel; const AMetrics: TTyTermCellMetrics; APPI: Integer);
var
  g: TTyTermGlyph;
  px, py: Integer;
begin
  if not TyTermIsCustomGlyph(ACodepoint) then Exit;
  if (ACellRect.Right <= ACellRect.Left) or (ACellRect.Bottom <= ACellRect.Top) then Exit;
  TyTermCustomGlyphPhase(ACodepoint, ACellRect.Left, ACellRect.Top, px, py);
  g := TyTermRasterizeCustomGlyph(ACodepoint, ACellRect.Right - ACellRect.Left,
    ACellRect.Bottom - ACellRect.Top, px, py, APPI);
  try
    TyTermBlendMaskGamma(ABmp, ACellRect.Left, ACellRect.Top, g.Mask,
      (Cardinal(AColor.red) shl 16) or (Cardinal(AColor.green) shl 8) or AColor.blue, ACellRect);
    ABmp.InvalidateBitmap;
  finally
    g.Free;
  end;
end;

procedure TyTermDrawCustomGlyphDirect(ABmp: TBGRABitmap; const ACellRect: TRect; ACodepoint: Cardinal;
  AColor: TBGRAPixel; APPI: Integer);
begin
  if not TyTermIsCustomGlyph(ACodepoint) then Exit;
  if (ACellRect.Right <= ACellRect.Left) or (ACellRect.Bottom <= ACellRect.Top) then Exit;
  if APPI <= 0 then APPI := 96;
  DrawCustomParts(ABmp, ACellRect, ACodepoint, AColor, APPI, 0, 0, True);
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

procedure TyTermBlendMaskGamma(ABmp: TBGRABitmap; AX, AY: Integer; AMask: TGrayscaleMask;
  AColor: Cardinal; const AClip: TRect);
var
  x, y, x0, x1, y0, y1: Integer;
  src: PByte;
  dst: PBGRAPixel;
  c: TBGRAPixel;
  ec: TExpandedPixel;
begin
  if AMask = nil then Exit;
  c := TyTermRgbToPixel(AColor);
  ec := GammaExpansion(c);
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
      { BGRASolidBrushDrawPixels: full coverage is the colour, partial the gamma blend }
      if src^ = 255 then
        dst^ := c
      else if src^ <> 0 then
        DrawExpandedPixelInlineNoAlphaCheck(dst, ec, src^);
      Inc(src);
      Inc(dst);
    end;
  end;
end;

{ ---- row painter ----------------------------------------------------------------- }

procedure TTyTermRowPainter.BeginFrame;
begin
  FRasterized := 0;
  if Assigned(Clock) then FFrameStart := Clock() else FFrameStart := 0;
end;

function TTyTermRowPainter.MayRasterize: Boolean;
begin
  Result := (RasterBudgetMs <= 0) or not Assigned(Clock) or (FRasterized = 0)
    or (Clock() - FFrameStart < RasterBudgetMs);
  if Result then
    Inc(FRasterized)
  else
    FRowComplete := False;
end;

procedure TTyTermRowPainter.DrawGlyphAt(ABmp: TBGRABitmap; ALine: TTyTerminalLine; ACol, AX,
  AY: Integer; AInk: Cardinal; const AClip: TRect);
var
  key: TTyTermGlyphKey;
  glyph: TTyTermGlyph;
  cp: Cardinal;
  w, px, py: Integer;
  attr: TTyTerminalAttrData;
  combined: Boolean;
  code: UInt64;
  font: TTyTermFontKind;
  cell: TRect;
begin
  if not ALine.HasContent(ACol) then Exit;
  w := ALine.GetWidth(ACol);
  if w <= 0 then Exit;
  cp := ALine.GetCodePoint(ACol);
  combined := ALine.IsCombined(ACol);
  if (not combined) and TyTermIsCustomGlyph(cp) then
  begin
    { drawn, not a font's: one mask per code point, cell size and shade phase }
    if GlyphHasPattern(cp) then
      FRowUsesYPhase := True;
    TyTermCustomGlyphPhase(cp, AX, AY, px, py);
    code := TyTermCustomGlyphKey(cp, w, px, py, Metrics.CellW, Metrics.CellH, Spec.PPI);
    glyph := GlyphCache.FindCode(code);
    if glyph = nil then
    begin
      if not MayRasterize then Exit;
      glyph := TyTermRasterizeCustomGlyph(cp, w * Metrics.CellW, Metrics.CellH, px, py, Spec.PPI);
      GlyphCache.AddCode(code, glyph);
    end;
    cell := Rect(AX, AY, AX + w * Metrics.CellW, AY + Metrics.CellH);
    IntersectRect(cell, cell, AClip);
    TyTermBlendMaskGamma(ABmp, AX, AY, glyph.Mask, AInk, cell);
    Exit;
  end;
  if (cp = 32) and not combined then Exit;
  attr := Default(TTyTerminalAttrData);
  attr.Fg := ALine.GetFg(ACol);
  attr.Bg := ALine.GetBg(ACol);
  if (w >= 2) and (Spec.WideName <> '') then font := tfkWide else font := tfkMain;
  { every field of key is set wherever it is used: no Default() on the hot path }
  if not combined then
  begin
    { a single code point: no string built unless it has to be rasterized }
    if (w = 1) and (cp > 32) and (cp <= 126) then
    begin
      glyph := GlyphCache.FindAscii(cp, attr.IsBold, attr.IsItalic);
      if glyph = nil then
      begin
        if not MayRasterize then Exit;
        key.Text := Chr(cp);
        key.Bold := attr.IsBold;
        key.Italic := attr.IsItalic;
        key.Cells := 1;
        key.Font := tfkMain;
        glyph := Rasterizer.Rasterize(key, Spec, Metrics);
        GlyphCache.Add(key, glyph);
      end;
    end
    else
    begin
      code := TyTermCodeKey(cp, attr.IsBold, attr.IsItalic, w, font);
      glyph := GlyphCache.FindCode(code);
      if glyph = nil then
      begin
        key.Text := ALine.GetChars(ACol);
        if (key.Text = '') or (key.Text = ' ') then Exit;
        if not MayRasterize then Exit;
        key.Bold := attr.IsBold;
        key.Italic := attr.IsItalic;
        key.Cells := w;
        key.Font := font;
        glyph := Rasterizer.Rasterize(key, Spec, Metrics);
        GlyphCache.AddCode(code, glyph);
      end;
    end;
  end
  else
  begin
    key.Text := ALine.GetChars(ACol);
    if (key.Text = '') or (key.Text = ' ') then Exit;
    key.Bold := attr.IsBold;
    key.Italic := attr.IsItalic;
    key.Cells := w;
    key.Font := font;
    glyph := GlyphCache.Find(key);
    if glyph = nil then
    begin
      if not MayRasterize then Exit;
      glyph := Rasterizer.Rasterize(key, Spec, Metrics);
      GlyphCache.Add(key, glyph);
    end;
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

function TyTermBlendOver(ABg: Cardinal; const AOver: TBGRAPixel): Cardinal;
var
  a: Cardinal;
begin
  a := AOver.alpha;
  Result := ((((ABg shr 16) and $FF) * (255 - a) + Cardinal(AOver.red) * a + 127) div 255) shl 16
    or ((((ABg shr 8) and $FF) * (255 - a) + Cardinal(AOver.green) * a + 127) div 255) shl 8
    or (((ABg and $FF) * (255 - a) + Cardinal(AOver.blue) * a + 127) div 255);
end;

function TTyTermRowPainter.PaintRow(ABmp: TBGRABitmap; AX, AY: Integer; ALine: TTyTerminalLine;
  ACols: Integer; ACursorCol: Integer; ACursorShape: TTyTermCursorShape): Boolean;
var
  c, runStart, x0, n, w, cw, cy, lw, kind, sf, st, owner: Integer;
  clip, cell: TRect;
  attr: TTyTerminalAttrData;
  ext: TTyTerminalExtAttrs;
  px: TBGRAPixel;
  runColor, ink: Cardinal;

  function LineStyleOf(ACol, AKind: Integer): Integer;
  begin
    case AKind of
      0: Result := FInfo[ACol].Ul;
      1: if FInfo[ACol].Strike then Result := 6 else Result := 0;
    else
      if FInfo[ACol].Over then Result := 7 else Result := 0;
    end;
  end;

  function LineColorOf(ACol, AKind: Integer): Cardinal;
  begin
    if AKind = 0 then Result := FInfo[ACol].C.Underline else Result := FInfo[ACol].C.Fg;
  end;

begin
  FRowComplete := True;
  FRowUsesYPhase := False;
  Result := True;
  if ACols <= 0 then Exit;
  clip := Rect(AX, AY, AX + ACols * Metrics.CellW, AY + Metrics.CellH);
  if Length(FInfo) < ACols then
    SetLength(FInfo, ACols);
  { 1. resolve every cell; backgrounds in runs of one colour }
  for c := 0 to ACols - 1 do
  begin
    if (ALine = nil) or (c >= ALine.Length) then
    begin
      FInfo[c].C := TyTermResolveCellColors(0, 0, Default(TTyTerminalExtAttrs), Resolver, DrawBoldBright);
      FInfo[c].Ul := 0;
      FInfo[c].Strike := False;
      FInfo[c].Over := False;
      Continue;
    end;
    if (c > 0) and (ALine.GetWidth(c) = 0) then
    begin
      { the second half of a wide character: the first half's colours }
      FInfo[c] := FInfo[c - 1];
      Continue;
    end;
    attr.Fg := ALine.GetFg(c);
    attr.Bg := ALine.GetBg(c);
    if not ALine.ExtendedEntry(c, ext) then ext := Default(TTyTerminalExtAttrs);
    attr.Extended := ext;
    FInfo[c].C := TyTermResolveCellColors(attr.Fg, attr.Bg, ext, Resolver, DrawBoldBright);
    if attr.IsUnderline then
    begin
      FInfo[c].Ul := attr.GetUnderlineStyle;
      if (FInfo[c].Ul < Ord(tusSingle)) or (FInfo[c].Ul > Ord(tusDashed)) then FInfo[c].Ul := Ord(tusSingle);
    end
    else
      FInfo[c].Ul := 0;
    FInfo[c].Strike := attr.IsStrikethrough;
    FInfo[c].Over := attr.IsOverline;
  end;
  { the selection takes the place of the cells' own backgrounds (not laid over them: an
    inverse cell or one on a bright background would hide it); a wide character is in
    it or not by its first column, both halves alike }
  sf := Max(SelFrom, 0);
  st := Min(SelTo, ACols);
  for c := 0 to ACols - 1 do
  begin
    owner := c;
    if (c > 0) and (ALine <> nil) and (c < ALine.Length) and (ALine.GetWidth(c) = 0) then
      owner := c - 1;
    FInfo[c].Sel := (owner >= sf) and (owner < st);
    if FInfo[c].Sel then
      FInfo[c].C.Bg := SelBg;
  end;
  runStart := 0;
  for c := 1 to ACols do
    if (c = ACols) or (FInfo[c].C.Bg <> FInfo[runStart].C.Bg) then
    begin
      ABmp.FillRect(AX + runStart * Metrics.CellW, AY, AX + c * Metrics.CellW, AY + Metrics.CellH,
        TyTermRgbToPixel(FInfo[runStart].C.Bg), dmSet);
      runStart := c;
    end;
  { 2. glyphs }
  if ALine <> nil then
    for c := 0 to Min(ACols, ALine.Length) - 1 do
      if not FInfo[c].C.Invisible then
      begin
        { a theme's selection colour for the text only where the theme gives one }
        if SelHasInk and FInfo[c].Sel then
          ink := SelInk
        else
          ink := FInfo[c].C.Fg;
        DrawGlyphAt(ABmp, ALine, c, AX + c * Metrics.CellW, AY, ink, clip);
      end;
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
  { the hovered link: one single underline over the cells' own }
  if Min(LinkTo, ACols) > Max(LinkFrom, 0) then
    DrawLineRun(ABmp, Ord(tusSingle), AX + Max(LinkFrom, 0) * Metrics.CellW,
      AX + Min(LinkTo, ACols) * Metrics.CellW, AY, LinkColor, clip);
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
          { hidden text (SGR 8) stays hidden under the cursor: upstream draws such a
            cell as a space (DomRendererRowFactory.ts:302-306) }
          if (ALine <> nil) and (ACursorCol < ALine.Length) and not FInfo[ACursorCol].C.Invisible then
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
  Result := FRowComplete;
end;

end.
