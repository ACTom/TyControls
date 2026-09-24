unit test.toolwindow.geometry;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, fpcunit, testregistry,
  { 只为它的 initialization —— 四个 RegisterClass 就发生在那里,别当成没用的 uses 删掉。 }
  tyControls.ToolWindows, tyControls.ToolWindows.Layout;

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
    procedure TestSameGeomComparesEveryRectAndTab;
    procedure TestActionsFlowFloorsEachItemAtItsMinimums;
    { 底栏标题行(spec §7.3,开工前问题 7):从尾端往前 [收起][最大化][分隔线][操作区][溢出][标签…]。 }
    procedure TestBottomRowLaysOutFromTheTrailingEnd;
    procedure TestBottomRowOverflowFollowsTheLastTab;
    procedure TestBottomRowKeepsTheActiveTabWhenOthersOverflow;
    procedure TestBottomRowSqueezesTheActionsDownToTheTabAreaMin;
    procedure TestBottomRowNarrowerThanItsButtonsClampsEverything;
    procedure TestBottomRowWithoutActionsGivesTheTabsTheRoom;
    procedure TestBottomRowWithoutWindowsKeepsOnlyTheButtons;
    procedure TestBottomRowMirrorsUnderRightToLeft;
    procedure TestBottomRowClampsTheButtonsToTheRowHeight;
    procedure TestBottomRowClampsNegativeInputs;
    { 命中是排布的精确逆运算。 }
    procedure TestZoneAtInvertsTheBottomLayout;
    procedure TestZoneAtAnswersNoneOffTheParts;
    procedure TestZoneAtOnASideRowIsAlwaysNone;
    procedure TestZoneAtNeverHitsAnEmptyPart;
    { spec §9.4:跨栏命中(TyToolWindowDropAt),表 D1–D15。 }
    procedure TestDropAtFindsSlotsOnTheSourceStrip;
    procedure TestDropAtSourceContentIsNoTarget;
    procedure TestDropAtOtherBarStripAndContent;
    procedure TestDropAtAVetoedBarIsNoTarget;
    procedure TestDropAtHolesAndNestedBars;
    procedure TestDropAtMapsToWindowIndexes;
    procedure TestDropAtClippedAndEmptyInputs;
  private
    { 公共输入:源栏 S、另一侧栏 T(spec §9.4 命中测试的几何:可见矩形、图标条、洞、槽位)。 }
    function ProbeS: TTyToolWindowDropProbe;
    function ProbeT: TTyToolWindowDropProbe;
    procedure CheckDrop(const AMsg: string; const AProbes: array of TTyToolWindowDropProbe;
      X, Y, AWantProbe, AWantSlot: Integer);
    procedure CheckRect(const AMsg: string; L, T, R, B: Integer; const ARect: TRect);
    { AExpected 是 (窗口序号, Left, Right) 三个一组;纵向一律 0..ARowH。 }
    procedure CheckTabs(const AMsg: string; const AGeom: TTyToolWindowHeaderGeom;
      ARowH: Integer; const AExpected: array of Integer);
    procedure CheckHidden(const AMsg: string; const AGeom: TTyToolWindowHeaderGeom;
      const AExpected: array of Integer);
    { 每个非空部件的中心都命中它自己(标签答窗口序号)。 }
    procedure CheckCentresHit(const AMsg: string; const AGeom: TTyToolWindowHeaderGeom);
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

{ 每次新建一份(动态数组在记录赋值时共享,拿 b := a 再改 b.Tabs[0] 会连 a 一起改)。 }
function FullGeom: TTyToolWindowHeaderGeom;
begin
  Result := Default(TTyToolWindowHeaderGeom);
  Result.Caption := Rect(1, 0, 11, 26);
  Result.Actions := Rect(2, 0, 12, 26);
  Result.TabArea := Rect(3, 0, 13, 26);
  Result.Overflow := Rect(4, 0, 14, 26);
  Result.Separator := Rect(5, 0, 15, 26);
  Result.Maximize := Rect(6, 0, 16, 26);
  Result.Collapse := Rect(7, 0, 17, 26);
  SetLength(Result.Tabs, 2);
  Result.Tabs[0].ItemIndex := 0;
  Result.Tabs[0].ItemRect := Rect(20, 0, 40, 26);
  Result.Tabs[1].ItemIndex := 5;
  Result.Tabs[1].ItemRect := Rect(40, 0, 60, 26);
  SetLength(Result.Hidden, 1);
  Result.Hidden[0] := 3;
