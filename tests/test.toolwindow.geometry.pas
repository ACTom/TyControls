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

initialization
  RegisterTest(TTyToolWindowGeometryTests);
end.
