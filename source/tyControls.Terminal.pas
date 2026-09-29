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
    OnQueryBaseColor、OnProcessRequest、OnWindowOptionsReport、OnResize、
    OnScrollbackCleared、OnUserInput。宿主可以自己挂的是 OnIconNameChange、OnLineFeed、
    OnRequestScrollToBottom(只是通知:Core 自己滚到底),或者 Core.Parser.Register*Handler。
  - 解析一次(AsyncSlice、WriteSync、Write)里 Core 可能滚几千次、改几次色:这期间滚动只记
    「整屏脏」「滚动条待同步」,颜色签名不看;解析返回后(EndDrive)统一失效、同步一次,
    签名变了(OSC 4 / 10 / 11 / 104 …)整窗失效——内边距也是 257 号色。
  - 帧率:距上次绘制不到一帧(16 ms)就接着跑下一片,不让出给 WM_PAINT;一帧里光栅化新
    字形有时间预算,没画完的行留脏、下一帧整行重画。
  - 焦点跟 LM_SETFOCUS / LM_KILLFOCUS(切到别的程序也算失焦),DoEnter / DoExit 也照报,
    两路幂等。
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
    RenderTo 开头再比一次兜底(无头测试直接调 RenderTo)。
  - 选区照上游记坐标(缓冲行),不记标记:输出把行挤出头部时按缓冲的 TrimmedLines 差值
    整体上移(SyncSelectionTrim),解析返回后、绘制前、每个鼠标入口都追一次。清选区的时机
    同上游:用户输入、行数变了、换缓冲(含 RIS / Reset)、程序打开鼠标上报;另加清滚回。 }

interface

uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType, LCLIntf, LMessages, LazUTF8, Forms,
  ExtCtrls, Clipbrd, Menus, tyControls.Menu, tyControls.StrConsts,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.StyleModel,
  tyControls.Controller, tyControls.ScrollBar, tyControls.PlatformWS, tyControls.TextMenu,
  tyControls.Unicode.Width, tyControls.Terminal.Buffer, tyControls.Terminal.Core,
  tyControls.Terminal.Keyboard, tyControls.Terminal.Render, tyControls.Terminal.Selection,
  tyControls.Terminal.Links, tyControls.Terminal.Parser;

