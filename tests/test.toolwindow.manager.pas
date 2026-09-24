unit test.toolwindow.manager;
{$mode objfpc}{$H+}

{ TTyToolWindowManager(spec §2 / §9.9 / §10.6):栏的注册与 Placement 冲突、CanMoveWindow、
  MoveWindow 的同步路径与事件、运行时直接改 Parent 的簿记。夹具在 test.toolwindow.bar
  (TTyToolWindowBarFixture)。无头的窗体永远不 Showing,MoveWindow 恒走同步那一支;排队、
  焦点、Showing 之后的时机在本单元的 TTyToolWindowManagerLiveTests(真句柄)。 }

interface

uses
  Classes, SysUtils, StrUtils, Types, TypInfo, Controls, Forms, Graphics, LCLType, LCLProc,
  LMessages, fpcunit, testregistry,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.Edit, tyControls.Button,
  tyControls.ToolWindows, tyControls.ToolWindows.Layout,
  test.toolwindow.window, test.toolwindow.bar;

type
  { manager 测试共用的夹具。本身没有 published 测试。 }
  TTyToolWindowManagerFixture = class(TTyToolWindowBarFixture)
  protected
    { 事件顺序:处理器往这里追加「名字;」,断言整串相等。 }
    FLog: string;
    { OnCanMoveWindow 的答案、被问了几次、最近一次的参数。 }
    FAllow: Boolean;
    FCanCalls: Integer;
    FCanWindow: TTyToolWindow;
    FCanTarget: TTyToolWindowBar;
    procedure SetUp; override;
    function NewManager: TTyToolWindowManager;
    { 窗体上一条 APlacement 的栏,按 ACaptions 建窗口(Name = 'W' + 标题,布局要用;标题长短
      不一);先设 Placement 再加窗口。两个以上窗口时当前页是第二个(不是第一个,B 期地雷 12)。
      栏的 Name 是 L / R / B 加序号(第一条不加),事件串里用它。 }
    function NewBarOn(APlacement: TTyToolWindowPlacement;
      const ACaptions: array of string): TBarAccess;
    procedure HandleCanMove(Sender: TObject; AWindow: TTyToolWindow;
      ATargetBar: TTyToolWindowBar; var AAllow: Boolean);
    { 栏事件记进 FLog:「栏名.change;」「栏名.expand;」「栏名.collapse;」。 }
    procedure LogBarChange(ASender: TObject);
    procedure LogBarExpand(ASender: TObject);
    procedure LogBarCollapse(ASender: TObject);
    procedure LogBarEvents(ABar: TTyToolWindowBar);
    { OnWindowMoved 记进 FLog:「moved(窗口名,源栏名,原序号);」。 }
    procedure LogMoved(Sender: TObject; AWindow: TTyToolWindow; ASourceBar: TTyToolWindowBar;
      AOldIndex: Integer);
    { 左栏 Explorer / Search / Git(当前页 Search),右栏 Outline(收起着),都注册在 AManager 上、
      栏事件和 OnWindowMoved 都记进 FLog。 }
    procedure NewLeftRight(out AManager: TTyToolWindowManager; out ALeft, ARight: TBarAccess);
    { 栏和它的每个窗口各请一遍对齐引擎(无头不跑,见 headless-tests-never-run-lcl-align)。 }
    procedure LayOut(ABar: TBarAccess);
  end;

  TTyToolWindowManagerTests = class(TTyToolWindowManagerFixture)
  published
    procedure TestOneBarPerPlacementIsUsable;
    procedure TestEveryBarSharingAPlacementIsUnusable;
    procedure TestLeavingTheManagerOrBeingFreedEndsAConflict;
    procedure TestFreeingTheManagerClearsEveryBar;
    procedure TestManagerIsAPublishedReference;
    { spec §9.9:CanMoveWindow / OnCanMoveWindow。 }
    procedure TestSideBarsCanTradeButNeverWithTheBottom;
    procedure TestDesignTimeSideToBottomIsRefusedToo;
    procedure TestTheSameBarIsAlwaysAllowedWithoutAsking;
    procedure TestBothBarsMustBeOnThisManager;
    procedure TestAConflictBlocksCrossMovesButNotTheSameBar;
    procedure TestABarOnAnotherFormIsRefused;
    procedure TestAnythingLoadingIsRefused;
    procedure TestTheEventCanVetoAndSeesTheArguments;
    procedure TestAskingChangesNothing;
    { spec §9.5 / §9.9 / §6.6:MoveWindow 的同步路径与事件。 }
    procedure TestMoveWindowActivatesAndExpandsTheTarget;
    procedure TestMoveWindowEventsFireInSpecOrder;
    procedure TestMoveWindowIndexClampsAndMinusOneMeansTheEnd;
    procedure TestMovingAnInactiveWindowLeavesTheSourceAlone;
    procedure TestMoveWindowWithinABarIsAReorder;
    procedure TestMoveWindowFromOnWindowMovedIsRefused;
    procedure TestMoveWindowFromOnCanMoveWindowIsRefused;
    procedure TestAVetoedMoveChangesNothing;
    procedure TestEveryReorderReportsOnWindowMoved;
    procedure TestDesignTimeMoveWindowIsSilent;
    { spec §3.2:运行时直接改 Parent 到同类栏的簿记。 }
    procedure TestADirectParentChangeBooksTheMove;
    procedure TestADirectParentChangeUnderOneManagerReportsTheMove;
    procedure TestBarsOnDifferentManagersReportNoMove;
    procedure TestAConflictingTargetStillTakesTheWindow;
    procedure TestMoveWindowReportsExactlyOnce;
    procedure TestDesignTimeAndLoadingParentChangesDoNotExpand;
    procedure TestOrphansAreNotBooked;
  private
    FReenterTarget: TTyToolWindowBar;
    FReenterWindow: TTyToolWindow;
    { -1 = 处理器没跑过;0 / 1 = 处理器里那一次 MoveWindow 的答案。 }
    FReentered: Integer;
    procedure MovedThenMoveAgain(Sender: TObject; AWindow: TTyToolWindow;
      ASourceBar: TTyToolWindowBar; AOldIndex: Integer);
    procedure CanMoveThenMove(Sender: TObject; AWindow: TTyToolWindow;
      ATargetBar: TTyToolWindowBar; var AAllow: Boolean);
  end;

  { 真句柄(焦点、Showing 之后的时机、队列)。夹具照 test.toolwindow.focus:本单元**自带**
    widgetset 惰性初始化开关;窗体摆到 (-4000, -4000) 再 Visible := True + HandleNeeded;
    Application.OnException 陷阱(消息里抛的异常不接住的话 LCL 弹模态框,runner 卡死)。
    左栏 Explorer / Search(当前页 Search,正文里一个编辑框),右栏 Outline,都注册在 FMgr 上。 }
  TTyToolWindowManagerLiveTests = class(TTestCase)
  private
    FForm: TForm;
    FCtl: TTyStyleController;
    FMgr: TTyToolWindowManager;
    FLeft, FRight: TTyToolWindowBar;
    FExplorer, FSearch, FOutline: TTyToolWindow;
    FEdit: TTyEdit;
    FPrevOnException: TExceptionEvent;
    FTrapped: string;
    FLog: string;
    FSeenBounds: TRect;
    { Search 操作区里的按钮;它的 OnClick 调 MoveWindow(Search, 右)。 }
    FBtn: TTyButton;
    FHandleKept: Boolean;
    FClickAnswer: Boolean;
    FCanCount: Integer;
    { OnCanMoveWindow 从第几次起答 False(0 = 一直放行)。 }
    FDenyFrom: Integer;
    procedure TrapException(Sender: TObject; E: Exception);
    procedure AssertNothingRaised(const AWhere: string);
    function NewWin(ABar: TTyToolWindowBar; const AName: string): TTyToolWindow;
    { 抽消息(含 Application 的异步队列)。 }
    procedure Pump(AMs: Integer = 100);
    procedure RightChangeSeesBounds(Sender: TObject);
    procedure LogChange(Sender: TObject);
    procedure LogExpand(Sender: TObject);
    procedure LogCollapse(Sender: TObject);
    procedure LogMoved(Sender: TObject; AWindow: TTyToolWindow; ASourceBar: TTyToolWindowBar;
      AOldIndex: Integer);
    procedure CountCan(Sender: TObject; AWindow: TTyToolWindow; ATargetBar: TTyToolWindowBar;
      var AAllow: Boolean);
    procedure BtnMovesSearch(Sender: TObject);
    { 异步队列只跑一轮(见实现处)。 }
    procedure RunAsyncOnce;
    { 真实的按下 / 松开消息点一下 AControl 的中心。 }
    procedure ClickReal(AControl: TWinControl);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    { spec §3.2:直接改 Parent 永远同步,窗体可见也一样。 }
    procedure TestADirectParentChangeKeepsTheFocus;
    procedure TestBarEventsSeeTheWindowAlreadyInPlace;
    { spec §9.9:Showing 之后的跨栏 MoveWindow 排队。 }
    procedure TestAMoveAfterShowingIsQueued;
    procedure TestAMoveBeforeShowingIsSynchronous;
    procedure TestAButtonInTheWindowCanMoveItsOwnWindow;
    procedure TestWindowIndexWaitsBehindAQueuedMove;
    procedure TestASameBarMoveWaitsBehindAQueuedMove;
    procedure TestFreeingTheTargetDropsTheQueuedMove;
    procedure TestFreeingTheWindowDropsTheQueuedMove;
    procedure TestFreeingTheManagerDropsTheQueue;
    procedure TestAVetoAtExecutionDropsTheMoveSilently;
    procedure TestACaptureInsideTheWindowDelaysTheMoveOnce;
    procedure TestACaptureThatNeverLetsGoDelaysOnlyOnce;
    { spec §9.5 / §9.9:拖放提交在 Showing 之后也同步;MoveNow 的焦点和事件时机。 }
    procedure TestADropAfterShowingIsNotQueued;
    procedure TestADropKeepsTheFocusInTheWindow;
    procedure TestBarEventsAfterADropSeeTheWindowInPlace;
    { spec §10.5:代码搭的 manager 在 Showing 之后第一次改布局之前记默认布局(开工前问题 2)。 }
    procedure TestResetAfterAClickRestoresTheCurrentPage;
    procedure TestResetAfterResizingRestoresTheSize;
    procedure TestResetAfterCollapsingRestoresIt;
    procedure TestResetAfterADragReorderRestoresTheOrder;
    procedure TestResetAfterACrossDropRestoresTheSide;
    procedure TestResetAfterADirectParentChangeRestoresTheSide;
    { spec §10.5:Showing 之后 Load / Reset 排队。 }
    procedure TestALoadAfterShowingIsQueued;
    procedure TestAResetButtonInsideTheMovedWindowIsSafe;
    procedure TestALoadReplacesAQueuedMove;
    procedure TestACaptureInAMovingWindowDelaysTheLayoutOnce;
    { spec §10.4 第 7 步 / §14:应用之后的焦点。 }
    procedure TestFocusLeavesACollapsedBarForTheNextControl;
    procedure TestFocusStaysInAMovedWindow;
    procedure TestFocusFollowsIntoTheNewCurrentPage;
  private
    { Tab 顺序在左栏前面 / 右栏后面的两个编辑框:分得清 SelectNext(栏) 和平台随手挑的第一个。 }
    FBefore, FOutside: TTyEdit;
    procedure BtnResets(Sender: TObject);
    { 真实的 MouseDown / MouseMove / MouseUp:把 Search 的图标拖到右栏第一格上半松开。 }
    procedure DragSearchToRight;
  end;

