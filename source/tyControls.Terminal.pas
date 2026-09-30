unit tyControls.Terminal;
{$mode objfpc}{$H+}

{ TTyTerminalView:可见的终端控件。把 2 期的 TTyTerminalCore 画出来、接上键盘和滚回。

  自己写的控件,没有移植代码;下面几处的**逻辑**参照 xterm.js 6.0.0(commit c58ea3637f39):
    同步输出(2026)   src/browser/services/RenderService.ts:155-200、:337-380
    焦点与键盘分流    src/browser/CoreBrowserTerminal.ts:860-1017
    滚轮三种去向      src/browser/services/MouseService.ts:250-292
  渲染部件(度量、颜色、字形遮罩、自绘框线、行绘制器)在 tyControls.Terminal.Render,
  按键编码在 tyControls.Terminal.Keyboard。鼠标、链接、OSC 52、右键菜单、选区胶水五段为了好读
  搬进了 include(tyControls.Terminal.View.Mouse / Links / Osc52 / Menu / Selection.inc)。

  改之前要知道的几件事:

  - 本控件**接管**了 Core 的这些事件,宿主别改写:OnData、OnRefreshRows、OnTitleChange、
    OnBell、OnCursorMove、OnScroll、OnBufferActivate、OnModesChange、OnOsc、
    OnQueryBaseColor、OnProcessRequest、OnWindowOptionsReport、OnResize、
    OnScrollbackCleared、OnUserInput。宿主可以自己挂的是 OnIconNameChange、OnLineFeed、
    OnRequestScrollToBottom(只是通知:Core 自己滚到底),或者 Core.Parser.Register*Handler。
  - 解析一次(AsyncSlice、WriteSync、Write)里 Core 可能滚几千次、改几次色:这期间滚动只记
    「网格待失效」「滚动条待同步」,颜色签名不看;解析返回后(EndDrive)统一失效、同步一次,
    签名变了(OSC 4 / 10 / 11 / 104 …)整窗失效——内边距也是 257 号色。
  - 行复用(5 期):每个视口行按(行对象的 Serial、Revision、压在这一行上的选区 / 悬停链接 /
    光标 / 组字串)记一个键。一帧里键和上一帧同一行相同就不动,和上一帧另一行相同就把
    那一行的像素搬过来(画了阴影 ░▒▓ 的行只按图案纵向周期的整数倍搬),都不是才画。
    帧级参数(色表、度量、聚焦、粗体变亮……)一变,全部键作废、整屏重画。滚动不再整屏
    标脏,只失效网格区让 Paint 贴一次。同步输出攒着的时候不搬也不画。
  - 帧率:输出排着时解析加绘制一轮约 50 ms(FloodCycleMs):离上次绘制不到「一轮减上一帧
    的绘制耗时」就接着跑片,到了就当场画这一帧(Update)再排下一片——Win32 上排片的
    WM_NULL 一直在,只靠消息循环 WM_PAINT 永远轮不到;有按键排队时下一片走计时器。一帧里
    光栅化新字形有时间预算(输出排着时 4 ms),没画完的行留脏、下一帧整行重画。
  - 焦点跟 LM_SETFOCUS / LM_KILLFOCUS(切到别的程序也算失焦),DoEnter / DoExit 也照报,
    两路幂等。
  - 不在 Paint 里改网格。RenderTo 只读状态、画;度量变了要改网格就记下来,经
    QueueAsyncCall 延后一次(改尺寸会发事件、宿主会改 PTY、会再次失效重画,在绘制里做就是
    重画风暴)。
  - 改尺寸合并(5 期):有句柄时(真窗口拖动)客户区一变,新网格先记在 FPendingGrid、排一次
    QueueAsyncCall,消息循环里才 Core.Resize——大滚回的重新折行一次上百毫秒,拖动中只按
    最后的尺寸折一次。排着的时候照旧按 Core 的格子画(网格外是底色,行画到内区为止);
    只有问几何的入口(Cols、Rows、CellAt、CellRect、SizeForGrid)和 WriteSync 先把排着的
    应用掉。Write、Input、Paste 不应用:拖动时程序收到改尺寸就会输出,每次 Write 都应用
    就成了每一步折一次。所以排着的时候 Core 仍是旧网格(Core 属性不应用),数据按旧网格
    解析,应用时一起折。释放中不应用。没有句柄(隐藏的控件、测试、设计器)照旧当场改。
  - 能出字符的键在 KeyDown 里**不清零**:Win32 上 LCL 处理了 WM_KEYDOWN(Key 被清零)就会
    吞掉随后的 WM_CHAR,字符就丢了。KeyDown 已经发过字节的键,由本控件自己记
    FKeyDownHandled,UTF8KeyPress 见到就丢——不靠 widgetset 的行为。
  - 列数不随滚动条显隐变:网格宽 = 客户区 − 内边距 − 条宽(条宽**恒扣**,备用屏里条只是
    禁用)。进 vim 那一刻列数不变,不会给程序多发一次改尺寸。
  - OnRefreshRows 报的行号 Core 已经换算成**视口行**(InputHandler.parse 的结尾),这里
    直接用,不再加 YBase − YDisp。
  - 主题变了没有钩子:覆盖 Invalidate,比 (模型, ThemeVersion, StyleClass, StyleOverride);
    RenderTo 开头再比一次兜底(无头测试直接调 RenderTo)。
  - 独立配色方案(6 期):ColorSource / ColorScheme / ColorSchemePaired / DarkColorScheme。
    改这几项(含方案里的色)不当场 Invalidate:色表的键里有来源、配对和选中那一边的修订号,
    当场就失效(Core 问颜色、996 已是新的);「清 OSC 覆盖、报 2031、重画」经 QueueAsyncCall
    做一次(RequestSchemeNotify),宿主连着设几项程序只收到一条 2031。加载中(csLoading)
    什么都不排、不通知;Loaded 之后第一次建色表不算「变了」。
  - 选区照上游记坐标(缓冲行),不记标记:输出把行挤出头部时按缓冲的 TrimmedLines 差值
    整体上移(SyncSelectionTrim),解析返回后、绘制前、每个鼠标入口都追一次。清选区的时机
    同上游:用户输入、行数变了、换缓冲(含 RIS / Reset)、程序打开鼠标上报;另加清滚回。 }

interface

