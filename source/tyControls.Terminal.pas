unit tyControls.Terminal;
{$mode objfpc}{$H+}

{ TTyTerminalView:可见的终端控件。把 2 期的 TTyTerminalCore 画出来、接上键盘和滚回。

  自己写的控件,没有移植代码;下面几处的**逻辑**参照 xterm.js 6.0.0(commit c58ea3637f39):
    同步输出(2026)   src/browser/services/RenderService.ts:155-200、:337-380
    焦点与键盘分流    src/browser/CoreBrowserTerminal.ts:860-1017
    滚轮三种去向      src/browser/services/MouseService.ts:250-292
  渲染部件(度量、颜色、字形遮罩、自绘框线、行绘制器)在 tyControls.Terminal.Render,
  按键编码在 tyControls.Terminal.Keyboard。

  改之前要知道的几件事:

  - 本控件**接管**了 Core 的这些事件,宿主别改写:OnData、OnRefreshRows、OnTitleChange、
    OnBell、OnCursorMove、OnScroll、OnBufferActivate、OnModesChange、OnOsc、
    OnQueryBaseColor、OnRequestScrollToBottom、OnProcessRequest、OnWindowOptionsReport、
    OnResize、OnScrollbackCleared。宿主可以自己挂的是 OnIconNameChange、OnLineFeed,
    或者 Core.Parser.Register*Handler。
  - 不在 Paint 里改网格。RenderTo 只读状态、画;度量变了要改网格就记下来,经
    QueueAsyncCall 延后一次(改尺寸会发事件、宿主会改 PTY、会再次失效重画,在绘制里做就是
    重画风暴)。
  - 能出字符的键在 KeyDown 里**不清零**:Win32 上 LCL 处理了 WM_KEYDOWN(Key 被清零)就会
    吞掉随后的 WM_CHAR,字符就丢了。KeyDown 已经发过字节的键,由本控件自己记
    FKeyDownHandled,UTF8KeyPress 见到就丢——不靠 widgetset 的行为。
  - 列数不随滚动条显隐变:网格宽 = 客户区 − 内边距 − 条宽(条宽**恒扣**,备用屏里条只是
    禁用)。进 vim 那一刻列数不变,不会给程序多发一次改尺寸。
  - OnRefreshRows 报的行号 Core 已经换算成**视口行**(InputHandler.parse 的结尾),这里
    直接用,不再加 YBase − YDisp。
  - 主题变了没有钩子:覆盖 Invalidate,比 (模型, ThemeVersion, StyleClass, StyleOverride);
    RenderTo 开头再比一次兜底(无头测试直接调 RenderTo)。 }

interface

uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType, LCLIntf, LazUTF8, Forms,
  ExtCtrls, Clipbrd,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.StyleModel,
  tyControls.Controller, tyControls.ScrollBar, tyControls.PlatformWS, tyControls.TextMenu,
  tyControls.Unicode.Width, tyControls.Terminal.Buffer, tyControls.Terminal.Core,
  tyControls.Terminal.Keyboard, tyControls.Terminal.Render;

