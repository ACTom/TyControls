unit test.toolwindow.manager;
{$mode objfpc}{$H+}

{ TTyToolWindowManager(spec §2 / §9.9 / §10.6):栏的注册与 Placement 冲突、CanMoveWindow、
  MoveWindow 的同步路径与事件、运行时直接改 Parent 的簿记。夹具在 test.toolwindow.bar
  (TTyToolWindowBarFixture)。无头的窗体永远不 Showing,MoveWindow 恒走同步那一支;排队、
  焦点、Showing 之后的时机在本单元的 TTyToolWindowManagerLiveTests(真句柄)。 }

interface

uses
  Classes, SysUtils, Types, TypInfo, Controls, Forms, Graphics, LCLType, LCLProc, LMessages,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.ToolWindows,
  tyControls.ToolWindows.Layout,
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

implementation

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

initialization
  RegisterTest(TTyToolWindowManagerTests);
end.
