unit tyControls.ScrollBar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Math, Controls, Graphics, LCLType, StdCtrls, ExtCtrls,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Painter, tyControls.Base, tyControls.Animation,
  tyControls.Controller, tyControls.StyleModel;
const
  { 自动隐藏延时的主题令牌。一条轴，没有歧义的零：
      -1 = 关（滚动条一直显示；基础层 light.tycss 就是这个值，经典世代的
           皮肤一行不写、全靠继承它；六个遮盖式滚动条的皮肤
           （win11/macos/fluent/material3/adwaita/ubuntu）写的是 1200）
       0 = 开，停手立即淡出
       N = 开，停手 N 毫秒后淡出
    走已有的 Metric 机制，tycss 不需要新的值类型。负号能活着走完
    ResolveMetric -> TyEvalLength -> ParsePctOrNum -> StrToFloat，理由见
    docs/superpowers/specs/2026-09-14-scrollbar-auto-hide-design.md §2。 }
  TyScrollBarAutoHideVar = '--scrollbar-auto-hide';
  { 「关」这一个值,原来在同一个函数里有三种写法(Exit(-1)、Def = -1、
    themeMs < 0)。给它一个名字，三处都指这里。 }
  TyScrollBarAutoHideOff = -1;
  TyScrollBarAutoHideDef = TyScrollBarAutoHideOff;
  { 属性明说要自动隐藏、而主题没给延时时的回退。macOS 量级。 }
  TyScrollBarAutoHideFallbackMs = 1200;
  { 出现要快——用户正在找它；消失要柔——别打扰。 }
  TyScrollBarFadeInMs  = 120;
  TyScrollBarFadeOutMs = 200;
  { 贴边内嵌条滑道的圆角(逻辑 px)。基础层 light.tycss 写的是 0:条是宿主边上的一条带,
    贴边侧的形状由宿主底色裁,内容侧再照 --radius-scroll 圆的话,两端各露出一块宿主底色的
    缺口,条的端头又「飘」起来 —— 正是贴边要去掉的样子。想要圆滑道的皮肤写非零值,自己
    接受两端的缺口。独立摆放的条不读它,照旧是 TyScrollBar 的 border-radius。
    **是令牌不是 variant(TyScrollBar.embedded 之类)**:皮肤只要给某个 typeKey 写了任何一条
    规则,内置那一层该 typeKey 的规则就**连同 variant**一起被压掉,variant 只写半截还会把控件
    抹白;令牌走合并后的变量层,皮肤不写就继承基础层,没有这两种故障。 }
  TyScrollBarEmbeddedRadiusVar = '--radius-scroll-embedded';
  TyScrollBarEmbeddedRadiusDef = 0;

