unit test.toolwindow.layoutapply;
{$mode objfpc}{$H+}

{ 布局的保存 / 读取 / 恢复(spec §10.1 / §10.2 保存 / §10.4 / §10.7):同步应用的批次。
  夹具:左栏 Explorer / Search(当前页 Search)、右栏 Outline、底栏 Problems / Output / Terminal
  (当前页 Output),窗口的 Name 是 'W' + 标题,都注册在一个 manager 上;栏事件、OnWindowMoved
  记进 FLog。无头的窗体永远不 Showing:Load / Reset 恒走同步那一支;挂起、排队、焦点在
  Task 13 的那几条(真句柄的在 test.toolwindow.manager 的 Live 套件)。 }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, LCLType,
  fpcunit, testregistry,
  tyControls.Controller, tyControls.ToolWindows, tyControls.ToolWindows.Layout,
  test.toolwindow.window, test.toolwindow.bar, test.toolwindow.manager;

type
  TTyToolWindowLayoutApplyTests = class(TTyToolWindowManagerFixture)
  private
    FMgr: TTyToolWindowManager;
    FLeft, FRight, FBottom: TBarAccess;
    FApplied: Integer;
    procedure CountApplied(Sender: TObject);
    function Win(const ACaption: string): TProbeWindow;
    procedure WatchShowHide(AWin: TTyToolWindow);
  protected
    procedure SetUp; override;
  published
    procedure TestARoundTripRestoresEverything;
    procedure TestEveryPrefixIsRejectedAndChangesNothing;
    procedure TestBadStringsChangeNothing;
    procedure TestSaveSkipsDuplicateAndUnnamedWindows;
    procedure TestTheGatesRefuseLoadAndReset;
    procedure TestTheBatchFiresNoBarOrMoveEvents;
    procedure TestShowAndHideStillFireWithoutAFallbackFlash;
    procedure TestAMovedInPageThatIsNotActiveIsNotShown;
    procedure TestAMaximizedBottomBarIsRestoredFirst;
    procedure TestLoadCancelsADrag;
    procedure TestAGroupForAMissingBarIsIgnored;
    procedure TestResetReturnsToTheCapturedLayout;
    procedure TestDpiChangesDoNotReachTheString;
    procedure TestSaveWritesTheRestoredSizeWhileMaximized;
    { 开工前问题 14:从 manager 自己发的事件里重入 Load / Reset 答 False。 }
    procedure TestLoadOrResetFromTheManagersOwnEventsIsRefused;
  private
    FInner: Integer;      { -1 = 处理器没跑;0 / 1 = 处理器里那一次调用的答案 }
    procedure LoadFromApplied(Sender: TObject);
    procedure ResetFromMoved(Sender: TObject; AWindow: TTyToolWindow;
      ASourceBar: TTyToolWindowBar; AOldIndex: Integer);
  end;

implementation

type
  { ParentFont 是 protected。 }
  TControlCrack = class(TControl);

  { 在 manager 析构、csDestroying 已经置上的时候调 Load / Reset。 }
  TLayoutOnFree = class(TComponent)
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); override;
  public
    Target: TTyToolWindowManager;
    Called: Boolean;
    LoadAnswer, ResetAnswer: Boolean;
  end;

procedure TLayoutOnFree.Notification(AComponent: TComponent; Operation: TOperation);
begin
  inherited Notification(AComponent, Operation);
  if (Operation = opRemove) and (AComponent = Target) then
  begin
    Called := True;
    LoadAnswer := Target.LoadLayoutFromString('TYTOOLLAYOUT/1|end');
    ResetAnswer := Target.ResetLayout;
  end;
end;

procedure TTyToolWindowLayoutApplyTests.SetUp;
begin
  inherited SetUp;
  FForm.SetBounds(0, 0, 3000, 1000);
  FMgr := NewManager;
  FMgr.OnWindowMoved := @LogMoved;
  FMgr.OnLayoutApplied := @CountApplied;
  FLeft := NewBarOn(twpLeft, ['Explorer', 'Search']);
  FRight := NewBarOn(twpRight, ['Outline']);
  FBottom := NewBarOn(twpBottom, ['Problems', 'Output', 'Terminal']);
  FLeft.Manager := FMgr;
  FRight.Manager := FMgr;
  FBottom.Manager := FMgr;
  LogBarEvents(FLeft);
  LogBarEvents(FRight);
  LogBarEvents(FBottom);
  FApplied := 0;
  FLog := '';
  FOrder := '';
end;

