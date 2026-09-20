unit test.toolwindow.geometry;
{$mode objfpc}{$H+}
interface
uses
  Classes, fpcunit, testregistry,
  { 只为它的 initialization —— 四个 RegisterClass 就发生在那里,别当成没用的 uses 删掉。 }
  tyControls.ToolWindows;

type
  TTyToolWindowGeometryTests = class(TTestCase)
  published
    procedure TestEveryClassIsRegisteredForStreaming;
    procedure TestSideHeaderGivesActionsItsWidthAndClipsTheCaption;
    procedure TestSideHeaderWithoutActionsPadsTheTrailingEdge;
    procedure TestStripKeepsTheActiveIconWhenItOverflows;
    procedure TestSlotAtMapsGapsToWindowIndexes;
    procedure TestSlotAtMapsWindowIndexesOnANonPrefixStrip;
    procedure TestSideHeaderMirrorsUnderRightToLeft;
    procedure TestDragThresholdScalesWithPpi;
    procedure TestStripWithNoWidthLaysOutNothing;
    procedure TestVisiblePlanKeepsTheActiveItemWhenNothingFits;
  end;

implementation

procedure TTyToolWindowGeometryTests.TestEveryClassIsRegisteredForStreaming;
begin
  { 这一条守的正是本任务交付的东西:漏掉任何一句 RegisterClass,读 .lfm 时按类名
    就找不到类。 }
  AssertNotNull('TTyToolWindow 必须注册', GetClass('TTyToolWindow'));
  AssertNotNull('TTyToolWindowActions 必须注册', GetClass('TTyToolWindowActions'));
  AssertNotNull('TTyToolWindowBar 必须注册', GetClass('TTyToolWindowBar'));
  AssertNotNull('TTyToolWindowManager 必须注册', GetClass('TTyToolWindowManager'));
end;

procedure TTyToolWindowGeometryTests.TestSideHeaderGivesActionsItsWidthAndClipsTheCaption;
var
  inp: TTyToolWindowHeaderInput;
  g: TTyToolWindowHeaderGeom;
begin
  inp := Default(TTyToolWindowHeaderInput);
  inp.Mode := twhSide;
  inp.RowWidth := 200;
  inp.RowHeight := 26;
  inp.Pad := 6;
  inp.Gap := 4;
  inp.ActionsWidth := 80;
  g := TyToolWindowHeaderLayout(inp);
  AssertEquals('操作区贴右端', 200 - 6 - 80, g.Actions.Left);
  AssertEquals('操作区保住自己的宽', 80, g.Actions.Right - g.Actions.Left);
  AssertEquals('标题从左内距开始', 6, g.Caption.Left);
  AssertEquals('标题被挤到操作区左边', 200 - 6 - 80 - 4, g.Caption.Right);
  AssertEquals('操作区从行顶开始', 0, g.Actions.Top);
  AssertEquals('操作区占满行高', 26, g.Actions.Bottom);
  AssertEquals('标题从行顶开始', 0, g.Caption.Top);
  AssertEquals('标题占满行高', 26, g.Caption.Bottom);
end;

procedure TTyToolWindowGeometryTests.TestSideHeaderWithoutActionsPadsTheTrailingEdge;
var
  inp: TTyToolWindowHeaderInput;
  g: TTyToolWindowHeaderGeom;
begin
  inp := Default(TTyToolWindowHeaderInput);
  inp.Mode := twhSide;
  inp.RowWidth := 200;
  inp.RowHeight := 26;
  inp.Pad := 6;
  inp.Gap := 4;
  inp.ActionsWidth := 0;
  g := TyToolWindowHeaderLayout(inp);
  AssertEquals('没有操作区时标题止于右内距', 200 - 6, g.Caption.Right);
  AssertTrue('没有操作区就是空矩形', g.Actions.Right <= g.Actions.Left);
  AssertEquals('标题从行顶开始', 0, g.Caption.Top);
  AssertEquals('标题占满行高', 26, g.Caption.Bottom);
end;

procedure TTyToolWindowGeometryTests.TestStripKeepsTheActiveIconWhenItOverflows;
var
  slots: TTyToolWindowSlots;
  hidden: Boolean;
  i, seen: Integer;
begin
  { 高度 150、每项 36、溢出按钮 36 —— 放得下 3 项 + 溢出按钮。当前页是第 8 个。 }
  slots := TyToolWindowStripLayout(36, 150, 36, 36, 10, 8, hidden);
  AssertTrue('十个图标放不下,必须报溢出', hidden);
  seen := -1;
  for i := 0 to High(slots) do
    if slots[i].ItemIndex = 8 then seen := i;
  AssertTrue('当前页的图标必须留在条上', seen >= 0);
  AssertEquals('当前页被追加到末尾', High(slots), seen);
end;

procedure TTyToolWindowGeometryTests.TestSlotAtMapsGapsToWindowIndexes;
var
  slots: TTyToolWindowSlots;
  hidden: Boolean;
