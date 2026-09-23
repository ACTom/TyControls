unit test.toolwindow.bottom;
{$mode objfpc}{$H+}

{ 底栏(spec §3.4 / §6.4 / §7):标题行输入的装配、统一行高、标签行绘制、最大化、跨类改 Parent、
  设计期。夹具在 test.toolwindow.bar(TTyToolWindowBarFixture)。 }

interface

uses
  Classes, SysUtils, Types, TypInfo, Controls, Forms, Graphics, Menus, LCLType, LCLProc, LMessages,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.ToolWindows,
  tyControls.ToolWindows.Layout,
  tyControls.Icons.Lucide, test.toolwindow.window,
  test.toolwindow.bar;

type
  TTyToolWindowBottomTests = class(TTyToolWindowBarFixture)
  protected
    FWins: array of TProbeWindow;
    { 一条宽 600 的底栏,按 ACaptions 建窗口(标题长短不一,地雷 12),AActive 是当前页。
      先设 Placement 再加窗口:运行时有窗口时侧 ↔ 底被忽略。最后请一遍对齐,窗口才有真实边界。 }
    procedure NewBottomBar(const ACaptions: array of string; AActive: Integer);
    { 栏和每个窗口各请一遍对齐引擎(无头不跑,见 headless-tests-never-run-lcl-align)。 }
    procedure Relayout;
    { 当前页此刻的标题行几何(窗口客户区坐标)。 }
    function ActiveGeom: TTyToolWindowHeaderGeom;
    function TabRectOf(const AGeom: TTyToolWindowHeaderGeom; AWindowIndex: Integer): TRect;
    { AWin 的操作区里放一个 AW×AH 的子控件(操作区没有就先建)。 }
    function AddActionsKid(AWin: TTyToolWindow; AW, AH: Integer): TBodyChild;
    { 当前页:对齐计数清零、绘制缓存填上一帧,之后看「有没有被请重排 / 丢缓存」。 }
    procedure ArmActive(AWin: TProbeWindow);
  published
    { Task 3:装配。 }
    procedure TestTheActionsSitInTheBottomRowBeforeTheButtons;
    procedure TestRenamingAnotherWindowWidensItsTab;
    procedure TestTheTabPadTokenReachesEveryTab;
    procedure TestTheButtonSizeTokenMovesTheButtons;
    procedure TestTheTabAreaMinTokenSqueezesTheActions;
    procedure TestAThemeChangeRemeasuresTheTabs;
    procedure TestADirectZOrderChangeReordersTheTabs;
    procedure TestTabsAreMeasuredAtTheWiderOfRestingAndSelected;
    procedure TestTheSeparatorSlotFollowsItsBorderWidth;
    procedure TestZoneAtInBarCoordinatesMapsThroughTheActivePage;
    { Task 4:统一行高(spec §3.4)。 }
    procedure TestEveryPageSharesTheTallestActionsRow;
    procedure TestATallChildOnAHiddenPageRelayoutsTheActivePageAtOnce;
    procedure TestAWindowJoiningCountsTowardsTheSharedHeight;
    procedure TestAConstraintsOnlyChangeReachesTheRow;
    procedure TestAThemeChangeStillRelayoutsABottomPage;
  end;

implementation

procedure TTyToolWindowBottomTests.NewBottomBar(const ACaptions: array of string;
  AActive: Integer);
var
  i: Integer;
begin
  FBar.Placement := twpBottom;
  FBar.Width := 600;
  FWins := nil;
  SetLength(FWins, Length(ACaptions));
  for i := 0 to High(ACaptions) do
  begin
    FWins[i] := NewWindow;
    FWins[i].Caption := ACaptions[i];
  end;
  if AActive >= 0 then FBar.ActiveWindow := FWins[AActive];
  Relayout;
end;

procedure TTyToolWindowBottomTests.Relayout;
var
  i: Integer;
begin
  FBar.CallAlignControls;
  for i := 0 to High(FWins) do
    if FWins[i].Parent = FBar then FWins[i].CallAlignControls;
end;

function TTyToolWindowBottomTests.ActiveGeom: TTyToolWindowHeaderGeom;
var
  w: TTyToolWindow;
