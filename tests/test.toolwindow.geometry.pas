unit test.toolwindow.geometry;
{$mode objfpc}{$H+}
interface
uses
  Classes, Types, fpcunit, testregistry,
  { 只为它的 initialization —— 四个 RegisterClass 就发生在那里,别当成没用的 uses 删掉。 }
  tyControls.ToolWindows;

type
  TTyToolWindowGeometryTests = class(TTestCase)
  published
    procedure TestEveryClassIsRegisteredForStreaming;
    procedure TestSideHeaderGivesActionsItsWidthAndClipsTheCaption;
    procedure TestSideHeaderWithoutActionsPadsTheTrailingEdge;
    procedure TestNarrowSideHeaderKeepsOnlyTheLeadingPadForTheActions;
    procedure TestStripKeepsTheActiveIconWhenItOverflows;
    procedure TestSlotAtMapsGapsToWindowIndexes;
    procedure TestSlotAtMapsWindowIndexesOnANonPrefixStrip;
    procedure TestSideHeaderMirrorsUnderRightToLeft;
    procedure TestDragThresholdScalesWithPpi;
    procedure TestStripWithNoWidthLaysOutNothing;
    procedure TestVisiblePlanKeepsTheActiveItemWhenNothingFits;
    procedure TestVisiblePlanClampsNegativeInputs;
    procedure TestStripClipsTheLastSlotToTheBand;
    procedure TestFlipAllMirrorsAZeroWidthRectInPlace;
    procedure TestFlipAllCoversEveryRectAndTab;
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
  { spec §3.4:「操作区自带内边距,宽为 0 时尾端补一个 header-pad」—— 尾端的 pad 只在
    没有操作区时才补。操作区的首选宽本来就含它自己两侧的 2×pad,再补一个的话
    最后一个按钮离右边是 12px 而不是 6px。这里原先钉的就是那个多出来的 pad。 }
  AssertEquals('操作区贴到行的右端,尾端不再补 pad(§3.4:操作区自带内边距)', 200 - 80, g.Actions.Left);
  AssertEquals('操作区右边就是行的右边(§3.4:宽为 0 时才补尾端 pad)', 200, g.Actions.Right);
  AssertEquals('操作区保住自己的宽', 80, g.Actions.Right - g.Actions.Left);
  AssertEquals('标题从左内距开始', 6, g.Caption.Left);
  AssertEquals('标题被挤到操作区左边,隔一个 gap(§3.4:[pad][标题][gap][操作区])',
    200 - 80 - 4, g.Caption.Right);
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

procedure TTyToolWindowGeometryTests.TestNarrowSideHeaderKeepsOnlyTheLeadingPadForTheActions;
var
  inp: TTyToolWindowHeaderInput;
  g: TTyToolWindowHeaderGeom;
begin
  { 行比操作区还窄:操作区优先保宽,但前导那个 pad 要留出来 —— 尾端不再留(§3.4:
    操作区自带内边距),所以钳位只扣一个 pad,不是两个。 }
  inp := Default(TTyToolWindowHeaderInput);
  inp.Mode := twhSide;
  inp.RowWidth := 50;
  inp.RowHeight := 26;
  inp.Pad := 6;
  inp.Gap := 4;
  inp.ActionsWidth := 80;
  g := TyToolWindowHeaderLayout(inp);
  AssertEquals('操作区从前导内距开始,不吃掉它', 6, g.Actions.Left);
  AssertEquals('操作区一直到行的右端', 50, g.Actions.Right);
  AssertTrue('标题没地方了', g.Caption.Right <= g.Caption.Left);
end;

procedure TTyToolWindowGeometryTests.TestStripKeepsTheActiveIconWhenItOverflows;
var
  slots: TTyToolWindowSlots;
  i, seen: Integer;