begin
  slots := TyToolWindowStripLayout(36, 200, 36, 36, 4, 0, hidden);
  AssertFalse('四个图标放得下', hidden);
  AssertEquals('第一个图标的上半 → 插到它前面', 0,
    TyToolWindowSlotAt(slots, 18, slots[0].ItemRect.Top + 4, True, 4));
  AssertEquals('第一个图标的下半 → 插到它后面', 1,
    TyToolWindowSlotAt(slots, 18, slots[0].ItemRect.Bottom - 4, True, 4));
  AssertEquals('最后一个图标之后 → 末尾', 4,
    TyToolWindowSlotAt(slots, 18, slots[3].ItemRect.Bottom + 2, True, 4));
end;

procedure TTyToolWindowGeometryTests.TestSlotAtMapsWindowIndexesOnANonPrefixStrip;
var
  slots: TTyToolWindowSlots;
  hidden: Boolean;
begin
  { 溢出时排出来的是 [0, 1, 8] —— 已排布项不是窗口列表的前缀,
    所以空隙必须答**窗口序号**,不是排布序号。 }
  slots := TyToolWindowStripLayout(36, 150, 36, 36, 10, 8, hidden);
  AssertEquals('条上只剩三个', 3, Length(slots));
  AssertEquals('第三个是被强制留下的当前页', 8, slots[2].ItemIndex);
  AssertEquals('图标 1 的下半 → 插到窗口 8 前面(不是 2)', 8,
    TyToolWindowSlotAt(slots, 18, slots[1].ItemRect.Bottom - 4, True, 10));
  AssertEquals('最后一个图标之后 → 窗口 9(不是 3)', 9,
    TyToolWindowSlotAt(slots, 18, slots[2].ItemRect.Bottom + 2, True, 10));
end;

procedure TTyToolWindowGeometryTests.TestSideHeaderMirrorsUnderRightToLeft;
var
  inp: TTyToolWindowHeaderInput;
  ltr, rtl: TTyToolWindowHeaderGeom;
begin
  inp := Default(TTyToolWindowHeaderInput);
  inp.Mode := twhSide;
  inp.RowWidth := 200;
  inp.RowHeight := 26;
  inp.Pad := 6;
  inp.Gap := 4;
  inp.ActionsWidth := 80;
  ltr := TyToolWindowHeaderLayout(inp);
  inp.RightToLeft := True;
  rtl := TyToolWindowHeaderLayout(inp);
  AssertEquals('RTL:操作区贴左内距', 6, rtl.Actions.Left);
  AssertEquals('RTL:操作区保住自己的宽',
    ltr.Actions.Right - ltr.Actions.Left, rtl.Actions.Right - rtl.Actions.Left);
  AssertEquals('RTL:标题在操作区右边,隔一个 gap',
    rtl.Actions.Right + 4, rtl.Caption.Left);
  AssertEquals('RTL:标题止于右内距', 200 - 6, rtl.Caption.Right);
  AssertEquals('RTL:标题宽度和 LTR 一样',
    ltr.Caption.Right - ltr.Caption.Left, rtl.Caption.Right - rtl.Caption.Left);
  AssertEquals('镜像不动纵向', 0, rtl.Caption.Top);
  AssertEquals('镜像不动纵向', 26, rtl.Caption.Bottom);
end;

procedure TTyToolWindowGeometryTests.TestDragThresholdScalesWithPpi;
begin
  AssertEquals('96 DPI 就是那个逻辑像素数', 6, TyToolWindowDragThreshold(96));
  AssertEquals('144 DPI 跟着放大', 9, TyToolWindowDragThreshold(144));
  AssertEquals('PPI 传 0 回落到 96', 6, TyToolWindowDragThreshold(0));
  AssertEquals('PPI 传负数回落到 96', 6, TyToolWindowDragThreshold(-120));
  AssertEquals('再小也不能是 0 —— 0 阈值等于每次按下都成拖动', 1,
    TyToolWindowDragThreshold(1));
end;

procedure TTyToolWindowGeometryTests.TestStripWithNoWidthLaysOutNothing;
var
  slots: TTyToolWindowSlots;
  hidden: Boolean;
begin
  { 条宽跟其他三个入参一样要守 —— 不守就会产出一批零宽/反转矩形。 }
  slots := TyToolWindowStripLayout(0, 200, 36, 36, 4, 0, hidden);
  AssertEquals('条宽为 0 就一个槽都不排', 0, Length(slots));
  AssertFalse('一个都没排上不等于有东西被收起来', hidden);
end;

procedure TTyToolWindowGeometryTests.TestVisiblePlanKeepsTheActiveItemWhenNothingFits;
var
  plan: TTyToolWindowPlan;
  hidden: Boolean;
begin
  plan := TyToolWindowVisiblePlan(0, [36, 36, 36], 2, 36, hidden);
  AssertEquals('可用宽为 0 时也要留住当前页,和 0 < 可用宽 <= 溢出按钮宽 '
    + '那条路径一致(spec §7.3:当前页始终留在行上)', 1, Length(plan));
  AssertEquals('留下的就是当前页', 2, plan[0]);
  AssertTrue('另外两个确实被收起来了', hidden);
end;

initialization
  RegisterTest(TTyToolWindowGeometryTests);
end.
