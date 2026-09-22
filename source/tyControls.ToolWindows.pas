unit tyControls.ToolWindows;
{$mode objfpc}{$H+}

{ IDE 工作台的侧栏 / 底栏。设计定稿见
  docs/superpowers/specs/2026-09-17-toolwindow-workbench-design.md。
  四个类同在一个单元:窗口与栏互相引用,拆单元只会多一圈前向声明。 }

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LMessages,
  tyControls.Types, tyControls.Base, tyControls.Component, tyControls.Painter,
  tyControls.StyleModel, tyControls.StrConsts;

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

  { 拖动阈值(逻辑像素)与点击防抖(毫秒)。 }
  TyToolWindowDragThresholdPx = 6;
  TyToolWindowClickGuardMs    = 300;

type
  TTyToolWindowPlacement = (twpLeft, twpRight, twpBottom);
  TTyToolWindowHeaderMode = (twhNone, twhSide, twhBottom);

  TTyToolWindowBar = class;
  TTyToolWindowActions = class;
  TTyToolWindowManager = class;

  { 标题行的一个可点部件。返回它的命中测跟底栏一起在 B 期落地。 }
  TTyToolWindowZone = (twzNone, twzTab, twzOverflow, twzSeparator, twzMaximize, twzCollapse);

  { 一个标签 / 一个图标的槽位。ItemIndex 是**窗口序号**,不是排布序号 ——
    当前页被强制留在条上时,已排布的项不再是窗口列表的前缀。 }
  TTyToolWindowSlot = record
    ItemIndex: Integer;
    ItemRect: TRect;
  end;
  TTyToolWindowSlots = array of TTyToolWindowSlot;

  { 可见计划:按排布顺序列出的**窗口序号**。 }
  TTyToolWindowPlan = array of Integer;

  { 一排宽度:设备像素,按**窗口序号**索引。 }
  TTyToolWindowWidths = array of Integer;

  { 排布的全部输入。尺寸一律是**设备像素**,调用方缩放好再传。 }
  TTyToolWindowHeaderInput = record
    Mode: TTyToolWindowHeaderMode;
    RowWidth, RowHeight: Integer;
    Pad, Gap: Integer;
    ActionsWidth: Integer;      { 操作区 raw 首选宽;0 = 没有操作区 }
    TabWidths: TTyToolWindowWidths; { 底栏:每个窗口的标签想要的宽 }
    ActiveIndex: Integer;
    TabAreaMin: Integer;
    ButtonSize: Integer;        { 底栏:最大化 / 收起 }
    SeparatorWidth: Integer;
    OverflowWidth: Integer;
    RightToLeft: Boolean;
  end;

  TTyToolWindowHeaderGeom = record
    Caption: TRect;             { 侧栏 }
    Actions: TRect;
    TabArea: TRect;             { 底栏:标签可用区 }
    Tabs: TTyToolWindowSlots;   { 底栏:真正排上去的标签 }
    Overflow: TRect;
    Separator: TRect;
    Maximize: TRect;
    Collapse: TRect;
    Hidden: TTyToolWindowPlan;  { 底栏:收进溢出菜单的窗口序号 }
  end;

  { 操作区那一排的一项输入(设备像素)。宽、高各按 max(本值, 下限) 算:TTyButton 按标题
    设 MinWidth(Button.pas:702),SetBounds 会把它撑得比 Width 宽 —— 只按 Width 排,
    撑宽的那一个就压到下一个身上。 }
  TTyToolWindowFlowItem = record
    Width, Height, MinWidth, MinHeight: Integer;
  end;
  TTyToolWindowFlowItems = array of TTyToolWindowFlowItem;

  { 操作区那一排的答案:每项的矩形(区域内坐标,与输入同序)和整排的 raw 首选尺寸。 }
  TTyToolWindowFlow = record
    Rects: array of TRect;
    Size: TSize;
  end;

  { 操作区的可见子控件,Controls[] 顺序,与 TTyToolWindowFlowItems 一一对应。 }
  TTyToolWindowKids = array of TControl;

  { GetStyleTypeKey 在 TTyCustomControl 上是 abstract,不覆写就等于注册了一个
    「一解析样式就抛 EAbstractError」的类 —— 而 RegisterClass 已经把它交给流式化了。
    类型键是契约不是实现,A 期就钉死。 }
  TTyToolWindow = class(TTyCustomControl)
  private
    FImageName: string;
    FImageIndex: Integer;
    FStripHint: string;
    FOnShow: TNotifyEvent;
    FOnHide: TNotifyEvent;
    { 标题行高的 token 那一项的缓存,键 = (PPI, model 身份, 主题版本, RTL, 标题行模式)。
      「有没有缓存」单拿一个布尔答,不拿 -1 当哨兵:token 是度量值,而 TyEvalLength
      不钳(Css.Values.pas:373),皮肤或 StyleOverride 里写 -1px 就真的解析成 -1 ——
      哨兵一旦跟真值撞上,缓存永远命中不了,Invalidate 里「上一次有值吗」也从此恒假,
      之后任何一次换主题都不再重排。操作区那一项不进这里,见 HeaderHeightAt。 }
    FHeaderPxCache: Integer;
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
    function ImageIndexIsStored: Boolean;
    function GetBar: TTyToolWindowBar;
    function GetActions: TTyToolWindowActions;
    function HeaderTokenPx: Integer;
    function HeaderHeightAt(APPI: Integer): Integer;
    function HeaderRowIn(const AClient: TRect; APPI: Integer): TRect;
    function ActionsPreferredSize(APPI: Integer): TSize;
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
    { 全库 76 处 RenderTo 里 71 处是 protected,两个近亲 TTyTabSheet / TTyCard 也是:
      画自己不是给外面用的接口。测试走探针子类。 }
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    { 栏切页就是开关 Visible(Task 5/10),所以这条消息就是本窗口的激活边 ——
      与 TCustomPage / TTyTabSheet 发 OnShow / OnHide 的是同一个钩子。 }
    procedure CMVisibleChanged(var Msg: TLMessage); message CM_VISIBLECHANGED;
    procedure DoShow; virtual;
    procedure DoHide; virtual;
    { 栏换当前页时那一批 Visible 切换不是用户眼里的「显示 / 隐藏」,spec §6.6 要求
      它们不发 OnShow / OnHide。三个调用者:Task 5 的 TTyToolWindowBar.ActivateWindow、
      Task 10 的收起 / 展开、C 期把存下来的布局应用回去那一遍。
      计数而不是布尔:布局应用会套着调 ActivateWindow,一个布尔会被里层提前解除。
      csLoading 挡不住这三个 —— 后两个发生时流式加载早就结束了。

      **调用方必须 try/finally**。负方向钳住了(EndSilentVisibility 不减到 0 以下),
      正方向钳不住:Begin 与 End 之间任何一处抛异常,计数就卡在 0 以上,这个窗口的
      OnShow / OnHide 从此再也不响 —— 而它是静默的,没有一条断言会指向那里。
      上面三个调用者一个都不例外。 }
    procedure BeginSilentVisibility;
    procedure EndSilentVisibility;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
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
    { 标题行排布的**答案**,一处算 —— 绘制(RenderTo)与摆操作区(Task 4 的
      CustomAlignPosition)必须拿同一份几何。只共享输入、各自再跑一遍排布的话,
      画出来的和点得中的照样会错开。行高在这里钳进 AClient,所以控件比标题行还矮时
      操作区不会被摆到控件外面。照 TTyCard.LayoutAtPPI(Card.pas:181)。
      返回的几何是**行内局部坐标**(0,0 在行的左上角);AClient 只用来定行宽、钳行高。 }
    function HeaderGeomAt(const AClient: TRect; APPI: Integer): TTyToolWindowHeaderGeom;
    { 已有就返回第一个操作区,没有就建一个(spec §3.1 / §4):Owner 是窗口的 Owner
      (窗体拥有,设计期容器的契约),Parent 是本窗口,TabOrder 0。 }
    function EnsureActions: TTyToolWindowActions;
    function HeaderHeightPx: Integer;
    function HeaderRowRect: TRect;
    function BodyRect: TRect;
    property Bar: TTyToolWindowBar read GetBar;
    property Actions: TTyToolWindowActions read GetActions;
  published
    property Caption;
    property ImageName: string read FImageName write FImageName;
    property ImageIndex: Integer read FImageIndex write FImageIndex
      stored ImageIndexIsStored default -1;
    property StripHint: string read FStripHint write FStripHint;
    property StyleClass;
    { 栏推给窗口、窗口再推给操作区;不进 .lfm(读进来的时机在注册之后,两边会漂开)。 }
    property Controller stored False;
    property Left stored False;
    property Top stored False;
    property Width stored False;
    property Height stored False;
    property TabOrder stored False;
    property Visible stored False;
    { 切页的触发边是 Visible —— 栏把当前页显示出来、把上一页藏起来(Task 5/10),
      而这两个事件就从 CM_VISIBLECHANGED 发,名字、签名、触发边都同 TCustomPage。 }
    property OnShow: TNotifyEvent read FOnShow write FOnShow;
    property OnHide: TNotifyEvent read FOnHide write FOnHide;
  end;

  { 标题行尾端的操作区(spec §4)。只由组件编辑器的「添加操作区」或 EnsureActions 建,
    位置和尺寸永远由所在窗口排:Align 钉死 alCustom,Align / Anchors 不 published;
    AutoSize、ChildSizing、BorderSpacing 在这个类上不起作用,子控件由它自己排成一排。 }
  TTyToolWindowActions = class(TTyCustomControl)
  private
    FInLayout: Boolean;
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
    { raw 首选尺寸,设备像素,按给定 PPI —— 窗口排标题行、LCL 的 GetPreferredSize、
      自己排子控件,问的都是这一处。**不**走 LCL 的 GetPreferredSize:那边有缓存,
      InsertControl 不作废它(wincontrol.inc:6392),而且答不了别的 PPI。
      运行时一个可见子控件都没有 → (0, 0);设计期空着 → 边长为 token 的方槽。 }
    function PreferredSizeAt(APPI: Integer): TSize;
    { 设计期提示画在哪里(客户区坐标,按自己字体的密度)—— Paint 画提示用的就是这个框。
      窗口认的那一个、以及运行时,答空矩形。 }
    function NoteRect: TRect;
  published
    { 由窗口推送,不进 .lfm(同 TTyToolWindow)。 }
    property Controller stored False;
    { 在窗口里由标题行排出来;孤儿的位置是用户摆的,照常存。 }
    property Left stored IsBoundsStored;
    property Top stored IsBoundsStored;
    property Width stored IsBoundsStored;
    property Height stored IsBoundsStored;
  end;

  TTyToolWindowBar = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
  end;

  { A 期只建壳:栏的 Manager 属性要到 C 期才接线,但类名先占住,
    免得 B 期的测试和 .lfm 里写出两个名字。
    继承 TTyComponent(不是 TComponent):全库非可视组件都从它来,它带着
    对象查看器里那个只读 Version。 }
  TTyToolWindowManager = class(TTyComponent)
  end;