begin
  w := FBar.ActiveWindow;
  AssertNotNull('前提:有当前页', w);
  Result := w.HeaderGeomAt(Rect(0, 0, w.ClientWidth, w.ClientHeight), w.Font.PixelsPerInch);
end;

function TTyToolWindowBottomTests.TabRectOf(const AGeom: TTyToolWindowHeaderGeom;
  AWindowIndex: Integer): TRect;
var
  i: Integer;
begin
  for i := 0 to High(AGeom.Tabs) do
    if AGeom.Tabs[i].ItemIndex = AWindowIndex then Exit(AGeom.Tabs[i].ItemRect);
  Fail(Format('窗口 %d 的标签没排上', [AWindowIndex]));
  Result := Rect(0, 0, 0, 0);
end;

function TTyToolWindowBottomTests.AddActionsKid(AWin: TTyToolWindow; AW, AH: Integer): TBodyChild;
var
  act: TTyToolWindowActions;
begin
  act := AWin.EnsureActions;
  Result := TBodyChild.Create(FForm);
  Result.SetBounds(0, 0, AW, AH);
  Result.Parent := act;
end;

procedure TTyToolWindowBottomTests.ArmActive(AWin: TProbeWindow);
begin
  AWin.AlignCount := 0;
  AWin.PrimeCache(AWin.ClientWidth, AWin.ClientHeight);
  AssertFalse('前提:缓存填上了', AWin.CacheWouldRender(AWin.ClientWidth, AWin.ClientHeight));
end;

{ --- Task 3 --------------------------------------------------------------------- }

procedure TTyToolWindowBottomTests.TestTheActionsSitInTheBottomRowBeforeTheButtons;
var
  act: TTyToolWindowActions;
  kid: TBodyChild;
  g: TTyToolWindowHeaderGeom;
  w: TProbeWindow;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  act := w.EnsureActions;
  kid := TBodyChild.Create(FForm);
  kid.SetBounds(0, 0, 40, 20);
  kid.Parent := act;
  Relayout;
  g := ActiveGeom;
  AssertEquals('前提:窗口有栏那么宽', 600, w.ClientWidth);
  AssertTrue('操作区摆在标题行几何给的位置', EqualRect(g.Actions, act.BoundsRect));
  { 尾端往前:pad 6、收起 22、gap 4、最大化 22、分隔线槽 2×4+1 —— 操作区右沿就在分隔线左沿,
    不是侧栏那样贴到行尾。 }
  AssertEquals('操作区右沿 = 行宽 − pad − 2 × 按钮 − gap − 分隔线槽', 600 - 6 - 22 - 4 - 22 - 9,
    act.Left + act.Width);
  AssertEquals('操作区紧挨分隔线', g.Separator.Left, act.Left + act.Width);
  AssertTrue('标签区在操作区左边', g.TabArea.Right <= act.Left);
end;

procedure TTyToolWindowBottomTests.TestRenamingAnotherWindowWidensItsTab;
var
  before, after: TTyToolWindowHeaderGeom;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  before := ActiveGeom;
  FWins[0].Caption := 'Problems and warnings';
  after := ActiveGeom;
  AssertTrue('改了标题的那个标签变宽',
    TabRectOf(after, 0).Width > TabRectOf(before, 0).Width);
  AssertEquals('它后面的标签跟着右移',
    TabRectOf(before, 1).Left + TabRectOf(after, 0).Width - TabRectOf(before, 0).Width,
    TabRectOf(after, 1).Left);
end;

procedure TTyToolWindowBottomTests.TestTheTabPadTokenReachesEveryTab;
var
  before, after: TTyToolWindowHeaderGeom;
  i: Integer;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  before := ActiveGeom;
  FCtl.StyleOverride := ':root { --toolwindow-tab-pad: 14px; }';
  after := ActiveGeom;
  for i := 0 to 2 do
    AssertEquals(Format('标签 %d 两侧各多 4', [i]), TabRectOf(before, i).Width + 8,
      TabRectOf(after, i).Width);
end;