begin
  { 高度 150、每项 36、溢出按钮 36、当前页是第 8 个,排出来是 [0, 1, 8]:
      Fill(150) 排上 4 项(144) → 还剩 6 个没排上,判溢出
      → 给溢出按钮留位置,budget = 150 - 36 = 114
      → Fill(114) 排上 3 项(108)= [0, 1, 2]
      → 当前页 8 不在里面,追加成 [0, 1, 2, 8](144 > 114)
      → 从它前面一个往前挤,去掉项 2 得 [0, 1, 8](108 ≤ 114)。
    下面那条非前缀测试就建立在这个 114 上。 }
  slots := TyToolWindowStripLayout(36, 150, 36, 36, 10, 8);
  AssertTrue('十个图标放不下,必须有被收起来的', Length(slots) < 10);
  seen := -1;
  for i := 0 to High(slots) do
    if slots[i].ItemIndex = 8 then seen := i;
  AssertTrue('当前页的图标必须留在条上', seen >= 0);
  AssertEquals('当前页被追加到末尾', High(slots), seen);
end;

procedure TTyToolWindowGeometryTests.TestSlotAtMapsGapsToWindowIndexes;
var
  slots: TTyToolWindowSlots;
begin
  slots := TyToolWindowStripLayout(36, 200, 36, 36, 4, 0);
  AssertEquals('四个图标放得下', 4, Length(slots));
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
begin
  { 溢出时排出来的是 [0, 1, 8] —— 已排布项不是窗口列表的前缀,
    所以空隙必须答**窗口序号**,不是排布序号。 }
  slots := TyToolWindowStripLayout(36, 150, 36, 36, 10, 8);
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
  AssertEquals('RTL:操作区贴到行的左端(尾端),不补 pad(§3.4:操作区自带内边距)', 0, rtl.Actions.Left);
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
  byWidth, byHeight: TTyToolWindowSlots;
begin
  { 条宽跟其他三个入参一样要守 —— 不守就会产出一批零宽/反转矩形。 }
  byWidth := TyToolWindowStripLayout(0, 200, 36, 36, 4, 0);
  byHeight := TyToolWindowStripLayout(36, 0, 36, 36, 4, 0);
  AssertEquals('条宽为 0 就一个槽都不排', 0, Length(byWidth));
  AssertEquals('条高为 0 同理', 0, Length(byHeight));
  { 两条轴上同样是「条上一个都没有、模型里还有四个」,对「有没有被收起来」就必须
    答同一句话。老的 out AAnyHidden 正是在这里答岔的:按高退化答 True、按宽退化答 False。 }
  AssertEquals('两条轴对「有没有被收起来」必须答同一句话',
    Length(byWidth) < 4, Length(byHeight) < 4);
end;

procedure TTyToolWindowGeometryTests.TestVisiblePlanKeepsTheActiveItemWhenNothingFits;
var
  zero, tight: TTyToolWindowPlan;
begin
  { 「可用宽为 0」和「留出溢出按钮后一个都放不下」是同一件事的两条路径
    (spec §7.3:当前页始终留在行上),必须答同一句话。 }
  zero := TyToolWindowVisiblePlan(0, [36, 36, 36], 2, 36);
  tight := TyToolWindowVisiblePlan(20, [36, 36, 36], 2, 36);
  AssertEquals('可用宽为 0:只留当前页', 1, Length(zero));
  AssertEquals('留出溢出按钮后放不下:也只留当前页', 1, Length(tight));
  AssertEquals('两条路径留下的是同一个', tight[0], zero[0]);
  AssertEquals('留下的就是当前页', 2, zero[0]);
end;

procedure TTyToolWindowGeometryTests.TestVisiblePlanClampsNegativeInputs;
const
  Avail = 100;
  NegItem: array[0..3] of Integer = (36, -20, 36, 36);
  Wide: array[0..2] of Integer = (60, 60, 60);

  function Total(const APlan: TTyToolWindowPlan; const AW: array of Integer): Integer;
  var
    i: Integer;
  begin
    Result := 0;
    for i := 0 to High(APlan) do
      if AW[APlan[i]] > 0 then Inc(Result, AW[APlan[i]]);
  end;