const
  { X11 惯例的 PRIMARY(选中即复制、中键粘贴):Unix 上除了 macOS。按平台取,不按 widgetset;
    控件的 FUsesPrimary 从它来,测试可以改 }
  TyTerminalUsesPrimary = {$IF DEFINED(UNIX) AND NOT DEFINED(DARWIN)}True{$ELSE}False{$ENDIF};

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
  { 按住哪个键时,程序接管了鼠标也照样本地选择:默认 macOS 是 Option(Alt)、其余 Shift }
  TTyTerminalSelectionOverrideKey = (tsoDefault, tsoShift, tsoAlt, tsoNone);
  { 一次按下走哪条路(在按下那一刻定,直到那个键抬起):上报给程序、本地选择、链接、
    中键粘贴 PRIMARY、什么都不做 }
  TTyTerminalMouseRoute = (mrNone, mrReport, mrSelect, mrLink, mrPrimary);
  { 链接被 Ctrl+单击(macOS Cmd+单击):AUri 原样(OSC 8 的 URI,或识别出的网址);控件自己
    不打开任何东西 }
  TTyTerminalLinkEvent = procedure(Sender: TObject; const AUri: string; AFromOsc8: Boolean) of object;
  { OSC 52 剪贴板:关(默认,全丢)、程序可以写、程序可以写也可以读(读要宿主同意) }
  TTyTerminalOsc52Policy = (to52Off, to52Write, to52ReadWrite);
  { 程序要写(AWrite)或读剪贴板。ASelection 是程序给的 Pc 原样(控件不按它选剪贴板)。写:
    AText 是解出来的文字,宿主可以改,AAllow 默认 True;读:AText 是剪贴板现在的内容,宿主可以
    改,AAllow 默认 False(宿主不说行就不给)。同步发,在解析中间:宿主可以在这里弹模态框 }
  TTyTerminalOsc52Event = procedure(Sender: TObject; AWrite: Boolean; const ASelection: string;
    var AText: string; var AAllow: Boolean) of object;

  { 终端。右键菜单是自建的四项(不实现 ITyTextEditActions:那是给编辑框六项菜单设计的)。 }
  TTyTerminalView = class(TTyCustomControl, ITyImeEditable, ITyScrollBarFrameHost)
  private
    FCore: TTyTerminalCore;
    FGlyphCache: TTyTermGlyphCache;
    FRasterizer: TTyTermGlyphRasterizer;
    FRowPainter: TTyTermRowPainter;
    FSurface: TBGRABitmap;
    { 画到的大小(客户区);位图本身按块向上取整,拖动改尺寸时不每次重建 }
    FSurfaceW, FSurfaceH: Integer;
    FFrameDirty, FAllDirty: Boolean;
    FDirty: array of Boolean;
    { 上一次画外框时的外框样式签名(含状态:悬停、按下、聚焦) }
    FFrameSig: Cardinal;
    FFrameSigValid: Boolean;
    FColorSig: Cardinal;
    { 这一帧的 259 色快照:行绘制器每格要问两三次颜色,经 Core 问一次要走覆盖表和色表的
      键比较,一屏几万次;画之前抄一份,画的时候查数组。禁用时已经按 :disabled 的 opacity
      预混(FrameColor 读的就是它) }
    FFrameColors: array[0..258] of Cardinal;
    FRawColors: array[0..258] of Cardinal;
    FCursorInkFrame: Cardinal;
    { 预混的键(原色签名 + Enabled + 主题版本)与结果的 alpha、混向的底色 }
    FPremixSig: Cardinal;
    FPremixValid: Boolean;
    FPremixAlpha: Integer;
    FPremixBase: Cardinal;
    { 解析过程中(AsyncSlice / WriteSync / Write)只记,返回后统一做 }
    FDriveDepth: Integer;
    FScrollPending, FBarPending: Boolean;
    FDrivenColorSig: Cardinal;
    FDrivenColorSigValid: Boolean;
    { 帧率上限与光栅化预算 }
    FLastPaintMs: Double;
    FRasterBudgetMs: Double;
    FRepaintQueued: Boolean;
    { 内边距 + 边框:按 (模型, 版本, 类, 覆盖, PPI, 状态) 缓存 }
    FInsets: TRect;
    FInsetsModel: TObject;
    FInsetsVersion: Cardinal;
    FInsetsClass, FInsetsOverride: string;
    FInsetsPPI: Integer;
    FInsetsStates: TTyStateSet;
    FInsetsValid: Boolean;
    { 度量:规格记录与它的键(便宜的字符串,先比键,变了才解析规格) }
    FSpec: TTyTermFontSpec;
    FSpecKey: string;
    FSpecValid: Boolean;
    FMetrics: TTyTermCellMetrics;
    { 色表:259 项 + 光标墨色,键 = (模型, ThemeVersion, StyleClass, StyleOverride) }
    FPalette: array[0..258] of Cardinal;
    FCursorInkRgb: Cardinal;
    { 同一个键下取的选区色(失焦 / 聚焦,带 alpha)、选区前景(主题写了才有)、链接色 }
    FSelBg: array[Boolean] of TTyColor;
    FSelInk: array[Boolean] of Cardinal;
    FSelHasInk: array[Boolean] of Boolean;
    FLinkRgb: Cardinal;
    FPaletteModel: TObject;
    FPaletteVersion: Cardinal;
    FPaletteClass, FPaletteOverride: string;
    FPaletteValid: Boolean;
    { 已经通知过 Core 的那张色表(第一次建色表不通知;主题变了但色表没变——改内边距、
      改字体——也不通知)与主题键 }
    FNotifiedPalette: array[0..258] of Cardinal;
    FNotifiedModel: TObject;
    FNotifiedVersion: Cardinal;
    FNotifiedClass, FNotifiedOverride: string;
    FNotifiedValid: Boolean;
    FNotifyQueued: Boolean;
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
    FBarSyncs, FControlInvalidates: Integer;
    FHasFocus: Boolean;
    FStateChange: Boolean;
    FGridAnnounced: Boolean;
    FRelayoutQueued: Boolean;
    FRelayingOut, FRelayoutAgain: Boolean;
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
    FHorzAccum: Integer;
    { 鼠标:这次按下定的路、开路的键、上报期间按着的键、右键是上报了还是本地的 }
    FRoute: TTyTerminalMouseRoute;
    FRouteButton: TMouseButton;
    FReportHeld: set of TMouseButton;
    FRightReported, FRightLocal: Boolean;
    FSelectionOverrideKey: TTyTerminalSelectionOverrideKey;
    FLastMousePos: TPoint;
    { 选区:上游 SelectionService 的非 DOM 部分;缓冲的 TrimmedLines 读数;上次画到的视口
      行段(失效用);多击;拖出边界的自动滚 }
    FSelection: TTyTermSelection;
    FSelTrimBase: Int64;
    FSelRows: Integer;
    FLastProtocol: TTyTerminalMouseProtocol;
    FSelDrawnFirst, FSelDrawnLast: Integer;
    FLastClickX, FLastClickY, FClickCount: Integer;
    FLastClickTick: QWord;
    FDragTimer: TTimer;
    FCopyOnSelect: Boolean;
    FWordSeparators: string;
    FOnSelectionChange: TNotifyEvent;
    { 链接:识别网址、非 http(s) 的 OSC 8 算不算链接;悬停的那条(按着链接键时)、按下时的
      那条、指针在不在控件里、上次悬停用的修饰键 }
    FDetectUrls, FAllowNonHttpLinks: Boolean;
    FOnLinkActivate: TTyTerminalLinkEvent;
    FHoverLink, FDownLink: TTyTermLink;
    FHoverValid: Boolean;
    FHoverShift: TShiftState;
    FMouseInside: Boolean;
    { OSC 52 }
    FOsc52: TTyTerminalOsc52Policy;
    FOnOsc52: TTyTerminalOsc52Event;
    { 右键菜单:自建四项,懒建,无 owner(析构里释放) }
    FMenu: TTyPopupMenu;
    FMenuCopy, FMenuPaste, FMenuSelectAll, FMenuClear: TMenuItem;
    { 输入法 }
    FImeHook: TObject;
    FImeCaretRect: TRect;
    FImeCaretValid: Boolean;
    FPreedit: string;
    FInPreedit: Boolean;
    { macOS:LM_IM_COMPOSITION 答它(TTyCocoaImeHandler),构造时就建,Cocoa 在建句柄时问 }
    FCocoaIme: TObject;
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
    procedure CoreProcessRequest(Sender: TObject);
    procedure CoreWindowReport(Sender: TObject; AKind: TTyTermWindowReport);
    procedure CoreResize(Sender: TObject; ACols, ARows: Integer);
    procedure CoreScrollbackCleared(Sender: TObject);
    procedure CoreUserInput(Sender: TObject);
    { 调度 }
    procedure AsyncRelayout(Data: PtrInt);
    procedure AsyncRepaint(Data: PtrInt);
    procedure AsyncNotifyScheme(Data: PtrInt);
    procedure BeginDrive;
    procedure EndDrive;
    procedure MaskUnencodedExtensions;
    { 主题、字体、网格 }
    function InstanceStyle(const ATypeKey: string): TTyStyleSet;
    function EnsurePalette: Boolean;
    procedure EnsureThemeCurrent;
    function FrameSignature: Cardinal;
    procedure SetHasFocus(AValue: Boolean);
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
    procedure HoldRows(AFirst, ALast: Integer);
    procedure DirtyRows(AFirst, ALast: Integer);
    procedure DirtyAll;
    procedure DirtyCursorRows;
    function CursorViewRow: Integer;
    function CursorShapeNow: TTyTermCursorShape;
    function ColorSignature: Cardinal;
    procedure PremixFrameColors(ARawSig: Cardinal);
    function FrameColor(AIndex: Integer): Cardinal;
    procedure PaintFrame(APPI: Integer);
    procedure BlitSurface(ACanvas: TCanvas; const APart: TRect; ADstX, ADstY: Integer);
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
    { 鼠标上报 }
    function Reporting: Boolean;
    function MakeMouseEvent(AButton: TTyTerminalMouseButton; AAction: TTyTerminalMouseAction;
      X, Y: Integer; Shift: TShiftState): TTyTerminalMouseEvent;
    procedure ReportMouse(AButton: TTyTerminalMouseButton; AAction: TTyTerminalMouseAction;
      X, Y: Integer; Shift: TShiftState);
    function OverrideIsAlt: Boolean;
    procedure UpdatePointer(Shift: TShiftState);
    { 选区 }
    procedure SelectionChanged(Sender: TObject);
    procedure SelectionRedraw(Sender: TObject);
    function SelectionViewRows(out AFirst, ALast: Integer): Boolean;
    function SelPointAt(X, Y: Integer): TTyTermSelPoint;
    procedure SelectionPress(Shift: TShiftState; X, Y: Integer);
    procedure SelectionDrag(X, Y: Integer);
    procedure SelectionRelease;
    procedure StartDragTimer;
    procedure StopDragTimer;
    procedure DragTimerFired(Sender: TObject);
    function GetSelectionText: string;
    function GetHasSelection: Boolean;
    procedure SetWordSeparators(const AValue: string);
    function WordSeparatorsStored: Boolean;
    { 链接 }
    function LinkKeyHeld(Shift: TShiftState): Boolean;
    procedure DirtyLinkRows(const ALink: TTyTermLink);
    procedure SetDetectUrls(AValue: Boolean);
    procedure SetAllowNonHttpLinks(AValue: Boolean);
    { OSC 52 的处理器(注册在 Core 的解析器上);一律答「处理了」,不进 OnOsc }
    function HandleOsc52(const AData: string): Boolean;
    { 右键菜单 }
    procedure MenuCopyClick(Sender: TObject);
    procedure MenuPasteClick(Sender: TObject);
    procedure MenuSelectAllClick(Sender: TObject);
    procedure MenuClearClick(Sender: TObject);
  protected
    { 平台标志:按平台(不是 widgetset)取;受保护,测试可以改成别的平台 }
    FIsMac, FIsWindows: Boolean;
    { 用不用 X11 的 PRIMARY(TyTerminalUsesPrimary);测试可以改 }
    FUsesPrimary: Boolean;
    function ReadPrimaryText: string; virtual;
    procedure WritePrimaryText(const S: string); virtual;
    { 选区追上被挤出头部的行(缓冲 TrimmedLines 的差值) }
    procedure SyncSelectionTrim;
    { 一次选择结束(松开、双击、三击、Shift 扩展、全选):选区非空就写 PRIMARY 与
      (CopyOnSelect 时)剪贴板 }
    procedure FinishSelection;
    { 自动滚计时器的回调转到这里;测试直接调 }
    procedure DragScrollTick;
    { 右键菜单:宿主的 OnContextPopup 先拿;程序拿了这次右键(上报了)就没有菜单;宿主设了
      PopupMenu 就由 LCL 弹宿主的;菜单键 (-1, -1) 弹在光标格左下角 }
    procedure DoContextPopup(MousePos: TPoint; var Handled: Boolean); override;
    { 建菜单(第一次)、按此刻的状态设 Enabled }
    procedure UpdateContextMenu;
    { 弹出(测试的缝:覆盖它就不真弹) }
    procedure ShowContextMenu(const AClientPos: TPoint); virtual;
    { 此刻按着的修饰键(菜单先于按下到时现算);默认 GetKeyShiftState }
    function CurrentShiftState: TShiftState; virtual;
    { 指针下(视口行 AViewRow、列 ACol)的链接:OSC 8 在前、DetectUrls 才认网址、去重叠后
      第一条命中的 }
    function LinkAt(ACol, AViewRow: Integer; out ALink: TTyTermLink): Boolean;
    { 悬停:指针在网格里、按着链接键、不在拖选 -> 指针下的链接,变了就重画涉及的行 }
    procedure UpdateHover(X, Y: Integer; Shift: TShiftState);
    { FOR THE TESTS:悬停的链接 }
    property HoverLink: TTyTermLink read FHoverLink;
    property HoverValid: Boolean read FHoverValid;
    { FOR THE TESTS }
    function DragTimerActive: Boolean;
    property Selection: TTyTermSelection read FSelection;
    property ContextMenu: TTyPopupMenu read FMenu;
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
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    procedure KeyUp(var Key: Word; Shift: TShiftState); override;
    procedure ModifierChanged(AKey: Word; Shift: TShiftState);
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    function DoMouseWheelHorz(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    { 覆盖键按着没有(SelectionOverrideKey;tsoDefault 在 macOS 是 Alt、其余 Shift) }
    function OverrideHeld(Shift: TShiftState): Boolean;
    { 要列选择:Alt 按着,且 Alt 不是覆盖键(macOS 默认、tsoAlt 时 Alt 让给覆盖键) }
    function ColumnWanted(Shift: TShiftState): Boolean;
    { FOR THE TESTS:这次按下走的路 }
    property Route: TTyTerminalMouseRoute read FRoute;
    procedure UTF8KeyPress(var UTF8Key: TUTF8Char); override;
    procedure FontChanged(Sender: TObject); override;
    procedure CMParentFontChanged(var Message: TLMessage); message CM_PARENTFONTCHANGED;
    procedure CMEnabledChanged(var Message: TLMessage); message CM_ENABLEDCHANGED;
    procedure WMSetFocus(var Message: TLMSetFocus); message LM_SETFOCUS;
    procedure WMKillFocus(var Message: TLMKillFocus); message LM_KILLFOCUS;
    {$IFDEF LCLCocoa}
    procedure CocoaImComposition(var Message: TLMessage); message LM_IM_COMPOSITION;
    {$ENDIF}
    { 输入法提交的整段文字:当作键入发给程序 }
    procedure HandleImeCommit(const ACommitUtf8: string);
    { 输入法候选窗的锚:上一帧画在光标所在格子上的矩形(宽字符不扩,候选窗只要一个锚点;
      视口不在底部时仍按光标所在的屏幕行算——候选窗跟光标,不跟视口)。没聚焦、没句柄、
      还没画过一帧:空矩形 }
    function GetImeCaretRect: TRect;
    procedure InitializeWnd; override;
    procedure DestroyWnd; override;
    { 调度的缝:默认 Application.QueueAsyncCall(设计期不排片) }
    procedure ScheduleSlice; virtual;
    { 排好的一片:跑到队列空、或者离上次绘制满一帧(16 ms)为止 }
    procedure AsyncSlice(Data: PtrInt);
    { 失效几行(视口行):有句柄时 InvalidateRect 那几行的并集。子类覆盖必须调 inherited。 }
    procedure InvalidateRows(AFirst, ALast: Integer); virtual;
    { 失效整个客户区(外框、内边距、每一行)。子类覆盖必须调 inherited。 }
    procedure InvalidateAll; virtual;
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
    function ScrollBarSyncs: Integer;
    { whole-control invalidations that went through (Invalidate that did not return early) }
    function ControlInvalidations: Integer;
    { 一帧里光栅化新字形的时间预算(ms,<= 0 不限);默认 10 }
    property RasterBudgetMs: Double read FRasterBudgetMs write FRasterBudgetMs;
    { 上一次贴到画布的时刻(Core 的时钟) }
    property LastPaintMs: Double read FLastPaintMs write FLastPaintMs;
    { rows still to paint (a frame that ran out of its rasterizing budget leaves some) }
    function RowsLeftToPaint: Boolean;
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
    { 有选区才写剪贴板(行间 LineEnding,见 SelectionText) }
    procedure CopyToClipboard;
    procedure SelectAll;
    procedure ClearSelection;
    { = 上游 setSelection:从 (ACol, 缓冲行 AAbsRow) 起 ALength 格 }
    procedure Select(ACol, AAbsRow, ALength: Integer);
    { 缓冲行 AFirst..ALast 整行(越界钳住) }
    procedure SelectLines(AFirst, ALast: Integer);
    { 选中的文字:行尾空白去掉、折行接成一行、行间 LineEnding(Windows 上 CRLF,上游同样)、
      NBSP 换成空格 }
    property SelectionText: string read GetSelectionText;
    property HasSelection: Boolean read GetHasSelection;
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
    property SelectionOverrideKey: TTyTerminalSelectionOverrideKey read FSelectionOverrideKey
      write FSelectionOverrideKey default tsoDefault;
    property WordSeparators: string read FWordSeparators write SetWordSeparators stored WordSeparatorsStored;
    property CopyOnSelect: Boolean read FCopyOnSelect write FCopyOnSelect default False;
    property DetectUrls: Boolean read FDetectUrls write SetDetectUrls default True;
    { OSC 8 里不是 http / https 的 URI(file://、ssh://)算不算链接:默认不算(上游没有
      linkHandler.allowNonHttpProtocols 时同样不算——不下划线、不能点) }
    property AllowNonHttpLinks: Boolean read FAllowNonHttpLinks write SetAllowNonHttpLinks default False;
    property Osc52: TTyTerminalOsc52Policy read FOsc52 write FOsc52 default to52Off;
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
    property OnSelectionChange: TNotifyEvent read FOnSelectionChange write FOnSelectionChange;
    property OnLinkActivate: TTyTerminalLinkEvent read FOnLinkActivate write FOnLinkActivate;
    property OnOsc52: TTyTerminalOsc52Event read FOnOsc52 write FOnOsc52;
  end;

{ MouseService._sendEvent 的键(MouseService.ts:112-136):按下、抬起按 LCL 的键(左、中、右,
  其余答 tmbNone,不报);移动按 Shift 里按着的键,左先于中、中先于右,都没按答 tmbNone。 }
function TyTerminalMouseButtonFor(AAction: TTyTerminalMouseAction; AButton: TMouseButton;
  AShift: TShiftState): TTyTerminalMouseButton;

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

{$IFDEF LCLCocoa}
uses
  tyControls.CocoaWS;
{$ENDIF}

{$IFDEF LCLWin32}
{ gdi32 的 StretchDIBits 与它要的位图头,自己声明:implementation 里 uses Windows 会让
  RECT 类型遮住 Types.Rect 函数 }
type
  TTyDibHeader = packed record
    biSize: LongWord;
    biWidth, biHeight: LongInt;
    biPlanes, biBitCount: Word;
    biCompression, biSizeImage: LongWord;
    biXPelsPerMeter, biYPelsPerMeter: LongInt;
    biClrUsed, biClrImportant: LongWord;
  end;

function TyStretchDIBits(ADC: HDC; AXDest, AYDest, ADestW, ADestH, AXSrc, AYSrc, ASrcW, ASrcH: LongInt;
  ABits: Pointer; const AInfo: TTyDibHeader; AUsage, ARop: LongWord): LongInt; stdcall;
  external 'gdi32' name 'StretchDIBits';
{$ENDIF}

const
  { token 缺失时的兜底;真值都在主题里(§11)。0..15 缺失时退到 Tango(TyTermDefaultPaletteColor) }
  FallbackFg = $000000;
  FallbackBg = $FFFFFF;
  BlinkIntervalMs = 600;
  BlinkRestMs = 300000;          { 5 分钟不活动就停在「显示」 }
  SyncTimeoutMs = 1000;          { RenderService.ts:359-363 }
  FrameMs = 16;                  { 一帧:离上次绘制不到这么久,接着跑下一片 }
  SurfaceBlock = 64;             { 表面位图按这么大的块向上取整 }
  DefaultRasterBudgetMs = 10;

{ ---- 构造与析构 --------------------------------------------------------------------- }

constructor TTyTerminalView.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  ControlStyle := ControlStyle + [csOpaque, csDoubleClicks, csTripleClicks];
  { 整个客户区都由表面位图贴上去(csOpaque),局部重画只贴那几行:LCL 的双缓冲再垫一张
    整窗位图只是多拷一遍 }
  DoubleBuffered := False;
  TabStop := True;
  FRasterBudgetMs := DefaultRasterBudgetMs;
  FPremixAlpha := 255;
  FCursorInactiveStyle := tcisOutline;
  FAlternateScroll := True;
  FDrawBoldBright := True;
  FScrollBarAutoHide := sbahDefault;
  FLineHeightPercent := 100;
  FLetterSpacing := 0;
  FIsMac := TyTerminalIsMac;
  FIsWindows := TyTerminalIsWindows;
  { 中键、右键拖出控件也要收到移动(上报期间);LCL 默认只捕获左键 }
  CaptureMouseButtons := [mbLeft, mbMiddle, mbRight];
  FSelectionOverrideKey := tsoDefault;
  FUsesPrimary := TyTerminalUsesPrimary;
  FWordSeparators := TyTermDefaultWordSeparators;
  FDetectUrls := True;
  FAllowNonHttpLinks := False;
  FOsc52 := to52Off;
  FSelDrawnFirst := -1;
  FSelDrawnLast := -1;
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
  FCore.OnProcessRequest := @CoreProcessRequest;
  FCore.OnWindowOptionsReport := @CoreWindowReport;
  FCore.OnResize := @CoreResize;
  FCore.OnScrollbackCleared := @CoreScrollbackCleared;
  FCore.OnUserInput := @CoreUserInput;
  FSelection := TTyTermSelection.Create(FCore.BufferService);
  FSelection.WordSeparators := UTF8Decode(FWordSeparators);
  FSelection.OnChange := @SelectionChanged;
  FSelection.OnRedraw := @SelectionRedraw;
  FSelTrimBase := FCore.Buffer.TrimmedLines;
  FSelRows := FCore.Rows;
  { OSC 52:同 Core 自己的处理器,交给解析器(它释放);Reset 不清解析器的处理器 }
  FCore.Parser.RegisterOscHandler(52, TTyTerminalOscStringHandler.Create(@HandleOsc52));
  MaskUnencodedExtensions;
  { Core 出生时 Focused = True(2 期交接):新控件还没焦点,马上告诉它 }
  FCore.ReportFocus(False);
  SetLength(FDirty, FCore.Rows);
  FAllDirty := True;
  FFrameDirty := True;
  {$IFDEF LCLCocoa}
  { 句柄建之前就要在:LCL-Cocoa 在 CreateHandle 里发 LM_IM_COMPOSITION(Edit.pas 同一做法);
    handler 以 COM 字段持有 Self,_AddRef 是空操作,没有环 }
  FCocoaIme := TTyCocoaImeHandler.Create(Self);
  {$ENDIF}
  SetInitialBounds(0, 0, 480, 300);
end;

destructor TTyTerminalView.Destroy;
begin
  { 地雷 8 的顺序:排着的异步调用 -> 计时器 -> 输入法 -> Core 的事件 -> 选区 -> Core 和缓存 }
  Application.RemoveAsyncCalls(Self);
  FreeAndNil(FBlinkTimer);
  FreeAndNil(FSyncTimer);
  FreeAndNil(FDragTimer);
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
    FCore.OnProcessRequest := nil;
    FCore.OnWindowOptionsReport := nil;
    FCore.OnResize := nil;
    FCore.OnScrollbackCleared := nil;
    FCore.OnUserInput := nil;
  end;
  if FSelection <> nil then
  begin
    FSelection.OnChange := nil;
    FSelection.OnRedraw := nil;
  end;
  FreeAndNil(FSelection);
  FreeAndNil(FMenu);
  FreeAndNil(FCore);
  FreeAndNil(FRowPainter);
  FreeAndNil(FGlyphCache);
  FreeAndNil(FRasterizer);
  FreeAndNil(FSurface);
  FreeAndNil(FCocoaIme);
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
  { 同步输出开着:DirtyRows 攒起来,不失效(见 HoldRows);关着:连同攒着的一起画 }
  DirtyRows(AFirst, ALast);
  if not FCore.Modes.SynchronizedOutput then
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
  { 一次解析里可能滚几千次:只记下来,EndDrive 统一做一次 }
  if FDriveDepth > 0 then
  begin
    FScrollPending := True;
    FBarPending := True;
    Exit;
  end;
  DirtyAll;
  SyncScrollBar;
end;

procedure TTyTerminalView.CoreBufferActivate(Sender: TObject);
begin
  { 换缓冲(含 RIS、Reset:新的一对缓冲)清选区,读数换成新缓冲的(SelectionService.ts:778-785) }
  ClearSelection;
  FSelTrimBase := FCore.Buffer.TrimmedLines;
  DirtyAll;
  SyncScrollBar;
end;

procedure TTyTerminalView.CoreModesChange(Sender: TObject);
var
  p: TTyTerminalMouseProtocol;
begin
  { DECSCUSR、DECTCEM:光标行重画;程序要不要闪烁也在这里变 }
  DirtyCursorRows;
  UpdateBlinkTimer;
  { 程序打开鼠标上报:上游 _syncMouseModeState -> SelectionService.disable() 清选区
    (MouseService.ts:380-393) }
  p := FCore.Modes.MouseProtocol;
  if (FLastProtocol = tmpNone) and (p <> tmpNone) then
    ClearSelection;
  FLastProtocol := p;
end;

procedure TTyTerminalView.CoreQueryColor(Sender: TObject; AIndex: Integer; out ARgb: Cardinal);
begin
  EnsurePalette;
  if (AIndex >= 0) and (AIndex <= 258) then
    ARgb := FPalette[AIndex]
  else
    ARgb := 0;
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
  { 行数变了清选区,列数变不清(SelectionService.ts:158-162) }
  if ARows <> FSelRows then
  begin
    FSelRows := ARows;
    ClearSelection;
  end;
  SetLength(FDirty, ARows);
  FAllDirty := True;
  FFrameDirty := True;
  FGridAnnounced := True;
  if Assigned(FOnGridResize) then FOnGridResize(Self, ACols, ARows);
  SyncScrollBar;
  InvalidateAll;
end;

procedure TTyTerminalView.CoreScrollbackCleared(Sender: TObject);
begin
  { 清滚回也清选区:上游 clear() 不清(CoreBrowserTerminal.ts:1075-1089),选区会指着别的行,
    这是我们加的(spec §15) }
  if FSelection.HasSelection then
    ClearSelection;
  if FDriveDepth > 0 then
    FBarPending := True
  else
    SyncScrollBar;
end;

{ 用户输入清选区(SelectionService.ts:139-143);ReadOnly 时 Core 不发 }
procedure TTyTerminalView.CoreUserInput(Sender: TObject);
begin
  if FSelection.HasSelection then
    ClearSelection;
end;

{ ---- 调度 --------------------------------------------------------------------------- }

procedure TTyTerminalView.ScheduleSlice;
begin
  if csDesigning in ComponentState then Exit;
  Application.QueueAsyncCall(@AsyncSlice, 0);
end;

procedure TTyTerminalView.AsyncSlice(Data: PtrInt);
var
  more: Boolean;
begin
  MaskUnencodedExtensions;
  BeginDrive;
  try
    { 帧率上限:离上次绘制还不到一帧,消息循环这时让出去也画不了新的一帧——接着跑片;
      满一帧了才让出(已经提交的 WM_PAINT 先处理) }
    repeat
      more := FCore.ProcessPending;
    until (not more) or (NowMs - FLastPaintMs >= FrameMs);
  finally
    EndDrive;
  end;
  if more then
    ScheduleSlice;
end;

procedure TTyTerminalView.BeginDrive;
begin
  Inc(FDriveDepth);
  if FDriveDepth = 1 then
  begin
    { 这次解析前的颜色签名:返回后比,变了就整窗重画 }
    FDrivenColorSig := ColorSignature;
    FDrivenColorSigValid := True;
  end;
end;

procedure TTyTerminalView.EndDrive;
begin
  Dec(FDriveDepth);
  if FDriveDepth > 0 then Exit;
  if FScrollPending then
  begin
    FScrollPending := False;
    DirtyAll;
  end;
  if FBarPending then
  begin
    FBarPending := False;
    SyncScrollBar;
  end;
  SyncSelectionTrim;
  { OSC 4 / 10 / 11 / 12 / 104 … 改了色:上游 onChangeColors -> _fullRefresh
    (RenderService.ts:120);257 号色还是内边距的底色,所以整窗 }
  if FDrivenColorSigValid and (ColorSignature <> FDrivenColorSig) then
  begin
    FFrameDirty := True;
    DirtyAll;
    InvalidateAll;
  end;
  FDrivenColorSigValid := False;
  { 输出改了悬停链接所在的行、或者滚了:在上次的指针位置重算(Linkifier.ts:299-321) }
  if FHoverValid then
    UpdateHover(FLastMousePos.X, FLastMousePos.Y, FHoverShift);
end;

{ Kitty 键盘协议、win32-input-mode 控件都不编码:程序查询时不能报支持(宿主改了 Core 的
  VtExtensions 也一样,每次解析前再屏蔽一次) }
procedure TTyTerminalView.MaskUnencodedExtensions;
begin
  if FCore.VtExtensions * [tveKittyKeyboard, tveWin32InputMode] <> [] then
    FCore.VtExtensions := FCore.VtExtensions - [tveKittyKeyboard, tveWin32InputMode];
end;

procedure TTyTerminalView.AsyncRepaint(Data: PtrInt);
var
  r: Integer;
begin
  { 上一帧光栅化超了预算留下的行:再失效一次,下一帧补画 }
  FRepaintQueued := False;
  if csDestroying in ComponentState then Exit;
  for r := 0 to High(FDirty) do
    if FDirty[r] then
      InvalidateRows(r, r);
end;

procedure TTyTerminalView.AsyncNotifyScheme(Data: PtrInt);
begin
  FNotifyQueued := False;
  if csDestroying in ComponentState then Exit;
  EnsureThemeCurrent;
end;

procedure TTyTerminalView.AsyncRelayout(Data: PtrInt);
begin
  FRelayoutQueued := False;
  if csDestroying in ComponentState then Exit;
  UpdateGrid;
end;

procedure TTyTerminalView.RequestRelayout;
begin
  { UpdateGrid 自己也问度量:排版中途不重入,这一趟完了再来一趟 }
  if FRelayingOut then
  begin
    FRelayoutAgain := True;
    Exit;
  end;
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

function TermFgOf(const S: TTyStyleSet; AFallback: Cardinal): Cardinal;
begin
  if tpTextColor in S.Present then
    Result := Cardinal(S.TextColor) and $FFFFFF
  else
    Result := AFallback;
end;

function TermBgOf(const S: TTyStyleSet; AFallback: Cardinal): Cardinal;
begin
  if (tpBackground in S.Present) and (S.Background.Kind = tfkSolid) then
    Result := Cardinal(S.Background.Color) and $FFFFFF
  else
    Result := AFallback;
end;

{ 本实例的**无状态**样式:类型键 + 本实例的类,TyTerminal 再叠 StyleOverride(覆盖是写给
  TyTerminal 这一个键的)。色表不跟悬停、聚焦、禁用走——禁用在画的时候预混
  (PremixFrameColors);色表本身是程序查询(OSC 4 / 10 / 11)答的那一份。 }
function TTyTerminalView.InstanceStyle(const ATypeKey: string): TTyStyleSet;
begin
  Result := ActiveController.Model.ResolveStyle(ATypeKey, TyStyleClassFor(Self, StyleClass), []);
  if (StyleOverride <> '') and SameText(ATypeKey, GetStyleTypeKey) then
    TyMergeStyleSet(Result, OverrideStyle);
end;

function TTyTerminalView.EnsurePalette: Boolean;
var
  model: TTyStyleModel;
  cls, ground, raw, ansiKey: string;
  st, bare, cur, bareCur: TTyStyleSet;
  i: Integer;
  instFg, instBg, themeFg, themeBg, c: Cardinal;
  inFocus: Boolean;
begin
  model := ActiveController.Model;
  cls := TyStyleClassFor(Self, StyleClass);
  if FPaletteValid and (FPaletteModel = model) and (FPaletteVersion = model.ThemeVersion)
    and (FPaletteClass = cls) and (FPaletteOverride = StyleOverride) then
    Exit(False);
  { 256 / 257:本实例的前景 / 底色;主题自己的(不带类、不带覆盖)用来看实例换没换底 }
  st := InstanceStyle(GetStyleTypeKey);
  instFg := TermFgOf(st, FallbackFg);
  instBg := TermBgOf(st, FallbackBg);
  bare := model.ResolveStyle(GetStyleTypeKey, '', []);
  themeFg := TermFgOf(bare, FallbackFg);
  themeBg := TermBgOf(bare, FallbackBg);
  FPalette[256] := instFg;
  FPalette[257] := instBg;
  { 选区:无状态是失焦那一色、:focus 是聚焦那一色(TyTerminalSelection,alpha 保留);前景
    只在主题给了 color 时才换(spec §11「写了才用」:基础层不写,17 个主题都不写——
    tpTextColor 在 Present 里就是规则写了) }
  for inFocus := False to True do
  begin
    if inFocus then
      st := model.ResolveStyle('TyTerminalSelection', cls, [tysFocused])
    else
      st := model.ResolveStyle('TyTerminalSelection', cls, []);
    if (tpBackground in st.Present) and (st.Background.Kind = tfkSolid) then
      FSelBg[inFocus] := st.Background.Color
    else
      FSelBg[inFocus] := TTyColor(($5A shl 24) or instFg);
    FSelHasInk[inFocus] := tpTextColor in st.Present;
    FSelInk[inFocus] := TermFgOf(st, instFg);
  end;
  FLinkRgb := TermFgOf(model.ResolveStyle('TyTerminalLink', cls, []), instFg);
  { 0..15 取实例的类;16..255 公式;颜色一律 RGB、丢 alpha;缺了退到 Tango,不抛 }
  ground := Format('#%.6x', [instBg]);
  for i := 0 to 15 do
  begin
    ansiKey := 'TyTerminalAnsi' + IntToStr(i);
    c := TermFgOf(model.ResolveStyle(ansiKey, cls, []), TyTermDefaultPaletteColor(i));
    if instBg <> themeBg then
    begin
      { 这个实例换了底(类或 StyleOverride 改了 background):16 色的 token 是
        on(var(--terminal-bg), 浅底用, 深底用),拿本实例的底色再求一次,深底就换成深底那套。
        只在这一色确实来自 token 时这么做:类没有另写它,主题的规则就是 token 的值。 }
      raw := Trim(model.RawVar('--terminal-ansi-' + IntToStr(i)));
      if (raw <> '') and (Pos('var(--terminal-bg)', LowerCase(raw)) > 0)
        and (TermFgOf(model.ResolveStyle(ansiKey, '', []), $1000000) = c)
        and (TermFgOf(model.ResolveOverride('color: ' + raw), $1000000) = c) then
        c := TermFgOf(model.ResolveOverride('color: '
          + StringReplace(raw, 'var(--terminal-bg)', ground, [rfReplaceAll, rfIgnoreCase])), c);
    end;
    FPalette[i] := c;
  end;
  for i := 16 to 255 do
    FPalette[i] := TyTermDefaultPaletteColor(i);
  { 258 光标色、光标下的字色:默认就是前景、底色(--terminal-cursor / -ink);实例换了前景 /
    底色而类没有另写光标时跟着换,否则深底实例上的光标还是浅底那一色 }
  cur := model.ResolveStyle('TyTerminalCursor', cls, []);
  bareCur := model.ResolveStyle('TyTerminalCursor', '', []);
  FPalette[258] := TermBgOf(cur, instFg);
  FCursorInkRgb := TermFgOf(cur, instBg);
  if (instFg <> themeFg) and (FPalette[258] = themeFg) and (TermBgOf(bareCur, $1000000) = themeFg) then
    FPalette[258] := instFg;
  if (instBg <> themeBg) and (FCursorInkRgb = themeBg) and (TermFgOf(bareCur, $1000000) = themeBg) then
    FCursorInkRgb := instBg;
  FPaletteModel := model;
  FPaletteVersion := model.ThemeVersion;
  FPaletteClass := cls;
  FPaletteOverride := StyleOverride;
  FPaletteValid := True;
  Result := True;
end;

procedure TTyTerminalView.EnsureThemeCurrent;
var
  i: Integer;
  differs: Boolean;
begin
  EnsurePalette;
  if FNotifiedValid and (FNotifiedModel = FPaletteModel) and (FNotifiedVersion = FPaletteVersion)
    and (FNotifiedClass = FPaletteClass) and (FNotifiedOverride = FPaletteOverride) then
    Exit;
  { 主题变了:外框和每一行重画、度量的键失效、内边距重取。只有色表真变了(换明暗、换配色)
    才告诉 Core——它清 OSC 覆盖色、2031 开着就报明暗;改内边距、改字体不算。第一次建
    色表不算「换」。在绘制里不当场通知(通知会发 OnData):记下来,消息循环里再做。 }
  differs := False;
  if FNotifiedValid then
    for i := 0 to 258 do
      if FPalette[i] <> FNotifiedPalette[i] then
      begin
        differs := True;
        Break;
      end;
  if differs and FInRender then
  begin
    if not FNotifyQueued then
    begin
      FNotifyQueued := True;
      Application.QueueAsyncCall(@AsyncNotifyScheme, 0);
    end;
    { 键先不记:AsyncNotifyScheme 回来还要比出「变了」 }
    FFrameDirty := True;
    FAllDirty := True;
    FSpecKey := '';
    FInsetsValid := False;
    Exit;
  end;
  if differs then
    FCore.NotifyColorSchemeChanged;
  for i := 0 to 258 do
    FNotifiedPalette[i] := FPalette[i];
  FNotifiedModel := FPaletteModel;
  FNotifiedVersion := FPaletteVersion;
  FNotifiedClass := FPaletteClass;
  FNotifiedOverride := FPaletteOverride;
  FNotifiedValid := True;
  FFrameDirty := True;
  FAllDirty := True;
  FSpecKey := '';
  FInsetsValid := False;
end;

{ 外框看得见的那几项(含状态:悬停、按下、聚焦时主题可能另写边框、底色、透明度) }
function TTyTerminalView.FrameSignature: Cardinal;
var
  st: TTyStyleSet;
  h: Cardinal;
  p: TTyProp;

  procedure Mix(AValue: Cardinal);
  begin
    h := (h xor AValue) * 16777619;
  end;

begin
  st := CurrentStyle;
  h := 2166136261;
  for p := Low(TTyProp) to High(TTyProp) do
    if p in st.Present then Mix(Ord(p) + 1);
  Mix(Cardinal(st.Background.Color));
  Mix(Ord(st.Background.Kind));
  Mix(Cardinal(st.BorderColor));
  Mix(Cardinal(st.BorderWidth));
  Mix(Ord(st.BorderStyle));
  Mix(Ord(st.RenderStyle));
  Mix(Cardinal(st.BorderRadius));
  Mix(Cardinal(st.Radius.TL) xor (Cardinal(st.Radius.TR) shl 8)
    xor (Cardinal(st.Radius.BR) shl 16) xor (Cardinal(st.Radius.BL) shl 24));
  Mix(Cardinal(st.Padding.Left) xor (Cardinal(st.Padding.Top) shl 8)
    xor (Cardinal(st.Padding.Right) shl 16) xor (Cardinal(st.Padding.Bottom) shl 24));
  if tpOpacity in st.Present then Mix(Cardinal(Round(st.Opacity * 1000)));
  Mix(Cardinal(st.ShadowColor));
  Mix(Cardinal(st.ShadowBlur));
  Mix(Cardinal(st.OutlineColor));
  Mix(Cardinal(st.OutlineWidth));
  Mix(Cardinal(st.OutlineOffset));
  Mix(Ord(Enabled));
  Result := h;
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
    { 基类在悬停、按下、聚焦时整控件失效:终端的外框大多不随这些状态变,重贴整张表面
      白花一次整窗贴图。外框样式真变了才重画外框(连同各行,外框的底铺在网格下面)。 }
    if FStateChange and FFrameSigValid and not FFrameDirty then
    begin
      if FrameSignature = FFrameSig then Exit;
      FFrameDirty := True;
    end;
  end;
  Inc(FControlInvalidates);
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
  fname, wide: string;
  size: Integer;
begin
  { 顺序(开工前问题二第 6 条):StyleOverride > 显式 Font > TyTerminal 规则 > token > monospace。
    font-family 不走 var()(StyleModel 不求值它),token 由这里 RawVar 读。 }
  model := ActiveController.Model;
  ovr := OverrideStyle;
  st := CurrentStyle;
  if (tpFontName in ovr.Present) and (ovr.FontName <> '') then
    fname := ovr.FontName
  else if (not ParentFont) and (Font.Name <> '') and not SameText(Font.Name, 'default') then
    fname := Font.Name
  else if (tpFontName in st.Present) and (st.FontName <> '') then
    fname := st.FontName
  else
    fname := Trim(model.RawVar('--terminal-font-family'));
  if (fname = '') or SameText(fname, 'monospace') then
    fname := PlatformMonospace;
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
  Result.MainName := fname;
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
  { 谁问出来的度量变了(CellRect、CellAt、SizeForGrid、14t 应答……),网格都跟着重排:
    不能让一次查询把「格子变了」这个信号吃掉。在绘制里经 QueueAsyncCall 延后。 }
  RequestRelayout;
end;

function TTyTerminalView.ContentInsets(APPI: Integer): TRect;
var
  st: TTyStyleSet;
  b: Integer;
  model: TTyStyleModel;
  states: TTyStateSet;
begin
  { 每行失效、每次查询都要:按主题键缓存(状态也在键里,:focus 可以另写内边距) }
  model := ActiveController.Model;
  states := CurrentStates;
  if FInsetsValid and (FInsetsModel = model) and (FInsetsVersion = model.ThemeVersion)
    and (FInsetsPPI = APPI) and (FInsetsStates = states) and (FInsetsClass = StyleClass)
    and (FInsetsOverride = StyleOverride) then
    Exit(FInsets);
  st := CurrentStyle;
  b := 0;
  if TyBorderVisible(st) then b := st.BorderWidth;
  Result := Rect(MulDiv(st.Padding.Left + b, APPI, 96), MulDiv(st.Padding.Top + b, APPI, 96),
    MulDiv(st.Padding.Right + b, APPI, 96), MulDiv(st.Padding.Bottom + b, APPI, 96));
  FInsets := Result;
  FInsetsModel := model;
  FInsetsVersion := model.ThemeVersion;
  FInsetsPPI := APPI;
  FInsetsStates := states;
  FInsetsClass := StyleClass;
  FInsetsOverride := StyleOverride;
  FInsetsValid := True;
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
  ppi, nc, nr, barW, passes: Integer;
  ins: TRect;
begin
  if (FCore = nil) or (Parent = nil) then Exit;
  if [csLoading, csDestroying] * ComponentState <> [] then Exit;
  if FRelayingOut then
  begin
    { 排版里又要排(宿主在 OnGridResize 里改了尺寸):这一趟完了再来一趟 }
    FRelayoutAgain := True;
    Exit;
  end;
  FRelayingOut := True;
  passes := 0;
  try
   repeat
    FRelayoutAgain := False;
    Inc(passes);
    ppi := Font.PixelsPerInch;
    EnsureThemeCurrent;
    EnsureMetrics(ppi);
    ins := ContentInsets(ppi);
    barW := ScrollBarWidth(ppi);
    UpdateScrollBar(ppi);
    { 条宽恒扣(地雷 6);设计期也扣,设计器和运行时同一网格 }
    nc := Max(TyTermMinimumCols, (ClientWidth - ins.Left - ins.Right - barW) div FMetrics.CellW);
    nr := Max(TyTermMinimumRows, (ClientHeight - ins.Top - ins.Bottom) div FMetrics.CellH);
    if (nc <> FCore.Cols) or (nr <> FCore.Rows) then
      { OnResize 回来做其余的事(地雷 7:在 Core 的事件里调会被延后,以 OnResize 为准) }
      FCore.Resize(nc, nr)
    else if not FGridAnnounced then
    begin
      { 加载完成后的第一次排版,尺寸没变也发一次(spec §9.2) }
      FGridAnnounced := True;
      if Assigned(FOnGridResize) then FOnGridResize(Self, nc, nr);
    end;
    WriteDesignPreview;
   until (not FRelayoutAgain) or (passes >= 3);
  finally
    FRelayingOut := False;
  end;
end;

procedure TTyTerminalView.FontChanged(Sender: TObject);
begin
  inherited FontChanged(Sender);
  { 字号、字体一改就重排,不等下一次有人来问度量 }
  if (FCore <> nil) and ([csLoading, csDestroying] * ComponentState = []) then
    RequestRelayout;
end;

procedure TTyTerminalView.CMParentFontChanged(var Message: TLMessage);
begin
  inherited;
  if (FCore <> nil) and ([csLoading, csDestroying] * ComponentState = []) then
    RequestRelayout;
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

procedure TTyTerminalView.InvalidateAll;
begin
  if HandleAllocated then
    LCLIntf.InvalidateRect(Handle, nil, False);
end;

procedure TTyTerminalView.HoldRows(AFirst, ALast: Integer);
begin
  { 同步输出(2026)开着:每一次要重画的行都攒起来——Core 报的脏行、光标行、滚动带来的
    整屏(上游这些全经 RenderService.refreshRows,开着 2026 就进 bufferRows)。计时器从
    **第一次攒行**起算(_timeout ??=),模式打开本身不起表。 }
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
end;

procedure TTyTerminalView.DirtyRows(AFirst, ALast: Integer);
var
  r: Integer;
begin
  if FCore.Modes.SynchronizedOutput then
  begin
    { 只攒视口里的行:视口外的行(用户上翻了一屏多)不算「攒到了」,不起表 }
    AFirst := Max(AFirst, 0);
    ALast := Min(ALast, FCore.Rows - 1);
    if ALast >= AFirst then
      HoldRows(AFirst, ALast);
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
  if AFirst < 0 then AFirst := 0;
  if ALast > High(FDirty) then ALast := High(FDirty);
  if ALast < AFirst then Exit;
  for r := AFirst to ALast do
    FDirty[r] := True;
  InvalidateRows(AFirst, ALast);
end;

procedure TTyTerminalView.DirtyAll;
begin
  if FCore.Modes.SynchronizedOutput then
  begin
    HoldRows(0, FCore.Rows - 1);
    Exit;
  end;
  FAllDirty := True;
  DirtyRows(0, FCore.Rows - 1);
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
  { 259 色(覆盖色优先)与光标下的字色的签名;顺手抄进 FRawColors。OSC 4 / 10 / 11 / 12
    改了覆盖色 Core 没有专门的事件,解析返回后比签名(EndDrive) }
  Result := 2166136261;
  for i := 0 to 258 do
  begin
    FRawColors[i] := FCore.ResolveColor(i);
    Result := (Result xor FRawColors[i]) * 16777619;
  end;
  EnsurePalette;
  Result := (Result xor FCursorInkRgb) * 16777619;
end;

function PremixRgb(AColor, ABase: Cardinal; AAlpha: Integer): Cardinal;
begin
  Result := ((((AColor shr 16) and $FF) * Cardinal(AAlpha) + ((ABase shr 16) and $FF) * Cardinal(255 - AAlpha) + 127) div 255) shl 16
    or ((((AColor shr 8) and $FF) * Cardinal(AAlpha) + ((ABase shr 8) and $FF) * Cardinal(255 - AAlpha) + 127) div 255) shl 8
    or (((AColor and $FF) * Cardinal(AAlpha) + (ABase and $FF) * Cardinal(255 - AAlpha) + 127) div 255);
end;

{ 这一帧的色表:原色(FRawColors)禁用时按 TyTerminal:disabled 的 opacity 朝父控件底色预混
  (TyApplyStyleOpacity 同一个方向:变淡而不透出底下的东西)。键 = 原色签名 + Enabled +
  主题版本;键没变就不重算(opacity 和父底色要解析样式、走父链)。 }
procedure TTyTerminalView.PremixFrameColors(ARawSig: Cardinal);
var
  st: TTyStyleSet;
  a, i: Integer;
  base, key: Cardinal;
  pc: TTyColor;
begin
  key := (((ARawSig xor Cardinal(Ord(Enabled))) * 16777619) xor ActiveController.Model.ThemeVersion) * 16777619;
  if FPremixValid and (key = FPremixSig) then Exit;
  a := 255;
  base := 0;
  if not Enabled then
  begin
    st := ActiveController.Model.ResolveStyle(GetStyleTypeKey, TyStyleClassFor(Self, StyleClass), [tysDisabled]);
    if StyleOverride <> '' then TyMergeStyleSet(st, OverrideStyle);
    if tpOpacity in st.Present then a := EnsureRange(Round(st.Opacity * 255), 0, 255);
    if TyResolveParentBg(Self, pc) then
      base := Cardinal(pc) and $FFFFFF
    else
      base := FRawColors[257];
  end;
  for i := 0 to 258 do
    if a < 255 then
      FFrameColors[i] := PremixRgb(FRawColors[i], base, a)
    else
      FFrameColors[i] := FRawColors[i];
  if a < 255 then
    FCursorInkFrame := PremixRgb(FCursorInkRgb, base, a)
  else
    FCursorInkFrame := FCursorInkRgb;
  FPremixAlpha := a;
  FPremixBase := base;
  FPremixSig := key;
  FPremixValid := True;
end;

function TTyTerminalView.FrameColor(AIndex: Integer): Cardinal;
begin
  if (AIndex >= 0) and (AIndex <= 258) then
    Result := FFrameColors[AIndex]
  else
    Result := 0;
end;

{ ---- 绘制 --------------------------------------------------------------------------- }

procedure TTyTerminalView.PaintFrame(APPI: Integer);
var
  P: TTyPainter;
  st: TTyStyleSet;
  bg: Cardinal;

  function Dim(AColor: TTyColor): TTyColor;
  var
    rgb: Cardinal;
  begin
    rgb := PremixRgb(Cardinal(AColor) and $FFFFFF, FPremixBase, FPremixAlpha);
    Result := TTyColor((Cardinal(AColor) and $FF000000) or rgb);
  end;

begin
  { 外框 + 内边距 + 网格外的余量:底色取这一帧的 257(OSC 11 改了底色,内边距也跟着变;
    禁用时已经预混)。外框的其余颜色同样预混,opacity 不再交给画笔(表面上画的外框
    EndPaint 时不经画布,画笔的 opacity 本来就落不下来) }
  bg := FFrameColors[257];
  FSurface.FillRect(0, 0, FSurfaceW, FSurfaceH, TyTermRgbToPixel(bg), dmSet);
  st := CurrentStyle;
  st.Background := Default(TTyFill);
  st.Background.Kind := tfkSolid;
  st.Background.Color := TyRGB((bg shr 16) and $FF, (bg shr 8) and $FF, bg and $FF);
  Include(st.Present, tpBackground);
  Exclude(st.Present, tpOpacity);
  if FPremixAlpha < 255 then
  begin
    st.BorderColor := Dim(st.BorderColor);
    st.OutlineColor := Dim(st.OutlineColor);
    st.ShadowColor := Dim(st.ShadowColor);
  end;
  P := TTyPainter.Create;
  try
    { 画布给 nil:EndPaint 不往任何画布上贴(贴由 RenderTo 末尾做) }
    P.BeginPaintOn(nil, Rect(0, 0, FSurfaceW, FSurfaceH), APPI, FSurface);
    DrawFrame(P, Rect(0, 0, FSurfaceW, FSurfaceH), st);
    P.EndPaint;
  finally
    P.Free;
  end;
  FFrameSig := FrameSignature;
  FFrameSigValid := True;
  FFrameDirty := False;
  FAllDirty := True;
end;

{ 表面位图的 APart(表面坐标)贴到画布的 (ADstX, ADstY):Win32 直接从位图的 DIB 带源偏移
  StretchDIBits,不经 GetPart 复制一份;别的 widgetset 仍走 BGRA 的 DrawPart(零拷贝的
  路子要各平台真机核实,见真机验收) }
procedure TTyTerminalView.BlitSurface(ACanvas: TCanvas; const APart: TRect; ADstX, ADstY: Integer);
{$IFDEF LCLWin32}
const
  BI_RGB = 0;
  DIB_RGB_COLORS = 0;
  SRCCOPY = $00CC0020;
var
  info: TTyDibHeader;
  w, h, ySrc: Integer;
{$ENDIF}
begin
  {$IFDEF LCLWin32}
  w := APart.Right - APart.Left;
  h := APart.Bottom - APart.Top;
  if (w <= 0) or (h <= 0) then Exit;
  FillChar(info, SizeOf(info), 0);
  info.biSize := SizeOf(info);
  info.biWidth := FSurface.Width;
  info.biPlanes := 1;
  info.biBitCount := 32;
  info.biCompression := BI_RGB;
  if FSurface.LineOrder = riloBottomToTop then
  begin
    { 自下而上的 DIB:源矩形的原点在左下角 }
    info.biHeight := FSurface.Height;
    ySrc := FSurface.Height - APart.Bottom;
  end
  else
  begin
    info.biHeight := -FSurface.Height;
    ySrc := APart.Top;
  end;
  TyStretchDIBits(ACanvas.Handle, ADstX, ADstY, w, h, APart.Left, ySrc, w, h,
    FSurface.Data, info, DIB_RGB_COLORS, SRCCOPY);
  {$ELSE}
  FSurface.DrawPart(APart, ACanvas, ADstX, ADstY, True);
  {$ENDIF}
end;

procedure TTyTerminalView.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);

  function Frame(ARgb: Cardinal): Cardinal;
  begin
    { 禁用时朝父控件底色预混(色表同一个方向);选区色的 alpha 不动 }
    if FPremixAlpha < 255 then
      Result := PremixRgb(ARgb, FPremixBase, FPremixAlpha)
    else
      Result := ARgb;
  end;

