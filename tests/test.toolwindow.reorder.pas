unit test.toolwindow.reorder;
{$mode objfpc}{$H+}

{ 栏内拖动调顺序(spec §9.2 / §9.4 / §9.7):阈值、插入线、松开提交、取消。夹具在 test.toolwindow.bar。 }

interface

uses
  Classes, SysUtils, Types, TypInfo, Controls, Forms, Graphics, LCLType, LCLProc, LMessages,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.ToolWindows,
  tyControls.ToolWindows.Layout,
  tyControls.Icons.Lucide, test.toolwindow.window,
  test.toolwindow.bar;

type
  TTyToolWindowReorderTests = class(TTyToolWindowBarFixture)
  private
    procedure RaiseInMouseUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState;
      X, Y: Integer);
    { 在第 AIndex 格图标上按下、往下拖过阈值。 }
    procedure StartDrag(AIndex: Integer);
  published
    procedure TestDragReordersOnReleaseNotLive;
    procedure TestSidewaysDragStarts;
    procedure TestEscCancelsAndTheReleaseIsNotAClick;
    procedure TestNoOpSlotsDoNotReorder;
    procedure TestDropIndicatorPixelsLandInTheStrip;
    procedure TestALostReleaseCancelModeOrCollapseCancelsTheDrag;
    procedure TestAMultiClickPressCanStillDrag;
    procedure TestADropOffTheStripIsACancel;
    procedure TestFreeingTheDraggedWindowEndsTheGesture;
    procedure TestWindowIndexReordersAndTheActivePageFollows;
    { 退出路径(spec §9.7):每一条都把临时光标栈、处理器、计时器、插入线收干净。 }
    procedure TestASecondPressWhileDraggingUnwindsEverything;
    procedure TestReleasingTheButtonAfterACancelResumesHover;
    procedure TestFreeingTheBarMidDragUnwindsTheCursorStack;
    procedure TestApplicationDeactivationCancelsTheDrag;
    procedure TestAnotherFormBecomingActiveCancelsTheDrag;
    procedure TestAPlacementChangeCancelsTheDragAndTheResize;
    procedure TestDisablingOrHidingTheBarEndsTheGestures;
    procedure TestAnExceptionInOnMouseUpLeavesNoGestureBehind;
  end;

implementation

procedure TTyToolWindowReorderTests.TestDragReordersOnReleaseNotLive;
var
  a, b, c: TProbeWindow;
  p: TPoint;
begin
  a := NewWindow;
  b := NewWindow;
  c := NewWindow;
  FBar.ActiveWindow := b;
  FBar.OnChange := @HandleChange;
  FBar.OnClick := @HandleClick;
  ResetCounts;
  FClicks := 0;
  { 三个窗口 a b c;把 a 拖到 c 后面。 }
  p := FBar.StripItemRect(0).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseMove(p.X, p.Y + 80);
  AssertTrue('过了阈值就是拖动', FBar.IsDraggingForTest);
  AssertSame('拖动过程中不实时挪', a, FBar.Windows[0]);
  AssertEquals('插入线落在末尾', 3, FBar.DropSlotForTest);
  { LCL 在 MouseUp 之前调 Click。 }
  FBar.CallClick;
  FBar.CallMouseUp(p.X, p.Y + 80);
  AssertSame('松开才提交', b, FBar.Windows[0]);
  AssertSame('c 跟上来', c, FBar.Windows[1]);
  AssertSame('a 到了最后', a, FBar.Windows[2]);
  AssertSame('当前页还是那个窗口', b, FBar.ActiveWindow);
  AssertEquals('ActiveIndex 跟着窗口走', 0, FBar.ActiveIndex);
  AssertEquals('调顺序不发 OnChange', 0, FChanges);
  AssertEquals('调顺序后栏的 OnClick 不触发', 0, FClicks);
  AssertFalse('不收起', FBar.Collapsed);
  AssertFalse('手势结束', FBar.IsDraggingForTest);
  { 往后拖到中间的空隙:FinalIndex = slot - 1(移走自己之后后面的空隙往前挪一格)。
    上面那次落在末尾,钳位会把少减的一格盖住,这里不会。 }
  p := FBar.StripItemRect(0).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseMove(p.X, FBar.StripItemRect(2).Top + 2);
  AssertEquals('前提:落点是 a 前面那个空隙', 2, FBar.DropSlotForTest);
  FBar.CallMouseUp(p.X, FBar.StripItemRect(2).Top + 2);
  AssertSame('c 到了最前', c, FBar.Windows[0]);
  AssertSame('b 落在 a 前面', b, FBar.Windows[1]);
  AssertSame('a 还在最后', a, FBar.Windows[2]);