begin
  { 负的项宽让「放不下就停」的累加倒退,负的溢出按钮宽把预算放大 —— 两个都能排出
    一个塞不进可用宽的计划。B 期的 TabWidths 是量文字来的,一次测量失败就喂进负数。 }
  AssertTrue('负的项宽:排上去的总宽不许超过可用宽',
    Total(TyToolWindowVisiblePlan(Avail, NegItem, 0, -1000), NegItem) <= Avail);
  AssertTrue('负的溢出按钮宽:预算不许被放大',
    Total(TyToolWindowVisiblePlan(Avail, Wide, 2, -1000), Wide) <= Avail);
end;

procedure TTyToolWindowGeometryTests.TestStripClipsTheLastSlotToTheBand;
var
  slots: TTyToolWindowSlots;
begin
  { 条高 20 连一个 36 的图标都放不下,但当前页必须留下 —— 留下的那个槽位要裁进条内,
    不然它戳在条外面。 }
  slots := TyToolWindowStripLayout(36, 20, 36, 36, 3, 2);
  AssertEquals('当前页还是留下了', 1, Length(slots));
  AssertEquals('留下的是当前页', 2, slots[0].ItemIndex);
  AssertEquals('槽位裁进条内', 20, slots[0].ItemRect.Bottom);
  AssertTrue('裁完不反转', slots[0].ItemRect.Bottom >= slots[0].ItemRect.Top);
end;

procedure TTyToolWindowGeometryTests.TestFlipAllMirrorsAZeroWidthRectInPlace;
var
  g: TTyToolWindowHeaderGeom;
begin
  g := Default(TTyToolWindowHeaderGeom);
  { 被挤成零宽但**有位置**的部件(B 期的分隔线、溢出按钮会这样)必须跟着镜像;
    只有全零那个「没有这个部件」的哨兵才豁免。 }
  g.Separator := Rect(150, 0, 150, 26);
  TyToolWindowFlipAll(g, 200);
  AssertEquals('零宽但有位置的矩形照样镜像', 50, g.Separator.Left);
  AssertEquals('零宽镜像完还是零宽', 50, g.Separator.Right);
  AssertEquals('全零哨兵原地不动', 0, g.Overflow.Left);
  AssertEquals('全零哨兵原地不动', 0, g.Overflow.Right);
end;

procedure TTyToolWindowGeometryTests.TestFlipAllCoversEveryRectAndTab;
var
  g: TTyToolWindowHeaderGeom;
begin
  g := Default(TTyToolWindowHeaderGeom);
  g.Caption := Rect(10, 0, 20, 26);
  g.Actions := Rect(10, 0, 20, 26);
  g.TabArea := Rect(10, 0, 20, 26);
  g.Overflow := Rect(10, 0, 20, 26);
  g.Separator := Rect(10, 0, 20, 26);
  g.Maximize := Rect(10, 0, 20, 26);
  g.Collapse := Rect(10, 0, 20, 26);
  SetLength(g.Tabs, 1);
  g.Tabs[0].ItemIndex := 3;
  g.Tabs[0].ItemRect := Rect(10, 0, 20, 26);
  TyToolWindowFlipAll(g, 200);
  { 漏掉任何一个字段,B 期那个部件就原地留在 LTR 坐标,而 LTR 那边全绿。 }
  AssertEquals('Caption', 180, g.Caption.Left);
  AssertEquals('Actions', 180, g.Actions.Left);
  AssertEquals('TabArea', 180, g.TabArea.Left);
  AssertEquals('Overflow', 180, g.Overflow.Left);
  AssertEquals('Separator', 180, g.Separator.Left);
  AssertEquals('Maximize', 180, g.Maximize.Left);
  AssertEquals('Collapse', 180, g.Collapse.Left);
  AssertEquals('Tabs[0].ItemRect', 180, g.Tabs[0].ItemRect.Left);
  AssertEquals('镜像不动纵向', 26, g.Caption.Bottom);
  AssertEquals('槽位的窗口序号不变', 3, g.Tabs[0].ItemIndex);
end;

initialization
  RegisterTest(TTyToolWindowGeometryTests);
end.