var
  w, h, r, cursorRow, cursorCol, sa, sb: Integer;
  selRgb: Cardinal;
  buf: TTyTerminalBuffer;
  ins, clip, part: TRect;
  shape: TTyTermCursorShape;
  sig: Cardinal;
  ime: TRect;
  incomplete: Boolean;
begin
  FInRender := True;
  try
    EnsureThemeCurrent;
    EnsureMetrics(APPI);           { 度量变了它自己排队重排 }
    { 追上被挤出头部的行(只动选区的行号,不发宿主事件;脏行这一帧画掉) }
    SyncSelectionTrim;
    w := ARect.Right - ARect.Left;
    h := ARect.Bottom - ARect.Top;
    if (w <= 0) or (h <= 0) then Exit;
    { 表面位图按块向上取整、只长不缩:拖着改尺寸不每次重建 }
    if (FSurface = nil) or (FSurface.Width < w) or (FSurface.Height < h) then
    begin
      FreeAndNil(FSurface);
      FSurface := TBGRABitmap.Create((w + SurfaceBlock - 1) div SurfaceBlock * SurfaceBlock,
        (h + SurfaceBlock - 1) div SurfaceBlock * SurfaceBlock);
      FFrameDirty := True;
    end;
    if (w <> FSurfaceW) or (h <> FSurfaceH) then
    begin
      FSurfaceW := w;
      FSurfaceH := h;
      FFrameDirty := True;
    end;
    sig := ColorSignature;
    PremixFrameColors(sig);
    if FPremixSig <> FColorSig then
    begin
      FColorSig := FPremixSig;
      FFrameDirty := True;
    end;
    if FFrameDirty then
      PaintFrame(APPI);
    { 行绘制器的这一帧参数 }
    FRowPainter.Metrics := FMetrics;
    FRowPainter.Spec := FSpec;
    FRowPainter.Resolver := @FrameColor;
    FRowPainter.GlyphCache := FGlyphCache;
    FRowPainter.Rasterizer := FRasterizer;
    FRowPainter.DrawBoldBright := FDrawBoldBright;
    FRowPainter.CursorColor := FFrameColors[258];
    FRowPainter.CursorInk := FCursorInkFrame;
    FRowPainter.CursorWidthPx := Max(1, MulDiv(FSpec.CursorWidthLogical, APPI, 96));
    FRowPainter.RasterBudgetMs := FRasterBudgetMs;
    FRowPainter.Clock := @NowMs;
    { 选区与链接:聚焦 / 失焦两色,禁用时预混 }
    selRgb := Frame(Cardinal(FSelBg[FHasFocus]) and $FFFFFF);
    FRowPainter.SelColor := BGRA((selRgb shr 16) and $FF, (selRgb shr 8) and $FF, selRgb and $FF,
      TyAlphaOf(FSelBg[FHasFocus]));
    FRowPainter.SelHasInk := FSelHasInk[FHasFocus];
    FRowPainter.SelInk := Frame(FSelInk[FHasFocus]);
    FRowPainter.LinkColor := Frame(FLinkRgb);
    FRowPainter.BeginFrame;
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
    incomplete := False;
    for r := 0 to FCore.Rows - 1 do
    begin
      if not (FAllDirty or FDirty[r]) then Continue;
      FDirty[r] := False;
      if ins.Top + r * FMetrics.CellH >= h then Continue;
      if r = cursorRow then
        cursorCol := Min(buf.X, FCore.Cols - 1)
      else
        cursorCol := -1;
      { 选区按缓冲行(视口滚了它跟着字走) }
      if FSelection.RowSpan(buf.YDisp + r, sa, sb) then
      begin
        FRowPainter.SelFrom := sa;
        FRowPainter.SelTo := sb;
      end
      else
      begin
        FRowPainter.SelFrom := 0;
        FRowPainter.SelTo := 0;
      end;
      { 悬停链接落在这一行上的那一段(1 起、闭区间、缓冲行) }
      FRowPainter.LinkFrom := 0;
      FRowPainter.LinkTo := 0;
      if FHoverValid and (buf.YDisp + r + 1 >= FHoverLink.Range.StartY) and (buf.YDisp + r + 1 <= FHoverLink.Range.EndY) then
      begin
        if buf.YDisp + r + 1 = FHoverLink.Range.StartY then
          FRowPainter.LinkFrom := FHoverLink.Range.StartX - 1;
        if buf.YDisp + r + 1 = FHoverLink.Range.EndY then
          FRowPainter.LinkTo := FHoverLink.Range.EndX
        else
          FRowPainter.LinkTo := FCore.Cols;
      end;
      if not FRowPainter.PaintRow(FSurface, ins.Left, ins.Top + r * FMetrics.CellH, buf.GetLine(buf.YDisp + r),
        FCore.Cols, cursorCol, shape) then
      begin
        { 光栅化超了这一帧的预算:这一行缺字,留脏,下一帧整行重画 }
        FDirty[r] := True;
        incomplete := True;
      end;
      { 组字串画在光标所在的视口行上,不管光标此刻显不显示(闪烁、DECTCEM) }
      if FInPreedit and (FPreedit <> '') and (r = CursorViewRow) then
        PaintPreedit(APPI);
    end;
    FAllDirty := False;
    FPaintedCursorRow := cursorRow;
    SelectionViewRows(FSelDrawnFirst, FSelDrawnLast);
    if incomplete and not FRepaintQueued and not (csDesigning in ComponentState) then
    begin
      FRepaintQueued := True;
      Application.QueueAsyncCall(@AsyncRepaint, 0);
    end;
    { 输入法的候选窗:锚在光标格(Edit.pas / Memo.pas 同一做法),用这一帧的度量(RenderTo 的
      PPI 可以不是 Font.PixelsPerInch,别经 CellRect 把度量换回去)。Win32 每帧都设
      (Memo.pas:4464):系统候选窗的位置按线程记,在别的控件里打过字就被挪走了 }
    ime := GridCellRect(Min(buf.X, FCore.Cols - 1), buf.Y, ins);
    if (not FImeCaretValid) or not EqualRect(ime, FImeCaretRect) then
    begin
      FImeCaretRect := ime;
      FImeCaretValid := True;
      TyImeUpdateCaret;
    end;
    if FHasFocus and HandleAllocated then
      TySetImeCaretPos(Self, ime.Left, ime.Top);
    { 只贴画布的裁剪区 }
    if ACanvas <> nil then
    begin
      FLastPaintMs := NowMs;
      clip := ACanvas.ClipRect;
      if IsRectEmpty(clip) then
        clip := ARect;
      if not IntersectRect(part, clip, ARect) then
        Exit;
      BlitSurface(ACanvas, Rect(part.Left - ARect.Left, part.Top - ARect.Top,
        part.Right - ARect.Left, part.Bottom - ARect.Top), part.Left, part.Top);
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
  bg := FFrameColors[257];
  fg := FFrameColors[256];
  line := FFrameColors[256];
  if (tpBackground in st.Present) and (st.Background.Kind = tfkSolid) then bg := Cardinal(st.Background.Color) and $FFFFFF;
  if tpTextColor in st.Present then fg := Cardinal(st.TextColor) and $FFFFFF;
  if tpBorderColor in st.Present then line := Cardinal(st.BorderColor) and $FFFFFF;
  ins := ContentInsets(APPI);
  x := ins.Left + Min(FCore.Buffer.X, FCore.Cols - 1) * FMetrics.CellW;
  y := ins.Top + CursorViewRow * FMetrics.CellH;
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