implementation

var
  ManagerWidgetSetReady: Boolean = False;

procedure NeedManagerWidgetSet;
begin
  if ManagerWidgetSetReady then Exit;
  Forms.Application.Initialize;
  ManagerWidgetSetReady := True;
end;

procedure TTyToolWindowManagerFixture.SetUp;
begin
  inherited SetUp;
  FLog := '';
  FAllow := True;
  FCanCalls := 0;
  FCanWindow := nil;
  FCanTarget := nil;
end;

function TTyToolWindowManagerFixture.NewManager: TTyToolWindowManager;
begin
  Result := TTyToolWindowManager.Create(FForm);
  Result.OnCanMoveWindow := @HandleCanMove;
end;

procedure TTyToolWindowManagerFixture.HandleCanMove(Sender: TObject; AWindow: TTyToolWindow;
  ATargetBar: TTyToolWindowBar; var AAllow: Boolean);
begin
  Inc(FCanCalls);
  FCanWindow := AWindow;
  FCanTarget := ATargetBar;
  AAllow := FAllow;
end;

procedure TTyToolWindowManagerFixture.LogBarChange(ASender: TObject);
begin
  FLog := FLog + TComponent(ASender).Name + '.change;';
end;

procedure TTyToolWindowManagerFixture.LogBarExpand(ASender: TObject);
begin
  FLog := FLog + TComponent(ASender).Name + '.expand;';
end;

procedure TTyToolWindowManagerFixture.LogBarCollapse(ASender: TObject);
begin
  FLog := FLog + TComponent(ASender).Name + '.collapse;';
end;

procedure TTyToolWindowManagerFixture.LogBarEvents(ABar: TTyToolWindowBar);
begin
  ABar.OnChange := @LogBarChange;
  ABar.OnExpand := @LogBarExpand;
  ABar.OnCollapse := @LogBarCollapse;
end;

procedure TTyToolWindowManagerFixture.LogMoved(Sender: TObject; AWindow: TTyToolWindow;
  ASourceBar: TTyToolWindowBar; AOldIndex: Integer);
begin
  FLog := FLog + Format('moved(%s,%s,%d);', [AWindow.Name, ASourceBar.Name, AOldIndex]);
end;

procedure TTyToolWindowManagerFixture.NewLeftRight(out AManager: TTyToolWindowManager;
  out ALeft, ARight: TBarAccess);
begin
  AManager := NewManager;
  AManager.OnWindowMoved := @LogMoved;
  ALeft := NewBarOn(twpLeft, ['Explorer', 'Search', 'Git']);
  ARight := NewBarOn(twpRight, ['Outline']);
  ARight.Collapsed := True;
  ALeft.Manager := AManager;
  ARight.Manager := AManager;
  LogBarEvents(ALeft);
  LogBarEvents(ARight);
  FLog := '';
end;

procedure TTyToolWindowManagerFixture.LayOut(ABar: TBarAccess);
var
  r: TRect;
  i: Integer;
begin
  ABar.CallAlignControls;
  r := ABar.ClientRect;
  ABar.CallAdjustClientRect(r);
  for i := 0 to ABar.WindowCount - 1 do
    if ABar.Windows[i] is TProbeWindow then
    begin
      ABar.Windows[i].BoundsRect := r;
      TProbeWindow(ABar.Windows[i]).CallAlignControls;
    end;
end;

function TTyToolWindowManagerFixture.NewBarOn(APlacement: TTyToolWindowPlacement;
  const ACaptions: array of string): TBarAccess;
const
  Prefix: array[TTyToolWindowPlacement] of string = ('L', 'R', 'B');
var
  i, n: Integer;
  w: TProbeWindow;
  nm: string;
begin
  Result := TBarAccess.Create(FForm);
  { 名字:同一个前缀的第几条。 }
  n := 1;
  nm := Prefix[APlacement];
  while FForm.FindComponent(nm) <> nil do
  begin
    Inc(n);
    nm := Prefix[APlacement] + IntToStr(n);
  end;
  Result.Name := nm;
  Result.Placement := APlacement;
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  if APlacement = twpBottom then Result.Width := 600 else Result.Height := 400;
  for i := 0 to High(ACaptions) do
  begin
    w := TProbeWindow.Create(FForm);
    w.Name := 'W' + ACaptions[i];
    w.Caption := ACaptions[i];
    w.Parent := Result;
  end;
  if Length(ACaptions) > 1 then Result.ActiveWindow := Result.Windows[1];
end;

{ --- 注册与冲突(spec §10.6) ------------------------------------------------------- }

procedure TTyToolWindowManagerTests.TestOneBarPerPlacementIsUsable;
var
  m: TTyToolWindowManager;
  l, r, b: TBarAccess;
begin
  m := NewManager;
  l := NewBarOn(twpLeft, ['Explorer', 'Search']);
  r := NewBarOn(twpRight, ['Outline']);
  b := NewBarOn(twpBottom, ['Problems', 'Output']);
  l.Manager := m;
  r.Manager := m;
  b.Manager := m;
  AssertSame('左栏注册上了', m, l.Manager);
  AssertTrue('左栏可用', m.IsBarUsable(l));
  AssertTrue('右栏可用', m.IsBarUsable(r));
  AssertTrue('底栏可用', m.IsBarUsable(b));
  AssertFalse('没注册的栏不可用', m.IsBarUsable(FBar));
  AssertFalse('nil 不可用', m.IsBarUsable(nil));
end;

procedure TTyToolWindowManagerTests.TestEveryBarSharingAPlacementIsUnusable;
var
  m: TTyToolWindowManager;
  l, l2, r, b: TBarAccess;
begin
  m := NewManager;
  l := NewBarOn(twpLeft, ['Explorer', 'Search']);
  r := NewBarOn(twpRight, ['Outline']);
  b := NewBarOn(twpBottom, ['Problems']);
  l2 := NewBarOn(twpLeft, ['Git']);
  l.Manager := m;
  r.Manager := m;
  b.Manager := m;
  l2.Manager := m;
  { 不按先来后到:fixup 倒序执行,「先注册的」其实是流里最后一个。 }
  AssertFalse('先注册的左栏也不可用', m.IsBarUsable(l));
  AssertFalse('后注册的左栏不可用', m.IsBarUsable(l2));
  AssertTrue('右栏不受影响', m.IsBarUsable(r));
  AssertTrue('底栏不受影响', m.IsBarUsable(b));
  { 改 Placement 之后现算:冲突跟着搬到右边。 }
  l2.Placement := twpRight;
  AssertTrue('冲突走了,左栏恢复可用', m.IsBarUsable(l));
  AssertFalse('右栏现在冲突', m.IsBarUsable(r));
  AssertFalse('搬过去的那条也冲突', m.IsBarUsable(l2));