procedure TTyToolWindowLayoutApplyTests.CountApplied(Sender: TObject);
begin
  Inc(FApplied);
end;

function TTyToolWindowLayoutApplyTests.Win(const ACaption: string): TProbeWindow;
begin
  Result := FForm.FindComponent('W' + ACaption) as TProbeWindow;
  AssertNotNull('前提:有窗口 ' + ACaption, Result);
end;

procedure TTyToolWindowLayoutApplyTests.WatchShowHide(AWin: TTyToolWindow);
begin
  AWin.OnShow := @HandleShowOrder;
  AWin.OnHide := @HandleHideOrder;
end;

procedure TTyToolWindowLayoutApplyTests.TestARoundTripRestoresEverything;
var
  u: TProbeWindow;
  s: string;
begin
  { 起点是非默认状态:调过顺序、一个窗口跨了侧、一侧收起、尺寸改过、当前页无名。 }
  u := TProbeWindow.Create(FForm);        { 无名窗口,进栏即成为当前页 }
  u.Parent := FLeft;
  u.WindowIndex := 0;
  FMgr.MoveWindow(Win('Search'), FRight);
  FRight.Collapsed := True;
  FBottom.ExpandedSize := 180;
  AssertSame('前提:左栏当前页是无名窗口', TTyToolWindow(u), FLeft.ActiveWindow);
  s := FMgr.SaveLayoutToString;
  AssertEquals('前提:串的样子',
    'TYTOOLLAYOUT/1|left=240,0|leftWins=WExplorer|leftActive=' +
    '|right=240,1|rightWins=WOutline,WSearch|rightActive=WSearch' +
    '|bottom=180,0|bottomWins=WProblems,WOutput,WTerminal|bottomActive=WOutput|end', s);
  { 全部改回去(无名的当前页读不回来,留着它)。 }
  FMgr.MoveWindow(Win('Search'), FLeft, 1);
  FRight.Collapsed := False;
  FBottom.ExpandedSize := 240;
  FLeft.ActiveWindow := u;
  AssertTrue('前提:状态挪离了 s', FMgr.SaveLayoutToString <> s);
  AssertTrue('读得进', FMgr.LoadLayoutFromString(s));
  AssertEquals('Save 逐字等于 s', s, FMgr.SaveLayoutToString);
  AssertSame('Search 回到右栏', TTyToolWindowBar(FRight), Win('Search').Bar);
  AssertSame('排在 Outline 后面', TTyToolWindow(Win('Search')), FRight.Windows[1]);
  AssertSame('右栏当前页', TTyToolWindow(Win('Search')), FRight.ActiveWindow);
  AssertTrue('右栏收起', FRight.Collapsed);
  AssertEquals('底栏尺寸', 180, FBottom.ExpandedSize);
  AssertSame('左栏:有名的在前', TTyToolWindow(Win('Explorer')), FLeft.Windows[0]);
  AssertSame('左栏:无名的留在后面', TTyToolWindow(u), FLeft.Windows[1]);
  AssertSame('无名当前页:左栏当前页不变', TTyToolWindow(u), FLeft.ActiveWindow);
end;

procedure TTyToolWindowLayoutApplyTests.TestEveryPrefixIsRejectedAndChangesNothing;
var
  s, before: string;
  i: Integer;
begin
  FMgr.MoveWindow(Win('Search'), FRight);
  FBottom.ExpandedSize := 180;           { 最后一组放多位数尺寸 }
  s := FMgr.SaveLayoutToString;
  { 状态先挪离 s:不挪的话,前缀即使被应用了照样绿。 }
  FMgr.MoveWindow(Win('Search'), FLeft);
  FBottom.ExpandedSize := 240;
  before := FMgr.SaveLayoutToString;
  AssertTrue('前提:状态挪离了 s', before <> s);
  for i := 1 to Length(s) - 1 do
  begin
    AssertFalse('前缀 ' + IntToStr(i) + ' 答 False', FMgr.LoadLayoutFromString(Copy(s, 1, i)));
    AssertEquals('前缀 ' + IntToStr(i) + ' 之后状态不变', before, FMgr.SaveLayoutToString);
  end;
  AssertEquals('一次都没应用', 0, FApplied);
end;

procedure TTyToolWindowLayoutApplyTests.TestBadStringsChangeNothing;
var
  before: string;

  procedure Check(const AMsg, AText: string);
  begin
    AssertFalse(AMsg + ' 答 False', FMgr.LoadLayoutFromString(AText));
    AssertEquals(AMsg + ' 之后状态不变', before, FMgr.SaveLayoutToString);
  end;

