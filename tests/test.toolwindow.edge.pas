unit test.toolwindow.edge;
{$mode objfpc}{$H+}

{ 拉宽边(spec §6.3):实时写 ExpandedSize、吸附收起、中途取消、悬停。夹具在 test.toolwindow.bar。 }

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
  TTyToolWindowEdgeTests = class(TTyToolWindowBarFixture)
  published
    procedure TestEdgeDragWritesExpandedSizeLive;
    procedure TestEdgeDragSnapsClosedBelowHalfTheMinimum;
    procedure TestEdgeDragBackAboveTheSnapDoesNotCollapse;
    procedure TestEdgeDragCancelRestoresTheStartValue;
    procedure TestRightBarGrowsLeftwardsAndBottomBarUpwards;
    procedure TestTheEdgeIsInertWithoutWindowsAndAtDesignTime;
    procedure TestHoveringTheEdgeShowsTheResizeCursorAndHoverColour;
    procedure TestMovingAlongTheEdgeWritesTheCursorOnce;
    procedure TestFreeingTheBarMidResizeIsQuiet;
    procedure TestAPressAfterALostReleaseRestoresTheStartSize;
  end;

implementation

procedure TTyToolWindowEdgeTests.TestEdgeDragWritesExpandedSizeLive;
var
  e: TPoint;
begin
  NewWindow;
  FBar.ExpandedSize := 200;
  e := FBar.EdgeRect.CenterPoint;
  FBar.CallMouseDown(e.X, e.Y);
  AssertTrue('按在边缘区上开始拉宽', FBar.IsEdgeDraggingForTest);
  FBar.CallMouseMove(e.X + 30, e.Y);
  AssertEquals('拖动过程中就写', 230, FBar.ExpandedSize);
  AssertEquals('宽跟着推', StripPx + EdgePx + 230, FBar.Width);
  FBar.CallMouseUp(e.X + 30, e.Y);
  AssertEquals('松开保持', 230, FBar.ExpandedSize);
  AssertFalse('没收起', FBar.Collapsed);
  AssertFalse('拉宽结束', FBar.IsEdgeDraggingForTest);
end;

procedure TTyToolWindowEdgeTests.TestEdgeDragSnapsClosedBelowHalfTheMinimum;
var
  e: TPoint;
begin
  NewWindow;
  FBar.ExpandedSize := 200;
  e := FBar.EdgeRect.CenterPoint;
  FBar.CallMouseDown(e.X, e.Y);
  { 不到一半之前:钳在 content-min,不收起。 }
  FBar.CallMouseMove(e.X - (200 - ContentMinPx + 20), e.Y);
  AssertEquals('一半以上、下限以下:钳在下限', ContentMinPx, FBar.ExpandedSize);
  AssertEquals('还是展开排布', StripPx + EdgePx + ContentMinPx, FBar.Width);
  { 从 200 往回拖到 content-min 的一半以下。 }
  FBar.CallMouseMove(e.X - (200 - ContentMinPx div 2 + 10), e.Y);
  AssertEquals('实时按收起排布:只剩图标条', StripPx, FBar.Width);
  AssertEquals('ExpandedSize 停在起点', 200, FBar.ExpandedSize);
  AssertFalse('拖动中还没写 Collapsed', FBar.Collapsed);
  FBar.CallMouseUp(e.X - (200 - ContentMinPx div 2 + 10), e.Y);
  AssertTrue('松开时处在吸附排布:收起', FBar.Collapsed);
  AssertEquals('ExpandedSize 仍是起点', 200, FBar.ExpandedSize);
  AssertEquals('收起的宽', StripPx, FBar.Width);
end;

procedure TTyToolWindowEdgeTests.TestEdgeDragBackAboveTheSnapDoesNotCollapse;
var
  e: TPoint;
begin
  NewWindow;
  FBar.ExpandedSize := 200;
  e := FBar.EdgeRect.CenterPoint;
  FBar.CallMouseDown(e.X, e.Y);
  FBar.CallMouseMove(e.X - 190, e.Y);
  AssertEquals('前提:吸附着', StripPx, FBar.Width);
  FBar.CallMouseMove(e.X - 20, e.Y);
  AssertEquals('拖回来:恢复展开、继续实时写', 180, FBar.ExpandedSize);
  AssertEquals('展开排布', StripPx + EdgePx + 180, FBar.Width);
  FBar.CallMouseUp(e.X - 20, e.Y);
  AssertFalse('拖回来再松开不收起', FBar.Collapsed);
  AssertEquals('尺寸是最后写的那个', 180, FBar.ExpandedSize);
end;

procedure TTyToolWindowEdgeTests.TestEdgeDragCancelRestoresTheStartValue;
var
  e: TPoint;
