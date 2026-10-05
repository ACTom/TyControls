unit test.toolwindow.disabled;
{$mode objfpc}{$H+}

{ 禁用的工具窗口(spec §3.7,E 期):图标 / 标签认窗口自己的 Enabled、当前页被禁用时侧栏图标仍能
  收起、底栏让出标签行(布局、绘制、输入)。夹具在 test.toolwindow.bottom(底栏)—— 侧栏的用例
  用同一个夹具里的 FBar(默认左栏)。 }

interface

uses
  Classes, SysUtils, Types, TypInfo, Controls, Forms, Graphics, Menus, LCLType, LCLProc, LMessages,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.ToolWindows,
  tyControls.ToolWindows.Layout, tyControls.StrConsts, tyControls.Painter,
  tyControls.Icons.Lucide, test.toolwindow.window,
  test.toolwindow.bar, test.toolwindow.bottom;

type
  TTyToolWindowDisabledTests = class(TTyToolWindowBottomFixture)
  private
    { 侧栏用例:Explorer / Search / Git,当前页 Explorer,图标都是 house,假时钟。 }
    FSide: array of TProbeWindow;
    procedure NewSideBar;
    { 推时钟躲开防抖,再在第 AIndex 格图标上按下、松开。 }
    procedure ClickSide(AIndex: Integer);
    { 在第 AIndex 格图标上按下,往右挪过拖动阈值(不松开)。 }
    procedure PressAndPull(AIndex: Integer);
    { 在内容区里松开:不是落点(拖着的就取消),也不在任何图标上(武装着的不算点击)。 }
    procedure ReleaseAway;
  published
    { --- Task 1:图标 / 标签认窗口的 Enabled --- }
    procedure TestADisabledIconDoesNotSwitch;
    procedure TestADisabledIconIsNotADragHandle;
    procedure TestADisabledIconTakesNoHover;
    procedure TestADisabledIconPaintsTheDisabledInk;
    procedure TestTheDisabledCurrentIconStillCollapsesAndExpands;
    procedure TestTheDisabledCurrentIconIsNotADragHandle;
    procedure TestOtherIconsStillSwitchAwayFromADisabledPage;
    procedure TestCodeStillActivatesADisabledWindow;
    procedure TestARightClickOnADisabledIconStillSetsContextWindow;
    procedure TestDisablingTheDraggedWindowCancelsTheDrag;
    procedure TestADisabledTabDoesNotSwitch;
    procedure TestADisabledTabPaintsTheDisabledInk;
    procedure TestADisabledTabTakesNoHover;
    procedure TestTheOverflowItemOfADisabledWindowIsGreyAndInert;
    procedure TestDisablingAWindowRepaintsTheSideBar;
    procedure TestDisablingAnotherPageRepaintsTheActivePage;
    { --- Task 2:让出标签行 —— 布局与绘制(spec §3.7 机制 ②) --- }
    procedure TestADisabledPageYieldsTheTabRowToTheBar;
    procedure TestTheYieldedPageKeepsNoHeaderRowAndTheBodyStays;
    procedure TestTheYieldedRowKeepsEveryTabInPlace;
    procedure TestReEnablingTakesTheRowBack;
    procedure TestDisablingTheCurrentPageAsksForARelayout;
    procedure TestSwitchingPagesYieldsAndTakesBack;
    procedure TestACollapsedBarYieldsNothing;
    procedure TestADesignTimeBarYieldsNothing;
    procedure TestASideBarYieldsNothing;
    procedure TestTheBarPaintsTheYieldedRowAtFullInk;
    procedure TestRenamingAPageRepaintsTheYieldedRow;
    procedure TestPartAtFindsTabsInTheYieldedRow;
    procedure TestOverflowWindowsSurviveTheYield;
    procedure TestTheOverflowMenuAnchorsOnTheYieldedRow;
    { --- Task 3:让出标签行 —— 输入(spec §3.7、§6.8 E 期补) --- }
    procedure TestClickingATabInTheYieldedRowSwitches;
    procedure TestAReleaseOnAnotherTabInTheYieldedRowIsNotAClick;
    procedure TestTheYieldedButtonsCollapseAndMaximize;
    procedure TestTheYieldedOverflowOpensTheMenu;
    procedure TestDraggingATabInTheYieldedRowReorders;
    procedure TestTheInsertLinePaintsInTheYieldedRow;
    procedure TestAPressedTabInTheYieldedRowPaintsPressed;
    procedure TestTheYieldedRowMapsBarCoordinatesIntoTheRow;
    procedure TestHoverOnTheYieldedRowAndLeave;
    procedure TestHintsOnTheYieldedRow;
    procedure TestRightClicksOnTheYieldedRow;
    procedure TestTheWheelIsSwallowedOnTheYieldedRow;
    procedure TestAClickOnTheDisabledPageBodyDoesNotClickTheBar;
    procedure TestTheRowGoesBackToThePageAfterSwitchingAway;
    { 标签行换了宿主(代码切到启用的页、禁用的页被启用):栏上武装着的标签行手势作废,
      之后栏上的松开不算点击(计划开工前问题 17)。 }
    procedure TestSwitchingInCodeCancelsAPressOnTheYieldedRow;
    procedure TestReEnablingCancelsAPressOnTheYieldedRow;
    { --- 整体审查(E 期) --- }
    { 按在禁用的当前页图标上(合法:点它收起),松开之前代码把当前页换走:松开在原图标上不许切回
      那个禁用窗口(StripClick 的那道闸,审查 1.1b)。 }
    procedure TestACodeSwitchBeforeTheReleaseDoesNotSwitchBackToADisabledWindow;
    { .lfm 里流进来一个禁用的当前页:加载完就让出;之后启用,栏请重排、页回到原边界。 }
    procedure TestAStreamedDisabledCurrentPageYieldsAndTakesBack;
    { 让出行的空白、禁用页的边界里:都不起栏的 LCL 自动拖动(同吞点击的那一处)。 }
    procedure TestTheYieldedRowAndTheDisabledPageStartNoLclDrag;
    { 指针在禁用的当前页上:不显示栏自己的 Hint。 }
    procedure TestTheDisabledPageShowsNotTheBarsHint;
    { 标签宽按静止、选中、禁用三种样子取最宽:禁用 / 启用不跳,禁用态更宽的字也放得下。 }
    procedure TestTabsAreMeasuredAtTheWidestOfRestingSelectedAndDisabled;
    { 拉宽边吸附着(按收起排布,高 0):不让出标签行 —— HostsTabRow / TabRowHost 一个口径;拖回来
      又让出。 }
    procedure TestASnappedEdgeYieldsNoRowAndDraggingBackYieldsAgain;
  private
    { 栏坐标上按下、Click、松开(LCL 的顺序)。 }
    procedure ClickRow(const APos: TPoint);
    { 让出行里一个不在任何部件上的点(标签后面、操作区前面),栏坐标。 }
    function RowBlank: TPoint;
    { 让栏回答 APos(栏坐标)上的 CM_HINTSHOW。 }
    function AskBarHint(const APos: TPoint; out AInfo: THintInfo): PtrInt;
  private
    { Task 2 / 3 的底栏:Problems / Output / Terminal,当前页 Output;Output 的操作区 30×20、
      Terminal 的 30×40(统一行高高过 token,地雷 3 的变异才分得开)。记下禁用前的行高、
      正文在栏里的顶、当前页几何、内容区;然后禁用 Output、排一遍。 }
    FH0, FT0: Integer;
    FG0: TTyToolWindowHeaderGeom;
    FContent0: TRect;
    procedure NewYieldingBar(ADisable: Boolean = True);
    { 让出行里窗口 AIndex 的标签中心,栏坐标。 }
    function RowTabCentre(AIndex: Integer): TPoint;
    { 让出行里某个部件矩形(行内坐标)换成栏坐标。 }
    function RowToBar(const ARect: TRect): TRect;
  end;

