unit test.toolwindow.commands;
{$mode objfpc}{$H+}

{ 侧栏图标条末端的命令项(TTyToolWindowBar.Commands):排布、命中与绘制是同一份几何、点击语义
  (同一项上按下并松开)、菜单与处理器、不参加拖动、右键、提示、图标规矩、没有窗口时留着图标条。
  夹具在 test.toolwindow.bar;.lfm 往返在 test.toolwindow.window,跨栏拖动里的那一条在
  test.toolwindow.crossdrag。 }

interface

uses
  Classes, SysUtils, Types, TypInfo, Controls, Forms, Graphics, Menus, LCLType, LMessages,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.ToolWindows,
  tyControls.ToolWindows.Layout,
  tyControls.Icons.Lucide, test.toolwindow.window, test.toolwindow.bar;

type
  { 命令项测试共用的那几个帮手;本身没有 published 测试。 }
  TTyToolWindowCommandFixture = class(TTyToolWindowBarFixture)
  protected
    FCmdClicks: Integer;
    FLastCmd: TTyToolWindowCommand;
    FLastSender: TObject;
    { 处理器里把 AHandled 置 True。 }
    FConsume: Boolean;
    { 处理器里把被点的那一项删掉。 }
    FDeleteInHandler: Boolean;
    { 处理器跑的那一刻,菜单已经被请了几次。 }
    FDropsAtClick: Integer;
    FContextPopups: Integer;
    FContextPos: TPoint;
    procedure HandleCommandClick(Sender: TObject; ACommand: TTyToolWindowCommand;
      var AHandled: Boolean);
    procedure CountContextPopup(Sender: TObject; MousePos: TPoint; var Handled: Boolean);
    function NewCommand(const ACaption: string; ABar: TTyToolWindowBar = nil): TTyToolWindowCommand;
    { 在 ADown 按下、在 AUp 松开(真实的 MouseDown / Click / MouseUp,LCL 的顺序)。 }
    procedure PressAndRelease(const ADown, AUp: TPoint);
    procedure ClickCommandCell(AIndex: Integer);
    function RenderCell(const ACell: TRect): TBitmap;
  end;

  TTyToolWindowCommandTests = class(TTyToolWindowCommandFixture)
  published
    { 排布 }
    procedure TestCommandsSitAtTheFarEndInCollectionOrder;
    procedure TestAHiddenCommandTakesNoCell;
    procedure TestWindowsOverflowBeforeACommandIsDropped;
    procedure TestTheStripDoesNotMirrorAndTheRightBarKeepsThemAtTheBottom;
    procedure TestABottomBarLaysOutNoCommands;
    procedure TestTheCellsFollowThePpi;
    { 命中与绘制 }
    procedure TestHitTestingAgreesWithThePaintedCells;
    procedure TestACommandPaintsFromItsOwnStyleKeyAndIsNeverSelected;
    procedure TestHoverAndPressPaintTheirStates;
    procedure TestADisabledCommandPaintsDisabledAndTakesNoHover;
    { 点击 }
    procedure TestAClickIsAPressAndAReleaseOnTheSameCommand;
    procedure TestADisabledCommandOrBarDoesNotClick;
    procedure TestTheMenuDropsUnlessTheHandlerTakesTheClick;
    procedure TestTheMenuOpensBesideTheCellTowardsTheContent;
    procedure TestAHandlerMayDeleteTheCommandItWasGiven;
    procedure TestACommandLeavingWhilePressedOrHoveredLeavesNothingBehind;
    procedure TestAFreedMenuIsForgotten;
    { 不参加拖动 }
    procedure TestACommandIsNotADragHandle;
    procedure TestTheCommandCellsAreNotDropSlots;
    { 右键、提示 }
    procedure TestARightClickOnACommandSetsContextCommand;
    procedure TestTheHintIsTheHintThenTheCaption;
    { 图标 }
    procedure TestTheImageNameIsTheDurableKey;
    { 其余 }
    procedure TestVisibleCommandsKeepABarWithoutWindowsOnScreen;
    procedure TestDesignTimeDrawsCommandsButNeverClicksThem;
    procedure TestThePublishedDefaultsAreTheConstructedValues;
    procedure TestAssigningTheCollectionCopiesTheCommands;
  end;

implementation

const
  ItemPx = TyToolWindowStripItemSizeDef;
  Cyan = TColor($FFFF00);   { CSS #00FFFF }

function Empty(const ARect: TRect): Boolean;
begin
  Result := (ARect.Right <= ARect.Left) or (ARect.Bottom <= ARect.Top);
end;

{ --- 夹具 ---------------------------------------------------------------------- }

procedure TTyToolWindowCommandFixture.HandleCommandClick(Sender: TObject;
  ACommand: TTyToolWindowCommand; var AHandled: Boolean);
begin
  Inc(FCmdClicks);
  FLastCmd := ACommand;
  FLastSender := Sender;
  FDropsAtClick := FBar.MenuDrops;
  if FConsume then AHandled := True;
  if FDeleteInHandler then ACommand.Free;
end;

procedure TTyToolWindowCommandFixture.CountContextPopup(Sender: TObject; MousePos: TPoint;
  var Handled: Boolean);
begin
  Inc(FContextPopups);
  FContextPos := MousePos;
end;

function TTyToolWindowCommandFixture.NewCommand(const ACaption: string;
  ABar: TTyToolWindowBar): TTyToolWindowCommand;
begin
  if ABar = nil then ABar := FBar;
  Result := ABar.Commands.Add;
  Result.Caption := ACaption;
end;

procedure TTyToolWindowCommandFixture.PressAndRelease(const ADown, AUp: TPoint);
begin
  FBar.CallMouseDown(ADown.X, ADown.Y);
  FBar.CallClick;          { LCL 在 MouseUp 之前调 Click }
  FBar.CallMouseUp(AUp.X, AUp.Y);
end;

procedure TTyToolWindowCommandFixture.ClickCommandCell(AIndex: Integer);
var
  r: TRect;
begin
  r := FBar.CommandRect(AIndex);
  AssertFalse(Format('前提:第 %d 个命令项排上了图标条', [AIndex]), Empty(r));
  PressAndRelease(r.CenterPoint, r.CenterPoint);
end;

function TTyToolWindowCommandFixture.RenderCell(const ACell: TRect): TBitmap;
begin
  AssertFalse('前提:要画的那一格不是空的', Empty(ACell));
  Result := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, ACell, Wipe);
