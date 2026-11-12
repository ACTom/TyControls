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
  Classes, SysUtils, Graphics, LCLType, tyControls.RichEdit.Text;

const
  { Insert without a format: the text takes the format of the character before it in the same
    paragraph, or of the character after it at the paragraph's start (as WordPad does). }
  TyRichInheritFormat = -1;

type
  ETyRichModel = class(Exception);

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

  { paraLeft..paraJustify, not the plan's paLeft..: Menus.TPopupAlignment already has paLeft,
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
    RtlPar: Boolean;        // kept and written back, not rendered (spec 6.1)
    Extra: TTyOpaqueAttrs;
    function Equals(const B: TTyParaFormat): Boolean;
    function Hash: Cardinal;
  end;

  TTyParaFormatField = (pffAlign, pffLeftIndent, pffRightIndent, pffFirstIndent,
    pffSpaceBefore, pffSpaceAfter, pffLineSpacing, pffTabs, pffList, pffRtlPar, pffExtra);
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
    { Merged cells and the like: shown and kept, but its structure cannot be edited
      (spec 3.5). }
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

  { One paragraph's formatting, immutable once made (internal; see the unit comment). FRuns
    nil means one run in the document's default character format. }
  TTyRichParaData = class
  private
    FRefCount: Integer;
    FPrev, FNext: TTyRichParaData;
    FParaFormat: TTyParaFormatId;
    FCell: TTyRichCell;
    FRuns: TTyRunArray;
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
    FFirstPara: Integer;
    FOldData: array of TTyRichOldData;   // run-length: one reference per entry
    FOldCount: Integer;
    procedure AddOld(D: TTyRichParaData);
    procedure SealOld;
  public
    destructor Destroy; override;
    { Bytes this record keeps alive, for the history's memory limit (the paragraph values
      themselves are shared and not counted). }
    function MemSize: Int64;
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
      character. }
    class function SetParagraph(ADoc: TTyRichDocument; AIndex: Integer;
      AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray; ACell: TTyRichCell = nil): Boolean;
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
      ETyRichModel while a command runs or inside BeginUpdate .. EndUpdate. Without the
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
      AMask: TTyCharFormatMask; const AValue: TTyCharFormat): TTyRichChange;
    function ApplyParaFormat(ADoc: TTyRichDocument; AFirstPara, ALastPara: Integer;
      AMask: TTyParaFormatMask; const AValue: TTyParaFormat): TTyRichChange;
    function MarkTable(ADoc: TTyRichDocument; AFirstPara: Integer; ATable: TTyRichTable;
      const ACellParas: array of Integer): TTyRichChange;

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
    { Bytes the history keeps for it (MaxUndoBytes). }
    function MemSize: Int64; virtual;
    { Its last run changed something; one that did not is not kept in the history. }
    property Changed: Boolean read FChanged;
  end;

  TTyRichHistoryEntry = record
    Cmd: TTyRichCommand;
    Bytes: Int64;
  end;

  TTyRichDocument = class
  private
    // history
    FUndo: array of TTyRichHistoryEntry;
    FUndoCount: Integer;
    FRedo: array of TTyRichHistoryEntry;
    FRedoCount: Integer;
    FHistoryBytes: Int64;
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
    procedure RunStep(ACmd: TTyRichCommand; AStep: Integer);
    procedure Flush;
    procedure PushUndo(ACmd: TTyRichCommand);
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
    FModified: Boolean;
    FOnChange: TTyRichChangeEvent;
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
      cell; the runs split at APos. AFormat: a character format id, or TyRichInheritFormat. }
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
      table are passed over. }
    function ApplyCharFormat(APos, ALen: TTyRichPos; AMask: TTyCharFormatMask;
      const AValue: TTyCharFormat): TTyRichUndoData;
    { Paragraphs of a row that holds a nested table are passed over. }
    function ApplyParaFormat(AFirstPara, ALastPara: Integer; AMask: TTyParaFormatMask;
      const AValue: TTyParaFormat): TTyRichUndoData;
    { Makes the paragraphs from AFirstPara on a table: ACellParas[i] paragraphs for each cell,
      row by row. ATable must not be in use; the paragraphs must not be in a table. }
    function MarkTable(AFirstPara: Integer; ATable: TTyRichTable;
      const ACellParas: array of Integer): TTyRichUndoData;
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
      is sent back: everything read stays as it was returned until the outermost EndRead.
      So whoever holds a table, a cell or an object across another read does it inside one -
      a layout pass over the visible paragraphs, a save, TableParas and CellParas themselves.
      (Format ids, RunsOf's copy and text are values: they need no scope. A running command
      is a scope by itself.) A scope costs nothing to open; keep it as short as the pass it
      protects: parsed paragraphs only pile up while it is open. }
    procedure BeginRead;
    procedure EndRead;

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

    { Runs ACmd and keeps it for undo; the document owns ACmd from here on, also when this
      returns False or raises. False: ACmd.CanExecute said no, or the document is Loading or
      Incomplete, and nothing changed. A command that changed nothing is not kept.
      Consecutive typing merges into one step until
      BreakMerge, an Undo or Redo, or any other command. A new command drops the redo side.
      Outside BeginUpdate .. EndUpdate it raises OnChange once. Raises inside a running
      command; if ACmd raises, what it did is reverted first. }
    function Execute(ACmd: TTyRichCommand): Boolean;
    { One step back / forward, one OnChange. Nothing to undo / redo: nothing happens. They
      raise inside BeginUpdate .. EndUpdate or a running command. }
    procedure Undo;
    procedure Redo;
    function CanUndo: Boolean;
    function CanRedo: Boolean;
    function UndoDescription: string;    // '' when there is nothing
    function RedoDescription: string;
    { Nested. The commands executed until the outermost EndUpdate become one undo step
      (TTyRichCompositeCommand, described by ADescription of the outermost BeginUpdate, or by
      its only command), and that EndUpdate raises the block's one OnChange covering all of
      it. A block that changed nothing keeps nothing and raises nothing. }
    procedure BeginUpdate(const ADescription: string = '');
    procedure EndUpdate;
    { The caret moved: the next typing does not merge with the typing before. }
    procedure BreakMerge;
    property UndoDepth: Integer read FUndoCount;
    property RedoDepth: Integer read FRedoCount;
    { What the undo and redo steps keep, as their MemSize when they were stored. }
    property HistoryBytes: Int64 read FHistoryBytes;
    { The history's limit: past it the oldest undo steps go, never the newest. 0 or less: no
      limit. }
    property MaxUndoBytes: Int64 read FMaxUndoBytes write SetMaxUndoBytes;

    { Read it; changing it directly bypasses the model (no undo, no OnChange: the touched
      paragraph's runs are only clipped to its text, new paragraphs are plain). }
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
    property Modified: Boolean read FModified write FModified;
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
  if pffRtlPar in AMask then Result.RtlPar := AValue.RtlPar;
  if pffExtra in AMask then Result.Extra := AValue.Extra;
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
  inherited Destroy;
end;

function TTyRichUndoData.MemSize: Int64;
begin
  Result := InstanceSize + Length(FRemoved.Pieces) * SizeOf(TTyRichPiece) +
    Length(FOldData) * SizeOf(TTyRichOldData);
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

class function TTyRichDocBuilder.SetParagraph(ADoc: TTyRichDocument; AIndex: Integer;
  AParaFormat: TTyParaFormatId; const ARuns: TTyRunArray; ACell: TTyRichCell): Boolean;
var
  len: Int64;
  runs: TTyRunArray;
  n, i: Integer;
  d: TTyRichParaData;
begin
  ADoc.CheckParaId(AParaFormat);
  if Length(ARuns) = 0 then
    raise ETyRichModel.Create('A paragraph needs at least one run');
  len := ADoc.FText.ParaLength(AIndex);
  for i := 0 to High(ARuns) do
  begin
    ADoc.CheckCharId(ARuns[i].Format);
    if ((i = 0) and (ARuns[i].Start <> 0)) or ((i > 0) and (ARuns[i].Start <= ARuns[i - 1].Start)) or
       ((i > 0) and (ARuns[i].Start >= len)) or
       ((ARuns[i].Obj <> nil) and (RunEnd(ARuns, i, len) <> ARuns[i].Start + 1)) then
      raise ETyRichModel.CreateFmt('Runs of paragraph %d are malformed', [AIndex]);
  end;
  if ADoc.SlotData(AIndex) <> nil then Exit(False);
  runs := nil;
  n := 0;
  if len = 0 then
    AppendRun(runs, n, 0, ARuns[0].Format, ARuns[0].Obj)
  else
    AppendSlice(runs, n, ARuns, len, 0, len, 0);
  SetLength(runs, n);
  d := ADoc.MakeData(AParaFormat, runs, ACell);
  ADoc.PutData(AIndex, nil, d);
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
  FModified := False;
  FLoadingContent := False;
  FIncomplete := False;
  c.NewLen := FText.Length;
  c.NewParaCount := FText.ParaCount;
  if Assigned(FOnChange) then FOnChange(Self, c);
end;

destructor TTyRichDocument.Destroy;
var
  d: TTyRichParaData;
begin
  // the history first: its records hold references to the values disposed below
  ClearHistory;
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
  // WordPad's page: US Letter, 1.25" left and right margins
  FPaperWidth := 12240;
  FPaperHeight := 15840;
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
    if ARuns[i].Obj <> nil then ARuns[i].Obj.AddRef;
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
  FModified := True;
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
  PutData(AIndex, d, MakeData(d.FParaFormat, runs, d.FCell));
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

{ ---- rows that hold a nested table ---- }

const
  SNestedRow = 'This row holds a nested table and is kept as the file has it: ' +
    'its text cannot be changed';

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
  FModified := True;
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
    FromIds, ToIds: array of TTyCharFormatId;
    PrevD, PrevNew: TTyRichParaData;
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
begin
  for x := 0 to High(FromIds) do
    if FromIds[x] = AId then Exit(ToIds[x]);
  Result := Doc.FFormats.InternChar(TyMergeCharFormat(Doc.FFormats.CharFormat(AId), Mask, Value));
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
      else nd := Doc.MakeData(Doc.FormatOfData(d), runs, Doc.CellOfData(d));
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
    else nd := Doc.MakeData(Doc.FormatOfData(d), runs, Doc.CellOfData(d));
  end;
  if nd <> d then
  begin
    // the slot's reference moves to the new value; the record keeps d alive
    Doc.AcquireData(nd);
    Doc.ReleaseData(d);
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
    else nd := Doc.MakeData(newFmt, Doc.RunsOfData(d), Doc.CellOfData(d));
    PrevD := d;
    PrevNew := nd;
  end;
  if nd <> d then
  begin
    Doc.AcquireData(nd);
    Doc.ReleaseData(d);
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
  if ChangeRefused(APos, 0) then raise ETyRichModel.Create(SNestedRow);
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
      PutData(k, d, MakeData(fmt, runs1, cell));
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
      PutData(k, d, MakeData(fmt, runs1, cell));
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
  if (ALen > 0) and ChangeRefused(APos, ALen) then raise ETyRichModel.Create(SNestedRow);
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
  dk, dm, merged: TTyRichParaData;
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
    merged := MakeData(FormatOfData(dk), runs, CellOfData(dk));
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
    end
    else
    begin
      // otherwise the paragraph the range ends in does (measured in WordPad)
      fmt := FormatOfData(dm);
      cell := CellOfData(dm);
    end;
    if (ok = 0) and (om = 0) and not join then
      merged := dm   // whole paragraphs went: the next one is untouched
    else
    begin
      AppendSlice(runs, n, rk, lenk, 0, ok, 0);
      AppendSlice(runs, n, rm, lenm, om, lenm, ok - om);
      if n = 0 then AppendRun(runs, n, 0, rk[RunIndexAt(rk, ok)].Format, nil);
      SetLength(runs, n);
      merged := MakeData(fmt, runs, cell);
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

function TTyRichDocument.ApplyCharFormat(APos, ALen: TTyRichPos; AMask: TTyCharFormatMask;
  const AValue: TTyCharFormat): TTyRichUndoData;
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
      // only the two end paragraphs need their place; the walk itself does no lookups
      w.PsK := FText.ParaStart(k);
      w.LenK := FText.ParaLength(k);
      w.PsLast := FText.ParaStart(last);
      w.LenLast := FText.ParaLength(last);
      Result.FFirstPara := k;
      FText.MapParaData(k, last, @w.Map);
      Result.SealOld;
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
      PutData(AFirstPara + i, d, NewData(FormatOfData(d), RunsOfData(d), cells[i]));
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
  AMask: TTyCharFormatMask; const AValue: TTyCharFormat): TTyRichChange;
begin
  CheckRunning(ADoc);
  Result := Keep(ADoc.ApplyCharFormat(APos, ALen, AMask, AValue));
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

{ ---- TTyRichDocument: commands and the history ---- }

procedure TTyRichDocument.CheckIdle(const AWhat: string);
begin
  if FRunning <> nil then
    raise ETyRichModel.CreateFmt('%s while a command runs', [AWhat]);
end;

procedure TTyRichDocument.Flush;
var
  c: TTyRichChange;
begin
  if (FHold > 0) or (FUpdateCount > 0) or not FHasPending then Exit;
  c := FPending;
  FHasPending := False;
  FPending := Default(TTyRichChange);
  if Assigned(FOnChange) then FOnChange(Self, c);
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
  e.Cmd := ACmd;
  e.Bytes := ACmd.MemSize;
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
begin
  if ACmd = nil then
    raise ETyRichModel.Create('Execute needs a command');
  try
    CheckIdle('Execute');
    // a document still loading (or cut short) is read-only
    ok := not FLoadingContent and not FIncomplete and ACmd.CanExecute(Self);
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
    Exit;
  end;
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
    if top.TryMerge(ACmd) then
    begin
      ACmd.Free;
      Dec(FHistoryBytes, FUndo[FUndoCount - 1].Bytes);
      FUndo[FUndoCount - 1].Bytes := top.MemSize;
      Inc(FHistoryBytes, FUndo[FUndoCount - 1].Bytes);
      ACmd := nil;
    end;
  end;
  if ACmd <> nil then PushUndo(ACmd);
  FMergeBroken := False;
  TrimHistory;
  Flush;
end;

procedure TTyRichDocument.Undo;
var
  cmd: TTyRichCommand;
  e: TTyRichHistoryEntry;
begin
  CheckIdle('Undo');
  if FUpdateCount > 0 then
    raise ETyRichModel.Create('Undo inside BeginUpdate .. EndUpdate');
  if FUndoCount = 0 then Exit;
  Dec(FUndoCount);
  cmd := FUndo[FUndoCount].Cmd;
  Dec(FHistoryBytes, FUndo[FUndoCount].Bytes);
  FMergeBroken := True;
  try
    RunStep(cmd, StepUndo);
  except
    // the document no longer matches the history: drop it all
    cmd.Free;
    ClearHistory;
    Flush;
    raise;
  end;
  e.Cmd := cmd;
  e.Bytes := cmd.MemSize;
  if FRedoCount = Length(FRedo) then SetLength(FRedo, FRedoCount * 2 + 8);
  FRedo[FRedoCount] := e;
  Inc(FRedoCount);
  Inc(FHistoryBytes, e.Bytes);
  Flush;
end;

procedure TTyRichDocument.Redo;
var
  cmd: TTyRichCommand;
begin
  CheckIdle('Redo');
  if FUpdateCount > 0 then
    raise ETyRichModel.Create('Redo inside BeginUpdate .. EndUpdate');
  if FRedoCount = 0 then Exit;
  Dec(FRedoCount);
  cmd := FRedo[FRedoCount].Cmd;
  Dec(FHistoryBytes, FRedo[FRedoCount].Bytes);
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
  PushUndo(cmd);
  TrimHistory;
  Flush;
end;

function TTyRichDocument.CanUndo: Boolean;
begin
  Result := (FUndoCount > 0) and (FUpdateCount = 0) and (FRunning = nil);
end;

function TTyRichDocument.CanRedo: Boolean;
begin
  Result := (FRedoCount > 0) and (FUpdateCount = 0) and (FRunning = nil);
end;

function TTyRichDocument.UndoDescription: string;
begin
  if FUndoCount = 0 then Result := '' else Result := FUndo[FUndoCount - 1].Cmd.Description;
end;

function TTyRichDocument.RedoDescription: string;
begin
  if FRedoCount = 0 then Result := '' else Result := FRedo[FRedoCount - 1].Cmd.Description;
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
    ClearRedo;
    PushUndo(comp);
    FMergeBroken := False;
    TrimHistory;
  end;
  FBlockDescription := '';
  Flush;
end;

procedure TTyRichDocument.BreakMerge;
begin
  FMergeBroken := True;
end;

end.
