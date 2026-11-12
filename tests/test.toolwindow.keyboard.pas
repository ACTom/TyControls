unit test.toolwindow.keyboard;
{$mode objfpc}{$H+}

{ 用键盘操作侧栏的图标条:落点、走的顺序(窗口图标 → 溢出按钮 → 命令项)、Home / End、
  Enter / 空格 = 点一下、菜单键 / Shift+F10 = 在焦点项上右键、焦点指示的像素。
  无头没有焦点:探针的 FakeFocus 顶替「栏拿着焦点」,键直接喂给真实的 KeyDown / KeyUp。
  需要真句柄的那一半(点击拿不拿焦点、Tab 落不落得上、方向键不把焦点漏给兄弟)在
  test.toolwindow.focus。 }

interface

uses
  Classes, SysUtils, Types, TypInfo, Controls, Forms, Graphics, Menus, LCLType, LMessages,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.BuiltinThemes,
  tyControls.ToolWindows, tyControls.ToolWindows.Layout,
  tyControls.Icons.Lucide, test.toolwindow.window, test.toolwindow.bar,
  test.toolwindow.commands;

type
  TTyToolWindowKeyboardTests = class(TTyToolWindowCommandFixture)
  private
    FEatKeys: Boolean;
    procedure EatKey(Sender: TObject; var Key: Word; Shift: TShiftState);
    { 栏拿到焦点(FakeFocus + 真实的 DoEnter)。 }
    procedure Focus;
    { 焦点项的名字:'w序号'(窗口序号)、'ovf'、'c序号'(集合序号)、'-'。 }
    function StopName(const AStop: TTyToolWindowStripStop): string;
    function Here: string;
    function WindowStop(AWindow: TTyCustomToolWindow): TTyToolWindowStripStop;
    function CommandStop(ACommand: TTyToolWindowCommand): TTyToolWindowStripStop;
    function OverflowStop: TTyToolWindowStripStop;
    { 当前页序号 / 收起 / OnChange、OnCollapse、OnExpand 各几次 / 命令点击几次:
      「键盘激活 = 点一下」比的就是这一串。 }
    function Outcome: string;
    function Render(const ACell: TRect): TBitmap;
    function DiffPixels(A, B: TBitmap): Integer;
  published
    procedure TestTabStopStaysOffAndABarWithNothingOnItHasNoStops;
    procedure TestEnteringLandsOnTheActiveIconElseTheFirstStop;
    procedure TestTheWalkGoesIconsThenOverflowThenCommandsAndStopsAtTheEnds;
    procedure TestDisabledAndHiddenItemsAreSkipped;
    procedure TestHomeAndEndGoToTheEnds;
    procedure TestEnterAndSpaceDoWhatAClickOnTheIconDoes;
    procedure TestAHeldKeyActivatesOnceOnRelease;
    procedure TestEnterOnACommandIsAClickOnIt;
    procedure TestEnterOnTheOverflowButtonOpensItsMenu;
    procedure TestTheMenuKeyIsARightClickOnTheFocusedItem;
    procedure TestKeysTheStripDoesNotUsePassThrough;
    procedure TestTheUsersOnKeyDownComesFirst;
    procedure TestTheFocusedItemPaintsItsFocusRingOnlyWhileTheBarHasTheFocus;
    procedure TestTheFocusRingShowsInABuiltinSkinToo;
    procedure TestAPressMovesTheKeyboardItemToThePressedOne;
    procedure TestLeavingWhileAKeyIsHeldDropsIt;
    procedure TestAStopThatGoesAwayFallsBackToTheDefault;
    procedure TestFocusStopAndActivateStopRejectWhatIsNotAStop;
  end;

implementation

