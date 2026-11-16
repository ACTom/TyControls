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
  { Advances kept per layouter; past it the older half is dropped. }
  CRichMeasureCacheEntries = 65536;
  { A layout width that means "no wrapping" (TTyRichWrapMode rwmNone). }
  CRichNoWrap = 0;
  { The box of a picture whose size is not known, in pixels at 96 PPI and zoom 1. }
  CRichDefaultObjectPx = 32;
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
    justification added). }
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
    FStale: Boolean;
    { It shows a list number, which depends on the paragraphs before it: a change of
      paragraphs or formats above it drops it too. }
    FNumbered: Boolean;
  public
    constructor Create(ALayouter: TTyRichLayouter);
    procedure AddRef;
    procedure Release;
    { The nearest caret place to (AX, AY): a position in [0, CharCount]. }
    function PosAtPoint(AX, AY: Integer): TTyRichPos; virtual; abstract;
    { The caret at APos: one pixel wide, as tall as its line. }
    function CaretRect(APos: TTyRichPos): TRect; virtual; abstract;
    { The rectangles that show [AFrom, ATo) selected, one per line it touches; a range that
      takes in the block's last separator (ATo > its last position) gets a mark past the
      end of its last line. }
    function SelectionRects(AFrom, ATo: TTyRichPos): TRectArray; virtual; abstract;
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
    { The paragraphs it shows changed after it was made (the layouter dropped it): what it
      says is what they were. }
    property Stale: Boolean read FStale;
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
    FHasMarker: Boolean;
    FMarker: TTyRichFragment;
    FInCell: Boolean;
    FLines: array of TTyRichLine;
    FLineCount: Integer;
    FFrags: array of TTyRichFragment;
    FFragCount: Integer;
    FSpaceBefore: Integer;
    FSpaceAfter: Integer;
    function GetLine(AIndex: Integer): TTyRichLine;
    function GetFragment(AIndex: Integer): TTyRichFragment;
    function ByteOfChar(const F: TTyRichFragment; AChars: Integer): Integer;
    function SnapToCluster(const F: TTyRichFragment; AChars: Integer): Integer;
    function PrefixWidth(const F: TTyRichFragment; AChars: Integer): Integer;
    function XInLine(ALine: Integer; APos: Integer): Integer;
    function NearestInFragment(const F: TTyRichFragment; AX: Integer): Integer;
  public
    destructor Destroy; override;
    function PosAtPoint(AX, AY: Integer): TTyRichPos; override;
    function CaretRect(APos: TTyRichPos): TRect; override;
    function SelectionRects(AFrom, ATo: TTyRichPos): TRectArray; override;
    function MemSize: Int64; override;
    { The line a position is on (the start of a wrapped line belongs to that line), and the
      line at a height (above the first: the first; below the last: the last). }
    function LineOfPos(APos: TTyRichPos): Integer;
    function LineAtY(AY: Integer): Integer;
    { What fragment AIndex draws (its Text for an object or a replacement). }
    function FragmentText(AIndex: Integer): UTF8String;
    property LineCount: Integer read FLineCount;
    property Lines[AIndex: Integer]: TTyRichLine read GetLine;
    property FragmentCount: Integer read FFragCount;
    property Fragments[AIndex: Integer]: TTyRichFragment read GetFragment;
    { The paragraph's text (UTF-8) and its length in characters. }
    property Text: RawByteString read FText;
    property Length: Integer read FLength;
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
    ItemCount - 1 of the row. Sides: the lines drawn, each LinePx thick - its left and its top
    (not when it continues the cell above: a vertical merge), and the right of the row's last
    cell and the bottom of the table's last row; so a line between two cells, or two rows, is
    drawn once, as the later one's. }
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
    edge (a negative one reaches left of it, as Word puts the lines in the margin) and never
    shrunk to the wrap width (the control scrolls); each cell's paragraphs laid out by
    themselves at the cell's width less the half gap on either side, their indents inside the
    cell, stacked from below its top line and placed by its vertical alignment; the row as
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
  public
    destructor Destroy; override;
    function PosAtPoint(AX, AY: Integer): TTyRichPos; override;
    function CaretRect(APos: TTyRichPos): TRect; override;
    function SelectionRects(AFrom, ATo: TTyRichPos): TRectArray; override;
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
    // measuring
    FMeasure, FMeasureOld: specialize TDictionary<string, Integer>;
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
    procedure WalkCollect(AIndex: Integer; AData: Pointer; ASrcOffset, ASrcBytes: Int64;
      var AContinue: Boolean);
    function ListOfFormat(ADoc: TTyRichDocument; AFormat: TTyParaFormatId): TTyListFormat;
    procedure DropNumbersFrom(AFirst: Integer);
    procedure SetBaseFontName(const AValue: string);
    procedure SetBaseFontSizeHalfPt(AValue: Integer);
    procedure FallbackFontsChanged(Sender: TObject);
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
  public
    constructor Create(ADevice: TTyRichTextDevice; AOwnsDevice: Boolean = True);
    destructor Destroy; override;
    { Paragraph AIndex of ADoc laid out at AWidth pixels (CRichNoWrap: no wrapping), APPI
      and AZoom (1.0 = 100 %). From the cache when it holds that paragraph at those values.
      The result carries a reference for the caller: Release it when done. The layouter
      works for one document at a time: a call with another one empties the cache first. }
    function LayoutPara(ADoc: TTyRichDocument; AIndex: Integer; AWidth: Integer;
      APPI: Integer; AZoom: Single): TTyParaLayout;
    { The block paragraph AIndex belongs to, with a reference for the caller: a
      TTyRowLayout when the paragraph is in a table cell - its row, whichever of the row's
      paragraphs AIndex is - else its TTyParaLayout. The entry the control uses: the next
      block starts at LastPara + 1. Finding a row's paragraphs reads the row's own and one
      on either side (never the whole table), inside one read scope. }
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
      and without counting a hit; nil when there is none. }
    function CachedLayout(AIndex: Integer): TTyBlockLayout;
    { What a paragraph not laid out yet counts as: one line of the base font. }
    function EstimatedParaHeight(APPI: Integer; AZoom: Single): Integer;
    { The advance of AText in AFont, kept by (font, text). }
    function MeasureText(AFont: TTyRichFontId; const AText: UTF8String): Integer;
    property Device: TTyRichTextDevice read FDevice;
    property Document: TTyRichDocument read FDoc;
    { The font a character format with no name / no size gets: the control's theme font. }
    property BaseFontName: string read FBaseFontName write SetBaseFontName;
    property BaseFontSizeHalfPt: Integer read FBaseFontSizeHalfPt write SetBaseFontSizeHalfPt;
    { Tried in order for a character the font in effect has no glyph for; the first that
      has it is used. Starts as the platform's list; change it freely. }
    property FallbackFonts: TStringList read FFallbackFonts;
    property OnFallbackFont: TTyRichFallbackEvent read FOnFallbackFont write FOnFallbackFont;
    property CacheHits: Int64 read FHits;
    property CacheMisses: Int64 read FMisses;
    function CachedCount: Integer;
    property CachedChars: Int64 read FCachedChars;
    { Paragraphs list numbering looked at, for the tests that check it stays bounded. }
    property ListWalkSteps: Int64 read FListWalkSteps;
  end;

{ The width LayoutPara takes for a wrap mode: rwmWindow AAvailWidth (at least 1), rwmPage
  the document's text width at APPI and AZoom, rwmNone CRichNoWrap. }
function TyRichLayoutWidth(AMode: TTyRichWrapMode; AAvailWidth: Integer;
  ADoc: TTyRichDocument; APPI: Integer; AZoom: Single): Integer;
function TyRichTwipsToPx(ATwips: Int64; APPI: Integer; AZoom: Single): Integer;
{ The font size of a character format in pixels (half-points at APPI and AZoom), at least 1. }
function TyRichHalfPointsToPx(AHalfPt: Integer; APPI: Integer; AZoom: Single): Integer;
function TyRichIsKinsokuNoLineStart(ACode: Cardinal): Boolean;
function TyRichIsKinsokuNoLineEnd(ACode: Cardinal): Boolean;
{ A code point that belongs to the cluster before it: a combining mark, a variation
  selector, a joiner, an emoji modifier or tag. }
function TyRichIsClusterExtend(ACode: Cardinal): Boolean;
{ The platform's fallback candidates (the plan's lists). }
procedure TyRichDefaultFallbackFonts(AList: TStrings);
{ What a list item's marker reads: a bullet by level (U+2022, U+25E6, U+25AA, over again from
  level 3), or ANumber followed by a full stop - 1, 2, 3; a, b, ... z, aa, ab (letters go on
  in base 26 with no zero); i, ii, ... (roman up to 3999). A number the kind cannot write
  (below 1, or past 3999 in roman) is written in digits. '' for no list. }
function TyRichListMarkerText(AKind: TTyListKind; ALevel: Integer; ANumber: Int64): UTF8String;

implementation

uses
  Math, LCLType, LCLIntf, tyControls.Types, tyControls.FontUnits, tyControls.Painter;

const
  ckText = 0;
  ckSpace = 1;
  ckTab = 2;
  ckBreak = 3;
  ckObject = 4;
  ckInvalid = 5;
  ckInvalid2 = 6;

  CUnlimited = MaxInt div 4;
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

function TyRichTwipsToPx(ATwips: Int64; APPI: Integer; AZoom: Single): Integer;
begin
  Result := Round(ATwips * Double(APPI) * Double(AZoom) / 1440);
end;

function TyRichHalfPointsToPx(AHalfPt: Integer; APPI: Integer; AZoom: Single): Integer;
begin
  Result := Round(AHalfPt * Double(APPI) * Double(AZoom) / 144);
  if Result < 1 then Result := 1;
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
  glyph is 0 has none) or 12 (all planes: groups). }
