unit tyControls.ToolWindows;
{$mode objfpc}{$H+}

{ IDE 工作台的侧栏 / 底栏。设计定稿见
  docs/superpowers/specs/2026-09-17-toolwindow-workbench-design.md。
  四个类同在一个单元:窗口与栏互相引用,拆单元只会多一圈前向声明。 }

interface

uses
  Classes, SysUtils, Types, Controls, Graphics, LCLType, LMessages,
  tyControls.Types, tyControls.Base, tyControls.Component, tyControls.Painter,
  tyControls.StyleModel;

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

  TTyToolWindowActions = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
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
begin
  { 操作区本身(连同扫 Controls[] 取第一个的这一句)是 Task 4 的活;在那之前一个
    操作区都不存在,标题行高就退化成 token 值。 }
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
  { 镜像整套几何靠这一个字段。A 期行里只有标题、而标题占的是对称的那一整条,
    镜像前后一模一样 —— 所以这条线今天没有任何像素能证伪,只有
    TestRightToLeftReachesTheHeaderLayout 那条接线断言守着它。操作区一进来
    (Task 4)它立刻变成看得见的东西。 }
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
  if mode = twhNone then Exit(0);
  mdl := ActiveController.Model;
  ver := mdl.ThemeVersion;
  { 键里既要版本号也要 model 身份:版本号是每个 model 各自算的,只按版本号键控
    会把 A 的值端给 B —— Controller 是 published,中途换得掉。 }
  if (not FHeaderPxValid) or (FHeaderPxAnchor <> TObject(mdl)) or (FHeaderPxVer <> ver)
     or (FHeaderPxPPI <> Font.PixelsPerInch) or (FHeaderPxRTL <> IsRightToLeft)
     or (FHeaderPxMode <> mode) then
  begin
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

{ 操作区的首选尺寸(设备像素,按给定 PPI)。Task 4 把这里换成真的 —— **一处答**:
  标题行高拿它的高钳底、排布拿它的宽留位,两边各写一个 0 的话 Task 4 只改一处,
  画出来的那条和挖出来的正文就会错开,而且不会红。 }
function TTyToolWindow.ActionsPreferredSize(APPI: Integer): TSize;
begin
  { Task 4:操作区存在时换成 Actions 的 raw 首选尺寸按 APPI 缩放;在那之前一个操作区
    都不存在,标题行高退化成 token 值、标题占满整条。 }
  Result.cx := 0;
  Result.cy := 0;
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
  CustomAlignPosition 就照着它把操作区摆到控件外面去。一处钳 —— HeaderGeomAt、
  HeaderRowRect、RenderTo 问的是同一条。照 TTyCard.LayoutAtPPI(Card.pas:181)。 }
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

function TTyToolWindow.HeaderHeightPx: Integer;
begin
  { 布局用的那一问:按自己字体的像素密度。AdjustClientRect / HeaderRowRect 走的都是它。 }
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
  Inc(ARect.Top, HeaderHeightPx);
  if ARect.Top > ARect.Bottom then ARect.Top := ARect.Bottom;
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

function TTyToolWindowActions.GetStyleTypeKey: string;
begin
  Result := 'TyToolWindowActions';
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

function TyToolWindowHeaderLayout(const AInput: TTyToolWindowHeaderInput): TTyToolWindowHeaderGeom;
var
  pad, gap, aw, x: Integer;
begin
  Result := Default(TTyToolWindowHeaderGeom);
  if (AInput.RowWidth <= 0) or (AInput.RowHeight <= 0) then Exit;
  pad := AInput.Pad; if pad < 0 then pad := 0;
  gap := AInput.Gap; if gap < 0 then gap := 0;
  aw := AInput.ActionsWidth; if aw < 0 then aw := 0;
  { 两个内距都要留出来:只扣一个的话,侧栏拖窄时操作区会吃掉前导内距。 }
  if aw > AInput.RowWidth - 2 * pad then aw := AInput.RowWidth - 2 * pad;

  if AInput.Mode = twhSide then
  begin
    { 贴右端的操作区只是侧栏的答案。底栏从尾端往前是
      [收起][最大化][分隔线][操作区][溢出][标签…](spec §7.3),操作区不在最右端;
      twhNone 的操作区按 raw 首选尺寸放在正文左上角(spec §3.2)。
      在分支外面算就等于给那两支发一个看起来合法的错答案。 }
    if aw > 0 then
    begin
      Result.Actions := Rect(AInput.RowWidth - pad - aw, 0, AInput.RowWidth - pad, AInput.RowHeight);
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