const
  ItemPx = TyToolWindowStripItemSizeDef;
  Cyan = TColor($FFFF00);   { CSS #00FFFF }
  FocusTheme = ':root { --toolwindow-strip-bg: #FF00FF; --focus-ring: #00FFFF; }';

function Empty(const ARect: TRect): Boolean;
begin
  Result := (ARect.Right <= ARect.Left) or (ARect.Bottom <= ARect.Top);
end;

procedure TTyToolWindowKeyboardTests.EatKey(Sender: TObject; var Key: Word; Shift: TShiftState);
begin
  if FEatKeys then Key := 0;
end;

procedure TTyToolWindowKeyboardTests.Focus;
begin
  FBar.FakeFocus := True;
  FBar.CallDoEnter;
end;

function TTyToolWindowKeyboardTests.StopName(const AStop: TTyToolWindowStripStop): string;
begin
  case AStop.Kind of
    twskWindow: Result := 'w' + IntToStr(FBar.IndexOfWindow(AStop.Window));
    twskOverflow: Result := 'ovf';
    twskCommand: Result := 'c' + IntToStr(AStop.Command.Index);
  else
    Result := '-';
  end;
end;

function TTyToolWindowKeyboardTests.Here: string;
begin
  Result := StopName(FBar.FocusedStop);
end;

function TTyToolWindowKeyboardTests.WindowStop(AWindow: TTyCustomToolWindow): TTyToolWindowStripStop;
begin
  Result := Default(TTyToolWindowStripStop);
  Result.Kind := twskWindow;
  Result.Window := AWindow;
end;

function TTyToolWindowKeyboardTests.CommandStop(ACommand: TTyToolWindowCommand): TTyToolWindowStripStop;
begin
  Result := Default(TTyToolWindowStripStop);
  Result.Kind := twskCommand;
  Result.Command := ACommand;
end;

function TTyToolWindowKeyboardTests.OverflowStop: TTyToolWindowStripStop;
begin
  Result := Default(TTyToolWindowStripStop);
  Result.Kind := twskOverflow;
end;

function TTyToolWindowKeyboardTests.Outcome: string;
begin
  Result := Format('active=%d collapsed=%d change=%d collapse=%d expand=%d cmd=%d',
    [FBar.ActiveIndex, Ord(FBar.Collapsed), FChanges, FCollapses, FExpands, FCmdClicks]);
end;

function TTyToolWindowKeyboardTests.Render(const ACell: TRect): TBitmap;
begin
  AssertFalse('前提:要画的那一格不是空的', Empty(ACell));
  Result := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, ACell, Wipe);
end;

function TTyToolWindowKeyboardTests.DiffPixels(A, B: TBitmap): Integer;
var
  ra, rb: TBGRABitmap;
  pa, pb: TBGRAPixel;
  x, y: Integer;
begin
  Result := 0;
  AssertTrue('前提:两张图一样大', (A.Width = B.Width) and (A.Height = B.Height));
  ra := TBGRABitmap.Create(A);
  rb := TBGRABitmap.Create(B);
  try
    for y := 0 to A.Height - 1 do
      for x := 0 to A.Width - 1 do
      begin
        pa := ra.GetPixel(x, y);
        pb := rb.GetPixel(x, y);
        if (pa.red <> pb.red) or (pa.green <> pb.green) or (pa.blue <> pb.blue) then Inc(Result);
      end;
  finally
    ra.Free;
    rb.Free;
  end;
end;

{ --- 焦点与落点 ---------------------------------------------------------------- }

procedure TTyToolWindowKeyboardTests.TestTabStopStaysOffAndABarWithNothingOnItHasNoStops;
var
  pi: PPropInfo;
  c: TTyToolWindowCommand;
  w: TProbeWindow;
begin
  { 已有的窗体不变:默认不是 Tab 停靠点,published 的 default 也照旧。 }
  AssertFalse('构造出来 TabStop 是关的', FBar.TabStop);
  pi := GetPropInfo(FBar, 'TabStop');
  AssertNotNull('TabStop 是 published', pi);
  AssertEquals('声明的 default 也是 False', 0, pi^.Default);
  { 没有东西可停的条一站都没有(什么键都不吃)。CanFocus 不跟着收窄:收起时交焦点要拿栏在
    Tab 顺序表里当起点,而那张表只收 CanFocus 的控件。 }
  AssertTrue('前提:没有窗口、没有命令项,整条隐藏', FBar.HiddenAsEmpty);
  AssertEquals('隐藏的空栏没有站', 0, Length(FBar.StripStops));
  AssertTrue('栏在 Tab 顺序表里的资格不变', FBar.CanFocus);
  c := NewCommand('Manage');
  AssertEquals('一个能用的命令项就是一站', 1, Length(FBar.StripStops));
  c.Enabled := False;
  AssertEquals('禁用的命令项不是站', 0, Length(FBar.StripStops));
  w := NewWindow;
  AssertEquals('窗口图标是一站', 1, Length(FBar.StripStops));
  w.Free;
  c.Enabled := True;
  FBar.Placement := twpBottom;
  NewWindow;
  AssertEquals('底栏没有图标条:没有站', 0, Length(FBar.StripStops));
  AssertTrue('底栏的焦点项是「没有」', FBar.FocusedStop.Kind = twskNone);
end;

procedure TTyToolWindowKeyboardTests.TestEnteringLandsOnTheActiveIconElseTheFirstStop;
var
  b: TProbeWindow;
  c0: TTyToolWindowCommand;