type
  TTyScrollBar = class;
  TTyScrollBarKind = (sbHorizontal, sbVertical);

  { 自动隐藏的三态。**不能是 Boolean**：Boolean 一旦被碰过就永远脱离主题
    控制，换主题不跟着变——在一个主打换肤的库里这是硬伤。 }
  TTyScrollBarAutoHide = (sbahDefault, sbahNever, sbahAuto);

  { 把 TTyScrollBar **贴着自己的边**摆、并让条替自己把框画回去的宿主。
    六个宿主实现它:列表框、备忘录、网格、列表视图、树、滚动框。

    为什么要条来画:条是窗口化子控件,它那块矩形上宿主一个像素都画不进去。从前的办法是
    把条的窗口缩小、让开边框 —— 直边上内缩一圈,圆角上再把条的两端各截掉几像素。真机的
    结论是「条飘着的,感觉不够紧凑」,而只要前提是「缩小窗口去躲」,圆角就一定要截短条,
    调常数调不出来。所以前提换了:条贴边、占满整条边,由条自己把宿主在这几个像素上的样子
    画出来(底下宿主背景、中间条身、最上面宿主的边框和焦点环)。见 TTyScrollBar.RenderTo。

    宿主只需要回答一件事:它**此刻**用哪份样式画自己的框。必须是状态解析过的那份
    (CurrentStyle,带着 :focus/:hover/:disabled),焦点环才会恰好在宿主有焦点时出现在条上;
    宿主画框前若改过样式(列表框在 Wayland 弹层上把圆角清零),这里要交出改过的那份。
    何时重画不归这个接口管:宿主 Invalidate 时 TTyCustomControl 会顺带让条重画,见
    TTyCustomControl.PaintsParentFrame。 }
  ITyScrollBarFrameHost = interface
    ['{5E0C8A7B-3F21-4C9D-B6E4-91D2A7F03C58}']
    function ScrollBarFrameStyle: TTyStyleSet;
    { ABar 是不是本宿主**自己建的**那几条之一。「内嵌」全库只认这一句,见
      TTyScrollBar.IsEmbedded。

      为什么不是「父控件实现了本接口」就算:滚动框是容器,用户完全可以往里面拖一根自己的
      TTyScrollBar,它的 Parent 同样实现本接口,却是一根独立的条 —— 该画自己的框、该在点击时
      拿焦点。也不是 TabStop:用户给独立条关掉 TabStop(不进 Tab 顺序)照样指望点它能拿到焦点。
      也不是 Owner:代码里 TTyScrollBar.Create(ScrollBox1) 再 Parent := ScrollBox1 是常见写法。
      只有宿主知道哪几根是它自己的,所以让宿主回答;做成接口方法,新宿主漏写就编译不过。 }
    function EmbedsScrollBar(ABar: TTyScrollBar): Boolean;
  end;

  TTyScrollBar = class(TTyCustomControl)
  private
    FKind: TTyScrollBarKind;
    FMirrorH: Boolean;
    FMin, FMax, FPosition, FPageSize: Integer;
    FSmallChange, FLargeChange: Integer;
    FOnChange: TNotifyEvent;
    FOnScroll: TScrollEvent;
    FDragGrabOffset: Integer;
    FDragStartTop: Integer;
    FLiveTracking: Boolean;
    { The value the thumb is being DRAGGED to while LiveTracking is off. It is the painted
      position for the duration of the drag and becomes Position on mouse-up; FPosition is
      left alone until then, which is the whole point of the mode. }
    FTrackPos: Integer;
    FAnimEnabled: Boolean;
    FAutoHide: TTyScrollBarAutoHide;
    { 上一次缓动滴答的时刻(0 = 还没开始)。用来算真实经过时间。 }
    FLastTickMs: QWord;
    { 本次位置变化要不要立刻刷自己(只在拖动中置位)。 }
    FNeedImmediateRepaint: Boolean;
    FPosAnim: TTyAnimator;      // 0..1 traversal driving FAnimFrom -> FAnimTo
    FAnimFrom, FAnimTo: Single; // displayed-thumb-position endpoints (Min..Max units)
    FTimer: TTimer;            // lazy; only created when actually animating
    { ——— 自动隐藏。整组字段和上面那套位置缓动毫无关系,别把两边的字段串着用。 }
    FFadeLevel: Single;         // 1 = 完全显示，0 = 完全隐藏
    FFadeAnim: TTyAnimator;     // 0..1 traversal，驱动 FFadeFrom -> FFadeTo
    FFadeFrom, FFadeTo: Single;
    FIdleMs: Integer;           // 距上次「在用」过去了多久
    { 指针在**宿主**身上——不是在条上。宿主的 MouseEnter/MouseLeave 转发进来，
      见 SetHostHovered。**必须和 FHover 分开记**：条是窗口化子控件，指针从
      宿主内容挪到条上时，宿主的 MouseLeave 和条的 MouseEnter 是两条各自到达
      的消息；两个字段合起来判，交界处才不会闪。 }
    FHostHovered: Boolean;
    { 淡入淡出上一拍的时刻(0 = 还没开始)。**不能和位置缓动的 FLastTickMs 共用**
      ——两套定时器各跑各的，串起来只会互相把对方的起点冲掉。 }
    FFadeLastTickMs: QWord;
    { 主题里那个延时令牌解出来的值，连同它是在哪个 model 的哪一版主题上解出来的。
      锚点故意存成 TObject：它只拿来比相等，永远不解引用，所以 controller 换过
      之后那个指针悬着也无所谓。nil = 还没解过。 }
    FAutoHideMsCache: Integer;
    FAutoHideMsVer: Cardinal;
    FAutoHideMsAnchor: TObject;
    { 惰性；等延时和跑淡出两个阶段共用它，一律 16ms 一拍。
      **一拍推进多少毫秒不看 Interval**，看真实经过时间——见 FadeTickElapsedMs。
      **和位置动画的 FTimer 无关**——那套有 FDragging/LiveTracking 的分支，
      掺进来只会把两件事一起弄坏。 }
    FHideTimer: TTimer;
    function TrackRect: TRect;
    function TrackLength: Integer;
    function PosAlong(X, Y: Integer): Integer;
    { True when THIS bar's track runs right-to-left, i.e. MirrorHorizontal is on AND the
      bar is horizontal. Every mirrored site asks this one question, so a vertical bar can
      never accidentally pick up the flag. }
    function Mirrored: Boolean;
    procedure SetMirrorHorizontal(const AValue: Boolean);
    procedure SetAutoHide(const AValue: TTyScrollBarAutoHide);
    procedure ButtonRects(const AClient: TRect; out ALo, AHi: TRect);
    procedure SetKind(const AValue: TTyScrollBarKind);
    procedure SetMin(const AValue: Integer);
    procedure SetMax(const AValue: Integer);
    procedure SetPosition(const AValue: Integer);
    procedure SetPageSize(const AValue: Integer);
    procedure SetSmallChange(const AValue: Integer);
    procedure SetLargeChange(const AValue: Integer);
    { How far one page action moves: LargeChange when set, PageSize otherwise. }
    function EffectiveLargeChange: Integer;
    function GetTrackPosition: Integer;
    procedure EnsureTimer;
    procedure HandleTimer(Sender: TObject);
    procedure EnsureHideTimer;
    { 把延时表装上并起起来,**不碰闲置时钟**。

      和 NoteActivity 的分工要划清:那个说的是「有人在用」——它把闲置清零、
      该淡回来的淡回来;这个只回答「这条条现在该不该有一块表在转」。条刚
      *进入*可自动隐藏的状态(句柄到手、换到一个开自动隐藏的皮肤)不是「有人
      在用」,拿 NoteActivity 来干这活等于每次重绘都给它续一次命,条就再也
      淡不掉了。 }
    procedure ArmAutoHideClock;
    procedure HandleHideTimer(Sender: TObject);
    function AutoHideHeldOpen: Boolean;
    procedure StartFade(ATo: Single; ADurationMs: Integer);
    { RenderTo 真正用的那份样式：主题样式叠上自动隐藏的淡出系数。见实现处。 }
    function PaintStyle: TTyStyleSet;
    { 条身:滑块 + 两头的箭头。条自己的底色和边框不在这里(那是 DrawFrame / 三段帧函数)。
      几何(箭头格、滑道、滑块在哪)一律按整条 ARect 算 —— 与 MouseDown 的命中测试是同一个
      调用;ASpan 是**看得见的那一截**,滑块只画在它里面、箭头居中在它里面。独立摆放的条
      ASpan = ARect,什么都不变。贴边的内嵌条见 RenderOverHostFrame。 }
    procedure PaintBody(APainter: TTyPainter; const ARect, ASpan: TRect;
      const AStyle: TTyStyleSet);
    { 条身单独画到一张**透明**位图上,调用方负责释放。淡出/贴边两条路都要先有这一层,
      再按可见度合成到底下真实的背景上。底色铺满 ARect,条自己的边框/焦点环和条身按 ASpan。 }
    function RenderBodyLayer(const ARect, ASpan: TRect; const AStyle: TTyStyleSet;
      APPI: Integer): TBGRABitmap;
    { 贴边内嵌条的整套绘制:宿主背景 -> 条身(按 AAlpha 合成、裁进宿主的底色形状)->
      宿主的边框与焦点环。见 RenderTo。 }
    procedure RenderOverHostFrame(APainter: TTyPainter; const ARect: TRect;
      const AHost: ITyScrollBarFrameHost; const AStyle: TTyStyleSet; AAlpha: Single);
    { 本条若是某个宿主自己的内嵌条,交出那个宿主。见 IsEmbedded。 }
    function EmbeddingHost(out AHost: ITyScrollBarFrameHost): Boolean;
    { 一次左键点击之后焦点该落在哪。独立的条拿焦点;内嵌条把焦点交给宿主。见实现处。 }
    procedure FocusAfterClick;
    { 主题说的延时，按 (model, ThemeVersion) 缓存。见实现处：热路径上一拍要问两次。 }
    function ThemeAutoHideMs: Integer;
  protected
    FDragging: Boolean;
    { Invalidate 被调过几次。只增不减,只给测试读 —— 它记在**真正的** Invalidate 里,所以
      「宿主获得焦点 -> 条跟着重画」这条接线被拆掉时它不涨,测试就红。无头下条没有窗口,
      重画本身看不见,能看见的只有这一下有没有被叫到。 }
    FInvalidations: Cardinal;
    { 内嵌条(IsEmbedded)在替宿主画框,宿主的框一变本条就得重画。 }
    function PaintsParentFrame: Boolean; override;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure Paint; override;
    { 句柄到手的那一刻把延时表起起来。**这是自动隐藏唯一一个「没人碰过它」的
      起表点。**

      从前起表只有 NoteActivity 一条路,而它的每一个调用点要么是用户在条上比划、
      要么是代码改 Position。条在出生期间收到的 NoteActivity 全都早于句柄
      (.lfm 流式化设 AutoHide -> SetAutoHide、宿主把 ScrollBarAutoHide 转发给
      刚建出来的条、宿主头一次 UpdateScrollBar 设 Position ——最后这个连
      NoteActivity 都到不了,0 = 0 在 SetPosition 里就早退了),而 EnsureHideTimer
      在没句柄的时候直接 Exit,建不出表来。句柄随后到位,**从前没有任何东西
      回头重试**:一条摆在屏幕上、谁也没碰过的条,表是 0 块,永远停在
      FadeLevel = 1.0,非得等鼠标移上去(MouseEnter -> NoteActivity)才开始算
      延时——用户报的就是这个。

      有一种情形这里救不了,也不该救:独立摆放的条要是正好是窗体的头一个
      tab stop,一出生就有焦点,而有焦点是「按住不放」的信号之一
      (AutoHideHeldOpen),表起来了头一拍也会把自己停掉。那是设计,不是 bug
      ——键盘焦点停在一个看不见的控件上才是事故。 }
    procedure InitializeWnd; override;
    { 全身只为自动隐藏服务：指针压在条上时它必须一直亮着。 }
    procedure MouseEnter; override;
    { 同上，指针离开那一半：把停掉的延时表重新起起来。 }
    procedure MouseLeave; override;
    { 同上,焦点那一半。 }
    procedure DoEnter; override;
    { 同上，失焦那一半。 }
    procedure DoExit; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure KeyDown(var Key: Word; Shift: TShiftState); override;
    function DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint): Boolean; override;
    // Fire OnScroll with ACode and the proposed APos (which the handler may
    // override via the var parameter); then commit Position := APos. This keeps
    // OnChange firing too (via the Position setter). Used by the user-driven
    // keyboard/track-paging paths.
    procedure DoScroll(ACode: TScrollCode; var APos: Integer);
    procedure ScrollTo(ACode: TScrollCode; AProposed: Integer);
    // Current displayed (possibly mid-animation) thumb position, eased between
    // the from/to endpoints. At rest this equals the logical FPosition.
    function DisplayPos: Single;
    // Steppable animation seam (no wall-clock): advance the thumb ease by AMs and
    // return True iff the eased progress changed. The lazy TTimer drives it at
    // runtime; tests drive it directly via an access subclass.
    function AdvanceAnimation(AMs: Integer): Boolean;
    // Force the *animating* path toward AValue (clamped) regardless of handle
    // state. Runtime always routes through SetPosition (which snaps headless);
    // this is the test seam so the animation is reachable without a window.
    procedure SetPositionAnimating(AValue: Integer);
    { 一拍推进多少毫秒(真实经过时间)。测试用受控时钟覆写它。 }
    function TickElapsedMs: Integer; virtual;
    procedure HandleTimerTick;
    { 淡出这一拍该推进多少毫秒(真实经过时间)。TickElapsedMs 的孪生体,连可见性
      一起孪生:那边抽成可覆写的理由这边一字不差 —— 否则「按真实时间推进」这条
      只能靠肉眼在真机上看,而那正是当初写成名义间隔也没人发现的原因。 }
    function FadeTickElapsedMs: Integer; virtual;
    { **缝开在「现在几点」这一层,不在算好的差值那一层。** 位置缓动那边的桩
      (test.controls.scrollbar.pas 的 TFakeClockScroll)覆写的是整个
      TickElapsedMs,那条路上没有别的逻辑;这边不行 —— 至少 1 毫秒的钳位和
      首拍的种子值都长在 FadeTickElapsedMs 里,覆写它等于把被测的那段搬进桩子,
      喂个 0 进去测出来的是桩子会不会返回 0。 }
    function FadeNowMs: QWord; virtual;
    { 延时表这一拍之后还有没有活干。抽出来一是 HandleHideTimer 要用，二是无头
      只够得着这里——没有句柄就不建表，「按住不放就停表」那条逻辑的效果
      (FHideTimer.Enabled)在无头下根本不存在，能验的只有这个判断本身。 }
    function AutoHideTimerNeeded: Boolean;
    { 手动走一拍 HandleHideTimer（无头没有表）。和位置缓动的 HandleTimerTick 同路。 }
    procedure HandleHideTimerTick;
  public
    { 设定位置并**立刻落位**,绝不缓动。

      给"镜像"用:宿主(网格/列表/树)自己滚完之后,把结果同步给滑块。
      内容已经动了,滑块再缓动追上去就是不跟手 —— 用户看到的是内容在动、
      滑块慢半拍。缓动只在"用户点滑道让它跳过去"那种场景才有意义。 }
    procedure SetPositionSnapped(AValue: Integer);
    { 本条是不是某个宿主(列表框、备忘录、网格、列表视图、树、滚动框)**自己的**内嵌条 ——
      由父控件经 ITyScrollBarFrameHost.EmbedsScrollBar 回答,不看 TabStop、不看 Owner。
      内嵌条贴边摆、替宿主画框,而且**永远不拿焦点**:点它,焦点归宿主(见 MouseDown)。
      独立摆放的条(哪怕摆在滚动框里)答 False,行为与从前一样。 }
    function IsEmbedded: Boolean;
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    function GetStyleTypeKey: string; override;
    procedure BeginThumbDrag(AGrabPosAlongTrack: Integer);
    procedure DragThumbTo(APosAlongTrack: Integer);
    procedure EndThumbDrag;
    { True while the user is dragging the thumb with the mouse. }
    property Dragging: Boolean read FDragging;
    { Where the thumb currently SITS, which is Position except in the middle of a
      LiveTracking=False drag -- there the thumb has moved and Position has not yet. A host
      that wants to preview the pending value (a row-number tooltip beside the thumb, say)
      reads this; everything else should keep reading Position. }
    property TrackPosition: Integer read GetTrackPosition;
    { 本条现在实际的自动隐藏延时，毫秒；-1 表示关（一直显示）。
      属性压过主题：sbahNever 恒为 -1；sbahAuto 在主题说关时用回退值。 }
    function EffectiveAutoHideMs: Integer;
    { 0..1 的当前可见度。1 = 完全显示。绘制时乘进样式的 opacity,作为条身那一层合成到
      真实背景上的不透明度(见 RenderTo)。 }
    property FadeLevel: Single read FFadeLevel;
    { 延时表现在转着没有。**只读**,问的是真表(FHideTimer),不是哪个影子状态。

      开这个口是为了让测试断言「起表这个决定做没做」——只看 FadeLevel 是断不出
      来的:一条从没起过表的条和一条刚起了表还没到点的条,可见度都是 1.0,
      长得一模一样,而这两者正是这次修的 bug 的两边。无头够得着真句柄
      (HandleNeeded 就会走 InitializeWnd),所以不需要假缝。 }
    function AutoHideClockArmed: Boolean;
    { 「有人在用」。滚动、悬停、拖动、聚焦都调它。 }
    procedure NoteActivity;
    { 宿主告诉这条条：指针现在在不在**宿主身上**。

      规则是「指针在宿主上 = 显示且不计时」，见 docs/controls/scrollbar.md §7。
      条自己的 MouseEnter 够不着这件事——指针停在列表正文上的时候条收不到
      任何鼠标消息，而那正是用户报回来的场景：「鼠标移到列表上 scrollbar
      没出来，只有滚轮滚一下或者移到条上才出来」。

      **进来不只是按住，还要把条叫出来**：指针刚进列表的那一刻条多半已经
      淡到 0 了，只把它标成「按住」的话没有任何东西会推它一拍。
      **离开只起表，不当场隐藏**：指针从内容挪到条上时宿主先收 MouseLeave，
      当场隐藏就是在交界处闪一下。 }
    procedure SetHostHovered(AValue: Boolean);
    { 指针在不在宿主身上。只读——写这件事只有宿主有资格，走 SetHostHovered。 }
    property HostHovered: Boolean read FHostHovered;
    { 测试缝：推进 AMs 毫秒。真机由 FHideTimer 驱动，headless 由测试驱动
      ——和位置动画的 HandleTimerTick 是同一个路子。 }
    procedure AutoHideTick(AMs: Integer);
    { 测试缝：问「这一帧的 opacity 是多少」，省得为了一个数去数像素。
      **它不能替代像素测试**：这个口子绕开了 RenderTo，光靠它绿，
      「算对了但没接到绘制上」照样一声不吭——那是本库的默认故障。 }
    function PaintStyleForTest: TTyStyleSet;
    { 换主题时控件收到的就只有这一个广播,所以「自动隐藏关着 -> 条必须看得见」
      这条不变量只能挂在这儿修。见实现处。 }
    procedure Invalidate; override;
  published
    { The universal properties the base classes stopped publishing in 4.0 (LCL visibility);
      RTTI order is the 3.0 order. }
    property Version;
    property Enabled;
    property Visible;
    property Font;
    property ShowHint;
    property TabOrder;
    { A standalone bar is a keyboard control (arrows / PgUp / PgDn / Home / End in
      KeyDown), so it takes a tab stop like the native TScrollBar does. Declared True to
      match the constructor, so a host's TabStop=False opt-out streams — which is exactly
      what the bars EMBEDDED inside a list/grid/tree/scroll box do, in code. }
    property TabStop default True;
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
    { LIVE TRACKING -- whether dragging the thumb moves Position continuously (True, the
      default and what this bar has always done) or only on mouse-up (False).

      This is the seam LCL's goThumbTracking needs. That flag was left out of TTyGrid.Options
      in 251db2d with the reason "needs a seam in the scroll bar, which always tracks live":
      publishing it while the bar could not honour it would have been a lying property, which
      is the exact defect class test.parity's LyingPropertiesStayUnpublished exists to stop.
      With this property a host CAN honour it -- see docs/controls/scrollbar.md.

      Off, the thumb still follows the mouse (the drag has to feel connected); what is deferred
      is the COMMIT -- Position, OnChange, and OnScroll(scPosition). OnScroll(scTrack) still
      fires on every move with the proposed value, exactly as a native bar keeps sending
      SB_THUMBTRACK; a host that does not want to act on it simply does not. That split is
      what makes the mode useful at all: an expensive host (a grid re-querying a database per
      row) previews on scTrack and only really moves once.

      Only the THUMB DRAG is affected. Arrow buttons, track paging, the wheel and the keyboard
      commit immediately in both modes -- they are discrete steps, not a continuous gesture,
      and native bars do not defer them either. }
    property LiveTracking: Boolean read FLiveTracking write FLiveTracking default True;
    // On by default. When enabled and the control has a window handle, a
    // PROGRAMMATIC Position change (keyboard/wheel/track-click) eases the painted
    // thumb to the new value; with no handle (every render test) or while
    // dragging it snaps, preserving exact-pixel tests and live mouse tracking.
    property AnimationsEnabled: Boolean read FAnimEnabled write FAnimEnabled default True;
    { 这条滚动条要不要在没人用的时候淡出。

      sbahDefault —— 跟主题走（令牌 --scrollbar-auto-hide）。
      sbahNever   —— 永远显示，压过主题。
      sbahAuto    —— 自动隐藏，压过主题；延时仍读主题，主题没给就用
                     TyScrollBarAutoHideFallbackMs。

      延时**故意不给属性**：单控件要不同延时是臆想需求。整体调快调慢改主题。 }
    property AutoHide: TTyScrollBarAutoHide read FAutoHide write SetAutoHide default sbahDefault;
    { RIGHT-TO-LEFT HORIZONTAL BAR: Min sits at the RIGHT end of the track and a rising
      Position walks the thumb LEFTWARDS. That is Windows' behaviour for a mirrored window,
      not a preference — a horizontal bar under WS_EX_LAYOUTRTL comes out reflected. The
      painted bar looks IDENTICAL either way (reflecting a left arrow at one end and a right
      arrow at the other is its own mirror image); what changes is where the thumb is for a
      given Position, which end button decrements, and which way the arrow keys step.
      Vertical bars ignore it entirely.

      OPT-IN, and default False on purpose — it is NOT wired to BiDiMode. Five controls in
      this library embed a horizontal bar (Grid, ListView, Memo, TreeView, ScrollBox) and
      none of them mirrors its CONTENT yet. A bar that put Position=Min on the right while
      the content it drives still began on the left would be a thumb pointing at the wrong
      half of the document — the paint/hit-test split this whole pass exists to remove, just
      moved up one level. A host turns this on in the same commit that mirrors its content.
      TTyScrollBox deliberately leaves it off: see the note on its horizontal bar. }
    property MirrorHorizontal: Boolean read FMirrorH write SetMirrorHorizontal default False;
    property Kind: TTyScrollBarKind read FKind write SetKind default sbVertical;
    property Min: Integer read FMin write SetMin default 0;
    property Max: Integer read FMax write SetMax default 100;
    property Position: Integer read FPosition write SetPosition default 0;
    { PageSize sizes the THUMB (thumb : track = PageSize : (Max-Min)+PageSize). It also
      used to be the only page STEP, so a proportional thumb and a page jump could not
      be chosen independently: shrinking the thumb shrank the page click with it. LCL
      keeps the two apart -- PageSize feeds ScrollInfo.nPage (include/scrollbar.inc:55)
      while LargeChange drives scPageUp/scPageDown (:195,199). }
    property PageSize: Integer read FPageSize write SetPageSize default 10;
    property SmallChange: Integer read FSmallChange write SetSmallChange default 1;
    { The page step: a track click, PgUp/PgDn, scPageUp/scPageDown. LCL: stdctrls.pp:106.

      DIFFERENT DEFAULT, deliberately. LCL's is 1, which would make a track click on
      every bar in this library -- the list box, the grid, the memo, the tree, the
      scroll box all embed one -- crawl by a single unit instead of a screenful. 0 here
      means "page by PageSize", i.e. exactly what this bar did before the property
      existed, so nothing that ships today changes; set it to page by something else. }
    property LargeChange: Integer read FLargeChange write SetLargeChange default 0;
    property OnChange: TNotifyEvent read FOnChange write FOnChange;
    property OnScroll: TScrollEvent read FOnScroll write FOnScroll;
    property Align;
    property Anchors;
  end;