{ 焦点的唯一入口:LM_SETFOCUS / LM_KILLFOCUS(窗口真的得到、失去键盘焦点,切到别的程序
  也在内)和 DoEnter / DoExit(窗体内换 ActiveControl)都走这里,重复的一路什么都不做。
  上游看的是 textarea 的 focus / blur,也就是系统焦点。 }
procedure TTyTerminalView.SetHasFocus(AValue: Boolean);
var
  a, b: Integer;
begin
  if FHasFocus = AValue then Exit;
  FHasFocus := AValue;
  FCore.ReportFocus(AValue);
  TyImeSetFocus(FImeHook, AValue);
  if AValue then
  begin
    { 候选窗位置按线程记:别的控件里打过字就挪走了,回来先按缓存的光标格设一次,下一帧
      再按新画的格子设 }
    FImeCaretValid := False;
    if HandleAllocated and FSpecValid then
      TySetImeCaretPos(Self, FImeCaretRect.Left, FImeCaretRect.Top);
    NoteActivity;
  end
  else
  begin
    FBlinkVisible := True;
    UpdateBlinkTimer;
  end;
  DirtyCursorRows;
  { 选区聚焦 / 失焦两色 }
  if SelectionViewRows(a, b) then
    DirtyRows(a, b);
end;

procedure TTyTerminalView.DoEnter;
begin
  FStateChange := True;
  try
    inherited DoEnter;
  finally
    FStateChange := False;
  end;
  SetHasFocus(True);