end;

{ --- 排布 ---------------------------------------------------------------------- }

procedure TTyToolWindowCommandTests.TestCommandsSitAtTheFarEndInCollectionOrder;
var
  L0, L: TTyToolWindowBarLayout;
  c0, c1: TTyToolWindowCommand;
  r0, r1, icon0: TRect;
begin
  NewWindow;
  NewWindow;
  L0 := FBar.BarLayout;
  icon0 := FBar.StripItemRect(0);
  AssertEquals('没有命令项:一格都不排', 0, Length(L0.Commands));
  AssertTrue('没有命令项:那一段是空的', Empty(L0.CommandCells));
  c0 := NewCommand('Accounts');
  c1 := NewCommand('Manage');
  L := FBar.BarLayout;
  AssertEquals('两项都排上', 2, Length(L.Commands));
  AssertEquals('槽位记的是集合里的序号', 0, L.Commands[0].ItemIndex);
  AssertEquals('槽位记的是集合里的序号', 1, L.Commands[1].ItemIndex);
  r0 := FBar.CommandRect(0);
  r1 := FBar.CommandRect(1);
  AssertTrue('槽位的矩形就是 CommandRect', EqualRect(r0, L.Commands[0].ItemRect)
    and EqualRect(r1, L.Commands[1].ItemRect));
  AssertEquals('最后一项贴着条尾', L0.Cells.Bottom, r1.Bottom);
  AssertEquals('按集合顺序从上到下', r0.Bottom, r1.Top);
  AssertEquals('格子和窗口图标一样高', icon0.Bottom - icon0.Top, r0.Bottom - r0.Top);
  AssertEquals('第二格也是', ItemPx, r1.Bottom - r1.Top);
  AssertEquals('和窗口图标同一列(左)', icon0.Left, r0.Left);
  AssertEquals('和窗口图标同一列(右)', icon0.Right, r0.Right);
  AssertEquals('排窗口图标的那一段到命令项为止', r0.Top, L.Cells.Bottom);
  AssertTrue('命令项那一段 = 两格合起来',
    EqualRect(L.CommandCells, Rect(r0.Left, r0.Top, r1.Right, r1.Bottom)));
  AssertTrue('窗口图标原地不动', EqualRect(icon0, FBar.StripItemRect(0)));
  { 集合里换了顺序,格子跟着换。 }
  c1.Index := 0;
  AssertSame('原来最后一项挪到第一格', c1, FBar.CommandAtPos(r0.CenterPoint.X, r0.CenterPoint.Y));
  AssertSame('原来第一项落到条尾', c0, FBar.CommandAtPos(r1.CenterPoint.X, r1.CenterPoint.Y));
end;

procedure TTyToolWindowCommandTests.TestAHiddenCommandTakesNoCell;
var
  c1: TTyToolWindowCommand;
  L: TTyToolWindowBarLayout;
  top3: Integer;
begin
  NewWindow;
  NewCommand('A');
  c1 := NewCommand('B');
  NewCommand('C');
  top3 := FBar.CommandRect(0).Top;
  c1.Visible := False;
  L := FBar.BarLayout;
  AssertEquals('藏起来的不排', 2, Length(L.Commands));
  AssertEquals('排上的是第 0 项', 0, L.Commands[0].ItemIndex);
  AssertEquals('和第 2 项', 2, L.Commands[1].ItemIndex);
  AssertTrue('藏起来的没有格子', Empty(FBar.CommandRect(1)));
  AssertEquals('前面的补上来:紧挨着', FBar.CommandRect(0).Bottom, FBar.CommandRect(2).Top);
  AssertEquals('整段矮了一格', top3 + ItemPx, FBar.CommandRect(0).Top);
  AssertEquals('窗口图标那一段跟着长一格', top3 + ItemPx, L.Cells.Bottom);
  c1.Visible := True;
  AssertFalse('显示回来又有格子', Empty(FBar.CommandRect(1)));
  AssertEquals('整段回到三格', top3, FBar.CommandRect(0).Top);
end;

procedure TTyToolWindowCommandTests.TestWindowsOverflowBeforeACommandIsDropped;
var
  w: array[0..4] of TProbeWindow;
  L: TTyToolWindowBarLayout;
  i: Integer;
begin
  for i := 0 to 4 do w[i] := NewWindow;      { 最后一个是当前页 }
  NewCommand('Accounts');
  NewCommand('Manage');
  { 五格高:命令项占两格,窗口剩三格 —— 放不下五个图标,先收进溢出。 }
  FBar.Height := 5 * ItemPx;
  L := FBar.BarLayout;
  AssertEquals('命令项都还在', 2, Length(L.Commands));
  AssertTrue('窗口收进了溢出', Length(FBar.OverflowWindows) > 0);
  AssertFalse('有溢出按钮', Empty(L.Overflow));
  AssertTrue('溢出按钮在命令项上面', L.Overflow.Bottom <= FBar.CommandRect(0).Top);
  AssertEquals('最后一项照样贴着条尾', 5 * ItemPx, FBar.CommandRect(1).Bottom);
  { 三格高:窗口有不止一个时留两格(当前页 + 溢出按钮),命令项只剩一格 —— 留下的是最后一项。 }
  FBar.Height := 3 * ItemPx;
  L := FBar.BarLayout;
  AssertEquals('只排得下一项', 1, Length(L.Commands));
  AssertEquals('留下的是最靠条尾的那一项', 1, L.Commands[0].ItemIndex);
  AssertTrue('前面那一项排不下:没有格子', Empty(FBar.CommandRect(0)));
  AssertEquals('它贴着条尾', 3 * ItemPx, FBar.CommandRect(1).Bottom);
  AssertEquals('当前页的图标还在条上', 1, Length(L.Slots));
  AssertEquals('就是当前页', 4, L.Slots[0].ItemIndex);
  AssertFalse('溢出按钮也还在', Empty(L.Overflow));
  AssertTrue('排不下的那一项点不中',
    FBar.CommandAtPos(L.Overflow.CenterPoint.X, L.Overflow.CenterPoint.Y) = nil);
  { 两格高:全让给窗口,命令项一项都不排。 }
  FBar.Height := 2 * ItemPx;
  L := FBar.BarLayout;
  AssertEquals('连一项都排不下', 0, Length(L.Commands));
  AssertTrue('那一段是空的', Empty(L.CommandCells));
  AssertEquals('窗口图标那一段是整条', 2 * ItemPx, L.Cells.Bottom - L.Cells.Top);
  AssertFalse('溢出按钮还在', Empty(L.Overflow));
  { 只有一个窗口:只给它留一格,同样两格高就排得下一项命令。 }
  for i := 0 to 3 do w[i].Free;
  L := FBar.BarLayout;
  AssertEquals('一个窗口只留一格', 1, Length(L.Commands));
  AssertEquals('还是最靠条尾的那一项', 1, L.Commands[0].ItemIndex);
  AssertEquals('窗口图标还是整格', ItemPx, FBar.StripItemRect(0).Bottom - FBar.StripItemRect(0).Top);