{ --- 纯规则 / 几何(无控件、无句柄、无主题,可无头测) ------------------------ }

{ 按顺序放,遇到第一个放不下的就停;当前页不在里面就追加到末尾,再从它前面一个
  开始往前挤,直到放得下。返回的是**窗口序号**的可见计划。
  有没有东西被收起来,调用方自己算 `Length(计划) < 窗口总数` ——
  多一个 out 参数买不到任何信息,只会多一处能跟这个恒等式不一致的地方。 }
function TyToolWindowVisiblePlan(AAvail: Integer; const AWidths: array of Integer;
  AActiveIndex, AOverflowWidth: Integer): TTyToolWindowPlan;

function TyToolWindowHeaderLayout(const AInput: TTyToolWindowHeaderInput): TTyToolWindowHeaderGeom;

{ 把排好的整套几何按行宽镜像(spec §7.3)。每个矩形字段和每个槽位都过一遍,
  所以 B 期给 Geom 加部件不用记得回来添一行。

  就地改,而且**不幂等**:TyToolWindowHeaderLayout 在 RightToLeft 为真时已经替你调过了,
  拿到它的结果别再调第二次 —— 镜像两次等于没镜像,而 LTR 那边照样全绿。
  ARowWidth 必须就是排布时用的那个 RowWidth;传成别的(比如此刻的 ClientWidth)不会报错,
  整套几何会整体平移,同样不会红。 }