function TyScrollThumbRect(const ATrack: TRect; AKind: TTyScrollBarKind;
  AMin, AMax, APosition, APageSize: Integer; ARightToLeft: Boolean = False): TRect;

{ THE ONLY PLACE THE HORIZONTAL AXIS IS EVER FLIPPED.

  AOffset is how far the thumb's near edge sits from the track's near edge; AFreeSpace is
  how far it can travel (track length minus thumb length). Mirroring a scroll bar is exactly
  "measure that offset from the other end", so it is one subtraction — and putting it in a
  function rather than inline is the whole point: TyScrollThumbRect (which PAINTS the thumb)
  and TTyScrollBar.DragThumbTo (which reads a dragged thumb back OUT into a Position) are
  inverse computations written in two different places, and this is the single line they
  share. Flip it here and both flip; there is no arrangement in which the thumb is drawn
  mirrored and the drag/click math is not.

  Vertical bars and left-to-right bars return AOffset untouched, which is why every existing
  caller is bit-for-bit unchanged. }
function TyScrollMirrorOffset(AOffset, AFreeSpace: Integer; AKind: TTyScrollBarKind;
  ARightToLeft: Boolean): Integer;

function TyScrollButtonSize(const AClient: TRect; AKind: TTyScrollBarKind): Integer;
{ NOT mirrored, and deliberately: the track is inset by one button-size at EACH end, so the
  rect is symmetric about the client centre and reflecting it is the identity. (The scoping
  document expected the two end buttons to swap here; the end buttons are not here — they are
  TTyScrollBar.ButtonRects — and they do not swap either. See RenderTo.) }
function TyScrollTrackRect(const AClient: TRect; AKind: TTyScrollBarKind;
  AButtonSize: Integer): TRect;

implementation

uses
  LCLIntf;

function TyScrollMirrorOffset(AOffset, AFreeSpace: Integer; AKind: TTyScrollBarKind;
  ARightToLeft: Boolean): Integer;
begin
  if ARightToLeft and (AKind = sbHorizontal) then
    Result := AFreeSpace - AOffset
  else
    Result := AOffset;
end;

function TyScrollThumbRect(const ATrack: TRect; AKind: TTyScrollBarKind;
  AMin, AMax, APosition, APageSize: Integer; ARightToLeft: Boolean): TRect;
var
  TrackLen, Span, ThumbLen, FreeSpace, Travel, Pos0, Offset: Integer;
  Cross, MinThumb: Integer;
begin
  if AKind = sbVertical then
    TrackLen := ATrack.Bottom - ATrack.Top
  else
    TrackLen := ATrack.Right - ATrack.Left;
  Span := (AMax - AMin) + APageSize;
  if (Span <= 0) or (APageSize <= 0) or (AMax <= AMin) then
  begin
    // degenerate: nothing to scroll, thumb fills the whole track
    Result := ATrack;
    Exit;
  end;
  ThumbLen := (APageSize * TrackLen) div Span;
  if AKind = sbVertical then Cross := ATrack.Right - ATrack.Left else Cross := ATrack.Bottom - ATrack.Top;
  MinThumb := Cross; if MinThumb < 6 then MinThumb := 6;
  if ThumbLen < MinThumb then ThumbLen := MinThumb;
  if ThumbLen > TrackLen then ThumbLen := TrackLen;
  FreeSpace := TrackLen - ThumbLen;
  Travel := AMax - AMin;
  Pos0 := APosition - AMin;
  if Pos0 < 0 then Pos0 := 0;
  if Pos0 > Travel then Pos0 := Travel;
  if Travel <= 0 then
    Offset := 0
  else
    Offset := Integer((Int64(Pos0) * FreeSpace) div Travel);
  Offset := TyScrollMirrorOffset(Offset, FreeSpace, AKind, ARightToLeft);
  if AKind = sbVertical then
    Result := Rect(ATrack.Left, ATrack.Top + Offset,
      ATrack.Right, ATrack.Top + Offset + ThumbLen)
  else
    Result := Rect(ATrack.Left + Offset, ATrack.Top,
      ATrack.Left + Offset + ThumbLen, ATrack.Bottom);
end;

function TyScrollButtonSize(const AClient: TRect; AKind: TTyScrollBarKind): Integer;
begin
  if AKind = sbVertical then
    Result := AClient.Right - AClient.Left
  else
    Result := AClient.Bottom - AClient.Top;
  if Result < 1 then Result := 1;
end;

function TyScrollTrackRect(const AClient: TRect; AKind: TTyScrollBarKind;
  AButtonSize: Integer): TRect;
var
  mainLen: Integer;
begin
  Result := AClient;
  if AKind = sbVertical then
    mainLen := AClient.Bottom - AClient.Top
  else
    mainLen := AClient.Right - AClient.Left;
  if mainLen <= 2 * AButtonSize then Exit;   // too short for two buttons -> whole client, no buttons
  if AKind = sbVertical then
    Result := Rect(AClient.Left, AClient.Top + AButtonSize,
      AClient.Right, AClient.Bottom - AButtonSize)
  else
    Result := Rect(AClient.Left + AButtonSize, AClient.Top,
      AClient.Right - AButtonSize, AClient.Bottom);
end;

constructor TTyScrollBar.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // KeyDown below implements the whole native keyboard: line, page and end-to-end. None of
  // it could ever run, because LCL defaults TabStop to False and TTyCustomControl.MouseDown
  // gates click-to-focus on it. Controls that EMBED a bar (list box, memo, grid, tree,
  // scroll box) turn it back off on their instance — see the comments there.
  TabStop := True;
  FKind := sbVertical;
  FMin := 0;
  FMax := 100;
  FPosition := 0;
  FPageSize := 10;
  FSmallChange := 1;
  FLargeChange := 0;           // 0 == page by PageSize (see the property comment)
  FMirrorH := False;           // opt-in; see the MirrorHorizontal property comment
  FLiveTracking := True;       // what this bar has always done; see the property comment
  FTrackPos := FPosition;
  FAnimEnabled := True;
  FAutoHide := sbahDefault;    // 跟主题走;与 published 的 default 一致
  { 出生就是全可见。主题关着自动隐藏时这个值再也不会变,这也正是
    「不开这个特性的人一分钱不花」的那条路。 }
  FFadeLevel := 1.0;
  // Thumb-glide animator: 0..1 traversal in ~120ms, decelerating. Start settled
  // at the rest endpoint so DisplayPos == FPosition before any change.
  FPosAnim.Progress := 1;
  FPosAnim.Target := 1;
  FPosAnim.DurationMs := 120;
  FPosAnim.Easing := teEaseOutCubic;
  FAnimFrom := FPosition;
  FAnimTo := FPosition;
  // Scrollbar thickness (cross-axis) follows the density-aware --scrollbar-size
  // token, the SAME token TTyScrollBox.ScrollbarThick reads. Classic resolves to
  // TyScrollbarSize (12); modern density packs raise it. Height (default length)
  // stays a plain constant.
  Width := MulDiv(ActiveController.Metric('--scrollbar-size', TyScrollbarSize), Font.PixelsPerInch, 96);
  Height := 160;
end;

destructor TTyScrollBar.Destroy;
begin
  // FTimer is owned by Self (would be freed by DestroyComponents), but free it
  // explicitly first so the OnTimer callback can never fire mid-teardown.
  FreeAndNil(FTimer);
  { 同理:淡出定时器的回调也不能在拆到一半的对象上跑。 }
  FreeAndNil(FHideTimer);
  inherited Destroy;
end;

function TTyScrollBar.GetStyleTypeKey: string;
begin
  Result := 'TyScrollBar';
end;

function TTyScrollBar.Mirrored: Boolean;
begin
  Result := FMirrorH and (FKind = sbHorizontal);
end;

procedure TTyScrollBar.SetMirrorHorizontal(const AValue: Boolean);
begin
  if FMirrorH = AValue then Exit;
  FMirrorH := AValue;
  { Only the thumb's x moves; the frame, the track and both end buttons are already
    symmetric, so a repaint is the whole update. }
  Invalidate;
end;

procedure TTyScrollBar.SetAutoHide(const AValue: TTyScrollBarAutoHide);
begin
  if FAutoHide = AValue then Exit;
  FAutoHide := AValue;
  { 为什么不是裸字段写:淡出跑完之后定时器会把自己停掉，那一刻没有任何东西
    在推进状态。此时把 AutoHide 改成 sbahNever,「关掉了就恢复全可见」那条臂
    永远轮不到执行，滚动条就永久隐身；sbahDefault -> sbahAuto 同理，没人会去
    把定时器启起来。所以属性变化必须能叫醒一条已经停摆的滚动条：重置空闲计时、
    该淡回来的淡回来、该重新起表的把表起起来,全在 NoteActivity 里。 }
  FIdleMs := 0;
  NoteActivity;
  Invalidate;
end;

function TTyScrollBar.EffectiveAutoHideMs: Integer;
var
  themeMs: Integer;
begin
  if FAutoHide = sbahNever then
    Exit(TyScrollBarAutoHideOff);
  themeMs := ThemeAutoHideMs;
  if FAutoHide = sbahAuto then
  begin
    { 属性明说要隐藏。主题关着（或没说）时不能跟着关，否则这个属性是个谎。

      契约里的「关」只有 TyScrollBarAutoHideOff 一个值；这里放宽到任何负数,
      是因为主题作者手写个 -2 显然也是想关，没道理让它掉进回退。
      **0 不在此列** —— 0 是「停手立即淡出」，是个合法延时，不是关。 }
    if themeMs < 0 then
      Exit(TyScrollBarAutoHideFallbackMs);
    Exit(themeMs);
  end;
  Result := themeMs;   // sbahDefault
end;

function TTyScrollBar.ThemeAutoHideMs: Integer;
{ --scrollbar-auto-hide 的解析结果，缓存在 (model, ThemeVersion) 上。

  为什么值得缓存：ResolveMetric **即使缓存命中**也要先拼一个
  AName + '|' + IntToStr(ADefault) 的 key 再 IndexOf ——每次调用一个堆字符串。
  而这个函数在常见路径上一拍要被问两次(AutoHideTick 一次、HandleHideTimer 的
  停表判断一次)，60fps × 最多 12 条内嵌条，静止不动的条也能烧掉每秒上千次
  字符串分配。TTyMemo 已经在逐帧开销上栽过一次(0.5 秒一键)。

  为什么是版本锚而不是「主题变了就作废」：**没有主题变更通知这回事**。
  TTyStyleController.Changed 广播出来的只有一个裸 Invalidate，全 source/ 没有
  StyleChanged 钩子。照字面写「变更时作废」，做出来的是一个永远供应旧主题
  延时的缓存。库里现成的做法就是拿 ThemeVersion 当锚(tyControls.Base.pas:767、
  :1670)。

  键里除了版本还有 model 身份：版本号是**每个 model 各自算的**，两个 controller
  都只加载过一次主题的话版本号一模一样，只按版本号键控会把 A 的延时端给 B ——
  而 Controller 是个 published 属性，中途换得掉。

  **缓存只盖住主题这一半。** 属性那一半(sbahNever/sbahAuto 的回退)留在
  EffectiveAutoHideMs 里没有缓存：那几步是整数比较，缓存它省不下什么，却要
  SetAutoHide 记得去作废它——忘了作废正是缓存变成 bug 的方式。 }
var
  { ActiveController，不是裸 Controller——后者在没挂 controller 时会 AV。
    全拎进局部变量:命中那条路是本函数存在的全部理由,别在上面反复问。 }
  ctrl: TTyStyleController;
  mdl: TTyStyleModel;
  ver: Cardinal;