implementation

type
  { 流式化的根,和流进来的栏(数「对齐引擎被请了几次」、自己请一遍对齐 —— 同 TBarAccess,
    那个名字别的单元也有,不拿它注册)。 }
  TDisabledHostForm = class(TForm)
  end;
  TYieldStreamBar = class(TTyToolWindowBar)
  public
    AlignCount: Integer;
    procedure AdjustSize; override;
    procedure CallAlignControls;
    procedure CallMouseDown(X, Y: Integer);
  end;

procedure TYieldStreamBar.AdjustSize;
begin
  Inc(AlignCount);
  inherited AdjustSize;
end;

procedure TYieldStreamBar.CallMouseDown(X, Y: Integer);
begin
  MouseDown(mbLeft, [ssLeft], X, Y);
end;

procedure TYieldStreamBar.CallAlignControls;
var
  r: TRect;
begin
  r := ClientRect;
  AlignControls(nil, r);
end;

const
  { CSS #00FF00:基础主题的 :disabled 取 --muted(同 TestADisabledParentGreysTheTabRow 的理由:
    绿在品红底上的混合线跟蓝、黄两条都不相交)。 }
  DisInk = TColor($00FF00);
  MutedGreen = ' :root { --muted: #00FF00; }';

procedure TTyToolWindowDisabledTests.NewSideBar;
const
  Names: array[0..2] of string = ('Explorer', 'Search', 'Git');
var
  i: Integer;
begin
  FBar.Images := NewHouseList;
  FSide := nil;
  SetLength(FSide, 3);
  for i := 0 to 2 do
  begin
    FSide[i] := NewWindow;
    FSide[i].Caption := Names[i];
    FSide[i].ImageName := 'house';
  end;
  FBar.ActiveWindow := FSide[0];
  FBar.FakeClock := True;
  FBar.Clock := 100000;
  FBar.OnChange := @HandleChange;
  ResetCounts;
end;

procedure TTyToolWindowDisabledTests.ClickSide(AIndex: Integer);
begin
  FBar.Clock := FBar.Clock + 1000;
  ClickIcon(AIndex);
end;

procedure TTyToolWindowDisabledTests.ReleaseAway;
begin
  FBar.CallMouseUp(FBar.ClientWidth - 10, FBar.ClientHeight - 10);
end;

procedure TTyToolWindowDisabledTests.PressAndPull(AIndex: Integer);
var
  p: TPoint;
begin
  FBar.Clock := FBar.Clock + 1000;
  p := FBar.StripItemRect(AIndex).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseMove(p.X + TyToolWindowDragThreshold(96) + 4, p.Y);
end;

{ --- Task 1 --------------------------------------------------------------------- }

procedure TTyToolWindowDisabledTests.TestADisabledIconDoesNotSwitch;
begin
  NewSideBar;
  FSide[1].Enabled := False;
  ClickSide(1);
  AssertSame('禁用窗口的图标:点了不切', FSide[0], FBar.ActiveWindow);
  AssertEquals('没有 OnChange', 0, FChanges);
  AssertFalse('也没收起', FBar.Collapsed);
  ClickSide(2);
  AssertSame('对照:启用的图标照常切', FSide[2], FBar.ActiveWindow);
end;

procedure TTyToolWindowDisabledTests.TestADisabledIconIsNotADragHandle;
begin
  NewSideBar;
  PressAndPull(1);
  AssertTrue('对照:启用时拖得起来', FBar.IsDraggingForTest);
  ReleaseAway;
  AssertSame('前提:对照那一次没调顺序', FSide[1], FBar.Windows[1]);
  FSide[1].Enabled := False;
  FBar.Clock := FBar.Clock + 1000;
  FBar.CallMouseDown(FBar.StripItemRect(1).CenterPoint.X, FBar.StripItemRect(1).CenterPoint.Y);
  AssertEquals('禁用窗口的图标:按下只吞,不武装', Ord(twgsIdle), Ord(FBar.GestureStateForTest));
  ReleaseAway;
  PressAndPull(1);
  AssertFalse('禁用窗口的图标不是拖动把手', FBar.IsDraggingForTest);
  ReleaseAway;
end;

procedure TTyToolWindowDisabledTests.TestADisabledIconTakesNoHover;
var
  p: TPoint;
begin
  NewSideBar;
  FSide[1].Enabled := False;
  p := FBar.StripItemRect(2).CenterPoint;
  FBar.CallMouseMove(p.X, p.Y, []);
  AssertEquals('对照:启用的图标有悬停', 2, FBar.StripHover);
  p := FBar.StripItemRect(1).CenterPoint;
  FBar.CallMouseMove(p.X, p.Y, []);
  AssertTrue('禁用窗口的图标不接悬停', FBar.StripHover <> 1);
end;

procedure TTyToolWindowDisabledTests.TestADisabledIconPaintsTheDisabledInk;
var
  bmp: TBitmap;
begin
  FCtl.StyleOverride := StripTheme + MutedGreen;
  NewSideBar;
  FSide[1].Enabled := False;
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, FBar.StripItemRect(1), Wipe);
  try
    AssertTrue('Search:禁用墨色', CountInk(bmp, Ground, DisInk) > 0);
    AssertEquals('Search:没有静止墨', 0, CountInk(bmp, Ground, RestInk));
  finally
    bmp.Free;
  end;
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, FBar.StripItemRect(2), Wipe);
  try
    AssertTrue('Git:静止墨', CountInk(bmp, Ground, RestInk) > 0);
    { 静止墨的抗锯齿边缘极淡的几个像素会落进绿那条混合线的容差里(同 TestADisabledBarGreysItsIcons
      的说明):按比例比,不钉 0。 }
    AssertTrue('Git:没有禁用墨', CountInk(bmp, Ground, DisInk) < CountInk(bmp, Ground, RestInk) div 4);
  finally
    bmp.Free;
  end;
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, FBar.StripItemRect(0), Wipe);
  try
    AssertTrue('Explorer(当前页):选中墨', CountInk(bmp, Ground, SelInk) > 0);
    AssertEquals('Explorer:没有禁用墨', 0, CountInk(bmp, Ground, DisInk));
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowDisabledTests.TestTheDisabledCurrentIconStillCollapsesAndExpands;
begin
  NewSideBar;
  FSide[0].Enabled := False;
  ClickSide(0);
  AssertTrue('禁用的当前页:点它的图标照样收起(spec §3.7)', FBar.Collapsed);
  ClickSide(0);
  AssertFalse('再点展开', FBar.Collapsed);
  AssertSame('当前页没变', FSide[0], FBar.ActiveWindow);
