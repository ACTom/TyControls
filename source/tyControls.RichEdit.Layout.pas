unit tyControls.RichEdit.Layout;

{ The layout layer under TTyRichEdit: what a paragraph looks like at a given width, PPI and
  zoom - its lines, and in each line the pieces of text, tabs and objects it is drawn in - and
  the queries a caret, a mouse and a selection need of it.

  Measuring goes through a text device (TTyRichTextDevice): it resolves fonts, answers their
  metrics, the advance of a piece of text, and whether a font has a glyph for a code point,
  and it draws a piece. The real one (TTyRichBgraDevice) measures and draws on the package's
  own text path (TyConfigureTextFont's set-up, TTyGdiTextRenderer on Windows); a test device
  answers by fixed rules and counts its calls. What is measured is what is drawn: a line is
  drawn fragment by fragment, each fragment exactly the string that was measured for it, at
  the X the layout gave it - never a whole line at once after measuring it piece by piece.

  Cost (a measure call is about a tenth of a millisecond on the real path, whatever its
  length): a paragraph is cut into pieces at its break opportunities (a word with its
  trailing spaces, one CJK character, a tab, an object), each piece is measured once and the
  advance kept by (font, text), and a line takes pieces while they fit. A line's pieces of
  one font and format are then measured once more as the one fragment that will be drawn.
  Positions inside a fragment are measured only when a caret, a hit test or a selection asks
  for them (one prefix measure each, kept the same way). Nothing here walks the document:
  laying out paragraph i reads paragraph i.

  The unit of layout is a block (TTyBlockLayout): a paragraph (TTyParaLayout), or a table
  row - the paragraphs of all its cells (TTyRowLayout). Positions in a
  block's queries count characters from the block's first character (a paragraph separator
  is one), so a block stays valid while the paragraphs before it are edited; the document
  position is TTyRichText.ParaStart(FirstPara) plus that.

  Layouts are reference counted. TTyRichLayouter keeps the recent ones (bounded by count and
  by characters held) and hands each out with a reference for the caller, who releases it;
  so a layout the caller still holds stays usable after the cache has let it go. A layout
  keeps a counted reference to every object it shows (an object read from a document that
  parses on demand is good only until the next read otherwise) and lets go when it is freed.
  A layout must not outlive the layouter that made it (its queries measure through it).

  How the control uses it (TTyCustomRichEdit, and the caret and selection built on it):
  - One layouter per control. Document := its document when it makes it and whenever it
    replaces the document or the document's content (a load): the layouter knows its
    document by being told, never by its address. Forward the document's OnChange to
    DocumentChanged.
  - LayoutBlock(Doc, i, Width, PPI, Zoom) per block on screen, Width from TyRichLayoutWidth
    (0 = CRichNoWrap is "no wrapping", never "a window 0 wide"). Keep the result (it carries
    a reference) while the block is shown; Release it after. After a change ask again for
    the blocks the change met (the cache answers at once for the others). A held layout the
    change did not touch still paints as it is; one the cache had let go of reports Stale
    after any change (it cannot follow its paragraph to a new index) - its holder takes the
    paragraph indexes from its own records or asks again.
  - A caret is a position and a flag: PosAtPoint(X, Y, AtLineEnd) gives both, and CaretRect
    takes both. The control keeps both with its caret: True where the caret sits at the end
    of a wrapped line (a click past it; End on such a line), False after any other move (a
    position reached by Home, an arrow, typing or a click elsewhere is shown at the start of
    the line it begins). SelectionRects takes positions only (a range has no affinity).
  - A block may be Truncated (a paragraph past CRichMaxParaLayoutChars): ShownChars of its
    CharCount positions are laid out; the control can tell the user.
  - BeginPaintPass once per paint, before the blocks are painted: the pictures one paint
    draws never evict each other. With TTyRichPaintStyle.DeferPictures a picture that is not
    PictureReady at its box's size is reported (TakeSkippedPictures); PreparePicture makes it
    ready - after that PictureReady is True for that size, whatever came of it (a placeholder
    for one that cannot be shown is ready too) - so a (picture, size) the control has just
    prepared is never queued again for that size.

  Bidirectional text is not laid out (spec 6.1): logical order, left to right; RtlPar is
  kept by the model and not shown. }

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$codepage utf8}

interface

uses
  Classes, SysUtils, Types, Graphics, Generics.Collections, BGRABitmap, BGRABitmapTypes,
  tyControls.RichEdit.Text, tyControls.RichEdit.Model, tyControls.RichEdit.RowFormat;