procedure ReadCmapSubtable(const B: TBytes; AAt: PtrInt; R: TTyGlyphRanges);
var
  fmt, segX2, i, nGroups: Cardinal;
  endAt, startAt, deltaAt, rangeAt: PtrInt;
  s, e, d, ro, c, g, runStart: Cardinal;
  inRun: Boolean;
  gs, ge, g0: Cardinal;
begin
  fmt := BE16(B, AAt);
  if fmt = 4 then
  begin
    segX2 := BE16(B, AAt + 6);
    endAt := AAt + 14;
    startAt := endAt + segX2 + 2;
    deltaAt := startAt + segX2;
    rangeAt := deltaAt + segX2;
    i := 0;
    while i < segX2 div 2 do
    begin
      e := BE16(B, endAt + i * 2);
      s := BE16(B, startAt + i * 2);
      d := BE16(B, deltaAt + i * 2);
      ro := BE16(B, rangeAt + i * 2);
      inRun := False;
      runStart := 0;
      c := s;
      while (c <= e) and (c < $FFFF) do
      begin
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
    nGroups := BE32(B, AAt + 12);
    i := 0;
    while i < nGroups do
    begin
      gs := BE32(B, AAt + 16 + i * 12);
      ge := BE32(B, AAt + 20 + i * 12);
      g0 := BE32(B, AAt + 24 + i * 12);
      if g0 = 0 then Inc(gs);
      if gs <= ge then R.Add(gs, ge);
      Inc(i);
    end;
  end;
