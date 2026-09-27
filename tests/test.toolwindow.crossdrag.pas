unit test.toolwindow.crossdrag;
{$mode objfpc}{$H+}

{ 跨侧拖动(spec §9.2 / §9.4 / §9.7 / §9.8):悬停时的目标栏、插入线、光标、各种取消;
  松开提交(spec §9.5)在「提交」那一段。夹具:窗体 800×600,左栏(FBar,Explorer / Search / Git,当前页
  Search)、右栏(Outline)、底栏(Problems / Output)、一个 alClient 的编辑区,都注册在一个
  manager 上;窗体的对齐引擎自己请一遍(无头不跑)。 }

interface

uses
  Classes, SysUtils, Types, Controls, Forms, Graphics, LCLType, LMessages,
  fpcunit, testregistry,
  tyControls.Controller, tyControls.ToolWindows, tyControls.ToolWindows.Layout,
  tyControls.ToolWindows.Manager,
  tyControls.Icons.Lucide, test.toolwindow.window, test.toolwindow.bar, test.toolwindow.manager;

type
  TTyToolWindowCrossDragTests = class(TTyToolWindowManagerFixture)
  private
    FMgr: TTyToolWindowManager;
    FRight, FBottom: TBarAccess;
    FEditor: TBodyChild;
    FExplorer, FSearch, FGit, FOutline: TProbeWindow;
    procedure AlignForm;
    function ScreenOf(ABar: TWinControl; const APoint: TPoint): TPoint;
    function ToSourceClient(const AScreen: TPoint): TPoint;
    { 在左栏第 AIndex 格按下、横拖过阈值(还在自己的图标条上)。 }
    procedure StartDrag(AIndex: Integer; ASource: TBarAccess = nil);
    procedure MoveTo(const AScreen: TPoint; ASource: TBarAccess = nil);
    procedure ReleaseAt(const AScreen: TPoint; ASource: TBarAccess = nil);
    { 从 ASource 的第 AIndex 格一路拖到 AScreen 松开。 }
    procedure DragDrop(AIndex: Integer; const AScreen: TPoint; ASource: TBarAccess = nil);
    procedure CountingVetoOnSecondAsk(Sender: TObject; AWindow: TTyToolWindow;
      ATargetBar: TTyToolWindowBar; var AAllow: Boolean);
    { 常用的几个屏幕点。 }
    function RightFirstCellTop: TPoint;
    function RightContent: TPoint;
    function EditorPoint: TPoint;
    function BottomPoint: TPoint;
    function LeftStripCell(AIndex: Integer): TPoint;
    { 右栏图标条画出来,数插入线色的像素。 }
    function DropInkIn(ABar: TBarAccess): Integer;
    procedure AssertNoDropAnywhere(const AMsg: string);
  protected
    procedure SetUp; override;
  published
    procedure TestHoveringTheOtherStripShowsTheSlotThere;
    procedure TestTheOtherBarsContentMeansTheEnd;
    procedure TestTheEditorAndTheBottomBarAreNoTargets;
    procedure TestTheTargetIsAskedOncePerGesture;
    procedure TestAVetoedBarIsNoTarget;
    procedure TestADisabledBarIsNoTarget;
    procedure TestAHiddenOrConflictingBarIsNoTarget;
    procedure TestAConflictingSourceHasNoOtherTargets;
    procedure TestABarOnAnotherFormIsNoTarget;
    procedure TestComingBackClearsTheOtherBar;
    procedure TestANestedBarIsAHole;
    procedure TestTheDropLineIsDrawnOnTheTargetBar;
    procedure TestEscCancelsTheCrossDrag;
    procedure TestCancelDragCancels;
    procedure TestChangingTheTargetBarCancels;
    procedure TestFreeingTheTargetBarCancels;
    procedure TestFreeingTheManagerCancels;
    procedure TestAMoveWithoutTheButtonOnAnotherBarCancels;
    procedure TestTakingTheManagerFromItsOwnerCancels;
    procedure TestMoveWindowCancelsTheDrag;
    { spec §9.5:松开提交。 }
    procedure TestDroppingOnTheOtherStripMovesTheWindowThere;
    procedure TestDroppingOnTheOtherContentAppends;
    procedure TestADropExpandsACollapsedTarget;
    procedure TestDroppingOnTheEditorChangesNothing;
    procedure TestTheTargetIsAskedAgainOnDrop;
    procedure TestADropAfterEscDoesNothing;
    procedure TestAnEmptiedBarKeepsItsStripAndTakesWindowsBack;
    procedure TestADropIsNotABarClick;
    procedure TestAnIndexOnlyIconSurvivesTheMove;
    { OnCanMoveWindow 里取消了拖动:不写落点,答案不进缓存。 }
    procedure TestAHandlerThatCancelsTheDragLeavesNoTarget;
    { 问过的栏离开 manager / 被释放:缓存里它的答案丢掉。 }
    procedure TestABarLeavingTheManagerIsForgottenByTheDrag;
    { 没有 manager 的栏在拖(栏内调顺序)时挂上 manager:取消。 }
    procedure TestSettingAManagerCancelsTheBarsOwnDrag;
    { spec §9.7:同栏调顺序的 MoveWindow 也取消拖动。 }
    procedure TestAReorderByMoveWindowCancelsTheDrag;
    { 嵌在窗体里的窗体藏着:里面的栏不是目标。 }
    procedure TestABarInAHiddenEmbeddedFormIsNoTarget;
    { 直接改 Parent 跟 MoveWindow 同一条路:拖着别的窗口时也取消拖动。 }
    procedure TestADirectParentChangeCancelsTheDrag;
    { 拖到一半目标栏被禁用 / 藏起来:下一次移动就不是目标,在那里松开不挪。 }
    procedure TestATargetDisabledOrHiddenMidDragIsNoTarget;
    { 放下时再问 OnCanMoveWindow,处理器里释放了 manager(spec §6.6 不许):不挪、不再碰它。 }
    procedure TestFreeingTheManagerWhenAskedOnDropDoesNotMove;
  private
    FDeadMgr: Pointer;
    FCanary: PByte;
    procedure CancelInsideTheAsk(Sender: TObject; AWindow: TTyToolWindow;
      ATargetBar: TTyToolWindowBar; var AAllow: Boolean);
    procedure FreeManagerOnTheDropAsk(Sender: TObject; AWindow: TTyToolWindow;
      ATargetBar: TTyToolWindowBar; var AAllow: Boolean);
  end;

