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

  // What a group saves and restores. Fragments (Extra) are byte ranges of the file; the arrays
  // are only ever replaced, never written into, so copies of the record can share them.
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
    CharExtra: TTyRtfRanges;
    // paragraph
    Align: TTyParaAlign;
    LeftIndent, RightIndent, FirstIndent, SpaceBefore, SpaceAfter: Integer;
    Sl, SlMult: Integer;
    SlTok, SlMultTok: TTyRtfRange;
    Tabs: TTyTabStops;
    TabAlign: TTyTabAlign;
    TabLeader: TTyTabLeader;
    RtlPar, InTable: Boolean;
    Itap: Integer;
    ListKind: TTyListKind;
    ListLevel, ListStart: Integer;
    Ls, Ilvl: Integer;
    ParaExtra: TTyRtfRanges;
  end;

  TTyRtfRowDef = record
    Cellx: array of Integer;
    Merged: Boolean;
    Raw: TTyRtfRange;
  end;

  // Everything the parse depends on, at any point of the file (with the header's tables).
  TTyRtfState = record
    Pos: PtrInt;                 // the next token
    Props: TTyRtfProps;
    Stack: array of TTyRtfProps;
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
    // A copy that shares nothing the parse writes into.
    function Snapshot: TTyRtfState;
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
  end;

  TTyRtfRowRec = record
    CellCount: Integer;
    Raw: TTyRtfRange;
    Cellx: array of Integer;
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
    FS: TTyRtfState;
    FPool: TTyFormatPool;
    FTok: TTyRtfToken;
    FTokStop: PtrInt;
    FContent, FCommitted: Boolean;
    FFinished: Boolean;
    FTrailerStart: PtrInt;
    // the header's tables
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
    FSep: RawByteString;
    FRuns: TTyRunArray;
    FRunN: Integer;
    FCurChars: Int64;
    FParas: array of TTyRtfParaRec;
    FParaN: Integer;
    FTables: array of TTyRtfTableRec;
    FTableN: Integer;
    FObjects: TFPList;           // every object made, for freeing the ones not used
    FKeepSnapshots: Boolean;
    FSnapshots: array of TTyRtfState;
    function Counting: Boolean; inline;
    procedure InitState;
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
    function BuildParaFormat: TTyParaFormat;
    function ParaFormatId: TTyParaFormatId;
    procedure ResolveList(var AList: TTyListFormat);
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
    // The state, as a snapshot to resume from.
    function SaveState: TTyRtfState;
    // Goes on from AState (taken by a parser over the same bytes); copy the header's tables
    // first with CopyTablesFrom.
    procedure Resume(const AState: TTyRtfState);
    procedure CopyTablesFrom(AOther: TTyRtfParser);
    function DefaultCharFormat: TTyCharFormat;
    // The UTF-8 text read, paragraphs separated by the platform's line break.
    function TextBytes: TBytes;
    function ParaCount: Integer;
    function ParaRec(AIndex: Integer): TTyRtfParaRec;
    function TableCount: Integer;
    function TableRec(AIndex: Integer): TTyRtfTableRec;
    function HeaderEnd: PtrInt;
    function TrailerStart: PtrInt;
    function SnapshotCount: Integer;
    function Snapshot(AIndex: Integer): TTyRtfState;
    function FragmentOf(const R: TTyRtfRange): RawByteString;
    property Bytes: TBytes read FBytes;
    property PaperWidth: Integer read FPaperW;
    property PaperHeight: Integer read FPaperH;
    property MarginLeft: Integer read FMargL;
    property MarginRight: Integer read FMargR;
    // Keep the state after each token that ended a paragraph (resuming from it reads the
    // rest exactly as the whole parse did).
    property KeepSnapshots: Boolean read FKeepSnapshots write FKeepSnapshots;
  end;

// Replaces ADoc's content with the RTF document in AStream, from its position to its end (as
// loading, not as a change: the history goes and Modified is False). Raises ETyRichRtf when
// the bytes do not start with the RTF signature; anything after that loads as far as it goes, however
// broken. AMap, when given, gets the file's bytes and how they were cut.
procedure TyRichLoadRtf(ADoc: TTyRichDocument; AStream: TStream; AMap: TTyRtfSourceMap = nil);

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

var
  WordSlots: array[0..2047] of SmallInt;   // index + 1 into WordTable, 0 empty

{$PUSH}{$Q-}{$R-}
function HashName(P: PByte; ALen: Integer): Cardinal;
var
  i: Integer;
begin
  Result := 2166136261;
  for i := 0 to ALen - 1 do
    Result := (Result xor P[i]) * 16777619;
end;
{$POP}