end;

{ The font's cmap, read through GDI: the Unicode subtable in format 12 when there is one,
  else the BMP one in format 4, else the symbol one. nil when the font has no cmap (not a
  TrueType or OpenType font). }
function ReadCmap(ADC: PtrUInt): TTyGlyphRanges;
const
  TagCmap = $70616D63;   // 'cmap', as GDI wants the tag: its bytes in file order
  GdiError = $FFFFFFFF;
var
  size: LongWord;
  b: TBytes;
  n, i, plat, enc: Cardinal;
  off: Cardinal;
  best12, best4, sym: PtrInt;
begin
  Result := nil;
  size := TyGetFontData(ADC, TagCmap, 0, nil, 0);
  if (size = GdiError) or (size < 4) then Exit;
  b := nil;
  SetLength(b, size);
  if TyGetFontData(ADC, TagCmap, 0, @b[0], size) = GdiError then Exit;
  n := BE16(b, 2);
  best12 := -1;
  best4 := -1;
  sym := -1;
  for i := 0 to n - 1 do
  begin
    plat := BE16(b, 4 + i * 8);
    enc := BE16(b, 6 + i * 8);
    off := BE32(b, 8 + i * 8);
    if off >= size then Continue;
    case BE16(b, off) of
      12: if ((plat = 3) and (enc = 10)) or (plat = 0) then best12 := off;
      4: if ((plat = 3) and (enc = 1)) or (plat = 0) then best4 := off
         else if (plat = 3) and (enc = 0) then sym := off;
    end;
  end;
  Result := TTyGlyphRanges.Create;
  if best12 >= 0 then ReadCmapSubtable(b, best12, Result)
  else if best4 >= 0 then ReadCmapSubtable(b, best4, Result)
  else if sym >= 0 then
  begin
    ReadCmapSubtable(b, sym, Result);
    Result.Symbol := True;
  end
  else
    FreeAndNil(Result);
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