procedure TyToolWindowFlipAll(var AGeom: TTyToolWindowHeaderGeom; ARowWidth: Integer);

{ 两套几何是否一模一样:每个矩形字段、每个标签槽(窗口序号 + 矩形)、收进溢出菜单的
  序号都比。同 TyToolWindowFlipAll,一处过完所有字段 —— 只比手挑的几个,B 期标签宽变了
  而控件尺寸没变,窗口就会 blit 出旧的那一帧。 }
function TyToolWindowSameGeom(const A, B: TTyToolWindowHeaderGeom): Boolean;

{ 操作区自己那一排(spec §4):按顺序从左往右,两端各 APad、之间 AGap;每项宽按
  max(Width, MinWidth)、高按 max(Height, MinHeight),在 AAvailH 里垂直居中。整排比
  AAvailW 宽时贴尾端(裁掉的是开头的);ARightToLeft 时按 AAvailW 整排镜像。
  Size 与 AAvailW / AAvailH 无关;一项都没有时 Size = (0, 0)、Rects 为空。 }
function TyToolWindowActionsFlow(const AItems: array of TTyToolWindowFlowItem;
  AAvailW, AAvailH, APad, AGap: Integer; ARightToLeft: Boolean): TTyToolWindowFlow;

{ 图标条 / 标签行的插入槽:按已排布项的中点分。返回 0..N 的**窗口序号**位置。 }
function TyToolWindowSlotAt(const ASlots: TTyToolWindowSlots; X, Y: Integer;
  AVertical: Boolean; ACount: Integer): Integer;

{ 图标条排布(竖直)。 }
function TyToolWindowStripLayout(AStripWidth, AStripHeight, AItemSize, AOverflowSize: Integer;
  ACount, AActiveIndex: Integer): TTyToolWindowSlots;

function TyToolWindowDragThreshold(APPI: Integer): Integer;

implementation

{ --- TTyToolWindow ------------------------------------------------------------ }

constructor TTyToolWindow.Create(AOwner: TComponent);
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

destructor TTyToolWindow.Destroy;
begin
  FPaintCache.Free;
  inherited Destroy;
end;

function TTyToolWindow.GetStyleTypeKey: string;
begin
  Result := 'TyToolWindow';
end;

function TTyToolWindow.ImageIndexIsStored: Boolean;
begin
  { 名字是持久键,序号只在名字给不出答案时才进流。 }
  Result := (FImageName = '') and (FImageIndex >= 0);
end;

function TTyToolWindow.GetBar: TTyToolWindowBar;
begin
  if Parent is TTyToolWindowBar then Result := TTyToolWindowBar(Parent)
  else Result := nil;
end;

function TTyToolWindow.GetActions: TTyToolWindowActions;
var
  i: Integer;
begin
  { 一个窗口只认 Controls[] 里的第一个操作区;粘贴等途径多出来的不参与标题行。
    不缓存:子控件增删、调顺序都不用再记得回来作废什么。 }
  for i := 0 to ControlCount - 1 do
    if Controls[i] is TTyToolWindowActions then
      Exit(TTyToolWindowActions(Controls[i]));
  Result := nil;
end;

procedure TTyToolWindow.TextChanged;
begin
  inherited TextChanged;
  { 标题就画在自己的标题行里(见 RenderTo),不重画就停在上一句。 }
  Invalidate;
end;

function TTyToolWindow.HeaderMode: TTyToolWindowHeaderMode;
begin
  { 只看所在栏的**位置** —— 不看哪页是当前页,否则切页时正文会跳。
    而位置(Placement)是 Task 5 的活,今天栏还答不出来;A 期也只有侧栏,
    twhBottom 连同它那一支标题行排布都在 B 期。Task 5 补上 Placement 时,
    这里要跟着变成 `if Bar.Placement = twpBottom then twhBottom else twhSide`。 }
  if Parent is TTyToolWindowBar then Result := twhSide
  else Result := twhNone;
end;

function TTyToolWindow.HeaderInput(APPI, ARowWidth: Integer): TTyToolWindowHeaderInput;
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
  { 镜像整套几何靠这一个字段。没有操作区时标题占的是对称的那一整条,镜像前后一模一样;
    有操作区时它就是看得见的位置差 —— 操作区到左端、标题到它右边,
    TestRightToLeftPutsTheActionsLeftAndTheCaptionRightOfIt 守着。 }
  Result.RightToLeft := IsRightToLeft;
end;

{ 标题行高的 **token 那一项**,带缓存,按自己字体的像素密度算。
  单独成一个过程是为了 Invalidate:它要比「主题动了没有」,而比的必须是同一个量 ——
  HeaderHeightPx 的返回值是 max(这一项, 操作区) 再钳到下限 1,token 为 0 时它永远不等于
  这一项,于是悬停、焦点、主题广播 —— 每一次重画都会整控件重排一遍。 }