begin
  NewWindow;
  FBar.ExpandedSize := 200;
  e := FBar.EdgeRect.CenterPoint;
  FBar.CallMouseDown(e.X, e.Y);
  FBar.CallMouseMove(e.X + 60, e.Y);
  AssertEquals('前提:拖到 260', 260, FBar.ExpandedSize);
  FBar.Perform(LM_CANCELMODE, 0, 0);
  AssertEquals('LM_CANCELMODE:回到起点', 200, FBar.ExpandedSize);
  AssertFalse('拉宽结束', FBar.IsEdgeDraggingForTest);
  FBar.CallMouseMove(e.X + 90, e.Y);
  AssertEquals('之后的移动不再写', 200, FBar.ExpandedSize);
  FBar.CallMouseUp(e.X + 90, e.Y);
  { 吸附中途被打断:回到展开排布,不写 Collapsed。 }
  e := FBar.EdgeRect.CenterPoint;
  FBar.CallMouseDown(e.X, e.Y);
  FBar.CallMouseMove(e.X - 190, e.Y);
  AssertEquals('前提:吸附着', StripPx, FBar.Width);
  FBar.Perform(LM_CANCELMODE, 0, 0);
  AssertEquals('打断吸附:回到展开的宽', StripPx + EdgePx + 200, FBar.Width);
  AssertFalse('不收起', FBar.Collapsed);
  { 拉宽中途 Collapsed 被别处改了:拉宽作废。 }
  e := FBar.EdgeRect.CenterPoint;
  FBar.CallMouseDown(e.X, e.Y);
  FBar.CallMouseMove(e.X + 40, e.Y);
  FBar.Collapsed := True;
  AssertEquals('Collapsed 被改:回到起点', 200, FBar.ExpandedSize);
  AssertFalse('拉宽结束', FBar.IsEdgeDraggingForTest);
  { 丢了松开(移动不带左键):也当被打断。 }
  FBar.Collapsed := False;
  e := FBar.EdgeRect.CenterPoint;
  FBar.CallMouseDown(e.X, e.Y);
  FBar.CallMouseMove(e.X + 40, e.Y);
  FBar.CallMouseMove(e.X + 50, e.Y, []);
  AssertEquals('没有 ssLeft 的移动:回到起点', 200, FBar.ExpandedSize);
  AssertFalse('拉宽结束', FBar.IsEdgeDraggingForTest);
end;

procedure TTyToolWindowEdgeTests.TestRightBarGrowsLeftwardsAndBottomBarUpwards;
var
  e: TPoint;
begin
  NewWindow;
  FBar.Placement := twpRight;
  FBar.ExpandedSize := 200;
  e := FBar.EdgeRect.CenterPoint;
  AssertEquals('右栏的边缘区在左边(靠编辑区)', 0, FBar.EdgeRect.Left);
  FBar.CallMouseDown(e.X, e.Y);
  FBar.CallMouseMove(e.X - 30, e.Y);
  AssertEquals('右栏向左拖是变宽', 230, FBar.ExpandedSize);
  FBar.CallMouseUp(e.X - 30, e.Y);
  { 底栏:侧 ↔ 底在运行时只有空栏改得动。 }
  FBar.Free;
  FBar := TBarAccess.Create(FForm);
  FBar.Parent := FForm;
  FBar.Controller := FCtl;
  FBar.Font.PixelsPerInch := 96;
  FBar.Placement := twpBottom;
  FBar.Width := 600;
  NewWindow;
  FBar.ExpandedSize := 150;
  e := FBar.EdgeRect.CenterPoint;
  AssertEquals('底栏的边缘区在顶边', 0, FBar.EdgeRect.Top);
  FBar.CallMouseDown(e.X, e.Y);
  FBar.CallMouseMove(e.X, e.Y - 25);
  AssertEquals('底栏向上拖是变高', 175, FBar.ExpandedSize);
  FBar.CallMouseUp(e.X, e.Y - 25);
end;

procedure TTyToolWindowEdgeTests.TestTheEdgeIsInertWithoutWindowsAndAtDesignTime;
var
  d: TBarAccess;
  e: TPoint;
begin
  AssertTrue('运行时空栏没有边缘区', IsRectEmpty(FBar.EdgeRect));
  d := NewDesignBar;
  NewWindowIn(d, FDesignOwner);
  d.ExpandedSize := 200;
  e := d.EdgeRect.CenterPoint;
  AssertFalse('设计期边缘区照画', IsRectEmpty(d.EdgeRect));
  d.CallMouseDown(e.X, e.Y);
  d.CallMouseMove(e.X + 40, e.Y);
  d.CallMouseUp(e.X + 40, e.Y);
  AssertFalse('设计期不拉宽(用设计器拖栏的边)', d.IsEdgeDraggingForTest);
  AssertEquals('ExpandedSize 不动', 200, d.ExpandedSize);
end;