end;

procedure TTyToolWindowGeometryTests.TestSameGeomComparesEveryRectAndTab;
var
  b: TTyToolWindowHeaderGeom;
begin
  { 同 TestFlipAllCoversEveryRectAndTab 的形状:逐字段改一个值,每一处都要判成不同。
    漏比任何一个字段,B 期那个部件变了而控件尺寸没变,窗口就 blit 出旧的那一帧。 }
  AssertTrue('一模一样就是相同', TyToolWindowSameGeom(FullGeom, FullGeom));
  b := FullGeom; b.Caption.Right := 99;
  AssertFalse('Caption', TyToolWindowSameGeom(FullGeom, b));
  b := FullGeom; b.Actions.Left := 99;
  AssertFalse('Actions', TyToolWindowSameGeom(FullGeom, b));
  b := FullGeom; b.TabArea.Bottom := 99;
  AssertFalse('TabArea', TyToolWindowSameGeom(FullGeom, b));
  b := FullGeom; b.Overflow.Top := 9;
  AssertFalse('Overflow', TyToolWindowSameGeom(FullGeom, b));
  b := FullGeom; b.Separator.Right := 99;
  AssertFalse('Separator', TyToolWindowSameGeom(FullGeom, b));
  b := FullGeom; b.Maximize.Left := 99;
  AssertFalse('Maximize', TyToolWindowSameGeom(FullGeom, b));
  b := FullGeom; b.Collapse.Right := 99;
  AssertFalse('Collapse', TyToolWindowSameGeom(FullGeom, b));
  b := FullGeom; b.Tabs[1].ItemRect.Right := 99;
  AssertFalse('Tabs[1].ItemRect(标签宽变了)', TyToolWindowSameGeom(FullGeom, b));
  b := FullGeom; b.Tabs[1].ItemIndex := 6;
  AssertFalse('Tabs[1].ItemIndex', TyToolWindowSameGeom(FullGeom, b));
  b := FullGeom; SetLength(b.Tabs, 1);
  AssertFalse('标签个数', TyToolWindowSameGeom(FullGeom, b));
  b := FullGeom; b.Hidden[0] := 4;
  AssertFalse('Hidden[0]', TyToolWindowSameGeom(FullGeom, b));
  b := FullGeom; SetLength(b.Hidden, 0);
  AssertFalse('收起的个数', TyToolWindowSameGeom(FullGeom, b));
end;

procedure TTyToolWindowGeometryTests.TestActionsFlowFloorsEachItemAtItsMinimums;
var
  items: array[0..2] of TTyToolWindowFlowItem;
  fl: TTyToolWindowFlow;
begin
  { 宽按 max(Width, MinWidth)、高按 max(Height, MinHeight);最高的放中间,
    「取最后一个」这种错实现不会碰巧对。 }
  items[0].Width := 20; items[0].Height := 10; items[0].MinWidth := 40; items[0].MinHeight := 0;
  items[1].Width := 30; items[1].Height := 12; items[1].MinWidth := 0;  items[1].MinHeight := 30;
  items[2].Width := 10; items[2].Height := 18; items[2].MinWidth := 0;  items[2].MinHeight := 0;
  fl := TyToolWindowActionsFlow(items, 200, 40, 6, 4, False);
  AssertEquals('宽 = 2×pad + (40 + 30 + 10) + 2×gap', 12 + 80 + 8, fl.Size.cx);
  AssertEquals('高 = 最高的(MinHeight 30) + 2×pad', 30 + 12, fl.Size.cy);
  AssertEquals('第一个按 MinWidth 占 40', 40, fl.Rects[0].Right - fl.Rects[0].Left);
  AssertEquals('第二个从 pad + 40 + gap 开始', 6 + 40 + 4, fl.Rects[1].Left);
  AssertEquals('第二个按 MinHeight 高 30', 30, fl.Rects[1].Bottom - fl.Rects[1].Top);
  AssertEquals('第二个按下限居中', (40 - 30) div 2, fl.Rects[1].Top);
  fl := TyToolWindowActionsFlow([], 200, 40, 6, 4, False);
  AssertEquals('一项都没有:宽 0', 0, fl.Size.cx);
  AssertEquals('一项都没有:高 0', 0, fl.Size.cy);