end;

procedure TTyToolWindowDisabledTests.TestTheDisabledCurrentIconIsNotADragHandle;
begin
  NewSideBar;
  FSide[0].Enabled := False;
  PressAndPull(0);
  AssertFalse('禁用的当前页能点、不能拖', FBar.IsDraggingForTest);
  ReleaseAway;
end;

procedure TTyToolWindowDisabledTests.TestOtherIconsStillSwitchAwayFromADisabledPage;
begin
  NewSideBar;
  FSide[0].Enabled := False;
  ClickSide(1);
  AssertSame('当前页禁用时别的图标照常切', FSide[1], FBar.ActiveWindow);
  AssertEquals('发了 OnChange', 1, FChanges);
end;

procedure TTyToolWindowDisabledTests.TestCodeStillActivatesADisabledWindow;
begin
  NewSideBar;
  FSide[1].Enabled := False;
  FBar.ActiveWindow := FSide[1];
  AssertSame('代码照常切到禁用窗口(spec §3.3)', FSide[1], FBar.ActiveWindow);
  AssertTrue('它显示出来了', FSide[1].Visible);
end;

procedure TTyToolWindowDisabledTests.TestARightClickOnADisabledIconStillSetsContextWindow;
var
  handled: Boolean;
begin
  NewSideBar;
  FSide[1].Enabled := False;
  handled := False;
  FBar.CallDoContextPopup(FBar.StripItemRect(1).CenterPoint, handled);
  AssertSame('右键照常设 ContextWindow(spec §3.7)', FSide[1], FBar.ContextWindow);
  AssertFalse('栏不替应用吞掉(菜单照弹)', handled);
end;

procedure TTyToolWindowDisabledTests.TestDisablingTheDraggedWindowCancelsTheDrag;
var
  p: TPoint;
begin
  NewSideBar;
  PressAndPull(1);
  AssertTrue('前提:在拖 Search', FBar.IsDraggingForTest);
  FSide[1].Enabled := False;
  AssertFalse('手势窗口被禁用:取消', FBar.IsDraggingForTest);
  p := FBar.StripItemRect(2).CenterPoint;
  FBar.CallMouseMove(p.X, p.Y + 10);
  FBar.CallMouseUp(p.X, p.Y + 10);
  AssertSame('松开不调顺序', FSide[1], FBar.Windows[1]);
end;

procedure TTyToolWindowDisabledTests.TestADisabledTabDoesNotSwitch;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 0);
  FWins[1].Enabled := False;
  ClickAt(FWins[0], TabCentre(1));
  AssertSame('禁用窗口的标签:点了不切', FWins[0], FBar.ActiveWindow);
  ClickAt(FWins[0], TabCentre(2));
  AssertSame('对照:启用的标签照常切', FWins[2], FBar.ActiveWindow);
end;

procedure TTyToolWindowDisabledTests.TestADisabledTabPaintsTheDisabledInk;
var
  g: TTyToolWindowHeaderGeom;
  bmp: TBitmap;
  w: TProbeWindow;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 0);
  FCtl.StyleOverride := BottomTheme + MutedGreen;
  w := FWins[0];
  FWins[1].Enabled := False;
  g := ActiveGeom;
  bmp := RenderPage(w, w.ClientWidth, w.ClientHeight, 96);
  try
    AssertTrue('Output:禁用墨色', InkIn(bmp, TabRectOf(g, 1), DisInk) > 0);
    AssertEquals('Output:没有静止墨', 0, InkIn(bmp, TabRectOf(g, 1), RestInk));
    AssertTrue('Terminal:静止墨', InkIn(bmp, TabRectOf(g, 2), RestInk) > 0);
    AssertEquals('Terminal:没有禁用墨', 0, InkIn(bmp, TabRectOf(g, 2), DisInk));
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowDisabledTests.TestADisabledTabTakesNoHover;
var
  p: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 0);
  FWins[1].Enabled := False;
  p := TabCentre(2);
  FWins[0].CallMouseMove(p.X, p.Y);
  AssertEquals('对照:启用的标签有悬停', Ord(twbpItem), Ord(FBar.HeaderHoverPartForTest));
  AssertEquals('对照:是 Terminal', 2, FBar.HeaderHoverIndexForTest);
  p := TabCentre(1);
  FWins[0].CallMouseMove(p.X, p.Y);
  AssertFalse('禁用窗口的标签不接悬停',
    (FBar.HeaderHoverPartForTest = twbpItem) and (FBar.HeaderHoverIndexForTest = 1));
end;

procedure TTyToolWindowDisabledTests.TestTheOverflowItemOfADisabledWindowIsGreyAndInert;
var
  p: TPoint;
  i: Integer;
  item, other: TMenuItem;
  hidden: TTyToolWindowPlan;
  found: Boolean;
begin
  NewSideBar;
  { 两格半高:一个图标 + 溢出按钮,Search、Git 收进溢出(照 A 期溢出测试的造法)。 }
  FBar.Height := 2 * TyToolWindowStripItemSizeDef + TyToolWindowStripItemSizeDef div 2;
  hidden := FBar.OverflowWindows;
  found := False;
  for i := 0 to High(hidden) do
    if hidden[i] = 1 then found := True;
  AssertTrue('前提:Search 收进了溢出', found);
  FSide[1].Enabled := False;
  FBar.Clock := FBar.Clock + 1000;
  p := FBar.BarLayout.Overflow.CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseUp(p.X, p.Y);
  AssertNotNull('前提:建了溢出菜单', FBar.OverflowMenu);
  item := nil;
  other := nil;
  for i := 0 to FBar.OverflowMenu.Items.Count - 1 do
    if FBar.OverflowMenu.Items[i].Tag = PtrInt(FSide[1]) then item := FBar.OverflowMenu.Items[i]
    else if FBar.OverflowMenu.Items[i].Tag = PtrInt(FSide[2]) then other := FBar.OverflowMenu.Items[i];
  AssertNotNull('Search 在菜单里', item);
  AssertNotNull('Git 在菜单里', other);
  AssertFalse('禁用窗口那一项灰掉', item.Enabled);
  AssertTrue('对照:别的项不灰', other.Enabled);
  item.OnClick(item);
  AssertSame('直接调它的 OnClick 也不切', FSide[0], FBar.ActiveWindow);
end;

procedure TTyToolWindowDisabledTests.TestDisablingAWindowRepaintsTheSideBar;
var
  before: Integer;
begin
  NewSideBar;
  before := FBar.Invalidates;
  FSide[1].Enabled := False;
  AssertTrue('侧栏:窗口禁用了栏要重画', FBar.Invalidates > before);
end;

procedure TTyToolWindowDisabledTests.TestDisablingAnotherPageRepaintsTheActivePage;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 0);
  ArmActive(FWins[0]);
  FWins[1].Enabled := False;
  AssertTrue('底栏:别的页禁用了,当前页的标签行要重渲染',
    FWins[0].CacheWouldRender(FWins[0].ClientWidth, FWins[0].ClientHeight));
end;