begin
  NewWindow;
  b := NewWindow;
  NewWindow;
  c0 := NewCommand('Accounts');
  NewCommand('Manage');
  FBar.ActiveWindow := b;
  Focus;
  AssertEquals('落在当前页的图标上', 'w1', Here);
  FBar.Tap(VK_DOWN);
  AssertEquals('前提:挪开了', 'w2', Here);
  FBar.CallDoExit;
  FBar.CallDoEnter;
  AssertEquals('再进来还是当前页的图标,不是上次停的那一格', 'w1', Here);
  FBar.Collapsed := True;
  FBar.CallDoExit;
  FBar.CallDoEnter;
  AssertEquals('收起着也落在当前页的图标上', 'w1', Here);
  { 没有窗口:第一个能停的。 }
  while FBar.WindowCount > 0 do FBar.Windows[0].Free;
  c0.Enabled := False;
  FBar.CallDoExit;
  FBar.CallDoEnter;
  AssertEquals('没有窗口:第一个可用的命令项', 'c1', Here);
end;

procedure TTyToolWindowKeyboardTests.TestTheWalkGoesIconsThenOverflowThenCommandsAndStopsAtTheEnds;
var
  stops: TTyToolWindowStripStops;
  i: Integer;
  seq: string;
begin
  for i := 0 to 4 do NewWindow;            { 最后一个是当前页 }
  NewCommand('Accounts');
  NewCommand('Manage');
  { 五格高:窗口图标两格(第一个和当前页)加溢出按钮,命令项两格。 }
  FBar.Height := 5 * ItemPx;
  AssertFalse('前提:有溢出按钮', Empty(FBar.BarLayout.Overflow));
  stops := FBar.StripStops;
  seq := '';
  for i := 0 to High(stops) do seq := seq + StopName(stops[i]) + ' ';
  AssertEquals('顺序:窗口图标、溢出按钮、命令项', 'w0 w4 ovf c0 c1 ', seq);
  Focus;
  AssertEquals('从当前页的图标起', 'w4', Here);
  AssertTrue('Up 被吃掉', FBar.Tap(VK_UP));
  AssertEquals('Up:上一个图标', 'w0', Here);
  AssertTrue('到头了 Up 照样吃掉(不许漏给窗体去挪焦点)', FBar.Tap(VK_UP));
  AssertEquals('到头不绕回去', 'w0', Here);
  seq := '';
  for i := 1 to 5 do
  begin
    AssertTrue('Down 被吃掉', FBar.Tap(VK_DOWN));
    seq := seq + Here + ' ';
  end;
  AssertEquals('Down 一路走到条尾,到头停住', 'w4 ovf c0 c1 c1 ', seq);
  seq := '';
  for i := 1 to 4 do
  begin
    FBar.Tap(VK_UP);
    seq := seq + Here + ' ';
  end;
  AssertEquals('Up 原路回去', 'c0 ovf w4 w0 ', seq);
end;

procedure TTyToolWindowKeyboardTests.TestDisabledAndHiddenItemsAreSkipped;
var
  a, b, c: TProbeWindow;
  c0, c1: TTyToolWindowCommand;
begin
  a := NewWindow;
  b := NewWindow;
  c := NewWindow;
  FBar.ActiveWindow := a;
  c0 := NewCommand('Disabled');
  c1 := NewCommand('Hidden');
  NewCommand('Manage');
  b.Enabled := False;
  c0.Enabled := False;
  c1.Visible := False;
  Focus;
  AssertEquals('前提:从当前页起', 'w0', Here);
  FBar.Tap(VK_DOWN);
  AssertEquals('禁用的窗口跳过', 'w2', Here);
  FBar.Tap(VK_DOWN);
  AssertEquals('禁用的、藏起来的命令项跳过', 'c2', Here);
  FBar.Tap(VK_UP);
  AssertEquals('往回同样跳过', 'w2', Here);
  { 禁用的当前页照样是一站:点它收起 / 展开是栏的动作。 }
  FBar.Tap(VK_UP);
  a.Enabled := False;
  AssertEquals('禁用的当前页还停得住', 'w0', Here);
  { 停着的那一站被禁用了:回到默认的落点。 }
  FBar.Tap(VK_DOWN);
  AssertEquals('前提:停在第三个窗口上', 'w2', Here);
  c.Enabled := False;
  AssertEquals('它被禁用了:回到当前页的图标', 'w0', Here);
end;

procedure TTyToolWindowKeyboardTests.TestHomeAndEndGoToTheEnds;
var
  b: TProbeWindow;