procedure TTyToolWindowEdgeTests.TestHoveringTheEdgeShowsTheResizeCursorAndHoverColour;
const
  Olive = TColor($008080);   { CSS #808000 }
  Navy = TColor($800000);    { CSS #000080 }
var
  e: TPoint;
  bmp: TBitmap;
  area: Integer;
begin
  FCtl.StyleOverride := ':root { --toolwindow-edge-color: #000080;' +
    ' --toolwindow-edge-color-hover: #808000; }';
  NewWindow;
  FBar.Cursor := crHandPoint;
  e := FBar.EdgeRect.CenterPoint;
  area := (FBar.EdgeRect.Right - FBar.EdgeRect.Left) * (FBar.EdgeRect.Bottom - FBar.EdgeRect.Top);
  FBar.CallMouseMove(e.X, e.Y, []);
  AssertEquals('悬停在边缘区:调整光标', Ord(crHSplit), Ord(FBar.Cursor));
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, FBar.EdgeRect, Wipe);
  try
    AssertEquals('悬停:整块换成 :hover 的颜色', area, CountExact(bmp, Olive));
    AssertEquals('悬停:那条静止的线收掉', 0, CountExact(bmp, Navy));
  finally
    bmp.Free;
  end;
  FBar.CallMouseDown(e.X, e.Y);
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, FBar.EdgeRect, Wipe);
  try
    AssertEquals('拉宽中:整块同样是 :hover 的颜色', area, CountExact(bmp, Olive));
  finally
    bmp.Free;
  end;
  FBar.CallMouseUp(e.X, e.Y);
  FBar.CallMouseMove(FBar.BarLayout.Content.CenterPoint.X, e.Y, []);
  AssertEquals('离开边缘区:用户自己的光标原样还回去', Ord(crHandPoint), Ord(FBar.Cursor));
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, FBar.EdgeRect, Wipe);
  try
    AssertEquals('不悬停:没有 :hover 的颜色', 0, CountExact(bmp, Olive));
  finally
    bmp.Free;
  end;
end;

{ --- 悬停抖动与退出路径 ---------------------------------------------------------- }

procedure TTyToolWindowEdgeTests.TestMovingAlongTheEdgeWritesTheCursorOnce;
var
  e: TPoint;
  cw, inv: Integer;
begin
  NewWindow;
  e := FBar.EdgeRect.CenterPoint;
  FBar.CallMouseMove(e.X, e.Y, []);
  AssertEquals('前提:进了边缘区,光标换成调整光标', Ord(crHSplit), Ord(FBar.Cursor));
  cw := FBar.CursorWrites;
  inv := FBar.Invalidates;
  FBar.CallMouseMove(e.X, e.Y + 5, []);
  FBar.CallMouseMove(e.X, e.Y + 10, []);
  { 清边缘悬停只在指针真的离开边缘区时做:在里面移动,每一下都「清掉再设回去」的话,
    光标和整条栏各白写一遍。 }
  AssertEquals('在边缘区里移动:不再写 Cursor', cw, FBar.CursorWrites);
  AssertEquals('在边缘区里移动:不再重画', inv, FBar.Invalidates);
  FBar.CallMouseMove(FBar.BarLayout.Content.CenterPoint.X, e.Y, []);
  AssertFalse('离开边缘区:光标还回去', FBar.Cursor = crHSplit);
end;

procedure TTyToolWindowEdgeTests.TestFreeingTheBarMidResizeIsQuiet;
var
  e: TPoint;
begin
  NewWindow;
  FBar.ExpandedSize := 200;
  e := FBar.EdgeRect.CenterPoint;
  FBar.CallMouseDown(e.X, e.Y);
  FBar.CallMouseMove(e.X + 30, e.Y);
  AssertTrue('前提:拉宽中', FBar.IsEdgeDraggingForTest);
  { 析构里只清标志:回到起点要 Relayout,而栏已经拆了一半。 }
  FBar.Free;
  FBar := nil;
  Application.IntfAppActivate;
  Application.IntfAppDeactivate;
end;

procedure TTyToolWindowEdgeTests.TestAPressAfterALostReleaseRestoresTheStartSize;
var
  e, p: TPoint;
begin
  NewWindow;
  NewWindow;
  FBar.ExpandedSize := 200;
  e := FBar.EdgeRect.CenterPoint;
  FBar.CallMouseDown(e.X, e.Y);
  FBar.CallMouseMove(e.X + 30, e.Y);
  AssertEquals('前提:实时写', 230, FBar.ExpandedSize);
  { 松开丢了,下一次按下落在图标上:拉到一半的尺寸不许留下。 }
  p := FBar.StripItemRect(1).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  AssertFalse('拉宽结束', FBar.IsEdgeDraggingForTest);
  AssertEquals('回到起点', 200, FBar.ExpandedSize);
  AssertEquals('这次按下照常武装', Ord(twgsArmed), Ord(FBar.GestureStateForTest));
  FBar.CallMouseUp(p.X, p.Y);
end;

initialization
  RegisterTest(TTyToolWindowEdgeTests);
end.
