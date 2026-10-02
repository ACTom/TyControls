unit tyControls.ToolWindows;
{$mode objfpc}{$H+}

{ IDE 工作台的侧栏 / 底栏。设计定稿见
  docs/superpowers/specs/2026-09-17-toolwindow-workbench-design.md。
  窗口、操作区、栏、栏的手势引擎(内部类)和 manager 的基类 TTyCustomToolWindowManager 同在
  一个单元:它们互相调对方的私有成员(注册 / 注销、切页、静默换父、拖动状态……),分开的话这些
  成员都得公开。manager 本身(MoveWindow、队列、布局的保存 / 读取 / 时机、跨栏拖动的命中测试)
  在 tyControls.ToolWindows.Manager,只经基类的 protected 方法碰栏和窗口的内部。
  实现段里两块 include 进来:角标(tyControls.ToolWindows.Badge.inc)、隐藏侧栏的放置预览
  (tyControls.ToolWindows.DropPreview.inc)—— 它们同样要碰私有成员,所以不拆成单元。 }

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LMessages, ImgList, Menus,
  Forms,     { TCustomForm:拖动期间 Screen 的「活动窗体换了」处理器 }
  tyControls.Types, tyControls.Base, tyControls.Component, tyControls.Painter,
  tyControls.StyleModel, tyControls.Controller, tyControls.StrConsts,
  tyControls.Button,   { TTyBadgeDisplayEvent、TyBidiFlipBadgePosition:角标照 TTyButton(spec §8.1) }
  tyControls.ToolWindows.Layout;      { 纯规则 / 几何:标题行、图标条、槽位、阈值 }

const
  { 长度 token。经典值必须等于这里的 Def —— light.tycss 的 :root 里写同一个数,
    不然加 token 这一步会悄悄给控件换一套尺寸。 }
  TyToolWindowHeaderHeightVar = '--toolwindow-header-height';
  TyToolWindowHeaderHeightDef = 26;
  TyToolWindowHeaderPadVar    = '--toolwindow-header-pad';
  TyToolWindowHeaderPadDef    = 6;
  TyToolWindowHeaderGapVar    = '--toolwindow-header-gap';
  TyToolWindowHeaderGapDef    = 4;
  TyToolWindowTabPadVar       = '--toolwindow-tab-pad';
  TyToolWindowTabPadDef       = 10;
  TyToolWindowTabAreaMinVar   = '--toolwindow-tab-area-min';
  TyToolWindowTabAreaMinDef   = 50;
  TyToolWindowIndicatorSizeVar = '--toolwindow-indicator-size';
  TyToolWindowIndicatorSizeDef = 2;
  TyToolWindowStripIndicatorSizeVar = '--toolwindow-strip-indicator-size';
  TyToolWindowStripIndicatorSizeDef = 2;
  TyToolWindowButtonSizeVar   = '--toolwindow-button-size';
  TyToolWindowButtonSizeDef   = 22;
  TyToolWindowGlyphSizeVar    = '--toolwindow-glyph-size';
  TyToolWindowGlyphSizeDef    = 16;
  TyToolWindowContentMinVar   = '--toolwindow-content-min';
  TyToolWindowContentMinDef   = 120;
  TyToolWindowStripSizeVar    = '--toolwindow-strip-size';
  TyToolWindowStripSizeDef    = 36;
  TyToolWindowStripItemSizeVar = '--toolwindow-strip-item-size';
  TyToolWindowStripItemSizeDef = 36;
  TyToolWindowEdgeSizeVar     = '--toolwindow-edge-size';
  TyToolWindowEdgeSizeDef     = 4;
  TyToolWindowDropSizeVar     = '--toolwindow-drop-size';
  TyToolWindowDropSizeDef     = 2;

  { 展开尺寸的出厂值。侧栏与底栏共用一个数:Pascal 的 published default 只能是常量,
    按 Placement 分两个数会让 .lfm 省略掉其中一侧的值、加载后变成另一侧的默认。
    名字不叫 ...Def —— 本库的 ...Var / ...Def 成对只用于「主题 token 与它的回落值」。 }
  TyToolWindowDefaultExpandedSize = 240;

  { 本单元自己解析的样式类型键(spec §12)。 }
  TyToolWindowKey                = 'TyToolWindow';
  TyToolWindowTabRowKey          = 'TyToolWindowTabRow';
  TyToolWindowTabKey             = 'TyToolWindowTab';
  TyToolWindowTabIndicatorKey    = 'TyToolWindowTabIndicator';
  TyToolWindowButtonKey          = 'TyToolWindowButton';
  TyToolWindowSeparatorKey       = 'TyToolWindowSeparator';
  TyToolWindowBarKey             = 'TyToolWindowBar';
  TyToolWindowActionsKey         = 'TyToolWindowActions';
  TyToolWindowHeaderKey          = 'TyToolWindowHeader';
  TyToolWindowStripKey           = 'TyToolWindowStrip';
  TyToolWindowStripItemKey       = 'TyToolWindowStripItem';
  TyToolWindowStripIndicatorKey  = 'TyToolWindowStripIndicator';
  TyToolWindowOverflowKey        = 'TyToolWindowOverflow';
  TyToolWindowEdgeKey            = 'TyToolWindowEdge';
  TyToolWindowDropIndicatorKey   = 'TyToolWindowDropIndicator';
  TyToolWindowNoteKey            = 'TyToolWindowNote';
  { E 期(spec §12):图标 / 标签上的角标、隐藏侧栏的放置预览。 }
  TyToolWindowBadgeKey           = 'TyToolWindowBadge';
  TyToolWindowDropZoneKey        = 'TyToolWindowDropZone';

  { 点击防抖(毫秒)。拖动阈值在 tyControls.ToolWindows.Layout。 }
  TyToolWindowClickGuardMs    = 300;

type
  TTyToolWindowPlacement = (twpLeft, twpRight, twpBottom);

  TTyCustomToolWindow = class;
  TTyToolWindow = class;
  TTyCustomToolWindowBar = class;
  TTyToolWindowBar = class;
  TTyCustomToolWindowActions = class;
  TTyToolWindowActions = class;
  TTyCustomToolWindowManager = class;

  { 操作区的可见子控件,Controls[] 顺序,与 TTyToolWindowFlowItems 一一对应。 }
  TTyToolWindowKids = array of TControl;

  { GetStyleTypeKey 在 TTyCustomControl 上是 abstract,不覆写就等于注册了一个
    「一解析样式就抛 EAbstractError」的类 —— 而 RegisterClass 已经把它交给流式化了。
    类型键是契约不是实现,一开始就钉死。 }
  TTyCustomToolWindow = class(TTyCustomControl)
  private
    FImageName: string;           { 持久键,在所在栏的生效列表里按名字解析 }
    FImageIndex: Integer;         { 最近一次按序号写进来的值;名字给不出答案时的回落 }
    { 按序号写进来、还没换成名字的那一次(没有栏 / 栏没有列表 / 栏正在流式加载)。 }
    FImageIndexPending: Boolean;
    FStripHint: TTranslateString;
    { 图标条上对这个窗口最近一次**真正执行**的点击动作的时刻(栏的 TickNow;0 = 没有)。
      防抖按窗口记(spec §9.3):点 A 之后马上点 B 照常生效。 }
    FLastStripClick: QWord;
    FOnShow: TNotifyEvent;
    FOnHide: TNotifyEvent;
    { 标题行高的 token 那一项的缓存,键 = (PPI, model 身份, 主题版本, RTL, 标题行模式)。
      「有没有缓存」单拿一个布尔答,不拿 -1 当哨兵:token 是度量值,而 TyEvalLength
      不钳(Css.Values.pas:373),皮肤或 StyleOverride 里写 -1px 就真的解析成 -1 ——
      哨兵一旦跟真值撞上,缓存永远命中不了,Invalidate 里「上一次有值吗」也从此恒假,
      之后任何一次换主题都不再重排。操作区那一项不进这里,见 HeaderHeightAt。 }
    FHeaderPxCache: Integer;
    { 同一把键下标题行底线的粗细(设备像素,0 = 没有)。跟 token 一起缓存、一起比:换主题
      只带来一次裸 Invalidate,底线出现 / 消失而 token 没变时也得重排。 }
    FHeaderRuleCache: Integer;
    FHeaderPxValid: Boolean;
    FHeaderPxPPI: Integer;
    FHeaderPxVer: Cardinal;
    FHeaderPxAnchor: TObject;
    FHeaderPxRTL: Boolean;
    FHeaderPxMode: TTyToolWindowHeaderMode;
    FRelayouting: Boolean;
    { 上一次对齐时标题行的样子(那一条 + 整套几何)。操作区变宽 / 变高 / 被藏起来,
      标题行跟着变,而窗口尺寸一个像素没动 —— 缓存自己看不出来,见 AlignControls。 }
    FAlignedRow: TRect;
    FAlignedGeom: TTyToolWindowHeaderGeom;
    { 探针的底:最近一次写 Visible 那一刻 csNoDesignVisible 在不在(见 SetVisible)。 }
    FNoDesignVisibleAtShow: Boolean;
    { 底栏当前页:此刻的标题行几何跟上一次对齐(或上一次请重排)时不一样了 —— 行高没变、
      操作区却要挪(换主题改了按钮尺寸、标签区下限、分隔线、标签宽)。答 True 时已经把
      这一份记进 FAlignedGeom。 }
    function BottomGeomDrifted: Boolean;
    function ImageIndexIsStored: Boolean;
    function GetImageIndex: TImageIndex;
    procedure SetImageIndex(AValue: TImageIndex);
    procedure SetImageName(const AValue: string);
    procedure SetStripHint(const AValue: TTranslateString);
    { 挂起的 ImageIndex 换成生效列表里那一格的名字(照 TTyTabSheet.ResolveImageIndex)。
      没挂起、没有栏、栏没有列表、栏正在流式加载 —— 都不动,留给之后那一次:
      加载中不解析,是因为这时候栏的列表引用谁先 fixup 上谁就是答案(spec §8),
      栏的 Loaded 统一解析。 }
    procedure ResolveImageIndex;
    { 图标条画的是名字 / 序号、提示读的是 StripHint:改了要让所在栏重画。 }
    procedure InvalidateBar;
    function GetBar: TTyCustomToolWindowBar;
    function GetActions: TTyCustomToolWindowActions;
    function GetWindowIndex: Integer;
    procedure SetWindowIndex(AValue: Integer);
    function HeaderTokenPx: Integer;
    { 侧栏标题行底线的粗细,设备像素,按给定 PPI:TyToolWindowHeader 解析出可见边框
      (border-color + border-width)才有,宽取 border-width,不低于 1 —— 写法照图标条的界线。
      底栏 / 孤儿答 0。 }
    function HeaderRuleAt(APPI: Integer): Integer;
    function HeaderRuleUncached(APPI: Integer): Integer;
    function HeaderHeightAt(APPI: Integer): Integer;
    function HeaderRowIn(const AClient: TRect; APPI: Integer): TRect;
    function ActionsPreferredSize(APPI: Integer): TSize;
    { 设计期孤儿的提示行(spec §3.2),AClient 坐标:顶上一行,高 = --toolwindow-header-height
      (跟栏的提示行、标题行是同一个「一行字加上下留白」的尺寸),钳在客户区里。不是设计期、
      在栏里时为空矩形。AdjustClientRect 让位、RenderTo 画提示、OrphanNoteRect 答探针,
      问的都是这一处。 }
    function OrphanNoteRectIn(const AClient: TRect; APPI: Integer): TRect;
  private
    { --- 底栏标签行的输入(spec §3.6):当前页把标签行区域的输入转给栏。 --- }
    { 哪几个键的这一次按下落在标签行区域里:这个键的整次点击(MouseUp,左键还有 Click /
      DblClick)都归标签行,不给用户的处理器 —— 按下落在哪决定归谁(spec §3.6)。按键分开记:
      左键拖动中右键按在正文,不许把左键那一次改判成「归用户」。每次按下重写那个键的一位。
      「手势在不在我身上」不在这里记,只问栏的引擎(HeaderCapturedBy)。 }
    FRowPresses: set of TMouseButton;
    { 按下消息自己带的坐标,只在那一拍有效:LCL 在 WndProc 里、MouseDown 之前调 BeginAutoDrag,
      手上没有坐标(同栏的 FAutoDragPos)。 }
    FPressPos: TPoint;
    FPressPosValid: Boolean;
    procedure LMCancelMode(var Message: TLMessage); message LM_CANCELMODE;
    { 标签行区域里的提示问栏(HeaderHint);区域外走继承。**不改**窗口的 ShowHint(spec §3.6):
      LCL 只把 CM_HINTSHOW 发给 ShowHint 为真的那一级控件。 }
    procedure CMHintShow(var Message: TLMessage); message CM_HINTSHOW;
    { 设计期(spec §3.6 / §7.4):标签行区域让位给栏 —— 答 1,设计器跳过本窗口、落到栏上,
      栏的 CM_DESIGNHITTEST 在栏坐标里认标签。别处、翻不了坐标时答 0(「在我身上」,也是
      没有这个处理器时 TControl 的答案)。写法照 TTyShape.CMMaskHitTest。本窗口的
      CM_DESIGNHITTEST 不改:窗口本身在设计期不接标签行的手势。 }
    procedure CMMaskHitTest(var Message: TCMHitTest); message CM_MASKHITTEST;
    { 运行时从一类栏直接挪到另一类栏(侧 ↔ 底)?见 SetParent。 }
    function MovesAcrossBarKinds(AOld, ANew: TWinControl): Boolean;
    { 这一次改 Parent 是「运行时同类栏之间直接改 Parent」,要走 CommitCrossMove(spec §3.2)。 }
    function BooksDirectMove(AOld, ANew: TWinControl): Boolean;
  private
    { MoveWindow / 布局应用自己换父时置上:SetParent 看见它就跳过「直接改 Parent」的簿记
      (spec §3.2),那些路径自己管激活、展开、事件。 }
    FQuietMove: Boolean;
  private
    { --- 角标(spec §8.1,E 期)。数字由窗口内容决定,所以在窗口上;窗口换栏,角标跟着走。 --- }
    FShowBadge: Boolean;
    FBadgeValue: Integer;
    FBadgeDot: Boolean;
    FOnBadgeDisplay: TTyBadgeDisplayEvent;
    procedure SetShowBadge(AValue: Boolean);
    procedure SetBadgeValue(AValue: Integer);
    procedure SetBadgeDot(AValue: Boolean);
    { 角标变了:侧栏重画;底栏丢标签宽缓存、重画标签行(标签宽变了,B 期收尾的漂移检查会把
      当前页的操作区跟上)。 }
    procedure BadgeChanged;
  protected
    FPaintCache: TTyPaintCache;      { protected:测试要能问「重渲染了没有」 }
    { > 0 = 这一批 Visible 切换不算「显示 / 隐藏」,见 BeginSilentVisibility。 }
    FSilentVisibility: Integer;
    function GetStyleTypeKey: string; override;
    procedure TextChanged; override;
    procedure AdjustClientRect(var ARect: TRect); override;
    { spec §3.2:拒绝工具窗口和栏,防止窗口套窗口。 }
    function ChildClassAllowed(ChildClass: TClass): Boolean; override;
    procedure AlignControls(AControl: TControl; var RemainingClientRect: TRect); override;
    { 第一个操作区摆进标题行、多出来的摆到正文左上角;别的子控件走继承。 }
    procedure CustomAlignPosition(AControl: TControl; var ANewLeft, ANewTop, ANewWidth,
      ANewHeight: Integer; var AlignRect: TRect; AlignInfo: TAlignInfo); override;
    procedure AutoAdjustLayout(AMode: TLayoutAdjustmentPolicy;
      const AFromPPI, AToPPI, AOldFormWidth, ANewFormWidth: Integer); override;
    procedure CMBiDiModeChanged(var Msg: TLMessage); message CM_BIDIMODECHANGED;
    { 窗口自己的 Enabled 变了(spec §3.7):图标 / 标签的样子、手势、底栏的「让出标签行」都跟着
      变,交给栏。先调继承 —— LCL 在那里禁用 / 启用原生句柄、挪走焦点(wincontrol.inc:6753-6763),
      不调就是 [[swallowed-cm-message-inherited]]。禁用时焦点原来在里面:照收起那一路交给栏后面
      的控件(spec §5.3),不让它掉到窗体本身。 }
    procedure CMEnabledChanged(var Message: TLMessage); message CM_ENABLEDCHANGED;
    { 全库 76 处 RenderTo 里 71 处是 protected,两个近亲 TTyTabSheet / TTyCard 也是:
      画自己不是给外面用的接口。测试走探针子类。 }
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { 栏切页就是开关 Visible(ShowWindowNow / HideWindowNow),所以这条消息就是本窗口的激活边 ——
      与 TCustomPage / TTyTabSheet 发 OnShow / OnHide 的是同一个钩子。 }
    procedure CMVisibleChanged(var Msg: TLMessage); message CM_VISIBLECHANGED;
    procedure DoShow; virtual;
    procedure DoHide; virtual;
    { 照 TTyTabSheet.SetParent:先记旧父控件 → 继承 → 从旧栏注销(任一方 csDestroying
      时跳过,释放那条路由 Notification 管)→ 注册到新栏 → 重排标题行(spec §3.2)。
      运行时从侧栏直接挪到底栏(或反过来)在继承之前抛 EInvalidOperation。运行时挪到另一条
      同类栏跟 MoveWindow 走同一条 CommitCrossMove(目标栏激活并展开、焦点还回去、事件按
      spec §6.6 的顺序、同一 manager 下发 OnWindowMoved),不问否决。 }
    procedure SetParent(NewParent: TWinControl); override;
    { 对外设 Visible 经栏路由(spec §3.3):运行时 True = 激活并展开,对当前页 False = 收起;
      设计期 True 只激活。栏自己切的(FBarSwitching)照写,并记探针。 }
    procedure SetVisible(Value: Boolean); override;
    { 窗口不重写 Loaded 去收 spec §10.5 的尾:FPC 的读取器先把子控件加进 Loaded 列表、再加父控件
      (reader.inc:1004-1019),窗口的 Loaded 永远在它的栏之前,那时栏还在 csLoading,收不了尾。
      窗口也不会跟它的栏分在两个流里(栏只收窗口,窗口的父控件在同一个流里)。收尾只靠 manager
      和栏的 Loaded(TTyToolWindowManager.TryFinishLoading)。 }
    { 推送链的第二段:窗口 → **每一个**操作区。多出来的那些设计期要按它画提示。 }
    procedure SetController(AValue: TTyStyleController); override;
    { 有些 Visible 切换不是用户眼里的「显示 / 隐藏」,spec §6.6 要求它们不发
      OnShow / OnHide:栏在 Loaded 里应用 ActiveIndex、加载结束时 manager 应用挂起的布局计划
      (TTyToolWindowManager.TryFinishLoading)。
      用户看得见的切页、收起、展开**照发**。唯一的调用者是 TTyToolWindowBar.BeginSilent /
      EndSilent,它把栏里的**每一个**窗口整批包起来(静默期间注册进来的也包上)。
      计数而不是布尔:布局应用会套着切页,一个布尔会被里层提前解除。
      csLoading 挡不住这两个 —— 发生时 csLoading 已经清了。

      **调用方必须 try/finally**。负方向钳住了(EndSilentVisibility 不减到 0 以下),
      正方向钳不住:Begin 与 End 之间任何一处抛异常,计数就卡在 0 以上,这个窗口的
      OnShow / OnHide 从此再也不响 —— 而它是静默的,没有一条断言会指向那里。 }
    procedure BeginSilentVisibility;
    procedure EndSilentVisibility;
    { 标签行区域 = 标题行减去操作区(窗口客户区坐标,含标签之间和后面的空白)。只有在栏里、
      底栏模式下才可能为真。下面所有「在不在区域里」都问这一处。 }
    function InTabRowRegion(X, Y: Integer): Boolean;
    { 同上,几何由调用方给(此刻客户区下的 HeaderGeomAt):一次事件里已经排过一份的,不再排。 }
    function InTabRowRegionOf(const AGeom: TTyToolWindowHeaderGeom; X, Y: Integer): Boolean;
    { 按下消息的坐标记给 BeginAutoDrag、并记下这一次按下归不归标签行:LCL 在 WndProc 里先调
      BeginAutoDrag、再调 MouseDown,等到 MouseDown 才记就晚了。 }
    procedure WndProc(var TheMessage: TLMessage); override;
    { 区域内:不调继承(用户的 OnMouseDown 不触发),落在部件上才转给栏;none 只吞。 }
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    { 转给栏(手势中不论位置;否则区域内的部件上转移动、别处转离开),然后照常调继承。 }
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    { 这一次按下归标签行 → 不调继承;手势中转给栏,作为最后一句(可能藏掉自己)。 }
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure Click; override;
    procedure DblClick; override;
    { 区域内的滚轮吞掉。MousePos 是客户区坐标:win32callback.inc:1711-1712 把 WM_MOUSEWHEEL
      的屏幕坐标换成客户区,TControl.WMMouseWheel 经 GetMousePosFromMessage(control.inc:1931-1940,
      宽高 ≤ 32767 时直接用消息坐标)交过来。 }
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    { 区域内的右键:Handled,不调继承;落在标签上时交给栏(spec §6.8 的同一条路)。
      键盘菜单键的 (-1, -1) 不在区域里,走继承。 }
    procedure DoContextPopup(MousePos: TPoint; var Handled: Boolean); override;
    { 标签行不起 LCL 拖动(DragMode = dmAutomatic 时任何位置左键按下都会起);位置取按下消息
      记下的那一个,没有才问指针。 }
    procedure BeginAutoDrag; override;
    { 挡在 LCL 自动拖动前面的那一道闸之后;测试探针重写它数次数。 }
    procedure StartLclAutoDrag; virtual;
    { 指针此刻在本控件客户区里的位置;没有句柄(无头)答 False。测试探针重写它。 }
    function PointerInClient(out APoint: TPoint): Boolean; virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    { 操作区插进来时把自己的控制器推给它 —— 流式加载、粘贴、代码里 Parent := 都走这里。 }
    procedure InsertControl(AControl: TControl; Index: Integer); override;
    { 操作区离开:底栏的共用行高少了它那一项(spec §3.4)。 }
    procedure RemoveControl(AControl: TControl); override;
    procedure Invalidate; override;
    procedure Paint; override;
    procedure RelayoutHeader;
    function HeaderMode: TTyToolWindowHeaderMode;
    { 标题行排布的全部**输入**。要答案请用 HeaderGeomAt —— 它手上有客户区,钳得住
      行高;这里手上没有,答的是没钳过的那个。留在 public 是给断言 Pad / Gap / RTL
      的测试用的。
      这条记录里的**每一个**尺寸都按入参 APPI 缩放 —— 行高按 Font.PixelsPerInch、
      内距按 APPI 的话,真实路径上两者相等看不出来,而别的 PPI 传进来时同一条记录里
      就是两套尺度。 }
    function HeaderInput(APPI, ARowWidth: Integer): TTyToolWindowHeaderInput;
    { 标题行排布的**答案**,一处算 —— 绘制(RenderTo)与摆操作区(CustomAlignPosition)
      必须拿同一份几何。只共享输入、各自再跑一遍排布的话,
      画出来的和点得中的照样会错开。行高在这里钳进 AClient,所以控件比标题行还矮时
      操作区不会被摆到控件外面。照 TTyCard.LayoutAtPPI(Card.pas:181)。
      返回的几何是**行内局部坐标**(0,0 在行的左上角);AClient 只用来定行宽、钳行高。 }
    function HeaderGeomAt(const AClient: TRect; APPI: Integer): TTyToolWindowHeaderGeom;
    { 已有就返回第一个操作区,没有就建一个(spec §3.1 / §4):Owner 是窗口的 Owner
      (窗体拥有,设计期容器的契约),Parent 是本窗口,TabOrder 0。 }
    function EnsureActions: TTyCustomToolWindowActions;
    function HeaderHeightPx: Integer;
    function HeaderRowRect: TRect;
    function BodyRect: TRect;
    { 设计期孤儿提示的那一行(客户区坐标,按自己字体的 PPI);不是设计期孤儿时为空矩形。 }
    function OrphanNoteRect: TRect;
    { 把焦点给正文里第一个可聚焦的控件(protected 的 SelectFirst 的公开包装,spec §3.1)。 }
    procedure FocusFirst;
    { 设计期 CM_MASKHITTEST 的答案,(X, Y) 是本窗口客户区坐标(spec §3.6 / §7.4):标签行区域
      (标签、标签之间和后面的空白、溢出、分隔线、按钮)答 1 —— 设计器跳过本窗口、落到栏上,
      栏在栏坐标里认标签;操作区、正文、底栏以外答 0(「在我身上」)。CMMaskHitTest 只负责
      换坐标,答案一律问这里。 }
    function DesignMaskAnswerAt(X, Y: Integer): Integer;
    { 是不是所在栏的当前页(spec §3.1)。栏收起着时当前页照样是它 —— 这里答的是
      「栏认哪一页」,不是「此刻看不看得见」。不在栏里、栏在流式加载中(那时栏还没挑)答 False。
      底栏的标签行只由当前页代画(spec §7.1),问的就是这一处。 }
    function IsActive: Boolean;
    { 在所在栏的窗口里排第几(spec §9.9);不在栏里是 -1。写 = 栏内调顺序,钳到
      0..窗口数-1,跟拖放提交走同一条路(TTyToolWindowBar.ReorderWindow)。不进 .lfm:
      顺序就是 Controls 顺序,已经流过了。 }
    property WindowIndex: Integer read GetWindowIndex write SetWindowIndex;
    property Bar: TTyCustomToolWindowBar read GetBar;
    property Actions: TTyCustomToolWindowActions read GetActions;
    { 探针:最近一次写 Visible 那一刻 csNoDesignVisible 在不在 —— 真实状态的只读视图。
      栏切页必须先改这个标志再写 Visible(spec §5.1 第 2、3 步),顺序无头看不出来,
      只能从这里钉(TestDesignVisibleFlagIsSetBeforeVisible)。 }
    property NoDesignVisibleAtLastShow: Boolean read FNoDesignVisibleAtShow;
    { 此刻画不画角标、画什么(事件已经应用过,spec §8.1)。AText 在圆点模式下是 ''。
      没开 ShowBadge 时不调事件。 }
    function BadgeDisplay(out AText: string; out ADot: Boolean): Boolean;
    { OnBadgeDisplay 的答案变了(它看的外部状态变了,BadgeValue / ShowBadge / BadgeDot 都没动):
      控件自己看不出来,调这一句。侧栏重画图标条;底栏丢标签宽缓存、重画标签行(当前页的,或让出时
      栏自己的)—— 跟改这三个属性走的是同一条路。 }
    procedure InvalidateBadge;
    property Visible stored False;
    property TabOrder stored False;
    { 栏推给窗口、窗口再推给操作区;不进 .lfm(读进来的时机在注册之后,两边会漂开)。 }
    property Controller stored False;
    { 图标条上的图标**按名字** —— 持久键,在所在栏的 EffectiveImages 里解析。列表是本库的
      (TTyVirtualImageList 及其子类)时,名字挺得过列表调顺序。'' = 没有;外来的 LCL 列表
      没有名字,那时它不起作用,键是 ImageIndex。找不到这个名字就不画(-1),不回落到序号。 }
    property ImageName: string read FImageName write SetImageName;
    { ImageName 的**视图**(TTyTabSheet 的约定):读 = 名字在生效列表里的那一格,名字解析
      不出来时回落到最近一次写进来的序号;写 = 把那一格的名字记成 ImageName(在栏里、栏有
      列表、栏不在加载中时当场换,否则挂起,栏的 Loaded / 换列表 / 进栏时再换)。
      只在名字存不下这个选择时进流(ImageIndexIsStored)。类型是 ImgList.TImageIndex:
      LCL 的 TImageIndexPropertyEditor 就会顺着 Parent = 栏 → Images 挂上下拉。 }
    property ImageIndex: TImageIndex read GetImageIndex write SetImageIndex
      stored ImageIndexIsStored default -1;
    { 图标条提示;空的时候用 Caption,**不用 Hint**(见 TTyToolWindowBar.StripHintText)。
      类型是 TTranslateString 不是 string:LCL 的窗体翻译只认类型正好是它的属性
      (lcltranslator.pas:313),设计器里填的提示才进得了 .po(同 TTyRibbon.FileTabCaption)。 }
    property StripHint: TTranslateString read FStripHint write SetStripHint;
    { 切页的触发边是 Visible —— 栏把当前页显示出来、把上一页藏起来(spec §5.1),
      而这两个事件就从 CM_VISIBLECHANGED 发,名字、签名、触发边都同 TCustomPage。 }
    property OnShow: TNotifyEvent read FOnShow write FOnShow;
    property OnHide: TNotifyEvent read FOnHide write FOnHide;
    { 角标(spec §8.1),名字和语义照 TTyButton:ShowBadge 是总开关,开着时 0 也显示;> 99 显示
      '99+';OnBadgeDisplay 可以改文字或藏起来(会被频繁调用 —— 量标签宽、画、命中都可能问 ——
      不许有副作用;它的答案变了请调 InvalidateBadge —— 窗口自己的 Invalidate 不够:非当前页藏着,
      角标画在栏或当前页里)。BadgeDot 画一个圆点代替数字。侧栏画在图标右上角,底栏画在标签标题
      后面。不进布局串。 }
    property ShowBadge: Boolean read FShowBadge write SetShowBadge default False;
    property BadgeValue: Integer read FBadgeValue write SetBadgeValue default 0;
    property BadgeDot: Boolean read FBadgeDot write SetBadgeDot default False;
    property OnBadgeDisplay: TTyBadgeDisplayEvent read FOnBadgeDisplay write FOnBadgeDisplay;
  published
    property Left stored False;
    property Top stored False;
    property Width stored False;
    property Height stored False;
  end;

  { TTyToolWindow publishes TTyCustomToolWindow's properties; everything lives in TTyCustomToolWindow. }
  TTyToolWindow = class(TTyCustomToolWindow)
  published
    property Version;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property TabOrder;
    property TabStop;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseWheel;
    property OnMouseWheelUp;
    property OnMouseWheelDown;
    property OnContextPopup;
    property OnResize;
    property OnChangeBounds;
    property AutoSize;
    property BorderWidth;
    property ChildSizing;
    property DragMode;
    property DragKind;
    property DragCursor;
    property OnDragOver;
    property OnDragDrop;
    property OnStartDrag;
    property OnEndDrag;
    property OnMouseWheelHorz;
    property OnMouseWheelLeft;
    property OnMouseWheelRight;
    property OnShowHint;
    property PopupMenu;
    property Constraints;
    property BorderSpacing;
    property ParentShowHint;
    property Action;
    property OnPaint;
    property OnKeyDown;
    property OnKeyUp;
    property OnKeyPress;
    property OnUTF8KeyPress;
    property OnEnter;
    property OnExit;
    property OnEditingDone;
    property StyleClass;
    property StyleOverride;
    property Controller;
    property Caption;
    property ImageName;
    property ImageIndex;
    property StripHint;
    property OnShow;
    property OnHide;
    property ShowBadge;
    property BadgeValue;
    property BadgeDot;
    property OnBadgeDisplay;
  end;

  { 标题行尾端的操作区(spec §4)。只由组件编辑器的「添加操作区」或 EnsureActions 建,
    位置和尺寸永远由所在窗口排:Align 钉死 alCustom,Align / Anchors 不 published;
    AutoSize、ChildSizing、BorderSpacing 在这个类上不起作用,子控件由它自己排成一排。 }
  TTyCustomToolWindowActions = class(TTyCustomControl)
  private
    FInLayout: Boolean;
    { 上一次 AdjustSize 时窗口拿去用的尺寸(按自己字体的 PPI;自己看不见时是 0,没挂在窗口里
      时不记):变了才通知所在底栏(spec §3.4)。 }
    FLastPreferred: TSize;
    function IsBoundsStored: Boolean;
    function IsUsedByWindow: Boolean;
    function HasVisibleChild: Boolean;
    function MetricPx(const AName: string; ADefault, APPI: Integer): Integer;
    { 可见子控件(Controls[] 顺序)和它们在 APPI 下的流输入 —— 一处筛、一处换算,
      排子控件(AlignControls)和量那一排(RowSizeAt)拿的是同一份。 }
    function FlowInput(APPI: Integer; out AKids: TTyToolWindowKids): TTyToolWindowFlowItems;
    { 子控件那一排的尺寸;一个可见子控件都没有就是 (0, 0),设计期也一样(方槽不算)。 }
    function RowSizeAt(APPI: Integer): TSize;
    function NoteText: string;
    function NoteStyle: TTyStyleSet;
    { 提示离前导边多远:有子控件时排在那一排后面(raw 宽 + gap),没有就是一个 pad。
      尺寸下限和提示的框都从这里取,两边不会各算各的。 }
    function NoteLeadAt(APPI: Integer): Integer;
    { 提示的框,AClient 坐标;不画提示时是空矩形。RTL 整体按宽镜像。 }
    function NoteRectIn(const AClient: TRect; APPI: Integer): TRect;
    { 设计期多余操作区 / 孤儿的最小尺寸:
      (提示前导距 + 提示宽 + pad) × max(raw 高, token)。 }
    function StrayDesignSize(APPI: Integer): TSize;
  protected
    function GetStyleTypeKey: string; override;
    procedure SetAlign(Value: TAlign); override;
    { 设计期多余的、孤儿的:尺寸不低于 StrayDesignSize,提示才看得全。运行时它们不露面,不碰。 }
    procedure ConstrainedResize(var MinWidth, MinHeight, MaxWidth, MaxHeight: TConstraintSize); override;
    function ChildClassAllowed(ChildClass: TClass): Boolean; override;
    procedure AlignControls(AControl: TControl; var RemainingClientRect: TRect); override;
    procedure CalculatePreferredSize(var PreferredWidth, PreferredHeight: Integer;
      WithThemeSpace: Boolean); override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  public
    constructor Create(AOwner: TComponent); override;
    { 运行时,所在窗口不认的那一个(多出来的、孤儿)不露面。派生而不是去写 Visible:
      写了就会进 .lfm,而且第一个被删掉之后第二个也回不来。 }
    function IsControlVisible: Boolean; override;
    procedure Paint; override;
    { 底栏统一行高的通知链(spec §3.4)。子控件增删、显隐、改尺寸、只改 Constraints 都走到
      这里(InsertControl / RemoveControl / 子控件的 AdjustSize 与 DoConstraintsChange →
      Parent.AdjustSize,wincontrol.inc:6416, 6459、control.inc:1520-1522, 4639-4640)——
      所在窗口藏着也一样:TControl.AdjustSize 向上传要看的是**子控件**自己可见。
      首选尺寸变了就告诉所在窗口的栏。 }
    procedure AdjustSize; override;
    { raw 首选尺寸,设备像素,按给定 PPI —— 窗口排标题行、LCL 的 GetPreferredSize、
      自己排子控件,问的都是这一处。**不**走 LCL 的 GetPreferredSize:那边有缓存,
      InsertControl 不作废它(wincontrol.inc:6392),而且答不了别的 PPI。
      运行时一个可见子控件都没有 → (0, 0);设计期空着 → 边长为 token 的方槽。 }
    function PreferredSizeAt(APPI: Integer): TSize;
    { 设计期提示画在哪里(客户区坐标,按自己字体的密度)—— Paint 画提示用的就是这个框。
      窗口认的那一个、以及运行时,答空矩形。 }
    function NoteRect: TRect;
    { 由窗口推送,不进 .lfm(同 TTyToolWindow)。 }
    property Controller stored False;
  published
    { 在窗口里由标题行排出来;孤儿的位置是用户摆的,照常存。 }
    property Left stored IsBoundsStored;
    property Top stored IsBoundsStored;
    property Width stored IsBoundsStored;
    property Height stored IsBoundsStored;
  end;

  { TTyToolWindowActions publishes TTyCustomToolWindowActions's properties; everything lives in TTyCustomToolWindowActions. }
  TTyToolWindowActions = class(TTyCustomToolWindowActions)
  published
    property Version;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property TabOrder;
    property TabStop;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseWheel;
    property OnMouseWheelUp;
    property OnMouseWheelDown;
    property OnContextPopup;
    property OnResize;
    property OnChangeBounds;
    property AutoSize;
    property BorderWidth;
    property ChildSizing;
    property DragMode;
    property DragKind;
    property DragCursor;
    property OnDragOver;
    property OnDragDrop;
    property OnStartDrag;
    property OnEndDrag;
    property OnMouseWheelHorz;
    property OnMouseWheelLeft;
    property OnMouseWheelRight;
    property OnShowHint;
    property PopupMenu;
    property Constraints;
    property BorderSpacing;
    property ParentShowHint;
    property Action;
    property OnPaint;
    property OnKeyDown;
    property OnKeyUp;
    property OnKeyPress;
    property OnUTF8KeyPress;
    property OnEnter;
    property OnExit;
    property OnEditingDone;
    property StyleClass;
    property StyleOverride;
    property Controller;
  end;

  { 栏自己那几项主题尺寸(设备像素):图标条宽(底栏为 0)、边缘区宽、单边 chrome、
    内容区下限、设计期提示行高。下限也在这里:推导按它钳内容项,只换
    --toolwindow-content-min 的主题也得重推。提示行高(借 --toolwindow-header-height)同理:
    设计期的漏入 / 冲突提示行从内容区底部扣,只换它的主题也得重排。
    NoteRow 在运行时还兼一份差事:它就是 --toolwindow-header-height 这个 token,而让出来的标签行
    (spec §3.7,BottomRowHeightAt = max(这个 token, 操作区))也从内容区顶上扣 —— 只换这个 token
    的主题,栏的 Invalidate 比 FLaid.NoteRow 看出来、重排,让出行跟着变高 / 变矮。不另设一项:
    同一个 token 记两份,两份只会一起变。 }
  TTyToolWindowBarMetrics = record
    Strip, Edge, Chrome, ContentMin, NoteRow: Integer;
  end;

  TTyToolWindowArray = array of TTyCustomToolWindow;

  { 当前页的标签行此刻在谁身上(spec §3.7,E 期)。Host = nil:不是底栏、没有当前页或行高 0。
    Row 是 Host 客户区坐标;Geom 是行内坐标(行左上角为原点)。平时 Host 是当前页(行在它客户区
    原点);当前页被禁用时 Host 是栏(行 = BarLayout.TabRow)。 }
  TTyToolWindowTabRowHost = record
    Host: TWinControl;
    Row: TRect;
    Geom: TTyToolWindowHeaderGeom;
  end;

  { 栏自己的几何,栏客户区坐标,**一处算**(TTyToolWindowBar.LayoutIn):AdjustClientRect 取
    Content、绘制取全部、图标条的命中(PartAt)取 Slots / Overflow。空矩形 = 没有这个部件。 }
  TTyToolWindowBarLayout = record
    { 放窗口的那一块 —— AdjustClientRect 的答案。 }
    Content: TRect;
    { 图标条整条(含靠内容区那一侧的界线);底栏为空。 }
    Strip: TRect;
    { 图标条里排图标的那一段:Strip 去掉界线。 }
    Cells: TRect;
    { 排上条的图标,ItemIndex 是**窗口序号**,ItemRect 已换成栏坐标。 }
    Slots: TTyToolWindowSlots;
    { 有窗口放不下时,紧跟在最后一个图标后面的溢出按钮。 }
    Overflow: TRect;
    { 拉宽边 / 贴编辑区的分隔线。运行时收起或没有窗口时为空(它这时不起作用,也不占宽)。 }
    Edge: TRect;
    { 设计期没有窗口:「添加工具窗口」提示画在这里。 }
    EmptyNote: TRect;
    { 设计期有漏进来的非窗口子控件:内容区底部让出来的一行提示(不让出来的话当前页整个
      盖在内容区上,提示一个像素都露不出来)。 }
    StrayNote: TRect;
    { 设计期 Placement 冲突(spec §10.6):同一 manager 下另有一条栏 Placement 相同。内容区底部
      再让出一行,叠在 StrayNote 上面 —— 当前页是窗口化子控件、盖满内容区,不让出来提示一个
      像素都露不出来。 }
    ConflictNote: TRect;
    { 运行时底栏的当前页被禁用:栏在内容区顶上让出来、自己画的标签行(spec §3.7)。
      禁用的页收不到鼠标(Win32 / GTK / Qt / Cocoa 各有各的原因,spec §3.7 根因),标签行
      只能长在栏自己的像素里。其余时候为空。 }
    TabRow: TRect;
  end;

  { 栏上一个点落在哪个部件上(TTyToolWindowBar.PartAt)。图标和底栏标签共用 twbpItem、两种溢出
    共用 twbpOverflow:一条栏只会有其中一种,手势引擎和点击分派因此不用分两套。最大化 / 收起 /
    分隔线只在底栏标签行上有。 }
  TTyToolWindowBarPart = (twbpNone, twbpItem, twbpOverflow, twbpEdge,
    twbpMaximize, twbpCollapse, twbpSeparator);

  { MoveWindow / 直接改 Parent 期间先记下、之后按 spec §6.6 的顺序发的栏事件。 }
  TTyToolWindowBarEvent = (twbeChange, twbeExpand, twbeCollapse);
  TTyToolWindowBarEvents = set of TTyToolWindowBarEvent;

  { 图标条手势引擎的状态(spec §9.2)。Cancelled 之后的松开什么都不做,也不算点击。 }
  TTyToolWindowGestureState = (twgsIdle, twgsArmed, twgsDragging, twgsCancelled);

  { 手势为什么收尾(TTyToolWindowBar.ResetGesture):
    twgeRelease —— 正常松开:拉宽保留此刻的尺寸;拖动回到 Idle,提交由调用方在之后做。
    twgeCancel  —— 被打断(Esc、失活、LM_CANCELMODE、丢了松开……):拉宽回到起点;拖动记成
                   Cancelled,之后的松开什么都不做;武装着的回到 Idle。
    twgeDiscard —— 记录作废(新的按下、窗口离开、栏析构):清理同 Cancel,状态回到 Idle。 }
  TTyToolWindowGestureEnd = (twgeRelease, twgeCancel, twgeDiscard);

  { 手势引擎一次移动之后告诉栏该做什么(见 TTyToolWindowGesture.Move 的状态表)。 }
  TTyToolWindowGestureMove = (
    twgmNone,       { 什么都不做:武装着没过阈值、Cancelled 还按着、丢了松开刚被取消 }
    twgmHover,      { 不在手势里(或取消后按键已松):追踪悬停 }
    twgmDragStart,  { 这一下刚过阈值进入拖动:先清悬停,再按拖动处理 }
    twgmDrag,       { 拖动中:重算落点 }
    twgmResize);    { 拉宽中:按位移写尺寸 }

  { 松开时这次手势算什么。零值 twrNone 就是安全的那一侧:什么都不做。 }
  TTyToolWindowReleaseKind = (twrNone, twrClick, twrDrop, twrResize);
  TTyToolWindowGestureRelease = record
    Kind: TTyToolWindowReleaseKind;
    Part: TTyToolWindowBarPart;   { twrClick:按下的那个部件 }
    Window: TTyCustomToolWindow;        { twrClick / twrDrop:手势的窗口 }
    Snapped: Boolean;             { twrResize:松手时处在吸附排布 }
  end;

  { 一次跨栏手势里问过的一条目标栏和答案(spec §9.4:每个目标栏每次手势只问一次)。 }
  TTyToolWindowAllowedEntry = record
    Bar: TTyCustomToolWindowBar;
    Allowed: Boolean;
  end;

  { 栏的手势引擎(spec §9.2 / §9.7)。每条栏一个,栏构造时建、析构最后放。
    只管状态机、手势记录、资源和唯一的收尾入口;命中、落点、提交、悬停都在栏上。
    内部类型:只给本单元的栏和 manager 用,不是公开 API。 }
  TTyToolWindowGesture = class
  private
    FBar: TTyCustomToolWindowBar;
    { 跨栏拖动此刻的目标栏(另一侧栏);nil = 目标是源栏自己或者没有目标。反馈画在它身上。 }
    FTarget: TTyCustomToolWindowBar;
    FAllowed: array of TTyToolWindowAllowedEntry;
    { --- 手势记录(spec §9.2)。每次按下新建一条:窗口记引用不记序号。 --- }
    FState: TTyToolWindowGestureState;
    FPart: TTyToolWindowBarPart;
    FWindow: TTyCustomToolWindow;
    { 收到按下、持有捕获的控件:图标条是栏,底栏标签行是当前页。阈值原点、捕获轮询都按它。 }
    FCapturer: TControl;
    FOrigin: TPoint;            { 屏幕坐标 }
    { 按下带 ssDouble / ssTriple / ssQuad:阈值以内松开永远不算点击。 }
    FMulti: Boolean;
    { 按下的部件是拖动把手(图标 / 标签);溢出按钮等不是。 }
    FDraggable: Boolean;
    { 这次按下落在图标条 / 边缘区:吞掉 LCL 在 MouseUp 之前调的 Click、以及 DblClick。 }
    FSwallowClick: Boolean;
    { --- 拉宽边(spec §6.3)。起点记逻辑尺寸和屏幕坐标:右栏 / 底栏拉宽时自己在挪,
      客户区坐标跟着变,屏幕坐标不变。 --- }
    FResizing: Boolean;
    { 未钳的尺寸小于 content-min 的一半:实时按收起排布,ExpandedSize 停在起点。 }
    FSnapped: Boolean;
    FStartSize: Integer;
    FStartPos: TPoint;          { 屏幕坐标 }
    { 设计期按在图标上:从按下到松开,CM_DESIGNHITTEST 一律答 1;松开那一拍先切页再答 0。
      被按下的是哪个窗口记引用、不记序号:武装期间别的窗口被删掉,序号全挪了。
      LM_CANCELMODE、设计期离开、捕获被别人拿走都解除武装 —— 否则这一次的松开丢了,
      之后随便一条不带按键的命中测试都会被当成松开、切页、通知设计器。 }
    FDesignArmed: Boolean;
    FDesignWindow: TTyCustomToolWindow;
    { --- 资源 --- }
    FCursor: TCursor;
    FCursorPushed: Boolean;
    { KeyDownBefore / ActiveFormChanged 两个处理器挂着。 }
    FHooked: Boolean;
    { 拉宽或拖动任一个在进行,就挂着 Application 的失活处理器。 }
    FDeactivateHooked: Boolean;
    FCaptureConfirmed: Boolean;
    { 只在拖动期间存在的计时器(ExtCtrls.TTimer;ExtCtrls 只在 implementation 里 uses),
      轮询捕获是不是被别人抢走了。 }
    FCaptureTimer: TComponent;
    { 放掉计时器、弹临时光标、摘处理器,不回调栏 —— 析构也走它。 }
    procedure FreeResources;
    { 幂等:FreeResources + 清插入线 + 失活处理器跟上。不碰手势记录 —— BeginDragging
      进门先调它,把上一次万一留下的残局收掉。 }
    procedure ReleaseResources;
    procedure SyncDeactivateHook;
    procedure BeginDragging;
    function PastThreshold(X, Y: Integer): Boolean;
    procedure KeyDownBefore(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure ActiveFormChanged(Sender: TObject; Form: TCustomForm);
    procedure AppDeactivated(Sender: TObject);
    procedure CaptureTimerTick(Sender: TObject);
  public
    constructor Create(ABar: TTyCustomToolWindowBar);
    destructor Destroy; override;
    { 新的一次按下(调用方已经 Reset(twgeDiscard) 过)。X, Y 是捕获者客户区坐标。 }
    procedure Press(APart: TTyToolWindowBarPart; AWindow: TTyCustomToolWindow; ADraggable: Boolean;
      ACapturer: TControl; X, Y: Integer; AShift: TShiftState);
    procedure BeginResize(AStartSize: Integer; const AScreenPos: TPoint);
    function Move(AShift: TShiftState; X, Y: Integer): TTyToolWindowGestureMove;
    { APart / AWindow:松开点上的部件和窗口(调用方命中);引擎判完就收尾,再把答案交回。
      拖动的落点由调用方在调它**之前**算好 —— 落点要看手势窗口,收尾之后就没了。 }
    function Release(APart: TTyToolWindowBarPart; AWindow: TTyCustomToolWindow): TTyToolWindowGestureRelease;
    { 手势收尾的**唯一入口**,幂等:拉宽(按 AReason 保留或回到起点)、临时光标、处理器、
      计时器、插入线、按下态、手势记录,一处全部归零。栏析构中只清标志,不重排不重画。
      见 TTyToolWindowGestureEnd。 }
    procedure Reset(AReason: TTyToolWindowGestureEnd);
    procedure SetCursor(ACursor: TCursor);
    { 换目标栏:旧的清外来落点、新的画 ASlot(ABar = nil 只清旧的)。 }
    procedure SetTarget(ABar: TTyCustomToolWindowBar; ASlot: Integer);
    { 这一次手势里拖过去行不行:在缓存里找,没有就问 manager 的 CanMoveWindow 并记下。 }
    function AllowedFor(ABar: TTyCustomToolWindowBar): Boolean;
    { 缓存里 ABar 的答案丢掉:它离开了 manager 或被释放,同一个地址之后可能是另一条栏。 }
    procedure ForgetBar(ABar: TTyCustomToolWindowBar);
    function AllowedCount: Integer;
    property Target: TTyCustomToolWindowBar read FTarget;
    { AWindow = nil 等于 DisarmDesign。 }
    procedure ArmDesign(AWindow: TTyCustomToolWindow);
    procedure DisarmDesign;
    function HasCaptureTimer: Boolean;
    property State: TTyToolWindowGestureState read FState;
    property Part: TTyToolWindowBarPart read FPart;
    property Window: TTyCustomToolWindow read FWindow;
    property Capturer: TControl read FCapturer;
    property Resizing: Boolean read FResizing;
    property Snapped: Boolean read FSnapped write FSnapped;
    property StartSize: Integer read FStartSize;
    property StartPos: TPoint read FStartPos;
    property SwallowClick: Boolean read FSwallowClick write FSwallowClick;
    property DesignArmed: Boolean read FDesignArmed;
    property DesignWindow: TTyCustomToolWindow read FDesignWindow;
  end;

  { 隐藏侧栏的放置预览(spec §9.8,E 期):拖动时在隐藏的那一侧、按那条栏展开后的宽显示一块。
    有句柄的子控件,不是顶层窗口(Wayland 不让程序定位顶层窗口);不透明、不拿焦点、不参加
    对齐(alNone)、不是栏的兄弟监听对象。拖动期间捕获在源栏上,它收不到鼠标,命中全靠
    manager 的几何(spec §9.4)。Owner = nil,由栏持有、栏析构时释放;只在运行时建,不进 .lfm。 }
  TTyToolWindowDropPreview = class(TTyCustomControl)
  private
    FBar: TTyCustomToolWindowBar;
    FHot: Boolean;
    procedure SetHot(AValue: Boolean);
  protected
    { TyToolWindowDropZone。 }
    function GetStyleTypeKey: string; override;
    { 先铺栏的底色(TyToolWindowBar 静止态 background —— 预览是不透明的,DropZone 的底色带
      透明度),再按 TyToolWindowDropZone(Hot 时 :hover)画底色和边框,正中一行文字(左栏
      rsTyToolWindowDropLeft、右栏 rsTyToolWindowDropRight),左右各缩一个 header-pad,放不下出
      省略号。不做绘制缓存:只在拖动中存在,重画少。 }
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { Paint 用的密度:栏的(预览的宽、pad、字号都按栏的尺度算 —— 宽来自栏的推导);没有栏时
      自己字体的。预览挂在栏的父控件上,自己的字体 PPI 跟栏的不一定一样。 }
    function PaintPPI: Integer;
  public
    constructor CreateFor(ABar: TTyCustomToolWindowBar);
    procedure Paint; override;
    { 指针在里面、它是此刻的目标(spec §9.8)。变了才重画。 }
    property Hot: Boolean read FHot write SetHot;
  end;

  TTyCustomToolWindowBar = class(TTyCustomControl)
  private
    { 注册过的窗口(集合,顺序不算数)。**窗口顺序永远就是 Controls 顺序**(spec §6.1),
      每次现取:SetControlIndex 不是虚方法,设计器的「移到最前 / 最后」直接调它 ——
      缓存一份顺序就会跟 Controls 漂开,.lfm 按 Controls 写、ActiveIndex 按缓存写。 }
    FRegistered: TTyToolWindowArray;
    { 正在离开的窗口和它离开前的窗口序号。两条离开的路(SetParent 的注销分支、释放时的
      Notification)走到时它都已经不在 Controls 里了,所以在 RemoveControl 里先记下来。 }
    FLeaving: TTyCustomToolWindow;
    FLeavingIndex: Integer;
    FPlacement: TTyToolWindowPlacement;
    FExpandedSize: Integer;
    FCollapsed: Boolean;
    { 当前页。加载中注册进来的窗口不碰它 —— 加载中「哪一页是当前页」只有一个答案:
      Loaded 还没挑,FActive 是 nil(继承窗体的第二遍加载例外:那时第一遍挑好的那页
      真的显示着,它照样答那一页)。 }
    FActive: TTyCustomToolWindow;
    { 加载中的待定当前页,Loaded 里应用(那时窗口才全注册完)。两种来源,后写的算:
      读进来 / 设进来的 ActiveIndex 记序号(流里本来就是序号);按窗口激活的
      (ActiveWindow、ShowControl)记窗口本身 —— 记成序号的话,加载中调顺序、有窗口
      离开,就会指到别的窗口上。Loaded 应用完把序号记成真正应用的那一个、窗口清空。 }
    FLoadingActiveIndex: Integer;
    FLoadingTarget: TTyCustomToolWindow;
    { 栏自己在切 Visible:TTyToolWindow.SetVisible 看见它就直接放行,不再路由回栏。 }
    FBarSwitching: Boolean;
    FDeriving: Boolean;
    FRelayouting: Boolean;
    { > 0 = 这一批不发任何用户事件(栏的 OnChange / OnCollapse / OnExpand 和窗口的
      OnShow / OnHide),见 BeginSilent。 }
    FSilent: Integer;
    { 主题尺寸的缓存,键 = (PPI, model 身份, 主题版本, Placement, 样式类, StyleOverride)。
      不含 RTL:栏的几何一律看 Placement,不看读写方向。 }
    FMetrics: TTyToolWindowBarMetrics;
    FMetricsValid: Boolean;
    FMetricsPPI: Integer;
    FMetricsAnchor: TObject;
    FMetricsVer: Cardinal;
    FMetricsPlacement: TTyToolWindowPlacement;
    FMetricsClass: string;
    FMetricsOverride: string;
    { 上一次推导尺寸时**真正用过**的那一份。Invalidate 拿它比,而不是拿缓存比 ——
      缓存谁读都会刷新(对齐引擎在 AdjustClientRect 里读、ConstrainedResize 里读),
      「谁先读就是谁的」:别人先把缓存刷成新值,Invalidate 就再也看不出主题变了。
      PPI 单独记:内容项 MulDiv(ExpandedSize, PPI, 96) 也跟着它变,而几项主题尺寸取整之后
      可能一个都没动(默认 token 的底栏在 96 → 100 PPI 下就是这样)。 }
    FLaid: TTyToolWindowBarMetrics;
    FLaidPPI: Integer;
    FLaidValid: Boolean;
    { 上一次 Invalidate 时的样式类 + StyleOverride。标签行的样式按栏的样式类解析、画在当前页里,
      改这两个只带来栏自己的一次裸 Invalidate —— 变了就让当前页重查几何(InvalidateHeader)。 }
    FHeaderStyleKey: string;
    FHeaderStyleKeyValid: Boolean;
    { 挂着显隐 / 改尺寸处理器的兄弟(同一父控件里的非栏控件),见 WatchSiblings。每个都
      FreeNotification 过:它被释放时从这里摘掉,不留悬垂。 }
    FWatched: array of TControl;
    { 沿轴尺寸变成 0 那一刻紧挨着的内侧同向兄弟(对齐排序里排在栏后面的第一个);从 0 回来时
      ApplyAxisSize 把排序键摆到它外面。FreeNotification 过,被释放 / 摘走时 Notification 清掉。 }
    FZeroInner: TControl;
    FOnChange: TNotifyEvent;
    FOnCollapse: TNotifyEvent;
    FOnExpand: TNotifyEvent;
    { 一侧没有窗口时整条隐藏(spec §6.9,E 期)。构造值 True,同 published 的 default。 }
    FHideWhenEmpty: Boolean;
    FImages: TCustomImageList;
    { 注册到的 manager(spec §2 / §10.6);nil = 没有,只有栏内调顺序。 }
    FManager: TTyCustomToolWindowManager;
    { 变更 link **真正注册在**哪个列表上。它和 EffectiveImages 可以一时不同 —— 生效列表刚变、
      还没重新订阅的那一刻 —— 所以单记一份:注销要找的是 link 实际挂着的那一个。 }
    FSubscribedList: TCustomImageList;
    FImageLink: TChangeLink;
    procedure SetManager(AValue: TTyCustomToolWindowManager);
    { 和 manager 断开(manager 被释放、或两边之一从 Owner 摘走):取消拖动、清引用、生效列表
      可能跟着变。不回头调 manager —— 从它的表里摘不摘由调用方定。 }
    procedure DetachManager;
    procedure SetImages(AValue: TCustomImageList);
    { 让 link 跟上 EffectiveImages:**先**从旧列表注销,**再**注册到新列表并 FreeNotification。
      顺序反了(或者不注销),同一个 link 就同时挂在两个列表上,而 Sender 只记得后一个 ——
      旧列表析构时 `while Count > 0 do UnregisterChanges(第 0 个)` 按 Sender 删,删不掉,
      死循环(imglist.inc:1692-1698, 2706-2711)。 }
    procedure SyncImageSubscription;
    { link 从 FSubscribedList 上摘下来、FSubscribedList 置 nil,并撤掉和它互相的
      FreeNotification —— 除非 FImages 还引用着它(引用要靠那条通知来清),或者它正在
      释放(它自己的析构在清通知表)。
      **FreeNotification 只归订阅这一处管**:订阅谁就 FreeNotification 谁(Sync 里加),
      注销谁就撤谁(这里撤)。FImages 不另外登记 —— 它非空且活着时就是生效列表,
      必然是订阅着的那一个。SetImages 不碰 FreeNotification。 }
    procedure UnsubscribeImages;
    { 生效列表可能换了:重新订阅、解析挂起的序号、重画。 }
    procedure ImagesChanged;
    { 订阅的列表内容变了(加名字、换图标集……)。 }
    procedure ImageListChange(Sender: TObject);
    { 栏里每个窗口挂起的 ImageIndex 换成名字;加载中、析构中不做(见 TTyToolWindow.ResolveImageIndex)。 }
    procedure ResolvePendingImageIndexes;
    procedure SetPlacement(AValue: TTyToolWindowPlacement);
    { 值变了且不在加载中:重推尺寸、重画(spec §6.9)。 }
    procedure SetHideWhenEmpty(AValue: Boolean);
    procedure SetExpandedSize(AValue: Integer);
    procedure SetCollapsed(AValue: Boolean);
    function GetActiveIndex: Integer;
    procedure SetActiveIndex(AValue: Integer);
    function GetWindow(AIndex: Integer): TTyCustomToolWindow;
    function GetWindowCount: Integer;
    function WidthIsStored: Boolean;
    function HeightIsStored: Boolean;
    function PPI: Integer;
    function Metrics: TTyToolWindowBarMetrics;
    { 运行时收起着(设计期永远按展开)。 }
    function CollapsedAtRunTime: Boolean;
    { 按「收起」算尺寸:运行时收起着、没有窗口、或拉宽边正吸附着(spec §6.3);设计期永远不算。 }
    function SizesAsCollapsed: Boolean;
    { 沿栏轴向的推导尺寸(侧栏 = Width,底栏 = Height),设备像素。内容项不低于
      content-min —— 和 ConstrainedResize 的下限同一个数,所以 ExpandedSize 比下限还小时
      Width 照样等于这里的答案,不会被对齐引擎悄悄钳开。空间不够时按 spec §6.2 收窄
      (NarrowedContentPx),收窄的结果同样不低于 content-min。 }
    function DerivedAxisPx(const AM: TTyToolWindowBarMetrics): Integer; overload;
    { 推导的两段:沿轴的固定部分(图标条、边缘区、chrome)和内容项。 }
    function FixedAxisPx(const AM: TTyToolWindowBarMetrics): Integer;
    { 内容项,钳到 content-min,**没收窄**;按收起算尺寸时是 0。 }
    function UnnarrowedContentPx(const AM: TTyToolWindowBarMetrics): Integer;
    { spec §6.2:空间不够时收窄的内容项。可用 = 父控件调整后客户区沿轴尺寸 − 同轴的非栏
      对齐兄弟 − 同轴所有栏的固定部分;同轴的栏按各自**未收窄**的内容一起算,放不下按
      ExpandedSize 比例分,各自不低于 content-min。只影响这一次排布,不写回 ExpandedSize。 }
    function NarrowedContentPx(const AM: TTyToolWindowBarMetrics): Integer;
    { 参与分空间:看得见、Align 就是 Placement 要求的那个。 }
    function JoinsNarrowing: Boolean;
    { 父控件尺寸变了:重推(收窄跟着可用空间走)。 }
    procedure ParentResized(Sender: TObject);
    { 收窄(spec §6.2)和最大化(§6.4)扣的是同轴对齐兄弟的尺寸 —— 兄弟显隐、改尺寸而父控件
      没动时 ParentResized 听不见。所以给父控件里每一个非栏兄弟挂显隐 / 改边界的处理器
      (栏之间本来就互相 DeriveSiblings)。和父控件此刻的子控件对一遍:已经不在父控件里的摘掉,
      新来的挂上。每次推导尺寸时对一遍(换父控件也经推导)—— LCL 不告诉别的子控件「来了
      一个兄弟」,新兄弟要等下一次推导才挂上(父控件里有 alClient 编辑区时,兄弟进出引起的
      重排会挪它,它的改边界处理器就触发这一次推导)。 }
    procedure WatchSiblings;
    procedure UnwatchAt(AIndex: Integer);
    procedure UnwatchAll;
    procedure SiblingChanged(Sender: TObject);
    { 同一父控件里其余每一条栏重推(它们按比例分的份额跟着本栏变)。 }
    procedure DeriveSiblings(AParent: TWinControl);
    { Placement 要求的 Align(左 → alLeft,右 → alRight,底 → alBottom)。 }
    function PlacementAlign: TAlign;
    procedure DeriveSize;
    { 把沿轴尺寸设成 AValue(推导的唯一写入口):外沿(LCL 对齐排序的键)不动、往编辑区一侧长;
      从 0 回来时排序键摆到变成 0 那一刻紧挨着的内侧同向兄弟外面(见实现处)。尺寸没变什么都
      不做。 }
    procedure ApplyAxisSize(AValue: Integer);
    procedure Relayout;
    { Controls 顺序里的窗口,去掉 AExcept(可为 nil)。非窗口子控件(粘贴等途径漏进来的)
      不计入任何序号。 }
    function WindowList(AExcept: TTyCustomToolWindow): TTyToolWindowArray;
    function IsRegistered(AWindow: TTyCustomToolWindow): Boolean;
    { 把窗口 AWindow 挪到窗口序号 APos 要用的 Controls 下标(spec §2 的换算)。 }
    function ControlIndexForWindowPos(AWindow: TTyCustomToolWindow; APos: Integer): Integer;
    procedure MoveToOuterEdge;
    function FocusIsInside(AWindow: TTyCustomToolWindow): Boolean;
    procedure ShowWindowNow(AWindow: TTyCustomToolWindow);
    procedure HideWindowNow(AWindow: TTyCustomToolWindow);
    { spec §5.1 的六步。AOld 只用来判断焦点原来在不在旧页里(可为 nil 或就是 AWindow)。
      显示 / 隐藏不看 AOld:先显示目标,再把栏里**其余每一个**窗口藏起来;收起着就
      连目标一起藏。 }
    procedure SwitchCore(AWindow, AOld: TTyCustomToolWindow; AMoveFocus: Boolean);
    { 一次静默切页 = BeginSilent + 切 + EndSilent(try/finally)的薄包装。 }
    procedure SwitchSilently(AWindow: TTyCustomToolWindow);
    { 跨栏移动的最后一步(CommitCrossMove):AWindow(已经在本栏里)成为当前页并展开;设计期
      只激活。收起着时先按展开的样子切页、再撤收起 —— 先切再展开的话,带着 Visible 挪进来的
      AWindow 会先被收起的切页藏一次、再被展开显示一次,多一对 OnHide / OnShow。 }
    procedure ActivateExpanded(AWindow: TTyCustomToolWindow);
    function EventsAllowed: Boolean;
    procedure DoChange;
  private
    { --- 延后事件(spec §6.6 的 MoveWindow 发送顺序)。> 0 时 DoChange 和 SetCollapsed 的事件
      只记进 FPendingEvents,由调用方在 EnableAlign、焦点恢复之后按顺序发(FireBarEvent)。 --- }
    FDeferEvents: Integer;
    FPendingEvents: TTyToolWindowBarEvents;
    { ActivateExpanded 里:收起着的栏这一次切页按展开的样子切(显示目标、藏其余)。 }
    FSwitchExpanded: Boolean;
    { > 0 = 布局应用的批次(spec §10.4):栏事件不发(EventsAllowed)、切页和收起跳过焦点那一步、
      当前页离开不回落(由计划统一激活)。窗口的 OnShow / OnHide 照常 —— 那是 BeginSilent 的事,
      两者互不替代(加载结束时应用挂起计划才两样一起包)。 }
    FLayoutBatch: Integer;
    { 调用方必须 try/finally 配对。 }
    procedure BeginDeferEvents;
    { 降到 0 时交还记下的事件并清空;没降到 0 交还空集(外层还在延后)。钳在 0。 }
    function EndDeferEvents: TTyToolWindowBarEvents;
    { 过一遍 EventsAllowed 再调对应的处理器。 }
    procedure FireBarEvent(AEvent: TTyToolWindowBarEvent);
    { 栏内调顺序的实体(不发 OnWindowMoved):钳到 0..N-1、换算成 Controls 下标。答挪之前的
      窗口序号;不在本栏或没挪动答 -1。 }
    function PlaceWindow(AWindow: TTyCustomToolWindow; AIndex: Integer): Integer;
    { 长度 token 按给定 PPI 换成设备像素,负的按 0。 }
    function TokenPxAt(const AName: string; ADefault, APPI: Integer): Integer;
    { 栏自己那几项主题尺寸按给定 PPI 现算(不缓存);Metrics 是按自己字体 PPI 的那一份的缓存。 }
    function MetricsAt(APPI: Integer): TTyToolWindowBarMetrics;
    { LayoutIn 的任意 PPI 版:RenderTo(APPI) 画的几何必须跟 APPI 是同一套尺度。 }
    function LayoutAt(const AClient: TRect; APPI: Integer): TTyToolWindowBarLayout;
    { 漏进来的非窗口子控件有几个(粘贴等途径;spec §6.1)。 }
    function StrayCount: Integer;
    { 同一 manager 下另有一条栏 Placement 相同(manager 现算,IsBarUsable)。manager 正在释放时
      不算。 }
    function PlacementConflicts: Boolean;
    { 冲突提示可能出现 / 消失了:它占内容区的一行,所以要重排再重画。只在设计期、不在加载 /
      释放中做 —— 加载中的由 Loaded → Relayout 带上;运行时没有这行提示。 }
    procedure ConflictMayHaveChanged;
  private
    { --- 底栏标题行(spec §7.2 / §7.3) --- }
    { 标签宽的缓存:只缓存量出来的宽(量字是贵的那一步),不缓存整份几何 —— 窗口顺序每次现取,
      设计器「移到最前 / 最后」直接调非虚的 SetControlIndex,戳记不到。键 = 此刻
      「(窗口引用, Caption) 按 Controls 顺序」的快照逐项比 + (PPI, model 身份, 主题版本,
      样式类, StyleOverride, 三种状态**解析后**的字号)。字号取量字真正用的那个
      (ResolveFontSize:样式的 font-size、非 ParentFont 时自己的 Font.Size、主题基准字号
      依次回落)—— 只记 Font.Size 的话,ParentFont 一翻、Font.Size 没变而字号换了一个来源,
      缓存照样命中。只缓存自己字体的 PPI 那一份,别的 PPI 现量。 }
    FTabCacheValid: Boolean;
    FTabCacheWins: TTyToolWindowArray;
    FTabCacheCaps: array of string;
    FTabCachePPI: Integer;
    FTabCacheAnchor: TObject;
    FTabCacheVer: Cardinal;
    FTabCacheClass: string;
    FTabCacheOverride: string;
    FTabCacheRestFs: Integer;
    FTabCacheSelFs: Integer;
    FTabCacheDisFs: Integer;
    { 键的一部分(E 期,spec §7.3 / §8.1):每个窗口此刻的角标显示,和标题那一组同一个循环逐项比
      —— 记的是事件应用之后的答案,不是 BadgeValue(事件可以改文字)。见 BadgeCacheKey。 }
    FTabCacheBadges: array of string;
    FTabCacheWidths: TTyToolWindowWidths;
    { 按窗口顺序,每个标签要的宽:标题取「静止态」「选中态」「禁用态」三份样式量的最大者(spec §7.3;
      每份又是 Painter 的两种量法取大),再加 2 × tab-pad。空标题也有 2 × tab-pad。有角标的
      再加 header-gap + 胶囊宽(BadgeSizeAt,画胶囊问的是同一处)。 }
    function TabWidthsAt(APPI: Integer): TTyToolWindowWidths;
    function MeasureTabWidths(const AWins: TTyToolWindowArray; APPI: Integer): TTyToolWindowWidths;
    { 标签宽缓存键里一个窗口的角标那一项:不显示 ''、圆点 #1'dot'(不会是真文字的串)、
      数字 '#' + 文字。 }
    function BadgeCacheKey(AWindow: TTyCustomToolWindow): string;
    { 只清标签宽缓存的标志(角标变了,spec §8.1)。 }
    procedure TabWidthsChanged;
    { 标签行竖分隔线的线宽(设备像素):TyToolWindowSeparator 解析出可见边框时按 border-width
      缩放、至少 1;否则 0(槽宽 = 2 × gap + 线宽,spec §7.3)。 }
    function SeparatorLinePx(APPI: Integer): Integer;
    { 标题行排布的全部输入:窗口给公共那几项(模式、行宽、pad、gap、操作区宽、RTL),
      底栏由栏补标签宽、当前页、标签区下限、按钮、分隔线槽、溢出按钮宽。 }
    function HeaderInputFor(AWindow: TTyCustomToolWindow; ARowWidth, ARowHeight,
      APPI: Integer): TTyToolWindowHeaderInput;
  private
    { 上一次**用过**的统一行高里操作区那一项(HeaderActionsHeight(nil, PPI));-1 = 还没用过。 }
    FBottomActionsPx: Integer;
    FActionsNotifying: Boolean;
    { 某一页的操作区首选尺寸变了、或者窗口列表变了(spec §3.4):底栏统一行高的操作区那一项
      变了,就对**当前页**重排标题行。非当前页在切页第 4 步 RelayoutHeader 时现取。 }
    procedure ActionsSizeChanged;
  private
    { --- 让出标签行(spec §3.7,E 期) --- }
    { 上一次按哪种样子排过(让出 / 没让出):TabRowHostMayHaveChanged 比它。 }
    FTabRowHosted: Boolean;
    { 底栏统一行高(spec §3.4),按 APPI。token 自己取(TokenPxAt),不读窗口的 HeaderTokenPx
      缓存 —— 那是窗口在自己的 Invalidate 里察觉换主题的唯一一条边,谁先读就是谁的。 }
    function BottomRowHeightAt(APPI: Integer): Integer;
    { 标签行此刻长在谁身上(只答控件,不算几何):按下态、插入线的「捕获者是不是宿主」用它。
      底栏以外 nil。 }
    function TabRowHostControl: TWinControl;
    { 让不让出变了:让出 / 收回那一行改的是 AdjustClientRect 的答案,要 Realign(只重画的话
      当前页停在旧边界里、盖着标签行);当前页 RelayoutHeader;栏和当前页都重画;进行中的
      标签行手势取消(拉宽不算)。加载 / 释放中不做。 }
    procedure TabRowHostMayHaveChanged;
    { 栏坐标 AP 落在禁用的当前页的边界里(它看得见、自己的 Enabled = False):Win32 上点禁用页,
      按下落到栏上(spec §3.7 根因第 1 条)。 }
    function InDisabledActivePage(const AP: TPoint): Boolean;
    { 这一下按下不算「按在栏上」:让出来的标签行里(空白也算),或禁用的当前页的边界里。
      MouseDown 吞 Click / DblClick、BeginAutoDrag 挡 LCL 自动拖动问的都是这一处。 }
    function SwallowPress(const AP: TPoint): Boolean;
  private
    { --- 角标(spec §8.1,E 期) --- }
    { 角标的尺寸(设备像素,按 APPI)和文字;不画时 (0, 0)。文字宽按标签的量法(两种量法取大),
      高按 '0',交给 TyBadgeSize —— 量标签宽和画胶囊都问这里,两边差一个像素胶囊就压到下一个
      标签上,而且不会红。样式取 TyToolWindowBadge 静止态(不看禁用,同 TTyButton 的徽标);
      内边距、--badge-min-size、--badge-dot-size 按 APPI。 }
    function BadgeSizeAt(AWindow: TTyCustomToolWindow; APPI: Integer; out AText: string;
      out ADot: Boolean): TSize;
    { 在 ABox(画笔坐标)里画角标。ABox、AText、ADot 都是同一次 BadgeSizeAt 的答案 —— 不再问
      OnBadgeDisplay:一次绘制里事件只答一次,量的和画的就不会是两个答案(事件是用户代码,两次之间
      它看的外部状态可能变了)。ABox 为空就什么都不做。圆点画成圆,数字画胶囊(圆角照
      TTyButton.DrawBadge:主题没给圆角就半高),文字用 ASmallCrisp。 }
    procedure DrawBadgeIn(APainter: TTyPainter; const ABox: TRect; const AText: string;
      ADot: Boolean);
  private
    { --- 隐藏侧栏的放置预览(spec §9.8,E 期) --- }
    FDropPreview: TTyToolWindowDropPreview;
    { 只在 ShownAxisPx 里置位:SizesAsCollapsed / HiddenAsEmpty 按「有一个窗口、展开着」答。 }
    FAssumeShown: Boolean;
    { 这条栏有一个窗口、展开着时推导出来的轴向尺寸(放置预览的宽,spec §9.8):图标条 +
      2 × chrome + 边缘区 + 按 §6.2 收窄后的内容。别的栏照常按自己的真实状态参加分空间 ——
      不另写一份推导公式(两份会漂开)。 }
    function ShownAxisPx: Integer;
    { 按 DropPreviewRect 显示预览(没建过就建);矩形为空就收掉。manager 进入拖动时调;拖动中
      栏换了父控件 / 父控件改了尺寸时 manager 再调一次,那时保留亮不亮。 }
    procedure ShowDropPreview;
    { 预览这个窗口化控件擦除时铺的颜色(ARect 是它的矩形):栏的底色 —— 纯色原样、渐变取两端的
      中间色;图片 / 九宫格给不出一个颜色,退到图标条的底色;都给不出答 False(不设,擦成父控件的
      颜色)。 }
    function DropPreviewEraseColor(const ARect: TRect; out AColor: TColor): Boolean;
    { 收掉(不释放,下次拖动复用)。 }
    procedure HideDropPreview;
    procedure SetDropPreviewHot(AOn: Boolean);
  private
    { 标签行上悬停的部件和(标签时)窗口序号;没有悬停是 (twbpNone, -1)。标签行的悬停只在
      当前页上,所以记在栏上一份就够。 }
    FHeaderHoverPart: TTyToolWindowBarPart;
    FHeaderHoverIndex: Integer;
    { 标签行上 APart(标签时是窗口 AItem 的那一个)此刻是不是按下着 —— 从手势引擎读,不另记:
      武装着(标签在拖动中也算,源标签保持 :active 直到收尾)、捕获者是这一页、部件相同
      (标签还要窗口相同)。 }
    function HeaderPressed(AWindow: TTyCustomToolWindow; APart: TTyToolWindowBarPart;
      AItem: TTyCustomToolWindow): Boolean;
    { 标签行上的手势此刻捕获在 AWindow 上(引擎的捕获者就是它)—— 窗口决定「移动 / 松开
      转不转给栏」只问这一处,自己不另记镜像。 }
    function HeaderCapturedBy(AWindow: TTyCustomToolWindow): Boolean;
    { 标签的状态:当前页只有 :selected(spec §12,禁用时再加 :disabled);其余按禁用 / 悬停 /
      按下 / 静止。AIndex 是窗口序号、AItem 是那个窗口、AActiveIndex 是当前页的窗口序号 ——
      由调用方一次取好(PaintHeader 逐个标签问,每次现数窗口表就是 O(N²))。 }
    function HeaderTabStates(AWindow: TTyCustomToolWindow; AIndex, AActiveIndex: Integer;
      AItem: TTyCustomToolWindow): TTyStateSet;
    { 溢出 / 最大化 / 收起按钮的状态:禁用 / 悬停 / 按下 / 静止。 }
    function HeaderPartStates(AWindow: TTyCustomToolWindow; APart: TTyToolWindowBarPart): TTyStateSet;
    { 标签行的像素属于当前页,当前页有绘制缓存(spec §3.5):标签行的一切视觉变化都经这里丢
      当前页的缓存。只 Invalidate 栏的话,运行时当前页 blit 旧帧。 }
    procedure InvalidateHeader;
    { 标签行的部件换成栏的部件:标签 → twbpItem、溢出 → twbpOverflow,其余一一对应。 }
    function PartOfZone(AZone: TTyToolWindowZone): TTyToolWindowBarPart;
    { 变了才写,并 InvalidateHeader(悬停画在当前页里)。 }
    procedure SetHeaderHover(APart: TTyToolWindowBarPart; AIndex: Integer);
    { 标签行上 (X, Y)(宿主客户区坐标)的插入槽:只有标签行区域(行里减去操作区)算目标
      (spec §9.4),区域外 -1。按阅读顺序找空隙:RTL 时拿一份几何翻回 LTR、指针 X' := 行宽 − 1 − X
      —— 直接在镜像后的几何上按 X 找,「前半边 / 后半边」会整个反过来。几何按当前页的读写方向
      镜像,翻回也按它。空隙映射到窗口序号(当前页被强制留下时已排标签不是前缀)。 }
    function RowDropSlot(const AHost: TTyToolWindowTabRowHost; X, Y: Integer): Integer;
    { 拖动中:重算插入槽、换光标(区域外 crNoDrop,其余 crDrag;空操作不画线)。 }
    procedure RowDragIn(const AHost: TTyToolWindowTabRowHost; X, Y: Integer);
    { 页当宿主时的那一份:行在页客户区原点,几何由调用方给(页一次事件只排一份)。 }
    function PageRowHost(AWindow: TTyCustomToolWindow; const AGeom: TTyToolWindowHeaderGeom): TTyToolWindowTabRowHost;
    { 标签行手势的核心(spec §7.4 / §9.2),按宿主做:AHost 是 TabRowHost(当前页或栏),X / Y 是
      宿主客户区坐标。引擎拿宿主坐标(阈值原点、捕获轮询都按宿主),几何命中减掉 Row.TopLeft
      换成行内坐标。当前页当宿主时行在它客户区原点,两套坐标相等 —— 原来那一路行为不变。 }
    procedure RowDown(const AHost: TTyToolWindowTabRowHost; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    procedure RowMove(const AHost: TTyToolWindowTabRowHost; Shift: TShiftState; X, Y: Integer);
    procedure RowUp(const AHost: TTyToolWindowTabRowHost; Button: TMouseButton;
      Shift: TShiftState; X, Y: Integer);
    { ARect 是命中部件的矩形,宿主客户区坐标。 }
    function RowHintAt(const AHost: TTyToolWindowTabRowHost; X, Y: Integer; out AText: string;
      out ARect: TRect): Boolean;
    { 移动的实体,几何由调用方给(当前页一次事件只排一份,见 TTyToolWindow.MouseMove)。 }
    procedure HeaderMoveIn(AWindow: TTyCustomToolWindow; const AGeom: TTyToolWindowHeaderGeom;
      Shift: TShiftState; X, Y: Integer);
  private
    { --- 最大化(spec §6.4)。只在运行时有,不进 .lfm。 --- }
    FMaximized: Boolean;
    { 侧栏、设计期、加载中、收起着、没有窗口时设 True 一律忽略(spec §6.4)。设成功:拉宽
      中途被改 = 结束拉宽回起点(spec §6.3),重推尺寸,标签行的字形换掉。ExpandedSize 从头到尾
      不写。 }
    procedure SetMaximized(AValue: Boolean);
    { 最大化时的内容项(spec §6.4):父控件调整后客户区高 − 同轴非栏对齐兄弟 − 所有参与
      分空间的同轴栏的固定部分 − **其余**参与者未收窄的内容,不低于 content-min。其余栏照
      §6.2 用各自的未收窄值,不让位。父控件改尺寸(ParentResized)、兄弟显隐 / 改尺寸
      (WatchSiblings)都会重推。 }
    function MaximizedContentPx(const AM: TTyToolWindowBarMetrics): Integer;
    { 图标条某一格的状态:disabled / hover / selected / active(照 TTySegmented.ItemStates)。
      收起时当前图标不画 :selected(spec §5.3)。AWindow 是第 AIndex 个窗口,由调用方一次取好
      (绘制循环里逐格现数窗口表就是 O(N²))。 }
    function StripItemStates(AIndex: Integer; AWindow: TTyCustomToolWindow): TTyStateSet;
    { 用户能不能点它切过去、按住它拖(spec §3.7):看窗口**自己的** Enabled —— IsEnabled 顺着
      父链算,栏一禁用全都答假,当前页的例外就被栏的禁用误触发了。栏自己禁用另有一道闸。 }
    function WindowClickable(AWindow: TTyCustomToolWindow): Boolean;
    { 窗口的 Enabled 变了:正武装 / 拖着它、或捕获在它身上的手势取消;它的悬停清掉;重画。
      底栏当前页的「让出标签行」也在这里对一遍。 }
    procedure WindowEnabledChanged(AWindow: TTyCustomToolWindow);
    { 溢出按钮的状态:disabled / hover / active。 }
    function OverflowStates: TTyStateSet;
  private
    { --- 手势(spec §9.2):状态机、记录、资源都在引擎上(TTyToolWindowGesture)。构造第一句建、
      析构最后一句放,其间一直在。只有继承构造 / 继承析构里可能被问到的那几个判 nil
      (EdgeResizing、EdgeSnapped、ResetGesture、HeaderPressed、HeaderCapturedBy),其余直接用。 --- }
    FGesture: TTyToolWindowGesture;
    { LCL 在 WndProc 里、MouseDown 之前调 BeginAutoDrag,手上没有坐标;按下消息自己带着
      坐标,在 WndProc 里先记下来(只在那一拍有效)。 }
    FAutoDragPos: TPoint;
    FAutoDragPosValid: Boolean;
    FOverflowHover: Boolean;
    FOverflowPressed: Boolean;
    { 右键(spec §6.8):落在图标上时是那个窗口,别处 nil。 }
    FContextWindow: TTyCustomToolWindow;
    { 这一次右键不在图标上:GetPopupMenu 答 nil,请求冒泡到窗体。DoContextPopup 置、
      GetPopupMenu 用掉就清(LCL 在同一条 WM_CONTEXTMENU 里先调前者、再调后者)。 }
    FPopupBlocked: Boolean;
    { 溢出菜单。不给 Owner:给栏的话它进栏的 Components,还得操心流式化;栏自己释放。 }
    FOverflowMenu: TPopupMenu;
    { --- 拉宽边(spec §6.3)。拉宽的记录(进行中、吸附、起点)在引擎上。 --- }
    FEdgeHover: Boolean;
    { 悬停在边缘区时借用 Cursor 显示调整光标;借之前的值原样还回去(同 TTyTreeView 的 A15)。 }
    FSavedCursor: TCursor;
    FCursorOverridden: Boolean;
    procedure BeginEdgeDrag(X, Y: Integer);
    procedure EdgeDragTo(X, Y: Integer);
    procedure SetEdgeHover(AOn: Boolean);
    { 拉宽中 / 吸附中(引擎的只读视图,nil 安全:构造里的推导、析构的继承部分都会问)。 }
    function EdgeResizing: Boolean;
    function EdgeSnapped: Boolean;
    { 引擎收尾时的两个回调。ResizeEnded:拉宽结束(栏不在析构中),松开保留此刻的尺寸,
      其他收尾回到起点(spec §6.3)。GestureCleared:按下的视觉状态清掉并重画;ATabRow = 这次
      手势的捕获者是底栏的一页,它的标签行画着按下态,要重画掉。 }
    procedure ResizeEnded(AReason: TTyToolWindowGestureEnd; AWasSnapped: Boolean);
    procedure GestureCleared(ATabRow: Boolean);
    procedure LMCancelMode(var Message: TLMessage); message LM_CANCELMODE;
  private
    { --- 拖动调顺序(spec §9.2 / §9.4 / §9.7) --- }
    { 插入槽(窗口序号 0..N);-1 = 没有目标(指针不在图标条上)。 }
    FDropSlot: Integer;
    { 外来落点(spec §9.4):别的栏拖过来的窗口落在本栏,FDropSlot 是它的槽位。由源栏的引擎经
      SetForeignDrop 写;有它时按槽位画线,不做空操作判断(跨栏没有空操作)。 }
    FForeignDrop: Boolean;
    { ASlot < 0 = 清掉。变了才 Invalidate;正在释放时只写字段。 }
    procedure SetForeignDrop(ASlot: Integer);
    procedure DragTo(X, Y: Integer);
    { (X, Y) 上的插入槽:只有图标条算目标(源栏自己的内容区、别处都不是)。 }
    function DropSlotAt(X, Y: Integer): Integer;
    { 插入槽是不是空操作:拖到自己前后两个空隙(spec §9.4)。 }
    function IsNoOpSlot(ASlot: Integer): Boolean;
    procedure SetDropSlot(ASlot: Integer);
    { 手势收尾:转发给引擎的唯一入口 TTyToolWindowGesture.Reset。 }
    procedure ResetGesture(AReason: TTyToolWindowGestureEnd);
    { 插入线的那一行(栏坐标 y);没有线答 -1。 }
    function DropLineY(const L: TTyToolWindowBarLayout): Integer;
    { 栏内调顺序:WindowIndex、图标 / 标签拖放提交、同栏 MoveWindow 的唯一一条路。
      PlaceWindow 真的挪了就经 manager 发 OnWindowMoved(spec §6.6)。 }
    procedure ReorderWindow(AWindow: TTyCustomToolWindow; AIndex: Integer);
    procedure SetStripHover(AIndex: Integer; AOverflow: Boolean);
    procedure UpdateHoverAt(X, Y: Integer);
    { spec §5.1 第 4 步:切页之后条上的图标可能换了位置(当前页被强制留在条上),按指针此刻
      的位置重查悬停。 }
    procedure RecheckHover;
    { 点击语义(spec §9.3):不是当前页 → 激活(收起着就展开);是当前页 → 切换收起。
      按窗口 300 ms 防抖。 }
    procedure StripClick(AWindow: TTyCustomToolWindow);
    procedure OverflowItemClick(Sender: TObject);
    { 溢出按钮上松开:按此刻收进去的窗口重建菜单,有句柄才弹。 }
    procedure ShowOverflowMenu;
    procedure CMDesignHitTest(var Message: TCMDesignHitTest); message CM_DESIGNHITTEST;
    { 图标上给 StripHintText 和那一格的 CursorRect,别处走继承(spec §8)。
      提示跟着栏自己的 ShowHint 走:LCL 只把 CM_HINTSHOW 发给 ShowHint 为真的那一级控件。 }
    procedure CMHintShow(var Message: TLMessage); message CM_HINTSHOW;
    { 栏被禁用或藏起来:拉到一半的边和拖到一半的图标都作废(照常调继承)。 }
    procedure CMEnabledChanged(var Message: TLMessage); message CM_ENABLEDCHANGED;
    procedure CMVisibleChanged(var Message: TLMessage); message CM_VISIBLECHANGED;
  protected
    { 图标条上悬停 / 按下的那一格(窗口序号,-1 = 没有)。悬停由 UpdateHoverAt / RecheckHover /
      MouseLeave 写,按下由手势写;窗口离开时按新的序号重新对上(UnregisterWindow)。 }
    FStripHover: Integer;
    FStripPressed: Integer;
    { 防抖的时钟,默认 GetTickCount64。无头测试的探针重写它把时钟往前推,否则 300 ms 防抖
      只能靠 Sleep(套件变慢又不稳)。 }
    function TickNow: QWord; virtual;
    { 指针此刻在本控件客户区里的位置;没有句柄(无头)答 False。切页后重查悬停、
      程序里直接调的 BeginAutoDrag 问的都是这一处,测试探针重写它。 }
    function PointerInClient(out APoint: TPoint): Boolean; virtual;
    { 按下消息的坐标记给 BeginAutoDrag(见 FAutoDragPos)。 }
    procedure WndProc(var TheMessage: TLMessage); override;
    { 设计期:捕获被别人拿走,武装着的设计期手势作废(见引擎的 DesignArmed)。运行时从不取消
      (spec §9.7:Win32 上每一次正常松开之前都会先到这里)。 }
    procedure CaptureChanged; override;
    { 挡在 LCL 自动拖动前面的那一道闸;通过才调继承的 BeginAutoDrag。测试探针重写它数次数,
      不用靠「无头起 LCL 拖动会抛异常」当判据。 }
    procedure StartLclAutoDrag; virtual;
    { spec §6.8:图标上的右键先设 ContextWindow 再走继承(OnContextPopup、PopupMenu);
      别处 —— 包括键盘菜单键的 (-1, -1),栏不拿焦点,这种请求一定来自子控件 —— 不调继承
      (不发 OnContextPopup,Handled 留 False),ContextWindow 置 nil,并挡住 GetPopupMenu,
      子控件的右键请求照样冒泡到窗体。两处都要挡:LCL 先调 DoContextPopup 再调
      GetPopupMenu(control.inc:2484-2492),只改后者挡不住 OnContextPopup。 }
    procedure DoContextPopup(MousePos: TPoint; var Handled: Boolean); override;
    function GetPopupMenu: TPopupMenu; override;
    { 让出来的标签行上的滚轮吞掉(spec §3.7,同页那一路 TTyToolWindow.DoMouseWheel);别处走继承。 }
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer; MousePos: TPoint): Boolean; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseLeave; override;
    procedure Click; override;
    procedure DblClick; override;
    { 图标条(含图标之间、条尾的空白)和边缘区不起 LCL 拖动(DragMode = dmAutomatic 时
      任何位置左键按下都会起)。位置取按下消息记下的那一个,不取此刻的指针。 }
    procedure BeginAutoDrag; override;
    { 注册 / 注销窗口:SetParent 和释放通知的内部簿记,不是给外面调的接口。 }
    procedure RegisterWindow(AWindow: TTyCustomToolWindow);
    procedure UnregisterWindow(AWindow: TTyCustomToolWindow);
    function GetStyleTypeKey: string; override;
    { 栏客户区坐标(0,0 起)里画整条栏:底色、图标条、图标、指示条、溢出、边缘区、设计期提示。
      几何全部来自 LayoutIn(R),跟 AdjustClientRect / 命中是同一份。 }
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { spec §6.1:只接受工具窗口。用 InheritsFrom:派生的窗口类照收。 }
    function ChildClassAllowed(ChildClass: TClass): Boolean; override;
    procedure AdjustClientRect(var ARect: TRect); override;
    procedure ConstrainedResize(var MinWidth, MinHeight, MaxWidth,
      MaxHeight: TConstraintSize); override;
    procedure Loaded; override;
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
    procedure SetController(AValue: TTyStyleController); override;
    { TWinControl 不重写它(继承的是 TComponent 的空实现),继承窗体里写的 ffChildPos
      会被静默丢掉。Order 按窗口序号算(spec §2)。 }
    procedure SetChildOrder(Child: TComponent; Order: Integer); override;
    { 本栏的窗口:激活;运行时同时展开,设计期不写 Collapsed(spec §5.1)。 }
    procedure ShowControl(AControl: TControl); override;
    { 此刻的主题尺寸下的推导值 —— Width(侧栏)/ Height(底栏)应当等于它。 }
    function DerivedAxisPx: Integer; overload;
    { 静默批次(spec §6.6):Begin 与 End 之间,栏不发 OnChange / OnCollapse / OnExpand、
      不通知设计器,栏里**每一个**窗口不发 OnShow / OnHide —— 切页、收起、展开、窗口进出
      都算在这一批里。EventsAllowed 是栏这一侧唯一的闸。计数,可嵌套。
      调用者:Loaded 应用 ActiveIndex(经 SwitchSilently);manager 加载结束时应用挂起的
      布局计划(TryFinishLoading,和布局批次 FLayoutBatch 一起包)。
      用户看得见的切换**不许**包进来。
      批次中途注册进来的窗口是这一批的一部分:注册时按当前层数补上静默,End 照样解除;
      中途离开的窗口在注销时把本栏加的那几层还掉 —— 否则它会带着静默去到别处,
      OnShow / OnHide 从此不响。
      **调用方必须 try/finally**:Begin 之后抛异常而没走到 End,整条栏和它的每个窗口
      从此都不发事件,而且没有一条断言会指向这里。 }
    procedure BeginSilent;
    procedure EndSilent;
    { 布局应用批次(spec §10.4)的进门 / 出门:批次层数(FLayoutBatch)和对齐锁一起进、一起出。
      manager 只对进了门的栏调 End(见 TTyToolWindowManager.ApplyText)。virtual:测试探针在
      这里模拟某一条栏进门时抛异常。 }
    procedure BeginLayoutBatch; virtual;
    procedure EndLayoutBatch; virtual;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    procedure Invalidate; override;
    { 图标解析用的列表:Images,为空时**读取时**回落到 Manager.Images(spec §8)。
      正在释放的列表和正在释放的 manager(csDestroying)都不算,答 nil / 不回落:它们的
      opRemove 到栏时,对方清没清引用说不准,重新订阅都不会又订回快死的那一个。
      Manager、Manager.Images 变化和 manager 被移除时都调 ImagesChanged;订阅和
      FreeNotification 都跟着这里走(SyncImageSubscription),被释放 / 摘走的订阅列表
      Notification 按身份注销,不看它是 Images 还是 Manager.Images。 }
    function EffectiveImages: TCustomImageList;
    { 图标条要画的那一格:ImageName 非空就按名字在 EffectiveImages 里找,找不到是 -1
      (不许乱画一个);名字为空才用序号。 }
    function ResolvedImageIndex(AWindow: TTyCustomToolWindow): Integer;
    { 图标条提示的文字:StripHint,空的时候 Caption。**不用 Hint**:LCL 顺着父链找第一个
      非空 Hint(application.inc:33-41),窗口的 Hint 一设,里面所有没设 Hint 的控件都会
      冒出它。栏的 CM_HINTSHOW(StripHintAt)用的就是它。 }
    function StripHintText(AWindow: TTyCustomToolWindow): string;
    procedure AutoAdjustLayout(AMode: TLayoutAdjustmentPolicy;
      const AFromPPI, AToPPI, AOldFormWidth, ANewFormWidth: Integer); override;
    { 设计器拖栏的边:只有这一种 SetBounds 写回 ExpandedSize(spec §6.1)。Align 不是
      Placement 要求的那一个时(比如用户改成 alClient)不写回:那时宽 / 高是对齐引擎按
      父控件摆出来的,父控件一变就会把 ExpandedSize 改掉。 }
    procedure SetBounds(ALeft, ATop, AWidth, AHeight: Integer); override;
    { 父控件的 OnResize 处理器跟着栏挪(spec §6.2 的收窄要看父控件的客户区)。 }
    procedure SetParent(NewParent: TWinControl); override;
    { 离开的两条路都在这之后才走到,窗口序号只能在这里记。 }
    procedure RemoveControl(AControl: TControl); override;
    { 漏进来的非窗口子控件(粘贴等途径,ChildClassAllowed 拦不住的那几条):运行时藏起来,
      设计期让出提示那一行(spec §6.1)。overload:不写的话单参数的 InsertControl(AControl)
      被这一个遮住,而它正是「直接塞进来」的那条路。 }
    procedure InsertControl(AControl: TControl; Index: Integer); overload; override;
    procedure Paint; override;
    { 栏的几何,AClient 是栏的客户区(AdjustClientRect 之前的那个)。见 TTyToolWindowBarLayout。 }
    function LayoutIn(const AClient: TRect): TTyToolWindowBarLayout;
    { 此刻客户区下的 LayoutIn。 }
    function BarLayout: TTyToolWindowBarLayout;
    { 窗口序号为 AIndex 的图标在栏上的格子;不在条上(收进溢出、底栏、越界)答空矩形。 }
    function StripItemRect(AIndex: Integer): TRect;
    { (X, Y)(栏客户区坐标)落在哪个部件上;图标时 AIndex 是窗口序号,否则 -1。
      绘制、手势、提示、设计期命中问的都是 BarLayout 这一份几何。 }
    function PartAt(X, Y: Integer; out AIndex: Integer): TTyToolWindowBarPart;
    { (X, Y) 上的图标对应的窗口;不在图标上答 nil(同 IndexOfTabAt,spec §6.8)。 }
    function WindowAtPos(X, Y: Integer): TTyCustomToolWindow;
    { 提示的纯查询:图标上答 True,给文字(StripHint,空则 Caption)和那一格的矩形。 }
    function StripHintAt(X, Y: Integer; out AText: string; out ARect: TRect): Boolean;
    { 收进溢出菜单的窗口(窗口序号,按窗口顺序)。 }
    function OverflowWindows: TTyToolWindowPlan;
    { 溢出菜单(点过一次溢出按钮才有);菜单项的 Tag 是窗口引用。 }
    property OverflowMenu: TPopupMenu read FOverflowMenu;
    { 溢出菜单挂在哪:答宿主控件(nil = 没有可挂的,底栏没有当前页时),APoint 是宿主客户区
      里的锚点。侧栏按栏自己的几何和读写方向;底栏按当前页标签行里的溢出按钮和**当前页**的
      读写方向(那一行就是按它镜像的)。ShowOverflowMenu 只问这一处。 }
    function OverflowMenuAnchorIn(out APoint: TPoint; out AAlignment: TPopupAlignment): TWinControl;
    { 最近一次右键落在哪个窗口的图标上;不在图标上是 nil(spec §6.8)。只读。 }
    property ContextWindow: TTyCustomToolWindow read FContextWindow;
    { 拉宽边(= BarLayout.Edge):运行时收起、没有窗口时为空。 }
    function EdgeRect: TRect;
    { 探针:手势此刻是否武装着 / 拖动中 —— 真实状态的只读视图。 }
    function GestureStateForTest: TTyToolWindowGestureState;
    function IsEdgeDraggingForTest: Boolean;
    function IsDraggingForTest: Boolean;
    { 探针:此刻在几层布局应用批次里(真实计数的只读视图)。 }
    property LayoutBatchForTest: Integer read FLayoutBatch;
    { 探针:底栏标签行上悬停的部件和窗口序号 —— 真实字段的只读视图。 }
    property HeaderHoverPartForTest: TTyToolWindowBarPart read FHeaderHoverPart;
    property HeaderHoverIndexForTest: Integer read FHeaderHoverIndex;
    property DropSlotForTest: Integer read FDropSlot;
    { 探针:此刻是不是别的栏拖过来的外来落点。 }
    property ForeignDropForTest: Boolean read FForeignDrop;
    { 探针:引擎最近一次压的临时光标(拖动中就是此刻显示的那个)。 }
    function DragCursorForTest: TCursor;
    { 探针:拖动期间轮询捕获的计时器此刻在不在。 }
    function HasCaptureTimerForTest: Boolean;
    { 探针:这一次手势里问过、记下答案的目标栏有几条(真实缓存的长度,不解引用)。 }
    function AllowedCacheCountForTest: Integer;
    { 探针:此刻挂着处理器的兄弟有几个(真实列表的长度)。 }
    function WatchedSiblingCountForTest: Integer;
    procedure ActivateWindow(AWindow: TTyCustomToolWindow);
    function IndexOfWindow(AWindow: TTyCustomToolWindow): Integer;
    function ChromeInsetPx: Integer;
    function StripSizePx: Integer;
    function EdgeSizePx: Integer;
    function ContentMinPx: Integer;
    property Windows[AIndex: Integer]: TTyCustomToolWindow read GetWindow;
    property WindowCount: Integer read GetWindowCount;
    { 设成不在本栏里的窗口(或 nil)被忽略。加载中答 nil(见 FActive)—— 继承窗体的第二遍
      加载例外,那时答第一遍挑好、正显示着的那一页。设进来的记作待定,Loaded 应用。 }
    property ActiveWindow: TTyCustomToolWindow read FActive write ActivateWindow;
    { 底栏最大化(spec §6.4):撑满父控件里编辑区那一截,还原回 ExpandedSize 推的高。**不
      published**:只在运行时有、不进 .lfm。收起、栏变空、换父控件、改 Placement 之前先还原。 }
    property Maximized: Boolean read FMaximized write SetMaximized;
  public
    { --- 底栏标题行的宿主那一面(spec §7.1 / §7.2)。标签行的像素属于当前页(窗口化子控件
      自己拥有那块像素),所以当前页替栏画、把输入转给栏;悬停、按下、溢出集合、最大化状态都在
      栏上。窗口找宿主经 Bar(「在不在栏里」只由 GetBar 回答)。AWindow = nil 表示「栏坐标、
      当前页的标题行」;没有当前页时几何为空、部件为 none。尺寸一律按入参 APPI(同 RenderTo
      的一套尺度)。只有栏一个实现、只有窗口一个调用方,所以是栏上的普通方法,不另立接口;
      放 public 是给测试直接问的。 --- }
    function HeaderMode(AWindow: TTyCustomToolWindow): TTyToolWindowHeaderMode;
    { 栏此刻是不是替当前页画标签行、收它的输入(spec §3.7「让出标签行」):运行时、底栏、有当前
      页、当前页**自己的** Enabled = False、栏没收起、拉宽边没吸附着(吸附 = 按收起排布,高 0)。 }
    function HostsTabRow: Boolean;
    { 此刻按「一侧没有窗口」隐藏(spec §6.9):运行时、侧栏、HideWhenEmpty、没有窗口(漏入的
      非窗口子控件运行时本来就藏着,不算)。推导宽 0,不写 Visible。 }
    function HiddenAsEmpty: Boolean;
    { 放置预览此刻该在的矩形,父控件客户区坐标(spec §9.8):从栏此刻的位置向编辑区一侧展开
      ShownAxisPx,钳进父控件调整后的客户区。不是隐藏的侧栏、没有父控件时为空。manager 的
      命中测试拿它当这条栏的探测矩形(spec §9.4)。 }
    function DropPreviewRect: TRect;
    { 放置预览控件(只读);没建过是 nil。 }
    property DropPreview: TTyToolWindowDropPreview read FDropPreview;
    { 「当前页的标签行此刻在谁身上」一处答(spec §3.7):宿主控件、行矩形(宿主客户区)、几何
      (行内)。HeaderZoneAt(nil, …)、PartAt、OverflowWindows、溢出菜单锚点、InvalidateHeader、
      按下态和插入线的捕获者判断都问它。见 TTyToolWindowTabRowHost。 }
    function TabRowHost: TTyToolWindowTabRowHost;
    { 底栏统一行高里操作区那一项:栏里所有窗口操作区 raw 首选高的最大值(spec §3.4)。 }
    function HeaderActionsHeight(AWindow: TTyCustomToolWindow; APPI: Integer): Integer;
    function HeaderGeometry(AWindow: TTyCustomToolWindow; ARowWidth, ARowHeight,
      APPI: Integer): TTyToolWindowHeaderGeom;
    procedure PaintHeader(AWindow: TTyCustomToolWindow; APainter: TTyPainter; const ARow: TRect;
      const AGeom: TTyToolWindowHeaderGeom; APPI: Integer);
    { AWindow 的客户区坐标(nil = 栏坐标、当前页);ARect 是命中部件的矩形,同一套坐标。 }
    function HeaderZoneAt(AWindow: TTyCustomToolWindow; X, Y: Integer; out AIndex: Integer;
      out ARect: TRect): TTyToolWindowZone;
    procedure HeaderMouseDown(AWindow: TTyCustomToolWindow; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    procedure HeaderMouseUp(AWindow: TTyCustomToolWindow; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    procedure HeaderMouseLeave(AWindow: TTyCustomToolWindow);
    { 捕获者是当前页、它收到了 LM_CANCELMODE(spec §9.7)。 }
    procedure HeaderCancelMode(AWindow: TTyCustomToolWindow);
    function HeaderHint(AWindow: TTyCustomToolWindow; X, Y: Integer; out AText: string;
      out ARect: TRect): Boolean;
    procedure HeaderContextPopup(AWindow: TTyCustomToolWindow; X, Y: Integer);
    property Placement: TTyToolWindowPlacement read FPlacement write SetPlacement default twpLeft;
    property ExpandedSize: Integer read FExpandedSize write SetExpandedSize
      default TyToolWindowDefaultExpandedSize;
    property Collapsed: Boolean read FCollapsed write SetCollapsed default False;
    { 窗口序号,跟随窗口身份:调顺序后当前页还是那个窗口,数值跟着变。 }
    property ActiveIndex: Integer read GetActiveIndex write SetActiveIndex default -1;
    { 跨侧拖动、MoveWindow、布局保存的协调者(spec §2)。同一个 manager 下与别的栏 Placement
      相同的每一条都不可用(spec §10.6),栏内调顺序照常。setter 在流式 fixup 里跑,从不抛异常。 }
    property Manager: TTyCustomToolWindowManager read FManager write SetManager;
    { 窗口图标的列表。对象查看器里窗口 ImageIndex 的下拉只看这一个(graphpropedits.pas:
      713-728),看不到 Manager.Images 回落 —— 只在 manager 上设列表时请设 ImageName。
      只设了 ImageIndex、没设 ImageName 的窗口要在两侧之间移动,就得用 manager 上的共享列表。 }
    property Images: TCustomImageList read FImages write SetImages;
    { 构造时按 Placement 设成 alLeft,default 必须跟着一致(否则 .lfm 省略的那个值加载后丢)。
      几何一律看 Placement,不看 Align。 }
    property Align default alLeft;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnCollapse: TNotifyEvent read FOnCollapse write FOnCollapse;
    property OnExpand: TNotifyEvent read FOnExpand write FOnExpand;
    { 一侧没有窗口时整条隐藏(推导宽度为 0,Visible 不动),默认开;只对侧栏起作用 —— 底栏没有
      窗口时本来就高 0。设计期永远不隐藏。隐藏的栏照样可用(IsBarUsable / UsableBar /
      MoveWindow),拖动时在它的位置显示放置预览(spec §6.9 / §9.8)。 }
    property HideWhenEmpty: Boolean read FHideWhenEmpty write SetHideWhenEmpty default True;
  published
    { 沿栏轴向的那一边由 ExpandedSize 推出来,不进 .lfm。 }
    property Width stored WidthIsStored;
    property Height stored HeightIsStored;
  end;

  { TTyToolWindowBar publishes TTyCustomToolWindowBar's properties; everything lives in TTyCustomToolWindowBar. }
  TTyToolWindowBar = class(TTyCustomToolWindowBar)
  published
    property Version;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property TabOrder;
    property TabStop;
    property OnClick;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseUp;
    property OnMouseMove;
    property OnMouseEnter;
    property OnMouseLeave;
    property OnMouseWheel;
    property OnMouseWheelUp;
    property OnMouseWheelDown;
    property OnContextPopup;
    property OnResize;
    property OnChangeBounds;
    property AutoSize;
    property BorderWidth;
    property ChildSizing;
    property DragMode;
    property DragKind;
    property DragCursor;
    property OnDragOver;
    property OnDragDrop;
    property OnStartDrag;
    property OnEndDrag;
    property OnMouseWheelHorz;
    property OnMouseWheelLeft;
    property OnMouseWheelRight;
    property OnShowHint;
    property PopupMenu;
    property Constraints;
    property BorderSpacing;
    property ParentShowHint;
    property Action;
    property OnPaint;
    property OnKeyDown;
    property OnKeyUp;
    property OnKeyPress;
    property OnUTF8KeyPress;
    property OnEnter;
    property OnExit;
    property OnEditingDone;
    property StyleClass;
    property StyleOverride;
    property Controller;
    property Placement;
    property ExpandedSize;
    property Collapsed;
    property ActiveIndex;
    property Manager;
    property Images;
    property Align;
    property OnChange;
    property OnCollapse;
    property OnExpand;
    property HideWhenEmpty;
  end;

  { spec §9.9:跨栏移动之前问一次(拖动悬停、放下、MoveWindow、排队的移动执行前)。 }
  TTyCanMoveWindowEvent = procedure(Sender: TObject; AWindow: TTyCustomToolWindow;
    ATargetBar: TTyCustomToolWindowBar; var AAllow: Boolean) of object;
  { spec §6.6:运行时窗口的栏或索引真正变了之后(手势、MoveWindow、WindowIndex、同一 manager 下
    直接改 Parent)。AOldIndex 是它在 ASourceBar 里原来的窗口序号。 }
  TTyWindowMovedEvent = procedure(Sender: TObject; AWindow: TTyCustomToolWindow;
    ASourceBar: TTyCustomToolWindowBar; AOldIndex: Integer) of object;

  { 派发 manager 事件那几处放在栈上的一格(内部类型,不是公开 API):处理器里把 manager 释放了
    (spec §6.6 不许,但不许崩),析构把链上每一格的 Alive 置 False;处理器返回后只看这一格,
    不碰 manager 身上的任何成员。 }
  PTyToolWindowLife = ^TTyToolWindowLife;
  TTyToolWindowLife = record
    Alive: Boolean;
    Prev: PTyToolWindowLife;
  end;

  { 工具窗口栏的协调者的基类(spec §2):栏、窗口、手势引擎用到的那一面 —— 注册表、拖动状态、
    共享图片列表、结构检查、两个移动事件、一次跨栏移动的提交。MoveWindow、队列、布局的保存 /
    读取 / 时机在 TTyToolWindowManager(tyControls.ToolWindows.Manager)。栏的 Manager 属性是
    这个类型,窗体上放的是 TTyToolWindowManager。
    本单元里的栏、窗口、引擎经这里的 protected / private 成员回调 manager(同一单元看得见);
    派生类要动栏和窗口的内部状态(静默换父、摆位置、批次……)也只经这里那几个 protected 方法,
    栏和窗口的私有成员不对外开放。 }
  TTyCustomToolWindowManager = class(TTyComponent)
  private
    FImages: TCustomImageList;
    FOnCanMoveWindow: TTyCanMoveWindowEvent;
    FOnWindowMoved: TTyWindowMovedEvent;
    { 栈上生命格的链头(见 TTyToolWindowLife)。 }
    FLife: PTyToolWindowLife;
    { 正在拖图标的那条栏(spec §9.2「标记 manager 正在拖」);nil = 没在拖。由源栏的引擎写:
      进入拖动时置上,收尾(ReleaseResources)时清。 }
    FDragSource: TTyCustomToolWindowBar;
    { FDragSource 只经这里写:值变了就调 DragSourceChanged(E 期,放置预览要跟着)。 }
    procedure SetDragSource(ABar: TTyCustomToolWindowBar);
    procedure AddBar(ABar: TTyCustomToolWindowBar);
    procedure RemoveBar(ABar: TTyCustomToolWindowBar);
    procedure SetImages(AValue: TCustomImageList);
    { 每条没在释放的注册栏的生效列表可能换了(spec §8)。 }
    procedure NotifyImagesChanged;
    { 发 OnWindowMoved 的门:manager 和源栏都不在设计 / 加载 / 释放中(spec §6.6)。 }
    function MovedEventAllowed(ASource: TTyCustomToolWindowBar): Boolean;
    { 参与拖动的栏(源栏或此刻的目标栏)改了 Collapsed / Placement / Manager:取消。 }
    procedure BarChanged(ABar: TTyCustomToolWindowBar);
    { 注册栏的 Placement 集合变了(加进 / 摘掉一条栏、某条栏改了 Placement):每条栏的冲突提示
      都可能出现或消失(spec §10.6)。可用性现算,这里只让它们按新答案重排、重画。 }
    procedure PlacementsChanged;
  protected
    { 注册着的栏,注册顺序,无语义(「先注册的赢」不成立:fixup 倒序执行,spec §10.6)。 }
    FBars: array of TTyCustomToolWindowBar;
    { > 0 = 正在发本 manager 的事件:处理器里再调 MoveWindow 答 False(spec §9.9)。 }
    FEventDepth: Integer;
    { 生命格进链 / 出链(见 TTyToolWindowLife)。Leave 在格子已死时什么都不做 —— 那时 Self
      是悬垂的。 }
    procedure EnterLife(var ALife: TTyToolWindowLife);
    procedure LeaveLife(var ALife: TTyToolWindowLife);
    { 派发本 manager 的事件:生命格 + FEventDepth 一起进、一起出。 }
    procedure EnterEvent(var ALife: TTyToolWindowLife);
    procedure LeaveEvent(var ALife: TTyToolWindowLife);
    { spec §9.9 的结构检查(不问事件)。ASource 出参是窗口此刻的栏。 }
    function StructureAllows(AWindow: TTyCustomToolWindow; ATarget: TTyCustomToolWindowBar;
      out ASource: TTyCustomToolWindowBar): Boolean;
    { 发 OnWindowMoved(spec §6.6),包在 FEventDepth 里:处理器里再调 MoveWindow 答 False。 }
    procedure WindowMoved(AWindow: TTyCustomToolWindow; ASource: TTyCustomToolWindowBar; AOldIndex: Integer);
    { 真正的一次跨栏移动(spec §9.5 的顺序,跟直接改 Parent 同一条 CommitCrossMove)。调用方
      已经过了结构检查和 CanMoveWindow。AIndex 已经换算好(MaxInt = 末尾)。 }
    procedure MoveNow(AWindow: TTyCustomToolWindow; ATarget: TTyCustomToolWindowBar; AIndex: Integer);
    { 拖放提交(spec §9.5):结构检查和 CanMoveWindow(放下时再问一次)都过才挪,**同步**,
      窗体 Showing 了也不排队(源栏不在窗口里,LCL 在 MouseUp 之前已放掉捕获)。 }
    function MoveFromDrop(AWindow: TTyCustomToolWindow; ATarget: TTyCustomToolWindowBar;
      ASlot: Integer): Boolean;
    { --- 栏 / 窗口 / 引擎回调的钩子。基类的实现是「没有这回事」,TTyToolWindowManager 重写。 --- }
    { 改布局之前(收起、尺寸、调顺序、跨栏、当前页):代码搭的 manager 在这里记默认布局
      (spec §10.5)。调用方在**改之前**调。 }
    procedure NoteLayoutChanging(ABar: TTyCustomToolWindowBar); virtual;
    { spec §10.5:最后一个离开 csLoading 的参与者(manager、注册栏)在自己的 Loaded 最后调它。 }
    procedure TryFinishLoading; virtual;
    { 源栏 ASource 上拖着它手势里的窗口,屏幕点 AScreen 落在哪条栏的哪个槽位(spec §9.4):答
      源栏自己、另一侧栏,或 nil(没有目标)。基类只认源栏自己的图标条。 }
    function DropTargetAt(ASource: TTyCustomToolWindowBar; const AScreen: TPoint;
      out ASlot: Integer): TTyCustomToolWindowBar; virtual;
    { 窗口的 WindowIndex:这个窗口还有排着的移动时排在它后面、答 True(spec §9.9);否则答
      False,由窗口当场调顺序。 }
    function QueueWindowIndex(AWindow: TTyCustomToolWindow; AIndex: Integer): Boolean; virtual;
    { 一条栏离开了本 manager(注销、被释放、从 Owner 摘走):它不再是排队移动的目标。 }
    procedure BarRemoved(ABar: TTyCustomToolWindowBar); virtual;
    { 「正在拖」变了(进入拖动 / 手势收尾,E 期):ASource 是此刻在拖的栏,nil = 不拖了。
      TTyToolWindowManager 在这里显示 / 收掉隐藏侧栏的放置预览(spec §9.8)。基类什么都不做。 }
    procedure DragSourceChanged(ASource: TTyCustomToolWindowBar); virtual;
    { 放置预览(spec §9.8):显示 / 收掉 ABar 的那一块。 }
    procedure BarShowDropPreview(ABar: TTyCustomToolWindowBar);
    procedure BarHideDropPreview(ABar: TTyCustomToolWindowBar);
    { --- 给派生类动栏 / 窗口内部状态的窗口(栏和窗口的私有成员只在本单元看得见)。 --- }
    { 这一次手势里拖到 ATarget 行不行(引擎缓存,每条目标栏每次手势只问一次)。 }
    function DragAllows(ASource, ATarget: TTyCustomToolWindowBar): Boolean;
    { 栏的窗口,Controls 顺序。 }
    function BarWindows(ABar: TTyCustomToolWindowBar): TTyToolWindowArray;
    { 栏内调顺序,不发 OnWindowMoved(PlaceWindow)/ 发(ReorderWindow)。 }
    procedure BarPlace(ABar: TTyCustomToolWindowBar; AWindow: TTyCustomToolWindow; AIndex: Integer);
    procedure BarReorder(ABar: TTyCustomToolWindowBar; AWindow: TTyCustomToolWindow; AIndex: Integer);
    { 切页(SwitchCore:藏其余每一个、不挪焦点、不发 OnChange)。 }
    procedure BarSwitch(ABar: TTyCustomToolWindowBar; AWindow: TTyCustomToolWindow);
    { 布局应用批次(BeginLayoutBatch / EndLayoutBatch)、静默批次(BeginSilent / EndSilent)。 }
    procedure BarEnterBatch(ABar: TTyCustomToolWindowBar);
    procedure BarLeaveBatch(ABar: TTyCustomToolWindowBar);
    procedure BarBeginSilent(ABar: TTyCustomToolWindowBar);
    procedure BarEndSilent(ABar: TTyCustomToolWindowBar);
    { 静默换父(FQuietMove):不走直接改 Parent 的簿记、注册不即激活。 }
    procedure QuietReparent(AWindow: TTyCustomToolWindow; ABar: TTyCustomToolWindowBar);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    { 在自己的某个事件处理器里被释放(spec §6.6 不许):先于任何析构把栈上的生命格判死。 }
    procedure BeforeDestruction; override;
    destructor Destroy; override;
    { 这条栏是不是可用:注册在本 manager 上、不在释放中,且没有别的(不在释放中的)注册栏和它
      Placement 相同(spec §10.6)。
      现算不缓存:注册栏最多几条,现算比记得在 SetManager / SetPlacement / opRemove 三处失效可靠。
      设计期的冲突提示也问它;Placement 集合一变,PlacementsChanged 让每条栏按新答案重排、重画。 }
    function IsBarUsable(ABar: TTyCustomToolWindowBar): Boolean;
    { 此刻 Placement 为 APlacement 的可用栏(spec §10.6:同 Placement 的都不可用,所以最多一条);
      没有答 nil。现算。组件编辑器的「移到另一侧栏」、应用自己的「移到另一侧」菜单都问它。 }
    function UsableBar(APlacement: TTyToolWindowPlacement): TTyCustomToolWindowBar;
    { 结构检查 + OnCanMoveWindow(spec §9.9)。同一条栏永远 True、不问事件;设计期不问事件。
      没有副作用:不取消拖动、不记默认布局、不动任何状态。 }
    function CanMoveWindow(AWindow: TTyCustomToolWindow; ATargetBar: TTyCustomToolWindowBar): Boolean;
    { 取消此刻的图标拖动(spec §9.7);没在拖什么都不做。 }
    procedure CancelDrag;
    { 注册栏里有一条正在拖图标。 }
    function IsDragging: Boolean;
    { 探针:注册表里记着几条栏(真实表的长度;不解引用任何一条)。 }
    function BarCountForTest: Integer;
    { 两侧共用的图片列表:栏自己的 Images 为空时读取时回落到它(spec §8)。只设了 ImageIndex、
      没设 ImageName 的窗口要在两侧之间移动,就得用这一份。TTyToolWindowManager 里 published。 }
    property Images: TCustomImageList read FImages write SetImages;
    property OnCanMoveWindow: TTyCanMoveWindowEvent read FOnCanMoveWindow write FOnCanMoveWindow;
    property OnWindowMoved: TTyWindowMovedEvent read FOnWindowMoved write FOnWindowMoved;
  end;

{ 图标条溢出菜单挂在哪、怎么对齐(栏客户区坐标):菜单往内容区那一侧开 —— 左栏从溢出按钮的
  右沿往右,右栏从左沿往左。TPopupAlignment 是**阅读顺序**的量(paLeft = 贴阅读起点,
  TyPopupAnchorShift 在 RTL 下把位移反过来),而栏的几何是物理方向(Placement):菜单跟着栏
  读 RTL 时(TTyPopupMenu 按 PopupComponent 定方向),物理上往右开的是 paRight、往左开的是
  paLeft,所以这里按 Placement 与 ARightToLeft 的异或选。
  底栏(AOverflow 是当前页标签行里的溢出按钮):从按钮底边、按阅读起点往下开 —— LTR 锚在左沿、
  RTL 锚在右沿,都是 paLeft。 }
procedure TyToolWindowOverflowMenuAnchor(const AOverflow: TRect;
  APlacement: TTyToolWindowPlacement; ARightToLeft: Boolean; out APoint: TPoint;
  out AAlignment: TPopupAlignment);

implementation

uses
  ExtCtrls,  { TTimer:拖动期间轮询捕获还在不在 }
  LCLProc,   { OwnerFormDesignerModified:设计期切页要告诉 IDE }
  BGRABitmap, BGRABitmapTypes,  { 图标条:渲染出来的图标是调用方持有的 BGRA 位图 }
  tyControls.ImageCollection,   { TyTintBitmapAlpha / TyFadeBitmapAlpha:图标按状态着色 }
  tyControls.ImageDraw,  { TyImageIndexOfName / TyImageNameOfIndex:名字 ↔ 格子;TyRenderImage }
  tyControls.Badge,      { TyBadgeText / TyBadgeSize / TyBadgeCornerPos:角标的字和尺寸 }
  tyControls.Css.Values, { TyMix:渐变底的放置预览取中间色当擦除色 }
  tyControls.Menu;       { TTyPopupMenu:图标条的溢出菜单 }

{ --- TTyCustomToolWindow ------------------------------------------------------ }

constructor TTyCustomToolWindow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { 多击两个标志:底栏标题行的按下落在窗口的句柄上,LCL 数点击次数看的是收到消息的
    那个窗口化控件;不加的话第三次按下会被还原成普通按下,又生效一次。 }
  ControlStyle := ControlStyle + [csAcceptsControls, csDesignFixedBounds,
    csNoDesignVisible, csNoFocus, csTripleClicks, csQuadClicks];
  FImageIndex := -1;
  FHeaderPxValid := False;
  Align := alClient;
  Visible := False;
  { 构造里一个子对象都不建 —— 建了会在流式加载时翻倍。 }
end;

destructor TTyCustomToolWindow.Destroy;
begin
  { 置 nil:继承析构里注销时,栏还可能回头 Invalidate 本窗口(Invalidate 会碰缓存)。 }
  FreeAndNil(FPaintCache);
  inherited Destroy;
end;

function TTyCustomToolWindow.GetStyleTypeKey: string;
begin
  Result := TyToolWindowKey;
end;

function TTyCustomToolWindow.ImageIndexIsStored: Boolean;
begin
  { 名字是持久键,序号只在名字给不出答案时才进流。 }
  Result := (FImageName = '') and (FImageIndex >= 0);
end;

function TTyCustomToolWindow.GetImageIndex: TImageIndex;
var
  b: TTyCustomToolWindowBar;
  n: Integer;
begin
  { 名字能在生效列表里解析就答那一格;否则答最近一次写进来的序号 —— 于是「设名字、读序号」
    和反过来那一问答得一致(同 TTyTabSheet.GetImageIndex)。图标条画什么不看这里,看
    TTyToolWindowBar.ResolvedImageIndex:名字解析不出来时那边答 -1。 }
  if FImageName <> '' then
  begin
    b := Bar;
    if b <> nil then
    begin
      n := TyImageIndexOfName(b.EffectiveImages, FImageName);
      if n >= 0 then Exit(n);
    end;
  end;
  Result := FImageIndex;
end;

procedure TTyCustomToolWindow.SetImageIndex(AValue: TImageIndex);
var
  oldName: string;
begin
  if AValue < -1 then AValue := -1;   { 「没有图标」只有一个值 }
  FImageIndex := AValue;
  { 先记挂起:这个请求不管此刻换不换得成名字都成立 —— 只在换得成时才记的话,流进来的
    ImageIndex 在栏的列表 fixup 之前就没了。 }
  FImageIndexPending := True;
  oldName := FImageName;
  ResolveImageIndex;
  { 名字变了,SetImageName 已经重画过。没变的 —— 没有列表、外来列表、越界(名字一直是 ''),
    或者新序号恰好还是同名的那一格 —— 画的是序号,得在这里重画。 }
  if FImageName = oldName then InvalidateBar;
end;

procedure TTyCustomToolWindow.SetImageName(const AValue: string);
begin
  { 后写的算:按名字设了,之前挂起的那个序号就作废 —— 不然栏一拿到列表,挂起的序号会把
    刚设的名字盖掉。ResolveImageIndex 自己调这里之前已经清了挂起,不受影响。 }
  FImageIndexPending := False;
  if FImageName = AValue then Exit;
  FImageName := AValue;
  InvalidateBar;
end;

procedure TTyCustomToolWindow.SetStripHint(const AValue: TTranslateString);
begin
  if FStripHint = AValue then Exit;
  FStripHint := AValue;
  InvalidateBar;
end;

{$I tyControls.ToolWindows.Badge.inc}

procedure TTyCustomToolWindow.ResolveImageIndex;
var
  b: TTyCustomToolWindowBar;
  list: TCustomImageList;
begin
  if not FImageIndexPending then Exit;   { 没有挂起的:绝不碰已经设好的 ImageName }
  b := Bar;
  if b = nil then Exit;
  if csLoading in b.ComponentState then Exit;
  list := b.EffectiveImages;
  if list = nil then Exit;               { 栏还没有列表:进栏 / 设列表时再来 }
  FImageIndexPending := False;
  if FImageIndex < 0 then
    SetImageName('')                     { 明确写 -1 = 清掉图标 }
  else
    { 外来列表、越界:名字是 '',序号就是键。 }
    SetImageName(TyImageNameOfIndex(list, FImageIndex));
end;

procedure TTyCustomToolWindow.InvalidateBar;
var
  b: TTyCustomToolWindowBar;
begin
  b := Bar;
  if b <> nil then b.Invalidate;
end;

function TTyCustomToolWindow.GetBar: TTyCustomToolWindowBar;
begin
  if Parent is TTyCustomToolWindowBar then Result := TTyCustomToolWindowBar(Parent)
  else Result := nil;
end;

function TTyCustomToolWindow.IsActive: Boolean;
var
  b: TTyCustomToolWindowBar;
begin
  b := Bar;
  Result := (b <> nil) and (b.ActiveWindow = Self);
end;

function TTyCustomToolWindow.GetWindowIndex: Integer;
var
  b: TTyCustomToolWindowBar;
begin
  b := Bar;
  if b <> nil then Result := b.IndexOfWindow(Self) else Result := -1;
end;

procedure TTyCustomToolWindow.SetWindowIndex(AValue: Integer);
var
  b: TTyCustomToolWindowBar;
begin
  b := Bar;
  if b = nil then Exit;
  { 这个窗口还有排着的移动:排在它后面,按调用顺序执行(spec §9.9)—— 当场调的话,之后
    执行的移动会把这一次覆盖掉。 }
  if (b.Manager <> nil) and b.Manager.QueueWindowIndex(Self, AValue) then Exit;
  b.ReorderWindow(Self, AValue);
end;

function TTyCustomToolWindow.GetActions: TTyCustomToolWindowActions;
var
  i: Integer;
begin
  { 一个窗口只认 Controls[] 里的第一个操作区;粘贴等途径多出来的不参与标题行。
    不缓存:子控件增删、调顺序都不用再记得回来作废什么。 }
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyCustomToolWindowActions then
      Exit(TTyCustomToolWindowActions(Controls[i]));
  Result := nil;
end;

procedure TTyCustomToolWindow.TextChanged;
var
  b: TTyCustomToolWindowBar;
begin
  inherited TextChanged;
  { 标题就画在自己的标题行里(见 RenderTo),不重画就停在上一句。 }
  Invalidate;
  { 底栏:标题是一个标签,画在**当前页**里 —— 改的是别的页的标题也得让当前页重画。 }
  b := Bar;
  if b <> nil then b.InvalidateHeader;
end;

function TTyCustomToolWindow.HeaderMode: TTyToolWindowHeaderMode;
var
  b: TTyCustomToolWindowBar;
begin
  { 只看所在栏的**位置** —— 不看哪页是当前页,否则切页时正文会跳。
    「在不在栏里」只由 GetBar 一处回答;在栏里时模式由栏答(TTyToolWindowBar.HeaderMode)。 }
  b := Bar;
  if b = nil then Result := twhNone
  else Result := b.HeaderMode(Self);
end;

function TTyCustomToolWindow.HeaderInput(APPI, ARowWidth: Integer): TTyToolWindowHeaderInput;
begin
  Result := Default(TTyToolWindowHeaderInput);
  Result.Mode := HeaderMode;
  Result.RowWidth := ARowWidth;
  Result.RowHeight := HeaderHeightAt(APPI);
  Result.Pad := MulDiv(ActiveController.Metric(TyToolWindowHeaderPadVar,
    TyToolWindowHeaderPadDef), APPI, 96);
  Result.Gap := MulDiv(ActiveController.Metric(TyToolWindowHeaderGapVar,
    TyToolWindowHeaderGapDef), APPI, 96);
  Result.ActionsWidth := ActionsPreferredSize(APPI).cx;
  Result.BottomRule := HeaderRuleAt(APPI);
  { 镜像整套几何靠这一个字段。没有操作区时标题占的是对称的那一整条,镜像前后一模一样;
    有操作区时它就是看得见的位置差 —— 操作区到左端、标题到它右边,
    TestRightToLeftPutsTheActionsLeftAndTheCaptionRightOfIt 守着。 }
  Result.RightToLeft := IsRightToLeft;
end;

{ 标题行高的 **token 那一项**,带缓存,按自己字体的像素密度算。
  单独成一个过程是为了 Invalidate:它要比「主题动了没有」,而比的必须是同一个量 ——
  HeaderHeightPx 的返回值是 max(这一项, 操作区) 再钳到下限 1,token 为 0 时它永远不等于
  这一项,于是悬停、焦点、主题广播 —— 每一次重画都会整控件重排一遍。 }
function TTyCustomToolWindow.HeaderTokenPx: Integer;
var
  mdl: TTyStyleModel;
  ver: Cardinal;
  mode: TTyToolWindowHeaderMode;
begin
  mode := HeaderMode;
  mdl := ActiveController.Model;
  ver := mdl.ThemeVersion;
  { 键里既要版本号也要 model 身份:版本号是每个 model 各自算的,只按版本号键控
    会把 A 的值端给 B —— Controller 是 published,中途换得掉。 }
  if (not FHeaderPxValid) or (FHeaderPxAnchor <> TObject(mdl)) or (FHeaderPxVer <> ver)
     or (FHeaderPxPPI <> Font.PixelsPerInch) or (FHeaderPxRTL <> IsRightToLeft)
     or (FHeaderPxMode <> mode) then
  begin
    { twhNone 也进缓存,键照常存(连同 mode)。在查键之前就 Exit(0) 的话,缓存和
      FHeaderPxMode 都停在上一次 —— 比如还在栏里时的 26 —— 于是 Invalidate 从此每次都
      看见 0 <> 26、每次都整控件重排。窗口出栏到孤儿、跨栏移动的中间态都会走到这里。 }
    if mode = twhNone then
      FHeaderPxCache := 0
    else
      FHeaderPxCache := MulDiv(ActiveController.Metric(TyToolWindowHeaderHeightVar,
        TyToolWindowHeaderHeightDef), Font.PixelsPerInch, 96);
    FHeaderRuleCache := HeaderRuleUncached(Font.PixelsPerInch);
    FHeaderPxAnchor := TObject(mdl);
    FHeaderPxVer := ver;
    FHeaderPxPPI := Font.PixelsPerInch;
    FHeaderPxRTL := IsRightToLeft;
    FHeaderPxMode := mode;
    FHeaderPxValid := True;
  end;
  Result := FHeaderPxCache;
end;

function TTyCustomToolWindow.HeaderRuleUncached(APPI: Integer): Integer;
var
  S: TTyStyleSet;
begin
  Result := 0;
  if HeaderMode <> twhSide then Exit;
  S := ActiveController.Model.ResolveStyle(TyToolWindowHeaderKey,
    TyStyleClassFor(Self, StyleClass), [tysNormal]);
  if not TyBorderVisible(S) then Exit;
  Result := MulDiv(S.BorderWidth, APPI, 96);
  if Result < 1 then Result := 1;
end;

function TTyCustomToolWindow.HeaderRuleAt(APPI: Integer): Integer;
begin
  if APPI = Font.PixelsPerInch then
  begin
    HeaderTokenPx;              { 刷新同一把键下的缓存 }
    Result := FHeaderRuleCache;
  end
  else
    Result := HeaderRuleUncached(APPI);
end;

{ 操作区的首选尺寸(设备像素,按给定 PPI),**一处答**:标题行高拿它的高钳底、排布
  拿它的宽留位。两边各问各的话改一处漏一处,画出来的那条和挖出来的正文就会错开,
  而且不会红。只认第一个操作区(Actions),多出来的不进标题行。 }
function TTyCustomToolWindow.ActionsPreferredSize(APPI: Integer): TSize;
var
  act: TTyCustomToolWindowActions;
begin
  { 没有操作区、或者它被藏起来了,标题行高退化成 token 值、标题占满整条。 }
  act := Actions;
  if (act <> nil) and act.IsControlVisible then
    Result := act.PreferredSizeAt(APPI)
  else
  begin
    Result.cx := 0;
    Result.cy := 0;
  end;
end;

{ 标题行高,按**给定的** PPI。缓存键钉在 Font.PixelsPerInch 上,所以只有问的就是
  自己那个密度时才走缓存,别的密度现算 —— HeaderInput 要能按它的入参 APPI 回答。 }
function TTyCustomToolWindow.HeaderHeightAt(APPI: Integer): Integer;
var
  actionsPx: Integer;
begin
  if HeaderMode = twhNone then Exit(0);
  { 栏让出了标签行(当前页被禁用,spec §3.7):页自己不再留标题行,正文从页顶开始、操作区
    摆成空的。行高没变,只是长到了栏里。 }
  if (HeaderMode = twhBottom) and IsActive and Bar.HostsTabRow then Exit(0);
  if APPI = Font.PixelsPerInch then Result := HeaderTokenPx
  else Result := MulDiv(ActiveController.Metric(TyToolWindowHeaderHeightVar,
    TyToolWindowHeaderHeightDef), APPI, 96);
  { 操作区那一项**不缓存**:子控件增删 / 显隐 / 改尺寸都会触发整窗体自顶向下重排,
    现取就能跟上。底栏:栏里所有页统一一个行高(spec §3.4),由栏答 —— 切页时标签行不跳。
    这里只问栏各窗口操作区的首选高,不碰任何窗口的 HeaderTokenPx 缓存(那是每个窗口在自己
    Invalidate 里察觉换主题的唯一一条边,谁先读就是谁的)。底栏没有底线。 }
  if HeaderMode = twhBottom then
    actionsPx := Bar.HeaderActionsHeight(Self, APPI)
  else
  begin
    { 侧栏:操作区排在底线上面那一条带里(spec §4),行高要连底线一起够它。 }
    actionsPx := ActionsPreferredSize(APPI).cy;
    if actionsPx > 0 then Inc(actionsPx, HeaderRuleAt(APPI));
  end;
  if actionsPx > Result then Result := actionsPx;
  if Result < 1 then Result := 1;
end;

{ 标题行在给定客户区里占的那一条,**钳进这个客户区**。不钳的话控件比标题行还矮时
  (栏拖到很窄、或者正在动画)HeaderRowRect 会报出一个比控件还高的矩形,
  CustomAlignPosition 就照着它把操作区摆到控件外面去。一处钳 —— 正文区
  (AdjustClientRect)、HeaderGeomAt、HeaderRowRect、RenderTo 问的是同一条。
  照 TTyCard.LayoutAtPPI(Card.pas:181)。 }
function TTyCustomToolWindow.HeaderRowIn(const AClient: TRect; APPI: Integer): TRect;
var
  clientH, h: Integer;
begin
  clientH := AClient.Bottom - AClient.Top;
  if clientH < 0 then clientH := 0;
  h := HeaderHeightAt(APPI);
  if h > clientH then h := clientH;
  Result := Rect(AClient.Left, AClient.Top, AClient.Right, AClient.Top + h);
end;

function TTyCustomToolWindow.HeaderGeomAt(const AClient: TRect; APPI: Integer): TTyToolWindowHeaderGeom;
var
  inp: TTyToolWindowHeaderInput;
  row: TRect;
begin
  row := HeaderRowIn(AClient, APPI);
  { 底栏:标签行由栏统一排(标签宽、当前页、按钮都在栏上),行仍由这里钳。 }
  if HeaderMode = twhBottom then
    Exit(Bar.HeaderGeometry(Self, row.Right - row.Left, row.Bottom - row.Top, APPI));
  inp := HeaderInput(APPI, row.Right - row.Left);
  { HeaderInput 手上没有客户区,答的是没钳过的行高;钳在这里,一处。 }
  inp.RowHeight := row.Bottom - row.Top;
  Result := TyToolWindowHeaderLayout(inp);
end;

function TTyCustomToolWindow.EnsureActions: TTyCustomToolWindowActions;
var
  own: TComponent;
begin
  Result := Actions;
  if Result <> nil then Exit;
  { 窗体拥有,好让它进 .lfm、设计器里点得到。代码里 Create(nil) 的窗口没有 Owner,
    而 LCL 不释放没有 Owner 的子控件(TWinControl.Destroy 只把它们摘下来),所以照
    TTyPageControl 建页的规矩(PageControl.pas:332)回落到窗口自己。 }
  if Owner <> nil then own := Owner else own := Self;
  Result := TTyToolWindowActions.Create(own);
  { 窗口按自己的控制器读 pad / gap 给操作区留位;操作区不接这一个的话,它按
    TyDefaultController 量自己,留的宽就是在另一套主题下算的(同 PageControl.pas:280)。 }
  Result.Controller := Controller;
  Result.Parent := Self;
  Result.TabOrder := 0;
end;

procedure TTyCustomToolWindow.FocusFirst;
var
  form: TCustomForm;
  act: TTyCustomToolWindowActions;
  list: TFPList;
  c: TWinControl;
  pass, i: Integer;
begin
  { 同 SelectFirst(先要 TabStop 的,没有再放宽),但跳过操作区那一棵子树:切页把焦点带进新页
    时要落在正文里,不是标题行的按钮上(spec §5.1 第 5 步)。正文里一个可聚焦的都没有,
    才退回整个窗口(含操作区)—— 总比把焦点留在刚藏起来的旧页里强。 }
  form := GetParentForm(Self);
  if form = nil then Exit;
  act := Actions;
  list := TFPList.Create;
  try
    GetTabOrderList(list);
    for pass := 0 to 1 do
      for i := 0 to list.Count - 1 do
      begin
        c := TWinControl(list[i]);
        if (act <> nil) and ((c = act) or act.ContainsControl(c)) then Continue;
        if ((pass = 1) or c.TabStop) and c.Enabled and c.IsVisible then
        begin
          form.ActiveControl := c;
          Exit;
        end;
      end;
  finally
    list.Free;
  end;
  SelectFirst;
end;

{ 两边都是栏、一侧一底(按 Placement,不看 Align)。不带任何豁免:运行时改 Parent 的豁免在
  MovesAcrossBarKinds 里,manager 的结构检查(设计期也要拒)只用这一句。 }
function BarKindsDiffer(AOld, ANew: TWinControl): Boolean;
begin
  Result := (AOld <> ANew) and (AOld is TTyCustomToolWindowBar) and (ANew is TTyCustomToolWindowBar)
    and ((TTyCustomToolWindowBar(AOld).Placement = twpBottom)
         <> (TTyCustomToolWindowBar(ANew).Placement = twpBottom));
end;

{ 跨栏移动(MoveWindow、直接改 Parent)之后:焦点原来在窗口里的,还给它 —— 换父控件时 LCL
  把它挪走了(spec §3.2 / §9.5)。 }
procedure RestoreMovedFocus(AForm: TCustomForm; AWindow: TTyCustomToolWindow; AFocus: TWinControl);
begin
  if (AForm <> nil) and (AFocus <> nil) and AWindow.ContainsControl(AFocus)
     and AFocus.CanFocus then
    AForm.ActiveControl := AFocus;
end;

{ 跨栏移动延后下来的栏事件,按 spec §6.6 的顺序发:源栏 OnChange → 目标栏 OnExpand →
  目标栏 OnChange。源栏从不发 OnCollapse(拖空不写 Collapsed)。 }
procedure FireMovedBarEvents(ASource, ATarget: TTyCustomToolWindowBar;
  ASourceEvents, ATargetEvents: TTyToolWindowBarEvents);
begin
  if twbeChange in ASourceEvents then ASource.FireBarEvent(twbeChange);
  if twbeExpand in ATargetEvents then ATarget.FireBarEvent(twbeExpand);
  if twbeChange in ATargetEvents then ATarget.FireBarEvent(twbeChange);
end;

function TTyCustomToolWindow.MovesAcrossBarKinds(AOld, ANew: TWinControl): Boolean;
const
  Exempt = [csLoading, csDesigning, csDestroying];
begin
  { 一侧一底(BarKindsDiffer),并且窗口和两条栏都不在加载 / 设计 / 释放中。孤儿进栏、
    出栏到 nil、同类栏之间都不算。 }
  Result := BarKindsDiffer(AOld, ANew)
    and (Exempt * ComponentState = [])
    and (Exempt * AOld.ComponentState = [])
    and (Exempt * ANew.ComponentState = []);
end;

{ 取消 ABar 参与的图标拖动:有 manager 的问 manager(它知道此刻谁在拖),没有的看栏自己。 }
procedure CancelBarDrag(ABar: TTyCustomToolWindowBar);
begin
  if ABar.Manager <> nil then ABar.Manager.CancelDrag
  else if ABar.FGesture.State = twgsDragging then ABar.ResetGesture(twgeCancel);
end;

{ 一次跨栏移动的实体,MoveWindow(经 MoveNow)和运行时直接改 Parent 共用(spec §3.2 / §9.5 /
  §6.6):取消进行中的拖动 → 改之前记默认布局 → 记焦点和原序号 → 两条栏延后事件、停对齐 →
  静默换父(FQuietMove:注册不即激活)→ 调到 AIndex(MaxInt = 末尾)→ 目标栏激活并展开 →
  恢复对齐 → 焦点还回去 → 按 §6.6 的顺序发栏事件 → 两条栏在同一个 manager 下时发
  OnWindowMoved。整段包在参与的 manager 的 FEventDepth 里:栏事件、OnWindowMoved、换父时
  回落页的 OnShow / OnHide 的处理器里再调 MoveWindow / Load / Reset 都答 False。处理器里把
  manager 释放了(spec §6.6 不许)也不崩:生命格判死之后不再碰它。 }
procedure CommitCrossMove(AWindow: TTyCustomToolWindow; ASource, ATarget: TTyCustomToolWindowBar;
  AIndex: Integer);
var
  mSrc, mDst: TTyCustomToolWindowManager;
  lifeSrc, lifeDst: TTyToolWindowLife;
  same: Boolean;
  form: TCustomForm;
  focus: TWinControl;
  oldIdx: Integer;
  srcEv, dstEv: TTyToolWindowBarEvents;
begin
  mSrc := ASource.Manager;
  mDst := ATarget.Manager;
  same := (mSrc <> nil) and (mSrc = mDst);
  if same then mDst := nil;
  if mSrc <> nil then mSrc.EnterEvent(lifeSrc);
  if mDst <> nil then mDst.EnterEvent(lifeDst);
  try
    { spec §9.7:取消此刻的拖动(拖放提交走到这里时手势已经收尾了)。 }
    CancelBarDrag(ASource);
    CancelBarDrag(ATarget);
    { 跨栏也是布局:改之前记默认布局(spec §10.5)。 }
    if mSrc <> nil then mSrc.NoteLayoutChanging(ASource);
    if mDst <> nil then mDst.NoteLayoutChanging(ATarget);
    { spec §9.5:记下焦点控件和原来的窗口序号。 }
    form := GetParentForm(ATarget);
    if form <> nil then focus := form.ActiveControl else focus := nil;
    oldIdx := ASource.IndexOfWindow(AWindow);
    srcEv := [];
    dstEv := [];
    { 两条栏的事件先记下、最后按 spec §6.6 的顺序发:都在 EnableAlign 和焦点恢复之后。 }
    ASource.BeginDeferEvents;
    try
      ATarget.BeginDeferEvents;
      try
        ASource.DisableAlign;
        try
          ATarget.DisableAlign;
          try
            { SetParent 里:从源栏注销并回落当前页、注册到目标栏、推 Controller、按目标栏的列表
              解析图标。W 里所有句柄重建(LCL 换父控件的固有行为)。 }
            AWindow.FQuietMove := True;
            try
              AWindow.Parent := ATarget;
            finally
              AWindow.FQuietMove := False;
            end;
            ATarget.PlaceWindow(AWindow, AIndex);
            { W 成为目标栏的当前页并展开(设计期只激活,不写 Collapsed,同 ShowControl)。 }
            ATarget.ActivateExpanded(AWindow);
          finally
            ATarget.EnableAlign;
          end;
        finally
          ASource.EnableAlign;
        end;
      finally
        dstEv := ATarget.EndDeferEvents;
      end;
    finally
      srcEv := ASource.EndDeferEvents;
    end;
    RestoreMovedFocus(form, AWindow, focus);
    { 设计期(组件编辑器的「移到另一侧栏」经 MoveWindow):不发事件,通知设计器(同
      ReorderWindow)。直接改 Parent 在设计期不走这里。 }
    if csDesigning in ATarget.ComponentState then
    begin
      OwnerFormDesignerModified(ATarget);
      Exit;
    end;
    FireMovedBarEvents(ASource, ATarget, srcEv, dstEv);
    { 前面任何一个处理器(回落页的 OnShow、栏事件)里把 manager 释放了:不再碰它。 }
    if same and lifeSrc.Alive then mSrc.WindowMoved(AWindow, ASource, oldIdx);
  finally
    if mDst <> nil then mDst.LeaveEvent(lifeDst);
    if mSrc <> nil then mSrc.LeaveEvent(lifeSrc);
  end;
end;

function TTyCustomToolWindow.BooksDirectMove(AOld, ANew: TWinControl): Boolean;
begin
  { 运行时同类栏之间直接改 Parent。MoveWindow / 布局应用自己换父时(FQuietMove)不算;
    布局应用的批次里(某一页的 OnShow / OnHide 里用户直接改 Parent)也不算 —— 批次不发栏事件
    和 OnWindowMoved、不自己展开,当前页由批次最后统一定(拦不住,只能不添乱)。 }
  Result := (not FQuietMove) and (AOld <> ANew)
    and (AOld is TTyCustomToolWindowBar) and (ANew is TTyCustomToolWindowBar)
    and ([csLoading, csDesigning, csDestroying]
         * (ComponentState + AOld.ComponentState + ANew.ComponentState) = [])
    and (TTyCustomToolWindowBar(AOld).FLayoutBatch = 0) and (TTyCustomToolWindowBar(ANew).FLayoutBatch = 0);
end;

procedure TTyCustomToolWindow.SetParent(NewParent: TWinControl);
var
  old: TWinControl;
begin
  old := Parent;
  { spec §3.2:运行时侧栏和底栏之间不能直接改 Parent(标题行模式、布局串的键都不一样)——
    在继承之前抛,窗口还在原来的栏里、原来的状态一点没动。**不在 CheckNewParent 里做**:
    读取器和设计器粘贴也经过它,而那两条路要放行(加载中 / 设计期豁免)。 }
  if MovesAcrossBarKinds(old, NewParent) then
    raise EInvalidOperation.Create(rsTyToolWindowCrossBarMove);
  { spec §3.2:运行时同类栏之间直接改 Parent —— 跟 MoveWindow 走同一条 CommitCrossMove(目标栏
    激活并展开、焦点还回去、事件按同一顺序、同一 manager 下发 OnWindowMoved),不问否决。它自己
    静默换父,换父那一句回到这里走下面的普通分支。
    不排在这个窗口排着的移动后面(MoveWindow 会):Parent 是属性,赋值返回时它就得是新值;排着的
    那几项执行时自己重新检查。 }
  if BooksDirectMove(old, NewParent) then
  begin
    CommitCrossMove(Self, TTyCustomToolWindowBar(old), TTyCustomToolWindowBar(NewParent), MaxInt);
    Exit;
  end;
  inherited SetParent(NewParent);
  { 离开一条栏跟进入一条栏一样是窗口表的事件。任一方正在拆:释放那条路走栏的
    Notification(opRemove),而旧栏这时可能已经拆了一半。 }
  if (old <> NewParent) and (old is TTyCustomToolWindowBar)
     and not (csDestroying in ComponentState)
     and not (csDestroying in old.ComponentState) then
    TTyCustomToolWindowBar(old).UnregisterWindow(Self);
  { 注册本身推 Controller;流式加载、设计器放下、代码里 Parent := 都走这一条。 }
  if NewParent is TTyCustomToolWindowBar then
    TTyCustomToolWindowBar(NewParent).RegisterWindow(Self)
  else if not (csDestroying in ComponentState) then
  begin
    if csDesigning in ComponentState then
    begin
      { 设计期的孤儿(spec §3.2):撤销删除、粘贴等途径落到栏外的窗口要看得见,才能右键
        「移回栏里」。先摘 csNoDesignVisible 再写 Visible(同 ShowWindowNow 的顺序)——
        只摘标志不够:设计期的显示状态是 `Visible or (csDesigning and not csNoDesignVisible)`,
        触发重算的是写 Visible,而孤儿的 Visible 往往已经是 False,写同值是空操作。
        Visible 是 stored False,这一句不进 .lfm。回到栏里由栏的切页把标志加回去。
        顶上那一行提示见 OrphanNoteRectIn,下面的 RelayoutHeader 让出它。 }
      ControlStyle := ControlStyle - [csNoDesignVisible];
      Visible := True;
    end
    else
      { 运行时的孤儿保持隐藏:没有栏替它守「一次只显示一页」,带着 Visible = True 挪出来的
        当前页会原样杵在新父控件上。 }
      Visible := False;
  end;
  { 标题行模式跟着父控件变(侧栏 / 底栏 / 孤儿),内缩量变了就得重排。 }
  if not (csDestroying in ComponentState) then
    RelayoutHeader;
end;

procedure TTyCustomToolWindow.SetVisible(Value: Boolean);
var
  b: TTyCustomToolWindowBar;
begin
  b := Bar;
  { 每条栏同时只显示一页,这个不变量由栏守(spec §3.3)。栏自己在切页 / 收起 / 展开
    (FBarSwitching),或者窗口不在栏里(构造、孤儿):照写。 }
  if (b = nil) or b.FBarSwitching then
  begin
    { 探针只读真实状态:此刻的 ControlStyle。 }
    FNoDesignVisibleAtShow := csNoDesignVisible in ControlStyle;
    inherited SetVisible(Value);
    Exit;
  end;
  { 加载中的赋值忽略:当前页由栏的 Loaded 挑。正在拆的窗口也不许借这一句去收起栏。 }
  if ([csLoading, csDestroying] * ComponentState <> [])
     or ([csLoading, csDestroying] * b.ComponentState <> []) then Exit;
  if csDesigning in ComponentState then
  begin
    { 设计期:外部设 True 只激活,不写 Collapsed;对当前页设 False 忽略。否则对象查看器里
      一勾,Collapsed 就被写进 .lfm,设计期又永远按展开显示,用户看不到,运行时却是收起的。 }
    if Value then b.ActivateWindow(Self);
    Exit;
  end;
  if Value then
  begin
    { 运行时对非当前页设 True → 通过栏激活并展开;对当前页设 True、栏收起着 → 展开。
      收起着时 ActivateWindow 只换当前页,展开那一步才把它显示出来。 }
    if b.FActive <> Self then b.ActivateWindow(Self);
    b.Collapsed := False;
  end
  else if b.FActive = Self then
    { 对当前页设 False → 收起栏(焦点搬家在 SetCollapsed 里)。 }
    b.Collapsed := True
  else
  begin
    { 非当前页本来就该藏着;万一还显示着(从别处带着 Visible 挪进来的),照藏。 }
    FNoDesignVisibleAtShow := csNoDesignVisible in ControlStyle;
    inherited SetVisible(False);
  end;
end;

procedure TTyCustomToolWindow.SetController(AValue: TTyStyleController);
var
  i: Integer;
begin
  inherited SetController(AValue);
  { 继承那一句在值没变时直接返回,推送照做:操作区可能是后插进来、带着别的控制器的。 }
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyCustomToolWindowActions then
      TTyCustomToolWindowActions(Controls[i]).Controller := AValue;
end;

procedure TTyCustomToolWindow.InsertControl(AControl: TControl; Index: Integer);
begin
  inherited InsertControl(AControl, Index);
  if AControl is TTyCustomToolWindowActions then
  begin
    TTyCustomToolWindowActions(AControl).Controller := Controller;
    { 带着子控件挂进来的:LCL 不替它调 AdjustSize,底栏的共用行高要在这一刻知道(spec §3.4)。 }
    TTyCustomToolWindowActions(AControl).AdjustSize;
  end;
end;

procedure TTyCustomToolWindow.RemoveControl(AControl: TControl);
var
  b: TTyCustomToolWindowBar;
begin
  inherited RemoveControl(AControl);
  if AControl is TTyCustomToolWindowActions then
  begin
    { 下一次挂进窗口时从「没有」比起。 }
    TTyCustomToolWindowActions(AControl).FLastPreferred := Default(TSize);
    b := Bar;
    if (b <> nil) and not (csDestroying in ComponentState) then b.ActionsSizeChanged;
  end;
end;

function TTyCustomToolWindow.HeaderHeightPx: Integer;
begin
  { 按自己字体的像素密度问的那一问,**没钳过**。正文区(AdjustClientRect)和
    HeaderRowRect 要的是钳进客户区的那一条,走 HeaderRowIn,不走这里。 }
  Result := HeaderHeightAt(Font.PixelsPerInch);
end;

function TTyCustomToolWindow.HeaderRowRect: TRect;
begin
  Result := HeaderRowIn(Rect(0, 0, ClientWidth, ClientHeight), Font.PixelsPerInch);
end;

function TTyCustomToolWindow.BodyRect: TRect;
begin
  { 查询就调自己的 AdjustClientRect —— 正文区只有一个定义,手摆和对齐摆落在同一处。 }
  Result := ClientRect;
  AdjustClientRect(Result);
end;

function TTyCustomToolWindow.OrphanNoteRect: TRect;
begin
  Result := OrphanNoteRectIn(Rect(0, 0, ClientWidth, ClientHeight), Font.PixelsPerInch);
end;

function TTyCustomToolWindow.OrphanNoteRectIn(const AClient: TRect; APPI: Integer): TRect;
var
  h: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if ([csDesigning, csDestroying] * ComponentState <> [csDesigning]) or (Bar <> nil) then Exit;
  h := MulDiv(ActiveController.Metric(TyToolWindowHeaderHeightVar,
    TyToolWindowHeaderHeightDef), APPI, 96);
  if h > AClient.Bottom - AClient.Top then h := AClient.Bottom - AClient.Top;
  if h <= 0 then Exit;
  Result := Rect(AClient.Left, AClient.Top, AClient.Right, AClient.Top + h);
end;

procedure TTyCustomToolWindow.AdjustClientRect(var ARect: TRect);
var
  n: TRect;
begin
  inherited AdjustClientRect(ARect);
  { 正文从钳过的标题行底下开始 —— 跟画出来的那一条、摆操作区的那一条是同一处钳。 }
  ARect.Top := HeaderRowIn(ARect, Font.PixelsPerInch).Bottom;
  { 设计期孤儿:顶上让出提示那一行。正文控件通常 alClient,不让出来的话提示一个像素都
    露不出来(同栏的 StrayNote)。孤儿没有标题行,上一句不挪 Top。 }
  n := OrphanNoteRectIn(ARect, Font.PixelsPerInch);
  if n.Bottom > ARect.Top then ARect.Top := n.Bottom;
end;

function TTyCustomToolWindow.ChildClassAllowed(ChildClass: TClass): Boolean;
begin
  { 用 InheritsFrom 不用 = :派生类同样不许进来。设计期面板拖放和「改变父控件」都问这里;
    粘贴漏过去的由孤儿模式显示出来(spec §11),不在 CheckNewParent 里抛异常。 }
  Result := inherited ChildClassAllowed(ChildClass)
    and not ChildClass.InheritsFrom(TTyCustomToolWindow)
    and not ChildClass.InheritsFrom(TTyCustomToolWindowBar);
end;

procedure TTyCustomToolWindow.AlignControls(AControl: TControl; var RemainingClientRect: TRect);
var
  row: TRect;
  g: TTyToolWindowHeaderGeom;
begin
  inherited AlignControls(AControl, RemainingClientRect);
  { 标题行的样子跟着操作区走:它变宽、变高、被藏起来,标题的省略号、那条底色的高度
    都得重画。而窗口尺寸一个像素没动,NeedsRender 答「不用」—— 运行时 blit 出旧的
    那一帧,设计期不走缓存、看着一切正常(spec §3.5)。子控件的变化都会走到整窗体
    DoAllAutoSize 的 AlignControl(control.inc:3097),所以在这里比。
    只在真的变了时才丢:每一遍 DoAllAutoSize 都会来这里,无条件丢缓存就等于没有缓存。 }
  row := HeaderRowRect;
  g := HeaderGeomAt(Rect(0, 0, ClientWidth, ClientHeight), Font.PixelsPerInch);
  if EqualRect(row, FAlignedRow) and TyToolWindowSameGeom(g, FAlignedGeom) then Exit;
  FAlignedRow := row;
  FAlignedGeom := g;
  if FPaintCache <> nil then FPaintCache.Drop;
  inherited Invalidate;
end;

procedure TTyCustomToolWindow.CustomAlignPosition(AControl: TControl; var ANewLeft, ANewTop,
  ANewWidth, ANewHeight: Integer; var AlignRect: TRect; AlignInfo: TAlignInfo);
var
  g: TTyToolWindowHeaderGeom;
  body: TRect;
  sz: TSize;
begin
  if not (AControl is TTyCustomToolWindowActions) then
  begin
    inherited CustomAlignPosition(AControl, ANewLeft, ANewTop, ANewWidth, ANewHeight,
      AlignRect, AlignInfo);
    Exit;
  end;
  if (AControl = Actions) and (HeaderMode <> twhNone) then
  begin
    { 四个边界全部取标题行的答案 —— 跟 RenderTo 画标题用的是同一份 HeaderGeomAt、同一个
      客户区,画出来的和摆出来的不会错开。行从客户区原点开始,所以行内坐标就是客户区坐标。 }
    g := HeaderGeomAt(Rect(0, 0, ClientWidth, ClientHeight), Font.PixelsPerInch);
    ANewLeft := g.Actions.Left;
    ANewTop := g.Actions.Top;
    ANewWidth := g.Actions.Right - g.Actions.Left;
    ANewHeight := g.Actions.Bottom - g.Actions.Top;
    Exit;
  end;
  { 多出来的操作区(只有设计期走得到这里,运行时它不露面),以及没有标题行的窗口
    (孤儿,不在栏里)的那一个:放在正文区左上角,按 raw 首选尺寸(spec §3.2 / §3.4)。 }
  body := BodyRect;
  sz := TTyCustomToolWindowActions(AControl).PreferredSizeAt(Font.PixelsPerInch);
  ANewLeft := body.Left;
  ANewTop := body.Top;
  ANewWidth := sz.cx;
  ANewHeight := sz.cy;
end;

procedure TTyCustomToolWindow.RelayoutHeader;
begin
  if FRelayouting then Exit;
  FRelayouting := True;
  try
    { 客户区内缩量变了就必须重排,只 Invalidate 会让 alClient 子控件盖住标题行。 }
    Realign;
    { 本方法自己丢缓存,所以直接调它也是安全的。下面那一句是 **inherited** Invalidate
      (走本类的 Invalidate 会再查一遍缓存键、可能又绕回这里),而它不丢缓存 ——
      指望调用方顺带丢的话,AutoAdjustLayout 这条路就漏了:DPI 变了而控件尺寸没变
      (宽度固定的栏)时 NeedsRender 为假,运行时 Paint 会 blit 出旧密度的那一帧,
      而设计期不走缓存、看着一切正常(spec §3.5)。 }
    if FPaintCache <> nil then FPaintCache.Drop;
    inherited Invalidate;
  finally
    FRelayouting := False;
  end;
end;

procedure TTyCustomToolWindow.Invalidate;
var
  old, oldRule: Integer;
  hadOld: Boolean;
begin
  { 自己的样子变了 —— 丢缓存。子控件打脏到不了这里,缓存正是靠这一点活着。 }
  if FPaintCache <> nil then FPaintCache.Drop;
  { 换主题是这个类唯一听不见的事件:广播过来的只有一个裸 Invalidate
    (tyControls.Controller.pas 的 Changed)。所以缓存键在这里重查一遍,
    而键变了要重排、不是只重画。
    这里**不**手动作废缓存:主题版本号已经在键里,而 ResolveMetric 就按同一个
    FVersion 记忆化(StyleModel.pas:1158),(anchor, ver) 这一对是完备的 ——
    作废一下等于每次重画都必然重算,缓存加了等于没加。
    两边比的都是 **token 那一项**。拿它跟 HeaderHeightPx(= max(token, 操作区) 再钳到
    下限 1)比的话,token 为 0 时两者永远不相等,于是悬停、焦点、主题广播 —— 每一次
    重画都会整控件重排一遍;操作区一旦高过 token,同样如此。 }
  old := FHeaderPxCache;
  oldRule := FHeaderRuleCache;
  hadOld := FHeaderPxValid;
  if (not FRelayouting) and hadOld
     and ((HeaderTokenPx <> old) or (FHeaderRuleCache <> oldRule)) then
    RelayoutHeader
  else if BottomGeomDrifted then
    RelayoutHeader;
  inherited Invalidate;
end;

function TTyCustomToolWindow.BottomGeomDrifted: Boolean;
var
  b: TTyCustomToolWindowBar;
  g: TTyToolWindowHeaderGeom;
begin
  { 底栏的标题行几何不止看行高:按钮尺寸、标签区下限、分隔线粗细、标签宽都能在行高不变时
    把操作区挪走,而换主题只带来一次裸 Invalidate(spec §3.5 / §7.3)。只查当前页:别的页
    切过来时第 4 步本来就重排。 }
  Result := False;
  if FRelayouting or ([csLoading, csDestroying] * ComponentState <> []) then Exit;
  if (HeaderMode <> twhBottom) or not IsActive then Exit;
  b := Bar;
  if [csLoading, csDestroying] * b.ComponentState <> [] then Exit;
  g := HeaderGeomAt(Rect(0, 0, ClientWidth, ClientHeight), Font.PixelsPerInch);
  if TyToolWindowSameGeom(g, FAlignedGeom) then Exit;
  { 先记下这一份:对齐引擎没跑起来的时候(藏着、没有句柄)不至于每一次重画都再请一遍。
    RelayoutHeader 自己丢缓存,AlignControls 看见「没变」也没关系 —— 操作区的位置
    CustomAlignPosition 每次都现算。 }
  FAlignedGeom := g;
  Result := True;
end;

procedure TTyCustomToolWindow.AutoAdjustLayout(AMode: TLayoutAdjustmentPolicy;
  const AFromPPI, AToPPI, AOldFormWidth, ANewFormWidth: Integer);
begin
  inherited AutoAdjustLayout(AMode, AFromPPI, AToPPI, AOldFormWidth, ANewFormWidth);
  { 不用手动作废缓存:PPI 和 RTL 本来就是缓存键的一部分,键自己会答「变了」。
    这里要做的只是重排 —— 内缩量变了,alClient 子控件得重新摆。 }
  RelayoutHeader;
end;

procedure TTyCustomToolWindow.CMBiDiModeChanged(var Msg: TLMessage);
begin
  inherited;
  RelayoutHeader;
end;

procedure TTyCustomToolWindow.CMEnabledChanged(var Message: TLMessage);
var
  b: TTyCustomToolWindowBar;
  form: TCustomForm;
  focusIn: Boolean;
begin
  b := Bar;
  { 禁用含焦点的页:继承那一句里 LCL 把 ActiveControl 置 nil(RemoveFocus → DefocusControl,
    customform.inc:901-910),焦点掉到窗体本身、快捷键全部失灵 —— 跟收起那一路是同一个问题
    (spec §5.3)。所以「焦点原来在不在里面」要在继承之前记。设计期不管焦点。 }
  focusIn := (b <> nil) and not Enabled and not (csDesigning in ComponentState)
    and ([csLoading, csDestroying] * b.ComponentState = []) and b.FocusIsInside(Self);
  inherited;
  if (b <> nil) and not (csDestroying in b.ComponentState) then
    b.WindowEnabledChanged(Self);
  { 照收起那一路:交给 Tab 顺序里栏后面的那一个(SelectNext(栏),TTyToolWindowBar.SetCollapsed)。
    不看继承之后 ActiveControl 是不是 nil:Win32 上禁用含焦点的句柄,继承返回时 ActiveControl
    已经不是 nil、也不是栏后面那一个(test.toolwindow.focus 实测)—— 平台挑的去处不是 spec §5.3
    要的。 }
  if focusIn then
  begin
    form := GetParentForm(b);
    if form <> nil then form.SelectNext(b, True, True);
  end;
end;

procedure TTyCustomToolWindow.CMVisibleChanged(var Msg: TLMessage);
begin
  inherited;
  { spec §6.6 的事件表:设计期不发(设计器摆控件、点页签,切的都是 Visible),栏静默
    切换的那一批也不发。这两种都不是 csLoading 能挡的 —— 栏在 Loaded 里应用
    ActiveIndex、加载收尾时应用挂起的布局计划,发生时 csLoading 早已清掉。 }
  if (csDesigning in ComponentState) or (FSilentVisibility > 0) then Exit;
  if Visible then DoShow else DoHide;
end;

procedure TTyCustomToolWindow.BeginSilentVisibility;
begin
  Inc(FSilentVisibility);
end;

procedure TTyCustomToolWindow.EndSilentVisibility;
begin
  { 钳住 0:没配对的 End 把计数压到负数的话,后面每一个 Begin 都只是从负数往上爬,
    抑制口就再也关不上了 —— 而那时事件照发,没有一条断言会指向这里。 }
  if FSilentVisibility > 0 then Dec(FSilentVisibility);
end;

procedure TTyCustomToolWindow.DoShow;
begin
  if Assigned(FOnShow) then FOnShow(Self);
end;

procedure TTyCustomToolWindow.DoHide;
begin
  if Assigned(FOnHide) then FOnHide(Self);
end;

procedure TTyCustomToolWindow.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, hdrS, noteS: TTyStyleSet;
  R, hdr, note: TRect;
  g: TTyToolWindowHeaderGeom;
  fill: TTyFill;
  rule: Integer;
begin
  P := TTyPainter.Create;
  try
    { painter 的位图是 W×H 并 blit 到 ARect 左上,所以内部一切坐标都用 (0,0)-local。 }
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    { 两件不同的事,都要告诉:画笔镜像的是**对齐**(逻辑 -> 物理),
      排布镜像的是**矩形**。少给哪一个,标题行都会跟读写方向脱节。 }
    P.BeginPaint(ACanvas, ARect, APPI, IsRightToLeft);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    { 画的那一条和排布用的那一条都从 HeaderRowIn / HeaderGeomAt 来,各算一次的话
      传进来的 PPI 一旦不是 Font.PixelsPerInch,底色铺的高度和几何算的高度就会差开。 }
    hdr := HeaderRowIn(R, APPI);
    if (HeaderMode = twhSide) and (hdr.Bottom > hdr.Top) then
    begin
      hdrS := ActiveController.Model.ResolveStyle(TyToolWindowHeaderKey,
        TyStyleClassFor(Self, StyleClass), [tysNormal]);
      if tpBackground in hdrS.Present then
        P.FillBackground(hdr, hdrS.Background, 0);
      { 可选的底线(spec §12):靠正文那一侧一条,粗细与排布让出来的是同一个数。 }
      rule := HeaderRuleAt(APPI);
      if rule > hdr.Bottom - hdr.Top then rule := hdr.Bottom - hdr.Top;
      if rule > 0 then
      begin
        fill := Default(TTyFill);
        fill.Kind := tfkSolid;
        fill.Color := hdrS.BorderColor;
        P.FillBackground(Rect(hdr.Left, hdr.Bottom - rule, hdr.Right, hdr.Bottom), fill, 0);
      end;
      g := HeaderGeomAt(R, APPI);
      { 标题拿下整个剩余跨度,放不下由 DrawText 自己出省略号。 }
      if (Caption <> '') and (g.Caption.Right > g.Caption.Left) then
        P.DrawText(g.Caption, Caption, hdrS.FontName, ResolveFontSize(hdrS),
          hdrS.FontWeight, hdrS.TextColor, taLeftJustify, tlCenter, True);
    end
    { 底栏:标签行只由当前页代画(spec §7.1)。非当前页藏着(设计期也是 csNoDesignVisible),
      它画出来的那一帧没人看得见,画了反而跟当前页的悬停 / 按下对不上。 }
    else if (HeaderMode = twhBottom) and (hdr.Bottom > hdr.Top) and IsActive then
    begin
      g := HeaderGeomAt(R, APPI);
      Bar.PaintHeader(Self, P, hdr, g, APPI);
    end;
    { 设计期孤儿的提示(spec §3.2):顶上让出来的那一行,写法照栏画 rsTyToolWindowBarStray。 }
    note := OrphanNoteRectIn(R, APPI);
    if note.Bottom > note.Top then
    begin
      noteS := ActiveController.Model.ResolveStyle(TyToolWindowNoteKey,
        TyStyleClassFor(Self, StyleClass), [tysNormal]);
      InflateRect(note, -MulDiv(ActiveController.Metric(TyToolWindowHeaderPadVar,
        TyToolWindowHeaderPadDef), APPI, 96), 0);
      if note.Right > note.Left then
        P.DrawText(note, rsTyToolWindowOrphan, noteS.FontName, ResolveFontSize(noteS),
          noteS.FontWeight, noteS.TextColor, taLeftJustify, tlCenter, True);
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCustomToolWindow.Paint;
var
  w, h: Integer;
begin
  { 设计器重绘少、而且边重绘边流式化,所以只在运行时用缓存。 }
  if csDesigning in ComponentState then
  begin
    RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
    Exit;
  end;
  w := ClientWidth; h := ClientHeight;
  if (w <= 0) or (h <= 0) then Exit;
  if FPaintCache = nil then FPaintCache := TTyPaintCache.Create;
  if FPaintCache.NeedsRender(w, h) then
    RenderTo(FPaintCache.Canvas, Rect(0, 0, w, h), Font.PixelsPerInch);
  FPaintCache.Blit(Canvas);
end;

{ --- 底栏标签行的输入(spec §3.6 运行时、§7.4) ------------------------------------- }

function TTyCustomToolWindow.InTabRowRegion(X, Y: Integer): Boolean;
begin
  if HeaderMode <> twhBottom then Exit(False);
  Result := InTabRowRegionOf(HeaderGeomAt(Rect(0, 0, ClientWidth, ClientHeight),
    Font.PixelsPerInch), X, Y);
end;

function TTyCustomToolWindow.InTabRowRegionOf(const AGeom: TTyToolWindowHeaderGeom;
  X, Y: Integer): Boolean;
var
  pt: TPoint;
begin
  Result := False;
  if HeaderMode <> twhBottom then Exit;
  pt := Point(X, Y);
  if not PtInRect(HeaderRowRect, pt) then Exit;
  { 行从客户区原点开始,几何的行内坐标就是客户区坐标。 }
  Result := not PtInRect(AGeom.Actions, pt);
end;

procedure TTyCustomToolWindow.WndProc(var TheMessage: TLMessage);
begin
  if (TheMessage.Msg = LM_LBUTTONDOWN) or (TheMessage.Msg = LM_LBUTTONDBLCLK) then
  begin
    { LCL 的顺序:WndProc 里先 BeginAutoDrag(control.inc:2284),再 MouseDown;双击是先
      DoMouseDown(ssDouble) 再 DblClick(control.inc:2602-2604)。所以这一次按在哪要在这里记。 }
    FPressPos := Point(TLMMouse(TheMessage).XPos, TLMMouse(TheMessage).YPos);
    FPressPosValid := True;
    if InTabRowRegion(FPressPos.X, FPressPos.Y) then Include(FRowPresses, mbLeft)
    else Exclude(FRowPresses, mbLeft);
    try
      inherited WndProc(TheMessage);
    finally
      FPressPosValid := False;
    end;
  end
  else
    inherited WndProc(TheMessage);
end;

procedure TTyCustomToolWindow.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  b: TTyCustomToolWindowBar;
  idx: Integer;
  r: TRect;
begin
  { 每一次按下都重新决定这个键「这一次归谁」(程序里直接调的也一样,不只经 WndProc 的那一路)。 }
  if not InTabRowRegion(X, Y) then
  begin
    Exclude(FRowPresses, Button);
    inherited MouseDown(Button, Shift, X, Y);
    Exit;
  end;
  Include(FRowPresses, Button);
  { 区域内:不调继承 —— 用户的 OnMouseDown 不触发,也从不 SetFocus(窗口本来就 csNoFocus)。
    栏收不收这一下(禁用、不是当前页、右键……)由栏自己判,收了才记得住捕获者。 }
  b := Bar;
  if b.HeaderZoneAt(Self, X, Y, idx, r) = twzNone then Exit;   { 空白只吞 }
  b.HeaderMouseDown(Self, Button, Shift, X, Y);
end;

procedure TTyCustomToolWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  b: TTyCustomToolWindowBar;
  g: TTyToolWindowHeaderGeom;
  idx: Integer;
begin
  b := Bar;
  if (b <> nil) and (HeaderMode = twhBottom) then
  begin
    { 移动是高频事件:一次只排一份几何,区域判断、部件命中、栏那一侧的悬停 / 拖动都用它。 }
    g := HeaderGeomAt(Rect(0, 0, ClientWidth, ClientHeight), Font.PixelsPerInch);
    { 标签行上的手势捕获在本页:移动不论位置都转。 }
    if b.HeaderCapturedBy(Self) then
      b.HeaderMoveIn(Self, g, Shift, X, Y)
    else if InTabRowRegionOf(g, X, Y) and (TyToolWindowZoneAt(g, X, Y, idx) <> twzNone) then
      b.HeaderMoveIn(Self, g, Shift, X, Y)
    else
      { 区域里的空白、或者出了区域:清悬停(不算「转发 none」)。 }
      b.HeaderMouseLeave(Self);
  end;
  { spec 只要求吞 Down / Up / Click / DblClick / 右键 / 滚轮,移动照常给用户。 }
  inherited MouseMove(Shift, X, Y);
end;

procedure TTyCustomToolWindow.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  b: TTyCustomToolWindowBar;
begin
  { 这个键的按下落在哪决定这整次点击归谁 —— 按在正文、松开在标签行,照常给用户。 }
  if not (Button in FRowPresses) then
  begin
    inherited MouseUp(Button, Shift, X, Y);
    Exit;
  end;
  b := Bar;
  { 只有手势真的捕获在本页上才转:栏拒绝过的按下(禁用、那时不是当前页)、已经收尾的手势,
    松开都不许去碰引擎 —— 引擎那时可能正武装在别的页上。最后一句:点标签切页、点收起都会
    在这里把本窗口藏起来(spec §9.2)。 }
  if (Button = mbLeft) and (b <> nil) and b.HeaderCapturedBy(Self) then
    b.HeaderMouseUp(Self, Button, Shift, X, Y);
end;

procedure TTyCustomToolWindow.MouseLeave;
var
  b: TTyCustomToolWindowBar;
begin
  inherited MouseLeave;
  b := Bar;
  if b <> nil then b.HeaderMouseLeave(Self);
end;

procedure TTyCustomToolWindow.Click;
begin
  { LCL 在 MouseUp 之前调它(control.inc:2827-2846)。 }
  if mbLeft in FRowPresses then Exit;
  inherited Click;
end;

procedure TTyCustomToolWindow.DblClick;
begin
  if mbLeft in FRowPresses then Exit;
  inherited DblClick;
end;

function TTyCustomToolWindow.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  if InTabRowRegion(MousePos.X, MousePos.Y) then Exit(True);
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
end;

procedure TTyCustomToolWindow.DoContextPopup(MousePos: TPoint; var Handled: Boolean);
var
  b: TTyCustomToolWindowBar;
  idx: Integer;
  r: TRect;
begin
  if ((MousePos.X <> -1) or (MousePos.Y <> -1)) and InTabRowRegion(MousePos.X, MousePos.Y) then
  begin
    Handled := True;
    b := Bar;
    if b.HeaderZoneAt(Self, MousePos.X, MousePos.Y, idx, r) = twzTab then
      b.HeaderContextPopup(Self, MousePos.X, MousePos.Y);
    Exit;
  end;
  inherited DoContextPopup(MousePos, Handled);
end;

function TTyCustomToolWindow.PointerInClient(out APoint: TPoint): Boolean;
begin
  Result := HandleAllocated;
  if Result then APoint := ScreenToClient(Mouse.CursorPos)
  else APoint := Point(-1, -1);
end;

procedure TTyCustomToolWindow.BeginAutoDrag;
var
  p: TPoint;
begin
  if FPressPosValid then p := FPressPos
  else if not PointerInClient(p) then p := Point(-1, -1);
  if InTabRowRegion(p.X, p.Y) then Exit;
  StartLclAutoDrag;
end;

procedure TTyCustomToolWindow.StartLclAutoDrag;
begin
  inherited BeginAutoDrag;
end;

procedure TTyCustomToolWindow.CMHintShow(var Message: TLMessage);
var
  info: PHintInfo;
  txt: string;
  r: TRect;
  p: TPoint;
begin
  info := PHintInfo(Message.LParam);
  if (info = nil) or not InTabRowRegion(info^.CursorPos.X, info^.CursorPos.Y) then
  begin
    inherited;
    Exit;
  end;
  p := info^.CursorPos;
  if Bar.HeaderHint(Self, p.X, p.Y, txt, r) then
  begin
    info^.HintStr := txt;
    info^.CursorRect := r;          { 本窗口客户区坐标:挪出这个部件就重新问 }
    Message.Result := 0;            { 0 = 显示 }
  end
  else
  begin
    { 分隔线、空白:不显示,也不回落到窗口自己的提示。挪一下就重新问。 }
    info^.CursorRect := Rect(p.X, p.Y, p.X + 1, p.Y + 1);
    Message.Result := 1;
  end;
end;

procedure TTyCustomToolWindow.CMMaskHitTest(var Message: TCMHitTest);
var
  frm: TCustomForm;
  p: TPoint;
begin
  { 注意极性:0 = 「这一点在我身上」。 }
  Message.Result := 0;
  { 设计器发的是**设计器窗体**坐标;TControl 重载的 GetDesignerForm 沿 Parent 找。 }
  frm := GetDesignerForm(TControl(Self));
  if frm = nil then Exit;
  p := ScreenToClient(frm.ClientToScreen(Point(Message.XPos, Message.YPos)));
  Message.Result := DesignMaskAnswerAt(p.X, p.Y);
end;

function TTyCustomToolWindow.DesignMaskAnswerAt(X, Y: Integer): Integer;
begin
  { 注意极性:1 = 「跳过我」,0 = 「在我身上」(同 TyShapeMaskHitTestAnswer 的约定)。 }
  if InTabRowRegion(X, Y) then Result := 1 else Result := 0;
end;

procedure TTyCustomToolWindow.LMCancelMode(var Message: TLMessage);
var
  b: TTyCustomToolWindowBar;
begin
  inherited;
  { 捕获者是本页、手势进行中(spec §9.7);是不是由栏按引擎判。 }
  b := Bar;
  if b <> nil then b.HeaderCancelMode(Self);
end;

{ --- TTyCustomToolWindowActions ----------------------------------------------- }

constructor TTyCustomToolWindowActions.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { 两个 KeepChild 标志:用户在对象查看器里开 AutoSize,TWinControl.DoAutoSize 会把
    子控件往左上挪(wincontrol.inc:3441-3476),和这里自己的排列互相覆盖。 }
  ControlStyle := ControlStyle + [csAcceptsControls, csDesignFixedBounds, csNoFocus,
    csAutoSizeKeepChildLeft, csAutoSizeKeepChildTop];
  inherited SetAlign(alCustom);
  { 构造里一个子对象都不建 —— 建了会在流式加载时翻倍。 }
end;

function TTyCustomToolWindowActions.GetStyleTypeKey: string;
begin
  Result := TyToolWindowActionsKey;
end;

procedure TTyCustomToolWindowActions.SetAlign(Value: TAlign);
begin
  { 位置由所在窗口的 CustomAlignPosition 定,Align 不接受别的值。 }
  inherited SetAlign(alCustom);
end;

function TTyCustomToolWindowActions.ChildClassAllowed(ChildClass: TClass): Boolean;
begin
  { 用 InheritsFrom 不用 = :派生类同样不许进来。 }
  Result := inherited ChildClassAllowed(ChildClass)
    and not ChildClass.InheritsFrom(TTyCustomToolWindow)
    and not ChildClass.InheritsFrom(TTyCustomToolWindowBar)
    and not ChildClass.InheritsFrom(TTyCustomToolWindowActions);
end;

function TTyCustomToolWindowActions.IsBoundsStored: Boolean;
begin
  Result := not (Parent is TTyCustomToolWindow);
end;

function TTyCustomToolWindowActions.IsUsedByWindow: Boolean;
begin
  Result := (Parent is TTyCustomToolWindow) and (TTyCustomToolWindow(Parent).Actions = Self);
end;

function TTyCustomToolWindowActions.IsControlVisible: Boolean;
begin
  Result := inherited IsControlVisible;
  { 状态一翻(第一个被删掉、孤儿被放回窗口)不用谁来通知:RemoveControl / InsertControl
    都会走到整窗体的 DoAllAutoSize,它对整棵树重新问一遍这里(UpdateShowingRecursive)。 }
  if Result and not (csDesigning in ComponentState) and not IsUsedByWindow then
    Result := False;
end;

function TTyCustomToolWindowActions.HasVisibleChild: Boolean;
var
  i: Integer;
begin
  for i := 0 to ControlCount - 1 do
    if Controls[i].IsControlVisible then Exit(True);
  Result := False;
end;

function TTyCustomToolWindowActions.MetricPx(const AName: string; ADefault, APPI: Integer): Integer;
begin
  Result := MulDiv(ActiveController.Metric(AName, ADefault), APPI, 96);
  { 同 TyToolWindowHeaderLayout:度量值不钳(TyEvalLength),负的内距 / 间距按 0 算。 }
  if Result < 0 then Result := 0;
end;

function TTyCustomToolWindowActions.FlowInput(APPI: Integer;
  out AKids: TTyToolWindowKids): TTyToolWindowFlowItems;
var
  i, n, own: Integer;
  c: TControl;
begin
  { 子控件的尺寸是按本控件此刻的密度排的设备像素;问别的 PPI 时按比例换过去,
    这一条记录里才是一套尺度。 }
  own := Font.PixelsPerInch;
  if own <= 0 then own := 96;
  Result := nil;
  AKids := nil;
  SetLength(Result, ControlCount);
  SetLength(AKids, ControlCount);
  n := 0;
  for i := 0 to ControlCount - 1 do
  begin
    c := Controls[i];
    if not c.IsControlVisible then Continue;
    AKids[n] := c;
    Result[n].Width := MulDiv(c.Width, APPI, own);
    Result[n].Height := MulDiv(c.Height, APPI, own);
    Result[n].MinWidth := MulDiv(c.Constraints.MinWidth, APPI, own);
    Result[n].MinHeight := MulDiv(c.Constraints.MinHeight, APPI, own);
    Inc(n);
  end;
  SetLength(Result, n);
  SetLength(AKids, n);
end;

function TTyCustomToolWindowActions.RowSizeAt(APPI: Integer): TSize;
var
  kids: TTyToolWindowKids;
begin
  Result := TyToolWindowActionsFlow(FlowInput(APPI, kids), 0, 0,
    MetricPx(TyToolWindowHeaderPadVar, TyToolWindowHeaderPadDef, APPI),
    MetricPx(TyToolWindowHeaderGapVar, TyToolWindowHeaderGapDef, APPI), False).Size;
end;

function TTyCustomToolWindowActions.PreferredSizeAt(APPI: Integer): TSize;
var
  own, lo: Integer;
begin
  Result := RowSizeAt(APPI);
  { 一个可见子控件都没有:运行时就是 0 —— 非 raw 的 GetPreferredSize 会把 0 宽换成 75px
    默认宽(control.inc:5609-5643),空操作区会平白占掉一截标题。
    设计期给一个方槽方便往里拖控件,边长取 token 本身 —— 取标题行高的话,标题行高
    本来就是 max(token, 操作区),定义会绕回自己。 }
  if (csDesigning in ComponentState) and not HasVisibleChild then
  begin
    Result.cx := MetricPx(TyToolWindowHeaderHeightVar, TyToolWindowHeaderHeightDef, APPI);
    Result.cy := Result.cx;
  end;
  { 自己的 Constraints 是 published 的,可 LCL 在 CustomAlignPosition 之后才施加
    (wincontrol.inc:3081-3082):标题行按没抬过的宽留位,施加之后它就伸出行外、压住标题。
    所以首选尺寸自己先抬到下限 —— 标题行、正文顶都按抬过的算。 }
  own := Font.PixelsPerInch;
  if own <= 0 then own := 96;
  lo := MulDiv(Constraints.MinWidth, APPI, own);
  if lo > Result.cx then Result.cx := lo;
  lo := MulDiv(Constraints.MinHeight, APPI, own);
  if lo > Result.cy then Result.cy := lo;
end;

procedure TTyCustomToolWindowActions.AdjustSize;
var
  sz: TSize;
  win: TTyCustomToolWindow;
begin
  inherited AdjustSize;
  { 子控件只改 Constraints 时 LCL 不作废本控件的首选尺寸缓存(control.inc:1520-1522 只调
    AdjustSize),GetPreferredSize 会端旧值。 }
  InvalidatePreferredSize;
  { 比的是窗口真正拿去用的那个量(TTyToolWindow.ActionsPreferredSize):整个操作区藏起来,
    子控件的尺寸一个没变,那一项照样从它的高变成 0。 }
  if IsControlVisible then sz := PreferredSizeAt(Font.PixelsPerInch)
  else sz := Default(TSize);
  { 没挂在窗口里时不记:先建好、带着子控件再挂进窗口的,挂进去那一次才是「变了」。 }
  if not (Parent is TTyCustomToolWindow) then Exit;
  if (sz.cx = FLastPreferred.cx) and (sz.cy = FLastPreferred.cy) then Exit;
  FLastPreferred := sz;
  win := TTyCustomToolWindow(Parent);
  if win.Bar <> nil then win.Bar.ActionsSizeChanged;
end;

procedure TTyCustomToolWindowActions.CalculatePreferredSize(var PreferredWidth,
  PreferredHeight: Integer; WithThemeSpace: Boolean);
var
  sz: TSize;
begin
  { LCL 的 GetPreferredSize(raw) 答的也是这一处,不另算一遍。 }
  sz := PreferredSizeAt(Font.PixelsPerInch);
  PreferredWidth := sz.cx;
  PreferredHeight := sz.cy;
end;

function TTyCustomToolWindowActions.NoteText: string;
begin
  if Parent is TTyCustomToolWindow then Result := rsTyToolWindowActionsExtra
  else Result := rsTyToolWindowActionsOrphan;
end;

function TTyCustomToolWindowActions.NoteStyle: TTyStyleSet;
begin
  Result := ActiveController.Model.ResolveStyle(TyToolWindowNoteKey,
    TyStyleClassFor(Self, StyleClass), [tysNormal]);
end;

function TTyCustomToolWindowActions.NoteLeadAt(APPI: Integer): Integer;
begin
  { 粘贴一个现成的操作区,进来的就是带按钮的多余操作区(spec §4 点名的场景)。子控件照常
    从前导边排,提示排在那一排后面 —— 从 pad 开始画的话前半截压在按钮底下。 }
  if HasVisibleChild then
    Result := RowSizeAt(APPI).cx + MetricPx(TyToolWindowHeaderGapVar, TyToolWindowHeaderGapDef, APPI)
  else
    Result := MetricPx(TyToolWindowHeaderPadVar, TyToolWindowHeaderPadDef, APPI);
end;

function TTyCustomToolWindowActions.NoteRectIn(const AClient: TRect; APPI: Integer): TRect;
var
  lead, pad: Integer;
begin
  Result := Rect(0, 0, 0, 0);
  if not (csDesigning in ComponentState) or IsUsedByWindow then Exit;
  lead := NoteLeadAt(APPI);
  pad := MetricPx(TyToolWindowHeaderPadVar, TyToolWindowHeaderPadDef, APPI);
  { [子控件那一排][gap][提示][pad];从右往左读时整体按宽镜像,跟子控件那一排的镜像
    (AlignControls)是同一条规则 —— 子控件到右边,提示在它们左边。 }
  if IsRightToLeft then
    Result := Rect(AClient.Left + pad, AClient.Top, AClient.Right - lead, AClient.Bottom)
  else
    Result := Rect(AClient.Left + lead, AClient.Top, AClient.Right - pad, AClient.Bottom);
  if Result.Right < Result.Left then Result.Right := Result.Left;
end;

function TTyCustomToolWindowActions.NoteRect: TRect;
begin
  { Paint 按 ClientRect、Font.PixelsPerInch 画(见 Paint → RenderTo),这里问的是同一个框。 }
  Result := NoteRectIn(Rect(0, 0, ClientWidth, ClientHeight), Font.PixelsPerInch);
end;

function TTyCustomToolWindowActions.StrayDesignSize(APPI: Integer): TSize;
var
  st: TTyStyleSet;
  blockW, blockH, textW, fontSize: Integer;
begin
  st := NoteStyle;
  fontSize := ResolveFontSize(st);
  { 两个量法取大的(Painter.pas 的约定):画布量的和渲染器量的差一个像素,只按前者
    给尺寸,DrawText 就会觉得放不下、出省略号。 }
  TyMeasureTextBlock(NoteText, st.FontName, fontSize, st.FontWeight, APPI, 0, 0, blockW, blockH);
  textW := TyMeasureRenderedTextWidth(NoteText, st.FontName, fontSize, st.FontWeight, APPI);
  if blockW > textW then textW := blockW;
  { 宽 = 提示前导距 + 提示宽 + pad:有子控件时是 raw 宽 + gap + 提示宽 + pad,
    没有时退化成 pad + 提示宽 + pad。跟 NoteRectIn 画提示用的是同一个前导距。 }
  Result.cx := NoteLeadAt(APPI) + textW
    + MetricPx(TyToolWindowHeaderPadVar, TyToolWindowHeaderPadDef, APPI);
  Result.cy := PreferredSizeAt(APPI).cy;
  blockH := MetricPx(TyToolWindowHeaderHeightVar, TyToolWindowHeaderHeightDef, APPI);
  if blockH > Result.cy then Result.cy := blockH;
end;

procedure TTyCustomToolWindowActions.ConstrainedResize(var MinWidth, MinHeight, MaxWidth,
  MaxHeight: TConstraintSize);
var
  sz: TSize;
begin
  inherited ConstrainedResize(MinWidth, MinHeight, MaxWidth, MaxHeight);
  { 设计期、窗口不认的那一个(多出来的、孤儿)才有下限:raw 尺寸下它是 26×26 的方槽,
    有子控件时子控件盖住提示,撤销删除后回来的孤儿是 LCL 默认的 75×50 —— 提示都只剩
    一个省略号。一处下限同时管住两条路:多出来的由窗口按 raw 摆(CustomAlignPosition),
    孤儿的尺寸是流里读出来 / 设计器给的,两边的 SetBounds 都经过这里
    (TControl.DoConstrainedResize)。运行时它们不露面,这里不碰。 }
  if not (csDesigning in ComponentState) or IsUsedByWindow then Exit;
  sz := StrayDesignSize(Font.PixelsPerInch);
  if sz.cx > MinWidth then MinWidth := sz.cx;
  if sz.cy > MinHeight then MinHeight := sz.cy;
end;

procedure TTyCustomToolWindowActions.AlignControls(AControl: TControl; var RemainingClientRect: TRect);
var
  kids: TTyToolWindowKids;
  items: TTyToolWindowFlowItems;
  fl: TTyToolWindowFlow;
  cr, r: TRect;
  sz: TSize;
  i: Integer;
begin
  { 不调继承:子控件的 Align / Anchors 在这里一律不算,由这一排说了算。
    给子控件 SetBounds 会绕回这里,所以带保护。 }
  if FInLayout then Exit;
  FInLayout := True;
  try
    { LCL 的 AlignControls 第一步就是这一句(wincontrol.inc:3259),传进来的是没扣过的客户区。 }
    cr := RemainingClientRect;
    AdjustClientRect(cr);
    items := FlowInput(Font.PixelsPerInch, kids);
    if Length(kids) > 0 then
    begin
      { 排法全在 TyToolWindowActionsFlow:从前导边排、放不下贴尾端(被裁的是开头的,
        尾端那几个最常用,spec §4)、RTL 整排镜像;量那一排的 RowSizeAt 问的也是它。 }
      fl := TyToolWindowActionsFlow(items, cr.Right - cr.Left, cr.Bottom - cr.Top,
        MetricPx(TyToolWindowHeaderPadVar, TyToolWindowHeaderPadDef, Font.PixelsPerInch),
        MetricPx(TyToolWindowHeaderGapVar, TyToolWindowHeaderGapDef, Font.PixelsPerInch),
        IsRightToLeft);
      for i := 0 to High(kids) do
      begin
        r := fl.Rects[i];
        kids[i].SetBounds(cr.Left + r.Left, cr.Top + r.Top, r.Right - r.Left, r.Bottom - r.Top);
      end;
    end;
  finally
    FInLayout := False;
  end;
  { 设计期往孤儿里拖控件:没人摆孤儿,ConstrainedResize 只在它自己的边界被设时才跑,
    于是下限停在拖进来之前、提示停在省略号。排完子控件顺手再施加一次。
    先例是 TTyToolBar 在 AlignControls 末尾设自己的 Height(ToolBar.pas:1905);这里放在
    保护**之外**,尺寸一变 LCL 为新的客户区再请一遍这里时能真的按新宽重排,而那一遍
    宽已够、不会再设,所以不循环。 }
  if (csDesigning in ComponentState) and not IsUsedByWindow then
  begin
    sz := StrayDesignSize(Font.PixelsPerInch);
    { 把撑好的尺寸直接给出去:SetBounds(Left, Top, Width, Height) 是空操作 ——
      TWinControl.SetBounds 见边界没变就直接返回(wincontrol.inc:8163 的 SameRect),
      根本走不到施加下限的 DoConstrainedResize。 }
    if (Width < sz.cx) or (Height < sz.cy) then
    begin
      if sz.cx < Width then sz.cx := Width;
      if sz.cy < Height then sz.cy := Height;
      SetBounds(Left, Top, sz.cx, sz.cy);
    end;
  end;
end;

procedure TTyCustomToolWindowActions.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, extraS: TTyStyleSet;
  R, noteR: TRect;
begin
  P := TTyPainter.Create;
  try
    { painter 的位图是 W×H 并 blit 到 ARect 左上,所以内部一切坐标都用 (0,0)-local。 }
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI, IsRightToLeft);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    if csDesigning in ComponentState then
    begin
      { 设计期空着:描出那个方槽,看得见才知道往哪里拖。 }
      if not HasVisibleChild then
      begin
        extraS := ActiveController.Model.ResolveOverride('border-color: var(--border);');
        if tpBorderColor in extraS.Present then
          P.StrokeBorder(R, 0, 1, extraS.BorderColor);
      end;
      { 窗口不认的那一个(多出来的、孤儿):一眼看得懂的提醒。框从 NoteRectIn 来 ——
        StrayDesignSize 按它量、NoteRect 按它答,量的、画的、测的是同一个框。 }
      noteR := NoteRectIn(R, APPI);
      if noteR.Right > noteR.Left then
      begin
        extraS := NoteStyle;
        P.DrawText(noteR, NoteText, extraS.FontName, ResolveFontSize(extraS),
          extraS.FontWeight, extraS.TextColor, taLeftJustify, tlCenter, True);
      end;
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCustomToolWindowActions.Paint;
begin
  { 不做绘制缓存:它小,而且子控件就铺在它上面,几乎没有只露它自己的那种重画。 }
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

{ --- TTyCustomToolWindowBar ---------------------------------------------------- }

type
  { AdjustClientRect 是 protected:收窄要的是父控件「调整后」的客户区。 }
  TWinControlAccess = class(TWinControl);

constructor TTyCustomToolWindowBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { 第一句:下面的 DeriveSize 会走到 SizesAsCollapsed(读吸附标志)。 }
  FGesture := TTyToolWindowGesture.Create(Self);
  ControlStyle := ControlStyle + [csAcceptsControls, csTripleClicks, csQuadClicks];
  FPlacement := twpLeft;
  FExpandedSize := TyToolWindowDefaultExpandedSize;
  FHideWhenEmpty := True;
  FLoadingActiveIndex := -1;
  FBottomActionsPx := -1;
  FHeaderHoverIndex := -1;
  FStripHover := -1;
  FStripPressed := -1;
  FDropSlot := -1;
  FImageLink := TChangeLink.Create;
  FImageLink.OnChange := @ImageListChange;
  Align := alLeft;
  { 默认值的属性不会进 .lfm,setter 也就不会跑 —— 出生时就得有一个推导过的尺寸。
    csDesigning 此刻已经在了(TComponent.Create 里的 InsertComponent),所以设计器里
    放下的空栏按展开算。 }
  DeriveSize;
end;

destructor TTyCustomToolWindowBar.Destroy;
begin
  { 直接 Free(不经 Owner 的 DestroyComponents)时 csDestroying 要到继承析构里才置上;
    先置上,下面的手势收尾就只清标志,不在拆到一半的栏上重排、重画。幂等。 }
  Destroying;
  { TChangeLink.Destroy 自己从 Sender(就是 FSubscribedList)注销。先放它:之后的继承析构
    里再有通知进来,SyncImageSubscription 看见 link 没了就不碰任何列表。 }
  FreeAndNil(FImageLink);
  FSubscribedList := nil;
  FreeAndNil(FOverflowMenu);
  { 兄弟身上挂着的处理器指向本栏,先摘。 }
  UnwatchAll;
  { 拖动 / 拉宽中被释放:临时光标弹掉、计时器放掉、拉宽标志清掉。拉宽 / 拖动期间装在
    Application 和 Screen 上的处理器,一个不留。 }
  ResetGesture(twgeDiscard);
  { 放置预览(Owner = nil,由本栏持有;它的 Parent 是别的控件):先摘 Parent 再释放。 }
  if FDropPreview <> nil then
  begin
    FDropPreview.Parent := nil;
    FreeAndNil(FDropPreview);
  end;
  { 排队的移动归 manager(队列里是 manager 的方法,RemoveAsyncCalls 按方法所属对象匹配,
    这里撤不到):以本栏为目标的项由 manager 在 opRemove 里删。 }
  if Application <> nil then
    Application.RemoveAllHandlersOfObject(Self);
  if Screen <> nil then Screen.RemoveAllHandlersOfObject(Self);
  inherited Destroy;
  { 最后一句:继承析构里注销窗口还会经 UnregisterWindow 走到 ResetGesture。引擎挂在
    Application / Screen 上的处理器由它自己的析构摘(上面那两句摘的是栏自己的)。 }
  FreeAndNil(FGesture);
end;

function TTyCustomToolWindowBar.GetStyleTypeKey: string;
begin
  Result := TyToolWindowBarKey;
end;

function TTyCustomToolWindowBar.EffectiveImages: TCustomImageList;
begin
  Result := FImages;
  if (Result = nil) and (FManager <> nil)
     and not (csDestroying in FManager.ComponentState) then
    Result := FManager.Images;
  if (Result <> nil) and (csDestroying in Result.ComponentState) then Result := nil;
end;

procedure TTyCustomToolWindowBar.UnsubscribeImages;
var
  old: TCustomImageList;
begin
  old := FSubscribedList;
  if old = nil then Exit;
  FSubscribedList := nil;
  { 被移除的正是它时**照样注销**(spec §8 原写「跳过」):opRemove 从列表的继承析构里
    发出,那时它的 link 表还在(imglist.inc:1692-1698 —— 表在 inherited Destroy 之后才清、
    才释放),注销是安全的;而跳过的话 link 还挂在它身上,紧接着注册到别的列表上,
    就是那个死循环。 }
  if FImageLink <> nil then
    old.UnRegisterChanges(FImageLink);
  if (old <> FImages) and not (csDestroying in old.ComponentState) then
    old.RemoveFreeNotification(Self);
end;

procedure TTyCustomToolWindowBar.SyncImageSubscription;
var
  target: TCustomImageList;
begin
  if FImageLink = nil then Exit;
  target := EffectiveImages;
  if target = FSubscribedList then Exit;
  { 先注销旧的,再订新的(见声明处)。 }
  UnsubscribeImages;
  FSubscribedList := target;
  if target <> nil then
  begin
    target.RegisterChanges(FImageLink);
    target.FreeNotification(Self);
  end;
end;

procedure TTyCustomToolWindowBar.ResolvePendingImageIndexes;
var
  i: Integer;
begin
  if [csLoading, csDestroying] * ComponentState <> [] then Exit;
  for i := 0 to High(FRegistered) do
    FRegistered[i].ResolveImageIndex;
end;

procedure TTyCustomToolWindowBar.ImagesChanged;
begin
  SyncImageSubscription;
  ResolvePendingImageIndexes;
  if not (csDestroying in ComponentState) then Invalidate;
end;

procedure TTyCustomToolWindowBar.ImageListChange(Sender: TObject);
begin
  { 只重画,不解析挂起的序号:挂起只在「栏没有列表」或「栏在加载中」时才有 —— 前者这里
    订阅着列表就不成立,后者 ResolvePendingImageIndexes 本来就不做。越界的序号也不是挂起的:
    它解析过了(名字是 '',序号就是键),列表后来长出那一格,画的就是那一格。 }
  if not (csDestroying in ComponentState) then Invalidate;
end;

procedure TTyCustomToolWindowBar.SetImages(AValue: TCustomImageList);
begin
  if FImages = AValue then Exit;
  FImages := AValue;
  { 流式加载时照样订阅(只是挂一个 link);解析留给 Loaded。旧列表的注销和
    FreeNotification 都在 SyncImageSubscription 里。 }
  ImagesChanged;
end;

function TTyCustomToolWindowBar.ResolvedImageIndex(AWindow: TTyCustomToolWindow): Integer;
begin
  if AWindow = nil then Exit(-1);
  if AWindow.ImageName <> '' then
    Result := TyImageIndexOfName(EffectiveImages, AWindow.ImageName)
  else
    Result := AWindow.FImageIndex;
end;

function TTyCustomToolWindowBar.StripHintText(AWindow: TTyCustomToolWindow): string;
begin
  if AWindow = nil then Exit('');
  if AWindow.StripHint <> '' then Result := AWindow.StripHint
  else Result := AWindow.Caption;
end;

function TTyCustomToolWindowBar.ChildClassAllowed(ChildClass: TClass): Boolean;
begin
  Result := inherited ChildClassAllowed(ChildClass)
    and ChildClass.InheritsFrom(TTyCustomToolWindow);
end;

function TTyCustomToolWindowBar.PPI: Integer;
begin
  Result := Font.PixelsPerInch;
  if Result <= 0 then Result := 96;
end;

function TTyCustomToolWindowBar.MetricsAt(APPI: Integer): TTyToolWindowBarMetrics;
var
  S: TTyStyleSet;
begin
  if FPlacement = twpBottom then Result.Strip := 0
  else Result.Strip := TokenPxAt(TyToolWindowStripSizeVar, TyToolWindowStripSizeDef, APPI);
  Result.Edge := TokenPxAt(TyToolWindowEdgeSizeVar, TyToolWindowEdgeSizeDef, APPI);
  Result.ContentMin := TokenPxAt(TyToolWindowContentMinVar, TyToolWindowContentMinDef, APPI);
  Result.NoteRow := TokenPxAt(TyToolWindowHeaderHeightVar, TyToolWindowHeaderHeightDef, APPI);
  { **静止态**样式:TyChromeInsetLogical 按状态解析后的样式量(焦点环比边框宽),拿
    CurrentStyle 的话悬停一下内缩量就变 —— 而悬停只 Invalidate、不 Realign,窗口会
    停在旧的客户区里。本控件的 StyleOverride 照样叠上(spec §6.1)。 }
  S := ActiveController.Model.ResolveStyle(GetStyleTypeKey, TyStyleClassFor(Self, StyleClass),
    [tysNormal]);
  if StyleOverride <> '' then
    TyMergeStyleSet(S, ActiveController.Model.ResolveOverride(StyleOverride));
  Result.Chrome := MulDiv(TyChromeInsetLogical(S), APPI, 96);
end;

function TTyCustomToolWindowBar.Metrics: TTyToolWindowBarMetrics;
var
  mdl: TTyStyleModel;
  ver: Cardinal;
  cls: string;
begin
  mdl := ActiveController.Model;
  ver := mdl.ThemeVersion;
  cls := TyStyleClassFor(Self, StyleClass);
  { 键里除了 spec §6.1 列的几项,还有样式类和本控件的 StyleOverride:chrome 按它们解析,
    而改这两个只会带来一次裸 Invalidate,键不变的话缓存就一直端旧值。 }
  if (not FMetricsValid) or (FMetricsAnchor <> TObject(mdl)) or (FMetricsVer <> ver)
     or (FMetricsPPI <> PPI)
     or (FMetricsPlacement <> FPlacement) or (FMetricsClass <> cls)
     or (FMetricsOverride <> StyleOverride) then
  begin
    FMetrics := MetricsAt(PPI);
    FMetricsAnchor := TObject(mdl);
    FMetricsVer := ver;
    FMetricsPPI := PPI;
    FMetricsPlacement := FPlacement;
    FMetricsClass := cls;
    FMetricsOverride := StyleOverride;
    FMetricsValid := True;
  end;
  Result := FMetrics;
end;

function TTyCustomToolWindowBar.ChromeInsetPx: Integer;
begin
  Result := Metrics.Chrome;
end;

function TTyCustomToolWindowBar.StripSizePx: Integer;
begin
  Result := Metrics.Strip;
end;

function TTyCustomToolWindowBar.EdgeSizePx: Integer;
begin
  Result := Metrics.Edge;
end;

function TTyCustomToolWindowBar.ContentMinPx: Integer;
begin
  Result := Metrics.ContentMin;
end;

function TTyCustomToolWindowBar.CollapsedAtRunTime: Boolean;
begin
  Result := FCollapsed and not (csDesigning in ComponentState);
end;

function TTyCustomToolWindowBar.SizesAsCollapsed: Boolean;
begin
  { 设计期不算收起,没有窗口也按展开算 —— 零宽 / 零高的栏在设计器里点不中(spec §5.4)。
    算放置预览的宽时(FAssumeShown,只在 ShownAxisPx 里)按「有一个窗口、展开着」答。 }
  Result := not FAssumeShown and not (csDesigning in ComponentState)
    and (FCollapsed or (WindowCount = 0) or EdgeSnapped);
end;

function TTyCustomToolWindowBar.HiddenAsEmpty: Boolean;
begin
  { FAssumeShown:算放置预览的宽时按「有一个窗口」答(只在 ShownAxisPx 里置位)。 }
  Result := FHideWhenEmpty and (FPlacement <> twpBottom) and not FAssumeShown
    and not (csDesigning in ComponentState) and (WindowCount = 0);
end;

function TTyCustomToolWindowBar.FixedAxisPx(const AM: TTyToolWindowBarMetrics): Integer;
begin
  if FPlacement = twpBottom then
  begin
    if SizesAsCollapsed then Result := 0
    else Result := 2 * AM.Chrome + AM.Edge;
  end
  else
  begin
    { 一侧没有窗口、整条隐藏(spec §6.9):连图标条和 chrome 都不算。内容项本来就是 0
      (SizesAsCollapsed),所以推导宽 0;参加 §6.2 分空间时固定部分也是 0。 }
    if HiddenAsEmpty then Exit(0);
    Result := AM.Strip + 2 * AM.Chrome;
    if not SizesAsCollapsed then Inc(Result, AM.Edge);
  end;
end;

function TTyCustomToolWindowBar.UnnarrowedContentPx(const AM: TTyToolWindowBarMetrics): Integer;
begin
  if SizesAsCollapsed then Exit(0);
  Result := MulDiv(FExpandedSize, PPI, 96);
  if Result < AM.ContentMin then Result := AM.ContentMin;
end;

function TTyCustomToolWindowBar.JoinsNarrowing: Boolean;
begin
  { 只有按 Placement 对齐的、看得见的栏参与分空间:改成 alClient 之类的栏,宽高由父控件定。 }
  Result := IsControlVisible and (Align = PlacementAlign);
end;

function TTyCustomToolWindowBar.NarrowedContentPx(const AM: TTyToolWindowBarMetrics): Integer;
var
  p: TWinControl;
  r: TRect;
  c: TControl;
  b: TTyCustomToolWindowBar;
  m: TTyToolWindowBarMetrics;
  side: Boolean;
  avail, demand, sumDemand, sumW, n, i, v: Integer;
begin
  Result := UnnarrowedContentPx(AM);
  if Result <= 0 then Exit;
  p := Parent;
  if (p = nil) or not JoinsNarrowing then Exit;
  { 父控件调整后的客户区,沿栏的轴向(spec §6.2)。 }
  r := p.ClientRect;
  TWinControlAccess(p).AdjustClientRect(r);
  side := FPlacement <> twpBottom;
  if side then avail := r.Right - r.Left else avail := r.Bottom - r.Top;
  sumDemand := 0;
  sumW := 0;
  n := 0;
  for i := 0 to p.ControlCount - 1 do
  begin
    c := p.Controls[i];
    if not c.IsControlVisible then Continue;
    if (c is TTyCustomToolWindowBar) and TTyCustomToolWindowBar(c).JoinsNarrowing
       and ((TTyCustomToolWindowBar(c).FPlacement <> twpBottom) = side) then
    begin
      { 同轴的栏:扣掉固定部分,内容按各自**未收窄**的值算,不读对方此刻的宽 ——
        读的话结果跟对齐顺序有关,先排的那一条总是赢。 }
      b := TTyCustomToolWindowBar(c);
      if b = Self then m := AM else m := b.Metrics;
      Dec(avail, b.FixedAxisPx(m));
      demand := b.UnnarrowedContentPx(m);
      if demand > 0 then
      begin
        Inc(sumDemand, demand);
        Inc(sumW, b.FExpandedSize);
        Inc(n);
      end;
    end
    else if side and (c.Align in [alLeft, alRight]) then
      Dec(avail, c.Width)
    else if (not side) and (c.Align in [alTop, alBottom]) then
      Dec(avail, c.Height);
    { alClient(编辑区)不算:它可以被压到 0。 }
  end;
  if sumDemand <= avail then Exit;           { 放得下就各用各的 }
  if avail < 0 then avail := 0;
  { 放不下:按 ExpandedSize 比例分,不超过自己要的,不低于 content-min。 }
  if sumW > 0 then v := MulDiv(avail, FExpandedSize, sumW)
  else v := avail div n;
  if v < Result then Result := v;
  if Result < AM.ContentMin then Result := AM.ContentMin;
end;

function TTyCustomToolWindowBar.DerivedAxisPx(const AM: TTyToolWindowBarMetrics): Integer;
begin
  { 最大化只改内容项;按收起算尺寸时照旧(那时内容项是 0)。 }
  if (FPlacement = twpBottom) and FMaximized and not SizesAsCollapsed then
    Result := FixedAxisPx(AM) + MaximizedContentPx(AM)
  else
    Result := FixedAxisPx(AM) + NarrowedContentPx(AM);
end;

function TTyCustomToolWindowBar.MaximizedContentPx(const AM: TTyToolWindowBarMetrics): Integer;
var
  p: TWinControl;
  r: TRect;
  c: TControl;
  b: TTyCustomToolWindowBar;
  m: TTyToolWindowBarMetrics;
  i: Integer;
begin
  p := Parent;
  if (p = nil) or not JoinsNarrowing then Exit(UnnarrowedContentPx(AM));
  r := p.ClientRect;
  TWinControlAccess(p).AdjustClientRect(r);
  Result := r.Bottom - r.Top;
  for i := 0 to p.ControlCount - 1 do
  begin
    c := p.Controls[i];
    if not c.IsControlVisible then Continue;
    if (c is TTyCustomToolWindowBar) and TTyCustomToolWindowBar(c).JoinsNarrowing
       and (TTyCustomToolWindowBar(c).FPlacement = twpBottom) then
    begin
      b := TTyCustomToolWindowBar(c);
      if b = Self then m := AM else m := b.Metrics;
      Dec(Result, b.FixedAxisPx(m));
      if b <> Self then Dec(Result, b.UnnarrowedContentPx(m));
    end
    else if c.Align in [alTop, alBottom] then
      Dec(Result, c.Height);
    { alClient(编辑区)不算:最大化就是把它压到 0。 }
  end;
  if Result < AM.ContentMin then Result := AM.ContentMin;
end;

procedure TTyCustomToolWindowBar.SetMaximized(AValue: Boolean);
begin
  if FMaximized = AValue then Exit;
  if AValue and ((FPlacement <> twpBottom)
     or ([csDesigning, csLoading, csDestroying] * ComponentState <> [])
     or FCollapsed or (WindowCount = 0)) then Exit;
  ResetGesture(twgeCancel);
  FMaximized := AValue;
  if csDestroying in ComponentState then Exit;
  Relayout;
  { 标签行上最大化按钮的字形换了(tgMaximize ↔ tgRestore)。标题行几何不变,不用重排。 }
  InvalidateHeader;
end;

procedure TTyCustomToolWindowBar.ParentResized(Sender: TObject);
begin
  if [csLoading, csDestroying] * ComponentState = [] then DeriveSize;
end;

procedure TTyCustomToolWindowBar.WatchSiblings;
var
  p: TWinControl;
  c: TControl;
  i, k: Integer;
  known: Boolean;
begin
  p := Parent;
  { 已经离开父控件的(挪到别处、父控件换了)先摘掉。 }
  for i := High(FWatched) downto 0 do
    if (p = nil) or (FWatched[i].Parent <> p) then UnwatchAt(i);
  if (p = nil) or (csDestroying in ComponentState) or (csDestroying in p.ComponentState) then Exit;
  for i := 0 to p.ControlCount - 1 do
  begin
    c := p.Controls[i];
    { 栏之间已经互相通知(DeriveSiblings、CMVisibleChanged),不再挂。放置预览(spec §6.2 E 期补)
      alNone、不影响分空间,挂上只会让每次显示 / 隐藏多一轮推导。 }
    if (c = Self) or (c is TTyCustomToolWindowBar) or (c is TTyToolWindowDropPreview)
       or (csDestroying in c.ComponentState) then Continue;
    known := False;
    for k := 0 to High(FWatched) do
      if FWatched[k] = c then
      begin
        known := True;
        Break;
      end;
    if known then Continue;
    c.AddHandlerOnVisibleChanged(@SiblingChanged);
    c.AddHandlerOnChangeBounds(@SiblingChanged);
    c.FreeNotification(Self);
    SetLength(FWatched, Length(FWatched) + 1);
    FWatched[High(FWatched)] := c;
  end;
end;

procedure TTyCustomToolWindowBar.UnwatchAt(AIndex: Integer);
var
  c: TControl;
begin
  c := FWatched[AIndex];
  Delete(FWatched, AIndex, 1);
  { 下面要撤掉互相的 FreeNotification,FZeroInner 靠的也是它:一起放掉(它离开了父控件或正在
    释放,本来也不再是排序的对手)。 }
  if c = FZeroInner then FZeroInner := nil;
  { 正在释放的那个:它的处理器表跟着它走,互相的 FreeNotification 由它的析构清。 }
  if csDestroying in c.ComponentState then Exit;
  c.RemoveHandlerOnVisibleChanged(@SiblingChanged);
  c.RemoveHandlerOnChangeBounds(@SiblingChanged);
  c.RemoveFreeNotification(Self);
end;

procedure TTyCustomToolWindowBar.UnwatchAll;
var
  i: Integer;
begin
  for i := High(FWatched) downto 0 do
    UnwatchAt(i);
end;

procedure TTyCustomToolWindowBar.SiblingChanged(Sender: TObject);
begin
  { 自己推导时改了尺寸,对齐引擎接着挪兄弟,那一圈回到这里 —— FDeriving 挡住。已经不在
    同一父控件里的(还没来得及摘)不算。 }
  if FDeriving or ([csLoading, csDestroying] * ComponentState <> []) then Exit;
  if not (Sender is TControl) or (TControl(Sender).Parent <> Parent) then Exit;
  DeriveSize;
end;

procedure TTyCustomToolWindowBar.DeriveSiblings(AParent: TWinControl);
var
  i: Integer;
begin
  if AParent = nil then Exit;
  for i := 0 to AParent.ControlCount - 1 do
    if (AParent.Controls[i] is TTyCustomToolWindowBar) and (AParent.Controls[i] <> Self) then
      TTyCustomToolWindowBar(AParent.Controls[i]).DeriveSize;
end;

procedure TTyCustomToolWindowBar.SetParent(NewParent: TWinControl);
var
  old: TWinControl;
begin
  old := Parent;
  { 换父控件之前先还原(spec §6.4):最大化的高是按旧父控件算的。 }
  if old <> NewParent then Maximized := False;
  if (old <> nil) and (old <> NewParent) then old.RemoveHandlerOnResize(@ParentResized);
  inherited SetParent(NewParent);
  if old = NewParent then Exit;
  if (NewParent <> nil) and not (csDestroying in ComponentState) then
    NewParent.AddHandlerOnResize(@ParentResized);
  { 兄弟的处理器不在这里挪:下面的 DeriveSize 第一件事就是 WatchSiblings(旧父控件里的摘掉、
    新的挂上;父控件为 nil 时全摘)。加载中推导不跑 —— 那时挂着的都指向别处的兄弟,
    SiblingChanged 按 Parent 比对不理它们,Loaded 的推导再对一遍。 }
  { 同轴的栏在两边各少了 / 多了一个,各自重分。 }
  if not (csDestroying in ComponentState) then
  begin
    DeriveSiblings(old);
    DeriveSize;
  end;
end;

function TTyCustomToolWindowBar.DerivedAxisPx: Integer;
begin
  Result := DerivedAxisPx(Metrics);
end;

function TTyCustomToolWindowBar.PlacementAlign: TAlign;
begin
  case FPlacement of
    twpRight: Result := alRight;
    twpBottom: Result := alBottom;
  else
    Result := alLeft;
  end;
end;

procedure TTyCustomToolWindowBar.DeriveSize;
var
  m: TTyToolWindowBarMetrics;
  v: Integer;
  noteMoved: Boolean;
begin
  if FDeriving or FDpiAdjusting
     or ([csLoading, csDestroying] * ComponentState <> []) then Exit;
  noteMoved := False;
  FDeriving := True;
  try
    { 推导要扣的兄弟一个不漏地挂上(新来的兄弟在这一刻才被看见)。 }
    WatchSiblings;
    m := Metrics;
    { 设计期提示行高变了:宽不变,对齐引擎不会自己再排。换主题时兄弟栏的 Relayout 经
      DeriveSiblings 先走到这里、把 FLaid 刷成新值,本栏自己的 Invalidate 就看不出来了 ——
      所以在这里就请一次对齐。 }
    noteMoved := FLaidValid and (m.NoteRow <> FLaid.NoteRow);
    FLaid := m;
    FLaidPPI := PPI;
    FLaidValid := True;
    v := DerivedAxisPx(m);
    ApplyAxisSize(v);
    { 同轴的另一条栏按比例分的那一份也跟着变(spec §6.2)。它们各自的 FDeriving 挡住回调。 }
    DeriveSiblings(Parent);
  finally
    FDeriving := False;
  end;
  { Relayout 里接着就 Realign,不重复请。 }
  if noteMoved and not FRelayouting then Realign;
end;

procedure TTyCustomToolWindowBar.ApplyAxisSize(AValue: Integer);
var
  p: TWinControl;
  c, best: TControl;
  nl, nt, nw, nh, cur, key, i: Integer;

  { LCL 的对齐排序键(wincontrol.inc:2522-2546):左 = Left(小的在外),右 = 右沿、底 = 底沿
    (大的在外)。 }
  function KeyOf(L, T, W, H: Integer): Integer;
  begin
    case FPlacement of
      twpRight: Result := L + W;
      twpBottom: Result := T + H;
    else
      Result := L;
    end;
  end;

  function KeyOfControl(AControl: TControl): Integer;
  begin
    Result := KeyOf(AControl.Left, AControl.Top, AControl.Width, AControl.Height);
  end;

  { AKey1 比 AKey2 靠外。 }
  function Outside(AKey1, AKey2: Integer): Boolean;
  begin
    if FPlacement = twpLeft then Result := AKey1 < AKey2
    else Result := AKey1 > AKey2;
  end;

  { 同一父控件里、同向对齐、看得见的兄弟(对齐排序的对手)。 }
  function Rival(AControl: TControl): Boolean;
  begin
    Result := (AControl <> Self) and (AControl.Align = Align) and AControl.IsControlVisible;
  end;

begin
  nl := Left;
  nt := Top;
  nw := Width;
  nh := Height;
  { 排序键那一边(外沿)不动,尺寸往编辑区那一侧长 / 缩(同 TCustomSplitter 对 akRight / akBottom
    的做法,customsplitter.inc:203-212)。只改宽高的话右栏 / 底栏的外沿跟着挪:展开、从宽 0 回来时
    右沿越过外侧的同向兄弟(活动条、状态栏),排序就把栏排到它们外面去了。左栏的键就是 Left,本来
    就不动。 }
  case FPlacement of
    twpRight:
      begin
        cur := Width;
        nl := Left + Width - AValue;
        nw := AValue;
      end;
    twpBottom:
      begin
        cur := Height;
        nt := Top + Height - AValue;
        nh := AValue;
      end;
  else
    cur := Width;
    nw := AValue;
  end;
  if AValue = cur then Exit;
  p := Parent;
  if (p <> nil) and (Align = PlacementAlign) then
  begin
    { 宽 0(侧栏一侧没有窗口、底栏空了或收起)时栏跟紧挨着它的内侧同向兄弟外沿重合,排序键相同。
      相等时 LCL 看 BaseBounds、再看对齐顺序(同上),都不跟着栏的意思走 —— 运行时窗体比设计时窄,
      内侧兄弟的 BaseBounds 就可能「更靠外」,几次对齐之后宽 0 的栏落到它里面去(看不见,不要紧),
      等它回来时就排错了。所以:变成 0 的这一刻记下紧挨着的内侧兄弟(这时栏还有宽,谁在里面一清二楚);
      从 0 回来的这一刻把排序键摆到它外面一格。 }
    if (cur > 0) and (AValue = 0) then
    begin
      key := KeyOf(Left, Top, Width, Height);
      best := nil;
      for i := 0 to p.ControlCount - 1 do
      begin
        c := p.Controls[i];
        if not Rival(c) or not Outside(key, KeyOfControl(c)) then Continue;
        if (best = nil) or Outside(KeyOfControl(c), KeyOfControl(best)) then best := c;
      end;
      FZeroInner := best;
      if best <> nil then best.FreeNotification(Self);
    end
    else if (cur = 0) and (AValue > 0) then
    begin
      if (FZeroInner <> nil) and (FZeroInner.Parent = p) and Rival(FZeroInner)
         and not Outside(KeyOf(nl, nt, nw, nh), KeyOfControl(FZeroInner)) then
      begin
        { 把键摆到记下的那个兄弟外面一格(这个数只是排序键,对齐引擎排一遍就改掉,不留缝)。 }
        key := KeyOfControl(FZeroInner);
        case FPlacement of
          twpRight: nl := key + 1 - nw;
          twpBottom: nt := key + 1 - nh;
        else
          nl := key - 1;
        end;
      end;
      FZeroInner := nil;
    end;
    { 没记下内侧兄弟(生来就是空的、那时它在最里面)时排序键照样可能跟谁相同:不另外挪。下面这一句
      SetBounds 更新栏的 BaseBounds、把它挪到父控件对齐顺序的最前面(UpdateAlignIndex),键和
      BaseBounds 都相同时 LCL 按这个顺序排,先排的就是外面那个 —— 正是栏。 }
  end;
  SetBounds(nl, nt, nw, nh);
end;

procedure TTyCustomToolWindowBar.Relayout;
begin
  if FRelayouting then Exit;
  FRelayouting := True;
  try
    DeriveSize;
    { 内缩量变了:窗口是 alClient,只重画的话它们停在旧的客户区里。 }
    Realign;
  finally
    FRelayouting := False;
  end;
  { 放置预览显示着,而这条栏不再隐藏了(来了窗口、HideWhenEmpty 关了):收掉(spec §9.8)。 }
  if (FDropPreview <> nil) and FDropPreview.Visible and not HiddenAsEmpty then
    HideDropPreview;
end;

procedure TTyCustomToolWindowBar.Invalidate;
var
  m: TTyToolWindowBarMetrics;
  key: string;
begin
  if [csLoading, csDestroying] * ComponentState = [] then
  begin
    key := TyStyleClassFor(Self, StyleClass) + #1 + StyleOverride;
    if FHeaderStyleKeyValid and (key <> FHeaderStyleKey) then
    begin
      FHeaderStyleKey := key;
      InvalidateHeader;
    end
    else
    begin
      FHeaderStyleKey := key;
      FHeaderStyleKeyValid := True;
    end;
  end;
  { 换主题只带来一次裸 Invalidate(Controller.Changed),没人调 Realign。所以在这里比:
    比的是上一次推导**用过**的那一份(FLaid),不是缓存 —— 见 FLaid 的声明。
    **不**在这里问窗口的标题行高:那是窗口自己的缓存,先替它读掉,窗口的 Invalidate
    就看不出主题变了 —— 缓存谁先读就是谁的,换主题的那一次裸 Invalidate 广播到谁先、谁后
    看注册顺序,不能假定窗口总在栏前面。设计期提示行高(NoteRow)读的是 token 本身,
    进栏自己的 Metrics,不碰窗口的缓存。 }
  if FLaidValid and not FRelayouting and not FDpiAdjusting
     and ([csLoading, csDestroying] * ComponentState = []) then
  begin
    m := Metrics;
    if (m.Strip <> FLaid.Strip) or (m.Edge <> FLaid.Edge) or (m.Chrome <> FLaid.Chrome)
       or (m.ContentMin <> FLaid.ContentMin) or (m.NoteRow <> FLaid.NoteRow)
       or (PPI <> FLaidPPI) then
      Relayout;
  end;
  inherited Invalidate;
end;

procedure TTyCustomToolWindowBar.AutoAdjustLayout(AMode: TLayoutAdjustmentPolicy;
  const AFromPPI, AToPPI, AOldFormWidth, ANewFormWidth: Integer);
begin
  { 继承那一遍按比例缩放了 Width(期间 FDpiAdjusting 为真,不写回 ExpandedSize、
    不推导);之后按新 PPI 重新推 —— 按比例缩放的值和推导值会差一个舍入。 }
  inherited AutoAdjustLayout(AMode, AFromPPI, AToPPI, AOldFormWidth, ANewFormWidth);
  Relayout;
end;

function TTyCustomToolWindowBar.WidthIsStored: Boolean;
begin
  Result := FPlacement = twpBottom;
end;

function TTyCustomToolWindowBar.HeightIsStored: Boolean;
begin
  Result := FPlacement <> twpBottom;
end;

procedure TTyCustomToolWindowBar.SetBounds(ALeft, ATop, AWidth, AHeight: Integer);
var
  m: TTyToolWindowBarMetrics;
  v: Integer;
begin
  { 只有设计器拖边这一种来源写回 ExpandedSize。推导(FDeriving)、DPI 缩放
    (FDpiAdjusting)、运行时、流式加载一律不写回 —— 否则收窄值会写回、DPI 会二次缩放,
    低于 96 的 PPI 下推导出来的宽再反算回去还会差一个舍入。
    还没有父控件的也不写回:从面板放下一条栏时,IDE 先 SetBounds 再设 Parent,宽高是把
    「构造出来的宽」当成 96 设计值再按设计器 PPI 放大的(customformeditor.pp:1453-1506)——
    而栏在构造里已经按屏幕 PPI 推导过,150% 下这就放大了两遍,写回的话 ExpandedSize 从 240
    变成 380。拖边只能拖已经在窗体上的栏。 }
  if ([csDesigning, csLoading, csDestroying] * ComponentState = [csDesigning])
     and not FDeriving and not FDpiAdjusting and (Align = PlacementAlign)
     and (Parent <> nil) then
  begin
    m := Metrics;
    if FPlacement = twpBottom then
    begin
      if AHeight <> Height then
      begin
        v := MulDiv(AHeight - 2 * m.Chrome - m.Edge, 96, PPI);
        if v < 0 then v := 0 else if v > 99999 then v := 99999;
        FExpandedSize := v;
        AHeight := DerivedAxisPx(m);
      end;
    end
    else if AWidth <> Width then
    begin
      v := MulDiv(AWidth - m.Strip - 2 * m.Chrome - m.Edge, 96, PPI);
      if v < 0 then v := 0 else if v > 99999 then v := 99999;
      FExpandedSize := v;
      AWidth := DerivedAxisPx(m);
    end;
  end;
  inherited SetBounds(ALeft, ATop, AWidth, AHeight);
end;

procedure TTyCustomToolWindowBar.ConstrainedResize(var MinWidth, MinHeight, MaxWidth,
  MaxHeight: TConstraintSize);
var
  m: TTyToolWindowBarMetrics;
  lo: Integer;
begin
  inherited ConstrainedResize(MinWidth, MinHeight, MaxWidth, MaxHeight);
  { 和推导走同一个分支;只改传进来的下限,不写用户的 Constraints。 }
  m := Metrics;
  if FPlacement = twpBottom then
  begin
    if SizesAsCollapsed then lo := 0
    else lo := 2 * m.Chrome + m.Edge + m.ContentMin;
    if lo > MinHeight then MinHeight := lo;
  end
  else
  begin
    { 隐藏的侧栏(spec §6.9)下限也是 0,否则 LCL 把宽 0 钳回图标条宽。 }
    if HiddenAsEmpty then lo := 0
    else
    begin
      lo := m.Strip + 2 * m.Chrome;
      if not SizesAsCollapsed then Inc(lo, m.Edge + m.ContentMin);
    end;
    if lo > MinWidth then MinWidth := lo;
  end;
end;

procedure TTyCustomToolWindowBar.AdjustClientRect(var ARect: TRect);
begin
  inherited AdjustClientRect(ARect);
  { 内容区只有一个定义:LayoutIn。画的、命中的、摆窗口的是同一份。 }
  ARect := LayoutIn(ARect).Content;
end;

function TTyCustomToolWindowBar.TokenPxAt(const AName: string; ADefault, APPI: Integer): Integer;
begin
  Result := MulDiv(ActiveController.Metric(AName, ADefault), APPI, 96);
  { 度量值不钳(TyEvalLength),负的按 0 算。 }
  if Result < 0 then Result := 0;
end;

function TTyCustomToolWindowBar.StrayCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to ControlCount - 1 do
    if not (Controls[i] is TTyCustomToolWindow) then Inc(Result);
end;

function TTyCustomToolWindowBar.PlacementConflicts: Boolean;
begin
  { 本栏在 manager 的表里、不在释放中时,IsBarUsable 答 False 只有冲突一种原因。释放中的栏
    IsBarUsable 也答 False,但那不是冲突 —— 先排除掉。 }
  Result := (FManager <> nil) and not (csDestroying in FManager.ComponentState)
    and not (csDestroying in ComponentState)
    and not FManager.IsBarUsable(Self);
end;

procedure TTyCustomToolWindowBar.ConflictMayHaveChanged;
begin
  if [csDesigning, csLoading, csDestroying] * ComponentState <> [csDesigning] then Exit;
  Realign;
  Invalidate;
end;

function TTyCustomToolWindowBar.LayoutIn(const AClient: TRect): TTyToolWindowBarLayout;
begin
  Result := LayoutAt(AClient, PPI);
end;

function TTyCustomToolWindowBar.LayoutAt(const AClient: TRect; APPI: Integer): TTyToolWindowBarLayout;
var
  m: TTyToolWindowBarMetrics;
  R: TRect;
  stripS: TTyStyleSet;
  bw, itemPx, bandH, i: Integer;
  slots: TTyToolWindowSlots;

  procedure ClampRect(var ARect: TRect);
  begin
    if ARect.Right < ARect.Left then ARect.Right := ARect.Left;
    if ARect.Bottom < ARect.Top then ARect.Bottom := ARect.Top;
  end;

begin
  Result := Default(TTyToolWindowBarLayout);
  { 一侧没有窗口、整条隐藏(spec §6.9):全是空矩形 —— 没有像素也就没有命中、提示、右键。
    设计期不会走到这里(HiddenAsEmpty 设计期恒假)。 }
  if HiddenAsEmpty then Exit;
  if APPI = PPI then m := Metrics else m := MetricsAt(APPI);
  R := AClient;
  InflateRect(R, -m.Chrome, -m.Chrome);
  ClampRect(R);
  Result.Content := R;
  { chrome 四周各一圈;图标条贴外侧,边缘区贴靠编辑区的那一侧(底栏在顶边)。
    哪一侧一律按 Placement,不看 Align、不看 RTL。 }
  case FPlacement of
    twpLeft:
      begin
        Result.Strip := Rect(R.Left, R.Top, R.Left + m.Strip, R.Bottom);
        Result.Edge := Rect(R.Right - m.Edge, R.Top, R.Right, R.Bottom);
        Inc(Result.Content.Left, m.Strip);
        Dec(Result.Content.Right, m.Edge);
      end;
    twpRight:
      begin
        Result.Strip := Rect(R.Right - m.Strip, R.Top, R.Right, R.Bottom);
        Result.Edge := Rect(R.Left, R.Top, R.Left + m.Edge, R.Bottom);
        Dec(Result.Content.Right, m.Strip);
        Inc(Result.Content.Left, m.Edge);
      end;
    twpBottom:
      begin
        Result.Edge := Rect(R.Left, R.Top, R.Right, R.Top + m.Edge);
        Inc(Result.Content.Top, m.Edge);
      end;
  end;
  { 收起时栏只剩图标条,内容区是负宽 —— 钳成空的,别让对齐引擎拿到反转的矩形。 }
  ClampRect(Result.Content);
  { 栏比图标条还窄时(拖到很窄、正在动画)条不许伸出栏外。底栏没有条,别给它钳出一个位置。 }
  if FPlacement <> twpBottom then
  begin
    if Result.Strip.Left < R.Left then Result.Strip.Left := R.Left;
    if Result.Strip.Right > R.Right then Result.Strip.Right := R.Right;
    ClampRect(Result.Strip);
  end;
  { 运行时收起或没有窗口:宽里本来就没算边缘区(DerivedAxisPx),它也不起作用(spec §5.4 /
    §6.3)—— 不画、不命中。这时按上面算出来的那一条会压在图标条上。 }
  if SizesAsCollapsed then
    Result.Edge := Rect(0, 0, 0, 0)
  else
    ClampRect(Result.Edge);

  { 当前页禁用:内容区顶上让出一行给标签行(spec §3.7),行高同没让出时 —— 标签行不跳。 }
  if HostsTabRow then
  begin
    bandH := BottomRowHeightAt(APPI);
    if bandH > Result.Content.Bottom - Result.Content.Top then
      bandH := Result.Content.Bottom - Result.Content.Top;
    Result.TabRow := Rect(Result.Content.Left, Result.Content.Top,
      Result.Content.Right, Result.Content.Top + bandH);
    Inc(Result.Content.Top, bandH);
  end;

  { 设计期有漏进来的子控件:内容区底部让出一行提示。行高借标题行的 token —— 它本来就是
    「一行字加上下留白」的尺寸。 }
  if (csDesigning in ComponentState) and (StrayCount > 0) then
  begin
    bandH := m.NoteRow;
    if bandH > Result.Content.Bottom - Result.Content.Top then
      bandH := Result.Content.Bottom - Result.Content.Top;
    Result.StrayNote := Rect(Result.Content.Left, Result.Content.Bottom - bandH,
      Result.Content.Right, Result.Content.Bottom);
    Dec(Result.Content.Bottom, bandH);
  end;
  { 设计期 Placement 冲突:再往上让一行,叠在漏入提示那一行上面(spec §10.6)。 }
  if (csDesigning in ComponentState) and PlacementConflicts then
  begin
    bandH := m.NoteRow;
    if bandH > Result.Content.Bottom - Result.Content.Top then
      bandH := Result.Content.Bottom - Result.Content.Top;
    Result.ConflictNote := Rect(Result.Content.Left, Result.Content.Bottom - bandH,
      Result.Content.Right, Result.Content.Bottom);
    Dec(Result.Content.Bottom, bandH);
  end;
  if (csDesigning in ComponentState) and (WindowCount = 0) then
    Result.EmptyNote := Result.Content;

  if Result.Strip.Right <= Result.Strip.Left then Exit;
  { 图标条的界线画在靠内容区那一侧(写法照 TyStatusBar 的顶线),图标只排在界线以内 ——
    否则当前格的指示条会跟界线叠在同一列上。 }
  Result.Cells := Result.Strip;
  stripS := ActiveController.Model.ResolveStyle(TyToolWindowStripKey,
    TyStyleClassFor(Self, StyleClass), [tysNormal]);
  if TyBorderVisible(stripS) then
  begin
    bw := MulDiv(stripS.BorderWidth, APPI, 96);
    if bw < 1 then bw := 1;
    if FPlacement = twpRight then Inc(Result.Cells.Left, bw)
    else Dec(Result.Cells.Right, bw);
    ClampRect(Result.Cells);
  end;
  itemPx := TokenPxAt(TyToolWindowStripItemSizeVar, TyToolWindowStripItemSizeDef, APPI);
  { 溢出按钮跟图标一样大。 }
  slots := TyToolWindowStripLayout(Result.Cells.Right - Result.Cells.Left,
    Result.Cells.Bottom - Result.Cells.Top, itemPx, itemPx, WindowCount, IndexOfWindow(FActive));
  for i := 0 to High(slots) do
    Types.OffsetRect(slots[i].ItemRect, Result.Cells.Left, Result.Cells.Top);
  Result.Slots := slots;
  { 有没有收起来的由调用方自己算(TyToolWindowVisiblePlan 的约定)。溢出按钮紧跟在最后一个
    图标后面:排布时已经从可用高度里给它扣过位置,所以它放得下。 }
  if Length(slots) < WindowCount then
  begin
    i := Result.Cells.Top + Length(slots) * itemPx;
    Result.Overflow := Rect(Result.Cells.Left, i, Result.Cells.Right, i + itemPx);
    if Result.Overflow.Top > Result.Cells.Bottom then Result.Overflow.Top := Result.Cells.Bottom;
    if Result.Overflow.Bottom > Result.Cells.Bottom then Result.Overflow.Bottom := Result.Cells.Bottom;
  end;
end;

function TTyCustomToolWindowBar.BarLayout: TTyToolWindowBarLayout;
begin
  Result := LayoutIn(ClientRect);
end;

function TTyCustomToolWindowBar.StripItemRect(AIndex: Integer): TRect;
var
  L: TTyToolWindowBarLayout;
  i: Integer;
begin
  L := BarLayout;
  for i := 0 to High(L.Slots) do
    if L.Slots[i].ItemIndex = AIndex then Exit(L.Slots[i].ItemRect);
  Result := Rect(0, 0, 0, 0);
end;

function TTyCustomToolWindowBar.OverflowStates: TTyStateSet;
begin
  { 同 StripItemStates:禁用时不接悬停、按下。溢出按钮没有「当前」。 }
  Result := [];
  if not Enabled then
    Include(Result, tysDisabled)
  else
  begin
    if FOverflowHover then Include(Result, tysHover);
    if FOverflowPressed then Include(Result, tysActive);
  end;
  if Result = [] then Include(Result, tysNormal);
end;

function TTyCustomToolWindowBar.StripItemStates(AIndex: Integer; AWindow: TTyCustomToolWindow): TTyStateSet;
begin
  Result := [];
  if (AWindow <> nil) and (AWindow = FActive) and not CollapsedAtRunTime then
    Include(Result, tysSelected);
  { 禁用时保留 :selected(同 TTySegmented):灰掉的栏也得看得出哪一页是当前页。窗口自己被禁用
    同样画 :disabled(spec §3.7)。 }
  if not Enabled or not WindowClickable(AWindow) then
    Include(Result, tysDisabled);
  { 悬停、按下:栏启用,且窗口可点 —— 或者它就是当前页。禁用的当前页仍然点一下收起 / 展开
    (收起是栏的动作,不许被困住,spec §3.7),所以它照样接悬停和按下,只是不能拖。 }
  if Enabled and (WindowClickable(AWindow) or ((AWindow <> nil) and (AWindow = FActive))) then
  begin
    if AIndex = FStripHover then Include(Result, tysHover);
    if AIndex = FStripPressed then Include(Result, tysActive);
  end;
  if Result = [] then Include(Result, tysNormal);
end;

function TTyCustomToolWindowBar.WindowClickable(AWindow: TTyCustomToolWindow): Boolean;
begin
  Result := (AWindow <> nil) and AWindow.Enabled;
end;

procedure TTyCustomToolWindowBar.WindowEnabledChanged(AWindow: TTyCustomToolWindow);
var
  idx: Integer;
begin
  if [csLoading, csDestroying] * ComponentState <> [] then Exit;
  idx := IndexOfWindow(AWindow);
  if idx < 0 then Exit;
  if not AWindow.Enabled then
  begin
    { 手势窗口或捕获者被禁用(spec §3.7):取消。拖着的松开不调顺序,武装着的松开不算点击。 }
    if (FGesture <> nil) and ((FGesture.Window = AWindow) or (FGesture.Capturer = AWindow)) then
      ResetGesture(twgeCancel);
    { 它身上的悬停清掉(当前页例外:它照样接悬停)。 }
    if (AWindow <> FActive) and (FStripHover = idx) then SetStripHover(-1, FOverflowHover);
    if (FHeaderHoverPart = twbpItem) and (FHeaderHoverIndex = idx) then
      SetHeaderHover(twbpNone, -1);
  end;
  if FPlacement = twpBottom then InvalidateHeader
  else Invalidate;
  { 底栏当前页:禁用 / 启用就是让出 / 收回标签行(spec §3.7)。 }
  if AWindow = FActive then TabRowHostMayHaveChanged;
end;

procedure TTyCustomToolWindowBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, stripS, itemS, partS: TTyStyleSet;
  R, cell, gr, rule: TRect;
  L: TTyToolWindowBarLayout;
  cls: string;
  list: TCustomImageList;
  bmp: TBGRABitmap;
  fill: TTyFill;
  ink: TTyColor;
  states: TTyStateSet;
  wins: TTyToolWindowArray;
  w: TTyCustomToolWindow;
  bsz: TSize;
  bpt: TPoint;
  btxt: string;
  bdot: Boolean;
  i, idx, glyphPx, indPx, bw, pad: Integer;
begin
  P := TTyPainter.Create;
  try
    { painter 的位图是 W×H 并 blit 到 ARect 左上,所以内部一切坐标都用 (0,0)-local。
      几何一律是物理方向(Placement 定左右),不看 RTL;画笔的 RTL 只管文字的对齐和阅读方向
      (同 TTyToolWindow.RenderTo 的标题行)—— 这里只有设计期提示是文字。几何和 token 一律
      按 APPI(LayoutAt / TokenPxAt),跟传进来的密度是同一套尺度。 }
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI, IsRightToLeft);
    S := CurrentStyle;
    DrawFrame(P, R, S);
    L := LayoutAt(R, APPI);
    cls := TyStyleClassFor(Self, StyleClass);
    fill := Default(TTyFill);
    fill.Kind := tfkSolid;

    if L.Strip.Right > L.Strip.Left then
    begin
      stripS := ActiveController.Model.ResolveStyle(TyToolWindowStripKey, cls, [tysNormal]);
      if tpBackground in stripS.Present then
        P.FillBackground(L.Strip, stripS.Background, 0);
      { 界线:靠内容区那一侧一条,不是整圈框(同 TyStatusBar)。宽度与 LayoutIn 扣掉的同一个数。 }
      if TyBorderVisible(stripS) then
      begin
        bw := L.Strip.Right - L.Strip.Left - (L.Cells.Right - L.Cells.Left);
        if bw > 0 then
        begin
          if FPlacement = twpRight then
            rule := Rect(L.Strip.Left, L.Strip.Top, L.Strip.Left + bw, L.Strip.Bottom)
          else
            rule := Rect(L.Strip.Right - bw, L.Strip.Top, L.Strip.Right, L.Strip.Bottom);
          fill.Color := stripS.BorderColor;
          P.FillBackground(rule, fill, 0);
        end;
      end;

      list := EffectiveImages;
      glyphPx := TokenPxAt(TyToolWindowGlyphSizeVar, TyToolWindowGlyphSizeDef, APPI);
      indPx := TokenPxAt(TyToolWindowStripIndicatorSizeVar, TyToolWindowStripIndicatorSizeDef, APPI);
      { 窗口表取一次:Windows[] 每问一次都数一遍 Controls。 }
      wins := WindowList(nil);
      for i := 0 to High(L.Slots) do
      begin
        cell := L.Slots[i].ItemRect;
        if (cell.Right <= cell.Left) or (cell.Bottom <= cell.Top) then Continue;
        if (L.Slots[i].ItemIndex < 0) or (L.Slots[i].ItemIndex > High(wins)) then Continue;
        w := wins[L.Slots[i].ItemIndex];
        states := StripItemStates(L.Slots[i].ItemIndex, w);
        itemS := ActiveController.Model.ResolveStyle(TyToolWindowStripItemKey, cls, states);
        if tpBackground in itemS.Present then
          P.FillBackground(cell, itemS.Background, 0);
        { 图标序号只从 ResolvedImageIndex 来:窗口的 ImageIndex 在名字找不到时会退回写过的
          序号,而 spec §8 要的是「找不到就不画」。 }
        idx := ResolvedImageIndex(w);
        if (list <> nil) and (idx >= 0) and (glyphPx > 0) then
        begin
          bmp := TyRenderImage(list, idx, glyphPx, APPI, False);
          if bmp <> nil then
          try
            { 本库的列表出来的是列表自己的 GlyphColor,不是墨色 —— 着成这一格状态的墨色。
              TyRenderImage 给的是调用方持有的拷贝,就地染不污染缓存。外来列表不染
              (部分 widgetset 物化出来的位图丢了 alpha,染了就是一个实心方块,spec §8)。 }
            if not TyImageIsBaked(list) then
            begin
              if tpTextColor in itemS.Present then ink := itemS.TextColor
              else ink := stripS.TextColor;
              TyTintBitmapAlpha(bmp, ink);
              if TyAlphaOf(ink) < 255 then TyFadeBitmapAlpha(bmp, TyAlphaOf(ink));
            end;
            P.Bitmap.PutImage(cell.Left + (cell.Right - cell.Left - bmp.Width) div 2,
              cell.Top + (cell.Bottom - cell.Top - bmp.Height) div 2, bmp,
              dmDrawWithTransparency);
          finally
            bmp.Free;
          end;
        end;
        { 当前格的指示条:贴在靠内容区那一侧,粗细 0 = 不画。 }
        if (tysSelected in states) and (indPx > 0) then
        begin
          partS := ActiveController.Model.ResolveStyle(TyToolWindowStripIndicatorKey, cls,
            [tysNormal]);
          if tpBackground in partS.Present then
          begin
            if FPlacement = twpRight then
              gr := Rect(cell.Left, cell.Top, cell.Left + indPx, cell.Bottom)
            else
              gr := Rect(cell.Right - indPx, cell.Top, cell.Right, cell.Bottom);
            P.FillBackground(gr, partS.Background, 0);
          end;
        end;
        { 角标(spec §8.1):图标格右上角,按画笔的读写方向镜像(同 TTyButton);在图标和指示条
          之后画 —— 在最上面。栏收起时照画(图标条还在)。 }
        bsz := BadgeSizeAt(w, APPI, btxt, bdot);
        if bsz.cx > 0 then
        begin
          bpt := TyBadgeCornerPos(cell, bsz.cx, bsz.cy,
            TokenPxAt(TyBadgeInsetVar, TyBadgeInset, APPI),
            TyBidiFlipBadgePosition(bpTopRight, P.RightToLeft));
          DrawBadgeIn(P, Rect(bpt.X, bpt.Y, bpt.X + bsz.cx, bpt.Y + bsz.cy), btxt, bdot);
        end;
      end;

      { 溢出按钮:图标大小的一格,中间一个字形大小的下箭头(主题可换,--glyph-chevron-down)。 }
      if (L.Overflow.Right > L.Overflow.Left) and (L.Overflow.Bottom > L.Overflow.Top) then
      begin
        { 状态照图标格(OverflowStates):悬停、按下、禁用。底色取溢出按钮自己的规则;字形的
          墨色取图标条的墨色(图标项按同一组状态解析)—— TyToolWindowOverflow 的 color 是给
          底栏标签行的(--toolwindow-tab-ink),皮肤只调了图标条的墨色时,条上的箭头得跟着图标走。 }
        states := OverflowStates;
        partS := ActiveController.Model.ResolveStyle(TyToolWindowOverflowKey, cls, states);
        if tpBackground in partS.Present then
          P.FillBackground(L.Overflow, partS.Background, 0);
        itemS := ActiveController.Model.ResolveStyle(TyToolWindowStripItemKey, cls, states);
        if tpTextColor in itemS.Present then ink := itemS.TextColor
        else ink := stripS.TextColor;
        gr := L.Overflow;
        if glyphPx < gr.Right - gr.Left then
        begin
          gr.Left := gr.Left + (gr.Right - gr.Left - glyphPx) div 2;
          gr.Right := gr.Left + glyphPx;
        end;
        if glyphPx < gr.Bottom - gr.Top then
        begin
          gr.Top := gr.Top + (gr.Bottom - gr.Top - glyphPx) div 2;
          gr.Bottom := gr.Top + glyphPx;
        end;
        TyDrawGlyph(P, ActiveController, gr, tgChevronDown, ink, 1);
      end;
    end;

    { 拖动调顺序的插入线:画进 BGRA 层,在 EndPaint 之前(之后画 GDI 会被盖掉)。 }
    idx := DropLineY(L);
    if idx >= 0 then
    begin
      bw := TokenPxAt(TyToolWindowDropSizeVar, TyToolWindowDropSizeDef, APPI);
      partS := ActiveController.Model.ResolveStyle(TyToolWindowDropIndicatorKey, cls, [tysNormal]);
      if (bw > 0) and (tpBackground in partS.Present) then
      begin
        gr := Rect(L.Cells.Left, idx - bw div 2, L.Cells.Right, idx - bw div 2 + bw);
        if gr.Top < L.Cells.Top then Types.OffsetRect(gr, 0, L.Cells.Top - gr.Top);
        if gr.Bottom > L.Cells.Bottom then Types.OffsetRect(gr, 0, L.Cells.Bottom - gr.Bottom);
        P.FillBackground(gr, partS.Background, 0);
      end;
    end;

    { 边缘区:拉宽边,也是贴着编辑区的那条分隔线(spec §6.3 / §12)。静止时不单独填色,只在
      靠编辑区那一侧画一条线(border-color / border-width,写法照 TyStatusBar 的顶线);悬停和
      拉宽中主题给整块底色、把线收掉。两样都由主题说了算,这里有什么画什么。 }
    if (L.Edge.Right > L.Edge.Left) and (L.Edge.Bottom > L.Edge.Top) then
    begin
      if EdgeResizing then states := [tysActive]
      else if FEdgeHover then states := [tysHover]
      else states := [tysNormal];
      partS := ActiveController.Model.ResolveStyle(TyToolWindowEdgeKey, cls, states);
      if tpBackground in partS.Present then
        P.FillBackground(L.Edge, partS.Background, 0);
      if TyBorderVisible(partS) then
      begin
        bw := MulDiv(partS.BorderWidth, APPI, 96);
        if bw < 1 then bw := 1;
        case FPlacement of
          twpLeft:
            begin
              if bw > L.Edge.Right - L.Edge.Left then bw := L.Edge.Right - L.Edge.Left;
              gr := Rect(L.Edge.Right - bw, L.Edge.Top, L.Edge.Right, L.Edge.Bottom);
            end;
          twpRight:
            begin
              if bw > L.Edge.Right - L.Edge.Left then bw := L.Edge.Right - L.Edge.Left;
              gr := Rect(L.Edge.Left, L.Edge.Top, L.Edge.Left + bw, L.Edge.Bottom);
            end;
        else
          if bw > L.Edge.Bottom - L.Edge.Top then bw := L.Edge.Bottom - L.Edge.Top;
          gr := Rect(L.Edge.Left, L.Edge.Top, L.Edge.Right, L.Edge.Top + bw);
        end;
        fill.Color := partS.BorderColor;
        P.FillBackground(gr, fill, 0);
      end;
    end;

    { 让出来的标签行(spec §3.7):当前页被禁用,栏在自己的像素里画它 —— 不受页的 opacity
      影响(栏没禁用)。几何照当前页的算(操作区那一格按首选宽留着),让出前后标签不重排。 }
    if (L.TabRow.Right > L.TabRow.Left) and (L.TabRow.Bottom > L.TabRow.Top) and (FActive <> nil) then
      PaintHeader(FActive, P, L.TabRow,
        HeaderGeometry(FActive, L.TabRow.Right - L.TabRow.Left, L.TabRow.Bottom - L.TabRow.Top, APPI),
        APPI);

    { 设计期提示(LayoutIn 只在设计期给这三个框)。 }
    if (L.EmptyNote.Right > L.EmptyNote.Left) or (L.StrayNote.Right > L.StrayNote.Left)
       or (L.ConflictNote.Right > L.ConflictNote.Left) then
    begin
      partS := ActiveController.Model.ResolveStyle(TyToolWindowNoteKey, cls, [tysNormal]);
      pad := TokenPxAt(TyToolWindowHeaderPadVar, TyToolWindowHeaderPadDef, APPI);
      gr := L.EmptyNote;
      InflateRect(gr, -pad, 0);
      if (gr.Right > gr.Left) and (gr.Bottom > gr.Top) then
        P.DrawText(gr, rsTyToolWindowBarEmpty, partS.FontName, ResolveFontSize(partS),
          partS.FontWeight, partS.TextColor, taCenter, tlCenter, True);
      gr := L.StrayNote;
      InflateRect(gr, -pad, 0);
      if (gr.Right > gr.Left) and (gr.Bottom > gr.Top) then
        P.DrawText(gr, rsTyToolWindowBarStray, partS.FontName, ResolveFontSize(partS),
          partS.FontWeight, partS.TextColor, taLeftJustify, tlCenter, True);
      gr := L.ConflictNote;
      InflateRect(gr, -pad, 0);
      if (gr.Right > gr.Left) and (gr.Bottom > gr.Top) then
        P.DrawText(gr, rsTyToolWindowBarConflict, partS.FontName, ResolveFontSize(partS),
          partS.FontWeight, partS.TextColor, taLeftJustify, tlCenter, True);
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyCustomToolWindowBar.Paint;
begin
  { 不做绘制缓存:悬停变化频繁,而且没有会不停打脏它的子控件(工具窗口有,所以工具窗口做)。 }
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

procedure TTyCustomToolWindowBar.InsertControl(AControl: TControl; Index: Integer);
begin
  inherited InsertControl(AControl, Index);
  if AControl is TTyCustomToolWindow then Exit;
  { 漏进来的:运行时藏起来(写 Visible 而不是派生 —— 这不是我们的类,IsControlVisible
    重写不了;运行时写 Visible 也进不了 .lfm)。设计期让出提示那一行,内缩量变了要重排。 }
  if not (csDesigning in ComponentState) then
    AControl.Visible := False
  else if not (csDestroying in ComponentState) then
  begin
    Realign;
    Invalidate;
  end;
end;

{ --- 底栏标题行(栏作宿主,spec §7.2) ----------------------------------------------- }

function TTyCustomToolWindowBar.MeasureTabWidths(const AWins: TTyToolWindowArray;
  APPI: Integer): TTyToolWindowWidths;
var
  cls: string;
  restS, selS, disS: TTyStyleSet;
  bsz: TSize;
  btxt: string;
  bdot: Boolean;
  i, pad, gap, w, sw: Integer;

  function TextPx(const AText: string; const AStyle: TTyStyleSet): Integer;
  var
    bw, bh, rw, fs: Integer;
  begin
    if AText = '' then Exit(0);
    fs := ResolveFontSize(AStyle);
    { 两种量法取大(Painter.pas 的约定):只按画布量,渲染器多出一个像素就出省略号。 }
    TyMeasureTextBlock(AText, AStyle.FontName, fs, AStyle.FontWeight, APPI, 0, 0, bw, bh);
    rw := TyMeasureRenderedTextWidth(AText, AStyle.FontName, fs, AStyle.FontWeight, APPI);
    if rw > bw then bw := rw;
    Result := bw;
  end;

begin
  cls := TyStyleClassFor(Self, StyleClass);
  restS := ActiveController.Model.ResolveStyle(TyToolWindowTabKey, cls, [tysNormal]);
  selS := ActiveController.Model.ResolveStyle(TyToolWindowTabKey, cls, [tysSelected]);
  disS := ActiveController.Model.ResolveStyle(TyToolWindowTabKey, cls, [tysDisabled]);
  pad := TokenPxAt(TyToolWindowTabPadVar, TyToolWindowTabPadDef, APPI);
  gap := TokenPxAt(TyToolWindowHeaderGapVar, TyToolWindowHeaderGapDef, APPI);
  Result := nil;
  SetLength(Result, Length(AWins));
  for i := 0 to High(AWins) do
  begin
    { 三种状态取大(spec §7.3):皮肤只让选中态加粗时,按静止态量会截当前标签,按各自
      状态量则切页时整行重排。:disabled 同理(E 期):窗口禁用 / 启用、栏或它的父控件被禁用
      (整行画 :disabled)时标签不许跳、不许被截 —— 所以不管此刻谁禁用着,每个标签都量它,
      宽也就跟 Enabled 无关,缓存键里不用记。 }
    w := TextPx(AWins[i].Caption, restS);
    sw := TextPx(AWins[i].Caption, selS);
    if sw > w then w := sw;
    sw := TextPx(AWins[i].Caption, disS);
    if sw > w then w := sw;
    { 角标(spec §8.1):标签 = [tab-pad][标题][header-gap][胶囊][tab-pad]。 }
    bsz := BadgeSizeAt(AWins[i], APPI, btxt, bdot);
    if bsz.cx > 0 then Inc(w, gap + bsz.cx);
    Result[i] := w + 2 * pad;
  end;
end;

function TTyCustomToolWindowBar.BadgeCacheKey(AWindow: TTyCustomToolWindow): string;
var
  txt: string;
  dot: Boolean;
begin
  if not AWindow.BadgeDisplay(txt, dot) then Result := ''
  else if dot then Result := #1'dot'
  else Result := '#' + txt;
end;

procedure TTyCustomToolWindowBar.TabWidthsChanged;
begin
  FTabCacheValid := False;
end;

function TTyCustomToolWindowBar.TabWidthsAt(APPI: Integer): TTyToolWindowWidths;
var
  wins: TTyToolWindowArray;
  mdl: TTyStyleModel;
  ver: Cardinal;
  cls: string;
  hit: Boolean;
  i, restFs, selFs, disFs: Integer;
begin
  wins := WindowList(nil);
  if APPI <> PPI then Exit(MeasureTabWidths(wins, APPI));
  mdl := ActiveController.Model;
  ver := mdl.ThemeVersion;
  cls := TyStyleClassFor(Self, StyleClass);
  restFs := ResolveFontSize(mdl.ResolveStyle(TyToolWindowTabKey, cls, [tysNormal]));
  selFs := ResolveFontSize(mdl.ResolveStyle(TyToolWindowTabKey, cls, [tysSelected]));
  disFs := ResolveFontSize(mdl.ResolveStyle(TyToolWindowTabKey, cls, [tysDisabled]));
  { 快照每次现取,逐项比(见 FTabCacheValid)。 }
  hit := FTabCacheValid and (FTabCachePPI = APPI) and (FTabCacheAnchor = TObject(mdl))
    and (FTabCacheVer = ver) and (FTabCacheClass = cls) and (FTabCacheOverride = StyleOverride)
    and (FTabCacheRestFs = restFs) and (FTabCacheSelFs = selFs) and (FTabCacheDisFs = disFs)
    and (Length(FTabCacheWins) = Length(wins));
  if hit then
    for i := 0 to High(wins) do
      if (FTabCacheWins[i] <> wins[i]) or (FTabCacheCaps[i] <> wins[i].Caption)
         or (FTabCacheBadges[i] <> BadgeCacheKey(wins[i])) then
      begin
        hit := False;
        Break;
      end;
  if not hit then
  begin
    FTabCacheWidths := MeasureTabWidths(wins, APPI);
    FTabCacheWins := wins;
    FTabCacheCaps := nil;
    SetLength(FTabCacheCaps, Length(wins));
    FTabCacheBadges := nil;
    SetLength(FTabCacheBadges, Length(wins));
    for i := 0 to High(wins) do
    begin
      FTabCacheCaps[i] := wins[i].Caption;
      FTabCacheBadges[i] := BadgeCacheKey(wins[i]);
    end;
    FTabCachePPI := APPI;
    FTabCacheAnchor := TObject(mdl);
    FTabCacheVer := ver;
    FTabCacheClass := cls;
    FTabCacheOverride := StyleOverride;
    FTabCacheRestFs := restFs;
    FTabCacheSelFs := selFs;
    FTabCacheDisFs := disFs;
    FTabCacheValid := True;
  end;
  { 拷一份出去:动态数组赋值共享存储,调用方改了会改到缓存。 }
  Result := Copy(FTabCacheWidths);
end;

function TTyCustomToolWindowBar.SeparatorLinePx(APPI: Integer): Integer;
var
  S: TTyStyleSet;
begin
  S := ActiveController.Model.ResolveStyle(TyToolWindowSeparatorKey,
    TyStyleClassFor(Self, StyleClass), [tysNormal]);
  if not TyBorderVisible(S) then Exit(0);
  Result := MulDiv(S.BorderWidth, APPI, 96);
  if Result < 1 then Result := 1;
end;

function TTyCustomToolWindowBar.HeaderInputFor(AWindow: TTyCustomToolWindow; ARowWidth, ARowHeight,
  APPI: Integer): TTyToolWindowHeaderInput;
begin
  Result := AWindow.HeaderInput(APPI, ARowWidth);
  Result.RowHeight := ARowHeight;
  if Result.Mode <> twhBottom then Exit;
  Result.TabWidths := TabWidthsAt(APPI);
  Result.ActiveIndex := IndexOfWindow(FActive);
  Result.TabAreaMin := TokenPxAt(TyToolWindowTabAreaMinVar, TyToolWindowTabAreaMinDef, APPI);
  Result.ButtonSize := TokenPxAt(TyToolWindowButtonSizeVar, TyToolWindowButtonSizeDef, APPI);
  { 溢出按钮跟最大化 / 收起一样大。 }
  Result.OverflowWidth := Result.ButtonSize;
  Result.SeparatorWidth := 2 * Result.Gap + SeparatorLinePx(APPI);
end;

function TTyCustomToolWindowBar.HeaderMode(AWindow: TTyCustomToolWindow): TTyToolWindowHeaderMode;
begin
  { 只看位置(同 TTyToolWindow.HeaderMode 的说明)。 }
  if FPlacement = twpBottom then Result := twhBottom
  else Result := twhSide;
end;

function TTyCustomToolWindowBar.HostsTabRow: Boolean;
begin
  { 设计期不让出:设计期 LCL 不禁用句柄(wincontrol.inc:6758),页照常收得到。收起时高 0,
    本来就没有这一行;拉宽边正吸附着(按收起排布,SizesAsCollapsed)同样高 0 —— 两种一个口径,
    TabRowHost / TabRowHostControl 都经这里,不会一个答栏、一个答没有。「禁用」看页自己的
    Enabled(地雷:IsEnabled 顺着父链算,栏一禁用全都答假)。 }
  Result := (FPlacement = twpBottom) and (FActive <> nil) and not FActive.Enabled
    and not (csDesigning in ComponentState) and not FCollapsed and not EdgeSnapped;
end;

function TTyCustomToolWindowBar.BottomRowHeightAt(APPI: Integer): Integer;
var
  a: Integer;
begin
  Result := TokenPxAt(TyToolWindowHeaderHeightVar, TyToolWindowHeaderHeightDef, APPI);
  a := HeaderActionsHeight(nil, APPI);
  if a > Result then Result := a;
  if Result < 1 then Result := 1;
end;

function TTyCustomToolWindowBar.TabRowHost: TTyToolWindowTabRowHost;
var
  L: TTyToolWindowBarLayout;
begin
  Result := Default(TTyToolWindowTabRowHost);
  if (FPlacement <> twpBottom) or (FActive = nil) then Exit;
  { PPI 与 FActive.Font.PixelsPerInch 在推送之后是同一个数;两支各用各的是照搬原来的调用点
    (栏画自己按栏的 PPI、页按自己字体的),别顺手统一。 }
  if HostsTabRow then
  begin
    L := BarLayout;
    if L.TabRow.Bottom <= L.TabRow.Top then Exit;
    Result.Host := Self;
    Result.Row := L.TabRow;
    Result.Geom := HeaderGeometry(FActive, L.TabRow.Right - L.TabRow.Left,
      L.TabRow.Bottom - L.TabRow.Top, PPI);
  end
  else
  begin
    Result.Row := FActive.HeaderRowRect;
    if Result.Row.Bottom <= Result.Row.Top then Exit;
    Result.Host := FActive;
    Result.Geom := FActive.HeaderGeomAt(Rect(0, 0, FActive.ClientWidth, FActive.ClientHeight),
      FActive.Font.PixelsPerInch);
  end;
end;

function TTyCustomToolWindowBar.TabRowHostControl: TWinControl;
begin
  if FPlacement <> twpBottom then Result := nil
  else if HostsTabRow then Result := Self
  else Result := FActive;
end;

procedure TTyCustomToolWindowBar.TabRowHostMayHaveChanged;
var
  now: Boolean;
begin
  if [csLoading, csDestroying] * ComponentState <> [] then Exit;
  now := HostsTabRow;
  if now = FTabRowHosted then Exit;
  FTabRowHosted := now;
  { 标签行换了宿主:进行中的标签行手势跟着失效(捕获者、坐标系都不是原来那个了);拉宽不算。 }
  if (FGesture <> nil) and not FGesture.Resizing
     and (FGesture.Part in [twbpItem, twbpOverflow, twbpMaximize, twbpCollapse]) then
    ResetGesture(twgeCancel);
  Realign;
  if (FActive <> nil) and not (csDestroying in FActive.ComponentState) then
    FActive.RelayoutHeader;
  Invalidate;
  InvalidateHeader;
end;

function TTyCustomToolWindowBar.InDisabledActivePage(const AP: TPoint): Boolean;
begin
  Result := (FActive <> nil) and not FActive.Enabled and FActive.Visible
    and PtInRect(FActive.BoundsRect, AP);
end;

function TTyCustomToolWindowBar.SwallowPress(const AP: TPoint): Boolean;
begin
  Result := (HostsTabRow and PtInRect(BarLayout.TabRow, AP)) or InDisabledActivePage(AP);
end;

function TTyCustomToolWindowBar.HeaderActionsHeight(AWindow: TTyCustomToolWindow; APPI: Integer): Integer;
var
  wins: TTyToolWindowArray;
  i, h: Integer;
begin
  { 每一页操作区的 raw 首选高都算 —— 不只当前页:切页时标签行不许跳(spec §3.4)。 }
  Result := 0;
  wins := WindowList(nil);
  for i := 0 to High(wins) do
  begin
    h := wins[i].ActionsPreferredSize(APPI).cy;
    if h > Result then Result := h;
  end;
end;

procedure TTyCustomToolWindowBar.ActionsSizeChanged;
var
  h: Integer;
begin
  if [csLoading, csDestroying] * ComponentState <> [] then Exit;
  if FPlacement <> twpBottom then Exit;
  h := HeaderActionsHeight(nil, PPI);
  if h = FBottomActionsPx then Exit;
  FBottomActionsPx := h;
  { 重排当前页会摆它的操作区,操作区的 AdjustSize 又会回到这里;值已经记下了,挡一层就够。 }
  if FActionsNotifying or (FActive = nil) then Exit;
  FActionsNotifying := True;
  try
    { 标签行让到了栏里(spec §3.7):行高是栏的内容区扣掉的,得栏重排。 }
    if HostsTabRow then
    begin
      Realign;
      Invalidate;
    end;
    FActive.RelayoutHeader;
  finally
    FActionsNotifying := False;
  end;
end;

function TTyCustomToolWindowBar.HeaderGeometry(AWindow: TTyCustomToolWindow; ARowWidth, ARowHeight,
  APPI: Integer): TTyToolWindowHeaderGeom;
var
  w: TTyCustomToolWindow;
begin
  w := AWindow;
  if w = nil then w := FActive;
  if w = nil then Exit(Default(TTyToolWindowHeaderGeom));
  Result := TyToolWindowHeaderLayout(HeaderInputFor(w, ARowWidth, ARowHeight, APPI));
end;

function TTyCustomToolWindowBar.HeaderPressed(AWindow: TTyCustomToolWindow; APart: TTyToolWindowBarPart;
  AItem: TTyCustomToolWindow): Boolean;
begin
  { 拖动中被拖的那个标签(源)照样画按下态,直到手势收尾;按钮不是拖动把手,只有武装态。
    捕获者要是标签行此刻的宿主(当前页,或让出时的栏,spec §3.7);AWindow 只是画它的那一页。 }
  Result := (FGesture <> nil) and (AWindow <> nil)
    and ((FGesture.State = twgsArmed) or ((FGesture.State = twgsDragging) and (APart = twbpItem)))
    and (FGesture.Capturer <> nil) and (FGesture.Capturer = TabRowHostControl)
    and (FGesture.Part = APart);
  if Result and (APart = twbpItem) then
    Result := (AItem <> nil) and (FGesture.Window = AItem);
end;

function TTyCustomToolWindowBar.HeaderCapturedBy(AWindow: TTyCustomToolWindow): Boolean;
begin
  Result := (AWindow <> nil) and (FGesture <> nil) and (FGesture.Capturer = AWindow);
end;

function TTyCustomToolWindowBar.HeaderTabStates(AWindow: TTyCustomToolWindow; AIndex, AActiveIndex: Integer;
  AItem: TTyCustomToolWindow): TTyStateSet;
begin
  Result := [];
  if AIndex = AActiveIndex then Include(Result, tysSelected);
  { 禁用时保留 :selected(同图标条):灰掉的栏也得看得出哪一页是当前页。禁用看 IsEnabled
    (父控件被禁用也算)—— 跟 HeaderMouseDown 收不收按下是同一个判断。窗口自己被禁用
    (spec §3.7)同样画 :disabled、不接悬停和按下 —— 是不是当前页都一样:底栏点当前页的标签
    本来什么都不做。 }
  if not IsEnabled or not WindowClickable(AItem) then
    Include(Result, tysDisabled)
  else if not (tysSelected in Result) then
  begin
    if (FHeaderHoverPart = twbpItem) and (FHeaderHoverIndex = AIndex) then
      Include(Result, tysHover);
    if HeaderPressed(AWindow, twbpItem, AItem) then Include(Result, tysActive);
  end;
  if Result = [] then Include(Result, tysNormal);
end;

function TTyCustomToolWindowBar.HeaderPartStates(AWindow: TTyCustomToolWindow;
  APart: TTyToolWindowBarPart): TTyStateSet;
begin
  Result := [];
  if not IsEnabled then
    Include(Result, tysDisabled)
  else
  begin
    if FHeaderHoverPart = APart then Include(Result, tysHover);
    if HeaderPressed(AWindow, APart, nil) then Include(Result, tysActive);
  end;
  if Result = [] then Include(Result, tysNormal);
end;

function TTyCustomToolWindowBar.PartOfZone(AZone: TTyToolWindowZone): TTyToolWindowBarPart;
begin
  case AZone of
    twzTab: Result := twbpItem;
    twzOverflow: Result := twbpOverflow;
    twzSeparator: Result := twbpSeparator;
    twzMaximize: Result := twbpMaximize;
    twzCollapse: Result := twbpCollapse;
  else
    Result := twbpNone;
  end;
end;

procedure TTyCustomToolWindowBar.SetHeaderHover(APart: TTyToolWindowBarPart; AIndex: Integer);
begin
  { 分隔线不可点,没有悬停态。 }
  if APart = twbpSeparator then APart := twbpNone;
  if APart <> twbpItem then AIndex := -1;
  if (APart = FHeaderHoverPart) and (AIndex = FHeaderHoverIndex) then Exit;
  FHeaderHoverPart := APart;
  FHeaderHoverIndex := AIndex;
  InvalidateHeader;
end;

function TTyCustomToolWindowBar.RowDropSlot(const AHost: TTyToolWindowTabRowHost;
  X, Y: Integer): Integer;
var
  g: TTyToolWindowHeaderGeom;
  rowW, rowH: Integer;
  rtl: Boolean;
  pt: TPoint;
begin
  Result := -1;
  if AHost.Host = nil then Exit;
  { 行内坐标。行里、不在操作区里才算标签行区域(同 TTyToolWindow.InTabRowRegionOf)。 }
  pt := Point(X - AHost.Row.Left, Y - AHost.Row.Top);
  rowW := AHost.Row.Right - AHost.Row.Left;
  rowH := AHost.Row.Bottom - AHost.Row.Top;
  if not PtInRect(Rect(0, 0, rowW, rowH), pt) or PtInRect(AHost.Geom.Actions, pt) then Exit;
  { 几何按画它的那一页的读写方向镜像:页当宿主就是它,栏当宿主是当前页。 }
  if AHost.Host is TTyCustomToolWindow then rtl := TTyCustomToolWindow(AHost.Host).IsRightToLeft
  else rtl := (FActive <> nil) and FActive.IsRightToLeft;
  g := AHost.Geom;
  if rtl then
  begin
    { 就地翻的是一份拷贝:动态数组赋值共享存储,不先拷一份就翻到了调用方手上的几何。 }
    g.Tabs := Copy(AHost.Geom.Tabs);
    TyToolWindowFlipAll(g, rowW);
    pt.X := rowW - 1 - pt.X;
  end;
  Result := TyToolWindowSlotAt(g.Tabs, pt.X, pt.Y, False, WindowCount);
end;

procedure TTyCustomToolWindowBar.RowDragIn(const AHost: TTyToolWindowTabRowHost; X, Y: Integer);
var
  slot: Integer;
begin
  slot := RowDropSlot(AHost, X, Y);
  SetDropSlot(slot);
  { 出了标签行 = 没有目标,在这里松开就是取消(spec §9.4)。 }
  if slot < 0 then FGesture.SetCursor(crNoDrop) else FGesture.SetCursor(crDrag);
end;

function TTyCustomToolWindowBar.PageRowHost(AWindow: TTyCustomToolWindow;
  const AGeom: TTyToolWindowHeaderGeom): TTyToolWindowTabRowHost;
begin
  Result.Host := AWindow;
  Result.Row := AWindow.HeaderRowRect;
  Result.Geom := AGeom;
end;

procedure TTyCustomToolWindowBar.InvalidateHeader;
begin
  if (FPlacement <> twpBottom) or (csDestroying in ComponentState) then Exit;
  { 标签行让到了栏里(当前页被禁用,spec §3.7):画在栏自己的像素里,栏没有绘制缓存,
    重画栏就够。 }
  if HostsTabRow then
  begin
    Invalidate;
    Exit;
  end;
  { 当前页正在释放(它的注销会走到这里):不碰它。 }
  if (FActive <> nil) and not (csDestroying in FActive.ComponentState) then
    FActive.Invalidate;
end;

procedure TTyCustomToolWindowBar.PaintHeader(AWindow: TTyCustomToolWindow; APainter: TTyPainter;
  const ARow: TRect; const AGeom: TTyToolWindowHeaderGeom; APPI: Integer);
var
  cls: string;
  S: TTyStyleSet;
  r, box, gr: TRect;
  fill: TTyFill;
  wins: TTyToolWindowArray;
  tbox: TRect;
  bsz: TSize;
  btxt: string;
  bdot: Boolean;
  pad, gap, bx, by, indPx, glyphPx, line, active, i, idx, bandTop, bandBottom, dropPx: Integer;

  { 部件矩形换到画笔坐标(行在窗口里的位置)。 }
  function Place(const ARect: TRect): TRect;
  begin
    Result := ARect;
    Types.OffsetRect(Result, ARow.Left, ARow.Top);
  end;

  function IsEmptyBox(const ARect: TRect): Boolean;
  begin
    Result := (ARect.Right <= ARect.Left) or (ARect.Bottom <= ARect.Top);
  end;

  { 按钮格里居中一个字形大小的方框(照图标条的溢出按钮)。 }
  function GlyphBox(const ACell: TRect): TRect;
  begin
    Result := ACell;
    if glyphPx < Result.Right - Result.Left then
    begin
      Result.Left := Result.Left + (Result.Right - Result.Left - glyphPx) div 2;
      Result.Right := Result.Left + glyphPx;
    end;
    if glyphPx < Result.Bottom - Result.Top then
    begin
      Result.Top := Result.Top + (Result.Bottom - Result.Top - glyphPx) div 2;
      Result.Bottom := Result.Top + glyphPx;
    end;
  end;

  { 溢出 / 最大化 / 收起:底色 + 字形,墨色取这个键自己的 color(spec §12)。 }
  procedure PaintButton(const ACell: TRect; const AKey: string; APart: TTyToolWindowBarPart;
    AGlyph: TTyGlyphKind);
  var
    cell: TRect;
    bs: TTyStyleSet;
  begin
    cell := Place(ACell);
    if IsEmptyBox(cell) then Exit;
    bs := ActiveController.Model.ResolveStyle(AKey, cls, HeaderPartStates(AWindow, APart));
    if tpBackground in bs.Present then
      APainter.FillBackground(cell, bs.Background, 0);
    { 字形框、线宽 1、默认内距都同图标条的溢出按钮(RenderTo):两处是同一族按钮,
      没有单独的 token。 }
    if glyphPx > 0 then
      TyDrawGlyph(APainter, ActiveController, GlyphBox(cell), AGlyph, bs.TextColor, 1);
  end;

begin
  { 一切画进 BGRA 层,在调用方的 EndPaint 之前(之后画 GDI 会被盖掉)。几何已经镜像过
    (RTL 只镜像一次),这里只按矩形画;文字的阅读方向由画笔自己的 RTL 管。 }
  cls := TyStyleClassFor(Self, StyleClass);
  pad := TokenPxAt(TyToolWindowTabPadVar, TyToolWindowTabPadDef, APPI);
  gap := TokenPxAt(TyToolWindowHeaderGapVar, TyToolWindowHeaderGapDef, APPI);
  indPx := TokenPxAt(TyToolWindowIndicatorSizeVar, TyToolWindowIndicatorSizeDef, APPI);
  glyphPx := TokenPxAt(TyToolWindowGlyphSizeVar, TyToolWindowGlyphSizeDef, APPI);
  fill := Default(TTyFill);
  fill.Kind := tfkSolid;

  { 1. 标签行底色。 }
  S := ActiveController.Model.ResolveStyle(TyToolWindowTabRowKey, cls, [tysNormal]);
  if tpBackground in S.Present then
    APainter.FillBackground(ARow, S.Background, 0);

  { 2、3. 标签与当前页的下划线。窗口表取一次:Windows[] / IndexOfWindow 每问一次都数一遍
    Controls,逐个标签问就是 O(N²)。 }
  wins := WindowList(nil);
  active := -1;
  for i := 0 to High(wins) do
    if wins[i] = FActive then active := i;
  for i := 0 to High(AGeom.Tabs) do
  begin
    r := Place(AGeom.Tabs[i].ItemRect);
    idx := AGeom.Tabs[i].ItemIndex;
    if IsEmptyBox(r) or (idx < 0) or (idx > High(wins)) then Continue;
    S := ActiveController.Model.ResolveStyle(TyToolWindowTabKey, cls,
      HeaderTabStates(AWindow, idx, active, wins[idx]));
    if tpBackground in S.Present then
      APainter.FillBackground(r, S.Background, 0);
    { 文字框:标签左右各内缩 tab-pad。只有被截的当前页标签会真的出省略号。 }
    box := r;
    InflateRect(box, -pad, 0);
    if box.Right > box.Left then
    begin
      { 角标(spec §8.1):从文字框的阅读终点一侧切出 header-gap + 胶囊宽(LTR 切右边、RTL 切左边
        —— 几何按当前页的读写方向镜像过);切完文字框还放得下才画胶囊,放不下就只画标题。
        被截的标签先截标题(省略号),胶囊保留。胶囊按行高垂直居中,贴着标题一侧。 }
      tbox := box;
      bsz := BadgeSizeAt(wins[idx], APPI, btxt, bdot);
      if bsz.cx > 0 then
      begin
        if AWindow.IsRightToLeft then Inc(tbox.Left, gap + bsz.cx)
        else Dec(tbox.Right, gap + bsz.cx);
        if tbox.Right >= tbox.Left then
        begin
          if AWindow.IsRightToLeft then bx := tbox.Left - gap - bsz.cx
          else bx := tbox.Right + gap;
          by := r.Top + (r.Bottom - r.Top - bsz.cy) div 2;
          DrawBadgeIn(APainter, Rect(bx, by, bx + bsz.cx, by + bsz.cy), btxt, bdot);
        end
        else
          tbox := box;
      end;
      if (wins[idx].Caption <> '') and (tbox.Right > tbox.Left) then
        APainter.DrawText(tbox, wins[idx].Caption, S.FontName, ResolveFontSize(S),
          S.FontWeight, S.TextColor, taCenter, tlCenter, True);
      { 下划线贴标签底边,横向跨文字框;粗细 0 = 不画。 }
      if (idx = active) and (indPx > 0) then
      begin
        S := ActiveController.Model.ResolveStyle(TyToolWindowTabIndicatorKey, cls, [tysNormal]);
        if tpBackground in S.Present then
        begin
          gr := Rect(box.Left, r.Bottom - indPx, box.Right, r.Bottom);
          if gr.Top < r.Top then gr.Top := r.Top;
          APainter.FillBackground(gr, S.Background, 0);
        end;
      end;
    end;
  end;

  { 4. 溢出按钮(有东西收起时才有)。它弹的是下拉菜单,用下拉的空心 V(spec §7.3),
    不用步进按钮的实心三角。 }
  PaintButton(AGeom.Overflow, TyToolWindowOverflowKey, twbpOverflow, tgChevronDown);

  { 5. 分隔线:槽中间一条线,纵向跟按钮带同高。 }
  r := Place(AGeom.Separator);
  line := SeparatorLinePx(APPI);
  if not IsEmptyBox(r) and (line > 0) then
  begin
    S := ActiveController.Model.ResolveStyle(TyToolWindowSeparatorKey, cls, [tysNormal]);
    if line > r.Right - r.Left then line := r.Right - r.Left;
    gr := Place(AGeom.Maximize);
    if IsEmptyBox(gr) then gr := Place(AGeom.Collapse);
    if IsEmptyBox(gr) then
    begin
      bandTop := r.Top;
      bandBottom := r.Bottom;
    end
    else
    begin
      bandTop := gr.Top;
      bandBottom := gr.Bottom;
    end;
    fill.Color := S.BorderColor;
    i := r.Left + (r.Right - r.Left - line) div 2;
    APainter.FillBackground(Rect(i, bandTop, i + line, bandBottom), fill, 0);
  end;

  { 6. 最大化、收起。收起用「隐藏」的横线(tgMinimize):tgClose 会被读成「关掉这个窗口」。 }
  if FMaximized then
    PaintButton(AGeom.Maximize, TyToolWindowButtonKey, twbpMaximize, tgRestore)
  else
    PaintButton(AGeom.Maximize, TyToolWindowButtonKey, twbpMaximize, tgMaximize);
  PaintButton(AGeom.Collapse, TyToolWindowButtonKey, twbpCollapse, tgMinimize);

  { 7. 拖动调顺序的插入线(spec §9.8:画在标签行里 —— 当前页,或让出时的栏)。空隙 k 在窗口 k
    那个标签的阅读起点一侧,最后一个之后在最后一个标签的阅读终点一侧 —— 几何已经镜像过,RTL 时
    起点是右沿。空操作不画。纵向占整个标题行,横向钳在标签区里。捕获者要是标签行此刻的宿主。 }
  if (FGesture <> nil) and (FGesture.State = twgsDragging) and (FGesture.Capturer <> nil)
     and (FGesture.Capturer = TabRowHostControl)
     and (FDropSlot >= 0) and not IsNoOpSlot(FDropSlot) then
  begin
    line := -1;
    for i := 0 to High(AGeom.Tabs) do
      if AGeom.Tabs[i].ItemIndex = FDropSlot then
      begin
        if AWindow.IsRightToLeft then line := AGeom.Tabs[i].ItemRect.Right
        else line := AGeom.Tabs[i].ItemRect.Left;
      end;
    if line < 0 then
      for i := 0 to High(AGeom.Tabs) do
        if AGeom.Tabs[i].ItemIndex = FDropSlot - 1 then
        begin
          if AWindow.IsRightToLeft then line := AGeom.Tabs[i].ItemRect.Left
          else line := AGeom.Tabs[i].ItemRect.Right;
        end;
    dropPx := TokenPxAt(TyToolWindowDropSizeVar, TyToolWindowDropSizeDef, APPI);
    S := ActiveController.Model.ResolveStyle(TyToolWindowDropIndicatorKey, cls, [tysNormal]);
    if (line >= 0) and (dropPx > 0) and (tpBackground in S.Present) then
    begin
      gr := Rect(line - dropPx div 2, 0, line - dropPx div 2 + dropPx, ARow.Bottom - ARow.Top);
      if gr.Left < AGeom.TabArea.Left then Types.OffsetRect(gr, AGeom.TabArea.Left - gr.Left, 0);
      if gr.Right > AGeom.TabArea.Right then Types.OffsetRect(gr, AGeom.TabArea.Right - gr.Right, 0);
      APainter.FillBackground(Place(gr), S.Background, 0);
    end;
  end;
end;

function TTyCustomToolWindowBar.HeaderZoneAt(AWindow: TTyCustomToolWindow; X, Y: Integer;
  out AIndex: Integer; out ARect: TRect): TTyToolWindowZone;
var
  g: TTyToolWindowHeaderGeom;
  h: TTyToolWindowTabRowHost;
  ox, oy, i: Integer;
begin
  AIndex := -1;
  ARect := Rect(0, 0, 0, 0);
  Result := twzNone;
  ox := 0;
  oy := 0;
  if AWindow = nil then
  begin
    { 栏坐标:标签行在谁身上一处答(TabRowHost)。栏当宿主时行就在栏客户区里(Row);当前页
      当宿主时,页是栏的直接子控件,它的 Left / Top 就是它在栏客户区里的位置,行在它客户区原点。 }
    h := TabRowHost;
    if h.Host = nil then Exit;
    if h.Host = TWinControl(Self) then
    begin
      ox := h.Row.Left;
      oy := h.Row.Top;
    end
    else
    begin
      ox := FActive.Left + h.Row.Left;
      oy := FActive.Top + h.Row.Top;
    end;
    g := h.Geom;
  end
  else
  begin
    if AWindow.HeaderMode <> twhBottom then Exit;
    { 页转来的:标题行从客户区原点开始,行内坐标就是窗口客户区坐标。 }
    g := AWindow.HeaderGeomAt(Rect(0, 0, AWindow.ClientWidth, AWindow.ClientHeight),
      AWindow.Font.PixelsPerInch);
  end;
  Result := TyToolWindowZoneAt(g, X - ox, Y - oy, AIndex);
  case Result of
    twzTab:
      for i := 0 to High(g.Tabs) do
        if g.Tabs[i].ItemIndex = AIndex then ARect := g.Tabs[i].ItemRect;
    twzOverflow: ARect := g.Overflow;
    twzSeparator: ARect := g.Separator;
    twzMaximize: ARect := g.Maximize;
    twzCollapse: ARect := g.Collapse;
  end;
  if Result <> twzNone then Types.OffsetRect(ARect, ox, oy);
end;

procedure TTyCustomToolWindowBar.RowDown(const AHost: TTyToolWindowTabRowHost; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  zone: TTyToolWindowZone;
  idx: Integer;
begin
  { 禁用的栏不武装(同图标条:LCL 不给禁用控件发鼠标消息,这里是给直接转发过来的那一路补同一道
    闸);设计期标签行不接手势(spec §3.6)。 }
  if (AHost.Host = nil) or not IsEnabled or (csDesigning in ComponentState) then Exit;
  { 右键、中键从不武装、从不切换(spec §6.8 / §9.2)。 }
  if Button <> mbLeft then Exit;
  { 每次按下新建一条记录:上一次丢了松开留下的一切在这里收干净。 }
  ResetGesture(twgeDiscard);
  { 几何是行内坐标;引擎拿宿主坐标(阈值原点、捕获者都是宿主)。 }
  zone := TyToolWindowZoneAt(AHost.Geom, X - AHost.Row.Left, Y - AHost.Row.Top, idx);
  case zone of
    { 按下只武装,什么都不激活(spec §9.3「为什么松开才切」)。标签是拖动把手 —— 禁用窗口的
      标签不是,也不武装(点了不切,spec §3.7)。 }
    twzTab:
      begin
        if not WindowClickable(Windows[idx]) then Exit;
        FGesture.Press(twbpItem, Windows[idx], True, AHost.Host, X, Y, Shift);
      end;
    twzOverflow, twzMaximize, twzCollapse:
      FGesture.Press(PartOfZone(zone), nil, False, AHost.Host, X, Y, Shift);
  else
    Exit;                  { 分隔线、空白:不武装 }
  end;
  InvalidateHeader;        { 按下态 }
end;

procedure TTyCustomToolWindowBar.RowMove(const AHost: TTyToolWindowTabRowHost; Shift: TShiftState;
  X, Y: Integer);
var
  zone: TTyToolWindowZone;
  idx: Integer;
begin
  if (AHost.Host = nil) or (csDesigning in ComponentState) then Exit;
  case FGesture.Move(Shift, X, Y) of
    twgmHover:
      begin
        zone := TyToolWindowZoneAt(AHost.Geom, X - AHost.Row.Left, Y - AHost.Row.Top, idx);
        { 禁用窗口的标签不接悬停(spec §3.7)。 }
        if (zone = twzTab) and not WindowClickable(Windows[idx]) then zone := twzNone;
        SetHeaderHover(PartOfZone(zone), idx);
      end;
    twgmDragStart:
      begin
        SetHeaderHover(twbpNone, -1);
        RowDragIn(AHost, X, Y);
      end;
    twgmDrag:
      RowDragIn(AHost, X, Y);
  end;
end;

procedure TTyCustomToolWindowBar.RowUp(const AHost: TTyToolWindowTabRowHost; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
var
  zone: TTyToolWindowZone;
  part: TTyToolWindowBarPart;
  w: TTyCustomToolWindow;
  rel: TTyToolWindowGestureRelease;
  idx, slot: Integer;
  commit: Boolean;
begin
  if (AHost.Host = nil) or (Button <> mbLeft) then Exit;
  { 拖动:在松开点重算落点 —— 要看手势窗口,所以在引擎收尾之前算(spec §9.2)。标签行外
    松开 = 取消:不调顺序,也不切页。 }
  slot := -1;
  commit := False;
  if FGesture.State = twgsDragging then
  begin
    slot := RowDropSlot(AHost, X, Y);
    commit := (slot >= 0) and (IndexOfWindow(FGesture.Window) >= 0) and not IsNoOpSlot(slot);
  end;
  zone := TyToolWindowZoneAt(AHost.Geom, X - AHost.Row.Left, Y - AHost.Row.Top, idx);
  part := PartOfZone(zone);
  if part = twbpItem then w := Windows[idx] else w := nil;
  { 引擎判完、收尾,答案拷在局部;动作放最后一句 —— 它可能把捕获者(当前页)自己藏起来
    (spec §9.2),之后不再碰宿主。 }
  rel := FGesture.Release(part, w);
  if AHost.Host = TabRowHostControl then
  begin
    { 禁用窗口的标签不接悬停(spec §3.7)。 }
    if (part = twbpItem) and not WindowClickable(w) then SetHeaderHover(twbpNone, -1)
    else SetHeaderHover(part, idx);
  end;
  if rel.Kind = twrDrop then
  begin
    { 只在本栏内调顺序(spec §9.1);不激活、不展开。FinalIndex := slot - Ord(slot > src)。 }
    if commit then
    begin
      if slot > IndexOfWindow(rel.Window) then Dec(slot);
      ReorderWindow(rel.Window, slot);
    end;
    Exit;
  end;
  if rel.Kind <> twrClick then Exit;
  case rel.Part of
    { 点当前页的标签什么都不做(spec §9.3 底栏标签);非当前页 → 切过去。 }
    twbpItem:
      if rel.Window <> FActive then ActivateWindow(rel.Window);
    twbpMaximize:
      Maximized := not FMaximized;
    twbpOverflow:
      ShowOverflowMenu;
    { 会把捕获者(当前页)自己藏起来:最后一句(spec §9.2)。 }
    twbpCollapse:
      Collapsed := True;
  end;
end;

function TTyCustomToolWindowBar.RowHintAt(const AHost: TTyToolWindowTabRowHost; X, Y: Integer;
  out AText: string; out ARect: TRect): Boolean;
var
  idx, i: Integer;
begin
  AText := '';
  ARect := Rect(0, 0, 0, 0);
  Result := AHost.Host <> nil;
  if not Result then Exit;
  case TyToolWindowZoneAt(AHost.Geom, X - AHost.Row.Left, Y - AHost.Row.Top, idx) of
    { 标签:StripHint,空的时候 Caption,**不用 Hint**(同图标条,见 StripHintText)。
      禁用窗口的标签提示照常(spec §3.7)。 }
    twzTab:
      begin
        AText := StripHintText(Windows[idx]);
        for i := 0 to High(AHost.Geom.Tabs) do
          if AHost.Geom.Tabs[i].ItemIndex = idx then ARect := AHost.Geom.Tabs[i].ItemRect;
      end;
    twzOverflow:
      begin
        AText := rsTyToolWindowMore;
        ARect := AHost.Geom.Overflow;
      end;
    twzMaximize:
      begin
        if FMaximized then AText := rsTyToolWindowRestore
        else AText := rsTyToolWindowMaximize;
        ARect := AHost.Geom.Maximize;
      end;
    twzCollapse:
      begin
        AText := rsTyToolWindowCollapse;
        ARect := AHost.Geom.Collapse;
      end;
  else
    Result := False;           { 分隔线、空白:不给提示 }
  end;
  if Result then Types.OffsetRect(ARect, AHost.Row.Left, AHost.Row.Top)
  else ARect := Rect(0, 0, 0, 0);
end;

procedure TTyCustomToolWindowBar.HeaderMouseDown(AWindow: TTyCustomToolWindow; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  { 只认当前页转来的(旧页迟到的消息不算)。其余的闸在 RowDown。 }
  if (AWindow = nil) or (AWindow <> FActive) then Exit;
  RowDown(PageRowHost(AWindow, AWindow.HeaderGeomAt(Rect(0, 0, AWindow.ClientWidth,
    AWindow.ClientHeight), AWindow.Font.PixelsPerInch)), Button, Shift, X, Y);
end;

procedure TTyCustomToolWindowBar.HeaderMoveIn(AWindow: TTyCustomToolWindow;
  const AGeom: TTyToolWindowHeaderGeom; Shift: TShiftState; X, Y: Integer);
begin
  { spec §7.1:旧页迟到的消息不许清新页的悬停。设计期不做悬停(RowMove)。 }
  if (AWindow = nil) or (AWindow <> FActive) then Exit;
  RowMove(PageRowHost(AWindow, AGeom), Shift, X, Y);
end;

procedure TTyCustomToolWindowBar.HeaderMouseUp(AWindow: TTyCustomToolWindow; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  if AWindow = nil then Exit;
  { 最后一句(RowUp 可能把本页藏起来)。 }
  RowUp(PageRowHost(AWindow, AWindow.HeaderGeomAt(Rect(0, 0, AWindow.ClientWidth,
    AWindow.ClientHeight), AWindow.Font.PixelsPerInch)), Button, Shift, X, Y);
end;

procedure TTyCustomToolWindowBar.HeaderMouseLeave(AWindow: TTyCustomToolWindow);
begin
  { 只清悬停,从不解除武装(spec §9.2:捕获期间 Win32 的 WM_MOUSELEAVE 可能在捕获者身上触发)。
    旧页迟到的离开不算(spec §7.1)。 }
  if (AWindow <> nil) and (AWindow = FActive) then SetHeaderHover(twbpNone, -1);
end;

procedure TTyCustomToolWindowBar.HeaderCancelMode(AWindow: TTyCustomToolWindow);
begin
  { 捕获者是这一页、它收到了 LM_CANCELMODE(spec §9.7):ShowModal、异常对话框之类。 }
  if (AWindow <> nil) and (FGesture.Capturer = AWindow) then ResetGesture(twgeCancel);
end;

function TTyCustomToolWindowBar.HeaderHint(AWindow: TTyCustomToolWindow; X, Y: Integer; out AText: string;
  out ARect: TRect): Boolean;
var
  h: TTyToolWindowTabRowHost;
begin
  if AWindow <> nil then
    Exit(RowHintAt(PageRowHost(AWindow, AWindow.HeaderGeomAt(Rect(0, 0, AWindow.ClientWidth,
      AWindow.ClientHeight), AWindow.Font.PixelsPerInch)), X, Y, AText, ARect));
  { nil = 栏坐标:标签行在谁身上问 TabRowHost;页当宿主时把行挪到页在栏里的位置。 }
  h := TabRowHost;
  if (h.Host <> nil) and (h.Host <> TWinControl(Self)) then
    Types.OffsetRect(h.Row, FActive.Left, FActive.Top);
  Result := RowHintAt(h, X, Y, AText, ARect);
end;

procedure TTyCustomToolWindowBar.HeaderContextPopup(AWindow: TTyCustomToolWindow; X, Y: Integer);
var
  idx: Integer;
  r: TRect;
  pt: TPoint;
  handled: Boolean;
  menu: TPopupMenu;
begin
  { 只在标签上(溢出、分隔线、按钮、空白上的右键窗口那边已经吞了)。 }
  if (AWindow = nil) or (HeaderZoneAt(AWindow, X, Y, idx, r) <> twzTab) then Exit;
  { 换成栏坐标,走栏自己的 DoContextPopup —— 它按栏坐标的 PartAt / WindowAtPos 认得标签,
    设 ContextWindow、不挡菜单、按栏坐标发 OnContextPopup(spec §6.8 的同一条路)。 }
  pt := Point(X + AWindow.Left, Y + AWindow.Top);
  handled := False;
  DoContextPopup(pt, handled);
  if handled then Exit;
  { DoContextPopup 只发事件;弹菜单本来是 LCL 的 WM_CONTEXTMENU 在它之后做的,这里没有那一层,
    自己补。只在当前页有句柄时弹。 }
  menu := GetPopupMenu;
  if (menu = nil) or not menu.AutoPopup or not AWindow.HandleAllocated then Exit;
  menu.PopupComponent := Self;
  pt := AWindow.ClientToScreen(Point(X, Y));
  menu.PopUp(pt.X, pt.Y);
end;

{ --- 图标条手势 ---------------------------------------------------------------- }

function TTyCustomToolWindowBar.PartAt(X, Y: Integer; out AIndex: Integer): TTyToolWindowBarPart;
var
  L: TTyToolWindowBarLayout;
  pt: TPoint;
  r: TRect;
  i: Integer;
begin
  AIndex := -1;
  Result := twbpNone;
  { 底栏:标签行在当前页里、或者当前页被禁用时让到了栏里(spec §3.7),栏坐标按 TabRowHost
    换算(HeaderZoneAt(nil, …))。平时栏自己收不到标签行上的按下(当前页盖着),这一段服务栏坐标
    的查询:WindowAtPos、右键、设计期命中;让出的那一行是栏自己的像素,按下也经这里认部件。 }
  if (FPlacement = twpBottom) and (FActive <> nil) then
  begin
    Result := PartOfZone(HeaderZoneAt(nil, X, Y, i, r));
    if Result <> twbpNone then
    begin
      if Result = twbpItem then AIndex := i;
      Exit;
    end;
  end;
  L := BarLayout;
  pt := Point(X, Y);
  for i := 0 to High(L.Slots) do
    if PtInRect(L.Slots[i].ItemRect, pt) then
    begin
      AIndex := L.Slots[i].ItemIndex;
      Exit(twbpItem);
    end;
  if PtInRect(L.Overflow, pt) then Exit(twbpOverflow);
  { 最大化期间边缘区不起作用(spec §6.4):不命中、不借调整光标;那条贴编辑区的线照画。 }
  if PtInRect(L.Edge, pt) and not FMaximized then Exit(twbpEdge);
end;

function TTyCustomToolWindowBar.WindowAtPos(X, Y: Integer): TTyCustomToolWindow;
var
  idx: Integer;
begin
  if PartAt(X, Y, idx) = twbpItem then Result := Windows[idx]
  else Result := nil;
end;

function TTyCustomToolWindowBar.StripHintAt(X, Y: Integer; out AText: string;
  out ARect: TRect): Boolean;
var
  idx: Integer;
begin
  AText := '';
  ARect := Rect(0, 0, 0, 0);
  Result := PartAt(X, Y, idx) = twbpItem;
  if not Result then Exit;
  AText := StripHintText(Windows[idx]);
  ARect := StripItemRect(idx);
end;

function TTyCustomToolWindowBar.OverflowWindows: TTyToolWindowPlan;
var
  L: TTyToolWindowBarLayout;
  h: TTyToolWindowTabRowHost;
  shown: array of Boolean;
  i, n: Integer;
begin
  Result := nil;
  n := WindowCount;
  if n = 0 then Exit;
  { 底栏:收进去的是当前页此刻标签行几何里的 Hidden(没有当前页、没有标签行时空)。标签行在
    谁身上问 TabRowHost:让出之后页里行高 0,问页就一个都放不下了。 }
  if FPlacement = twpBottom then
  begin
    h := TabRowHost;
    if h.Host <> nil then Result := Copy(h.Geom.Hidden);
    Exit;
  end;
  L := BarLayout;
  shown := nil;
  SetLength(shown, n);
  for i := 0 to High(L.Slots) do
    if (L.Slots[i].ItemIndex >= 0) and (L.Slots[i].ItemIndex < n) then
      shown[L.Slots[i].ItemIndex] := True;
  for i := 0 to n - 1 do
    if not shown[i] then
    begin
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := i;
    end;
end;

function TTyCustomToolWindowBar.GestureStateForTest: TTyToolWindowGestureState;
begin
  Result := FGesture.State;
end;

function TTyCustomToolWindowBar.HasCaptureTimerForTest: Boolean;
begin
  Result := FGesture.HasCaptureTimer;
end;

function TTyCustomToolWindowBar.AllowedCacheCountForTest: Integer;
begin
  Result := FGesture.AllowedCount;
end;

function TTyCustomToolWindowBar.WatchedSiblingCountForTest: Integer;
begin
  Result := Length(FWatched);
end;

function TTyCustomToolWindowBar.IsEdgeDraggingForTest: Boolean;
begin
  Result := EdgeResizing;
end;

function TTyCustomToolWindowBar.EdgeResizing: Boolean;
begin
  Result := (FGesture <> nil) and FGesture.Resizing;
end;

function TTyCustomToolWindowBar.EdgeSnapped: Boolean;
begin
  Result := (FGesture <> nil) and FGesture.Snapped;
end;

function TTyCustomToolWindowBar.TickNow: QWord;
begin
  Result := GetTickCount64;
end;

function TTyCustomToolWindowBar.PointerInClient(out APoint: TPoint): Boolean;
begin
  Result := HandleAllocated;
  if Result then APoint := ScreenToClient(Mouse.CursorPos)
  else APoint := Point(-1, -1);
end;

procedure TTyCustomToolWindowBar.ResetGesture(AReason: TTyToolWindowGestureEnd);
begin
  if FGesture <> nil then FGesture.Reset(AReason);
end;

procedure TTyCustomToolWindowBar.ResizeEnded(AReason: TTyToolWindowGestureEnd; AWasSnapped: Boolean);
begin
  { 拉宽:松开保留此刻的尺寸;其他收尾回到起点(spec §6.3)。析构中引擎不调这里 —— 回到
    起点要 Relayout,而栏已经拆了一半。 }
  if AReason <> twgeRelease then
  begin
    if FExpandedSize <> FGesture.StartSize then
      ExpandedSize := FGesture.StartSize          { 自己 Relayout }
    else if AWasSnapped then
      Relayout;                                   { 吸附排布还回「展开」 }
  end;
  Invalidate;
  { 吸附着收尾:引擎已经清了吸附标志,让出行按此刻的样子对一遍(松开时接着 Collapsed := True,
    那一句再对一遍)。 }
  if AWasSnapped then TabRowHostMayHaveChanged;
end;

procedure TTyCustomToolWindowBar.GestureCleared(ATabRow: Boolean);
begin
  if (FStripPressed <> -1) or FOverflowPressed then
  begin
    FStripPressed := -1;
    FOverflowPressed := False;
    if not (csDestroying in ComponentState) then Invalidate;
  end;
  { 标签行的按下态是从引擎读的(HeaderPressed):收尾之后当前页得重画掉它。 }
  if ATabRow then InvalidateHeader;
end;

procedure TTyCustomToolWindowBar.SetStripHover(AIndex: Integer; AOverflow: Boolean);
begin
  { 只管图标和溢出按钮。边缘区的悬停另由 SetEdgeHover 管,调用方显式地给 —— 在这里顺手清
    的话,在边缘区里每移动一下都是「清掉、再设回去」,光标和整条栏各白写一遍。 }
  if (AIndex = FStripHover) and (AOverflow = FOverflowHover) then Exit;
  FStripHover := AIndex;
  FOverflowHover := AOverflow;
  if not (csDestroying in ComponentState) then Invalidate;
end;

procedure TTyCustomToolWindowBar.UpdateHoverAt(X, Y: Integer);
var
  part: TTyToolWindowBarPart;
  idx: Integer;
begin
  { 设计期不做悬停:设计期控件收不到 enter / leave(spec §7.4)。 }
  if csDesigning in ComponentState then Exit;
  part := PartAt(X, Y, idx);
  { 禁用窗口的图标 / 标签不接悬停(spec §3.7);侧栏的当前页例外 —— 它照样点一下收起。 }
  if (part = twbpItem) and not WindowClickable(Windows[idx])
     and ((FPlacement = twpBottom) or (Windows[idx] <> FActive)) then
  begin
    part := twbpNone;
    idx := -1;
  end;
  if FPlacement = twpBottom then
  begin
    { 底栏的标签、溢出、按钮在当前页的标签行里,悬停记在标签行那一份上。 }
    if part in [twbpItem, twbpOverflow, twbpMaximize, twbpCollapse] then
      SetHeaderHover(part, idx)
    else
      SetHeaderHover(twbpNone, -1);
    SetEdgeHover(part = twbpEdge);
    Exit;
  end;
  if part <> twbpItem then idx := -1;
  SetStripHover(idx, part = twbpOverflow);
  SetEdgeHover(part = twbpEdge);
end;

procedure TTyCustomToolWindowBar.RecheckHover;
var
  p: TPoint;
begin
  if [csDesigning, csDestroying] * ComponentState <> [] then Exit;
  { 底栏同样经这里:栏坐标的指针经当前页换算成标签行的部件(PartAt → HeaderZoneAt(nil, …)),
    不在当前页的标签行里就清掉。 }
  if PointerInClient(p) then UpdateHoverAt(p.X, p.Y)
  else
  begin
    SetStripHover(-1, False);
    SetHeaderHover(twbpNone, -1);
    if not EdgeResizing then SetEdgeHover(False);
  end;
end;

procedure TTyCustomToolWindowBar.StripClick(AWindow: TTyCustomToolWindow);
var
  now: QWord;
begin
  if IndexOfWindow(AWindow) < 0 then Exit;
  { 禁用窗口点了不切(spec §3.7);当前页例外 —— 收起 / 展开是栏的动作。按下那一道闸已经挡过
    「按下时就禁用着」的,这里还有一条它挡不住:按在禁用的**当前页**上(合法:点它收起),松开之前
    代码把当前页换走了 —— 手势照样武装在它身上,松开在它的图标上就是一次点击,而它此刻已经不是
    当前页,不挡就切回一个禁用窗口。切页不取消条上的手势(换当前页不是作废理由,点别的图标照常),
    所以只能在这里挡。「按下之后才被禁用」那一条 WindowEnabledChanged 已经取消了手势。 }
  if not WindowClickable(AWindow) and (AWindow <> FActive) then Exit;
  { 防抖:距离这个窗口上一次真正执行的点击不到 300 ms 就忽略 —— 慢速双击(系统默认
    500 ms 内的第二次按下才标 ssDouble,而那条路有多击标记挡着)之外,GTK3 不下发三击
    消息,三击靠这里(spec §9.3)。被忽略的那一下**不**刷新时间戳:窗口从上一次真正
    执行的那一下算起,不是从上一次按下算起。 }
  now := TickNow;
  if (AWindow.FLastStripClick <> 0) and (now >= AWindow.FLastStripClick)
     and (now - AWindow.FLastStripClick < TyToolWindowClickGuardMs) then Exit;
  AWindow.FLastStripClick := now;
  if AWindow <> FActive then
  begin
    { 收起着时 ActivateWindow 只换 FActive,展开那一步把它显示出来。 }
    ActivateWindow(AWindow);
    Collapsed := False;
  end
  else
    Collapsed := not FCollapsed;
end;

procedure TTyCustomToolWindowBar.OverflowItemClick(Sender: TObject);
var
  w: TTyCustomToolWindow;
begin
  { Tag 里是窗口引用;只拿来跟活着的窗口列表比指针,不解引用 —— 菜单开着的时候它可能
    已经走了。菜单项不受防抖限制(spec §6.5)。 }
  w := TTyCustomToolWindow(PtrUInt(TMenuItem(Sender).Tag));
  if IndexOfWindow(w) < 0 then Exit;
  { 菜单开着的时候它被禁用了(菜单项在建菜单那一刻就灰了,spec §3.7)。 }
  if not w.Enabled then Exit;
  ActivateWindow(w);
  Collapsed := False;
end;

procedure TTyCustomToolWindowBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  part: TTyToolWindowBarPart;
  idx: Integer;
  inStrip: Boolean;
  w: TTyCustomToolWindow;
begin
  { 每次按下都新建一条记录。上一次手势丢了松开留下的一切 —— 临时光标、处理器、计时器、
    拉到一半的边 —— 在这里一次收干净,而且在继承之前:用户的 OnMouseDown 看到的是
    干净的状态,它抛异常也不会把残局留到下一次。 }
  if Button = mbLeft then ResetGesture(twgeDiscard);
  inherited MouseDown(Button, Shift, X, Y);
  { 右键、中键从不武装、从不切换(spec §6.8 / §9.2)。 }
  if Button <> mbLeft then Exit;
  part := PartAt(X, Y, idx);
  { 吞 Click / DblClick:按在部件上;按在让出来的标签行里(空白也算,同页那一路);或者按在禁用的
    当前页的边界里 —— Win32 上点禁用页的正文,按下落到栏(spec §3.7 根因第 1 条;GTK / Cocoa 上
    这一下直接丢)。栏的 OnMouseDown / OnMouseUp 挡不住:它们在继承里先发。 }
  FGesture.SwallowClick := (part <> twbpNone) or SwallowPress(Point(X, Y));
  { 兜底:DragMode = dmAutomatic 时 LCL 在这之前就调过 BeginAutoDrag(见 WndProc)。那边按
    记下的按下位置挡;万一没挡住(程序里直接调的、按下消息没带坐标的),这里撤掉。 }
  inStrip := PtInRect(BarLayout.Strip, Point(X, Y));
  if (inStrip or (part <> twbpNone)) and Dragging then EndDrag(False);
  if csDesigning in ComponentState then
  begin
    { 设计期只有「点图标切页」,切换写在 CM_DESIGNHITTEST 的松开分支里;收起、调顺序、
      拉宽一律不做。捕获好让拖出控件的移动也到这里(设计器递消息前放掉了捕获)。 }
    if part = twbpItem then FGesture.ArmDesign(Windows[idx]) else FGesture.ArmDesign(nil);
    if FGesture.DesignArmed and HandleAllocated then MouseCapture := True;
    Exit;
  end;
  { 底栏:标签、溢出、按钮在标签行里。平时标签行长在当前页上、由它收了转过来,栏自己收到的
    (当前页没有句柄、程序里直接调的)只吞 —— 不许走图标条「点当前页就收起」的语义(spec §9.3
    底栏标签)。当前页被禁用时标签行让到了栏里(spec §3.7):那就是栏自己的像素,走同一套标签行
    手势,捕获者是栏。 }
  if (FPlacement = twpBottom) and (part in [twbpItem, twbpOverflow, twbpMaximize, twbpCollapse]) then
  begin
    if HostsTabRow then RowDown(TabRowHost, Button, Shift, X, Y);
    Exit;
  end;
  if part in [twbpItem, twbpOverflow] then
  begin
    { 按下只武装,什么都不激活(spec §9.3「为什么松开才切」)。多击的按下照常武装
      (之后可以拖),但阈值以内松开永远不算点击(spec §9.2);溢出按钮不是拖动把手。 }
    if part = twbpItem then
    begin
      w := Windows[idx];
      { 禁用窗口的图标(spec §3.7):只吞(SwallowClick 上面已经置了),不武装。禁用的当前页
        例外:照样点一下收起 / 展开,但不是拖动把手。 }
      if not WindowClickable(w) and (w <> FActive) then Exit;
      FGesture.Press(part, w, WindowClickable(w), Self, X, Y, Shift);
      FStripPressed := idx;
    end
    else
    begin
      FGesture.Press(part, nil, False, Self, X, Y, Shift);
      FOverflowPressed := True;
    end;
    Invalidate;
  end
  else if part = twbpEdge then
    BeginEdgeDrag(X, Y);
end;

procedure TTyCustomToolWindowBar.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  { spec §9.7:任何注册栏看到没有 ssLeft 的移动,别的栏上正在拖的就丢了松开 —— 取消。 }
  if (FManager <> nil) and (FManager.FDragSource <> nil) and (FManager.FDragSource <> Self)
     and not (ssLeft in Shift) then
    FManager.CancelDrag;
  inherited MouseMove(Shift, X, Y);
  { 让出来的标签行上的手势捕获在栏上(spec §3.7):阈值、拖动、落点都走标签行那一套。不带键的
    悬停照旧走下面的 UpdateHoverAt(PartAt 已经按 TabRowHost 换算)。 }
  if (FPlacement = twpBottom) and (FGesture.Capturer = Self)
     and (FGesture.Part in [twbpItem, twbpOverflow, twbpMaximize, twbpCollapse]) then
  begin
    RowMove(TabRowHost, Shift, X, Y);
    Exit;
  end;
  { 状态转移全在引擎里(丢了松开的取消、阈值、取消后等松开);这里只按答案做栏的那一半。 }
  case FGesture.Move(Shift, X, Y) of
    twgmResize: EdgeDragTo(X, Y);
    twgmDragStart:
      begin
        SetStripHover(-1, False);
        DragTo(X, Y);
      end;
    twgmDrag: DragTo(X, Y);
    twgmHover: UpdateHoverAt(X, Y);
  end;
end;

procedure TTyCustomToolWindowBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  part: TTyToolWindowBarPart;
  w: TTyCustomToolWindow;
  rel: TTyToolWindowGestureRelease;
  commit: Boolean;
  idx, slot: Integer;
  tgt, cross: TTyCustomToolWindowBar;
begin
  { 手势在继承之后收尾(spec §9.2);用户的 OnMouseUp 抛异常的话,残局在这里收掉再往外抛。 }
  try
    inherited MouseUp(Button, Shift, X, Y);
  except
    if Button = mbLeft then ResetGesture(twgeCancel);
    raise;
  end;
  if Button <> mbLeft then Exit;
  if csDesigning in ComponentState then
  begin
    { 正常情况下松开那一拍 CM_DESIGNHITTEST 已经答了 0,设计器不会再调这里;万一来了,
      只解除武装,不切页。 }
    FGesture.DisarmDesign;
    Exit;
  end;
  { 让出来的标签行上的手势(spec §3.7):同一套松开,最后一句(可能收起栏)。 }
  if (FPlacement = twpBottom) and (FGesture.Capturer = Self)
     and (FGesture.Part in [twbpItem, twbpOverflow, twbpMaximize, twbpCollapse]) then
  begin
    RowUp(TabRowHost, Button, Shift, X, Y);
    Exit;
  end;
  { 拖动:在松开点重算落点 —— 要看手势窗口,所以在引擎收尾之前算(spec §9.2)。有 manager 的
    侧栏问 manager:落点可能在另一侧栏上(spec §9.4)。 }
  slot := -1;
  commit := False;
  cross := nil;
  if FGesture.State = twgsDragging then
  begin
    if (FManager <> nil) and (FPlacement <> twpBottom) then
    begin
      tgt := FManager.DropTargetAt(Self, ClientToScreen(Point(X, Y)), slot);
      if tgt <> Self then
      begin
        cross := tgt;               { nil = 没有目标:取消 }
        if tgt = nil then slot := -1;
      end;
    end
    else
      slot := DropSlotAt(X, Y);
    if cross = nil then
      commit := (slot >= 0) and (IndexOfWindow(FGesture.Window) >= 0) and not IsNoOpSlot(slot);
  end;
  part := PartAt(X, Y, idx);
  if part = twbpItem then w := Windows[idx] else w := nil;
  { 引擎判完、收尾,答案拷在局部:动作放最后,它引起的事件里就算重新按下也是一条新记录。 }
  rel := FGesture.Release(part, w);
  case rel.Kind of
    twrResize:
      begin
        { 松手时处在吸附排布才写 Collapsed;ExpandedSize 一直停在起点(spec §6.3)。
          收尾先把排布还给「展开」那一支,Collapsed 的 Relayout 再按收起推。 }
        if rel.Snapped then Collapsed := True;
        UpdateHoverAt(X, Y);
      end;
    twrDrop:
      begin
        UpdateHoverAt(X, Y);
        if commit then
        begin
          { FinalIndex := slot - Ord(slot > src):移走自己之后,后面的空隙往前挪一格。 }
          if slot > IndexOfWindow(rel.Window) then Dec(slot);
          ReorderWindow(rel.Window, slot);
        end
        else if (cross <> nil) and (FManager <> nil) then
          { 另一侧栏:最后一句(spec §9.2),之后不再碰 Self。 }
          FManager.MoveFromDrop(rel.Window, cross, slot);
      end;
    twrClick:
      begin
        UpdateHoverAt(X, Y);
        { Armed、落在同一个部件(同一个窗口的图标)上、没有多击标记 → 点击。 }
        case rel.Part of
          twbpItem: StripClick(rel.Window);
          twbpOverflow: ShowOverflowMenu;
        end;
      end;
  else
    UpdateHoverAt(X, Y);
  end;
end;

procedure TTyCustomToolWindowBar.MouseLeave;
begin
  inherited MouseLeave;
  { 只清悬停,**不**解除武装:捕获期间 Win32 的 WM_MOUSELEAVE 可能在捕获者身上触发一次
    (spec §9.2)。拉宽中边缘区的悬停态(和借来的调整光标)留着。 }
  SetStripHover(-1, False);
  if not EdgeResizing then SetEdgeHover(False);
  { 让出来的标签行(spec §3.7):悬停记在标签行那一份上,一起清。 }
  if HostsTabRow then SetHeaderHover(twbpNone, -1);
  { 设计期例外:设计器的捕获已经丢了,这一次的松开不会再来(见引擎的 DesignArmed)。 }
  if csDesigning in ComponentState then
    FGesture.DisarmDesign;
end;

procedure TTyCustomToolWindowBar.Click;
begin
  { 栏 published 了 OnClick,LCL 在 MouseUp 之前调它:按在图标条 / 边缘区上的那一下不是
    「点了栏」。 }
  if FGesture.SwallowClick then Exit;
  inherited Click;
end;

procedure TTyCustomToolWindowBar.DblClick;
begin
  if FGesture.SwallowClick then Exit;
  inherited DblClick;
end;

procedure TTyCustomToolWindowBar.WndProc(var TheMessage: TLMessage);
begin
  if (TheMessage.Msg = LM_LBUTTONDOWN) or (TheMessage.Msg = LM_LBUTTONDBLCLK) then
  begin
    FAutoDragPos := Point(TLMMouse(TheMessage).XPos, TLMMouse(TheMessage).YPos);
    FAutoDragPosValid := True;
    try
      inherited WndProc(TheMessage);
    finally
      FAutoDragPosValid := False;
    end;
  end
  else
    inherited WndProc(TheMessage);
end;

procedure TTyCustomToolWindowBar.CaptureChanged;
begin
  if (csDesigning in ComponentState) and FGesture.DesignArmed and (GetCaptureControl <> Self) then
    FGesture.DisarmDesign;
  inherited CaptureChanged;
end;

procedure TTyCustomToolWindowBar.BeginAutoDrag;
var
  p: TPoint;
  idx: Integer;
begin
  { LCL 在 WndProc 里、MouseDown 之前调这里(control.inc:2284),手势记录还没建。位置取按下
    消息自己带的那一个 —— 此刻的指针可能已经挪开了(快速按下就拖);程序里直接调的才问指针。
    条上的一切(图标、溢出、图标之间和条尾的空白)和边缘区都挡:都不是拖动把手(spec §9.6)。 }
  if FAutoDragPosValid then p := FAutoDragPos
  else if not PointerInClient(p) then p := Point(-1, -1);
  if PtInRect(BarLayout.Strip, p) or (PartAt(p.X, p.Y, idx) <> twbpNone) then Exit;
  { 让出来的标签行(空白也算,同页那一路 TTyToolWindow.BeginAutoDrag)、禁用的当前页的边界
    (Win32 上点禁用页的正文,按下落到栏,spec §3.7):都不是「按在栏上」,MouseDown 吞点击问的
    是同一处(SwallowPress)。 }
  if SwallowPress(p) then Exit;
  StartLclAutoDrag;
end;

procedure TTyCustomToolWindowBar.StartLclAutoDrag;
begin
  inherited BeginAutoDrag;
end;

procedure TTyCustomToolWindowBar.DoContextPopup(MousePos: TPoint; var Handled: Boolean);
begin
  { 让出来的标签行里、不在标签上(spec §3.7 / §6.8 E 期补):吞掉,不冒泡到窗体(同页那一路)。
    标签上照常:WindowAtPos 按 TabRowHost 认得出。 }
  if ((MousePos.X <> -1) or (MousePos.Y <> -1)) and HostsTabRow
     and PtInRect(BarLayout.TabRow, MousePos) and (WindowAtPos(MousePos.X, MousePos.Y) = nil) then
  begin
    FContextWindow := nil;
    FPopupBlocked := False;
    Handled := True;
    Exit;
  end;
  if (MousePos.X <> -1) or (MousePos.Y <> -1) then
    FContextWindow := WindowAtPos(MousePos.X, MousePos.Y)
  else
    FContextWindow := nil;
  FPopupBlocked := FContextWindow = nil;
  if FPopupBlocked then Exit;
  inherited DoContextPopup(MousePos, Handled);
end;

function TTyCustomToolWindowBar.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  if HostsTabRow and PtInRect(BarLayout.TabRow, MousePos) then Exit(True);
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
end;

function TTyCustomToolWindowBar.GetPopupMenu: TPopupMenu;
begin
  if FPopupBlocked then
  begin
    FPopupBlocked := False;
    Exit(nil);
  end;
  Result := inherited GetPopupMenu;
end;

procedure TTyCustomToolWindowBar.ShowOverflowMenu;
var
  hidden: TTyToolWindowPlan;
  item: TMenuItem;
  host: TWinControl;
  pt: TPoint;
  menuAlign: TPopupAlignment;
  w: TTyCustomToolWindow;
  btxt: string;
  bdot: Boolean;
  i: Integer;
begin
  hidden := OverflowWindows;
  if Length(hidden) = 0 then Exit;
  if FOverflowMenu = nil then FOverflowMenu := TTyPopupMenu.Create(nil);
  TTyPopupMenu(FOverflowMenu).Controller := Controller;
  FOverflowMenu.PopupComponent := Self;
  FOverflowMenu.Items.Clear;
  for i := 0 to High(hidden) do
  begin
    item := TMenuItem.Create(FOverflowMenu);
    { 角标跟着进菜单(spec §8.1):收进溢出的窗口在行上看不见,数字也丢了的话用户不知道那里有
      东西。数字写成「Problems (3)」,圆点写成「Problems •」。 }
    w := Windows[hidden[i]];
    if not w.BadgeDisplay(btxt, bdot) then item.Caption := w.Caption
    else if bdot then item.Caption := w.Caption + ' ' + #$E2#$80#$A2
    else item.Caption := w.Caption + ' (' + btxt + ')';
    item.Tag := PtrInt(Windows[hidden[i]]);
    { 禁用窗口那一项灰掉、点不了(spec §3.7)。 }
    item.Enabled := Windows[hidden[i]].Enabled;
    item.OnClick := @OverflowItemClick;
    FOverflowMenu.Items.Add(item);
  end;
  { PopupComponent 仍是栏。只在有句柄时弹(spec §7.4)。 }
  host := OverflowMenuAnchorIn(pt, menuAlign);
  if host = nil then Exit;
  FOverflowMenu.Alignment := menuAlign;
  if not host.HandleAllocated then Exit;
  pt := host.ClientToScreen(pt);
  FOverflowMenu.PopUp(pt.X, pt.Y);
end;

function TTyCustomToolWindowBar.OverflowMenuAnchorIn(out APoint: TPoint;
  out AAlignment: TPopupAlignment): TWinControl;
var
  r: TRect;
  h: TTyToolWindowTabRowHost;
begin
  { 菜单贴着溢出按钮开(锚点和对齐方式一处算,见 TyToolWindowOverflowMenuAnchor)。
    底栏的溢出按钮在标签行里,标签行在谁身上问 TabRowHost:平时是当前页,当前页被禁用时是栏
    (spec §3.7)。矩形换成宿主客户区坐标,换屏幕坐标用宿主;读写方向取当前页的 —— 那一行几何
    就是按它镜像的,取栏的话两者不一致时锚到镜像前的那一侧。 }
  if FPlacement = twpBottom then
  begin
    h := TabRowHost;
    Result := h.Host;
    if Result = nil then Result := FActive;
    if Result = nil then
    begin
      APoint := Point(0, 0);
      AAlignment := paLeft;
      Exit;
    end;
    r := h.Geom.Overflow;
    if h.Host <> nil then Types.OffsetRect(r, h.Row.Left, h.Row.Top);
    TyToolWindowOverflowMenuAnchor(r, FPlacement, FActive.IsRightToLeft, APoint, AAlignment);
  end
  else
  begin
    Result := Self;
    r := BarLayout.Overflow;
    TyToolWindowOverflowMenuAnchor(r, FPlacement, IsRightToLeft, APoint, AAlignment);
  end;
end;

function TTyCustomToolWindowBar.EdgeRect: TRect;
begin
  Result := BarLayout.Edge;
end;

procedure TTyCustomToolWindowBar.LMCancelMode(var Message: TLMessage);
begin
  inherited;
  { ShowModal、Application.HandleException 会发:拉宽到一半的尺寸不许留下,拖到一半的
    也作废;设计期武装着的手势同样作废(见引擎的 DesignArmed)。 }
  ResetGesture(twgeCancel);
  FGesture.DisarmDesign;
end;

procedure TTyCustomToolWindowBar.CMEnabledChanged(var Message: TLMessage);
begin
  inherited;
  if not Enabled then ResetGesture(twgeCancel);
  { 拖动中被禁用的隐藏侧栏不再是放置目标(manager 的 IsCrossCandidate):预览当场收掉,不等指针
    再动一下(spec §9.8)。 }
  if not Enabled then HideDropPreview;
  { 标签行跟着灰掉 / 恢复(它画在当前页里)。 }
  InvalidateHeader;
end;

procedure TTyCustomToolWindowBar.CMVisibleChanged(var Message: TLMessage);
begin
  inherited;
  if not Visible then ResetGesture(twgeCancel);
  { 同上:藏起来的栏不是放置目标。 }
  if not Visible then HideDropPreview;
  { 看得见的栏才参与分空间:同轴的另一条要重分。 }
  if [csLoading, csDestroying] * ComponentState = [] then DeriveSiblings(Parent);
end;

procedure TTyCustomToolWindowBar.SetEdgeHover(AOn: Boolean);
var
  want: TCursor;
begin
  if AOn = FEdgeHover then Exit;
  FEdgeHover := AOn;
  if AOn then
  begin
    if FPlacement = twpBottom then want := crVSplit else want := crHSplit;
    if not FCursorOverridden then
    begin
      FSavedCursor := Cursor;
      FCursorOverridden := True;
    end;
    Cursor := want;
  end
  else if FCursorOverridden then
  begin
    FCursorOverridden := False;
    Cursor := FSavedCursor;
  end;
  if not (csDestroying in ComponentState) then Invalidate;
end;

procedure TTyCustomToolWindowBar.BeginEdgeDrag(X, Y: Integer);
begin
  { 没有窗口、设计期:边缘区不起作用(LayoutIn 这时给的 Edge 本来就是空的,按不到这里)。
    吞点击的标志 MouseDown 已经按部件设过了。 }
  if (WindowCount = 0) or (csDesigning in ComponentState) or FMaximized then Exit;
  FGesture.BeginResize(FExpandedSize, ClientToScreen(Point(X, Y)));
  Invalidate;
end;

procedure TTyCustomToolWindowBar.EdgeDragTo(X, Y: Integer);
var
  p: TPoint;
  d, want, minL, v: Integer;
  wasSnapped: Boolean;
begin
  p := ClientToScreen(Point(X, Y));
  { 位移按增长方向取符号:左栏向右、右栏向左、底栏向上为正(同 TySplitterNewSize 对
    alRight / alBottom 取反,Splitter.pas:103-106)。 }
  case FPlacement of
    twpLeft: d := p.X - FGesture.StartPos.X;
    twpRight: d := FGesture.StartPos.X - p.X;
  else
    d := FGesture.StartPos.Y - p.Y;
  end;
  want := FGesture.StartSize + MulDiv(d, 96, PPI);
  minL := ActiveController.Metric(TyToolWindowContentMinVar, TyToolWindowContentMinDef);
  if minL < 0 then minL := 0;
  wasSnapped := FGesture.Snapped;
  { 吸附收起(spec §6.3):原始尺寸不到 content-min 的一半就实时按收起排布,ExpandedSize
    保持起点;拖回阈值以内恢复展开、继续实时写。 }
  FGesture.Snapped := want < minL div 2;
  if FGesture.Snapped then v := FGesture.StartSize
  else if want < minL then v := minL
  else v := want;
  if v <> FExpandedSize then
    ExpandedSize := v            { 自己 Relayout }
  else if wasSnapped <> FGesture.Snapped then
  begin
    Relayout;
    Invalidate;
  end;
  { 吸附 / 回来:让出行跟着没了 / 回来(HostsTabRow 的口径含吸附)。 }
  if wasSnapped <> FGesture.Snapped then TabRowHostMayHaveChanged;
end;

function TTyCustomToolWindowBar.IsDraggingForTest: Boolean;
begin
  Result := FGesture.State = twgsDragging;
end;

function TTyCustomToolWindowBar.DropSlotAt(X, Y: Integer): Integer;
var
  L: TTyToolWindowBarLayout;
begin
  L := BarLayout;
  { 源栏自己只算它的图标条(spec §9.4):内容区被当前页盖着,反馈也只能画在条上。
    条上沿条方向按已排布图标的中点找空隙;条的空白尾巴、溢出按钮都算「最后一个之后」。 }
  if not PtInRect(L.Cells, Point(X, Y)) then Exit(-1);
  Result := TyToolWindowSlotAt(L.Slots, X, Y, True, WindowCount);
end;

function TTyCustomToolWindowBar.IsNoOpSlot(ASlot: Integer): Boolean;
var
  src: Integer;
begin
  src := IndexOfWindow(FGesture.Window);
  Result := (src < 0) or (ASlot = src) or (ASlot = src + 1);
end;

function TTyCustomToolWindowBar.DropLineY(const L: TTyToolWindowBarLayout): Integer;
var
  i: Integer;
begin
  Result := -1;
  if FForeignDrop then
  begin
    { 别的栏拖过来的:跨栏没有空操作,有槽位就画。 }
    if FDropSlot < 0 then Exit;
  end
  else if (FGesture.State <> twgsDragging) or (FDropSlot < 0) or IsNoOpSlot(FDropSlot) then Exit;
  { 空隙 k 画在「窗口 k 那一格」的上沿;最后一个之后画在最后一格的下沿。 }
  for i := 0 to High(L.Slots) do
    if L.Slots[i].ItemIndex = FDropSlot then Exit(L.Slots[i].ItemRect.Top);
  for i := 0 to High(L.Slots) do
    if L.Slots[i].ItemIndex = FDropSlot - 1 then Exit(L.Slots[i].ItemRect.Bottom);
  { 空栏(条上一个图标都没有)照样是目标:线画在条的上沿。 }
  if FForeignDrop then Result := L.Cells.Top;
end;

procedure TTyCustomToolWindowBar.SetForeignDrop(ASlot: Integer);
var
  lit: Boolean;
begin
  lit := ASlot >= 0;
  if not lit then ASlot := -1;
  if (lit = FForeignDrop) and (ASlot = FDropSlot) then Exit;
  FForeignDrop := lit;
  FDropSlot := ASlot;
  if csDestroying in ComponentState then Exit;
  { 隐藏的栏没有像素、不画插入线:把放置预览切到 :hover(spec §9.8)。 }
  if HiddenAsEmpty then SetDropPreviewHot(lit)
  else Invalidate;
end;

function TTyCustomToolWindowBar.DragCursorForTest: TCursor;
begin
  Result := FGesture.FCursor;
end;

procedure TTyCustomToolWindowBar.SetDropSlot(ASlot: Integer);
begin
  if ASlot = FDropSlot then Exit;
  FDropSlot := ASlot;
  { 只在槽位变了时 invalidate(spec §9.8)。底栏的插入线画在当前页里:丢当前页的缓存。 }
  if csDestroying in ComponentState then Exit;
  if FPlacement = twpBottom then InvalidateHeader
  else Invalidate;
end;

procedure TTyCustomToolWindowBar.DragTo(X, Y: Integer);
var
  slot: Integer;
  tgt: TTyCustomToolWindowBar;
begin
  { 有 manager 的侧栏:问 manager(spec §9.4),答本栏、另一侧栏或没有目标。 }
  if (FManager <> nil) and (FPlacement <> twpBottom) then
  begin
    tgt := FManager.DropTargetAt(Self, ClientToScreen(Point(X, Y)), slot);
    { 问 OnCanMoveWindow 的时候处理器可能把拖动取消了(CancelDrag、Load、改栏的 Collapsed……):
      手势已经收尾,不再往任何一条栏上写落点。 }
    if FGesture.State <> twgsDragging then Exit;
    if tgt = Self then
    begin
      FGesture.SetTarget(nil, -1);
      SetDropSlot(slot);
    end
    else
    begin
      SetDropSlot(-1);
      FGesture.SetTarget(tgt, slot);     { tgt 为 nil 时只清旧目标 }
    end;
    if tgt = nil then FGesture.SetCursor(crNoDrop) else FGesture.SetCursor(crDrag);
    Exit;
  end;
  { 没有 manager:照 A 期只看自己的图标条。 }
  slot := DropSlotAt(X, Y);
  SetDropSlot(slot);
  { 不在图标条上 = 没有目标,在这里松开就是取消。 }
  if slot < 0 then FGesture.SetCursor(crNoDrop) else FGesture.SetCursor(crDrag);
end;

function TTyCustomToolWindowBar.PlaceWindow(AWindow: TTyCustomToolWindow; AIndex: Integer): Integer;
var
  cur, n: Integer;
begin
  Result := -1;
  cur := IndexOfWindow(AWindow);
  if cur < 0 then Exit;
  n := WindowCount;
  if AIndex < 0 then AIndex := 0;
  if AIndex > n - 1 then AIndex := n - 1;
  if AIndex = cur then Exit;
  { 不激活、不展开、不换父(spec §9.5);当前页还是那个窗口,ActiveIndex 跟着变,不发 OnChange。 }
  SetControlIndex(AWindow, ControlIndexForWindowPos(AWindow, AIndex));
  Invalidate;
  InvalidateHeader;
  if [csDesigning, csLoading, csDestroying] * ComponentState = [csDesigning] then
    OwnerFormDesignerModified(Self);
  Result := cur;
end;

procedure TTyCustomToolWindowBar.ReorderWindow(AWindow: TTyCustomToolWindow; AIndex: Integer);
var
  old: Integer;
begin
  { 改之前(spec §10.5):调顺序也是布局。 }
  if FManager <> nil then FManager.NoteLayoutChanging(Self);
  old := PlaceWindow(AWindow, AIndex);
  { 空操作(拖回原位、钳位之后没动)不报。SetChildOrder(流式、设计器)不经过这里,不报。
    布局应用的批次不报(它用 PlaceWindow,这一道防以后有人在批次里调 WindowIndex)。 }
  if (old >= 0) and (FManager <> nil) and (FLayoutBatch = 0) then
    FManager.WindowMoved(AWindow, Self, old);
end;

procedure TTyCustomToolWindowBar.BeginDeferEvents;
begin
  Inc(FDeferEvents);
end;

function TTyCustomToolWindowBar.EndDeferEvents: TTyToolWindowBarEvents;
begin
  Result := [];
  if FDeferEvents <= 0 then Exit;
  Dec(FDeferEvents);
  if FDeferEvents > 0 then Exit;
  Result := FPendingEvents;
  FPendingEvents := [];
end;

procedure TTyCustomToolWindowBar.FireBarEvent(AEvent: TTyToolWindowBarEvent);
begin
  if not EventsAllowed then Exit;
  case AEvent of
    twbeChange:
      if Assigned(FOnChange) then FOnChange(Self);
    twbeExpand:
      if Assigned(FOnExpand) then FOnExpand(Self);
    twbeCollapse:
      if Assigned(FOnCollapse) then FOnCollapse(Self);
  end;
end;

procedure TTyCustomToolWindowBar.CMDesignHitTest(var Message: TCMDesignHitTest);
var
  idx: Integer;
  w: TTyCustomToolWindow;
begin
  { 应答照 TabStrip(designer-hittest-gesture-consistency):按下和拖动答 1,松开答 0
    交还设计器。切换时机不照 TabStrip(它按下就切):写在松开分支里,**先切再答 0** ——
    答 0 之后设计器不会再调 MouseUp(designer.pp:2486-2494)。 }
  Message.Result := 0;
  if FGesture.DesignArmed then
  begin
    if (Message.Keys and MK_LBUTTON) <> 0 then
      Message.Result := 1
    else
    begin
      w := FGesture.DesignWindow;
      FGesture.DisarmDesign;
      if HandleAllocated then MouseCapture := False;
      if (PartAt(Message.XPos, Message.YPos, idx) = twbpItem) and (Windows[idx] = w) then
        ActivateWindow(w);
      Message.Result := 0;
    end;
  end
  else if PartAt(Message.XPos, Message.YPos, idx) = twbpItem then
    Message.Result := 1;
end;

procedure TTyCustomToolWindowBar.CMHintShow(var Message: TLMessage);
var
  info: PHintInfo;
  txt: string;
  r: TRect;
begin
  info := PHintInfo(Message.LParam);
  { 让出来的标签行(spec §3.7):标签、溢出、最大化 / 还原、收起给提示;行内空白答 1 —— 不显示,
    也不回落到栏自己的 Hint(同页那一路)。 }
  if (info <> nil) and HostsTabRow and PtInRect(BarLayout.TabRow, info^.CursorPos) then
  begin
    if RowHintAt(TabRowHost, info^.CursorPos.X, info^.CursorPos.Y, txt, r) then
    begin
      info^.HintStr := txt;
      info^.CursorRect := r;
      Message.Result := 0;
    end
    else
    begin
      info^.CursorRect := Rect(info^.CursorPos.X, info^.CursorPos.Y,
        info^.CursorPos.X + 1, info^.CursorPos.Y + 1);
      Message.Result := 1;
    end;
    Exit;
  end;
  { 禁用的当前页的边界里(Win32 上指针在禁用页上,提示请求落到栏,spec §3.7):那不是「指着栏」,
    不显示栏自己的 Hint。挪一下就重新问。 }
  if (info <> nil) and InDisabledActivePage(info^.CursorPos) then
  begin
    info^.CursorRect := Rect(info^.CursorPos.X, info^.CursorPos.Y,
      info^.CursorPos.X + 1, info^.CursorPos.Y + 1);
    Message.Result := 1;
    Exit;
  end;
  if (info <> nil) and StripHintAt(info^.CursorPos.X, info^.CursorPos.Y, txt, r) then
  begin
    info^.HintStr := txt;
    info^.CursorRect := r;
    Message.Result := 0;      { 0 = 显示 }
  end
  else
    inherited;
end;

procedure TTyCustomToolWindowBar.SetPlacement(AValue: TTyToolWindowPlacement);
var
  wins: TTyToolWindowArray;
  i: Integer;
begin
  if FPlacement = AValue then Exit;
  { 侧 ↔ 底:运行时栏里有窗口就忽略 —— 会破坏「不能跨到底栏」的规则和布局串的键。 }
  if ((FPlacement = twpBottom) <> (AValue = twpBottom)) and (WindowCount > 0)
     and ([csDesigning, csLoading] * ComponentState = []) then Exit;
  { 改 Placement 之前先还原(spec §6.4)。 }
  Maximized := False;
  ResetGesture(twgeCancel);
  { 参与拖动的栏(源栏或目标栏)改了 Placement:取消(spec §9.7)。 }
  if FManager <> nil then FManager.BarChanged(Self);
  FPlacement := AValue;
  { 同一 manager 下每条栏的冲突提示都可能跟着变(本栏在表里,一起重排)。 }
  if FManager <> nil then FManager.PlacementsChanged;
  { 流式加载时 Align 自己也在流里,不替它改。 }
  if not (csLoading in ComponentState) then
    Align := PlacementAlign;
  DeriveSize;
  if not (csLoading in ComponentState) then
    MoveToOuterEdge;
  { 侧 ↔ 底换的是窗口的标题行模式。 }
  wins := WindowList(nil);
  for i := 0 to High(wins) do
    wins[i].RelayoutHeader;
  Realign;
  Invalidate;
end;

procedure TTyCustomToolWindowBar.MoveToOuterEdge;
var
  p: TWinControl;
  c: TControl;
  i, v: Integer;
begin
  { 把 Left(左右)或 Top(底)设到父控件同侧的最外边,让对齐引擎把它排在同向对齐兄弟的
    最外侧。LCL 按 Left / 右端 / 底端**严格**比较定顺序(wincontrol.inc:2522),相等时看
    BaseBounds —— 不可预测,所以已经有兄弟贴在边上时再往外一格。这个数只是排序键,
    对齐引擎排一遍就改掉。 }
  p := Parent;
  if p = nil then Exit;
  case FPlacement of
    twpLeft:
      begin
        v := 0;
        for i := 0 to p.ControlCount - 1 do
        begin
          c := p.Controls[i];
          if (c <> Self) and (c.Align = alLeft) and (c.Left <= v) then v := c.Left - 1;
        end;
        Left := v;
      end;
    twpRight:
      begin
        v := p.ClientWidth;
        for i := 0 to p.ControlCount - 1 do
        begin
          c := p.Controls[i];
          if (c <> Self) and (c.Align = alRight) and (c.Left + c.Width >= v) then
            v := c.Left + c.Width + 1;
        end;
        Left := v - Width;
      end;
    twpBottom:
      begin
        v := p.ClientHeight;
        for i := 0 to p.ControlCount - 1 do
        begin
          c := p.Controls[i];
          if (c <> Self) and (c.Align = alBottom) and (c.Top + c.Height >= v) then
            v := c.Top + c.Height + 1;
        end;
        Top := v - Height;
      end;
  end;
end;

procedure TTyCustomToolWindowBar.SetHideWhenEmpty(AValue: Boolean);
begin
  if FHideWhenEmpty = AValue then Exit;
  FHideWhenEmpty := AValue;
  if [csLoading, csDestroying] * ComponentState <> [] then Exit;
  Relayout;
  Invalidate;
end;

procedure TTyCustomToolWindowBar.SetExpandedSize(AValue: Integer);
begin
  { 和布局串的 1-5 位纯数字对齐。拉宽、设计器改大小、代码、读布局都经过这里。 }
  if AValue < 0 then AValue := 0
  else if AValue > 99999 then AValue := 99999;
  if FExpandedSize = AValue then Exit;
  { 改之前(spec §10.5):含拉宽边。 }
  if FManager <> nil then FManager.NoteLayoutChanging(Self);
  FExpandedSize := AValue;
  Relayout;
  Invalidate;
end;

function TTyCustomToolWindowBar.EventsAllowed: Boolean;
begin
  Result := ([csDesigning, csLoading, csDestroying] * ComponentState = []) and (FSilent = 0)
    and (FLayoutBatch = 0);
end;

procedure TTyCustomToolWindowBar.DoChange;
begin
  { 延后期间只记下来,由 MoveWindow / 直接改 Parent 的簿记按顺序发。 }
  if FDeferEvents > 0 then
  begin
    Include(FPendingEvents, twbeChange);
    Exit;
  end;
  if EventsAllowed and Assigned(FOnChange) then FOnChange(Self);
end;

procedure TTyCustomToolWindowBar.SetCollapsed(AValue: Boolean);
var
  focusIn: Boolean;
  form: TCustomForm;
begin
  if FCollapsed = AValue then Exit;
  { 代码搭的 manager:Showing 之后第一次改布局之前记默认布局(spec §10.5)。 }
  if FManager <> nil then FManager.NoteLayoutChanging(Self);
  { 收起之前先还原(spec §6.4):再展开时是还原的高度。 }
  if AValue then Maximized := False;
  { 拉宽中途 Collapsed 被别处改了:拉宽作废,ExpandedSize 回到起点(spec §6.3)。 }
  ResetGesture(twgeCancel);
  { 别的栏正拖着窗口、目标就是本栏:取消(spec §9.7)。 }
  if FManager <> nil then FManager.BarChanged(Self);
  FCollapsed := AValue;
  { 只在运行时生效:流式加载时由 Loaded 统一应用;设计期永远按展开显示。 }
  if [csLoading, csDesigning, csDestroying] * ComponentState = [] then
  begin
    if FActive <> nil then
    begin
      if AValue then
      begin
        { 先记下焦点在不在里面 —— 藏起来之后 LCL 会把它挪到窗体本身。布局应用的批次跳过
          这一步,由批次最后统一处理(spec §5.3 / §10.4 第 7 步)。 }
        focusIn := (FLayoutBatch = 0) and FocusIsInside(FActive);
        HideWindowNow(FActive);
        { 焦点掉到窗体本身的话快捷键全部失灵(spec §5.3)。需要真句柄的那一半在 test.toolwindow.focus 测。 }
        if focusIn then
        begin
          form := GetParentForm(Self);
          if form <> nil then form.SelectNext(Self, True, True);
        end;
      end
      else
        ShowWindowNow(FActive);
    end;
    Relayout;
    Invalidate;
    { 收起时没有标签行,展开回来当前页若还禁用就再让出来(spec §3.7)。 }
    TabRowHostMayHaveChanged;
  end;
  { 延后期间只记下来(见 BeginDeferEvents)。同一次延后里先收起后展开两个都记着,由调用方
    按顺序发 —— 眼下没有这种路径。 }
  if FDeferEvents > 0 then
  begin
    if AValue then Include(FPendingEvents, twbeCollapse)
    else Include(FPendingEvents, twbeExpand);
  end
  { 事件只由 EventsAllowed 一处把关(设计期、加载中、静默批次都不发)。 }
  else if EventsAllowed then
  begin
    if AValue then
    begin
      if Assigned(FOnCollapse) then FOnCollapse(Self);
    end
    else if Assigned(FOnExpand) then
      FOnExpand(Self);
  end;
end;

function TTyCustomToolWindowBar.WindowList(AExcept: TTyCustomToolWindow): TTyToolWindowArray;
var
  i, n: Integer;
begin
  Result := nil;
  SetLength(Result, ControlCount);
  n := 0;
  for i := 0 to ControlCount - 1 do
    if (Controls[i] is TTyCustomToolWindow) and (Controls[i] <> AExcept) then
    begin
      Result[n] := TTyCustomToolWindow(Controls[i]);
      Inc(n);
    end;
  SetLength(Result, n);
end;

function TTyCustomToolWindowBar.IsRegistered(AWindow: TTyCustomToolWindow): Boolean;
var
  i: Integer;
begin
  if AWindow <> nil then
    for i := 0 to High(FRegistered) do
      if FRegistered[i] = AWindow then Exit(True);
  Result := False;
end;

function TTyCustomToolWindowBar.GetWindow(AIndex: Integer): TTyCustomToolWindow;
var
  i, n: Integer;
begin
  n := 0;
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyCustomToolWindow then
    begin
      if n = AIndex then Exit(TTyCustomToolWindow(Controls[i]));
      Inc(n);
    end;
  raise EListError.CreateFmt('Tool window index out of bounds (%d)', [AIndex]);
end;

function TTyCustomToolWindowBar.GetWindowCount: Integer;
var
  i: Integer;
begin
  Result := 0;
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyCustomToolWindow then Inc(Result);
end;

function TTyCustomToolWindowBar.IndexOfWindow(AWindow: TTyCustomToolWindow): Integer;
var
  i, n: Integer;
begin
  if AWindow <> nil then
  begin
    n := 0;
    for i := 0 to ControlCount - 1 do
      if Controls[i] is TTyCustomToolWindow then
      begin
        if Controls[i] = AWindow then Exit(n);
        Inc(n);
      end;
  end;
  Result := -1;
end;

function TTyCustomToolWindowBar.ControlIndexForWindowPos(AWindow: TTyCustomToolWindow;
  APos: Integer): Integer;
var
  others: TTyToolWindowArray;
  cur, c: Integer;
begin
  { SetControlIndex 是「先摘下再插到 NewIndex」,所以目标在自己后面时要减一。 }
  cur := GetControlIndex(AWindow);
  Result := cur;
  others := WindowList(AWindow);
  if Length(others) = 0 then Exit;
  if APos < 0 then APos := 0;
  if APos <= High(others) then
  begin
    c := GetControlIndex(others[APos]);            { 插到它前面 }
    if cur < c then Result := c - 1 else Result := c;
  end
  else
  begin
    c := GetControlIndex(others[High(others)]);    { 插到最后一个窗口后面 }
    if cur < c then Result := c else Result := c + 1;
  end;
end;

procedure TTyCustomToolWindowBar.SetChildOrder(Child: TComponent; Order: Integer);
begin
  if (Child is TTyCustomToolWindow) and (TTyCustomToolWindow(Child).Parent = Self) then
  begin
    SetControlIndex(TControl(Child),
      ControlIndexForWindowPos(TTyCustomToolWindow(Child), Order));
    Invalidate;
    InvalidateHeader;
  end
  else
    inherited SetChildOrder(Child, Order);
end;

function TTyCustomToolWindowBar.FocusIsInside(AWindow: TTyCustomToolWindow): Boolean;
var
  form: TCustomForm;
begin
  Result := False;
  if AWindow = nil then Exit;
  form := GetParentForm(Self);
  if (form = nil) or (form.ActiveControl = nil) then Exit;
  Result := AWindow.ContainsControl(form.ActiveControl);
end;

procedure TTyCustomToolWindowBar.ShowWindowNow(AWindow: TTyCustomToolWindow);
var
  was: Boolean;
begin
  was := FBarSwitching;
  FBarSwitching := True;
  try
    { csNoDesignVisible 必须在写 Visible 之前摘:设计期的显示状态是
      `Visible or (csDesigning and not csNoDesignVisible)`,触发重算的是写 Visible 那一次。
      顺序反了,设计器里这一页的 HWND 要到整体重绘才露面(PageControl.pas:244-262)。 }
    AWindow.ControlStyle := AWindow.ControlStyle - [csNoDesignVisible];
    { 藏着的这段时间里,它画的标签行可能已经过时了:收起期间切到它、别的页改了标题
      (那时 InvalidateHeader 丢的是当时的当前页)、换了主题……藏着的页没人替它丢缓存,
      显示出来就 blit 旧帧(spec §3.5)。显示是低频事件,统一在这里丢。 }
    if AWindow.FPaintCache <> nil then AWindow.FPaintCache.Drop;
    AWindow.Visible := True;
  finally
    FBarSwitching := was;
  end;
end;

procedure TTyCustomToolWindowBar.HideWindowNow(AWindow: TTyCustomToolWindow);
var
  was: Boolean;
begin
  was := FBarSwitching;
  FBarSwitching := True;
  try
    { 同上,反过来:先加标志再写 Visible,否则切走的那一页 HWND 一直杵着。 }
    AWindow.ControlStyle := AWindow.ControlStyle + [csNoDesignVisible];
    AWindow.Visible := False;
  finally
    FBarSwitching := was;
  end;
end;

procedure TTyCustomToolWindowBar.SwitchCore(AWindow, AOld: TTyCustomToolWindow; AMoveFocus: Boolean);
var
  focusIn: Boolean;
  wins: TTyToolWindowArray;
  i: Integer;
begin
  { 布局应用的批次跳过焦点这一步,由批次最后统一处理(spec §5.1 第 5 步 / §10.4 第 7 步)。 }
  if FLayoutBatch > 0 then AMoveFocus := False;
  { 第 5 步要的是「焦点**原来**在不在旧页里」,藏之前记。 }
  focusIn := AMoveFocus and (AOld <> nil) and (AOld <> AWindow) and FocusIsInside(AOld);
  FActive := AWindow;
  { 标签行上的手势属于捕获它的那一页。代码在手势进行中换了当前页:那一页的标签行不再显示,
    手势作废 —— 否则之后在旧页上的松开照样被当成点击 / 落点(spec §7.1 / §9.7)。 }
  if (FGesture.Capturer is TTyCustomToolWindow) and (FGesture.Capturer <> FActive) then
    ResetGesture(twgeCancel);
  { 藏的是栏里**其余每一个**窗口,不只 AOld:带着 Visible = True 进来的窗口(从别的栏
    挪过来、代码里先 Visible 再 Parent)、布局应用挪进来的窗口,都不是「上一页」,
    只按 (新, 旧) 成对开关的话它们会一直杵在那里。已经藏着的再藏一次不改 Visible,
    也就不发 CM_VISIBLECHANGED —— 事件语义不变。只算注册过的:直接调 UnregisterWindow
    时离开的那个还在 Controls 里,回落不该去藏它(spec §5.2)。 }
  wins := WindowList(nil);
  if CollapsedAtRunTime and not FSwitchExpanded then
  begin
    { 1. 收起着就到此为止(spec §5.3):一页都不显示,连目标一起藏。 }
    for i := 0 to High(wins) do
      if IsRegistered(wins[i]) then HideWindowNow(wins[i]);
  end
  else
  begin
    { 2、3:先显示新页再藏其余的 —— 先藏的话 LCL 会把焦点交给窗体本身。 }
    if AWindow <> nil then ShowWindowNow(AWindow);
    for i := 0 to High(wins) do
      if (wins[i] <> AWindow) and IsRegistered(wins[i]) then HideWindowNow(wins[i]);
    { 4. 标题行按此刻的样子重排(悬停在下面重查)。 }
    if AWindow <> nil then AWindow.RelayoutHeader;
    { 5. 只有焦点原来在旧页里才动它;新页已经显示了才聚焦得上。 }
    if focusIn and (AWindow <> nil) and AWindow.CanFocus then
      AWindow.FocusFirst;
  end;
  { 4(续). 当前页被强制留在条上,切页可能换掉条上排的是哪几个图标:按指针此刻的位置
    重查悬停,不然悬停停在切页前那一格上。设计期不做悬停。 }
  RecheckHover;
  { 新的当前页可能是禁用的、旧的可能是:标签行在谁身上跟着变(spec §3.7)。 }
  TabRowHostMayHaveChanged;
  { 6. 设计期切页改了一个 published 值:两声都要(见 TTyCustomTabStrip 同一处)。
    静默那一批(Loaded 应用 ActiveIndex)是打开窗体,不是改了它。 }
  if FSilent = 0 then
  begin
    OwnerFormDesignerModified(Self);
    if ([csDesigning, csLoading, csDestroying] * ComponentState = [csDesigning])
       and Assigned(TyDesignerRefreshValuesProc) then
      TyDesignerRefreshValuesProc();
  end;
end;

procedure TTyCustomToolWindowBar.BeginSilent;
var
  i: Integer;
begin
  { 走 FRegistered 而不是 Controls:这一批的账是按注册记的(注册时补层、注销时还层)。
    释放那条路上窗口先被 RemoveControl 摘下、过一阵才由 Notification 注销 ——
    按 Controls 找的话,这个空档里的 End 会漏掉它,它就带着一层静默走了。 }
  Inc(FSilent);
  for i := 0 to High(FRegistered) do
    FRegistered[i].BeginSilentVisibility;
end;

procedure TTyCustomToolWindowBar.EndSilent;
var
  i: Integer;
begin
  { 同 EndSilentVisibility 钳住 0:没配对的 End 不许把窗口那边的计数也减下去。 }
  if FSilent <= 0 then Exit;
  for i := 0 to High(FRegistered) do
    FRegistered[i].EndSilentVisibility;
  Dec(FSilent);
end;

procedure TTyCustomToolWindowBar.ActivateExpanded(AWindow: TTyCustomToolWindow);
begin
  if csDesigning in ComponentState then
  begin
    ActivateWindow(AWindow);
    Exit;
  end;
  if FCollapsed and (AWindow <> FActive) then
  begin
    { 展开紧跟在后面:这一次切页照展开的样子显示 AWindow(带着 Visible 进来的就不再藏一次),
      下面的展开再显示当前页时它已经显示着,不再发 OnShow。 }
    FSwitchExpanded := True;
    try
      ActivateWindow(AWindow);
    finally
      FSwitchExpanded := False;
    end;
  end
  else
    ActivateWindow(AWindow);
  Collapsed := False;
end;

procedure TTyCustomToolWindowBar.BeginLayoutBatch;
begin
  Inc(FLayoutBatch);
  DisableAlign;
end;

procedure TTyCustomToolWindowBar.EndLayoutBatch;
begin
  { 恢复对齐会重排,重排里用户的 OnResize 可能抛异常:层数照样还。 }
  try
    EnableAlign;
  finally
    if FLayoutBatch > 0 then Dec(FLayoutBatch);
  end;
end;

procedure TTyCustomToolWindowBar.SwitchSilently(AWindow: TTyCustomToolWindow);
begin
  BeginSilent;
  try
    SwitchCore(AWindow, FActive, False);
  finally
    EndSilent;
  end;
end;

procedure TTyCustomToolWindowBar.ActivateWindow(AWindow: TTyCustomToolWindow);
var
  prev: TTyCustomToolWindow;
begin
  if IndexOfWindow(AWindow) < 0 then Exit;
  { 流式加载期间只记下来,Loaded 统一应用。记窗口本身,不记序号(见 FLoadingTarget)。 }
  if csLoading in ComponentState then
  begin
    FLoadingTarget := AWindow;
    FLoadingActiveIndex := -1;
    Exit;
  end;
  if AWindow = FActive then Exit;
  { 当前页也存在布局串里(spec §10.2 的 pActive):改之前记默认布局(spec §10.5)。 }
  if FManager <> nil then FManager.NoteLayoutChanging(Self);
  prev := FActive;
  SwitchCore(AWindow, prev, True);
  if FActive <> prev then DoChange;
end;

function TTyCustomToolWindowBar.GetActiveIndex: Integer;
begin
  if not (csLoading in ComponentState) then Result := IndexOfWindow(FActive)
  else if FLoadingTarget <> nil then Result := IndexOfWindow(FLoadingTarget)
  else Result := FLoadingActiveIndex;
end;

procedure TTyCustomToolWindowBar.SetActiveIndex(AValue: Integer);
begin
  { 流式加载时窗口还没读完,先记下来。 }
  if csLoading in ComponentState then
  begin
    FLoadingActiveIndex := AValue;
    FLoadingTarget := nil;
    Exit;
  end;
  if (AValue < 0) or (AValue >= WindowCount) then Exit;
  ActivateWindow(Windows[AValue]);
end;

procedure TTyCustomToolWindowBar.RegisterWindow(AWindow: TTyCustomToolWindow);
var
  i: Integer;
  prev: TTyCustomToolWindow;
begin
  if (AWindow = nil) or (AWindow.Parent <> Self) then Exit;
  if IsRegistered(AWindow) then Exit;     { 幂等 }
  SetLength(FRegistered, Length(FRegistered) + 1);
  FRegistered[High(FRegistered)] := AWindow;
  { 窗体之外建的窗口(Owner = nil)被释放时,Owner 的广播到不了这里。 }
  AWindow.FreeNotification(Self);
  AWindow.Controller := Controller;
  { 静默批次中途进来的窗口是这一批的一部分:按当前层数补上,EndSilent 照样解除。
    必须在下面的切页之前 —— 它进来就会被显示出来。 }
  for i := 1 to FSilent do
    AWindow.BeginSilentVisibility;
  { 没有列表时写进来的序号,进了有列表的栏就换成名字。加载中它自己不动(Loaded 统一换)。 }
  AWindow.ResolveImageIndex;
  { 加载中不碰当前页,也不显示任何一页:Loaded 按待定值静默地挑、静默地显示。 }
  prev := FActive;
  { 不在加载中注册进来的(组件编辑器新建、粘贴、代码添加、从别的栏挪过来)成为当前页。
    MoveWindow 和布局应用自己管激活(FQuietMove,spec §5.1)。 }
  if not (csLoading in ComponentState) and not AWindow.FQuietMove then
    SwitchCore(AWindow, prev, True);
  { 先把尺寸推好再发事件:OnChange 里读到的 Width 得是新的(第一个窗口进来,空栏就展开)。 }
  Relayout;
  Invalidate;
  { 底栏统一行高:窗口列表变了,操作区那一项可能跟着变(spec §3.4)。 }
  ActionsSizeChanged;
  { 标签多了一个。 }
  InvalidateHeader;
  TabRowHostMayHaveChanged;
  if FActive <> prev then DoChange;
end;

procedure TTyCustomToolWindowBar.RemoveControl(AControl: TControl);
begin
  if (AControl is TTyCustomToolWindow) and IsRegistered(TTyCustomToolWindow(AControl)) then
  begin
    FLeaving := TTyCustomToolWindow(AControl);
    FLeavingIndex := IndexOfWindow(FLeaving);
  end;
  inherited RemoveControl(AControl);
  { 设计期漏进来的那个被删掉 / 挪走:提示那一行让回给窗口。 }
  if not (AControl is TTyCustomToolWindow)
     and ([csDesigning, csDestroying] * ComponentState = [csDesigning]) then
  begin
    Realign;
    Invalidate;
  end;
end;

procedure TTyCustomToolWindowBar.UnregisterWindow(AWindow: TTyCustomToolWindow);
var
  i, idx: Integer;
  prev, next: TTyCustomToolWindow;
  rest: TTyToolWindowArray;
begin
  if not IsRegistered(AWindow) then Exit;
  for i := 0 to High(FRegistered) do
    if FRegistered[i] = AWindow then
    begin
      Delete(FRegistered, i, 1);
      Break;
    end;
  { 静默批次中途离开:把本栏加的那几层还掉,不然它带着静默去到别处(见 BeginSilent)。 }
  for i := 1 to FSilent do
    AWindow.EndSilentVisibility;
  if AWindow = FLoadingTarget then FLoadingTarget := nil;
  { spec §5.2 / §9.7:属于它的手势记录清掉 —— 武装着的窗口走了,松开不许当成点击;
    设计期武装在它身上的也一样。 }
  { 底栏标签行上捕获者(当前页)和手势窗口(按下的那个标签)可以是两个窗口:捕获者走了也收尾,
    不然引擎记着一个已释放的捕获者。 }
  if (AWindow = FGesture.Window) or (AWindow = FGesture.Capturer) then
    ResetGesture(twgeDiscard);
  if AWindow = FGesture.DesignWindow then FGesture.DisarmDesign;
  if AWindow = FContextWindow then FContextWindow := nil;
  { 最后一个窗口走了:边缘区不再起作用,拉到一半的也作废;最大化的底栏先还原(spec §6.4)。 }
  if EdgeResizing and (Length(FRegistered) = 0) then ResetGesture(twgeCancel);
  if Length(FRegistered) = 0 then Maximized := False;
  { 悬停和按下按窗口序号记,别的窗口一走序号就挪了:悬停清掉(下一次移动重查),
    按下按还在的那个手势窗口重新对上(溢出按钮的按下态不按序号,不动)。 }
  FStripHover := -1;
  FOverflowHover := False;
  FHeaderHoverPart := twbpNone;
  FHeaderHoverIndex := -1;
  if (FGesture.Window <> nil) and (FGesture.Part = twbpItem) then
    FStripPressed := IndexOfWindow(FGesture.Window)
  else
    FStripPressed := -1;
  { 离开前的窗口序号:通常它已经不在 Controls 里了,取 RemoveControl 记下的那个;
    直接调本方法、它还在里面时现量。 }
  idx := IndexOfWindow(AWindow);
  if (idx < 0) and (AWindow = FLeaving) then idx := FLeavingIndex;
  if AWindow = FLeaving then FLeaving := nil;
  if not (csDestroying in AWindow.ComponentState) then
    AWindow.RemoveFreeNotification(Self);
  prev := FActive;
  if csDestroying in ComponentState then
  begin
    if FActive = AWindow then FActive := nil;
    Exit;
  end;
  { 加载中 FActive 通常是 nil(见 FActive);继承窗体第二遍加载时它是第一遍挑好的那页,
    离开了也不回落 —— 置 nil,Loaded 自己挑。 }
  { 布局应用的批次里也不回落:回落页会先显示、再被计划藏掉,多一对 OnShow / OnHide(spec §5.2 /
    §10.3,计划统一激活)。 }
  if (AWindow = FActive) and ((csLoading in ComponentState) or (FLayoutBatch > 0)) then
    FActive := nil
  else if AWindow = FActive then
  begin
    { 先置 nil 再回落:回落用的切换不该因为「焦点在旧页里」去挪焦点(spec §5.2)。
      原位置上的下一个,没有就上一个,都没有就保持 nil。 }
    FActive := nil;
    next := nil;
    rest := WindowList(AWindow);
    if (idx >= 0) and (idx <= High(rest)) then next := rest[idx]
    else if Length(rest) > 0 then next := rest[High(rest)];
    if next <> nil then SwitchCore(next, nil, False);
  end;
  Relayout;
  Invalidate;
  ActionsSizeChanged;
  InvalidateHeader;
  { 走的是禁用的当前页、又没有回落页:标签行不再让出(spec §3.7)。 }
  TabRowHostMayHaveChanged;
  if FActive <> prev then DoChange;
end;

procedure TTyCustomToolWindowBar.Notification(AComponent: TComponent; Operation: TOperation);
var
  i: Integer;
begin
  inherited Notification(AComponent, Operation);
  { 挂着处理器的兄弟被释放(或从 Owner 摘走 —— 那时它还活着,UnwatchAt 照常摘处理器,
    下一次推导再挂)。 }
  if (Operation = opRemove) and (AComponent is TControl) then
    for i := High(FWatched) downto 0 do
      if FWatched[i] = AComponent then UnwatchAt(i);
  if (Operation = opRemove) and (AComponent = FZeroInner) then FZeroInner := nil;
  { 窗口被释放(含设计期删除):LCL 在 SetParent(nil) 时它已经 csDestroying,
    注销那一步跳过了,走到这里。 }
  if (Operation = opRemove) and (AComponent is TTyCustomToolWindow) then
    UnregisterWindow(TTyCustomToolWindow(AComponent));
  { manager 被释放:只清自己的引用,不回头调它 —— 它正在走,它的表由它自己清。
    只是从 Owner 摘走(RemoveComponent、InsertComponent 换 Owner):它还活着、表里还记着本栏,
    而继承的 Notification 刚把两边的 FreeNotification 都拆了 —— 不从它的表里摘掉本栏,
    本栏日后释放时它收不到通知,表里留下悬垂指针。所以两边一起断。 }
  if (Operation = opRemove) and (AComponent = FManager) then
  begin
    if not (csDestroying in FManager.ComponentState) then FManager.RemoveBar(Self);
    DetachManager;
  end;
  { 列表被释放,或者只是从 Owner 里摘走(RemoveComponent 同样广播 opRemove,列表还活着):
    清引用,是订阅着的那一个就**当场**注销,再按生效列表重新订阅。注销不交给 Sync 去比
    差值:两种情形都必须注销 —— 摘走的那个活下来还会发变更、日后析构时要清自己的 link 表;
    释放中的那个,这一刻可能改订 Manager.Images。先清 FImages 再注销,互相的
    FreeNotification 才撤得掉(继承的 TComponent.Notification 在 opRemove 时也撤一遍,幂等)。 }
  if (Operation = opRemove)
     and ((AComponent = FImages) or (AComponent = FSubscribedList)) then
  begin
    if AComponent = FImages then FImages := nil;
    if AComponent = FSubscribedList then UnsubscribeImages;
    ImagesChanged;
  end;
end;

procedure TTyCustomToolWindowBar.DetachManager;
begin
  { 拖到一半 manager 走了(spec §9.7「manager 的 opRemove」)。 }
  ResetGesture(twgeCancel);
  FManager := nil;
  { 生效列表可能是它的 Images(spec §8)。 }
  ImagesChanged;
  { 离开了 manager,冲突提示(有的话)没了。manager 被释放的那条路只走到这里。 }
  ConflictMayHaveChanged;
end;

procedure TTyCustomToolWindowBar.SetManager(AValue: TTyCustomToolWindowManager);
begin
  if FManager = AValue then Exit;
  { 本栏正在拖图标(spec §9.7:参与拖动的栏改了 Manager 就取消)。原来没有 manager 时这是栏内
    调顺序:新 manager 不知道它在拖(FDragSource 只在进入拖动时记),CancelDrag 取消不到,落点
    却要改问新 manager —— 一样取消。换掉旧 manager 的那一半 RemoveBar 里也会取消。 }
  if FGesture.State = twgsDragging then ResetGesture(twgeCancel);
  { 流式 fixup 期间也会走到这里:绝不抛异常(spec §10.6)。冲突只是「不可用」,由 manager 现算。 }
  if FManager <> nil then
  begin
    { RemoveBar 里:参与拖动的栏换了 manager 就取消(spec §9.7),以它为目标的排队项删掉。 }
    FManager.RemoveBar(Self);
    { 双向挂的通知一起拆 —— 本栏和旧 manager 之间别无其他引用。旧 manager 正在释放时
      它自己在清通知表,不碰。 }
    if not (csDestroying in FManager.ComponentState) then
      FManager.RemoveFreeNotification(Self);
  end;
  FManager := AValue;
  if AValue <> nil then AValue.AddBar(Self);
  { 生效列表可能跟着 manager 换了(spec §8)。 }
  ImagesChanged;
  { 离开旧 manager 的这一条已经不在它的表里,旧表的 PlacementsChanged 轮不到本栏。 }
  ConflictMayHaveChanged;
end;

procedure TTyCustomToolWindowBar.SetController(AValue: TTyStyleController);
var
  wins: TTyToolWindowArray;
  i: Integer;
begin
  inherited SetController(AValue);
  { 推送链的第一段:栏 → 每个窗口(窗口再推给它的每个操作区)。 }
  wins := WindowList(nil);
  for i := 0 to High(wins) do
    wins[i].Controller := AValue;
end;

procedure TTyCustomToolWindowBar.ShowControl(AControl: TControl);
begin
  if (AControl is TTyCustomToolWindow) and (IndexOfWindow(TTyCustomToolWindow(AControl)) >= 0) then
  begin
    ActivateWindow(TTyCustomToolWindow(AControl));
    if not (csDesigning in ComponentState) then
      Collapsed := False;
  end;
  { 往上传:栏自己在某个页里时,那一页也得露面。 }
  inherited ShowControl(AControl);
end;

procedure TTyCustomToolWindowBar.Loaded;
var
  wins: TTyToolWindowArray;
  idx, i: Integer;
  target: TTyCustomToolWindow;
begin
  inherited Loaded;
  { 窗口都在 SetParent 里注册过了,顺序就是 Controls 顺序(ffChildPos 经 SetChildOrder)。
    -1 或越界、栏里又有窗口时取第一个(同 PageControl.pas:392-395)。 }
  wins := WindowList(nil);
  { 按窗口激活过的就是那个窗口(它离开时 UnregisterWindow 已经清掉了);否则按序号。 }
  if FLoadingTarget <> nil then
    target := FLoadingTarget
  else
  begin
    idx := FLoadingActiveIndex;
    if (idx < 0) or (idx > High(wins)) then
    begin
      if Length(wins) > 0 then idx := 0 else idx := -1;
    end;
    if idx >= 0 then target := wins[idx] else target := nil;
  end;
  FLoadingTarget := nil;
  { 视同流式加载:csLoading 已清,但窗体的 OnCreate 还没跑 —— 不发 OnChange,
    也不发窗口的 OnShow / OnHide(spec §5.1 / §6.6)。 }
  SwitchSilently(target);
  { 继承窗体的下一遍加载从真正应用的那一页开始,加载中 ActiveIndex 也答它。 }
  FLoadingActiveIndex := IndexOfWindow(FActive);
  { 挂起的 ImageIndex 在这里、而且只在这里换成名字(spec §8):加载中列表引用还没 fixup 完,
    谁先 fixup 上就会解析到谁。到这一步同一窗体里的引用都已就位(根读完时
    DoFixupReferences,reader.inc:1061-1062,早于 1528-1530 逐个调 Loaded);指向别的窗体 /
    数据模块的列表可能更晚才到(GlobalFixupReferences,:1537),那时经 SetImages →
    ImagesChanged 再解析。 }
  ResolvePendingImageIndexes;
  for i := 0 to High(wins) do
    wins[i].RelayoutHeader;
  Relayout;
  { .lfm 里流进来一个 Enabled = False 的当前页:标签行让到栏里(spec §3.7)—— 上面的 SwitchSilently
    已经做了(SwitchCore 最后一步 TabRowHostMayHaveChanged,那时 csLoading 已经清了),这里不再
    调一次。 }
  { spec §10.5:最后一句。谁最后一个离开 csLoading,谁收尾(manager 那边判)。 }
  if FManager <> nil then FManager.TryFinishLoading;
end;

{ --- TTyToolWindowGesture ------------------------------------------------------ }

constructor TTyToolWindowGesture.Create(ABar: TTyCustomToolWindowBar);
begin
  inherited Create;
  FBar := ABar;
end;

destructor TTyToolWindowGesture.Destroy;
begin
  { 栏已经析构完(它在 inherited Destroy 之后才放引擎):不回调栏,只收自己的资源。
    处理器挂在引擎对象上,栏的 RemoveAllHandlersOfObject(栏) 摘不掉它们。 }
  FreeResources;
  if Application <> nil then Application.RemoveAllHandlersOfObject(Self);
  if Screen <> nil then Screen.RemoveAllHandlersOfObject(Self);
  inherited Destroy;
end;

procedure TTyToolWindowGesture.FreeResources;
var
  t: TTimer;
begin
  if FHooked then
  begin
    FHooked := False;
    if Application <> nil then Application.RemoveOnKeyDownBeforeHandler(@KeyDownBefore);
    if Screen <> nil then Screen.RemoveHandlerActiveFormChanged(@ActiveFormChanged);
  end;
  { 唯一一次:不配对的 EndTempCursor 会把别人压的那一层弹掉。 }
  if FCursorPushed then
  begin
    FCursorPushed := False;
    if Screen <> nil then Screen.EndTempCursor(FCursor);
  end;
  { 可能正是在它自己的 OnTimer 里放它(CaptureTimerTick):先摘掉处理器再释放,同
    BalloonHint / Notification 的惯例 —— 已经排进消息队列的那一拍不会再进来。 }
  if FCaptureTimer <> nil then
  begin
    t := TTimer(FCaptureTimer);
    FCaptureTimer := nil;
    t.OnTimer := nil;
    t.Free;
  end;
  FCaptureConfirmed := False;
end;

procedure TTyToolWindowGesture.ReleaseResources;
begin
  FreeResources;
  FBar.SetDropSlot(-1);
  SyncDeactivateHook;
  { 跨栏的那一半:目标栏的外来落点、问过的答案、manager 的「正在拖」。 }
  SetTarget(nil, -1);
  FAllowed := nil;
  if (FBar.Manager <> nil) and (FBar.Manager.FDragSource = FBar) then
    FBar.Manager.SetDragSource(nil);
end;

procedure TTyToolWindowGesture.SetTarget(ABar: TTyCustomToolWindowBar; ASlot: Integer);
begin
  if (FTarget <> nil) and (FTarget <> ABar) then FTarget.SetForeignDrop(-1);
  FTarget := ABar;
  if ABar <> nil then ABar.SetForeignDrop(ASlot);
end;

function TTyToolWindowGesture.AllowedFor(ABar: TTyCustomToolWindowBar): Boolean;
var
  i: Integer;
  w: TTyCustomToolWindow;
begin
  for i := 0 to High(FAllowed) do
    if FAllowed[i].Bar = ABar then Exit(FAllowed[i].Allowed);
  w := FWindow;
  Result := (FBar.Manager <> nil) and FBar.Manager.CanMoveWindow(w, ABar);
  { 处理器里把拖动取消了(或者这一次手势已经换成了别的):这份答案不属于此刻的手势,不记 ——
    缓存只在进入拖动时清,记下的话会留给下一次手势。落点由调用方(DragTo)看状态不写。 }
  if (FState <> twgsDragging) or (FWindow <> w) then Exit;
  SetLength(FAllowed, Length(FAllowed) + 1);
  FAllowed[High(FAllowed)].Bar := ABar;
  FAllowed[High(FAllowed)].Allowed := Result;
end;

procedure TTyToolWindowGesture.ForgetBar(ABar: TTyCustomToolWindowBar);
var
  i: Integer;
begin
  for i := High(FAllowed) downto 0 do
    if FAllowed[i].Bar = ABar then Delete(FAllowed, i, 1);
end;

function TTyToolWindowGesture.AllowedCount: Integer;
begin
  Result := Length(FAllowed);
end;

procedure TTyToolWindowGesture.SyncDeactivateHook;
var
  want: Boolean;
begin
  want := FResizing or FHooked;
  if (want = FDeactivateHooked) or (Application = nil) then Exit;
  FDeactivateHooked := want;
  if want then Application.AddOnDeactivateHandler(@AppDeactivated)
  else Application.RemoveOnDeactivateHandler(@AppDeactivated);
end;

procedure TTyToolWindowGesture.AppDeactivated(Sender: TObject);
begin
  Reset(twgeCancel);
end;

procedure TTyToolWindowGesture.Press(APart: TTyToolWindowBarPart; AWindow: TTyCustomToolWindow;
  ADraggable: Boolean; ACapturer: TControl; X, Y: Integer; AShift: TShiftState);
begin
  FState := twgsArmed;
  FPart := APart;
  FWindow := AWindow;
  FDraggable := ADraggable;
  FCapturer := ACapturer;
  FOrigin := ACapturer.ClientToScreen(Point(X, Y));
  { 多击的按下照常武装(之后可以拖),但阈值以内松开永远不算点击(spec §9.2)。 }
  FMulti := AShift * [ssDouble, ssTriple, ssQuad] <> [];
end;

procedure TTyToolWindowGesture.BeginResize(AStartSize: Integer; const AScreenPos: TPoint);
begin
  FResizing := True;
  FSnapped := False;
  FStartSize := AStartSize;
  FStartPos := AScreenPos;
  SyncDeactivateHook;
end;

function TTyToolWindowGesture.PastThreshold(X, Y: Integer): Boolean;
var
  p: TPoint;
  d: Integer;
begin
  { 阈值按屏幕坐标、两个轴取大的(spec §9.2):只算沿条方向的话,竖着的图标条往右
    横拖永远拖不起来(TabStrip 就是这样)。坐标是捕获者的客户区。 }
  p := FCapturer.ClientToScreen(Point(X, Y));
  d := Abs(p.X - FOrigin.X);
  if Abs(p.Y - FOrigin.Y) > d then d := Abs(p.Y - FOrigin.Y);
  Result := d >= TyToolWindowDragThreshold(FBar.PPI);
end;

procedure TTyToolWindowGesture.BeginDragging;
begin
  { 防重入:上一次的临时光标、处理器、计时器万一还在(不该在),先收掉再压新的 ——
    否则 Screen 的临时光标栈上多一层,永远弹不掉。吞点击的标志按下时已经设过了。 }
  ReleaseResources;
  FState := twgsDragging;
  if Application <> nil then Application.CancelHint;
  { 控件自己的 Cursor 在捕获期间管不到别的窗口,用 Screen 的临时光标(spec §9.2)。 }
  FCursor := crDrag;
  Screen.BeginTempCursor(FCursor);
  FCursorPushed := True;
  { 图标条 / 标签行不拿焦点,Esc 到不了控件的 KeyDown:挂在 Application 的 KeyDownBefore 上。 }
  Application.AddOnKeyDownBeforeHandler(@KeyDownBefore);
  Screen.AddHandlerActiveFormChanged(@ActiveFormChanged);
  FHooked := True;
  SyncDeactivateHook;
  { 不用 AddOnIdleHandler:链上任一个把 Done 置 False,后面的就不跑;弹出菜单直接
    ReleaseCapture 抢走捕获的情况只有轮询抓得到(spec §9.2)。捕获没确认过(无头、
    没有句柄)就没有可轮询的。比的是捕获者,不是栏。 }
  FCaptureConfirmed := (FCapturer is TWinControl) and TWinControl(FCapturer).HandleAllocated
    and (GetCaptureControl = FCapturer);
  if FCaptureConfirmed then
  begin
    FCaptureTimer := TTimer.Create(nil);
    TTimer(FCaptureTimer).Interval := 100;
    TTimer(FCaptureTimer).OnTimer := @CaptureTimerTick;
    TTimer(FCaptureTimer).Enabled := True;
  end;
  { manager 记下「正在拖」:任何注册栏、manager 自己都能取消它(spec §9.2 / §9.7)。 }
  if FBar.Manager <> nil then FBar.Manager.SetDragSource(FBar);
end;

function TTyToolWindowGesture.Move(AShift: TShiftState; X, Y: Integer): TTyToolWindowGestureMove;
begin
  Result := twgmNone;
  if FResizing then
  begin
    { 丢了松开(没有 ssLeft):当作被打断,回到起点。 }
    if ssLeft in AShift then Result := twgmResize else Reset(twgeCancel);
    Exit;
  end;
  case FState of
    twgsDragging:
      { 没有 ssLeft:丢了松开,取消(spec §9.7)。 }
      if ssLeft in AShift then Result := twgmDrag else Reset(twgeCancel);
    twgsArmed:
      if not (ssLeft in AShift) then
        Reset(twgeCancel)                         { 丢了松开:武装着的回到 Idle }
      else if FDraggable and PastThreshold(X, Y) then
      begin
        BeginDragging;
        Result := twgmDragStart;
      end;
    twgsCancelled:
      { 取消之后按键已经松了:手势到此为止,悬停追踪接着来。还按着就等松开。 }
      if not (ssLeft in AShift) then
      begin
        Reset(twgeDiscard);
        Result := twgmHover;
      end;
  else
    Result := twgmHover;
  end;
end;

function TTyToolWindowGesture.Release(APart: TTyToolWindowBarPart;
  AWindow: TTyCustomToolWindow): TTyToolWindowGestureRelease;
begin
  Result := Default(TTyToolWindowGestureRelease);
  if FResizing then
  begin
    Result.Kind := twrResize;
    Result.Snapped := FSnapped;
  end
  else if FState = twgsDragging then
  begin
    Result.Kind := twrDrop;
    Result.Window := FWindow;
  end
  { Armed、落在同一个部件(同一个窗口的图标 / 标签)上、没有多击标记 → 点击;其他什么都不做。 }
  else if (FState = twgsArmed) and not FMulti and (APart = FPart)
     and ((APart <> twbpItem) or (AWindow = FWindow)) then
  begin
    Result.Kind := twrClick;
    Result.Part := FPart;
    Result.Window := FWindow;
  end;
  Reset(twgeRelease);
end;

procedure TTyToolWindowGesture.Reset(AReason: TTyToolWindowGestureEnd);
var
  dying, wasSnapped, wasDragging, wasCancelled, onTabRow: Boolean;
begin
  { 捕获者是一页(底栏标签行),或者是让出标签行的底栏自己(spec §3.7):标签行画着按下态,
    收尾之后要重画。清记录之前先记下。 }
  onTabRow := (FCapturer is TTyCustomToolWindow)
    or ((FCapturer = FBar) and (FBar.Placement = twpBottom)
        and (FPart in [twbpItem, twbpOverflow, twbpMaximize, twbpCollapse]));
  dying := csDestroying in FBar.ComponentState;
  { 拉宽:析构中只清标志 —— 回到起点要 Relayout,而栏已经拆了一半。 }
  if FResizing then
  begin
    FResizing := False;
    wasSnapped := FSnapped;
    FSnapped := False;
    if not dying then FBar.ResizeEnded(AReason, wasSnapped);
  end;
  ReleaseResources;
  wasDragging := FState = twgsDragging;
  wasCancelled := FState = twgsCancelled;
  FState := twgsIdle;
  if (AReason = twgeCancel) and (wasDragging or wasCancelled) then
    FState := twgsCancelled;
  FPart := twbpNone;
  FWindow := nil;
  FCapturer := nil;
  FMulti := False;
  FDraggable := False;
  FBar.GestureCleared(onTabRow);
end;

procedure TTyToolWindowGesture.SetCursor(ACursor: TCursor);
begin
  if (not FCursorPushed) or (ACursor = FCursor) then Exit;
  { 先压新的再弹旧的:中间不闪回原来的光标(spec §9.2)。 }
  Screen.BeginTempCursor(ACursor);
  Screen.EndTempCursor(FCursor);
  FCursor := ACursor;
end;

procedure TTyToolWindowGesture.ArmDesign(AWindow: TTyCustomToolWindow);
begin
  FDesignWindow := AWindow;
  FDesignArmed := AWindow <> nil;
end;

procedure TTyToolWindowGesture.DisarmDesign;
begin
  FDesignArmed := False;
  FDesignWindow := nil;
end;

function TTyToolWindowGesture.HasCaptureTimer: Boolean;
begin
  Result := FCaptureTimer <> nil;
end;

procedure TTyToolWindowGesture.KeyDownBefore(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  { 只吃掉 KeyDown;Esc 的 KeyUp 照样到焦点控件(spec §9.7)。 }
  if (Key = VK_ESCAPE) and (FState = twgsDragging) then
  begin
    Key := 0;
    Reset(twgeCancel);
  end;
end;

procedure TTyToolWindowGesture.ActiveFormChanged(Sender: TObject; Form: TCustomForm);
begin
  if Form <> GetParentForm(FBar) then Reset(twgeCancel);
end;

procedure TTyToolWindowGesture.CaptureTimerTick(Sender: TObject);
begin
  { 不在拖动了而计时器还在:残局,只放资源,不动手势记录。 }
  if FState <> twgsDragging then
  begin
    ReleaseResources;
    Exit;
  end;
  { CaptureChanged 从不取消(Win32 上每次正常松开都会先到);捕获被别人抢走只有轮询抓得到。 }
  if FCaptureConfirmed and (GetCaptureControl <> FCapturer) then Reset(twgeCancel);
end;

{$I tyControls.ToolWindows.DropPreview.inc}

{ --- TTyCustomToolWindowManager -------------------------------------------------- }

procedure TTyCustomToolWindowManager.BeforeDestruction;
var
  p: PTyToolWindowLife;
begin
  inherited BeforeDestruction;
  { 在自己的某个事件处理器里被释放(spec §6.6 不许):派发那几处栈上的生命格一律判死,
    处理器返回后它们不再碰本对象。在任何一层析构之前做(BeforeDestruction 先于析构体)。 }
  p := FLife;
  while p <> nil do
  begin
    p^.Alive := False;
    p := p^.Prev;
  end;
  FLife := nil;
end;

destructor TTyCustomToolWindowManager.Destroy;
begin
  { 拖到一半 manager 被释放:源栏的手势作废(spec §9.7)。 }
  CancelDrag;
  inherited Destroy;
end;

procedure TTyCustomToolWindowManager.EnterLife(var ALife: TTyToolWindowLife);
begin
  ALife.Alive := True;
  ALife.Prev := FLife;
  FLife := @ALife;
end;

procedure TTyCustomToolWindowManager.LeaveLife(var ALife: TTyToolWindowLife);
begin
  { 已死:Self 是悬垂的,一个成员都不碰(非虚方法,调用本身不解引用 Self)。 }
  if not ALife.Alive then Exit;
  FLife := ALife.Prev;
end;

procedure TTyCustomToolWindowManager.EnterEvent(var ALife: TTyToolWindowLife);
begin
  EnterLife(ALife);
  Inc(FEventDepth);
end;

procedure TTyCustomToolWindowManager.LeaveEvent(var ALife: TTyToolWindowLife);
begin
  if not ALife.Alive then Exit;
  Dec(FEventDepth);
  LeaveLife(ALife);
end;

procedure TTyCustomToolWindowManager.CancelDrag;
begin
  if FDragSource <> nil then FDragSource.ResetGesture(twgeCancel);
end;

function TTyCustomToolWindowManager.IsDragging: Boolean;
begin
  Result := FDragSource <> nil;
end;

function TTyCustomToolWindowManager.MoveFromDrop(AWindow: TTyCustomToolWindow; ATarget: TTyCustomToolWindowBar;
  ASlot: Integer): Boolean;
var
  src: TTyCustomToolWindowBar;
  life: TTyToolWindowLife;
begin
  { 这个窗口还有排着的移动也照做:拖动开始后它不会再被排队以外的路挪走,排着的那一项
    执行时会重新检查。 }
  Result := StructureAllows(AWindow, ATarget, src) and (src <> ATarget);
  if not Result then Exit;
  EnterLife(life);
  try
    { OnCanMoveWindow 里把本 manager 释放了:到此为止。 }
    Result := CanMoveWindow(AWindow, ATarget) and life.Alive;
    { 跨栏的最终位置就是槽位本身(spec §9.4:移走的不在目标栏里,不减一)。 }
    if Result then MoveNow(AWindow, ATarget, ASlot);
  finally
    LeaveLife(life);
  end;
end;

procedure TTyCustomToolWindowManager.BarChanged(ABar: TTyCustomToolWindowBar);
begin
  if (FDragSource <> nil) and (ABar <> nil)
     and ((ABar = FDragSource) or (ABar = FDragSource.FGesture.Target)) then
    CancelDrag;
end;

{ --- 钩子的基类实现 --- }

procedure TTyCustomToolWindowManager.NoteLayoutChanging(ABar: TTyCustomToolWindowBar);
begin
end;

procedure TTyCustomToolWindowManager.TryFinishLoading;
begin
end;

function TTyCustomToolWindowManager.DropTargetAt(ASource: TTyCustomToolWindowBar;
  const AScreen: TPoint; out ASlot: Integer): TTyCustomToolWindowBar;
var
  p: TPoint;
begin
  { 只有源栏自己的图标条(同没有 manager 时,spec §9.4)。 }
  p := ASource.ScreenToClient(AScreen);
  ASlot := ASource.DropSlotAt(p.X, p.Y);
  if ASlot >= 0 then Result := ASource else Result := nil;
end;

function TTyCustomToolWindowManager.QueueWindowIndex(AWindow: TTyCustomToolWindow;
  AIndex: Integer): Boolean;
begin
  Result := False;
end;

procedure TTyCustomToolWindowManager.BarRemoved(ABar: TTyCustomToolWindowBar);
begin
end;

procedure TTyCustomToolWindowManager.DragSourceChanged(ASource: TTyCustomToolWindowBar);
begin
end;

procedure TTyCustomToolWindowManager.SetDragSource(ABar: TTyCustomToolWindowBar);
begin
  if FDragSource = ABar then Exit;
  FDragSource := ABar;
  DragSourceChanged(ABar);
end;

procedure TTyCustomToolWindowManager.BarShowDropPreview(ABar: TTyCustomToolWindowBar);
begin
  ABar.ShowDropPreview;
end;

procedure TTyCustomToolWindowManager.BarHideDropPreview(ABar: TTyCustomToolWindowBar);
begin
  ABar.HideDropPreview;
end;

{ --- 给派生类的内部操作 --- }

function TTyCustomToolWindowManager.DragAllows(ASource, ATarget: TTyCustomToolWindowBar): Boolean;
begin
  Result := ASource.FGesture.AllowedFor(ATarget);
end;

function TTyCustomToolWindowManager.BarWindows(ABar: TTyCustomToolWindowBar): TTyToolWindowArray;
begin
  Result := ABar.WindowList(nil);
end;

procedure TTyCustomToolWindowManager.BarPlace(ABar: TTyCustomToolWindowBar; AWindow: TTyCustomToolWindow;
  AIndex: Integer);
begin
  ABar.PlaceWindow(AWindow, AIndex);
end;

procedure TTyCustomToolWindowManager.BarReorder(ABar: TTyCustomToolWindowBar; AWindow: TTyCustomToolWindow;
  AIndex: Integer);
begin
  ABar.ReorderWindow(AWindow, AIndex);
end;

procedure TTyCustomToolWindowManager.BarSwitch(ABar: TTyCustomToolWindowBar; AWindow: TTyCustomToolWindow);
begin
  ABar.SwitchCore(AWindow, ABar.FActive, False);
end;

procedure TTyCustomToolWindowManager.BarEnterBatch(ABar: TTyCustomToolWindowBar);
begin
  ABar.BeginLayoutBatch;
end;

procedure TTyCustomToolWindowManager.BarLeaveBatch(ABar: TTyCustomToolWindowBar);
begin
  ABar.EndLayoutBatch;
end;

procedure TTyCustomToolWindowManager.BarBeginSilent(ABar: TTyCustomToolWindowBar);
begin
  ABar.BeginSilent;
end;

procedure TTyCustomToolWindowManager.BarEndSilent(ABar: TTyCustomToolWindowBar);
begin
  ABar.EndSilent;
end;

procedure TTyCustomToolWindowManager.QuietReparent(AWindow: TTyCustomToolWindow;
  ABar: TTyCustomToolWindowBar);
begin
  AWindow.FQuietMove := True;
  try
    AWindow.Parent := ABar;
  finally
    AWindow.FQuietMove := False;
  end;
end;

procedure TTyCustomToolWindowManager.AddBar(ABar: TTyCustomToolWindowBar);
var
  i: Integer;
begin
  for i := 0 to High(FBars) do
    if FBars[i] = ABar then Exit;
  SetLength(FBars, Length(FBars) + 1);
  FBars[High(FBars)] := ABar;
  { 双向:栏被释放时本 manager 收到 opRemove,本 manager 被释放时栏收到。 }
  ABar.FreeNotification(Self);
  PlacementsChanged;
end;

procedure TTyCustomToolWindowManager.RemoveBar(ABar: TTyCustomToolWindowBar);
var
  i: Integer;
begin
  for i := 0 to High(FBars) do
    if FBars[i] = ABar then
    begin
      Delete(FBars, i, 1);
      Break;
    end;
  { 离开的是参与拖动的栏(源栏或此刻的目标栏):取消(spec §9.7)。 }
  BarChanged(ABar);
  { 别的栏正在拖、问过它:答案丢掉。它离开 manager 之后不再是目标;被释放的话同一个地址之后
    可能是另一条栏,缓存命中就是别人的答案。 }
  if FDragSource <> nil then FDragSource.FGesture.ForgetBar(ABar);
  { 离开 manager 的栏不再是排队移动的目标。 }
  BarRemoved(ABar);
  { 留下的栏的冲突提示可能没了(释放那条路经 Notification 也走到这里)。 }
  PlacementsChanged;
end;

procedure TTyCustomToolWindowManager.PlacementsChanged;
var
  i: Integer;
begin
  { 每条栏自己过滤设计期 / 加载 / 释放(ConflictMayHaveChanged)。 }
  for i := 0 to High(FBars) do
    FBars[i].ConflictMayHaveChanged;
end;

procedure TTyCustomToolWindowManager.Notification(AComponent: TComponent; Operation: TOperation);
var
  b: TTyCustomToolWindowBar;
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent is TTyCustomToolWindowBar) then
  begin
    b := TTyCustomToolWindowBar(AComponent);
    RemoveBar(b);
    { 栏只是从 Owner 摘走(RemoveComponent、InsertComponent 换 Owner),还活着、还指着本
      manager:继承的 Notification 已经把两边的 FreeNotification 拆了,本 manager 日后释放时
      它收不到通知 —— 这里替它断引用。 }
    if (b.FManager = Self) and not (csDestroying in b.ComponentState) then b.DetachManager;
  end;
  { 列表被释放(或从 Owner 摘走):清引用,回落到它的栏重新订阅。栏自己也可能收到同一条
    通知(它订阅着这个列表),谁先谁后说不准 —— 各清各的(csDestroying 过滤在 EffectiveImages)。 }
  if (Operation = opRemove) and (AComponent = FImages) then
  begin
    FImages := nil;
    NotifyImagesChanged;
  end;
end;

procedure TTyCustomToolWindowManager.SetImages(AValue: TCustomImageList);
begin
  if FImages = AValue then Exit;
  { 旧列表的 FreeNotification 不拆:它之后的 opRemove 到这里时已经不是 FImages,什么都不做
    —— 多一次通知无害,拆错一次是悬垂指针。 }
  FImages := AValue;
  if AValue <> nil then AValue.FreeNotification(Self);
  NotifyImagesChanged;
end;

procedure TTyCustomToolWindowManager.NotifyImagesChanged;
var
  i: Integer;
begin
  for i := 0 to High(FBars) do
    if not (csDestroying in FBars[i].ComponentState) then
      FBars[i].ImagesChanged;
end;

function TTyCustomToolWindowManager.IsBarUsable(ABar: TTyCustomToolWindowBar): Boolean;
var
  i: Integer;
begin
  { 与别的注册栏 Placement 相同的**每一条**都不可用,不按先来后到(spec §10.6)。
    释放中的栏已经在走:它自己不可用,也不再占着它那一侧 —— 从 csDestroying 置上到
    opRemove 把它从表里摘掉之间,留下的那一条就已经可用(UsableBar 同一条规则)。 }
  Result := (ABar <> nil) and (ABar.Manager = Self)
    and not (csDestroying in ABar.ComponentState);
  if not Result then Exit;
  for i := 0 to High(FBars) do
    if (FBars[i] <> ABar) and (FBars[i].Placement = ABar.Placement)
       and not (csDestroying in FBars[i].ComponentState) then Exit(False);
end;

function TTyCustomToolWindowManager.UsableBar(APlacement: TTyToolWindowPlacement): TTyCustomToolWindowBar;
var
  i: Integer;
begin
  { 就是 IsBarUsable 答 True 的那一条:同 Placement、不在释放中的正好一条。 }
  for i := 0 to High(FBars) do
    if (FBars[i].Placement = APlacement) and IsBarUsable(FBars[i]) then Exit(FBars[i]);
  Result := nil;
end;

function TTyCustomToolWindowManager.StructureAllows(AWindow: TTyCustomToolWindow; ATarget: TTyCustomToolWindowBar;
  out ASource: TTyCustomToolWindowBar): Boolean;
const
  Busy = [csLoading, csDestroying];
begin
  Result := False;
  ASource := nil;
  if (AWindow = nil) or (ATarget = nil) then Exit;
  ASource := AWindow.Bar;
  if ASource = nil then Exit;
  { 两条栏都注册在本 manager 上。 }
  if (ASource.Manager <> Self) or (ATarget.Manager <> Self) then Exit;
  { manager、窗口、两条栏都不在加载 / 释放中。 }
  if Busy * (ComponentState + AWindow.ComponentState + ASource.ComponentState
     + ATarget.ComponentState) <> [] then Exit;
  { 同一个窗体(spec §9.1:不做跨窗体)。 }
  if GetParentForm(ASource) <> GetParentForm(ATarget) then Exit;
  { 侧 ↔ 底永远不行,设计期也不行 —— 所以不用 MovesAcrossBarKinds(它对设计期放行)。 }
  if BarKindsDiffer(ASource, ATarget) then Exit;
  { 冲突的栏只能栏内调顺序(spec §10.6)。 }
  Result := (ASource = ATarget) or (IsBarUsable(ASource) and IsBarUsable(ATarget));
end;

function TTyCustomToolWindowManager.CanMoveWindow(AWindow: TTyCustomToolWindow;
  ATargetBar: TTyCustomToolWindowBar): Boolean;
var
  src: TTyCustomToolWindowBar;
  allow: Boolean;
  life: TTyToolWindowLife;
begin
  Result := StructureAllows(AWindow, ATargetBar, src);
  if not Result then Exit;
  { 同一条栏就是调顺序,永远行;设计期不问事件(spec §6.6)。 }
  if (src = ATargetBar) or (csDesigning in ComponentState) then Exit(True);
  allow := True;
  if Assigned(FOnCanMoveWindow) then
  begin
    EnterEvent(life);
    try
      FOnCanMoveWindow(Self, AWindow, ATargetBar, allow);
    finally
      LeaveEvent(life);
    end;
  end;
  Result := allow;
end;

function TTyCustomToolWindowManager.MovedEventAllowed(ASource: TTyCustomToolWindowBar): Boolean;
const
  Quiet = [csDesigning, csLoading, csDestroying];
begin
  Result := Assigned(FOnWindowMoved) and (ASource <> nil)
    and (Quiet * (ComponentState + ASource.ComponentState) = []);
end;

procedure TTyCustomToolWindowManager.WindowMoved(AWindow: TTyCustomToolWindow; ASource: TTyCustomToolWindowBar;
  AOldIndex: Integer);
var
  life: TTyToolWindowLife;
begin
  if not MovedEventAllowed(ASource) then Exit;
  EnterEvent(life);
  try
    FOnWindowMoved(Self, AWindow, ASource, AOldIndex);
  finally
    LeaveEvent(life);
  end;
end;

procedure TTyCustomToolWindowManager.MoveNow(AWindow: TTyCustomToolWindow; ATarget: TTyCustomToolWindowBar;
  AIndex: Integer);
begin
  { 跟运行时直接改 Parent 同一条路(spec §3.2 / §9.5)。AIndex 已经是换算过的(MoveWindow 入口
    把 -1 换成 MaxInt;拖放给的槽位不会是负的)。 }
  CommitCrossMove(AWindow, AWindow.Bar, ATarget, AIndex);
end;

function TTyCustomToolWindowManager.BarCountForTest: Integer;
begin
  Result := Length(FBars);
end;

procedure TyToolWindowOverflowMenuAnchor(const AOverflow: TRect;
  APlacement: TTyToolWindowPlacement; ARightToLeft: Boolean; out APoint: TPoint;
  out AAlignment: TPopupAlignment);
var
  opensLeft: Boolean;
begin
  { 底栏:从溢出按钮底边、按阅读起点往下开(spec §7.3)—— LTR 左沿、RTL 右沿,都是 paLeft
    (TyPopupAnchorShift 在 RTL 下把「贴阅读起点」换成贴右沿)。 }
  if APlacement = twpBottom then
  begin
    if ARightToLeft then APoint := Point(AOverflow.Right, AOverflow.Bottom)
    else APoint := Point(AOverflow.Left, AOverflow.Bottom);
    AAlignment := paLeft;
    Exit;
  end;
  opensLeft := APlacement = twpRight;
  if opensLeft then APoint := Point(AOverflow.Left, AOverflow.Top)
  else APoint := Point(AOverflow.Right, AOverflow.Top);
  { 物理上往左开:LTR 下是「贴阅读终点」(paRight),RTL 下阅读起点就在右边(paLeft)。 }
  if opensLeft <> ARightToLeft then AAlignment := paRight
  else AAlignment := paLeft;
end;

initialization
  { 运行时 .lfm 按类名实例化流里的子对象,三个都要注册;TTyToolWindowManager 在
    tyControls.ToolWindows.Manager 里注册。 }
  RegisterClass(TTyToolWindow);
  RegisterClass(TTyToolWindowActions);
  RegisterClass(TTyToolWindowBar);
end.