end;

procedure TTyTerminalView.DoExit;
begin
  FStateChange := True;
  try
    inherited DoExit;
  finally
    FStateChange := False;
  end;
  SetHasFocus(False);
end;

procedure TTyTerminalView.WMSetFocus(var Message: TLMSetFocus);
begin
  inherited;
  if not (csDestroying in ComponentState) then
    SetHasFocus(True);
end;

procedure TTyTerminalView.WMKillFocus(var Message: TLMKillFocus);
begin
  inherited;
  if not (csDestroying in ComponentState) then
    SetHasFocus(False);
end;

procedure TTyTerminalView.CMEnabledChanged(var Message: TLMessage);
begin
  { 禁用 / 启用:色表按 :disabled 的 opacity 预混(键里有 Enabled),外框、每一行都重画 }
  inherited;
  if FCore = nil then Exit;
  FFrameDirty := True;
  DirtyAll;
  InvalidateAll;
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
  Inc(FBarSyncs);
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
  FStateChange := True;
  try
    inherited MouseEnter;
  finally
    FStateChange := False;
  end;
  NoteHostHover(True);
  FMouseInside := True;
end;

procedure TTyTerminalView.MouseLeave;
begin
  FStateChange := True;
  try
    inherited MouseLeave;
  finally
    FStateChange := False;
  end;
  NoteHostHover(False);
  FMouseInside := False;
  { 离开:悬停清掉(按着链接键也一样) }
  UpdateHover(-1, -1, []);
end;

procedure TTyTerminalView.SetScrollBarAutoHide(AValue: TTyScrollBarAutoHide);
begin
  if FScrollBarAutoHide = AValue then Exit;
  FScrollBarAutoHide := AValue;
  if FScrollBar <> nil then FScrollBar.AutoHide := AValue;
end;

{ ---- 公开方法 ----------------------------------------------------------------------- }