end;

procedure TTyToolWindowCommandTests.TestTheStripDoesNotMirrorAndTheRightBarKeepsThemAtTheBottom;
var
  rL, rR: TRect;
  L: TTyToolWindowBarLayout;
begin
  NewWindow;
  NewCommand('Manage');
  rL := FBar.CommandRect(0);
  FBar.BiDiMode := bdRightToLeft;
  AssertTrue('前提:栏读 RTL', FBar.IsRightToLeft);
  AssertTrue('图标条的几何看 Placement,不看读写方向', EqualRect(rL, FBar.CommandRect(0)));
  FBar.BiDiMode := bdLeftToRight;
  FBar.Placement := twpRight;
  L := FBar.BarLayout;
  rR := FBar.CommandRect(0);
  AssertFalse('右栏也排', Empty(rR));
  AssertEquals('右栏:同样贴着条尾', rL.Bottom, rR.Bottom);
  AssertEquals('右栏:同样高', rL.Top, rR.Top);
  AssertEquals('右栏:跟窗口图标同一列', FBar.StripItemRect(0).Left, rR.Left);
  AssertTrue('右栏:在内容区右边的图标条里', (rR.Left >= L.Content.Right) and (rR.Right <= L.Strip.Right));
end;

procedure TTyToolWindowCommandTests.TestABottomBarLaysOutNoCommands;
var
  c: TTyToolWindowCommand;
  L: TTyToolWindowBarLayout;
begin
  c := NewCommand('Manage');
  AssertFalse('前提:侧栏排得上', Empty(FBar.CommandRect(0)));
  FBar.Placement := twpBottom;
  NewWindow;
  L := FBar.BarLayout;
  AssertEquals('底栏没有图标条:不排', 0, Length(L.Commands));
  AssertTrue('没有格子', Empty(FBar.CommandRect(0)));
  AssertTrue('哪里都点不中',
    FBar.CommandAtPos(FBar.ClientWidth div 2, FBar.ClientHeight div 2) = nil);
  AssertSame('集合里还在', c, FBar.Commands[0]);
end;

procedure TTyToolWindowCommandTests.TestTheCellsFollowThePpi;
var
  r: TRect;
begin
  NewWindow;
  NewCommand('Manage');
  r := FBar.CommandRect(0);
  AssertEquals('96 PPI:一格', ItemPx, r.Bottom - r.Top);
  FBar.Font.PixelsPerInch := 192;
  r := FBar.CommandRect(0);
  AssertEquals('192 PPI:高两倍', 2 * ItemPx, r.Bottom - r.Top);
  AssertEquals('照样贴着条尾', FBar.ClientHeight, r.Bottom);
end;

{ --- 命中与绘制 ---------------------------------------------------------------- }

procedure TTyToolWindowCommandTests.TestHitTestingAgreesWithThePaintedCells;
var
  a: TProbeWindow;
  c: array[0..1] of TTyToolWindowCommand;
  r, gap, icon: TRect;
  bmp: TBitmap;
  i, idx, notGround, wipeLeft: Integer;
begin
  FCtl.StyleOverride := StripTheme;
  FBar.Images := NewHouseList;
  a := NewWindow;
  a.ImageName := 'house';
  c[0] := NewCommand('Accounts');
  c[1] := NewCommand('Manage');
  for i := 0 to 1 do
  begin
    c[i].ImageName := 'house';
    r := FBar.CommandRect(i);
    AssertSame('格子中心', c[i], FBar.CommandAtPos(r.CenterPoint.X, r.CenterPoint.Y));
    AssertSame('左上角那个像素', c[i], FBar.CommandAtPos(r.Left, r.Top));
    AssertSame('右下角那个像素', c[i], FBar.CommandAtPos(r.Right - 1, r.Bottom - 1));
    AssertTrue('部件是命令项', FBar.PartAt(r.CenterPoint.X, r.CenterPoint.Y, idx) = twbpCommand);
    AssertEquals('序号是集合里的序号', i, idx);
    AssertTrue('命令项上没有窗口', FBar.WindowAtPos(r.CenterPoint.X, r.CenterPoint.Y) = nil);
    { 画的就是那一格:图标着成静止态的墨色,整格都画到。 }
    bmp := RenderCell(r);
    try
      AssertTrue('格子里画了图标', CountInk(bmp, Ground, RestInk) > 0);
      TallyPixels(bmp, Ground, Wipe, notGround, wipeLeft);
      AssertEquals('整格都画到,不留底漆', 0, wipeLeft);
    finally
      bmp.Free;
    end;
  end;
  { 图标和命令项之间的空白:点不中,也什么都没画。 }
  icon := FBar.StripItemRect(0);
  r := FBar.CommandRect(0);
  gap := Rect(r.Left, icon.Bottom, r.Right, r.Top);
  AssertTrue('第一格上面一个像素不是它', FBar.CommandAtPos(r.Left, r.Top - 1) = nil);
  AssertTrue('空白处部件是 none', FBar.PartAt(gap.CenterPoint.X, gap.CenterPoint.Y, idx) = twbpNone);
  bmp := RenderCell(gap);
  try
    TallyPixels(bmp, Ground, Wipe, notGround, wipeLeft);
    AssertEquals('空白处只有图标条的底色', 0, notGround);
  finally
    bmp.Free;
  end;
  { 条的右边(内容区)不是命令项。 }
  AssertTrue('内容区里不是命令项',
    FBar.CommandAtPos(FBar.BarLayout.Content.CenterPoint.X, r.CenterPoint.Y) = nil);
end;

