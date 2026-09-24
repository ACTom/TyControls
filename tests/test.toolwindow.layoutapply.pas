unit test.toolwindow.layoutapply;
{$mode objfpc}{$H+}

{ 布局的保存 / 读取 / 恢复(spec §10.1 / §10.2 保存 / §10.4 / §10.7):同步应用的批次。
  夹具:左栏 Explorer / Search(当前页 Search)、右栏 Outline、底栏 Problems / Output / Terminal
  (当前页 Output),窗口的 Name 是 'W' + 标题,都注册在一个 manager 上;栏事件、OnWindowMoved
  记进 FLog。无头的窗体永远不 Showing:Load / Reset 恒走同步那一支。加载中挂起、收尾、默认
  布局(spec §10.5)在本单元后半段(流式往返);Showing 之后的排队和焦点要真句柄,在
  test.toolwindow.manager 的 Live 套件。 }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, LCLType,
  fpcunit, testregistry,
  tyControls.Controller, tyControls.ToolWindows, tyControls.ToolWindows.Layout,
  tyControls.ToolWindows.Manager,
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
    { 从 manager 自己发的事件里重入 Load / Reset 答 False(同 MoveWindow 的 spec §9.9)。 }
    procedure TestLoadOrResetFromTheManagersOwnEventsIsRefused;
    { spec §10.5:加载中挂起、最后一个 Loaded 收尾、默认布局。 }
    procedure TestALoadDuringStreamingWaitsForTheEnd;
    procedure TestThePendingPlanIsSilentAndQueuesOnLayoutApplied;
    procedure TestAManagerStreamedFirstIsFinishedByTheLastBar;
    procedure TestOnlyTheLastPendingCallApplies;
    procedure TestABadStringWhileLoadingIsRefusedAtOnce;
    procedure TestTheStreamedLayoutIsTheDefault;
    procedure TestAnInheritedFormResetsToTheDescendantsValues;
    procedure TestACodeBuiltManagerCapturesBeforeTheFirstLoad;
    procedure TestAnExplicitCaptureIsKeptByLoad;
    { 批次里(某一页的 OnShow)的重入:MoveWindow / Load 答 False,CaptureDefaultLayout 不记,
      直接改 Parent 不簿记,批次不把别的栏的窗口当成本栏的当前页。 }
    procedure TestMoveLoadAndCaptureFromAPageEventInsideTheBatchAreRefused;
    procedure TestADirectParentChangeInsideTheBatchLeavesEveryBarWhole;
    { 某一条栏进批次时抛异常:进了门的都出门,没进门的不多解一层。 }
    procedure TestABarFailingToEnterTheBatchLeavesNoBarInIt;
    { 从 TStringList.Text / 文件读回来的串:结尾换行、开头 BOM 照收,中间照旧严格。 }
    procedure TestLoadToleratesTheStorageShell;
    { .lfm 里只有 manager、栏在 FormCreate 里用代码挂:Loaded 那一刻不记空布局。 }
    procedure TestAStreamedManagerWithCodeBuiltBarsResetsToTheBuiltLayout;
    { 窗体还没显示(FormCreate 里读布局):第 7 步不抛异常、ActiveControl 不停在被藏起来的
      控件上,原控件还聚焦得上时还给它(所以这一步不能在没显示的窗体上跳过)。 }
    procedure TestTheFocusStepOnAHiddenFormIsSafeAndRestores;
  private
    FInner: Integer;      { -1 = 处理器没跑;0 / 1 = 处理器里那一次调用的答案 }
    FInnerLoad: Integer;
    FInnerDone: Boolean;
    procedure ReenterFromShow(Sender: TObject);
    procedure ReparentFromShow(Sender: TObject);
    { 每条栏至多一页显示着、当前页就在这条栏里。 }
    procedure AssertEveryBarWhole(const AMsg: string);
    procedure LoadFromApplied(Sender: TObject);
    procedure ResetFromMoved(Sender: TObject; AWindow: TTyToolWindow;
      ASourceBar: TTyToolWindowBar; AOldIndex: Integer);
  end;