begin
  before := FMgr.SaveLayoutToString;
  Check('R1', 'TYTOOLLAYOUT/2|left=100,1|leftWins=WSearch|leftActive=WSearch|end');
  Check('R3', 'TYTOOLLAYOUT/1|left=100,1|leftWins=WSearch|leftActive=WSearch');
  Check('R6', 'TYTOOLLAYOUT/1|left=100,1|leftWins=WSearch|end');
  Check('R8', 'TYTOOLLAYOUT/1|left=$F0,1|leftWins=WSearch|leftActive=WSearch|end');
  Check('R15', 'TYTOOLLAYOUT/1|left=100,1|leftWins=WSearch|leftActive=WSearch' +
    '|right=100,1|rightWins=wsearch|rightActive=|end');
  Check('R17', 'TYTOOLLAYOUT/1|left=100,1|leftWins=WSearch,,WExplorer|leftActive=|end');
  Check('R24', '');
  AssertEquals('一次都没应用', 0, FApplied);
end;

procedure TTyToolWindowLayoutApplyTests.TestSaveSkipsDuplicateAndUnnamedWindows;
var
  dup: TProbeWindow;
  u: TProbeWindow;
  s: string;
begin
  { 两个窗口 Owner 不同,名字可以一样。 }
  dup := TProbeWindow.Create(nil);
  try
    dup.Name := 'WExplorer';
    dup.Parent := FRight;
    u := TProbeWindow.Create(FForm);
    u.Parent := FBottom;
    s := FMgr.SaveLayoutToString;
    AssertEquals('重名的两个都不写', 0, Pos('WExplorer', s));
    AssertTrue('别的照写', Pos('WSearch', s) > 0);
    AssertTrue('自己写出来的串读得回来', FMgr.LoadLayoutFromString(s));
  finally
    dup.Free;
  end;
end;

procedure TTyToolWindowLayoutApplyTests.TestTheGatesRefuseLoadAndReset;
var
  dm, bare, dying: TTyToolWindowManager;
  b2, b3: TBarAccess;
  watcher: TLayoutOnFree;
begin
  { 设计期的 manager(注册着一条栏)。 }
  dm := TTyToolWindowManager.Create(nil);
  try
    TDesignOwner(dm).MarkDesigning;
    b2 := NewBarOn(twpLeft, ['Git']);
    b2.Manager := dm;
    AssertFalse('设计期:Load', dm.LoadLayoutFromString('TYTOOLLAYOUT/1|end'));
    AssertFalse('设计期:Reset', dm.ResetLayout);
  finally
    dm.Free;
  end;
  { 没有注册栏。 }
  bare := NewManager;
  AssertFalse('没有注册栏:Load', bare.LoadLayoutFromString('TYTOOLLAYOUT/1|end'));
  AssertFalse('没有注册栏:Reset', bare.ResetLayout);
  { 正在释放。 }
  dying := NewManager;
  b3 := NewBarOn(twpLeft, ['Debug']);
  b3.Manager := dying;
  watcher := TLayoutOnFree.Create(nil);
  try
    watcher.Target := dying;
    dying.FreeNotification(watcher);
    dying.Free;
    AssertTrue('前提:释放中问过了', watcher.Called);
    AssertFalse('正在释放:Load', watcher.LoadAnswer);
    AssertFalse('正在释放:Reset', watcher.ResetAnswer);
  finally
    watcher.Free;
  end;
  AssertTrue('对照:正常的 manager 读得进', FMgr.LoadLayoutFromString('TYTOOLLAYOUT/1|end'));
end;

procedure TTyToolWindowLayoutApplyTests.TestTheBatchFiresNoBarOrMoveEvents;
begin
  AssertTrue(FMgr.LoadLayoutFromString('TYTOOLLAYOUT/1' +
    '|left=200,1|leftWins=WExplorer|leftActive=WExplorer' +
    '|right=300,0|rightWins=WSearch,WOutline|rightActive=WSearch' +
    '|bottom=150,1|bottomWins=WTerminal,WProblems,WOutput|bottomActive=WTerminal|end'));
  AssertSame('前提:应用了(Search 跨到右栏)', TTyToolWindowBar(FRight), Win('Search').Bar);
  AssertTrue('前提:应用了(左栏收起)', FLeft.Collapsed);
  AssertEquals('批次里没有栏事件,也没有 OnWindowMoved', '', FLog);
  AssertEquals('不问 OnCanMoveWindow', 0, FCanCalls);
  AssertEquals('OnLayoutApplied 恰好一次', 1, FApplied);
end;