type
  { 公开接口里用到的类型在这里各起一个同名别名:宿主只 uses tyControls.Terminal 就够。 }
  TTyTerminalDataEvent = tyControls.Terminal.Core.TTyTerminalDataEvent;
  TTyTerminalTextEvent = tyControls.Terminal.Core.TTyTerminalTextEvent;
  TTyTerminalOscEvent = tyControls.Terminal.Core.TTyTerminalOscEvent;
  TTyTerminalWriteDone = tyControls.Terminal.Core.TTyTerminalWriteDone;
  TTyTerminalCore = tyControls.Terminal.Core.TTyTerminalCore;
  TTyUnicodeVersion = tyControls.Unicode.Width.TTyUnicodeVersion;
  TTyScrollBarAutoHide = tyControls.ScrollBar.TTyScrollBarAutoHide;

  TTyTerminalCursorStyle = (tcsBlock, tcsUnderline, tcsBar);
  TTyTerminalCursorInactiveStyle = (tcisOutline, tcisBlock, tcisBar, tcisUnderline, tcisNone);
  TTyTerminalGridResizeEvent = procedure(Sender: TObject; ACols, ARows: Integer) of object;
  TTyTerminalShortcutQueryEvent = procedure(Sender: TObject; Key: Word; Shift: TShiftState;
    var APassToApplication: Boolean) of object;

  { 终端。右键菜单(ITyTextEditActions)、选区、鼠标上报在 4 期。 }
  TTyTerminalView = class(TTyCustomControl, ITyImeEditable, ITyScrollBarFrameHost)
  private
    FCore: TTyTerminalCore;
    FGlyphCache: TTyTermGlyphCache;
    FRasterizer: TTyTermGlyphRasterizer;
    FRowPainter: TTyTermRowPainter;
    FSurface: TBGRABitmap;
    FFrameDirty, FAllDirty: Boolean;
    FDirty: array of Boolean;
    FFrameBg: Cardinal;
    FColorSig: Cardinal;
    { 度量:规格记录与它的键(便宜的字符串,先比键,变了才解析规格) }
    FSpec: TTyTermFontSpec;
    FSpecKey: string;
    FSpecValid: Boolean;
    FMetrics: TTyTermCellMetrics;
    { 色表:259 项 + 光标墨色,键 = (模型, ThemeVersion, StyleClass, StyleOverride) }
    FPalette: array[0..258] of Cardinal;
    FCursorInkRgb: Cardinal;
    FPaletteModel: TObject;
    FPaletteVersion: Cardinal;
    FPaletteClass, FPaletteOverride: string;
    FPaletteValid: Boolean;
    { 已经通知过 Core 的那个主题键(第一次建色表不通知) }
    FNotifiedModel: TObject;
    FNotifiedVersion: Cardinal;
    FNotifiedClass, FNotifiedOverride: string;
    FNotifiedValid: Boolean;
    { 覆盖通道的字体:StyleOverride 单独解析一次,按 (模型, 版本, 文本) 缓存 }
    FOvrModel: TObject;
    FOvrVersion: Cardinal;
    FOvrText: string;
    FOvrStyle: TTyStyleSet;
    FOvrValid: Boolean;
    { 属性 }
    FCursorInactiveStyle: TTyTerminalCursorInactiveStyle;
    FMacOptionIsMeta: Boolean;
    FAlternateScroll: Boolean;
    FDrawBoldBright: Boolean;
    FScrollBarAutoHide: TTyScrollBarAutoHide;
    FLineHeightPercent: Integer;
    FLetterSpacing: Integer;
    { 状态 }
    FScrollBar: TTyScrollBar;
    FSyncingScroll: Boolean;
    FHasFocus: Boolean;
    FGridAnnounced: Boolean;
    FRelayoutQueued: Boolean;
    FInRender: Boolean;
    FPreviewCols, FPreviewRows: Integer;
    FPaintedCursorRow: Integer;
    { 闪烁 }
    FBlinkTimer: TTimer;
    FBlinkVisible: Boolean;
    FLastActivityMs: Double;
    { 同步输出 }
    FSyncTimer: TTimer;
    FSyncHolding: Boolean;
    FSyncFirst, FSyncLast: Integer;
    { 键盘、滚轮 }
    FKeyDownHandled: Boolean;
    FLastKeyShift: TShiftState;
    FWheelAccum: Integer;
    { 输入法 }
    FImeHook: TObject;
    FImeCaretRect: TRect;
    FPreedit: string;
    FInPreedit: Boolean;
    { 事件 }
    FOnData: TTyTerminalDataEvent;
    FOnGridResize: TTyTerminalGridResizeEvent;
    FOnTitleChange: TTyTerminalTextEvent;
    FOnBell: TNotifyEvent;
    FOnOsc: TTyTerminalOscEvent;
    FOnShortcutQuery: TTyTerminalShortcutQueryEvent;
    { Core 的事件 }
    procedure CoreData(Sender: TObject; const AData: RawByteString);
    procedure CoreRefreshRows(Sender: TObject; AFirst, ALast: Integer);
    procedure CoreTitle(Sender: TObject; const AText: string);
    procedure CoreBell(Sender: TObject);
    procedure CoreOsc(Sender: TObject; AIdent: Integer; const AData: string);
    procedure CoreCursorMove(Sender: TObject);
    procedure CoreScroll(Sender: TObject; AYDisp: Integer);
    procedure CoreBufferActivate(Sender: TObject);
    procedure CoreModesChange(Sender: TObject);
    procedure CoreQueryColor(Sender: TObject; AIndex: Integer; out ARgb: Cardinal);
    procedure CoreRequestScrollToBottom(Sender: TObject);
    procedure CoreProcessRequest(Sender: TObject);
    procedure CoreWindowReport(Sender: TObject; AKind: TTyTermWindowReport);
    procedure CoreResize(Sender: TObject; ACols, ARows: Integer);
    procedure CoreScrollbackCleared(Sender: TObject);
    { 调度 }
    procedure AsyncSlice(Data: PtrInt);
    procedure AsyncRelayout(Data: PtrInt);
    { 主题、字体、网格 }
    function StyleColor(const ATypeKey: string; ABackground: Boolean; AFallback: Cardinal): Cardinal;
    function EnsurePalette: Boolean;
    procedure EnsureThemeCurrent;
    function OverrideStyle: TTyStyleSet;
    function ResolveFontSpec(APPI: Integer): TTyTermFontSpec;
    function SpecKey(APPI: Integer): string;
    function EnsureMetrics(APPI: Integer): Boolean;
    function ContentInsets(APPI: Integer): TRect;
    function ScrollBarWidth(APPI: Integer): Integer;
    procedure RequestRelayout;
    procedure UpdateGrid;
    function GridCellRect(ACol, ARow: Integer; const AInsets: TRect): TRect;
    procedure WriteDesignPreview;
    { 脏行 }
    procedure DirtyRows(AFirst, ALast: Integer);
    procedure DirtyAll;
    procedure DirtyCursorRows;
    function CursorViewRow: Integer;
    function CursorShapeNow: TTyTermCursorShape;
    function ColorSignature: Cardinal;
    procedure PaintFrame(APPI: Integer);
    procedure PaintPreedit(APPI: Integer);
    { 闪烁、同步输出 }
    function EffectiveBlink: Boolean;
    procedure UpdateBlinkTimer;
    procedure BlinkTimerFired(Sender: TObject);
    procedure NoteActivity;
    function NowMs: Double;
    { 滚动条 }
    procedure UpdateScrollBar(APPI: Integer);
    procedure SyncScrollBar;
    procedure ScrollBarChange(Sender: TObject);
    procedure NoteHostHover(AHovered: Boolean);
    { 属性 getter / setter }
    function GetCols: Integer;
    function GetRows: Integer;
    function GetTitle: string;
    function GetScrollback: Integer;
    procedure SetScrollback(AValue: Integer);
    function GetCursorStyle: TTyTerminalCursorStyle;
    procedure SetCursorStyle(AValue: TTyTerminalCursorStyle);
    procedure SetCursorInactiveStyle(AValue: TTyTerminalCursorInactiveStyle);
    function GetCursorBlink: Boolean;
    procedure SetCursorBlink(AValue: Boolean);
    function GetAmbiguousWide: Boolean;
    procedure SetAmbiguousWide(AValue: Boolean);
    function GetUnicodeVersion: TTyUnicodeVersion;
    procedure SetUnicodeVersion(AValue: TTyUnicodeVersion);
    procedure SetDrawBoldBright(AValue: Boolean);
    function GetReadOnly: Boolean;
    procedure SetReadOnly(AValue: Boolean);
    function GetConvertEol: Boolean;
    procedure SetConvertEol(AValue: Boolean);
    function GetTabStopWidth: Integer;
    procedure SetTabStopWidth(AValue: Integer);
    function GetScrollOnUserInput: Boolean;
    procedure SetScrollOnUserInput(AValue: Boolean);
    procedure SetScrollBarAutoHide(AValue: TTyScrollBarAutoHide);
    procedure SetLineHeightPercent(AValue: Integer);
    procedure SetLetterSpacing(AValue: Integer);
  protected
    { 平台标志:按平台(不是 widgetset)取;受保护,测试可以改成别的平台 }
    FIsMac, FIsWindows: Boolean;
    function GetStyleTypeKey: string; override;
    procedure SetController(AValue: TTyStyleController); override;
    procedure Loaded; override;
    procedure SetParent(AParent: TWinControl); override;
    procedure Resize; override;
    procedure Paint; override;
    procedure DoEnter; override;
    procedure DoExit; override;
    procedure MouseEnter; override;
    procedure MouseLeave; override;
    { 调度的缝:默认 Application.QueueAsyncCall(设计期不排片) }
    procedure ScheduleSlice; virtual;
    { 失效几行(视口行):有句柄时 InvalidateRect 那几行的并集。子类覆盖必须调 inherited。 }
    procedure InvalidateRows(AFirst, ALast: Integer); virtual;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { 闪烁计时器的回调转到这里;测试直接喂时间 }
    procedure BlinkTick(ANowMs: Double);
    { 同步输出 1 秒到点(计时器的回调;测试直接调) }
    procedure SyncTimerFired(Sender: TObject);
    function ReadClipboardText: string; virtual;
    procedure WriteClipboardText(const S: string); virtual;
    { ITyScrollBarFrameHost }
    function ScrollBarFrameStyle: TTyStyleSet;
    function EmbedsScrollBar(ABar: TTyScrollBar): Boolean;
    { ITyImeEditable(macOS 的本地组字串) }
    function ImeTargetControl: TWinControl;
    function ImeIsReadOnly: Boolean;
    function ImeCaretBoundClient: TRect;
    function ImeCaretIndex: Integer;
    procedure ImeSessionBegin;
    procedure ImeSessionEnd;
    procedure ImeReplace(AStart, ALen: Integer; const AText: string);
    { FOR THE TESTS }
    function RowsPainted: Integer;
    function GlyphCache: TTyTermGlyphCache;
    function Metrics: TTyTermCellMetrics;
    function FontSpec: TTyTermFontSpec;
    function SurfaceBitmap: TBGRABitmap;
    function BlinkTimerActive: Boolean;
    function SyncTimerActive: Boolean;
    function PendingSyncRows: TPoint;         { (-1, -1) = 没在攒 }
    function HasFocusFlag: Boolean;
    property ScrollBar: TTyScrollBar read FScrollBar;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Invalidate; override;
    procedure Write(const AData: RawByteString; AOnDone: TTyTerminalWriteDone = nil; ATag: PtrInt = 0); overload;
    procedure Write(const ABuf; ACount: Integer; AOnDone: TTyTerminalWriteDone = nil; ATag: PtrInt = 0); overload;
    procedure WriteSync(const AData: RawByteString);
    { 粘贴编码(括号粘贴由程序的 2004 决定)后当作键入发给程序 }
    procedure Paste(const AText: string);
    { 当作键入 }
    procedure Input(const AText: string);
    { 清滚回(Core.ClearScrollback) }
    procedure Clear;
    { Core.Reset + 整屏重画 }
    procedure Reset;
    procedure ScrollLines(ADelta: Integer);
    procedure ScrollPages(APages: Integer);
    procedure ScrollToTop;
    procedure ScrollToBottom;
    procedure PasteFromClipboard;
    { 复制选区;选区在 4 期,本期什么都不做 }
    procedure CopyToClipboard;
    { 客户区设备像素 -> 0 起的格子,钳在网格内 }
    function CellAt(X, Y: Integer): TPoint;
    { 视口行的格子矩形,客户区设备像素 }
    function CellRect(ACol, ARow: Integer): TRect;
    { 给定网格要多大的客户区(内边距、条宽都算进去) }
    function SizeForGrid(ACols, ARows: Integer): TSize;
    property Core: TTyTerminalCore read FCore;
    property Cols: Integer read GetCols;
    property Rows: Integer read GetRows;
    property Title: string read GetTitle;
  published
    property Scrollback: Integer read GetScrollback write SetScrollback default 1000;
    property CursorStyle: TTyTerminalCursorStyle read GetCursorStyle write SetCursorStyle default tcsBlock;
    property CursorInactiveStyle: TTyTerminalCursorInactiveStyle read FCursorInactiveStyle
      write SetCursorInactiveStyle default tcisOutline;
    property CursorBlink: Boolean read GetCursorBlink write SetCursorBlink default False;
    property AmbiguousWide: Boolean read GetAmbiguousWide write SetAmbiguousWide default False;
    property UnicodeVersion: TTyUnicodeVersion read GetUnicodeVersion write SetUnicodeVersion default tuv11;
    property MacOptionIsMeta: Boolean read FMacOptionIsMeta write FMacOptionIsMeta default False;
    property AlternateScroll: Boolean read FAlternateScroll write FAlternateScroll default True;
    property DrawBoldTextInBrightColors: Boolean read FDrawBoldBright write SetDrawBoldBright default True;
    property ReadOnly: Boolean read GetReadOnly write SetReadOnly default False;
    property ConvertEol: Boolean read GetConvertEol write SetConvertEol default False;
    property TabStopWidth: Integer read GetTabStopWidth write SetTabStopWidth default 8;
    property ScrollOnUserInput: Boolean read GetScrollOnUserInput write SetScrollOnUserInput default True;
    property ScrollBarAutoHide: TTyScrollBarAutoHide read FScrollBarAutoHide write SetScrollBarAutoHide
      default sbahDefault;
    property LineHeightPercent: Integer read FLineHeightPercent write SetLineHeightPercent default 100;
    property LetterSpacing: Integer read FLetterSpacing write SetLetterSpacing default 0;
    property TabStop default True;
    property Align;
    property Anchors;
    property ParentFont;
    property OnData: TTyTerminalDataEvent read FOnData write FOnData;
    property OnGridResize: TTyTerminalGridResizeEvent read FOnGridResize write FOnGridResize;
    property OnTitleChange: TTyTerminalTextEvent read FOnTitleChange write FOnTitleChange;
    property OnBell: TNotifyEvent read FOnBell write FOnBell;
    property OnOsc: TTyTerminalOscEvent read FOnOsc write FOnOsc;
    property OnShortcutQuery: TTyTerminalShortcutQueryEvent read FOnShortcutQuery write FOnShortcutQuery;
  end;