end;

procedure TTyToolWindowManagerTests.TestLeavingTheManagerOrBeingFreedEndsAConflict;
var
  m: TTyToolWindowManager;
  r, r2: TBarAccess;
begin
  m := NewManager;
  r := NewBarOn(twpRight, ['Outline']);
  r2 := NewBarOn(twpRight, ['Git']);
  r.Manager := m;
  r2.Manager := m;
  AssertFalse('前提:冲突', m.IsBarUsable(r));
  r2.Manager := nil;
  AssertFalse('离开的那条不在 manager 上,不可用', m.IsBarUsable(r2));
  AssertTrue('留下的那条恢复可用', m.IsBarUsable(r));
  r2.Manager := m;
  AssertFalse('前提:又冲突了', m.IsBarUsable(r));
  r2.Free;
  AssertTrue('冲突的那条被释放:留下的恢复可用', m.IsBarUsable(r));
end;

procedure TTyToolWindowManagerTests.TestFreeingTheManagerClearsEveryBar;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
begin
  m := NewManager;
  l := NewBarOn(twpLeft, ['Explorer']);
  r := NewBarOn(twpRight, ['Outline']);
  l.Manager := m;
  r.Manager := m;
  m.Free;
  { 比 nil,不比已释放的指针(地址会被立刻复用)。 }
  AssertTrue('左栏的引用清掉了', l.Manager = nil);
  AssertTrue('右栏的引用清掉了', r.Manager = nil);
end;

procedure TTyToolWindowManagerTests.TestManagerIsAPublishedReference;
var
  info: PPropInfo;
begin
  info := GetPropInfo(TTyToolWindowBar, 'Manager');
  AssertNotNull('Manager 是 published', info);
  AssertEquals('类型是 manager', 'TTyToolWindowManager', info^.PropType^.Name);
  AssertTrue('读得到(对象查看器要能读)', info^.GetProc <> nil);
end;

{ --- CanMoveWindow(spec §9.9) ------------------------------------------------------- }

procedure TTyToolWindowManagerTests.TestSideBarsCanTradeButNeverWithTheBottom;
var
  m: TTyToolWindowManager;
  l, r, b: TBarAccess;
begin
  m := NewManager;
  l := NewBarOn(twpLeft, ['Explorer', 'Search']);
  r := NewBarOn(twpRight, ['Outline']);
  b := NewBarOn(twpBottom, ['Problems', 'Output']);
  l.Manager := m;
  r.Manager := m;
  b.Manager := m;
  AssertTrue('左 → 右', m.CanMoveWindow(l.Windows[0], r));
  AssertTrue('右 → 左', m.CanMoveWindow(r.Windows[0], l));
  AssertFalse('左 → 底', m.CanMoveWindow(l.Windows[0], b));
  AssertFalse('底 → 右', m.CanMoveWindow(b.Windows[0], r));
  AssertFalse('nil 窗口', m.CanMoveWindow(nil, r));
  AssertFalse('nil 目标', m.CanMoveWindow(l.Windows[0], nil));
end;

procedure TTyToolWindowManagerTests.TestDesignTimeSideToBottomIsRefusedToo;
var
  m: TTyToolWindowManager;
  l, r, b: TBarAccess;
  w: TProbeWindow;
begin
  l := NewDesignBar;
  r := NewDesignBar;
  r.Placement := twpRight;
  b := NewDesignBar;
  b.Placement := twpBottom;
  m := TTyToolWindowManager.Create(FDesignOwner);
  m.OnCanMoveWindow := @HandleCanMove;
  AssertTrue('前提:manager 在设计期', csDesigning in m.ComponentState);
  l.Manager := m;
  r.Manager := m;
  b.Manager := m;
  w := NewWindowIn(l, FDesignOwner);
  NewWindowIn(b, FDesignOwner);
  { 运行时改 Parent 的豁免(设计期放行)不许漏进来:D 期的「移到另一侧栏」靠这一句拒。 }
  AssertFalse('设计期 左 → 底 也不行', m.CanMoveWindow(w, b));
  AssertTrue('设计期 左 → 右 行', m.CanMoveWindow(w, r));
  AssertEquals('设计期不问事件', 0, FCanCalls);
end;

procedure TTyToolWindowManagerTests.TestTheSameBarIsAlwaysAllowedWithoutAsking;
var
  m: TTyToolWindowManager;
  l: TBarAccess;
begin
  m := NewManager;
  l := NewBarOn(twpLeft, ['Explorer', 'Search']);
  l.Manager := m;
  FAllow := False;
  AssertTrue('同一条栏 = 调顺序,永远行', m.CanMoveWindow(l.Windows[0], l));
  AssertEquals('同栏不问事件', 0, FCanCalls);
end;

procedure TTyToolWindowManagerTests.TestBothBarsMustBeOnThisManager;
var
  m, m2: TTyToolWindowManager;
  l, r: TBarAccess;
begin
  m := NewManager;
  m2 := NewManager;
  l := NewBarOn(twpLeft, ['Explorer']);
  r := NewBarOn(twpRight, ['Outline']);
  l.Manager := m;
  AssertFalse('目标栏没有 manager', m.CanMoveWindow(l.Windows[0], r));
  r.Manager := m2;
  AssertFalse('目标栏在别的 manager 上', m.CanMoveWindow(l.Windows[0], r));
  AssertFalse('窗口的栏不在本 manager 上', m2.CanMoveWindow(l.Windows[0], r));
  r.Manager := m;
  AssertTrue('都在本 manager 上', m.CanMoveWindow(l.Windows[0], r));
end;

procedure TTyToolWindowManagerTests.TestAConflictBlocksCrossMovesButNotTheSameBar;
var
  m: TTyToolWindowManager;
  l, r, r2: TBarAccess;
begin
  m := NewManager;
  l := NewBarOn(twpLeft, ['Explorer', 'Search']);
  r := NewBarOn(twpRight, ['Outline']);
  r2 := NewBarOn(twpRight, ['Git', 'Debug']);
  l.Manager := m;
  r.Manager := m;
  r2.Manager := m;
  AssertFalse('目标栏冲突', m.CanMoveWindow(l.Windows[0], r));
  AssertFalse('源栏冲突,去别的栏', m.CanMoveWindow(r.Windows[0], l));
  AssertTrue('冲突的源栏,栏内调顺序照常', m.CanMoveWindow(r2.Windows[0], r2));
  AssertEquals('结构不过就不问事件', 0, FCanCalls);
end;

procedure TTyToolWindowManagerTests.TestABarOnAnotherFormIsRefused;
var
  m: TTyToolWindowManager;
  l: TBarAccess;
  f2: TForm;
  r2: TTyToolWindowBar;
  w: TTyToolWindow;
begin
  m := NewManager;
  l := NewBarOn(twpLeft, ['Explorer']);
  l.Manager := m;
  f2 := TForm.CreateNew(nil);
  try
    r2 := TTyToolWindowBar.Create(f2);
    r2.Placement := twpRight;
    r2.Parent := f2;
    w := TTyToolWindow.Create(f2);
    w.Parent := r2;
    r2.Manager := m;
    AssertTrue('前提:两条都可用', m.IsBarUsable(l) and m.IsBarUsable(r2));
    AssertFalse('另一个窗体上的栏不是目标', m.CanMoveWindow(l.Windows[0], r2));
    AssertFalse('反过来也不行', m.CanMoveWindow(w, l));
  finally
    f2.Free;
  end;
end;

procedure TTyToolWindowManagerTests.TestAnythingLoadingIsRefused;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
begin
  m := NewManager;
  l := NewBarOn(twpLeft, ['Explorer']);
  r := NewBarOn(twpRight, ['Outline']);
  l.Manager := m;
  r.Manager := m;
  r.BeginLoad;
  try
    AssertFalse('目标栏在加载中', m.CanMoveWindow(l.Windows[0], r));
  finally
    r.EndLoad;
  end;
  l.BeginLoad;
  try
    AssertFalse('源栏在加载中', m.CanMoveWindow(l.Windows[0], r));
  finally
    l.EndLoad;
  end;
  AssertTrue('加载完了就行', m.CanMoveWindow(l.Windows[0], r));
end;

procedure TTyToolWindowManagerTests.TestTheEventCanVetoAndSeesTheArguments;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
begin
  m := NewManager;
  l := NewBarOn(twpLeft, ['Explorer', 'Search']);
  r := NewBarOn(twpRight, ['Outline']);
  l.Manager := m;
  r.Manager := m;
  FAllow := False;
  AssertFalse('事件否决', m.CanMoveWindow(l.Windows[1], r));
  AssertEquals('问了一次', 1, FCanCalls);
  AssertSame('事件收到的窗口', l.Windows[1], FCanWindow);
  AssertSame('事件收到的目标栏', r, FCanTarget);
  FAllow := True;
  AssertTrue('事件放行', m.CanMoveWindow(l.Windows[1], r));
end;