procedure TTyToolWindowLayoutApplyTests.TestShowAndHideStillFireWithoutAFallbackFlash;
var
  git: TProbeWindow;
begin
  { 左栏 Explorer / Search / Git,当前页 Git。串把 Git 挪到右栏、左栏当前页定成 Explorer:
    Git 离开时左栏的回落页(Search)不许先显示一下。 }
  git := TProbeWindow.Create(FForm);
  git.Name := 'WGit';
  git.Parent := FLeft;
  AssertSame('前提:Git 是左栏当前页', TTyToolWindow(git), FLeft.ActiveWindow);
  WatchShowHide(Win('Explorer'));
  WatchShowHide(Win('Search'));
  WatchShowHide(git);
  WatchShowHide(Win('Outline'));
  FOrder := '';
  AssertTrue(FMgr.LoadLayoutFromString('TYTOOLLAYOUT/1' +
    '|left=240,0|leftWins=WExplorer,WSearch|leftActive=WExplorer' +
    '|right=240,0|rightWins=WGit,WOutline|rightActive=WGit|end'));
  AssertSame('前提:Git 到了右栏', TTyToolWindowBar(FRight), git.Bar);
  AssertEquals('照常发:Explorer 显示,Outline 藏起;回落页 Search 没有闪一下',
    'show WExplorer;hide WOutline;', FOrder);
  { 同一条栏里换当前页:旧的恰好藏一次、新的恰好显示一次。 }
  FOrder := '';
  AssertTrue(FMgr.LoadLayoutFromString('TYTOOLLAYOUT/1' +
    '|left=240,0|leftWins=WExplorer,WSearch|leftActive=WSearch|end'));
  AssertEquals('换当前页', 'show WSearch;hide WExplorer;', FOrder);
end;

procedure TTyToolWindowLayoutApplyTests.TestAMovedInPageThatIsNotActiveIsNotShown;
begin
  WatchShowHide(Win('Explorer'));
  FOrder := '';
  AssertTrue(FMgr.LoadLayoutFromString('TYTOOLLAYOUT/1' +
    '|right=240,0|rightWins=WOutline,WExplorer|rightActive=WOutline|end'));
  AssertSame('前提:Explorer 到了右栏', TTyToolWindowBar(FRight), Win('Explorer').Bar);
  AssertSame('前提:右栏当前页还是 Outline', TTyToolWindow(Win('Outline')), FRight.ActiveWindow);
  AssertEquals('挪进来、又不是当前页:没有 show', '', FOrder);
  AssertFalse('它藏着', Win('Explorer').Visible);
end;

procedure TTyToolWindowLayoutApplyTests.TestAMaximizedBottomBarIsRestoredFirst;
begin
  FBottom.Maximized := True;
  AssertTrue('前提:最大化了', FBottom.Maximized);
  AssertTrue(FMgr.LoadLayoutFromString('TYTOOLLAYOUT/1' +
    '|bottom=170,0|bottomWins=WProblems,WOutput,WTerminal|bottomActive=WOutput|end'));
  AssertFalse('先还原', FBottom.Maximized);
  AssertEquals('尺寸是串里的', 170, FBottom.ExpandedSize);
end;

procedure TTyToolWindowLayoutApplyTests.TestLoadCancelsADrag;
var
  p: TPoint;
begin
  p := FLeft.StripItemRect(0).CenterPoint;
  FLeft.CallMouseDown(p.X, p.Y);
  FLeft.CallMouseMove(p.X + 10, p.Y);
  AssertTrue('前提:在拖', FMgr.IsDragging);
  AssertTrue(FMgr.LoadLayoutFromString('TYTOOLLAYOUT/1|end'));
  AssertFalse('Load 取消拖动', FMgr.IsDragging);
end;

procedure TTyToolWindowLayoutApplyTests.TestAGroupForAMissingBarIsIgnored;
begin
  FBottom.Manager := nil;
  AssertTrue('带底栏组的串读进没底栏的程序', FMgr.LoadLayoutFromString('TYTOOLLAYOUT/1' +
    '|left=210,1|leftWins=WSearch,WExplorer|leftActive=WSearch' +
    '|right=240,0|rightWins=WOutline|rightActive=WOutline' +
    '|bottom=150,1|bottomWins=WProblems|bottomActive=WProblems|end'));
  AssertSame('左栏照应用', TTyToolWindow(Win('Search')), FLeft.Windows[0]);
  AssertEquals('左栏尺寸', 210, FLeft.ExpandedSize);
  AssertTrue('左栏收起', FLeft.Collapsed);
  AssertEquals('底栏不碰', TyToolWindowDefaultExpandedSize, FBottom.ExpandedSize);
  AssertFalse('底栏不碰', FBottom.Collapsed);
