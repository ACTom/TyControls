unit tyControls.RichEdit.RtfRead;

// Reading RTF into TTyRichEdit's document (tyControls.RichEdit.Model).
//
// The lexer cuts the bytes into tokens without allocating anything: control words, control
// symbols, \'xx, group braces, runs of text and \bin data, each as offsets into the buffer.
// The parser keeps everything the rest of the parse depends on in one record, TTyRtfState:
// the properties in effect and the group stack, the \uc fallback still to skip, a lead byte
// waiting for its trail byte, where the body began and where the current paragraph's bytes
// start. A copy of it is a snapshot the parse can resume from. What the header defines
// (fonts, colours, lists, the ANSI code page) lives beside it in the parser and is copied to
// a parser that resumes.
//
// Decoding - Chinese RTF must open without garbage:
// - bytes written as \'xx (or raw) are decoded with the code page of the font in effect: the
//   font entry's \cpg, else its \fcharset, else \ansicpg, else 1252 - never the system's code
//   page; \fcharset2 (Symbol) maps byte b to U+F000+b;
// - a lead byte and its trail byte are one character when both are in the same font, also
//   with braces or control words between them; a trail byte written as a literal ASCII
//   character joins too; halves in two fonts do not join (the lone lead byte reads as '?');
// - \uN (a negative N is N+65536) is followed by \ucN fallback items - a character, a \'xx or
//   a control symbol; a control word or a brace ends them early - and a surrogate pair
//   written as two \u is one character;
// - Word's font slots (\loch, \hich, \dbch with \f or \af after them) give each character the
//   font of its class.
//
// What the model does not understand is kept as the file's own bytes: unknown character words
// on the run (TTyCharFormat.Extra), unknown paragraph words on the paragraph
// (TTyParaFormat.Extra), a block inside a paragraph ({\*\...} and the destinations WordTable
// marks opaque) as one TTyRichOpaque character. And the file is cut into a header, one byte
// range per paragraph and a trailer, which together are the file, so that a writer can put an
// unchanged paragraph back exactly as it was read.

{$mode objfpc}{$H+}
{$modeswitch advancedrecords}
{$inline on}

interface

uses
  Classes, SysUtils, Graphics, LCLType, tyControls.RichEdit.Text, tyControls.RichEdit.Model;

type
  ETyRichRtf = class(Exception);

  // Bytes [Start, Stop) of the file.
  TTyRtfRange = record
    Start: Int64;
    Stop: Int64;
  end;
  TTyRtfRanges = array of TTyRtfRange;

  // How the reader cut the file: the header (everything before the first paragraph: the
  // tables, \info, document properties), one range per paragraph of the document, and the
  // trailer (what follows the last paragraph: Word's closing blocks, the closing brace,
  // WordPad's CR LF NUL). They follow each other with no gap and no overlap: put together
  // they are Bytes.
  TTyRtfSourceMap = class
  public
    Bytes: TBytes;
    Header: TTyRtfRange;
    Paras: TTyRtfRanges;
    Trailer: TTyRtfRange;
    function ParaCount: Integer;
  end;

  TTyRtfTokenKind = (rtkGroupStart, rtkGroupEnd, rtkWord, rtkSymbol, rtkHex, rtkText, rtkBin);

  // One token, as offsets into the buffer: [Start, Stop) are all its bytes (a control word's
  // delimiting space and \bin's data included). rtkWord and rtkBin: the name is [NameStart,
  // NameStart + NameLen), with Param when HasParam. rtkSymbol: Value is the character (-1: a
  // backslash at the very end). rtkHex: Value is the byte, -1 when fewer than two hex digits
  // followed. rtkBin: the data is [DataStart, Stop) - cut short at the end of the buffer.
  TTyRtfToken = record
    Kind: TTyRtfTokenKind;
    Start: PtrInt;
    Stop: PtrInt;
    NameStart: PtrInt;
    NameLen: Integer;
    HasParam: Boolean;
    Param: Integer;
    Value: Integer;
    DataStart: PtrInt;
  end;

  // Reads tokens from a byte range; allocates nothing. A record, so a copy of it looks
  // ahead without moving the original.
  TTyRtfLexer = record
  private
    FBuf: PByte;
    FPos: PtrInt;
    FEnd: PtrInt;
  public
    procedure Init(ABuf: PByte; APos, AEnd: PtrInt);
    function Next(out T: TTyRtfToken): Boolean;   // False at the end
    property Position: PtrInt read FPos write FPos;
  end;

  TTyRtfDest = (rdNormal, rdFontTable, rdFontEntry, rdColorTable, rdListTable, rdList,
    rdListLevel, rdOverrideTable, rdOverride, rdPict, rdShpPict, rdField, rdFieldResult, rdPn,
    rdUpr);
  TTyRtfSlot = (sloNone, sloLoch, sloHich, sloDbch, sloOther);
  TTyRtfAbsorb = (absNone, absLast, absCurrent);

  // One entry of the lists the properties keep (Extra fragments, tab stops, a row's \cellx):
  // a fragment is the bytes [A, B), a tab stop is at A with B = alignment or leader shl 8, a
  // \cellx is A. Lists are linked backwards (Prev, -1 ends) and never change once made, so a
  // group's saved properties and the current ones share their common part, and saving a group
  // copies no list.
  TTyRtfNode = record
    A, B: Int64;
    Prev: Integer;
    Key: Cardinal;               // a fragment: what it is, for finding its like; 0 otherwise
  end;
  TTyRtfNodes = array of TTyRtfNode;

  // How a fragment that goes into an Extra list takes the place of what the list holds
  // (TTyRtfParser.KeepFragment; internal).
  TTyRtfKeepRule = (
    krName,     // the fragment of the same control word goes: the later value is in effect
    krExact,    // only its like goes - the same word with the same number, or the same bytes
    krHeader,   // a word that the ones after it belong to: \rtlch, a border's side
    krMember);  // a word that belongs to the header before it; replaced among that one's

  // What a kept fragment is: its control word (a group's: its destination), with the number
  // after it. NameLen 0: no word - a control symbol - which is its bytes.
  TTyRtfFragKey = record
    Name: PtrInt;
    NameLen: Integer;
    HasParam: Boolean;
    Param: Integer;
    Rule: TTyRtfKeepRule;
  end;

  // What a group saves and restores. Nothing in it is managed, so a group costs one plain copy
  // of the record; the lists are indices into the parser's node pool (-1: empty).
  TTyRtfProps = record
    Dest: TTyRtfDest;
    DestOwner: Boolean;          // this group began Dest (its end finishes it)
    DestStart: PtrInt;           // where that group's brace is
    Uc: Integer;
    // character
    FontNum: Integer;            // -1: \deff
    LochNum, HichNum, DbchNum: Integer;   // -1: not set
    Slot: TTyRtfSlot;
    Size: Integer;               // half points
    Bold, Italic, Underline, Strike: Boolean;
    VertAlign: TTyVertAlign;
    ColorIdx, HighlightIdx: Integer;
    CharExtra: Integer;
    CharHead, CharLast: Integer; // its header named last, and the last one in it (-1 none)
    // paragraph
    Align: TTyParaAlign;
    LeftIndent, RightIndent, FirstIndent, SpaceBefore, SpaceAfter: Integer;
    Sl, SlMult: Integer;
    SlTok, SlMultTok: TTyRtfRange;
    Tabs: Integer;
    TabAlign: TTyTabAlign;
    TabLeader: TTyTabLeader;
    RtlPar, InTable: Boolean;
    Itap: Integer;
    ListKind: TTyListKind;
    ListLevel, ListStart: Integer;
    Ls, Ilvl: Integer;
    ParaExtra: Integer;
    ParaHead, ParaLast: Integer;
  end;

  TTyRtfRowDef = record
    Cellx: Integer;              // a node list, the last \cellx first
    Merged: Boolean;
    Raw: TTyRtfRange;
  end;

  // Everything the parse depends on at a point between two tokens, but the group stack and
  // the node pool (the parser holds those; a TTyRtfState carries copies).
  TTyRtfCore = record
    Pos: PtrInt;                 // the next token
    Props: TTyRtfProps;
    Depth: Integer;              // groups open, the document's included
    Overflow: Integer;           // groups past MaxDepth, counted only
    GroupOpen, Star: Boolean;    // just after a brace (and its \*)
    GroupStart: PtrInt;
    UcSkip: Integer;             // fallback items still to skip
    PendingLead: Integer;        // a lead byte waiting for its trail byte, -1 none
    PendingLeadFont: Integer;
    PendingHigh: Integer;        // a high surrogate waiting for its low half, 0 none
    OneShot: TTyRtfRange;        // \- for the next character (Start < 0: none)
    BodyStarted: Boolean;
    PendingGroup: PtrInt;        // before the body: the outermost brace not yet known as header
    PendingGroupDepth: Integer;
    HeaderEnd: PtrInt;
    Boundary: PtrInt;            // where the current paragraph's bytes start
    BoundaryDepth: Integer;      // the depth there
    LastStartDepth: Integer;     // the depth where the paragraph before started
    Absorb: TTyRtfAbsorb;        // what closing braces and line breaks still extend
    HasContent: Boolean;         // the current paragraph has a character
    CurEnd: PtrInt;              // its bytes so far end here
    LastWasCell: Boolean;
    DocClosed: Boolean;
    DocCloseAt: PtrInt;
    Paras: Integer;              // paragraphs ended so far
    InRowDef: Boolean;
    RowDef: TTyRtfRowDef;
    CellIdx, RowMax: Integer;
    TableOpen, Nested: Boolean;
    RowNested: Boolean;          // the row being read holds a nested table
  end;

  // A snapshot: everything the parse depends on at a point between two tokens (with the
  // header's tables, which the parser that resumes copies separately). Its node pool holds
  // only what its lists use.
  TTyRtfState = record
    Core: TTyRtfCore;
    Stack: array of TTyRtfProps;   // Core.Depth entries (at most MaxDepth)
    Nodes: TTyRtfNodes;
    TablesGen: Integer;            // the parser's table generation when it was taken
    // Bytes it holds.
    function MemSize: Int64;
  end;
  TTyRtfStateArray = array of TTyRtfState;

  // Where a table's paragraphs are: global paragraph indices and the bytes from the start of
  // its first paragraph to the end of its last.
  TTyRtfTableExtent = record
    FirstPara, LastPara: Integer;
    Start, Stop: Int64;
  end;

  TTyRtfFont = record
    Num: Integer;
    Charset: Integer;            // -1: none given
    Cpg: Integer;                // 0: none given
    CodePage: Integer;           // resolved; CpSymbol for the Symbol charset
    Table: Pointer;
    Name: UTF8String;
  end;

  TTyRtfListLevel = record
    Nfc: Integer;
    Start: Integer;
  end;

  TTyRtfList = record
    Id: Integer;
    Levels: array of TTyRtfListLevel;
  end;

  TTyRtfParaKind = (rpkPar, rpkCell, rpkNestCell);

  TTyRtfParaRec = record
    Src: TTyRtfRange;
    Chars: Int64;
    Format: TTyParaFormatId;
    Runs: TTyRunArray;
    Table, Row, Cell: Integer;   // Table -1: not in a table
    TextStart: PtrInt;           // building: its UTF-8 in the parser's output (no separator)
    TextLen: Integer;
  end;

  TTyRtfRowRec = record
    CellCount: Integer;
    Raw: TTyRtfRange;
    Cellx: array of Integer;
    Nested: Boolean;             // one of its cells holds a table (TTyRichRow.HoldsNestedTable)
  end;

  TTyRtfTableRec = record
    Rows: array of TTyRtfRowRec;
    RowCount: Integer;
    Locked: Boolean;
  end;

  TTyRtfCharClass = (rccLoch, rccHich, rccDbch);

  // The parser. With a format pool it builds paragraphs (text, runs, formats, objects, table
  // cells); without one it only counts each paragraph's characters, by the same code and the
  // same decoding rules, and builds nothing. It never writes into a document:
  // TyRichLoadRtf does that from what it collected.
  TTyRtfParser = class
  private
    FBytes: TBytes;
    FBuf: PByte;
    FLen: PtrInt;
    FLex: TTyRtfLexer;
    FS: TTyRtfCore;
    FStack: array of TTyRtfProps;
    FNodes: TTyRtfNodes;
    FNodeN: Integer;
    FCompactAt: Integer;
    FPool: TTyFormatPool;
    FTok: TTyRtfToken;
    FTokStop: PtrInt;
    FContent, FCommitted: Boolean;
    FFinished: Boolean;
    FTrailerStart: PtrInt;
    // the header's tables
    FTablesGen: Integer;         // changes whenever one of them does
    FVersions: TFPList;          // parsers holding the tables in effect at a snapshot
    FVersionGen: Integer;
    FAnsiCp: Integer;
    FAnsiCpSet: Boolean;
    FDeff: Integer;
    FPaperW, FPaperH, FMargL, FMargR: Integer;
    FFonts: array of TTyRtfFont;
    FFontCount: Integer;
    FFontsSorted: Boolean;
    FFontGen: Integer;
    FColors: array of TColor;
    FColorAuto: array of Boolean;
    FColorCount: Integer;
    FColorR, FColorG, FColorB: Integer;
    FColorAny: Boolean;
    FFontTblClose, FColorTblClose: PtrInt;   // the header's tables' closing braces, -1 none
    FFontTblOpen: PtrInt;                    // the font table's opening brace, -1 none
    FLastOpen: Boolean;          // the last paragraph ended without a terminator
    FLists: array of TTyRtfList;
    FListCount: Integer;
    FOverrideLs, FOverrideId: array of Integer;
    FOverrideCount: Integer;
    // a font entry, a list, a list level, an override being read
    FEntryOn: Boolean;
    FEntry: TTyRtfFont;
    FEntryRaw: RawByteString;
    FCurList: TTyRtfList;
    FCurLevel: TTyRtfListLevel;
    FCurOvLs, FCurOvId: Integer;
    // decoding: the table of the font in effect
    FDecNum, FDecGen: Integer;
    FDecCp: Integer;
    FDecTable: Pointer;
    FDecCls: PByte;               // its byte classes and pairs, for the scan
    FDecPairs: PByte;
    // a picture being read
    FPicFormat: TTyRichPictureFormat;
    FPicData: TBytes;
    FPicLen: Integer;
    FPicNibble: Integer;
    FPicW, FPicH, FPicWGoal, FPicHGoal, FPicSX, FPicSY: Integer;
    FHeld: TTyRichPicture;      // read inside \shppict, shown when it ends
    // fields
    FFieldNest: Integer;
    FFieldText: UTF8String;
    FFieldLen: Integer;
    FFirstFont: Integer;         // the number of the font table's first entry, -1 none
    // format ids for the properties in effect
    FCharValid: array[TTyRtfCharClass] of Boolean;
    FCharId: array[TTyRtfCharClass] of TTyCharFormatId;
    FParaValid: Boolean;
    FParaId: TTyParaFormatId;
    // what was read
    FOut: TBytes;
    FOutLen: PtrInt;
    FParaTextStart: PtrInt;
    FSep: RawByteString;
    FRuns: TTyRunArray;
    FRunN: Integer;
    FCurChars: Int64;
    FParas: array of TTyRtfParaRec;
    FParaN: Integer;
    FParaBase: Integer;          // paragraphs handed out with DropParas
    FTables: array of TTyRtfTableRec;
    FTableN: Integer;
    FExtents: array of TTyRtfTableExtent;
    FExtentN: Integer;
    FObjects: TFPList;           // every object made, for freeing the ones not used
    FKeepSnapshots: Boolean;
    FSnapshotEvery: Int64;
    FNextSnapshotAt: Int64;
    FSnapshots: array of TTyRtfState;
    FSnapshotN: Integer;
    function Counting: Boolean; inline;
    procedure InitState;
    // the node pool
    function Push(AList: Integer; A, B: Int64): Integer;
    function PushKey(AList: Integer; A, B: Int64; AKey: Cardinal): Integer;
    function KeepFragment(var AList, AHead, ALast: Integer; AStart, AStop: PtrInt;
      APara: Boolean): Boolean;
    procedure ChangeList(var AList, AHead, ALast: Integer; AStart, AStop: PtrInt;
      ARule: TTyRtfKeepRule; AKey: Cardinal; AFound: Integer);
    procedure Settle(var AList, AHead, ALast: Integer);
    procedure SettleLists;
    function ListNodes(AList: Integer): TTyRtfNodes;
    procedure Compact;
    procedure TakeSnapshot;
    function FastRun(AStopPos: PtrInt): Boolean;
    procedure MarkContent; inline;
    procedure TablesChanged; inline;
    procedure SetSnapshotEvery(AValue: Int64);
    // tokens
    procedure DoGroupStart;
    function DoGroupEnd: Boolean;
    function DoText: Boolean;
    procedure DoWord;
    procedure DoSymbol;
    procedure DoHex;
    procedure DoBin;
    procedure PopGroup;
    function SkipGroup: PtrInt;
    procedure SkipAndPop;
    function HandleDestination(AKw: Integer): Boolean;
    procedure BeginDest(ADest: TTyRtfDest);
    procedure EndDest(const AOld: TTyRtfProps);
    procedure Extend(AWasBrace: Boolean);
    // body, paragraphs, tables
    procedure EnsureBody;
    procedure StartContent;
    procedure EndParagraph(AKind: TTyRtfParaKind);
    procedure DoRow;
    procedure FinishRow;
    procedure CloseTable;
    procedure MarkNested; inline;
    procedure EndRowDef;
    procedure Finish;
    // characters
    procedure Flush;
    procedure EmitCode(ACode: Cardinal; AFromPair: Boolean);
    procedure EmitChar(ACode: Cardinal);
    procedure EmitUnicode(AValue: Integer);
    procedure ProcessByte(B: Byte);
    procedure EmitObject(AObj: TTyRichObject);
    procedure EmitOpaque(AStart, AStop: PtrInt; const ADisplay: UTF8String);
    procedure PutOut(ACode: Cardinal);
    procedure PutField(ACode: Cardinal);
    procedure AddRun(AFormat: TTyCharFormatId; AObj: TTyRichObject);
    // words by destination
    procedure BodyWord(AKw: Integer);
    procedure FontWord(AKw: Integer);
    procedure ListWord(AKw: Integer);
    procedure PictWord(AKw: Integer);
    procedure AddCharExtra(AStart, AStop: PtrInt);
    procedure AddParaExtra(AStart, AStop: PtrInt);
    procedure ResetChar;
    procedure ResetPara;
    procedure CharChanged;
    procedure ParaChanged;
    // tables of the header
    procedure BeginFontEntry(ANum: Integer);
    procedure FinishFontEntry;
    procedure SortFonts;
    function FontIndex(ANum: Integer): Integer;
    function FontOfNum(ANum: Integer): Integer;
    function ResolveCodePage(ACharset, ACpg: Integer): Integer;
    function DecodeRaw(const ARaw: RawByteString; ACodePage: Integer): UTF8String;
    procedure UpdateDecoder;
    procedure AddColor;
    function ColorOf(AIndex: Integer; ADefault: TColor): TColor;
    // formats
    function SlotsSet: Boolean; inline;
    function ClassOf(ACode: Cardinal; AFromPair: Boolean): TTyRtfCharClass;
    function BuildCharFormat(AClass: TTyRtfCharClass; AOneShot: Boolean): TTyCharFormat;
    function CharFormatFor(AClass: TTyRtfCharClass): TTyCharFormatId;
    function PlainListWords(const ANodes: TTyRtfNodes): Boolean;
    function BuildParaFormat: TTyParaFormat;
    function ParaFormatId: TTyParaFormatId;
    function Fragment(const R: TTyRtfRange): RawByteString;
    // pictures
    procedure BeginPicture;
    function TakePicture(AStart, AStop: PtrInt): TTyRichPicture;
    procedure PutPicByte(B: Byte);
  public
    // APool nil: count characters only. The parser keeps a reference to ABytes.
    constructor Create(const ABytes: TBytes; APool: TTyFormatPool);
    destructor Destroy; override;
    // Reads from where the state stands to the end of the document.
    procedure Parse;
    // Reads on until the document ends (then True), or stops after the token that reaches
    // AStopPos, or once AStopParas paragraphs (counted from the start of the document) have
    // ended and no table row is still open (-1: no such limit).
    function ParseUntil(AStopPos: PtrInt; AStopParas: Integer): Boolean;
    // The state, as a snapshot to resume from.
    function SaveState: TTyRtfState;
    // Goes on from AState (taken by a parser over the same bytes); copy the header's tables
    // first with CopyTablesFrom.
    procedure Resume(const AState: TTyRtfState);
    procedure CopyTablesFrom(AOther: TTyRtfParser);
    function DefaultCharFormat: TTyCharFormat;
    // The UTF-8 text read, paragraphs separated by the platform's line break.
    function TextBytes: TBytes;
    // Paragraph AIndex's text (building only), without its separator.
    function ParaText(AIndex: Integer): RawByteString;
    // The paragraphs this parser read (after a Resume: ParaRec(0) is the first after the
    // snapshot), the dropped ones included.
    function ParaCount: Integer;
    function ParaRec(AIndex: Integer): TTyRtfParaRec;
    // A paragraph's bytes and characters (no record with a managed field copied).
    procedure ParaSpan(AIndex: Integer; out ASrc: TTyRtfRange; out AChars: Int64);
    // The first paragraph ParaRec still has.
    property FirstParaRec: Integer read FParaBase;
    // Forgets the records of the paragraphs before AIndex (an index scan keeps no record of
    // the whole document). The last paragraph that ended stays: its range may still grow.
    procedure DropParas(AIndex: Integer);
    function TableCount: Integer;
    function TableRec(AIndex: Integer): TTyRtfTableRec;
    // Where each table that ended is (also when counting).
    function TableExtentCount: Integer;
    function TableExtent(AIndex: Integer): TTyRtfTableExtent;
    function HeaderEnd: PtrInt;
    function TrailerStart: PtrInt;
    function BodyStarted: Boolean;
    function Finished: Boolean;
    function Position: PtrInt;
    function SnapshotCount: Integer;
    function Snapshot(AIndex: Integer): TTyRtfState;
    // Hands the snapshots taken so far over (they are no longer the parser's).
    function TakeSnapshots: TTyRtfStateArray;
    // A parser holding the header's tables as they were when the snapshots of generation
    // AGen were taken (owned by this parser).
    function TablesOf(AGen: Integer): TTyRtfParser;
    function FragmentOf(const R: TTyRtfRange): RawByteString;
    // The objects made, as owned by the caller from now on (each with one reference taken).
    function TakeObjects: TFPList;
    // For a writer - the header's tables as they were read: the fonts (in the order of their
    // numbers once their table has ended), the colours (AAuto: the entry names no colour),
    // and what a paragraph's \lsN \ilvlN mean through the list tables (AList is left as it
    // is when N names no list).
    function FontCount: Integer;
    function Font(AIndex: Integer): TTyRtfFont;
    function ColorCount: Integer;
    function Color(AIndex: Integer; out AAuto: Boolean): TColor;
    procedure ResolveListRef(ALs, AIlvl: Integer; var AList: TTyListFormat);
    property AnsiCodePage: Integer read FAnsiCp;
    property DefaultFont: Integer read FDeff;     // \deff, -1 none
    // Where the first font table and the first colour table before the body close (the
    // position of their closing brace), -1 when the header has none.
    property FontTableClose: PtrInt read FFontTblClose;
    property ColorTableClose: PtrInt read FColorTblClose;
    // The highest N of the \fN words between the braces of that font table: of every entry,
    // also of those this reader passes over (a group that begins with neither \f nor a
    // theme font's role) and of groups inside them. A writer numbers new fonts above it.
    // -1: no font table, or no \fN in it.
    function FontTableHighest: Integer;
    // After the parse: the last paragraph has no terminator (its bytes run to the trailer),
    // so nothing can be written after it as it is.
    property LastParaOpen: Boolean read FLastOpen;
    property Bytes: TBytes read FBytes;
    property PaperWidth: Integer read FPaperW;
    property PaperHeight: Integer read FPaperH;
    property MarginLeft: Integer read FMargL;
    property MarginRight: Integer read FMargR;
    // Keep the state after each token that ended a paragraph (resuming from it reads the
    // rest exactly as the whole parse did).
    property KeepSnapshots: Boolean read FKeepSnapshots write FKeepSnapshots;
    // Keep the state at the first paragraph end (outside a table row) at least this many
    // bytes after the one before: an index scan's resume points. 0: none.
    property SnapshotEvery: Int64 read FSnapshotEvery write SetSnapshotEvery;
  end;

const
  // An index scan keeps a snapshot at the first paragraph end after every this many bytes;
  // parsing on demand reads from the snapshot before a paragraph to the next one.
  CRtfSnapshotBytes = 65536;
  // A table whose rows take more bytes than this is not parsed as a whole when one of its
  // paragraphs is needed: each stretch between snapshots becomes a table of its own
  // (StructureLocked), so that a giant table cannot make one paragraph slow to show.
  CRtfBigTableBytes = 1 shl 20;
  // Intervals that share a table are parsed together, so that the table is one table - up to
  // this many. Tables that follow each other closely can link interval to interval through
  // the whole file; such a chain is parsed in blocks of this many intervals, and a table cut
  // where a block ends is two parts (StructureLocked), as a big table's are.
  CRtfGroupIntervals = CRtfBigTableBytes div CRtfSnapshotBytes;
  // How many snapshot intervals stay parsed (their formats set, their text decoded) before
  // the least recently used ones go back to unparsed.
  CRtfResidentIntervals = 16;
  // What TyRichBeginLoadRtf indexes before it returns (then Step goes on).
  CRtfFirstSliceBytes = 4 shl 20;

