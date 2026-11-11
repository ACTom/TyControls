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

  The only public way to change a document is a command (TTyRichDocument.Execute, added by the
  commands task). The primitives commands are built from are protected here; each returns a
  TTyRichUndoData that Revert puts back exactly. }

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
  public
    function Clone: TTyRichObject; virtual; abstract;
  end;

  TTyRichPictureFormat = (rpfUnknown, rpfPng, rpfJpeg, rpfBmp, rpfDib, rpfEmf, rpfWmf);

  TTyRichPicture = class(TTyRichObject)
  private
    FFormat: TTyRichPictureFormat;
    FData: TBytes;
    FWidthTwips: Integer;
    FHeightTwips: Integer;
    FRawRtf: RawByteString;
  public
    constructor Create(AFormat: TTyRichPictureFormat; const AData: TBytes;
      AWidthTwips, AHeightTwips: Integer; const ARawRtf: RawByteString = '');
    function Clone: TTyRichObject; override;
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
  public
    constructor Create(const ABytes: RawByteString);
    function Clone: TTyRichObject; override;
    property Bytes: RawByteString read FBytes;
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
      const ABoundaries: array of Integer): TTyRichRow; overload;
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

  TTyRichDocument = class;

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
    FOldData: array of TTyRichParaData;
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
  end;

  { Parses paragraphs on demand. EnsureParsed calls LoadParagraph for a paragraph that has no
    formatting yet; it sets that paragraph's (and, if it likes, its neighbours') formatting with
    SetParagraph. A paragraph it leaves unset counts as plain and is not asked about again. }
  TTyRichParaLoader = class(TTyRichDocBuilder)
  public
    procedure LoadParagraph(ADoc: TTyRichDocument; AIndex: Integer); virtual; abstract;
  end;

  TTyRichDocument = class
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
    procedure Init;
    procedure SetDefaults(const AFormat: TTyCharFormat);
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
  protected
    { The modification primitives. Each changes the document, raises OnChange, sets Modified
      and returns what Revert needs to undo it exactly (never nil; a no-op returns an empty
      record and notifies nothing). Undo records must be reverted in the reverse order they
      were made. A redo runs the primitive again. }

    { AText may hold paragraph separators. A split gives every part the paragraph's format and
      cell; the runs split at APos. AFormat: a character format id, or TyRichInheritFormat. }
    function InsertText(APos: TTyRichPos; const AText: UTF8String;
      AFormat: TTyCharFormatId = TyRichInheritFormat): TTyRichUndoData;
    { Inserts the object's U+FFFC; the document takes a reference to AObject. }
    function InsertObject(APos: TTyRichPos; AObject: TTyRichObject;
      AFormat: TTyCharFormatId = TyRichInheritFormat): TTyRichUndoData;
    { Across paragraphs (as WordPad): the merged paragraph takes the format of the paragraph
      the range ends in, except when the range is one separator and nothing else - then the
      format of the paragraph before it. }
    function DeleteRange(APos, ALen: TTyRichPos): TTyRichUndoData;
    { Changes only the AMask fields of every run in the range (an empty paragraph whose
      separator is in the range: its one run). }
    function ApplyCharFormat(APos, ALen: TTyRichPos; AMask: TTyCharFormatMask;
      const AValue: TTyCharFormat): TTyRichUndoData;
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
      between AIndex and the cell. }
    function CellParas(AIndex: Integer; ACell: TTyRichCell; out AFirst, ALast: Integer): Boolean;

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
  end;

function TyDefaultCharFormat: TTyCharFormat;
function TyDefaultParaFormat: TTyParaFormat;
function TyMergeCharFormat(const ABase: TTyCharFormat; AMask: TTyCharFormatMask;
  const AValue: TTyCharFormat): TTyCharFormat;
function TyMergeParaFormat(const ABase: TTyParaFormat; AMask: TTyParaFormatMask;
  const AValue: TTyParaFormat): TTyParaFormat;
{ U+FFFC in UTF-8, the character an object occupies. }
function TyRichObjectChar: UTF8String;

implementation

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

constructor TTyRichPicture.Create(AFormat: TTyRichPictureFormat; const AData: TBytes;
  AWidthTwips, AHeightTwips: Integer; const ARawRtf: RawByteString);
begin
  inherited Create;
  FFormat := AFormat;
  FData := AData;
  FWidthTwips := AWidthTwips;
  FHeightTwips := AHeightTwips;
  FRawRtf := ARawRtf;
end;

function TTyRichPicture.Clone: TTyRichObject;
begin
  Result := TTyRichPicture.Create(FFormat, FData, FWidthTwips, FHeightTwips, FRawRtf);
end;

constructor TTyRichOpaque.Create(const ABytes: RawByteString);
begin
  inherited Create;
  FBytes := ABytes;
