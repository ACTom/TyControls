unit tyControls.RichEdit.Text;

{ Text storage for TTyRichEdit: a piece table whose pieces sit, in document order, in the
  leaves of a B+ tree, and that tree is the paragraph index as well.

  Pieces refer to bytes that never move: the original buffer (referenced, never copied),
  the append-only add buffer, or a lazy source - a paragraph known only by its byte range
  in the original file and its character count, whose text a TTyRichTextProvider decodes
  the first time somebody reads or edits it (the RTF reader's paragraphs).

  Counting: positions are code points. CR, LF and CRLF are each one separator and one
  character; a separator is always the last thing in its piece, so a paragraph is a run of
  pieces ending with one that carries a separator, and the last paragraph is the run after
  the last separator (it has none). A byte that is not part of a valid UTF-8 sequence is one
  character on its own and is kept as it is, so a file goes back out byte for byte. A
  separator, once stored, is never re-paired: an LF inserted after a lone CR stays a second
  separator.

  Inner nodes keep, per child, the number of pieces, separators, characters, bytes, how many
  paragraphs have a measured height and the sum of those heights, so position, paragraph
  and height lookups walk one root-to-leaf path. Each paragraph has a height - measured, or
  not yet: then it counts as DefaultParaHeight - and a pointer-sized data slot, kept on the
  piece that carries its separator (the last paragraph's live in the object), so they move
  with the paragraph when paragraphs before it come and go. }

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$inline on}

interface

uses
  Classes, SysUtils, Generics.Collections;

const
  TyRichLeafCap = 128;
  TyRichInnerCap = 64;
  TyRichMaxDepth = 24;
  { A piece never grows past this many bytes (plus the rest of the character that crosses
    it), so its counts fit a LongInt: the load scan ends a piece there, without a separator,
    and so must a reader that finds the pieces itself (CreateScanned). }
  TyRichMaxPieceBytes = 1 shl 30;
  { The highest height a paragraph can be given (a piece stores it plus one in a LongInt). }
  TyRichMaxParaHeight = High(LongInt) - 1;

type
  TTyRichPos = Int64;

  ETyRichText = class(Exception);

  TTyRichPieceKind = (rpkOriginal, rpkAdded, rpkLazy);
  TTyRichSeparator = (rsNone, rsCR, rsLF, rsCRLF);

  PTyRichPiece = ^TTyRichPiece;

  { One piece. In the live tree FHeight/FData are the paragraph's when the piece carries a
    separator (zero/nil otherwise); FHeight is the measured height plus one, 0 while the
    paragraph is not measured, so that a piece made from nothing is unmeasured. In a
    TTyRichPieces snapshot FHeight is 0 and FData of a separator piece is the data of the
    paragraph that FOLLOWS that separator, which is what RestorePieces needs to put a
    deleted range's paragraph data back. }
  TTyRichPiece = packed record
  private
    FSrc: Int64;        // source offset in the low 56 bits, kind and separator above
    FBytes: LongInt;    // bytes in the source (a lazy piece: in the original file)
    FChars: LongInt;    // characters, the separator included
    FHeight: LongInt;
    FData: Pointer;
  public
    function Kind: TTyRichPieceKind;
    function Separator: TTyRichSeparator;
    function SrcOffset: Int64;
    function ByteCount: Integer;
    function CharCount: Integer;
    function Data: Pointer;
  end;

  TTyRichPieceArray = array of TTyRichPiece;

  { What a command keeps to put a range back: piece references, never text. }
  TTyRichPieces = record
    Pieces: TTyRichPieceArray;
    CharCount: Int64;
  end;

  { One stretch of bytes a writer can copy. Bytes is nil for a lazy run (the bytes are in
    the original file at SrcOffset, which the text does not hold) and is valid only during
    the callback. A run of the whole of a paragraph that is still rpkOriginal or rpkLazy is
    that paragraph's untouched source. }
  TTyRichByteRun = record
    Kind: TTyRichPieceKind;
    SrcOffset: Int64;
    ByteCount: Int64;
    CharCount: Int64;
    Separator: TTyRichSeparator;  // the run ends with this separator (its bytes included)
    Bytes: PByte;
  end;

  TTyRichRunEvent = procedure(const ARun: TTyRichByteRun; var AContinue: Boolean) of object;
  TTyRichParasChangedEvent = procedure(Sender: TObject; AFirst, AOldCount, ANewCount: Integer)
    of object;
  TTyRichParaDataEvent = procedure(Sender: TObject; AData: Pointer) of object;
  { One step of MapParaData: paragraph AIndex holds AData; what it returns goes in its slot. }
  TTyRichParaDataMap = function(AIndex: Integer; AData: Pointer): Pointer of object;
  { One step of WalkParas: paragraph AIndex holds AData, and when it is a lazy paragraph that
    was never edited its bytes in the original file are ASrcBytes from ASrcOffset (-1
    otherwise). AContinue False ends the walk. }
  TTyRichParaWalk = procedure(AIndex: Integer; AData: Pointer; ASrcOffset, ASrcBytes: Int64;
    var AContinue: Boolean) of object;

  { Decodes one lazy paragraph: its text WITHOUT the separator, exactly ACharCount
    characters minus the separator, containing no CR or LF. It may read the text and set
    paragraph data; changing the text from inside it raises. }
  TTyRichTextProvider = class
  public
    function DecodeParagraph(ASrcOffset, ASrcBytes, ACharCount: Int64): UTF8String;
      virtual; abstract;
  end;

  TTyRichSum = record
    Entries: LongInt;
    Seps: LongInt;
    Chars: Int64;
    Bytes: Int64;
    Height: Int64;     // of the measured paragraphs only
    LazyMax: Int64;    // the highest source offset of a lazy piece, -1 none
    Measured: LongInt; // separators whose paragraph has a measured height
  end;

  { The heights a node holds - a leaf's FHeight, an inner node's Height and Measured per
    child - count only while HeightEpoch is the text's: UnmeasureAll moves the text's on,
    and a node left behind drops its heights when it is next entered (Settle). }
  PTyRichNode = ^TTyRichNode;
  TTyRichNode = record
    Count: LongInt;
    IsLeaf: Boolean;
    Pad: array[0..2] of Byte;
    HeightEpoch: Int64;
  end;

  PTyRichLeaf = ^TTyRichLeaf;
  TTyRichLeaf = record
    Count: LongInt;
    IsLeaf: Boolean;
    Pad: array[0..2] of Byte;
    HeightEpoch: Int64;
    Items: array[0..TyRichLeafCap - 1] of TTyRichPiece;
  end;

  PTyRichInner = ^TTyRichInner;
  TTyRichInner = record
    Count: LongInt;
    IsLeaf: Boolean;
    Pad: array[0..2] of Byte;
    HeightEpoch: Int64;
    Child: array[0..TyRichInnerCap - 1] of PTyRichNode;
    Sum: array[0..TyRichInnerCap - 1] of TTyRichSum;
  end;

  TTyRichStep = record
    Node: PTyRichNode;
    Index: LongInt;
  end;

  TTyRichPath = record
    Steps: array[0..TyRichMaxDepth] of TTyRichStep;
  end;

  TTyRichSeek = (rskEntry, rskChar, rskSep, rskHeight);

  { Decoded lazy paragraphs by source offset: their text and separator bytes. }
  TTyRichDecodedMap = specialize TDictionary<Int64, RawByteString>;

  TTyRichText = class
  private
    FOrig: TBytes;
    FAdd: TBytes;
    FAddLen: Int64;
    FRoot: PTyRichNode;
    FDepth: Integer;
    FTotal: TTyRichSum;
    FLastData: Pointer;
    FLastHeight: LongInt;              // as a piece's FHeight
    FDefaultHeight: Int64;
    FHeightEpoch: Int64;
    FNodeVisits: Int64;
    FSumScans: Int64;
    FProvider: TTyRichTextProvider;
    FOwnsProvider: Boolean;
    FDecoded: TTyRichDecodedMap;
    FDecodedBytes: Int64;
    FLoading: Boolean;
    FLoadLeaf: PTyRichLeaf;
    FLoadLeaves: TFPList;
    FLoadLastSep: Boolean;
    FLoadLastSrc: Int64;
    FLoadLastBytes: Int64;
    FLoadLastChars: Int64;
    FReopened: Boolean;                // ReopenLazyLoad .. EndLazyLoad
    FLazyTail: Boolean;                // the last paragraph is the empty lazy one appended last
    FAppend: TTyRichPieceArray;
    FAppendCount: Integer;
    FScanToLoad: Boolean;
    FScan: TTyRichPieceArray;
    FScanCount: Integer;
    FLoadSeps: array[0..3] of Int64;   // separators the load scan found, by stored kind
    FLoadInvalid: Int64;               // bytes the load scan found that start no UTF-8
    FScanned: Boolean;                 // CreateScanned .. EndScanned
    FScannedBytes: Int64;              // bytes the appended pieces cover so far
    FWalking: Integer;
    FOnParasChanged: TTyRichParasChangedEvent;
    FOnParaDataDropped: TTyRichParaDataEvent;
    // tree
    function NewNode(ALeaf: Boolean): PTyRichNode;
    procedure FreeNode(ANode: PTyRichNode);
    function NodeSum(ANode: PTyRichNode): TTyRichSum;
    procedure Settle(ANode: PTyRichNode); inline;
    procedure DropHeights(ANode: PTyRichNode);
    function SumHeight(const ASum: TTyRichSum): Int64; inline;
    function PieceHeight(const APiece: TTyRichPiece): Int64; inline;
    procedure AddToPath(const APath: TTyRichPath; AHeight: Int64; AMeasured: Integer);
    function Descend(AMode: TTyRichSeek; AKey: Int64; out APath: TTyRichPath;
      out ABefore: TTyRichSum): Boolean;
    procedure Find(AMode: TTyRichSeek; AKey: Int64; out APath: TTyRichPath;
      out ABefore: TTyRichSum);
    function ItemAt(const APath: TTyRichPath): PTyRichPiece;
    function Advance(var APath: TTyRichPath; ACountVisits: Boolean = False): Boolean;
    procedure FixUp(var APath: TTyRichPath; ALevel: Integer);
    procedure SplitNode(var APath: TTyRichPath; ALevel, AAt: Integer);
    procedure RemoveNode(var APath: TTyRichPath; ALevel: Integer);
    procedure Rebalance(var APath: TTyRichPath; ALevel: Integer);
    procedure CollapseRoot;
    procedure InsertEntries(AAt: LongInt; const AItems: array of TTyRichPiece);
    procedure DeleteEntries(AFirst, ACount: LongInt);
    // loading
    procedure LoadPiece(ASrc: Int64; ABytes, AChars: LongInt; AKind: Byte; ASep: Byte); inline;
    procedure FinishLoad;
    procedure Emit(ASrc: Int64; ABytes, AChars: LongInt; AKind, ASep: Byte); inline;
    procedure Scan(ABuf: PByte; ACount: Int64; ABase: Int64; AKind: Byte);
    // pieces
    function AppendAdd(AData: Pointer; ACount: Int64): Int64;
    function DecodedOf(AItem: PTyRichPiece): RawByteString;
    procedure LazySlice(AItem: PTyRichPiece; AFrom, ATo: LongInt; out AText: RawByteString;
      out AByte0, AByte1: PtrInt);
    function PieceText(AItem: PTyRichPiece; out ALen: LongInt): PByte;
    procedure ConvertToAdded(var APath: TTyRichPath);
    function SplitAt(APos: TTyRichPos): LongInt;
    procedure CheckJunction(APos: TTyRichPos);
    procedure TrimPiece(AItem: PTyRichPiece; AFrom, ATo: LongInt; out APiece: TTyRichPiece);
    procedure InsertPieces(APos: TTyRichPos; var APieces: TTyRichPieceArray; ACount: Integer;
      const AFollow: array of Pointer);
    // paragraphs
    procedure CheckReady;
    procedure CheckPara(AIndex: Integer);
    procedure CheckRange(APos, ALen: TTyRichPos);
    procedure CheckNotWalking;
    function GetParaData(AIndex: Integer): Pointer;
    procedure SetParaData(AIndex: Integer; AValue: Pointer);
    procedure SetParaRaw(AIndex: Integer; AData: Pointer; AHeight: LongInt);
    function GetParaRawHeight(AIndex: Integer): LongInt;
    procedure PutHeights(AFirst, ALast: Integer; AHeights: PInt64);
    procedure SetDefaultParaHeight(AValue: Int64);
    procedure DoParasChanged(AFirst, AOldCount, ANewCount: Integer);
    function CheckNode(ANode: PTyRichNode; ALevel: Integer; var APrevSep: Boolean;
      var APrevLazyOpen: Boolean; var APrevLazy: Int64): string;
  public
    constructor Create;
    { The buffer is referenced, not copied; it must not change afterwards. }
    constructor CreateFromUtf8(const ABuffer: TBytes);
    { A text built from lazy paragraphs: call AppendLazyParagraph for each paragraph in
      order (source offsets strictly increasing; only the last may have rsNone), then
      EndLazyLoad. Nothing is decoded until it is read or edited. }
    constructor CreateLazy(AProvider: TTyRichTextProvider; AOwnsProvider: Boolean);
    procedure AppendLazyParagraph(ACharCount, ASrcOffset, ASrcBytes: Int64;
      ASeparator: TTyRichSeparator);
    { Ends the load, and one that was reopened: the paragraphs appended since come into the
      text without OnParasChanged - the reader that appended them reports its own change. }
    procedure EndLazyLoad;
    { Goes on with a lazy load that has ended, for a reader that indexes a file in slices
      while the part indexed so far is read: the last paragraph - still the one appended
      last, unedited - gets ALastSeparator, and the paragraphs AppendLazyParagraph adds
      until the next EndLazyLoad follow it (the text cannot be read in between). Its data
      and height move with it. Raises when the last paragraph is no longer that one. }
    procedure ReopenLazyLoad(ALastSeparator: TTyRichSeparator);
    { A text over a buffer whose pieces the reader finds itself while it writes the buffer
      (a converted file: decoding and indexing in one pass, with no scan afterwards). Call
      AppendScanned for every piece in order - each starts where the one before ended - and
      then EndScanned with the buffer they cover, which is referenced as CreateFromUtf8's.
      The pieces must be what CreateFromUtf8's scan would make of that buffer: one per
      separator (which ends it, its bytes included and counted as one character), and a
      piece without one where a paragraph reaches TyRichMaxPieceBytes and at the end; a byte
      that starts no valid UTF-8 sequence is one character, AInvalid of them in all. }
    constructor CreateScanned;
    procedure AppendScanned(ABytes, AChars: LongInt; ASeparator: TTyRichSeparator);
    procedure EndScanned(const ABuffer: TBytes; AInvalid: Int64);
    destructor Destroy; override;

    procedure Insert(APos: TTyRichPos; const AText: UTF8String);
    procedure Delete(APos, ALen: TTyRichPos);
    function Length: TTyRichPos;
    { Bytes the pieces cover; a lazy piece counts its bytes in the original file. }
    function ByteCount: Int64;
    { The stored bytes, separators as they are (a CRLF comes back as two bytes). }
    function GetText(APos, ALen: TTyRichPos): UTF8String;
    { Shows AProc the bytes of the range, piece by piece (see TTyRichByteRun). AProc may read
      the text - GetText, the lookups, paragraph data - and set paragraph data and heights.
      Changing the text (Insert, Delete, RestorePieces, ReopenLazyLoad) raises ETyRichText
      while the walk runs, as in MapParaData and WalkParas: a walk holds its place in the
      tree while foreign code runs, and an edit would leave it on freed nodes. }
    procedure ForEachRun(APos, ALen: TTyRichPos; AProc: TTyRichRunEvent);

    function ParaCount: Integer;
    function ParaStart(AIndex: Integer): TTyRichPos;
    function ParaLength(AIndex: Integer): TTyRichPos;
    function ParaOfPos(APos: TTyRichPos): Integer;
    function ParaSeparator(AIndex: Integer): TTyRichSeparator;
    { True when paragraph AIndex is a lazy paragraph that was never edited (it may have been
      read): its bytes in the original file. }
    function ParaLazySource(AIndex: Integer; out ASrcOffset, ASrcBytes: Int64): Boolean;
    { The paragraph that is the unedited lazy paragraph from ASrcOffset, or -1. One
      root-to-leaf walk: lazy pieces stay in the order of their offsets (edits make new
      pieces; a restore puts pieces back where they were). }
    function ParaOfLazySource(ASrcOffset: Int64): Integer;
    { Lets the decoded text of the lazy paragraph from ASrcOffset go (it is decoded again
      when it is read again); does nothing when it is not decoded. }
    procedure ForgetDecoded(ASrcOffset: Int64);
    function IsDecoded(ASrcOffset: Int64): Boolean;
    { Bytes of decoded lazy text held (separators included). }
    property DecodedBytes: Int64 read FDecodedBytes;
    { How many separators of the kind CreateFromUtf8's scan found in the buffer (0 for
      rsNone and for the other constructors). Counted during that one pass, so a file's
      majority line break costs nothing more; edits do not change it. }
    function LoadedSeparators(ASep: TTyRichSeparator): Int64;
    { Bytes of the buffer CreateFromUtf8's scan found that are not part of a valid UTF-8
      sequence (each is a character of its own); 0: the buffer is valid UTF-8. Counted in
      the same pass, so telling UTF-8 from other text costs no pass of its own. }
    property LoadedInvalidBytes: Int64 read FLoadInvalid;

    function PieceSnapshot(APos, ALen: TTyRichPos): TTyRichPieces;
    { Puts a snapshot's pieces back at APos - the position it was taken from, after the range
      was deleted (an undo). Lazy pieces must stay in the order of their source offsets,
      which ParaOfLazySource walks by: pieces put anywhere else, or a second time, break it
      and CheckIntegrity says so. }
    procedure RestorePieces(APos: TTyRichPos; const P: TTyRichPieces);

    { The height index. A paragraph is measured - it has a height the layout gave it,
      0..TyRichMaxParaHeight, and 0 is a height like any other - or unmeasured: every
      paragraph is until a height is set (after a load, a restore, and the paragraphs a
      split adds), and an unmeasured paragraph counts as DefaultParaHeight everywhere below.
      So the layout sets one estimate and measures only what it shows; nothing here ever
      needs a pass over the document.

      Edits do not touch heights: a paragraph whose text changed keeps its height (now an
      estimate; OnParasChanged names it), a split leaves the height with the first part, a
      merge keeps the first paragraph's.

      Costs: SetParaHeight one descent, the sums on the path changed by the difference (no
      node is recomputed); SetParaHeights and UnmeasureParas one descent, then leaf by
      leaf; UnmeasureAll, DefaultParaHeight, TotalHeight and MeasuredParaCount O(1);
      ParaHeight, ParaMeasured, ParaTop and ParaAtHeight one descent. }
    procedure SetParaHeight(AIndex: Integer; AHeight: Int64);
    { Paragraphs AFirst .. AFirst + Length(AHeights) - 1 get the heights given, in order. }
    procedure SetParaHeights(AFirst: Integer; const AHeights: array of Int64);
    { Paragraphs AFirst..ALast lose their measured height. }
    procedure UnmeasureParas(AFirst, ALast: Integer);
    { Every paragraph loses its measured height (the width or the zoom changed). Nothing is
      walked: each node drops its heights when a lookup next enters it. }
    procedure UnmeasureAll;
    function ParaMeasured(AIndex: Integer): Boolean;
    function MeasuredParaCount: Integer;
    { The measured height, or DefaultParaHeight for an unmeasured paragraph. }
    function ParaHeight(AIndex: Integer): Int64;
    { The sum of ParaHeight of the paragraphs before AIndex. }
    function ParaTop(AIndex: Integer): Int64;
    { The paragraph that covers row AY: the first one, in order, with
      ParaTop + ParaHeight > AY. A paragraph of height 0 covers no row, so it is never the
      answer for a row inside the document; it sits at its successor's top
      (ParaTop(i) = ParaTop(i + 1)). AY < 0 answers 0. AY at or past TotalHeight answers
      the last paragraph - also when the total is 0, which is every AY while nothing is
      measured and DefaultParaHeight is 0: set the default before asking. }
    function ParaAtHeight(AY: Int64): Integer;
    { The sum of ParaHeight over all paragraphs. }
    function TotalHeight: Int64;
    { What an unmeasured paragraph counts as; 0 at first. Setting it changes ParaHeight,
      ParaTop, ParaAtHeight and TotalHeight at once and touches no node. }
    property DefaultParaHeight: Int64 read FDefaultHeight write SetDefaultParaHeight;

    function PieceCount: Integer;
    { Levels of inner nodes above the leaves (for tests). }
    function TreeDepth: Integer;
    { '' when every summary and invariant holds, else the first problem (for tests). }
    function CheckIntegrity: string;

    { nil by default. A split leaves it with the first part and gives the new paragraph
      nil; a merge keeps the first paragraph's and reports the others to OnParaDataDropped
      (the text never frees anything, also not on Destroy). }
    property ParaData[AIndex: Integer]: Pointer read GetParaData write SetParaData;
    { Gives the data of paragraphs AFirst..ALast, in order, to AMap and puts what it returns
      in each slot. One descent, then leaf by leaf: n paragraphs cost O(log n + n), not a
      lookup each (a format change over the whole document). AMap may read the text and set
      paragraph data or heights; changing the text (Insert, Delete, RestorePieces) raises
      while the walk runs. Nodes the walk moves into count in NodeVisits. }
    procedure MapParaData(AFirst, ALast: Integer; AMap: TTyRichParaDataMap);
    { Shows AProc every paragraph from AFirst on, in order: its data and, for one that is
      still the unedited lazy paragraph, where its bytes are in the original file - what
      ParaData and ParaLazySource give, without a lookup per paragraph (one descent, then
      piece by piece: a writer goes through millions of them). AProc may read the text and
      set paragraph data; changing the text raises while the walk runs. }
    procedure WalkParas(AFirst: Integer; AProc: TTyRichParaWalk);
    property AddedBytes: Int64 read FAddLen;
    { Tree nodes entered by lookups, for tests that check the index stays logarithmic. }
    property NodeVisits: Int64 read FNodeVisits write FNodeVisits;
    { Nodes whose summary was recomputed from their contents, for tests: an edit does that
      along its path, setting a height must not. }
    property SumScans: Int64 read FSumScans;
    property OnParasChanged: TTyRichParasChangedEvent read FOnParasChanged
      write FOnParasChanged;
    property OnParaDataDropped: TTyRichParaDataEvent read FOnParaDataDropped
      write FOnParaDataDropped;
  end;

implementation

const
  SrcMask = (Int64(1) shl 56) - 1;
  // stored kinds (3 is unused: whether a lazy piece is decoded is FDecoded's business, so
  // its text can be let go of again)
  kOrig = 0;
  kAdded = 1;
  kLazy = 2;
  // stored separators match Ord(TTyRichSeparator)
  sNone = 0;
  sCR = 1;
  sLF = 2;
  sCRLF = 3;
  MaxPieceBytes = TyRichMaxPieceBytes;
  // an insert's scan buffer is kept for the next insert up to this many pieces
  ScanKeep = 1024;

{ ---- pieces ---- }

function PKind(const P: TTyRichPiece): Byte; inline;
begin
  Result := (P.FSrc shr 56) and 3;
end;

function PSep(const P: TTyRichPiece): Byte; inline;
begin
  Result := (P.FSrc shr 58) and 3;
end;

function POff(const P: TTyRichPiece): Int64; inline;
begin
  Result := P.FSrc and SrcMask;
end;

function MakeSrc(AOff: Int64; AKind, ASep: Byte): Int64; inline;
begin
  Result := AOff or (Int64(AKind) shl 56) or (Int64(ASep) shl 58);
end;

function SepBytes(ASep: Byte): Integer; inline;
begin
  case ASep of
    sCR, sLF: Result := 1;
    sCRLF: Result := 2;
  else
    Result := 0;
  end;
end;

function IsLazy(const P: TTyRichPiece): Boolean; inline;
begin
  Result := PKind(P) = kLazy;
end;

function TTyRichPiece.Kind: TTyRichPieceKind;
begin
  case PKind(Self) of
    kOrig: Result := rpkOriginal;
    kAdded: Result := rpkAdded;
  else
    Result := rpkLazy;
  end;
end;

function TTyRichPiece.Separator: TTyRichSeparator;
begin
  Result := TTyRichSeparator(PSep(Self));
end;

function TTyRichPiece.SrcOffset: Int64;
begin
  Result := POff(Self);
end;

function TTyRichPiece.ByteCount: Integer;
begin
  Result := FBytes;
end;

function TTyRichPiece.CharCount: Integer;
begin
  Result := FChars;
end;

function TTyRichPiece.Data: Pointer;
begin
  Result := FData;
end;

{ ---- UTF-8 ---- }

{ The length of the valid UTF-8 sequence at P, or 1 when the byte there does not start one
  (it is then a character on its own). Strict: no overlongs, surrogates or > U+10FFFF. }
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

function CountChars(P: PByte; ACount: PtrInt): PtrInt;
var
  stop: PByte;
begin
  Result := 0;
  stop := P + ACount;
  while P < stop do
  begin
    if P^ < $80 then Inc(P) else Inc(P, SeqLen(P, stop - P));
    Inc(Result);
  end;
end;

{ Byte offset of character AChars in the separator-free bytes P[0..ACount). This is the
  scan inside one piece every position lookup ends with, so ASCII goes eight bytes at a
  time and CJK's three-byte sequences are checked inline. }
{$PUSH}{$Q-}{$R-}
function ByteOfChar(P: PByte; ACount: PtrInt; AChars: PtrInt): PtrInt;
var
  q, stop: PByte;
  b: Byte;
begin
  q := P;
  stop := P + ACount;
  while (AChars > 0) and (q < stop) do
  begin
    if (AChars >= 8) and (stop - q >= 8) and
       (unaligned(PQWord(q)^) and QWord($8080808080808080) = 0) then
    begin
      Inc(q, 8);
      Dec(AChars, 8);
      Continue;
    end;
    b := q^;
    if b < $80 then
      Inc(q)
    else if (b and $F0 = $E0) and (b <> $E0) and (b <> $ED) and (stop - q >= 3) and
            (unaligned(PWord(q + 1)^) and $C0C0 = $8080) then
      Inc(q, 3)
    else
      Inc(q, SeqLen(q, stop - q));
    Dec(AChars);
  end;
  Result := q - P;
end;
{$POP}

function HasBreak(P: PByte; ACount: PtrInt): Boolean;
var
  i: PtrInt;
begin
  for i := 0 to ACount - 1 do
    if (P[i] = 10) or (P[i] = 13) then Exit(True);
  Result := False;
end;

{ ---- TTyRichText: tree ---- }

function TTyRichText.NewNode(ALeaf: Boolean): PTyRichNode;
begin
  if ALeaf then
    Result := GetMem(SizeOf(TTyRichLeaf))
  else
    Result := GetMem(SizeOf(TTyRichInner));
  Result^.Count := 0;
  Result^.IsLeaf := ALeaf;
  Result^.HeightEpoch := FHeightEpoch;
end;

procedure TTyRichText.FreeNode(ANode: PTyRichNode);
var
  i: Integer;
begin
  if ANode = nil then Exit;
  if not ANode^.IsLeaf then
    for i := 0 to ANode^.Count - 1 do
      FreeNode(PTyRichInner(ANode)^.Child[i]);
  FreeMem(ANode);
end;

function TTyRichText.NodeSum(ANode: PTyRichNode): TTyRichSum;
var
  i: Integer;
  leaf: PTyRichLeaf;
  inner: PTyRichInner;
  heights: Boolean;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.LazyMax := -1;
  Inc(FSumScans);
  // a node UnmeasureAll left behind holds no heights, whatever is still written in it
  heights := ANode^.HeightEpoch = FHeightEpoch;
  if ANode^.IsLeaf then
  begin
    leaf := PTyRichLeaf(ANode);
    Result.Entries := leaf^.Count;
    for i := 0 to leaf^.Count - 1 do
    begin
      if PSep(leaf^.Items[i]) <> sNone then Inc(Result.Seps);
      Inc(Result.Chars, leaf^.Items[i].FChars);
      Inc(Result.Bytes, leaf^.Items[i].FBytes);
      if heights and (leaf^.Items[i].FHeight > 0) then
      begin
        Inc(Result.Measured);
        Inc(Result.Height, leaf^.Items[i].FHeight - 1);
      end;
      if IsLazy(leaf^.Items[i]) and (POff(leaf^.Items[i]) > Result.LazyMax) then
        Result.LazyMax := POff(leaf^.Items[i]);
    end;
  end
  else
  begin
    inner := PTyRichInner(ANode);
    for i := 0 to inner^.Count - 1 do
    begin
      Inc(Result.Entries, inner^.Sum[i].Entries);
      Inc(Result.Seps, inner^.Sum[i].Seps);
      Inc(Result.Chars, inner^.Sum[i].Chars);
      Inc(Result.Bytes, inner^.Sum[i].Bytes);
      if heights then
      begin
        Inc(Result.Measured, inner^.Sum[i].Measured);
        Inc(Result.Height, inner^.Sum[i].Height);
      end;
      if inner^.Sum[i].LazyMax > Result.LazyMax then Result.LazyMax := inner^.Sum[i].LazyMax;
    end;
  end;
end;

{ Brings a node UnmeasureAll left behind up to date: its heights are gone. Everything that
  reads or writes a height in a node, or moves its contents into another, settles it first;
  a path made by Descend and moved by Advance holds settled nodes only. }
procedure TTyRichText.Settle(ANode: PTyRichNode);
begin
  if ANode^.HeightEpoch <> FHeightEpoch then DropHeights(ANode);
end;

procedure TTyRichText.DropHeights(ANode: PTyRichNode);
var
  i: Integer;
begin
  if ANode^.IsLeaf then
    for i := 0 to ANode^.Count - 1 do
      PTyRichLeaf(ANode)^.Items[i].FHeight := 0
  else
    for i := 0 to ANode^.Count - 1 do
    begin
      PTyRichInner(ANode)^.Sum[i].Height := 0;
      PTyRichInner(ANode)^.Sum[i].Measured := 0;
    end;
  ANode^.HeightEpoch := FHeightEpoch;
end;

{ The height of what a summary covers: its measured heights, and the default for the rest. }
function TTyRichText.SumHeight(const ASum: TTyRichSum): Int64;
begin
  Result := ASum.Height + Int64(ASum.Seps - ASum.Measured) * FDefaultHeight;
end;

{ The height of the paragraph a separator piece ends. }
function TTyRichText.PieceHeight(const APiece: TTyRichPiece): Int64;
begin
  if APiece.FHeight > 0 then Result := APiece.FHeight - 1 else Result := FDefaultHeight;
end;

{ A height changed in the leaf the path ends in: the sums above it change by the difference. }
procedure TTyRichText.AddToPath(const APath: TTyRichPath; AHeight: Int64; AMeasured: Integer);
var
  l: Integer;
begin
  if (AHeight = 0) and (AMeasured = 0) then Exit;
  for l := FDepth downto 1 do
    with PTyRichInner(APath.Steps[l - 1].Node)^.Sum[APath.Steps[l - 1].Index] do
    begin
      Inc(Height, AHeight);
      Inc(Measured, AMeasured);
    end;
  Inc(FTotal.Height, AHeight);
  Inc(FTotal.Measured, AMeasured);
end;

{ Walks one root-to-leaf path to the piece the key falls in: the AKey-th piece, the piece
  holding character AKey, the AKey-th separator piece, or the piece whose height range
  holds AKey (an unmeasured paragraph being DefaultParaHeight high). ABefore sums everything
  in front of it. When the key is past the end the path ends one past the last piece and
  the result is False. Every node on the path is settled. }
function TTyRichText.Descend(AMode: TTyRichSeek; AKey: Int64; out APath: TTyRichPath;
  out ABefore: TTyRichSum): Boolean;
var
  node: PTyRichNode;
  inner: PTyRichInner;
  leaf: PTyRichLeaf;
  lvl, i: Integer;
  hit, sep: Boolean;
  h: Int64;
begin
  FillChar(ABefore, SizeOf(ABefore), 0);
  h := 0;
  node := FRoot;
  lvl := 0;
  while not node^.IsLeaf do
  begin
    Inc(FNodeVisits);
    Settle(node);
    inner := PTyRichInner(node);
    i := 0;
    while i < inner^.Count - 1 do
    begin
      with inner^.Sum[i] do
      begin
        case AMode of
          rskEntry: hit := AKey < Entries;
          rskChar: hit := AKey < Chars;
          rskSep: hit := AKey < Seps;
        else
          h := Height + Int64(Seps - Measured) * FDefaultHeight;
          hit := AKey < h;
        end;
        if hit then Break;
        case AMode of
          rskEntry: Dec(AKey, Entries);
          rskChar: Dec(AKey, Chars);
          rskSep: Dec(AKey, Seps);
        else
          Dec(AKey, h);
        end;
        Inc(ABefore.Entries, Entries);
        Inc(ABefore.Seps, Seps);
        Inc(ABefore.Chars, Chars);
        Inc(ABefore.Bytes, Bytes);
        Inc(ABefore.Height, Height);
        Inc(ABefore.Measured, Measured);
      end;
      Inc(i);
    end;
    APath.Steps[lvl].Node := node;
    APath.Steps[lvl].Index := i;
    node := inner^.Child[i];
    Inc(lvl);
  end;
  Inc(FNodeVisits);
  Settle(node);
  leaf := PTyRichLeaf(node);
  APath.Steps[lvl].Node := node;
  for i := 0 to leaf^.Count - 1 do
    with leaf^.Items[i] do
    begin
      sep := PSep(leaf^.Items[i]) <> sNone;
      case AMode of
        rskEntry: hit := AKey = 0;
        rskChar: hit := AKey < FChars;
        rskSep: hit := sep and (AKey = 0);
      else
        // only a separator piece stands for a paragraph; a height of 0 holds no key
        if sep then h := PieceHeight(leaf^.Items[i]) else h := 0;
        hit := AKey < h;
      end;
      if hit then
      begin
        APath.Steps[lvl].Index := i;
        Exit(True);
      end;
      case AMode of
        rskEntry: Dec(AKey);
        rskChar: Dec(AKey, FChars);
        rskSep: if sep then Dec(AKey);
      else
        Dec(AKey, h);
      end;
      Inc(ABefore.Entries);
      if sep then Inc(ABefore.Seps);
      Inc(ABefore.Chars, FChars);
      Inc(ABefore.Bytes, FBytes);
      if FHeight > 0 then
      begin
        Inc(ABefore.Height, FHeight - 1);
        Inc(ABefore.Measured);
      end;
    end;
  APath.Steps[lvl].Index := leaf^.Count;
  Result := False;
end;

{ Descend for a key that must be inside the text. A miss means the summaries are broken;
  using the path then would read and write past a leaf's pieces. }
procedure TTyRichText.Find(AMode: TTyRichSeek; AKey: Int64; out APath: TTyRichPath;
  out ABefore: TTyRichSum);
begin
  if not Descend(AMode, AKey, APath, ABefore) then
    raise ETyRichText.Create('Rich text index is inconsistent');
end;

function TTyRichText.ItemAt(const APath: TTyRichPath): PTyRichPiece;
begin
  Result := @PTyRichLeaf(APath.Steps[FDepth].Node)^.Items[APath.Steps[FDepth].Index];
end;

{ Moves the path to the next piece; False at the end. The nodes it enters are settled, and
  counted in NodeVisits when asked. }
function TTyRichText.Advance(var APath: TTyRichPath; ACountVisits: Boolean): Boolean;
var
  l, d: Integer;
begin
  Inc(APath.Steps[FDepth].Index);
  if APath.Steps[FDepth].Index < APath.Steps[FDepth].Node^.Count then Exit(True);
  l := FDepth;
  repeat
    Dec(l);
    if l < 0 then Exit(False);
    Inc(APath.Steps[l].Index);
  until APath.Steps[l].Index < APath.Steps[l].Node^.Count;
  for d := l + 1 to FDepth do
  begin
    APath.Steps[d].Node := PTyRichInner(APath.Steps[d - 1].Node)^.Child[APath.Steps[d - 1].Index];
    APath.Steps[d].Index := 0;
    Settle(APath.Steps[d].Node);
  end;
  if ACountVisits then Inc(FNodeVisits, FDepth - l);
  Result := True;
end;

{ Recomputes the summaries from the node at ALevel up to the root. }
procedure TTyRichText.FixUp(var APath: TTyRichPath; ALevel: Integer);
var
  l: Integer;
begin
  for l := ALevel downto 1 do
    PTyRichInner(APath.Steps[l - 1].Node)^.Sum[APath.Steps[l - 1].Index] :=
      NodeSum(APath.Steps[l].Node);
  FTotal := NodeSum(FRoot);
end;

{ Splits the node at ALevel into [0, AAt) and [AAt, Count), the new right half going in
  after it in the parent (split first when full). The path stays valid at every level: it
  follows its own index into whichever half holds it. }
procedure TTyRichText.SplitNode(var APath: TTyRichPath; ALevel, AAt: Integer);
var
  root, pa: PTyRichInner;
  n, n2: PTyRichNode;
  l, idx, oldDepth, moved: Integer;
begin
  if ALevel = 0 then
  begin
    if FDepth >= TyRichMaxDepth then
      raise ETyRichText.Create('Rich text index too deep');
    root := PTyRichInner(NewNode(False));
    root^.Count := 1;
    root^.Child[0] := FRoot;
    root^.Sum[0] := NodeSum(FRoot);
    FRoot := PTyRichNode(root);
    for l := FDepth downto 0 do
      APath.Steps[l + 1] := APath.Steps[l];
    APath.Steps[0].Node := PTyRichNode(root);
    APath.Steps[0].Index := 0;
    Inc(FDepth);
    ALevel := 1;
  end;
  pa := PTyRichInner(APath.Steps[ALevel - 1].Node);
  if pa^.Count = TyRichInnerCap then
  begin
    oldDepth := FDepth;
    SplitNode(APath, ALevel - 1, TyRichInnerCap div 2);
    Inc(ALevel, FDepth - oldDepth);
    pa := PTyRichInner(APath.Steps[ALevel - 1].Node);
  end;
  n := APath.Steps[ALevel].Node;
  idx := APath.Steps[ALevel - 1].Index;
  // n is on the path, so it is settled: what moves into the new node counts as it stands
  n2 := NewNode(n^.IsLeaf);
  moved := n^.Count - AAt;
  if n^.IsLeaf then
  begin
    if moved > 0 then
      Move(PTyRichLeaf(n)^.Items[AAt], PTyRichLeaf(n2)^.Items[0], moved * SizeOf(TTyRichPiece));
  end
  else if moved > 0 then
  begin
    Move(PTyRichInner(n)^.Child[AAt], PTyRichInner(n2)^.Child[0], moved * SizeOf(PTyRichNode));
    Move(PTyRichInner(n)^.Sum[AAt], PTyRichInner(n2)^.Sum[0], moved * SizeOf(TTyRichSum));
  end;
  n2^.Count := moved;
  n^.Count := AAt;
  if idx + 1 < pa^.Count then
  begin
    Move(pa^.Child[idx + 1], pa^.Child[idx + 2], (pa^.Count - idx - 1) * SizeOf(PTyRichNode));
    Move(pa^.Sum[idx + 1], pa^.Sum[idx + 2], (pa^.Count - idx - 1) * SizeOf(TTyRichSum));
  end;
  pa^.Child[idx + 1] := n2;
  pa^.Sum[idx] := NodeSum(n);
  pa^.Sum[idx + 1] := NodeSum(n2);
  Inc(pa^.Count);
  if APath.Steps[ALevel].Index >= AAt then
  begin
    APath.Steps[ALevel].Node := n2;
    Dec(APath.Steps[ALevel].Index, AAt);
    APath.Steps[ALevel - 1].Index := idx + 1;
  end;
end;

{ Unlinks and frees the (empty) node at ALevel, and its parent too when that empties. }
procedure TTyRichText.RemoveNode(var APath: TTyRichPath; ALevel: Integer);
var
  pa: PTyRichInner;
  idx: Integer;
begin
  pa := PTyRichInner(APath.Steps[ALevel - 1].Node);
  idx := APath.Steps[ALevel - 1].Index;
  FreeNode(APath.Steps[ALevel].Node);
  if idx < pa^.Count - 1 then
  begin
    Move(pa^.Child[idx + 1], pa^.Child[idx], (pa^.Count - idx - 1) * SizeOf(PTyRichNode));
    Move(pa^.Sum[idx + 1], pa^.Sum[idx], (pa^.Count - idx - 1) * SizeOf(TTyRichSum));
  end;
  Dec(pa^.Count);
  if (pa^.Count = 0) and (ALevel - 1 > 0) then
    RemoveNode(APath, ALevel - 1)
  else
  begin
    if pa^.Count > 0 then
      APath.Steps[ALevel - 1].Index := 0;
    FixUp(APath, ALevel - 1);
    Rebalance(APath, ALevel - 1);
  end;
end;

{ Merges a node that fell under a quarter full into a neighbour when both fit in one. }
procedure TTyRichText.Rebalance(var APath: TTyRichPath; ALevel: Integer);
var
  n, nl, nr: PTyRichNode;
  pa: PTyRichInner;
  idx, li, ri, cap: Integer;
begin
  if ALevel <= 0 then Exit;
  n := APath.Steps[ALevel].Node;
  if n^.IsLeaf then cap := TyRichLeafCap else cap := TyRichInnerCap;
  if n^.Count >= cap div 4 then Exit;
  pa := PTyRichInner(APath.Steps[ALevel - 1].Node);
  idx := APath.Steps[ALevel - 1].Index;
  if idx + 1 < pa^.Count then
  begin
    li := idx;
    ri := idx + 1;
  end
  else if idx > 0 then
  begin
    li := idx - 1;
    ri := idx;
  end
  else
    Exit;
  nl := pa^.Child[li];
  nr := pa^.Child[ri];
  if nl^.Count + nr^.Count > cap then Exit;
  // the neighbour is not on the path: it may still hold heights UnmeasureAll took away
  Settle(nl);
  Settle(nr);
  if nl^.IsLeaf then
    Move(PTyRichLeaf(nr)^.Items[0], PTyRichLeaf(nl)^.Items[nl^.Count],
      nr^.Count * SizeOf(TTyRichPiece))
  else
  begin
    Move(PTyRichInner(nr)^.Child[0], PTyRichInner(nl)^.Child[nl^.Count],
      nr^.Count * SizeOf(PTyRichNode));
    Move(PTyRichInner(nr)^.Sum[0], PTyRichInner(nl)^.Sum[nl^.Count],
      nr^.Count * SizeOf(TTyRichSum));
  end;
  Inc(nl^.Count, nr^.Count);
  FreeMem(nr);
  pa^.Sum[li] := NodeSum(nl);
  if ri < pa^.Count - 1 then
  begin
    Move(pa^.Child[ri + 1], pa^.Child[ri], (pa^.Count - ri - 1) * SizeOf(PTyRichNode));
    Move(pa^.Sum[ri + 1], pa^.Sum[ri], (pa^.Count - ri - 1) * SizeOf(TTyRichSum));
  end;
  Dec(pa^.Count);
  APath.Steps[ALevel - 1].Index := li;
  APath.Steps[ALevel].Node := nl;
  FixUp(APath, ALevel - 1);
  Rebalance(APath, ALevel - 1);
end;

procedure TTyRichText.CollapseRoot;
var
  child: PTyRichNode;
begin
  while (FDepth > 0) and (FRoot^.Count = 1) do
  begin
    child := PTyRichInner(FRoot)^.Child[0];
    FreeMem(FRoot);
    FRoot := child;
    Dec(FDepth);
  end;
  if (FDepth > 0) and (FRoot^.Count = 0) then
  begin
    FreeMem(FRoot);
    FRoot := NewNode(True);
    FDepth := 0;
  end;
  FTotal := NodeSum(FRoot);
end;

{ Puts AItems in front of piece AAt (AAt = PieceCount appends). When they do not fit in
  the leaf: a few pieces going inside it (typing, a replace - and after a load every leaf is
  full) split the leaf in the middle and go in place, so both halves have room for the
  inserts that follow; a big run, or one at the leaf's end, sets the leaf's tail aside and
  is appended leaf after full leaf, so a big restore and a load that goes on pack the
  leaves instead of leaving them half full. }
procedure TTyRichText.InsertEntries(AAt: LongInt; const AItems: array of TTyRichPiece);
var
  p: TTyRichPath;
  before: TTyRichSum;
  leaf: PTyRichLeaf;
  idx, n: Integer;
  tail: TTyRichPieceArray;

  procedure AppendRun(const ASrc: array of TTyRichPiece; AFrom, ACount: Integer);
  var
    k: Integer;
  begin
    while ACount > 0 do
    begin
      leaf := PTyRichLeaf(p.Steps[FDepth].Node);
      if leaf^.Count = TyRichLeafCap then
      begin
        // no FixUp needed first: the split recomputes both halves from their contents,
        // and the FixUp after the last run covers the path it ends on
        p.Steps[FDepth].Index := leaf^.Count;
        SplitNode(p, FDepth, leaf^.Count);
        leaf := PTyRichLeaf(p.Steps[FDepth].Node);
      end;
      k := TyRichLeafCap - leaf^.Count;
      if k > ACount then k := ACount;
      Move(ASrc[AFrom], leaf^.Items[leaf^.Count], k * SizeOf(TTyRichPiece));
      Inc(leaf^.Count, k);
      p.Steps[FDepth].Index := leaf^.Count;
      Inc(AFrom, k);
      Dec(ACount, k);
    end;
  end;

begin
  n := System.Length(AItems);
  if n = 0 then Exit;
  Descend(rskEntry, AAt, p, before);
  leaf := PTyRichLeaf(p.Steps[FDepth].Node);
  idx := p.Steps[FDepth].Index;
  if (leaf^.Count + n > TyRichLeafCap) and (n <= TyRichLeafCap div 2) and
     (idx < leaf^.Count) then
  begin
    // packing here would leave this leaf full and put the one piece that no longer fits
    // in a leaf of its own - again at the next insert into it, a leaf per piece
    SplitNode(p, FDepth, leaf^.Count div 2);
    leaf := PTyRichLeaf(p.Steps[FDepth].Node);
    idx := p.Steps[FDepth].Index;
  end;
  if leaf^.Count + n <= TyRichLeafCap then
  begin
    if idx < leaf^.Count then
      Move(leaf^.Items[idx], leaf^.Items[idx + n], (leaf^.Count - idx) * SizeOf(TTyRichPiece));
    Move(AItems[0], leaf^.Items[idx], n * SizeOf(TTyRichPiece));
    Inc(leaf^.Count, n);
    FixUp(p, FDepth);
    Exit;
  end;
  tail := nil;
  SetLength(tail, leaf^.Count - idx);
  if System.Length(tail) > 0 then
    Move(leaf^.Items[idx], tail[0], System.Length(tail) * SizeOf(TTyRichPiece));
  leaf^.Count := idx;
  AppendRun(AItems, 0, n);
  if System.Length(tail) > 0 then
    AppendRun(tail, 0, System.Length(tail));
  FixUp(p, FDepth);
end;

procedure TTyRichText.DeleteEntries(AFirst, ACount: LongInt);
var
  p: TTyRichPath;
  before: TTyRichSum;
  leaf: PTyRichLeaf;
  idx, k: Integer;
begin
  while ACount > 0 do
  begin
    Descend(rskEntry, AFirst, p, before);
    leaf := PTyRichLeaf(p.Steps[FDepth].Node);
    idx := p.Steps[FDepth].Index;
    k := leaf^.Count - idx;
    if k > ACount then k := ACount;
    // only a broken summary can point past a leaf's pieces; looping on it would hang
    if k <= 0 then
      raise ETyRichText.Create('Rich text index is inconsistent');
    if (k = leaf^.Count) and (FDepth > 0) then
      RemoveNode(p, FDepth)
    else
    begin
      if idx + k < leaf^.Count then
        Move(leaf^.Items[idx + k], leaf^.Items[idx], (leaf^.Count - idx - k) * SizeOf(TTyRichPiece));
      Dec(leaf^.Count, k);
      FixUp(p, FDepth);
      Rebalance(p, FDepth);
    end;
    Dec(ACount, k);
  end;
  CollapseRoot;
end;

{ ---- loading ---- }

procedure TTyRichText.LoadPiece(ASrc: Int64; ABytes, AChars: LongInt; AKind: Byte; ASep: Byte);
var
  it: PTyRichPiece;
begin
  if FLoadLeaf^.Count = TyRichLeafCap then
  begin
    FLoadLeaves.Add(FLoadLeaf);
    FLoadLeaf := PTyRichLeaf(NewNode(True));
  end;
  it := @FLoadLeaf^.Items[FLoadLeaf^.Count];
  it^.FSrc := MakeSrc(ASrc, AKind, ASep);
  it^.FBytes := ABytes;
  it^.FChars := AChars;
  it^.FHeight := 0;
  it^.FData := nil;
  Inc(FLoadLeaf^.Count);
end;

{ Builds the inner levels over the packed leaves, bottom up. }
procedure TTyRichText.FinishLoad;
var
  level, next: TFPList;
  groups, g, size, i, k: Integer;
  inner: PTyRichInner;
begin
  if (FLoadLeaf^.Count > 0) or (FLoadLeaves.Count = 0) then
    FLoadLeaves.Add(FLoadLeaf)
  else
    FreeMem(FLoadLeaf);
  FLoadLeaf := nil;
  level := FLoadLeaves;
  FLoadLeaves := nil;
  FDepth := 0;
  try
    while level.Count > 1 do
    begin
      next := TFPList.Create;
      groups := (level.Count + TyRichInnerCap - 1) div TyRichInnerCap;
      i := 0;
      for g := 0 to groups - 1 do
      begin
        size := level.Count div groups;
        if g < level.Count mod groups then Inc(size);
        inner := PTyRichInner(NewNode(False));
        for k := 0 to size - 1 do
        begin
          inner^.Child[k] := PTyRichNode(level[i]);
          inner^.Sum[k] := NodeSum(PTyRichNode(level[i]));
          Inc(i);
        end;
        inner^.Count := size;
        next.Add(inner);
      end;
      level.Free;
      level := next;
      Inc(FDepth);
    end;
    FRoot := PTyRichNode(level[0]);
  finally
    level.Free;
  end;
  FTotal := NodeSum(FRoot);
  FLoading := False;
end;

procedure TTyRichText.Emit(ASrc: Int64; ABytes, AChars: LongInt; AKind, ASep: Byte);
begin
  if FScanToLoad then
    LoadPiece(ASrc, ABytes, AChars, AKind, ASep)
  else
  begin
    if FScanCount = System.Length(FScan) then
      SetLength(FScan, FScanCount * 2 + 4);
    with FScan[FScanCount] do
    begin
      FSrc := MakeSrc(ASrc, AKind, ASep);
      FBytes := ABytes;
      FChars := AChars;
      FHeight := 0;
      FData := nil;
    end;
    Inc(FScanCount);
  end;
end;

{ The one pass over a whole document the UI thread is allowed: a tight loop, a call per
  paragraph, nothing per character. Pieces end at separators and at MaxPieceBytes. A run
  of printable ASCII is skipped eight bytes at a time (no high bit, none below 14) and
  counted by its length; a run of non-ASCII checks the three-byte sequences CJK text is
  made of inline and leaves the rest to SeqLen. }
{$PUSH}{$Q-}{$R-}
procedure TTyRichText.Scan(ABuf: PByte; ACount: Int64; ABase: Int64; AKind: Byte);
const
  High8 = QWord($8080808080808080);
  Below14 = QWord($0E0E0E0E0E0E0E0E);
var
  p, q, bufEnd, start, chunkEnd: PByte;
  chars, bad: PtrInt;
  n: Integer;
  b, sep: Byte;
  x: QWord;
begin
  p := ABuf;
  bufEnd := ABuf + ACount;
  bad := 0;
  start := p;
  chars := 0;
  while p < bufEnd do
  begin
    if bufEnd - start > MaxPieceBytes then chunkEnd := start + MaxPieceBytes
    else chunkEnd := bufEnd;
    while p < chunkEnd do
    begin
      b := p^;
      if (b > 13) and (b < $80) then
      begin
        q := p;
        while chunkEnd - p >= 8 do
        begin
          x := unaligned(PQWord(p)^);
          if (x or ((x - Below14) and not x)) and High8 <> 0 then Break;
          Inc(p, 8);
        end;
        while (p < chunkEnd) and (p^ > 13) and (p^ < $80) do Inc(p);
        Inc(chars, p - q);
      end
      else if b >= $80 then
        repeat
          if (p^ and $F0 = $E0) and (p^ <> $E0) and (p^ <> $ED) and (bufEnd - p >= 3) and
             (unaligned(PWord(p + 1)^) and $C0C0 = $8080) then
            Inc(p, 3)
          else
          begin
            n := SeqLen(p, bufEnd - p);
            // a byte from $80 up that starts no sequence: the buffer is not valid UTF-8
            if n = 1 then Inc(bad);
            Inc(p, n);
          end;
          Inc(chars);
        until (p >= chunkEnd) or (p^ < $80)
      else if (b = 10) or (b = 13) then
      begin
        Inc(p);
        if b = 10 then sep := sLF
        else if (p < bufEnd) and (p^ = 10) then
        begin
          Inc(p);
          sep := sCRLF;
        end
        else
          sep := sCR;
        if FScanToLoad then Inc(FLoadSeps[sep]);
        Emit(ABase + (start - ABuf), p - start, chars + 1, AKind, sep);
        start := p;
        chars := 0;
        if bufEnd - start > MaxPieceBytes then chunkEnd := start + MaxPieceBytes
        else chunkEnd := bufEnd;
      end
      else
      begin
        Inc(p);
        Inc(chars);
      end;
    end;
    if (p < bufEnd) and (p > start) then
    begin
      Emit(ABase + (start - ABuf), p - start, chars, AKind, sNone);
      start := p;
      chars := 0;
    end;
  end;
  if p > start then
    Emit(ABase + (start - ABuf), p - start, chars, AKind, sNone);
  if FScanToLoad then Inc(FLoadInvalid, bad);
end;
{$POP}

{ ---- construction ---- }

constructor TTyRichText.Create;
begin
  inherited Create;
  FRoot := NewNode(True);
  FDepth := 0;
  FTotal := NodeSum(FRoot);
end;

constructor TTyRichText.CreateFromUtf8(const ABuffer: TBytes);
begin
  inherited Create;
  FOrig := ABuffer;
  FLoading := True;
  FLoadLeaves := TFPList.Create;
  FLoadLeaf := PTyRichLeaf(NewNode(True));
  FScanToLoad := True;
  if System.Length(FOrig) > 0 then
    Scan(@FOrig[0], System.Length(FOrig), 0, kOrig);
  FScanToLoad := False;
  FinishLoad;
end;

constructor TTyRichText.CreateLazy(AProvider: TTyRichTextProvider; AOwnsProvider: Boolean);
begin
  inherited Create;
  FProvider := AProvider;
  FOwnsProvider := AOwnsProvider;
  FLoading := True;
  FLoadLeaves := TFPList.Create;
  FLoadLeaf := PTyRichLeaf(NewNode(True));
  FLoadLastSep := True;
  FLoadLastSrc := -1;
end;

procedure TTyRichText.AppendLazyParagraph(ACharCount, ASrcOffset, ASrcBytes: Int64;
  ASeparator: TTyRichSeparator);
var
  chars: Int64;
begin
  if not (FLoading or FReopened) or FScanned or (FProvider = nil) then
    raise ETyRichText.Create('AppendLazyParagraph outside a lazy load');
  if not FLoadLastSep then
    raise ETyRichText.Create('Only the last lazy paragraph may have no separator');
  if (ASrcOffset <= FLoadLastSrc) or (ASrcOffset > SrcMask) then
    raise ETyRichText.Create('Lazy paragraph source offsets must increase');
  chars := ACharCount;
  if ASeparator <> rsNone then Inc(chars);
  if (ACharCount < 0) or (chars >= MaxPieceBytes) or (ASrcBytes < 0) or
     (ASrcBytes >= MaxPieceBytes) then
    raise ETyRichText.Create('Lazy paragraph out of range');
  FLoadLastSep := ASeparator <> rsNone;
  FLoadLastSrc := ASrcOffset;
  FLoadLastBytes := ASrcBytes;
  FLoadLastChars := chars;
  // an empty last paragraph has no piece to carry its source: the text remembers it
  FLazyTail := chars = 0;
  if chars = 0 then Exit;
  if FReopened then
  begin
    if FAppendCount = System.Length(FAppend) then
      SetLength(FAppend, FAppendCount * 2 + 64);
    with FAppend[FAppendCount] do
    begin
      FSrc := MakeSrc(ASrcOffset, kLazy, Ord(ASeparator));
      FBytes := ASrcBytes;
      FChars := chars;
      FHeight := 0;
      FData := nil;
    end;
    Inc(FAppendCount);
  end
  else
    LoadPiece(ASrcOffset, ASrcBytes, chars, kLazy, Ord(ASeparator));
end;

procedure TTyRichText.EndLazyLoad;
begin
  if FReopened then
  begin
    FReopened := False;
    if FAppendCount > 0 then
      // appended leaf after full leaf, as a load packs them
      InsertEntries(FTotal.Entries, FAppend[0..FAppendCount - 1]);
    FAppend := nil;
    FAppendCount := 0;
    Exit;
  end;
  if not FLoading or FScanned then
    raise ETyRichText.Create('EndLazyLoad outside a lazy load');
  FinishLoad;
end;

procedure TTyRichText.ReopenLazyLoad(ALastSeparator: TTyRichSeparator);
var
  p: TTyRichPath;
  before: TTyRichSum;
  it: PTyRichPiece;
  piece: TTyRichPiece;
  last: Integer;
begin
  if FLoading or FReopened or FScanned or (FProvider = nil) or FLoadLastSep or
     (FLoadLastSrc < 0) or (ALastSeparator = rsNone) then
    raise ETyRichText.Create('ReopenLazyLoad needs an ended lazy load whose last paragraph ' +
      'has no separator');
  CheckNotWalking;
  last := FTotal.Seps;
  if FLoadLastChars > 0 then
  begin
    // the last paragraph must still be the lazy piece appended last
    if FTotal.Entries = 0 then
      raise ETyRichText.Create('The last lazy paragraph was edited');
    Find(rskEntry, FTotal.Entries - 1, p, before);
    it := ItemAt(p);
    if not IsLazy(it^) or (PSep(it^) <> sNone) or (POff(it^) <> FLoadLastSrc) or
       (before.Seps <> last) then
      raise ETyRichText.Create('The last lazy paragraph was edited');
    if it^.FChars + 1 >= MaxPieceBytes then
      raise ETyRichText.Create('Lazy paragraph out of range');
    // its decoded text has no separator yet
    ForgetDecoded(POff(it^));
    it^.FSrc := MakeSrc(POff(it^), kLazy, Ord(ALastSeparator));
    Inc(it^.FChars);
    it^.FData := FLastData;
    it^.FHeight := FLastHeight;
    FixUp(p, FDepth);
  end
  else
  begin
    // an empty last paragraph has no piece: it gets one, of its separator only
    if not FLazyTail or (FTotal.Chars <> ParaStart(last)) then
      raise ETyRichText.Create('The last lazy paragraph was edited');
    FLazyTail := False;
    piece.FSrc := MakeSrc(FLoadLastSrc, kLazy, Ord(ALastSeparator));
    piece.FBytes := FLoadLastBytes;
    piece.FChars := 1;
    piece.FHeight := FLastHeight;
    piece.FData := FLastData;
    InsertEntries(FTotal.Entries, [piece]);
  end;
  FLastData := nil;
  FLastHeight := 0;
  FLoadLastSep := True;
  FReopened := True;
  FAppendCount := 0;
end;

constructor TTyRichText.CreateScanned;
begin
  inherited Create;
  FLoading := True;
  FScanned := True;
  FLoadLeaves := TFPList.Create;
  FLoadLeaf := PTyRichLeaf(NewNode(True));
end;

procedure TTyRichText.AppendScanned(ABytes, AChars: LongInt; ASeparator: TTyRichSeparator);
var
  sb: Integer;
begin
  if not FScanned then
    raise ETyRichText.Create('AppendScanned outside a scanned load');
  // a UTF-8 character is at least one byte; a separator is one character of 1 or 2 bytes,
  // and the piece holds all of them
  sb := SepBytes(Ord(ASeparator));
  if (ABytes <= 0) or (AChars <= 0) or (ABytes < sb) or
     (AChars - Ord(sb > 0) > ABytes - sb) or (ABytes > MaxPieceBytes + 4) then
    raise ETyRichText.Create('Scanned piece out of range');
  LoadPiece(FScannedBytes, ABytes, AChars, kOrig, Ord(ASeparator));
  Inc(FScannedBytes, ABytes);
  if ASeparator <> rsNone then Inc(FLoadSeps[Ord(ASeparator)]);
end;

procedure TTyRichText.EndScanned(const ABuffer: TBytes; AInvalid: Int64);
begin
  if not FScanned then
    raise ETyRichText.Create('EndScanned outside a scanned load');
  if FScannedBytes <> System.Length(ABuffer) then
    raise ETyRichText.CreateFmt('The scanned pieces cover %d bytes of a buffer of %d',
      [FScannedBytes, System.Length(ABuffer)]);
  FOrig := ABuffer;
  FLoadInvalid := AInvalid;
  FScanned := False;
  FinishLoad;
end;

destructor TTyRichText.Destroy;
var
  i: Integer;
begin
  FreeNode(FRoot);
  if FLoadLeaves <> nil then
  begin
    for i := 0 to FLoadLeaves.Count - 1 do
      FreeMem(FLoadLeaves[i]);
    FLoadLeaves.Free;
  end;
  if FLoadLeaf <> nil then FreeMem(FLoadLeaf);
  FDecoded.Free;
  if FOwnsProvider then FProvider.Free;
  inherited Destroy;
end;

{ ---- pieces ---- }

function TTyRichText.AppendAdd(AData: Pointer; ACount: Int64): Int64;
var
  cap: Int64;
begin
  Result := FAddLen;
  if FAddLen + ACount > System.Length(FAdd) then
  begin
    cap := System.Length(FAdd) * 2;
    if cap < FAddLen + ACount then cap := FAddLen + ACount;
    if cap < 4096 then cap := 4096;
    SetLength(FAdd, cap);
  end;
  if ACount > 0 then
    Move(AData^, FAdd[FAddLen], ACount);
  Inc(FAddLen, ACount);
end;

{ A lazy piece's decoded text with its separator bytes, decoding it the first time. It is
  kept apart from the add buffer, so that it can be let go of again (ForgetDecoded) while
  the paragraph is unedited; the piece itself keeps pointing at its source range, so a
  writer can still copy an unedited paragraph verbatim after it has been read. }
function TTyRichText.DecodedOf(AItem: PTyRichPiece): RawByteString;
var
  s: UTF8String;
  sep: Byte;
  content: PtrInt;
  len: PtrInt;
begin
  if (FDecoded <> nil) and FDecoded.TryGetValue(POff(AItem^), Result) then Exit;
  sep := PSep(AItem^);
  content := AItem^.FChars;
  if sep <> sNone then Dec(content);
  // the provider is foreign code and AItem points into a leaf: as in a walk, an edit from
  // inside it is refused
  Inc(FWalking);
  try
    s := FProvider.DecodeParagraph(POff(AItem^), AItem^.FBytes, content);
  finally
    Dec(FWalking);
  end;
  if (System.Length(s) > 0) and
     (HasBreak(@s[1], System.Length(s)) or (CountChars(@s[1], System.Length(s)) <> content)) then
    raise ETyRichText.CreateFmt('Lazy paragraph at %d decoded to the wrong text',
      [POff(AItem^)]);
  if (System.Length(s) = 0) and (content <> 0) then
    raise ETyRichText.CreateFmt('Lazy paragraph at %d decoded to the wrong text',
      [POff(AItem^)]);
  if FDecoded = nil then FDecoded := TTyRichDecodedMap.Create;
  Result := s;
  len := System.Length(s);
  if sep <> sNone then
  begin
    SetLength(Result, len + SepBytes(sep));
    case sep of
      sCR: Result[len + 1] := #13;
      sLF: Result[len + 1] := #10;
      sCRLF:
        begin
          Result[len + 1] := #13;
          Result[len + 2] := #10;
        end;
    end;
  end;
  FDecoded.AddOrSetValue(POff(AItem^), Result);
  Inc(FDecodedBytes, System.Length(Result));
end;

{ Characters [AFrom, ATo) of a lazy piece: its decoded text and their bytes in it. }
procedure TTyRichText.LazySlice(AItem: PTyRichPiece; AFrom, ATo: LongInt;
  out AText: RawByteString; out AByte0, AByte1: PtrInt);
var
  content: PtrInt;
  text: PByte;
begin
  AText := DecodedOf(AItem);
  text := PByte(Pointer(AText));
  content := System.Length(AText) - SepBytes(PSep(AItem^));
  AByte0 := ByteOfChar(text, content, AFrom);
  if ATo = AItem^.FChars then
    AByte1 := System.Length(AText)
  else
    AByte1 := AByte0 + ByteOfChar(text + AByte0, content - AByte0, ATo - AFrom);
end;

{ The bytes of a piece's text (decoding a lazy one); valid until the add buffer grows, and
  for a lazy one until it is forgotten. }
function TTyRichText.PieceText(AItem: PTyRichPiece; out ALen: LongInt): PByte;
var
  s: RawByteString;
begin
  case PKind(AItem^) of
    kOrig:
      begin
        ALen := AItem^.FBytes;
        Result := @FOrig[POff(AItem^)];
      end;
    kAdded:
      begin
        ALen := AItem^.FBytes;
        Result := @FAdd[POff(AItem^)];
      end;
  else
    // the map holds the string, so the pointer outlives s
    s := DecodedOf(AItem);
    ALen := System.Length(s);
    Result := PByte(Pointer(s));
  end;
end;

{ A lazy piece about to be edited becomes an ordinary add-buffer piece. }
procedure TTyRichText.ConvertToAdded(var APath: TTyRichPath);
var
  it: PTyRichPiece;
  s: RawByteString;
  src: Int64;
begin
  it := ItemAt(APath);
  if not IsLazy(it^) then Exit;
  s := DecodedOf(it);
  src := POff(it^);
  it^.FSrc := MakeSrc(AppendAdd(Pointer(s), System.Length(s)), kAdded, PSep(it^));
  it^.FBytes := System.Length(s);
  ForgetDecoded(src);
  FixUp(APath, FDepth);
end;

procedure TTyRichText.ForgetDecoded(ASrcOffset: Int64);
var
  s: RawByteString;
begin
  if (FDecoded = nil) or not FDecoded.TryGetValue(ASrcOffset, s) then Exit;
  Dec(FDecodedBytes, System.Length(s));
  FDecoded.Remove(ASrcOffset);
end;

function TTyRichText.IsDecoded(ASrcOffset: Int64): Boolean;
begin
  Result := (FDecoded <> nil) and FDecoded.ContainsKey(ASrcOffset);
end;

{ Makes APos a piece boundary and returns the index of the piece that starts there. }
function TTyRichText.SplitAt(APos: TTyRichPos): LongInt;
var
  p: TTyRichPath;
  before: TTyRichSum;
  it: PTyRichPiece;
  left: TTyRichPiece;
  off, bo: PtrInt;
  sep, kind: Byte;
begin
  if APos >= FTotal.Chars then Exit(FTotal.Entries);
  Find(rskChar, APos, p, before);
  off := APos - before.Chars;
  Result := before.Entries;
  if off = 0 then Exit;
  ConvertToAdded(p);
  it := ItemAt(p);
  sep := PSep(it^);
  kind := PKind(it^);
  if kind = kOrig then
    bo := ByteOfChar(@FOrig[POff(it^)], it^.FBytes - SepBytes(sep), off)
  else
    bo := ByteOfChar(@FAdd[POff(it^)], it^.FBytes - SepBytes(sep), off);
  left.FSrc := MakeSrc(POff(it^), kind, sNone);
  left.FBytes := bo;
  left.FChars := off;
  left.FHeight := 0;
  left.FData := nil;
  it^.FSrc := MakeSrc(POff(it^) + bo, kind, sep);
  Dec(it^.FBytes, bo);
  Dec(it^.FChars, off);
  FixUp(p, FDepth);
  InsertEntries(Result, [left]);
  Inc(Result);
end;

{ A lazy piece must stay a whole paragraph: preceded by a separator (or the start) and
  ending with one (or the text). An edit that glues something to it decodes it. }
procedure TTyRichText.CheckJunction(APos: TTyRichPos);
var
  pr, pl: TTyRichPath;
  br, bl: TTyRichSum;
  r, l: PTyRichPiece;
begin
  if (APos <= 0) or (APos >= FTotal.Chars) then Exit;
  Find(rskChar, APos, pr, br);
  Find(rskChar, APos - 1, pl, bl);
  r := ItemAt(pr);
  l := ItemAt(pl);
  if PSep(l^) <> sNone then Exit;
  if IsLazy(l^) then ConvertToAdded(pl);
  if IsLazy(r^) then ConvertToAdded(pr);
end;

{ Characters [AFrom, ATo) of a piece as a piece of their own; a lazy piece that is cut
  is decoded, its text copied into the add buffer (a piece's bytes must not go away), and
  the cut refers to that copy. }
procedure TTyRichText.TrimPiece(AItem: PTyRichPiece; AFrom, ATo: LongInt; out APiece: TTyRichPiece);
var
  text: PByte;
  len: LongInt;
  content, b0, b1: PtrInt;
  sep, kind: Byte;
  src: Int64;
  s: RawByteString;
begin
  APiece := AItem^;
  APiece.FHeight := 0;
  APiece.FData := nil;
  if (AFrom = 0) and (ATo = AItem^.FChars) then Exit;
  sep := PSep(AItem^);
  if IsLazy(AItem^) then
  begin
    s := DecodedOf(AItem);
    len := System.Length(s);
    src := AppendAdd(Pointer(s), len);
    text := @FAdd[src];
    kind := kAdded;
  end
  else
  begin
    text := PieceText(AItem, len);
    src := POff(AItem^);
    kind := PKind(AItem^);
  end;
  content := len - SepBytes(sep);
  b0 := ByteOfChar(text, content, AFrom);
  if ATo = AItem^.FChars then
    b1 := len
  else
    b1 := b0 + ByteOfChar(text + b0, content - b0, ATo - AFrom);
  if ATo <> AItem^.FChars then sep := sNone;
  APiece.FSrc := MakeSrc(src + b0, kind, sep);
  APiece.FBytes := b1 - b0;
  APiece.FChars := ATo - AFrom;
end;

{ Splits paragraph k (holding APos) by the separators in APieces. Paragraph k keeps its
  data and height on the first part; the paragraphs after the i-th separator get
  AFollow[i] (nil when AFollow is empty) and are unmeasured. }
procedure TTyRichText.InsertPieces(APos: TTyRichPos; var APieces: TTyRichPieceArray;
  ACount: Integer; const AFollow: array of Pointer);
var
  k, s, i, j: Integer;
  chars: Int64;
  oldData: Pointer;
  oldHeight: LongInt;
  e: LongInt;
begin
  k := ParaOfPos(APos);
  s := 0;
  chars := 0;
  for i := 0 to ACount - 1 do
  begin
    if PSep(APieces[i]) <> sNone then Inc(s);
    Inc(chars, APieces[i].FChars);
  end;
  if s > 0 then
  begin
    oldData := GetParaData(k);
    oldHeight := GetParaRawHeight(k);
    j := 0;
    for i := 0 to ACount - 1 do
    begin
      APieces[i].FHeight := 0;
      APieces[i].FData := nil;
      if PSep(APieces[i]) <> sNone then
      begin
        if j = 0 then
        begin
          APieces[i].FData := oldData;
          APieces[i].FHeight := oldHeight;
        end
        else if System.Length(AFollow) > 0 then
          APieces[i].FData := AFollow[j - 1];
        Inc(j);
      end;
    end;
  end
  else
    for i := 0 to ACount - 1 do
    begin
      APieces[i].FHeight := 0;
      APieces[i].FData := nil;
    end;
  e := SplitAt(APos);
  InsertEntries(e, APieces[0..ACount - 1]);
  if s > 0 then
  begin
    if System.Length(AFollow) > 0 then
      SetParaRaw(k + s, AFollow[s - 1], 0)
    else
      SetParaRaw(k + s, nil, 0);
  end;
  CheckJunction(APos);
  CheckJunction(APos + chars);
  DoParasChanged(k, 1, 1 + s);
end;

{ ---- checks ---- }

procedure TTyRichText.CheckReady;
begin
  if FLoading or FReopened then
    raise ETyRichText.Create('Rich text used before EndLazyLoad');
end;

procedure TTyRichText.CheckPara(AIndex: Integer);
begin
  CheckReady;
  if (AIndex < 0) or (AIndex > FTotal.Seps) then
    raise ETyRichText.CreateFmt('Paragraph index %d out of range', [AIndex]);
end;

procedure TTyRichText.CheckRange(APos, ALen: TTyRichPos);
begin
  CheckReady;
  if (APos < 0) or (ALen < 0) or (APos + ALen > FTotal.Chars) then
    raise ETyRichText.CreateFmt('Range %d+%d out of 0..%d', [APos, ALen, FTotal.Chars]);
end;

procedure TTyRichText.CheckNotWalking;
begin
  // the walk holds a path into the tree; a structural change would leave it dangling
  if FWalking > 0 then
    raise ETyRichText.Create('The text cannot change during a walk (MapParaData, WalkParas, ' +
      'ForEachRun)');
end;

{ ---- editing ---- }

procedure TTyRichText.Insert(APos: TTyRichPos; const AText: UTF8String);
var
  base: Int64;
  p: TTyRichPath;
  before: TTyRichSum;
  it: PTyRichPiece;
  k: Integer;
begin
  CheckRange(APos, 0);
  CheckNotWalking;
  if AText = '' then Exit;
  if APos = FTotal.Chars then FLazyTail := False;
  base := AppendAdd(@AText[1], System.Length(AText));
  FScanCount := 0;
  Scan(@FAdd[base], System.Length(AText), base, kAdded);
  // typing: the piece just before APos ends where this text was appended, so it grows.
  // Not when the text starts with a continuation byte: it was counted on its own here, but
  // joined to a lead byte the piece ends with it would read as fewer characters, and the
  // piece's count would disagree with its bytes. It stays a piece of its own then
  if (FScanCount = 1) and (PSep(FScan[0]) = sNone) and (APos > 0) and
     (FAdd[base] and $C0 <> $80) then
  begin
    Find(rskChar, APos - 1, p, before);
    it := ItemAt(p);
    if (before.Chars + it^.FChars = APos) and (PKind(it^) = kAdded) and
       (PSep(it^) = sNone) and (POff(it^) + it^.FBytes = base) and
       (it^.FBytes + FScan[0].FBytes <= MaxPieceBytes) then
    begin
      k := before.Seps;
      Inc(it^.FBytes, FScan[0].FBytes);
      Inc(it^.FChars, FScan[0].FChars);
      FixUp(p, FDepth);
      DoParasChanged(k, 1, 1);
      Exit;
    end;
  end;
  InsertPieces(APos, FScan, FScanCount, []);
  // typing reuses the buffer; a paste of many lines made it as big as the index it filled
  if System.Length(FScan) > ScanKeep then FScan := nil;
end;

procedure TTyRichText.Delete(APos, ALen: TTyRichPos);
var
  a, b: TTyRichPos;
  k, m, i: Integer;
  dk: Pointer;
  hk: LongInt;
  ea, eb: LongInt;
  dropped: TFPList;
  p: TTyRichPath;
  before: TTyRichSum;
  firstSep: Boolean;
  it: PTyRichPiece;
begin
  CheckRange(APos, ALen);
  CheckNotWalking;
  if ALen = 0 then Exit;
  a := APos;
  b := APos + ALen;
  if b = FTotal.Chars then FLazyTail := False;
  k := ParaOfPos(a);
  m := ParaOfPos(b);
  dk := nil;
  hk := 0;
  dropped := nil;
  try
    if m > k then
    begin
      dk := GetParaData(k);
      hk := GetParaRawHeight(k);
      dropped := TFPList.Create;
    end;
    ea := SplitAt(a);
    eb := SplitAt(b);
    if m > k then
    begin
      // the separators in the range end paragraphs k..m-1; k's data moves to the merged
      // paragraph, the data of k+1..m goes
      Find(rskEntry, ea, p, before);
      firstSep := True;
      for i := ea to eb - 1 do
      begin
        it := ItemAt(p);
        if PSep(it^) <> sNone then
        begin
          if not firstSep and (it^.FData <> nil) then dropped.Add(it^.FData);
          firstSep := False;
        end;
        if (i < eb - 1) and not Advance(p) then
          raise ETyRichText.Create('Rich text index is inconsistent');
      end;
      if GetParaData(m) <> nil then dropped.Add(GetParaData(m));
    end;
    DeleteEntries(ea, eb - ea);
    if m > k then
      SetParaRaw(k, dk, hk);
    CheckJunction(a);
    if (dropped <> nil) and Assigned(FOnParaDataDropped) then
      for i := 0 to dropped.Count - 1 do
        FOnParaDataDropped(Self, dropped[i]);
  finally
    dropped.Free;
  end;
  DoParasChanged(k, m - k + 1, 1);
end;

function TTyRichText.Length: TTyRichPos;
begin
  Result := FTotal.Chars;
end;

function TTyRichText.ByteCount: Int64;
begin
  Result := FTotal.Bytes;
end;

function TTyRichText.PieceCount: Integer;
begin
  Result := FTotal.Entries;
end;

function TTyRichText.TreeDepth: Integer;
begin
  Result := FDepth;
end;

function TTyRichText.GetText(APos, ALen: TTyRichPos): UTF8String;
type
  TSeg = record
    Src: Byte;   // kOrig, kAdded, or kLazy: Text
    Off: Int64;
    Len: Int64;
    Text: RawByteString;
  end;
var
  segs: array of TSeg;
  nseg, i: Integer;
  total, pos, stop, start: Int64;
  p: TTyRichPath;
  before: TTyRichSum;
  it: PTyRichPiece;
  piece: TTyRichPiece;
  from, upto: LongInt;
  dst: Int64;
  b0, b1: PtrInt;
begin
  Result := '';
  CheckRange(APos, ALen);
  if ALen = 0 then Exit;
  segs := nil;
  nseg := 0;
  total := 0;
  stop := APos + ALen;
  Find(rskChar, APos, p, before);
  start := before.Chars;
  pos := APos;
  repeat
    it := ItemAt(p);
    from := pos - start;
    if stop - start < it^.FChars then upto := stop - start else upto := it^.FChars;
    if nseg = System.Length(segs) then SetLength(segs, nseg * 2 + 4);
    if IsLazy(it^) then
    begin
      // read from the decoded text itself: a part of it is not copied anywhere
      LazySlice(it, from, upto, segs[nseg].Text, b0, b1);
      segs[nseg].Src := kLazy;
      segs[nseg].Off := b0;
      segs[nseg].Len := b1 - b0;
    end
    else
    begin
      TrimPiece(it, from, upto, piece);
      segs[nseg].Src := PKind(piece);
      segs[nseg].Off := POff(piece);
      segs[nseg].Len := piece.FBytes;
    end;
    Inc(total, segs[nseg].Len);
    Inc(nseg);
    Inc(start, it^.FChars);
    pos := start;
  until (pos >= stop) or not Advance(p);
  SetLength(Result, total);
  dst := 1;
  for i := 0 to nseg - 1 do
  begin
    if segs[i].Len = 0 then Continue;
    case segs[i].Src of
      kOrig: Move(FOrig[segs[i].Off], Result[dst], segs[i].Len);
      kAdded: Move(FAdd[segs[i].Off], Result[dst], segs[i].Len);
    else
      Move(segs[i].Text[segs[i].Off + 1], Result[dst], segs[i].Len);
    end;
    Inc(dst, segs[i].Len);
  end;
end;

procedure TTyRichText.ForEachRun(APos, ALen: TTyRichPos; AProc: TTyRichRunEvent);
var
  p: TTyRichPath;
  before: TTyRichSum;
  it: PTyRichPiece;
  piece: TTyRichPiece;
  run: TTyRichByteRun;
  pos, stop, start: Int64;
  from, upto: LongInt;
  goOn: Boolean;
  s: RawByteString;
  b0, b1: PtrInt;
begin
  CheckRange(APos, ALen);
  if ALen = 0 then Exit;
  stop := APos + ALen;
  // the piece is read again after the callback and the path is advanced from where it stood
  Inc(FWalking);
  try
    Find(rskChar, APos, p, before);
    start := before.Chars;
    pos := APos;
    goOn := True;
    repeat
      it := ItemAt(p);
      from := pos - start;
      if stop - start < it^.FChars then upto := stop - start else upto := it^.FChars;
      if IsLazy(it^) and ((from > 0) or (upto < it^.FChars)) then
      begin
        // part of a lazy paragraph: its decoded bytes, which are no source of their own
        LazySlice(it, from, upto, s, b0, b1);
        run.Kind := rpkAdded;
        run.SrcOffset := -1;
        run.ByteCount := b1 - b0;
        run.CharCount := upto - from;
        if upto = it^.FChars then run.Separator := it^.Separator else run.Separator := rsNone;
        run.Bytes := PByte(Pointer(s)) + b0;
      end
      else
      begin
        TrimPiece(it, from, upto, piece);
        run.Kind := piece.Kind;
        run.SrcOffset := POff(piece);
        run.ByteCount := piece.FBytes;
        run.CharCount := piece.FChars;
        run.Separator := piece.Separator;
        case PKind(piece) of
          kOrig: run.Bytes := @FOrig[POff(piece)];
          kAdded: run.Bytes := @FAdd[POff(piece)];
        else
          run.Bytes := nil;
        end;
      end;
      AProc(run, goOn);
      Inc(start, it^.FChars);
      pos := start;
    until not goOn or (pos >= stop) or not Advance(p);
  finally
    Dec(FWalking);
  end;
end;

function TTyRichText.PieceSnapshot(APos, ALen: TTyRichPos): TTyRichPieces;
var
  p, p2: TTyRichPath;
  before, before2: TTyRichSum;
  it: PTyRichPiece;
  n, i, pending: Integer;
  pos, stop, start: Int64;
  from, upto: LongInt;
begin
  Result.Pieces := nil;
  Result.CharCount := 0;
  CheckRange(APos, ALen);
  if ALen = 0 then Exit;
  stop := APos + ALen;
  Find(rskChar, APos, p, before);
  Find(rskChar, stop - 1, p2, before2);
  n := before2.Entries - before.Entries + 1;
  SetLength(Result.Pieces, n);
  Result.CharCount := ALen;
  start := before.Chars;
  pos := APos;
  pending := -1;
  for i := 0 to n - 1 do
  begin
    it := ItemAt(p);
    from := pos - start;
    if stop - start < it^.FChars then upto := stop - start else upto := it^.FChars;
    if PSep(it^) <> sNone then
    begin
      // this separator ends the paragraph that followed the previous one
      if pending >= 0 then Result.Pieces[pending].FData := it^.FData;
    end;
    TrimPiece(it, from, upto, Result.Pieces[i]);
    if PSep(Result.Pieces[i]) <> sNone then pending := i;
    Inc(start, it^.FChars);
    pos := start;
    if (i < n - 1) and not Advance(p) then
      raise ETyRichText.Create('Rich text index is inconsistent');
  end;
  if pending >= 0 then
    Result.Pieces[pending].FData := GetParaData(ParaOfPos(stop));
end;

procedure TTyRichText.RestorePieces(APos: TTyRichPos; const P: TTyRichPieces);
var
  items: TTyRichPieceArray;
  follow: array of Pointer;
  i, s: Integer;
begin
  CheckRange(APos, 0);
  CheckNotWalking;
  if System.Length(P.Pieces) = 0 then Exit;
  if APos = FTotal.Chars then FLazyTail := False;
  items := Copy(P.Pieces);
  follow := nil;
  SetLength(follow, System.Length(items));
  s := 0;
  for i := 0 to High(items) do
    if PSep(items[i]) <> sNone then
    begin
      follow[s] := items[i].FData;
      Inc(s);
    end;
  SetLength(follow, s);
  if s = 0 then
    InsertPieces(APos, items, System.Length(items), [])
  else
    InsertPieces(APos, items, System.Length(items), follow);
end;

{ ---- paragraphs ---- }

function TTyRichText.ParaCount: Integer;
begin
  Result := FTotal.Seps + 1;
end;

function TTyRichText.ParaStart(AIndex: Integer): TTyRichPos;
var
  p: TTyRichPath;
  before: TTyRichSum;
begin
  CheckPara(AIndex);
  if AIndex = 0 then Exit(0);
  Find(rskSep, AIndex - 1, p, before);
  Result := before.Chars + ItemAt(p)^.FChars;
end;

function TTyRichText.ParaLength(AIndex: Integer): TTyRichPos;
begin
  if AIndex = FTotal.Seps then
    Result := FTotal.Chars - ParaStart(AIndex)
  else
    Result := ParaStart(AIndex + 1) - 1 - ParaStart(AIndex);
end;

function TTyRichText.ParaOfPos(APos: TTyRichPos): Integer;
var
  p: TTyRichPath;
  before: TTyRichSum;
begin
  CheckRange(APos, 0);
  if Descend(rskChar, APos, p, before) then
    Result := before.Seps
  else
    Result := FTotal.Seps;
end;

function TTyRichText.ParaLazySource(AIndex: Integer; out ASrcOffset, ASrcBytes: Int64): Boolean;
var
  p: TTyRichPath;
  before: TTyRichSum;
  it: PTyRichPiece;
begin
  CheckPara(AIndex);
  ASrcOffset := -1;
  ASrcBytes := 0;
  if FLazyTail and (AIndex = FTotal.Seps) then
  begin
    ASrcOffset := FLoadLastSrc;
    ASrcBytes := FLoadLastBytes;
    Exit(True);
  end;
  if AIndex = 0 then
  begin
    if FTotal.Entries = 0 then Exit(False);
    Find(rskEntry, 0, p, before);
  end
  else
  begin
    // the piece after the separator that ends the paragraph before
    Find(rskSep, AIndex - 1, p, before);
    if not Advance(p) then Exit(False);
  end;
  it := ItemAt(p);
  // a lazy piece is always a whole paragraph
  Result := IsLazy(it^);
  if Result then
  begin
    ASrcOffset := POff(it^);
    ASrcBytes := it^.FBytes;
  end;
end;

function TTyRichText.ParaOfLazySource(ASrcOffset: Int64): Integer;
var
  node: PTyRichNode;
  inner: PTyRichInner;
  leaf: PTyRichLeaf;
  i: Integer;
  seps: Int64;
begin
  CheckReady;
  if FLazyTail and (ASrcOffset = FLoadLastSrc) then Exit(FTotal.Seps);
  if (ASrcOffset < 0) or (FTotal.LazyMax < ASrcOffset) then Exit(-1);
  node := FRoot;
  seps := 0;
  while not node^.IsLeaf do
  begin
    Inc(FNodeVisits);
    inner := PTyRichInner(node);
    i := 0;
    // the first subtree whose lazy pieces reach the offset holds it, if anything does
    while (i < inner^.Count) and (inner^.Sum[i].LazyMax < ASrcOffset) do
    begin
      Inc(seps, inner^.Sum[i].Seps);
      Inc(i);
    end;
    if i = inner^.Count then Exit(-1);
    node := inner^.Child[i];
  end;
  Inc(FNodeVisits);
  leaf := PTyRichLeaf(node);
  for i := 0 to leaf^.Count - 1 do
  begin
    if IsLazy(leaf^.Items[i]) then
    begin
      if POff(leaf^.Items[i]) = ASrcOffset then Exit(seps);
      if POff(leaf^.Items[i]) > ASrcOffset then Exit(-1);
    end;
    if PSep(leaf^.Items[i]) <> sNone then Inc(seps);
  end;
  Result := -1;
end;

function TTyRichText.LoadedSeparators(ASep: TTyRichSeparator): Int64;
begin
  if ASep = rsNone then Result := 0 else Result := FLoadSeps[Ord(ASep)];
end;

function TTyRichText.ParaSeparator(AIndex: Integer): TTyRichSeparator;
var
  p: TTyRichPath;
  before: TTyRichSum;
begin
  CheckPara(AIndex);
  if AIndex = FTotal.Seps then Exit(rsNone);
  Find(rskSep, AIndex, p, before);
  Result := TTyRichSeparator(PSep(ItemAt(p)^));
end;

function TTyRichText.GetParaData(AIndex: Integer): Pointer;
var
  p: TTyRichPath;
  before: TTyRichSum;
begin
  CheckPara(AIndex);
  if AIndex = FTotal.Seps then Exit(FLastData);
  Find(rskSep, AIndex, p, before);
  Result := ItemAt(p)^.FData;
end;

procedure TTyRichText.SetParaData(AIndex: Integer; AValue: Pointer);
var
  p: TTyRichPath;
  before: TTyRichSum;
begin
  CheckPara(AIndex);
  if AIndex = FTotal.Seps then
    FLastData := AValue
  else
  begin
    Find(rskSep, AIndex, p, before);
    ItemAt(p)^.FData := AValue;
  end;
end;

procedure TTyRichText.MapParaData(AFirst, ALast: Integer; AMap: TTyRichParaDataMap);
var
  p: TTyRichPath;
  before: TTyRichSum;
  it: PTyRichPiece;
  prev: array[0..TyRichMaxDepth] of PTyRichNode;
  i, l: Integer;
  crossing: Boolean;
begin
  CheckPara(AFirst);
  CheckPara(ALast);
  if ALast < AFirst then Exit;
  Inc(FWalking);
  try
    i := AFirst;
    if i < FTotal.Seps then
    begin
      // data lives on the separator pieces: find the first one, then walk the pieces on
      Find(rskSep, i, p, before);
      repeat
        it := ItemAt(p);
        if PSep(it^) <> sNone then
        begin
          // AMap may set other slots through ParaData; that changes no node, so it stays valid
          it^.FData := AMap(i, it^.FData);
          Inc(i);
          if (i > ALast) or (i >= FTotal.Seps) then Break;
        end;
        crossing := p.Steps[FDepth].Index = p.Steps[FDepth].Node^.Count - 1;
        if crossing then
          for l := 1 to FDepth do prev[l] := p.Steps[l].Node;
        if not Advance(p) then
          raise ETyRichText.Create('Rich text index is inconsistent');
        if crossing then
          for l := 1 to FDepth do
            if p.Steps[l].Node <> prev[l] then Inc(FNodeVisits);
      until False;
    end;
    if (i <= ALast) and (i = FTotal.Seps) then
      FLastData := AMap(i, FLastData);
  finally
    Dec(FWalking);
  end;
end;

procedure TTyRichText.WalkParas(AFirst: Integer; AProc: TTyRichParaWalk);
var
  p: TTyRichPath;
  before: TTyRichSum;
  it: PTyRichPiece;
  i: Integer;
  src, n: Int64;
  atStart, more, go: Boolean;
begin
  CheckPara(AFirst);
  Inc(FWalking);
  try
    i := AFirst;
    go := True;
    more := FTotal.Entries > 0;
    if more then
      if i = 0 then
        Find(rskEntry, 0, p, before)
      else
      begin
        // the piece after the separator that ends the paragraph before
        Find(rskSep, i - 1, p, before);
        more := Advance(p);
      end;
    atStart := True;
    src := -1;
    n := 0;
    while more do
    begin
      it := ItemAt(p);
      if atStart then
      begin
        // a lazy piece is always a whole paragraph
        if IsLazy(it^) then
        begin
          src := POff(it^);
          n := it^.FBytes;
        end
        else
        begin
          src := -1;
          n := 0;
        end;
        atStart := False;
      end;
      if PSep(it^) <> sNone then
      begin
        AProc(i, it^.FData, src, n, go);
        if not go then Exit;
        Inc(i);
        atStart := True;
      end;
      more := Advance(p);
    end;
    // the last paragraph: what follows the last separator
    if atStart then
    begin
      src := -1;
      n := 0;
    end;
    if FLazyTail then
    begin
      src := FLoadLastSrc;
      n := FLoadLastBytes;
    end;
    AProc(i, FLastData, src, n, go);
  finally
    Dec(FWalking);
  end;
end;

procedure TTyRichText.SetParaRaw(AIndex: Integer; AData: Pointer; AHeight: LongInt);
var
  p: TTyRichPath;
  before: TTyRichSum;
begin
  if AIndex = FTotal.Seps then
  begin
    FLastData := AData;
    FLastHeight := AHeight;
  end
  else
  begin
    Find(rskSep, AIndex, p, before);
    ItemAt(p)^.FData := AData;
    ItemAt(p)^.FHeight := AHeight;
    FixUp(p, FDepth);
  end;
end;

{ The stored height of a paragraph: the measured height plus one, 0 unmeasured. }
function TTyRichText.GetParaRawHeight(AIndex: Integer): LongInt;
var
  p: TTyRichPath;
  before: TTyRichSum;
begin
  if AIndex = FTotal.Seps then Exit(FLastHeight);
  Find(rskSep, AIndex, p, before);
  Result := ItemAt(p)^.FHeight;
end;

{ Gives paragraphs AFirst..ALast their stored heights: AHeights^[i - AFirst] measured, or
  none of them (nil). One descent, then piece by piece; what changed in a leaf goes up its
  path by the difference when the walk leaves it, so no summary is recomputed. }
procedure TTyRichText.PutHeights(AFirst, ALast: Integer; AHeights: PInt64);
var
  p: TTyRichPath;
  before: TTyRichSum;
  it: PTyRichPiece;
  i: Integer;
  dh: Int64;
  dm: Integer;

  function Next: LongInt;
  begin
    if AHeights = nil then Result := 0 else Result := AHeights[i - AFirst] + 1;
  end;

begin
  if ALast < AFirst then Exit;
  i := AFirst;
  if i < FTotal.Seps then
  begin
    Find(rskSep, i, p, before);
    dh := 0;
    dm := 0;
    repeat
      it := ItemAt(p);
      if PSep(it^) <> sNone then
      begin
        if it^.FHeight > 0 then
        begin
          Dec(dh, it^.FHeight - 1);
          Dec(dm);
        end;
        it^.FHeight := Next;
        if it^.FHeight > 0 then
        begin
          Inc(dh, it^.FHeight - 1);
          Inc(dm);
        end;
        Inc(i);
        if (i > ALast) or (i >= FTotal.Seps) then Break;
      end;
      if p.Steps[FDepth].Index = p.Steps[FDepth].Node^.Count - 1 then
      begin
        // the path is about to move to the next leaf
        AddToPath(p, dh, dm);
        dh := 0;
        dm := 0;
      end;
      if not Advance(p, True) then
        raise ETyRichText.Create('Rich text index is inconsistent');
    until False;
    AddToPath(p, dh, dm);
  end;
  if (i <= ALast) and (i = FTotal.Seps) then
    FLastHeight := Next;
end;

procedure TTyRichText.SetParaHeight(AIndex: Integer; AHeight: Int64);
var
  p: TTyRichPath;
  before: TTyRichSum;
  it: PTyRichPiece;
  dh: Int64;
  dm: Integer;
begin
  CheckPara(AIndex);
  if (AHeight < 0) or (AHeight > TyRichMaxParaHeight) then
    raise ETyRichText.CreateFmt('Paragraph height %d out of range', [AHeight]);
  if AIndex = FTotal.Seps then
    FLastHeight := AHeight + 1
  else
  begin
    Find(rskSep, AIndex, p, before);
    it := ItemAt(p);
    dh := AHeight;
    dm := 1;
    if it^.FHeight > 0 then
    begin
      Dec(dh, it^.FHeight - 1);
      dm := 0;
    end;
    it^.FHeight := AHeight + 1;
    // by the difference, not FixUp: the layout sets heights by the thousand while it
    // scrolls, and recomputing a leaf and its ancestors for each took 3 us
    AddToPath(p, dh, dm);
  end;
end;

procedure TTyRichText.SetParaHeights(AFirst: Integer; const AHeights: array of Int64);
var
  i: Integer;
begin
  CheckPara(AFirst);
  if System.Length(AHeights) = 0 then Exit;
  CheckPara(AFirst + High(AHeights));
  // all of them before the first is stored: a refused call changes nothing
  for i := 0 to High(AHeights) do
    if (AHeights[i] < 0) or (AHeights[i] > TyRichMaxParaHeight) then
      raise ETyRichText.CreateFmt('Paragraph height %d out of range', [AHeights[i]]);
  PutHeights(AFirst, AFirst + High(AHeights), @AHeights[0]);
end;

procedure TTyRichText.UnmeasureParas(AFirst, ALast: Integer);
begin
  CheckPara(AFirst);
  CheckPara(ALast);
  PutHeights(AFirst, ALast, nil);
end;

procedure TTyRichText.UnmeasureAll;
begin
  CheckReady;
  // every node is now behind and holds no heights; the totals say so already
  Inc(FHeightEpoch);
  FTotal.Height := 0;
  FTotal.Measured := 0;
  FLastHeight := 0;
end;

procedure TTyRichText.SetDefaultParaHeight(AValue: Int64);
begin
  if (AValue < 0) or (AValue > TyRichMaxParaHeight) then
    raise ETyRichText.CreateFmt('Paragraph height %d out of range', [AValue]);
  FDefaultHeight := AValue;
end;

function TTyRichText.ParaMeasured(AIndex: Integer): Boolean;
begin
  CheckPara(AIndex);
  Result := GetParaRawHeight(AIndex) > 0;
end;

function TTyRichText.MeasuredParaCount: Integer;
begin
  Result := FTotal.Measured + Ord(FLastHeight > 0);
end;

function TTyRichText.ParaHeight(AIndex: Integer): Int64;
var
  raw: LongInt;
begin
  CheckPara(AIndex);
  raw := GetParaRawHeight(AIndex);
  if raw > 0 then Result := raw - 1 else Result := FDefaultHeight;
end;

function TTyRichText.ParaTop(AIndex: Integer): Int64;
var
  p: TTyRichPath;
  before: TTyRichSum;
begin
  CheckPara(AIndex);
  if AIndex = 0 then Exit(0);
  Find(rskSep, AIndex - 1, p, before);
  Result := SumHeight(before) + PieceHeight(ItemAt(p)^);
end;

function TTyRichText.ParaAtHeight(AY: Int64): Integer;
var
  p: TTyRichPath;
  before: TTyRichSum;
begin
  CheckReady;
  if AY < 0 then Exit(0);
  if Descend(rskHeight, AY, p, before) then
    Result := before.Seps
  else
    Result := FTotal.Seps;
end;

function TTyRichText.TotalHeight: Int64;
begin
  Result := SumHeight(FTotal);
  if FLastHeight > 0 then Inc(Result, FLastHeight - 1) else Inc(Result, FDefaultHeight);
end;

procedure TTyRichText.DoParasChanged(AFirst, AOldCount, ANewCount: Integer);
begin
  if Assigned(FOnParasChanged) then
    FOnParasChanged(Self, AFirst, AOldCount, ANewCount);
end;

{ ---- integrity ---- }

function TTyRichText.CheckNode(ANode: PTyRichNode; ALevel: Integer; var APrevSep: Boolean;
  var APrevLazyOpen: Boolean; var APrevLazy: Int64): string;
var
  i: Integer;
  it: PTyRichPiece;
  text: PByte;
  len: LongInt;
  sep: Byte;
  content: PtrInt;
  s: TTyRichSum;
  heights: Boolean;
begin
  Result := '';
  if (ANode <> FRoot) and (ANode^.Count = 0) then Exit('empty node');
  if ANode^.IsLeaf <> (ALevel = FDepth) then Exit('leaves at different depths');
  if ANode^.HeightEpoch > FHeightEpoch then Exit('a node ahead of the height epoch');
  // a node UnmeasureAll left behind holds no heights: what is written there is not looked at
  heights := ANode^.HeightEpoch = FHeightEpoch;
  if not ANode^.IsLeaf then
  begin
    for i := 0 to ANode^.Count - 1 do
    begin
      s := NodeSum(PTyRichInner(ANode)^.Child[i]);
      with PTyRichInner(ANode)^.Sum[i] do
        if (s.Entries <> Entries) or (s.Seps <> Seps) or (s.Chars <> Chars) or
           (s.Bytes <> Bytes) or (s.LazyMax <> LazyMax) or
           (heights and ((s.Height <> Height) or (s.Measured <> Measured))) then
          Exit(Format('stale summary at level %d child %d', [ALevel, i]));
      Result := CheckNode(PTyRichInner(ANode)^.Child[i], ALevel + 1, APrevSep, APrevLazyOpen,
        APrevLazy);
      if Result <> '' then Exit;
    end;
    Exit;
  end;
  for i := 0 to ANode^.Count - 1 do
  begin
    it := @PTyRichLeaf(ANode)^.Items[i];
    sep := PSep(it^);
    if APrevLazyOpen then Exit('a lazy last paragraph is followed by a piece');
    if it^.FChars <= 0 then Exit('empty piece');
    if (sep = sNone) and ((heights and (it^.FHeight <> 0)) or (it^.FData <> nil)) then
      Exit('height or data on a piece without a separator');
    if heights and (it^.FHeight < 0) then Exit('negative height');
    if IsLazy(it^) then
    begin
      if not APrevSep then Exit('a lazy piece does not start its paragraph');
      // ParaOfLazySource walks towards an offset
      if POff(it^) <= APrevLazy then Exit('lazy pieces out of source order');
      APrevLazy := POff(it^);
      APrevLazyOpen := sep = sNone;
    end
    else
    begin
      text := PieceText(it, len);
      if len <> it^.FBytes then Exit('byte count');
      content := len - SepBytes(sep);
      if content < 0 then Exit('separator longer than the piece');
      if HasBreak(text, content) then Exit('a separator inside a piece');
      case sep of
        sCR: if text[content] <> 13 then Exit('separator bytes');
        sLF: if text[content] <> 10 then Exit('separator bytes');
        sCRLF: if (text[content] <> 13) or (text[content + 1] <> 10) then
            Exit('separator bytes');
      end;
      if CountChars(text, content) + Ord(sep <> sNone) <> it^.FChars then
        Exit(Format('character count %d of a piece', [it^.FChars]));
    end;
    APrevSep := sep <> sNone;
  end;
end;

function TTyRichText.CheckIntegrity: string;
var
  s: TTyRichSum;
  prevSep, lazyOpen: Boolean;
  prevLazy: Int64;
begin
  CheckReady;
  s := NodeSum(FRoot);
  if (s.Entries <> FTotal.Entries) or (s.Seps <> FTotal.Seps) or (s.Chars <> FTotal.Chars) or
     (s.Bytes <> FTotal.Bytes) or (s.Height <> FTotal.Height) or
     (s.Measured <> FTotal.Measured) or (s.LazyMax <> FTotal.LazyMax) then
    Exit('stale total');
  if FLastHeight < 0 then Exit('negative height');
  prevSep := True;
  lazyOpen := False;
  prevLazy := -1;
  Result := CheckNode(FRoot, 0, prevSep, lazyOpen, prevLazy);
end;

end.
