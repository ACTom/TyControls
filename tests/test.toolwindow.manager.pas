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
    function NewManager: TTyToolWindowManager;
    { 窗体上一条 APlacement 的栏,按 ACaptions 建窗口(Name = 'W' + 标题,布局要用;标题长短
      不一);先设 Placement 再加窗口。两个以上窗口时当前页是第二个(不是第一个,B 期地雷 12)。 }
    function NewBarOn(APlacement: TTyToolWindowPlacement;
      const ACaptions: array of string): TBarAccess;
  end;

  TTyToolWindowManagerTests = class(TTyToolWindowManagerFixture)
  published
    procedure TestOneBarPerPlacementIsUsable;
    procedure TestEveryBarSharingAPlacementIsUnusable;
    procedure TestLeavingTheManagerOrBeingFreedEndsAConflict;
    procedure TestFreeingTheManagerClearsEveryBar;
    procedure TestManagerIsAPublishedReference;
  end;

implementation

function TTyToolWindowManagerFixture.NewManager: TTyToolWindowManager;
begin
  Result := TTyToolWindowManager.Create(FForm);
end;

function TTyToolWindowManagerFixture.NewBarOn(APlacement: TTyToolWindowPlacement;
  const ACaptions: array of string): TBarAccess;
var
  i: Integer;
  w: TProbeWindow;
begin
  Result := TBarAccess.Create(FForm);
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

initialization
  RegisterTest(TTyToolWindowManagerTests);
end.