end;

function TTyRichOpaque.Clone: TTyRichObject;
begin
  Result := TTyRichOpaque.Create(FBytes);
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
  const ABoundaries: array of Integer): TTyRichRow;
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
  for i := 0 to High(FOldData) do FDoc.ReleaseData(FOldData[i]);
  for i := 0 to High(FRemoved.Pieces) do
    if (FRemoved.Pieces[i].Separator <> rsNone) and (FRemoved.Pieces[i].Data <> nil) then
      FDoc.ReleaseData(TTyRichParaData(FRemoved.Pieces[i].Data));
  inherited Destroy;
end;

function TTyRichUndoData.MemSize: Int64;
begin
  Result := InstanceSize + Length(FRemoved.Pieces) * SizeOf(TTyRichPiece) +
    Length(FOldData) * SizeOf(Pointer);
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
  // WordPad's page: US Letter, 1.25" left and right margins
  FPaperWidth := 12240;
  FPaperHeight := 15840;
  FMarginLeft := 1800;
  FMarginRight := 1800;
  FText.OnParasChanged := @TextParasChanged;
  FText.OnParaDataDropped := @TextDataDropped;
end;

destructor TTyRichDocument.Destroy;
var
  d: TTyRichParaData;
begin
  if FText <> nil then
  begin
    FText.OnParasChanged := nil;
    FText.OnParaDataDropped := nil;
  end;
  // nothing may outlive the document (the history goes first), so every value still alive is
  // the text's or the plain sentinel; the text itself never frees data
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
  if (Result <> nil) or (FLoader = nil) or FInLoad then Exit;
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
  t := TableAt(AIndex);
  if t = nil then Exit(False);
  AFirst := AIndex;
  while (AFirst > 0) and (TableAt(AFirst - 1) = t) do Dec(AFirst);
  ALast := AIndex;
  last := FText.ParaCount - 1;
  while (ALast < last) and (TableAt(ALast + 1) = t) do Inc(ALast);
  Result := True;
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

procedure TTyRichDocument.Notify(const AChange: TTyRichChange);
begin
  FModified := True;
  if Assigned(FOnChange) then FOnChange(Self, AChange);
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
begin
  c := Default(TTyRichChange);
  c.Pos := APos;
  FText.ParaOfPos(APos);   // range check before anything changes
  if AText = '' then Exit(NewUndo(c));
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
    SetLength(Result.FOldData, 1);
    Result.FOldData[0] := d;
    AcquireData(d);
    Inc(FEditing);
    try
      FText.Insert(APos, AText);
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
var
  c: TTyRichChange;
  k, m, n, i: Integer;
  dk, dm, merged: TTyRichParaData;
  rk, rm, runs: TTyRunArray;
  e, psk, lenk, ok, lenm, om: Int64;
  fmt: TTyParaFormatId;
  cell: TTyRichCell;
begin
  c := Default(TTyRichChange);
  c.Pos := APos;
  if (APos < 0) or (ALen < 0) or (APos + ALen > FText.Length) then
    raise ETyRichModel.CreateFmt('Range %d+%d out of 0..%d', [APos, ALen, FText.Length]);
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
    if (m = k + 1) and (ALen = 1) then
    begin
      // one separator and nothing else: the paragraph before it gives the format
      fmt := FormatOfData(dk);
      cell := CellOfData(dk);
    end
    else
    begin
      // otherwise the paragraph the range ends in does (measured in WordPad)
      fmt := FormatOfData(dm);
      cell := CellOfData(dm);
    end;
    if (ok = 0) and (om = 0) and not ((m = k + 1) and (ALen = 1)) then
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
    SetLength(Result.FOldData, 1);
    Result.FOldData[0] := dk;
    AcquireData(dk);
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
  k, last, i, j, n: Integer;
  b, ps, len, lo, hi, s, e: Int64;
  d, nd, prevD, prevNew: TTyRichParaData;
  r, runs: TTyRunArray;
  whole, changed: Boolean;
  fromIds, toIds: array of TTyCharFormatId;

  function MapId(AId: TTyCharFormatId): TTyCharFormatId;
  var
    x: Integer;
  begin
    for x := 0 to High(fromIds) do
      if fromIds[x] = AId then Exit(toIds[x]);
    Result := FFormats.InternChar(TyMergeCharFormat(FFormats.CharFormat(AId), AMask, AValue));
    SetLength(fromIds, Length(fromIds) + 1);
    SetLength(toIds, Length(toIds) + 1);
    fromIds[High(fromIds)] := AId;
    toIds[High(toIds)] := Result;
  end;