{ Write 通常只入队;用户刚键入过时 Core 当场解析(回显延迟),所以也算一次解析 }
procedure TTyTerminalView.Write(const AData: RawByteString; AOnDone: TTyTerminalWriteDone; ATag: PtrInt);
begin
  MaskUnencodedExtensions;
  BeginDrive;
  try
    FCore.Write(AData, AOnDone, ATag);
  finally
    EndDrive;
  end;
end;

procedure TTyTerminalView.Write(const ABuf; ACount: Integer; AOnDone: TTyTerminalWriteDone; ATag: PtrInt);
begin
  MaskUnencodedExtensions;
  BeginDrive;
  try
    FCore.Write(ABuf, ACount, AOnDone, ATag);
  finally
    EndDrive;
  end;
end;

procedure TTyTerminalView.WriteSync(const AData: RawByteString);
begin
  MaskUnencodedExtensions;
  BeginDrive;
  try
    FCore.WriteSync(AData);
  finally
    EndDrive;
  end;
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

function TTyTerminalView.ReadPrimaryText: string;
begin
  Result := PrimarySelection.AsText;
end;

procedure TTyTerminalView.WritePrimaryText(const S: string);
begin
  PrimarySelection.AsText := S;
end;

procedure TTyTerminalView.PasteFromClipboard;
begin
  Paste(ReadClipboardText);
end;

{ ---- 键盘 --------------------------------------------------------------------------- }

{ 能打出字符的键:留给字符事件。KeyDown 里发不得、也清零不得——键盘布局只有 widgetset 知道
  (美式表查出来的 Key 只对美式键盘对),而 Win32 上 KeyDown 清零会吞掉随后的 WM_CHAR。
  上游的对应处:Keyboard.ts:365-368(无修饰、keyCode >= 48、恰一个 UTF-16 单元的键按 ev.key
  发)与 CoreBrowserTerminal.ts:898-903(A-Z 留给 keypress);空格上游 keydown 本来就不发。 }
function KeyWaitsForItsCharacter(const AEvent: TTyTerminalKeyEvent): Boolean;
begin
  Result := not AEvent.Ctrl and not AEvent.Alt and not AEvent.Meta
    and (((AEvent.KeyCode >= 48) and (TyTermJsLength(AEvent.Key) = 1)) or (AEvent.KeyCode = VK_SPACE));
end;

{ 修饰键按下 / 抬起:链接悬停与指针形状跟着变(指针没动也一样)。不改变按键的去向 }
procedure TTyTerminalView.ModifierChanged(AKey: Word; Shift: TShiftState);
begin
  if (AKey = VK_CONTROL) or (AKey = VK_SHIFT) or (AKey = VK_MENU) or (AKey = VK_LWIN) or (AKey = VK_RWIN) then
  begin
    UpdateHover(FLastMousePos.X, FLastMousePos.Y, Shift);
    if FMouseInside then
      UpdatePointer(Shift);
  end;
end;

procedure TTyTerminalView.KeyDown(var Key: Word; Shift: TShiftState);
type
  TKeyAction = (kaNone, kaSend, kaCopy, kaPaste, kaPageUp, kaPageDown, kaTop, kaBottom, kaSelectAll);
var
  ev: TTyTerminalKeyEvent;
  r: TTyTerminalKeyResult;
  act: TKeyAction;
  pass, ctrl, alt, meta, shf: Boolean;
begin
  ModifierChanged(Key, Shift);
  { 宿主的 OnKeyDown 先拿到;它清了零就到此为止 }
  inherited KeyDown(Key, Shift);
  FKeyDownHandled := False;
  FLastKeyShift := Shift;
  if Key = 0 then Exit;
  { 输入法正在组字(CompositionHelper.ts:117-131 同一个意思):不动 }
  if (Key = TyVkImeProcess) or (Key = VK_PROCESSKEY) then Exit;
  ev := TyTerminalKeyEventFromLCL(Key, Shift);
  ctrl := ssCtrl in Shift;
  alt := ssAlt in Shift;
  meta := ssMeta in Shift;
  shf := ssShift in Shift;
  r := Default(TTyTerminalKeyResult);
  act := kaNone;
  { 本地动作先认:复制、粘贴(Ctrl+C 永远发给程序,macOS 上是 Cmd+C / Cmd+V) }
  if FIsMac then
  begin
    if meta and not ctrl and not alt and not shf then
      if Key = Ord('C') then act := kaCopy
      else if Key = Ord('V') then act := kaPaste;
  end
  else if not meta and not alt then
  begin
    if ctrl and shf and (Key = Ord('C')) then act := kaCopy
    else if ctrl and shf and (Key = Ord('V')) then act := kaPaste
    else if ctrl and not shf and (Key = VK_INSERT) then act := kaCopy
    else if shf and not ctrl and (Key = VK_INSERT) then act := kaPaste;
  end;
  { Shift+Home / Shift+End:滚回到顶、到底 }
  if (act = kaNone) and shf and not ctrl and not alt and not meta then
    if Key = VK_HOME then act := kaTop
    else if Key = VK_END then act := kaBottom;
  if act = kaNone then
  begin
    r := TyTerminalEvaluateKey(ev, FCore.Modes.ApplicationCursorKeys, FIsMac, FMacOptionIsMeta);
    case r.Kind of
      tkrPageUp: act := kaPageUp;
      tkrPageDown: act := kaPageDown;
      tkrSelectAll: act := kaSelectAll;   { macOS 的 Cmd+A(Keyboard.ts 的 SELECT_ALL) }
    else
      begin
        { 第三层 Shift(AltGr、macOS Option):字符留给 UTF8KeyPress,上游 return true }
        if TyTerminalIsThirdLevelShift(ev, FIsMac, FIsWindows, FMacOptionIsMeta, False) then Exit;
        if KeyWaitsForItsCharacter(ev) then Exit;
        if r.Key <> '' then act := kaSend;
      end;
    end;
  end;
  { 没有动作:Key 原样往下走(窗体快捷键、Tab 导航照常) }
  if act = kaNone then Exit;
  { 有动作:先问宿主要不要放行给窗体 }
  pass := False;
  if Assigned(FOnShortcutQuery) then
    FOnShortcutQuery(Self, Key, Shift, pass);
  if pass then Exit;
  case act of
    kaSend:
      begin
        { ReadOnly 不在这里判断:Core 把 OnData 挡掉(上游 disableStdin 同样挡在
          triggerDataEvent 里),本地动作照常 }
        FCore.Input(r.Key, True);
        NoteActivity;
      end;
    kaCopy: CopyToClipboard;
    kaPaste: PasteFromClipboard;
    kaPageUp: FCore.ScrollLines(-(FCore.Rows - 1));     { 上游 rows - 1,CoreBrowserTerminal.ts:873-878 }
    kaPageDown: FCore.ScrollLines(FCore.Rows - 1);
    kaTop: FCore.ScrollToTop;
    kaBottom: FCore.ScrollToBottom;
    kaSelectAll:
      begin
        SelectAll;
        FinishSelection;
      end;
  end;
  Key := 0;
  FKeyDownHandled := True;
end;

procedure TTyTerminalView.KeyUp(var Key: Word; Shift: TShiftState);
begin
  ModifierChanged(Key, Shift);
  inherited KeyUp(Key, Shift);
  { 这个键的字符没来(widgetset 不送、或者按下时被别处拿走):别留给下一个键 }
  FKeyDownHandled := False;
end;

procedure TTyTerminalView.UTF8KeyPress(var UTF8Key: TUTF8Char);
var
  full: string;
  ev: TTyTerminalKeyEvent;