begin
  ctrl := ActiveController;
  mdl := ctrl.Model;
  ver := mdl.ThemeVersion;
  { 存下去的是 TObject:那个字段只拿来比相等,永远不解引用。 }
  if (FAutoHideMsAnchor = TObject(mdl)) and (FAutoHideMsVer = ver) then
    Exit(FAutoHideMsCache);
  FAutoHideMsCache := ctrl.Metric(TyScrollBarAutoHideVar, TyScrollBarAutoHideDef);
  FAutoHideMsVer := ver;
  FAutoHideMsAnchor := TObject(mdl);
  Result := FAutoHideMsCache;
end;

function TTyScrollBar.AutoHideHeldOpen: Boolean;
begin
  { 任一成立就「按住不放」，延时表根本不起。
    注意 Focused 只对独立摆放的条有意义：内嵌条既不进 Tab 顺序(TabStop=False),点击也把
    焦点交给宿主(FocusAfterClick),所以这一臂对内嵌条恒假。内嵌条拖动时靠的是 FDragging
    (和拖动途中指针在不在条上无关),指针在宿主上靠 FHostHovered —— 没有哪一臂指望它有焦点。

    **FHover 和 FHostHovered 必须合起来判——交界处不抖的全部理由就在这里。**
    条是窗口化子控件：指针从宿主内容挪到条上时，宿主收到 MouseLeave、条收到
    MouseEnter，**两者的先后 LCL 不保证**。只认其中一个的话，先到的那个转假的
    瞬间条就该淡了，用户看到的是移到条上的一刹那它闪一下。两个或起来，再加上
    「离开只起表、不当场隐藏」（见 SetHostHovered），交界处就没有一帧是在淡的。 }
  Result := FHover or FHostHovered or FDragging or (csDesigning in ComponentState)
            or (HandleAllocated and Focused);
end;

procedure TTyScrollBar.NoteActivity;
begin
  FIdleMs := 0;
  if EffectiveAutoHideMs < 0 then
  begin
    { 关着的时候**没有任何东西**会再推进淡入淡出 —— 定时器不起,淡入就算装上了
      也永远跑不起来。所以「回到全可见」必须在这里当场做掉,否则一条已经淡掉的
      条,在主题或属性把自动隐藏关掉之后会永久隐身。关闭臂就在 AutoHideTick 里,
      喂它一拍即可,不必抄一遍。 }
    AutoHideTick(0);
    Exit;
  end;
  { 光看可见度不够。淡出「装上了膛但还没推进」的那一拍,可见度还正好是 1.0,
    膛里装的却是 0.0 —— 只判 FFadeLevel < 1.0 的话这里什么也不做,那发淡出
    下一拍照常打出去。而淡出跑动期间不计闲置、跑完可见度又成了 0,条就一直
    不见了:用户看到的是「滚了一下,条反而没了」。所以还要问一句:有没有一发
    反方向的动画正在跑。 }
  if (FFadeLevel < 1.0) or (FFadeAnim.Running and (FFadeTo < 1.0)) then
    StartFade(1.0, TyScrollBarFadeInMs);
  EnsureHideTimer;
  if FHideTimer <> nil then FHideTimer.Enabled := True;
end;

procedure TTyScrollBar.SetHostHovered(AValue: Boolean);
begin
  if FHostHovered = AValue then Exit;
  FHostHovered := AValue;
  { **进来无条件叫醒，离开只在条真的看得见的时候起表。** 两边不对称是有理由的。

    离开那一半要挡：内容装得下的时候宿主把条 Visible 关了，而 NoteActivity 会给
    它挂上 16ms 一拍的定时器，一路转完「延时 + 淡出」（默认 1.4 秒）——为一个一
    个像素都不画的控件。指针每划过一个不需要滚动的列表就来这么一次，两条。

    进来那一半**不能挡**：一条淡到 0 之后才被宿主收起来的条，等内容长出来、
    宿主把它重新显示的那一刻，指针还在宿主上——AutoHideHeldOpen 恒真，
    AutoHideTimerNeeded 就恒答「不用起表」，条会停在 0 上永远不露面，
    正是这次要修的那类 bug。而叫醒一条看不见的条最多花一拍：按住不放的时候
    表头一拍就把自己停掉。

    字段则**无条件**记：等宿主把条显示出来的那一刻，「指针还在宿主上」这件事
    必须是准的。离开之后要起的那块表由 Invalidate 那条臂补上——它判的就是
    「没表就起表」。 }
  if AValue or Visible then NoteActivity;
end;

procedure TTyScrollBar.StartFade(ATo: Single; ADurationMs: Integer);
begin
  { 「已经在那儿了」只有在**没有反方向的动画在跑**的时候才等于「无事可做」。
    只比可见度的话,装了膛还没推进的那一拍(可见度 1.0、目标 0.0)会在这里
    早退,上面那句重定向就白写了。 }
  if SameValue(FFadeLevel, ATo, 0.001) and
     (not FFadeAnim.Running or SameValue(FFadeTo, ATo, 0.001)) then Exit;
  FFadeFrom := FFadeLevel;
  FFadeTo := ATo;
  FFadeAnim := TyAnimatorInit(ADurationMs, teEaseOutCubic);
end;

function TTyScrollBar.PaintStyle: TTyStyleSet;
{ 主题给的那份样式，乘上自动隐藏的当前可见度。

  乘出来的 Opacity 是**条身这一层**合成到底下时的不透明度(见 RenderTo),不再交给画笔。
  从前交给画笔:EndPaint 先铺一层 OpacityBase —— 从父控件**正中间取样的一个颜色** ——
  再把整张图按 opacity 盖上去,于是淡出途中条那一块底色是一块平板,渐变背景上实测上下
  两头差 0,而真背景差 221。那条路是全库所有 opacity 共用的(TyApplyStyleOpacity),
  修它等于改 Base.pas 里人人都在用的代码;在条自己的 RenderTo 里分层合成就绕开了。

  完全可见时**原样**交出去，一个字段都不碰：独立摆放、完全可见的条走的还是原来那条
  DrawFrame 路,多写一个 tpOpacity 进去就把它从「不合成」挪到「合成」上,而没开自动
  隐藏的条一个像素都不许变。守它的是 test.scrollbar.autohide 的
  AtRestTheThemeStyleIsHandedOverUntouched。

  乘法不是摆设：主题给 TyScrollBar:disabled 写了 opacity(light/dark/green/
  system/showcase 都有),一条禁用的条淡出时要的是两者相乘,而不是拿淡出
  系数把主题那个值顶掉。 }
var
  base: Single;
begin
  Result := CurrentStyle;
  if SameValue(FFadeLevel, 1.0, 0.001) then Exit;
  { record 是非托管的：契约是 Present 那个集合——它没说有 tpOpacity，
    Result.Opacity 里是什么就不归契约管，不能直接乘上去。
    (今天 EmptyStyleSet 恰好把它种成 1.0，所以直接乘也能给出同一个答案；
    这句防的是「哪天种子变了、或者换一条不经过 EmptyStyleSet 的路进来」，
    那种事不会在这个单元里报错，只会让滚动条整条消失。) }
  if tpOpacity in Result.Present then base := Result.Opacity else base := 1.0;
  Result.Opacity := base * FFadeLevel;
  Include(Result.Present, tpOpacity);
end;

function TTyScrollBar.PaintStyleForTest: TTyStyleSet;
begin
  Result := PaintStyle;
end;

procedure TTyScrollBar.AutoHideTick(AMs: Integer);
var
  delay: Integer;
begin
  delay := EffectiveAutoHideMs;
  if delay < 0 then
  begin
    { 关着。任何残留的淡出都要收回来，否则改主题/改属性之后条会停在半透明。

      **停动画这一下不能挂在「可见度不对」里面**:可见度正好是 1.0、动画却还在
      跑的状态是够得着的 —— 淡出刚装上膛(Progress=0)可见度就是 1.0,淡入跑到
      Progress=0.9333 时缓动值 0.9997 也落在容差里。漏掉的话:定时器那句「没事
      干就歇」永远不成立,一条关着自动隐藏的条上挂着个 60fps 的空转定时器;
      哪天又把自动隐藏打开,膛里那发陈旧的淡出还会接着打出去。 }
    FFadeAnim.SetTargetImmediate(1.0);
    if not SameValue(FFadeLevel, 1.0, 0.001) then
    begin
      FFadeLevel := 1.0;
      Invalidate;
    end;
    Exit;
  end;

  if FFadeAnim.Running then
  begin
    if FFadeAnim.Advance(AMs) then
    begin
      FFadeLevel := TyLerpF(FFadeFrom, FFadeTo, FFadeAnim.Eased);
      Invalidate;
    end;
    if not FFadeAnim.Running then FFadeLevel := FFadeTo;
    Exit;   { 动画期间不计闲置——否则淡入刚跑一半就被判定该淡出 }
  end;

  if AutoHideHeldOpen then
  begin
    FIdleMs := 0;
    Exit;
  end;

  Inc(FIdleMs, AMs);
  if (FIdleMs >= delay) and (FFadeLevel > 0.0) then
    StartFade(0.0, TyScrollBarFadeOutMs);
end;

procedure TTyScrollBar.EnsureHideTimer;
begin
  { 设计期不淡(AutoHideHeldOpen 已经恒真),无窗口时也不建表——无头测试直接
    喂 AutoHideTick,建了也只是个永远空转的定时器。 }
  if (csDesigning in ComponentState) or not HandleAllocated then Exit;
  if FHideTimer = nil then
  begin
    FHideTimer := TTimer.Create(Self);
    FHideTimer.Enabled := False;
    FHideTimer.Interval := 16;   // ~60fps
    FHideTimer.OnTimer := @HandleHideTimer;
  end;
end;

procedure TTyScrollBar.ArmAutoHideClock;
begin
  { 真正的门是第二句 AutoHideTimerNeeded:已经淡到 0 又没人按住的条起表也没活干,
    头一拍就会把自己停掉——那一拍是白烧的,而且 HandleHideTimer 停表时顺手清掉
    FFadeLastTickMs,看着像什么都没发生过,查起来更费事。

    头一句是**热路径的短路**,不是第二道保险:AutoHideTimerNeeded 最后问的就是
    同一个 EffectiveAutoHideMs >= 0,所以单独摘掉头一句,行为上几乎看不出来
    ——变异测试证实过,全量 7103 条一条不红。它在这儿是因为 Invalidate 一秒钟
    要走几十次,而自动隐藏关着的条应该在**第一个字段读**上就出去,不该先绕过
    FFadeAnim.Running、再绕过 AutoHideHeldOpen(那里面还有一次 Focused,要问
    widgetset)。顺带也真挡住一种状态:淡出刚装上膛还没推进(可见度仍是 1.0)
    的那一刻主题把自动隐藏关掉,AutoHideTimerNeeded 会在 FFadeAnim.Running 上
    答 True —— 没这一句就会给一条主人已经关掉特性的条挂上表(下一拍自己会停,
    所以测不出来,但那一拍本来就不该有)。

    **这里不碰 FIdleMs**,理由见声明处。 }
  if EffectiveAutoHideMs < 0 then Exit;
  if not AutoHideTimerNeeded then Exit;
  EnsureHideTimer;
  if FHideTimer <> nil then FHideTimer.Enabled := True;
end;

function TTyScrollBar.AutoHideClockArmed: Boolean;
begin
  Result := (FHideTimer <> nil) and FHideTimer.Enabled;
end;

procedure TTyScrollBar.InitializeWnd;
begin
  inherited InitializeWnd;
  { 两个时钟都从这一刻起算。一条刚拿到句柄的条没有「已经闲置过的时间」——
    出生那一段它根本还不在屏幕上;FFadeLastTickMs 同理,留着出生前的旧戳的话
    头一拍会把那一整段报成经过时间,闲置时钟一步跨过延时,条一露面就开始淡。 }
  FIdleMs := 0;
  FFadeLastTickMs := 0;
  ArmAutoHideClock;
end;

function TTyScrollBar.AutoHideTimerNeeded: Boolean;
{ 三条,顺序是有讲究的。

  **跑着的淡入淡出排第一,这一条不是风格问题,是 Task 3 那个搁浅 bug 的完整重演。**
  一条已经淡到 0、表也停了的条,指针移到它(看不见的)那块地方上:MouseEnter ->
  NoteActivity 把淡入装上膛、把表起起来。要是先问「按住没有」,起起来的表**头一拍
  就把自己停掉**,而指针一直搁在那儿,再没有第二个 MouseEnter —— 条就在指针底下
  永远不出现。半路上被压住的淡出同理,会卡在半透明。

  「按住不放」要停表:指针停在滚动条上是个极其常见的鼠标停靠位置，而按住的时候
  本来就没有任何东西要推进(AutoHideTick 那条臂只是把闲置时钟清成 0)，让它以
  16ms 转下去纯属白烧。离开/失焦/松手三处各自调 NoteActivity 把表起回来;
  **单就那三处而言**,万一哪处漏了坏的方向是「条多留一会儿」,随便碰一下就恢复
  ——这句只管重启那三处,不管上面那个顺序,别拿它去给重排这几行背书。

  最后才问延时。它也不只是「省一次主题解析」:自动隐藏关掉(换主题或改属性)
  的那一刻表要是正转着,没有这一条它就**再也停不下来** —— 一条主人压根没开
  这个特性的滚动条上挂着个 60fps 的空转定时器,而构造函数许诺的是「不开这个
  特性的人一分钱不花」。 }