type
  TTyRtfProgressEvent = procedure(Sender: TObject; ADone, ATotal: Int64) of object;

  TTyRtfGroup = class;

  // A paragraph value the load set that outlived its group: the paragraph at ASrc still
  // has Value (held), and is the file's own while it does.
  TTyRtfKept = record
    Src: Int64;
    Value: Pointer;
  end;

  // An RTF document being loaded, and then parsed on demand: the file's bytes, the header's
  // tables (through the scan), the snapshots, the header and trailer ranges and where the
  // tables are. It lives as long as its document's content does (the document owns it through
  // its paragraph loader).
  TTyRtfLoad = class
  private
    FDoc: TTyRichDocument;
    FBytes: TBytes;
    FScan: TTyRtfParser;             // the index scan; it also keeps the header's tables
    FSep: TTyRichSeparator;          // what separates paragraphs in the text
    // Interval i: the bytes from FIntervalPos[i] (its snapshot, FSnaps[i]; interval 0 is read
    // from the start of the file) to the next interval's start; its first paragraph
    FSnaps: TTyRtfStateArray;
    FIntervalPos: array of Int64;
    FIntervalPara: array of Integer;
    FIntervalN: Integer;
    FSnapBytes: Int64;
    FAppended: Integer;              // paragraphs in the document's text
    FDone, FCancelled: Boolean;
    FHeaderEnd: Int64;
    FTrailer: TTyRtfRange;
    FMap: TTyRtfSourceMap;           // ranges for the caller of TyRichLoadRtf
    FMapN: Integer;
    FQuiet: Boolean;                 // no OnChange per slice (the caller reports once)
    FGroups: TFPList;                // parsed groups of intervals, most recently used last
    FResident: Integer;              // intervals the groups hold
    FMaxResident: Integer;
    FStamp: Int64;
    FKept: array of TTyRtfKept;      // by Src
    FKeptN: Integer;
    // the group the last read used, and the paragraphs that are its own while the text has
    // FUsedParas paragraphs and FUsedLength characters
    FUsedGroup: TTyRtfGroup;
    FUsedFirst, FUsedStop, FUsedParas: Integer;
    FUsedLength: Int64;
    FParsedBytes: Int64;
    FParseCount: Integer;
    FWhole: Boolean;
    FCheck: TTyRtfGroup;             // ParseWhole: the group being compared with the index
    FCheckBad: Integer;
    FWalk: TTyRtfParser;             // StateAt's own scan, kept to go on from
    FOnLoadProgress: TTyRtfProgressEvent;
    procedure Index(ABudget: Int64; AMinParas: Integer);
    procedure Collect;
    procedure Append(AFrom, ATo: Integer);
    procedure AddMapRange(const R: TTyRtfRange);
    procedure Finish;
    function IntervalOf(ASrc: Int64): Integer;
    function IntervalOfPara(APara: Integer): Integer;
    function IntervalParaStop(AIndex: Integer): Integer;
    function IsBig(const X: TTyRtfTableExtent): Boolean;
    function Linked(AInterval, ALo, AHi, AMax: Integer; out AFirst, ALast: Integer): Boolean;
    function ExtentAt(APara: Integer): Integer;
    function GroupOf(ASrc: Int64): TTyRtfGroup;
    function GroupFor(ASrc: Int64; out AIndex: Integer): TTyRtfGroup;
    function ParseGroup(AInterval: Integer): TTyRtfGroup;
    function GroupFrom(AParser: TTyRtfParser; AFirst, ALast: Integer): TTyRtfGroup;
    procedure ParseWhole;
    procedure CheckWhole(AIndex: Integer; AData: Pointer; ASrcOffset, ASrcBytes: Int64;
      var AContinue: Boolean);
    procedure Touch(AGroup: TTyRtfGroup);
    procedure Used(AIndex: Integer);
    function KeptAt(ASrc: Int64; out AIndex: Integer): Boolean;
    procedure KeepValue(ASrc: Int64; AValue: Pointer);
    procedure Unkeep(AIndex: Integer);
    procedure Apply(AGroup: TTyRtfGroup);
    procedure Drop(AGroup: TTyRtfGroup; AReset: Boolean);
    procedure FreeGroup(AGroup: TTyRtfGroup);
    function Decode(ASrcOffset, ASrcBytes, ACharCount: Int64): UTF8String;
    procedure LoadParagraph(AIndex: Integer);
  public
    constructor Create(ADoc: TTyRichDocument; const ABytes: TBytes);
    destructor Destroy; override;
    // Indexes about AByteBudget more bytes of the file (at least one token) and appends the
    // paragraphs found to the document (OnChange: they come after its last paragraph); True
    // when the whole file is indexed - the document can then be changed. Deterministic: a
    // byte budget, not a clock (the control calls it from idle time and watches the clock).
    // The document's OnChange and OnLoadProgress run inside it: a handler must not put
    // other content into the document (that frees this object, which Step still uses).
    // Whoever keeps a load across such events asks TyRichRtfLoadOf(document) for it again.
    function Step(AByteBudget: Int64): Boolean;
    // Stops indexing: the document keeps what was indexed and stays read-only, Incomplete
    // (a writer must refuse to save it - the rest of the file is not in it).
    procedure Cancel;
    // Sends the least recently used parsed intervals back to unparsed until at most
    // MaxResidentIntervals remain. Used means read: a read of a paragraph that is parsed
    // counts as much as the read that parsed it. Does nothing while a command runs or a read
    // scope is open (TTyRichDocument.BeginRead): the tables, cells and objects of an
    // interval go with it, and whoever reads inside a scope still holds them. A read that
    // parses does this by itself, and so does the end of the outermost read scope.
    //
    // A table of which a paragraph was changed stays as it is when its interval goes (it is
    // one object for all its paragraphs): those paragraphs keep their values, and the load
    // keeps a record of each, so that they are still known as the file's own (ParaSource,
    // OwnsValue) and are the group's again when the interval is next parsed.
    procedure Trim;
    // For a writer: paragraph AIndex is still the file's own, untouched (its text and formats
    // never changed), at ARange of Bytes.
    function ParaSource(AIndex: Integer; out ARange: TTyRtfRange): Boolean;
    // The second half of ParaSource, for a writer that walks the paragraphs itself: the
    // unedited lazy paragraph from ASrcOffset, whose value is AValue, still has the formats
    // the file gives it (AValue nil - never parsed - or the very value this load set,
    // whether its interval is parsed at the moment or not).
    function OwnsValue(ASrcOffset: Int64; AValue: Pointer): Boolean;
    // For a writer: the reader's state at byte APos of the file - a paragraph's start, or the
    // trailer's - scanned from the snapshot before it (no paragraph is parsed, nothing is
    // set in the document). Asking for rising positions goes on from the last one. False
    // when the scan cannot stop exactly there, or the file ends before it.
    function StateAt(APos: Int64; out AState: TTyRtfState): Boolean;
    // The index scan, for the header's tables (TTyRtfParser.Font, Color, ...).
    property Scan: TTyRtfParser read FScan;
    // The file's last paragraph has no terminator: what follows it in the file is the trailer.
    function LastParaOpen: Boolean;
    property Bytes: TBytes read FBytes;
    // Before the first paragraph: the tables, the document's properties.
    function Header: TTyRtfRange;
    // After the last paragraph to the end of the file (Start = Stop = -1 until Done).
    property Trailer: TTyRtfRange read FTrailer;
    property Done: Boolean read FDone;
    property Cancelled: Boolean read FCancelled;
    function BytesIndexed: Int64;
    function BytesTotal: Int64;
    property OnLoadProgress: TTyRtfProgressEvent read FOnLoadProgress write FOnLoadProgress;
    // What parsing on demand did (tests and probes)
    property ParsedBytes: Int64 read FParsedBytes;
    property ParseCount: Integer read FParseCount;
    // The file was parsed as a whole (TyRichLoadRtfFull): one parse from its first byte to
    // its last set every paragraph, and nothing is ever sent back to unparsed.
    property Whole: Boolean read FWhole;
    function SnapshotCount: Integer;
    // Interval i (0 .. IntervalCount - 1): its bytes start at IntervalStart (interval 0 at
    // the start of the file, the others at their snapshot); its first paragraph.
    function IntervalCount: Integer;
    function IntervalStart(AIndex: Integer): Int64;
    function IntervalFirstPara(AIndex: Integer): Integer;
    property SnapshotBytes: Int64 read FSnapBytes;
    property ResidentIntervals: Integer read FResident;
    property MaxResidentIntervals: Integer read FMaxResident write FMaxResident;
  end;

  // Intervals parsed together: one, or more when a table crosses their boundaries (internal).
  TTyRtfGroup = class
  public
    FirstSnap, LastSnap: Integer;    // its intervals
    Recs: array of TTyRtfParaRec;    // as parsed (Table is an index into Tables)
    Texts: array of RawByteString;   // each paragraph's text, without its separator
    States: array of Byte;           // set by us (Values holds the value, held), or not
    Values: array of Pointer;
    Tables: array of TTyRichTable;   // held
    Objects: TFPList;                // held
    Stamp: Int64;                    // when it was last used
    function Find(ASrc: Int64): Integer;
    function HasValues: Boolean;
  end;

// Replaces ADoc's content with the RTF document in AStream, from its position to its end (as
// loading, not as a change: the history goes and Modified is False). Raises ETyRichRtf when
// the bytes do not start with the RTF signature; anything after that loads as far as it goes,
// however broken.
//
// The load only indexes the file: one fast scan finds every paragraph's bytes and characters
// and keeps a snapshot of the parse state every CRtfSnapshotBytes; a paragraph's formats and
// text are parsed the first time somebody reads them (TTyRichDocument.EnsureParsed, or the
// text), from the snapshot before it to the next. TyRichBeginLoadRtf indexes about AFirstSlice
// bytes (and at least the header and two paragraphs) and returns; the document then holds
// what was indexed, can be read but not changed (Loading), and Step indexes the rest. The
// returned object belongs to the document.
function TyRichBeginLoadRtf(ADoc: TTyRichDocument; AStream: TStream;
  AFirstSlice: Int64 = CRtfFirstSliceBytes): TTyRtfLoad;
// TyRichBeginLoadRtf and then Step to the end, raising OnChange once. AMap, when given, gets
// the file's bytes and how they were cut.
procedure TyRichLoadRtf(ADoc: TTyRichDocument; AStream: TStream; AMap: TTyRtfSourceMap = nil);
// As TyRichLoadRtf, and then the whole file parsed at once: one parse from the first byte to
// the last - not interval by interval from the snapshots - sets every paragraph's formats
// and text, and they stay (TTyRtfLoad.Whole). For comparison (tests) and for callers that
// want every paragraph read right away. The document has its load like any other read from
// RTF, so it is saved as its file: unchanged paragraphs as their bytes, with the file's
// header. Raises ETyRichRtf when the parse and the index do not find the same paragraphs.
procedure TyRichLoadRtfFull(ADoc: TTyRichDocument; AStream: TStream; AMap: TTyRtfSourceMap = nil);
// The RTF load ADoc's content came from; nil when it did not come from TyRichLoadRtf (or
// TyRichBeginLoadRtf), or after it was replaced.
function TyRichRtfLoadOf(ADoc: TTyRichDocument): TTyRtfLoad;

type
  // Where the reader finds a fragment of TTyParaFormat.Extra: among a paragraph's own words
  // (pekTop; \lsN and \ilvlN apart, with N), or inside its {\*\pn ...} group (pekPn) - which
  // is where a writer has to put it back for the reader to keep it on the paragraph again.
  TTyRtfParaExtraKind = (pekTop, pekPn, pekLs, pekIlvl);

function TyRtfParaExtraKind(const AFragment: RawByteString; out AParam: Integer): TTyRtfParaExtraKind;
// True when the fragment is the control word AName (with any parameter).
function TyRtfFragmentIsWord(const AFragment: RawByteString; const AName: string): Boolean;
// The reverse of the reader, for a writer that has written something of its own and now
// copies the file's bytes again from the place AState was taken at (TTyRtfLoad.StateAt): the
// control words - beginning with \pard\plain, ending with a control word and no delimiter -
// that leave a reader with exactly the properties those bytes were read with: \uc, the font
// and Word's three font slots, the character and paragraph properties, and every unknown
// word kept as Extra, in its order. ALevel -1: the properties in effect at that place;
// 0 .. Depth - 1: the properties the group open at that depth saved (AState.Stack), which
// come back when the file's bytes close it - a writer puts them in effect and then opens the
// group again. ATable False leaves out \intbl and \itap: for a place where the paragraph
// that follows is in no table, so that whatever "in a table" was in effect there ends
// before the paragraph does and changes nothing - while the system's RichEdit loses the
// paragraph after an \intbl that no cell follows. ABytes is the file AState was taken from.
function TyRtfStateWords(const AState: TTyRtfState; const ABytes: TBytes;
  ALevel: Integer = -1; ATable: Boolean = True): RawByteString;
// The code page the reader decodes a font's bytes (and its name) with: its \fcharset's, else
// the file's \ansicpg; 0 for the Symbol charset, which has none.
function TyRtfCharsetCodePage(ACharset, AAnsiCodePage: Integer): Integer;

implementation

uses
  tyControls.RichEdit.TextIO;

const
  CpSymbol = -2;
  MaxDepth = 4096;        // groups deeper than this are only counted
  DefaultSize = 24;       // RTF's 12 pt

// ---- the words the reader knows ----

const
  kwUnknown = 0;
  // document
  kwRtf = 1; kwAnsi = 2; kwMac = 3; kwPc = 4; kwPca = 5; kwAnsiCpg = 6; kwDeff = 7;
  kwPaperW = 8; kwPaperH = 9; kwMargL = 10; kwMargR = 11; kwUc = 12; kwU = 13;
  // character
  kwPlain = 20; kwB = 21; kwI = 22; kwUl = 23; kwUlNone = 24; kwStrike = 25; kwSuper = 26;
  kwSub = 27; kwNoSuperSub = 28; kwF = 29; kwAf = 30; kwFs = 31; kwCf = 32; kwHighlight = 33;
  kwLoch = 34; kwHich = 35; kwDbch = 36; kwRtlCh = 37; kwLtrCh = 38;
  // paragraph
  kwPard = 40; kwQl = 41; kwQc = 42; kwQr = 43; kwQj = 44; kwLi = 45; kwRi = 46; kwFi = 47;
  kwSb = 48; kwSa = 49; kwSl = 50; kwSlMult = 51; kwTx = 52; kwTqc = 53; kwTqr = 54;
  kwTqDec = 55; kwTlDot = 56; kwTlHyph = 57; kwTlUl = 58; kwTlTh = 59; kwTlEq = 60;
  kwRtlPar = 61; kwLtrPar = 62; kwIntbl = 63; kwItap = 64; kwLs = 65; kwIlvl = 66;
  kwParaExtra = 67;
  kwPnLvlBlt = 70; kwPnLvlBody = 71; kwPnLvl = 72; kwPnDec = 73; kwPnLcLtr = 74; kwPnUcLtr = 75;
  kwPnLcRm = 76; kwPnUcRm = 77; kwPnStart = 78;
  // table
  kwTrowd = 80; kwCellx = 81; kwClMerge = 82; kwCell = 83; kwRow = 84; kwNestCell = 85;
  kwNestRow = 86;
  // characters
  kwPar = 90; kwLine = 91; kwTab = 92; kwLdblquote = 93; kwRdblquote = 94; kwLquote = 95;
  kwRquote = 96; kwEmdash = 97; kwEndash = 98; kwBullet = 99; kwEmspace = 100;
  kwEnspace = 101; kwQmspace = 102; kwZwj = 103; kwZwnj = 104; kwLtrMark = 105;
  kwRtlMark = 106; kwZwbo = 107; kwZwnbo = 108;
  kwObjWord = 110;          // stands for a character the reader does not produce
  // the header's tables
  kwFcharset = 120; kwCpg = 121; kwRed = 122; kwGreen = 123; kwBlue = 124; kwLevelNfc = 125;
  kwLevelStartAt = 126; kwListId = 127;
  // pictures
  kwPngBlip = 130; kwJpegBlip = 131; kwDibitmap = 132; kwWbitmap = 133; kwWmetafile = 134;
  kwEmfBlip = 135; kwPicW = 136; kwPicH = 137; kwPicWGoal = 138; kwPicHGoal = 139;
  kwPicScaleX = 140; kwPicScaleY = 141;
  // destinations
  kwDFontTbl = 150; kwDColorTbl = 151; kwDListTable = 152; kwDList = 153; kwDListLevel = 154;
  kwDOverrideTable = 155; kwDOverride = 156; kwDPict = 157; kwDShpPict = 158;
  kwDField = 159; kwDFldInst = 160; kwDFldRslt = 161; kwDListText = 162; kwDPn = 163;
  kwDPnText = 164; kwDUpr = 165; kwDUd = 166;
  kwDNestSkip = 167;        // a nested table's properties: in the paragraph's bytes only
  kwDDocSkip = 168;         // document-level: header or trailer bytes
  kwDHeaderFooter = 169;    // in the header region: header bytes; in the body: an object
  kwDOpaque = 170;          // a non-text block: one object
  kwDCharExtra = 171;       // a property group: the run's Extra
  kwDParaExtra = 172;       // a property group: the paragraph's Extra

type
  TWordDef = record
    N: string;
    K: Integer;
  end;

const
  // One table of every word the reader treats specially. Destinations the reader does not
  // implement are here as kwDOpaque (a block in a paragraph: one object holding its bytes),
  // kwDDocSkip (document level: kept in the header or trailer bytes), kwDHeaderFooter,
  // kwDCharExtra / kwDParaExtra. A {\*\...} destination not in this table is opaque too; a
  // word not in it is an unknown character property (the run's Extra), and kwParaExtra marks
  // paragraph properties that are kept as the paragraph's Extra.
  WordTable: array[0..271] of TWordDef = (
    (N: 'rtf'; K: kwRtf), (N: 'ansi'; K: kwAnsi), (N: 'mac'; K: kwMac), (N: 'pc'; K: kwPc),
    (N: 'pca'; K: kwPca), (N: 'ansicpg'; K: kwAnsiCpg), (N: 'deff'; K: kwDeff),
    (N: 'paperw'; K: kwPaperW), (N: 'paperh'; K: kwPaperH), (N: 'margl'; K: kwMargL),
    (N: 'margr'; K: kwMargR), (N: 'uc'; K: kwUc), (N: 'u'; K: kwU),
    (N: 'plain'; K: kwPlain), (N: 'b'; K: kwB), (N: 'i'; K: kwI), (N: 'ul'; K: kwUl),
    (N: 'ulnone'; K: kwUlNone), (N: 'strike'; K: kwStrike), (N: 'super'; K: kwSuper),
    (N: 'sub'; K: kwSub), (N: 'nosupersub'; K: kwNoSuperSub), (N: 'f'; K: kwF),
    (N: 'af'; K: kwAf), (N: 'fs'; K: kwFs), (N: 'cf'; K: kwCf), (N: 'highlight'; K: kwHighlight),
    (N: 'loch'; K: kwLoch), (N: 'hich'; K: kwHich), (N: 'dbch'; K: kwDbch),
    (N: 'rtlch'; K: kwRtlCh), (N: 'ltrch'; K: kwLtrCh),
    (N: 'pard'; K: kwPard), (N: 'ql'; K: kwQl), (N: 'qc'; K: kwQc), (N: 'qr'; K: kwQr),
    (N: 'qj'; K: kwQj), (N: 'li'; K: kwLi), (N: 'ri'; K: kwRi), (N: 'fi'; K: kwFi),
    (N: 'sb'; K: kwSb), (N: 'sa'; K: kwSa), (N: 'sl'; K: kwSl), (N: 'slmult'; K: kwSlMult),
    (N: 'tx'; K: kwTx), (N: 'tqc'; K: kwTqc), (N: 'tqr'; K: kwTqr), (N: 'tqdec'; K: kwTqDec),
    (N: 'tldot'; K: kwTlDot), (N: 'tlhyph'; K: kwTlHyph), (N: 'tlul'; K: kwTlUl),
    (N: 'tlth'; K: kwTlTh), (N: 'tleq'; K: kwTlEq), (N: 'rtlpar'; K: kwRtlPar),
    (N: 'ltrpar'; K: kwLtrPar), (N: 'intbl'; K: kwIntbl), (N: 'itap'; K: kwItap),
    (N: 'ls'; K: kwLs), (N: 'ilvl'; K: kwIlvl),
    // paragraph properties the model does not have
    (N: 's'; K: kwParaExtra), (N: 'keep'; K: kwParaExtra), (N: 'keepn'; K: kwParaExtra),
    (N: 'widctlpar'; K: kwParaExtra), (N: 'nowidctlpar'; K: kwParaExtra),
    (N: 'hyphpar'; K: kwParaExtra), (N: 'outlinelevel'; K: kwParaExtra),
    (N: 'pagebb'; K: kwParaExtra), (N: 'noline'; K: kwParaExtra), (N: 'sbauto'; K: kwParaExtra),
    (N: 'saauto'; K: kwParaExtra), (N: 'sbys'; K: kwParaExtra), (N: 'lin'; K: kwParaExtra),
    (N: 'rin'; K: kwParaExtra), (N: 'wrapdefault'; K: kwParaExtra),
    (N: 'nowwrap'; K: kwParaExtra), (N: 'aspalpha'; K: kwParaExtra),
    (N: 'aspnum'; K: kwParaExtra), (N: 'faauto'; K: kwParaExtra), (N: 'fahang'; K: kwParaExtra),
    (N: 'facenter'; K: kwParaExtra), (N: 'faroman'; K: kwParaExtra),
    (N: 'favar'; K: kwParaExtra), (N: 'fafixed'; K: kwParaExtra),
    (N: 'adjustright'; K: kwParaExtra), (N: 'adjustleft'; K: kwParaExtra),
    (N: 'nooverflow'; K: kwParaExtra), (N: 'nocwrap'; K: kwParaExtra),
    (N: 'snaptogrid'; K: kwParaExtra), (N: 'nosnaplinegrid'; K: kwParaExtra),
    (N: 'contextualspace'; K: kwParaExtra), (N: 'indmirror'; K: kwParaExtra),
    (N: 'qd'; K: kwParaExtra), (N: 'qt'; K: kwParaExtra), (N: 'cufi'; K: kwParaExtra),
    (N: 'culi'; K: kwParaExtra), (N: 'curi'; K: kwParaExtra), (N: 'lisa'; K: kwParaExtra),
    (N: 'lisb'; K: kwParaExtra), (N: 'pnlvlcont'; K: kwParaExtra),
    (N: 'shading'; K: kwParaExtra), (N: 'cbpat'; K: kwParaExtra), (N: 'cfpat'; K: kwParaExtra),
    (N: 'box'; K: kwParaExtra), (N: 'tb'; K: kwParaExtra), (N: 'spv'; K: kwParaExtra),
    // lists
    (N: 'pnlvlblt'; K: kwPnLvlBlt), (N: 'pnlvlbody'; K: kwPnLvlBody), (N: 'pnlvl'; K: kwPnLvl),
    (N: 'pndec'; K: kwPnDec), (N: 'pnlcltr'; K: kwPnLcLtr), (N: 'pnucltr'; K: kwPnUcLtr),
    (N: 'pnlcrm'; K: kwPnLcRm), (N: 'pnucrm'; K: kwPnUcRm), (N: 'pnstart'; K: kwPnStart),
    // tables
    (N: 'trowd'; K: kwTrowd), (N: 'cellx'; K: kwCellx), (N: 'clmgf'; K: kwClMerge),
    (N: 'clmrg'; K: kwClMerge), (N: 'clvmgf'; K: kwClMerge), (N: 'clvmrg'; K: kwClMerge),
    (N: 'cell'; K: kwCell), (N: 'row'; K: kwRow), (N: 'nestcell'; K: kwNestCell),
    (N: 'nestrow'; K: kwNestRow),
    // characters
    (N: 'par'; K: kwPar), (N: 'line'; K: kwLine), (N: 'tab'; K: kwTab),
    (N: 'ldblquote'; K: kwLdblquote), (N: 'rdblquote'; K: kwRdblquote),
    (N: 'lquote'; K: kwLquote), (N: 'rquote'; K: kwRquote), (N: 'emdash'; K: kwEmdash),
    (N: 'endash'; K: kwEndash), (N: 'bullet'; K: kwBullet), (N: 'emspace'; K: kwEmspace),
    (N: 'enspace'; K: kwEnspace), (N: 'qmspace'; K: kwQmspace), (N: 'zwj'; K: kwZwj),
    (N: 'zwnj'; K: kwZwnj), (N: 'ltrmark'; K: kwLtrMark), (N: 'rtlmark'; K: kwRtlMark),
    (N: 'zwbo'; K: kwZwbo), (N: 'zwnbo'; K: kwZwnbo),
    // characters the reader does not produce: kept as objects where they are
    (N: 'chatn'; K: kwObjWord), (N: 'chftn'; K: kwObjWord), (N: 'chftnsep'; K: kwObjWord),
    (N: 'chftnsepc'; K: kwObjWord), (N: 'chpgn'; K: kwObjWord), (N: 'chdate'; K: kwObjWord),
    (N: 'chtime'; K: kwObjWord), (N: 'chdpl'; K: kwObjWord), (N: 'chdpa'; K: kwObjWord),
    (N: 'sectnum'; K: kwObjWord), (N: 'page'; K: kwObjWord), (N: 'column'; K: kwObjWord),
    (N: 'sect'; K: kwObjWord),
    // the header's tables
    (N: 'fcharset'; K: kwFcharset), (N: 'cpg'; K: kwCpg), (N: 'red'; K: kwRed),
    (N: 'green'; K: kwGreen), (N: 'blue'; K: kwBlue), (N: 'levelnfc'; K: kwLevelNfc),
    (N: 'levelnfcn'; K: kwLevelNfc), (N: 'levelstartat'; K: kwLevelStartAt),
    (N: 'listid'; K: kwListId),
    // pictures
    (N: 'pngblip'; K: kwPngBlip), (N: 'jpegblip'; K: kwJpegBlip), (N: 'dibitmap'; K: kwDibitmap),
    (N: 'wbitmap'; K: kwWbitmap), (N: 'wmetafile'; K: kwWmetafile), (N: 'emfblip'; K: kwEmfBlip),
    (N: 'picw'; K: kwPicW), (N: 'pich'; K: kwPicH), (N: 'picwgoal'; K: kwPicWGoal),
    (N: 'pichgoal'; K: kwPicHGoal), (N: 'picscalex'; K: kwPicScaleX),
    (N: 'picscaley'; K: kwPicScaleY),
    // destinations the reader reads
    (N: 'fonttbl'; K: kwDFontTbl), (N: 'colortbl'; K: kwDColorTbl),
    (N: 'listtable'; K: kwDListTable), (N: 'list'; K: kwDList), (N: 'listlevel'; K: kwDListLevel),
    (N: 'listoverridetable'; K: kwDOverrideTable), (N: 'listoverride'; K: kwDOverride),
    (N: 'pict'; K: kwDPict), (N: 'shppict'; K: kwDShpPict), (N: 'nonshppict'; K: kwDShpPict),
    (N: 'field'; K: kwDField), (N: 'fldinst'; K: kwDFldInst), (N: 'fldrslt'; K: kwDFldRslt),
    (N: 'pntext'; K: kwDListText), (N: 'listtext'; K: kwDListText), (N: 'pn'; K: kwDPn),
    (N: 'pntxta'; K: kwDPnText), (N: 'pntxtb'; K: kwDPnText), (N: 'upr'; K: kwDUpr),
    (N: 'ud'; K: kwDUd), (N: 'nesttableprops'; K: kwDNestSkip),
    (N: 'nonesttables'; K: kwDNestSkip),
    // document-level destinations
    (N: 'stylesheet'; K: kwDDocSkip), (N: 'info'; K: kwDDocSkip), (N: 'generator'; K: kwDDocSkip),
    (N: 'revtbl'; K: kwDDocSkip), (N: 'rsidtbl'; K: kwDDocSkip), (N: 'defchp'; K: kwDDocSkip),
    (N: 'defpap'; K: kwDDocSkip), (N: 'latentstyles'; K: kwDDocSkip),
    (N: 'themedata'; K: kwDDocSkip), (N: 'colorschememapping'; K: kwDDocSkip),
    (N: 'datastore'; K: kwDDocSkip), (N: 'xmlnstbl'; K: kwDDocSkip),
    (N: 'listpicture'; K: kwDDocSkip), (N: 'pgdsctbl'; K: kwDDocSkip),
    (N: 'mmathPr'; K: kwDDocSkip), (N: 'wgrffmtfilter'; K: kwDDocSkip),
    (N: 'fchars'; K: kwDDocSkip), (N: 'lchars'; K: kwDDocSkip), (N: 'userprops'; K: kwDDocSkip),
    (N: 'docvar'; K: kwDDocSkip), (N: 'template'; K: kwDDocSkip), (N: 'filetbl'; K: kwDDocSkip),
    (N: 'protusertbl'; K: kwDDocSkip), (N: 'ftnsep'; K: kwDDocSkip),
    (N: 'ftnsepc'; K: kwDDocSkip), (N: 'ftncn'; K: kwDDocSkip), (N: 'aftnsep'; K: kwDDocSkip),
    (N: 'aftnsepc'; K: kwDDocSkip), (N: 'aftncn'; K: kwDDocSkip),
    (N: 'pnseclvl'; K: kwDDocSkip), (N: 'private'; K: kwDDocSkip), (N: 'falt'; K: kwDDocSkip),
    (N: 'panose'; K: kwDDocSkip), (N: 'fname'; K: kwDDocSkip), (N: 'listname'; K: kwDDocSkip),
    (N: 'leveltext'; K: kwDDocSkip), (N: 'levelnumbers'; K: kwDDocSkip),
    (N: 'picprop'; K: kwDDocSkip), (N: 'blipuid'; K: kwDDocSkip),
    (N: 'passwordhash'; K: kwDDocSkip), (N: 'background'; K: kwDDocSkip),
    (N: 'header'; K: kwDHeaderFooter), (N: 'headerl'; K: kwDHeaderFooter),
    (N: 'headerr'; K: kwDHeaderFooter), (N: 'headerf'; K: kwDHeaderFooter),
    (N: 'footer'; K: kwDHeaderFooter), (N: 'footerl'; K: kwDHeaderFooter),
    (N: 'footerr'; K: kwDHeaderFooter), (N: 'footerf'; K: kwDHeaderFooter),
    // non-text blocks inside a paragraph: one object each
    (N: 'footnote'; K: kwDOpaque), (N: 'annotation'; K: kwDOpaque),
    (N: 'atrfstart'; K: kwDOpaque), (N: 'atrfend'; K: kwDOpaque), (N: 'atnid'; K: kwDOpaque),
    (N: 'atnauthor'; K: kwDOpaque), (N: 'atnref'; K: kwDOpaque), (N: 'atndate'; K: kwDOpaque),
    (N: 'atnparent'; K: kwDOpaque), (N: 'atntime'; K: kwDOpaque), (N: 'atnicn'; K: kwDOpaque),
    (N: 'mmath'; K: kwDOpaque), (N: 'object'; K: kwDOpaque), (N: 'shp'; K: kwDOpaque),
    (N: 'shpgrp'; K: kwDOpaque), (N: 'bkmkstart'; K: kwDOpaque), (N: 'bkmkend'; K: kwDOpaque),
    (N: 'xe'; K: kwDOpaque), (N: 'tc'; K: kwDOpaque), (N: 'txe'; K: kwDOpaque),
    (N: 'rxe'; K: kwDOpaque), (N: 'do'; K: kwDOpaque),
    // property groups
    (N: 'oldcprops'; K: kwDCharExtra), (N: 'oldpprops'; K: kwDParaExtra)
  );

