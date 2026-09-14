unit test.scrollbar.autohide;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, TypInfo, fpcunit, testregistry, Forms, Controls, StdCtrls, Graphics,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.ScrollBar, tyControls.Panel,
  { 内嵌了滚动条的宿主——转发那一组测试要的。 }
  tyControls.ListBox, tyControls.Memo, tyControls.Grid, tyControls.ListView,
  { 内置主题包——「现代开、经典关」那条要按名字装真皮肤,不是手写 CSS。 }
  tyControls.BuiltinThemes,
  tyControls.ScrollBox, tyControls.TreeView, tyControls.ValueListEditor;

type
  TTyScrollBarAutoHideTests = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FBar: TTyScrollBar;
    procedure UseThemeCss(const ACss: string);
    { 宿主转发那一组共用的两个探针，见各自的实现处。 }
    procedure CheckHostDeclaredDefault(AHost: TComponent; const AWhat: string);
    procedure CheckBothBarsGot(AHost: TWinControl; AValue: TTyScrollBarAutoHide;
      const AWhat: string);
    function NewListBox: TTyListBox;
    procedure FillListBox(ALb: TTyListBox);
    function NewMemo: TTyMemo;
    function NewGrid: TTyStringGrid;
    function NewListView: TTyListView;
    function NewScrollBox: TTyScrollBox;
    function NewTreeView: TTyTreeView;
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
    procedure DesignTimeNeverHides;
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
    procedure FadeMultipliesIntoStyleOpacity;
    procedure FadingMarksOpacityPresentEvenWhenTheThemeNeverSetIt;
    procedure AtRestTheThemeStyleIsHandedOverUntouched;
    procedure FadeReachesThePaintedPixels;
    procedure HidingShowsTheRealParentBackgroundNotAFlatSlab;
    { --- 宿主转发 ------------------------------------------------------------
      每个宿主一组，故意不写成循环：六个宿主的构造路径各不相同(两个惰性、
      四个急切，其中 ScrollBox 的「急切」还发生在 inherited Create 里面)，
      挂了一个要能一眼看出是哪个。 }
    procedure ListBoxForwardsToItsEmbeddedBars;
    procedure ListBoxForwardsToBarsBornLater;
    procedure ListBoxDeclaredDefaultMatchesConstructed;
    procedure MemoForwardsToItsEmbeddedBars;
    procedure MemoForwardsToBarsBornLater;
    procedure MemoDeclaredDefaultMatchesConstructed;
    procedure GridForwardsToItsEmbeddedBars;
    procedure GridDeclaredDefaultMatchesConstructed;
    procedure ListViewForwardsToItsEmbeddedBars;
    procedure ListViewDeclaredDefaultMatchesConstructed;
    procedure ScrollBoxForwardsToItsEmbeddedBars;
    procedure ScrollBoxBuildsItsBarsInsideInheritedCreate;
    procedure ScrollBoxDeclaredDefaultMatchesConstructed;
    procedure TreeViewForwardsToItsEmbeddedBars;
    procedure TreeViewDeclaredDefaultMatchesConstructed;
    { 后代白拿。这不是第七个宿主，是「白拿」那句话的凭据。 }
    procedure ValueListEditorInheritsTheListBoxProperty;
    { --- 出厂主题 ------------------------------------------------------------ }
    procedure ModernThemesHideClassicThemesDoNot;
    procedure AppWideOffSwitchIsTheControllerStyleOverride;
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
    { SetDesigning 在 TComponent 上也是 protected,同一个口子。 }
    procedure MarkDesigning(AValue: Boolean);
    { 「延时表还有没有活干」这个判断在 protected 里。**能验的只有这个判断**:
      无头没有句柄就不建表(EnsureHideTimer 直接 Exit),FHideTimer 恒为 nil,
      「停表」这个动作本身在无头下不存在。 }
    function TimerNeeded: Boolean;
    { 手动走一拍真正的 timer 回调。 }
    procedure HideTimerTick;
    { RenderTo 在 protected 里。走同一个口，和 test.controls.scrollbar.pas
      的 TScrollAccess.SmokeRender 一个路子。 }
    procedure RenderInto(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  { 受控时钟驱动的淡入淡出。照 test.controls.scrollbar.pas 里 TFakeClockScroll
    的路子(位置缓动那边的同一个问题:名义间隔写错了没人看得出来),但缝的位置
    不一样:**桩喂的是「现在几点」,不是算好的差值**。至少 1 毫秒的钳位和首拍
    的种子值都长在 FadeTickElapsedMs 里,覆写它等于把被测的那段逻辑搬进桩子,
    喂个 0 下去测出来的只是桩子会不会返回 0。

    有了它,「按真实时间推进」和「0 毫秒的一步要被钳住」两条都是**确定性**的,
    不用靠 Sleep 去撞真实时钟的刻度。 }
  TFakeFadeClock = class(TBarAccess)
  private
    FNow: QWord;
  protected
    function FadeNowMs: QWord; override;
  public
    constructor Create(AOwner: TComponent); override;
    { 墙上的钟往前走，但**不走 timer** —— 表停着的那段时间就长这样。 }
    procedure AdvanceClock(AMs: Integer);
    { 钟往前走 AMs 毫秒，然后走一拍真正的 timer 回调。 }
    procedure Tick(AMs: Integer);
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

procedure TBarAccess.MarkDesigning(AValue: Boolean);
begin
  SetDesigning(AValue, False);
end;

function TBarAccess.TimerNeeded: Boolean;
begin
  Result := AutoHideTimerNeeded;
end;

procedure TBarAccess.HideTimerTick;
begin
  HandleHideTimerTick;
end;

procedure TBarAccess.RenderInto(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

constructor TFakeFadeClock.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  { 别从 0 起:0 是 FFadeLastTickMs 「还没开始」的哨兵。真机上 GetTickCount64
    给 0 只有开机那一瞬,这里只是别在测试里把那个哨兵撞出来。 }
  FNow := 100000;
end;

function TFakeFadeClock.FadeNowMs: QWord;
begin
  Result := FNow;
end;

procedure TFakeFadeClock.AdvanceClock(AMs: Integer);
begin
  Inc(FNow, QWord(AMs));
end;

procedure TFakeFadeClock.Tick(AMs: Integer);
begin
  AdvanceClock(AMs);
  HideTimerTick;
end;

function NewFakeClockBar(AForm: TForm; ACtl: TTyStyleController): TFakeFadeClock;
begin
  { 同 SetUp:必须有父控件、必须自带 controller,否则读的是进程级主题
    ——单跑绿、全量红。 }
  Result := TFakeFadeClock.Create(AForm);
  Result.Parent := AForm;
  Result.Controller := ACtl;
end;

{ 把条画进一张先铺了 AWipe 的位图，数两件事：
    ANotGround —— 有多少像素**不是**底色,也就是条还看得见多少;
    AWipeLeft  —— 有多少像素还留着底漆,也就是渲染压根没碰到的地方。
  第二个数不是凑数的:没有它,「一个非底色像素都没有」这句在一张根本没画过的
  位图上也成立。 }
procedure RenderAndTally(ABar: TBarAccess; AGround, AWipe: TColor;
  out ANotGround, AWipeLeft: Integer);
const
  BarW = 16;
  BarH = 160;
var
  bmp: TBitmap;
  re: TBGRABitmap;
  gnd, wip, p: TBGRAPixel;
  x, y: Integer;
begin
  ANotGround := 0;
  AWipeLeft := 0;
  gnd := ColorToBGRA(ColorToRGB(AGround));
  wip := ColorToBGRA(ColorToRGB(AWipe));
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(BarW, BarH);
    bmp.Canvas.Brush.Color := AWipe;
    bmp.Canvas.FillRect(0, 0, BarW, BarH);
    ABar.RenderInto(bmp.Canvas, Rect(0, 0, BarW, BarH), 96);
    re := TBGRABitmap.Create(bmp);
    try
      { 只比 RGB。pf32bit 的 GDI 位图读回来 alpha 通道是不可信的(全图会被
        校正),拿 alpha 做断言永远成立。 }
      for y := 0 to BarH - 1 do
        for x := 0 to BarW - 1 do
        begin
          p := re.GetPixel(x, y);
          if (p.red <> gnd.red) or (p.green <> gnd.green) or (p.blue <> gnd.blue) then
            Inc(ANotGround);
          if (p.red = wip.red) and (p.green = wip.green) and (p.blue = wip.blue) then
            Inc(AWipeLeft);
        end;
    finally
      re.Free;
    end;
  finally
    bmp.Free;
  end;
end;

{ 画一帧，数有多少像素**正好**落在 AColor 上。
  用来问「淡出途中还有没有东西停在它主题里那个原色上」——漏掉淡出的元素
  会原样保留自己的颜色，被淡到的不会。 }
function RenderAndCountExact(ABar: TBarAccess; AColor: TColor): Integer;
const
  BarW = 16;
  BarH = 160;
var
  bmp: TBitmap;
  re: TBGRABitmap;
  c, p: TBGRAPixel;
  x, y: Integer;
begin
  Result := 0;
  c := ColorToBGRA(ColorToRGB(AColor));
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(BarW, BarH);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, BarW, BarH);
    ABar.RenderInto(bmp.Canvas, Rect(0, 0, BarW, BarH), 96);
    re := TBGRABitmap.Create(bmp);
    try
      for y := 0 to BarH - 1 do
        for x := 0 to BarW - 1 do
        begin
          p := re.GetPixel(x, y);
          if (p.red = c.red) and (p.green = c.green) and (p.blue = c.blue) then
            Inc(Result);
        end;
    finally
      re.Free;
    end;
  finally
    bmp.Free;
  end;
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
  { 装一个主题，但它不提这个令牌——经典世代的皮肤就是这样(只有四个现代皮肤写了它),
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
  AssertEquals('到点这一拍只装膛 -> 可见度还没动', 1.0, FBar.FadeLevel, 0.001);
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

procedure TTyScrollBarAutoHideTests.DesignTimeNeverHides;
begin
  UseThemeCss(':root { --scrollbar-auto-hide: 0; }');   // 最激进：立即隐藏
  TBarAccess(FBar).MarkDesigning(True);
  FBar.AutoHideTick(99999);
  { 第二个 tick 不能省。第一个 tick 只是「武装」淡出——StartFade 不动
    FadeLevel，所以门控删没删，这一刻都读 1.0。真正把两种实现分开的是
    下面这一下：门控还在就什么都不会发生，门控没了就会跑完 200ms 淡出。 }
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals('设计器里看不见滚动条是不可接受的', 1.0, FBar.FadeLevel, 0.001);
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
  { 两个终态:自动隐藏关着、以及已经淡到底。到了终态就该停表,没到就得转着 ——
    先把「该转的时候在转」钉住,否则下面两条「不该转」可以靠恒 False 蒙混过关。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.NoteActivity;
  AssertTrue('还在等延时,表得转着', TBarAccess(FBar).TimerNeeded);

  { 「关着」这一条必须**趁可见度还是 1.0** 验。放到淡到底之后再验是条永远不会
    红的断言:那时候「已经淡到底」自己就把结果按成 False 了,把延时那一条整个
    删掉照样绿(第一版就是这么写的,而且真的漏掉了一个活着的变异体)。
    丢了这一条的后果也不是化妆品:自动隐藏关掉的那一刻表要是正转着,它就
    **再也停不下来** —— 一条主人压根没开这个特性的条上挂着个 60fps 的空转定时器,
    而构造函数许诺的是「不开这个特性的人一分钱不花」。 }
  UseThemeCss(':root { --scrollbar-auto-hide: -1; }');
  AssertFalse('关着的时候可见度还是 1.0,一样不该转', TBarAccess(FBar).TimerNeeded);

  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.NoteActivity;
  FBar.AutoHideTick(1000);
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals(0.0, FBar.FadeLevel, 0.001);
  AssertFalse('淡到底了就没什么可推进的了', TBarAccess(FBar).TimerNeeded);
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
  { 顺序:先问「有没有动画在跑」,再问「按住没有」。反过来是 Task 3 那个搁浅 bug
    的完整重演,不是「条多留一会儿」那种小毛病 ——

    条已经淡到 0、表也停了。指针移到它(看不见的)那块地方上:MouseEnter ->
    NoteActivity 把淡入装上膛、顺手把表起起来。要是先问「按住没有」,刚起起来的
    表**头一拍就把自己停掉**;而指针一直搁在那儿,再没有第二个 MouseEnter ——
    条就在指针底下永远不出现。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }');
  FBar.NoteActivity;
  FBar.AutoHideTick(1000);
  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals('前提:条已经看不见了', 0.0, FBar.FadeLevel, 0.001);
  AssertFalse('前提:这时候表本来就停着', TBarAccess(FBar).TimerNeeded);
  TBarAccess(FBar).EnterBar;                       { 指针移到那条看不见的条上 }
  AssertTrue('指针刚把淡入装上膛,这一拍要是因为「按住了」就停表,条永远不出现',
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
var
  bar: TFakeFadeClock;
begin
  { 界面忙的时候定时器会被饿死 —— 而**网格滚动中正是这段代码在跑的时候**。
    按 FHideTimer.Interval 那个标称的 16 累加的话,一拍迟到 260 毫秒也只走 16,
    200 毫秒的淡出要爬将近一秒,用户看到的是条黏在屏幕上化不掉。
    受控时钟直接把「这一拍隔了 260 毫秒」摆出来,不用睡。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 0; }');
  bar := NewFakeClockBar(FForm, FCtl);
  bar.NoteActivity;
  bar.Tick(16);                            { 头一拍:16 毫秒的种子,把淡出装上膛 }
  AssertEquals('前提:这一拍只是装膛', 1.0, bar.FadeLevel, 0.001);
  bar.Tick(TyScrollBarFadeOutMs + 60);     { 被饿死的一拍 }
  AssertEquals('一拍迟到这么久,淡出必须一次补齐,不是走 16 毫秒',
    0.0, bar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.BackToBackTicksStepTheFadeInsteadOfSnappingIt;
var
  bar: TFakeFadeClock;
begin
  { 两拍落在同一个时钟刻度里,真实经过时间就是 0 —— 而 TTyAnimator.Advance 把
    AMs <= 0 当成「直接吸附到 Target」。钳到至少 1 毫秒的那道闸要是被拿掉,
    淡出就从渐变变成跳变:下面读到的会是 0.0。
    时钟是喂的,所以「同一刻度」是摆出来的,不是撞出来的 —— 靠真实 GetTickCount64
    去撞,这条只能算个概率性的守卫。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 0; }');
  bar := NewFakeClockBar(FForm, FCtl);
  bar.NoteActivity;
  bar.Tick(16);                            { 装膛,可见度仍是 1.0 }
  AssertEquals('前提:这一拍只是装膛', 1.0, bar.FadeLevel, 0.001);
  bar.Tick(0);                             { 紧接着一拍:钟一点没动 }
  AssertTrue('0 毫秒的一步会被 Advance 当成吸附,淡出就成了跳变',
    (bar.FadeLevel > 0.0) and (bar.FadeLevel < 1.0));
end;

procedure TTyScrollBarAutoHideTests.AStoppedClockDoesNotBankTheTimeItWasStoppedFor;
var
  bar: TFakeFadeClock;
begin
  { 停表的时候不把时刻戳清掉,重新起表的头一拍就会把**停着的那整段时间**报出来。
    真机上这就是:指针在滚动条上歇了一会儿(表停着),一挪开条当场就没了 —— 闲置
    时钟被那一拍一步推过了延时。指针停在滚动条上正是这个特性最常撞上的场景。
    AdvanceClock 而不是 Tick:表停着的那段**墙上的钟照走、timer 不走**,这个
    区别正是本条要摆出来的东西。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 300; }');
  bar := NewFakeClockBar(FForm, FCtl);
  bar.NoteActivity;
  bar.Tick(16);                { 表转起来,顺便把时刻戳打上 }
  bar.EnterBar;                { 指针压上来 }
  bar.Tick(1);                 { 这一拍把表停掉,戳该跟着清 }
  bar.AdvanceClock(400);       { 指针在条上歇着:表停了,钟照走,比延时还久 }
  bar.LeaveBar;                { 挪开:表起回来 }
  bar.Tick(1);                 { 头一拍只能是种子值,不能是那 400 毫秒 }
  bar.AutoHideTick(TyScrollBarFadeOutMs);
  AssertEquals('歇着的那 400 毫秒不算闲置,挪开之后还得等满 300 毫秒',
    1.0, bar.FadeLevel, 0.001);
end;

procedure TTyScrollBarAutoHideTests.FadeMultipliesIntoStyleOpacity;
var
  s: TTyStyleSet;
begin
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }' +
              'TyScrollBar { background: #808080; color: #404040; opacity: 0.5; }');
  FBar.NoteActivity;
  s := FBar.PaintStyleForTest;
  AssertEquals('完全可见时就是主题自己的 opacity', 0.5, s.Opacity, 0.001);

  { 两拍,不是一拍。头一拍只是**把淡出装上膛** —— StartFade 不动可见度,
    这时候问 opacity 拿到的还是主题那个 0.5。本特性已经有四条测试栽在
    「断言落在装膛那一拍上」,所以推进那一拍必须单独写出来。 }
  FBar.AutoHideTick(1000);

  { **中途**这一刀是乘法唯一咬得住的地方。1.0 那头走的是早退、乘法根本没跑;
    0.0 那头随便乘什么都是 0 —— 两头都是「两个答案碰巧一致」,把 base 整个
    删掉也照样绿。只有卡在中间,0.5 × 系数 和 系数 才分得开。
    动画吃的是明确的毫秒数,所以这一刀是确定的,不靠撞时钟。 }
  FBar.AutoHideTick(TyScrollBarFadeOutMs div 3);
  AssertTrue('前置：确实卡在中途', (FBar.FadeLevel > 0.01) and (FBar.FadeLevel < 0.99));
  s := FBar.PaintStyleForTest;
  AssertEquals('主题的 0.5 必须乘进去，不是被顶掉',
    0.5 * FBar.FadeLevel, s.Opacity, 0.001);

  FBar.AutoHideTick(TyScrollBarFadeOutMs);
  s := FBar.PaintStyleForTest;
  AssertEquals('淡出到底 -> 0，而不是主题的 0.5', 0.0, s.Opacity, 0.001);
  { 这一句**咬不动** —— 上面那段 css 自己就写了 opacity: 0.5,tpOpacity 是
    主题放进 Present 的,把 PaintStyle 里的 Include 删掉它照样绿(变异测试
    证过)。留着是因为它说清了意图;真正守得住的那一半在下一条。 }
  AssertTrue('必须把 tpOpacity 标成 present，否则画笔根本不看这个值',
    tpOpacity in s.Present);
end;

procedure TTyScrollBarAutoHideTests.FadingMarksOpacityPresentEvenWhenTheThemeNeverSetIt;
var
  s: TTyStyleSet;
begin
  { 主题一个字没提 opacity —— 那 Present 里的 tpOpacity 只可能是淡出自己
    补的。没补上的话 TyApplyStyleOpacity 连看都不看那个值,画笔的 opacity
    一直是 1,条永远淡不掉。
    内置主题给 TyScrollBar 写 opacity 的只有 :disabled 那一条,所以「没有
    基数」正是常态那一格该走的路,上一条测的有基数那一格反倒是禁用态。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }' +
              'TyScrollBar { background: #808080; }');
  FBar.NoteActivity;
  FBar.AutoHideTick(1000);                    { 装上膛 }

  { 同样要在中途看一眼,理由和上一条一样,但咬的是**另一个** base:这里走的是
    「主题没给基数 -> 按 1.0 算」那条岔路。把它改成 0.0,淡到底那一格照样是 0、
    看不出来;中途这一格立刻露馅。 }
  FBar.AutoHideTick(TyScrollBarFadeOutMs div 3);
  AssertTrue('前置：确实卡在中途', (FBar.FadeLevel > 0.01) and (FBar.FadeLevel < 0.99));
  s := FBar.PaintStyleForTest;
  AssertEquals('没有主题基数就按 1.0 算，乘出来就是可见度本身',
    FBar.FadeLevel, s.Opacity, 0.001);

  FBar.AutoHideTick(TyScrollBarFadeOutMs);    { 这一拍推到底 }
  AssertEquals('前置条件：确实淡到底了', 0.0, FBar.FadeLevel, 0.001);
  s := FBar.PaintStyleForTest;
  AssertTrue('主题没写 opacity 时，这个标记只可能是淡出补上的',
    tpOpacity in s.Present);
  AssertEquals('没有主题基数就按 1.0 算，乘完是 0', 0.0, s.Opacity, 0.001);
end;

procedure TTyScrollBarAutoHideTests.AtRestTheThemeStyleIsHandedOverUntouched;
var
  s: TTyStyleSet;
begin
  { 主题没写 opacity、条又完全可见 —— 这份样式必须**原样**交给 RenderTo。
    凭空补一个 tpOpacity 进去,绘制就从「不碰 opacity」那条路挪到「碰」那条
    路上(EndPaint 里是两段不同的合成代码),而 golden 守的正是「没开自动隐藏
    的条,一个像素都不许变」。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }' +
              'TyScrollBar { background: #808080; }');
  FBar.NoteActivity;
  s := FBar.PaintStyleForTest;
  AssertEquals('前置条件：确实是完全可见那一格', 1.0, FBar.FadeLevel, 0.001);
  AssertFalse('静止时不许凭空造一个 opacity 出来', tpOpacity in s.Present);
end;

procedure TTyScrollBarAutoHideTests.FadeReachesThePaintedPixels;
const
  { 哨兵底色,**不能用白** —— 白正好是 light 主题的表面色,「淡没了」和
    「本来就是白的」给的是同一个答案。 }
  Ground = TColor($FF00FF);   { 品红：父窗口的底色,也就是「彻底淡掉」该长的样子 }
  Wipe   = TColor($00FF00);   { 亮绿：渲染前铺上去,用来证明这块地方真被画过 }
var
  bar: TBarAccess;
  visible, hidden, wipeLeft: Integer;
begin
  { 这一条守的是**接线**,不是算术。FadeMultipliesIntoStyleOpacity 问的是
    「乘出来的 opacity 对不对」,可它一次都没走过 RenderTo —— 把 RenderTo 里
    那句改回 CurrentStyle,它照样全绿。「建好了没接线」是本库的默认故障,
    已经八次,所以这一条一路数到像素。

    顺带把滑块也一起守了:滑块的样式是另一次 ResolveStyle('TyScrollThumb'),
    不经过 PaintStyle。它跟着淡是因为 opacity 是**画笔级**的(EndPaint 对
    整张 FBmp 做 ApplyGlobalOpacity),不是因为谁去乘了滑块的样式 —— 哪天
    滑块被挪去单开一个 painter,这条会红。 }
  FForm.Color := Ground;
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }' +
              'TyScrollBar { background: #808080; border-width: 0px; }' +
              'TyScrollThumb { background: #202020; }');
  bar := TBarAccess.Create(FForm);
  bar.Parent := FForm;
  bar.Controller := FCtl;
  bar.SetBounds(0, 0, 16, 160);
  bar.NoteActivity;

  RenderAndTally(bar, Ground, Wipe, visible, wipeLeft);
  AssertEquals('渲染要盖满整块——还留着底漆就说明这条压根没画', 0, wipeLeft);
  { 不是「画了点什么」,是**整块都画满了**。这段 css 没有边框、没有圆角,
    base 层又被压掉了,所以没有半透明的抗锯齿边——静止时 16×160 一个不少
    全是条自己的颜色。顺手把「静止时条不透明地铺满自己那块矩形」也钉住。 }
  AssertEquals('静止时整块都是条(否则下面那句「不见了」谁都能过)', 16 * 160, visible);

  bar.AutoHideTick(1000);                    { 到点,装上膛 }

  { **中途**这一刀是滑块那条结论唯一还咬得住的地方。淡到底那一格现在被
    RenderTo 的短路接管了(压根不画),所以「滑块跟着条一起淡」只在这 200
    毫秒里看得见。判据:漏掉淡出的元素会原样留着它主题里那个原色,被淡到的
    不会 —— 所以中途一个像素都不该还停在 #808080 或 #202020 上。 }
  bar.AutoHideTick(TyScrollBarFadeOutMs div 3);
  AssertTrue('前置：确实卡在中途',
    (bar.FadeLevel > 0.01) and (bar.FadeLevel < 0.99));
  AssertEquals('淡出途中不该有像素还停在条身的原色上',
    0, RenderAndCountExact(bar, TColor($808080)));
  AssertEquals('淡出途中不该有像素还停在滑块的原色上',
    0, RenderAndCountExact(bar, TColor($202020)));

  bar.AutoHideTick(TyScrollBarFadeOutMs);    { 这一拍推到底 }
  AssertEquals('前置条件：确实淡到底了', 0.0, bar.FadeLevel, 0.001);

  RenderAndTally(bar, Ground, Wipe, hidden, wipeLeft);
  AssertEquals('渲染要盖满整块', 0, wipeLeft);
  AssertEquals('淡到底之后一个像素都不该剩下——边框、滑块、两头的箭头全算',
    0, hidden);
end;

procedure TTyScrollBarAutoHideTests.HidingShowsTheRealParentBackgroundNotAFlatSlab;
const
  Wipe = TColor($00FF00);
var
  panel: TTyPanel;
  bar: TBarAccess;
  bmp: TBitmap;
  re: TBGRABitmap;
  top, bot: Integer;
begin
  { 父控件的背景是**渐变**的。彻底隐身那一格要是照旧走画笔的 opacity,
    EndPaint 会按 TyResolveParentBg 给的**一个居中采样色**铺一块不透明平板,
    再把 alpha 全零的图盖上去 —— 条那块矩形上下两头一样亮,成了渐变上挖出来
    的一个方块。短路之后铺的是 TyFillParentBg 的渐变**切片**,上下差一整条
    ramp。

    上一条 FadeReachesThePaintedPixels 照不出这个区别:那里的父控件是纯色的
    TForm,居中采样色**恰好**等于真背景,两条路给的是同一张图。 }
  UseThemeCss(':root { --scrollbar-auto-hide: 1000; }' +
              'TyPanel { background: linear-gradient(90deg, #000000, #FFFFFF);' +
              ' border-width: 0px; padding: 0px; }' +
              'TyScrollBar { background: #808080; border-width: 0px; }' +
              'TyScrollThumb { background: #202020; }');
  panel := TTyPanel.Create(FForm);
  panel.Parent := FForm;
  panel.Controller := FCtl;
  panel.SetBounds(0, 0, 16, 160);
  bar := TBarAccess.Create(FForm);
  bar.Parent := panel;
  bar.Controller := FCtl;
  bar.SetBounds(0, 0, 16, 160);
  bar.NoteActivity;
  bar.AutoHideTick(1000);                    { 装上膛 }
  bar.AutoHideTick(TyScrollBarFadeOutMs);    { 这一拍推到底 }
  AssertEquals('前置条件：确实淡到底了', 0.0, bar.FadeLevel, 0.001);

  bmp := TBitmap.Create;
  re := nil;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(16, 160);
    bmp.Canvas.Brush.Color := Wipe;
    bmp.Canvas.FillRect(0, 0, 16, 160);
    bar.RenderInto(bmp.Canvas, Rect(0, 0, 16, 160), 96);
    re := TBGRABitmap.Create(bmp);
    top := re.GetPixel(8, 4).green;
    bot := re.GetPixel(8, 155).green;
  finally
    re.Free;
    bmp.Free;
  end;
  AssertTrue(Format('隐身那块要透出真的渐变，不是一块平板(顶=%d 底=%d)',
    [top, bot]), bot - top > 100);
end;

{ ---- 宿主转发 -------------------------------------------------------------- }

function FindEmbeddedBar(AHost: TWinControl; AKind: TTyScrollBarKind): TTyScrollBar;
var
  i: Integer;
begin
  { 内嵌条是宿主的真子控件(建的时候 Parent := Self)，所以遍历得到。
    这样就不用为了测试给宿主开一个 public 函数——那种测试专用 API
    一旦进了公开面就再也删不掉。 }
  Result := nil;
  for i := 0 to AHost.ControlCount - 1 do
    if (AHost.Controls[i] is TTyScrollBar)
       and (TTyScrollBar(AHost.Controls[i]).Kind = AKind) then
      Exit(TTyScrollBar(AHost.Controls[i]));
end;

procedure TTyScrollBarAutoHideTests.CheckBothBarsGot(AHost: TWinControl;
  AValue: TTyScrollBarAutoHide; const AWhat: string);
var
  v, h: TTyScrollBar;
begin
  { 两条都查。转发这种四平八稳的代码最容易只写一半——竖条接了、横条忘了，
    而只查竖条的测试对这种一半照样是绿的。 }
  v := FindEmbeddedBar(AHost, sbVertical);
  h := FindEmbeddedBar(AHost, sbHorizontal);
  AssertTrue(AWhat + '：内嵌竖条应当已经存在', v <> nil);
  AssertTrue(AWhat + '：内嵌横条应当已经存在', h <> nil);
  AssertEquals(AWhat + '：属性必须传到内嵌竖条上', Ord(AValue), Ord(v.AutoHide));
  AssertEquals(AWhat + '：属性必须传到内嵌横条上', Ord(AValue), Ord(h.AutoHide));
end;

procedure TTyScrollBarAutoHideTests.CheckHostDeclaredDefault(AHost: TComponent;
  const AWhat: string);
var
  pi: PPropInfo;
begin
  { 声明的 default 与构造值不一致 -> .lfm 里写的值被当默认省略 -> 加载后丢失。
    全库没有能扫出这种不一致的统一守卫，逐属性写就是全部机制；断言消息里带
    宿主名，挂哪个一眼看得出。 }
  pi := GetPropInfo(AHost, 'ScrollBarAutoHide');
  AssertTrue(AWhat + '：ScrollBarAutoHide 必须是 published', pi <> nil);
  AssertEquals(AWhat + '：声明的 default 必须等于构造函数赋的值',
    Integer(GetOrdProp(AHost, pi)), Integer(pi^.Default));
end;

function TTyScrollBarAutoHideTests.NewListBox: TTyListBox;
begin
  Result := TTyListBox.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.SetBounds(0, 0, 120, 60);
end;

procedure TTyScrollBarAutoHideTests.FillListBox(ALb: TTyListBox);
var
  i: Integer;
begin
  { ListBox 的两条是**惰性创建**的：不塞够条目竖条根本不存在，于是
    「找不到条」会被误读成「转发没生效」。横条还要 ScrollWidth 撑出横向溢出。 }
  for i := 1 to 100 do ALb.Items.Add('item ' + IntToStr(i));
  ALb.ScrollWidth := 600;
end;

procedure TTyScrollBarAutoHideTests.ListBoxForwardsToItsEmbeddedBars;
var
  lb: TTyListBox;
begin
  { 「建好了没接线」是本库的默认故障，已经八次。转发这种四平八稳的代码最容易
    只写一半——属性加了，创建处没传。 }
  lb := NewListBox;
  FillListBox(lb);
  lb.ScrollBarAutoHide := sbahNever;
  CheckBothBarsGot(lb, sbahNever, 'ListBox');
end;

procedure TTyScrollBarAutoHideTests.ListBoxForwardsToBarsBornLater;
var
  lb: TTyListBox;
begin
  { setter 管「已经建好的」，创建处管「之后才建的」。只写 setter 的话，
    先设属性后滚动的用法会静静丢值——而那正是最自然的用法：在 .lfm 里设好，
    列表运行时才填满。 }
  lb := NewListBox;
  AssertTrue('前置条件：这会儿一条都还没有',
    (FindEmbeddedBar(lb, sbVertical) = nil) and (FindEmbeddedBar(lb, sbHorizontal) = nil));
  lb.ScrollBarAutoHide := sbahAuto;
  FillListBox(lb);
  CheckBothBarsGot(lb, sbahAuto, 'ListBox(后生的条)');
end;

procedure TTyScrollBarAutoHideTests.ListBoxDeclaredDefaultMatchesConstructed;
begin
  CheckHostDeclaredDefault(NewListBox, 'ListBox');
end;

function TTyScrollBarAutoHideTests.NewMemo: TTyMemo;
begin
  Result := TTyMemo.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.SetBounds(0, 0, 200, 120);
end;

procedure TTyScrollBarAutoHideTests.MemoForwardsToItsEmbeddedBars;
var
  m: TTyMemo;
begin
  { Memo 的两条同样惰性：ssBoth 把两条都要出来(WordWrap 默认 False，
    横条那条臂才走得到)。不先要出来，「找不到条」会被误读成「转发没生效」。 }
  m := NewMemo;
  m.ScrollBars := ssBoth;
  m.ScrollBarAutoHide := sbahNever;
  CheckBothBarsGot(m, sbahNever, 'Memo');
end;

procedure TTyScrollBarAutoHideTests.MemoForwardsToBarsBornLater;
var
  m: TTyMemo;
begin
  { 和 ListBox 同一条缝：setter 够不着还没出生的条。 }
  m := NewMemo;
  AssertTrue('前置条件：这会儿一条都还没有',
    (FindEmbeddedBar(m, sbVertical) = nil) and (FindEmbeddedBar(m, sbHorizontal) = nil));
  m.ScrollBarAutoHide := sbahAuto;
  m.ScrollBars := ssBoth;
  CheckBothBarsGot(m, sbahAuto, 'Memo(后生的条)');
end;

procedure TTyScrollBarAutoHideTests.MemoDeclaredDefaultMatchesConstructed;
begin
  CheckHostDeclaredDefault(NewMemo, 'Memo');
end;

function TTyScrollBarAutoHideTests.NewGrid: TTyStringGrid;
begin
  { 属性和两条条都长在 TTyCustomGrid 上；用发布出去的那个后代建，
    顺带验一句「后代真的继承得到」——用户拖到窗体上的是它，不是基类。 }
  Result := TTyStringGrid.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.SetBounds(0, 0, 200, 120);
end;

procedure TTyScrollBarAutoHideTests.GridForwardsToItsEmbeddedBars;
var
  g: TTyStringGrid;
begin
  { 网格的两条在构造函数里就建好了(只是 Visible := False)，不用塞内容——
    所以这里走的是 setter 那一半。 }
  g := NewGrid;
  g.ScrollBarAutoHide := sbahNever;
  CheckBothBarsGot(g, sbahNever, 'Grid');
end;

procedure TTyScrollBarAutoHideTests.GridDeclaredDefaultMatchesConstructed;
begin
  CheckHostDeclaredDefault(NewGrid, 'Grid');
end;

function TTyScrollBarAutoHideTests.NewListView: TTyListView;
begin
  Result := TTyListView.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.SetBounds(0, 0, 200, 120);
end;

procedure TTyScrollBarAutoHideTests.ListViewForwardsToItsEmbeddedBars;
var
  lv: TTyListView;
begin
  { 和网格一样，两条在构造函数里就建好了，不用塞内容。 }
  lv := NewListView;
  lv.ScrollBarAutoHide := sbahNever;
  CheckBothBarsGot(lv, sbahNever, 'ListView');
end;

procedure TTyScrollBarAutoHideTests.ListViewDeclaredDefaultMatchesConstructed;
begin
  CheckHostDeclaredDefault(NewListView, 'ListView');
end;

function TTyScrollBarAutoHideTests.NewScrollBox: TTyScrollBox;
begin
  Result := TTyScrollBox.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.SetBounds(0, 0, 200, 120);
end;

procedure TTyScrollBarAutoHideTests.ScrollBoxBuildsItsBarsInsideInheritedCreate;
var
  sb: TTyScrollBox;
begin
  { 这一条钉的是 ScrollBox 与另外五个宿主都不一样的地方：它的两条条不是在
    构造函数**体**里建的，而是 inherited Create 设 Width/Height 时
    Resize -> UpdateScrollRange -> EnsureBars 顺手建出来的，也就是比构造函数
    体的第一句还早。EnsureBars 里那两行读 FScrollBarAutoHide 时，字段还只是
    RTL 的零填充；零恰好就是 sbahDefault，这套安排才成立。
    哪天这条不再成立——条改成更晚才建、或者默认值不再是第一个枚举成员——
    下面那句会红：它拿条上的值去比**宿主此刻的字段**。默认值一改，构造函数体里
    那句赋值就落在 EnsureBars 读零填充之后，条上留着旧的 sbahDefault、宿主字段
    已经是新默认值，两边对不上。

    拿写死的 sbahDefault 去比是守不住的：那正好就是零填充的值,读早了也照样相等。
    ScrollBoxDeclaredDefaultMatchesConstructed 也守不住 —— 它比的是声明的 default
    和宿主字段,那两个那时候一致,条上是什么它根本不看。 }
  sb := TTyScrollBox.Create(FForm);
  AssertTrue('构造函数一返回，两条条就该已经在了',
    (FindEmbeddedBar(sb, sbVertical) <> nil) and (FindEmbeddedBar(sb, sbHorizontal) <> nil));
  AssertEquals('而且它们拿到的是宿主此刻的值，不是一个读早了的零填充',
    Ord(sb.ScrollBarAutoHide), Ord(FindEmbeddedBar(sb, sbVertical).AutoHide));
end;

procedure TTyScrollBarAutoHideTests.ScrollBoxForwardsToItsEmbeddedBars;
var
  sb: TTyScrollBox;
begin
  sb := NewScrollBox;
  sb.ScrollBarAutoHide := sbahNever;
  CheckBothBarsGot(sb, sbahNever, 'ScrollBox');
end;

procedure TTyScrollBarAutoHideTests.ScrollBoxDeclaredDefaultMatchesConstructed;
begin
  CheckHostDeclaredDefault(NewScrollBox, 'ScrollBox');
end;

function TTyScrollBarAutoHideTests.NewTreeView: TTyTreeView;
begin
  Result := TTyTreeView.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.SetBounds(0, 0, 200, 120);
end;

procedure TTyScrollBarAutoHideTests.TreeViewForwardsToItsEmbeddedBars;
var
  tv: TTyTreeView;
begin
  { 两条在构造函数里就建好了，不用塞节点。 }
  tv := NewTreeView;
  tv.ScrollBarAutoHide := sbahNever;
  CheckBothBarsGot(tv, sbahNever, 'TreeView');
end;

procedure TTyScrollBarAutoHideTests.TreeViewDeclaredDefaultMatchesConstructed;
begin
  CheckHostDeclaredDefault(NewTreeView, 'TreeView');
end;

procedure TTyScrollBarAutoHideTests.ValueListEditorInheritsTheListBoxProperty;
var
  vle: TTyValueListEditor;
begin
  { TTyValueListEditor 是 **TTyListBox** 的后代——不是网格的,尽管它长得像属性
    表格、名字也像。所以它白拿这个属性和那两条惰性内嵌条,不用单独接线。
    这条测试就是「白拿」这句话的凭据,不然它只是一句假设。 }
  AssertTrue('TTyValueListEditor 必须是 TTyListBox 的后代',
    TTyValueListEditor.InheritsFrom(TTyListBox));
  vle := TTyValueListEditor.Create(FForm);
  vle.Parent := FForm;
  vle.Controller := FCtl;
  vle.SetBounds(0, 0, 200, 60);
  { 后代自己也要过 default 那一关:属性是继承来的,但 RTTI 按后代那个类查,
    而后代的构造函数有机会改掉字段却改不了声明。 }
  CheckHostDeclaredDefault(vle, 'ValueListEditor');
  vle.ScrollBarAutoHide := sbahAuto;
  AssertEquals('继承来的属性确实存下了', Ord(sbahAuto), Ord(vle.ScrollBarAutoHide));
end;

type
  { 名字 + 该报的延时。排成**现代/经典交替**不是为了好看:同类连着排的话,
    除了第一条,后面每一条的“期望值”跟上一条一模一样 —— 那些名字就算一个也没
    装上(拼错了、没注册),模型原封不动,断言照样绿。交替之后每一条都得
    真把模型从上一个值换到另一个值才能绿。 }
  TThemeAutoHideCase = record
    Name: string;
    Ms: Integer;
  end;

const
  { 写死 1200 而不是「>= 0」:「>= 0」连 0(停手即消失)都放行,而那是个能
    把现代皮肤毁掉的手滑值。 }
  CModernMs = 1200;
  { 左边一列是平台真用遮盖式滚动条的六个皮肤；右边那些不是「剩下的」,是挑出来
    钉住的——每一个都是有人会想当然地把它归进现代那半边的:
      win10  —— 平、方、Fluent-1 血统,但 Win32 桌面滚动条从不自动隐藏(只有 UWP 会)。
      office —— 桌面版 Office 的面孔,不是 Office web 的。
      breeze —— KDE Plasma 默认一直显示,遮盖式是逐应用可选项。
    把这三个写进表里,是为了让「故意不开」有个发声的地方:谁顺手把它们打开,
    这里红,而不是悄无声息地改掉一个发布皮肤的行为。 }
  CThemeAutoHide: array[0..11] of TThemeAutoHideCase = (
    (Name: 'win11';     Ms: CModernMs),
    (Name: 'classic';   Ms: TyScrollBarAutoHideOff),
    (Name: 'macos';     Ms: CModernMs),
    (Name: 'xp';        Ms: TyScrollBarAutoHideOff),
    (Name: 'fluent';    Ms: CModernMs),
    (Name: 'aero';      Ms: TyScrollBarAutoHideOff),
    (Name: 'material3'; Ms: CModernMs),
    (Name: 'win10';     Ms: TyScrollBarAutoHideOff),
    (Name: 'adwaita';   Ms: CModernMs),
    (Name: 'office';    Ms: TyScrollBarAutoHideOff),
    (Name: 'ubuntu';    Ms: CModernMs),
    (Name: 'breeze';    Ms: TyScrollBarAutoHideOff));

procedure TTyScrollBarAutoHideTests.ModernThemesHideClassicThemesDoNot;
var
  i: Integer;
begin
  { 这是整条链的唯一守卫:主题文件 -> gen-builtinthemes.ps1 -> BuiltinThemeData
    -> Metric。前面那批测试全都手写 CSS 喂 LoadThemeCss,一条都碰不到生成物——
    生成器忘了重跑、皮肤里那一行写错了名字,它们照样全绿,功能却在出厂主题上
    整个休眠。所以这里必须按名字装真皮肤。

    经典那半边同时还在验「没写 = 继承基础层」:经典皮肤一行都不写这个令牌,
    -1 是从 light.tycss 这一层透上来的。

    坐标系里有个坑得先拆掉:CModernMs 恰好等于
    TyScrollBarAutoHideFallbackMs。两条路能给出同一个 1200 —— 读到了皮肤的值,
    或者 AutoHide = sbahAuto 而主题根本没给值。所以先把属性钉在出厂的
    sbahDefault 上:那条回退臂根本进不去,1200 只能是皮肤给的。 }
  AssertEquals('得从出厂属性出发,否则 1200 说不清是皮肤给的还是回退给的',
    Ord(sbahDefault), Ord(FBar.AutoHide));
  TyRegisterBuiltinThemes;
  for i := 0 to High(CThemeAutoHide) do
  begin
    FCtl.ThemeName := CThemeAutoHide[i].Name;
    AssertEquals(CThemeAutoHide[i].Name + ' 的自动隐藏延时',
      CThemeAutoHide[i].Ms, FBar.EffectiveAutoHideMs);
  end;
end;

procedure TTyScrollBarAutoHideTests.AppWideOffSwitchIsTheControllerStyleOverride;
const
  COddMs = 777;   // 库里任何一处都没有这个数
begin
  { 文档 §7「一句话全库关掉」的凭据,也是这个令牌唯一碰得到**追加层**的测试。
    前面那一整批走的都是 LoadThemeCss —— 那是把主题层整个**替换**掉;而这条补丁走的
    是 controller.StyleOverride -> ReloadThemeLayer -> LoadFromCssAdditive -> FVars ->
    RebuildMergedVars -> Metric,另一条路,一条测试都没碰过。

    坐标系要先搭好,这里有两个「碰巧一致」的坑:
    - CModernMs 恰好等于 TyScrollBarAutoHideFallbackMs。先把属性钉在出厂的
      sbahDefault 上,回退臂进不去,1200 只能是皮肤给的。
    - light.tycss 的基础层写的就是 -1。直接验 -1 不够:补丁根本没生效、而主题层又碰巧
      被冲成空的话,透上来的还是 -1,断言照样绿。所以先用一个库里没有的 777 证明补丁
      真的一路走到了 Metric,再验文档给的那一句。 }
  AssertEquals('得从出厂属性出发,否则 1200 说不清是皮肤给的还是回退给的',
    Ord(sbahDefault), Ord(FBar.AutoHide));
  TyRegisterBuiltinThemes;
  FCtl.ThemeName := 'win11';
  AssertEquals('先确认皮肤这一层是开着的', CModernMs, FBar.EffectiveAutoHideMs);

  FCtl.StyleOverride := Format(':root { --scrollbar-auto-hide: %d; }', [COddMs]);
  AssertEquals('补丁里的 :root 令牌该压过皮肤', COddMs, FBar.EffectiveAutoHideMs);

  FCtl.StyleOverride := ':root { --scrollbar-auto-hide: -1; }';
  AssertEquals('文档给的那一句该把开着的皮肤一起关掉',
    TyScrollBarAutoHideOff, FBar.EffectiveAutoHideMs);

  { 另一半:文档说不管用的两种写法也得真的不管用,否则文档和测试各说各话。 }
  FCtl.StyleOverride := 'TyScrollBar { --scrollbar-auto-hide: -1; }';
  AssertEquals('写进类型规则只是给那条规则挂了个没人读的声明,进不了变量表',
    CModernMs, FBar.EffectiveAutoHideMs);

  FCtl.StyleOverride := '';
  FBar.StyleOverride := ':root { --scrollbar-auto-hide: -1; }';
  AssertEquals('控件上的同名属性只收裸声明,带选择器的整块解析不过、被当空补丁扔掉',
    CModernMs, FBar.EffectiveAutoHideMs);
end;

initialization
  RegisterTest(TTyScrollBarAutoHideTests);
end.