procedure TTyToolWindowBottomTests.TestTheButtonSizeTokenMovesTheButtons;
var
  before, after: TTyToolWindowHeaderGeom;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  before := ActiveGeom;
  FCtl.StyleOverride := ':root { --toolwindow-button-size: 30px; }';
  after := ActiveGeom;
  AssertEquals('收起按钮宽 30', 30, after.Collapse.Width);
  AssertEquals('收起左沿左移 8', before.Collapse.Left - 8, after.Collapse.Left);
  AssertEquals('最大化再左移 8', before.Maximize.Left - 16, after.Maximize.Left);
end;

procedure TTyToolWindowBottomTests.TestTheTabAreaMinTokenSqueezesTheActions;
var
  act: TTyToolWindowActions;
  kid: TBodyChild;
  before, after: TTyToolWindowHeaderGeom;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  act := FWins[1].EnsureActions;
  kid := TBodyChild.Create(FForm);
  kid.SetBounds(0, 0, 200, 20);
  kid.Parent := act;
  before := ActiveGeom;
  AssertEquals('前提:操作区保宽(200 + 2 × pad)', 212, before.Actions.Width);
  FCtl.StyleOverride := ':root { --toolwindow-tab-area-min: 400px; }';
  after := ActiveGeom;
  AssertEquals('标签区停在新的下限', 400, after.TabArea.Width);
  AssertEquals('操作区让出来的就是那一截', 600 - 6 - 22 - 4 - 22 - 9 - 6 - 400,
    after.Actions.Width);
end;

procedure TTyToolWindowBottomTests.TestAThemeChangeRemeasuresTheTabs;
var
  before, after: TTyToolWindowHeaderGeom;
  i: Integer;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  before := ActiveGeom;
  { 同一个 model、同一套窗口和标题:只有主题版本变了。 }
  FCtl.StyleOverride := 'TyToolWindowTab { font-size: 24px; }';
  after := ActiveGeom;
  for i := 0 to 2 do
    AssertTrue(Format('标签 %d 按新字号重量', [i]),
      TabRectOf(after, i).Width > TabRectOf(before, i).Width);
end;

procedure TTyToolWindowBottomTests.TestADirectZOrderChangeReordersTheTabs;
var
  before, after: TTyToolWindowHeaderGeom;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  before := ActiveGeom;
  { 设计器「移到最后」直接调它,不经 ReorderWindow、不通知谁。 }
  FBar.SetControlIndex(FWins[0], FBar.ControlCount - 1);
  after := ActiveGeom;
  AssertSame('前提:顺序真的变了', FWins[1], FBar.Windows[0]);
  AssertEquals('第一格现在是 Output 的宽', TabRectOf(before, 1).Width, TabRectOf(after, 0).Width);
  AssertEquals('最后一格现在是 Problems 的宽', TabRectOf(before, 0).Width,
    TabRectOf(after, 2).Width);
end;

procedure TTyToolWindowBottomTests.TestTabsAreMeasuredAtTheWiderOfRestingAndSelected;
var
  plain, bold, switched: TTyToolWindowHeaderGeom;
  i: Integer;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  plain := ActiveGeom;
  FCtl.StyleOverride := 'TyToolWindowTab:selected { font-weight: 700; }';
  bold := ActiveGeom;
  for i := 0 to 2 do
    AssertTrue(Format('标签 %d 按加粗的选中态量(否则当前页的标题被截)', [i]),
      TabRectOf(bold, i).Width > TabRectOf(plain, i).Width);
  FBar.ActiveWindow := FWins[2];
  Relayout;
  switched := ActiveGeom;
  for i := 0 to 2 do
    AssertEquals(Format('切页之后标签 %d 宽不变(整行不跳)', [i]), TabRectOf(bold, i).Width,
      TabRectOf(switched, i).Width);
end;

procedure TTyToolWindowBottomTests.TestTheSeparatorSlotFollowsItsBorderWidth;
var
  g: TTyToolWindowHeaderGeom;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  g := ActiveGeom;
  AssertEquals('基础主题:2 × gap + 1', 2 * 4 + 1, g.Separator.Width);
  { 覆写层里给这个键写基础规则,基础层的整条规则就被压掉 —— 线色要一起写。 }
  FCtl.StyleOverride := 'TyToolWindowSeparator { border-color: #000000; border-width: 3px; }';
  g := ActiveGeom;
  AssertEquals('线宽 3:2 × gap + 3', 2 * 4 + 3, g.Separator.Width);
  FCtl.StyleOverride := 'TyToolWindowSeparator { border-color: #000000; border-width: 0; }';
  g := ActiveGeom;
  AssertEquals('没有可见的线:只剩 2 × gap', 2 * 4, g.Separator.Width);