type
  // WordTable as the lookup reads it: one small block per word, nothing managed
  TWordKey = record
    Len: Integer;
    K: Integer;
    Name: array[0..31] of Byte;
  end;

var
  WordSlots: array[0..4095] of SmallInt;   // index + 1 into WordTable, 0 empty
  WordKeys: array[0..High(WordTable)] of TWordKey;
  LetterTab: array[0..255] of Byte;          // 1: a letter a control word is made of

// A word's slot: from its length and its first two and last two letters, so that it costs
// the same for every word (the letters are compared after it anyway).
{$PUSH}{$Q-}{$R-}
function WordHash(P: PByte; ALen: Integer): Cardinal; inline;
begin
  Result := (Cardinal(ALen) shl 24) xor (Cardinal(P[0]) shl 16) xor
    (Cardinal(P[(ALen - 1) shr 1]) shl 8) xor Cardinal(P[ALen - 1]) xor
    (Cardinal(P[ALen shr 1]) shl 4);
  Result := (Result * 2654435761) shr 20;
end;
{$POP}

procedure InitWords;
var
  i: Integer;
  h: Cardinal;
begin
  FillChar(WordSlots, SizeOf(WordSlots), 0);
  for i := 0 to 255 do
    LetterTab[i] := Ord(((i >= Ord('a')) and (i <= Ord('z'))) or ((i >= Ord('A')) and (i <= Ord('Z'))));
  for i := 0 to High(WordTable) do
  begin
    WordKeys[i].Len := Length(WordTable[i].N);
    WordKeys[i].K := WordTable[i].K;
    FillChar(WordKeys[i].Name, SizeOf(WordKeys[i].Name), 0);
    Move(WordTable[i].N[1], WordKeys[i].Name[0], Length(WordTable[i].N));
    h := WordHash(@WordKeys[i].Name[0], WordKeys[i].Len) and High(WordSlots);
    while WordSlots[h] <> 0 do h := (h + 1) and High(WordSlots);
    WordSlots[h] := i + 1;
  end;
end;

// Every word goes through here: no call per byte, no string touched.
function LookupWord(P: PByte; ALen: Integer): Integer;
var
  h: Cardinal;
  s, i: Integer;
begin
  h := WordHash(P, ALen) and High(WordSlots);
  repeat
    s := WordSlots[h];
    if s = 0 then Exit(kwUnknown);
    with WordKeys[s - 1] do
      if Len = ALen then
      begin
        i := 0;
        while (i < ALen) and (P[i] = Name[i]) do Inc(i);
        if i = ALen then Exit(K);
      end;
    h := (h + 1) and High(WordSlots);
  until False;
end;

function NameStarts(P: PByte; ALen: Integer; const APrefix: string): Boolean; inline;
var
  i: Integer;
begin
  if ALen < Length(APrefix) then Exit(False);
  for i := 1 to Length(APrefix) do
    if P[i - 1] <> Ord(APrefix[i]) then Exit(False);
  Result := True;
end;

// A table row's own words: kept in the row's definition, never on a paragraph or run.
function IsRowWord(P: PByte; ALen: Integer; AInRowDef: Boolean): Boolean;
begin
  // most words a reader does not know start with none of these letters
  case P^ of
    Ord('t'), Ord('c'), Ord('i'), Ord('l'), Ord('r'), Ord('b'):
      ;
  else
    Exit(False);
  end;
  Result := NameStarts(P, ALen, 'tr') or NameStarts(P, ALen, 'cl') or
    NameStarts(P, ALen, 'irow') or NameStarts(P, ALen, 'lastrow') or
    NameStarts(P, ALen, 'ltrrow') or NameStarts(P, ALen, 'rtlrow');
  if not Result and AInRowDef then
    Result := NameStarts(P, ALen, 'brdr') or NameStarts(P, ALen, 'brsp') or
      NameStarts(P, ALen, 'ts') or NameStarts(P, ALen, 'tbl') or NameStarts(P, ALen, 'tp') or
      NameStarts(P, ALen, 'tdfrmtxt') or NameStarts(P, ALen, 'tabsnoovrlp') or
      NameStarts(P, ALen, 'taprtl');
end;

// The roles of Word's theme fonts: a font table entry may begin with one, before its \f.
function IsThemeFontRole(P: PByte; ALen: Integer): Boolean;
begin
  Result := (ALen = 8) and (P[0] = Ord('f')) and
    (NameStarts(P + 3, 5, 'major') or NameStarts(P + 3, 5, 'minor')) and
    (NameStarts(P + 1, 2, 'lo') or NameStarts(P + 1, 2, 'hi') or NameStarts(P + 1, 2, 'db') or
     NameStarts(P + 1, 2, 'bi'));
end;

// Paragraph borders and shading: the paragraph's Extra.
function IsParaPrefixWord(P: PByte; ALen: Integer): Boolean;
begin
  if P^ <> Ord('b') then Exit(False);
  Result := NameStarts(P, ALen, 'brdr') or NameStarts(P, ALen, 'brsp') or
    NameStarts(P, ALen, 'bg');
end;

// ---- small helpers ----

function HexVal(B: Byte): Integer; inline;
begin
  case B of
    Ord('0')..Ord('9'): Result := B - Ord('0');
    Ord('a')..Ord('f'): Result := B - Ord('a') + 10;
    Ord('A')..Ord('F'): Result := B - Ord('A') + 10;
  else
    Result := -1;
  end;
end;

function IsLetter(B: Byte): Boolean; inline;
begin
  Result := ((B >= Ord('a')) and (B <= Ord('z'))) or ((B >= Ord('A')) and (B <= Ord('Z')));
end;

function IsDigit(B: Byte): Boolean; inline;
begin
  Result := (B >= Ord('0')) and (B <= Ord('9'));
end;

// The bytes of a UTF-8 string in a string (the model's font names), with no conversion.
function AsString(const S: UTF8String): string;
begin
  Result := '';
  SetLength(Result, Length(S));
  if S <> '' then Move(S[1], Result[1], Length(S));
end;

function Range(AStart, AStop: Int64): TTyRtfRange; inline;
begin
  Result.Start := AStart;
  Result.Stop := AStop;
end;

procedure UtfPut(var ABuf: TBytes; var ALen: PtrInt; ACode: Cardinal); inline;
begin
  if ALen + 4 > Length(ABuf) then SetLength(ABuf, (Length(ABuf) + 4) * 2);
  if ACode < $80 then
  begin
    ABuf[ALen] := ACode;
    Inc(ALen);
  end
  else if ACode < $800 then
  begin
    ABuf[ALen] := $C0 or (ACode shr 6);
    ABuf[ALen + 1] := $80 or (ACode and $3F);
    Inc(ALen, 2);
  end
  else if ACode < $10000 then
  begin
    ABuf[ALen] := $E0 or (ACode shr 12);
    ABuf[ALen + 1] := $80 or ((ACode shr 6) and $3F);
    ABuf[ALen + 2] := $80 or (ACode and $3F);
    Inc(ALen, 3);
  end
  else
  begin
    ABuf[ALen] := $F0 or (ACode shr 18);
    ABuf[ALen + 1] := $80 or ((ACode shr 12) and $3F);
    ABuf[ALen + 2] := $80 or ((ACode shr 6) and $3F);
    ABuf[ALen + 3] := $80 or (ACode and $3F);
    Inc(ALen, 4);
  end;
end;

// The character \uN names: N as it is, a negative N as N + 65536 (a 16-bit number written
// signed). A number that is no character - a damaged file - reads as U+FFFD: one character
// for the index scan and for the text, never bytes that are no UTF-8.
function UnicodeOfParam(AParam: Integer): Cardinal;
var
  v: Int64;
begin
  v := AParam;
  if v < 0 then Inc(v, 65536);
  if (v < 0) or (v > $10FFFF) then Result := $FFFD else Result := v;
end;

// CJK ideographs, kana, Hangul, Bopomofo, CJK punctuation and the full-width forms: the
// characters Word gives the double-byte font.
function IsEastAsian(ACode: Cardinal): Boolean;
begin
  case ACode of
    $1100..$11FF, $2E80..$A4CF, $A960..$A97F, $AC00..$D7FF, $F900..$FAFF, $FE10..$FE1F,
    $FE30..$FE4F, $FF00..$FFEF, $20000..$3FFFF:
      Result := True;
  else
    Result := False;
  end;
end;

// \fcharset to a code page; 0 for "the document's" (ANSI, default, OEM-less).
function CharsetCodePage(ACharset: Integer): Integer;
begin
  case ACharset of
    0: Result := 1252;
    2: Result := CpSymbol;
    77: Result := 10000;
    128: Result := 932;
    129: Result := 949;
    130: Result := 1361;
    134: Result := 936;
    136: Result := 950;
    161: Result := 1253;
    162: Result := 1254;
    163: Result := 1258;
    177: Result := 1255;
    178: Result := 1256;
    186: Result := 1257;
    204: Result := 1251;
    222: Result := 874;
    238: Result := 1250;
    254: Result := 437;
    255: Result := 850;
  else
    Result := 0;     // 1 default, 3 invalid, none given, or unknown: \ansicpg
  end;
end;

// A code page as \ansicpg or \cpg names it, to the one whose table decodes it. WordPad on a
// Chinese system writes \ansicpg54936 (GB18030): its one- and two-byte sequences are GBK's.
// Its four-byte sequences (a lead byte, then 30-39) are not decoded: WordPad writes such
// characters as \uN, and in a file that has them anyway the lead byte reads as '?' and each
// 30-39 byte as its digit, as in a GBK file.
function RtfCodePage(ACodePage: Integer): Integer;
begin
  if ACodePage = 54936 then Result := 936 else Result := ACodePage;
end;

// ---- TTyRtfSourceMap ----

function TTyRtfSourceMap.ParaCount: Integer;
begin
  Result := Length(Paras);
end;

// ---- TTyRtfLexer ----

procedure TTyRtfLexer.Init(ABuf: PByte; APos, AEnd: PtrInt);
begin
  FBuf := ABuf;
  FPos := APos;
  FEnd := AEnd;
end;

function TTyRtfLexer.Next(out T: TTyRtfToken): Boolean;
var
  p: PtrInt;
  c: Byte;
  v: Int64;
  neg: Boolean;
  digits, h: Integer;