procedure TTyToolWindowManagerTests.TestAskingChangesNothing;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
  a, b, c: TTyToolWindow;
  x: TTyToolWindow;
begin
  m := NewManager;
  l := NewBarOn(twpLeft, ['Explorer', 'Search', 'Git']);
  r := NewBarOn(twpRight, ['Outline']);
  l.Manager := m;
  r.Manager := m;
  a := l.Windows[0];
  b := l.Windows[1];
  c := l.Windows[2];
  x := r.Windows[0];
  r.Collapsed := True;
  r.ExpandedSize := 300;
  AssertSame('前提:左栏当前页是第二个', b, l.ActiveWindow);
  FAllow := True;
  m.CanMoveWindow(b, r);
  FAllow := False;
  m.CanMoveWindow(b, r);
  m.CanMoveWindow(a, l);
  AssertSame('窗口还在左栏', TWinControl(l), b.Parent);
  AssertTrue('顺序没变', (l.Windows[0] = a) and (l.Windows[1] = b) and (l.Windows[2] = c));
  AssertSame('左栏当前页没变', b, l.ActiveWindow);
  AssertSame('右栏当前页没变', x, r.ActiveWindow);
  AssertTrue('右栏还收起着', r.Collapsed);
  AssertFalse('左栏没被收起', l.Collapsed);
  AssertEquals('尺寸没变', 300, r.ExpandedSize);
end;

{ --- MoveWindow 的同步路径(spec §9.5 / §9.9 / §6.6) ----------------------------------- }

procedure TTyToolWindowManagerTests.MovedThenMoveAgain(Sender: TObject; AWindow: TTyToolWindow;
  ASourceBar: TTyToolWindowBar; AOldIndex: Integer);
begin
  LogMoved(Sender, AWindow, ASourceBar, AOldIndex);
  if FReentered <> -1 then Exit;
  FReentered := -2;
  FReentered := Ord(TTyToolWindowManager(Sender).MoveWindow(AWindow, FReenterTarget));
end;

procedure TTyToolWindowManagerTests.CanMoveThenMove(Sender: TObject; AWindow: TTyToolWindow;
  ATargetBar: TTyToolWindowBar; var AAllow: Boolean);
begin
  AAllow := True;
  { 只重入一次:变异掉重入闸时这里会无限递归。 }
  if FReentered <> -1 then Exit;
  FReentered := -2;
  FReentered := Ord(TTyToolWindowManager(Sender).MoveWindow(FReenterWindow, FReenterTarget));
end;

procedure TTyToolWindowManagerTests.TestMoveWindowActivatesAndExpandsTheTarget;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
  b, c: TTyToolWindow;
begin
  NewLeftRight(m, l, r);
  b := l.Windows[1];
  c := l.Windows[2];
  AssertSame('前提:左栏当前页是 Search', b, l.ActiveWindow);
  AssertTrue('前提:右栏收起着', r.Collapsed);
  AssertTrue('接受了', m.MoveWindow(b, r, 0));
  AssertSame('窗口到了右栏', TTyToolWindowBar(r), b.Bar);
  AssertSame('排在第一个', b, r.Windows[0]);
  AssertSame('成为右栏当前页', b, r.ActiveWindow);
  AssertFalse('右栏展开了', r.Collapsed);
  AssertTrue('它显示着', b.Visible);
  AssertSame('左栏回落到原位置上的下一个', c, l.ActiveWindow);
  AssertFalse('左栏的 Collapsed 不动', l.Collapsed);
end;

procedure TTyToolWindowManagerTests.TestMoveWindowEventsFireInSpecOrder;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
begin
  NewLeftRight(m, l, r);
  m.MoveWindow(l.Windows[1], r, 0);
  { 源栏 OnChange → 目标栏 OnExpand → 目标栏 OnChange → OnWindowMoved(spec §6.6)。 }
  AssertEquals('事件顺序', 'L.change;R.expand;R.change;moved(WSearch,L,1);', FLog);
end;

procedure TTyToolWindowManagerTests.TestMoveWindowIndexClampsAndMinusOneMeansTheEnd;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
  a, b, c, x: TTyToolWindow;
begin
  NewLeftRight(m, l, r);
  a := l.Windows[0];
  b := l.Windows[1];
  c := l.Windows[2];
  x := r.Windows[0];
  m.MoveWindow(a, r, -1);
  AssertSame('-1 = 末尾', a, r.Windows[1]);
  AssertSame('原来的还在前面', x, r.Windows[0]);
  m.MoveWindow(c, r, 99);
  AssertSame('越界钳到末尾', c, r.Windows[2]);
  m.MoveWindow(b, r, 0);
  AssertSame('0 = 第一个', b, r.Windows[0]);
  AssertEquals('四个', 4, r.WindowCount);
end;

procedure TTyToolWindowManagerTests.TestMovingAnInactiveWindowLeavesTheSourceAlone;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
  b: TTyToolWindow;
begin
  NewLeftRight(m, l, r);
  b := l.Windows[1];
  m.MoveWindow(l.Windows[0], r);
  AssertSame('左栏当前页还是 Search', b, l.ActiveWindow);
  AssertEquals('左栏不发 OnChange', 'R.expand;R.change;moved(WExplorer,L,0);', FLog);
end;

procedure TTyToolWindowManagerTests.TestMoveWindowWithinABarIsAReorder;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
  a, b, c: TTyToolWindow;
begin
  NewLeftRight(m, l, r);
  a := l.Windows[0];
  b := l.Windows[1];
  c := l.Windows[2];
  FAllow := False;
  AssertTrue('同栏:接受', m.MoveWindow(a, l, 2));
  AssertTrue('顺序变了', (l.Windows[0] = b) and (l.Windows[1] = c) and (l.Windows[2] = a));
  AssertSame('当前页还是 Search', b, l.ActiveWindow);
  AssertEquals('只报一次 OnWindowMoved,不发 OnChange', 'moved(WExplorer,L,0);', FLog);
  AssertEquals('同栏不问 OnCanMoveWindow', 0, FCanCalls);
end;

procedure TTyToolWindowManagerTests.TestMoveWindowFromOnWindowMovedIsRefused;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
  b: TTyToolWindow;
begin
  NewLeftRight(m, l, r);
  b := l.Windows[1];
  FReentered := -1;
  FReenterTarget := l;
  m.OnWindowMoved := @MovedThenMoveAgain;
  AssertTrue('外层接受', m.MoveWindow(b, r));
  AssertEquals('处理器里再调 MoveWindow:答 False', 0, FReentered);
  AssertSame('没被挪回去', TTyToolWindowBar(r), b.Bar);
end;

procedure TTyToolWindowManagerTests.TestMoveWindowFromOnCanMoveWindowIsRefused;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
  a, x: TTyToolWindow;
begin
  NewLeftRight(m, l, r);
  a := l.Windows[0];
  x := r.Windows[0];
  FReentered := -1;
  FReenterWindow := x;
  FReenterTarget := l;
  m.OnCanMoveWindow := @CanMoveThenMove;
  AssertTrue('外层接受', m.MoveWindow(a, r));
  AssertEquals('OnCanMoveWindow 里调 MoveWindow:答 False', 0, FReentered);
  AssertSame('x 没被挪', TTyToolWindowBar(r), x.Bar);
end;

procedure TTyToolWindowManagerTests.TestAVetoedMoveChangesNothing;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
  b: TTyToolWindow;
begin
  NewLeftRight(m, l, r);
  b := l.Windows[1];
  FAllow := False;
  AssertFalse('被否决', m.MoveWindow(b, r));
  AssertSame('还在左栏', TTyToolWindowBar(l), b.Bar);
  AssertSame('左栏当前页没变', b, l.ActiveWindow);
  AssertTrue('右栏还收起着', r.Collapsed);
  AssertEquals('没有任何事件', '', FLog);
end;

procedure TTyToolWindowManagerTests.TestEveryReorderReportsOnWindowMoved;
var
  m, dm: TTyToolWindowManager;
  l, r, bb, d: TBarAccess;
  b, dw: TTyToolWindow;
  p: TPoint;
  act: TProbeWindow;
  g: TTyToolWindowHeaderGeom;
  i: Integer;
  c, e: TPoint;
