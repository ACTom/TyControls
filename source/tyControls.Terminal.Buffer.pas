unit tyControls.Terminal.Buffer;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

{ The terminal's screen memory: cells, lines, the ring of lines, the normal and
  alternate buffers with their cursor, margins and tab stops, markers, the buffer
  service that scrolls and resizes, and the OSC 8 link table. No LCL.

  PORTED FROM xterm.js 6.0.0, commit c58ea3637f39:
    src/common/buffer/Constants.ts      the cell bit layout
    src/common/buffer/AttributeData.ts  TTyTerminalAttrData, TTyTerminalExtAttrs
    src/common/buffer/CellData.ts       TTyTerminalCellData
    src/common/buffer/BufferLine.ts     TTyTerminalLine
    src/common/CircularList.ts          TTyTerminalLineList
    src/common/buffer/Marker.ts         TTyTerminalMarker
    src/common/buffer/Buffer.ts         TTyTerminalBuffer (reflow not yet, see below)
    src/common/buffer/BufferSet.ts      TTyTerminalBufferSet
    src/common/services/BufferService.ts   TTyTerminalBufferService
    src/common/services/OscLinkService.ts  TTyTerminalOscLinks

    Copyright (c) 2017-2019, The xterm.js authors (https://github.com/xtermjs/xterm.js)
    Copyright (c) 2014-2016, SourceLair Private Company (https://www.sourcelair.com)
    Copyright (c) 2012-2013, Christopher Jeffrey (https://github.com/chjj/)
  MIT; the full text is in THIRD-PARTY-NOTICES.md.

  WHAT DIFFERS IN SHAPE (never in result):

  - Extended attributes are values. Upstream shares ExtendedAttrs objects between
    cells but clones before every change, so a record copy behaves the same.
  - Lines are reference counted (AddRef / Release, freed at zero; not atomic, the
    core is main-thread only). Every ring slot and the buffer service's cached blank
    line hold one reference; a line that is still needed across a change of the
    ring is pinned with AddRef. A new line starts at 1 and belongs to whoever made
    it: after handing it to the ring (Push / SetItem / Splice) that owner releases
    its own reference -- the *Owned helpers do both.
    Pinned in this unit: BufferService.Scroll's blank line (the service's cache).
    Buffer.Resize only touches lines between ring changes, and the link table holds
    markers, not lines. Pinned in tyControls.Terminal.Core: print's current and old
    row, and the cursor row that ClearScrollback moves to the top.
  - Markers are reference counted too: the buffer holds one while a marker is live,
    the link table one per marker it lists; a marker disposed is dropped by both.
  - Reflow is phase 5: IsReflowEnabled is always False, so the buffer resizes the
    way xterm.js does for an old ConPTY -- narrower columns keep the longer lines,
    wider ones pad them, nothing is rewrapped.
  - BufferService lives here, not in the core, so the buffer layer can be held to
    upstream on its own (the core owns one).

  The combined text and the extended attributes of a line are small arrays sorted by
  column, read only when the cell's flag says so -- like upstream's sparse objects,
  an entry can outlive its cell and is simply never read. }

interface

uses
  SysUtils, Classes, Types, tyControls.Unicode.Width;

const  { buffer/Constants.ts:36-157, names upper-camel with a TyTerm prefix, values identical }
  TyTermContentCodepointMask = $1FFFFF;
  TyTermContentIsCombinedMask = $200000;
  TyTermContentHasContentMask = $3FFFFF;
  TyTermContentWidthMask = $C00000;
  TyTermContentWidthShift = 22;
  TyTermAttrCmMask = $3000000;
  TyTermAttrCmDefault = 0;
  TyTermAttrCmP16 = $1000000;
  TyTermAttrCmP256 = $2000000;
  TyTermAttrCmRgb = $3000000;
  TyTermAttrRgbMask = $FFFFFF;
  TyTermAttrPColorMask = $FF;
  TyTermFgInverse = $4000000;
  TyTermFgBold = $8000000;
  TyTermFgUnderline = $10000000;
  TyTermFgBlink = $20000000;
  TyTermFgInvisible = $40000000;
  TyTermFgStrikethrough = $80000000;
  TyTermBgItalic = $4000000;
  TyTermBgDim = $8000000;
  TyTermBgHasExtended = $10000000;
  TyTermBgProtected = $20000000;
  TyTermBgOverline = $40000000;
  TyTermExtUnderlineStyle = $1C000000;
  TyTermExtVariantOffset = $E0000000;
  TyTermNullCellCode = 0;
  TyTermNullCellWidth = 1;
  TyTermWhitespaceCellCode = 32;
  TyTermMaxBufferSize = 4294967295;        { Buffer.ts:20 }
  TyTermMinimumCols = 2;                   { BufferService.ts MINIMUM_COLS }
  TyTermMinimumRows = 1;

type
  TTyTermUnderlineStyle = (tusNone, tusSingle, tusDouble, tusCurly, tusDotted, tusDashed);

  { ExtendedAttrs, AttributeData.ts:140-213 -- a value (unit header). Upstream's
    payload field is only used by the image addon and is not ported. }
  TTyTerminalExtAttrs = record
    RawExt: Cardinal;                      { upstream _ext }
    UrlId: Integer;
    function Ext: Cardinal;                { the getter: DASHED forced while UrlId <> 0 }
    function UnderlineStyle: Integer;
    procedure SetUnderlineStyle(AValue: Integer);
    function UnderlineColor: Cardinal;
    procedure SetUnderlineColor(AValue: Integer);   { -1 stores $3FFFFFF, as upstream }
    function UnderlineVariantOffset: Integer;
    procedure SetUnderlineVariantOffset(AValue: Integer);
    function IsEmpty: Boolean;
  end;

  { AttributeData; the getters keep upstream's names (is/get prefixes included). }
  TTyTerminalAttrData = record
    Fg, Bg: Cardinal;
    Extended: TTyTerminalExtAttrs;
    function IsInverse: Boolean;
    function IsBold: Boolean;
    function IsUnderline: Boolean;
    function IsBlink: Boolean;
    function IsInvisible: Boolean;
    function IsItalic: Boolean;
    function IsDim: Boolean;
    function IsStrikethrough: Boolean;
    function IsProtected: Boolean;
    function IsOverline: Boolean;
    function GetFgColorMode: Cardinal;
    function GetBgColorMode: Cardinal;
    function IsFgRGB: Boolean;
    function IsBgRGB: Boolean;
    function IsFgPalette: Boolean;
    function IsBgPalette: Boolean;
    function IsFgDefault: Boolean;
    function IsBgDefault: Boolean;
    function IsAttributeDefault: Boolean;
    function GetFgColor: Integer;           { -1 = default }
    function GetBgColor: Integer;
    function HasExtendedAttrs: Boolean;
    procedure UpdateExtended;
    function GetUnderlineColor: Integer;
    function GetUnderlineColorMode: Cardinal;
    function GetUnderlineStyle: Integer;
    function GetUnderlineVariantOffset: Integer;
  end;

  { CellData (design spec 6.3); Combined is UTF-8. }
  TTyTerminalCellData = record
    Content, Fg, Bg: Cardinal;
    Ext: TTyTerminalExtAttrs;
    Combined: string;
    function Width: Integer;
    function IsCombined: Boolean;
    function Chars: string;
    function AsAttr: TTyTerminalAttrData;
  end;

  TTyTermComboEntry = record
    Col: Integer;
    Text: string;                          { UTF-8 }
  end;
  TTyTermExtEntry = record
    Col: Integer;
    Ext: TTyTerminalExtAttrs;
  end;

  { BufferLine, BufferLine.ts:69-618; reference counted (unit header). }
  TTyTerminalLine = class
  private
    class var GLiveCount: Integer;
  private
    FData: array of Cardinal;              { the whole allocation: upstream's ArrayBuffer }
    FLength: Integer;                      { cells in use: _data is FLength * 3 of it }
    FCombined: array of TTyTermComboEntry;
    FCombinedCount: Integer;
    FExtended: array of TTyTermExtEntry;
    FExtendedCount: Integer;
    FIsWrapped: Boolean;
    FRefCount: Integer;
    FCacheValid, FCacheTrimmed: Boolean;   { translateToString's cache: observable }
    FCache: string;
    function CombinedIndex(ACol: Integer; out AIndex: Integer): Boolean;
    function ExtendedIndex(ACol: Integer; out AIndex: Integer): Boolean;
    procedure PutCombined(ACol: Integer; const AText: string);
    procedure PutExtended(ACol: Integer; const AExt: TTyTerminalExtAttrs);
    procedure ClearSparse;
    procedure CopyCellMapsFrom(ASrc: TTyTerminalLine; ASrcCol, ADestCol: Integer);
    procedure CopySparseMapsFrom(ALine: TTyTerminalLine);
    procedure PutCp(ACol: Integer; ACodepoint: Cardinal; AWidth: Integer; AFg, ABg: Cardinal;
      const AExt: TTyTerminalExtAttrs);
    function Word0(ACol: Integer): Cardinal; inline;
  public
    constructor Create(ACols: Integer; const AFill: TTyTerminalCellData; AIsWrapped: Boolean = False);
    constructor CreateDefault(ACols: Integer; AIsWrapped: Boolean = False);   { NULL cells }
    destructor Destroy; override;
    procedure AddRef;
    procedure Release;                     { frees at zero }
    class function LiveCount: Integer;     { pure query, leak guard }
    function GetWidth(ACol: Integer): Integer;
    function HasWidth(ACol: Integer): Boolean;
    function GetFg(ACol: Integer): Cardinal;
    function GetBg(ACol: Integer): Cardinal;
    function GetContent(ACol: Integer): Cardinal;
    function HasContent(ACol: Integer): Boolean;
    { A combined cell answers the last UTF-16 unit of its text, as upstream (a low
      surrogate for a trailing astral code point). }
    function GetCodePoint(ACol: Integer): Cardinal;
    function IsCombined(ACol: Integer): Boolean;
    function GetChars(ACol: Integer): string;          { getString, UTF-8 }
    function IsProtected(ACol: Integer): Boolean;
    { The combined text of ACol if the table has an entry (flag or not). }
    function CombinedEntry(ACol: Integer; out AText: string): Boolean;
    function ExtendedEntry(ACol: Integer; out AExt: TTyTerminalExtAttrs): Boolean;
    procedure LoadCell(ACol: Integer; var ACell: TTyTerminalCellData);
    function GetExtended(ACol: Integer): TTyTerminalExtAttrs;
    procedure SetCell(ACol: Integer; const ACell: TTyTerminalCellData);
    procedure SetCellFromCodepoint(ACol: Integer; ACodepoint: Cardinal; AWidth: Integer;
      const AAttrs: TTyTerminalAttrData);
    procedure AddCodepointToCell(ACol: Integer; ACodepoint: Cardinal; AWidth: Integer);
    procedure InsertCells(APos: Integer; ACount: Int64; const AFill: TTyTerminalCellData);
    procedure DeleteCells(APos: Integer; ACount: Int64; const AFill: TTyTerminalCellData);
    procedure ReplaceCells(AStart: Integer; AEnd: Int64; const AFill: TTyTerminalCellData;
      ARespectProtect: Boolean = False);
    function Resize(ACols: Integer; const AFill: TTyTerminalCellData): Boolean;
    procedure Fill(const AFill: TTyTerminalCellData; ARespectProtect: Boolean = False);
    procedure CopyFrom(ALine: TTyTerminalLine; ABlank: Boolean = False);
    function Clone(ABlank: Boolean = False): TTyTerminalLine;   { refcount 1, owned by caller }
    function GetTrimmedLength: Integer;
    function GetNoBgTrimmedLength: Integer;
    procedure CopyCellsFrom(ASrc: TTyTerminalLine; ASrcCol, ADestCol, ALength: Integer;
      AApplyInReverse: Boolean);
    { AStartCol 0 and AEndCol -1 (upstream: undefined) is the canonical request that
      goes through the cache. }
    function TranslateToString(ATrimRight: Boolean = False; AStartCol: Integer = 0;
      AEndCol: Integer = -1): string;
    property IsWrapped: Boolean read FIsWrapped write FIsWrapped;
    property Length: Integer read FLength;
    property RefCount: Integer read FRefCount;
  end;

  TTyTermListEvent = procedure(AIndex, AAmount: Integer) of object;
  TTyTermTrimEvent = procedure(AAmount: Integer) of object;

  { CircularList<IBufferLine>, CircularList.ts:45-262. Every slot holds a reference
    (the unit header); Get borrows. The start index is kept the way upstream keeps
    it -- reduced after push / recycle, not after splice, trimStart or shift -- so
    that Get(-1) answers what upstream answers. Slots past Length keep their lines
    until overwritten, as upstream's array does. Events fire in upstream's order
    (splice: delete, insert, trim). }
  TTyTerminalLineList = class
  private
    FArray: array of TTyTerminalLine;
    FMaxLength: Integer;
    FStartIndex: Int64;
    FLength: Integer;
    FOnInsert: TTyTermListEvent;
    FOnDelete: TTyTermListEvent;
    FOnTrim: TTyTermTrimEvent;
    function Cyclic(AIndex: Int64): Int64; inline;
    procedure Store(ASlot: Int64; ALine: TTyTerminalLine);
    procedure SetMaxLength(AValue: Integer);
    procedure SetLengthValue(AValue: Integer);
    function GetIsFull: Boolean;
    procedure DoTrim(AAmount: Integer);
  public
    constructor Create(AMaxLength: Integer);
    destructor Destroy; override;
    function Get(AIndex: Integer): TTyTerminalLine;               { borrowed; nil outside }
    procedure SetItem(AIndex: Integer; ALine: TTyTerminalLine);   { takes a reference }
    procedure SetItemOwned(AIndex: Integer; ALine: TTyTerminalLine);   { and drops the caller's }
    procedure Push(ALine: TTyTerminalLine);
    procedure PushOwned(ALine: TTyTerminalLine);
    { Raises EInvalidOperation unless full (upstream throws). The line stays in its
      slot and is borrowed. }
    function Recycle: TTyTerminalLine;
    function Pop: TTyTerminalLine;                                 { borrowed }
    procedure Splice(AStart, ADeleteCount: Integer; const AItems: array of TTyTerminalLine);
    procedure SpliceOwned(AStart, ADeleteCount: Integer; ALine: TTyTerminalLine);
    procedure TrimStart(ACount: Integer);
    { Raises EArgumentOutOfRangeException where upstream throws. }
    procedure ShiftElements(AStart, ACount, AOffset: Integer);
    function SlotLine(ASlot: Integer): TTyTerminalLine;           { pure query, leak guard }
    property Length: Integer read FLength write SetLengthValue;
    property MaxLength: Integer read FMaxLength write SetMaxLength;
    property IsFull: Boolean read GetIsFull;
    property OnInsert: TTyTermListEvent read FOnInsert write FOnInsert;
    property OnDelete: TTyTermListEvent read FOnDelete write FOnDelete;
    property OnTrim: TTyTermTrimEvent read FOnTrim write FOnTrim;
  end;

  { Marker.ts; reference counted (unit header). }
  TTyTerminalMarker = class
  private
    class var GNextId: Integer;
  private
    FId: Integer;
    FLine: Integer;
    FIsDisposed: Boolean;
    FListeners: array of TNotifyEvent;
    FRefCount: Integer;
    FGeneration: Integer;
    FTag: TObject;
  public
    constructor Create(ALine: Integer);
    procedure AddRef;
    procedure Release;
    { Idempotent: sets IsDisposed and Line -1, then calls the listeners in the order
      they were added. }
    procedure Dispose;
    procedure AddDisposeListener(AHandler: TNotifyEvent);
    procedure RemoveDisposeListener(AHandler: TNotifyEvent);
    property Id: Integer read FId;
    property Line: Integer read FLine write FLine;
    property IsDisposed: Boolean read FIsDisposed;
    property Tag: TObject read FTag write FTag;
  end;

  TTyTermWindowsPtyBackend = (twpNone, twpConPty, twpWinPty);
  TTyTerminalWindowsPty = record
    Backend: TTyTermWindowsPtyBackend;
    BuildNumber: Integer;                  { 0 = not given }
  end;
  { 0 = none (upstream undefined); the others index the core's charset table }
  TTyTermCharsetId = type Byte;
  TTyTermCharsetIds = array of TTyTermCharsetId;
  TTyTermCursorStyleOption = (tcoBlock, tcoUnderline, tcoBar);   { options.cursorStyle }
  TTyTermYDispEvent = procedure(AYDisp: Integer) of object;
  TTyTermResizeEvent = procedure(ACols, ARows: Integer; AColsChanged, ARowsChanged: Boolean) of object;

  { The OptionsService subset the buffer and the core read (defaults as upstream's
    DEFAULT_OPTIONS). WindowOptions / VtExtensions / the Unicode version live in the
    core. }
  TTyTerminalOptions = class
  public
    Scrollback: Integer;
    TabStopWidth: Integer;
    ConvertEol: Boolean;
    ScrollOnUserInput: Boolean;
    DisableStdin: Boolean;
    ScrollOnEraseInDisplay: Boolean;
    ReflowCursorLine: Boolean;
    CursorBlink: Boolean;
    AllowSetCursorBlink: Boolean;
    CursorStyle: TTyTermCursorStyleOption;
    WindowsPty: TTyTerminalWindowsPty;
    constructor Create;
  end;

  TTyTerminalBufferService = class;

  { Buffer.ts:29-672 without _reflow* (phase 5). }
  TTyTerminalBuffer = class
  private
    FLines: TTyTerminalLineList;
    FYDisp, FYBase, FY, FX: Integer;
    FScrollTop, FScrollBottom: Integer;
    FTabs: array of Boolean;
    FMarkers: TFPList;
    FCols, FRows: Integer;
    FIsClearing: Boolean;
    FHasScrollback: Boolean;
    FGeneration: Integer;
    FOptions: TTyTerminalOptions;
    FService: TTyTerminalBufferService;
    procedure NewLines;
    function GetCorrectBufferLength(ARows: Integer): Integer;
    procedure LinesTrim(AAmount: Integer);
    procedure LinesInsert(AIndex, AAmount: Integer);
    procedure LinesDelete(AIndex, AAmount: Integer);
    procedure MarkerDisposed(Sender: TObject);
    function MarkerSnapshot: TFPList;
    function GetHasScrollback: Boolean;
    function GetIsCursorInViewport: Boolean;
    function GetMarker(AIndex: Integer): TTyTerminalMarker;
    function GetMarkerCount: Integer;
    function GetLength: Integer;
    function GetIsReflowEnabled: Boolean;
  public
    SavedX, SavedY: Integer;
    SavedAttr: TTyTerminalAttrData;        { upstream savedCurAttrData }
    SavedCharset: TTyTermCharsetId;
    SavedCharsets: TTyTermCharsetIds;      { a copy (upstream slice()); 0 = undefined }
    SavedGLevel: Integer;
    SavedOriginMode: Boolean;
    SavedWraparoundMode: Boolean;
    constructor Create(AHasScrollback: Boolean; AOptions: TTyTerminalOptions; AService: TTyTerminalBufferService);
    destructor Destroy; override;
    function GetLine(AAbsRow: Integer): TTyTerminalLine;          { borrowed }
    { Always True; AFirst / ALast as upstream's first / last. }
    function GetWrappedRangeForLine(AAbsRow: Integer; out AFirst, ALast: Integer): Boolean;
    { The marker is borrowed: AddRef it to keep it past its disposal. }
    function AddMarker(AAbsRow: Integer): TTyTerminalMarker;
    procedure ClearMarkers(AAbsRow: Integer);
    procedure ClearAllMarkers;
    function GetNullCell: TTyTerminalCellData; overload;
    function GetNullCell(const AAttr: TTyTerminalAttrData): TTyTerminalCellData; overload;
    function GetWhitespaceCell: TTyTerminalCellData; overload;
    function GetWhitespaceCell(const AAttr: TTyTerminalAttrData): TTyTerminalCellData; overload;
    { A new line, refcount 1, owned by the caller (unit header). }
    function GetBlankLine(const AAttr: TTyTerminalAttrData; AIsWrapped: Boolean = False): TTyTerminalLine;
    procedure FillViewportRows; overload;
    procedure FillViewportRows(const AAttr: TTyTerminalAttrData); overload;
    procedure Clear;
    procedure Resize(ANewCols, ANewRows: Integer);
    procedure SetupTabStops(AFrom: Integer = -1);      { -1 = upstream's undefined }
    function PrevStop(AX: Integer = MaxInt): Integer;  { MaxInt = this.x }
    function NextStop(AX: Integer = MaxInt): Integer;
    function HasTab(ACol: Integer): Boolean;
    procedure SetTab(ACol: Integer; AOn: Boolean);     { off = upstream's delete }
    procedure ClearAllTabs;
    { Every set tab, ascending -- keys beyond the columns included (upstream keeps them). }
    function TabStops: TIntegerDynArray;
    function TranslateBufferLineToString(AAbsRow: Integer; ATrimRight: Boolean;
      AStartCol: Integer = 0; AEndCol: Integer = -1): string;
    property Lines: TTyTerminalLineList read FLines;
    property Markers[AIndex: Integer]: TTyTerminalMarker read GetMarker;
    property MarkerCount: Integer read GetMarkerCount;
    property YBase: Integer read FYBase write FYBase;
    property YDisp: Integer read FYDisp write FYDisp;
    property X: Integer read FX write FX;
    property Y: Integer read FY write FY;
    property ScrollTop: Integer read FScrollTop write FScrollTop;
    property ScrollBottom: Integer read FScrollBottom write FScrollBottom;
    property HasScrollback: Boolean read GetHasScrollback;
    property IsCursorInViewport: Boolean read GetIsCursorInViewport;
    property Length: Integer read GetLength;           { Lines.Length }
    { Phase 2: always False (phase 5 wires BufferReflow). }
    property IsReflowEnabled: Boolean read GetIsReflowEnabled;
  end;

  TTyTermBufferActivateEvent = procedure(AActive, AInactive: TTyTerminalBuffer) of object;

  { BufferSet.ts }
  TTyTerminalBufferSet = class
  private
    FNormal, FAlt, FActive: TTyTerminalBuffer;
    FOptions: TTyTerminalOptions;
    FService: TTyTerminalBufferService;
    FOnBufferActivate: TTyTermBufferActivateEvent;
    function GetIsAlt: Boolean;
  public
    constructor Create(AOptions: TTyTerminalOptions; AService: TTyTerminalBufferService);
    destructor Destroy; override;
    procedure Reset;
    procedure ActivateNormalBuffer;
    procedure ActivateAltBuffer; overload;
    procedure ActivateAltBuffer(const AFill: TTyTerminalAttrData); overload;
    procedure Resize(ANewCols, ANewRows: Integer);
    procedure SetupTabStops(AFrom: Integer = -1);
    property Normal: TTyTerminalBuffer read FNormal;
    property Alt: TTyTerminalBuffer read FAlt;
    property Active: TTyTerminalBuffer read FActive;
    property IsAlt: Boolean read GetIsAlt;
    property OnBufferActivate: TTyTermBufferActivateEvent read FOnBufferActivate write FOnBufferActivate;
  end;

  { services/BufferService.ts, here rather than in the core (unit header). }
  TTyTerminalBufferService = class
  private
    FOptions: TTyTerminalOptions;
    FCols, FRows: Integer;
    FBuffers: TTyTerminalBufferSet;
    FIsUserScrolling: Boolean;
    FCachedBlankLine: TTyTerminalLine;
    FOnScroll: TTyTermYDispEvent;
    FOnResize: TTyTermResizeEvent;
    FOnBufferActivate: TTyTermBufferActivateEvent;
    procedure BuffersActivated(AActive, AInactive: TTyTerminalBuffer);
    function GetBuffer: TTyTerminalBuffer;
  public
    constructor Create(AOptions: TTyTerminalOptions; ACols, ARows: Integer);   { min 2 x 1 }
    destructor Destroy; override;
    procedure Resize(ACols, ARows: Integer);
    procedure Reset;
    procedure Scroll(const AEraseAttr: TTyTerminalAttrData; AIsWrapped: Boolean = False);
    procedure ScrollLines(ADisp: Integer; ASuppressScrollEvent: Boolean = False);
    { option-change reactions, BufferSet.ts:36-37 }
    procedure ScrollbackChanged;
    procedure TabStopWidthChanged;
    property Cols: Integer read FCols;
    property Rows: Integer read FRows;
    property Buffers: TTyTerminalBufferSet read FBuffers;
    property Buffer: TTyTerminalBuffer read GetBuffer;
    property IsUserScrolling: Boolean read FIsUserScrolling write FIsUserScrolling;
    property Options: TTyTerminalOptions read FOptions;
    property OnScroll: TTyTermYDispEvent read FOnScroll write FOnScroll;
    property OnResize: TTyTermResizeEvent read FOnResize write FOnResize;
    { after OnScroll, for the core }
    property OnBufferActivate: TTyTermBufferActivateEvent read FOnBufferActivate write FOnBufferActivate;
  end;

  TTyTerminalLinkData = record                { IOscLinkData }
    Id: string;
    HasId: Boolean;
    Uri: string;
  end;

  TTyTermLinkEntry = class
  public
    LinkId: Integer;
    Data: TTyTerminalLinkData;
    Key: string;
    Markers: TFPList;
    constructor Create;
    destructor Destroy; override;
  end;

  { services/OscLinkService.ts. Link numbers start at 1 and are never reused, reset
    or not. }
  TTyTerminalOscLinks = class
  private
    FService: TTyTerminalBufferService;
    FNextId: Integer;
    FEntries: TFPList;                     { by link id, ascending }
    FKeys: array of string;                { entries with an id, by key }
    FKeyEntries: array of TTyTermLinkEntry;
    FKeyCount: Integer;
    function FindEntry(ALinkId: Integer; out AIndex: Integer): Boolean;
    function FindKey(const AKey: string; out AIndex: Integer): Boolean;
    procedure AttachMarker(AEntry: TTyTermLinkEntry; AMarker: TTyTerminalMarker);
    procedure MarkerDisposed(Sender: TObject);
  public
    constructor Create(AService: TTyTerminalBufferService);
    destructor Destroy; override;
    function RegisterLink(const AData: TTyTerminalLinkData): Integer;
    procedure AddLineToLink(ALinkId, AAbsRow: Integer);
    function GetLinkData(ALinkId: Integer; out AData: TTyTerminalLinkData): Boolean;
    function LinkIds: TIntegerDynArray;                  { ascending }
    function LinkLines(ALinkId: Integer): TIntegerDynArray;   { marker lines, in entry order }
    property NextId: Integer read FNextId;
  end;

{ The cell constructors of CellData / Buffer.getNullCell / getWhitespaceCell. }
function TyTermCellFromCodepoint(ACode: Cardinal; AWidth: Integer; const AAttr: TTyTerminalAttrData): TTyTerminalCellData;
function TyTermNullCell(const AAttr: TTyTerminalAttrData): TTyTerminalCellData;
function TyTermWhitespaceCell(const AAttr: TTyTerminalAttrData): TTyTerminalCellData;
{ UTF-8 -> code points (the decoder's input is valid UTF-8; nothing else reaches it). }
function TyTermUtf8Codepoints(const S: string): TIntegerDynArray;
{ ECMAScript WhiteSpace + LineTerminator: what trim / trimEnd drop. }
function TyTermIsJsWhitespace(c: Cardinal): Boolean;
{ JavaScript's String.prototype.trimEnd over UTF-8. }
function TyTermJsTrimEnd(const S: string): string;

const
  TyTermDefaultAttr: TTyTerminalAttrData = (Fg: 0; Bg: 0; Extended: (RawExt: 0; UrlId: 0));

implementation

{ ---- small helpers ---------------------------------------------------------------- }

function CpToUtf8(c: Cardinal): string; inline;
begin
  Result := TyUnicodeCodepointToUtf8(c);
end;

function TyTermUtf8Codepoints(const S: string): TIntegerDynArray;
var
  i, n, len, k: Integer;
  b: Byte;
  c: Cardinal;
begin
  Result := nil;
  SetLength(Result, System.Length(S));
  n := 0;
  i := 1;
  len := System.Length(S);
  while i <= len do
  begin
    b := Ord(S[i]);
    if b < $80 then begin c := b; k := 0; end
    else if b and $E0 = $C0 then begin c := b and $1F; k := 1; end
    else if b and $F0 = $E0 then begin c := b and $0F; k := 2; end
    else begin c := b and $07; k := 3; end;
    Inc(i);
    while (k > 0) and (i <= len) do
    begin
      c := (c shl 6) or (Ord(S[i]) and $3F);
      Inc(i);
      Dec(k);
    end;
    Result[n] := Integer(c);
    Inc(n);
  end;
  SetLength(Result, n);
end;

function TyTermIsJsWhitespace(c: Cardinal): Boolean;
begin
  case c of
    $09..$0D, $20, $A0, $1680, $2000..$200A, $2028, $2029, $202F, $205F, $3000, $FEFF:
      Result := True;
  else
    Result := False;
  end;
end;

function TyTermJsTrimEnd(const S: string): string;
var
  e, p: Integer;
  c: Cardinal;
  b: Byte;
begin
  e := System.Length(S);
  while e > 0 do
  begin
    { the start of the last code point }
    p := e;
    while (p > 1) and (Ord(S[p]) and $C0 = $80) do
      Dec(p);
    b := Ord(S[p]);
    if b < $80 then c := b
    else if b and $E0 = $C0 then c := b and $1F
    else if b and $F0 = $E0 then c := b and $0F
    else c := b and $07;
    Inc(p);
    while p <= e do
    begin
      c := (c shl 6) or (Ord(S[p]) and $3F);
      Inc(p);
    end;
    if not TyTermIsJsWhitespace(c) then
      Break;
    { step back over that code point }
    p := e;
    while (p > 1) and (Ord(S[p]) and $C0 = $80) do
      Dec(p);
    e := p - 1;
  end;
  Result := Copy(S, 1, e);
end;

{ ---- TTyTerminalExtAttrs (AttributeData.ts:140-213) ------------------------------ }

function TTyTerminalExtAttrs.Ext: Cardinal;
begin
  if UrlId <> 0 then
    Result := (RawExt and not Cardinal(TyTermExtUnderlineStyle)) or (Cardinal(UnderlineStyle) shl 26)
  else
    Result := RawExt;
end;

function TTyTerminalExtAttrs.UnderlineStyle: Integer;
begin
  if UrlId <> 0 then
    Exit(Ord(tusDashed));                  { always the URL style }
  Result := (RawExt and TyTermExtUnderlineStyle) shr 26;
end;

procedure TTyTerminalExtAttrs.SetUnderlineStyle(AValue: Integer);
begin
  RawExt := (RawExt and not Cardinal(TyTermExtUnderlineStyle))
    or ((Cardinal(AValue) shl 26) and TyTermExtUnderlineStyle);
end;

function TTyTerminalExtAttrs.UnderlineColor: Cardinal;
begin
  Result := RawExt and (TyTermAttrCmMask or TyTermAttrRgbMask);
end;

procedure TTyTerminalExtAttrs.SetUnderlineColor(AValue: Integer);
begin
  RawExt := (RawExt and not Cardinal(TyTermAttrCmMask or TyTermAttrRgbMask))
    or (Cardinal(AValue) and (TyTermAttrCmMask or TyTermAttrRgbMask));
end;

{ (_ext & 0xE0000000) >> 29 is a signed shift upstream: -4..-1 for the high values,
  then ^ 0xFFFFFFF8 (as int32, -8) turns them back into 4..7 }
function TTyTerminalExtAttrs.UnderlineVariantOffset: Integer;
begin
  Result := SarLongint(Integer(RawExt and TyTermExtVariantOffset), 29);
  if Result < 0 then
    Result := Result xor Integer($FFFFFFF8);
end;

procedure TTyTerminalExtAttrs.SetUnderlineVariantOffset(AValue: Integer);
begin
  RawExt := (RawExt and not Cardinal(TyTermExtVariantOffset))
    or ((Cardinal(AValue) shl 29) and TyTermExtVariantOffset);
end;

function TTyTerminalExtAttrs.IsEmpty: Boolean;
begin
  Result := (UnderlineStyle = Ord(tusNone)) and (UrlId = 0);
end;

{ ---- TTyTerminalAttrData (AttributeData.ts:10-133) -------------------------------- }

function TTyTerminalAttrData.IsInverse: Boolean;
begin
  Result := Fg and TyTermFgInverse <> 0;
end;

function TTyTerminalAttrData.IsBold: Boolean;
begin
  Result := Fg and TyTermFgBold <> 0;
end;

function TTyTerminalAttrData.IsUnderline: Boolean;
begin
  if HasExtendedAttrs and (Extended.UnderlineStyle <> Ord(tusNone)) then
    Exit(True);
  Result := Fg and TyTermFgUnderline <> 0;
end;

function TTyTerminalAttrData.IsBlink: Boolean;
begin
  Result := Fg and TyTermFgBlink <> 0;
end;

function TTyTerminalAttrData.IsInvisible: Boolean;
begin
  Result := Fg and TyTermFgInvisible <> 0;
end;

function TTyTerminalAttrData.IsItalic: Boolean;
begin
  Result := Bg and TyTermBgItalic <> 0;
end;

function TTyTerminalAttrData.IsDim: Boolean;
begin
  Result := Bg and TyTermBgDim <> 0;
end;

function TTyTerminalAttrData.IsStrikethrough: Boolean;
begin
  Result := Fg and TyTermFgStrikethrough <> 0;
end;

function TTyTerminalAttrData.IsProtected: Boolean;
begin
  Result := Bg and TyTermBgProtected <> 0;
end;

function TTyTerminalAttrData.IsOverline: Boolean;
begin
  Result := Bg and TyTermBgOverline <> 0;
end;

function TTyTerminalAttrData.GetFgColorMode: Cardinal;
begin
  Result := Fg and TyTermAttrCmMask;
end;

function TTyTerminalAttrData.GetBgColorMode: Cardinal;
begin
  Result := Bg and TyTermAttrCmMask;
end;

function TTyTerminalAttrData.IsFgRGB: Boolean;
begin
  Result := Fg and TyTermAttrCmMask = TyTermAttrCmRgb;
end;

function TTyTerminalAttrData.IsBgRGB: Boolean;
begin
  Result := Bg and TyTermAttrCmMask = TyTermAttrCmRgb;
end;

function TTyTerminalAttrData.IsFgPalette: Boolean;
begin
  Result := (Fg and TyTermAttrCmMask = TyTermAttrCmP16) or (Fg and TyTermAttrCmMask = TyTermAttrCmP256);
end;

function TTyTerminalAttrData.IsBgPalette: Boolean;
begin
  Result := (Bg and TyTermAttrCmMask = TyTermAttrCmP16) or (Bg and TyTermAttrCmMask = TyTermAttrCmP256);
end;

function TTyTerminalAttrData.IsFgDefault: Boolean;
begin
  Result := Fg and TyTermAttrCmMask = 0;
end;

function TTyTerminalAttrData.IsBgDefault: Boolean;
begin
  Result := Bg and TyTermAttrCmMask = 0;
end;

function TTyTerminalAttrData.IsAttributeDefault: Boolean;
begin
  Result := (Fg = 0) and (Bg = 0);
end;

function TTyTerminalAttrData.GetFgColor: Integer;
begin
  case Fg and TyTermAttrCmMask of
    TyTermAttrCmP16, TyTermAttrCmP256: Result := Fg and TyTermAttrPColorMask;
    TyTermAttrCmRgb: Result := Fg and TyTermAttrRgbMask;
  else
    Result := -1;
  end;
end;

function TTyTerminalAttrData.GetBgColor: Integer;
begin
  case Bg and TyTermAttrCmMask of
    TyTermAttrCmP16, TyTermAttrCmP256: Result := Bg and TyTermAttrPColorMask;
    TyTermAttrCmRgb: Result := Bg and TyTermAttrRgbMask;
  else
    Result := -1;
  end;
end;

function TTyTerminalAttrData.HasExtendedAttrs: Boolean;
begin
  Result := Bg and TyTermBgHasExtended <> 0;
end;

procedure TTyTerminalAttrData.UpdateExtended;
begin
  if Extended.IsEmpty then
    Bg := Bg and not Cardinal(TyTermBgHasExtended)
  else
    Bg := Bg or TyTermBgHasExtended;
end;

{ ~underlineColor: anything but all bits set counts }
function TTyTerminalAttrData.GetUnderlineColor: Integer;
begin
  if HasExtendedAttrs and (Extended.UnderlineColor <> $FFFFFFFF) then
    case Extended.UnderlineColor and TyTermAttrCmMask of
      TyTermAttrCmP16, TyTermAttrCmP256: Exit(Extended.UnderlineColor and TyTermAttrPColorMask);
      TyTermAttrCmRgb: Exit(Extended.UnderlineColor and TyTermAttrRgbMask);
    else
      Exit(GetFgColor);
    end;
  Result := GetFgColor;
end;

function TTyTerminalAttrData.GetUnderlineColorMode: Cardinal;
begin
  if HasExtendedAttrs and (Extended.UnderlineColor <> $FFFFFFFF) then
    Result := Extended.UnderlineColor and TyTermAttrCmMask
  else
    Result := GetFgColorMode;
end;

function TTyTerminalAttrData.GetUnderlineStyle: Integer;
begin
  if Fg and TyTermFgUnderline <> 0 then
  begin
    if HasExtendedAttrs then
      Result := Extended.UnderlineStyle
    else
      Result := Ord(tusSingle);
  end
  else
    Result := Ord(tusNone);
end;

function TTyTerminalAttrData.GetUnderlineVariantOffset: Integer;
begin
  Result := Extended.UnderlineVariantOffset;
end;

{ ---- TTyTerminalCellData (CellData.ts) -------------------------------------------- }

function TTyTerminalCellData.Width: Integer;
begin
  Result := Content shr TyTermContentWidthShift;
end;

function TTyTerminalCellData.IsCombined: Boolean;
begin
  Result := Content and TyTermContentIsCombinedMask <> 0;
end;

function TTyTerminalCellData.Chars: string;
begin
  if IsCombined then
    Exit(Combined);
  if Content and TyTermContentCodepointMask <> 0 then
    Exit(CpToUtf8(Content and TyTermContentCodepointMask));
  Result := '';
end;

function TTyTerminalCellData.AsAttr: TTyTerminalAttrData;
begin
  Result.Fg := Fg;
  Result.Bg := Bg;
  Result.Extended := Ext;
end;

function TyTermCellFromCodepoint(ACode: Cardinal; AWidth: Integer; const AAttr: TTyTerminalAttrData): TTyTerminalCellData;
begin
  Result.Content := ACode or (Cardinal(AWidth) shl TyTermContentWidthShift);
  Result.Fg := AAttr.Fg;
  Result.Bg := AAttr.Bg;
  Result.Ext := AAttr.Extended;
  Result.Combined := '';
end;

function TyTermNullCell(const AAttr: TTyTerminalAttrData): TTyTerminalCellData;
begin
  Result := TyTermCellFromCodepoint(TyTermNullCellCode, TyTermNullCellWidth, AAttr);
end;

function TyTermWhitespaceCell(const AAttr: TTyTerminalAttrData): TTyTerminalCellData;
begin
  Result := TyTermCellFromCodepoint(TyTermWhitespaceCellCode, 1, AAttr);
end;

{ ---- TTyTerminalLine (BufferLine.ts) ---------------------------------------------- }

constructor TTyTerminalLine.Create(ACols: Integer; const AFill: TTyTerminalCellData; AIsWrapped: Boolean);
var
  i: Integer;
begin                                                                        { :82-93 }
  inherited Create;
  Inc(GLiveCount);
  FRefCount := 1;
  FIsWrapped := AIsWrapped;
  if ACols < 0 then
    ACols := 0;
  SetLength(FData, ACols * 3);
  FLength := ACols;
  for i := 0 to ACols - 1 do
    SetCell(i, AFill);
end;

constructor TTyTerminalLine.CreateDefault(ACols: Integer; AIsWrapped: Boolean);
begin
  Create(ACols, TyTermNullCell(TyTermDefaultAttr), AIsWrapped);
end;

destructor TTyTerminalLine.Destroy;
begin
  Dec(GLiveCount);
  inherited Destroy;
end;

procedure TTyTerminalLine.AddRef;
begin
  Inc(FRefCount);
end;

procedure TTyTerminalLine.Release;
begin
  Dec(FRefCount);
  if FRefCount <= 0 then
    Free;
end;

class function TTyTerminalLine.LiveCount: Integer;
begin
  Result := GLiveCount;
end;

function TTyTerminalLine.Word0(ACol: Integer): Cardinal;
begin
  { outside the view a typed array reads undefined, which every caller turns into 0 }
  if (ACol < 0) or (ACol >= FLength) then
    Result := 0
  else
    Result := FData[ACol * 3];
end;

function TTyTerminalLine.CombinedIndex(ACol: Integer; out AIndex: Integer): Boolean;
var
  lo, hi, mid: Integer;
begin
  lo := 0;
  hi := FCombinedCount - 1;
  while lo <= hi do
  begin
    mid := (lo + hi) shr 1;
    if FCombined[mid].Col = ACol then
    begin
      AIndex := mid;
      Exit(True);
    end;
    if FCombined[mid].Col < ACol then lo := mid + 1 else hi := mid - 1;
  end;
  AIndex := lo;
  Result := False;
end;

function TTyTerminalLine.ExtendedIndex(ACol: Integer; out AIndex: Integer): Boolean;
var
  lo, hi, mid: Integer;
begin
  lo := 0;
  hi := FExtendedCount - 1;
  while lo <= hi do
  begin
    mid := (lo + hi) shr 1;
    if FExtended[mid].Col = ACol then
    begin
      AIndex := mid;
      Exit(True);
    end;
    if FExtended[mid].Col < ACol then lo := mid + 1 else hi := mid - 1;
  end;
  AIndex := lo;
  Result := False;
end;

procedure TTyTerminalLine.PutCombined(ACol: Integer; const AText: string);
var
  i, k: Integer;
begin
  if not CombinedIndex(ACol, i) then
  begin
    if FCombinedCount = System.Length(FCombined) then
      SetLength(FCombined, FCombinedCount * 2 + 2);
    for k := FCombinedCount downto i + 1 do
      FCombined[k] := FCombined[k - 1];
    FCombined[i].Col := ACol;
    Inc(FCombinedCount);
  end;
  FCombined[i].Text := AText;
end;

procedure TTyTerminalLine.PutExtended(ACol: Integer; const AExt: TTyTerminalExtAttrs);
var
  i, k: Integer;
begin
  if not ExtendedIndex(ACol, i) then
  begin
    if FExtendedCount = System.Length(FExtended) then
      SetLength(FExtended, FExtendedCount * 2 + 2);
    for k := FExtendedCount downto i + 1 do
      FExtended[k] := FExtended[k - 1];
    FExtended[i].Col := ACol;
    Inc(FExtendedCount);
  end;
  FExtended[i].Ext := AExt;
end;

procedure TTyTerminalLine.ClearSparse;
begin
  FCombined := nil;
  FCombinedCount := 0;
  FExtended := nil;
  FExtendedCount := 0;
end;

function TTyTerminalLine.CombinedEntry(ACol: Integer; out AText: string): Boolean;
var
  i: Integer;
begin
  Result := CombinedIndex(ACol, i);
  if Result then
    AText := FCombined[i].Text
  else
    AText := '';
end;

function TTyTerminalLine.ExtendedEntry(ACol: Integer; out AExt: TTyTerminalExtAttrs): Boolean;
var
  i: Integer;
begin
  Result := ExtendedIndex(ACol, i);
  if Result then
    AExt := FExtended[i].Ext
  else
  begin
    AExt.RawExt := 0;
    AExt.UrlId := 0;
  end;
end;

function TTyTerminalLine.GetWidth(ACol: Integer): Integer;
begin
  Result := Word0(ACol) shr TyTermContentWidthShift;
end;

function TTyTerminalLine.HasWidth(ACol: Integer): Boolean;
begin
  Result := Word0(ACol) and TyTermContentWidthMask <> 0;
end;

function TTyTerminalLine.GetFg(ACol: Integer): Cardinal;
begin
  if (ACol < 0) or (ACol >= FLength) then Exit(0);
  Result := FData[ACol * 3 + 1];
end;

function TTyTerminalLine.GetBg(ACol: Integer): Cardinal;
begin
  if (ACol < 0) or (ACol >= FLength) then Exit(0);
  Result := FData[ACol * 3 + 2];
end;

function TTyTerminalLine.GetContent(ACol: Integer): Cardinal;
begin
  Result := Word0(ACol);
end;

function TTyTerminalLine.HasContent(ACol: Integer): Boolean;
begin
  Result := Word0(ACol) and TyTermContentHasContentMask <> 0;
end;

function TTyTerminalLine.GetCodePoint(ACol: Integer): Cardinal;              { :166-172 }
var
  s: string;
  cps: TIntegerDynArray;
  c: Cardinal;
begin
  if Word0(ACol) and TyTermContentIsCombinedMask <> 0 then
  begin
    CombinedEntry(ACol, s);
    cps := TyTermUtf8Codepoints(s);
    if System.Length(cps) = 0 then
      Exit(0);
    c := Cardinal(cps[High(cps)]);
    if c > $FFFF then                      { charCodeAt(length - 1): the low surrogate }
      c := $DC00 + ((c - $10000) and $3FF);
    Exit(c);
  end;
  Result := Word0(ACol) and TyTermContentCodepointMask;
end;

function TTyTerminalLine.IsCombined(ACol: Integer): Boolean;
begin
  Result := Word0(ACol) and TyTermContentIsCombinedMask <> 0;
end;

function TTyTerminalLine.GetChars(ACol: Integer): string;                    { :180-190 }
var
  content: Cardinal;
begin
  content := Word0(ACol);
  if content and TyTermContentIsCombinedMask <> 0 then
  begin
    CombinedEntry(ACol, Result);
    Exit;
  end;
  if content and TyTermContentCodepointMask <> 0 then
    Exit(CpToUtf8(content and TyTermContentCodepointMask));
  Result := '';
end;

function TTyTerminalLine.IsProtected(ACol: Integer): Boolean;
begin
  Result := GetBg(ACol) and TyTermBgProtected <> 0;
end;

procedure TTyTerminalLine.LoadCell(ACol: Integer; var ACell: TTyTerminalCellData);
begin                                                                        { :201-213 }
  ACell.Content := Word0(ACol);
  ACell.Fg := GetFg(ACol);
  ACell.Bg := GetBg(ACol);
  if ACell.Content and TyTermContentIsCombinedMask <> 0 then
    CombinedEntry(ACol, ACell.Combined)
  else
    ACell.Combined := '';
  ACell.Ext := GetExtended(ACol);
end;

function TTyTerminalLine.GetExtended(ACol: Integer): TTyTerminalExtAttrs;   { :215-228 }
begin
  if GetBg(ACol) and TyTermBgHasExtended <> 0 then
    ExtendedEntry(ACol, Result)
  else
  begin
    Result.RawExt := 0;
    Result.UrlId := 0;
  end;
end;

procedure TTyTerminalLine.SetCell(ACol: Integer; const ACell: TTyTerminalCellData);
begin                                                                        { :233-244 }
  FCacheValid := False;
  if (ACol < 0) or (ACol >= FLength) then
    Exit;                                  { a typed array ignores the write }
  if ACell.Content and TyTermContentIsCombinedMask <> 0 then
    PutCombined(ACol, ACell.Combined);
  if ACell.Bg and TyTermBgHasExtended <> 0 then
    PutExtended(ACol, ACell.Ext);
  FData[ACol * 3] := ACell.Content;
  FData[ACol * 3 + 1] := ACell.Fg;
  FData[ACol * 3 + 2] := ACell.Bg;
end;

procedure TTyTerminalLine.PutCp(ACol: Integer; ACodepoint: Cardinal; AWidth: Integer;
  AFg, ABg: Cardinal; const AExt: TTyTerminalExtAttrs);
begin                                                                        { :251-260 }
  FCacheValid := False;
  if (ACol < 0) or (ACol >= FLength) then
    Exit;
  if ABg and TyTermBgHasExtended <> 0 then
    PutExtended(ACol, AExt);
  FData[ACol * 3] := ACodepoint or (Cardinal(AWidth) shl TyTermContentWidthShift);
  FData[ACol * 3 + 1] := AFg;
  FData[ACol * 3 + 2] := ABg;
end;

procedure TTyTerminalLine.SetCellFromCodepoint(ACol: Integer; ACodepoint: Cardinal; AWidth: Integer;
  const AAttrs: TTyTerminalAttrData);
begin
  PutCp(ACol, ACodepoint, AWidth, AAttrs.Fg, AAttrs.Bg, AAttrs.Extended);
end;

procedure TTyTerminalLine.AddCodepointToCell(ACol: Integer; ACodepoint: Cardinal; AWidth: Integer);
var
  content: Cardinal;
  s: string;
begin                                                                        { :268-293 }
  FCacheValid := False;
  if (ACol < 0) or (ACol >= FLength) then
    Exit;
  content := FData[ACol * 3];
  if content and TyTermContentIsCombinedMask <> 0 then
  begin
    { already combined: append }
    CombinedEntry(ACol, s);
    PutCombined(ACol, s + CpToUtf8(ACodepoint));
  end
  else
  begin
    if content and TyTermContentCodepointMask <> 0 then
    begin
      { the leading character and the new one become the combined text }
      PutCombined(ACol, CpToUtf8(content and TyTermContentCodepointMask) + CpToUtf8(ACodepoint));
      content := content and not Cardinal(TyTermContentCodepointMask);
      content := content or TyTermContentIsCombinedMask;
    end
    else
      { should not happen upstream: an empty cell, taken with width 1 }
      content := ACodepoint or (Cardinal(1) shl TyTermContentWidthShift);
  end;
  if AWidth <> 0 then
  begin
    content := content and not Cardinal(TyTermContentWidthMask);
    content := content or (Cardinal(AWidth) shl TyTermContentWidthShift);
  end;
  FData[ACol * 3] := content;
end;

procedure TTyTerminalLine.InsertCells(APos: Integer; ACount: Int64; const AFill: TTyTerminalCellData);
var
  i: Integer;
  n: Integer;
  cell: TTyTerminalCellData;
begin                                                                        { :295-321 }
  FCacheValid := False;
  if FLength = 0 then
    Exit;                                  { pos % 0 is NaN upstream: nothing is written }
  APos := APos mod FLength;
  { pos on the second cell of a wide character: reset the first }
  if (APos <> 0) and (GetWidth(APos - 1) = 2) then
    PutCp(APos - 1, 0, 1, AFill.Fg, AFill.Bg, AFill.Ext);
  if ACount < Int64(FLength) - APos then
  begin
    n := Integer(ACount);
    for i := FLength - APos - n - 1 downto 0 do
    begin
      LoadCell(APos + i, cell);
      SetCell(APos + n + i, cell);
    end;
    for i := 0 to n - 1 do
      SetCell(APos + i, AFill);
  end
  else
    for i := APos to FLength - 1 do
      SetCell(i, AFill);
  { a wide character pushed into the last cell cannot stay }
  if GetWidth(FLength - 1) = 2 then
    PutCp(FLength - 1, 0, 1, AFill.Fg, AFill.Bg, AFill.Ext);
end;

procedure TTyTerminalLine.DeleteCells(APos: Integer; ACount: Int64; const AFill: TTyTerminalCellData);
var
  i, n: Integer;
  cell: TTyTerminalCellData;
begin                                                                        { :323-348 }
  FCacheValid := False;
  if FLength = 0 then
    Exit;
  APos := APos mod FLength;
  if ACount < Int64(FLength) - APos then
  begin
    n := Integer(ACount);
    for i := 0 to FLength - APos - n - 1 do
    begin
      LoadCell(APos + n + i, cell);
      SetCell(APos + i, cell);
    end;
    for i := FLength - n to FLength - 1 do
      SetCell(i, AFill);
  end
  else
    for i := APos to FLength - 1 do
      SetCell(i, AFill);
  { pos - 1 left as the first half of a wide character, pos as a lone second half }
  if (APos <> 0) and (GetWidth(APos - 1) = 2) then
    PutCp(APos - 1, 0, 1, AFill.Fg, AFill.Bg, AFill.Ext);
  if (GetWidth(APos) = 0) and not HasContent(APos) then
    PutCp(APos, 0, 1, AFill.Fg, AFill.Bg, AFill.Ext);
end;

procedure TTyTerminalLine.ReplaceCells(AStart: Integer; AEnd: Int64; const AFill: TTyTerminalCellData;
  ARespectProtect: Boolean);
begin                                                                        { :350-381 }
  FCacheValid := False;
  if ARespectProtect then
  begin
    if (AStart <> 0) and (GetWidth(AStart - 1) = 2) and not IsProtected(AStart - 1) then
      PutCp(AStart - 1, 0, 1, AFill.Fg, AFill.Bg, AFill.Ext);
    if (AEnd < FLength) and (GetWidth(Integer(AEnd) - 1) = 2) and not IsProtected(Integer(AEnd)) then
      PutCp(Integer(AEnd), 0, 1, AFill.Fg, AFill.Bg, AFill.Ext);
    while (AStart < AEnd) and (AStart < FLength) do
    begin
      if not IsProtected(AStart) then
        SetCell(AStart, AFill);
      Inc(AStart);
    end;
    Exit;
  end;
  { start on the second half of a wide character: reset the first }
  if (AStart <> 0) and (GetWidth(AStart - 1) = 2) then
    PutCp(AStart - 1, 0, 1, AFill.Fg, AFill.Bg, AFill.Ext);
  { end on the second half of a wide character: reset that half }
  if (AEnd < FLength) and (GetWidth(Integer(AEnd) - 1) = 2) then
    PutCp(Integer(AEnd), 0, 1, AFill.Fg, AFill.Bg, AFill.Ext);
  while (AStart < AEnd) and (AStart < FLength) do
  begin
    SetCell(AStart, AFill);
    Inc(AStart);
  end;
end;

{ The answer is upstream's "would cleanupMemory free anything" over the size of the
  allocation (its ArrayBuffer): a shrink keeps the allocation, a grow reuses it when
  it is big enough. Upstream schedules a clean-up from it (_memoryCleanupQueue);
  that is a memory optimisation with nothing observable and is not ported. }
function TTyTerminalLine.Resize(ACols: Integer; const AFill: TTyTerminalCellData): Boolean;
var
  cells, i, k, oldLength: Integer;
begin                                                                        { :390-431 }
  FCacheValid := False;
  if ACols = FLength then
    Exit(Int64(FLength) * 3 * 4 * 2 < Int64(System.Length(FData)) * 4);
  cells := ACols * 3;
  if ACols > FLength then
  begin
    if System.Length(FData) < cells then
      SetLength(FData, cells);             { the slow path: a new allocation, data copied }
    oldLength := FLength;
    FLength := ACols;
    for i := oldLength to ACols - 1 do
      SetCell(i, AFill);
  end
  else
  begin
    FLength := ACols;
    { drop cut-off combined text and extended attributes }
    k := 0;
    for i := 0 to FCombinedCount - 1 do
      if FCombined[i].Col < ACols then
      begin
        FCombined[k] := FCombined[i];
        Inc(k);
      end;
    for i := k to FCombinedCount - 1 do
      FCombined[i].Text := '';
    FCombinedCount := k;
    k := 0;
    for i := 0 to FExtendedCount - 1 do
      if FExtended[i].Col < ACols then
      begin
        FExtended[k] := FExtended[i];
        Inc(k);
      end;
    FExtendedCount := k;
  end;
  Result := Int64(cells) * 4 * 2 < Int64(System.Length(FData)) * 4;
end;

procedure TTyTerminalLine.Fill(const AFill: TTyTerminalCellData; ARespectProtect: Boolean);
var
  i: Integer;
begin                                                                        { :450-466 }
  FCacheValid := False;
  if ARespectProtect then
  begin
    for i := 0 to FLength - 1 do
      if not IsProtected(i) then
        SetCell(i, AFill);
    Exit;
  end;
  ClearSparse;
  for i := 0 to FLength - 1 do
    SetCell(i, AFill);
end;

procedure TTyTerminalLine.CopyCellMapsFrom(ASrc: TTyTerminalLine; ASrcCol, ADestCol: Integer);
var
  s: string;
  e: TTyTerminalExtAttrs;
begin                                                                        { :600-608 }
  if ASrc.Word0(ASrcCol) and TyTermContentIsCombinedMask <> 0 then
  begin
    ASrc.CombinedEntry(ASrcCol, s);
    PutCombined(ADestCol, s);
  end;
  if ASrc.GetBg(ASrcCol) and TyTermBgHasExtended <> 0 then
  begin
    ASrc.ExtendedEntry(ASrcCol, e);
    PutExtended(ADestCol, e);
  end;
end;

procedure TTyTerminalLine.CopySparseMapsFrom(ALine: TTyTerminalLine);
var
  i: Integer;
begin                                                                        { :611-617 }
  ClearSparse;
  for i := 0 to ALine.FLength - 1 do
    CopyCellMapsFrom(ALine, i, i);
end;

procedure TTyTerminalLine.CopyFrom(ALine: TTyTerminalLine; ABlank: Boolean);
begin                                                                        { :469-488 }
  if ALine = Self then
  begin
    { upstream empties its maps before copying them from the line -- itself -- so
      they end up empty either way }
    ClearSparse;
    FCache := '';
    FCacheValid := False;
    Exit;
  end;
  if FLength <> ALine.FLength then
    FData := Copy(ALine.FData, 0, ALine.FLength * 3)     { a new allocation of that size }
  else if FLength > 0 then
    Move(ALine.FData[0], FData[0], FLength * 3 * SizeOf(Cardinal));
  FLength := ALine.FLength;
  if ABlank then
    ClearSparse                            { a blank line never holds either }
  else
    CopySparseMapsFrom(ALine);
  FCache := '';
  FCacheValid := False;
  FIsWrapped := ALine.FIsWrapped;
end;

function TTyTerminalLine.Clone(ABlank: Boolean): TTyTerminalLine;
begin                                                                        { :491-502 }
  Result := TTyTerminalLine.CreateDefault(0);
  Result.FData := Copy(FData, 0, FLength * 3);
  Result.FLength := FLength;
  if not ABlank then
    Result.CopySparseMapsFrom(Self);
  Result.FIsWrapped := FIsWrapped;
end;

function TTyTerminalLine.GetTrimmedLength: Integer;
var
  i: Integer;
begin                                                                        { :504-511 }
  for i := FLength - 1 downto 0 do
    if FData[i * 3] and TyTermContentHasContentMask <> 0 then
      Exit(i + Integer(FData[i * 3] shr TyTermContentWidthShift));
  Result := 0;
end;

function TTyTerminalLine.GetNoBgTrimmedLength: Integer;
var
  i: Integer;
begin                                                                        { :513-520 }
  for i := FLength - 1 downto 0 do
    if (FData[i * 3] and TyTermContentHasContentMask <> 0) or (FData[i * 3 + 2] and TyTermAttrCmMask <> 0) then
      Exit(i + Integer(FData[i * 3] shr TyTermContentWidthShift));
  Result := 0;
end;

procedure TTyTerminalLine.CopyCellsFrom(ASrc: TTyTerminalLine; ASrcCol, ADestCol, ALength: Integer;
  AApplyInReverse: Boolean);

  procedure One(ACell: Integer);
  var
    k, s, d: Integer;
  begin
    for k := 0 to 2 do
    begin
      d := (ADestCol + ACell) * 3 + k;
      s := (ASrcCol + ACell) * 3 + k;
      if (d >= 0) and (d < FLength * 3) then
      begin
        if (s >= 0) and (s < ASrc.FLength * 3) then
          FData[d] := ASrc.FData[s]
        else
          FData[d] := 0;
      end;
    end;
    CopyCellMapsFrom(ASrc, ASrcCol + ACell, ADestCol + ACell);
  end;

var
  c: Integer;
begin                                                                        { :522-540 }
  FCacheValid := False;
  if AApplyInReverse then
    for c := ALength - 1 downto 0 do
      One(c)
  else
    for c := 0 to ALength - 1 do
      One(c);
end;

{ :556-597. The cache is ported: a canonical call with trimRight after an untrimmed
  one answers the cached text through trimEnd(), which also drops written spaces and
  other JavaScript whitespace -- a different answer from the trimmed-length path. }
function TTyTerminalLine.TranslateToString(ATrimRight: Boolean; AStartCol, AEndCol: Integer): string;
var
  isCanonical: Boolean;
  content, cp: Cardinal;
  w: Integer;
  s: string;
begin
  isCanonical := (AStartCol = 0) and (AEndCol = -1);
  if isCanonical and FCacheValid then
  begin
    if ATrimRight then
    begin
      if FCacheTrimmed then Exit(FCache) else Exit(TyTermJsTrimEnd(FCache));
    end;
    if not FCacheTrimmed then
      Exit(FCache);
  end;
  if AEndCol = -1 then
    AEndCol := FLength;
  if ATrimRight and (GetTrimmedLength < AEndCol) then
    AEndCol := GetTrimmedLength;
  Result := '';
  while AStartCol < AEndCol do
  begin
    content := Word0(AStartCol);
    cp := content and TyTermContentCodepointMask;
    if content and TyTermContentIsCombinedMask <> 0 then
    begin
      CombinedEntry(AStartCol, s);
      Result := Result + s;
    end
    else if cp <> 0 then
      Result := Result + CpToUtf8(cp)
    else
      Result := Result + ' ';
    w := content shr TyTermContentWidthShift;
    if w = 0 then
      w := 1;                              { always advance by at least 1 }
    Inc(AStartCol, w);
  end;
  if isCanonical then
  begin
    FCache := Result;
    FCacheValid := True;
    FCacheTrimmed := ATrimRight;
  end;
end;

{ ---- TTyTerminalLineList (CircularList.ts) ---------------------------------------- }

constructor TTyTerminalLineList.Create(AMaxLength: Integer);
begin
  inherited Create;
  FMaxLength := AMaxLength;
  SetLength(FArray, AMaxLength);
end;

destructor TTyTerminalLineList.Destroy;
var
  i: Integer;
begin
  for i := 0 to High(FArray) do
    if FArray[i] <> nil then
      FArray[i].Release;
  inherited Destroy;
end;

function TTyTerminalLineList.Cyclic(AIndex: Int64): Int64;                   { :259-261 }
begin
  if FMaxLength = 0 then
    Exit(-1);
  Result := (FStartIndex + AIndex) mod FMaxLength;   { negative stays negative, as % }
end;

{ The one way into a slot: the new line gains a reference before the old one loses
  its own, so storing a line over itself is safe. }
procedure TTyTerminalLineList.Store(ASlot: Int64; ALine: TTyTerminalLine);
var
  old: TTyTerminalLine;
begin
  if (ASlot < 0) or (ASlot >= System.Length(FArray)) then
    Exit;
  if ALine <> nil then
    ALine.AddRef;
  old := FArray[ASlot];
  FArray[ASlot] := ALine;
  if old <> nil then
    old.Release;
end;

procedure TTyTerminalLineList.DoTrim(AAmount: Integer);
begin
  if Assigned(FOnTrim) then
    FOnTrim(AAmount);
end;

procedure TTyTerminalLineList.SetMaxLength(AValue: Integer);                 { :70-85 }
var
  newArray: array of TTyTerminalLine;
  i, n: Integer;
  slot: Int64;
begin
  if FMaxLength = AValue then
    Exit;
  newArray := nil;
  SetLength(newArray, AValue);
  n := FLength;
  if AValue < n then
    n := AValue;
  for i := 0 to n - 1 do
  begin
    slot := Cyclic(i);
    if slot >= 0 then
    begin
      newArray[i] := FArray[slot];
      if newArray[i] <> nil then
        newArray[i].AddRef;
    end;
  end;
  for i := 0 to High(FArray) do
    if FArray[i] <> nil then
      FArray[i].Release;
  FArray := newArray;
  FMaxLength := AValue;
  FStartIndex := 0;
end;

{ upstream clears the new slots by RAW index, not through the start index }
procedure TTyTerminalLineList.SetLengthValue(AValue: Integer);               { :91-98 }
var
  i: Integer;
begin
  if AValue > FLength then
    for i := FLength to AValue - 1 do
      if i < FMaxLength then
        Store(i, nil);
  FLength := AValue;
end;

function TTyTerminalLineList.GetIsFull: Boolean;
begin
  Result := FLength = FMaxLength;
end;

function TTyTerminalLineList.Get(AIndex: Integer): TTyTerminalLine;          { :108-110 }
var
  slot: Int64;
begin
  slot := Cyclic(AIndex);
  if (slot < 0) or (slot >= System.Length(FArray)) then
    Result := nil
  else
    Result := FArray[slot];
end;

procedure TTyTerminalLineList.SetItem(AIndex: Integer; ALine: TTyTerminalLine);
begin                                                                        { :120-122 }
  Store(Cyclic(AIndex), ALine);
end;

procedure TTyTerminalLineList.SetItemOwned(AIndex: Integer; ALine: TTyTerminalLine);
begin
  SetItem(AIndex, ALine);
  ALine.Release;
end;

procedure TTyTerminalLineList.Push(ALine: TTyTerminalLine);                  { :129-137 }
begin
  Store(Cyclic(FLength), ALine);
  if FLength = FMaxLength then
  begin
    FStartIndex := (FStartIndex + 1) mod FMaxLength;
    DoTrim(1);
  end
  else
    Inc(FLength);
end;

procedure TTyTerminalLineList.PushOwned(ALine: TTyTerminalLine);
begin
  Push(ALine);
  ALine.Release;
end;

function TTyTerminalLineList.Recycle: TTyTerminalLine;                       { :144-151 }
begin
  if FLength <> FMaxLength then
    raise EInvalidOperation.Create('Can only recycle when the buffer is full');
  FStartIndex := (FStartIndex + 1) mod FMaxLength;
  DoTrim(1);
  Result := Get(FLength - 1);
end;

function TTyTerminalLineList.Pop: TTyTerminalLine;                           { :164-166 }
begin
  Result := Get(FLength - 1);
  Dec(FLength);
end;

procedure TTyTerminalLineList.Splice(AStart, ADeleteCount: Integer; const AItems: array of TTyTerminalLine);
var
  i, n, countToTrim: Integer;
begin                                                                        { :177-207 }
  n := System.Length(AItems);
  if ADeleteCount <> 0 then
  begin
    for i := AStart to FLength - ADeleteCount - 1 do
      Store(Cyclic(i), Get(i + ADeleteCount));
    Dec(FLength, ADeleteCount);
    if Assigned(FOnDelete) then
      FOnDelete(AStart, ADeleteCount);
  end;
  for i := FLength - 1 downto AStart do
    Store(Cyclic(i + n), Get(i));
  for i := 0 to n - 1 do
    Store(Cyclic(AStart + i), AItems[i]);
  if (n > 0) and Assigned(FOnInsert) then
    FOnInsert(AStart, n);
  if FLength + n > FMaxLength then
  begin
    countToTrim := FLength + n - FMaxLength;
    Inc(FStartIndex, countToTrim);
    FLength := FMaxLength;
    DoTrim(countToTrim);
  end
  else
    Inc(FLength, n);
end;

procedure TTyTerminalLineList.SpliceOwned(AStart, ADeleteCount: Integer; ALine: TTyTerminalLine);
begin
  Splice(AStart, ADeleteCount, [ALine]);
  ALine.Release;
end;

procedure TTyTerminalLineList.TrimStart(ACount: Integer);                    { :213-220 }
begin
  if ACount > FLength then
    ACount := FLength;
  Inc(FStartIndex, ACount);
  Dec(FLength, ACount);
  DoTrim(ACount);
end;

procedure TTyTerminalLineList.ShiftElements(AStart, ACount, AOffset: Integer);   { :222-251 }
var
  i, expandListBy: Integer;
begin
  if ACount <= 0 then
    Exit;
  if (AStart < 0) or (AStart >= FLength) then
    raise EArgumentOutOfRangeException.Create('start argument out of range');
  if AStart + AOffset < 0 then
    raise EArgumentOutOfRangeException.Create('Cannot shift elements in list beyond index 0');
  if AOffset > 0 then
  begin
    for i := ACount - 1 downto 0 do
      SetItem(AStart + i + AOffset, Get(AStart + i));
    expandListBy := AStart + ACount + AOffset - FLength;
    if expandListBy > 0 then
    begin
      Inc(FLength, expandListBy);
      while FLength > FMaxLength do
      begin
        Dec(FLength);
        Inc(FStartIndex);
        DoTrim(1);
      end;
    end;
  end
  else
    for i := 0 to ACount - 1 do
      SetItem(AStart + i + AOffset, Get(AStart + i));
end;

function TTyTerminalLineList.SlotLine(ASlot: Integer): TTyTerminalLine;
begin
  if (ASlot < 0) or (ASlot > High(FArray)) then
    Result := nil
  else
    Result := FArray[ASlot];
end;

{ ---- TTyTerminalMarker (Marker.ts) ------------------------------------------------ }

constructor TTyTerminalMarker.Create(ALine: Integer);
begin
  inherited Create;
  Inc(GNextId);
  FId := GNextId;
  FLine := ALine;
  FRefCount := 1;
end;

procedure TTyTerminalMarker.AddRef;
begin
  Inc(FRefCount);
end;

procedure TTyTerminalMarker.Release;
begin
  Dec(FRefCount);
  if FRefCount <= 0 then
    Free;
end;

procedure TTyTerminalMarker.Dispose;                                         { :27-37 }
var
  snapshot: array of TNotifyEvent;
  i: Integer;
begin
  if FIsDisposed then
    Exit;
  AddRef;                                  { a listener may drop the last other reference }
  try
    FIsDisposed := True;
    FLine := -1;
    snapshot := Copy(FListeners);
    for i := 0 to High(snapshot) do
      snapshot[i](Self);
    FListeners := nil;
  finally
    Release;
  end;
end;

procedure TTyTerminalMarker.AddDisposeListener(AHandler: TNotifyEvent);
begin
  SetLength(FListeners, System.Length(FListeners) + 1);
  FListeners[High(FListeners)] := AHandler;
end;

procedure TTyTerminalMarker.RemoveDisposeListener(AHandler: TNotifyEvent);
var
  i, k: Integer;
begin
  for i := 0 to High(FListeners) do
    if (TMethod(FListeners[i]).Code = TMethod(AHandler).Code)
      and (TMethod(FListeners[i]).Data = TMethod(AHandler).Data) then
    begin
      for k := i to High(FListeners) - 1 do
        FListeners[k] := FListeners[k + 1];
      SetLength(FListeners, System.Length(FListeners) - 1);
      Exit;
    end;
end;

{ ---- TTyTerminalOptions ----------------------------------------------------------- }

constructor TTyTerminalOptions.Create;
begin
  inherited Create;
  Scrollback := 1000;
  TabStopWidth := 8;
  ScrollOnUserInput := True;
  CursorStyle := tcoBlock;
end;

{ ---- TTyTerminalBuffer (Buffer.ts) ------------------------------------------------ }

constructor TTyTerminalBuffer.Create(AHasScrollback: Boolean; AOptions: TTyTerminalOptions;
  AService: TTyTerminalBufferService);
begin                                                                        { :55-71 }
  inherited Create;
  FHasScrollback := AHasScrollback;
  FOptions := AOptions;
  FService := AService;
  FCols := AService.Cols;
  FRows := AService.Rows;
  FMarkers := TFPList.Create;
  SavedAttr := TyTermDefaultAttr;
  SavedWraparoundMode := True;
  NewLines;
  FScrollTop := 0;
  FScrollBottom := FRows - 1;
  SetupTabStops;
end;

destructor TTyTerminalBuffer.Destroy;
begin
  ClearAllMarkers;                         { upstream disposes them with the buffer }
  FMarkers.Free;
  FLines.Free;
  inherited Destroy;
end;

procedure TTyTerminalBuffer.NewLines;
begin
  FLines.Free;
  FLines := TTyTerminalLineList.Create(GetCorrectBufferLength(FRows));
  FLines.OnTrim := @LinesTrim;
  FLines.OnInsert := @LinesInsert;
  FLines.OnDelete := @LinesDelete;
  { markers made before now listened to the old list upstream and stop moving }
  Inc(FGeneration);
end;

function TTyTerminalBuffer.GetCorrectBufferLength(ARows: Integer): Integer;  { :118-126 }
var
  n: Int64;
begin
  if not FHasScrollback then
    Exit(ARows);
  n := Int64(ARows) + FOptions.Scrollback;
  if n > High(Integer) then
    n := High(Integer);
  Result := Integer(n);
end;

function TTyTerminalBuffer.GetNullCell: TTyTerminalCellData;
begin
  Result := TyTermNullCell(TyTermDefaultAttr);
end;

function TTyTerminalBuffer.GetNullCell(const AAttr: TTyTerminalAttrData): TTyTerminalCellData;
begin
  Result := TyTermNullCell(AAttr);
end;

function TTyTerminalBuffer.GetWhitespaceCell: TTyTerminalCellData;
begin
  Result := TyTermWhitespaceCell(TyTermDefaultAttr);
end;

function TTyTerminalBuffer.GetWhitespaceCell(const AAttr: TTyTerminalAttrData): TTyTerminalCellData;
begin
  Result := TyTermWhitespaceCell(AAttr);
end;

function TTyTerminalBuffer.GetBlankLine(const AAttr: TTyTerminalAttrData; AIsWrapped: Boolean): TTyTerminalLine;
begin                                                                        { :99-101 }
  Result := TTyTerminalLine.Create(FService.Cols, TyTermNullCell(AAttr), AIsWrapped);
end;

function TTyTerminalBuffer.GetHasScrollback: Boolean;
begin
  Result := FHasScrollback and (FLines.MaxLength > FRows);
end;

function TTyTerminalBuffer.GetIsCursorInViewport: Boolean;
var
  rel: Integer;
begin
  rel := FYBase + FY - FYDisp;
  Result := (rel >= 0) and (rel < FRows);
end;

function TTyTerminalBuffer.GetMarker(AIndex: Integer): TTyTerminalMarker;
begin
  Result := TTyTerminalMarker(FMarkers[AIndex]);
end;

function TTyTerminalBuffer.GetMarkerCount: Integer;
begin
  Result := FMarkers.Count;
end;

function TTyTerminalBuffer.GetLength: Integer;
begin
  Result := FLines.Length;
end;

{ Phase 5: with windowsPty.buildNumber given, hasScrollback and conpty and
  >= 21376, otherwise hasScrollback (Buffer.ts:310-316); then Resize runs
  _reflow and trims the lines (:258-268). Until then it is the path upstream takes
  for an old ConPTY. }
function TTyTerminalBuffer.GetIsReflowEnabled: Boolean;
begin
  Result := False;
end;

function TTyTerminalBuffer.GetLine(AAbsRow: Integer): TTyTerminalLine;
begin
  Result := FLines.Get(AAbsRow);
end;

procedure TTyTerminalBuffer.FillViewportRows;
begin
  FillViewportRows(TyTermDefaultAttr);
end;

procedure TTyTerminalBuffer.FillViewportRows(const AAttr: TTyTerminalAttrData);
var
  i: Integer;
begin                                                                        { :131-139 }
  if FLines.Length = 0 then
    for i := 1 to FRows do
      FLines.PushOwned(GetBlankLine(AAttr));
end;

procedure TTyTerminalBuffer.Clear;                                           { :144-153 }
begin
  FYDisp := 0;
  FYBase := 0;
  FY := 0;
  FX := 0;
  NewLines;
  FScrollTop := 0;
  FScrollBottom := FRows - 1;
  SetupTabStops;
end;

procedure TTyTerminalBuffer.Resize(ANewCols, ANewRows: Integer);             { :160-286 }
var
  nullCell: TTyTerminalCellData;
  newMaxLength, i, row, addToY, amountToTrim, maxY: Integer;
  windows: Boolean;
begin
  nullCell := GetNullCell(TyTermDefaultAttr);
  { grow the ring first, so there is room for what follows }
  newMaxLength := GetCorrectBufferLength(ANewRows);
  if newMaxLength > FLines.MaxLength then
    FLines.MaxLength := newMaxLength;
  if FLines.Length > 0 then
  begin
    { wider: every line now (narrower waits for the reflow, which phase 2 lacks) }
    if FCols < ANewCols then
      for i := 0 to FLines.Length - 1 do
        FLines.Get(i).Resize(ANewCols, nullCell);
    addToY := 0;
    if FRows < ANewRows then
    begin
      windows := (FOptions.WindowsPty.Backend <> twpNone) or (FOptions.WindowsPty.BuildNumber <> 0);
      for row := FRows to ANewRows - 1 do
        if FLines.Length < ANewRows + FYBase then
        begin
          if windows then
            { conpty reprints the screen; once in the scrollback a line stays there }
            FLines.PushOwned(TTyTerminalLine.Create(ANewCols, nullCell, False))
          else if (FYBase > 0) and (FLines.Length <= FYBase + FY + addToY + 1) then
          begin
            { room above and no empty line below the cursor: scroll up }
            Dec(FYBase);
            Inc(addToY);
            if FYDisp > 0 then
              Dec(FYDisp);
          end
          else
            FLines.PushOwned(TTyTerminalLine.Create(ANewCols, nullCell, False));
        end;
    end
    else
      for row := FRows downto ANewRows + 1 do
        if FLines.Length > ANewRows + FYBase then
        begin
          if FLines.Length > FYBase + FY + 1 then
            FLines.Pop                     { a blank line below the cursor }
          else
          begin
            Inc(FYBase);                   { the cursor line: scroll down }
            Inc(FYDisp);
          end;
        end;
    { shrink the ring last: trim the top, not the bottom }
    if newMaxLength < FLines.MaxLength then
    begin
      amountToTrim := FLines.Length - newMaxLength;
      if amountToTrim > 0 then
      begin
        FLines.TrimStart(amountToTrim);
        if FYBase - amountToTrim > 0 then FYBase := FYBase - amountToTrim else FYBase := 0;
        if FYDisp - amountToTrim > 0 then FYDisp := FYDisp - amountToTrim else FYDisp := 0;
        if SavedY - amountToTrim > 0 then SavedY := SavedY - amountToTrim else SavedY := 0;
      end;
      FLines.MaxLength := newMaxLength;
    end;
    { keep the cursor on screen }
    if ANewCols - 1 < FX then FX := ANewCols - 1;
    if ANewRows - 1 < FY then FY := ANewRows - 1;
    if addToY <> 0 then
      Inc(FY, addToY);
    if ANewCols - 1 < SavedX then SavedX := ANewCols - 1;
    FScrollTop := 0;
  end;
  FScrollBottom := ANewRows - 1;
  { IsReflowEnabled: always False in phase 2, see GetIsReflowEnabled }
  FCols := ANewCols;
  FRows := ANewRows;
  { ybase + y stays within the lines }
  if FLines.Length > 0 then
  begin
    maxY := FLines.Length - FYBase - 1;
    if maxY < 0 then
      maxY := 0;
    if maxY < FY then
      FY := maxY;
  end;
end;

function TTyTerminalBuffer.TranslateBufferLineToString(AAbsRow: Integer; ATrimRight: Boolean;
  AStartCol, AEndCol: Integer): string;
var
  line: TTyTerminalLine;
begin                                                                        { :549-555 }
  line := FLines.Get(AAbsRow);
  if line = nil then
    Exit('');
  Result := line.TranslateToString(ATrimRight, AStartCol, AEndCol);
end;

function TTyTerminalBuffer.GetWrappedRangeForLine(AAbsRow: Integer; out AFirst, ALast: Integer): Boolean;
var
  line: TTyTerminalLine;
begin                                                                        { :557-569 }
  AFirst := AAbsRow;
  ALast := AAbsRow;
  while AFirst > 0 do
  begin
    line := FLines.Get(AFirst);
    if (line = nil) or not line.IsWrapped then
      Break;
    Dec(AFirst);
  end;
  while ALast + 1 < FLines.Length do
  begin
    line := FLines.Get(ALast + 1);
    if (line = nil) or not line.IsWrapped then
      Break;
    Inc(ALast);
  end;
  Result := True;
end;

function TTyTerminalBuffer.HasTab(ACol: Integer): Boolean;
begin
  Result := (ACol >= 0) and (ACol <= High(FTabs)) and FTabs[ACol];
end;

procedure TTyTerminalBuffer.SetTab(ACol: Integer; AOn: Boolean);
var
  i, old: Integer;
begin
  if ACol < 0 then
    Exit;
  if ACol > High(FTabs) then
  begin
    if not AOn then
      Exit;
    old := System.Length(FTabs);
    SetLength(FTabs, ACol + 1);
    for i := old to ACol do
      FTabs[i] := False;
  end;
  FTabs[ACol] := AOn;
end;

procedure TTyTerminalBuffer.ClearAllTabs;
begin
  FTabs := nil;
end;

function TTyTerminalBuffer.TabStops: TIntegerDynArray;
var
  i, n: Integer;
begin
  Result := nil;
  SetLength(Result, System.Length(FTabs));
  n := 0;
  for i := 0 to High(FTabs) do
    if FTabs[i] then
    begin
      Result[n] := i;
      Inc(n);
    end;
  SetLength(Result, n);
end;

procedure TTyTerminalBuffer.SetupTabStops(AFrom: Integer);                   { :575-588 }
var
  i: Integer;
begin
  if AFrom <> -1 then
  begin
    i := AFrom;
    if not HasTab(i) then
      i := PrevStop(i);
  end
  else
  begin
    ClearAllTabs;
    i := 0;
  end;
  while i < FCols do
  begin
    SetTab(i, True);
    Inc(i, FOptions.TabStopWidth);
  end;
end;

function TTyTerminalBuffer.PrevStop(AX: Integer): Integer;                   { :594-598 }
begin
  if AX = MaxInt then
    AX := FX;
  repeat
    Dec(AX);
    if HasTab(AX) then
      Break;
  until not (AX > 0);
  if AX >= FCols then
    Result := FCols - 1
  else if AX < 0 then
    Result := 0
  else
    Result := AX;
end;

function TTyTerminalBuffer.NextStop(AX: Integer): Integer;                   { :604-608 }
begin
  if AX = MaxInt then
    AX := FX;
  repeat
    Inc(AX);
    if HasTab(AX) then
      Break;
  until not (AX < FCols);
  if AX >= FCols then
    Result := FCols - 1
  else if AX < 0 then
    Result := 0
  else
    Result := AX;
end;

procedure TTyTerminalBuffer.ClearMarkers(AAbsRow: Integer);                  { :614-623 }
var
  i: Integer;
  m: TTyTerminalMarker;
begin
  FIsClearing := True;
  try
    i := 0;
    while i < FMarkers.Count do
    begin
      m := TTyTerminalMarker(FMarkers[i]);
      if m.Line = AAbsRow then
      begin
        m.Dispose;
        FMarkers.Delete(i);
        m.Release;
      end
      else
        Inc(i);
    end;
  finally
    FIsClearing := False;
  end;
end;

procedure TTyTerminalBuffer.ClearAllMarkers;                                 { :628-635 }
var
  i: Integer;
  list: TFPList;
begin
  FIsClearing := True;
  list := TFPList.Create;
  try
    list.Assign(FMarkers);
    for i := 0 to list.Count - 1 do
      TTyTerminalMarker(list[i]).Dispose;
    FMarkers.Clear;
    for i := 0 to list.Count - 1 do
      TTyTerminalMarker(list[i]).Release;
  finally
    list.Free;
    FIsClearing := False;
  end;
end;

function TTyTerminalBuffer.AddMarker(AAbsRow: Integer): TTyTerminalMarker;   { :637-665 }
begin
  Result := TTyTerminalMarker.Create(AAbsRow);  { the buffer's reference }
  Result.FGeneration := FGeneration;
  FMarkers.Add(Result);
  Result.AddDisposeListener(@MarkerDisposed);
end;

procedure TTyTerminalBuffer.MarkerDisposed(Sender: TObject);                 { :667-671 }
var
  i: Integer;
begin
  if FIsClearing then
    Exit;
  i := FMarkers.IndexOf(Sender);
  if i >= 0 then
  begin
    FMarkers.Delete(i);
    TTyTerminalMarker(Sender).Release;
  end;
end;

{ Upstream's markers each subscribe to the list, in creation order; the buffer runs
  the same handlers over a pinned copy of its live markers. }
function TTyTerminalBuffer.MarkerSnapshot: TFPList;
var
  i: Integer;
begin
  Result := TFPList.Create;
  for i := 0 to FMarkers.Count - 1 do
    if TTyTerminalMarker(FMarkers[i]).FGeneration = FGeneration then
    begin
      Result.Add(FMarkers[i]);
      TTyTerminalMarker(FMarkers[i]).AddRef;
    end;
end;

procedure ReleaseSnapshot(AList: TFPList);
var
  i: Integer;
begin
  for i := 0 to AList.Count - 1 do
    TTyTerminalMarker(AList[i]).Release;
  AList.Free;
end;

procedure TTyTerminalBuffer.LinesTrim(AAmount: Integer);                     { :640-646 }
var
  snap: TFPList;
  i: Integer;
  m: TTyTerminalMarker;
begin
  if FMarkers.Count = 0 then
    Exit;
  snap := MarkerSnapshot;
  try
    for i := 0 to snap.Count - 1 do
    begin
      m := TTyTerminalMarker(snap[i]);
      if m.IsDisposed then
        Continue;
      m.Line := m.Line - AAmount;
      if m.Line < 0 then
        m.Dispose;
    end;
  finally
    ReleaseSnapshot(snap);
  end;
end;

procedure TTyTerminalBuffer.LinesInsert(AIndex, AAmount: Integer);           { :647-651 }
var
  snap: TFPList;
  i: Integer;
  m: TTyTerminalMarker;
begin
  if FMarkers.Count = 0 then
    Exit;
  snap := MarkerSnapshot;
  try
    for i := 0 to snap.Count - 1 do
    begin
      m := TTyTerminalMarker(snap[i]);
      if m.IsDisposed then
        Continue;
      if m.Line >= AIndex then
        m.Line := m.Line + AAmount;
    end;
  finally
    ReleaseSnapshot(snap);
  end;
end;

procedure TTyTerminalBuffer.LinesDelete(AIndex, AAmount: Integer);           { :652-662 }
var
  snap: TFPList;
  i: Integer;
  m: TTyTerminalMarker;
begin
  if FMarkers.Count = 0 then
    Exit;
  snap := MarkerSnapshot;
  try
    for i := 0 to snap.Count - 1 do
    begin
      m := TTyTerminalMarker(snap[i]);
      if m.IsDisposed then
        Continue;
      { inside the deleted range: gone }
      if (m.Line >= AIndex) and (m.Line < AIndex + AAmount) then
        m.Dispose;
      { after it: move up }
      if m.Line > AIndex then
        m.Line := m.Line - AAmount;
    end;
  finally
    ReleaseSnapshot(snap);
  end;
end;

{ ---- TTyTerminalBufferSet (BufferSet.ts) ------------------------------------------ }

constructor TTyTerminalBufferSet.Create(AOptions: TTyTerminalOptions; AService: TTyTerminalBufferService);
begin                                                                        { :29-38 }
  inherited Create;
  FOptions := AOptions;
  FService := AService;
  Reset;
end;

destructor TTyTerminalBufferSet.Destroy;
begin
  FNormal.Free;
  FAlt.Free;
  inherited Destroy;
end;

procedure TTyTerminalBufferSet.Reset;                                        { :40-56 }
var
  old: TTyTerminalBuffer;
begin
  { the old buffer goes as the new one takes its place (MutableDisposable) }
  old := FNormal;
  FNormal := TTyTerminalBuffer.Create(True, FOptions, FService);
  old.Free;
  FNormal.FillViewportRows;
  { the alt buffer never has scrollback }
  old := FAlt;
  FAlt := TTyTerminalBuffer.Create(False, FOptions, FService);
  old.Free;
  FActive := FNormal;
  if Assigned(FOnBufferActivate) then
    FOnBufferActivate(FNormal, FAlt);
  SetupTabStops;
end;

procedure TTyTerminalBufferSet.ActivateNormalBuffer;                         { :82-98 }
begin
  if FActive = FNormal then
    Exit;
  FNormal.X := FAlt.X;
  FNormal.Y := FAlt.Y;
  { the alt buffer is cleared on the way back, it is always new when activated }
  FAlt.ClearAllMarkers;
  FAlt.Clear;
  FActive := FNormal;
  if Assigned(FOnBufferActivate) then
    FOnBufferActivate(FNormal, FAlt);
end;

procedure TTyTerminalBufferSet.ActivateAltBuffer;
begin
  ActivateAltBuffer(TyTermDefaultAttr);
end;

procedure TTyTerminalBufferSet.ActivateAltBuffer(const AFill: TTyTerminalAttrData);
begin                                                                        { :103-117 }
  if FActive = FAlt then
    Exit;
  FAlt.FillViewportRows(AFill);
  FAlt.X := FNormal.X;
  FAlt.Y := FNormal.Y;
  FActive := FAlt;
  if Assigned(FOnBufferActivate) then
    FOnBufferActivate(FAlt, FNormal);
end;

procedure TTyTerminalBufferSet.Resize(ANewCols, ANewRows: Integer);          { :124-128 }
begin
  FNormal.Resize(ANewCols, ANewRows);
  FAlt.Resize(ANewCols, ANewRows);
  SetupTabStops(ANewCols);
end;

procedure TTyTerminalBufferSet.SetupTabStops(AFrom: Integer);
begin
  FNormal.SetupTabStops(AFrom);
  FAlt.SetupTabStops(AFrom);
end;

function TTyTerminalBufferSet.GetIsAlt: Boolean;
begin
  Result := FActive = FAlt;
end;

{ ---- TTyTerminalBufferService (BufferService.ts) ---------------------------------- }

constructor TTyTerminalBufferService.Create(AOptions: TTyTerminalOptions; ACols, ARows: Integer);
begin                                                                        { :36-47 }
  inherited Create;
  FOptions := AOptions;
  if ACols < TyTermMinimumCols then ACols := TyTermMinimumCols;
  if ARows < TyTermMinimumRows then ARows := TyTermMinimumRows;
  FCols := ACols;
  FRows := ARows;
  FBuffers := TTyTerminalBufferSet.Create(AOptions, Self);
  { subscribed after the set's first reset, as upstream }
  FBuffers.OnBufferActivate := @BuffersActivated;
end;

destructor TTyTerminalBufferService.Destroy;
begin
  FBuffers.Free;
  if FCachedBlankLine <> nil then
    FCachedBlankLine.Release;
  inherited Destroy;
end;

procedure TTyTerminalBufferService.BuffersActivated(AActive, AInactive: TTyTerminalBuffer);
begin
  if Assigned(FOnScroll) then
    FOnScroll(AActive.YDisp);
  if Assigned(FOnBufferActivate) then
    FOnBufferActivate(AActive, AInactive);
end;

function TTyTerminalBufferService.GetBuffer: TTyTerminalBuffer;
begin
  Result := FBuffers.Active;
end;

procedure TTyTerminalBufferService.Resize(ACols, ARows: Integer);            { :49-56 }
var
  colsChanged, rowsChanged: Boolean;
begin
  colsChanged := FCols <> ACols;
  rowsChanged := FRows <> ARows;
  FCols := ACols;
  FRows := ARows;
  FBuffers.Resize(ACols, ARows);
  if Assigned(FOnResize) then
    FOnResize(ACols, ARows, colsChanged, rowsChanged);
end;

procedure TTyTerminalBufferService.Reset;                                    { :58-61 }
begin
  FBuffers.Reset;
  FIsUserScrolling := False;
end;

procedure TTyTerminalBufferService.Scroll(const AEraseAttr: TTyTerminalAttrData; AIsWrapped: Boolean);
var
  buf: TTyTerminalBuffer;
  newLine: TTyTerminalLine;
  topRow, bottomRow, h: Integer;
  willTrim: Boolean;
begin                                                                        { :68-126 }
  buf := Buffer;
  newLine := FCachedBlankLine;
  if (newLine = nil) or (newLine.Length <> FCols) or (newLine.GetFg(0) <> AEraseAttr.Fg)
    or (newLine.GetBg(0) <> AEraseAttr.Bg) then
  begin
    newLine := buf.GetBlankLine(AEraseAttr, AIsWrapped);
    if FCachedBlankLine <> nil then
      FCachedBlankLine.Release;
    FCachedBlankLine := newLine;           { the service's reference (pinned) }
  end;
  newLine.IsWrapped := AIsWrapped;
  topRow := buf.YBase + buf.ScrollTop;
  bottomRow := buf.YBase + buf.ScrollBottom;
  if buf.ScrollTop = 0 then
  begin
    willTrim := buf.Lines.IsFull;
    if bottomRow = buf.Lines.Length - 1 then
    begin
      if willTrim then
        buf.Lines.Recycle.CopyFrom(newLine, True)
      else
        buf.Lines.PushOwned(newLine.Clone(True));
    end
    else
      buf.Lines.SpliceOwned(bottomRow + 1, 0, newLine.Clone(True));
    { ybase and ydisp move only while nothing is trimmed }
    if not willTrim then
    begin
      buf.YBase := buf.YBase + 1;
      if not FIsUserScrolling then
        buf.YDisp := buf.YDisp + 1;
    end
    else if FIsUserScrolling then
    begin
      { full and scrolled up: keep the text still unless ydisp is at the top }
      if buf.YDisp - 1 > 0 then buf.YDisp := buf.YDisp - 1 else buf.YDisp := 0;
    end;
  end
  else
  begin
    { a top margin: shift in place, nothing reaches the scrollback }
    h := bottomRow - topRow + 1;
    buf.Lines.ShiftElements(topRow + 1, h - 1, -1);
    buf.Lines.SetItemOwned(bottomRow, newLine.Clone(True));
  end;
  if not FIsUserScrolling then
    buf.YDisp := buf.YBase;
  if Assigned(FOnScroll) then
    FOnScroll(buf.YDisp);
end;

procedure TTyTerminalBufferService.ScrollLines(ADisp: Integer; ASuppressScrollEvent: Boolean);
var
  buf: TTyTerminalBuffer;
  oldYDisp, v: Integer;
begin                                                                        { :135-157 }
  buf := Buffer;
  if ADisp < 0 then
  begin
    if buf.YDisp = 0 then
      Exit;
    FIsUserScrolling := True;
  end
  else if Int64(ADisp) + buf.YDisp >= buf.YBase then
    FIsUserScrolling := False;
  oldYDisp := buf.YDisp;
  v := buf.YDisp + ADisp;
  if v > buf.YBase then v := buf.YBase;
  if v < 0 then v := 0;
  buf.YDisp := v;
  if oldYDisp = buf.YDisp then
    Exit;
  if (not ASuppressScrollEvent) and Assigned(FOnScroll) then
    FOnScroll(buf.YDisp);
end;

procedure TTyTerminalBufferService.ScrollbackChanged;
begin
  FBuffers.Resize(FCols, FRows);
end;

procedure TTyTerminalBufferService.TabStopWidthChanged;
begin
  FBuffers.SetupTabStops;
end;

{ ---- TTyTerminalOscLinks (OscLinkService.ts) -------------------------------------- }

constructor TTyTermLinkEntry.Create;
begin
  inherited Create;
  Markers := TFPList.Create;
end;

destructor TTyTermLinkEntry.Destroy;
begin
  Markers.Free;
  inherited Destroy;
end;

constructor TTyTerminalOscLinks.Create(AService: TTyTerminalBufferService);
begin
  inherited Create;
  FService := AService;
  FNextId := 1;
  FEntries := TFPList.Create;
end;

destructor TTyTerminalOscLinks.Destroy;
var
  i, k: Integer;
  e: TTyTermLinkEntry;
  m: TTyTerminalMarker;
begin
  for i := 0 to FEntries.Count - 1 do
  begin
    e := TTyTermLinkEntry(FEntries[i]);
    for k := 0 to e.Markers.Count - 1 do
    begin
      m := TTyTerminalMarker(e.Markers[k]);
      m.RemoveDisposeListener(@MarkerDisposed);
      m.Release;
    end;
    e.Free;
  end;
  FEntries.Free;
  inherited Destroy;
end;

function TTyTerminalOscLinks.FindEntry(ALinkId: Integer; out AIndex: Integer): Boolean;
var
  lo, hi, mid, id: Integer;
begin
  lo := 0;
  hi := FEntries.Count - 1;
  while lo <= hi do
  begin
    mid := (lo + hi) shr 1;
    id := TTyTermLinkEntry(FEntries[mid]).LinkId;
    if id = ALinkId then
    begin
      AIndex := mid;
      Exit(True);
    end;
    if id < ALinkId then lo := mid + 1 else hi := mid - 1;
  end;
  AIndex := lo;
  Result := False;
end;

function TTyTerminalOscLinks.FindKey(const AKey: string; out AIndex: Integer): Boolean;
var
  lo, hi, mid, c: Integer;
begin
  lo := 0;
  hi := FKeyCount - 1;
  while lo <= hi do
  begin
    mid := (lo + hi) shr 1;
    c := CompareStr(FKeys[mid], AKey);
    if c = 0 then
    begin
      AIndex := mid;
      Exit(True);
    end;
    if c < 0 then lo := mid + 1 else hi := mid - 1;
  end;
  AIndex := lo;
  Result := False;
end;

procedure TTyTerminalOscLinks.AttachMarker(AEntry: TTyTermLinkEntry; AMarker: TTyTerminalMarker);
begin
  AMarker.AddRef;                          { the entry's reference }
  AMarker.Tag := AEntry;
  AEntry.Markers.Add(AMarker);
  AMarker.AddDisposeListener(@MarkerDisposed);
end;

function TTyTerminalOscLinks.RegisterLink(const AData: TTyTerminalLinkData): Integer;
var
  buf: TTyTerminalBuffer;
  e: TTyTermLinkEntry;
  key: string;
  k, i: Integer;
begin                                                                        { :31-68 }
  buf := FService.Buffer;
  if not AData.HasId then
  begin
    { a link without an id is only ever registered once }
    e := TTyTermLinkEntry.Create;
    e.Data := AData;
    e.LinkId := FNextId;
    Inc(FNextId);
    AttachMarker(e, buf.AddMarker(buf.YBase + buf.Y));
    FEntries.Add(e);
    Exit(e.LinkId);
  end;
  key := AData.Id + ';;' + AData.Uri;
  if FindKey(key, k) then
  begin
    AddLineToLink(FKeyEntries[k].LinkId, buf.YBase + buf.Y);
    Exit(FKeyEntries[k].LinkId);
  end;
  e := TTyTermLinkEntry.Create;
  e.Data := AData;
  e.Key := key;
  e.LinkId := FNextId;
  Inc(FNextId);
  AttachMarker(e, buf.AddMarker(buf.YBase + buf.Y));
  if FKeyCount = System.Length(FKeys) then
  begin
    SetLength(FKeys, FKeyCount * 2 + 4);
    SetLength(FKeyEntries, FKeyCount * 2 + 4);
  end;
  for i := FKeyCount downto k + 1 do
  begin
    FKeys[i] := FKeys[i - 1];
    FKeyEntries[i] := FKeyEntries[i - 1];
  end;
  FKeys[k] := key;
  FKeyEntries[k] := e;
  Inc(FKeyCount);
  FEntries.Add(e);
  Result := e.LinkId;
end;

procedure TTyTerminalOscLinks.AddLineToLink(ALinkId, AAbsRow: Integer);
var
  i, k: Integer;
  e: TTyTermLinkEntry;
begin                                                                        { :70-80 }
  if not FindEntry(ALinkId, i) then
    Exit;
  e := TTyTermLinkEntry(FEntries[i]);
  for k := 0 to e.Markers.Count - 1 do
    if TTyTerminalMarker(e.Markers[k]).Line = AAbsRow then
      Exit;
  AttachMarker(e, FService.Buffer.AddMarker(AAbsRow));
end;

function TTyTerminalOscLinks.GetLinkData(ALinkId: Integer; out AData: TTyTerminalLinkData): Boolean;
var
  i: Integer;
begin
  Result := FindEntry(ALinkId, i);
  if Result then
    AData := TTyTermLinkEntry(FEntries[i]).Data
  else
  begin
    AData.Id := '';
    AData.HasId := False;
    AData.Uri := '';
  end;
end;

procedure TTyTerminalOscLinks.MarkerDisposed(Sender: TObject);               { :90-102 }
var
  m: TTyTerminalMarker;
  e: TTyTermLinkEntry;
  i, k: Integer;
begin
  m := TTyTerminalMarker(Sender);
  e := TTyTermLinkEntry(m.Tag);
  if e = nil then
    Exit;
  i := e.Markers.IndexOf(m);
  if i = -1 then
    Exit;
  e.Markers.Delete(i);
  m.Tag := nil;
  m.Release;
  if e.Markers.Count = 0 then
  begin
    if e.Data.HasId and FindKey(e.Key, k) then
    begin
      for i := k to FKeyCount - 2 do
      begin
        FKeys[i] := FKeys[i + 1];
        FKeyEntries[i] := FKeyEntries[i + 1];
      end;
      Dec(FKeyCount);
      FKeys[FKeyCount] := '';
    end;
    if FindEntry(e.LinkId, i) then
      FEntries.Delete(i);
    e.Free;
  end;
end;

function TTyTerminalOscLinks.LinkIds: TIntegerDynArray;
var
  i: Integer;
begin
  Result := nil;
  SetLength(Result, FEntries.Count);
  for i := 0 to FEntries.Count - 1 do
    Result[i] := TTyTermLinkEntry(FEntries[i]).LinkId;
end;

function TTyTerminalOscLinks.LinkLines(ALinkId: Integer): TIntegerDynArray;
var
  i, k: Integer;
  e: TTyTermLinkEntry;
begin
  Result := nil;
  if not FindEntry(ALinkId, i) then
    Exit;
  e := TTyTermLinkEntry(FEntries[i]);
  SetLength(Result, e.Markers.Count);
  for k := 0 to e.Markers.Count - 1 do
    Result[k] := TTyTerminalMarker(e.Markers[k]).Line;
end;

end.