implementation

type
  TFormAccess = class(TForm);

const
  Orange = TColor($0080FF);    { CSS #FF8000 }
  DropTheme = ':root { --toolwindow-strip-bg: #FF00FF; --toolwindow-drop-color: #FF8000; }';

function NewNamedWindow(AOwner: TComponent; ABar: TTyToolWindowBar;
  const ACaption: string): TProbeWindow;
begin
  Result := TProbeWindow.Create(AOwner);
  Result.Name := 'W' + ACaption;
  Result.Caption := ACaption;
  Result.Parent := ABar;
end;

procedure TTyToolWindowCrossDragTests.SetUp;
begin
  inherited SetUp;
  FMgr := NewManager;
  FBar.Name := 'L';
  FExplorer := NewNamedWindow(FForm, FBar, 'Explorer');
  FSearch := NewNamedWindow(FForm, FBar, 'Search');
  FGit := NewNamedWindow(FForm, FBar, 'Git');
  FBar.ActiveWindow := FSearch;
  FRight := NewBarOn(twpRight, ['Outline']);
  FOutline := FRight.Windows[0] as TProbeWindow;
  FBottom := NewBarOn(twpBottom, ['Problems', 'Output']);
  FEditor := TBodyChild.Create(FForm);
  FEditor.Parent := FForm;
  FEditor.Align := alClient;
  FBar.Manager := FMgr;
  FRight.Manager := FMgr;
  FBottom.Manager := FMgr;
  AlignForm;
  { 摆错了的话后面每一条都假绿。 }
  AssertEquals('前提:左栏贴左边', 0, FBar.Left);
  AssertEquals('前提:右栏贴右边', FForm.ClientWidth, FRight.Left + FRight.Width);
  AssertTrue('前提:编辑区在两条侧栏之间',
    (FEditor.Left >= FBar.Left + FBar.Width) and (FEditor.Left + FEditor.Width <= FRight.Left));
  AssertTrue('前提:底栏在侧栏下面', FBottom.Top >= FBar.Top + FBar.Height);
end;

procedure TTyToolWindowCrossDragTests.AlignForm;
var
  r: TRect;
begin
  r := FForm.ClientRect;
  TFormAccess(FForm).AdjustClientRect(r);
  TFormAccess(FForm).AlignControls(nil, r);
  LayOut(FBar);
  LayOut(FRight);
end;

function TTyToolWindowCrossDragTests.ScreenOf(ABar: TWinControl; const APoint: TPoint): TPoint;
begin
  Result := ABar.ClientToScreen(APoint);
end;

function TTyToolWindowCrossDragTests.ToSourceClient(const AScreen: TPoint): TPoint;
begin
  Result := FBar.ScreenToClient(AScreen);
end;

procedure TTyToolWindowCrossDragTests.StartDrag(AIndex: Integer; ASource: TBarAccess);
var
  p: TPoint;
begin
  if ASource = nil then ASource := FBar;
  p := ASource.StripItemRect(AIndex).CenterPoint;
  ASource.CallMouseDown(p.X, p.Y);
  ASource.CallMouseMove(p.X + 10, p.Y);
  AssertTrue('前提:拖起来了', ASource.IsDraggingForTest);
end;

procedure TTyToolWindowCrossDragTests.MoveTo(const AScreen: TPoint; ASource: TBarAccess);
var
  q: TPoint;
begin
  if ASource = nil then ASource := FBar;
  q := ASource.ScreenToClient(AScreen);
  ASource.CallMouseMove(q.X, q.Y);
end;

procedure TTyToolWindowCrossDragTests.ReleaseAt(const AScreen: TPoint; ASource: TBarAccess);
var
  q: TPoint;
begin
  if ASource = nil then ASource := FBar;
  q := ASource.ScreenToClient(AScreen);
  ASource.CallClick;          { LCL 在 MouseUp 之前调 Click }
  ASource.CallMouseUp(q.X, q.Y);
end;

procedure TTyToolWindowCrossDragTests.DragDrop(AIndex: Integer; const AScreen: TPoint;
  ASource: TBarAccess);
begin
  StartDrag(AIndex, ASource);
  MoveTo(AScreen, ASource);
  ReleaseAt(AScreen, ASource);
end;

procedure TTyToolWindowCrossDragTests.CountingVetoOnSecondAsk(Sender: TObject;
  AWindow: TTyToolWindow; ATargetBar: TTyToolWindowBar; var AAllow: Boolean);
begin
  Inc(FCanCalls);
  AAllow := FCanCalls < 2;
end;

function TTyToolWindowCrossDragTests.RightFirstCellTop: TPoint;
var
  r: TRect;
begin
  r := FRight.StripItemRect(0);
  AssertTrue('前提:右栏第一格排上了', not IsRectEmpty(r));
  Result := ScreenOf(FRight, Point(r.CenterPoint.X, r.Top + 4));
end;

function TTyToolWindowCrossDragTests.RightContent: TPoint;
begin
  Result := ScreenOf(FRight, FRight.BarLayout.Content.CenterPoint);
end;

function TTyToolWindowCrossDragTests.EditorPoint: TPoint;
begin
  Result := ScreenOf(FEditor, Point(FEditor.ClientWidth div 2, FEditor.ClientHeight div 2));
end;

function TTyToolWindowCrossDragTests.BottomPoint: TPoint;
begin
  Result := ScreenOf(FBottom, Point(FBottom.ClientWidth div 2, FBottom.ClientHeight div 2));
end;

function TTyToolWindowCrossDragTests.LeftStripCell(AIndex: Integer): TPoint;
begin
  Result := ScreenOf(FBar, FBar.StripItemRect(AIndex).CenterPoint);
end;

function TTyToolWindowCrossDragTests.DropInkIn(ABar: TBarAccess): Integer;
var
  bmp: TBitmap;
begin
  bmp := RenderRegion(ABar, ABar.ClientWidth, ABar.ClientHeight, ABar.BarLayout.Cells, Wipe);
  try
    Result := CountExact(bmp, Orange);
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowCrossDragTests.AssertNoDropAnywhere(const AMsg: string);
begin
  AssertFalse(AMsg + ':右栏没有外来落点', FRight.ForeignDropForTest);
  AssertEquals(AMsg + ':右栏槽位', -1, FRight.DropSlotForTest);
  AssertEquals(AMsg + ':左栏槽位', -1, FBar.DropSlotForTest);
end;

{ --- 悬停(spec §9.4) ---------------------------------------------------------------- }

procedure TTyToolWindowCrossDragTests.TestHoveringTheOtherStripShowsTheSlotThere;
begin
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  AssertTrue('右栏有外来落点', FRight.ForeignDropForTest);
  AssertEquals('右栏槽位 0', 0, FRight.DropSlotForTest);
  AssertEquals('左栏自己没有落点', -1, FBar.DropSlotForTest);
  AssertTrue('manager 知道正在拖', FMgr.IsDragging);
  AssertEquals('光标是拖动', Ord(crDrag), Ord(FBar.DragCursorForTest));
end;

procedure TTyToolWindowCrossDragTests.TestTheOtherBarsContentMeansTheEnd;
begin
  StartDrag(1);
  MoveTo(RightContent);
  AssertTrue('内容区也是目标', FRight.ForeignDropForTest);
  AssertEquals('内容区 = 最后一个图标之后', 1, FRight.DropSlotForTest);
end;

procedure TTyToolWindowCrossDragTests.TestTheEditorAndTheBottomBarAreNoTargets;
begin
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  MoveTo(EditorPoint);
  AssertNoDropAnywhere('编辑区');
  AssertEquals('编辑区上是禁止光标', Ord(crNoDrop), Ord(FBar.DragCursorForTest));
  MoveTo(BottomPoint);
  AssertNoDropAnywhere('底栏');
  AssertEquals('底栏上是禁止光标', Ord(crNoDrop), Ord(FBar.DragCursorForTest));
end;

procedure TTyToolWindowCrossDragTests.TestTheTargetIsAskedOncePerGesture;
begin
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  MoveTo(EditorPoint);
  MoveTo(RightContent);
  MoveTo(RightFirstCellTop);
  AssertEquals('每个目标栏每次手势只问一次', 1, FCanCalls);
  AssertSame('问的是拖着的窗口', FSearch, FCanWindow);
  AssertSame('问的是右栏', FRight, FCanTarget);
end;

procedure TTyToolWindowCrossDragTests.TestAVetoedBarIsNoTarget;
begin
  FAllow := False;
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  AssertNoDropAnywhere('被否决的右栏');
  AssertEquals('禁止光标', Ord(crNoDrop), Ord(FBar.DragCursorForTest));
end;

procedure TTyToolWindowCrossDragTests.TestADisabledBarIsNoTarget;
begin
  FRight.Enabled := False;
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  AssertNoDropAnywhere('禁用的右栏');
  MoveTo(RightContent);
  AssertNoDropAnywhere('禁用的右栏内容区');
end;

procedure TTyToolWindowCrossDragTests.TestAHiddenOrConflictingBarIsNoTarget;
var
  p: TPoint;
  r2: TBarAccess;
begin
  p := RightFirstCellTop;
  FRight.Visible := False;
  StartDrag(1);
  MoveTo(p);
  AssertNoDropAnywhere('藏起来的右栏');
  MoveTo(LeftStripCell(2));
  AssertTrue('左栏内调顺序照常有落点', FBar.DropSlotForTest >= 0);
  FBar.CallMouseUp(0, 0);
  FRight.Visible := True;
  r2 := NewBarOn(twpRight, ['Debug']);
  r2.Manager := FMgr;
  AlignForm;
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  AssertNoDropAnywhere('冲突的右栏');
  MoveTo(LeftStripCell(2));
  AssertTrue('冲突不影响左栏内调顺序', FBar.DropSlotForTest >= 0);
end;

procedure TTyToolWindowCrossDragTests.TestAConflictingSourceHasNoOtherTargets;
var
  l2: TBarAccess;
begin
  l2 := NewBarOn(twpLeft, ['Debug']);
  l2.Manager := FMgr;
  AlignForm;
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  AssertNoDropAnywhere('源栏冲突:别的栏都不是目标');
  MoveTo(LeftStripCell(2));
  AssertTrue('源栏自己照样能调顺序', FBar.DropSlotForTest >= 0);
end;

procedure TTyToolWindowCrossDragTests.TestABarOnAnotherFormIsNoTarget;
var
  f2: TForm;
  r2: TTyToolWindowBar;
  w: TTyToolWindow;
  p: TPoint;
begin
  { 右边那一格让给另一个窗体上的栏:本窗体的右栏离开 manager。 }
  FRight.Manager := nil;
  f2 := TForm.CreateNew(nil);
  try
    f2.SetBounds(2000, 0, 400, 400);
    r2 := TTyToolWindowBar.Create(f2);
    r2.Placement := twpRight;
    r2.Parent := f2;
    r2.Controller := FCtl;
    r2.Height := 400;
    w := TTyToolWindow.Create(f2);
    w.Parent := r2;
    r2.Manager := FMgr;
    AssertTrue('前提:它可用', FMgr.IsBarUsable(r2));
    p := r2.ClientToScreen(r2.BarLayout.Content.CenterPoint);
    StartDrag(1);
    MoveTo(p);
    AssertFalse('另一个窗体上的栏不是目标', r2.ForeignDropForTest);
    AssertEquals('禁止光标', Ord(crNoDrop), Ord(FBar.DragCursorForTest));
    FBar.CallMouseUp(0, 0);
  finally
    f2.Free;
  end;
end;

procedure TTyToolWindowCrossDragTests.TestComingBackClearsTheOtherBar;
begin
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  AssertTrue('前提:右栏有落点', FRight.ForeignDropForTest);
  MoveTo(LeftStripCell(2));
  AssertFalse('回到左栏:右栏的外来落点清掉', FRight.ForeignDropForTest);
  AssertEquals('右栏槽位清掉', -1, FRight.DropSlotForTest);
  AssertTrue('左栏自己有落点', FBar.DropSlotForTest >= 0);
end;

procedure TTyToolWindowCrossDragTests.TestANestedBarIsAHole;
var
  host: TBodyChild;
  nested: TTyToolWindowBar;
  p: TPoint;
begin
  { 窗口不收栏(ChildClassAllowed):嵌在正文里的一个容器里。 }
  host := TBodyChild.Create(FForm);
  host.Parent := FOutline;
  host.SetBounds(0, 30, 150, 200);
  nested := TTyToolWindowBar.Create(FForm);
  nested.Parent := host;
  nested.Align := alNone;
  nested.Controller := FCtl;
  nested.SetBounds(10, 40, 60, 120);
  AssertTrue('前提:嵌套栏和它所在的页都显示着(窗体以下)',
    nested.Visible and host.Visible and FOutline.Visible and FRight.Visible);
  p := nested.ClientToScreen(Point(nested.ClientWidth div 2, nested.ClientHeight div 2));
  AssertTrue('前提:这一点在右栏的内容区里',
    PtInRect(FRight.BarLayout.Content, FRight.ScreenToClient(p)));
  StartDrag(1);
  MoveTo(p);
  AssertNoDropAnywhere('嵌在右栏里的栏');
  { 只问命中的那一条:落在洞里一条都不问(按「在不在它的可见矩形里」问的话会问右栏)。 }
  AssertEquals('落在洞里:不问外面那条栏', 0, FCanCalls);
end;

{ --- 反馈外观(spec §9.8) ------------------------------------------------------------- }

procedure TTyToolWindowCrossDragTests.TestTheDropLineIsDrawnOnTheTargetBar;
var
  w: Integer;
begin
  FCtl.StyleOverride := DropTheme;
  AssertEquals('没拖动:右栏没有线', 0, DropInkIn(FRight));
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  w := FRight.BarLayout.Cells.Right - FRight.BarLayout.Cells.Left;
  AssertEquals('右栏:插入线横跨图标条', TyToolWindowDropSizeDef * w, DropInkIn(FRight));
  AssertEquals('左栏图标条里没有线', 0, DropInkIn(FBar));
  FBar.CallMouseUp(0, 0);
  { 空的右栏(Outline 挪走)照样画线 —— 留着图标条的那种(HideWhenEmpty = False);隐藏的空栏
    用放置预览代替插入线,在 test.toolwindow.hide。 }
  FRight.HideWhenEmpty := False;
  FOutline.Parent := FBar;
  AlignForm;
  AssertEquals('前提:右栏空了', 0, FRight.WindowCount);
  StartDrag(1);
  MoveTo(ScreenOf(FRight, FRight.BarLayout.Cells.CenterPoint));
  AssertTrue('前提:空栏也是目标', FRight.ForeignDropForTest);
  AssertTrue('空的右栏也有插入线', DropInkIn(FRight) > 0);
end;

{ --- 取消(spec §9.7) ------------------------------------------------------------------ }

procedure TTyToolWindowCrossDragTests.TestEscCancelsTheCrossDrag;
begin
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  FEditor.Perform(CN_KEYDOWN, VK_ESCAPE, 0);
  AssertFalse('Esc:不在拖了', FMgr.IsDragging);
  AssertNoDropAnywhere('Esc');
end;

procedure TTyToolWindowCrossDragTests.TestCancelDragCancels;
begin
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  FMgr.CancelDrag;
  AssertFalse('CancelDrag:不在拖了', FMgr.IsDragging);
  AssertNoDropAnywhere('CancelDrag');
  AssertEquals('引擎记成 Cancelled', Ord(twgsCancelled), Ord(FBar.GestureStateForTest));
  ReleaseAt(RightFirstCellTop);
  AssertSame('之后的松开什么都不做', TTyToolWindowBar(FBar), FSearch.Bar);
  AssertSame('也不是点击', FSearch, FBar.ActiveWindow);
end;

procedure TTyToolWindowCrossDragTests.TestChangingTheTargetBarCancels;
begin
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  FRight.Collapsed := True;
  AssertFalse('目标栏收起:取消', FMgr.IsDragging);
  AssertNoDropAnywhere('目标栏收起');
  FBar.CallMouseUp(0, 0);
  FRight.Collapsed := False;
  AlignForm;
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  FRight.Manager := nil;
  AssertFalse('目标栏离开 manager:取消', FMgr.IsDragging);
  AssertNoDropAnywhere('目标栏离开 manager');
  FBar.CallMouseUp(0, 0);
  FRight.Manager := FMgr;
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  FRight.Placement := twpLeft;
  AssertFalse('目标栏改 Placement:取消', FMgr.IsDragging);
  AssertNoDropAnywhere('目标栏改 Placement');
end;

procedure TTyToolWindowCrossDragTests.TestFreeingTheTargetBarCancels;
begin
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  FreeAndNil(FRight);
  AssertFalse('目标栏被释放:不在拖了', FMgr.IsDragging);
  AssertTrue('源栏的引擎收尾了', FBar.GestureStateForTest in [twgsCancelled, twgsIdle]);
  AssertEquals('左栏没有落点', -1, FBar.DropSlotForTest);
end;

procedure TTyToolWindowCrossDragTests.TestFreeingTheManagerCancels;
var
  p: TPoint;
begin
  p := RightFirstCellTop;
  StartDrag(1);
  MoveTo(p);
  FreeAndNil(FMgr);
  AssertEquals('manager 被释放:源栏的手势取消', Ord(twgsCancelled), Ord(FBar.GestureStateForTest));
  AssertFalse('右栏的外来落点清掉', FRight.ForeignDropForTest);
  ReleaseAt(p);
  AssertSame('之后在右栏位置松开什么都不发生', TTyToolWindowBar(FBar), FSearch.Bar);
  AssertEquals('右栏还是一个窗口', 1, FRight.WindowCount);
end;

procedure TTyToolWindowCrossDragTests.TestAMoveWithoutTheButtonOnAnotherBarCancels;
var
  q: TPoint;
begin
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  q := FRight.ScreenToClient(RightContent);
  FRight.CallMouseMove(q.X, q.Y, []);
  AssertFalse('别的注册栏看到没按键的移动:取消', FMgr.IsDragging);
  AssertNoDropAnywhere('丢了松开');
end;

procedure TTyToolWindowCrossDragTests.TestTakingTheManagerFromItsOwnerCancels;
begin
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  { RemoveComponent 同样广播 opRemove,manager 还活着 —— 它的析构取消不了,只有栏自己那一条。 }
  FForm.RemoveComponent(FMgr);
  try
    AssertTrue('前提:栏的引用清掉了', FBar.Manager = nil);
    AssertEquals('栏收到 manager 的 opRemove:取消', Ord(twgsCancelled),
      Ord(FBar.GestureStateForTest));
    AssertFalse('manager 那边也不再记着在拖', FMgr.IsDragging);
  finally
    FreeAndNil(FMgr);
  end;
end;

procedure TTyToolWindowCrossDragTests.TestMoveWindowCancelsTheDrag;
begin
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  AssertTrue('无头:同步挪', FMgr.MoveWindow(FGit, FRight));
  AssertFalse('MoveWindow 取消此刻的拖动', FMgr.IsDragging);
  AssertEquals('源栏的手势取消', Ord(twgsCancelled), Ord(FBar.GestureStateForTest));
end;

{ --- 提交(spec §9.5) ------------------------------------------------------------------ }

procedure TTyToolWindowCrossDragTests.TestDroppingOnTheOtherStripMovesTheWindowThere;
begin
  FRight.Collapsed := True;
  AlignForm;
  LogBarEvents(FBar);
  LogBarEvents(FRight);
  FMgr.OnWindowMoved := @LogMoved;
  FLog := '';
  DragDrop(1, RightFirstCellTop);
  AssertSame('到了右栏', TTyToolWindowBar(FRight), FSearch.Bar);
  AssertSame('排在第一个', TTyToolWindow(FSearch), FRight.Windows[0]);
  AssertSame('成为右栏当前页', TTyToolWindow(FSearch), FRight.ActiveWindow);
  AssertFalse('右栏展开', FRight.Collapsed);
  AssertSame('左栏回落到原位置上的下一个', TTyToolWindow(FGit), FBar.ActiveWindow);
  AssertEquals('事件顺序同 MoveWindow', 'L.change;R.expand;R.change;moved(WSearch,L,1);', FLog);
  AssertFalse('手势收尾了', FMgr.IsDragging);
  AssertFalse('右栏的外来落点清掉', FRight.ForeignDropForTest);
end;

procedure TTyToolWindowCrossDragTests.TestDroppingOnTheOtherContentAppends;
begin
  DragDrop(1, RightContent);
  AssertSame('到了右栏', TTyToolWindowBar(FRight), FSearch.Bar);
  AssertSame('排在末尾', TTyToolWindow(FSearch), FRight.Windows[1]);
end;

procedure TTyToolWindowCrossDragTests.TestADropExpandsACollapsedTarget;
begin
  FRight.ExpandedSize := 260;
  FRight.Collapsed := True;
  AlignForm;
  DragDrop(0, RightFirstCellTop);
  AssertFalse('展开', FRight.Collapsed);
  AssertEquals('展开到它的 ExpandedSize(推导值)', FRight.CallDerivedAxisPx, FRight.Width);
  AssertEquals('推导值里内容项是 ExpandedSize', FRight.StripSizePx + FRight.EdgeSizePx
    + 2 * FRight.ChromeInsetPx + 260, FRight.Width);
end;

procedure TTyToolWindowCrossDragTests.TestDroppingOnTheEditorChangesNothing;
begin
  LogBarEvents(FBar);
  LogBarEvents(FRight);
  FMgr.OnWindowMoved := @LogMoved;
  FLog := '';
  DragDrop(1, EditorPoint);
  AssertSame('还在左栏', TTyToolWindowBar(FBar), FSearch.Bar);
  AssertSame('左栏当前页没变(也不是点击)', TTyToolWindow(FSearch), FBar.ActiveWindow);
  AssertFalse('左栏没被收起(不是点击)', FBar.Collapsed);
  AssertEquals('没有任何事件', '', FLog);
end;

procedure TTyToolWindowCrossDragTests.TestTheTargetIsAskedAgainOnDrop;
begin
  FMgr.OnCanMoveWindow := @CountingVetoOnSecondAsk;
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  AssertTrue('前提:悬停时放行,有落点', FRight.ForeignDropForTest);
  ReleaseAt(RightFirstCellTop);
  AssertEquals('放下时又问了一次', 2, FCanCalls);
  AssertSame('放下时否决:不挪', TTyToolWindowBar(FBar), FSearch.Bar);
end;

procedure TTyToolWindowCrossDragTests.TestADropAfterEscDoesNothing;
begin
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  FEditor.Perform(CN_KEYDOWN, VK_ESCAPE, 0);
  ReleaseAt(RightFirstCellTop);
  AssertSame('取消后松开:不挪', TTyToolWindowBar(FBar), FSearch.Bar);
end;

procedure TTyToolWindowCrossDragTests.TestAnEmptiedBarKeepsItsStripAndTakesWindowsBack;
begin
  { 保留图标条是 HideWhenEmpty = False 的样子(E 期,spec §6.9);默认的整条隐藏 + 放置预览在
    test.toolwindow.hide。 }
  FBar.HideWhenEmpty := False;
  DragDrop(0, RightContent);
  AlignForm;
  DragDrop(0, RightContent);
  AlignForm;
  DragDrop(0, RightContent);
  AlignForm;
  AssertEquals('左栏拖空了', 0, FBar.WindowCount);
  AssertFalse('拖空不写 Collapsed', FBar.Collapsed);
  AssertEquals('只剩图标条', FBar.StripSizePx + 2 * FBar.ChromeInsetPx, FBar.Width);
  { 从右栏拖一个回来,落在空的左栏图标条上。 }
  DragDrop(0, ScreenOf(FBar, FBar.BarLayout.Cells.CenterPoint), FRight);
  AssertEquals('空栏照样是目标:拖回来了', 1, FBar.WindowCount);
  AssertSame('成为左栏当前页', FBar.Windows[0], FBar.ActiveWindow);
end;

procedure TTyToolWindowCrossDragTests.TestADropIsNotABarClick;
begin
  FClicks := 0;
  FBar.OnClick := @HandleClick;
  DragDrop(1, RightFirstCellTop);
  AssertSame('前提:挪过去了', TTyToolWindowBar(FRight), FSearch.Bar);
  AssertEquals('栏的 OnClick 没触发', 0, FClicks);
end;

procedure TTyToolWindowCrossDragTests.TestAnIndexOnlyIconSurvivesTheMove;
var
  list: TTyLucideImageList;
begin
  list := TTyLucideImageList.Create(FForm);
  list.Names.Text := 'house' + LineEnding + 'folder';
  FMgr.Images := list;
  FSearch.ImageIndex := 1;
  AssertEquals('前提:左栏按 manager 的列表解析', 1, FBar.ResolvedImageIndex(FSearch));
  DragDrop(1, RightFirstCellTop);
  AssertSame('前提:挪过去了', TTyToolWindowBar(FRight), FSearch.Bar);
  AssertEquals('两侧共用 manager 的列表:那一格不变', 1, FRight.ResolvedImageIndex(FSearch));
end;

{ --- 处理器、缓存、取消的口径 -------------------------------------------------------- }

procedure TTyToolWindowCrossDragTests.CancelInsideTheAsk(Sender: TObject; AWindow: TTyToolWindow;
  ATargetBar: TTyToolWindowBar; var AAllow: Boolean);
begin
  Inc(FCanCalls);
  AAllow := True;
  TTyToolWindowManager(Sender).CancelDrag;
end;

procedure TTyToolWindowCrossDragTests.TestAHandlerThatCancelsTheDragLeavesNoTarget;
begin
  FMgr.OnCanMoveWindow := @CancelInsideTheAsk;
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  AssertEquals('前提:问了一次', 1, FCanCalls);
  AssertEquals('处理器取消了拖动', Ord(twgsCancelled), Ord(FBar.GestureStateForTest));
  AssertNoDropAnywhere('处理器里取消之后');
  AssertEquals('这一份答案不进缓存(留给下一次手势就是别人的答案)', 0,
    FBar.AllowedCacheCountForTest);
end;

procedure TTyToolWindowCrossDragTests.TestABarLeavingTheManagerIsForgottenByTheDrag;
begin
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  MoveTo(LeftStripCell(2));
  AssertEquals('前提:右栏问过、记着', 1, FBar.AllowedCacheCountForTest);
  AssertFalse('前提:此刻目标不是右栏', FRight.ForeignDropForTest);
  FRight.Manager := nil;
  AssertTrue('离开的不是参与拖动的栏:拖动照常', FMgr.IsDragging);
  AssertEquals('离开 manager:它的答案丢掉', 0, FBar.AllowedCacheCountForTest);
  FRight.Manager := FMgr;
  MoveTo(RightFirstCellTop);
  MoveTo(LeftStripCell(2));
  AssertEquals('前提:又问过、记着', 1, FBar.AllowedCacheCountForTest);
  FreeAndNil(FRight);
  AssertTrue('被释放的不是参与拖动的栏:拖动照常', FMgr.IsDragging);
  AssertEquals('被释放:它的答案丢掉(地址之后可能是另一条栏)', 0, FBar.AllowedCacheCountForTest);
end;

procedure TTyToolWindowCrossDragTests.TestSettingAManagerCancelsTheBarsOwnDrag;
var
  nb: TBarAccess;
begin
  nb := NewBarOn(twpLeft, ['Debug', 'Tests', 'Todo']);
  AssertTrue('前提:没有 manager', nb.Manager = nil);
  StartDrag(0, nb);
  AssertFalse('前提:manager 不知道它在拖', FMgr.IsDragging);
  nb.Manager := FMgr;
  AssertEquals('挂上 manager:栏自己的拖动取消', Ord(twgsCancelled), Ord(nb.GestureStateForTest));
end;

procedure TTyToolWindowCrossDragTests.TestAReorderByMoveWindowCancelsTheDrag;
begin
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  AssertTrue('同栏调顺序:接受', FMgr.MoveWindow(FExplorer, FBar, 2));
  AssertSame('前提:调了顺序', TTyToolWindow(FExplorer), FBar.Windows[2]);
  AssertFalse('同栏的 MoveWindow 也取消拖动', FMgr.IsDragging);
  AssertEquals('源栏的手势取消', Ord(twgsCancelled), Ord(FBar.GestureStateForTest));
end;

procedure TTyToolWindowCrossDragTests.TestABarInAHiddenEmbeddedFormIsNoTarget;
var
  ef: TForm;
  r2: TTyToolWindowBar;
  w: TTyToolWindow;
  p: TPoint;
  r: TRect;
begin
  { 右边那一格让给嵌入式窗体里的栏:本窗体的右栏离开 manager。 }
  FRight.Manager := nil;
  ef := TForm.CreateNew(nil);
  try
    ef.BorderStyle := bsNone;
    ef.Parent := FForm;
    ef.SetBounds(FRight.Left, FRight.Top, FRight.Width, FRight.Height);
    r2 := TTyToolWindowBar.Create(ef);
    r2.Placement := twpRight;
    r2.Parent := ef;
    r2.Controller := FCtl;
    r2.Align := alNone;
    r2.SetBounds(0, 0, FRight.Width, FRight.Height);
    w := TTyToolWindow.Create(ef);
    w.Parent := r2;
    r2.Manager := FMgr;
    AssertTrue('前提:它可用', FMgr.IsBarUsable(r2));
    AssertTrue('前提:同一个顶层窗体', GetParentForm(r2) = FForm);
    AssertTrue('前提:结构上挪得过去', FMgr.CanMoveWindow(FSearch, r2));
    FCanCalls := 0;
    r := r2.BarLayout.Content;
    p := r2.ClientToScreen(r.CenterPoint);
    { 对照:嵌入式窗体显示着时这一点就是它的内容区。 }
    ef.Visible := True;
    StartDrag(1);
    MoveTo(p);
    AssertTrue('对照:显示着的嵌入式窗体里的栏是目标', r2.ForeignDropForTest);
    FBar.CallMouseUp(0, 0);
    ef.Visible := False;
    AssertFalse('前提:嵌入式窗体藏着', ef.Visible);
    StartDrag(1);
    MoveTo(p);
    AssertFalse('藏着的嵌入式窗体里的栏不是目标', r2.ForeignDropForTest);
    AssertEquals('禁止光标', Ord(crNoDrop), Ord(FBar.DragCursorForTest));
    FBar.CallMouseUp(0, 0);
  finally
    ef.Free;
  end;
end;

procedure TTyToolWindowCrossDragTests.TestADirectParentChangeCancelsTheDrag;
begin
  StartDrag(0);
  MoveTo(RightFirstCellTop);
  AssertTrue('前提:拖着 Explorer', FMgr.IsDragging);
  { 挪的是另一个窗口(Git):离开的不是手势的窗口,光靠注销收不了尾。 }
  FGit.Parent := FRight;
  AssertSame('前提:挪过去了', TTyToolWindowBar(FRight), FGit.Bar);
  AssertFalse('直接改 Parent 也取消拖动', FMgr.IsDragging);
  AssertNoDropAnywhere('直接改 Parent 之后');
end;

procedure TTyToolWindowCrossDragTests.TestATargetDisabledOrHiddenMidDragIsNoTarget;
var
  p: TPoint;
begin
  p := RightFirstCellTop;
  StartDrag(1);
  MoveTo(p);
  AssertTrue('前提:右栏有落点', FRight.ForeignDropForTest);
  FRight.Enabled := False;
  MoveTo(p);
  AssertNoDropAnywhere('拖到一半右栏被禁用');
  ReleaseAt(p);
  AssertSame('在被禁用的右栏上松开:不挪', TTyToolWindowBar(FBar), FSearch.Bar);
  FRight.Enabled := True;
  StartDrag(1);
  MoveTo(p);
  AssertTrue('前提:右栏又有落点', FRight.ForeignDropForTest);
  FRight.Visible := False;
  MoveTo(p);
  AssertNoDropAnywhere('拖到一半右栏被藏起来');
  ReleaseAt(p);
  AssertSame('在藏起来的右栏那里松开:不挪', TTyToolWindowBar(FBar), FSearch.Bar);
end;

procedure TTyToolWindowCrossDragTests.FreeManagerOnTheDropAsk(Sender: TObject;
  AWindow: TTyToolWindow; ATargetBar: TTyToolWindowBar; var AAllow: Boolean);
begin
  Inc(FCanCalls);
  AAllow := True;
  { 悬停时放行;放下时再问的那一次里释放 manager。 }
  if (FCanCalls < 2) or (FMgr = nil) then Exit;
  FDeadMgr := Pointer(FMgr);
  FreeAndNil(FMgr);
  { 金丝雀:刚还掉的那一块马上借回来、填满,之后谁往死 manager 身上写就看得见。 }
  FCanary := GetMem(TTyToolWindowManager.InstanceSize);
  FillChar(FCanary^, TTyToolWindowManager.InstanceSize, $A5);
end;

procedure TTyToolWindowCrossDragTests.TestFreeingTheManagerWhenAskedOnDropDoesNotMove;
var
  i: Integer;
  intact: Boolean;
begin
  FCanary := nil;
  FMgr.OnCanMoveWindow := @FreeManagerOnTheDropAsk;
  StartDrag(1);
  MoveTo(RightFirstCellTop);
  AssertTrue('前提:悬停时放行,有落点', FRight.ForeignDropForTest);
  try
    ReleaseAt(RightFirstCellTop);
    AssertTrue('前提:放下时再问的那一次里释放了 manager', FMgr = nil);
    AssertTrue('前提:释放掉的那一块被借回来了(不然这一条什么都测不到)',
      Pointer(FCanary) = FDeadMgr);
    intact := True;
    for i := 0 to TTyToolWindowManager.InstanceSize - 1 do
      if FCanary[i] <> $A5 then intact := False;
    AssertTrue('处理器返回之后没有人再往死 manager 身上写', intact);
    AssertSame('manager 在放下时没了:不挪', TTyToolWindowBar(FBar), FSearch.Bar);
  finally
    if FCanary <> nil then FreeMem(FCanary);
  end;
end;

initialization
  RegisterTest(TTyToolWindowCrossDragTests);
end.