function TTyToolWindow.HeaderTokenPx: Integer;
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
      看见 0 <> 26、每次都整控件重排。C 期应用布局时窗口暂时脱离栏、跨栏移动的中间态
      都会走到这里。 }
    if mode = twhNone then
      FHeaderPxCache := 0
    else
      FHeaderPxCache := MulDiv(ActiveController.Metric(TyToolWindowHeaderHeightVar,
        TyToolWindowHeaderHeightDef), Font.PixelsPerInch, 96);
    FHeaderPxAnchor := TObject(mdl);
    FHeaderPxVer := ver;
    FHeaderPxPPI := Font.PixelsPerInch;
    FHeaderPxRTL := IsRightToLeft;
    FHeaderPxMode := mode;
    FHeaderPxValid := True;
  end;
  Result := FHeaderPxCache;
end;

{ 操作区的首选尺寸(设备像素,按给定 PPI),**一处答**:标题行高拿它的高钳底、排布
  拿它的宽留位。两边各问各的话改一处漏一处,画出来的那条和挖出来的正文就会错开,
  而且不会红。只认第一个操作区(Actions),多出来的不进标题行。 }
function TTyToolWindow.ActionsPreferredSize(APPI: Integer): TSize;
var
  act: TTyToolWindowActions;
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
function TTyToolWindow.HeaderHeightAt(APPI: Integer): Integer;
var
  actionsPx: Integer;
begin
  if HeaderMode = twhNone then Exit(0);
  if APPI = Font.PixelsPerInch then Result := HeaderTokenPx
  else Result := MulDiv(ActiveController.Metric(TyToolWindowHeaderHeightVar,
    TyToolWindowHeaderHeightDef), APPI, 96);
  { 操作区那一项**不缓存**:子控件增删 / 显隐 / 改尺寸都会触发整窗体自顶向下重排,
    现取就能跟上。底栏模式下由栏统一算(B 期),A 期两种模式都按本窗口算。 }
  actionsPx := ActionsPreferredSize(APPI).cy;
  if actionsPx > Result then Result := actionsPx;
  if Result < 1 then Result := 1;
end;

{ 标题行在给定客户区里占的那一条,**钳进这个客户区**。不钳的话控件比标题行还矮时
  (栏拖到很窄、或者正在动画)HeaderRowRect 会报出一个比控件还高的矩形,Task 4 的
  CustomAlignPosition 就照着它把操作区摆到控件外面去。一处钳 —— 正文区
  (AdjustClientRect)、HeaderGeomAt、HeaderRowRect、RenderTo 问的是同一条。
  照 TTyCard.LayoutAtPPI(Card.pas:181)。 }
function TTyToolWindow.HeaderRowIn(const AClient: TRect; APPI: Integer): TRect;
var
  clientH, h: Integer;
begin
  clientH := AClient.Bottom - AClient.Top;
  if clientH < 0 then clientH := 0;
  h := HeaderHeightAt(APPI);
  if h > clientH then h := clientH;
  Result := Rect(AClient.Left, AClient.Top, AClient.Right, AClient.Top + h);
end;

function TTyToolWindow.HeaderGeomAt(const AClient: TRect; APPI: Integer): TTyToolWindowHeaderGeom;
var
  inp: TTyToolWindowHeaderInput;
  row: TRect;
begin
  row := HeaderRowIn(AClient, APPI);
  inp := HeaderInput(APPI, row.Right - row.Left);
  { HeaderInput 手上没有客户区,答的是没钳过的行高;钳在这里,一处。 }
  inp.RowHeight := row.Bottom - row.Top;
  Result := TyToolWindowHeaderLayout(inp);
end;

function TTyToolWindow.EnsureActions: TTyToolWindowActions;
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

function TTyToolWindow.HeaderHeightPx: Integer;
begin
  { 按自己字体的像素密度问的那一问,**没钳过**。正文区(AdjustClientRect)和
    HeaderRowRect 要的是钳进客户区的那一条,走 HeaderRowIn,不走这里。 }
  Result := HeaderHeightAt(Font.PixelsPerInch);
end;

function TTyToolWindow.HeaderRowRect: TRect;
begin
  Result := HeaderRowIn(Rect(0, 0, ClientWidth, ClientHeight), Font.PixelsPerInch);
end;

function TTyToolWindow.BodyRect: TRect;
begin
  { 查询就调自己的 AdjustClientRect —— 正文区只有一个定义,手摆和对齐摆落在同一处。 }
  Result := ClientRect;
  AdjustClientRect(Result);
end;

procedure TTyToolWindow.AdjustClientRect(var ARect: TRect);
begin
  inherited AdjustClientRect(ARect);
  { 正文从钳过的标题行底下开始 —— 跟画出来的那一条、摆操作区的那一条是同一处钳。 }
  ARect.Top := HeaderRowIn(ARect, Font.PixelsPerInch).Bottom;
end;

function TTyToolWindow.ChildClassAllowed(ChildClass: TClass): Boolean;
begin
  { 用 InheritsFrom 不用 = :派生类同样不许进来。设计期面板拖放和「改变父控件」都问这里;
    粘贴漏过去的由孤儿模式显示出来(spec §11),不在 CheckNewParent 里抛异常。 }
  Result := inherited ChildClassAllowed(ChildClass)
    and not ChildClass.InheritsFrom(TTyToolWindow)
    and not ChildClass.InheritsFrom(TTyToolWindowBar);
end;

procedure TTyToolWindow.AlignControls(AControl: TControl; var RemainingClientRect: TRect);
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

procedure TTyToolWindow.CustomAlignPosition(AControl: TControl; var ANewLeft, ANewTop,
  ANewWidth, ANewHeight: Integer; var AlignRect: TRect; AlignInfo: TAlignInfo);
var
  g: TTyToolWindowHeaderGeom;
  body: TRect;
  sz: TSize;