procedure InitWords;
var
  i: Integer;
  h: Cardinal;
begin
  FillChar(WordSlots, SizeOf(WordSlots), 0);
  for i := 0 to High(WordTable) do
  begin
    h := HashName(PByte(PChar(WordTable[i].N)), Length(WordTable[i].N)) and High(WordSlots);
    while WordSlots[h] <> 0 do h := (h + 1) and High(WordSlots);
    WordSlots[h] := i + 1;
  end;
end;

function LookupWord(P: PByte; ALen: Integer): Integer;
var
  h: Cardinal;
  s: Integer;
begin
  h := HashName(P, ALen) and High(WordSlots);
  repeat
    s := WordSlots[h];
    if s = 0 then Exit(kwUnknown);
    if (Length(WordTable[s - 1].N) = ALen) and
       CompareMem(P, PChar(WordTable[s - 1].N), ALen) then
      Exit(WordTable[s - 1].K);
    h := (h + 1) and High(WordSlots);
  until False;
end;

function NameStarts(P: PByte; ALen: Integer; const APrefix: string): Boolean;
begin
  Result := (ALen >= Length(APrefix)) and CompareMem(P, PChar(APrefix), Length(APrefix));
end;

// A table row's own words: kept in the row's definition, never on a paragraph or run.
function IsRowWord(P: PByte; ALen: Integer; AInRowDef: Boolean): Boolean;
begin
  Result := NameStarts(P, ALen, 'tr') or NameStarts(P, ALen, 'cl') or
    NameStarts(P, ALen, 'irow') or NameStarts(P, ALen, 'lastrow') or
    NameStarts(P, ALen, 'ltrrow') or NameStarts(P, ALen, 'rtlrow');
  if not Result and AInRowDef then
    Result := NameStarts(P, ALen, 'brdr') or NameStarts(P, ALen, 'brsp') or
      NameStarts(P, ALen, 'ts') or NameStarts(P, ALen, 'tbl') or NameStarts(P, ALen, 'tp') or
      NameStarts(P, ALen, 'tdfrmtxt') or NameStarts(P, ALen, 'tabsnoovrlp') or
      NameStarts(P, ALen, 'taprtl');
end;

// Paragraph borders and shading: the paragraph's Extra.
function IsParaPrefixWord(P: PByte; ALen: Integer): Boolean;
begin
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

// A new array with R at the end: the old one may be shared by a saved group or a snapshot.
procedure AppendRange(var A: TTyRtfRanges; const R: TTyRtfRange);
var
  n: Integer;
  b: TTyRtfRanges;
begin
  n := Length(A);
  b := nil;
  SetLength(b, n + 1);
  if n > 0 then Move(A[0], b[0], n * SizeOf(TTyRtfRange));
  b[n] := R;
  A := b;
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

function TTyRtfState.Snapshot: TTyRtfState;
begin
  Result := Self;
  Result.Stack := Copy(Stack, 0, Length(Stack));
  Result.RowDef.Cellx := Copy(RowDef.Cellx, 0, Length(RowDef.Cellx));
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
  inherited Destroy;
end;

function TTyRtfParser.Counting: Boolean;
begin
  Result := FPool = nil;
end;

procedure TTyRtfParser.InitState;
begin
  FS := Default(TTyRtfState);
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
    CharExtra := nil;
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
    Tabs := nil;
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
    ParaExtra := nil;
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
begin
  FS.Pos := FLex.Position;
  Result := FS.Snapshot;
end;

procedure TTyRtfParser.Resume(const AState: TTyRtfState);
begin
  FS := AState.Snapshot;
  FLex.Init(FBuf, FS.Pos, FLen);
  FFinished := False;
  FDecNum := -100;
  CharChanged;
  ParaChanged;
end;

procedure TTyRtfParser.CopyTablesFrom(AOther: TTyRtfParser);
begin
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
var
  absorbable: Boolean;
  paras: Integer;
begin
  while not FS.DocClosed and FLex.Next(FTok) do
  begin
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
    // after the token that ended a paragraph, all of it done (a row's end included)
    if FKeepSnapshots and (FS.Paras <> paras) then
    begin
      SetLength(FSnapshots, Length(FSnapshots) + 1);
      FSnapshots[High(FSnapshots)] := SaveState;
    end;
  end;
  Finish;
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
  if Length(FS.Stack) <= FS.Depth then SetLength(FS.Stack, FS.Depth * 2 + 8);
  FS.Stack[FS.Depth] := FS.Props;
  Inc(FS.Depth);
  FS.Props.DestOwner := False;
  FS.GroupOpen := True;
  FS.Star := False;
  FS.GroupStart := FTok.Start;