begin
  NewLeftRight(m, l, r);
  b := l.Windows[1];
  { WindowIndex。 }
  b.WindowIndex := 0;
  AssertEquals('WindowIndex 报一次', 'moved(WSearch,L,1);', FLog);
  FLog := '';
  b.WindowIndex := 0;
  AssertEquals('原地设不报', '', FLog);
  { 图标拖动:此刻 Search / Explorer / Git,把第一个拖到末尾。 }
  p := l.StripItemRect(0).CenterPoint;
  l.CallMouseDown(p.X, p.Y);
  l.CallMouseMove(p.X, p.Y + 80);
  l.CallMouseUp(p.X, p.Y + 80);
  AssertSame('前提:拖到了末尾', b, l.Windows[2]);
  AssertEquals('图标拖动报一次', 'moved(WSearch,L,0);', FLog);
  FLog := '';
  { 拖回自己的空隙(空操作)。 }
  p := l.StripItemRect(0).CenterPoint;
  l.CallMouseDown(p.X, p.Y);
  l.CallMouseMove(p.X, p.Y + 10);
  AssertTrue('前提:拖起来了', l.IsDraggingForTest);
  l.CallMouseUp(p.X, p.Y + 10);
  AssertEquals('空操作不报', '', FLog);
  { SetChildOrder(流式、设计器)不经过 ReorderWindow。 }
  l.CallSetChildOrder(l.Windows[0], 2);
  AssertEquals('SetChildOrder 不报', '', FLog);
  { 底栏标签拖动。 }
  bb := NewBarOn(twpBottom, ['Problems', 'Output', 'Terminal']);
  bb.Manager := m;
  LayOut(bb);
  act := bb.ActiveWindow as TProbeWindow;
  g := act.HeaderGeomAt(Rect(0, 0, act.ClientWidth, act.ClientHeight), 96);
  c := Point(-1, -1);
  for i := 0 to High(g.Tabs) do
    if g.Tabs[i].ItemIndex = 0 then c := g.Tabs[i].ItemRect.CenterPoint;
  AssertTrue('前提:第一个标签排上了', c.X >= 0);
  e := Point(g.Tabs[High(g.Tabs)].ItemRect.Right + 5, c.Y);
  FLog := '';
  act.CallMouseDown(c.X, c.Y);
  act.CallMouseMove(e.X, e.Y, [ssLeft]);
  AssertTrue('前提:标签拖起来了', bb.IsDraggingForTest);
  act.CallMouseUp(e.X, e.Y);
  AssertEquals('标签拖动报一次', 'moved(WProblems,B,0);', FLog);
  { 设计期的栏:WindowIndex 不报。 }
  FLog := '';
  d := NewDesignBar;
  dm := TTyToolWindowManager.Create(FDesignOwner);
  dm.OnWindowMoved := @LogMoved;
  d.Manager := dm;
  dw := NewWindowIn(d, FDesignOwner);
  NewWindowIn(d, FDesignOwner);
  dw.WindowIndex := 1;
  AssertSame('前提:设计期照样调了顺序', dw, d.Windows[1]);
  AssertEquals('设计期不报', '', FLog);
end;

procedure TTyToolWindowManagerTests.TestDesignTimeMoveWindowIsSilent;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
  w: TTyToolWindow;
begin
  l := NewDesignBar;
  r := NewDesignBar;
  r.Placement := twpRight;
  m := TTyToolWindowManager.Create(FDesignOwner);
  m.OnCanMoveWindow := @HandleCanMove;
  m.OnWindowMoved := @LogMoved;
  l.Manager := m;
  r.Manager := m;
  LogBarEvents(l);
  LogBarEvents(r);
  w := NewWindowIn(l, FDesignOwner);
  NewWindowIn(l, FDesignOwner);
  NewWindowIn(r, FDesignOwner);
  FLog := '';
  AssertTrue('设计期接受', m.MoveWindow(w, r));
  AssertSame('同步挪过去了', TTyToolWindowBar(r), w.Bar);
  AssertSame('成为目标栏当前页', w, r.ActiveWindow);
  AssertEquals('不问 OnCanMoveWindow', 0, FCanCalls);
  AssertEquals('不发任何事件', '', FLog);
end;

{ --- 直接改 Parent(spec §3.2) --------------------------------------------------------- }

procedure TTyToolWindowManagerTests.TestADirectParentChangeBooksTheMove;
var
  l, r: TBarAccess;
  b, c: TTyToolWindow;
begin
  l := NewBarOn(twpLeft, ['Explorer', 'Search', 'Git']);
  r := NewBarOn(twpRight, ['Outline']);
  r.Collapsed := True;
  LogBarEvents(l);
  LogBarEvents(r);
  b := l.Windows[1];
  c := l.Windows[2];
  FLog := '';
  b.Parent := r;
  AssertSame('成为目标栏当前页', b, r.ActiveWindow);
  AssertFalse('目标栏展开', r.Collapsed);
  AssertSame('源栏回落', c, l.ActiveWindow);
  AssertEquals('没有 manager:栏事件照 MoveWindow 的顺序', 'L.change;R.expand;R.change;', FLog);
end;

procedure TTyToolWindowManagerTests.TestADirectParentChangeUnderOneManagerReportsTheMove;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
begin
  NewLeftRight(m, l, r);
  FAllow := False;
  l.Windows[1].Parent := r;
  AssertEquals('同一 manager:多报一次 OnWindowMoved',
    'L.change;R.expand;R.change;moved(WSearch,L,1);', FLog);
  AssertEquals('不问否决', 0, FCanCalls);
  AssertSame('照做了', r.Windows[1], r.ActiveWindow);
end;

procedure TTyToolWindowManagerTests.TestBarsOnDifferentManagersReportNoMove;
var
  m, m2: TTyToolWindowManager;
  l, r: TBarAccess;
begin
  NewLeftRight(m, l, r);
  m2 := NewManager;
  m2.OnWindowMoved := @LogMoved;
  r.Manager := m2;
  FLog := '';
  l.Windows[1].Parent := r;
  AssertEquals('两个 manager:没有 OnWindowMoved', 'L.change;R.expand;R.change;', FLog);
end;

procedure TTyToolWindowManagerTests.TestAConflictingTargetStillTakesTheWindow;
var
  m: TTyToolWindowManager;
  l, r, r2: TBarAccess;
  b: TTyToolWindow;
begin
  NewLeftRight(m, l, r);
  r2 := NewBarOn(twpRight, ['Debug']);
  r2.Manager := m;
  AssertFalse('前提:目标栏冲突', m.IsBarUsable(r));
  b := l.Windows[1];
  FLog := '';
  b.Parent := r;
  AssertSame('冲突不冲突都照做', TTyToolWindowBar(r), b.Bar);
  AssertFalse('展开', r.Collapsed);
  AssertEquals('照样报', 'L.change;R.expand;R.change;moved(WSearch,L,1);', FLog);
end;

procedure TTyToolWindowManagerTests.TestMoveWindowReportsExactlyOnce;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
  p, n: Integer;
begin
  NewLeftRight(m, l, r);
  m.MoveWindow(l.Windows[1], r);
  n := 0;
  p := Pos('moved(', FLog);
  while p > 0 do
  begin
    Inc(n);
    p := PosEx('moved(', FLog, p + 1);
  end;
  AssertEquals('MoveWindow 自己换父不再走一遍直接改 Parent 的簿记', 1, n);
end;

procedure TTyToolWindowManagerTests.TestDesignTimeAndLoadingParentChangesDoNotExpand;
var
  dl, dr: TBarAccess;
  w: TTyToolWindow;
  l, r: TBarAccess;
begin
  dl := NewDesignBar;
  dr := NewDesignBar;
  dr.Placement := twpRight;
  w := NewWindowIn(dl, FDesignOwner);
  NewWindowIn(dr, FDesignOwner);
  dr.Collapsed := True;
  w.Parent := dr;
  AssertTrue('设计期:目标栏的 Collapsed 不被改', dr.Collapsed);
  l := NewBarOn(twpLeft, ['Explorer', 'Search']);
  r := NewBarOn(twpRight, ['Outline']);
  r.BeginLoad;
  try
    r.Collapsed := True;
    l.Windows[1].Parent := r;
    AssertTrue('加载中:目标栏的 Collapsed 不被改', r.Collapsed);
  finally
    r.EndLoad;
  end;
end;

procedure TTyToolWindowManagerTests.TestOrphansAreNotBooked;
var
  l, r: TBarAccess;
  o: TProbeWindow;
begin
  l := NewBarOn(twpLeft, ['Explorer', 'Search']);
  r := NewBarOn(twpRight, ['Outline']);
  r.Collapsed := True;
  o := TProbeWindow.Create(FForm);
  o.Parent := FForm;
  LogBarEvents(l);
  LogBarEvents(r);
  FLog := '';
  o.Parent := r;
  AssertTrue('孤儿进栏:不展开', r.Collapsed);
  AssertEquals('孤儿进栏:只有注册即激活的那一次 OnChange', 'R.change;', FLog);
  FLog := '';
  l.Windows[1].Parent := nil;
  AssertEquals('出栏到 nil:只有源栏回落', 'L.change;', FLog);
end;

{ --- 真句柄 --------------------------------------------------------------------------- }

procedure TTyToolWindowManagerLiveTests.TrapException(Sender: TObject; E: Exception);
begin
  if FTrapped = '' then
    FTrapped := E.ClassName + ': ' + E.Message;
end;

procedure TTyToolWindowManagerLiveTests.AssertNothingRaised(const AWhere: string);
var
  s: string;
begin
  if FTrapped = '' then Exit;
  s := FTrapped;
  FTrapped := '';
  Fail(AWhere + ' raised on the real message path: ' + s);
end;

function TTyToolWindowManagerLiveTests.NewWin(ABar: TTyToolWindowBar;
  const AName: string): TTyToolWindow;
begin
  Result := TTyToolWindow.Create(FForm);
  Result.Name := AName;
  Result.Caption := AName;
  Result.Parent := ABar;