end;

procedure TTyToolWindowReorderTests.TestSidewaysDragStarts;
var
  p: TPoint;
  thr: Integer;
begin
  NewWindow;
  NewWindow;
  thr := TyToolWindowDragThreshold(96);
  p := FBar.StripItemRect(0).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseMove(p.X + thr - 1, p.Y);
  AssertFalse('阈值以内还是武装', FBar.IsDraggingForTest);
  { 竖直图标条上**横向**移动过阈值也要进入拖动 —— TabStrip 只算主轴,照抄永远拖不起来。 }
  FBar.CallMouseMove(p.X + thr, p.Y);
  AssertTrue('横拖也算拖', FBar.IsDraggingForTest);
  FBar.CallMouseUp(p.X + thr, p.Y);
end;

procedure TTyToolWindowReorderTests.TestEscCancelsAndTheReleaseIsNotAClick;
var
  a, b: TProbeWindow;
  other: TBodyChild;
  p: TPoint;
begin
  a := NewWindow;
  b := NewWindow;
  FBar.ActiveWindow := a;
  other := TBodyChild.Create(FForm);
  other.Parent := FForm;
  p := FBar.StripItemRect(1).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseMove(p.X, p.Y - 50);
  AssertTrue('前提:拖起来了', FBar.IsDraggingForTest);
  AssertEquals('前提:落点是 a 前面', 0, FBar.DropSlotForTest);
  { 图标条不拿焦点,Esc 落在焦点控件上;经 Application 的 KeyDownBefore 到栏。 }
  other.Perform(CN_KEYDOWN, VK_ESCAPE, 0);
  AssertFalse('Esc 取消拖动', FBar.IsDraggingForTest);
  AssertEquals('记成 Cancelled', Ord(twgsCancelled), Ord(FBar.GestureStateForTest));
  AssertEquals('反馈清掉', -1, FBar.DropSlotForTest);
  FBar.CallMouseMove(p.X, p.Y - 50);
  FBar.CallMouseUp(p.X, p.Y);
  AssertSame('顺序不变', a, FBar.Windows[0]);
  AssertSame('取消后的松开不是点击:当前页不变', a, FBar.ActiveWindow);
  AssertEquals('松开之后回到 Idle', Ord(twgsIdle), Ord(FBar.GestureStateForTest));
  ClickIcon(1);
  AssertSame('下一次按下照常点击', b, FBar.ActiveWindow);
end;

procedure TTyToolWindowReorderTests.TestNoOpSlotsDoNotReorder;
var
  a, b, c: TProbeWindow;
  p: TPoint;
begin
  a := NewWindow;
  b := NewWindow;
  c := NewWindow;
  FBar.ActiveWindow := a;
  FBar.OnChange := @HandleChange;
  ResetCounts;
  { 拖 b 放回它自己前后两个空隙(slot = src 与 src+1)。 }
  p := FBar.StripItemRect(1).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseMove(p.X, FBar.StripItemRect(1).Top + 2);
  AssertEquals('自己前面的空隙', 1, FBar.DropSlotForTest);
  FBar.CallMouseUp(p.X, FBar.StripItemRect(1).Top + 2);
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseMove(p.X, FBar.StripItemRect(2).Top + 2);
  AssertEquals('自己后面的空隙', 2, FBar.DropSlotForTest);
  FBar.CallMouseUp(p.X, FBar.StripItemRect(2).Top + 2);
  AssertSame('顺序一点不变', a, FBar.Windows[0]);
  AssertSame('顺序一点不变', b, FBar.Windows[1]);
  AssertSame('顺序一点不变', c, FBar.Windows[2]);
  AssertEquals('也不发 OnChange', 0, FChanges);
