unit tyControls.Terminal.Core;
{$mode objfpc}{$H+}
{$modeswitch advancedrecords}

{ TTyTerminalCore: the invisible terminal. Bytes go in through the write queue, get
  decoded and parsed, and the handlers here change the buffers, the modes and the
  character sets and send replies back through OnData. No LCL (design spec 3.1):
  the control that shows it is built on top in a later phase.

  The implementation continues in four include files, split off only for length:
  tyControls.Terminal.Core.Services.inc (the services, the entry points),
  tyControls.Terminal.Core.InputHandler.inc (every sequence handler),
  tyControls.Terminal.Core.WriteQueue.inc (the queue and re-entry) and
  tyControls.Terminal.Core.Stream.inc (the stream and parser hooks -- ours, not
  ported; see below).

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
  - Events fire synchronously, in the middle of parsing (OnScroll, OnData, OnBell,
    OnTitleChange, OnOsc, OnRefreshRows ...), and while Resize / Reset run. A host
    that calls Resize, Reset or WriteSync from such an event is not refused: the
    call is noted and carried out once the chunk (with its write callback) is done
    -- in call order, only the last Resize kept. ProcessPending called then returns
    False at once and the core asks again afterwards. Nothing is parsed twice and no
    buffer goes away under a running handler.
  - The write queue survives an exception from a handler or a callback: the chunk
    that raised counts as parsed, its dirty rows are still reported, and what is
    left asks for another slice.
  - A slice (ProcessPending) parses a chunk in pieces of TyTermSlicePieceBytes and
    checks the time budget between pieces, not only between chunks, so one huge Write
    does not hold the thread (upstream parses a chunk in one go, WriteBuffer.ts:224-297:
    a deliberate difference, spec 15); a piece that small runs over the budget by a
    millisecond or two, not by one of MAX_PARSEBUFFER's 128 KB. A flush (WriteSync,
    Resize) takes pieces of TyTermMaxParseBuffer. Each piece is one parse call (its own
    OnCursorMove / OnRefreshRows); the state afterwards is the whole chunk's. A
    chunk's callback comes once, after its last piece; calls made from events wait
    for it too; PendingBytes drops piece by piece; a flush (WriteSync, Resize) goes
    on from the piece a slice stopped at; DiscardPending drops the half-parsed chunk
    without its callback.
  - REP prints its text count times, exactly -- bounded in time, not by capping the
    count: once the output has turned over the whole ring (rows + scrollback) the
    state repeats with the period the repetitions found, so whole periods are
    skipped (the lines, the cursor and the ring's start index come out as printing
    them one by one would; the OnScroll events of the skipped scrolls are not sent).
    Upstream allocates repeats x text before printing and gives no answer for a
    huge count. A REP whose repetitions only pile code points onto one cell stops
    after TyTermRepeatLimit code points on that line.
  - IL, DL, SU, SD, CHT and CBT clamp their loop count to the passes that can still
    change something: the lines from the cursor (or the region) to the bottom
    margin, the columns left of or right of the cursor. Every pass past that is a
    no-op upstream, so the clamp changes nothing but the time (upstream takes
    seconds for 99999 and never finishes 2^31).
  - Coordinates plus parameters are summed in Int64 (a parameter can be 2^31 - 1).
  - Colours: the core keeps the overrides set by OSC 4 / 10 / 11 / 12 and answers
    queries from them, falling back to OnQueryBaseColor. A set or a restore reports
    the colour scheme when DECSET 2031 is on; RIS leaves the overrides alone; the
    host's NotifyColorSchemeChanged (a new theme) drops them all -- the browser
    layer's ThemeService semantics. With no OnQueryBaseColor there is no theme to
    answer from, and the core answers no colour query, no colour-scheme query and
    sends no 2031 report -- as headless xterm.js.
  - Mouse: the protocol state, RestrictMouseEvent / EncodeMouseEvent (1-based
    coordinates, as upstream's) and TriggerMouseEvent, the browser layer's
    _triggerMouseEvent (0-based in, filtered, de-duplicated, routed). Turning LCL
    mouse events into TTyTerminalMouseEvent is the control's job (phase 4).
  - The screen-reader branches of print and tab are not ported (no accessibility
    layer, spec 15).
  - Stream hooks (spec 19; ours, xterm.js has none): with a TTyTerminalStreamHandler
    added, every piece the queue hands over is offered, as raw bytes, to Detect before
    it is decoded; a handler that claims gets the rest of the output through Feed
    (the decoder, the parser and the screen stay as they are) until it Releases, the
    host Resets or removes it. The bytes before the claim are parsed first; a Release
    hands the bytes that are not the handler's back in front of everything still
    queued, through Detect again (a claim that ate nothing hands back its first byte
    to the parser, or the same handler would claim it for ever). Detect / Claimed /
    Feed run with the core busy, so what they cause (a Resize, a Reset, a WriteSync)
    waits for the chunk like any event's. While claimed the user's input goes to
    OnClaimedInput and the core's own reports (focus, 2031, default-encoding mouse,
    Input with AWasUserInput False) are dropped; TriggerMouseEvent answers False.
    With no handler and no claim, ProcessOneChunk costs three more comparisons.
    DiscardPending drops the handed-back bytes with the queue and leaves the claim;
    Reset ends it (ClaimEnded(tceReset)); the destructor calls no handler. }

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
  { ours: the piece of a chunk a slice parses between two looks at the clock (unit
    header); a flush parses TyTermMaxParseBuffer at a time }
  TyTermSlicePieceBytes = 32768;
  TyTermWriteBufferLengthThreshold = 50;  { WriteBuffer.ts:28 }
  TyTermStackLimit = 10;                  { InputHandler.ts:47 }
  { REP: code points printed on one line, without a scroll or a new line, after
    which the repetitions stop (unit header) }
  TyTermRepeatLimit = 1048576;
  { ours: queued chunks not yet parsed; one more raises like the byte watermark }
  TyTermMaxPendingChunks = 100000;