function TTyParaLayout.PrefixWidth(const F: TTyRichFragment; AChars: Integer): Integer;
begin
  if AChars <= 0 then Exit(0);
  if AChars >= F.Count then Exit(F.Width);
  case F.Kind of
    rfkText:
      Result := FLayouter.MeasureText(F.Font, Copy(FText, F.ByteStart + 1, ByteOfChar(F, AChars)));
    rfkSpace:
      if F.Width = F.Natural then
        Result := FLayouter.MeasureText(F.Font, Copy(FText, F.ByteStart + 1, AChars))
      else
        Result := Int64(F.Width) * AChars div F.Count;
  else
    // a replacement pair: the first character has the advance, the second none
    Result := F.Width;
  end;
end;

function TTyParaLayout.LineOfPos(APos: TTyRichPos): Integer;
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

function TTyParaLayout.PosAtPoint(AX, AY: Integer): TTyRichPos;
var
  ln, i, lastPos, x0, x1: Integer;
  f: ^TTyRichFragment;
begin
  ln := LineAtY(AY);
  with FLines[ln] do
  begin
    // past the end of a line that U+000B ended: before the U+000B, which is still this
    // line's; past a wrapped line: where the next line starts
    lastPos := First + Count - Ord(Forced);
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
    Result := lastPos;
  end;
end;

function TTyParaLayout.CaretRect(APos: TTyRichPos): TRect;
var
  ln, x: Integer;
begin
  if APos < 0 then APos := 0;
  if APos > FLength then APos := FLength;
  ln := LineOfPos(APos);
  x := XInLine(ln, APos);
  Result := Rect(x, FLines[ln].Top, x + 1, FLines[ln].Top + FLines[ln].Height);
end;

function TTyParaLayout.SelectionRects(AFrom, ATo: TTyRichPos): TRectArray;
var
  n, ln, a, b, xa, xb, stop, mark: Integer;
  isLast: Boolean;
begin
  Result := nil;
  if AFrom < 0 then AFrom := 0;
  if ATo > FLength + 1 then ATo := FLength + 1;
  if ATo <= AFrom then Exit;
  n := 0;
  for ln := LineOfPos(Min(AFrom, FLength)) to FLineCount - 1 do
  begin
    isLast := ln = FLineCount - 1;
    with FLines[ln] do
    begin
      if First >= ATo then Break;
      stop := First + Count;
      a := Max(AFrom, First);
      b := Min(ATo, stop);
      if b < a then Continue;
      xa := XInLine(ln, a);
      if (b >= stop) and not isLast then xb := EndX else xb := XInLine(ln, b);
      mark := Max(2, Height div 4);
      // a selected U+000B, or the paragraph's separator: a mark past the line's end
      if (Forced and (ATo >= stop) and (AFrom < stop)) or (isLast and (ATo > FLength)) then
        xb := Max(xb, EndX) + mark;
      if xb <= xa then Continue;
      SetLength(Result, n + 1);
      Result[n] := Rect(xa, Top, xb, Top + Height);
      Inc(n);
    end;
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