end;

procedure TTyToolWindowBottomTests.TestZoneAtInBarCoordinatesMapsThroughTheActivePage;
var
  w: TProbeWindow;
  g: TTyToolWindowHeaderGeom;
  tab, r: TRect;
  idx: Integer;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  AssertTrue('前提:当前页不在栏的原点(上面有边缘区)', w.Top > 0);
  g := ActiveGeom;
  tab := TabRectOf(g, 2);
  { 标签底部那一行:只在窗口坐标里落在标签上,栏坐标原样拿去算就落到行外。 }
  AssertEquals('栏坐标命中标签', Ord(twzTab),
    Ord(FBar.HeaderZoneAt(nil, tab.Left + 3 + w.Left, tab.Bottom - 1 + w.Top, idx, r)));
  AssertEquals('答窗口序号', 2, idx);
  AssertTrue('矩形回到栏坐标', EqualRect(r, Rect(tab.Left + w.Left, tab.Top + w.Top,
    tab.Right + w.Left, tab.Bottom + w.Top)));
  AssertEquals('窗口坐标照样命中', Ord(twzTab),
    Ord(FBar.HeaderZoneAt(w, tab.Left + 3, tab.Bottom - 1, idx, r)));
  AssertTrue('窗口坐标的矩形不偏移', EqualRect(r, tab));
end;

{ --- Task 4 --------------------------------------------------------------------- }

procedure TTyToolWindowBottomTests.TestEveryPageSharesTheTallestActionsRow;
var
  tall: Integer;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  AddActionsKid(FWins[0], 30, 20);
  AddActionsKid(FWins[1], 30, 40);
  tall := FWins[1].Actions.PreferredSizeAt(96).cy;
  AssertTrue('前提:高的那个操作区比 token 高', tall > TyToolWindowHeaderHeightDef);
  AssertTrue('前提:两个操作区不一样高', FWins[0].Actions.PreferredSizeAt(96).cy < tall);
  AssertEquals('当前页按最高的那个', tall, FWins[1].HeaderHeightPx);
  AssertEquals('矮的那一页也按最高的那个', tall, FWins[0].HeaderHeightPx);
  AssertEquals('没有操作区的那一页也一样', tall, FWins[2].HeaderHeightPx);
  FBar.ActiveWindow := FWins[0];
  Relayout;
  AssertEquals('切页之后标签行不跳', tall, FWins[0].HeaderRowRect.Height);
  FBar.ActiveWindow := FWins[1];
  Relayout;
  AssertEquals('切回来还是一样', tall, FWins[1].HeaderRowRect.Height);
end;

procedure TTyToolWindowBottomTests.TestATallChildOnAHiddenPageRelayoutsTheActivePageAtOnce;
var
  w: TProbeWindow;
  kid: TBodyChild;
  tall: Integer;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  FWins[0].EnsureActions;
  ArmActive(w);
  kid := AddActionsKid(FWins[0], 30, 60);
  AssertSame('没有切页', w, FBar.ActiveWindow);
  tall := FWins[0].Actions.PreferredSizeAt(96).cy;
  AssertEquals('当前页的标签行立刻变高', tall, w.HeaderRowRect.Height);
  AssertEquals('正文顶跟着下移', tall, w.BodyRect.Top);
  { 行高是现算的,上面两条不靠通知也绿;差别在当前页有没有被请重排、有没有丢缓存。 }
  AssertTrue('当前页被请了重排', w.AlignCount > 0);
  AssertTrue('当前页丢了缓存', w.CacheWouldRender(w.ClientWidth, w.ClientHeight));
  ArmActive(w);
  kid.Visible := False;
  AssertEquals('藏掉它:立刻变回 token 高', TyToolWindowHeaderHeightDef, w.HeaderRowRect.Height);
  AssertTrue('又被请了重排', w.AlignCount > 0);
  AssertTrue('又丢了缓存', w.CacheWouldRender(w.ClientWidth, w.ClientHeight));
