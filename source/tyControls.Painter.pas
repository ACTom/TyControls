unit tyControls.Painter;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType, LazUTF8, BGRABitmap, BGRABitmapTypes,
  BGRAGradientScanner, BGRACanvas2D, BGRATextBidi,
  FPReadJPEG, FPReadPNG, FPReadBMP,  // register FPImage readers so url() jpg/png/bmp load
  tyControls.Types;

type
  TTyGlyphKind = (tgClose, tgMinimize, tgMaximize, tgRestore, tgCheck, tgCheckIndeterminate,
    tgRadioDot, tgChevronDown, tgChevronRight,
    // tgChevronLeft is tgChevronRight's MIRROR PARTNER and exists for one reason: a
    // right-to-left control that has already moved its collapsed-node chevron to the other
    // end still has to turn the STROKE round, and a direction the glyph set cannot name is a
    // direction no caller can ask for. Not every directional glyph needs a partner -- an
    // arrow at each end of a scroll-bar track reflects onto itself, which is why
    // TTyScrollBar deliberately keeps its pair (tyControls.ScrollBar.pas:617).
    tgChevronLeft,
    tgArrowUp, tgArrowDown, tgArrowLeft, tgArrowRight,
    { FILLED triangles -- the shape Windows itself uses for the STEP role. Rendering the live
      uxtheme parts on a Win10 box: SPIN/SPNP_UP is a solid 5x3 triangle with no antialiasing,
      identical in normal/hot/pressed, and the native tab control's scrollers are the same part
      (it spawns an UPDOWN). The drop-down button is deliberately NOT this shape -- CP_DROPDOWN-
      BUTTON is an antialiased hollow chevron -- so the two idioms are split by ROLE, not by
      taste: triangle to step a value or scroll a strip, chevron to disclose something.
      Before these existed the enum had no filled triangle at all, so the four controls that
      wanted one hand-rolled a path with four different sets of coefficients, and the six that
      wanted a spinner drew tgArrow* (a shaft with an open head) instead. AThicknessLogical is
      meaningless here and ignored; a filled shape has no stroke. }
    tgTriangleUp, tgTriangleDown, tgTriangleLeft, tgTriangleRight,
    tgDialogLauncher,
    // Semantic status marks (TTyAlert / TTyNotification). Drawn in ONE ink like every glyph
    // here, so they are outlines (ring + mark), not AntD's filled discs — a filled disc needs
    // two colours and would not tint with the caller's single AColor.
    tgInfo, tgSuccess, tgWarning, tgError);

  { Which side of a body a speech-balloon pointer leaves from. Named for the BODY's edge, so
    tpsTop means the wedge stands above the body -- which is what a balloon ANCHORED BELOW its
    target looks like. }
  TTyPointerSide = (tpsTop, tpsBottom, tpsLeft, tpsRight);

  TTyPainter = class
  private
    FBmp: TBGRABitmap;
    FCanvas: TCanvas;
    FRect: TRect;
    FPPI: Integer;
    FOwnsBmp: Boolean;
    FRightToLeft: Boolean;
    procedure GradientEndpoints(const ARect: TRect; AAngleDeg: Single; out P1, P2: TPointF);
    procedure BlitRegion(ASrc: TBGRABitmap; const ASrcR, ADstR: TRect; ATile: Boolean = False);
    {$IF defined(LINUX) or defined(DARWIN)}
    procedure DrawTextSupersampled(const ARect: TRect; const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AColor: TTyColor; AHAlign: TAlignment; AVAlign: TTextLayout);
    {$ENDIF}
    { ONE line of text, drawn exactly as DrawText always drew: ellipsis fitting, mnemonic
      underline, SingleLine + Clipping. The public DrawText is now only the dispatcher that
      decides how many of these to draw, so the single-line path is literally the same code
      it was before multi-line existed (and the pixel goldens with it). }
    procedure DrawTextLine(const ARect: TRect; const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AColor: TTyColor; AHAlign: TAlignment;
      AVAlign: TTextLayout; AEllipsis: Boolean; AMnemonicPos: Integer; ASmallCrisp: Boolean);
    { ONE line of text that carries right-to-left script, laid out through BGRA's
      TBidiTextLayout instead of through a single TextRect.

      WHY a second path rather than a flag on the first: a bare TextRect is always laid out
      with an IMPLICIT LEFT-TO-RIGHT paragraph base. Inside that call the widgetset's own
      engine does reorder the runs and shape the Arabic -- that part was never broken -- but
      it never asks whose paragraph this is. So "<arabic phrase> Acme" came out with the two
      halves swapped: the Arabic on the left, where a native reader expects the Latin tail.
      TBidiTextLayout resolves the base direction from the first strong character (fbmAuto),
      splits the line into same-level parts and places them itself, which also stops the
      answer depending on which widgetset is underneath.

      The font must already be configured on FBmp: the layout borrows FBmp.FontRenderer.

      LIMIT worth knowing: this is called once per LINE, so a caption that has already been
      wrapped (TyWrapTextCJK, which breaks on spaces and on CJK codepoints and therefore
      wraps Arabic correctly) resolves its base direction PER LINE. UAX #9 says a wrapped
      line should inherit the PARAGRAPH's base direction, so a wrapped right-to-left
      paragraph whose second line happens to begin with a Latin word gets a left-to-right
      base for that line alone. Fixing it means carrying the paragraph's direction down from
      the wrapper, which is a change to every wrapping caller, not to this function.

      AMnemonicPos is a 1-based BYTE offset into AText, 0 for none. }
    procedure DrawTextLineBidi(const ARect: TRect; const AText: string; AColor: TTyColor;
      AHAlign: TAlignment; AVAlign: TTextLayout; AMnemonicPos: Integer);
    { Build ONE line's bidi layout, already anchored in ARect by AHAlign/AVAlign. Shared by
      the drawing path and the caret queries, so a caret can never disagree with the glyph it
      is pointing at. The font must already be configured on FBmp. Caller frees; nil when
      there is nothing to lay out. }
    function BuildLineLayout(const ARect: TRect; const AText: string;
      AHAlign: TAlignment; AVAlign: TTextLayout): TBidiTextLayout;
    { The device-px height of one line box: the theme's --line-height (passed in as logical
      px by the caller, who owns the controller) when set, else the font's own line box.
      Assumes the font is already configured on FBmp. }
    function LineBoxHeight(ALineHeightLogical: Integer): Integer;
  public
    Opacity: Single;
    OpacityBase: TTyColor;   // when Opacity<1, dim TOWARD this opaque colour (0 = old alpha-reduce)
    { ARightToLeft arms this frame's MIRRORING. It says one thing only: the alignments the
      caller is about to pass are LOGICAL -- taLeftJustify means "the reading start", not
      "the left edge" -- so the painter resolves each of them to a physical side through
      LCL's BidiFlipAlignment. The control gets it from TControl.IsRightToLeft
      (controls.pp:1833, = BiDiMode <> bdLeftToRight), which is public and works from code
      even though nothing publishes BiDiMode yet.

      Deliberately a PARAMETER with a False default rather than something read off the
      control, and that is the whole safety property of this batch. Flipping every caller at
      once was the tempting design (plans/2026-08-04-rtl-mirroring-scope.md §2.1 counted 146
      DrawText sites behind this one function), but it is wrong for any caller that has
      already sliced its content rect into a SLOT and pre-positioned the text inside it:
      TTyEdit hands DrawText a taLeftJustify over Rect(ContentRect.Left + AlignOffset, ...)
      (tyControls.Edit.pas:1928) and keeps its caret and selection band on that same offset.
      Flip that alignment without moving the slot and the glyphs jump to the far edge while
      the caret stays put -- paint and hit test disagreeing, which is the exact defect this
      codebase keeps digging out. So a control opts in only once its GEOMETRY mirrors too,
      and `grep -n "BeginPaint(.*IsRightToLeft"` is the honest list of which ones do. }
    procedure BeginPaint(ACanvas: TCanvas; const ARect: TRect; APPI: Integer;
      ARightToLeft: Boolean = False);
    { 画到**调用方提供**的位图上,EndPaint 只 blit 不释放,也不预先清空。
      给需要跨帧复用表面的调用方用(网格的滚动脏区重绘)。 }
    procedure BeginPaintOn(ACanvas: TCanvas; const ARect: TRect; APPI: Integer;
      ABmp: TBGRABitmap; ARightToLeft: Boolean = False);
    { Which way this frame reads. Exposed because a DrawContent override receives the
      painter but not the control (TTyGlyphButtonBase.DrawContent), and asking the painter
      guarantees the slot it lays out agrees with the direction the text was armed with. }
    property RightToLeft: Boolean read FRightToLeft;
    procedure EndPaint;
    function Scale(ALogical: Integer): Integer;
    function Unscale(ADevice: Integer): Integer;
    function MeasureText(const AText, AFontName: string; AFontSizeLogical, AWeight: Integer): TSize;
    procedure FillBackground(const ARect: TRect; const AFill: TTyFill; ARadiusLogical: Integer); overload;
    procedure FillBackground(const ARect: TRect; const AFill: TTyFill; const ACorners: TTyCorners); overload;
    procedure StrokeBorder(const ARect: TRect; ARadiusLogical, AWidthLogical: Integer; AColor: TTyColor); overload;
    procedure StrokeBorder(const ARect: TRect; const ACorners: TTyCorners; AWidthLogical: Integer; AColor: TTyColor); overload;
    { A rounded body that carries a triangular POINTER out of one of its sides, filled and
      stroked as ONE closed path.

      WHY this exists rather than a rect plus a triangle: drawn as two shapes, the body's own
      border runs straight across the pointer's base, so the wedge reads as a separate sliver
      stuck onto a closed box -- the seam TTyBalloonHint and TTyPopover both documented as a
      known cosmetic. One path has no interior edge to stroke, and the pointer's two slanted
      sides get the border they were missing.

      ABody      the body, DEVICE px. The pointer stands OUTSIDE this rect.
      ACorners   the body's corner radii, LOGICAL px (scaled here, as StrokeBorder does).
      ATipPos    the apex ALONG the pointer's side, device px: x for tpsTop/tpsBottom, y for
                 tpsLeft/tpsRight.
      AHalfBase  half the pointer's base; AHeight how far the apex stands off the body edge.
      ABorderWidthLogical <= 0 (or a fully transparent colour) fills only.

      Fill and stroke are built from DIFFERENT rects, matching the rest of the painter: the
      fill covers the body verbatim, the stroke rides an inset centreline (Left+w/2 ..
      Right-1-w/2) exactly like StrokeBorder, so a bordered balloon lines up with every other
      bordered control. The pointer is TRANSLATED with that inset, never rescaled, so its
      slope is identical in both passes. }
    procedure FillPointerShape(const ABody: TRect; const ACorners: TTyCorners;
      ASide: TTyPointerSide; ATipPos, AHalfBase, AHeight: Integer;
      AFillColor, ABorderColor: TTyColor; ABorderWidthLogical: Integer);
    { v3/B2: a crisp, square, two-tone 3D bevel. The top+left edges get ATLColor and the
      bottom+right get ABRColor (light/dark for outset; swapped for inset). Corners: the
      light L-shape wins the shared corners. AWidthLogical is the (logical-px) edge width. }
    procedure DrawEdge(const ARect: TRect; AWidthLogical: Integer; ATLColor, ABRColor: TTyColor);
    { v3/C5: blit a pre-rendered glyph bitmap centered in ARect (used for icon-font glyph
      overrides; a nil/empty bitmap draws nothing). }
    procedure DrawGlyphBitmap(const ARect: TRect; ABmp: TBGRABitmap);
    procedure DropShadow(const ARect: TRect; ARadiusLogical: Integer; AColor: TTyColor; ABlurLogical: Integer; const AOffsetLogical: TPoint);
    { AMultiLine (default False = every existing caller, byte-identical) opts into honouring
      the line breaks the AUTHOR wrote into the caption: without it the text path forced
      SingleLine, so Caption := '你好'#13#10'世界' drew as one run on every control in the
      library. The block is laid out line by line — each line box ALineHeightLogical tall
      (logical px, 0 = the font's own line box) — and the WHOLE block is then anchored by
      AVAlign, the way a paragraph moves as one thing rather than each line centering itself.
      A caption with no break in it falls through to the single-line path unchanged, so
      turning the flag on costs nothing until there IS a break.
      AMnemonicPos is honoured on that single-line fall-through only: the index counts into
      the whole caption, and mapping it onto a line is the caller's knowledge, not ours. }
    procedure DrawText(const ARect: TRect; const AText, AFontName: string; AFontSizeLogical, AWeight: Integer; AColor: TTyColor; AHAlign: TAlignment; AVAlign: TTextLayout; AEllipsis: Boolean; AMnemonicPos: Integer = 0; ASmallCrisp: Boolean = False; AMultiLine: Boolean = False; ALineHeightLogical: Integer = 0);
    { --- Where a character IS, once bidirectional reordering has moved it ---------------

      These two answer, for the SAME rectangle and font DrawText would use, the two questions
      a text-editing control has to answer: "where do I put the caret for codepoint N" and
      "which codepoint did the user click on". They are exposed because the answer stops
      being derivable from a prefix sum the moment the text is bidirectional: TTyEdit builds
      cumulative codepoint widths in STRING order (MeasureCodepointWidths), which is exactly
      right for Latin and CJK and simply untrue for Arabic or Hebrew, where the caret between
      two logically adjacent codepoints can be at two different places on screen.

      NOTHING IN THIS LIBRARY CALLS THEM YET. TTyEdit still walks its own prefix sum, so an
      Arabic string in an edit now DRAWS correctly and still SELECTS in logical order --
      caret and click-to-position land on the wrong glyph. Wiring the edits up is a separate
      job; this is the seam it needs, put here rather than in a control so that the caret and
      the glyphs are computed by one piece of code.

      Cost: each call builds and lays out a TBidiTextLayout, so they are per-click / per-key
      operations, not per-frame ones. Ask TyTextHasRTL first and keep the cheap prefix sum
      when it says no.

      ACharIndex is a 0-based CODEPOINT index (not a byte offset), 0..codepoint count. }
    function TextCaretX(const ARect: TRect; const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AHAlign: TAlignment; ACharIndex: Integer): Integer;
    { The 0-based codepoint index a click at device-x AX selects. Rounds to the nearer
      character boundary, which is what a text cursor does. }
    function TextCharIndexAtX(const ARect: TRect; const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AHAlign: TAlignment; AX: Integer): Integer;
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

{ The height, in DEVICE PIXELS, of a theme font size at APPI -- the character (em) height, the
  number BGRA calls FontHeight and LCL calls a NEGATIVE Font.Height. The ONE place a font size
  becomes pixels: the drawing side and the measuring side both take it from here, because they
  did not use to, and that was the HiDPI defect reported as ACTom/TyControls#2.

  Drawing always computed exactly this. Measuring wrote `Font.Size := MulDiv(size, APPI, 96)`
  instead -- POINTS, which an LCL TFont turns into pixels with ITS OWN PixelsPerInch, and a
  freshly created TBitmap's font is born at the SCREEN's PPI (font.inc, TFont.Create). So the
  PPI went in twice. Measured, for a 9px theme size:

      screen PPI   drawn   measured
          96         12       12      the two agree, which is what hid it
         144         18       28      150%: line pitch and wrap width 1.5x too large
         168         21       37      175%: every size floor 1.75x too large
          72         12        9      the headless test runner: 25% too SMALL

  A pixel height has no PPI left in it to get wrong. }
function TyFontHeightPx(AFontSizeLogical, APPI: Integer): Integer;

// Shared font setup so text measurement (in controls) matches text drawing
// (in TTyPainter.DrawText) exactly: same BGRA engine, same height semantics.
procedure TyConfigureTextFont(ABmp: TBGRABitmap; const AFontName: string;
  AFontSizeLogical, AWeight, APPI: Integer);

{ How TEXT is rasterized on this widgetset -- the one answer, for every surface that draws
  words (the painter, the HTML label). Icons drawn from an icon font are pictures, not text,
  and keep their own supersampled quality. See the implementation for why each branch. }
function TyTextFontQuality: TBGRAFontQuality;

{ Put the library's text renderer on ABmp. On Win32 that is a renderer that draws text the
  way Windows lays it out and shapes it -- see TTyGdiTextRenderer; elsewhere it leaves BGRA's
  own. TyConfigureTextFont calls it, so every bitmap configured for text has it; a surface
  that configures a font by hand must call it too. }
procedure TyUseTextRenderer(ABmp: TBGRABitmap);
{ FOR THE TESTS: GDI bitmaps the Win32 text renderer has made or grown (it keeps one); 0
  elsewhere. }
function TyGdiTextBitmapsMade: Integer;
{ FOR THE TESTS, pure queries (0 / False elsewhere than Win32): the kept bitmap's handle
  and size (0 when there is none); the bitmaps made for one run only (another thread's
  run, a run too big to keep one for); the runs whose coverage went through a whole
  conversion to BGRA instead of being read off the DIB. }
function TyGdiTextKeptBitmapForTest(out AWidth, AHeight: Integer): THandle;
function TyGdiTextOneOffBitmapsForTest: Integer;
function TyGdiTextConversionsForTest: Integer;
{ FOR THE TESTS: let go of the kept bitmap (the next run makes a new one); send every run
  through the conversion (the path a bitmap that is not a DIB takes). }
procedure TyGdiTextResetForTest;
procedure TyGdiTextForceConversionForTest(AOn: Boolean);

// Resolves the concrete font name to use: the style's font-family if set,
// otherwise the TyFallbackFontName (when non-empty). Both BGRA config and the
// few LCL-canvas caption-width measures (GroupBox/TabControl) go through this so
// measured width matches drawn glyphs even when the theme sets no font-family.
function TyEffectiveFontName(const AName: string): string;
{ The size a measurement/draw will really use: the caller's, or TyFallbackFontSize when the
  caller has none (a theme rule that omitted font-size). Named because THREE places applied
  this same two-line rule -- both font-configuration procedures and, since the measurement
  memo landed, its key -- and a near-copy is how a key stops agreeing with the thing it
  keys. It matters that it is one function: TyFallbackFontSize is rewritten from
  --font-size-base on every theme apply, so a key that computed it differently from the
  measurement would serve a pre-switch width. }
function TyEffectiveFontSizeLogical(AFontSizeLogical: Integer): Integer;
{ Greedy line wrap that understands both scripts. Western words break at spaces (runs
  collapse to one space); CJK text carries no spaces, so each ideograph / kana / hangul
  syllable is its own break opportunity — without this a Chinese run is one unbreakable
  word and overflows a narrow box instead of wrapping. Walks UTF-8 by codepoint so a
  multi-byte glyph is never split. ACanvas must already carry the target font so TextWidth
  measures the drawn glyphs. Shared by TTyLabel and TTyNotification. }
procedure TyWrapTextCJK(const AText: string; AMaxWidthPx: Integer;
  ACanvas: TCanvas; ALines: TStrings);
{ True for codepoints that participate in inter-character line breaking: Han, kana, hangul,
  bopomofo, CJK symbols/punctuation and the fullwidth forms. This is the classifier
  TyWrapTextCJK breaks on (each such glyph is its own wrap atom); exported so other wrap
  implementations (TTyMemo's visual-row builder) break at the same codepoints. }
function TyIsCJKCodepoint(AValue: Cardinal): Boolean;
{ Split AText on the line breaks the author wrote — CR, LF and CRLF alike — keeping a blank
  line between paragraphs as content and never returning nothing (an empty caption is one
  empty line, so it still measures as one line tall).
  Factored OUT of TyWrapTextCJK rather than written beside it: the wrapping path and the
  no-wrap multi-line path must agree on what a line break is, and two copies of the split
  would eventually stop agreeing. }
procedure TySplitTextLines(const AText: string; ALines: TStrings);
{ Put the font a resolved style asks for onto a MEASUREMENT canvas: the effective family
  (theme font-family, else TyFallbackFontName), the pixel height TyFontHeightPx gives the
  drawing side too, bold above weight 600.
  EVERY caption measurement on an LCL canvas goes through here -- the twelve units that
  used to carry their own copy of these lines now call it -- and tests/test.dpi.measurefont
  scans source/ so that a copy cannot come back: a copy is how the measuring font and the
  drawn font came to disagree at every PPI but 96. }
procedure TyConfigureMeasureFont(ACanvas: TCanvas; const AFontName: string;
  AFontSizeLogical, AWeight, APPI: Integer);
{ The font's own line box on an already-configured canvas. Measured from a fixed reference
  pair ('Ag' — an ascender and a descender) and never from the caption, so an empty caption
  and a caption of digits come out the same height, and floored at 1 so a degenerate font
  cannot make a block zero-tall. }
function TyNaturalLineHeight(ACanvas: TCanvas): Integer;
{ Measure a caption BLOCK: width = the widest line, height = line count x line height.
  - AWrapWidthPx > 0 also wraps to that width (CJK-aware, TyWrapTextCJK); <= 0 honours only
    the breaks the author wrote.
  - ALineHeightLogical is the theme's --line-height in LOGICAL px; 0 = the font's natural
    line box, which is why adding the token moves nothing until a theme sets it. Resolve it
    with TyLineHeight(ActiveController) — the controller lives a unit up from here.
  This is the measurement a size FLOOR is built from: a control's minimum height is this
  height plus its style's vertical padding, because the font and the padding are what decide
  whether the ink fits, not the --control-height the theme asked for. Factored out of
  TTyLabel.MeasureCaption (which now calls it) so every control measures a caption the same
  way instead of each carrying its own near-copy. }
procedure TyMeasureTextBlock(const AText, AFontName: string;
  AFontSizeLogical, AWeight, APPI, AWrapWidthPx, ALineHeightLogical: Integer;
  out AWidthPx, AHeightPx: Integer);
{ The width the RENDERER reports for one line of text -- the exact number DrawTextLine's
  ellipsis test compares the content box against.

  WHY THIS IS NOT TyMeasureTextBlock. That one measures on an LCL TBitmap.Canvas; the text
  is DRAWN on a TBGRABitmap. They are two rasterisers and they round differently: measured
  on this machine at the demo's own font, "Open" comes out 32 on both, but "New" is 26 by
  the canvas and 27 by the renderer. One pixel is enough. A control that builds its size
  floor from the canvas measurement alone sizes its content box to exactly the canvas
  width, the renderer then finds itself one pixel over, and the caption the button JUST
  SIZED ITSELF FOR is ellipsised -- the demo tool bar's AutoSize '&New' rendered "Ne...".
  Which captions get hit is pure luck, which is why it looked like a translation bug.

  So: any control whose size floor feeds a clip must take the LARGER of the two. }
function TyMeasureRenderedTextWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight, APPI: Integer): Integer;

{ ===== The caption-measurement memo (af881) ==================================
  Both measurement functions above are memoised. This block is the ARGUMENT that the
  memo cannot go stale; read it before changing either of them, because the risk here
  was never performance, it was staleness -- a theme change reaches these controls as a
  bare Invalidate, so a memo keyed on too little silently keeps the previous theme's
  width, which is precisely the ellipsised-toolbar-button defect (memory/
  skin-variance-breaks-fixed-widths) that those Invalidate overrides exist to prevent.

  WHY IT IS WORTH THE RISK. plans/2026-08-08-permonitor-dpi.md §2e measured a 60-control
  form crossing 96->240 DPI: caption re-measurement is 51-57% of the synchronous
  WM_DPICHANGED pass, several hundred calls at ~0.44-0.80 ms each, and linear in control
  count. Nothing else in the pass comes close. §2f is what this memo then did to that.

  THE ENUMERATION -- every input the measured value depends on, and where it is keyed:

    1. AText                        parameter, in the key verbatim
    2. AFontName                    parameter -- NOT keyed raw; see (8)
    3. AFontSizeLogical             parameter -- NOT keyed raw; see (9)
    4. AWeight                      parameter, keyed RAW (see the note below)
    5. APPI                         parameter, in the key
    6. AWrapWidthPx                 parameter, in the key (block measure only --
                                    it selects TyWrapTextCJK over TySplitTextLines)
    7. ALineHeightLogical           parameter, in the key (block measure only)
    8. TyFallbackFontName  GLOBAL   folded: the key carries TyEffectiveFontName(AFontName),
                                    which is the name the font is actually configured with.
                                    The controller writes this global once from
                                    Screen.SystemFont (tyControls.Controller.pas:210).
    9. TyFallbackFontSize  GLOBAL   folded: the key carries the size AFTER the <=0
                                    fallback. This global is rewritten from
                                    --font-size-base on EVERY theme apply
                                    (tyControls.Controller.pas:602), so keying the raw
                                    parameter would be a genuine theme-staleness hole.
   10. the process font registry     NOT keyable -- see TyInvalidateTextMeasureCache.
   11. the widgetset text engine     compile-time -- TyTextFontQuality picks the
                                    rasterizer per widgetset (fqSystem on Win32,
                                    fqSystemClearType elsewhere). Constant per
                                    binary, so it cannot make an entry stale.
   12. Screen.PixelsPerInch          NOT AN INPUT ANY MORE. It used to reach the LCL path
                                    through TFont.Size->Height on the scratch TBitmap,
                                    whose font is born at the screen's PPI -- and that was
                                    the HiDPI defect of ACTom/TyControls#2, not a harmless
                                    process constant. TyConfigureMeasureFont now writes a
                                    pixel Height, which has no PPI left in it;
                                    tests/test.dpi.measurefont varies ScreenInfo to pin it.
                                    (The §5 latch in the DPI plan is a different path and
                                    still reads it -- one layer BELOW this library.)

  FOLD OR KEY RAW -- the rule applied above, stated so the next edit follows it: key the
  RAW parameter when the parameter alone determines what the font engine is configured
  with; fold to the EFFECTIVE value when a global gets a vote. (8) and (9) are folded for
  that reason. (4) is deliberately kept RAW even though only the AWeight>=600 bold test is
  read today: keying the derived boolean would be correct-but-clever, and would rot the
  instant a caller starts honouring real weights. Raw costs only hit rate.

  NOT IN THE KEY, DELIBERATELY: the theme version. It would be redundant -- items 2,3,4,6,7
  ARE the theme's font decision, passed by value by the caller that resolved them, and 8/9
  are folded. The controller drops the memo on a theme change anyway (belt and braces, and
  TyTextMeasureCacheDropsOnThemeChange pins that wiring), but the key is what makes it
  SAFE: a per-control font override that moves no theme version still changes the key.

  THE MEMO IS NOT THREAD-SAFE, exactly like TTyStyleModel's resolve cache. Both are
  reached only from control layout and paint, which are main-thread by LCL contract. }

{ Drop every memoised measurement. Call this after doing anything that changes what a
  font NAME resolves to inside the process -- which is item (10) of the enumeration above
  and the one dependency that is genuinely not observable at measure time: registering a
  font file makes a family that previously fell back to a default suddenly real, and every
  measurement taken before that is wrong by exactly the difference between the two faces.
  TTyIconFont.LoadFontFile / UnloadFontFile (tyControls.IconFont.pas:240) is the library's
  own instance of this and does NOT yet call it -- see the plan's §2f follow-up. Also
  exposed so an application that loads fonts by its own route has a supported way to say so. }
procedure TyInvalidateTextMeasureCache;
{ Memo counters, for the A/B in the plan and for the tests that pin the invalidation
  wiring (an entry count of 0 right after a theme switch is what proves the hook fired --
  a value assertion alone cannot tell "dropped and recomputed" from "never cached").
  AEntries is both caches' live entries; ResetStats zeroes the counters, not the caches. }
procedure TyTextMeasureCacheStats(out AHits, AMisses: Int64; out AEntries: Integer);
procedure TyResetTextMeasureCacheStats;

{ The prefix the ellipsis fitter uses when it has narrowed the text to ACharCount CHARACTERS.
  A named function purely so the invariant is testable: the version this replaced shortened by
  one BYTE, which cuts a three-byte CJK character in half. The headless BGRA path silently
  swallows the stray byte, so a pixel comparison cannot see it -- the real GUI draws a
  replacement glyph, which is what the maintainer saw. Assert the string, not the pixels. }
function TyEllipsisPrefix(const AText: string; ACharCount: Integer): string;

{ What single-line drawing shows of AText: up to its first line break, with '...' when there was
  more. BGRA strips CR/LF before it measures or draws, so a multi-line text drawn on one line used
  to come out with its lines glued together ("first linesecond line..."). A text without a break
  comes back unchanged. }
function TySingleLineText(const AText: string): string;

{ AText fitted into AMaxWidthPx on ABmp's current font, the way DrawText fits a caption: whole if
  it fits, else the longest prefix that fits with '...' after it (one codepoint at the least). A
  text with a line break shows only its first line, with '...' (TySingleLineText). The one fit
  DrawText and the grid share.

  It used to cut one codepoint at a time and measure the whole remaining prefix each time --
  quadratic in the text's length, with a bitmap and a GDI layout behind every measurement. A
  300-line script in a tree cell (about 12k characters) took long enough to freeze the tree
  (#18). Widths only grow with the prefix, so a binary search finds the same cut in about a
  dozen measurements. }
function TyEllipsisFit(ABmp: TBGRABitmap; const AText: string; AMaxWidthPx: Integer): string;
{ Clamp a device-px corner radius to half the shorter side of a WxH rect, so an oversized
  "pill" radius (e.g. border-radius:100 on a short progress track) renders as a rounded pill
  instead of overshooting the corner arcs into a pointed lens. Exposed for tests. }
function TyClampRadiusPx(ARadiusPx, AWidthPx, AHeightPx: Integer): Integer;
{ True when AText contains at least one codepoint from a right-to-left script -- Hebrew,
  Arabic, Syriac, Thaana, N'Ko, Samaritan, Mandaic, Adlam and the Arabic presentation forms
  -- or an explicit right-to-left mark / embedding / override.

  THIS IS THE FAST-PATH GATE, and it is the reason bidirectional support costs the common
  case nothing. Every one of the 146 DrawText call sites in this library passes through it,
  and all but a vanishing few pass Latin or CJK; those must keep taking the single-TextRect
  path they have always taken, because building a TBidiTextLayout per caption per frame is
  the same shape of mistake that once cost TTyMemo half a second per keystroke.

  So the scan is arranged to be cheap in exactly the cases that are common: an ASCII byte is
  one compare, and a non-ASCII lead byte outside the handful that can possibly BEGIN a
  right-to-left codepoint is one set test -- CJK ($E4..$E9) and Cyrillic/Greek ($D0..$D5)
  never get decoded at all.

  Measured on Windows, 2e6 calls each: 24-32 ns for a 14-byte Latin caption, 24 ns for a
  15-byte Chinese one, 227 ns for a 108-byte sentence. The draw it guards, on the same
  machine and in the same run, costs 1.5 ms for a small 11 px label and 11 ms for a 24 px
  one -- so the gate is four to five orders of magnitude below the thing it is protecting,
  and a caption that does NOT need BiDi pays only that. A caption that DOES pays about
  2.1 ms more for the layout (roughly four bare text measurements), once per draw.

  Conservative by design: it answers True for the unassigned holes inside those blocks too.
  A false positive costs one correct-but-slower layout; a false negative would draw the text
  backwards, so test.bidi pins the scan against BGRA's own GetUnicodeBidiClass tables. }
function TyTextHasRTL(const AText: string): Boolean;

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

  { ===== af881: the caption-measurement memo ==================================
    Off switch, for two reasons and no others:
      - it makes the A/B honest. The hit-rate and timing numbers in
        plans/2026-08-08-permonitor-dpi.md §2f were taken by flipping THIS, in ONE
        binary, in one load window -- not by building two binaries, which on this
        host varies more than the effect being measured;
      - an application that registers fonts at run time by some route the library
        cannot see (see TyInvalidateTextMeasureCache) can turn the memo off rather
        than reason about when to drop it.
    Flipping it to False never changes an answer, only how long it takes. }
  TyTextMeasureCacheEnabled: Boolean = True;

implementation

uses
  LCLIntf, BGRAText;

function TyEffectiveFontName(const AName: string): string;
begin
  if (AName = '') and (TyFallbackFontName <> '') then
    Result := TyFallbackFontName
  else
    Result := AName;
end;

function TyEffectiveFontSizeLogical(AFontSizeLogical: Integer): Integer;
begin
  if AFontSizeLogical <= 0 then
    Result := TyFallbackFontSize
  else
    Result := AFontSizeLogical;
end;

{ ===== The caption-measurement memo -- storage ===============================
  See the long block at the TyInvalidateTextMeasureCache declaration for the staleness
  argument. This half is only mechanics. }
type
  { One memoised block measurement. BOXED rather than packed into Objects[] as a PtrInt:
    two Integers do not fit a 32-bit pointer and this unit compiles for 32-bit targets.
    TyMeasureRenderedTextWidth returns ONE Integer, so its cache stashes it in Objects[]
    directly, the way TTyStyleModel's FMetricCache does. }
  TTyTextBlockMeasure = class
    W, H: Integer;
  end;

const
  { A cap, because the key contains the CAPTION: a caller that measures a stream of
    distinct strings (a data grid walking a column) would otherwise grow this without
    bound for the rest of the process. On overflow the cache is CLEARED rather than
    evicted least-recently-used -- an LRU needs a second index and a recency field to
    save an allocation on a path that is already doing font metrics, and clearing keeps
    the only invariant that matters (every live entry was computed under the CURRENT
    globals) trivially true. }
  TY_TEXT_MEASURE_CACHE_MAX = 4096;

var
  GBlockCache: TStringList = nil;    // sorted; Objects[] OWN TTyTextBlockMeasure
  GRenderCache: TStringList = nil;   // sorted; Objects[] hold a plain Integer width
  GMeasHits: Int64 = 0;
  GMeasMisses: Int64 = 0;

function TyTextMeasureCacheList(var AList: TStringList): TStringList;
begin
  if AList = nil then
  begin
    AList := TStringList.Create;
    AList.CaseSensitive := True;     // font names and captions are case-significant
    AList.Sorted := True;            // IndexOf is a binary search, not a linear scan
    AList.Duplicates := dupIgnore;
  end;
  Result := AList;
end;

{ An INJECTIVE encoding of the key tuple -- distinct inputs can never collide onto one
  string. That is not pedantry: memory/index-keyed-string-sort-trap is this repo's record
  of a string key that silently merged two different things and destroyed data. The
  numeric fields are fixed-arity and delimited; the FONT NAME is length-prefixed (so a
  name containing the delimiter cannot eat into the next field); and the CAPTION is last,
  so nothing follows it that its own content could be mistaken for. }
function TyTextMeasureKey(const AText, AEffFontName: string;
  AEffFontSizeLogical, AWeight, APPI, AWrapWidthPx, ALineHeightLogical: Integer): string;
begin
  Result := IntToStr(AEffFontSizeLogical) + '|' + IntToStr(AWeight) + '|'
    + IntToStr(APPI) + '|' + IntToStr(AWrapWidthPx) + '|'
    + IntToStr(ALineHeightLogical) + '|' + IntToStr(Length(AEffFontName)) + '|'
    + AEffFontName + AText;
end;

procedure TyInvalidateTextMeasureCache;
var
  i: Integer;
begin
  if GBlockCache <> nil then
  begin
    for i := 0 to GBlockCache.Count - 1 do
      GBlockCache.Objects[i].Free;
    GBlockCache.Clear;
  end;
  if GRenderCache <> nil then
    GRenderCache.Clear;             // Objects[] here are plain ints, nothing to free
end;

procedure TyTextMeasureCacheStats(out AHits, AMisses: Int64; out AEntries: Integer);
begin
  AHits := GMeasHits;
  AMisses := GMeasMisses;
  AEntries := 0;
  if GBlockCache <> nil then Inc(AEntries, GBlockCache.Count);
  if GRenderCache <> nil then Inc(AEntries, GRenderCache.Count);
end;

procedure TyResetTextMeasureCacheStats;
begin
  GMeasHits := 0;
  GMeasMisses := 0;
end;

function TyTextHasRTL(const AText: string): Boolean;
const
  { The only UTF-8 LEAD bytes that can begin a right-to-left codepoint:
      $D6..$DF  ->  U+0580..U+07FF   Hebrew, Arabic, Syriac, Thaana, N'Ko
      $E0       ->  U+0800..U+0FFF   Samaritan, Mandaic, Arabic Extended-A/B
      $E2       ->  U+2000..U+2FFF   the RLM / RLE / RLO / RLI / FSI direction controls
      $EF       ->  U+F000..U+FFFF   Hebrew + Arabic presentation forms
      $F0       ->  U+10000..U+3FFFF Cypriot..Kharoshthi, Adlam, Arabic Mathematical
    Everything else -- and that is all of CJK, Cyrillic, Greek, Latin Extended -- is
    rejected on the lead byte alone, without decoding the codepoint. }
  RTL_LEADS = [$D6..$DF, $E0, $E2, $EF, $F0];
var
  i, n, len: Integer;
  b: Byte;
  u: LongWord;
begin
  n := Length(AText);
  i := 1;
  while i <= n do
  begin
    b := Byte(AText[i]);
    if b < $80 then                       // ASCII: the common case, one compare
    begin
      Inc(i);
      Continue;
    end;
    if (b and $E0) = $C0 then len := 2
    else if (b and $F0) = $E0 then len := 3
    else if (b and $F8) = $F0 then len := 4
    else begin Inc(i); Continue; end;     // stray continuation byte -- step, never spin
    if i + len - 1 > n then Break;        // truncated tail: nothing decodable left
    if not (b in RTL_LEADS) then
    begin
      Inc(i, len);
      Continue;
    end;
    case len of
      2: u := ((b and $1F) shl 6) or (Byte(AText[i + 1]) and $3F);
      3: u := ((b and $0F) shl 12) or ((Byte(AText[i + 1]) and $3F) shl 6)
              or (Byte(AText[i + 2]) and $3F);
    else
      u := ((b and $07) shl 18) or ((Byte(AText[i + 1]) and $3F) shl 12)
           or ((Byte(AText[i + 2]) and $3F) shl 6) or (Byte(AText[i + 3]) and $3F);
    end;
    if ((u >= $0590) and (u <= $08FF)) or            // Hebrew .. Arabic Extended-A
       (u = $200F) or (u = $202B) or (u = $202E) or  // RLM, RLE, RLO
       (u = $2067) or (u = $2068) or                 // RLI, FSI
       ((u >= $FB1D) and (u <= $FDFF)) or            // Hebrew + Arabic presentation forms A
       ((u >= $FE70) and (u <= $FEFF)) or            // Arabic presentation forms B
       ((u >= $10800) and (u <= $10FFF)) or          // Cypriot .. Manichaean .. Hanifi
       ((u >= $1E800) and (u <= $1EFFF)) then        // Mende, Adlam, Arabic Mathematical
      Exit(True);
    Inc(i, len);
  end;
  Result := False;
end;

{ Wraps ONE authored line (no CR/LF inside). ABase is ALines.Count at entry, so the
  "never return nothing" guard below is about THIS segment and not about lines an earlier
  segment already contributed. }
function TyEllipsisPrefix(const AText: string; ACharCount: Integer): string;
begin
  if ACharCount <= 0 then Exit('');
  Result := UTF8Copy(AText, 1, ACharCount);
end;

function TySingleLineText(const AText: string): string;
var
  i: Integer;
begin
  for i := 1 to Length(AText) do
    if (AText[i] = #13) or (AText[i] = #10) then
      Exit(Copy(AText, 1, i - 1) + '...');
  Result := AText;
end;

function TyEllipsisFit(ABmp: TBGRABitmap; const AText: string; AMaxWidthPx: Integer): string;
var
  line: string;
  cut: Boolean;
  i, n, lo, hi, mid, best: Integer;
begin
  Result := AText;
  if (ABmp = nil) or (AText = '') then Exit;
  line := AText;
  cut := False;
  for i := 1 to Length(AText) do
    if (AText[i] = #13) or (AText[i] = #10) then
    begin
      line := Copy(AText, 1, i - 1);
      cut := True;
      Break;
    end;
  if cut then
  begin
    { There is more than this line, so the ellipsis is always shown. }
    if line = '' then Exit('...');
    if ABmp.TextSize(line + '...').cx <= AMaxWidthPx then Exit(line + '...');
  end
  else
  begin
    if ABmp.TextSize(line).cx <= AMaxWidthPx then Exit(line);
    if UTF8Length(line) <= 1 then Exit(line);   // a lone codepoint is never ellipsised
  end;
  { The longest prefix of at most n-1 codepoints that fits with '...', and one codepoint when
    none does -- what the one-at-a-time loop found, top down. }
  n := UTF8Length(line) - 1;
  hi := n;
  if hi < 1 then hi := 1;
  lo := 1;
  best := 1;
  while lo <= hi do
  begin
    mid := (lo + hi) div 2;
    if ABmp.TextSize(TyEllipsisPrefix(line, mid) + '...').cx <= AMaxWidthPx then
    begin
      best := mid;
      lo := mid + 1;
    end
    else
      hi := mid - 1;
  end;
  Result := TyEllipsisPrefix(line, best) + '...';
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

  { The shared unit-level classifier (TyIsCJKCodepoint), aliased for brevity. }
  function IsCJKChar(AValue: Cardinal): Boolean;
  begin
    Result := TyIsCJKCodepoint(AValue);
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

procedure TySplitTextLines(const AText: string; ALines: TStrings);
begin
  ALines.Clear;
  if Pos(#10, AText) + Pos(#13, AText) = 0 then
  begin
    { No break at all — one line, even when the caption is empty. Returning an EMPTY list
      here would make an empty caption measure zero lines tall, and a control whose height
      floor is "lines x line height" would then be allowed to collapse. }
    ALines.Add(AText);
    Exit;
  end;
  ALines.Text := AText;         // splits on CR, LF and CRLF alike
  if ALines.Count = 0 then
    ALines.Add('');
end;

{ Greedy CJK-aware wrap of a whole caption.

  Authored line breaks come FIRST. The wrapper only ever knew about spaces and CJK codepoints,
  so a caption written with an explicit #13#10 in it came out as one run: TTyLabel with
  WordWrap on silently swallowed every line the author put there. TTyNotification looked
  correct only because its caller split the message on CR/LF before calling in -- doing it
  here makes that pre-split redundant rather than load-bearing, and fixes every other caller
  at the same time. The split itself is TySplitTextLines, shared with the no-wrap path.

  An empty segment is kept as an empty line: a blank line between paragraphs is content. }

function TyIsCJKCodepoint(AValue: Cardinal): Boolean;
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

procedure TyWrapTextCJK(const AText: string; AMaxWidthPx: Integer;
  ACanvas: TCanvas; ALines: TStrings);
var
  seg: TStringList;
  i: Integer;
begin
  ALines.Clear;
  seg := TStringList.Create;
  try
    TySplitTextLines(AText, seg);
    for i := 0 to seg.Count - 1 do
      if seg[i] = '' then
        ALines.Add('')
      else
        TyWrapSegmentCJK(seg[i], AMaxWidthPx, ACanvas, ALines, ALines.Count);
  finally
    seg.Free;
  end;
end;

function TyFontHeightPx(AFontSizeLogical, APPI: Integer): Integer;
begin
  Result := MulDiv(Round(AFontSizeLogical * 96 / 72), APPI, 96);
  { Never 0: an LCL Font.Height of 0 does not mean "invisible", it means "the default size",
    which would measure a caption nobody is going to draw. }
  if Result < 1 then Result := 1;
end;

procedure TyConfigureMeasureFont(ACanvas: TCanvas; const AFontName: string;
  AFontSizeLogical, AWeight, APPI: Integer);
begin
  // A missing font-size would measure at the canvas's own size, which is not what gets
  // drawn -- TyConfigureTextFont falls back the same way on the drawing side.
  AFontSizeLogical := TyEffectiveFontSizeLogical(AFontSizeLogical);
  ACanvas.Font.Name := TyEffectiveFontName(AFontName);
  { Height, in pixels, NEGATIVE (= character height, what BGRA's FontHeight means) -- never
    Size. Size is points, and the canvas font converts points with its own PixelsPerInch,
    which is the screen's: see TyFontHeightPx for what that did at 150% and 175%.
    Font.PixelsPerInch is deliberately left alone: TFont.SetPixelsPerInch RESCALES a non-zero
    Height, so touching it after this line would put the PPI back in a second time. }
  ACanvas.Font.Height := -TyFontHeightPx(AFontSizeLogical, APPI);
  if AWeight >= 600 then
    ACanvas.Font.Style := [fsBold]
  else
    ACanvas.Font.Style := [];
end;

function TyNaturalLineHeight(ACanvas: TCanvas): Integer;
begin
  Result := ACanvas.TextHeight('Ag');
  if Result < 1 then Result := 1;
end;

procedure TyMeasureTextBlock(const AText, AFontName: string;
  AFontSizeLogical, AWeight, APPI, AWrapWidthPx, ALineHeightLogical: Integer;
  out AWidthPx, AHeightPx: Integer);
var
  Meas: TBitmap;
  Lines: TStringList;
  i, w, lineH: Integer;
  key: string;
  idx: Integer;
  box: TTyTextBlockMeasure;
  cache: TStringList;
begin
  AWidthPx := 0;
  AHeightPx := 0;

  { The memo. The key is built from the EFFECTIVE font name and size -- the values the
    configuration below will really use -- because both fall back to a mutable global.
    TyFallbackFontSize in particular is rewritten from --font-size-base on every theme
    apply, so keying the raw parameter would serve a pre-switch width. The enumeration
    of every keyed and unkeyed input is at TyInvalidateTextMeasureCache.
    NOTE the two calls below still pass the RAW AFontName/AFontSizeLogical, so the
    fallback is applied by exactly the code it always was: if the key ever stopped
    folding, the measurement would NOT follow it, and the difference is a stale answer a
    test can see. Handing the effective values down instead would hide that. }
  key := '';
  if TyTextMeasureCacheEnabled then
  begin
    key := TyTextMeasureKey(AText, TyEffectiveFontName(AFontName),
      TyEffectiveFontSizeLogical(AFontSizeLogical), AWeight, APPI,
      AWrapWidthPx, ALineHeightLogical);
    cache := TyTextMeasureCacheList(GBlockCache);
    idx := cache.IndexOf(key);
    if idx >= 0 then
    begin
      Inc(GMeasHits);
      box := TTyTextBlockMeasure(cache.Objects[idx]);
      AWidthPx := box.W;
      AHeightPx := box.H;
      Exit;
    end;
    Inc(GMeasMisses);
  end;

  Meas := TBitmap.Create;
  Lines := TStringList.Create;
  try
    Meas.SetSize(1, 1);
    TyConfigureMeasureFont(Meas.Canvas, AFontName, AFontSizeLogical, AWeight, APPI);
    { The theme's line box wins when it set one, else the font's. Scaled here the same way
      the font size was, so a --line-height authored in logical px survives a HiDPI PPI. }
    if ALineHeightLogical > 0 then
      lineH := MulDiv(ALineHeightLogical, APPI, 96)
    else
      lineH := TyNaturalLineHeight(Meas.Canvas);
    if lineH < 1 then lineH := 1;

    if AWrapWidthPx > 0 then
      TyWrapTextCJK(AText, AWrapWidthPx, Meas.Canvas, Lines)
    else
      TySplitTextLines(AText, Lines);

    for i := 0 to Lines.Count - 1 do
    begin
      w := Meas.Canvas.TextWidth(Lines[i]);
      if w > AWidthPx then AWidthPx := w;
    end;
    AHeightPx := Lines.Count * lineH;
  finally
    Lines.Free;
    Meas.Free;
  end;

  if TyTextMeasureCacheEnabled then
  begin
    cache := TyTextMeasureCacheList(GBlockCache);
    if cache.Count >= TY_TEXT_MEASURE_CACHE_MAX then
      TyInvalidateTextMeasureCache;
    box := TTyTextBlockMeasure.Create;
    box.W := AWidthPx;
    box.H := AHeightPx;
    { AddObject on a sorted dupIgnore list DROPS a duplicate key and leaks the object it
      was handed, so check first. A duplicate cannot happen -- the miss above proved the
      key was absent and nothing re-entrantly measures between there and here -- but the
      cost of being wrong is a silent leak, and the cost of the guard is one search. }
    if cache.IndexOf(key) < 0 then
      cache.AddObject(key, box)
    else
      box.Free;
  end;
end;

function TyTextFontQuality: TBGRAFontQuality;
begin
  { Qt, GTK and Cocoa: the native text renderer (fqSystemClearType). fqFineAntialiasing renders
    BLANK on Qt/GTK (diagnostic on Windows+Qt6: fqFine=0 px vs fqSystemClearType=621), and on
    Cocoa it silently drops to single-pass fqSystem for text > ~13px (SYSTEM_RENDERER_IS_FINE, see
    DrawTextSupersampled below), so CJK came out jagged and thin. The native path is also the one
    that runs the OS font-substitution cascade a Latin UI font (macOS San Francisco) needs to
    fill CJK glyphs.

    Win32: fqSystem, which TTyGdiTextRenderer turns into ClearType's shapes laid down in grey
    -- see there. Rotated text is the one thing that renderer hands back to BGRA. }
  {$IF DEFINED(LCLQt5) or DEFINED(LCLQt6) or DEFINED(LCLGtk2) or DEFINED(LCLGtk3) or DEFINED(LCLCocoa)}
  Result := fqSystemClearType;
  {$ELSE}
  Result := fqSystem;
  {$ENDIF}
end;

{$IFDEF LCLWin32}
type
  { TEXT ON WINDOWS, AS WINDOWS DRAWS IT.

    Three ways to put a caption on a BGRA surface were tried against the text Windows draws in
    the same window, and each was wrong in its own way:

      fqFineAntialiasing   GDI at six times the size, box-filtered down. The hinting is done
                           for a font six times too big, so no stem lands on the pixel grid:
                           every stroke two grey pixels. Soft and light -- "blurry".
      fqSystem             GDI's grayscale antialiasing at the real size. Crisp, but GDI then
                           hints BOTH axes, and Microsoft YaHei's hinting is written for
                           ClearType, which hints only the vertical: strokes snap sideways to
                           whole pixels, their weights go uneven, the glyphs turn blocky.
                           "Ugly", and rightly.
      fqSystemClearType    the right shapes, but a SUBPIXEL mask: colour fringes on a coloured
                           or translucent surface, and BGRA's compositing of it both fringes
                           more and inks lighter than the OS's.

    What Windows draws is the third one's SHAPES -- hinted vertically only, so horizontal
    strokes are crisp and the glyph keeps its form -- at the weight ClearType gives them. This
    renderer draws exactly that: GDI renders the run in ClearType in the ink's polarity --
    dark ink black on white, light ink white on black -- the three subpixel coverages are
    averaged into one grey, and that grey is laid down in the ink colour with the same
    non-gamma blend GDI uses. The polarity is not a nicety: Windows weights the two
    differently under the user's ClearType contrast. At the default (1400) they cover within
    half a percent of each other; at 1200 a white-on-black line of 9pt Segoe UI inks 12% more
    than the black-on-white one, and light text drawn from the dark-on-light coverage came out
    a tenth lighter than the text Windows drew beside it.
    Measured on a line of 9pt YaHei: the ink it lays down is the ink native ClearType lays
    down (1403 against 1404 at 100%, 3697 against 3697 at 175%), and so is the share of solid
    pixels; there is no colour, so a transparent surface or an accent button is safe.

    Layout is GDI's own, and it is the layout the measuring side reports: the run is drawn by
    the very DrawText call BGRA measures it with (DT_CALCRECT dropped), on the same font in the
    same quality, so the kerning, the right-to-left reading and the mnemonic prefix a
    TextSize or TextFitInfo answer includes are in the glyphs, and a caret placed on measured
    advances sits on them. Not TCanvas.TextOut, which does not kern the pairs DrawText kerns;
    not TCanvas.TextRect, which silently renames an unnamed font 'default' -- a different
    face from the one measured, and a run a fifth wider than its caret positions. Rotated,
    textured and self-underlined text go to BGRA's own path. }
  TTyGdiTextRenderer = class(TLCLFontRenderer)
  private
    { ONE GDI bitmap the runs are drawn on, kept for every renderer (the main thread's):
      a run used to cost a fresh TBitmap and a whole-bitmap conversion to BGRA, about as
      much as drawing it. It grows in the direction a run needs, up to GdiKeptMaxPixels /
      GdiKeptMaxWidth; each run clears the part it uses and its
      coverage is read straight off the DIB. The counters are FOR THE TESTS. }
    class var GShot: TBitmap;
    class var GBitmapsMade, GOneOffs, GConversions: Integer;
    class var GForceConversion: Boolean;
  protected
    procedure UpdateFont; override;
    { The measuring side, answered for the run exactly as it is drawn. }
    function RunStyle(ARightToLeft, AShowPrefix: Boolean): TTextStyle;
    procedure InternalTextOutAngle(ADest: TBGRACustomBitmap; x, y: single;
      AOrientation: integer; sUTF8: string; c: TBGRAPixel; texture: IBGRAScanner;
      align: TAlignment; AShowPrefix: boolean = false; ARightToLeft: boolean = false); override;
  end;

  TTyCanvasAccess = class(TCanvas);
  TTyBitmapAccess = class(TBitmap);        { GetRawImageDescriptionPtr is protected }

const
  { The kept bitmap stays at most this big (24-bit: 12 MB); a run that would need more
    -- a very long unwrapped line, a huge title -- gets a bitmap of its own, freed after. }
  GdiKeptMaxPixels = 4 * 1024 * 1024;
  GdiKeptMaxWidth = 8192;

function TyGdiFlush: LongBool; stdcall; external 'gdi32' name 'GdiFlush';

function TTyGdiTextRenderer.RunStyle(ARightToLeft, AShowPrefix: Boolean): TTextStyle;
begin
  { BGRA's own Win32 run style (BGRADefaultTextOutStyle, which the unit does not export):
    the one its TextSize measures every unrotated run with. }
  FillChar(Result, SizeOf(Result), 0);
  Result.SingleLine := True;
  Result.Alignment := taLeftJustify;
  Result.Layout := tlTop;
  Result.RightToLeft := ARightToLeft;
  Result.ShowPrefix := AShowPrefix;
end;

procedure TTyGdiTextRenderer.UpdateFont;
begin
  inherited UpdateFont;
  { The measuring side reads this font too: TextSize and TextFitInfo must answer in the
    advances the drawing side lays the glyphs out with. }
  FFont.Quality := fqCleartypeNatural;
end;

procedure TTyGdiTextRenderer.InternalTextOutAngle(ADest: TBGRACustomBitmap; x, y: single;
  AOrientation: integer; sUTF8: string; c: TBGRAPixel; texture: IBGRAScanner;
  align: TAlignment; AShowPrefix: boolean; ARightToLeft: boolean);
var
  sz: TSize;
  ofsX: Single;
  ox, oy, mx, my, w, h, px, py, dy, cov, a: Integer;
  flags: Cardinal;
  r: TRect;
  tmp: TBitmap;
  shot: TBGRABitmap;
  row: PBGRAPixel;
  ink: TBGRAPixel;
  kept, lightInk: Boolean;
  ds: TDIBSection;
  bits, line: PByte;
  stride, bpp, nw, nh: Integer;
  bottomUp: Boolean;
begin
  if sUTF8 = '' then Exit;
  if (AOrientation mod 3600 <> 0) or (texture <> nil) or FOwnUnderline then
  begin
    inherited InternalTextOutAngle(ADest, x, y, AOrientation, sUTF8, c, texture, align,
      AShowPrefix, ARightToLeft);
    Exit;
  end;
  if c.alpha = 0 then Exit;
  { Light ink is drawn white on black, as Windows draws light text: see the class comment. }
  lightInk := (c.red * 30 + c.green * 59 + c.blue * 11) div 100 > 128;
  UpdateFont;
  sz := InternalTextSizeStyle(sUTF8, RunStyle(ARightToLeft, AShowPrefix), MaxLongint);
  if (sz.cx <= 0) or (sz.cy <= 0) then Exit;
  case align of
    taCenter: ofsX := sz.cx / 2;
    taRightJustify: ofsX := sz.cx;
  else
    ofsX := 0;
  end;
  { Rounded half up, as BGRA's own path places a run: a fractional pen position (a bidi
    layout advances by fractions) lands on the pixel it always did. }
  ox := Floor(x - ofsX + 0.5);
  oy := Floor(y + 0.5);
  { Room for what overhangs the advance box: an italic's lean, a swash, ClearType's bleed. }
  mx := sz.cy div 2 + 2;
  my := sz.cy div 4 + 2;
  w := sz.cx + 2 * mx;
  h := sz.cy + 2 * my;
  { The kept bitmap (GShot) grows in the direction a run needs more room and stays within
    GdiKeptMaxPixels / GdiKeptMaxWidth (it gives up height only to make room for width
    under that cap, never otherwise); only the w x h the run uses is
    cleared and read. A run too big for that, and a thread other than the main one, draw
    on a bitmap of their own, freed after, as every run once did. }
  kept := (GetCurrentThreadId = MainThreadID) and (w <= GdiKeptMaxWidth)
    and (Int64(w) * h <= GdiKeptMaxPixels);
  nw := 0;
  nh := 0;
  if kept then
  begin
    if GShot <> nil then
    begin
      nw := GShot.Width;
      nh := GShot.Height;
    end;
    { half again as much as asked, in the direction that is short: a line a little
      longer than the last does not reallocate, and a tall run after a wide one does not
      widen it }
    if nw < w then nw := Min(Max(w, nw + nw div 2), GdiKeptMaxWidth);
    if nh < h then nh := Max(h, nh + nh div 2);
    if Int64(nw) * nh > GdiKeptMaxPixels then
    begin
      { no room for the headroom: what the run needs (at most the width it has) }
      nh := Max(h, GdiKeptMaxPixels div nw);
      if Int64(nw) * nh > GdiKeptMaxPixels then
        kept := False;
    end;
  end;
  tmp := nil;
  shot := nil;
  try
    if kept then
    begin
      if GShot = nil then
      begin
        GShot := TBitmap.Create;
        GShot.PixelFormat := pf24bit;
        GShot.SetSize(nw, nh);
        Inc(GBitmapsMade);
      end
      else if (GShot.Width <> nw) or (GShot.Height <> nh) then
      begin
        GShot.SetSize(nw, nh);
        Inc(GBitmapsMade);
      end;
      tmp := GShot;
    end
    else
    begin
      tmp := TBitmap.Create;
      Inc(GOneOffs);
      tmp.PixelFormat := pf24bit;
      tmp.SetSize(w, h);
    end;
    if lightInk then tmp.Canvas.Brush.Color := clBlack else tmp.Canvas.Brush.Color := clWhite;
    tmp.Canvas.FillRect(0, 0, w, h);
    { A fresh canvas's font was born at the screen's PPI of the moment, and Assign takes
      the pixel height across only between equal PPIs (Size otherwise): the kept canvas
      is put back to that first, or a run at a changed screen PPI gets another height. }
    tmp.Canvas.Font.PixelsPerInch := ScreenInfo.PixelsPerInchY;
    tmp.Canvas.Font := FFont;
    TTyCanvasAccess(tmp.Canvas).RequiredState([csHandleValid, csFontValid]);
    SetBkMode(tmp.Canvas.Handle, TRANSPARENT);
    if lightInk then SetTextColor(tmp.Canvas.Handle, $FFFFFF) else SetTextColor(tmp.Canvas.Handle, 0);
    { The flags BGRA's BitmapTextExtentStyle measures RunStyle with, less DT_CALCRECT. }
    flags := DT_SINGLELINE or DT_NOCLIP;
    if ARightToLeft then flags := flags or DT_RTLREADING;
    if not AShowPrefix then flags := flags or DT_NOPREFIX;
    r := Rect(mx, my, w, h);
    tmp.Canvas.Changing;
    LCLIntf.DrawText(tmp.Canvas.Handle, PChar(sUTF8), Length(sUTF8), r, flags);
    tmp.Canvas.Changed;   // what TCanvas's own text calls do: the image is read back next
    { The coverage straight off the DIB section GDI drew into -- the bytes BGRA's
      conversion of the whole bitmap used to copy out, without the copy. The row length is
      the one GDI reports; the row order is LCL's own description of the DIB it made: GetObject
      answers a POSITIVE height in dsBmih as in dsBm even for the top-down DIB LCL makes
      (measured on Windows 10 19044), so the sign cannot tell. A bitmap that is not a 24-
      or 32-bit DIB has its w x h copied into a BGRA bitmap, as the conversion did. }
    bits := nil;
    stride := 0;
    bpp := 0;
    if (not GForceConversion) and (LCLIntf.GetObject(tmp.Handle, SizeOf(ds), @ds) = SizeOf(ds))
      and (ds.dsBm.bmBits <> nil) and ((ds.dsBm.bmBitsPixel = 24) or (ds.dsBm.bmBitsPixel = 32)) then
    begin
      TyGdiFlush;                          { GDI may still be batching the DrawText }
      bottomUp := TTyBitmapAccess(tmp).GetRawImageDescriptionPtr^.LineOrder = riloBottomToTop;
      bits := ds.dsBm.bmBits;
      bpp := ds.dsBm.bmBitsPixel div 8;
      stride := ds.dsBm.bmWidthBytes;
    end
    else
    begin
      Inc(GConversions);
      shot := TBGRABitmap.Create(w, h);
      shot.GetImageFromCanvas(tmp.Canvas, 0, 0);
    end;
    ink := c;
    for py := 0 to h - 1 do
    begin
      dy := oy - my + py;
      if (dy < ADest.ClipRect.Top) or (dy >= ADest.ClipRect.Bottom) then Continue;
      if bits <> nil then
      begin
        if bottomUp then
          line := bits + (ds.dsBm.bmHeight - 1 - py) * stride
        else
          line := bits + py * stride;
        row := nil;
      end
      else
      begin
        line := nil;
        row := shot.ScanLine[py];
      end;
      for px := 0 to w - 1 do
      begin
        if line <> nil then
          cov := (line[px * bpp] + line[px * bpp + 1] + line[px * bpp + 2]) div 3
        else
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
    if not kept then
      tmp.Free;
  end;
end;
{$ENDIF}

function TyGdiTextBitmapsMade: Integer;
begin
  {$IFDEF LCLWin32}
  Result := TTyGdiTextRenderer.GBitmapsMade;
  {$ELSE}
  Result := 0;
  {$ENDIF}
end;

function TyGdiTextKeptBitmapForTest(out AWidth, AHeight: Integer): THandle;
begin
  AWidth := 0;
  AHeight := 0;
  Result := 0;
  {$IFDEF LCLWin32}
  if TTyGdiTextRenderer.GShot = nil then Exit;
  AWidth := TTyGdiTextRenderer.GShot.Width;
  AHeight := TTyGdiTextRenderer.GShot.Height;
  Result := TTyGdiTextRenderer.GShot.Handle;
  {$ENDIF}
end;

function TyGdiTextOneOffBitmapsForTest: Integer;
begin
  {$IFDEF LCLWin32}
  Result := TTyGdiTextRenderer.GOneOffs;
  {$ELSE}
  Result := 0;
  {$ENDIF}
end;

function TyGdiTextConversionsForTest: Integer;
begin
  {$IFDEF LCLWin32}
  Result := TTyGdiTextRenderer.GConversions;
  {$ELSE}
  Result := 0;
  {$ENDIF}
end;

procedure TyGdiTextResetForTest;
begin
  {$IFDEF LCLWin32}
  FreeAndNil(TTyGdiTextRenderer.GShot);
  {$ENDIF}
end;

procedure TyGdiTextForceConversionForTest(AOn: Boolean);
begin
  {$IFDEF LCLWin32}
  TTyGdiTextRenderer.GForceConversion := AOn;
  {$ELSE}
  if AOn then ;
  {$ENDIF}
end;

procedure TyUseTextRenderer(ABmp: TBGRABitmap);
begin
  {$IFDEF LCLWin32}
  if not (ABmp.FontRenderer is TTyGdiTextRenderer) then
    ABmp.FontRenderer := TTyGdiTextRenderer.Create;
  {$ELSE}
  if ABmp = nil then ;
  {$ENDIF}
end;

procedure TyConfigureTextFont(ABmp: TBGRABitmap; const AFontName: string;
  AFontSizeLogical, AWeight, APPI: Integer);
begin
  // A missing font-size (0) would render invisible text; fall back to a visible default.
  AFontSizeLogical := TyEffectiveFontSizeLogical(AFontSizeLogical);
  ABmp.FontName := TyEffectiveFontName(AFontName);
  ABmp.FontHeight := TyFontHeightPx(AFontSizeLogical, APPI);
  ABmp.FontQuality := TyTextFontQuality;
  TyUseTextRenderer(ABmp);
  if AWeight >= 600 then ABmp.FontStyle := [fsBold] else ABmp.FontStyle := [];
end;

function TyMeasureRenderedTextWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight, APPI: Integer): Integer;
var
  Meas: TBGRABitmap;
  Lines: TStringList;
  i, w: Integer;
  key: string;
  idx: Integer;
  cache: TStringList;
begin
  Result := 0;
  if AText = '' then Exit;

  { Memoised on the same key shape as TyMeasureTextBlock minus the two block-only fields
    (this one neither wraps nor stacks lines), and for the same reasons -- see the
    enumeration at TyInvalidateTextMeasureCache. Kept a SEPARATE cache from the block one
    rather than a shared key namespace: the two answer different questions on different
    rasterisers (that is the whole point of this function's header comment), and one
    namespace would need a discriminator byte doing the same job with more ways to get it
    wrong. }
  key := '';
  if TyTextMeasureCacheEnabled then
  begin
    key := TyTextMeasureKey(AText, TyEffectiveFontName(AFontName),
      TyEffectiveFontSizeLogical(AFontSizeLogical), AWeight, APPI, 0, 0);
    cache := TyTextMeasureCacheList(GRenderCache);
    idx := cache.IndexOf(key);
    if idx >= 0 then
    begin
      Inc(GMeasHits);
      Exit(Integer(PtrInt(cache.Objects[idx])));
    end;
    Inc(GMeasMisses);
  end;

  { A 1x1 surface: TextSize asks the font, never the pixels, so the bitmap never has to be
    big enough to hold the string. Allocated per call for the same reason TyMeasureTextBlock
    allocates its TBitmap per call -- a cached one would carry the last caller's font across
    a theme switch, and this is a size-FLOOR path, not a per-frame paint path. }
  Meas := TBGRABitmap.Create(1, 1);
  Lines := TStringList.Create;
  try
    TyConfigureTextFont(Meas, AFontName, AFontSizeLogical, AWeight, APPI);
    { PER LINE, then the widest -- exactly as TyMeasureTextBlock does it, and for the same
      reason: DrawText renders an authored break as two lines, so the block is as wide as its
      widest line, not as wide as the two of them laid end to end. Measuring the raw string
      here reported '你好'+LineEnding+'你好' as 48 where one '你好' is 24, which is the width
      of a button that draws two 24px lines. }
    TySplitTextLines(AText, Lines);
    for i := 0 to Lines.Count - 1 do
    begin
      if Lines[i] = '' then Continue;
      w := Meas.TextSize(Lines[i]).cx;
      if w > Result then Result := w;
    end;
  finally
    Lines.Free;
    Meas.Free;
  end;
  if Result < 0 then Result := 0;

  if TyTextMeasureCacheEnabled then
  begin
    cache := TyTextMeasureCacheList(GRenderCache);
    if cache.Count >= TY_TEXT_MEASURE_CACHE_MAX then
      TyInvalidateTextMeasureCache;
    if cache.IndexOf(key) < 0 then
      cache.AddObject(key, TObject(PtrInt(Result)));
  end;
end;

function TyColorToBGRA(c: TTyColor): TBGRAPixel;
begin
  Result := BGRA(TyRedOf(c), TyGreenOf(c), TyBlueOf(c), TyAlphaOf(c));
end;

procedure TTyPainter.BeginPaint(ACanvas: TCanvas; const ARect: TRect; APPI: Integer;
  ARightToLeft: Boolean = False);
begin
  FCanvas := ACanvas;
  FRect := ARect;
  FRightToLeft := ARightToLeft;
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
  APPI: Integer; ABmp: TBGRABitmap; ARightToLeft: Boolean = False);
begin
  FCanvas := ACanvas;
  FRect := ARect;
  FRightToLeft := ARightToLeft;
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
  { Deliberately NOT routed through the bidi layout, unlike the drawing side. Reordering a
    line does not change how wide it is, and the widgetset's own measurement already accounts
    for Arabic shaping (a joined BEH+TEH measures 31 px against 46 for the two isolated
    forms) -- so the answer is already right, and building a TBidiTextLayout for each of the
    36 MeasureText call sites would buy nothing but cost. The one visible consequence: for a
    MIXED line the layout's own UsedWidth can exceed this by a pixel or two, because it sums
    per-run widths that were each rounded. The draw clips, so the effect is bounded there. }
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

procedure TTyPainter.FillPointerShape(const ABody: TRect; const ACorners: TTyCorners;
  ASide: TTyPointerSide; ATipPos, AHalfBase, AHeight: Integer;
  AFillColor, ABorderColor: TTyColor; ABorderWidthLogical: Integer);
var
  ctx: TBGRACanvas2D;
  w: Integer;
  half: Single;

  { Emit the closed outline into ctx: the body's four rounded corners, with the pointer
    spliced into ASide's straight run. AInset shifts every edge inward by that much (0 for
    the fill, half the line width for the stroke) and carries the pointer along with it. }
  procedure BuildPath(AInset: Single);
  var
    l, t, r, b, tp: Single;
    rTL, rTR, rBR, rBL, maxR: Integer;

    { Clamp one corner radius so two corners on the same side can never overlap. }
    function Corner(ALogical: Integer): Single;
    begin
      Result := TyClampRadiusPx(Scale(ALogical), Round(r - l), Round(b - t));
    end;

  begin
    l := ABody.Left + AInset;
    t := ABody.Top + AInset;
    r := ABody.Right - 1 - AInset;
    b := ABody.Bottom - 1 - AInset;
    if (r <= l) or (b <= t) then Exit;
    maxR := ACorners.TL;
    if ACorners.TR > maxR then maxR := ACorners.TR;
    if ACorners.BR > maxR then maxR := ACorners.BR;
    if ACorners.BL > maxR then maxR := ACorners.BL;
    rTL := Round(Corner(ACorners.TL)); rTR := Round(Corner(ACorners.TR));
    rBR := Round(Corner(ACorners.BR)); rBL := Round(Corner(ACorners.BL));
    if maxR = 0 then begin rTL := 0; rTR := 0; rBR := 0; rBL := 0; end;
    tp := ATipPos;

    ctx.beginPath;
    { Top edge, left to right. }
    ctx.moveTo(l + rTL, t);
    if ASide = tpsTop then
    begin
      ctx.lineTo(tp - AHalfBase, t);
      ctx.lineTo(tp, t - AHeight);
      ctx.lineTo(tp + AHalfBase, t);
    end;
    if rTR > 0 then ctx.arcTo(r, t, r, t + rTR, rTR) else ctx.lineTo(r, t);
    { Right edge, top to bottom. }
    if ASide = tpsRight then
    begin
      ctx.lineTo(r, tp - AHalfBase);
      ctx.lineTo(r + AHeight, tp);
      ctx.lineTo(r, tp + AHalfBase);
    end;
    if rBR > 0 then ctx.arcTo(r, b, r - rBR, b, rBR) else ctx.lineTo(r, b);
    { Bottom edge, right to left. }
    if ASide = tpsBottom then
    begin
      ctx.lineTo(tp + AHalfBase, b);
      ctx.lineTo(tp, b + AHeight);
      ctx.lineTo(tp - AHalfBase, b);
    end;
    if rBL > 0 then ctx.arcTo(l, b, l, b - rBL, rBL) else ctx.lineTo(l, b);
    { Left edge, bottom to top. }
    if ASide = tpsLeft then
    begin
      ctx.lineTo(l, tp + AHalfBase);
      ctx.lineTo(l - AHeight, tp);
      ctx.lineTo(l, tp - AHalfBase);
    end;
    if rTL > 0 then ctx.arcTo(l, t, l + rTL, t, rTL) else ctx.lineTo(l, t);
    ctx.closePath;
  end;

begin
  if FBmp = nil then Exit;
  ctx := FBmp.Canvas2D;
  BuildPath(0);
  ctx.fillStyle(TyColorToBGRA(AFillColor));
  ctx.fill;

  w := Scale(ABorderWidthLogical);
  if (w <= 0) or (TyAlphaOf(ABorderColor) = 0) then Exit;
  half := w / 2;
  { The pointer rides the SAME inset as the body edge, so the wedge is translated inward, not
    reshaped -- its two sides keep the slope the fill drew. }
  BuildPath(half);
  ctx.strokeStyle(TyColorToBGRA(ABorderColor));
  ctx.lineWidth := w;
  ctx.stroke;
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

function TTyPainter.LineBoxHeight(ALineHeightLogical: Integer): Integer;
begin
  if ALineHeightLogical > 0 then
    Result := Scale(ALineHeightLogical)
  else if FBmp <> nil then
    Result := FBmp.TextSize('Ag').cy   // same reference pair the measurer uses
  else
    Result := 0;
  if Result < 1 then Result := 1;
end;

procedure TTyPainter.DrawText(const ARect: TRect; const AText, AFontName: string; AFontSizeLogical, AWeight: Integer; AColor: TTyColor; AHAlign: TAlignment; AVAlign: TTextLayout; AEllipsis: Boolean; AMnemonicPos: Integer = 0; ASmallCrisp: Boolean = False; AMultiLine: Boolean = False; ALineHeightLogical: Integer = 0);
var
  Lines: TStringList;
  i, lineH, blockH, yOff, boxH: Integer;
  LineRect: TRect;
begin
  if FBmp = nil then
    Exit;
  if not AMultiLine then
  begin
    DrawTextLine(ARect, AText, AFontName, AFontSizeLogical, AWeight, AColor,
      AHAlign, AVAlign, AEllipsis, AMnemonicPos, ASmallCrisp);
    Exit;
  end;
  Lines := TStringList.Create;
  try
    TySplitTextLines(AText, Lines);
    if Lines.Count <= 1 then
    begin
      { Nothing to lay out: take the untouched single-line path, mnemonic underline and all,
        so opting into multi-line never changes how an ordinary caption is drawn. }
      DrawTextLine(ARect, AText, AFontName, AFontSizeLogical, AWeight, AColor,
        AHAlign, AVAlign, AEllipsis, AMnemonicPos, ASmallCrisp);
      Exit;
    end;
    // The line box has to be known before the block can be anchored, and it comes from the
    // font unless the theme overrode it -- so configure the font first, then ask.
    TyConfigureTextFont(FBmp, AFontName, AFontSizeLogical, AWeight, FPPI);
    lineH := LineBoxHeight(ALineHeightLogical);
    blockH := Lines.Count * lineH;
    boxH := ARect.Bottom - ARect.Top;
    { AVAlign anchors the WHOLE block, not each line — the way a paragraph moves as one
      thing. Never negative: a block taller than its box starts at the top and loses its
      tail, which is the same "the bottom is what disappears" behaviour a single clipped
      line has, rather than losing the first line instead. }
    case AVAlign of
      tlCenter: yOff := (boxH - blockH) div 2;
      tlBottom: yOff := boxH - blockH;
    else
      yOff := 0;   // tlTop
    end;
    if yOff < 0 then yOff := 0;
    for i := 0 to Lines.Count - 1 do
    begin
      LineRect := Rect(ARect.Left, ARect.Top + yOff + i * lineH,
        ARect.Right, ARect.Top + yOff + (i + 1) * lineH);
      if LineRect.Top >= ARect.Bottom then Break;
      { tlCenter INSIDE the line box: the block is already positioned, so each line only has
        to sit in the middle of its own box — which is where extra leading from a themed
        --line-height goes, half above and half below. }
      DrawTextLine(LineRect, Lines[i], AFontName, AFontSizeLogical, AWeight, AColor,
        AHAlign, tlCenter, AEllipsis, 0, ASmallCrisp);
    end;
  finally
    Lines.Free;
  end;
end;

procedure TTyPainter.DrawTextLine(const ARect: TRect; const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AColor: TTyColor; AHAlign: TAlignment;
  AVAlign: TTextLayout; AEllipsis: Boolean; AMnemonicPos: Integer; ASmallCrisp: Boolean);
var
  style: TTextStyle;
  s: string;
  full: TSize;
  px: TBGRAPixel;
  beforeW, charW, ux, uy, uth: Integer;
  rtl: Boolean;
begin
  if FBmp = nil then
    Exit;
  { MIRRORING, resolved once for all four ways out of this function: the supersampled
    twin below, style.Alignment, the mnemonic-underline case, and the bidi path's
    BuildLineLayout. AHAlign arrives LOGICAL (see BeginPaint) and leaves physical, so
    everything downstream of here reads a side, never a direction, and the three
    placements cannot drift apart. BidiFlipAlignment (controls.pp:2922) is a two-row
    lookup: left<->right, taCenter fixed. FRightToLeft = False is the identity row, which
    is why every existing caller stays byte-identical.

    Note this is layout direction, NOT script direction -- `rtl` just below is a different
    question (does the STRING carry right-to-left codepoints), answered per caption. An
    Arabic label on a left-to-right form still reorders its words; a Latin label on a
    right-to-left form still moves to the right edge. }
  AHAlign := BidiFlipAlignment(AHAlign, FRightToLeft);
  { Asked ONCE, of the caption rather than of the ellipsised prefix: this is the question
    "is this a bidirectional caption at all", and a truncation that happens to drop the last
    Arabic word does not turn it into a Latin one. Everything below reads the answer. }
  rtl := TyTextHasRTL(AText);
  {$IF defined(LINUX) or defined(DARWIN)}
  // On Linux/macOS, BGRABitmap's LCL renderer drops fqFineAntialiasing to single-pass
  // fqSystem for text taller than ~13px (bgratext.pas SYSTEM_RENDERER_IS_FINE), so small
  // bold glyphs come out soft/blurry -- unlike Windows, where it always supersamples. For
  // callers that ask for crisp small text (the button badge) we supersample ourselves. Skips
  // the ellipsis/mnemonic features (the badge uses neither); only compiled where it's needed,
  // so Windows/headless keep the exact original path (and the pixel goldens stay byte-identical).
  // Right-to-left text is skipped too: the supersampler is a bare TextRect at 3x, so it
  // carries the same implicit left-to-right paragraph base the ordinary path had. Legible
  // beats crisp, and the only caller (the button badge) draws digits.
  if ASmallCrisp and not AEllipsis and (AMnemonicPos = 0) and not rtl then
  begin
    DrawTextSupersampled(ARect, AText, AFontName, AFontSizeLogical, AWeight, AColor, AHAlign, AVAlign);
    Exit;
  end;
  {$ENDIF}
  px := TyColorToBGRA(AColor);
  TyConfigureTextFont(FBmp, AFontName, AFontSizeLogical, AWeight, FPPI);
  s := AText;
  if AEllipsis then
    { Cut by CODEPOINT, never by byte (a byte cut halves a CJK character and the renderer draws
      a '?'), and in a bounded number of measurements: see TyEllipsisFit. That is the one path
      nearly every control's text goes through -- title-bar captions, button labels, list rows,
      tab headers, tree cells. }
    s := TyEllipsisFit(FBmp, AText, ARect.Right - ARect.Left);
  if rtl then
  begin
    { The mnemonic is dropped for an ellipsised caption here for the same reason the legacy
      path drops it below: the underline would land on a '.' or on a glyph that moved. }
    if s = AText then
      DrawTextLineBidi(ARect, s, AColor, AHAlign, AVAlign, AMnemonicPos)
    else
      DrawTextLineBidi(ARect, s, AColor, AHAlign, AVAlign, 0);
    Exit;
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

function TTyPainter.BuildLineLayout(const ARect: TRect; const AText: string;
  AHAlign: TAlignment; AVAlign: TTextLayout): TBidiTextLayout;
var
  x, y, w, h: Integer;
begin
  Result := nil;
  if (FBmp = nil) or (AText = '') then Exit;
  { fbmAuto = resolve the paragraph direction from the first strong character, which is what
    "the user typed an Arabic sentence" means. Still deliberately NOT the control's BiDiMode:
    that one answers "which way does this FORM read", which is the question BeginPaint's
    ARightToLeft carries and AHAlign already encodes -- a different question from "which way
    does this SENTENCE read", and conflating them would swap the halves of a Latin caption on
    a right-to-left form. }
  Result := TBidiTextLayout.Create(FBmp.FontRenderer, AText);
  { AvailableWidth is deliberately LEFT UNSET (BGRA reads that as "infinite"), for two
    reasons that happen to be the same reason. It stops the layout from word-wrapping -- this
    is the SINGLE-line path, and the callers that wrap have already wrapped, CJK-aware, in
    TyWrapTextCJK. And it makes the layout's own box exactly as wide as the text, so its
    ParagraphAlignment has nothing left to do and cannot quietly right-align a right-to-left
    paragraph on us. That matters: right-aligning it would be the MIRRORING half of the job,
    and mirroring is now a decision the CONTROL makes and passes down (BeginPaint's
    ARightToLeft, already applied to AHAlign by the time it gets here) -- not something the
    text layout is allowed to infer from the script it happens to be holding. Those two
    answers differ for every Arabic caption on a left-to-right form. So the caller's AHAlign
    stays the only thing that decides where the block sits. Anchor it here, exactly as the
    legacy path anchors a TextRect.
    If a caller ever needs AvailableWidth, it must pin ParagraphAlignment to btaLeftJustify
    at the same time, or that decision changes underneath every control at once. }
  w := Ceil(Result.UsedWidth);
  h := Ceil(Result.TotalTextHeight);
  case AHAlign of
    taCenter:       x := ARect.Left + ((ARect.Right - ARect.Left) - w) div 2;
    taRightJustify: x := ARect.Right - w;
  else
    x := ARect.Left;
  end;
  case AVAlign of
    tlCenter: y := ARect.Top + ((ARect.Bottom - ARect.Top) - h) div 2;
    tlBottom: y := ARect.Bottom - h;
  else
    y := ARect.Top;
  end;
  Result.TopLeft := PointF(x, y);
end;

{ The visual x-span of ONE codepoint of a laid-out line.

  GetCaret alone cannot answer this. Where a left-to-right run meets a right-to-left one,
  a single character index has TWO screen positions, and BGRA resolves the ambiguity towards
  the run that ENDS at that index. So asking it for both edges of the character just AFTER a
  boundary returns the same x twice and the span comes out empty -- which is exactly how the
  mnemonic underline first went missing. Locate the part the codepoint lives in and take
  that part's own end carets when the index sits on its edge. }
function BidiCharSpan(ALayout: TBidiTextLayout; ACharIndex: Integer;
  out AX1, AX2, ABottom: Single): Boolean;

  function EdgeX(APart, AIndex: Integer): Single;
  begin
    if AIndex <= ALayout.PartStartIndex[APart] then
      Result := ALayout.PartStartCaret[APart].Top.x
    else if AIndex >= ALayout.PartEndIndex[APart] then
      Result := ALayout.PartEndCaret[APart].Top.x
    else
      Result := ALayout.GetCaret(AIndex).Top.x;   // strictly inside a part: unambiguous
  end;

var
  i: Integer;
  t: Single;
begin
  Result := False;
  AX1 := 0; AX2 := 0; ABottom := 0;
  for i := 0 to ALayout.PartCount - 1 do
    if (ACharIndex >= ALayout.PartStartIndex[i]) and (ACharIndex < ALayout.PartEndIndex[i]) then
    begin
      AX1 := EdgeX(i, ACharIndex);
      AX2 := EdgeX(i, ACharIndex + 1);
      { A caret inside a right-to-left run advances LEFTWARDS, so the second edge is the
        smaller x. Take the span, not the signed difference. }
      if AX2 < AX1 then begin t := AX1; AX1 := AX2; AX2 := t; end;
      ABottom := ALayout.PartRectF[i].Bottom;
      Exit(True);
    end;
end;

procedure TTyPainter.DrawTextLineBidi(const ARect: TRect; const AText: string;
  AColor: TTyColor; AHAlign: TAlignment; AVAlign: TTextLayout; AMnemonicPos: Integer);
var
  lay: TBidiTextLayout;
  ux, uy, uth, uw, cp: Integer;
  oldClip: TRect;
  px: TBGRAPixel;
  x1, x2, bottom: Single;
begin
  lay := BuildLineLayout(ARect, AText, AHAlign, AVAlign);
  if lay = nil then Exit;
  try
    px := TyColorToBGRA(AColor);
    { TextRect clipped for us (style.Clipping); the layout does not, so a caption wider than
      its box would paint over the control next to it. }
    oldClip := FBmp.ClipRect;
    FBmp.ClipRect := TRect.Intersect(oldClip, ARect);
    try
      lay.DrawText(FBmp, px);
      { Mnemonic underline. The legacy arithmetic -- measure the bytes BEFORE the mnemonic,
        add that to the block's left edge -- assumes the glyphs come out in the order the
        bytes went in, which is precisely what stops being true here: in "<arabic> &Save"
        the S displays at the far LEFT and the old sum put its underline a whole word to the
        right. Ask the layout where that character actually landed instead. }
      if (AMnemonicPos >= 1) and (AMnemonicPos <= Length(AText)) then
      begin
        cp := UTF8Length(Copy(AText, 1, AMnemonicPos - 1));   // bytes before -> chars before
        if BidiCharSpan(lay, cp, x1, x2, bottom) then
        begin
          ux := Round(x1);
          uw := Round(x2 - x1);
          uth := Scale(1);
          if uth < 1 then uth := 1;
          uy := Round(bottom) - uth;
          if uw > 0 then
            FBmp.FillRect(ux, uy, ux + uw, uy + uth, px, dmDrawWithTransparency);
        end;
      end;
    finally
      FBmp.ClipRect := oldClip;
    end;
  finally
    lay.Free;
  end;
end;

function TTyPainter.TextCaretX(const ARect: TRect; const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AHAlign: TAlignment; ACharIndex: Integer): Integer;
var
  lay: TBidiTextLayout;
begin
  Result := ARect.Left;
  if FBmp = nil then Exit;
  TyConfigureTextFont(FBmp, AFontName, AFontSizeLogical, AWeight, FPPI);
  { The SAME flip DrawTextLine applies, for the reason this pair exists at all: a caret that
    answered from an unmirrored block would point at a glyph that is no longer there. }
  lay := BuildLineLayout(ARect, AText, BidiFlipAlignment(AHAlign, FRightToLeft), tlTop);
  if lay = nil then Exit;
  try
    if ACharIndex < 0 then ACharIndex := 0;
    if ACharIndex > lay.CharCount then ACharIndex := lay.CharCount;
    Result := Round(lay.GetCaret(ACharIndex).Top.x);
  finally
    lay.Free;
  end;
end;

function TTyPainter.TextCharIndexAtX(const ARect: TRect; const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AHAlign: TAlignment; AX: Integer): Integer;
var
  lay: TBidiTextLayout;
begin
  Result := 0;
  if FBmp = nil then Exit;
  TyConfigureTextFont(FBmp, AFontName, AFontSizeLogical, AWeight, FPPI);
  { See TextCaretX: the inverse query must be built on the block the DRAW produced. }
  lay := BuildLineLayout(ARect, AText, BidiFlipAlignment(AHAlign, FRightToLeft), tlTop);
  if lay = nil then Exit;
  try
    { Probed at the vertical middle of the line the layout actually produced, not of ARect:
      a one-line layout anchored at the top of a tall box would otherwise be probed below
      its own glyphs. }
    Result := lay.GetCharIndexAt(PointF(AX, lay.TopLeft.y + lay.TotalTextHeight / 2));
  finally
    lay.Free;
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
    tgChevronLeft:
      { The exact reflection of tgChevronRight about the glyph box's vertical centre line
        (x -> l + r - x), written out rather than derived so the two stay one shape: a
        mirrored control must draw the SAME chevron its unmirrored twin draws, and a second
        set of hand-picked coefficients is a second thing to drift. }
      FBmp.DrawPolyLineAntialias([PointF(r - w * 0.3, t),
        PointF(l + w * 0.2, cy), PointF(r - w * 0.3, b)], px, th);
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
    { Filled triangles. Base m, height 0.6*m -- the 5:3 proportion the Windows spin part uses,
      kept as a ratio so the shape is the same at every density instead of a fixed 5x3 that
      would vanish on a 200% display. Centred on the glyph box, so a caller that squares its
      button half (TySquareGlyphBox) gets the same triangle up and down. }
    tgTriangleUp:
      FBmp.FillPolyAntialias([PointF(cx, cy - m * 0.3),
        PointF(cx + m * 0.5, cy + m * 0.3), PointF(cx - m * 0.5, cy + m * 0.3)], px);
    tgTriangleDown:
      FBmp.FillPolyAntialias([PointF(cx, cy + m * 0.3),
        PointF(cx - m * 0.5, cy - m * 0.3), PointF(cx + m * 0.5, cy - m * 0.3)], px);
    tgTriangleLeft:
      FBmp.FillPolyAntialias([PointF(cx - m * 0.3, cy),
        PointF(cx + m * 0.3, cy - m * 0.5), PointF(cx + m * 0.3, cy + m * 0.5)], px);
    tgTriangleRight:
      FBmp.FillPolyAntialias([PointF(cx + m * 0.3, cy),
        PointF(cx - m * 0.3, cy + m * 0.5), PointF(cx - m * 0.3, cy - m * 0.5)], px);
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
  {$IFDEF LCLWin32}
  FreeAndNil(TTyGdiTextRenderer.GShot);
  {$ENDIF}
  FreeAndNil(GImgCache);  // OwnsObjects frees the cached bitmaps
  TyInvalidateTextMeasureCache;   // frees the boxed block measurements
  FreeAndNil(GBlockCache);
  FreeAndNil(GRenderCache);

end.