end;

{ --- 底栏标题行 ---------------------------------------------------------------- }

{ 公共输入(计划 Task 2 的表):行高 26、pad 6、gap 4、按钮 22、分隔线槽 9、溢出 22、
  标签区下限 50、操作区 60、标签宽 [80, 70, 90]。 }
function BottomInput(ARowWidth, AActive: Integer): TTyToolWindowHeaderInput;
begin
  Result := Default(TTyToolWindowHeaderInput);
  Result.Mode := twhBottom;
  Result.RowWidth := ARowWidth;
  Result.RowHeight := 26;
  Result.Pad := 6;
  Result.Gap := 4;
  Result.ButtonSize := 22;
  Result.SeparatorWidth := 9;
  Result.OverflowWidth := 22;
  Result.TabAreaMin := 50;
  Result.ActionsWidth := 60;
  Result.TabWidths := nil;
  SetLength(Result.TabWidths, 3);
  Result.TabWidths[0] := 80;
  Result.TabWidths[1] := 70;
  Result.TabWidths[2] := 90;
  Result.ActiveIndex := AActive;
end;

{ 一套几何里的每一个矩形(含标签),方便整体扫。 }
type
  TRectArray = array of TRect;

function AllRects(const AGeom: TTyToolWindowHeaderGeom): TRectArray;
var
  i: Integer;
begin
  Result := nil;
  SetLength(Result, 7 + Length(AGeom.Tabs));
  Result[0] := AGeom.Caption;
  Result[1] := AGeom.Actions;
  Result[2] := AGeom.TabArea;
  Result[3] := AGeom.Overflow;
  Result[4] := AGeom.Separator;
  Result[5] := AGeom.Maximize;
  Result[6] := AGeom.Collapse;
  for i := 0 to High(AGeom.Tabs) do
    Result[7 + i] := AGeom.Tabs[i].ItemRect;
end;

procedure TTyToolWindowGeometryTests.CheckRect(const AMsg: string; L, T, R, B: Integer;
  const ARect: TRect);
begin
  AssertEquals(AMsg + ' Left', L, ARect.Left);
  AssertEquals(AMsg + ' Top', T, ARect.Top);
  AssertEquals(AMsg + ' Right', R, ARect.Right);
  AssertEquals(AMsg + ' Bottom', B, ARect.Bottom);
end;

procedure TTyToolWindowGeometryTests.CheckTabs(const AMsg: string;
  const AGeom: TTyToolWindowHeaderGeom; ARowH: Integer; const AExpected: array of Integer);
var
  i: Integer;
begin
  AssertEquals(AMsg + ':排上的标签个数', Length(AExpected) div 3, Length(AGeom.Tabs));
  for i := 0 to High(AGeom.Tabs) do
  begin
    AssertEquals(Format('%s:第 %d 格的窗口序号', [AMsg, i]), AExpected[3 * i],
      AGeom.Tabs[i].ItemIndex);
    CheckRect(Format('%s:第 %d 格', [AMsg, i]), AExpected[3 * i + 1], 0,
      AExpected[3 * i + 2], ARowH, AGeom.Tabs[i].ItemRect);
  end;
end;

procedure TTyToolWindowGeometryTests.CheckHidden(const AMsg: string;
  const AGeom: TTyToolWindowHeaderGeom; const AExpected: array of Integer);
var
  i: Integer;
begin
  AssertEquals(AMsg + ':收起的个数', Length(AExpected), Length(AGeom.Hidden));
  for i := 0 to High(AExpected) do
    AssertEquals(Format('%s:收起的第 %d 个', [AMsg, i]), AExpected[i], AGeom.Hidden[i]);