end;

procedure TTyToolWindowLayoutApplyTests.TestResetReturnsToTheCapturedLayout;
var
  s0: string;
begin
  s0 := FMgr.SaveLayoutToString;
  AssertTrue('第一次 Reset:先记下此刻', FMgr.ResetLayout);
  AssertEquals('第一次 Reset 什么都没变', s0, FMgr.SaveLayoutToString);
  FMgr.MoveWindow(Win('Search'), FRight);
  FLeft.Collapsed := True;
  FBottom.ExpandedSize := 300;
  AssertTrue(FMgr.ResetLayout);
  AssertEquals('回到记下的样子', s0, FMgr.SaveLayoutToString);
  AssertSame('Search 回到左栏', TTyToolWindowBar(FLeft), Win('Search').Bar);
end;

procedure TTyToolWindowLayoutApplyTests.TestDpiChangesDoNotReachTheString;
var
  s: string;
  bars: array[0..2] of TBarAccess;
  i: Integer;
begin
  bars[0] := FLeft;
  bars[1] := FRight;
  bars[2] := FBottom;
  for i := 0 to 2 do
  begin
    TControlCrack(bars[i]).ParentFont := False;
    bars[i].Font.PixelsPerInch := 96;
  end;
  FLeft.ExpandedSize := 203;
  s := FMgr.SaveLayoutToString;
  for i := 0 to 2 do bars[i].AutoAdjustLayout(lapAutoAdjustForDPI, 96, 144, 0, 0);
  AssertEquals('前提:换了密度', 144, FLeft.Font.PixelsPerInch);
  AssertEquals('144 下 Save 不变(写的是逻辑尺寸)', s, FMgr.SaveLayoutToString);
  AssertTrue(FMgr.LoadLayoutFromString('TYTOOLLAYOUT/1' +
    '|left=210,0|leftWins=WExplorer,WSearch|leftActive=WSearch|end'));
  AssertEquals('144 下 Load:设备宽 = MulDiv(ExpandedSize, 144, 96) + 固定部分',
    FLeft.StripSizePx + FLeft.EdgeSizePx + 2 * FLeft.ChromeInsetPx + MulDiv(210, 144, 96),
    FLeft.Width);
  FLeft.ExpandedSize := 203;
  for i := 0 to 2 do bars[i].AutoAdjustLayout(lapAutoAdjustForDPI, 144, 96, 0, 0);
  AssertEquals('96 → 144 → 96 之后 Save 不变', s, FMgr.SaveLayoutToString);
end;

procedure TTyToolWindowLayoutApplyTests.TestSaveWritesTheRestoredSizeWhileMaximized;
begin
  FBottom.ExpandedSize := 190;
  FBottom.Maximized := True;
  AssertTrue('前提:最大化之后的高比展开尺寸大', FBottom.Height > 190 + FBottom.EdgeSizePx);
  AssertTrue('不保存最大化:写的是还原高度',
    Pos('|bottom=190,0|', FMgr.SaveLayoutToString) > 0);
end;

procedure TTyToolWindowLayoutApplyTests.LoadFromApplied(Sender: TObject);
begin
  if FInner <> -1 then Exit;
  FInner := -2;
  FInner := Ord(FMgr.LoadLayoutFromString('TYTOOLLAYOUT/1|end'));
end;

procedure TTyToolWindowLayoutApplyTests.ResetFromMoved(Sender: TObject; AWindow: TTyToolWindow;
  ASourceBar: TTyToolWindowBar; AOldIndex: Integer);
begin
  if FInner <> -1 then Exit;
  FInner := -2;
  FInner := Ord(FMgr.ResetLayout);
end;

procedure TTyToolWindowLayoutApplyTests.TestLoadOrResetFromTheManagersOwnEventsIsRefused;
begin
  FInner := -1;
  FMgr.OnLayoutApplied := @LoadFromApplied;
  AssertTrue(FMgr.LoadLayoutFromString('TYTOOLLAYOUT/1|end'));
  AssertEquals('OnLayoutApplied 里再 Load:答 False', 0, FInner);
  FInner := -1;
  FMgr.OnWindowMoved := @ResetFromMoved;
  Win('Search').WindowIndex := 0;
  AssertEquals('OnWindowMoved 里 Reset:答 False', 0, FInner);
end;

initialization
  RegisterTest(TTyToolWindowLayoutApplyTests);
end.