begin
  c := Default(TTyRichChange);
  c.Pos := APos;
  if (APos < 0) or (ALen < 0) or (APos + ALen > FText.Length) then
    raise ETyRichModel.CreateFmt('Range %d+%d out of 0..%d', [APos, ALen, FText.Length]);
  if (ALen = 0) or (AMask = []) then Exit(NewUndo(c));
  b := APos + ALen;
  k := FText.ParaOfPos(APos);
  last := FText.ParaOfPos(b);
  if (last > k) and (FText.ParaStart(last) = b) then Dec(last);
  fromIds := nil;
  toIds := nil;
  prevD := nil;
  prevNew := nil;
  Result := NewUndo(c);
  try
    Result.FFirstPara := k;
    SetLength(Result.FOldData, last - k + 1);
    for i := k to last do
    begin
      d := DataOf(i);
      Result.FOldData[i - k] := d;
      AcquireData(d);
      r := RunsOfData(d);
      whole := (i > k) and (i < last);
      runs := nil;
      n := 0;
      if whole then
      begin
        // a paragraph inside the range: every run, no lengths needed; equal values (plain
        // paragraphs) map to one shared result
        if (i > k + 1) and (d = prevD) then
        begin
          PutData(i, d, prevNew);
          Continue;
        end;
        for j := 0 to High(r) do AppendRun(runs, n, r[j].Start, MapId(r[j].Format), r[j].Obj);
      end
      else
      begin
        ps := FText.ParaStart(i);
        len := FText.ParaLength(i);
        lo := APos - ps;
        if lo < 0 then lo := 0;
        hi := b - ps;
        if hi > len then hi := len;
        if len = 0 then
        begin
          if (APos <= ps) and (ps < b) then
            AppendRun(runs, n, 0, MapId(r[0].Format), nil)
          else
            Continue;
        end
        else if lo >= hi then
          Continue
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
      end;
      SetLength(runs, n);
      changed := not SameRuns(runs, r);
      if changed then nd := MakeData(FormatOfData(d), runs, CellOfData(d)) else nd := d;
      PutData(i, d, nd);
      if whole then
      begin
        prevD := d;
        prevNew := nd;
      end;
    end;
  except
    Result.Free;
    raise;
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
  i, x: Integer;
  d, nd, prevD, prevNew: TTyRichParaData;
  oldFmt, newFmt: TTyParaFormatId;
  fromIds, toIds: array of TTyParaFormatId;
begin
  c := Default(TTyRichChange);
  if (AFirstPara < 0) or (ALastPara < AFirstPara) or (ALastPara >= FText.ParaCount) then
    raise ETyRichModel.CreateFmt('Paragraphs %d..%d out of 0..%d',
      [AFirstPara, ALastPara, FText.ParaCount - 1]);
  c.Pos := FText.ParaStart(AFirstPara);
  if AMask = [] then Exit(NewUndo(c));
  fromIds := nil;
  toIds := nil;
  prevD := nil;
  prevNew := nil;
  Result := NewUndo(c);
  try
    Result.FFirstPara := AFirstPara;
    SetLength(Result.FOldData, ALastPara - AFirstPara + 1);
    for i := AFirstPara to ALastPara do
    begin
      d := DataOf(i);
      Result.FOldData[i - AFirstPara] := d;
      AcquireData(d);
      if (i > AFirstPara) and (d = prevD) then
      begin
        PutData(i, d, prevNew);
        Continue;
      end;
      oldFmt := FormatOfData(d);
      newFmt := -1;
      for x := 0 to High(fromIds) do
        if fromIds[x] = oldFmt then newFmt := toIds[x];
      if newFmt < 0 then
      begin
        newFmt := FFormats.InternPara(TyMergeParaFormat(FFormats.ParaFormat(oldFmt), AMask,
          AValue));
        SetLength(fromIds, Length(fromIds) + 1);
        SetLength(toIds, Length(toIds) + 1);
        fromIds[High(fromIds)] := oldFmt;
        toIds[High(toIds)] := newFmt;
      end;
      // the runs are immutable, so the new value shares them
      if newFmt = oldFmt then nd := d
      else nd := MakeData(newFmt, RunsOfData(d), CellOfData(d));
      PutData(i, d, nd);
      prevD := d;
      prevNew := nd;
    end;
  except
    Result.Free;
    raise;
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
    SetLength(Result.FOldData, total);
    for i := 0 to total - 1 do
    begin
      d := DataOf(AFirstPara + i);
      Result.FOldData[i] := d;
      AcquireData(d);
      PutData(AFirstPara + i, d, NewData(FormatOfData(d), RunsOfData(d), cells[i]));
    end;
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
  i: Integer;
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
      for i := 0 to High(u.FOldData) do
        PutData(u.FFirstPara + i, SlotData(u.FFirstPara + i), u.FOldData[i]);
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

end.