end;

procedure TTyToolWindowGeometryTests.CheckCentresHit(const AMsg: string;
  const AGeom: TTyToolWindowHeaderGeom);

  procedure One(const AName: string; const ARect: TRect; AZone: TTyToolWindowZone);
  var
    idx: Integer;
    c: TPoint;
  begin
    if (ARect.Right <= ARect.Left) or (ARect.Bottom <= ARect.Top) then Exit;
    c := ARect.CenterPoint;
    AssertEquals(AMsg + ':' + AName + ' 的中心', Ord(AZone),
      Ord(TyToolWindowZoneAt(AGeom, c.X, c.Y, idx)));
    AssertEquals(AMsg + ':' + AName + ' 不是标签,序号 -1', -1, idx);
  end;

var
  i, idx: Integer;
  c: TPoint;
begin
  One('溢出', AGeom.Overflow, twzOverflow);
  One('分隔线', AGeom.Separator, twzSeparator);
  One('最大化', AGeom.Maximize, twzMaximize);
  One('收起', AGeom.Collapse, twzCollapse);
  for i := 0 to High(AGeom.Tabs) do
  begin
    c := AGeom.Tabs[i].ItemRect.CenterPoint;
    AssertEquals(Format('%s:第 %d 格标签的中心', [AMsg, i]), Ord(twzTab),
      Ord(TyToolWindowZoneAt(AGeom, c.X, c.Y, idx)));
    AssertEquals(Format('%s:第 %d 格标签答的是窗口序号', [AMsg, i]),
      AGeom.Tabs[i].ItemIndex, idx);
  end;
end;

procedure TTyToolWindowGeometryTests.TestBottomRowLaysOutFromTheTrailingEnd;
var
  g: TTyToolWindowHeaderGeom;
begin
  { B1:全放得下。 }
  g := TyToolWindowHeaderLayout(BottomInput(400, 0));
  CheckRect('收起贴尾端内距', 372, 2, 394, 24, g.Collapse);
  CheckRect('最大化隔一个 gap', 346, 2, 368, 24, g.Maximize);
  CheckRect('分隔线槽占整行高', 337, 0, 346, 26, g.Separator);
  CheckRect('操作区保宽', 277, 0, 337, 26, g.Actions);
  CheckRect('标签区', 6, 0, 277, 26, g.TabArea);
  CheckTabs('标签按窗口顺序', g, 26, [0, 6, 86, 1, 86, 156, 2, 156, 246]);
  CheckRect('没有收起的就没有溢出按钮', 0, 0, 0, 0, g.Overflow);
  CheckHidden('B1', g, []);
end;

procedure TTyToolWindowGeometryTests.TestBottomRowOverflowFollowsTheLastTab;
var
  g: TTyToolWindowHeaderGeom;
begin
  { B2:放不下,溢出按钮紧跟最后一个已排标签(问题 7),不贴操作区。 }
  g := TyToolWindowHeaderLayout(BottomInput(300, 0));
  CheckRect('操作区', 177, 0, 237, 26, g.Actions);
  CheckRect('标签区', 6, 0, 177, 26, g.TabArea);
  CheckTabs('只剩第一个', g, 26, [0, 6, 86]);
  CheckRect('溢出紧跟在它后面', 86, 2, 108, 24, g.Overflow);
  CheckHidden('B2', g, [1, 2]);
end;

procedure TTyToolWindowGeometryTests.TestBottomRowKeepsTheActiveTabWhenOthersOverflow;
var
  g: TTyToolWindowHeaderGeom;
begin
  { B3:当前页是窗口 2,被强制留在行上 —— 它排在第一格,ItemIndex 答窗口序号 2。 }
  g := TyToolWindowHeaderLayout(BottomInput(300, 2));
  CheckTabs('当前页排在第一格', g, 26, [2, 6, 96]);
  CheckRect('溢出紧跟在它后面', 96, 2, 118, 24, g.Overflow);
  CheckHidden('B3', g, [0, 1]);
end;