end;

procedure TTyToolWindowManagerLiveTests.Pump(AMs: Integer);
var
  t0: QWord;
begin
  t0 := GetTickCount64;
  repeat
    Application.ProcessMessages;
    Sleep(5);
  until GetTickCount64 - t0 >= QWord(AMs);
end;

procedure TTyToolWindowManagerLiveTests.SetUp;
begin
  NeedManagerWidgetSet;
  FTrapped := '';
  FLog := '';
  FPrevOnException := Forms.Application.OnException;
  Forms.Application.OnException := @TrapException;
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(-4000, -4000, 900, 500);
  FCtl := TTyStyleController.Create(FForm);
  FMgr := TTyToolWindowManager.Create(FForm);
  FBefore := TTyEdit.Create(FForm);
  FBefore.Parent := FForm;
  FBefore.SetBounds(400, 8, 120, 26);
  FLeft := TTyToolWindowBar.Create(FForm);
  FLeft.Name := 'L';
  FLeft.Parent := FForm;
  FLeft.Controller := FCtl;
  FLeft.Manager := FMgr;
  FRight := TTyToolWindowBar.Create(FForm);
  FRight.Name := 'R';
  FRight.Placement := twpRight;
  FRight.Parent := FForm;
  FRight.Controller := FCtl;
  FRight.Manager := FMgr;
  FExplorer := NewWin(FLeft, 'WExplorer');
  FSearch := NewWin(FLeft, 'WSearch');
  FEdit := TTyEdit.Create(FForm);
  FEdit.Parent := FSearch;
  FEdit.SetBounds(8, 40, 120, 26);
  FOutline := NewWin(FRight, 'WOutline');
  FOutside := TTyEdit.Create(FForm);
  FOutside.Parent := FForm;
  FOutside.SetBounds(400, 60, 120, 26);
  FBtn := TTyButton.Create(FForm);
  FBtn.Parent := FSearch.EnsureActions;
  FBtn.OnClick := @BtnMovesSearch;
  FCanCount := 0;
  FDenyFrom := 0;
  FMgr.OnCanMoveWindow := @CountCan;
  FMgr.OnWindowMoved := @LogMoved;
  FLeft.ActiveWindow := FSearch;
  FForm.Visible := True;
  FForm.HandleNeeded;
  Pump;
  AssertTrue('前提:窗体显示着', FForm.Showing);
  AssertTrue('前提:当前页里的编辑框聚焦得上', FEdit.CanFocus);
end;

procedure TTyToolWindowManagerLiveTests.TearDown;
begin
  SetCaptureControl(nil);
  FForm.Free;
  FForm := nil;
  Forms.Application.OnException := FPrevOnException;
end;

procedure TTyToolWindowManagerLiveTests.RightChangeSeesBounds(Sender: TObject);
begin
  FSeenBounds := FSearch.BoundsRect;
  FLog := FLog + 'R.change;';
end;

procedure TTyToolWindowManagerLiveTests.LogChange(Sender: TObject);
begin
  FLog := FLog + TComponent(Sender).Name + '.change;';
end;

procedure TTyToolWindowManagerLiveTests.LogExpand(Sender: TObject);
begin
  FLog := FLog + TComponent(Sender).Name + '.expand;';
end;

procedure TTyToolWindowManagerLiveTests.LogCollapse(Sender: TObject);
begin
  FLog := FLog + TComponent(Sender).Name + '.collapse;';
end;

procedure TTyToolWindowManagerLiveTests.LogMoved(Sender: TObject; AWindow: TTyToolWindow;
  ASourceBar: TTyToolWindowBar; AOldIndex: Integer);
begin
  FLog := FLog + Format('moved(%s,%s,%d);', [AWindow.Name, ASourceBar.Name, AOldIndex]);
end;

procedure TTyToolWindowManagerLiveTests.CountCan(Sender: TObject; AWindow: TTyToolWindow;
  ATargetBar: TTyToolWindowBar; var AAllow: Boolean);
begin
  Inc(FCanCount);
  AAllow := (FDenyFrom = 0) or (FCanCount < FDenyFrom);
end;

procedure TTyToolWindowManagerLiveTests.BtnMovesSearch(Sender: TObject);
var
  h: THandle;
begin
  h := FBtn.Handle;
  FClickAnswer := FMgr.MoveWindow(FSearch, FRight);
  { 同步换父会在这里销毁按钮的句柄(它就在要挪的窗口里)。 }
  FHandleKept := FBtn.HandleAllocated and (FBtn.Handle = h);
end;

procedure TTyToolWindowManagerLiveTests.ClickReal(AControl: TWinControl);
var
  p: PtrInt;
begin
  p := PtrInt(((AControl.Height div 2) shl 16) or ((AControl.Width div 2) and $FFFF));
  AControl.Perform(LM_LBUTTONDOWN, MK_LBUTTON, p);
  AControl.Perform(LM_LBUTTONUP, 0, p);
end;

procedure TTyToolWindowManagerLiveTests.TestAMoveAfterShowingIsQueued;
begin
  FLeft.OnChange := @LogChange;
  FRight.OnChange := @LogChange;
  FRight.OnExpand := @LogExpand;
  FRight.Collapsed := True;
  Pump;
  FLog := '';
  AssertTrue('接受了', FMgr.MoveWindow(FSearch, FRight, 0));
  AssertSame('返回那一刻还在左栏', FLeft, FSearch.Bar);
  AssertEquals('还没有事件', '', FLog);
  Pump;
  AssertNothingRaised('排队的移动');
  AssertSame('抽消息之后到了右栏', FRight, FSearch.Bar);
  AssertEquals('事件照同步路径的顺序', 'L.change;R.expand;R.change;moved(WSearch,L,1);', FLog);
end;

procedure TTyToolWindowManagerLiveTests.TestAMoveBeforeShowingIsSynchronous;
begin
  FForm.Visible := False;
  Pump;
  AssertFalse('前提:窗体没显示', FForm.Showing);
  AssertTrue('接受了', FMgr.MoveWindow(FSearch, FRight));
  AssertSame('窗体没 Showing:当场生效', FRight, FSearch.Bar);
end;

procedure TTyToolWindowManagerLiveTests.TestAButtonInTheWindowCanMoveItsOwnWindow;
begin
  Pump;
  AssertTrue('前提:按钮有句柄', FBtn.HandleAllocated);
  FHandleKept := False;
  FClickAnswer := False;
  ClickReal(FBtn);
  AssertNothingRaised('按钮自己的点击里 MoveWindow');
  AssertTrue('前提:OnClick 跑了、MoveWindow 接受了', FClickAnswer);
  AssertTrue('处理器返回前按钮的句柄没被销毁', FHandleKept);
  AssertSame('点击处理里还没挪', FLeft, FSearch.Bar);
  Pump;
  AssertNothingRaised('排队的移动');
  AssertSame('抽消息之后到了右栏', FRight, FSearch.Bar);
end;

procedure TTyToolWindowManagerLiveTests.TestWindowIndexWaitsBehindAQueuedMove;
begin
  FMgr.MoveWindow(FSearch, FRight, 0);
  FSearch.WindowIndex := 1;
  Pump;
  AssertNothingRaised('排队的移动');
  AssertSame('先挪到右栏', FRight, FSearch.Bar);
  AssertEquals('再按调用顺序调顺序', 1, FSearch.WindowIndex);
end;

procedure TTyToolWindowManagerLiveTests.TestASameBarMoveWaitsBehindAQueuedMove;
begin
  FMgr.MoveWindow(FSearch, FRight, 0);
  AssertTrue('同栏的也接受', FMgr.MoveWindow(FSearch, FLeft, 0));
  AssertEquals('同栏的这一次也排着:当场没动', 1, FSearch.WindowIndex);
  Pump;
  AssertNothingRaised('排队的移动');
  AssertSame('按调用顺序:先去右栏、再回左栏', FLeft, FSearch.Bar);
  AssertEquals('回到第一个', 0, FSearch.WindowIndex);
end;

procedure TTyToolWindowManagerLiveTests.TestFreeingTheTargetDropsTheQueuedMove;
begin
  FMgr.MoveWindow(FSearch, FRight);
  AssertEquals('前提:排着一项', 1, FMgr.QueuedCountForTest);
  FreeAndNil(FRight);
  AssertEquals('目标栏被释放:以它为目标的排队项删掉了', 0, FMgr.QueuedCountForTest);
  Pump;
  AssertNothingRaised('目标栏被释放之后抽消息');
  AssertSame('还在左栏', FLeft, FSearch.Bar);
end;

procedure TTyToolWindowManagerLiveTests.TestFreeingTheWindowDropsTheQueuedMove;
begin
  FMgr.MoveWindow(FSearch, FRight);
  AssertEquals('前提:排着一项', 1, FMgr.QueuedCountForTest);
  FreeAndNil(FSearch);
  { 不删的话队列里留着悬垂指针 —— 执行时读的是已释放的内存,不一定当场 AV。 }
  AssertEquals('窗口被释放:它的排队项删掉了', 0, FMgr.QueuedCountForTest);
  Pump;
  AssertNothingRaised('窗口被释放之后抽消息');
  AssertEquals('右栏只有原来那一个', 1, FRight.WindowCount);