begin
  if FFadeAnim.Running then Exit(True);
  if AutoHideHeldOpen then Exit(False);
  Result := (EffectiveAutoHideMs >= 0) and (FFadeLevel > 0.0);
end;

procedure TTyScrollBar.HandleHideTimerTick;
begin
  HandleHideTimer(nil);
end;

procedure TTyScrollBar.HandleHideTimer(Sender: TObject);
begin
  { 按**真实经过的时间**推进,不是 FHideTimer.Interval 那个标称的 16。理由和
    200 行开外的 HandleTimer 一模一样:界面忙的时候定时器会被饿死,而**网格滚动
    中正是这段代码在跑的时候** —— 按标称累加的话 200 毫秒的淡出要爬将近一秒,
    1200 毫秒的延时能拖成好几秒。 }
  AutoHideTick(FadeTickElapsedMs);
  if not AutoHideTimerNeeded then
  begin
    { 停表必须把时刻戳一起清掉。下次起表可能是几分钟之后(指针一直压在条上),
      带着旧戳的话头一拍会把那整段时间报出来:闲置时钟一步跨过延时,指针刚一
      离开条就没了。位置缓动那边 HandleTimer 出于同样的理由清 FLastTickMs。 }
    FFadeLastTickMs := 0;
    { 判空:表是惰性建的(无头根本不建),而这个回调还能从 HandleHideTimerTick
      进来。和位置缓动的 HandleTimer 同一处理。 }
    if FHideTimer <> nil then FHideTimer.Enabled := False;
  end;
end;

function TTyScrollBar.FadeNowMs: QWord;
begin
  Result := GetTickCount64;
end;

function TTyScrollBar.FadeTickElapsedMs: Integer;
{ TickElapsedMs 的孪生体,自带时刻戳。**不能共用 FLastTickMs** ——那是位置缓动
  的,两套定时器各跑各的,共用一个戳就是互相把对方的起点冲掉。

  钳到至少 1 毫秒:除了讲得通,它还是挡住 0 毫秒步长的那道闸 —— TTyAnimator.Advance
  把 AMs <= 0 当成「直接吸附到 Target」,一个 0 毫秒的滴答会把淡出变成跳变。
  而 0 毫秒的一拍不是假想:两拍落在同一个 GetTickCount64 刻度里就是 0。 }
var
  nowMs: QWord;
begin
  nowMs := FadeNowMs;
  if FFadeLastTickMs = 0 then
    Result := 16
  else
    Result := Integer(nowMs - FFadeLastTickMs);
  FFadeLastTickMs := nowMs;
  if Result < 1 then Result := 1;
end;

procedure TTyScrollBar.MouseEnter;
begin
  { 不调 inherited 会吞掉 LCL 那层的 hover 状态。而「指针在不在条上」这件事
    inherited 已经记在 FHover 里了(TTyCustomControl.MouseEnter/MouseLeave 是
    全库仅有的两处写入),本控件画滑块时读的也是它 —— 所以这里不再另存一份,
    AutoHideHeldOpen 直接问 FHover。两个字段记同一件事,迟早会不一致。

    MouseLeave 从前不必重写,理由是「指针在条上的每一拍,按住不放那条臂都把闲置
    时钟清成 0 了,离开的那一刻它本来就是 0」。**那条理由现在不成立了**:按住的
    时候延时表是停的(见 AutoHideTimerNeeded),根本没有「每一拍」这回事,指针
    一走也就没人把表起回来。见 MouseLeave。 }
  inherited MouseEnter;
  NoteActivity;
end;

procedure TTyScrollBar.MouseLeave;
begin
  { 先 inherited:FHover 由它清(全库只有 TTyCustomControl.MouseEnter/MouseLeave
    写这个字段),清完 AutoHideHeldOpen 才答「没按住」。

    然后 NoteActivity —— 这是本方法存在的全部理由:表在指针压上来的时候停了,
    这里不把它起回来的话,条就一直留在屏幕上。顺带把闲置从「离开这一刻」重新
    起算,那本来就是该有的语义。

    NoteActivity 里 FHideTimer.Enabled := True 是**下一拍**才生效的(16ms 之后),
    所以哪怕这一刻 FHover 还没清干净也不要紧:等表真转起来的时候,状态早就稳了。
    DoExit 那一半就是靠这个才不必去操心 LCL 什么时候把 Focused 翻成 False。 }
  inherited MouseLeave;
  NoteActivity;
end;

procedure TTyScrollBar.DoEnter;
begin
  { 焦点不只是「不计时」,还得**把条叫回来**。独立摆放的条 TabStop=True:等它
    淡到 0、定时器把自己停掉之后再 Tab 过来,按住不放那条臂连跑的机会都没有
    (没人推它了),键盘焦点就停在一个看不见的控件上 —— 这是可访问性事故,
    不是设计。悬停那一半由 MouseEnter 拿到,焦点这一半得自己写。

    从前说「不写对应的 DoExit」,理由和 MouseLeave 那条一样,也和它一起作废了:
    见 DoExit。 }
  inherited DoEnter;
  NoteActivity;
end;

procedure TTyScrollBar.DoExit;
begin
  { 和 MouseLeave 同理,焦点这一半:有焦点的那段延时表是停的,这里不起回来的话条就
    一直留着。**只有独立摆放的条走得到这里。** 从前内嵌条也走得到 —— MouseDown 里那句
    无条件的 if CanFocus then SetFocus 把焦点给了它,「点一下条、再去点别处」就进来了;
    现在点内嵌条焦点归宿主(FocusAfterClick),内嵌条不再有 DoEnter/DoExit。 }
  inherited DoExit;
  NoteActivity;
end;

procedure TTyScrollBar.Invalidate;
begin
  { 换主题是这个类唯一听不见的事件:TTyStyleController.Changed 广播出来的就是
    一个光秃秃的 Invalidate(它自己的注释也这么写),全库没有 StyleChanged 钩子。
    于是「自动隐藏的主题下淡到 0、定时器把自己停了,再换到一个不自动隐藏的主题」
    会让条永久隐身:没有任何东西会再推它一拍。属性那条路(SetAutoHide ->
    NoteActivity)早就防了同一个坑,主题这半边只能挂在这里。

    为什么不用 AddChangeListener:全库的控件没有一个用它(只有 TTyNativeStyler
    那种非可视组件在用,它自己管 controller 的加和摘),而控件的 Controller 可以
    中途换、还能是 nil 回落到进程级的 TyDefaultController —— 把每一根滚动条的
    方法指针塞进那张全局表,哪回忘了摘就是野指针。

    重绘是热路径,所以三个条件的**顺序**是有讲究的:前两个都只是读字段,常态
    (可见度就是 1.0)在第二个条件上就短路了,要读主题的那个条件只有在条真的
    淡着的时候才走得到。(那次解析现在带缓存了——见 ThemeAutoHideMs——但命中
    也不是免费的,顺序照旧。)
    not FFadeAnim.Running 也是必须的:正在跑的淡入淡出不能被这里掐断。 }
  Inc(FInvalidations);
  if (not FFadeAnim.Running) and (FFadeLevel < 1.0) and (EffectiveAutoHideMs < 0) then
  begin
    FFadeAnim.SetTargetImmediate(1.0);
    FFadeLevel := 1.0;
  end
  { **换主题的另一半方向,从前这里是空的。** 上面那条管「换到一个不自动隐藏的
    主题」,可反过来——换到一个自动隐藏的皮肤——同样没有任何东西会去起表:
    条没被碰过就没有 NoteActivity,句柄早就有了所以 InitializeWnd 也过去了,
    于是新皮肤明明写了 1200,条却一直亮着。跟上面那条是同一个根:换主题只有
    Invalidate 这一个广播。

    顺序是为热路径挑的,不是随手写的:重绘一秒钟几十次,而绝大多数重绘发生在
    表已经转着的条上——先读 FHideTimer.Enabled 这个字段,那种情形一次比较就
    短路了;自动隐藏关着的条落到 ArmAutoHideClock,头一句就是带缓存的
    EffectiveAutoHideMs,同样立刻出来。 }
  else if (FHideTimer = nil) or (not FHideTimer.Enabled) then
    ArmAutoHideClock;
  inherited Invalidate;
end;

procedure TTyScrollBar.EnsureTimer;
begin
  if FTimer = nil then
  begin
    FTimer := TTimer.Create(Self);
    FTimer.Enabled := False;
    FTimer.Interval := 16;  // ~60fps
    FTimer.OnTimer := @HandleTimer;
  end;
end;

{ 这一拍该推进多少毫秒 = 距上一拍的**真实**经过时间。
  抽成可覆写的,是为了让测试能喂一个受控时钟 —— 否则"按真实时间推进"
  这条只能靠肉眼在真机上看,而这正是当初写成名义间隔也没人发现的原因。 }
function TTyScrollBar.TickElapsedMs: Integer;
var
  nowMs: QWord;
begin
  nowMs := GetTickCount64;
  if FLastTickMs = 0 then
    Result := 16
  else
    Result := Integer(nowMs - FLastTickMs);
  FLastTickMs := nowMs;
  if Result < 1 then Result := 1;
end;

procedure TTyScrollBar.HandleTimerTick;
begin
  HandleTimer(nil);
end;

procedure TTyScrollBar.HandleTimer(Sender: TObject);
var
  elapsed: Integer;