type
  { More than 50 MB waiting: the host is not doing flow control (upstream throws a
    plain Error). }
  ETyTerminalWriteOverflow = class(Exception);

  TTyTerminalDataEvent  = procedure(Sender: TObject; const AData: RawByteString) of object;
  TTyTerminalTextEvent  = procedure(Sender: TObject; const AText: string) of object;
  TTyTerminalRowsEvent  = procedure(Sender: TObject; AFirst, ALast: Integer) of object;
  { An OSC no handler took; the core does nothing else with it. }
  TTyTerminalOscEvent   = procedure(Sender: TObject; AIdent: Integer; const AData: string) of object;
  TTyTerminalWriteDone  = procedure(Sender: TObject; ATag: PtrInt) of object;
  TTyTerminalResizeEvent = procedure(Sender: TObject; ACols, ARows: Integer) of object;
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

  { a Resize / Reset / WriteSync asked for while the core was busy (unit header) }
  TTyTermDeferredKind = (tdkResize, tdkReset, tdkWriteSync);
  TTyTermDeferred = record
    Kind: TTyTermDeferredKind;
    Cols, Rows: Integer;
    Data: RawByteString;
  end;

  TTyTerminalStreamSession = class;

  { spec 19.3: a claim that the handler did not end itself }
  TTyTerminalClaimEnd = (tceReset, tceRemoved);

  { In-band protocol hook (spec 19.3). The host derives from it and hands it to
    AddStreamHandler; the core does not own it (remove it before freeing it). Main
    thread only. }
  TTyTerminalStreamHandler = class
  public
    { The program's raw bytes (not decoded) are about to reach the parser. True with
      AClaimAt in 0..ACount: claim from there; the bytes before it are parsed first.
      Asked only while nobody claims. A marker cut between two pieces is the handler's
      to remember -- the earlier piece is already on screen. }
    function Detect(AData: PByte; ACount: Integer; out AClaimAt: Integer): Boolean; virtual; abstract;
    { the claim starts; everything before AClaimAt has been parsed. ASession stays
      Active until the claim ends. Default: nothing. }
    procedure Claimed(ASession: TTyTerminalStreamSession); virtual;
    { the program's output while claimed, in order; the first call is the rest of the
      piece Detect saw (none when AClaimAt = ACount) }
    procedure Feed(AData: PByte; ACount: Integer); virtual; abstract;
    { the host ended the claim (Reset, RemoveStreamHandler), not Release. The session
      still sends (SendRaw: tell the program to stop) and shows text during this call;
      Release there does nothing. Default: nothing. }
    procedure ClaimEnded(AHow: TTyTerminalClaimEnd); virtual;
  end;

  { One per core, for the core's life; Active only during a claim. Every method is a
    no-op (SendRaw answers False) when not Active. }
  TTyTerminalStreamSession = class
  private
    FCore: TTyTerminalCore;
    FHandler: TTyTerminalStreamHandler;
    FActive: Boolean;
    FEnding: Boolean;                    { inside ClaimEnded: Release is a no-op }
  public
    constructor Create(ACore: TTyTerminalCore);
    { straight to OnData: no key encoding, no scroll to the bottom, no OnUserInput, not
      "the user just typed". False under ReadOnly, without OnData, or not Active. }
    function SendRaw(const AData: RawByteString): Boolean;
    { ends the claim; ALeftover (bytes the handler took but that are not its own) goes
      back in front of everything not parsed yet: through Detect again, then the parser }
    procedure Release(const ALeftover: RawByteString = '');
    { UTF-8 text (control sequences allowed) on the screen, not sent: parsed now with a
      decoder of its own; while the parser runs (an event of its own parse) it waits
      for that parse to return }
    procedure ShowText(const AText: string);
    property Active: Boolean read FActive;
    property Core: TTyTerminalCore read FCore;
    property Handler: TTyTerminalStreamHandler read FHandler;
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
    FOscCollecting: Boolean;             { OnOsc was assigned when the OSC started }
    { colours, focus, mouse }
    FOverrides: array[0..258] of TTyTermColorOverride;
    FFocused: Boolean;
    FLastMouse: TTyTerminalMouseEvent;   { MouseService._lastEvent }
    FHasLastMouse: Boolean;
    { re-entry (unit header): > 0 while parsing, resizing or resetting }
    FBusy: Integer;
    FDeferred: array of TTyTermDeferred;
    FDeferredCount: Integer;
    FRerequest: Boolean;                 { ProcessPending came while busy }
    { the old-ConPTY heuristics }
    FWindowsHeuristics: Boolean;
    FWindowsCsiHandle: Integer;
    { the write queue }
    FQueue: array of TTyTermQueueItem;
    FQueueCount: Integer;
    FBufferOffset: Integer;
    FPendingData: Int64;
    { bytes of the head chunk already parsed (a slice may stop inside a chunk), and a
      count of queue clears (a nested DiscardPending is seen by the running piece) }
    FChunkPos: Integer;
    FQueueGen: Cardinal;
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
    FOnResize: TTyTerminalResizeEvent;
    FOnScrollbackCleared: TNotifyEvent;
    FOnUserInput: TNotifyEvent;
    { stream hooks (spec 19, Core.Stream.inc). FStreamHandlers may hold nil slots while
      the handlers are asked (a handler removed from Detect); FStreamCount counts the
      live ones. }
    FStreamHandlers: array of TTyTerminalStreamHandler;
    FStreamCount: Integer;
    FStreamLoop: Integer;                { > 0 while the handlers are asked }
    FClaim: TTyTerminalStreamHandler;
    FStreamSession: TTyTerminalStreamSession;
    { the bytes a claim handed back, parsed before anything queued; not in PendingBytes }
    FFront: RawByteString;
    FFrontPos: Integer;
    FFrontBypass: Boolean;               { its first byte goes to the parser, not to Detect }
    FClaimFed: Int64;                    { bytes this claim was fed }
    FClaimReturned: Integer;             { bytes this claim's Release handed back }
    FShowDecoder: TTyUtf8Decoder;
    FShowPending: RawByteString;
    FShowFlushing: Boolean;
    FParsing: Integer;                   { parse depth: ParseRange and ShowText }
    FUserHandles: array of Integer;      { what Register*Handler gave out }
    FOnClaimedInput: TTyTerminalDataEvent;
    FStreamPiecesOffered, FStreamDetectCalls: Int64;

    { wiring }
    procedure RegisterHandlers;
    procedure BufferScrolled(AYDisp: Integer);
    procedure BufferActivated(AActive, AInactive: TTyTerminalBuffer);
    procedure BufferResized(ACols, ARows: Integer; AColsChanged, ARowsChanged: Boolean);
    function GetBuffer: TTyTerminalBuffer;
    function GetBuffers: TTyTerminalBufferSet;
    function GetCols: Integer;
    function GetRows: Integer;
    { CoreService / CharsetService / MouseStateService }
    procedure CoreServiceReset;
    procedure TriggerDataEvent(const AData: RawByteString; AWasUserInput: Boolean = False);
    procedure TriggerBinaryEvent(const AData: RawByteString);
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
    { bytes [AStart, AStart + ACount) of AData (1-based): one parse call }
    procedure ParseRange(const AData: RawByteString; AStart, ACount: Integer);
    procedure DoPrint(const AData: array of Cardinal; AStart, AEnd: Integer; ARepeat: Int64);
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
    procedure DoReset;
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
    function NowMs: Double;
    procedure RequestProcess;
    procedure Enqueue(const AData: RawByteString; AOnDone: TTyTerminalWriteDone; ATag: PtrInt);
    procedure ProcessOneChunk(APieceBytes: Integer);
    procedure InnerWrite(ABudgetMs: Integer; out AMore: Boolean);
    procedure FlushSync;
    procedure ClearQueue;
    { re-entry }
    procedure Defer(AKind: TTyTermDeferredKind; ACols, ARows: Integer; const AData: RawByteString);
    procedure RunDeferred;
    procedure AfterDrive;

    { ---- stream hooks (spec 19, Core.Stream.inc) ---- }
    function GetStreamHandlerCount: Integer;
    function GetStreamClaimed: Boolean;
    function GetClaimingHandler: TTyTerminalStreamHandler;
    procedure CompactStreamHandlers;
    function StreamHandlerListed(AHandler: TTyTerminalStreamHandler): Boolean;
    { the slow path of ProcessOneChunk: AData[AFrom .. AFrom + ACount - 1] }
    procedure StreamPiece(const AData: RawByteString; AFrom, ACount: Integer);
    procedure OfferPiece(const AData: RawByteString; AFrom, ACount: Integer);
    procedure DoFeed(const AData: RawByteString; AFrom, ACount: Integer);
    procedure BeginClaim(AHandler: TTyTerminalStreamHandler);
    procedure EndClaim(AHow: TTyTerminalClaimEnd; ANotify: Boolean);
    procedure ReleaseClaim(const ALeftover: RawByteString);
    { AData goes in front of the bytes handed back but not parsed yet, after the first
      AOffset of them }
    procedure SpliceFront(const AData: RawByteString; AOffset: Integer);
    { one piece of the handed-back bytes }
    procedure ProcessFrontPiece(APieceBytes: Integer);
    procedure ShowLocal(const AText: string);
    procedure FlushShowPending;
    { ParseRange with a decoder of the caller's (the program's, or ShowText's) }
    procedure ParseDecoded(ADecoder: TTyUtf8Decoder; const AData: RawByteString; AStart, ACount: Integer);
    procedure NoteUserHandle(AHandle: Integer);
  public
    constructor Create(ACols, ARows: Integer);
    destructor Destroy; override;
    { Every method and property: the main thread only (spec 3.5). Write, WriteSync,
      ProcessPending, Resize, Reset, Input, the Scroll* methods, ClearScrollback,
      TriggerMouseEvent, ReportFocus, NotifyColorSchemeChanged and
      EndSynchronizedOutput raise EInvalidOperation on another thread. }
    { writing. Write('') without a callback is ignored; with one it is queued (its
      callback runs after everything before it). More than TyTermDiscardWatermark
      bytes or TyTermMaxPendingChunks chunks waiting: ETyTerminalWriteOverflow. }
    procedure Write(const AData: RawByteString; AOnDone: TTyTerminalWriteDone = nil; ATag: PtrInt = 0); overload;
    procedure Write(const ABuf; ACount: Integer; AOnDone: TTyTerminalWriteDone = nil; ATag: PtrInt = 0); overload;
    { Parses what is queued, then AData. Called from an event while the core is busy
      it only takes note, and runs once the current chunk is done (unit header). }
    procedure WriteSync(const AData: RawByteString);
    { One slice: chunks until the budget is spent, checked between chunks. True when
      something is left -- the caller schedules the next slice. Called while the
      core is busy (from an event, a modal loop in a handler) it returns False at
      once; the core raises OnProcessRequest again when it is done. }
    function ProcessPending(ABudgetMs: Integer = TyTermWriteTimeoutMs): Boolean;
    { Drops every chunk not parsed yet, WITHOUT calling their callbacks -- the host asked
      for it (a replay switching recordings, a session reset), so its own flow-control
      count restarts with it. Not in upstream (WriteBuffer has no such call). }
    procedure DiscardPending;
    { input from the control }
    procedure Input(const AData: RawByteString; AWasUserInput: Boolean = True);
    { MouseStateService.restrictMouseEvent / encodeMouseEvent: Col / Row 1-BASED
      here, as upstream's (TriggerMouseEvent converts). }
    function RestrictMouseEvent(var AEvent: TTyTerminalMouseEvent): Boolean;
    { '' when suppressed (the default encoding past 223) }
    function EncodeMouseEvent(const AEvent: TTyTerminalMouseEvent): RawByteString;
    { MouseService._triggerMouseEvent (MouseService.ts:497-545): Col / Row 0-based
      cells, X / Y device pixels. Out of the grid or a meaningless button and action:
      False. Then 1-based, a move equal to the last event (by cell, by pixel under
      SGR-pixels) dropped, the protocol applied, the report encoded and sent -- the
      default encoding as binary (no scroll to bottom), the others as user input.
      True when the event passed every filter (even if the encoding had no room). }
    function TriggerMouseEvent(const AEvent: TTyTerminalMouseEvent): Boolean;
    { Also remembered for DECSET 1004, which reports it at once. Focused starts True:
      the control reports its real focus as soon as it has one. }
    procedure ReportFocus(AFocused: Boolean);
    procedure NotifyColorSchemeChanged;
    { RenderService's 1-second timeout of DECSET 2026 (RenderService.ts:359-363):
      mode 2026 off, the whole screen refreshed. The control's timer calls it. }
    procedure EndSynchronizedOutput;
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
    { stream hooks (spec 19.3-19.5, unit header). Main thread only. }
    procedure AddStreamHandler(AHandler: TTyTerminalStreamHandler);     { again: ignored; nil raises }
    { taken off the list first, then the claiming one gets ClaimEnded(tceRemoved) (a
      Detect it causes cannot reach it); unknown: ignored }
    procedure RemoveStreamHandler(AHandler: TTyTerminalStreamHandler);
    property StreamHandlerCount: Integer read GetStreamHandlerCount;
    property StreamClaimed: Boolean read GetStreamClaimed;
    property ClaimingHandler: TTyTerminalStreamHandler read GetClaimingHandler;   { nil = nobody }
    property StreamSession: TTyTerminalStreamSession read FStreamSession;
    { while claimed, the user's input (keys, a paste, the arrows a wheel turns into) goes
      here instead of OnData -- never while ReadOnly }
    property OnClaimedInput: TTyTerminalDataEvent read FOnClaimedInput write FOnClaimedInput;
    { Parser hooks (spec 19.6, after xterm.js's ParserApi): the newest is tried first,
      True stops, False tries the one before, the core's own last. OSC / DCS / APC:
      once, on a successful end, payload up to 10 MB; an OSC number with a handler
      no longer reaches OnOsc (a non-empty chain never falls back, as upstream). The
      params are borrowed (Clone to keep). An identifier upstream refuses raises
      EArgumentException with upstream's message; a nil handler
      EArgumentNilException, an OSC number below 0 EArgumentOutOfRangeException.
      Reset keeps them. Main thread only. }
    function RegisterCsiHandler(const AId: TTyTerminalFunctionId; AHandler: TTyTerminalCsiEvent): Integer;
    function RegisterEscHandler(const AId: TTyTerminalFunctionId; AHandler: TTyTerminalEscEvent): Integer;
    function RegisterOscHandler(AIdent: Integer; AHandler: TTyTerminalOscDataEvent): Integer;
    function RegisterDcsHandler(const AId: TTyTerminalFunctionId; AHandler: TTyTerminalDcsDataEvent): Integer;
    function RegisterApcHandler(const AId: TTyTerminalFunctionId; AHandler: TTyTerminalOscDataEvent): Integer;
    { only handles these five gave out; anything else (the core's own) is ignored }
    procedure UnregisterHandler(AHandle: Integer);
    { FOR THE TESTS (pure queries) }
    property StreamPiecesOffered: Int64 read FStreamPiecesOffered;   { pieces that took the slow path }
    property StreamDetectCalls: Int64 read FStreamDetectCalls;
    { FOR THE TESTS (pure queries; the fixtures compare them with upstream's
      internals, nothing uses them at run time) }
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
    { the erase attributes as last worked out (upstream _eraseAttrDataInternal) }
    property EraseAttr: TTyTerminalAttrData read FEraseAttr;
    property BufferService: TTyTerminalBufferService read FBufferService;

    property PendingBytes: Int64 read FPendingData;
    { FOR THE TESTS (a pure query): the bytes of the head chunk parsed so far }
    property HeadChunkParsed: Integer read FChunkPos;
    property Clock: TTyTerminalClock read FClock write FClock;
    property Focused: Boolean read FFocused;
    property Cols: Integer read GetCols;
    property Rows: Integer read GetRows;
    property Buffers: TTyTerminalBufferSet read GetBuffers;
    property Buffer: TTyTerminalBuffer read GetBuffer;
    property Modes: TTyTerminalModes read GetModes;
    property Title: string read FWindowTitle;
    property IconName: string read FIconName;
    { the LOW-LEVEL interface: its Clear*, Set*Fallback and SetPrintHandler take the
      core's own handling apart. A host adds handlers through Register*Handler. }
    property Parser: TTyTerminalParser read FParser;
    property Links: TTyTerminalOscLinks read FLinks;
    { options }
    { 0..TyTermMaxScrollback: a larger value is taken as the maximum, a negative one
      raises (upstream's check) }
    property Scrollback: Integer read GetScrollback write SetScrollback;
    property TabStopWidth: Integer read GetTabStopWidth write SetTabStopWidth;
    property ConvertEol: Boolean index 0 read GetOptBool write SetOptBool;
    property ScrollOnUserInput: Boolean index 1 read GetOptBool write SetOptBool;
    property ReadOnly: Boolean index 2 read GetOptBool write SetOptBool;
    property CursorBlink: Boolean index 3 read GetOptBool write SetOptBool;
    property ScrollOnEraseInDisplay: Boolean index 4 read GetOptBool write SetOptBool;
    property AllowSetCursorBlink: Boolean index 5 read GetOptBool write SetOptBool;
    { reflowCursorLine (OptionsService.ts:50), default False: the wrapped run holding
      the cursor is not rewrapped on a new column count (the program redraws its own
      line); a host may turn it on }
    property ReflowCursorLine: Boolean index 6 read GetOptBool write SetOptBool;
    property AmbiguousWide: Boolean read FAmbiguousWide write FAmbiguousWide;
    property UnicodeVersion: TTyUnicodeVersion read FUnicodeVersion write FUnicodeVersion;
    property WindowsPty: TTyTerminalWindowsPty read GetWindowsPty write SetWindowsPty;
    property WindowOptions: TTyTerminalWindowOptions read FWindowOptions write FWindowOptions;
    property VtExtensions: TTyTerminalVtExtensions read FVtExtensions write FVtExtensions;
    property CursorStyle: TTyTermCursorStyleOption read GetCursorStyle write SetCursorStyle;
    { events -- all synchronous, most of them in the middle of parsing (unit header) }
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
    { the grid changed size: Resize, and DECCOLM (CSI ? 3 h / l with twoSetWinLines)
      -- the host resizes its PTY (BufferService.onResize) }
    property OnResize: TTyTerminalResizeEvent read FOnResize write FOnResize;
    { the scrollback went: ED 3 (when it held lines) and ClearScrollback }
    property OnScrollbackCleared: TNotifyEvent read FOnScrollbackCleared write FOnScrollbackCleared;
    { CoreService.onUserInput (CoreService.ts:86-89): data the user made (keys, a paste,
      a mouse report the encoding sends as user input) is about to go out -- after the
      scroll to the bottom, before OnData; never while ReadOnly. The control takes it
      (it clears the selection). }
    property OnUserInput: TNotifyEvent read FOnUserInput write FOnUserInput;
  end;

{ The built-in clock, milliseconds: QueryPerformanceCounter on Windows,
  mach_absolute_time on macOS, GetTickCount64 elsewhere (CLOCK_MONOTONIC on Linux
  and FreeBSD; FPC 3.2.2 falls back to gettimeofday on the other Unixes, which is
  not monotonic). }
function TyTermDefaultClock: Double;
{ XParseColor.ts:23-56 parseColor; channels 0..255. }
function TyTermParseXColor(const ASpec: string; out R, G, B: Integer): Boolean;
{ XParseColor.ts:58-80 toRgbString, 16 bits per channel. }
function TyTermToRgbString(ARgb: Cardinal): string;
{ Color.ts:236-259, bit for bit: the linearized channels come from a table of V8's own
  results (tyControls.Terminal.Luminance.inc, contrast-cases.js), summed in upstream's
  order with Double constants. The minimum-contrast functions (Render) use it too. }
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

function ClampInt(AValue: Int64): Integer; inline;
begin
  if AValue > High(Integer) then
    Result := High(Integer)
  else if AValue < Low(Integer) then
    Result := Low(Integer)
  else
    Result := Integer(AValue);
end;

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

{$I tyControls.Terminal.Luminance.inc}

function TyTermRelativeLuminance(ARgb: Cardinal): Double;
const
  KR: Double = 0.2126;
  KG: Double = 0.7152;
  KB: Double = 0.0722;
var
  r, g, b: QWord;
begin
  r := TyTermLinearChannelBits[(ARgb shr 16) and $FF];
  g := TyTermLinearChannelBits[(ARgb shr 8) and $FF];
  b := TyTermLinearChannelBits[ARgb and $FF];
  Result := PDouble(@r)^ * KR + PDouble(@g)^ * KG + PDouble(@b)^ * KB;
end;

{$IFDEF MSWINDOWS}
var
  GQpcFrequency: Double = 0;             { counts per second, asked once }

function TyTermDefaultClock: Double;
var
  c, f: Int64;
  count: Double;
begin
  { GetTickCount64 steps by ~15.6 ms here, coarser than the 12 ms budget }
  if GQpcFrequency = 0 then
  begin
    f := 1;
    QueryPerformanceFrequency(f);
    if f <= 0 then
      f := 1;
    GQpcFrequency := f;
  end;
  c := 0;
  QueryPerformanceCounter(c);
  { a Double variable: "c * 1000.0" would take the literal as a Single and lose the
    milliseconds of a counter in the trillions }
  count := c;
  Result := count / GQpcFrequency * 1000;
end;
{$ELSE}
{$IFDEF DARWIN}
{ FPC 3.2.2's GetTickCount64 is gettimeofday on Darwin (rtl/unix/sysutils.pp: only
  Linux and FreeBSD get CLOCK_MONOTONIC), which jumps with the wall clock. The RTL
  declares no mach timer, so the two libSystem calls are declared here. }
type
  TTyMachTimebase = record
    Numer, Denom: Cardinal;
  end;

function mach_absolute_time: QWord; cdecl; external 'c' name 'mach_absolute_time';
function mach_timebase_info(var AInfo: TTyMachTimebase): Integer; cdecl; external 'c' name 'mach_timebase_info';

var
  GMachNsPerTick: Double = 0;

function TyTermDefaultClock: Double;
var
  tb: TTyMachTimebase;
  n, d, t: Double;
begin
  if GMachNsPerTick = 0 then
  begin
    tb.Numer := 1;
    tb.Denom := 1;
    if (mach_timebase_info(tb) <> 0) or (tb.Denom = 0) or (tb.Numer = 0) then
    begin
      tb.Numer := 1;
      tb.Denom := 1;
    end;
    n := tb.Numer;
    d := tb.Denom;
    GMachNsPerTick := n / d;
  end;
  t := mach_absolute_time;
  Result := t * GMachNsPerTick / 1000000;
end;
{$ELSE}
function TyTermDefaultClock: Double;
begin
  { clock_gettime(CLOCK_MONOTONIC) on Linux and FreeBSD, 1 ms; gettimeofday on the
    other Unixes (FPC 3.2.2, rtl/unix/sysutils.pp) }
  Result := GetTickCount64;
end;
{$ENDIF}
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
  FBufferService.OnResize := @BufferResized;
  FLinks := TTyTerminalOscLinks.Create(FBufferService);
  FParser := TTyTerminalParser.Create;
  FDecoder := TTyUtf8Decoder.Create;
  FOscData := TTyLimitedStringBuilder.Create(TyTermParserPayloadLimit);
  FShowDecoder := TTyUtf8Decoder.Create;
  FStreamSession := TTyTerminalStreamSession.Create(Self);
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
  FDeferred := nil;
  FDeferredCount := 0;
  { spec 19.5: no handler is called (the host may be going too) }
  FClaim := nil;
  FStreamHandlers := nil;
  FStreamCount := 0;
  FStreamSession.Free;
  FShowDecoder.Free;
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

{ BufferService.onResize, forwarded as onResize (CoreTerminal.ts:147) }
procedure TTyTerminalCore.BufferResized(ACols, ARows: Integer; AColsChanged, ARowsChanged: Boolean);
begin
  if Assigned(FOnResize) then
    FOnResize(Self, ACols, ARows);
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

{$I tyControls.Terminal.Core.Services.inc}

{$I tyControls.Terminal.Core.InputHandler.inc}

{$I tyControls.Terminal.Core.WriteQueue.inc}

{$I tyControls.Terminal.Core.Stream.inc}

end.