{ --- Task 2 --------------------------------------------------------------------- }

procedure TTyToolWindowDisabledTests.NewYieldingBar(ADisable: Boolean);
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  AddActionsKid(FWins[1], 30, 20);
  AddActionsKid(FWins[2], 30, 40);
  Relayout;
  FH0 := FWins[1].HeaderHeightPx;
  AssertTrue('前提:统一行高高过 token', FH0 > TyToolWindowHeaderHeightDef);
  FT0 := FWins[1].Top + FWins[1].BodyRect.Top;
  FG0 := ActiveGeom;
  FContent0 := FBar.BarLayout.Content;
  if ADisable then
  begin
    FWins[1].Enabled := False;
    Relayout;
  end;
end;

function TTyToolWindowDisabledTests.RowToBar(const ARect: TRect): TRect;
var
  h: TTyToolWindowTabRowHost;
begin
  h := FBar.TabRowHost;
  AssertTrue('前提:标签行在栏上', h.Host = TWinControl(FBar));
  Result := ARect;
  Types.OffsetRect(Result, h.Row.Left, h.Row.Top);
end;

function TTyToolWindowDisabledTests.RowTabCentre(AIndex: Integer): TPoint;
begin
  Result := RowToBar(TabRectOf(FBar.TabRowHost.Geom, AIndex)).CenterPoint;
end;

procedure TTyToolWindowDisabledTests.TestADisabledPageYieldsTheTabRowToTheBar;
var
  L: TTyToolWindowBarLayout;
begin
  NewYieldingBar;
  AssertTrue('当前页禁用:栏让出标签行', FBar.HostsTabRow);
  L := FBar.BarLayout;
  AssertEquals('行高 = 禁用前的统一行高(含操作区,不只 token)', FH0, L.TabRow.Bottom - L.TabRow.Top);
  AssertEquals('行在内容区原来的顶上', FContent0.Top, L.TabRow.Top);
  AssertEquals('行横跨内容区', FContent0.Left, L.TabRow.Left);
  AssertEquals('行横跨内容区(右)', FContent0.Right, L.TabRow.Right);
  AssertEquals('内容区从行下面开始', L.TabRow.Bottom, L.Content.Top);
end;

procedure TTyToolWindowDisabledTests.TestTheYieldedPageKeepsNoHeaderRowAndTheBodyStays;
var
  w: TProbeWindow;
  act: TTyCustomToolWindowActions;
  body, a, x: TRect;
begin
  NewYieldingBar;
  w := FWins[1];
  AssertEquals('页不再留标题行', 0, w.HeaderHeightPx);
  AssertEquals('正文从页顶开始', 0, w.BodyRect.Top);
  AssertEquals('页在行下面', FBar.BarLayout.TabRow.Bottom, w.Top);
  AssertEquals('正文在栏里的位置不变(行高两边一个算法)', FT0, w.Top + w.BodyRect.Top);
  act := w.Actions;
  AssertNotNull('前提:页有操作区', act);
  body := w.BodyRect;
  a := act.BoundsRect;
  AssertTrue('操作区摆成空的,不压在正文上',
    (a.Bottom <= a.Top) or not Types.IntersectRect(x, a, body));
end;

procedure TTyToolWindowDisabledTests.TestTheYieldedRowKeepsEveryTabInPlace;
var
  h: TTyToolWindowTabRowHost;
  i: Integer;
begin
  NewYieldingBar;
  h := FBar.TabRowHost;
  AssertTrue('宿主是栏', h.Host = TWinControl(FBar));
  AssertTrue('行 = BarLayout.TabRow', EqualRect(FBar.BarLayout.TabRow, h.Row));
  AssertEquals('标签个数不变', Length(FG0.Tabs), Length(h.Geom.Tabs));
  for i := 0 to High(FG0.Tabs) do
  begin
    AssertEquals(Format('第 %d 个标签的窗口不变', [i]), FG0.Tabs[i].ItemIndex, h.Geom.Tabs[i].ItemIndex);
    AssertTrue(Format('第 %d 个标签的矩形不变(不重排)', [i]),
      EqualRect(FG0.Tabs[i].ItemRect, h.Geom.Tabs[i].ItemRect));
  end;
  AssertTrue('前提:操作区那一格不是空的', FG0.Actions.Right > FG0.Actions.Left);
  AssertEquals('操作区那一格照留', FG0.Actions.Right - FG0.Actions.Left,
    h.Geom.Actions.Right - h.Geom.Actions.Left);
end;

procedure TTyToolWindowDisabledTests.TestReEnablingTakesTheRowBack;
var
  L: TTyToolWindowBarLayout;
begin
  NewYieldingBar;
  FWins[1].Enabled := True;
  Relayout;
  AssertFalse('启用回来:不再让出', FBar.HostsTabRow);
  L := FBar.BarLayout;
  AssertTrue('TabRow 空', L.TabRow.Bottom <= L.TabRow.Top);
  AssertEquals('页的标题行回来了', FH0, FWins[1].HeaderHeightPx);
  AssertTrue('宿主回到当前页', FBar.TabRowHost.Host = TWinControl(FWins[1]));
end;

procedure TTyToolWindowDisabledTests.TestDisablingTheCurrentPageAsksForARelayout;
var
  inv: Integer;
begin
  NewYieldingBar(False);
  FBar.AlignCount := 0;
  FWins[1].AlignCount := 0;
  inv := FBar.Invalidates;
  FWins[1].Enabled := False;
  { 要的是栏重排:让出那一行改的是栏的 AdjustClientRect(当前页自己那一边的漂移检查只重排页)。 }
  AssertTrue('让出:栏被请了重排', FBar.AlignCount > 0);
  AssertTrue('栏重画', FBar.Invalidates > inv);
end;

procedure TTyToolWindowDisabledTests.TestSwitchingPagesYieldsAndTakesBack;
begin
  NewYieldingBar;
  FBar.AlignCount := 0;
  FBar.ActiveWindow := FWins[0];
  AssertFalse('切到启用的页:收回', FBar.HostsTabRow);
  AssertTrue('栏被请了重排', FBar.AlignCount > 0);
  FBar.ActiveWindow := FWins[1];
  AssertTrue('切回禁用的页:再让出', FBar.HostsTabRow);
end;

procedure TTyToolWindowDisabledTests.TestACollapsedBarYieldsNothing;
var
  L: TTyToolWindowBarLayout;
begin
  NewYieldingBar;
  FBar.Collapsed := True;
  AssertFalse('收起时不让出', FBar.HostsTabRow);
  L := FBar.BarLayout;
  AssertTrue('TabRow 空', L.TabRow.Bottom <= L.TabRow.Top);
  FBar.Collapsed := False;
  AssertTrue('展开回来再让出', FBar.HostsTabRow);
end;

procedure TTyToolWindowDisabledTests.TestADesignTimeBarYieldsNothing;
var
  b: TBarAccess;
  a, c: TProbeWindow;