begin
  { GTK3 把输入法的提交截断成一个 TUTF8Char 送来:整段还在 widgetset 手里,取那一段
    (Edit.pas 同一个绕行;其他 widgetset 上返回空串) }
  full := TyImeTakeCommit(UTF8Key);
  if full <> '' then
  begin
    HandleImeCommit(full);
    UTF8Key := '';
    Exit;
  end;
  inherited UTF8KeyPress(UTF8Key);
  if UTF8Key = '' then Exit;
  { KeyDown 已经把这个键的字节发了:widgetset 还送来的字符丢掉(上游 _keyDownHandled) }
  if FKeyDownHandled then
  begin
    FKeyDownHandled := False;
    UTF8Key := '';
    Exit;
  end;
  { 带着 Ctrl / Alt / Meta 打出来的字符,除非是第三层 Shift,都不发(CoreBrowserTerminal.ts
    :980-985) }
  if [ssCtrl, ssAlt, ssMeta] * FLastKeyShift <> [] then
  begin
    ev := TyTerminalKeyEventFromLCL(0, FLastKeyShift);
    if not TyTerminalIsThirdLevelShift(ev, FIsMac, FIsWindows, FMacOptionIsMeta, True) then
    begin
      UTF8Key := '';
      Exit;
    end;
  end;
  { 控制字符只可能是 KeyDown 已经处理过、widgetset 又送来的那一份 }
  if (Length(UTF8Key) = 1) and ((UTF8Key[1] < #32) or (UTF8Key[1] = #127)) then
  begin
    UTF8Key := '';
    Exit;
  end;
  FCore.Input(UTF8Key, True);
  NoteActivity;
  UTF8Key := '';
end;

{ ---- 鼠标 --------------------------------------------------------------------------- }

function TTyTerminalView.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  notches, i, dir: Integer;
  ev: TTyTerminalMouseEvent;
begin
  { 宿主的 OnMouseWheel 先拿;它处理了就到此为止 }
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result or not Enabled then Exit;
  { Shift+滚轮:上游既不上报也不翻方向键(MouseService.ts:459 的 _consumeWheelEvent 对
    shiftKey 答 0 行);滚回在 Windows / Linux 上是横滚(scrollableElement.ts:394,终端没有
    横向可滚),只有 macOS 照常竖滚。不是我们的事就不吃,交给父控件。 }
  if ssShift in Shift then
  begin
    if not (FIsMac and FCore.Buffer.HasScrollback) then Exit;
    if (FWheelAccum <> 0) and ((FWheelAccum > 0) <> (WheelDelta > 0)) then
      FWheelAccum := 0;
    Inc(FWheelAccum, WheelDelta);
    notches := FWheelAccum div 120;
    FWheelAccum := FWheelAccum - notches * 120;
    Result := True;
    if notches <> 0 then
      FCore.ScrollLines(-3 * notches);
    Exit;
  end;
  { 每满 ±120 出一格,同号的余数留着,反向时清零;一格都不满也吃掉这点位移 }
  if (FWheelAccum <> 0) and ((FWheelAccum > 0) <> (WheelDelta > 0)) then
    FWheelAccum := 0;
  Inc(FWheelAccum, WheelDelta);
  notches := FWheelAccum div 120;
  FWheelAccum := FWheelAccum - notches * 120;
  Result := True;
  if notches = 0 then Exit;
  if notches > 0 then dir := 1 else dir := -1;
  for i := 1 to Abs(notches) do
  begin
    { MouseService.ts:250-292:程序要滚轮事件就上报;否则有滚回就滚 3 行;再否则
      (备用屏、AlternateScroll)发方向键 }
    if Reporting then
    begin
      if dir > 0 then
        ev := MakeMouseEvent(tmbWheel, tmaUp, MousePos.X, MousePos.Y, Shift)
      else
        ev := MakeMouseEvent(tmbWheel, tmaDown, MousePos.X, MousePos.Y, Shift);
      if FCore.TriggerMouseEvent(ev) then Continue;
    end;
    if FCore.Buffer.HasScrollback then
      FCore.ScrollLines(-3 * dir)
    else if FAlternateScroll then
    begin
      if FCore.Modes.ApplicationCursorKeys then
      begin
        if dir > 0 then FCore.Input(#27'OA', True) else FCore.Input(#27'OB', True);
      end
      else if dir > 0 then
        FCore.Input(#27'[A', True)
      else
        FCore.Input(#27'[B', True);
    end;
  end;
end;

{ 横向滚轮:LCL 的 DoMouseWheelLeft / Right 拿不到 WheelDelta(DoMouseWheelHorz 按正负分过去),
  照竖向按 ±120 累计要覆盖这一层。程序要了滚轮就报 66 / 67(左 / 右);没要就交还父控件——
  终端没有横向可滚。 }
function TTyTerminalView.DoMouseWheelHorz(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean;
var
  notches, i: Integer;
begin
  Result := inherited DoMouseWheelHorz(Shift, WheelDelta, MousePos);
  if Result or not Enabled or (csDesigning in ComponentState) then Exit;
  if not Reporting then
    Exit(False);
  if (FHorzAccum <> 0) and ((FHorzAccum > 0) <> (WheelDelta > 0)) then
    FHorzAccum := 0;
  Inc(FHorzAccum, WheelDelta);
  notches := FHorzAccum div 120;
  FHorzAccum := FHorzAccum - notches * 120;
  Result := True;
  { LCL:WheelDelta < 0 是向左(DoMouseWheelHorz 分给 DoMouseWheelLeft) }
  for i := 1 to Abs(notches) do
    if notches < 0 then
      ReportMouse(tmbWheel, tmaLeft, MousePos.X, MousePos.Y, Shift)
    else
      ReportMouse(tmbWheel, tmaRight, MousePos.X, MousePos.Y, Shift);
end;

function TyTerminalMouseButtonFor(AAction: TTyTerminalMouseAction; AButton: TMouseButton;
  AShift: TShiftState): TTyTerminalMouseButton;
begin
  if AAction = tmaMove then
  begin
    if ssLeft in AShift then Result := tmbLeft
    else if ssMiddle in AShift then Result := tmbMiddle
    else if ssRight in AShift then Result := tmbRight
    else Result := tmbNone;
    Exit;
  end;
  case AButton of
    mbLeft: Result := tmbLeft;
    mbMiddle: Result := tmbMiddle;
    mbRight: Result := tmbRight;
  else
    Result := tmbNone;
  end;
end;

function TTyTerminalView.Reporting: Boolean;
begin
  Result := FCore.Modes.MouseProtocol <> tmpNone;
end;

{ 上报用的事件:格子按 CellAt(整除再钳,上游 getCoords 的非选区取整),像素钳在网格里
  (MouseCoordsService.ts:38-39 钳到画布宽高 - 1),修饰键原样:覆盖键按着时按键不会走到
  这里,滚轮照上游带着修饰位(MouseService.ts:175-179 只在 mouseEventsRequireAlt 时剥) }
function TTyTerminalView.MakeMouseEvent(AButton: TTyTerminalMouseButton; AAction: TTyTerminalMouseAction;
  X, Y: Integer; Shift: TShiftState): TTyTerminalMouseEvent;
var
  cell: TPoint;
  ins: TRect;
begin
  cell := CellAt(X, Y);
  ins := ContentInsets(Font.PixelsPerInch);
  Result := Default(TTyTerminalMouseEvent);
  Result.Col := cell.X;
  Result.Row := cell.Y;
  Result.X := EnsureRange(X - ins.Left, 0, FCore.Cols * FMetrics.CellW - 1);
  Result.Y := EnsureRange(Y - ins.Top, 0, FCore.Rows * FMetrics.CellH - 1);
  Result.Button := AButton;
  Result.Action := AAction;
  Result.Shift := ssShift in Shift;
  Result.Alt := ssAlt in Shift;
  Result.Ctrl := ssCtrl in Shift;
end;

procedure TTyTerminalView.ReportMouse(AButton: TTyTerminalMouseButton; AAction: TTyTerminalMouseAction;
  X, Y: Integer; Shift: TShiftState);
begin
  { 第 4、5 键上游是 NONE + 按下 / 抬起,被 TriggerMouseEvent 滤掉:不报 }
  if (AButton = tmbNone) and (AAction <> tmaMove) then Exit;
  FCore.TriggerMouseEvent(MakeMouseEvent(AButton, AAction, X, Y, Shift));
end;

function TTyTerminalView.OverrideIsAlt: Boolean;
begin
  Result := (FSelectionOverrideKey = tsoAlt) or ((FSelectionOverrideKey = tsoDefault) and FIsMac);
end;

function TTyTerminalView.OverrideHeld(Shift: TShiftState): Boolean;
begin
  case FSelectionOverrideKey of
    tsoShift: Result := ssShift in Shift;
    tsoAlt: Result := ssAlt in Shift;
    tsoNone: Result := False;
  else
    if FIsMac then Result := ssAlt in Shift else Result := ssShift in Shift;
  end;
end;

function TTyTerminalView.ColumnWanted(Shift: TShiftState): Boolean;
begin
  Result := (ssAlt in Shift) and not OverrideIsAlt;
end;

{ 指针形状(xterm.css:39、:119-120、:130):程序接管鼠标(没按覆盖键)箭头;要列选择十字;
  平常 I 形,宿主设了别的 Cursor 就用宿主的。用 SetTempCursor,不写 Cursor 属性;LCL 进出
  控件时会拿 Cursor 复位,所以每次移动都重设。 }
procedure TTyTerminalView.UpdatePointer(Shift: TShiftState);
var
  c: TCursor;
begin
  if csDesigning in ComponentState then Exit;
  if FHoverValid then
    c := crHandPoint
  else if Reporting and not OverrideHeld(Shift) then
    c := crDefault
  else if ColumnWanted(Shift) then
    c := crCross
  else if Cursor <> crDefault then
    c := Cursor
  else
    c := crIBeam;
  SetTempCursor(c);
end;

{ 谁拿鼠标(4 期 4b 附录的表):路在按下那一刻定,拖动、抬起一直走它,中途松开覆盖键不换路
  (MouseService.ts:224-249,选区服务的 mousemove 监听 stopImmediatePropagation)。上报路上
  别的键按下也照报;其他路上别的键不管。 }
procedure TTyTerminalView.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  cell: TPoint;
  link: TTyTermLink;
begin
  FStateChange := True;
  try
    inherited MouseDown(Button, Shift, X, Y);
  finally
    FStateChange := False;
  end;
  { 基类只在左键时取焦点;终端照终端的惯例,哪个键点下去都取(中键、右键也是在跟这个
    终端打交道)。守着 TabStop 同基类:TabStop = False 的终端(宿主拿它当只看的面板)
    点了也不抢焦点。SetFocus 可能抛(窗体还没显示、无头),同基类吞掉。 }
  if TabStop and CanFocus and not Focused then
    try
      SetFocus;
    except
    end;
  if csDesigning in ComponentState then Exit;
  FLastMousePos := Point(X, Y);
  SyncSelectionTrim;
  { Ctrl(macOS Cmd)+单击链接:链接优先,程序接管了鼠标也一样(spec §9.8);不上报、不选择 }
  if (FRoute = mrNone) and (Button = mbLeft) and LinkKeyHeld(Shift) then
  begin
    cell := CellAt(X, Y);
    if LinkAt(cell.X, cell.Y, link) then
    begin
      FRoute := mrLink;
      FRouteButton := Button;
      FDownLink := link;
      Exit;
    end;
  end;
  if FRoute = mrReport then
  begin
    Include(FReportHeld, Button);
    if Button = mbRight then FRightReported := True;
    ReportMouse(TyTerminalMouseButtonFor(tmaDown, Button, Shift), tmaDown, X, Y, Shift);
    Exit;
  end;
  if FRoute <> mrNone then Exit;
  if Button = mbRight then
  begin
    FRightReported := False;
    FRightLocal := False;
  end;
  if Reporting and not OverrideHeld(Shift) then
  begin
    FRoute := mrReport;
    FRouteButton := Button;
    FReportHeld := [Button];
    if Button = mbRight then FRightReported := True;
    ReportMouse(TyTerminalMouseButtonFor(tmaDown, Button, Shift), tmaDown, X, Y, Shift);
    Exit;
  end;
  case Button of
    mbLeft:
      begin
        FRoute := mrSelect;
        FRouteButton := Button;
        SelectionPress(Shift, X, Y);
      end;
    mbRight: FRightLocal := True;           { 菜单由 DoContextPopup 弹 }
    mbMiddle:
      { X11 惯例:中键粘贴 PRIMARY(松开时);Windows / macOS 上中键不做事 }
      if FUsesPrimary then
      begin
        FRoute := mrPrimary;
        FRouteButton := Button;
      end;
  end;
end;

procedure TTyTerminalView.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseMove(Shift, X, Y);
  if csDesigning in ComponentState then Exit;
  FLastMousePos := Point(X, Y);
  case FRoute of
    mrReport:
      ReportMouse(TyTerminalMouseButtonFor(tmaMove, mbLeft, Shift), tmaMove, X, Y, Shift);
    mrSelect:
      SelectionDrag(X, Y);
    mrNone:
      { 不带键的移动:只有 1003 放行(TriggerMouseEvent 按协议与去重决定);带着键却没有
        路(在别处按下的)上游也不报 }
      if Reporting and ([ssLeft, ssMiddle, ssRight] * Shift = []) then
        ReportMouse(tmbNone, tmaMove, X, Y, Shift);
  end;
  FMouseInside := True;
  UpdateHover(X, Y, Shift);
  UpdatePointer(Shift);
end;

procedure TTyTerminalView.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  rt: TTyTerminalMouseRoute;
  cell: TPoint;
  link: TTyTermLink;
begin
  FStateChange := True;
  try
    inherited MouseUp(Button, Shift, X, Y);
  finally
    FStateChange := False;
  end;
  if csDesigning in ComponentState then Exit;
  FLastMousePos := Point(X, Y);
  if FRoute = mrReport then
  begin
    ReportMouse(TyTerminalMouseButtonFor(tmaUp, Button, Shift), tmaUp, X, Y, Shift);
    { 上游在所有键都松开时才摘掉全局监听(MouseService.ts:196-203) }
    Exclude(FReportHeld, Button);
    if FReportHeld = [] then
      FRoute := mrNone;
    Exit;
  end;
  if (FRoute <> mrNone) and (Button = FRouteButton) then
  begin
    rt := FRoute;
    FRoute := mrNone;
    case rt of
      mrSelect: SelectionRelease;
      mrPrimary: Paste(ReadPrimaryText);
      mrLink:
        begin
          { 按下和抬起在同一条链接上才算(Linkifier.ts:220-233) }
          cell := CellAt(X, Y);
          if LinkAt(cell.X, cell.Y, link) and TyTermLinkEquals(link, FDownLink)
            and Assigned(FOnLinkActivate) then
            FOnLinkActivate(Self, link.Text, link.Source = tlsOsc8);
        end;
    end;
  end;
end;

{ ---- 链接 --------------------------------------------------------------------------- }

function TTyTerminalView.LinkKeyHeld(Shift: TShiftState): Boolean;
begin
  if FIsMac then
    Result := ssMeta in Shift
  else
    Result := ssCtrl in Shift;
end;

function TTyTerminalView.LinkAt(ACol, AViewRow: Integer; out ALink: TTyTermLink): Boolean;
begin
  Result := TyTermFindLinkAt(FCore.Buffer, FCore.Links, ACol, FCore.Buffer.YDisp + AViewRow, FCore.Cols,
    FDetectUrls, FAllowNonHttpLinks, ALink);
end;

procedure TTyTerminalView.DirtyLinkRows(const ALink: TTyTermLink);
var
  a, b, i: Integer;
begin
  a := Max(ALink.Range.StartY - 1 - FCore.Buffer.YDisp, 0);
  b := Min(ALink.Range.EndY - 1 - FCore.Buffer.YDisp, FCore.Rows - 1);
  if b < a then Exit;
  if FInRender then
  begin
    for i := a to Min(b, High(FDirty)) do
      FDirty[i] := True;
  end
  else
    DirtyRows(a, b);
end;

procedure TTyTerminalView.UpdateHover(X, Y: Integer; Shift: TShiftState);
var
  ins: TRect;
  cell: TPoint;
  link: TTyTermLink;
  valid: Boolean;
begin
  if csDesigning in ComponentState then Exit;
  FHoverShift := Shift;
  valid := False;
  link := Default(TTyTermLink);
  if (X >= 0) and (Y >= 0) and LinkKeyHeld(Shift) and (FRoute <> mrSelect) then
  begin
    EnsureMetrics(Font.PixelsPerInch);
    ins := ContentInsets(Font.PixelsPerInch);
    if (X >= ins.Left) and (Y >= ins.Top) and (X < ins.Left + FCore.Cols * FMetrics.CellW)
      and (Y < ins.Top + FCore.Rows * FMetrics.CellH) then
    begin
      cell := CellAt(X, Y);
      valid := LinkAt(cell.X, cell.Y, link);
    end;
  end;
  if (valid = FHoverValid) and (not valid or TyTermLinkEquals(link, FHoverLink)) then
    Exit;
  if FHoverValid then
    DirtyLinkRows(FHoverLink);
  FHoverLink := link;
  FHoverValid := valid;
  if FHoverValid then
    DirtyLinkRows(FHoverLink);
end;

{ ---- OSC 52 ------------------------------------------------------------------------ }

{ ClipboardAddon.ts:32-66,外加三种策略与宿主的同意。上游读剪贴板是 Promise、解析器停住等
  它;这里同步问宿主,应答的顺序同样不乱。应答不是用户输入(不清选区、不滚到底)。 }
function TTyTerminalView.HandleOsc52(const AData: string): Boolean;
var
  pc, pd, txt: string;
  allow: Boolean;
begin
  Result := True;
  if FOsc52 = to52Off then
    Exit;
  if not TyTermOsc52Split(AData, pc, pd) then
    Exit;
  if pd = '?' then
  begin
    if FOsc52 <> to52ReadWrite then
      Exit;
    txt := ReadClipboardText;
    allow := False;
    if Assigned(FOnOsc52) then
      FOnOsc52(Self, False, pc, txt, allow);
    if allow then
      FCore.Input(TyTermOsc52Reply(pc, txt), False);
  end
  else
  begin
    txt := TyTermOsc52Decode(pd);
    allow := True;
    if Assigned(FOnOsc52) then
      FOnOsc52(Self, True, pc, txt, allow);
    if allow then
      WriteClipboardText(txt);
  end;
end;

procedure TTyTerminalView.SetDetectUrls(AValue: Boolean);
begin
  if FDetectUrls = AValue then Exit;
  FDetectUrls := AValue;
  if FHoverValid then
    UpdateHover(FLastMousePos.X, FLastMousePos.Y, FHoverShift);
end;

procedure TTyTerminalView.SetAllowNonHttpLinks(AValue: Boolean);
begin
  if FAllowNonHttpLinks = AValue then Exit;
  FAllowNonHttpLinks := AValue;
  if FHoverValid then
    UpdateHover(FLastMousePos.X, FLastMousePos.Y, FHoverShift);
end;

{ ---- 右键菜单 ----------------------------------------------------------------------- }

procedure TTyTerminalView.DoContextPopup(MousePos: TPoint; var Handled: Boolean);
var
  keyboard: Boolean;
  cur: TRect;
  buf: TTyTerminalBuffer;
  cell: TPoint;
  link: TTyTermLink;
begin
  inherited DoContextPopup(MousePos, Handled);
  if Handled or (csDesigning in ComponentState) then Exit;
  keyboard := (MousePos.X = -1) and (MousePos.Y = -1);
  if not keyboard then
  begin
    { 这次右键按下报给了程序:不弹(Win32 在抬起后才发 WM_CONTEXTMENU) }
    if FRightReported then
    begin
      FRightReported := False;
      Handled := True;
      Exit;
    end;
    if FRightLocal then
      FRightLocal := False
    else if Reporting and not OverrideHeld(CurrentShiftState) then
    begin
      { 菜单先于按下到(有的 widgetset 按下时就发):按下会报给程序,这里不弹 }
      Handled := True;
      Exit;
    end;
  end;
  if PopupMenu <> nil then Exit;
  if keyboard then
  begin
    buf := FCore.Buffer;
    cur := CellRect(Min(buf.X, FCore.Cols - 1), EnsureRange(CursorViewRow, 0, FCore.Rows - 1));
    MousePos := Point(cur.Left, cur.Bottom);
  end
  else if FIsMac then
  begin
    { macOS 惯例(上游 rightClickSelectsWord: isMac):右键在选区外先选中那个词(指针下有链接
      就选整条) }
    SyncSelectionTrim;
    cell := CellAt(MousePos.X, MousePos.Y);
    if LinkAt(cell.X, cell.Y, link) then
      FSelection.RightClickSelect(SelPointAt(MousePos.X, MousePos.Y), @link.Range)
    else
      FSelection.RightClickSelect(SelPointAt(MousePos.X, MousePos.Y));
  end;
  ShowContextMenu(MousePos);
  Handled := True;
end;

procedure TTyTerminalView.UpdateContextMenu;

  function Add(const ACaption: string; AOnClick: TNotifyEvent): TMenuItem;
  begin
    Result := TMenuItem.Create(FMenu);
    Result.Caption := ACaption;
    Result.OnClick := AOnClick;
    FMenu.Items.Add(Result);
  end;

var
  sep: TMenuItem;
begin
  if FMenu = nil then
  begin
    FMenu := TTyPopupMenu.Create(nil);
    FMenuCopy := Add(rsTextMenuCopy, @MenuCopyClick);
    FMenuPaste := Add(rsTextMenuPaste, @MenuPasteClick);
    sep := TMenuItem.Create(FMenu);
    sep.Caption := '-';
    FMenu.Items.Add(sep);
    FMenuSelectAll := Add(rsTextMenuSelectAll, @MenuSelectAllClick);
    FMenuClear := Add(rsTerminalMenuClear, @MenuClearClick);
  end;
  FMenuCopy.Enabled := HasSelection;
  FMenuPaste.Enabled := not ReadOnly and (ReadClipboardText <> '');
  FMenuSelectAll.Enabled := True;
  FMenuClear.Enabled := True;
end;

procedure TTyTerminalView.ShowContextMenu(const AClientPos: TPoint);
var
  p: TPoint;
begin
  UpdateContextMenu;
  FMenu.Controller := ActiveController;
  FMenu.PopupComponent := Self;
  p := ClientToScreen(AClientPos);
  FMenu.PopUp(p.X, p.Y);
end;

function TTyTerminalView.CurrentShiftState: TShiftState;
begin
  Result := GetKeyShiftState;
end;

procedure TTyTerminalView.MenuCopyClick(Sender: TObject);
begin
  CopyToClipboard;
end;

procedure TTyTerminalView.MenuPasteClick(Sender: TObject);
begin
  PasteFromClipboard;
end;

procedure TTyTerminalView.MenuSelectAllClick(Sender: TObject);
begin
  SelectAll;
  FinishSelection;
end;

procedure TTyTerminalView.MenuClearClick(Sender: TObject);
begin
  Clear;
end;

{ ---- 选区 --------------------------------------------------------------------------- }

procedure TTyTerminalView.SelectionChanged(Sender: TObject);
begin
  if Assigned(FOnSelectionChange) then FOnSelectionChange(Self);
end;

{ 选区此刻落在哪几个视口行(钳在视口里);False = 没有,或不在视口里 }
function TTyTerminalView.SelectionViewRows(out AFirst, ALast: Integer): Boolean;
var
  s, e: TTyTermSelPoint;
  yd: Integer;
begin
  AFirst := -1;
  ALast := -1;
  if not FSelection.FinalStart(s) or not FSelection.FinalEnd(e) then
    Exit(False);
  yd := FCore.Buffer.YDisp;
  AFirst := Max(Min(s.Row, e.Row) - yd, 0);
  ALast := Min(Max(s.Row, e.Row) - yd, FCore.Rows - 1);
  Result := AFirst <= ALast;
  if not Result then
  begin
    AFirst := -1;
    ALast := -1;
  end;
end;

{ 上游 refresh():只重画涉及的行——上次画过的选区行段与现在的并集。在绘制里(追 trim)只标
  脏不失效:这一帧就画掉 }
procedure TTyTerminalView.SelectionRedraw(Sender: TObject);
var
  a, b, i: Integer;
begin
  if FSelDrawnFirst >= 0 then
  begin
    a := FSelDrawnFirst;
    b := FSelDrawnLast;
  end
  else
  begin
    a := MaxInt;
    b := -1;
  end;
  if SelectionViewRows(FSelDrawnFirst, FSelDrawnLast) then
  begin
    a := Min(a, FSelDrawnFirst);
    b := Max(b, FSelDrawnLast);
  end;
  { 画的时候会重记;这里先记下现在的,下一次失效就从它算 }
  if (b < a) or (a = MaxInt) then Exit;
  a := Max(a, 0);
  b := Min(b, High(FDirty));
  if b < a then Exit;
  if FInRender then
  begin
    for i := a to b do
      FDirty[i] := True;
  end
  else
    DirtyRows(a, b);
end;

procedure TTyTerminalView.SyncSelectionTrim;
var
  d: Int64;
begin
  if FSelection = nil then Exit;
  d := FCore.Buffer.TrimmedLines - FSelTrimBase;
  FSelTrimBase := FCore.Buffer.TrimmedLines;
  if d > 0 then
  begin
    if d > MaxInt then d := MaxInt;
    FSelection.HandleTrim(Integer(d));
  end;
end;

function TTyTerminalView.SelPointAt(X, Y: Integer): TTyTermSelPoint;
var
  ins: TRect;
  p: TPoint;
begin
  EnsureMetrics(Font.PixelsPerInch);
  ins := ContentInsets(Font.PixelsPerInch);
  p := TyTermSelectionPointAt(X - ins.Left, Y - ins.Top, FMetrics.CellW, FMetrics.CellH,
    FCore.Cols, FCore.Rows);
  Result.Col := p.X;
  Result.Row := p.Y + FCore.Buffer.YDisp;
end;

procedure TTyTerminalView.SelectionPress(Shift: TShiftState; X, Y: Integer);
var
  clicks: Integer;
  cell: TPoint;
  link: TTyTermLink;
  lp: PTyTermLinkRange;
begin
  clicks := TyMultiClickCount(ssDouble in Shift, X, Y, FLastClickX, FLastClickY, FLastClickTick,
    FClickCount, Font.PixelsPerInch);
  { 双击时指针下有链接就选整条(上游 _selectWordAtCursor 先看 linkifier.currentLink);
    不要求链接键,受 DetectUrls / AllowNonHttpLinks 管 }
  lp := nil;
  if clicks = 2 then
  begin
    cell := CellAt(X, Y);
    if LinkAt(cell.X, cell.Y, link) then
      lp := @link.Range;
  end;
  { Shift 扩展只在程序没接管鼠标时(上游 _enabled && shiftKey);程序接管时 Shift 是覆盖键 }
  FSelection.Press(SelPointAt(X, Y), clicks, not Reporting and (ssShift in Shift), ColumnWanted(Shift), lp);
  if FSelection.Dragging then
    StartDragTimer;
end;

procedure TTyTerminalView.SelectionDrag(X, Y: Integer);
var
  ins: TRect;
begin
  SyncSelectionTrim;
  EnsureMetrics(Font.PixelsPerInch);
  ins := ContentInsets(Font.PixelsPerInch);
  { 点钳在网格里,滚速按真实的越界距离算;50 像素是逻辑像素,按 PPI 缩放 }
  FSelection.DragTo(SelPointAt(X, Y), TyTermDragScrollAmount(Y - ins.Top, FCore.Rows * FMetrics.CellH,
    MulDiv(TyTermDragScrollMaxThreshold, Font.PixelsPerInch, 96)));
end;

procedure TTyTerminalView.SelectionRelease;
begin
  StopDragTimer;
  SyncSelectionTrim;
  FSelection.Release;
  FinishSelection;
end;

procedure TTyTerminalView.FinishSelection;
var
  t: string;
begin
  SyncSelectionTrim;
  if not FSelection.HasSelection then Exit;
  t := FSelection.Text(LineEnding);
  if FUsesPrimary then
    WritePrimaryText(t);
  if FCopyOnSelect then
    WriteClipboardText(t);
end;

procedure TTyTerminalView.StartDragTimer;
begin
  if csDesigning in ComponentState then Exit;
  if FDragTimer = nil then
  begin
    FDragTimer := TTimer.Create(nil);
    FDragTimer.Enabled := False;
    FDragTimer.Interval := TyTermDragScrollInterval;
    FDragTimer.OnTimer := @DragTimerFired;
  end;
  FDragTimer.Enabled := True;
end;

procedure TTyTerminalView.StopDragTimer;
begin
  if FDragTimer <> nil then
    FDragTimer.Enabled := False;
end;

procedure TTyTerminalView.DragTimerFired(Sender: TObject);
begin
  DragScrollTick;
end;

procedure TTyTerminalView.DragScrollTick;
var
  n: Integer;
begin
  SyncSelectionTrim;
  n := FSelection.DragScrollAmount;
  if n <> 0 then
  begin
    FCore.ScrollLines(n);
    FSelection.AfterDragScroll;
  end;
end;

function TTyTerminalView.DragTimerActive: Boolean;
begin
  Result := (FDragTimer <> nil) and FDragTimer.Enabled;
end;

procedure TTyTerminalView.SelectAll;
begin
  SyncSelectionTrim;
  FSelection.SelectAll;
end;

procedure TTyTerminalView.ClearSelection;
begin
  StopDragTimer;
  FSelection.Clear;
end;

procedure TTyTerminalView.Select(ACol, AAbsRow, ALength: Integer);
begin
  SyncSelectionTrim;
  FSelection.SetSelection(ACol, AAbsRow, ALength);
end;

procedure TTyTerminalView.SelectLines(AFirst, ALast: Integer);
begin
  SyncSelectionTrim;
  FSelection.SelectLines(AFirst, ALast);
end;

function TTyTerminalView.GetSelectionText: string;
begin
  SyncSelectionTrim;
  Result := FSelection.Text(LineEnding);
end;

function TTyTerminalView.GetHasSelection: Boolean;
begin
  SyncSelectionTrim;
  Result := FSelection.HasSelection;
end;

procedure TTyTerminalView.SetWordSeparators(const AValue: string);
begin
  FWordSeparators := AValue;
  FSelection.WordSeparators := UTF8Decode(AValue);
end;

function TTyTerminalView.WordSeparatorsStored: Boolean;
begin
  Result := FWordSeparators <> TyTermDefaultWordSeparators;
end;

{ ---- 输入法 ------------------------------------------------------------------------- }

procedure TTyTerminalView.InitializeWnd;
begin
  inherited InitializeWnd;
  { Qt / GTK2 的库内钩子(提交整段、不被 TUTF8Char 截断;候选窗跟着光标);Win32、Cocoa
    上返回 nil。设计期不装。 }
  if csDesigning in ComponentState then Exit;
  TyImeUninstall(FImeHook);
  FImeHook := TyImeInstall(Self, @HandleImeCommit, @GetImeCaretRect);
end;

procedure TTyTerminalView.DestroyWnd;
begin
  TyImeUninstall(FImeHook);
  inherited DestroyWnd;
end;

function TTyTerminalView.GetImeCaretRect: TRect;
begin
  if (not HandleAllocated) or (not FHasFocus) or (not FImeCaretValid) then
    Exit(Rect(0, 0, 0, 0));
  Result := FImeCaretRect;
end;

{$IFDEF LCLCocoa}
procedure TTyTerminalView.CocoaImComposition(var Message: TLMessage);
begin
  { WParam 0 = IM_MESSAGE_WPARAM_GET_IME_HANDLER:LCL-Cocoa 要 ICocoaIMEControl(Edit.pas 同一做法) }
  if Message.WParam = 0 then Message.Result := PtrInt(FCocoaIme)
  else Message.Result := 0;
end;
{$ENDIF}

procedure TTyTerminalView.HandleImeCommit(const ACommitUtf8: string);
begin
  if ACommitUtf8 = '' then Exit;
  FCore.Input(ACommitUtf8, True);
  NoteActivity;
end;

procedure TTyTerminalView.CopyToClipboard;
begin
  if HasSelection then
    WriteClipboardText(SelectionText);
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
  { macOS 的候选窗锚:和 GetImeCaretRect 同一个矩形(上一帧画出来的光标格);还没画过就
    现算一个 }
  if not FHasFocus then
    Exit(Rect(0, 0, 0, 0));
  if FImeCaretValid then
    Result := FImeCaretRect
  else
    Result := CellRect(Min(FCore.Buffer.X, FCore.Cols - 1), FCore.Buffer.Y);
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
  { 不在组字会话里:LCL-Cocoa 在没有标记文本、却带着替换范围(死键)时直接调
    IMEInsertFinalText,后面不跟 IMESessionEnd——这就是一次提交,当场发出,不留在组字串里
    (留着的话下一次会话结束会再发一遍) }
  if not FInPreedit then
  begin
    HandleImeCommit(AText);
    Exit;
  end;
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

function TTyTerminalView.ScrollBarSyncs: Integer;
begin
  Result := FBarSyncs;
end;

function TTyTerminalView.ControlInvalidations: Integer;
begin
  Result := FControlInvalidates;
end;

function TTyTerminalView.RowsLeftToPaint: Boolean;
var
  r: Integer;
begin
  Result := FAllDirty;
  for r := 0 to High(FDirty) do
    if FDirty[r] then Exit(True);
end;

end.
