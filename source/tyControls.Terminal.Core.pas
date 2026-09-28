unit tyControls.Terminal.Core;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

{ TTyTerminalCore: the invisible terminal. Bytes go in through the write queue, get
  decoded and parsed, and the handlers here change the buffers, the modes and the
  character sets and send replies back through OnData. No LCL (design spec 3.1):
  the control that shows it is built on top in a later phase.

  PORTED FROM xterm.js 6.0.0, commit c58ea3637f39:
    src/common/InputHandler.ts            every handler, the parse entry, dirty rows
    src/common/CoreTerminal.ts            the non-UI part: resize, scroll, reset,
                                          the old-ConPTY wrap heuristics
    src/headless/Terminal.ts              reset, clear, resize
    src/common/services/CoreService.ts    modes, triggerDataEvent
    src/common/services/CharsetService.ts G0-G3
    src/common/services/MouseStateService.ts   protocols, restriction, encoding
    src/common/input/WriteBuffer.ts       the write queue
    src/common/input/XParseColor.ts       colour specs
    src/common/WindowsMode.ts             the wrap heuristic
    src/common/data/Charsets.ts           (through tyControls.Terminal.Charsets.inc)
    src/common/data/EscapeSequences.ts    C0 / C1 names
    src/common/Color.ts                   relativeLuminance
    and from the browser layer, what the core answers itself here:
    src/browser/CoreBrowserTerminal.ts:204-268 (colour requests, colour scheme),
    :305-331 and :1124-1130 (focus reports), src/browser/services/ThemeService.ts
    (set, restore, a theme change drops the overrides).

    Copyright (c) 2017-2019, The xterm.js authors (https://github.com/xtermjs/xterm.js)
    Copyright (c) 2014-2016, SourceLair Private Company (https://www.sourcelair.com)
    Copyright (c) 2012-2013, Christopher Jeffrey (https://github.com/chjj/)
  MIT; the full text is in THIRD-PARTY-NOTICES.md. xterm.js's CoreTerminal was
  originally forked (with the author's permission) from Fabrice Bellard's javascript
  vt100 for jslinux (http://bellard.org/jslinux/, Copyright (c) 2011 Fabrice
  Bellard).

  WHAT TO KNOW BEFORE CHANGING ANYTHING:

  - Reset is headless xterm.js's reset, which is partial on purpose: it keeps the
    title, the link-number counter, a hidden cursor and the parser state. RIS
    (ESC c) is the same plus a parser reset. Do not "fix" either into a full reset;
    the fixtures hold both.
  - REP stops at 2^20 repeats. Upstream allocates repeats x text before printing and
    never returns for a huge count, so beyond the cap there is no upstream answer;
    up to it the result is upstream's bit for bit. This is a deliberate difference.
  - IL, DL, SU, SD, CHT and CBT clamp their loop count to the region height or the
    column count. Every pass past that is a no-op upstream, so the clamp changes
    nothing but the time (upstream takes seconds for 99999 and never finishes 2^31).
  - Coordinates plus parameters are summed in Int64 (a parameter can be 2^31 - 1).
  - Colours: the core keeps the overrides set by OSC 4 / 10 / 11 / 12 and answers
    queries from them, falling back to OnQueryBaseColor. A set or a restore reports
    the colour scheme when DECSET 2031 is on; RIS leaves the overrides alone; the
    host's NotifyColorSchemeChanged (a new theme) drops them all -- the browser
    layer's ThemeService semantics.
  - Mouse: only the protocol state and the two pure functions RestrictMouseEvent /
    EncodeMouseEvent; turning LCL mouse events into reports is the control's job
    (phase 4).
  - The screen-reader branches of print and tab are not ported (no accessibility
    layer, spec 15). }

interface

uses
  SysUtils, Classes, Math, Types, tyControls.Unicode.Width, tyControls.Terminal.Parser,
  tyControls.Terminal.Buffer;

const
  { = TyVersion (tyControls.Types, which uses LCL and cannot be used here): change
    both together when releasing -- TTyTerminalCoreTests.TestXtVersionConstant. }
  TyTermLibraryVersion = '3.1.0';
  TyTermDiscardWatermark = 50000000;      { WriteBuffer.ts:20 }
  TyTermWriteTimeoutMs = 12;              { WriteBuffer.ts:27 }
  TyTermWriteBufferLengthThreshold = 50;  { WriteBuffer.ts:28 }
  TyTermStackLimit = 10;                  { InputHandler.ts:47 }
  TyTermRepeatLimit = 1048576;            { REP cap, unit header }

type
  { More than 50 MB waiting: the host is not doing flow control (upstream throws a
    plain Error). }
  ETyTerminalWriteOverflow = class(Exception);

  TTyTerminalDataEvent  = procedure(Sender: TObject; const AData: RawByteString) of object;
  TTyTerminalTextEvent  = procedure(Sender: TObject; const AText: string) of object;
  TTyTerminalRowsEvent  = procedure(Sender: TObject; AFirst, ALast: Integer) of object;
  TTyTerminalOscEvent   = procedure(Sender: TObject; AIdent: Integer; const AData: string;
                            var AHandled: Boolean) of object;
  TTyTerminalWriteDone  = procedure(Sender: TObject; ATag: PtrInt) of object;
  { AIndex: 0..255 palette, 256 foreground, 257 background, 258 cursor }
  TTyTerminalColorQuery = procedure(Sender: TObject; AIndex: Integer; out ARgb: Cardinal) of object;
  TTyTerminalScrollEvent = procedure(Sender: TObject; AYDisp: Integer) of object;
  TTyTerminalClock = function: Double of object;                       { milliseconds }
  TTyTermWindowReport = (twrWinSizePixels, twrCellSizePixels);
  TTyTerminalWindowReportEvent = procedure(Sender: TObject; AKind: TTyTermWindowReport) of object;

  { CoreMouseButton 0..4 in order; CoreMouseAction: MOVE is 32 upstream, see
    TyTermMouseActionCode }
  TTyTerminalMouseButton = (tmbLeft, tmbMiddle, tmbRight, tmbNone, tmbWheel);
  TTyTerminalMouseAction = (tmaUp, tmaDown, tmaLeft, tmaRight, tmaMove);
  TTyTerminalMouseEvent = record
    Col, Row, X, Y: Integer;
    Button: TTyTerminalMouseButton;
    Action: TTyTerminalMouseAction;
    Shift, Alt, Ctrl: Boolean;
  end;
  TTyTerminalMouseProtocol = (tmpNone, tmpX10, tmpVT200, tmpDrag, tmpAny);
  TTyTerminalMouseEncoding = (tmeDefault, tmeSgr, tmeSgrPixels);
  TTyTermCursorRequest = (tcrDefault, tcrBlock, tcrUnderline, tcrBar);
  TTyTermBlinkRequest = (tbrDefault, tbrOn, tbrOff);
  { a snapshot (design spec 7.6) }
  TTyTerminalModes = record
    ApplicationCursorKeys, ApplicationKeypad, BracketedPaste, Insert, Origin, ReverseWraparound,
    SendFocus, ShowCursor, SynchronizedOutput, Win32Input, Wraparound, ColorSchemeUpdates: Boolean;
    MouseProtocol: TTyTerminalMouseProtocol;
    MouseEncoding: TTyTerminalMouseEncoding;
    CursorRequest: TTyTermCursorRequest;
    BlinkRequest: TTyTermBlinkRequest;
  end;
  { IWindowOptions, Types.ts:248-271 }
  TTyTermWindowOption = (twoRestoreWin, twoMinimizeWin, twoSetWinPosition, twoSetWinSizePixels,
    twoRaiseWin, twoLowerWin, twoRefreshWin, twoSetWinSizeChars, twoMaximizeWin, twoFullscreenWin,
    twoGetWinState, twoGetWinPosition, twoGetWinSizePixels, twoGetScreenSizePixels,
    twoGetCellSizePixels, twoGetWinSizeChars, twoGetScreenSizeChars, twoGetIconTitle,
    twoGetWinTitle, twoPushTitle, twoPopTitle, twoSetWinLines);
  TTyTerminalWindowOptions = set of TTyTermWindowOption;
  TTyTermVtExtension = (tveKittyKeyboard, tveWin32InputMode, tveKittySgrBoldFaint, tveColorSchemeQuery);
  TTyTerminalVtExtensions = set of TTyTermVtExtension;

  TTyTerminalCore = class;

  { One ESC ( ) * + - . / designation: FPC has no closures, so each registered
    handler is a small object that knows its two characters. }
  TTyTermCharsetHandler = class
  public
    Core: TTyTerminalCore;
    Designation: string;
    function Run: Boolean;
  end;

  TTyTermQueueItem = record
    Data: RawByteString;
    OnDone: TTyTerminalWriteDone;
    Tag: PtrInt;
  end;

  TTyTermColorOverride = record
    IsSet: Boolean;
    Rgb: Cardinal;
  end;

  TTyTerminalCore = class
  private
    FOptions: TTyTerminalOptions;
    FBufferService: TTyTerminalBufferService;
    FLinks: TTyTerminalOscLinks;
    FParser: TTyTerminalParser;
    FDecoder: TTyUtf8Decoder;
    FParseBuffer: array of Cardinal;
    FCharsetHandlers: TFPList;
    FWindowOptions: TTyTerminalWindowOptions;
    FVtExtensions: TTyTerminalVtExtensions;
    FUnicodeVersion: TTyUnicodeVersion;
    FAmbiguousWide: Boolean;
    { CoreService }
    FInsertMode: Boolean;
    FApplicationCursorKeys, FApplicationKeypad, FBracketedPasteMode, FColorSchemeUpdates,
    FOrigin, FReverseWraparound, FSendFocus, FSynchronizedOutput, FWin32InputMode,
    FWraparound: Boolean;
    FCursorStyleRequest: TTyTermCursorRequest;   { decPrivateModes.cursorStyle, default = undefined }
    FCursorBlinkRequest: TTyTermBlinkRequest;    { decPrivateModes.cursorBlink }
    FIsCursorHidden, FIsCursorInitialized: Boolean;
    FKittyFlags, FKittyMainFlags, FKittyAltFlags: Integer;
    FKittyMainStack, FKittyAltStack: TIntegerDynArray;
    { CharsetService }
    FCharset: TTyTermCharsetId;
    FGLevel: Integer;
    FCharsets: TTyTermCharsetIds;
    { MouseStateService }
    FMouseProtocol: TTyTerminalMouseProtocol;
    FMouseEncoding: TTyTerminalMouseEncoding;
    { InputHandler }
    FCurAttr: TTyTerminalAttrData;
    FEraseAttr: TTyTerminalAttrData;
    FWindowTitle, FIconName: string;
    FWindowTitleStack, FIconNameStack: TStringDynArray;
    FDirtyStart, FDirtyEnd: Integer;
    FOscData: TTyLimitedStringBuilder;   { the payload of an OSC no handler took }
    FOscDataHitLimit: Boolean;
    { colours and focus }
    FOverrides: array[0..258] of TTyTermColorOverride;
    FFocused: Boolean;
    { the old-ConPTY heuristics }
    FWindowsHeuristics: Boolean;
    FWindowsCsiHandle: Integer;
    { the write queue }
    FQueue: array of TTyTermQueueItem;
    FQueueCount: Integer;
    FBufferOffset: Integer;
    FPendingData: Int64;
    FIsSyncWriting: Boolean;
    FDidUserInput: Boolean;
    FProcessRequested: Boolean;
    FClock: TTyTerminalClock;
    { events }
    FOnData: TTyTerminalDataEvent;
    FOnRefreshRows: TTyTerminalRowsEvent;
    FOnTitleChange, FOnIconNameChange: TTyTerminalTextEvent;
    FOnBell, FOnCursorMove, FOnLineFeed, FOnBufferActivate, FOnModesChange: TNotifyEvent;
    FOnScroll: TTyTerminalScrollEvent;
    FOnOsc: TTyTerminalOscEvent;
    FOnQueryBaseColor: TTyTerminalColorQuery;
    FOnRequestScrollToBottom: TNotifyEvent;
    FOnProcessRequest: TNotifyEvent;
    FOnWindowOptionsReport: TTyTerminalWindowReportEvent;

    { wiring }
    procedure RegisterHandlers;
    procedure BufferScrolled(AYDisp: Integer);
    procedure BufferActivated(AActive, AInactive: TTyTerminalBuffer);
    function GetBuffer: TTyTerminalBuffer;
    function GetBuffers: TTyTerminalBufferSet;
    function GetCols: Integer;
    function GetRows: Integer;
    { CoreService / CharsetService / MouseStateService }
    procedure CoreServiceReset;
    procedure TriggerDataEvent(const AData: RawByteString; AWasUserInput: Boolean = False);
    procedure CharsetReset;
    procedure SetGLevel(AG: Integer);
    procedure SetGCharset(AG: Integer; ACharset: TTyTermCharsetId);
    procedure SetMouseProtocol(AValue: TTyTerminalMouseProtocol);
    function GetModes: TTyTerminalModes;
    procedure ModesChangedSince(const ABefore: TTyTerminalModes);
    { colours and focus }
    procedure ReportColor(AIndex: Integer);
    procedure SetColor(AIndex: Integer; ARgb: Cardinal);
    procedure RestoreColor(AIndex: Integer);            { -1 = the whole palette }
    procedure ColorsChanged;
    procedure ReportColorScheme;
    procedure ReportFocusNow;
    { DirtyRowTracker, InputHandler.ts:3655-3695 }
    procedure ClearRange;
    procedure MarkDirty(AY: Integer);
    procedure MarkRangeDirty(AY1, AY2: Integer);
    procedure MarkAllDirty;
    procedure RefreshAll;
    { the old-ConPTY heuristics (CoreTerminal.ts:279-306, WindowsMode.ts) }
    procedure HandleWindowsPtyOptionChange;
    procedure UpdateWindowsModeWrappedState;
    function WindowsHeuristicCsiH(AParams: TTyTerminalParams): Boolean;
    { options }
    procedure SetScrollback(AValue: Integer);
    procedure SetTabStopWidth(AValue: Integer);
    procedure SetWindowsPty(const AValue: TTyTerminalWindowsPty);
    function GetOptBool(AIndex: Integer): Boolean;
    procedure SetOptBool(AIndex: Integer; AValue: Boolean);
    function GetCursorStyle: TTyTermCursorStyleOption;
    procedure SetCursorStyle(AValue: TTyTermCursorStyleOption);
    function GetWindowsPty: TTyTerminalWindowsPty;
    function GetScrollback: Integer;
    function GetTabStopWidth: Integer;

    { ---- InputHandler: parse, print, controls, cursor, erase, scroll (Task 16) ---- }
    procedure Parse(const AData: RawByteString);
    procedure DoPrint(const AData: array of Cardinal; AStart, AEnd: Integer; ARepeat: Integer);
    procedure PrintHandler(const AData: array of Cardinal; AStart, AEnd: Integer);
    function EraseAttrData: TTyTerminalAttrData;
    procedure RestrictCursor(AMaxCol: Integer = -1);
    procedure SetCursor(AX, AY: Int64);
    procedure MoveCursor(AX, AY: Int64);
    procedure EraseInBufferLine(AY, AStart: Integer; AEnd: Int64; AClearWrap: Boolean = False;
      ARespectProtect: Boolean = False);
    procedure ResetBufferLine(AY: Integer; ARespectProtect: Boolean = False);
    function Bell: Boolean;
    function LineFeed: Boolean;
    function CarriageReturn: Boolean;
    function Backspace: Boolean;
    function Tab: Boolean;
    function ShiftOut: Boolean;
    function ShiftIn: Boolean;
    function Index: Boolean;
    function NextLine: Boolean;
    function TabSet: Boolean;
    function ReverseIndex: Boolean;
    function CursorUp(AParams: TTyTerminalParams): Boolean;
    function CursorDown(AParams: TTyTerminalParams): Boolean;
    function CursorForward(AParams: TTyTerminalParams): Boolean;
    function CursorBackward(AParams: TTyTerminalParams): Boolean;
    function CursorNextLine(AParams: TTyTerminalParams): Boolean;
    function CursorPrecedingLine(AParams: TTyTerminalParams): Boolean;
    function CursorCharAbsolute(AParams: TTyTerminalParams): Boolean;
    function CursorPosition(AParams: TTyTerminalParams): Boolean;
    function CharPosAbsolute(AParams: TTyTerminalParams): Boolean;
    function HPositionRelative(AParams: TTyTerminalParams): Boolean;
    function LinePosAbsolute(AParams: TTyTerminalParams): Boolean;
    function VPositionRelative(AParams: TTyTerminalParams): Boolean;
    function HVPosition(AParams: TTyTerminalParams): Boolean;
    function TabClear(AParams: TTyTerminalParams): Boolean;
    function CursorForwardTab(AParams: TTyTerminalParams): Boolean;
    function CursorBackwardTab(AParams: TTyTerminalParams): Boolean;
    function SelectProtected(AParams: TTyTerminalParams): Boolean;
    function EraseInDisplay(AParams: TTyTerminalParams; ARespectProtect: Boolean): Boolean;
    function EraseInDisplayCsi(AParams: TTyTerminalParams): Boolean;
    function EraseInDisplayProtected(AParams: TTyTerminalParams): Boolean;
    function EraseInLine(AParams: TTyTerminalParams; ARespectProtect: Boolean): Boolean;
    function EraseInLineCsi(AParams: TTyTerminalParams): Boolean;
    function EraseInLineProtected(AParams: TTyTerminalParams): Boolean;
    function InsertLines(AParams: TTyTerminalParams): Boolean;
    function DeleteLines(AParams: TTyTerminalParams): Boolean;
    function InsertChars(AParams: TTyTerminalParams): Boolean;
    function DeleteChars(AParams: TTyTerminalParams): Boolean;
    function ScrollUp(AParams: TTyTerminalParams): Boolean;
    function ScrollDown(AParams: TTyTerminalParams): Boolean;
    function ScrollLeft(AParams: TTyTerminalParams): Boolean;
    function ScrollRight(AParams: TTyTerminalParams): Boolean;
    function InsertColumns(AParams: TTyTerminalParams): Boolean;
    function DeleteColumns(AParams: TTyTerminalParams): Boolean;
    function EraseChars(AParams: TTyTerminalParams): Boolean;
    function RepeatPrecedingCharacter(AParams: TTyTerminalParams): Boolean;
    function ScreenAlignmentPattern: Boolean;

    { ---- InputHandler: modes, SGR, replies, cursor store, OSC, resets (Task 17) ---- }
    function SetModeCsi(AParams: TTyTerminalParams): Boolean;
    function ResetModeCsi(AParams: TTyTerminalParams): Boolean;
    function SetModePrivate(AParams: TTyTerminalParams): Boolean;
    function ResetModePrivate(AParams: TTyTerminalParams): Boolean;
    function RequestMode(AParams: TTyTerminalParams; AAnsi: Boolean): Boolean;
    function RequestModeAnsi(AParams: TTyTerminalParams): Boolean;
    function RequestModePrivate(AParams: TTyTerminalParams): Boolean;
    function UpdateAttrColor(AColor: Cardinal; AMode, AC1, AC2, AC3: Integer): Cardinal;
    function ExtractColor(AParams: TTyTerminalParams; APos: Integer; var AAttr: TTyTerminalAttrData): Integer;
    procedure ProcessUnderline(AStyle: Integer; var AAttr: TTyTerminalAttrData);
    procedure ProcessSGR0(var AAttr: TTyTerminalAttrData);
    function CharAttributes(AParams: TTyTerminalParams): Boolean;
    function SendDeviceAttributesPrimary(AParams: TTyTerminalParams): Boolean;
    function SendDeviceAttributesSecondary(AParams: TTyTerminalParams): Boolean;
    function SendXtVersion(AParams: TTyTerminalParams): Boolean;
    function DeviceStatus(AParams: TTyTerminalParams): Boolean;
    function DeviceStatusPrivate(AParams: TTyTerminalParams): Boolean;
    function SoftReset(AParams: TTyTerminalParams): Boolean;
    function SetCursorStyleCsi(AParams: TTyTerminalParams): Boolean;
    function SetScrollRegion(AParams: TTyTerminalParams): Boolean;
    function WindowOptionsCsi(AParams: TTyTerminalParams): Boolean;
    function SaveCursor: Boolean;
    function SaveCursorCsi(AParams: TTyTerminalParams): Boolean;
    function RestoreCursor: Boolean;
    function RestoreCursorCsi(AParams: TTyTerminalParams): Boolean;
    function KeypadApplicationMode: Boolean;
    function KeypadNumericMode: Boolean;
    function SelectDefaultCharset: Boolean;
    function SelectCharset(const ACollectAndFlag: string): Boolean;
    function SetGLevel1: Boolean;
    function SetGLevel2: Boolean;
    function SetGLevel3: Boolean;
    function FullReset: Boolean;
    procedure InputHandlerReset;
    function RequestStatusString(const AData: string; AParams: TTyTerminalParams): Boolean;
    function OscTitleAndIcon(const AData: string): Boolean;
    function OscIconName(const AData: string): Boolean;
    function OscTitle(const AData: string): Boolean;
    function OscIndexedColor(const AData: string): Boolean;
    function OscHyperlink(const AData: string): Boolean;
    function OscFgColor(const AData: string): Boolean;
    function OscBgColor(const AData: string): Boolean;
    function OscCursorColor(const AData: string): Boolean;
    function OscRestoreIndexedColor(const AData: string): Boolean;
    function OscRestoreFgColor(const AData: string): Boolean;
    function OscRestoreBgColor(const AData: string): Boolean;
    function OscRestoreCursorColor(const AData: string): Boolean;
    procedure SetOrReportSpecialColor(const AData: string; AOffset: Integer);
    function CreateHyperlink(const AParams, AUri: string): Boolean;
    function FinishHyperlink: Boolean;
    procedure SetTitle(const AData: string);
    procedure SetIconName(const AData: string);
    procedure OscFallback(AIdent: Int64; AAction: TTyTermSubAction; const APayload: string; ASuccess: Boolean);
    function KittyKeyboardSet(AParams: TTyTerminalParams): Boolean;
    function KittyKeyboardQuery(AParams: TTyTerminalParams): Boolean;
    function KittyKeyboardPush(AParams: TTyTerminalParams): Boolean;
    function KittyKeyboardPop(AParams: TTyTerminalParams): Boolean;

    { ---- the write queue (Task 19) ---- }
    procedure CheckThread(const AMethod: string);
    function Now: Double;
    procedure RequestProcess;
    procedure Enqueue(const AData: RawByteString; AOnDone: TTyTerminalWriteDone; ATag: PtrInt);
    procedure InnerWrite(ABudgetMs: Integer; out AMore: Boolean);
    procedure FlushSync;
    procedure ClearQueue;
  public
    constructor Create(ACols, ARows: Integer);
    destructor Destroy; override;
    { writing: only on the main thread (EInvalidOperation otherwise) }
    procedure Write(const AData: RawByteString; AOnDone: TTyTerminalWriteDone = nil; ATag: PtrInt = 0); overload;
    procedure Write(const ABuf; ACount: Integer; AOnDone: TTyTerminalWriteDone = nil; ATag: PtrInt = 0); overload;
    procedure WriteSync(const AData: RawByteString);
    { One slice: chunks until the budget is spent, checked between chunks. True when
      something is left -- the caller schedules the next slice. }
    function ProcessPending(ABudgetMs: Integer = TyTermWriteTimeoutMs): Boolean;
    { input from the control }
    procedure Input(const AData: RawByteString; AWasUserInput: Boolean = True);
    function RestrictMouseEvent(var AEvent: TTyTerminalMouseEvent): Boolean;
    { '' when suppressed (the default encoding past 223) }
    function EncodeMouseEvent(const AEvent: TTyTerminalMouseEvent): RawByteString;
    procedure ReportFocus(AFocused: Boolean);
    procedure NotifyColorSchemeChanged;
    { size and state }
    procedure Resize(ACols, ARows: Integer);             { min 2 x 1; flushes pending first }
    procedure Reset;                                     { headless Terminal.reset }
    procedure ScrollLines(ADelta: Integer);
    procedure ScrollPages(APages: Integer);
    procedure ScrollToBottom;
    procedure ScrollToTop;
    procedure ClearScrollback;                           { headless Terminal.clear }
    function ResolveColor(AIndex: Integer): Cardinal;
    function HasColorOverride(AIndex: Integer): Boolean;
    { pure queries for the tests and the renderer }
    function CharsetOfG(AG: Integer): TTyTermCharsetId;
    function CharsetKey(AId: TTyTermCharsetId): string;  { first designation of a table; '' for 0 }
    function WindowTitleStack: TStringDynArray;
    function IconNameStack: TStringDynArray;
    function KittyStacks(AAlt: Boolean): TIntegerDynArray;
    property KittyFlags: Integer read FKittyFlags;
    property KittyMainFlags: Integer read FKittyMainFlags;
    property KittyAltFlags: Integer read FKittyAltFlags;
    property IsCursorInitialized: Boolean read FIsCursorInitialized;
    property GLevel: Integer read FGLevel;
    property CurrentAttr: TTyTerminalAttrData read FCurAttr;
    property BufferService: TTyTerminalBufferService read FBufferService;

    property PendingBytes: Int64 read FPendingData;
    property Clock: TTyTerminalClock read FClock write FClock;
    property Focused: Boolean read FFocused;
    property Cols: Integer read GetCols;
    property Rows: Integer read GetRows;
    property Buffers: TTyTerminalBufferSet read GetBuffers;
    property Buffer: TTyTerminalBuffer read GetBuffer;
    property Modes: TTyTerminalModes read GetModes;
    property Title: string read FWindowTitle;
    property IconName: string read FIconName;
    property Parser: TTyTerminalParser read FParser;
    property Links: TTyTerminalOscLinks read FLinks;
    { options }
    property Scrollback: Integer read GetScrollback write SetScrollback;
    property TabStopWidth: Integer read GetTabStopWidth write SetTabStopWidth;
    property ConvertEol: Boolean index 0 read GetOptBool write SetOptBool;
    property ScrollOnUserInput: Boolean index 1 read GetOptBool write SetOptBool;
    property ReadOnly: Boolean index 2 read GetOptBool write SetOptBool;
    property CursorBlink: Boolean index 3 read GetOptBool write SetOptBool;
    property ScrollOnEraseInDisplay: Boolean index 4 read GetOptBool write SetOptBool;
    property AllowSetCursorBlink: Boolean index 5 read GetOptBool write SetOptBool;
    property AmbiguousWide: Boolean read FAmbiguousWide write FAmbiguousWide;
    property UnicodeVersion: TTyUnicodeVersion read FUnicodeVersion write FUnicodeVersion;
    property WindowsPty: TTyTerminalWindowsPty read GetWindowsPty write SetWindowsPty;
    property WindowOptions: TTyTerminalWindowOptions read FWindowOptions write FWindowOptions;
    property VtExtensions: TTyTerminalVtExtensions read FVtExtensions write FVtExtensions;
    property CursorStyle: TTyTermCursorStyleOption read GetCursorStyle write SetCursorStyle;
    { events }
    property OnData: TTyTerminalDataEvent read FOnData write FOnData;
    property OnRefreshRows: TTyTerminalRowsEvent read FOnRefreshRows write FOnRefreshRows;
    property OnTitleChange: TTyTerminalTextEvent read FOnTitleChange write FOnTitleChange;
    property OnIconNameChange: TTyTerminalTextEvent read FOnIconNameChange write FOnIconNameChange;
    property OnBell: TNotifyEvent read FOnBell write FOnBell;
    property OnCursorMove: TNotifyEvent read FOnCursorMove write FOnCursorMove;
    property OnLineFeed: TNotifyEvent read FOnLineFeed write FOnLineFeed;
    property OnBufferActivate: TNotifyEvent read FOnBufferActivate write FOnBufferActivate;
    property OnModesChange: TNotifyEvent read FOnModesChange write FOnModesChange;
    property OnScroll: TTyTerminalScrollEvent read FOnScroll write FOnScroll;
    property OnOsc: TTyTerminalOscEvent read FOnOsc write FOnOsc;
    property OnQueryBaseColor: TTyTerminalColorQuery read FOnQueryBaseColor write FOnQueryBaseColor;
    property OnRequestScrollToBottom: TNotifyEvent read FOnRequestScrollToBottom write FOnRequestScrollToBottom;
    { the queue went from empty to not empty: schedule ProcessPending }
    property OnProcessRequest: TNotifyEvent read FOnProcessRequest write FOnProcessRequest;
    { CSI 14 t / 16 t with the matching window option: the control answers in pixels }
    property OnWindowOptionsReport: TTyTerminalWindowReportEvent read FOnWindowOptionsReport write FOnWindowOptionsReport;
  end;

{ The built-in monotonic clock, milliseconds. }
function TyTermDefaultClock: Double;
{ XParseColor.ts:23-56 parseColor; channels 0..255. }
function TyTermParseXColor(const ASpec: string; out R, G, B: Integer): Boolean;
{ XParseColor.ts:58-80 toRgbString, 16 bits per channel. }
function TyTermToRgbString(ARgb: Cardinal): string;
{ Color.ts:236-259 }
function TyTermRelativeLuminance(ARgb: Cardinal): Double;
{ CoreMouseAction's value upstream (MOVE = 32) }
function TyTermMouseActionCode(AAction: TTyTerminalMouseAction): Integer;

implementation

{$IFDEF MSWINDOWS}
uses
  Windows;
{$ENDIF}

{$I tyControls.Terminal.Charsets.inc}

const
  { SpecialColorIndex }
  ColorFg = 256;
  ColorBg = 257;
  ColorCursor = 258;
  GLevelOf: array[0..5] of record C: Char; G: Integer; end = (
    (C: '('; G: 0), (C: ')'; G: 1), (C: '*'; G: 2), (C: '+'; G: 3), (C: '-'; G: 1), (C: '.'; G: 2));

{ ---- pure helpers ------------------------------------------------------------------- }

function TyTermMouseActionCode(AAction: TTyTerminalMouseAction): Integer;
begin
  case AAction of
    tmaUp: Result := 0;
    tmaDown: Result := 1;
    tmaLeft: Result := 2;
    tmaRight: Result := 3;
  else
    Result := 32;                          { MOVE }
  end;
end;

function IsHexDigit(C: Char): Boolean; inline;
begin
  Result := C in ['0'..'9', 'a'..'f'];
end;

function HexValue(const S: string): Int64;
var
  i: Integer;
begin
  Result := 0;
  for i := 1 to Length(S) do
    if S[i] <= '9' then
      Result := Result * 16 + (Ord(S[i]) - Ord('0'))
    else
      Result := Result * 16 + (Ord(S[i]) - Ord('a') + 10);
end;

{ Math.round(parseInt(x, 16) / base * 255): divide first, then multiply, then round
  half up (JavaScript's round, not FPC's banker's rounding). }
function ScaleChannel(const AHex: string; ABase: Integer): Integer;
var
  v: Double;
begin
  v := HexValue(AHex) / ABase * 255;
  Result := Floor(v + 0.5);
end;

function TyTermParseXColor(const ASpec: string; out R, G, B: Integer): Boolean;
var
  low, rest, p1, p2, p3: string;
  i, w, adv: Integer;
  parts: array[0..2] of string;
  v: Int64;
begin
  R := 0;
  G := 0;
  B := 0;
  Result := False;
  if ASpec = '' then
    Exit;
  low := LowerCase(ASpec);
  if Copy(low, 1, 4) = 'rgb:' then
  begin
    rest := Copy(low, 5, MaxInt);
    { r/g/b | rr/gg/bb | rrr/ggg/bbb | rrrr/gggg/bbbb: three equal-width hex groups }
    i := Pos('/', rest);
    if i = 0 then Exit;
    p1 := Copy(rest, 1, i - 1);
    rest := Copy(rest, i + 1, MaxInt);
    i := Pos('/', rest);
    if i = 0 then Exit;
    p2 := Copy(rest, 1, i - 1);
    p3 := Copy(rest, i + 1, MaxInt);
    w := Length(p1);
    if (w < 1) or (w > 4) or (Length(p2) <> w) or (Length(p3) <> w) then Exit;
    parts[0] := p1;
    parts[1] := p2;
    parts[2] := p3;
    for i := 0 to 2 do
      for adv := 1 to w do
        if not IsHexDigit(parts[i][adv]) then Exit;
    case w of
      1: v := 15;
      2: v := 255;
      3: v := 4095;
    else
      v := 65535;
    end;
    R := ScaleChannel(p1, v);
    G := ScaleChannel(p2, v);
    B := ScaleChannel(p3, v);
    Result := True;
  end
  else if Copy(low, 1, 1) = '#' then
  begin
    rest := Copy(low, 2, MaxInt);
    if rest = '' then Exit;
    for i := 1 to Length(rest) do
      if not IsHexDigit(rest[i]) then Exit;
    if not (Length(rest) in [3, 6, 9, 12]) then Exit;
    adv := Length(rest) div 3;
    for i := 0 to 2 do
    begin
      v := HexValue(Copy(rest, adv * i + 1, adv));
      case adv of
        1: v := v shl 4;
        2: ;
        3: v := v shr 4;
      else
        v := v shr 8;
      end;
      case i of
        0: R := v;
        1: G := v;
      else
        B := v;
      end;
    end;
    Result := True;
  end;
end;

function TyTermToRgbString(ARgb: Cardinal): string;

  function Pad(n: Integer): string;
  begin
    Result := LowerCase(IntToHex(n, 2));
    Result := Result + Result;
  end;

begin
  Result := 'rgb:' + Pad((ARgb shr 16) and $FF) + '/' + Pad((ARgb shr 8) and $FF) + '/' + Pad(ARgb and $FF);
end;

function TyTermRelativeLuminance(ARgb: Cardinal): Double;

  function Channel(c: Integer): Double;
  var
    s: Double;
  begin
    s := c / 255;
    if s <= 0.03928 then
      Result := s / 12.92
    else
      Result := Power((s + 0.055) / 1.055, 2.4);
  end;

begin
  Result := Channel((ARgb shr 16) and $FF) * 0.2126 + Channel((ARgb shr 8) and $FF) * 0.7152
    + Channel(ARgb and $FF) * 0.0722;
end;

function TyTermDefaultClock: Double;
{$IFDEF MSWINDOWS}
var
  c, f: Int64;
begin
  { GetTickCount64 steps by ~15.6 ms here, coarser than the 12 ms budget }
  c := 0;
  f := 1;
  QueryPerformanceCounter(c);
  QueryPerformanceFrequency(f);
  Result := c * 1000.0 / f;
end;
{$ELSE}
begin
  { FPC's GetTickCount64 on Unix is clock_gettime(CLOCK_MONOTONIC), 1 ms }
  Result := GetTickCount64;
end;
{$ENDIF}

{ ---- TTyTermCharsetHandler ------------------------------------------------------------ }

function TTyTermCharsetHandler.Run: Boolean;
begin
  Result := Core.SelectCharset(Designation);
end;

{ ---- construction ----------------------------------------------------------------------- }

constructor TTyTerminalCore.Create(ACols, ARows: Integer);
begin
  inherited Create;
  FOptions := TTyTerminalOptions.Create;
  FVtExtensions := [tveKittySgrBoldFaint, tveColorSchemeQuery];
  FUnicodeVersion := tuv11;
  FFocused := True;
  FWraparound := True;
  FCurAttr := TyTermDefaultAttr;
  FEraseAttr := TyTermDefaultAttr;
  FMouseProtocol := tmpNone;
  FMouseEncoding := tmeDefault;
  FBufferService := TTyTerminalBufferService.Create(FOptions, ACols, ARows);
  FBufferService.OnScroll := @BufferScrolled;
  FBufferService.OnBufferActivate := @BufferActivated;
  FLinks := TTyTerminalOscLinks.Create(FBufferService);
  FParser := TTyTerminalParser.Create;
  FDecoder := TTyUtf8Decoder.Create;
  FOscData := TTyLimitedStringBuilder.Create(TyTermParserPayloadLimit);
  FCharsetHandlers := TFPList.Create;
  SetLength(FParseBuffer, 4096);
  ClearRange;
  RegisterHandlers;
  HandleWindowsPtyOptionChange;          { headless Terminal's constructor: _setup() }
end;

destructor TTyTerminalCore.Destroy;
var
  i: Integer;
begin
  ClearQueue;                            { pending chunks are dropped, callbacks not called }
  FParser.Free;
  { the buffers dispose their markers, which the link table listens to }
  FBufferService.Free;
  FLinks.Free;
  for i := 0 to FCharsetHandlers.Count - 1 do
    TObject(FCharsetHandlers[i]).Free;
  FCharsetHandlers.Free;
  FOscData.Free;
  FDecoder.Free;
  FOptions.Free;
  inherited Destroy;
end;

function Id(const APrefix, AIntermediates: string; AFinal: Char): TTyTerminalFunctionId; inline;
begin
  Result := TyTerminalFunctionId(APrefix, AIntermediates, AFinal);
end;

{ InputHandler.ts:180-378, in the same order: the order decides a chain's order }
procedure TTyTerminalCore.RegisterHandlers;
var
  p: TTyTerminalParser;
  k, i: Integer;
  h: TTyTermCharsetHandler;
const
  Intermediates = '()*+-./';
begin
  p := FParser;
  p.SetPrintHandler(@PrintHandler);
  p.SetOscHandlerFallback(@OscFallback);
  { CSI }
  p.RegisterCsiHandler(Id('', '', '@'), @InsertChars);
  p.RegisterCsiHandler(Id('', ' ', '@'), @ScrollLeft);
  p.RegisterCsiHandler(Id('', '', 'A'), @CursorUp);
  p.RegisterCsiHandler(Id('', ' ', 'A'), @ScrollRight);
  p.RegisterCsiHandler(Id('', '', 'B'), @CursorDown);
  p.RegisterCsiHandler(Id('', '', 'C'), @CursorForward);
  p.RegisterCsiHandler(Id('', '', 'D'), @CursorBackward);
  p.RegisterCsiHandler(Id('', '', 'E'), @CursorNextLine);
  p.RegisterCsiHandler(Id('', '', 'F'), @CursorPrecedingLine);
  p.RegisterCsiHandler(Id('', '', 'G'), @CursorCharAbsolute);
  p.RegisterCsiHandler(Id('', '', 'H'), @CursorPosition);
  p.RegisterCsiHandler(Id('', '', 'I'), @CursorForwardTab);
  p.RegisterCsiHandler(Id('', '', 'J'), @EraseInDisplayCsi);
  p.RegisterCsiHandler(Id('?', '', 'J'), @EraseInDisplayProtected);
  p.RegisterCsiHandler(Id('', '', 'K'), @EraseInLineCsi);
  p.RegisterCsiHandler(Id('?', '', 'K'), @EraseInLineProtected);
  p.RegisterCsiHandler(Id('', '', 'L'), @InsertLines);
  p.RegisterCsiHandler(Id('', '', 'M'), @DeleteLines);
  p.RegisterCsiHandler(Id('', '', 'P'), @DeleteChars);
  p.RegisterCsiHandler(Id('', '', 'S'), @ScrollUp);
  p.RegisterCsiHandler(Id('', '', 'T'), @ScrollDown);
  p.RegisterCsiHandler(Id('', '', 'X'), @EraseChars);
  p.RegisterCsiHandler(Id('', '', 'Z'), @CursorBackwardTab);
  p.RegisterCsiHandler(Id('', '', '^'), @ScrollDown);
  p.RegisterCsiHandler(Id('', '', '`'), @CharPosAbsolute);
  p.RegisterCsiHandler(Id('', '', 'a'), @HPositionRelative);
  p.RegisterCsiHandler(Id('', '', 'b'), @RepeatPrecedingCharacter);
  p.RegisterCsiHandler(Id('', '', 'c'), @SendDeviceAttributesPrimary);
  p.RegisterCsiHandler(Id('>', '', 'c'), @SendDeviceAttributesSecondary);
  p.RegisterCsiHandler(Id('', '', 'd'), @LinePosAbsolute);
  p.RegisterCsiHandler(Id('', '', 'e'), @VPositionRelative);
  p.RegisterCsiHandler(Id('', '', 'f'), @HVPosition);
  p.RegisterCsiHandler(Id('', '', 'g'), @TabClear);
  p.RegisterCsiHandler(Id('', '', 'h'), @SetModeCsi);
  p.RegisterCsiHandler(Id('?', '', 'h'), @SetModePrivate);
  p.RegisterCsiHandler(Id('', '', 'l'), @ResetModeCsi);
  p.RegisterCsiHandler(Id('?', '', 'l'), @ResetModePrivate);
  p.RegisterCsiHandler(Id('', '', 'm'), @CharAttributes);
  p.RegisterCsiHandler(Id('', '', 'n'), @DeviceStatus);
  p.RegisterCsiHandler(Id('?', '', 'n'), @DeviceStatusPrivate);
  p.RegisterCsiHandler(Id('', '!', 'p'), @SoftReset);
  p.RegisterCsiHandler(Id('>', '', 'q'), @SendXtVersion);
  p.RegisterCsiHandler(Id('', ' ', 'q'), @SetCursorStyleCsi);
  p.RegisterCsiHandler(Id('', '', 'r'), @SetScrollRegion);
  p.RegisterCsiHandler(Id('', '', 's'), @SaveCursorCsi);
  p.RegisterCsiHandler(Id('', '', 't'), @WindowOptionsCsi);
  p.RegisterCsiHandler(Id('', '', 'u'), @RestoreCursorCsi);
  p.RegisterCsiHandler(Id('', '''', '}'), @InsertColumns);
  p.RegisterCsiHandler(Id('', '''', '~'), @DeleteColumns);
  p.RegisterCsiHandler(Id('', '"', 'q'), @SelectProtected);
  p.RegisterCsiHandler(Id('', '$', 'p'), @RequestModeAnsi);
  p.RegisterCsiHandler(Id('?', '$', 'p'), @RequestModePrivate);
  p.RegisterCsiHandler(Id('=', '', 'u'), @KittyKeyboardSet);
  p.RegisterCsiHandler(Id('?', '', 'u'), @KittyKeyboardQuery);
  p.RegisterCsiHandler(Id('>', '', 'u'), @KittyKeyboardPush);
  p.RegisterCsiHandler(Id('<', '', 'u'), @KittyKeyboardPop);
  { execute }
  p.SetExecuteHandler($07, @Bell);
  p.SetExecuteHandler($0A, @LineFeed);
  p.SetExecuteHandler($0B, @LineFeed);
  p.SetExecuteHandler($0C, @LineFeed);
  p.SetExecuteHandler($0D, @CarriageReturn);
  p.SetExecuteHandler($08, @Backspace);
  p.SetExecuteHandler($09, @Tab);
  p.SetExecuteHandler($0E, @ShiftOut);
  p.SetExecuteHandler($0F, @ShiftIn);
  p.SetExecuteHandler($84, @Index);        { C1 IND }
  p.SetExecuteHandler($85, @NextLine);     { C1 NEL }
  p.SetExecuteHandler($88, @TabSet);       { C1 HTS }
  { OSC }
  p.RegisterOscHandler(0, TTyTerminalOscStringHandler.Create(@OscTitleAndIcon));
  p.RegisterOscHandler(1, TTyTerminalOscStringHandler.Create(@OscIconName));
  p.RegisterOscHandler(2, TTyTerminalOscStringHandler.Create(@OscTitle));
  p.RegisterOscHandler(4, TTyTerminalOscStringHandler.Create(@OscIndexedColor));
  p.RegisterOscHandler(8, TTyTerminalOscStringHandler.Create(@OscHyperlink));
  p.RegisterOscHandler(10, TTyTerminalOscStringHandler.Create(@OscFgColor));
  p.RegisterOscHandler(11, TTyTerminalOscStringHandler.Create(@OscBgColor));
  p.RegisterOscHandler(12, TTyTerminalOscStringHandler.Create(@OscCursorColor));
  p.RegisterOscHandler(104, TTyTerminalOscStringHandler.Create(@OscRestoreIndexedColor));
  p.RegisterOscHandler(110, TTyTerminalOscStringHandler.Create(@OscRestoreFgColor));
  p.RegisterOscHandler(111, TTyTerminalOscStringHandler.Create(@OscRestoreBgColor));
  p.RegisterOscHandler(112, TTyTerminalOscStringHandler.Create(@OscRestoreCursorColor));
  { ESC }
  p.RegisterEscHandler(Id('', '', '7'), @SaveCursor);
  p.RegisterEscHandler(Id('', '', '8'), @RestoreCursor);
  p.RegisterEscHandler(Id('', '', 'D'), @Index);
  p.RegisterEscHandler(Id('', '', 'E'), @NextLine);
  p.RegisterEscHandler(Id('', '', 'H'), @TabSet);
  p.RegisterEscHandler(Id('', '', 'M'), @ReverseIndex);
  p.RegisterEscHandler(Id('', '', '='), @KeypadApplicationMode);
  p.RegisterEscHandler(Id('', '', '>'), @KeypadNumericMode);
  p.RegisterEscHandler(Id('', '', 'c'), @FullReset);
  p.RegisterEscHandler(Id('', '', 'n'), @SetGLevel2);
  p.RegisterEscHandler(Id('', '', 'o'), @SetGLevel3);
  p.RegisterEscHandler(Id('', '', '|'), @SetGLevel3);
  p.RegisterEscHandler(Id('', '', '}'), @SetGLevel2);
  p.RegisterEscHandler(Id('', '', '~'), @SetGLevel1);
  p.RegisterEscHandler(Id('', '%', '@'), @SelectDefaultCharset);
  p.RegisterEscHandler(Id('', '%', 'G'), @SelectDefaultCharset);
  for k := 0 to TyTermCharsetKeyCount - 1 do
    for i := 1 to Length(Intermediates) do
    begin
      h := TTyTermCharsetHandler.Create;
      h.Core := Self;
      h.Designation := Intermediates[i] + TyTermCharsetKeys[k];
      FCharsetHandlers.Add(h);
      p.RegisterEscHandler(Id('', Intermediates[i], TyTermCharsetKeys[k]), @h.Run);
    end;
  p.RegisterEscHandler(Id('', '#', '8'), @ScreenAlignmentPattern);
  { DCS }
  p.RegisterDcsHandler(Id('', '$', 'q'), TTyTerminalDcsStringHandler.Create(@RequestStatusString));
end;

{ ---- wiring ------------------------------------------------------------------------------ }

{ CoreTerminal.ts:152-156: a buffer scroll is an onScroll with the viewport position
  and marks the scroll region dirty }
procedure TTyTerminalCore.BufferScrolled(AYDisp: Integer);
begin
  if Assigned(FOnScroll) then
    FOnScroll(Self, AYDisp);
  MarkRangeDirty(Buffer.ScrollTop, Buffer.ScrollBottom);
end;

procedure TTyTerminalCore.BufferActivated(AActive, AInactive: TTyTerminalBuffer);
begin
  if Assigned(FOnBufferActivate) then
    FOnBufferActivate(Self);
end;

function TTyTerminalCore.GetBuffer: TTyTerminalBuffer;
begin
  Result := FBufferService.Buffer;
end;

function TTyTerminalCore.GetBuffers: TTyTerminalBufferSet;
begin
  Result := FBufferService.Buffers;
end;

function TTyTerminalCore.GetCols: Integer;
begin
  Result := FBufferService.Cols;
end;

function TTyTerminalCore.GetRows: Integer;
begin
  Result := FBufferService.Rows;
end;

{ ---- CoreService (CoreService.ts) --------------------------------------------------------- }

procedure TTyTerminalCore.CoreServiceReset;                                  { :68-72 }
begin
  { modes and kitty state; isCursorHidden and isCursorInitialized stay }
  FInsertMode := False;
  FApplicationCursorKeys := False;
  FApplicationKeypad := False;
  FBracketedPasteMode := False;
  FColorSchemeUpdates := False;
  FCursorBlinkRequest := tbrDefault;
  FCursorStyleRequest := tcrDefault;
  FOrigin := False;
  FReverseWraparound := False;
  FSendFocus := False;
  FSynchronizedOutput := False;
  FWin32InputMode := False;
  FWraparound := True;
  FKittyFlags := 0;
  FKittyMainFlags := 0;
  FKittyAltFlags := 0;
  FKittyMainStack := nil;
  FKittyAltStack := nil;
end;

procedure TTyTerminalCore.TriggerDataEvent(const AData: RawByteString; AWasUserInput: Boolean);
var
  buf: TTyTerminalBuffer;
begin                                                                        { :74-95 }
  if FOptions.DisableStdin then
    Exit;
  buf := Buffer;
  if AWasUserInput and FOptions.ScrollOnUserInput and (buf.YBase <> buf.YDisp) then
  begin
    if Assigned(FOnRequestScrollToBottom) then
      FOnRequestScrollToBottom(Self);
    ScrollToBottom;                      { CoreTerminal.ts:150 }
  end;
  if AWasUserInput then
    FDidUserInput := True;               { CoreTerminal.ts:151 -> WriteBuffer.handleUserInput }
  if Assigned(FOnData) then
    FOnData(Self, AData);
end;

function TTyTerminalCore.GetModes: TTyTerminalModes;
begin
  Result.ApplicationCursorKeys := FApplicationCursorKeys;
  Result.ApplicationKeypad := FApplicationKeypad;
  Result.BracketedPaste := FBracketedPasteMode;
  Result.Insert := FInsertMode;
  Result.Origin := FOrigin;
  Result.ReverseWraparound := FReverseWraparound;
  Result.SendFocus := FSendFocus;
  Result.ShowCursor := not FIsCursorHidden;
  Result.SynchronizedOutput := FSynchronizedOutput;
  Result.Win32Input := FWin32InputMode;
  Result.Wraparound := FWraparound;
  Result.ColorSchemeUpdates := FColorSchemeUpdates;
  Result.MouseProtocol := FMouseProtocol;
  Result.MouseEncoding := FMouseEncoding;
  Result.CursorRequest := FCursorStyleRequest;
  Result.BlinkRequest := FCursorBlinkRequest;
end;

function SameModes(const A, B: TTyTerminalModes): Boolean;
begin
  Result := (A.ApplicationCursorKeys = B.ApplicationCursorKeys) and (A.ApplicationKeypad = B.ApplicationKeypad)
    and (A.BracketedPaste = B.BracketedPaste) and (A.Insert = B.Insert) and (A.Origin = B.Origin)
    and (A.ReverseWraparound = B.ReverseWraparound) and (A.SendFocus = B.SendFocus)
    and (A.ShowCursor = B.ShowCursor) and (A.SynchronizedOutput = B.SynchronizedOutput)
    and (A.Win32Input = B.Win32Input) and (A.Wraparound = B.Wraparound)
    and (A.ColorSchemeUpdates = B.ColorSchemeUpdates) and (A.MouseProtocol = B.MouseProtocol)
    and (A.MouseEncoding = B.MouseEncoding) and (A.CursorRequest = B.CursorRequest)
    and (A.BlinkRequest = B.BlinkRequest);
end;

{ OnModesChange: once per sequence that changed a mode (upstream has no such event) }
procedure TTyTerminalCore.ModesChangedSince(const ABefore: TTyTerminalModes);
begin
  if Assigned(FOnModesChange) and not SameModes(ABefore, GetModes) then
    FOnModesChange(Self);
end;

{ ---- CharsetService ------------------------------------------------------------------------ }

procedure TTyTerminalCore.CharsetReset;
begin
  FCharset := 0;
  FCharsets := nil;
  FGLevel := 0;
end;

procedure TTyTerminalCore.SetGLevel(AG: Integer);
begin
  FGLevel := AG;
  FCharset := CharsetOfG(AG);
end;

procedure TTyTerminalCore.SetGCharset(AG: Integer; ACharset: TTyTermCharsetId);
var
  i, old: Integer;
begin
  if AG < 0 then
    Exit;
  if AG > High(FCharsets) then
  begin
    old := Length(FCharsets);
    SetLength(FCharsets, AG + 1);
    for i := old to AG do
      FCharsets[i] := 0;                 { holes: undefined }
  end;
  FCharsets[AG] := ACharset;
  if FGLevel = AG then
    FCharset := ACharset;
end;

function TTyTerminalCore.CharsetOfG(AG: Integer): TTyTermCharsetId;
begin
  if (AG >= 0) and (AG <= High(FCharsets)) then
    Result := FCharsets[AG]
  else
    Result := 0;
end;

function TTyTerminalCore.CharsetKey(AId: TTyTermCharsetId): string;
var
  k: Integer;
begin
  Result := '';
  if AId = 0 then
    Exit;
  for k := 0 to TyTermCharsetKeyCount - 1 do
    if TyTermCharsetOfKey[k] = AId then
      Exit(TyTermCharsetKeys[k]);
end;

{ ---- MouseStateService (MouseStateService.ts) ---------------------------------------------- }

procedure TTyTerminalCore.SetMouseProtocol(AValue: TTyTerminalMouseProtocol);
begin
  FMouseProtocol := AValue;
end;

{ the five restrict functions, :13-83 }
function TTyTerminalCore.RestrictMouseEvent(var AEvent: TTyTerminalMouseEvent): Boolean;
begin
  case FMouseProtocol of
    tmpNone: Result := False;
    tmpX10:
      begin
        { no wheel, no move, no up, no modifiers }
        if (AEvent.Button = tmbWheel) or (AEvent.Action <> tmaDown) then
          Exit(False);
        AEvent.Ctrl := False;
        AEvent.Alt := False;
        AEvent.Shift := False;
        Result := True;
      end;
    tmpVT200: Result := AEvent.Action <> tmaMove;
    tmpDrag: Result := not ((AEvent.Action = tmaMove) and (AEvent.Button = tmbNone));
  else
    Result := True;
  end;
end;

{ eventCode, :92-113 }
function MouseEventCode(const E: TTyTerminalMouseEvent; AIsSgr: Boolean): Integer;
var
  button: Integer;
begin
  Result := 0;
  if E.Ctrl then Result := Result or 16;
  if E.Shift then Result := Result or 4;
  if E.Alt then Result := Result or 8;
  button := Ord(E.Button);
  if E.Button = tmbWheel then
  begin
    Result := Result or 64;
    Result := Result or TyTermMouseActionCode(E.Action);
  end
  else
  begin
    Result := Result or (button and 3);
    if button and 4 <> 0 then Result := Result or 64;
    if button and 8 <> 0 then Result := Result or 128;
    if E.Action = tmaMove then
      Result := Result or 32
    else if (E.Action = tmaUp) and not AIsSgr then
      Result := Result or Ord(tmbNone);  { only SGR reports the released button }
  end;
end;

{ the three encodings, :121-151; the default one is bytes (spec 3.3) }
function TTyTerminalCore.EncodeMouseEvent(const AEvent: TTyTerminalMouseEvent): RawByteString;
var
  p0, p1, p2: Integer;
  fin: Char;
begin
  case FMouseEncoding of
    tmeDefault:
      begin
        p0 := MouseEventCode(AEvent, False) + 32;
        p1 := AEvent.Col + 32;
        p2 := AEvent.Row + 32;
        { past the addressable range: no report (as vte and konsole) }
        if (p0 > 255) or (p1 > 255) or (p2 > 255) then
          Exit('');
        Result := #27'[M' + Chr(p0) + Chr(p1) + Chr(p2);
      end;
  else
    if (AEvent.Action = tmaUp) and (AEvent.Button <> tmbWheel) then fin := 'm' else fin := 'M';
    if FMouseEncoding = tmeSgr then
      Result := Format(#27'[<%d;%d;%d%s', [MouseEventCode(AEvent, True), AEvent.Col, AEvent.Row, fin])
    else
      Result := Format(#27'[<%d;%d;%d%s', [MouseEventCode(AEvent, True), AEvent.X, AEvent.Y, fin]);
  end;
end;

{ ---- colours and focus ----------------------------------------------------------------------- }

function TTyTerminalCore.ResolveColor(AIndex: Integer): Cardinal;
begin
  Result := 0;
  if (AIndex < 0) or (AIndex > 258) then
    Exit;
  if FOverrides[AIndex].IsSet then
    Exit(FOverrides[AIndex].Rgb);
  if Assigned(FOnQueryBaseColor) then
    FOnQueryBaseColor(Self, AIndex, Result);
end;

function TTyTerminalCore.HasColorOverride(AIndex: Integer): Boolean;
begin
  Result := (AIndex >= 0) and (AIndex <= 258) and FOverrides[AIndex].IsSet;
end;

{ CoreBrowserTerminal.ts:238-240 }
procedure TTyTerminalCore.ReportColor(AIndex: Integer);
var
  ident: string;
begin
  case AIndex of
    ColorFg: ident := '10';
    ColorBg: ident := '11';
    ColorCursor: ident := '12';
  else
    ident := '4;' + IntToStr(AIndex);
  end;
  TriggerDataEvent(#27']' + ident + ';' + TyTermToRgbString(ResolveColor(AIndex)) + #27'\');
end;

procedure TTyTerminalCore.SetColor(AIndex: Integer; ARgb: Cardinal);
begin
  FOverrides[AIndex].IsSet := True;
  FOverrides[AIndex].Rgb := ARgb and $FFFFFF;
  ColorsChanged;                         { modifyColors fires onChangeColors }
end;

procedure TTyTerminalCore.RestoreColor(AIndex: Integer);
var
  i: Integer;
begin
  { no index restores the 256 palette entries only (ThemeService.ts:156-161) }
  if AIndex < 0 then
    for i := 0 to 255 do
      FOverrides[i].IsSet := False
  else
    FOverrides[AIndex].IsSet := False;
  ColorsChanged;                         { restoreColor fires onChangeColors }
end;

{ CoreBrowserTerminal.ts:526-531: every colour change reports when 2031 is on }
procedure TTyTerminalCore.ColorsChanged;
begin
  if FColorSchemeUpdates then
    ReportColorScheme;
end;

{ CoreBrowserTerminal.ts:261-268 }
procedure TTyTerminalCore.ReportColorScheme;
var
  mode: Integer;
begin
  if TyTermRelativeLuminance(ResolveColor(ColorBg)) < TyTermRelativeLuminance(ResolveColor(ColorFg)) then
    mode := 1
  else
    mode := 2;
  TriggerDataEvent(#27'[?997;' + IntToStr(mode) + 'n');
end;

procedure TTyTerminalCore.NotifyColorSchemeChanged;
var
  i: Integer;
begin
  { a new theme rebuilds the whole colour set upstream: the overrides go }
  for i := 0 to High(FOverrides) do
    FOverrides[i].IsSet := False;
  ColorsChanged;
end;

{ CoreBrowserTerminal.ts:1124-1130, sent when DECSET 1004 is turned on }
procedure TTyTerminalCore.ReportFocusNow;
begin
  if FFocused then
    TriggerDataEvent(#27'[I')
  else
    TriggerDataEvent(#27'[O');
end;

{ CoreBrowserTerminal.ts:305-331 }
procedure TTyTerminalCore.ReportFocus(AFocused: Boolean);
begin
  FFocused := AFocused;
  if FSendFocus then
    ReportFocusNow;
end;

{ ---- DirtyRowTracker ---------------------------------------------------------------------------- }

procedure TTyTerminalCore.ClearRange;
begin
  FDirtyStart := Buffer.Y;
  FDirtyEnd := Buffer.Y;
end;

procedure TTyTerminalCore.MarkDirty(AY: Integer);
begin
  if AY < FDirtyStart then
    FDirtyStart := AY
  else if AY > FDirtyEnd then
    FDirtyEnd := AY;
end;

procedure TTyTerminalCore.MarkRangeDirty(AY1, AY2: Integer);
var
  t: Integer;
begin
  if AY1 > AY2 then
  begin
    t := AY1;
    AY1 := AY2;
    AY2 := t;
  end;
  if AY1 < FDirtyStart then
    FDirtyStart := AY1;
  if AY2 > FDirtyEnd then
    FDirtyEnd := AY2;
end;

procedure TTyTerminalCore.MarkAllDirty;
begin
  MarkRangeDirty(0, Rows - 1);
end;

{ onRequestRefreshRows(undefined): headless maps it to the whole screen }
procedure TTyTerminalCore.RefreshAll;
begin
  if Assigned(FOnRefreshRows) then
    FOnRefreshRows(Self, 0, Rows - 1);
end;

{ ---- the old-ConPTY heuristics ------------------------------------------------------------------- }

procedure TTyTerminalCore.HandleWindowsPtyOptionChange;                      { CoreTerminal.ts:279-289 }
var
  value: Boolean;
begin
  value := (FOptions.WindowsPty.Backend <> twpNone) and (FOptions.WindowsPty.BuildNumber <> 0)
    and (FOptions.WindowsPty.Backend = twpConPty) and (FOptions.WindowsPty.BuildNumber < 21376);
  if value then
  begin
    if not FWindowsHeuristics then
    begin
      FWindowsHeuristics := True;
      { a CSI H handler that runs before cursorPosition and lets it through }
      FWindowsCsiHandle := FParser.RegisterCsiHandler(Id('', '', 'H'), @WindowsHeuristicCsiH);
    end;
  end
  else if FWindowsHeuristics then
  begin
    FWindowsHeuristics := False;
    FParser.Unregister(FWindowsCsiHandle);
    FWindowsCsiHandle := 0;
  end;
end;

function TTyTerminalCore.WindowsHeuristicCsiH(AParams: TTyTerminalParams): Boolean;
begin
  UpdateWindowsModeWrappedState;
  Result := False;
end;

{ WindowsMode.ts: mark the next line wrapped when the last character of this one is
  neither empty nor a space. For a combined cell upstream looks at the last UTF-16
  unit of its text, which is never 0 or 32 -- the same answer as its code point. }
procedure TTyTerminalCore.UpdateWindowsModeWrappedState;
var
  buf: TTyTerminalBuffer;
  line, nextLine: TTyTerminalLine;
  code: Cardinal;
begin
  buf := Buffer;
  line := buf.Lines.Get(buf.YBase + buf.Y - 1);
  nextLine := buf.Lines.Get(buf.YBase + buf.Y);
  if (nextLine <> nil) and (line <> nil) then
  begin
    code := line.GetCodePoint(Cols - 1);
    nextLine.IsWrapped := (code <> TyTermNullCellCode) and (code <> TyTermWhitespaceCellCode);
  end;
end;

{ ---- options ------------------------------------------------------------------------------------ }

function TTyTerminalCore.GetScrollback: Integer;
begin
  Result := FOptions.Scrollback;
end;

function TTyTerminalCore.GetTabStopWidth: Integer;
begin
  Result := FOptions.TabStopWidth;
end;

{ an option change event only fires for a different value (OptionsService.ts:135) }
procedure TTyTerminalCore.SetScrollback(AValue: Integer);
begin
  if AValue < 0 then
    raise EArgumentException.CreateFmt('scrollback cannot be less than 0, value: %d', [AValue]);
  if FOptions.Scrollback = AValue then
    Exit;
  FOptions.Scrollback := AValue;
  FBufferService.ScrollbackChanged;
end;

procedure TTyTerminalCore.SetTabStopWidth(AValue: Integer);
begin
  if AValue < 1 then
    raise EArgumentException.CreateFmt('tabStopWidth cannot be less than 1, value: %d', [AValue]);
  if FOptions.TabStopWidth = AValue then
    Exit;
  FOptions.TabStopWidth := AValue;
  FBufferService.TabStopWidthChanged;
end;

function TTyTerminalCore.GetWindowsPty: TTyTerminalWindowsPty;
begin
  Result := FOptions.WindowsPty;
end;

procedure TTyTerminalCore.SetWindowsPty(const AValue: TTyTerminalWindowsPty);
begin
  FOptions.WindowsPty := AValue;
  HandleWindowsPtyOptionChange;
end;

function TTyTerminalCore.GetOptBool(AIndex: Integer): Boolean;
begin
  case AIndex of
    0: Result := FOptions.ConvertEol;
    1: Result := FOptions.ScrollOnUserInput;
    2: Result := FOptions.DisableStdin;
    3: Result := FOptions.CursorBlink;
    4: Result := FOptions.ScrollOnEraseInDisplay;
  else
    Result := FOptions.AllowSetCursorBlink;
  end;
end;

procedure TTyTerminalCore.SetOptBool(AIndex: Integer; AValue: Boolean);
begin
  case AIndex of
    0: FOptions.ConvertEol := AValue;
    1: FOptions.ScrollOnUserInput := AValue;
    2: FOptions.DisableStdin := AValue;
    3: FOptions.CursorBlink := AValue;
    4: FOptions.ScrollOnEraseInDisplay := AValue;
  else
    FOptions.AllowSetCursorBlink := AValue;
  end;
end;

function TTyTerminalCore.GetCursorStyle: TTyTermCursorStyleOption;
begin
  Result := FOptions.CursorStyle;
end;

procedure TTyTerminalCore.SetCursorStyle(AValue: TTyTermCursorStyleOption);
begin
  FOptions.CursorStyle := AValue;
end;

{ ---- size, reset, scroll, input ------------------------------------------------------------------ }

procedure TTyTerminalCore.Resize(ACols, ARows: Integer);
begin
  { headless Terminal.ts:90-96, then CoreTerminal.ts:187-200 }
  if (ACols = Cols) and (ARows = Rows) then
    Exit;
  if ACols < TyTermMinimumCols then ACols := TyTermMinimumCols;
  if ARows < TyTermMinimumRows then ARows := TyTermMinimumRows;
  { pending writes are parsed at the old size first }
  FlushSync;
  FBufferService.Resize(ACols, ARows);
end;

{ headless Terminal.ts:122-132 -> CoreTerminal.ts:270-276. Partial on purpose (unit
  header): not the parser, the title, the link numbers, a hidden cursor. }
procedure TTyTerminalCore.Reset;
var
  before: TTyTerminalModes;
begin
  before := GetModes;
  HandleWindowsPtyOptionChange;          { _setup() }
  InputHandlerReset;
  FBufferService.Reset;
  CharsetReset;
  CoreServiceReset;
  SetMouseProtocol(tmpNone);             { mouseStateService.reset }
  FMouseEncoding := tmeDefault;
  ModesChangedSince(before);
end;

procedure TTyTerminalCore.ScrollLines(ADelta: Integer);
begin
  FBufferService.ScrollLines(ADelta);
end;

procedure TTyTerminalCore.ScrollPages(APages: Integer);
begin
  ScrollLines(APages * (Rows - 1));
end;

procedure TTyTerminalCore.ScrollToBottom;
begin
  ScrollLines(Buffer.YBase - Buffer.YDisp);
end;

procedure TTyTerminalCore.ScrollToTop;
begin
  ScrollLines(-Buffer.YDisp);
end;

{ headless Terminal.ts:101-112: the cursor's line becomes the first line }
procedure TTyTerminalCore.ClearScrollback;
var
  buf: TTyTerminalBuffer;
  row: TTyTerminalLine;
  i: Integer;
begin
  buf := Buffer;
  buf.ClearAllMarkers;
  row := buf.Lines.Get(buf.YBase + buf.Y);
  if row <> nil then
  begin
    { pinned: storing it in slot 0 can release the line that held it there }
    row.AddRef;
    try
      buf.Lines.SetItem(0, row);
    finally
      row.Release;
    end;
  end;
  buf.Lines.Length := 1;
  buf.YDisp := 0;
  buf.YBase := 0;
  buf.Y := 0;
  for i := 1 to Rows - 1 do
    buf.Lines.PushOwned(buf.GetBlankLine(TyTermDefaultAttr));
  { straight to onScroll, not through the buffer service: no dirty rows }
  if Assigned(FOnScroll) then
    FOnScroll(Self, buf.YDisp);
end;

procedure TTyTerminalCore.Input(const AData: RawByteString; AWasUserInput: Boolean);
begin
  TriggerDataEvent(AData, AWasUserInput);
end;

function TTyTerminalCore.WindowTitleStack: TStringDynArray;
begin
  Result := Copy(FWindowTitleStack);
end;

function TTyTerminalCore.IconNameStack: TStringDynArray;
begin
  Result := Copy(FIconNameStack);
end;

function TTyTerminalCore.KittyStacks(AAlt: Boolean): TIntegerDynArray;
begin
  if AAlt then
    Result := Copy(FKittyAltStack)
  else
    Result := Copy(FKittyMainStack);
end;

{ ==== InputHandler: parse, print, controls, cursor, erase, scroll ================================== }

{ parse, InputHandler.ts:430-485, without the async resume. The input is cut every
  131072 BYTES (MAX_PARSEBUFFER_LENGTH counts input units, and a byte is the unit
  here); the decoder and precedingJoinState carry across the cuts. }
procedure TTyTerminalCore.Parse(const AData: RawByteString);
var
  buf: TTyTerminalBuffer;
  cursorStartX, cursorStartY, total, i, chunk, len, viewportStart, viewportEnd: Integer;
begin
  buf := Buffer;
  cursorStartX := buf.X;
  cursorStartY := buf.Y;
  total := Length(AData);
  chunk := Min(total, TyTermMaxParseBuffer);
  if Length(FParseBuffer) < chunk then
    SetLength(FParseBuffer, chunk);
  { which rows the parse changes }
  ClearRange;
  i := 0;
  while i < total do
  begin
    chunk := Min(TyTermMaxParseBuffer, total - i);
    len := FDecoder.Decode(AData[i + 1], chunk, FParseBuffer);
    FParser.Parse(FParseBuffer, len);
    Inc(i, chunk);
  end;
  buf := Buffer;
  if (buf.X <> cursorStartX) or (buf.Y <> cursorStartY) then
    if Assigned(FOnCursorMove) then
      FOnCursorMove(Self);
  { the rows that changed, relative to the viewport (ydisp), not to ybase }
  viewportEnd := FDirtyEnd + (buf.YBase - buf.YDisp);
  viewportStart := FDirtyStart + (buf.YBase - buf.YDisp);
  if viewportStart < Rows then
    if Assigned(FOnRefreshRows) then
      FOnRefreshRows(Self, Min(viewportStart, Rows - 1), Min(viewportEnd, Rows - 1));
end;

procedure TTyTerminalCore.PrintHandler(const AData: array of Cardinal; AStart, AEnd: Integer);
begin
  DoPrint(AData, AStart, AEnd, 1);
end;

{ print, InputHandler.ts:517-661. ARepeat runs the same text that many times in ONE
  call, which is what REP's single print of the repeated text is upstream -- without
  building the repeated array (REP up to 2^20 times). The current row, and the old
  row across a wrap, are pinned: a scroll can drop them from the ring while print
  still writes to them, as upstream keeps writing to a detached line. }
procedure TTyTerminalCore.DoPrint(const AData: array of Cardinal; AStart, AEnd: Integer; ARepeat: Integer);
var
  buf: TTyTerminalBuffer;
  bufferRow, oldRow, ln: TTyTerminalLine;
  charset: TTyTermCharsetId;
  cols, r, pos, chWidth, oldWidth, oldCol, offset, delta: Integer;
  code, m: Cardinal;
  wraparound, insert, shouldJoin: Boolean;
  precedingJoinState, currentInfo: TTyUnicodeCharProps;
  total: Int64;
  linkId: Integer;
begin
  charset := FCharset;
  cols := Cols;
  wraparound := FWraparound;
  insert := FInsertMode;
  buf := Buffer;
  bufferRow := buf.Lines.Get(buf.YBase + buf.Y);
  if bufferRow = nil then
    Exit;
  bufferRow.AddRef;
  oldRow := nil;
  try
    MarkDirty(buf.Y);
    total := Int64(AEnd - AStart) * ARepeat;
    { overwriting the second cell of a wide character: reset the first }
    if (buf.X <> 0) and (total > 0) and (bufferRow.GetWidth(buf.X - 1) = 2) then
      bufferRow.SetCellFromCodepoint(buf.X - 1, 0, 1, FCurAttr);
    precedingJoinState := FParser.PrecedingJoinState;
    for r := 1 to ARepeat do
      for pos := AStart to AEnd - 1 do
      begin
        code := AData[pos];
        { soft hyphen: a zero-width layout hint, ignored (:546-548) }
        if code = $AD then
          Continue;
        { charset replacement, ASCII only }
        if (code < 127) and (charset <> 0) and (code >= $20) then
        begin
          m := TyTermCharsetMap[charset, code];
          if m <> 0 then
            code := m;
        end;
        currentInfo := TyUnicodeCharProperties(code, precedingJoinState, FUnicodeVersion, FAmbiguousWide);
        chWidth := TyUnicodePropsWidth(currentInfo);
        shouldJoin := TyUnicodePropsShouldJoin(currentInfo);
        if shouldJoin then
          oldWidth := TyUnicodePropsWidth(precedingJoinState)
        else
          oldWidth := 0;
        precedingJoinState := currentInfo;
        linkId := FCurAttr.Extended.UrlId;
        if linkId <> 0 then
          FLinks.AddLineToLink(linkId, buf.YBase + buf.Y);

        { the character does not fit: wrap (DECAWM) or stay in the last cell }
        if buf.X + chWidth - oldWidth > cols then
        begin
          if wraparound then
          begin
            oldRow := bufferRow;             { the pin moves with it }
            bufferRow := nil;
            oldCol := buf.X - oldWidth;
            buf.X := oldWidth;
            buf.Y := buf.Y + 1;
            if buf.Y = buf.ScrollBottom + 1 then
            begin
              buf.Y := buf.Y - 1;
              FBufferService.Scroll(EraseAttrData, True);
            end
            else
            begin
              if buf.Y >= Rows then
                buf.Y := Rows - 1;
              { an existing line (the initial viewport): mark it wrapped }
              ln := buf.Lines.Get(buf.YBase + buf.Y);
              if ln <> nil then
                ln.IsWrapped := True;
            end;
            bufferRow := buf.Lines.Get(buf.YBase + buf.Y);
            if bufferRow = nil then
              Exit;
            bufferRow.AddRef;
            { a combining character widened the last one: move it to the new line }
            if oldWidth > 0 then
              bufferRow.CopyCellsFrom(oldRow, oldCol, 0, oldWidth, False);
            { clear what is left to the right }
            while oldCol < cols do
            begin
              oldRow.SetCellFromCodepoint(oldCol, 0, 1, FCurAttr);
              Inc(oldCol);
            end;
            oldRow.Release;
            oldRow := nil;
          end
          else
          begin
            buf.X := cols - 1;
            { a wide character that does not fit the last cell is dropped }
            if chWidth = 2 then
              Continue;
          end;
        end;

        { a joining character goes onto the previous cell }
        if shouldJoin and (buf.X <> 0) then
        begin
          { after a wide character the empty stub sits in between }
          if bufferRow.GetWidth(buf.X - 1) <> 0 then
            offset := 1
          else
            offset := 2;
          bufferRow.AddCodepointToCell(buf.X - offset, code, chWidth);
          delta := chWidth - oldWidth;
          while delta > 0 do
          begin
            bufferRow.SetCellFromCodepoint(buf.X, 0, 0, FCurAttr);
            buf.X := buf.X + 1;
            Dec(delta);
          end;
          Continue;
        end;

        { insert mode: shift right; a wide character pushed into the last cell is lost }
        if insert then
        begin
          bufferRow.InsertCells(buf.X, chWidth - oldWidth, buf.GetNullCell(FCurAttr));
          if bufferRow.GetWidth(cols - 1) = 2 then
            bufferRow.SetCellFromCodepoint(cols - 1, TyTermNullCellCode, TyTermNullCellWidth, FCurAttr);
        end;

        bufferRow.SetCellFromCodepoint(buf.X, code, chWidth, FCurAttr);
        buf.X := buf.X + 1;
        { the cells after a wide character: empty stubs of width 0 }
        if chWidth > 0 then
        begin
          Dec(chWidth);
          while chWidth > 0 do
          begin
            bufferRow.SetCellFromCodepoint(buf.X, 0, 0, FCurAttr);
            buf.X := buf.X + 1;
            Dec(chWidth);
          end;
        end;
      end;
    FParser.PrecedingJoinState := precedingJoinState;
    { a lone second half of a wide character right of the cursor: reset it }
    if (buf.X < cols) and (total > 0) and (bufferRow.GetWidth(buf.X) = 0)
      and not bufferRow.HasContent(buf.X) then
      bufferRow.SetCellFromCodepoint(buf.X, 0, 1, FCurAttr);
    MarkDirty(buf.Y);
  finally
    if bufferRow <> nil then
      bufferRow.Release;
    if oldRow <> nil then
      oldRow.Release;
  end;
end;

{ _eraseAttrData, :3441-3445: only the background colour of the current attributes }
function TTyTerminalCore.EraseAttrData: TTyTerminalAttrData;
begin
  FEraseAttr.Bg := FEraseAttr.Bg and not Cardinal(TyTermAttrCmMask or $FFFFFF);
  FEraseAttr.Bg := FEraseAttr.Bg or (FCurAttr.Bg and not Cardinal($FC000000));
  Result := FEraseAttr;
end;

function ClampInt(AValue: Int64): Integer; inline;
begin
  if AValue > High(Integer) then
    Result := High(Integer)
  else if AValue < Low(Integer) then
    Result := Low(Integer)
  else
    Result := Integer(AValue);
end;

{ _restrictCursor, :873-880 }
procedure TTyTerminalCore.RestrictCursor(AMaxCol: Integer);
var
  buf: TTyTerminalBuffer;
begin
  buf := Buffer;
  if AMaxCol = -1 then
    AMaxCol := Cols - 1;
  buf.X := Min(AMaxCol, Max(0, buf.X));
  if FOrigin then
    buf.Y := Min(buf.ScrollBottom, Max(buf.ScrollTop, buf.Y))
  else
    buf.Y := Min(Rows - 1, Max(0, buf.Y));
  MarkDirty(buf.Y);
end;

{ _setCursor, :885-897, the sums in Int64 (a parameter can be 2^31 - 1) }
procedure TTyTerminalCore.SetCursor(AX, AY: Int64);
var
  buf: TTyTerminalBuffer;
begin
  buf := Buffer;
  MarkDirty(buf.Y);
  if FOrigin then
  begin
    buf.X := ClampInt(AX);
    buf.Y := ClampInt(buf.ScrollTop + AY);
  end
  else
  begin
    buf.X := ClampInt(AX);
    buf.Y := ClampInt(AY);
  end;
  RestrictCursor;
  MarkDirty(buf.Y);
end;

{ _moveCursor, :902-907 }
procedure TTyTerminalCore.MoveCursor(AX, AY: Int64);
begin
  RestrictCursor;
  SetCursor(Buffer.X + AX, Buffer.Y + AY);
end;

function P0or1(AParams: TTyTerminalParams): Integer; inline;
begin
  Result := AParams[0];
  if Result = 0 then
    Result := 1;
end;

function TTyTerminalCore.Bell: Boolean;                                      { :727-730 }
begin
  if Assigned(FOnBell) then
    FOnBell(Self);
  Result := True;
end;

function TTyTerminalCore.LineFeed: Boolean;                                  { :742-771 }
var
  buf: TTyTerminalBuffer;
  line: TTyTerminalLine;
begin
  buf := Buffer;
  MarkDirty(buf.Y);
  if FOptions.ConvertEol then
    buf.X := 0;
  buf.Y := buf.Y + 1;
  if buf.Y = buf.ScrollBottom + 1 then
  begin
    buf.Y := buf.Y - 1;
    FBufferService.Scroll(EraseAttrData);
  end
  else if buf.Y >= Rows then
    buf.Y := Rows - 1
  else
  begin
    { an explicit line feed: this line is not a wrapped continuation }
    line := buf.Lines.Get(buf.YBase + buf.Y);
    if line <> nil then
      line.IsWrapped := False;
  end;
  { at the end of the line, do not wrap on to the next one }
  if buf.X >= Cols then
    buf.X := buf.X - 1;
  MarkDirty(buf.Y);
  { onLineFeed: the Windows heuristic listens first (CoreTerminal.ts:293) }
  if FWindowsHeuristics then
    UpdateWindowsModeWrappedState;
  if Assigned(FOnLineFeed) then
    FOnLineFeed(Self);
  Result := True;
end;

function TTyTerminalCore.CarriageReturn: Boolean;                            { :777-780 }
begin
  Buffer.X := 0;
  Result := True;
end;

function TTyTerminalCore.Backspace: Boolean;                                 { :793-845 }
var
  buf: TTyTerminalBuffer;
  line: TTyTerminalLine;
begin
  buf := Buffer;
  if not FReverseWraparound then
  begin
    RestrictCursor;
    if buf.X > 0 then
      buf.X := buf.X - 1;
    Exit(True);
  end;
  { reverse wrap-around: x may be cols here to reach the last cell }
  RestrictCursor(Cols);
  if buf.X > 0 then
    buf.X := buf.X - 1
  else
  begin
    { only a soft wrap is undone, within the margins, never into the scrollback }
    line := buf.Lines.Get(buf.YBase + buf.Y);
    if (buf.X = 0) and (buf.Y > buf.ScrollTop) and (buf.Y <= buf.ScrollBottom)
      and (line <> nil) and line.IsWrapped then
    begin
      line.IsWrapped := False;
      buf.Y := buf.Y - 1;
      buf.X := Cols - 1;
      { an empty cell left by a wide character that wrapped early: one more back }
      line := buf.Lines.Get(buf.YBase + buf.Y);
      if (line <> nil) and line.HasWidth(buf.X) and not line.HasContent(buf.X) then
        buf.X := buf.X - 1;
    end;
  end;
  RestrictCursor;
  Result := True;
end;

function TTyTerminalCore.Tab: Boolean;                                       { :850-860 }
begin
  if Buffer.X >= Cols then
    Exit(True);
  Buffer.X := Buffer.NextStop;
  Result := True;
end;

function TTyTerminalCore.ShiftOut: Boolean;
begin
  SetGLevel(1);
  Result := True;
end;

function TTyTerminalCore.ShiftIn: Boolean;
begin
  SetGLevel(0);
  Result := True;
end;

function TTyTerminalCore.CursorUp(AParams: TTyTerminalParams): Boolean;     { :930-940 }
var
  diffToTop: Integer;
begin
  diffToTop := Buffer.Y - Buffer.ScrollTop;
  if diffToTop >= 0 then
    MoveCursor(0, -Min(Int64(diffToTop), P0or1(AParams)))
  else
    MoveCursor(0, -Int64(P0or1(AParams)));
  Result := True;
end;

function TTyTerminalCore.CursorDown(AParams: TTyTerminalParams): Boolean;   { :948-958 }
var
  diffToBottom: Integer;
begin
  diffToBottom := Buffer.ScrollBottom - Buffer.Y;
  if diffToBottom >= 0 then
    MoveCursor(0, Min(Int64(diffToBottom), P0or1(AParams)))
  else
    MoveCursor(0, P0or1(AParams));
  Result := True;
end;

function TTyTerminalCore.CursorForward(AParams: TTyTerminalParams): Boolean;
begin
  MoveCursor(P0or1(AParams), 0);
  Result := True;
end;

function TTyTerminalCore.CursorBackward(AParams: TTyTerminalParams): Boolean;
begin
  MoveCursor(-Int64(P0or1(AParams)), 0);
  Result := True;
end;

function TTyTerminalCore.CursorNextLine(AParams: TTyTerminalParams): Boolean;
begin
  CursorDown(AParams);
  Buffer.X := 0;
  Result := True;
end;

function TTyTerminalCore.CursorPrecedingLine(AParams: TTyTerminalParams): Boolean;
begin
  CursorUp(AParams);
  Buffer.X := 0;
  Result := True;
end;

function TTyTerminalCore.CursorCharAbsolute(AParams: TTyTerminalParams): Boolean;
begin
  SetCursor(Int64(P0or1(AParams)) - 1, Buffer.Y);
  Result := True;
end;

function TTyTerminalCore.CursorPosition(AParams: TTyTerminalParams): Boolean;  { :1036-1045 }
var
  col: Int64;
begin
  if AParams.Length >= 2 then
  begin
    col := AParams[1];
    if col = 0 then col := 1;
    col := col - 1;
  end
  else
    col := 0;
  SetCursor(col, Int64(P0or1(AParams)) - 1);
  Result := True;
end;

function TTyTerminalCore.CharPosAbsolute(AParams: TTyTerminalParams): Boolean;
begin
  SetCursor(Int64(P0or1(AParams)) - 1, Buffer.Y);
  Result := True;
end;

function TTyTerminalCore.HPositionRelative(AParams: TTyTerminalParams): Boolean;
begin
  MoveCursor(P0or1(AParams), 0);
  Result := True;
end;

function TTyTerminalCore.LinePosAbsolute(AParams: TTyTerminalParams): Boolean;
begin
  SetCursor(Buffer.X, Int64(P0or1(AParams)) - 1);
  Result := True;
end;

function TTyTerminalCore.VPositionRelative(AParams: TTyTerminalParams): Boolean;
begin
  MoveCursor(0, P0or1(AParams));
  Result := True;
end;

function TTyTerminalCore.HVPosition(AParams: TTyTerminalParams): Boolean;
begin
  CursorPosition(AParams);
  Result := True;
end;

function TTyTerminalCore.TabClear(AParams: TTyTerminalParams): Boolean;     { :1109-1119 }
begin
  case AParams[0] of
    0: Buffer.SetTab(Buffer.X, False);
    3: Buffer.ClearAllTabs;
  end;
  Result := True;
end;

{ CHT / CBT, :1125-1150. The count is clamped to the columns: every stop is reached
  by then and later passes stay put (unit header). }
function TTyTerminalCore.CursorForwardTab(AParams: TTyTerminalParams): Boolean;
var
  p: Integer;
begin
  if Buffer.X >= Cols then
    Exit(True);
  p := Min(P0or1(AParams), Cols);
  while p > 0 do
  begin
    Buffer.X := Buffer.NextStop;
    Dec(p);
  end;
  Result := True;
end;

function TTyTerminalCore.CursorBackwardTab(AParams: TTyTerminalParams): Boolean;
var
  p: Integer;
begin
  if Buffer.X >= Cols then
    Exit(True);
  p := Min(P0or1(AParams), Cols);
  while p > 0 do
  begin
    Buffer.X := Buffer.PrevStop;
    Dec(p);
  end;
  Result := True;
end;

function TTyTerminalCore.SelectProtected(AParams: TTyTerminalParams): Boolean;   { :1158-1163 }
var
  p: Integer;
begin
  p := AParams[0];
  if p = 1 then
    FCurAttr.Bg := FCurAttr.Bg or TyTermBgProtected;
  if (p = 2) or (p = 0) then
    FCurAttr.Bg := FCurAttr.Bg and not Cardinal(TyTermBgProtected);
  Result := True;
end;

procedure TTyTerminalCore.EraseInBufferLine(AY, AStart: Integer; AEnd: Int64; AClearWrap: Boolean;
  ARespectProtect: Boolean);
var
  line: TTyTerminalLine;
begin                                                                        { :1175-1190 }
  line := Buffer.Lines.Get(Buffer.YBase + AY);
  if line = nil then
    Exit;
  line.ReplaceCells(AStart, AEnd, Buffer.GetNullCell(EraseAttrData), ARespectProtect);
  if AClearWrap then
    line.IsWrapped := False;
end;

procedure TTyTerminalCore.ResetBufferLine(AY: Integer; ARespectProtect: Boolean);
var
  line: TTyTerminalLine;
begin                                                                        { :1196-1203 }
  line := Buffer.Lines.Get(Buffer.YBase + AY);
  if line <> nil then
  begin
    line.Fill(Buffer.GetNullCell(EraseAttrData), ARespectProtect);
    FBufferService.Buffer.ClearMarkers(Buffer.YBase + AY);
    line.IsWrapped := False;
  end;
end;

function TTyTerminalCore.EraseInDisplay(AParams: TTyTerminalParams; ARespectProtect: Boolean): Boolean;
var
  buf: TTyTerminalBuffer;
  j, scrollBackSize: Integer;
  found: Boolean;
  line: TTyTerminalLine;
begin                                                                        { :1229-1305 }
  buf := Buffer;
  RestrictCursor(Cols);
  case AParams[0] of
    0:
      begin
        j := buf.Y;
        MarkDirty(j);
        EraseInBufferLine(j, buf.X, Cols, buf.X = 0, ARespectProtect);
        Inc(j);
        while j < Rows do
        begin
          ResetBufferLine(j, ARespectProtect);
          Inc(j);
        end;
        MarkDirty(j);
      end;
    1:
      begin
        j := buf.Y;
        MarkDirty(j);
        { the front of the line and everything above: this line is not wrapped now }
        EraseInBufferLine(j, 0, Int64(buf.X) + 1, True, ARespectProtect);
        if buf.X + 1 >= Cols then
        begin
          { the whole line went: the next one cannot be a continuation. Upstream
            indexes lines.get(j + 1) without ybase; kept as it is. }
          line := buf.Lines.Get(j + 1);
          if line <> nil then
            line.IsWrapped := False;
        end;
        while j > 0 do
        begin
          Dec(j);
          ResetBufferLine(j, ARespectProtect);
        end;
        MarkDirty(0);
      end;
    2:
      if FOptions.ScrollOnEraseInDisplay then
      begin
        { push the screen, down to its last non-empty row, into the scrollback }
        j := Rows;
        MarkRangeDirty(0, j - 1);
        found := False;
        while j > 0 do
        begin
          Dec(j);
          line := buf.Lines.Get(buf.YBase + j);
          if (line <> nil) and (line.GetTrimmedLength <> 0) then
          begin
            found := True;
            Break;
          end;
        end;
        if not found then
          j := -1;
        while j >= 0 do
        begin
          FBufferService.Scroll(EraseAttrData);
          Dec(j);
        end;
      end
      else
      begin
        j := Rows;
        MarkDirty(j - 1);
        while j > 0 do
        begin
          Dec(j);
          ResetBufferLine(j, ARespectProtect);
        end;
        MarkDirty(0);
      end;
    3:
      begin
        { the scrollback: everything above the viewport }
        scrollBackSize := buf.Lines.Length - Rows;
        if scrollBackSize > 0 then
        begin
          buf.Lines.TrimStart(scrollBackSize);
          buf.YBase := Max(buf.YBase - scrollBackSize, 0);
          buf.YDisp := Max(buf.YDisp - scrollBackSize, 0);
          { isUserScrolling belongs to the normal buffer's viewport }
          if buf = Buffers.Normal then
            FBufferService.IsUserScrolling := False;
          { upstream then fires InputHandler.onScroll(0), which nothing listens to
            outside the browser: no OnScroll here }
        end;
      end;
  end;
  Result := True;
end;

function TTyTerminalCore.EraseInDisplayCsi(AParams: TTyTerminalParams): Boolean;
begin
  Result := EraseInDisplay(AParams, False);
end;

function TTyTerminalCore.EraseInDisplayProtected(AParams: TTyTerminalParams): Boolean;
begin
  Result := EraseInDisplay(AParams, True);
end;

function TTyTerminalCore.EraseInLine(AParams: TTyTerminalParams; ARespectProtect: Boolean): Boolean;
var
  buf: TTyTerminalBuffer;
begin                                                                        { :1324-1340 }
  buf := Buffer;
  RestrictCursor(Cols);
  case AParams[0] of
    0: EraseInBufferLine(buf.Y, buf.X, Cols, buf.X = 0, ARespectProtect);
    1: EraseInBufferLine(buf.Y, 0, Int64(buf.X) + 1, False, ARespectProtect);
    2: EraseInBufferLine(buf.Y, 0, Cols, True, ARespectProtect);
  end;
  MarkDirty(buf.Y);
  Result := True;
end;

function TTyTerminalCore.EraseInLineCsi(AParams: TTyTerminalParams): Boolean;
begin
  Result := EraseInLine(AParams, False);
end;

function TTyTerminalCore.EraseInLineProtected(AParams: TTyTerminalParams): Boolean;
begin
  Result := EraseInLine(AParams, True);
end;

{ IL, :1350-1373. The count is clamped to the lines from the cursor to the bottom
  margin: by then the region is blank and later passes change nothing. }
function TTyTerminalCore.InsertLines(AParams: TTyTerminalParams): Boolean;
var
  buf: TTyTerminalBuffer;
  p, row, scrollBottomRowsOffset, scrollBottomAbsolute: Integer;
begin
  buf := Buffer;
  RestrictCursor;
  p := P0or1(AParams);
  if (buf.Y > buf.ScrollBottom) or (buf.Y < buf.ScrollTop) then
    Exit(True);
  row := buf.YBase + buf.Y;
  scrollBottomRowsOffset := Rows - 1 - buf.ScrollBottom;
  scrollBottomAbsolute := Rows - 1 + buf.YBase - scrollBottomRowsOffset + 1;
  p := Min(p, buf.ScrollBottom - buf.Y + 1);
  while p > 0 do
  begin
    { blankLine(true): xterm and linux blank with the erase attributes }
    buf.Lines.Splice(scrollBottomAbsolute - 1, 1, []);
    buf.Lines.SpliceOwned(row, 0, buf.GetBlankLine(EraseAttrData));
    Dec(p);
  end;
  MarkRangeDirty(buf.Y, buf.ScrollBottom);
  buf.X := 0;
  Result := True;
end;

{ DL, :1383-1405, clamped as IL }
function TTyTerminalCore.DeleteLines(AParams: TTyTerminalParams): Boolean;
var
  buf: TTyTerminalBuffer;
  p, row, j: Integer;
begin
  buf := Buffer;
  RestrictCursor;
  p := P0or1(AParams);
  if (buf.Y > buf.ScrollBottom) or (buf.Y < buf.ScrollTop) then
    Exit(True);
  row := buf.YBase + buf.Y;
  j := Rows - 1 - buf.ScrollBottom;
  j := Rows - 1 + buf.YBase - j;
  p := Min(p, buf.ScrollBottom - buf.Y + 1);
  while p > 0 do
  begin
    buf.Lines.Splice(row, 1, []);
    buf.Lines.SpliceOwned(j, 0, buf.GetBlankLine(EraseAttrData));
    Dec(p);
  end;
  MarkRangeDirty(buf.Y, buf.ScrollBottom);
  buf.X := 0;
  Result := True;
end;

function TTyTerminalCore.InsertChars(AParams: TTyTerminalParams): Boolean;   { :1412-1425 }
var
  line: TTyTerminalLine;
begin
  RestrictCursor;
  line := Buffer.Lines.Get(Buffer.YBase + Buffer.Y);
  if line <> nil then
  begin
    line.InsertCells(Buffer.X, P0or1(AParams), Buffer.GetNullCell(EraseAttrData));
    MarkDirty(Buffer.Y);
  end;
  Result := True;
end;

function TTyTerminalCore.DeleteChars(AParams: TTyTerminalParams): Boolean;   { :1432-1445 }
var
  line: TTyTerminalLine;
begin
  RestrictCursor;
  line := Buffer.Lines.Get(Buffer.YBase + Buffer.Y);
  if line <> nil then
  begin
    line.DeleteCells(Buffer.X, P0or1(AParams), Buffer.GetNullCell(EraseAttrData));
    MarkDirty(Buffer.Y);
  end;
  Result := True;
end;

{ SU, :1464-1474, clamped to the region height (unit header) }
function TTyTerminalCore.ScrollUp(AParams: TTyTerminalParams): Boolean;
var
  buf: TTyTerminalBuffer;
  p: Integer;
begin
  buf := Buffer;
  p := Min(P0or1(AParams), Max(buf.ScrollBottom - buf.ScrollTop + 1, 0));
  while p > 0 do
  begin
    buf.Lines.Splice(buf.YBase + buf.ScrollTop, 1, []);
    buf.Lines.SpliceOwned(buf.YBase + buf.ScrollBottom, 0, buf.GetBlankLine(EraseAttrData));
    Dec(p);
  end;
  MarkRangeDirty(buf.ScrollTop, buf.ScrollBottom);
  Result := True;
end;

{ SD, :1480-1490: the new lines take the DEFAULT attributes, not the erase ones }
function TTyTerminalCore.ScrollDown(AParams: TTyTerminalParams): Boolean;
var
  buf: TTyTerminalBuffer;
  p: Integer;
begin
  buf := Buffer;
  p := Min(P0or1(AParams), Max(buf.ScrollBottom - buf.ScrollTop + 1, 0));
  while p > 0 do
  begin
    buf.Lines.Splice(buf.YBase + buf.ScrollBottom, 1, []);
    buf.Lines.SpliceOwned(buf.YBase + buf.ScrollTop, 0, buf.GetBlankLine(TyTermDefaultAttr));
    Dec(p);
  end;
  MarkRangeDirty(buf.ScrollTop, buf.ScrollBottom);
  Result := True;
end;

function TTyTerminalCore.ScrollLeft(AParams: TTyTerminalParams): Boolean;   { :1510-1523 }
var
  buf: TTyTerminalBuffer;
  p, y: Integer;
  line: TTyTerminalLine;
begin
  buf := Buffer;
  if (buf.Y > buf.ScrollBottom) or (buf.Y < buf.ScrollTop) then
    Exit(True);
  p := P0or1(AParams);
  for y := buf.ScrollTop to buf.ScrollBottom do
  begin
    line := buf.Lines.Get(buf.YBase + y);
    if line = nil then Continue;
    line.DeleteCells(0, p, buf.GetNullCell(EraseAttrData));
    line.IsWrapped := False;
  end;
  MarkRangeDirty(buf.ScrollTop, buf.ScrollBottom);
  Result := True;
end;

function TTyTerminalCore.ScrollRight(AParams: TTyTerminalParams): Boolean;  { :1543-1556 }
var
  buf: TTyTerminalBuffer;
  p, y: Integer;
  line: TTyTerminalLine;
begin
  buf := Buffer;
  if (buf.Y > buf.ScrollBottom) or (buf.Y < buf.ScrollTop) then
    Exit(True);
  p := P0or1(AParams);
  for y := buf.ScrollTop to buf.ScrollBottom do
  begin
    line := buf.Lines.Get(buf.YBase + y);
    if line = nil then Continue;
    line.InsertCells(0, p, buf.GetNullCell(EraseAttrData));
    line.IsWrapped := False;
  end;
  MarkRangeDirty(buf.ScrollTop, buf.ScrollBottom);
  Result := True;
end;

function TTyTerminalCore.InsertColumns(AParams: TTyTerminalParams): Boolean;   { :1564-1577 }
var
  buf: TTyTerminalBuffer;
  p, y: Integer;
  line: TTyTerminalLine;
begin
  buf := Buffer;
  if (buf.Y > buf.ScrollBottom) or (buf.Y < buf.ScrollTop) then
    Exit(True);
  p := P0or1(AParams);
  for y := buf.ScrollTop to buf.ScrollBottom do
  begin
    line := buf.Lines.Get(buf.YBase + y);
    if line = nil then Continue;
    line.InsertCells(buf.X, p, buf.GetNullCell(EraseAttrData));
    line.IsWrapped := False;
  end;
  MarkRangeDirty(buf.ScrollTop, buf.ScrollBottom);
  Result := True;
end;

function TTyTerminalCore.DeleteColumns(AParams: TTyTerminalParams): Boolean;   { :1585-1598 }
var
  buf: TTyTerminalBuffer;
  p, y: Integer;
  line: TTyTerminalLine;
begin
  buf := Buffer;
  if (buf.Y > buf.ScrollBottom) or (buf.Y < buf.ScrollTop) then
    Exit(True);
  p := P0or1(AParams);
  for y := buf.ScrollTop to buf.ScrollBottom do
  begin
    line := buf.Lines.Get(buf.YBase + y);
    if line = nil then Continue;
    line.DeleteCells(buf.X, p, buf.GetNullCell(EraseAttrData));
    line.IsWrapped := False;
  end;
  MarkRangeDirty(buf.ScrollTop, buf.ScrollBottom);
  Result := True;
end;

{ ECH, :1614-1626: x + n in Int64, so a 20-digit count erases to the end }
function TTyTerminalCore.EraseChars(AParams: TTyTerminalParams): Boolean;
var
  line: TTyTerminalLine;
begin
  RestrictCursor;
  line := Buffer.Lines.Get(Buffer.YBase + Buffer.Y);
  if line <> nil then
  begin
    line.ReplaceCells(Buffer.X, Int64(Buffer.X) + P0or1(AParams), Buffer.GetNullCell(EraseAttrData));
    MarkDirty(Buffer.Y);
  end;
  Result := True;
end;

{ REP, :1654-1678: the text of the cell before the cursor, printed again. Upstream
  builds text x count code points and prints them in one call; this prints the text
  count times in one call (DoPrint), count capped at 2^20 (unit header). }
function TTyTerminalCore.RepeatPrecedingCharacter(AParams: TTyTerminalParams): Boolean;
var
  joinState: TTyUnicodeCharProps;
  count, chWidth, x, i: Integer;
  row: TTyTerminalLine;
  cps: TIntegerDynArray;
  data: array of Cardinal;
begin
  joinState := FParser.PrecedingJoinState;
  if joinState = 0 then
    Exit(True);
  count := Min(P0or1(AParams), TyTermRepeatLimit);
  chWidth := TyUnicodePropsWidth(joinState);
  x := Buffer.X - chWidth;
  row := Buffer.Lines.Get(Buffer.YBase + Buffer.Y);
  if row = nil then
    Exit(True);
  cps := TyTermUtf8Codepoints(row.GetChars(x));
  data := nil;
  SetLength(data, Length(cps));
  for i := 0 to High(cps) do
    data[i] := Cardinal(cps[i]);
  DoPrint(data, 0, Length(data), count);
  Result := True;
end;

{ DECALN, :3470-3494 }
function TTyTerminalCore.ScreenAlignmentPattern: Boolean;
var
  cell: TTyTerminalCellData;
  yOffset: Integer;
  line: TTyTerminalLine;
begin
  cell.Content := (Cardinal(1) shl TyTermContentWidthShift) or Ord('E');
  cell.Fg := FCurAttr.Fg;
  cell.Bg := FCurAttr.Bg;
  cell.Ext.RawExt := 0;                  { a new CellData's own, empty, extended attributes }
  cell.Ext.UrlId := 0;
  cell.Combined := '';
  SetCursor(0, 0);
  for yOffset := 0 to Rows - 1 do
  begin
    line := Buffer.Lines.Get(Buffer.YBase + Buffer.Y + yOffset);
    if line <> nil then
    begin
      line.Fill(cell);
      line.IsWrapped := False;
    end;
  end;
  MarkAllDirty;
  SetCursor(0, 0);
  Result := True;
end;

{ IND, :3366-3378 }
function TTyTerminalCore.Index: Boolean;
var
  buf: TTyTerminalBuffer;
begin
  buf := Buffer;
  RestrictCursor;
  buf.Y := buf.Y + 1;
  if buf.Y = buf.ScrollBottom + 1 then
  begin
    buf.Y := buf.Y - 1;
    FBufferService.Scroll(EraseAttrData);
  end
  else if buf.Y >= Rows then
    buf.Y := Rows - 1;
  RestrictCursor;
  Result := True;
end;

function TTyTerminalCore.NextLine: Boolean;                                  { :3287-3291 }
begin
  Buffer.X := 0;
  Index;
  Result := True;
end;

function TTyTerminalCore.TabSet: Boolean;                                    { :3389-3392 }
begin
  Buffer.SetTab(Buffer.X, True);
  Result := True;
end;

{ RI, :3400-3419 }
function TTyTerminalCore.ReverseIndex: Boolean;
var
  buf: TTyTerminalBuffer;
  h: Integer;
begin
  buf := Buffer;
  RestrictCursor;
  if buf.Y = buf.ScrollTop then
  begin
    { at the top margin: the region moves down, a blank line comes in on top }
    h := buf.ScrollBottom - buf.ScrollTop;
    buf.Lines.ShiftElements(buf.YBase + buf.Y, h, 1);
    buf.Lines.SetItemOwned(buf.YBase + buf.Y, buf.GetBlankLine(EraseAttrData));
    MarkRangeDirty(buf.ScrollTop, buf.ScrollBottom);
  end
  else
  begin
    buf.Y := buf.Y - 1;
    RestrictCursor;
  end;
  Result := True;
end;

{ ==== InputHandler: modes, SGR, replies, cursor store, charsets, OSC, resets ======================= }

{ SM, :1797-1810 (20 = LNM changes the convertEol option) }
function TTyTerminalCore.SetModeCsi(AParams: TTyTerminalParams): Boolean;
var
  before: TTyTerminalModes;
  i: Integer;
begin
  before := GetModes;
  for i := 0 to AParams.Length - 1 do
    case AParams[i] of
      4: FInsertMode := True;
      20: FOptions.ConvertEol := True;
    end;
  ModesChangedSince(before);
  Result := True;
end;

{ RM, :2083-2096 }
function TTyTerminalCore.ResetModeCsi(AParams: TTyTerminalParams): Boolean;
var
  before: TTyTerminalModes;
  i: Integer;
begin
  before := GetModes;
  for i := 0 to AParams.Length - 1 do
    case AParams[i] of
      4: FInsertMode := False;
      20: FOptions.ConvertEol := False;
    end;
  ModesChangedSince(before);
  Result := True;
end;

{ DECSET, :1932-2071 }
function TTyTerminalCore.SetModePrivate(AParams: TTyTerminalParams): Boolean;
var
  before: TTyTerminalModes;
  i, p: Integer;
begin
  before := GetModes;
  for i := 0 to AParams.Length - 1 do
  begin
    p := AParams[i];
    case p of
      1: FApplicationCursorKeys := True;
      2:
        begin
          { set VT100 mode: every G back to the default }
          SetGCharset(0, 0);
          SetGCharset(1, 0);
          SetGCharset(2, 0);
          SetGCharset(3, 0);
        end;
      3:
        if twoSetWinLines in FWindowOptions then
        begin
          FBufferService.Resize(132, Rows);
          Reset;                         { onRequestReset -> headless reset }
        end;
      6:
        begin
          FOrigin := True;
          SetCursor(0, 0);
        end;
      7: FWraparound := True;
      12:
        if FOptions.AllowSetCursorBlink then
          FOptions.CursorBlink := True;
      45: FReverseWraparound := True;
      66: FApplicationKeypad := True;
      9: SetMouseProtocol(tmpX10);       { no release, no motion, no wheel, no modifiers }
      1000: SetMouseProtocol(tmpVT200);  { no motion }
      1002: SetMouseProtocol(tmpDrag);
      1003: SetMouseProtocol(tmpAny);
      1004:
        begin
          FSendFocus := True;
          ReportFocusNow;                { onRequestSendFocus: the browser reports at once }
        end;
      1005: ;                            { utf8 mouse, removed upstream (#2507) }
      1006: FMouseEncoding := tmeSgr;
      1015: ;                            { urxvt mouse, removed upstream (#2507) }
      1016: FMouseEncoding := tmeSgrPixels;
      25: FIsCursorHidden := False;
      1048: SaveCursor;
      47, 1047, 1049:
        begin
          if p = 1049 then
            SaveCursor;
          { kitty: save the main screen's flags, take the alt screen's }
          if tveKittyKeyboard in FVtExtensions then
          begin
            FKittyMainFlags := FKittyFlags;
            FKittyFlags := FKittyAltFlags;
          end;
          Buffers.ActivateAltBuffer(EraseAttrData);
          FIsCursorInitialized := True;
          RefreshAll;
        end;
      2004: FBracketedPasteMode := True;
      2026: FSynchronizedOutput := True;
      2031:
        if tveColorSchemeQuery in FVtExtensions then
          FColorSchemeUpdates := True;
      9001:
        if tveWin32InputMode in FVtExtensions then
          FWin32InputMode := True;
    end;
  end;
  ModesChangedSince(before);
  Result := True;
end;

{ DECRST, :2198-2317 }
function TTyTerminalCore.ResetModePrivate(AParams: TTyTerminalParams): Boolean;
var
  before: TTyTerminalModes;
  i, p: Integer;
begin
  before := GetModes;
  for i := 0 to AParams.Length - 1 do
  begin
    p := AParams[i];
    case p of
      1: FApplicationCursorKeys := False;
      3:
        if twoSetWinLines in FWindowOptions then
        begin
          FBufferService.Resize(80, Rows);
          Reset;
        end;
      6:
        begin
          FOrigin := False;
          SetCursor(0, 0);
        end;
      7: FWraparound := False;
      12:
        if FOptions.AllowSetCursorBlink then
          FOptions.CursorBlink := False;
      45: FReverseWraparound := False;
      66: FApplicationKeypad := False;
      9, 1000, 1002, 1003: SetMouseProtocol(tmpNone);
      1004: FSendFocus := False;
      1005: ;
      1006: FMouseEncoding := tmeDefault;
      1015: ;
      1016: FMouseEncoding := tmeDefault;
      25: FIsCursorHidden := True;
      1048: RestoreCursor;
      47, 1047, 1049:
        begin
          { kitty: save the alt screen's flags, take the main screen's }
          if tveKittyKeyboard in FVtExtensions then
          begin
            FKittyAltFlags := FKittyFlags;
            FKittyFlags := FKittyMainFlags;
          end;
          Buffers.ActivateNormalBuffer;
          if p = 1049 then
            RestoreCursor;
          FIsCursorInitialized := True;
          RefreshAll;
        end;
      2004: FBracketedPasteMode := False;
      2026:
        begin
          FSynchronizedOutput := False;
          RefreshAll;
        end;
      2031:
        if tveColorSchemeQuery in FVtExtensions then
          FColorSchemeUpdates := False;
      9001:
        if tveWin32InputMode in FVtExtensions then
          FWin32InputMode := False;
    end;
  end;
  ModesChangedSince(before);
  Result := True;
end;

{ DECRQM, :2336-2396; the reply is DECRPM }
function TTyTerminalCore.RequestMode(AParams: TTyTerminalParams; AAnsi: Boolean): Boolean;
const
  NotRecognized = 0;
  VSet = 1;
  VReset = 2;
  PermanentlySet = 3;
  PermanentlyReset = 4;
var
  p, v: Integer;

  function B2V(AValue: Boolean): Integer;
  begin
    if AValue then Result := VSet else Result := VReset;
  end;

begin
  p := AParams[0];
  if AAnsi then
    case p of
      2: v := PermanentlyReset;
      4: v := B2V(FInsertMode);
      12: v := PermanentlySet;
      20: v := B2V(FOptions.ConvertEol);
    else
      v := NotRecognized;
    end
  else
    case p of
      1: v := B2V(FApplicationCursorKeys);
      3:
        if twoSetWinLines in FWindowOptions then
        begin
          if Cols = 80 then v := VReset
          else if Cols = 132 then v := VSet
          else v := NotRecognized;
        end
        else
          v := NotRecognized;
      6: v := B2V(FOrigin);
      7: v := B2V(FWraparound);
      8: v := PermanentlySet;
      9: v := B2V(FMouseProtocol = tmpX10);
      12: v := B2V(FOptions.CursorBlink);
      25: v := B2V(not FIsCursorHidden);
      45: v := B2V(FReverseWraparound);
      66: v := B2V(FApplicationKeypad);
      67: v := PermanentlyReset;
      1000: v := B2V(FMouseProtocol = tmpVT200);
      1002: v := B2V(FMouseProtocol = tmpDrag);
      1003: v := B2V(FMouseProtocol = tmpAny);
      1004: v := B2V(FSendFocus);
      1005: v := PermanentlyReset;
      1006: v := B2V(FMouseEncoding = tmeSgr);
      1015: v := PermanentlyReset;
      1016: v := B2V(FMouseEncoding = tmeSgrPixels);
      1048: v := VSet;                    { xterm always answers SET }
      47, 1047, 1049: v := B2V(Buffers.IsAlt);
      2004: v := B2V(FBracketedPasteMode);
      2026: v := B2V(FSynchronizedOutput);
      9001:
        if tveWin32InputMode in FVtExtensions then
          v := B2V(FWin32InputMode)
        else
          v := NotRecognized;
    else
      v := NotRecognized;
    end;
  if AAnsi then
    TriggerDataEvent(#27'[' + IntToStr(p) + ';' + IntToStr(v) + '$y')
  else
    TriggerDataEvent(#27'[?' + IntToStr(p) + ';' + IntToStr(v) + '$y');
  Result := True;
end;

function TTyTerminalCore.RequestModeAnsi(AParams: TTyTerminalParams): Boolean;
begin
  Result := RequestMode(AParams, True);
end;

function TTyTerminalCore.RequestModePrivate(AParams: TTyTerminalParams): Boolean;
begin
  Result := RequestMode(AParams, False);
end;

{ _updateAttrColor, :2401-2411 }
function TTyTerminalCore.UpdateAttrColor(AColor: Cardinal; AMode, AC1, AC2, AC3: Integer): Cardinal;
begin
  if AMode = 2 then
  begin
    AColor := AColor or TyTermAttrCmRgb;
    AColor := AColor and not Cardinal(TyTermAttrRgbMask);
    AColor := AColor or ((Cardinal(AC1 and 255) shl 16) or (Cardinal(AC2 and 255) shl 8) or Cardinal(AC3 and 255));
  end
  else if AMode = 5 then
  begin
    AColor := AColor and not Cardinal(TyTermAttrCmMask or TyTermAttrRgbMask);
    AColor := AColor or TyTermAttrCmP256 or Cardinal(AC1 and $FF);
  end;
  Result := AColor;
end;

{ _extractColor, :2416-2475, statement for statement. accu is
    [target, CM, colour space, v1, v2, v3]  (RGB: r g b; 256: v1 only)
  and may grow by one slot the way a JavaScript array does when a sub-parameter
  lands one past its end. Returns how many params were used after the first. }
function TTyTerminalCore.ExtractColor(AParams: TTyTerminalParams; APos: Integer;
  var AAttr: TTyTerminalAttrData): Integer;
var
  accu: array[0..7] of Integer;
  accuLen, cSpace, advance, i, subCount: Integer;

  procedure Put(AIdx, AValue: Integer);
  begin
    if AIdx >= accuLen then
      accuLen := AIdx + 1;
    accu[AIdx] := AValue;
  end;

begin
  accu[0] := 0; accu[1] := 0; accu[2] := -1; accu[3] := 0; accu[4] := 0; accu[5] := 0;
  accu[6] := 0; accu[7] := 0;
  accuLen := 6;
  cSpace := 0;                           { alignment for the missing colour-space slot }
  advance := 0;
  repeat
    Put(advance + cSpace, AParams[APos + advance]);
    if AParams.HasSubParams(APos + advance) then
    begin
      subCount := AParams.SubParamCount(APos + advance);
      i := 0;
      repeat
        if accu[1] = 5 then
          cSpace := 1;
        Put(advance + i + 1 + cSpace, AParams.SubParam(APos + advance, i));
        Inc(i);
      until not ((i < subCount) and (i + advance + 1 + cSpace < accuLen));
      Break;
    end;
    { semicolons: stop as soon as the colour mode is decided }
    if ((accu[1] = 5) and (advance + cSpace >= 2)) or ((accu[1] = 2) and (advance + cSpace >= 5)) then
      Break;
    { semicolon mode has no colour-space slot }
    if accu[1] <> 0 then
      cSpace := 1;
    Inc(advance);
  until not ((advance + APos < AParams.Length) and (advance + cSpace < accuLen));
  for i := 2 to accuLen - 1 do
    if accu[i] = -1 then
      accu[i] := 0;
  case accu[0] of
    38: AAttr.Fg := UpdateAttrColor(AAttr.Fg, accu[1], accu[3], accu[4], accu[5]);
    48: AAttr.Bg := UpdateAttrColor(AAttr.Bg, accu[1], accu[3], accu[4], accu[5]);
    58: AAttr.Extended.SetUnderlineColor(Integer(UpdateAttrColor(AAttr.Extended.UnderlineColor,
          accu[1], accu[3], accu[4], accu[5])));
  end;
  Result := advance;
end;

{ _processUnderline, :2485-2500 (upstream clones the extended attributes first; they
  are a value here) }
procedure TTyTerminalCore.ProcessUnderline(AStyle: Integer; var AAttr: TTyTerminalAttrData);
begin
  if (AStyle = -1) or (AStyle > 5) then
    AStyle := 1;                         { default: single }
  AAttr.Extended.SetUnderlineStyle(AStyle);
  AAttr.Fg := AAttr.Fg or TyTermFgUnderline;
  if AStyle = 0 then
    AAttr.Fg := AAttr.Fg and not Cardinal(TyTermFgUnderline);
  AAttr.UpdateExtended;
end;

{ _processSGR0, :2502-2511: the link (urlId) survives }
procedure TTyTerminalCore.ProcessSGR0(var AAttr: TTyTerminalAttrData);
begin
  AAttr.Fg := TyTermDefaultAttr.Fg;
  AAttr.Bg := TyTermDefaultAttr.Bg;
  AAttr.Extended.SetUnderlineStyle(Ord(tusNone));
  AAttr.Extended.SetUnderlineColor(Integer(AAttr.Extended.UnderlineColor
    and not Cardinal(TyTermAttrCmMask or TyTermAttrRgbMask)));
  AAttr.UpdateExtended;
end;

{ SGR, :2600-2725 }
function TTyTerminalCore.CharAttributes(AParams: TTyTerminalParams): Boolean;
var
  i, l, p: Integer;
begin
  { a single SGR 0, the common case }
  if (AParams.Length = 1) and (AParams[0] = 0) then
  begin
    ProcessSGR0(FCurAttr);
    Exit(True);
  end;
  l := AParams.Length;
  i := 0;
  while i < l do
  begin
    p := AParams[i];
    if (p >= 30) and (p <= 37) then
    begin
      FCurAttr.Fg := FCurAttr.Fg and not Cardinal(TyTermAttrCmMask or TyTermAttrRgbMask);
      FCurAttr.Fg := FCurAttr.Fg or TyTermAttrCmP16 or Cardinal(p - 30);
    end
    else if (p >= 40) and (p <= 47) then
    begin
      FCurAttr.Bg := FCurAttr.Bg and not Cardinal(TyTermAttrCmMask or TyTermAttrRgbMask);
      FCurAttr.Bg := FCurAttr.Bg or TyTermAttrCmP16 or Cardinal(p - 40);
    end
    else if (p >= 90) and (p <= 97) then
    begin
      FCurAttr.Fg := FCurAttr.Fg and not Cardinal(TyTermAttrCmMask or TyTermAttrRgbMask);
      FCurAttr.Fg := FCurAttr.Fg or TyTermAttrCmP16 or Cardinal(p - 90) or 8;
    end
    else if (p >= 100) and (p <= 107) then
    begin
      FCurAttr.Bg := FCurAttr.Bg and not Cardinal(TyTermAttrCmMask or TyTermAttrRgbMask);
      FCurAttr.Bg := FCurAttr.Bg or TyTermAttrCmP16 or Cardinal(p - 100) or 8;
    end
    else if p = 0 then
      ProcessSGR0(FCurAttr)
    else if p = 1 then
      FCurAttr.Fg := FCurAttr.Fg or TyTermFgBold
    else if p = 3 then
      FCurAttr.Bg := FCurAttr.Bg or TyTermBgItalic
    else if p = 4 then
    begin
      FCurAttr.Fg := FCurAttr.Fg or TyTermFgUnderline;
      if AParams.HasSubParams(i) then
        ProcessUnderline(AParams.SubParam(i, 0), FCurAttr)
      else
        ProcessUnderline(Ord(tusSingle), FCurAttr);
    end
    else if p = 5 then
      FCurAttr.Fg := FCurAttr.Fg or TyTermFgBlink
    else if p = 7 then
      FCurAttr.Fg := FCurAttr.Fg or TyTermFgInverse
    else if p = 8 then
      FCurAttr.Fg := FCurAttr.Fg or TyTermFgInvisible
    else if p = 9 then
      FCurAttr.Fg := FCurAttr.Fg or TyTermFgStrikethrough
    else if p = 2 then
      FCurAttr.Bg := FCurAttr.Bg or TyTermBgDim
    else if p = 21 then
      ProcessUnderline(Ord(tusDouble), FCurAttr)
    else if p = 22 then
    begin
      FCurAttr.Fg := FCurAttr.Fg and not Cardinal(TyTermFgBold);
      FCurAttr.Bg := FCurAttr.Bg and not Cardinal(TyTermBgDim);
    end
    else if p = 23 then
      FCurAttr.Bg := FCurAttr.Bg and not Cardinal(TyTermBgItalic)
    else if p = 24 then
    begin
      FCurAttr.Fg := FCurAttr.Fg and not Cardinal(TyTermFgUnderline);
      ProcessUnderline(Ord(tusNone), FCurAttr);
    end
    else if p = 25 then
      FCurAttr.Fg := FCurAttr.Fg and not Cardinal(TyTermFgBlink)
    else if p = 27 then
      FCurAttr.Fg := FCurAttr.Fg and not Cardinal(TyTermFgInverse)
    else if p = 28 then
      FCurAttr.Fg := FCurAttr.Fg and not Cardinal(TyTermFgInvisible)
    else if p = 29 then
      FCurAttr.Fg := FCurAttr.Fg and not Cardinal(TyTermFgStrikethrough)
    else if p = 39 then
    begin
      FCurAttr.Fg := FCurAttr.Fg and not Cardinal(TyTermAttrCmMask or TyTermAttrRgbMask);
      FCurAttr.Fg := FCurAttr.Fg or (TyTermDefaultAttr.Fg and TyTermAttrRgbMask);
    end
    else if p = 49 then
    begin
      FCurAttr.Bg := FCurAttr.Bg and not Cardinal(TyTermAttrCmMask or TyTermAttrRgbMask);
      FCurAttr.Bg := FCurAttr.Bg or (TyTermDefaultAttr.Bg and TyTermAttrRgbMask);
    end
    else if (p = 38) or (p = 48) or (p = 58) then
      Inc(i, ExtractColor(AParams, i, FCurAttr))
    else if p = 53 then
      FCurAttr.Bg := FCurAttr.Bg or TyTermBgOverline
    else if p = 55 then
      FCurAttr.Bg := FCurAttr.Bg and not Cardinal(TyTermBgOverline)
    else if (p = 221) and (tveKittySgrBoldFaint in FVtExtensions) then
      FCurAttr.Fg := FCurAttr.Fg and not Cardinal(TyTermFgBold)       { not bold (kitty) }
    else if (p = 222) and (tveKittySgrBoldFaint in FVtExtensions) then
      FCurAttr.Bg := FCurAttr.Bg and not Cardinal(TyTermBgDim)        { not faint (kitty) }
    else if p = 59 then
    begin
      { the colour becomes -1 & 0x3FFFFFF, not "default" (upstream's answer) }
      FCurAttr.Extended.SetUnderlineColor(-1);
      FCurAttr.UpdateExtended;
    end;
    Inc(i);
  end;
  Result := True;
end;

{ DA1, :1706-1717; termName is always 'xterm' here, so the rxvt / linux / screen
  branches of _is() cannot be reached and are not ported }
function TTyTerminalCore.SendDeviceAttributesPrimary(AParams: TTyTerminalParams): Boolean;
begin
  if AParams[0] > 0 then
    Exit(True);
  TriggerDataEvent(#27'[?1;2c');
  Result := True;
end;

{ DA2, :1742-1762 (termName 'xterm') }
function TTyTerminalCore.SendDeviceAttributesSecondary(AParams: TTyTerminalParams): Boolean;
begin
  if AParams[0] > 0 then
    Exit(True);
  TriggerDataEvent(#27'[>0;276;0c');
  Result := True;
end;

{ XTVERSION, :1771-1777: we report ourselves, not xterm.js (spec 17.2 #11) }
function TTyTerminalCore.SendXtVersion(AParams: TTyTerminalParams): Boolean;
begin
  if AParams[0] > 0 then
    Exit(True);
  TriggerDataEvent(#27'P>|TyControls(' + TyTermLibraryVersion + ')'#27'\');
  Result := True;
end;

{ DSR, :2743-2757 }
function TTyTerminalCore.DeviceStatus(AParams: TTyTerminalParams): Boolean;
begin
  case AParams[0] of
    5: TriggerDataEvent(#27'[0n');
    6: TriggerDataEvent(#27'[' + IntToStr(Buffer.Y + 1) + ';' + IntToStr(Buffer.X + 1) + 'R');
  end;
  Result := True;
end;

{ DECDSR, :2760-2795 }
function TTyTerminalCore.DeviceStatusPrivate(AParams: TTyTerminalParams): Boolean;
begin
  case AParams[0] of
    6: TriggerDataEvent(#27'[?' + IntToStr(Buffer.Y + 1) + ';' + IntToStr(Buffer.X + 1) + 'R');
    996:
      if tveColorSchemeQuery in FVtExtensions then
        ReportColorScheme;               { onRequestColorSchemeQuery }
  end;
  Result := True;
end;

{ DECSTR, :2816-2835 }
function TTyTerminalCore.SoftReset(AParams: TTyTerminalParams): Boolean;
var
  before: TTyTerminalModes;
  buf: TTyTerminalBuffer;
begin
  before := GetModes;
  buf := Buffer;
  FIsCursorHidden := False;
  buf.ScrollTop := 0;
  buf.ScrollBottom := Rows - 1;
  FCurAttr := TyTermDefaultAttr;
  CoreServiceReset;
  CharsetReset;
  { reset DECSC data -- savedY becomes ybase, as upstream writes it }
  buf.SavedX := 0;
  buf.SavedY := buf.YBase;
  buf.SavedAttr.Fg := FCurAttr.Fg;
  buf.SavedAttr.Bg := FCurAttr.Bg;
  buf.SavedCharset := FCharset;
  FOrigin := False;
  ModesChangedSince(before);
  Result := True;
end;

{ DECSCUSR, :2840-2863 }
function TTyTerminalCore.SetCursorStyleCsi(AParams: TTyTerminalParams): Boolean;
var
  before: TTyTerminalModes;
  param: Integer;
begin
  before := GetModes;
  if AParams.Length = 0 then
    param := 1
  else
    param := AParams[0];
  if param = 0 then
  begin
    FCursorStyleRequest := tcrDefault;
    FCursorBlinkRequest := tbrDefault;
  end
  else
  begin
    case param of
      1, 2: FCursorStyleRequest := tcrBlock;
      3, 4: FCursorStyleRequest := tcrUnderline;
      5, 6: FCursorStyleRequest := tcrBar;
    end;
    if param mod 2 = 1 then
      FCursorBlinkRequest := tbrOn
    else
      FCursorBlinkRequest := tbrOff;
  end;
  ModesChangedSince(before);
  Result := True;
end;

{ DECSTBM, :2890-2905 }
function TTyTerminalCore.SetScrollRegion(AParams: TTyTerminalParams): Boolean;
var
  top, bottom: Integer;
begin
  top := P0or1(AParams);
  if AParams.Length < 2 then
    bottom := Rows
  else
  begin
    bottom := AParams[1];
    if (bottom > Rows) or (bottom = 0) then
      bottom := Rows;
  end;
  if bottom > top then
  begin
    Buffer.ScrollTop := top - 1;
    Buffer.ScrollBottom := bottom - 1;
    SetCursor(0, 0);
  end;
  Result := True;
end;

{ paramToWindowOption, :52-80 }
function ParamToWindowOption(n: Integer; const AOpts: TTyTerminalWindowOptions): Boolean;
begin
  if n > 24 then
    Exit(twoSetWinLines in AOpts);
  case n of
    1: Result := twoRestoreWin in AOpts;
    2: Result := twoMinimizeWin in AOpts;
    3: Result := twoSetWinPosition in AOpts;
    4: Result := twoSetWinSizePixels in AOpts;
    5: Result := twoRaiseWin in AOpts;
    6: Result := twoLowerWin in AOpts;
    7: Result := twoRefreshWin in AOpts;
    8: Result := twoSetWinSizeChars in AOpts;
    9: Result := twoMaximizeWin in AOpts;
    10: Result := twoFullscreenWin in AOpts;
    11: Result := twoGetWinState in AOpts;
    13: Result := twoGetWinPosition in AOpts;
    14: Result := twoGetWinSizePixels in AOpts;
    15: Result := twoGetScreenSizePixels in AOpts;
    16: Result := twoGetCellSizePixels in AOpts;
    18: Result := twoGetWinSizeChars in AOpts;
    19: Result := twoGetScreenSizeChars in AOpts;
    20: Result := twoGetIconTitle in AOpts;
    21: Result := twoGetWinTitle in AOpts;
    22: Result := twoPushTitle in AOpts;
    23: Result := twoPopTitle in AOpts;
    24: Result := twoSetWinLines in AOpts;
  else
    Result := False;
  end;
end;

procedure PushLimited(var AStack: TStringDynArray; const AValue: string);
var
  i: Integer;
begin
  SetLength(AStack, Length(AStack) + 1);
  AStack[High(AStack)] := AValue;
  if Length(AStack) > TyTermStackLimit then
  begin
    for i := 0 to High(AStack) - 1 do
      AStack[i] := AStack[i + 1];
    SetLength(AStack, Length(AStack) - 1);
  end;
end;

function PopString(var AStack: TStringDynArray): string;
begin
  Result := AStack[High(AStack)];
  SetLength(AStack, Length(AStack) - 1);
end;

{ XTWINOPS, :2936-2983 -- all off by default; 14 and 16 need pixels, which the
  control answers through OnWindowOptionsReport }
function TTyTerminalCore.WindowOptionsCsi(AParams: TTyTerminalParams): Boolean;
var
  second: Integer;
begin
  if not ParamToWindowOption(AParams[0], FWindowOptions) then
    Exit(True);
  if AParams.Length > 1 then
    second := AParams[1]
  else
    second := 0;
  case AParams[0] of
    14:
      if (second <> 2) and Assigned(FOnWindowOptionsReport) then
        FOnWindowOptionsReport(Self, twrWinSizePixels);
    16:
      if Assigned(FOnWindowOptionsReport) then
        FOnWindowOptionsReport(Self, twrCellSizePixels);
    18: TriggerDataEvent(#27'[8;' + IntToStr(Rows) + ';' + IntToStr(Cols) + 't');
    22:
      begin
        if (second = 0) or (second = 2) then
          PushLimited(FWindowTitleStack, FWindowTitle);
        if (second = 0) or (second = 1) then
          PushLimited(FIconNameStack, FIconName);
      end;
    23:
      begin
        if ((second = 0) or (second = 2)) and (Length(FWindowTitleStack) > 0) then
          SetTitle(PopString(FWindowTitleStack));
        if ((second = 0) or (second = 1)) and (Length(FIconNameStack) > 0) then
          SetIconName(PopString(FIconNameStack));
      end;
  end;
  Result := True;
end;

{ DECSC, :2994-3005 }
function TTyTerminalCore.SaveCursor: Boolean;
var
  buf: TTyTerminalBuffer;
begin
  buf := Buffer;
  buf.SavedX := buf.X;
  buf.SavedY := buf.YBase + buf.Y;
  buf.SavedAttr.Fg := FCurAttr.Fg;
  buf.SavedAttr.Bg := FCurAttr.Bg;
  buf.SavedCharset := FCharset;
  buf.SavedCharsets := Copy(FCharsets);
  buf.SavedGLevel := FGLevel;
  buf.SavedOriginMode := FOrigin;
  buf.SavedWraparoundMode := FWraparound;
  Result := True;
end;

function TTyTerminalCore.SaveCursorCsi(AParams: TTyTerminalParams): Boolean;
begin
  Result := SaveCursor;
end;

{ DECRC, :3015-3029 }
function TTyTerminalCore.RestoreCursor: Boolean;
var
  buf: TTyTerminalBuffer;
  before: TTyTerminalModes;
  i: Integer;
begin
  before := GetModes;
  buf := Buffer;
  buf.X := buf.SavedX;
  buf.Y := Max(buf.SavedY - buf.YBase, 0);
  FCurAttr.Fg := buf.SavedAttr.Fg;
  FCurAttr.Bg := buf.SavedAttr.Bg;
  for i := 0 to High(buf.SavedCharsets) do
    SetGCharset(i, buf.SavedCharsets[i]);
  SetGLevel(buf.SavedGLevel);
  FOrigin := buf.SavedOriginMode;
  FWraparound := buf.SavedWraparoundMode;
  RestrictCursor;
  ModesChangedSince(before);
  Result := True;
end;

function TTyTerminalCore.RestoreCursorCsi(AParams: TTyTerminalParams): Boolean;
begin
  Result := RestoreCursor;
end;

function TTyTerminalCore.KeypadApplicationMode: Boolean;                     { :3301-3305 }
var
  before: TTyTerminalModes;
begin
  before := GetModes;
  FApplicationKeypad := True;
  ModesChangedSince(before);
  Result := True;
end;

function TTyTerminalCore.KeypadNumericMode: Boolean;                         { :3310-3315 }
var
  before: TTyTerminalModes;
begin
  before := GetModes;
  FApplicationKeypad := False;
  ModesChangedSince(before);
  Result := True;
end;

function TTyTerminalCore.SelectDefaultCharset: Boolean;                      { :3323-3327 }
begin
  SetGLevel(0);
  SetGCharset(0, 0);                     { US (default) }
  Result := True;
end;

{ SCS, :3344-3354: ( ) * + - . pick G0..G2/G3; / is accepted and does nothing }
function TTyTerminalCore.SelectCharset(const ACollectAndFlag: string): Boolean;
var
  g, k: Integer;
  cs: TTyTermCharsetId;
begin
  if Length(ACollectAndFlag) <> 2 then
  begin
    SelectDefaultCharset;
    Exit(True);
  end;
  if ACollectAndFlag[1] = '/' then
    Exit(True);
  g := -1;
  for k := 0 to High(GLevelOf) do
    if GLevelOf[k].C = ACollectAndFlag[1] then
      g := GLevelOf[k].G;
  cs := 0;                               { unknown key: DEFAULT_CHARSET }
  for k := 0 to TyTermCharsetKeyCount - 1 do
    if TyTermCharsetKeys[k] = ACollectAndFlag[2] then
    begin
      cs := TyTermCharsetOfKey[k];
      Break;
    end;
  SetGCharset(g, cs);
  Result := True;
end;

function TTyTerminalCore.SetGLevel1: Boolean;
begin
  SetGLevel(1);
  Result := True;
end;

function TTyTerminalCore.SetGLevel2: Boolean;
begin
  SetGLevel(2);
  Result := True;
end;

function TTyTerminalCore.SetGLevel3: Boolean;
begin
  SetGLevel(3);
  Result := True;
end;

{ RIS, :3427-3431: the parser, then the headless reset (still partial) }
function TTyTerminalCore.FullReset: Boolean;
begin
  FParser.Reset;
  Reset;
  Result := True;
end;

procedure TTyTerminalCore.InputHandlerReset;                                 { :3433-3436 }
begin
  FCurAttr := TyTermDefaultAttr;
  FEraseAttr := TyTermDefaultAttr;
end;

{ DECRQSS, :3519-3537 }
function TTyTerminalCore.RequestStatusString(const AData: string; AParams: TTyTerminalParams): Boolean;

  procedure F(const S: string);
  begin
    TriggerDataEvent(#27 + S + #27'\');
  end;

const
  Styles: array[TTyTermCursorStyleOption] of Integer = (2, 4, 6);   { block underline bar }
var
  b: Integer;
begin
  Result := True;
  if AData = '"q' then
  begin
    if FCurAttr.IsProtected then b := 1 else b := 0;
    F('P1$r' + IntToStr(b) + '"q');
  end
  else if AData = '"p' then
    F('P1$r61;1"p')
  else if AData = 'r' then
    F('P1$r' + IntToStr(Buffer.ScrollTop + 1) + ';' + IntToStr(Buffer.ScrollBottom + 1) + 'r')
  else if AData = 'm' then
    F('P1$r0m')                          { upstream: real SGR settings not reported }
  else if AData = ' q' then
  begin
    { the OPTIONS, not DECSCUSR's request }
    b := Styles[FOptions.CursorStyle];
    if FOptions.CursorBlink then
      Dec(b);
    F('P1$r' + IntToStr(b) + ' q');
  end
  else
    F('P0$r');
end;

procedure TTyTerminalCore.SetTitle(const AData: string);                     { :3042-3046 }
begin
  FWindowTitle := AData;
  if Assigned(FOnTitleChange) then
    FOnTitleChange(Self, AData);
end;

{ :3052-3055 -- upstream only stores it; the event is ours (spec 7.6) }
procedure TTyTerminalCore.SetIconName(const AData: string);
begin
  FIconName := AData;
  if Assigned(FOnIconNameChange) then
    FOnIconNameChange(Self, AData);
end;

function TTyTerminalCore.OscTitleAndIcon(const AData: string): Boolean;
begin
  SetTitle(AData);
  SetIconName(AData);
  Result := True;
end;

function TTyTerminalCore.OscIconName(const AData: string): Boolean;
begin
  SetIconName(AData);
  Result := True;
end;

function TTyTerminalCore.OscTitle(const AData: string): Boolean;
begin
  SetTitle(AData);
  Result := True;
end;

{ String.prototype.split(';'): empty pieces kept, '' gives one empty piece }
function SplitOn(const S: string; ASep: Char): TStringDynArray;
var
  i, start, n: Integer;
begin
  Result := nil;
  n := 1;
  for i := 1 to Length(S) do
    if S[i] = ASep then
      Inc(n);
  SetLength(Result, n);
  n := 0;
  start := 1;
  for i := 1 to Length(S) do
    if S[i] = ASep then
    begin
      Result[n] := Copy(S, start, i - start);
      Inc(n);
      start := i + 1;
    end;
  Result[n] := Copy(S, start, MaxInt);
end;

{ /^\d+$/ then parseInt(.., 10) and 0 <= v < 256; the value saturates, so a
  hundred digits cannot overflow into a valid index }
function ColorIndexOf(const S: string; out AIndex: Integer): Boolean;
var
  i: Integer;
  v: Int64;
begin
  AIndex := -1;
  if S = '' then
    Exit(False);
  v := 0;
  for i := 1 to Length(S) do
  begin
    if not (S[i] in ['0'..'9']) then
      Exit(False);
    v := v * 10 + (Ord(S[i]) - Ord('0'));
    if v > 1000 then
      v := 1000;
  end;
  Result := v < 256;
  if Result then
    AIndex := Integer(v);
end;

function RgbOf(const ASpec: string; out ARgb: Cardinal): Boolean;
var
  r, g, b: Integer;
begin
  Result := TyTermParseXColor(ASpec, r, g, b);
  ARgb := (Cardinal(r and 255) shl 16) or (Cardinal(g and 255) shl 8) or Cardinal(b and 255);
end;

{ OSC 4, :3066-3090: index;spec pairs, each a query (?) or a set }
function TTyTerminalCore.OscIndexedColor(const AData: string): Boolean;
var
  slots: TStringDynArray;
  k, idx: Integer;
  rgb: Cardinal;
begin
  slots := SplitOn(AData, ';');
  k := 0;
  while Length(slots) - k > 1 do
  begin
    if ColorIndexOf(slots[k], idx) then
    begin
      if slots[k + 1] = '?' then
        ReportColor(idx)
      else if RgbOf(slots[k + 1], rgb) then
        SetColor(idx, rgb);
    end;
    Inc(k, 2);
  end;
  Result := True;
end;

{ JavaScript's trim(): its whitespace, not FPC's "everything below a space" }
function JsTrim(const S: string): string;
var
  p, e: Integer;
  c: Cardinal;
  b: Byte;
  cps: TIntegerDynArray;

  function IsWs(c: Cardinal): Boolean;
  begin
    case c of
      $09..$0D, $20, $A0, $1680, $2000..$200A, $2028, $2029, $202F, $205F, $3000, $FEFF:
        Result := True;
    else
      Result := False;
    end;
  end;

begin
  Result := TyTermJsTrimEnd(S);
  p := 1;
  while p <= Length(Result) do
  begin
    b := Ord(Result[p]);
    if b < $80 then e := 1
    else if b and $E0 = $C0 then e := 2
    else if b and $F0 = $E0 then e := 3
    else e := 4;
    cps := TyTermUtf8Codepoints(Copy(Result, p, e));
    if Length(cps) = 0 then Break;
    c := Cardinal(cps[0]);
    if not IsWs(c) then Break;
    Inc(p, e);
  end;
  Result := Copy(Result, p, MaxInt);
end;

{ OSC 8, :3109-3150. Arguments are split at the first ';' only, so a URI may hold
  more of them (#4944). }
function TTyTerminalCore.OscHyperlink(const AData: string): Boolean;
var
  idx: Integer;
  id, uri: string;
begin
  idx := Pos(';', AData);
  if idx = 0 then
    Exit(True);                          { malformed: handled, nothing done }
  id := JsTrim(Copy(AData, 1, idx - 1));
  uri := Copy(AData, idx + 1, MaxInt);
  if uri <> '' then
    Exit(CreateHyperlink(id, uri));
  if JsTrim(id) <> '' then
    Exit(False);
  Result := FinishHyperlink;
end;

function TTyTerminalCore.CreateHyperlink(const AParams, AUri: string): Boolean;
var
  parts: TStringDynArray;
  k: Integer;
  data: TTyTerminalLinkData;
begin
  { a new link may open without closing the previous one }
  if FCurAttr.Extended.UrlId <> 0 then
    FinishHyperlink;
  parts := SplitOn(AParams, ':');
  data.HasId := False;
  data.Id := '';
  for k := 0 to High(parts) do
    if Copy(parts[k], 1, 3) = 'id=' then
    begin
      data.Id := Copy(parts[k], 4, MaxInt);
      data.HasId := data.Id <> '';       { "id=" alone counts as no id }
      Break;
    end;
  data.Uri := AUri;
  FCurAttr.Extended.UrlId := FLinks.RegisterLink(data);
  FCurAttr.UpdateExtended;
  Result := True;
end;

function TTyTerminalCore.FinishHyperlink: Boolean;
begin
  FCurAttr.Extended.UrlId := 0;
  FCurAttr.UpdateExtended;
  Result := True;
end;

{ OSC 10 / 11 / 12, :3159-3200: a list starting at the given special colour }
procedure TTyTerminalCore.SetOrReportSpecialColor(const AData: string; AOffset: Integer);
var
  slots: TStringDynArray;
  i: Integer;
  rgb: Cardinal;
begin
  slots := SplitOn(AData, ';');
  for i := 0 to High(slots) do
  begin
    if AOffset >= 3 then
      Break;
    if slots[i] = '?' then
      ReportColor(ColorFg + AOffset)
    else if RgbOf(slots[i], rgb) then
      SetColor(ColorFg + AOffset, rgb);
    Inc(AOffset);
  end;
end;

function TTyTerminalCore.OscFgColor(const AData: string): Boolean;
begin
  SetOrReportSpecialColor(AData, 0);
  Result := True;
end;

function TTyTerminalCore.OscBgColor(const AData: string): Boolean;
begin
  SetOrReportSpecialColor(AData, 1);
  Result := True;
end;

function TTyTerminalCore.OscCursorColor(const AData: string): Boolean;
begin
  SetOrReportSpecialColor(AData, 2);
  Result := True;
end;

{ OSC 104, :3212-3236: no data restores the whole palette }
function TTyTerminalCore.OscRestoreIndexedColor(const AData: string): Boolean;
var
  slots: TStringDynArray;
  i, idx: Integer;
begin
  if AData = '' then
  begin
    RestoreColor(-1);
    Exit(True);
  end;
  slots := SplitOn(AData, ';');
  for i := 0 to High(slots) do
    if ColorIndexOf(slots[i], idx) then
      RestoreColor(idx);
  Result := True;
end;

function TTyTerminalCore.OscRestoreFgColor(const AData: string): Boolean;
begin
  RestoreColor(ColorFg);
  Result := True;
end;

function TTyTerminalCore.OscRestoreBgColor(const AData: string): Boolean;
begin
  RestoreColor(ColorBg);
  Result := True;
end;

function TTyTerminalCore.OscRestoreCursorColor(const AData: string): Boolean;
begin
  RestoreColor(ColorCursor);
  Result := True;
end;

{ An OSC no handler took (spec 7.4): the payload is collected with the same limit
  as a string handler and handed to OnOsc when it ends well. Numbers past
  High(Integer), and the -1 of an OSC without a number, never reach the host. }
procedure TTyTerminalCore.OscFallback(AIdent: Int64; AAction: TTyTermSubAction; const APayload: string;
  ASuccess: Boolean);
var
  cps: TIntegerDynArray;
  data: array of Cardinal;
  i: Integer;
  handled: Boolean;
begin
  case AAction of
    tsaStart:
      begin
        FOscData.Reset;
        FOscDataHitLimit := False;
      end;
    tsaPut:
      if not FOscDataHitLimit then
      begin
        cps := TyTermUtf8Codepoints(APayload);
        data := nil;
        SetLength(data, Length(cps));
        for i := 0 to High(cps) do
          data[i] := Cardinal(cps[i]);
        if FOscData.Append(data, 0, Length(data)) then
          FOscDataHitLimit := True;
      end;
    tsaEnd:
      begin
        if ASuccess and not FOscDataHitLimit and (AIdent >= 0) and (AIdent <= High(Integer))
          and Assigned(FOnOsc) then
        begin
          handled := False;
          FOnOsc(Self, Integer(AIdent), FOscData.Text, handled);
        end;
        FOscData.Reset;
        FOscDataHitLimit := False;
      end;
  end;
end;

{ ---- kitty keyboard, :3552-3651 (off unless vtExtensions.kittyKeyboard) ---- }

function TTyTerminalCore.KittyKeyboardSet(AParams: TTyTerminalParams): Boolean;
var
  flags, mode: Integer;
begin
  if not (tveKittyKeyboard in FVtExtensions) then
    Exit(True);
  flags := AParams[0];
  if AParams.Length > 1 then
  begin
    mode := AParams[1];
    if mode = 0 then mode := 1;
  end
  else
    mode := 1;
  case mode of
    1: FKittyFlags := flags;                          { set all }
    2: FKittyFlags := FKittyFlags or flags;           { set the given }
    3: FKittyFlags := FKittyFlags and not flags;      { reset the given }
  end;
  Result := True;
end;

function TTyTerminalCore.KittyKeyboardQuery(AParams: TTyTerminalParams): Boolean;
begin
  if not (tveKittyKeyboard in FVtExtensions) then
    Exit(True);
  TriggerDataEvent(#27'[?' + IntToStr(FKittyFlags) + 'u');
  Result := True;
end;

function TTyTerminalCore.KittyKeyboardPush(AParams: TTyTerminalParams): Boolean;

  procedure Push(var AStack: TIntegerDynArray);
  var
    i: Integer;
  begin
    { a full stack drops its oldest entry (limit 16) }
    if Length(AStack) >= 16 then
    begin
      for i := 0 to High(AStack) - 1 do
        AStack[i] := AStack[i + 1];
      SetLength(AStack, Length(AStack) - 1);
    end;
    SetLength(AStack, Length(AStack) + 1);
    AStack[High(AStack)] := FKittyFlags;
  end;

begin
  if not (tveKittyKeyboard in FVtExtensions) then
    Exit(True);
  if Buffer = Buffers.Alt then
    Push(FKittyAltStack)
  else
    Push(FKittyMainStack);
  FKittyFlags := AParams[0];
  Result := True;
end;

function TTyTerminalCore.KittyKeyboardPop(AParams: TTyTerminalParams): Boolean;

  procedure Pop(var AStack: TIntegerDynArray; ACount: Integer);
  var
    i: Integer;
  begin
    i := 0;
    while (i < ACount) and (Length(AStack) > 0) do
    begin
      FKittyFlags := AStack[High(AStack)];
      SetLength(AStack, Length(AStack) - 1);
      Inc(i);
    end;
    { an emptied stack leaves the flags at 0 }
    if (Length(AStack) = 0) and (ACount > 0) then
      FKittyFlags := 0;
  end;

var
  count: Integer;
begin
  if not (tveKittyKeyboard in FVtExtensions) then
    Exit(True);
  count := Max(1, P0or1(AParams));
  if Buffer = Buffers.Alt then
    Pop(FKittyAltStack, count)
  else
    Pop(FKittyMainStack, count);
  Result := True;
end;

{@@TASK19@@}

end.