begin
  NewWindow;
  b := NewWindow;
  NewWindow;
  NewCommand('Accounts');
  NewCommand('Manage').Enabled := False;
  FBar.ActiveWindow := b;
  Focus;
  AssertTrue('End 被吃掉', FBar.Tap(VK_END));
  AssertEquals('End:最后一个能停的(禁用的那一项不算)', 'c0', Here);
  AssertTrue('Home 被吃掉', FBar.Tap(VK_HOME));
  AssertEquals('Home:第一个图标', 'w0', Here);
end;

{ --- 激活 ---------------------------------------------------------------------- }

procedure TTyToolWindowKeyboardTests.TestEnterAndSpaceDoWhatAClickOnTheIconDoes;
var
  a, b: TProbeWindow;
  byMouse, byKeys: array[0..2] of string;
  start: string;

  procedure Arrange;
  begin
    FBar.Collapsed := False;
    FBar.ActiveWindow := a;
    ResetCounts;
    FBar.Clock := FBar.Clock + 1000;
  end;

begin
  a := NewWindow;
  b := NewWindow;
  FBar.OnChange := @HandleChange;
  FBar.OnCollapse := @HandleCollapse;
  FBar.OnExpand := @HandleExpand;
  FBar.FakeClock := True;
  FBar.Clock := 5000;
  { 鼠标:点另一页的图标(切过去)、再点它(收起)、收起着点第一页的图标(切过去并展开)。 }
  Arrange;
  start := Outcome;
  ClickIcon(1);
  byMouse[0] := Outcome;
  FBar.Clock := FBar.Clock + 1000;
  ClickIcon(1);
  byMouse[1] := Outcome;
  FBar.Clock := FBar.Clock + 1000;
  ClickIcon(0);
  byMouse[2] := Outcome;
  AssertTrue('前提:三步各自都改了点什么',
    (byMouse[0] <> start) and (byMouse[1] <> byMouse[0]) and (byMouse[2] <> byMouse[1]));
  AssertSame('前提:鼠标那一遍最后停在第一页', a, FBar.ActiveWindow);
  { 键盘:同样的三步,Enter、空格、Enter。 }
  Arrange;
  AssertEquals('前提:回到同一个起点', start, Outcome);
  Focus;
  AssertTrue('前提:焦点挪得到另一页的图标', FBar.FocusStop(WindowStop(b)));
  AssertTrue('Enter 被吃掉', FBar.Tap(VK_RETURN));
  byKeys[0] := Outcome;
  FBar.Clock := FBar.Clock + 1000;
  AssertTrue('空格被吃掉', FBar.Tap(VK_SPACE));
  byKeys[1] := Outcome;
  FBar.Clock := FBar.Clock + 1000;
  FBar.FocusStop(WindowStop(a));
  FBar.Tap(VK_RETURN);
  byKeys[2] := Outcome;
  AssertEquals('Enter 在另一页的图标上 = 点它', byMouse[0], byKeys[0]);
  AssertEquals('空格在当前页的图标上 = 点它', byMouse[1], byKeys[1]);
  AssertEquals('收起着 Enter 在别的图标上 = 点它', byMouse[2], byKeys[2]);
  AssertEquals('激活之后焦点项还是那个图标', 'w0', Here);
end;

procedure TTyToolWindowKeyboardTests.TestAHeldKeyActivatesOnceOnRelease;
var
  c: TTyToolWindowCommand;
begin
  NewWindow;
  c := NewCommand('Manage');
  FBar.OnCommandClick := @HandleCommandClick;
  Focus;
  FBar.FocusStop(CommandStop(c));
  AssertTrue('按下被吃掉', FBar.CallKeyDown(VK_RETURN));
  AssertEquals('按下不激活', 0, FCmdClicks);
  FBar.CallKeyDown(VK_RETURN);
  FBar.CallKeyDown(VK_RETURN);
  AssertEquals('按住不放(自动重复)也不激活', 0, FCmdClicks);
  AssertTrue('松开被吃掉', FBar.CallKeyUp(VK_RETURN));
  AssertEquals('松开才激活,只一次', 1, FCmdClicks);
  AssertFalse('没按下过的松开不归它管', FBar.CallKeyUp(VK_RETURN));
  AssertEquals('也不激活', 1, FCmdClicks);
  { 按下的是一个键、松开的是另一个:不算。 }
  FBar.CallKeyDown(VK_SPACE);
  FBar.CallKeyUp(VK_RETURN);
  AssertEquals('松开的不是按下的那个键:不激活', 1, FCmdClicks);
  FBar.CallKeyUp(VK_SPACE);
  AssertEquals('按下的那个键松开才算', 2, FCmdClicks);
end;

procedure TTyToolWindowKeyboardTests.TestEnterOnACommandIsAClickOnIt;
var
  c0, c1: TTyToolWindowCommand;
  menu: TPopupMenu;