begin
  b := NewDesignBar;
  b.Placement := twpBottom;
  b.Width := 600;
  a := NewWindowIn(b, FDesignOwner);
  c := NewWindowIn(b, FDesignOwner);
  b.ActiveWindow := a;
  AssertTrue('前提:设计期', csDesigning in a.ComponentState);
  AssertNotNull('前提:有第二个窗口', c);
  a.Enabled := False;
  AssertFalse('设计期不让出', b.HostsTabRow);
  AssertTrue('TabRow 空', b.BarLayout.TabRow.Bottom <= b.BarLayout.TabRow.Top);
end;

procedure TTyToolWindowDisabledTests.TestASideBarYieldsNothing;
var
  L: TTyToolWindowBarLayout;
begin
  NewSideBar;
  FSide[0].Enabled := False;
  AssertFalse('侧栏不让出', FBar.HostsTabRow);
  L := FBar.BarLayout;
  AssertTrue('TabRow 空', L.TabRow.Bottom <= L.TabRow.Top);
end;

procedure TTyToolWindowDisabledTests.TestTheBarPaintsTheYieldedRowAtFullInk;
var
  h: TTyToolWindowTabRowHost;
  bmp: TBitmap;
begin
  NewYieldingBar;
  { 页自己的 :disabled opacity 钉成 1:下面要看的是「页画没画标签行」,不是它有多淡。 }
  FCtl.StyleOverride := BottomTheme + MutedGreen + ' TyToolWindow:disabled { opacity: 1; }';
  h := FBar.TabRowHost;
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, h.Row, Wipe);
  try
    AssertTrue('Problems:静止墨', InkIn(bmp, TabRectOf(h.Geom, 0), RestInk) > 0);
    AssertTrue('Terminal:静止墨', InkIn(bmp, TabRectOf(h.Geom, 2), RestInk) > 0);
    AssertTrue('Output(禁用的当前页):禁用墨', InkIn(bmp, TabRectOf(h.Geom, 1), DisInk) > 0);
    AssertTrue('下划线是原色(栏没禁用,不淡)', ExactIn(bmp, TabRectOf(h.Geom, 1), clBlack) > 0);
    AssertTrue('最大化按钮是静止墨', InkIn(bmp, h.Geom.Maximize, RestInk) > 0);
    AssertEquals('最大化按钮没有禁用墨', 0, InkIn(bmp, h.Geom.Maximize, DisInk));
  finally
    bmp.Free;
  end;
  bmp := RenderPage(FWins[1], FWins[1].ClientWidth, FWins[1].ClientHeight, 96);
  try
    AssertEquals('页自己不画标签行:没有静止墨', 0,
      InkIn(bmp, Rect(0, 0, FWins[1].ClientWidth, FH0), RestInk));
    AssertEquals('页自己不画标签行:没有禁用墨', 0,
      InkIn(bmp, Rect(0, 0, FWins[1].ClientWidth, FH0), DisInk));
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowDisabledTests.TestRenamingAPageRepaintsTheYieldedRow;
var
  inv: Integer;
begin
  NewYieldingBar;
  inv := FBar.Invalidates;
  FWins[0].Caption := 'Problems and warnings';
  AssertTrue('让出期间标签行画在栏里:改标题要重画栏', FBar.Invalidates > inv);
end;

procedure TTyToolWindowDisabledTests.TestPartAtFindsTabsInTheYieldedRow;
var
  c: TPoint;
  idx: Integer;
begin
  NewYieldingBar;
  c := RowTabCentre(2);
  AssertEquals('栏坐标里认得出 Terminal 的标签', Ord(twbpItem), Ord(FBar.PartAt(c.X, c.Y, idx)));
  AssertEquals('序号 2', 2, idx);
  AssertSame('WindowAtPos 答 Terminal', FWins[2], FBar.WindowAtPos(c.X, c.Y));
  c := RowToBar(FBar.TabRowHost.Geom.Collapse).CenterPoint;
  AssertEquals('收起按钮', Ord(twbpCollapse), Ord(FBar.PartAt(c.X, c.Y, idx)));
end;

procedure TTyToolWindowDisabledTests.TestOverflowWindowsSurviveTheYield;
var
  before, after: TTyToolWindowPlan;
  i: Integer;
begin
  NewYieldingBar(False);
  FBar.Width := 220;
  Relayout;
  before := FBar.OverflowWindows;
  AssertTrue('前提:有收进溢出的', Length(before) > 0);
  FWins[1].Enabled := False;
  Relayout;
  after := FBar.OverflowWindows;
  AssertEquals('让出前后收进去的一样多', Length(before), Length(after));
  for i := 0 to High(before) do
    AssertEquals(Format('第 %d 个', [i]), before[i], after[i]);
end;

procedure TTyToolWindowDisabledTests.TestTheOverflowMenuAnchorsOnTheYieldedRow;
var
  host: TWinControl;
  pt: TPoint;
  al: TPopupAlignment;
  r: TRect;
begin
  NewYieldingBar(False);
  FBar.Width := 220;
  Relayout;
  FWins[1].Enabled := False;
  Relayout;
  r := RowToBar(FBar.TabRowHost.Geom.Overflow);
  AssertTrue('前提:有溢出按钮', r.Right > r.Left);
  host := FBar.OverflowMenuAnchorIn(pt, al);
  AssertTrue('挂在栏上', host = TWinControl(FBar));
  AssertEquals('锚在溢出按钮左沿', r.Left, pt.X);
  AssertEquals('从按钮底边往下开', r.Bottom, pt.Y);
end;

{ --- Task 3 --------------------------------------------------------------------- }

