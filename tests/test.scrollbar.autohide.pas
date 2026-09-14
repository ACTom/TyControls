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
    { DoEnter 同样是 protected。 }
    procedure FocusIn;
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

initialization
  RegisterTest(TTyScrollBarAutoHideTests);
end.