begin
  NewWindow;
  c0 := NewCommand('Accounts');
  c1 := NewCommand('Manage');
  menu := TPopupMenu.Create(FForm);
  c1.DropDownMenu := menu;
  FBar.OnCommandClick := @HandleCommandClick;
  Focus;
  FBar.FocusStop(CommandStop(c0));
  FBar.Tap(VK_RETURN);
  AssertEquals('Enter:发 OnCommandClick', 1, FCmdClicks);
  AssertSame('给的是焦点项', c0, FLastCmd);
  AssertEquals('没有菜单的不弹', 0, FBar.MenuDrops);
  FBar.Tap(VK_DOWN);
  FBar.Tap(VK_SPACE);
  AssertEquals('空格:同样发', 2, FCmdClicks);
  AssertSame('给的是下一项', c1, FLastCmd);
  AssertEquals('有菜单、没处理掉:弹它的菜单', 1, FBar.MenuDrops);
  AssertSame('弹的是这一项的', c1, FBar.LastDropped);
  FConsume := True;
  FBar.Tap(VK_RETURN);
  AssertEquals('事件照发', 3, FCmdClicks);
  AssertEquals('处理掉了:不弹', 1, FBar.MenuDrops);
end;

procedure TTyToolWindowKeyboardTests.TestEnterOnTheOverflowButtonOpensItsMenu;
var
  i: Integer;
begin
  for i := 0 to 3 do NewWindow.Caption := 'W' + IntToStr(i);
  FBar.Height := 3 * ItemPx + ItemPx div 2;
  AssertEquals('前提:两个窗口收进了溢出', 2, Length(FBar.OverflowWindows));
  Focus;
  AssertTrue('溢出按钮是一站', FBar.FocusStop(OverflowStop));
  AssertTrue('前提:还没点过,没有菜单', FBar.OverflowMenu = nil);
  FBar.Tap(VK_RETURN);
  AssertTrue('Enter:建出溢出菜单', FBar.OverflowMenu <> nil);
  AssertEquals('菜单里是收进去的那两个', 2, FBar.OverflowMenu.Items.Count);
  AssertEquals('按窗口顺序', 'W1', FBar.OverflowMenu.Items[0].Caption);
end;

procedure TTyToolWindowKeyboardTests.TestTheMenuKeyIsARightClickOnTheFocusedItem;
var
  b: TProbeWindow;
  c: TTyToolWindowCommand;
  menu: TPopupMenu;
  handled: Boolean;
  centre: TPoint;
begin
  NewWindow;
  b := NewWindow;
  c := NewCommand('Manage');
  menu := TPopupMenu.Create(FForm);
  FBar.PopupMenu := menu;
  FBar.OnContextPopup := @CountContextPopup;
  Focus;
  FBar.FocusStop(WindowStop(b));
  centre := FBar.StripItemRect(1).CenterPoint;
  AssertTrue('菜单键按下被吃掉', FBar.CallKeyDown(VK_APPS));
  AssertEquals('按下还不问', 0, FContextPopups);
  AssertTrue('松开也吃掉(不然平台再补一条右键请求)', FBar.CallKeyUp(VK_APPS));
  AssertEquals('松开:发 OnContextPopup', 1, FContextPopups);
  AssertSame('ContextWindow 是焦点项的窗口', b, FBar.ContextWindow);
  AssertTrue('ContextCommand 是 nil', FBar.ContextCommand = nil);
  AssertTrue('位置是那一格的中心(同在那里右键)',
    (FContextPos.X = centre.X) and (FContextPos.Y = centre.Y));
  AssertSame('右键不切页', b, FBar.ActiveWindow);
  { Shift+F10 在命令项上。 }
  FBar.FocusStop(CommandStop(c));
  centre := FBar.CommandRect(0).CenterPoint;
  AssertTrue('Shift+F10 被吃掉', FBar.Tap(VK_F10, [ssShift]));
  AssertEquals('同样发', 2, FContextPopups);
  AssertSame('ContextCommand 是焦点项', c, FBar.ContextCommand);
  AssertTrue('ContextWindow 是 nil', FBar.ContextWindow = nil);
  AssertTrue('位置是那一格的中心', (FContextPos.X = centre.X) and (FContextPos.Y = centre.Y));
  AssertFalse('不带 Shift 的 F10 不归它管', FBar.Tap(VK_F10));
  AssertEquals('也不问', 2, FContextPopups);
  { 平台自己发来的键盘右键请求((-1, -1))落在拿着焦点的栏上:同一条路,菜单由栏自己弹。 }
  FBar.FocusStop(WindowStop(b));
  handled := False;
  FBar.CallDoContextPopup(Point(-1, -1), handled);
  AssertEquals('同样发 OnContextPopup', 3, FContextPopups);
  AssertSame('认的是焦点项', b, FBar.ContextWindow);
  AssertTrue('处理掉了:LCL 不再在 (0, 0) 弹一次', handled);
  { 栏没拿着焦点时的 (-1, -1) 是子控件冒上来的:照旧不发、不弹,接着往上冒。 }
  FBar.FakeFocus := False;
  handled := False;
  FBar.CallDoContextPopup(Point(-1, -1), handled);
  AssertEquals('不发', 3, FContextPopups);
  AssertFalse('Handled 留 False', handled);
  AssertTrue('栏的菜单不弹', FBar.CallGetPopupMenu = nil);
