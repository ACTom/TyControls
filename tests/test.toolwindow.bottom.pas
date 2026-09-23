unit test.toolwindow.bottom;
{$mode objfpc}{$H+}

{ 底栏(spec §3.4 / §6.4 / §7):标题行输入的装配、统一行高、标签行绘制、最大化、跨类改 Parent、
  设计期。夹具在 test.toolwindow.bar(TTyToolWindowBarFixture)。 }

interface

uses
  Classes, SysUtils, Types, TypInfo, Controls, Forms, Graphics, Menus, LCLType, LCLProc, LMessages,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.ToolWindows,
  tyControls.ToolWindows.Layout, tyControls.StrConsts,
  tyControls.Icons.Lucide, test.toolwindow.window,
  test.toolwindow.bar;

type
  { 底栏测试共用的夹具。本身没有 published 测试 —— fpcunit 会把基类的 published 方法在每个
    子类里各跑一遍。 }
  TTyToolWindowBottomFixture = class(TTyToolWindowBarFixture)
  protected
    FWins: array of TProbeWindow;
    FDowns, FUps, FWheels: Integer;
    procedure CountDown(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure CountUp(Sender: TObject; Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
    procedure CountWheel(Sender: TObject; Shift: TShiftState; WheelDelta: Integer;
      MousePos: TPoint; var Handled: Boolean);
    { 当前页上第 AIndex 个窗口的标签的中心(当前页客户区坐标)。 }
    function TabCentre(AIndex: Integer): TPoint;
    { 在 AWin 上按 LCL 的顺序按下、Click、松开(真实的 protected 入口)。 }
    procedure ClickAt(AWin: TProbeWindow; const APos: TPoint);
    { 一条宽 600 的底栏,按 ACaptions 建窗口(标题长短不一,地雷 12),AActive 是当前页。
      先设 Placement 再加窗口:运行时有窗口时侧 ↔ 底被忽略。最后请一遍对齐,窗口才有真实边界。 }
    procedure NewBottomBar(const ACaptions: array of string; AActive: Integer);
    { 栏和每个窗口各请一遍对齐引擎(无头不跑,见 headless-tests-never-run-lcl-align)。 }
    procedure Relayout;
    { 当前页此刻的标题行几何(窗口客户区坐标)。 }
    function ActiveGeom: TTyToolWindowHeaderGeom;
    function TabRectOf(const AGeom: TTyToolWindowHeaderGeom; AWindowIndex: Integer): TRect;
    { AWin 的操作区里放一个 AW×AH 的子控件(操作区没有就先建)。 }
    function AddActionsKid(AWin: TTyToolWindow; AW, AH: Integer): TBodyChild;
    { 当前页:对齐计数清零、绘制缓存填上一帧,之后看「有没有被请重排 / 丢缓存」。 }
    procedure ArmActive(AWin: TProbeWindow);
    { 把 AWin 按 AW×AH、APPI 画出来;先铺底漆 Wipe。调用方释放。 }
    function RenderPage(AWin: TProbeWindow; AW, AH, APPI: Integer): TBitmap;
  end;

  { 装配、统一行高、绘制、最大化、跨类改 Parent、设计期。 }
  TTyToolWindowBottomTests = class(TTyToolWindowBottomFixture)
  published
    { Task 3:装配。 }
    procedure TestTheActionsSitInTheBottomRowBeforeTheButtons;
    procedure TestRenamingAnotherWindowWidensItsTab;
    procedure TestTheTabPadTokenReachesEveryTab;
    procedure TestTheButtonSizeTokenMovesTheButtons;
    procedure TestTheTabAreaMinTokenSqueezesTheActions;
    procedure TestAThemeChangeRemeasuresTheTabs;
    procedure TestADirectZOrderChangeReordersTheTabs;
    procedure TestTabsAreMeasuredAtTheWiderOfRestingAndSelected;
    procedure TestTheSeparatorSlotFollowsItsBorderWidth;
    procedure TestZoneAtInBarCoordinatesMapsThroughTheActivePage;
    { Task 4:统一行高(spec §3.4)。 }
    procedure TestEveryPageSharesTheTallestActionsRow;
    procedure TestATallChildOnAHiddenPageRelayoutsTheActivePageAtOnce;
    procedure TestAWindowJoiningCountsTowardsTheSharedHeight;
    procedure TestAConstraintsOnlyChangeReachesTheRow;
    procedure TestAThemeChangeStillRelayoutsABottomPage;
    { 行高没变、几何变了(spec §3.5 / §7.3):栏的样式类换了,当前页的操作区照样重排。
      换主题 token 那一半要真句柄,在 test.toolwindow.focus。 }
    procedure TestABarStyleClassChangeRelayoutsTheActivePage;
    { Task 5:标签行绘制(哨兵底色,地雷 13)。 }
    procedure TestTheUnderlineSitsOnTheActiveTabsBottomOnly;
    procedure TestTheIndicatorSizeTokenSetsTheUnderlineRows;
    procedure TestSelectedInkOnlyOnTheActiveTabRestingInkOnTheOthers;
    procedure TestAHiddenPagePaintsNoTabRow;
    procedure TestTheOverflowButtonPaintsOnlyWhenSomethingIsHidden;
    procedure TestTheSeparatorIsALineCentredInItsSlot;
    procedure TestTheUnderlineFollowsTheMirroredTab;
    procedure TestRenderingAt144ScalesTabsAndButtons;
    procedure TestRenamingAHiddenPageRepaintsTheActivePage;
    procedure TestReorderingRepaintsTheActivePage;
    { Task 7:最大化 / 还原(spec §6.4)。 }
    procedure TestMaximizeFillsTheParentOverItsSiblings;
    procedure TestRestoringGoesBackToTheExpandedHeight;
    procedure TestCollapsingRestoresFirst;
    procedure TestMaximizeIsIgnoredWhereItCannotApply;
    procedure TestMaximizedIsNotPublished;
    procedure TestTheEdgeIsInertWhileMaximized;
    procedure TestMaximizingMidResizeRestoresTheStartSize;
    procedure TestTheMaximizeButtonTogglesOnARealClick;
    procedure TestTheMaximizeGlyphTurnsIntoRestore;
    procedure TestMaximizingRepaintsTheActivePage;
    { Task 10:设计期点标签(spec §3.6 设计期、§7.4 设计期)。 }
    procedure TestADesignTimeTabClickSwitchesOnRelease;
    procedure TestDesignTimeButtonsAndSeparatorAnswerZero;
    procedure TestTheDesignTimeRowsBlankSelectsTheBar;
    procedure TestTheTabRowRegionLeavesOutTheActions;
    procedure TestMaskHitTestFallsBackToSelectable;
    { Task 11:运行时跨类改 Parent 抛 EInvalidOperation(spec §3.2)。 }
    procedure TestASideWindowCannotMoveToABottomBarAtRunTime;
    procedure TestABottomWindowCannotMoveToASideBarAtRunTime;
    procedure TestDesignTimeMovesAcrossBarKinds;
    procedure TestLoadingMovesAcrossBarKinds;
    procedure TestSameKindOrphanAndNilMovesDoNotRaise;
  private
    FDesignWins: array of TProbeWindow;
    { 窗体上一条运行时底栏,带一个窗口。 }
    function NewRuntimeBar(APlacement: TTyToolWindowPlacement; out AWin: TProbeWindow): TBarAccess;
    { AWin.Parent := ANew,答「抛了 EInvalidOperation」。 }
    function MoveRaises(AWin: TTyToolWindow; ANew: TWinControl): Boolean;
    { 设计期的底栏(宽 600),三个窗口,当前页是第二个;窗口摆到内容区。 }
    function NewDesignBottomBar(AWidth: Integer = 600): TBarAccess;
    { 设计期底栏上窗口 AIndex 的标签中心,栏坐标。 }
    function DesignTabCentre(ABar: TBarAccess; AIndex: Integer): TPoint;
    { 一个 600×400 的宿主:上面一个 30 高的 alTop 兄弟、一个 alClient 编辑区;栏挪进去。 }
    procedure HostTheBar;
  end;

  { 标签行的输入:转发、点击、溢出、提示、右键、调顺序(spec §3.6 / §7.4 / §9)。 }
  TTyToolWindowBottomInputTests = class(TTyToolWindowBottomFixture)
  published
    { Task 6:转发与标签点击。 }
    procedure TestATabSwitchesOnReleaseNotOnPress;
    procedure TestAReleaseOnAnotherTabIsNotAClick;
    procedure TestClickingTheActiveTabDoesNothing;
    procedure TestADoubleClickPressNeverCounts;
    procedure TestTheRowSwallowsTheUsersMouseEvents;
    procedure TestAPressInTheBodyKeepsItsMouseUpInTheRow;
    procedure TestTheWheelIsSwallowedInTheRow;
    { 「标签行不起 LCL 拖动」要真实的按下消息(抓捕获要句柄),在 test.toolwindow.focus。 }
    procedure TestALateLeaveFromTheOldPageKeepsTheNewHover;
    procedure TestCancelModeOnTheActivePageCancelsThePress;
    procedure TestAWindowFreedWhileArmedIsNotAClick;
    procedure TestADisabledBarDoesNotSwitch;
    procedure TestHoverFollowsThePointerAndRepaintsTheActivePage;
    procedure TestWindowAtPosFindsTabsInBarCoordinates;
    procedure TestAFinishedClickRepaintsThePressedState;
    procedure TestHoverIsRecheckedAfterASwitch;
    { Task 8:溢出菜单、收起按钮、提示、右键。 }
    procedure TestTheOverflowMenuListsTheHiddenWindows;
    procedure TestPickingAnOverflowItemActivatesIt;
    procedure TestADoubleClickPressOnOverflowOrHideDoesNothing;
    procedure TestTheHideButtonCollapsesOnRelease;
    procedure TestATabHintIsStripHintOrCaptionNeverHint;
    procedure TestTheMaximizeHintFollowsTheState;
    procedure TestTheRowsBlankShowsNoHint;
    procedure TestARightClickOnATabGoesToTheBarInBarCoordinates;
    procedure TestARightClickOnTheRowsBlankIsSwallowed;
    { Task 9:标签拖动调顺序(spec §9.1 / §9.2 / §9.4 / §9.8)。 }
    procedure TestDraggingOutOfTheRowShowsNoDropAndCancels;
    procedure TestDraggingToTheEndReordersOnRelease;
    procedure TestItsOwnGapsAreANoOpWithoutALine;
    procedure TestAForcedActiveTabMapsGapsToWindowIndexes;
    procedure TestTheDropSlotReadsTheMirroredRowInReadingOrder;
    procedure TestTheInsertLinePaintsInTheActivePage;
    procedure TestEscCancelsATabDrag;
    procedure TestCancelModeOnTheActivePageCancelsATabDrag;
    procedure TestADropSlotChangeRepaintsTheActivePage;
    procedure TestFreeingTheActivePageMidDragEndsTheGesture;
  private
    FBarPopups, FWinPopups: Integer;
    FBarPopupPos: TPoint;
    procedure CountBarPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    procedure CountWinPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    { 让 AWin 回答 (X, Y) 上的 CM_HINTSHOW(LCL 自己发的那一条)。 }
    function AskHint(AWin: TProbeWindow; const APos: TPoint; out AInfo: THintInfo): PtrInt;
    { 栏窄到放不下全部标签(有溢出按钮)。 }
    procedure Narrow;
  end;

implementation

const
  { 标签行钉成品红底(窗口本身也是)、静止墨蓝、选中墨黄、下划线黑、分隔线青
    (不用绿:绿是夹具的底漆 Wipe)。 }
  BottomTheme = ':root { --toolwindow-bg: #FF00FF; --toolwindow-header-bg: #FF00FF;' +
    ' --toolwindow-tab-ink: #0000FF; --toolwindow-tab-ink-selected: #FFFF00;' +
    ' --toolwindow-indicator-color: #000000; }' +
    ' TyToolWindowSeparator { border-color: #00FFFF; border-width: 1px; }';
  LineInk = TColor($FFFF00);

{ ARect(位图坐标,钳进位图)里有多少像素:AExact 时恰好是 AInk;否则落在「AGround 上盖一层
  半透明 AInk」那条混合线上(含实心,不含纯底色,算法同 CountInk)。 }
function CountIn(ABmp: TBitmap; const ARect: TRect; AGround, AInk: TColor;
  AExact: Boolean): Integer;
var
  re: TBGRABitmap;
  g, k, px: TBGRAPixel;
  x, y, c, best: Integer;
  gv, kv, pv: array[0..2] of Integer;
  a: Double;
  ok: Boolean;
  r: TRect;
begin
  Result := 0;
  r := ARect;
  if r.Left < 0 then r.Left := 0;
  if r.Top < 0 then r.Top := 0;
  if r.Right > ABmp.Width then r.Right := ABmp.Width;
  if r.Bottom > ABmp.Height then r.Bottom := ABmp.Height;
  g := ColorToBGRA(ColorToRGB(AGround));
  k := ColorToBGRA(ColorToRGB(AInk));
  gv[0] := g.red; gv[1] := g.green; gv[2] := g.blue;
  kv[0] := k.red; kv[1] := k.green; kv[2] := k.blue;
  best := 0;
  for c := 1 to 2 do
    if Abs(kv[c] - gv[c]) > Abs(kv[best] - gv[best]) then best := c;
  re := TBGRABitmap.Create(ABmp);
  try
    for y := r.Top to r.Bottom - 1 do
      for x := r.Left to r.Right - 1 do
      begin
        px := re.GetPixel(x, y);
        pv[0] := px.red; pv[1] := px.green; pv[2] := px.blue;
        if AExact then
        begin
          if (pv[0] = kv[0]) and (pv[1] = kv[1]) and (pv[2] = kv[2]) then Inc(Result);
          Continue;
        end;
        if kv[best] = gv[best] then Continue;
        a := (pv[best] - gv[best]) / (kv[best] - gv[best]);
        if (a <= 0.01) or (a > 1.02) then Continue;
        ok := True;
        for c := 0 to 2 do
          if Abs(gv[c] + a * (kv[c] - gv[c]) - pv[c]) > 3 then ok := False;
        if ok then Inc(Result);
      end;
  finally
    re.Free;
  end;
end;

function ExactIn(ABmp: TBitmap; const ARect: TRect; AColor: TColor): Integer;
begin
  Result := CountIn(ABmp, ARect, AColor, AColor, True);
end;

function InkIn(ABmp: TBitmap; const ARect: TRect; AInk: TColor): Integer;
begin
  Result := CountIn(ABmp, ARect, Ground, AInk, False);
end;

function Area(const ARect: TRect): Integer;
begin
  Result := (ARect.Right - ARect.Left) * (ARect.Bottom - ARect.Top);
end;

procedure TTyToolWindowBottomFixture.NewBottomBar(const ACaptions: array of string;
  AActive: Integer);
var
  i: Integer;
begin
  FBar.Placement := twpBottom;
  FBar.Width := 600;
  FWins := nil;
  SetLength(FWins, Length(ACaptions));
  for i := 0 to High(ACaptions) do
  begin
    FWins[i] := NewWindow;
    FWins[i].Caption := ACaptions[i];
  end;
  if AActive >= 0 then FBar.ActiveWindow := FWins[AActive];
  Relayout;
end;

procedure TTyToolWindowBottomFixture.Relayout;
var
  r: TRect;
  i: Integer;
begin
  FBar.CallAlignControls;
  { 藏着的页对齐引擎不摆;真机上切页时会摆到内容区,这里直接给它们内容区,切页之后
    立刻问几何(悬停重查、命中)的测试才有真实的边界。 }
  r := FBar.ClientRect;
  FBar.CallAdjustClientRect(r);
  for i := 0 to High(FWins) do
    if (FWins[i] <> nil) and (FWins[i].Parent = FBar) then
    begin
      FWins[i].BoundsRect := r;
      FWins[i].CallAlignControls;
    end;
end;

procedure TTyToolWindowBottomFixture.CountDown(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  Inc(FDowns);
end;

procedure TTyToolWindowBottomFixture.CountUp(Sender: TObject; Button: TMouseButton;
  Shift: TShiftState; X, Y: Integer);
begin
  Inc(FUps);
end;

procedure TTyToolWindowBottomFixture.CountWheel(Sender: TObject; Shift: TShiftState;
  WheelDelta: Integer; MousePos: TPoint; var Handled: Boolean);
begin
  Inc(FWheels);
end;

function TTyToolWindowBottomFixture.TabCentre(AIndex: Integer): TPoint;
begin
  Result := TabRectOf(ActiveGeom, AIndex).CenterPoint;
end;

procedure TTyToolWindowBottomFixture.ClickAt(AWin: TProbeWindow; const APos: TPoint);
begin
  AWin.CallMouseDown(APos.X, APos.Y);
  { LCL 在 MouseUp 之前调 Click(control.inc:2827-2846)。 }
  AWin.CallClick;
  AWin.CallMouseUp(APos.X, APos.Y);
end;

function TTyToolWindowBottomFixture.ActiveGeom: TTyToolWindowHeaderGeom;
var
  w: TTyToolWindow;
begin
  w := FBar.ActiveWindow;
  AssertNotNull('前提:有当前页', w);
  Result := w.HeaderGeomAt(Rect(0, 0, w.ClientWidth, w.ClientHeight), w.Font.PixelsPerInch);
end;

function TTyToolWindowBottomFixture.TabRectOf(const AGeom: TTyToolWindowHeaderGeom;
  AWindowIndex: Integer): TRect;
var
  i: Integer;
begin
  for i := 0 to High(AGeom.Tabs) do
    if AGeom.Tabs[i].ItemIndex = AWindowIndex then Exit(AGeom.Tabs[i].ItemRect);
  Fail(Format('窗口 %d 的标签没排上', [AWindowIndex]));
  Result := Rect(0, 0, 0, 0);
end;

function TTyToolWindowBottomFixture.AddActionsKid(AWin: TTyToolWindow; AW, AH: Integer): TBodyChild;
var
  act: TTyToolWindowActions;
begin
  act := AWin.EnsureActions;
  Result := TBodyChild.Create(FForm);
  Result.SetBounds(0, 0, AW, AH);
  Result.Parent := act;
end;

procedure TTyToolWindowBottomFixture.ArmActive(AWin: TProbeWindow);
begin
  AWin.AlignCount := 0;
  AWin.PrimeCache(AWin.ClientWidth, AWin.ClientHeight);
  AssertFalse('前提:缓存填上了', AWin.CacheWouldRender(AWin.ClientWidth, AWin.ClientHeight));
end;

function TTyToolWindowBottomFixture.RenderPage(AWin: TProbeWindow; AW, AH, APPI: Integer): TBitmap;
begin
  Result := TBitmap.Create;
  Result.PixelFormat := pf32bit;
  Result.SetSize(AW, AH);
  Result.Canvas.Brush.Color := Wipe;
  Result.Canvas.FillRect(0, 0, AW, AH);
  AWin.CallRenderTo(Result.Canvas, Rect(0, 0, AW, AH), APPI);
end;

{ --- Task 3 --------------------------------------------------------------------- }

procedure TTyToolWindowBottomTests.TestTheActionsSitInTheBottomRowBeforeTheButtons;
var
  act: TTyToolWindowActions;
  kid: TBodyChild;
  g: TTyToolWindowHeaderGeom;
  w: TProbeWindow;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  act := w.EnsureActions;
  kid := TBodyChild.Create(FForm);
  kid.SetBounds(0, 0, 40, 20);
  kid.Parent := act;
  Relayout;
  g := ActiveGeom;
  AssertEquals('前提:窗口有栏那么宽', 600, w.ClientWidth);
  AssertTrue('操作区摆在标题行几何给的位置', EqualRect(g.Actions, act.BoundsRect));
  { 尾端往前:pad 6、收起 22、gap 4、最大化 22、分隔线槽 2×4+1 —— 操作区右沿就在分隔线左沿,
    不是侧栏那样贴到行尾。 }
  AssertEquals('操作区右沿 = 行宽 − pad − 2 × 按钮 − gap − 分隔线槽', 600 - 6 - 22 - 4 - 22 - 9,
    act.Left + act.Width);
  AssertEquals('操作区紧挨分隔线', g.Separator.Left, act.Left + act.Width);
  AssertTrue('标签区在操作区左边', g.TabArea.Right <= act.Left);
end;

procedure TTyToolWindowBottomTests.TestRenamingAnotherWindowWidensItsTab;
var
  before, after: TTyToolWindowHeaderGeom;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  before := ActiveGeom;
  FWins[0].Caption := 'Problems and warnings';
  after := ActiveGeom;
  AssertTrue('改了标题的那个标签变宽',
    TabRectOf(after, 0).Width > TabRectOf(before, 0).Width);
  AssertEquals('它后面的标签跟着右移',
    TabRectOf(before, 1).Left + TabRectOf(after, 0).Width - TabRectOf(before, 0).Width,
    TabRectOf(after, 1).Left);
end;

procedure TTyToolWindowBottomTests.TestTheTabPadTokenReachesEveryTab;
var
  before, after: TTyToolWindowHeaderGeom;
  i: Integer;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  before := ActiveGeom;
  FCtl.StyleOverride := ':root { --toolwindow-tab-pad: 14px; }';
  after := ActiveGeom;
  for i := 0 to 2 do
    AssertEquals(Format('标签 %d 两侧各多 4', [i]), TabRectOf(before, i).Width + 8,
      TabRectOf(after, i).Width);
end;

procedure TTyToolWindowBottomTests.TestTheButtonSizeTokenMovesTheButtons;
var
  before, after: TTyToolWindowHeaderGeom;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  before := ActiveGeom;
  FCtl.StyleOverride := ':root { --toolwindow-button-size: 30px; }';
  after := ActiveGeom;
  AssertEquals('收起按钮宽 30', 30, after.Collapse.Width);
  AssertEquals('收起左沿左移 8', before.Collapse.Left - 8, after.Collapse.Left);
  AssertEquals('最大化再左移 8', before.Maximize.Left - 16, after.Maximize.Left);
end;

procedure TTyToolWindowBottomTests.TestTheTabAreaMinTokenSqueezesTheActions;
var
  act: TTyToolWindowActions;
  kid: TBodyChild;
  before, after: TTyToolWindowHeaderGeom;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  act := FWins[1].EnsureActions;
  kid := TBodyChild.Create(FForm);
  kid.SetBounds(0, 0, 200, 20);
  kid.Parent := act;
  before := ActiveGeom;
  AssertEquals('前提:操作区保宽(200 + 2 × pad)', 212, before.Actions.Width);
  FCtl.StyleOverride := ':root { --toolwindow-tab-area-min: 400px; }';
  after := ActiveGeom;
  AssertEquals('标签区停在新的下限', 400, after.TabArea.Width);
  AssertEquals('操作区让出来的就是那一截', 600 - 6 - 22 - 4 - 22 - 9 - 6 - 400,
    after.Actions.Width);
end;

procedure TTyToolWindowBottomTests.TestAThemeChangeRemeasuresTheTabs;
var
  before, after: TTyToolWindowHeaderGeom;
  i: Integer;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  before := ActiveGeom;
  { 同一个 model、同一套窗口和标题:只有主题版本变了。 }
  FCtl.StyleOverride := 'TyToolWindowTab { font-size: 24px; }';
  after := ActiveGeom;
  for i := 0 to 2 do
    AssertTrue(Format('标签 %d 按新字号重量', [i]),
      TabRectOf(after, i).Width > TabRectOf(before, i).Width);
end;

procedure TTyToolWindowBottomTests.TestADirectZOrderChangeReordersTheTabs;
var
  before, after: TTyToolWindowHeaderGeom;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  before := ActiveGeom;
  { 设计器「移到最后」直接调它,不经 ReorderWindow、不通知谁。 }
  FBar.SetControlIndex(FWins[0], FBar.ControlCount - 1);
  after := ActiveGeom;
  AssertSame('前提:顺序真的变了', FWins[1], FBar.Windows[0]);
  AssertEquals('第一格现在是 Output 的宽', TabRectOf(before, 1).Width, TabRectOf(after, 0).Width);
  AssertEquals('最后一格现在是 Problems 的宽', TabRectOf(before, 0).Width,
    TabRectOf(after, 2).Width);
end;

procedure TTyToolWindowBottomTests.TestTabsAreMeasuredAtTheWiderOfRestingAndSelected;
var
  plain, bold, switched: TTyToolWindowHeaderGeom;
  i: Integer;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  plain := ActiveGeom;
  FCtl.StyleOverride := 'TyToolWindowTab:selected { font-weight: 700; }';
  bold := ActiveGeom;
  for i := 0 to 2 do
    AssertTrue(Format('标签 %d 按加粗的选中态量(否则当前页的标题被截)', [i]),
      TabRectOf(bold, i).Width > TabRectOf(plain, i).Width);
  FBar.ActiveWindow := FWins[2];
  Relayout;
  switched := ActiveGeom;
  for i := 0 to 2 do
    AssertEquals(Format('切页之后标签 %d 宽不变(整行不跳)', [i]), TabRectOf(bold, i).Width,
      TabRectOf(switched, i).Width);
end;

procedure TTyToolWindowBottomTests.TestTheSeparatorSlotFollowsItsBorderWidth;
var
  g: TTyToolWindowHeaderGeom;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  g := ActiveGeom;
  AssertEquals('基础主题:2 × gap + 1', 2 * 4 + 1, g.Separator.Width);
  { 覆写层里给这个键写基础规则,基础层的整条规则就被压掉 —— 线色要一起写。 }
  FCtl.StyleOverride := 'TyToolWindowSeparator { border-color: #000000; border-width: 3px; }';
  g := ActiveGeom;
  AssertEquals('线宽 3:2 × gap + 3', 2 * 4 + 3, g.Separator.Width);
  FCtl.StyleOverride := 'TyToolWindowSeparator { border-color: #000000; border-width: 0; }';
  g := ActiveGeom;
  AssertEquals('没有可见的线:只剩 2 × gap', 2 * 4, g.Separator.Width);
end;

procedure TTyToolWindowBottomTests.TestZoneAtInBarCoordinatesMapsThroughTheActivePage;
var
  w: TProbeWindow;
  g: TTyToolWindowHeaderGeom;
  tab, r: TRect;
  idx: Integer;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  AssertTrue('前提:当前页不在栏的原点(上面有边缘区)', w.Top > 0);
  g := ActiveGeom;
  tab := TabRectOf(g, 2);
  { 标签底部那一行:只在窗口坐标里落在标签上,栏坐标原样拿去算就落到行外。 }
  AssertEquals('栏坐标命中标签', Ord(twzTab),
    Ord(FBar.HeaderZoneAt(nil, tab.Left + 3 + w.Left, tab.Bottom - 1 + w.Top, idx, r)));
  AssertEquals('答窗口序号', 2, idx);
  AssertTrue('矩形回到栏坐标', EqualRect(r, Rect(tab.Left + w.Left, tab.Top + w.Top,
    tab.Right + w.Left, tab.Bottom + w.Top)));
  AssertEquals('窗口坐标照样命中', Ord(twzTab),
    Ord(FBar.HeaderZoneAt(w, tab.Left + 3, tab.Bottom - 1, idx, r)));
  AssertTrue('窗口坐标的矩形不偏移', EqualRect(r, tab));
end;

{ --- Task 4 --------------------------------------------------------------------- }

procedure TTyToolWindowBottomTests.TestEveryPageSharesTheTallestActionsRow;
var
  tall: Integer;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  AddActionsKid(FWins[0], 30, 20);
  AddActionsKid(FWins[1], 30, 40);
  tall := FWins[1].Actions.PreferredSizeAt(96).cy;
  AssertTrue('前提:高的那个操作区比 token 高', tall > TyToolWindowHeaderHeightDef);
  AssertTrue('前提:两个操作区不一样高', FWins[0].Actions.PreferredSizeAt(96).cy < tall);
  AssertEquals('当前页按最高的那个', tall, FWins[1].HeaderHeightPx);
  AssertEquals('矮的那一页也按最高的那个', tall, FWins[0].HeaderHeightPx);
  AssertEquals('没有操作区的那一页也一样', tall, FWins[2].HeaderHeightPx);
  FBar.ActiveWindow := FWins[0];
  Relayout;
  AssertEquals('切页之后标签行不跳', tall, FWins[0].HeaderRowRect.Height);
  FBar.ActiveWindow := FWins[1];
  Relayout;
  AssertEquals('切回来还是一样', tall, FWins[1].HeaderRowRect.Height);
end;

procedure TTyToolWindowBottomTests.TestATallChildOnAHiddenPageRelayoutsTheActivePageAtOnce;
var
  w: TProbeWindow;
  kid: TBodyChild;
  tall: Integer;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  FWins[0].EnsureActions;
  ArmActive(w);
  kid := AddActionsKid(FWins[0], 30, 60);
  AssertSame('没有切页', w, FBar.ActiveWindow);
  tall := FWins[0].Actions.PreferredSizeAt(96).cy;
  AssertEquals('当前页的标签行立刻变高', tall, w.HeaderRowRect.Height);
  AssertEquals('正文顶跟着下移', tall, w.BodyRect.Top);
  { 行高是现算的,上面两条不靠通知也绿;差别在当前页有没有被请重排、有没有丢缓存。 }
  AssertTrue('当前页被请了重排', w.AlignCount > 0);
  AssertTrue('当前页丢了缓存', w.CacheWouldRender(w.ClientWidth, w.ClientHeight));
  ArmActive(w);
  kid.Visible := False;
  AssertEquals('藏掉它:立刻变回 token 高', TyToolWindowHeaderHeightDef, w.HeaderRowRect.Height);
  AssertTrue('又被请了重排', w.AlignCount > 0);
  AssertTrue('又丢了缓存', w.CacheWouldRender(w.ClientWidth, w.ClientHeight));
end;

procedure TTyToolWindowBottomTests.TestAWindowJoiningCountsTowardsTheSharedHeight;
var
  a, b: TProbeWindow;
  kid: TBodyChild;
begin
  NewBottomBar(['Problems', 'Output'], 0);
  a := FWins[0];
  { 先经操作区那条路让栏记下「操作区那一项 = 0」:放一个子控件再藏掉。不然栏记着的还是
    出生时的「没用过」,之后任何一个值都算「变了」,注册时重不重算都看不出来。 }
  AddActionsKid(a, 30, 20).Visible := False;
  { 操作区在进栏之前就长高了:那时它没有栏可通知,只能靠注册时重算。 }
  b := TProbeWindow.Create(FForm);
  b.Caption := 'Terminal';
  { 钉成栏的 PPI:无头默认不是 96,进栏时字体跟着父控件换 PPI,操作区的首选尺寸跟着变、
    自己就通知了栏 —— 注册时有没有重算就看不出来了。 }
  b.Font.PixelsPerInch := 96;
  kid := AddActionsKid(b, 30, 60);
  b.Parent := FBar;
  FBar.ActiveWindow := a;
  Relayout;
  AssertEquals('前提:共用行高算上了新来的', b.Actions.PreferredSizeAt(96).cy, a.HeaderHeightPx);
  ArmActive(a);
  { 注册时没重算的话,栏记着的还是它来之前的高,这一下「没变」就不重排当前页。 }
  kid.Visible := False;
  AssertEquals('藏掉它:当前页变回 token 高', TyToolWindowHeaderHeightDef, a.HeaderHeightPx);
  AssertTrue('当前页被请了重排', a.AlignCount > 0);
end;

procedure TTyToolWindowBottomTests.TestAConstraintsOnlyChangeReachesTheRow;
var
  w: TProbeWindow;
  act: TTyToolWindowActions;
  kid: TBodyChild;
  pw, ph: Integer;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  kid := AddActionsKid(FWins[0], 30, 20);
  act := FWins[0].Actions;
  { LCL 的首选尺寸缓存先填上一次:只改 Constraints 时 LCL 不作废它。 }
  act.GetPreferredSize(pw, ph, True);
  AssertEquals('前提:LCL 量到的是 20 + 2 × pad', 32, ph);
  ArmActive(w);
  kid.Constraints.MinHeight := 50;
  AssertEquals('当前页的行高跟上下限', 62, w.HeaderHeightPx);
  AssertTrue('当前页被请了重排', w.AlignCount > 0);
  act.GetPreferredSize(pw, ph, True);
  AssertEquals('LCL 的 GetPreferredSize 也不端旧值', 62, ph);
end;

procedure TTyToolWindowBottomTests.TestAThemeChangeStillRelayoutsABottomPage;
var
  w: TProbeWindow;
  before, after, i: Integer;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  { 控制器按注册的倒序广播 Invalidate。夹具里栏先注册、窗口后注册,窗口总是先收到 ——
    栏替窗口读缓存的错在那个顺序下看不出来。把栏挪到窗口后面注册,它就先收到。真实窗体里
    谁先谁后看注册顺序,不能假定窗口总在前面。 }
  FBar.Controller := nil;
  for i := 0 to High(FWins) do
    FWins[i].Controller := FCtl;
  FBar.Controller := FCtl;
  before := w.HeaderHeightPx;
  w.AlignCount := 0;
  FCtl.StyleOverride := ':root { --toolwindow-header-height: 48px; }';
  after := w.HeaderHeightPx;
  AssertTrue('换主题后标签行变高', after > before);
  { 换主题只广播裸 Invalidate;窗口在自己的 Invalidate 里看 token 缓存察觉。栏替它先读了
    那个缓存,它就再也看不出来(谁先读就是谁的)。 }
  AssertTrue('底栏窗口照样被请重排', w.AlignCount > 0);
end;

procedure TTyToolWindowBottomTests.TestABarStyleClassChangeRelayoutsTheActivePage;
var
  w: TProbeWindow;
  act: TTyToolWindowActions;
  before: TRect;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  FCtl.StyleOverride := 'TyToolWindowSeparator.wide { border-color: #000000; border-width: 5px; }';
  w := FWins[1];
  AddActionsKid(w, 40, 20);
  act := w.Actions;
  Relayout;
  before := act.BoundsRect;
  AssertTrue('前提:操作区摆在几何给的位置', EqualRect(ActiveGeom.Actions, before));
  ArmActive(w);
  { 只换栏的样式类:主题版本号不动,行高不动,只带来栏自己一次裸 Invalidate。 }
  FBar.StyleClass := 'wide';
  AssertTrue('当前页被请了重排', w.AlignCount > 0);
  AssertTrue('当前页丢了缓存', w.CacheWouldRender(w.ClientWidth, w.ClientHeight));
  w.CallAlignControls;
  AssertEquals('分隔线粗 5:操作区左移 4', before.Left - 4, act.Left);
  AssertTrue('摆在新几何给的位置', EqualRect(ActiveGeom.Actions, act.BoundsRect));
end;

{ --- Task 5 --------------------------------------------------------------------- }

procedure TTyToolWindowBottomTests.TestTheUnderlineSitsOnTheActiveTabsBottomOnly;
var
  w: TProbeWindow;
  g: TTyToolWindowHeaderGeom;
  bmp: TBitmap;
  r: TRect;
  i: Integer;
begin
  { 三个标题长短不一,当前页是第二个(地雷 12)。 }
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  FCtl.StyleOverride := BottomTheme;
  w := FWins[1];
  g := ActiveGeom;
  bmp := RenderPage(w, w.ClientWidth, w.ClientHeight, 96);
  try
    AssertEquals('整块都画到', 0, CountExact(bmp, Wipe));
    for i := 0 to 2 do
    begin
      r := TabRectOf(g, i);
      if i = 1 then
      begin
        { 下划线横跨文字框(标签左右各内缩 tab-pad 10)、贴底边、粗 2。 }
        AssertEquals('当前页:下划线正好是文字框宽 × 2 行', (r.Width - 20) * 2,
          ExactIn(bmp, r, clBlack));
        AssertEquals('全在底边那两行', (r.Width - 20) * 2,
          ExactIn(bmp, Rect(r.Left, r.Bottom - 2, r.Right, r.Bottom), clBlack));
      end
      else
        AssertEquals(Format('标签 %d 不是当前页:没有下划线', [i]), 0, ExactIn(bmp, r, clBlack));
    end;
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowBottomTests.TestTheIndicatorSizeTokenSetsTheUnderlineRows;
var
  w: TProbeWindow;
  bmp: TBitmap;
  r: TRect;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  FCtl.StyleOverride := BottomTheme + ' :root { --toolwindow-indicator-size: 4px; }';
  w := FWins[1];
  r := TabRectOf(ActiveGeom, 1);
  bmp := RenderPage(w, w.ClientWidth, w.ClientHeight, 96);
  try
    AssertEquals('粗 4:底边 4 行', (r.Width - 20) * 4,
      ExactIn(bmp, Rect(r.Left, r.Bottom - 4, r.Right, r.Bottom), clBlack));
    AssertEquals('再往上一行没有', 0,
      ExactIn(bmp, Rect(r.Left, r.Top, r.Right, r.Bottom - 4), clBlack));
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowBottomTests.TestSelectedInkOnlyOnTheActiveTabRestingInkOnTheOthers;
var
  w: TProbeWindow;
  g: TTyToolWindowHeaderGeom;
  bmp: TBitmap;
  r: TRect;
  i: Integer;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  FCtl.StyleOverride := BottomTheme;
  w := FWins[1];
  g := ActiveGeom;
  bmp := RenderPage(w, w.ClientWidth, w.ClientHeight, 96);
  try
    for i := 0 to 2 do
    begin
      r := TabRectOf(g, i);
      if i = 1 then
      begin
        AssertTrue('当前页:选中墨(黄)', InkIn(bmp, r, SelInk) > 0);
        AssertEquals('当前页:没有静止墨(蓝)', 0, InkIn(bmp, r, RestInk));
      end
      else
      begin
        AssertTrue(Format('标签 %d:静止墨(蓝)', [i]), InkIn(bmp, r, RestInk) > 0);
        AssertEquals(Format('标签 %d:没有选中墨(黄)', [i]), 0, InkIn(bmp, r, SelInk));
      end;
    end;
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowBottomTests.TestAHiddenPagePaintsNoTabRow;
var
  bmp: TBitmap;
  row: TRect;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  FCtl.StyleOverride := BottomTheme;
  bmp := RenderPage(FWins[0], 600, 240, 96);
  try
    row := Rect(0, 0, 600, TyToolWindowHeaderHeightDef);
    AssertEquals('非当前页:标题行里没有静止墨', 0, InkIn(bmp, row, RestInk));
    AssertEquals('非当前页:标题行里没有选中墨', 0, InkIn(bmp, row, SelInk));
    AssertEquals('非当前页:没有下划线', 0, ExactIn(bmp, row, clBlack));
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowBottomTests.TestTheOverflowButtonPaintsOnlyWhenSomethingIsHidden;
var
  w: TProbeWindow;
  g: TTyToolWindowHeaderGeom;
  bmp: TBitmap;
  r: TRect;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  FCtl.StyleOverride := BottomTheme;
  w := FWins[1];
  g := ActiveGeom;
  AssertTrue('前提:全放得下,没有溢出按钮', IsRectEmpty(g.Overflow));
  { 溢出按钮要是出现,就在最后一个标签后面那一格。 }
  r := Rect(g.Tabs[High(g.Tabs)].ItemRect.Right, 0, g.Tabs[High(g.Tabs)].ItemRect.Right + 22, 26);
  bmp := RenderPage(w, w.ClientWidth, w.ClientHeight, 96);
  try
    AssertEquals('全放得下:那一格是底色', Area(r), ExactIn(bmp, r, Ground));
  finally
    bmp.Free;
  end;
  FBar.Width := 220;
  Relayout;
  g := ActiveGeom;
  AssertFalse('前提:窄下来有东西收起', IsRectEmpty(g.Overflow));
  bmp := RenderPage(w, w.ClientWidth, w.ClientHeight, 96);
  try
    AssertTrue('溢出按钮里有字形(标签行墨色)', InkIn(bmp, g.Overflow, RestInk) > 0);
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowBottomTests.TestTheSeparatorIsALineCentredInItsSlot;
var
  w: TProbeWindow;
  g: TTyToolWindowHeaderGeom;
  bmp: TBitmap;
  r: TRect;
  mid: Integer;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  FCtl.StyleOverride := BottomTheme;
  w := FWins[1];
  g := ActiveGeom;
  r := g.Separator;
  AssertEquals('前提:槽宽 2 × gap + 1', 9, r.Width);
  mid := r.Left + 4;
  bmp := RenderPage(w, w.ClientWidth, w.ClientHeight, 96);
  try
    AssertEquals('中间那一列在按钮带里是线色', g.Maximize.Height,
      ExactIn(bmp, Rect(mid, g.Maximize.Top, mid + 1, g.Maximize.Bottom), LineInk));
    AssertEquals('左边的 gap 是底色', 4 * g.Maximize.Height,
      ExactIn(bmp, Rect(r.Left, g.Maximize.Top, mid, g.Maximize.Bottom), Ground));
    AssertEquals('右边的 gap 是底色', 4 * g.Maximize.Height,
      ExactIn(bmp, Rect(mid + 1, g.Maximize.Top, r.Right, g.Maximize.Bottom), Ground));
    AssertEquals('线只有一条', g.Maximize.Height, ExactIn(bmp, r, LineInk));
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowBottomTests.TestTheUnderlineFollowsTheMirroredTab;
var
  w: TProbeWindow;
  ltr, rtl: TTyToolWindowHeaderGeom;
  bmp: TBitmap;
  r: TRect;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  FCtl.StyleOverride := BottomTheme;
  w := FWins[1];
  ltr := ActiveGeom;
  FBar.BiDiMode := bdRightToLeft;
  AssertTrue('前提:窗口跟着栏从右往左读', w.IsRightToLeft);
  rtl := ActiveGeom;
  r := TabRectOf(rtl, 1);
  AssertFalse('前提:镜像前后当前页的标签不重叠',
    IntersectRect(r, r, TabRectOf(ltr, 1)));
  r := TabRectOf(rtl, 1);
  bmp := RenderPage(w, w.ClientWidth, w.ClientHeight, 96);
  try
    AssertEquals('下划线落在镜像后的当前页标签里', (r.Width - 20) * 2, ExactIn(bmp, r, clBlack));
    AssertEquals('没有落在镜像前的位置', 0, ExactIn(bmp, TabRectOf(ltr, 1), clBlack));
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowBottomTests.TestRenderingAt144ScalesTabsAndButtons;
var
  w: TProbeWindow;
  g96, g144: TTyToolWindowHeaderGeom;
  bmp: TBitmap;
  r: TRect;
  i: Integer;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  FCtl.StyleOverride := BottomTheme;
  w := FWins[1];
  g96 := ActiveGeom;
  g144 := w.HeaderGeomAt(Rect(0, 0, 900, 360), 144);
  AssertEquals('按钮按 144 缩放', 33, g144.Collapse.Width);
  { 字的宽不是严格线性的(widgetset 初始化过之后按真实字体度量,hinting 让 144 下的字宽
    跟 1.5 倍差几个像素):只要求落在 1.25 ~ 1.75 倍之间 —— 按字体 PPI 量的话是 1 倍。 }
  for i := 0 to 2 do
    AssertTrue(Format('标签 %d 按 144 量(约 1.5 倍:96 下 %d,144 下 %d)',
      [i, TabRectOf(g96, i).Width, TabRectOf(g144, i).Width]),
      (TabRectOf(g144, i).Width * 4 >= TabRectOf(g96, i).Width * 5)
      and (TabRectOf(g144, i).Width * 4 <= TabRectOf(g96, i).Width * 7));
  r := TabRectOf(g144, 1);
  bmp := RenderPage(w, 900, 360, 144);
  try
    { 画的和排的是同一套尺度:下划线横跨 144 下的文字框(tab-pad 15)、粗 3。 }
    AssertEquals('下划线按 144 的几何画', (r.Width - 30) * 3, ExactIn(bmp, r, clBlack));
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowBottomTests.TestRenamingAHiddenPageRepaintsTheActivePage;
var
  w: TProbeWindow;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  ArmActive(w);
  FWins[0].Caption := 'Problems and warnings';
  AssertTrue('改的是别的页的标题,当前页也得重画(标签画在它里面)',
    w.CacheWouldRender(w.ClientWidth, w.ClientHeight));
end;

procedure TTyToolWindowBottomTests.TestReorderingRepaintsTheActivePage;
var
  w: TProbeWindow;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  ArmActive(w);
  FWins[0].WindowIndex := 2;
  AssertTrue('调顺序之后当前页重画', w.CacheWouldRender(w.ClientWidth, w.ClientHeight));
end;

{ --- Task 7 --------------------------------------------------------------------- }

procedure TTyToolWindowBottomTests.HostTheBar;
var
  host, top, client: TBodyChild;
begin
  host := TBodyChild.Create(FForm);
  host.Parent := FForm;
  host.SetBounds(0, 0, 600, 400);
  top := TBodyChild.Create(FForm);
  top.Parent := host;
  top.Align := alTop;
  top.Height := 30;
  client := TBodyChild.Create(FForm);
  client.Parent := host;
  client.Align := alClient;
  FBar.Parent := host;
end;

procedure TTyToolWindowBottomTests.TestMaximizeFillsTheParentOverItsSiblings;
begin
  HostTheBar;
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  FBar.ExpandedSize := 150;
  AssertEquals('前提:按展开尺寸推(边缘区 4 + 150)', 154, FBar.Height);
  FBar.Maximized := True;
  AssertTrue('最大化了', FBar.Maximized);
  AssertEquals('撑满父控件、扣掉上面那个兄弟', 400 - 30, FBar.Height);
  AssertEquals('ExpandedSize 不写', 150, FBar.ExpandedSize);
end;

procedure TTyToolWindowBottomTests.TestRestoringGoesBackToTheExpandedHeight;
begin
  HostTheBar;
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  FBar.ExpandedSize := 150;
  FBar.Maximized := True;
  AssertEquals('前提:最大化的高', 370, FBar.Height);
  FBar.Maximized := False;
  AssertEquals('还原回展开尺寸推的高', 154, FBar.Height);
end;

procedure TTyToolWindowBottomTests.TestCollapsingRestoresFirst;
begin
  HostTheBar;
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  FBar.ExpandedSize := 150;
  FBar.Maximized := True;
  FBar.Collapsed := True;
  AssertFalse('收起之前先还原', FBar.Maximized);
  AssertEquals('收起的底栏高 0', 0, FBar.Height);
  FBar.Collapsed := False;
  AssertEquals('再展开是还原的高', 154, FBar.Height);
end;

procedure TTyToolWindowBottomTests.TestMaximizeIsIgnoredWhereItCannotApply;
var
  b, d: TBarAccess;
begin
  { 侧栏。 }
  NewWindow;
  FBar.Maximized := True;
  AssertFalse('侧栏不能最大化', FBar.Maximized);
  { 设计期的底栏。 }
  d := NewDesignBar;
  d.Placement := twpBottom;
  NewWindowIn(d, FDesignOwner);
  d.Maximized := True;
  AssertFalse('设计期不能最大化', d.Maximized);
  { 空底栏。 }
  b := TBarAccess.Create(FForm);
  b.Parent := FForm;
  b.Controller := FCtl;
  b.Placement := twpBottom;
  b.Maximized := True;
  AssertFalse('没有窗口不能最大化', b.Maximized);
  { 收起着。 }
  NewWindowIn(b, FForm);
  b.Collapsed := True;
  b.Maximized := True;
  AssertFalse('收起着不能最大化', b.Maximized);
  AssertTrue('也不顺带展开', b.Collapsed);
  { 加载中。 }
  b.Collapsed := False;
  b.BeginLoad;
  b.Maximized := True;
  b.EndLoad;
  AssertFalse('加载中不能最大化', b.Maximized);
  b.Maximized := True;
  AssertTrue('前提:同一条栏条件都满足时设得上', b.Maximized);
end;

procedure TTyToolWindowBottomTests.TestMaximizedIsNotPublished;
begin
  AssertNull('Maximized 只在运行时有,不进 .lfm', GetPropInfo(FBar, 'Maximized'));
end;

procedure TTyToolWindowBottomTests.TestTheEdgeIsInertWhileMaximized;
var
  e: TPoint;
  cur: TCursor;
begin
  HostTheBar;
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  FBar.ExpandedSize := 150;
  FBar.Maximized := True;
  e := FBar.EdgeRect.CenterPoint;
  AssertFalse('前提:那条线照画(边缘区还在几何里)', IsRectEmpty(FBar.EdgeRect));
  cur := FBar.Cursor;
  FBar.CallMouseMove(e.X, e.Y, []);
  AssertEquals('悬停不借调整光标', Ord(cur), Ord(FBar.Cursor));
  FBar.CallMouseDown(e.X, e.Y);
  FBar.CallMouseMove(e.X, e.Y - 40);
  AssertFalse('按下拖动不拉宽', FBar.IsEdgeDraggingForTest);
  FBar.CallMouseUp(e.X, e.Y - 40);
  AssertEquals('ExpandedSize 不变', 150, FBar.ExpandedSize);
  AssertTrue('还是最大化着', FBar.Maximized);
end;

procedure TTyToolWindowBottomTests.TestMaximizingMidResizeRestoresTheStartSize;
var
  e: TPoint;
begin
  HostTheBar;
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  FBar.ExpandedSize := 150;
  e := FBar.EdgeRect.CenterPoint;
  FBar.CallMouseDown(e.X, e.Y);
  FBar.CallMouseMove(e.X, e.Y - 40);
  AssertTrue('前提:拉宽中', FBar.IsEdgeDraggingForTest);
  AssertEquals('前提:拉宽实时写', 190, FBar.ExpandedSize);
  FBar.Maximized := True;
  AssertFalse('拉宽结束', FBar.IsEdgeDraggingForTest);
  AssertEquals('ExpandedSize 回到起点', 150, FBar.ExpandedSize);
end;

procedure TTyToolWindowBottomTests.TestTheMaximizeButtonTogglesOnARealClick;
var
  w: TProbeWindow;
  c: TPoint;
begin
  HostTheBar;
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  c := ActiveGeom.Maximize.CenterPoint;
  w.CallMouseDown(c.X, c.Y);
  w.CallMouseUp(100, w.BodyRect.Top + 40);
  AssertFalse('按在按钮、松开在别处:不变', FBar.Maximized);
  w.CallMouseDown(c.X, c.Y, [ssLeft, ssDouble]);
  w.CallMouseUp(c.X, c.Y);
  AssertFalse('多击的按下:不变(spec §7.4)', FBar.Maximized);
  ClickAt(w, c);
  AssertTrue('同一个按钮上按下松开:最大化', FBar.Maximized);
  ClickAt(w, c);
  AssertFalse('再点一下:还原', FBar.Maximized);
end;

procedure TTyToolWindowBottomTests.TestTheMaximizeGlyphTurnsIntoRestore;
var
  w: TProbeWindow;
  r: TRect;
  before, after: TBitmap;
  x, y, diff: Integer;
begin
  HostTheBar;
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  FCtl.StyleOverride := BottomTheme;
  w := FWins[1];
  r := ActiveGeom.Maximize;
  { 两次都按同一个尺寸画:标签行的几何只看行宽。 }
  before := RenderPage(w, 600, 200, 96);
  FBar.Maximized := True;
  after := RenderPage(w, 600, 200, 96);
  try
    AssertTrue('前提:按钮里有字形', InkIn(before, r, RestInk) > 0);
    diff := 0;
    for y := r.Top to r.Bottom - 1 do
      for x := r.Left to r.Right - 1 do
        if before.Canvas.Pixels[x, y] <> after.Canvas.Pixels[x, y] then Inc(diff);
    AssertTrue('最大化之后按钮画的是「还原」', diff > 0);
  finally
    before.Free;
    after.Free;
  end;
end;

procedure TTyToolWindowBottomTests.TestMaximizingRepaintsTheActivePage;
var
  w: TProbeWindow;
begin
  HostTheBar;
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  ArmActive(w);
  FBar.Maximized := True;
  AssertTrue('字形换了:当前页丢缓存', w.CacheWouldRender(w.ClientWidth, w.ClientHeight));
end;

{ --- Task 10 -------------------------------------------------------------------- }

function TTyToolWindowBottomTests.NewDesignBottomBar(AWidth: Integer): TBarAccess;
const
  Caps: array[0..2] of string = ('Problems', 'Output', 'Terminal');
var
  r: TRect;
  i: Integer;
begin
  Result := NewDesignBar;
  Result.Placement := twpBottom;
  Result.Width := AWidth;
  FDesignWins := nil;
  SetLength(FDesignWins, 3);
  for i := 0 to 2 do
  begin
    FDesignWins[i] := NewWindowIn(Result, FDesignOwner);
    FDesignWins[i].Caption := Caps[i];
  end;
  Result.ActiveWindow := FDesignWins[1];
  AssertTrue('前提:窗口是设计期的', csDesigning in FDesignWins[1].ComponentState);
  r := Result.ClientRect;
  Result.CallAdjustClientRect(r);
  for i := 0 to 2 do
    FDesignWins[i].BoundsRect := r;
end;

function TTyToolWindowBottomTests.DesignTabCentre(ABar: TBarAccess; AIndex: Integer): TPoint;
var
  w: TTyToolWindow;
begin
  w := ABar.ActiveWindow;
  Result := TabRectOf(w.HeaderGeomAt(Rect(0, 0, w.ClientWidth, w.ClientHeight),
    w.Font.PixelsPerInch), AIndex).CenterPoint;
  Result.X := Result.X + w.Left;
  Result.Y := Result.Y + w.Top;
end;

procedure TTyToolWindowBottomTests.TestADesignTimeTabClickSwitchesOnRelease;
var
  d: TBarAccess;
  p: TPoint;
begin
  d := NewDesignBottomBar;
  p := DesignTabCentre(d, 0);
  AssertEquals('栏坐标里非当前页的标签:答 1', 1, d.DesignHitTest(p.X, p.Y, 0));
  d.CallMouseDown(p.X, p.Y);
  AssertSame('按下不切', FDesignWins[1], d.ActiveWindow);
  AssertEquals('按着拖动:答 1', 1, d.DesignHitTest(p.X, p.Y, MK_LBUTTON));
  AssertEquals('松开那一拍:答 0 交还设计器', 0, d.DesignHitTest(p.X, p.Y, 0));
  AssertSame('并且在这一拍切过去', FDesignWins[0], d.ActiveWindow);
end;

procedure TTyToolWindowBottomTests.TestDesignTimeButtonsAndSeparatorAnswerZero;
var
  d: TBarAccess;
  w: TTyToolWindow;
  g: TTyToolWindowHeaderGeom;

  procedure Probe(const AName: string; const ARect: TRect);
  var
    p: TPoint;
  begin
    AssertFalse('前提:' + AName + ' 排上了', IsRectEmpty(ARect));
    p := ARect.CenterPoint;
    p.X := p.X + w.Left;
    p.Y := p.Y + w.Top;
    AssertEquals(AName + ':答 0(改模型、没有撤销)', 0, d.DesignHitTest(p.X, p.Y, 0));
    d.CallMouseDown(p.X, p.Y);
    d.DesignHitTest(p.X, p.Y, 0);
    d.CallMouseUp(p.X, p.Y);
    AssertFalse(AName + ':没有最大化', d.Maximized);
    AssertFalse(AName + ':没有收起', d.Collapsed);
    AssertSame(AName + ':当前页不变', FDesignWins[1], d.ActiveWindow);
  end;

begin
  d := NewDesignBottomBar(220);
  w := d.ActiveWindow;
  g := w.HeaderGeomAt(Rect(0, 0, w.ClientWidth, w.ClientHeight), w.Font.PixelsPerInch);
  Probe('溢出', g.Overflow);
  Probe('分隔线', g.Separator);
  Probe('最大化', g.Maximize);
  Probe('收起', g.Collapse);
end;

procedure TTyToolWindowBottomTests.TestTheDesignTimeRowsBlankSelectsTheBar;
var
  d: TBarAccess;
  w: TTyToolWindow;
  g: TTyToolWindowHeaderGeom;
begin
  d := NewDesignBottomBar;
  w := d.ActiveWindow;
  g := w.HeaderGeomAt(Rect(0, 0, w.ClientWidth, w.ClientHeight), w.Font.PixelsPerInch);
  AssertEquals('标签行空白:答 0(点空白就是选中栏)', 0,
    d.DesignHitTest(g.Tabs[High(g.Tabs)].ItemRect.Right + 5 + w.Left, 13 + w.Top, 0));
end;

procedure TTyToolWindowBottomTests.TestTheTabRowRegionLeavesOutTheActions;
var
  w: TProbeWindow;
  g: TTyToolWindowHeaderGeom;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  AddActionsKid(w, 40, 20);
  Relayout;
  g := ActiveGeom;
  AssertFalse('前提:有操作区', IsRectEmpty(g.Actions));
  AssertTrue('标签上', w.CallInTabRowRegion(TabCentre(0).X, TabCentre(0).Y));
  AssertTrue('最后一个标签之后、操作区左边的空白',
    w.CallInTabRowRegion(g.Tabs[High(g.Tabs)].ItemRect.Right + 5, 10));
  AssertTrue('按钮上', w.CallInTabRowRegion(g.Collapse.CenterPoint.X, g.Collapse.CenterPoint.Y));
  AssertFalse('操作区里不算', w.CallInTabRowRegion(g.Actions.CenterPoint.X, g.Actions.CenterPoint.Y));
  AssertFalse('正文里不算', w.CallInTabRowRegion(100, w.BodyRect.Top + 20));
end;

procedure TTyToolWindowBottomTests.TestMaskHitTestFallsBackToSelectable;
var
  w: TProbeWindow;
  msg: TCMHitTest;
  c: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  c := TabCentre(0);
  { 没有设计器窗体:坐标翻不过去,答 0(可选中),同 TestMaskHitTestFallsBackToSelectable。 }
  FillChar(msg, SizeOf(msg), 0);
  msg.Msg := CM_MASKHITTEST;
  msg.XPos := c.X;
  msg.YPos := c.Y;
  msg.Result := 99;
  w.Dispatch(msg);
  AssertEquals('没有设计器窗体:答 0', 0, msg.Result);
end;

{ --- Task 11 -------------------------------------------------------------------- }

function TTyToolWindowBottomTests.NewRuntimeBar(APlacement: TTyToolWindowPlacement;
  out AWin: TProbeWindow): TBarAccess;
begin
  Result := TBarAccess.Create(FForm);
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Placement := APlacement;
  AWin := NewWindowIn(Result, FForm);
end;

function TTyToolWindowBottomTests.MoveRaises(AWin: TTyToolWindow; ANew: TWinControl): Boolean;
begin
  Result := False;
  try
    AWin.Parent := ANew;
  except
    on EInvalidOperation do Result := True;
  end;
end;

procedure TTyToolWindowBottomTests.TestASideWindowCannotMoveToABottomBarAtRunTime;
var
  a, other: TProbeWindow;
  b: TBarAccess;
begin
  a := NewWindow;
  b := NewRuntimeBar(twpBottom, other);
  FBar.ActiveWindow := a;
  AssertTrue('侧栏窗口改到底栏:抛 EInvalidOperation', MoveRaises(a, b));
  AssertSame('它还在侧栏里', FBar, a.Parent);
  AssertSame('还是侧栏的当前页', a, FBar.ActiveWindow);
  AssertEquals('侧栏窗口数不变', 1, FBar.WindowCount);
  AssertEquals('底栏窗口数不变', 1, b.WindowCount);
end;

procedure TTyToolWindowBottomTests.TestABottomWindowCannotMoveToASideBarAtRunTime;
var
  w: TProbeWindow;
  b: TBarAccess;
begin
  NewWindow;
  b := NewRuntimeBar(twpBottom, w);
  AssertTrue('底栏窗口改到侧栏:同样抛', MoveRaises(w, FBar));
  AssertSame('它还在底栏里', b, w.Parent);
  AssertEquals('侧栏窗口数不变', 1, FBar.WindowCount);
end;

procedure TTyToolWindowBottomTests.TestDesignTimeMovesAcrossBarKinds;
var
  d1, d2: TBarAccess;
  w: TProbeWindow;
begin
  d1 := NewDesignBar;
  w := NewWindowIn(d1, FDesignOwner);
  d2 := NewDesignBar;
  d2.Placement := twpBottom;
  AssertFalse('设计期照做,不抛', MoveRaises(w, d2));
  AssertSame('挪过去了', d2, w.Parent);
end;

procedure TTyToolWindowBottomTests.TestLoadingMovesAcrossBarKinds;
var
  a, other: TProbeWindow;
  b: TBarAccess;
begin
  a := NewWindow;
  b := NewRuntimeBar(twpBottom, other);
  b.BeginLoad;
  try
    AssertFalse('加载中照做,不抛', MoveRaises(a, b));
  finally
    b.EndLoad;
  end;
  AssertSame('挪过去了', b, a.Parent);
end;

procedure TTyToolWindowBottomTests.TestSameKindOrphanAndNilMovesDoNotRaise;
var
  a, w, other: TProbeWindow;
  side2, b: TBarAccess;
  orphan: TProbeWindow;
begin
  a := NewWindow;
  side2 := NewRuntimeBar(twpRight, other);
  AssertFalse('侧 → 侧:不抛', MoveRaises(a, side2));
  AssertSame('挪过去了', side2, a.Parent);
  b := NewRuntimeBar(twpBottom, w);
  orphan := TProbeWindow.Create(FForm);
  orphan.Parent := FForm;
  AssertFalse('孤儿 → 底栏:不抛', MoveRaises(orphan, b));
  AssertSame('进了底栏', b, orphan.Parent);
  AssertFalse('底栏 → nil:不抛', MoveRaises(w, nil));
  AssertNull('离开了', w.Parent);
end;

{ --- Task 6:TTyToolWindowBottomInputTests ------------------------------------------ }

procedure TTyToolWindowBottomInputTests.TestATabSwitchesOnReleaseNotOnPress;
var
  w: TProbeWindow;
  c: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  c := TabCentre(0);
  w.CallMouseDown(c.X, c.Y);
  AssertSame('按下什么都不激活', w, FBar.ActiveWindow);
  w.CallClick;
  w.CallMouseUp(c.X, c.Y);
  AssertSame('在同一个标签上松开:切过去', FWins[0], FBar.ActiveWindow);
end;

procedure TTyToolWindowBottomInputTests.TestAReleaseOnAnotherTabIsNotAClick;
var
  w: TProbeWindow;
  a, b: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  a := TabCentre(0);
  b := TabCentre(2);
  { 两点离得近,不过拖动阈值:按在 A、松开在 B。 }
  AssertTrue('前提:两个标签挨着', Abs(b.X - a.X) > 0);
  w.CallMouseDown(a.X, a.Y);
  w.CallMouseUp(b.X, b.Y);
  AssertSame('按在 A、松开在 B:不切', w, FBar.ActiveWindow);
end;

procedure TTyToolWindowBottomInputTests.TestClickingTheActiveTabDoesNothing;
var
  w: TProbeWindow;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  FBar.OnChange := @HandleChange;
  ResetCounts;
  ClickAt(w, TabCentre(1));
  AssertSame('当前页不变', w, FBar.ActiveWindow);
  AssertFalse('不收起(不是图标条的「再点一下收起」)', FBar.Collapsed);
  AssertEquals('不发 OnChange', 0, FChanges);
end;

procedure TTyToolWindowBottomInputTests.TestADoubleClickPressNeverCounts;
var
  w: TProbeWindow;
  c: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  c := TabCentre(0);
  w.CallMouseDown(c.X, c.Y, [ssLeft, ssDouble]);
  w.CallMouseUp(c.X, c.Y);
  AssertSame('多击的按下阈值以内松开永远不算点击', w, FBar.ActiveWindow);
end;

procedure TTyToolWindowBottomInputTests.TestTheRowSwallowsTheUsersMouseEvents;
var
  w: TProbeWindow;
  c, body: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  w.OnMouseDown := @CountDown;
  w.OnMouseUp := @CountUp;
  w.OnClick := @HandleClick;
  FClicks := 0;
  c := TabCentre(1);
  ClickAt(w, c);
  AssertEquals('标签行:OnMouseDown 不触发', 0, FDowns);
  AssertEquals('标签行:OnMouseUp 不触发', 0, FUps);
  AssertEquals('标签行:OnClick 不触发', 0, FClicks);
  body := Point(100, w.BodyRect.Top + 40);
  ClickAt(w, body);
  AssertEquals('正文:OnMouseDown 照常', 1, FDowns);
  AssertEquals('正文:OnMouseUp 照常', 1, FUps);
  AssertEquals('正文:OnClick 照常', 1, FClicks);
end;

procedure TTyToolWindowBottomInputTests.TestAPressInTheBodyKeepsItsMouseUpInTheRow;
var
  w: TProbeWindow;
  c: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  w.OnMouseDown := @CountDown;
  w.OnMouseUp := @CountUp;
  c := TabCentre(0);
  w.CallMouseDown(100, w.BodyRect.Top + 40);
  w.CallMouseUp(c.X, c.Y);
  AssertEquals('按在正文:OnMouseDown', 1, FDowns);
  AssertEquals('按下决定归谁:松开在标签行也给用户配对的 OnMouseUp', 1, FUps);
  AssertSame('也不是标签点击', w, FBar.ActiveWindow);
end;

procedure TTyToolWindowBottomInputTests.TestTheWheelIsSwallowedInTheRow;
var
  w: TProbeWindow;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  w.OnMouseWheel := @CountWheel;
  AssertTrue('标签行里的滚轮答「处理过了」', w.CallDoMouseWheel(TabCentre(0)));
  AssertEquals('用户的 OnMouseWheel 不触发', 0, FWheels);
  w.CallDoMouseWheel(Point(100, w.BodyRect.Top + 40));
  AssertEquals('正文里照常', 1, FWheels);
end;

procedure TTyToolWindowBottomInputTests.TestALateLeaveFromTheOldPageKeepsTheNewHover;
var
  old, cur: TProbeWindow;
  c: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  old := FWins[1];
  ClickAt(old, TabCentre(2));
  cur := FWins[2];
  AssertSame('前提:切过去了', cur, FBar.ActiveWindow);
  c := TabCentre(0);
  cur.CallMouseMove(c.X, c.Y);
  AssertEquals('前提:新页上悬停在标签 0', 0, FBar.HeaderHoverIndexForTest);
  old.CallMouseLeave;
  AssertEquals('旧页迟到的离开不清新页的悬停', 0, FBar.HeaderHoverIndexForTest);
  AssertEquals('部件也还是标签', Ord(twbpItem), Ord(FBar.HeaderHoverPartForTest));
end;

procedure TTyToolWindowBottomInputTests.TestCancelModeOnTheActivePageCancelsThePress;
var
  w: TProbeWindow;
  c: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  c := TabCentre(0);
  w.CallMouseDown(c.X, c.Y);
  AssertEquals('前提:武装着', Ord(twgsArmed), Ord(FBar.GestureStateForTest));
  w.Perform(LM_CANCELMODE, 0, 0);
  AssertEquals('捕获者收到 LM_CANCELMODE:手势收尾', Ord(twgsIdle), Ord(FBar.GestureStateForTest));
  w.CallMouseUp(c.X, c.Y);
  AssertSame('之后的松开不是点击', w, FBar.ActiveWindow);
end;

procedure TTyToolWindowBottomInputTests.TestAWindowFreedWhileArmedIsNotAClick;
var
  w: TProbeWindow;
  c: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  c := TabCentre(0);
  w.CallMouseDown(c.X, c.Y);
  AssertEquals('前提:武装在标签 0 上', Ord(twgsArmed), Ord(FBar.GestureStateForTest));
  FWins[0].Free;
  FWins[0] := nil;
  { 不比已释放的指针(地雷 14):看手势状态和当前页。 }
  AssertEquals('手势窗口走了:记录作废', Ord(twgsIdle), Ord(FBar.GestureStateForTest));
  w.CallMouseUp(c.X, c.Y);
  AssertSame('原位置松开:当前页不变', w, FBar.ActiveWindow);
end;

procedure TTyToolWindowBottomInputTests.TestADisabledBarDoesNotSwitch;
var
  w: TProbeWindow;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  FBar.Enabled := False;
  ClickAt(w, TabCentre(0));
  AssertSame('禁用的栏:标签点不动', w, FBar.ActiveWindow);
end;

procedure TTyToolWindowBottomInputTests.TestHoverFollowsThePointerAndRepaintsTheActivePage;
var
  w: TProbeWindow;
  c: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  ArmActive(w);
  c := TabCentre(2);
  w.CallMouseMove(c.X, c.Y);
  AssertEquals('悬停在标签 2', 2, FBar.HeaderHoverIndexForTest);
  AssertEquals('部件是标签', Ord(twbpItem), Ord(FBar.HeaderHoverPartForTest));
  AssertTrue('悬停画在当前页里:当前页丢缓存', w.CacheWouldRender(w.ClientWidth, w.ClientHeight));
  w.CallMouseMove(100, w.BodyRect.Top + 40);
  AssertEquals('移到正文:悬停清掉', -1, FBar.HeaderHoverIndexForTest);
end;

procedure TTyToolWindowBottomInputTests.TestWindowAtPosFindsTabsInBarCoordinates;
var
  w: TProbeWindow;
  g: TTyToolWindowHeaderGeom;
  c: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  g := ActiveGeom;
  c := TabCentre(2);
  AssertSame('栏坐标里的标签答那个窗口', FWins[2], FBar.WindowAtPos(c.X + w.Left, c.Y + w.Top));
  c := Point(g.Tabs[High(g.Tabs)].ItemRect.Right + 5, 13);
  AssertNull('标签行空白处答 nil', FBar.WindowAtPos(c.X + w.Left, c.Y + w.Top));
end;

procedure TTyToolWindowBottomInputTests.TestAFinishedClickRepaintsThePressedState;
var
  w: TProbeWindow;
  c: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  c := TabCentre(1);
  { 悬停先落定,松开时悬停不变 —— 只剩「按下态收尾」这一件事会丢缓存。 }
  w.CallMouseMove(c.X, c.Y);
  w.CallMouseDown(c.X, c.Y);
  ArmActive(w);
  w.CallMouseUp(c.X, c.Y);
  AssertTrue('按下态要被重画掉', w.CacheWouldRender(w.ClientWidth, w.ClientHeight));
end;

procedure TTyToolWindowBottomInputTests.TestHoverIsRecheckedAfterASwitch;
var
  w: TProbeWindow;
  c: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  { 每一页的标签行排得一样(全放得下),指针放在标签 0 上(栏坐标)。 }
  c := TabCentre(0);
  FBar.FakePointer := True;
  FBar.FakePoint := Point(c.X + w.Left, c.Y + w.Top);
  ClickAt(w, TabCentre(2));
  AssertSame('前提:切过去了', FWins[2], FBar.ActiveWindow);
  AssertEquals('切页之后按指针此刻的位置重查悬停', 0, FBar.HeaderHoverIndexForTest);
end;

{ --- Task 8 --------------------------------------------------------------------- }

procedure TTyToolWindowBottomInputTests.CountBarPopup(Sender: TObject; MousePos: TPoint;
  var Handled: Boolean);
begin
  Inc(FBarPopups);
  FBarPopupPos := MousePos;
end;

procedure TTyToolWindowBottomInputTests.CountWinPopup(Sender: TObject; MousePos: TPoint;
  var Handled: Boolean);
begin
  Inc(FWinPopups);
end;

function TTyToolWindowBottomInputTests.AskHint(AWin: TProbeWindow; const APos: TPoint;
  out AInfo: THintInfo): PtrInt;
begin
  FillChar(AInfo, SizeOf(AInfo), 0);
  AInfo.HintControl := AWin;
  AInfo.CursorPos := APos;
  AInfo.HintStr := '<untouched>';
  Result := AWin.Perform(CM_HINTSHOW, 0, PtrInt(@AInfo));
end;

procedure TTyToolWindowBottomInputTests.Narrow;
begin
  FBar.Width := 220;
  Relayout;
  AssertFalse('前提:窄下来有溢出按钮', IsRectEmpty(ActiveGeom.Overflow));
end;

procedure TTyToolWindowBottomInputTests.TestTheOverflowMenuListsTheHiddenWindows;
var
  w: TProbeWindow;
  g: TTyToolWindowHeaderGeom;
  i: Integer;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  Narrow;
  g := ActiveGeom;
  AssertTrue('前提:有收起的', Length(g.Hidden) > 0);
  ClickAt(w, g.Overflow.CenterPoint);
  AssertNotNull('松开在溢出按钮上:建了菜单', FBar.OverflowMenu);
  AssertEquals('菜单项恰好是收起的那几个', Length(g.Hidden), FBar.OverflowMenu.Items.Count);
  for i := 0 to High(g.Hidden) do
  begin
    AssertEquals(Format('第 %d 项按窗口顺序', [i]), FBar.Windows[g.Hidden[i]].Caption,
      FBar.OverflowMenu.Items[i].Caption);
    AssertFalse('当前页不在里面', FBar.OverflowMenu.Items[i].Caption = w.Caption);
  end;
end;

procedure TTyToolWindowBottomInputTests.TestPickingAnOverflowItemActivatesIt;
var
  w, target: TProbeWindow;
  g: TTyToolWindowHeaderGeom;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  Narrow;
  g := ActiveGeom;
  target := FWins[g.Hidden[0]];
  ClickAt(w, g.Overflow.CenterPoint);
  FBar.OverflowMenu.Items[0].Click;
  AssertSame('点菜单项:那个窗口成为当前页', target, FBar.ActiveWindow);
end;

procedure TTyToolWindowBottomInputTests.TestADoubleClickPressOnOverflowOrHideDoesNothing;
var
  w: TProbeWindow;
  g: TTyToolWindowHeaderGeom;
  c: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  Narrow;
  g := ActiveGeom;
  c := g.Overflow.CenterPoint;
  w.CallMouseDown(c.X, c.Y, [ssLeft, ssDouble]);
  w.CallMouseUp(c.X, c.Y);
  AssertNull('多击的按下:溢出不弹菜单', FBar.OverflowMenu);
  c := g.Collapse.CenterPoint;
  w.CallMouseDown(c.X, c.Y, [ssLeft, ssDouble]);
  w.CallMouseUp(c.X, c.Y);
  AssertFalse('多击的按下:收起不生效', FBar.Collapsed);
end;

procedure TTyToolWindowBottomInputTests.TestTheHideButtonCollapsesOnRelease;
var
  w: TProbeWindow;
  c: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  c := ActiveGeom.Collapse.CenterPoint;
  w.CallMouseDown(c.X, c.Y);
  AssertFalse('按下不收起', FBar.Collapsed);
  w.CallClick;
  w.CallMouseUp(c.X, c.Y);
  AssertTrue('同处松开:收起', FBar.Collapsed);
  AssertFalse('底栏收起后当前页不可见(spec §14)', w.Visible);
  AssertEquals('收起的底栏高 0', 0, FBar.Height);
  AssertSame('当前页还是它', w, FBar.ActiveWindow);
end;

procedure TTyToolWindowBottomInputTests.TestATabHintIsStripHintOrCaptionNeverHint;
var
  w: TProbeWindow;
  info: THintInfo;
  g: TTyToolWindowHeaderGeom;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  FWins[0].StripHint := 'Show the problems';
  FWins[0].Hint := 'window hint 0';
  FWins[2].Hint := 'window hint 2';
  g := ActiveGeom;
  AssertEquals('显示提示', 0, AskHint(w, TabRectOf(g, 0).CenterPoint, info));
  AssertEquals('设了 StripHint 用它', 'Show the problems', info.HintStr);
  AssertTrue('CursorRect 是那个标签(窗口坐标)', EqualRect(TabRectOf(g, 0), info.CursorRect));
  AskHint(w, TabRectOf(g, 2).CenterPoint, info);
  AssertEquals('没设 StripHint 用 Caption,不用 Hint', 'Terminal', info.HintStr);
end;

procedure TTyToolWindowBottomInputTests.TestTheMaximizeHintFollowsTheState;
var
  w: TProbeWindow;
  info: THintInfo;
  c: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  c := ActiveGeom.Maximize.CenterPoint;
  AskHint(w, c, info);
  AssertEquals('最大化之前', rsTyToolWindowMaximize, info.HintStr);
  FBar.Maximized := True;
  AskHint(w, c, info);
  AssertEquals('最大化之后', rsTyToolWindowRestore, info.HintStr);
  AskHint(w, ActiveGeom.Collapse.CenterPoint, info);
  AssertEquals('收起按钮', rsTyToolWindowCollapse, info.HintStr);
end;

procedure TTyToolWindowBottomInputTests.TestTheRowsBlankShowsNoHint;
var
  w: TProbeWindow;
  info: THintInfo;
  g: TTyToolWindowHeaderGeom;
  c: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  w.Hint := 'window hint';
  g := ActiveGeom;
  c := Point(g.Tabs[High(g.Tabs)].ItemRect.Right + 5, 13);
  AssertEquals('标签行空白处:不显示', 1, AskHint(w, c, info));
  AssertEquals('也不填窗口自己的提示', '<untouched>', info.HintStr);
end;

procedure TTyToolWindowBottomInputTests.TestARightClickOnATabGoesToTheBarInBarCoordinates;
var
  w: TProbeWindow;
  c: TPoint;
  handled: Boolean;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  FBar.OnContextPopup := @CountBarPopup;
  w.OnContextPopup := @CountWinPopup;
  c := TabCentre(0);
  handled := False;
  w.CallDoContextPopup(c, handled);
  AssertTrue('标签行里的右键窗口这边处理掉了', handled);
  AssertEquals('栏的 OnContextPopup 触发', 1, FBarPopups);
  AssertSame('ContextWindow 是那个标签的窗口', FWins[0], FBar.ContextWindow);
  AssertEquals('MousePos 是栏坐标(X)', c.X + w.Left, FBarPopupPos.X);
  AssertEquals('MousePos 是栏坐标(Y)', c.Y + w.Top, FBarPopupPos.Y);
  AssertEquals('窗口的 OnContextPopup 不触发', 0, FWinPopups);
end;

procedure TTyToolWindowBottomInputTests.TestARightClickOnTheRowsBlankIsSwallowed;
var
  w: TProbeWindow;
  g: TTyToolWindowHeaderGeom;
  handled: Boolean;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  FBar.OnContextPopup := @CountBarPopup;
  w.OnContextPopup := @CountWinPopup;
  g := ActiveGeom;
  handled := False;
  w.CallDoContextPopup(Point(g.Tabs[High(g.Tabs)].ItemRect.Right + 5, 13), handled);
  AssertTrue('空白处的右键吞掉', handled);
  AssertEquals('栏的不触发', 0, FBarPopups);
  AssertEquals('窗口的也不触发', 0, FWinPopups);
end;

{ --- Task 9 --------------------------------------------------------------------- }

const
  { 插入线钉成橙色(CSS #FF8000)。 }
  DropTheme = ' :root { --toolwindow-drop-color: #FF8000; }';
  DropInk = TColor($0080FF);

procedure TTyToolWindowBottomInputTests.TestDraggingOutOfTheRowShowsNoDropAndCancels;
var
  w: TProbeWindow;
  c: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  c := TabCentre(0);
  w.CallMouseDown(c.X, c.Y);
  { 竖着移出标签行:阈值两个轴取大的。 }
  w.CallMouseMove(c.X, c.Y + 60, [ssLeft]);
  AssertTrue('竖着移过阈值:进入拖动', FBar.IsDraggingForTest);
  AssertEquals('标签行外没有目标', -1, FBar.DropSlotForTest);
  AssertEquals('禁止光标', Ord(crNoDrop), Ord(Screen.RealCursor));
  w.CallMouseUp(c.X, c.Y + 60);
  AssertSame('松开:顺序不变', FWins[0], FBar.Windows[0]);
  AssertSame('也不切页', w, FBar.ActiveWindow);
  AssertEquals('收尾', Ord(twgsIdle), Ord(FBar.GestureStateForTest));
end;

procedure TTyToolWindowBottomInputTests.TestDraggingToTheEndReordersOnRelease;
var
  w: TProbeWindow;
  g: TTyToolWindowHeaderGeom;
  c, e: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  FBar.OnChange := @HandleChange;
  ResetCounts;
  g := ActiveGeom;
  c := TabCentre(0);
  e := Point(g.Tabs[High(g.Tabs)].ItemRect.Right + 5, c.Y);
  w.CallMouseDown(c.X, c.Y);
  w.CallMouseMove(e.X, e.Y, [ssLeft]);
  AssertTrue('前提:拖起来了', FBar.IsDraggingForTest);
  AssertEquals('落点是最后一个之后', 3, FBar.DropSlotForTest);
  AssertSame('拖动过程中顺序不实时变', FWins[0], FBar.Windows[0]);
  w.CallMouseUp(e.X, e.Y);
  AssertSame('松开:它变成最后一个', FWins[0], FBar.Windows[2]);
  AssertSame('当前页不变', w, FBar.ActiveWindow);
  AssertEquals('不发 OnChange', 0, FChanges);
end;

procedure TTyToolWindowBottomInputTests.TestItsOwnGapsAreANoOpWithoutALine;
var
  w: TProbeWindow;
  r: TRect;
  c: TPoint;
  bmp: TBitmap;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  FCtl.StyleOverride := BottomTheme + DropTheme;
  w := FWins[1];
  r := TabRectOf(ActiveGeom, 1);
  c := r.CenterPoint;
  w.CallMouseDown(c.X, c.Y);
  { 在自己的右半边拖过阈值:落点是自己后面那个空隙。 }
  w.CallMouseMove(r.Right - 2, c.Y, [ssLeft]);
  AssertTrue('前提:拖起来了', FBar.IsDraggingForTest);
  AssertEquals('前提:落点是自己后面的空隙', 2, FBar.DropSlotForTest);
  bmp := RenderPage(w, w.ClientWidth, w.ClientHeight, 96);
  try
    AssertEquals('空操作不画线', 0, ExactIn(bmp, Rect(0, 0, w.ClientWidth, 26), DropInk));
  finally
    bmp.Free;
  end;
  w.CallMouseUp(r.Right - 2, c.Y);
  AssertSame('顺序不变', w, FBar.Windows[1]);
end;

procedure TTyToolWindowBottomInputTests.TestAForcedActiveTabMapsGapsToWindowIndexes;
var
  w: TProbeWindow;
  g: TTyToolWindowHeaderGeom;
  r: TRect;
  c: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal', 'Debug'], 3);
  FBar.Width := 250;
  Relayout;
  w := FWins[3];
  g := ActiveGeom;
  AssertEquals('前提:只排上两个', 2, Length(g.Tabs));
  AssertEquals('前提:当前页被强制留在第二格(不是前缀)', 3, g.Tabs[1].ItemIndex);
  r := g.Tabs[1].ItemRect;
  c := r.CenterPoint;
  { 拖到它自己右边的空隙:按窗口序号是 4 = 自己 + 1,空操作。 }
  w.CallMouseDown(c.X, c.Y);
  w.CallMouseMove(r.Right - 2, c.Y, [ssLeft]);
  AssertEquals('右边的空隙是窗口序号 4', 4, FBar.DropSlotForTest);
  w.CallMouseUp(r.Right - 2, c.Y);
  AssertSame('空操作:顺序不变', w, FBar.Windows[3]);
  { 拖到第一格左边:窗口序号 0。 }
  c := TabCentre(3);
  w.CallMouseDown(c.X, c.Y);
  w.CallMouseMove(g.Tabs[0].ItemRect.Left + 2, c.Y, [ssLeft]);
  AssertEquals('第一格左边是窗口序号 0', 0, FBar.DropSlotForTest);
  w.CallMouseUp(g.Tabs[0].ItemRect.Left + 2, c.Y);
  AssertSame('它挪到最前面', w, FBar.Windows[0]);
end;

procedure TTyToolWindowBottomInputTests.TestTheDropSlotReadsTheMirroredRowInReadingOrder;
var
  w: TProbeWindow;
  r: TRect;
  c: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  FBar.BiDiMode := bdRightToLeft;
  w := FWins[1];
  AssertTrue('前提:从右往左读', w.IsRightToLeft);
  r := TabRectOf(ActiveGeom, 0);
  AssertTrue('前提:窗口 0 的标签在物理最右边', r.Right > TabRectOf(ActiveGeom, 2).Right);
  c := TabCentre(2);
  w.CallMouseDown(c.X, c.Y);
  { 物理上最右那个标签的右半边 = 阅读顺序上它的前半边。 }
  w.CallMouseMove(r.Right - 3, c.Y, [ssLeft]);
  AssertTrue('前提:拖起来了', FBar.IsDraggingForTest);
  AssertEquals('落点是窗口 0 前面(槽位 0)', 0, FBar.DropSlotForTest);
  w.CallMouseUp(r.Right - 3, c.Y);
  AssertSame('松开:窗口 2 挪到最前', FWins[2], FBar.Windows[0]);
end;

procedure TTyToolWindowBottomInputTests.TestTheInsertLinePaintsInTheActivePage;
var
  w: TProbeWindow;
  g: TTyToolWindowHeaderGeom;
  c: TPoint;
  x: Integer;
  bmp: TBitmap;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  FCtl.StyleOverride := BottomTheme + DropTheme;
  w := FWins[1];
  g := ActiveGeom;
  bmp := RenderPage(w, w.ClientWidth, w.ClientHeight, 96);
  try
    AssertEquals('没拖动时没有插入线', 0, ExactIn(bmp, Rect(0, 0, w.ClientWidth, 26), DropInk));
  finally
    bmp.Free;
  end;
  c := TabCentre(0);
  x := g.Tabs[High(g.Tabs)].ItemRect.Right;
  w.CallMouseDown(c.X, c.Y);
  w.CallMouseMove(x + 5, c.Y, [ssLeft]);
  AssertEquals('前提:落点是最后一个之后', 3, FBar.DropSlotForTest);
  bmp := RenderPage(w, w.ClientWidth, w.ClientHeight, 96);
  try
    AssertTrue('插入线画在当前页里、最后一个标签的右沿',
      ExactIn(bmp, Rect(x - 2, 0, x + 2, 26), DropInk) > 0);
    AssertEquals('别处没有', ExactIn(bmp, Rect(0, 0, w.ClientWidth, 26), DropInk),
      ExactIn(bmp, Rect(x - 2, 0, x + 2, 26), DropInk));
  finally
    bmp.Free;
  end;
  w.CallMouseUp(c.X, c.Y + 60);
  { RTL:同一个落点画在镜像后的位置 —— 最后一个标签的左沿。 }
  FBar.BiDiMode := bdRightToLeft;
  g := ActiveGeom;
  c := TabCentre(0);
  x := g.Tabs[High(g.Tabs)].ItemRect.Left;
  w.CallMouseDown(c.X, c.Y);
  w.CallMouseMove(x - 5, c.Y, [ssLeft]);
  AssertEquals('前提:RTL 下落点也是最后一个之后', 3, FBar.DropSlotForTest);
  bmp := RenderPage(w, w.ClientWidth, w.ClientHeight, 96);
  try
    AssertTrue('RTL:插入线在镜像后的位置', ExactIn(bmp, Rect(x - 2, 0, x + 2, 26), DropInk) > 0);
  finally
    bmp.Free;
  end;
  w.CallMouseUp(c.X, c.Y + 60);
end;

procedure TTyToolWindowBottomInputTests.TestEscCancelsATabDrag;
var
  w: TProbeWindow;
  other: TBodyChild;
  g: TTyToolWindowHeaderGeom;
  c, e: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  other := TBodyChild.Create(FForm);
  other.Parent := FForm;
  g := ActiveGeom;
  c := TabCentre(0);
  e := Point(g.Tabs[High(g.Tabs)].ItemRect.Right + 5, c.Y);
  w.CallMouseDown(c.X, c.Y);
  w.CallMouseMove(e.X, e.Y, [ssLeft]);
  AssertTrue('前提:拖起来了', FBar.IsDraggingForTest);
  { 捕获者换成了当前页,Esc 照样经 Application 的 KeyDownBefore 到引擎。 }
  other.Perform(CN_KEYDOWN, VK_ESCAPE, 0);
  AssertEquals('Esc 取消', Ord(twgsCancelled), Ord(FBar.GestureStateForTest));
  w.CallMouseUp(e.X, e.Y);
  AssertSame('之后的松开不提交', FWins[0], FBar.Windows[0]);
  AssertSame('也不是点击', w, FBar.ActiveWindow);
end;

procedure TTyToolWindowBottomInputTests.TestCancelModeOnTheActivePageCancelsATabDrag;
var
  w: TProbeWindow;
  g: TTyToolWindowHeaderGeom;
  c, e: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  g := ActiveGeom;
  c := TabCentre(0);
  e := Point(g.Tabs[High(g.Tabs)].ItemRect.Right + 5, c.Y);
  w.CallMouseDown(c.X, c.Y);
  w.CallMouseMove(e.X, e.Y, [ssLeft]);
  AssertTrue('前提:拖起来了', FBar.IsDraggingForTest);
  w.Perform(LM_CANCELMODE, 0, 0);
  AssertEquals('当前页收到 LM_CANCELMODE:取消', Ord(twgsCancelled), Ord(FBar.GestureStateForTest));
  w.CallMouseUp(e.X, e.Y);
  AssertSame('顺序不变', FWins[0], FBar.Windows[0]);
end;

procedure TTyToolWindowBottomInputTests.TestADropSlotChangeRepaintsTheActivePage;
var
  w: TProbeWindow;
  g: TTyToolWindowHeaderGeom;
  c: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  g := ActiveGeom;
  c := TabCentre(0);
  w.CallMouseDown(c.X, c.Y);
  w.CallMouseMove(g.Tabs[High(g.Tabs)].ItemRect.Right + 5, c.Y, [ssLeft]);
  AssertEquals('前提:落点 3', 3, FBar.DropSlotForTest);
  ArmActive(w);
  w.CallMouseMove(TabRectOf(g, 2).Left + 2, c.Y, [ssLeft]);
  AssertEquals('前提:落点换成 2', 2, FBar.DropSlotForTest);
  AssertTrue('插入线挪了:当前页丢缓存', w.CacheWouldRender(w.ClientWidth, w.ClientHeight));
  w.CallMouseUp(c.X, c.Y + 60);
end;

procedure TTyToolWindowBottomInputTests.TestFreeingTheActivePageMidDragEndsTheGesture;
var
  w, next: TProbeWindow;
  g: TTyToolWindowHeaderGeom;
  c: TPoint;
begin
  NewBottomBar(['Problems', 'Output', 'Terminal'], 1);
  w := FWins[1];
  g := ActiveGeom;
  c := TabCentre(0);
  { 拖的是标签 0,捕获者是当前页(窗口 1):手势窗口和捕获者是两个窗口。 }
  w.CallMouseDown(c.X, c.Y);
  w.CallMouseMove(g.Tabs[High(g.Tabs)].ItemRect.Right + 5, c.Y, [ssLeft]);
  AssertTrue('前提:拖起来了', FBar.IsDraggingForTest);
  FWins[1].Free;
  FWins[1] := nil;
  { 不比已释放的指针(地雷 14):看手势状态。 }
  AssertEquals('捕获者走了:手势作废', Ord(twgsIdle), Ord(FBar.GestureStateForTest));
  AssertEquals('反馈清掉', -1, FBar.DropSlotForTest);
  next := TProbeWindow(FBar.ActiveWindow);
  AssertNotNull('前提:回落到别的页', next);
  Relayout;
  { 下一次按下是一条新记录,不碰那个走掉的捕获者。 }
  c := TabCentre(0);
  next.CallMouseDown(c.X, c.Y);
  next.CallMouseUp(c.X, c.Y);
end;

initialization
  RegisterTest(TTyToolWindowBottomInputTests);
  RegisterTest(TTyToolWindowBottomTests);
end.