const
  { #FF7F00(TColor 是 $BBGGRR):插入线、按下态的哨兵。 }
  Sentinel = TColor($007FFF);

procedure TTyToolWindowDisabledTests.ClickRow(const APos: TPoint);
begin
  FBar.CallMouseDown(APos.X, APos.Y);
  FBar.CallClick;
  FBar.CallMouseUp(APos.X, APos.Y);
end;

function TTyToolWindowDisabledTests.RowBlank: TPoint;
var
  h: TTyToolWindowTabRowHost;
  i, x, idx: Integer;
begin
  h := FBar.TabRowHost;
  x := h.Geom.TabArea.Left;
  for i := 0 to High(h.Geom.Tabs) do
    if h.Geom.Tabs[i].ItemRect.Right > x then x := h.Geom.Tabs[i].ItemRect.Right;
  AssertTrue('前提:标签后面还有空白', h.Geom.TabArea.Right - x > 4);
  Result := Point(h.Row.Left + (x + h.Geom.TabArea.Right) div 2,
    h.Row.Top + (h.Row.Bottom - h.Row.Top) div 2);
  AssertEquals('前提:空白上没有部件', Ord(twbpNone), Ord(FBar.PartAt(Result.X, Result.Y, idx)));
end;

function TTyToolWindowDisabledTests.AskBarHint(const APos: TPoint; out AInfo: THintInfo): PtrInt;
begin
  FillChar(AInfo, SizeOf(AInfo), 0);
  AInfo.HintControl := FBar;
  AInfo.CursorPos := APos;
  AInfo.HintStr := '<untouched>';
  Result := FBar.Perform(CM_HINTSHOW, 0, PtrInt(@AInfo));
end;

procedure TTyToolWindowDisabledTests.TestClickingATabInTheYieldedRowSwitches;
begin
  NewYieldingBar;
  FBar.OnChange := @HandleChange;
  ResetCounts;
  ClickRow(RowTabCentre(2));
  AssertSame('点让出行里的 Terminal:切过去', FWins[2], FBar.ActiveWindow);
  AssertEquals('一次 OnChange', 1, FChanges);
end;

procedure TTyToolWindowDisabledTests.TestAReleaseOnAnotherTabInTheYieldedRowIsNotAClick;
var
  a, b: TPoint;
begin
  NewYieldingBar;
  a := RowTabCentre(2);
  b := RowTabCentre(0);
  FBar.CallMouseDown(a.X, a.Y);
  FBar.CallMouseUp(b.X, b.Y);
  AssertSame('按在 Terminal、松在 Problems:不切', FWins[1], FBar.ActiveWindow);
end;

procedure TTyToolWindowDisabledTests.TestTheYieldedButtonsCollapseAndMaximize;
begin
  NewYieldingBar;
  ClickRow(RowToBar(FBar.TabRowHost.Geom.Collapse).CenterPoint);
  AssertTrue('收起按钮:收起', FBar.Collapsed);
  FBar.Collapsed := False;
  Relayout;
  AssertTrue('前提:展开后又让出', FBar.HostsTabRow);
  ClickRow(RowToBar(FBar.TabRowHost.Geom.Maximize).CenterPoint);
  AssertTrue('最大化按钮:最大化', FBar.Maximized);
  Relayout;
  ClickRow(RowToBar(FBar.TabRowHost.Geom.Maximize).CenterPoint);
  AssertFalse('再点:还原', FBar.Maximized);
end;

procedure TTyToolWindowDisabledTests.TestTheYieldedOverflowOpensTheMenu;
begin
  NewYieldingBar(False);
  FBar.Width := 220;
  Relayout;
  FWins[1].Enabled := False;
  Relayout;
  AssertTrue('前提:有收进溢出的', Length(FBar.OverflowWindows) > 0);
  ClickRow(RowToBar(FBar.TabRowHost.Geom.Overflow).CenterPoint);
  AssertNotNull('溢出按钮:建了菜单', FBar.OverflowMenu);
  AssertEquals('菜单项 = 收进去的个数', Length(FBar.OverflowWindows), FBar.OverflowMenu.Items.Count);
end;

procedure TTyToolWindowDisabledTests.TestDraggingATabInTheYieldedRowReorders;
var
  p: TPoint;
  r: TRect;
begin
  NewYieldingBar;
  p := RowTabCentre(0);
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseMove(p.X + TyToolWindowDragThreshold(96) + 4, p.Y);
  AssertTrue('拖起来了', FBar.IsDraggingForTest);
  r := RowToBar(TabRectOf(FBar.TabRowHost.Geom, 2));
  p := Point(r.Right - 3, (r.Top + r.Bottom) div 2);
  FBar.CallMouseMove(p.X, p.Y);
  FBar.CallMouseUp(p.X, p.Y);
  AssertSame('第 0 个:Output', FWins[1], FBar.Windows[0]);
  AssertSame('第 1 个:Terminal', FWins[2], FBar.Windows[1]);
  AssertSame('第 2 个:Problems', FWins[0], FBar.Windows[2]);
  AssertSame('当前页仍是 Output', FWins[1], FBar.ActiveWindow);
end;

procedure TTyToolWindowDisabledTests.TestTheInsertLinePaintsInTheYieldedRow;
var
  p: TPoint;
  r: TRect;
  h: TTyToolWindowTabRowHost;
  bmp: TBitmap;
begin
  NewYieldingBar;
  FCtl.StyleOverride := BottomTheme + ' :root { --toolwindow-drop-color: #FF7F00; }';
  p := RowTabCentre(0);
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseMove(p.X + TyToolWindowDragThreshold(96) + 4, p.Y);
  r := RowToBar(TabRectOf(FBar.TabRowHost.Geom, 2));
  p := Point(r.Right - 3, (r.Top + r.Bottom) div 2);
  FBar.CallMouseMove(p.X, p.Y);
  AssertEquals('前提:落点是最后一个之后', 3, FBar.DropSlotForTest);
  h := FBar.TabRowHost;
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, h.Row, Wipe);
  try
    AssertTrue('插入线画在让出行里', ExactIn(bmp, Rect(0, 0, bmp.Width, bmp.Height), Sentinel) > 0);
  finally
    bmp.Free;
  end;
  FBar.CallMouseUp(p.X, p.Y);
end;

procedure TTyToolWindowDisabledTests.TestAPressedTabInTheYieldedRowPaintsPressed;
var
  p: TPoint;
  h: TTyToolWindowTabRowHost;
  bmp: TBitmap;
begin
  NewYieldingBar;
  { 基础主题的标签没有 :active 底色;这里给一个哨兵,看的是「按下态有没有传到标签」。 }
  FCtl.StyleOverride := BottomTheme + ' TyToolWindowTab:active { background: #FF7F00; }';
  p := RowTabCentre(2);
  FBar.CallMouseDown(p.X, p.Y);
  h := FBar.TabRowHost;
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, h.Row, Wipe);
  try
    AssertTrue('按下的 Terminal 画按下态', ExactIn(bmp, TabRectOf(h.Geom, 2), Sentinel) > 0);
    AssertEquals('Problems 没有', 0, ExactIn(bmp, TabRectOf(h.Geom, 0), Sentinel));
  finally
    bmp.Free;
  end;
  FBar.CallMouseUp(0, 0);
end;

procedure TTyToolWindowDisabledTests.TestTheYieldedRowMapsBarCoordinatesIntoTheRow;
var
  h: TTyToolWindowTabRowHost;
  r: TRect;
  rowH, yLocal: Integer;
begin
  NewYieldingBar;
  h := FBar.TabRowHost;
  rowH := h.Row.Bottom - h.Row.Top;
  AssertTrue('前提:行不在栏顶(前面有边缘区 / chrome)', h.Row.Top > 0);
  r := TabRectOf(h.Geom, 2);
  { 标签下半部:行内 y 大于「行高 − Row.Top」,直接拿栏坐标查行内几何就落到行外。 }
  yLocal := r.Bottom - 2;
  AssertTrue('前提:点够低', yLocal >= rowH - h.Row.Top);
  ClickRow(Point(h.Row.Left + (r.Left + r.Right) div 2, h.Row.Top + yLocal));
  AssertSame('按行内坐标命中 Terminal', FWins[2], FBar.ActiveWindow);
end;

procedure TTyToolWindowDisabledTests.TestHoverOnTheYieldedRowAndLeave;
var
  p: TPoint;
begin
  NewYieldingBar;
  p := RowTabCentre(0);
  FBar.CallMouseMove(p.X, p.Y, []);
  AssertEquals('悬停在 Problems 上', Ord(twbpItem), Ord(FBar.HeaderHoverPartForTest));
  AssertEquals('序号 0', 0, FBar.HeaderHoverIndexForTest);
  FBar.CallMouseLeave;
  AssertEquals('离开清掉', Ord(twbpNone), Ord(FBar.HeaderHoverPartForTest));
end;

procedure TTyToolWindowDisabledTests.TestHintsOnTheYieldedRow;
var
  info: THintInfo;