const
  { The layout cache: at most this many blocks ... }
  CLayoutCacheParas = 2048;
  { ... and at most this many characters in them, so that a few giant paragraphs cannot keep
    hundreds of megabytes of layout alive. The block laid out last always stays. }
  CLayoutCacheChars = 2000000;
  { A tab past the last explicit stop goes to the next multiple of this (twips, from the
    layout's left edge, as RTF counts \tx). }
  CRichDefaultTabTwips = 720;
  { The longest piece measured, and the longest fragment drawn, as one string (characters;
    a cluster is never cut, so one may run a little over). A long word is measured in such
    pieces, so that breaking it costs what its length costs, not its length squared. }
  CRichMaxPieceChars = 256;
  { Advances kept per layouter; past it the older half is dropped ... }
  CRichMeasureCacheEntries = 65536;
  { ... and the bytes their keys (a font and a fragment's text, up to CRichMaxPieceChars
    characters) take, with what an entry costs besides: past half of it the older half goes
    too, so a cache of long Chinese fragments stays a few megabytes. }
  CRichMeasureCacheBytes = 8 * 1024 * 1024;
  { A layout width that means "no wrapping" (TTyRichWrapMode rwmNone). }
  CRichNoWrap = 0;
  { The box of a picture whose size is not known, in pixels at 96 PPI and zoom 1. }
  CRichDefaultObjectPx = 32;
  { Ceilings on the way from a file's sizes to pixels; the document keeps what it read. The
    largest font, in pixels: Word's largest size (1638 pt, \fs3276) is 3276 px at 100 % on a
    144 PPI screen. A larger size (a corrupt \fs, or a zoom past it) is measured, given its
    metrics and drawn at this one - every font goes through the device's ResolveFont, which
    applies it - since the renderer allocates a run's box and an unbounded size is
    gigabytes. }
  CRichMaxFontPx = 3300;
  { The longest length a file gives that becomes pixels (TyRichTwipsToPx saturates at it,
    either sign): indents, tab positions, space before and after, an exact or at-least line
    height, a picture's box, a cell's edges. }
  CRichMaxLengthPx = 32767;
  { A block's height and its lines' tops are sums of such lengths; they stop here. }
  CRichMaxBlockPx = MaxInt div 4;
  { A paragraph longer than this many characters is laid out only up to them (cut at a
    cluster's start), with one line under it that says how many are not shown
    (rsRichEditParaNotShown, in the paragraph's font; not selectable, no positions): a guard,
    so that a file that is one 100 MB line costs a 100,000-character paragraph, not gigabytes.
    The document keeps the whole paragraph (copying and saving take all of it); positions
    past the cut show at the cut (TTyBlockLayout.Truncated, ShownChars). }
  CRichMaxParaLayoutChars = 100000;
  { A list item's number is its place among the items before it, found by looking back; the
    look goes back at most this many paragraphs. An item further down a longer list is
    numbered as if the list started at the cap (its number is too small) - the price of never
    reading thousands of paragraphs, which a document that parses on demand would parse, to
    show one screen. }
  CRichListWalkParas = 4096;
  { Numbers found are remembered (so scrolling down a list costs one step per item) up to this
    many paragraphs; past it they are forgotten all at once. }
  CRichListOrdinalCache = 65536;
  { A table cell whose right edge neither the row nor the table gives is this wide (twips). }
  CRichDefaultCellTwips = 1440;
  { The widest cell border drawn (twips): Word's limit for \brdrw. A wider one in a file is
    drawn this wide. }
  CRichMaxBorderTwips = 75;
  { Pictures the layouter has drawn are kept decoded (or reduced to the size they were drawn
    at) up to this many bytes - their pixels, and the bytes of the pictures held for them -
    the least recently drawn going first, the ones of the current paint pass (and the one
    drawn last) always staying: a document of thousands of pictures keeps decoded only what
    was on screen lately, and one screen's pictures never evict each other. }
  CRichPictureCacheBytes = 64 * 1024 * 1024;
  { The most pixels a picture is decoded to: 32 Mi (128 MB decoded). A header that says more
    is not decoded - a placeholder - except a JPEG, which decodes at 1/2, 1/4 or 1/8 while
    decoding to fit; nothing is allocated before the header says what it costs. }
  CRichPictureMaxPixels = 32 * 1024 * 1024;
  { The largest reduced copy kept of a picture: 8 Mi pixels (32 MB, a 4K screen). A reduction
    to more is drawn from the decoded image for the part inside the clip, as an enlargement
    always is. }
  CRichPictureMaxScaledPixels = 8 * 1024 * 1024;

  { Line-breaking rules (kinsoku), after the common practice of JIS X 4051 and GB/T 15834:
    the characters a line must not start with (closing brackets and quotes, sentence and
    clause punctuation, iteration marks, small kana, the prolonged sound mark) and the ones
    it must not end with (opening brackets and quotes, currency signs that lead a number),
    as code points. Not resourcestrings: they are rules of the scripts, not words of a
    language. }
  CRichKinsokuNoLineStart: array[0..118] of Cardinal = (
    $0021, $0025, $0029, $002C, $002E, $003A, $003B, $003F, $005D, $007D, $00A2, $00B0, $00B7,
    $00BB, $2010, $2013, $2014, $2019, $201D, $2025, $2026, $2030, $2032, $2033, $203A, $2103,
    $2236, $3001, $3002, $3003, $3006, $3005, $3009, $300B, $300D, $300F, $3011, $3015, $3017,
    $3019, $301B, $301C, $301E, $301F, $303B, $309B, $309C, $309D, $309E, $30FB, $30FC, $30FD,
    $30FE, $3041, $3043, $3045, $3047, $3049, $3063, $3083, $3085, $3087, $308E, $3095, $3096,
    $30A1, $30A3, $30A5, $30A7, $30A9, $30C3, $30E3, $30E5, $30E7, $30EE, $30F5, $30F6, $31F0,
    $31F1, $31F2, $31F3, $31F4, $31F5, $31F6, $31F7, $31F8, $31F9, $31FA, $31FB, $31FC, $31FD,
    $31FE, $31FF, $FF01, $FF05, $FF09, $FF0C, $FF0E, $FF1A, $FF1B, $FF1F, $FF3D, $FF5D, $FF61,
    $FF63, $FF64, $FF65, $FF70, $FF60, $FE50, $FE51, $FE52, $FE54, $FE55, $FE56, $FE57, $FE5A,
    $FE5C, $FE5E);
  CRichKinsokuNoLineEnd: array[0..29] of Cardinal = (
    $0028, $005B, $007B, $00A3, $00A5, $00AB, $2018, $201C, $2039, $3008, $300A, $300C, $300E,
    $3010, $3014, $3016, $3018, $301A, $301D, $FF08, $FF3B, $FF5B, $FF62, $FF5F, $FF04, $FFE1,
    $FFE5, $FE59, $FE5B, $FE5D);

type
  TRectArray = array of TRect;

  { Code points First..Last (inclusive). }
  TTyRichCodeRange = record
    First, Last: Cardinal;
  end;
  TTyRichCodeRanges = array of TTyRichCodeRange;

  { rwmWindow: lines wrap at the width the owner passes (the window's, in pixels);
    rwmPage: at the page's text width (PaperWidth - MarginLeft - MarginRight, in pixels at
    the PPI and zoom); rwmNone: they do not wrap. TyRichLayoutWidth turns a mode into the
    width LayoutPara takes. }
  TTyRichWrapMode = (rwmWindow, rwmPage, rwmNone);

  { A font as the device resolved it: a small number, the same for the same name, pixel
    height and style for the device's whole life. }
  TTyRichFontId = Integer;

  { Pixels: above the baseline, below it, and the gap the font asks for below that. }
  TTyRichFontMetrics = record
    Ascent: Integer;
    Descent: Integer;
    Leading: Integer;
  end;

  TTyRichFontEntry = record
    Name: string;
    PixelHeight: Integer;
    Style: TFontStyles;
    Metrics: TTyRichFontMetrics;
    HasMetrics: Boolean;
  end;

  { What layout measures with and painting draws with. A subclass answers the Do* calls; the
    public calls count them (for tests that check what a layout costs). Fonts are resolved
    here, once per (name, pixel height, style); only bold and italic are a font's style -
    underline and strike-through are drawn by the painter. }
  TTyRichTextDevice = class
  private
    FFonts: array of TTyRichFontEntry;
    FFontCount: Integer;
    FFontIndex: specialize TDictionary<string, Integer>;
    FMeasureCalls: Int64;
    FMeasuredChars: Int64;
    FGlyphQueries: Int64;
    FDrawCalls: Int64;
    procedure CheckFont(AFont: TTyRichFontId);
  protected
    function DoMetrics(AFont: TTyRichFontId): TTyRichFontMetrics; virtual; abstract;
    { The advance of AText drawn as one string in AFont, in whole pixels. }
    function DoTextWidth(AFont: TTyRichFontId; const AText: UTF8String): Integer; virtual; abstract;
    { How many code points from the start of AText fit in AMaxWidth (a hint: layout checks it
      with DoTextWidth). This one searches with DoTextWidth. }
    function DoFitCount(AFont: TTyRichFontId; const AText: UTF8String;
      AMaxWidth: Integer): Integer; virtual;
    function DoHasGlyph(AFont: TTyRichFontId; ACode: Cardinal): Boolean; virtual; abstract;
    { Draws AText in AFont with its baseline's left end at (AX, ABaseline) of ATarget. }
    procedure DoDrawText(ATarget: TBGRABitmap; AFont: TTyRichFontId; AX, ABaseline: Integer;
      const AText: UTF8String; AColor: TBGRAPixel); virtual; abstract;
    { Counts a measure of ACodePoints code points; for a subclass whose DoFitCount measures
      on its own. }
    procedure CountMeasure(ACodePoints: Integer);
  public
    constructor Create;
    destructor Destroy; override;
    function ResolveFont(const AName: string; APixelHeight: Integer;
      AStyle: TFontStyles): TTyRichFontId;
    function FontCount: Integer;
    function FontName(AFont: TTyRichFontId): string;
    function FontPixelHeight(AFont: TTyRichFontId): Integer;
    function FontStyle(AFont: TTyRichFontId): TFontStyles;
    { Kept per font: asked of the subclass once. }
    function Metrics(AFont: TTyRichFontId): TTyRichFontMetrics;
    function TextWidth(AFont: TTyRichFontId; const AText: UTF8String): Integer;
    function FitCount(AFont: TTyRichFontId; const AText: UTF8String; AMaxWidth: Integer): Integer;
    function HasGlyph(AFont: TTyRichFontId; ACode: Cardinal): Boolean;
    { The drawing entry: AText is a fragment's text, (AX, ABaseline) where the layout put it
      (ATarget's pixels). }
    procedure DrawText(ATarget: TBGRABitmap; AFont: TTyRichFontId; AX, ABaseline: Integer;
      const AText: UTF8String; AColor: TBGRAPixel);
    procedure ResetCounters;
    { TextWidth and FitCount calls, and the code points they were given. }
    property MeasureCalls: Int64 read FMeasureCalls;
    property MeasuredChars: Int64 read FMeasuredChars;
    property GlyphQueries: Int64 read FGlyphQueries;
    property DrawCalls: Int64 read FDrawCalls;
  end;

  { The real device: measures and draws on the package's text path - a TBGRABitmap with
    TyConfigureTextFont's set-up (the font name through TyEffectiveFontName, the pixel height
    as BGRA's FontHeight, TyTextFontQuality, the package's text renderer) - so a width it
    reports is the width TTyPainter draws, and DrawText draws on the same set-up. The
    metrics come from an LCL canvas with the same font (the ascent the renderer puts the
    baseline at). Glyphs: on Windows read from the font's own cmap table through GDI (every
    widgetset); elsewhere, where the platform's text engine substitutes missing glyphs by
    itself, a font is taken to have a CJK or emoji glyph when its name says it is such a
    font (unverified there). Main thread only, like all drawing. }
  TTyRichBgraDevice = class(TTyRichTextDevice)
  private
    FMeasure: TBGRABitmap;
    FMeasureFont: TTyRichFontId;
    FMetricsBmp: TBitmap;
    FCoverage: TObject;
    procedure Configure(ABmp: TBGRABitmap; AFont: TTyRichFontId);
  protected
    function DoMetrics(AFont: TTyRichFontId): TTyRichFontMetrics; override;
    function DoTextWidth(AFont: TTyRichFontId; const AText: UTF8String): Integer; override;
    function DoHasGlyph(AFont: TTyRichFontId; ACode: Cardinal): Boolean; override;
    procedure DoDrawText(ATarget: TBGRABitmap; AFont: TTyRichFontId; AX, ABaseline: Integer;
      const AText: UTF8String; AColor: TBGRAPixel); override;
  public
    constructor Create;
    destructor Destroy; override;
  end;

  { rfkText: characters drawn as Text; rfkSpace: a run of spaces (justification widens it);
    rfkTab: one tab, Width up to its stop, Leader to draw in it; rfkBreak: U+000B, no width;
    rfkObject: one object character - a picture's box, or an opaque object shown as its
    display text (Text), atomic for positions; rfkReplacement: a byte that is not text,
    shown as one U+FFFD - for the two characters of an escaped byte, the first takes the
    glyph's advance and the second none. }
  TTyRichFragKind = (rfkText, rfkSpace, rfkTab, rfkBreak, rfkObject, rfkReplacement);

  { One piece of a line, drawn as one string (Text) in Font with its baseline at the line's
    Baseline + Shift. First/Count: the characters it covers (block-relative). X, Width:
    block-relative pixels. Format: the character format (colour, highlight, underline,
    strike-through for the painter). Ascent/Descent: what it needs above and below the
    line's baseline, its shift included. Natural: its measured width (Width less what
    justification added).

    A justified line with no spaces to stretch is stretched between its characters, where a
    line may break, and keeps its text in few fragments: such a fragment is cut into segments
    at its break opportunities (StretchGaps > 0) - each segment one string, measured and drawn
    by itself, the fragment's natural width their sum - and the gap before its k-th break
    opportunity (k = 1, 2, ...) is the line's Stretch spread over its StretchGaps gaps: the
    caret, hit tests, selections and painting all put segment k at
    Stretch * (StretchFirst + k) div StretchGaps - Stretch * StretchFirst div StretchGaps past
    its natural place, StretchFirst being the gaps of the line before the fragment. Only such
    lines are drawn a segment (for Chinese, a character) a call. }
  TTyRichFragment = record
    Kind: TTyRichFragKind;
    First: Integer;
    Count: Integer;
    X: Integer;
    Width: Integer;
    Natural: Integer;
    Font: TTyRichFontId;
    Format: TTyCharFormatId;
    Shift: Integer;
    Ascent: Integer;
    Descent: Integer;
    ByteStart: Integer;      // in the block's text (0-based), rfkText and rfkSpace
    ByteLen: Integer;
    Text: UTF8String;        // rfkObject's display text, rfkReplacement's U+FFFD
    Obj: TTyRichObject;      // rfkObject: a counted reference the layout holds
    Leader: TTyTabLeader;    // rfkTab
    Stretch: Integer;        // rfkText cut into segments (StretchGaps > 0), see above
    StretchGaps: Integer;
    StretchFirst: Integer;
  end;

  { One line. First/Count: its characters (block-relative; trailing spaces and a U+000B
    that ends it included). Top, Height, Baseline: block-relative pixels. Left: where its
    content starts; ContentWidth: its width without the trailing spaces, which hang past
    the right edge; EndX: where its last fragment ends. Forced: ended by U+000B. }
  TTyRichLine = record
    First: Integer;
    Count: Integer;
    Top: Integer;
    Height: Integer;
    Baseline: Integer;
    Left: Integer;
    ContentWidth: Integer;
    EndX: Integer;
    FirstFrag: Integer;
    FragCount: Integer;
    Forced: Boolean;
  end;

  { The colours painting takes from the control's theme - the layouter never looks at a theme;
    the control fills this in, a test by hand. A run's own colour and highlight are the
    document's, not these. }
  TTyRichPaintStyle = record
    TextColor: TBGRAPixel;          // text in clDefault (the theme's text colour)
    SelectionBack: TBGRAPixel;
    SelectionText: TBGRAPixel;
    PlaceholderFill: TBGRAPixel;    // a picture that cannot be shown
    PlaceholderFrame: TBGRAPixel;
    ObjectFrame: TBGRAPixel;        // around a selected picture
    TableBorder: TBGRAPixel;
    { A picture not ready to be drawn at its box's size (not decoded, or not scaled to it) is
      not made ready by this paint: its box is filled PlaceholderFill (no frame, which would
      flash) and the layouter notes it (TakeSkippedPictures), for the owner to prepare later
      (PreparePicture) and repaint that box - so a paint while scrolling never waits for a
      decoder. False: every picture is decoded and drawn now (a preview, a test). }
    DeferPictures: Boolean;
  end;

  { A picture a paint passed over (TTyRichPaintStyle.DeferPictures): the box it was to be drawn
    in (the target's pixels, as that paint placed the block). The record holds a reference to
    the picture, which whoever takes it releases. }
  TTyRichSkippedPicture = record
    Picture: TTyRichPicture;
    Box: TRect;
  end;
  TTyRichSkippedPictures = array of TTyRichSkippedPicture;

  { What painting needs of a character format, taken when the layout is made. }
  TTyRichPaintFormat = record
    Format: TTyCharFormatId;
    Color: TColor;
    Highlight: TColor;
    Underline: Boolean;
    Strike: Boolean;
  end;

  TTyRichLayouter = class;

  { A laid-out block: one paragraph, or (later) one table row. Coordinates are pixels from
    the block's top-left; positions count characters from the block's first character.
    Reference counted: AddRef to keep one, Release when done (it is freed at 0). }
  TTyBlockLayout = class
  private
    FRefCount: Integer;
    FLruPrev, FLruNext: TTyBlockLayout;
    FInCache: Boolean;
  protected
    FLayouter: TTyRichLayouter;
    FFirstPara: Integer;
    FLastPara: Integer;
    FWidth: Integer;
    FHeight: Integer;
    FLayoutWidth: Integer;
    FPPI: Integer;
    FZoom: Single;
    FCharCount: Integer;
    FShownChars: Integer;
    FTruncated: Boolean;
    FStale: Boolean;
    { It shows a list number, which depends on the paragraphs before it: a change of
      paragraphs or formats above it drops it too. }
    FNumbered: Boolean;
    { The layouter's change count when the cache last vouched for it (see Stale). }
    FGen: Int64;
    function GetStale: Boolean;
  public
    constructor Create(ALayouter: TTyRichLayouter);
    procedure AddRef;
    procedure Release;
    { The nearest caret place to (AX, AY): a position in [0, CharCount]. AAtLineEnd: the place
      is the end of a line that wraps inside its paragraph - the point is past that line's
      end, or on the spaces that hang past it - which is the same position as the start of
      the line below; the caret belongs at the end of the line the point is on, so pass the
      flag on to CaretRect with the position. False everywhere else (a line that U+000B ends
      has its end before the U+000B, a position of its own; a paragraph's end is no line's
      start). }
    function PosAtPoint(AX, AY: Integer; out AAtLineEnd: Boolean): TTyRichPos; overload;
      virtual; abstract;
    { The same without the flag: a caret shown at the position goes to the next line's start. }
    function PosAtPoint(AX, AY: Integer): TTyRichPos; overload;
    { The caret at APos: one pixel wide, as tall as its line. AAtLineEnd (from PosAtPoint, or
      kept with a caret the keyboard moved to a line's end): at a position where a wrapped line
      ends and the next begins, the end of the earlier line; elsewhere it changes nothing. }
    function CaretRect(APos: TTyRichPos; AAtLineEnd: Boolean = False): TRect; virtual; abstract;
    { The rectangles that show [AFrom, ATo) selected, one per line it touches; a range that
      takes in the block's last separator (ATo > its last position) gets a mark past the
      end of its last line. }
    function SelectionRects(AFrom, ATo: TTyRichPos): TRectArray; virtual; abstract;
    { Draws the block with its top-left at (AX, AY) of ATarget. Only what meets AClip (the
      target's pixels; the target's own ClipRect is kept to as well) is drawn: lines,
      fragments, cells and pictures outside it cost nothing - a partial repaint is cheap.
      The ground is the caller's: it has painted the background and prepared the target for
      text (TTyPainter.PrepareTextGround). [ASelFrom, ASelTo) is the selection, block-relative
      as SelectionRects takes it (past the last position: the last separator too); an empty
      range selects nothing. A line is drawn in this order: highlights, the selection's
      ground, the text - each fragment exactly the string measured for it, at its measured
      place; a fragment selected in part is drawn whole once a part, the clip cut at the
      selection's edges, so no glyph moves - underline and strike-through (their thickness and
      place from the font's size), tab leaders, pictures and placeholders (a selected picture
      framed), the list marker. A row draws its cells' paragraphs, each clipped to its cell,
      then its lines. }
    procedure Paint(ATarget: TBGRABitmap; AX, AY: Integer; const AClip: TRect;
      const AStyle: TTyRichPaintStyle; ASelFrom, ASelTo: TTyRichPos); virtual; abstract;
    { Bytes the layout keeps (for the tests that check it stays linear). }
    function MemSize: Int64; virtual;
    property FirstPara: Integer read FFirstPara;
    property LastPara: Integer read FLastPara;
    { The widest line's right end (trailing spaces left out), and the block's height. }
    property Width: Integer read FWidth;
    property Height: Integer read FHeight;
    { What it was laid out for (CRichNoWrap: no wrapping). }
    property LayoutWidth: Integer read FLayoutWidth;
    property PPI: Integer read FPPI;
    property Zoom: Single read FZoom;
    { The characters it covers, separators between its paragraphs included. }
    property CharCount: Integer read FCharCount;
    { A paragraph of it was longer than CRichMaxParaLayoutChars and is shown only up to the
      cut (the control can tell the user); ShownChars: the positions laid out - CharCount when
      nothing is cut, else CharCount less what is not shown. }
    property Truncated: Boolean read FTruncated;
    property ShownChars: Integer read FShownChars;
    { What it says may no longer be the document: the paragraphs it shows changed after it
      was made (the layouter dropped it), or - for a layout the cache had already let go of
      while its holder kept it (evicted for space) - the document changed in any way since:
      such a layout cannot follow its paragraphs to new indexes, so after any change it is
      stale whatever the change touched. A holder asks for the block again after a change
      (LayoutBlock; the cache answers for the ones it kept, which follow their paragraphs and
      are not stale). A stale layout still paints and answers as it was made. }
    property Stale: Boolean read GetStale;
    property RefCount: Integer read FRefCount;
  end;

  { One paragraph laid out. Positions are characters from the paragraph's start; the
    paragraph's end (Length) is a caret place at the end of its last line.

    A list paragraph has a marker (HasMarker): its bullet or number, which layout makes - it
    is not in the text. It sits in the first line, on that line's baseline, at the first
    line's indent, as WordPad puts it: the text then starts at the left indent when the
    marker ends before it, else at the next tab stop after the marker. It is in the first
    run's font and size, has no characters (First and Count 0) and is not one of the line's
    fragments, so the caret, hit tests and selections never meet it. }
  TTyParaLayout = class(TTyBlockLayout)
  private
    FText: RawByteString;
    FLength: Integer;
    FShown: Integer;
    FNotice: TTyRichFragment;
    FNoticeTop, FNoticeBaseline: Integer;
    FHasMarker: Boolean;
    FMarker: TTyRichFragment;
    FInCell: Boolean;
    FLines: array of TTyRichLine;
    FLineCount: Integer;
    FFrags: array of TTyRichFragment;
    FFragCount: Integer;
    FSpaceBefore: Integer;
    FSpaceAfter: Integer;
    FPaintFormats: array of TTyRichPaintFormat;
    function GetLine(AIndex: Integer): TTyRichLine;
    function GetFragment(AIndex: Integer): TTyRichFragment;
    function ByteOfChar(const F: TTyRichFragment; AChars: Integer): Integer;
    function SnapToCluster(const F: TTyRichFragment; AChars: Integer): Integer;
    function PrefixWidth(const F: TTyRichFragment; AChars: Integer): Integer;
    function SegmentStarts(const F: TTyRichFragment; out ABytes: TIntegerDynArray): TIntegerDynArray;
    function SegmentWidth(const F: TTyRichFragment; const ABytes: TIntegerDynArray;
      ASeg: Integer): Integer;
    function XInLine(ALine: Integer; APos: Integer): Integer;
    function NearestInFragment(const F: TTyRichFragment; AX: Integer): Integer;
    function PointInLine(ALine, AX: Integer): Integer;
    function PaintFormat(AFormat: TTyCharFormatId): TTyRichPaintFormat;
    procedure TakePaintFormats(ADoc: TTyRichDocument);
    function LineSelection(ALine: Integer; AFrom, ATo: TTyRichPos; out AXa, AXb: Integer): Boolean;
    procedure PaintLine(ATarget: TBGRABitmap; ALine, AX, AY: Integer; const AClip: TRect;
      const AStyle: TTyRichPaintStyle; ASelFrom, ASelTo: TTyRichPos);
  public
    destructor Destroy; override;
    function PosAtPoint(AX, AY: Integer; out AAtLineEnd: Boolean): TTyRichPos; overload; override;
    function CaretRect(APos: TTyRichPos; AAtLineEnd: Boolean = False): TRect; override;
    function SelectionRects(AFrom, ATo: TTyRichPos): TRectArray; override;
    procedure Paint(ATarget: TBGRABitmap; AX, AY: Integer; const AClip: TRect;
      const AStyle: TTyRichPaintStyle; ASelFrom, ASelTo: TTyRichPos); override;
    function MemSize: Int64; override;
    { The line a position is on (the start of a wrapped line belongs to that line - or, with
      AAtLineEnd, to the line it ends: see CaretRect), and the line at a height (above the
      first: the first; below the last: the last). }
    function LineOfPos(APos: TTyRichPos; AAtLineEnd: Boolean = False): Integer;
    function LineAtY(AY: Integer): Integer;
    { What fragment AIndex draws (its Text for an object or a replacement). }
    function FragmentText(AIndex: Integer): UTF8String;
    property LineCount: Integer read FLineCount;
    property Lines[AIndex: Integer]: TTyRichLine read GetLine;
    property FragmentCount: Integer read FFragCount;
    property Fragments[AIndex: Integer]: TTyRichFragment read GetFragment;
    { The paragraph's text (UTF-8) as laid out, and the paragraph's length in characters. A
      Truncated paragraph's Text is what is shown, ShownChars characters; positions past
      them show at the cut, and the line under the text (Notice: its Text, Font, X, Width,
      drawn on NoticeBaseline) says how many are not shown. }
    property Text: RawByteString read FText;
    property Length: Integer read FLength;
    property Notice: TTyRichFragment read FNotice;
    property NoticeBaseline: Integer read FNoticeBaseline;
    property SpaceBefore: Integer read FSpaceBefore;
    property SpaceAfter: Integer read FSpaceAfter;
    property HasMarker: Boolean read FHasMarker;
    { Text, Font, Format, X, Width, Ascent, Descent; drawn on Lines[0].Baseline. }
    property Marker: TTyRichFragment read FMarker;
  end;

  { One cell of a laid-out row as it is shown. Left/Right: its box (block-relative pixels; a
    run of horizontally merged cells: the first cell's box reaches across all of them); the
    box is as tall as the row. Hidden: a cell merged into the one before it - not shown, never
    hit; its paragraphs (the file's empty ones) are positions the caret shows at the end of
    the cell it went into (Owner). Its paragraphs are items FirstItem .. FirstItem +
    ItemCount - 1 of the row. Sides: the lines drawn, each LinePx thick (a file's width up to
    CRichMaxBorderTwips) - its left and its top (not when it continues the cell above: a
    vertical merge), the right of the row's last cell and the bottom of the table's last row;
    so a line between two cells, or two rows, is drawn once, as the later one's. A declared
    right (bottom) is drawn by the cell itself when the next cell (the cell below: the one of
    the same index in the next row) does not declare the line on its side - a table that
    declares only bottom lines, as report generators write them, keeps them. }
  TTyRichCellBox = record
    Left, Right: Integer;
    Hidden: Boolean;
    Owner: Integer;
    FirstItem, ItemCount: Integer;
    ContentHeight: Integer;
    VAlign: TTyRowCellVAlign;
    VMerge: TTyRowCellMerge;
    Sides: TTyRowCellSides;
    LinePx: array[TTyRowCellSide] of Integer;
  end;

  { One paragraph of a row: its layout (the row holds the reference; it follows the row to
    new paragraph indexes), where that layout's top-left is in the row, its first position in
    the row, its cell. }
  TTyRichRowItem = record
    Layout: TTyParaLayout;
    X, Y: Integer;
    Pos: Integer;
    Cell: Integer;
  end;

  { One table row laid out (a block): all the paragraphs of all its cells, in text order -
    cell after cell, paragraph after paragraph - and its positions count through them as the
    document's text does, each paragraph's end one character.

    Geometry is the row format's (tyControls.RichEdit.RowFormat): the cells from their right
    edges (the row's own, else the table's), the row placed by \trleft from the layout's left
    edge (a negative one reaches left of it, as Word puts the lines in the margin) - or, for
    \trqc / \trqr, centred in or at the right of the layout width (when it wraps) - and never
    shrunk to the wrap width (the control scrolls); each cell's paragraphs laid out by
    themselves at the cell's width less the half gap (at most half the cell) on either side,
    their indents inside the cell, stacked from below its top line and placed by its vertical
    alignment (a cell with no width left for text takes no height for it); the row as
    tall as its tallest cell, and not less than (or, for an exact height, exactly) what the
    format demands. A horizontally merged run of cells is one box with the first cell's
    content; a cell that continues the one above draws no line toward it. A row that holds a
    nested table shows its paragraphs stacked in the outer cell (the model has no inner
    structure; that is phase 2). Not in phase 1: cell shading and border colours (they need
    the colour table), border styles other than a solid line, row-level borders, the content
    of a vertically merged cell centred over all its rows, dragging column edges.

    The row holds a counted reference to its table (so Table and Table.Rows[RowIndex] stay
    readable when the document lets the table go) and one to each paragraph's layout. }
  TTyRowLayout = class(TTyBlockLayout)
  private
    FTable: TTyRichTable;
    FRowIndex: Integer;
    FDisplay: TTyRowDisplay;
    FCells: array of TTyRichCellBox;
    FItems: array of TTyRichRowItem;
    function GetCell(AIndex: Integer): TTyRichCellBox;
    function GetItem(AIndex: Integer): TTyRichRowItem;
    function CellAtX(AX: Integer): Integer;
    procedure PaintRow(ATarget: TBGRABitmap; AX, AY: Integer; const AClip, AOld: TRect;
      const AStyle: TTyRichPaintStyle; ASelFrom, ASelTo: TTyRichPos);
  public
    destructor Destroy; override;
    { A point and a caret pass the line-end flag through to the paragraph they are in. The
      caret and the selection's rectangles stay inside the cell's box (and the row's height):
      what an exact-height row clips is not shown, nor its caret over the next row. }
    function PosAtPoint(AX, AY: Integer; out AAtLineEnd: Boolean): TTyRichPos; overload; override;
    function CaretRect(APos: TTyRichPos; AAtLineEnd: Boolean = False): TRect; override;
    function SelectionRects(AFrom, ATo: TTyRichPos): TRectArray; override;
    procedure Paint(ATarget: TBGRABitmap; AX, AY: Integer; const AClip: TRect;
      const AStyle: TTyRichPaintStyle; ASelFrom, ASelTo: TTyRichPos); override;
    function MemSize: Int64; override;
    { The item (paragraph) position APos is in: the last that starts at or before it. }
    function ItemAt(APos: TTyRichPos): Integer;
    function CellCount: Integer;
    property Cells[AIndex: Integer]: TTyRichCellBox read GetCell;
    function ItemCount: Integer;
    property Items[AIndex: Integer]: TTyRichRowItem read GetItem;
    property Table: TTyRichTable read FTable;
    property RowIndex: Integer read FRowIndex;
    { What the row's format says (TyRtfRowDisplay of its RawFormat; TyDefaultRowDisplay for a
      row with none). }
    property Display: TTyRowDisplay read FDisplay;
  end;

  { A character the font in effect has no glyph for: name a font for it in AFontName (left
    '' the layouter tries its FallbackFonts). }
  TTyRichFallbackEvent = procedure(Sender: TObject; const ABaseFont: string; ACode: Cardinal;
    var AFontName: string) of object;

  TTyRichFormatFont = record
    Font: TTyRichFontId;
    Shift: Integer;
  end;

  { A list item's number, remembered with the kind and level it was counted for. }
  TTyRichListOrdinal = record
    Kind: TTyListKind;
    Level: Integer;
    Number: Int64;
  end;

  TTyRichLayouter = class
  private
    FDevice: TTyRichTextDevice;
    FOwnsDevice: Boolean;
    FDoc: TTyRichDocument;
    FBaseFontName: string;
    FBaseFontSizeHalfPt: Integer;
    FFallbackFonts: TStringList;
    FOnFallbackFont: TTyRichFallbackEvent;
    // the layout cache: by first paragraph, LRU order, two bounds
    FCache: specialize TDictionary<Integer, TTyBlockLayout>;
    FLruFirst, FLruLast: TTyBlockLayout;
    FCachedChars: Int64;
    FHits, FMisses: Int64;
    // changes seen (DocumentChanged, Invalidate, Clear): what a layout out of the cache
    // compares its FGen with
    FChangeGen: Int64;
    // measuring
    FMeasure, FMeasureOld: specialize TDictionary<string, Integer>;
    FMeasureBytes, FMeasureOldBytes: Int64;
    FGlyphs: specialize TDictionary<Int64, Boolean>;
    FFallback: specialize TDictionary<Int64, Integer>;
    FFormatFonts: specialize TDictionary<Integer, TTyRichFormatFont>;
    FFontPPI: Integer;
    FFontZoom: Single;
    FFontName: string;
    FFontSize: Integer;
    // list numbers: by paragraph index; the list format of each paragraph format id
    FOrdinals: specialize TDictionary<Integer, TTyRichListOrdinal>;
    FListOfFormat: specialize TDictionary<Integer, TTyListFormat>;
    FListWalkSteps: Int64;
    FWalkData: array of Pointer;
    FWalkFirst, FWalkLast: Integer;
    // decoded pictures: by picture, LRU order (most recent first), bounded by bytes
    FPictures: specialize TDictionary<Pointer, TObject>;
    FPicFirst, FPicLast: TObject;
    FPictureBytes: Int64;
    FPictureLimit: Int64;
    FPictureDecodes: Int64;
    FPictureScales: Int64;
    FSkipped: TTyRichSkippedPictures;
    FSkippedCount: Integer;
    FPicturePass: Int64;
    FPassByCaller: Boolean;
    FPaintDepth: Integer;
    FPictureDecodeBudget: Int64;
    FPictureScaleBudget: Int64;
    FPictureDecodedPixels: Int64;
    function PictureEntry(APicture: TTyRichPicture): TObject;
    procedure PictureRecount(AEntry: TObject);
    procedure PictureDecode(AEntry: TObject);
    function PictureHow(AEntry: TObject; AWidth, AHeight: Integer): Integer;
    procedure PictureMakeReady(AEntry: TObject; AWidth, AHeight: Integer);
    procedure PaintEnter;
    procedure PaintLeave;
    procedure ClearLayouts;
    procedure NoteSkippedPicture(APicture: TTyRichPicture; const ABox: TRect);
    procedure ClearSkippedPictures;
    procedure WalkCollect(AIndex: Integer; AData: Pointer; ASrcOffset, ASrcBytes: Int64;
      var AContinue: Boolean);
    function ListOfFormat(ADoc: TTyRichDocument; AFormat: TTyParaFormatId): TTyListFormat;
    procedure DropNumbersFrom(AFirst: Integer);
    procedure PictureUnlink(AEntry: TObject);
    procedure PicturePushFront(AEntry: TObject);
    procedure PictureDrop(AEntry: TObject);
    procedure PictureTrim(AKeep: TObject);
    procedure SetPictureLimit(AValue: Int64);
    procedure SetDocument(AValue: TTyRichDocument);
    procedure SetBaseFontName(const AValue: string);
    procedure SetBaseFontSizeHalfPt(AValue: Integer);
    procedure FallbackFontsChanged(Sender: TObject);
    procedure SetOnFallbackFont(AValue: TTyRichFallbackEvent);
    procedure LruUnlink(L: TTyBlockLayout);
    procedure LruPushFront(L: TTyBlockLayout);
    procedure CacheDrop(L: TTyBlockLayout; AStale: Boolean);
    procedure CacheInsert(L: TTyBlockLayout);
    procedure CacheTrim(AKeep: TTyBlockLayout);
    procedure FontsFor(APPI: Integer; AZoom: Single);
    function BuildPara(ADoc: TTyRichDocument; AIndex, AWidth, APPI: Integer;
      AZoom: Single): TTyParaLayout;
    function BuildRow(ADoc: TTyRichDocument; AFirst, ALast: Integer; ARow: TTyRichRow;
      AWidth, APPI: Integer; AZoom: Single): TTyRowLayout;
    procedure Prepare(ADoc: TTyRichDocument; AIndex: Integer; var AWidth, APPI: Integer;
      var AZoom: Single);
    function CacheHit(AIndex, AWidth, APPI: Integer; AZoom: Single;
      ARow: Boolean): TTyBlockLayout;
  protected
    { Fonts and measuring, for the layouts this layouter makes. }
    function FormatFont(AFormat: TTyCharFormatId; APPI: Integer; AZoom: Single): TTyRichFormatFont;
    function GlyphIn(AFont: TTyRichFontId; ACode: Cardinal): Boolean;
    function FallbackFor(AFont: TTyRichFontId; ACode: Cardinal): TTyRichFontId;
    { The number list item AIndex (in AList, its own list format) shows: its place among the
      consecutive items of its level and kind before it - an item of a deeper level is passed
      over; a shallower one, another kind on the level or a paragraph that is no list item
      ends the list - counted from the StartAt of the list's first item. Looks back at most
      CRichListWalkParas paragraphs (see there), inside one read scope, each paragraph's
      value read without a parse when it is parsed already; remembers what it found. 0 for
      a bullet or no list. }
    function ListNumber(ADoc: TTyRichDocument; AIndex: Integer;
      const AList: TTyListFormat): Int64;
    { Decodes an image file's bytes (AJpegScale 1..3: a JPEG at 1/2, 1/4, 1/8 while decoding);
      raises what the decoder raises. A seam for the tests. }
    function DecodeImage(AStream: TStream; AJpegScale: Integer): TBGRABitmap; virtual;
    { AImage reduced to AWidth x AHeight (rfBestQuality); raises what the resampler raises. A
      seam for the tests. }
    function ScaleImage(AImage: TBGRABitmap; AWidth, AHeight: Integer): TBGRABitmap; virtual;
  public
    constructor Create(ADevice: TTyRichTextDevice; AOwnsDevice: Boolean = True);
    destructor Destroy; override;
    { Paragraph AIndex of ADoc laid out at AWidth pixels, APPI and AZoom (1.0 = 100 %).
      AWidth 0 (CRichNoWrap, what TyRichLayoutWidth gives for rwmNone) means no wrapping at
      all - every paragraph one line, the right indent ignored - not a window 0 wide: a
      caller with a client width of 0 passes 1 (TyRichLayoutWidth does). From the cache when
      it holds that paragraph at those values. The result carries a reference for the
      caller: Release it when done. The layouter works for one document at a time, Document:
      a call with another one switches to it through that setter (which empties the caches).
      A paragraph in a table cell is laid out alone here, not as its row; the cache keeps one
      block per first paragraph, so at a row's first paragraph this layout and the row's
      (LayoutBlock) replace each other - a caller that mixes the two lays the whole row out
      again each time. What is shown is asked of LayoutBlock. }
    function LayoutPara(ADoc: TTyRichDocument; AIndex: Integer; AWidth: Integer;
      APPI: Integer; AZoom: Single): TTyParaLayout;
    { The block paragraph AIndex belongs to, with a reference for the caller: a
      TTyRowLayout when the paragraph is in a table cell - its row, whichever of the row's
      paragraphs AIndex is - else its TTyParaLayout. The entry the control uses: the next
      block starts at LastPara + 1. Finding a row's paragraphs reads the row's own and one
      on either side (never the whole table), inside one read scope. AWidth as LayoutPara
      takes it (0: no wrapping; a row's cells wrap at their own widths anyway). }
    function LayoutBlock(ADoc: TTyRichDocument; AIndex: Integer; AWidth: Integer;
      APPI: Integer; AZoom: Single): TTyBlockLayout; virtual;
    { Paragraphs AFirst .. AFirst + ACount - 1 changed: their layouts go (Stale). }
    procedure Invalidate(AFirst, ACount: Integer);
    { The document's change, forwarded by the owner (TTyRichDocument.OnChange): the changed
      paragraphs' layouts go, and those after them follow the paragraphs that came or went
      to their new indexes. }
    procedure DocumentChanged(const AChange: TTyRichChange);
    { Every layout goes (Stale) and every kept measure. }
    procedure Clear;
    { The cached layout of the block that starts at paragraph AIndex, without a reference
      and without counting a hit; nil when there is none. Blocks are kept by their first
      paragraph only: a row is found at its FirstPara, and this is nil for its other
      paragraphs (ask LayoutBlock, which finds the row from any of them). }
    function CachedLayout(AIndex: Integer): TTyBlockLayout;
    { What a paragraph not laid out yet counts as: one line of the base font. }
    function EstimatedParaHeight(APPI: Integer; AZoom: Single): Integer;
    { The advance of AText in AFont, kept by (font, text). }
    function MeasureText(AFont: TTyRichFontId; const AText: UTF8String): Integer;
    property Device: TTyRichTextDevice read FDevice;
    { The document laid out. Setting it - the same document too - empties every cache (the
      layouts go Stale; measures, glyph and fallback answers, list numbers and pictures go):
      a layouter knows its document by being told, never by its address, which a new
      document can share with a freed one. The control sets it when it makes its document
      and whenever it replaces the document or its content; nil lets go of it. }
    property Document: TTyRichDocument read FDoc write SetDocument;
    { The font a character format with no name / no size gets: the control's theme font. }
    property BaseFontName: string read FBaseFontName write SetBaseFontName;
    property BaseFontSizeHalfPt: Integer read FBaseFontSizeHalfPt write SetBaseFontSizeHalfPt;
    { Tried in order for a character the font in effect has no glyph for; the first that
      has it is used. Starts as the platform's list; change it freely. Changing the list, or
      naming another OnFallbackFont (asked first), empties the caches: the fonts found before
      and the layouts made with them go (the decoded pictures, which depend on no font, stay;
      so they do when the base font changes). }
    property FallbackFonts: TStringList read FFallbackFonts;
    property OnFallbackFont: TTyRichFallbackEvent read FOnFallbackFont write SetOnFallbackFont;
    property CacheHits: Int64 read FHits;
    property CacheMisses: Int64 read FMisses;
    function CachedCount: Integer;
    property CachedChars: Int64 read FCachedChars;
    { What the kept advances take (counted as CRichMeasureCacheBytes counts them). }
    function MeasureCacheBytes: Int64;
    { Paragraphs list numbering looked at, for the tests that check it stays bounded. }
    property ListWalkSteps: Int64 read FListWalkSteps;
    { Draws APicture into ABox of ATarget (the target's pixels, its ClipRect respected): its
      image - decoded the first time the picture is drawn (never at layout); at its own size
      as it is; reduced once per size and kept (the full image then let go, decoded again
      only for a size that needs it); enlarged - or reduced past CRichPictureMaxScaledPixels -
      straight from the decoded image for the part inside the clip, with no copy kept - or,
      for a picture that cannot be shown (a metafile that is not one bitmap, an unknown
      format, no bytes, a header that says more than CRichPictureMaxPixels pixels and is not
      a JPEG that decodes reduced within them, bytes that do not decode, a reduction that
      failed at this size), a placeholder: the box filled and framed ALinePx thick. Never
      raises for what a picture's bytes are (EAccessViolation and EOutOfMemory are let
      through). True when the image was drawn. The kept pictures are held by a counted
      reference until they leave the cache (Clear empties it). }
    function DrawPicture(ATarget: TBGRABitmap; APicture: TTyRichPicture; const ABox: TRect;
      ALinePx: Integer; const AStyle: TTyRichPaintStyle): Boolean;
    { A paint of the control begins: the pictures it draws (and those prepared until the next
      call) are one pass, and no picture used in the current pass leaves the cache for space
      - so the pictures of one screen never evict each other, whatever they take together.
      The control calls it once per paint. Until it is first called, each outermost Paint (a
      DrawPicture or PreparePicture outside one) is a pass by itself. }
    procedure BeginPaintPass;
    { Bytes the decoded pictures may hold (CRichPictureCacheBytes to start with), past what
      the current paint pass uses. }
    property PictureCacheLimit: Int64 read FPictureLimit write SetPictureLimit;
    property PictureCacheBytes: Int64 read FPictureBytes;
    function PictureCacheCount: Integer;
    { Decodes tried (a header read counts) and reductions made; pixels the decoders made. For
      the tests that check when that happens. }
    property PictureDecodes: Int64 read FPictureDecodes;
    property PictureScales: Int64 read FPictureScales;
    property PictureDecodedPixels: Int64 read FPictureDecodedPixels;
    { The pixel budgets (CRichPictureMaxPixels, CRichPictureMaxScaledPixels to start with),
      settable for tests. }
    property PictureDecodeBudget: Int64 read FPictureDecodeBudget write FPictureDecodeBudget;
    property PictureScaleBudget: Int64 read FPictureScaleBudget write FPictureScaleBudget;
    { Drawing APicture in a box of AWidth x AHeight now would neither decode nor resample: its
      image is kept at that size, or it is drawn from the kept decoded image (its own size, an
      enlargement), or it has been tried and cannot be shown there (a failed decode, a failed
      reduction, over the budget: the placeholder is what is drawn). False when a decode is
      needed - never tried, or the full image was let go after a reduction and this size needs
      it again - or a reduction to this size. Asking changes nothing. }
    function PictureReady(APicture: TTyRichPicture; AWidth, AHeight: Integer): Boolean;
    { Brings APicture to what PictureReady calls ready for AWidth x AHeight - decoded,
      reduced, or found that it cannot be (remembered) - without drawing it. Afterwards
      PictureReady(APicture, AWidth, AHeight) is True. }
    procedure PreparePicture(APicture: TTyRichPicture; AWidth, AHeight: Integer);
    { The pictures paints with DeferPictures passed over since the last call, in the order they
      were met (each with a reference the caller releases); the list starts empty again. }
    function TakeSkippedPictures: TTyRichSkippedPictures;
    property SkippedPictureCount: Integer read FSkippedCount;
  end;

{ The width LayoutPara takes for a wrap mode: rwmWindow AAvailWidth (at least 1), rwmPage
  the document's text width at APPI and AZoom, rwmNone CRichNoWrap. }
function TyRichLayoutWidth(AMode: TTyRichWrapMode; AAvailWidth: Integer;
  ADoc: TTyRichDocument; APPI: Integer; AZoom: Single): Integer;
{ A length in twips as pixels at APPI and AZoom, saturating at +-CRichMaxLengthPx (never
  wrapping). }
function TyRichTwipsToPx(ATwips: Int64; APPI: Integer; AZoom: Single): Integer;
{ The font size of a character format in pixels (half-points at APPI and AZoom), from 1 to
  CRichMaxFontPx. }
function TyRichHalfPointsToPx(AHalfPt: Integer; APPI: Integer; AZoom: Single): Integer;
{ A pixel length clamped to +-CRichMaxLengthPx: the one helper for a size that does not come
  through TyRichTwipsToPx. }
function TyRichClampPx(APx: Int64): Integer;
function TyRichIsKinsokuNoLineStart(ACode: Cardinal): Boolean;
function TyRichIsKinsokuNoLineEnd(ACode: Cardinal): Boolean;
{ A code point that belongs to the cluster before it: a combining mark, a variation
  selector, a joiner, an emoji modifier or tag. }
function TyRichIsClusterExtend(ACode: Cardinal): Boolean;
{ The platform's fallback candidates (the plan's lists). }
procedure TyRichDefaultFallbackFonts(AList: TStrings);
{ The code points a font's cmap table (its bytes, as GetFontData gives them) maps to glyphs -
  what the real device reads on Windows: the format 12 subtable, else format 4, else the
  symbol one (ASymbol: codes sit at U+F000 + byte). Every count in the table is bounded by
  what the table can hold, so a malformed one costs what its size costs: ASteps counts the
  records and codes looked at. }
function TyRichReadCmapTable(const ATable: TBytes; out ASymbol: Boolean;
  out ASteps: Int64): TTyRichCodeRanges;
{ What a list item's marker reads: a bullet by level (U+2022, U+25E6, U+25AA, over again from
  level 3), or ANumber followed by a full stop - 1, 2, 3; a, b, ... z, aa, ab (letters go on
  in base 26 with no zero); i, ii, ... (roman up to 3999). A number the kind cannot write
  (below 1, or past 3999 in roman) is written in digits. '' for no list. }
function TyRichListMarkerText(AKind: TTyListKind; ALevel: Integer; ANumber: Int64): UTF8String;
{ Black text, a blue selection with white text, grey placeholders and table lines: what a
  test or a probe paints with when it has no theme. }
function TyRichDefaultPaintStyle: TTyRichPaintStyle;

implementation

uses
  Math, LCLType, LCLIntf, BGRAReadPng, BGRAReadJpeg, BGRAReadBMP, tyControls.Types,
  tyControls.FontUnits, tyControls.Painter, tyControls.StrConsts;

const
  ckText = 0;
  ckSpace = 1;
  ckTab = 2;
  ckBreak = 3;
  ckObject = 4;
  ckInvalid = 5;
  ckInvalid2 = 6;

  CUnlimited = MaxInt div 4;
  { What a kept advance costs besides its key's characters: the key's string header and the
    dictionary's slot (hash, key, value). }
  CMeasureEntryBytes = 48;
  // U+FFFD in UTF-8
  CReplacement: UTF8String = #$EF#$BF#$BD;

{ ---- characters ---- }

{ The length of the valid UTF-8 sequence at P, or 1 when the byte there starts none - the
  text storage's rule (tyControls.RichEdit.Text), so a paragraph decodes into exactly the
  characters positions count. }
function SeqLen(P: PByte; AAvail: PtrInt): Integer; inline;
var
  b0, b1: Byte;
begin
  b0 := P^;
  if b0 < $C2 then Exit(1);
  if b0 < $E0 then
  begin
    if (AAvail >= 2) and (P[1] and $C0 = $80) then Exit(2);
    Exit(1);
  end;
  if b0 < $F0 then
  begin
    if AAvail < 3 then Exit(1);
    b1 := P[1];
    if (b1 and $C0 <> $80) or (P[2] and $C0 <> $80) then Exit(1);
    if (b0 = $E0) and (b1 < $A0) then Exit(1);
    if (b0 = $ED) and (b1 > $9F) then Exit(1);
    Exit(3);
  end;
  if b0 < $F5 then
  begin
    if AAvail < 4 then Exit(1);
    b1 := P[1];
    if (b1 and $C0 <> $80) or (P[2] and $C0 <> $80) or (P[3] and $C0 <> $80) then Exit(1);
    if (b0 = $F0) and (b1 < $90) then Exit(1);
    if (b0 = $F4) and (b1 > $8F) then Exit(1);
    Exit(4);
  end;
  Result := 1;
end;

{ The code point of the sequence of ALen bytes at P (ALen from SeqLen, and a valid one). }
function CodeOf(P: PByte; ALen: Integer): Cardinal; inline;
begin
  case ALen of
    1: Result := P^;
    2: Result := (Cardinal(P[0] and $1F) shl 6) or (P[1] and $3F);
    3: Result := (Cardinal(P[0] and $0F) shl 12) or (Cardinal(P[1] and $3F) shl 6) or (P[2] and $3F);
  else
    Result := (Cardinal(P[0] and $07) shl 18) or (Cardinal(P[1] and $3F) shl 12) or
      (Cardinal(P[2] and $3F) shl 6) or (P[3] and $3F);
  end;
end;

{ The code point at byte AByte of S (1-based) and the bytes it takes; an invalid byte is
  U+FFFD of one byte. }
function DecodeAt(const S: RawByteString; AByte: Integer; out ACode: Cardinal): Integer; inline;
var
  p: PByte;
begin
  p := PByte(@S[AByte]);
  if p^ < $80 then
  begin
    ACode := p^;
    Exit(1);
  end;
  Result := SeqLen(p, System.Length(S) - AByte + 1);
  if (Result = 1) then ACode := $FFFD else ACode := CodeOf(p, Result);
end;

function TyRichIsClusterExtend(ACode: Cardinal): Boolean;
begin
  if ACode < $0300 then Exit(False);
  Result :=
    ((ACode >= $0300) and (ACode <= $036F)) or
    ((ACode >= $0483) and (ACode <= $0489)) or
    ((ACode >= $0591) and (ACode <= $05BD)) or
    ((ACode >= $0610) and (ACode <= $061A)) or
    ((ACode >= $064B) and (ACode <= $065F)) or (ACode = $0670) or
    ((ACode >= $0900) and (ACode <= $0903)) or
    ((ACode >= $093A) and (ACode <= $094F) and (ACode <> $093D)) or
    ((ACode >= $0951) and (ACode <= $0957)) or ((ACode >= $0962) and (ACode <= $0963)) or
    (ACode = $0E31) or ((ACode >= $0E34) and (ACode <= $0E3A)) or
    ((ACode >= $0E47) and (ACode <= $0E4E)) or
    ((ACode >= $1160) and (ACode <= $11FF)) or
    ((ACode >= $1AB0) and (ACode <= $1AFF)) or
    ((ACode >= $1DC0) and (ACode <= $1DFF)) or
    (ACode = $200C) or (ACode = $200D) or
    ((ACode >= $20D0) and (ACode <= $20FF)) or
    ((ACode >= $302A) and (ACode <= $302F)) or
    ((ACode >= $3099) and (ACode <= $309A)) or
    ((ACode >= $FE00) and (ACode <= $FE0F)) or
    ((ACode >= $FE20) and (ACode <= $FE2F)) or
    ((ACode >= $1F3FB) and (ACode <= $1F3FF)) or
    ((ACode >= $E0020) and (ACode <= $E007F)) or
    ((ACode >= $E0100) and (ACode <= $E01EF));
end;

function IsRegional(ACode: Cardinal): Boolean; inline;
begin
  Result := (ACode >= $1F1E6) and (ACode <= $1F1FF);
end;

function IsEmoji(ACode: Cardinal): Boolean; inline;
begin
  Result := ((ACode >= $1F000) and (ACode <= $1FAFF)) or
    ((ACode >= $2600) and (ACode <= $27BF)) or ((ACode >= $2B00) and (ACode <= $2BFF));
end;

{ Text that breaks between any two of its characters: CJK, and emoji. }
function IsIdeographic(ACode: Cardinal): Boolean; inline;
begin
  Result := TyIsCJKCodepoint(ACode) or IsEmoji(ACode);
end;

type
  TCodeList = array of Cardinal;

var
  GNoStart, GNoEnd: TCodeList;
  GKinsokuReady: Boolean = False;

procedure SortCodes(var A: TCodeList);
var
  i, j: Integer;
  t: Cardinal;
begin
  for i := 1 to High(A) do
  begin
    t := A[i];
    j := i - 1;
    while (j >= 0) and (A[j] > t) do
    begin
      A[j + 1] := A[j];
      Dec(j);
    end;
    A[j + 1] := t;
  end;
end;

function SortedCodes(const A: array of Cardinal): TCodeList;
var
  i: Integer;
begin
  Result := nil;
  SetLength(Result, Length(A));
  for i := 0 to High(A) do Result[i] := A[i];
  SortCodes(Result);
end;

procedure KinsokuReady;
begin
  if GKinsokuReady then Exit;
  GNoStart := SortedCodes(CRichKinsokuNoLineStart);
  GNoEnd := SortedCodes(CRichKinsokuNoLineEnd);
  GKinsokuReady := True;
end;

function InCodes(const A: TCodeList; ACode: Cardinal): Boolean;
var
  lo, hi, mid: Integer;
begin
  lo := 0;
  hi := High(A);
  while lo <= hi do
  begin
    mid := (lo + hi) div 2;
    if A[mid] = ACode then Exit(True);
    if A[mid] < ACode then lo := mid + 1 else hi := mid - 1;
  end;
  Result := False;
end;

function TyRichIsKinsokuNoLineStart(ACode: Cardinal): Boolean;
begin
  KinsokuReady;
  Result := InCodes(GNoStart, ACode);
end;

function TyRichIsKinsokuNoLineEnd(ACode: Cardinal): Boolean;
begin
  KinsokuReady;
  Result := InCodes(GNoEnd, ACode);
end;

{ Whether a line may break between two text clusters whose base characters are APrev and
  ACur: never before a closing mark or after an opening one (kinsoku), else beside CJK and
  emoji. The one rule both the line breaker and a fragment cut into segments (a justified
  line stretched between its characters) apply, so the two always find the same places. }
function TextBreakBetween(APrev, ACur: Cardinal): Boolean;
begin
  Result := not TyRichIsKinsokuNoLineStart(ACur) and not TyRichIsKinsokuNoLineEnd(APrev) and
    (IsIdeographic(APrev) or IsIdeographic(ACur));
end;

{ The characters of S as the text storage counts them. }
function CharCountOf(const S: RawByteString): Integer;
var
  i: Integer;
  c: Cardinal;
begin
  Result := 0;
  i := 1;
  while i <= System.Length(S) do
  begin
    Inc(i, DecodeAt(S, i, c));
    Inc(Result);
  end;
end;

procedure TyRichDefaultFallbackFonts(AList: TStrings);
begin
  AList.Clear;
  {$IF DEFINED(MSWINDOWS)}
  // 微软雅黑 and 宋体 by their English family names, which GDI matches whatever the
  // system's language
  AList.Add('Microsoft YaHei');
  AList.Add('SimSun');
  AList.Add('SimSun-ExtB');
  AList.Add('Segoe UI Emoji');
  AList.Add('Segoe UI Symbol');
  {$ELSEIF DEFINED(DARWIN)}
  AList.Add('PingFang SC');
  AList.Add('Hiragino Sans GB');
  AList.Add('Apple Color Emoji');
  {$ELSE}
  AList.Add('Noto Sans CJK SC');
  AList.Add('WenQuanYi Micro Hei');
  AList.Add('Noto Color Emoji');
  {$ENDIF}
end;

{ ---- units ---- }

function TyRichClampPx(APx: Int64): Integer;
begin
  if APx > CRichMaxLengthPx then Exit(CRichMaxLengthPx);
  if APx < -CRichMaxLengthPx then Exit(-CRichMaxLengthPx);
  Result := APx;
end;

function TyRichTwipsToPx(ATwips: Int64; APPI: Integer; AZoom: Single): Integer;
var
  d: Double;
begin
  // saturated in floating point, before Round (which would raise past Int64)
  d := ATwips * Double(APPI) * Double(AZoom) / 1440;
  if d >= CRichMaxLengthPx then Exit(CRichMaxLengthPx);
  if d <= -CRichMaxLengthPx then Exit(-CRichMaxLengthPx);
  if not (Abs(d) < CRichMaxLengthPx) then Exit(0);   // NaN
  Result := Round(d);
end;

function TyRichHalfPointsToPx(AHalfPt: Integer; APPI: Integer; AZoom: Single): Integer;
var
  d: Double;
begin
  d := AHalfPt * Double(APPI) * Double(AZoom) / 144;
  if d >= CRichMaxFontPx then Exit(CRichMaxFontPx);
  if not (d >= 1) then Exit(1);   // NaN too
  Result := Max(1, Round(d));
end;

{ A + B, stopping at CRichMaxBlockPx (B is never negative here). }
function SatAdd(A, B: Integer): Integer; inline;
begin
  Result := Integer(Min(Int64(A) + B, Int64(CRichMaxBlockPx)));
end;

function TyRichLayoutWidth(AMode: TTyRichWrapMode; AAvailWidth: Integer;
  ADoc: TTyRichDocument; APPI: Integer; AZoom: Single): Integer;
begin
  case AMode of
    rwmWindow: Result := Max(1, AAvailWidth);
    rwmPage: Result := Max(1, TyRichTwipsToPx(Int64(ADoc.PaperWidth) - ADoc.MarginLeft -
      ADoc.MarginRight, APPI, AZoom));
  else
    Result := CRichNoWrap;
  end;
end;

{ ---- list markers ---- }

function TyRichListMarkerText(AKind: TTyListKind; ALevel: Integer; ANumber: Int64): UTF8String;
const
  // U+2022, U+25E6, U+25AA in UTF-8 (the library keeps no non-ASCII literal in source/)
  Bullets: array[0..2] of UTF8String = (#$E2#$80#$A2, #$E2#$97#$A6, #$E2#$96#$AA);
  RomanValue: array[0..12] of Integer = (1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1);
  RomanText: array[0..12] of string = ('m', 'cm', 'd', 'cd', 'c', 'xc', 'l', 'xl', 'x', 'ix',
    'v', 'iv', 'i');
var
  n: QWord;
  i: Integer;
  s: string;
begin
  case AKind of
    lkNone: Exit('');
    lkBullet: Exit(Bullets[Abs(ALevel) mod 3]);
  end;
  s := '';
  if (ANumber >= 1) and (AKind in [lkLowerAlpha, lkUpperAlpha]) then
  begin
    // base 26 with no zero: 26 is z, 27 aa - at most 14 letters for the largest Int64
    n := QWord(ANumber);
    while n > 0 do
    begin
      Dec(n);
      s := Chr(Ord('a') + Integer(n mod 26)) + s;
      n := n div 26;
    end;
  end
  else if (ANumber >= 1) and (ANumber <= 3999) and (AKind in [lkLowerRoman, lkUpperRoman]) then
  begin
    n := QWord(ANumber);
    for i := 0 to High(RomanValue) do
      while n >= QWord(RomanValue[i]) do
      begin
        s := s + RomanText[i];
        Dec(n, RomanValue[i]);
      end;
  end
  else
    s := IntToStr(ANumber);
  if AKind in [lkUpperAlpha, lkUpperRoman] then s := UpperCase(s);
  Result := s + '.';
end;

{ ---- the device ---- }

constructor TTyRichTextDevice.Create;
begin
  inherited Create;
  FFontIndex := specialize TDictionary<string, Integer>.Create;
end;

destructor TTyRichTextDevice.Destroy;
begin
  FFontIndex.Free;
  inherited Destroy;
end;

procedure TTyRichTextDevice.CheckFont(AFont: TTyRichFontId);
begin
  if (AFont < 0) or (AFont >= FFontCount) then
    raise EArgumentOutOfRangeException.CreateFmt('no font %d', [AFont]);
end;

function TTyRichTextDevice.ResolveFont(const AName: string; APixelHeight: Integer;
  AStyle: TFontStyles): TTyRichFontId;
var
  key: string;
  st: TFontStyles;
begin
  if APixelHeight < 1 then APixelHeight := 1;
  // the one ceiling every font meets: measuring, metrics and drawing all go by this id
  if APixelHeight > CRichMaxFontPx then APixelHeight := CRichMaxFontPx;
  st := AStyle * [fsBold, fsItalic];
  key := AName + #0 + IntToStr(APixelHeight) + #0 + IntToStr(Ord(fsBold in st)) +
    IntToStr(Ord(fsItalic in st));
  if FFontIndex.TryGetValue(key, Result) then Exit;
  if FFontCount = System.Length(FFonts) then SetLength(FFonts, FFontCount * 2 + 8);
  FFonts[FFontCount].Name := AName;
  FFonts[FFontCount].PixelHeight := APixelHeight;
  FFonts[FFontCount].Style := st;
  FFonts[FFontCount].HasMetrics := False;
  Result := FFontCount;
  Inc(FFontCount);
  FFontIndex.Add(key, Result);
end;

function TTyRichTextDevice.FontCount: Integer;
begin
  Result := FFontCount;
end;

function TTyRichTextDevice.FontName(AFont: TTyRichFontId): string;
begin
  CheckFont(AFont);
  Result := FFonts[AFont].Name;
end;

function TTyRichTextDevice.FontPixelHeight(AFont: TTyRichFontId): Integer;
begin
  CheckFont(AFont);
  Result := FFonts[AFont].PixelHeight;
end;

function TTyRichTextDevice.FontStyle(AFont: TTyRichFontId): TFontStyles;
begin
  CheckFont(AFont);
  Result := FFonts[AFont].Style;
end;

function TTyRichTextDevice.Metrics(AFont: TTyRichFontId): TTyRichFontMetrics;
begin
  CheckFont(AFont);
  if not FFonts[AFont].HasMetrics then
  begin
    FFonts[AFont].Metrics := DoMetrics(AFont);
    FFonts[AFont].HasMetrics := True;
  end;
  Result := FFonts[AFont].Metrics;
end;

procedure TTyRichTextDevice.CountMeasure(ACodePoints: Integer);
begin
  Inc(FMeasureCalls);
  Inc(FMeasuredChars, ACodePoints);
end;

function TTyRichTextDevice.TextWidth(AFont: TTyRichFontId; const AText: UTF8String): Integer;
begin
  CheckFont(AFont);
  if AText = '' then Exit(0);
  CountMeasure(CharCountOf(AText));
  Result := DoTextWidth(AFont, AText);
end;

function TTyRichTextDevice.DoFitCount(AFont: TTyRichFontId; const AText: UTF8String;
  AMaxWidth: Integer): Integer;
var
  bytes: array of Integer;
  n, i, lo, hi, mid: Integer;
  c: Cardinal;
begin
  bytes := nil;
  SetLength(bytes, System.Length(AText) + 1);
  n := 0;
  i := 1;
  while i <= System.Length(AText) do
  begin
    Inc(i, DecodeAt(AText, i, c));
    Inc(n);
    bytes[n] := i - 1;
  end;
  lo := 0;
  hi := n;
  while lo < hi do
  begin
    mid := (lo + hi + 1) div 2;
    CountMeasure(mid);
    if DoTextWidth(AFont, Copy(AText, 1, bytes[mid])) <= AMaxWidth then lo := mid
    else hi := mid - 1;
  end;
  Result := lo;
end;

function TTyRichTextDevice.FitCount(AFont: TTyRichFontId; const AText: UTF8String;
  AMaxWidth: Integer): Integer;
begin
  CheckFont(AFont);
  if (AText = '') or (AMaxWidth < 0) then Exit(0);
  Result := DoFitCount(AFont, AText, AMaxWidth);
end;

function TTyRichTextDevice.HasGlyph(AFont: TTyRichFontId; ACode: Cardinal): Boolean;
begin
  CheckFont(AFont);
  Inc(FGlyphQueries);
  Result := DoHasGlyph(AFont, ACode);
end;

procedure TTyRichTextDevice.DrawText(ATarget: TBGRABitmap; AFont: TTyRichFontId;
  AX, ABaseline: Integer; const AText: UTF8String; AColor: TBGRAPixel);
begin
  CheckFont(AFont);
  if AText = '' then Exit;
  Inc(FDrawCalls);
  DoDrawText(ATarget, AFont, AX, ABaseline, AText, AColor);
end;

procedure TTyRichTextDevice.ResetCounters;
begin
  FMeasureCalls := 0;
  FMeasuredChars := 0;
  FGlyphQueries := 0;
  FDrawCalls := 0;
end;

{ ---- the real device: which glyphs a font has ---- }

type
  { The code points a font maps to a glyph, as inclusive ranges sorted by start. }
  TTyGlyphRanges = class
  public
    Starts, Ends: array of Cardinal;
    Count: Integer;
    Symbol: Boolean;     // a symbol font: its codes sit at U+F000 + byte
    procedure Add(AFrom, ATo: Cardinal);
    function Has(ACode: Cardinal): Boolean;
  end;

procedure TTyGlyphRanges.Add(AFrom, ATo: Cardinal);
begin
  if (Count > 0) and (AFrom <= Ends[Count - 1] + 1) and (AFrom >= Starts[Count - 1]) then
  begin
    if ATo > Ends[Count - 1] then Ends[Count - 1] := ATo;
    Exit;
  end;
  if Count = System.Length(Starts) then
  begin
    SetLength(Starts, Count * 2 + 16);
    SetLength(Ends, Count * 2 + 16);
  end;
  Starts[Count] := AFrom;
  Ends[Count] := ATo;
  Inc(Count);
end;

function TTyGlyphRanges.Has(ACode: Cardinal): Boolean;
var
  lo, hi, mid: Integer;
begin
  if Symbol and (ACode < $100) then ACode := ACode + $F000;
  lo := 0;
  hi := Count - 1;
  while lo <= hi do
  begin
    mid := (lo + hi) div 2;
    if ACode < Starts[mid] then hi := mid - 1
    else if ACode > Ends[mid] then lo := mid + 1
    else Exit(True);
  end;
  Result := False;
end;

{$IFDEF MSWINDOWS}
function TyCreateCompatibleDC(ADC: PtrUInt): PtrUInt; stdcall;
  external 'gdi32' name 'CreateCompatibleDC';
function TyDeleteDC(ADC: PtrUInt): LongBool; stdcall; external 'gdi32' name 'DeleteDC';
function TyCreateFontW(AHeight, AWidth, AEscapement, AOrientation, AWeight: LongInt;
  AItalic, AUnderline, AStrikeOut, ACharSet, AOutPrecision, AClipPrecision, AQuality,
  APitchAndFamily: LongWord; AFace: PWideChar): PtrUInt; stdcall;
  external 'gdi32' name 'CreateFontW';
function TySelectObject(ADC, AObject: PtrUInt): PtrUInt; stdcall;
  external 'gdi32' name 'SelectObject';
function TyDeleteObject(AObject: PtrUInt): LongBool; stdcall;
  external 'gdi32' name 'DeleteObject';
function TyGetFontData(ADC: PtrUInt; ATable, AOffset: LongWord; ABuffer: Pointer;
  ALength: LongWord): LongWord; stdcall; external 'gdi32' name 'GetFontData';

{$ENDIF}

function BE16(const B: TBytes; AAt: PtrInt): Cardinal; inline;
begin
  if (AAt < 0) or (AAt + 2 > System.Length(B)) then Exit(0);
  Result := (Cardinal(B[AAt]) shl 8) or B[AAt + 1];
end;

function BE32(const B: TBytes; AAt: PtrInt): Cardinal; inline;
begin
  if (AAt < 0) or (AAt + 4 > System.Length(B)) then Exit(0);
  Result := (Cardinal(B[AAt]) shl 24) or (Cardinal(B[AAt + 1]) shl 16) or
    (Cardinal(B[AAt + 2]) shl 8) or B[AAt + 3];
end;

{ The ranges of a cmap subtable in format 4 (BMP: segments, a glyph per code - a code whose
  glyph is 0 has none) or 12 (all planes: groups). Every count is bounded by what the table
  can hold (no read leaves it either: BE16/BE32), and format 4's codes by the 65,536 the BMP
  has, so a malformed font costs what its size costs; ASteps counts what was looked at. }
procedure ReadCmapSubtable(const B: TBytes; AAt: PtrInt; R: TTyGlyphRanges; var ASteps: Int64);
var
  fmt, segX2, i, nGroups, room: Cardinal;
  endAt, startAt, deltaAt, rangeAt: PtrInt;
  s, e, d, ro, c, g, runStart: Cardinal;
  inRun: Boolean;
  gs, ge, g0: Cardinal;
  budget: Int64;
begin
  fmt := BE16(B, AAt);
  if System.Length(B) - AAt < 16 then Exit;
  room := System.Length(B) - AAt - 16;
  if fmt = 4 then
  begin
    // four arrays of segX2 bytes after a 14-byte header and a pad
    segX2 := BE16(B, AAt + 6);
    if segX2 > room div 4 then segX2 := room div 4;
    endAt := AAt + 14;
    startAt := endAt + segX2 + 2;
    deltaAt := startAt + segX2;
    rangeAt := deltaAt + segX2;
    budget := 65536;
    i := 0;
    while (i < segX2 div 2) and (budget > 0) do
    begin
      Inc(ASteps);
      e := BE16(B, endAt + i * 2);
      s := BE16(B, startAt + i * 2);
      d := BE16(B, deltaAt + i * 2);
      ro := BE16(B, rangeAt + i * 2);
      inRun := False;
      runStart := 0;
      c := s;
      while (c <= e) and (c < $FFFF) and (budget > 0) do
      begin
        Inc(ASteps);
        Dec(budget);
        if ro = 0 then
          g := (c + d) and $FFFF
        else
        begin
          g := BE16(B, rangeAt + i * 2 + ro + (c - s) * 2);
          if g <> 0 then g := (g + d) and $FFFF;
        end;
        if g <> 0 then
        begin
          if not inRun then
          begin
            runStart := c;
            inRun := True;
          end;
        end
        else if inRun then
        begin
          R.Add(runStart, c - 1);
          inRun := False;
        end;
        Inc(c);
      end;
      if inRun then R.Add(runStart, c - 1);
      Inc(i);
    end;
  end
  else if fmt = 12 then
  begin
    // 12 bytes a group after a 16-byte header
    nGroups := BE32(B, AAt + 12);
    if nGroups > room div 12 then nGroups := room div 12;
    i := 0;
    while i < nGroups do
    begin
      Inc(ASteps);
      gs := BE32(B, AAt + 16 + i * 12);
      ge := BE32(B, AAt + 20 + i * 12);
      g0 := BE32(B, AAt + 24 + i * 12);
      if g0 = 0 then Inc(gs);
      if gs <= ge then R.Add(gs, ge);
      Inc(i);
    end;
  end;
end;

{ A font's cmap table: the Unicode subtable in format 12 when there is one, else the BMP one
  in format 4, else the symbol one. nil when it has none of them. The number of encoding
  records is bounded by the table's size. }
function ParseCmap(const B: TBytes; var ASteps: Int64): TTyGlyphRanges;
var
  n, i, plat, enc, off: Cardinal;
  best12, best4, sym: PtrInt;
begin
  Result := nil;
  if System.Length(B) < 4 then Exit;
  n := BE16(B, 2);
  if n > Cardinal(System.Length(B) - 4) div 8 then n := Cardinal(System.Length(B) - 4) div 8;
  best12 := -1;
  best4 := -1;
  sym := -1;
  i := 0;
  while i < n do
  begin
    Inc(ASteps);
    plat := BE16(B, 4 + i * 8);
    enc := BE16(B, 6 + i * 8);
    off := BE32(B, 8 + i * 8);
    Inc(i);
    if off >= Cardinal(System.Length(B)) then Continue;
    case BE16(B, off) of
      12: if ((plat = 3) and (enc = 10)) or (plat = 0) then best12 := off;
      4: if ((plat = 3) and (enc = 1)) or (plat = 0) then best4 := off
         else if (plat = 3) and (enc = 0) then sym := off;
    end;
  end;
  Result := TTyGlyphRanges.Create;
  if best12 >= 0 then ReadCmapSubtable(B, best12, Result, ASteps)
  else if best4 >= 0 then ReadCmapSubtable(B, best4, Result, ASteps)
  else if sym >= 0 then
  begin
    ReadCmapSubtable(B, sym, Result, ASteps);
    Result.Symbol := True;
  end
  else
    FreeAndNil(Result);
end;

function TyRichReadCmapTable(const ATable: TBytes; out ASymbol: Boolean;
  out ASteps: Int64): TTyRichCodeRanges;
var
  r: TTyGlyphRanges;
  i: Integer;
begin
  Result := nil;
  ASymbol := False;
  ASteps := 0;
  r := ParseCmap(ATable, ASteps);
  if r = nil then Exit;
  try
    ASymbol := r.Symbol;
    SetLength(Result, r.Count);
    for i := 0 to r.Count - 1 do
    begin
      Result[i].First := r.Starts[i];
      Result[i].Last := r.Ends[i];
    end;
  finally
    r.Free;
  end;
end;

{$IFDEF MSWINDOWS}
{ The font's cmap, read through GDI (ParseCmap). nil when the font has no cmap (not a
  TrueType or OpenType font). }
function ReadCmap(ADC: PtrUInt): TTyGlyphRanges;
const
  TagCmap = $70616D63;   // 'cmap', as GDI wants the tag: its bytes in file order
  GdiError = $FFFFFFFF;
var
  size: LongWord;
  b: TBytes;
  steps: Int64;
begin
  Result := nil;
  size := TyGetFontData(ADC, TagCmap, 0, nil, 0);
  if (size = GdiError) or (size < 4) then Exit;
  b := nil;
  SetLength(b, size);
  if TyGetFontData(ADC, TagCmap, 0, @b[0], size) = GdiError then Exit;
  steps := 0;
  Result := ParseCmap(b, steps);
end;
{$ENDIF}

type
  { What the real device knows of each face: its glyph ranges (Windows), by font name and
    style. }
  TTyCoverageMap = class
  public
    Map: specialize TDictionary<string, TTyGlyphRanges>;
    constructor Create;
    destructor Destroy; override;
  end;

constructor TTyCoverageMap.Create;
begin
  inherited Create;
  Map := specialize TDictionary<string, TTyGlyphRanges>.Create;
end;

destructor TTyCoverageMap.Destroy;
var
  r: TTyGlyphRanges;
begin
  for r in Map.Values do r.Free;
  Map.Free;
  inherited Destroy;
end;

{ Off Windows: a font is taken to have CJK and emoji glyphs only when its name says it is
  such a font (the platforms' text engines fill other glyphs in by themselves). }
function NameCovers(const AName: string; ACode: Cardinal): Boolean;
const
  CjkWords: array[0..21] of string = ('cjk', 'hei', 'song', 'ming', 'kai', 'pingfang',
    'hiragino', 'wenquanyi', 'yahei', 'simsun', 'gothic', 'mincho', 'source han',
    'droid sans fallback', 'fangsong', 'yuanti', 'noto sans sc', 'noto serif sc', 'gulim',
    'batang', 'dotum', 'malgun');
var
  n: string;
  i: Integer;
begin
  if IsEmoji(ACode) then Exit(Pos('emoji', LowerCase(AName)) > 0);
  if not TyIsCJKCodepoint(ACode) then Exit(True);
  n := LowerCase(AName);
  for i := Low(CjkWords) to High(CjkWords) do
    if Pos(CjkWords[i], n) > 0 then Exit(True);
  Result := False;
end;

constructor TTyRichBgraDevice.Create;
begin
  inherited Create;
  FMeasure := TBGRABitmap.Create(1, 1);
  FMeasureFont := -1;
  FMetricsBmp := TBitmap.Create;
  FMetricsBmp.SetSize(1, 1);
  FCoverage := TTyCoverageMap.Create;
end;

destructor TTyRichBgraDevice.Destroy;
begin
  FCoverage.Free;
  FMetricsBmp.Free;
  FMeasure.Free;
  inherited Destroy;
end;

procedure TTyRichBgraDevice.Configure(ABmp: TBGRABitmap; AFont: TTyRichFontId);
begin
  { TyConfigureTextFont's set-up with the pixel height given outright: a rich text size is
    half-points times PPI times zoom, which the theme's integer size cannot carry. }
  ABmp.FontName := TyEffectiveFontName(FontName(AFont));
  ABmp.FontHeight := FontPixelHeight(AFont);
  ABmp.FontQuality := TyTextFontQuality;
  TyUseTextRenderer(ABmp);
  ABmp.FontStyle := FontStyle(AFont);
end;

function TTyRichBgraDevice.DoMetrics(AFont: TTyRichFontId): TTyRichFontMetrics;
var
  tm: TLCLTextMetric;
begin
  // the measuring font's one set-up, given the pixel height as a px size at 96 PPI
  TyConfigureMeasureFont(FMetricsBmp.Canvas, FontName(AFont),
    TyFontSizeFromPx(FontPixelHeight(AFont)), TyFontWeightWithStyle(400, FontStyle(AFont)), 96);
  Result.Ascent := 0;
  Result.Descent := 0;
  Result.Leading := 0;
  if FMetricsBmp.Canvas.GetTextMetrics(tm) then
  begin
    Result.Ascent := tm.Ascender;
    Result.Descent := tm.Descender;
    Result.Leading := Max(0, tm.Height - tm.Ascender - tm.Descender);
  end;
  if Result.Ascent + Result.Descent <= 0 then
  begin
    // no answer: the em box, four fifths above the baseline
    Result.Ascent := FontPixelHeight(AFont) * 4 div 5;
    Result.Descent := FontPixelHeight(AFont) - Result.Ascent;
  end;
end;

function TTyRichBgraDevice.DoTextWidth(AFont: TTyRichFontId; const AText: UTF8String): Integer;
begin
  if FMeasureFont <> AFont then
  begin
    Configure(FMeasure, AFont);
    FMeasureFont := AFont;
  end;
  Result := FMeasure.TextSize(AText).cx;
end;

{ Windows: the cmap of the face GDI realises for the font's name. Not verified (left from the
  layout review): for a font that is not installed, CreateFontW with DEFAULT_CHARSET realises
  a substitute, and that face's cmap is read - which need not be the face the renderer picks
  for the same name, so a fallback may be taken (or not) for a glyph the drawn face has (or
  lacks). }
function TTyRichBgraDevice.DoHasGlyph(AFont: TTyRichFontId; ACode: Cardinal): Boolean;
{$IFDEF MSWINDOWS}
var
  key: string;
  r: TTyGlyphRanges;
  map: TTyCoverageMap;
  dc, f, old: PtrUInt;
  w: UnicodeString;
  st: TFontStyles;
{$ENDIF}
begin
  {$IFDEF MSWINDOWS}
  map := TTyCoverageMap(FCoverage);
  st := FontStyle(AFont);
  key := LowerCase(TyEffectiveFontName(FontName(AFont))) + '|' + IntToStr(Ord(fsBold in st)) +
    IntToStr(Ord(fsItalic in st));
  if not map.Map.TryGetValue(key, r) then
  begin
    r := nil;
    dc := TyCreateCompatibleDC(0);
    if dc <> 0 then
    try
      w := UnicodeString(TyEffectiveFontName(FontName(AFont)));
      f := TyCreateFontW(-16, 0, 0, 0, IfThen(fsBold in st, 700, 400),
        LongWord(Ord(fsItalic in st)), 0, 0, 1 {DEFAULT_CHARSET}, 0, 0, 0, 0, PWideChar(w));
      if f <> 0 then
      try
        old := TySelectObject(dc, f);
        r := ReadCmap(dc);
        if r = nil then
        begin
          // no cmap: a bitmap font, Latin-1 at most
          r := TTyGlyphRanges.Create;
          r.Add($20, $FF);
        end;
        TySelectObject(dc, old);
      finally
        TyDeleteObject(f);
      end;
    finally
      TyDeleteDC(dc);
    end;
    map.Map.Add(key, r);
  end;
  if r = nil then Exit(True);
  Result := r.Has(ACode);
  {$ELSE}
  Result := NameCovers(TyEffectiveFontName(FontName(AFont)), ACode);
  {$ENDIF}
end;

procedure TTyRichBgraDevice.DoDrawText(ATarget: TBGRABitmap; AFont: TTyRichFontId;
  AX, ABaseline: Integer; const AText: UTF8String; AColor: TBGRAPixel);
begin
  { The same set-up as the measuring bitmap's; the renderer draws with the top of the line
    box at Y, so the baseline lands at Y + the ascent the metrics report. }
  Configure(ATarget, AFont);
  ATarget.TextOut(AX, ABaseline - Metrics(AFont).Ascent, AText, AColor);
end;

{ ---- layouts ---- }

constructor TTyBlockLayout.Create(ALayouter: TTyRichLayouter);
begin
  inherited Create;
  FLayouter := ALayouter;
  FRefCount := 1;
  if ALayouter <> nil then FGen := ALayouter.FChangeGen;
end;

function TTyBlockLayout.GetStale: Boolean;
begin
  Result := FStale or (not FInCache and (FLayouter <> nil) and
    (FGen <> FLayouter.FChangeGen));
end;

procedure TTyBlockLayout.AddRef;
begin
  Inc(FRefCount);
end;

procedure TTyBlockLayout.Release;
begin
  if Self = nil then Exit;
  Dec(FRefCount);
  if FRefCount <= 0 then Free;
end;

function TTyBlockLayout.MemSize: Int64;
begin
  Result := InstanceSize;
end;

function TTyBlockLayout.PosAtPoint(AX, AY: Integer): TTyRichPos;
var
  atEnd: Boolean;
begin
  Result := PosAtPoint(AX, AY, atEnd);
end;

destructor TTyParaLayout.Destroy;
var
  i: Integer;
begin
  for i := 0 to FFragCount - 1 do
    if FFrags[i].Obj <> nil then FFrags[i].Obj.Release;
  inherited Destroy;
end;

function TTyParaLayout.GetLine(AIndex: Integer): TTyRichLine;
begin
  if (AIndex < 0) or (AIndex >= FLineCount) then
    raise EArgumentOutOfRangeException.CreateFmt('no line %d', [AIndex]);
  Result := FLines[AIndex];
end;

function TTyParaLayout.GetFragment(AIndex: Integer): TTyRichFragment;
begin
  if (AIndex < 0) or (AIndex >= FFragCount) then
    raise EArgumentOutOfRangeException.CreateFmt('no fragment %d', [AIndex]);
  Result := FFrags[AIndex];
end;

function TTyParaLayout.FragmentText(AIndex: Integer): UTF8String;
var
  f: TTyRichFragment;
begin
  f := GetFragment(AIndex);
  case f.Kind of
    rfkText, rfkSpace: Result := Copy(FText, f.ByteStart + 1, f.ByteLen);
    rfkObject, rfkReplacement: Result := f.Text;
  else
    Result := '';
  end;
end;

function TTyParaLayout.MemSize: Int64;
var
  i: Integer;
begin
  Result := inherited MemSize + System.Length(FText) +
    Int64(System.Length(FLines)) * SizeOf(TTyRichLine) +
    Int64(System.Length(FFrags)) * SizeOf(TTyRichFragment);
  for i := 0 to FFragCount - 1 do Inc(Result, System.Length(FFrags[i].Text));
end;

function TTyParaLayout.ByteOfChar(const F: TTyRichFragment; AChars: Integer): Integer;
var
  i, stop: Integer;
  c: Cardinal;
begin
  i := F.ByteStart + 1;
  stop := F.ByteStart + F.ByteLen;
  while (AChars > 0) and (i <= stop) do
  begin
    Inc(i, DecodeAt(FText, i, c));
    Dec(AChars);
  end;
  Result := i - 1 - F.ByteStart;
end;

{ AChars inside a text fragment moved back to the start of its cluster. }
function TTyParaLayout.SnapToCluster(const F: TTyRichFragment; AChars: Integer): Integer;
var
  i, k, len, lastStart: Integer;
  c, prev: Cardinal;
  riOdd, start: Boolean;
begin
  if (F.Kind <> rfkText) or (AChars <= 0) or (AChars >= F.Count) then Exit(AChars);
  i := F.ByteStart + 1;
  k := 0;
  lastStart := 0;
  prev := 0;
  riOdd := False;
  while k <= AChars do
  begin
    len := DecodeAt(FText, i, c);
    if k = 0 then start := True
    else start := not (TyRichIsClusterExtend(c) or (prev = $200D) or
      (IsRegional(c) and IsRegional(prev) and riOdd));
    if IsRegional(c) then riOdd := start else riOdd := False;
    if start then lastStart := k;
    prev := c;
    Inc(i, len);
    Inc(k);
  end;
  Result := lastStart;
end;

{ Where the segments of a fragment cut at its break opportunities (StretchGaps > 0) start, as
  characters from its first, the fragment's end last (so segment s is [Result[s],
  Result[s + 1])); ABytes the same as bytes from its ByteStart. A segment starts at a cluster
  start where TextBreakBetween allows a break - the line breaker's rule for two text
  characters, which is what made the pieces the line was built of. }
function TTyParaLayout.SegmentStarts(const F: TTyRichFragment;
  out ABytes: TIntegerDynArray): TIntegerDynArray;
var
  i, k, n, len: Integer;
  c, prev, base: Cardinal;
  riOdd, start: Boolean;
begin
  Result := nil;
  ABytes := nil;
  SetLength(Result, F.Count + 1);
  SetLength(ABytes, F.Count + 1);
  n := 0;
  i := F.ByteStart + 1;
  prev := 0;
  base := 0;
  riOdd := False;
  for k := 0 to F.Count - 1 do
  begin
    len := DecodeAt(FText, i, c);
    if k = 0 then start := True
    else start := not (TyRichIsClusterExtend(c) or (prev = $200D) or
      (IsRegional(c) and IsRegional(prev) and riOdd));
    if IsRegional(c) then riOdd := start else riOdd := False;
    if start then
    begin
      if (k = 0) or TextBreakBetween(base, c) then
      begin
        Result[n] := k;
        ABytes[n] := i - 1 - F.ByteStart;
        Inc(n);
      end;
      base := c;
    end;
    prev := c;
    Inc(i, len);
  end;
  Result[n] := F.Count;
  ABytes[n] := F.ByteLen;
  SetLength(Result, n + 1);
  SetLength(ABytes, n + 1);
end;

function TTyParaLayout.SegmentWidth(const F: TTyRichFragment; const ABytes: TIntegerDynArray;
  ASeg: Integer): Integer;
begin
  Result := FLayouter.MeasureText(F.Font, Copy(FText, F.ByteStart + 1 + ABytes[ASeg],
    ABytes[ASeg + 1] - ABytes[ASeg]));
end;

{ What the stretch of a fragment cut into segments adds before its segment ASeg. }
function StretchBefore(const F: TTyRichFragment; ASeg: Integer): Integer; inline;
begin
  if (F.StretchGaps <= 0) or (ASeg <= 0) then Exit(0);
  Result := Int64(F.Stretch) * (F.StretchFirst + ASeg) div F.StretchGaps -
    Int64(F.Stretch) * F.StretchFirst div F.StretchGaps;
end;

function TTyParaLayout.PrefixWidth(const F: TTyRichFragment; AChars: Integer): Integer;
var
  starts, bytes: TIntegerDynArray;
  s: Integer;
begin
  if AChars <= 0 then Exit(0);
  if AChars >= F.Count then Exit(F.Width);
  case F.Kind of
    rfkText:
      if F.StretchGaps > 0 then
      begin
        // the whole segments before AChars, then a prefix of the one it is in, then the gaps
        starts := SegmentStarts(F, bytes);
        Result := 0;
        s := 0;
        while starts[s + 1] <= AChars do
        begin
          Inc(Result, SegmentWidth(F, bytes, s));
          Inc(s);
        end;
        if AChars > starts[s] then
          Inc(Result, FLayouter.MeasureText(F.Font, Copy(FText, F.ByteStart + 1 + bytes[s],
            ByteOfChar(F, AChars) - bytes[s])));
        Inc(Result, StretchBefore(F, s));
      end
      else
        Result := FLayouter.MeasureText(F.Font, Copy(FText, F.ByteStart + 1, ByteOfChar(F, AChars)));
    rfkSpace:
      if F.Width = F.Natural then
        Result := FLayouter.MeasureText(F.Font, Copy(FText, F.ByteStart + 1, ByteOfChar(F, AChars)))
      else
        Result := Int64(F.Width) * AChars div F.Count;
  else
    // a replacement pair: the first character has the advance, the second none
    Result := F.Width;
  end;
end;

function TTyParaLayout.LineOfPos(APos: TTyRichPos; AAtLineEnd: Boolean): Integer;
var
  lo, hi, mid: Integer;
begin
  if FLineCount <= 1 then Exit(0);
  lo := 0;
  hi := FLineCount - 1;
  while lo < hi do
  begin
    mid := (lo + hi + 1) div 2;
    if FLines[mid].First <= APos then lo := mid else hi := mid - 1;
  end;
  // the end of the line before, which wrapped here (a U+000B before is a character of its own)
  if AAtLineEnd and (lo > 0) and (FLines[lo].First = APos) and not FLines[lo - 1].Forced then
    Dec(lo);
  Result := lo;
end;

function TTyParaLayout.LineAtY(AY: Integer): Integer;
var
  lo, hi, mid: Integer;
begin
  lo := 0;
  hi := FLineCount - 1;
  while lo < hi do
  begin
    mid := (lo + hi) div 2;
    if FLines[mid].Top + FLines[mid].Height > AY then hi := mid else lo := mid + 1;
  end;
  Result := lo;
end;

function TTyParaLayout.XInLine(ALine: Integer; APos: Integer): Integer;
var
  i: Integer;
  f: ^TTyRichFragment;
begin
  with FLines[ALine] do
  begin
    for i := FirstFrag to FirstFrag + FragCount - 1 do
    begin
      f := @FFrags[i];
      if APos <= f^.First then Exit(f^.X);
      if APos < f^.First + f^.Count then
        Exit(f^.X + PrefixWidth(f^, SnapToCluster(f^, APos - f^.First)));
    end;
    Result := EndX;
  end;
end;

{ The caret place inside F nearest to AX (characters from F.First); a tie goes to the
  earlier place. }
function TTyParaLayout.NearestInFragment(const F: TTyRichFragment; AX: Integer): Integer;
var
  offs: array of Integer;
  n, i, k, len, lo, hi, mid, dx, wl, wh: Integer;
  c, prev: Cardinal;
  riOdd, start: Boolean;
begin
  dx := AX - F.X;
  case F.Kind of
    rfkText: ;
    rfkSpace:
      begin
        if F.Width <= 0 then Exit(0);
        Result := (dx * F.Count * 2 + F.Width) div (F.Width * 2);
        if Result < 0 then Result := 0;
        if Result > F.Count then Result := F.Count;
        if F.Width = F.Natural then
        begin
          // natural spaces: measured, not proportional
          lo := Max(0, Result - 1);
          hi := Min(F.Count, Result + 1);
          Result := lo;
          wl := Abs(PrefixWidth(F, lo) - dx);
          for i := lo + 1 to hi do
          begin
            wh := Abs(PrefixWidth(F, i) - dx);
            if wh < wl then
            begin
              wl := wh;
              Result := i;
            end;
          end;
        end;
        Exit;
      end;
  else
    // atomic: one edge or the other
    if dx * 2 > F.Width then Exit(F.Count) else Exit(0);
  end;
  // the cluster starts of a text fragment
  offs := nil;
  SetLength(offs, F.Count + 1);
  n := 0;
  i := F.ByteStart + 1;
  prev := 0;
  riOdd := False;
  for k := 0 to F.Count - 1 do
  begin
    len := DecodeAt(FText, i, c);
    if k = 0 then start := True
    else start := not (TyRichIsClusterExtend(c) or (prev = $200D) or
      (IsRegional(c) and IsRegional(prev) and riOdd));
    if IsRegional(c) then riOdd := start else riOdd := False;
    if start then
    begin
      offs[n] := k;
      Inc(n);
    end;
    prev := c;
    Inc(i, len);
  end;
  offs[n] := F.Count;
  // offs[0..n]: widths grow with them; find the two around dx
  if dx <= 0 then Exit(0);
  if dx >= F.Width then Exit(F.Count);
  lo := 0;
  hi := n;
  while hi - lo > 1 do
  begin
    mid := (lo + hi) div 2;
    if PrefixWidth(F, offs[mid]) <= dx then lo := mid else hi := mid;
  end;
  wl := dx - PrefixWidth(F, offs[lo]);
  wh := PrefixWidth(F, offs[hi]) - dx;
  if wh < wl then Result := offs[hi] else Result := offs[lo];
end;

{ The caret place on line ALine nearest to AX. }
function TTyParaLayout.PointInLine(ALine, AX: Integer): Integer;
var
  i, x0, x1: Integer;
  f: ^TTyRichFragment;
begin
  with FLines[ALine] do
  begin
    if FragCount = 0 then Exit(First);
    for i := FirstFrag to FirstFrag + FragCount - 1 do
    begin
      f := @FFrags[i];
      x0 := f^.X;
      x1 := f^.X + f^.Width;
      // before this fragment, in a gap (justification) or left of the line: its start,
      // the one caret place there is
      if AX < x0 then Exit(f^.First);
      // a fragment with no width (U+000B, a tab with nothing to fill) has its one edge
      if x1 = x0 then
      begin
        if AX = x0 then Exit(f^.First);
        Continue;
      end;
      if AX <= x1 then Exit(f^.First + NearestInFragment(f^, AX));
    end;
    // past the end of a line that U+000B ended: before the U+000B, which is still this
    // line's; past a wrapped line: its end, which is where the next line starts
    Result := First + Count - Ord(Forced);
  end;
end;

function TTyParaLayout.PosAtPoint(AX, AY: Integer; out AAtLineEnd: Boolean): TTyRichPos;
var
  ln: Integer;
begin
  // the line saying what a cut paragraph does not show has no positions: the cut
  if FTruncated and (AY >= FNoticeTop) then
  begin
    AAtLineEnd := False;
    Exit(FShown);
  end;
  ln := LineAtY(AY);
  Result := PointInLine(ln, AX);
  // the end of a line that wraps is also the next line's start: say which one was meant
  with FLines[ln] do
    AAtLineEnd := (ln < FLineCount - 1) and not Forced and (Result = First + Count);
end;

function TTyParaLayout.CaretRect(APos: TTyRichPos; AAtLineEnd: Boolean): TRect;
var
  ln, x: Integer;
begin
  if APos < 0 then APos := 0;
  // past a cut paragraph's cut: at the cut
  if APos > FShown then APos := FShown;
  ln := LineOfPos(APos, AAtLineEnd);
  x := XInLine(ln, APos);
  Result := Rect(x, FLines[ln].Top, x + 1, FLines[ln].Top + FLines[ln].Height);
end;

function TTyParaLayout.SelectionRects(AFrom, ATo: TTyRichPos): TRectArray;
var
  n, ln, xa, xb: Integer;
begin
  Result := nil;
  if AFrom < 0 then AFrom := 0;
  if ATo > FLength + 1 then ATo := FLength + 1;
  if ATo <= AFrom then Exit;
  n := 0;
  for ln := LineOfPos(Min(AFrom, FShown)) to FLineCount - 1 do
  begin
    if FLines[ln].First >= ATo then Break;
    if not LineSelection(ln, AFrom, ATo, xa, xb) then Continue;
    SetLength(Result, n + 1);
    Result[n] := Rect(xa, FLines[ln].Top, xb, FLines[ln].Top + FLines[ln].Height);
    Inc(n);
  end;
end;

{ ---- table rows ---- }

destructor TTyRowLayout.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FItems) do FItems[i].Layout.Release;
  if FTable <> nil then FTable.Release;
  inherited Destroy;
end;

function TTyRowLayout.GetCell(AIndex: Integer): TTyRichCellBox;
begin
  if (AIndex < 0) or (AIndex > High(FCells)) then
    raise EArgumentOutOfRangeException.CreateFmt('no cell %d', [AIndex]);
  Result := FCells[AIndex];
end;

function TTyRowLayout.GetItem(AIndex: Integer): TTyRichRowItem;
begin
  if (AIndex < 0) or (AIndex > High(FItems)) then
    raise EArgumentOutOfRangeException.CreateFmt('no item %d', [AIndex]);
  Result := FItems[AIndex];
end;

function TTyRowLayout.CellCount: Integer;
begin
  Result := System.Length(FCells);
end;

function TTyRowLayout.ItemCount: Integer;
begin
  Result := System.Length(FItems);
end;

function TTyRowLayout.MemSize: Int64;
var
  i: Integer;
begin
  Result := inherited MemSize + Int64(System.Length(FCells)) * SizeOf(TTyRichCellBox) +
    Int64(System.Length(FItems)) * SizeOf(TTyRichRowItem) +
    Int64(System.Length(FDisplay.Cells)) * SizeOf(TTyRowCellDisplay);
  for i := 0 to High(FItems) do Inc(Result, FItems[i].Layout.MemSize);
end;

function TTyRowLayout.ItemAt(APos: TTyRichPos): Integer;
var
  lo, hi, mid: Integer;
begin
  lo := 0;
  hi := High(FItems);
  while lo < hi do
  begin
    mid := (lo + hi + 1) div 2;
    if FItems[mid].Pos <= APos then lo := mid else hi := mid - 1;
  end;
  Result := lo;
end;

{ The shown cell at AX, or the nearest one: a point left of the row is in its first cell,
  one right of it in its last. -1 when no cell is shown. }
function TTyRowLayout.CellAtX(AX: Integer): Integer;
var
  i, d, best: Integer;
begin
  Result := -1;
  best := MaxInt;
  for i := 0 to High(FCells) do
  begin
    if FCells[i].Hidden or (FCells[i].ItemCount = 0) then Continue;
    if AX < FCells[i].Left then d := FCells[i].Left - AX
    else if AX >= FCells[i].Right then d := AX - FCells[i].Right + 1
    else d := 0;
    if d < best then
    begin
      best := d;
      Result := i;
    end;
  end;
end;

function TTyRowLayout.PosAtPoint(AX, AY: Integer; out AAtLineEnd: Boolean): TTyRichPos;
var
  c, k, last: Integer;
begin
  AAtLineEnd := False;
  c := CellAtX(AX);
  if c < 0 then Exit(0);
  // the cell's paragraph at AY: above the first, the first; below the last, the last
  k := FCells[c].FirstItem;
  last := k + FCells[c].ItemCount - 1;
  while (k < last) and ((FItems[k].Cell <> c) or
    (FItems[k].Y + FItems[k].Layout.Height <= AY)) do
    Inc(k);
  Result := FItems[k].Pos + FItems[k].Layout.PosAtPoint(AX - FItems[k].X, AY - FItems[k].Y,
    AAtLineEnd);
end;

function TTyRowLayout.CaretRect(APos: TTyRichPos; AAtLineEnd: Boolean): TRect;
var
  k, o: Integer;
begin
  if System.Length(FItems) = 0 then Exit(Rect(0, 0, 1, 1));
  if APos < 0 then APos := 0;
  if APos > FCharCount - 1 then APos := FCharCount - 1;
  k := ItemAt(APos);
  o := FCells[FItems[k].Cell].Owner;
  if FCells[FItems[k].Cell].Hidden and (FCells[o].ItemCount > 0) then
  begin
    // a paragraph of a cell merged away: at the end of the cell it went into
    k := FCells[o].FirstItem + FCells[o].ItemCount - 1;
    Result := FItems[k].Layout.CaretRect(FItems[k].Layout.Length);
  end
  else
    Result := FItems[k].Layout.CaretRect(APos - FItems[k].Pos, AAtLineEnd);
  Types.OffsetRect(Result, FItems[k].X, FItems[k].Y);
  { Inside the cell's box: what an exact-height row (or a cell with no room) does not show,
    its caret is not drawn over the next row either - at the box's edge instead. }
  o := FCells[FItems[k].Cell].Owner;
  if Result.Bottom > FHeight then Result.Bottom := FHeight;
  if Result.Top > Result.Bottom - 1 then Result.Top := Result.Bottom - 1;
  if Result.Top < 0 then
  begin
    Result.Top := 0;
    if Result.Bottom < 1 then Result.Bottom := 1;
  end;
  if Result.Left > FCells[o].Right - 1 then Result.Left := FCells[o].Right - 1;
  if Result.Left < FCells[o].Left then Result.Left := FCells[o].Left;
  Result.Right := Result.Left + 1;
end;

function TTyRowLayout.SelectionRects(AFrom, ATo: TTyRichPos): TRectArray;
var
  k, i, n, o: Integer;
  a, b: TTyRichPos;
  rs: TRectArray;
  r, box: TRect;
begin
  Result := nil;
  n := 0;
  for k := 0 to High(FItems) do
  begin
    if FCells[FItems[k].Cell].Hidden then Continue;
    a := AFrom - FItems[k].Pos;
    b := ATo - FItems[k].Pos;
    if (b <= 0) or (a > FItems[k].Layout.Length) then Continue;
    rs := FItems[k].Layout.SelectionRects(a, b);
    o := FCells[FItems[k].Cell].Owner;
    box := Rect(FCells[o].Left, 0, FCells[o].Right, FHeight);
    SetLength(Result, n + System.Length(rs));
    for i := 0 to High(rs) do
    begin
      r := rs[i];
      Types.OffsetRect(r, FItems[k].X, FItems[k].Y);
      // what the cell's box does not show is not shown selected either
      if not Types.IntersectRect(r, r, box) then Continue;
      Result[n] := r;
      Inc(n);
    end;
  end;
  SetLength(Result, n);
end;

{ ---- painting ---- }

function PaintColor(AColor: TColor; const ADefault: TBGRAPixel): TBGRAPixel;
begin
  if (AColor = clDefault) or (AColor = clNone) then Exit(ADefault);
  Result := ColorToBGRA(ColorToRGB(AColor));
end;

{ The selected stretch [ASelX0, ASelX1) cut out of what is drawn of a fragment: the parts
  left and right of it in the normal colour, the stretch in the selection's - each the whole
  fragment drawn with the clip narrowed to its part, so that no glyph moves between them. }
type
  TTyInkPart = record
    Clip: TRect;
    Selected: Boolean;
  end;
  TTyInkParts = array[0..2] of TTyInkPart;

function InkParts(const AClip: TRect; AX0, AX1, ASelX0, ASelX1: Integer;
  out AParts: TTyInkParts): Integer;
var
  s0, s1, n: Integer;

  procedure Add(ALeft, ARight: Integer; ASel: Boolean);
  begin
    if ARight <= ALeft then Exit;
    AParts[n].Clip := Rect(ALeft, AClip.Top, ARight, AClip.Bottom);
    AParts[n].Selected := ASel;
    Inc(n);
  end;

begin
  n := 0;
  s0 := Max(Max(AX0, ASelX0), AClip.Left);
  s1 := Min(Min(AX1, ASelX1), AClip.Right);
  if s1 <= s0 then
  begin
    // not selected: drawn once, in the caller's clip
    AParts[0].Clip := AClip;
    AParts[0].Selected := False;
    Exit(1);
  end;
  if (s0 <= Max(AX0, AClip.Left)) and (s1 >= Min(AX1, AClip.Right)) then
  begin
    // all of it that is drawn is selected
    AParts[0].Clip := AClip;
    AParts[0].Selected := True;
    Exit(1);
  end;
  Add(AClip.Left, s0, False);
  Add(s0, s1, True);
  Add(s1, AClip.Right, False);
  Result := n;
end;

function TTyParaLayout.PaintFormat(AFormat: TTyCharFormatId): TTyRichPaintFormat;
var
  lo, hi, mid: Integer;
begin
  lo := 0;
  hi := High(FPaintFormats);
  while lo <= hi do
  begin
    mid := (lo + hi) div 2;
    if FPaintFormats[mid].Format = AFormat then Exit(FPaintFormats[mid]);
    if FPaintFormats[mid].Format < AFormat then lo := mid + 1 else hi := mid - 1;
  end;
  Result.Format := AFormat;
  Result.Color := clDefault;
  Result.Highlight := clNone;
  Result.Underline := False;
  Result.Strike := False;
end;

{ What painting needs of each character format the fragments use, taken from the document
  when the layout is made (a layout outlives a document switch of its layouter): sorted by
  format id. }
procedure TTyParaLayout.TakePaintFormats(ADoc: TTyRichDocument);
var
  ids: array of Integer;
  n, i, j, k: Integer;
  f: TTyCharFormat;

  procedure AddId(AId: Integer);
  var
    m: Integer;
  begin
    for m := 0 to n - 1 do
      if ids[m] = AId then Exit;
    if n = System.Length(ids) then SetLength(ids, n * 2 + 4);
    ids[n] := AId;
    Inc(n);
  end;

begin
  ids := nil;
  n := 0;
  for i := 0 to FFragCount - 1 do AddId(FFrags[i].Format);
  if FHasMarker then AddId(FMarker.Format);
  if FTruncated then AddId(FNotice.Format);
  // sorted (they are few)
  for i := 1 to n - 1 do
  begin
    k := ids[i];
    j := i - 1;
    while (j >= 0) and (ids[j] > k) do
    begin
      ids[j + 1] := ids[j];
      Dec(j);
    end;
    ids[j + 1] := k;
  end;
  SetLength(FPaintFormats, n);
  for i := 0 to n - 1 do
  begin
    if (ids[i] >= 0) and (ids[i] < ADoc.Formats.CharCount) then
      f := ADoc.Formats.CharFormat(ids[i])
    else
      f := TyDefaultCharFormat;
    FPaintFormats[i].Format := ids[i];
    FPaintFormats[i].Color := f.Color;
    FPaintFormats[i].Highlight := f.HighlightColor;
    FPaintFormats[i].Underline := fsUnderline in f.Style;
    FPaintFormats[i].Strike := f.Strike or (fsStrikeOut in f.Style);
  end;
end;

{ The selected stretch of line ALine for [AFrom, ATo) (block pixels): from the start's caret
  to the end's, a whole line that the selection goes on past to its end with its hanging
  spaces, and a mark past the end for a selected U+000B or the paragraph's separator. False
  when nothing of the line is selected. }
function TTyParaLayout.LineSelection(ALine: Integer; AFrom, ATo: TTyRichPos;
  out AXa, AXb: Integer): Boolean;
var
  a, b, stop, mark: Integer;
  isLast: Boolean;
begin
  Result := False;
  AXa := 0;
  AXb := 0;
  if AFrom < 0 then AFrom := 0;
  if ATo > FLength + 1 then ATo := FLength + 1;
  if ATo <= AFrom then Exit;
  isLast := ALine = FLineCount - 1;
  with FLines[ALine] do
  begin
    if First >= ATo then Exit;
    stop := First + Count;
    a := Max(AFrom, First);
    b := Min(ATo, stop);
    if b < a then Exit;
    AXa := XInLine(ALine, a);
    if (b >= stop) and not isLast then AXb := EndX else AXb := XInLine(ALine, b);
    mark := Max(2, Height div 4);
    // a selected U+000B, or the paragraph's separator: a mark past the line's end
    if (Forced and (ATo >= stop) and (AFrom < stop)) or (isLast and (ATo > FLength)) then
      AXb := Max(AXb, EndX) + mark;
    Result := AXb > AXa;
  end;
end;

procedure TTyParaLayout.Paint(ATarget: TBGRABitmap; AX, AY: Integer; const AClip: TRect;
  const AStyle: TTyRichPaintStyle; ASelFrom, ASelTo: TTyRichPos);
var
  clip, old: TRect;
  ln, top: Integer;
begin
  if ATarget = nil then Exit;
  old := ATarget.ClipRect;
  if not Types.IntersectRect(clip, AClip, old) then Exit;
  ATarget.ClipRect := clip;
  FLayouter.PaintEnter;
  try
    // the lines that meet the clip, and no others
    ln := LineAtY(clip.Top - AY);
    while ln < FLineCount do
    begin
      top := AY + FLines[ln].Top;
      if top >= clip.Bottom then Break;
      if top + FLines[ln].Height > clip.Top then
        PaintLine(ATarget, ln, AX, AY, clip, AStyle, ASelFrom, ASelTo);
      Inc(ln);
    end;
    // a cut paragraph's notice, under its text, never selected
    if FTruncated and (AY + FNoticeTop < clip.Bottom) and
      (AY + FNoticeBaseline + FNotice.Descent > clip.Top) then
      FLayouter.Device.DrawText(ATarget, FNotice.Font, AX + FNotice.X, AY + FNoticeBaseline,
        FNotice.Text, PaintColor(PaintFormat(FNotice.Format).Color, AStyle.TextColor));
  finally
    FLayouter.PaintLeave;
    ATarget.ClipRect := old;
  end;
end;

procedure TTyParaLayout.PaintLine(ATarget: TBGRABitmap; ALine, AX, AY: Integer;
  const AClip: TRect; const AStyle: TTyRichPaintStyle; ASelFrom, ASelTo: TTyRichPos);
var
  ln: ^TTyRichLine;
  f: ^TTyRichFragment;
  pf: TTyRichPaintFormat;
  i, k, n, y0, y1, base, xa, xb, x0, x1, px, th, slack, contentRight, lineY, linePx: Integer;
  hasSel, sel: Boolean;
  parts: TTyInkParts;
  ink, col: TBGRAPixel;
  drawn: UTF8String;
  box: TRect;

  // the fragment's place and some room for glyphs that reach past it; False: nothing of it
  // is in the clip
  function Visible(const F: TTyRichFragment): Boolean;
  begin
    x0 := AX + F.X;
    x1 := x0 + F.Width;
    slack := Max(2, FLayouter.Device.FontPixelHeight(F.Font) div 2);
    Result := (x1 + slack > AClip.Left) and (x0 - slack < AClip.Right);
  end;

  function SelectedChars(const F: TTyRichFragment): Boolean;
  begin
    Result := (F.Count > 0) and (F.First >= ASelFrom) and (F.First + F.Count <= ASelTo);
  end;

  // a fragment cut into segments (a line stretched between its characters): each segment as
  // it was measured, at its stretched place - where its caret place is - the ones the clip
  // meets
  procedure DrawSegments(const F: TTyRichFragment; const AInClip: TRect; AColor: TBGRAPixel);
  var
    starts, bytes: TIntegerDynArray;
    s, x, xs, w: Integer;
  begin
    starts := SegmentStarts(F, bytes);
    x := x0;
    for s := 0 to High(starts) - 1 do
    begin
      w := SegmentWidth(F, bytes, s);
      xs := x + StretchBefore(F, s);
      if (xs + w + slack > AInClip.Left) and (xs - slack < AInClip.Right) then
        FLayouter.Device.DrawText(ATarget, F.Font, xs, base + F.Shift,
          Copy(FText, F.ByteStart + 1 + bytes[s], bytes[s + 1] - bytes[s]), AColor);
      Inc(x, w);
    end;
  end;

  // a horizontal line [AL, AR) x [AT, AT + AH) in the fragment's colours, cut at the selection
  procedure Bar(AL, AR, AT, AH: Integer; ANormal, ASel: TBGRAPixel);
  var
    m, j: Integer;
    pp: TTyInkParts;
    r: TRect;
  begin
    if hasSel then m := InkParts(AClip, AL, AR, AX + xa, AX + xb, pp)
    else m := InkParts(AClip, AL, AR, 0, 0, pp);
    for j := 0 to m - 1 do
    begin
      if not Types.IntersectRect(r, Rect(AL, AT, AR, AT + AH), pp[j].Clip) then Continue;
      if pp[j].Selected then ATarget.FillRect(r.Left, r.Top, r.Right, r.Bottom, ASel, dmSet)
      else ATarget.FillRect(r.Left, r.Top, r.Right, r.Bottom, ANormal, dmSet);
    end;
  end;

  procedure Leader(const F: TTyRichFragment; AColor: TBGRAPixel);
  var
    step, dot, x, xs, xe: Integer;
  begin
    xs := AX + F.X;
    xe := xs + F.Width;
    step := Max(3, px div 4);
    dot := Max(1, px div 12);
    case F.Leader of
      ttlDot, ttlHyphen:
        begin
          // on a grid of the block, so leaders on lines above one another line up
          x := AX + ((F.X + step - 1) div step) * step;
          while x + dot <= xe do
          begin
            if F.Leader = ttlDot then
              ATarget.FillRect(x, base - dot, x + dot, base, AColor, dmSet)
            else
              ATarget.FillRect(x, base - px div 4 - th, x + Max(dot, step * 2 div 3), base - px div 4,
                AColor, dmSet);
            Inc(x, step);
          end;
        end;
      ttlUnderline:
        ATarget.FillRect(xs, lineY, xe, lineY + th, AColor, dmSet);
      ttlThick:
        ATarget.FillRect(xs, lineY, xe, lineY + 2 * th, AColor, dmSet);
      ttlEqual:
        begin
          ATarget.FillRect(xs, base - px div 4 - 2 * th, xe, base - px div 4 - th, AColor, dmSet);
          ATarget.FillRect(xs, base - px div 4 + th, xe, base - px div 4 + 2 * th, AColor, dmSet);
        end;
    end;
  end;

begin
  ln := @FLines[ALine];
  y0 := AY + ln^.Top;
  y1 := y0 + ln^.Height;
  base := AY + ln^.Baseline;
  hasSel := LineSelection(ALine, ASelFrom, ASelTo, xa, xb);
  contentRight := AX + ln^.Left + ln^.ContentWidth;
  linePx := Max(1, Round(FPPI * Double(FZoom) / 96));
  // highlights
  for i := ln^.FirstFrag to ln^.FirstFrag + ln^.FragCount - 1 do
  begin
    f := @FFrags[i];
    if not Visible(f^) then Continue;
    pf := PaintFormat(f^.Format);
    if pf.Highlight <> clNone then
      ATarget.FillRect(x0, y0, x1, y1, PaintColor(pf.Highlight, AStyle.SelectionBack), dmSet);
  end;
  // the selection
  if hasSel then
    ATarget.FillRect(AX + xa, y0, AX + xb, y1, AStyle.SelectionBack, dmDrawWithTransparency);
  // text: each fragment as it was measured, where it was measured
  for i := ln^.FirstFrag to ln^.FirstFrag + ln^.FragCount - 1 do
  begin
    f := @FFrags[i];
    if not (f^.Kind in [rfkText, rfkReplacement, rfkObject]) then Continue;
    if (f^.Kind = rfkObject) and (f^.Text = '') then Continue;
    if not Visible(f^) then Continue;
    drawn := FragmentText(i);
    if drawn = '' then Continue;
    ink := PaintColor(PaintFormat(f^.Format).Color, AStyle.TextColor);
    if hasSel then n := InkParts(AClip, x0, x1, AX + xa, AX + xb, parts)
    else n := InkParts(AClip, x0, x1, 0, 0, parts);
    for k := 0 to n - 1 do
    begin
      if n > 1 then ATarget.ClipRect := parts[k].Clip;
      if parts[k].Selected then col := AStyle.SelectionText else col := ink;
      if f^.StretchGaps > 0 then
        DrawSegments(f^, parts[k].Clip, col)
      else
        FLayouter.Device.DrawText(ATarget, f^.Font, x0, base + f^.Shift, drawn, col);
    end;
    if n > 1 then ATarget.ClipRect := AClip;
  end;
  // underline and strike-through, tab leaders: thickness and place from the font's size
  for i := ln^.FirstFrag to ln^.FirstFrag + ln^.FragCount - 1 do
  begin
    f := @FFrags[i];
    if f^.Kind = rfkBreak then Continue;
    if not Visible(f^) then Continue;
    pf := PaintFormat(f^.Format);
    px := FLayouter.Device.FontPixelHeight(f^.Font);
    th := Max(1, Round(px / 16));
    lineY := base + f^.Shift + Max(1, Round(px / 10));
    ink := PaintColor(pf.Color, AStyle.TextColor);
    if (f^.Kind = rfkTab) and (f^.Leader <> ttlNone) then
    begin
      if hasSel and SelectedChars(f^) then Leader(f^, AStyle.SelectionText)
      else Leader(f^, ink);
    end;
    // not under the spaces that hang past the line's content
    if (pf.Underline or pf.Strike) and (x0 < contentRight) and
      not ((f^.Kind = rfkObject) and (f^.Text = '')) then
    begin
      if pf.Underline then
        Bar(x0, Min(x1, contentRight), lineY, th, ink, AStyle.SelectionText);
      if pf.Strike then
        Bar(x0, Min(x1, contentRight), base + f^.Shift - Round(px * 0.28), th, ink,
          AStyle.SelectionText);
    end;
  end;
  // pictures and placeholders, decoded when one is first drawn
  for i := ln^.FirstFrag to ln^.FirstFrag + ln^.FragCount - 1 do
  begin
    f := @FFrags[i];
    if (f^.Kind <> rfkObject) or not (f^.Obj is TTyRichPicture) then Continue;
    box := Rect(AX + f^.X, base - f^.Ascent, AX + f^.X + f^.Width, base + f^.Descent);
    if (box.Right <= AClip.Left) or (box.Left >= AClip.Right) or (box.Bottom <= AClip.Top) or
      (box.Top >= AClip.Bottom) then
      Continue;
    if AStyle.DeferPictures and not FLayouter.PictureReady(TTyRichPicture(f^.Obj),
      box.Right - box.Left, box.Bottom - box.Top) then
    begin
      // not decoded here: an empty box now, the picture when its owner has prepared it
      ATarget.FillRect(box.Left, box.Top, box.Right, box.Bottom, AStyle.PlaceholderFill,
        dmDrawWithTransparency);
      FLayouter.NoteSkippedPicture(TTyRichPicture(f^.Obj), box);
    end
    else
      FLayouter.DrawPicture(ATarget, TTyRichPicture(f^.Obj), box, linePx, AStyle);
    sel := (f^.First >= ASelFrom) and (f^.First < ASelTo);
    if sel then
    begin
      ATarget.FillRect(box.Left, box.Top, box.Right, box.Top + linePx, AStyle.ObjectFrame, dmSet);
      ATarget.FillRect(box.Left, box.Bottom - linePx, box.Right, box.Bottom, AStyle.ObjectFrame,
        dmSet);
      ATarget.FillRect(box.Left, box.Top, box.Left + linePx, box.Bottom, AStyle.ObjectFrame, dmSet);
      ATarget.FillRect(box.Right - linePx, box.Top, box.Right, box.Bottom, AStyle.ObjectFrame,
        dmSet);
    end;
  end;
  // the list marker, never selected
  if (ALine = 0) and FHasMarker and Visible(FMarker) then
    FLayouter.Device.DrawText(ATarget, FMarker.Font, x0, base, FMarker.Text,
      PaintColor(PaintFormat(FMarker.Format).Color, AStyle.TextColor));
end;

procedure TTyRowLayout.Paint(ATarget: TBGRABitmap; AX, AY: Integer; const AClip: TRect;
  const AStyle: TTyRichPaintStyle; ASelFrom, ASelTo: TTyRichPos);
var
  clip, old: TRect;
begin
  if ATarget = nil then Exit;
  old := ATarget.ClipRect;
  if not Types.IntersectRect(clip, AClip, old) then Exit;
  // one paint pass for all its cells' pictures (when the caller counts none)
  FLayouter.PaintEnter;
  try
    PaintRow(ATarget, AX, AY, clip, old, AStyle, ASelFrom, ASelTo);
  finally
    FLayouter.PaintLeave;
  end;
end;

procedure TTyRowLayout.PaintRow(ATarget: TBGRABitmap; AX, AY: Integer; const AClip,
  AOld: TRect; const AStyle: TTyRichPaintStyle; ASelFrom, ASelTo: TTyRichPos);
var
  i, k, w: Integer;
  clip, old, cr, box: TRect;
  bx: ^TTyRichCellBox;
  it: ^TTyRichRowItem;
begin
  clip := AClip;
  old := AOld;
  // contents: each shown cell that meets the clip, its paragraphs clipped to its box
  for i := 0 to High(FCells) do
  begin
    bx := @FCells[i];
    if bx^.Hidden then Continue;
    box := Rect(AX + bx^.Left, AY, AX + bx^.Right, AY + FHeight);
    if not Types.IntersectRect(cr, clip, box) then Continue;
    for k := bx^.FirstItem to bx^.FirstItem + bx^.ItemCount - 1 do
    begin
      it := @FItems[k];
      if it^.Cell <> i then Continue;
      if (AY + it^.Y >= cr.Bottom) or (AY + it^.Y + it^.Layout.Height <= cr.Top) then Continue;
      it^.Layout.Paint(ATarget, AX + it^.X, AY + it^.Y, cr, AStyle, ASelFrom - it^.Pos,
        ASelTo - it^.Pos);
    end;
  end;
  // then the lines, over them
  ATarget.ClipRect := clip;
  try
    for i := 0 to High(FCells) do
    begin
      bx := @FCells[i];
      if bx^.Hidden or (bx^.Sides = []) then Continue;
      box := Rect(AX + bx^.Left, AY, AX + bx^.Right, AY + FHeight);
      if not Types.IntersectRect(cr, clip, box) then Continue;
      if rcsLeft in bx^.Sides then
      begin
        w := bx^.LinePx[rcsLeft];
        ATarget.FillRect(box.Left, box.Top, box.Left + w, box.Bottom, AStyle.TableBorder, dmSet);
      end;
      if rcsTop in bx^.Sides then
      begin
        w := bx^.LinePx[rcsTop];
        ATarget.FillRect(box.Left, box.Top, box.Right, box.Top + w, AStyle.TableBorder, dmSet);
      end;
      if rcsRight in bx^.Sides then
      begin
        w := bx^.LinePx[rcsRight];
        ATarget.FillRect(box.Right - w, box.Top, box.Right, box.Bottom, AStyle.TableBorder, dmSet);
      end;
      if rcsBottom in bx^.Sides then
      begin
        w := bx^.LinePx[rcsBottom];
        ATarget.FillRect(box.Left, box.Bottom - w, box.Right, box.Bottom, AStyle.TableBorder,
          dmSet);
      end;
    end;
  finally
    ATarget.ClipRect := old;
  end;
end;

{ ---- building a paragraph's layout ---- }

type
  TPiece = record
    First, Count: Integer;
    Kind: TTyRichFragKind;
    Font: TTyRichFontId;
    Format: TTyCharFormatId;
    Shift: Integer;
    Width: Integer;
    Brk: Byte;              // 0: no line may start here, 1: one may (U+000B ends its line itself)
    Obj: TTyRichObject;
    Asc, Desc, Lead: Integer;
    Text: UTF8String;
  end;

  TItem = record
    Piece: Integer;
    Kind: TTyRichFragKind;
    First, Count: Integer;
    Width: Integer;
    X: Integer;
    Natural: Integer;
    Stretch, StretchGaps, StretchFirst: Integer;
  end;

  { How a line's pieces are joined into fragments: jmAll - neighbours of one font and format,
    words and the spaces between them (a line that is not justified); jmWords - text with
    text only, the spaces apart, for they take a justified line's stretch; jmChars - text with
    text, measured as the sum of the segments between its break opportunities, for a
    justified line with no spaces is stretched there. }
  TJoinMode = (jmAll, jmWords, jmChars);

  TParaBuilder = class
  public
    L: TTyRichLayouter;
    Dev: TTyRichTextDevice;
    Layout: TTyParaLayout;
    Txt: RawByteString;
    N: Integer;
    PPI: Integer;
    Zoom: Single;
    Width: Integer;
    Pf: TTyParaFormat;
    Runs: TTyRunArray;
    Cp: array of Cardinal;
    Bo: array of Integer;
    Kind: array of Byte;
    ClStart: array of Boolean;
    Brk: array of Byte;
    CFont: array of Integer;
    CFmt: array of Integer;
    CObj: array of TTyRichObject;
    Pieces: array of TPiece;
    PieceCount: Integer;
    Items: array of TItem;
    ItemCount: Integer;
    LeftPx, RightPx, FirstPx: Integer;
    TabPos: array of Integer;
    TabAlign: array of TTyTabAlign;
    TabLeader: array of TTyTabLeader;
    DefTab: Integer;
    FirstLine: Boolean;  // the line being laid out is the paragraph's first
    ListNumber: Int64;
    FullLen: Integer;    // the paragraph's length (N is what is laid out of it)
    function Px(ATwips: Integer): Integer;
    function MakeMarker: Integer;
    procedure Decode(const AText: RawByteString; AExpected: Integer);
    procedure MapRuns;
    procedure FindClusters;
    procedure FindBreaks;
    procedure ResolveFonts;
    procedure MakePieces;
    function ClusterEnd(I: Integer): Integer;
    function RangeText(AFrom, ATo: Integer): UTF8String;
    function MeasureRange(APiece, AFrom, ATo: Integer): Integer;
    procedure NextStop(AX: Integer; out AStop: Integer; out AAlign: TTyTabAlign;
      out ALeader: TTyTabLeader);
    function FitClusters(APiece, AFrom, AAvail: Integer): Integer;
    function FindLineEnd(AStart: Integer; var AK: Integer; ALeft: Integer): Integer;
    procedure LayLine(AStart, AEnd, AK: Integer; AMode: TJoinMode);
    function SegmentsWidth(AFont: TTyRichFontId; AFrom, ATo: Integer): Integer;
    function PieceAt(AChar, AHint: Integer): Integer;
    procedure EmitLine(AStart, AEnd, AK: Integer; ALeft: Integer; var ATop: Integer;
      AForced, ALast: Boolean; AEmptyFormat: TTyCharFormatId);
    procedure MakeNotice(var ATop: Integer; AFormat: TTyCharFormatId);
    procedure Run;
  end;

function TParaBuilder.Px(ATwips: Integer): Integer;
begin
  Result := TyRichTwipsToPx(ATwips, PPI, Zoom);
end;

procedure TParaBuilder.Decode(const AText: RawByteString; AExpected: Integer);
var
  pos, i, len, cap: Integer;
  b: Byte;
  c: Cardinal;
begin
  Txt := AText;
  cap := Max(AExpected, 0) + 1;
  SetLength(Cp, cap);
  SetLength(Bo, cap + 1);
  SetLength(Kind, cap);
  i := 0;
  pos := 1;
  while pos <= System.Length(Txt) do
  begin
    if i + 2 >= cap then
    begin
      cap := cap * 2 + 16;
      SetLength(Cp, cap);
      SetLength(Bo, cap + 1);
      SetLength(Kind, cap);
    end;
    Bo[i] := pos - 1;
    b := Byte(Txt[pos]);
    if b < $80 then
    begin
      c := b;
      len := 1;
    end
    else
    begin
      len := SeqLen(PByte(@Txt[pos]), System.Length(Txt) - pos + 1);
      if len = 1 then
      begin
        { not text. An escaped byte (TextIO: F8..FB, then 80..BF) is two characters and
          shows as one replacement; any other such byte is one character and one. }
        Cp[i] := $FFFD;
        Kind[i] := ckInvalid;
        Inc(i);
        Inc(pos);
        if (b >= $F8) and (b <= $FB) and (pos <= System.Length(Txt)) and
          (Byte(Txt[pos]) and $C0 = $80) then
        begin
          Bo[i] := pos - 1;
          Cp[i] := $FFFD;
          Kind[i] := ckInvalid2;
          Inc(i);
          Inc(pos);
        end;
        Continue;
      end;
      c := CodeOf(PByte(@Txt[pos]), len);
    end;
    Cp[i] := c;
    case c of
      $20: Kind[i] := ckSpace;
      $09: Kind[i] := ckTab;
      $0B: Kind[i] := ckBreak;
    else
      Kind[i] := ckText;
    end;
    Inc(i);
    Inc(pos, len);
  end;
  N := i;
  Bo[N] := System.Length(Txt);
end;

procedure TParaBuilder.MapRuns;
var
  r, i, stop: Integer;
begin
  SetLength(CFmt, N + 1);
  SetLength(CObj, N + 1);
  if System.Length(Runs) = 0 then
  begin
    for i := 0 to N - 1 do
    begin
      CFmt[i] := 0;
      CObj[i] := nil;
    end;
    Exit;
  end;
  for r := 0 to High(Runs) do
  begin
    // a cut paragraph: the runs past what was read are not looked at
    if Runs[r].Start >= N then Break;
    if r < High(Runs) then stop := Runs[r + 1].Start else stop := N;
    if stop > N then stop := N;
    for i := Max(0, Runs[r].Start) to stop - 1 do
    begin
      CFmt[i] := Runs[r].Format;
      CObj[i] := nil;
    end;
    if (Runs[r].Obj <> nil) and (Runs[r].Start >= 0) and (Runs[r].Start < N) then
    begin
      CObj[Runs[r].Start] := Runs[r].Obj;
      Kind[Runs[r].Start] := ckObject;
    end;
  end;
  // characters before the first run (there are none in a well-formed paragraph)
  for i := 0 to Min(Runs[0].Start, N) - 1 do
  begin
    CFmt[i] := Runs[0].Format;
    CObj[i] := nil;
  end;
end;

procedure TParaBuilder.FindClusters;
var
  i, cs: Integer;
  join, riOdd: Boolean;
begin
  SetLength(ClStart, N + 1);
  if N = 0 then Exit;
  ClStart[0] := True;
  cs := 0;
  riOdd := IsRegional(Cp[0]) and (Kind[0] = ckText);
  for i := 1 to N - 1 do
  begin
    join := False;
    if Kind[i] = ckInvalid2 then
      join := True
    else if (Kind[i] = ckText) and (Kind[i - 1] in [ckText, ckSpace]) then
      join := TyRichIsClusterExtend(Cp[i]) or ((Cp[i - 1] = $200D) and (Kind[i - 1] = ckText)) or
        (IsRegional(Cp[i]) and IsRegional(Cp[i - 1]) and riOdd);
    ClStart[i] := not join;
    if join then
    begin
      CFmt[i] := CFmt[i - 1];
      // a space carrying a mark is text: drawn, measured, broken as a letter
      if Kind[cs] = ckSpace then Kind[cs] := ckText;
    end
    else
      cs := i;
    if (Kind[i] = ckText) and IsRegional(Cp[i]) then riOdd := not join else riOdd := False;
  end;
end;

procedure TParaBuilder.FindBreaks;
var
  i, p: Integer;
  pk, ck: Byte;
  pc, cc: Cardinal;
  b: Byte;
begin
  SetLength(Brk, N + 1);
  if N = 0 then Exit;
  Brk[0] := 0;
  p := 0;   // the start of the cluster before i
  for i := 1 to N - 1 do
  begin
    if not ClStart[i] then
    begin
      Brk[i] := 0;
      Continue;
    end;
    pk := Kind[p];
    pc := Cp[p];
    ck := Kind[i];
    cc := Cp[i];
    if pk = ckBreak then b := 1
    // between two text clusters: the rule a fragment cut into segments applies too
    else if (pk = ckText) and (ck = ckText) then b := Ord(TextBreakBetween(pc, cc))
    else if ck in [ckSpace, ckBreak, ckTab] then b := 0
    else if (ck = ckText) and TyRichIsKinsokuNoLineStart(cc) then b := 0
    else if (pk = ckText) and TyRichIsKinsokuNoLineEnd(pc) then b := 0
    else if pk in [ckSpace, ckTab] then b := 1
    else if (pk in [ckObject, ckInvalid]) or (ck in [ckObject, ckInvalid]) then b := 1
    else if IsIdeographic(pc) or IsIdeographic(cc) then b := 1
    else b := 0;
    Brk[i] := b;
    p := i;
  end;
end;

procedure TParaBuilder.ResolveFonts;
var
  i, prevStart, f: Integer;
begin
  SetLength(CFont, N + 1);
  prevStart := -1;
  for i := 0 to N - 1 do
  begin
    if not ClStart[i] then
    begin
      CFont[i] := CFont[i - 1];
      Continue;
    end;
    f := L.FormatFont(CFmt[i], PPI, Zoom).Font;
    case Kind[i] of
      ckText:
        if not L.GlyphIn(f, Cp[i]) then f := L.FallbackFor(f, Cp[i]);
      ckSpace:
        // a space between characters of a fallback font stays in that font, so the run is
        // not cut in three
        if (prevStart >= 0) and (CFont[prevStart] <> f) and (CFmt[prevStart] = CFmt[i]) and
          (Kind[prevStart] in [ckText, ckSpace]) and L.GlyphIn(CFont[prevStart], $20) then
          f := CFont[prevStart];
      ckInvalid:
        if not L.GlyphIn(f, $FFFD) then f := L.FallbackFor(f, $FFFD);
    end;
    CFont[i] := f;
    prevStart := i;
  end;
end;

function TParaBuilder.ClusterEnd(I: Integer): Integer;
begin
  Result := I + 1;
  while (Result < N) and not ClStart[Result] do Inc(Result);
end;

function TParaBuilder.RangeText(AFrom, ATo: Integer): UTF8String;
begin
  Result := Copy(Txt, Bo[AFrom] + 1, Bo[ATo] - Bo[AFrom]);
end;

function PieceKindOf(AKind: Byte): TTyRichFragKind; inline;
begin
  case AKind of
    ckSpace: Result := rfkSpace;
    ckTab: Result := rfkTab;
    ckBreak: Result := rfkBreak;
    ckObject: Result := rfkObject;
    ckInvalid, ckInvalid2: Result := rfkReplacement;
  else
    Result := rfkText;
  end;
end;

procedure TParaBuilder.MakePieces;
var
  i, j: Integer;
  pk: TTyRichFragKind;
  p: ^TPiece;
  ff: TTyRichFormatFont;
  m: TTyRichFontMetrics;
  pic: TTyRichPicture;
  w, h: Integer;
begin
  PieceCount := 0;
  SetLength(Pieces, 16);
  i := 0;
  while i < N do
  begin
    pk := PieceKindOf(Kind[i]);
    if pk in [rfkTab, rfkBreak, rfkObject] then
      j := i + 1
    else if pk = rfkReplacement then
      j := ClusterEnd(i)
    else
    begin
      j := ClusterEnd(i);
      while (j < N) and (Brk[j] = 0) and (PieceKindOf(Kind[j]) = pk) and
        (CFont[j] = CFont[i]) and (CFmt[j] = CFmt[i]) and (j - i < CRichMaxPieceChars) do
        j := ClusterEnd(j);
    end;
    if PieceCount = System.Length(Pieces) then SetLength(Pieces, PieceCount * 2);
    p := @Pieces[PieceCount];
    Inc(PieceCount);
    p^.First := i;
    p^.Count := j - i;
    p^.Kind := pk;
    p^.Font := CFont[i];
    p^.Format := CFmt[i];
    ff := L.FormatFont(CFmt[i], PPI, Zoom);
    p^.Shift := ff.Shift;
    if i = 0 then p^.Brk := 0 else p^.Brk := Brk[i];
    p^.Obj := nil;
    p^.Text := '';
    m := Dev.Metrics(p^.Font);
    p^.Asc := m.Ascent - p^.Shift;
    p^.Desc := m.Descent + p^.Shift;
    p^.Lead := m.Leading;
    case pk of
      rfkText, rfkSpace:
        p^.Width := L.MeasureText(p^.Font, RangeText(i, j));
      rfkReplacement:
        begin
          p^.Text := CReplacement;
          p^.Width := L.MeasureText(p^.Font, CReplacement);
        end;
      rfkObject:
        begin
          p^.Obj := CObj[i];
          p^.Width := 0;
          if p^.Obj is TTyRichPicture then
          begin
            pic := TTyRichPicture(p^.Obj);
            w := Px(pic.WidthTwips);
            h := Px(pic.HeightTwips);
            if (w <= 0) or (h <= 0) then
            begin
              w := Max(1, TyRichClampPx(Round(CRichDefaultObjectPx * PPI * Double(Zoom) / 96)));
              h := w;
            end;
            p^.Width := w;
            p^.Asc := h;
            p^.Desc := 0;
            p^.Lead := 0;
          end
          else if (p^.Obj is TTyRichOpaque) and (TTyRichOpaque(p^.Obj).DisplayText <> '') then
          begin
            p^.Text := TTyRichOpaque(p^.Obj).DisplayText;
            p^.Width := L.MeasureText(p^.Font, p^.Text);
          end;
        end;
    else
      p^.Width := 0;   // a tab's width is its stop's business, U+000B has none
    end;
    i := j;
  end;
end;

{ The piece character AChar is in, found from a piece near it (lines go forward; a line that
  ended at an earlier break opportunity than the piece it looked at moves the hint back). }
function TParaBuilder.PieceAt(AChar, AHint: Integer): Integer;
begin
  Result := Max(0, Min(AHint, PieceCount - 1));
  while (Result > 0) and (Pieces[Result].First > AChar) do Dec(Result);
  while (Result < PieceCount - 1) and (Pieces[Result].First + Pieces[Result].Count <= AChar) do
    Inc(Result);
end;

function TParaBuilder.MeasureRange(APiece, AFrom, ATo: Integer): Integer;
var
  p: ^TPiece;
begin
  p := @Pieces[APiece];
  if (AFrom <= p^.First) and (ATo >= p^.First + p^.Count) then Exit(p^.Width);
  if p^.Kind in [rfkText, rfkSpace] then
    Result := L.MeasureText(p^.Font, RangeText(AFrom, ATo))
  else
    Result := p^.Width;
end;

{ The first explicit stop right of AX; past the last one (AX is then at or past it) the next
  multiple of the default interval. On the first line of a paragraph with a hanging indent
  the left indent is a stop too, as Word and RichEdit have it (a hand-numbered item's text
  goes there): before it only explicit stops count, the default ones are passed over. }
procedure TParaBuilder.NextStop(AX: Integer; out AStop: Integer; out AAlign: TTyTabAlign;
  out ALeader: TTyTabLeader);
var
  i: Integer;
  hang: Boolean;
begin
  hang := FirstLine and (FirstPx < 0) and (AX < LeftPx);
  for i := 0 to High(TabPos) do
    if TabPos[i] > AX then
    begin
      if hang and (TabPos[i] > LeftPx) then Break;
      AStop := TabPos[i];
      AAlign := TabAlign[i];
      ALeader := TabLeader[i];
      Exit;
    end;
  AAlign := ttaLeft;
  ALeader := ttlNone;
  if hang then AStop := LeftPx
  else AStop := (Max(AX, 0) div DefTab + 1) * DefTab;
end;

{ How many characters of piece APiece from AFrom fit in AAvail pixels, whole clusters only;
  0 when not even the first cluster does. The device's fit is a hint: what is returned is
  measured. The text handed over is at most a piece, so this costs what a line costs. }
function TParaBuilder.FitClusters(APiece, AFrom, AAvail: Integer): Integer;
var
  p: ^TPiece;
  stop, k, e, prev, w: Integer;
  s: UTF8String;
begin
  p := @Pieces[APiece];
  stop := p^.First + p^.Count;
  if AAvail <= 0 then Exit(0);
  s := RangeText(AFrom, stop);
  k := Dev.FitCount(p^.Font, s, AAvail);
  // to a cluster boundary at or before AFrom + k
  e := AFrom;
  while (e < stop) and (ClusterEnd(e) <= AFrom + k) do e := ClusterEnd(e);
  if e = AFrom then
  begin
    if MeasureRange(APiece, AFrom, ClusterEnd(AFrom)) <= AAvail then e := ClusterEnd(AFrom)
    else Exit(0);
  end;
  // check it; step back while it is over
  w := MeasureRange(APiece, AFrom, e);
  while (w > AAvail) and (e > ClusterEnd(AFrom)) do
  begin
    prev := AFrom;
    while ClusterEnd(prev) < e do prev := ClusterEnd(prev);
    e := prev;
    w := MeasureRange(APiece, AFrom, e);
  end;
  if w > AAvail then Exit(0);
  // and forward while one more cluster still fits
  while (e < stop) and (MeasureRange(APiece, AFrom, ClusterEnd(e)) <= AAvail) do
    e := ClusterEnd(e);
  Result := e - AFrom;
end;

{ Where the line that starts at character AStart ends. AK: the piece AStart is in (moved on to
  the piece the end is in). Pieces are taken while they fit; spaces always (they hang past
  the right edge); a piece that does not fit ends the line at the last break opportunity on
  it, or - with none - is cut at the edge. }
function TParaBuilder.FindLineEnd(AStart: Integer; var AK: Integer; ALeft: Integer): Integer;
var
  k, off, x, w, newX, lastOpp, c: Integer;
  xTab, segW, stop, decW: Integer;
  pending, decFound: Boolean;
  al: TTyTabAlign;
  ld: TTyTabLeader;
  p: ^TPiece;
  j: Integer;

  function TabW(ASeg, ADec: Integer; ADecFound: Boolean): Integer;
  begin
    case al of
      ttaRight: Result := stop - xTab - ASeg;
      ttaCenter: Result := stop - xTab - ASeg div 2;
      ttaDecimal: if ADecFound then Result := stop - xTab - ADec else Result := stop - xTab - ASeg;
    else
      Result := stop - xTab;
    end;
    if Result < 0 then Result := 0;
  end;

begin
  k := PieceAt(AStart, AK);
  off := AStart - Pieces[k].First;
  x := ALeft;
  pending := False;
  decFound := False;
  decW := 0;
  segW := 0;
  xTab := 0;
  stop := 0;
  al := ttaLeft;
  lastOpp := -1;
  while k < PieceCount do
  begin
    p := @Pieces[k];
    AK := k;
    if (off = 0) and (p^.First > AStart) then
    begin
      if p^.Brk <> 0 then lastOpp := p^.First;
    end;
    case p^.Kind of
      rfkTab:
        begin
          NextStop(x, stop, al, ld);
          { a stop past the right edge: the tab goes to the next line, as Word puts it -
            unless it is the line's first item, which then reaches to the edge }
          if (RightPx < CUnlimited) and (stop > RightPx) then
          begin
            if p^.First > AStart then Exit(p^.First);
            stop := Max(x, RightPx);
          end;
          if al = ttaLeft then
          begin
            x := stop;
            pending := False;
          end
          else
          begin
            pending := True;
            xTab := x;
            segW := 0;
            decFound := False;
            decW := 0;
            x := xTab + TabW(0, 0, False);
          end;
          Inc(k);
          off := 0;
          Continue;
        end;
      rfkBreak:
        Exit(p^.First + 1);
      rfkSpace:
        begin
          w := MeasureRange(k, p^.First + off, p^.First + p^.Count);
          if pending then
          begin
            Inc(segW, w);
            x := xTab + TabW(segW, decW, decFound) + segW;
          end
          else
            Inc(x, w);
          Inc(k);
          off := 0;
          Continue;
        end;
    end;
    w := MeasureRange(k, p^.First + off, p^.First + p^.Count);
    if pending then newX := xTab + TabW(segW + w, decW, decFound) + segW + w
    else newX := x + w;
    if (RightPx >= CUnlimited) or (newX <= RightPx) then
    begin
      if pending then
      begin
        if (al = ttaDecimal) and not decFound and (p^.Kind = rfkText) then
          for j := p^.First + off to p^.First + p^.Count - 1 do
            if Cp[j] = Ord('.') then
            begin
              decFound := True;
              decW := segW + MeasureRange(k, p^.First + off, j);
              Break;
            end;
        Inc(segW, w);
        x := xTab + TabW(segW, decW, decFound) + segW;
      end
      else
        x := newX;
      Inc(k);
      off := 0;
      Continue;
    end;
    // it does not fit
    if (off = 0) and (p^.Brk <> 0) and (p^.First > AStart) then Exit(p^.First);
    if lastOpp > AStart then Exit(lastOpp);
    if p^.Kind = rfkText then
    begin
      c := FitClusters(k, p^.First + off, RightPx - x);
      if c > 0 then Exit(p^.First + off + c);
    end;
    if p^.First + off > AStart then Exit(p^.First + off);
    // nothing fits, not even one cluster: it goes on the line anyway
    if p^.Kind = rfkText then Exit(ClusterEnd(p^.First + off));
    Exit(p^.First + p^.Count);
  end;
  Result := N;
end;

{ The width of [AFrom, ATo) (text of one font) as the segments between its break
  opportunities, each measured by itself - what a fragment cut into segments draws. }
function TParaBuilder.SegmentsWidth(AFont: TTyRichFontId; AFrom, ATo: Integer): Integer;
var
  c, s: Integer;
begin
  Result := 0;
  s := AFrom;
  for c := AFrom + 1 to ATo - 1 do
    if Brk[c] <> 0 then
    begin
      Inc(Result, L.MeasureText(AFont, RangeText(s, c)));
      s := c;
    end;
  Inc(Result, L.MeasureText(AFont, RangeText(s, ATo)));
end;

{ The items (unpositioned yet) of the line [AStart, AEnd): pieces, cut at the line's ends, and
  neighbours of one font and format joined into one item (AMode says which), measured again
  as what will be drawn - the one string, or for jmChars its segments. The spaces after the
  line's content stay an item of their own: they hang. }
procedure TParaBuilder.LayLine(AStart, AEnd, AK: Integer; AMode: TJoinMode);
var
  k, a, b, contentEnd: Integer;
  it: ^TItem;
  p, q: ^TPiece;
  joined: Boolean;
begin
  ItemCount := 0;
  contentEnd := AEnd;
  while (contentEnd > AStart) and (Kind[contentEnd - 1] in [ckSpace, ckBreak]) do
    Dec(contentEnd);
  k := AK;
  while (k < PieceCount) and (Pieces[k].First < AEnd) do
  begin
    p := @Pieces[k];
    a := Max(AStart, p^.First);
    b := Min(AEnd, p^.First + p^.Count);
    if b > a then
    begin
      joined := False;
      if (ItemCount > 0) and (b <= contentEnd) and ((p^.Kind = rfkText) or
        ((AMode = jmAll) and (p^.Kind = rfkSpace))) then
      begin
        it := @Items[ItemCount - 1];
        q := @Pieces[it^.Piece];
        if ((it^.Kind = rfkText) or ((AMode = jmAll) and (it^.Kind = rfkSpace))) and
          (q^.Font = p^.Font) and (q^.Format = p^.Format) and (it^.First + it^.Count = a) and
          (it^.Count + (b - a) <= CRichMaxPieceChars) then
        begin
          Inc(it^.Count, b - a);
          it^.Kind := rfkText;
          it^.Width := -1;     // measured below, as one string
          joined := True;
        end;
      end;
      if not joined then
      begin
        if ItemCount = System.Length(Items) then SetLength(Items, ItemCount * 2 + 16);
        it := @Items[ItemCount];
        Inc(ItemCount);
        it^.Piece := k;
        it^.Kind := p^.Kind;
        it^.First := a;
        it^.Count := b - a;
        it^.Width := MeasureRange(k, a, b);
        it^.X := 0;
        it^.Stretch := 0;
        it^.StretchGaps := 0;
        it^.StretchFirst := 0;
      end;
    end;
    Inc(k);
  end;
  for a := 0 to ItemCount - 1 do
  begin
    if Items[a].Width < 0 then
    begin
      if AMode = jmChars then
        Items[a].Width := SegmentsWidth(Pieces[Items[a].Piece].Font, Items[a].First,
          Items[a].First + Items[a].Count)
      else
        Items[a].Width := L.MeasureText(Pieces[Items[a].Piece].Font,
          RangeText(Items[a].First, Items[a].First + Items[a].Count));
    end;
    Items[a].Natural := Items[a].Width;
  end;
end;

{ Lays out [AStart, AEnd) as one line at ATop and moves ATop below it. }
procedure TParaBuilder.EmitLine(AStart, AEnd, AK: Integer; ALeft: Integer; var ATop: Integer;
  AForced, ALast: Boolean; AEmptyFormat: TTyCharFormatId);
var
  i, x, stop, tabItem, segStart, segW, decW, tw, xTab, lastTab: Integer;
  contentEnd, contentRight, avail, off, extra, gaps, spaces, done, add, cum: Integer;
  maxA, maxD, maxL, natural, h, k: Integer;
  al: TTyTabAlign;
  ld: TTyTabLeader;
  decFound: Boolean;
  justify: Boolean;
  mode: TJoinMode;
  c, j, j0: Integer;
  p: ^TPiece;
  it: ^TItem;
  ln: ^TTyRichLine;
  fr: ^TTyRichFragment;
  m: TTyRichFontMetrics;
  ff: TTyRichFormatFont;
  leaders: array of TTyTabLeader;

  procedure CloseTab;
  var
    k: Integer;
  begin
    if tabItem < 0 then Exit;
    case al of
      ttaRight: tw := stop - xTab - segW;
      ttaCenter: tw := stop - xTab - segW div 2;
      ttaDecimal: if decFound then tw := stop - xTab - decW else tw := stop - xTab - segW;
    else
      tw := stop - xTab;
    end;
    if tw < 0 then tw := 0;
    Items[tabItem].Width := tw;
    for k := segStart to i - 1 do Inc(Items[k].X, tw);
    x := xTab + tw + segW;
    tabItem := -1;
  end;

begin
  justify := (Pf.Align = paraJustify) and not ALast and not AForced and (RightPx < CUnlimited);
  { A justified line is stretched at its spaces after the last tab - then its words stay
    whole fragments - or, with none there, between its characters, where it may break: then
    its text is joined into fragments cut into segments. Either way a fragment per word or
    per run, not per character. }
  mode := jmAll;
  if justify then
  begin
    k := AEnd;
    while (k > AStart) and (Kind[k - 1] in [ckSpace, ckBreak]) do Dec(k);
    mode := jmChars;
    for i := k - 1 downto AStart do
      if Kind[i] = ckTab then Break
      else if Kind[i] = ckSpace then
      begin
        mode := jmWords;
        Break;
      end;
  end;
  if AEnd > AStart then LayLine(AStart, AEnd, PieceAt(AStart, AK), mode)
  else ItemCount := 0;
  leaders := nil;
  SetLength(leaders, ItemCount);
  // positions, tabs included
  x := ALeft;
  tabItem := -1;
  lastTab := -1;
  segW := 0;
  segStart := 0;
  decW := 0;
  decFound := False;
  xTab := 0;
  stop := 0;
  al := ttaLeft;
  i := 0;
  while i < ItemCount do
  begin
    it := @Items[i];
    p := @Pieces[it^.Piece];
    leaders[i] := ttlNone;
    if it^.Kind = rfkTab then
    begin
      CloseTab;
      lastTab := i;
      NextStop(x, stop, al, ld);
      // as FindLineEnd: only the line's first item meets a stop past the edge, and stops there
      if (RightPx < CUnlimited) and (stop > RightPx) then stop := Max(x, RightPx);
      leaders[i] := ld;
      it^.X := x;
      if al = ttaLeft then
      begin
        it^.Width := stop - x;
        x := stop;
      end
      else
      begin
        tabItem := i;
        xTab := x;
        segW := 0;
        segStart := i + 1;
        decFound := False;
        decW := 0;
        it^.Width := 0;
      end;
      Inc(i);
      Continue;
    end;
    if tabItem >= 0 then
    begin
      it^.X := xTab + segW;
      if (al = ttaDecimal) and not decFound and (it^.Kind = rfkText) then
        for k := it^.First to it^.First + it^.Count - 1 do
          if Cp[k] = Ord('.') then
          begin
            decFound := True;
            // the item may be several pieces joined: measured up to the point as one string
            decW := segW + L.MeasureText(p^.Font, RangeText(it^.First, k));
            Break;
          end;
      Inc(segW, it^.Width);
    end
    else
    begin
      it^.X := x;
      Inc(x, it^.Width);
    end;
    Inc(i);
  end;
  CloseTab;
  // the content ends before the trailing spaces (and the U+000B)
  contentEnd := ItemCount - 1;
  while (contentEnd >= 0) and (Items[contentEnd].Kind in [rfkSpace, rfkBreak]) do
    Dec(contentEnd);
  if contentEnd >= 0 then contentRight := Items[contentEnd].X + Items[contentEnd].Width
  else contentRight := ALeft;
  // alignment
  off := 0;
  if RightPx < CUnlimited then
  begin
    avail := RightPx - ALeft;
    case Pf.Align of
      paraCenter: off := (avail - (contentRight - ALeft)) div 2;
      paraRight: off := avail - (contentRight - ALeft);
    end;
    if off < 0 then off := 0;
  end;
  if justify and (contentEnd >= 0) then
  begin
    extra := RightPx - contentRight;
    if extra > 0 then
    begin
      // the spaces between the last tab and the content's end take it, by their characters;
      // a line with none (CJK) takes it between its characters, where it may break
      spaces := 0;
      gaps := 0;
      for i := lastTab + 1 to contentEnd do
        if Items[i].Kind = rfkSpace then Inc(spaces, Items[i].Count);
      done := 0;
      cum := 0;
      if spaces > 0 then
      begin
        for i := lastTab + 1 to ItemCount - 1 do
        begin
          Inc(Items[i].X, done);
          if (i <= contentEnd) and (Items[i].Kind = rfkSpace) then
          begin
            Inc(cum, Items[i].Count);
            add := Int64(extra) * cum div spaces - done;
            Inc(Items[i].Width, add);
            Inc(done, add);
          end;
        end;
      end
      else
      begin
        { the break opportunities after the last tab: between items, and inside the text
          items (their segments); the k-th gets extra * k div gaps - extra * (k - 1) div gaps }
        gaps := 0;
        for i := lastTab + 1 to contentEnd do
        begin
          if (i >= lastTab + 2) and (Brk[Items[i].First] <> 0) then Inc(gaps);
          if Items[i].Kind = rfkText then
            for c := Items[i].First + 1 to Items[i].First + Items[i].Count - 1 do
              if Brk[c] <> 0 then Inc(gaps);
        end;
        if gaps > 0 then
        begin
          j := 0;
          for i := lastTab + 1 to ItemCount - 1 do
          begin
            it := @Items[i];
            if i > contentEnd then
            begin
              Inc(it^.X, extra);
              Continue;
            end;
            if (i >= lastTab + 2) and (Brk[it^.First] <> 0) then Inc(j);
            j0 := j;
            Inc(it^.X, Int64(extra) * j div gaps);
            if it^.Kind = rfkText then
            begin
              for c := it^.First + 1 to it^.First + it^.Count - 1 do
                if Brk[c] <> 0 then Inc(j);
              if j > j0 then
              begin
                it^.Stretch := extra;
                it^.StretchGaps := gaps;
                it^.StretchFirst := j0;
                Inc(it^.Width, Int64(extra) * j div gaps - Int64(extra) * j0 div gaps);
              end;
            end;
          end;
        end;
      end;
      // the content reaches the right edge now
      if (spaces > 0) or (gaps > 0) then contentRight := RightPx;
    end;
  end;
  if mode = jmChars then
    for i := 0 to ItemCount - 1 do
      if (Items[i].Kind = rfkText) and (Items[i].StretchGaps = 0) then
        for c := Items[i].First + 1 to Items[i].First + Items[i].Count - 1 do
          if Brk[c] <> 0 then
          begin
            // measured as its segments: drawn so too, with nothing between them
            Items[i].StretchGaps := 1;
            Break;
          end;
  // metrics
  maxA := 0;
  maxD := 0;
  maxL := 0;
  if ItemCount = 0 then
  begin
    ff := L.FormatFont(AEmptyFormat, PPI, Zoom);
    m := Dev.Metrics(ff.Font);
    maxA := m.Ascent - ff.Shift;
    maxD := m.Descent + ff.Shift;
    maxL := m.Leading;
  end;
  for i := 0 to ItemCount - 1 do
  begin
    p := @Pieces[Items[i].Piece];
    if p^.Asc > maxA then maxA := p^.Asc;
    if p^.Desc > maxD then maxD := p^.Desc;
    if p^.Lead > maxL then maxL := p^.Lead;
  end;
  natural := maxA + maxD + maxL;
  case Pf.LineSpacing of
    ls115: h := Round(natural * 1.15);
    ls15: h := Round(natural * 1.5);
    lsDouble: h := natural * 2;
    lsExact: h := Px(Pf.LineSpacingValue);
    lsAtLeast: h := Max(natural, Px(Pf.LineSpacingValue));
  else
    h := natural;
  end;
  if h < 1 then h := 1;
  // the line
  with Layout do
  begin
    if FLineCount = System.Length(FLines) then SetLength(FLines, FLineCount * 2 + 4);
    ln := @FLines[FLineCount];
    Inc(FLineCount);
    ln^.First := AStart;
    ln^.Count := AEnd - AStart;
    ln^.Top := ATop;
    ln^.Height := h;
    // what the spacing adds goes above the text
    ln^.Baseline := ATop + h - maxD - maxL;
    ln^.Left := ALeft + off;
    ln^.ContentWidth := contentRight - ALeft;
    ln^.Forced := AForced;
    ln^.FirstFrag := FFragCount;
    ln^.FragCount := ItemCount;
    if ItemCount > 0 then ln^.EndX := Items[ItemCount - 1].X + Items[ItemCount - 1].Width + off
    else ln^.EndX := ALeft + off;
    if contentRight + off > FWidth then FWidth := contentRight + off;
    if FFragCount + ItemCount > System.Length(FFrags) then
      SetLength(FFrags, (FFragCount + ItemCount) * 2 + 8);
    for i := 0 to ItemCount - 1 do
    begin
      it := @Items[i];
      p := @Pieces[it^.Piece];
      fr := @FFrags[FFragCount];
      Inc(FFragCount);
      fr^.Kind := it^.Kind;
      fr^.First := it^.First;
      fr^.Count := it^.Count;
      fr^.X := it^.X + off;
      fr^.Width := it^.Width;
      if it^.Kind = rfkSpace then
        fr^.Natural := MeasureRange(it^.Piece, it^.First, it^.First + it^.Count)
      else if it^.Kind = rfkText then
        fr^.Natural := it^.Natural
      else
        fr^.Natural := it^.Width;
      if (it^.Kind = rfkSpace) and not justify then fr^.Natural := fr^.Width;
      fr^.Stretch := it^.Stretch;
      fr^.StretchGaps := it^.StretchGaps;
      fr^.StretchFirst := it^.StretchFirst;
      fr^.Font := p^.Font;
      fr^.Format := p^.Format;
      fr^.Shift := p^.Shift;
      fr^.Ascent := p^.Asc;
      fr^.Descent := p^.Desc;
      fr^.ByteStart := Bo[it^.First];
      fr^.ByteLen := Bo[it^.First + it^.Count] - Bo[it^.First];
      fr^.Text := p^.Text;
      fr^.Leader := leaders[i];
      fr^.Obj := p^.Obj;
      if fr^.Obj <> nil then fr^.Obj.AddRef;
    end;
  end;
  // a block's height stops at CRichMaxBlockPx, it never wraps negative
  ATop := SatAdd(ATop, h);
end;

{ A list paragraph's marker, put in Layout.FMarker; returns where the first line's text
  starts. The marker goes where WordPad (RichEdit) puts it - at the first line's indent - and
  is followed by what RichEdit's own tab after it does: to the left indent when that is
  further right, else to the next tab stop. In the first run's font (its size included, a
  super- or subscript's shift not), a missing bullet glyph from the fallback fonts. }
function TParaBuilder.MakeMarker: Integer;
var
  fmt: TTyCharFormatId;
  f: TTyRichFontId;
  m: TTyRichFontMetrics;
  xEnd, stop: Integer;
  al: TTyTabAlign;
  ld: TTyTabLeader;
  code: Cardinal;
  mk: ^TTyRichFragment;
begin
  Result := Max(0, LeftPx + FirstPx);
  if Pf.List.Kind = lkNone then Exit;
  if System.Length(Runs) > 0 then fmt := Runs[0].Format else fmt := 0;
  f := L.FormatFont(fmt, PPI, Zoom).Font;
  mk := @Layout.FMarker;
  mk^.Kind := rfkText;
  mk^.First := 0;
  mk^.Count := 0;
  mk^.Text := TyRichListMarkerText(Pf.List.Kind, Pf.List.Level, ListNumber);
  DecodeAt(mk^.Text, 1, code);
  if not L.GlyphIn(f, code) then f := L.FallbackFor(f, code);
  mk^.Font := f;
  mk^.Format := fmt;
  mk^.Shift := 0;
  m := Dev.Metrics(f);
  mk^.Ascent := m.Ascent;
  mk^.Descent := m.Descent;
  mk^.X := Result;
  mk^.Width := L.MeasureText(f, mk^.Text);
  mk^.Natural := mk^.Width;
  mk^.ByteStart := 0;
  mk^.ByteLen := 0;
  mk^.Obj := nil;
  mk^.Leader := ttlNone;
  Layout.FHasMarker := True;
  Layout.FNumbered := not (Pf.List.Kind in [lkNone, lkBullet]);
  xEnd := mk^.X + mk^.Width;
  if xEnd < LeftPx then Exit(LeftPx);
  NextStop(xEnd, stop, al, ld);
  Result := stop;
end;

{ The line under a cut paragraph: how many characters are not shown, in the paragraph's (its
  first run's) font, at the left indent; no positions, so never hit or selected. }
procedure TParaBuilder.MakeNotice(var ATop: Integer; AFormat: TTyCharFormatId);
var
  nt: ^TTyRichFragment;
  m: TTyRichFontMetrics;
begin
  nt := @Layout.FNotice;
  nt^.Kind := rfkText;
  nt^.First := N;
  nt^.Count := 0;
  nt^.Text := Format(rsRichEditParaNotShown, [IntToStr(Int64(FullLen) - N)]);
  nt^.Font := L.FormatFont(AFormat, PPI, Zoom).Font;
  nt^.Format := AFormat;
  nt^.Shift := 0;
  m := Dev.Metrics(nt^.Font);
  nt^.Ascent := m.Ascent;
  nt^.Descent := m.Descent;
  nt^.X := LeftPx;
  nt^.Width := L.MeasureText(nt^.Font, nt^.Text);
  nt^.Natural := nt^.Width;
  Layout.FNoticeTop := ATop;
  Layout.FNoticeBaseline := SatAdd(ATop, m.Ascent);
  ATop := SatAdd(ATop, Max(1, m.Ascent + m.Descent + m.Leading));
  Layout.FTruncated := True;
end;

procedure TParaBuilder.Run;
var
  s, e, k, top, left, firstLeft: Integer;
  i, k0: Integer;
  tabs: TTyTabStops;
  ta: TTyTabAlign;
  tl: TTyTabLeader;
  emptyFmt: TTyCharFormatId;
begin
  LeftPx := Max(0, Px(Pf.LeftIndent));
  FirstPx := Px(Pf.FirstIndent);
  if Width <= CRichNoWrap then
    RightPx := CUnlimited
  else
    RightPx := Max(LeftPx + 1, Max(LeftPx + FirstPx + 1, Width - Px(Pf.RightIndent)));
  DefTab := Max(1, Px(CRichDefaultTabTwips));
  tabs := Pf.Tabs;
  SetLength(TabPos, System.Length(tabs));
  SetLength(TabAlign, System.Length(tabs));
  SetLength(TabLeader, System.Length(tabs));
  for i := 0 to High(tabs) do
  begin
    TabPos[i] := Px(tabs[i].Position);
    TabAlign[i] := tabs[i].Align;
    TabLeader[i] := tabs[i].Leader;
  end;
  // sorted by position (the model keeps them in file order)
  for s := 1 to High(TabPos) do
    for e := s downto 1 do
      if TabPos[e] < TabPos[e - 1] then
      begin
        k := TabPos[e]; TabPos[e] := TabPos[e - 1]; TabPos[e - 1] := k;
        ta := TabAlign[e]; TabAlign[e] := TabAlign[e - 1]; TabAlign[e - 1] := ta;
        tl := TabLeader[e]; TabLeader[e] := TabLeader[e - 1]; TabLeader[e - 1] := tl;
      end;
  MapRuns;
  FindClusters;
  { A paragraph past CRichMaxParaLayoutChars: what was read of it (one character past the
    cap, so the cap's cluster is known) is cut at the start of the cluster the cap is in; one
    cluster longer than the cap (nothing to cut at) is cut at the cap. }
  if FullLen > CRichMaxParaLayoutChars then
  begin
    e := Min(N, CRichMaxParaLayoutChars);
    while (e > 0) and not ClStart[e] do Dec(e);
    if e = 0 then e := Min(N, CRichMaxParaLayoutChars);
    N := e;
    Txt := Copy(Txt, 1, Bo[N]);
  end;
  FindBreaks;
  ResolveFonts;
  MakePieces;
  FirstLine := True;
  firstLeft := MakeMarker;
  if System.Length(Runs) > 0 then emptyFmt := Runs[0].Format else emptyFmt := 0;
  Layout.FSpaceBefore := Max(0, Px(Pf.SpaceBefore));
  Layout.FSpaceAfter := Max(0, Px(Pf.SpaceAfter));
  top := Layout.FSpaceBefore;
  s := 0;
  k := 0;
  if N = 0 then
    EmitLine(0, 0, 0, firstLeft, top, False, True, emptyFmt)
  else
    while s < N do
    begin
      if s = 0 then left := firstLeft else left := LeftPx;
      FirstLine := s = 0;
      k0 := k;
      e := FindLineEnd(s, k, left);
      if e <= s then e := ClusterEnd(s);
      EmitLine(s, e, k0, left, top, Kind[e - 1] = ckBreak, e >= N, CFmt[e - 1]);
      s := e;
      // a paragraph that ends with U+000B has an empty line after it, for the caret
      if (s = N) and (Kind[N - 1] = ckBreak) then
      begin
        FirstLine := False;
        EmitLine(N, N, k, LeftPx, top, False, True, CFmt[N - 1]);
      end;
    end;
  if N < FullLen then MakeNotice(top, emptyFmt);
  Layout.FHeight := SatAdd(top, Layout.FSpaceAfter);
  SetLength(Layout.FLines, Layout.FLineCount);
  SetLength(Layout.FFrags, Layout.FFragCount);
end;

{ ---- pictures ---- }

type
  { A picture the layouter drew or prepared. Tried: its decode was tried (Failed: it cannot be
    shown - no bytes to show, a format the header reader does not know, over the decode
    budget, bytes that do not decode - and is a placeholder at every size). ImgW x ImgH: the
    decoded image's size, known also after Image was let go: once a reduced copy (Scaled) is
    made, the full image is freed and decoded again only for a size that needs it. BadW x
    BadH: a reduction that failed at that size (a placeholder there, not tried again). Pass:
    the paint pass it was last used in (never evicted inside it). It holds a counted reference
    to the picture, so the key stays this picture's for as long as the entry lives. }
  TTyPictureEntry = class
  public
    Pic: TTyRichPicture;
    Tried, Failed: Boolean;
    ImgW, ImgH: Integer;
    Image: TBGRABitmap;
    Scaled: TBGRABitmap;
    BadW, BadH: Integer;
    Bytes: Int64;
    Pass: Int64;
    Prev, Next: TTyPictureEntry;
    destructor Destroy; override;
  end;

  { How a picture is drawn at a size: a placeholder; its decoded image as it is; its reduced
    copy; the decoded image stretched, for the part inside the clip only (an enlargement, or a
    reduction past the scaled-copy budget). }
  TPictureDraw = (pdPlaceholder, pdImage, pdScaled, pdStretch);

destructor TTyPictureEntry.Destroy;
begin
  Scaled.Free;
  Image.Free;
  if Pic <> nil then Pic.Release;
  inherited Destroy;
end;

function LE16(const B: TBytes; AAt: PtrInt): Cardinal; inline;
begin
  if (AAt < 0) or (AAt + 2 > System.Length(B)) then Exit(0);
  Result := Cardinal(B[AAt]) or (Cardinal(B[AAt + 1]) shl 8);
end;

function LE32(const B: TBytes; AAt: PtrInt): Cardinal; inline;
begin
  if (AAt < 0) or (AAt + 4 > System.Length(B)) then Exit(0);
  Result := Cardinal(B[AAt]) or (Cardinal(B[AAt + 1]) shl 8) or (Cardinal(B[AAt + 2]) shl 16) or
    (Cardinal(B[AAt + 3]) shl 24);
end;

{ The BITMAPFILEHEADER a DIB (a BITMAPINFO and its bits, as a metafile carries one) needs to be
  read as a .bmp file: 'BM', the file's size, and where the bits start - after the header,
  the colour table and, for bit fields, the masks. }
procedure WriteBmpFileHeader(AStream: TStream; const AData: TBytes; AStart, ACount: Integer);
var
  hs, bits, comp, used, entry, pal, off: Cardinal;
  h: array[0..13] of Byte;

  procedure Put32(AAt: Integer; AValue: Cardinal);
  begin
    h[AAt] := AValue and $FF;
    h[AAt + 1] := (AValue shr 8) and $FF;
    h[AAt + 2] := (AValue shr 16) and $FF;
    h[AAt + 3] := (AValue shr 24) and $FF;
  end;

begin
  hs := LE32(AData, AStart);
  if hs = 12 then
  begin
    // BITMAPCOREHEADER: three bytes a colour
    bits := LE16(AData, AStart + 10);
    comp := 0;
    used := 0;
    entry := 3;
  end
  else
  begin
    bits := LE16(AData, AStart + 14);
    comp := LE32(AData, AStart + 16);
    if hs >= 36 then used := LE32(AData, AStart + 32) else used := 0;
    entry := 4;
  end;
  if (used = 0) and (bits >= 1) and (bits <= 8) then used := Cardinal(1) shl bits;
  if used > 65536 then used := 0;
  pal := used * entry;
  // BI_BITFIELDS / BI_ALPHABITFIELDS after a 40-byte header: the masks follow it
  if (hs = 40) and (comp = 3) then Inc(pal, 12)
  else if (hs = 40) and (comp = 6) then Inc(pal, 16);
  off := 14 + hs + pal;
  FillChar(h, SizeOf(h), 0);
  h[0] := Ord('B');
  h[1] := Ord('M');
  Put32(2, 14 + Cardinal(ACount));
  Put32(10, off);
  AStream.WriteBuffer(h, SizeOf(h));
end;

{ The bytes a decoder is handed for the picture: what DisplayData says can be shown (a DIB with
  a BITMAPFILEHEADER put in front); nil when nothing can. }
function PictureStream(APicture: TTyRichPicture): TMemoryStream;
var
  fmt: TTyRichPictureFormat;
  start, count: Integer;
  data: TBytes;
begin
  Result := nil;
  if not APicture.DisplayData(fmt, start, count) then Exit;
  data := APicture.Data;
  if (start < 0) or (count <= 0) or (Int64(start) + count > System.Length(data)) then Exit;
  Result := TMemoryStream.Create;
  try
    if fmt = rpfDib then WriteBmpFileHeader(Result, data, start, count);
    Result.WriteBuffer(data[start], count);
    Result.Position := 0;
  except
    FreeAndNil(Result);
    raise;
  end;
end;

function BE16At(P: PByte; AAt, ACount: PtrInt): Int64; inline;
begin
  if (AAt < 0) or (AAt + 2 > ACount) then Exit(-1);
  Result := (Int64(P[AAt]) shl 8) or P[AAt + 1];
end;

function BE32At(P: PByte; AAt, ACount: PtrInt): Int64; inline;
begin
  if (AAt < 0) or (AAt + 4 > ACount) then Exit(-1);
  Result := (Int64(P[AAt]) shl 24) or (Int64(P[AAt + 1]) shl 16) or (Int64(P[AAt + 2]) shl 8) or
    P[AAt + 3];
end;

function LE32At(P: PByte; AAt, ACount: PtrInt): Int64; inline;
begin
  if (AAt < 0) or (AAt + 4 > ACount) then Exit(-1);
  Result := Int64(P[AAt]) or (Int64(P[AAt + 1]) shl 8) or (Int64(P[AAt + 2]) shl 16) or
    (Int64(P[AAt + 3]) shl 24);
end;

{ The size an image file says it has, read from its header before anything is decoded: PNG
  (IHDR), JPEG (the first start-of-frame marker), BMP (its DIB header; a negative height is a
  top-down bitmap). False for anything else, or a header cut short: such bytes are not handed
  to a decoder, which would find its size only by allocating it. }
function ImageHeaderSize(P: PByte; ACount: PtrInt; out AWidth, AHeight: Int64;
  out AJpeg: Boolean): Boolean;
var
  i, len: Int64;
  m: Byte;
  hs: Int64;
begin
  Result := False;
  AWidth := 0;
  AHeight := 0;
  AJpeg := False;
  if ACount < 4 then Exit;
  if (P[0] = $89) and (P[1] = $50) and (P[2] = $4E) and (P[3] = $47) then
  begin
    if (ACount < 24) or (P[12] <> Ord('I')) or (P[13] <> Ord('H')) or (P[14] <> Ord('D')) or
      (P[15] <> Ord('R')) then
      Exit;
    AWidth := BE32At(P, 16, ACount);
    AHeight := BE32At(P, 20, ACount);
  end
  else if (P[0] = $FF) and (P[1] = $D8) then
  begin
    AJpeg := True;
    i := 2;
    while i + 4 <= ACount do
    begin
      if P[i] <> $FF then Exit;
      // fill bytes before a marker
      while (i < ACount) and (P[i] = $FF) do Inc(i);
      if i >= ACount then Exit;
      m := P[i];
      Inc(i);
      if (m = $01) or ((m >= $D0) and (m <= $D7)) then Continue;   // no length
      if (m = $D9) or (m = $DA) then Exit;   // the image ended, or its data began: no frame
      len := BE16At(P, i, ACount);
      if len < 2 then Exit;
      if (m >= $C0) and (m <= $CF) and (m <> $C4) and (m <> $C8) and (m <> $CC) then
      begin
        AHeight := BE16At(P, i + 3, ACount);
        AWidth := BE16At(P, i + 5, ACount);
        Break;
      end;
      Inc(i, len);
    end;
  end
  else if (P[0] = Ord('B')) and (P[1] = Ord('M')) then
  begin
    hs := LE32At(P, 14, ACount);
    if hs = 12 then
    begin
      if ACount < 26 then Exit;
      AWidth := Int64(P[18]) or (Int64(P[19]) shl 8);
      AHeight := Int64(P[20]) or (Int64(P[21]) shl 8);
    end
    else if hs >= 40 then
    begin
      AWidth := LE32At(P, 18, ACount);
      AHeight := LE32At(P, 22, ACount);
      if AWidth >= $80000000 then AWidth := AWidth - $100000000;
      if AHeight >= $80000000 then AHeight := AHeight - $100000000;
      AHeight := Abs(AHeight);
    end
    else
      Exit;
  end
  else
    Exit;
  Result := (AWidth > 0) and (AHeight > 0);
end;

function ImageBytes(AImage: TBGRABitmap): Int64; inline;
begin
  if AImage = nil then Exit(0);
  Result := Int64(AImage.Width) * AImage.Height * SizeOf(TBGRAPixel);
end;

procedure DrawPlaceholder(ATarget: TBGRABitmap; const ABox: TRect; ALinePx: Integer;
  const AStyle: TTyRichPaintStyle);
var
  t: Integer;
begin
  ATarget.FillRect(ABox.Left, ABox.Top, ABox.Right, ABox.Bottom, AStyle.PlaceholderFill,
    dmDrawWithTransparency);
  t := Max(1, Min(ALinePx, Min(ABox.Right - ABox.Left, ABox.Bottom - ABox.Top) div 2));
  ATarget.FillRect(ABox.Left, ABox.Top, ABox.Right, ABox.Top + t, AStyle.PlaceholderFrame,
    dmDrawWithTransparency);
  ATarget.FillRect(ABox.Left, ABox.Bottom - t, ABox.Right, ABox.Bottom, AStyle.PlaceholderFrame,
    dmDrawWithTransparency);
  ATarget.FillRect(ABox.Left, ABox.Top + t, ABox.Left + t, ABox.Bottom - t,
    AStyle.PlaceholderFrame, dmDrawWithTransparency);
  ATarget.FillRect(ABox.Right - t, ABox.Top + t, ABox.Right, ABox.Bottom - t,
    AStyle.PlaceholderFrame, dmDrawWithTransparency);
end;

function TyRichDefaultPaintStyle: TTyRichPaintStyle;
begin
  Result.TextColor := BGRABlack;
  Result.SelectionBack := BGRA(51, 153, 255, 255);
  Result.SelectionText := BGRAWhite;
  Result.PlaceholderFill := BGRA(240, 240, 240, 255);
  Result.PlaceholderFrame := BGRA(160, 160, 160, 255);
  Result.ObjectFrame := BGRA(51, 153, 255, 255);
  Result.TableBorder := BGRA(128, 128, 128, 255);
  Result.DeferPictures := False;
end;

{ ---- layouter: pictures ---- }

procedure TTyRichLayouter.PictureUnlink(AEntry: TObject);
var
  e: TTyPictureEntry;
begin
  e := TTyPictureEntry(AEntry);
  if e.Prev <> nil then e.Prev.Next := e.Next else FPicFirst := e.Next;
  if e.Next <> nil then e.Next.Prev := e.Prev else FPicLast := e.Prev;
  e.Prev := nil;
  e.Next := nil;
end;

procedure TTyRichLayouter.PicturePushFront(AEntry: TObject);
var
  e: TTyPictureEntry;
begin
  e := TTyPictureEntry(AEntry);
  e.Prev := nil;
  e.Next := TTyPictureEntry(FPicFirst);
  if FPicFirst <> nil then TTyPictureEntry(FPicFirst).Prev := e;
  FPicFirst := e;
  if FPicLast = nil then FPicLast := e;
end;

procedure TTyRichLayouter.PictureDrop(AEntry: TObject);
var
  e: TTyPictureEntry;
begin
  e := TTyPictureEntry(AEntry);
  PictureUnlink(e);
  FPictures.Remove(e.Pic);
  Dec(FPictureBytes, e.Bytes);
  e.Free;
end;

procedure TTyRichLayouter.PictureTrim(AKeep: TObject);
begin
  // the least recently used go first - never one used in the current paint pass
  while (FPicLast <> nil) and (FPicLast <> AKeep) and (FPictureBytes > FPictureLimit) and
    (TTyPictureEntry(FPicLast).Pass <> FPicturePass) do
    PictureDrop(FPicLast);
end;

procedure TTyRichLayouter.SetPictureLimit(AValue: Int64);
begin
  if AValue < 0 then AValue := 0;
  FPictureLimit := AValue;
  PictureTrim(FPicFirst);
end;

function TTyRichLayouter.PictureCacheCount: Integer;
begin
  Result := FPictures.Count;
end;

procedure TTyRichLayouter.BeginPaintPass;
begin
  Inc(FPicturePass);
  FPassByCaller := True;
end;

procedure TTyRichLayouter.PaintEnter;
begin
  // no caller counting passes: each outermost Paint (or a DrawPicture outside one) is one
  if (FPaintDepth = 0) and not FPassByCaller then Inc(FPicturePass);
  Inc(FPaintDepth);
end;

procedure TTyRichLayouter.PaintLeave;
begin
  if FPaintDepth > 0 then Dec(FPaintDepth);
end;

{ Lets EAccessViolation and EOutOfMemory through (a decoder's bug, a process out of memory:
  not what a picture's bytes are); anything else a decoder or the resampler raises means "this
  picture cannot be shown (at this size)". }
function PictureFatal(E: Exception): Boolean; inline;
begin
  Result := (E is EAccessViolation) or (E is EOutOfMemory);
end;

function TTyRichLayouter.DecodeImage(AStream: TStream; AJpegScale: Integer): TBGRABitmap;
var
  rd: TBGRAReaderJpeg;
begin
  Result := TBGRABitmap.Create;
  try
    if AJpegScale > 0 then
    begin
      rd := TBGRAReaderJpeg.Create;
      try
        rd.Scale := TJPEGScale(AJpegScale);
        Result.LoadFromStream(AStream, rd);
      finally
        rd.Free;
      end;
    end
    else
      Result.LoadFromStream(AStream);
  except
    Result.Free;
    raise;
  end;
end;

function TTyRichLayouter.ScaleImage(AImage: TBGRABitmap; AWidth, AHeight: Integer): TBGRABitmap;
begin
  AImage.ResampleFilter := rfBestQuality;
  Result := AImage.Resample(AWidth, AHeight, rmFineResample) as TBGRABitmap;
end;

{ What the entry costs to keep: the entry, its images, and the picture's bytes it holds - not
  for one that cannot be shown (a placeholder does not keep its bytes in use). }
procedure TTyRichLayouter.PictureRecount(AEntry: TObject);
var
  e: TTyPictureEntry;
  b: Int64;
begin
  e := TTyPictureEntry(AEntry);
  b := e.InstanceSize + ImageBytes(e.Image) + ImageBytes(e.Scaled);
  if not e.Failed then Inc(b, System.Length(e.Pic.Data));
  Inc(FPictureBytes, b - e.Bytes);
  e.Bytes := b;
end;

{ Decodes the entry's picture into Image (again, when it was let go). The size comes from the
  file's header first: over FPictureDecodeBudget pixels a JPEG is decoded reduced (1/2, 1/4,
  1/8, while decoding - the reader can do that cheaply), anything else is not decoded and is a
  placeholder; a header the reader cannot read is not handed to a decoder either. }
procedure TTyRichLayouter.PictureDecode(AEntry: TObject);
var
  e: TTyPictureEntry;
  st: TMemoryStream;
  w, h: Int64;
  jpeg: Boolean;
  sc: Integer;
  img: TBGRABitmap;
begin
  e := TTyPictureEntry(AEntry);
  e.Tried := True;
  st := PictureStream(e.Pic);
  if st = nil then
  begin
    e.Failed := True;
    Exit;
  end;
  img := nil;
  try
    Inc(FPictureDecodes);
    if not ImageHeaderSize(st.Memory, st.Size, w, h, jpeg) then
    begin
      e.Failed := True;
      Exit;
    end;
    sc := 0;
    while (sc < 3) and (((w + (Int64(1) shl sc) - 1) shr sc) * ((h + (Int64(1) shl sc) - 1) shr sc) >
      FPictureDecodeBudget) do
      Inc(sc);
    if ((w + (Int64(1) shl sc) - 1) shr sc) * ((h + (Int64(1) shl sc) - 1) shr sc) >
      FPictureDecodeBudget then
    begin
      e.Failed := True;
      Exit;
    end;
    if (sc > 0) and not jpeg then
    begin
      e.Failed := True;
      Exit;
    end;
    try
      img := DecodeImage(st, sc);
    except
      on E: Exception do
      begin
        if PictureFatal(E) then raise;
        img := nil;
      end;
    end;
    if (img <> nil) and ((img.Width <= 0) or (img.Height <= 0)) then FreeAndNil(img);
    if img = nil then
    begin
      e.Failed := True;
      Exit;
    end;
    Inc(FPictureDecodedPixels, Int64(img.Width) * img.Height);
    e.Image := img;
    e.ImgW := img.Width;
    e.ImgH := img.Height;
  finally
    st.Free;
  end;
end;

{ How drawing the entry at AWidth x AHeight goes (it has been tried): a placeholder when it
  cannot be shown or a reduction to that size failed; the image itself at its own size; a
  reduced copy when the box is no larger either way and within FPictureScaleBudget pixels;
  else the image stretched for the part inside the clip - an enlargement keeps no copy, it
  costs what the visible area costs. }
function TTyRichLayouter.PictureHow(AEntry: TObject; AWidth, AHeight: Integer): Integer;
var
  e: TTyPictureEntry;
begin
  e := TTyPictureEntry(AEntry);
  if e.Failed then Exit(Ord(pdPlaceholder));
  if (AWidth = e.ImgW) and (AHeight = e.ImgH) then Exit(Ord(pdImage));
  if (AWidth <= e.ImgW) and (AHeight <= e.ImgH) and
    (Int64(AWidth) * AHeight <= FPictureScaleBudget) then
  begin
    if (AWidth = e.BadW) and (AHeight = e.BadH) then Exit(Ord(pdPlaceholder));
    Exit(Ord(pdScaled));
  end;
  Result := Ord(pdStretch);
end;

{ The kept entry of APicture, made now when there is none (nothing decoded yet), moved to the
  front and marked used in the current paint pass. }
function TTyRichLayouter.PictureEntry(APicture: TTyRichPicture): TObject;
var
  o: TObject;
  e: TTyPictureEntry;
begin
  if FPictures.TryGetValue(APicture, o) then
  begin
    e := TTyPictureEntry(o);
    PictureUnlink(e);
    PicturePushFront(e);
  end
  else
  begin
    e := TTyPictureEntry.Create;
    e.Pic := APicture;
    APicture.AddRef;
    e.BadW := -1;
    e.BadH := -1;
    FPictures.Add(APicture, e);
    PicturePushFront(e);
    PictureRecount(e);
  end;
  e.Pass := FPicturePass;
  Result := e;
end;

{ Brings the entry to the state PictureReady calls ready for AWidth x AHeight: decoded the
  first time (never at layout), decoded again when the size needs the full image and it was
  let go, reduced once per size - after which the full image is let go - or found that it
  cannot be (remembered). }
procedure TTyRichLayouter.PictureMakeReady(AEntry: TObject; AWidth, AHeight: Integer);
var
  e: TTyPictureEntry;
  how: TPictureDraw;
  s: TBGRABitmap;
begin
  e := TTyPictureEntry(AEntry);
  try
    if not e.Tried then PictureDecode(e);
    how := TPictureDraw(PictureHow(e, AWidth, AHeight));
    case how of
      pdImage, pdStretch:
        if e.Image = nil then PictureDecode(e);
      pdScaled:
        if (e.Scaled = nil) or (e.Scaled.Width <> AWidth) or (e.Scaled.Height <> AHeight) then
        begin
          FreeAndNil(e.Scaled);
          if e.Image = nil then PictureDecode(e);
          if e.Image <> nil then
          begin
            Inc(FPictureScales);
            s := nil;
            try
              s := ScaleImage(e.Image, AWidth, AHeight);
            except
              on E: Exception do
              begin
                if PictureFatal(E) then raise;
                s := nil;
              end;
            end;
            if s = nil then
            begin
              // remembered, like a failed decode: a placeholder at this size
              e.BadW := AWidth;
              e.BadH := AHeight;
            end
            else
            begin
              e.Scaled := s;
              // shown reduced: the full image goes (decoded again for a size that needs it)
              FreeAndNil(e.Image);
            end;
          end;
        end;
    end;
  finally
    PictureRecount(e);
  end;
end;

function TTyRichLayouter.DrawPicture(ATarget: TBGRABitmap; APicture: TTyRichPicture;
  const ABox: TRect; ALinePx: Integer; const AStyle: TTyRichPaintStyle): Boolean;
var
  e: TTyPictureEntry;
  w, h: Integer;
  was: Int64;
begin
  Result := False;
  w := ABox.Right - ABox.Left;
  h := ABox.Bottom - ABox.Top;
  if (ATarget = nil) or (APicture = nil) or (w <= 0) or (h <= 0) then Exit;
  PaintEnter;
  try
    was := FPictureBytes;
    e := TTyPictureEntry(PictureEntry(APicture));
    PictureMakeReady(e, w, h);
    case TPictureDraw(PictureHow(e, w, h)) of
      pdImage:
        if e.Image <> nil then
        begin
          ATarget.PutImage(ABox.Left, ABox.Top, e.Image, dmDrawWithTransparency);
          Result := True;
        end;
      pdScaled:
        if e.Scaled <> nil then
        begin
          ATarget.PutImage(ABox.Left, ABox.Top, e.Scaled, dmDrawWithTransparency);
          Result := True;
        end;
      pdStretch:
        if e.Image <> nil then
        begin
          // the clip's part only: the target's ClipRect bounds what is computed
          ATarget.StretchPutImage(ABox, e.Image, dmDrawWithTransparency);
          Result := True;
        end;
    end;
    if not Result then DrawPlaceholder(ATarget, ABox, ALinePx, AStyle);
    // only what this draw added can push others out: a repaint of kept pictures evicts none
    if FPictureBytes > was then PictureTrim(e);
  finally
    PaintLeave;
  end;
end;

function TTyRichLayouter.PictureReady(APicture: TTyRichPicture; AWidth,
  AHeight: Integer): Boolean;
var
  o: TObject;
  e: TTyPictureEntry;
  fmt: TTyRichPictureFormat;
  start, count: Integer;
begin
  if (APicture = nil) or (AWidth <= 0) or (AHeight <= 0) then Exit(True);
  // never drawn: there is something to decode, unless nothing of it can be shown
  if not FPictures.TryGetValue(APicture, o) then
    Exit(not APicture.DisplayData(fmt, start, count));
  e := TTyPictureEntry(o);
  if not e.Tried then Exit(False);
  case TPictureDraw(PictureHow(e, AWidth, AHeight)) of
    pdPlaceholder: Result := True;
    pdImage, pdStretch: Result := e.Image <> nil;
  else
    Result := (e.Scaled <> nil) and (e.Scaled.Width = AWidth) and (e.Scaled.Height = AHeight);
  end;
end;

procedure TTyRichLayouter.PreparePicture(APicture: TTyRichPicture; AWidth, AHeight: Integer);
var
  e: TObject;
  was: Int64;
begin
  if (APicture = nil) or (AWidth <= 0) or (AHeight <= 0) then Exit;
  PaintEnter;
  try
    was := FPictureBytes;
    e := PictureEntry(APicture);
    PictureMakeReady(e, AWidth, AHeight);
    if FPictureBytes > was then PictureTrim(e);
  finally
    PaintLeave;
  end;
end;

procedure TTyRichLayouter.NoteSkippedPicture(APicture: TTyRichPicture; const ABox: TRect);
begin
  if FSkippedCount = System.Length(FSkipped) then
    SetLength(FSkipped, FSkippedCount * 2 + 8);
  APicture.AddRef;
  FSkipped[FSkippedCount].Picture := APicture;
  FSkipped[FSkippedCount].Box := ABox;
  Inc(FSkippedCount);
end;

procedure TTyRichLayouter.ClearSkippedPictures;
var
  i: Integer;
begin
  for i := 0 to FSkippedCount - 1 do FSkipped[i].Picture.Release;
  FSkipped := nil;
  FSkippedCount := 0;
end;

function TTyRichLayouter.TakeSkippedPictures: TTyRichSkippedPictures;
begin
  Result := Copy(FSkipped, 0, FSkippedCount);
  FSkipped := nil;
  FSkippedCount := 0;
end;

{ ---- the layouter ---- }

constructor TTyRichLayouter.Create(ADevice: TTyRichTextDevice; AOwnsDevice: Boolean);
begin
  inherited Create;
  FDevice := ADevice;
  FOwnsDevice := AOwnsDevice;
  FBaseFontSizeHalfPt := 20;
  FFallbackFonts := TStringList.Create;
  TyRichDefaultFallbackFonts(FFallbackFonts);
  FFallbackFonts.OnChange := @FallbackFontsChanged;
  FCache := specialize TDictionary<Integer, TTyBlockLayout>.Create;
  FMeasure := specialize TDictionary<string, Integer>.Create;
  FGlyphs := specialize TDictionary<Int64, Boolean>.Create;
  FFallback := specialize TDictionary<Int64, Integer>.Create;
  FFormatFonts := specialize TDictionary<Integer, TTyRichFormatFont>.Create;
  FOrdinals := specialize TDictionary<Integer, TTyRichListOrdinal>.Create;
  FListOfFormat := specialize TDictionary<Integer, TTyListFormat>.Create;
  FPictures := specialize TDictionary<Pointer, TObject>.Create;
  FPictureLimit := CRichPictureCacheBytes;
  FPictureDecodeBudget := CRichPictureMaxPixels;
  FPictureScaleBudget := CRichPictureMaxScaledPixels;
  FFontPPI := -1;
end;

destructor TTyRichLayouter.Destroy;
begin
  Clear;
  ClearSkippedPictures;
  FPictures.Free;
  FListOfFormat.Free;
  FOrdinals.Free;
  FFormatFonts.Free;
  FFallback.Free;
  FGlyphs.Free;
  FMeasureOld.Free;
  FMeasure.Free;
  FCache.Free;
  FFallbackFonts.Free;
  if FOwnsDevice then FDevice.Free;
  inherited Destroy;
end;

procedure TTyRichLayouter.SetDocument(AValue: TTyRichDocument);
begin
  Clear;
  FDoc := AValue;
end;

procedure TTyRichLayouter.SetBaseFontName(const AValue: string);
begin
  if FBaseFontName = AValue then Exit;
  FBaseFontName := AValue;
  ClearLayouts;
end;

procedure TTyRichLayouter.SetBaseFontSizeHalfPt(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FBaseFontSizeHalfPt = AValue then Exit;
  FBaseFontSizeHalfPt := AValue;
  ClearLayouts;
end;

procedure TTyRichLayouter.FallbackFontsChanged(Sender: TObject);
begin
  ClearLayouts;
end;

procedure TTyRichLayouter.SetOnFallbackFont(AValue: TTyRichFallbackEvent);
begin
  if (TMethod(AValue).Code = TMethod(FOnFallbackFont).Code) and
    (TMethod(AValue).Data = TMethod(FOnFallbackFont).Data) then
    Exit;
  FOnFallbackFont := AValue;
  // the answers found without it (or with the one before) are not its answers
  ClearLayouts;
end;

procedure TTyRichLayouter.LruUnlink(L: TTyBlockLayout);
begin
  if L.FLruPrev <> nil then L.FLruPrev.FLruNext := L.FLruNext else FLruFirst := L.FLruNext;
  if L.FLruNext <> nil then L.FLruNext.FLruPrev := L.FLruPrev else FLruLast := L.FLruPrev;
  L.FLruPrev := nil;
  L.FLruNext := nil;
end;

procedure TTyRichLayouter.LruPushFront(L: TTyBlockLayout);
begin
  L.FLruPrev := nil;
  L.FLruNext := FLruFirst;
  if FLruFirst <> nil then FLruFirst.FLruPrev := L;
  FLruFirst := L;
  if FLruLast = nil then FLruLast := L;
end;

procedure TTyRichLayouter.CacheDrop(L: TTyBlockLayout; AStale: Boolean);
begin
  LruUnlink(L);
  FCache.Remove(L.FFirstPara);
  Dec(FCachedChars, L.FCharCount);
  L.FInCache := False;
  if AStale then L.FStale := True;
  L.Release;
end;

procedure TTyRichLayouter.CacheInsert(L: TTyBlockLayout);
var
  old: TTyBlockLayout;
begin
  if FCache.TryGetValue(L.FFirstPara, old) then CacheDrop(old, False);
  FCache.Add(L.FFirstPara, L);
  LruPushFront(L);
  L.FInCache := True;
  Inc(FCachedChars, L.FCharCount);
end;

procedure TTyRichLayouter.CacheTrim(AKeep: TTyBlockLayout);
begin
  while (FLruLast <> nil) and (FLruLast <> AKeep) and
    ((FCache.Count > CLayoutCacheParas) or (FCachedChars > CLayoutCacheChars)) do
    CacheDrop(FLruLast, False);
end;

function TTyRichLayouter.CachedCount: Integer;
begin
  Result := FCache.Count;
end;

function TTyRichLayouter.CachedLayout(AIndex: Integer): TTyBlockLayout;
begin
  if not FCache.TryGetValue(AIndex, Result) then Result := nil;
end;

{ L stays in the cache across a change: it (and a row's paragraphs) is good at the new count. }
procedure Vouch(L: TTyBlockLayout; AGen: Int64);
var
  i: Integer;
begin
  L.FGen := AGen;
  if L is TTyRowLayout then
    for i := 0 to High(TTyRowLayout(L).FItems) do TTyRowLayout(L).FItems[i].Layout.FGen := AGen;
end;

procedure TTyRichLayouter.Clear;
begin
  ClearLayouts;
  // the decoded pictures, and the references held for them
  while FPicFirst <> nil do PictureDrop(FPicFirst);
end;

{ Every layout and everything measured goes; the decoded pictures stay (they depend on no
  font): what a change of the base font or of the fallback fonts clears. }
procedure TTyRichLayouter.ClearLayouts;
begin
  // what is held out of the cache cannot be found: it goes stale by the count
  Inc(FChangeGen);
  while FLruFirst <> nil do CacheDrop(FLruFirst, True);
  FMeasure.Clear;
  FreeAndNil(FMeasureOld);
  FMeasureBytes := 0;
  FMeasureOldBytes := 0;
  FGlyphs.Clear;
  FFallback.Clear;
  FFormatFonts.Clear;
  FOrdinals.Clear;
  FListOfFormat.Clear;
  FFontPPI := -1;
end;

procedure TTyRichLayouter.DropNumbersFrom(AFirst: Integer);
var
  gone: array of Integer;
  k, n, i: Integer;
begin
  if FOrdinals.Count = 0 then Exit;
  gone := nil;
  SetLength(gone, FOrdinals.Count);
  n := 0;
  for k in FOrdinals.Keys do
    if k >= AFirst then
    begin
      gone[n] := k;
      Inc(n);
    end;
  for i := 0 to n - 1 do FOrdinals.Remove(gone[i]);
end;

procedure TTyRichLayouter.Invalidate(AFirst, ACount: Integer);
var
  L, nx: TTyBlockLayout;
begin
  if ACount <= 0 then Exit;
  Inc(FChangeGen);
  // the numbers from here on may count differently now
  DropNumbersFrom(AFirst);
  L := FLruFirst;
  while L <> nil do
  begin
    nx := L.FLruNext;
    if ((L.FLastPara >= AFirst) and (L.FFirstPara < AFirst + ACount)) or
      (L.FNumbered and (L.FFirstPara >= AFirst)) then
      CacheDrop(L, True)
    else
      Vouch(L, FChangeGen);
    L := nx;
  end;
end;

procedure TTyRichLayouter.DocumentChanged(const AChange: TTyRichChange);
var
  L, nx: TTyBlockLayout;
  first, oldEnd, delta: Integer;
  moved: array of TTyBlockLayout;
  n, i: Integer;
  numbering: Boolean;
begin
  { Any change: a layout held out of the cache (evicted while held) cannot follow, so it goes
    stale by the count; the cached ones that stay are vouched for below. }
  Inc(FChangeGen);
  first := AChange.FirstPara;
  oldEnd := first + Max(AChange.OldParaCount, 1);
  delta := AChange.NewParaCount - AChange.OldParaCount;
  { Paragraphs that came or went, or a format that changed, may change the number of every
    list item after them; typing inside paragraphs does not. }
  numbering := (AChange.Kinds * [rckStructure, rckFormat] <> []) or (delta <> 0);
  if numbering then DropNumbersFrom(first);
  moved := nil;
  n := 0;
  L := FLruFirst;
  while L <> nil do
  begin
    nx := L.FLruNext;
    if (L.FLastPara >= first) and (L.FFirstPara < oldEnd) then
      CacheDrop(L, True)
    else if (L.FFirstPara >= oldEnd) and numbering and L.FNumbered then
      CacheDrop(L, True)
    else if (L.FFirstPara >= oldEnd) and (delta <> 0) then
    begin
      // it follows its paragraph to its new index: out of the map now, back in below
      FCache.Remove(L.FFirstPara);
      Inc(L.FFirstPara, delta);
      Inc(L.FLastPara, delta);
      if L is TTyRowLayout then
        for i := 0 to High(TTyRowLayout(L).FItems) do
          with TTyRowLayout(L).FItems[i].Layout do
          begin
            Inc(FFirstPara, delta);
            Inc(FLastPara, delta);
          end;
      if n = System.Length(moved) then SetLength(moved, n * 2 + 8);
      moved[n] := L;
      Inc(n);
      Vouch(L, FChangeGen);
    end
    else
      Vouch(L, FChangeGen);
    L := nx;
  end;
  for i := 0 to n - 1 do FCache.AddOrSetValue(moved[i].FFirstPara, moved[i]);
end;

procedure TTyRichLayouter.FontsFor(APPI: Integer; AZoom: Single);
begin
  if (FFontPPI = APPI) and (FFontZoom = AZoom) and (FFontName = FBaseFontName) and
    (FFontSize = FBaseFontSizeHalfPt) then Exit;
  FFormatFonts.Clear;
  FFontPPI := APPI;
  FFontZoom := AZoom;
  FFontName := FBaseFontName;
  FFontSize := FBaseFontSizeHalfPt;
end;

function TTyRichLayouter.FormatFont(AFormat: TTyCharFormatId; APPI: Integer;
  AZoom: Single): TTyRichFormatFont;
var
  f: TTyCharFormat;
  name: string;
  size, px: Integer;
begin
  FontsFor(APPI, AZoom);
  if FFormatFonts.TryGetValue(AFormat, Result) then Exit;
  if (FDoc <> nil) and (AFormat >= 0) and (AFormat < FDoc.Formats.CharCount) then
    f := FDoc.Formats.CharFormat(AFormat)
  else
    f := TyDefaultCharFormat;
  name := f.FontName;
  if name = '' then name := FBaseFontName;
  size := f.SizeHalfPt;
  if size <= 0 then size := FBaseFontSizeHalfPt;
  px := TyRichHalfPointsToPx(size, APPI, AZoom);
  Result.Shift := 0;
  case f.VertAlign of
    vaSuper:
      begin
        Result.Shift := -Round(px / 3);
        px := Max(1, Round(px * 2 / 3));
      end;
    vaSub:
      begin
        Result.Shift := Round(px / 6);
        px := Max(1, Round(px * 2 / 3));
      end;
  end;
  Result.Font := FDevice.ResolveFont(name, px, f.Style);
  FFormatFonts.Add(AFormat, Result);
end;

function TTyRichLayouter.GlyphIn(AFont: TTyRichFontId; ACode: Cardinal): Boolean;
var
  key: Int64;
begin
  key := (Int64(AFont) shl 32) or ACode;
  if FGlyphs.TryGetValue(key, Result) then Exit;
  Result := FDevice.HasGlyph(AFont, ACode);
  if FGlyphs.Count >= CRichMeasureCacheEntries then FGlyphs.Clear;
  FGlyphs.Add(key, Result);
end;

function TTyRichLayouter.FallbackFor(AFont: TTyRichFontId; ACode: Cardinal): TTyRichFontId;
var
  key: Int64;
  name, base: string;
  i: Integer;
  c: TTyRichFontId;
begin
  key := (Int64(AFont) shl 32) or ACode;
  if FFallback.TryGetValue(key, Result) then Exit;
  Result := AFont;
  base := FDevice.FontName(AFont);
  name := '';
  if Assigned(FOnFallbackFont) then FOnFallbackFont(Self, base, ACode, name);
  if name <> '' then
    Result := FDevice.ResolveFont(name, FDevice.FontPixelHeight(AFont), FDevice.FontStyle(AFont))
  else
    for i := 0 to FFallbackFonts.Count - 1 do
    begin
      if SameText(FFallbackFonts[i], base) then Continue;
      c := FDevice.ResolveFont(FFallbackFonts[i], FDevice.FontPixelHeight(AFont),
        FDevice.FontStyle(AFont));
      if GlyphIn(c, ACode) then
      begin
        Result := c;
        Break;
      end;
    end;
  // none has it: the character stays in its own font (the renderer's substitution, or a box)
  if FFallback.Count >= CRichMeasureCacheEntries then FFallback.Clear;
  FFallback.Add(key, Result);
end;

procedure TTyRichLayouter.WalkCollect(AIndex: Integer; AData: Pointer; ASrcOffset,
  ASrcBytes: Int64; var AContinue: Boolean);
begin
  FWalkData[AIndex - FWalkFirst] := AData;
  AContinue := AIndex < FWalkLast;
end;

function TTyRichLayouter.ListOfFormat(ADoc: TTyRichDocument;
  AFormat: TTyParaFormatId): TTyListFormat;
begin
  if FListOfFormat.TryGetValue(AFormat, Result) then Exit;
  Result := ADoc.Formats.ParaFormat(AFormat).List;
  FListOfFormat.Add(AFormat, Result);
end;

function TTyRichLayouter.ListNumber(ADoc: TTyRichDocument; AIndex: Integer;
  const AList: TTyListFormat): Int64;
var
  found: array of Integer;
  nFound, j, lo, k, chunk, i: Integer;
  startAt: Int64;
  e: TTyRichListOrdinal;
  lf: TTyListFormat;
  fmt: TTyParaFormatId;
  runs: TTyRunArray;
  cell: TTyRichCell;
  done, known: Boolean;
begin
  if AList.Kind in [lkNone, lkBullet] then Exit(0);
  if FOrdinals.TryGetValue(AIndex, e) and (e.Kind = AList.Kind) and (e.Level = AList.Level) then
    Exit(e.Number);
  found := nil;
  SetLength(found, 16);
  found[0] := AIndex;
  nFound := 1;
  startAt := AList.StartAt;
  known := False;
  Result := 0;
  done := False;
  j := AIndex - 1;
  chunk := 16;
  ADoc.BeginRead;
  try
    { Back in chunks, each read in one walk of the text (one descent, not a lookup per
      paragraph), growing so that a long list costs a few walks and a short one reads little
      past its start. }
    while (not done) and (j >= 0) do
    begin
      lo := Max(Max(0, j - chunk + 1), AIndex - CRichListWalkParas);
      if lo > j then Break;   // the cap
      FWalkFirst := lo;
      FWalkLast := j;
      SetLength(FWalkData, j - lo + 1);
      ADoc.Text.WalkParas(lo, @WalkCollect);
      for k := j downto lo do
      begin
        Inc(FListWalkSteps);
        // the value as it is when it is parsed; a paragraph not parsed yet is read (parsed)
        if not ADoc.ReadValue(FWalkData[k - lo], fmt, runs, cell) then
          fmt := ADoc.ParaFormatOf(k);
        lf := ListOfFormat(ADoc, fmt);
        if (lf.Kind = lkNone) or (lf.Level < AList.Level) then
        begin
          done := True;
          Break;
        end;
        if lf.Level > AList.Level then Continue;
        if lf.Kind <> AList.Kind then
        begin
          done := True;
          Break;
        end;
        if FOrdinals.TryGetValue(k, e) and (e.Kind = lf.Kind) and (e.Level = lf.Level) then
        begin
          Result := e.Number + nFound;
          known := True;
          done := True;
          Break;
        end;
        if nFound = System.Length(found) then SetLength(found, nFound * 2);
        found[nFound] := k;
        Inc(nFound);
        startAt := lf.StartAt;
      end;
      j := lo - 1;
      chunk := chunk * 2;
    end;
  finally
    ADoc.EndRead;
  end;
  if not known then Result := startAt + nFound - 1;
  if FOrdinals.Count + nFound > CRichListOrdinalCache then FOrdinals.Clear;
  e.Kind := AList.Kind;
  e.Level := AList.Level;
  for i := 0 to nFound - 1 do
  begin
    e.Number := Result - i;
    FOrdinals.AddOrSetValue(found[i], e);
  end;
end;

function TTyRichLayouter.MeasureText(AFont: TTyRichFontId; const AText: UTF8String): Integer;
var
  key: string;
begin
  if AText = '' then Exit(0);
  key := IntToStr(AFont) + #1 + AText;
  if FMeasure.TryGetValue(key, Result) then Exit;
  if (FMeasureOld <> nil) and FMeasureOld.TryGetValue(key, Result) then
  begin
    // brought forward: counted again in the newer half (the older one goes as a whole)
    FMeasure.AddOrSetValue(key, Result);
    Inc(FMeasureBytes, System.Length(key) + CMeasureEntryBytes);
    Exit;
  end;
  Result := FDevice.TextWidth(AFont, AText);
  if (FMeasure.Count >= CRichMeasureCacheEntries div 2) or
    (FMeasureBytes >= CRichMeasureCacheBytes div 2) then
  begin
    // the older half goes; what was used since it became the older half came forward
    FMeasureOld.Free;
    FMeasureOld := FMeasure;
    FMeasureOldBytes := FMeasureBytes;
    FMeasure := specialize TDictionary<string, Integer>.Create;
    FMeasureBytes := 0;
  end;
  FMeasure.AddOrSetValue(key, Result);
  Inc(FMeasureBytes, System.Length(key) + CMeasureEntryBytes);
end;

function TTyRichLayouter.MeasureCacheBytes: Int64;
begin
  Result := FMeasureBytes + FMeasureOldBytes;
end;

function TTyRichLayouter.EstimatedParaHeight(APPI: Integer; AZoom: Single): Integer;
var
  m: TTyRichFontMetrics;
begin
  m := FDevice.Metrics(FDevice.ResolveFont(FBaseFontName,
    TyRichHalfPointsToPx(FBaseFontSizeHalfPt, APPI, AZoom), []));
  Result := Max(1, m.Ascent + m.Descent + m.Leading);
end;

function TTyRichLayouter.BuildPara(ADoc: TTyRichDocument; AIndex, AWidth, APPI: Integer;
  AZoom: Single): TTyParaLayout;
var
  b: TParaBuilder;
  t: TTyRichText;
  start, len: TTyRichPos;
  text: RawByteString;
begin
  Result := TTyParaLayout.Create(Self);
  b := TParaBuilder.Create;
  try
    ADoc.BeginRead;
    try
      { the runs first: reading them parses the paragraph of a document that parses on demand;
        everything read here stays as it is until EndRead, and the layout takes its own
        references to the objects before that }
      b.Runs := ADoc.RunsOf(AIndex);
      b.Pf := ADoc.Formats.ParaFormat(ADoc.ParaFormatOf(AIndex));
      Result.FInCell := ADoc.CellAt(AIndex) <> nil;
      // a number reads the paragraphs before this one (in this read scope)
      b.ListNumber := ListNumber(ADoc, AIndex, b.Pf.List);
      t := ADoc.Text;
      start := t.ParaStart(AIndex);
      len := t.ParaLength(AIndex);
      // a paragraph past the cap: only what is laid out is read (and one character more)
      if len > CRichMaxParaLayoutChars then
        text := t.GetText(start, CRichMaxParaLayoutChars + 1)
      else
        text := t.GetText(start, len);
      b.L := Self;
      b.Dev := FDevice;
      b.Layout := Result;
      b.PPI := APPI;
      b.Zoom := AZoom;
      b.Width := AWidth;
      b.Decode(text, Min(len, CRichMaxParaLayoutChars + 1));
      if len > CRichMaxParaLayoutChars then b.FullLen := len else b.FullLen := b.N;
      Result.FLength := b.FullLen;
      Result.FFirstPara := AIndex;
      Result.FLastPara := AIndex;
      Result.FLayoutWidth := AWidth;
      Result.FPPI := APPI;
      Result.FZoom := AZoom;
      Result.FCharCount := b.FullLen + 1;
      b.Run;
      Result.FText := b.Txt;
      Result.FShown := b.N;
      // the positions laid out: the paragraph's, its end and separator included, unless cut
      if Result.FTruncated then Result.FShownChars := b.N
      else Result.FShownChars := Result.FCharCount;
      Result.TakePaintFormats(ADoc);
    finally
      ADoc.EndRead;
    end;
  except
    b.Free;
    Result.Release;
    raise;
  end;
  b.Free;
end;

function TTyRichLayouter.BuildRow(ADoc: TTyRichDocument; AFirst, ALast: Integer;
  ARow: TTyRichRow; AWidth, APPI: Integer; AZoom: Single): TTyRowLayout;
var
  R: TTyRowLayout;
  tbl: TTyRichTable;
  nc, i, j, k, o, ci, gap, g, inner, pos, rowH, padT, padB, off, y, cut, shift, lo, hi: Integer;
  prevTw, rightTw: Int64;
  cd: TTyRowCellDisplay;
  s: TTyRowCellSide;
  lastRow, haveNext: Boolean;
  bx: ^TTyRichCellBox;
  cell: TTyRichCell;
  P: TTyParaLayout;
  nextDisp: TTyRowDisplay;
  room: array of Boolean;

  function Px(ATwips: Int64): Integer;
  begin
    Result := TyRichTwipsToPx(ATwips, APPI, AZoom);
  end;

  function CellDisplay(const ADisp: TTyRowDisplay; AIndex: Integer): TTyRowCellDisplay;
  begin
    if (AIndex >= 0) and (AIndex < System.Length(ADisp.Cells)) then Result := ADisp.Cells[AIndex]
    else Result := TyPlainRowCell;
  end;

  { Cell AIndex declares a right line and the next cell, which would draw it as its left, does
    not declare one (and is not merged into the same box). }
  function RightOpen(AIndex: Integer): Boolean;
  var
    nd: TTyRowCellDisplay;
  begin
    nd := CellDisplay(R.FDisplay, AIndex + 1);
    Result := (nd.HMerge <> rcmContinue) and not (rcsLeft in nd.Borders);
  end;

  { The cell below cell AIndex (the one of that index in the next row - the box it was merged
    into there) would not draw the line between them as its top: it declares none, and it does
    not continue this cell (a vertical merge has no line inside). }
  function BottomOpen(AIndex: Integer): Boolean;
  var
    nd: TTyRowCellDisplay;
    nr: TTyRichRow;
    m: Integer;
  begin
    if not haveNext then
    begin
      nr := tbl.Rows[ARow.Index + 1];
      if nr.RawFormat <> '' then nextDisp := TyRtfRowDisplay(nr.RawFormat)
      else nextDisp := TyDefaultRowDisplay(Max(1, nr.CellCount));
      haveNext := True;
    end;
    m := AIndex;
    while (m > 0) and (m < System.Length(nextDisp.Cells)) and
      (nextDisp.Cells[m].HMerge = rcmContinue) do
      Dec(m);
    nd := CellDisplay(nextDisp, m);
    Result := (nd.VMerge <> rcmContinue) and not (rcsTop in nd.Borders);
  end;

begin
  R := TTyRowLayout.Create(Self);
  try
    tbl := ARow.Table;
    tbl.AddRef;
    R.FTable := tbl;
    R.FRowIndex := ARow.Index;
    R.FFirstPara := AFirst;
    R.FLastPara := ALast;
    R.FLayoutWidth := AWidth;
    R.FPPI := APPI;
    R.FZoom := AZoom;
    nc := Max(1, ARow.CellCount);
    if ARow.RawFormat <> '' then R.FDisplay := TyRtfRowDisplay(ARow.RawFormat)
    else R.FDisplay := TyDefaultRowDisplay(nc);
    lastRow := ARow.Index >= tbl.RowCount - 1;
    haveNext := False;
    // the cells' boxes, left to right
    SetLength(R.FCells, nc);
    prevTw := R.FDisplay.Left;
    for i := 0 to nc - 1 do
    begin
      if i < ARow.BoundaryCount then rightTw := ARow.Boundaries[i]
      else if i < tbl.ColBoundaryCount then rightTw := tbl.ColBoundaries[i]
      else if (i < System.Length(R.FDisplay.Cells)) and R.FDisplay.Cells[i].HasRight then
        rightTw := R.FDisplay.Cells[i].Right
      else
        rightTw := prevTw + CRichDefaultCellTwips;
      // an edge left of the one before it: an empty cell there
      if rightTw < prevTw then rightTw := prevTw;
      cd := CellDisplay(R.FDisplay, i);
      bx := @R.FCells[i];
      bx^.Left := Px(prevTw);
      bx^.Right := Px(rightTw);
      bx^.FirstItem := 0;
      bx^.ItemCount := 0;
      bx^.ContentHeight := 0;
      bx^.VAlign := cd.VAlign;
      bx^.VMerge := cd.VMerge;
      // a file's width up to Word's limit
      for s := Low(TTyRowCellSide) to High(TTyRowCellSide) do
        bx^.LinePx[s] := Max(1, Px(Min(cd.BorderWidth[s], CRichMaxBorderTwips)));
      bx^.Sides := [];
      if (cd.HMerge = rcmContinue) and (i > 0) then
      begin
        // merged into the cell before: that one's box reaches over this one
        bx^.Hidden := True;
        bx^.Owner := R.FCells[i - 1].Owner;
        R.FCells[bx^.Owner].Right := bx^.Right;
      end
      else
      begin
        bx^.Hidden := False;
        bx^.Owner := i;
        if rcsLeft in cd.Borders then Include(bx^.Sides, rcsLeft);
        // a cell that continues the one above draws no line toward it
        if (rcsTop in cd.Borders) and (cd.VMerge <> rcmContinue) then Include(bx^.Sides, rcsTop);
        { A line between two rows is the lower one's top; the table's last row closes it, and
          a declared bottom is drawn here too when the cell below does not draw the line. }
        if (rcsBottom in cd.Borders) and (lastRow or BottomOpen(i)) then
          Include(bx^.Sides, rcsBottom);
      end;
      { A line between two cells is the later one's left; the row's last cell closes the row,
        and a declared right is drawn here too when the next cell does not draw the line (on
        the box the cell is in, when merged). }
      if (rcsRight in cd.Borders) and ((i = nc - 1) or RightOpen(i)) then
      begin
        o := bx^.Owner;
        Include(R.FCells[o].Sides, rcsRight);
        R.FCells[o].LinePx[rcsRight] := bx^.LinePx[rcsRight];
      end;
      prevTw := rightTw;
    end;
    { \trqc / \trqr: the row centred in, or at the right of, the width it is laid out at (not
      without wrapping: there is no width to place it in). }
    if (R.FDisplay.Align <> rraLeft) and (AWidth > 0) then
    begin
      lo := R.FCells[0].Left;
      hi := R.FCells[0].Right;
      for i := 1 to nc - 1 do hi := Max(hi, R.FCells[i].Right);
      if R.FDisplay.Align = rraCenter then shift := (AWidth - (hi - lo)) div 2 - lo
      else shift := AWidth - hi;
      for i := 0 to nc - 1 do
      begin
        Inc(R.FCells[i].Left, shift);
        Inc(R.FCells[i].Right, shift);
      end;
    end;
    // the paragraphs, each in its cell (a merged-away cell's at the box it went into)
    gap := Max(0, Px(R.FDisplay.HalfGap));
    pos := 0;
    cut := 0;
    room := nil;
    SetLength(room, nc);
    SetLength(R.FItems, ALast - AFirst + 1);
    for k := AFirst to ALast do
    begin
      cell := ADoc.CellAt(k);
      if cell <> nil then ci := Min(Max(cell.Index, 0), nc - 1) else ci := 0;
      o := R.FCells[ci].Owner;
      { The text's distance from the edges is at most half the cell. A cell with no room for
        text (no width, or an edge left of the one before) lays its paragraphs out unwrapped
        - a line each, cheaply - and they take no height: they are positions nobody sees. }
      g := Min(gap, Max(0, R.FCells[o].Right - R.FCells[o].Left) div 2);
      inner := R.FCells[o].Right - R.FCells[o].Left - 2 * g;
      room[ci] := inner > 0;
      if inner > 0 then P := BuildPara(ADoc, k, inner, APPI, AZoom)
      else P := BuildPara(ADoc, k, CRichNoWrap, APPI, AZoom);
      j := k - AFirst;
      R.FItems[j].Layout := P;
      R.FItems[j].X := R.FCells[o].Left + g;
      R.FItems[j].Y := 0;
      R.FItems[j].Pos := pos;
      R.FItems[j].Cell := ci;
      Inc(pos, P.FLength + 1);
      if P.FNumbered then R.FNumbered := True;
      if P.FTruncated then
      begin
        R.FTruncated := True;
        Inc(cut, P.FLength - P.FShown);
      end;
      if R.FCells[ci].ItemCount = 0 then R.FCells[ci].FirstItem := j;
      Inc(R.FCells[ci].ItemCount);
      if inner > 0 then
        R.FCells[ci].ContentHeight := SatAdd(R.FCells[ci].ContentHeight, P.Height);
    end;
    R.FCharCount := pos;
    R.FShownChars := pos - cut;
    // the row's height: its tallest cell, lines included, and what the format demands
    rowH := 0;
    for i := 0 to nc - 1 do
    begin
      bx := @R.FCells[i];
      if bx^.Hidden then Continue;
      padT := 0;
      padB := 0;
      if rcsTop in bx^.Sides then padT := bx^.LinePx[rcsTop];
      if rcsBottom in bx^.Sides then padB := bx^.LinePx[rcsBottom];
      rowH := Max(rowH, SatAdd(SatAdd(padT, bx^.ContentHeight), padB));
    end;
    if R.FDisplay.Height > 0 then rowH := Max(rowH, Px(R.FDisplay.Height))
    else if R.FDisplay.Height < 0 then rowH := Px(-Int64(R.FDisplay.Height));
    rowH := Max(1, rowH);
    R.FHeight := rowH;
    R.FWidth := 0;
    for i := 0 to nc - 1 do
    begin
      bx := @R.FCells[i];
      if bx^.Hidden then Continue;
      if bx^.Right > R.FWidth then R.FWidth := bx^.Right;
      padT := 0;
      padB := 0;
      if rcsTop in bx^.Sides then padT := bx^.LinePx[rcsTop];
      if rcsBottom in bx^.Sides then padB := bx^.LinePx[rcsBottom];
      off := Max(0, rowH - padT - padB - bx^.ContentHeight);
      case bx^.VAlign of
        rcvCenter: off := off div 2;
        rcvBottom: ;
      else
        off := 0;
      end;
      y := padT + off;
      for j := bx^.FirstItem to bx^.FirstItem + bx^.ItemCount - 1 do
        if R.FItems[j].Cell = i then
        begin
          R.FItems[j].Y := y;
          if room[i] then y := SatAdd(y, R.FItems[j].Layout.Height);
        end;
    end;
  except
    R.Release;
    raise;
  end;
  Result := R;
end;

procedure TTyRichLayouter.Prepare(ADoc: TTyRichDocument; AIndex: Integer; var AWidth,
  APPI: Integer; var AZoom: Single);
begin
  // another document: switched to as the setter does (the same object at the address of a
  // freed one is only told apart by the owner setting Document)
  if ADoc <> FDoc then SetDocument(ADoc);
  if (AIndex < 0) or (AIndex >= ADoc.Text.ParaCount) then
    raise EArgumentOutOfRangeException.CreateFmt('no paragraph %d', [AIndex]);
  if AWidth < 0 then AWidth := CRichNoWrap;
  if APPI <= 0 then APPI := 96;
  if not (AZoom > 0) then AZoom := 1;
end;

{ The cached block that starts at AIndex, of the kind asked for (a row, or a paragraph) and
  laid out for these values, with a reference for the caller; nil when there is none. }
function TTyRichLayouter.CacheHit(AIndex, AWidth, APPI: Integer; AZoom: Single;
  ARow: Boolean): TTyBlockLayout;
var
  L: TTyBlockLayout;
begin
  Result := nil;
  if not FCache.TryGetValue(AIndex, L) then Exit;
  if (ARow <> (L is TTyRowLayout)) or (L.FLayoutWidth <> AWidth) or (L.FPPI <> APPI) or
    (L.FZoom <> AZoom) then
    Exit;
  Inc(FHits);
  LruUnlink(L);
  LruPushFront(L);
  L.AddRef;
  Result := L;
end;

function TTyRichLayouter.LayoutPara(ADoc: TTyRichDocument; AIndex: Integer; AWidth: Integer;
  APPI: Integer; AZoom: Single): TTyParaLayout;
begin
  Prepare(ADoc, AIndex, AWidth, APPI, AZoom);
  Result := TTyParaLayout(CacheHit(AIndex, AWidth, APPI, AZoom, False));
  if Result <> nil then Exit;
  Inc(FMisses);
  Result := BuildPara(ADoc, AIndex, AWidth, APPI, AZoom);
  // in place of what the cache held there for other values (CacheInsert)
  CacheInsert(Result);
  CacheTrim(Result);
  Result.AddRef;
end;

function TTyRichLayouter.LayoutBlock(ADoc: TTyRichDocument; AIndex: Integer; AWidth: Integer;
  APPI: Integer; AZoom: Single): TTyBlockLayout;
var
  L: TTyBlockLayout;
  cell, c: TTyRichCell;
  row: TTyRichRow;
  first, last, n: Integer;
begin
  Prepare(ADoc, AIndex, AWidth, APPI, AZoom);
  // the usual call: the block that starts here (a paragraph laid out by itself while it sits
  // in a cell - LayoutPara's - is not one)
  if FCache.TryGetValue(AIndex, L) and not ((L is TTyParaLayout) and TTyParaLayout(L).FInCell) then
  begin
    Result := CacheHit(AIndex, AWidth, APPI, AZoom, L is TTyRowLayout);
    if Result <> nil then Exit;
  end;
  ADoc.BeginRead;
  try
    cell := ADoc.CellAt(AIndex);
    if cell = nil then Exit(LayoutPara(ADoc, AIndex, AWidth, APPI, AZoom));
    // the row's paragraphs: the ones around AIndex in the same row, and no others
    row := cell.Row;
    first := AIndex;
    while first > 0 do
    begin
      c := ADoc.CellAt(first - 1);
      if (c = nil) or (c.Row <> row) then Break;
      Dec(first);
    end;
    n := ADoc.Text.ParaCount;
    last := AIndex;
    while last < n - 1 do
    begin
      c := ADoc.CellAt(last + 1);
      if (c = nil) or (c.Row <> row) then Break;
      Inc(last);
    end;
    Result := CacheHit(first, AWidth, APPI, AZoom, True);
    if Result <> nil then Exit;
    Inc(FMisses);
    Result := BuildRow(ADoc, first, last, row, AWidth, APPI, AZoom);
    CacheInsert(Result);
    CacheTrim(Result);
    Result.AddRef;
  finally
    ADoc.EndRead;
  end;
end;

end.