end;

procedure TTyToolWindowReorderTests.TestDropIndicatorPixelsLandInTheStrip;
const
  Orange = TColor($0080FF);   { CSS #FF8000:红绿蓝三个都不相等,别的元素混不出来 }
var
  a: TProbeWindow;
  cells: TRect;
  p: TPoint;
  bmp: TBitmap;
  w, lineY: Integer;

  function Drawn: Integer;
  var
    b: TBitmap;
  begin
    b := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, cells, Wipe);
    try
      Result := CountExact(b, Orange);
    finally
      b.Free;
    end;
  end;

begin
  FCtl.StyleOverride := ':root { --toolwindow-strip-bg: #FF00FF; --toolwindow-drop-color: #FF8000; }';
  a := NewWindow;
  NewWindow;
  NewWindow;
  FBar.ActiveWindow := a;
  cells := FBar.BarLayout.Cells;
  w := cells.Right - cells.Left;
  AssertEquals('没拖动:没有插入线', 0, Drawn);
  p := FBar.StripItemRect(0).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseMove(p.X, p.Y + 80);
  AssertEquals('前提:落点在末尾', 3, FBar.DropSlotForTest);
  AssertEquals('拖动中:插入线横跨图标条,粗细 = token', TyToolWindowDropSizeDef * w, Drawn);
  lineY := FBar.StripItemRect(2).Bottom;
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, cells, Wipe);
  try
    AssertTrue('线画在最后一格的下沿', PixelIs(bmp, w div 2, lineY - cells.Top - 1, Orange));
  finally
    bmp.Free;
  end;
  { 空操作(拖回自己前面):不画线。 }
  FBar.CallMouseMove(p.X, FBar.StripItemRect(0).Top + 2);
  AssertEquals('前提:空操作的空隙', 0, FBar.DropSlotForTest);
  AssertEquals('空操作不画线', 0, Drawn);
  FBar.Perform(LM_CANCELMODE, 0, 0);
  AssertEquals('取消后没有线', 0, Drawn);
end;

procedure TTyToolWindowReorderTests.TestALostReleaseCancelModeOrCollapseCancelsTheDrag;
var
  a: TProbeWindow;
  p: TPoint;
begin
  a := NewWindow;
  NewWindow;
  NewWindow;
  FBar.ActiveWindow := a;
  p := FBar.StripItemRect(0).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseMove(p.X, p.Y + 80);
  FBar.CallMouseMove(p.X, p.Y + 80, []);
  AssertFalse('没有 ssLeft 的移动:取消', FBar.IsDraggingForTest);
  FBar.CallMouseUp(p.X, p.Y + 80);
  AssertSame('顺序不变', a, FBar.Windows[0]);
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseMove(p.X, p.Y + 80);
  FBar.Perform(LM_CANCELMODE, 0, 0);
  AssertFalse('LM_CANCELMODE:取消', FBar.IsDraggingForTest);
  FBar.CallMouseUp(p.X, p.Y + 80);
  AssertSame('顺序不变', a, FBar.Windows[0]);
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseMove(p.X, p.Y + 80);
  FBar.Collapsed := True;
  AssertFalse('栏的 Collapsed 被改:取消', FBar.IsDraggingForTest);
  FBar.CallMouseUp(p.X, p.Y + 80);
  AssertSame('顺序不变', a, FBar.Windows[0]);
end;

procedure TTyToolWindowReorderTests.TestAMultiClickPressCanStillDrag;
var
  a: TProbeWindow;
  p: TPoint;
begin
  a := NewWindow;
  NewWindow;
  NewWindow;
  p := FBar.StripItemRect(0).CenterPoint;
  { 点一下图标、马上按住同一个图标拖:第二下被 LCL 标成 ssDouble(spec §9.2)。 }
  FBar.CallMouseDown(p.X, p.Y, [ssLeft, ssDouble]);
  FBar.CallMouseMove(p.X, p.Y + 80);
  AssertTrue('多击的按下照样拖得起来', FBar.IsDraggingForTest);
  FBar.CallMouseUp(p.X, p.Y + 80);
  AssertSame('照样提交', a, FBar.Windows[2]);