begin
  NewYieldingBar;
  FBar.Hint := 'bar hint';
  AssertEquals('标签上显示', 0, AskBarHint(RowTabCentre(2), info));
  AssertEquals('Terminal 的提示是 Caption', 'Terminal', info.HintStr);
  AskBarHint(RowToBar(FBar.TabRowHost.Geom.Maximize).CenterPoint, info);
  AssertEquals('最大化按钮', rsTyToolWindowMaximize, info.HintStr);
  AssertEquals('空白:不显示', 1, AskBarHint(RowBlank, info));
  AssertEquals('空白:不回落到栏自己的 Hint', '<untouched>', info.HintStr);
end;

procedure TTyToolWindowDisabledTests.TestRightClicksOnTheYieldedRow;
var
  handled: Boolean;
begin
  NewYieldingBar;
  handled := False;
  FBar.CallDoContextPopup(RowTabCentre(2), handled);
  AssertSame('标签上:ContextWindow = Terminal', FWins[2], FBar.ContextWindow);
  handled := False;
  FBar.CallDoContextPopup(RowBlank, handled);
  AssertTrue('行内空白:吞掉', handled);
  AssertNull('行内空白:没有 ContextWindow', FBar.ContextWindow);
  handled := False;
  FBar.CallDoContextPopup(FBar.BarLayout.Edge.CenterPoint, handled);
  AssertFalse('边缘区:不吞(冒泡到窗体)', handled);
end;

procedure TTyToolWindowDisabledTests.TestTheWheelIsSwallowedOnTheYieldedRow;
begin
  NewYieldingBar;
  AssertTrue('让出行上的滚轮吞掉', FBar.CallDoMouseWheel(RowTabCentre(0)));
end;

procedure TTyToolWindowDisabledTests.TestAClickOnTheDisabledPageBodyDoesNotClickTheBar;
var
  p: TPoint;
begin
  NewYieldingBar;
  FBar.OnClick := @HandleClick;
  FClicks := 0;
  p := FWins[1].BoundsRect.CenterPoint;
  ClickRow(p);
  AssertEquals('禁用页正文上的按下落到栏:栏的 OnClick 不响', 0, FClicks);
  FWins[1].Enabled := True;
  Relayout;
  p := FWins[1].BoundsRect.CenterPoint;
  ClickRow(p);
  AssertEquals('对照:页启用时同一处直接调栏,OnClick 照响', 1, FClicks);
end;

procedure TTyToolWindowDisabledTests.TestTheRowGoesBackToThePageAfterSwitchingAway;
begin
  NewYieldingBar;
  ClickRow(RowTabCentre(0));
  AssertSame('切到 Problems', FWins[0], FBar.ActiveWindow);
  AssertFalse('收回了', FBar.HostsTabRow);
  Relayout;
  ClickAt(FWins[0], TabCentre(2));
  AssertSame('页上的标签行照常:切到 Terminal', FWins[2], FBar.ActiveWindow);
end;

procedure TTyToolWindowDisabledTests.TestSwitchingInCodeCancelsAPressOnTheYieldedRow;
var
  p: TPoint;
begin
  NewYieldingBar;
  p := RowTabCentre(2);
  FBar.CallMouseDown(p.X, p.Y);
  AssertEquals('前提:武装着', Ord(twgsArmed), Ord(FBar.GestureStateForTest));
  FBar.ActiveWindow := FWins[0];
  AssertFalse('前提:收回了', FBar.HostsTabRow);
  AssertEquals('标签行换了宿主:手势作废', Ord(twgsIdle), Ord(FBar.GestureStateForTest));
  FBar.CallClick;
  FBar.CallMouseUp(p.X, p.Y);
  AssertSame('之后栏上的松开不算点击', FWins[0], FBar.ActiveWindow);
end;

procedure TTyToolWindowDisabledTests.TestReEnablingCancelsAPressOnTheYieldedRow;
var
  p: TPoint;
begin
  NewYieldingBar;
  p := RowTabCentre(2);
  FBar.CallMouseDown(p.X, p.Y);
  AssertEquals('前提:武装着', Ord(twgsArmed), Ord(FBar.GestureStateForTest));
  FWins[1].Enabled := True;
  AssertEquals('启用回来、标签行回到页上:手势作废', Ord(twgsIdle), Ord(FBar.GestureStateForTest));
  FBar.CallClick;
  FBar.CallMouseUp(p.X, p.Y);
  AssertSame('之后栏上的松开不算点击', FWins[1], FBar.ActiveWindow);
end;

{ --- 整体审查 --------------------------------------------------------------------- }

procedure TTyToolWindowDisabledTests.TestACodeSwitchBeforeTheReleaseDoesNotSwitchBackToADisabledWindow;
var
  p: TPoint;
begin
  NewSideBar;
  FSide[0].Enabled := False;
  FBar.Clock := FBar.Clock + 1000;
  p := FBar.StripItemRect(0).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  AssertEquals('前提:禁用的当前页的图标按下武装着(点它收起是合法的)', Ord(twgsArmed),
    Ord(FBar.GestureStateForTest));
  FBar.ActiveWindow := FSide[1];
  AssertSame('前提:代码换走了当前页', FSide[1], FBar.ActiveWindow);
  ResetCounts;
  p := FBar.StripItemRect(0).CenterPoint;
  FBar.CallClick;
  FBar.CallMouseUp(p.X, p.Y);
  AssertSame('在原图标上松开:不切回禁用窗口', FSide[1], FBar.ActiveWindow);
  AssertFalse('也不收起', FBar.Collapsed);
  AssertEquals('没有 OnChange', 0, FChanges);
end;

procedure TTyToolWindowDisabledTests.TestAStreamedDisabledCurrentPageYieldsAndTakesBack;
var
  src, dst: TForm;
  ms: TMemoryStream;
  bar: TYieldStreamBar;
  dbar: TYieldStreamBar;
  w1, w2, dw2: TTyToolWindow;
  L: TTyToolWindowBarLayout;
  content0: TRect;
  p: TPoint;
