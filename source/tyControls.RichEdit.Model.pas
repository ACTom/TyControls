unit tyControls.RichEdit.Model;

{ The document model under TTyRichEdit: character and paragraph formats (values, interned in
  a pool so equal formats share an id), paragraphs made of runs, embedded objects, tables, and
  TTyRichDocument, which owns the text storage (tyControls.RichEdit.Text) and hangs each
  paragraph's formatting on the paragraph's data slot there.

  Paragraph data is an immutable, reference-counted value. A change never edits it in place:
  it builds a new value and puts that in the slot. So whoever holds an old value - an undo
  record, or a piece snapshot the text took before a delete - can put it back later, any
  number of undo/redo cycles on, and gets exactly the old runs, formats and objects. A slot
  holds one reference; the text reports what a merge drops, and the document lets go of it.

  A paragraph whose slot is nil costs nothing: it is plain, in the document's default formats.
  When a loader is installed (the on-demand RTF reader), nil means "not parsed yet" instead,
  and every reader goes through EnsureParsed, which asks the loader for that paragraph.

  The only public way to change a document is a command: TTyRichDocument.Execute runs it and
  keeps it in the document's undo history. The primitives commands are built from are
  protected here; each returns a TTyRichUndoData that Revert puts back exactly. TTyRichCommand
  hands them on to its subclasses (built-in ones in tyControls.RichEdit.Commands, or a
  program's own), only while the document is running that command, and keeps what they
  return, so undo is the records reverted newest first and redo is the command run again. }

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

interface

uses
  Classes, SysUtils, Graphics, LCLType, Generics.Collections, tyControls.RichEdit.Text;

const
  { Insert without a format: the text takes the format of the character before it in the same
    paragraph, or of the character after it at the paragraph's start (as WordPad does). }
  TyRichInheritFormat = -1;

type
  ETyRichModel = class(Exception);
  { The document refused a change and changed nothing (a command reverted what it had done):
    FixedRow - a row that holds a nested table was in the way (TTyRichRow.HoldsNestedTable),
    else the range could not be changed for another reason (a command's CanExecute). }
  ETyRichRefused = class(ETyRichModel)
  public
    FixedRow: Boolean;
  end;

  TTyCharFormatId = Integer;
  TTyParaFormatId = Integer;

  { Unknown RTF attributes, kept as the raw fragments they were read as, in order, so a writer
    can put them back byte for byte. Two formats that differ only here are two formats. Empty,
    the usual case, is one nil pointer. }
  TTyOpaqueAttrs = record
  private
    FItems: array of RawByteString;
  public
    function Count: Integer;
    function Item(AIndex: Integer): RawByteString;
    procedure Add(const AFragment: RawByteString);
    procedure Clear;
    function Equals(const B: TTyOpaqueAttrs): Boolean;
    function Hash: Cardinal;
  end;

  TTyVertAlign = (vaNone, vaSuper, vaSub);

  { FontName '' and SizeHalfPt 0 mean "the control's theme font / size"; Color clDefault means
    the theme's text colour, HighlightColor clNone no highlight. Style holds bold, italic and
    underline; strike-through is Strike (the pool moves an fsStrikeOut in Style there). }
  TTyCharFormat = record
    FontName: string;
    Charset: Integer;
    SizeHalfPt: Integer;
    Style: TFontStyles;
    Strike: Boolean;
    VertAlign: TTyVertAlign;
    Color: TColor;
    HighlightColor: TColor;
    Extra: TTyOpaqueAttrs;
    function Equals(const B: TTyCharFormat): Boolean;
    function Hash: Cardinal;
  end;

  TTyCharFormatField = (cffFontName, cffCharset, cffSize, cffBold, cffItalic, cffUnderline,
    cffStrike, cffVertAlign, cffColor, cffHighlight, cffExtra);
  TTyCharFormatMask = set of TTyCharFormatField;

  { paraLeft..paraJustify, not paLeft..: Menus.TPopupAlignment already has paLeft,
    paCenter and paRight, and the control units use Menus. }
  TTyParaAlign = (paraLeft, paraCenter, paraRight, paraJustify);
  TTyLineSpacing = (lsSingle, ls115, ls15, lsDouble, lsExact, lsAtLeast);
  TTyTabAlign = (ttaLeft, ttaCenter, ttaRight, ttaDecimal);
  TTyTabLeader = (ttlNone, ttlDot, ttlHyphen, ttlUnderline, ttlThick, ttlEqual);

  TTyTabStop = record
    Position: Integer;      // twips from the left indent's origin (RTF \tx)
    Align: TTyTabAlign;
    Leader: TTyTabLeader;
  end;
  TTyTabStops = array of TTyTabStop;

  TTyListKind = (lkNone, lkBullet, lkDecimal, lkLowerAlpha, lkUpperAlpha, lkLowerRoman,
    lkUpperRoman);

  TTyListFormat = record
    Kind: TTyListKind;
    Level: Integer;
    StartAt: Integer;
  end;

  TTyParaFormat = record
    Align: TTyParaAlign;
    LeftIndent: Integer;    // twips
    RightIndent: Integer;
    FirstIndent: Integer;
    SpaceBefore: Integer;
    SpaceAfter: Integer;
    LineSpacing: TTyLineSpacing;
    LineSpacingValue: Integer;   // twips, for lsExact and lsAtLeast
    Tabs: TTyTabStops;
    List: TTyListFormat;
    RtlPar: Boolean;        // kept and written back, not rendered (no bidirectional layout)
    Extra: TTyOpaqueAttrs;
    function Equals(const B: TTyParaFormat): Boolean;
    function Hash: Cardinal;
  end;

  { The fields of a paragraph format a write sets (TyMergeParaFormat). The last five set no
    field of their own: they move one indent meaning per paragraph and keep another, each
    paragraph from its own values - LeftIndent is where the lines after the first
    start, LeftIndent + FirstIndent where the first line starts; AValue gives them in those
    terms:
    pffStartIndent  the first line at AValue.LeftIndent + AValue.FirstIndent, the other lines
                    keeping their offset from it (the paragraph moves: Delphi's FirstIndent);
    pffOffset       the first line's offset from the other lines becomes AValue.FirstIndent,
                    the first line staying where it is (Delphi's LeftIndent);
    pffFirstLine    the first line at AValue.LeftIndent + AValue.FirstIndent, the other lines
                    staying (RichMemo's FirstLine);
    pffHeadIndent   the other lines at AValue.LeftIndent, the first line staying (RichMemo's
                    HeadIndent);
    pffListIndents  with pffList (or pffListKind): a paragraph that becomes a list item and has no indent
                    (both 0) takes AValue's LeftIndent and FirstIndent - the default hanging
                    indent; one that stops being a list item gets both back to 0 (Windows' rich
                    edit's and WordPad's rule); others keep theirs.
    They are applied after the absolute fields, in this order. Four more set one part of a
    record each paragraph keeps the rest of, applied with the absolute fields:
    pffListKind     the list kind (lkNone: the list record at its default; another kind:
                    the paragraph's own start, 1 where it has none);
    pffListStart    the list's start number, the kind staying;
    pffSpacingRule  the line spacing rule; a height stays where the rule is exactly or at
                    least (a paragraph without one takes AValue's), else it is 0;
    pffSpacingHeight the height (LineSpacingValue), the rule staying where it is exactly or
                    at least, else at least (Word's way). }
  TTyParaFormatField = (pffAlign, pffLeftIndent, pffRightIndent, pffFirstIndent,
    pffSpaceBefore, pffSpaceAfter, pffLineSpacing, pffTabs, pffList, pffRtlPar, pffExtra,
    pffStartIndent, pffOffset, pffFirstLine, pffHeadIndent, pffListIndents,
    pffListKind, pffListStart, pffSpacingRule, pffSpacingHeight);
  TTyParaFormatMask = set of TTyParaFormatField;

  { Equal formats get the same id; ids are never reused, so an id an undo record keeps stays
    valid. }
  TTyFormatPool = class
  private
    FChars: array of TTyCharFormat;
    FCharHash: array of Cardinal;
    FCharNext: array of Integer;
    FCharBucket: array of Integer;
    FCharCount: Integer;
    FParas: array of TTyParaFormat;
    FParaHash: array of Cardinal;
    FParaNext: array of Integer;
    FParaBucket: array of Integer;
    FParaCount: Integer;
    procedure RehashChars;
    procedure RehashParas;
  public
    function InternChar(const F: TTyCharFormat): TTyCharFormatId;
    function InternPara(const F: TTyParaFormat): TTyParaFormatId;
    function CharFormat(AId: TTyCharFormatId): TTyCharFormat;
    function ParaFormat(AId: TTyParaFormatId): TTyParaFormat;
    property CharCount: Integer read FCharCount;
    property ParaCount: Integer read FParaCount;
  end;

  { AddRef/Release: freed when the count falls back to 0. The document holds one reference per
    paragraph value that uses it; a command that must re-attach it on redo holds its own. One
    that was never attached and never AddRef'd belongs to whoever created it. }
  TTyRichRefCounted = class
  private
    FRefCount: Integer;
  public
    procedure AddRef;
    procedure Release;
    property RefCount: Integer read FRefCount;
  end;

  { An embedded object: one U+FFFC character in the text; the object rides on the paragraph's
    run list. Immutable once created - an undo record may still show the old one, so a change
    (a resized picture) is a new object (Clone and change). }
  TTyRichObject = class(TTyRichRefCounted)
  private
    FRawUc: Integer;
  public
    constructor Create;
    function Clone: TTyRichObject; virtual; abstract;
    { The bytes its data takes (an image, kept RTF): what a history step that keeps it alive
      counts toward the history's memory limit (TTyRichDocument.MaxUndoBytes). }
    function DataBytes: Int64; virtual;
    { For an object that keeps RTF bytes as they were read (TTyRichOpaque.Bytes,
      TTyRichPicture.RawRtf): the \ucN in effect where they were read - how many fallback
      bytes follow each \uN in them, which the bytes themselves do not say. A writer puts
      them back under that \uc. 1 (RTF's default) for an object made here. }
    property RawUc: Integer read FRawUc;
  end;

  TTyRichPictureFormat = (rpfUnknown, rpfPng, rpfJpeg, rpfBmp, rpfDib, rpfEmf, rpfWmf);

  TTyRichPicture = class(TTyRichObject)
  private
    FFormat: TTyRichPictureFormat;
    FData: TBytes;
    FWidthTwips: Integer;
    FHeightTwips: Integer;
    FRawRtf: RawByteString;
    FShown: Byte;      // 0 not worked out yet, 1 shown, 2 a placeholder
    FShowFormat: TTyRichPictureFormat;
    FShowStart, FShowCount: Integer;
  public
    constructor Create(AFormat: TTyRichPictureFormat; const AData: TBytes;
      AWidthTwips, AHeightTwips: Integer; const ARawRtf: RawByteString = '';
      ARawUc: Integer = 1);
    function Clone: TTyRichObject; override;
    function DataBytes: Int64; override;
    { What an image decoder can show of this picture: the format to decode as and the part of
      Data to hand it, [AStart, AStart + ACount). PNG, JPEG, BMP and DIB pictures are their
      data; a metafile whose whole drawing is one bitmap is that bitmap (rpfDib, the
      BITMAPINFO inside the metafile). False for any other metafile, and for an unknown or
      empty picture: the layout draws a placeholder. Nothing is decoded or copied here, and
      PictureFormat and Data stay what the file had (writing is unchanged). }
    function DisplayData(out AFormat: TTyRichPictureFormat; out AStart, ACount: Integer): Boolean;
    property PictureFormat: TTyRichPictureFormat read FFormat;
    property Data: TBytes read FData;              // the image file's bytes; do not change
    property WidthTwips: Integer read FWidthTwips;  // display size
    property HeightTwips: Integer read FHeightTwips;
    property RawRtf: RawByteString read FRawRtf;    // the {\pict ...} group as read, '' if new
  end;

  // An RTF group this model does not understand ({\*\...}, fields, equations, ...), kept as
  // its bytes.
  TTyRichOpaque = class(TTyRichObject)
  private
    FBytes: RawByteString;
    FDisplayText: UTF8String;
  public
    constructor Create(const ABytes: RawByteString; const ADisplayText: UTF8String = '';
      ARawUc: Integer = 1);
    function Clone: TTyRichObject; override;
    function DataBytes: Int64; override;
    property Bytes: RawByteString read FBytes;
    // what stands for it on screen, as plain text: a field's result ('' for most blocks)
    property DisplayText: UTF8String read FDisplayText;
  end;

  TTyRichTable = class;
  TTyRichRow = class;

  TTyRichCell = class
  private
    FRow: TTyRichRow;
    FIndex: Integer;
  public
    function Table: TTyRichTable;
    property Row: TTyRichRow read FRow;
    property Index: Integer read FIndex;
  end;

  TTyRichRow = class
  private
    FTable: TTyRichTable;
    FIndex: Integer;
    FCells: array of TTyRichCell;
    FBoundaries: array of Integer;
    FRawFormat: RawByteString;
    FHoldsNestedTable: Boolean;
    function GetCell(AIndex: Integer): TTyRichCell;
    function GetBoundary(AIndex: Integer): Integer;
  public
    destructor Destroy; override;
    function CellCount: Integer;
    function BoundaryCount: Integer;
    property Cells[AIndex: Integer]: TTyRichCell read GetCell;
    { This row's own cell right edges in twips (\cellx); none means the table's. }
    property Boundaries[AIndex: Integer]: Integer read GetBoundary;
    { The row's \trowd ... \cellx fragment as read, '' for a new row. }
    property RawFormat: RawByteString read FRawFormat;
    { One of the row's cells holds a table of its own. The model has no nested tables: the
      inner cells' paragraphs are paragraphs of the outer cell, and what made them a table is
      only in the file's bytes. So the row stays as the file has it: the primitives refuse to
      change the text of its paragraphs and leave their formats alone (see
      TTyRichDocument.CanChange). }
    property HoldsNestedTable: Boolean read FHoldsNestedTable;
    property Table: TTyRichTable read FTable;
    property Index: Integer read FIndex;
  end;

  { A table is a contiguous range of paragraphs. A paragraph's data points to its cell; the
    table knows no paragraph index, so paragraphs before it come and go without touching it.
    Its rows and cells are fixed once a paragraph uses it (AddRow raises then). }
  TTyRichTable = class(TTyRichRefCounted)
  private
    FRows: array of TTyRichRow;
    FColBoundaries: array of Integer;
    FStructureLocked: Boolean;
    FFrozen: Boolean;
    FParaRefs: Integer;
    function GetRow(AIndex: Integer): TTyRichRow;
    function GetColBoundary(AIndex: Integer): Integer;
  public
    constructor Create(const AColBoundaries: array of Integer; AStructureLocked: Boolean = False);
    destructor Destroy; override;
    function AddRow(ACellCount: Integer; const ARawFormat: RawByteString = ''): TTyRichRow;
      overload;
    function AddRow(ACellCount: Integer; const ARawFormat: RawByteString;
      const ABoundaries: array of Integer; AHoldsNestedTable: Boolean = False): TTyRichRow;
      overload;
    function RowCount: Integer;
    function CellCount: Integer;
    function ColBoundaryCount: Integer;
    property Rows[AIndex: Integer]: TTyRichRow read GetRow;
    property ColBoundaries[AIndex: Integer]: Integer read GetColBoundary;  // twips
    { Merged cells and the like: shown and kept, but its structure cannot be edited. }
    property StructureLocked: Boolean read FStructureLocked;
  end;

  { A run starts at Start (characters from the paragraph's start) and reaches the next run's
    Start, the last one the paragraph's end. With Obj set, the run is that object's one U+FFFC
    character. }
  TTyRichRun = record
    Start: Integer;
    Format: TTyCharFormatId;
    Obj: TTyRichObject;
  end;
  TTyRunArray = array of TTyRichRun;

  { Objects a history step holds (GatherObjects): duplicates allowed, the history counts
    each distinct one once. }
  TTyRichObjectList = array of TTyRichObject;

  { One paragraph's formatting, immutable once made (internal; see the unit comment). FRuns
    nil means one run in the document's default character format. }
  TTyRichParaData = class
  private
    FRefCount: Integer;
    FPrev, FNext: TTyRichParaData;
    FParaFormat: TTyParaFormatId;
    FCell: TTyRichCell;
    FRuns: TTyRunArray;
    // the file's own marker text of a list item (TTyRichDocument.ListTextOf)
    FListText: UTF8String;
    { The identity of its objects, in order (for the history, which counts each object
      once): 0 when its runs hold none; a value
      made from another one with the very same objects (typing in a paragraph that holds
      pictures) shares that one's key, so the history knows those objects are counted
      without walking them again. }
    FObjKey: Int64;
  end;

  TTyRichChangeKind = (rckText, rckFormat, rckStructure);
  TTyRichChangeKinds = set of TTyRichChangeKind;

  { What a change did: the characters [Pos, Pos+OldLen) became [Pos, Pos+NewLen), and the
    paragraphs FirstPara..FirstPara+OldParaCount-1 became FirstPara..FirstPara+NewParaCount-1.
    rckStructure: paragraphs came or went, or table structure changed. }
  TTyRichChange = record
    Kinds: TTyRichChangeKinds;
    Pos: TTyRichPos;
    OldLen: TTyRichPos;
    NewLen: TTyRichPos;
    FirstPara: Integer;
    OldParaCount: Integer;
    NewParaCount: Integer;
  end;

  TTyRichChangeEvent = procedure(Sender: TObject; const AChange: TTyRichChange) of object;

  { How a plain text file is encoded (tyControls.RichEdit.TextIO reads and writes it).
    teAuto only asks the reader to find out; teAnsi's code page is a number beside it. }
  TTyTextEncoding = (teAuto, teUtf8, teUtf8Bom, teUtf16LE, teUtf16BE, teAnsi);

  TTyRichDocument = class;

  { Count paragraphs in a row that had the same old value: a format change over two million
    plain paragraphs keeps one entry, not two million pointers. }
  TTyRichOldData = record
    Data: TTyRichParaData;
    Count: Integer;
  end;

  { A paragraph ReplaceInParas changed: its index (that edit keeps every paragraph where it
    was), its pieces before - whole, its separator with them (First, Count in
    TTyRichUndoData's swap pieces) - and its value before. }
  TTyRichParaSwap = record
    Para: Integer;
    First, Count: Integer;
    Old: TTyRichParaData;
  end;

  { What a primitive took away, kept so that Revert can put it back: the removed text's pieces
    (with the data of the paragraphs that followed their separators) and the old data of the
    paragraphs that survived. It holds references, no text. Free it when the command that made
    it goes; it must not outlive its document. }
  TTyRichUndoData = class
  private
    FDoc: TTyRichDocument;
    FChange: TTyRichChange;
    FInserted: TTyRichPos;        // characters the change put at FChange.Pos
    FRemoved: TTyRichPieces;      // what it took away there
    { The storage at the places the change split or decoded, as it was (the paragraph's lazy
      piece among them): Revert gives it back once the text is the same again, so a paragraph
      an undo returns to what it was is its file's bytes again. FSpan2: a delete's other
      end, when it is apart from the first. }
    FSpan, FSpan2: TTyRichSpan;
    FFirstPara: Integer;
    FOldData: array of TTyRichOldData;   // run-length: one reference per entry
    FOldCount: Integer;
    // ReplaceInParas: the paragraphs it changed, in the order it changed them
    FSwaps: array of TTyRichParaSwap;
    FSwapCount: Integer;
    FSwapPieces: TTyRichPieceArray;
    FSwapPieceCount: Integer;
    procedure AddOld(D: TTyRichParaData);
    procedure SealOld;
    procedure AddSwap(APara: Integer; AOld: TTyRichParaData; const APieces: TTyRichPieces);
    procedure SealSwaps;
  public
    destructor Destroy; override;
    { Bytes this record keeps alive, for the history's memory limit (the paragraph values
      themselves are shared and not counted, nor the objects they hold: GatherObjects). }
    function MemSize: Int64;
    { Appends the objects the values this record keeps hold (a deleted picture, a paragraph's
      old value with its picture) to AList (ACount used). }
    procedure GatherObjects(var AList: TTyRichObjectList; var ACount: Integer);
    property Change: TTyRichChange read FChange;
  end;

  { The way in for readers (RTF): sets a paragraph's formatting, the document defaults and the
    page, as loading, not as a change - no OnChange, no undo, Modified untouched. Subclass it
    and call the class methods. }
  TTyRichDocBuilder = class
  protected
    { Sets the paragraph's formatting if it has none yet and returns True; leaves a paragraph
      that already has formatting (edited, or parsed before) alone and returns False. ARuns as
      RunsOf returns them: the first starts at 0, starts increase, an object run is one
      character. AListText: the marker text the file gives the paragraph (ListTextOf); a
      value of its own then, never the one plain paragraphs share. }
    class function SetParagraph(ADoc: TTyRichDocument; AIndex: Integer;
      AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray; ACell: TTyRichCell = nil;
      const AListText: UTF8String = ''): Boolean;
    { The value SetParagraph would give paragraph AIndex (the same checks, the runs clipped
      to its text alike), put in no paragraph's slot and held once for the caller, who lets
      it go with ReleaseValue: for a reader that hands a walk what it parsed without setting
      it (TTyRichTextProvider.WalkValue), so that a walk leaves nothing behind. A plain
      paragraph gets the value parsed plain paragraphs share. }
    class function MakeValue(ADoc: TTyRichDocument; AIndex: Integer;
      AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray; ACell: TTyRichCell = nil;
      const AListText: UTF8String = ''): Pointer;
    class procedure SetDefaultCharFormat(ADoc: TTyRichDocument; const AFormat: TTyCharFormat);
    class procedure SetPage(ADoc: TTyRichDocument; APaperWidth, APaperHeight, AMarginLeft,
      AMarginRight: Integer);
    { Puts AText in place of ADoc's whole content - a file opened into an existing document.
      ADoc takes AText over, also when this raises; AText must be one no document has used
      (its paragraph slots nil). The history goes, every paragraph value of the old content
      is let go of, an installed loader goes with the content it parsed, the default
      character format and the page go back to a new document's (a reader that has its own
      sets them afterwards), Modified becomes False, and the source metadata is set; then
      OnChange reports one change of everything:
      Kinds [rckText, rckFormat, rckStructure], Pos 0, the old and new lengths, paragraphs 0
      with the old and new counts (a view throws all its layout away on it). Raises
      ETyRichModel while a command runs, inside BeginUpdate .. EndUpdate, while the document
      is being saved or inside a read scope (BeginRead) - it frees AText then. Without the
      metadata: UTF-8 without a BOM, and the majority line break of AText's load scan. }
    class procedure ReplaceText(ADoc: TTyRichDocument; AText: TTyRichText); overload;
    class procedure ReplaceText(ADoc: TTyRichDocument; AText: TTyRichText;
      AEncoding: TTyTextEncoding; ACodePage: Integer; AHasBom: Boolean;
      ALineBreak: TTyRichSeparator); overload;
    { A reader that loads in slices: while ALoading the document can be read but not changed
      (Execute returns False); AIncomplete: the load stopped before the end of the file, and
      the document stays read-only (a writer must not save it as the file). ReplaceText
      clears both. }
    class procedure SetLoadState(ADoc: TTyRichDocument; ALoading, AIncomplete: Boolean);
    { Raises OnChange for what a slice of loading added (no undo, Modified untouched). }
    class procedure ReportLoad(ADoc: TTyRichDocument; const AChange: TTyRichChange);
    { For a loader that sends parsed paragraphs back to unparsed. ParagraphValue: the
      paragraph's value as it is, without parsing it (nil: none). HoldValue/ReleaseValue
      keep a value alive (so that its identity means "unchanged" while held). UnsetParagraph:
      when the paragraph still has AValue, it becomes unparsed (True). }
    class function ParagraphValue(ADoc: TTyRichDocument; AIndex: Integer): Pointer;
    class procedure HoldValue(ADoc: TTyRichDocument; AValue: Pointer);
    class procedure ReleaseValue(ADoc: TTyRichDocument; AValue: Pointer);
    { Somebody besides the caller's own hold keeps AValue alive: a paragraph has it, or an
      undo record that can put it back. Never True for the one value all plain parsed
      paragraphs share: it says nothing about any one of them. }
    class function ValueShared(ADoc: TTyRichDocument; AValue: Pointer): Boolean;
    { AValue is that one shared value: whether a paragraph that has it is the file's own
      cannot be told from the value - only from what the file makes of the paragraph. }
    class function IsPlainValue(ADoc: TTyRichDocument; AValue: Pointer): Boolean;
    class function UnsetParagraph(ADoc: TTyRichDocument; AIndex: Integer;
      AValue: Pointer): Boolean;
    { A command is running, the text is being changed, or a read scope is open
      (TTyRichDocument.BeginRead): values read earlier are in use, and nothing may be sent
      back to unparsed. }
    class function DocumentBusy(ADoc: TTyRichDocument): Boolean;
  end;

  { Parses paragraphs on demand. EnsureParsed calls LoadParagraph for a paragraph that has no
    formatting yet; it sets that paragraph's (and, if it likes, its neighbours') formatting with
    SetParagraph. A paragraph it leaves unset counts as plain and is not asked about again.
    A loader that sends parsed paragraphs back to unparsed (UnsetParagraph) does so only
    while DocumentBusy is False - never inside a read scope, never while a command runs. }
  TTyRichParaLoader = class(TTyRichDocBuilder)
  public
    procedure LoadParagraph(ADoc: TTyRichDocument; AIndex: Integer); virtual; abstract;
    { A read found paragraph AIndex parsed already: it is in use (for a loader that keeps
      the most recently used paragraphs parsed). Called for every such read: keep it cheap. }
    procedure ParagraphRead(ADoc: TTyRichDocument; AIndex: Integer); virtual;
    { The outermost read scope ended: nothing read inside it is held any longer. }
    procedure ReadsEnded(ADoc: TTyRichDocument); virtual;
  end;

  TTyRichRange = record
    Pos: TTyRichPos;
    Len: TTyRichPos;
  end;

  { A view's selection: its anchor, its caret, and whether the caret stands at the end of a
    wrapped line (its affinity). }
  TTyRichSelectionMark = record
    Anchor: TTyRichPos;
    Caret: TTyRichPos;
    AtLineEnd: Boolean;
  end;

  { Where the view that made a step had its selection before the step and after it
    (TTyRichCommand.Marks): the view's, not the document's - the document only keeps it with
    the step, so that an undo can put the selection back as it was and a redo where the step
    left it, which the change's extent cannot tell (a deleted selection and a character taken
    by Backspace report the same range). A step made by code has none (HasBefore and HasAfter
    False). A merged run of typing keeps the Before of its first insert and the After of its
    last; the marks go with the step when the history lets it go. }
  TTyRichStepMarks = record
    HasBefore: Boolean;
    HasAfter: Boolean;
    Before: TTyRichSelectionMark;
    After: TTyRichSelectionMark;
  end;

  { What a fragment carries of its source's kept bytes into a document whose file's header
    tables are not the source's (TTyRichFragment, AFilter). A format's Extra, a row's
    RawFormat and an opaque object's bytes may name fonts, colours, styles and lists by the
    numbers of the source's tables; in another document those numbers mean the target's
    entries. Who reads such bytes implements it (tyControls.RichEdit.RtfRead's
    TyRichFragmentFilterFor, which also says what is kept where the tables agree); the model
    only asks it. It never changes the source. }
  TTyRichFragmentFilter = class
  public
    { A fragment of a format's Extra (APara: a paragraph format's) goes along. }
    function KeepFragment(const AFragment: RawByteString; APara: Boolean): Boolean; virtual; abstract;
    { A row's RawFormat as the row made again for the target has it. }
    function RowFormat(const ARaw: RawByteString): RawByteString; virtual; abstract;
    { AObj as it goes along: AObj itself; an object made again (a new one no reference was
      taken of - the fragment's paragraph values take theirs); or nil: it is left out, and
      AText ('' none) stands in its character's place, in its run's format. }
    function MapObject(AObj: TTyRichObject; out AText: UTF8String): TTyRichObject; virtual; abstract;
  end;

  { Content of a document of its own (what a reader made of a clipboard's RTF) made ready to
    go into another document at one place - what TTyRichDocument's InsertFragment inserts.
    Made by the target document's terms: the source's character and paragraph formats are
    interned in the target's pool (a run with no font of its own gets the source's default
    font, and the source's default size where it has none: it is shown as it was where it was
    copied, whatever the target's defaults are); objects and tables are shared, each with the
    references the target's paragraph values take (they are immutable, so a second document
    may hold them); the source's document-level things (its page, its default character
    format, its loader) do not come along. The source is only read: the caller frees it, and
    may do so as soon as this is made.

    The paragraphs are "parts": part 0 joins the text before APos, the last part the text after
    it, the ones between are paragraphs of their own, each a value of the target held here (so
    a redo puts the very same values back). AEndsWithParagraph: the source's last paragraph
    ended with a paragraph mark (in RTF, a \par after it): the text after APos then stays a
    paragraph of its own (a last part that is the target's own). Tables: rows go in as rows
    when APos is in no table and AFlatten is False - the paragraph at APos is split before the
    first row when text stands before APos, and after a last row always (no row is ever joined
    with text, no row is left half); otherwise (APos in a cell, or AFlatten) every paragraph
    is a plain paragraph of the cell (or of no table) APos is in: never a nested table. A
    source table one of whose rows holds a nested table (TTyRichRow.HoldsNestedTable) goes in
    as its paragraphs, plain, in no table - the model's own view of the inner table: what made
    it a table is only in the source file's bytes. The
    list markers a file gave are not taken: the numbers are counted, as after any edit.

    AFilter (nil: everything goes as the source has it - what a paste inside one document,
    or between two documents whose files' header tables agree, wants): what the source keeps
    of its file's bytes goes through it - a format's Extra fragment by fragment, each object -
    and its tables are made again for the target, each row with the RawFormat the filter
    gives (the rows are then the fragment's own, not the source's). The filter is used only
    while the fragment is made; the caller frees it.
    The values hold references into the target document: free a fragment before its target. }
  TTyRichFragment = class
  private
    FDoc, FSrc: TTyRichDocument;
    FText: UTF8String;
    FTextLen: PtrInt;
    FParts: array of TTyRichParaData;   // per part (nil: plain), one reference each
    FLens: array of Int64;              // its characters
    FOwn: array of Boolean;             // the target's own: no content, the target's format
    FCount: Integer;
    FFlat: Boolean;
    FFlatCell: TTyRichCell;
    FCharMap, FParaMap: array of Integer;
    FSrcDefault: TTyCharFormat;
    FFilter: TTyRichFragmentFilter;
    // what the first insert put in the text, as its pieces: a redo puts these back instead of
    // copying the text into the add buffer once more (it only grows)
    FPieces: TTyRichPieces;
    FHavePieces: Boolean;
    FTextBytes: Int64;
    // the source's tables met, and what goes in for each (made again, or the very one)
    FTabSrc, FTabNew: array of TTyRichTable;
    FTabCount: Integer;
    procedure AddPart(AValue: TTyRichParaData; ALen: Int64; AOwn: Boolean);
    procedure InsertOwnFirst;
    procedure AddText(P: PByte; ALen: PtrInt);
    function MapChar(AId: TTyCharFormatId): TTyCharFormatId;
    function MapPara(AId: TTyParaFormatId): TTyParaFormatId;
    function MapExtra(const AExtra: TTyOpaqueAttrs; APara: Boolean): TTyOpaqueAttrs;
    function MapCell(ACell: TTyRichCell): TTyRichCell;
    procedure MapObjects(var AText: RawByteString; var ARuns: TTyRunArray; var AChars: Int64);
    procedure TakePara(AIndex: Integer; AData: Pointer; AText: PByte; ALen: PtrInt;
      var AContinue: Boolean);
    function PartCell(AIndex: Integer): TTyRichCell;
  public
    constructor Create(ATarget: TTyRichDocument; APos: TTyRichPos; ASource: TTyRichDocument;
      AEndsWithParagraph: Boolean; AFlatten: Boolean = False;
      AFilter: TTyRichFragmentFilter = nil);
    destructor Destroy; override;
    { Parts (paragraph separators inserted + 1); 0: nothing to insert. }
    property PartCount: Integer read FCount;
    { The tables went in as plain paragraphs. }
    property Flattened: Boolean read FFlat;
    { Characters inserted (separators counted). }
    function CharCount: Int64;
    { Its text and values (the objects they bring: GatherObjects). }
    function MemSize: Int64;
    procedure GatherObjects(var AList: TTyRichObjectList; var ACount: Integer);
  end;

  { A change to a document, and the one way to make one: TTyRichDocument.Execute runs it and
    keeps it for undo. A subclass changes the document in DoExecute through the protected
    InsertText .. MarkTable below - they work only while the document runs this command, and
    each keeps what its primitive returned. So the inherited DoUndo (revert those records,
    newest first) and DoRedo (DoExecute again: after an exact undo the same arguments give
    the same result) are already right for a command that only calls them. }
  TTyRichCommand = class
  private
    FRecords: array of TTyRichUndoData;
    FRecordCount: Integer;
    FSummary: TTyRichChange;
    FChanged: Boolean;
    FDoc: TTyRichDocument;    // the document running this command, nil otherwise
    FMarks: TTyRichStepMarks;
    { The document's states (TTyRichDocument's saved point) before this step ran and after
      it: an undo goes back to the one, a redo forward to the other. }
    FStateBefore, FStateAfter: Int64;
    procedure CheckRunning(ADoc: TTyRichDocument);
    function Keep(AUndo: TTyRichUndoData): TTyRichChange;
    procedure AddSummary(const AChange: TTyRichChange);
    procedure ResetSummary;
    procedure FreeRecords;
  protected
    procedure DoExecute(ADoc: TTyRichDocument); virtual; abstract;
    { Reverts the kept records, newest first. }
    procedure DoUndo(ADoc: TTyRichDocument); virtual;
    { Runs DoExecute again. }
    procedure DoRedo(ADoc: TTyRichDocument); virtual;

    { The document's primitives (see TTyRichDocument), for DoExecute. Each returns what the
      change did. Called when this command is not being run by ADoc, they raise. }
    function InsertText(ADoc: TTyRichDocument; APos: TTyRichPos; const AText: UTF8String;
      AFormat: TTyCharFormatId = TyRichInheritFormat): TTyRichChange;
    function InsertObject(ADoc: TTyRichDocument; APos: TTyRichPos; AObject: TTyRichObject;
      AFormat: TTyCharFormatId = TyRichInheritFormat): TTyRichChange;
    function DeleteRange(ADoc: TTyRichDocument; APos, ALen: TTyRichPos): TTyRichChange;
    function ApplyCharFormat(ADoc: TTyRichDocument; APos, ALen: TTyRichPos;
      AMask: TTyCharFormatMask; const AValue: TTyCharFormat;
      AKeepNone: TTyCharFormatMask = []): TTyRichChange;
    function ApplyParaFormat(ADoc: TTyRichDocument; AFirstPara, ALastPara: Integer;
      AMask: TTyParaFormatMask; const AValue: TTyParaFormat): TTyRichChange;
    function MarkTable(ADoc: TTyRichDocument; AFirstPara: Integer; ATable: TTyRichTable;
      const ACellParas: array of Integer): TTyRichChange;
    function InsertFragment(ADoc: TTyRichDocument; APos: TTyRichPos;
      AFragment: TTyRichFragment): TTyRichChange;
    function ReplaceInParas(ADoc: TTyRichDocument; const APos: array of TTyRichPos;
      AFrom, ACount: Integer; ALen: TTyRichPos; const AText: UTF8String;
      out ASkipped: Integer): TTyRichChange;
    { One more part of this command's work, as part of the step it is
      (TTyRichDocument.ExecutePart): it changes the document through the primitives as DoExecute
      does; its records join the step's. The default raises: a command goes on only when it
      says how. }
    procedure DoContinue(ADoc: TTyRichDocument); virtual;
    { What the records from AFrom on keep (their MemSize), for a command that counts its own
      size as it goes. }
    function RecordsSize(AFrom: Integer): Int64;

    { For a command made of commands: runs, undoes or redoes AChild as part of this one, and
      counts its change as this command's. A child whose execute or redo raises is reverted
      first. }
    procedure ExecuteChild(ADoc: TTyRichDocument; AChild: TTyRichCommand);
    procedure UndoChild(ADoc: TTyRichDocument; AChild: TTyRichCommand);
    procedure RedoChild(ADoc: TTyRichDocument; AChild: TTyRichCommand);
    { Counts the change of AChild, which has already run, as this command's. }
    procedure AdoptChange(AChild: TTyRichCommand);
    { For TryMerge: takes ANext's records (they are reverted before this command's own) and
      its change. }
    procedure TakeOver(ANext: TTyRichCommand);
    property RecordCount: Integer read FRecordCount;
  public
    destructor Destroy; override;
    { False: Execute leaves the document alone and frees the command. }
    function CanExecute(ADoc: TTyRichDocument): Boolean; virtual;
    { ANext ran right after this command; True when this command took it over (TakeOver),
      and the history then frees ANext. }
    function TryMerge(ANext: TTyRichCommand): Boolean; virtual;
    { For the undo menu. }
    function Description: string; virtual;
    { The characters the command changed, in the document as it left it. }
    function ChangedRange: TTyRichRange;
    { Bytes the history keeps for it (MaxUndoBytes): its own - records, texts -, without the
      objects it holds, which GatherObjects names and the history counts once each however
      many steps hold them. }
    function MemSize: Int64; virtual;
    { Appends the objects this step keeps alive to AList (ACount used): those of its records;
      a command that holds an object itself adds it (TTyRichInsertObject, a fragment's, a
      composite's parts'). }
    procedure GatherObjects(var AList: TTyRichObjectList; var ACount: Integer); virtual;
    { Its last run changed something; one that did not is not kept in the history. }
    property Changed: Boolean read FChanged;
    { What its last execute or redo changed, composed as the document reports it (inside the
      document's update the observers hear it only as part of the block's one change, so a
      view that places its own edits there reads it here). Meaningful when Changed. }
    property Change: TTyRichChange read FSummary;
    { The selection of the view that made this step, before it and after it (see
      TTyRichStepMarks). The document never reads or changes them; TakeOver (a merge) keeps
      this command's Before and takes ANext's After. }
    property Marks: TTyRichStepMarks read FMarks write FMarks;
    { Another step went on top of this one in the history: it is not the top step any more,
      so it will not be continued (ExecutePart goes on with the top step only) - a command that
      holds what only its next part would need lets go of it here. Nothing by default. }
    procedure Covered; virtual;
  end;

  TTyRichKeyList = array of Int64;

  TTyRichHistoryEntry = record
    Cmd: TTyRichCommand;
    Bytes: Int64;                 // the step's own (MemSize)
    Objs: TTyRichObjectList;      // the distinct objects it holds, each counted in FObjHolds
    { The object keys (TTyRichParaData.FObjKey) of the values whose objects are in Objs: a
      value with one of them adds nothing when a merge brings it. }
    Keys: TTyRichKeyList;
  end;

  { How many steps of the history hold each object: an object counts toward the
    history's bytes once, while at least one step holds it. }
  TTyRichObjHolds = specialize TDictionary<Pointer, Integer>;
  // the object keys a gathering has met (or skips)
  TTyRichKeySet = specialize TDictionary<Int64, Boolean>;

  TTyRichDocument = class
  private
    // history
    FUndo: array of TTyRichHistoryEntry;
    FUndoCount: Integer;
    FRedo: array of TTyRichHistoryEntry;
    FRedoCount: Integer;
    FHistoryBytes: Int64;
    FHistoryObjectVisits: Int64;
    FObjHolds: TTyRichObjHolds;
    { A gathering of a step's objects (BeginGather .. EndGather): the keys met or skipped -
      a value whose key is here adds nothing -, the ones met first, and the next key. }
    FGathering: Boolean;
    FKeyMet: TTyRichKeySet;
    FGatherKeys: TTyRichKeyList;
    FGatherKeyCount: Integer;
    FNextObjKey: Int64;
    FMaxUndoBytes: Int64;
    FMergeBroken: Boolean;
    FRunning: TTyRichCommand;
    FUpdateCount: Integer;
    FBlock: array of TTyRichCommand;
    FBlockCount: Integer;
    FBlockDescription: string;
    FHold: Integer;
    FPending: TTyRichChange;
    FHasPending: Boolean;
    { The saved point: every content the document goes through has a number of its own
      (FState), never given twice (FNextState); FSavedState is the number of the content last
      loaded or saved (-1: none it can come back to). A step remembers the numbers before and
      after it, so an undo or a redo brings back the number with the content. }
    FState, FSavedState, FNextState: Int64;
    FModifiedSeen: Boolean;
    FOnModifiedChange: TNotifyEvent;
    function NewState: Int64;
    function GetModified: Boolean;
    procedure SetModified(AValue: Boolean);
    { The content changed outside the history (a primitive outside a command, an edit straight
      on Text, an undo that failed): a number of its own, and the saved point is gone. }
    procedure LeftHistory;
    { OnModifiedChange when Modified is not what it was when it was last raised. }
    procedure NoteModified;
    procedure RunStep(ACmd: TTyRichCommand; AStep: Integer);
    procedure Flush;
    procedure PushUndo(ACmd: TTyRichCommand);
    procedure HoldObjects(var AEntry: TTyRichHistoryEntry);
    procedure LetGoObjects(var AEntry: TTyRichHistoryEntry);
    { A gathering that passes over the values whose key is in ASkip or met before in it;
      EndGather gives the keys it met. MeetKey: True the first time a key is met. }
    procedure BeginGather(const ASkip: array of Int64);
    function EndGather: TTyRichKeyList;
    function MeetKey(AKey: Int64): Boolean;
    { The distinct objects of AList[0..ACount) the step does not hold yet are held by it
      (counted once in the history's bytes), and AKeys join its keys: what a merge brings. }
    procedure HoldMore(var AEntry: TTyRichHistoryEntry; var AList: TTyRichObjectList;
      ACount: Integer; const AKeys: TTyRichKeyList);
    procedure DropOldestUndo;
    procedure ClearRedo;
    procedure ClearHistory;
    procedure TrimHistory;
    procedure SetMaxUndoBytes(AValue: Int64);
    procedure CheckIdle(const AWhat: string);
  private
    FText: TTyRichText;
    FFormats: TTyFormatPool;
    FDefaultCharFormat: TTyCharFormat;
    FDefaultCharId: TTyCharFormatId;
    FDefaultParaId: TTyParaFormatId;
    FDefaultRuns: TTyRunArray;
    FPaperWidth: Integer;
    FPaperHeight: Integer;
    FMarginLeft: Integer;
    FMarginRight: Integer;
    FOnChange: TTyRichChangeEvent;
    FOnUpdatingEnd: TNotifyEvent;
    FLoader: TTyRichParaLoader;
    FOwnsLoader: Boolean;
    FInLoad: Boolean;
    FPlainParsed: TTyRichParaData;
    FFirstData: TTyRichParaData;
    FLiveData: Integer;
    FEditing: Integer;
    FReading: Integer;
    FValuesGone: Boolean;
    FSourceEncoding: TTyTextEncoding;
    FSourceCodePage: Integer;
    FSourceHasBom: Boolean;
    FDominantLineBreak: TTyRichSeparator;
    FLoadingContent: Boolean;
    FIncomplete: Boolean;
    FSaving: Integer;
    FBaseFontName: string;
    function GetSaving: Boolean;
    function GetUpdating: Boolean;
    procedure Init;
    procedure ResetContent(AText: TTyRichText; AEncoding: TTyTextEncoding; ACodePage: Integer;
      AHasBom: Boolean; ALineBreak: TTyRichSeparator);
    procedure SetDefaults(const AFormat: TTyCharFormat);
    procedure SetDefaultPage;
    procedure TextParasChanged(Sender: TObject; AFirst, AOldCount, ANewCount: Integer);
    procedure TextDataDropped(Sender: TObject; AData: Pointer);
    // paragraph values
    function NewData(AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray;
      ACell: TTyRichCell): TTyRichParaData;
    procedure DisposeData(D: TTyRichParaData);
    procedure AcquireData(D: TTyRichParaData);
    procedure ReleaseData(D: TTyRichParaData);
    function PlainValue: TTyRichParaData;
    function MakeData(AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray;
      ACell: TTyRichCell): TTyRichParaData;
    function MakeDataLike(AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray;
      ACell: TTyRichCell; AFrom: TTyRichParaData): TTyRichParaData;
    procedure PutData(AIndex: Integer; AOld, ANew: TTyRichParaData);
    function SlotData(AIndex: Integer): TTyRichParaData;
    function DataOf(AIndex: Integer): TTyRichParaData;
    function RunsOfData(D: TTyRichParaData): TTyRunArray; inline;
    function FormatOfData(D: TTyRichParaData): TTyParaFormatId; inline;
    function CellOfData(D: TTyRichParaData): TTyRichCell; inline;
    procedure ClipRuns(AIndex: Integer);
    // edits
    function NewUndo(const AChange: TTyRichChange): TTyRichUndoData;
    procedure Notify(const AChange: TTyRichChange);
    function InsertCore(APos: TTyRichPos; const AText: UTF8String; AFormat: TTyCharFormatId;
      AObj: TTyRichObject): TTyRichUndoData;
    procedure CheckCharId(AId: TTyCharFormatId);
    procedure CheckParaId(AId: TTyParaFormatId);
    function DeleteCore(APos, ALen: TTyRichPos): TTyRichUndoData;
    function FixedData(D: TTyRichParaData): Boolean; inline;
    function FixedRowAt(AIndex: Integer): TTyRichRow;
    function RowAt(AIndex: Integer): TTyRichRow;
    function ChangeRefused(APos, ALen: TTyRichPos): Boolean;
    procedure RevertSwaps(AUndo: TTyRichUndoData);
  protected
    { The modification primitives. Each changes the document, raises OnChange, sets Modified
      and returns what Revert needs to undo it exactly (never nil; a no-op returns an empty
      record and notifies nothing). Undo records must be reverted in the reverse order they
      were made. A redo runs the primitive again.

      A row that holds a nested table (TTyRichRow.HoldsNestedTable) stays as it is:
      InsertText, InsertObject and DeleteRange raise ETyRichModel, before anything changes,
      when they would change a paragraph of such a row or take away a part of the row
      (CanChange says which); ApplyCharFormat and ApplyParaFormat leave the paragraphs of
      such rows as they are and change the rest of their range. }

    { AText may hold paragraph separators. A split gives every part the paragraph's format and
      cell; the runs split at APos. AFormat: a character format id, or TyRichInheritFormat.
      AText must not start with a byte that continues a UTF-8 sequence nor end inside one
      (raises ETyRichModel before anything changes): the storage would count those bytes as
      other characters than a reader of the paragraph's bytes does. A byte that is no text
      inside it (a stray continuation in the middle) is a character of its own, as in a file. }
    function InsertText(APos: TTyRichPos; const AText: UTF8String;
      AFormat: TTyCharFormatId = TyRichInheritFormat): TTyRichUndoData;
    { Inserts the object's U+FFFC; the document takes a reference to AObject. }
    function InsertObject(APos: TTyRichPos; AObject: TTyRichObject;
      AFormat: TTyCharFormatId = TyRichInheritFormat): TTyRichUndoData;
    { Across paragraphs (as WordPad): the merged paragraph takes the format of the paragraph
      the range ends in, except when the range is one separator and nothing else and the
      paragraph before it is not empty - then the format of that paragraph. (The separator
      of an empty paragraph takes the empty paragraph away: what follows stays as it is.) }
    function DeleteRange(APos, ALen: TTyRichPos): TTyRichUndoData;
    { Changes only the AMask fields of every run in the range (an empty paragraph whose
      separator is in the range: its one run). Paragraphs of a row that holds a nested
      table are passed over. AKeepNone (cffFontName, cffSize): a run that has no name / size
      of its own keeps none - for a view that writes the value such text is shown in, which
      it shows already (the base's value is not frozen into it). }
    function ApplyCharFormat(APos, ALen: TTyRichPos; AMask: TTyCharFormatMask;
      const AValue: TTyCharFormat; AKeepNone: TTyCharFormatMask = []): TTyRichUndoData;
    { Paragraphs of a row that holds a nested table are passed over. }
    function ApplyParaFormat(AFirstPara, ALastPara: Integer; AMask: TTyParaFormatMask;
      const AValue: TTyParaFormat): TTyRichUndoData;
    { Makes the paragraphs from AFirstPara on a table: ACellParas[i] paragraphs for each cell,
      row by row. ATable must not be in use; the paragraphs must not be in a table. }
    function MarkTable(AFirstPara: Integer; ATable: TTyRichTable;
      const ACellParas: array of Integer): TTyRichUndoData;
    { Inserts AFragment (made for this document at APos) at APos: its text in one insert, then
      its parts' values in the paragraphs it made. How a part meets the paragraph at APos - the
      paragraph format goes with the paragraph's end, as in Word: a paragraph that ends with a
      paragraph mark of the fragment has that paragraph's format, one that ends with a mark of
      this document has its own. So part 0 joined with the text before APos takes part 0's
      format (unless the fragment is one part: inline, the paragraph keeps its own), the last
      part joined with the text after APos keeps the paragraph's format and cell, and the
      parts between are the fragment's paragraphs. Runs: the text before APos keeps its runs,
      each part's follow, then the text after APos. One undo record, of an insert's size: a
      revert deletes the inserted characters and gives the paragraph at APos its value back.
      Refused (ETyRichModel, before anything changes) inside a row that holds a nested table. }
    function InsertFragment(APos: TTyRichPos; AFragment: TTyRichFragment): TTyRichUndoData;
    { Replaces the matches APos[AFrom .. AFrom + ACount - 1] - rising, none overlapping, each
      inside one paragraph (no separator in it) - of ALen characters each by AText (no
      separator either), each in the format of the first character it replaces; the
      paragraphs' formats, cells and objects stay. A paragraph of a row that holds a nested
      table keeps its matches (ASkipped counts them). One record for all of them, small:
      for each paragraph changed its pieces before and its value before - references, no
      text: a few dozen bytes a paragraph however many matches it holds. Matches closer
      than a few hundred characters are one stretch of the text: what lies between them is
      copied with the replacements, so the text keeps few pieces. Revert gives each
      paragraph its pieces and its value back (a lazily read one is its file's bytes again,
      so that an edit undone saves the file as it was; the paragraph after it the value it
      had). For a replace of every match
      (tyControls.RichEdit.Find's TTyRichReplaceAllCommand). Raises ETyRichModel for
      matches out of order or range, a separator in them or in AText, before anything
      changes. }
    function ReplaceInParas(const APos: array of TTyRichPos; AFrom, ACount: Integer;
      ALen: TTyRichPos; const AText: UTF8String; out ASkipped: Integer): TTyRichUndoData;
    { Puts back what the primitive that returned AUndo changed, frees AUndo and sets it nil. }
    procedure Revert(var AUndo: TTyRichUndoData);
    { The paragraph's data value (an opaque identity, for tests and the history). }
    function ParaDataOf(AIndex: Integer): Pointer;
    function IsLiveParaData(AData: Pointer): Boolean;
    property LiveParaData: Integer read FLiveData;
  public
    constructor Create;
    { The buffer is referenced, not copied (TTyRichText.CreateFromUtf8). }
    constructor CreateFromUtf8(const ABuffer: TBytes);
    { Takes ownership of AText, e.g. a lazy text from the RTF scan. }
    constructor CreateOnText(AText: TTyRichText);
    destructor Destroy; override;

    { Install right after creating the document, before anything reads it. }
    procedure InstallLoader(ALoader: TTyRichParaLoader; AOwnsLoader: Boolean);
    procedure EnsureParsed(AIndex: Integer);
    { A read scope, counted (BeginRead .. EndRead may nest; pair them with try .. finally).
      In a document that parses on demand, a read may send paragraphs read earlier back to
      unparsed, and the tables, cells and objects they gave out go with them: what TableAt,
      CellAt or a run's Obj returned is good until the next read. Inside a read scope nothing
      is sent back, and a load into the document is refused (ETyRichModel): everything read
      stays as it was returned until the outermost EndRead.
      So whoever holds a table, a cell or an object across another read does it inside one -
      a layout pass over the visible paragraphs, a save, TableParas and CellParas themselves.
      (Format ids, RunsOf's copy and text are values: they need no scope. A running command
      is a scope by itself.) A scope costs nothing to open; keep it as short as the pass it
      protects: parsed paragraphs only pile up while it is open. }
    procedure BeginRead;
    procedure EndRead;
    { A save is in progress, counted (pair them with try .. finally; the writers do it
      themselves). A save plans with the paragraphs as they are when it starts, and its
      progress callback or its stream may let the application run - so in between nothing
      may change the document: Execute returns False, Undo and Redo do nothing (CanUndo and
      CanRedo are False), as while the document is Loading, and a load into it (any reader's,
      through TTyRichDocBuilder.ReplaceText) raises ETyRichModel and leaves it as it was.
      Reading is fine. }
    procedure BeginSave;
    procedure EndSave;

    function ParaFormatOf(AIndex: Integer): TTyParaFormatId;
    { A copy: the paragraph's runs. A plain paragraph has one run in DefaultCharFormatId. }
    function RunsOf(AIndex: Integer): TTyRunArray;
    { The format text typed at APos gets. }
    function TypingFormatAt(APos: TTyRichPos): TTyCharFormatId;
    function TableAt(AIndex: Integer): TTyRichTable;
    function CellAt(AIndex: Integer): TTyRichCell;
    { The paragraph range of the table AIndex is in; False outside a table. Walks the table's
      paragraphs. }
    function TableParas(AIndex: Integer; out AFirst, ALast: Integer): Boolean;
    { The paragraph range of ACell, a cell of the table AIndex is in. Walks the paragraphs
      between AIndex and the cell. In a document that parses on demand, read ACell and call
      this inside one read scope (BeginRead). }
    function CellParas(AIndex: Integer; ACell: TTyRichCell; out AFirst, ALast: Integer): Boolean;
    { What a paragraph's value holds, for a reader that walks the text itself and has the
      value from the walk (AData of TTyRichText.WalkParas and WalkParaTexts): the
      paragraph's format, runs and cell with no lookup, nothing parsed, and without the
      loader hearing of a read. A paragraph with no value (AData nil) is plain - but in a
      document that parses on demand it is one not parsed yet: False then, and the caller
      reads it by its index (ParaFormatOf, RunsOf, CellAt), which parses it. ARuns is the
      value's own array, not a copy: it is not to be changed. What is returned is good
      while the value is the paragraph's: until the document is changed, and for a cell or
      an object inside a read scope (BeginRead). A walk that asks for values (WalkParaTexts
      with AValues) hands an unparsed paragraph of a reader that parses on demand a value
      of the moment instead of nil: True for it, and what it gives is good during that call
      only - a cell or an object kept past it needs a reference of its own (a cell's
      table's AddRef); the paragraph stays unparsed. }
    function ReadValue(AData: Pointer; out AFormat: TTyParaFormatId; out ARuns: TTyRunArray;
      out ACell: TTyRichCell): Boolean;
    { The marker text the file gave list paragraph AIndex - its {\listtext ...} or {\pntext ...},
      decoded as the reader decodes text, the tab and spaces at its end dropped: the number
      Word or WordPad showed ("2.", "iii)"). '' when the file gave none, for a document not
      read from RTF, and for a paragraph an edit made (inserted, the later parts of a split);
      an edit inside a paragraph (typing, a format, a split's first part, a join's first
      paragraph) keeps it, and an undo brings back what it had - the value; whether a layout
      shows it is the layout's business (TTyRichLayouter stops trusting the markers from a
      change that can renumber on, and an undo does not bring that trust back). Read only: it
      is not written (a paragraph written back as its bytes has its own; one written from the model gets
      the marker the writer generates), takes no part in format equality, and goes with the
      paragraph's value when a document that parses on demand lets the paragraph go. Parses
      the paragraph (as RunsOf). }
    function ListTextOf(AIndex: Integer): UTF8String;
    { The same from a value of a walk (AData as ReadValue takes it): no lookup, nothing
      parsed; '' for none. }
    function ValueListText(AData: Pointer): UTF8String;
    { May the text change here: False when inserting at APos (ALen 0) or deleting ALen
      characters from APos would be refused because of a row that holds a nested table
      (TTyRichRow.HoldsNestedTable). Inserting is refused inside a paragraph of such a row.
      Deleting is refused when a paragraph of such a row would lose characters or be joined
      with another, or when the row would lose some of its paragraphs but not all: a range
      that takes whole such rows away, with whatever is around them, is fine. A range that
      is not inside the text is not this question (True; the primitive raises). Parses the
      paragraphs at the range's ends. A command asks this in CanExecute; the insert and
      delete commands do. }
    function CanChange(APos, ALen: TTyRichPos): Boolean;
    { The one place of the rule that a user's edit never joins text across a cell's or a
      row's edge (until table editing): may [AStart, AStart + ALen) be
      deleted or replaced as a user's edit - a key, the menu, a find's replace? The paragraph
      the deletion then joins with counts: the range INCLUDING the paragraph after it must not
      cross a cell's or a row's edge, unless it is whole rows (WholeRows). A range that begins
      outside a table and ends exactly where the table's first row starts keeps its last
      separator (ALen one less: the paragraph before the table stays, Word's way) - a caller
      that cannot take a shorter range treats that as a refusal. False: refused. Reads the
      cells inside a read scope of its own. }
    function UserRangeAllowed(var AStart, ALen: TTyRichPos): Boolean;
    { [AFrom, ATo) is whole rows of one table: from a row's first paragraph's start to the
      start of the paragraph after a row (never the text's end). Call it inside a read scope. }
    function WholeRows(AFrom, ATo: TTyRichPos): Boolean;

    { Runs ACmd and keeps it for undo; the document owns ACmd from here on, also when this
      returns False or raises. False: ACmd.CanExecute said no, or the document is Loading,
      Incomplete or Saving, and nothing changed. A command that changed nothing is not kept.
      Consecutive typing merges into one step until
      BreakMerge, an Undo or Redo, or any other command. A new command drops the redo side.
      Outside BeginUpdate .. EndUpdate it raises OnChange once. Raises inside a running
      command; if ACmd raises, what it did is reverted first. }
    function Execute(ACmd: TTyRichCommand): Boolean;
    { One step back / forward, one OnChange. Nothing to undo / redo, or the document is
      Saving: nothing happens. They raise inside BeginUpdate .. EndUpdate or a running
      command. }
    { Runs one more part of ACmd (TTyRichCommand.DoContinue) as part of the step it is: the
      work of a command that runs in parts - a replace of every match, range by range - is
      one undo step, never merged with another, the document consistent and reported
      between two parts. ACmd must be the newest undo step and the content the one it left:
      nothing changed since (no edit, undo or redo; the redo side empty), no saved point set
      on it since (Modified := False, a save: the step would carry its "after" past it), no
      update block open, the document not loading, incomplete or saving. Otherwise False,
      and nothing ran - nothing of the part is anywhere, the redo side included. True: the
      part ran; what it changed is reported (one OnChange) and joins the step (its bytes,
      its objects; the history trimmed as after any step). If the part raises, what it did
      is reverted and the step is as it was (were the revert to fail, the history goes, as
      for a failed undo). BreakMerge does not stop it: the step merges with nothing. }
    function ExecutePart(ACmd: TTyRichCommand): Boolean;
    procedure Undo;
    procedure Redo;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    { Every undo and redo step goes; the content stays as it is (not Modified by it). Raises
      inside BeginUpdate .. EndUpdate or a running command. }
    procedure ClearUndo;
    function UndoDescription: string;    // '' when there is nothing
    function RedoDescription: string;
    { The step Undo takes back next / Redo puts in next (nil: none), for a view that keeps its
      selection with the step it made (TTyRichCommand.Marks). The history owns it: it is
      good until the history changes. }
    function UndoStep: TTyRichCommand;
    function RedoStep: TTyRichCommand;
    { Nested. The commands executed until the outermost EndUpdate become one undo step
      (TTyRichCompositeCommand, described by ADescription of the outermost BeginUpdate, or by
      its only command), and that EndUpdate raises the block's one OnChange covering all of
      it. A block that changed nothing keeps nothing and raises nothing. }
    procedure BeginUpdate(const ADescription: string = '');
    procedure EndUpdate;
    { True while the document holds its changes back from OnChange: from BeginUpdate to the
      outermost EndUpdate, and while a command (or an undo or redo step) runs. The text may
      then differ from what an observer last heard of: a view must not look its blocks up by
      what it knows until the change is reported (it is False again inside that OnChange). }
    property Updating: Boolean read GetUpdating;
    { Updating turned False: raised at the outermost EndUpdate and at the end of a command's,
      an undo's or a redo's run (outside an update), after the OnChange that reports what
      changed - also when nothing changed and nothing was reported. Updating is False inside
      it. What an observer put off while the document held its changes back is done here. }
    property OnUpdatingEnd: TNotifyEvent read FOnUpdatingEnd write FOnUpdatingEnd;
    { The caret moved: the next typing does not merge with the typing before. }
    procedure BreakMerge;
    property UndoDepth: Integer read FUndoCount;
    property RedoDepth: Integer read FRedoCount;
    { What the undo and redo steps keep, as their MemSize when they were stored. }
    property HistoryBytes: Int64 read FHistoryBytes;
    { Object references the history's byte count looked at (for tests that check it takes
      one pass: a step's count is done when the step is stored). }
    property HistoryObjectVisits: Int64 read FHistoryObjectVisits write FHistoryObjectVisits;
    { The history's limit: past it the oldest undo steps go, never the newest. 0 or less: no
      limit. }
    property MaxUndoBytes: Int64 read FMaxUndoBytes write SetMaxUndoBytes;

    { Read it; changing it directly bypasses the model (no undo, no OnChange: the touched
      paragraph's runs are only clipped to its text, new paragraphs are plain). Such a change
      also loses to a later undo of a step whose range it overlaps: the undo gives back the
      pieces the step's edit split (TTyRichText.RestoreSpan), which holds the text from
      before the bypass where it has the same length. }
    property Text: TTyRichText read FText;
    property Formats: TTyFormatPool read FFormats;
    property DefaultCharFormat: TTyCharFormat read FDefaultCharFormat;
    property DefaultCharFormatId: TTyCharFormatId read FDefaultCharId;
    property DefaultParaFormatId: TTyParaFormatId read FDefaultParaId;
    property PaperWidth: Integer read FPaperWidth;      // twips
    property PaperHeight: Integer read FPaperHeight;
    property MarginLeft: Integer read FMarginLeft;
    property MarginRight: Integer read FMarginRight;
    property Loader: TTyRichParaLoader read FLoader;
    { The content differs from the one last loaded or saved. The history remembers the
      saved point: Modified is False exactly when the document is at that content again - an
      undo back to it, a redo forward to it - and True otherwise; True for good (until the next
      Modified := False or load) once the step that led back to it is gone (the history's
      memory bound dropped it, ClearUndo, a new step after an undo past it) or the content was
      changed outside the history (a primitive outside a command, an edit straight on Text, an
      undo that failed). ClearUndo at the saved point keeps it: the content is still that one.
      A load (ReplaceText) sets the saved point. Modified := False sets it here (and the next
      typing does not merge into the step before: an undo can come back here);
      Modified := True forces True until the next saved point. Not a change: no OnChange. }
    property Modified: Boolean read GetModified write SetModified;
    { Modified turned (raised at the end of the step, the undo, the redo, the update block,
      the load or the assignment that turned it; an edit straight on Text is noticed at the
      next of these). }
    property OnModifiedChange: TNotifyEvent read FOnModifiedChange write FOnModifiedChange;
    { The number of the content as it is now (Modified's): a step, an undo, a redo, a load
      or an edit outside the history gives another one; the same number is the same
      content. What a reader may remember an answer by (the control's
      ConsistentAttributes). A lazy load's slices and parses change no content and keep it. }
    property ContentState: Int64 read FState;
    property OnChange: TTyRichChangeEvent read FOnChange write FOnChange;

    { Where the content came from, so a text file goes back out as it came in; set by the
      reader through TTyRichDocBuilder.ReplaceText. A new document: teUtf8, no BOM, code
      page 0 (it is the ANSI code page only for teAnsi). }
    property SourceEncoding: TTyTextEncoding read FSourceEncoding;
    property SourceCodePage: Integer read FSourceCodePage;
    property SourceHasBom: Boolean read FSourceHasBom;
    { The kind of line break every inserted one becomes (InsertText turns CR, LF and CRLF in
      the inserted text into it; the breaks already there stay as they are). The file's
      majority kind; a new document, a tie or a text without one: the platform's. }
    property DominantLineBreak: TTyRichSeparator read FDominantLineBreak;
    { A reader is still loading the content in slices: what is there can be read, scrolled
      and laid out, but not changed (Execute returns False) until the last slice is in. }
    property Loading: Boolean read FLoadingContent;
    { The load was cancelled: the document holds only the part of the file read before, and
      stays read-only; a writer must refuse to save it in place of that file. }
    property Incomplete: Boolean read FIncomplete;
    { Inside BeginSave .. EndSave: the document cannot be changed. }
    property Saving: Boolean read GetSaving;
    { The font a view shows the text in that names none of its own (a character format's
      FontName '' is "the view's font"): TTyRichEdit puts its base font here. Not content -
      no command, no OnChange, not Modified, kept by a load - but what a writer names when it
      must: RTF written for a document that was not read from RTF (a new one, a text file)
      defines it as \f0, the document's default font, with the charset its name or the text
      in it calls for. '' (a document no view set it for): such text is written in no font. }
    property BaseFontName: string read FBaseFontName write FBaseFontName;
  end;

function TyDefaultCharFormat: TTyCharFormat;
function TyDefaultParaFormat: TTyParaFormat;
function TyMergeCharFormat(const ABase: TTyCharFormat; AMask: TTyCharFormatMask;
  const AValue: TTyCharFormat): TTyCharFormat;
function TyMergeParaFormat(const ABase: TTyParaFormat; AMask: TTyParaFormatMask;
  const AValue: TTyParaFormat): TTyParaFormat;
{ U+FFFC in UTF-8, the character an object occupies. }
function TyRichObjectChar: UTF8String;
{ The platform's line break (sLineBreak) as a separator kind. }
function TyRichPlatformLineBreak: TTyRichSeparator;
{ The kind most of the counted breaks are; a tie for the most, or no break at all: the
  platform's. }
function TyRichMajorityLineBreak(ACR, ALF, ACRLF: Int64): TTyRichSeparator;
{ The caret's word rule (what a double click and Ctrl+Left / Right take, and a find's whole
  word): white space (a space, a tab, U+00A0, U+000B) and ASCII punctuation are no word (0),
  an object (U+FFFC) is a word by itself (2), every other character is a word character (1) -
  letters, digits, ideographs, marks, a byte that is no text. A paragraph's end (a find's
  $FFFFFFFF) and "no character" ($FFFFFFFE, before the text's start) are no word. }
function TyRichWordClass(C: Cardinal): Integer;
{ A character of a script written without spaces - Hangul Jamo and syllables, the CJK
  radicals, punctuation, kana, Bopomofo, the ideographs of every extension, Yi, the
  compatibility ideographs and forms, the full-width forms: a word ends on both of its sides
  (a find's whole word). The line breaker's set (tyControls.Painter's TyIsCJKCodepoint, a unit
  of the controls this one does not use; a test holds the two equal). }
function TyRichNoSpaceScript(C: Cardinal): Boolean;

implementation

uses
  tyControls.StrConsts, tyControls.RichEdit.Commands, tyControls.RichEdit.Wmf;

const
  // RunStep
  StepExecute = 0;
  StepUndo = 1;
  StepRedo = 2;
  DefaultMaxUndoBytes = 64 * 1024 * 1024;

// hashes wrap around on purpose, also in a build with overflow and range checks
{$PUSH}{$Q-}{$R-}

const
  HashBasis = Cardinal(2166136261);
  HashPrime = Cardinal(16777619);

function HashMix(AHash, AValue: Cardinal): Cardinal; inline;
begin
  Result := (AHash xor AValue) * HashPrime;
end;

function HashBytes(AHash: Cardinal; P: PByte; ACount: Integer): Cardinal;
var
  i: Integer;
begin
  Result := AHash;
  for i := 0 to ACount - 1 do
    Result := (Result xor P[i]) * HashPrime;
end;

function HashStr(AHash: Cardinal; const S: RawByteString): Cardinal; inline;
begin
  Result := HashMix(HashBytes(AHash, PByte(PAnsiChar(S)), Length(S)), Length(S));
end;

function SameBytes(const A, B: RawByteString): Boolean; inline;
begin
  // byte compare: comparing with = could convert between code pages
  Result := (Length(A) = Length(B)) and
    ((Length(A) = 0) or (CompareByte(A[1], B[1], Length(A)) = 0));
end;

function TyRichNoSpaceScript(C: Cardinal): Boolean;
begin
  Result :=
    ((C >= $1100) and (C <= $11FF)) or     // Hangul Jamo
    ((C >= $2E80) and (C <= $A4CF)) or     // radicals .. CJK punctuation .. kana .. Ext-A .. Yi
    ((C >= $AC00) and (C <= $D7A3)) or     // Hangul syllables
    ((C >= $F900) and (C <= $FAFF)) or     // CJK compatibility ideographs
    ((C >= $FE30) and (C <= $FE4F)) or     // CJK compatibility forms
    ((C >= $FF00) and (C <= $FF60)) or     // full-width forms
    ((C >= $FFE0) and (C <= $FFE6)) or     // full-width signs
    ((C >= $20000) and (C <= $2FA1F));     // CJK Ext B-F
end;

function TyRichWordClass(C: Cardinal): Integer;
begin
  case C of
    $FFFC: Result := 2;
    9, 11, 32, $A0, 33..47, 58..64, 91..94, 96, 123..126, $FFFFFFFE, $FFFFFFFF: Result := 0;
  else
    Result := 1;
  end;
end;

function TyRichObjectChar: UTF8String;
begin
  Result := '';
  SetLength(Result, 3);
  Result[1] := Chr($EF);
  Result[2] := Chr($BF);
  Result[3] := Chr($BC);
end;

function TyRichPlatformLineBreak: TTyRichSeparator;
var
  s: string;
begin
  // through a variable: comparing the constant itself leaves unreachable branches
  s := sLineBreak;
  if s = #13#10 then Result := rsCRLF
  else if s = #13 then Result := rsCR
  else Result := rsLF;
end;

function TyRichMajorityLineBreak(ACR, ALF, ACRLF: Int64): TTyRichSeparator;
var
  top: Int64;
  n: Integer;
begin
  top := ACR;
  if ALF > top then top := ALF;
  if ACRLF > top then top := ACRLF;
  n := 0;
  if ACR = top then Inc(n);
  if ALF = top then Inc(n);
  if ACRLF = top then Inc(n);
  if (top = 0) or (n > 1) then Result := TyRichPlatformLineBreak
  else if ACRLF = top then Result := rsCRLF
  else if ALF = top then Result := rsLF
  else Result := rsCR;
end;

{ AText with every CR, LF and CRLF in it made ABreak; AText itself when it holds none. A CR
  or LF byte is always a break in UTF-8 (no multi-byte sequence contains one). }
function WithBreaks(const AText: UTF8String; ABreak: TTyRichSeparator): UTF8String;
var
  i, n, k: Integer;
  found: Boolean;
begin
  found := False;
  for i := 1 to Length(AText) do
    if (AText[i] = #13) or (AText[i] = #10) then
    begin
      found := True;
      Break;
    end;
  if not found then Exit(AText);
  Result := '';
  SetLength(Result, Length(AText) * 2);
  n := Length(AText);
  i := 1;
  k := 0;
  while i <= n do
  begin
    if (AText[i] = #13) or (AText[i] = #10) then
    begin
      if (AText[i] = #13) and (i < n) and (AText[i + 1] = #10) then Inc(i);
      if ABreak <> rsLF then
      begin
        Inc(k);
        Result[k] := #13;
      end;
      if ABreak <> rsCR then
      begin
        Inc(k);
        Result[k] := #10;
      end;
    end
    else
    begin
      Inc(k);
      Result[k] := AText[i];
    end;
    Inc(i);
  end;
  SetLength(Result, k);
end;

{ ---- TTyOpaqueAttrs ---- }

function TTyOpaqueAttrs.Count: Integer;
begin
  Result := Length(FItems);
end;

function TTyOpaqueAttrs.Item(AIndex: Integer): RawByteString;
begin
  Result := FItems[AIndex];
end;

procedure TTyOpaqueAttrs.Add(const AFragment: RawByteString);
var
  a: array of RawByteString;
  n: Integer;
begin
  // a fresh array: a copied record shares FItems, and the pool's copy must not change
  n := Length(FItems);
  a := Copy(FItems, 0, n);
  SetLength(a, n + 1);
  a[n] := AFragment;
  FItems := a;
end;

procedure TTyOpaqueAttrs.Clear;
begin
  FItems := nil;
end;

function TTyOpaqueAttrs.Equals(const B: TTyOpaqueAttrs): Boolean;
var
  i: Integer;
begin
  if Length(FItems) <> Length(B.FItems) then Exit(False);
  for i := 0 to High(FItems) do
    if not SameBytes(FItems[i], B.FItems[i]) then Exit(False);
  Result := True;
end;

function TTyOpaqueAttrs.Hash: Cardinal;
var
  i: Integer;
begin
  Result := HashMix(HashBasis, Length(FItems));
  for i := 0 to High(FItems) do
    Result := HashStr(Result, FItems[i]);
end;

{ ---- formats ---- }

function TTyCharFormat.Equals(const B: TTyCharFormat): Boolean;
begin
  Result := SameBytes(FontName, B.FontName) and (Charset = B.Charset) and
    (SizeHalfPt = B.SizeHalfPt) and (Style = B.Style) and (Strike = B.Strike) and
    (VertAlign = B.VertAlign) and (Color = B.Color) and
    (HighlightColor = B.HighlightColor) and Extra.Equals(B.Extra);
end;

function TTyCharFormat.Hash: Cardinal;
var
  st: Byte;
begin
  st := 0;
  if fsBold in Style then st := st or 1;
  if fsItalic in Style then st := st or 2;
  if fsUnderline in Style then st := st or 4;
  if fsStrikeOut in Style then st := st or 8;
  Result := HashStr(HashBasis, FontName);
  Result := HashMix(Result, Cardinal(Charset));
  Result := HashMix(Result, Cardinal(SizeHalfPt));
  Result := HashMix(Result, st or (Ord(Strike) shl 4) or (Ord(VertAlign) shl 5));
  Result := HashMix(Result, Cardinal(Color));
  Result := HashMix(Result, Cardinal(HighlightColor));
  Result := HashMix(Result, Extra.Hash);
end;

function TTyParaFormat.Equals(const B: TTyParaFormat): Boolean;
var
  i: Integer;
begin
  Result := (Align = B.Align) and (LeftIndent = B.LeftIndent) and
    (RightIndent = B.RightIndent) and (FirstIndent = B.FirstIndent) and
    (SpaceBefore = B.SpaceBefore) and (SpaceAfter = B.SpaceAfter) and
    (LineSpacing = B.LineSpacing) and (LineSpacingValue = B.LineSpacingValue) and
    (Length(Tabs) = Length(B.Tabs)) and (List.Kind = B.List.Kind) and
    (List.Level = B.List.Level) and (List.StartAt = B.List.StartAt) and
    (RtlPar = B.RtlPar) and Extra.Equals(B.Extra);
  if not Result then Exit;
  for i := 0 to High(Tabs) do
    if (Tabs[i].Position <> B.Tabs[i].Position) or (Tabs[i].Align <> B.Tabs[i].Align) or
       (Tabs[i].Leader <> B.Tabs[i].Leader) then
      Exit(False);
end;

function TTyParaFormat.Hash: Cardinal;
var
  i: Integer;
begin
  Result := HashMix(HashBasis, Ord(Align) or (Ord(LineSpacing) shl 4) or (Ord(RtlPar) shl 8));
  Result := HashMix(Result, Cardinal(LeftIndent));
  Result := HashMix(Result, Cardinal(RightIndent));
  Result := HashMix(Result, Cardinal(FirstIndent));
  Result := HashMix(Result, Cardinal(SpaceBefore));
  Result := HashMix(Result, Cardinal(SpaceAfter));
  Result := HashMix(Result, Cardinal(LineSpacingValue));
  Result := HashMix(Result, Ord(List.Kind) or (Cardinal(List.Level) shl 4));
  Result := HashMix(Result, Cardinal(List.StartAt));
  Result := HashMix(Result, Length(Tabs));
  for i := 0 to High(Tabs) do
    Result := HashMix(Result, Cardinal(Tabs[i].Position) xor
      (Cardinal(Ord(Tabs[i].Align)) shl 24) xor (Cardinal(Ord(Tabs[i].Leader)) shl 28));
  Result := HashMix(Result, Extra.Hash);
end;

{$POP}

function TyDefaultCharFormat: TTyCharFormat;
begin
  Result := Default(TTyCharFormat);
  Result.FontName := '';
  Result.Charset := DEFAULT_CHARSET;
  Result.SizeHalfPt := 0;
  Result.Style := [];
  Result.Strike := False;
  Result.VertAlign := vaNone;
  Result.Color := clDefault;
  Result.HighlightColor := clNone;
end;

function TyDefaultParaFormat: TTyParaFormat;
begin
  Result := Default(TTyParaFormat);
  Result.Align := paraLeft;
  Result.LineSpacing := lsSingle;
  Result.List.Kind := lkNone;
end;

function TakeStyle(AStyles: TFontStyles; AStyle: TFontStyle; AFrom: TFontStyles): TFontStyles;
begin
  Result := AStyles;
  if AStyle in AFrom then Include(Result, AStyle) else Exclude(Result, AStyle);
end;

function TyMergeCharFormat(const ABase: TTyCharFormat; AMask: TTyCharFormatMask;
  const AValue: TTyCharFormat): TTyCharFormat;
begin
  Result := ABase;
  if cffFontName in AMask then Result.FontName := AValue.FontName;
  if cffCharset in AMask then Result.Charset := AValue.Charset;
  if cffSize in AMask then Result.SizeHalfPt := AValue.SizeHalfPt;
  if cffBold in AMask then Result.Style := TakeStyle(Result.Style, fsBold, AValue.Style);
  if cffItalic in AMask then Result.Style := TakeStyle(Result.Style, fsItalic, AValue.Style);
  if cffUnderline in AMask then
    Result.Style := TakeStyle(Result.Style, fsUnderline, AValue.Style);
  if cffStrike in AMask then Result.Strike := AValue.Strike or (fsStrikeOut in AValue.Style);
  if cffVertAlign in AMask then Result.VertAlign := AValue.VertAlign;
  if cffColor in AMask then Result.Color := AValue.Color;
  if cffHighlight in AMask then Result.HighlightColor := AValue.HighlightColor;
  if cffExtra in AMask then Result.Extra := AValue.Extra;
end;

function TyMergeParaFormat(const ABase: TTyParaFormat; AMask: TTyParaFormatMask;
  const AValue: TTyParaFormat): TTyParaFormat;
var
  first: Integer;
  wasList, isList: Boolean;
begin
  Result := ABase;
  if pffAlign in AMask then Result.Align := AValue.Align;
  if pffLeftIndent in AMask then Result.LeftIndent := AValue.LeftIndent;
  if pffRightIndent in AMask then Result.RightIndent := AValue.RightIndent;
  if pffFirstIndent in AMask then Result.FirstIndent := AValue.FirstIndent;
  if pffSpaceBefore in AMask then Result.SpaceBefore := AValue.SpaceBefore;
  if pffSpaceAfter in AMask then Result.SpaceAfter := AValue.SpaceAfter;
  if pffLineSpacing in AMask then
  begin
    Result.LineSpacing := AValue.LineSpacing;
    Result.LineSpacingValue := AValue.LineSpacingValue;
  end;
  if pffTabs in AMask then Result.Tabs := Copy(AValue.Tabs);
  if pffList in AMask then Result.List := AValue.List;
  // one part of the list record and of the spacing, each paragraph keeping the rest
  if pffListKind in AMask then
    if AValue.List.Kind = lkNone then
      Result.List := TyDefaultParaFormat.List
    else
    begin
      Result.List.Kind := AValue.List.Kind;
      if Result.List.StartAt <= 0 then Result.List.StartAt := 1;
    end;
  if pffListStart in AMask then Result.List.StartAt := AValue.List.StartAt;
  if pffSpacingRule in AMask then
  begin
    Result.LineSpacing := AValue.LineSpacing;
    if not (AValue.LineSpacing in [lsExact, lsAtLeast]) then
      Result.LineSpacingValue := 0
    else if Result.LineSpacingValue <= 0 then
      Result.LineSpacingValue := AValue.LineSpacingValue;
  end;
  if pffSpacingHeight in AMask then
  begin
    if not (Result.LineSpacing in [lsExact, lsAtLeast]) then Result.LineSpacing := lsAtLeast;
    Result.LineSpacingValue := AValue.LineSpacingValue;
  end;
  if pffRtlPar in AMask then Result.RtlPar := AValue.RtlPar;
  if pffExtra in AMask then Result.Extra := AValue.Extra;
  // the relative indent fields (see TTyParaFormatField), each from this paragraph's values
  if pffStartIndent in AMask then
    Result.LeftIndent := AValue.LeftIndent + AValue.FirstIndent - Result.FirstIndent;
  if pffOffset in AMask then
  begin
    first := Result.LeftIndent + Result.FirstIndent;
    Result.FirstIndent := AValue.FirstIndent;
    Result.LeftIndent := first - AValue.FirstIndent;
  end;
  if pffFirstLine in AMask then
    Result.FirstIndent := AValue.LeftIndent + AValue.FirstIndent - Result.LeftIndent;
  if pffHeadIndent in AMask then
  begin
    first := Result.LeftIndent + Result.FirstIndent;
    Result.LeftIndent := AValue.LeftIndent;
    Result.FirstIndent := first - AValue.LeftIndent;
  end;
  if pffListIndents in AMask then
  begin
    wasList := ABase.List.Kind <> lkNone;
    isList := Result.List.Kind <> lkNone;
    if isList and not wasList and (Result.LeftIndent = 0) and (Result.FirstIndent = 0) then
    begin
      Result.LeftIndent := AValue.LeftIndent;
      Result.FirstIndent := AValue.FirstIndent;
    end
    else if wasList and not isList then
    begin
      Result.LeftIndent := 0;
      Result.FirstIndent := 0;
    end;
  end;
end;

{ ---- TTyFormatPool ---- }

procedure TTyFormatPool.RehashChars;
var
  i, n: Integer;
  b: Cardinal;
begin
  n := Length(FCharBucket) * 2;
  if n < 16 then n := 16;
  SetLength(FCharBucket, n);
  for i := 0 to n - 1 do FCharBucket[i] := -1;
  for i := 0 to FCharCount - 1 do
  begin
    b := FCharHash[i] and Cardinal(n - 1);
    FCharNext[i] := FCharBucket[b];
    FCharBucket[b] := i;
  end;
end;

procedure TTyFormatPool.RehashParas;
var
  i, n: Integer;
  b: Cardinal;
begin
  n := Length(FParaBucket) * 2;
  if n < 16 then n := 16;
  SetLength(FParaBucket, n);
  for i := 0 to n - 1 do FParaBucket[i] := -1;
  for i := 0 to FParaCount - 1 do
  begin
    b := FParaHash[i] and Cardinal(n - 1);
    FParaNext[i] := FParaBucket[b];
    FParaBucket[b] := i;
  end;
end;

function TTyFormatPool.InternChar(const F: TTyCharFormat): TTyCharFormatId;
var
  g: TTyCharFormat;
  h, b: Cardinal;
  i: Integer;
begin
  g := F;
  if fsStrikeOut in g.Style then
  begin
    Exclude(g.Style, fsStrikeOut);
    g.Strike := True;
  end;
  h := g.Hash;
  if Length(FCharBucket) > 0 then
  begin
    i := FCharBucket[h and Cardinal(Length(FCharBucket) - 1)];
    while i >= 0 do
    begin
      if (FCharHash[i] = h) and FChars[i].Equals(g) then Exit(i);
      i := FCharNext[i];
    end;
  end;
  if FCharCount = Length(FChars) then
  begin
    SetLength(FChars, FCharCount * 2 + 8);
    SetLength(FCharHash, Length(FChars));
    SetLength(FCharNext, Length(FChars));
  end;
  Result := FCharCount;
  g.Extra.FItems := Copy(g.Extra.FItems);
  FChars[Result] := g;
  FCharHash[Result] := h;
  Inc(FCharCount);
  if FCharCount > Length(FCharBucket) then
    RehashChars
  else
  begin
    b := h and Cardinal(Length(FCharBucket) - 1);
    FCharNext[Result] := FCharBucket[b];
    FCharBucket[b] := Result;
  end;
end;

function TTyFormatPool.InternPara(const F: TTyParaFormat): TTyParaFormatId;
var
  g: TTyParaFormat;
  h, b: Cardinal;
  i: Integer;
begin
  g := F;
  h := g.Hash;
  if Length(FParaBucket) > 0 then
  begin
    i := FParaBucket[h and Cardinal(Length(FParaBucket) - 1)];
    while i >= 0 do
    begin
      if (FParaHash[i] = h) and FParas[i].Equals(g) then Exit(i);
      i := FParaNext[i];
    end;
  end;
  if FParaCount = Length(FParas) then
  begin
    SetLength(FParas, FParaCount * 2 + 8);
    SetLength(FParaHash, Length(FParas));
    SetLength(FParaNext, Length(FParas));
  end;
  Result := FParaCount;
  // the caller's arrays are shared with this copy; the pool keeps its own
  g.Tabs := Copy(g.Tabs);
  g.Extra.FItems := Copy(g.Extra.FItems);
  FParas[Result] := g;
  FParaHash[Result] := h;
  Inc(FParaCount);
  if FParaCount > Length(FParaBucket) then
    RehashParas
  else
  begin
    b := h and Cardinal(Length(FParaBucket) - 1);
    FParaNext[Result] := FParaBucket[b];
    FParaBucket[b] := Result;
  end;
end;

function TTyFormatPool.CharFormat(AId: TTyCharFormatId): TTyCharFormat;
begin
  if (AId < 0) or (AId >= FCharCount) then
    raise ETyRichModel.CreateFmt('Character format id %d out of range', [AId]);
  // Extra's array is private and Add replaces it, so sharing it is safe
  Result := FChars[AId];
end;

function TTyFormatPool.ParaFormat(AId: TTyParaFormatId): TTyParaFormat;
begin
  if (AId < 0) or (AId >= FParaCount) then
    raise ETyRichModel.CreateFmt('Paragraph format id %d out of range', [AId]);
  Result := FParas[AId];
  // Tabs is a public array: writing an element of a shared one would change the pool's
  Result.Tabs := Copy(Result.Tabs);
end;

{ ---- TTyRichRefCounted ---- }

procedure TTyRichRefCounted.AddRef;
begin
  Inc(FRefCount);
end;

procedure TTyRichRefCounted.Release;
begin
  if FRefCount <= 0 then
    raise ETyRichModel.CreateFmt('%s released more often than referenced', [ClassName]);
  Dec(FRefCount);
  if FRefCount = 0 then Free;
end;

{ ---- objects ---- }

constructor TTyRichObject.Create;
begin
  inherited Create;
  FRawUc := 1;
end;

constructor TTyRichPicture.Create(AFormat: TTyRichPictureFormat; const AData: TBytes;
  AWidthTwips, AHeightTwips: Integer; const ARawRtf: RawByteString; ARawUc: Integer);
begin
  inherited Create;
  FFormat := AFormat;
  FData := AData;
  FWidthTwips := AWidthTwips;
  FHeightTwips := AHeightTwips;
  FRawRtf := ARawRtf;
  if ARawUc >= 0 then FRawUc := ARawUc;
end;

function TTyRichObject.DataBytes: Int64;
begin
  Result := InstanceSize;
end;

function TTyRichPicture.DataBytes: Int64;
begin
  Result := InstanceSize + Length(FData) + Length(FRawRtf);
end;

function TTyRichOpaque.DataBytes: Int64;
begin
  Result := InstanceSize + Length(FBytes) + Length(FDisplayText);
end;

function TTyRichPicture.Clone: TTyRichObject;
begin
  Result := TTyRichPicture.Create(FFormat, FData, FWidthTwips, FHeightTwips, FRawRtf, FRawUc);
end;

function TTyRichPicture.DisplayData(out AFormat: TTyRichPictureFormat;
  out AStart, ACount: Integer): Boolean;
var
  bm: TTyWmfBitmap;
begin
  // the picture never changes, so the metafile's records are walked once
  if FShown = 0 then
  begin
    FShown := 2;
    FShowFormat := rpfUnknown;
    FShowStart := 0;
    FShowCount := 0;
    if Length(FData) > 0 then
      case FFormat of
        rpfPng, rpfJpeg, rpfBmp, rpfDib:
          begin
            FShown := 1;
            FShowFormat := FFormat;
            FShowCount := Length(FData);
          end;
        rpfWmf:
          if TyWmfSingleBitmap(FData, bm) then
          begin
            FShown := 1;
            FShowFormat := rpfDib;
            FShowStart := bm.DibStart;
            FShowCount := bm.DibCount;
          end;
      else
        ;  // EMF and other metafiles are drawn by nothing in phase 1
      end;
  end;
  Result := FShown = 1;
  AFormat := FShowFormat;
  AStart := FShowStart;
  ACount := FShowCount;
end;

constructor TTyRichOpaque.Create(const ABytes: RawByteString; const ADisplayText: UTF8String;
  ARawUc: Integer);
begin
  inherited Create;
  FBytes := ABytes;
  FDisplayText := ADisplayText;
  if ARawUc >= 0 then FRawUc := ARawUc;
end;

function TTyRichOpaque.Clone: TTyRichObject;
begin
  Result := TTyRichOpaque.Create(FBytes, FDisplayText, FRawUc);
end;

{ ---- tables ---- }

function TTyRichCell.Table: TTyRichTable;
begin
  Result := FRow.FTable;
end;

destructor TTyRichRow.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FCells) do FCells[i].Free;
  inherited Destroy;
end;

function TTyRichRow.GetCell(AIndex: Integer): TTyRichCell;
begin
  if (AIndex < 0) or (AIndex > High(FCells)) then
    raise ETyRichModel.CreateFmt('Cell index %d out of range', [AIndex]);
  Result := FCells[AIndex];
end;

function TTyRichRow.GetBoundary(AIndex: Integer): Integer;
begin
  if (AIndex < 0) or (AIndex > High(FBoundaries)) then
    raise ETyRichModel.CreateFmt('Boundary index %d out of range', [AIndex]);
  Result := FBoundaries[AIndex];
end;

function TTyRichRow.CellCount: Integer;
begin
  Result := Length(FCells);
end;

function TTyRichRow.BoundaryCount: Integer;
begin
  Result := Length(FBoundaries);
end;

constructor TTyRichTable.Create(const AColBoundaries: array of Integer;
  AStructureLocked: Boolean);
var
  i: Integer;
begin
  inherited Create;
  SetLength(FColBoundaries, Length(AColBoundaries));
  for i := 0 to High(AColBoundaries) do FColBoundaries[i] := AColBoundaries[i];
  FStructureLocked := AStructureLocked;
end;

destructor TTyRichTable.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FRows) do FRows[i].Free;
  inherited Destroy;
end;

function TTyRichTable.AddRow(ACellCount: Integer; const ARawFormat: RawByteString): TTyRichRow;
begin
  Result := AddRow(ACellCount, ARawFormat, []);
end;

function TTyRichTable.AddRow(ACellCount: Integer; const ARawFormat: RawByteString;
  const ABoundaries: array of Integer; AHoldsNestedTable: Boolean): TTyRichRow;
var
  i: Integer;
  c: TTyRichCell;
begin
  if FFrozen then
    raise ETyRichModel.Create('A table in use cannot change its rows');
  if ACellCount < 1 then
    raise ETyRichModel.Create('A row needs at least one cell');
  Result := TTyRichRow.Create;
  Result.FTable := Self;
  Result.FIndex := Length(FRows);
  Result.FRawFormat := ARawFormat;
  Result.FHoldsNestedTable := AHoldsNestedTable;
  SetLength(Result.FBoundaries, Length(ABoundaries));
  for i := 0 to High(ABoundaries) do Result.FBoundaries[i] := ABoundaries[i];
  SetLength(Result.FCells, ACellCount);
  for i := 0 to ACellCount - 1 do
  begin
    c := TTyRichCell.Create;
    c.FRow := Result;
    c.FIndex := i;
    Result.FCells[i] := c;
  end;
  SetLength(FRows, Length(FRows) + 1);
  FRows[High(FRows)] := Result;
end;

function TTyRichTable.GetRow(AIndex: Integer): TTyRichRow;
begin
  if (AIndex < 0) or (AIndex > High(FRows)) then
    raise ETyRichModel.CreateFmt('Row index %d out of range', [AIndex]);
  Result := FRows[AIndex];
end;

function TTyRichTable.GetColBoundary(AIndex: Integer): Integer;
begin
  if (AIndex < 0) or (AIndex > High(FColBoundaries)) then
    raise ETyRichModel.CreateFmt('Column boundary index %d out of range', [AIndex]);
  Result := FColBoundaries[AIndex];
end;

function TTyRichTable.RowCount: Integer;
begin
  Result := Length(FRows);
end;

function TTyRichTable.CellCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to High(FRows) do Inc(Result, Length(FRows[i].FCells));
end;

function TTyRichTable.ColBoundaryCount: Integer;
begin
  Result := Length(FColBoundaries);
end;

{ ---- TTyRichUndoData ---- }

destructor TTyRichUndoData.Destroy;
var
  i: Integer;
begin
  for i := 0 to FOldCount - 1 do FDoc.ReleaseData(FOldData[i].Data);
  for i := 0 to High(FRemoved.Pieces) do
    if (FRemoved.Pieces[i].Separator <> rsNone) and (FRemoved.Pieces[i].Data <> nil) then
      FDoc.ReleaseData(TTyRichParaData(FRemoved.Pieces[i].Data));
  for i := 0 to FSwapCount - 1 do FDoc.ReleaseData(FSwaps[i].Old);
  for i := 0 to FSwapPieceCount - 1 do
    if (FSwapPieces[i].Separator <> rsNone) and (FSwapPieces[i].Data <> nil) then
      FDoc.ReleaseData(TTyRichParaData(FSwapPieces[i].Data));
  inherited Destroy;
end;

function TTyRichUndoData.MemSize: Int64;
begin
  Result := InstanceSize + (Length(FRemoved.Pieces) + Length(FSpan.Pieces.Pieces) +
    Length(FSpan2.Pieces.Pieces) + Length(FSwapPieces)) * SizeOf(TTyRichPiece) +
    Length(FOldData) * SizeOf(TTyRichOldData) + Length(FSwaps) * SizeOf(TTyRichParaSwap);
end;

procedure AddObject(var AList: TTyRichObjectList; var ACount: Integer; AObj: TTyRichObject);
begin
  if ACount = Length(AList) then SetLength(AList, ACount * 2 + 4);
  AList[ACount] := AObj;
  Inc(ACount);
end;

procedure SortObjects(var AList: TTyRichObjectList; ALo, AHi: Integer);
var
  i, j: Integer;
  p, t: TTyRichObject;
begin
  while ALo < AHi do
  begin
    i := ALo;
    j := AHi;
    p := AList[(ALo + AHi) div 2];
    repeat
      while PtrUInt(AList[i]) < PtrUInt(p) do Inc(i);
      while PtrUInt(AList[j]) > PtrUInt(p) do Dec(j);
      if i <= j then
      begin
        t := AList[i];
        AList[i] := AList[j];
        AList[j] := t;
        Inc(i);
        Dec(j);
      end;
    until i > j;
    if j - ALo < AHi - i then
    begin
      if ALo < j then SortObjects(AList, ALo, j);
      ALo := i;
    end
    else
    begin
      if i < AHi then SortObjects(AList, i, AHi);
      AHi := j;
    end;
  end;
end;

procedure TTyRichUndoData.GatherObjects(var AList: TTyRichObjectList; var ACount: Integer);
var
  i: Integer;

  // the objects of a value this record holds
  procedure Take(D: TTyRichParaData);
  var
    j: Integer;
  begin
    if D = nil then Exit;
    { In the history's gathering: a value of no objects, or of objects already gathered or
      held by the step (its key met), adds nothing - no walk of its runs. }
    if FDoc.FGathering and ((D.FObjKey = 0) or not FDoc.MeetKey(D.FObjKey)) then Exit;
    for j := 0 to High(D.FRuns) do
      if D.FRuns[j].Obj <> nil then
      begin
        Inc(FDoc.FHistoryObjectVisits);
        AddObject(AList, ACount, D.FRuns[j].Obj);
      end;
  end;

begin
  { Every object a value this record keeps holds - also while the document or a reader's
    resident values hold it too: the history counts it once however many steps hold it,
    which over-counts one the document still shows (the safe side, bounded by the
    document's own pictures). One pass over the values, no lookup per object. }
  for i := 0 to FOldCount - 1 do Take(FOldData[i].Data);
  for i := 0 to High(FRemoved.Pieces) do
    if FRemoved.Pieces[i].Separator <> rsNone then Take(TTyRichParaData(FRemoved.Pieces[i].Data));
  for i := 0 to FSwapCount - 1 do Take(FSwaps[i].Old);
  for i := 0 to FSwapPieceCount - 1 do
    if FSwapPieces[i].Separator <> rsNone then Take(TTyRichParaData(FSwapPieces[i].Data));
end;

procedure TTyRichUndoData.AddOld(D: TTyRichParaData);
begin
  if (FOldCount > 0) and (FOldData[FOldCount - 1].Data = D) then
  begin
    Inc(FOldData[FOldCount - 1].Count);
    Exit;
  end;
  if FOldCount = Length(FOldData) then SetLength(FOldData, FOldCount * 2 + 1);
  FOldData[FOldCount].Data := D;
  FOldData[FOldCount].Count := 1;
  Inc(FOldCount);
  FDoc.AcquireData(D);
end;

procedure TTyRichUndoData.SealOld;
begin
  SetLength(FOldData, FOldCount);
end;

procedure TTyRichUndoData.AddSwap(APara: Integer; AOld: TTyRichParaData;
  const APieces: TTyRichPieces);
var
  i: Integer;
begin
  if FSwapCount = Length(FSwaps) then SetLength(FSwaps, FSwapCount * 2 + 4);
  FSwaps[FSwapCount].Para := APara;
  FSwaps[FSwapCount].Old := AOld;
  FSwaps[FSwapCount].First := FSwapPieceCount;
  FSwaps[FSwapCount].Count := Length(APieces.Pieces);
  Inc(FSwapCount);
  FDoc.AcquireData(AOld);
  for i := 0 to High(APieces.Pieces) do
  begin
    if FSwapPieceCount = Length(FSwapPieces) then
      SetLength(FSwapPieces, FSwapPieceCount * 2 + 4);
    FSwapPieces[FSwapPieceCount] := APieces.Pieces[i];
    Inc(FSwapPieceCount);
    // (the value after its separator: the one the paragraph after it gets back)
    if (APieces.Pieces[i].Separator <> rsNone) and (APieces.Pieces[i].Data <> nil) then
      FDoc.AcquireData(TTyRichParaData(APieces.Pieces[i].Data));
  end;
end;

procedure TTyRichUndoData.SealSwaps;
begin
  SetLength(FSwaps, FSwapCount);
  SetLength(FSwapPieces, FSwapPieceCount);
end;

{ ---- runs ---- }

procedure AppendRun(var A: TTyRunArray; var N: Integer; AStart: Int64;
  AFormat: TTyCharFormatId; AObj: TTyRichObject);
begin
  if AStart > High(LongInt) then
    raise ETyRichModel.Create('A formatted paragraph is limited to 2^31-1 characters');
  // a run that would be empty gives way; an equal plain neighbour absorbs the new one
  while (N > 0) and (A[N - 1].Start >= AStart) do Dec(N);
  if (N > 0) and (AObj = nil) and (A[N - 1].Obj = nil) and (A[N - 1].Format = AFormat) then
    Exit;
  if N = Length(A) then SetLength(A, N * 2 + 4);
  A[N].Start := AStart;
  A[N].Format := AFormat;
  A[N].Obj := AObj;
  Inc(N);
end;

function RunEnd(const R: TTyRunArray; AIndex: Integer; ALen: Int64): Int64; inline;
begin
  if AIndex < High(R) then Result := R[AIndex + 1].Start else Result := ALen;
end;

{ Appends the parts of R (a paragraph of ALen characters) inside [AFrom, ATo), moved by
  ADelta. }
procedure AppendSlice(var A: TTyRunArray; var N: Integer; const R: TTyRunArray; ALen: Int64;
  AFrom, ATo, ADelta: Int64);
var
  j: Integer;
  s, e: Int64;
begin
  for j := 0 to High(R) do
  begin
    s := R[j].Start;
    if s >= ATo then Break;
    e := RunEnd(R, j, ALen);
    if e <= AFrom then Continue;
    if s < AFrom then s := AFrom;
    if e > ATo then e := ATo;
    if s < e then AppendRun(A, N, s + ADelta, R[j].Format, R[j].Obj);
  end;
end;

function RunIndexAt(const R: TTyRunArray; AOffset: Int64): Integer;
var
  lo, hi, mid: Integer;
begin
  lo := 0;
  hi := High(R);
  while lo < hi do
  begin
    mid := (lo + hi + 1) div 2;
    if R[mid].Start <= AOffset then lo := mid else hi := mid - 1;
  end;
  Result := lo;
end;

function InheritedFormat(const R: TTyRunArray; AOffset: Int64): TTyCharFormatId;
begin
  if AOffset > 0 then
    Result := R[RunIndexAt(R, AOffset - 1)].Format
  else
    Result := R[0].Format;
end;

function SameRuns(const A, B: TTyRunArray): Boolean;
var
  i: Integer;
begin
  if Pointer(A) = Pointer(B) then Exit(True);
  if Length(A) <> Length(B) then Exit(False);
  for i := 0 to High(A) do
    if (A[i].Start <> B[i].Start) or (A[i].Format <> B[i].Format) or (A[i].Obj <> B[i].Obj) then
      Exit(False);
  Result := True;
end;

{ ---- TTyRichDocBuilder ---- }

{ Checks a reader's runs for paragraph AIndex (raises when malformed); its length. }
function CheckReaderRuns(ADoc: TTyRichDocument; AIndex: Integer; AParaFormat: TTyParaFormatId;
  const ARuns: TTyRunArray): Int64;
var
  i: Integer;
begin
  ADoc.CheckParaId(AParaFormat);
  if Length(ARuns) = 0 then
    raise ETyRichModel.Create('A paragraph needs at least one run');
  Result := ADoc.FText.ParaLength(AIndex);
  for i := 0 to High(ARuns) do
  begin
    ADoc.CheckCharId(ARuns[i].Format);
    if ((i = 0) and (ARuns[i].Start <> 0)) or ((i > 0) and (ARuns[i].Start <= ARuns[i - 1].Start)) or
       ((i > 0) and (ARuns[i].Start >= Result)) or
       ((ARuns[i].Obj <> nil) and (RunEnd(ARuns, i, Result) <> ARuns[i].Start + 1)) then
      raise ETyRichModel.CreateFmt('Runs of paragraph %d are malformed', [AIndex]);
  end;
end;

{ A reader's value for a paragraph of ALen characters (checked runs), not held. }
function ReaderValue(ADoc: TTyRichDocument; ALen: Int64; AParaFormat: TTyParaFormatId;
  const ARuns: TTyRunArray; ACell: TTyRichCell; const AListText: UTF8String): TTyRichParaData;
var
  runs: TTyRunArray;
  n: Integer;
begin
  runs := nil;
  n := 0;
  if ALen = 0 then
    AppendRun(runs, n, 0, ARuns[0].Format, ARuns[0].Obj)
  else
    AppendSlice(runs, n, ARuns, ALen, 0, ALen, 0);
  SetLength(runs, n);
  if AListText <> '' then
  begin
    Result := ADoc.NewData(AParaFormat, runs, ACell);
    Result.FListText := AListText;
  end
  else
    Result := ADoc.MakeData(AParaFormat, runs, ACell);
end;

class function TTyRichDocBuilder.MakeValue(ADoc: TTyRichDocument; AIndex: Integer;
  AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray; ACell: TTyRichCell;
  const AListText: UTF8String): Pointer;
var
  d: TTyRichParaData;
begin
  d := ReaderValue(ADoc, CheckReaderRuns(ADoc, AIndex, AParaFormat, ARuns), AParaFormat, ARuns,
    ACell, AListText);
  ADoc.AcquireData(d);
  Result := d;
end;

class function TTyRichDocBuilder.SetParagraph(ADoc: TTyRichDocument; AIndex: Integer;
  AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray; ACell: TTyRichCell;
  const AListText: UTF8String): Boolean;
var
  len: Int64;
begin
  len := CheckReaderRuns(ADoc, AIndex, AParaFormat, ARuns);
  if ADoc.SlotData(AIndex) <> nil then Exit(False);
  ADoc.PutData(AIndex, nil, ReaderValue(ADoc, len, AParaFormat, ARuns, ACell, AListText));
  Result := True;
end;

class procedure TTyRichDocBuilder.SetDefaultCharFormat(ADoc: TTyRichDocument;
  const AFormat: TTyCharFormat);
begin
  ADoc.SetDefaults(AFormat);
end;

class procedure TTyRichDocBuilder.SetPage(ADoc: TTyRichDocument; APaperWidth, APaperHeight,
  AMarginLeft, AMarginRight: Integer);
begin
  ADoc.FPaperWidth := APaperWidth;
  ADoc.FPaperHeight := APaperHeight;
  ADoc.FMarginLeft := AMarginLeft;
  ADoc.FMarginRight := AMarginRight;
end;

class procedure TTyRichDocBuilder.ReplaceText(ADoc: TTyRichDocument; AText: TTyRichText);
begin
  if AText = nil then
    raise ETyRichModel.Create('ReplaceText needs a text');
  ADoc.ResetContent(AText, teUtf8, 0, False, TyRichMajorityLineBreak(
    AText.LoadedSeparators(rsCR), AText.LoadedSeparators(rsLF), AText.LoadedSeparators(rsCRLF)));
end;

class procedure TTyRichDocBuilder.ReplaceText(ADoc: TTyRichDocument; AText: TTyRichText;
  AEncoding: TTyTextEncoding; ACodePage: Integer; AHasBom: Boolean;
  ALineBreak: TTyRichSeparator);
begin
  ADoc.ResetContent(AText, AEncoding, ACodePage, AHasBom, ALineBreak);
end;

class procedure TTyRichDocBuilder.SetLoadState(ADoc: TTyRichDocument; ALoading,
  AIncomplete: Boolean);
begin
  ADoc.FLoadingContent := ALoading;
  ADoc.FIncomplete := AIncomplete;
end;

class procedure TTyRichDocBuilder.ReportLoad(ADoc: TTyRichDocument; const AChange: TTyRichChange);
begin
  if Assigned(ADoc.FOnChange) then ADoc.FOnChange(ADoc, AChange);
end;

class function TTyRichDocBuilder.ParagraphValue(ADoc: TTyRichDocument; AIndex: Integer): Pointer;
begin
  Result := ADoc.SlotData(AIndex);
end;

class procedure TTyRichDocBuilder.HoldValue(ADoc: TTyRichDocument; AValue: Pointer);
begin
  ADoc.AcquireData(TTyRichParaData(AValue));
end;

class procedure TTyRichDocBuilder.ReleaseValue(ADoc: TTyRichDocument; AValue: Pointer);
begin
  ADoc.ReleaseData(TTyRichParaData(AValue));
end;

class function TTyRichDocBuilder.ValueShared(ADoc: TTyRichDocument; AValue: Pointer): Boolean;
begin
  Result := (AValue <> nil) and (AValue <> Pointer(ADoc.FPlainParsed)) and
    (TTyRichParaData(AValue).FRefCount > 1);
end;

class function TTyRichDocBuilder.IsPlainValue(ADoc: TTyRichDocument; AValue: Pointer): Boolean;
begin
  Result := (AValue <> nil) and (AValue = Pointer(ADoc.FPlainParsed));
end;

class function TTyRichDocBuilder.UnsetParagraph(ADoc: TTyRichDocument; AIndex: Integer;
  AValue: Pointer): Boolean;
begin
  // without a loader nil means plain, not unparsed
  Result := (ADoc.FLoader <> nil) and (AValue <> nil) and
    (Pointer(ADoc.SlotData(AIndex)) = AValue);
  if Result then ADoc.PutData(AIndex, TTyRichParaData(AValue), nil);
end;

class function TTyRichDocBuilder.DocumentBusy(ADoc: TTyRichDocument): Boolean;
begin
  Result := (ADoc.FRunning <> nil) or (ADoc.FEditing > 0) or (ADoc.FReading > 0);
end;

{ ---- TTyRichParaLoader ---- }

procedure TTyRichParaLoader.ParagraphRead(ADoc: TTyRichDocument; AIndex: Integer);
begin
end;

procedure TTyRichParaLoader.ReadsEnded(ADoc: TTyRichDocument);
begin
end;

{ ---- TTyRichDocument: life ---- }

constructor TTyRichDocument.Create;
begin
  inherited Create;
  FText := TTyRichText.Create;
  Init;
end;

constructor TTyRichDocument.CreateFromUtf8(const ABuffer: TBytes);
begin
  inherited Create;
  FText := TTyRichText.CreateFromUtf8(ABuffer);
  Init;
end;

constructor TTyRichDocument.CreateOnText(AText: TTyRichText);
begin
  inherited Create;
  if AText = nil then
    raise ETyRichModel.Create('CreateOnText needs a text');
  FText := AText;
  Init;
end;

procedure TTyRichDocument.Init;
begin
  FFormats := TTyFormatPool.Create;
  FDefaultParaId := FFormats.InternPara(TyDefaultParaFormat);
  SetDefaults(TyDefaultCharFormat);
  SetDefaultPage;
  FMaxUndoBytes := DefaultMaxUndoBytes;
  FState := 0;
  FSavedState := 0;
  FNextState := 1;
  FText.OnParasChanged := @TextParasChanged;
  FText.OnParaDataDropped := @TextDataDropped;
  FSourceEncoding := teUtf8;
  FSourceCodePage := 0;
  FSourceHasBom := False;
  // over a buffer: the majority of its breaks; empty or lazy: none counted, the platform's
  FDominantLineBreak := TyRichMajorityLineBreak(FText.LoadedSeparators(rsCR),
    FText.LoadedSeparators(rsLF), FText.LoadedSeparators(rsCRLF));
end;

procedure TTyRichDocument.ResetContent(AText: TTyRichText; AEncoding: TTyTextEncoding;
  ACodePage: Integer; AHasBom: Boolean; ALineBreak: TTyRichSeparator);
var
  c: TTyRichChange;
begin
  if AText = nil then
    raise ETyRichModel.Create('ReplaceText needs a text');
  if AText = FText then
    raise ETyRichModel.Create('ReplaceText needs a new text');
  if (FRunning <> nil) or (FUpdateCount > 0) or FInLoad then
  begin
    AText.Free;
    // the history being built refers to the old content's paragraphs and pieces
    raise ETyRichModel.Create('A document cannot be replaced while a command runs or ' +
      'inside BeginUpdate .. EndUpdate');
  end;
  if (FSaving > 0) or (FReading > 0) then
  begin
    AText.Free;
    // a save walks the text and copies from the loader this would free; a read scope holds
    // tables, cells and objects of the content this would free
    raise ETyRichModel.Create('A document cannot be loaded into while it is being saved ' +
      'or read (inside BeginRead .. EndRead)');
  end;
  c := Default(TTyRichChange);
  c.Kinds := [rckText, rckFormat, rckStructure];
  c.OldLen := FText.Length;
  c.OldParaCount := FText.ParaCount;
  // as in Destroy: the history first, its records hold references to the values
  ClearHistory;
  FMergeBroken := False;
  FHasPending := False;
  FPending := Default(TTyRichChange);
  FText.OnParasChanged := nil;
  FText.OnParaDataDropped := nil;
  FValuesGone := True;
  while FFirstData <> nil do
    DisposeData(FFirstData);
  FValuesGone := False;
  FText.Free;
  FText := AText;
  FText.OnParasChanged := @TextParasChanged;
  FText.OnParaDataDropped := @TextDataDropped;
  // a loader parses the content it was made for
  if FOwnsLoader then FLoader.Free;
  FLoader := nil;
  FOwnsLoader := False;
  // the default font and the page were the old content's (an RTF file's): a text file
  // loaded next has neither, and would show in them
  SetDefaults(TyDefaultCharFormat);
  SetDefaultPage;
  FSourceEncoding := AEncoding;
  FSourceCodePage := ACodePage;
  FSourceHasBom := AHasBom;
  if ALineBreak = rsNone then ALineBreak := TyRichPlatformLineBreak;
  FDominantLineBreak := ALineBreak;
  // the content as loaded is the saved point
  FState := NewState;
  FSavedState := FState;
  FLoadingContent := False;
  FIncomplete := False;
  c.NewLen := FText.Length;
  c.NewParaCount := FText.ParaCount;
  if Assigned(FOnChange) then FOnChange(Self, c);
  NoteModified;
end;

destructor TTyRichDocument.Destroy;
var
  d: TTyRichParaData;
begin
  // the history first: its records hold references to the values disposed below
  ClearHistory;
  FreeAndNil(FObjHolds);
  FreeAndNil(FKeyMet);
  if FText <> nil then
  begin
    FText.OnParasChanged := nil;
    FText.OnParaDataDropped := nil;
  end;
  // nothing may outlive the document (the history goes first), so every value still alive is
  // the text's or the plain sentinel; the text itself never frees data. From here on a
  // release can only come from a record that outlived its document: it raises instead of
  // writing into a freed value
  FValuesGone := True;
  while FFirstData <> nil do
  begin
    d := FFirstData;
    DisposeData(d);
  end;
  FText.Free;
  FFormats.Free;
  if FOwnsLoader then FLoader.Free;
  inherited Destroy;
end;

procedure TTyRichDocument.SetDefaultPage;
begin
  { A new document's page, and one not read from RTF (a reader of RTF sets the file's):
    A4 (Word's default page for a Chinese locale: a control for Chinese users), WordPad's 1.25"
    side margins }
  FPaperWidth := 11906;
  FPaperHeight := 16838;
  FMarginLeft := 1800;
  FMarginRight := 1800;
end;

procedure TTyRichDocument.SetDefaults(const AFormat: TTyCharFormat);
begin
  FDefaultCharId := FFormats.InternChar(AFormat);
  FDefaultCharFormat := FFormats.CharFormat(FDefaultCharId);
  // a new array: values made earlier may share the old one
  FDefaultRuns := nil;
  SetLength(FDefaultRuns, 1);
  FDefaultRuns[0].Start := 0;
  FDefaultRuns[0].Format := FDefaultCharId;
  FDefaultRuns[0].Obj := nil;
end;

procedure TTyRichDocument.InstallLoader(ALoader: TTyRichParaLoader; AOwnsLoader: Boolean);
var
  d: TTyRichParaData;
begin
  if FOwnsLoader and (FLoader <> ALoader) then FLoader.Free;
  FLoader := ALoader;
  FOwnsLoader := AOwnsLoader;
  if (FLoader <> nil) and (FPlainParsed = nil) then
  begin
    // with a loader nil means "not parsed", so a parsed plain paragraph needs a value; one
    // shared value, held by the document itself
    d := TTyRichParaData.Create;
    d.FParaFormat := FDefaultParaId;
    d.FNext := FFirstData;
    if FFirstData <> nil then FFirstData.FPrev := d;
    FFirstData := d;
    Inc(FLiveData);
    AcquireData(d);
    FPlainParsed := d;
  end;
end;

{ ---- paragraph values ---- }

function TTyRichDocument.NewData(AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray;
  ACell: TTyRichCell): TTyRichParaData;
var
  i: Integer;
  t: TTyRichTable;
begin
  Result := TTyRichParaData.Create;
  Result.FParaFormat := AParaFormat;
  Result.FRuns := ARuns;
  Result.FCell := ACell;
  for i := 0 to High(ARuns) do
    if ARuns[i].Obj <> nil then
    begin
      ARuns[i].Obj.AddRef;
      // objects: a key of its own (MakeDataLike may give it its source's)
      if Result.FObjKey = 0 then
      begin
        Inc(FNextObjKey);
        Result.FObjKey := FNextObjKey;
      end;
    end;
  if ACell <> nil then
  begin
    t := ACell.Table;
    t.AddRef;
    Inc(t.FParaRefs);
    t.FFrozen := True;
  end;
  Result.FNext := FFirstData;
  if FFirstData <> nil then FFirstData.FPrev := Result;
  FFirstData := Result;
  Inc(FLiveData);
end;

procedure TTyRichDocument.DisposeData(D: TTyRichParaData);
var
  i: Integer;
  t: TTyRichTable;
begin
  if D.FPrev <> nil then D.FPrev.FNext := D.FNext else FFirstData := D.FNext;
  if D.FNext <> nil then D.FNext.FPrev := D.FPrev;
  Dec(FLiveData);
  if D = FPlainParsed then FPlainParsed := nil;
  for i := 0 to High(D.FRuns) do
    if D.FRuns[i].Obj <> nil then D.FRuns[i].Obj.Release;
  if D.FCell <> nil then
  begin
    t := D.FCell.Table;
    Dec(t.FParaRefs);
    t.Release;
  end;
  // poison: a value used after it is gone shows up as garbage formats, not as the old ones
  D.FParaFormat := -1;
  D.FCell := nil;
  D.FRuns := nil;
  D.FListText := '';
  D.FRefCount := -1;
  D.Free;
end;

procedure TTyRichDocument.AcquireData(D: TTyRichParaData);
begin
  if D <> nil then Inc(D.FRefCount);
end;

procedure TTyRichDocument.ReleaseData(D: TTyRichParaData);
begin
  if D = nil then Exit;
  if FValuesGone then
    raise ETyRichModel.Create('An undo record outlived the values of its document');
  if D.FRefCount <= 0 then
    raise ETyRichModel.Create('Paragraph data released more often than referenced');
  Dec(D.FRefCount);
  if D.FRefCount = 0 then DisposeData(D);
end;

function TTyRichDocument.PlainValue: TTyRichParaData;
begin
  if FLoader <> nil then Result := FPlainParsed else Result := nil;
end;

function TTyRichDocument.MakeData(AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray;
  ACell: TTyRichCell): TTyRichParaData;
begin
  if (AParaFormat = FDefaultParaId) and (ACell = nil) and (Length(ARuns) = 1) and
     (ARuns[0].Format = FDefaultCharId) and (ARuns[0].Obj = nil) then
    Result := PlainValue
  else
    Result := NewData(AParaFormat, ARuns, ACell);
end;

{ A new value for the paragraph AFrom was the value of (the same paragraph after an edit in
  it: typing, a format, the first part of a split): it keeps the file's marker text. }
function TTyRichDocument.MakeDataLike(AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray;
  ACell: TTyRichCell; AFrom: TTyRichParaData): TTyRichParaData;
var
  i, j: Integer;
  same: Boolean;
begin
  if (AFrom <> nil) and (AFrom.FListText <> '') then
  begin
    Result := NewData(AParaFormat, ARuns, ACell);
    Result.FListText := AFrom.FListText;
  end
  else
    Result := MakeData(AParaFormat, ARuns, ACell);
  { The very same objects in the same order as the value it was made from (typing, a format
    change): the same key - one pass, beside NewData's own over the runs. }
  // (nil: the plain value of a document without a loader - no objects)
  if (AFrom = nil) or (Result = nil) or (Result.FObjKey = 0) or (AFrom.FObjKey = 0) then Exit;
  j := 0;
  same := True;
  for i := 0 to High(Result.FRuns) do
    if Result.FRuns[i].Obj <> nil then
    begin
      while (j <= High(AFrom.FRuns)) and (AFrom.FRuns[j].Obj = nil) do Inc(j);
      if (j > High(AFrom.FRuns)) or (AFrom.FRuns[j].Obj <> Result.FRuns[i].Obj) then
      begin
        same := False;
        Break;
      end;
      Inc(j);
    end;
  if same then
  begin
    while (j <= High(AFrom.FRuns)) and (AFrom.FRuns[j].Obj = nil) do Inc(j);
    if j > High(AFrom.FRuns) then Result.FObjKey := AFrom.FObjKey;
  end;
end;

procedure TTyRichDocument.PutData(AIndex: Integer; AOld, ANew: TTyRichParaData);
begin
  if AOld = ANew then Exit;
  AcquireData(ANew);
  FText.ParaData[AIndex] := ANew;
  ReleaseData(AOld);
end;

function TTyRichDocument.SlotData(AIndex: Integer): TTyRichParaData;
begin
  Result := TTyRichParaData(FText.ParaData[AIndex]);
end;

function TTyRichDocument.DataOf(AIndex: Integer): TTyRichParaData;
begin
  Result := SlotData(AIndex);
  if (FLoader = nil) or FInLoad then Exit;
  if Result <> nil then
  begin
    // parsed already: the loader hears that it is in use
    FLoader.ParagraphRead(Self, AIndex);
    Exit;
  end;
  FInLoad := True;
  try
    FLoader.LoadParagraph(Self, AIndex);
  finally
    FInLoad := False;
  end;
  Result := SlotData(AIndex);
  if Result = nil then
  begin
    Result := FPlainParsed;
    PutData(AIndex, nil, Result);
  end;
end;

function TTyRichDocument.RunsOfData(D: TTyRichParaData): TTyRunArray;
begin
  if (D = nil) or (D.FRuns = nil) then Result := FDefaultRuns else Result := D.FRuns;
end;

function TTyRichDocument.FormatOfData(D: TTyRichParaData): TTyParaFormatId;
begin
  if D = nil then Result := FDefaultParaId else Result := D.FParaFormat;
end;

function TTyRichDocument.CellOfData(D: TTyRichParaData): TTyRichCell;
begin
  if D = nil then Result := nil else Result := D.FCell;
end;

procedure TTyRichDocument.TextDataDropped(Sender: TObject; AData: Pointer);
begin
  // the slot's reference goes; an undo record that still needs the value holds its own
  ReleaseData(TTyRichParaData(AData));
end;

procedure TTyRichDocument.TextParasChanged(Sender: TObject; AFirst, AOldCount,
  ANewCount: Integer);
begin
  if FEditing > 0 then Exit;
  // an edit made straight on Text: no undo, no notification; keep the runs inside the text
  LeftHistory;
  ClipRuns(AFirst);
end;

procedure TTyRichDocument.ClipRuns(AIndex: Integer);
var
  d: TTyRichParaData;
  len: Int64;
  runs: TTyRunArray;
  n: Integer;
begin
  d := SlotData(AIndex);
  if (d = nil) or (d.FRuns = nil) then Exit;
  len := FText.ParaLength(AIndex);
  runs := nil;
  n := 0;
  if len = 0 then
    AppendRun(runs, n, 0, d.FRuns[0].Format, nil)
  else
  begin
    AppendSlice(runs, n, d.FRuns, len, 0, len, 0);
    // an object whose character went is dropped
    if (n > 0) and (runs[n - 1].Obj <> nil) and (runs[n - 1].Start + 1 > len) then
      runs[n - 1].Obj := nil;
    if n = 0 then AppendRun(runs, n, 0, d.FRuns[0].Format, nil);
  end;
  SetLength(runs, n);
  if SameRuns(runs, d.FRuns) then Exit;
  PutData(AIndex, d, MakeDataLike(d.FParaFormat, runs, d.FCell, d));
end;

{ ---- readers ---- }

procedure TTyRichDocument.EnsureParsed(AIndex: Integer);
begin
  DataOf(AIndex);
end;

procedure TTyRichDocument.BeginRead;
begin
  Inc(FReading);
end;

procedure TTyRichDocument.EndRead;
begin
  if FReading <= 0 then
    raise ETyRichModel.Create('EndRead without BeginRead');
  Dec(FReading);
  if (FReading = 0) and (FLoader <> nil) and not FInLoad then FLoader.ReadsEnded(Self);
end;

procedure TTyRichDocument.BeginSave;
begin
  Inc(FSaving);
end;

procedure TTyRichDocument.EndSave;
begin
  if FSaving <= 0 then
    raise ETyRichModel.Create('EndSave without BeginSave');
  Dec(FSaving);
end;

function TTyRichDocument.GetSaving: Boolean;
begin
  Result := FSaving > 0;
end;

function TTyRichDocument.ParaFormatOf(AIndex: Integer): TTyParaFormatId;
begin
  Result := FormatOfData(DataOf(AIndex));
end;

function TTyRichDocument.RunsOf(AIndex: Integer): TTyRunArray;
begin
  Result := Copy(RunsOfData(DataOf(AIndex)));
end;

function TTyRichDocument.TypingFormatAt(APos: TTyRichPos): TTyCharFormatId;
var
  k: Integer;
begin
  k := FText.ParaOfPos(APos);
  Result := InheritedFormat(RunsOfData(DataOf(k)), APos - FText.ParaStart(k));
end;

function TTyRichDocument.CellAt(AIndex: Integer): TTyRichCell;
begin
  Result := CellOfData(DataOf(AIndex));
end;

function TTyRichDocument.ReadValue(AData: Pointer; out AFormat: TTyParaFormatId;
  out ARuns: TTyRunArray; out ACell: TTyRichCell): Boolean;
var
  d: TTyRichParaData;
begin
  d := TTyRichParaData(AData);
  Result := (d <> nil) or (FLoader = nil);
  AFormat := FormatOfData(d);
  ARuns := RunsOfData(d);
  ACell := CellOfData(d);
end;

function TTyRichDocument.ListTextOf(AIndex: Integer): UTF8String;
begin
  Result := ValueListText(DataOf(AIndex));
end;

function TTyRichDocument.ValueListText(AData: Pointer): UTF8String;
begin
  if AData = nil then Exit('');
  Result := TTyRichParaData(AData).FListText;
end;

{ ---- rows that hold a nested table ---- }

function NestedRowRefused: ETyRichRefused;
begin
  Result := ETyRichRefused.Create(rsRichModelNestedRow);
  Result.FixedRow := True;
end;

function TTyRichDocument.FixedData(D: TTyRichParaData): Boolean;
begin
  Result := (D <> nil) and (D.FCell <> nil) and D.FCell.FRow.FHoldsNestedTable;
end;

function TTyRichDocument.RowAt(AIndex: Integer): TTyRichRow;
var
  c: TTyRichCell;
begin
  c := CellOfData(DataOf(AIndex));
  if c = nil then Result := nil else Result := c.FRow;
end;

function TTyRichDocument.FixedRowAt(AIndex: Integer): TTyRichRow;
begin
  Result := RowAt(AIndex);
  if (Result <> nil) and not Result.FHoldsNestedTable then Result := nil;
end;

{ What a delete leaves of the paragraphs k .. m its range lies in: one paragraph, made of
  k's head and m's tail. A paragraph is changed when it loses characters or is joined with
  another; the ones between, and k when the range starts at its start, go whole. Only k and
  m are read (the delete reads them anyway), and a neighbour of one that is in such a row:
  paragraphs that go whole are not parsed for this. }
function TTyRichDocument.ChangeRefused(APos, ALen: TTyRichPos): Boolean;
var
  k, m: Integer;
  e: TTyRichPos;
  headOfK, headOfM: Boolean;
  rk, rm: TTyRichRow;
begin
  Result := False;
  if (APos < 0) or (ALen < 0) or (APos + ALen > FText.Length) then Exit;
  BeginRead;
  try
    k := FText.ParaOfPos(APos);
    if ALen = 0 then Exit(FixedRowAt(k) <> nil);
    e := APos + ALen;
    m := FText.ParaOfPos(e);
    if m = k then Exit(FixedRowAt(k) <> nil);
    headOfK := APos > FText.ParaStart(k);      // k keeps a head: it is joined with m's tail
    headOfM := e > FText.ParaStart(m);         // m loses a head
    rk := FixedRowAt(k);
    rm := FixedRowAt(m);
    if headOfK and (rk <> nil) then Exit(True);
    if (headOfK or headOfM) and (rm <> nil) then Exit(True);
    // a row among the paragraphs that go whole must go whole too. A row is a run of
    // paragraphs, so it is cut only where a paragraph of it stays just outside them: the
    // one before k (when k goes), or m (when the one before m goes with it)
    if not headOfK and (rk <> nil) and (k > 0) and (RowAt(k - 1) = rk) then Exit(True);
    if (rm <> nil) and (RowAt(m - 1) = rm) then Exit(True);
  finally
    EndRead;
  end;
end;

function TTyRichDocument.CanChange(APos, ALen: TTyRichPos): Boolean;
begin
  Result := not ChangeRefused(APos, ALen);
end;

function TTyRichDocument.WholeRows(AFrom, ATo: TTyRichPos): Boolean;
var
  k, m: Integer;
  ck, cl, cn: TTyRichCell;
begin
  Result := False;
  k := FText.ParaOfPos(AFrom);
  ck := CellAt(k);
  if (ck = nil) or (AFrom <> FText.ParaStart(k)) then Exit;
  // from a row's first paragraph
  if (k > 0) and (CellAt(k - 1) <> nil) and (CellAt(k - 1).Row = ck.Row) then Exit;
  { To the start of the paragraph after a row of the same table. Not to the text's end: a
    range that ends there ends inside a table that ends the text (only code makes one: a
    file read from RTF ends after its last row), whose last paragraph has no separator to
    go with it - the engine would leave it in its cell and the row's other cells with no
    paragraph. Refused, until table editing. }
  if ATo >= FText.Length then Exit;
  m := FText.ParaOfPos(ATo);
  if (m = 0) or (ATo <> FText.ParaStart(m)) then Exit;
  cl := CellAt(m - 1);
  if (cl = nil) or (cl.Row.Table <> ck.Row.Table) then Exit;
  if m < FText.ParaCount then
  begin
    cn := CellAt(m);
    if (cn <> nil) and (cn.Row = cl.Row) then Exit;
  end;
  Result := True;
end;

function TTyRichDocument.UserRangeAllowed(var AStart, ALen: TTyRichPos): Boolean;
var
  k, m: Integer;
  ck, cm, cp: TTyRichCell;
begin
  Result := True;
  if ALen <= 0 then Exit;
  // (the cells are compared inside one read: a document that parses on demand keeps them)
  BeginRead;
  try
    k := FText.ParaOfPos(AStart);
    // the paragraph the deletion joins with: the one its end lies in (after a separator, the next)
    m := FText.ParaOfPos(AStart + ALen);
    if m = k then Exit;
    ck := CellAt(k);
    cm := CellAt(m);
    { A range that begins outside a table and ends exactly where its first row starts keeps
      its last separator: the text goes, the paragraph before the table stays (Word's way) -
      the engine would merge it into the first cell. }
    if (cm <> nil) and (AStart + ALen = FText.ParaStart(m)) and
      ((ck = nil) or (ck.Row.Table <> cm.Row.Table)) then
    begin
      cp := CellAt(m - 1);
      if (cp = nil) or (cp.Row.Table <> cm.Row.Table) then
      begin
        Dec(ALen);
        m := FText.ParaOfPos(AStart + ALen);
        if m = k then Exit;
        cm := CellAt(m);
      end;
    end;
    { One that crosses a cell's or a row's edge is refused: the engine would merge paragraphs
      of two cells and leave a cell with no paragraph, no place for the caret. Whole rows,
      from a row's start to a row's end, the engine deletes cleanly. }
    if (ck <> cm) and not WholeRows(AStart, AStart + ALen) then Result := False;
  finally
    EndRead;
  end;
end;

function TTyRichDocument.TableAt(AIndex: Integer): TTyRichTable;
var
  c: TTyRichCell;
begin
  c := CellAt(AIndex);
  if c = nil then Result := nil else Result := c.Table;
end;

function TTyRichDocument.TableParas(AIndex: Integer; out AFirst, ALast: Integer): Boolean;
var
  t: TTyRichTable;
  last: Integer;
begin
  AFirst := -1;
  ALast := -1;
  // t is held across the reads of its neighbours
  BeginRead;
  try
    t := TableAt(AIndex);
    if t = nil then Exit(False);
    AFirst := AIndex;
    while (AFirst > 0) and (TableAt(AFirst - 1) = t) do Dec(AFirst);
    ALast := AIndex;
    last := FText.ParaCount - 1;
    while (ALast < last) and (TableAt(ALast + 1) = t) do Inc(ALast);
    Result := True;
  finally
    EndRead;
  end;
end;

function TTyRichDocument.CellParas(AIndex: Integer; ACell: TTyRichCell;
  out AFirst, ALast: Integer): Boolean;
var
  t: TTyRichTable;
  c: TTyRichCell;
  i, last: Integer;

  function Before(A, B: TTyRichCell): Boolean;
  begin
    Result := (A.Row.Index < B.Row.Index) or
      ((A.Row.Index = B.Row.Index) and (A.Index < B.Index));
  end;

begin
  AFirst := -1;
  ALast := -1;
  // (ACell is the caller's: it reads it and calls this inside one read scope)
  BeginRead;
  try
    t := TableAt(AIndex);
    if (t = nil) or (ACell = nil) or (ACell.Table <> t) then Exit(False);
    last := FText.ParaCount - 1;
    i := AIndex;
    c := CellAt(i);
    // walk towards the cell: cells lie in row order
    while c <> ACell do
    begin
      if Before(c, ACell) then Inc(i) else Dec(i);
      if (i < 0) or (i > last) then Exit(False);
      c := CellAt(i);
      if (c = nil) or (c.Table <> t) then Exit(False);
    end;
    AFirst := i;
    while (AFirst > 0) and (CellAt(AFirst - 1) = ACell) do Dec(AFirst);
    ALast := i;
    while (ALast < last) and (CellAt(ALast + 1) = ACell) do Inc(ALast);
    Result := True;
  finally
    EndRead;
  end;
end;

function TTyRichDocument.ParaDataOf(AIndex: Integer): Pointer;
begin
  Result := DataOf(AIndex);
end;

function TTyRichDocument.IsLiveParaData(AData: Pointer): Boolean;
var
  d: TTyRichParaData;
begin
  d := FFirstData;
  while d <> nil do
  begin
    if Pointer(d) = AData then Exit(True);
    d := d.FNext;
  end;
  Result := False;
end;

{ ---- primitives ---- }

procedure TTyRichDocument.CheckCharId(AId: TTyCharFormatId);
begin
  if (AId < 0) or (AId >= FFormats.CharCount) then
    raise ETyRichModel.CreateFmt('Character format id %d out of range', [AId]);
end;

procedure TTyRichDocument.CheckParaId(AId: TTyParaFormatId);
begin
  if (AId < 0) or (AId >= FFormats.ParaCount) then
    raise ETyRichModel.CreateFmt('Paragraph format id %d out of range', [AId]);
end;

function TTyRichDocument.NewUndo(const AChange: TTyRichChange): TTyRichUndoData;
begin
  Result := TTyRichUndoData.Create;
  Result.FDoc := Self;
  Result.FChange := AChange;
end;

{ A then B, as one change: the span of both, in the coordinates before A (old) and after B
  (new). Outside the span the two documents differ only by the shift A and B made. }
procedure ComposeChange(var A: TTyRichChange; var AHas: Boolean; const B: TTyRichChange);
var
  s, e: TTyRichPos;
  ps, pe: Integer;
begin
  if not AHas then
  begin
    A := B;
    AHas := True;
    Exit;
  end;
  s := A.Pos;
  if B.Pos < s then s := B.Pos;
  e := A.Pos + A.NewLen;
  if B.Pos + B.OldLen > e then e := B.Pos + B.OldLen;
  A.OldLen := (e - s) - (A.NewLen - A.OldLen);
  A.NewLen := (e - s) + (B.NewLen - B.OldLen);
  A.Pos := s;
  ps := A.FirstPara;
  if B.FirstPara < ps then ps := B.FirstPara;
  pe := A.FirstPara + A.NewParaCount;
  if B.FirstPara + B.OldParaCount > pe then pe := B.FirstPara + B.OldParaCount;
  A.OldParaCount := (pe - ps) - (A.NewParaCount - A.OldParaCount);
  A.NewParaCount := (pe - ps) + (B.NewParaCount - B.OldParaCount);
  A.FirstPara := ps;
  A.Kinds := A.Kinds + B.Kinds;
end;

procedure TTyRichDocument.Notify(const AChange: TTyRichChange);
begin
  // inside a command the history numbers the content (Execute, Undo, Redo)
  if FRunning = nil then LeftHistory;
  // inside a command the observers hear one change at the end (Flush; in an update block,
  // at the outermost EndUpdate)
  if FHold > 0 then
  begin
    ComposeChange(FPending, FHasPending, AChange);
    Exit;
  end;
  if Assigned(FOnChange) then FOnChange(Self, AChange);
end;

{ ---- format walks (one MapParaData pass, see ApplyCharFormat) ---- }

type
  TTyRichCharWalk = class
  public
    Doc: TTyRichDocument;
    Undo: TTyRichUndoData;
    K, Last: Integer;
    APos, B: Int64;
    PsK, LenK, PsLast, LenLast: Int64;
    Mask: TTyCharFormatMask;
    Value: TTyCharFormat;
    // of FontName and SizeHalfPt: a run with none of its own keeps none
    KeepNone: TTyCharFormatMask;
    FromIds, ToIds: array of TTyCharFormatId;
    PrevD, PrevNew: TTyRichParaData;
    Changed: Boolean;     // a value changed (a write of what is there is no step)
    function MapId(AId: TTyCharFormatId): TTyCharFormatId;
    function Map(AIndex: Integer; AData: Pointer): Pointer;
  end;

  TTyRichParaWalk = class
  public
    Doc: TTyRichDocument;
    Undo: TTyRichUndoData;
    First: Integer;
    Mask: TTyParaFormatMask;
    Value: TTyParaFormat;
    FromIds, ToIds: array of TTyParaFormatId;
    PrevD, PrevNew: TTyRichParaData;
    Changed: Boolean;
    function Map(AIndex: Integer; AData: Pointer): Pointer;
  end;

  TTyRichRevertWalk = class
  public
    Doc: TTyRichDocument;
    Undo: TTyRichUndoData;
    Run: Integer;
    Left: Integer;
    function Map(AIndex: Integer; AData: Pointer): Pointer;
  end;

function TTyRichCharWalk.MapId(AId: TTyCharFormatId): TTyCharFormatId;
var
  x: Integer;
  f: TTyCharFormat;
  m: TTyCharFormatMask;
begin
  for x := 0 to High(FromIds) do
    if FromIds[x] = AId then Exit(ToIds[x]);
  f := Doc.FFormats.CharFormat(AId);
  m := Mask;
  if (cffFontName in KeepNone) and (f.FontName = '') then Exclude(m, cffFontName);
  if (cffSize in KeepNone) and (f.SizeHalfPt <= 0) then Exclude(m, cffSize);
  Result := Doc.FFormats.InternChar(TyMergeCharFormat(f, m, Value));
  SetLength(FromIds, Length(FromIds) + 1);
  SetLength(ToIds, Length(ToIds) + 1);
  FromIds[High(FromIds)] := AId;
  ToIds[High(ToIds)] := Result;
end;

function TTyRichCharWalk.Map(AIndex: Integer; AData: Pointer): Pointer;
var
  d, nd: TTyRichParaData;
  r, runs: TTyRunArray;
  whole: Boolean;
  j, n: Integer;
  ps, len, lo, hi, s, e: Int64;
begin
  d := TTyRichParaData(AData);
  // not parsed yet: parse it (the slot then holds d)
  if (d = nil) and (Doc.FLoader <> nil) then d := Doc.DataOf(AIndex);
  Undo.AddOld(d);
  Result := d;
  // a row that holds a nested table stays as the file has it
  if Doc.FixedData(d) then Exit;
  r := Doc.RunsOfData(d);
  whole := (AIndex > K) and (AIndex < Last);
  runs := nil;
  n := 0;
  if whole then
  begin
    // a paragraph inside the range: every run, no lengths needed; equal values (plain
    // paragraphs) map to one shared result
    if (AIndex > K + 1) and (d = PrevD) then
      nd := PrevNew
    else
    begin
      for j := 0 to High(r) do AppendRun(runs, n, r[j].Start, MapId(r[j].Format), r[j].Obj);
      SetLength(runs, n);
      if SameRuns(runs, r) then nd := d
      else nd := Doc.MakeDataLike(Doc.FormatOfData(d), runs, Doc.CellOfData(d), d);
      PrevD := d;
      PrevNew := nd;
    end;
  end
  else
  begin
    if AIndex = K then
    begin
      ps := PsK;
      len := LenK;
    end
    else
    begin
      ps := PsLast;
      len := LenLast;
    end;
    lo := APos - ps;
    if lo < 0 then lo := 0;
    hi := B - ps;
    if hi > len then hi := len;
    if len = 0 then
    begin
      if (APos <= ps) and (ps < B) then
        AppendRun(runs, n, 0, MapId(r[0].Format), nil)
      else
        Exit;
    end
    else if lo >= hi then
      Exit
    else
      for j := 0 to High(r) do
      begin
        s := r[j].Start;
        e := RunEnd(r, j, len);
        if (s < lo) then AppendRun(runs, n, s, r[j].Format, r[j].Obj);
        if (e > lo) and (s < hi) then
        begin
          if s < lo then s := lo;
          AppendRun(runs, n, s, MapId(r[j].Format), r[j].Obj);
        end;
        if e > hi then
        begin
          if s < hi then s := hi;
          AppendRun(runs, n, s, r[j].Format, r[j].Obj);
        end;
      end;
    SetLength(runs, n);
    if SameRuns(runs, r) then nd := d
    else nd := Doc.MakeDataLike(Doc.FormatOfData(d), runs, Doc.CellOfData(d), d);
  end;
  if nd <> d then
  begin
    // the slot's reference moves to the new value; the record keeps d alive
    Doc.AcquireData(nd);
    Doc.ReleaseData(d);
    Changed := True;
  end;
  Result := nd;
end;

function TTyRichParaWalk.Map(AIndex: Integer; AData: Pointer): Pointer;
var
  d, nd: TTyRichParaData;
  oldFmt, newFmt: TTyParaFormatId;
  x: Integer;
begin
  d := TTyRichParaData(AData);
  if (d = nil) and (Doc.FLoader <> nil) then d := Doc.DataOf(AIndex);
  Undo.AddOld(d);
  // a row that holds a nested table stays as the file has it
  if Doc.FixedData(d) then Exit(d);
  if (AIndex > First) and (d = PrevD) then
    nd := PrevNew
  else
  begin
    oldFmt := Doc.FormatOfData(d);
    newFmt := -1;
    for x := 0 to High(FromIds) do
      if FromIds[x] = oldFmt then newFmt := ToIds[x];
    if newFmt < 0 then
    begin
      newFmt := Doc.FFormats.InternPara(TyMergeParaFormat(Doc.FFormats.ParaFormat(oldFmt), Mask,
        Value));
      SetLength(FromIds, Length(FromIds) + 1);
      SetLength(ToIds, Length(ToIds) + 1);
      FromIds[High(FromIds)] := oldFmt;
      ToIds[High(ToIds)] := newFmt;
    end;
    // the runs are immutable, so the new value shares them
    if newFmt = oldFmt then nd := d
    else nd := Doc.MakeDataLike(newFmt, Doc.RunsOfData(d), Doc.CellOfData(d), d);
    PrevD := d;
    PrevNew := nd;
  end;
  if nd <> d then
  begin
    Doc.AcquireData(nd);
    Doc.ReleaseData(d);
    Changed := True;
  end;
  Result := nd;
end;

function TTyRichRevertWalk.Map(AIndex: Integer; AData: Pointer): Pointer;
var
  old: TTyRichParaData;
begin
  old := Undo.FOldData[Run].Data;
  Dec(Left);
  if (Left = 0) and (Run + 1 < Undo.FOldCount) then
  begin
    Inc(Run);
    Left := Undo.FOldData[Run].Count;
  end;
  if Pointer(old) <> AData then
  begin
    Doc.AcquireData(old);
    Doc.ReleaseData(TTyRichParaData(AData));
  end;
  Result := old;
end;

{ AText starts with a byte that continues a UTF-8 sequence (80..BF), or ends inside one: a lead
  byte (C2..F4, or F8..FB, the first of a text file's escaped byte) that its last bytes do not
  complete. The storage counts characters piece by piece and keeps an insert in pieces of its
  own, while the copy and the layout read a paragraph's bytes as one stretch: such ends would
  join with the bytes next to them there and be counted as other characters than the storage
  counts. }
function CutSequence(const AText: UTF8String): Boolean;
var
  n, i, need: Integer;
begin
  n := Length(AText);
  if n = 0 then Exit(False);
  if Byte(AText[1]) and $C0 = $80 then Exit(True);
  i := n;
  while (i > 1) and (n - i < 3) and (Byte(AText[i]) and $C0 = $80) do Dec(i);
  case Byte(AText[i]) of
    $C2..$DF, $F8..$FB: need := 2;
    $E0..$EF: need := 3;
    $F0..$F4: need := 4;
  else
    Exit(False);
  end;
  Result := n - i + 1 < need;
end;

function TTyRichDocument.InsertCore(APos: TTyRichPos; const AText: UTF8String;
  AFormat: TTyCharFormatId; AObj: TTyRichObject): TTyRichUndoData;
var
  c: TTyRichChange;
  k, s, i, n1, n2: Integer;
  d, mid: TTyRichParaData;
  r, runs1, runs2, one: TTyRunArray;
  ps, o, len, len1, lenLast, added, oldChars: Int64;
  f: TTyCharFormatId;
  fmt: TTyParaFormatId;
  cell: TTyRichCell;
  oldCount: Integer;
  txt: UTF8String;
begin
  c := Default(TTyRichChange);
  c.Pos := APos;
  FText.ParaOfPos(APos);   // range check before anything changes
  if AText = '' then Exit(NewUndo(c));
  if CutSequence(AText) then
    raise ETyRichModel.Create('The text to insert starts or ends inside a UTF-8 sequence');
  if ChangeRefused(APos, 0) then raise NestedRowRefused;
  // new breaks take the document's majority kind, so saving writes the stored bytes as they
  // are: the breaks already there stay what they were in the file
  txt := WithBreaks(AText, FDominantLineBreak);
  if AFormat <> TyRichInheritFormat then CheckCharId(AFormat);
  k := FText.ParaOfPos(APos);
  d := DataOf(k);
  r := RunsOfData(d);
  ps := FText.ParaStart(k);
  o := APos - ps;
  len := FText.ParaLength(k);
  if AFormat = TyRichInheritFormat then f := InheritedFormat(r, o) else f := AFormat;
  fmt := FormatOfData(d);
  cell := CellOfData(d);
  oldChars := FText.Length;
  oldCount := FText.ParaCount;
  Result := NewUndo(c);
  try
    Result.FFirstPara := k;
    Result.AddOld(d);
    Result.SealOld;
    // the pieces the insert splits (a lazy paragraph's one), for the undo to give back
    Result.FSpan := FText.PieceSpan(APos, APos);
    Inc(FEditing);
    try
      FText.Insert(APos, txt);
    finally
      Dec(FEditing);
    end;
    added := FText.Length - oldChars;
    s := FText.ParaCount - oldCount;
    runs1 := nil;
    n1 := 0;
    if s = 0 then
    begin
      SetLength(runs1, Length(r) + 2);
      AppendSlice(runs1, n1, r, len, 0, o, 0);
      AppendRun(runs1, n1, o, f, AObj);
      AppendSlice(runs1, n1, r, len, o, len, added);
      SetLength(runs1, n1);
      PutData(k, d, MakeDataLike(fmt, runs1, cell, d));
    end
    else
    begin
      // the storage left d with the first part and nil on the new paragraphs; every part
      // carries the paragraph's format, the runs split at APos
      len1 := FText.ParaLength(k);
      AppendSlice(runs1, n1, r, len, 0, o, 0);
      if len1 > o then AppendRun(runs1, n1, o, f, nil);
      if n1 = 0 then AppendRun(runs1, n1, 0, f, nil);
      SetLength(runs1, n1);
      lenLast := FText.ParaLength(k + s) - (len - o);
      runs2 := nil;
      n2 := 0;
      if lenLast > 0 then AppendRun(runs2, n2, 0, f, nil);
      AppendSlice(runs2, n2, r, len, o, len, lenLast - o);
      if n2 = 0 then AppendRun(runs2, n2, 0, f, nil);
      SetLength(runs2, n2);
      if s > 1 then
      begin
        // the paragraphs in between are alike: one shared value
        one := nil;
        SetLength(one, 1);
        one[0].Start := 0;
        one[0].Format := f;
        one[0].Obj := nil;
        mid := MakeData(fmt, one, cell);
        if mid <> nil then
        begin
          AcquireData(mid);
          for i := k + 1 to k + s - 1 do PutData(i, nil, mid);
          ReleaseData(mid);
        end;
      end;
      PutData(k, d, MakeDataLike(fmt, runs1, cell, d));
      PutData(k + s, nil, MakeData(fmt, runs2, cell));
    end;
  except
    Result.Free;
    raise;
  end;
  c.Kinds := [rckText];
  if s > 0 then Include(c.Kinds, rckStructure);
  c.NewLen := added;
  Result.FInserted := added;
  c.FirstPara := k;
  c.OldParaCount := 1;
  c.NewParaCount := 1 + s;
  Result.FChange := c;
  Notify(c);
end;

function TTyRichDocument.InsertText(APos: TTyRichPos; const AText: UTF8String;
  AFormat: TTyCharFormatId): TTyRichUndoData;
begin
  Result := InsertCore(APos, AText, AFormat, nil);
end;

function TTyRichDocument.InsertObject(APos: TTyRichPos; AObject: TTyRichObject;
  AFormat: TTyCharFormatId): TTyRichUndoData;
begin
  if AObject = nil then
    raise ETyRichModel.Create('InsertObject needs an object');
  Result := InsertCore(APos, TyRichObjectChar, AFormat, AObject);
end;

function TTyRichDocument.DeleteRange(APos, ALen: TTyRichPos): TTyRichUndoData;
begin
  if (APos < 0) or (ALen < 0) or (APos + ALen > FText.Length) then
    raise ETyRichModel.CreateFmt('Range %d+%d out of 0..%d', [APos, ALen, FText.Length]);
  if (ALen > 0) and ChangeRefused(APos, ALen) then raise NestedRowRefused;
  // the values of the two end paragraphs are held while the other is read
  BeginRead;
  try
    Result := DeleteCore(APos, ALen);
  finally
    EndRead;
  end;
end;

function TTyRichDocument.DeleteCore(APos, ALen: TTyRichPos): TTyRichUndoData;
var
  c: TTyRichChange;
  k, m, n, i: Integer;
  dk, dm, merged, src: TTyRichParaData;
  rk, rm, runs: TTyRunArray;
  e, psk, lenk, ok, lenm, om: Int64;
  fmt: TTyParaFormatId;
  cell: TTyRichCell;
  join: Boolean;
begin
  c := Default(TTyRichChange);
  c.Pos := APos;
  if ALen = 0 then Exit(NewUndo(c));
  e := APos + ALen;
  k := FText.ParaOfPos(APos);
  m := FText.ParaOfPos(e);
  dk := DataOf(k);
  if m <> k then dm := DataOf(m) else dm := dk;
  rk := RunsOfData(dk);
  psk := FText.ParaStart(k);
  lenk := FText.ParaLength(k);
  ok := APos - psk;
  runs := nil;
  n := 0;
  if m = k then
  begin
    AppendSlice(runs, n, rk, lenk, 0, ok, 0);
    AppendSlice(runs, n, rk, lenk, ok + ALen, lenk, -ALen);
    if n = 0 then AppendRun(runs, n, 0, rk[RunIndexAt(rk, ok)].Format, nil);
    SetLength(runs, n);
    merged := MakeDataLike(FormatOfData(dk), runs, CellOfData(dk), dk);
  end
  else
  begin
    rm := RunsOfData(dm);
    lenm := FText.ParaLength(m);
    om := e - FText.ParaStart(m);
    // one separator and nothing else, after text: the paragraph before it gives the format.
    // After an empty paragraph it does not (measured in WordPad's engine): that is the
    // empty paragraph going, a whole paragraph like any other
    join := (m = k + 1) and (ALen = 1) and (lenk > 0);
    if join then
    begin
      fmt := FormatOfData(dk);
      cell := CellOfData(dk);
      src := dk;
    end
    else
    begin
      // otherwise the paragraph the range ends in does (measured in WordPad)
      fmt := FormatOfData(dm);
      cell := CellOfData(dm);
      src := dm;
    end;
    if (ok = 0) and (om = 0) and not join then
      merged := dm   // whole paragraphs went: the next one is untouched
    else
    begin
      AppendSlice(runs, n, rk, lenk, 0, ok, 0);
      AppendSlice(runs, n, rm, lenm, om, lenm, ok - om);
      if n = 0 then AppendRun(runs, n, 0, rk[RunIndexAt(rk, ok)].Format, nil);
      SetLength(runs, n);
      merged := MakeDataLike(fmt, runs, cell, src);
    end;
  end;
  Result := NewUndo(c);
  try
    Result.FRemoved := FText.PieceSnapshot(APos, ALen);
    for i := 0 to High(Result.FRemoved.Pieces) do
      if (Result.FRemoved.Pieces[i].Separator <> rsNone) and
         (Result.FRemoved.Pieces[i].Data <> nil) then
        AcquireData(TTyRichParaData(Result.FRemoved.Pieces[i].Data));
    Result.FFirstPara := k;
    Result.AddOld(dk);
    Result.SealOld;
    { The pieces the delete splits at its two ends (a lazy paragraph it cuts into), for the
      undo to give back: one span when the ends are that close. }
    Result.FSpan := FText.PieceSpan(APos, APos);
    Result.FSpan2 := FText.PieceSpan(e, e);
    if Result.FSpan.Pos + Result.FSpan.Pieces.CharCount > Result.FSpan2.Pos then
    begin
      Result.FSpan := FText.PieceSpan(APos, e);
      Result.FSpan2 := Default(TTyRichSpan);
    end;
    AcquireData(merged);   // it may be dm, whose slot the delete drops
    try
      Inc(FEditing);
      try
        FText.Delete(APos, ALen);
      finally
        Dec(FEditing);
      end;
      PutData(k, dk, merged);
    finally
      ReleaseData(merged);
    end;
  except
    Result.Free;
    raise;
  end;
  c.Kinds := [rckText];
  if m > k then Include(c.Kinds, rckStructure);
  c.OldLen := ALen;
  c.FirstPara := k;
  c.OldParaCount := m - k + 1;
  c.NewParaCount := 1;
  Result.FChange := c;
  Notify(c);
end;

{ The text storage's sequence rule (tyControls.RichEdit.Text's SeqLen): the length of the valid
  UTF-8 sequence at P, 1 for a byte that starts none (a character of its own). }
function StoredSeqLen(P: PByte; AAvail: PtrInt): Integer; inline;
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

function StoredChars(const S: RawByteString): Int64;
var
  p, stop: PByte;
begin
  Result := 0;
  if S = '' then Exit;
  p := PByte(Pointer(S));
  stop := p + Length(S);
  while p < stop do
  begin
    if p^ < $80 then Inc(p) else Inc(p, StoredSeqLen(p, stop - p));
    Inc(Result);
  end;
end;

{ A growing buffer of bytes: a stretch's new text, built once. }
type
  TReplaceBuf = record
    S: RawByteString;
    N: PtrInt;
  end;

procedure BufAdd(var B: TReplaceBuf; P: PByte; ACount: PtrInt);
var
  cap: PtrInt;
begin
  if ACount <= 0 then Exit;
  if B.N + ACount > Length(B.S) then
  begin
    cap := Length(B.S) * 2;
    if cap < B.N + ACount then cap := B.N + ACount;
    if cap < 256 then cap := 256;
    SetLength(B.S, cap);
  end;
  Move(P^, B.S[B.N + 1], ACount);
  Inc(B.N, ACount);
end;

function TTyRichDocument.ReplaceInParas(const APos: array of TTyRichPos; AFrom, ACount: Integer;
  ALen: TTyRichPos; const AText: UTF8String; out ASkipped: Integer): TTyRichUndoData;
const
  // two matches this close are one stretch of the text: what lies between them is copied
  CGap = 256;
var
  c: TTyRichChange;
  i, j, x, y, z, para, nr, lowPara, highPara: Integer;
  d: TTyRichParaData;
  runs, nruns: TTyRunArray;
  ps, len, off, shift, prevEnd, rlen, a, b, total, grow, oldLo, oldHi, at: TTyRichPos;
  snap: TTyRichPieces;
  seg: UTF8String;
  buf: TReplaceBuf;
  p, stop, gapFrom: PByte;
  k: Integer;
begin
  ASkipped := 0;
  c := Default(TTyRichChange);
  Result := nil;
  if ACount <= 0 then Exit(NewUndo(c));
  if CutSequence(AText) then
    raise ETyRichModel.Create('The text to insert starts or ends inside a UTF-8 sequence');
  for k := 1 to Length(AText) do
    if AText[k] in [#10, #13] then
      raise ETyRichModel.Create('ReplaceInParas takes no paragraph separator');
  if ALen <= 0 then raise ETyRichModel.Create('ReplaceInParas needs matches of a length');
  for i := AFrom to AFrom + ACount - 1 do
    if (APos[i] < 0) or (APos[i] + ALen > FText.Length) or
      ((i > AFrom) and (APos[i] < APos[i - 1] + ALen)) then
      raise ETyRichModel.Create('ReplaceInParas: matches out of range or out of order');
  rlen := StoredChars(AText);
  Result := NewUndo(c);
  lowPara := -1;
  highPara := -1;
  grow := 0;
  oldLo := 0;
  oldHi := 0;
  buf.S := '';
  buf.N := 0;
  // (the values read are held while the others are: one read scope)
  BeginRead;
  try
    try
      // paragraph by paragraph, the last first: positions before stay where they are
      i := AFrom + ACount - 1;
      while i >= AFrom do
      begin
        para := FText.ParaOfPos(APos[i]);
        ps := FText.ParaStart(para);
        len := FText.ParaLength(para);
        j := i;
        while (j > AFrom) and (APos[j - 1] >= ps) do Dec(j);
        if APos[i] + ALen > ps + len then
          raise ETyRichModel.Create('ReplaceInParas: a match takes a paragraph separator');
        d := DataOf(para);
        // a row that holds a nested table stays as the file has it
        if FixedData(d) then
        begin
          Inc(ASkipped, i - j + 1);
          i := j - 1;
          Continue;
        end;
        runs := RunsOfData(d);
        // its runs after: each replacement in the format of the first character it replaces
        nruns := nil;
        nr := 0;
        shift := 0;
        prevEnd := 0;
        for x := j to i do
        begin
          off := APos[x] - ps;
          AppendSlice(nruns, nr, runs, len, prevEnd, off, shift);
          if rlen > 0 then AppendRun(nruns, nr, off + shift, runs[RunIndexAt(runs, off)].Format, nil);
          Inc(shift, rlen - ALen);
          prevEnd := off + ALen;
        end;
        AppendSlice(nruns, nr, runs, len, prevEnd, len, shift);
        if nr = 0 then AppendRun(nruns, nr, 0, runs[RunIndexAt(runs, APos[j] - ps)].Format, nil);
        SetLength(nruns, nr);
        // its pieces as they are, whole, with its separator (a lazy paragraph: one, the file's)
        total := len;
        if para < FText.ParaCount - 1 then Inc(total);
        snap := FText.PieceSnapshot(ps, total);
        Result.AddSwap(para, d, snap);
        // the text: stretch by stretch, the last first
        Inc(FEditing);
        try
          x := i;
          while x >= j do
          begin
            y := x;
            while (y > j) and (APos[y] - (APos[y - 1] + ALen) <= CGap) do Dec(y);
            a := APos[y];
            b := APos[x] + ALen;
            buf.N := 0;
            if y = x then
              BufAdd(buf, PByte(Pointer(AText)), Length(AText))
            else
            begin
              // the stretch once, and what lies between its matches out of it
              seg := FText.GetText(a, b - a);
              p := PByte(Pointer(seg));
              stop := p + Length(seg);
              at := a;
              for z := y to x do
              begin
                // at the match z: its characters go, the text comes
                gapFrom := nil;
                while at < APos[z] + ALen do
                begin
                  if at = APos[z] then
                    BufAdd(buf, PByte(Pointer(AText)), Length(AText));
                  if p^ < $80 then Inc(p) else Inc(p, StoredSeqLen(p, stop - p));
                  Inc(at);
                end;
                if z < x then
                begin
                  gapFrom := p;
                  while at < APos[z + 1] do
                  begin
                    if p^ < $80 then Inc(p) else Inc(p, StoredSeqLen(p, stop - p));
                    Inc(at);
                  end;
                  BufAdd(buf, gapFrom, p - gapFrom);
                end;
              end;
            end;
            FText.Delete(a, b - a);
            if buf.N > 0 then FText.Insert(a, Copy(buf.S, 1, buf.N));
            x := y - 1;
          end;
        finally
          Dec(FEditing);
        end;
        PutData(para, d, MakeDataLike(FormatOfData(d), nruns, CellOfData(d), d));
        Inc(grow, shift);
        if highPara < 0 then
        begin
          highPara := para;
          oldHi := ps + len;
        end;
        lowPara := para;
        oldLo := ps;
        i := j - 1;
      end;
      Result.SealSwaps;
    except
      // what was changed goes back before the error travels on
      try
        Revert(Result);
      except
      end;
      Result.Free;
      raise;
    end;
  finally
    EndRead;
  end;
  // (all of them in rows the document keeps: nothing changed, an empty record)
  if lowPara < 0 then Exit;
  c.Kinds := [rckText];
  c.Pos := oldLo;
  c.OldLen := oldHi - oldLo;
  c.NewLen := c.OldLen + grow;
  c.FirstPara := lowPara;
  c.OldParaCount := highPara - lowPara + 1;
  c.NewParaCount := c.OldParaCount;
  Result.FChange := c;
  Notify(c);
end;

{ Undoes what ReplaceInParas did, the paragraph changed last first: each paragraph's text goes
  whole, with its separator, and its pieces come back (a lazy one: the file's bytes again, so
  that an edit undone saves the file as it was; the paragraph after it gets the value it had
  then), then its value. }
procedure TTyRichDocument.RevertSwaps(AUndo: TTyRichUndoData);
var
  e, i: Integer;
  ps, n: TTyRichPos;
  p: TTyRichPieces;
begin
  for e := AUndo.FSwapCount - 1 downto 0 do
  begin
    ps := FText.ParaStart(AUndo.FSwaps[e].Para);
    n := FText.ParaLength(AUndo.FSwaps[e].Para);
    if AUndo.FSwaps[e].Para < FText.ParaCount - 1 then Inc(n);
    p.Pieces := Copy(AUndo.FSwapPieces, AUndo.FSwaps[e].First, AUndo.FSwaps[e].Count);
    p.CharCount := 0;
    for i := 0 to High(p.Pieces) do Inc(p.CharCount, p.Pieces[i].CharCount);
    // the restored separator puts its value back in a slot: the slot's reference
    for i := 0 to High(p.Pieces) do
      if (p.Pieces[i].Separator <> rsNone) and (p.Pieces[i].Data <> nil) then
        AcquireData(TTyRichParaData(p.Pieces[i].Data));
    FText.Delete(ps, n);
    FText.RestorePieces(ps, p);
    PutData(AUndo.FSwaps[e].Para, SlotData(AUndo.FSwaps[e].Para), AUndo.FSwaps[e].Old);
  end;
end;

function TTyRichDocument.ApplyCharFormat(APos, ALen: TTyRichPos; AMask: TTyCharFormatMask;
  const AValue: TTyCharFormat; AKeepNone: TTyCharFormatMask): TTyRichUndoData;
var
  c: TTyRichChange;
  k, last: Integer;
  w: TTyRichCharWalk;
begin
  c := Default(TTyRichChange);
  c.Pos := APos;
  if (APos < 0) or (ALen < 0) or (APos + ALen > FText.Length) then
    raise ETyRichModel.CreateFmt('Range %d+%d out of 0..%d', [APos, ALen, FText.Length]);
  if (ALen = 0) or (AMask = []) then Exit(NewUndo(c));
  k := FText.ParaOfPos(APos);
  last := FText.ParaOfPos(APos + ALen);
  if (last > k) and (FText.ParaStart(last) = APos + ALen) then Dec(last);
  Result := NewUndo(c);
  w := TTyRichCharWalk.Create;
  try
    try
      w.Doc := Self;
      w.Undo := Result;
      w.K := k;
      w.Last := last;
      w.APos := APos;
      w.B := APos + ALen;
      w.Mask := AMask;
      w.Value := AValue;
      w.KeepNone := AKeepNone * [cffFontName, cffSize];
      // only the two end paragraphs need their place; the walk itself does no lookups
      w.PsK := FText.ParaStart(k);
      w.LenK := FText.ParaLength(k);
      w.PsLast := FText.ParaStart(last);
      w.LenLast := FText.ParaLength(last);
      Result.FFirstPara := k;
      FText.MapParaData(k, last, @w.Map);
      Result.SealOld;
      { No value changed (a write of what the text has, or a range wholly inside a row
        that holds a nested table): no change - the command is then not kept. }
      if not w.Changed then
      begin
        Result.FChange := c;
        Exit;
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    w.Free;
  end;
  c.Kinds := [rckFormat];
  c.OldLen := ALen;
  c.NewLen := ALen;
  c.FirstPara := k;
  c.OldParaCount := last - k + 1;
  c.NewParaCount := last - k + 1;
  Result.FChange := c;
  Notify(c);
end;

function TTyRichDocument.ApplyParaFormat(AFirstPara, ALastPara: Integer;
  AMask: TTyParaFormatMask; const AValue: TTyParaFormat): TTyRichUndoData;
var
  c: TTyRichChange;
  w: TTyRichParaWalk;
begin
  c := Default(TTyRichChange);
  if (AFirstPara < 0) or (ALastPara < AFirstPara) or (ALastPara >= FText.ParaCount) then
    raise ETyRichModel.CreateFmt('Paragraphs %d..%d out of 0..%d',
      [AFirstPara, ALastPara, FText.ParaCount - 1]);
  c.Pos := FText.ParaStart(AFirstPara);
  if AMask = [] then Exit(NewUndo(c));
  Result := NewUndo(c);
  w := TTyRichParaWalk.Create;
  try
    try
      w.Doc := Self;
      w.Undo := Result;
      w.First := AFirstPara;
      w.Mask := AMask;
      w.Value := AValue;
      Result.FFirstPara := AFirstPara;
      FText.MapParaData(AFirstPara, ALastPara, @w.Map);
      Result.SealOld;
      // no value changed: no change, the command is not kept
      if not w.Changed then
      begin
        Result.FChange := c;
        Exit;
      end;
    except
      Result.Free;
      raise;
    end;
  finally
    w.Free;
  end;
  c.Kinds := [rckFormat];
  c.OldLen := FText.ParaStart(ALastPara) + FText.ParaLength(ALastPara) - c.Pos;
  c.NewLen := c.OldLen;
  c.FirstPara := AFirstPara;
  c.OldParaCount := ALastPara - AFirstPara + 1;
  c.NewParaCount := c.OldParaCount;
  Result.FChange := c;
  Notify(c);
end;

function TTyRichDocument.MarkTable(AFirstPara: Integer; ATable: TTyRichTable;
  const ACellParas: array of Integer): TTyRichUndoData;
var
  c: TTyRichChange;
  total, i, p, r, ci, x, lastPara: Integer;
  cells: array of TTyRichCell;
  d: TTyRichParaData;
begin
  if ATable = nil then
    raise ETyRichModel.Create('MarkTable needs a table');
  if ATable.FParaRefs > 0 then
    raise ETyRichModel.Create('The table is already in use');
  if Length(ACellParas) <> ATable.CellCount then
    raise ETyRichModel.CreateFmt('%d paragraph counts for %d cells',
      [Length(ACellParas), ATable.CellCount]);
  total := 0;
  for i := 0 to High(ACellParas) do
  begin
    if ACellParas[i] < 1 then
      raise ETyRichModel.Create('Every cell needs at least one paragraph');
    Inc(total, ACellParas[i]);
  end;
  // no row yet: there is no paragraph range to mark (and none to report as changed)
  if total = 0 then
    raise ETyRichModel.Create('A table without cells cannot be marked');
  lastPara := AFirstPara + total - 1;
  if (AFirstPara < 0) or (lastPara >= FText.ParaCount) then
    raise ETyRichModel.CreateFmt('Paragraphs %d..%d out of 0..%d',
      [AFirstPara, lastPara, FText.ParaCount - 1]);
  for i := AFirstPara to lastPara do
    if CellOfData(DataOf(i)) <> nil then
      raise ETyRichModel.CreateFmt('Paragraph %d is already in a table', [i]);
  cells := nil;
  SetLength(cells, total);
  p := 0;
  i := 0;
  for r := 0 to ATable.RowCount - 1 do
    for ci := 0 to ATable.Rows[r].CellCount - 1 do
    begin
      for x := 1 to ACellParas[i] do
      begin
        cells[p] := ATable.Rows[r].Cells[ci];
        Inc(p);
      end;
      Inc(i);
    end;
  c := Default(TTyRichChange);
  c.Pos := FText.ParaStart(AFirstPara);
  Result := NewUndo(c);
  try
    Result.FFirstPara := AFirstPara;
    for i := 0 to total - 1 do
    begin
      d := DataOf(AFirstPara + i);
      Result.AddOld(d);
      PutData(AFirstPara + i, d, MakeDataLike(FormatOfData(d), RunsOfData(d), cells[i], d));
    end;
    Result.SealOld;
  except
    Result.Free;
    raise;
  end;
  c.Kinds := [rckStructure];
  c.OldLen := FText.ParaStart(lastPara) + FText.ParaLength(lastPara) - c.Pos;
  c.NewLen := c.OldLen;
  c.FirstPara := AFirstPara;
  c.OldParaCount := total;
  c.NewParaCount := total;
  Result.FChange := c;
  Notify(c);
end;

{ ---- a fragment of another document ---- }

constructor TTyRichFragment.Create(ATarget: TTyRichDocument; APos: TTyRichPos;
  ASource: TTyRichDocument; AEndsWithParagraph: Boolean; AFlatten: Boolean;
  AFilter: TTyRichFragmentFilter);
var
  t: TTyRichText;
  k, n, i: Integer;
  o: Int64;
  cell: TTyRichCell;
begin
  inherited Create;
  if (ATarget = nil) or (ASource = nil) or (ATarget = ASource) then
    raise ETyRichModel.Create('A fragment needs a target and a source of its own');
  FDoc := ATarget;
  FSrc := ASource;
  FFilter := AFilter;
  t := ATarget.FText;
  k := t.ParaOfPos(APos);   // range check
  o := APos - t.ParaStart(k);
  { The target's cell at APos is used to the end (the values made here hold it): in a document
    that parses on demand it stays as read only inside a read scope - one for all of this. }
  ATarget.BeginRead;
  try
  cell := ATarget.CellOfData(ATarget.DataOf(k));
  // a table goes into a table only as its text: there are no nested tables
  FFlat := AFlatten or (cell <> nil);
  FFlatCell := cell;
  FSrcDefault := ASource.DefaultCharFormat;
  n := ASource.FText.ParaCount;
  try
    if (ASource.FText.Length = 0) and not AEndsWithParagraph then Exit;
    SetLength(FCharMap, ASource.FFormats.CharCount);
    for i := 0 to High(FCharMap) do FCharMap[i] := -1;
    SetLength(FParaMap, ASource.FFormats.ParaCount);
    for i := 0 to High(FParaMap) do FParaMap[i] := -1;
    SetLength(FParts, n + 3);
    SetLength(FLens, n + 3);
    SetLength(FOwn, n + 3);
    // tables, cells and objects of a document that parses on demand stay as read meanwhile
    ASource.BeginRead;
    try
      ASource.FText.WalkParaTexts(0, n - 1, @TakePara, True);
    finally
      ASource.EndRead;
    end;
    if AEndsWithParagraph then
    begin
      AddText(nil, 0);
      AddPart(nil, 0, True);
    end;
    if not FFlat then
    begin
      // rows stay rows: the text before APos keeps its own paragraph, and a last row is
      // never joined with the text after APos
      if (o > 0) and (PartCell(0) <> nil) then InsertOwnFirst;
      if PartCell(FCount - 1) <> nil then
      begin
        AddText(nil, 0);
        AddPart(nil, 0, True);
      end;
    end;
    SetLength(FText, FTextLen);
  finally
    FSrc := nil;
    FFilter := nil;
    FCharMap := nil;
    FParaMap := nil;
    // a table made again was held while it was made: the values that use it hold theirs
    for i := 0 to FTabCount - 1 do
      if (FTabNew[i] <> nil) and (FTabNew[i] <> FTabSrc[i]) then FTabNew[i].Release;
    FTabSrc := nil;
    FTabNew := nil;
    FTabCount := 0;
  end;
  finally
    ATarget.EndRead;
  end;
end;

destructor TTyRichFragment.Destroy;
var
  i: Integer;
begin
  if FDoc <> nil then
    for i := 0 to FCount - 1 do FDoc.ReleaseData(FParts[i]);
  inherited Destroy;
end;

function TTyRichFragment.CharCount: Int64;
var
  i: Integer;
begin
  Result := 0;
  if FCount = 0 then Exit;
  Result := FCount - 1;
  for i := 0 to FCount - 1 do Inc(Result, FLens[i]);
end;

function TTyRichFragment.MemSize: Int64;
var
  i: Integer;
begin
  // the text: as it is, or what its first insert keeps alive in the add buffer
  Result := InstanceSize + Length(FText) + FTextBytes +
    Length(FPieces.Pieces) * SizeOf(TTyRichPiece) +
    Length(FParts) * (SizeOf(Pointer) + SizeOf(Int64) + 1);
  // the values are this fragment's own (made for it), with their runs (the objects they
  // bring: GatherObjects)
  for i := 0 to FCount - 1 do
    if FParts[i] <> nil then
      Inc(Result, FParts[i].InstanceSize + Length(FParts[i].FRuns) * SizeOf(TTyRichRun));
end;

procedure TTyRichFragment.GatherObjects(var AList: TTyRichObjectList; var ACount: Integer);
var
  i, j: Integer;
begin
  for i := 0 to FCount - 1 do
    if FParts[i] <> nil then
      for j := 0 to High(FParts[i].FRuns) do
        if FParts[i].FRuns[j].Obj <> nil then
        begin
          Inc(FDoc.FHistoryObjectVisits);
          AddObject(AList, ACount, FParts[i].FRuns[j].Obj);
        end;
end;

function TTyRichFragment.PartCell(AIndex: Integer): TTyRichCell;
begin
  if (AIndex < 0) or (AIndex >= FCount) or FOwn[AIndex] or (FParts[AIndex] = nil) then
    Result := nil
  else
    Result := FParts[AIndex].FCell;
end;

procedure TTyRichFragment.AddPart(AValue: TTyRichParaData; ALen: Int64; AOwn: Boolean);
begin
  if FCount = Length(FParts) then
  begin
    SetLength(FParts, FCount * 2 + 4);
    SetLength(FLens, FCount * 2 + 4);
    SetLength(FOwn, FCount * 2 + 4);
  end;
  FDoc.AcquireData(AValue);
  FParts[FCount] := AValue;
  FLens[FCount] := ALen;
  FOwn[FCount] := AOwn;
  Inc(FCount);
end;

procedure TTyRichFragment.InsertOwnFirst;
var
  i: Integer;
  s: UTF8String;
begin
  AddPart(nil, 0, True);
  for i := FCount - 1 downto 1 do
  begin
    FParts[i] := FParts[i - 1];
    FLens[i] := FLens[i - 1];
    FOwn[i] := FOwn[i - 1];
  end;
  FParts[0] := nil;
  FLens[0] := 0;
  FOwn[0] := True;
  s := #10;
  SetLength(FText, FTextLen);
  FText := s + FText;
  Inc(FTextLen);
end;

{ ALen bytes at P, after a separator when a part came before. }
procedure TTyRichFragment.AddText(P: PByte; ALen: PtrInt);
var
  need, i: PtrInt;
  q: PAnsiChar;
begin
  need := FTextLen + ALen + 1;
  if need > Length(FText) then
  begin
    if need < 2 * Length(FText) then need := 2 * Length(FText);
    SetLength(FText, need + 16);
  end;
  if FCount > 0 then
  begin
    FText[FTextLen + 1] := #10;
    Inc(FTextLen);
  end;
  if ALen > 0 then
  begin
    Move(P^, FText[FTextLen + 1], ALen);
    { A paragraph's text holds no separator; one a source should never give (a CR inside a
      paragraph) is a space here, so that the insert makes the parts it was counted to make. }
    q := @FText[FTextLen + 1];
    for i := 0 to ALen - 1 do
      if q[i] in [#10, #13] then q[i] := ' ';
    Inc(FTextLen, ALen);
  end;
end;

function TTyRichFragment.MapChar(AId: TTyCharFormatId): TTyCharFormatId;
var
  f: TTyCharFormat;
begin
  if (AId >= 0) and (AId < Length(FCharMap)) and (FCharMap[AId] >= 0) then Exit(FCharMap[AId]);
  f := FSrc.FFormats.CharFormat(AId);
  { What the source showed in its default font (no font of its own) keeps that font here,
    named: the target's defaults are not the source's. }
  if (f.FontName = '') and (FSrcDefault.FontName <> '') then
  begin
    f.FontName := FSrcDefault.FontName;
    f.Charset := FSrcDefault.Charset;
  end;
  if (f.SizeHalfPt = 0) and (FSrcDefault.SizeHalfPt <> 0) then f.SizeHalfPt := FSrcDefault.SizeHalfPt;
  if FFilter <> nil then f.Extra := MapExtra(f.Extra, False);
  Result := FDoc.FFormats.InternChar(f);
  if (AId >= 0) and (AId < Length(FCharMap)) then FCharMap[AId] := Result;
end;

function TTyRichFragment.MapPara(AId: TTyParaFormatId): TTyParaFormatId;
var
  f: TTyParaFormat;
begin
  if (AId >= 0) and (AId < Length(FParaMap)) and (FParaMap[AId] >= 0) then Exit(FParaMap[AId]);
  f := FSrc.FFormats.ParaFormat(AId);
  if FFilter <> nil then f.Extra := MapExtra(f.Extra, True);
  Result := FDoc.FFormats.InternPara(f);
  if (AId >= 0) and (AId < Length(FParaMap)) then FParaMap[AId] := Result;
end;

function TTyRichFragment.MapExtra(const AExtra: TTyOpaqueAttrs; APara: Boolean): TTyOpaqueAttrs;
var
  i: Integer;
begin
  Result.FItems := nil;
  for i := 0 to AExtra.Count - 1 do
    if FFilter.KeepFragment(AExtra.Item(i), APara) then Result.Add(AExtra.Item(i));
end;

{ The cell a paragraph of the source's ACell goes into: the very one, or with a filter the
  same cell of the table made again for the target - made at its first paragraph, whole (a
  table's rows are fixed once a paragraph uses it). }
function TTyRichFragment.MapCell(ACell: TTyRichCell): TTyRichCell;
var
  src, nt: TTyRichTable;
  r: TTyRichRow;
  i: Integer;
begin
  Result := ACell;
  if ACell = nil then Exit;
  src := ACell.Table;
  i := FTabCount - 1;
  while (i >= 0) and (FTabSrc[i] <> src) do Dec(i);
  if i < 0 then
  begin
    nt := src;
    { A table with a row that holds a nested table goes in as its paragraphs: what
      made the inner table one is only in the bytes of the source's file, and in this
      document such a row could neither be saved nor edited. }
    for i := 0 to High(src.FRows) do
      if src.FRows[i].FHoldsNestedTable then nt := nil;
    if FTabCount = Length(FTabSrc) then
    begin
      SetLength(FTabSrc, FTabCount * 2 + 4);
      SetLength(FTabNew, FTabCount * 2 + 4);
    end;
    if (nt <> nil) and (FFilter <> nil) then
    begin
      nt := TTyRichTable.Create(src.FColBoundaries, src.FStructureLocked);
      { held while the fragment is made (Create lets go of it at its end) - entered first, so
        that a failure while its rows are made (out of memory, the filter's) lets go of it too }
      nt.AddRef;
      FTabSrc[FTabCount] := src;
      FTabNew[FTabCount] := nt;
      Inc(FTabCount);
      for i := 0 to High(src.FRows) do
      begin
        r := src.FRows[i];
        nt.AddRow(Length(r.FCells), FFilter.RowFormat(r.FRawFormat), r.FBoundaries,
          r.FHoldsNestedTable);
      end;
    end
    else
    begin
      FTabSrc[FTabCount] := src;
      FTabNew[FTabCount] := nt;
      Inc(FTabCount);
    end;
    i := FTabCount - 1;
  end
  else if i < FTabCount - 1 then
  begin
    // the table met last first: a table's paragraphs follow each other
    src := FTabSrc[i];
    nt := FTabNew[i];
    FTabSrc[i] := FTabSrc[FTabCount - 1];
    FTabNew[i] := FTabNew[FTabCount - 1];
    FTabSrc[FTabCount - 1] := src;
    FTabNew[FTabCount - 1] := nt;
    i := FTabCount - 1;
  end;
  nt := FTabNew[i];
  if nt = nil then Exit(nil);
  if nt = ACell.Table then Exit;
  Result := nt.FRows[ACell.FRow.FIndex].FCells[ACell.FIndex];
end;

function Utf8SeqLen(B: Byte): Integer; inline;
begin
  if B < $C0 then Result := 1
  else if B < $E0 then Result := 2
  else if B < $F0 then Result := 3
  else Result := 4;
end;

{ The paragraph's objects through the filter: one kept or made again stays its character; one
  left out gives its character's place to the text the filter has for it (or to nothing). }
procedure TTyRichFragment.MapObjects(var AText: RawByteString; var ARuns: TTyRunArray;
  var AChars: Int64);
var
  j, n: Integer;
  p, q: PtrInt;
  ch, runEnd, outCh: Int64;
  got: TTyRichObject;
  s: UTF8String;
  o: RawByteString;
  runs: TTyRunArray;
begin
  o := '';
  runs := nil;
  SetLength(runs, Length(ARuns));
  n := 0;
  p := 1;
  ch := 0;
  outCh := 0;
  for j := 0 to High(ARuns) do
  begin
    if j < High(ARuns) then runEnd := ARuns[j + 1].Start else runEnd := AChars;
    if ARuns[j].Obj = nil then
    begin
      AppendRun(runs, n, outCh, ARuns[j].Format, nil);
      q := p;
      while (ch < runEnd) and (q <= Length(AText)) do
      begin
        Inc(q, Utf8SeqLen(Byte(AText[q])));
        Inc(ch);
        Inc(outCh);
      end;
      if q > Length(AText) + 1 then q := Length(AText) + 1;
      o := o + Copy(AText, p, q - p);
      p := q;
      Continue;
    end;
    // an object run is its one character
    q := p;
    if (ch < runEnd) and (q <= Length(AText)) then
    begin
      Inc(q, Utf8SeqLen(Byte(AText[q])));
      if q > Length(AText) + 1 then q := Length(AText) + 1;
      Inc(ch);
    end;
    got := FFilter.MapObject(ARuns[j].Obj, s);
    if got <> nil then
    begin
      AppendRun(runs, n, outCh, ARuns[j].Format, got);
      o := o + Copy(AText, p, q - p);
      Inc(outCh);
    end
    else if s <> '' then
    begin
      AppendRun(runs, n, outCh, ARuns[j].Format, nil);
      o := o + s;
      q := 1;
      while q <= Length(s) do
      begin
        Inc(q, Utf8SeqLen(Byte(s[q])));
        Inc(outCh);
      end;
    end;
    p := q;
    // (a run that held more than its one character: the rest as text)
    if (ch < runEnd) and (p <= Length(AText)) then
      AppendRun(runs, n, outCh, ARuns[j].Format, nil);
    while (ch < runEnd) and (p <= Length(AText)) do
    begin
      q := p + Utf8SeqLen(Byte(AText[p]));
      if q > Length(AText) + 1 then q := Length(AText) + 1;
      o := o + Copy(AText, p, q - p);
      p := q;
      Inc(ch);
      Inc(outCh);
    end;
  end;
  if n = 0 then AppendRun(runs, n, 0, ARuns[0].Format, nil);
  SetLength(runs, n);
  AText := o;
  ARuns := runs;
  AChars := outCh;
end;

procedure TTyRichFragment.TakePara(AIndex: Integer; AData: Pointer; AText: PByte; ALen: PtrInt;
  var AContinue: Boolean);
var
  fmt: TTyParaFormatId;
  runs, mapped: TTyRunArray;
  cell: TTyRichCell;
  n, j: Integer;
  chars: Int64;
  txt: RawByteString;
  objs: Boolean;
begin
  // a paragraph of a reader that parses on demand with no value of the moment: parse it
  if not FSrc.ReadValue(AData, fmt, runs, cell) then
    FSrc.ReadValue(FSrc.DataOf(AIndex), fmt, runs, cell);
  chars := FSrc.FText.ParaLength(AIndex);
  objs := False;
  if FFilter <> nil then
    for j := 0 to High(runs) do
      if runs[j].Obj <> nil then
      begin
        objs := True;
        Break;
      end;
  if objs then
  begin
    txt := '';
    SetLength(txt, ALen);
    if ALen > 0 then Move(AText^, txt[1], ALen);
    MapObjects(txt, runs, chars);
  end;
  mapped := nil;
  n := 0;
  SetLength(mapped, Length(runs));
  for j := 0 to High(runs) do
    AppendRun(mapped, n, runs[j].Start, MapChar(runs[j].Format), runs[j].Obj);
  SetLength(mapped, n);
  if FFlat then cell := FFlatCell else cell := MapCell(cell);
  if objs then AddText(PByte(PAnsiChar(txt)), Length(txt))
  else AddText(AText, ALen);
  AddPart(FDoc.MakeData(MapPara(fmt), mapped, cell), chars, False);
end;

type
  // the fragment's parts between its first and last into the paragraphs the insert made
  TTyRichFragmentWalk = class
  public
    Doc: TTyRichDocument;
    Fragment: TTyRichFragment;
    First: Integer;
    function Map(AIndex: Integer; AData: Pointer): Pointer;
  end;

function TTyRichFragmentWalk.Map(AIndex: Integer; AData: Pointer): Pointer;
var
  v: TTyRichParaData;
begin
  v := Fragment.FParts[AIndex - First];
  if Pointer(v) <> AData then
  begin
    Doc.AcquireData(v);
    Doc.ReleaseData(TTyRichParaData(AData));
  end;
  Result := v;
end;

function TTyRichDocument.InsertFragment(APos: TTyRichPos;
  AFragment: TTyRichFragment): TTyRichUndoData;
var
  c: TTyRichChange;
  k, s, n1, n2, last: Integer;
  d, part: TTyRichParaData;
  r, pr, runs1, runs2: TTyRunArray;
  ps, o, len, plen, added, oldChars: Int64;
  f: TTyCharFormatId;
  fmt: TTyParaFormatId;
  cell: TTyRichCell;
  oldCount: Integer;
  txt: UTF8String;
  w: TTyRichFragmentWalk;
begin
  if AFragment = nil then
    raise ETyRichModel.Create('InsertFragment needs a fragment');
  if AFragment.FDoc <> Self then
    raise ETyRichModel.Create('The fragment was made for another document');
  c := Default(TTyRichChange);
  c.Pos := APos;
  FText.ParaOfPos(APos);   // range check before anything changes
  if AFragment.FCount = 0 then Exit(NewUndo(c));
  if ChangeRefused(APos, 0) then raise NestedRowRefused;
  if AFragment.FHavePieces then txt := '' else txt := WithBreaks(AFragment.FText, FDominantLineBreak);
  k := FText.ParaOfPos(APos);
  d := DataOf(k);
  r := RunsOfData(d);
  ps := FText.ParaStart(k);
  o := APos - ps;
  len := FText.ParaLength(k);
  f := InheritedFormat(r, o);
  fmt := FormatOfData(d);
  cell := CellOfData(d);
  last := AFragment.FCount - 1;
  oldChars := FText.Length;
  oldCount := FText.ParaCount;
  Result := NewUndo(c);
  try
    Result.FFirstPara := k;
    Result.AddOld(d);
    Result.SealOld;
    Result.FSpan := FText.PieceSpan(APos, APos);
    if AFragment.FHavePieces then
    begin
      // again (a redo): the very bytes of the first insert, still in the add buffer
      Inc(FEditing);
      try
        FText.RestorePieces(APos, AFragment.FPieces);
      finally
        Dec(FEditing);
      end;
    end
    else if txt <> '' then
    begin
      Inc(FEditing);
      try
        FText.Insert(APos, txt);
        // (taken before any paragraph value is put: the separators hand out no data)
        AFragment.FPieces := FText.PieceSnapshot(APos, FText.Length - oldChars);
        AFragment.FHavePieces := True;
        // the text itself is no longer needed (its bytes are counted still: MemSize)
        AFragment.FTextBytes := Length(AFragment.FText);
        AFragment.FText := '';
      finally
        Dec(FEditing);
      end;
    end;
    added := FText.Length - oldChars;
    s := FText.ParaCount - oldCount;
    if s <> last then
      raise ETyRichModel.CreateFmt('A fragment of %d parts made %d paragraphs', [last + 1, s + 1]);
    runs1 := nil;
    n1 := 0;
    // the text before APos keeps its runs
    AppendSlice(runs1, n1, r, len, 0, o, 0);
    part := AFragment.FParts[0];
    plen := AFragment.FLens[0];
    if not AFragment.FOwn[0] then
    begin
      pr := RunsOfData(part);
      AppendSlice(runs1, n1, pr, plen, 0, plen, o);
      if n1 = 0 then AppendRun(runs1, n1, 0, pr[0].Format, nil);
    end;
    if last = 0 then
    begin
      // inline: one paragraph, its own format and cell, the text after APos follows
      AppendSlice(runs1, n1, r, len, o, len, plen);
      if n1 = 0 then AppendRun(runs1, n1, 0, f, nil);
      SetLength(runs1, n1);
      PutData(k, d, MakeDataLike(fmt, runs1, cell, d));
    end
    else
    begin
      if n1 = 0 then AppendRun(runs1, n1, 0, f, nil);
      SetLength(runs1, n1);
      // the paragraph that ends with the fragment's first mark has that paragraph's format
      if AFragment.FOwn[0] then PutData(k, d, MakeDataLike(fmt, runs1, cell, d))
      // (a format of the fragment: not the file's list marker of the paragraph it was)
      else PutData(k, d, MakeData(FormatOfData(part), runs1, CellOfData(part)));
      if last > 1 then
      begin
        w := TTyRichFragmentWalk.Create;
        try
          w.Doc := Self;
          w.Fragment := AFragment;
          w.First := k;
          FText.MapParaData(k + 1, k + last - 1, @w.Map);
        finally
          w.Free;
        end;
      end;
      // the last part and the text after APos: this document's mark, its format and cell
      runs2 := nil;
      n2 := 0;
      part := AFragment.FParts[last];
      plen := AFragment.FLens[last];
      if not AFragment.FOwn[last] then
        AppendSlice(runs2, n2, RunsOfData(part), plen, 0, plen, 0);
      AppendSlice(runs2, n2, r, len, o, len, plen - o);
      if n2 = 0 then
      begin
        if AFragment.FOwn[last] then AppendRun(runs2, n2, 0, f, nil)
        else AppendRun(runs2, n2, 0, RunsOfData(part)[0].Format, nil);
      end;
      SetLength(runs2, n2);
      PutData(k + last, SlotData(k + last), MakeData(fmt, runs2, cell));
    end;
  except
    Result.Free;
    raise;
  end;
  c.Kinds := [rckText];
  if s > 0 then c.Kinds := c.Kinds + [rckStructure, rckFormat];
  c.NewLen := added;
  Result.FInserted := added;
  c.FirstPara := k;
  c.OldParaCount := 1;
  c.NewParaCount := 1 + s;
  Result.FChange := c;
  Notify(c);
end;

procedure TTyRichDocument.Revert(var AUndo: TTyRichUndoData);
var
  u: TTyRichUndoData;
  c: TTyRichChange;
  i, total: Integer;
  w: TTyRichRevertWalk;
begin
  u := AUndo;
  if u = nil then Exit;
  if u.FDoc <> Self then
    raise ETyRichModel.Create('Undo data of another document');
  AUndo := nil;
  try
    Inc(FEditing);
    try
      if u.FSwapCount > 0 then RevertSwaps(u);
      if u.FInserted > 0 then
        FText.Delete(u.FChange.Pos, u.FInserted);
      if u.FRemoved.CharCount > 0 then
      begin
        // the restored separators put these values back in slots: the slots' references
        for i := 0 to High(u.FRemoved.Pieces) do
          if (u.FRemoved.Pieces[i].Separator <> rsNone) and (u.FRemoved.Pieces[i].Data <> nil) then
            AcquireData(TTyRichParaData(u.FRemoved.Pieces[i].Data));
        FText.RestorePieces(u.FChange.Pos, u.FRemoved);
      end;
      { The text is what it was where the change split it: its pieces too (a decoded lazy
        paragraph lazy again). }
      if (Length(u.FSpan2.Pieces.Pieces) > 0) or u.FSpan2.LazyTail then FText.RestoreSpan(u.FSpan2);
      if (Length(u.FSpan.Pieces.Pieces) > 0) or u.FSpan.LazyTail then FText.RestoreSpan(u.FSpan);
      if u.FOldCount > 0 then
      begin
        total := 0;
        for i := 0 to u.FOldCount - 1 do Inc(total, u.FOldData[i].Count);
        w := TTyRichRevertWalk.Create;
        try
          w.Doc := Self;
          w.Undo := u;
          w.Run := 0;
          w.Left := u.FOldData[0].Count;
          FText.MapParaData(u.FFirstPara, u.FFirstPara + total - 1, @w.Map);
        finally
          w.Free;
        end;
      end;
    finally
      Dec(FEditing);
    end;
    if u.FChange.Kinds <> [] then
    begin
      c := u.FChange;
      c.OldLen := u.FChange.NewLen;
      c.NewLen := u.FChange.OldLen;
      c.OldParaCount := u.FChange.NewParaCount;
      c.NewParaCount := u.FChange.OldParaCount;
      Notify(c);
    end;
  finally
    u.Free;
  end;
end;

{ ---- TTyRichCommand ---- }

destructor TTyRichCommand.Destroy;
begin
  FreeRecords;
  inherited Destroy;
end;

procedure TTyRichCommand.Covered;
begin
end;

procedure TTyRichCommand.FreeRecords;
begin
  while FRecordCount > 0 do
  begin
    Dec(FRecordCount);
    FRecords[FRecordCount].Free;
    FRecords[FRecordCount] := nil;
  end;
  FRecords := nil;
end;

procedure TTyRichCommand.CheckRunning(ADoc: TTyRichDocument);
begin
  // the guarantee that every change is in the history: a command changes a document only
  // while that document runs it
  if (ADoc = nil) or (FDoc <> ADoc) then
    raise ETyRichModel.CreateFmt('%s changes a document only while the document runs it',
      [ClassName]);
end;

procedure TTyRichCommand.AddSummary(const AChange: TTyRichChange);
begin
  ComposeChange(FSummary, FChanged, AChange);
end;

procedure TTyRichCommand.ResetSummary;
begin
  FSummary := Default(TTyRichChange);
  FChanged := False;
end;

function TTyRichCommand.Keep(AUndo: TTyRichUndoData): TTyRichChange;
begin
  Result := AUndo.Change;
  if Result.Kinds = [] then
  begin
    // a no-op: nothing to put back
    AUndo.Free;
    Exit;
  end;
  if FRecordCount = Length(FRecords) then SetLength(FRecords, FRecordCount * 2 + 2);
  FRecords[FRecordCount] := AUndo;
  Inc(FRecordCount);
  AddSummary(Result);
end;

procedure TTyRichCommand.DoUndo(ADoc: TTyRichDocument);
begin
  // newest first: each record was made on the document the later ones changed again
  while FRecordCount > 0 do
  begin
    Dec(FRecordCount);
    ADoc.Revert(FRecords[FRecordCount]);
  end;
end;

procedure TTyRichCommand.DoRedo(ADoc: TTyRichDocument);
begin
  DoExecute(ADoc);
end;

function TTyRichCommand.InsertText(ADoc: TTyRichDocument; APos: TTyRichPos;
  const AText: UTF8String; AFormat: TTyCharFormatId): TTyRichChange;
begin
  CheckRunning(ADoc);
  Result := Keep(ADoc.InsertText(APos, AText, AFormat));
end;

function TTyRichCommand.InsertObject(ADoc: TTyRichDocument; APos: TTyRichPos;
  AObject: TTyRichObject; AFormat: TTyCharFormatId): TTyRichChange;
begin
  CheckRunning(ADoc);
  Result := Keep(ADoc.InsertObject(APos, AObject, AFormat));
end;

function TTyRichCommand.DeleteRange(ADoc: TTyRichDocument; APos, ALen: TTyRichPos): TTyRichChange;
begin
  CheckRunning(ADoc);
  Result := Keep(ADoc.DeleteRange(APos, ALen));
end;

function TTyRichCommand.ApplyCharFormat(ADoc: TTyRichDocument; APos, ALen: TTyRichPos;
  AMask: TTyCharFormatMask; const AValue: TTyCharFormat;
  AKeepNone: TTyCharFormatMask): TTyRichChange;
begin
  CheckRunning(ADoc);
  Result := Keep(ADoc.ApplyCharFormat(APos, ALen, AMask, AValue, AKeepNone));
end;

function TTyRichCommand.ApplyParaFormat(ADoc: TTyRichDocument; AFirstPara, ALastPara: Integer;
  AMask: TTyParaFormatMask; const AValue: TTyParaFormat): TTyRichChange;
begin
  CheckRunning(ADoc);
  Result := Keep(ADoc.ApplyParaFormat(AFirstPara, ALastPara, AMask, AValue));
end;

function TTyRichCommand.MarkTable(ADoc: TTyRichDocument; AFirstPara: Integer;
  ATable: TTyRichTable; const ACellParas: array of Integer): TTyRichChange;
begin
  CheckRunning(ADoc);
  Result := Keep(ADoc.MarkTable(AFirstPara, ATable, ACellParas));
end;

function TTyRichCommand.InsertFragment(ADoc: TTyRichDocument; APos: TTyRichPos;
  AFragment: TTyRichFragment): TTyRichChange;
begin
  CheckRunning(ADoc);
  Result := Keep(ADoc.InsertFragment(APos, AFragment));
end;

function TTyRichCommand.ReplaceInParas(ADoc: TTyRichDocument; const APos: array of TTyRichPos;
  AFrom, ACount: Integer; ALen: TTyRichPos; const AText: UTF8String;
  out ASkipped: Integer): TTyRichChange;
begin
  CheckRunning(ADoc);
  Result := Keep(ADoc.ReplaceInParas(APos, AFrom, ACount, ALen, AText, ASkipped));
end;

procedure TTyRichCommand.DoContinue(ADoc: TTyRichDocument);
begin
  raise ETyRichModel.CreateFmt('%s does not go on in parts', [ClassName]);
end;

function TTyRichCommand.RecordsSize(AFrom: Integer): Int64;
var
  i: Integer;
begin
  Result := 0;
  if AFrom < 0 then AFrom := 0;
  for i := AFrom to FRecordCount - 1 do Inc(Result, FRecords[i].MemSize);
end;

procedure TTyRichCommand.AdoptChange(AChild: TTyRichCommand);
begin
  if AChild.FChanged then AddSummary(AChild.FSummary);
end;

procedure TTyRichCommand.ExecuteChild(ADoc: TTyRichDocument; AChild: TTyRichCommand);
begin
  CheckRunning(ADoc);
  AChild.FreeRecords;
  AChild.ResetSummary;
  AChild.FDoc := ADoc;
  try
    try
      AChild.DoExecute(ADoc);
    except
      // what the child did so far goes back before the error travels on
      try
        AChild.DoUndo(ADoc);
      except
      end;
      raise;
    end;
  finally
    AChild.FDoc := nil;
  end;
  AdoptChange(AChild);
end;

procedure TTyRichCommand.UndoChild(ADoc: TTyRichDocument; AChild: TTyRichCommand);
begin
  CheckRunning(ADoc);
  AChild.FDoc := ADoc;
  try
    AChild.DoUndo(ADoc);
  finally
    AChild.FDoc := nil;
  end;
  // records a DoUndo override left are stale: redo runs the child again
  AChild.FreeRecords;
end;

procedure TTyRichCommand.RedoChild(ADoc: TTyRichDocument; AChild: TTyRichCommand);
begin
  CheckRunning(ADoc);
  AChild.FreeRecords;
  AChild.ResetSummary;
  AChild.FDoc := ADoc;
  try
    try
      AChild.DoRedo(ADoc);
    except
      try
        AChild.DoUndo(ADoc);
      except
      end;
      raise;
    end;
  finally
    AChild.FDoc := nil;
  end;
  AdoptChange(AChild);
end;

procedure TTyRichCommand.TakeOver(ANext: TTyRichCommand);
var
  i: Integer;
begin
  for i := 0 to ANext.FRecordCount - 1 do
  begin
    if FRecordCount = Length(FRecords) then SetLength(FRecords, FRecordCount * 2 + 2);
    FRecords[FRecordCount] := ANext.FRecords[i];
    Inc(FRecordCount);
    ANext.FRecords[i] := nil;
  end;
  ANext.FRecordCount := 0;
  AdoptChange(ANext);
  // the merged step ends where ANext left the view (it begins where this one began)
  FMarks.HasAfter := ANext.FMarks.HasAfter;
  FMarks.After := ANext.FMarks.After;
end;

function TTyRichCommand.CanExecute(ADoc: TTyRichDocument): Boolean;
begin
  Result := True;
end;

function TTyRichCommand.TryMerge(ANext: TTyRichCommand): Boolean;
begin
  Result := False;
end;

function TTyRichCommand.Description: string;
begin
  Result := rsRichUndoEdit;
end;

function TTyRichCommand.ChangedRange: TTyRichRange;
begin
  Result.Pos := FSummary.Pos;
  Result.Len := FSummary.NewLen;
end;

function TTyRichCommand.MemSize: Int64;
var
  i: Integer;
begin
  Result := InstanceSize + Length(FRecords) * SizeOf(Pointer);
  for i := 0 to FRecordCount - 1 do Inc(Result, FRecords[i].MemSize);
end;

procedure TTyRichCommand.GatherObjects(var AList: TTyRichObjectList; var ACount: Integer);
var
  i: Integer;
begin
  for i := 0 to FRecordCount - 1 do FRecords[i].GatherObjects(AList, ACount);
end;

{ ---- the history's objects ---- }

{ AEntry's command's objects, each distinct one held once by this step; an object no other
  step held yet adds its bytes to the history's. Sorted by address to find the distinct ones:
  no walk of the other steps. }
{ AList[0..ACount) sorted by address and its duplicates gone: the distinct count. }
function SortDistinct(var AList: TTyRichObjectList; ACount: Integer): Integer;
var
  i, j: Integer;
  t: TTyRichObject;
begin
  // insertion sort of the few, merge-free: steps hold few objects as a rule
  if ACount > 1 then
    if ACount <= 32 then
    begin
      for i := 1 to ACount - 1 do
      begin
        t := AList[i];
        j := i;
        while (j > 0) and (PtrUInt(AList[j - 1]) > PtrUInt(t)) do
        begin
          AList[j] := AList[j - 1];
          Dec(j);
        end;
        AList[j] := t;
      end;
    end
    else
      SortObjects(AList, 0, ACount - 1);
  Result := 0;
  for i := 0 to ACount - 1 do
    if (Result = 0) or (AList[Result - 1] <> AList[i]) then
    begin
      AList[Result] := AList[i];
      Inc(Result);
    end;
end;

procedure TTyRichDocument.BeginGather(const ASkip: array of Int64);
var
  i: Integer;
begin
  if FKeyMet = nil then FKeyMet := TTyRichKeySet.Create else FKeyMet.Clear;
  for i := 0 to High(ASkip) do FKeyMet.AddOrSetValue(ASkip[i], True);
  FGatherKeys := nil;
  FGatherKeyCount := 0;
  FGathering := True;
end;

function TTyRichDocument.EndGather: TTyRichKeyList;
begin
  FGathering := False;
  Result := FGatherKeys;
  SetLength(Result, FGatherKeyCount);
  FGatherKeys := nil;
  FGatherKeyCount := 0;
end;

function TTyRichDocument.MeetKey(AKey: Int64): Boolean;
begin
  Result := not FKeyMet.ContainsKey(AKey);
  if not Result then Exit;
  FKeyMet.Add(AKey, True);
  if FGatherKeyCount = Length(FGatherKeys) then SetLength(FGatherKeys, FGatherKeyCount * 2 + 4);
  FGatherKeys[FGatherKeyCount] := AKey;
  Inc(FGatherKeyCount);
end;

procedure TTyRichDocument.HoldObjects(var AEntry: TTyRichHistoryEntry);
var
  list: TTyRichObjectList;
  n, i, k, c: Integer;
begin
  list := nil;
  n := 0;
  // (values that share a key - a merged run of typing's - are walked once)
  BeginGather([]);
  try
    AEntry.Cmd.GatherObjects(list, n);
  finally
    AEntry.Keys := EndGather;
  end;
  k := SortDistinct(list, n);
  SetLength(list, k);
  AEntry.Objs := list;
  if FObjHolds = nil then FObjHolds := TTyRichObjHolds.Create;
  for i := 0 to k - 1 do
  begin
    if FObjHolds.TryGetValue(list[i], c) then
      FObjHolds[list[i]] := c + 1
    else
    begin
      FObjHolds.Add(list[i], 1);
      Inc(FHistoryBytes, list[i].DataBytes);
    end;
  end;
end;

procedure TTyRichDocument.HoldMore(var AEntry: TTyRichHistoryEntry;
  var AList: TTyRichObjectList; ACount: Integer; const AKeys: TTyRichKeyList);
var
  k, i, j, m, c: Integer;
  merged: TTyRichObjectList;
begin
  if Length(AKeys) > 0 then
  begin
    m := Length(AEntry.Keys);
    SetLength(AEntry.Keys, m + Length(AKeys));
    for i := 0 to High(AKeys) do AEntry.Keys[m + i] := AKeys[i];
  end;
  if ACount = 0 then Exit;
  k := SortDistinct(AList, ACount);
  if FObjHolds = nil then FObjHolds := TTyRichObjHolds.Create;
  // both sorted: one pass merges the new ones in, each held by this step once
  merged := nil;
  SetLength(merged, Length(AEntry.Objs) + k);
  i := 0;
  j := 0;
  m := 0;
  while (i < Length(AEntry.Objs)) or (j < k) do
    if (j >= k) or ((i < Length(AEntry.Objs)) and
      (PtrUInt(AEntry.Objs[i]) <= PtrUInt(AList[j]))) then
    begin
      // (one the step holds already: once)
      if (j < k) and (AEntry.Objs[i] = AList[j]) then Inc(j);
      merged[m] := AEntry.Objs[i];
      Inc(m);
      Inc(i);
    end
    else
    begin
      merged[m] := AList[j];
      Inc(m);
      if FObjHolds.TryGetValue(AList[j], c) then
        FObjHolds[AList[j]] := c + 1
      else
      begin
        FObjHolds.Add(AList[j], 1);
        Inc(FHistoryBytes, AList[j].DataBytes);
      end;
      Inc(j);
    end;
  SetLength(merged, m);
  AEntry.Objs := merged;
end;

{ The step lets go of its objects: one no step holds any more leaves the history's bytes.
  Before the step's command is freed (the address must still be that object). }
procedure TTyRichDocument.LetGoObjects(var AEntry: TTyRichHistoryEntry);
var
  i, c: Integer;
begin
  for i := 0 to High(AEntry.Objs) do
    if (FObjHolds <> nil) and FObjHolds.TryGetValue(AEntry.Objs[i], c) then
      if c > 1 then
        FObjHolds[AEntry.Objs[i]] := c - 1
      else
      begin
        FObjHolds.Remove(AEntry.Objs[i]);
        Dec(FHistoryBytes, AEntry.Objs[i].DataBytes);
      end;
  AEntry.Objs := nil;
  AEntry.Keys := nil;
end;

{ ---- TTyRichDocument: commands and the history ---- }

function TTyRichDocument.NewState: Int64;
begin
  Result := FNextState;
  Inc(FNextState);
end;

function TTyRichDocument.GetModified: Boolean;
begin
  Result := FState <> FSavedState;
end;

procedure TTyRichDocument.SetModified(AValue: Boolean);
begin
  if AValue then
    FSavedState := -1
  else
  begin
    FSavedState := FState;
    { Typing merged into the step that led here would carry the step's "after" past this
      content: an undo could not come back to it. }
    FMergeBroken := True;
  end;
  NoteModified;
end;

procedure TTyRichDocument.LeftHistory;
begin
  FState := NewState;
  FSavedState := -1;
end;

procedure TTyRichDocument.NoteModified;
var
  m: Boolean;
begin
  m := GetModified;
  if m = FModifiedSeen then Exit;
  FModifiedSeen := m;
  if Assigned(FOnModifiedChange) then FOnModifiedChange(Self);
end;

procedure TTyRichDocument.CheckIdle(const AWhat: string);
begin
  if FRunning <> nil then
    raise ETyRichModel.CreateFmt('%s while a command runs', [AWhat]);
end;

{ The end of a stretch the changes were held in (a command's run, an update block): what is
  pending is reported, then the edge (OnUpdatingEnd) - also after a report that raised. }
procedure TTyRichDocument.Flush;
var
  c: TTyRichChange;
begin
  if (FHold > 0) or (FUpdateCount > 0) then Exit;
  try
    if FHasPending then
    begin
      c := FPending;
      FHasPending := False;
      FPending := Default(TTyRichChange);
      if Assigned(FOnChange) then FOnChange(Self, c);
    end;
  finally
    // (a handler of the report may have begun an update)
    if Assigned(FOnUpdatingEnd) and not Updating then FOnUpdatingEnd(Self);
  end;
end;

{ Runs one step of ACmd with the notifications held; a failed execute or redo is reverted
  before the error travels on. }
procedure TTyRichDocument.RunStep(ACmd: TTyRichCommand; AStep: Integer);
begin
  Inc(FHold);
  FRunning := ACmd;
  ACmd.FDoc := Self;
  try
    if AStep = StepUndo then
    begin
      ACmd.DoUndo(Self);
      ACmd.FreeRecords;
    end
    else
    begin
      ACmd.FreeRecords;
      ACmd.ResetSummary;
      try
        if AStep = StepExecute then ACmd.DoExecute(Self) else ACmd.DoRedo(Self);
      except
        try
          ACmd.DoUndo(Self);
        except
        end;
        raise;
      end;
    end;
  finally
    ACmd.FDoc := nil;
    FRunning := nil;
    Dec(FHold);
  end;
end;

procedure TTyRichDocument.PushUndo(ACmd: TTyRichCommand);
var
  e: TTyRichHistoryEntry;
begin
  if FUndoCount > 0 then FUndo[FUndoCount - 1].Cmd.Covered;
  e := Default(TTyRichHistoryEntry);
  e.Cmd := ACmd;
  e.Bytes := ACmd.MemSize;
  HoldObjects(e);
  if FUndoCount = Length(FUndo) then SetLength(FUndo, FUndoCount * 2 + 8);
  FUndo[FUndoCount] := e;
  Inc(FUndoCount);
  Inc(FHistoryBytes, e.Bytes);
end;

procedure TTyRichDocument.DropOldestUndo;
var
  i: Integer;
begin
  Dec(FHistoryBytes, FUndo[0].Bytes);
  LetGoObjects(FUndo[0]);
  FUndo[0].Cmd.Free;
  for i := 1 to FUndoCount - 1 do FUndo[i - 1] := FUndo[i];
  Dec(FUndoCount);
end;

procedure TTyRichDocument.ClearRedo;
begin
  while FRedoCount > 0 do
  begin
    Dec(FRedoCount);
    Dec(FHistoryBytes, FRedo[FRedoCount].Bytes);
    LetGoObjects(FRedo[FRedoCount]);
    FRedo[FRedoCount].Cmd.Free;
  end;
end;

procedure TTyRichDocument.ClearHistory;
begin
  ClearRedo;
  while FUndoCount > 0 do
  begin
    Dec(FUndoCount);
    Dec(FHistoryBytes, FUndo[FUndoCount].Bytes);
    LetGoObjects(FUndo[FUndoCount]);
    FUndo[FUndoCount].Cmd.Free;
  end;
  while FBlockCount > 0 do
  begin
    Dec(FBlockCount);
    FBlock[FBlockCount].Free;
  end;
  FUndo := nil;
  FRedo := nil;
  FBlock := nil;
  FHistoryBytes := 0;
  if FObjHolds <> nil then FObjHolds.Clear;
end;

procedure TTyRichDocument.TrimHistory;
begin
  // the newest step always stays, however big
  while (FMaxUndoBytes > 0) and (FHistoryBytes > FMaxUndoBytes) and (FUndoCount > 1) do
    DropOldestUndo;
end;

procedure TTyRichDocument.SetMaxUndoBytes(AValue: Int64);
begin
  FMaxUndoBytes := AValue;
  TrimHistory;
end;

function TTyRichDocument.Execute(ACmd: TTyRichCommand): Boolean;
var
  ok: Boolean;
  top: TTyRichCommand;
  list: TTyRichObjectList;
  n: Integer;
  keys: TTyRichKeyList;
begin
  if ACmd = nil then
    raise ETyRichModel.Create('Execute needs a command');
  try
    CheckIdle('Execute');
    // a document still loading (or cut short) is read-only, and so is one being saved: the
    // save's plan holds paragraph indices
    ok := not FLoadingContent and not FIncomplete and (FSaving = 0) and ACmd.CanExecute(Self);
  except
    ACmd.Free;
    raise;
  end;
  if not ok then
  begin
    ACmd.Free;
    Exit(False);
  end;
  Result := True;
  try
    RunStep(ACmd, StepExecute);
  except
    ACmd.Free;
    Flush;
    raise;
  end;
  if not ACmd.Changed then
  begin
    ACmd.Free;
    // nothing to report; the run's hold ended all the same
    Flush;
    Exit;
  end;
  // a content of its own; a merged step takes the new "after" (below)
  ACmd.FStateBefore := FState;
  FState := NewState;
  ACmd.FStateAfter := FState;
  if FUpdateCount > 0 then
  begin
    if FBlockCount = Length(FBlock) then SetLength(FBlock, FBlockCount * 2 + 4);
    FBlock[FBlockCount] := ACmd;
    Inc(FBlockCount);
    Exit;
  end;
  ClearRedo;
  // typing merges as the Memo's undo stack does: not across BreakMerge, Undo or Redo
  if (not FMergeBroken) and (FUndoCount > 0) then
  begin
    top := FUndo[FUndoCount - 1].Cmd;
    if top.ClassType = ACmd.ClassType then
    begin
      { The kinds that merge (typing, a replace's batches): what ACmd brings is gathered
        while its records are its own, past the values the step holds already (their keys) -
        a merged keystroke beside a paragraph's pictures walks none of them. }
      list := nil;
      n := 0;
      BeginGather(FUndo[FUndoCount - 1].Keys);
      try
        ACmd.GatherObjects(list, n);
      finally
        keys := EndGather;
      end;
      if top.TryMerge(ACmd) then
      begin
        top.FStateAfter := ACmd.FStateAfter;
        ACmd.Free;
        Dec(FHistoryBytes, FUndo[FUndoCount - 1].Bytes);
        FUndo[FUndoCount - 1].Bytes := top.MemSize;
        Inc(FHistoryBytes, FUndo[FUndoCount - 1].Bytes);
        ACmd := nil;
        HoldMore(FUndo[FUndoCount - 1], list, n, keys);
      end;
    end
    else
    begin
      // (another merge: the step's objects let go first, held again with ANext's)
      LetGoObjects(FUndo[FUndoCount - 1]);
      if top.TryMerge(ACmd) then
      begin
        top.FStateAfter := ACmd.FStateAfter;
        ACmd.Free;
        Dec(FHistoryBytes, FUndo[FUndoCount - 1].Bytes);
        FUndo[FUndoCount - 1].Bytes := top.MemSize;
        Inc(FHistoryBytes, FUndo[FUndoCount - 1].Bytes);
        ACmd := nil;
      end;
      HoldObjects(FUndo[FUndoCount - 1]);
    end;
  end;
  if ACmd <> nil then PushUndo(ACmd);
  FMergeBroken := False;
  TrimHistory;
  Flush;
  NoteModified;
end;

function TTyRichDocument.ExecutePart(ACmd: TTyRichCommand): Boolean;
var
  top, n0, cnt, i: Integer;
  list: TTyRichObjectList;
  keys: TTyRichKeyList;
  ok, lost: Boolean;
begin
  Result := False;
  if ACmd = nil then raise ETyRichModel.Create('ExecutePart needs a command');
  CheckIdle('ExecutePart');
  if (FUpdateCount > 0) or FLoadingContent or FIncomplete or (FSaving > 0) then Exit;
  if (FUndoCount = 0) or (FUndo[FUndoCount - 1].Cmd <> ACmd) or (FRedoCount > 0) then Exit;
  // the content it left, and no saved point set on it since
  if (FState <> ACmd.FStateAfter) or (FSavedState = FState) then Exit;
  top := FUndoCount - 1;
  n0 := ACmd.FRecordCount;
  ok := False;
  lost := False;
  Inc(FHold);
  FRunning := ACmd;
  ACmd.FDoc := Self;
  try
    ACmd.DoContinue(Self);
    ok := True;
  finally
    if not ok then
      // what the part did goes back, newest first: the step is as it was
      try
        while ACmd.FRecordCount > n0 do
        begin
          Dec(ACmd.FRecordCount);
          Revert(ACmd.FRecords[ACmd.FRecordCount]);
        end;
      except
        lost := True;
      end;
    ACmd.FDoc := nil;
    FRunning := nil;
    Dec(FHold);
    if not ok then
    begin
      if lost then
      begin
        // the document no longer matches the history: drop it all
        ClearHistory;
        LeftHistory;
      end;
      Flush;
      NoteModified;
    end;
  end;
  Result := True;
  if ACmd.FRecordCount > n0 then
  begin
    FState := NewState;
    ACmd.FStateAfter := FState;
    // what the part brought joins the step: its bytes, the objects its records hold
    Dec(FHistoryBytes, FUndo[top].Bytes);
    FUndo[top].Bytes := ACmd.MemSize;
    Inc(FHistoryBytes, FUndo[top].Bytes);
    list := nil;
    cnt := 0;
    BeginGather(FUndo[top].Keys);
    try
      for i := n0 to ACmd.FRecordCount - 1 do ACmd.FRecords[i].GatherObjects(list, cnt);
    finally
      keys := EndGather;
    end;
    HoldMore(FUndo[top], list, cnt, keys);
    TrimHistory;
  end;
  Flush;
  NoteModified;
end;

procedure TTyRichDocument.Undo;
var
  cmd: TTyRichCommand;
  e: TTyRichHistoryEntry;
begin
  CheckIdle('Undo');
  if FUpdateCount > 0 then
    raise ETyRichModel.Create('Undo inside BeginUpdate .. EndUpdate');
  if (FUndoCount = 0) or (FSaving > 0) then Exit;
  Dec(FUndoCount);
  cmd := FUndo[FUndoCount].Cmd;
  Dec(FHistoryBytes, FUndo[FUndoCount].Bytes);
  // (before the undo frees its records: the objects' addresses are still theirs)
  LetGoObjects(FUndo[FUndoCount]);
  FMergeBroken := True;
  try
    RunStep(cmd, StepUndo);
  except
    // the document no longer matches the history: drop it all
    cmd.Free;
    ClearHistory;
    LeftHistory;
    Flush;
    NoteModified;
    raise;
  end;
  FState := cmd.FStateBefore;
  e := Default(TTyRichHistoryEntry);
  e.Cmd := cmd;
  e.Bytes := cmd.MemSize;
  HoldObjects(e);
  if FRedoCount = Length(FRedo) then SetLength(FRedo, FRedoCount * 2 + 8);
  FRedo[FRedoCount] := e;
  Inc(FRedoCount);
  Inc(FHistoryBytes, e.Bytes);
  Flush;
  NoteModified;
end;

procedure TTyRichDocument.Redo;
var
  cmd: TTyRichCommand;
begin
  CheckIdle('Redo');
  if FUpdateCount > 0 then
    raise ETyRichModel.Create('Redo inside BeginUpdate .. EndUpdate');
  if (FRedoCount = 0) or (FSaving > 0) then Exit;
  Dec(FRedoCount);
  cmd := FRedo[FRedoCount].Cmd;
  Dec(FHistoryBytes, FRedo[FRedoCount].Bytes);
  LetGoObjects(FRedo[FRedoCount]);
  FMergeBroken := True;
  try
    RunStep(cmd, StepRedo);
  except
    // reverted; the steps after it were made on top of it
    cmd.Free;
    ClearRedo;
    Flush;
    raise;
  end;
  FState := cmd.FStateAfter;
  PushUndo(cmd);
  TrimHistory;
  Flush;
  NoteModified;
end;

function TTyRichDocument.CanUndo: Boolean;
begin
  Result := (FUndoCount > 0) and (FUpdateCount = 0) and (FRunning = nil) and (FSaving = 0);
end;

function TTyRichDocument.CanRedo: Boolean;
begin
  Result := (FRedoCount > 0) and (FUpdateCount = 0) and (FRunning = nil) and (FSaving = 0);
end;

procedure TTyRichDocument.ClearUndo;
begin
  CheckIdle('ClearUndo');
  if FUpdateCount > 0 then
    raise ETyRichModel.Create('ClearUndo inside BeginUpdate .. EndUpdate');
  ClearHistory;
  FMergeBroken := False;
end;

function TTyRichDocument.UndoDescription: string;
begin
  if FUndoCount = 0 then Result := '' else Result := FUndo[FUndoCount - 1].Cmd.Description;
end;

function TTyRichDocument.RedoDescription: string;
begin
  if FRedoCount = 0 then Result := '' else Result := FRedo[FRedoCount - 1].Cmd.Description;
end;

function TTyRichDocument.UndoStep: TTyRichCommand;
begin
  if FUndoCount = 0 then Result := nil else Result := FUndo[FUndoCount - 1].Cmd;
end;

function TTyRichDocument.RedoStep: TTyRichCommand;
begin
  if FRedoCount = 0 then Result := nil else Result := FRedo[FRedoCount - 1].Cmd;
end;

procedure TTyRichDocument.BeginUpdate(const ADescription: string);
begin
  CheckIdle('BeginUpdate');
  Inc(FUpdateCount);
  if FUpdateCount = 1 then FBlockDescription := ADescription;
end;

procedure TTyRichDocument.EndUpdate;
var
  cmds: array of TTyRichCommand;
  comp: TTyRichCompositeCommand;
  i: Integer;
begin
  CheckIdle('EndUpdate');
  if FUpdateCount = 0 then
    raise ETyRichModel.Create('EndUpdate without BeginUpdate');
  Dec(FUpdateCount);
  if FUpdateCount > 0 then Exit;
  if FBlockCount > 0 then
  begin
    cmds := nil;
    SetLength(cmds, FBlockCount);
    for i := 0 to FBlockCount - 1 do cmds[i] := FBlock[i];
    FBlockCount := 0;
    FBlock := nil;
    comp := TTyRichCompositeCommand.CreateExecuted(FBlockDescription, cmds);
    comp.FStateBefore := cmds[0].FStateBefore;
    comp.FStateAfter := cmds[High(cmds)].FStateAfter;
    ClearRedo;
    PushUndo(comp);
    FMergeBroken := False;
    TrimHistory;
  end;
  FBlockDescription := '';
  Flush;
  NoteModified;
end;

function TTyRichDocument.GetUpdating: Boolean;
begin
  Result := (FUpdateCount > 0) or (FHold > 0);
end;

procedure TTyRichDocument.BreakMerge;
begin
  FMergeBroken := True;
end;

end.