uses
  tyControls.Css.Values,
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType, LCLIntf, LMessages, LazUTF8, Forms,
  ExtCtrls, Clipbrd, Menus, tyControls.Menu, tyControls.StrConsts,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.StyleModel,
  tyControls.Controller, tyControls.ScrollBar, tyControls.PlatformWS, tyControls.TextMenu,
  tyControls.Unicode.Width, tyControls.Terminal.Buffer, tyControls.Terminal.Core,
  tyControls.Terminal.Keyboard, tyControls.Terminal.Render, tyControls.Terminal.Selection,
  tyControls.Terminal.Links, tyControls.Terminal.Parser, tyControls.Terminal.ColorScheme;

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
  TTyTerminalColorScheme = tyControls.Terminal.ColorScheme.TTyTerminalColorScheme;

  { 色表从哪来:跟随主题(默认,5 期的样子)/ 自定义方案(ColorScheme,配对时按主题明暗选边) }
  TTyTerminalColorSource = (tsrcTheme, tsrcScheme);

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
    改,AAllow 默认 False(宿主不说行就不给)。同步发,在解析中间:宿主可以在这里弹模态框,
    **不能释放控件**(也不能关它所在的窗体);事件抛出的异常控件吞掉,这一条作罢 }
  TTyTerminalOsc52Event = procedure(Sender: TObject; AWrite: Boolean; const ASelection: string;
    var AText: string; var AAllow: Boolean) of object;

  { 5 期:行复用。压在一行上的东西(按字段比,不用哈希):选区列段 [SelFrom, SelTo)、悬停链接
    列段 [LinkFrom, LinkTo)、光标(列,不显示时 -1;形状)、组字串(在这一行时)和它画在哪一列
    (光标不显示时它照样画,横移光标的列要单独记,不然组字串留在旧位置) }
  TTyTermRowOverlay = record
    SelFrom, SelTo, LinkFrom, LinkTo, CursorCol: Integer;
    CursorShape: TTyTermCursorShape;
    Preedit: string;
    PreeditCol: Integer;
  end;
  { 一行像素的键。Serial / Revision 来自 TTyTerminalLine(没有行:0 / 0);YPhase:这一行画了
    阴影图案;Valid:这一行的像素是按这个键画全的 }
  TTyTermRowKey = record
    Serial: Int64;
    Revision: QWord;
    Overlay: TTyTermRowOverlay;
    YPhase, Valid: Boolean;
  end;

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
    { 行复用:上一帧每个视口行的键、帧级参数的签名、这一帧新算的键、搬行的草稿 }
    FRowKeys, FNewKeys: array of TTyTermRowKey;
    FFrameKey: string;
    FMoveScratch: array of TBGRAPixel;
    FRowsMoved, FRowsPaintedFrame: Integer;
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
    FLastFrameCostMs: Double;              { 上一帧 RenderTo(贴到画布的那种)花了多久 }
    FSliceTimer: TTimer;                   { Win32:输入在排队时,下一片走它 }
    FRasterBudgetMs: Double;
    { 最低对比度(5 期):钳过的值;两份缓存(常规 / 暗淡减半),色表签名一变一起清 }
    FMinContrast: Double;
    FContrastCache, FHalfContrastCache: TTyTermContrastCache;
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
    { 独立配色方案(6 期) }
    FColorSource: TTyTerminalColorSource;
    FColorScheme, FDarkColorScheme: TTyTerminalColorScheme;
    FColorSchemePaired: Boolean;
    { 色表缓存键新增的:来源、配对、上次选了哪一边、那一边的修订号 }
    FPaletteSource: TTyTerminalColorSource;
    FPalettePaired, FPaletteDarkSide: Boolean;
    FPaletteSchemeRev: Cardinal;
    FActiveScheme: TTyTerminalColorScheme;
    FThemeGroundDark: Boolean;
    { EnsureThemeCurrent 的「上次通知」键同样加这四项 }
    FNotifiedSource: TTyTerminalColorSource;
    FNotifiedPaired, FNotifiedDarkSide: Boolean;
    FNotifiedSchemeRev: Cardinal;
    FSchemeNotifyRequests: Integer;
    { 状态 }
    FScrollBar: TTyScrollBar;
    FSyncingScroll: Boolean;
    FBarSyncs, FControlInvalidates: Integer;
    FHasFocus: Boolean;
    FStateChange: Boolean;
    FGridAnnounced: Boolean;
    FRelayoutQueued: Boolean;
    { 改尺寸合并:排着的网格 }
    FPendingGrid: TPoint;
    FGridPending: Boolean;
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
    { 在 LCL 的抬起消息里(它先放捕获、CaptureChanged 先于 MouseUp 到):这时的捕获变化不是
      「抬起丢了」 }
    FInButtonUp: Boolean;
    FSelectionOverrideKey: TTyTerminalSelectionOverrideKey;
    FLastMousePos: TPoint;
    { 选区:上游 SelectionService 的非 DOM 部分;缓冲的 TrimmedLines 读数;上次画到的视口
      行段(失效用);多击;拖出边界的自动滚 }
    FSelection: TTyTermSelection;
    FSelTrimBase: Int64;
    FSelRows, FSelCols: Integer;
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
    procedure AsyncApplyGrid(Data: PtrInt);
    { 排着的网格当场应用(要新网格的公开入口先调它) }
    procedure ApplyPendingGrid;
    function GetCore: TTyTerminalCore;
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
    { 行复用:AFrom[r] >= 0 的行从上一帧的第 AFrom[r] 行搬过来(先把源行都拷进草稿) }
    procedure MoveRows(const AFrom: TIntegerDynArray; const AInsets: TRect);
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
    { 独立配色方案 }
    procedure SetColorSource(AValue: TTyTerminalColorSource);
    procedure SetColorScheme(AValue: TTyTerminalColorScheme);
    procedure SetDarkColorScheme(AValue: TTyTerminalColorScheme);
    procedure SetColorSchemePaired(AValue: Boolean);
    procedure SchemeChanged(Sender: TObject);
    { 改了来源 / 配对 / 方案:经消息循环通知一次(加载中、释放中不排) }
    procedure RequestSchemeNotify;
    { 这一边(深 = True)用的方案的修订号;跟随主题时 0 }
    function SideRevision(ADark: Boolean): Cardinal;
    { 鼠标上报 }
    function Reporting: Boolean;
    function MakeMouseEvent(AButton: TTyTerminalMouseButton; AAction: TTyTerminalMouseAction;
      X, Y: Integer; Shift: TShiftState): TTyTerminalMouseEvent;
    function ReportMouse(AButton: TTyTerminalMouseButton; AAction: TTyTerminalMouseAction;
      X, Y: Integer; Shift: TShiftState): Boolean;
    function OverrideIsAlt: Boolean;
    procedure UpdatePointer(Shift: TShiftState);
    { 这次按下的路要的键还按着没有(HeldMouseButtons) }
    function RouteButtonsHeld: Boolean;
    { 抬起丢了(捕获被拿走、失焦,键已经不在了):照 MouseUp 收尾——停自动滚、选区松开、
      上报路补发抬起、路复位;链接不激活、PRIMARY 不粘贴 }
    procedure ForgetPress;
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
    procedure SetMinContrast(AValue: Double);
    function MinimumContrastRatioStored: Boolean;
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
    { PRIMARY 按需:有人要时才取选区的文字(LCL 的 OnRequest,FormatID = 0 是丢了所有权) }
    procedure PrimaryRequest(const RequestedFormatID: TClipboardFormat; Data: TStream);
  protected
    { 平台标志:按平台(不是 widgetset)取;受保护,测试可以改成别的平台 }
    FIsMac, FIsWindows: Boolean;
    { 用不用 X11 的 PRIMARY(TyTerminalUsesPrimary);测试可以改 }
    FUsesPrimary: Boolean;
    function ReadPrimaryText: string; virtual;
    { 选区成了 PRIMARY:只登记「有、是文字」,文字等有人要时才取(PrimaryRequestText);默认
      走 LCL 的 PrimarySelection.OnRequest(SynEdit 的做法) }
    procedure OfferPrimary; virtual;
    { 有人要 PRIMARY 时给的:此刻的选区文字 }
    function PrimaryRequestText: string;
    { 剪贴板里有没有文字(弹菜单时判「粘贴」,不读整段);默认 TyClipboardHasText }
    function ClipboardHasText: Boolean; virtual;
    { 此刻实际按着的鼠标键(ssLeft / ssMiddle / ssRight);默认按 GetKeyState 问 }
    function HeldMouseButtons: TShiftState; virtual;
    { 捕获被拿走:不在 LCL 的抬起消息里、路要的键也不在了,就是抬起丢了(ForgetPress) }
    procedure CaptureChanged; override;
    procedure WMLButtonUp(var Message: TLMLButtonUp); message LM_LBUTTONUP;
    procedure WMMButtonUp(var Message: TLMMButtonUp); message LM_MBUTTONUP;
    procedure WMRButtonUp(var Message: TLMRButtonUp); message LM_RBUTTONUP;
    { 选区追上被挤出头部的行(缓冲 TrimmedLines 的差值) }
    procedure SyncSelectionTrim;
    { 一次选择结束(松开、双击、三击、Shift 扩展、全选):选区非空就登记 PRIMARY(文字按需)、
      CopyOnSelect 时写剪贴板;两样都不要就不取文字 }
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
    { 调度的缝:默认 Application.QueueAsyncCall(设计期不排片;Win32 上键盘、鼠标按键在排队时
      走一个 1 ms 计时器,先让输入进来) }
    procedure ScheduleSlice; virtual;
    procedure SliceTimerFired(Sender: TObject);
    { 排好的一片:跑到队列空、或者离上次绘制够一轮为止(留给解析的时间 = 50 ms 减上一帧
      画了多久,至少 3 ms);还有没解析的就当场画这一帧再排下一片 }
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
    { FOR THE TESTS(5 期):上一帧每个视口行的键;这一帧搬了几行、画了几行;下一帧当作
      整屏都没画过(对照「增量 = 整屏」) }
    function RowKeyOf(AViewRow: Integer): TTyTermRowKey;
    property RowsMovedLastFrame: Integer read FRowsMoved;
    property RowsPaintedLastFrame: Integer read FRowsPaintedFrame;
    procedure ForgetPaintedRows;
    function GlyphCache: TTyTermGlyphCache;
    { FOR THE TESTS(5 期):最低对比度的两份缓存 }
    function ContrastCache: TTyTermContrastCache;
    function HalfContrastCache: TTyTermContrastCache;
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
    { FOR THE TESTS(6 期,纯查询):色表这一刻用的是哪套(nil = 跟随主题)、主题的底算不算深、
      有没有排着的通知、RequestSchemeNotify 真正排队过几次 }
    function ActiveColorScheme: TTyTerminalColorScheme;
    function ThemeGroundIsDark: Boolean;
    function NotifyQueued: Boolean;
    function SchemeNotifyRequests: Integer;
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
    property Core: TTyTerminalCore read GetCore;
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
    { 最低对比度(xterm.js minimumContrastRatio):1 = 不调(默认,OptionsService.ts:43);大于 1
      时字色按上游 ensureContrastRatio 推离画出来的底色,暗淡的字按一半;框线块元素、
      Powerline、块光标下的字、链接下划线、显式下划线色不动。写入时照上游钳到 1..21、
      一位小数(NaN、无穷按 1)。Double 而非 Single:1.3 存成 Single 回读是 1.2999999523,
      边界上的比较会和上游不同 }
    property MinimumContrastRatio: Double read FMinContrast write SetMinContrast
      stored MinimumContrastRatioStored;
    property CopyOnSelect: Boolean read FCopyOnSelect write FCopyOnSelect default False;
    property DetectUrls: Boolean read FDetectUrls write SetDetectUrls default True;
    { OSC 8 里不是 http / https 的 URI(file://、ssh://)算不算链接:默认不算(上游没有
      linkHandler.allowNonHttpProtocols 时同样不算——不下划线、不能点) }
    property AllowNonHttpLinks: Boolean read FAllowNonHttpLinks write SetAllowNonHttpLinks default False;
    property Osc52: TTyTerminalOsc52Policy read FOsc52 write FOsc52 default to52Off;
    property LineHeightPercent: Integer read FLineHeightPercent write SetLineHeightPercent default 100;
    property LetterSpacing: Integer read FLetterSpacing write SetLetterSpacing default 0;
    { 独立配色方案(6 期):程序的 OSC 4 / 10 / 11 / 12 > 方案里设了的 > 主题。方案里没设的
      项跟主题;两个方案对象的 setter 是 Assign }
    property ColorSource: TTyTerminalColorSource read FColorSource write SetColorSource default tsrcTheme;
    property ColorScheme: TTyTerminalColorScheme read FColorScheme write SetColorScheme;
    { 开着时:主题的底是浅的用 ColorScheme、深的用 DarkColorScheme(按 tycss on() 的规则) }
    property ColorSchemePaired: Boolean read FColorSchemePaired write SetColorSchemePaired default False;
    property DarkColorScheme: TTyTerminalColorScheme read FDarkColorScheme write SetDarkColorScheme;
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