function TTyRowLayout.PosAtPoint(AX, AY: Integer): TTyRichPos;
var
  c, k, last: Integer;
begin
  c := CellAtX(AX);
  if c < 0 then Exit(0);
  // the cell's paragraph at AY: above the first, the first; below the last, the last
  k := FCells[c].FirstItem;
  last := k + FCells[c].ItemCount - 1;
  while (k < last) and ((FItems[k].Cell <> c) or
    (FItems[k].Y + FItems[k].Layout.Height <= AY)) do
    Inc(k);
  Result := FItems[k].Pos + FItems[k].Layout.PosAtPoint(AX - FItems[k].X, AY - FItems[k].Y);
end;

function TTyRowLayout.CaretRect(APos: TTyRichPos): TRect;
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
    Result := FItems[k].Layout.CaretRect(APos - FItems[k].Pos);
  OffsetRect(Result, FItems[k].X, FItems[k].Y);
end;

function TTyRowLayout.SelectionRects(AFrom, ATo: TTyRichPos): TRectArray;
var
  k, i, n: Integer;
  a, b: TTyRichPos;
  rs: TRectArray;
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
    SetLength(Result, n + System.Length(rs));
    for i := 0 to High(rs) do
    begin
      Result[n] := rs[i];
      OffsetRect(Result[n], FItems[k].X, FItems[k].Y);
      Inc(n);
    end;
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
  end;

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
    ListNumber: Int64;
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
    procedure LayLine(AStart, AEnd, AK: Integer; AJustify: Boolean);
    function PieceAt(AChar, AHint: Integer): Integer;
    procedure EmitLine(AStart, AEnd, AK: Integer; ALeft: Integer; var ATop: Integer;
      AForced, ALast: Boolean; AEmptyFormat: TTyCharFormatId);
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
  i: Integer;
  join, riOdd: Boolean;
begin
  SetLength(ClStart, N + 1);
  if N = 0 then Exit;
  ClStart[0] := True;
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
      CFmt[i] := CFmt[i - 1];
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
              w := Max(1, Round(CRichDefaultObjectPx * PPI * Double(Zoom) / 96));
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
  multiple of the default interval. }
procedure TParaBuilder.NextStop(AX: Integer; out AStop: Integer; out AAlign: TTyTabAlign;
  out ALeader: TTyTabLeader);
var
  i: Integer;
begin
  for i := 0 to High(TabPos) do
    if TabPos[i] > AX then
    begin
      AStop := TabPos[i];
      AAlign := TabAlign[i];
      ALeader := TabLeader[i];
      Exit;
    end;
  AAlign := ttaLeft;
  ALeader := ttlNone;
  AStop := (Max(AX, 0) div DefTab + 1) * DefTab;
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