begin
  if not (AControl is TTyToolWindowActions) then
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
  sz := TTyToolWindowActions(AControl).PreferredSizeAt(Font.PixelsPerInch);
  ANewLeft := body.Left;
  ANewTop := body.Top;
  ANewWidth := sz.cx;
  ANewHeight := sz.cy;
end;

procedure TTyToolWindow.RelayoutHeader;
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

procedure TTyToolWindow.Invalidate;
var
  old: Integer;
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
    重画都会整控件重排一遍;Task 4 的操作区一旦高过 token,同样如此。 }
  old := FHeaderPxCache;
  hadOld := FHeaderPxValid;
  if (not FRelayouting) and hadOld and (HeaderTokenPx <> old) then
    RelayoutHeader;
  inherited Invalidate;
end;

procedure TTyToolWindow.AutoAdjustLayout(AMode: TLayoutAdjustmentPolicy;
  const AFromPPI, AToPPI, AOldFormWidth, ANewFormWidth: Integer);
begin
  inherited AutoAdjustLayout(AMode, AFromPPI, AToPPI, AOldFormWidth, ANewFormWidth);
  { 不用手动作废缓存:PPI 和 RTL 本来就是缓存键的一部分,键自己会答「变了」。
    这里要做的只是重排 —— 内缩量变了,alClient 子控件得重新摆。 }
  RelayoutHeader;
end;

procedure TTyToolWindow.CMBiDiModeChanged(var Msg: TLMessage);
begin
  inherited;
  RelayoutHeader;
end;

procedure TTyToolWindow.CMVisibleChanged(var Msg: TLMessage);
begin
  inherited;
  { spec §6.6 的事件表:设计期不发(设计器摆控件、点页签,切的都是 Visible),栏换
    当前页的那一批也不发。这两种都不是 csLoading 能挡的 —— 栏在 Loaded 里应用
    ActiveIndex、加载收尾时应用挂起的布局计划,发生时 csLoading 早已清掉。 }
  if (csDesigning in ComponentState) or (FSilentVisibility > 0) then Exit;
  if Visible then DoShow else DoHide;
end;

procedure TTyToolWindow.BeginSilentVisibility;
begin
  Inc(FSilentVisibility);
end;

procedure TTyToolWindow.EndSilentVisibility;
begin
  { 钳住 0:没配对的 End 把计数压到负数的话,后面每一个 Begin 都只是从负数往上爬,
    抑制口就再也关不上了 —— 而那时事件照发,没有一条断言会指向这里。 }
  if FSilentVisibility > 0 then Dec(FSilentVisibility);
end;

procedure TTyToolWindow.DoShow;
begin
  if Assigned(FOnShow) then FOnShow(Self);
end;

procedure TTyToolWindow.DoHide;
begin
  if Assigned(FOnHide) then FOnHide(Self);
end;

procedure TTyToolWindow.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S, hdrS: TTyStyleSet;
  R, hdr: TRect;
  g: TTyToolWindowHeaderGeom;
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
      hdrS := ActiveController.Model.ResolveStyle('TyToolWindowHeader',
        TyStyleClassFor(Self, StyleClass), [tysNormal]);
      if tpBackground in hdrS.Present then
        P.FillBackground(hdr, hdrS.Background, 0);
      g := HeaderGeomAt(R, APPI);
      { 标题拿下整个剩余跨度,放不下由 DrawText 自己出省略号。 }
      if (Caption <> '') and (g.Caption.Right > g.Caption.Left) then
        P.DrawText(g.Caption, Caption, hdrS.FontName, ResolveFontSize(hdrS),
          hdrS.FontWeight, hdrS.TextColor, taLeftJustify, tlCenter, True);
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyToolWindow.Paint;
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

{ --- TTyToolWindowActions ----------------------------------------------------- }

constructor TTyToolWindowActions.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { 两个 KeepChild 标志:用户在对象查看器里开 AutoSize,TWinControl.DoAutoSize 会把
    子控件往左上挪(wincontrol.inc:3441-3476),和这里自己的排列互相覆盖。 }
  ControlStyle := ControlStyle + [csAcceptsControls, csDesignFixedBounds, csNoFocus,
    csAutoSizeKeepChildLeft, csAutoSizeKeepChildTop];
  inherited SetAlign(alCustom);
  { 构造里一个子对象都不建 —— 建了会在流式加载时翻倍。 }
end;

function TTyToolWindowActions.GetStyleTypeKey: string;
begin
  Result := 'TyToolWindowActions';
end;

procedure TTyToolWindowActions.SetAlign(Value: TAlign);
begin
  { 位置由所在窗口的 CustomAlignPosition 定,Align 不接受别的值。 }
  inherited SetAlign(alCustom);
end;

function TTyToolWindowActions.ChildClassAllowed(ChildClass: TClass): Boolean;
begin
  { 用 InheritsFrom 不用 = :派生类同样不许进来。 }
  Result := inherited ChildClassAllowed(ChildClass)
    and not ChildClass.InheritsFrom(TTyToolWindow)
    and not ChildClass.InheritsFrom(TTyToolWindowBar)
    and not ChildClass.InheritsFrom(TTyToolWindowActions);
end;

function TTyToolWindowActions.IsBoundsStored: Boolean;
begin
  Result := not (Parent is TTyToolWindow);
end;

function TTyToolWindowActions.IsUsedByWindow: Boolean;
begin
  Result := (Parent is TTyToolWindow) and (TTyToolWindow(Parent).Actions = Self);
end;

function TTyToolWindowActions.IsControlVisible: Boolean;
begin
  Result := inherited IsControlVisible;
  { 状态一翻(第一个被删掉、孤儿被放回窗口)不用谁来通知:RemoveControl / InsertControl
    都会走到整窗体的 DoAllAutoSize,它对整棵树重新问一遍这里(UpdateShowingRecursive)。 }
  if Result and not (csDesigning in ComponentState) and not IsUsedByWindow then
    Result := False;
end;

