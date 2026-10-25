unit tyControls.Painter;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType, LazUTF8, BGRABitmap, BGRABitmapTypes,
  BGRAGradientScanner, BGRACanvas2D, BGRATextBidi, BGRATransform,
  BGRAPath,   // TBGRAPath: measures a path:// symbol's own bounds for SvgPathIn
  FPReadJPEG, FPReadPNG, FPReadBMP,  // register FPImage readers so url() jpg/png/bmp load
  tyControls.Types, tyControls.FontUnits;

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
    tgInfo, tgSuccess, tgWarning, tgError,
    // The fourth chevron. Appended rather than placed beside its siblings so every existing
    // ordinal stays where it was; a GlyphKind in an .lfm streams by name either way. The
    // ribbon's collapse button points up while the ribbon is open, and without this kind it
    // drew a shafted arrow instead.
    tgChevronUp);

  { Which side of a body a speech-balloon pointer leaves from. Named for the BODY's edge, so
    tpsTop means the wedge stands above the body -- which is what a balloon ANCHORED BELOW its
    target looks like. }
  TTyPointerSide = (tpsTop, tpsBottom, tpsLeft, tpsRight);

  { ---- vector path API types (see the VECTOR PATH API block below) ---- }

  { How a self-intersecting path decides what is inside. tfrEvenOdd is what
    gives a ring its hole when both contours wind the same way -- a donut, a
    sunburst band. tfrNonZero would fill the hole in. }
  TTyFillRule = (tfrNonZero, tfrEvenOdd);
  TTyLineCap  = (tlcButt, tlcRound, tlcSquare);
  TTyLineJoin = (tljMiter, tljRound, tljBevel);

  { A path vertex, DEVICE px. Its own record rather than TPointF because that
    one is Single and the chart's geometry layer is Double throughout. }
  TTyVecPoint = record X, Y: Double; end;

  { Dash on/off lengths in LOGICAL px. Kept as its own type because the painter
    stores one across SaveState/RestoreState -- see SetLineDash. }
  TTyDashPattern = array of Double;
  { How many device pixels one unit of a canvas covers -- see TyCanvasDeviceScale below. }
  TTyCanvasScale = record
    Scale: Integer;        // device pixels per canvas unit, 1..4
    DeviceUnits: Boolean;  // the canvas's own coordinates are device pixels (an S-times cache)
  end;

  TTyPainter = class
  private
    FBmp: TBGRABitmap;
    FCanvas: TCanvas;
    FRect: TRect;
    FPPI: Integer;
    FOwnsBmp: Boolean;
    FRightToLeft: Boolean;
    { The dash pattern in LOGICAL px, plus its own save/restore stack.

      It cannot simply be pushed at the canvas: BGRA's pen pattern is measured in
      MULTIPLES OF THE LINE WIDTH (bgrapen.pas:1324, DashPenStyle = 3,1), and the
      width is not known until StrokePath. So SetLineDash records the caller's
      intent in px and StrokePath does the division. That in turn means
      ctx.save/restore cannot carry it, hence the parallel stack. }
    FVecDash: TTyDashPattern;
    FVecDashStack: array of TTyDashPattern;
    { [R2-F] the dash's phase (a canvas' lineDashOffset), LOGICAL px, and its
      save/restore stack beside the pattern's }
    FVecDashOffset: Double;
    FVecDashOffsetStack: array of Double;
    { [R2-F] whether the current path holds anything since BeginPath: a circle
      or an ellipse added to it starts a sub-path of its own (zrender's
      Circle.buildPath moves to (cx + r, cy) first); BGRA's arc has no move,
      and joined every circle traced into one path to the one before. An
      empty path takes none, so a lone circle draws as it always did. }
    FPathOpen: Boolean;
    { [R4-P] FastStrokes: see the property }
    FFastStrokes: Boolean;
    { #83: the layer holds FScale device pixels per layout pixel. FLayoutPPI is the PPI callers
      paint at; FPPI is the PPI the drawing code scales by, which is the layout PPI except
      inside a raster scope (RasterEnter), where it is FLayoutPPI * FScale. FDeviceUnits: the
      canvas counts device pixels, so EndPaint lands the layer 1:1 instead of stretching it. }
    FScale: Integer;
    FDeviceUnits: Boolean;
    FLayoutPPI: Integer;
    FRasterDepth: Integer;
    { A caller's surface (BeginPaintOn) at S > 1: its Canvas2D transforms from before the
      preset, which EndPaint puts back. }
    FKeptC2D: Boolean;
    FKeptMatrix, FKeptStrokeMatrix: TAffineMatrix;
    { The rect clip masks it holds in the kept pool (GClipPool) are the entries that
      name it as their owner: see ClipRect. }
    procedure ReleaseClipMasks;
    { [R4-P] the current path stroked by the hairline rasteriser when FastStrokes is on and
      the pen is one it draws: True when it took the stroke }
    function StrokeHairline(ACtx: TBGRACanvas2D): Boolean;
    function GetRasterPPI: Integer;
    { The canvas2D of a scaled layer works in layout pixels: BeginPaint presets scale(S, S). }
    procedure PresetCanvas2D;
    { Draw ABmp (layer-sized) onto the canvas at the device scale: into the layout rect, or 1:1 at
      S times its position when the canvas counts device pixels. }
    procedure BlitScaled(ABmp: TBGRABitmap; AOpaque: Boolean);
    { THE RASTER SCOPE. A drawing method enters it first and leaves it last. The OUTERMOST entry
      of a scaled painter switches FPPI to the raster PPI and returns True: the method then maps
      its own geometry (rects, points, device lengths) with Dev, and every Scale inside it --
      and inside the painter methods it calls -- comes out in raster pixels. Nested entries
      return False, so a method that calls another never maps twice. At S = 1 it never maps. }
    function RasterEnter: Boolean;
    procedure RasterLeave;
    { The bodies of the drawing methods that map their rect in the raster scope: the public
      method of the same name enters the scope and calls these with the mapped rect. }
    procedure FillBackgroundAt(const ARect: TRect; const AFill: TTyFill; const ACorners: TTyCorners);
    procedure StrokeBorderAt(const ARect: TRect; const ACorners: TTyCorners; AWidthLogical: Integer; AColor: TTyColor);
    procedure DrawEdgeAt(const ARect: TRect; AWidthLogical: Integer; ATLColor, ABRColor: TTyColor);
    procedure DropShadowAt(const ARect: TRect; ARadiusLogical: Integer; AColor: TTyColor; ABlurLogical: Integer; const AOffsetLogical: TPoint);
    procedure DrawGlyphAt(const ARect: TRect; AGlyph: TTyGlyphKind; AColor: TTyColor; AThicknessLogical: Integer; APadLogical: Integer);
    procedure DrawDropChevronAt(const AZoneRect: TRect; AColor: TTyColor; ASizeLogical: Integer);
    procedure DrawChevronAt(const AZoneRect: TRect; AKind: TTyGlyphKind; AColor: TTyColor; ASizeLogical: Integer);
    procedure FillCornerGapsAt(const ARect: TRect; const ACorners: TTyCorners; AColor: TTyColor);
    procedure EraseRectAt(const ARect: TRect);
    procedure DrawRuleAt(const ARect: TRect; const AColor: TBGRAPixel);
    procedure FillPointerShapeAt(const ABody: TRect; const ACorners: TTyCorners;
      ASide: TTyPointerSide; ATipPos, AHalfBase, AHeight: Integer;
      AFillColor, ABorderColor: TTyColor; ABorderWidthLogical: Integer);
    procedure NineSliceAt(const ARect: TRect; const AImagePath: string; const AInsets: TRect; ATile: Boolean);
    procedure DrawImageFillAt(const ARect: TRect; const AImagePath: string; AMode: TTyImageMode; ABlurLogical: Integer);
    procedure FillImageSliceAt(const ARect: TRect; ASrc: TBGRABitmap; const ASrcOffset: TPoint);
    procedure FillGlassAt(const ARect: TRect; AGlass: TBGRABitmap; const ASrcOffset: TPoint; const ATint: TTyColor; const ACorners: TTyCorners);
    procedure DrawGlyphBitmapAt(const ARect: TRect; ABmp: TBGRABitmap);
    procedure DrawTextAt(const ARect: TRect; const AText, AFontName: string; AFontSizeLogical, AWeight: Integer; AColor: TTyColor; AHAlign: TAlignment; AVAlign: TTextLayout; AEllipsis: Boolean; AMnemonicPos: Integer; ASmallCrisp: Boolean; AMultiLine: Boolean; ALineHeightLogical: Integer);
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
    destructor Destroy; override;
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
    procedure BeginPaintOnScaled(ACanvas: TCanvas; const ARect: TRect; APPI: Integer;
      ABmp: TBGRABitmap; const AScale: TTyCanvasScale; ARightToLeft: Boolean = False);
    { BeginPaint at a device scale the caller already knows -- a painter with no canvas that
      still has to draw for one (TTyForm's glass backdrop). BeginPaint asks TyCanvasDeviceScale. }
    procedure BeginPaintScaled(ACanvas: TCanvas; const ARect: TRect; APPI: Integer;
      const AScale: TTyCanvasScale; ARightToLeft: Boolean = False);
    { Device pixels per layout pixel in this frame (1 outside BeginPaint and off a Retina canvas). }
    property DeviceScale: Integer read FScale;
    { The PPI the layer is drawn at: PPI * DeviceScale. Code that configures a font or renders an
      icon for Bitmap directly uses this, not PPI. }
    property RasterPPI: Integer read GetRasterPPI;
    { Layout pixels to the layer's raster pixels, for code that draws on Bitmap directly with
      anything but its Canvas2D. }
    function Dev(AValue: Integer): Integer; overload;
    function Dev(const ARect: TRect): TRect; overload;
    function Dev(const APoint: TPoint): TPoint; overload;
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
      overrides; a nil/empty bitmap draws nothing). ABmp is in RASTER pixels: render it at
      Dev(size) so it stays sharp on a scaled layer (#83); it is placed 1:1. }
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
      instead of a big ugly V. ASizeLogical is the chevron width (height 0.5x). The same mark
      DrawChevron draws pointing down. }
    procedure DrawDropChevron(const AZoneRect: TRect; AColor: TTyColor; ASizeLogical: Integer = TyDropChevronSize);
    { THE disclosure chevron: a drop field's V, a tree node's >, a submenu's >, an expander's V
      or ^ (AKind = tgChevronDown / Right / Left / Up; anything else draws Down). It has a FIXED
      size, centred in AZoneRect, so every caller draws one mark whatever its slot -- the slot
      decides where the mark goes, never how big it is. ASizeLogical is the long side of the
      centre line; the arms meet at 90 degrees, the stroke is 5/28 of the size (1.25 at 7, the
      weight BGRA's linear-light blending needs to match a 1px chevron drawn by Direct2D), and
      the ends and the join are round, as all three desktop platforms draw them. The apex lands
      on a whole device pixel, so the 45-degree arms cross a pixel centre on every row instead
      of smearing over two half-covered pixels. }
    procedure DrawChevron(const AZoneRect: TRect; AKind: TTyGlyphKind; AColor: TTyColor; ASizeLogical: Integer = TyDropChevronSize);
    procedure NineSlice(const ARect: TRect; const AImagePath: string; const AInsets: TRect; ATile: Boolean = False);
    procedure DrawImageFill(const ARect: TRect; const AImagePath: string; AMode: TTyImageMode; ABlurLogical: Integer);
    procedure FillImageSlice(const ARect: TRect; ASrc: TBGRABitmap; const ASrcOffset: TPoint);
    procedure FillGlass(const ARect: TRect; AGlass: TBGRABitmap; const ASrcOffset: TPoint; const ATint: TTyColor; const ACorners: TTyCorners);
    { Paint AColor into the area OUTSIDE the rounded rectangle (the 4 corner gaps).
      Used to re-establish a clean parent background in a windowed control's corners
      after a drop shadow bled into them. No-op when there are no rounded corners. }
    procedure FillCornerGaps(const ARect: TRect; const ACorners: TTyCorners; AColor: TTyColor);
    procedure EraseRect(const ARect: TRect);
    { Bitmap.DrawLine(AX1, AY1, AX2, AY2, AColor, False) for a horizontal or vertical run, in
      layout pixels: the same pixels -- from the first point up to, not including, the second --
      one LAYOUT pixel wide at any device scale. Bitmap.DrawLine is one DEVICE pixel wide: half
      the weight on a 2x layer (#83). A slanted run is Bitmap.DrawLine itself, ends mapped. }
    procedure DrawRule(AX1, AY1, AX2, AY2: Integer; const AColor: TBGRAPixel);
    { The layer, DeviceScale times the layout size (#83). Two conventions on it:
      - Bitmap.Canvas2D takes LAYOUT pixels: BeginPaint presets scale(S) and strokeScale(S).
      - Everything else on it (FillRect, PutImage, ClipRect, DrawLine, TextRect, ...) takes
        RASTER pixels: map with Dev(), give fonts RasterPPI, draw 1-px rules with DrawRule.
      At S = 1 the two are the same and nothing needs mapping. }
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
    property PPI: Integer read FLayoutPPI;
    constructor Create;

    { ============================ VECTOR PATH API ============================
      Added for TTyAdvanceChart (Tier 0 item 2), but general: any control needing
      a shape the chrome primitives above cannot express belongs here rather than
      reaching around the painter for Bitmap.Canvas2D.

      WHY IT IS ON THE PAINTER AT ALL. Everything above draws widget CHROME --
      rounded rects, borders, glyphs, nine-slice. A chart draws arbitrary
      geometry, and before this the only way to get it was P.Bitmap.Canvas2D,
      which is what tyControls.Chart.pas does today. Twenty series renderers each
      doing that would each re-derive DPI scaling, theme colour resolution, the
      bidi text path and the non-Windows supersampling gate -- the exact bug class
      this repo has already paid for.

      UNITS, and they differ on purpose:
        * PATH COORDINATES are DEVICE px, Double. The chart's geometry layer has
          already converted values to device pixels; scaling again here is a bug.
          ("Device px" throughout this block means PPI-scaled pixels -- the painter's
          LAYOUT pixels in #83's terms. On a layer at a device scale the painter's
          Canvas2D preset maps them to raster pixels; the entry points below that
          step outside the matrix -- ResetTransform, FillPathPattern, PathContains,
          DrawTextRotated -- map them themselves.)
        * WIDTHS, DASH LENGTHS and RADII are LOGICAL px, Double, and go through
          ScaleF, which does NOT round -- a 1 px axis line at 150 % must be 1.5
          device px, not the 2 the integer Scale() would give.

      STATE. The underlying TBGRACanvas2D is cached per bitmap
      (bgradefaultbitmap.pas:3865), so its state survives across calls and across
      the chrome primitives above. Nothing here assumes a clean context: every
      drawing entry point sets each property it depends on. }

    { Fractional DPI scale. Public because a series renderer needs the same
      conversion for its own arithmetic. Deliberately unrounded -- see above. }
    function ScaleF(ALogical: Double): Double;

    { ---- path building (coordinates: DEVICE px) ---- }
    procedure BeginPath;
    procedure ClosePath;
    procedure MoveTo(AX, AY: Double);
    procedure LineTo(AX, AY: Double);
    { Cubic bezier from the current point. }
    procedure CurveTo(AC1X, AC1Y, AC2X, AC2Y, AX, AY: Double);
    { Quadratic bezier from the current point. }
    procedure QuadTo(ACX, ACY, AX, AY: Double);
    { Arc on the circle (ACX,ACY,ARadius). Angles are RADIANS measured CLOCKWISE
      from the +x axis, matching BGRA; a caller working in ECharts' degrees
      converts once at its own call site rather than here. }
    procedure ArcTo(ACX, ACY, ARadius, AStartRad, AEndRad: Double;
      AAnticlockwise: Boolean = False);
    procedure PolylineTo(const APoints: array of TTyVecPoint);
    procedure RectPath(AL, AT, AR, AB: Double);
    procedure RoundRectPath(AL, AT, AR, AB, ARadiusLogical: Double);
    procedure EllipsePath(ACX, ACY, ARX, ARY: Double);
    procedure CirclePath(ACX, ACY, AR: Double);
    { SVG path data appended to the current path, in DEVICE px. This is ECharts'
      `path://` symbol format; BGRA's parser covers the whole grammar including
      elliptical arcs (bgrapath.pas:2301, 2400), so nothing is parsed here. }
    procedure SvgPath(const APathData: string);
    { The same, scaled and centred to fit ARect. AKeepAspect False stretches. }
    procedure SvgPathIn(const APathData: string; const ARect: TRect;
      AKeepAspect: Boolean = True);

    { ---- painting the current path ---- }
    procedure FillPath(AColor: TTyColor; ARule: TTyFillRule = tfrNonZero);
    { Fill the current path with a ramp between AStops.

      TWO POINTS OR A CENTRE AND A RADIUS -- not an angle. TTyFill's gradient
      is angle-shaped because a themed control's gradient runs across its own
      box and an angle says that in one number; a chart's gradient is written
      by the author as two endpoints, and converting those to an angle loses
      the length. So this is a second, lower entry point rather than a third
      caller of GradientEndpoints.

      ARadius > 0 selects the radial shape, whose inner radius is always
      nought. Coordinates are DEVICE pixels: a chart resolves its own
      geometry and hands over real numbers.

      GAMMA OFF, as everywhere in the painter. BGRA's gamma-corrected ramp
      uses an exponent of 1.7 while Canvas 2D and CSS interpolate in plain
      sRGB, so a corrected ramp would put the midpoint of every chart
      gradient somewhere upstream never puts it. }
    procedure FillPathGradient(const AStops: array of TTyGradStop;
      AX1, AY1, AX2, AY2, ARadius: Double;
      ARule: TTyFillRule = tfrNonZero);
    { Fill the current path with AImage tiled as a canvas pattern:
      ARepetition is createPattern's ('repeat', 'repeat-x', 'repeat-y',
      'no-repeat'; anything else repeats both ways), AMatrix [a, b, c, d, e,
      f] takes the image's pixels to DEVICE pixels, on top of the current
      transform. The image is borrowed, not owned. }
    procedure FillPathPattern(AImage: TBGRABitmap; const ARepetition: string;
      const AMatrix: array of Double; ARule: TTyFillRule = tfrNonZero);
    { Fill with a themed TTyFill. ABounds is what a gradient's angle resolves
      against (the rect the caller would have passed FillBackground), which is
      not derivable from the path: a bar's gradient is usually meant to run
      across the whole plot band, not across the one bar. }
    procedure FillPathWith(const AFill: TTyFill; const ABounds: TRect;
      ARule: TTyFillRule = tfrNonZero);
    { A width <= 0 draws NOTHING. Falling back to a default width would put a
      hairline everywhere a theme meant to switch a border off. }
    procedure StrokePath(AColor: TTyColor; AWidthLogical: Double);
    { [R2-P] StrokePath, its coverage KEPT. What BGRA fills for a stroke is the polygon its
      pen makes of the path, and what the antialiased fill does with it -- the brush calls,
      position by position, before any colour -- depends on that polygon and the bitmap's
      clip rect alone. A polygon met again (a chart label's halo on the next hover frame)
      replays those calls through this stroke's own brush instead of filling again: the same
      calls on the same brush, so the same pixels, and the global Random left as the fill
      would have left it. Kept per process, main thread only, and dropped whole past a cap.
      Whatever the replay does not model -- a clip mask, a stroke texture, a shadow, no
      antialiasing, an ink that draws nothing, another thread -- strokes as StrokePath. Worth
      it only where the same path comes back; every miss records as it fills. }
    procedure StrokePathKept(AColor: TTyColor; AWidthLogical: Double);
    { [R4-P] THE FAST WAYS TO STROKE, off by default: no control but the one that asks for
      them draws any differently. On, two things change:
      - StrokePath and StrokePathKept lay a solid pen narrower than one RASTER pixel (its
        width times the canvas' uniform scale) with a hairline rasteriser instead of BGRA's
        antialiased fill of the pen's polygon: along each segment of the flattened path,
        column by column (row by row where it runs steeper than 45 degrees), the segment's
        share of the column spread over the rows the line's thickness crosses, the coverage
        of every pixel summed over the segments that reach it and capped at full, then laid
        once with the brush the fill would use -- the same colour, global alpha, blending and
        clip mask. The ink is the pen's area (the width times the length, a square or round
        cap's share at the ends of an open path); joins are not drawn, so two segments
        meeting at a shallow angle share the column at the joint and do not darken it.
        Ten times and more cheaper on a long thin curve; the pixels differ from BGRA's fill
        in the last steps of coverage. A dashed pen, a texture, a shadow, no antialiasing, an
        arrow, a skewed or unequally scaled pen, or another thread strokes as before.
      - StrokePathByDistance is open to the caller (it does not look at the switch). }
    property FastStrokes: Boolean read FFastStrokes write FFastStrokes;
    { [R4-P] THE CURRENT PATH STROKED BY DISTANCE: every pixel whose centre lies within half
      the width (plus half a pixel) of the path takes the coverage a straight band that wide
      would give it -- the overlap of [d - w/2, d + w/2] with the pixel, d its centre's
      distance to the nearest point of the path -- laid once, so where the path comes back
      near itself the ink is the union's, as a canvas stroke's. The pen's joins (a miter
      within its limit, else round) and caps. Made
      for strokes along many short segments that a polygon fill makes slow (a chart label's
      halo round its glyphs' outline); the coverage is kept by the path, the width and the
      clip rect, as StrokePathKept keeps its fill's, and a path met again is replayed
      through this stroke's brush. What it does not model -- a dash, a texture, a shadow, no
      antialiasing, a skewed or unequally scaled canvas, another thread -- strokes as
      StrokePathKept. }
    procedure StrokePathByDistance(AColor: TTyColor; AWidthLogical: Double);
    { Stroke the current path with the same ramp FillPathGradient fills with.
      Its own entry point rather than a flag on the fill: a stroke needs a
      width and a fill does not, and one procedure taking both would have a
      parameter that is meaningless half the time. }
    procedure StrokePathGradient(const AStops: array of TTyGradStop;
      AX1, AY1, AX2, AY2, ARadius, AWidthLogical: Double);
    procedure FillAndStrokePath(AFillColor, AStrokeColor: TTyColor;
      AWidthLogical: Double; ARule: TTyFillRule = tfrNonZero);
    { Hit-test the current path, DEVICE px, THROUGH the current transform -- so
      paint and hit-test can share one path, which is the TTySegmented rule.

      TAKES THE RULE, defaulted like every other entry point here. The
      underlying isPointInPath reads the canvas' shared fillMode, so setting
      none left the answer depending on whatever was filled last: even-odd on a
      fresh painter, because that is the zero value of TFillMode, and winding
      after any FillPath. A ring could hit-test one way and paint the other. }
    function PathContains(AX, AY: Double;
      ARule: TTyFillRule = tfrNonZero): Boolean;

    { ---- stroke state ---- }
    { On/off lengths in LOGICAL px; an empty array restores a solid line. The
      phase starts again at nought. }
    procedure SetLineDash(const APatternLogical: array of Double); overload;
    { The same with a phase: a canvas' lineDashOffset, LOGICAL px -- each
      sub-path's pattern starts AOffsetLogical along it (negative: before
      it). A phase of nought (or of whole periods) strokes exactly as the
      pattern alone; any other lays the dashes along each sub-path itself,
      each dash a sub-path of its own with its caps, as a canvas does. }
    procedure SetLineDash(const APatternLogical: array of Double;
      AOffsetLogical: Double); overload;
    procedure SetLineCap(ACap: TTyLineCap);
    procedure SetLineJoin(AJoin: TTyLineJoin; AMiterLimit: Double = 10);

    { ---- state stack, transform, clip, per-element alpha ---- }
    { Saves transform + clip + stroke state + element alpha together. Anything
      left unrestored shows up as one series' style leaking into the next. }
    procedure SaveState;
    procedure RestoreState;
    procedure Translate(ADX, ADY: Double);
    { Positive is CLOCKWISE on screen (y grows downward), matching BGRA. }
    procedure RotateBy(AAngleRad: Double);
    procedure ScaleBy(ASX, ASY: Double);
    procedure ResetTransform;
    { Intersect the clip with the current path. }
    procedure ClipPath(ARule: TTyFillRule = tfrNonZero);
    { Intersect the clip with a rect -- built as a PATH so the current matrix
      applies. A clip that ignored the matrix would cut rotated content with an
      unrotated box. }
    procedure ClipRect(const ARect: TRect);
    { 0..1, per element. Orthogonal to the Opacity field, which dims the whole
      frame at EndPaint; both may be in force at once. }
    procedure SetElementAlpha(AAlpha: Double);

    { ---- rotated text ---- }
    { Text rotated about (AX, AY), with AHAlign/AVAlign saying where that anchor
      sits in the text box. AAngleRad is COUNTER-CLOCKWISE positive, and 0 draws
      exactly where the unrotated path would. Goes through TextOutAngle rather
      than the canvas' own text so it keeps TyConfigureTextFont's font cascade
      and fallback (empty-fontname-gotcha). }
    { [R2-F] Where a run's ALPHABETIC BASELINE lies under the top of the box
      DrawTextRotated and DrawText hang it by: the renderer's baseline for
      the font, LOGICAL px. }
    function TextBaseline(const AFontName: string; AFontSizeLogical, AWeight: Integer): Double;
    procedure DrawTextRotated(const AText, AFontName: string;
      AFontSizeLogical, AWeight: Integer; AColor: TTyColor;
      AX, AY, AAngleRad: Double; AHAlign: TAlignment; AVAlign: TTextLayout);
  end;

{ ===== The device scale (#83) ================================================

  On a Retina Mac one LCL pixel is one POINT and covers two device pixels. LCL-Cocoa says how
  many through TControl.GetCanvasScaleFactor (there since Lazarus 3.0; every other widgetset
  answers 1). A painter that draws its layer at the size of the control's bounds in points
  gets stretched by the system and comes out blurred, so the painter asks how many device
  pixels a canvas unit covers and draws its layer that many times larger. }
var
  { False puts every painter back at one times, as before #83: the way back for code that draws
    on TTyPainter.Bitmap in layout coordinates and has not been taught the device scale. }
  TyDeviceScaleRendering: Boolean = True;

{ A widgetset's scale factor as a whole number of device pixels per unit: rounded, at least 1,
  at most 4. Only whole factors are drawn at (macOS has 1 and 2); NaN and <= 0 read as 1. }
function TyDeviceScaleOf(AFactor: Double): Integer;
{ How many device pixels one unit of ACanvas covers, asked in this order: the switch above
  (off = 1); the test seam; the canvases an S-times offscreen cache registered (DeviceUnits);
  the scale factor of the control a TControlCanvas belongs to; else 1. nil = 1. }
function TyCanvasDeviceScale(ACanvas: TCanvas): TTyCanvasScale;
{ An offscreen cache whose bitmap holds AScale device pixels per layout pixel registers its
  canvas, so a painter drawing onto it draws at that scale and lands 1:1 (DeviceUnits).
  Registering again replaces the scale; unregistering a canvas that is not there does nothing. }
procedure TyRegisterRasterCanvas(ACanvas: TCanvas; AScale: Integer);
procedure TyUnregisterRasterCanvas(ACanvas: TCanvas);
{ ALayout in ACanvas's own units: S times it on a canvas in device units (a raster cache), as it is
  on one in layout units. For code that draws on the canvas outside a painter (#83). }
function TyCanvasRect(ACanvas: TCanvas; const ALayout: TRect): TRect;
{ Lays ABmp down over ALayout the way the painter's EndPaint lays its layer down. ABmp holds S
  device pixels per layout pixel, S = TyCanvasDeviceScale(ACanvas).Scale: 1:1 at S = 1 or on a
  canvas in device units, into the layout rectangle on one in layout units (a Retina window: the
  system puts each layout pixel back on S device pixels). For a caller that rendered with a
  canvas-less painter at the canvas's scale (#83). }
procedure TyDrawRasterBitmap(ACanvas: TCanvas; const ALayout: TRect; ABmp: TBGRABitmap;
  AOpaque: Boolean);
{ The scale ACanvas is registered with, 0 when it is not. Compares the pointer only, so it may be
  asked about a canvas that is already freed. }
function TyRegisteredRasterScale(ACanvas: TCanvas): Integer;
{ FOR THE TESTS: answer (AScale, ADeviceUnits) for every canvas; AScale = 0 turns it off.
  ANilCanvasToo = False keeps the real answer for a nil canvas (scale 1): a control drawn as on a
  Retina window, whose sub-painters with no canvas must take the window's scale from their caller
  (BeginPaintOnScaled) and are not handed it by the seam. A painter test drawing with no canvas
  leaves it True. }
procedure TyForceDeviceScaleForTest(AScale: Integer; ADeviceUnits: Boolean;
  ANilCanvasToo: Boolean = True);
function TyVecPoint(AX, AY: Double): TTyVecPoint;

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
{ AWeight, here and in every text call that passes a style's FontWeight on, is the CSS
  weight with italic, underline and strikeout above it (TyFontItalic & co., #92); the two
  font set-ups decode it with TyFontStylesOf. }

{ How TEXT is rasterized on this widgetset -- the one answer, for every surface that draws
  words (the painter, the HTML label). Icons drawn from an icon font are pictures, not text,
  and keep their own supersampled quality. See the implementation for why each branch. }
function TyTextFontQuality: TBGRAFontQuality;

{ Put the library's text renderer on ABmp. On Win32 that is a renderer that draws text the
  way Windows lays it out and shapes it -- see TTyGdiTextRenderer; on Cocoa one that draws
  each run in its ink's polarity -- see tyControls.CanvasText (#91); elsewhere it leaves
  BGRA's own. TyConfigureTextFont calls it, so every bitmap configured for text has it; a
  surface that configures a font by hand must call it too. }
procedure TyUseTextRenderer(ABmp: TBGRABitmap);
{ FOR THE TESTS: GDI bitmaps the Win32 text renderer has made or grown (it keeps one); 0
  elsewhere. }
function TyGdiTextBitmapsMade: Integer;
{ FOR THE TESTS: drop shadows actually rendered (blurred) since start -- a draw served from
  the shadow cache does not count. }
function TyShadowsRendered: Integer;
{ FOR THE TESTS: drop the cached shadows (the next draw of each renders again). }
procedure TyClearShadowCache;
{ Every pixel of ABmp has alpha 255 (stops at the first that does not). }
function TyBitmapIsOpaque(ABmp: TBGRABitmap): Boolean;
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
{ The kept measuring DC and turned-run DIB (Win32): how many times either was made or
  grown, and a switch back to BGRA's own per-call scratch for both -- the reference the
  kept ones must match pixel for pixel. }
function TyGdiTextKeptSurfacesMadeForTest: Integer;
procedure TyGdiTextBgraPathsForTest(AOn: Boolean);
{ The kept runs (Win32): a switch for them, and how many there are. }
procedure TyGdiTextRunCacheForTest(AOn: Boolean);
function TyGdiTextRunsKeptForTest: Integer;
{ TTyPainter.ClipRect's kept masks: how many first clips of a state it has BUILT (a reuse
  does not count), and a switch that turns the reuse off -- the reference it must match. }
function TyPainterClipMasksBuiltForTest: Integer;
procedure TyPainterClipReuseForTest(AOn: Boolean);
{ [R2-P] StrokePathKept's kept fills: a switch (off: every stroke goes through Canvas2D,
  and what is kept is dropped), how many fills were recorded and how many replayed. }
procedure TyPainterKeptStrokesForTest(AOn: Boolean);
function TyPainterKeptStrokeFillsForTest: Integer;
function TyPainterKeptStrokeReplaysForTest: Integer;
{ [R2-L] ... and the pen's polygons it keeps beside them: how many were computed (a
  kept one met again does not count). }
function TyPainterKeptStrokeContoursForTest: Integer;
{ Every kept fill hashed alike, so that a lookup is decided by its polygon and
  clip compare alone (the kept fills dropped either way). }
procedure TyPainterKeptFillHashesCollideForTest(AOn: Boolean);
{ [R4-P] how many strokes the hairline rasteriser took, how many distance strokes were
  computed (a kept one met again does not count) and how many replayed }
function TyPainterHairlinesForTest: Integer;
function TyPainterDistanceStrokesForTest: Integer;
function TyPainterDistanceReplaysForTest: Integer;

{ BGRA'S POLYGON FILLER TAKES ITS PIVOTS FROM THE GLOBAL Random. The one-pass
  filler behind FillPolyAntialias and the Canvas2D fill, stroke and clip
  (TOnePassFillPolyInfo.PartitionByY) sorts a polygon's edges by y with a
  quicksort whose pivot is Random(n). Edges on the same y come out in a
  pivot-dependent order, and where that order decides which scanline path the
  antialiaser takes the coverage differs by a step or two -- the same long line
  painted differently from one run of an exe to the next, and from a fresh
  chart to the next in one process.

  Call TyPinBgraRandom before such a call and TyUnpinBgraRandom with its
  answer after it: the generator is pinned to one seed for the call, so a
  polygon paints the same whatever the application's generator holds. FPC's
  generator state is private, so the application's stream cannot be put back
  as it was; when BGRA drew from the pinned one, the application's is reseeded
  from a value derived from the seed it held -- it keeps running rather than
  restarting, and stays reproducible for an application that seeds it. When
  BGRA drew nothing (fewer than ten points) the stream is left exactly as it
  was. Main thread only, like everything else that paints. }
function TyPinBgraRandom: LongWord;
procedure TyUnpinBgraRandom(ASaved: LongWord);
{ [R2-H] A Canvas2D's own fill, stroke and clip with the generator pinned, as
  the painter's are: for a control that draws its path straight on the
  bitmap's Canvas2D (an arc, a long line) }
procedure TyCtxFill(ACtx: TBGRACanvas2D);
procedure TyCtxStroke(ACtx: TBGRACanvas2D);
procedure TyCtxClip(ACtx: TBGRACanvas2D);

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
{ The same wrap for a caller that has a font and a width but no canvas: returns
  AText with real line breaks inserted. Measures on the shared measurement
  surface, so a caller wrapping one string per axis label does not allocate a
  bitmap per label -- which is what the chart's own version was doing. }
function TyWrapTextToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight, APPI, AMaxWidthPx: Integer): string;
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
{ How many times TyInvalidateTextMeasureCache has run. A cache kept outside this unit
  whose entries come out of drawn or measured text (a chart's traced label outlines)
  drops them when this moves -- the same staleness rule, without a hook list. }
function TyTextMeasureGeneration: Cardinal;

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

  { Off switch for the drop-shadow cache (see TTyPainter.DropShadow). Like the memo's, it
    never changes a pixel, only how long a shadow takes: the tests draw every shadow with it
    off too and require the same bytes. }
  TyShadowCacheEnabled: Boolean = True;

implementation

uses
  LCLIntf, BGRAText, BGRAGrayscaleMask, Generics.Collections, BGRAPolygon, BGRABlend,
  tyControls.CanvasText, tyControls.PlatformWS;

{ Canvas2D's own fill, stroke and clip with the generator pinned. }
procedure CtxFill(ACtx: TBGRACanvas2D);
var
  saved: LongWord;
begin
  saved := TyPinBgraRandom;
  try
    ACtx.fill;
  finally
    TyUnpinBgraRandom(saved);
  end;
end;

procedure CtxStroke(ACtx: TBGRACanvas2D);
var
  saved: LongWord;
begin
  saved := TyPinBgraRandom;
  try
    ACtx.stroke;
  finally
    TyUnpinBgraRandom(saved);
  end;
end;

procedure CtxClip(ACtx: TBGRACanvas2D);
var
  saved: LongWord;
begin
  saved := TyPinBgraRandom;
  try
    ACtx.clip;
  finally
    TyUnpinBgraRandom(saved);
  end;
end;

{ THE TWO MEASUREMENT SURFACES, REUSED.

  Both measurement functions used to create a 1x1 scratch, measure on it and free
  it. Two reasons were given for that, and only one of them was ever true.

  "A size-FLOOR path, not a per-frame paint path" WAS true when it was written --
  one measurement per control, at AutoSize time. An axis measures one string per
  LABEL: 5,000 categories cost 15,047 ms to lay out, and the same 5,000 with one
  repeated label -- where the memo answers every call and neither surface is
  touched -- cost 74 ms.

  "A cached one would carry the last caller's font" is the half that needs care,
  because the obvious defence of it is WRONG. It is tempting to say each function
  reassigns every font property before measuring; neither does.

    * TyConfigureTextFont sets FontName, FontHeight, FontQuality and FontStyle on
      the BGRA surface -- but TBGRADefaultBitmap.GetFontRenderer feeds FIVE
      fields to the renderer, and the fifth, FontOrientation, is never assigned
      here.
    * TyConfigureMeasureFont sets Name, Height and Style on the LCL canvas, and
      never Quality, Orientation, CharSet or Pitch. (Nor PixelsPerInch, which
      stays at the screen's as of the moment the surface was made -- and does not
      matter, because the height it is given is a pixel count: see TyFontHeightPx.)

  What actually makes a shared surface safe is that NOTHING IN THIS LIBRARY EVER
  WRITES those fields on these two surfaces. FontOrientation has one would-be
  user, DrawTextRotated, and it passes its angle to TextOutAngle rather than
  setting it; grep source/ for Font.Orientation / Font.CharSet / Font.Pitch /
  Font.Quality and there are no assignments at all -- bar one that keeps the rule:
  on Win32 TyConfigureTextFont also puts TTyGdiTextRenderer on the BGRA surface,
  whose UpdateFont sets ITS OWN font's Quality to the same value on every call, so
  no caller's state rides along in it. So every unassigned field holds its
  construction default for the life of the surface -- which is what a freshly
  created one would have held too. If a caller ever does set one of them,
  this stops being true and the reset has to become explicit, which is why the
  list above is written out rather than summarised.

  MAIN THREAD ONLY, exactly like the memo above and TTyStyleModel's resolve
  cache, and for the same reason: both are reached only from control layout and
  paint, which are main-thread by LCL contract.

  Dropped by TyInvalidateTextMeasureCache so that "invalidate" means everything
  this unit is holding, and so a surface cannot outlive the memo it was filling.
  NOT because that releases a font handle: LCL keeps those in a process-global
  FontResourceCache and TFont.FreeReference only decrements a refcount, so
  destroying a surface returns nothing to the widgetset. Item (10) of the
  enumeration above is closed by dropping the MEMO, which that routine already
  did before this change. }
var
  GRenderScratch: TBGRABitmap = nil;
  GBlockScratch: TBitmap = nil;

function RenderScratch: TBGRABitmap;
begin
  if GRenderScratch = nil then GRenderScratch := TBGRABitmap.Create(1, 1);
  Result := GRenderScratch;
end;

function BlockScratch: TBitmap;
begin
  if GBlockScratch = nil then
  begin
    GBlockScratch := TBitmap.Create;
    GBlockScratch.SetSize(1, 1);
  end;
  Result := GBlockScratch;
end;

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
  GMeasGeneration: Cardinal = 0;
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

procedure TyGdiTextDropKept; forward;

procedure TyInvalidateTextMeasureCache;
var
  i: Integer;
begin
  Inc(GMeasGeneration);
  if GBlockCache <> nil then
  begin
    for i := 0 to GBlockCache.Count - 1 do
      GBlockCache.Objects[i].Free;
    GBlockCache.Clear;
  end;
  if GRenderCache <> nil then
    GRenderCache.Clear;             // Objects[] here are plain ints, nothing to free
  { The scratch surfaces too. Not because they can hold a stale FONT -- every
    caller reassigns all four properties before measuring -- but because this is
    the hook for item (10) of the enumeration above: registering a font file
    changes what a name resolves to in the process, and a live surface may be
    holding a handle resolved before that happened. }
  FreeAndNil(GRenderScratch);
  FreeAndNil(GBlockScratch);
  { and the renderer's kept measuring and turning DCs, for the same reason }
  TyGdiTextDropKept;
end;

procedure TyTextMeasureCacheStats(out AHits, AMisses: Int64; out AEntries: Integer);
begin
  AHits := GMeasHits;
  AMisses := GMeasMisses;
  AEntries := 0;
  if GBlockCache <> nil then Inc(AEntries, GBlockCache.Count);
  if GRenderCache <> nil then Inc(AEntries, GRenderCache.Count);
end;

function TyTextMeasureGeneration: Cardinal;
begin
  Result := GMeasGeneration;
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
  { an author size in CSS px (tyControls.FontUnits) is px at 96 PPI, not points }
  if TyFontSizeIsPx(AFontSizeLogical) then
    Result := Round(TyFontPxOf(AFontSizeLogical) * APPI / 96)
  else
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
  ACanvas.Font.Style := TyFontStylesOf(AWeight);
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

  Meas := BlockScratch;
  Lines := TStringList.Create;
  try
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

    Win32: fqSystem, which TTyGdiTextRenderer turns into ClearType as Windows lays it down
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
    dark ink black on white, light ink white on black -- and the three subpixel coverages are
    laid down in the ink colour with the same non-gamma blend GDI uses: channel by channel
    where the surface under the pixel is opaque, as GDI lays them on a window; averaged into
    one grey where it is not, since there the colour the text ends up on is not known yet
    and a coloured edge would land on whatever shows through. (Every pixel was grey until
    #90: weight right, sharpness not -- a stem ClearType puts on two subpixels came out as
    two grey pixels, soft next to the system's own text.) A desktop with ClearType off gets
    grey everywhere, as its own text is. The polarity is not a nicety: Windows weights the two
    differently under the user's ClearType contrast. At the default (1400) they cover within
    half a percent of each other; at 1200 a white-on-black line of 9pt Segoe UI inks 12% more
    than the black-on-white one, and light text drawn from the dark-on-light coverage came out
    a tenth lighter than the text Windows drew beside it.
    Measured on a line of 9pt YaHei: the ink it lays down is the ink native ClearType lays
    down (1403 against 1404 at 100%, 3697 against 3697 at 175%), and so is the share of solid
    pixels; on an opaque surface black on white and white on black, every channel of every
    pixel is the one GDI draws there.

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
    { BGRA MEASURES every run, and lays every TURNED run down, on a TBitmap of its own:
      a memory DC, a bitmap and a font selected into them, made and freed per call. On
      the machine this was measured on that is about a millisecond a call, and a chart
      measures a string per label and per tick: a radial tree of 250 labels spent 3 s
      of its first frame making DCs. GMeasure is the DC BGRA's measuring calls would
      make (a 0 x 0 TBitmap, as theirs is), kept; GTurn the 32-bit DIB its turned
      path draws on, kept and grown like GShot. The GDI calls on them are BGRA's own,
      call for call, on the same font -- see InternalTextSizeStyle and TurnedTextOut --
      so the sizes and the pixels are the ones BGRA produced. Main thread only, like
      GShot; dropped with it, and by TyInvalidateTextMeasureCache. }
    class var GMeasure, GTurn: TBitmap;
    class var GKeptMade: Integer;        { GMeasure and GTurn made or grown: FOR THE TESTS }
    class var GBgraPaths: Boolean;       { BGRA's own measuring and turned paths: FOR THE TESTS }
    { WHAT A RUN COMES TO, KEPT. A chart repaints its labels on every hover frame -- the
      same strings in the same fonts at the same places -- and each repaint asked GDI to
      measure and draw them again: a radial tree's hover frame was 250 turned labels, each
      realising a turned font twice. GDI answers the same question the same way, so the
      answers are kept: GSizes the measurements (by font, style flags, width and text),
      GRuns the ink -- a straight run's coverage, a turned run's mask -- by font, ink
      polarity or angle and sub-pixel offset, and text. Laid down by the same blend as a
      fresh one. Main thread only; cleared when they grow past a cap, with the kept
      surfaces, and by TyInvalidateTextMeasureCache. }
    class var GSizes: specialize TDictionary<string, TSize>;
    class var GRuns: specialize TDictionary<string, TObject>;
    class var GRunBytes: Int64;
    class var GNoRunCache: Boolean;      { FOR THE TESTS }
    class function RunCacheOn: Boolean;
    class function FontSig(AFont: TFont): string;
    class function FindRun(const AKey: string): TObject;
    class procedure KeepRun(const AKey: string; ARun: TObject; ABytes: Integer);
    class procedure DropRuns;
    class function MeasureSurface(AFont: TFont): TBitmap;
    procedure TurnedTextOut(ADest: TBGRACustomBitmap; xf, yf: single;
      AOrientation: integer; const sUTF8: string; c: TBGRAPixel; align: TAlignment);
  protected
    procedure UpdateFont; override;
    { The measuring side, answered for the run exactly as it is drawn. }
    function RunStyle(ARightToLeft, AShowPrefix: Boolean): TTextStyle;
    function InternalTextSizeStyle(sUTF8: string; AStyle: TTextStyle;
      AMaxWidth: integer): TSize; override;
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
function TySystemParametersInfo(uiAction, uiParam: LongWord; pvParam: Pointer;
  fWinIni: LongWord): LongBool; stdcall; external 'user32' name 'SystemParametersInfoW';

{ Whether the desktop draws its own text in ClearType: font smoothing on, and of that type.
  Asked per run -- a user32 read of a setting the user can change at any time, which LCL does
  not pass on (it swallows WM_SETTINGCHANGE). }
function TyDesktopClearType: Boolean;
const
  SPI_GETFONTSMOOTHING = $004A;
  SPI_GETFONTSMOOTHINGTYPE = $200A;
  FE_FONTSMOOTHINGCLEARTYPE = 2;
var
  smooth: LongBool;
  kind: LongWord;
begin
  smooth := False;
  kind := 0;
  Result := TySystemParametersInfo(SPI_GETFONTSMOOTHING, 0, @smooth, 0) and smooth
    and TySystemParametersInfo(SPI_GETFONTSMOOTHINGTYPE, 0, @kind, 0)
    and (kind = FE_FONTSMOOTHINGCLEARTYPE);
end;

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

class function TTyGdiTextRenderer.MeasureSurface(AFont: TFont): TBitmap;
begin
  if GMeasure = nil then
  begin
    GMeasure := TBitmap.Create;
    Inc(GKeptMade);
  end;
  Result := GMeasure;
  { What BGRA's scratch has: a canvas font born at the screen's PPI (see GShot's note
    on Assign), then AFont, then AFont's pixel height set outright. }
  Result.Canvas.Font.PixelsPerInch := ScreenInfo.PixelsPerInchY;
  Result.Canvas.Font := AFont;
  Result.Canvas.Font.Height := AFont.Height;
end;

type
  { A straight run's coverage, 0..255 three times per pixel of its w x h box -- the red,
    green and blue subpixels, in that order -- already turned the way the ink reads it (see
    InternalTextOutAngle). }
  TTyRunInk = class
    W, H: Integer;
    Cov: array of Byte;
  end;

const
  { the caps: past either, everything kept is dropped (the CLEAR-not-evict choice of
    the measurement memo above) }
  GdiRunsMaxCount = 8192;
  GdiRunsMaxBytes = 32 * 1024 * 1024;
  GdiSizesMaxCount = 32768;

class function TTyGdiTextRenderer.RunCacheOn: Boolean;
begin
  Result := (GetCurrentThreadId = MainThreadID) and not GNoRunCache and not GBgraPaths
    and not GForceConversion;
end;

{ Every TFont property that reaches the LOGFONT GDI realises: two fonts with one
  signature are drawn and measured alike. }
class function TTyGdiTextRenderer.FontSig(AFont: TFont): string;
var
  st: TFontStyle;
  s: Integer;
begin
  s := 0;
  for st := Low(TFontStyle) to High(TFontStyle) do
    if st in AFont.Style then s := s or (1 shl Ord(st));
  Result := IntToStr(AFont.Height) + ',' + IntToStr(s) + ',' + IntToStr(Ord(AFont.Quality))
    + ',' + IntToStr(AFont.Orientation) + ',' + IntToStr(AFont.CharSet) + ','
    + IntToStr(Ord(AFont.Pitch)) + ',' + IntToStr(AFont.PixelsPerInch) + ','
    + IntToStr(Length(AFont.Name)) + ',' + AFont.Name;
end;

class function TTyGdiTextRenderer.FindRun(const AKey: string): TObject;
begin
  Result := nil;
  if GRuns <> nil then GRuns.TryGetValue(AKey, Result);
end;

class procedure TTyGdiTextRenderer.KeepRun(const AKey: string; ARun: TObject; ABytes: Integer);
begin
  if GRuns = nil then GRuns := specialize TDictionary<string, TObject>.Create;
  if (GRuns.Count >= GdiRunsMaxCount) or (GRunBytes + ABytes > GdiRunsMaxBytes) then
    DropRuns;
  GRuns.Add(AKey, ARun);
  Inc(GRunBytes, ABytes + Length(AKey));
end;

class procedure TTyGdiTextRenderer.DropRuns;
var
  o: TObject;
begin
  if GRuns <> nil then
  begin
    for o in GRuns.Values do o.Free;
    GRuns.Clear;
  end;
  GRunBytes := 0;
  if GSizes <> nil then GSizes.Clear;
end;

function TTyGdiTextRenderer.InternalTextSizeStyle(sUTF8: string; AStyle: TTextStyle;
  AMaxWidth: integer): TSize;
var
  bounds: TRect;
  flags: Cardinal;
  key: string;
begin
  { BGRATextSizeStyle -> BGRAOriginalTextSizeStyle -> BitmapTextExtentStyle, on the kept
    DC instead of a new one. Fine qualities scale the font and divide the answer; they
    and other threads keep BGRA's path. }
  if GBgraPaths or (GetCurrentThreadId <> MainThreadID) or not SystemFontAvailable
    or (FontQuality in [fqFineClearTypeBGR, fqFineClearTypeRGB, fqFineAntialiasing]) then
    Exit(inherited InternalTextSizeStyle(sUTF8, AStyle, AMaxWidth));
  bounds := Rect(0, 0, AMaxWidth, MaxInt);
  flags := DT_CALCRECT;
  if AStyle.SingleLine then flags := flags or DT_SINGLELINE;
  if AStyle.EndEllipsis then flags := flags or DT_END_ELLIPSIS;
  if AStyle.ExpandTabs then flags := flags or DT_EXPANDTABS;
  if AStyle.Wordbreak then flags := flags or DT_WORDBREAK;
  if AStyle.RightToLeft then flags := flags or DT_RTLREADING;
  if not AStyle.ShowPrefix then flags := flags or DT_NOPREFIX;
  key := '';
  if RunCacheOn then
  begin
    key := IntToStr(flags) + ',' + IntToStr(AMaxWidth) + ',' + FontSig(FFont) + sUTF8;
    if (GSizes <> nil) and GSizes.TryGetValue(key, Result) then Exit;
  end;
  LCLIntf.DrawText(MeasureSurface(FFont).Canvas.Handle, PChar(sUTF8), Length(sUTF8),
    bounds, flags);
  Result := Size(bounds.Width, bounds.Height);
  if key <> '' then
  begin
    if GSizes = nil then GSizes := specialize TDictionary<string, TSize>.Create;
    if GSizes.Count >= GdiSizesMaxCount then GSizes.Clear;
    GSizes.Add(key, Result);
  end;
end;

procedure TTyGdiTextRenderer.TurnedTextOut(ADest: TBGRACustomBitmap; xf, yf: single;
  AOrientation: integer; const sUTF8: string; c: TBGRAPixel; align: TAlignment);
{ BGRATextOutAngle for fqSystem, statement for statement (the same Single arithmetic,
  the same rounding), with its two scratch bitmaps replaced by the kept ones: the size
  is BGRAOriginalTextSizeExAngle's TextExtent with the turned font on GMeasure, the run
  is drawn white on black on GTurn by the same TCanvas.TextOut, and FilterOriginalText's
  green channel through GammaExpansionTab is laid down by the same DrawAsAlpha. }
var
  posF: TPointF;
  x, y: integer;
  deltaX, deltaY: integer;
  size: TSize;
  TopLeft, TopRight, BottomRight, BottomLeft: TPointF;
  Top, dy: Single;
  Left: Single;
  cosA, sinA: single;
  rotBounds: TRect;
  sizeFactor: integer;
  w, h, nw, nh, px, py, stride, bpp: integer;
  ds: TDIBSection;
  bits, line, pdest: PByte;
  bottomUp: Boolean;
  mask: TGrayscaleMask;
  cache: Boolean;
  sig, key: string;

  procedure rotBoundsAdd(pt: TPointF);
  begin
    if pt.x < Left then Left := pt.x;
    if pt.y < Top then Top := pt.y;
    if floor(pt.X) < rotBounds.Left then rotBounds.Left := floor(pt.X/sizeFactor)*sizeFactor;
    if floor(pt.Y) < rotBounds.Top then rotBounds.Top := floor(pt.Y/sizeFactor)*sizeFactor;
    if ceil(pt.X) > rotBounds.Right then rotBounds.Right := ceil(pt.X/sizeFactor)*sizeFactor;
    if ceil(pt.Y) > rotBounds.Bottom then rotBounds.Bottom := ceil(pt.Y/sizeFactor)*sizeFactor;
  end;

begin
  sizeFactor := 1;
  cache := RunCacheOn;
  key := '';
  if cache then
  begin
    sig := IntToStr(AOrientation) + ',' + FontSig(FFont);
    key := 'T' + sig + sUTF8;
  end;
  if not (cache and (GSizes <> nil) and GSizes.TryGetValue(key, size)) then
  begin
    with MeasureSurface(FFont) do
    begin
      Canvas.Font.Orientation := AOrientation;
      size := Canvas.TextExtent(sUTF8);
    end;
    if cache then
    begin
      if GSizes = nil then GSizes := specialize TDictionary<string, TSize>.Create;
      if GSizes.Count >= GdiSizesMaxCount then GSizes.Clear;
      GSizes.Add(key, size);
    end;
  end;
  if (size.cx = 0) or (size.cy = 0) then Exit;
  { BGRA's extra vertical margin measures the run a second time with the orientation
    put back to the same angle, so it is always 0 and dy is 0. }
  dy := 0;

  cosA := cos(AOrientation*Pi/1800);
  sinA := sin(AOrientation*Pi/1800);
  TopLeft := PointF(sinA*dy,cosA*dy);
  posF := PointF(xf,yf);
  posF.Offset( TopLeft * (1/sizeFactor) );
  TopRight := TopLeft + PointF(cosA*size.cx,-sinA*size.cx);
  BottomRight := TopRight + PointF(sinA*size.cy,cosA*size.cy);
  BottomLeft := TopLeft + PointF(sinA*size.cy,cosA*size.cy);
  rotBounds := rect(0,0,0,0);
  Top := 0;
  Left := 0;
  rotBoundsAdd(TopRight);
  rotBoundsAdd(BottomRight);
  rotBoundsAdd(BottomLeft);
  inc(rotBounds.Right);
  inc(rotBounds.Bottom);

  posF.Offset( Left/sizeFactor, Top/sizeFactor );
  case align of
    taLeftJustify: ;
    taCenter:
      posF.Offset( -TopRight*(1/(2*sizeFactor)) );
    taRightJustify:
      posF.Offset( -TopRight*(1/sizeFactor) );
  end;
  x := floor(posF.x);
  deltaX := HalfUp((posF.x - x)*sizeFactor);
  y := floor(posF.y);
  deltaY := HalfUp((posF.y - y)*sizeFactor);
  if deltaX <> 0 then inc(rotBounds.Right, sizeFactor);
  if deltaY <> 0 then inc(rotBounds.Bottom, sizeFactor);

  w := rotBounds.Right - rotBounds.Left;
  h := rotBounds.Bottom - rotBounds.Top;
  if (w <= 0) or (h <= 0) then Exit;
  { the mask is the run's at this angle and this sub-pixel offset }
  if cache then
  begin
    key := 'M' + IntToStr(deltaX) + ',' + IntToStr(deltaY) + ',' + sig + sUTF8;
    mask := TGrayscaleMask(FindRun(key));
    if mask <> nil then
    begin
      mask.DrawAsAlpha(ADest, x, y, c);
      Exit;
    end;
  end;
  if (w > GdiKeptMaxWidth) or (Int64(w) * h > GdiKeptMaxPixels) then
  begin
    { too big to keep: BGRA's own path, scratch and all }
    BGRATextOutAngle(ADest, FFont, FontQuality, xf, yf, AOrientation, sUTF8, c, nil, align, 0);
    Exit;
  end;
  nw := 0;
  nh := 0;
  if GTurn <> nil then
  begin
    nw := GTurn.Width;
    nh := GTurn.Height;
  end;
  if nw < w then nw := Min(Max(w, nw + nw div 2), GdiKeptMaxWidth);
  if nh < h then nh := Max(h, nh + nh div 2);
  if Int64(nw) * nh > GdiKeptMaxPixels then nh := Max(h, GdiKeptMaxPixels div nw);
  if GTurn = nil then
  begin
    GTurn := TBitmap.Create;
    GTurn.PixelFormat := pf32bit;
    GTurn.SetSize(nw, nh);
    Inc(GKeptMade);
  end
  else if (GTurn.Width <> nw) or (GTurn.Height <> nh) then
  begin
    GTurn.SetSize(nw, nh);
    Inc(GKeptMade);
  end;
  if (LCLIntf.GetObject(GTurn.Handle, SizeOf(ds), @ds) <> SizeOf(ds))
    or (ds.dsBm.bmBits = nil) or (ds.dsBm.bmBitsPixel <> 32) then
  begin
    BGRATextOutAngle(ADest, FFont, FontQuality, xf, yf, AOrientation, sUTF8, c, nil, align, 0);
    Exit;
  end;
  bottomUp := TTyBitmapAccess(GTurn).GetRawImageDescriptionPtr^.LineOrder = riloBottomToTop;
  bits := ds.dsBm.bmBits;
  bpp := 4;
  stride := ds.dsBm.bmWidthBytes;
  { BGRABlack, as BGRA's scratch is made: blue, green, red 0, alpha 255 }
  TyGdiFlush;
  for py := 0 to h - 1 do
  begin
    if bottomUp then
      line := bits + (ds.dsBm.bmHeight - 1 - py) * stride
    else
      line := bits + py * stride;
    for px := 0 to w - 1 do
      PLongWord(line + px * bpp)^ := $FF000000;
  end;
  { BGRATextOutAngle's "with temp do": the font, white, its height, then
    BitmapTextOutAngle's orientation and clear brush and TCanvas.TextOut. }
  GTurn.Canvas.Font.PixelsPerInch := ScreenInfo.PixelsPerInchY;
  GTurn.Canvas.Font := FFont;
  GTurn.Canvas.Font.Color := clWhite;
  GTurn.Canvas.Font.Height := FFont.Height*sizeFactor;
  GTurn.Canvas.Font.Orientation := AOrientation;
  GTurn.Canvas.Brush.Style := bsClear;
  GTurn.Canvas.TextOut(-rotBounds.Left+deltaX, -rotBounds.Top+deltaY, sUTF8);
  TyGdiFlush;
  mask := TGrayscaleMask.Create(w, h, 0);
  try
    for py := 0 to h - 1 do
    begin
      if bottomUp then
        line := bits + (ds.dsBm.bmHeight - 1 - py) * stride
      else
        line := bits + py * stride;
      pdest := mask.ScanLine[py];
      for px := 0 to w - 1 do
      begin
        pdest^ := GammaExpansionTab[line[px * bpp + 1]] shr 8;
        Inc(pdest);
      end;
    end;
    mask.DrawAsAlpha(ADest, x, y, c);
    if cache then
    begin
      KeepRun(key, mask, w * h);
      mask := nil;
    end;
  finally
    mask.Free;
  end;
end;

procedure TTyGdiTextRenderer.InternalTextOutAngle(ADest: TBGRACustomBitmap; x, y: single;
  AOrientation: integer; sUTF8: string; c: TBGRAPixel; texture: IBGRAScanner;
  align: TAlignment; AShowPrefix: boolean; ARightToLeft: boolean);
var
  sz: TSize;
  ofsX: Single;
  ox, oy, mx, my, w, h, px, py, dx, dy, cov, a: Integer;
  cr, cg, cb, ir, ig, ib, v: Integer;
  flags: Cardinal;
  r: TRect;
  tmp: TBitmap;
  shot: TBGRABitmap;
  row: PBGRAPixel;
  ink: TBGRAPixel;
  kept, lightInk, cache, clearType, wrote: Boolean;
  dline, d: PBGRAPixel;
  ds: TDIBSection;
  bits, line, pc: PByte;
  stride, bpp, nw, nh: Integer;
  bottomUp: Boolean;
  run: TTyRunInk;
  key: string;
begin
  if sUTF8 = '' then Exit;
  if (AOrientation mod 3600 <> 0) and (texture = nil) and not FOwnUnderline
    and not AShowPrefix and (FontQuality = fqSystem) and SystemFontAvailable
    and (GetCurrentThreadId = MainThreadID) and not GBgraPaths then
  begin
    { BGRA's own turned path, on the kept surfaces }
    if c.alpha <> 0 then TurnedTextOut(ADest, x, y, AOrientation, sUTF8, c, align);
    Exit;
  end;
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
  { the run's coverage, kept (see GRuns): it is the text's, in this font, in this polarity }
  cache := RunCacheOn;
  key := '';
  run := nil;
  if cache then
  begin
    key := 'S' + IntToStr(Ord(lightInk)) + IntToStr(Ord(ARightToLeft))
      + IntToStr(Ord(AShowPrefix)) + ',' + FontSig(FFont) + sUTF8;
    run := TTyRunInk(FindRun(key));
  end;
  if run = nil then
  begin
    run := TTyRunInk.Create;
    run.W := w;
    run.H := h;
    SetLength(run.Cov, w * h * 3);
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
      { the whole box's coverage, row by row }
      pc := PByte(run.Cov);
      for py := 0 to h - 1 do
      begin
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
          { a DIB row is blue, green, red }
          if line <> nil then
          begin
            cb := line[px * bpp];
            cg := line[px * bpp + 1];
            cr := line[px * bpp + 2];
          end
          else
          begin
            cr := row[px].red;
            cg := row[px].green;
            cb := row[px].blue;
          end;
          if not lightInk then
          begin
            cr := 255 - cr;
            cg := 255 - cg;
            cb := 255 - cb;
          end;
          pc[0] := cr;
          pc[1] := cg;
          pc[2] := cb;
          Inc(pc, 3);
        end;
      end;
    finally
      shot.Free;
      if not kept then
        tmp.Free;
    end;
    if cache then KeepRun(key, run, w * h * 3);
  end;
  try
    ink := c;
    ir := c.red;   { Integer copies: (byte - byte) of a field goes negative here }
    ig := c.green;
    ib := c.blue;
    clearType := TyDesktopClearType;
    wrote := False;
    for py := 0 to h - 1 do
    begin
      dy := oy - my + py;
      if (dy < ADest.ClipRect.Top) or (dy >= ADest.ClipRect.Bottom) then Continue;
      pc := PByte(run.Cov) + py * w * 3;
      dline := nil;
      for px := 0 to w - 1 do
      begin
        cr := pc[px * 3];
        cg := pc[px * 3 + 1];
        cb := pc[px * 3 + 2];
        if (cr = 0) and (cg = 0) and (cb = 0) then Continue;
        dx := ox - mx + px;
        { An opaque surface: each coverage on its own channel, as GDI lays it on a window. }
        if clearType and (dx >= ADest.ClipRect.Left) and (dx < ADest.ClipRect.Right) then
        begin
          if dline = nil then dline := ADest.ScanLine[dy];
          d := dline + dx;
          if d^.alpha = 255 then
          begin
            v := d^.red;
            d^.red := v + (ir - v) * (cr * c.alpha div 255) div 255;
            v := d^.green;
            d^.green := v + (ig - v) * (cg * c.alpha div 255) div 255;
            v := d^.blue;
            d^.blue := v + (ib - v) * (cb * c.alpha div 255) div 255;
            wrote := True;
            Continue;
          end;
        end;
        cov := (cr + cg + cb) div 3;
        if cov > 0 then
        begin
          a := cov * c.alpha div 255;
          if a > 0 then
          begin
            ink.alpha := a;
            ADest.FastBlendPixel(dx, dy, ink);   // clipped against ClipRect there
          end;
        end;
      end;
    end;
    if wrote then
      ADest.InvalidateBitmap;   // written through ScanLine, as FastBlendPixel does after its own
  finally
    if not cache then run.Free;
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
  FreeAndNil(TTyGdiTextRenderer.GMeasure);
  FreeAndNil(TTyGdiTextRenderer.GTurn);
  TTyGdiTextRenderer.DropRuns;
  {$ENDIF}
end;

procedure TyGdiTextRunCacheForTest(AOn: Boolean);
begin
  {$IFDEF LCLWin32}
  TTyGdiTextRenderer.GNoRunCache := not AOn;
  {$ELSE}
  if AOn then ;
  {$ENDIF}
end;

function TyGdiTextRunsKeptForTest: Integer;
begin
  Result := 0;
  {$IFDEF LCLWin32}
  if TTyGdiTextRenderer.GRuns <> nil then Result := TTyGdiTextRenderer.GRuns.Count;
  {$ENDIF}
end;

function TyGdiTextKeptSurfacesMadeForTest: Integer;
begin
  {$IFDEF LCLWin32}
  Result := TTyGdiTextRenderer.GKeptMade;
  {$ELSE}
  Result := 0;
  {$ENDIF}
end;

procedure TyGdiTextBgraPathsForTest(AOn: Boolean);
begin
  {$IFDEF LCLWin32}
  TTyGdiTextRenderer.GBgraPaths := AOn;
  {$ELSE}
  if AOn then ;
  {$ENDIF}
end;

procedure TyGdiTextDropKept;
begin
  {$IFDEF LCLWin32}
  FreeAndNil(TTyGdiTextRenderer.GMeasure);
  FreeAndNil(TTyGdiTextRenderer.GTurn);
  TTyGdiTextRenderer.DropRuns;
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
  {$ENDIF}
  {$IFDEF LCLCocoa}
  if not (ABmp.FontRenderer is TTyCanvasTextRenderer) then
    ABmp.FontRenderer := TTyCanvasTextRenderer.Create;
  {$ENDIF}
  {$IF not defined(LCLWin32) and not defined(LCLCocoa)}
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
  ABmp.FontStyle := TyFontStylesOf(AWeight);
end;

function TyWrapTextToWidth(const AText, AFontName: string;
  AFontSizeLogical, AWeight, APPI, AMaxWidthPx: Integer): string;
var
  lines: TStringList;
begin
  Result := AText;
  if (AText = '') or (AMaxWidthPx <= 0) then Exit;
  lines := TStringList.Create;
  try
    TyConfigureMeasureFont(BlockScratch.Canvas, AFontName, AFontSizeLogical,
                           AWeight, APPI);
    TyWrapTextCJK(AText, AMaxWidthPx, BlockScratch.Canvas, lines);
    if lines.Count > 0 then Result := TrimRight(lines.Text);
  finally
    lines.Free;
  end;
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
    big enough to hold the string. SHARED rather than allocated per call, as
    TyMeasureTextBlock's TBitmap is -- see RenderScratch above for why sharing one is
    safe, and for the measurement that says why it is worth doing. }
  Meas := RenderScratch;
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

constructor TTyPainter.Create;
begin
  inherited Create;
  FScale := 1;
end;

procedure TTyPainter.BeginPaint(ACanvas: TCanvas; const ARect: TRect; APPI: Integer;
  ARightToLeft: Boolean = False);
begin
  BeginPaintScaled(ACanvas, ARect, APPI, TyCanvasDeviceScale(ACanvas), ARightToLeft);
end;

procedure TTyPainter.BeginPaintScaled(ACanvas: TCanvas; const ARect: TRect; APPI: Integer;
  const AScale: TTyCanvasScale; ARightToLeft: Boolean = False);
begin
  ReleaseClipMasks;
  { A frame starts with no dash and an empty state stack: vector state must
    not survive from the previous paint. }
  FVecDash := nil;
  FVecDashStack := nil;
  FVecDashOffset := 0;
  FVecDashOffsetStack := nil;
  FPathOpen := False;
  FCanvas := ACanvas;
  FRect := ARect;
  FRightToLeft := ARightToLeft;
  if APPI <= 0 then
    FPPI := 96
  else
    FPPI := APPI;
  FLayoutPPI := FPPI;
  FScale := AScale.Scale;
  if FScale < 1 then FScale := 1;
  FDeviceUnits := AScale.DeviceUnits;
  FRasterDepth := 0;
  Opacity := 1.0;
  OpacityBase := 0;   // 0 alpha = "not set" -> EndPaint uses the old alpha-reduce path
  FBmp := TBGRABitmap.Create((ARect.Right - ARect.Left) * FScale, (ARect.Bottom - ARect.Top) * FScale);
  FOwnsBmp := True;
  FKeptC2D := False;
  FBmp.Fill(BGRAPixelTransparent);
  if FScale > 1 then PresetCanvas2D;
end;

procedure TTyPainter.BeginPaintOn(ACanvas: TCanvas; const ARect: TRect;
  APPI: Integer; ABmp: TBGRABitmap; ARightToLeft: Boolean = False);
begin
  BeginPaintOnScaled(ACanvas, ARect, APPI, ABmp, TyCanvasDeviceScale(ACanvas), ARightToLeft);
end;

procedure TTyPainter.BeginPaintOnScaled(ACanvas: TCanvas; const ARect: TRect; APPI: Integer;
  ABmp: TBGRABitmap; const AScale: TTyCanvasScale; ARightToLeft: Boolean = False);
var
  w, h: Integer;
begin
  ReleaseClipMasks;
  { A frame starts with no dash and an empty state stack: vector state must
    not survive from the previous paint. }
  FVecDash := nil;
  FVecDashStack := nil;
  FVecDashOffset := 0;
  FVecDashOffsetStack := nil;
  FPathOpen := False;
  FCanvas := ACanvas;
  FRect := ARect;
  FRightToLeft := ARightToLeft;
  if APPI <= 0 then FPPI := 96 else FPPI := APPI;
  FLayoutPPI := FPPI;
  FScale := AScale.Scale;
  if FScale < 1 then FScale := 1;
  FDeviceUnits := AScale.DeviceUnits;
  FRasterDepth := 0;
  Opacity := 1.0;
  OpacityBase := 0;
  FBmp := ABmp;
  { **不清空** —— 上一帧的像素正是要复用的东西;清哪一块由调用方决定。
    The raster rect has to fit: a bitmap smaller than it is grown (a resized surface holds
    nothing the frame can reuse anyway). One that is LARGER keeps its size and its pixels --
    a terminal surface rounded up to 64-px blocks, a scroll bar's host frame: what lies
    outside the rect is the caller's (plan B Task 4; the 3.0 line resized it to the rect). }
  w := (ARect.Right - ARect.Left) * FScale;
  h := (ARect.Bottom - ARect.Top) * FScale;
  if (FBmp <> nil) and ((FBmp.Width < w) or (FBmp.Height < h)) then
    FBmp.SetSize(Max(FBmp.Width, w), Max(FBmp.Height, h));
  FOwnsBmp := False;
  { The surface outlives the frame, and BGRA keeps its Canvas2D -- transform and stroke
    transform -- across SetSize: note what the caller had, so that EndPaint puts it back and a
    frame at S = 1 (the window moved to a one-times screen) does not find scale(S) there. }
  FKeptC2D := (FBmp <> nil) and (FScale > 1);
  if FKeptC2D then
  begin
    FKeptMatrix := FBmp.Canvas2D.matrix;
    FKeptStrokeMatrix := FBmp.Canvas2D.strokeMatrix;
    PresetCanvas2D;
  end;
end;

procedure TTyPainter.PresetCanvas2D;
begin
  FBmp.Canvas2D.resetTransform;
  FBmp.Canvas2D.scale(FScale, FScale);
  { BGRA keeps the stroke geometry apart from the path transform: lineWidth is taken in device
    pixels through strokeMatrix, not through the matrix above. Scale it too, so a lineWidth set
    in layout pixels strokes S times as wide, as it would on an HTML canvas. }
  FBmp.Canvas2D.strokeResetTransform;
  FBmp.Canvas2D.strokeScale(FScale, FScale);
end;

procedure TTyPainter.BlitScaled(ABmp: TBGRABitmap; AOpaque: Boolean);
begin
  if FDeviceUnits then
    ABmp.Draw(FCanvas, FRect.Left * FScale, FRect.Top * FScale, AOpaque)
  else
    ABmp.Draw(FCanvas, FRect, AOpaque);
end;

function TTyPainter.GetRasterPPI: Integer;
begin
  Result := FLayoutPPI * FScale;
end;

function TTyPainter.Dev(AValue: Integer): Integer;
begin
  Result := AValue * FScale;
end;

function TTyPainter.Dev(const ARect: TRect): TRect;
begin
  Result := Rect(ARect.Left * FScale, ARect.Top * FScale, ARect.Right * FScale, ARect.Bottom * FScale);
end;

function TTyPainter.Dev(const APoint: TPoint): TPoint;
begin
  Result := Point(APoint.X * FScale, APoint.Y * FScale);
end;

function TTyPainter.RasterEnter: Boolean;
begin
  Inc(FRasterDepth);
  Result := (FRasterDepth = 1) and (FScale > 1);
  if Result then FPPI := FLayoutPPI * FScale;
end;

procedure TTyPainter.RasterLeave;
begin
  Dec(FRasterDepth);
  if FRasterDepth <= 0 then
  begin
    FRasterDepth := 0;
    FPPI := FLayoutPPI;
  end;
end;

procedure TTyPainter.EndPaint;
var
  baseBmp, layer: TBGRABitmap;
  c: TBGRAPixel;
  rw, rh: Integer;
  partOnly: Boolean;
begin
  { before the bitmap goes: a kept bitmap's canvas must not be left sharing them }
  ReleaseClipMasks;
  if FKeptC2D then
  begin
    { The two transforms only: a path the caller has open holds device points already. }
    FKeptC2D := False;
    if FBmp <> nil then
    begin
      FBmp.Canvas2D.matrix := FKeptMatrix;
      FBmp.Canvas2D.strokeMatrix := FKeptStrokeMatrix;
    end;
  end;
  if Assigned(FBmp) then
  begin
    { What lands is the raster rect. A caller's bitmap larger than it (BeginPaintOn) keeps the
      rest for itself: that part is neither drawn nor dimmed. }
    layer := FBmp;
    rw := (FRect.Right - FRect.Left) * FScale;
    rh := (FRect.Bottom - FRect.Top) * FScale;
    partOnly := Assigned(FCanvas) and (not FOwnsBmp) and ((FBmp.Width > rw) or (FBmp.Height > rh));
    if partOnly then
      layer := FBmp.GetPart(Rect(0, 0, rw, rh)) as TBGRABitmap;
    try
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
        baseBmp := TBGRABitmap.Create(layer.Width, layer.Height, c);
        try
          if FScale = 1 then
            baseBmp.Draw(FCanvas, FRect.Left, FRect.Top, True)
          else
            BlitScaled(baseBmp, True);
        finally
          baseBmp.Free;
        end;
        layer.ApplyGlobalOpacity(Round(Opacity * 255));
        if FScale = 1 then
          layer.Draw(FCanvas, FRect.Left, FRect.Top, False)
        else
          BlitScaled(layer, False);
        if FOwnsBmp then FreeAndNil(FBmp) else FBmp := nil;
        FScale := 1;
        Exit;
      end;
      if Opacity < 1.0 then
        layer.ApplyGlobalOpacity(Round(Opacity * 255));
      if FScale = 1 then
        layer.Draw(FCanvas, FRect.Left, FRect.Top, False)
      else
        BlitScaled(layer, False);
    end;
    finally
      if partOnly then layer.Free;   // the copy; FBmp itself may be gone by now (the Exit above)
    end;
    if FOwnsBmp then FreeAndNil(FBmp) else FBmp := nil;
  end;
  FScale := 1;
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

{ Measuring: deliberately OUTSIDE the raster scope, so the font is configured at the layout
  PPI and the answer is in layout pixels however large the layer is (#83). }
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
  R: TRect;
begin
  if RasterEnter then R := Dev(ARect) else R := ARect;
  try
    FillBackgroundAt(R, AFill, ACorners);
  finally
    RasterLeave;
  end;
end;

procedure TTyPainter.FillBackgroundAt(const ARect: TRect; const AFill: TTyFill; const ACorners: TTyCorners);
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
        { PLAIN sRGB, BOTH PATHS. A themed gradient blends channel by channel in sRGB, as a
          CSS gradient and Canvas 2D do, so the colours of a web design come out here as they
          do in a browser. BGRA defaults the other way -- its two-colour scanner blends with
          gamma correction (exponent 1.7, a lighter midpoint) -- and when only the multi-stop
          path turned it off, the same two colours met in a different middle depending on
          whether they were written as two colours or as stops. }
        if TyGradientNeedsStops(AFill) then
        begin
          // v3/B1 multi-stop: build a BGRA multi-gradient from the stops. Two stops at 0 and 1
          // take the two-colour scanner below, which is the cheaper of the two and blends the
          // same way; two stops anywhere else are placed by position -- the two-colour scanner
          // spread '#F00 20%, #00F 80%' over the whole sweep (#49).
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
          // The last argument is gammaColorCorrection, which DEFAULTS to True: spelled out.
          grad := TBGRAGradientScanner.Create(TyColorToBGRA(AFill.GradFrom), TyColorToBGRA(AFill.GradTo),
            gtLinear, p1f, p2f, False);
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
{ Canvas2D, but in the raster scope like the rect methods, not through the preset scale(S,S):
  the outline follows the pixel-index convention of StrokeBorder (Right - 1, a half-line
  inset), which a matrix would double along with everything else. So the geometry is mapped
  here and drawn with the Canvas2D transforms set aside for the call. }
var
  body: TRect;
  tip, halfBase, height: Integer;
  ctx: TBGRACanvas2D;
begin
  if FBmp = nil then Exit;
  if RasterEnter then
  begin
    body := Dev(ABody);
    tip := Dev(ATipPos);
    halfBase := Dev(AHalfBase);
    height := Dev(AHeight);
  end
  else
  begin
    body := ABody;
    tip := ATipPos;
    halfBase := AHalfBase;
    height := AHeight;
  end;
  try
    if FScale > 1 then
    begin
      ctx := FBmp.Canvas2D;
      ctx.save;
      try
        ctx.resetTransform;
        ctx.strokeResetTransform;
        FillPointerShapeAt(body, ACorners, ASide, tip, halfBase, height, AFillColor,
          ABorderColor, ABorderWidthLogical);
      finally
        ctx.restore;
      end;
    end
    else
      FillPointerShapeAt(body, ACorners, ASide, tip, halfBase, height, AFillColor,
        ABorderColor, ABorderWidthLogical);
  finally
    RasterLeave;
  end;
end;

procedure TTyPainter.FillPointerShapeAt(const ABody: TRect; const ACorners: TTyCorners;
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
  CtxFill(ctx);

  w := Scale(ABorderWidthLogical);
  if (w <= 0) or (TyAlphaOf(ABorderColor) = 0) then Exit;
  half := w / 2;
  { The pointer rides the SAME inset as the body edge, so the wedge is translated inward, not
    reshaped -- its two sides keep the slope the fill drew. }
  BuildPath(half);
  ctx.strokeStyle(TyColorToBGRA(ABorderColor));
  ctx.lineWidth := w;
  CtxStroke(ctx);
end;

procedure TTyPainter.StrokeBorder(const ARect: TRect; ARadiusLogical, AWidthLogical: Integer; AColor: TTyColor);
begin
  StrokeBorder(ARect, TyUniformCorners(ARadiusLogical), AWidthLogical, AColor);
end;

procedure TTyPainter.StrokeBorder(const ARect: TRect; const ACorners: TTyCorners; AWidthLogical: Integer; AColor: TTyColor);
var
  R: TRect;
begin
  if RasterEnter then R := Dev(ARect) else R := ARect;
  try
    StrokeBorderAt(R, ACorners, AWidthLogical, AColor);
  finally
    RasterLeave;
  end;
end;

procedure TTyPainter.StrokeBorderAt(const ARect: TRect; const ACorners: TTyCorners; AWidthLogical: Integer; AColor: TTyColor);
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
var
  R: TRect;
begin
  if RasterEnter then R := Dev(ARect) else R := ARect;
  try
    DrawEdgeAt(R, AWidthLogical, ATLColor, ABRColor);
  finally
    RasterLeave;
  end;
end;

procedure TTyPainter.DrawEdgeAt(const ARect: TRect; AWidthLogical: Integer; ATLColor, ABRColor: TTyColor);
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
var
  R: TRect;
begin
  if RasterEnter then R := Dev(ARect) else R := ARect;
  try
    DrawGlyphBitmapAt(R, ABmp);
  finally
    RasterLeave;
  end;
end;

procedure TTyPainter.DrawGlyphBitmapAt(const ARect: TRect; ABmp: TBGRABitmap);
var x, y: Integer;
begin
  if (FBmp = nil) or (ABmp = nil) then Exit;
  x := ARect.Left + ((ARect.Right - ARect.Left) - ABmp.Width) div 2;
  y := ARect.Top + ((ARect.Bottom - ARect.Top) - ABmp.Height) div 2;
  FBmp.PutImage(x, y, ABmp, dmDrawWithTransparency);
end;

type
  { A rendered shadow, cropped to the pixels that carry any alpha, and where that crop sat
    in the bitmap it was rendered on. }
  TTyShadowEntry = class
    Bmp: TBGRABitmap;
    Origin: TPoint;
    destructor Destroy; override;
  end;

destructor TTyShadowEntry.Destroy;
begin
  Bmp.Free;
  inherited Destroy;
end;

const
  { Pixels the shadow cache may hold, all entries together (4 bytes each: 16 MB). A shadow
    bigger than that on its own is drawn every time, as before. Counted in LAYOUT pixels: a
    layer at device scale S holds S^2 raster pixels for each, so on that screen the cache
    keeps as many shadows as at S = 1, in S^2 the bytes; at S = 1 nothing changes (#83). }
  ShadowCacheMaxPixels = 4 * 1024 * 1024;

var
  GShadowCache: TStringList = nil;   // sorted key -> TTyShadowEntry (OwnsObjects)
  GShadowCachePixels: Int64 = 0;
  GShadowsRendered: Integer = 0;

function TyShadowsRendered: Integer;
begin
  Result := GShadowsRendered;
end;

procedure TyClearShadowCache;
begin
  if GShadowCache <> nil then GShadowCache.Clear;
  GShadowCachePixels := 0;
end;

function TyBitmapIsOpaque(ABmp: TBGRABitmap): Boolean;
var
  y, x: Integer;
  p: PBGRAPixel;
begin
  Result := False;
  if ABmp = nil then Exit;
  for y := 0 to ABmp.Height - 1 do
  begin
    p := ABmp.ScanLine[y];
    for x := 0 to ABmp.Width - 1 do
    begin
      if p^.alpha <> 255 then Exit;
      Inc(p);
    end;
  end;
  Result := True;
end;


{ DROP SHADOWS ARE RENDERED ONCE PER LOOK.
  A shadow is a blur of the control's outline over a bitmap the size of the control, redone
  on every paint: 38 ms for a 400 x 300 card, 300 ms for 1200 x 800, so a shadowed card
  (fluent's cards and buttons carry one) stalled on every hover. What it depends on is all
  here -- the bitmap's size, the outline, the corner radius, the blur, the colour -- so it is
  kept under exactly that key; the offset is applied when it is laid down. The cache holds
  the blur cropped to its ink and puts it back where it came from: every pixel outside the
  crop is fully transparent, which a transparent draw leaves alone, so the result is the
  same bytes. Main thread only (another thread renders as before); bounded by
  ShadowCacheMaxPixels, emptied whole when full. }
procedure TTyPainter.DropShadow(const ARect: TRect; ARadiusLogical: Integer; AColor: TTyColor; ABlurLogical: Integer; const AOffsetLogical: TPoint);
var
  R: TRect;
begin
  if RasterEnter then R := Dev(ARect) else R := ARect;
  try
    DropShadowAt(R, ARadiusLogical, AColor, ABlurLogical, AOffsetLogical);
  finally
    RasterLeave;
  end;
end;

procedure TTyPainter.DropShadowAt(const ARect: TRect; ARadiusLogical: Integer; AColor: TTyColor; ABlurLogical: Integer; const AOffsetLogical: TPoint);
var
  r, blur, ox, oy, idx: Integer;
  shadow, blurred: TBGRABitmap;
  px: TBGRAPixel;
  key: string;
  useCache: Boolean;
  entry: TTyShadowEntry;
  ink: TRect;
  sq, cost: Int64;
begin
  if FBmp = nil then
    Exit;
  sq := Int64(FScale) * FScale;   // raster pixels per layout pixel
  r := Scale(ARadiusLogical);
  r := TyClampRadiusPx(r, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
  blur := Scale(ABlurLogical);
  ox := Scale(AOffsetLogical.X);
  oy := Scale(AOffsetLogical.Y);
  px := TyColorToBGRA(AColor);
  useCache := TyShadowCacheEnabled and (GetCurrentThreadId = MainThreadID)
    and (Int64(FBmp.Width) * FBmp.Height <= ShadowCacheMaxPixels * sq);
  key := '';
  if useCache then
  begin
    key := Format('%d,%d|%d,%d,%d,%d|%d|%d|%.2x%.2x%.2x%.2x', [FBmp.Width, FBmp.Height,
      ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, r, blur,
      px.red, px.green, px.blue, px.alpha]);
    if GShadowCache <> nil then
    begin
      idx := GShadowCache.IndexOf(key);
      if idx >= 0 then
      begin
        entry := TTyShadowEntry(GShadowCache.Objects[idx]);
        if entry.Bmp <> nil then
          FBmp.PutImage(ox + entry.Origin.X, oy + entry.Origin.Y, entry.Bmp, dmDrawWithTransparency);
        Exit;
      end;
    end;
  end;
  Inc(GShadowsRendered);
  shadow := TBGRABitmap.Create(FBmp.Width, FBmp.Height, BGRAPixelTransparent);
  blurred := nil;
  try
    if r <= 0 then
      shadow.FillRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, px, dmSet)
    else
      shadow.FillRoundRectAntialias(ARect.Left, ARect.Top, ARect.Right - 1, ARect.Bottom - 1, r, r, px, [rrDefault]);
    if blur > 0 then
    begin
      blurred := shadow.FilterBlurRadial(blur, rbFast) as TBGRABitmap;
      FBmp.PutImage(ox, oy, blurred, dmDrawWithTransparency);
    end
    else
      FBmp.PutImage(ox, oy, shadow, dmDrawWithTransparency);
    if useCache then
    begin
      if blurred = nil then
      begin
        blurred := shadow;
        shadow := nil;
      end;
      entry := TTyShadowEntry.Create;
      ink := blurred.GetImageBounds;
      if not IsRectEmpty(ink) then
      begin
        entry.Bmp := blurred.GetPart(ink) as TBGRABitmap;
        entry.Origin := ink.TopLeft;
      end;
      if GShadowCache = nil then
      begin
        GShadowCache := TStringList.Create;
        GShadowCache.Sorted := True;
        GShadowCache.Duplicates := dupError;
        GShadowCache.OwnsObjects := True;
      end;
      if entry.Bmp <> nil then
      begin
        cost := Int64(entry.Bmp.Width) * entry.Bmp.Height div sq;
        if GShadowCachePixels + cost > ShadowCacheMaxPixels then
          TyClearShadowCache;
        Inc(GShadowCachePixels, cost);
      end;
      GShadowCache.AddObject(key, entry);
    end;
  finally
    shadow.Free;
    blurred.Free;
  end;
end;

{ StarPath and DrawStar stay OUTSIDE the raster scope on purpose: their geometry is pure (a
  centre and radii, no pixel-index convention), so the scale(S,S) BeginPaint presets on the
  Canvas2D draws them at the device scale from layout coordinates -- which is also what lets a
  control trace StarPath and then fill or clip with its own Canvas2D calls (TTyRating). }
procedure TTyPainter.StarPath(ACx, ACy, AOuter, AInner: Double);
var
  ctx: TBGRACanvas2D;
  k: Integer;
  ang, rr: Double;
begin
  if FBmp = nil then Exit;
  ctx := FBmp.Canvas2D;
  ctx.beginPath;
  FPathOpen := True;
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
    CtxFill(ctx);
  end
  else
  begin
    ctx.lineWidth := Math.Max(1, Scale(1));
    ctx.strokeStyle(TyColorToBGRA(AColor));
    CtxStroke(ctx);
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
  R: TRect;
begin
  { The only way text gets onto the layer: DrawTextLine, DrawTextLineBidi and
    DrawTextSupersampled are reached from here alone, so they receive the raster rect and
    configure their fonts at the raster PPI. The measuring side (MeasureText, TextCaretX,
    TextCharIndexAtX) stays out of the scope on purpose: it answers in layout pixels. }
  if RasterEnter then R := Dev(ARect) else R := ARect;
  try
    DrawTextAt(R, AText, AFontName, AFontSizeLogical, AWeight, AColor, AHAlign, AVAlign,
      AEllipsis, AMnemonicPos, ASmallCrisp, AMultiLine, ALineHeightLogical);
  finally
    RasterLeave;
  end;
end;

procedure TTyPainter.DrawTextAt(const ARect: TRect; const AText, AFontName: string; AFontSizeLogical, AWeight: Integer; AColor: TTyColor; AHAlign: TAlignment; AVAlign: TTextLayout; AEllipsis: Boolean; AMnemonicPos: Integer; ASmallCrisp: Boolean; AMultiLine: Boolean; ALineHeightLogical: Integer);
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
  R: TRect;
begin
  if RasterEnter then R := Dev(ARect) else R := ARect;
  try
    DrawGlyphAt(R, AGlyph, AColor, AThicknessLogical, APadLogical);
  finally
    RasterLeave;
  end;
end;

procedure TTyPainter.DrawGlyphAt(const ARect: TRect; AGlyph: TTyGlyphKind; AColor: TTyColor; AThicknessLogical: Integer; APadLogical: Integer);
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
    tgChevronUp:
      { tgChevronDown reflected about the box's horizontal centre line (y -> t + b - y). }
      FBmp.DrawPolyLineAntialias([PointF(l, b - h * 0.3),
        PointF(cx, t + h * 0.2), PointF(r, b - h * 0.3)], px, th);
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
  R: TRect;
begin
  if RasterEnter then R := Dev(AZoneRect) else R := AZoneRect;
  try
    DrawDropChevronAt(R, AColor, ASizeLogical);
  finally
    RasterLeave;
  end;
end;

procedure TTyPainter.DrawDropChevronAt(const AZoneRect: TRect; AColor: TTyColor; ASizeLogical: Integer);
begin
  DrawChevronAt(AZoneRect, tgChevronDown, AColor, ASizeLogical);
end;

procedure TTyPainter.DrawChevron(const AZoneRect: TRect; AKind: TTyGlyphKind; AColor: TTyColor; ASizeLogical: Integer);
var
  R: TRect;
begin
  if RasterEnter then R := Dev(AZoneRect) else R := AZoneRect;
  try
    DrawChevronAt(R, AKind, AColor, ASizeLogical);
  finally
    RasterLeave;
  end;
end;

procedure TTyPainter.DrawChevronAt(const AZoneRect: TRect; AKind: TTyGlyphKind; AColor: TTyColor; ASizeLogical: Integer);
var
  len, half, th, zx, zy, ax, ay: Single;
  px: TBGRAPixel;
  pts: array[0..2] of TPointF;
  oldJoin: TPenJoinStyle;
begin
  if FBmp = nil then Exit;
  px := TyColorToBGRA(AColor);
  len := Scale(ASizeLogical);
  if len < 4 then len := 4;
  half := len / 2;
  th := len * 5 / 28;
  if th < 1 then th := 1;
  { The zone's centre in BGRA's coordinates, where a pixel's CENTRE is the whole number: a
    zone [0, 18) covers pixels 0..17, so its centre is 8.5, not 9. }
  zx := (AZoneRect.Left + AZoneRect.Right - 1) / 2;
  zy := (AZoneRect.Top + AZoneRect.Bottom - 1) / 2;
  { The ink box is centred on the zone; the apex is then rounded onto a pixel centre, the
    same way on both sides of a .5 (Floor(x + 0.5), not banker's Round). }
  case AKind of
    tgChevronUp:
      begin
        ax := Floor(zx + 0.5); ay := Floor(zy - half / 2 + 0.5);
        pts[0] := PointF(ax - half, ay + half); pts[1] := PointF(ax, ay); pts[2] := PointF(ax + half, ay + half);
      end;
    tgChevronRight:
      begin
        ax := Floor(zx + half / 2 + 0.5); ay := Floor(zy + 0.5);
        pts[0] := PointF(ax - half, ay - half); pts[1] := PointF(ax, ay); pts[2] := PointF(ax - half, ay + half);
      end;
    tgChevronLeft:
      begin
        ax := Floor(zx - half / 2 + 0.5); ay := Floor(zy + 0.5);
        pts[0] := PointF(ax + half, ay - half); pts[1] := PointF(ax, ay); pts[2] := PointF(ax + half, ay + half);
      end;
  else
    begin
      ax := Floor(zx + 0.5); ay := Floor(zy + half / 2 + 0.5);
      pts[0] := PointF(ax - half, ay - half); pts[1] := PointF(ax, ay); pts[2] := PointF(ax + half, ay - half);
    end;
  end;
  oldJoin := FBmp.JoinStyle;
  FBmp.JoinStyle := pjsRound;
  try
    { AClosedCap TRUE: BGRA's False means "leave the LAST point open so a next segment can
      join it" -- no cap and a gap -- which made the second arm visibly shorter than the
      first (the V's right arm, the >'s lower one). Both ends take the pen's round cap. }
    FBmp.DrawPolyLineAntialias(pts, px, th, True);
  finally
    FBmp.JoinStyle := oldJoin;
  end;
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

function GetCachedImage(const APath: string; ABlurDev: Integer): TBGRABitmap; forward;
function GetCachedScaledImage(const APath: string; APicture: TBGRABitmap;
  AScale: Integer): TBGRABitmap; forward;

procedure TTyPainter.NineSlice(const ARect: TRect; const AImagePath: string; const AInsets: TRect; ATile: Boolean);
var
  R: TRect;
begin
  if RasterEnter then R := Dev(ARect) else R := ARect;
  try
    NineSliceAt(R, AImagePath, AInsets, ATile);
  finally
    RasterLeave;
  end;
end;

procedure TTyPainter.NineSliceAt(const ARect: TRect; const AImagePath: string; const AInsets: TRect; ATile: Boolean);
var
  src: TBGRABitmap;
  iw, ih: Integer;
  sl, st, sr, sb: Integer;
  dl, dt, dr, db: Integer;
  sxL, sxR, syT, syB: Integer;
begin
  if FBmp = nil then
    Exit;
  { The image cache DrawImageFill uses (owned by it -- not freed here): the file was read
    from disk on every paint. }
  src := GetCachedImage(AImagePath, 0);
  if src = nil then
    Exit;
  begin
    sl := AInsets.Left;
    st := AInsets.Top;
    sr := AInsets.Right;
    sb := AInsets.Bottom;
    { A theme image is a one-times asset, its pixels layout pixels (#83). On a layer at a device
      scale it is taken S times as large, insets too, so a frame keeps its thickness in layout
      pixels; each image pixel lands on S x S device pixels, as the system would have put it. }
    if FScale > 1 then
    begin
      { the cache owns src (main's GetCachedImage): the S-times picture is kept beside it under
        its own key, made once, and src is neither freed nor replaced in the cache }
      src := GetCachedScaledImage(AImagePath, src, FScale);
      sl := sl * FScale;
      st := st * FScale;
      sr := sr * FScale;
      sb := sb * FScale;
    end;
    iw := src.Width;
    ih := src.Height;
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
  end;
end;

procedure TTyPainter.FillImageSlice(const ARect: TRect; ASrc: TBGRABitmap;
  const ASrcOffset: TPoint);
var
  R: TRect;
  O: TPoint;
begin
  { The backdrop is kept at the device scale too (TTyForm.RebuildBackdrop), so the
    offset into it is mapped with the rect. }
  if RasterEnter then
  begin
    R := Dev(ARect);
    O := Dev(ASrcOffset);
  end
  else
  begin
    R := ARect;
    O := ASrcOffset;
  end;
  try
    FillImageSliceAt(R, ASrc, O);
  finally
    RasterLeave;
  end;
end;

procedure TTyPainter.FillImageSliceAt(const ARect: TRect; ASrc: TBGRABitmap; const ASrcOffset: TPoint);
{ Blit a (clamped) slice of a backdrop bitmap 1:1 into ARect — used as the opaque
  base behind ANY control on an image-backed form, so its corners read as the same
  photo the form shows instead of a flat solid fill. }
var
  w, h, ovL, ovT, ovR, ovB: Integer;
  part: TBGRABitmap;
  oldClip, dst: TRect;
  src: TPoint;
begin
  if (FBmp = nil) or (ASrc = nil) then Exit;
  { Only the part of ARect that lands on this bitmap is copied out of the backdrop. For a
    control filling its own rect that is ARect itself and nothing below changes; it matters
    for a child painting its HOST's backdrop, whose rect is mostly off the child's bitmap
    (an embedded scroll bar), where copying the whole host-sized slice would be pure waste. }
  if not IntersectRect(dst, ARect, Rect(0, 0, FBmp.Width, FBmp.Height)) then Exit;
  src := Point(ASrcOffset.X + (dst.Left - ARect.Left), ASrcOffset.Y + (dst.Top - ARect.Top));
  w := dst.Right - dst.Left;
  h := dst.Bottom - dst.Top;
  if (w <= 0) or (h <= 0) then Exit;
  ovL := src.X; if ovL < 0 then ovL := 0;
  ovT := src.Y; if ovT < 0 then ovT := 0;
  ovR := src.X + w; if ovR > ASrc.Width then ovR := ASrc.Width;
  ovB := src.Y + h; if ovB > ASrc.Height then ovB := ASrc.Height;
  if (ovR <= ovL) or (ovB <= ovT) then Exit;
  oldClip := FBmp.ClipRect;
  FBmp.ClipRect := dst;
  try
    part := ASrc.GetPart(Rect(ovL, ovT, ovR, ovB)) as TBGRABitmap;
    try
      FBmp.PutImage(dst.Left + (ovL - src.X),
                    dst.Top  + (ovT - src.Y), part, dmSet);
    finally
      part.Free;
    end;
  finally
    FBmp.ClipRect := oldClip;
  end;
end;

procedure TTyPainter.FillGlass(const ARect: TRect; AGlass: TBGRABitmap;
  const ASrcOffset: TPoint; const ATint: TTyColor; const ACorners: TTyCorners);
var
  R: TRect;
  O: TPoint;
begin
  { The backdrop is kept at the device scale too (TTyForm.RebuildBackdrop), so the
    offset into it is mapped with the rect. }
  if RasterEnter then
  begin
    R := Dev(ARect);
    O := Dev(ASrcOffset);
  end
  else
  begin
    R := ARect;
    O := ASrcOffset;
  end;
  try
    FillGlassAt(R, AGlass, O, ATint, ACorners);
  finally
    RasterLeave;
  end;
end;

procedure TTyPainter.FillGlassAt(const ARect: TRect; AGlass: TBGRABitmap; const ASrcOffset: TPoint; const ATint: TTyColor; const ACorners: TTyCorners);
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
  R: TRect;
begin
  if RasterEnter then R := Dev(ARect) else R := ARect;
  try
    FillCornerGapsAt(R, ACorners, AColor);
  finally
    RasterLeave;
  end;
end;

procedure TTyPainter.FillCornerGapsAt(const ARect: TRect; const ACorners: TTyCorners; AColor: TTyColor);
var
  temp: TBGRABitmap;
  w, h, r: Integer;
  vis: TRect;
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
  { Only over the part of ARect that is on the bitmap: the shape keeps its full geometry (the
    erase is offset, not shrunk), so a control filling its own rect gets exactly what it got
    before, and a child replaying its host's frame does not allocate a host-sized buffer. }
  if not IntersectRect(vis, ARect, Rect(0, 0, FBmp.Width, FBmp.Height)) then Exit;
  temp := TBGRABitmap.Create(vis.Right - vis.Left, vis.Bottom - vis.Top, TyColorToBGRA(AColor));
  try
    temp.EraseRoundRectAntialias(ARect.Left - vis.Left, ARect.Top - vis.Top,
      ARect.Left - vis.Left + w - 1, ARect.Top - vis.Top + h - 1, r, r, 255, opts);
    FBmp.PutImage(vis.Left, vis.Top, temp, dmDrawWithTransparency);
  finally
    temp.Free;
  end;
end;

procedure TTyPainter.EraseRect(const ARect: TRect);
var
  R: TRect;
begin
  if RasterEnter then R := Dev(ARect) else R := ARect;
  try
    EraseRectAt(R);
  finally
    RasterLeave;
  end;
end;

procedure TTyPainter.EraseRectAt(const ARect: TRect);
begin
  if FBmp = nil then Exit;
  FBmp.FillRect(ARect.Left, ARect.Top, ARect.Right, ARect.Bottom, BGRA(0,0,0,0), dmSet);
end;

procedure TTyPainter.DrawRule(AX1, AY1, AX2, AY2: Integer; const AColor: TBGRAPixel);
var
  R: TRect;
  mapped: Boolean;
begin
  mapped := RasterEnter;
  try
    if (AX1 <> AX2) and (AY1 <> AY2) then
    begin
      { Slanted: there is no "one layout pixel wide" for it to keep, so it is the plain line. }
      if FBmp = nil then Exit;
      if mapped then
        FBmp.DrawLine(Dev(AX1), Dev(AY1), Dev(AX2), Dev(AY2), AColor, False)
      else
        FBmp.DrawLine(AX1, AY1, AX2, AY2, AColor, False);
      Exit;
    end;
    if AY1 = AY2 then
    begin
      if AX1 = AX2 then Exit;
      if AX2 > AX1 then R := Rect(AX1, AY1, AX2, AY1 + 1)
      else R := Rect(AX2 + 1, AY1, AX1 + 1, AY1 + 1);
    end
    else if AY2 > AY1 then R := Rect(AX1, AY1, AX1 + 1, AY2)
    else R := Rect(AX1, AY2 + 1, AX1 + 1, AY1 + 1);
    if mapped then R := Dev(R);
    DrawRuleAt(R, AColor);
  finally
    RasterLeave;
  end;
end;

procedure TTyPainter.DrawRuleAt(const ARect: TRect; const AColor: TBGRAPixel);
begin
  if FBmp = nil then Exit;
  FBmp.FillRect(ARect, AColor, dmDrawWithTransparency);
end;

var
  GImgCache: TStringList = nil;  // key 'path|blurDev' -> TBGRABitmap (OwnsObjects)

{ APicture -- GetCachedImage's picture for APath -- AScale times as large, each pixel on
  AScale x AScale (#83: a theme image is a one-times asset, NineSlice at a device scale). Kept
  in the same cache under its own key ('path|xS'), made once: the original stays the cache's,
  untouched. }
function GetCachedScaledImage(const APath: string; APicture: TBGRABitmap;
  AScale: Integer): TBGRABitmap;
var
  key: string;
  idx: Integer;
begin
  key := APath + '|x' + IntToStr(AScale);
  idx := GImgCache.IndexOf(key);   // there: APicture came from it
  if idx >= 0 then
    Exit(TBGRABitmap(GImgCache.Objects[idx]));
  Result := APicture.Resample(APicture.Width * AScale, APicture.Height * AScale,
    rmSimpleStretch) as TBGRABitmap;
  GImgCache.AddObject(key, Result);
end;

{ Load (and optionally blur) an image once, cached by path + device-px blur radius.
  The returned bitmap is owned by the cache — callers must not free it. }
function GetCachedImage(const APath: string; ABlurDev: Integer): TBGRABitmap;
var
  key: string;
  idx: Integer;
  raw, bl: TBGRABitmap;
begin
  Result := nil;
  if GImgCache = nil then
  begin
    GImgCache := TStringList.Create;
    GImgCache.OwnsObjects := True;
  end;
  key := APath + '|' + IntToStr(ABlurDev);
  idx := GImgCache.IndexOf(key);
  if idx >= 0 then
    Exit(TBGRABitmap(GImgCache.Objects[idx]));
  { Asked only on a miss: a hit costs no file-system call. }
  if not FileExists(APath) then Exit;
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
  R: TRect;
begin
  if RasterEnter then R := Dev(ARect) else R := ARect;
  try
    DrawImageFillAt(R, AImagePath, AMode, ABlurLogical);
  finally
    RasterLeave;
  end;
end;

procedure TTyPainter.DrawImageFillAt(const ARect: TRect; const AImagePath: string; AMode: TTyImageMode; ABlurLogical: Integer);
var
  src: TBGRABitmap;
  iw, ih, dw, dh, sw, sh, ox, oy: Integer;
  sc, scW, scH: Double;
  oldClip: TRect;
begin
  if FBmp = nil then Exit;
  { The image is a one-times asset whose pixels are layout pixels (#83): blurred at the LAYOUT
    radius, then stretched onto the raster with the rest of the picture; centred, it is drawn S
    times its size. At S = 1 the layout PPI is the PPI. }
  src := GetCachedImage(AImagePath, MulDiv(ABlurLogical, FLayoutPPI, 96));
  if src = nil then Exit;
  iw := src.Width * FScale; ih := src.Height * FScale;
  dw := ARect.Right - ARect.Left; dh := ARect.Bottom - ARect.Top;
  if (iw <= 0) or (ih <= 0) or (dw <= 0) or (dh <= 0) then Exit;
  oldClip := FBmp.ClipRect;
  FBmp.ClipRect := ARect;
  try
    case AMode of
      timStretch:
        FBmp.StretchPutImage(ARect, src, dmDrawWithTransparency);
      timCenter:
        if FScale = 1 then
          FBmp.PutImage(ARect.Left + (dw - iw) div 2, ARect.Top + (dh - ih) div 2,
            src, dmDrawWithTransparency)
        else
          FBmp.StretchPutImage(Bounds(ARect.Left + (dw - iw) div 2, ARect.Top + (dh - ih) div 2,
            iw, ih), src, dmDrawWithTransparency);
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

{ ===== The device scale (#83) ================================================ }

type
  TTyRasterCanvasEntry = record
    Canvas: TCanvas;
    Scale: Integer;
  end;

var
  GRasterCanvases: array of TTyRasterCanvasEntry;
  GForcedScale: Integer = 0;
  GForcedDeviceUnits: Boolean = False;
  GForcedNilCanvas: Boolean = True;

function RasterCanvasIndex(ACanvas: TCanvas): Integer;
var
  i: Integer;
begin
  for i := 0 to High(GRasterCanvases) do
    if GRasterCanvases[i].Canvas = ACanvas then Exit(i);
  Result := -1;
end;

function TyDeviceScaleOf(AFactor: Double): Integer;
begin
  if IsNan(AFactor) or (AFactor <= 0) then Exit(1);
  if AFactor > 4 then Exit(4);
  Result := Round(AFactor);
  if Result < 1 then Result := 1;
end;

function TyCanvasDeviceScale(ACanvas: TCanvas): TTyCanvasScale;
var
  i: Integer;
begin
  Result.Scale := 1;
  Result.DeviceUnits := False;
  if not TyDeviceScaleRendering then Exit;
  { A raster cache's canvas answers its own registration first, the test seam included: it is
    in device units whatever the window it is blitted to is in, and a seam answering it as a
    window would paint the cache at half size on a layout-units run. }
  if ACanvas <> nil then
  begin
    i := RasterCanvasIndex(ACanvas);
    if i >= 0 then
    begin
      Result.Scale := GRasterCanvases[i].Scale;
      Result.DeviceUnits := True;
      Exit;
    end;
  end;
  if (GForcedScale > 0) and ((ACanvas <> nil) or GForcedNilCanvas) then
  begin
    Result.Scale := GForcedScale;
    Result.DeviceUnits := GForcedDeviceUnits;
    Exit;
  end;
  if ACanvas = nil then Exit;
  { The system is asked through the platform facade, never here: a widgetset that needs its own
    query gets it in PlatformWS and its WS unit, and this unit stays free of widgetset IFDEFs. }
  if (ACanvas is TControlCanvas) and (TControlCanvas(ACanvas).Control <> nil) then
    Result.Scale := TyDeviceScaleOf(TyControlDeviceScale(TControlCanvas(ACanvas).Control));
end;

procedure TyRegisterRasterCanvas(ACanvas: TCanvas; AScale: Integer);
var
  i: Integer;
begin
  if ACanvas = nil then Exit;
  i := RasterCanvasIndex(ACanvas);
  if i < 0 then
  begin
    i := Length(GRasterCanvases);
    SetLength(GRasterCanvases, i + 1);
    GRasterCanvases[i].Canvas := ACanvas;
  end;
  GRasterCanvases[i].Scale := AScale;
end;

procedure TyUnregisterRasterCanvas(ACanvas: TCanvas);
var
  i: Integer;
begin
  i := RasterCanvasIndex(ACanvas);
  if i < 0 then Exit;
  GRasterCanvases[i] := GRasterCanvases[High(GRasterCanvases)];
  SetLength(GRasterCanvases, Length(GRasterCanvases) - 1);
end;

function TyCanvasRect(ACanvas: TCanvas; const ALayout: TRect): TRect;
var
  sc: TTyCanvasScale;
begin
  sc := TyCanvasDeviceScale(ACanvas);
  if sc.DeviceUnits and (sc.Scale > 1) then
    Result := Rect(ALayout.Left * sc.Scale, ALayout.Top * sc.Scale,
      ALayout.Right * sc.Scale, ALayout.Bottom * sc.Scale)
  else
    Result := ALayout;
end;

procedure TyDrawRasterBitmap(ACanvas: TCanvas; const ALayout: TRect; ABmp: TBGRABitmap;
  AOpaque: Boolean);
var
  sc: TTyCanvasScale;
begin
  if (ACanvas = nil) or (ABmp = nil) then Exit;
  sc := TyCanvasDeviceScale(ACanvas);
  if (sc.Scale <= 1) or sc.DeviceUnits then
    ABmp.Draw(ACanvas, TyCanvasRect(ACanvas, ALayout).Left, TyCanvasRect(ACanvas, ALayout).Top,
      AOpaque)
  else
    ABmp.Draw(ACanvas, ALayout, AOpaque);
end;

function TyRegisteredRasterScale(ACanvas: TCanvas): Integer;
var
  i: Integer;
begin
  i := RasterCanvasIndex(ACanvas);
  if i < 0 then Result := 0 else Result := GRasterCanvases[i].Scale;
end;

procedure TyForceDeviceScaleForTest(AScale: Integer; ADeviceUnits: Boolean;
  ANilCanvasToo: Boolean = True);
begin
  GForcedScale := AScale;
  GForcedDeviceUnits := ADeviceUnits;
  GForcedNilCanvas := ANilCanvasToo;
end;

{ ============================ VECTOR PATH API ============================
  See the declaration block in the interface for the units convention and for
  why this lives on the painter instead of each caller reaching for Canvas2D.

  Every drawing entry point below sets each canvas property it depends on. The
  TBGRACanvas2D is cached per bitmap, so the chrome primitives above -- and any
  earlier vector call -- may have left it in any state. }

function TyVecPoint(AX, AY: Double): TTyVecPoint;
begin
  Result.X := AX;
  Result.Y := AY;
end;

{ TFillMode for a rule. Named separately so every call site reads as the rule
  the caller asked for rather than as a BGRA enum. }
function VecFillMode(ARule: TTyFillRule): TFillMode;
begin
  if ARule = tfrEvenOdd then
    Result := fmAlternate
  else
    Result := fmWinding;
end;

function TTyPainter.ScaleF(ALogical: Double): Double;
begin
  if FPPI <= 0 then
    Exit(ALogical);
  Result := ALogical * FPPI / 96;
end;

{ ---- path building ---- }

procedure TTyPainter.BeginPath;
begin
  if FBmp = nil then Exit;
  FBmp.Canvas2D.beginPath;
  FPathOpen := False;
end;

procedure TTyPainter.ClosePath;
begin
  if FBmp = nil then Exit;
  FBmp.Canvas2D.closePath;
end;

procedure TTyPainter.MoveTo(AX, AY: Double);
begin
  if FBmp = nil then Exit;
  FBmp.Canvas2D.moveTo(AX, AY);
  FPathOpen := True;
end;

procedure TTyPainter.LineTo(AX, AY: Double);
begin
  if FBmp = nil then Exit;
  FBmp.Canvas2D.lineTo(AX, AY);
  FPathOpen := True;
end;

procedure TTyPainter.CurveTo(AC1X, AC1Y, AC2X, AC2Y, AX, AY: Double);
begin
  if FBmp = nil then Exit;
  FBmp.Canvas2D.bezierCurveTo(AC1X, AC1Y, AC2X, AC2Y, AX, AY);
  FPathOpen := True;
end;

procedure TTyPainter.QuadTo(ACX, ACY, AX, AY: Double);
begin
  if FBmp = nil then Exit;
  FBmp.Canvas2D.quadraticCurveTo(ACX, ACY, AX, AY);
  FPathOpen := True;
end;

procedure TTyPainter.ArcTo(ACX, ACY, ARadius, AStartRad, AEndRad: Double;
  AAnticlockwise: Boolean);
begin
  if FBmp = nil then Exit;
  FBmp.Canvas2D.arc(ACX, ACY, ARadius, AStartRad, AEndRad, AAnticlockwise);
  FPathOpen := True;
end;

procedure TTyPainter.PolylineTo(const APoints: array of TTyVecPoint);
var
  i: Integer;
begin
  if (FBmp = nil) or (Length(APoints) = 0) then Exit;
  for i := 0 to High(APoints) do
    FBmp.Canvas2D.lineTo(APoints[i].X, APoints[i].Y);
  FPathOpen := True;
end;

procedure TTyPainter.RectPath(AL, AT, AR, AB: Double);
begin
  if FBmp = nil then Exit;
  FBmp.Canvas2D.rect(AL, AT, AR - AL, AB - AT);
  FPathOpen := True;
end;

procedure TTyPainter.RoundRectPath(AL, AT, AR, AB, ARadiusLogical: Double);
begin
  if FBmp = nil then Exit;
  { The only job here is the LOGICAL -> device conversion. Clamping an oversize
    radius is deliberately NOT done: TBGRACanvas2D.roundRect already does it
    (bgracanvas2d.pas:2685, `if radius*2 > w then radius := w/2`), and a second
    clamp would be dead code pretending to be a safeguard. Verified by mutation:
    removing a clamp here changed nothing. NOTE this is not the same entry point
    as FillRoundRectAntialias, which is the one TyClampRadiusPx exists for. }
  FBmp.Canvas2D.roundRect(AL, AT, AR - AL, AB - AT, ScaleF(ARadiusLogical));
  FPathOpen := True;
end;

procedure TTyPainter.EllipsePath(ACX, ACY, ARX, ARY: Double);
begin
  if FBmp = nil then Exit;
  { a sub-path of its own after anything else in the path [R2-F] }
  if FPathOpen then FBmp.Canvas2D.moveTo(ACX + ARX, ACY);
  FBmp.Canvas2D.ellipse(ACX, ACY, ARX, ARY);
  FPathOpen := True;
end;

procedure TTyPainter.CirclePath(ACX, ACY, AR: Double);
begin
  if FBmp = nil then Exit;
  { a sub-path of its own after anything else in the path: zrender's
    Circle.buildPath moves to (cx + r, cy) before its arc, where BGRA's
    circle is an arc from the current point [R2-F] }
  if FPathOpen then FBmp.Canvas2D.moveTo(ACX + AR, ACY);
  FBmp.Canvas2D.circle(ACX, ACY, AR);
  FPathOpen := True;
end;

procedure TTyPainter.SvgPath(const APathData: string);
begin
  if (FBmp = nil) or (APathData = '') then Exit;
  FBmp.Canvas2D.addPath(APathData);
  FPathOpen := True;
end;

procedure TTyPainter.SvgPathIn(const APathData: string; const ARect: TRect;
  AKeepAspect: Boolean);
var
  probe: TBGRAPath;
  bb: TRectF;
  w, h, sx, sy, sc, ox, oy: Double;
begin
  if (FBmp = nil) or (APathData = '') then Exit;
  { Measure the path's own bounds on a throwaway TBGRAPath, so the fit is
    computed without disturbing the canvas' current path or transform.
    TBGRAPath.getPoints is protected; GetBounds is the public way in. }
  probe := TBGRAPath.Create(APathData);
  try
    bb := probe.GetBounds;
  finally
    probe.Free;
  end;
  w := bb.Right - bb.Left;
  h := bb.Bottom - bb.Top;
  { No extent in either direction means nothing to fit. Flat in ONE direction is
    fitted on the other and left alone on that one, rather than blowing up to an
    infinite scale -- a horizontal rule symbol is a legitimate path. }
  if (w <= 0) and (h <= 0) then Exit;
  if w <= 0 then w := 1;
  if h <= 0 then h := 1;
  sx := (ARect.Right - ARect.Left) / w;
  sy := (ARect.Bottom - ARect.Top) / h;
  if AKeepAspect then
  begin
    if sx < sy then sc := sx else sc := sy;
    sx := sc;
    sy := sc;
  end;
  ox := (ARect.Left + ARect.Right) / 2 - (bb.Left + bb.Right) / 2 * sx;
  oy := (ARect.Top + ARect.Bottom) / 2 - (bb.Top + bb.Bottom) / 2 * sy;
  FBmp.Canvas2D.save;
  try
    FBmp.Canvas2D.translate(ox, oy);
    FBmp.Canvas2D.scale(sx, sy);
    FBmp.Canvas2D.addPath(APathData);
    FPathOpen := True;
  finally
    { The path keeps the points the transform produced; restoring here leaves
      the CTM as the caller left it, so a later fill is not scaled twice. }
    FBmp.Canvas2D.restore;
  end;
end;

{ ---- painting the current path ---- }

{ One ramp, built the same way for a fill and for a stroke. }
function BuildGradient(ctx: TBGRACanvas2D; const AStops: array of TTyGradStop;
  AX1, AY1, AX2, AY2, ARadius: Double): IBGRACanvasGradient2D;
var i: Integer; px: TBGRAPixel;
begin
  if ARadius > 0 then
    Result := ctx.createRadialGradient(AX1, AY1, 0, AX2, AY2, ARadius)
  else
    Result := ctx.createLinearGradient(AX1, AY1, AX2, AY2);
  Result.setColors(nil);
  for i := 0 to High(AStops) do
  begin
    px := TyColorToBGRA(AStops[i].Color);
    { A ZERO-ALPHA STOP LOSES ITS HUE in a straight-alpha interpolator, and
      BGRA's is straight: a ramp from an opaque red to `transparent` decays
      toward BLACK rather than fading out, because `transparent` is
      rgba(0,0,0,0) and its zero channels are still averaged in. Canvas 2D
      premultiplies and does not have the problem. Borrowing the neighbour's
      colour for an invisible stop makes the two agree and changes nothing
      about what that stop itself paints -- it is invisible either way. }
    if (px.alpha = 0) and (Length(AStops) > 1) then
    begin
      if i > 0 then px := TyColorToBGRA(AStops[i - 1].Color)
      else px := TyColorToBGRA(AStops[i + 1].Color);
      px.alpha := 0;
    end;
    Result.addColorStop(AStops[i].Pos, px);
  end;
  { GAMMA OFF, as for every gradient the painter draws (FillBackground,
    FillPathWith). BGRA's corrected ramp uses an exponent of 1.7 while Canvas 2D
    and CSS interpolate in plain sRGB, so a corrected ramp would put the
    midpoint of every chart gradient somewhere upstream never puts it. }
  Result.gammaCorrection := False;
end;

procedure TTyPainter.FillPathGradient(const AStops: array of TTyGradStop;
  AX1, AY1, AX2, AY2, ARadius: Double; ARule: TTyFillRule);
var
  ctx: TBGRACanvas2D;
  grad: IBGRACanvasGradient2D;
  i: Integer;
  px: TBGRAPixel;
begin
  if FBmp = nil then Exit;
  if Length(AStops) = 0 then Exit;
  ctx := FBmp.Canvas2D;
  ctx.fillMode := VecFillMode(ARule);
  grad := BuildGradient(ctx, AStops, AX1, AY1, AX2, AY2, ARadius);
  ctx.fillStyle(grad);
  CtxFill(ctx);
end;

procedure TTyPainter.FillPathPattern(AImage: TBGRABitmap;
  const ARepetition: string; const AMatrix: array of Double; ARule: TTyFillRule);
var
  ctx: TBGRACanvas2D;
  pat: IBGRACanvasTextureProvider2D;
  tex: TBGRAAffineBitmapTransform;
  rx, ry: Boolean;
  m: TAffineMatrix;
begin
  if (FBmp = nil) or (AImage = nil) or (Length(AMatrix) < 6) then Exit;
  if (AImage.Width <= 0) or (AImage.Height <= 0) then Exit;
  ctx := FBmp.Canvas2D;
  ctx.fillMode := VecFillMode(ARule);
  rx := True;
  ry := True;
  if LowerCase(Trim(ARepetition)) = 'repeat-x' then ry := False
  else if LowerCase(Trim(ARepetition)) = 'repeat-y' then rx := False
  else if LowerCase(Trim(ARepetition)) = 'no-repeat' then
  begin
    rx := False;
    ry := False;
  end;
  { OUR OWN TEXTURE rather than createPattern(image): that one fits the
    image's first and LAST pixel centres to the tile's corners, which
    stretches a tile by width / (width - 1) the moment its origin is not a
    whole pixel. Here the scanner is asked at device pixel CENTRES and the
    image's pixel centres sit at its integer coordinates, so the map from
    image to device is the pattern's matrix with half a pixel taken off on
    the way in and put back on the way out. }
  tex := TBGRAAffineBitmapTransform.Create(AImage, rx, ry, rfLinear);
  try
    { AMatrix maps the image to layout pixels; the scanner works on the raster, which is
      FScale times that (#83 -- the pattern is made with the transform reset, so the
      Canvas2D preset does not apply here) }
    m := AffineMatrixTranslation(-0.5, -0.5)
      * AffineMatrixScale(FScale, FScale)
      * AffineMatrix(AMatrix[0], AMatrix[2], AMatrix[4],
                     AMatrix[1], AMatrix[3], AMatrix[5])
      * AffineMatrixTranslation(0.5, 0.5);
    tex.Matrix := m;
    tex.Invert;
    { the pattern's own transform is the identity: createPattern(texture)
      adds only the canvas offset, which the scanner's coordinates already
      are }
    ctx.save;
    try
      ctx.resetTransform;
      pat := ctx.createPattern(tex);
    finally
      ctx.restore;
    end;
    ctx.fillStyle(pat);
    try
      CtxFill(ctx);
    finally
      pat := nil;
    end;
  finally
    tex.Free;
  end;
end;

procedure TTyPainter.StrokePathGradient(
  const AStops: array of TTyGradStop;
  AX1, AY1, AX2, AY2, ARadius, AWidthLogical: Double);
var
  ctx: TBGRACanvas2D;
  grad: IBGRACanvasGradient2D;
  w: Double;
begin
  if FBmp = nil then Exit;
  if Length(AStops) = 0 then Exit;
  w := ScaleF(AWidthLogical);
  { The same floor StrokePath keeps: a width that scaled to nothing is
    still a hairline, not an absence. }
  if w <= 0 then Exit;
  ctx := FBmp.Canvas2D;
  grad := BuildGradient(ctx, AStops, AX1, AY1, AX2, AY2, ARadius);
  ctx.strokeStyle(grad);
  ctx.lineWidth := w;
  CtxStroke(ctx);
end;

procedure TTyPainter.FillPath(AColor: TTyColor; ARule: TTyFillRule);
var
  ctx: TBGRACanvas2D;
begin
  if FBmp = nil then Exit;
  ctx := FBmp.Canvas2D;
  ctx.fillMode := VecFillMode(ARule);
  ctx.fillStyle(TyColorToBGRA(AColor));
  CtxFill(ctx);
end;

procedure TTyPainter.FillPathWith(const AFill: TTyFill; const ABounds: TRect;
  ARule: TTyFillRule);
var
  ctx: TBGRACanvas2D;
  grad: IBGRACanvasGradient2D;
  pat: IBGRACanvasTextureProvider2D;
  p1, p2: TPointF;
  i, bw, bh: Integer;
  img, scaled: TBGRABitmap;
begin
  if (FBmp = nil) or (AFill.Kind = tfkNone) then Exit;
  ctx := FBmp.Canvas2D;
  ctx.fillMode := VecFillMode(ARule);
  scaled := nil;
  case AFill.Kind of
    tfkLinearGradient:
      begin
        GradientEndpoints(ABounds, AFill.GradAngleDeg, p1, p2);
        grad := ctx.createLinearGradient(p1.x, p1.y, p2.x, p2.y);
        if Length(AFill.GradStops) > 1 then
          for i := 0 to High(AFill.GradStops) do
            grad.addColorStop(AFill.GradStops[i].Pos,
                              TyColorToBGRA(AFill.GradStops[i].Color))
        else
        begin
          grad.addColorStop(0, TyColorToBGRA(AFill.GradFrom));
          grad.addColorStop(1, TyColorToBGRA(AFill.GradTo));
        end;
        { Plain sRGB, as FillBackground blends the same fill. The canvas starts its
          gradients that way today (gradientGammaCorrection = False), but that is a
          per-canvas setting anyone can flip; the fill's answer should not depend on it. }
        grad.gammaCorrection := False;
        ctx.fillStyle(grad);
      end;
    tfkImage, tfkNineSlice:
      begin
        { A PATH-SHAPED TEXTURE. This used to fall through to AFill.Color and
          claim that was a graceful degrade -- but an image fill's Color is
          tyTransparent, so it painted nothing at all and said nothing about
          it. The suggested alternative, clipping to the path and image-filling
          the bounds, cannot work either: DrawImageFill sets FBmp.ClipRect, a
          rectangle on the bitmap, and never sees the Canvas2D clip mask that
          ClipPath writes.

          A path cannot be nine-sliced -- slicing needs four corners -- so a
          nine-slice fill tiles like any other texture here. That is a real
          answer rather than an invisible one, and the chrome primitives still
          slice properly where there are corners to slice. }
        img := GetCachedImage(AFill.ImagePath, Scale(AFill.Blur));
        if img = nil then
          ctx.fillStyle(TyColorToBGRA(AFill.Color))
        else
        begin
          bw := ABounds.Right - ABounds.Left;
          bh := ABounds.Bottom - ABounds.Top;
          { ANCHORED TO THE BOUNDS. createPattern takes its origin from the
            current transform, and the path was already built -- BGRA applies
            the matrix as points are ADDED -- so moving the matrix now moves
            the tiling and not the shape. }
          ctx.save;
          try
            ctx.translate(ABounds.Left, ABounds.Top);
            if (AFill.ImageMode = timStretch) and (bw > 0) and (bh > 0)
              and (img.Width > 0) and (img.Height > 0) then
            begin
              { Stretch means ONE tile the size of the bounds, so the image is
                resampled rather than repeated. Freed after the fill, because
                the pattern holds the bitmap rather than copying it. At a device
                scale it is resampled to the RASTER size and the pattern is put
                back by 1/S under the preset, so it lands pixel for pixel rather
                than magnified (#83). }
              scaled := img.Resample(bw * FScale, bh * FScale) as TBGRABitmap;
              if FScale > 1 then ctx.scale(1 / FScale, 1 / FScale);
              pat := ctx.createPattern(scaled, 'no-repeat');
            end
            else
              pat := ctx.createPattern(img, 'repeat');
          finally
            ctx.restore;
          end;
          ctx.fillStyle(pat);
        end;
      end;
  else
    ctx.fillStyle(TyColorToBGRA(AFill.Color));
  end;
  try
    CtxFill(ctx);
  finally
    { AFTER the fill: the pattern references this bitmap, it does not own a
      copy of it. }
    pat := nil;
    scaled.Free;
  end;
end;

const
  { [R2-V] the thinnest dashed pen laid, in device px: 1/512 of a pixel's
    coverage rounds to nothing in 8 bits }
  cThinDashPx = 1 / 512;

{ [R2-F] A DASH WITH A PHASE. BGRA's pen starts every pattern at its head
  (bgrapen.pas, ComputeWidePolylinePoints' FlushLine: posstyle := 0) and has
  no way in for a phase, and it refuses a pattern with a zero entry (it
  raises). Those are laid here: each sub-path of the current path walked by
  its length in the pen's space (where BGRA measures a pattern, in widths),
  the pattern starting APhase widths along it -- a canvas starts every
  sub-path's pattern at the offset -- each dash an open sub-path of its own,
  its caps on it as a canvas draws a dash (a dash of no length shows only
  where the cap has a size), and the lot stroked solid; then the path is put
  back as it was. False, with nothing done, where there is nothing to lay:
  no pattern, an entry negative or not a number, a pattern of no length, or
  -- no zero entry and -- a phase of whole periods: the pen's own dashing
  then, as ever, to the pixel. }
function StrokeDashPhased(ACtx: TBGRACanvas2D; const ADash: array of Single;
  APhase: Double): Boolean;
var
  pat: array of Double;
  n, i, j, s, e, di, nd: Integer;
  period, pos, left, segLen, zoom, unitLen, ox, oy: Double;
  pts, pen, dash: ArrayOfTPointF;
  sm, m, mi: TAffineMatrix;
  hasZero, on, open, flat: Boolean;
  dir: TPointF;
  dashes: array of ArrayOfTPointF;

  procedure Put(const AP: TPointF);
  begin
    if nd >= Length(dash) then SetLength(dash, nd * 2 + 8);
    dash[nd] := AP;
    Inc(nd);
  end;

  procedure Emit;
  var q: Integer;
  begin
    if nd = 0 then Exit;
    { a dash of no length: nothing under a butt cap; under a square or a
      round one, a stub along the way it was going }
    q := 1;
    while (q < nd) and (dash[q] = dash[0]) do Inc(q);
    if q = nd then
    begin
      if flat then
      begin
        nd := 0;
        Exit;
      end;
      Put(dash[0] + dir * Single(unitLen * 1e-3));
    end;
    SetLength(dashes, Length(dashes) + 1);
    dashes[High(dashes)] := Copy(dash, 0, nd);
    nd := 0;
  end;

  function Along(const A, B: TPointF; AFrac: Double): TPointF;
  begin
    Result := PointF(A.x + (B.x - A.x) * AFrac, A.y + (B.y - A.y) * AFrac);
  end;

begin
  Result := False;
  n := Length(ADash);
  if n = 0 then Exit;
  hasZero := False;
  for i := 0 to n - 1 do
  begin
    if IsNan(ADash[i]) or IsInfinite(ADash[i]) or (ADash[i] < 0) then Exit;
    if ADash[i] = 0 then hasZero := True;
  end;
  { an odd pattern said twice, as the canvas' lineStyle does }
  if Odd(n) then
  begin
    SetLength(pat, 2 * n);
    for i := 0 to n - 1 do
    begin
      pat[i] := ADash[i];
      pat[n + i] := ADash[i];
    end;
  end
  else
  begin
    SetLength(pat, n);
    for i := 0 to n - 1 do pat[i] := ADash[i];
  end;
  period := 0;
  for i := 0 to High(pat) do period := period + pat[i];
  if not (period > 0) then Exit;
  if IsNan(APhase) or IsInfinite(APhase) then APhase := 0;
  pos := APhase - Floor(APhase / period) * period;
  if (pos >= period) or (pos < 0) then pos := 0;
  if (pos = 0) and not hasZero then Exit;
  pts := ACtx.currentPath;
  Result := True;
  if Length(pts) = 0 then Exit;
  { the pen's space: the stroke matrix without its move, its zoom taken out
    (TBGRAPenStroker.SetStrokeMatrix); a pattern's unit is the width there }
  sm := ACtx.strokeMatrix;
  sm[1, 3] := 0;
  sm[2, 3] := 0;
  zoom := Max(Sqrt(Sqr(sm[1, 1]) + Sqr(sm[2, 1])), Sqrt(Sqr(sm[1, 2]) + Sqr(sm[2, 2])));
  m := AffineMatrixIdentity;
  if zoom > 0 then m := sm * AffineMatrixScale(1 / zoom, 1 / zoom);
  if IsAffineMatrixInversible(m) then mi := AffineMatrixInverse(m)
  else
  begin
    m := AffineMatrixIdentity;
    mi := AffineMatrixIdentity;
  end;
  if zoom <= 0 then zoom := 1;
  unitLen := ACtx.lineWidth * zoom;
  if not (unitLen > 0) then
  begin
    Result := False;
    Exit;
  end;
  pen := mi * pts;
  flat := ACtx.lineCapLCL = pecFlat;
  dashes := nil;
  dash := nil;
  nd := 0;
  dir := PointF(1, 0);
  s := 0;
  while s <= High(pen) do
  begin
    if isEmptyPointF(pen[s]) then
    begin
      Inc(s);
      Continue;
    end;
    e := s;
    while (e < High(pen)) and not isEmptyPointF(pen[e + 1]) do Inc(e);
    { the sub-path's pattern from the phase }
    di := 0;
    left := pat[0] * unitLen;
    ox := pos * unitLen;
    while ox > 0 do
    begin
      if ox < left then
      begin
        left := left - ox;
        ox := 0;
      end
      else
      begin
        ox := ox - left;
        di := (di + 1) mod Length(pat);
        left := pat[di] * unitLen;
      end;
    end;
    on := not Odd(di);
    open := False;
    nd := 0;
    for j := s to e - 1 do
    begin
      segLen := Sqrt(Sqr(Double(pen[j + 1].x) - pen[j].x) + Sqr(Double(pen[j + 1].y) - pen[j].y));
      if not (segLen > 0) then Continue;
      dir := PointF((pen[j + 1].x - pen[j].x) / segLen, (pen[j + 1].y - pen[j].y) / segLen);
      ox := 0;
      while ox < segLen do
      begin
        if on and not open then
        begin
          Put(Along(pen[j], pen[j + 1], ox / segLen));
          open := True;
        end;
        if segLen - ox <= left then
        begin
          left := left - (segLen - ox);
          ox := segLen;
          if on then Put(pen[j + 1]);
        end
        else
        begin
          ox := ox + left;
          if on then
          begin
            Put(Along(pen[j], pen[j + 1], ox / segLen));
            Emit;
            open := False;
          end;
          di := (di + 1) mod Length(pat);
          left := pat[di] * unitLen;
          on := not Odd(di);
        end;
      end;
    end;
    if open then Emit;
    nd := 0;
    s := e + 1;
  end;
  ACtx.save;
  try
    ACtx.resetTransform;
    ACtx.beginPath;
    for i := 0 to High(dashes) do
    begin
      dash := m * dashes[i];
      ACtx.moveTo(dash[0]);
      for j := 1 to High(dash) do ACtx.lineTo(dash[j]);
    end;
    ACtx.lineStyle(psSolid);
    if Length(dashes) > 0 then CtxStroke(ACtx);
    { the path as the caller left it }
    ACtx.beginPath;
    open := False;
    for i := 0 to High(pts) do
      if isEmptyPointF(pts[i]) then open := False
      else if not open then
      begin
        ACtx.moveTo(pts[i]);
        open := True;
      end
      else
        ACtx.lineTo(pts[i]);
  finally
    ACtx.restore;
  end;
end;

procedure TTyPainter.StrokePath(AColor: TTyColor; AWidthLogical: Double);
var
  ctx: TBGRACanvas2D;
  w: Double;
  devDash: array of Single;
  i: Integer;
begin
  if FBmp = nil then Exit;
  w := ScaleF(AWidthLogical);
  { A theme that set a border width of 0 means "no border". Falling back to
    BGRA's default width would draw a hairline everywhere it was switched off. }
  if w <= 0 then Exit;
  { A DASHED PEN TOO THIN TO LEAVE A MARK is not laid [R2-V]: a dash written
    as a word scales with the width, and a width tweening to 0 (a state's
    borderWidth 0) passes 1e-7 px on its way -- hundreds of millions of
    dashes round one bar, a stroke that never finished. Under 1/512 px no
    pixel takes any of it in 8 bits. }
  if (Length(FVecDash) > 0) and (w < cThinDashPx) then Exit;
  ctx := FBmp.Canvas2D;
  ctx.lineWidth := w;
  { Logical px -> multiples of the device line width, which is what BGRA's pen
    pattern actually means. Scaling the pattern by the DPI directly (the obvious
    thing) would scale it twice, because the width it multiplies is already
    scaled -- a 6 px dash would come out 4x too long at 200 %. }
  SetLength(devDash, Length(FVecDash));
  for i := 0 to High(FVecDash) do
    devDash[i] := ScaleF(FVecDash[i]) / w;
  ctx.strokeStyle(TyColorToBGRA(AColor));
  { [R2-F] a phase: the dashes laid here, stroked solid }
  if StrokeDashPhased(ctx, devDash, ScaleF(FVecDashOffset) / w) then Exit;
  ctx.lineStyle(devDash);
  { [R4-P] a pen under one raster pixel, when asked for }
  if FFastStrokes and StrokeHairline(ctx) then Exit;
  CtxStroke(ctx);
end;

procedure TTyPainter.FillAndStrokePath(AFillColor, AStrokeColor: TTyColor;
  AWidthLogical: Double; ARule: TTyFillRule);
begin
  if FBmp = nil then Exit;
  FillPath(AFillColor, ARule);
  StrokePath(AStrokeColor, AWidthLogical);
end;

function TTyPainter.PathContains(AX, AY: Double;
  ARule: TTyFillRule): Boolean;
var
  ctx: TBGRACanvas2D;
begin
  if FBmp = nil then Exit(False);
  ctx := FBmp.Canvas2D;
  { SET, not assumed. isPointInPath reads this shared state, and leaving it
    alone made the answer depend on the last thing filled. }
  ctx.fillMode := VecFillMode(ARule);
  { the path's points went through the preset onto the raster; the point does not (#83) }
  Result := ctx.isPointInPath(AX * FScale, AY * FScale);
end;

{ ---- stroke state ---- }

procedure TTyPainter.SetLineDash(const APatternLogical: array of Double);
var
  i: Integer;
begin
  { RECORDED, not applied. BGRA measures a pen pattern in multiples of the line
    width, and the width arrives later at StrokePath, so the conversion has to
    happen there. An empty pattern means solid, and is stored as such rather than
    ignored -- the canvas state is shared, so a dash left over from the previous
    element would otherwise still be in force. }
  SetLength(FVecDash, Length(APatternLogical));
  for i := 0 to High(APatternLogical) do
    FVecDash[i] := APatternLogical[i];
  FVecDashOffset := 0;
end;

procedure TTyPainter.SetLineDash(const APatternLogical: array of Double;
  AOffsetLogical: Double);
begin
  SetLineDash(APatternLogical);
  if not (IsNan(AOffsetLogical) or IsInfinite(AOffsetLogical)) then
    FVecDashOffset := AOffsetLogical;
end;

procedure TTyPainter.SetLineCap(ACap: TTyLineCap);
begin
  if FBmp = nil then Exit;
  case ACap of
    tlcRound:  FBmp.Canvas2D.lineCapLCL := pecRound;
    tlcSquare: FBmp.Canvas2D.lineCapLCL := pecSquare;
  else
    FBmp.Canvas2D.lineCapLCL := pecFlat;
  end;
end;

procedure TTyPainter.SetLineJoin(AJoin: TTyLineJoin; AMiterLimit: Double);
begin
  if FBmp = nil then Exit;
  case AJoin of
    tljRound: FBmp.Canvas2D.lineJoinLCL := pjsRound;
    tljBevel: FBmp.Canvas2D.lineJoinLCL := pjsBevel;
  else
    FBmp.Canvas2D.lineJoinLCL := pjsMiter;
  end;
  if AMiterLimit > 0 then
    FBmp.Canvas2D.miterLimit := AMiterLimit;
end;

{ ---- state stack, transform, clip, per-element alpha ---- }

procedure TTyPainter.SaveState;
var
  n, i: Integer;
begin
  if FBmp = nil then Exit;
  FBmp.Canvas2D.save;
  { The dash lives beside the canvas state (see FVecDash), so it needs pushing
    here or a RestoreState would leave the previous element's dash in force. }
  n := Length(FVecDashStack);
  SetLength(FVecDashStack, n + 1);
  SetLength(FVecDashStack[n], Length(FVecDash));
  for i := 0 to High(FVecDash) do
    FVecDashStack[n][i] := FVecDash[i];
  SetLength(FVecDashOffsetStack, n + 1);
  FVecDashOffsetStack[n] := FVecDashOffset;
end;

procedure TTyPainter.RestoreState;
var
  n, i: Integer;
begin
  if FBmp = nil then Exit;
  FBmp.Canvas2D.restore;
  n := Length(FVecDashStack);
  if n = 0 then Exit;
  SetLength(FVecDash, Length(FVecDashStack[n - 1]));
  for i := 0 to High(FVecDash) do
    FVecDash[i] := FVecDashStack[n - 1][i];
  SetLength(FVecDashStack, n - 1);
  if n <= Length(FVecDashOffsetStack) then
  begin
    FVecDashOffset := FVecDashOffsetStack[n - 1];
    SetLength(FVecDashOffsetStack, n - 1);
  end;
end;

procedure TTyPainter.Translate(ADX, ADY: Double);
begin
  if FBmp = nil then Exit;
  FBmp.Canvas2D.translate(ADX, ADY);
end;

procedure TTyPainter.RotateBy(AAngleRad: Double);
begin
  if FBmp = nil then Exit;
  FBmp.Canvas2D.rotate(AAngleRad);
end;

procedure TTyPainter.ScaleBy(ASX, ASY: Double);
begin
  if FBmp = nil then Exit;
  FBmp.Canvas2D.scale(ASX, ASY);
end;

procedure TTyPainter.ResetTransform;
begin
  if FBmp = nil then Exit;
  FBmp.Canvas2D.resetTransform;
  { back to the device scale's preset, not to the identity: callers' coordinates stay layout
    pixels (#83). BGRA's resetTransform leaves the stroke matrix alone, so widths keep theirs. }
  if FScale > 1 then FBmp.Canvas2D.scale(FScale, FScale);
end;

procedure TTyPainter.ClipPath(ARule: TTyFillRule);
var
  ctx: TBGRACanvas2D;
begin
  if FBmp = nil then Exit;
  ctx := FBmp.Canvas2D;
  ctx.fillMode := VecFillMode(ARule);
  CtxClip(ctx);
end;

{ CLIP MASKS, REUSED.

  BGRA's Canvas2D clips with a grayscale mask the size of the whole surface: every clip
  allocates one filled white and one filled black, fills the path into the second and
  multiplies it into the first. A chart clips every element to its series' box, so a
  graph of 2,000 nodes on an 800 x 500 layer built 4,000 masks of 400 KB per frame --
  five seconds of a first frame, nearly all of it. The mask a clip gives a state with no
  clip yet depends only on the rect, the matrix it is traced under, the surface's size,
  antialiasing and pixel centring; ClipRect keeps the masks it built (GClipPool) and
  hands an identical request the kept one, shared, as Canvas2D's own save shares a
  parent's mask with the saved state (not owned: a later clip on the state copies it
  first, and restore does not free it). The pixels are the ones the clip would have
  made, because it is the mask the clip made.

  Canvas2D does not publish its current state. TBGRACanvasState2D is public (SetClipMask,
  clipMaskReadOnly) but the field holding it is private, so CanvasStateOf finds it once:
  in TBGRACanvas2D's own declaration order FSurface, StateStack, currentState follow one
  another, and the probe accepts the slot only if the three hold the surface, a TList and
  a TBGRACanvasState2D. A BGRA that lays them out otherwise is not recognised and every
  clip is built as before. }
{ [P2] THE KEPT MASKS OUTLIVE THE PAINTER. A chart paints every frame with a new painter
  (the static layer, the dynamic one, an animation's every tick), and every one of them
  built its series' box masks again -- a seventh of a long line's animation frame. So the
  masks sit in one pool for the process. An entry is owned by the painter whose canvas
  may share it, or spare: a painter takes a spare entry (or one of its own) on a hit, and
  evicts only those; one another live painter owns is neither handed out nor evicted.
  When a painter lets go (EndPaint, BeginPaint*, its destructor) the states of its canvas
  that share its entries get copies, as before, and the entries become spare -- a mask
  larger than cClipPoolKeepPx is freed then rather than kept. Main thread only, like the
  rest of the painter's caches.
  cClipPoolKeepPx counts LAYOUT pixels: a mask built at device scale S has S^2 raster pixels
  for each, and is kept up to S^2 cClipPoolKeepPx of them -- on that screen only (#83). }
const
  cClipPool = 4;
  cClipPoolKeepPx = 2 * 1024 * 1024;

var
  GStateSlot: Integer = -2;   // -2: not probed yet; -1: layout not recognised
  GClipMasksBuilt: Integer = 0;
  GClipReuseOff: Boolean = False;
  { Mask is a TGrayscaleMask (TObject: the interface does not use BGRAGrayscaleMask) }
  GClipPool: array[0..cClipPool - 1] of record
    Mask: TObject;
    R: TRect;
    M: TAffineMatrix;
    W, H: Integer;
    S: Integer;   // the device scale it was built at
    AA, PC: Boolean;
    Owner: TObject;
  end;
  GClipPoolNext: Integer = 0;

procedure ClipPoolFreeAll;
var i: Integer;
begin
  for i := 0 to cClipPool - 1 do
  begin
    FreeAndNil(GClipPool[i].Mask);
    GClipPool[i].Owner := nil;
  end;
end;

{ the spare entries freed: a switch of the reuse starts from an empty pool }
procedure ClipPoolDropSpares;
var i: Integer;
begin
  for i := 0 to cClipPool - 1 do
    if GClipPool[i].Owner = nil then FreeAndNil(GClipPool[i].Mask);
end;

function TyPainterClipMasksBuiltForTest: Integer;
begin
  Result := GClipMasksBuilt;
end;

const
  CBgraPinnedSeed = LongWord($6A09E667);

function TyPinBgraRandom: LongWord;
begin
  Result := RandSeed;
  RandSeed := CBgraPinnedSeed;
end;

procedure TyUnpinBgraRandom(ASaved: LongWord);
begin
  { Untouched: FPC reseeds only when RandSeed <> its last seed, and nothing
    called Random, so putting the value back leaves the stream where it was. }
  if RandSeed = CBgraPinnedSeed then
  begin
    RandSeed := ASaved;
    Exit;
  end;
  { Drawn from: putting ASaved back would reseed the application's generator
    from it at its next call -- the same numbers after every paint. A value
    derived from it instead; the reseed then differs paint by paint. }
  {$push}{$R-}{$Q-}
  RandSeed := (ASaved xor LongWord($9E3779B9)) * 1103515245 + 12345;
  {$pop}
end;

procedure TyCtxFill(ACtx: TBGRACanvas2D);
begin
  CtxFill(ACtx);
end;

procedure TyCtxStroke(ACtx: TBGRACanvas2D);
begin
  CtxStroke(ACtx);
end;

procedure TyCtxClip(ACtx: TBGRACanvas2D);
begin
  CtxClip(ACtx);
end;

procedure TyPainterClipReuseForTest(AOn: Boolean);
begin
  GClipReuseOff := not AOn;
  ClipPoolDropSpares;
end;

function CanvasStateSlot(ACtx: TBGRACanvas2D): Integer;
var
  p: PPointer;
  i, n: Integer;
begin
  if (GStateSlot = -2) and (ACtx.surface <> nil) then
  begin
    GStateSlot := -1;
    p := PPointer(ACtx);
    n := ACtx.InstanceSize div SizeOf(Pointer);
    try
      for i := 1 to n - 3 do
        if (p[i] = Pointer(ACtx.surface)) and (p[i + 1] <> nil)
          and (PPointer(p[i + 1])^ = Pointer(TList)) and (p[i + 2] <> nil)
          and (PPointer(p[i + 2])^ = Pointer(TBGRACanvasState2D)) then
        begin
          GStateSlot := i + 2;
          Break;
        end;
    except
      GStateSlot := -1;
    end;
  end;
  Result := GStateSlot;
end;

function CanvasStateOf(ACtx: TBGRACanvas2D): TBGRACanvasState2D;
var
  slot: Integer;
  p: Pointer;
begin
  Result := nil;
  slot := CanvasStateSlot(ACtx);
  if slot < 0 then Exit;
  p := PPointer(ACtx)[slot];
  if (p <> nil) and (PPointer(p)^ = Pointer(TBGRACanvasState2D)) then
    Result := TBGRACanvasState2D(p);
end;

{ [R2-P] THE KEPT FILLS (StrokePathKept). One per stroke polygon and clip rect met: the
  polygon, the clip rect, and the brush calls the antialiased fill made -- -1, x, y for a
  MoveTo at (x, y); alpha, count for a PutNextPixels -- and whether the fill drew from the
  pinned Random. Found by a hash of the polygon and the rect, then compared whole. }
type
  TTyKeptFill = class
    Pts: array of TPointF;
    Clip: TRect;
    Ops: array of LongInt;
    NOps: Integer;
    UsedRandom: Boolean;
    Width: Single;          // [R4-P] a distance stroke's width (raster px); 0 for a fill
    Join: TPenJoinStyle;    // [R4-P] and its pen's join, miter limit and cap
    Miter: Single;
    Cap: TPenEndCap;
    Next: TTyKeptFill;      // another polygon with the same hash
    procedure Add(A: LongInt);
  end;

procedure TTyKeptFill.Add(A: LongInt);
begin
  if NOps >= Length(Ops) then SetLength(Ops, Length(Ops) * 2 + 64);
  Ops[NOps] := A;
  Inc(NOps);
end;

const
  KeptFillsMaxCount = 8192;
  KeptFillsMaxBytes = 48 * 1024 * 1024;

var
  GKeptFills: specialize TDictionary<QWord, TTyKeptFill> = nil;
  GKeptFillCount: Integer = 0;
  GKeptFillBytes: Int64 = 0;
  GKeptFillsOff: Boolean = False;
  GKeptFillHashCollide: Boolean = False;
  GKeptFillsMade: Integer = 0;
  GKeptFillsReplayed: Integer = 0;

{ [R2-L] THE KEPT PENS. What the pen makes of a path -- the polygon the fill is given -- is
  a function of the path's points, the width, and the stroker's join, cap, miter limit,
  stroke matrix and dash pattern (TBGRAPenStroker.ComputePolylineAutocycle, no arrow, no
  random draw): kept by those, found by a hash of them and compared whole. A path met
  again (a progressive layer drawn again on a hover) skips the pen as the kept fill skips
  the filler. }
type
  TTyKeptContour = class
    Pts: array of TPointF;
    Width, Miter: Single;
    Join: TPenJoinStyle;
    Cap: TPenEndCap;
    Mat: TAffineMatrix;
    Style: TBGRAPenStyle;
    Contour: ArrayOfTPointF;
    Next: TTyKeptContour;
  end;

const
  KeptContoursMaxCount = 8192;
  KeptContoursMaxBytes = 48 * 1024 * 1024;

var
  GKeptContours: specialize TDictionary<QWord, TTyKeptContour> = nil;
  GKeptContourCount: Integer = 0;
  GKeptContourBytes: Int64 = 0;
  GKeptContoursMade: Integer = 0;

procedure DropKeptContours;
var
  c, n, nx: TTyKeptContour;
begin
  if GKeptContours <> nil then
  begin
    for c in GKeptContours.Values do
    begin
      n := c;
      while n <> nil do
      begin
        nx := n.Next;
        n.Free;
        n := nx;
      end;
    end;
    GKeptContours.Clear;
  end;
  GKeptContourCount := 0;
  GKeptContourBytes := 0;
end;

function TyPainterKeptStrokeContoursForTest: Integer;
begin
  Result := GKeptContoursMade;
end;

function KeptContourOf(AStroker: TBGRACustomPenStroker; const APts: ArrayOfTPointF;
  AWidth: Single): ArrayOfTPointF;
var
  h: QWord;
  q: PQWord;
  i: Integer;
  join: TPenJoinStyle;
  cap: TPenEndCap;
  miter: Single;
  mat: TAffineMatrix;
  style: TBGRAPenStyle;
  c, first: TTyKeptContour;

  procedure Mix(AValue: QWord);
  begin
    {$push}{$R-}{$Q-}
    h := (h xor AValue) * QWord($100000001B3);
    {$pop}
  end;

begin
  join := AStroker.JoinStyle;
  cap := AStroker.LineCap;
  miter := AStroker.MiterLimit;
  mat := AStroker.StrokeMatrix;
  style := AStroker.CustomPenStyle;
  h := QWord($CBF29CE484222325);
  Mix(QWord(PLongWord(@AWidth)^) or (QWord(Ord(join)) shl 32) or (QWord(Ord(cap)) shl 40));
  Mix(QWord(PLongWord(@miter)^) or (QWord(Length(style)) shl 32));
  for i := 0 to High(style) do Mix(QWord(PLongWord(@style[i])^));
  q := PQWord(@mat);
  for i := 0 to (SizeOf(mat) div 8) - 1 do Mix(q[i]);
  if Length(APts) > 0 then
  begin
    q := PQWord(@APts[0]);
    for i := 0 to High(APts) do Mix(q[i]);
  end;
  first := nil;
  if GKeptContours <> nil then GKeptContours.TryGetValue(h, first);
  c := first;
  while c <> nil do
  begin
    if (Length(c.Pts) = Length(APts)) and (c.Width = AWidth) and (c.Miter = miter)
      and (c.Join = join) and (c.Cap = cap) and (Length(c.Style) = Length(style))
      and CompareMem(@c.Mat, @mat, SizeOf(mat))
      and ((Length(style) = 0) or CompareMem(@c.Style[0], @style[0], Length(style) * SizeOf(Single)))
      and ((Length(APts) = 0) or CompareMem(@c.Pts[0], @APts[0], Length(APts) * SizeOf(TPointF))) then
      Exit(c.Contour);
    c := c.Next;
  end;
  Result := AStroker.ComputePolylineAutocycle(APts, AWidth);
  Inc(GKeptContoursMade);
  c := TTyKeptContour.Create;
  c.Pts := APts;
  c.Width := AWidth;
  c.Miter := miter;
  c.Join := join;
  c.Cap := cap;
  c.Mat := mat;
  c.Style := Copy(style);
  c.Contour := Result;
  if GKeptContours = nil then
    GKeptContours := specialize TDictionary<QWord, TTyKeptContour>.Create;
  if (GKeptContourCount >= KeptContoursMaxCount) or (GKeptContourBytes
    + Int64(Length(APts) + Length(Result)) * SizeOf(TPointF) > KeptContoursMaxBytes) then
  begin
    DropKeptContours;
    first := nil;
  end;
  c.Next := first;
  GKeptContours.AddOrSetValue(h, c);
  Inc(GKeptContourCount);
  Inc(GKeptContourBytes, Int64(Length(APts) + Length(Result)) * SizeOf(TPointF));
end;

procedure DropKeptFills;
var
  f, n, nx: TTyKeptFill;
begin
  if GKeptFills <> nil then
  begin
    for f in GKeptFills.Values do
    begin
      n := f;
      while n <> nil do
      begin
        nx := n.Next;
        n.Free;
        n := nx;
      end;
    end;
    GKeptFills.Clear;
  end;
  GKeptFillCount := 0;
  GKeptFillBytes := 0;
end;

procedure DropKeptBands; forward;

procedure TyPainterKeptStrokesForTest(AOn: Boolean);
begin
  DropKeptFills;
  DropKeptContours;
  DropKeptBands;
  GKeptFillsOff := not AOn;
end;

procedure TyPainterKeptFillHashesCollideForTest(AOn: Boolean);
begin
  DropKeptFills;
  GKeptFillHashCollide := AOn;
end;

function TyPainterKeptStrokeFillsForTest: Integer;
begin
  Result := GKeptFillsMade;
end;

function TyPainterKeptStrokeReplaysForTest: Integer;
begin
  Result := GKeptFillsReplayed;
end;

{ FNV-1a over the rect and the points, a point (two Singles) at a time }
function KeptFillHash(const APts: ArrayOfTPointF; const AClip: TRect): QWord;
var
  q: PQWord;
  i: Integer;
begin
  if GKeptFillHashCollide then Exit(0);
  {$push}{$R-}{$Q-}
  Result := QWord($CBF29CE484222325);
  Result := (Result xor QWord(LongWord(AClip.Left)) xor (QWord(LongWord(AClip.Top)) shl 32))
    * QWord($100000001B3);
  Result := (Result xor QWord(LongWord(AClip.Right)) xor (QWord(LongWord(AClip.Bottom)) shl 32))
    * QWord($100000001B3);
  if Length(APts) > 0 then
  begin
    q := PQWord(@APts[0]);
    for i := 0 to High(APts) do
      Result := (Result xor q[i]) * QWord($100000001B3);
  end;
  {$pop}
end;

{ the recording brush: its fixed data holds the fill it records into }
procedure KeptFillRecMove(AFixedData: Pointer; AContextData: PUniBrushContext);
var f: TTyKeptFill;
begin
  f := TTyKeptFill(PPointer(AFixedData)^);
  f.Add(-1);
  f.Add(AContextData^.Ofs.X);
  f.Add(AContextData^.Ofs.Y);
end;

procedure KeptFillRecPut(AFixedData: Pointer; AContextData: PUniBrushContext;
  AAlpha: Word; ACount: Integer);
var f: TTyKeptFill;
begin
  f := TTyKeptFill(PPointer(AFixedData)^);
  f.Add(AAlpha);
  f.Add(ACount);
end;

procedure TTyPainter.StrokePathKept(AColor: TTyColor; AWidthLogical: Double);
var
  ctx: TBGRACanvas2D;
  st: TBGRACanvasState2D;
  w: Double;
  devDash: array of Single;
  i, k: Integer;
  pts, contour: ArrayOfTPointF;
  h: QWord;
  f, first: TTyKeptFill;
  clip: TRect;
  saved, before: LongWord;
  rb, b: TUniversalBrush;
  c: TBGRAPixel;
  uctx: TUniBrushContext;
  mode: TDrawMode;
  maskScan: TBGRACustomScanner;
begin
  if FBmp = nil then Exit;
  w := ScaleF(AWidthLogical);
  if w <= 0 then Exit;
  { A DASHED PEN TOO THIN TO LEAVE A MARK is not laid [R2-V]: a dash written
    as a word scales with the width, and a width tweening to 0 (a state's
    borderWidth 0) passes 1e-7 px on its way -- hundreds of millions of
    dashes round one bar, a stroke that never finished. Under 1/512 px no
    pixel takes any of it in 8 bits. }
  if (Length(FVecDash) > 0) and (w < cThinDashPx) then Exit;
  ctx := FBmp.Canvas2D;
  { the state StrokePath sets, set the same way }
  ctx.lineWidth := w;
  SetLength(devDash, Length(FVecDash));
  for i := 0 to High(FVecDash) do
    devDash[i] := ScaleF(FVecDash[i]) / w;
  ctx.strokeStyle(TyColorToBGRA(AColor));
  { [R2-F] a phase: the dashes laid here, stroked solid, not kept }
  if StrokeDashPhased(ctx, devDash, ScaleF(FVecDashOffset) / w) then Exit;
  ctx.lineStyle(devDash);
  { [R4-P] a pen under one raster pixel, when asked for: nothing to keep }
  if FFastStrokes and StrokeHairline(ctx) then Exit;
  st := nil;
  if not GKeptFillsOff and (GetCurrentThreadId = MainThreadID) then
    st := CanvasStateOf(ctx);
  if (st = nil) or (st.strokeTextureProvider <> nil)
    or ctx.hasShadow or not ctx.antialiasing or (st.lineWidth = 0)
    or (ctx.surface <> FBmp) or (st.penStroker.Arrow <> nil) then
  begin
    CtxStroke(ctx);
    Exit;
  end;
  { the brush StrokePoly's fill makes (AnyBrush): the stroke colour at the global alpha --
    [R2-L] or, under a clip mask, its scanner of that colour through the mask
    (FillPolyAntialiasWithTexture: the same fill, nonzero, pixel-centred, a scanner brush) }
  c := st.strokeColor;
  c.alpha := ApplyOpacity(c.alpha, st.globalAlpha);
  if ctx.linearBlend then mode := dmLinearBlend else mode := dmDrawWithTransparency;
  maskScan := nil;
  if st.clipMaskReadOnly <> nil then
  begin
    maskScan := TBGRASolidColorMaskScanner.Create(st.clipMaskReadOnly, Point(0, 0), c);
    FBmp.ScannerBrush(b, maskScan, mode);
  end
  else
    FBmp.SolidBrush(b, c, mode);
  try
  { [R2-L] A SOLID INK THAT DRAWS NOTHING draws nothing: StrokePoly's fill
    leaves at once (FillPolyAntialias: brush.DoesNothing), before any random
    draw -- the pen's polygon it makes first goes nowhere. Not made. }
  if b.DoesNothing then Exit;
  pts := ctx.currentPath;
  if Length(pts) = 0 then Exit;
  saved := TyPinBgraRandom;
  try
    { the pen's polygon, kept by everything it is made from [R2-L] }
    contour := KeptContourOf(st.penStroker, pts, st.lineWidth);
    if Length(contour) < 3 then Exit;   // FillPolyAntialias draws nothing
    clip := FBmp.ClipRect;
    h := KeptFillHash(contour, clip);
    first := nil;
    if GKeptFills <> nil then GKeptFills.TryGetValue(h, first);
    f := first;
    while f <> nil do
    begin
      if (Length(f.Pts) = Length(contour)) and EqualRect(f.Clip, clip)
        and CompareMem(@f.Pts[0], @contour[0], Length(contour) * SizeOf(TPointF)) then
        Break;
      f := f.Next;
    end;
    if f = nil then
    begin
      { RECORDED: the fill StrokePoly would run, through a brush that writes down its calls }
      f := TTyKeptFill.Create;
      f.Pts := contour;
      f.Clip := clip;
      rb := Default(TUniversalBrush);
      rb.Colorspace := FBmp.Colorspace;
      rb.InternalInitContext := @KeptFillRecMove;
      rb.InternalPutNextPixels := @KeptFillRecPut;
      PPointer(@rb.FixedData[0])^ := Pointer(f);
      before := RandSeed;
      BGRAPolygon.FillPolyAntialias(FBmp, contour, rb, True, True);
      f.UsedRandom := RandSeed <> before;
      SetLength(f.Ops, f.NOps);
      Inc(GKeptFillsMade);
      if GKeptFills = nil then
        GKeptFills := specialize TDictionary<QWord, TTyKeptFill>.Create;
      if (GKeptFillCount >= KeptFillsMaxCount)
        or (GKeptFillBytes + Int64(Length(f.Pts)) * SizeOf(TPointF) + f.NOps * 4 > KeptFillsMaxBytes) then
      begin
        DropKeptFills;
        first := nil;
      end;
      f.Next := first;
      GKeptFills.AddOrSetValue(h, f);
      Inc(GKeptFillCount);
      Inc(GKeptFillBytes, Int64(Length(f.Pts)) * SizeOf(TPointF) + f.NOps * 4);
    end
    else
    begin
      Inc(GKeptFillsReplayed);
      { the fill drew from the pinned generator: say so, so that unpinning reseeds the
        application's as after a fill }
      if f.UsedRandom and (RandSeed = CBgraPinnedSeed) then
        RandSeed := CBgraPinnedSeed xor 1;
    end;
  finally
    TyUnpinBgraRandom(saved);
  end;
  { REPLAYED through the real brush: FillShapeAntialias's own calls, its own LoadFromBitmap
    and InvalidateBitmap around them }
  if f.NOps = 0 then Exit;
  FBmp.LoadFromBitmapIfNeeded;
  uctx := Default(TUniBrushContext);
  k := 0;
  while k < f.NOps do
    if f.Ops[k] = -1 then
    begin
      b.MoveTo(@uctx, FBmp.GetPixelAddress(f.Ops[k + 1], f.Ops[k + 2]), f.Ops[k + 1],
        f.Ops[k + 2]);
      Inc(k, 3);
    end
    else
    begin
      b.PutNextPixels(@uctx, Word(f.Ops[k]), f.Ops[k + 1]);
      Inc(k, 2);
    end;
  FBmp.InvalidateBitmap;
  finally
    maskScan.Free;
  end;
end;

{ ===== [R4-P] THE FAST STROKES ===========================================================

  Both lay coverage through the brush the canvas' stroke would fill with (StrokePoly ->
  AnyBrush): the stroke colour at the global alpha, the blending the canvas says, through
  the clip mask's scanner where there is one. }
function FastStrokeBrush(ABmp: TBGRABitmap; ACtx: TBGRACanvas2D; ASt: TBGRACanvasState2D;
  out ABrush: TUniversalBrush; out AMaskScan: TBGRACustomScanner): Boolean;
var
  c: TBGRAPixel;
  mode: TDrawMode;
begin
  c := ASt.strokeColor;
  c.alpha := ApplyOpacity(c.alpha, ASt.globalAlpha);
  if ACtx.linearBlend then mode := dmLinearBlend else mode := dmDrawWithTransparency;
  AMaskScan := nil;
  if ASt.clipMaskReadOnly <> nil then
  begin
    AMaskScan := TBGRASolidColorMaskScanner.Create(ASt.clipMaskReadOnly, Point(0, 0), c);
    ABmp.ScannerBrush(ABrush, AMaskScan, mode);
  end
  else
    ABmp.SolidBrush(ABrush, c, mode);
  Result := not ABrush.DoesNothing;
end;

{ the canvas' pen as one the fast strokes draw, and its width in raster px: a solid pen,
  no texture, no shadow, no arrow, antialiased, on this bitmap, its stroke matrix a uniform
  scale (and a turn) }
function FastStrokePen(ABmp: TBGRABitmap; ACtx: TBGRACanvas2D; out ASt: TBGRACanvasState2D;
  out AWidth: Double): Boolean;
var
  m: TAffineMatrix;
  a, b, c, d, zx, zy: Double;
begin
  Result := False;
  ASt := nil;
  AWidth := 0;
  if GetCurrentThreadId <> MainThreadID then Exit;
  ASt := CanvasStateOf(ACtx);
  if (ASt = nil) or (ASt.strokeTextureProvider <> nil) or ACtx.hasShadow
    or not ACtx.antialiasing or (ACtx.surface <> ABmp) or (ASt.penStroker.Arrow <> nil)
    or (Length(ASt.penStroker.CustomPenStyle) > 0) then Exit;
  m := ASt.penStroker.StrokeMatrix;
  a := m[1, 1];
  b := m[2, 1];
  c := m[1, 2];
  d := m[2, 2];
  zx := Sqrt(a * a + b * b);
  zy := Sqrt(c * c + d * d);
  if not (zx > 0) or (Abs(zx - zy) > 1e-6 * zx) or (Abs(a * c + b * d) > 1e-6 * zx * zx) then
    Exit;
  AWidth := ASt.lineWidth * zx;
  Result := (AWidth > 0) and not IsInfinite(AWidth);
end;

{ the recorded brush calls (TTyKeptFill.Ops) through ABrush on ABmp }
procedure ReplayKeptOps(ABmp: TBGRABitmap; AFill: TTyKeptFill; var ABrush: TUniversalBrush);
var
  k: Integer;
  uctx: TUniBrushContext;
begin
  if AFill.NOps = 0 then Exit;
  ABmp.LoadFromBitmapIfNeeded;
  uctx := Default(TUniBrushContext);
  k := 0;
  while k < AFill.NOps do
    if AFill.Ops[k] = -1 then
    begin
      ABrush.MoveTo(@uctx, ABmp.GetPixelAddress(AFill.Ops[k + 1], AFill.Ops[k + 2]),
        AFill.Ops[k + 1], AFill.Ops[k + 2]);
      Inc(k, 3);
    end
    else
    begin
      ABrush.PutNextPixels(@uctx, Word(AFill.Ops[k]), AFill.Ops[k + 1]);
      Inc(k, 2);
    end;
  ABmp.InvalidateBitmap;
end;

{ THE HAIRLINE RASTERISER's scratch: a coverage per raster pixel (0 between strokes) and
  the pixels a stroke touched, kept on the main thread and grown to the largest bitmap met }
var
  GHairCov: array of Word = nil;
  GHairTouched: array of Integer = nil;
  GHairStrokes: Integer = 0;

const
  { a flattened path's points within this many raster px of a chord walk as the chord,
    up to this many at a time }
  HairChordTol = 0.05;
  HairChordRun = 8;

function TyPainterHairlinesForTest: Integer;
begin
  Result := GHairStrokes;
end;

{ ONE SEGMENT of a hairline: along its major axis, pixel by pixel, the part of the pixel it
  spans (f) and the band its thickness covers across the minor axis at the middle of that
  part, each pixel of the band taking f times its share of the band, summed into the
  coverage (65535 full) and capped there; a pixel's first touch is written down.

  REGISTER VARIABLES here, as in the graph's force step: at the default level every Double
  local of the column loop lives on the stack. A 64-bit register holds a Double exactly as
  memory does; x86-64 only, where Doubles are SSE values. }
type
  THairCtx = record
    W: Double;               // the width, raster px
    Bw: Integer;             // the bitmap's width: a pixel's index is y * Bw + x
    Clip: TRect;
    NTouched: Integer;
  end;

{$push}
{$IFDEF CPUX86_64}{$OPTIMIZATION REGVAR}{$ENDIF}
procedure HairSegment(var C: THairCtx; AX0, AY0, AX1, AY1: Double);
var
  dx, dy, len, u0, u1, v0, v1, t, slope, lo, hi, cc, ht, vlo, vhi, f, a, z: Double;
  i0, i1, ii, j, j0, j1, uMin, uMax, vMin, vMax, kk, v, stepU, stepV: Integer;
  cov: PWord;
begin
  if not ((Abs(AX0) < 1e9) and (Abs(AY0) < 1e9) and (Abs(AX1) < 1e9) and (Abs(AY1) < 1e9)) then
    Exit;
  dx := AX1 - AX0;
  dy := AY1 - AY0;
  len := Sqrt(dx * dx + dy * dy);
  if len = 0 then Exit;
  if Abs(dx) >= Abs(dy) then
  begin
    u0 := AX0; u1 := AX1; v0 := AY0; v1 := AY1;
    uMin := C.Clip.Left; uMax := C.Clip.Right - 1; vMin := C.Clip.Top; vMax := C.Clip.Bottom - 1;
    stepU := 1;
    stepV := C.Bw;
  end
  else
  begin
    u0 := AY0; u1 := AY1; v0 := AX0; v1 := AX1;
    uMin := C.Clip.Top; uMax := C.Clip.Bottom - 1; vMin := C.Clip.Left; vMax := C.Clip.Right - 1;
    stepU := C.Bw;
    stepV := 1;
  end;
  if u1 < u0 then
  begin
    t := u0; u0 := u1; u1 := t;
    t := v0; v0 := v1; v1 := t;
  end;
  slope := (v1 - v0) / (u1 - u0);
  { the thickness across the minor axis: the width over the cosine }
  ht := C.W * len / (u1 - u0) / 2;
  { only the pixels inside the clip along the major axis }
  if u0 < uMin - 0.5 then
  begin
    v0 := v0 + (uMin - 0.5 - u0) * slope;
    u0 := uMin - 0.5;
  end;
  if u1 > uMax + 0.5 then u1 := uMax + 0.5;
  if u1 <= u0 then Exit;
  cov := @GHairCov[0];
  { floors of numbers above -4 }
  i0 := Trunc(u0 + 4.5) - 4;
  i1 := Trunc(u1 + 4.5) - 4;
  if i1 > uMax then i1 := uMax;
  for ii := i0 to i1 do
  begin
    lo := ii - 0.5;
    if u0 > lo then lo := u0;
    hi := ii + 0.5;
    if u1 < hi then hi := u1;
    f := hi - lo;
    if f <= 0 then Continue;
    cc := v0 + ((lo + hi) * 0.5 - u0) * slope;
    vlo := cc - ht;
    vhi := cc + ht;
    if (vhi <= vMin - 0.5) or (vlo >= vMax + 0.5) then Continue;
    { vlo and vhi lie within 2 of the clip here: a thickness under 1.5 }
    j0 := Trunc(vlo + 4.5) - 4;
    j1 := Trunc(vhi + 4.5) - 4;
    if j0 < vMin then j0 := vMin;
    if j1 > vMax then j1 := vMax;
    f := f * 65535;
    kk := ii * stepU + j0 * stepV;
    for j := j0 to j1 do
    begin
      a := j - 0.5;
      if vlo > a then a := vlo;
      z := j + 0.5;
      if vhi < z then z := vhi;
      if z > a then
      begin
        v := Trunc(f * (z - a) + 0.5);
        if v > 0 then
        begin
          if cov[kk] = 0 then
          begin
            if C.NTouched >= Length(GHairTouched) then
              SetLength(GHairTouched, 2 * C.NTouched + 4096);
            GHairTouched[C.NTouched] := kk;
            Inc(C.NTouched);
          end
          else
            v := v + cov[kk];
          if v > 65535 then v := 65535;
          cov[kk] := v;
        end;
      end;
      Inc(kk, stepV);
    end;
  end;
end;
{$pop}

function TTyPainter.StrokeHairline(ACtx: TBGRACanvas2D): Boolean;
var
  st: TBGRACanvasState2D;
  w, ext: Double;
  b: TUniversalBrush;
  maskScan: TBGRACustomScanner;
  pts: ArrayOfTPointF;
  clip: TRect;
  bw, nTouched, i, s, e, k, n, m, a, x, y, idx: Integer;
  hc: THairCtx;
  cap: TPenEndCap;
  closed: Boolean;
  uctx: TUniBrushContext;
  q, qs: array of TPointF;

  { whether every point of q strictly between AA and AK lies within HairChordTol of the
    chord from q[AA] to q[AK], and along it }
  function Covers(AA, AK: Integer): Boolean;
  var
    dx, dy, l2, lim, ex, ey, cr, dt: Double;
    ii: Integer;
  begin
    Result := False;
    dx := q[AK].x - q[AA].x;
    dy := q[AK].y - q[AA].y;
    l2 := dx * dx + dy * dy;
    if l2 = 0 then Exit;
    lim := HairChordTol * HairChordTol * l2;
    for ii := AA + 1 to AK - 1 do
    begin
      ex := q[ii].x - q[AA].x;
      ey := q[ii].y - q[AA].y;
      cr := ex * dy - ey * dx;
      if cr * cr > lim then Exit;
      dt := ex * dx + ey * dy;
      if (dt < 0) or (dt > l2) then Exit;
    end;
    Result := True;
  end;

  { AV of a pixel's area to raster pixel (AX, AY), inside the clip }
  procedure Cell(AX, AY: Integer; AV: Double);
  var
    kk, v: Integer;
  begin
    if (AX < clip.Left) or (AX >= clip.Right) or (AY < clip.Top) or (AY >= clip.Bottom) then
      Exit;
    v := Round(AV * 65535);
    if v <= 0 then Exit;
    kk := AY * bw + AX;
    if GHairCov[kk] = 0 then
    begin
      if nTouched >= Length(GHairTouched) then
        SetLength(GHairTouched, 2 * nTouched + 4096);
      GHairTouched[nTouched] := kk;
      Inc(nTouched);
    end
    else
      v := v + GHairCov[kk];
    if v > 65535 then v := 65535;
    GHairCov[kk] := v;
  end;

  { an open path's end pushed out by ext along its first or last segment }
  function Pushed(const AEnd, AFrom: TPointF): TPointF;
  var
    ddx, ddy, l: Double;
  begin
    Result := AEnd;
    ddx := AEnd.x - AFrom.x;
    ddy := AEnd.y - AFrom.y;
    l := Sqrt(ddx * ddx + ddy * ddy);
    if l > 0 then
    begin
      Result.x := AEnd.x + ddx / l * ext;
      Result.y := AEnd.y + ddy / l * ext;
    end;
  end;

begin
  Result := False;
  if not FastStrokePen(FBmp, ACtx, st, w) or not (w < 1) then Exit;
  Result := True;
  pts := ACtx.currentPath;
  if Length(pts) = 0 then Exit;
  if not FastStrokeBrush(FBmp, ACtx, st, b, maskScan) then
  begin
    maskScan.Free;
    Exit;
  end;
  Inc(GHairStrokes);
  bw := FBmp.Width;
  clip := FBmp.ClipRect;
  if Length(GHairCov) < bw * FBmp.Height then SetLength(GHairCov, bw * FBmp.Height);
  nTouched := 0;
  hc.W := w;
  hc.Bw := bw;
  hc.Clip := clip;
  hc.NTouched := 0;
  cap := st.penStroker.LineCap;
  case cap of
    pecSquare: ext := w / 2;
    pecRound: ext := w * Pi / 8;   // a half disc's area as a length of the line
  else
    ext := 0;
  end;
  try
    try
      s := 0;
      while s <= High(pts) do
      begin
        { a subpath: s .. e - 1, its repeated points dropped }
        e := s;
        while (e <= High(pts)) and not isEmptyPointF(pts[e]) do Inc(e);
        if Length(q) < e - s then
        begin
          SetLength(q, e - s);
          SetLength(qs, e - s);
        end;
        n := 0;
        for i := s to e - 1 do
          if (n = 0) or (pts[i].x <> q[n - 1].x) or (pts[i].y <> q[n - 1].y) then
          begin
            q[n] := pts[i];
            Inc(n);
          end;
        { THE CHORDS: BGRA flattens a curve to a twentieth of a pixel, far finer than a
          hairline needs, and a column met by three short segments is walked three times. A
          run of up to HairChordRun points that all lie within HairChordTol of the chord from
          its first to its last is walked as the chord. }
        if n > 2 then
        begin
          qs[0] := q[0];
          m := 1;
          a := 0;
          for i := 2 to n - 1 do
            if (i - a > HairChordRun) or not Covers(a, i) then
            begin
              qs[m] := q[i - 1];
              Inc(m);
              a := i - 1;
            end;
          qs[m] := q[n - 1];
          Inc(m);
          for i := 0 to m - 1 do q[i] := qs[i];
          n := m;
        end;
        if n = 1 then
        begin
          { a point: a square or round cap's dot, its area on the nearest pixel }
          if cap = pecSquare then Cell(Floor(q[0].x + 0.5), Floor(q[0].y + 0.5), w * w)
          else if cap = pecRound then Cell(Floor(q[0].x + 0.5), Floor(q[0].y + 0.5), Pi * w * w / 4);
        end
        else if n > 1 then
        begin
          closed := (n > 2) and (q[0] = q[n - 1]);
          if not closed and (ext > 0) then
          begin
            q[0] := Pushed(q[0], q[1]);
            q[n - 1] := Pushed(q[n - 1], q[n - 2]);
          end;
          hc.NTouched := nTouched;
          for i := 0 to n - 2 do
            HairSegment(hc, q[i].x, q[i].y, q[i + 1].x, q[i + 1].y);
          nTouched := hc.NTouched;
        end;
        s := e + 1;
      end;
      { laid once, through the stroke's brush }
      if nTouched > 0 then
      begin
        FBmp.LoadFromBitmapIfNeeded;
        uctx := Default(TUniBrushContext);
        for k := 0 to nTouched - 1 do
        begin
          idx := GHairTouched[k];
          y := idx div bw;
          x := idx - y * bw;
          b.MoveTo(@uctx, FBmp.GetPixelAddress(x, y), x, y);
          b.PutNextPixels(@uctx, GHairCov[idx], 1);
        end;
        FBmp.InvalidateBitmap;
      end;
    finally
      for k := 0 to nTouched - 1 do GHairCov[GHairTouched[k]] := 0;
    end;
  finally
    maskScan.Free;
  end;
end;

{ THE DISTANCE STROKES, KEPT: as the kept fills, by the path, the width and the clip rect }
var
  GKeptBands: specialize TDictionary<QWord, TTyKeptFill> = nil;
  GKeptBandCount: Integer = 0;
  GKeptBandBytes: Int64 = 0;
  GBandsMade: Integer = 0;
  GBandsReplayed: Integer = 0;
  GBandDist: array of Single = nil;

function TyPainterDistanceStrokesForTest: Integer;
begin
  Result := GBandsMade;
end;

function TyPainterDistanceReplaysForTest: Integer;
begin
  Result := GBandsReplayed;
end;

procedure DropKeptBands;
var
  f, n, nx: TTyKeptFill;
begin
  if GKeptBands <> nil then
  begin
    for f in GKeptBands.Values do
    begin
      n := f;
      while n <> nil do
      begin
        nx := n.Next;
        n.Free;
        n := nx;
      end;
    end;
    GKeptBands.Clear;
  end;
  GKeptBandCount := 0;
  GKeptBandBytes := 0;
end;

{ the band's coverage as brush calls into AFill: APts the path (raster px, pixel centred),
  AW the width in raster px, AClip the bitmap's clip rect, the pen's join, miter limit and
  cap. False: too large a box to walk.

  THE PEN'S CORNERS. Each segment is a strip AW wide. At a joint the miter is the polygon
  vertex, the two outer corners, the tip, which the line from the vertex to the tip splits
  into two triangles, one carried on past the end of each strip on its outer side: past the
  vertex by s (up to e = r tan(turn / 2), r half the width) the strip keeps the points of
  its outer half that lie beyond r s / e from its centre line. A miter whose tip would lie
  further from the vertex than the limit times r is cut there across the bisector, as BGRA
  cuts it (TBGRAPenStroker: the 'little border'); a bevel is BGRA's cut at r. A round join,
  and a turn straight back, takes the disc round the vertex. An open end takes the cap: none
  past a butt, the whole strip carried on by r for a square one, the disc for a round one.
  Every point inside the box then takes its distance to the nearest of them. }
function MakeDistanceBand(AFill: TTyKeptFill; const APts: ArrayOfTPointF; AW: Double;
  const AClip: TRect; AJoin: TPenJoinStyle; AMiter: Single; ACap: TPenEndCap): Boolean;
var
  r, reach, reach2, xmin, xmax, ymin, ymax, d2, d, cov, ext: Double;
  bx0, bx1, by0, by1, bwid, bht, i, j, k, n, s, x, y, a, runA, runN: Integer;
  moved, closed: Boolean;
  row: PSingle;
  q: array of TPointF;
  { per segment and end (0 its start, 1 its end): e how far the strip goes on past the
    vertex (< 0: the disc there instead), t the miter triangle's run (r tan(turn / 2)), o
    the outer side (the sign of ex dy - ey dx; 0: the whole strip), and a cut across the
    bisector (cx, cy) at cm from the vertex (cm < 0: none) }
  ux, uy, len, e0, e1, t0, t1, cx0, cy0, cm0, cx1, cy1, cm1: array of Double;
  o0, o1: array of Integer;
  jz, jt, jbx, jby, jm: Double;
  segs: Integer;

  { a joint between the unit directions (AU) in and (AV) out, on the side ASide:
    jz how far each strip goes on past the vertex (-1: the disc), jt the triangle's run,
    (jbx, jby) the outer bisector and jm the cut's distance (-1: none) }
  procedure Joint(AUX, AUY, AVX, AVY: Double; ASide: Integer);
  var cs, sn, half, lim, nax, nay, nbx, nby, bl, sc: Double;
  begin
    jz := -1;
    jt := 0;
    jm := -1;
    jbx := 0;
    jby := 0;
    cs := AUX * AVX + AUY * AVY;
    if (AJoin = pjsRound) or (cs <= -1 + 1e-9) then Exit;
    sn := Abs(AUX * AVY - AUY * AVX);
    jt := r * sn / (1 + cs);
    jz := jt;
    { the tip lies r / cos(turn / 2) from the vertex; BGRA cuts it at r times the limit
      (at r for a bevel) }
    half := Sqrt(Max(0.0, (1 + cs) / 2));
    if (AJoin = pjsMiter) and (AMiter >= 1.001) then lim := r * AMiter else lim := r * 1.001;
    if r <= lim * half then Exit;
    nax := ASide * AUY;
    nay := -ASide * AUX;
    nbx := ASide * AVY;
    nby := -ASide * AVX;
    bl := Sqrt(Sqr(nax + nbx) + Sqr(nay + nby));
    if bl <= 0 then
    begin
      jz := -1;
      Exit;
    end;
    jbx := (nax + nbx) / bl;
    jby := (nay + nby) / bl;
    jm := lim;
    { where the cut meets the strip's outer edge }
    sc := AUX * jbx + AUY * jby;
    if sc > 0 then
      jz := Min(jt, (lim - r * (nax * jbx + nay * jby)) / sc);
    if jz < 0 then jz := 0;
  end;

  procedure Seg(AK: Integer);
  var
    xx, yy, sx0, sx1, sy0, sy1: Integer;
    pd: PSingle;
    x0, y0, x1, y1, dx, dy, ex, ey, al, pp, lo, hi, dd: Double;
  begin
    x0 := q[AK].x;
    y0 := q[AK].y;
    x1 := q[AK + 1].x;
    y1 := q[AK + 1].y;
    dx := ux[AK];
    dy := uy[AK];
    lo := -Max(0.0, e0[AK]);
    hi := len[AK] + Max(0.0, e1[AK]);
    { the box of the carried-on strip }
    sx0 := Ceil(Min(x0 + dx * lo, x0 + dx * hi) - reach);
    sx1 := Floor(Max(x0 + dx * lo, x0 + dx * hi) + reach);
    sy0 := Ceil(Min(y0 + dy * lo, y0 + dy * hi) - reach);
    sy1 := Floor(Max(y0 + dy * lo, y0 + dy * hi) + reach);
    if sx0 < bx0 then sx0 := bx0;
    if sx1 > bx1 then sx1 := bx1;
    if sy0 < by0 then sy0 := by0;
    if sy1 > by1 then sy1 := by1;
    for yy := sy0 to sy1 do
    begin
      pd := @GBandDist[(yy - by0) * bwid + (sx0 - bx0)];
      ey := yy - y0;
      for xx := sx0 to sx1 do
      begin
        ex := xx - x0;
        al := ex * dx + ey * dy;
        pp := ex * dy - ey * dx;
        if al < lo then
        begin
          if e0[AK] >= 0 then
          begin
            Inc(pd);
            Continue;
          end;
          dd := ex * ex + ey * ey;
        end
        else if al > hi then
        begin
          if e1[AK] >= 0 then
          begin
            Inc(pd);
            Continue;
          end;
          dd := (xx - x1) * (xx - x1) + (yy - y1) * (yy - y1);
        end
        else if (al < 0) and (o0[AK] <> 0) and ((o0[AK] * pp * t0[AK] < r * -al)
          or ((cm0[AK] >= 0) and (ex * cx0[AK] + ey * cy0[AK] > cm0[AK]))) then
        begin
          { before the start, inside the miter (its triangle, short of its cut) only }
          Inc(pd);
          Continue;
        end
        else if (al > len[AK]) and (o1[AK] <> 0) and ((o1[AK] * pp * t1[AK] < r * (al - len[AK]))
          or ((cm1[AK] >= 0) and ((xx - x1) * cx1[AK] + (yy - y1) * cy1[AK] > cm1[AK]))) then
        begin
          Inc(pd);
          Continue;
        end
        else
          dd := pp * pp;
        if dd < pd^ then pd^ := dd;
        Inc(pd);
      end;
    end;
  end;

  { a lone point: a round cap's disc, a square cap's square }
  procedure Dot(const AP: TPointF);
  var
    xx, yy: Integer;
    pd: PSingle;
    dd, ax, ay: Double;
  begin
    if ACap = pecFlat then Exit;
    for yy := Max(by0, Ceil(AP.y - reach)) to Min(by1, Floor(AP.y + reach)) do
    begin
      pd := @GBandDist[(yy - by0) * bwid + (Max(bx0, Ceil(AP.x - reach)) - bx0)];
      for xx := Max(bx0, Ceil(AP.x - reach)) to Min(bx1, Floor(AP.x + reach)) do
      begin
        ax := Abs(xx - AP.x);
        ay := Abs(yy - AP.y);
        if ACap = pecSquare then dd := Sqr(Max(ax, ay)) else dd := ax * ax + ay * ay;
        if dd < pd^ then pd^ := dd;
        Inc(pd);
      end;
    end;
  end;

begin
  Result := True;
  r := AW / 2;
  reach := r + 0.5;
  reach2 := reach * reach;
  for i := 0 to High(APts) do
    if not isEmptyPointF(APts[i])
      and not ((Abs(APts[i].x) < 1e7) and (Abs(APts[i].y) < 1e7)) then Exit(False);
  { two passes over the subpaths: the box (the strips carried on included), then the walk }
  xmin := 0; xmax := 0; ymin := 0; ymax := 0;
  bx0 := 0; bx1 := -1; by0 := 0; by1 := -1;
  bwid := 0;
  for k := 0 to 1 do
  begin
    if k = 1 then
    begin
      if bx1 < bx0 then Exit;
      bx0 := Max(AClip.Left, Ceil(xmin - reach));
      bx1 := Min(AClip.Right - 1, Floor(xmax + reach));
      by0 := Max(AClip.Top, Ceil(ymin - reach));
      by1 := Min(AClip.Bottom - 1, Floor(ymax + reach));
      if (bx0 > bx1) or (by0 > by1) then Exit;
      bwid := bx1 - bx0 + 1;
      bht := by1 - by0 + 1;
      if Int64(bwid) * bht > 16 * 1024 * 1024 then Exit(False);
      if Length(GBandDist) < bwid * bht then SetLength(GBandDist, bwid * bht);
      for i := 0 to bwid * bht - 1 do GBandDist[i] := reach2;
    end;
    s := 0;
    while s <= High(APts) do
    begin
      if isEmptyPointF(APts[s]) then
      begin
        Inc(s);
        Continue;
      end;
      { the subpath, its repeated points dropped; closed when it comes back to its start }
      j := s;
      while (j < High(APts)) and not isEmptyPointF(APts[j + 1]) do Inc(j);
      SetLength(q, j - s + 1);
      n := 0;
      for i := s to j do
        if (n = 0) or (APts[i].x <> q[n - 1].x) or (APts[i].y <> q[n - 1].y) then
        begin
          q[n] := APts[i];
          Inc(n);
        end;
      s := j + 1;
      closed := (n > 2) and (q[0].x = q[n - 1].x) and (q[0].y = q[n - 1].y);
      if closed then Dec(n);   // q[n] (= q[0]) closes it
      if n = 1 then
      begin
        if k = 0 then
        begin
          if bx1 < bx0 then
          begin
            xmin := q[0].x; xmax := xmin; ymin := q[0].y; ymax := ymin;
            bx0 := 0; bx1 := 0;
          end;
          xmin := Min(xmin, q[0].x); xmax := Max(xmax, q[0].x);
          ymin := Min(ymin, q[0].y); ymax := Max(ymax, q[0].y);
        end
        else
          Dot(q[0]);
        Continue;
      end;
      if closed then
      begin
        SetLength(q, n + 1);
        q[n] := q[0];
        segs := n;
      end
      else
        segs := n - 1;
      SetLength(ux, segs);
      SetLength(uy, segs);
      SetLength(len, segs);
      SetLength(e0, segs);
      SetLength(e1, segs);
      SetLength(o0, segs);
      SetLength(o1, segs);
      SetLength(t0, segs);
      SetLength(t1, segs);
      SetLength(cx0, segs);
      SetLength(cy0, segs);
      SetLength(cm0, segs);
      SetLength(cx1, segs);
      SetLength(cy1, segs);
      SetLength(cm1, segs);
      for i := 0 to segs - 1 do
      begin
        len[i] := Sqrt(Sqr(q[i + 1].x - q[i].x) + Sqr(q[i + 1].y - q[i].y));
        ux[i] := (q[i + 1].x - q[i].x) / len[i];
        uy[i] := (q[i + 1].y - q[i].y) / len[i];
      end;
      for i := 0 to segs - 1 do
      begin
        { the joint at the segment's end, and so the next one's start }
        if (i < segs - 1) or closed then
        begin
          j := (i + 1) mod segs;
          if ux[i] * uy[j] - uy[i] * ux[j] >= 0 then a := 1 else a := -1;
          Joint(ux[i], uy[i], ux[j], uy[j], a);
          e1[i] := jz;
          e0[j] := jz;
          t1[i] := jt;
          t0[j] := jt;
          o1[i] := a;
          o0[j] := a;
          cx1[i] := jbx;
          cy1[i] := jby;
          cm1[i] := jm;
          cx0[j] := jbx;
          cy0[j] := jby;
          cm0[j] := jm;
        end;
      end;
      if not closed then
      begin
        case ACap of
          pecFlat: ext := 0;
          pecSquare: ext := r;
        else
          ext := -1;
        end;
        e0[0] := ext;
        e1[segs - 1] := ext;
        o0[0] := 0;
        o1[segs - 1] := 0;
        cm0[0] := -1;
        cm1[segs - 1] := -1;
      end;
      for i := 0 to segs - 1 do
        if k = 0 then
        begin
          if bx1 < bx0 then
          begin
            xmin := q[i].x; xmax := xmin; ymin := q[i].y; ymax := ymin;
            bx0 := 0; bx1 := 0;
          end;
          for a := 0 to 1 do
          begin
            if a = 0 then d := -Max(0.0, e0[i]) else d := len[i] + Max(0.0, e1[i]);
            xmin := Min(xmin, q[i].x + ux[i] * d);
            xmax := Max(xmax, q[i].x + ux[i] * d);
            ymin := Min(ymin, q[i].y + uy[i] * d);
            ymax := Max(ymax, q[i].y + uy[i] * d);
          end;
        end
        else
          Seg(i);
    end;
  end;
  { the coverage, row by row: a move at a run's first pixel, a put per run of one alpha }
  for y := by0 to by1 do
  begin
    row := @GBandDist[(y - by0) * bwid];
    moved := False;
    runA := 0;
    runN := 0;
    for x := bx0 to bx1 do
    begin
      d2 := row^;
      Inc(row);
      a := 0;
      if d2 < reach2 then
      begin
        d := Sqrt(d2);
        cov := Min(d + r, 0.5) - Max(d - r, -0.5);
        if cov >= 1 then a := 65535
        else if cov > 0 then a := Round(cov * 65535);
      end;
      if a = 0 then
      begin
        if runN > 0 then
        begin
          AFill.Add(runA);
          AFill.Add(runN);
          runN := 0;
        end;
        moved := False;
        Continue;
      end;
      if not moved then
      begin
        AFill.Add(-1);
        AFill.Add(x);
        AFill.Add(y);
        moved := True;
        runA := a;
        runN := 1;
      end
      else if a = runA then
        Inc(runN)
      else
      begin
        AFill.Add(runA);
        AFill.Add(runN);
        runA := a;
        runN := 1;
      end;
    end;
    if runN > 0 then
    begin
      AFill.Add(runA);
      AFill.Add(runN);
    end;
  end;
end;

procedure TTyPainter.StrokePathByDistance(AColor: TTyColor; AWidthLogical: Double);
var
  ctx: TBGRACanvas2D;
  st: TBGRACanvasState2D;
  w, wr: Double;
  pts: ArrayOfTPointF;
  b: TUniversalBrush;
  maskScan: TBGRACustomScanner;
  clip: TRect;
  h: QWord;
  f, first: TTyKeptFill;
  keep, made: Boolean;
  ws: Single;
begin
  if FBmp = nil then Exit;
  w := ScaleF(AWidthLogical);
  if w <= 0 then Exit;
  ctx := FBmp.Canvas2D;
  ctx.lineWidth := w;
  ctx.strokeStyle(TyColorToBGRA(AColor));
  if (Length(FVecDash) > 0) then
  begin
    StrokePathKept(AColor, AWidthLogical);
    Exit;
  end;
  ctx.lineStyle([]);
  if not FastStrokePen(FBmp, ctx, st, wr) then
  begin
    StrokePathKept(AColor, AWidthLogical);
    Exit;
  end;
  pts := ctx.currentPath;
  if Length(pts) = 0 then Exit;
  if not FastStrokeBrush(FBmp, ctx, st, b, maskScan) then
  begin
    maskScan.Free;
    Exit;
  end;
  try
    clip := FBmp.ClipRect;
    ws := wr;
    keep := not GKeptFillsOff;
    { found by the path, the width and the clip }
    h := KeptFillHash(pts, clip);
    {$push}{$R-}{$Q-}
    h := (h xor QWord(PLongWord(@ws)^)) * QWord($100000001B3);
    {$pop}
    first := nil;
    f := nil;
    if keep and (GKeptBands <> nil) and GKeptBands.TryGetValue(h, first) then
    begin
      f := first;
      while f <> nil do
      begin
        if (Length(f.Pts) = Length(pts)) and EqualRect(f.Clip, clip) and (f.Width = ws)
          and (f.Join = st.penStroker.JoinStyle) and (f.Miter = st.penStroker.MiterLimit)
          and (f.Cap = st.penStroker.LineCap)
          and CompareMem(@f.Pts[0], @pts[0], Length(pts) * SizeOf(TPointF)) then
          Break;
        f := f.Next;
      end;
    end;
    made := f = nil;
    if made then
    begin
      f := TTyKeptFill.Create;
      f.Pts := pts;
      f.Clip := clip;
      f.Width := ws;
      f.Join := st.penStroker.JoinStyle;
      f.Miter := st.penStroker.MiterLimit;
      f.Cap := st.penStroker.LineCap;
      if not MakeDistanceBand(f, pts, wr, clip, f.Join, f.Miter, f.Cap) then
      begin
        f.Free;
        maskScan.Free;
        maskScan := nil;
        StrokePathKept(AColor, AWidthLogical);
        Exit;
      end;
      SetLength(f.Ops, f.NOps);
      Inc(GBandsMade);
    end
    else
      Inc(GBandsReplayed);
    ReplayKeptOps(FBmp, f, b);
    if made then
    begin
      if keep then
      begin
        if GKeptBands = nil then
          GKeptBands := specialize TDictionary<QWord, TTyKeptFill>.Create;
        if (GKeptBandCount >= KeptFillsMaxCount)
          or (GKeptBandBytes + Int64(Length(f.Pts)) * SizeOf(TPointF) + f.NOps * 4 > KeptFillsMaxBytes) then
        begin
          DropKeptBands;
          first := nil;
        end;
        f.Next := first;
        GKeptBands.AddOrSetValue(h, f);
        Inc(GKeptBandCount);
        Inc(GKeptBandBytes, Int64(Length(f.Pts)) * SizeOf(TPointF) + f.NOps * 4);
      end
      else
        f.Free;
    end;
  finally
    maskScan.Free;
  end;
end;

{ Every state on ACtx (the current one and the saved ones) that shares AMask gets a copy
  of its own, so AMask can be freed. }
procedure CanvasDisownMask(ACtx: TBGRACanvas2D; AMask: TGrayscaleMask);
var
  slot, i: Integer;
  st: TBGRACanvasState2D;
  stack: TList;

  procedure Disown(S: TBGRACanvasState2D);
  begin
    if (S <> nil) and (S.clipMaskReadOnly = AMask) then
      S.SetClipMask(AMask.Duplicate as TGrayscaleMask, True);
  end;

begin
  st := CanvasStateOf(ACtx);
  if st = nil then Exit;
  Disown(st);
  slot := CanvasStateSlot(ACtx);
  stack := TList(PPointer(ACtx)[slot - 1]);
  for i := 0 to stack.Count - 1 do
    Disown(TBGRACanvasState2D(stack[i]));
end;

procedure TTyPainter.ReleaseClipMasks;
var
  i: Integer;
begin
  for i := 0 to cClipPool - 1 do
    with GClipPool[i] do
      if Owner = Self then
      begin
        Owner := nil;
        if Mask = nil then Continue;
        if FBmp <> nil then
          CanvasDisownMask(FBmp.Canvas2D, TGrayscaleMask(Mask));
        if Int64(W) * H > Int64(cClipPoolKeepPx) * S * S then FreeAndNil(Mask);
      end;
end;

destructor TTyPainter.Destroy;
begin
  ReleaseClipMasks;
  inherited Destroy;
end;

procedure TTyPainter.ClipRect(const ARect: TRect);
var
  ctx: TBGRACanvas2D;
  st: TBGRACanvasState2D;
  cur: TAffineMatrix;
  i, slot: Integer;
  fresh: Boolean;
begin
  if FBmp = nil then Exit;
  ctx := FBmp.Canvas2D;
  { an intersection with an earlier clip is built as always; only the first clip of a
    state comes from (and goes to) the kept masks }
  st := CanvasStateOf(ctx);
  fresh := (st <> nil) and (st.clipMaskReadOnly = nil) and not GClipReuseOff;
  if fresh then
  begin
    cur := ctx.matrix;
    for i := 0 to cClipPool - 1 do
      with GClipPool[i] do
        if (Mask <> nil) and ((Owner = nil) or (Owner = Self))
          and CompareMem(@R, @ARect, SizeOf(TRect))
          and CompareMem(@M, @cur, SizeOf(cur)) and (W = FBmp.Width) and (H = FBmp.Height)
          and (AA = ctx.antialiasing) and (PC = ctx.pixelCenteredCoordinates) then
        begin
          Owner := Self;
          { what the clip below leaves behind besides the mask }
          ctx.fillMode := fmWinding;
          ctx.beginPath;
          FPathOpen := False;
          st.SetClipMask(TGrayscaleMask(Mask), False);
          Exit;
        end;
  end;
  { Built as a PATH, not as a rectangular region, so the current matrix applies.
    A region-based clip would cut rotated content with an unrotated box. }
  ctx.beginPath;
  ctx.rect(ARect.Left, ARect.Top, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
  ctx.fillMode := fmWinding;
  CtxClip(ctx);
  ctx.beginPath;   // leave no half-built path behind for the caller to trip on
  FPathOpen := False;
  if not (fresh and (st.clipMaskReadOnly <> nil)) then Exit;
  Inc(GClipMasksBuilt);
  { a slot that is spare or this painter's own, round the pool from where the last
    one went; none -- every entry another live painter's -- keeps nothing }
  slot := -1;
  for i := 0 to cClipPool - 1 do
    if (GClipPool[(GClipPoolNext + i) mod cClipPool].Owner = nil)
      or (GClipPool[(GClipPoolNext + i) mod cClipPool].Owner = Self) then
    begin
      slot := (GClipPoolNext + i) mod cClipPool;
      Break;
    end;
  if slot < 0 then Exit;
  with GClipPool[slot] do
  begin
    if Mask <> nil then
    begin
      { a spare one nobody shares; this painter's own its canvas may }
      if Owner = Self then CanvasDisownMask(ctx, TGrayscaleMask(Mask));
      FreeAndNil(Mask);
    end;
    Mask := st.clipMaskReadOnly.Duplicate as TGrayscaleMask;
    R := ARect;
    M := cur;
    W := FBmp.Width;
    H := FBmp.Height;
    S := FScale;
    AA := ctx.antialiasing;
    PC := ctx.pixelCenteredCoordinates;
    Owner := Self;
    { the state shares the kept copy, as a hit would }
    st.SetClipMask(TGrayscaleMask(Mask), False);
  end;
  GClipPoolNext := (slot + 1) mod cClipPool;
end;

procedure TTyPainter.SetElementAlpha(AAlpha: Double);
begin
  if FBmp = nil then Exit;
  if AAlpha < 0 then AAlpha := 0;
  if AAlpha > 1 then AAlpha := 1;
  FBmp.Canvas2D.globalAlpha := AAlpha;
end;

{ ---- rotated text ---- }

function TTyPainter.TextBaseline(const AFontName: string;
  AFontSizeLogical, AWeight: Integer): Double;
var
  m: TFontPixelMetric;
  raster: Boolean;
  sz: TSize;
begin
  Result := 0;
  if FBmp = nil then Exit;
  raster := RasterEnter;
  try
    TyConfigureTextFont(FBmp, AFontName, AFontSizeLogical, AWeight, FPPI);
    m := FBmp.FontPixelMetric;
    if m.Defined then Result := m.Baseline
    else
    begin
      { no metric from the renderer: the box's height less a fifth, the
        usual descent }
      sz := FBmp.TextSize('Hg');
      Result := sz.cy * 0.8;
    end;
    if raster then Result := Result / FScale;
  finally
    RasterLeave;
  end;
end;

procedure TTyPainter.DrawTextRotated(const AText, AFontName: string;
  AFontSizeLogical, AWeight: Integer; AColor: TTyColor;
  AX, AY, AAngleRad: Double; AHAlign: TAlignment; AVAlign: TTextLayout);
var
  sz: TSize;
  ca, sa, ox, oy, rx, ry, anchorX, anchorY: Double;
begin
  if (FBmp = nil) or (AText = '') then Exit;
  { drawn straight on the layer, so in the raster scope: the anchor in raster pixels, the
    font at the raster PPI (#83) }
  if RasterEnter then
  begin
    anchorX := AX * FScale;
    anchorY := AY * FScale;
  end
  else
  begin
    anchorX := AX;
    anchorY := AY;
  end;
  try
  TyConfigureTextFont(FBmp, AFontName, AFontSizeLogical, AWeight, FPPI);
  sz := FBmp.TextSize(AText);

  { Resolve the alignment into an offset from the ANCHOR to the text box's
    top-left, in the text's own unrotated frame... }
  case AHAlign of
    taCenter:       ox := -sz.cx / 2;
    taRightJustify: ox := -sz.cx;
  else
    ox := 0;
  end;
  case AVAlign of
    tlCenter: oy := -sz.cy / 2;
    tlBottom: oy := -sz.cy;
  else
    oy := 0;
  end;

  { ...then rotate that offset, so the anchor stays put and the box swings
    around it. TextOutAngle takes tenths of a degree, counter-clockwise. }
  ca := Cos(AAngleRad);
  sa := Sin(AAngleRad);
  rx := ox * ca + oy * sa;
  ry := -ox * sa + oy * ca;

  FBmp.TextOutAngle(anchorX + rx, anchorY + ry, Round(AAngleRad * 1800 / Pi),
                    AText, TyColorToBGRA(AColor), taLeftJustify, FRightToLeft);
  finally
    RasterLeave;
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
  FreeAndNil(TTyGdiTextRenderer.GMeasure);
  FreeAndNil(TTyGdiTextRenderer.GTurn);
  TTyGdiTextRenderer.DropRuns;
  FreeAndNil(TTyGdiTextRenderer.GRuns);
  FreeAndNil(TTyGdiTextRenderer.GSizes);
  {$ENDIF}
  FreeAndNil(GImgCache);  // OwnsObjects frees the cached bitmaps
  FreeAndNil(GShadowCache);
  TyInvalidateTextMeasureCache;   // frees the boxed block measurements
  FreeAndNil(GBlockCache);
  FreeAndNil(GRenderCache);
  { a painter still alive at exit would have let go of its entries already: the
    pool's masks are no state's now }
  ClipPoolFreeAll;
  GRasterCanvases := nil;
  DropKeptFills;
  FreeAndNil(GKeptFills);
  DropKeptContours;
  FreeAndNil(GKeptContours);

end.