{ The items (unpositioned yet) of the line [AStart, AEnd): pieces, cut at the line's ends;
  unless the line is to be justified, the neighbours of one font and format - words and the
  spaces between them - joined into one item, measured again as the one string that will be
  drawn. The spaces after the line's content stay an item of their own: they hang. }
procedure TParaBuilder.LayLine(AStart, AEnd, AK: Integer; AJustify: Boolean);
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
      if (not AJustify) and (ItemCount > 0) and (p^.Kind in [rfkText, rfkSpace]) and
        (b <= contentEnd) then
      begin
        it := @Items[ItemCount - 1];
        q := @Pieces[it^.Piece];
        if (it^.Kind in [rfkText, rfkSpace]) and (q^.Font = p^.Font) and
          (q^.Format = p^.Format) and (it^.First + it^.Count = a) and
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
      end;
    end;
    Inc(k);
  end;
  for a := 0 to ItemCount - 1 do
    if Items[a].Width < 0 then
      Items[a].Width := L.MeasureText(Pieces[Items[a].Piece].Font,
        RangeText(Items[a].First, Items[a].First + Items[a].Count));
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
  if AEnd > AStart then LayLine(AStart, AEnd, PieceAt(AStart, AK), justify)
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
            decW := segW + MeasureRange(it^.Piece, it^.First, k);
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
        gaps := 0;
        for i := lastTab + 2 to contentEnd do
          if Brk[Items[i].First] <> 0 then Inc(gaps);
        if gaps > 0 then
          for i := lastTab + 2 to ItemCount - 1 do
          begin
            if (i <= contentEnd) and (Brk[Items[i].First] <> 0) then
            begin
              Inc(cum);
              done := Int64(extra) * cum div gaps;
            end;
            Inc(Items[i].X, done);
          end;
      end;
    end;
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
      else
        fr^.Natural := it^.Width;
      if (it^.Kind = rfkSpace) and not justify then fr^.Natural := fr^.Width;
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
  Inc(ATop, h);
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
  FindBreaks;
  ResolveFonts;
  MakePieces;
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
      k0 := k;
      e := FindLineEnd(s, k, left);
      if e <= s then e := ClusterEnd(s);
      EmitLine(s, e, k0, left, top, Kind[e - 1] = ckBreak, e >= N, CFmt[e - 1]);
      s := e;
      // a paragraph that ends with U+000B has an empty line after it, for the caret
      if (s = N) and (Kind[N - 1] = ckBreak) then
        EmitLine(N, N, k, LeftPx, top, False, True, CFmt[N - 1]);
    end;
  Layout.FHeight := top + Layout.FSpaceAfter;
  SetLength(Layout.FLines, Layout.FLineCount);
  SetLength(Layout.FFrags, Layout.FFragCount);
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
  FFontPPI := -1;
end;

destructor TTyRichLayouter.Destroy;
begin
  Clear;
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

procedure TTyRichLayouter.SetBaseFontName(const AValue: string);
begin
  if FBaseFontName = AValue then Exit;
  FBaseFontName := AValue;
  Clear;
end;

procedure TTyRichLayouter.SetBaseFontSizeHalfPt(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  if FBaseFontSizeHalfPt = AValue then Exit;
  FBaseFontSizeHalfPt := AValue;
  Clear;
end;

procedure TTyRichLayouter.FallbackFontsChanged(Sender: TObject);
begin
  Clear;
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

procedure TTyRichLayouter.Clear;
begin
  while FLruFirst <> nil do CacheDrop(FLruFirst, True);
  FMeasure.Clear;
  FreeAndNil(FMeasureOld);
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
  // the numbers from here on may count differently now
  DropNumbersFrom(AFirst);
  L := FLruFirst;
  while L <> nil do
  begin
    nx := L.FLruNext;
    if ((L.FLastPara >= AFirst) and (L.FFirstPara < AFirst + ACount)) or
      (L.FNumbered and (L.FFirstPara >= AFirst)) then
      CacheDrop(L, True);
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
    end;
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
    FMeasure.AddOrSetValue(key, Result);
    Exit;
  end;
  Result := FDevice.TextWidth(AFont, AText);
  if FMeasure.Count >= CRichMeasureCacheEntries div 2 then
  begin
    // the older half goes; what was used since it became the older half came forward
    FMeasureOld.Free;
    FMeasureOld := FMeasure;
    FMeasure := specialize TDictionary<string, Integer>.Create;
  end;
  FMeasure.AddOrSetValue(key, Result);
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
      text := t.GetText(start, len);
      b.L := Self;
      b.Dev := FDevice;
      b.Layout := Result;
      b.PPI := APPI;
      b.Zoom := AZoom;
      b.Width := AWidth;
      b.Decode(text, len);
      Result.FText := b.Txt;
      Result.FLength := b.N;
      Result.FFirstPara := AIndex;
      Result.FLastPara := AIndex;
      Result.FLayoutWidth := AWidth;
      Result.FPPI := APPI;
      Result.FZoom := AZoom;
      Result.FCharCount := b.N + 1;
      b.Run;
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
  nc, i, j, k, o, ci, gap, pos, rowH, padT, padB, off, y: Integer;
  prevTw, rightTw: Int64;
  cd: TTyRowCellDisplay;
  s: TTyRowCellSide;
  lastRow: Boolean;
  bx: ^TTyRichCellBox;
  cell: TTyRichCell;
  P: TTyParaLayout;

  function Px(ATwips: Int64): Integer;
  begin
    Result := TyRichTwipsToPx(ATwips, APPI, AZoom);
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
    // the cells' boxes, left to right
    SetLength(R.FCells, nc);
    prevTw := R.FDisplay.Left;
    for i := 0 to nc - 1 do
    begin
      if i < ARow.BoundaryCount then rightTw := ARow.Boundaries[i]
      else if i < tbl.ColBoundaryCount then rightTw := tbl.ColBoundaries[i]
      else if (i < System.Length(R.FDisplay.Cells)) and (R.FDisplay.Cells[i].Right >= 0) then
        rightTw := R.FDisplay.Cells[i].Right
      else
        rightTw := prevTw + CRichDefaultCellTwips;
      // an edge left of the one before it: an empty cell there
      if rightTw < prevTw then rightTw := prevTw;
      if i < System.Length(R.FDisplay.Cells) then cd := R.FDisplay.Cells[i]
      else cd := TyPlainRowCell;
      bx := @R.FCells[i];
      bx^.Left := Px(prevTw);
      bx^.Right := Px(rightTw);
      bx^.FirstItem := 0;
      bx^.ItemCount := 0;
      bx^.ContentHeight := 0;
      bx^.VAlign := cd.VAlign;
      bx^.VMerge := cd.VMerge;
      for s := Low(TTyRowCellSide) to High(TTyRowCellSide) do
        bx^.LinePx[s] := Max(1, Px(cd.BorderWidth[s]));
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
        if lastRow and (rcsBottom in cd.Borders) then Include(bx^.Sides, rcsBottom);
      end;
      // the row's last cell closes it on the right (the box it is in, when merged)
      if (i = nc - 1) and (rcsRight in cd.Borders) then
      begin
        o := bx^.Owner;
        Include(R.FCells[o].Sides, rcsRight);
        R.FCells[o].LinePx[rcsRight] := bx^.LinePx[rcsRight];
      end;
      prevTw := rightTw;
    end;
    // the paragraphs, each in its cell (a merged-away cell's at the box it went into)
    gap := Max(0, Px(R.FDisplay.HalfGap));
    pos := 0;
    SetLength(R.FItems, ALast - AFirst + 1);
    for k := AFirst to ALast do
    begin
      cell := ADoc.CellAt(k);
      if cell <> nil then ci := Min(Max(cell.Index, 0), nc - 1) else ci := 0;
      o := R.FCells[ci].Owner;
      P := BuildPara(ADoc, k, Max(1, R.FCells[o].Right - R.FCells[o].Left - 2 * gap), APPI,
        AZoom);
      j := k - AFirst;
      R.FItems[j].Layout := P;
      R.FItems[j].X := R.FCells[o].Left + gap;
      R.FItems[j].Y := 0;
      R.FItems[j].Pos := pos;
      R.FItems[j].Cell := ci;
      Inc(pos, P.FLength + 1);
      if P.FNumbered then R.FNumbered := True;
      if R.FCells[ci].ItemCount = 0 then R.FCells[ci].FirstItem := j;
      Inc(R.FCells[ci].ItemCount);
      Inc(R.FCells[ci].ContentHeight, P.Height);
    end;
    R.FCharCount := pos;
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
      rowH := Max(rowH, padT + bx^.ContentHeight + padB);
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
          Inc(y, R.FItems[j].Layout.Height);
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
  if ADoc <> FDoc then
  begin
    Clear;
    FDoc := ADoc;
  end;
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