const
  { 设计期预览:RIS 之后写进去,不进流式化。16 色前景 / 背景、属性、宽字符、框线。 }
  TyTerminalDesignPreview: RawByteString =
    #27'[30mblack '#27'[31mred '#27'[32mgreen '#27'[33myellow '#27'[34mblue '#27'[35mmagenta '
    + #27'[36mcyan '#27'[37mwhite'#27'[0m'#13#10
    + #27'[90mblack '#27'[91mred '#27'[92mgreen '#27'[93myellow '#27'[94mblue '#27'[95mmagenta '
    + #27'[96mcyan '#27'[97mwhite'#27'[0m'#13#10
    + #27'[40m  '#27'[41m  '#27'[42m  '#27'[43m  '#27'[44m  '#27'[45m  '#27'[46m  '#27'[47m  '
    + #27'[100m  '#27'[101m  '#27'[102m  '#27'[103m  '#27'[104m  '#27'[105m  '#27'[106m  '#27'[107m  '
    + #27'[0m'#13#10
    + #27'[1mbold'#27'[22m '#27'[2mdim'#27'[22m '#27'[3mitalic'#27'[23m '
    + #27'[4:1msingle'#27'[24m '#27'[4:2mdouble'#27'[24m '#27'[4:3mcurly'#27'[24m '
    + #27'[4:4mdotted'#27'[24m '#27'[4:5mdashed'#27'[24m '#27'[9mstrike'#27'[29m '
    + #27'[7minverse'#27'[27m'#13#10
    { 中文 한국어 ┌─┬─┐ }
    + #$E4#$B8#$AD#$E6#$96#$87' '#$ED#$95#$9C#$EA#$B5#$AD#$EC#$96#$B4' '
    + #$E2#$94#$8C#$E2#$94#$80#$E2#$94#$AC#$E2#$94#$80#$E2#$94#$90
    + #27'[0m';

implementation

const
  { token 缺失时的兜底;真值都在主题里(§11) }
  FallbackFg = $000000;
  FallbackBg = $FFFFFF;
  TangoFallback: array[0..15] of Cardinal = (
    $2E3436, $CC0000, $4E9A06, $C4A000, $3465A4, $75507B, $06989A, $D3D7CF,
    $555753, $EF2929, $8AE234, $FCE94F, $729FCF, $AD7FA8, $34E2E2, $EEEEEC);
  BlinkIntervalMs = 600;
  BlinkRestMs = 300000;          { 5 分钟不活动就停在「显示」 }
  SyncTimeoutMs = 1000;          { RenderService.ts:359-363 }

{ ---- 构造与析构 --------------------------------------------------------------------- }

constructor TTyTerminalView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque, csDoubleClicks, csTripleClicks];
  TabStop := True;
  FCursorInactiveStyle := tcisOutline;
  FAlternateScroll := True;
  FDrawBoldBright := True;
  FScrollBarAutoHide := sbahDefault;
  FLineHeightPercent := 100;
  FLetterSpacing := 0;
  FIsMac := TyTerminalIsMac;
  FIsWindows := TyTerminalIsWindows;
  FBlinkVisible := True;
  FPaintedCursorRow := -1;
  FSyncFirst := -1;
  FSyncLast := -1;
  FGlyphCache := TTyTermGlyphCache.Create;
  FRasterizer := TTyTermGlyphRasterizer.Create;
  FRowPainter := TTyTermRowPainter.Create;
  FCore := TTyTerminalCore.Create(80, 24);
  FCore.OnData := @CoreData;
  FCore.OnRefreshRows := @CoreRefreshRows;
  FCore.OnTitleChange := @CoreTitle;
  FCore.OnBell := @CoreBell;
  FCore.OnOsc := @CoreOsc;
  FCore.OnCursorMove := @CoreCursorMove;
  FCore.OnScroll := @CoreScroll;
  FCore.OnBufferActivate := @CoreBufferActivate;
  FCore.OnModesChange := @CoreModesChange;
  FCore.OnQueryBaseColor := @CoreQueryColor;
  FCore.OnRequestScrollToBottom := @CoreRequestScrollToBottom;
  FCore.OnProcessRequest := @CoreProcessRequest;
  FCore.OnWindowOptionsReport := @CoreWindowReport;
  FCore.OnResize := @CoreResize;
  FCore.OnScrollbackCleared := @CoreScrollbackCleared;
  { Core 出生时 Focused = True(2 期交接):新控件还没焦点,马上告诉它 }
  FCore.ReportFocus(False);
  SetLength(FDirty, FCore.Rows);
  FAllDirty := True;
  FFrameDirty := True;
  SetInitialBounds(0, 0, 480, 300);
end;

destructor TTyTerminalView.Destroy;
begin
  { 地雷 8 的顺序:排着的异步调用 -> 两个计时器 -> 输入法 -> Core 的事件 -> Core 和缓存 }
  Application.RemoveAsyncCalls(Self);
  FreeAndNil(FBlinkTimer);
  FreeAndNil(FSyncTimer);
  TyImeUninstall(FImeHook);
  if FCore <> nil then
  begin
    FCore.OnData := nil;
    FCore.OnRefreshRows := nil;
    FCore.OnTitleChange := nil;
    FCore.OnBell := nil;
    FCore.OnOsc := nil;
    FCore.OnCursorMove := nil;
    FCore.OnScroll := nil;
    FCore.OnBufferActivate := nil;
    FCore.OnModesChange := nil;
    FCore.OnQueryBaseColor := nil;
    FCore.OnRequestScrollToBottom := nil;
    FCore.OnProcessRequest := nil;
    FCore.OnWindowOptionsReport := nil;
    FCore.OnResize := nil;
    FCore.OnScrollbackCleared := nil;
  end;
  FreeAndNil(FCore);
  FreeAndNil(FRowPainter);
  FreeAndNil(FGlyphCache);
  FreeAndNil(FRasterizer);
  FreeAndNil(FSurface);
  inherited Destroy;
end;

function TTyTerminalView.GetStyleTypeKey: string;
begin
  Result := 'TyTerminal';
end;

{ ---- Core 的事件 ------------------------------------------------------------------- }

procedure TTyTerminalView.CoreData(Sender: TObject; const AData: RawByteString);
begin
  { ReadOnly 已经由 Core 挡掉(上游 disableStdin 同样挡在 triggerDataEvent 里) }
  if Assigned(FOnData) then FOnData(Self, AData);
end;

procedure TTyTerminalView.CoreRefreshRows(Sender: TObject; AFirst, ALast: Integer);
begin
  { 同步输出开着:攒起来,不失效;计时器从**第一次攒行**起算(RenderService.ts 的
    bufferRows,_timeout ??=),模式打开本身不起表 }
  if FCore.Modes.SynchronizedOutput then
  begin
    if FSyncHolding then
    begin
      FSyncFirst := Min(FSyncFirst, AFirst);
      FSyncLast := Max(FSyncLast, ALast);
    end
    else
    begin
      FSyncHolding := True;
      FSyncFirst := AFirst;
      FSyncLast := ALast;
    end;
    if FSyncTimer = nil then
    begin
      FSyncTimer := TTimer.Create(nil);
      FSyncTimer.Enabled := False;
      FSyncTimer.Interval := SyncTimeoutMs;
      FSyncTimer.OnTimer := @SyncTimerFired;
    end;
    if not FSyncTimer.Enabled then
      FSyncTimer.Enabled := True;
    Exit;
  end;
  { 模式关了:攒着的并进来一起画 }
  if FSyncHolding then
  begin
    AFirst := Min(AFirst, FSyncFirst);
    ALast := Max(ALast, FSyncLast);
    FSyncHolding := False;
    FSyncFirst := -1;
    FSyncLast := -1;
    if FSyncTimer <> nil then FSyncTimer.Enabled := False;
  end;
  DirtyRows(AFirst, ALast);
  NoteActivity;
end;

procedure TTyTerminalView.CoreTitle(Sender: TObject; const AText: string);
begin
  if Assigned(FOnTitleChange) then FOnTitleChange(Self, AText);
end;

procedure TTyTerminalView.CoreBell(Sender: TObject);
begin
  if Assigned(FOnBell) then FOnBell(Self);
end;

