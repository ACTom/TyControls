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
  tyControls.ToolWindows.Layout,
  tyControls.Icons.Lucide, test.toolwindow.window,
  test.toolwindow.bar;

type
  TTyToolWindowBottomTests = class(TTyToolWindowBarFixture)
  protected
    FWins: array of TProbeWindow;
    { 一条宽 600 的底栏,按 ACaptions 建窗口(标题长短不一,地雷 12),AActive 是当前页。
      先设 Placement 再加窗口:运行时有窗口时侧 ↔ 底被忽略。最后请一遍对齐,窗口才有真实边界。 }
    procedure NewBottomBar(const ACaptions: array of string; AActive: Integer);
    { 栏和每个窗口各请一遍对齐引擎(无头不跑,见 headless-tests-never-run-lcl-align)。 }
    procedure Relayout;
    { 当前页此刻的标题行几何(窗口客户区坐标)。 }
    function ActiveGeom: TTyToolWindowHeaderGeom;
    function TabRectOf(const AGeom: TTyToolWindowHeaderGeom; AWindowIndex: Integer): TRect;
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
  end;

implementation

procedure TTyToolWindowBottomTests.NewBottomBar(const ACaptions: array of string;
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

procedure TTyToolWindowBottomTests.Relayout;
var
  i: Integer;
begin
  FBar.CallAlignControls;
  for i := 0 to High(FWins) do
    if FWins[i].Parent = FBar then FWins[i].CallAlignControls;
end;

function TTyToolWindowBottomTests.ActiveGeom: TTyToolWindowHeaderGeom;
var
  w: TTyToolWindow;
begin
  w := FBar.ActiveWindow;
  AssertNotNull('前提:有当前页', w);
  Result := w.HeaderGeomAt(Rect(0, 0, w.ClientWidth, w.ClientHeight), w.Font.PixelsPerInch);
end;

function TTyToolWindowBottomTests.TabRectOf(const AGeom: TTyToolWindowHeaderGeom;
  AWindowIndex: Integer): TRect;
var
  i: Integer;
begin
  for i := 0 to High(AGeom.Tabs) do
    if AGeom.Tabs[i].ItemIndex = AWindowIndex then Exit(AGeom.Tabs[i].ItemRect);
  Fail(Format('窗口 %d 的标签没排上', [AWindowIndex]));
  Result := Rect(0, 0, 0, 0);
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

initialization
  RegisterTest(TTyToolWindowBottomTests);
end.