end;

procedure TTyToolWindowKeyboardTests.TestKeysTheStripDoesNotUsePassThrough;
var
  bottom, design: TBarAccess;
begin
  NewWindow;
  NewWindow;
  NewCommand('Manage');
  Focus;
  FBar.Tap(VK_HOME);
  AssertFalse('Left 不归竖着的条管', FBar.Tap(VK_LEFT));
  AssertFalse('Right 也不', FBar.Tap(VK_RIGHT));
  AssertFalse('Tab 留给窗体', FBar.Tap(VK_TAB));
  AssertFalse('Esc 不管', FBar.Tap(VK_ESCAPE));
  AssertFalse('带 Ctrl 的 Down 不管', FBar.Tap(VK_DOWN, [ssCtrl]));
  AssertFalse('带 Shift 的 End 不管', FBar.Tap(VK_END, [ssShift]));
  AssertFalse('带 Alt 的 Enter 不管', FBar.Tap(VK_RETURN, [ssAlt]));
  AssertEquals('焦点项一步都没动', 'w0', Here);
  { 底栏没有图标条:什么键都不吃。 }
  bottom := TBarAccess.Create(FForm);
  bottom.Parent := FForm;
  bottom.Controller := FCtl;
  bottom.Placement := twpBottom;
  NewWindowIn(bottom, FForm);
  bottom.FakeFocus := True;
  bottom.CallDoEnter;
  AssertFalse('底栏:Down 不吃', bottom.Tap(VK_DOWN));
  AssertFalse('底栏:Enter 不吃', bottom.Tap(VK_RETURN));
  AssertFalse('底栏:菜单键不吃', bottom.Tap(VK_APPS));
  { 禁用的栏、设计期的栏:同样一个键都不吃。 }
  FBar.Enabled := False;
  AssertFalse('禁用的栏:Down 不吃', FBar.Tap(VK_DOWN));
  AssertFalse('禁用的栏:Enter 不吃', FBar.Tap(VK_RETURN));
  AssertEquals('禁用的栏:焦点项没动', 'w0', Here);
  design := NewDesignBar;
  NewWindowIn(design, FDesignOwner);
  NewWindowIn(design, FDesignOwner);
  design.FakeFocus := True;
  design.CallDoEnter;
  AssertFalse('设计期:Down 不吃', design.Tap(VK_UP));
  AssertFalse('设计期:Enter 不吃', design.Tap(VK_RETURN));
end;

procedure TTyToolWindowKeyboardTests.TestTheUsersOnKeyDownComesFirst;
begin
  NewWindow;
  NewWindow;
  FBar.OnKeyDown := @EatKey;
  Focus;
  FBar.Tap(VK_HOME);
  AssertEquals('前提:处理器不拦时照常走', 'w0', Here);
  FEatKeys := True;
  FBar.Tap(VK_DOWN);
  AssertEquals('OnKeyDown 把键吃了:内置的不动', 'w0', Here);
  FEatKeys := False;
  FBar.Tap(VK_DOWN);
  AssertEquals('不拦了又走', 'w1', Here);
end;

{ --- 焦点指示 ------------------------------------------------------------------ }

procedure TTyToolWindowKeyboardTests.TestTheFocusedItemPaintsItsFocusRingOnlyWhileTheBarHasTheFocus;
var
  i: Integer;
  c: TTyToolWindowCommand;

  function Ring(const ACell: TRect): Integer;
  var
    bmp: TBitmap;
  begin
    bmp := Render(ACell);
    try
      Result := CountExact(bmp, Cyan);
    finally
      bmp.Free;
    end;
  end;