procedure TTyTerminalView.CoreOsc(Sender: TObject; AIdent: Integer; const AData: string);
begin
  if Assigned(FOnOsc) then FOnOsc(Self, AIdent, AData);
end;

procedure TTyTerminalView.CoreCursorMove(Sender: TObject);
begin
  DirtyCursorRows;
  NoteActivity;
  { 输入法的候选窗跟着光标:光标行标脏会触发一次重画,RenderTo 末尾更新矩形 }
end;

procedure TTyTerminalView.CoreScroll(Sender: TObject; AYDisp: Integer);
begin
  DirtyAll;
  SyncScrollBar;
end;

procedure TTyTerminalView.CoreBufferActivate(Sender: TObject);
begin
  DirtyAll;
  SyncScrollBar;
end;

procedure TTyTerminalView.CoreModesChange(Sender: TObject);
begin
  { DECSCUSR、DECTCEM:光标行重画;程序要不要闪烁也在这里变 }
  DirtyCursorRows;
  UpdateBlinkTimer;
end;

procedure TTyTerminalView.CoreQueryColor(Sender: TObject; AIndex: Integer; out ARgb: Cardinal);
begin
  EnsurePalette;
  if (AIndex >= 0) and (AIndex <= 258) then
    ARgb := FPalette[AIndex]
  else
    ARgb := 0;
end;

procedure TTyTerminalView.CoreRequestScrollToBottom(Sender: TObject);
begin
  FCore.ScrollToBottom;
end;

procedure TTyTerminalView.CoreProcessRequest(Sender: TObject);
begin
  ScheduleSlice;
end;