implementation

type
  { ParentFont 是 protected。 }
  TControlCrack = class(TControl);
  { Loading / Loaded 是 protected:模拟「从 .lfm 读进来」。 }
  TComponentCrack = class(TComponent);

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

{ --- 批次里的重入与异常(spec §10.4) ------------------------------------------------ }

procedure TTyToolWindowLayoutApplyTests.ReenterFromShow(Sender: TObject);
begin
  if FInnerDone then Exit;
  FInnerDone := True;
  FInner := Ord(FMgr.MoveWindow(Win('Outline'), FLeft));
  FInnerLoad := Ord(FMgr.LoadLayoutFromString('TYTOOLLAYOUT/1|end'));
  FMgr.CaptureDefaultLayout;
end;

procedure TTyToolWindowLayoutApplyTests.ReparentFromShow(Sender: TObject);
begin
  if FInnerDone then Exit;
  FInnerDone := True;
  Win('Outline').Parent := FLeft;
end;

procedure TTyToolWindowLayoutApplyTests.AssertEveryBarWhole(const AMsg: string);
var
  bars: array[0..2] of TBarAccess;
  i, k, shown: Integer;
begin
  bars[0] := FLeft;
  bars[1] := FRight;
  bars[2] := FBottom;
  for i := 0 to 2 do
  begin
    shown := 0;
    for k := 0 to bars[i].WindowCount - 1 do
      if bars[i].Windows[k].Visible then Inc(shown);
    AssertTrue(AMsg + ':' + bars[i].Name + ' 至多一页显示着', shown <= 1);
    AssertTrue(AMsg + ':' + bars[i].Name + ' 的当前页就在它里面',
      (bars[i].ActiveWindow = nil) or (bars[i].IndexOfWindow(bars[i].ActiveWindow) >= 0));
  end;
end;

procedure TTyToolWindowLayoutApplyTests.TestMoveLoadAndCaptureFromAPageEventInsideTheBatchAreRefused;
var
  s0: string;
begin
  s0 := FMgr.SaveLayoutToString;
  FInner := -1;
  FInnerLoad := -1;
  FInnerDone := False;
  Win('Explorer').OnShow := @ReenterFromShow;
  { 左栏换到 Explorer:它的 OnShow 在批次中间(5b 左栏切页)发。 }
  AssertTrue(FMgr.LoadLayoutFromString('TYTOOLLAYOUT/1' +
    '|left=240,0|leftWins=WExplorer,WSearch|leftActive=WExplorer' +
    '|right=240,0|rightWins=WOutline|rightActive=WOutline|end'));
  AssertTrue('前提:处理器跑了', FInnerDone);
  AssertEquals('批次里 MoveWindow 答 False', 0, FInner);
  AssertEquals('批次里 Load 答 False', 0, FInnerLoad);
  AssertSame('Outline 没被挪', TTyToolWindowBar(FRight), Win('Outline').Bar);
  AssertEveryBarWhole('批次之后');
  { 默认布局是 Load 进门时记下的那一份,不是批次里应用了一半的样子。 }
  Win('Explorer').OnShow := nil;
  AssertTrue(FMgr.ResetLayout);
  AssertEquals('批次里的 CaptureDefaultLayout 没有生效', s0, FMgr.SaveLayoutToString);
end;