end;

procedure TTyToolWindowManagerLiveTests.TestFreeingTheManagerDropsTheQueue;
var
  dead: Pointer;
  before: PtrUInt;
begin
  FMgr.MoveWindow(FSearch, FRight);
  dead := Pointer(FMgr);
  FreeAndNil(FMgr);
  { 析构没撤掉的话,Application 的异步队列里还挂着「死 manager 的 RunQueue」:这里再按那个地址
    撤一次(只比指针,不解引用),撤得到就会还掉一项的内存。空队列跑在死对象上不一定当场 AV,
    所以不靠 AV 判。 }
  before := GetFPCHeapStatus.CurrHeapUsed;
  Application.RemoveAsyncCalls(TObject(dead));
  AssertEquals('manager 析构已经撤掉了自己排的异步调用', before,
    GetFPCHeapStatus.CurrHeapUsed);
  Pump;
  AssertNothingRaised('manager 被释放之后抽消息');
  AssertSame('还在左栏', FLeft, FSearch.Bar);
end;

procedure TTyToolWindowManagerLiveTests.TestAVetoAtExecutionDropsTheMoveSilently;
begin
  FLeft.OnChange := @LogChange;
  FRight.OnChange := @LogChange;
  FRight.OnExpand := @LogExpand;
  FDenyFrom := 2;                    { 排队时放行,执行前再问一次时否决 }
  AssertTrue('排队时放行', FMgr.MoveWindow(FSearch, FRight));
  FLog := '';
  Pump;
  AssertNothingRaised('排队的移动');
  AssertEquals('执行前又问了一次', 2, FCanCount);
  AssertSame('被否决:还在左栏', FLeft, FSearch.Bar);
  AssertEquals('静默丢弃:没有任何事件', '', FLog);
end;

procedure TTyToolWindowManagerLiveTests.TestACaptureInsideTheWindowDelaysTheMoveOnce;
begin
  FMgr.MoveWindow(FSearch, FRight);
  SetCaptureControl(FBtn);
  try
    AssertSame('前提:捕获在窗口里的按钮上', FBtn, GetCaptureControl);
    RunAsyncOnce;
    AssertNothingRaised('第一轮');
    AssertSame('前提:执行那一刻捕获还在', FBtn, GetCaptureControl);
    AssertSame('捕获在窗口里:再排一次,还在左栏', FLeft, FSearch.Bar);
  finally
    SetCaptureControl(nil);
  end;
  Pump;
  AssertNothingRaised('第二轮');
  AssertSame('放掉捕获之后到了右栏', FRight, FSearch.Bar);
end;

procedure TTyToolWindowManagerLiveTests.TestACaptureThatNeverLetsGoDelaysOnlyOnce;
begin
  FMgr.MoveWindow(FSearch, FRight);
  SetCaptureControl(FBtn);
  try
    RunAsyncOnce;
    AssertSame('前提:第一轮再排了', FLeft, FSearch.Bar);
    AssertSame('前提:捕获还在', FBtn, GetCaptureControl);
    RunAsyncOnce;
    AssertNothingRaised('第二轮');
    AssertSame('第二轮捕获还在也照做', FRight, FSearch.Bar);
  finally
    SetCaptureControl(nil);
  end;
end;

type
  { ProcessAsyncCallQueue 是 protected。 }
  TAppAccess = class(TApplication);

procedure TTyToolWindowManagerLiveTests.RunAsyncOnce;
begin
  { 只跑异步队列的一轮、不抽 OS 消息:一次 Application.ProcessMessages 可能跑两轮(消息
    分派里有人再进一次队列),而窗体不在前台时抽 OS 消息系统会收走捕获。 }
  TAppAccess(Application).ProcessAsyncCallQueue;
end;

type
  { 受保护的鼠标入口开出来(真句柄夹具的栏是 TTyToolWindowBar 本身)。 }
  TBarCrack = class(TTyToolWindowBar);

procedure TTyToolWindowManagerLiveTests.DragSearchToRight;
var
  p, q: TPoint;
  r: TRect;
begin
  p := FLeft.StripItemRect(1).CenterPoint;
  TBarCrack(FLeft).MouseDown(mbLeft, [ssLeft], p.X, p.Y);
  TBarCrack(FLeft).MouseMove([ssLeft], p.X + 10, p.Y);
  AssertTrue('前提:拖起来了', FLeft.IsDraggingForTest);
  r := FRight.StripItemRect(0);
  q := FLeft.ScreenToClient(FRight.ClientToScreen(Point(r.CenterPoint.X, r.Top + 4)));
  TBarCrack(FLeft).MouseMove([ssLeft], q.X, q.Y);
  AssertTrue('前提:右栏有落点', FRight.ForeignDropForTest);
  TBarCrack(FLeft).MouseUp(mbLeft, [], q.X, q.Y);
end;

procedure TTyToolWindowManagerLiveTests.TestADropAfterShowingIsNotQueued;
begin
  DragSearchToRight;
  AssertNothingRaised('拖放');
  AssertSame('松开那一刻已经在右栏(拖放提交不排队)', FRight, FSearch.Bar);
end;

procedure TTyToolWindowManagerLiveTests.TestADropKeepsTheFocusInTheWindow;
begin
  FEdit.SetFocus;
  AssertSame('前提:焦点在 Search 的编辑框里', FEdit, FForm.ActiveControl);
  DragSearchToRight;
  AssertNothingRaised('拖放');
  AssertSame('前提:挪过去了', FRight, FSearch.Bar);
  AssertSame('焦点还给编辑框', FEdit, FForm.ActiveControl);
end;

procedure TTyToolWindowManagerLiveTests.TestBarEventsAfterADropSeeTheWindowInPlace;
begin
  FRight.Collapsed := True;
  Pump;
  FRight.OnChange := @RightChangeSeesBounds;
  DragSearchToRight;
  AssertNothingRaised('拖放');
  AssertEquals('前提:发了一次', 'R.change;moved(WSearch,L,1);', FLog);
  AssertTrue('OnChange 里读到的已经是右栏内容区(事件在 EnableAlign 之后)',
    EqualRect(FRight.BarLayout.Content, FSeenBounds));
end;

{ --- 默认布局的自动记录、排队、焦点(spec §10.4 / §10.5) --------------------------------- }

procedure TTyToolWindowManagerLiveTests.BtnResets(Sender: TObject);
var
  h: THandle;
begin
  h := FBtn.Handle;
  FClickAnswer := FMgr.ResetLayout;
  FHandleKept := FBtn.HandleAllocated and (FBtn.Handle = h);
end;

procedure TTyToolWindowManagerLiveTests.TestResetAfterAClickRestoresTheCurrentPage;
var
  p: TPoint;
begin
  { 代码搭的 manager,没调过 Load / Reset / CaptureDefaultLayout:显示之后点另一个图标。 }
  p := FLeft.StripItemRect(0).CenterPoint;
  TBarCrack(FLeft).MouseDown(mbLeft, [ssLeft], p.X, p.Y);
  TBarCrack(FLeft).MouseUp(mbLeft, [], p.X, p.Y);
  AssertSame('前提:点过去了', FExplorer, FLeft.ActiveWindow);
  AssertTrue(FMgr.ResetLayout);
  Pump;
  AssertNothingRaised('Reset');
  AssertSame('当前页回到点之前那一页', FSearch, FLeft.ActiveWindow);
end;

procedure TTyToolWindowManagerLiveTests.TestResetAfterResizingRestoresTheSize;
begin
  FLeft.ExpandedSize := 300;
  AssertTrue(FMgr.ResetLayout);
  Pump;
  AssertEquals('尺寸回到改之前', TyToolWindowDefaultExpandedSize, FLeft.ExpandedSize);
end;

procedure TTyToolWindowManagerLiveTests.TestResetAfterCollapsingRestoresIt;
begin
  FLeft.Collapsed := True;
  AssertTrue(FMgr.ResetLayout);
  Pump;
  AssertFalse('收起回到改之前', FLeft.Collapsed);
end;

procedure TTyToolWindowManagerLiveTests.TestResetAfterADragReorderRestoresTheOrder;
var
  p: TPoint;
begin
  p := FLeft.StripItemRect(0).CenterPoint;
  TBarCrack(FLeft).MouseDown(mbLeft, [ssLeft], p.X, p.Y);
  TBarCrack(FLeft).MouseMove([ssLeft], p.X, p.Y + 80);
  TBarCrack(FLeft).MouseUp(mbLeft, [], p.X, p.Y + 80);
  AssertSame('前提:拖到了后面', FExplorer, FLeft.Windows[1]);
  AssertTrue(FMgr.ResetLayout);
  Pump;
  AssertSame('顺序回到改之前', FExplorer, FLeft.Windows[0]);
end;