begin
  p := FPos;
  if p >= FEnd then Exit(False);
  T.Start := p;
  T.NameStart := p;
  T.NameLen := 0;
  T.HasParam := False;
  T.Param := 0;
  T.Value := 0;
  T.DataStart := p;
  c := FBuf[p];
  if c = Ord('{') then
  begin
    T.Kind := rtkGroupStart;
    Inc(p);
  end
  else if c = Ord('}') then
  begin
    T.Kind := rtkGroupEnd;
    Inc(p);
  end
  else if c = Ord('\') then
  begin
    Inc(p);
    if p >= FEnd then
    begin
      T.Kind := rtkSymbol;
      T.Value := -1;
    end
    else
    begin
      c := FBuf[p];
      if IsLetter(c) then
      begin
        T.Kind := rtkWord;
        T.NameStart := p;
        while (p < FEnd) and IsLetter(FBuf[p]) do Inc(p);
        T.NameLen := p - T.NameStart;
        neg := False;
        if (p + 1 < FEnd) and (FBuf[p] = Ord('-')) and IsDigit(FBuf[p + 1]) then
        begin
          neg := True;
          Inc(p);
        end;
        if (p < FEnd) and IsDigit(FBuf[p]) then
        begin
          T.HasParam := True;
          v := 0;
          while (p < FEnd) and IsDigit(FBuf[p]) do
          begin
            // saturate: a number too long for anything stays too big
            if v < 100000000000 then v := v * 10 + (FBuf[p] - Ord('0'));
            Inc(p);
          end;
          if neg then v := -v;
          if v > High(Integer) then v := High(Integer)
          else if v < -High(Integer) then v := -High(Integer);
          T.Param := Integer(v);
        end;
        if (p < FEnd) and (FBuf[p] = Ord(' ')) then Inc(p);
        if (T.NameLen = 3) and (FBuf[T.NameStart] = Ord('b')) and
           (FBuf[T.NameStart + 1] = Ord('i')) and (FBuf[T.NameStart + 2] = Ord('n')) then
        begin
          T.Kind := rtkBin;
          T.DataStart := p;
          if T.HasParam and (T.Param > 0) then
            if T.Param >= FEnd - p then p := FEnd else Inc(p, T.Param);
        end;
      end
      else if c = Ord('''') then
      begin
        T.Kind := rtkHex;
        Inc(p);
        v := 0;
        digits := 0;
        while (digits < 2) and (p < FEnd) do
        begin
          h := HexVal(FBuf[p]);
          if h < 0 then Break;
          v := v * 16 + h;
          Inc(p);
          Inc(digits);
        end;
        if digits = 2 then T.Value := v else T.Value := -1;
      end
      else
      begin
        T.Kind := rtkSymbol;
        T.Value := c;
        Inc(p);
      end;
    end;
  end
  else
  begin
    T.Kind := rtkText;
    repeat
      Inc(p);
    until (p >= FEnd) or (FBuf[p] = Ord('\')) or (FBuf[p] = Ord('{')) or (FBuf[p] = Ord('}'));
  end;
  T.Stop := p;
  FPos := p;
  Result := True;
end;

// ---- TTyRtfState ----

function TTyRtfState.MemSize: Int64;
begin
  Result := SizeOf(TTyRtfState) + Int64(Length(Stack)) * SizeOf(TTyRtfProps) +
    Int64(Length(Nodes)) * SizeOf(TTyRtfNode);
end;

// ---- TTyRtfParser: life ----

constructor TTyRtfParser.Create(const ABytes: TBytes; APool: TTyFormatPool);
begin
  inherited Create;
  FBytes := ABytes;
  FLen := Length(ABytes);
  if FLen > 0 then FBuf := @FBytes[0] else FBuf := nil;
  FPool := APool;
  FObjects := TFPList.Create;
  FCompactAt := 4096;
  FVersionGen := -1;
  FFontTblClose := -1;
  FFontTblOpen := -1;
  FColorTblClose := -1;
  FAnsiCp := 1252;
  FDeff := -1;
  FFirstFont := -1;
  FPaperW := 12240;
  FPaperH := 15840;
  FMargL := 1800;
  FMargR := 1800;
  FDecNum := -100;
  FSep := #13#10;
  if TyRichPlatformLineBreak = rsLF then FSep := #10
  else if TyRichPlatformLineBreak = rsCR then FSep := #13;
  InitState;
end;

destructor TTyRtfParser.Destroy;
var
  i: Integer;
begin
  // the objects a document took are its own now; the rest are still ours
  for i := 0 to FObjects.Count - 1 do
    if TTyRichObject(FObjects[i]).RefCount = 0 then TTyRichObject(FObjects[i]).Free;
  FObjects.Free;
  if FVersions <> nil then
    for i := 0 to FVersions.Count - 1 do TTyRtfParser(FVersions[i]).Free;
  FVersions.Free;
  inherited Destroy;
end;

function TTyRtfParser.TakeObjects: TFPList;
var
  i: Integer;
begin
  Result := FObjects;
  for i := 0 to Result.Count - 1 do TTyRichObject(Result[i]).AddRef;
  FObjects := TFPList.Create;
end;

// ---- the node pool ----

function TTyRtfParser.Push(AList: Integer; A, B: Int64): Integer;
begin
  Result := PushKey(AList, A, B, 0);
end;

function TTyRtfParser.PushKey(AList: Integer; A, B: Int64; AKey: Cardinal): Integer;
begin
  if FNodeN = Length(FNodes) then SetLength(FNodes, FNodeN * 2 + 64);
  FNodes[FNodeN].A := A;
  FNodes[FNodeN].B := B;
  FNodes[FNodeN].Prev := AList;
  FNodes[FNodeN].Key := AKey;
  Result := FNodeN;
  Inc(FNodeN);
end;

// Keeps only the nodes the state's lists use (the pool only grows otherwise), renumbering
// them in their order, so a list's earlier nodes still come before it.
procedure TTyRtfParser.Compact;
var
  remap: array of Integer;
  i, k, d: Integer;

  procedure Mark(R: Integer);
  begin
    while (R >= 0) and (remap[R] = -1) do
    begin
      remap[R] := -2;
      R := FNodes[R].Prev;
    end;
  end;

  procedure MarkProps(const P: TTyRtfProps);
  begin
    Mark(P.CharExtra);
    Mark(P.Tabs);
    Mark(P.ParaExtra);
  end;

  function Renum(R: Integer): Integer; inline;
  begin
    if R < 0 then Result := R else Result := remap[R];
  end;

  procedure MapProps(var P: TTyRtfProps);
  begin
    P.CharExtra := Renum(P.CharExtra);
    P.CharHead := Renum(P.CharHead);
    P.CharLast := Renum(P.CharLast);
    P.Tabs := Renum(P.Tabs);
    P.ParaExtra := Renum(P.ParaExtra);
    P.ParaHead := Renum(P.ParaHead);
    P.ParaLast := Renum(P.ParaLast);
  end;

begin
  remap := nil;
  SetLength(remap, FNodeN);
  for i := 0 to FNodeN - 1 do remap[i] := -1;
  d := FS.Depth;
  if d > Length(FStack) then d := Length(FStack);
  MarkProps(FS.Props);
  Mark(FS.RowDef.Cellx);
  for i := 0 to d - 1 do MarkProps(FStack[i]);
  k := 0;
  for i := 0 to FNodeN - 1 do
    if remap[i] = -2 then
    begin
      remap[i] := k;
      FNodes[k] := FNodes[i];
      // the node before is earlier, so it already has its new number
      if FNodes[k].Prev >= 0 then FNodes[k].Prev := remap[FNodes[k].Prev];
      Inc(k);
    end;
  FNodeN := k;
  MapProps(FS.Props);
  FS.RowDef.Cellx := Renum(FS.RowDef.Cellx);
  for i := 0 to d - 1 do MapProps(FStack[i]);
  FCompactAt := FNodeN * 2 + 4096;
end;

procedure TTyRtfParser.TablesChanged;
begin
  Inc(FTablesGen);
end;

procedure TTyRtfParser.SetSnapshotEvery(AValue: Int64);
begin
  FSnapshotEvery := AValue;
  FNextSnapshotAt := FLex.Position + AValue;
end;

function TTyRtfParser.TablesOf(AGen: Integer): TTyRtfParser;
var
  i: Integer;
begin
  Result := nil;
  if FVersions <> nil then
    for i := 0 to FVersions.Count - 1 do
      if TTyRtfParser(FVersions[i]).FTablesGen = AGen then Exit(TTyRtfParser(FVersions[i]));
end;

procedure TTyRtfParser.TakeSnapshot;
var
  v: TTyRtfParser;
begin
  // the tables a parse resuming here must start from (a font table in the middle of the
  // body makes a new generation)
  if FTablesGen <> FVersionGen then
  begin
    if FVersions = nil then FVersions := TFPList.Create;
    v := TTyRtfParser.Create(FBytes, nil);
    v.CopyTablesFrom(Self);
    v.FTablesGen := FTablesGen;
    FVersions.Add(v);
    FVersionGen := FTablesGen;
  end;
  if FSnapshotN = Length(FSnapshots) then SetLength(FSnapshots, FSnapshotN * 2 + 16);
  FSnapshots[FSnapshotN] := SaveState;
  Inc(FSnapshotN);
end;

function TTyRtfParser.Counting: Boolean;
begin
  Result := FPool = nil;
end;

procedure TTyRtfParser.InitState;
begin
  FS := Default(TTyRtfCore);
  FNodeN := 0;
  FS.RowDef.Cellx := -1;
  FS.Props.Dest := rdNormal;
  FS.Props.Uc := 1;
  FS.PendingLead := -1;
  FS.PendingLeadFont := -1;
  FS.OneShot.Start := -1;
  FS.PendingGroup := -1;
  FS.DocCloseAt := -1;
  ResetChar;
  ResetPara;
  FLex.Init(FBuf, 0, FLen);
end;

procedure TTyRtfParser.ResetChar;
begin
  with FS.Props do
  begin
    FontNum := -1;
    LochNum := -1;
    HichNum := -1;
    DbchNum := -1;
    Slot := sloNone;
    Size := DefaultSize;
    Bold := False;
    Italic := False;
    Underline := False;
    Strike := False;
    VertAlign := vaNone;
    ColorIdx := 0;
    HighlightIdx := 0;
    CharExtra := -1;
    CharHead := -1;
    CharLast := -1;
  end;
  CharChanged;
end;

procedure TTyRtfParser.ResetPara;
begin
  with FS.Props do
  begin
    Align := paraLeft;
    LeftIndent := 0;
    RightIndent := 0;
    FirstIndent := 0;
    SpaceBefore := 0;
    SpaceAfter := 0;
    Sl := 0;
    SlMult := 0;
    SlTok := Range(-1, -1);
    SlMultTok := Range(-1, -1);
    Tabs := -1;
    TabAlign := ttaLeft;
    TabLeader := ttlNone;
    RtlPar := False;
    InTable := False;
    Itap := 0;
    ListKind := lkNone;
    ListLevel := 0;
    ListStart := 0;
    Ls := 0;
    Ilvl := 0;
    ParaExtra := -1;
    ParaHead := -1;
    ParaLast := -1;
  end;
  ParaChanged;
end;

procedure TTyRtfParser.CharChanged;
begin
  FCharValid[rccLoch] := False;
  FCharValid[rccHich] := False;
  FCharValid[rccDbch] := False;
end;

procedure TTyRtfParser.ParaChanged;
begin
  FParaValid := False;
end;

function TTyRtfParser.SaveState: TTyRtfState;
var
  d: Integer;
begin
  FS.Pos := FLex.Position;
  // (a snapshot's lists are read as they stand)
  SettleLists;
  Compact;
  Result.Core := FS;
  d := FS.Depth;
  if d > Length(FStack) then d := Length(FStack);
  Result.Stack := Copy(FStack, 0, d);
  Result.Nodes := Copy(FNodes, 0, FNodeN);
  Result.TablesGen := FTablesGen;
end;

procedure TTyRtfParser.Resume(const AState: TTyRtfState);
begin
  FS := AState.Core;
  FStack := Copy(AState.Stack, 0, Length(AState.Stack));
  FNodes := Copy(AState.Nodes, 0, Length(AState.Nodes));
  FNodeN := Length(FNodes);
  FCompactAt := FNodeN * 2 + 4096;
  FLex.Init(FBuf, FS.Pos, FLen);
  FFinished := False;
  FDecNum := -100;
  // ParaRec(0) is the first paragraph after the snapshot
  FParaBase := 0;
  FParaN := 0;
  CharChanged;
  ParaChanged;
end;

procedure TTyRtfParser.CopyTablesFrom(AOther: TTyRtfParser);
begin
  TablesChanged;
  FAnsiCp := AOther.FAnsiCp;
  FAnsiCpSet := AOther.FAnsiCpSet;
  FDeff := AOther.FDeff;
  FFirstFont := AOther.FFirstFont;
  FFonts := Copy(AOther.FFonts, 0, Length(AOther.FFonts));
  FFontCount := AOther.FFontCount;
  FFontsSorted := AOther.FFontsSorted;
  Inc(FFontGen);
  FColors := Copy(AOther.FColors, 0, Length(AOther.FColors));
  FColorAuto := Copy(AOther.FColorAuto, 0, Length(AOther.FColorAuto));
  FColorCount := AOther.FColorCount;
  FLists := Copy(AOther.FLists, 0, Length(AOther.FLists));
  FListCount := AOther.FListCount;
  FOverrideLs := Copy(AOther.FOverrideLs, 0, Length(AOther.FOverrideLs));
  FOverrideId := Copy(AOther.FOverrideId, 0, Length(AOther.FOverrideId));
  FOverrideCount := AOther.FOverrideCount;
  FPaperW := AOther.FPaperW;
  FPaperH := AOther.FPaperH;
  FMargL := AOther.FMargL;
  FMargR := AOther.FMargR;
end;

// ---- the loop ----

procedure TTyRtfParser.Parse;
begin
  ParseUntil(High(PtrInt), -1);
end;

// StartContent once the body has started.
procedure TTyRtfParser.MarkContent;
begin
  FS.HasContent := True;
  FS.CurEnd := FTokStop;
  FS.Absorb := absCurrent;
  FContent := True;
end;

// The index scan's own way through the commonest tokens - text, \'xx, braces - with nothing
// to build: exactly what the token loop below does with them (DoText, DoHex, DoGroupStart,
// DoGroupEnd and the bookkeeping after each), only without a token record, a call per byte
// or a call per token. It stops at the first token it does not take (a control word or
// symbol, a destination's closing brace, any state out of the ordinary), which the token
// loop then reads. False: it is at AStopPos or the end.
function TTyRtfParser.FastRun(AStopPos: PtrInt): Boolean;
var
  p, e, q: PtrInt;
  b: Byte;
  h1, h2, kw, nameLen: Integer;
  any, counted, neg: Boolean;
  buf: PByte;
  v: Int64;
begin
  buf := FBuf;
  p := FLex.Position;
  e := FLen;
  Result := True;
  while p < e do
  begin
    if p >= AStopPos then
    begin
      FLex.Position := p;
      Exit(False);
    end;
    // only plain body text in an ordinary state
    if (FS.Props.Dest <> rdNormal) or (FS.UcSkip <> 0) or (FS.PendingHigh <> 0) or
       not FS.BodyStarted or (FS.Overflow <> 0) or FS.DocClosed then
      Break;
    b := buf[p];
    if (b = Ord('\')) and (p + 1 < e) and IsLetter(buf[p + 1]) then
    begin
      // a control word, read as the lexer reads it
      q := p + 2;
      while (q < e) and (LetterTab[buf[q]] <> 0) do Inc(q);
      nameLen := q - p - 1;
      // \bin carries data
      if (nameLen = 3) and (buf[p + 1] = Ord('b')) and (buf[p + 2] = Ord('i')) and
         (buf[p + 3] = Ord('n')) then
        Break;
      kw := LookupWord(@buf[p + 1], nameLen);
      // only words that set properties: the rest (paragraph ends, destinations, tables, a
      // group's first word that may begin a destination) are the token loop's
      case kw of
        kwUnknown, kwParaExtra, kwUc, kwU, kwPlain..kwLtrCh, kwPard..kwRtlPar, kwIntbl..kwIlvl,
        kwTrowd, kwCellx, kwClMerge: ;
      else
        Break;
      end;
      if FS.GroupOpen and FS.Star then Break;
      FTok.Kind := rtkWord;
      FTok.Start := p;
      FTok.NameStart := p + 1;
      FTok.NameLen := nameLen;
      FTok.HasParam := False;
      FTok.Param := 0;
      neg := False;
      if (q + 1 < e) and (buf[q] = Ord('-')) and IsDigit(buf[q + 1]) then
      begin
        neg := True;
        Inc(q);
      end;
      if (q < e) and IsDigit(buf[q]) then
      begin
        FTok.HasParam := True;
        v := 0;
        while (q < e) and IsDigit(buf[q]) do
        begin
          if v < 100000000000 then v := v * 10 + (buf[q] - Ord('0'));
          Inc(q);
        end;
        if neg then v := -v;
        if v > High(Integer) then v := High(Integer)
        else if v < -High(Integer) then v := -High(Integer);
        FTok.Param := Integer(v);
      end;
      if (q < e) and (buf[q] = Ord(' ')) then Inc(q);
      FTok.Stop := q;
      FTokStop := q;
      p := q;
      FContent := False;
      // DoWord: (not a destination) then BodyWord
      FS.GroupOpen := False;
      FS.UcSkip := 0;
      if FS.InRowDef and (kw <> kwTrowd) and (kw <> kwCellx) and (kw <> kwClMerge) and
         not IsRowWord(@buf[FTok.NameStart], nameLen, True) then
        EndRowDef;
      if kw = kwUnknown then
      begin
        if IsRowWord(@buf[FTok.NameStart], nameLen, FS.InRowDef) then
        begin
          if FS.InRowDef then FS.RowDef.Raw.Stop := FTok.Stop;
        end
        else if IsParaPrefixWord(@buf[FTok.NameStart], nameLen) then
          AddParaExtra(FTok.Start, FTok.Stop)
        else
          AddCharExtra(FTok.Start, FTok.Stop);
      end
      else if kw = kwParaExtra then
        AddParaExtra(FTok.Start, FTok.Stop)
      else
        BodyWord(kw);
      if not FContent then FS.Absorb := absNone;
      if FNodeN > FCompactAt then Compact;
    end
    else if b = Ord('\') then
    begin
      // \'xx with both digits
      if (p + 3 >= e) or (buf[p + 1] <> Ord('''')) then Break;
      h1 := HexVal(buf[p + 2]);
      h2 := HexVal(buf[p + 3]);
      if (h1 < 0) or (h2 < 0) then Break;
      b := (h1 shl 4) or h2;
      FS.GroupOpen := False;
      FS.InRowDef := False;
      FTok.Start := p;
      Inc(p, 4);
      FTokStop := p;
      FTok.Stop := p;
      FContent := False;
      if (b = 0) or (b = 10) or (b = 13) then
      begin
        FS.Absorb := absNone;
        Continue;
      end;
      if (FS.PendingLead < 0) and (b < $80) then
      begin
        if (b >= $20) or (b = 9) then
        begin
          MarkContent;
          FS.OneShot.Start := -1;
          Inc(FCurChars);
        end;
      end
      else
      begin
        if (FDecNum <> FS.Props.FontNum) or (FDecGen <> FFontGen) then UpdateDecoder;
        if FS.PendingLead >= 0 then
        begin
          // the trail byte of a pair the table knows: one character
          h1 := (FS.PendingLead shl 8) or b;
          if (FS.PendingLeadFont = FS.Props.FontNum) and (FDecPairs <> nil) and
             (FDecPairs[h1 shr 3] and (1 shl (h1 and 7)) <> 0) then
          begin
            FS.PendingLead := -1;
            MarkContent;
            FS.OneShot.Start := -1;
            Inc(FCurChars);
          end
          else
            ProcessByte(b);
        end
        else if (FDecCls <> nil) and (FDecCls[b] = 2) then
        begin
          FS.PendingLead := b;
          FS.PendingLeadFont := FS.Props.FontNum;
          MarkContent;
        end
        else if (FDecCls <> nil) and (FDecCls[b] = 1) then
        begin
          MarkContent;
          FS.OneShot.Start := -1;
          Inc(FCurChars);
        end
        else
          ProcessByte(b);
      end;
      if not FContent then FS.Absorb := absNone;
    end
    else if b = Ord('{') then
    begin
      FTok.Start := p;
      Inc(p);
      FTok.Stop := p;
      FTokStop := p;
      DoGroupStart;
      FS.Absorb := absNone;
    end
    else if b = Ord('}') then
    begin
      // a group that began a destination ends it: the token loop's
      if FS.Props.DestOwner or (FS.Depth <= 1) then Break;
      FTok.Start := p;
      Inc(p);
      FTok.Stop := p;
      FTokStop := p;
      FContent := False;
      PopGroup;
      Extend(True);
    end
    else
    begin
      // a run of text: ASCII counted here, the rest by ProcessByte
      FS.GroupOpen := False;
      FTok.Start := p;
      q := p;
      repeat
        Inc(q);
      until (q >= e) or (buf[q] = Ord('\')) or (buf[q] = Ord('{')) or (buf[q] = Ord('}'));
      FTok.Stop := q;
      FTokStop := q;
      FContent := False;
      any := False;
      counted := False;
      while p < q do
      begin
        b := buf[p];
        Inc(p);
        if (b = 13) or (b = 10) or (b = 0) then Continue;
        if not any then
        begin
          any := True;
          FS.InRowDef := False;
        end;
        if (b < $80) and (FS.PendingLead < 0) and (FS.UcSkip = 0) then
        begin
          if (b >= $20) or (b = 9) then
          begin
            Inc(FCurChars);
            counted := True;
          end;
        end
        else
          ProcessByte(b);
      end;
      if counted then
      begin
        MarkContent;
        FS.OneShot.Start := -1;
      end;
      if not any then Extend(False)
      else if not FContent then FS.Absorb := absNone;
    end;
  end;
  FLex.Position := p;
  if p >= e then Result := p < e;
end;

function TTyRtfParser.ParseUntil(AStopPos: PtrInt; AStopParas: Integer): Boolean;
var
  absorbable: Boolean;
  paras: Integer;
begin
  while not FS.DocClosed do
  begin
    if Counting and not FastRun(AStopPos) then
    begin
      if FLex.Position >= FLen then Break;
      Exit(False);
    end;
    if not FLex.Next(FTok) then Break;
    FTokStop := FTok.Stop;
    FContent := False;
    FCommitted := False;
    absorbable := False;
    paras := FS.Paras;
    case FTok.Kind of
      rtkGroupStart: DoGroupStart;
      rtkGroupEnd: absorbable := DoGroupEnd;
      rtkText: absorbable := DoText;
      rtkWord: DoWord;
      rtkSymbol: DoSymbol;
      rtkHex: DoHex;
      rtkBin: DoBin;
    end;
    if not (FContent or FCommitted) then
      if absorbable then Extend(FTok.Kind = rtkGroupEnd)
      else FS.Absorb := absNone;
    if FS.Paras <> paras then
    begin
      // after the token that ended a paragraph, all of it done (a row's end included)
      if FKeepSnapshots then
        TakeSnapshot
      else if (FSnapshotEvery > 0) and (FTokStop >= FNextSnapshotAt) and (FS.CellIdx = 0) and
        (FS.RowMax = 0) then
      begin
        // not inside a table row: a parse resuming here starts at a row
        TakeSnapshot;
        FNextSnapshotAt := FTokStop + FSnapshotEvery;
      end;
    end
    else if (FS.CellIdx = 0) and (FS.RowMax = 0) and (FSnapshotEvery > 0) and
      (FTokStop >= FNextSnapshotAt) and (FTok.Kind = rtkWord) and FS.TableOpen and
      (FS.Absorb = absLast) and not FS.HasContent then
    begin
      // a row just ended (its \row belongs to the last cell): also a place to resume from
      TakeSnapshot;
      FNextSnapshotAt := FTokStop + FSnapshotEvery;
    end;
    if FNodeN > FCompactAt then Compact;
    if (AStopParas >= 0) and (FS.Paras >= AStopParas) and (FS.CellIdx = 0) and
       (FS.RowMax = 0) then
      Exit(False);
    if FLex.Position >= AStopPos then Exit(False);
  end;
  Finish;
  Result := True;
end;

// A closing brace or a run of line breaks after a paragraph's end (or after its last
// character) still belongs to that paragraph; a brace only while it closes a group opened
// inside the paragraph's own bytes.
procedure TTyRtfParser.Extend(AWasBrace: Boolean);
begin
  case FS.Absorb of
    absLast:
      if not AWasBrace or (FS.Depth >= FS.LastStartDepth) then
      begin
        FS.Boundary := FTokStop;
        FS.BoundaryDepth := FS.Depth;
        if FParaN > 0 then FParas[FParaN - 1].Src.Stop := FTokStop;
      end
      else
        FS.Absorb := absNone;
    absCurrent:
      if not AWasBrace or (FS.Depth >= FS.BoundaryDepth) then FS.CurEnd := FTokStop
      else FS.Absorb := absNone;
  end;
end;

procedure TTyRtfParser.DoGroupStart;
begin
  FS.UcSkip := 0;
  FS.GroupOpen := False;
  if (FS.Overflow > 0) or (FS.Depth >= MaxDepth) then
  begin
    Inc(FS.Overflow);
    Exit;
  end;
  if not FS.BodyStarted and (FS.Depth >= 1) and (FS.PendingGroup < 0) then
  begin
    FS.PendingGroup := FTok.Start;
    FS.PendingGroupDepth := FS.Depth;
  end;
  if Length(FStack) <= FS.Depth then SetLength(FStack, FS.Depth * 2 + 8);
  // (saved properties are read as they stand: the words that restore them go by the lists)
  SettleLists;
  FStack[FS.Depth] := FS.Props;
  Inc(FS.Depth);
  FS.Props.DestOwner := False;
  FS.GroupOpen := True;
  FS.Star := False;
  FS.GroupStart := FTok.Start;
end;

procedure TTyRtfParser.PopGroup;
var
  old: TTyRtfProps;
  owner: Boolean;
begin
  FS.UcSkip := 0;
  FS.GroupOpen := False;
  if FS.Overflow > 0 then
  begin
    Dec(FS.Overflow);
    Exit;
  end;
  if FS.Depth <= 0 then Exit;
  owner := FS.Props.DestOwner;
  if owner then old := FS.Props;
  FS.Props := FStack[FS.Depth - 1];
  Dec(FS.Depth);
  CharChanged;
  ParaChanged;
  if not FS.BodyStarted and (FS.PendingGroup >= 0) and (FS.Depth <= FS.PendingGroupDepth) then
    FS.PendingGroup := -1;
  if FS.Depth = 0 then
  begin
    FS.DocClosed := True;
    FS.DocCloseAt := FTok.Start;
  end;
  if owner then EndDest(old);
end;

function TTyRtfParser.DoGroupEnd: Boolean;
begin
  PopGroup;
  Result := not FContent;
end;

// Consumes the rest of a group whose brace is behind; returns where it ends.
function TTyRtfParser.SkipGroup: PtrInt;
var
  d: Integer;
  t: TTyRtfToken;
begin
  d := 1;
  while FLex.Next(t) do
    case t.Kind of
      rtkGroupStart: Inc(d);
      rtkGroupEnd:
        begin
          Dec(d);
          if d = 0 then Exit(t.Stop);
        end;
    end;
  Result := FLen;
end;

procedure TTyRtfParser.SkipAndPop;
begin
  FTokStop := SkipGroup;
  FTok.Start := FTokStop - 1;
  PopGroup;
end;

function TTyRtfParser.DoText: Boolean;
var
  p, e: PtrInt;
  b: Byte;
  any: Boolean;
begin
  FS.GroupOpen := False;
  p := FTok.Start;
  e := FTok.Stop;
  any := False;
  case FS.Props.Dest of
    rdNormal, rdFieldResult:
      while p < e do
      begin
        b := FBuf[p];
        Inc(p);
        if (b = 13) or (b = 10) or (b = 0) then Continue;
        if not any then
        begin
          any := True;
          if FS.InRowDef then EndRowDef;
        end;
        ProcessByte(b);
      end;
    rdFontTable, rdFontEntry:
      while p < e do
      begin
        b := FBuf[p];
        Inc(p);
        any := True;
        if (b = 13) or (b = 10) or (b = 0) then Continue;
        if FS.UcSkip > 0 then Dec(FS.UcSkip)
        else if b = Ord(';') then FinishFontEntry
        else if FEntryOn then FEntryRaw := FEntryRaw + AnsiChar(b);
      end;
    rdColorTable:
      while p < e do
      begin
        if FBuf[p] = Ord(';') then AddColor;
        Inc(p);
        any := True;
      end;
    rdPict:
      begin
        any := True;
        if not Counting then
          while p < e do
          begin
            PutPicByte(FBuf[p]);
            Inc(p);
          end;
      end;
  else
    any := True;
  end;
  Result := not any;
end;

procedure TTyRtfParser.DoHex;
begin
  FS.GroupOpen := False;
  if FS.InRowDef then EndRowDef;
  if FTok.Value < 0 then
  begin
    // \' without its two digits: dropped
    if FS.UcSkip > 0 then Dec(FS.UcSkip);
    Exit;
  end;
  case FS.Props.Dest of
    rdNormal, rdFieldResult: ProcessByte(FTok.Value);
    rdFontTable, rdFontEntry:
      if FS.UcSkip > 0 then Dec(FS.UcSkip)
      else if FEntryOn then FEntryRaw := FEntryRaw + AnsiChar(FTok.Value);
  end;
end;

procedure TTyRtfParser.DoBin;
var
  p: PtrInt;
begin
  FS.GroupOpen := False;
  if FS.Props.Dest = rdPict then
  begin
    if not Counting then
    begin
      FPicNibble := -1;
      if FPicLen + (FTok.Stop - FTok.DataStart) > Length(FPicData) then
        SetLength(FPicData, FPicLen + (FTok.Stop - FTok.DataStart));
      p := FTok.DataStart;
      while p < FTok.Stop do
      begin
        FPicData[FPicLen] := FBuf[p];
        Inc(FPicLen);
        Inc(p);
      end;
    end;
  end
  else if FS.UcSkip > 0 then
    Dec(FS.UcSkip);
end;

procedure TTyRtfParser.DoSymbol;
var
  v: Integer;
begin
  v := FTok.Value;
  if FS.GroupOpen and (v = Ord('*')) then
  begin
    FS.Star := True;
    Exit;
  end;
  FS.GroupOpen := False;
  if v = Ord('*') then Exit;
  if FS.UcSkip > 0 then
  begin
    Dec(FS.UcSkip);
    Exit;
  end;
  if not (FS.Props.Dest in [rdNormal, rdFieldResult]) then Exit;
  if FS.InRowDef then EndRowDef;
  case v of
    Ord('~'): EmitChar($A0);
    Ord('_'): EmitChar($2011);
    Ord('\'), Ord('{'), Ord('}'): EmitChar(v);
    Ord('-'):
      if FS.Props.Dest = rdNormal then
      begin
        // the optional hyphen rides on the character after it
        EnsureBody;
        FS.OneShot := Range(FTok.Start, FTok.Stop);
      end;
    10, 13:
      if FS.Props.Dest = rdNormal then EndParagraph(rpkPar);
  else
    if (FS.Props.Dest = rdNormal) and (v >= 0) then
    begin
      EnsureBody;
      AddCharExtra(FTok.Start, FTok.Stop);
    end;
  end;
end;

// ---- destinations ----

procedure TTyRtfParser.DoWord;
var
  kw: Integer;
begin
  kw := LookupWord(@FBuf[FTok.NameStart], FTok.NameLen);
  if FS.GroupOpen then
  begin
    FS.GroupOpen := False;
    if HandleDestination(kw) then Exit;
  end;
  FS.UcSkip := 0;
  if FS.InRowDef and (kw <> kwTrowd) and (kw <> kwCellx) and (kw <> kwClMerge) and
     not IsRowWord(@FBuf[FTok.NameStart], FTok.NameLen, True) then
    EndRowDef;
  case FS.Props.Dest of
    rdNormal, rdFieldResult, rdPn: BodyWord(kw);
    rdFontTable, rdFontEntry: FontWord(kw);
    rdColorTable:
      begin
        case kw of
          kwRed: FColorR := FTok.Param;
          kwGreen: FColorG := FTok.Param;
          kwBlue: FColorB := FTok.Param;
        end;
        if kw in [kwRed, kwGreen, kwBlue] then FColorAny := True;
      end;
    rdList, rdListLevel, rdOverride: ListWord(kw);
    rdPict: PictWord(kw);
    rdUpr:
      if kw in [kwAnsiCpg, kwUc] then BodyWord(kw);
  end;
end;

procedure TTyRtfParser.BeginDest(ADest: TTyRtfDest);
begin
  FS.Props.Dest := ADest;
  FS.Props.DestOwner := True;
  FS.Props.DestStart := FS.GroupStart;
end;

// The first word of a group: True when it made the group a destination of its own (read in
// its own way, or skipped as a whole).
function TTyRtfParser.HandleDestination(AKw: Integer): Boolean;
var
  content: Boolean;
  start: PtrInt;
begin
  Result := True;
  start := FS.GroupStart;
  case FS.Props.Dest of
    rdFontTable:
      if AKw = kwF then
      begin
        BeginDest(rdFontEntry);
        BeginFontEntry(FTok.Param);
        Exit;
      end
      else if IsThemeFontRole(@FBuf[FTok.NameStart], FTok.NameLen) then
      begin
        // {\fhiminor\f31506 ...}: Word's theme fonts, which its body text is in. The entry
        // begins at the \f that follows the role (FontWord); the role itself is the header's
        // bytes, which go back out as they are
        if FEntryOn then FinishFontEntry;
        BeginDest(rdFontEntry);
        Exit;
      end
      else
      begin
        SkipAndPop;
        Exit;
      end;
    rdFontEntry, rdColorTable, rdPict, rdListLevel, rdOverride:
      begin
        SkipAndPop;
        Exit;
      end;
    rdPn:
      begin
        SkipAndPop;
        // the bullet's or number's text and the like: what the list format cannot say
        if AKw = kwDPnText then AddParaExtra(start, FTokStop);
        Exit;
      end;
    rdListTable:
      begin
        if AKw = kwDList then
        begin
          BeginDest(rdList);
          FCurList := Default(TTyRtfList);
        end
        else
          SkipAndPop;
        Exit;
      end;
    rdList:
      begin
        if AKw = kwDListLevel then
        begin
          BeginDest(rdListLevel);
          FCurLevel.Nfc := 0;
          FCurLevel.Start := 1;
        end
        else
          SkipAndPop;
        Exit;
      end;
    rdOverrideTable:
      begin
        if AKw = kwDOverride then
        begin
          BeginDest(rdOverride);
          FCurOvLs := 0;
          FCurOvId := 0;
        end
        else
          SkipAndPop;
        Exit;
      end;
    rdUpr:
      begin
        if AKw = kwDUd then
        begin
          // the Unicode half is the text; inside a field's result it is the result's
          if FFieldNest > 0 then FS.Props.Dest := rdFieldResult else FS.Props.Dest := rdNormal;
        end
        else
          SkipAndPop;
        Exit;
      end;
    rdField:
      begin
        if AKw = kwDFldRslt then FS.Props.Dest := rdFieldResult
        else SkipAndPop;
        Exit;
      end;
    rdShpPict:
      begin
        if AKw = kwDPict then
        begin
          BeginDest(rdPict);
          BeginPicture;
        end
        else
          SkipAndPop;
        Exit;
      end;
  end;
  // rdNormal and rdFieldResult
  content := (FS.Props.Dest = rdNormal) and (FFieldNest = 0);
  case AKw of
    kwDFontTbl:
      begin
        BeginDest(rdFontTable);
        FEntryOn := False;
      end;
    kwDColorTbl:
      begin
        BeginDest(rdColorTable);
        FColorCount := 0;
        FColorR := 0;
        FColorG := 0;
        FColorB := 0;
        FColorAny := False;
      end;
    kwDListTable: BeginDest(rdListTable);
    kwDOverrideTable: BeginDest(rdOverrideTable);
    kwDDocSkip, kwDFldInst, kwDFldRslt, kwDPnText, kwDUd: SkipAndPop;
    kwDNestSkip:
      begin
        MarkNested;
        SkipAndPop;
      end;
    kwDListText:
      begin
        if content then EnsureBody;
        SkipAndPop;
      end;
    kwDHeaderFooter, kwDOpaque:
      if content and ((AKw = kwDOpaque) or FS.BodyStarted) then
      begin
        EnsureBody;
        SkipAndPop;
        EmitOpaque(start, FTokStop, '');
      end
      else
        SkipAndPop;
    kwDCharExtra, kwDParaExtra:
      begin
        if content then EnsureBody;
        SkipAndPop;
        if content then
          if AKw = kwDCharExtra then AddCharExtra(start, FTokStop)
          else AddParaExtra(start, FTokStop);
      end;
    kwDField:
      begin
        if content then EnsureBody;
        BeginDest(rdField);
        if FFieldNest = 0 then FFieldLen := 0;
        Inc(FFieldNest);
      end;
    kwDPict, kwDShpPict:
      if content then
      begin
        EnsureBody;
        if AKw = kwDPict then
        begin
          BeginDest(rdPict);
          BeginPicture;
        end
        else
          BeginDest(rdShpPict);
      end
      else
        SkipAndPop;
    kwDPn:
      if FS.Props.Dest = rdNormal then
      begin
        if content then EnsureBody;
        BeginDest(rdPn);
      end
      else
        SkipAndPop;
    kwDUpr: BeginDest(rdUpr);
  else
    if FS.Star then
    begin
      // a destination this reader does not know: in a paragraph, an object of its bytes
      if content and FS.BodyStarted then
      begin
        SkipAndPop;
        EmitOpaque(start, FTokStop, '');
      end
      else
        SkipAndPop;
    end
    else
      Result := False;
  end;
end;

function TextIsBreaks(const T: TTyRtfToken; ABuf: PByte): Boolean;
var
  p: PtrInt;
begin
  for p := T.Start to T.Stop - 1 do
    if not (ABuf[p] in [0, 10, 13]) then Exit(False);
  Result := True;
end;

procedure TTyRtfParser.EndDest(const AOld: TTyRtfProps);
var
  pic: TTyRichPicture;
  peek: TTyRtfLexer;
  t1, t2: TTyRtfToken;
  stop: PtrInt;
  got: Boolean;

  function TokenIs(const T: TTyRtfToken; const AName: string): Boolean;
  begin
    Result := (T.NameLen = Length(AName)) and CompareMem(@FBuf[T.NameStart], PChar(AName),
      T.NameLen);
  end;

begin
  case AOld.Dest of
    rdFontEntry: FinishFontEntry;
    rdFontTable:
      begin
        FinishFontEntry;
        SortFonts;
        // (a writer adds the fonts a changed paragraph needs before this brace)
        if not FS.BodyStarted and (FFontTblClose < 0) then
        begin
          FFontTblClose := FTok.Start;
          FFontTblOpen := AOld.DestStart;
        end;
      end;
    rdColorTable:
      begin
        if FColorAny then AddColor;
        if not FS.BodyStarted and (FColorTblClose < 0) then FColorTblClose := FTok.Start;
      end;
    rdListLevel:
      begin
        SetLength(FCurList.Levels, Length(FCurList.Levels) + 1);
        FCurList.Levels[High(FCurList.Levels)] := FCurLevel;
      end;
    rdList:
      begin
        if FListCount = Length(FLists) then SetLength(FLists, FListCount * 2 + 4);
        FLists[FListCount] := FCurList;
        Inc(FListCount);
        TablesChanged;
      end;
    rdOverride:
      begin
        if FOverrideCount = Length(FOverrideLs) then
        begin
          SetLength(FOverrideLs, FOverrideCount * 2 + 4);
          SetLength(FOverrideId, FOverrideCount * 2 + 4);
        end;
        FOverrideLs[FOverrideCount] := FCurOvLs;
        FOverrideId[FOverrideCount] := FCurOvId;
        Inc(FOverrideCount);
        TablesChanged;
      end;
    rdPn:
      begin
        // the list properties belong to the paragraph, not to the {\*\pn} group
        FS.Props.ListKind := AOld.ListKind;
        FS.Props.ListLevel := AOld.ListLevel;
        FS.Props.ListStart := AOld.ListStart;
        FS.Props.ParaExtra := AOld.ParaExtra;
        FS.Props.ParaHead := AOld.ParaHead;
        FS.Props.ParaLast := AOld.ParaLast;
        ParaChanged;
      end;
    rdPict:
      begin
        // (FObjects owns what TakePicture makes until a document takes it)
        pic := TakePicture(AOld.DestStart, FTokStop);
        if FS.Props.Dest = rdShpPict then FHeld := pic
        else EmitObject(pic);
      end;
    rdShpPict:
      begin
        stop := FTokStop;
        // Word's pair: {\*\shppict{\pict ...}}{\nonshppict{\pict ...}} is one picture, the
        // first; the second is for readers that do not know \shppict
        peek := FLex;
        got := peek.Next(t1);
        while got and (t1.Kind = rtkText) and TextIsBreaks(t1, FBuf) do got := peek.Next(t1);
        if got and (t1.Kind = rtkGroupStart) and peek.Next(t2) and (t2.Kind = rtkWord) and
           TokenIs(t2, 'nonshppict') then
        begin
          FLex := peek;
          stop := SkipGroup;
          FTokStop := stop;
        end;
        if FHeld <> nil then
        begin
          pic := TTyRichPicture.Create(FHeld.PictureFormat, FHeld.Data, FHeld.WidthTwips,
            FHeld.HeightTwips, Fragment(Range(AOld.DestStart, stop)), FS.Props.Uc);
          FObjects.Add(pic);
          FHeld := nil;
          EmitObject(pic);
        end
        else
          EmitOpaque(AOld.DestStart, stop, '');
      end;
    rdField:
      begin
        Dec(FFieldNest);
        if (FFieldNest = 0) and (FS.Props.Dest = rdNormal) then
          EmitOpaque(AOld.DestStart, FTokStop, Copy(FFieldText, 1, FFieldLen));
      end;
  end;
end;

// ---- the header's tables ----

procedure TTyRtfParser.BeginFontEntry(ANum: Integer);
begin
  if FEntryOn then FinishFontEntry;
  FEntryOn := True;
  FEntry := Default(TTyRtfFont);
  FEntry.Num := ANum;
  FEntry.Charset := -1;
  FEntryRaw := '';
end;

procedure TTyRtfParser.FinishFontEntry;
var
  n: Integer;
begin
  if not FEntryOn then Exit;
  FEntryOn := False;
  FEntry.CodePage := ResolveCodePage(FEntry.Charset, FEntry.Cpg);
  FEntry.Name := FEntry.Name + DecodeRaw(FEntryRaw, FEntry.CodePage);
  FEntryRaw := '';
  if FEntry.CodePage <> CpSymbol then FEntry.Table := TyRichCodePageTable(FEntry.CodePage);
  if FFirstFont < 0 then FFirstFont := FEntry.Num;
  // a number given twice: the later entry wins
  n := FontIndex(FEntry.Num);
  if n < 0 then
  begin
    if FFontCount = Length(FFonts) then SetLength(FFonts, FFontCount * 2 + 8);
    n := FFontCount;
    Inc(FFontCount);
    FFontsSorted := False;
  end;
  FFonts[n] := FEntry;
  Inc(FFontGen);
  TablesChanged;
  CharChanged;
end;

procedure TTyRtfParser.SortFonts;
var
  i, j: Integer;
  f: TTyRtfFont;
begin
  for i := 1 to FFontCount - 1 do
  begin
    f := FFonts[i];
    j := i - 1;
    while (j >= 0) and (FFonts[j].Num > f.Num) do
    begin
      FFonts[j + 1] := FFonts[j];
      Dec(j);
    end;
    FFonts[j + 1] := f;
  end;
  FFontsSorted := True;
  Inc(FFontGen);
  TablesChanged;
  CharChanged;
end;

function TTyRtfParser.FontIndex(ANum: Integer): Integer;
var
  lo, hi, mid: Integer;
begin
  if FFontsSorted then
  begin
    lo := 0;
    hi := FFontCount - 1;
    while lo <= hi do
    begin
      mid := (lo + hi) div 2;
      if FFonts[mid].Num = ANum then Exit(mid);
      if FFonts[mid].Num < ANum then lo := mid + 1 else hi := mid - 1;
    end;
    Exit(-1);
  end;
  for lo := 0 to FFontCount - 1 do
    if FFonts[lo].Num = ANum then Exit(lo);
  Result := -1;
end;

// The font table entry a \f number means; -1 (no \f yet) is \deff, and with no \deff the
// table's first font.
function TTyRtfParser.FontOfNum(ANum: Integer): Integer;
begin
  if ANum < 0 then ANum := FDeff;
  if ANum < 0 then ANum := FFirstFont;
  if ANum < 0 then Exit(-1);
  Result := FontIndex(ANum);
end;

function TTyRtfParser.ResolveCodePage(ACharset, ACpg: Integer): Integer;
begin
  ACpg := RtfCodePage(ACpg);
  if (ACpg > 0) and TyRichCodePageSupported(ACpg) then Exit(ACpg);
  Result := CharsetCodePage(ACharset);
  if Result = CpSymbol then Exit;
  if (Result = 0) or not TyRichCodePageSupported(Result) then Result := FAnsiCp;
end;

// A font name's bytes in its own code page.
function TTyRtfParser.DecodeRaw(const ARaw: RawByteString; ACodePage: Integer): UTF8String;
var
  t: Pointer;
  buf: TBytes;
  len: PtrInt;
  i: Integer;
  b: Byte;
  code: Cardinal;
begin
  Result := '';
  if ARaw = '' then Exit;
  t := nil;
  if ACodePage <> CpSymbol then t := TyRichCodePageTable(ACodePage);
  buf := nil;
  len := 0;
  i := 1;
  while i <= Length(ARaw) do
  begin
    b := Byte(ARaw[i]);
    Inc(i);
    if b < $80 then code := b
    else if ACodePage = CpSymbol then code := $F000 + b
    else if t = nil then code := Ord('?')
    else if TyRichCodePageIsLead(t, b) and (i <= Length(ARaw)) then
    begin
      code := TyRichCodePageChar(t, b, Byte(ARaw[i]));
      if code <> 0 then Inc(i) else code := Ord('?');
    end
    else
    begin
      code := TyRichCodePageChar(t, b, -1);
      if code = 0 then code := Ord('?');
    end;
    UtfPut(buf, len, code);
  end;
  SetLength(Result, len);
  if len > 0 then Move(buf[0], Result[1], len);
end;

procedure TTyRtfParser.FontWord(AKw: Integer);
var
  code: Cardinal;
  buf: TBytes;
  len: PtrInt;
  utf: UTF8String;
begin
  case AKw of
    kwF: BeginFontEntry(FTok.Param);
    kwFcharset: if FEntryOn then FEntry.Charset := FTok.Param;
    kwCpg: if FEntryOn then FEntry.Cpg := FTok.Param;
    kwU:
      if FEntryOn then
      begin
        // a \u in a name: what came before it is decoded now, in the entry's code page
        FEntry.Name := FEntry.Name + DecodeRaw(FEntryRaw,
          ResolveCodePage(FEntry.Charset, FEntry.Cpg));
        FEntryRaw := '';
        // (a name has no place for a surrogate pair: a half reads as U+FFFD)
        code := UnicodeOfParam(FTok.Param);
        if (code >= $D800) and (code <= $DFFF) then code := $FFFD;
        buf := nil;
        len := 0;
        UtfPut(buf, len, code);
        SetLength(utf, len);
        Move(buf[0], utf[1], len);
        FEntry.Name := FEntry.Name + utf;
        FS.UcSkip := FS.Props.Uc;
      end;
  end;
end;

procedure TTyRtfParser.AddColor;
begin
  if FColorCount = Length(FColors) then
  begin
    SetLength(FColors, FColorCount * 2 + 16);
    SetLength(FColorAuto, FColorCount * 2 + 16);
  end;
  FColorAuto[FColorCount] := not FColorAny;
  FColors[FColorCount] := RGBToColor(Byte(FColorR), Byte(FColorG), Byte(FColorB));
  Inc(FColorCount);
  FColorR := 0;
  FColorG := 0;
  FColorB := 0;
  FColorAny := False;
  TablesChanged;
  CharChanged;
end;

function TTyRtfParser.ColorOf(AIndex: Integer; ADefault: TColor): TColor;
begin
  if (AIndex <= 0) or (AIndex >= FColorCount) or FColorAuto[AIndex] then Result := ADefault
  else Result := FColors[AIndex];
end;

function TTyRtfParser.FontCount: Integer;
begin
  Result := FFontCount;
end;

function TTyRtfParser.Font(AIndex: Integer): TTyRtfFont;
begin
  Result := FFonts[AIndex];
end;

function TTyRtfParser.FontTableHighest: Integer;
var
  lex: TTyRtfLexer;
  t: TTyRtfToken;
begin
  Result := -1;
  if (FFontTblOpen < 0) or (FFontTblClose <= FFontTblOpen) then Exit;
  // every token between the braces, whatever group it is in: \f is the only word whose
  // name is "f" (\fcharset, \fprq, \fs are other words; \'66 and \\ are no words)
  lex.Init(FBuf, FFontTblOpen, FFontTblClose);
  while lex.Next(t) do
    if (t.Kind = rtkWord) and (t.NameLen = 1) and (FBuf[t.NameStart] = Ord('f')) and
       t.HasParam and (t.Param > Result) then
      Result := t.Param;
end;

function TTyRtfParser.ColorCount: Integer;
begin
  Result := FColorCount;
end;

function TTyRtfParser.Color(AIndex: Integer; out AAuto: Boolean): TColor;
begin
  AAuto := FColorAuto[AIndex];
  Result := FColors[AIndex];
end;

procedure TTyRtfParser.ListWord(AKw: Integer);
begin
  case FS.Props.Dest of
    rdList: if AKw = kwListId then FCurList.Id := FTok.Param;
    rdListLevel:
      case AKw of
        kwLevelNfc: FCurLevel.Nfc := FTok.Param;
        kwLevelStartAt: FCurLevel.Start := FTok.Param;
      end;
    rdOverride:
      case AKw of
        kwListId: FCurOvId := FTok.Param;
        kwLs: FCurOvLs := FTok.Param;
      end;
  end;
end;

// ---- pictures ----

procedure TTyRtfParser.BeginPicture;
begin
  FPicFormat := rpfUnknown;
  FPicData := nil;
  FPicLen := 0;
  FPicNibble := -1;
  FPicW := 0;
  FPicH := 0;
  FPicWGoal := 0;
  FPicHGoal := 0;
  FPicSX := 100;
  FPicSY := 100;
end;

procedure TTyRtfParser.PutPicByte(B: Byte);
var
  h: Integer;
begin
  h := HexVal(B);
  if h < 0 then Exit;
  if FPicNibble < 0 then
  begin
    FPicNibble := h;
    Exit;
  end;
  if FPicLen = Length(FPicData) then SetLength(FPicData, FPicLen * 2 + 256);
  FPicData[FPicLen] := (FPicNibble shl 4) or h;
  Inc(FPicLen);
  FPicNibble := -1;
end;

procedure TTyRtfParser.PictWord(AKw: Integer);
begin
  case AKw of
    kwPngBlip: FPicFormat := rpfPng;
    kwJpegBlip: FPicFormat := rpfJpeg;
    kwDibitmap: FPicFormat := rpfDib;
    kwWbitmap: FPicFormat := rpfBmp;
    kwWmetafile: FPicFormat := rpfWmf;
    kwEmfBlip: FPicFormat := rpfEmf;
    kwPicW: FPicW := FTok.Param;
    kwPicH: FPicH := FTok.Param;
    kwPicWGoal: FPicWGoal := FTok.Param;
    kwPicHGoal: FPicHGoal := FTok.Param;
    kwPicScaleX: FPicSX := FTok.Param;
    kwPicScaleY: FPicSY := FTok.Param;
  end;
end;

// The picture read so far, its bytes [AStart, AStop) of the file; nil when counting.
function TTyRtfParser.TakePicture(AStart, AStop: PtrInt): TTyRichPicture;
var
  w, h: Int64;
  data: TBytes;
begin
  if Counting then Exit(nil);
  // the display size: \picwgoal / \pichgoal (twips), else \picw / \pich - hundredths of a
  // millimetre for metafiles, pixels (at 96 dpi) for the rest; then \picscalex / \picscaley
  w := FPicWGoal;
  h := FPicHGoal;
  if w <= 0 then
    if FPicFormat in [rpfWmf, rpfEmf] then w := Int64(FPicW) * 1440 div 2540
    else w := Int64(FPicW) * 15;
  if h <= 0 then
    if FPicFormat in [rpfWmf, rpfEmf] then h := Int64(FPicH) * 1440 div 2540
    else h := Int64(FPicH) * 15;
  if FPicSX > 0 then w := w * FPicSX div 100;
  if FPicSY > 0 then h := h * FPicSY div 100;
  if w > High(Integer) then w := High(Integer) else if w < 0 then w := 0;
  if h > High(Integer) then h := High(Integer) else if h < 0 then h := 0;
  data := Copy(FPicData, 0, FPicLen);
  // (its group has ended: the \uc in effect now is the one it was opened under)
  Result := TTyRichPicture.Create(FPicFormat, data, Integer(w), Integer(h),
    Fragment(Range(AStart, AStop)), FS.Props.Uc);
  FObjects.Add(Result);
  FPicData := nil;
  FPicLen := 0;
end;

// ---- body words ----

// The sides of a paragraph border: the words after one (\brdrs, \brdrw10, \brsp20, ...)
// describe that side.
function IsBorderSide(P: PByte; ALen: Integer): Boolean;
begin
  case ALen of
    3: Result := NameStarts(P, ALen, 'box');
    5: Result := NameStarts(P, ALen, 'brdr') and (P[4] in [Ord('t'), Ord('b'), Ord('l'), Ord('r')]);
    7: Result := NameStarts(P, ALen, 'brdrbtw') or NameStarts(P, ALen, 'brdrbar');
  else
    Result := False;
  end;
end;

// How a control word is kept, by its name.
function FragRule(AName: PByte; ALen: Integer; APara: Boolean): TTyRtfKeepRule; inline;
begin
  Result := krName;
  if APara then
  begin
    // several words describe one border, and the same ones the next: they go with their
    // side. \tbN is one bar tab of several.
    if AName^ = Ord('b') then
    begin
      if IsBorderSide(AName, ALen) then Result := krHeader
      else if NameStarts(AName, ALen, 'brdr') or NameStarts(AName, ALen, 'brsp') then
        Result := krMember;
    end
    else if (ALen = 2) and NameStarts(AName, 2, 'tb') then Result := krExact;
  end
  else
  begin
    // Word's \rtlch\fcs1 ... \ltrch\fcs0 ...: \fcs says which of the two it follows.
    // (Letter by letter: this runs for every unknown word of a file.)
    if ALen = 5 then
    begin
      if (AName[1] = Ord('t')) and (AName[3] = Ord('c')) and (AName[4] = Ord('h')) and
         (((AName[0] = Ord('r')) and (AName[2] = Ord('l'))) or
          ((AName[0] = Ord('l')) and (AName[2] = Ord('r')))) then
        Result := krHeader;
    end
    else if (ALen = 3) and (AName[0] = Ord('f')) and (AName[1] = Ord('c')) and
      (AName[2] = Ord('s')) then
      Result := krMember;
  end;
end;

function FragKey(ABuf: PByte; AStart, AStop: PtrInt; APara: Boolean): TTyRtfFragKey;
var
  p: PtrInt;
  neg: Boolean;
  v: Int64;
begin
  Result.Name := AStart;
  Result.NameLen := 0;
  Result.HasParam := False;
  Result.Param := 0;
  Result.Rule := krExact;
  p := AStart;
  if (p < AStop) and (ABuf[p] = Ord('{')) then
  begin
    // a group kept as a whole: {\*\oldcprops ...}, {\pntxtb ...}
    Inc(p);
    if (p + 1 < AStop) and (ABuf[p] = Ord('\')) and (ABuf[p + 1] = Ord('*')) then Inc(p, 2);
  end;
  if (p + 1 >= AStop) or (ABuf[p] <> Ord('\')) or (LetterTab[ABuf[p + 1]] = 0) then Exit;
  Inc(p);
  Result.Name := p;
  while (p < AStop) and (LetterTab[ABuf[p]] <> 0) do Inc(p);
  Result.NameLen := p - Result.Name;
  // the number, as the lexer reads it
  neg := (p + 1 < AStop) and (ABuf[p] = Ord('-')) and IsDigit(ABuf[p + 1]);
  if neg then Inc(p);
  v := 0;
  while (p < AStop) and IsDigit(ABuf[p]) do
  begin
    Result.HasParam := True;
    if v < 100000000000 then v := v * 10 + (ABuf[p] - Ord('0'));
    Inc(p);
  end;
  if neg then v := -v;
  if v > High(Integer) then v := High(Integer)
  else if v < -High(Integer) then v := -High(Integer);
  Result.Param := Integer(v);
  Result.Rule := FragRule(ABuf + Result.Name, Result.NameLen, APara);
end;

// A node's Key: a hash of the fragment's name (a symbol's: of its bytes) above its rule, so
// that looking for a fragment's like in a list compares numbers, not names.
{$PUSH}{$Q-}{$R-}
function FragHash(ABuf: PByte; const AKey: TTyRtfFragKey; AStart, AStop: PtrInt): Cardinal;
var
  h: Cardinal;
  i, e: PtrInt;
begin
  if AKey.NameLen > 0 then
    // (as the word table's: from the length and four letters; the name is compared after)
    h := WordHash(ABuf + AKey.Name, AKey.NameLen)
  else
  begin
    h := 2166136261;
    i := AStart;
    e := AStop;
    while i < e do
    begin
      h := (h xor ABuf[i]) * 16777619;
      Inc(i);
    end;
  end;
  Result := (h shl 2) or Cardinal(Ord(AKey.Rule));
end;
{$POP}

const
  KeepSmall = 32;    // a list's nodes are gathered on the stack up to this many

// An Extra list is read in its order, with one exception: the header named last (AHead) and
// what follows it up to the next header come last, wherever they stand. Naming a header
// again only says so - Word names \rtlch and \ltrch in every run, and the list need not be
// made anew twice a run for it. This puts the list in that order (then AHead is ALast, the
// last header in it): before the list gets a new fragment, and wherever it is read as it
// stands - a format made from it, a group's saved properties, a snapshot.
procedure TTyRtfParser.Settle(var AList, AHead, ALast: Integer);
var
  few: array[0..KeepSmall - 1] of Integer;
  many: array of Integer;
  ix: PInteger;
  n, i, c, p, h: Integer;
begin
  if AHead = ALast then Exit;
  // the nodes after the header, the earliest first: its own, then the later headers'
  c := 0;
  n := AList;
  while n <> AHead do
  begin
    Inc(c);
    n := FNodes[n].Prev;
  end;
  many := nil;
  if c <= KeepSmall then ix := @few[0]
  else
  begin
    SetLength(many, c);
    ix := @many[0];
  end;
  n := AList;
  for i := c - 1 downto 0 do
  begin
    ix[i] := n;
    n := FNodes[n].Prev;
  end;
  p := 0;
  while (p < c) and (TTyRtfKeepRule(FNodes[ix[p]].Key and 3) <> krHeader) do Inc(p);
  h := AHead;
  AList := FNodes[h].Prev;
  for i := p to c - 1 do
    AList := PushKey(AList, FNodes[ix[i]].A, FNodes[ix[i]].B, FNodes[ix[i]].Key);
  AList := PushKey(AList, FNodes[h].A, FNodes[h].B, FNodes[h].Key);
  AHead := AList;
  ALast := AList;
  for i := 0 to p - 1 do
    AList := PushKey(AList, FNodes[ix[i]].A, FNodes[ix[i]].B, FNodes[ix[i]].Key);
end;

procedure TTyRtfParser.SettleLists;
begin
  with FS.Props do
  begin
    if CharHead <> CharLast then Settle(CharExtra, CharHead, CharLast);
    if ParaHead <> ParaLast then Settle(ParaExtra, ParaHead, ParaLast);
  end;
end;

// The node holds the fragment's like - the same control word (for krExact with the same
// number; a symbol: the same bytes). AAlike: it also says the same: the same word with the
// same number (the space that may end a control word is no difference), or for a group the
// same bytes.
function SameFragment(ABuf: PByte; const ANode: TTyRtfNode; const AKey: TTyRtfFragKey;
  AStart, AStop: PtrInt; APara: Boolean; out AAlike: Boolean): Boolean;
var
  other: TTyRtfFragKey;
  n, i: PtrInt;
  p, q: PByte;
begin
  n := AStop - AStart;
  AAlike := ANode.B - ANode.A = n;
  if AAlike then
    if n <= 16 then
    begin
      // (a control word is a few bytes: compared here, without a call)
      p := ABuf + ANode.A;
      q := ABuf + AStart;
      for i := 0 to n - 1 do
        if p[i] <> q[i] then
        begin
          AAlike := False;
          Break;
        end;
    end
    else
      AAlike := CompareMem(ABuf + ANode.A, ABuf + AStart, n);
  if AKey.NameLen = 0 then Exit(AAlike);
  if AAlike then Exit(True);
  other := FragKey(ABuf, ANode.A, ANode.B, APara);
  Result := (other.NameLen = AKey.NameLen) and
    CompareMem(ABuf + other.Name, ABuf + AKey.Name, AKey.NameLen);
  if not Result then Exit;
  AAlike := (ABuf[AStart] <> Ord('{')) and (ABuf[ANode.A] <> Ord('{')) and
    (other.HasParam = AKey.HasParam) and (other.Param = AKey.Param);
  if (AKey.Rule = krExact) and not AAlike then Result := False;
end;

// Puts the fragment [AStart, AStop) into an Extra list (AList, with its current header AHead
// and its last one ALast). WordPad writes \lang2052 ... \lang1033 ... \lang2052 as bare
// words and never resets them, so a list that only grew would grow with the document, and
// every format and every snapshot with it. A fragment therefore takes the place of its like
// (see TTyRtfKeepRule):
// - a word of the same name goes, and the new one is the list's last: the list is in the
//   order its words were last written;
// - a header named again stays where it is and is the current one (see Settle);
// - a member replaces the member of its name under the current header, where that stands.
// A fragment that says what its like in the list says changes nothing and costs a look
// through the list: Word names the same five words in every run. True: the list reads
// differently now (formats made from it are stale).
function TTyRtfParser.KeepFragment(var AList, AHead, ALast: Integer; AStart, AStop: PtrInt;
  APara: Boolean): Boolean;
var
  key: TTyRtfFragKey;
  k: Cardinal;
  n, found: Integer;
  alike, a: Boolean;
  nodes: ^TTyRtfNode;
begin
  if (FTok.Kind = rtkWord) and (FTok.Start = AStart) and (FTok.Stop = AStop) then
  begin
    // the word just read: its name and number are the token's
    key.Name := FTok.NameStart;
    key.NameLen := FTok.NameLen;
    key.HasParam := FTok.HasParam;
    key.Param := FTok.Param;
    key.Rule := FragRule(FBuf + FTok.NameStart, FTok.NameLen, APara);
  end
  else
    key := FragKey(FBuf, AStart, AStop, APara);
  k := FragHash(FBuf, key, AStart, AStop);
  repeat
    found := -1;
    alike := False;
    n := AList;
    // (the pool does not move while it is only read)
    nodes := Pointer(FNodes);
    if key.Rule <> krMember then
      while n >= 0 do
      begin
        if nodes[n].Key = k then
          if SameFragment(FBuf, nodes[n], key, AStart, AStop, APara, alike) then
          begin
            found := n;
            Break;
          end;
        n := nodes[n].Prev;
      end
    else
      // a member's like: under the current header only - from that header (the start of
      // the list when there is none) to the next one
      while (n >= 0) and (n <> AHead) do
      begin
        if nodes[n].Key = k then
        begin
          if SameFragment(FBuf, nodes[n], key, AStart, AStop, APara, a) then
          begin
            found := n;
            alike := a;
          end;
        end
        else if TTyRtfKeepRule(nodes[n].Key and 3) = krHeader then
          found := -1;      // (a later header's members came first on the way back)
        n := nodes[n].Prev;
      end;
    if (found >= 0) and alike then
    begin
      if key.Rule <> krHeader then Exit(False);
      Result := AHead <> found;
      AHead := found;
      Exit;
    end;
    if found < 0 then
    begin
      // a new one: the list's last (a header: the current one)
      if AHead <> ALast then Settle(AList, AHead, ALast);
      AList := PushKey(AList, AStart, AStop, k);
      if key.Rule = krHeader then
      begin
        AHead := AList;
        ALast := AList;
      end;
      Exit(True);
    end;
    // a word that goes out and comes last leaves a list in its order: settled first, the
    // list is made anew, and its like is looked for again
    if (key.Rule in [krHeader, krMember]) or (AHead = ALast) then Break;
    Settle(AList, AHead, ALast);
  until False;
  ChangeList(AList, AHead, ALast, AStart, AStop, key.Rule, k, found);
  Result := True;
end;

// KeepFragment's other half: the list is made anew from the node that changes on. AFound:
// the fragment's like, which does not say the same.
procedure TTyRtfParser.ChangeList(var AList, AHead, ALast: Integer; AStart, AStop: PtrInt;
  ARule: TTyRtfKeepRule; AKey: Cardinal; AFound: Integer);
var
  few: array[0..KeepSmall - 1] of Integer;
  many: array of Integer;
  ix: PInteger;
  cnt, oldHead, oldLast, i, fresh: Integer;

  // The nodes after ANode, the earliest first, in ix[0 .. cnt - 1].
  procedure Gather(ANode: Integer);
  var
    m, j: Integer;
  begin
    cnt := 0;
    m := AList;
    while m <> ANode do
    begin
      Inc(cnt);
      m := FNodes[m].Prev;
    end;
    if cnt <= KeepSmall then ix := @few[0]
    else
    begin
      SetLength(many, cnt);
      ix := @many[0];
    end;
    m := AList;
    for j := cnt - 1 downto 0 do
    begin
      ix[j] := m;
      m := FNodes[m].Prev;
    end;
  end;

  // Puts a node on the list again as it is; a header keeps its place as AHead / ALast.
  procedure Carry(ANode: Integer);
  begin
    AList := PushKey(AList, FNodes[ANode].A, FNodes[ANode].B, FNodes[ANode].Key);
    if ANode = oldHead then AHead := AList;
    if ANode = oldLast then ALast := AList;
  end;

begin
  many := nil;
  if ARule in [krHeader, krMember] then
  begin
    // where its like stood
    Gather(AFound);
    oldHead := AHead;
    oldLast := ALast;
    AList := PushKey(FNodes[AFound].Prev, AStart, AStop, AKey);
    fresh := AList;
    if AFound = oldLast then ALast := fresh;
    if AFound = oldHead then AHead := fresh;
    for i := 0 to cnt - 1 do Carry(ix[i]);
    if ARule = krHeader then AHead := fresh;
    Exit;
  end;
  // its like out, the new one last (the list is settled: KeepFragment saw to it)
  Gather(AFound);
  oldHead := AHead;
  oldLast := ALast;
  AList := FNodes[AFound].Prev;
  for i := 0 to cnt - 1 do Carry(ix[i]);
  AList := PushKey(AList, AStart, AStop, AKey);
end;

procedure TTyRtfParser.AddCharExtra(AStart, AStop: PtrInt);
begin
  with FS.Props do
    if KeepFragment(CharExtra, CharHead, CharLast, AStart, AStop, False) then CharChanged;
end;

procedure TTyRtfParser.AddParaExtra(AStart, AStop: PtrInt);
begin
  with FS.Props do
    if KeepFragment(ParaExtra, ParaHead, ParaLast, AStart, AStop, True) then ParaChanged;
end;

// A node list's entries, first to last.
function TTyRtfParser.ListNodes(AList: Integer): TTyRtfNodes;
var
  n, i: Integer;
begin
  n := 0;
  i := AList;
  while i >= 0 do
  begin
    Inc(n);
    i := FNodes[i].Prev;
  end;
  Result := nil;
  SetLength(Result, n);
  i := AList;
  while i >= 0 do
  begin
    Dec(n);
    Result[n] := FNodes[i];
    i := FNodes[i].Prev;
  end;
end;

procedure TTyRtfParser.EndRowDef;
begin
  FS.InRowDef := False;
end;

// A sign of a table inside a cell (\itap of 2 or more, \nestcell, \nestrow, the nested
// table's properties): the table cannot be edited as a grid, and the row being read holds
// more than the model has of it - it is marked, so that it stays as the file has it.
procedure TTyRtfParser.MarkNested;
begin
  FS.Nested := True;
  FS.RowNested := True;
end;

procedure TTyRtfParser.BodyWord(AKw: Integer);
var
  p: Integer;
  onOff: Boolean;
  inPn, normal: Boolean;
begin
  p := FTok.Param;
  onOff := not FTok.HasParam or (p <> 0);
  inPn := FS.Props.Dest = rdPn;
  normal := FS.Props.Dest = rdNormal;
  // what starts the body: anything that formats or is text - not the document's own words
  if not FS.BodyStarted and normal then
    case AKw of
      kwPlain..kwRtlCh, kwPard..kwRtlPar, kwIntbl..kwNestRow, kwPar..kwObjWord: EnsureBody;
      kwUnknown:
        ;  // an unknown word before the body is the header's
    end;
  case AKw of
    // document
    kwAnsi, kwMac, kwPc, kwPca:
      if not FAnsiCpSet then
      begin
        case AKw of
          kwAnsi: FAnsiCp := 1252;
          kwMac: FAnsiCp := 10000;
          kwPc: FAnsiCp := 437;
        else
          FAnsiCp := 850;
        end;
        TablesChanged;
      end;
    kwAnsiCpg:
      begin
        p := RtfCodePage(p);
        if TyRichCodePageSupported(p) then FAnsiCp := p else FAnsiCp := 1252;
        FAnsiCpSet := True;
        Inc(FFontGen);
        TablesChanged;
      end;
    kwDeff:
      begin
        FDeff := p;
        TablesChanged;
        CharChanged;
      end;
    kwPaperW, kwPaperH, kwMargL, kwMargR:
      begin
        case AKw of
          kwPaperW: if p > 0 then FPaperW := p;
          kwPaperH: if p > 0 then FPaperH := p;
          kwMargL: if p >= 0 then FMargL := p;
        else
          if p >= 0 then FMargR := p;
        end;
        TablesChanged;
      end;
    kwUc: if p >= 0 then FS.Props.Uc := p;
    kwU: EmitUnicode(p);
    // character
    kwPlain: ResetChar;
    kwB:
      begin
        FS.Props.Bold := onOff;
        CharChanged;
      end;
    kwI:
      begin
        FS.Props.Italic := onOff;
        CharChanged;
      end;
    kwUl:
      begin
        FS.Props.Underline := onOff;
        CharChanged;
      end;
    kwUlNone:
      begin
        FS.Props.Underline := False;
        CharChanged;
      end;
    kwStrike:
      begin
        FS.Props.Strike := onOff;
        CharChanged;
      end;
    kwSuper:
      begin
        FS.Props.VertAlign := vaSuper;
        CharChanged;
      end;
    kwSub:
      begin
        FS.Props.VertAlign := vaSub;
        CharChanged;
      end;
    kwNoSuperSub:
      begin
        FS.Props.VertAlign := vaNone;
        CharChanged;
      end;
    kwF:
      begin
        FS.Props.FontNum := p;
        case FS.Props.Slot of
          sloLoch: FS.Props.LochNum := p;
          sloHich: FS.Props.HichNum := p;
          sloDbch: FS.Props.DbchNum := p;
        end;
        CharChanged;
      end;
    kwAf:
      case FS.Props.Slot of
        sloLoch: FS.Props.LochNum := p;
        sloHich: FS.Props.HichNum := p;
        sloDbch: FS.Props.DbchNum := p;
      else
        // the font of right-to-left text: not modelled
        if normal then AddCharExtra(FTok.Start, FTok.Stop);
      end;
    kwFs:
      begin
        if p > 0 then FS.Props.Size := p else FS.Props.Size := DefaultSize;
        CharChanged;
      end;
    kwCf:
      begin
        FS.Props.ColorIdx := p;
        CharChanged;
      end;
    kwHighlight:
      begin
        FS.Props.HighlightIdx := p;
        CharChanged;
      end;
    kwLoch: FS.Props.Slot := sloLoch;
    kwHich: FS.Props.Slot := sloHich;
    kwDbch: FS.Props.Slot := sloDbch;
    kwRtlCh, kwLtrCh:
      begin
        FS.Props.Slot := sloOther;
        if normal then AddCharExtra(FTok.Start, FTok.Stop);
      end;
    // paragraph
    kwPard: ResetPara;
    kwQl, kwQc, kwQr, kwQj:
      begin
        case AKw of
          kwQl: FS.Props.Align := paraLeft;
          kwQc: FS.Props.Align := paraCenter;
          kwQr: FS.Props.Align := paraRight;
        else
          FS.Props.Align := paraJustify;
        end;
        ParaChanged;
      end;
    kwLi:
      begin
        FS.Props.LeftIndent := p;
        ParaChanged;
      end;
    kwRi:
      begin
        FS.Props.RightIndent := p;
        ParaChanged;
      end;
    kwFi:
      begin
        FS.Props.FirstIndent := p;
        ParaChanged;
      end;
    kwSb:
      begin
        FS.Props.SpaceBefore := p;
        ParaChanged;
      end;
    kwSa:
      begin
        FS.Props.SpaceAfter := p;
        ParaChanged;
      end;
    kwSl:
      begin
        FS.Props.Sl := p;
        FS.Props.SlMult := 0;
        FS.Props.SlTok := Range(FTok.Start, FTok.Stop);
        FS.Props.SlMultTok := Range(-1, -1);
        ParaChanged;
      end;
    kwSlMult:
      begin
        FS.Props.SlMult := p;
        FS.Props.SlMultTok := Range(FTok.Start, FTok.Stop);
        ParaChanged;
      end;
    kwTqc: FS.Props.TabAlign := ttaCenter;
    kwTqr: FS.Props.TabAlign := ttaRight;
    kwTqDec: FS.Props.TabAlign := ttaDecimal;
    kwTlDot: FS.Props.TabLeader := ttlDot;
    kwTlHyph: FS.Props.TabLeader := ttlHyphen;
    kwTlUl: FS.Props.TabLeader := ttlUnderline;
    kwTlTh: FS.Props.TabLeader := ttlThick;
    kwTlEq: FS.Props.TabLeader := ttlEqual;
    kwTx:
      begin
        FS.Props.Tabs := Push(FS.Props.Tabs, p,
          Ord(FS.Props.TabAlign) or (Ord(FS.Props.TabLeader) shl 8));
        FS.Props.TabAlign := ttaLeft;
        FS.Props.TabLeader := ttlNone;
        ParaChanged;
      end;
    kwRtlPar, kwLtrPar:
      begin
        FS.Props.RtlPar := AKw = kwRtlPar;
        ParaChanged;
      end;
    kwIntbl:
      begin
        FS.Props.InTable := True;
        ParaChanged;
      end;
    kwItap:
      begin
        FS.Props.Itap := p;
        if p >= 2 then MarkNested;
        ParaChanged;
      end;
    kwLs, kwIlvl:
      begin
        if AKw = kwLs then FS.Props.Ls := p else FS.Props.Ilvl := p;
        // the list it names lives in the header's table: the reference stays as it was
        AddParaExtra(FTok.Start, FTok.Stop);
      end;
    kwParaExtra: if normal or inPn then AddParaExtra(FTok.Start, FTok.Stop);
    kwPnLvlBlt, kwPnLvlBody, kwPnLvl:
      begin
        if AKw = kwPnLvlBlt then
        begin
          FS.Props.ListKind := lkBullet;
          FS.Props.ListLevel := 0;
        end
        else
        begin
          if FS.Props.ListKind in [lkNone, lkBullet] then FS.Props.ListKind := lkDecimal;
          if AKw = kwPnLvl then FS.Props.ListLevel := p - 1 else FS.Props.ListLevel := 0;
          if FS.Props.ListLevel < 0 then FS.Props.ListLevel := 0;
        end;
        ParaChanged;
      end;
    kwPnDec, kwPnLcLtr, kwPnUcLtr, kwPnLcRm, kwPnUcRm:
      begin
        case AKw of
          kwPnDec: FS.Props.ListKind := lkDecimal;
          kwPnLcLtr: FS.Props.ListKind := lkLowerAlpha;
          kwPnUcLtr: FS.Props.ListKind := lkUpperAlpha;
          kwPnLcRm: FS.Props.ListKind := lkLowerRoman;
        else
          FS.Props.ListKind := lkUpperRoman;
        end;
        ParaChanged;
      end;
    kwPnStart:
      begin
        FS.Props.ListStart := p;
        ParaChanged;
      end;
    // tables
    kwTrowd:
      begin
        FS.InRowDef := True;
        FS.RowDef.Cellx := -1;
        FS.RowDef.Merged := False;
        FS.RowDef.Raw := Range(FTok.Start, FTok.Stop);
      end;
    kwCellx:
      begin
        FS.RowDef.Cellx := Push(FS.RowDef.Cellx, p, 0);
        if FS.InRowDef then FS.RowDef.Raw.Stop := FTok.Stop;
      end;
    kwClMerge:
      begin
        FS.RowDef.Merged := True;
        if FS.InRowDef then FS.RowDef.Raw.Stop := FTok.Stop;
      end;
    kwCell: if normal then EndParagraph(rpkCell);
    kwNestCell:
      if normal then
      begin
        MarkNested;
        EndParagraph(rpkNestCell);
      end;
    kwNestRow: MarkNested;
    kwRow: if normal then DoRow;
    // characters
    kwPar: if normal then EndParagraph(rpkPar);
    kwLine: EmitChar($0B);
    kwTab: EmitChar($09);
    kwLdblquote: EmitChar($201C);
    kwRdblquote: EmitChar($201D);
    kwLquote: EmitChar($2018);
    kwRquote: EmitChar($2019);
    kwEmdash: EmitChar($2014);
    kwEndash: EmitChar($2013);
    kwBullet: EmitChar($2022);
    kwEmspace: EmitChar($2003);
    kwEnspace: EmitChar($2002);
    kwQmspace: EmitChar($2005);
    kwZwj: EmitChar($200D);
    kwZwnj: EmitChar($200C);
    kwLtrMark: EmitChar($200E);
    kwRtlMark: EmitChar($200F);
    kwZwbo: EmitChar($200B);
    kwZwnbo: EmitChar($FEFF);
    kwObjWord:
      if normal and (FFieldNest = 0) then
      begin
        EnsureBody;
        EmitOpaque(FTok.Start, FTok.Stop, '');
      end;
  else
    // a word of a table row, or one this reader does not know
    if IsRowWord(@FBuf[FTok.NameStart], FTok.NameLen, FS.InRowDef) then
    begin
      if FS.InRowDef then FS.RowDef.Raw.Stop := FTok.Stop;
    end
    else if (normal and FS.BodyStarted) or inPn then
    begin
      if inPn or IsParaPrefixWord(@FBuf[FTok.NameStart], FTok.NameLen) then
        AddParaExtra(FTok.Start, FTok.Stop)
      else
        AddCharExtra(FTok.Start, FTok.Stop);
    end;
  end;
end;

// ---- the body and its paragraphs ----

procedure TTyRtfParser.EnsureBody;
begin
  if FS.BodyStarted then Exit;
  FS.BodyStarted := True;
  if FS.PendingGroup >= 0 then
  begin
    FS.HeaderEnd := FS.PendingGroup;
    FS.BoundaryDepth := FS.PendingGroupDepth;
  end
  else
  begin
    FS.HeaderEnd := FTok.Start;
    FS.BoundaryDepth := FS.Depth;
  end;
  FS.PendingGroup := -1;
  FS.Boundary := FS.HeaderEnd;
  FS.LastStartDepth := FS.BoundaryDepth;
end;

// The current token is content of the current paragraph.
procedure TTyRtfParser.StartContent;
begin
  EnsureBody;
  FS.HasContent := True;
  FS.CurEnd := FTokStop;
  FS.Absorb := absCurrent;
  FContent := True;
end;

procedure TTyRtfParser.AddRun(AFormat: TTyCharFormatId; AObj: TTyRichObject);
begin
  if (FRunN > 0) and (AObj = nil) and (FRuns[FRunN - 1].Obj = nil) and
     (FRuns[FRunN - 1].Format = AFormat) then
    Exit;
  if FRunN = Length(FRuns) then SetLength(FRuns, FRunN * 2 + 4);
  FRuns[FRunN].Start := FCurChars;
  FRuns[FRunN].Format := AFormat;
  FRuns[FRunN].Obj := AObj;
  Inc(FRunN);
end;

procedure TTyRtfParser.PutOut(ACode: Cardinal);
begin
  UtfPut(FOut, FOutLen, ACode);
end;

procedure TTyRtfParser.PutField(ACode: Cardinal);
var
  b: TBytes;
  n: PtrInt;
begin
  b := nil;
  n := 0;
  UtfPut(b, n, ACode);
  if FFieldLen + n > Length(FFieldText) then SetLength(FFieldText, (FFieldLen + n) * 2 + 16);
  Move(b[0], FFieldText[FFieldLen + 1], n);
  Inc(FFieldLen, n);
end;

// A character of the text, as it is (pending halves are the caller's).
procedure TTyRtfParser.EmitCode(ACode: Cardinal; AFromPair: Boolean);
begin
  if FS.Props.Dest = rdFieldResult then
  begin
    if ACode >= $20 then PutField(ACode);
    Exit;
  end;
  if FS.Props.Dest <> rdNormal then Exit;
  StartContent;
  if not Counting then
  begin
    AddRun(CharFormatFor(ClassOf(ACode, AFromPair)), nil);
    PutOut(ACode);
  end;
  FS.OneShot.Start := -1;
  Inc(FCurChars);
end;

// A lone lead byte reads as '?', a lone high surrogate as U+FFFD.
procedure TTyRtfParser.Flush;
begin
  if FS.PendingLead >= 0 then
  begin
    FS.PendingLead := -1;
    EmitCode(Ord('?'), False);
  end;
  if FS.PendingHigh <> 0 then
  begin
    FS.PendingHigh := 0;
    EmitCode($FFFD, False);
  end;
end;

procedure TTyRtfParser.EmitChar(ACode: Cardinal);
begin
  if not (FS.Props.Dest in [rdNormal, rdFieldResult]) then Exit;
  if FS.InRowDef then EndRowDef;
  Flush;
  EmitCode(ACode, False);
end;

procedure TTyRtfParser.EmitUnicode(AValue: Integer);
var
  c: Cardinal;
begin
  if not (FS.Props.Dest in [rdNormal, rdFieldResult]) then Exit;
  c := UnicodeOfParam(AValue);
  if FS.PendingLead >= 0 then
  begin
    FS.PendingLead := -1;
    EmitCode(Ord('?'), False);
  end;
  if (c >= $DC00) and (c <= $DFFF) and (FS.PendingHigh <> 0) then
  begin
    c := $10000 + ((Cardinal(FS.PendingHigh) - $D800) shl 10) + (c - $DC00);
    FS.PendingHigh := 0;
    EmitCode(c, False);
  end
  else
  begin
    Flush;
    if (c >= $D800) and (c <= $DBFF) then
    begin
      FS.PendingHigh := c;
      StartContent;     // the character it begins is this paragraph's
    end
    else if (c >= $DC00) and (c <= $DFFF) then
      EmitCode($FFFD, False)
    else if (c = 0) or (c = 10) or (c = 13) then
      // not text: a NUL, and line breaks that would split the paragraph
    else
      EmitCode(c, False);
  end;
  FS.UcSkip := FS.Props.Uc;
end;

// One byte of text (raw, or written \'xx), in the font in effect.
procedure TTyRtfParser.ProcessByte(B: Byte);
var
  lead: Integer;
  code: Cardinal;
begin
  if FS.UcSkip > 0 then
  begin
    Dec(FS.UcSkip);
    Exit;
  end;
  if (B = 0) or (B = 10) or (B = 13) then Exit;
  if FS.PendingHigh <> 0 then
  begin
    FS.PendingHigh := 0;
    EmitCode($FFFD, False);
  end;
  UpdateDecoder;
  if FS.PendingLead >= 0 then
  begin
    lead := FS.PendingLead;
    FS.PendingLead := -1;
    if (FS.PendingLeadFont = FS.Props.FontNum) and (FDecTable <> nil) then
    begin
      code := TyRichCodePageChar(FDecTable, lead, B);
      if code <> 0 then
      begin
        EmitCode(code, True);
        Exit;
      end;
    end;
    EmitCode(Ord('?'), False);
  end;
  if B < $20 then
  begin
    if B = 9 then EmitCode(9, False);
    Exit;
  end;
  if FDecCp = CpSymbol then
  begin
    if B > $20 then EmitCode($F000 + B, False) else EmitCode(B, False);
    Exit;
  end;
  if (B < $80) or (FDecTable = nil) then
  begin
    if B < $80 then EmitCode(B, False) else EmitCode(Ord('?'), False);
    Exit;
  end;
  if TyRichCodePageIsLead(FDecTable, B) then
  begin
    FS.PendingLead := B;
    FS.PendingLeadFont := FS.Props.FontNum;
    if FS.Props.Dest = rdNormal then StartContent;
    Exit;
  end;
  code := TyRichCodePageChar(FDecTable, B, -1);
  if code = 0 then code := Ord('?');
  EmitCode(code, False);
end;

// The code page (and its table) of the font in effect.
procedure TTyRtfParser.UpdateDecoder;
var
  i: Integer;
begin
  if (FDecNum = FS.Props.FontNum) and (FDecGen = FFontGen) then Exit;
  FDecNum := FS.Props.FontNum;
  FDecGen := FFontGen;
  i := FontOfNum(FDecNum);
  if i >= 0 then
  begin
    FDecCp := FFonts[i].CodePage;
    FDecTable := FFonts[i].Table;
  end
  else
  begin
    FDecCp := FAnsiCp;
    FDecTable := TyRichCodePageTable(FAnsiCp);
  end;
  if (FDecCp <> CpSymbol) and (FDecTable = nil) then
  begin
    FDecCp := 1252;
    FDecTable := TyRichCodePageTable(1252);
  end;
  if FDecTable <> nil then
  begin
    FDecCls := TyRichCodePageClasses(FDecTable);
    FDecPairs := TyRichCodePagePairs(FDecTable);
  end
  else
  begin
    FDecCls := nil;
    FDecPairs := nil;
  end;
end;

procedure TTyRtfParser.EmitObject(AObj: TTyRichObject);
begin
  Flush;
  StartContent;
  if not Counting then
  begin
    AddRun(CharFormatFor(rccLoch), AObj);
    PutOut($FFFC);
  end;
  Inc(FCurChars);
end;

procedure TTyRtfParser.EmitOpaque(AStart, AStop: PtrInt; const ADisplay: UTF8String);
var
  o: TTyRichOpaque;
  uc: Integer;
begin
  if Counting then
  begin
    EmitObject(nil);
    Exit;
  end;
  // the block is a group that has ended: the \uc in effect here is the one its bytes were
  // read under, and they only read the same again under that one. (One control word kept
  // as an object - a page number - holds no \uN: it reads the same anywhere.)
  if FBuf[AStart] = Ord('{') then uc := FS.Props.Uc else uc := 1;
  o := TTyRichOpaque.Create(Fragment(Range(AStart, AStop)), ADisplay, uc);
  FObjects.Add(o);
  EmitObject(o);
end;

procedure TTyRtfParser.EndParagraph(AKind: TTyRtfParaKind);
var
  rec: ^TTyRtfParaRec;
  inTable: Boolean;
  i: Integer;
begin
  if FS.InRowDef then EndRowDef;
  Flush;
  EnsureBody;
  // the record is filled where it goes (no record with a managed field is copied per
  // paragraph: the index scan ends millions of them)
  if FParaN = Length(FParas) then SetLength(FParas, FParaN * 2 + 16);
  rec := @FParas[FParaN];
  rec^.Table := -1;
  rec^.Row := 0;
  rec^.Cell := 0;
  rec^.Format := 0;
  rec^.TextStart := 0;
  rec^.TextLen := 0;
  rec^.Chars := FCurChars;
  rec^.Src := Range(FS.Boundary, FTok.Stop);
  if not Counting then
  begin
    if FRunN = 0 then AddRun(CharFormatFor(rccLoch), nil);
    rec^.Runs := Copy(FRuns, 0, FRunN);
    rec^.Format := ParaFormatId;
    rec^.TextStart := FParaTextStart;
    rec^.TextLen := FOutLen - FParaTextStart;
    for i := 1 to Length(FSep) do PutOut(Ord(FSep[i]));
    FParaTextStart := FOutLen;
  end
  else if rec^.Runs <> nil then
    rec^.Runs := nil;
  inTable := (AKind <> rpkPar) or FS.Props.InTable or (FS.Props.Itap > 0);
  if inTable then
  begin
    // (a parse resumed inside a table starts a record of its own for the rest of it)
    if not FS.TableOpen or (not Counting and (FTableN = 0)) then
    begin
      if not FS.TableOpen then
      begin
        if FExtentN = Length(FExtents) then SetLength(FExtents, FExtentN * 2 + 4);
        FExtents[FExtentN].FirstPara := FParaBase + FParaN;
        FExtents[FExtentN].LastPara := -1;
        FExtents[FExtentN].Start := rec^.Src.Start;
        FExtents[FExtentN].Stop := -1;
        Inc(FExtentN);
      end;
      FS.TableOpen := True;
      if not Counting then
      begin
        if FTableN = Length(FTables) then SetLength(FTables, FTableN * 2 + 2);
        FTables[FTableN] := Default(TTyRtfTableRec);
        Inc(FTableN);
      end;
    end;
    if not Counting then
    begin
      rec^.Table := FTableN - 1;
      rec^.Row := FTables[FTableN - 1].RowCount;
      rec^.Cell := FS.CellIdx;
    end;
    if FS.CellIdx + 1 > FS.RowMax then FS.RowMax := FS.CellIdx + 1;
    if AKind = rpkCell then Inc(FS.CellIdx);
    // (the level may have been set in a row before this one)
    if FS.Props.Itap >= 2 then MarkNested;
  end
  else if FS.TableOpen then
    CloseTable;
  Inc(FParaN);
  FS.LastStartDepth := FS.BoundaryDepth;
  FS.Boundary := FTok.Stop;
  FS.BoundaryDepth := FS.Depth;
  FS.Absorb := absLast;
  FCommitted := True;
  FS.HasContent := False;
  FS.LastWasCell := AKind = rpkCell;
  FS.OneShot.Start := -1;
  Inc(FS.Paras);
  FRunN := 0;
  FCurChars := 0;
end;

procedure TTyRtfParser.DoRow;
begin
  if FS.HasContent then
    EndParagraph(rpkCell)
  else if FS.LastWasCell then
  begin
    // the row's end belongs to its last cell
    FS.Boundary := FTok.Stop;
    FS.BoundaryDepth := FS.Depth;
    if FParaN > 0 then FParas[FParaN - 1].Src.Stop := FTok.Stop;
    FS.Absorb := absLast;
    FCommitted := True;
  end;
  FS.LastWasCell := False;
  if FS.TableOpen then FinishRow;
  EndRowDef;
end;

procedure TTyRtfParser.FinishRow;
var
  n, i: Integer;
  r: TTyRtfRowRec;
  nodes: TTyRtfNodes;
begin
  n := FS.CellIdx;
  if FS.RowMax > n then n := FS.RowMax;
  FS.CellIdx := 0;
  FS.RowMax := 0;
  r.Nested := FS.RowNested;
  FS.RowNested := False;
  if (n = 0) or Counting or (FTableN = 0) then Exit;
  r.CellCount := n;
  r.Raw := FS.RowDef.Raw;
  nodes := ListNodes(FS.RowDef.Cellx);
  r.Cellx := nil;
  SetLength(r.Cellx, Length(nodes));
  for i := 0 to High(nodes) do r.Cellx[i] := nodes[i].A;
  with FTables[FTableN - 1] do
  begin
    if RowCount = Length(Rows) then SetLength(Rows, RowCount * 2 + 4);
    Rows[RowCount] := r;
    Inc(RowCount);
    if FS.RowDef.Merged or FS.Nested then Locked := True;
  end;
end;

procedure TTyRtfParser.CloseTable;
begin
  if (FS.CellIdx > 0) or (FS.RowMax > 0) then FinishRow;
  if not Counting and (FTableN > 0) and FS.Nested then FTables[FTableN - 1].Locked := True;
  FS.TableOpen := False;
  FS.Nested := False;
  FS.RowNested := False;
  // the table's last paragraph is the last one that ended
  if (FExtentN > 0) and (FExtents[FExtentN - 1].LastPara < 0) and (FParaN > 0) then
  begin
    FExtents[FExtentN - 1].LastPara := FParaBase + FParaN - 1;
    FExtents[FExtentN - 1].Stop := FParas[FParaN - 1].Src.Stop;
  end;
end;

procedure TTyRtfParser.Finish;
var
  keep: PtrInt;
  had: Boolean;
begin
  if FFinished then Exit;
  FFinished := True;
  // a file cut short: its open groups end here
  FTok.Start := FLen;
  FTok.Stop := FLen;
  FTokStop := FLen;
  while not FS.DocClosed and (FS.Depth > 0) do PopGroup;
  if FS.DocCloseAt < 0 then FS.DocCloseAt := FLen;
  if FS.HasContent or (FS.PendingLead >= 0) or (FS.PendingHigh <> 0) then
  begin
    // the halves still waiting are the last paragraph's (it ends where its bytes did)
    had := FS.HasContent;
    keep := FS.CurEnd;
    Flush;
    if had then FS.CurEnd := keep;
  end;
  if not FS.BodyStarted then
  begin
    FS.BodyStarted := True;
    FS.HeaderEnd := FS.DocCloseAt;
    FS.Boundary := FS.HeaderEnd;
  end;
  FLastOpen := FS.HasContent or (FS.Paras = 0);
  if FS.HasContent then
  begin
    FTok.Stop := FS.CurEnd;
    EndParagraph(rpkPar);
    FTrailerStart := FS.Boundary;
  end
  else if FS.Paras = 0 then
  begin
    // an empty document is one empty paragraph
    FTok.Stop := FS.Boundary;
    EndParagraph(rpkPar);
    FTrailerStart := FS.Boundary;
  end
  else
    // the last \par makes no paragraph after it
    FTrailerStart := FS.Boundary;
  if FS.TableOpen then CloseTable;
end;

// ---- formats ----

function TTyRtfParser.SlotsSet: Boolean;
begin
  Result := (FS.Props.LochNum >= 0) or (FS.Props.HichNum >= 0) or (FS.Props.DbchNum >= 0);
end;

// Which of Word's three fonts a character takes: ASCII the low-ANSI one, East Asian
// characters (and every character of a double-byte pair) the double-byte one, the rest the
// high-ANSI one - or the double-byte one when \dbch was the last of the three named, as Word
// does for punctuation both scripts share.
function TTyRtfParser.ClassOf(ACode: Cardinal; AFromPair: Boolean): TTyRtfCharClass;
begin
  if not SlotsSet then Exit(rccLoch);
  if AFromPair then Result := rccDbch
  else if ACode < $80 then Result := rccLoch
  else if IsEastAsian(ACode) then Result := rccDbch
  else if FS.Props.Slot = sloDbch then Result := rccDbch
  else Result := rccHich;
end;

function TTyRtfParser.Fragment(const R: TTyRtfRange): RawByteString;
begin
  Result := '';
  if R.Stop <= R.Start then Exit;
  SetLength(Result, R.Stop - R.Start);
  Move(FBuf[R.Start], Result[1], R.Stop - R.Start);
end;

function TTyRtfParser.BuildCharFormat(AClass: TTyRtfCharClass; AOneShot: Boolean): TTyCharFormat;
var
  num, i: Integer;
  nodes: TTyRtfNodes;
begin
  Result := TyDefaultCharFormat;
  num := FS.Props.FontNum;
  case AClass of
    rccLoch: if FS.Props.LochNum >= 0 then num := FS.Props.LochNum;
    rccHich: if FS.Props.HichNum >= 0 then num := FS.Props.HichNum;
    rccDbch: if FS.Props.DbchNum >= 0 then num := FS.Props.DbchNum;
  end;
  i := FontOfNum(num);
  if i >= 0 then
  begin
    Result.FontName := AsString(FFonts[i].Name);
    if FFonts[i].Charset >= 0 then Result.Charset := FFonts[i].Charset;
  end;
  Result.SizeHalfPt := FS.Props.Size;
  if FS.Props.Bold then Include(Result.Style, fsBold);
  if FS.Props.Italic then Include(Result.Style, fsItalic);
  if FS.Props.Underline then Include(Result.Style, fsUnderline);
  Result.Strike := FS.Props.Strike;
  Result.VertAlign := FS.Props.VertAlign;
  Result.Color := ColorOf(FS.Props.ColorIdx, clDefault);
  Result.HighlightColor := ColorOf(FS.Props.HighlightIdx, clNone);
  SettleLists;
  nodes := ListNodes(FS.Props.CharExtra);
  for i := 0 to High(nodes) do
    Result.Extra.Add(Fragment(Range(nodes[i].A, nodes[i].B)));
  if AOneShot then Result.Extra.Add(Fragment(FS.OneShot));
end;

function TTyRtfParser.CharFormatFor(AClass: TTyRtfCharClass): TTyCharFormatId;
begin
  if FS.OneShot.Start >= 0 then
  begin
    Result := FPool.InternChar(BuildCharFormat(AClass, True));
    FS.OneShot.Start := -1;
    Exit;
  end;
  if not FCharValid[AClass] then
  begin
    FCharId[AClass] := FPool.InternChar(BuildCharFormat(AClass, False));
    FCharValid[AClass] := True;
  end;
  Result := FCharId[AClass];
end;

procedure TTyRtfParser.ResolveListRef(ALs, AIlvl: Integer; var AList: TTyListFormat);
var
  i, id, lvl: Integer;
begin
  id := -1;
  for i := 0 to FOverrideCount - 1 do
    if FOverrideLs[i] = ALs then
    begin
      id := FOverrideId[i];
      Break;
    end;
  if id < 0 then Exit;
  for i := 0 to FListCount - 1 do
    if FLists[i].Id = id then
    begin
      lvl := AIlvl;
      if lvl < 0 then lvl := 0;
      AList.Level := lvl;
      if lvl > High(FLists[i].Levels) then Exit;
      case FLists[i].Levels[lvl].Nfc of
        0: AList.Kind := lkDecimal;
        1: AList.Kind := lkUpperRoman;
        2: AList.Kind := lkLowerRoman;
        3: AList.Kind := lkUpperAlpha;
        4: AList.Kind := lkLowerAlpha;
        23: AList.Kind := lkBullet;
      else
        AList.Kind := lkNone;
      end;
      if AList.Kind <> lkNone then AList.StartAt := FLists[i].Levels[lvl].Start;
      Exit;
    end;
end;

// The paragraph's {\*\pn ...} group holds, beside what the list format has, exactly what
// RichEdit writes for a list of that kind - the font of the bullet (a Symbol font) or of the
// number, \pnindent0, and {\pntxtb\'B7} for a bullet or {\pntxta.} for a number - and
// nothing else. Then the list format says all of it (a writer makes these words from it),
// and they are not kept beside it. One thing more or less in the group, and all of them stay.
function TTyRtfParser.PlainListWords(const ANodes: TTyRtfNodes): Boolean;
var
  i, k, param: Integer;
  frag: RawByteString;
  hasFont, hasIndent, hasText: Boolean;
begin
  Result := False;
  if (FS.Props.Ls > 0) or (FS.Props.ListKind = lkNone) then Exit;
  hasFont := False;
  hasIndent := False;
  hasText := False;
  for i := 0 to High(ANodes) do
  begin
    frag := Fragment(Range(ANodes[i].A, ANodes[i].B));
    if TyRtfParaExtraKind(frag, param) <> pekPn then Continue;
    if TyRtfFragmentIsWord(frag, 'pnf') then
    begin
      if FS.Props.ListKind = lkBullet then
      begin
        k := FontIndex(param);
        if (k < 0) or (FFonts[k].Charset <> 2) then Exit;
      end;
      hasFont := True;
    end
    else if TyRtfFragmentIsWord(frag, 'pnindent') then
    begin
      if param <> 0 then Exit;
      hasIndent := True;
    end
    else if FS.Props.ListKind = lkBullet then
    begin
      if (frag <> '{\pntxtb\''B7}') and (frag <> '{\pntxtb\''b7}') then Exit;
      hasText := True;
    end
    else
    begin
      if frag <> '{\pntxta.}' then Exit;
      hasText := True;
    end;
  end;
  Result := hasFont and hasIndent and hasText;
end;

function TTyRtfParser.BuildParaFormat: TTyParaFormat;
var
  i, param: Integer;
  slExtra, plain: Boolean;
  nodes: TTyRtfNodes;
  frag: RawByteString;
begin
  Result := TyDefaultParaFormat;
  SettleLists;
  nodes := ListNodes(FS.Props.Tabs);
  if Length(nodes) > 0 then
  begin
    SetLength(Result.Tabs, Length(nodes));
    for i := 0 to High(nodes) do
    begin
      Result.Tabs[i].Position := nodes[i].A;
      Result.Tabs[i].Align := TTyTabAlign(nodes[i].B and $FF);
      Result.Tabs[i].Leader := TTyTabLeader(nodes[i].B shr 8);
    end;
  end;
  with FS.Props do
  begin
    Result.Align := Align;
    Result.LeftIndent := LeftIndent;
    Result.RightIndent := RightIndent;
    Result.FirstIndent := FirstIndent;
    Result.SpaceBefore := SpaceBefore;
    Result.SpaceAfter := SpaceAfter;
    Result.RtlPar := RtlPar;
    slExtra := False;
    if Sl <> 0 then
      if SlMult = 1 then
        case Sl of
          240: Result.LineSpacing := lsSingle;
          276: Result.LineSpacing := ls115;
          360: Result.LineSpacing := ls15;
          480: Result.LineSpacing := lsDouble;
        else
          slExtra := True;    // a multiple the model has no name for: kept as written
        end
      else if Sl < 0 then
      begin
        Result.LineSpacing := lsExact;
        Result.LineSpacingValue := -Sl;
      end
      else
      begin
        Result.LineSpacing := lsAtLeast;
        Result.LineSpacingValue := Sl;
      end;
    if Ls > 0 then
      ResolveListRef(Ls, Ilvl, Result.List)
    else if ListKind <> lkNone then
    begin
      Result.List.Kind := ListKind;
      Result.List.Level := ListLevel;
      Result.List.StartAt := ListStart;
      if (ListKind <> lkBullet) and (ListStart = 0) then Result.List.StartAt := 1;
    end;
    nodes := ListNodes(ParaExtra);
    plain := PlainListWords(nodes);
    for i := 0 to High(nodes) do
    begin
      frag := Fragment(Range(nodes[i].A, nodes[i].B));
      if plain and (TyRtfParaExtraKind(frag, param) = pekPn) then Continue;
      Result.Extra.Add(frag);
    end;
    if slExtra then
    begin
      Result.Extra.Add(Fragment(SlTok));
      if SlMultTok.Start >= 0 then Result.Extra.Add(Fragment(SlMultTok));
    end;
  end;
end;

function TTyRtfParser.ParaFormatId: TTyParaFormatId;
begin
  if not FParaValid then
  begin
    FParaId := FPool.InternPara(BuildParaFormat);
    FParaValid := True;
  end;
  Result := FParaId;
end;

function TTyRtfParser.DefaultCharFormat: TTyCharFormat;
var
  i: Integer;
begin
  Result := TyDefaultCharFormat;
  Result.SizeHalfPt := DefaultSize;
  i := FontOfNum(-1);
  if i >= 0 then
  begin
    Result.FontName := AsString(FFonts[i].Name);
    if FFonts[i].Charset >= 0 then Result.Charset := FFonts[i].Charset;
  end;
end;

// ---- results ----

function TTyRtfParser.TextBytes: TBytes;
var
  n: PtrInt;
begin
  // every paragraph was written with a separator after it; the last one has none
  n := FOutLen - Length(FSep);
  if n < 0 then n := 0;
  Result := Copy(FOut, 0, n);
end;

function TTyRtfParser.ParaText(AIndex: Integer): RawByteString;
var
  r: ^TTyRtfParaRec;
begin
  r := @FParas[AIndex - FParaBase];
  Result := '';
  SetLength(Result, r^.TextLen);
  if r^.TextLen > 0 then Move(FOut[r^.TextStart], Result[1], r^.TextLen);
end;

function TTyRtfParser.ParaCount: Integer;
begin
  Result := FParaBase + FParaN;
end;

function TTyRtfParser.ParaRec(AIndex: Integer): TTyRtfParaRec;
begin
  Result := FParas[AIndex - FParaBase];
end;

procedure TTyRtfParser.ParaSpan(AIndex: Integer; out ASrc: TTyRtfRange; out AChars: Int64);
begin
  ASrc := FParas[AIndex - FParaBase].Src;
  AChars := FParas[AIndex - FParaBase].Chars;
end;

procedure TTyRtfParser.DropParas(AIndex: Integer);
var
  n, i: Integer;
begin
  n := AIndex - FParaBase;
  if n > FParaN - 1 then n := FParaN - 1;
  if n <= 0 then Exit;
  for i := 0 to FParaN - n - 1 do FParas[i] := FParas[i + n];
  // counting has no runs to let go of; the slots are filled again in place
  if not Counting then
    for i := FParaN - n to FParaN - 1 do FParas[i] := Default(TTyRtfParaRec);
  Dec(FParaN, n);
  Inc(FParaBase, n);
end;

function TTyRtfParser.TableCount: Integer;
begin
  Result := FTableN;
end;

function TTyRtfParser.TableRec(AIndex: Integer): TTyRtfTableRec;
begin
  Result := FTables[AIndex];
end;

function TTyRtfParser.TableExtentCount: Integer;
begin
  Result := FExtentN;
end;

function TTyRtfParser.TableExtent(AIndex: Integer): TTyRtfTableExtent;
begin
  Result := FExtents[AIndex];
end;

function TTyRtfParser.HeaderEnd: PtrInt;
begin
  Result := FS.HeaderEnd;
end;

function TTyRtfParser.TrailerStart: PtrInt;
begin
  Result := FTrailerStart;
end;

function TTyRtfParser.BodyStarted: Boolean;
begin
  Result := FS.BodyStarted;
end;

function TTyRtfParser.Finished: Boolean;
begin
  Result := FFinished;
end;

function TTyRtfParser.Position: PtrInt;
begin
  Result := FLex.Position;
end;

function TTyRtfParser.SnapshotCount: Integer;
begin
  Result := FSnapshotN;
end;

function TTyRtfParser.Snapshot(AIndex: Integer): TTyRtfState;
begin
  Result := FSnapshots[AIndex];
end;

function TTyRtfParser.TakeSnapshots: TTyRtfStateArray;
begin
  Result := Copy(FSnapshots, 0, FSnapshotN);
  FSnapshots := nil;
  FSnapshotN := 0;
end;

function TTyRtfParser.FragmentOf(const R: TTyRtfRange): RawByteString;
begin
  Result := Fragment(R);
end;

// ---- loading ----

function ReadRtfBytes(AStream: TStream): TBytes;
const
  Signature: array[0..4] of Char = '{\rtf';
var
  n: Int64;
begin
  n := AStream.Size - AStream.Position;
  Result := nil;
  if n > 0 then
  begin
    SetLength(Result, n);
    AStream.ReadBuffer(Result[0], n);
  end;
  if (n < 5) or not CompareMem(@Result[0], @Signature[0], 5) then
    raise ETyRichRtf.Create('This is no RTF: it does not start with {\rtf');
end;

// ---- parsing on demand ----

type
  // The text storage's way to the load: decodes a paragraph from the parse of its interval.
  TRtfProvider = class(TTyRichTextProvider)
  public
    Load: TTyRtfLoad;
    function DecodeParagraph(ASrcOffset, ASrcBytes, ACharCount: Int64): UTF8String; override;
  end;

  // The document's way to the load, which it owns through this.
  TRtfLoader = class(TTyRichParaLoader)
  public
    Load: TTyRtfLoad;
    destructor Destroy; override;
    procedure LoadParagraph(ADoc: TTyRichDocument; AIndex: Integer); override;
    procedure ParagraphRead(ADoc: TTyRichDocument; AIndex: Integer); override;
    procedure ReadsEnded(ADoc: TTyRichDocument); override;
  end;

  TRtfBuild = class(TTyRichDocBuilder)
  end;

const
  StateNew = 0;          // a group's paragraph: not set in the document yet
  StateOurs = 1;         // set by the load, its value held
  StateSkipped = 2;      // not set by the load (edited before, or not in the text)
  IndexChunk = 1 shl 20; // the scan hands its paragraphs over at least this often

function TRtfProvider.DecodeParagraph(ASrcOffset, ASrcBytes, ACharCount: Int64): UTF8String;
begin
  Result := Load.Decode(ASrcOffset, ASrcBytes, ACharCount);
end;

destructor TRtfLoader.Destroy;
begin
  Load.Free;
  inherited Destroy;
end;

procedure TRtfLoader.LoadParagraph(ADoc: TTyRichDocument; AIndex: Integer);
begin
  Load.LoadParagraph(AIndex);
end;

procedure TRtfLoader.ParagraphRead(ADoc: TTyRichDocument; AIndex: Integer);
begin
  Load.Used(AIndex);
end;

procedure TRtfLoader.ReadsEnded(ADoc: TTyRichDocument);
begin
  // what the scope kept parsed past the limit can go now
  Load.Trim;
end;

function TyRichRtfLoadOf(ADoc: TTyRichDocument): TTyRtfLoad;
begin
  if (ADoc <> nil) and (ADoc.Loader is TRtfLoader) then
    Result := TRtfLoader(ADoc.Loader).Load
  else
    Result := nil;
end;

// ---- TTyRtfGroup ----

function TTyRtfGroup.Find(ASrc: Int64): Integer;
var
  lo, hi, mid: Integer;
begin
  lo := 0;
  hi := High(Recs);
  while lo <= hi do
  begin
    mid := (lo + hi) div 2;
    if Recs[mid].Src.Start = ASrc then Exit(mid);
    if Recs[mid].Src.Start < ASrc then lo := mid + 1 else hi := mid - 1;
  end;
  Result := -1;
end;

function TTyRtfGroup.HasValues: Boolean;
var
  i: Integer;
begin
  for i := 0 to High(States) do
    if States[i] = StateOurs then Exit(True);
  Result := False;
end;

// ---- TTyRtfLoad ----

constructor TTyRtfLoad.Create(ADoc: TTyRichDocument; const ABytes: TBytes);
begin
  inherited Create;
  FDoc := ADoc;
  FBytes := ABytes;
  FScan := TTyRtfParser.Create(ABytes, nil);
  FScan.SnapshotEvery := CRtfSnapshotBytes;
  FGroups := TFPList.Create;
  FMaxResident := CRtfResidentIntervals;
  FTrailer := Range(-1, -1);
  FSep := TyRichPlatformLineBreak;
  // interval 0 is read from the start of the file: it reads the header's tables itself
  SetLength(FIntervalPos, 16);
  SetLength(FIntervalPara, 16);
  SetLength(FSnaps, 16);
  FIntervalPos[0] := 0;
  FIntervalPara[0] := 0;
  FIntervalN := 1;
end;

destructor TTyRtfLoad.Destroy;
var
  i: Integer;
begin
  // the document's values are gone or going (it owns this through its loader): only what
  // the groups hold besides them is let go of
  for i := 0 to FGroups.Count - 1 do FreeGroup(TTyRtfGroup(FGroups[i]));
  FGroups.Free;
  FWalk.Free;
  FScan.Free;
  inherited Destroy;
end;

procedure TTyRtfLoad.FreeGroup(AGroup: TTyRtfGroup);
var
  i: Integer;
begin
  for i := 0 to High(AGroup.Tables) do
    if AGroup.Tables[i] <> nil then AGroup.Tables[i].Release;
  if AGroup.Objects <> nil then
  begin
    for i := 0 to AGroup.Objects.Count - 1 do TTyRichObject(AGroup.Objects[i]).Release;
    AGroup.Objects.Free;
  end;
  AGroup.Free;
end;

function TTyRtfLoad.Header: TTyRtfRange;
begin
  Result := Range(0, FHeaderEnd);
end;

function TTyRtfLoad.BytesIndexed: Int64;
begin
  if FDone then Result := Length(FBytes) else Result := FScan.Position;
end;

function TTyRtfLoad.BytesTotal: Int64;
begin
  Result := Length(FBytes);
end;

function TTyRtfLoad.SnapshotCount: Integer;
begin
  Result := FIntervalN - 1;
end;

function TTyRtfLoad.IntervalCount: Integer;
begin
  Result := FIntervalN;
end;

function TTyRtfLoad.IntervalStart(AIndex: Integer): Int64;
begin
  Result := FIntervalPos[AIndex];
end;

function TTyRtfLoad.IntervalFirstPara(AIndex: Integer): Integer;
begin
  Result := FIntervalPara[AIndex];
end;

// ---- indexing ----

// Takes what the scan found since the last time: snapshots, and the paragraphs that can go
// into the text (all but the last one that ended, whose range may still grow - unless the
// file is done).
procedure TTyRtfLoad.Collect;
var
  snaps: TTyRtfStateArray;
  i, upto: Integer;
begin
  snaps := FScan.TakeSnapshots;
  for i := 0 to High(snaps) do
  begin
    if FIntervalN >= Length(FSnaps) then
    begin
      SetLength(FIntervalPos, FIntervalN * 2 + 16);
      SetLength(FIntervalPara, FIntervalN * 2 + 16);
      SetLength(FSnaps, FIntervalN * 2 + 16);
    end;
    FSnaps[FIntervalN] := snaps[i];
    FIntervalPos[FIntervalN] := snaps[i].Core.Pos;
    FIntervalPara[FIntervalN] := snaps[i].Core.Paras;
    Inc(FSnapBytes, snaps[i].MemSize);
    Inc(FIntervalN);
  end;
  upto := FScan.ParaCount;
  if not FScan.Finished then Dec(upto);
  if upto > FAppended then Append(FAppended, upto);
  FScan.DropParas(upto);
end;

// Puts paragraphs AFrom..ATo-1 of the scan into the document's text after the ones there
// (the last of them without a separator).
procedure TTyRtfLoad.Append(AFrom, ATo: Integer);
var
  text: TTyRichText;
  i, oldParas: Integer;
  oldLen, chars: Int64;
  src: TTyRtfRange;
  sep: TTyRichSeparator;
  c: TTyRichChange;
begin
  text := FDoc.Text;
  oldLen := text.Length;
  oldParas := text.ParaCount;
  text.ReopenLazyLoad(FSep);
  try
    for i := AFrom to ATo - 1 do
    begin
      FScan.ParaSpan(i, src, chars);
      if i < ATo - 1 then sep := FSep else sep := rsNone;
      text.AppendLazyParagraph(chars, src.Start, src.Stop - src.Start, sep);
      if FMap <> nil then AddMapRange(src);
    end;
  finally
    text.EndLazyLoad;
  end;
  FAppended := ATo;
  if FQuiet then Exit;
  // the last paragraph got its separator and the new ones follow it
  c := Default(TTyRichChange);
  c.Kinds := [rckText, rckStructure];
  c.Pos := oldLen;
  c.OldLen := 0;
  c.NewLen := text.Length - oldLen;
  c.FirstPara := oldParas - 1;
  c.OldParaCount := 1;
  c.NewParaCount := text.ParaCount - oldParas + 1;
  TRtfBuild.ReportLoad(FDoc, c);
end;

procedure TTyRtfLoad.AddMapRange(const R: TTyRtfRange);
var
  n: Integer;
begin
  n := Length(FMap.Paras);
  if FMapN = n then SetLength(FMap.Paras, n * 2 + 64);
  FMap.Paras[FMapN] := R;
  Inc(FMapN);
end;

// Scans about ABudget bytes (and on until AMinParas paragraphs have ended), handing what it
// finds over every IndexChunk bytes.
procedure TTyRtfLoad.Index(ABudget: Int64; AMinParas: Integer);
var
  stop, chunk: Int64;
  ended: Boolean;
begin
  if ABudget < 1 then ABudget := 1;
  if ABudget > High(Int64) - FScan.Position then stop := High(Int64)
  else stop := FScan.Position + ABudget;
  repeat
    chunk := FScan.Position + IndexChunk;
    if chunk > stop then chunk := stop;
    ended := FScan.ParseUntil(chunk, -1);
    if ended then Break;
    if FAppended > 0 then Collect;
  until (FScan.Position >= stop) and (FScan.ParaCount >= AMinParas);
  if ended then Finish else Collect;
end;

procedure TTyRtfLoad.Finish;
begin
  Collect;
  FDone := True;
  FHeaderEnd := FScan.HeaderEnd;
  FTrailer := Range(FScan.TrailerStart, Length(FBytes));
  TRtfBuild.SetLoadState(FDoc, False, False);
end;

function TTyRtfLoad.Step(AByteBudget: Int64): Boolean;
begin
  if not (FDone or FCancelled) then
  begin
    Index(AByteBudget, 0);
    if Assigned(FOnLoadProgress) then FOnLoadProgress(Self, BytesIndexed, BytesTotal);
  end;
  Result := FDone;
end;

procedure TTyRtfLoad.Cancel;
var
  c: TTyRichChange;
begin
  if FDone or FCancelled then Exit;
  FCancelled := True;
  // the last paragraph that ended is as long as it gets now
  if FScan.ParaCount > FAppended then Append(FAppended, FScan.ParaCount);
  FHeaderEnd := FScan.HeaderEnd;
  TRtfBuild.SetLoadState(FDoc, False, True);
  if FQuiet then Exit;
  // nothing more comes: a view that waits for the end can stop waiting
  c := Default(TTyRichChange);
  c.Kinds := [rckStructure];
  c.FirstPara := FDoc.Text.ParaCount - 1;
  c.OldParaCount := 1;
  c.NewParaCount := 1;
  c.Pos := FDoc.Text.Length;
  TRtfBuild.ReportLoad(FDoc, c);
end;

// ---- parsing on demand ----

// The interval whose bytes hold ASrc: the last one starting at or before it.
function TTyRtfLoad.IntervalOf(ASrc: Int64): Integer;
var
  lo, hi, mid: Integer;
begin
  lo := 0;
  hi := FIntervalN - 1;
  while lo < hi do
  begin
    mid := (lo + hi + 1) div 2;
    if FIntervalPos[mid] <= ASrc then lo := mid else hi := mid - 1;
  end;
  Result := lo;
end;

function TTyRtfLoad.IntervalOfPara(APara: Integer): Integer;
var
  lo, hi, mid: Integer;
begin
  lo := 0;
  hi := FIntervalN - 1;
  while lo < hi do
  begin
    mid := (lo + hi + 1) div 2;
    if FIntervalPara[mid] <= APara then lo := mid else hi := mid - 1;
  end;
  Result := lo;
end;

// Paragraphs before the end of interval AIndex (the last: all that the scan has ended).
function TTyRtfLoad.IntervalParaStop(AIndex: Integer): Integer;
begin
  if AIndex + 1 < FIntervalN then Result := FIntervalPara[AIndex + 1]
  else Result := FScan.ParaCount;
end;

// The table is parsed in parts, interval by interval: one too long to parse as a whole for
// a single read, and one still open where the scan stands - how long it gets is not known,
// what is parsed of it now is a part of it in any case, and a read while the file loads
// must stay small.
function TTyRtfLoad.IsBig(const X: TTyRtfTableExtent): Boolean;
begin
  Result := (X.LastPara < 0) or (X.Stop - X.Start > CRtfBigTableBytes);
end;

// The last table to start at or before paragraph APara, -1 none.
function TTyRtfLoad.ExtentAt(APara: Integer): Integer;
var
  lo, hi, mid: Integer;
begin
  lo := 0;
  hi := FScan.TableExtentCount - 1;
  Result := -1;
  while lo <= hi do
  begin
    mid := (lo + hi) div 2;
    if FScan.TableExtent(mid).FirstPara <= APara then
    begin
      Result := mid;
      lo := mid + 1;
    end
    else
      hi := mid - 1;
  end;
end;

// The parsed group that has the interval ASrc lies in. By interval, not by bytes: a group
// parsed while its interval was the last one indexed would answer for every byte after it.
function TTyRtfLoad.GroupOf(ASrc: Int64): TTyRtfGroup;
var
  i, k: Integer;
begin
  k := IntervalOf(ASrc);
  for i := FGroups.Count - 1 downto 0 do
  begin
    Result := TTyRtfGroup(FGroups[i]);
    if (k >= Result.FirstSnap) and (k <= Result.LastSnap) then Exit;
  end;
  Result := nil;
end;

// The intervals around AInterval that share a table with it, directly or through the
// tables between: AFirst .. ALast, never outside ALo .. AHi (a table that reaches further is
// cut there). False as soon as they number more than AMax. A big table links nothing.
function TTyRtfLoad.Linked(AInterval, ALo, AHi, AMax: Integer; out AFirst, ALast: Integer): Boolean;
var
  i, k, firstPara, lastPara: Integer;
  x: TTyRtfTableExtent;
  changed, big: Boolean;
begin
  AFirst := AInterval;
  ALast := AInterval;
  repeat
    changed := False;
    firstPara := FIntervalPara[AFirst];
    lastPara := IntervalParaStop(ALast) - 1;
    // tables follow each other: the ones in these paragraphs are the last one starting in
    // them and those before it, back to the first that ends before them
    i := ExtentAt(lastPara);
    while (i >= 0) and not changed do
    begin
      x := FScan.TableExtent(i);
      // (asked of the extent as the scan gave it: an open one has no last paragraph yet)
      big := IsBig(x);
      if x.LastPara < 0 then x.LastPara := FScan.ParaCount - 1;
      if x.LastPara < firstPara then Break;
      if not big then
      begin
        if x.FirstPara < firstPara then
        begin
          k := IntervalOfPara(x.FirstPara);
          if k < ALo then k := ALo;
          if k < AFirst then
          begin
            AFirst := k;
            changed := True;
          end;
        end;
        if x.LastPara > lastPara then
        begin
          k := IntervalOfPara(x.LastPara);
          if k > AHi then k := AHi;
          if k > ALast then
          begin
            ALast := k;
            changed := True;
          end;
        end;
      end;
      Dec(i);
    end;
    if ALast - AFirst + 1 > AMax then Exit(False);
  until not changed;
  Result := True;
end;

// Parses the intervals around AInterval that must be parsed together: a table is parsed
// from its first paragraph to its last, so that it is one table - unless it is big, or its
// intervals and the ones linked to them through other tables are more than
// CRtfGroupIntervals. Then the block of CRtfGroupIntervals intervals AInterval lies in is
// the limit (blocks are counted from the first interval, so the same intervals are parsed
// together whichever of them is asked for), and a table that crosses a block's end is cut
// there.
function TTyRtfLoad.ParseGroup(AInterval: Integer): TTyRtfGroup;
var
  s, e, lo, hi, i: Integer;
  p: TTyRtfParser;
  start: PtrInt;
begin
  if not Linked(AInterval, 0, FIntervalN - 1, CRtfGroupIntervals, s, e) then
  begin
    lo := AInterval - AInterval mod CRtfGroupIntervals;
    hi := lo + CRtfGroupIntervals - 1;
    if hi > FIntervalN - 1 then hi := FIntervalN - 1;
    Linked(AInterval, lo, hi, MaxInt, s, e);
  end;
  // one group per interval: what overlaps this one goes (it was parsed while the file was
  // still being indexed, or before a table it shares was known in full)
  for i := FGroups.Count - 1 downto 0 do
    with TTyRtfGroup(FGroups[i]) do
      if (FirstSnap <= e) and (LastSnap >= s) then Drop(TTyRtfGroup(FGroups[i]), True);
  p := TTyRtfParser.Create(FBytes, FDoc.Formats);
  try
    if s > 0 then
    begin
      p.CopyTablesFrom(FScan.TablesOf(FSnaps[s].TablesGen));
      p.Resume(FSnaps[s]);
    end;
    start := p.Position;
    p.ParseUntil(High(PtrInt), IntervalParaStop(e));
    Inc(FParsedBytes, p.Position - start);
    Inc(FParseCount);
    Result := GroupFrom(p, s, e);
  finally
    p.Free;
  end;
  FGroups.Add(Result);
  Inc(FResident, e - s + 1);
  Touch(Result);
end;

// What a parser read of intervals AFirst .. ALast, as a group: its paragraphs, their texts,
// its objects and its tables.
function TTyRtfLoad.GroupFrom(AParser: TTyRtfParser; AFirst, ALast: Integer): TTyRtfGroup;
var
  i, j, k, n, lastPara: Integer;
  x: TTyRtfTableExtent;
  tr: TTyRtfTableRec;
  t: TTyRichTable;
  global: Int64;
begin
  lastPara := IntervalParaStop(ALast) - 1;
  Result := TTyRtfGroup.Create;
  Result.FirstSnap := AFirst;
  Result.LastSnap := ALast;
  // from the first paragraph after snapshot AFirst to the last before snapshot ALast + 1
  // (the last interval: to the last paragraph the scan has ended)
  n := AParser.ParaCount;
  SetLength(Result.Recs, n);
  SetLength(Result.Texts, n);
  SetLength(Result.Values, n);
  SetLength(Result.States, n);
  for i := 0 to n - 1 do
  begin
    Result.Recs[i] := AParser.ParaRec(i);
    Result.Texts[i] := AParser.ParaText(i);
  end;
  Result.Objects := AParser.TakeObjects;
  // the tables; one that reaches outside these intervals (a big one, one cut at a block's
  // end), or is still open at the end of what is indexed, is only a part of its table: it
  // cannot grow
  SetLength(Result.Tables, AParser.TableCount);
  for i := 0 to AParser.TableCount - 1 do
  begin
    tr := AParser.TableRec(i);
    j := -1;
    for k := 0 to n - 1 do
      if Result.Recs[k].Table = i then
      begin
        j := k;
        Break;
      end;
    if j >= 0 then
    begin
      global := FIntervalPara[AFirst] + j;
      k := ExtentAt(global);
      if k >= 0 then
      begin
        x := FScan.TableExtent(k);
        if (x.LastPara < 0) or ((x.LastPara >= global) and
           ((x.FirstPara < FIntervalPara[AFirst]) or (x.LastPara > lastPara))) then
          tr.Locked := True;
      end;
    end;
    if tr.RowCount > 0 then t := TTyRichTable.Create(tr.Rows[0].Cellx, tr.Locked)
    else t := TTyRichTable.Create([], tr.Locked);
    t.AddRef;
    Result.Tables[i] := t;
    for j := 0 to tr.RowCount - 1 do
      t.AddRow(tr.Rows[j].CellCount, AParser.FragmentOf(tr.Rows[j].Raw), tr.Rows[j].Cellx,
        tr.Rows[j].Nested);
  end;
end;

procedure TTyRtfLoad.CheckWhole(AIndex: Integer; AData: Pointer; ASrcOffset, ASrcBytes: Int64;
  var AContinue: Boolean);
begin
  if (AIndex > High(FCheck.Recs)) or (FCheck.Recs[AIndex].Src.Start <> ASrcOffset) or
     (FCheck.Recs[AIndex].Src.Stop - FCheck.Recs[AIndex].Src.Start <> ASrcBytes) then
  begin
    FCheckBad := AIndex;
    AContinue := False;
  end;
end;

// The whole file parsed in one go, from its first byte: every paragraph gets its formats
// from that one parse, and its text when it is read. The index (the scan that found the
// paragraphs' bytes) and this parse are two readings of the file by the same rules; they
// must find the same paragraphs, and are compared. The one group this makes holds every
// interval and is the only one, so it is never the least recently used: it stays.
procedure TTyRtfLoad.ParseWhole;
var
  p: TTyRtfParser;
  g: TTyRtfGroup;
  i, n: Integer;
begin
  for i := FGroups.Count - 1 downto 0 do Drop(TTyRtfGroup(FGroups[i]), True);
  p := TTyRtfParser.Create(FBytes, FDoc.Formats);
  try
    p.Parse;
    Inc(FParsedBytes, p.Position);
    Inc(FParseCount);
    n := p.ParaCount;
    if (n <> FDoc.Text.ParaCount) or (p.HeaderEnd <> FHeaderEnd) or
       (p.TrailerStart <> FTrailer.Start) then
      raise ETyRichRtf.CreateFmt('RTF reader: the whole parse found %d paragraphs in bytes ' +
        '%d to %d, the index %d in bytes %d to %d', [n, Int64(p.HeaderEnd), Int64(p.TrailerStart),
        FDoc.Text.ParaCount, FHeaderEnd, FTrailer.Start]);
    g := GroupFrom(p, 0, FIntervalN - 1);
    // the defaults as this parse read them
    TRtfBuild.SetDefaultCharFormat(FDoc, p.DefaultCharFormat);
    TRtfBuild.SetPage(FDoc, p.PaperWidth, p.PaperHeight, p.MarginLeft, p.MarginRight);
  finally
    p.Free;
  end;
  FGroups.Add(g);
  Inc(FResident, FIntervalN);
  Touch(g);
  FCheck := g;
  FCheckBad := -1;
  FDoc.Text.WalkParas(0, @CheckWhole);
  FCheck := nil;
  if FCheckBad >= 0 then
  begin
    i := FCheckBad;
    Drop(g, True);
    raise ETyRichRtf.CreateFmt('RTF reader: the whole parse and the index do not agree ' +
      'on the bytes of paragraph %d', [i]);
  end;
  FWhole := True;
  Apply(g);
end;

procedure TTyRtfLoad.Touch(AGroup: TTyRtfGroup);
begin
  Inc(FStamp);
  AGroup.Stamp := FStamp;
  if FGroups[FGroups.Count - 1] <> Pointer(AGroup) then
  begin
    FGroups.Remove(AGroup);
    FGroups.Add(AGroup);
  end;
end;

// A read found paragraph AIndex parsed: its group is the one used last. Reads come in runs
// over neighbouring paragraphs, so the group of the read before and the paragraphs that are
// its own are remembered - good while the text has as many paragraphs and characters as it
// had then (an edit that moves paragraphs changes one or the other; a wrong guess would
// only make another interval go first).
procedure TTyRtfLoad.Used(AIndex: Integer);
var
  text: TTyRichText;
  src, nbytes: Int64;
  g: TTyRtfGroup;
  i: Integer;
begin
  text := FDoc.Text;
  if (FUsedGroup <> nil) and (AIndex >= FUsedFirst) and (AIndex < FUsedStop) and
     (text.ParaCount = FUsedParas) and (text.Length = FUsedLength) then
  begin
    if FGroups[FGroups.Count - 1] <> Pointer(FUsedGroup) then Touch(FUsedGroup);
    Exit;
  end;
  if not text.ParaLazySource(AIndex, src, nbytes) then Exit;
  g := GroupOf(src);
  if g = nil then Exit;
  i := g.Find(src);
  if i < 0 then Exit;
  Touch(g);
  FUsedGroup := g;
  FUsedFirst := AIndex - i;
  FUsedStop := FUsedFirst + Length(g.Recs);
  FUsedParas := text.ParaCount;
  FUsedLength := text.Length;
end;

// The record of the paragraph at ASrc; False: none, and AIndex is where it would go.
function TTyRtfLoad.KeptAt(ASrc: Int64; out AIndex: Integer): Boolean;
var
  lo, hi, mid: Integer;
begin
  lo := 0;
  hi := FKeptN - 1;
  while lo <= hi do
  begin
    mid := (lo + hi) div 2;
    if FKept[mid].Src = ASrc then
    begin
      AIndex := mid;
      Exit(True);
    end;
    if FKept[mid].Src < ASrc then lo := mid + 1 else hi := mid - 1;
  end;
  AIndex := lo;
  Result := False;
end;

// Records that the paragraph at ASrc keeps AValue though its group goes. The group's hold
// on the value becomes the record's.
procedure TTyRtfLoad.KeepValue(ASrc: Int64; AValue: Pointer);
var
  k: Integer;
begin
  if KeptAt(ASrc, k) then
  begin
    // an older record: that value is no longer the paragraph's
    TRtfBuild.ReleaseValue(FDoc, FKept[k].Value);
    FKept[k].Value := AValue;
    Exit;
  end;
  if FKeptN = Length(FKept) then SetLength(FKept, FKeptN * 2 + 16);
  if k < FKeptN then Move(FKept[k], FKept[k + 1], (FKeptN - k) * SizeOf(TTyRtfKept));
  FKept[k].Src := ASrc;
  FKept[k].Value := AValue;
  Inc(FKeptN);
end;

// Takes record AIndex out (its hold is the caller's now).
procedure TTyRtfLoad.Unkeep(AIndex: Integer);
begin
  Dec(FKeptN);
  if AIndex < FKeptN then
    Move(FKept[AIndex + 1], FKept[AIndex], (FKeptN - AIndex) * SizeOf(TTyRtfKept));
end;

// The group that has paragraph ASrc, parsed if need be.
function TTyRtfLoad.GroupFor(ASrc: Int64; out AIndex: Integer): TTyRtfGroup;
begin
  Result := GroupOf(ASrc);
  if Result <> nil then
  begin
    AIndex := Result.Find(ASrc);
    if AIndex >= 0 then Exit;
  end;
  // not parsed, or parsed before the scan reached this paragraph
  Result := ParseGroup(IntervalOf(ASrc));
  AIndex := Result.Find(ASrc);
end;

// Sets the formats of the group's paragraphs that are still unparsed (found through their
// source in the text: an edit before them moves them, an undo may bring them back).
procedure TTyRtfLoad.Apply(AGroup: TTyRtfGroup);
var
  i, j, k: Integer;
  rec: ^TTyRtfParaRec;
  cell: TTyRichCell;
  t: TTyRichTable;
  v: Pointer;
begin
  for i := 0 to High(AGroup.Recs) do
  begin
    if AGroup.States[i] <> StateNew then Continue;
    rec := @AGroup.Recs[i];
    j := FDoc.Text.ParaOfLazySource(rec^.Src.Start);
    if j < 0 then Continue;
    cell := nil;
    if (rec^.Table >= 0) and (rec^.Table <= High(AGroup.Tables)) then
    begin
      t := AGroup.Tables[rec^.Table];
      if (rec^.Row < t.RowCount) and (rec^.Cell < t.Rows[rec^.Row].CellCount) then
        cell := t.Rows[rec^.Row].Cells[rec^.Cell];
    end;
    if TRtfBuild.SetParagraph(FDoc, j, rec^.Format, rec^.Runs, cell) then
    begin
      v := TRtfBuild.ParagraphValue(FDoc, j);
      TRtfBuild.HoldValue(FDoc, v);
      AGroup.Values[i] := v;
      AGroup.States[i] := StateOurs;
    end
    else if KeptAt(rec^.Src.Start, k) then
    begin
      // set already, by this load: the group that set it went and it stayed. While it has
      // that value it is this group's again (the record's hold comes with it)
      if FKept[k].Value = TRtfBuild.ParagraphValue(FDoc, j) then
      begin
        AGroup.Values[i] := FKept[k].Value;
        AGroup.States[i] := StateOurs;
      end
      else
      begin
        TRtfBuild.ReleaseValue(FDoc, FKept[k].Value);
        AGroup.States[i] := StateSkipped;
      end;
      Unkeep(k);
    end
    else
      AGroup.States[i] := StateSkipped;
  end;
end;

// Lets the group go. AReset: its paragraphs that are still as it set them go back to
// unparsed (only while the document is not busy - values read before may be in use); a
// table whose paragraphs are not all still ours stays as it is (it is one object for all of
// them). A paragraph that keeps the value the group gave it is recorded (KeepValue): it is still
// the file's own.
procedure TTyRtfLoad.Drop(AGroup: TTyRtfGroup; AReset: Boolean);
var
  i, j: Integer;
  keep: array of Boolean;
  idx: array of Integer;
  text: TTyRichText;
begin
  text := FDoc.Text;
  if AReset and TRtfBuild.DocumentBusy(FDoc) then AReset := False;
  keep := nil;
  SetLength(keep, Length(AGroup.Tables));
  idx := nil;
  SetLength(idx, Length(AGroup.Recs));
  for i := 0 to High(AGroup.Recs) do
  begin
    idx[i] := -1;
    if AGroup.States[i] <> StateOurs then
    begin
      // not set by this group: changed before it was parsed (its text - then it is not
      // found by its source and was never asked about - or its formats)
      if AGroup.Recs[i].Table >= 0 then keep[AGroup.Recs[i].Table] := True;
      Continue;
    end;
    if AReset then
    begin
      j := text.ParaOfLazySource(AGroup.Recs[i].Src.Start);
      if (j >= 0) and (TRtfBuild.ParagraphValue(FDoc, j) = AGroup.Values[i]) then
        idx[i] := j
      else if AGroup.Recs[i].Table >= 0 then
        keep[AGroup.Recs[i].Table] := True;
    end;
  end;
  for i := 0 to High(AGroup.Recs) do
  begin
    if AGroup.States[i] = StateOurs then
    begin
      if not AReset then
        // nothing was looked at: it may well still be the paragraph's value
        KeepValue(AGroup.Recs[i].Src.Start, AGroup.Values[i])
      else if idx[i] < 0 then
        // the paragraph has another value by now, or is gone
        TRtfBuild.ReleaseValue(FDoc, AGroup.Values[i])
      else if (AGroup.Recs[i].Table >= 0) and keep[AGroup.Recs[i].Table] then
        KeepValue(AGroup.Recs[i].Src.Start, AGroup.Values[i])
      else
      begin
        TRtfBuild.UnsetParagraph(FDoc, idx[i], AGroup.Values[i]);
        TRtfBuild.ReleaseValue(FDoc, AGroup.Values[i]);
      end;
    end;
    text.ForgetDecoded(AGroup.Recs[i].Src.Start);
  end;
  if FUsedGroup = AGroup then FUsedGroup := nil;
  FGroups.Remove(AGroup);
  Dec(FResident, AGroup.LastSnap - AGroup.FirstSnap + 1);
  FreeGroup(AGroup);
end;

procedure TTyRtfLoad.Trim;
var
  g: TTyRtfGroup;
begin
  if TRtfBuild.DocumentBusy(FDoc) then Exit;
  // the most recently used group always stays
  while (FResident > FMaxResident) and (FGroups.Count > 1) do
  begin
    g := TTyRtfGroup(FGroups[0]);
    Drop(g, True);
  end;
end;

function TTyRtfLoad.Decode(ASrcOffset, ASrcBytes, ACharCount: Int64): UTF8String;
var
  g: TTyRtfGroup;
  i, k: Integer;
begin
  g := GroupFor(ASrcOffset, i);
  if i < 0 then
    raise ETyRichRtf.CreateFmt('RTF reader: no paragraph starts at byte %d', [ASrcOffset]);
  Result := g.Texts[i];
  Touch(g);
  // reading text alone (no formats asked) must not keep every interval: groups nothing was
  // set from can go at any time, slots are not touched
  if FResident div 2 > FMaxResident then
  begin
    k := 0;
    while (FResident > FMaxResident) and (k < FGroups.Count - 1) do
    begin
      if not TTyRtfGroup(FGroups[k]).HasValues then
        Drop(TTyRtfGroup(FGroups[k]), False)
      else
        Inc(k);
    end;
  end;
end;

procedure TTyRtfLoad.LoadParagraph(AIndex: Integer);
var
  src, nbytes: Int64;
  g: TTyRtfGroup;
  i: Integer;
begin
  if not FDoc.Text.ParaLazySource(AIndex, src, nbytes) then Exit;
  g := GroupFor(src, i);
  if i < 0 then Exit;
  Apply(g);
  Touch(g);
  Trim;
end;

function TTyRtfLoad.ParaSource(AIndex: Integer; out ARange: TTyRtfRange): Boolean;
var
  src, nbytes: Int64;
  v: Pointer;
begin
  ARange := Range(-1, -1);
  if not FDoc.Text.ParaLazySource(AIndex, src, nbytes) then Exit(False);
  v := TRtfBuild.ParagraphValue(FDoc, AIndex);
  if not OwnsValue(src, v) then Exit(False);
  ARange := Range(src, src + nbytes);
  Result := True;
end;

function TTyRtfLoad.OwnsValue(ASrcOffset: Int64; AValue: Pointer): Boolean;
var
  g: TTyRtfGroup;
  i: Integer;
begin
  if AValue = nil then Exit(True);
  // parsed: untouched while it still has the value this load gave it - which a group
  // knows, or, for a paragraph that stayed set when its group went, the record kept then
  g := GroupOf(ASrcOffset);
  if g <> nil then
  begin
    i := g.Find(ASrcOffset);
    if (i >= 0) and (g.States[i] = StateOurs) and (g.Values[i] = AValue) then Exit(True);
  end;
  Result := KeptAt(ASrcOffset, i) and (FKept[i].Value = AValue);
end;

function TTyRtfLoad.LastParaOpen: Boolean;
begin
  Result := FDone and FScan.LastParaOpen;
end;

function TTyRtfLoad.StateAt(APos: Int64; out AState: TTyRtfState): Boolean;
var
  k: Integer;
begin
  AState := Default(TTyRtfState);
  if (APos < 0) or (APos > Length(FBytes)) then Exit(False);
  k := IntervalOf(APos);
  // the scan kept from the last call goes on when the position is ahead of it and no
  // snapshot is nearer
  if (FWalk = nil) or FWalk.Finished or (FWalk.Position > APos) or
     (FIntervalPos[k] > FWalk.Position) then
  begin
    FreeAndNil(FWalk);
    FWalk := TTyRtfParser.Create(FBytes, nil);
    if k > 0 then
    begin
      FWalk.CopyTablesFrom(FScan.TablesOf(FSnaps[k].TablesGen));
      FWalk.Resume(FSnaps[k]);
    end;
  end;
  if FWalk.Position < APos then FWalk.ParseUntil(APos, -1);
  // (a scan that reached the end of the file has closed every group: not a state to go on from)
  Result := (FWalk.Position = APos) and not FWalk.Finished;
  if Result then AState := FWalk.SaveState;
  // it keeps no record of the paragraphs it went over
  FWalk.DropParas(FWalk.ParaCount);
end;

// ---- the entry points ----

function BeginLoad(ADoc: TTyRichDocument; AStream: TStream; AFirstSlice: Int64;
  AMap: TTyRtfSourceMap): TTyRtfLoad;
var
  bytes: TBytes;
  load: TTyRtfLoad;
  loader: TRtfLoader;
  provider: TRtfProvider;
  text, owned: TTyRichText;
  handler: TTyRichChangeEvent;
  change: TTyRichChange;
  src: TTyRtfRange;
  chars: Int64;
  i, n: Integer;
begin
  bytes := ReadRtfBytes(AStream);
  load := TTyRtfLoad.Create(ADoc, bytes);
  loader := nil;
  text := nil;
  change := Default(TTyRichChange);
  change.Kinds := [rckText, rckFormat, rckStructure];
  change.OldLen := ADoc.Text.Length;
  change.OldParaCount := ADoc.Text.ParaCount;
  // the one change is reported when the document is all set up
  handler := ADoc.OnChange;
  ADoc.OnChange := nil;
  try
    try
      load.FQuiet := True;
      if AMap <> nil then
      begin
        load.FMap := AMap;
        AMap.Paras := nil;
      end;
      // the header and two paragraphs at least: the text starts with one (the last that
      // ended is held back while its range may still grow)
      if AFirstSlice < IndexChunk then load.FScan.ParseUntil(AFirstSlice, -1)
      else load.FScan.ParseUntil(IndexChunk, -1);
      while not load.FScan.Finished and (load.FScan.ParaCount < 2) do
        load.FScan.ParseUntil(load.FScan.Position + IndexChunk, -1);
      provider := TRtfProvider.Create;
      provider.Load := load;
      text := TTyRichText.CreateLazy(provider, True);
      n := load.FScan.ParaCount;
      if not load.FScan.Finished then Dec(n);
      for i := 0 to n - 1 do
      begin
        load.FScan.ParaSpan(i, src, chars);
        if i < n - 1 then
          text.AppendLazyParagraph(chars, src.Start, src.Stop - src.Start, load.FSep)
        else
          text.AppendLazyParagraph(chars, src.Start, src.Stop - src.Start, rsNone);
        if AMap <> nil then load.AddMapRange(src);
      end;
      text.EndLazyLoad;
      load.FAppended := n;
      load.FHeaderEnd := load.FScan.HeaderEnd;
      // the document takes the text over, also when it refuses it (and frees it then)
      owned := text;
      text := nil;
      TRtfBuild.ReplaceText(ADoc, owned);
      loader := TRtfLoader.Create;
      loader.Load := load;
      ADoc.InstallLoader(loader, True);
      TRtfBuild.SetDefaultCharFormat(ADoc, load.FScan.DefaultCharFormat);
      TRtfBuild.SetPage(ADoc, load.FScan.PaperWidth, load.FScan.PaperHeight,
        load.FScan.MarginLeft, load.FScan.MarginRight);
      if load.FScan.Finished then
        load.Finish
      else
      begin
        load.Collect;
        TRtfBuild.SetLoadState(ADoc, True, False);
        // the rest of the first slice
        if AFirstSlice > load.FScan.Position then
          load.Index(AFirstSlice - load.FScan.Position, 0);
      end;
      load.FQuiet := False;
    except
      text.Free;
      if loader = nil then load.Free;
      raise;
    end;
  finally
    ADoc.OnChange := handler;
  end;
  change.NewLen := ADoc.Text.Length;
  change.NewParaCount := ADoc.Text.ParaCount;
  if Assigned(handler) then handler(ADoc, change);
  Result := load;
end;

function TyRichBeginLoadRtf(ADoc: TTyRichDocument; AStream: TStream;
  AFirstSlice: Int64): TTyRtfLoad;
begin
  Result := BeginLoad(ADoc, AStream, AFirstSlice, nil);
end;

// The whole file indexed in one call; AWhole: and parsed (TTyRtfLoad.ParseWhole).
procedure LoadAll(ADoc: TTyRichDocument; AStream: TStream; AMap: TTyRtfSourceMap;
  AWhole: Boolean);
var
  load: TTyRtfLoad;
  handler: TTyRichChangeEvent;
  change: TTyRichChange;
begin
  change := Default(TTyRichChange);
  change.Kinds := [rckText, rckFormat, rckStructure];
  change.OldLen := ADoc.Text.Length;
  change.OldParaCount := ADoc.Text.ParaCount;
  handler := ADoc.OnChange;
  ADoc.OnChange := nil;
  try
    load := BeginLoad(ADoc, AStream, High(Int64) div 2, AMap);
    load.FQuiet := True;
    while not load.Step(High(Int64) div 2) do ;
    if AWhole then load.ParseWhole;
    load.FQuiet := False;
  finally
    ADoc.OnChange := handler;
  end;
  if AMap <> nil then
  begin
    AMap.Bytes := load.FBytes;
    SetLength(AMap.Paras, load.FMapN);
    load.FMap := nil;
    AMap.Header := load.Header;
    AMap.Trailer := load.Trailer;
  end;
  change.NewLen := ADoc.Text.Length;
  change.NewParaCount := ADoc.Text.ParaCount;
  if Assigned(handler) then handler(ADoc, change);
end;

procedure TyRichLoadRtf(ADoc: TTyRichDocument; AStream: TStream; AMap: TTyRtfSourceMap);
begin
  LoadAll(ADoc, AStream, AMap, False);
end;

procedure TyRichLoadRtfFull(ADoc: TTyRichDocument; AStream: TStream; AMap: TTyRtfSourceMap);
begin
  LoadAll(ADoc, AStream, AMap, True);
end;

// ---- for the writer ----

function TyRtfCharsetCodePage(ACharset, AAnsiCodePage: Integer): Integer;
begin
  Result := CharsetCodePage(ACharset);
  if Result = CpSymbol then Exit(0);
  if (Result = 0) or not TyRichCodePageSupported(Result) then Result := AAnsiCodePage;
end;

function TyRtfFragmentIsWord(const AFragment: RawByteString; const AName: string): Boolean;
var
  lex: TTyRtfLexer;
  t: TTyRtfToken;
  p: PByte;
begin
  Result := False;
  if AFragment = '' then Exit;
  p := PByte(PAnsiChar(AFragment));
  lex.Init(p, 0, Length(AFragment));
  if not lex.Next(t) or (t.Kind <> rtkWord) then Exit;
  Result := (t.NameLen = Length(AName)) and NameStarts(p + t.NameStart, t.NameLen, AName);
end;

// By the same tests BodyWord and HandleDestination make when they put a fragment into the
// paragraph's Extra.
function TyRtfParaExtraKind(const AFragment: RawByteString; out AParam: Integer): TTyRtfParaExtraKind;
var
  lex: TTyRtfLexer;
  t: TTyRtfToken;
  p: PByte;
  got: Boolean;
begin
  AParam := 0;
  if AFragment = '' then Exit(pekTop);
  p := PByte(PAnsiChar(AFragment));
  lex.Init(p, 0, Length(AFragment));
  if not lex.Next(t) then Exit(pekTop);
  Result := pekPn;
  if t.Kind = rtkGroupStart then
  begin
    // a group: {\*\oldpprops ...} among the paragraph's words, {\pntxta ...} and
    // {\pntxtb ...} inside {\*\pn}
    got := lex.Next(t);
    while got and (t.Kind = rtkSymbol) and (t.Value = Ord('*')) do got := lex.Next(t);
    if got and (t.Kind = rtkWord) and
       (LookupWord(p + t.NameStart, t.NameLen) = kwDParaExtra) then
      Result := pekTop;
    Exit;
  end;
  if t.Kind <> rtkWord then Exit;
  AParam := t.Param;
  case LookupWord(p + t.NameStart, t.NameLen) of
    kwLs: Result := pekLs;
    kwIlvl: Result := pekIlvl;
    kwParaExtra, kwSl, kwSlMult: Result := pekTop;
    kwUnknown:
      // borders and shading; any other unknown word is the paragraph's only inside {\*\pn}
      if IsParaPrefixWord(p + t.NameStart, t.NameLen) then Result := pekTop;
  end;
end;

type
  // Control words put together as bytes (fragments of the file go in as they are: no string
  // of one code page is ever joined to one of another).
  TWordBuf = record
    Data: TBytes;
    Len: PtrInt;
    procedure Add(const S: string);
    procedure AddWord(const AName: string; AValue: Integer);
    procedure AddBytes(P: PByte; ACount: PtrInt);
  end;

procedure TWordBuf.AddBytes(P: PByte; ACount: PtrInt);
begin
  if ACount <= 0 then Exit;
  if Len + ACount > Length(Data) then SetLength(Data, (Len + ACount) * 2 + 64);
  Move(P^, Data[Len], ACount);
  Inc(Len, ACount);
end;

procedure TWordBuf.Add(const S: string);
begin
  if S <> '' then AddBytes(PByte(PChar(S)), Length(S));
end;

procedure TWordBuf.AddWord(const AName: string; AValue: Integer);
begin
  Add('\' + AName + IntToStr(AValue));
end;

function TyRtfStateWords(const AState: TTyRtfState; const ABytes: TBytes;
  ALevel: Integer; ATable: Boolean): RawByteString;
const
  TabAlignWord: array[TTyTabAlign] of string = ('', '\tqc', '\tqr', '\tqdec');
  TabLeaderWord: array[TTyTabLeader] of string = ('', '\tldot', '\tlhyph', '\tlul', '\tlth',
    '\tleq');
var
  b: TWordBuf;
  p: TTyRtfProps;
  nodes: TTyRtfNodes;
  i, split, param: Integer;
  inPn, pnDone: Boolean;

  // A node list's entries, first to last.
  function ListOf(AList: Integer): TTyRtfNodes;
  var
    n, k: Integer;
  begin
    n := 0;
    k := AList;
    while (k >= 0) and (k <= High(AState.Nodes)) do
    begin
      Inc(n);
      k := AState.Nodes[k].Prev;
    end;
    Result := nil;
    SetLength(Result, n);
    k := AList;
    while n > 0 do
    begin
      Dec(n);
      Result[n] := AState.Nodes[k];
      k := AState.Nodes[k].Prev;
    end;
  end;

  function Fragment(const R: TTyRtfNode): RawByteString;
  begin
    Result := '';
    if (R.A < 0) or (R.B > Length(ABytes)) or (R.B <= R.A) then Exit;
    SetLength(Result, R.B - R.A);
    Move(ABytes[R.A], Result[1], R.B - R.A);
  end;

  procedure Put(AStart, AStop: Int64);
  begin
    if (AStart >= 0) and (AStop <= Length(ABytes)) and (AStop > AStart) then
      b.AddBytes(@ABytes[AStart], AStop - AStart);
  end;

  // What {\*\pn ...} sets apart from the fragments it leaves in Extra.
  procedure PnWords;
  begin
    if p.ListKind = lkBullet then
      b.Add('\pnlvlblt')
    else if p.ListKind <> lkNone then
    begin
      if p.ListLevel > 0 then b.AddWord('pnlvl', p.ListLevel + 1) else b.Add('\pnlvlbody');
      case p.ListKind of
        lkDecimal: b.Add('\pndec');
        lkLowerAlpha: b.Add('\pnlcltr');
        lkUpperAlpha: b.Add('\pnucltr');
        lkLowerRoman: b.Add('\pnlcrm');
        lkUpperRoman: b.Add('\pnucrm');
      end;
    end;
    if p.ListStart <> 0 then b.AddWord('pnstart', p.ListStart);
  end;

begin
  b := Default(TWordBuf);
  if (ALevel >= 0) and (ALevel <= High(AState.Stack)) then p := AState.Stack[ALevel]
  else p := AState.Core.Props;
  b.Add('\pard\plain');
  b.AddWord('uc', p.Uc);
  // the paragraph
  case p.Align of
    paraCenter: b.Add('\qc');
    paraRight: b.Add('\qr');
    paraJustify: b.Add('\qj');
  end;
  if p.FirstIndent <> 0 then b.AddWord('fi', p.FirstIndent);
  if p.LeftIndent <> 0 then b.AddWord('li', p.LeftIndent);
  if p.RightIndent <> 0 then b.AddWord('ri', p.RightIndent);
  if p.SpaceBefore <> 0 then b.AddWord('sb', p.SpaceBefore);
  if p.SpaceAfter <> 0 then b.AddWord('sa', p.SpaceAfter);
  // the line spacing as its own tokens: an unnamed multiple goes into Extra as they are
  Put(p.SlTok.Start, p.SlTok.Stop);
  Put(p.SlMultTok.Start, p.SlMultTok.Stop);
  nodes := ListOf(p.Tabs);
  for i := 0 to High(nodes) do
  begin
    b.Add(TabAlignWord[TTyTabAlign(nodes[i].B and $FF)]);
    b.Add(TabLeaderWord[TTyTabLeader(nodes[i].B shr 8)]);
    b.AddWord('tx', Integer(nodes[i].A));
  end;
  // a kind named for a tab stop that has not come yet
  b.Add(TabAlignWord[p.TabAlign]);
  b.Add(TabLeaderWord[p.TabLeader]);
  if p.RtlPar then b.Add('\rtlpar');
  if ATable then
  begin
    if p.InTable then b.Add('\intbl');
    if p.Itap <> 0 then b.AddWord('itap', p.Itap);
  end;
  // the paragraph's unknown words in their order, those read inside {\*\pn} inside one
  // again (outside it the reader would take them for character words)
  nodes := ListOf(p.ParaExtra);
  inPn := False;
  pnDone := False;
  for i := 0 to High(nodes) do
  begin
    if TyRtfParaExtraKind(Fragment(nodes[i]), param) = pekPn then
    begin
      if not inPn then
      begin
        b.Add('{\*\pn');
        if not pnDone then PnWords;
        pnDone := True;
        inPn := True;
      end;
    end
    else if inPn then
    begin
      b.Add('}');
      inPn := False;
    end;
    Put(nodes[i].A, nodes[i].B);
  end;
  if inPn then b.Add('}');
  if not pnDone and ((p.ListKind <> lkNone) or (p.ListStart <> 0)) then
  begin
    b.Add('{\*\pn');
    PnWords;
    b.Add('}');
  end;
  // the characters. \f first: no slot is named yet, so it sets the font and no slot. Then
  // the unknown words - an \af among them is one only while no slot is named - then the
  // slots (\af: the font stays), and last what names the slot in effect: the slot's own
  // word, or, when \rtlch or \ltrch was the last to name one, the unknown words from the
  // last of those on.
  if p.FontNum >= 0 then b.AddWord('f', p.FontNum);
  nodes := ListOf(p.CharExtra);
  split := Length(nodes);
  if (p.Slot = sloOther) and ((p.LochNum >= 0) or (p.HichNum >= 0) or (p.DbchNum >= 0)) then
    for i := High(nodes) downto 0 do
      if TyRtfFragmentIsWord(Fragment(nodes[i]), 'rtlch') or
         TyRtfFragmentIsWord(Fragment(nodes[i]), 'ltrch') then
      begin
        split := i;
        Break;
      end;
  for i := 0 to split - 1 do Put(nodes[i].A, nodes[i].B);
  if p.LochNum >= 0 then
  begin
    b.Add('\loch');
    b.AddWord('af', p.LochNum);
  end;
  if p.HichNum >= 0 then
  begin
    b.Add('\hich');
    b.AddWord('af', p.HichNum);
  end;
  if p.DbchNum >= 0 then
  begin
    b.Add('\dbch');
    b.AddWord('af', p.DbchNum);
  end;
  if split < Length(nodes) then
    for i := split to High(nodes) do Put(nodes[i].A, nodes[i].B)
  else
    case p.Slot of
      sloLoch: b.Add('\loch');
      sloHich: b.Add('\hich');
      sloDbch: b.Add('\dbch');
    end;
  if p.Bold then b.Add('\b');
  if p.Italic then b.Add('\i');
  if p.Underline then b.Add('\ul');
  if p.Strike then b.Add('\strike');
  case p.VertAlign of
    vaSuper: b.Add('\super');
    vaSub: b.Add('\sub');
  end;
  if p.ColorIdx <> 0 then b.AddWord('cf', p.ColorIdx);
  if p.HighlightIdx <> 0 then b.AddWord('highlight', p.HighlightIdx);
  // (the size last: whatever came before it, the words end with one of the reader's own)
  b.AddWord('fs', p.Size);
  Result := '';
  SetLength(Result, b.Len);
  if b.Len > 0 then Move(b.Data[0], Result[1], b.Len);
end;

initialization
  InitWords;
end.