end;

procedure TTyToolWindowReorderTests.TestADropOffTheStripIsACancel;
var
  a: TProbeWindow;
  p, q: TPoint;
begin
  a := NewWindow;
  NewWindow;
  p := FBar.StripItemRect(0).CenterPoint;
  q := FBar.BarLayout.Content.CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseMove(q.X, q.Y);
  AssertTrue('前提:拖起来了', FBar.IsDraggingForTest);
  AssertEquals('源栏自己的内容区不是目标', -1, FBar.DropSlotForTest);
  FBar.CallMouseUp(q.X, q.Y);
  AssertSame('在这里松开就是取消', a, FBar.Windows[0]);
end;

procedure TTyToolWindowReorderTests.TestFreeingTheDraggedWindowEndsTheGesture;
var
  a, b: TProbeWindow;
  p: TPoint;
begin
  a := NewWindow;
  b := NewWindow;
  NewWindow;
  p := FBar.StripItemRect(1).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseMove(p.X, p.Y + 60);
  AssertTrue('前提:拖着 b', FBar.IsDraggingForTest);
  b.Free;
  AssertEquals('拖着的窗口走了:手势结束(spec §9.7)', Ord(twgsIdle), Ord(FBar.GestureStateForTest));
  AssertEquals('反馈清掉', -1, FBar.DropSlotForTest);
  FBar.CallMouseUp(p.X, p.Y + 60);
  AssertSame('剩下的顺序不变', a, FBar.Windows[0]);
  { 临时光标弹过、处理器摘过:下一次拖动照常起、照常结束。 }
  p := FBar.StripItemRect(0).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseMove(p.X, p.Y + 60);
  AssertTrue('下一次照常拖', FBar.IsDraggingForTest);
  FBar.CallMouseUp(p.X, p.Y + 60);
  AssertSame('照常提交', a, FBar.Windows[1]);
end;

procedure TTyToolWindowReorderTests.TestWindowIndexReordersAndTheActivePageFollows;
var
  a, b, c, orphan: TProbeWindow;
begin
  a := NewWindow;
  b := NewWindow;
  c := NewWindow;
  FBar.ActiveWindow := b;
  FBar.OnChange := @HandleChange;
  ResetCounts;
  AssertEquals('WindowIndex 就是窗口序号', 1, b.WindowIndex);
  a.WindowIndex := 2;
  AssertSame('a 到了最后', a, FBar.Windows[2]);
  AssertSame('b 到了最前', b, FBar.Windows[0]);
  AssertSame('当前页不变', b, FBar.ActiveWindow);
  AssertEquals('ActiveIndex 跟着窗口', 0, FBar.ActiveIndex);
  AssertEquals('不发 OnChange', 0, FChanges);
  c.WindowIndex := 99;
  AssertEquals('钳到最后', 2, c.WindowIndex);
  c.WindowIndex := -5;
  AssertEquals('钳到最前', 0, c.WindowIndex);
  orphan := TProbeWindow.Create(FForm);
  AssertEquals('不在栏里是 -1', -1, orphan.WindowIndex);
  orphan.WindowIndex := 1;
  AssertEquals('不在栏里写了也没用', -1, orphan.WindowIndex);
end;

{ --- 退出路径 ------------------------------------------------------------------ }

type
  EOnMouseUpBoom = class(Exception);

procedure TTyToolWindowReorderTests.RaiseInMouseUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  raise EOnMouseUpBoom.Create('boom');
end;

procedure TTyToolWindowReorderTests.StartDrag(AIndex: Integer);
var
  p: TPoint;
begin
  p := FBar.StripItemRect(AIndex).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseMove(p.X, p.Y + 60);
  AssertTrue('前提:拖起来了', FBar.IsDraggingForTest);
  AssertEquals('前提:拖动光标压上了', Ord(crDrag), Ord(Screen.RealCursor));
end;