procedure TTyToolWindowLayoutApplyTests.TestADirectParentChangeInsideTheBatchLeavesEveryBarWhole;
begin
  FInnerDone := False;
  Win('Explorer').OnShow := @ReparentFromShow;
  AssertTrue(FMgr.LoadLayoutFromString('TYTOOLLAYOUT/1' +
    '|left=240,0|leftWins=WExplorer,WSearch|leftActive=WExplorer' +
    '|right=240,0|rightWins=WOutline|rightActive=WOutline|end'));
  AssertTrue('前提:处理器跑了', FInnerDone);
  AssertSame('前提:直接改 Parent 拦不住', TTyToolWindowBar(FLeft), Win('Outline').Bar);
  AssertEquals('批次里的直接改 Parent 不簿记:没有 OnWindowMoved,也没有栏事件', '', FLog);
  AssertEveryBarWhole('批次之后');
  AssertTrue('右栏空了,没有当前页(不是左栏的 Outline)', FRight.ActiveWindow = nil);
end;

procedure TTyToolWindowLayoutApplyTests.TestABarFailingToEnterTheBatchLeavesNoBarInIt;
var
  bars: array[0..2] of TBarAccess;
  locks: array[0..2] of Integer;
  i: Integer;
  raised: Boolean;
begin
  bars[0] := FLeft;
  bars[1] := FRight;
  bars[2] := FBottom;
  for i := 0 to 2 do locks[i] := bars[i].AlignLockForTest;
  { 注册顺序 L、R、B:左栏进了门,右栏进门时抛。 }
  FRight.RaiseOnLayoutBatch := True;
  raised := False;
  try
    FMgr.LoadLayoutFromString('TYTOOLLAYOUT/1|left=200,1|leftWins=WExplorer|leftActive=|end');
  except
    on Exception do raised := True;
  end;
  FRight.RaiseOnLayoutBatch := False;
  AssertTrue('前提:抛出来了', raised);
  for i := 0 to 2 do
  begin
    AssertEquals(bars[i].Name + ' 不在批次里', 0, bars[i].LayoutBatchForTest);
    AssertEquals(bars[i].Name + ' 的对齐锁回到原样', locks[i], bars[i].AlignLockForTest);
  end;
  { 批次层数真的清了:用户看得见的收起照发事件。 }
  FLog := '';
  FLeft.Collapsed := True;
  AssertEquals('之后的收起照常发事件', 'L.collapse;', FLog);
end;

procedure TTyToolWindowLayoutApplyTests.TestTheFocusStepOnAHiddenFormIsSafeAndRestores;
var
  e, after: TBodyChild;
  raised: string;
begin
  e := TBodyChild.Create(FForm);
  e.Parent := Win('Search');
  e.TabStop := True;
  { Tab 顺序里排在栏后面、聚焦得上的一个:显示着的窗体上焦点该交给它(SelectNext(栏))。 }
  after := TBodyChild.Create(FForm);
  after.Parent := FForm;
  after.TabStop := True;
  after.SetBounds(900, 10, 50, 20);
  FForm.ActiveControl := e;
  AssertFalse('前提:无头的窗体没显示(FormCreate 里读布局)', FForm.Showing);
  AssertTrue('前提:两个都聚焦得上', e.CanFocus and after.CanFocus);
  raised := '';
  try
    AssertTrue(FMgr.LoadLayoutFromString('TYTOOLLAYOUT/1' +
      '|left=240,1|leftWins=WExplorer,WSearch|leftActive=WSearch|end'));
  except
    on x: Exception do raised := x.ClassName + ': ' + x.Message;
  end;
  { 没显示的窗体上 SelectNext 挑到 after 就 SetFocus,经 FocusControl 去聚焦窗体本身 —— 抛。 }
  AssertEquals('没显示的窗体:读布局不因为搬焦点抛异常', '', raised);
  AssertTrue('前提:左栏收起了,Search 藏着', FLeft.Collapsed and not e.CanFocus);
  AssertFalse('ActiveControl 不停在藏起来的控件上', FForm.ActiveControl = e);
  { 反过来:Search 跟着布局挪到右栏、仍是当前页 —— 换父时 LCL 清掉了 ActiveControl,第 7 步
    要还给它(没显示的窗体也一样,否则窗体显示时焦点落到别处)。 }
  AssertTrue(FMgr.LoadLayoutFromString('TYTOOLLAYOUT/1' +
    '|left=240,0|leftWins=WExplorer|leftActive=WExplorer' +
    '|right=240,0|rightWins=WOutline,WSearch|rightActive=WSearch|end'));
  FForm.ActiveControl := e;
  AssertTrue(FMgr.LoadLayoutFromString('TYTOOLLAYOUT/1' +
    '|left=240,0|leftWins=WExplorer,WSearch|leftActive=WSearch' +
    '|right=240,0|rightWins=WOutline|rightActive=WOutline|end'));
  AssertSame('前提:Search 回到左栏、是当前页', TTyToolWindow(Win('Search')), FLeft.ActiveWindow);
  AssertSame('原控件还聚焦得上:ActiveControl 还给它', TWinControl(e), FForm.ActiveControl);