const
  TyQsKey = $0001;
  TyQsMouseButton = $0004;

{ user32 GetQueueStatus: the high word is what waits in the thread's queue now }
function TyGetQueueStatus(AFlags: LongWord): LongWord; stdcall; external 'user32' name 'GetQueueStatus';
{$ENDIF}

const
  { token 缺失时的兜底;真值都在主题里(§11)。0..15 缺失时退到 Tango(TyTermDefaultPaletteColor) }
  FallbackFg = $000000;
  FallbackBg = $FFFFFF;
  BlinkIntervalMs = 600;
  BlinkRestMs = 300000;          { 5 分钟不活动就停在「显示」 }
  SyncTimeoutMs = 1000;          { RenderService.ts:359-363 }
  SurfaceBlock = 64;             { 表面位图按这么大的块向上取整 }
  DefaultRasterBudgetMs = 10;
  FloodRasterBudgetMs = 4;       { 还有输出排着时一帧光栅化新字形的预算 }
  MinSliceMs = 3;                { 一片至少给解析这么久 }
  FloodCycleMs = 50;             { 输出一直排着时,解析加绘制一轮这么久(约 20 帧每秒) }

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
  FColorSource := tsrcTheme;
  FColorSchemePaired := False;
  FColorScheme := TTyTerminalColorScheme.Create(Self);
  FColorScheme.OnChange := @SchemeChanged;
  FDarkColorScheme := TTyTerminalColorScheme.Create(Self);
  FDarkColorScheme.OnChange := @SchemeChanged;
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
  FMinContrast := 1;
  FContrastCache := TTyTermContrastCache.Create;
  FHalfContrastCache := TTyTermContrastCache.Create;
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
  FSelCols := FCore.Cols;
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
  FreeAndNil(FSliceTimer);
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
  { 还拿着 PRIMARY:交出去(OnRequest 指着本对象的方法) }
  if FUsesPrimary and (PrimarySelection.OnRequest = @PrimaryRequest) then
    PrimarySelection.OnRequest := nil;
  FreeAndNil(FSelection);
  FreeAndNil(FMenu);
  FreeAndNil(FCore);
  FreeAndNil(FRowPainter);
  FreeAndNil(FGlyphCache);
  FreeAndNil(FContrastCache);
  FreeAndNil(FHalfContrastCache);
  FreeAndNil(FRasterizer);
  FreeAndNil(FSurface);
  FreeAndNil(FCocoaIme);
  if FColorScheme <> nil then FColorScheme.OnChange := nil;
  if FDarkColorScheme <> nil then FDarkColorScheme.OnChange := nil;
  FreeAndNil(FColorScheme);
  FreeAndNil(FDarkColorScheme);
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
  { 行复用:行的像素按键认,滚动只要网格区失效一次(同步输出开着就攒着) }
  DirtyRows(0, FCore.Rows - 1);
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
  { 程序换了鼠标上报协议、换完是开着的:上游每次协议变化都走 _syncMouseModeState ->
    SelectionService.disable() 清选区(MouseService.ts:380-393;1000 换 1002 也清),关掉
    不清。上游同一协议重复 DECSET 也清(activeProtocol 的 setter 每次都发);Core 只在模式
    真变了才发 OnModesChange,这一条我们不清(spec §15) }
  p := FCore.Modes.MouseProtocol;
  if (p <> FLastProtocol) and (p <> tmpNone) then
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
  { 行数变了清选区(SelectionService.ts:158-162)。列数变了上游不清;但当前缓冲这次真的重新
    折行了,格子里已经是别的字,选区还框着原来的坐标——这时也清(spec §15)。不折行
    (老 ConPTY、备用屏)照上游保留,折行挤出头部的行照常经 SyncSelectionTrim 上移。 }
  if (ARows <> FSelRows) or ((ACols <> FSelCols) and FCore.Buffer.IsReflowEnabled) then
    ClearSelection;
  FSelRows := ARows;
  FSelCols := ACols;
  { 悬停的链接照上游清掉(Linkifier.ts:47-50 _clearCurrentLink):范围指着旧坐标;指针再动
    时 UpdateHover 按新缓冲重新找 }
  if FHoverValid then
  begin
    DirtyLinkRows(FHoverLink);
    FHoverValid := False;
    { and the hand goes with it (Linkifier.ts:355-357 _linkLeave) }
    UpdatePointer(FHoverShift);
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
  {$IFDEF LCLWin32}
  { QueueAsyncCall 每排一次就投一个 WM_NULL,投递的消息排在键盘、鼠标之前:一片接一片地排,
    输入就一直进不来。有按键、鼠标按键在排队时下一片改走计时器(WM_TIMER 排在输入和绘制
    之后) }
  if HandleAllocated and ((TyGetQueueStatus(TyQsKey or TyQsMouseButton) shr 16) <> 0) then
  begin
    if FSliceTimer = nil then
    begin
      FSliceTimer := TTimer.Create(nil);
      FSliceTimer.Enabled := False;
      FSliceTimer.Interval := 1;
      FSliceTimer.OnTimer := @SliceTimerFired;
    end;
    FSliceTimer.Enabled := True;
    Exit;
  end;
  {$ENDIF}
  Application.QueueAsyncCall(@AsyncSlice, 0);
end;

procedure TTyTerminalView.SliceTimerFired(Sender: TObject);
begin
  FSliceTimer.Enabled := False;
  if csDestroying in ComponentState then Exit;
  AsyncSlice(0);
end;

procedure TTyTerminalView.AsyncSlice(Data: PtrInt);
var
  more: Boolean;
  window, elapsed: Double;
  budget: Integer;
begin
  MaskUnencodedExtensions;
  { 一轮里留给解析的时间:FloodCycleMs 减去上一帧画了多久,至少 MinSliceMs。一帧整屏新行
    要画 15–20 ms,贴上屏之后 DWM 还要再占十几毫秒:按 16 ms 一帧算,解析只剩 3 ms,吞吐掉到
    五分之一;50 ms 一轮,两次绘制隔 50–85 ms,吞吐约 5 MB/s(5 期实测,spec §3.1) }
  window := FloodCycleMs - FLastFrameCostMs;
  if window < MinSliceMs then window := MinSliceMs;
  BeginDrive;
  try
    { 帧率上限:离上次绘制还不到这么久,接着跑片;到了才停。每一片的预算是离这一刻还剩
      多少(至少 MinSliceMs);好久没画过(隐藏、无头)就按上游的 12 ms 一片 }
    repeat
      elapsed := NowMs - FLastPaintMs;
      if elapsed > 2 * FloodCycleMs then
        budget := TyTermWriteTimeoutMs
      else
      begin
        budget := Round(window - elapsed);
        if budget < MinSliceMs then budget := MinSliceMs;
      end;
      more := FCore.ProcessPending(budget);
    until (not more) or (NowMs - FLastPaintMs >= window);
  finally
    EndDrive;
  end;
  if more then
  begin
    { 这一帧当场画(UpdateWindow)。Windows 只在没有投递消息等着的时候才给 WM_PAINT,
      异步队列一片投一个消息:光靠排队,整个 flood 期间窗口一次也画不上 }
    if HandleAllocated and IsVisible and not (csDestroying in ComponentState) then
      Update;
    ScheduleSlice;
  end;
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
    DirtyRows(0, FCore.Rows - 1);
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
  { 改方案的路(RequestSchemeNotify)没有当场 Invalidate:这里重画 }
  Invalidate;
end;

procedure TTyTerminalView.AsyncApplyGrid(Data: PtrInt);
begin
  if csDestroying in ComponentState then Exit;
  ApplyPendingGrid;
end;

procedure TTyTerminalView.ApplyPendingGrid;
begin
  if not FGridPending then Exit;
  FGridPending := False;
  { a host reading Cols in its OnDestroy: no resize (and no reflow) on the way out }
  if csDestroying in ComponentState then Exit;
  if (FPendingGrid.X <> FCore.Cols) or (FPendingGrid.Y <> FCore.Rows) then
    FCore.Resize(FPendingGrid.X, FPendingGrid.Y);
end;

{ The core as it is: while a grid waits (header), its grid is still the old one. }
function TTyTerminalView.GetCore: TTyTerminalCore;
begin
  Result := FCore;
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
  instFg, instBg, themeFg, themeBg, c, rgb: Cardinal;
  inFocus, darkSide, selSet: Boolean;
  scheme: TTyTerminalColorScheme;
begin
  model := ActiveController.Model;
  cls := TyStyleClassFor(Self, StyleClass);
  { 6 期:键里再加来源、配对、选中那一边方案的修订号。选哪一边只取决于主题,主题的四项已经
    在键里,所以用上次算出的那一边挑修订号(另一边的方案改了不失效、不重画) }
  if FPaletteValid and (FPaletteModel = model) and (FPaletteVersion = model.ThemeVersion)
    and (FPaletteClass = cls) and (FPaletteOverride = StyleOverride)
    and (FPaletteSource = FColorSource) and (FPalettePaired = FColorSchemePaired)
    and (FPaletteSchemeRev = SideRevision(FPaletteDarkSide)) then
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
  { 6 期:独立配色方案。主题是深是浅看本实例跟随主题时的底色(instBg,不是方案的底),
    和 tycss 三参数 on() 同一条规则:Rec.601 亮度 > 0.5 为浅,恰好 0.5 算深 }
  darkSide := not (TyLuminance(TyRGB((instBg shr 16) and $FF, (instBg shr 8) and $FF, instBg and $FF)) > 0.5);
  if FColorSource = tsrcTheme then
    scheme := nil
  else if FColorSchemePaired and darkSide then
    scheme := FDarkColorScheme
  else
    scheme := FColorScheme;
  { 全空的方案画出来和跟随主题一样(spec §11.1.3):不走下面的「未设置取生效色」 }
  if (scheme <> nil) and scheme.IsEmpty then
    scheme := nil;
  if scheme <> nil then
  begin
    { 逐槽:方案设了用方案,没设的保留上面算好的主题值(spec §11.1.4) }
    for i := 0 to 15 do
      if scheme.SlotRgb(TTyTerminalSchemeSlot(i), rgb) then
        FPalette[i] := rgb;
    if scheme.SlotRgb(tssForeground, rgb) then FPalette[256] := rgb;
    if scheme.SlotRgb(tssBackground, rgb) then FPalette[257] := rgb;
    { 光标没设 = 生效的前景;光标下的字没设 = 生效的底色 }
    if scheme.SlotRgb(tssCursor, rgb) then
      FPalette[258] := rgb
    else
      FPalette[258] := FPalette[256];
    if scheme.SlotRgb(tssCursorText, rgb) then
      FCursorInkRgb := rgb
    else
      FCursorInkRgb := FPalette[257];
    { 选区:不透明的方案色按 xterm 降到 0.3(color.opacity 的 alpha = round(0.3 x 255) =
      $4D,ThemeService.ts:97-106),绘制时再在生效的底色上混成不透明;失焦没设就用聚焦的
      (ThemeService.ts:89),都没设跟主题 }
    selSet := scheme.SlotRgb(tssSelection, rgb);
    if selSet then
      FSelBg[True] := TTyColor(($4D shl 24) or rgb);
    if scheme.SlotRgb(tssSelectionInactive, rgb) then
      FSelBg[False] := TTyColor(($4D shl 24) or rgb)
    else if selSet then
      FSelBg[False] := FSelBg[True];
  end;
  FActiveScheme := scheme;
  FThemeGroundDark := darkSide;
  FPaletteSource := FColorSource;
  FPalettePaired := FColorSchemePaired;
  FPaletteDarkSide := darkSide;
  FPaletteSchemeRev := SideRevision(darkSide);
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
  { .lfm 的子属性一项项流进来:加载中不建色表、不记「已通知」(半套方案) }
  if csLoading in ComponentState then Exit;
  EnsurePalette;
  if FNotifiedValid and (FNotifiedModel = FPaletteModel) and (FNotifiedVersion = FPaletteVersion)
    and (FNotifiedClass = FPaletteClass) and (FNotifiedOverride = FPaletteOverride)
    and (FNotifiedSource = FPaletteSource) and (FNotifiedPaired = FPalettePaired)
    and (FNotifiedDarkSide = FPaletteDarkSide) and (FNotifiedSchemeRev = FPaletteSchemeRev) then
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
  FNotifiedSource := FPaletteSource;
  FNotifiedPaired := FPalettePaired;
  FNotifiedDarkSide := FPaletteDarkSide;
  FNotifiedSchemeRev := FPaletteSchemeRev;
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
    begin
      if HandleAllocated and not (csDesigning in ComponentState) then
      begin
        { 真窗口:合并到消息循环里,只按最后的尺寸改一次(单元头) }
        FPendingGrid := Point(nc, nr);
        if not FGridPending then
        begin
          FGridPending := True;
          Application.QueueAsyncCall(@AsyncApplyGrid, 0);
        end;
      end
      else
        { OnResize 回来做其余的事(地雷 7:在 Core 的事件里调会被延后,以 OnResize 为准) }
        FCore.Resize(nc, nr);
    end
    else
    begin
      { 拖回了 Core 现在的尺寸:排着的作废 }
      FGridPending := False;
      if not FGridAnnounced then
      begin
        { 加载完成后的第一次排版,尺寸没变也发一次(spec §9.2) }
        FGridAnnounced := True;
        if Assigned(FOnGridResize) then FOnGridResize(Self, nc, nr);
      end;
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
  { 加载定下的是起始状态:之后第一次建色表不算「变了」(不清 OSC 覆盖、不报 2031);
    不往 published 字段写任何东西 }
  FNotifiedValid := False;
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
  ApplyPendingGrid;
  EnsureMetrics(Font.PixelsPerInch);
  Result := GridCellRect(ACol, ARow, ContentInsets(Font.PixelsPerInch));
end;

function TTyTerminalView.CellAt(X, Y: Integer): TPoint;
var
  ins: TRect;
begin
  { 上游先钳再除(MouseCoordsService.ts:38-44);这里除完再钳到网格内,结果相同 }
  ApplyPendingGrid;
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
  ApplyPendingGrid;
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

{ 两个键画出来的像素一样:行对象、它的修订号、压在上面的东西都相同(上一帧那个键得是画全的) }
function SameRowKey(const APrev, ANew: TTyTermRowKey): Boolean;
begin
  Result := APrev.Valid and ANew.Valid and (APrev.Serial = ANew.Serial) and (APrev.Revision = ANew.Revision)
    and (APrev.Overlay.SelFrom = ANew.Overlay.SelFrom) and (APrev.Overlay.SelTo = ANew.Overlay.SelTo)
    and (APrev.Overlay.LinkFrom = ANew.Overlay.LinkFrom) and (APrev.Overlay.LinkTo = ANew.Overlay.LinkTo)
    and (APrev.Overlay.CursorCol = ANew.Overlay.CursorCol) and (APrev.Overlay.CursorShape = ANew.Overlay.CursorShape)
    and (APrev.Overlay.Preedit = ANew.Overlay.Preedit) and (APrev.Overlay.PreeditCol = ANew.Overlay.PreeditCol);
end;

procedure TTyTerminalView.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);

  function Frame(ARgb: Cardinal): Cardinal;
  begin
    { 禁用时朝父控件底色预混(色表同一个方向) }
    if FPremixAlpha < 255 then
      Result := PremixRgb(ARgb, FPremixBase, FPremixAlpha)
    else
      Result := ARgb;
  end;