procedure TTyToolWindowReorderTests.TestASecondPressWhileDraggingUnwindsEverything;
var
  a, b: TProbeWindow;
  before: TCursor;
  p: TPoint;
begin
  a := NewWindow;
  b := NewWindow;
  NewWindow;
  FBar.ActiveWindow := a;
  { 哨兵:自己先压一层独有的光标,断言栈顶回到它。只记「之前是什么」的话,同一 suite 里
    前面哪条测试漏掉的一层 crDrag 会让 before 本身就是 crDrag,漏弹也照样绿。 }
  Screen.BeginTempCursor(crHandPoint);
  try
    before := Screen.RealCursor;
    StartDrag(0);
    { 松开丢了:下一次按下直接落在 b 的图标上。 }
    p := FBar.StripItemRect(1).CenterPoint;
    FBar.CallMouseDown(p.X, p.Y);
    AssertEquals('临时光标弹回原样(栈顶是哨兵)', Ord(before), Ord(Screen.RealCursor));
  finally
    Screen.EndTempCursor(crHandPoint);
  end;
  AssertEquals('新的按下是一条新记录:武装着', Ord(twgsArmed), Ord(FBar.GestureStateForTest));
  AssertEquals('插入线清掉', -1, FBar.DropSlotForTest);
  AssertFalse('没有计时器', FBar.HasCaptureTimerForTest);
  FBar.CallMouseUp(p.X, p.Y);
  AssertSame('这次松开照常是点击', b, FBar.ActiveWindow);
  AssertSame('顺序没动', a, FBar.Windows[0]);
end;

procedure TTyToolWindowReorderTests.TestReleasingTheButtonAfterACancelResumesHover;
var
  q: TPoint;
begin
  NewWindow;
  NewWindow;
  StartDrag(0);
  FBar.Perform(LM_CANCELMODE, 0, 0);
  AssertEquals('前提:Cancelled', Ord(twgsCancelled), Ord(FBar.GestureStateForTest));
  q := FBar.StripItemRect(1).CenterPoint;
  FBar.CallMouseMove(q.X, q.Y);
  AssertEquals('还按着:仍是 Cancelled', Ord(twgsCancelled), Ord(FBar.GestureStateForTest));
  AssertEquals('还按着:不追悬停', -1, FBar.StripHover);
  FBar.CallMouseMove(q.X, q.Y, []);
  AssertEquals('按键松了(松开丢了):回到 Idle', Ord(twgsIdle), Ord(FBar.GestureStateForTest));
  AssertEquals('悬停追踪接着来', 1, FBar.StripHover);
end;

procedure TTyToolWindowReorderTests.TestFreeingTheBarMidDragUnwindsTheCursorStack;
var
  before: TCursor;
begin
  NewWindow;
  NewWindow;
  { 哨兵同 TestASecondPressWhileDraggingUnwindsEverything。 }
  Screen.BeginTempCursor(crHandPoint);
  try
    before := Screen.RealCursor;
    StartDrag(0);
    FBar.Free;
    FBar := nil;
    AssertEquals('栏走了,临时光标也弹掉了(栈顶是哨兵)', Ord(before), Ord(Screen.RealCursor));
  finally
    Screen.EndTempCursor(crHandPoint);
  end;
  { Application 的处理器也摘干净了:失活时不会调进一个已经释放的栏。 }
  Application.IntfAppActivate;
  Application.IntfAppDeactivate;
end;

procedure TTyToolWindowReorderTests.TestApplicationDeactivationCancelsTheDrag;
var
  before: TCursor;
begin
  NewWindow;
  NewWindow;
  before := Screen.RealCursor;
  StartDrag(0);
  Application.IntfAppActivate;
  Application.IntfAppDeactivate;
  AssertEquals('失活:取消', Ord(twgsCancelled), Ord(FBar.GestureStateForTest));
  AssertEquals('光标弹回', Ord(before), Ord(Screen.RealCursor));
end;

procedure TTyToolWindowReorderTests.TestAnotherFormBecomingActiveCancelsTheDrag;
var
  other: TForm;
  before: TCursor;