procedure TTyToolWindowCommandTests.TestACommandPaintsFromItsOwnStyleKeyAndIsNeverSelected;
var
  a: TProbeWindow;
  c: TTyToolWindowCommand;
  bmp: TBitmap;
begin
  FBar.Images := NewHouseList;
  a := NewWindow;
  a.ImageName := 'house';
  c := NewCommand('Manage');
  c.ImageName := 'house';
  { 默认:命令项和静止的窗口图标同一种墨色;当前页那一格是选中墨色加指示条,命令项从来没有。 }
  FCtl.StyleOverride := StripTheme;
  bmp := RenderCell(FBar.StripItemRect(0));
  try
    AssertTrue('前提:当前页那一格是选中墨色', CountInk(bmp, Ground, SelInk) > 0);
    AssertTrue('前提:当前页那一格有指示条', CountExact(bmp, clBlack) > 0);
  finally
    bmp.Free;
  end;
  bmp := RenderCell(FBar.CommandRect(0));
  try
    AssertTrue('命令项着静止墨色', CountInk(bmp, Ground, RestInk) > 0);
    AssertEquals('没有选中墨色', 0, CountInk(bmp, Ground, SelInk));
    AssertEquals('没有指示条', 0, CountExact(bmp, clBlack));
  finally
    bmp.Free;
  end;
  { 主题按它自己的键改:只有命令项变,窗口图标不跟着。 }
  NewWindow.ImageName := 'house';
  FBar.ActiveWindow := a;
  FCtl.StyleOverride := StripTheme + ' TyToolWindowStripCommand { color: #FFFF00; }';
  bmp := RenderCell(FBar.CommandRect(0));
  try
    AssertTrue('命令项按自己的键着色', CountInk(bmp, Ground, SelInk) > 0);
    AssertEquals('不再是图标项的静止墨色', 0, CountInk(bmp, Ground, RestInk));
  finally
    bmp.Free;
  end;
  bmp := RenderCell(FBar.StripItemRect(1));
  try
    AssertTrue('静止的窗口图标还是原来的墨色', CountInk(bmp, Ground, RestInk) > 0);
    AssertEquals('没被命令项的规则带走', 0, CountInk(bmp, Ground, SelInk));
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowCommandTests.TestHoverAndPressPaintTheirStates;
const
  Orange = TColor($0080FF);    { CSS #FF8000 }
var
  r, icon: TRect;
  area: Integer;

  function Count(const ACell: TRect; AColor: TColor): Integer;
  var
    bmp: TBitmap;
  begin
    bmp := RenderCell(ACell);
    try
      Result := CountExact(bmp, AColor);
    finally
      bmp.Free;
    end;
  end;

begin
  FCtl.StyleOverride := ':root { --toolwindow-strip-bg: #FF00FF;' +
    ' --toolwindow-overlay-hover: #00FFFF; --toolwindow-overlay-active: #FF8000; }';
  NewWindow;
  NewWindow;
  NewCommand('Accounts');
  NewCommand('Manage');
  r := FBar.CommandRect(1);
  { 第一个窗口不是当前页:它那一格没有指示条,悬停时整格一个颜色。 }
  icon := FBar.StripItemRect(0);
  area := (r.Right - r.Left) * (r.Bottom - r.Top);
  AssertEquals('前提:没悬停时没有悬停底色', 0, Count(r, Cyan));
  { 真实的悬停追踪:不带键的移动。 }
  FBar.CallMouseMove(r.CenterPoint.X, r.CenterPoint.Y, []);
  AssertEquals('悬停的那一格整格铺 :hover 的底色', area, Count(r, Cyan));
  AssertEquals('另一项不亮', 0, Count(FBar.CommandRect(0), Cyan));
  AssertEquals('窗口图标不亮', 0, Count(icon, Cyan));
  FBar.CallMouseMove(icon.CenterPoint.X, icon.CenterPoint.Y, []);
  AssertEquals('挪到窗口图标上:命令项不亮了', 0, Count(r, Cyan));
  AssertEquals('亮的是窗口图标', area, Count(icon, Cyan));
  FBar.CallMouseMove(r.CenterPoint.X, r.CenterPoint.Y, []);
  FBar.CallMouseLeave;
  AssertEquals('指针离开:悬停清掉', 0, Count(r, Cyan));
  { 按下:那一格是 :active。 }
  AssertEquals('前提:没按下时没有按下底色', 0, Count(r, Orange));
  FBar.CallMouseDown(r.CenterPoint.X, r.CenterPoint.Y);
  AssertEquals('按下的那一格整格铺 :active 的底色', area, Count(r, Orange));
  AssertEquals('另一项没按下', 0, Count(FBar.CommandRect(0), Orange));
  FBar.CallMouseUp(r.CenterPoint.X, r.CenterPoint.Y);
  AssertEquals('松开:按下态清掉', 0, Count(r, Orange));
end;

procedure TTyToolWindowCommandTests.TestADisabledCommandPaintsDisabledAndTakesNoHover;
var
  c: TTyToolWindowCommand;
  r: TRect;
  bmp: TBitmap;
begin
  { :disabled 的墨色是 --muted:钉成黄的(SelInk 那条混合线)。 }
  FCtl.StyleOverride := StripTheme + ' :root { --muted: #FFFF00; --toolwindow-overlay-hover: #00FFFF; }';
  FBar.Images := NewHouseList;
  NewWindow;
  c := NewCommand('Manage');
  c.ImageName := 'house';
  r := FBar.CommandRect(0);
  bmp := RenderCell(r);
  try
    AssertTrue('可用:静止墨色', CountInk(bmp, Ground, RestInk) > 0);
    AssertEquals('可用:没有禁用墨色', 0, CountInk(bmp, Ground, SelInk));
  finally
    bmp.Free;
  end;
  c.Enabled := False;
  FBar.CallMouseMove(r.CenterPoint.X, r.CenterPoint.Y, []);
  bmp := RenderCell(r);
  try
    AssertTrue('禁用:图标着 :disabled 的墨色', CountInk(bmp, Ground, SelInk) > 0);
    AssertEquals('禁用:没有静止墨色', 0, CountInk(bmp, Ground, RestInk));
    AssertEquals('禁用的不接悬停', 0, CountExact(bmp, Cyan));
  finally
    bmp.Free;
  end;
  c.Enabled := True;
  FBar.CallMouseMove(r.CenterPoint.X, r.CenterPoint.Y + 1, []);
  bmp := RenderCell(r);
  try
    AssertTrue('启用回来就接悬停', CountExact(bmp, Cyan) > 0);
  finally
    bmp.Free;
  end;
end;

{ --- 点击 ---------------------------------------------------------------------- }

procedure TTyToolWindowCommandTests.TestAClickIsAPressAndAReleaseOnTheSameCommand;
var
  a, b: TProbeWindow;
  c0, c1: TTyToolWindowCommand;
  p0, p1, blank, icon: TPoint;
begin
  a := NewWindow;
  b := NewWindow;
  FBar.ActiveWindow := a;
  c0 := NewCommand('Accounts');
  c1 := NewCommand('Manage');
  FBar.OnCommandClick := @HandleCommandClick;
  FBar.OnClick := @HandleClick;
  FBar.OnChange := @HandleChange;
  FBar.OnCollapse := @HandleCollapse;
  ResetCounts;
  p0 := FBar.CommandRect(0).CenterPoint;
  p1 := FBar.CommandRect(1).CenterPoint;
  icon := FBar.StripItemRect(1).CenterPoint;
  blank := Point(p0.X, FBar.CommandRect(0).Top - 10);
  AssertTrue('前提:空白处什么都不是',
    (FBar.CommandAtPos(blank.X, blank.Y) = nil) and (FBar.WindowAtPos(blank.X, blank.Y) = nil));
  FBar.CallMouseDown(p0.X, p0.Y);
  AssertEquals('按下不算', 0, FCmdClicks);
  FBar.CallClick;
  FBar.CallMouseUp(p0.X, p0.Y);
  AssertEquals('同一项上松开:一次点击', 1, FCmdClicks);
  AssertSame('事件给的是那一项', c0, FLastCmd);
  AssertSame('Sender 是栏', FBar, FLastSender);
  AssertEquals('不是「点了栏」:OnClick 不发', 0, FClicks);
  PressAndRelease(p0, p1);
  AssertEquals('在另一项上松开:不算', 1, FCmdClicks);
  PressAndRelease(p0, blank);
  AssertEquals('在空白处松开:不算', 1, FCmdClicks);
  PressAndRelease(icon, p0);
  AssertEquals('按在窗口图标上、松在命令项上:不算', 1, FCmdClicks);
  AssertSame('也不切页', a, FBar.ActiveWindow);
  PressAndRelease(p0, icon);
  AssertEquals('按在命令项上、松在窗口图标上:不算', 1, FCmdClicks);
  AssertSame('也不切页(反过来)', a, FBar.ActiveWindow);
  PressAndRelease(p1, p1);
  AssertEquals('另一项的点击', 2, FCmdClicks);
  AssertSame('给的是另一项', c1, FLastCmd);
  { 命令项从不显示工具窗口:当前页、收起状态都没动过。 }
  AssertSame('当前页没变', a, FBar.ActiveWindow);
  AssertFalse('没有收起', FBar.Collapsed);
  AssertEquals('没发 OnChange', 0, FChanges);
  AssertEquals('没发 OnCollapse', 0, FCollapses);
  AssertTrue('另一个窗口还藏着', not b.Visible);
end;

procedure TTyToolWindowCommandTests.TestADisabledCommandOrBarDoesNotClick;
var
  c: TTyToolWindowCommand;
begin
  NewWindow;
  c := NewCommand('Manage');
  FBar.OnCommandClick := @HandleCommandClick;
  c.Enabled := False;
  ClickCommandCell(0);
  AssertEquals('禁用的命令项点了没反应', 0, FCmdClicks);
  c.Click;
  AssertEquals('程序里调 Click 也一样', 0, FCmdClicks);
  { 按下时它是禁用的:这一下没有武装,松开之前启用了也不算点击。 }
  FBar.CallMouseDown(FBar.CommandRect(0).CenterPoint.X, FBar.CommandRect(0).CenterPoint.Y);
  c.Enabled := True;
  FBar.CallMouseUp(FBar.CommandRect(0).CenterPoint.X, FBar.CommandRect(0).CenterPoint.Y);
  AssertEquals('按在禁用的命令项上:不武装', 0, FCmdClicks);
  ClickCommandCell(0);
  AssertEquals('启用了就响', 1, FCmdClicks);
  c.Click;
  AssertEquals('程序里调 Click 等于点一下', 2, FCmdClicks);
  AssertSame('给的是它', c, FLastCmd);
  FBar.Enabled := False;
  c.Click;
  ClickCommandCell(0);
  AssertEquals('整条栏禁用:都不响', 2, FCmdClicks);
end;

procedure TTyToolWindowCommandTests.TestTheMenuDropsUnlessTheHandlerTakesTheClick;
var
  c: TTyToolWindowCommand;
  menu: TPopupMenu;
begin
  NewWindow;
  c := NewCommand('Manage');
  menu := TPopupMenu.Create(FForm);
  c.DropDownMenu := menu;
  { 没有处理器:直接弹菜单。 }
  ClickCommandCell(0);
  AssertEquals('没有处理器:弹菜单', 1, FBar.MenuDrops);
  AssertSame('弹的是这一项的', c, FBar.LastDropped);
  AssertSame('菜单的 PopupComponent 是栏', FBar, menu.PopupComponent);
  { 处理器没处理掉:先发事件,再弹菜单。 }
  FBar.OnCommandClick := @HandleCommandClick;
  FConsume := False;
  ClickCommandCell(0);
  AssertEquals('事件照发', 1, FCmdClicks);
  AssertEquals('没处理掉:菜单照弹', 2, FBar.MenuDrops);
  AssertEquals('事件在弹菜单之前', 1, FDropsAtClick);
  { 处理器处理掉了:不弹。 }
  FConsume := True;
  ClickCommandCell(0);
  AssertEquals('事件照发', 2, FCmdClicks);
  AssertEquals('处理掉了:菜单不弹', 2, FBar.MenuDrops);
  { 没有菜单的命令项:只有事件。 }
  FConsume := False;
  c.DropDownMenu := nil;
  ClickCommandCell(0);
  AssertEquals('事件照发', 3, FCmdClicks);
  AssertEquals('没有菜单:没东西可弹', 2, FBar.MenuDrops);
end;

procedure TTyToolWindowCommandTests.TestTheMenuOpensBesideTheCellTowardsTheContent;
var
  c, hidden: TTyToolWindowCommand;
  menu: TPopupMenu;
  r: TRect;
  pt: TPoint;
  al: TPopupAlignment;
begin
  NewWindow;
  hidden := NewCommand('Hidden');
  hidden.Visible := False;
  c := NewCommand('Manage');
  menu := TPopupMenu.Create(FForm);
  c.DropDownMenu := menu;
  r := FBar.CommandRect(1);
  AssertTrue('排上条的有锚点', FBar.CommandMenuAnchor(c, pt, al));
  AssertEquals('左栏:从那一格的右沿', r.Right, pt.X);
  AssertEquals('左栏:和那一格顶对齐', r.Top, pt.Y);
  AssertTrue('左栏:往右开', al = paLeft);
  AssertFalse('没排上条的没有锚点', FBar.CommandMenuAnchor(hidden, pt, al));
  FBar.Placement := twpRight;
  r := FBar.CommandRect(1);
  AssertTrue('右栏也有', FBar.CommandMenuAnchor(c, pt, al));
  AssertEquals('右栏:从那一格的左沿', r.Left, pt.X);
  AssertEquals('右栏:和那一格顶对齐', r.Top, pt.Y);
  AssertTrue('右栏:往左开', al = paRight);
  menu.Alignment := paLeft;
  ClickCommandCell(1);
  AssertEquals('前提:菜单被请了', 1, FBar.MenuDrops);
  AssertTrue('弹之前把菜单的对齐方式设成开向内容区的那一个', menu.Alignment = paRight);
end;

procedure TTyToolWindowCommandTests.TestAHandlerMayDeleteTheCommandItWasGiven;
var
  c: TTyToolWindowCommand;
  menu: TPopupMenu;
begin
  NewWindow;
  NewCommand('Keep');
  c := NewCommand('Gone');
  menu := TPopupMenu.Create(FForm);
  c.DropDownMenu := menu;
  FBar.OnCommandClick := @HandleCommandClick;
  FDeleteInHandler := True;
  ClickCommandCell(1);
  AssertEquals('事件发了', 1, FCmdClicks);
  AssertEquals('那一项没了', 1, FBar.Commands.Count);
  AssertEquals('它的菜单不弹(它已经不在了)', 0, FBar.MenuDrops);
end;

procedure TTyToolWindowCommandTests.TestACommandLeavingWhilePressedOrHoveredLeavesNothingBehind;
var
  c0: TTyToolWindowCommand;
  p: TPoint;
  bmp: TBitmap;
  handled: Boolean;
begin
  FCtl.StyleOverride := ':root { --toolwindow-strip-bg: #FF00FF;' +
    ' --toolwindow-overlay-hover: #00FFFF; --toolwindow-overlay-active: #00FFFF; }';
  NewWindow;
  c0 := NewCommand('First');
  NewCommand('Second');
  FBar.OnCommandClick := @HandleCommandClick;
  FBar.OnContextPopup := @CountContextPopup;
  { 条尾那一格现在是 Second;把它删掉,First 落到这一格。 }
  p := FBar.CommandRect(1).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  AssertTrue('前提:武装着', FBar.GestureStateForTest = twgsArmed);
  FBar.Commands.Delete(1);
  AssertTrue('按下的那一项走了:手势作废', FBar.GestureStateForTest = twgsIdle);
  AssertSame('前提:现在这一格是另一项', c0, FBar.CommandAtPos(p.X, p.Y));
  FBar.CallMouseUp(p.X, p.Y);
  AssertEquals('松开不算点击(按下的不是它)', 0, FCmdClicks);
  { 悬停着的那一项走了:不留悬停。 }
  NewCommand('Third');
  p := FBar.CommandRect(1).CenterPoint;
  FBar.CallMouseMove(p.X, p.Y, []);
  bmp := RenderCell(FBar.CommandRect(1));
  try
    AssertTrue('前提:悬停着', CountExact(bmp, Cyan) > 0);
  finally
    bmp.Free;
  end;
  { 右键也落在它上面。 }
  handled := False;
  FBar.CallDoContextPopup(p, handled);
  AssertTrue('前提:右键记下了它', FBar.ContextCommand <> nil);
  FBar.Commands.Delete(1);
  AssertTrue('它走了:ContextCommand 不悬空', FBar.ContextCommand = nil);
  bmp := RenderCell(FBar.CommandRect(0));
  try
    AssertEquals('补上来的那一项没有悬停', 0, CountExact(bmp, Cyan));
  finally
    bmp.Free;
  end;
  { 紧接着新建的一项多半落在刚释放的那块内存上:记着的悬停要是没清,它一出生就是悬停的。 }
  NewCommand('Reborn');
  bmp := RenderCell(FBar.CommandRect(1));
  try
    AssertEquals('新建的一项不继承走掉那一项的悬停', 0, CountExact(bmp, Cyan));
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowCommandTests.TestAFreedMenuIsForgotten;
var
  c0, c1: TTyToolWindowCommand;
  menu, other: TPopupMenu;
begin
  NewWindow;
  c0 := NewCommand('A');
  c1 := NewCommand('B');
  menu := TPopupMenu.Create(nil);
  other := TPopupMenu.Create(FForm);
  c0.DropDownMenu := menu;
  c1.DropDownMenu := other;
  menu.Free;
  AssertTrue('菜单释放了:引用清掉', c0.DropDownMenu = nil);
  AssertSame('别的命令项的菜单不动', other, c1.DropDownMenu);
  ClickCommandCell(0);
  AssertEquals('没有菜单可弹', 0, FBar.MenuDrops);
end;

{ --- 不参加拖动 ---------------------------------------------------------------- }

procedure TTyToolWindowCommandTests.TestACommandIsNotADragHandle;
var
  a: TProbeWindow;
  p: TPoint;
begin
  a := NewWindow;
  NewWindow;
  NewWindow;
  NewCommand('Manage');
  FBar.OnCommandClick := @HandleCommandClick;
  FBar.DragMode := dmAutomatic;
  p := FBar.CommandRect(0).CenterPoint;
  { LCL 的自动拖动也不起。 }
  FBar.FakePointer := True;
  FBar.FakePoint := p;
  FBar.CallBeginAutoDrag;
  AssertEquals('命令项上不起 LCL 拖动', 0, FBar.AutoDragStarts);
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseMove(p.X, p.Y - 3 * ItemPx);
  AssertFalse('按住命令项拖过阈值:拖不起来', FBar.IsDraggingForTest);
  AssertEquals('没有落点', -1, FBar.DropSlotForTest);
  FBar.CallMouseUp(p.X, p.Y - 3 * ItemPx);
  AssertEquals('松在别处:不算点击', 0, FCmdClicks);
  AssertSame('窗口顺序没动', a, FBar.Windows[0]);
end;

procedure TTyToolWindowCommandTests.TestTheCommandCellsAreNotDropSlots;
var
  a, b, c: TProbeWindow;
  p, cmd, blank: TPoint;
begin
  a := NewWindow;
  b := NewWindow;
  c := NewWindow;
  NewCommand('Accounts');
  NewCommand('Manage');
  p := FBar.StripItemRect(0).CenterPoint;
  cmd := FBar.CommandRect(1).CenterPoint;
  { 最后一个图标下面、命令项上面的空白:还在排窗口图标的那一段里。 }
  blank := Point(p.X, FBar.CommandRect(0).Top - 4);
  AssertTrue('前提:空白处在最后一个图标下面', blank.Y > FBar.StripItemRect(2).Bottom);
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseMove(p.X + 10, p.Y);
  AssertTrue('前提:拖起来了', FBar.IsDraggingForTest);
  FBar.CallMouseMove(blank.X, blank.Y);
  AssertEquals('条上的空白 = 最后一个之后', 3, FBar.DropSlotForTest);
  FBar.CallMouseMove(cmd.X, cmd.Y);
  AssertEquals('命令项上没有落点', -1, FBar.DropSlotForTest);
  AssertEquals('是禁止光标', Ord(crNoDrop), Ord(FBar.DragCursorForTest));
  FBar.CallMouseUp(cmd.X, cmd.Y);
  AssertSame('在命令项上松开:顺序不变', a, FBar.Windows[0]);
  AssertSame('顺序不变', b, FBar.Windows[1]);
  AssertSame('顺序不变', c, FBar.Windows[2]);
  { 对照:松在空白处就挪到最后。 }
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseMove(p.X + 10, p.Y);
  FBar.CallMouseMove(blank.X, blank.Y);
  FBar.CallMouseUp(blank.X, blank.Y);
  AssertSame('松在空白处:挪到最后', a, FBar.Windows[2]);
end;

{ --- 右键、提示 ---------------------------------------------------------------- }

procedure TTyToolWindowCommandTests.TestARightClickOnACommandSetsContextCommand;
var
  a: TProbeWindow;
  c: TTyToolWindowCommand;
  menu: TPopupMenu;
  handled: Boolean;
  p: TPoint;
begin
  a := NewWindow;
  NewCommand('Accounts');
  c := NewCommand('Manage');
  menu := TPopupMenu.Create(FForm);
  FBar.PopupMenu := menu;
  FBar.OnContextPopup := @CountContextPopup;
  FBar.OnCommandClick := @HandleCommandClick;
  p := FBar.CommandRect(1).CenterPoint;
  handled := False;
  FBar.CallDoContextPopup(p, handled);
  AssertSame('命令项上:ContextCommand 是那一项', c, FBar.ContextCommand);
  AssertTrue('ContextWindow 是 nil', FBar.ContextWindow = nil);
  AssertEquals('照常发 OnContextPopup', 1, FContextPopups);
  AssertSame('栏的菜单照常弹', menu, FBar.CallGetPopupMenu);
  AssertEquals('右键不是点击', 0, FCmdClicks);
  { 落在窗口图标上:换成 ContextWindow。 }
  p := FBar.StripItemRect(0).CenterPoint;
  FBar.CallDoContextPopup(p, handled);
  AssertTrue('图标上:ContextCommand 清掉', FBar.ContextCommand = nil);
  AssertSame('图标上:ContextWindow 是那个窗口', a, FBar.ContextWindow);
  FBar.CallGetPopupMenu;
  { 内容区(子控件冒上来的):两个都是 nil。 }
  p := FBar.CommandRect(1).CenterPoint;
  FBar.CallDoContextPopup(p, handled);
  AssertTrue('前提:又记上了', FBar.ContextCommand = c);
  FBar.CallGetPopupMenu;
  FBar.CallDoContextPopup(FBar.BarLayout.Content.CenterPoint, handled);
  AssertTrue('内容区:ContextCommand 清掉', FBar.ContextCommand = nil);
end;

procedure TTyToolWindowCommandTests.TestTheHintIsTheHintThenTheCaption;
var
  c: TTyToolWindowCommand;
  r, hr: TRect;
  txt: string;
begin
  NewWindow;
  c := NewCommand('Manage');
  c.Hint := 'Manage settings';
  r := FBar.CommandRect(0);
  AssertTrue('命令项上有提示', FBar.StripHintAt(r.CenterPoint.X, r.CenterPoint.Y, txt, hr));
  AssertEquals('文字是 Hint', 'Manage settings', txt);
  AssertTrue('矩形是那一格', EqualRect(r, hr));
  AssertEquals('HintText 同一个答案', 'Manage settings', c.HintText);
  c.Hint := '';
  AssertTrue('Hint 空了照样有', FBar.StripHintAt(r.CenterPoint.X, r.CenterPoint.Y, txt, hr));
  AssertEquals('文字换成 Caption', 'Manage', txt);
  AssertFalse('命令项上面的空白没有', FBar.StripHintAt(r.CenterPoint.X, r.Top - 5, txt, hr));
end;

{ --- 图标 ---------------------------------------------------------------------- }

procedure TTyToolWindowCommandTests.TestTheImageNameIsTheDurableKey;
var
  c, early: TTyToolWindowCommand;
  list: TTyLucideImageList;
  bmp: TBitmap;
begin
  FCtl.StyleOverride := StripTheme;
  NewWindow;
  { 栏还没有列表时按序号设的:挂着,列表来了换成名字。 }
  early := NewCommand('Early');
  early.ImageIndex := 0;
  AssertEquals('没有列表:名字还是空的', '', early.ImageName);
  list := NewHouseList;
  FBar.Images := list;
  AssertEquals('列表来了:挂起的序号换成名字', 'house', early.ImageName);
  c := NewCommand('Manage');
  AssertEquals('默认没有图标', -1, c.ImageIndex);
  c.ImageIndex := 0;
  AssertEquals('按序号设:记成那一格的名字', 'house', c.ImageName);
  AssertEquals('读回来是那一格', 0, c.ImageIndex);
  bmp := RenderCell(FBar.CommandRect(1));
  try
    AssertTrue('画出来了', CountInk(bmp, Ground, RestInk) > 0);
  finally
    bmp.Free;
  end;
  c.ImageName := 'no-such-icon';
  AssertEquals('名字找不到:要画的是 -1', -1, c.ResolvedImageIndex);
  bmp := RenderCell(FBar.CommandRect(1));
  try
    AssertEquals('找不到就不画,不回落到序号', 0, CountInk(bmp, Ground, RestInk));
  finally
    bmp.Free;
  end;
  c.ImageName := 'house';
  AssertEquals('名字对上了', 0, c.ResolvedImageIndex);
  c.ImageIndex := -1;
  AssertEquals('写 -1 = 清掉图标', '', c.ImageName);
end;

{ --- 其余 ---------------------------------------------------------------------- }

procedure TTyToolWindowCommandTests.TestVisibleCommandsKeepABarWithoutWindowsOnScreen;
var
  c: TTyToolWindowCommand;
  w: TProbeWindow;
begin
  AssertTrue('前提:没有窗口的侧栏整条隐藏', FBar.HiddenAsEmpty);
  AssertEquals('前提:宽 0', 0, FBar.Width);
  c := NewCommand('Manage');
  AssertFalse('有看得见的命令项:不算空', FBar.HiddenAsEmpty);
  AssertEquals('留着图标条', StripPx, FBar.Width);
  AssertFalse('命令项排上了', Empty(FBar.CommandRect(0)));
  c.Visible := False;
  AssertTrue('藏起来的不算', FBar.HiddenAsEmpty);
  AssertEquals('宽回到 0', 0, FBar.Width);
  c.Visible := True;
  AssertEquals('再显示:图标条回来', StripPx, FBar.Width);
  { 窗口来了又走:栏展开、再回到只剩图标条。 }
  w := NewWindow;
  AssertTrue('前提:有窗口时展开', FBar.Width > StripPx);
  w.Free;
  AssertFalse('窗口走了:还是不算空', FBar.HiddenAsEmpty);
  AssertEquals('只剩图标条', StripPx, FBar.Width);
  FBar.Commands.Clear;
  AssertTrue('命令项也清了:整条隐藏', FBar.HiddenAsEmpty);
  AssertEquals('宽 0', 0, FBar.Width);
end;

procedure TTyToolWindowCommandTests.TestDesignTimeDrawsCommandsButNeverClicksThem;
var
  d: TBarAccess;
  r: TRect;
  p: TPoint;
begin
  d := NewDesignBar;
  NewWindowIn(d, FDesignOwner);
  NewCommand('Manage', d);
  d.OnCommandClick := @HandleCommandClick;
  r := d.CommandRect(0);
  AssertFalse('设计期也排上条', Empty(r));
  p := r.CenterPoint;
  AssertEquals('设计器的命中:命令项上答 0(点它是选中栏)', 0, d.DesignHitTest(p.X, p.Y, 0));
  d.CallMouseDown(p.X, p.Y);
  d.CallMouseUp(p.X, p.Y);
  AssertEquals('设计期点了不发事件', 0, FCmdClicks);
  d.Commands[0].Click;
  AssertEquals('设计期调 Click 也不发', 0, FCmdClicks);
end;

procedure TTyToolWindowCommandTests.TestThePublishedDefaultsAreTheConstructedValues;
var
  c: TTyToolWindowCommand;

  procedure CheckDefault(const AProp: string; AConstructed: Int64);
  var
    pi: PPropInfo;
  begin
    pi := GetPropInfo(c, AProp);
    AssertNotNull(AProp + ' 是 published', pi);
    AssertEquals(AProp + ' 的 default 等于构造出来的值', AConstructed, Int64(pi^.Default));
    AssertEquals(AProp + ' 构造出来的值', AConstructed, GetOrdProp(c, pi));
  end;

begin
  AssertEquals('空集合不进 .lfm', False, IsStoredProp(FBar, GetPropInfo(FBar, 'Commands')));
  c := FBar.Commands.Add;
  AssertEquals('有命令项才进', True, IsStoredProp(FBar, GetPropInfo(FBar, 'Commands')));
  CheckDefault('Enabled', 1);
  CheckDefault('Visible', 1);
  CheckDefault('ImageIndex', -1);
  CheckDefault('Tag', 0);
  AssertEquals('TabStop 照旧默认关', False, FBar.TabStop);
end;

procedure TTyToolWindowCommandTests.TestAssigningTheCollectionCopiesTheCommands;
var
  other: TBarAccess;
  c: TTyToolWindowCommand;
  menu: TPopupMenu;
begin
  NewWindow;
  menu := TPopupMenu.Create(nil);
  try
    c := NewCommand('Manage');
    c.Hint := 'Settings';
    c.ImageName := 'settings';
    c.Enabled := False;
    c.Tag := 7;
    c.DropDownMenu := menu;
    NewCommand('Hidden').Visible := False;
    other := TBarAccess.Create(FForm);
    other.Parent := FForm;
    other.Controller := FCtl;
    other.Commands := FBar.Commands;
    AssertEquals('两项都过去了', 2, other.Commands.Count);
    AssertEquals('Caption', 'Manage', other.Commands[0].Caption);
    AssertEquals('Hint', 'Settings', other.Commands[0].Hint);
    AssertEquals('ImageName', 'settings', other.Commands[0].ImageName);
    AssertFalse('Enabled', other.Commands[0].Enabled);
    AssertEquals('Tag', 7, other.Commands[0].Tag);
    AssertSame('菜单引用', menu, other.Commands[0].DropDownMenu);
    AssertFalse('Visible', other.Commands[1].Visible);
    AssertSame('拷过去的项属于那条栏', other, other.Commands[0].Bar);
    AssertFalse('看得见的命令项:那条栏也不算空', other.HiddenAsEmpty);
  finally
    menu.Free;
  end;
  AssertTrue('菜单释放:拷过去的那一份也清掉', other.Commands[0].DropDownMenu = nil);
  AssertTrue('原来的那一份也清掉', FBar.Commands[0].DropDownMenu = nil);
end;

initialization
  RegisterTest(TTyToolWindowCommandTests);
end.
