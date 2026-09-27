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
  end;

implementation

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
  FBar.CallMouseUp(0, 0);
  FSide[1].Enabled := False;
  PressAndPull(1);
  AssertFalse('禁用窗口的图标不是拖动把手', FBar.IsDraggingForTest);
  FBar.CallMouseUp(0, 0);
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
    AssertEquals('Git:没有禁用墨', 0, CountInk(bmp, Ground, DisInk));
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
  FBar.CallMouseUp(0, 0);
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

initialization
  RegisterTest(TTyToolWindowDisabledTests);
end.
