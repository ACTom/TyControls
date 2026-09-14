unit test.scrollbar.autohide;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, TypInfo, fpcunit, testregistry, Forms,
  tyControls.Controller, tyControls.ScrollBar;

type
  TTyScrollBarAutoHideTests = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FBar: TTyScrollBar;
    procedure UseThemeCss(const ACss: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure ThemeOffByDefault;
    procedure ThemeDelayIsRead;
    procedure NegativeOneParsesAsOff;
    procedure NeverBeatsAnAutoHidingTheme;
    procedure AutoBeatsAnOffTheme;
    procedure AutoStillReadsTheThemeDelay;
    procedure ImmediateIsAValidDelay;
    procedure AutoHonoursAnImmediateTheme;
    procedure DeclaredDefaultMatchesConstructed;
    procedure OffThemeAlwaysFullyVisible;
    procedure IdleFadesOutAfterTheDelay;
    procedure ActivityBringsItBack;
    procedure PositionChangeCountsAsActivity;
    procedure PointerOnBarHoldsItOpen;
    procedure DraggingHoldsItOpen;
    procedure FadingIgnoresAnimationsEnabled;
    procedure FadeInIsNotCutShortByTheIdleClock;
    procedure TurningAutoHideOffUnhidesAFadedBar;
    procedure SnappedMirrorCountsAsActivity;
    procedure ActivityCancelsAnArmedFadeOut;
    procedure TurningItOffDisarmsAPendingFade;
    procedure ThemeTurningItOffUnhidesAFadedBar;
    procedure FocusBringsItBack;
    procedure ThemeDelayTracksAThemeSwitch;
    procedure ThemeDelayTracksAControllerSwitch;
    procedure PropertyChangeIsNotServedAStaleDelay;
    procedure WaitingOutTheDelayNeedsTheClock;
    procedure PointerOnBarStopsTheClockSpinning;
    procedure ARunningFadeOutranksBeingHeldOpen;
    procedure PointerLeavingRestartsTheIdleClock;
    procedure FocusLeavingRestartsTheIdleClock;
    procedure ReleasingTheThumbRestartsTheIdleClock;
    procedure OneLateTickCatchesTheFadeUp;
    procedure BackToBackTicksStepTheFadeInsteadOfSnappingIt;
    procedure AStoppedClockDoesNotBankTheTimeItWasStoppedFor;
  end;

implementation

type
  { FDragging 在 protected 里。跟 tests/test.controls.scrollbar.pas 的 TScrollAccess
    一个路子：用一个后代把它开成 public，别另发明别的口子。 }
  TBarAccess = class(TTyScrollBar)
  public
    procedure SetDraggingState(AValue: Boolean);
    { MouseEnter/MouseLeave 在 TControl 里也是 protected,外部单元同样够不着
      (编译器报的是「identifier idents no member」,看着像根本没这个方法)。
      走同一个口子,而不是为了测试把控件的可见性往上抬。 }
    procedure EnterBar;
    procedure LeaveBar;
    { DoEnter/DoExit 同样是 protected。 }
    procedure FocusIn;
    procedure FocusOut;
    { 「延时表还有没有活干」这个判断在 protected 里。**能验的只有这个判断**:
      无头没有句柄就不建表(EnsureHideTimer 直接 Exit),FHideTimer 恒为 nil,
      「停表」这个动作本身在无头下不存在。 }
    function TimerNeeded: Boolean;
    { 手动走一拍真正的 timer 回调。 }
    procedure HideTimerTick;
  end;

procedure TBarAccess.SetDraggingState(AValue: Boolean);
begin
  FDragging := AValue;
end;

procedure TBarAccess.EnterBar;
begin
  MouseEnter;
end;

procedure TBarAccess.LeaveBar;
begin
  MouseLeave;
end;

procedure TBarAccess.FocusIn;
begin
  DoEnter;
end;

procedure TBarAccess.FocusOut;
begin
  DoExit;
end;

function TBarAccess.TimerNeeded: Boolean;
begin
  Result := AutoHideTimerNeeded;
end;

procedure TBarAccess.HideTimerTick;
begin
  HandleHideTimerTick;
end;

procedure TTyScrollBarAutoHideTests.SetUp;
begin
  { 控件必须有父控件，并且自带 controller——否则它读的是进程级主题，
    单跑绿、全量红。 }
  FForm := TForm.CreateNew(nil);
  FCtl := TTyStyleController.Create(FForm);
  FBar := TTyScrollBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.Controller := FCtl;
end;

procedure TTyScrollBarAutoHideTests.TearDown;
begin
  FreeAndNil(FForm);   // 拥有 controller 与 bar
end;

procedure TTyScrollBarAutoHideTests.UseThemeCss(const ACss: string);
begin
  FCtl.LoadThemeCss(ACss);
end;

procedure TTyScrollBarAutoHideTests.ThemeOffByDefault;
begin
  { 装一个主题，但它不提这个令牌——这才是出厂状态(内置主题都没写它),
    比「一个空模型」更接近真实。Metric 回退到 TyScrollBarAutoHideDef = 关。 }
  UseThemeCss(':root { --surface: #fff; }');
  AssertEquals(TyScrollBarAutoHideOff, FBar.EffectiveAutoHideMs);
end;

procedure TTyScrollBarAutoHideTests.ThemeDelayIsRead;
begin
  { 故意不用 1200——那正好是 TyScrollBarAutoHideFallbackMs。拿一个和回退常量
    同值的数去验「读到了主题」，一旦这条路被错接到回退上，两边答案一样，
    这条断言就看不出来。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  AssertEquals(1000, FBar.EffectiveAutoHideMs);
end;

procedure TTyScrollBarAutoHideTests.NegativeOneParsesAsOff;
begin
  UseThemeCss(':root { --scrollbar-auto-hide: -1; }');
  { 探针的回退**故意不是 -1**。ResolveMetric 解析失败时原样退回 ADefault
    (tyControls.StyleModel.pas)，所以拿 -1 当回退去问「是不是 -1」，
    解析成功和解析被吞给的是同一个答案，这条断言永远绿——它看着像在守，
    其实一点信号都没有。换成 999：解析对了是 -1，解析被吞了是 999。

    守的是 TyEvalLength 那句「头两个字符都是 '-' 才算变量引用」
    (tyControls.Css.Values.pas)。谁把它收紧成「以 '-' 开头」，'-1' 就被
    当成对变量 '1' 的引用，查不到、抛异常、退回 999，这里红。 }
  AssertEquals(-1, FCtl.Metric(TyScrollBarAutoHideVar, 999));
  { 而且这个 -1 确实一路走到了控件。 }
  AssertEquals(-1, FBar.EffectiveAutoHideMs);
end;

procedure TTyScrollBarAutoHideTests.NeverBeatsAnAutoHidingTheme;
begin
  UseThemeCss(':root { --scrollbar-auto-hide: 1200; }');
  FBar.AutoHide := sbahNever;
  AssertEquals(-1, FBar.EffectiveAutoHideMs);
end;

procedure TTyScrollBarAutoHideTests.AutoBeatsAnOffTheme;
begin
  { 主题说关，属性说要自动隐藏 -> 用回退延时，而不是「关」 }
  UseThemeCss(':root { --scrollbar-auto-hide: -1; }');
  FBar.AutoHide := sbahAuto;
  AssertEquals(TyScrollBarAutoHideFallbackMs, FBar.EffectiveAutoHideMs);
end;

procedure TTyScrollBarAutoHideTests.AutoStillReadsTheThemeDelay;
begin
  { sbahAuto 压过主题的是「要不要隐藏」，不是「多久」——主题给了延时就用主题的。
    这正是属性注释承诺的后半句「延时仍读主题」，而 AutoBeatsAnOffTheme 走的是
    主题说关时的回退臂，碰不到这一条。800 既不是回退的 1200，也不是别处在用的值。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 800; }');
  FBar.AutoHide := sbahAuto;
  AssertEquals(800, FBar.EffectiveAutoHideMs);
end;

procedure TTyScrollBarAutoHideTests.ImmediateIsAValidDelay;
begin
  { 0 是三个令牌值里唯一没被钉住的那个，而它恰恰最容易被当成「假」顺手抹掉。
    0 = 停手立刻淡出，是延时不是开关。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 0; }');
  AssertEquals(0, FBar.EffectiveAutoHideMs);
end;

procedure TTyScrollBarAutoHideTests.AutoHonoursAnImmediateTheme;
begin
  { sbahAuto 那条臂用「主题是不是负数」来决定要不要回退。写成 <= 0 一样能
    让别的测试全绿，但这里会把 0 当成关、返回 1200 —— 立即淡出就没了。
    后面的任务拿 delay = 0 当强制值去验「拖动时不隐藏」「设计期不隐藏」，
    所以 0 的含义得先立住，那些测试才可信。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 0; }');
  FBar.AutoHide := sbahAuto;
  AssertEquals(0, FBar.EffectiveAutoHideMs);
end;

procedure TTyScrollBarAutoHideTests.DeclaredDefaultMatchesConstructed;
var
  pi: PPropInfo;
begin
  { 声明的 default 与构造值不一致 -> .lfm 里写的值被当默认省略 -> 加载后丢失。
    全库没有能扫出这种不一致的统一守卫，逐属性写就是全部机制。 }
  pi := GetPropInfo(FBar, 'AutoHide');
  AssertTrue('AutoHide 必须是 published', pi <> nil);
  AssertEquals('声明的 default 必须等于构造函数赋的值', Ord(FBar.AutoHide), pi^.Default);
end;

procedure TTyScrollBarAutoHideTests.OffThemeAlwaysFullyVisible;
begin
  AssertEquals('主题关着时必须恒为完全可见', 1.0, FBar.FadeLevel, 0.001);
  FBar.NoteActivity;
  FBar.AutoHideTick(99999);
  { 还得再推一整段淡出。StartFade 只装膛不开火,所以把 AutoHideTick 里
    「关着就早退」那条臂整个删掉,上面那一拍读到的照样是 1.0 —— 99999 >= -1
    当场把淡出装上了膛,可见度却要到下一拍才掉。 }
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals('关着的时候多久都不该淡出', 1.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.IdleFadesOutAfterTheDelay;
begin
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.NoteActivity;
  AssertEquals('刚用过 -> 完全可见', 1.0, FBar.FadeLevel, 0.001);
  FBar.AutoHideTick(999);
  { 断言要落在**下一拍之后**。999 这一拍就算把淡出装上了膛,可见度也还是 1.0;
    真正能把两者分开的是再推一点点:门槛要是被改松(比如 delay div 2),那发
    子弹已经上膛,1 毫秒就够让可见度跌出容差(缓动头一下就掉 0.015)。 }
  FBar.AutoHideTick(1);            // 累计 1000，到点
  AssertEquals('延时没到 -> 还在', 1.0, FBar.FadeLevel, 0.001);
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals('淡出跑完 -> 不见了', 0.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.ActivityBringsItBack;
begin
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.NoteActivity;
  FBar.AutoHideTick(1000);
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals(0.0, FBar.FadeLevel, 0.001);
  FBar.NoteActivity;
  FBar.AutoHideTick(TyScrollBarFadeInMs);
  AssertEquals('用一下就该回来', 1.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.PositionChangeCountsAsActivity;
begin
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.AutoHideTick(1000);
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals(0.0, FBar.FadeLevel, 0.001);
  FBar.Position := 42;             // 程序化赋值也算「在用」
  FBar.AutoHideTick(TyScrollBarFadeInMs);
  AssertEquals(1.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.PointerOnBarHoldsItOpen;
begin
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  TBarAccess(FBar).EnterBar;
  FBar.AutoHideTick(99999);        // 鼠标在条上，多久都不该淡
  FBar.AutoHideTick(TyScrollBarFadeOutMs);   { 同 DraggingHoldsItOpen:得真跑一段才看得见 }
  AssertEquals(1.0, FBar.FadeLevel, 0.001);
  TBarAccess(FBar).LeaveBar;
  FBar.AutoHideTick(1000);
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals('鼠标离开后才开始计时', 0.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.DraggingHoldsItOpen;
begin
  { 条在手底下消失是不可接受的。用最激进的 delay=0 逼它。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 0; }');
  TBarAccess(FBar).SetDraggingState(True);
  FBar.AutoHideTick(99999);
  { **再推一整段淡出**。StartFade 只是把淡出装上膛,并不当场改可见度 —— 少了这一拍,
    把 AutoHideHeldOpen 里的 FDragging 整个删掉,这条照样绿:装了膛没开火,读到的
    还是 1.0。实测过,它原来就是这么绿的。 }
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals('拖着的时候不能淡出', 1.0, FBar.FadeLevel, 0.001);
  TBarAccess(FBar).SetDraggingState(False);
  FBar.AutoHideTick(0);                       // delay=0 -> 立刻该淡
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals('松手之后才轮到它淡', 0.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.FadingIgnoresAnimationsEnabled;
begin
  { 内嵌条构造时一律 AnimationsEnabled := False——那管的是**滑块位置**缓动，
    有意为之（滚动要跟手，缓动会让滑块和内容错位）。淡入淡出要是共用了那个
    标志，内嵌条就永远是跳变——而内嵌条正是这个特性的主场。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.AnimationsEnabled := False;
  FBar.NoteActivity;
  FBar.AutoHideTick(1000);
  FBar.AutoHideTick(TyScrollBarFadeOutMs div 2);
  AssertTrue('淡出必须真的经过中间态，不是一步跳到 0',
    (FBar.FadeLevel > 0.0) and (FBar.FadeLevel < 1.0));
end;

procedure TTyScrollBarAutoHideTests.FadeInIsNotCutShortByTheIdleClock;
begin
  { 延时为 0 时「闲置够久了」永远成立。淡入这 120 毫秒里但凡让闲置时钟走一步,
    刚亮起来的条当场就被判定该淡出、掉头淡回去 —— 用户看到的是一闪。
    延时 1000 的那几条测不出这个:淡入总共才 120 毫秒,时钟怎么走也够不到 1000。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 0; }');
  FBar.AutoHideTick(0);
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals('先淡到底', 0.0, FBar.FadeLevel, 0.001);
  FBar.NoteActivity;
  FBar.AutoHideTick(TyScrollBarFadeInMs div 2);
  FBar.AutoHideTick(TyScrollBarFadeInMs div 2);
  AssertEquals('淡入必须跑得完,不能被自己的闲置时钟掐掉', 1.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.TurningAutoHideOffUnhidesAFadedBar;
begin
  { 淡到底的条,定时器已经把自己停了 —— 这之后关掉自动隐藏,**没有任何东西**
    会再推它一拍。要是「关着就恢复全可见」只写在 AutoHideTick 里,这条就永久隐身。
    这正是 AutoHide 走 setter 而不是裸字段的全部理由。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.NoteActivity;
  FBar.AutoHideTick(1000);
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals(0.0, FBar.FadeLevel, 0.001);
  FBar.AutoHide := sbahNever;
  AssertEquals('关掉自动隐藏就得当场看得见,不能等谁来推一拍', 1.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.SnappedMirrorCountsAsActivity;
begin
  { 宿主自己滚完内容、再把位置镜像给滑块的那条路是 SetPositionSnapped,它
    **不经过 Position 的 setter**,所以 PositionChangeCountsAsActivity 守不到它。
    全库只有 TTyGrid 这么走(其余五个宿主都是 Position := ),而网格正是最该
    看见滚动条出来的控件 —— 这条不算「在用」的话,网格滚一整天条也不露面。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.AutoHideTick(1000);
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals(0.0, FBar.FadeLevel, 0.001);
  FBar.SetPositionSnapped(42);
  FBar.AutoHideTick(TyScrollBarFadeInMs);
  AssertEquals('宿主镜像过来的位置也算在用', 1.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.ActivityCancelsAnArmedFadeOut;
begin
  { 「淡出装上了膛、但一拍都还没推进」是个真实存在的窗口:这一拍可见度还是 1.0,
    膛里装的却是 0.0。活动落在这个窗口里(滚轮、网格镜像过来的位置)而唤醒只看
    「可见度是不是 1.0」的话,这发淡出下一拍照常打出去 —— 淡出跑动期间不计闲置、
    跑完可见度又成了 0,条就一直不见了。用户看到的是:滚了一下,条反而没了。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.NoteActivity;
  FBar.AutoHideTick(1000);
  AssertEquals('前提:这一拍可见度确实还是 1.0', 1.0, FBar.FadeLevel, 0.001);
  FBar.NoteActivity;
  FBar.AutoHideTick(TyScrollBarFadeInMs);
  AssertEquals('动过之后不能还把那发陈旧的淡出打出来', 1.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.TurningItOffDisarmsAPendingFade;
begin
  { 关闭臂不光要管可见度,还要把动画停掉。可见度正好是 1.0、动画却还在跑的状态
    是够得着的(淡出刚装膛就是),漏停的话:定时器那句「没事干就歇」永远不成立,
    关着自动隐藏的条上挂着个空转定时器(无头测不到);而且自动隐藏一旦再打开,
    关之前那发陈旧的淡出会接着打出去 —— 下面验的就是后者。
    这里用**改主题**而不是改属性来关:改属性会顺带 NoteActivity,那条路会把
    陈旧的淡出重定向掉,就看不出关闭臂自己有没有做干净了。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.AutoHideTick(1000);          { 淡出装上膛,可见度仍是 1.0 }
  UseThemeCss(':root { --scrollbar-auto-hide: -1; }');
  FBar.AutoHideTick(16);            { 关闭臂:该把膛里的子弹退掉 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals('关过一趟,关之前装的那发淡出不能再打出来', 1.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.ThemeTurningItOffUnhidesAFadedBar;
begin
  { 换主题时控件收到的**只有一个 Invalidate** —— TTyStyleController.Changed 就是
    这么广播的,全库没有 StyleChanged 钩子。所以:自动隐藏的主题下淡到 0、定时器
    把自己停了,这时候换到一个不自动隐藏的主题,没有任何东西会再推它一拍,条就
    永久隐身。属性那条路(SetAutoHide)早就防了同一个坑,主题这半边漏了。
    而这个库卖的就是换肤 —— 「换个皮肤滚动条没了」不能出。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.NoteActivity;
  FBar.AutoHideTick(1000);
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals(0.0, FBar.FadeLevel, 0.001);
  UseThemeCss(':root { --scrollbar-auto-hide: -1; }');
  { **一拍都不推**:换完主题当场就得看得见。等谁来推一拍才恢复的话,真机上
    就是「换肤之后条不见了,随便滚一下又回来」那种说不清的间歇性毛病。 }
  AssertEquals('换到不自动隐藏的主题,条当场就该在那儿', 1.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.FocusBringsItBack;
begin
  { 焦点得**把条叫回来**,不能只是「不计时」。独立摆放的条 TabStop=True:淡到 0、
    定时器停了之后 Tab 过来,按住不放那条臂连跑的机会都没有(没人推它),
    键盘焦点就停在一个看不见的控件上。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.NoteActivity;
  FBar.AutoHideTick(1000);
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals(0.0, FBar.FadeLevel, 0.001);
  TBarAccess(FBar).FocusIn;
  FBar.AutoHideTick(TyScrollBarFadeInMs);
  AssertEquals('Tab 到条上就该看得见', 1.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.ThemeDelayTracksAThemeSwitch;
begin
  { 延时是按主题版本缓存的(一拍要问两次,每次都拼一个 key 字符串走 IndexOf)。
    缓存写成「主题变了再作废」的话这条会红:**库里没有主题变更通知这回事**,
    TTyStyleController.Changed 广播出来的就是一个裸 Invalidate,于是那种缓存
    会永远端着旧主题的延时。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  AssertEquals(1000, FBar.EffectiveAutoHideMs);
  UseThemeCss(':root { --scrollbar-auto-hide: 300; }');
  AssertEquals('换了主题就得读新主题的延时', 300, FBar.EffectiveAutoHideMs);
end;

procedure TTyScrollBarAutoHideTests.ThemeDelayTracksAControllerSwitch;
var
  other: TTyStyleController;
begin
  { 版本号是**每个 model 各自算的**。两个 controller 都只加载过一次主题,版本号
    就一模一样 —— 缓存只按版本号键控的话,换 controller 之后会把前一个的延时
    端出来。Controller 是个 published 属性,中途换得掉,所以键里还要有 model 身份。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  AssertEquals(1000, FBar.EffectiveAutoHideMs);
  other := TTyStyleController.Create(FForm);
  other.LoadThemeCss(':root { --scrollbar-auto-hide: 300; }');
  { 前提:两边版本号确实撞上了。撞不上这条就退化成「随便换个 controller 也对」,
    还是绿的,却什么也没验 —— 所以把前提写成断言,别让它哪天悄悄变成一条空测试。 }
  AssertTrue('前提:两个 model 的版本号确实一样',
    FCtl.Model.ThemeVersion = other.Model.ThemeVersion);
  FBar.Controller := other;
  AssertEquals('换了 controller 就得读新 model 的延时', 300, FBar.EffectiveAutoHideMs);
end;

procedure TTyScrollBarAutoHideTests.PropertyChangeIsNotServedAStaleDelay;
begin
  { 缓存只盖住「主题解出来多少」那一半;属性那一半留在缓存外面,SetAutoHide 就
    不必记得去作废它 —— 忘了作废正是缓存变成 bug 的方式。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  AssertEquals(1000, FBar.EffectiveAutoHideMs);
  FBar.AutoHide := sbahNever;
  AssertEquals('属性说关就是关,不能端上刚才那份 1000',
    TyScrollBarAutoHideOff, FBar.EffectiveAutoHideMs);
  UseThemeCss(':root { --scrollbar-auto-hide: -1; }');
  FBar.AutoHide := sbahDefault;
  AssertEquals(TyScrollBarAutoHideOff, FBar.EffectiveAutoHideMs);
  FBar.AutoHide := sbahAuto;
  AssertEquals('属性说要隐藏,主题关着就走回退',
    TyScrollBarAutoHideFallbackMs, FBar.EffectiveAutoHideMs);
end;

procedure TTyScrollBarAutoHideTests.WaitingOutTheDelayNeedsTheClock;
begin
  { 两个终态:淡到底了、以及自动隐藏关着。到了终态就该停表,没到就得转着 —— 先
    把「该转的时候在转」钉住,否则下一条「按住就停」可以靠恒 False 蒙混过关。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.NoteActivity;
  AssertTrue('还在等延时,表得转着', TBarAccess(FBar).TimerNeeded);
  FBar.AutoHideTick(1000);
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals(0.0, FBar.FadeLevel, 0.001);
  AssertFalse('淡到底了就没什么可推进的了', TBarAccess(FBar).TimerNeeded);
  UseThemeCss(':root { --scrollbar-auto-hide: -1; }');
  AssertFalse('关着自动隐藏更没有', TBarAccess(FBar).TimerNeeded);
end;

procedure TTyScrollBarAutoHideTests.PointerOnBarStopsTheClockSpinning;
begin
  { 指针停在滚动条上是个极其常见的鼠标停靠位置。按住不放的时候 AutoHideTick
    那条臂只是把闲置时钟清成 0 —— 没有任何东西要推进,却让表以 16ms 一拍转到
    天荒地老。最多 12 条内嵌条 × 60fps,烧的全是白工。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.NoteActivity;
  TBarAccess(FBar).EnterBar;
  AssertFalse('指针压着的时候没有任何东西要推进,别让表空转',
    TBarAccess(FBar).TimerNeeded);
  TBarAccess(FBar).LeaveBar;
  AssertTrue('指针一走就又有活干了', TBarAccess(FBar).TimerNeeded);
end;

procedure TTyScrollBarAutoHideTests.ARunningFadeOutranksBeingHeldOpen;
begin
  { 顺序:先问「有没有动画在跑」,再问「按住没有」。反过来的话,指针压到一条正在
    淡出的条上,掉头那发淡入当场被停表掐掉 —— 条卡在半透明上,而且再没人推它。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 0; }');
  FBar.NoteActivity;
  FBar.AutoHideTick(0);                            { 延时 0:当场装膛 }
  FBar.AutoHideTick(TyScrollBarFadeOutMs div 2);   { 淡到半路 }
  AssertTrue('前提:确实停在半路上',
    (FBar.FadeLevel > 0.0) and (FBar.FadeLevel < 1.0));
  TBarAccess(FBar).EnterBar;                       { 指针压上来 -> 掉头淡回去 }
  AssertTrue('跑着的淡入不能因为「按住了」就被掐掉',
    TBarAccess(FBar).TimerNeeded);
end;

procedure TTyScrollBarAutoHideTests.PointerLeavingRestartsTheIdleClock;
begin
  { 无头够不着「把表起回来」那一半(没句柄就不建表,FHideTimer 恒为 nil),
    这条钉的是同一句 NoteActivity 的另一半可见效果:闲置从离开这一刻重新起算。
    整个 MouseLeave 重写被删掉的话,999 + 1 就到点,条会当场开始淡出。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.NoteActivity;
  FBar.AutoHideTick(999);
  TBarAccess(FBar).LeaveBar;
  FBar.AutoHideTick(1);
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals('指针离开之后闲置要从头算,不能接着离开之前那 999 毫秒',
    1.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.FocusLeavingRestartsTheIdleClock;
begin
  { 同上,焦点那一半。DoExit 的真正职责是把停掉的表起回来,而那一半无头验不了。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.NoteActivity;
  FBar.AutoHideTick(999);
  TBarAccess(FBar).FocusOut;
  FBar.AutoHideTick(1);
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals('失焦之后闲置要从头算', 1.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.ReleasingTheThumbRestartsTheIdleClock;
begin
  { 拖动结束这一处和另两处不一样:BeginThumbDrag 不调 NoteActivity,所以按下之前
    攒的那点闲置是真的会留到松手 —— 这条测的状态在真机上就长这样。
    而且原地放手的拖动一次 Position 都不会写,EndThumbDrag 里那几句 Position :=
    顺带的 NoteActivity 一次也走不到。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.NoteActivity;
  FBar.AutoHideTick(999);
  FBar.BeginThumbDrag(0);
  FBar.EndThumbDrag;
  FBar.AutoHideTick(1);
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals('刚松手的条不能过 1 毫秒就开始淡', 1.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.OneLateTickCatchesTheFadeUp;
begin
  { 界面忙的时候定时器会被饿死 —— 而**网格滚动中正是这段代码在跑的时候**。
    按 FHideTimer.Interval 那个标称的 16 累加的话,一拍迟到 260 毫秒也只走 16,
    200 毫秒的淡出要爬将近一秒,用户看到的是条黏在屏幕上化不掉。
    这里睡一觉再走一拍:补齐的那一步必须一次把淡出走完。
    (Sleep 只会睡多不会睡少,断言取的是下界,所以不会抖。) }
  UseThemeCss(':root { --scrollbar-auto-hide: 0; }');
  FBar.NoteActivity;
  TBarAccess(FBar).HideTimerTick;          { 头一拍:16 毫秒的种子,把淡出装上膛 }
  AssertEquals('前提:这一拍只是装膛', 1.0, FBar.FadeLevel, 0.001);
  Sleep(TyScrollBarFadeOutMs + 60);
  TBarAccess(FBar).HideTimerTick;
  AssertEquals('一拍迟到这么久,淡出必须一次补齐,不是走 16 毫秒',
    0.0, FBar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.BackToBackTicksStepTheFadeInsteadOfSnappingIt;
begin
  { 真实经过时间会给出 0 毫秒的一步(两拍落在同一个 tick 里),而
    TTyAnimator.Advance 把 AMs <= 0 当成「直接吸附到 Target」—— 钳到至少 1
    毫秒的那道闸要是被拿掉,淡出就从渐变变成跳变:下面读到的会是 0.0。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 0; }');
  FBar.NoteActivity;
  TBarAccess(FBar).HideTimerTick;          { 装膛,可见度仍是 1.0 }
  AssertEquals('前提:这一拍只是装膛', 1.0, FBar.FadeLevel, 0.001);
  TBarAccess(FBar).HideTimerTick;          { 紧接着一拍:真实经过 0 毫秒 }
  AssertTrue('0 毫秒的一步会被 Advance 当成吸附,淡出就成了跳变',
    (FBar.FadeLevel > 0.0) and (FBar.FadeLevel < 1.0));
end;

procedure TTyScrollBarAutoHideTests.AStoppedClockDoesNotBankTheTimeItWasStoppedFor;
begin
  { 停表的时候不把时刻戳清掉,重新起表的头一拍就会把**停着的那整段时间**报出来。
    真机上这就是:指针在滚动条上歇了一会儿(表停着),一挪开条当场就没了 —— 闲置
    时钟被那一拍一步推过了延时。指针停在滚动条上正是这个特性最常撞上的场景。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 300; }');
  FBar.NoteActivity;
  TBarAccess(FBar).HideTimerTick;          { 表转起来,顺便把时刻戳打上 }
  TBarAccess(FBar).EnterBar;               { 指针压上来 }
  TBarAccess(FBar).HideTimerTick;          { 这一拍把表停掉,戳该跟着清 }
  Sleep(400);                              { 指针在条上歇着,比延时还久 }
  TBarAccess(FBar).LeaveBar;               { 挪开:表起回来 }
  TBarAccess(FBar).HideTimerTick;          { 头一拍只能是种子值,不能是那 400 毫秒 }
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals('歇着的那 400 毫秒不算闲置,挪开之后还得等满 300 毫秒',
    1.0, FBar.FadeLevel, 0.001);
end;

initialization
  RegisterTest(TTyScrollBarAutoHideTests);
end.
