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

{@@TASK16@@}

end.