procedure TTyTerminalView.CoreWindowReport(Sender: TObject; AKind: TTyTermWindowReport);
begin
  { CoreBrowserTerminal.ts:1133-1150 报 CSS 像素;我们报设备像素(同 SGR 像素鼠标) }
  EnsureMetrics(Font.PixelsPerInch);
  case AKind of
    twrWinSizePixels:
      FCore.Input(#27'[4;' + IntToStr(FCore.Rows * FMetrics.CellH) + ';'
        + IntToStr(FCore.Cols * FMetrics.CellW) + 't', False);
    twrCellSizePixels:
      FCore.Input(#27'[6;' + IntToStr(FMetrics.CellH) + ';' + IntToStr(FMetrics.CellW) + 't', False);
  end;
end;

procedure TTyTerminalView.CoreResize(Sender: TObject; ACols, ARows: Integer);
begin
  SetLength(FDirty, ARows);
  FAllDirty := True;
  FFrameDirty := True;
  FGridAnnounced := True;
  if Assigned(FOnGridResize) then FOnGridResize(Self, ACols, ARows);
  SyncScrollBar;
  if HandleAllocated then LCLIntf.InvalidateRect(Handle, nil, False);
end;

procedure TTyTerminalView.CoreScrollbackCleared(Sender: TObject);
begin
  SyncScrollBar;
end;

{ ---- 调度 --------------------------------------------------------------------------- }

procedure TTyTerminalView.ScheduleSlice;
begin
  if csDesigning in ComponentState then Exit;
  Application.QueueAsyncCall(@AsyncSlice, 0);
end;

procedure TTyTerminalView.AsyncSlice(Data: PtrInt);
begin
  if FCore.ProcessPending then
    ScheduleSlice;
end;

procedure TTyTerminalView.AsyncRelayout(Data: PtrInt);
begin
  FRelayoutQueued := False;
  if csDestroying in ComponentState then Exit;
  UpdateGrid;
end;

procedure TTyTerminalView.RequestRelayout;
begin
  if FInRender then
  begin
    { 在绘制里:记下来,消息循环里再改(地雷 5) }
    if not FRelayoutQueued then
    begin
      FRelayoutQueued := True;
      Application.QueueAsyncCall(@AsyncRelayout, 0);
    end;
  end
  else
    UpdateGrid;
end;

{ ---- 主题 --------------------------------------------------------------------------- }

function TTyTerminalView.StyleColor(const ATypeKey: string; ABackground: Boolean; AFallback: Cardinal): Cardinal;
var
  st: TTyStyleSet;
begin
  st := ActiveController.Model.ResolveStyle(ATypeKey, '', []);
  Result := AFallback;
  if ABackground then
  begin
    if (tpBackground in st.Present) and (st.Background.Kind = tfkSolid) then
      Result := Cardinal(st.Background.Color) and $FFFFFF;
  end
  else if tpTextColor in st.Present then
    Result := Cardinal(st.TextColor) and $FFFFFF;
end;

function TTyTerminalView.EnsurePalette: Boolean;
var
  model: TObject;
  st: TTyStyleSet;
  i: Integer;
begin
  model := ActiveController.Model;
  if FPaletteValid and (FPaletteModel = model)
    and (FPaletteVersion = ActiveController.Model.ThemeVersion)
    and (FPaletteClass = StyleClass) and (FPaletteOverride = StyleOverride) then
    Exit(False);
  { 0..15 主题;16..255 公式;256 / 257 TyTerminal 的前景 / 底色;258 光标底色。
    颜色一律取 RGB、丢 alpha;没解析出来的退到 Tango / 黑白,不抛。 }
  for i := 0 to 15 do
    FPalette[i] := StyleColor('TyTerminalAnsi' + IntToStr(i), False, TangoFallback[i]);
  for i := 16 to 255 do
    FPalette[i] := TyTermDefaultPaletteColor(i);
  st := CurrentStyle;
  if tpTextColor in st.Present then
    FPalette[256] := Cardinal(st.TextColor) and $FFFFFF
  else
    FPalette[256] := FallbackFg;
  if (tpBackground in st.Present) and (st.Background.Kind = tfkSolid) then
    FPalette[257] := Cardinal(st.Background.Color) and $FFFFFF
  else
    FPalette[257] := FallbackBg;
  FPalette[258] := StyleColor('TyTerminalCursor', True, FPalette[256]);
  FCursorInkRgb := StyleColor('TyTerminalCursor', False, FPalette[257]);
  FPaletteModel := model;
  FPaletteVersion := ActiveController.Model.ThemeVersion;
  FPaletteClass := StyleClass;
  FPaletteOverride := StyleOverride;
  FPaletteValid := True;
  Result := True;
end;

procedure TTyTerminalView.EnsureThemeCurrent;
begin
  EnsurePalette;
  if FNotifiedValid and (FNotifiedModel = FPaletteModel) and (FNotifiedVersion = FPaletteVersion)
    and (FNotifiedClass = FPaletteClass) and (FNotifiedOverride = FPaletteOverride) then
    Exit;
  { 换了主题:Core 清 OSC 覆盖色、2031 开着就报明暗;外框和每一行重画;度量的键失效。
    第一次建色表不算「换」。 }
  if FNotifiedValid then
    FCore.NotifyColorSchemeChanged;
  FNotifiedModel := FPaletteModel;
  FNotifiedVersion := FPaletteVersion;
  FNotifiedClass := FPaletteClass;
  FNotifiedOverride := FPaletteOverride;
  FNotifiedValid := True;
  FFrameDirty := True;
  FAllDirty := True;
  FSpecKey := '';
end;

procedure TTyTerminalView.Invalidate;
var
  wasKey: string;
begin
  { 换主题只有这一个广播(TTyStyleController.Changed 对每个登记的控件 Invalidate),
    理由同 TTyScrollBar.Invalidate 的注释。 }
  if (FCore <> nil) and not (csDestroying in ComponentState) then
  begin
    wasKey := FSpecKey;
    EnsureThemeCurrent;
    if (wasKey <> '') and (FSpecKey = '') and not FInRender then
      RequestRelayout;
  end;
  inherited Invalidate;
end;

procedure TTyTerminalView.SetController(AValue: TTyStyleController);
begin
  inherited SetController(AValue);
  { 键里有模型指针,换 controller 自然走到 ThemeChanged;条也要跟着换 }
  if FScrollBar <> nil then FScrollBar.Controller := AValue;
  if FCore <> nil then Invalidate;
end;

{ ---- 字体与度量 ---------------------------------------------------------------------- }

function TTyTerminalView.OverrideStyle: TTyStyleSet;
var
  model: TTyStyleModel;
begin
  if StyleOverride = '' then
    Exit(EmptyStyleSet);
  model := ActiveController.Model;
  if (not FOvrValid) or (FOvrModel <> model) or (FOvrVersion <> model.ThemeVersion)
    or (FOvrText <> StyleOverride) then
  begin
    FOvrStyle := model.ResolveOverride(StyleOverride);
    FOvrModel := model;
    FOvrVersion := model.ThemeVersion;
    FOvrText := StyleOverride;
    FOvrValid := True;
  end;
  Result := FOvrStyle;
end;

function PlatformMonospace: string;
begin
  {$IF DEFINED(MSWINDOWS)}
  Result := 'Consolas';
  {$ELSEIF DEFINED(DARWIN)}
  Result := 'Menlo';
  {$ELSE}
  Result := 'Monospace';
  {$ENDIF}
end;

{ monospace-wide 的平台默认(开工前实验 E1):Windows 上 Consolas 经系统字体链接就把 CJK
  画在格子里、两格宽、不截,所以不另用字体(空串 = 交给系统替换);macOS / Linux 没在
  真机上量过,按证据先给 CJK 字体(等宽主字体的遮罩会切掉 CJK 下半截),进真机验收。 }
function PlatformMonospaceWide: string;
begin
  {$IF DEFINED(MSWINDOWS)}
  Result := '';
  {$ELSEIF DEFINED(DARWIN)}
  Result := 'PingFang SC';
  {$ELSE}
  Result := 'Noto Sans CJK SC';
  {$ENDIF}
end;

function TTyTerminalView.SpecKey(APPI: Integer): string;
var
  model: TTyStyleModel;
begin
  model := ActiveController.Model;
  Result := IntToHex(PtrUInt(model), 16) + '|' + IntToStr(model.ThemeVersion) + '|' + StyleClass + '|'
    + StyleOverride + '|' + BoolToStr(ParentFont, '1', '0') + '|' + Font.Name + '|' + IntToStr(Font.Size) + '|'
    + IntToStr(APPI) + '|' + IntToStr(FLetterSpacing) + '|' + IntToStr(FLineHeightPercent);
end;

function TTyTerminalView.ResolveFontSpec(APPI: Integer): TTyTermFontSpec;
var
  ovr, st: TTyStyleSet;
  model: TTyStyleModel;
  name, wide: string;
  size: Integer;
begin
  { 顺序(开工前问题二第 6 条):StyleOverride > 显式 Font > TyTerminal 规则 > token > monospace。
    font-family 不走 var()(StyleModel 不求值它),token 由这里 RawVar 读。 }
  model := ActiveController.Model;
  ovr := OverrideStyle;
  st := CurrentStyle;
  if (tpFontName in ovr.Present) and (ovr.FontName <> '') then
    name := ovr.FontName
  else if (not ParentFont) and (Font.Name <> '') and not SameText(Font.Name, 'default') then
    name := Font.Name
  else if (tpFontName in st.Present) and (st.FontName <> '') then
    name := st.FontName
  else
    name := Trim(model.RawVar('--terminal-font-family'));
  if (name = '') or SameText(name, 'monospace') then
    name := PlatformMonospace;
  wide := Trim(model.RawVar('--terminal-font-family-wide'));
  if SameText(wide, 'monospace-wide') then
    wide := PlatformMonospaceWide;
  if (tpFontSize in ovr.Present) and (ovr.FontSize > 0) then
    size := ovr.FontSize
  else if (not ParentFont) and (Font.Size <> 0) then
    size := Abs(Font.Size)
  else if (tpFontSize in st.Present) and (st.FontSize > 0) then
    size := st.FontSize
  else
    size := TyEffectiveFontSizeLogical(0);
  Result := Default(TTyTermFontSpec);
  Result.MainName := name;
  Result.WideName := wide;
  Result.SizeLogical := size;
  if APPI <= 0 then APPI := 96;
  Result.PPI := APPI;
  Result.LetterSpacingLogical := FLetterSpacing;
  Result.LineHeightPercent := FLineHeightPercent;
  Result.UnderlineWidthLogical := ActiveController.Metric('--terminal-underline-width', 1);
  Result.CursorWidthLogical := ActiveController.Metric('--terminal-cursor-width', 1);
end;

function TTyTerminalView.EnsureMetrics(APPI: Integer): Boolean;
var
  key: string;
  spec: TTyTermFontSpec;
begin
  Result := False;
  if APPI <= 0 then APPI := 96;
  key := SpecKey(APPI);
  if FSpecValid and (key = FSpecKey) then Exit;
  FSpecKey := key;
  spec := ResolveFontSpec(APPI);
  if FSpecValid and (spec = FSpec) then Exit;
  FSpec := spec;
  FMetrics := TyTermMeasureCell(spec);
  FSpecValid := True;
  FGlyphCache.Clear;
  FAllDirty := True;
  FFrameDirty := True;
  Result := True;
end;

function TTyTerminalView.ContentInsets(APPI: Integer): TRect;
var
  st: TTyStyleSet;
  b: Integer;
begin
  st := CurrentStyle;
  b := 0;
  if TyBorderVisible(st) then b := st.BorderWidth;
  Result := Rect(MulDiv(st.Padding.Left + b, APPI, 96), MulDiv(st.Padding.Top + b, APPI, 96),
    MulDiv(st.Padding.Right + b, APPI, 96), MulDiv(st.Padding.Bottom + b, APPI, 96));
end;

function TTyTerminalView.ScrollBarWidth(APPI: Integer): Integer;
begin
  Result := MulDiv(ActiveController.Metric('--scrollbar-size', TyScrollbarSize), APPI, 96);
end;

{ ---- 网格 --------------------------------------------------------------------------- }

procedure TTyTerminalView.Resize;
begin
  inherited Resize;
  UpdateGrid;
end;

procedure TTyTerminalView.UpdateGrid;
var
  ppi, cols, rows, barW: Integer;
  ins: TRect;
begin
  if (FCore = nil) or (Parent = nil) then Exit;
  if [csLoading, csDestroying] * ComponentState <> [] then Exit;
  ppi := Font.PixelsPerInch;
  EnsureThemeCurrent;
  EnsureMetrics(ppi);
  ins := ContentInsets(ppi);
  barW := ScrollBarWidth(ppi);
  UpdateScrollBar(ppi);
  { 条宽恒扣(地雷 6);设计期也扣,设计器和运行时同一网格 }
  cols := Max(TyTermMinimumCols, (ClientWidth - ins.Left - ins.Right - barW) div FMetrics.CellW);
  rows := Max(TyTermMinimumRows, (ClientHeight - ins.Top - ins.Bottom) div FMetrics.CellH);
  if (cols <> FCore.Cols) or (rows <> FCore.Rows) then
    { OnResize 回来做其余的事(地雷 7:在 Core 的事件里调会被延后,以 OnResize 为准) }
    FCore.Resize(cols, rows)
  else if not FGridAnnounced then
  begin
    { 加载完成后的第一次排版,尺寸没变也发一次(spec §9.2) }
    FGridAnnounced := True;
    if Assigned(FOnGridResize) then FOnGridResize(Self, cols, rows);
  end;
  WriteDesignPreview;
end;

procedure TTyTerminalView.Loaded;
begin
  inherited Loaded;
  UpdateGrid;
end;

procedure TTyTerminalView.SetParent(AParent: TWinControl);
begin
  inherited SetParent(AParent);
  if AParent <> nil then UpdateGrid;
end;

procedure TTyTerminalView.WriteDesignPreview;
begin
  if not (csDesigning in ComponentState) then Exit;
  if (FPreviewCols = FCore.Cols) and (FPreviewRows = FCore.Rows) then Exit;
  FPreviewCols := FCore.Cols;
  FPreviewRows := FCore.Rows;
  FCore.WriteSync(#27'c' + TyTerminalDesignPreview);
end;

function TTyTerminalView.GridCellRect(ACol, ARow: Integer; const AInsets: TRect): TRect;
begin
  Result.Left := AInsets.Left + ACol * FMetrics.CellW;
  Result.Top := AInsets.Top + ARow * FMetrics.CellH;
  Result.Right := Result.Left + FMetrics.CellW;
  Result.Bottom := Result.Top + FMetrics.CellH;
end;

function TTyTerminalView.CellRect(ACol, ARow: Integer): TRect;
begin
  EnsureMetrics(Font.PixelsPerInch);
  Result := GridCellRect(ACol, ARow, ContentInsets(Font.PixelsPerInch));
end;

function TTyTerminalView.CellAt(X, Y: Integer): TPoint;
var
  ins: TRect;
begin
  { 上游先钳再除(MouseCoordsService.ts:38-44);这里除完再钳到网格内,结果相同 }
  EnsureMetrics(Font.PixelsPerInch);
  ins := ContentInsets(Font.PixelsPerInch);
  X := X - ins.Left;
  Y := Y - ins.Top;
  if X < 0 then X := 0;
  if Y < 0 then Y := 0;
  Result.X := Min(X div FMetrics.CellW, FCore.Cols - 1);
  Result.Y := Min(Y div FMetrics.CellH, FCore.Rows - 1);
end;

function TTyTerminalView.SizeForGrid(ACols, ARows: Integer): TSize;
var
  ins: TRect;
begin
  EnsureMetrics(Font.PixelsPerInch);
  ins := ContentInsets(Font.PixelsPerInch);
  Result.cx := ins.Left + ins.Right + ScrollBarWidth(Font.PixelsPerInch) + ACols * FMetrics.CellW;
  Result.cy := ins.Top + ins.Bottom + ARows * FMetrics.CellH;
end;

{ ---- 脏行与失效 ----------------------------------------------------------------------- }

procedure TTyTerminalView.InvalidateRows(AFirst, ALast: Integer);
var
  r: TRect;
  ins: TRect;
begin
  if not HandleAllocated then Exit;
  if not FSpecValid then
  begin
    LCLIntf.InvalidateRect(Handle, nil, False);
    Exit;
  end;
  ins := ContentInsets(Font.PixelsPerInch);
  r := GridCellRect(0, AFirst, ins);
  r.Left := 0;
  r.Right := ClientWidth;
  r.Bottom := GridCellRect(0, ALast, ins).Bottom;
  LCLIntf.InvalidateRect(Handle, @r, False);
end;

procedure TTyTerminalView.DirtyRows(AFirst, ALast: Integer);
var
  r: Integer;
begin
  if AFirst < 0 then AFirst := 0;
  if ALast > High(FDirty) then ALast := High(FDirty);
  if ALast < AFirst then Exit;
  for r := AFirst to ALast do
    FDirty[r] := True;
  InvalidateRows(AFirst, ALast);
end;

procedure TTyTerminalView.DirtyAll;
begin
  FAllDirty := True;
  if Length(FDirty) > 0 then
    InvalidateRows(0, High(FDirty));
end;

function TTyTerminalView.CursorViewRow: Integer;
var
  buf: TTyTerminalBuffer;
begin
  buf := FCore.Buffer;
  Result := buf.Y + buf.YBase - buf.YDisp;
end;

procedure TTyTerminalView.DirtyCursorRows;
var
  r: Integer;
begin
  if (FPaintedCursorRow >= 0) and (FPaintedCursorRow <= High(FDirty)) then
    DirtyRows(FPaintedCursorRow, FPaintedCursorRow);
  r := CursorViewRow;
  if (r >= 0) and (r <= High(FDirty)) and (r <> FPaintedCursorRow) then
    DirtyRows(r, r);
end;

function TTyTerminalView.CursorShapeNow: TTyTermCursorShape;
var
  req: TTyTermCursorRequest;
begin
  if FHasFocus then
  begin
    { 程序的 DECSCUSR 压过属性 }
    req := FCore.Modes.CursorRequest;
    if req = tcrDefault then
      case FCore.CursorStyle of
        tcoUnderline: req := tcrUnderline;
        tcoBar: req := tcrBar;
      else
        req := tcrBlock;
      end;
    case req of
      tcrUnderline: Result := tcpUnderline;
      tcrBar: Result := tcpBar;
    else
      Result := tcpBlock;
    end;
  end
  else
    case FCursorInactiveStyle of
      tcisOutline: Result := tcpOutline;
      tcisBlock: Result := tcpBlock;
      tcisBar: Result := tcpBar;
      tcisUnderline: Result := tcpUnderline;
    else
      Result := tcpNone;
    end;
end;

function TTyTerminalView.ColorSignature: Cardinal;
var
  i: Integer;
begin
  { OSC 4 / 10 / 11 / 12 改了覆盖色,Core 没有专门的事件;整屏的颜色签名变了就全部重画 }
  Result := 2166136261;
  for i := 0 to 258 do
    Result := (Result xor FCore.ResolveColor(i)) * 16777619;
end;

{ ---- 绘制 --------------------------------------------------------------------------- }

procedure TTyTerminalView.PaintFrame(APPI: Integer);
var
  P: TTyPainter;
  st: TTyStyleSet;
begin
  { 外框 + 内边距 + 网格外的余量:底色取 Core 的 257(OSC 11 改了底色,内边距也跟着变) }
  FSurface.Fill(TyTermRgbToPixel(FFrameBg));
  st := CurrentStyle;
  st.Background := Default(TTyFill);
  st.Background.Kind := tfkSolid;
  st.Background.Color := TyRGB((FFrameBg shr 16) and $FF, (FFrameBg shr 8) and $FF, FFrameBg and $FF);
  Include(st.Present, tpBackground);
  P := TTyPainter.Create;
  try
    { 画布给 nil:EndPaint 不往任何画布上贴(贴由 RenderTo 末尾的 DrawPart 做) }
    P.BeginPaintOn(nil, Rect(0, 0, FSurface.Width, FSurface.Height), APPI, FSurface);
    DrawFrame(P, Rect(0, 0, FSurface.Width, FSurface.Height), st);
    P.EndPaint;
  finally
    P.Free;
  end;
  FFrameDirty := False;
  FAllDirty := True;
end;

procedure TTyTerminalView.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  w, h, r, cursorRow, cursorCol: Integer;
  buf: TTyTerminalBuffer;
  ins, clip, part: TRect;
  shape: TTyTermCursorShape;
  sig: Cardinal;
  ime: TRect;
begin
  FInRender := True;
  try
    EnsureThemeCurrent;
    if EnsureMetrics(APPI) then
      RequestRelayout;
    w := ARect.Right - ARect.Left;
    h := ARect.Bottom - ARect.Top;
    if (w <= 0) or (h <= 0) then Exit;
    if (FSurface = nil) or (FSurface.Width <> w) or (FSurface.Height <> h) then
    begin
      FreeAndNil(FSurface);
      FSurface := TBGRABitmap.Create(w, h);
      FFrameDirty := True;
    end;
    sig := ColorSignature;
    if sig <> FColorSig then
    begin
      FColorSig := sig;
      FFrameDirty := True;
    end;
    if FCore.ResolveColor(257) <> FFrameBg then
    begin
      FFrameBg := FCore.ResolveColor(257);
      FFrameDirty := True;
    end;
    if FFrameDirty then
      PaintFrame(APPI);
    { 行绘制器的这一帧参数 }
    FRowPainter.Metrics := FMetrics;
    FRowPainter.Spec := FSpec;
    FRowPainter.Resolver := @FCore.ResolveColor;
    FRowPainter.GlyphCache := FGlyphCache;
    FRowPainter.Rasterizer := FRasterizer;
    FRowPainter.DrawBoldBright := FDrawBoldBright;
    FRowPainter.CursorColor := FCore.ResolveColor(258);
    FRowPainter.CursorInk := FCursorInkRgb;
    FRowPainter.CursorWidthPx := Max(1, MulDiv(FSpec.CursorWidthLogical, APPI, 96));
    ins := ContentInsets(APPI);
    buf := FCore.Buffer;
    { 光标:显示、视口在底部、闪烁相位为显示 }
    cursorRow := -1;
    if FCore.Modes.ShowCursor and (buf.YDisp = buf.YBase) and FBlinkVisible then
      cursorRow := buf.Y;
    shape := CursorShapeNow;
    if Length(FDirty) <> FCore.Rows then
    begin
      SetLength(FDirty, FCore.Rows);
      FAllDirty := True;
    end;
    for r := 0 to FCore.Rows - 1 do
    begin
      if not (FAllDirty or FDirty[r]) then Continue;
      FDirty[r] := False;
      if ins.Top + r * FMetrics.CellH >= h then Continue;
      if r = cursorRow then
        cursorCol := Min(buf.X, FCore.Cols - 1)
      else
        cursorCol := -1;
      FRowPainter.PaintRow(FSurface, ins.Left, ins.Top + r * FMetrics.CellH, buf.GetLine(buf.YDisp + r),
        FCore.Cols, cursorCol, shape);
      if (r = cursorRow) and FInPreedit and (FPreedit <> '') then
        PaintPreedit(APPI);
    end;
    FAllDirty := False;
    FPaintedCursorRow := cursorRow;
    { 输入法的候选窗:锚在光标格(Edit.pas / Memo.pas 同一做法) }
    { 用这一帧的度量(RenderTo 的 PPI 可以不是 Font.PixelsPerInch,别经 CellRect 把度量换回去) }
    ime := GridCellRect(Min(buf.X, FCore.Cols - 1), buf.Y, ins);
    if not EqualRect(ime, FImeCaretRect) then
    begin
      FImeCaretRect := ime;
      TyImeUpdateCaret;
      if FHasFocus and HandleAllocated then
        TySetImeCaretPos(Self, ime.Left, ime.Top);
    end;
    { 只贴画布的裁剪区 }
    if ACanvas <> nil then
    begin
      clip := ACanvas.ClipRect;
      if IsRectEmpty(clip) then
        clip := ARect;
      if not IntersectRect(part, clip, ARect) then
        Exit;
      FSurface.DrawPart(Rect(part.Left - ARect.Left, part.Top - ARect.Top,
        part.Right - ARect.Left, part.Bottom - ARect.Top), ACanvas, part.Left, part.Top, True);
    end;
  finally
    FInRender := False;
  end;
end;

procedure TTyTerminalView.PaintPreedit(APPI: Integer);
var
  st: TTyStyleSet;
  bg, fg, line: Cardinal;
  x, y, cells, w: Integer;
  ins: TRect;
  key: TTyTermGlyphKey;
  glyph: TTyTermGlyph;
begin
  { macOS 的组字串:从光标格起画在光标行上,不进缓冲、不动光标 }
  st := ActiveController.Model.ResolveStyle('TyTerminalPreedit', '', []);
  bg := FCore.ResolveColor(257);
  fg := FCore.ResolveColor(256);
  line := FCore.ResolveColor(256);
  if (tpBackground in st.Present) and (st.Background.Kind = tfkSolid) then bg := Cardinal(st.Background.Color) and $FFFFFF;
  if tpTextColor in st.Present then fg := Cardinal(st.TextColor) and $FFFFFF;
  if tpBorderColor in st.Present then line := Cardinal(st.BorderColor) and $FFFFFF;
  ins := ContentInsets(APPI);
  x := ins.Left + Min(FCore.Buffer.X, FCore.Cols - 1) * FMetrics.CellW;
  y := ins.Top + FCore.Buffer.Y * FMetrics.CellH;
  cells := TyUnicodeStringCellWidth(FPreedit, UnicodeVersion, AmbiguousWide);
  cells := Max(1, Min(cells, FCore.Cols - Min(FCore.Buffer.X, FCore.Cols - 1)));
  w := cells * FMetrics.CellW;
  FSurface.FillRect(x, y, x + w, y + FMetrics.CellH, TyTermRgbToPixel(bg), dmSet);
  key := Default(TTyTermGlyphKey);
  key.Text := FPreedit;
  key.Cells := cells;
  glyph := FGlyphCache.Find(key);
  if glyph = nil then
  begin
    glyph := FRasterizer.Rasterize(key, FSpec, FMetrics);
    FGlyphCache.Add(key, glyph);
  end;
  TyTermBlendMask(FSurface, x + glyph.OffsetX, y + glyph.OffsetY, glyph.Mask, fg, Rect(x, y, x + w, y + FMetrics.CellH));
  FSurface.FillRect(x, y + FMetrics.CellH - FMetrics.LineW, x + w, y + FMetrics.CellH, TyTermRgbToPixel(line), dmSet);
  FSurface.InvalidateBitmap;
end;

procedure TTyTerminalView.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

{ ---- 焦点、闪烁、同步输出 -------------------------------------------------------------- }

procedure TTyTerminalView.DoEnter;
begin
  inherited DoEnter;
  FHasFocus := True;
  FCore.ReportFocus(True);
  TyImeSetFocus(FImeHook, True);
  NoteActivity;
  DirtyCursorRows;
end;

procedure TTyTerminalView.DoExit;
begin
  inherited DoExit;
  FHasFocus := False;
  FCore.ReportFocus(False);
  TyImeSetFocus(FImeHook, False);
  FBlinkVisible := True;
  UpdateBlinkTimer;
  DirtyCursorRows;
end;

function TTyTerminalView.NowMs: Double;
begin
  if Assigned(FCore.Clock) then
    Result := FCore.Clock()
  else
    Result := TyTermDefaultClock;
end;

function TTyTerminalView.EffectiveBlink: Boolean;
begin
  case FCore.Modes.BlinkRequest of
    tbrOn: Result := True;
    tbrOff: Result := False;
  else
    Result := FCore.CursorBlink;
  end;
end;

procedure TTyTerminalView.UpdateBlinkTimer;
var
  want: Boolean;
begin
  want := EffectiveBlink and FHasFocus and not (csDesigning in ComponentState)
    and (NowMs - FLastActivityMs < BlinkRestMs);
  if want then
  begin
    if FBlinkTimer = nil then
    begin
      FBlinkTimer := TTimer.Create(nil);
      FBlinkTimer.Enabled := False;
      FBlinkTimer.Interval := BlinkIntervalMs;
      FBlinkTimer.OnTimer := @BlinkTimerFired;
    end;
    if not FBlinkTimer.Enabled then FBlinkTimer.Enabled := True;
  end
  else
  begin
    if FBlinkTimer <> nil then FBlinkTimer.Enabled := False;
    if not FBlinkVisible then
    begin
      FBlinkVisible := True;
      DirtyCursorRows;
    end;
  end;
end;

procedure TTyTerminalView.BlinkTimerFired(Sender: TObject);
begin
  BlinkTick(NowMs);
end;

procedure TTyTerminalView.BlinkTick(ANowMs: Double);
begin
  if ANowMs - FLastActivityMs >= BlinkRestMs then
  begin
    { 放着不动 5 分钟:停在「显示」,计时器停 }
    FBlinkVisible := True;
    if FBlinkTimer <> nil then FBlinkTimer.Enabled := False;
  end
  else
    FBlinkVisible := not FBlinkVisible;
  DirtyCursorRows;
end;

procedure TTyTerminalView.NoteActivity;
begin
  FLastActivityMs := NowMs;
  if not FBlinkVisible then
  begin
    FBlinkVisible := True;
    DirtyCursorRows;
  end;
  UpdateBlinkTimer;
end;

procedure TTyTerminalView.SyncTimerFired(Sender: TObject);
begin
  if FSyncTimer <> nil then FSyncTimer.Enabled := False;
  { 清模式、RefreshAll -> 回到上一条正常重画(Core 自己做) }
  FCore.EndSynchronizedOutput;
end;

{ ---- 滚动条 ------------------------------------------------------------------------- }

procedure TTyTerminalView.UpdateScrollBar(APPI: Integer);
begin
  if csDesigning in ComponentState then Exit;
  if FScrollBar = nil then
  begin
    { 照 Memo.pas 的竖条逐项抄 }
    FScrollBar := TTyScrollBar.Create(Self);
    FScrollBar.Parent := Self;
    FScrollBar.Kind := sbVertical;
    FScrollBar.Align := alRight;
    FScrollBar.TabStop := False;
    FScrollBar.OnChange := @ScrollBarChange;
    FScrollBar.AnimationsEnabled := False;
    FScrollBar.AutoHide := FScrollBarAutoHide;
    FScrollBar.ControlStyle := FScrollBar.ControlStyle + [csNoDesignVisible];
  end;
  FScrollBar.Width := ScrollBarWidth(APPI);
  FScrollBar.Controller := Self.Controller;
  SyncScrollBar;
end;

procedure TTyTerminalView.SyncScrollBar;
var
  buf: TTyTerminalBuffer;
begin
  if FScrollBar = nil then Exit;
  buf := FCore.Buffer;
  FSyncingScroll := True;
  try
    { Max 是**最大位置**(行数 − 视口行数),不是内容高 }
    FScrollBar.Min := 0;
    FScrollBar.Max := buf.YBase;
    FScrollBar.PageSize := FCore.Rows;
    FScrollBar.Position := buf.YDisp;
    { 备用屏、Scrollback = 0 都没有滚回:禁用,不藏(列数不变) }
    FScrollBar.Enabled := buf.HasScrollback;
  finally
    FSyncingScroll := False;
  end;
end;

procedure TTyTerminalView.ScrollBarChange(Sender: TObject);
begin
  if FSyncingScroll then Exit;
  FCore.ScrollLines(FScrollBar.Position - FCore.Buffer.YDisp);
end;

function TTyTerminalView.ScrollBarFrameStyle: TTyStyleSet;
begin
  Result := CurrentStyle;
end;

function TTyTerminalView.EmbedsScrollBar(ABar: TTyScrollBar): Boolean;
begin
  Result := (ABar <> nil) and (ABar = FScrollBar);
end;

procedure TTyTerminalView.NoteHostHover(AHovered: Boolean);
begin
  if FScrollBar <> nil then FScrollBar.SetHostHovered(AHovered);
end;

procedure TTyTerminalView.MouseEnter;
begin
  inherited MouseEnter;
  NoteHostHover(True);
end;

procedure TTyTerminalView.MouseLeave;
begin
  inherited MouseLeave;
  NoteHostHover(False);
end;

procedure TTyTerminalView.SetScrollBarAutoHide(AValue: TTyScrollBarAutoHide);
begin
  if FScrollBarAutoHide = AValue then Exit;
  FScrollBarAutoHide := AValue;
  if FScrollBar <> nil then FScrollBar.AutoHide := AValue;
end;

{ ---- 公开方法 ----------------------------------------------------------------------- }

procedure TTyTerminalView.Write(const AData: RawByteString; AOnDone: TTyTerminalWriteDone; ATag: PtrInt);
begin
  FCore.Write(AData, AOnDone, ATag);
end;

procedure TTyTerminalView.Write(const ABuf; ACount: Integer; AOnDone: TTyTerminalWriteDone; ATag: PtrInt);
begin
  FCore.Write(ABuf, ACount, AOnDone, ATag);
end;

procedure TTyTerminalView.WriteSync(const AData: RawByteString);
begin
  FCore.WriteSync(AData);
end;

procedure TTyTerminalView.Paste(const AText: string);
begin
  if AText = '' then Exit;
  FCore.Input(TyTerminalPrepareTextForPaste(AText, FCore.Modes.BracketedPaste), True);
  NoteActivity;
end;

procedure TTyTerminalView.Input(const AText: string);
begin
  if AText = '' then Exit;
  FCore.Input(AText, True);
  NoteActivity;
end;

procedure TTyTerminalView.Clear;
begin
  FCore.ClearScrollback;
end;

procedure TTyTerminalView.Reset;
begin
  FCore.Reset;
  DirtyAll;
  FFrameDirty := True;
end;

procedure TTyTerminalView.ScrollLines(ADelta: Integer);
begin
  FCore.ScrollLines(ADelta);
end;

procedure TTyTerminalView.ScrollPages(APages: Integer);
begin
  FCore.ScrollPages(APages);
end;

procedure TTyTerminalView.ScrollToTop;
begin
  FCore.ScrollToTop;
end;

procedure TTyTerminalView.ScrollToBottom;
begin
  FCore.ScrollToBottom;
end;

function TTyTerminalView.ReadClipboardText: string;
begin
  Result := Clipboard.AsText;
end;

procedure TTyTerminalView.WriteClipboardText(const S: string);
begin
  Clipboard.AsText := S;
end;

procedure TTyTerminalView.PasteFromClipboard;
begin
  Paste(ReadClipboardText);
end;

procedure TTyTerminalView.CopyToClipboard;
begin
  { 选区在 4 期:本期没有选区,什么都不做 }
end;

{ ---- 属性 --------------------------------------------------------------------------- }

function TTyTerminalView.GetCols: Integer;
begin
  Result := FCore.Cols;
end;

function TTyTerminalView.GetRows: Integer;
begin
  Result := FCore.Rows;
end;

function TTyTerminalView.GetTitle: string;
begin
  Result := FCore.Title;
end;

function TTyTerminalView.GetScrollback: Integer;
begin
  Result := FCore.Scrollback;
end;

procedure TTyTerminalView.SetScrollback(AValue: Integer);
begin
  if AValue < 0 then AValue := 0;
  FCore.Scrollback := AValue;
  SyncScrollBar;
end;

function TTyTerminalView.GetCursorStyle: TTyTerminalCursorStyle;
begin
  case FCore.CursorStyle of
    tcoUnderline: Result := tcsUnderline;
    tcoBar: Result := tcsBar;
  else
    Result := tcsBlock;
  end;
end;

procedure TTyTerminalView.SetCursorStyle(AValue: TTyTerminalCursorStyle);
begin
  case AValue of
    tcsUnderline: FCore.CursorStyle := tcoUnderline;
    tcsBar: FCore.CursorStyle := tcoBar;
  else
    FCore.CursorStyle := tcoBlock;
  end;
  DirtyCursorRows;
end;

procedure TTyTerminalView.SetCursorInactiveStyle(AValue: TTyTerminalCursorInactiveStyle);
begin
  if FCursorInactiveStyle = AValue then Exit;
  FCursorInactiveStyle := AValue;
  DirtyCursorRows;
end;

function TTyTerminalView.GetCursorBlink: Boolean;
begin
  Result := FCore.CursorBlink;
end;

procedure TTyTerminalView.SetCursorBlink(AValue: Boolean);
begin
  FCore.CursorBlink := AValue;
  UpdateBlinkTimer;
end;

function TTyTerminalView.GetAmbiguousWide: Boolean;
begin
  Result := FCore.AmbiguousWide;
end;

procedure TTyTerminalView.SetAmbiguousWide(AValue: Boolean);
begin
  if FCore.AmbiguousWide = AValue then Exit;
  FCore.AmbiguousWide := AValue;
  FGlyphCache.Clear;
  DirtyAll;
end;

function TTyTerminalView.GetUnicodeVersion: TTyUnicodeVersion;
begin
  Result := FCore.UnicodeVersion;
end;

procedure TTyTerminalView.SetUnicodeVersion(AValue: TTyUnicodeVersion);
begin
  if FCore.UnicodeVersion = AValue then Exit;
  FCore.UnicodeVersion := AValue;
  FGlyphCache.Clear;
  DirtyAll;
end;

procedure TTyTerminalView.SetDrawBoldBright(AValue: Boolean);
begin
  if FDrawBoldBright = AValue then Exit;
  FDrawBoldBright := AValue;
  DirtyAll;
end;

function TTyTerminalView.GetReadOnly: Boolean;
begin
  Result := FCore.ReadOnly;
end;

procedure TTyTerminalView.SetReadOnly(AValue: Boolean);
begin
  FCore.ReadOnly := AValue;
end;

function TTyTerminalView.GetConvertEol: Boolean;
begin
  Result := FCore.ConvertEol;
end;

procedure TTyTerminalView.SetConvertEol(AValue: Boolean);
begin
  FCore.ConvertEol := AValue;
end;

function TTyTerminalView.GetTabStopWidth: Integer;
begin
  Result := FCore.TabStopWidth;
end;

procedure TTyTerminalView.SetTabStopWidth(AValue: Integer);
begin
  if AValue < 1 then AValue := 1;
  FCore.TabStopWidth := AValue;
end;

function TTyTerminalView.GetScrollOnUserInput: Boolean;
begin
  Result := FCore.ScrollOnUserInput;
end;

procedure TTyTerminalView.SetScrollOnUserInput(AValue: Boolean);
begin
  FCore.ScrollOnUserInput := AValue;
end;

procedure TTyTerminalView.SetLineHeightPercent(AValue: Integer);
begin
  { 上游 lineHeight < 1 抛异常;这里钳到 100..300 }
  AValue := EnsureRange(AValue, 100, 300);
  if FLineHeightPercent = AValue then Exit;
  FLineHeightPercent := AValue;
  RequestRelayout;
  DirtyAll;
end;

procedure TTyTerminalView.SetLetterSpacing(AValue: Integer);
begin
  AValue := EnsureRange(AValue, -10, 50);
  if FLetterSpacing = AValue then Exit;
  FLetterSpacing := AValue;
  RequestRelayout;
  DirtyAll;
end;

{ ---- 输入法 ------------------------------------------------------------------------- }

function TTyTerminalView.ImeTargetControl: TWinControl;
begin
  Result := Self;
end;

function TTyTerminalView.ImeIsReadOnly: Boolean;
begin
  Result := ReadOnly;
end;

function TTyTerminalView.ImeCaretBoundClient: TRect;
begin
  if FHasFocus then
    Result := CellRect(Min(FCore.Buffer.X, FCore.Cols - 1), FCore.Buffer.Y)
  else
    Result := Rect(0, 0, 0, 0);
end;

function TTyTerminalView.ImeCaretIndex: Integer;
begin
  Result := 0;
end;

procedure TTyTerminalView.ImeSessionBegin;
begin
  FPreedit := '';
  FInPreedit := True;
end;

procedure TTyTerminalView.ImeSessionEnd;
begin
  if FPreedit <> '' then
  begin
    FCore.Input(FPreedit, True);
    NoteActivity;
  end;
  FPreedit := '';
  FInPreedit := False;
  DirtyCursorRows;
end;

procedure TTyTerminalView.ImeReplace(AStart, ALen: Integer; const AText: string);
var
  n: Integer;
begin
  { 按码位下标,越界钳住 }
  n := UTF8Length(FPreedit);
  AStart := EnsureRange(AStart, 0, n);
  ALen := EnsureRange(ALen, 0, n - AStart);
  FPreedit := UTF8Copy(FPreedit, 1, AStart) + AText + UTF8Copy(FPreedit, AStart + ALen + 1, MaxInt);
  DirtyCursorRows;
end;

{ ---- FOR THE TESTS ------------------------------------------------------------------ }

function TTyTerminalView.RowsPainted: Integer;
begin
  Result := FRowPainter.RowsPainted;
end;

function TTyTerminalView.GlyphCache: TTyTermGlyphCache;
begin
  Result := FGlyphCache;
end;

function TTyTerminalView.Metrics: TTyTermCellMetrics;
begin
  Result := FMetrics;
end;

function TTyTerminalView.FontSpec: TTyTermFontSpec;
begin
  Result := FSpec;
end;

function TTyTerminalView.SurfaceBitmap: TBGRABitmap;
begin
  Result := FSurface;
end;

function TTyTerminalView.BlinkTimerActive: Boolean;
begin
  Result := (FBlinkTimer <> nil) and FBlinkTimer.Enabled;
end;

function TTyTerminalView.SyncTimerActive: Boolean;
begin
  Result := (FSyncTimer <> nil) and FSyncTimer.Enabled;
end;

function TTyTerminalView.PendingSyncRows: TPoint;
begin
  if FSyncHolding then
    Result := Point(FSyncFirst, FSyncLast)
  else
    Result := Point(-1, -1);
end;

function TTyTerminalView.HasFocusFlag: Boolean;
begin
  Result := FHasFocus;
end;

end.