var
  w, h, r, s, cursorRow, period: Integer;
  sel: TTyColor;
  buf: TTyTerminalBuffer;
  ins, clip, part: TRect;
  shape: TTyTermCursorShape;
  sig: Cardinal;
  ime: TRect;
  incomplete, allNew, holding: Boolean;
  frameKey: string;
  frameStart: Double;
  inner: TRect;
  line: TTyTerminalLine;
  rowAction: array of Byte;             { 0 不动,1 从别的行搬,2 画 }
  moved: TIntegerDynArray;
begin
  FInRender := True;
  frameStart := NowMs;
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
      { 上游换主题清对比度缓存(ThemeService.ts:136) }
      FContrastCache.Clear;
      FHalfContrastCache.Clear;
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
    { output still waiting (a flood): rows scroll away within frames, their new glyphs are
      mostly drawn for nothing -- a smaller budget, the frame comes back sooner }
    if (FCore.PendingBytes > 0) and ((FRasterBudgetMs <= 0) or (FRasterBudgetMs > FloodRasterBudgetMs)) then
      FRowPainter.RasterBudgetMs := IfThen(FRasterBudgetMs <= 0, FRasterBudgetMs, FloodRasterBudgetMs);
    FRowPainter.Clock := @NowMs;
    { 选区与链接:聚焦 / 失焦两色。选区色先带着它的 alpha 在主题底色上混成不透明(上游
      selectionBackgroundOpaque / selectionInactiveBackgroundOpaque,ThemeService.ts:87-90),
      禁用时再预混;行绘制器拿它**替换**选中格的底色(DomRendererRowFactory.ts:380-386),
      反显格、亮底色格上的选区也看得见 }
    sel := FSelBg[FHasFocus];
    FRowPainter.SelBg := Frame(TyTermBlendOver(FPalette[257],
      BGRA(TyRedOf(sel), TyGreenOf(sel), TyBlueOf(sel), TyAlphaOf(sel))));
    FRowPainter.SelHasInk := FSelHasInk[FHasFocus];
    FRowPainter.SelInk := Frame(FSelInk[FHasFocus]);
    FRowPainter.LinkColor := Frame(FLinkRgb);
    FRowPainter.MinContrast := FMinContrast;
    FRowPainter.ContrastCache := FContrastCache;
    FRowPainter.HalfContrastCache := FHalfContrastCache;
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
    { 帧级参数:色表(含禁用预混)、度量与字体、PPI、列数、聚焦(选区两色跟着它)、粗体变亮、
      网格的位置、最低对比度。任何一个变了,上一帧的键全部作废(主题换了经
      EnsureThemeCurrent 整屏) }
    frameKey := IntToHex(FPremixSig, 8) + '|' + FSpecKey + '|' + IntToStr(APPI) + '|' + IntToStr(FCore.Cols)
      + '|' + BoolToStr(FHasFocus, '1', '0') + BoolToStr(FDrawBoldBright, '1', '0')
      + '|' + IntToStr(ins.Left) + ',' + IntToStr(ins.Top)
      + '|' + IntToHex(PQWord(@FMinContrast)^, 16);
    if FAllDirty or (frameKey <> FFrameKey) or (Length(FRowKeys) <> FCore.Rows) then
    begin
      SetLength(FRowKeys, FCore.Rows);
      for r := 0 to High(FRowKeys) do
        FRowKeys[r].Valid := False;
      FFrameKey := frameKey;
      allNew := True;
    end
    else
      allNew := False;
    FAllDirty := False;
    for r := 0 to High(FDirty) do
      FDirty[r] := False;
    FRowsMoved := 0;
    FRowsPaintedFrame := 0;
    { 这一帧每个视口行的键 }
    if Length(FNewKeys) <> FCore.Rows then
      SetLength(FNewKeys, FCore.Rows);
    for r := 0 to FCore.Rows - 1 do
      with FNewKeys[r] do
      begin
        line := buf.GetLine(buf.YDisp + r);
        if line <> nil then
        begin
          Serial := line.Serial;
          Revision := line.Revision;
        end
        else
        begin
          Serial := 0;
          Revision := 0;
        end;
        { 选区按缓冲行(视口滚了它跟着字走) }
        if not FSelection.RowSpan(buf.YDisp + r, Overlay.SelFrom, Overlay.SelTo) then
        begin
          Overlay.SelFrom := 0;
          Overlay.SelTo := 0;
        end;
        { 悬停链接落在这一行上的那一段(1 起、闭区间、缓冲行) }
        Overlay.LinkFrom := 0;
        Overlay.LinkTo := 0;
        if FHoverValid and (buf.YDisp + r + 1 >= FHoverLink.Range.StartY) and (buf.YDisp + r + 1 <= FHoverLink.Range.EndY) then
        begin
          if buf.YDisp + r + 1 = FHoverLink.Range.StartY then
            Overlay.LinkFrom := FHoverLink.Range.StartX - 1;
          if buf.YDisp + r + 1 = FHoverLink.Range.EndY then
            Overlay.LinkTo := FHoverLink.Range.EndX
          else
            Overlay.LinkTo := FCore.Cols;
        end;
        if r = cursorRow then
        begin
          Overlay.CursorCol := Min(buf.X, FCore.Cols - 1);
          Overlay.CursorShape := shape;
        end
        else
        begin
          Overlay.CursorCol := -1;
          Overlay.CursorShape := tcpNone;
        end;
        { 组字串画在光标所在的视口行上,不管光标此刻显不显示(闪烁、DECTCEM) }
        if FInPreedit and (FPreedit <> '') and (r = CursorViewRow) then
        begin
          Overlay.Preedit := FPreedit;
          Overlay.PreeditCol := Min(buf.X, FCore.Cols - 1);
        end
        else
        begin
          Overlay.Preedit := '';
          Overlay.PreeditCol := -1;
        end;
        YPhase := False;
        Valid := True;
      end;
    { 同步输出攒着(3 期「攒着的一起画」):不搬也不画,只贴图——帧级变化照旧整屏 }
    if FSyncHolding and not allNew then
      holding := True
    else
      holding := False;
    moved := nil;
    { rows are drawn and moved inside the frame only: a grid still waiting to be applied
      (header) can be larger than the client area for a moment }
    inner := Rect(ins.Left, ins.Top, Max(ins.Left, w - ins.Right - ScrollBarWidth(APPI)), Max(ins.Top, h - ins.Bottom));
    FSurface.ClipRect := inner;
    if not holding then
    begin
      SetLength(rowAction, FCore.Rows);
      SetLength(moved, FCore.Rows);
      period := TyTermGlyphPeriodY;
      for r := 0 to FCore.Rows - 1 do
      begin
        moved[r] := -1;
        if ins.Top + r * FMetrics.CellH >= h then
        begin
          rowAction[r] := 0;                  { 在表面外:不画,键作废 }
          FNewKeys[r].Valid := False;
          Continue;
        end;
        if SameRowKey(FRowKeys[r], FNewKeys[r]) then
        begin
          rowAction[r] := 0;
          FNewKeys[r].YPhase := FRowKeys[r].YPhase;
          Continue;
        end;
        rowAction[r] := 2;
        for s := 0 to FCore.Rows - 1 do
          if (s <> r) and SameRowKey(FRowKeys[s], FNewKeys[r])
            and ((not FRowKeys[s].YPhase) or ((r - s) * FMetrics.CellH mod period = 0)) then
          begin
            rowAction[r] := 1;
            moved[r] := s;
            FNewKeys[r].YPhase := FRowKeys[s].YPhase;
            Break;
          end;
      end;
      MoveRows(moved, ins);
      incomplete := False;
      for r := 0 to FCore.Rows - 1 do
      begin
        if rowAction[r] <> 2 then Continue;
        FRowPainter.SelFrom := FNewKeys[r].Overlay.SelFrom;
        FRowPainter.SelTo := FNewKeys[r].Overlay.SelTo;
        FRowPainter.LinkFrom := FNewKeys[r].Overlay.LinkFrom;
        FRowPainter.LinkTo := FNewKeys[r].Overlay.LinkTo;
        if not FRowPainter.PaintRow(FSurface, ins.Left, ins.Top + r * FMetrics.CellH, buf.GetLine(buf.YDisp + r),
          FCore.Cols, FNewKeys[r].Overlay.CursorCol, FNewKeys[r].Overlay.CursorShape) then
        begin
          { 光栅化超了这一帧的预算:这一行缺字,键作废,下一帧整行重画 }
          FDirty[r] := True;
          FNewKeys[r].Valid := False;
          incomplete := True;
        end;
        FNewKeys[r].YPhase := FRowPainter.RowUsesYPhase;
        Inc(FRowsPaintedFrame);
        if FNewKeys[r].Overlay.Preedit <> '' then
          PaintPreedit(APPI);
      end;
      for r := 0 to FCore.Rows - 1 do
      begin
        if rowAction[r] = 1 then Inc(FRowsMoved);
        { a row cut by the surface's bottom has pixels nobody drew: never kept, never a
          source to move from }
        if ins.Top + (r + 1) * FMetrics.CellH > inner.Bottom then
          FNewKeys[r].Valid := False;
        FRowKeys[r] := FNewKeys[r];
      end;
      { 画了或搬了、却不在这次画布裁剪区里的行:补一次失效,下一次 Paint 把它贴上去 }
      if ACanvas <> nil then
      begin
        clip := ACanvas.ClipRect;
        if not IsRectEmpty(clip) then
          for r := 0 to FCore.Rows - 1 do
            if (rowAction[r] <> 0) and ((ARect.Top + ins.Top + r * FMetrics.CellH < clip.Top)
              or (ARect.Top + ins.Top + (r + 1) * FMetrics.CellH > clip.Bottom)
              or (ARect.Left + ins.Left < clip.Left)
              or (ARect.Left + ins.Left + FCore.Cols * FMetrics.CellW > clip.Right)) then
              InvalidateRows(r, r);
      end;
    end
    else
      incomplete := False;
    FSurface.NoClip;
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
      FLastFrameCostMs := FLastPaintMs - frameStart;
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