end;

procedure TTyToolWindowLayoutApplyTests.TestLoadToleratesTheStorageShell;
const
  Bom = #$EF#$BB#$BF;
var
  s, before: string;
  sl: TStringList;
begin
  FMgr.MoveWindow(Win('Search'), FRight);
  FBottom.ExpandedSize := 180;
  s := FMgr.SaveLayoutToString;
  FMgr.MoveWindow(Win('Search'), FLeft);
  FBottom.ExpandedSize := 240;
  before := FMgr.SaveLayoutToString;
  AssertTrue('前提:状态挪离了 s', before <> s);
  sl := TStringList.Create;
  try
    sl.Text := s;
    AssertTrue('TStringList.Text(结尾带换行)读得进', FMgr.LoadLayoutFromString(sl.Text));
    AssertEquals('读进来的就是 s', s, FMgr.SaveLayoutToString);
  finally
    sl.Free;
  end;
  AssertTrue(FMgr.LoadLayoutFromString(before));
  AssertTrue('开头 BOM、结尾 CRLF 和空白读得进',
    FMgr.LoadLayoutFromString(Bom + s + #13#10'  '#9));
  AssertEquals('读进来的就是 s', s, FMgr.SaveLayoutToString);
  AssertTrue(FMgr.LoadLayoutFromString(before));
  AssertFalse('开头的空白照旧拒', FMgr.LoadLayoutFromString(' ' + s));
  AssertFalse('中间的空白照旧拒',
    FMgr.LoadLayoutFromString(StringReplace(s, '|end', ' |end', [])));
  AssertEquals('拒了就什么都不改', before, FMgr.SaveLayoutToString);
end;

procedure TTyToolWindowLayoutApplyTests.TestAStreamedManagerWithCodeBuiltBarsResetsToTheBuiltLayout;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
  built: string;
begin
  { .lfm 里只有 manager:它的 Loaded 收尾那一刻一条栏都没有。 }
  m := TTyToolWindowManager.Create(FForm);
  TComponentCrack(m).Loading;
  TComponentCrack(m).Loaded;
  { FormCreate:代码挂栏、搭好(窗体还没显示,改的都算搭建)。 }
  l := NewBarOn(twpLeft, ['Git', 'Debug']);
  r := NewBarOn(twpRight, ['Tree']);
  l.Manager := m;
  r.Manager := m;
  l.ExpandedSize := 222;
  r.Collapsed := True;
  built := m.SaveLayoutToString;
  AssertTrue(m.LoadLayoutFromString('TYTOOLLAYOUT/1' +
    '|left=200,1|leftWins=WDebug,WGit|leftActive=WGit' +
    '|right=240,0|rightWins=WTree|rightActive=WTree|end'));
  AssertTrue('前提:读进了别的样子', m.SaveLayoutToString <> built);
  AssertTrue(m.ResetLayout);
  AssertEquals('Reset 回到代码挂好的样子(不是 Loaded 那一刻的空布局)', built,
    m.SaveLayoutToString);
end;

{ --- 加载中挂起、收尾、默认布局(spec §10.5) ------------------------------------------ }

var
  { 流式化的根上的事件处理器数到这里(读回来的组件只能挂根上的方法)。 }
  StreamedEvents: Integer;
  StreamedApplied: Integer;

type
  { 读回来时它的 Loaded 调 Manager.LoadLayoutFromString(LayoutText)(再 Reset,如果要)。
    是个控件:在窗体的流里排在栏前面(控件按 Controls 顺序写),它的 Loaded 先跑 —— 那时
    栏、窗口、manager 全都还在 csLoading。 }
  TLoadCaller = class(TControl)
  private
    FManager: TTyToolWindowManager;
    FLayoutText: string;
    FThenReset: Boolean;
  protected
    procedure Loaded; override;
  public
    class var LastLoad, LastReset: Boolean;
  published
    property Manager: TTyToolWindowManager read FManager write FManager;
    property LayoutText: string read FLayoutText write FLayoutText;
    property ThenReset: Boolean read FThenReset write FThenReset;
  end;

  TLayoutHostForm = class(TForm)
  published
    procedure CountEvent(Sender: TObject);
    procedure CountApplied(Sender: TObject);
  end;

  { 非可视组件先写、控件后写(窗体和 frame 都是反过来的,见 customform.inc / customframe.inc
    的 GetChildren):manager 第一个 Loaded,最后一个 Loaded 的是最后一条栏。 }
  TManagerFirstRoot = class(TWinControl)
  protected
    procedure GetChildren(Proc: TGetChildProc; Root: TComponent); override;
  end;

procedure TLoadCaller.Loaded;
begin
  inherited Loaded;
  if FManager = nil then Exit;
  if FLayoutText <> '' then LastLoad := FManager.LoadLayoutFromString(FLayoutText);
  if FThenReset then LastReset := FManager.ResetLayout;
end;

procedure TLayoutHostForm.CountEvent(Sender: TObject);
begin
  Inc(StreamedEvents);
end;

procedure TLayoutHostForm.CountApplied(Sender: TObject);
begin
  Inc(StreamedApplied);
end;

procedure TManagerFirstRoot.GetChildren(Proc: TGetChildProc; Root: TComponent);
var
  i: Integer;
begin
  if Root = Self then
    for i := 0 to ComponentCount - 1 do
      if not Components[i].HasParent then Proc(Components[i]);
  inherited GetChildren(Proc, Root);
end;

const
  { 跟流进来的样子每一样都不同的一份。 }
  UserLayout = 'TYTOOLLAYOUT/1' +
    '|left=200,0|leftWins=WSearch,WExplorer|leftActive=WExplorer' +
    '|right=300,0|rightWins=WOutline|rightActive=WOutline' +
    '|bottom=150,1|bottomWins=WTerminal,WProblems,WOutput|bottomActive=WProblems|end';

{ ARoot 里搭一套:manager 'Mgr'、三条栏和它们的窗口(流进来的值都不是出厂值),栏事件和窗口的
  OnShow / OnHide 挂到根的 CountEvent 上(根是 TLayoutHostForm 时)。ACaller 不为 nil 时它
  先建(排在栏前面)。答 manager。 }
function BuildStreamSource(ARoot: TWinControl; ACaller: Boolean;
  const AText: string; AThenReset: Boolean): TTyToolWindowManager;
var
  host: TLayoutHostForm;
  caller: TLoadCaller;
  mgr: TTyToolWindowManager;
  l, r, b: TTyToolWindowBar;

  function Bar(const AName: string; APlacement: TTyToolWindowPlacement): TTyToolWindowBar;
  begin
    Result := TTyToolWindowBar.Create(ARoot);
    Result.Name := AName;
    Result.Placement := APlacement;
    Result.Parent := ARoot;
    Result.Manager := mgr;
    if host <> nil then
    begin
      Result.OnChange := @host.CountEvent;
      Result.OnCollapse := @host.CountEvent;
      Result.OnExpand := @host.CountEvent;
    end;
  end;

  procedure Win(ABar: TTyToolWindowBar; const AName: string);
  var
    w: TTyToolWindow;
  begin
    w := TTyToolWindow.Create(ARoot);
    w.Name := AName;
    w.Parent := ABar;
    if host <> nil then
    begin
      w.OnShow := @host.CountEvent;
      w.OnHide := @host.CountEvent;
    end;
  end;

begin
  if ARoot is TLayoutHostForm then host := TLayoutHostForm(ARoot) else host := nil;
  ARoot.SetBounds(0, 0, 3000, 1000);
  caller := nil;
  if ACaller then
  begin
    caller := TLoadCaller.Create(ARoot);
    caller.Name := 'Caller';
    caller.Parent := ARoot;
  end;
  mgr := TTyToolWindowManager.Create(ARoot);
  mgr.Name := 'Mgr';
  if host <> nil then mgr.OnLayoutApplied := @host.CountApplied;
  Result := mgr;
  l := Bar('BarL', twpLeft);
  Win(l, 'WExplorer');
  Win(l, 'WSearch');
  l.ActiveIndex := 1;
  l.ExpandedSize := 250;
  r := Bar('BarR', twpRight);
  Win(r, 'WOutline');
  r.Collapsed := True;
  b := Bar('BarB', twpBottom);
  Win(b, 'WProblems');
  Win(b, 'WOutput');
  Win(b, 'WTerminal');
  b.ActiveIndex := 2;
  if caller <> nil then
  begin
    caller.Manager := mgr;
    caller.LayoutText := AText;
    caller.ThenReset := AThenReset;
  end;
end;

{ 写出去再读进 ADest(同一种根)。答读回来的 manager。 }
function RoundTrip(ASource, ADest: TComponent): TTyToolWindowManager;
var
  ms: TMemoryStream;
begin
  ms := TMemoryStream.Create;
  try
    ms.WriteComponent(ASource);
    ms.Position := 0;
    StreamedEvents := 0;
    StreamedApplied := 0;
    TLoadCaller.LastLoad := False;
    TLoadCaller.LastReset := False;
    ms.ReadComponent(ADest);
  finally
    ms.Free;
  end;
  Result := ADest.FindComponent('Mgr') as TTyToolWindowManager;
end;

procedure TTyToolWindowLayoutApplyTests.TestALoadDuringStreamingWaitsForTheEnd;
var
  src, dst: TLayoutHostForm;
  m: TTyToolWindowManager;
begin
  src := TLayoutHostForm.CreateNew(nil);
  dst := TLayoutHostForm.CreateNew(nil);
  try
    BuildStreamSource(src, True, UserLayout, False);
    m := RoundTrip(src, dst);
    AssertTrue('加载中调的 Load 答 True(已接受、挂起)', TLoadCaller.LastLoad);
    AssertEquals('读完之后布局就是那一份', UserLayout, m.SaveLayoutToString);
  finally
    dst.Free;
    src.Free;
  end;
end;

procedure TTyToolWindowLayoutApplyTests.TestThePendingPlanIsSilentAndQueuesOnLayoutApplied;
var
  src, dst: TLayoutHostForm;
begin
  src := TLayoutHostForm.CreateNew(nil);
  dst := TLayoutHostForm.CreateNew(nil);
  try
    BuildStreamSource(src, True, UserLayout, False);
    RoundTrip(src, dst);
    AssertEquals('应用挂起计划:没有任何用户事件(栏事件、OnShow / OnHide)', 0, StreamedEvents);
    AssertEquals('OnLayoutApplied 还没发(推到加载结束之后)', 0, StreamedApplied);
    Application.ProcessMessages;
    AssertEquals('抽消息之后恰好一次', 1, StreamedApplied);
  finally
    dst.Free;
    src.Free;
  end;
end;

procedure TTyToolWindowLayoutApplyTests.TestAManagerStreamedFirstIsFinishedByTheLastBar;
var
  src, dst: TManagerFirstRoot;
  m: TTyToolWindowManager;
begin
  src := TManagerFirstRoot.Create(nil);
  dst := TManagerFirstRoot.Create(nil);
  try
    BuildStreamSource(src, True, UserLayout, False);
    m := RoundTrip(src, dst);
    AssertTrue('前提:Load 在加载中调过', TLoadCaller.LastLoad);
    { manager 写在最前,第一个 Loaded(那时别的都还在加载,收不了尾)。读取器在读完一个组件
      (连同它的子控件)之后才把它加进 Loaded 列表(reader.inc:1004-1019),所以栏排在它的
      窗口后面,最后一个 Loaded 的是最后一条栏 —— 它收尾。 }
    AssertEquals('最后一个离开 csLoading 的收了尾', UserLayout, m.SaveLayoutToString);
  finally
    dst.Free;
    src.Free;
  end;
end;

procedure TTyToolWindowLayoutApplyTests.TestOnlyTheLastPendingCallApplies;
var
  src, dst: TLayoutHostForm;
  m: TTyToolWindowManager;
  streamed: string;
begin
  src := TLayoutHostForm.CreateNew(nil);
  dst := TLayoutHostForm.CreateNew(nil);
  try
    streamed := BuildStreamSource(src, True, UserLayout, True).SaveLayoutToString;
    m := RoundTrip(src, dst);
    AssertTrue('前提:Reset 也答 True', TLoadCaller.LastReset);
    AssertEquals('先 Load 后 Reset:只应用后一次(Reset = 流进来的样子)', streamed,
      m.SaveLayoutToString);
  finally
    dst.Free;
    src.Free;
  end;
end;

procedure TTyToolWindowLayoutApplyTests.TestABadStringWhileLoadingIsRefusedAtOnce;
var
  src, dst: TLayoutHostForm;
  m: TTyToolWindowManager;
  streamed: string;
begin
  src := TLayoutHostForm.CreateNew(nil);
  dst := TLayoutHostForm.CreateNew(nil);
  try
    streamed := BuildStreamSource(src, True, Copy(UserLayout, 1, Length(UserLayout) - 4),
      False).SaveLayoutToString;
    TLoadCaller.LastLoad := True;
    m := RoundTrip(src, dst);
    AssertFalse('加载中喂坏串:立即 False', TLoadCaller.LastLoad);
    AssertEquals('加载结束后什么都没应用', streamed, m.SaveLayoutToString);
    Application.ProcessMessages;
    AssertEquals('也没有 OnLayoutApplied', 0, StreamedApplied);
  finally
    dst.Free;
    src.Free;
  end;
end;

procedure TTyToolWindowLayoutApplyTests.TestTheStreamedLayoutIsTheDefault;
var
  src, dst: TLayoutHostForm;
  m: TTyToolWindowManager;
  streamed: string;
  l: TTyToolWindowBar;
begin
  src := TLayoutHostForm.CreateNew(nil);
  dst := TLayoutHostForm.CreateNew(nil);
  try
    streamed := BuildStreamSource(src, False, '', False).SaveLayoutToString;
    m := RoundTrip(src, dst);
    AssertEquals('前提:读回来是流进来的样子', streamed, m.SaveLayoutToString);
    l := dst.FindComponent('BarL') as TTyToolWindowBar;
    l.Windows[1].WindowIndex := 0;
    l.ActiveIndex := 1;
    l.ExpandedSize := 199;
    (dst.FindComponent('BarR') as TTyToolWindowBar).Collapsed := False;
    AssertTrue('前提:改过了', m.SaveLayoutToString <> streamed);
    AssertTrue(m.ResetLayout);
    AssertEquals('Reset 回到流进来的顺序、当前页、尺寸、收起', streamed, m.SaveLayoutToString);
  finally
    dst.Free;
    src.Free;
  end;
end;

procedure TTyToolWindowLayoutApplyTests.TestAnInheritedFormResetsToTheDescendantsValues;
var
  anc, desc, e: TLayoutHostForm;
  ancMS, descMS: TMemoryStream;
  m: TTyToolWindowManager;
  descText: string;
  dl: TTyToolWindowBar;
begin
  anc := TLayoutHostForm.CreateNew(nil);
  desc := TLayoutHostForm.CreateNew(nil);
  e := TLayoutHostForm.CreateNew(nil);
  ancMS := TMemoryStream.Create;
  descMS := TMemoryStream.Create;
  try
    BuildStreamSource(anc, False, '', False);
    ancMS.WriteComponent(anc);
    ancMS.Position := 0;
    ancMS.ReadComponent(desc);
    { 子孙窗体:改顺序、尺寸、收起。 }
    dl := desc.FindComponent('BarL') as TTyToolWindowBar;
    dl.SetControlIndex(desc.FindComponent('WSearch') as TControl, 0);
    dl.ExpandedSize := 222;
    (desc.FindComponent('BarB') as TTyToolWindowBar).Collapsed := True;
    descText := (desc.FindComponent('Mgr') as TTyToolWindowManager).SaveLayoutToString;
    descMS.WriteDescendent(desc, anc);
    { 加载子孙窗体 = 先读祖先那一份,再在同一个实例上读子孙那一份。 }
    ancMS.Position := 0;
    ancMS.ReadComponent(e);
    descMS.Position := 0;
    descMS.ReadComponent(e);
    m := e.FindComponent('Mgr') as TTyToolWindowManager;
    AssertEquals('前提:读回来是子孙窗体的样子', descText, m.SaveLayoutToString);
    (e.FindComponent('BarR') as TTyToolWindowBar).Collapsed := False;
    (e.FindComponent('BarL') as TTyToolWindowBar).ExpandedSize := 300;
    AssertTrue(m.ResetLayout);
    AssertEquals('Reset 回到子孙窗体流进来的值', descText, m.SaveLayoutToString);
  finally
    descMS.Free;
    ancMS.Free;
    e.Free;
    desc.Free;
    anc.Free;
  end;
end;

procedure TTyToolWindowLayoutApplyTests.TestACodeBuiltManagerCapturesBeforeTheFirstLoad;
var
  built: string;
begin
  { 「FormCreate」里:窗体还没 Showing,改的都算搭建。 }
  FLeft.Collapsed := True;
  FRight.ExpandedSize := 260;
  Win('Search').WindowIndex := 0;
  FMgr.MoveWindow(Win('Problems'), FBottom, 2);
  built := FMgr.SaveLayoutToString;
  AssertTrue(FMgr.LoadLayoutFromString(UserLayout));
  AssertEquals('前提:读进了用户布局', UserLayout, FMgr.SaveLayoutToString);
  AssertTrue(FMgr.ResetLayout);
  AssertEquals('默认布局 = 搭好之后、读用户布局之前的样子', built, FMgr.SaveLayoutToString);
end;

procedure TTyToolWindowLayoutApplyTests.TestAnExplicitCaptureIsKeptByLoad;
var
  captured: string;
begin
  FLeft.ExpandedSize := 211;
  FMgr.CaptureDefaultLayout;
  captured := FMgr.SaveLayoutToString;
  FRight.Collapsed := True;
  AssertTrue(FMgr.LoadLayoutFromString(UserLayout));
  AssertTrue(FMgr.ResetLayout);
  AssertEquals('Reset 回到 CaptureDefaultLayout 那一刻', captured, FMgr.SaveLayoutToString);
end;

initialization
  RegisterClasses([TLoadCaller]);
  RegisterTest(TTyToolWindowLayoutApplyTests);
end.