begin
  { 按**真实经过的时间**推进,不能按定时器的名义间隔累加。

    界面忙的时候(例如大网格重绘一帧要上百毫秒)定时器会被饿死:
    按名义 16ms 一步的话,120ms 的缓动要七八次滴答才走完,而每次滴答实际隔了
    上百毫秒 —— 缓动被拉成将近一秒,看起来就是"滑块慢一拍才跟上"。
    按真实时间推进时,一次迟到的滴答会把该走的进度一次补齐。 }
  elapsed := TickElapsedMs;
  if AdvanceAnimation(elapsed) then
    Invalidate;
  if not FPosAnim.Running then
  begin
    { 定时器是**惰性创建**的(SetPositionAnimating 这个测试缝就不建它),
      所以这里必须判空 —— 从前是直接 FTimer.Enabled,靠"只有定时器自己会调
      HandleTimer"这个隐含前提撑着。 }
    if FTimer <> nil then FTimer.Enabled := False;
    FLastTickMs := 0;
  end;
end;

function TTyScrollBar.AdvanceAnimation(AMs: Integer): Boolean;
begin
  Result := FPosAnim.Advance(AMs);
end;

function TTyScrollBar.DisplayPos: Single;
begin
  { Mid-drag with LiveTracking off, the thumb is ahead of Position on purpose -- that gap IS
    the mode. Everything that PAINTS the thumb goes through here, so putting the exception in
    this one function is what keeps the hit test and the paint agreeing: MouseDown's thumb-rect
    test uses FPosition, and during such a drag the hit test is irrelevant (we already have the
    capture), while at rest FTrackPos = FPosition and the two are the same number again. }
  if FDragging and not FLiveTracking then
    Exit(FTrackPos);
  Result := TyLerpF(FAnimFrom, FAnimTo, FPosAnim.Eased);
end;

procedure TTyScrollBar.SetPositionAnimating(AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := AValue;
  if Clamped < FMin then Clamped := FMin;
  if Clamped > FMax then Clamped := FMax;
  // Arm the ease from the currently displayed thumb position to the new target,
  // independent of handle state (test seam). FPosition still tracks the logical
  // value for Min/Max/value semantics.
  FAnimFrom := DisplayPos;
  FAnimTo := Clamped;
  FPosAnim.Progress := 0;
  FPosAnim.Target := 1;
  FPosition := Clamped;
  Invalidate;
end;

procedure TTyScrollBar.SetPositionSnapped(AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := AValue;
  if Clamped < FMin then Clamped := FMin;
  if Clamped > FMax then Clamped := FMax;

  { 无条件停掉可能正在跑的缓动 —— 哪怕位置没变也要停,
    否则上一次的缓动会继续把滑块拖向一个**过时**的目标。 }
  FAnimFrom := Clamped;
  FAnimTo := Clamped;
  FPosAnim.SetTargetImmediate(1);
  if FTimer <> nil then FTimer.Enabled := False;

  if FPosition = Clamped then
  begin
    Invalidate;
    Exit;
  end;
  FPosition := Clamped;
  Invalidate;
  if Assigned(FOnChange) then FOnChange(Self);

  { 镜像过来的位置一样算「在用」。这条路**绕开了 Position 的 setter**,所以
    唤醒必须在这里单独写一遍 —— 全库只有 TTyGrid 走它(其余五个宿主都是
    Position := ),而网格恰恰是最该看见滚动条出来的那个控件。

    这条路跳过位置缓动,是因为内容已经被宿主挪走了、滑块再缓动追过去就不跟手;
    那跟「这条滚动条该不该看得见」是两码事,别把两件事连坐。

    网格有两处调用写着 if not Dragging then ——那时候条本来就被 FDragging
    按住不放,这里不会重复唤醒,别当成冗余顺手删掉。 }
  NoteActivity;
end;

procedure TTyScrollBar.SetKind(const AValue: TTyScrollBarKind);
begin
  if FKind = AValue then Exit;
  FKind := AValue;
  Invalidate;
end;

procedure TTyScrollBar.SetMin(const AValue: Integer);
begin
  if FMin = AValue then Exit;
  FMin := AValue;
  if FPosition < FMin then FPosition := FMin;
  Invalidate;
end;

procedure TTyScrollBar.SetMax(const AValue: Integer);
begin
  if FMax = AValue then Exit;
  FMax := AValue;
  if FPosition > FMax then FPosition := FMax;
  Invalidate;
end;

procedure TTyScrollBar.SetPosition(const AValue: Integer);
var
  Clamped: Integer;
begin
  Clamped := AValue;
  if Clamped < FMin then Clamped := FMin;
  if Clamped > FMax then Clamped := FMax;
  if FPosition = Clamped then Exit;
  // Decide how the PAINTED thumb reaches the new value:
  if FDragging then
  begin
    // Live drag: the thumb must track the mouse, so snap instantly.
    FAnimFrom := Clamped;
    FAnimTo := Clamped;
    FPosAnim.SetTargetImmediate(1);
    FNeedImmediateRepaint := True;
  end
  else if FAnimEnabled and HandleAllocated then
  begin
    // Programmatic change with a window: ease the thumb from where it is now to
    // the new value. (Headless render tests have no handle -> they snap below.)
    FAnimFrom := DisplayPos;
    FAnimTo := Clamped;
    FPosAnim.Progress := 0;
    FPosAnim.Target := 1;
    EnsureTimer;
    FLastTickMs := 0;          { 重新起算,别把上一段动画的时刻带进来 }
    FTimer.Enabled := True;
  end
  else
  begin
    // Headless (no handle) or animations off: snap so DisplayPos == new
    // immediately, keeping the existing exact-pixel scrollbar tests green.
    FAnimFrom := Clamped;
    FAnimTo := Clamped;
    FPosAnim.SetTargetImmediate(1);
  end;
  FPosition := Clamped;
  Invalidate;

  { 拖动中**立刻把自己重画掉**,不要排队等下一轮消息循环。

    滑块是独立的窗口化控件,本来有自己的 WM_PAINT;但 WM_PAINT 优先级最低,
    宿主(大网格一帧要几十毫秒)一忙,滑块的重绘就被挤到后面 —— 表现就是
    "内容在动、滑块慢半拍"。自己这块表面很小(实测整屏 blit 才 0.8ms,
    滑块只有它的百分之一),同步刷一次完全不心疼。

    只在拖动时这么做:程序性变化走正常的排队重绘,不必抢。 }
  if FNeedImmediateRepaint then
  begin
    FNeedImmediateRepaint := False;
    if HandleAllocated then Update;
  end;

  if Assigned(FOnChange) then
    FOnChange(Self);

  { 位置变了就是「在用」——哪怕这一下是宿主代码赋的值。滚轮、键盘、点滑道
    都经过这里,所以唤醒写在这一处就够,不必在每个手势里各来一遍。
    **SetPositionSnapped 不经过这里**:宿主自己滚完内容、再把位置镜像给滑块的
    那条路是单独的一条,接线是宿主那一步的事。 }
  NoteActivity;
end;

procedure TTyScrollBar.SetPageSize(const AValue: Integer);
begin
  if FPageSize = AValue then Exit;
  if AValue < 0 then
    FPageSize := 0
  else
    FPageSize := AValue;
  Invalidate;
end;

procedure TTyScrollBar.SetSmallChange(const AValue: Integer);
begin
  if AValue < 1 then
    FSmallChange := 1
  else
    FSmallChange := AValue;
end;

procedure TTyScrollBar.SetLargeChange(const AValue: Integer);
begin
  // Negative is meaningless (a page action would scroll backwards); 0 is the "follow
  // PageSize" sentinel, so it is the floor rather than 1.
  if AValue < 0 then
    FLargeChange := 0
  else
    FLargeChange := AValue;
end;

{ FTrackPos is only meaningful for the duration of a deferred drag; outside one the pending
  value IS the committed value, and deriving that here rather than keeping the field in sync
  from every setter leaves exactly one place that can be wrong. }
function TTyScrollBar.GetTrackPosition: Integer;
begin
  if FDragging and not FLiveTracking then
    Result := FTrackPos
  else
    Result := FPosition;
end;

function TTyScrollBar.EffectiveLargeChange: Integer;
begin
  if FLargeChange > 0 then Result := FLargeChange else Result := FPageSize;
  if Result < 1 then Result := 1;   // a page action that moves nothing is a dead control
end;

procedure TTyScrollBar.DoScroll(ACode: TScrollCode; var APos: Integer);
begin
  if Assigned(FOnScroll) then
    FOnScroll(Self, ACode, APos);
end;

procedure TTyScrollBar.ScrollTo(ACode: TScrollCode; AProposed: Integer);
var
  P: Integer;
begin
  // Clamp the proposed value first, let the OnScroll handler optionally adjust
  // it (honoring its var parameter), then commit through the Position setter
  // (which clamps again and fires OnChange).
  P := AProposed;
  if P < FMin then P := FMin;
  if P > FMax then P := FMax;
  DoScroll(ACode, P);
  Position := P;
end;

function TTyScrollBar.DoMouseWheel(Shift: TShiftState; WheelDelta: Integer;
  MousePos: TPoint): Boolean;
begin
  // Let the published OnMouseWheel/Up/Down events fire first; if a handler marks
  // the wheel handled, honor that and do not step.
  Result := inherited DoMouseWheel(Shift, WheelDelta, MousePos);
  if Result then Exit;
  if not Enabled then Exit;
  // Convention: wheel-up (WheelDelta > 0) scrolls content up -> Position
  // DECREASES by SmallChange; wheel-down increases it. (Standard scrollbar.)
  Position := Position - Sign(WheelDelta) * FSmallChange;
  Result := True;
end;

function TTyScrollBar.EmbeddingHost(out AHost: ITyScrollBarFrameHost): Boolean;
begin
  Result := (Parent <> nil) and Supports(Parent, ITyScrollBarFrameHost, AHost)
            and AHost.EmbedsScrollBar(Self);
  if not Result then AHost := nil;
end;

function TTyScrollBar.IsEmbedded: Boolean;
var
  host: ITyScrollBarFrameHost;
begin
  Result := EmbeddingHost(host);
end;

function TTyScrollBar.PaintsParentFrame: Boolean;
begin
  Result := IsEmbedded;
end;

procedure TTyScrollBar.PaintBody(APainter: TTyPainter; const ARect, ASpan: TRect;
  const AStyle: TTyStyleSet);
var
  ThumbS: TTyStyleSet;
  Track, ThumbR, LoR, HiR: TRect;
  ThumbFill: TTyFill;
  ThumbStates: TTyStateSet;

  { 箭头的字形框:大小仍按整格(箭头不因为贴边就变小),**中心**挪到这一格看得见的部分上。
    横跨条的方向上要正好居中 —— 条的两条长边就是拿这个比的 —— 而一个偶数宽的框放不到奇数宽
    那一截的正中(差半个像素,三角形的抗锯齿两边就不一样),这时框收一个像素。只有宿主带焦点环
    (让 3 列)才会碰上。沿条方向差半个像素没人看得出,不为它再收。 }
  function GlyphBox(const AButton: TRect): TRect;
  var
    vis: TRect;
    s, crossVis: Integer;
  begin
    Result := TySquareGlyphBox(AButton);
    if (not IntersectRect(vis, AButton, ASpan)) or EqualRect(vis, AButton) then Exit;
    s := Result.Right - Result.Left;
    if FKind = sbVertical then
      crossVis := vis.Right - vis.Left
    else
      crossVis := vis.Bottom - vis.Top;
    if Odd(s - crossVis) then Dec(s);
    Result.Left := (vis.Left + vis.Right - s) div 2;
    Result.Top := (vis.Top + vis.Bottom - s) div 2;
    Result.Right := Result.Left + s;
    Result.Bottom := Result.Top + s;
  end;

begin
  Track := TyScrollTrackRect(ARect, FKind, TyScrollButtonSize(ARect, FKind));
  // The PAINTED thumb uses the displayed (possibly mid-animation) position; at
  // rest DisplayPos == FPosition so headless renders are pixel-identical. The
  // track-paging hit math, drag math and BeginThumbDrag keep using FPosition.
  ThumbR := TyScrollThumbRect(Track, FKind, FMin, FMax, Round(DisplayPos), FPageSize, Mirrored);
  { 滑块只画在看得见的那一截里。位置和长短照旧按整条算(见声明处),收的只是它画出来的
    矩形 —— 贴边侧那几列归宿主的框,滑块的圆边要落在框的内沿以内,两侧才一样圆。 }
  if not IntersectRect(ThumbR, ThumbR, ASpan) then
    ThumbR := Rect(0, 0, 0, 0);
  // Thumb fill is its own sub-element typeKey (TyScrollThumb). Feed the control's
  // hover/press state so TyScrollThumb:hover/:active render (matches the pre-typeKey
  // behavior where the thumb borrowed the parent's state-resolved TextColor).
  ThumbStates := [];
  if FPressed then
    Include(ThumbStates, tysActive)
  else if FHover then
    Include(ThumbStates, tysHover);
  { 这里**不乘**淡出系数。滑块和条身画进的是同一层(RenderBodyLayer 那张透明位图),
    淡出是整层合成时一次乘进去的;在这儿再乘一次只会把滑块压得比条身更淡。
    (也根本不读 ThumbS.Opacity——只取 Background.Color 和 BorderRadius。哪天滑块被挪去
    单开一层,就要自己接淡出了:test.scrollbar.autohide 的 FadeReachesThePaintedPixels
    数的是整块像素,到时候会红。) }
  ThumbS := ActiveController.Model.ResolveStyle('TyScrollThumb', '', ThumbStates);
  ThumbFill := Default(TTyFill);
  ThumbFill.Kind := tfkSolid;
  ThumbFill.Color := ThumbS.Background.Color;
  if not IsRectEmpty(ThumbR) then
    APainter.FillBackground(ThumbR, ThumbFill, ThumbS.BorderRadius);
  ButtonRects(ARect, LoR, HiR);
  if (LoR.Right > LoR.Left) then   // buttons exist
  begin
    if FKind = sbVertical then
    begin
      // v3/C5 overridable. Triangles: a scroll-bar end button steps the view, the same role
      // the spin buttons have, and Windows draws both from the same triangular idiom.
      TyDrawGlyph(APainter, ActiveController, GlyphBox(LoR), tgTriangleUp,   AStyle.TextColor, 2, 1);
      TyDrawGlyph(APainter, ActiveController, GlyphBox(HiR), tgTriangleDown, AStyle.TextColor, 2, 1);
    end
    else
    begin
      { The GLYPHS do not swap under MirrorHorizontal, and that is not an omission.
        Reflecting a pair "left arrow at the left end, right arrow at the right end" gives
        back the same picture, which is why Windows' mirrored horizontal bar is visually
        indistinguishable from its unmirrored one. What the mirror moves is the MEANING:
        the left-end button now steps Position UP (see MouseDown), because that is the
        direction the thumb travels when it goes left. Drawing tgArrowRight on the left
        would make the button point away from where it sends the thumb. }
      TyDrawGlyph(APainter, ActiveController, GlyphBox(LoR), tgTriangleLeft,  AStyle.TextColor, 2, 1);
      TyDrawGlyph(APainter, ActiveController, GlyphBox(HiR), tgTriangleRight, AStyle.TextColor, 2, 1);
    end;
  end;
end;

function TTyScrollBar.RenderBodyLayer(const ARect, ASpan: TRect; const AStyle: TTyStyleSet;
  APPI: Integer): TBGRABitmap;
var
  B: TTyPainter;
begin
  { 位图是这里建、调用方释放的,所以走 BeginPaintOn:EndPaint 既不释放它,也没有画布可
    blit(画布是 nil)。条自己的底色/边框/焦点环走的是 DrawFrame 的后两段,**不含**父背景
    —— 这一层的透明处必须透出底下真实的背景,那正是分层的意义。
    底色铺满整条:贴边侧宿主框占掉的那几列里,框线沾到的像素反正要被换回宿主的,沾不到的
    (某些 DPI 下让开的那一圈比墨宽)就该是滑道,而不是一道宿主底色的细缝。 }
  Result := TBGRABitmap.Create(ARect.Right - ARect.Left, ARect.Bottom - ARect.Top,
    BGRAPixelTransparent);
  B := TTyPainter.Create;
  try
    B.BeginPaintOn(nil, ARect, APPI, Result);
    TyDrawFrameUnderlay(B, ARect, AStyle);
    TyDrawFrameChrome(Self, B, ASpan, AStyle);
    PaintBody(B, ARect, ASpan, AStyle);
    B.EndPaint;
  finally
    B.Free;
  end;
end;

procedure TTyScrollBar.RenderOverHostFrame(APainter: TTyPainter; const ARect: TRect;
  const AHost: ITyScrollBarFrameHost; const AStyle: TTyStyleSet; AAlpha: Single);
var
  host: TControl;
  hs, clipStyle, bodyStyle: TTyStyleSet;
  hostR, span: TRect;
  origin: TPoint;
  frame, ink, clip, body: TBGRABitmap;
  L: TTyPainter;
  w, h, x, y, band, radius: Integer;
  pd, pf, pk, pb, pc: PBGRAPixel;
begin
  host := Parent;
  hs := AHost.ScrollBarFrameStyle;
  { 宿主的矩形,在**本条**的坐标系里。条的 Left/Top 相对宿主客户区原点,宿主的框画在
    Rect(0,0,宽,高) 上,所以就是平移一下;绝大部分落在本条的位图外面,画的时候被裁掉。
    RTL 下竖条停在左边,Left = 0,于是这里画出来的自然是宿主的**左**边和左边两个角。 }
  origin := Point(-Left, -Top);
  hostR := Rect(origin.X, origin.Y, origin.X + host.Width, origin.Y + host.Height);
  w := ARect.Right - ARect.Left;
  h := ARect.Bottom - ARect.Top;

  { 条身看得见的那一截。条的哪条边贴着宿主外沿,那条边就让开宿主框**此刻**占掉的那一圈
    (TyChromeInsetLogical:边框或焦点环取宽的那个,再加一列抗锯齿;宿主获得焦点时大一档,
    与列表框的行让开的是同一条带)。
    为什么要让:下面「上层」那一步把框线沾到的像素整列换回宿主的,条身若按整条排,凡是左右
    对称画的东西 —— 滑块的圆边、条自己的焦点环、箭头的居中 —— 在内容侧完整、在贴边侧被削掉
    一截,两条长边就长得不一样(真机报的「滚动条左右的渲染好奇怪」)。按看得见的那一截排,
    两侧才是镜像。
    只让贴边的那几条边:内容侧没有框;竖条下沿挨着横条时也没有。 }
  band := APainter.Scale(TyChromeInsetLogical(hs));
  span := ARect;
  if hostR.Left >= ARect.Left then Inc(span.Left, band);
  if hostR.Top >= ARect.Top then Inc(span.Top, band);
  if hostR.Right <= ARect.Right then Dec(span.Right, band);
  if hostR.Bottom <= ARect.Bottom then Dec(span.Bottom, band);
  if span.Right < span.Left then span.Right := span.Left;
  if span.Bottom < span.Top then span.Bottom := span.Top;

  { 条身的形状归宿主,不归条自己的 border-radius。独立摆放的条是一颗药丸,四个角按主题圆;
    贴边的条是宿主边上的一条带:贴边侧的两个角由宿主底色的形状裁(下面的 clip),内容侧照
    主题圆的话,两端各露出一块宿主底色的缺口,条的端头又「飘」起来 —— 正是贴边要去掉的样子。
    所以滑道、条自己的边框和焦点环的圆角换成 --radius-scroll-embedded,基础层给 0 = 方角
    (理由和「为什么是令牌」见 TyScrollBarEmbeddedRadiusVar)。滑块是自己的 typeKey
    (TyScrollThumb),照旧圆。
    ActiveController,不是裸 Controller:没挂 controller 的条回落到进程级默认主题。 }
  radius := ActiveController.Metric(TyScrollBarEmbeddedRadiusVar, TyScrollBarEmbeddedRadiusDef);
  if radius < 0 then radius := 0;
  bodyStyle := AStyle;
  bodyStyle.BorderRadius := radius;
  bodyStyle.Radius := TyUniformCorners(radius);

  { 宿主整个被 :disabled 的 opacity 压暗时,本条跟它一起暗 —— 用宿主自己的样式、宿主自己
    的 OpacityBase,与宿主画它那几百个像素时一模一样。 }
  TyApplyStyleOpacity(host, APainter, hs);

  { ---- 底层:宿主在这几个像素上的样子,去掉框线 ----
    宿主背后的背景(圆角外面那几块)+ 宿主的阴影与底色。宿主画自己的时候也是这两步,
    只是它画在 Rect(0,0,宽,高) 上,这里画在 hostR 上。 }
  TyFillParentBgAt(host, APainter, Rect(0, 0, host.Width, host.Height), origin, hs);
  TyDrawFrameUnderlay(APainter, hostR, hs);

  if AAlpha <= 0.0 then
  begin
    { 彻底淡没:没有条身,底层上直接盖框线就是宿主本来的样子。 }
    TyDrawFrameChrome(host, APainter, hostR, hs);
    Exit;
  end;

  frame := nil; ink := nil; clip := nil; body := nil;
  L := TTyPainter.Create;
  try
    { frame = 底层 + 框线:宿主自己在这几个像素上画出来的东西,逐字节。 }
    frame := APainter.Bitmap.Duplicate as TBGRABitmap;
    L.BeginPaintOn(nil, ARect, APainter.PPI, frame);
    TyDrawFrameChrome(host, L, hostR, hs);
    L.EndPaint;
    { ink = 框线单独画在透明底上:alpha > 0 的像素就是框线(边框、焦点环、有阴影时角外的
      缺口)沾到的像素。 }
    ink := TBGRABitmap.Create(w, h, BGRAPixelTransparent);
    L.BeginPaintOn(nil, ARect, APainter.PPI, ink);
    TyDrawFrameChrome(host, L, hostR, hs);
    L.EndPaint;
    { clip = 宿主底色的形状。用 underlay 本身来画(换成不透明的纯色、去掉阴影),圆角怎么
      算、render-style 怎么展开都与宿主画底色的那一句同源,不另抄一份几何。 }
    clipStyle := hs;
    clipStyle.Background := Default(TTyFill);
    clipStyle.Background.Kind := tfkSolid;
    clipStyle.Background.Color := TyRGB(255, 255, 255);
    Include(clipStyle.Present, tpBackground);
    Exclude(clipStyle.Present, tpShadow);
    clip := TBGRABitmap.Create(w, h, BGRAPixelTransparent);
    L.BeginPaintOn(nil, ARect, APainter.PPI, clip);
    TyDrawFrameUnderlay(L, hostR, clipStyle);
    L.EndPaint;

    { ---- 中层:条身,按可见度合成 ----
      合成到**真实的**底层上,不是合成到某一个取样色上 —— 渐变底色在淡出途中照样是渐变。
      条身先裁进宿主底色的形状:圆角那一段条身被弧切掉,不会伸到弧外的父背景上。
      **只留底色完全盖住的像素**,底色形状抗锯齿边上那一圈半盖的像素一律不要条身:那一圈
      是宿主轮廓的一部分,宿主在那儿画的是「父背景和底色各占几成」。实测圆角上它会落在边框
      外沿**外面**(底色的弧比边框描边的弧往外多出零点几个像素),框线没沾到,按比例留条身
      的话条身就把宿主的轮廓染了一层灰。 }
    body := RenderBodyLayer(ARect, span, bodyStyle, APainter.PPI);
    for y := 0 to h - 1 do
    begin
      pb := body.ScanLine[y];
      pc := clip.ScanLine[y];
      for x := 0 to w - 1 do
      begin
        if pc^.alpha < 255 then pb^.alpha := 0;
        Inc(pb);
        Inc(pc);
      end;
    end;
    body.InvalidateBitmap;
    APainter.Bitmap.PutImage(0, 0, body, dmLinearBlend, Round(AAlpha * 255));

    { ---- 上层:宿主的边框与焦点环,永远不透明 ----
      不是在合成结果上**再描一遍**框线:框线的抗锯齿边会与底下的颜色混,底下是条身时混出来
      的就不是宿主画的那个颜色。所以凡是框线沾到的像素,整个换成 frame 里的那个像素 ——
      宿主自己在那儿画的是什么,这里就是什么,在任何可见度下都逐字节一致。代价是条身在
      框线的抗锯齿内沿上让出那一两个像素,等于条身被框线的内沿裁掉。 }
    for y := 0 to h - 1 do
    begin
      pd := APainter.Bitmap.ScanLine[y];
      pf := frame.ScanLine[y];
      pk := ink.ScanLine[y];
      for x := 0 to w - 1 do
      begin
        if pk^.alpha > 0 then pd^ := pf^;
        Inc(pd);
        Inc(pf);
        Inc(pk);
      end;
    end;
    APainter.Bitmap.InvalidateBitmap;
  finally
    L.Free;
    body.Free;
    clip.Free;
    ink.Free;
    frame.Free;
  end;
end;

procedure TTyScrollBar.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
var
  P: TTyPainter;
  S: TTyStyleSet;
  R: TRect;
  host: ITyScrollBarFrameHost;
  alpha: Single;
  body: TBGRABitmap;
begin
  P := TTyPainter.Create;
  try
    R := Rect(0, 0, ARect.Right - ARect.Left, ARect.Bottom - ARect.Top);
    P.BeginPaint(ACanvas, ARect, APPI);
    { PaintStyle，不是 CurrentStyle：自动隐藏的淡出**只有这一个入口**进绘制。
      它的 Opacity(主题 opacity × 可见度)就是下面条身那一层的合成不透明度。 }
    S := PaintStyle;
    if tpOpacity in S.Present then alpha := S.Opacity else alpha := 1.0;
    if alpha < 0.0 then alpha := 0.0;
    if alpha > 1.0 then alpha := 1.0;

    if EmbeddingHost(host) then
      { 贴边的内嵌条:三层 —— 宿主的背景、条身、宿主的框。每个可见度都走这一条,完全可见
        也一样:框线在条上面,焦点环不会再被一条看得见的条截断。 }
      RenderOverHostFrame(P, R, host, S, alpha)
    else if alpha <= 0.0 then
      { 独立摆放、彻底隐身:不画自己,只把父控件的背景按**本控件这块矩形**原样铺一遍 ——
        渐变切片、图片切片都是真的,不是一块居中取样的平板。 }
      TyFillParentBg(Self, P, R, S)
    else if SameValue(FFadeLevel, 1.0, 0.001) then
    begin
      { 独立摆放、完全可见:原来那条路,一个像素不变(主题自己的 :disabled opacity 也还是
        照旧交给 DrawFrame)。 }
      DrawFrame(P, R, S);
      PaintBody(P, R, R, S);
    end
    else
    begin
      { 独立摆放、淡出途中:父背景的真切片 + 条身按可见度合成上去。 }
      TyFillParentBg(Self, P, R, S);
      body := RenderBodyLayer(R, R, S, APPI);
      try
        P.Bitmap.PutImage(0, 0, body, dmLinearBlend, Round(alpha * 255));
      finally
        body.Free;
      end;
    end;
    P.EndPaint;
  finally
    P.Free;
  end;
end;

procedure TTyScrollBar.Paint;
begin
  RenderTo(Canvas, ClientRect, Font.PixelsPerInch);
end;

function TTyScrollBar.TrackRect: TRect;
begin
  // Inset client by a button-size at each end so the thumb/drag/paging
  // operate on the track between the (Task 5) end arrow buttons.
  Result := TyScrollTrackRect(ClientRect, FKind, TyScrollButtonSize(ClientRect, FKind));
end;

procedure TTyScrollBar.ButtonRects(const AClient: TRect; out ALo, AHi: TRect);
var
  bs, mainLen: Integer;
begin
  bs := TyScrollButtonSize(AClient, FKind);
  if FKind = sbVertical then
    mainLen := AClient.Bottom - AClient.Top
  else
    mainLen := AClient.Right - AClient.Left;
  if mainLen <= 2 * bs then
  begin
    ALo := Rect(0, 0, 0, 0);
    AHi := Rect(0, 0, 0, 0);
    Exit;   // no buttons
  end;
  if FKind = sbVertical then
  begin
    ALo := Rect(AClient.Left, AClient.Top, AClient.Right, AClient.Top + bs);
    AHi := Rect(AClient.Left, AClient.Bottom - bs, AClient.Right, AClient.Bottom);
  end
  else
  begin
    ALo := Rect(AClient.Left, AClient.Top, AClient.Left + bs, AClient.Bottom);
    AHi := Rect(AClient.Right - bs, AClient.Top, AClient.Right, AClient.Bottom);
  end;
end;

function TTyScrollBar.TrackLength: Integer;
var
  Track: TRect;
begin
  // Derive from the inset track so drag and paint share the same rect basis
  // (TyScrollThumbRect is now computed against the inset track).
  Track := TrackRect;
  if FKind = sbVertical then
    Result := Track.Bottom - Track.Top
  else
    Result := Track.Right - Track.Left;
end;

procedure TTyScrollBar.BeginThumbDrag(AGrabPosAlongTrack: Integer);
var
  ThumbR: TRect;
  ThumbStart: Integer;
begin
  ThumbR := TyScrollThumbRect(TrackRect, FKind, FMin, FMax, FPosition, FPageSize, Mirrored);
  if FKind = sbVertical then
    ThumbStart := ThumbR.Top
  else
    ThumbStart := ThumbR.Left;
  FDragging := True;
  FDragStartTop := ThumbStart;
  FDragGrabOffset := AGrabPosAlongTrack - ThumbStart;
  // The pending value starts where the committed one is; with LiveTracking off this is
  // what the thumb is painted from until mouse-up.
  FTrackPos := FPosition;
  // Sync the displayed thumb to the logical position on grab so DisplayPos ==
  // FPosition at drag start (subsequent drag SetPosition calls snap).
  FAnimFrom := FPosition;
  FAnimTo := FPosition;
  FPosAnim.SetTargetImmediate(1);
end;

procedure TTyScrollBar.DragThumbTo(APosAlongTrack: Integer);
var
  Track, ThumbR: TRect;
  ThumbLen, FreeSpace, NewTop, Travel, NewPos, TrackStart, Off: Integer;
begin
  if not FDragging then Exit;
  Track := TrackRect;
  ThumbR := TyScrollThumbRect(Track, FKind, FMin, FMax, FPosition, FPageSize, Mirrored);
  if FKind = sbVertical then
    ThumbLen := ThumbR.Bottom - ThumbR.Top
  else
    ThumbLen := ThumbR.Right - ThumbR.Left;
  FreeSpace := TrackLength - ThumbLen;
  if FreeSpace < 1 then FreeSpace := 1;
  // The thumb lives in [TrackStart, TrackStart+FreeSpace] in CLIENT coords,
  // because the track is inset by a button-size at each end.
  if FKind = sbVertical then
    TrackStart := Track.Top
  else
    TrackStart := Track.Left;
  NewTop := APosAlongTrack - FDragGrabOffset;
  if NewTop < TrackStart then NewTop := TrackStart;
  if NewTop > TrackStart + FreeSpace then NewTop := TrackStart + FreeSpace;
  Travel := FMax - FMin;
  { The inverse of TyScrollThumbRect, through the same one-line mirror it uses. NewTop is a
    real CLIENT coordinate either way (the thumb follows the cursor whichever end the origin
    is at); what the mirror decides is only how that distance-from-the-left is read back as a
    distance-from-the-ORIGIN. }
  Off := TyScrollMirrorOffset(NewTop - TrackStart, FreeSpace, FKind, Mirrored);
  NewPos := FMin + Integer((Int64(Off) * Travel) div FreeSpace);
  // Live drag tracking fires scTrack with the proposed value (handler may
  // adjust it); commit through the Position setter (clamps + OnChange).
  if NewPos < FMin then NewPos := FMin;
  if NewPos > FMax then NewPos := FMax;
  DoScroll(scTrack, NewPos);
  if FLiveTracking then
    Position := NewPos
  else
  begin
    { Deferred commit. The thumb still has to MOVE -- a drag whose thumb sat still would read
      as a dead control -- so record the pending value and repaint from it (RenderTo paints
      DisplayPos, which returns FTrackPos for the duration of this drag). Position, OnChange
      and scPosition all wait for EndThumbDrag.

      Repaint synchronously, for the same reason the live path does: the bar is its own window
      and WM_PAINT is the lowest-priority message, so on a busy host a queued repaint lands a
      frame or two after the mouse and the thumb visibly lags the cursor. }
    if FTrackPos <> NewPos then
    begin
      FTrackPos := NewPos;
      Invalidate;
      if HandleAllocated then Update;
    end;
  end;
end;

procedure TTyScrollBar.EndThumbDrag;
var
  P: Integer;
  wasDragging: Boolean;
begin
  wasDragging := FDragging;
  if FDragging then
  begin
    { Final committed value of the drag: scPosition then scEndScroll.

      With LiveTracking off this is the ONLY place the drag reaches Position, so the proposed
      value is the pending one, not the (still untouched) current one. Position is written
      unconditionally in that case -- the `if P <> FPosition` short-circuit below is about a
      handler having ADJUSTED an already-committed value, and here there is nothing committed
      yet. FDragging is still True, so the setter snaps rather than gliding, and the content
      lands exactly where the thumb was let go. }
    if FLiveTracking then
      P := FPosition
    else
      P := FTrackPos;
    DoScroll(scPosition, P);
    if (P <> FPosition) or not FLiveTracking then
      Position := P;
    P := FPosition;
    DoScroll(scEndScroll, P);
    if P <> FPosition then
      Position := P;
  end;
  FDragging := False;
  FTrackPos := FPosition;
  { 松手也要把延时表起回来:按住的那段表是停的(AutoHideTimerNeeded)。

    **只在真有一次拖动结束的时候**。MouseUp 是无条件调 EndThumbDrag 的,箭头
    点击、滑道翻页的那次抬起也会走到这里,而那些路本来就没人按住表;它们该有的
    「在用」由 ScrollTo -> Position -> NoteActivity 给。

    放在这里而不是 MouseUp,是因为 EndThumbDrag 是公开的:宿主自己驱动拖动的话
    松手就只经过这里。source/ 里现在还没有哪个宿主这么用,是留给以后的。

    上面那几句 Position := 有时候也会顺带 NoteActivity,但那是在 FDragging 还
    是 True 的时候,而且只在值真变了的时候才走 —— 原地放手的拖动一次都不走。 }
  if wasDragging then NoteActivity;
end;

function TTyScrollBar.PosAlong(X, Y: Integer): Integer;
begin
  { Stays a raw CLIENT coordinate under mirroring. The scoping document proposed turning this
    into TrackRect.Right - X, "one line"; it is the wrong line. Everything downstream of this
    -- BeginThumbDrag's ThumbR.Left, DragThumbTo's clamp against Track.Left, the thumb rect
    the click is tested against -- is in client coordinates, so flipping here would leave the
    grab offset measured from one end and the thumb from the other. The flip belongs where
    the offset becomes a POSITION, which is TyScrollMirrorOffset, and it is applied there. }
  if FKind = sbVertical then
    Result := Y
  else
    Result := X;
end;

procedure TTyScrollBar.FocusAfterClick;
{ 独立摆放的条:点它就拿焦点,与从前一样 —— 它有完整的键盘操作,焦点也是自动隐藏「按住
  不放」的信号。**不看 TabStop**:TabStop=False 的独立条只是不进 Tab 顺序,点它照样该拿到。

  内嵌条:**永远不拿焦点**,焦点交给宿主。六个宿主建条时都写了 TabStop := False 并注释了理由
  (拖条不能把焦点从列表抢走,否则列表丢了焦点环、滚到一半键盘导航也没了),设计文档
  (2026-09-14-scrollbar-auto-hide-design.md §4)也写着内嵌条拿不到焦点 —— 而这里从前是一句
  无条件的 if CanFocus then SetFocus,一点就把这些全推翻了:焦点落到一根 12px 的条上,条画起
  自己的焦点环,方向键滚的是条而不是列表。

  交给宿主的规则与宿主被直接点中时一样(TTyCustomControl.MouseDown:TabStop 且 CanFocus),
  所以不参与焦点的宿主(滚动框默认 TabStop=False)点它的条焦点原地不动。多一条:焦点**已经在
  宿主里面**(宿主自己,或它的行内编辑器,比如网格正在编辑的那一格)就不动。网格的编辑器一
  失焦就提交并收起,滚一下就把编辑结束掉不是滚动条该做的事。条自己若被代码 SetFocus 过,不算
  「在里面」,照样挪给宿主。

  try/except 与从前相同:无头运行的窗体从没 Show 过,SetFocus 会一路抛到父窗体上。 }
var
  host: TWinControl;
  focusedCtl: TWinControl;
begin
  try
    if not IsEmbedded then
    begin
      if CanFocus then SetFocus;
      Exit;
    end;
    host := Parent;
    { 先问便宜的那两个:无头下 CanFocus 就是 False,GetFocus 根本不用去问 widgetset。 }
    if not (host.TabStop and host.CanFocus) then Exit;
    focusedCtl := FindOwnerControl(GetFocus);
    if (focusedCtl <> nil) and (focusedCtl <> Self) and host.ContainsControl(focusedCtl) then Exit;
    host.SetFocus;
  except
  end;
end;

procedure TTyScrollBar.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
var
  ThumbR, LoR, HiR: TRect;
  Back, Fwd: TScrollCode;
  BackSign: Integer;
begin
  if not Enabled then Exit;
  inherited MouseDown(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    { WHICH WAY THE LOW END OF THE BAR STEPS. On a mirrored horizontal bar the origin is the
      right end, so the LEFT-hand button and the track left of the thumb are the direction
      Position INCREASES -- the same swap the thumb's own arithmetic makes. Resolving it once
      into a pair of (code, step) values keeps the six call sites below from each having to
      remember it. BackSign is the sign the LEFT/TOP side moves Position in; the right/bottom
      side is its negation. }
    if Mirrored then
    begin
      Back := scLineDown;  Fwd := scLineUp;    BackSign := +1;
    end
    else
    begin
      Back := scLineUp;    Fwd := scLineDown;  BackSign := -1;
    end;
    ButtonRects(ClientRect, LoR, HiR);
    if PtInRect(LoR, Point(X, Y)) then
    begin
      ScrollTo(Back, Position + BackSign * FSmallChange);
      FocusAfterClick;
      Exit;
    end;
    if PtInRect(HiR, Point(X, Y)) then
    begin
      ScrollTo(Fwd, Position - BackSign * FSmallChange);
      FocusAfterClick;
      Exit;
    end;
    { THE HIT TEST AND THE PAINT ARE THE SAME CALL. RenderTo builds its thumb from
      TyScrollThumbRect and so does this, with the same Mirrored argument -- there is no
      second copy of the geometry that could be mirrored on one side only. (The painted rect
      uses DisplayPos so the thumb can glide; at rest, and always while dragging, that equals
      FPosition.) }
    ThumbR := TyScrollThumbRect(TrackRect, FKind, FMin, FMax, FPosition, FPageSize, Mirrored);
    if PtInRect(ThumbR, Point(X, Y)) then
    begin
      BeginThumbDrag(PosAlong(X, Y));
      { A control with no window cannot hold a capture, and LCL does not say so gently:
        SetCaptureControl forces the handle into existence and the widgetset RAISES when the
        window class is not registered -- which in a headless runner is any process that has
        not already built a form. The drag itself is pure arithmetic and works without one,
        so the only thing that raise ever did was put the hit test out of reach of a guard. }
      if HandleAllocated then MouseCapture := True;
    end
    else
    begin
      // click on the track: page one PageSize toward the click
      if (FKind = sbVertical) and (Y < ThumbR.Top) then
        ScrollTo(scPageUp, Position - EffectiveLargeChange)
      else if (FKind = sbVertical) and (Y >= ThumbR.Bottom) then
        ScrollTo(scPageDown, Position + EffectiveLargeChange)
      else if (FKind = sbHorizontal) and (X < ThumbR.Left) then
        ScrollTo(Back, Position + BackSign * EffectiveLargeChange)
      else if (FKind = sbHorizontal) and (X >= ThumbR.Right) then
        ScrollTo(Fwd, Position - BackSign * EffectiveLargeChange);
    end;
    FocusAfterClick;
  end;
end;

procedure TTyScrollBar.MouseMove(Shift: TShiftState; X, Y: Integer);
begin
  if not Enabled then Exit;
  inherited MouseMove(Shift, X, Y);
  if FDragging then
    DragThumbTo(PosAlong(X, Y));
end;

procedure TTyScrollBar.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited MouseUp(Button, Shift, X, Y);
  if Button = mbLeft then
  begin
    EndThumbDrag;
    MouseCapture := False;
  end;
end;

procedure TTyScrollBar.KeyDown(var Key: Word; Shift: TShiftState);
var
  Dec1, Inc1: Word;
begin
  if not Enabled then Exit;
  inherited KeyDown(Key, Shift);
  if FKind = sbVertical then
  begin
    Dec1 := VK_UP;
    Inc1 := VK_DOWN;
  end
  else if Mirrored then
  begin
    { The arrow keys on a scroll bar are a LAYOUT direction, not a text direction, so they
      follow the mirror (plans/2026-08-04-rtl-mirroring-scope.md §6.3 item 4 draws exactly
      this line: keys that move through a laid-out thing flip, keys that move through a
      STRING do not). Left steps the thumb left, which on a mirrored bar is up-Position.
      Home/End below stay logical -- they mean first/last, not leftmost/rightmost. }
    Dec1 := VK_RIGHT;
    Inc1 := VK_LEFT;
  end
  else
  begin
    Dec1 := VK_LEFT;
    Inc1 := VK_RIGHT;
  end;
  if Key = Dec1 then
  begin
    ScrollTo(scLineUp, Position - FSmallChange);
    Key := 0;
  end
  else if Key = Inc1 then
  begin
    ScrollTo(scLineDown, Position + FSmallChange);
    Key := 0;
  end
  else
    case Key of
      VK_PRIOR: begin ScrollTo(scPageUp, Position - EffectiveLargeChange); Key := 0; end;
      VK_NEXT:  begin ScrollTo(scPageDown, Position + EffectiveLargeChange); Key := 0; end;
      VK_HOME:  begin ScrollTo(scTop, FMin); Key := 0; end;
      VK_END:   begin ScrollTo(scBottom, FMax); Key := 0; end;
    end;
end;

end.