end;

procedure TTyToolWindowBottomTests.TestAWindowJoiningCountsTowardsTheSharedHeight;
var
  a, b: TProbeWindow;
  kid: TBodyChild;
begin
  NewBottomBar(['Problems', 'Output'], 0);
  a := FWins[0];
  { 先经操作区那条路让栏记下「操作区那一项 = 0」:放一个子控件再藏掉。不然栏记着的还是
    出生时的「没用过」,之后任何一个值都算「变了」,注册时重不重算都看不出来。 }
  AddActionsKid(a, 30, 20).Visible := False;
  { 操作区在进栏之前就长高了:那时它没有栏可通知,只能靠注册时重算。 }
  b := TProbeWindow.Create(FForm);
  b.Caption := 'Terminal';
  { 钉成栏的 PPI:无头默认不是 96,进栏时字体跟着父控件换 PPI,操作区的首选尺寸跟着变、
    自己就通知了栏 —— 注册时有没有重算就看不出来了。 }
  b.Font.PixelsPerInch := 96;
  kid := AddActionsKid(b, 30, 60);
  b.Parent := FBar;
  FBar.ActiveWindow := a;
  Relayout;
  AssertEquals('前提:共用行高算上了新来的', b.Actions.PreferredSizeAt(96).cy, a.HeaderHeightPx);
  ArmActive(a);
  { 注册时没重算的话,栏记着的还是它来之前的高,这一下「没变」就不重排当前页。 }
  kid.Visible := False;
  AssertEquals('藏掉它:当前页变回 token 高', TyToolWindowHeaderHeightDef, a.HeaderHeightPx);
  AssertTrue('当前页被请了重排', a.AlignCount > 0);
end;

procedure TTyToolWindowBottomTests.TestAConstraintsOnlyChangeReachesTheRow;
var
  w: TProbeWindow;
  act: TTyToolWindowActions;
  kid: TBodyChild;
  pw, ph: Integer;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  kid := AddActionsKid(FWins[0], 30, 20);
  act := FWins[0].Actions;
  { LCL 的首选尺寸缓存先填上一次:只改 Constraints 时 LCL 不作废它。 }
  act.GetPreferredSize(pw, ph, True);
  AssertEquals('前提:LCL 量到的是 20 + 2 × pad', 32, ph);
  ArmActive(w);
  kid.Constraints.MinHeight := 50;
  AssertEquals('当前页的行高跟上下限', 62, w.HeaderHeightPx);
  AssertTrue('当前页被请了重排', w.AlignCount > 0);
  act.GetPreferredSize(pw, ph, True);
  AssertEquals('LCL 的 GetPreferredSize 也不端旧值', 62, ph);
end;

procedure TTyToolWindowBottomTests.TestAThemeChangeStillRelayoutsABottomPage;
var
  w: TProbeWindow;
  before, after, i: Integer;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  { 控制器按注册的倒序广播 Invalidate。夹具里栏先注册、窗口后注册,窗口总是先收到 ——
    栏替窗口读缓存的错在那个顺序下看不出来。把栏挪到窗口后面注册,它就先收到。真实窗体里
    谁先谁后看注册顺序,不能假定窗口总在前面。 }
  FBar.Controller := nil;
  for i := 0 to High(FWins) do
    FWins[i].Controller := FCtl;
  FBar.Controller := FCtl;
  before := w.HeaderHeightPx;
  w.AlignCount := 0;
  FCtl.StyleOverride := ':root { --toolwindow-header-height: 48px; }';
  after := w.HeaderHeightPx;
  AssertTrue('换主题后标签行变高', after > before);
  { 换主题只广播裸 Invalidate;窗口在自己的 Invalidate 里看 token 缓存察觉。栏替它先读了
    那个缓存,它就再也看不出来(谁先读就是谁的)。 }
  AssertTrue('底栏窗口照样被请重排', w.AlignCount > 0);
end;

initialization
  RegisterTest(TTyToolWindowBottomTests);
end.