end;

procedure TTyRtfParser.PopGroup;
var
  old: TTyRtfProps;
begin
  FS.UcSkip := 0;
  FS.GroupOpen := False;
  if FS.Overflow > 0 then
  begin
    Dec(FS.Overflow);
    Exit;
  end;
  if FS.Depth <= 0 then Exit;
  old := FS.Props;
  FS.Props := FS.Stack[FS.Depth - 1];
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
  if old.DestOwner then EndDest(old);
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
        FS.Nested := True;
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
      end;
    rdColorTable:
      if FColorAny then AddColor;
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
      end;
    rdPn:
      begin
        // the list properties belong to the paragraph, not to the {\*\pn} group
        FS.Props.ListKind := AOld.ListKind;
        FS.Props.ListLevel := AOld.ListLevel;
        FS.Props.ListStart := AOld.ListStart;
        FS.Props.ParaExtra := AOld.ParaExtra;
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
            FHeld.HeightTwips, Fragment(Range(AOld.DestStart, stop)));
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
        if FTok.Param < 0 then
          FEntry.Name := FEntry.Name + UTF8Encode(WideChar(FTok.Param + 65536))
        else
          FEntry.Name := FEntry.Name + UTF8Encode(WideChar(FTok.Param));
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
  CharChanged;
end;

function TTyRtfParser.ColorOf(AIndex: Integer; ADefault: TColor): TColor;
begin
  if (AIndex <= 0) or (AIndex >= FColorCount) or FColorAuto[AIndex] then Result := ADefault
  else Result := FColors[AIndex];
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
  Result := TTyRichPicture.Create(FPicFormat, data, Integer(w), Integer(h),
    Fragment(Range(AStart, AStop)));
  FObjects.Add(Result);
  FPicData := nil;
  FPicLen := 0;
end;

// ---- body words ----

procedure TTyRtfParser.AddCharExtra(AStart, AStop: PtrInt);
begin
  AppendRange(FS.Props.CharExtra, Range(AStart, AStop));
  CharChanged;
end;

procedure TTyRtfParser.AddParaExtra(AStart, AStop: PtrInt);
begin
  AppendRange(FS.Props.ParaExtra, Range(AStart, AStop));
  ParaChanged;
end;

procedure TTyRtfParser.EndRowDef;
begin
  FS.InRowDef := False;
end;

procedure TTyRtfParser.BodyWord(AKw: Integer);
var
  p: Integer;
  onOff: Boolean;
  t: TTyTabStops;
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
    kwAnsi: if not FAnsiCpSet then FAnsiCp := 1252;
    kwMac: if not FAnsiCpSet then FAnsiCp := 10000;
    kwPc: if not FAnsiCpSet then FAnsiCp := 437;
    kwPca: if not FAnsiCpSet then FAnsiCp := 850;
    kwAnsiCpg:
      begin
        if TyRichCodePageSupported(p) then FAnsiCp := p else FAnsiCp := 1252;
        FAnsiCpSet := True;
        Inc(FFontGen);
      end;
    kwDeff:
      begin
        FDeff := p;
        CharChanged;
      end;
    kwPaperW: if p > 0 then FPaperW := p;
    kwPaperH: if p > 0 then FPaperH := p;
    kwMargL: if p >= 0 then FMargL := p;
    kwMargR: if p >= 0 then FMargR := p;
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
        t := Copy(FS.Props.Tabs, 0, Length(FS.Props.Tabs));
        SetLength(t, Length(t) + 1);
        t[High(t)].Position := p;
        t[High(t)].Align := FS.Props.TabAlign;
        t[High(t)].Leader := FS.Props.TabLeader;
        FS.Props.Tabs := t;
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
        if p >= 2 then FS.Nested := True;
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
        FS.RowDef.Cellx := nil;
        FS.RowDef.Merged := False;
        FS.RowDef.Raw := Range(FTok.Start, FTok.Stop);
      end;
    kwCellx:
      begin
        FS.RowDef.Cellx := Copy(FS.RowDef.Cellx, 0, Length(FS.RowDef.Cellx));
        SetLength(FS.RowDef.Cellx, Length(FS.RowDef.Cellx) + 1);
        FS.RowDef.Cellx[High(FS.RowDef.Cellx)] := p;
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
        FS.Nested := True;
        EndParagraph(rpkNestCell);
      end;
    kwNestRow: FS.Nested := True;
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
  if AValue < 0 then c := AValue + 65536 else c := AValue;
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
begin
  if Counting then
  begin
    EmitObject(nil);
    Exit;
  end;
  o := TTyRichOpaque.Create(Fragment(Range(AStart, AStop)), ADisplay);
  FObjects.Add(o);
  EmitObject(o);