procedure TTyTerminalView.MoveRows(const AFrom: TIntegerDynArray; const AInsets: TRect);
var
  r, y, k, w, h, sy, dy, cnt, d, first, last, step: Integer;
  uniform: Boolean;
begin
  cnt := 0;
  uniform := True;
  d := 0;
  first := -1;
  last := -1;
  for r := 0 to High(AFrom) do
    if AFrom[r] >= 0 then
    begin
      if cnt = 0 then
      begin
        d := AFrom[r] - r;
        first := r;
      end
      else if AFrom[r] - r <> d then
        uniform := False;
      last := r;
      Inc(cnt);
    end;
  if cnt = 0 then Exit;
  { inside the frame (RenderTo's clip): a waiting grid larger than the client area }
  w := Min(FCore.Cols * FMetrics.CellW, FSurface.ClipRect.Right - AInsets.Left);
  h := FMetrics.CellH;
  if w <= 0 then Exit;
  if uniform then
  begin
    { every row moves by the same d (a scroll): each pixel row straight to its place, in
      the order that reads every source before it is written over -- upward (d > 0, the
      sources below) from the top, downward from the bottom. One copy, no scratch. }
    if d > 0 then
    begin
      r := first;
      step := 1;
    end
    else
    begin
      r := last;
      step := -1;
    end;
    while (r >= first) and (r <= last) do
    begin
      if AFrom[r] >= 0 then
        for k := 0 to h - 1 do
        begin
          if step > 0 then y := k else y := h - 1 - k;
          dy := AInsets.Top + r * h + y;
          sy := dy + d * h;
          if (dy >= 0) and (dy < FSurface.Height) and (sy >= 0) and (sy < FSurface.Height) then
            Move((FSurface.ScanLine[sy] + AInsets.Left)^, (FSurface.ScanLine[dy] + AInsets.Left)^,
              w * SizeOf(TBGRAPixel));
        end;
      Inc(r, step);
    end;
    FSurface.InvalidateBitmap;
    Exit;
  end;
  if Length(FMoveScratch) < cnt * h * w then
    SetLength(FMoveScratch, cnt * h * w);
  { 源行先全部拷进草稿:一行的目标可能是另一行的源(地雷 11:自下而上存的位图也按
    ScanLine 逐像素行拷,不在原地重叠拷) }
  k := 0;
  for r := 0 to High(AFrom) do
    if AFrom[r] >= 0 then
      for y := 0 to h - 1 do
      begin
        sy := AInsets.Top + AFrom[r] * h + y;
        if (sy >= 0) and (sy < FSurface.Height) then
          Move((FSurface.ScanLine[sy] + AInsets.Left)^, FMoveScratch[k * w], w * SizeOf(TBGRAPixel));
        Inc(k);
      end;
  k := 0;
  for r := 0 to High(AFrom) do
    if AFrom[r] >= 0 then
      for y := 0 to h - 1 do
      begin
        dy := AInsets.Top + r * h + y;
        if (dy >= 0) and (dy < FSurface.Height) then
          Move(FMoveScratch[k * w], (FSurface.ScanLine[dy] + AInsets.Left)^, w * SizeOf(TBGRAPixel));
        Inc(k);
      end;
  FSurface.InvalidateBitmap;
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
  { 自定义方案下底色 / 字色用生效的 257 / 256(TyTerminalPreedit 的底色、字色本来就是
    --terminal-bg / -fg,方案的底上不能冒出一块主题色);下划线仍取主题 }
  if FActiveScheme = nil then
  begin
    if (tpBackground in st.Present) and (st.Background.Kind = tfkSolid) then bg := Cardinal(st.Background.Color) and $FFFFFF;
    if tpTextColor in st.Present then fg := Cardinal(st.TextColor) and $FFFFFF;
  end;
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
  { 失焦时一次按下还没收尾,而它的键已经松开(抬起落到了别处):照 MouseUp 收尾 }
  if (FRoute <> mrNone) and not (csDesigning in ComponentState) and not RouteButtonsHeld then
    ForgetPress;
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
  ApplyPendingGrid;
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

procedure TTyTerminalView.OfferPrimary;
var
  fmt: TClipboardFormat;
begin
  if PrimarySelection.OnRequest = @PrimaryRequest then Exit;
  fmt := CF_TEXT;
  PrimarySelection.SetSupportedFormats(1, @fmt);
  PrimarySelection.OnRequest := @PrimaryRequest;
end;

function TTyTerminalView.PrimaryRequestText: string;
begin
  SyncSelectionTrim;
  Result := FSelection.Text(LineEnding);
end;

procedure TTyTerminalView.PrimaryRequest(const RequestedFormatID: TClipboardFormat; Data: TStream);
var
  t: string;
begin
  if (RequestedFormatID = 0) or (Data = nil) then Exit;
  t := PrimaryRequestText;
  if t <> '' then
    Data.Write(t[1], Length(t));
end;

function TTyTerminalView.ClipboardHasText: Boolean;
begin
  Result := TyClipboardHasText;
end;

function TTyTerminalView.HeldMouseButtons: TShiftState;
begin
  Result := [];
  if GetKeyState(VK_LBUTTON) < 0 then Include(Result, ssLeft);
  if GetKeyState(VK_MBUTTON) < 0 then Include(Result, ssMiddle);
  if GetKeyState(VK_RBUTTON) < 0 then Include(Result, ssRight);
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

{$I tyControls.Terminal.View.Mouse.inc}

{$I tyControls.Terminal.View.Links.inc}

{$I tyControls.Terminal.View.Osc52.inc}

{$I tyControls.Terminal.View.Menu.inc}

{$I tyControls.Terminal.View.Selection.inc}

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
  ApplyPendingGrid;
  Result := FCore.Cols;
end;

function TTyTerminalView.GetRows: Integer;
begin
  ApplyPendingGrid;
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

procedure TTyTerminalView.SetMinContrast(AValue: Double);
var
  v: Double;
begin
  v := TyTermClampContrastRatio(AValue);
  if v = FMinContrast then Exit;
  FMinContrast := v;
  { 缓存的答案是按旧比值算的 }
  FContrastCache.Clear;
  FHalfContrastCache.Clear;
  DirtyAll;
end;

function TTyTerminalView.MinimumContrastRatioStored: Boolean;
begin
  Result := FMinContrast <> 1;
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

{ ---- 独立配色方案(6 期) ------------------------------------------------------------- }

procedure TTyTerminalView.SetColorSource(AValue: TTyTerminalColorSource);
begin
  if FColorSource = AValue then Exit;
  FColorSource := AValue;
  RequestSchemeNotify;
end;

procedure TTyTerminalView.SetColorScheme(AValue: TTyTerminalColorScheme);
begin
  { 对象属性要有 setter 才流式化(TTyHeader.Columns 的注释);Assign 发一次 OnChange }
  FColorScheme.Assign(AValue);
end;

procedure TTyTerminalView.SetDarkColorScheme(AValue: TTyTerminalColorScheme);
begin
  FDarkColorScheme.Assign(AValue);
end;

procedure TTyTerminalView.SetColorSchemePaired(AValue: Boolean);
begin
  if FColorSchemePaired = AValue then Exit;
  FColorSchemePaired := AValue;
  RequestSchemeNotify;
end;

procedure TTyTerminalView.SchemeChanged(Sender: TObject);
begin
  { 方案的修订号已经加了一:色表的键当场失效。没用到的那一边改了,键不变,通知回来时
    逐项比也是一样,不报、不重画 }
  RequestSchemeNotify;
end;

procedure TTyTerminalView.RequestSchemeNotify;
begin
  { 不当场 Invalidate:它当场 EnsureThemeCurrent、当场通知,连着设几项就是几条 2031 }
  if [csLoading, csDestroying] * ComponentState <> [] then Exit;
  if FNotifyQueued then Exit;
  FNotifyQueued := True;
  Inc(FSchemeNotifyRequests);
  Application.QueueAsyncCall(@AsyncNotifyScheme, 0);
end;

function TTyTerminalView.SideRevision(ADark: Boolean): Cardinal;
begin
  if FColorSource = tsrcTheme then
    Result := 0
  else if FColorSchemePaired and ADark then
    Result := FDarkColorScheme.Revision
  else
    Result := FColorScheme.Revision;
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
  begin
    { the waiting grid first: the cell is counted in it }
    ApplyPendingGrid;
    Result := CellRect(Min(FCore.Buffer.X, FCore.Cols - 1), FCore.Buffer.Y);
  end;
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

function TTyTerminalView.RowKeyOf(AViewRow: Integer): TTyTermRowKey;
begin
  if (AViewRow >= 0) and (AViewRow <= High(FRowKeys)) then
    Result := FRowKeys[AViewRow]
  else
    Result := Default(TTyTermRowKey);
end;

procedure TTyTerminalView.ForgetPaintedRows;
var
  r: Integer;
begin
  for r := 0 to High(FRowKeys) do
    FRowKeys[r].Valid := False;
end;

function TTyTerminalView.GlyphCache: TTyTermGlyphCache;
begin
  Result := FGlyphCache;
end;

function TTyTerminalView.ContrastCache: TTyTermContrastCache;
begin
  Result := FContrastCache;
end;

function TTyTerminalView.HalfContrastCache: TTyTermContrastCache;
begin
  Result := FHalfContrastCache;
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

function TTyTerminalView.ActiveColorScheme: TTyTerminalColorScheme;
begin
  EnsurePalette;
  Result := FActiveScheme;
end;

function TTyTerminalView.ThemeGroundIsDark: Boolean;
begin
  EnsurePalette;
  Result := FThemeGroundDark;
end;

function TTyTerminalView.NotifyQueued: Boolean;
begin
  Result := FNotifyQueued;
end;

function TTyTerminalView.SchemeNotifyRequests: Integer;
begin
  Result := FSchemeNotifyRequests;
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