procedure TTyToolWindowGeometryTests.TestBottomRowSqueezesTheActionsDownToTheTabAreaMin;
var
  g: TTyToolWindowHeaderGeom;
begin
  { B4:标签区缩到下限之后才压操作区;当前页的标签连单独都放不下时被截(画的时候出省略号)。 }
  g := TyToolWindowHeaderLayout(BottomInput(160, 0));
  CheckRect('分隔线', 97, 0, 106, 26, g.Separator);
  CheckRect('操作区被压到 41', 56, 0, 97, 26, g.Actions);
  CheckRect('标签区停在下限 50', 6, 0, 56, 26, g.TabArea);
  CheckTabs('当前页被截在溢出按钮前面', g, 26, [0, 6, 34]);
  CheckRect('溢出', 34, 2, 56, 24, g.Overflow);
  CheckHidden('B4', g, [1, 2]);
end;

procedure TTyToolWindowGeometryTests.TestBottomRowNarrowerThanItsButtonsClampsEverything;
var
  g: TTyToolWindowHeaderGeom;
  r: TRect;
begin
  { B5:行比固定部件还窄。固定部件不缩,放不下的那一截钳在 [0, 行宽] 里。 }
  g := TyToolWindowHeaderLayout(BottomInput(60, 1));
  CheckRect('收起', 32, 2, 54, 24, g.Collapse);
  CheckRect('最大化', 6, 2, 28, 24, g.Maximize);
  CheckRect('分隔线钳到行首', 0, 0, 6, 26, g.Separator);
  CheckRect('操作区压没了(全零哨兵)', 0, 0, 0, 0, g.Actions);
  AssertEquals('标签区宽 0', 0, g.TabArea.Right - g.TabArea.Left);
  AssertEquals('当前页还在', 1, Length(g.Tabs));
  AssertEquals('留下的是当前页', 1, g.Tabs[0].ItemIndex);
  AssertEquals('它宽 0', 0, g.Tabs[0].ItemRect.Right - g.Tabs[0].ItemRect.Left);
  CheckHidden('B5', g, [0, 2]);
  for r in AllRects(g) do
  begin
    AssertTrue('矩形不出行首', r.Left >= 0);
    AssertTrue('矩形不出行尾', r.Right <= 60);
    AssertTrue('矩形不反转', r.Right >= r.Left);
  end;
end;

procedure TTyToolWindowGeometryTests.TestBottomRowWithoutActionsGivesTheTabsTheRoom;
var
  inp: TTyToolWindowHeaderInput;
  g: TTyToolWindowHeaderGeom;
begin
  inp := BottomInput(400, 0);
  inp.ActionsWidth := 0;
  g := TyToolWindowHeaderLayout(inp);
  CheckRect('没有操作区:全零', 0, 0, 0, 0, g.Actions);
  CheckRect('标签区一直到分隔线', 6, 0, 337, 26, g.TabArea);
end;

procedure TTyToolWindowGeometryTests.TestBottomRowWithoutWindowsKeepsOnlyTheButtons;
var
  inp: TTyToolWindowHeaderInput;
  g: TTyToolWindowHeaderGeom;
begin
  inp := BottomInput(400, 0);
  inp.TabWidths := nil;
  inp.ActiveIndex := -1;
  g := TyToolWindowHeaderLayout(inp);
  AssertEquals('没有标签', 0, Length(g.Tabs));
  CheckRect('没有溢出', 0, 0, 0, 0, g.Overflow);
  CheckHidden('B7', g, []);
  CheckRect('收起同 B1', 372, 2, 394, 24, g.Collapse);
  CheckRect('最大化同 B1', 346, 2, 368, 24, g.Maximize);
  CheckRect('分隔线同 B1', 337, 0, 346, 26, g.Separator);
end;

procedure TTyToolWindowGeometryTests.TestBottomRowMirrorsUnderRightToLeft;
var
  inp: TTyToolWindowHeaderInput;
  ltr, rtl: TTyToolWindowHeaderGeom;
  a, b: TRectArray;
  i: Integer;