procedure TTyToolWindowManagerLiveTests.TestResetAfterACrossDropRestoresTheSide;
begin
  DragSearchToRight;
  AssertSame('前提:拖过去了', FRight, FSearch.Bar);
  AssertTrue(FMgr.ResetLayout);
  Pump;
  AssertSame('回到左栏', FLeft, FSearch.Bar);
  AssertSame('左栏当前页也回来了', FSearch, FLeft.ActiveWindow);
end;

procedure TTyToolWindowManagerLiveTests.TestResetAfterADirectParentChangeRestoresTheSide;
begin
  FSearch.Parent := FRight;
  AssertSame('前提:挪过去了', FRight, FSearch.Bar);
  AssertTrue(FMgr.ResetLayout);
  Pump;
  AssertSame('回到左栏', FLeft, FSearch.Bar);
end;

procedure TTyToolWindowManagerLiveTests.TestALoadAfterShowingIsQueued;
const
  S = 'TYTOOLLAYOUT/1|left=240,0|leftWins=WExplorer|leftActive=WExplorer' +
    '|right=240,0|rightWins=WOutline,WSearch|rightActive=WSearch|end';
begin
  AssertTrue('接受了', FMgr.LoadLayoutFromString(S));
  AssertSame('返回那一刻状态没变', FLeft, FSearch.Bar);
  Pump;
  AssertNothingRaised('排队的 Load');
  AssertSame('抽消息之后应用了', FRight, FSearch.Bar);
  AssertEquals('就是那一份', S, FMgr.SaveLayoutToString);
end;

procedure TTyToolWindowManagerLiveTests.TestAResetButtonInsideTheMovedWindowIsSafe;
begin
  { 默认布局里 Search 在右栏;此刻在左栏,「恢复布局」按钮就在 Search 的操作区里。 }
  FMgr.MoveWindow(FSearch, FRight);
  Pump;
  FMgr.CaptureDefaultLayout;
  FMgr.MoveWindow(FSearch, FLeft);
  Pump;
  AssertSame('前提:Search 在左栏', FLeft, FSearch.Bar);
  FBtn.OnClick := @BtnResets;
  FHandleKept := False;
  FClickAnswer := False;
  ClickReal(FBtn);
  AssertNothingRaised('按钮自己的点击里 ResetLayout');
  AssertTrue('前提:OnClick 跑了、Reset 接受了', FClickAnswer);
  AssertTrue('处理器返回前按钮的句柄没被销毁', FHandleKept);
  Pump;
  AssertNothingRaised('排队的 Reset');
  AssertSame('抽消息之后生效', FRight, FSearch.Bar);
end;

procedure TTyToolWindowManagerLiveTests.TestALoadReplacesAQueuedMove;
begin
  FMgr.MoveWindow(FSearch, FRight);
  AssertEquals('前提:移动排着', 1, FMgr.QueuedCountForTest);
  { 这一份不提 Search:它留在此刻所在的栏。 }
  AssertTrue(FMgr.LoadLayoutFromString('TYTOOLLAYOUT/1' +
    '|left=240,0|leftWins=WExplorer|leftActive=WExplorer|end'));
  AssertEquals('排着的只剩布局', 1, FMgr.QueuedCountForTest);
  Pump;
  AssertNothingRaised('排队的 Load');
  AssertSame('移动被覆盖:Search 还在左栏', FLeft, FSearch.Bar);
end;

procedure TTyToolWindowManagerLiveTests.TestACaptureInAMovingWindowDelaysTheLayoutOnce;
const
  S = 'TYTOOLLAYOUT/1|left=240,0|leftWins=WExplorer|leftActive=WExplorer' +
    '|right=240,0|rightWins=WOutline,WSearch|rightActive=WSearch|end';
begin
  AssertTrue(FMgr.LoadLayoutFromString(S));
  SetCaptureControl(FBtn);
  try
    RunAsyncOnce;
    AssertNothingRaised('第一轮');
    AssertSame('前提:执行那一刻捕获还在', FBtn, GetCaptureControl);
    AssertSame('捕获在要跨栏移动的 Search 里:再排一次,还没应用', FLeft, FSearch.Bar);
    RunAsyncOnce;
    AssertNothingRaised('第二轮');
    AssertSame('第二轮捕获还在也照做(只再排一次)', FRight, FSearch.Bar);
  finally
    SetCaptureControl(nil);
  end;
end;

procedure TTyToolWindowManagerLiveTests.TestFocusLeavesACollapsedBarForTheNextControl;
begin
  FEdit.SetFocus;
  AssertSame('前提:焦点在左栏当前页里', FEdit, FForm.ActiveControl);
  AssertTrue(FMgr.LoadLayoutFromString('TYTOOLLAYOUT/1' +
    '|left=240,1|leftWins=WExplorer,WSearch|leftActive=WSearch|end'));
  Pump;
  AssertNothingRaised('排队的 Load');
  AssertTrue('前提:左栏收起了、当前页没变', FLeft.Collapsed and (FLeft.ActiveWindow = FSearch));
  AssertTrue('焦点不是窗体本身', (FForm.ActiveControl <> nil) and (FForm.ActiveControl <> FForm));
  AssertFalse('焦点不在藏起来的窗口里', FSearch.ContainsControl(FForm.ActiveControl));
  AssertSame('交给 Tab 顺序里栏后面的那一个(SelectNext(栏)),不是平台挑的第一个',
    FOutside, FForm.ActiveControl);
end;

procedure TTyToolWindowManagerLiveTests.TestFocusStaysInAMovedWindow;
var
  first: TTyEdit;
begin
  { 正文里 Tab 顺序第一个是另一个编辑框:「进当前页的正文」会落到它身上,分得清。 }
  first := TTyEdit.Create(FForm);
  first.Parent := FSearch;
  first.SetBounds(8, 80, 120, 26);
  first.TabOrder := 0;
  Pump;
  FEdit.SetFocus;
  AssertSame('前提:焦点在 Search 的编辑框里', FEdit, FForm.ActiveControl);
  AssertTrue(FMgr.LoadLayoutFromString('TYTOOLLAYOUT/1' +
    '|left=240,0|leftWins=WExplorer|leftActive=WExplorer' +
    '|right=240,0|rightWins=WOutline,WSearch|rightActive=WSearch|end'));
  Pump;
  AssertNothingRaised('排队的 Load');
  AssertSame('前提:Search 到了右栏、是当前页', FSearch, FRight.ActiveWindow);
  AssertSame('原控件还聚焦得上:还给它', FEdit, FForm.ActiveControl);
end;

procedure TTyToolWindowManagerLiveTests.TestFocusFollowsIntoTheNewCurrentPage;
var
  inOutline: TTyEdit;
  headerBtn: TTyButton;
begin
  { Outline 标题行的操作区里一个按钮(Tab 顺序在正文前面):FocusFirst 跳过它落到正文,
    SelectNext(右栏) 会先落到它 —— 分得清。 }
  headerBtn := TTyButton.Create(FForm);
  headerBtn.Parent := FOutline.EnsureActions;
  inOutline := TTyEdit.Create(FForm);
  inOutline.Parent := FOutline;
  inOutline.SetBounds(8, 40, 120, 26);
  Pump;
  AssertTrue('前提:标题行的按钮聚焦得上', headerBtn.CanFocus);
  FEdit.SetFocus;
  AssertSame('前提:焦点在 Search 的编辑框里', FEdit, FForm.ActiveControl);
  AssertTrue(FMgr.LoadLayoutFromString('TYTOOLLAYOUT/1' +
    '|left=240,0|leftWins=WExplorer|leftActive=WExplorer' +
    '|right=240,0|rightWins=WOutline,WSearch|rightActive=WOutline|end'));
  Pump;
  AssertNothingRaised('排队的 Load');
  AssertSame('前提:Search 到了右栏、但当前页是 Outline', FOutline, FRight.ActiveWindow);
  AssertSame('焦点进了右栏当前页的正文(FocusFirst),不在窗体本身', inOutline,
    FForm.ActiveControl);
end;

procedure TTyToolWindowManagerLiveTests.TestADirectParentChangeKeepsTheFocus;
begin
  FEdit.SetFocus;
  AssertSame('前提:焦点在 Search 的编辑框里', FEdit, FForm.ActiveControl);
  FSearch.Parent := FRight;
  AssertNothingRaised('直接改 Parent');
  AssertSame('前提:挪过去了', FRight, FSearch.Bar);
  AssertSame('焦点还给编辑框', FEdit, FForm.ActiveControl);
end;

procedure TTyToolWindowManagerLiveTests.TestBarEventsSeeTheWindowAlreadyInPlace;
begin
  FRight.Collapsed := True;
  Pump;
  FRight.OnChange := @RightChangeSeesBounds;
  FSearch.Parent := FRight;
  AssertNothingRaised('直接改 Parent');
  AssertEquals('前提:发了一次', 'R.change;moved(WSearch,L,1);', FLog);
  AssertFalse('前提:展开了', FRight.Collapsed);
  AssertTrue('OnChange 里读到的已经是右栏内容区(事件在展开、对齐之后)',
    EqualRect(FRight.BarLayout.Content, FSeenBounds));
end;

initialization
  RegisterTest(TTyToolWindowManagerTests);
  RegisterTest(TTyToolWindowManagerLiveTests);
end.