end;

procedure TTyRtfParser.EndParagraph(AKind: TTyRtfParaKind);
var
  rec: TTyRtfParaRec;
  inTable: Boolean;
  i: Integer;
begin
  if FS.InRowDef then EndRowDef;
  Flush;
  EnsureBody;
  rec := Default(TTyRtfParaRec);
  rec.Table := -1;
  rec.Chars := FCurChars;
  if not Counting then
  begin
    if FRunN = 0 then AddRun(CharFormatFor(rccLoch), nil);
    rec.Runs := Copy(FRuns, 0, FRunN);
    rec.Format := ParaFormatId;
    for i := 1 to Length(FSep) do PutOut(Ord(FSep[i]));
  end;
  inTable := (AKind <> rpkPar) or FS.Props.InTable or (FS.Props.Itap > 0);
  if inTable then
  begin
    // (a parse resumed inside a table starts a record of its own for the rest of it)
    if not FS.TableOpen or (not Counting and (FTableN = 0)) then
    begin
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
      rec.Table := FTableN - 1;
      rec.Row := FTables[FTableN - 1].RowCount;
      rec.Cell := FS.CellIdx;
    end;
    if FS.CellIdx + 1 > FS.RowMax then FS.RowMax := FS.CellIdx + 1;
    if AKind = rpkCell then Inc(FS.CellIdx);
  end
  else if FS.TableOpen then
    CloseTable;
  rec.Src := Range(FS.Boundary, FTok.Stop);
  if FParaN = Length(FParas) then SetLength(FParas, FParaN * 2 + 16);
  FParas[FParaN] := rec;
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
  n: Integer;
  r: TTyRtfRowRec;
begin
  n := FS.CellIdx;
  if FS.RowMax > n then n := FS.RowMax;
  FS.CellIdx := 0;
  FS.RowMax := 0;
  if (n = 0) or Counting or (FTableN = 0) then Exit;
  r.CellCount := n;
  r.Raw := FS.RowDef.Raw;
  r.Cellx := Copy(FS.RowDef.Cellx, 0, Length(FS.RowDef.Cellx));
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
  for i := 0 to High(FS.Props.CharExtra) do
    Result.Extra.Add(Fragment(FS.Props.CharExtra[i]));
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

procedure TTyRtfParser.ResolveList(var AList: TTyListFormat);
var
  i, id, lvl: Integer;
begin
  id := -1;
  for i := 0 to FOverrideCount - 1 do
    if FOverrideLs[i] = FS.Props.Ls then
    begin
      id := FOverrideId[i];
      Break;
    end;
  if id < 0 then Exit;
  for i := 0 to FListCount - 1 do
    if FLists[i].Id = id then
    begin
      lvl := FS.Props.Ilvl;
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

function TTyRtfParser.BuildParaFormat: TTyParaFormat;
var
  i: Integer;
  slExtra: Boolean;
begin
  Result := TyDefaultParaFormat;
  with FS.Props do
  begin
    Result.Align := Align;
    Result.LeftIndent := LeftIndent;
    Result.RightIndent := RightIndent;
    Result.FirstIndent := FirstIndent;
    Result.SpaceBefore := SpaceBefore;
    Result.SpaceAfter := SpaceAfter;
    Result.Tabs := Tabs;
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
      ResolveList(Result.List)
    else if ListKind <> lkNone then
    begin
      Result.List.Kind := ListKind;
      Result.List.Level := ListLevel;
      Result.List.StartAt := ListStart;
      if (ListKind <> lkBullet) and (ListStart = 0) then Result.List.StartAt := 1;
    end;
    for i := 0 to High(ParaExtra) do Result.Extra.Add(Fragment(ParaExtra[i]));
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

function TTyRtfParser.ParaCount: Integer;
begin
  Result := FParaN;
end;

function TTyRtfParser.ParaRec(AIndex: Integer): TTyRtfParaRec;
begin
  Result := FParas[AIndex];
end;

function TTyRtfParser.TableCount: Integer;
begin
  Result := FTableN;
end;

function TTyRtfParser.TableRec(AIndex: Integer): TTyRtfTableRec;
begin
  Result := FTables[AIndex];
end;

function TTyRtfParser.HeaderEnd: PtrInt;
begin
  Result := FS.HeaderEnd;
end;

function TTyRtfParser.TrailerStart: PtrInt;
begin
  Result := FTrailerStart;
end;

function TTyRtfParser.SnapshotCount: Integer;
begin
  Result := Length(FSnapshots);
end;