begin
  inp := BottomInput(400, 0);
  ltr := TyToolWindowHeaderLayout(inp);
  inp.RightToLeft := True;
  rtl := TyToolWindowHeaderLayout(inp);
  CheckRect('RTL:收起到行首', 6, 2, 28, 24, rtl.Collapse);
  CheckRect('RTL:第一个标签到行尾', 314, 0, 394, 26, rtl.Tabs[0].ItemRect);
  CheckRect('RTL:操作区', 63, 0, 123, 26, rtl.Actions);
  a := AllRects(ltr);
  b := AllRects(rtl);
  AssertEquals('矩形个数一样', Length(a), Length(b));
  for i := 0 to High(a) do
    if not ((a[i].Left = 0) and (a[i].Right = 0) and (a[i].Top = 0) and (a[i].Bottom = 0)) then
      CheckRect(Format('RTL:第 %d 个矩形是 LTR 的镜像', [i]), 400 - a[i].Right, a[i].Top,
        400 - a[i].Left, a[i].Bottom, b[i]);
end;

procedure TTyToolWindowGeometryTests.TestBottomRowClampsTheButtonsToTheRowHeight;
var
  inp: TTyToolWindowHeaderInput;
  g: TTyToolWindowHeaderGeom;
begin
  inp := BottomInput(300, 0);
  inp.RowHeight := 16;
  g := TyToolWindowHeaderLayout(inp);
  CheckRect('按钮高钳进行高', 272, 0, 294, 16, g.Collapse);
  CheckRect('溢出按钮同样', 86, 0, 108, 16, g.Overflow);
end;

procedure TTyToolWindowGeometryTests.TestBottomRowClampsNegativeInputs;
var
  inp: TTyToolWindowHeaderInput;
  g: TTyToolWindowHeaderGeom;
  r: TRect;
begin
  inp := BottomInput(400, 0);
  inp.TabWidths[1] := -5;
  inp.ButtonSize := -3;
  g := TyToolWindowHeaderLayout(inp);
  AssertEquals('按钮宽按 0', 0, g.Collapse.Right - g.Collapse.Left);
  AssertEquals('三个标签都排上', 3, Length(g.Tabs));
  AssertEquals('负宽的标签按 0', 0, g.Tabs[1].ItemRect.Right - g.Tabs[1].ItemRect.Left);
  AssertEquals('后一个紧接着它', g.Tabs[1].ItemRect.Right, g.Tabs[2].ItemRect.Left);
  for r in AllRects(g) do
  begin
    AssertTrue('矩形不反转(横)', r.Right >= r.Left);
    AssertTrue('矩形不反转(纵)', r.Bottom >= r.Top);
  end;
end;

procedure TTyToolWindowGeometryTests.TestZoneAtInvertsTheBottomLayout;
var
  inp: TTyToolWindowHeaderInput;
begin
  CheckCentresHit('B1', TyToolWindowHeaderLayout(BottomInput(400, 0)));
  CheckCentresHit('B2', TyToolWindowHeaderLayout(BottomInput(300, 0)));
  CheckCentresHit('B3', TyToolWindowHeaderLayout(BottomInput(300, 2)));
  CheckCentresHit('B4', TyToolWindowHeaderLayout(BottomInput(160, 0)));
  inp := BottomInput(400, 0);
  inp.RightToLeft := True;
  CheckCentresHit('B8', TyToolWindowHeaderLayout(inp));
end;

procedure TTyToolWindowGeometryTests.TestZoneAtAnswersNoneOffTheParts;
var
  g: TTyToolWindowHeaderGeom;
  c: TPoint;
  idx: Integer;
begin
  g := TyToolWindowHeaderLayout(BottomInput(400, 0));
  c := g.Actions.CenterPoint;
  AssertEquals('操作区不是标题行的部件', Ord(twzNone), Ord(TyToolWindowZoneAt(g, c.X, c.Y, idx)));
  AssertEquals('none 的序号 -1', -1, idx);
  AssertEquals('最后一个标签之后的空白', Ord(twzNone), Ord(TyToolWindowZoneAt(g, 260, 13, idx)));
  AssertEquals('空白的序号 -1', -1, idx);