begin
  src := TDisabledHostForm.CreateNew(nil);
  src.Name := 'HostForm1';
  dst := TDisabledHostForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  try
    bar := TYieldStreamBar.Create(src);
    bar.Name := 'Bar';
    bar.Placement := twpBottom;
    bar.Parent := src;
    bar.Width := 600;
    w1 := TTyToolWindow.Create(src);
    w1.Name := 'W1';
    w1.Caption := 'Problems';
    w1.Parent := bar;
    w2 := TTyToolWindow.Create(src);
    w2.Name := 'W2';
    w2.Caption := 'Output';
    w2.Parent := bar;
    bar.ActiveWindow := w2;
    w2.Enabled := False;
    ms.WriteComponent(src);
    ms.Position := 0;
    ms.ReadComponent(dst);
    dbar := dst.FindComponent('Bar') as TYieldStreamBar;
    dw2 := dst.FindComponent('W2') as TTyToolWindow;
    AssertSame('前提:当前页读回来是 Output', dw2, dbar.ActiveWindow);
    AssertFalse('前提:它读回来是禁用的', dw2.Enabled);
    AssertTrue('加载完就让出标签行', dbar.HostsTabRow);
    AssertTrue('标签行在栏上', dbar.TabRowHost.Host = TWinControl(dbar));
    L := dbar.BarLayout;
    AssertTrue('让出的那一行有高', L.TabRow.Bottom > L.TabRow.Top);
    dbar.CallAlignControls;
    AssertEquals('页在让出行下面', L.TabRow.Bottom, dw2.Top);
    content0 := L.Content;
    content0.Top := L.TabRow.Top;          { 让出之前的内容区 }
    { 在让出行的 Problems 标签上按下:手势武装在栏上。启用之后标签行回到页上,栏得知道「宿主
      换了」、把它作废 —— 栏只拿「上一次按哪种样子排过」比,加载时没记下「让出着」的话,启用时
      它以为什么都没变。 }
    p := TabRectOf(dbar.TabRowHost.Geom, 0).CenterPoint;
    dbar.CallMouseDown(L.TabRow.Left + p.X, L.TabRow.Top + p.Y);
    AssertEquals('前提:让出行上的按下武装着', Ord(twgsArmed), Ord(dbar.GestureStateForTest));
    dbar.AlignCount := 0;
    dw2.Enabled := True;
    AssertEquals('启用:标签行换了宿主,栏上的手势作废(加载时记下了「让出着」)', Ord(twgsIdle),
      Ord(dbar.GestureStateForTest));
    AssertTrue('启用:栏被请了重排(让出行收回,内容区变了)', dbar.AlignCount > 0);
    AssertFalse('不再让出', dbar.HostsTabRow);
    L := dbar.BarLayout;
    AssertTrue('TabRow 空', L.TabRow.Bottom <= L.TabRow.Top);
    dbar.CallAlignControls;
    AssertEquals('页回到原来的边界:内容区顶', content0.Top, dw2.Top);
    AssertEquals('页回到原来的边界:内容区底', content0.Bottom, dw2.Top + dw2.Height);
  finally
    ms.Free;
    dst.Free;
    src.Free;
  end;
end;

procedure TTyToolWindowDisabledTests.TestTheYieldedRowAndTheDisabledPageStartNoLclDrag;
var
  p: TPoint;
begin
  NewYieldingBar;
  FBar.DragMode := dmAutomatic;
  FBar.FakePointer := True;
  FBar.FakePoint := RowBlank;
  FBar.AutoDragStarts := 0;
  FBar.CallBeginAutoDrag;
  AssertEquals('让出行的空白上不起 LCL 拖动', 0, FBar.AutoDragStarts);
  p := FWins[1].BoundsRect.CenterPoint;
  FBar.FakePoint := p;
  FBar.CallBeginAutoDrag;
  AssertEquals('禁用页的边界里(Win32 上按下落到栏)不起', 0, FBar.AutoDragStarts);
  FWins[1].Enabled := True;
  Relayout;
  FBar.FakePoint := FWins[1].BoundsRect.CenterPoint;
  FBar.CallBeginAutoDrag;
  AssertEquals('对照:页启用时同一处直接调栏,照常起', 1, FBar.AutoDragStarts);
end;

procedure TTyToolWindowDisabledTests.TestTheDisabledPageShowsNotTheBarsHint;
var
  info: THintInfo;
begin
  NewYieldingBar;
  FBar.Hint := 'bar hint';
  FBar.ShowHint := True;
  AssertEquals('禁用页的边界里:不显示', 1, AskBarHint(FWins[1].BoundsRect.CenterPoint, info));
  AssertEquals('不回落到栏自己的 Hint', '<untouched>', info.HintStr);
  FWins[1].Enabled := True;
  Relayout;
  AssertEquals('对照:页启用时同一处走继承(显示)', 0,
    AskBarHint(FWins[1].BoundsRect.CenterPoint, info));
end;

procedure TTyToolWindowDisabledTests.TestTabsAreMeasuredAtTheWidestOfRestingSelectedAndDisabled;
var
  S: TTyStyleSet;
  fs, tw, th, rw, pad, before: Integer;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  { 禁用态的字号远大于静止 / 选中态:按那两种量的话,禁用的标签画出来被截。 }
  FCtl.StyleOverride := BottomTheme + ' TyToolWindowTab:disabled { font-size: 30px; }';
  Relayout;
  S := FCtl.Model.ResolveStyle(TyToolWindowTabKey, '', [tysDisabled]);
  AssertTrue('前提:禁用态的字号由主题给', tpFontSize in S.Present);
  fs := S.FontSize;
  TyMeasureTextBlock('Problems', S.FontName, fs, S.FontWeight, 96, 0, 0, tw, th);
  rw := TyMeasureRenderedTextWidth('Problems', S.FontName, fs, S.FontWeight, 96);
  if rw > tw then tw := rw;
  pad := FCtl.Metric(TyToolWindowTabPadVar, TyToolWindowTabPadDef);
  before := TabRectOf(ActiveGeom, 0).Right - TabRectOf(ActiveGeom, 0).Left;
  AssertTrue(Format('Problems 的标签宽放得下禁用态的字(宽 %d,字 %d + 2 × %d)', [before, tw, pad]),
    before >= tw + 2 * pad);
  FWins[0].Enabled := False;
  Relayout;
  AssertEquals('禁用它:标签不跳', before,
    TabRectOf(ActiveGeom, 0).Right - TabRectOf(ActiveGeom, 0).Left);
end;

procedure TTyToolWindowDisabledTests.TestASnappedEdgeYieldsNoRowAndDraggingBackYieldsAgain;
var
  e, s, q: TPoint;
  h: TTyToolWindowTabRowHost;
begin
  NewYieldingBar;
  AssertTrue('前提:让出着', FBar.HostsTabRow);
  e := FBar.EdgeRect.CenterPoint;
  FBar.CallMouseDown(e.X, e.Y);
  AssertTrue('前提:拉宽中', FBar.IsEdgeDraggingForTest);
  { 底栏往下拉(向下为缩小),拉过 content-min 的一半:吸附。 }
  { 拉宽按屏幕坐标算位移(栏自己在挪):每一步把同一个屏幕点换回栏此刻的客户区坐标。 }
  s := FBar.ClientToScreen(e);
  q := FBar.ScreenToClient(Point(s.X, s.Y + FBar.Height));
  FBar.CallMouseMove(q.X, q.Y);
  AssertEquals('前提:吸附着,按收起排布(高 0)', 0, FBar.Height);
  AssertFalse('吸附着不让出(同收起)', FBar.HostsTabRow);
  h := FBar.TabRowHost;
  AssertTrue('TabRowHost 同一个口径:行不在栏上', h.Host <> TWinControl(FBar));
  q := FBar.ScreenToClient(s);
  FBar.CallMouseMove(q.X, q.Y);
  AssertTrue('拖回来:又让出', FBar.HostsTabRow);
  AssertTrue('标签行回到栏上', FBar.TabRowHost.Host = TWinControl(FBar));
  q := FBar.ScreenToClient(s);
  FBar.CallMouseUp(q.X, q.Y);
end;

initialization
  RegisterClasses([TDisabledHostForm, TYieldStreamBar]);
  RegisterTest(TTyToolWindowDisabledTests);
end.