function TTyToolWindowActions.HasVisibleChild: Boolean;
var
  i: Integer;
begin
  for i := 0 to ControlCount - 1 do
    if Controls[i].IsControlVisible then Exit(True);
  Result := False;
end;

function TTyToolWindowActions.MetricPx(const AName: string; ADefault, APPI: Integer): Integer;
begin
  Result := MulDiv(ActiveController.Metric(AName, ADefault), APPI, 96);
  { 同 TyToolWindowHeaderLayout:度量值不钳(TyEvalLength),负的内距 / 间距按 0 算。 }
  if Result < 0 then Result := 0;
end;

function TTyToolWindowActions.FlowInput(APPI: Integer;
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

function TTyToolWindowActions.RowSizeAt(APPI: Integer): TSize;
var
  kids: TTyToolWindowKids;
begin
  Result := TyToolWindowActionsFlow(FlowInput(APPI, kids), 0, 0,
    MetricPx(TyToolWindowHeaderPadVar, TyToolWindowHeaderPadDef, APPI),
    MetricPx(TyToolWindowHeaderGapVar, TyToolWindowHeaderGapDef, APPI), False).Size;
end;

function TTyToolWindowActions.PreferredSizeAt(APPI: Integer): TSize;
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

procedure TTyToolWindowActions.CalculatePreferredSize(var PreferredWidth,
  PreferredHeight: Integer; WithThemeSpace: Boolean);
var
  sz: TSize;
begin
  { LCL 的 GetPreferredSize(raw) 答的也是这一处,不另算一遍。 }
  sz := PreferredSizeAt(Font.PixelsPerInch);
  PreferredWidth := sz.cx;
  PreferredHeight := sz.cy;
end;

function TTyToolWindowActions.NoteText: string;
begin
  if Parent is TTyToolWindow then Result := rsTyToolWindowActionsExtra
  else Result := rsTyToolWindowActionsOrphan;
end;

function TTyToolWindowActions.NoteStyle: TTyStyleSet;
begin
  Result := ActiveController.Model.ResolveStyle('TyToolWindowNote',
    TyStyleClassFor(Self, StyleClass), [tysNormal]);
end;

function TTyToolWindowActions.NoteLeadAt(APPI: Integer): Integer;
begin
  { 粘贴一个现成的操作区,进来的就是带按钮的多余操作区(spec §4 点名的场景)。子控件照常
    从前导边排,提示排在那一排后面 —— 从 pad 开始画的话前半截压在按钮底下。 }
  if HasVisibleChild then
    Result := RowSizeAt(APPI).cx + MetricPx(TyToolWindowHeaderGapVar, TyToolWindowHeaderGapDef, APPI)
  else
    Result := MetricPx(TyToolWindowHeaderPadVar, TyToolWindowHeaderPadDef, APPI);
end;

function TTyToolWindowActions.NoteRectIn(const AClient: TRect; APPI: Integer): TRect;
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

function TTyToolWindowActions.NoteRect: TRect;
begin
  { Paint 按 ClientRect、Font.PixelsPerInch 画(见 Paint → RenderTo),这里问的是同一个框。 }
  Result := NoteRectIn(Rect(0, 0, ClientWidth, ClientHeight), Font.PixelsPerInch);
end;

function TTyToolWindowActions.StrayDesignSize(APPI: Integer): TSize;
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

procedure TTyToolWindowActions.ConstrainedResize(var MinWidth, MinHeight, MaxWidth,
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

procedure TTyToolWindowActions.AlignControls(AControl: TControl; var RemainingClientRect: TRect);
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

procedure TTyToolWindowActions.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
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

procedure TTyToolWindowActions.Paint;
begin
  { 不做绘制缓存:它小,而且子控件就铺在它上面,几乎没有只露它自己的那种重画。 }
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

function TTyToolWindowBar.GetStyleTypeKey: string;
begin
  Result := 'TyToolWindowBar';
end;

procedure TyToolWindowFlipAll(var AGeom: TTyToolWindowHeaderGeom; ARowWidth: Integer);
var
  span: TRect;
  i: Integer;

  function Flip(const ARect: TRect): TRect;
  begin
    { 只豁免全零那个「没有这个部件」的哨兵。被挤成零宽但**有位置**的部件照样要镜像 ——
      放过它的话它会原地留在 LTR 坐标,而 LTR 那边全绿。 }
    if (ARect.Left = 0) and (ARect.Right = 0) and (ARect.Top = 0) and (ARect.Bottom = 0) then
      Exit(ARect);
    Result := BidiFlipRect(ARect, span, True);
  end;

begin
  { 末尾一次过完每个矩形字段 —— 逐字段列在调用处的话,B 期加一个部件漏一行不会红。
    算术交给 LCL 自己那五行(controls.pp:2966),跟 CoolBar / ControlBar 同一个调用。
    span 的高写 0:纵向不动,这本身就是声明。 }
  span := Rect(0, 0, ARowWidth, 0);
  AGeom.Caption := Flip(AGeom.Caption);
  AGeom.Actions := Flip(AGeom.Actions);
  AGeom.TabArea := Flip(AGeom.TabArea);
  AGeom.Overflow := Flip(AGeom.Overflow);
  AGeom.Separator := Flip(AGeom.Separator);
  AGeom.Maximize := Flip(AGeom.Maximize);
  AGeom.Collapse := Flip(AGeom.Collapse);
  for i := 0 to High(AGeom.Tabs) do
    AGeom.Tabs[i].ItemRect := Flip(AGeom.Tabs[i].ItemRect);
end;

function TyToolWindowSameGeom(const A, B: TTyToolWindowHeaderGeom): Boolean;
var
  i: Integer;
begin
  { 跟 TyToolWindowFlipAll 同一份字段清单,一处过完 —— B 期给 Geom 加部件时,这里和
    那里挨着,漏一行看得见。 }
  Result := False;
  if not EqualRect(A.Caption, B.Caption) then Exit;
  if not EqualRect(A.Actions, B.Actions) then Exit;
  if not EqualRect(A.TabArea, B.TabArea) then Exit;
  if not EqualRect(A.Overflow, B.Overflow) then Exit;
  if not EqualRect(A.Separator, B.Separator) then Exit;
  if not EqualRect(A.Maximize, B.Maximize) then Exit;
  if not EqualRect(A.Collapse, B.Collapse) then Exit;
  if Length(A.Tabs) <> Length(B.Tabs) then Exit;
  for i := 0 to High(A.Tabs) do
  begin
    if A.Tabs[i].ItemIndex <> B.Tabs[i].ItemIndex then Exit;
    if not EqualRect(A.Tabs[i].ItemRect, B.Tabs[i].ItemRect) then Exit;
  end;
  if Length(A.Hidden) <> Length(B.Hidden) then Exit;
  for i := 0 to High(A.Hidden) do
    if A.Hidden[i] <> B.Hidden[i] then Exit;
  Result := True;
end;

function TyToolWindowActionsFlow(const AItems: array of TTyToolWindowFlowItem;
  AAvailW, AAvailH, APad, AGap: Integer; ARightToLeft: Boolean): TTyToolWindowFlow;
var
  ws, hs: array of Integer;
  n, i, sum, tallest, x, left: Integer;
begin
  Result := Default(TTyToolWindowFlow);
  n := Length(AItems);
  if n = 0 then Exit;
  { 同 TyToolWindowHeaderLayout:度量值不钳,负的内距 / 间距按 0 算。 }
  if APad < 0 then APad := 0;
  if AGap < 0 then AGap := 0;
  ws := nil;
  hs := nil;
  SetLength(ws, n);
  SetLength(hs, n);
  sum := 0;
  tallest := 0;
  for i := 0 to n - 1 do
  begin
    ws[i] := AItems[i].Width;
    if AItems[i].MinWidth > ws[i] then ws[i] := AItems[i].MinWidth;
    if ws[i] < 0 then ws[i] := 0;
    hs[i] := AItems[i].Height;
    if AItems[i].MinHeight > hs[i] then hs[i] := AItems[i].MinHeight;
    if hs[i] < 0 then hs[i] := 0;
    Inc(sum, ws[i]);
    if hs[i] > tallest then tallest := hs[i];
  end;
  Result.Size.cx := 2 * APad + sum + (n - 1) * AGap;
  Result.Size.cy := tallest + 2 * APad;
  { 放得下从前导内距开始;放不下整排贴尾端,被裁掉的是开头的。 }
  if Result.Size.cx <= AAvailW then x := APad
  else x := AAvailW - Result.Size.cx + APad;
  SetLength(Result.Rects, n);
  for i := 0 to n - 1 do
  begin
    { 从右往左读时整排按宽镜像:第一个到右端,贴尾端就成了贴左端,被裁的仍是开头那个。 }
    if ARightToLeft then left := AAvailW - x - ws[i]
    else left := x;
    Result.Rects[i] := Bounds(left, (AAvailH - hs[i]) div 2, ws[i], hs[i]);
    Inc(x, ws[i] + AGap);
  end;
end;

function TyToolWindowHeaderLayout(const AInput: TTyToolWindowHeaderInput): TTyToolWindowHeaderGeom;
var
  pad, gap, aw, x: Integer;
begin
  Result := Default(TTyToolWindowHeaderGeom);
  if (AInput.RowWidth <= 0) or (AInput.RowHeight <= 0) then Exit;
  pad := AInput.Pad; if pad < 0 then pad := 0;
  gap := AInput.Gap; if gap < 0 then gap := 0;
  aw := AInput.ActionsWidth; if aw < 0 then aw := 0;

  if AInput.Mode = twhSide then
  begin
    { 贴右端的操作区只是侧栏的答案。底栏从尾端往前是
      [收起][最大化][分隔线][操作区][溢出][标签…](spec §7.3),操作区不在最右端;
      twhNone 的操作区按 raw 首选尺寸放在正文左上角(spec §3.2)。
      在分支外面算就等于给那两支发一个看起来合法的错答案 —— 下面的钳位也一样。 }
    { 只给前导那个内距让位:尾端的 pad 由操作区自己带着(它的首选宽里就有两侧的 2×pad),
      spec §3.4「操作区自带内边距,宽为 0 时尾端补一个 header-pad」。 }
    if aw > AInput.RowWidth - pad then aw := AInput.RowWidth - pad;
    if aw > 0 then
    begin
      { 贴到行的右端:再补一个 pad 的话,最后一个按钮离右边就是 2×pad。 }
      Result.Actions := Rect(AInput.RowWidth - aw, 0, AInput.RowWidth, AInput.RowHeight);
      x := Result.Actions.Left - gap;
    end
    else
      x := AInput.RowWidth - pad;         { 没有操作区,尾端补一个内距 }
    if x > pad then
      Result.Caption := Rect(pad, 0, x, AInput.RowHeight);
    { 标题拿下整个剩余跨度 —— spec §3.4:"操作区优先保宽;标题先省略号"。
      放不下由 DrawText 自己出省略号,所以这里没有「标题想要多宽」这个输入。 }
  end;
  { twhBottom 那一支在 B 期实现;twhNone 什么都不排。 }

  if AInput.RightToLeft then
    TyToolWindowFlipAll(Result, AInput.RowWidth);
end;

function TyToolWindowVisiblePlan(AAvail: Integer; const AWidths: array of Integer;
  AActiveIndex, AOverflowWidth: Integer): TTyToolWindowPlan;
var
  w: TTyToolWindowWidths;
  plan: TTyToolWindowPlan;
  n, budget, i: Integer;

  function Fill(ABudget: Integer): TTyToolWindowPlan;
  var
    k, used: Integer;
  begin
    Result := nil;
    used := 0;
    for k := 0 to n - 1 do
    begin
      if used + w[k] > ABudget then Break;   { 遇到第一个放不下的就停 }
      Inc(used, w[k]);
      SetLength(Result, Length(Result) + 1);
      Result[High(Result)] := k;
    end;
  end;

  function Has(const APlan: TTyToolWindowPlan; AIdx: Integer): Boolean;
  var k: Integer;
  begin
    Result := False;
    for k := 0 to High(APlan) do
      if APlan[k] = AIdx then Exit(True);
  end;

  function Width(const APlan: TTyToolWindowPlan): Integer;
  var k: Integer;
  begin
    Result := 0;
    for k := 0 to High(APlan) do Inc(Result, w[APlan[k]]);
  end;

begin
  Result := nil;
  n := Length(AWidths);
  if n = 0 then Exit;
  { 负数入参在这里一次钳干净,下面的算术就能直着读(照 Breadcrumb 的规矩)。
    不钳的话:负的项宽让累加倒退、负的溢出按钮宽把预算放大,两个都能骗过「放不下就停」。
    B 期的 TabWidths 是量文字来的,一次测量失败就能喂进 0 或负数。 }
  w := nil;
  SetLength(w, n);
  for i := 0 to n - 1 do
  begin
    w[i] := AWidths[i];
    if w[i] < 0 then w[i] := 0;
  end;
  if AOverflowWidth < 0 then AOverflowWidth := 0;

  if AAvail <= 0 then
  begin
    { spec §7.3:当前页始终留在行上。「留出溢出按钮后一个都放不下」
      那条路径就是这么答的 —— 这里不一致的话,栏宽收到 0 会把当前页也弄丢。 }
    if (AActiveIndex >= 0) and (AActiveIndex < n) then
    begin
      SetLength(Result, 1);
      Result[0] := AActiveIndex;
    end;
    Exit;
  end;

  plan := Fill(AAvail);
  if Length(plan) < n then
  begin
    { 确实有东西被收起来了,才给溢出按钮留位置,然后重排一次。 }
    budget := AAvail - AOverflowWidth;
    if budget < 0 then budget := 0;
    plan := Fill(budget);
    { 当前页强制留在行上:追加到末尾,再从它前面一个开始往前挤。 }
    if (AActiveIndex >= 0) and (AActiveIndex < n) and not Has(plan, AActiveIndex) then
    begin
      SetLength(plan, Length(plan) + 1);
      plan[High(plan)] := AActiveIndex;
      i := Length(plan) - 2;
      while (i >= 0) and (Width(plan) > budget) do
      begin
        Delete(plan, i, 1);
        Dec(i);
      end;
    end;
  end;
  Result := plan;
end;

function TyToolWindowSlotAt(const ASlots: TTyToolWindowSlots; X, Y: Integer;
  AVertical: Boolean; ACount: Integer): Integer;
var
  i, mid, pos, last: Integer;
  R: TRect;
begin
  { 已排布项不一定是窗口列表的前缀(当前页被强制留下),所以空隙映射到**它对应窗口的序号**,
    不是排布序号。 }
  if Length(ASlots) = 0 then Exit(ACount);
  last := -1;
  for i := 0 to High(ASlots) do
  begin
    R := ASlots[i].ItemRect;
    { 空槽没有中点可言,跳过 —— B 期 Geom.Tabs 会带被挤成零的槽位。 }
    if (R.Right <= R.Left) or (R.Bottom <= R.Top) then Continue;
    last := i;
    if AVertical then
    begin
      mid := (R.Top + R.Bottom) div 2;
      pos := Y;
    end
    else
    begin
      mid := (R.Left + R.Right) div 2;
      pos := X;
    end;
    if pos < mid then Exit(ASlots[i].ItemIndex);
  end;
  if last < 0 then Exit(ACount);          { 全是空槽 }
  Result := ASlots[last].ItemIndex + 1;
end;

function TyToolWindowStripLayout(AStripWidth, AStripHeight, AItemSize, AOverflowSize: Integer;
  ACount, AActiveIndex: Integer): TTyToolWindowSlots;
var
  widths: TTyToolWindowWidths;
  plan: TTyToolWindowPlan;
  i, y, t, b: Integer;
begin
  Result := nil;
  if (ACount <= 0) or (AItemSize <= 0) or (AStripWidth <= 0) or (AStripHeight <= 0) then Exit;
  widths := nil;
  SetLength(widths, ACount);
  for i := 0 to ACount - 1 do widths[i] := AItemSize;   { 图标是方的,等宽 }
  plan := TyToolWindowVisiblePlan(AStripHeight, widths, AActiveIndex, AOverflowSize);
  SetLength(Result, Length(plan));
  y := 0;
  for i := 0 to High(plan) do
  begin
    { 条裁掉它。条矮到放不下一个图标时当前页仍然被强制留下,那个槽位不裁就会戳在条外面;
      同时保证不反转。 }
    t := y;
    if t > AStripHeight then t := AStripHeight;
    b := y + AItemSize;
    if b > AStripHeight then b := AStripHeight;
    if b < t then b := t;
    Result[i].ItemIndex := plan[i];
    Result[i].ItemRect := Rect(0, t, AStripWidth, b);
    Inc(y, AItemSize);
  end;
end;

function TyToolWindowDragThreshold(APPI: Integer): Integer;
begin
  if APPI <= 0 then APPI := 96;
  Result := MulDiv(TyToolWindowDragThresholdPx, APPI, 96);
  if Result < 1 then Result := 1;
end;

initialization
  { 运行时 .lfm 按类名实例化流里的子对象,四个都要注册。 }
  RegisterClass(TTyToolWindow);
  RegisterClass(TTyToolWindowActions);
  RegisterClass(TTyToolWindowBar);
  RegisterClass(TTyToolWindowManager);
end.