end;

procedure TTyToolWindowGeometryTests.TestZoneAtOnASideRowIsAlwaysNone;
var
  inp: TTyToolWindowHeaderInput;
  g: TTyToolWindowHeaderGeom;
  x, idx: Integer;
begin
  inp := Default(TTyToolWindowHeaderInput);
  inp.Mode := twhSide;
  inp.RowWidth := 200;
  inp.RowHeight := 26;
  inp.Pad := 6;
  inp.Gap := 4;
  inp.ActionsWidth := 80;
  g := TyToolWindowHeaderLayout(inp);
  for x := -1 to 201 do
    AssertEquals('侧栏标题行没有可点的部件', Ord(twzNone), Ord(TyToolWindowZoneAt(g, x, 13, idx)));
end;

procedure TTyToolWindowGeometryTests.TestZoneAtNeverHitsAnEmptyPart;
var
  g: TTyToolWindowHeaderGeom;
  x, idx: Integer;
  z: TTyToolWindowZone;
begin
  { B5:当前页的标签宽 0、溢出按钮被钳成零宽 —— 扫整行,哪一点都不许答它们。 }
  g := TyToolWindowHeaderLayout(BottomInput(60, 1));
  for x := 0 to 60 do
  begin
    z := TyToolWindowZoneAt(g, x, 13, idx);
    AssertFalse(Format('x=%d 不许命中宽 0 的标签', [x]), z = twzTab);
    AssertFalse(Format('x=%d 不许命中零宽的溢出按钮', [x]), z = twzOverflow);
  end;
end;

{ --- 跨栏命中(spec §9.4) ------------------------------------------------------------- }

function Slot(AIndex, L, T, R, B: Integer): TTyToolWindowSlot;
begin
  Result.ItemIndex := AIndex;
  Result.ItemRect := Rect(L, T, R, B);
end;

function TTyToolWindowGeometryTests.ProbeS: TTyToolWindowDropProbe;
begin
  Result := Default(TTyToolWindowDropProbe);
  Result.Visible := Rect(0, 0, 200, 400);
  Result.Cells := Rect(0, 0, 36, 400);
  SetLength(Result.Slots, 2);
  Result.Slots[0] := Slot(0, 0, 0, 36, 36);
  Result.Slots[1] := Slot(1, 0, 36, 36, 72);
  Result.Count := 2;
  Result.IsSource := True;
end;

function TTyToolWindowGeometryTests.ProbeT: TTyToolWindowDropProbe;
begin
  Result := Default(TTyToolWindowDropProbe);
  Result.Visible := Rect(600, 0, 800, 400);
  Result.Cells := Rect(764, 0, 800, 400);
  SetLength(Result.Slots, 1);
  Result.Slots[0] := Slot(0, 764, 0, 800, 36);
  Result.Count := 1;
  Result.Allowed := True;
end;

procedure TTyToolWindowGeometryTests.CheckDrop(const AMsg: string;
  const AProbes: array of TTyToolWindowDropProbe; X, Y, AWantProbe, AWantSlot: Integer);
var
  slot, got: Integer;
begin
  got := TyToolWindowDropAt(AProbes, Point(X, Y), slot);
  AssertEquals(AMsg + ':候选', AWantProbe, got);
  if AWantProbe >= 0 then AssertEquals(AMsg + ':槽位', AWantSlot, slot)
  else AssertEquals(AMsg + ':没有目标时槽位 -1', -1, slot);
end;

procedure TTyToolWindowGeometryTests.TestDropAtFindsSlotsOnTheSourceStrip;
begin
  CheckDrop('D1 第一格上半', [ProbeS, ProbeT], 18, 10, 0, 0);
  CheckDrop('D2 第二个图标中点之后', [ProbeS, ProbeT], 18, 60, 0, 2);
  CheckDrop('D3 条尾空白 = 最后一个之后', [ProbeS, ProbeT], 18, 300, 0, 2);
end;

procedure TTyToolWindowGeometryTests.TestDropAtSourceContentIsNoTarget;
var
  n: TTyToolWindowDropProbe;