function TTyRtfParser.Snapshot(AIndex: Integer): TTyRtfState;
begin
  Result := FSnapshots[AIndex].Snapshot;
end;

function TTyRtfParser.FragmentOf(const R: TTyRtfRange): RawByteString;
begin
  Result := Fragment(R);
end;

// ---- loading ----

type
  TRtfFiller = class(TTyRichDocBuilder)
  public
    class procedure Fill(ADoc: TTyRichDocument; AParser: TTyRtfParser);
  end;

class procedure TRtfFiller.Fill(ADoc: TTyRichDocument; AParser: TTyRtfParser);
var
  text: TTyRichText;
  handler: TTyRichChangeEvent;
  change: TTyRichChange;
  tables: array of TTyRichTable;
  i, j: Integer;
  rec: TTyRtfParaRec;
  tr: TTyRtfTableRec;
  cell: TTyRichCell;
  t: TTyRichTable;
begin
  text := TTyRichText.CreateFromUtf8(AParser.TextBytes);
  if text.ParaCount <> AParser.ParaCount then
  begin
    text.Free;
    raise ETyRichRtf.CreateFmt('RTF reader: %d paragraphs read, but the text has %d',
      [AParser.ParaCount, text.ParaCount]);
  end;
  change := Default(TTyRichChange);
  change.Kinds := [rckText, rckFormat, rckStructure];
  change.OldLen := ADoc.Text.Length;
  change.OldParaCount := ADoc.Text.ParaCount;
  // the one change is reported when the formats are in place, not while the text is plain
  handler := ADoc.OnChange;
  ADoc.OnChange := nil;
  tables := nil;
  try
    ReplaceText(ADoc, text);
    SetDefaultCharFormat(ADoc, AParser.DefaultCharFormat);
    SetPage(ADoc, AParser.PaperWidth, AParser.PaperHeight, AParser.MarginLeft,
      AParser.MarginRight);
    SetLength(tables, AParser.TableCount);
    for i := 0 to AParser.TableCount - 1 do
    begin
      tr := AParser.TableRec(i);
      if tr.RowCount > 0 then t := TTyRichTable.Create(tr.Rows[0].Cellx, tr.Locked)
      else t := TTyRichTable.Create([], tr.Locked);
      tables[i] := t;
      for j := 0 to tr.RowCount - 1 do
        t.AddRow(tr.Rows[j].CellCount, AParser.FragmentOf(tr.Rows[j].Raw), tr.Rows[j].Cellx);
    end;
    for i := 0 to AParser.ParaCount - 1 do
    begin
      rec := AParser.ParaRec(i);
      cell := nil;
      if (rec.Table >= 0) and (rec.Table < Length(tables)) and
         (rec.Row < tables[rec.Table].RowCount) and
         (rec.Cell < tables[rec.Table].Rows[rec.Row].CellCount) then
        cell := tables[rec.Table].Rows[rec.Row].Cells[rec.Cell];
      SetParagraph(ADoc, i, rec.Format, rec.Runs, cell);
    end;
  finally
    for i := 0 to High(tables) do
      if (tables[i] <> nil) and (tables[i].RefCount = 0) then tables[i].Free;
    ADoc.OnChange := handler;
  end;
  change.NewLen := ADoc.Text.Length;
  change.NewParaCount := ADoc.Text.ParaCount;
  if Assigned(handler) then handler(ADoc, change);
end;

procedure TyRichLoadRtf(ADoc: TTyRichDocument; AStream: TStream; AMap: TTyRtfSourceMap);
const
  Signature: array[0..4] of Char = '{\rtf';
var
  bytes: TBytes;
  n: Int64;
  p: TTyRtfParser;
  i: Integer;
begin
  n := AStream.Size - AStream.Position;
  bytes := nil;
  if n > 0 then
  begin
    SetLength(bytes, n);
    AStream.ReadBuffer(bytes[0], n);
  end;
  if (n < 5) or not CompareMem(@bytes[0], @Signature[0], 5) then
    raise ETyRichRtf.Create('This is no RTF: it does not start with {\rtf');
  p := TTyRtfParser.Create(bytes, ADoc.Formats);
  try
    p.Parse;
    TRtfFiller.Fill(ADoc, p);
    if AMap <> nil then
    begin
      AMap.Bytes := bytes;
      AMap.Header := Range(0, p.HeaderEnd);
      SetLength(AMap.Paras, p.ParaCount);
      for i := 0 to p.ParaCount - 1 do AMap.Paras[i] := p.ParaRec(i).Src;
      AMap.Trailer := Range(p.TrailerStart, n);
    end;
  finally
    p.Free;
  end;
end;

initialization
  InitWords;
end.