begin
  FCtl.StyleOverride := FocusTheme;
  for i := 0 to 3 do NewWindow;            { 最后一个是当前页 }
  c := NewCommand('Manage');
  FBar.Height := 4 * ItemPx;               { 窗口三格:两个图标加溢出按钮 }
  AssertFalse('前提:有溢出按钮', Empty(FBar.BarLayout.Overflow));
  AssertEquals('没拿焦点:哪一格都没有焦点环', 0,
    Ring(FBar.StripItemRect(0)) + Ring(FBar.StripItemRect(3)) + Ring(FBar.BarLayout.Overflow)
    + Ring(FBar.CommandRect(0)));
  Focus;
  AssertEquals('前提:焦点在当前页的图标上', 'w3', Here);
  AssertTrue('焦点项那一格画了焦点环', Ring(FBar.StripItemRect(3)) > 0);
  AssertEquals('别的图标没有', 0, Ring(FBar.StripItemRect(0)));
  AssertEquals('溢出按钮没有', 0, Ring(FBar.BarLayout.Overflow));
  AssertEquals('命令项没有', 0, Ring(FBar.CommandRect(0)));
  FBar.Tap(VK_DOWN);
  AssertEquals('前提:挪到溢出按钮', 'ovf', Here);
  AssertTrue('溢出按钮画了焦点环', Ring(FBar.BarLayout.Overflow) > 0);
  AssertEquals('原来那一格的环收掉了', 0, Ring(FBar.StripItemRect(3)));
  FBar.Tap(VK_DOWN);
  AssertEquals('前提:挪到命令项', 'c0', Here);
  AssertTrue('命令项画了焦点环', Ring(FBar.CommandRect(0)) > 0);
  AssertEquals('溢出按钮的环收掉了', 0, Ring(FBar.BarLayout.Overflow));
  { 焦点离开栏:焦点项还记着,环不画。 }
  FBar.FakeFocus := False;
  FBar.CallDoExit;
  AssertEquals('栏没有焦点:不画焦点环', 0, Ring(FBar.CommandRect(0)));
  AssertSame('前提:焦点项没变', c, FBar.FocusedStop.Command);
end;

procedure TTyToolWindowKeyboardTests.TestTheFocusRingShowsInABuiltinSkinToo;
var
  plain, focused: TBitmap;
  names: TStringArray;
  i, tested: Integer;
begin
  { 不钉颜色:换成内置皮肤(亮、暗各一遍),焦点项那一格和没焦点时画得不一样,别的格一样。 }
  TyRegisterBuiltinThemes;
  NewWindow;
  NewWindow;
  NewCommand('Manage');
  names := TyBuiltinThemeNames;
  tested := 0;
  for i := 0 to High(names) do
  begin
    if (names[i] <> 'fluent') and (names[i] <> 'win10') then Continue;
    Inc(tested);
    FCtl.ThemeName := names[i];
    if names[i] = 'fluent' then FCtl.Mode := 'dark' else FCtl.Mode := 'light';
    FBar.FakeFocus := False;
    plain := Render(FBar.StripItemRect(1));
    try
      Focus;
      AssertEquals('前提:焦点在当前页的图标上', 'w1', Here);
      focused := Render(FBar.StripItemRect(1));
      try
        AssertTrue(names[i] + ':焦点项那一格看得出焦点', DiffPixels(plain, focused) > 0);
      finally
        focused.Free;
      end;
    finally
      plain.Free;
    end;
    plain := Render(FBar.CommandRect(0));
    try
      FBar.FakeFocus := False;
      focused := Render(FBar.CommandRect(0));
      try
        AssertEquals(names[i] + ':没停在上面的格子不受影响', 0, DiffPixels(plain, focused));
      finally
        focused.Free;
      end;
    finally
      plain.Free;
    end;
    FBar.CallDoExit;
  end;
  AssertEquals('前提:两个皮肤都查到了', 2, tested);
end;

{ --- 其余 ---------------------------------------------------------------------- }

procedure TTyToolWindowKeyboardTests.TestAPressMovesTheKeyboardItemToThePressedOne;
var
  c0, c1: TTyToolWindowCommand;
  p: TPoint;
begin
  NewWindow;
  NewWindow;
  c0 := NewCommand('Accounts');
  c1 := NewCommand('Manage');
  c1.Enabled := False;
  Focus;
  AssertEquals('前提:在当前页的图标上', 'w1', Here);
  p := FBar.CommandRect(0).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  AssertEquals('按在命令项上:焦点项跟过去', 'c0', Here);
  FBar.CallMouseUp(p.X, p.Y);
  p := FBar.CommandRect(1).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseUp(p.X, p.Y);
  AssertEquals('按在禁用的命令项上:不动', 'c0', Here);
  p := FBar.StripItemRect(0).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  AssertEquals('按在窗口图标上:跟过去', 'w0', Here);
  FBar.CallMouseUp(p.X, p.Y);
  AssertSame('前提:c0 没被这些按下点到', c0, FBar.Commands[0]);