begin
  CheckDrop('D4 源栏内容区', [ProbeS, ProbeT], 100, 100, -1, -1);
  { 后面还有一个候选盖着这一点(没登记成洞):源栏的内容区先截住,不许落到它上面。 }
  n := ProbeT;
  n.Visible := Rect(40, 100, 200, 200);
  n.Cells := Rect(40, 100, 76, 200);
  n.Slots := nil;
  n.Count := 0;
  CheckDrop('D4b 源栏内容区后面还有候选', [ProbeS, n], 120, 150, -1, -1);
  CheckDrop('D9 编辑区', [ProbeS, ProbeT], 400, 200, -1, -1);
end;

procedure TTyToolWindowGeometryTests.TestDropAtOtherBarStripAndContent;
begin
  CheckDrop('D5 另一侧栏第一格上半', [ProbeS, ProbeT], 780, 10, 1, 0);
  CheckDrop('D6 另一侧栏条尾', [ProbeS, ProbeT], 780, 300, 1, 1);
  CheckDrop('D7 另一侧栏内容区 = 末尾空隙', [ProbeS, ProbeT], 650, 200, 1, 1);
end;

procedure TTyToolWindowGeometryTests.TestDropAtAVetoedBarIsNoTarget;
var
  t: TTyToolWindowDropProbe;
begin
  t := ProbeT;
  t.Allowed := False;
  CheckDrop('D8 被否决:条上', [ProbeS, t], 780, 10, -1, -1);
  CheckDrop('D8 被否决:内容区', [ProbeS, t], 650, 200, -1, -1);
end;

procedure TTyToolWindowGeometryTests.TestDropAtHolesAndNestedBars;
var
  s, t, n: TTyToolWindowDropProbe;
begin
  t := ProbeT;
  SetLength(t.Holes, 1);
  t.Holes[0] := Rect(640, 100, 700, 150);
  CheckDrop('D10 落在嵌套栏里', [ProbeS, t], 660, 120, -1, -1);
  CheckDrop('D10 洞外照常', [ProbeS, t], 660, 200, 1, 1);
  s := ProbeS;
  SetLength(s.Holes, 1);
  s.Holes[0] := Rect(40, 100, 200, 200);
  n := ProbeT;
  n.Visible := Rect(40, 100, 200, 200);
  n.Cells := Rect(40, 100, 76, 200);
  n.Slots := nil;
  n.Count := 0;
  CheckDrop('D15 嵌在源栏里的栏能当目标', [s, ProbeT, n], 120, 150, 2, 0);
end;

procedure TTyToolWindowGeometryTests.TestDropAtMapsToWindowIndexes;
var
  t: TTyToolWindowDropProbe;
begin
  t := ProbeT;
  t.Count := 3;
  t.Slots[0] := Slot(2, 764, 0, 800, 36);
  CheckDrop('D11 条上:窗口序号不是排布序号', [ProbeS, t], 780, 10, 1, 2);
  CheckDrop('D11 内容区:最后一个已排布之后', [ProbeS, t], 650, 200, 1, 3);
  { 后两个被溢出收起、排在条上的是窗口 0:「最后一个已排布之后」是 1,不是窗口数。 }
  t.Slots[0] := Slot(0, 764, 0, 800, 36);
  CheckDrop('D11b 有溢出时内容区不是窗口数', [ProbeS, t], 650, 200, 1, 1);
end;

procedure TTyToolWindowGeometryTests.TestDropAtClippedAndEmptyInputs;
var
  t: TTyToolWindowDropProbe;
  none: array of TTyToolWindowDropProbe;
begin
  t := ProbeT;
  t.Count := 0;
  t.Slots := nil;
  CheckDrop('D12 空栏', [ProbeS, t], 650, 200, 1, 0);
  t := ProbeT;
  t.Visible := Rect(600, 0, 700, 400);
  CheckDrop('D13 祖先裁掉了图标条', [ProbeS, t], 780, 10, -1, -1);
  none := nil;
  CheckDrop('D14 空数组', none, 10, 10, -1, -1);
end;

initialization
  RegisterTest(TTyToolWindowGeometryTests);
end.