begin
  NewWindow;
  NewWindow;
  before := Screen.RealCursor;
  other := TForm.CreateNew(nil);
  try
    StartDrag(0);
    { SetFocusedControl 是 LCL 通知「活动窗体换了」的那条真实路径(Screen.UpdateLastActive)。 }
    other.SetFocusedControl(other);
    AssertEquals('别的窗体成了活动窗体:取消', Ord(twgsCancelled), Ord(FBar.GestureStateForTest));
    AssertEquals('光标弹回', Ord(before), Ord(Screen.RealCursor));
  finally
    other.Free;
  end;
end;

procedure TTyToolWindowReorderTests.TestAPlacementChangeCancelsTheDragAndTheResize;
var
  e: TPoint;
begin
  NewWindow;
  NewWindow;
  StartDrag(0);
  FBar.Placement := twpRight;
  AssertFalse('改 Placement:拖动取消', FBar.IsDraggingForTest);
  FBar.Placement := twpLeft;
  FBar.ExpandedSize := 200;
  e := FBar.EdgeRect.CenterPoint;
  FBar.CallMouseDown(e.X, e.Y);
  FBar.CallMouseMove(e.X + 40, e.Y);
  AssertEquals('前提:拉宽实时写', 240, FBar.ExpandedSize);
  FBar.Placement := twpRight;
  AssertFalse('改 Placement:拉宽结束', FBar.IsEdgeDraggingForTest);
  AssertEquals('并回到起点', 200, FBar.ExpandedSize);
end;

procedure TTyToolWindowReorderTests.TestDisablingOrHidingTheBarEndsTheGestures;
var
  before: TCursor;
  e: TPoint;
begin
  NewWindow;
  NewWindow;
  before := Screen.RealCursor;
  StartDrag(0);
  FBar.Enabled := False;
  AssertFalse('禁用:拖动结束', FBar.IsDraggingForTest);
  AssertEquals('光标弹回', Ord(before), Ord(Screen.RealCursor));
  FBar.Enabled := True;
  StartDrag(0);
  FBar.Visible := False;
  AssertFalse('藏起来:拖动结束', FBar.IsDraggingForTest);
  AssertEquals('光标弹回', Ord(before), Ord(Screen.RealCursor));
  FBar.Visible := True;
  FBar.ExpandedSize := 200;
  e := FBar.EdgeRect.CenterPoint;
  FBar.CallMouseDown(e.X, e.Y);
  FBar.CallMouseMove(e.X + 40, e.Y);
  FBar.Enabled := False;
  AssertFalse('禁用:拉宽结束', FBar.IsEdgeDraggingForTest);
  AssertEquals('并回到起点', 200, FBar.ExpandedSize);
  FBar.Enabled := True;
  FBar.CallMouseDown(e.X, e.Y);
  FBar.CallMouseMove(e.X + 40, e.Y);
  FBar.Visible := False;
  AssertFalse('藏起来:拉宽结束', FBar.IsEdgeDraggingForTest);
  AssertEquals('并回到起点', 200, FBar.ExpandedSize);
end;

procedure TTyToolWindowReorderTests.TestAnExceptionInOnMouseUpLeavesNoGestureBehind;
var
  a: TProbeWindow;
  before: TCursor;
  p: TPoint;
  raised: Boolean;
begin
  a := NewWindow;
  NewWindow;
  NewWindow;
  before := Screen.RealCursor;
  FBar.OnMouseUp := @RaiseInMouseUp;
  StartDrag(0);
  p := FBar.StripItemRect(0).CenterPoint;
  raised := False;
  try
    FBar.CallMouseUp(p.X, p.Y + 60);
  except
    on EOnMouseUpBoom do raised := True;
  end;
  AssertTrue('前提:用户的 OnMouseUp 抛了', raised);
  AssertFalse('拖动不许留着', FBar.IsDraggingForTest);
  AssertEquals('光标弹回', Ord(before), Ord(Screen.RealCursor));
  AssertEquals('插入线清掉', -1, FBar.DropSlotForTest);
  AssertSame('也没提交', a, FBar.Windows[0]);
end;

initialization
  RegisterTest(TTyToolWindowReorderTests);
end.