end;

procedure TTyToolWindowKeyboardTests.TestLeavingWhileAKeyIsHeldDropsIt;
var
  c: TTyToolWindowCommand;
begin
  NewWindow;
  c := NewCommand('Manage');
  FBar.OnCommandClick := @HandleCommandClick;
  Focus;
  FBar.FocusStop(CommandStop(c));
  FBar.CallKeyDown(VK_RETURN);
  FBar.CallDoExit;
  FBar.CallDoEnter;
  FBar.FocusStop(CommandStop(c));
  AssertFalse('焦点走过一趟:那一下按下作废,松开不归它管', FBar.CallKeyUp(VK_RETURN));
  AssertEquals('不激活', 0, FCmdClicks);
  { 按下之后焦点项挪走了:松开也不激活(激活的得是按下时的那一项)。 }
  FBar.CallKeyDown(VK_RETURN);
  FBar.FocusStop(WindowStop(FBar.Windows[0]));
  FBar.CallKeyUp(VK_RETURN);
  AssertEquals('焦点项换了:不激活', 0, FCmdClicks);
  AssertFalse('也没有去点窗口图标', FBar.Collapsed);
end;

procedure TTyToolWindowKeyboardTests.TestAStopThatGoesAwayFallsBackToTheDefault;
var
  a, b: TProbeWindow;
  c: TTyToolWindowCommand;
begin
  a := NewWindow;
  b := NewWindow;
  c := NewCommand('Manage');
  FBar.ActiveWindow := a;
  Focus;
  FBar.FocusStop(CommandStop(c));
  AssertEquals('前提:在命令项上', 'c0', Here);
  c.Free;
  AssertEquals('它被删了:回到当前页的图标', 'w0', Here);
  { 紧接着新建的一项多半落在刚释放的那块内存上:记着的焦点项要是没清,焦点就落在它身上了。 }
  c := NewCommand('Reborn');
  AssertEquals('新建的一项不继承走掉那一项的焦点', 'w0', Here);
  c.Free;
  FBar.FocusStop(WindowStop(b));
  AssertEquals('前提:在第二个窗口上', 'w1', Here);
  b.Free;
  AssertEquals('窗口走了:回到当前页的图标', 'w0', Here);
  { 同上:新建的窗口多半落在刚释放的那块内存上。它一进来是当前页,把当前页换回第一个再看。 }
  b := NewWindow;
  FBar.ActiveWindow := a;
  AssertEquals('新建的窗口不继承走掉那个窗口的焦点', 'w0', Here);
  b.Free;
  a.Free;
  AssertEquals('一站都没有了', '-', Here);
  AssertFalse('没有站:Down 不吃', FBar.Tap(VK_DOWN));
end;

procedure TTyToolWindowKeyboardTests.TestFocusStopAndActivateStopRejectWhatIsNotAStop;
var
  a, b: TProbeWindow;
  c: TTyToolWindowCommand;
  other: TBarAccess;
  stranger: TProbeWindow;
begin
  a := NewWindow;
  b := NewWindow;
  FBar.ActiveWindow := a;
  c := NewCommand('Manage');
  FBar.OnCommandClick := @HandleCommandClick;
  other := TBarAccess.Create(FForm);
  other.Parent := FForm;
  other.Controller := FCtl;
  stranger := NewWindowIn(other, FForm);
  Focus;
  AssertFalse('别的栏的窗口不是这条栏的站', FBar.FocusStop(WindowStop(stranger)));
  AssertFalse('没有溢出按钮时它不是站', FBar.FocusStop(OverflowStop));
  b.Enabled := False;
  AssertFalse('禁用的窗口不是站', FBar.FocusStop(WindowStop(b)));
  AssertFalse('也激活不了', FBar.ActivateStop(WindowStop(b)));
  AssertSame('当前页没动', a, FBar.ActiveWindow);
  c.Enabled := False;
  AssertFalse('禁用的命令项不是站', FBar.FocusStop(CommandStop(c)));
  AssertFalse('也激活不了', FBar.ActivateStop(CommandStop(c)));
  AssertEquals('没发事件', 0, FCmdClicks);
  AssertEquals('焦点项没动', 'w0', Here);
  c.Enabled := True;
  AssertTrue('可用的命令项激活得了(不用先聚焦)', FBar.ActivateStop(CommandStop(c)));
  AssertEquals('发了事件', 1, FCmdClicks);
  AssertEquals('激活不挪焦点项', 'w0', Here);
end;

initialization
  RegisterTest(TTyToolWindowKeyboardTests);
end.
