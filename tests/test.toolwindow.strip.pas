unit test.toolwindow.strip;
{$mode objfpc}{$H+}

{ 图标条:绘制(图标、着色、指示条、溢出、边缘区、设计期提示)与点击手势(松开切换、
  收起、防抖、多击、设计期命中、悬停、提示、溢出菜单)。夹具在 test.toolwindow.bar。 }

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
  TTyToolWindowStripTests = class(TTyToolWindowBarFixture)
  published
    procedure TestStripPaintsAndTheActiveItemDiffers;
    procedure TestTheIndicatorSitsOnTheContentSideOfTheActiveCellOnly;
    procedure TestAnUnresolvedNameDrawsNoIcon;
    procedure TestAHoveredCellPaintsItsHoverState;
    procedure TestAShortStripShowsTheOverflowAfterTheLastIcon;
    procedure TestTheEdgeFillsItsBandAndGoesAwayWhenCollapsed;
    procedure TestDesignTimeEmptyBarPaintsANote;
    procedure TestAStrayChildGetsANoteLineAtDesignTime;
    procedure TestIconSwitchesOnReleaseNotOnPress;
    procedure TestClickingTheActiveIconTogglesCollapse;
    procedure TestASecondClickWithin300msIsIgnored;
    procedure TestDoubleClickPressNeverCounts;
    procedure TestAReleaseOffTheIconIsNotAClick;
    procedure TestDesignerHitTestArmsOnPressAndHandsBackOnRelease;
    procedure TestAWindowFreedWhileArmedIsNotAClick;
    procedure TestHoverFollowsThePointerAndIsRecheckedAfterASwitch;
    procedure TestStripHintComesFromTheIconUnderThePointer;
    procedure TestAPressOnTheStripDoesNotFireTheBarsOnClick;
    procedure TestTheOverflowMenuListsTheHiddenWindowsAndActivatesOne;
    procedure TestTheStripNeverStartsAnLclDrag;
    procedure TestTheAutoDragUsesThePressPositionNotThePointer;
    procedure TestPointerInClientIsFalseWithoutAHandle;
    procedure TestTheGuardCountsFromTheLastClickThatRan;
    procedure TestACancelledDesignGestureIgnoresTheNextBareHitTest;
    procedure TestAWindowLeavingKeepsThePressedIconOnItsWindow;
    procedure TestADesignGestureFollowsItsWindowWhenAnotherLeaves;
    procedure TestTheOverflowButtonPaintsHoverAndPressedInTheStripInk;
    procedure TestTheOverflowMenuOpensTowardsTheContent;
    procedure TestShowingTheOverflowMenuSetsItsAlignment;
  end;

implementation

procedure TTyToolWindowStripTests.TestStripPaintsAndTheActiveItemDiffers;
var
  a, b: TProbeWindow;
  restPix, activePix, wipeLeft: Integer;
  bmp: TBitmap;
begin
  FCtl.StyleOverride := StripTheme;
  FBar.Images := NewHouseList;
  a := NewWindow;
  a.ImageName := 'house';
  b := NewWindow;
  b.ImageName := 'house';
  FBar.ActiveWindow := a;
  { 两个窗口,当前页是第一个。分别数图标条第 1 格和第 2 格里的非底色像素。 }
  TallyStripCell(0, Ground, Wipe, activePix, wipeLeft);
  AssertEquals('整块都画到,不许留底漆', 0, wipeLeft);
  TallyStripCell(1, Ground, Wipe, restPix, wipeLeft);
  AssertEquals('静止格也整块画到', 0, wipeLeft);
  AssertTrue('图标条画了东西', restPix > 0);
  AssertTrue('当前页那一格和静止格不一样', activePix <> restPix);
  { 像素数只说明「画了不一样多的东西」(指示条就占掉这个差)—— 图标着的是哪种墨色得看颜色。 }
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, FBar.StripItemRect(0), Wipe);
  try
    AssertTrue('当前格的图标着成 :selected 的墨色', CountInk(bmp, Ground, SelInk) > 0);
    AssertEquals('当前格里没有静止态的墨色', 0, CountInk(bmp, Ground, RestInk));
  finally
    bmp.Free;
  end;
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, FBar.StripItemRect(1), Wipe);
  try
    AssertTrue('静止格的图标着成静止态的墨色', CountInk(bmp, Ground, RestInk) > 0);
    AssertEquals('静止格里没有选中墨色', 0, CountInk(bmp, Ground, SelInk));
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowStripTests.TestTheIndicatorSitsOnTheContentSideOfTheActiveCellOnly;
var
  a: TProbeWindow;
  cell: TRect;
  bmp: TBitmap;
  w, h: Integer;

  function Cell0: TBitmap;
  begin
    cell := FBar.StripItemRect(0);
    w := cell.Right - cell.Left;
    h := cell.Bottom - cell.Top;
    Result := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, cell, Wipe);
  end;

begin
  FCtl.StyleOverride := StripTheme;
  a := NewWindow;
  NewWindow;
  FBar.ActiveWindow := a;
  bmp := Cell0;
  try
    AssertEquals('指示条 = 粗细 × 格高', TyToolWindowStripIndicatorSizeDef * h,
      CountExact(bmp, clBlack));
    AssertTrue('左栏:贴在靠内容区的那一侧(右)', PixelIs(bmp, w - 1, h div 2, clBlack));
    AssertFalse('外侧没有', PixelIs(bmp, 0, h div 2, clBlack));
  finally
    bmp.Free;
  end;
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, FBar.StripItemRect(1), Wipe);
  try
    AssertEquals('静止格没有指示条', 0, CountExact(bmp, clBlack));
  finally
    bmp.Free;
  end;
  FBar.Placement := twpRight;
  bmp := Cell0;
  try
    AssertTrue('右栏:内容区在左,指示条跟着到左', PixelIs(bmp, 0, h div 2, clBlack));
    AssertFalse('右栏的外侧(右)没有', PixelIs(bmp, w - 1, h div 2, clBlack));
  finally
    bmp.Free;
  end;
  FBar.Placement := twpLeft;
  FBar.Collapsed := True;
  bmp := Cell0;
  try
    AssertEquals('收起时当前图标不画 :selected,指示条也不画(spec §5.3)', 0,
      CountExact(bmp, clBlack));
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowStripTests.TestAnUnresolvedNameDrawsNoIcon;
var
  a, b, c: TProbeWindow;
  pix, housePix, wipeLeft: Integer;
begin
  FCtl.StyleOverride := StripTheme;
  FBar.Images := NewHouseList;
  a := NewWindow;
  a.ImageName := 'house';
  b := NewWindow;
  b.ImageIndex := 0;
  AssertEquals('前提:序号当场换成了名字', 'house', b.ImageName);
  b.ImageName := 'no-such-glyph';
  AssertEquals('前提:ImageIndex 这个视图回落到写过的序号', 0, b.ImageIndex);
  AssertEquals('前提:图标条要的那一格是 -1', -1, FBar.ResolvedImageIndex(b));
  c := NewWindow;
  c.ImageName := 'house';
  FBar.ActiveWindow := a;
  TallyStripCell(2, Ground, Wipe, housePix, wipeLeft);
  AssertTrue('对照:静止格里名字找得到就画得出图标', housePix > 0);
  { 静止格没有底色、没有指示条,非底色像素只能是图标。拿窗口的 ImageIndex 画的话,这里
    画的是那个退回来的序号 —— spec §8「找不到 → -1,不许乱画一个」。 }
  TallyStripCell(1, Ground, Wipe, pix, wipeLeft);
  AssertEquals('整块都画到', 0, wipeLeft);
  AssertEquals('名字找不到:那一格一个图标像素都没有', 0, pix);
end;

procedure TTyToolWindowStripTests.TestAHoveredCellPaintsItsHoverState;
const
  Cyan = TColor($FFFF00);   { CSS #00FFFF }
var
  a: TProbeWindow;
  cell: TRect;
  bmp: TBitmap;
begin
  FCtl.StyleOverride := ':root { --toolwindow-strip-bg: #FF00FF;' +
    ' --toolwindow-overlay-hover: #00FFFF; }';
  a := NewWindow;
  NewWindow;
  FBar.ActiveWindow := a;
  cell := FBar.StripItemRect(1);
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, cell, Wipe);
  try
    AssertEquals('前提:没悬停时没有悬停底色', 0, CountExact(bmp, Cyan));
  finally
    bmp.Free;
  end;
  FBar.SetStripHover(1);
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, cell, Wipe);
  try
    AssertEquals('悬停格整格铺 :hover 的底色',
      (cell.Right - cell.Left) * (cell.Bottom - cell.Top), CountExact(bmp, Cyan));
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowStripTests.TestAShortStripShowsTheOverflowAfterTheLastIcon;
const
  ItemPx = TyToolWindowStripItemSizeDef;
var
  i: Integer;
  L: TTyToolWindowBarLayout;
  bmp: TBitmap;
begin
  { 字形着的是图标条的墨色,不是标签行的(--toolwindow-tab-ink 属于底栏)。 }
  FCtl.StyleOverride := ':root { --toolwindow-strip-bg: #FF00FF; --toolwindow-strip-ink: #0000FF; }';
  for i := 1 to 4 do NewWindow;         { 最后一个是当前页 }
  L := FBar.BarLayout;
  AssertEquals('前提:放得下时四个都在条上', 4, Length(L.Slots));
  AssertTrue('放得下就没有溢出按钮', L.Overflow.Bottom <= L.Overflow.Top);
  FBar.Height := 3 * ItemPx + ItemPx div 2;
  L := FBar.BarLayout;
  AssertEquals('放不下:扣掉溢出按钮后只剩两格', 2, Length(L.Slots));
  AssertEquals('当前页被留在条上', 3, L.Slots[1].ItemIndex);
  AssertTrue('有溢出按钮', L.Overflow.Bottom > L.Overflow.Top);
  AssertEquals('溢出按钮紧跟在最后一个图标后面', L.Slots[1].ItemRect.Bottom, L.Overflow.Top);
  AssertEquals('跟图标一样大', ItemPx, L.Overflow.Bottom - L.Overflow.Top);
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, L.Overflow, Wipe);
  try
    AssertTrue('溢出按钮画出了它的字形', CountInk(bmp, Ground, RestInk) > 0);
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowStripTests.TestTheEdgeFillsItsBandAndGoesAwayWhenCollapsed;
const
  Navy = TColor($800000);   { CSS #000080 }
var
  L: TTyToolWindowBarLayout;
  bmp: TBitmap;
begin
  FCtl.StyleOverride := ':root { --toolwindow-edge-color: #000080; }';
  AssertTrue('运行时空栏:边缘区不起作用', IsRectEmpty(FBar.BarLayout.Edge));
  NewWindow;
  L := FBar.BarLayout;
  AssertEquals('边缘区宽 = token', EdgePx, L.Edge.Right - L.Edge.Left);
  AssertEquals('左栏的边缘区贴右边(靠编辑区)', FBar.ClientWidth, L.Edge.Right);
  bmp := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, L.Edge, Wipe);
  try
    AssertEquals('整条铺边缘区的底色', (L.Edge.Right - L.Edge.Left) * (L.Edge.Bottom - L.Edge.Top),
      CountExact(bmp, Navy));
  finally
    bmp.Free;
  end;
  FBar.Collapsed := True;
  AssertTrue('收起:边缘区不起作用,也不画', IsRectEmpty(FBar.BarLayout.Edge));
end;

procedure TTyToolWindowStripTests.TestDesignTimeEmptyBarPaintsANote;
var
  d: TBarAccess;
  L: TTyToolWindowBarLayout;
  bmp: TBitmap;
  pix, wipeLeft: Integer;
begin
  FCtl.StyleOverride := 'TyToolWindowBar { background: #FF00FF; }';
  d := NewDesignBar;
  L := d.BarLayout;
  AssertFalse('设计期空栏有提示框', IsRectEmpty(L.EmptyNote));
  bmp := RenderRegion(d, d.ClientWidth, d.ClientHeight, L.EmptyNote, Wipe);
  try
    TallyPixels(bmp, Ground, Wipe, pix, wipeLeft);
  finally
    bmp.Free;
  end;
  AssertEquals('整块都画到', 0, wipeLeft);
  AssertTrue('设计期没有窗口:画出提示文字', pix > 0);
  { 运行时同一个位置(按设计期那么大画)一个字都没有。 }
  AssertTrue('运行时没有提示框', IsRectEmpty(FBar.BarLayout.EmptyNote));
  bmp := RenderRegion(FBar, d.ClientWidth, d.ClientHeight, L.EmptyNote, Wipe);
  try
    TallyPixels(bmp, Ground, Wipe, pix, wipeLeft);
  finally
    bmp.Free;
  end;
  AssertEquals('运行时也整块画到', 0, wipeLeft);
  AssertEquals('运行时不画提示', 0, pix);
end;

procedure TTyToolWindowStripTests.TestAStrayChildGetsANoteLineAtDesignTime;
var
  d: TBarAccess;
  stray: TBodyChild;
  full, r: TRect;
  L: TTyToolWindowBarLayout;
  bmp: TBitmap;
  pix, wipeLeft: Integer;
begin
  FCtl.StyleOverride := 'TyToolWindowBar { background: #FF00FF; }';
  d := NewDesignBar;
  NewWindowIn(d, FDesignOwner);
  full := d.ClientRect;
  d.CallAdjustClientRect(full);
  AssertTrue('前提:没有漏进来的就不让提示行', IsRectEmpty(d.BarLayout.StrayNote));
  stray := TBodyChild.Create(FDesignOwner);
  d.InsertControl(stray);
  AssertTrue('设计期不藏:用户得看得见它、删得掉它', stray.Visible);
  L := d.BarLayout;
  AssertFalse('设计期让出一行提示', IsRectEmpty(L.StrayNote));
  AssertEquals('提示行贴在原来内容区的底边', full.Bottom, L.StrayNote.Bottom);
  { 不让出来的话当前页(alClient)整个盖在内容区上,提示一个像素都露不出来。 }
  r := d.ClientRect;
  d.CallAdjustClientRect(r);
  AssertEquals('窗口的内容区停在提示行上面', L.StrayNote.Top, r.Bottom);
  bmp := RenderRegion(d, d.ClientWidth, d.ClientHeight, L.StrayNote, Wipe);
  try
    TallyPixels(bmp, Ground, Wipe, pix, wipeLeft);
  finally
    bmp.Free;
  end;
  AssertEquals('整块都画到', 0, wipeLeft);
  AssertTrue('提示行里画了字', pix > 0);
  stray.Free;
  AssertTrue('它走了,提示行也走', IsRectEmpty(d.BarLayout.StrayNote));
  r := d.ClientRect;
  d.CallAdjustClientRect(r);
  AssertEquals('内容区还给窗口', full.Bottom, r.Bottom);
end;

procedure TTyToolWindowStripTests.TestIconSwitchesOnReleaseNotOnPress;
var
  a, b: TProbeWindow;
  p: TPoint;
begin
  a := NewWindow;
  b := NewWindow;
  FBar.ActiveWindow := a;
  { 两个窗口,当前页是第一个;点第二个图标。 }
  p := FBar.StripItemRect(1).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  AssertSame('按下不切', a, FBar.ActiveWindow);
  AssertEquals('按下只武装', Ord(twgsArmed), Ord(FBar.GestureStateForTest));
  FBar.CallMouseUp(p.X, p.Y);
  AssertSame('松开才切', b, FBar.ActiveWindow);
  AssertEquals('松开之后回到 Idle', Ord(twgsIdle), Ord(FBar.GestureStateForTest));
end;

procedure TTyToolWindowStripTests.TestClickingTheActiveIconTogglesCollapse;
var
  a: TProbeWindow;
begin
  a := NewWindow;
  NewWindow;
  FBar.ActiveWindow := a;
  ClickIcon(0);
  AssertTrue('点当前页的图标 → 收起', FBar.Collapsed);
  AssertSame('当前页不变', a, FBar.ActiveWindow);
  FBar.FakeClock := True;
  FBar.Clock := GetTickCount64 + TyToolWindowClickGuardMs + 1;
  ClickIcon(0);
  AssertFalse('再点一次 → 展开', FBar.Collapsed);
  AssertTrue('展开后当前页显示出来', a.Visible);
end;

procedure TTyToolWindowStripTests.TestASecondClickWithin300msIsIgnored;
var
  a, b: TProbeWindow;
begin
  a := NewWindow;
  b := NewWindow;
  FBar.ActiveWindow := a;
  ClickIcon(0);
  AssertTrue('前提:第一下收起', FBar.Collapsed);
  { 不推时钟:慢速双击(系统默认 500 ms,第二下不一定带 ssDouble)不许收起又展开。 }
  FBar.FakeClock := True;
  FBar.Clock := GetTickCount64 + TyToolWindowClickGuardMs - 50;
  ClickIcon(0);
  AssertTrue('300 ms 以内的第二下什么都不做', FBar.Collapsed);
  { 防抖按窗口记:点 A 之后马上点 B 照常生效。 }
  ClickIcon(1);
  AssertSame('别的窗口的点击不受这个窗口的防抖限制', b, FBar.ActiveWindow);
  AssertFalse('点收起栏里的另一个图标:激活并展开', FBar.Collapsed);
end;

procedure TTyToolWindowStripTests.TestDoubleClickPressNeverCounts;
var
  a: TProbeWindow;
  p: TPoint;
begin
  a := NewWindow;
  NewWindow;
  FBar.ActiveWindow := a;
  p := FBar.StripItemRect(1).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y, [ssLeft, ssDouble]);
  { 多击的按下照常武装 —— 点一下图标再马上按住拖,必须拖得起来(拖动那一半在 Task 9)。 }
  AssertEquals('多击的按下也武装', Ord(twgsArmed), Ord(FBar.GestureStateForTest));
  FBar.CallMouseUp(p.X, p.Y);
  AssertSame('松开不算点击:当前页不变', a, FBar.ActiveWindow);
  AssertFalse('也不收起', FBar.Collapsed);
  p := FBar.StripItemRect(0).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y, [ssLeft, ssTriple]);
  FBar.CallMouseUp(p.X, p.Y);
  AssertFalse('三击的按下落在当前页上也不收起', FBar.Collapsed);
end;

procedure TTyToolWindowStripTests.TestAReleaseOffTheIconIsNotAClick;
var
  a: TProbeWindow;
  p, q: TPoint;
begin
  a := NewWindow;
  NewWindow;
  FBar.ActiveWindow := a;
  p := FBar.StripItemRect(1).CenterPoint;
  q := FBar.StripItemRect(0).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseUp(q.X, q.Y);
  AssertSame('在别的图标上松开不是点击', a, FBar.ActiveWindow);
  AssertFalse('也不收起按下时不在的那一页', FBar.Collapsed);
end;

procedure TTyToolWindowStripTests.TestDesignerHitTestArmsOnPressAndHandsBackOnRelease;
var
  d: TBarAccess;
  w0, w1: TProbeWindow;
  icon, body: TPoint;
begin
  d := NewDesignBar;
  w0 := NewWindowIn(d, FDesignOwner);
  w1 := NewWindowIn(d, FDesignOwner);
  d.ActiveWindow := w0;
  icon := d.StripItemRect(1).CenterPoint;
  body := d.BarLayout.Content.CenterPoint;
  { ① 图标上按位置问 → 1;正文 → 0(设计器照常选中 / 放控件)。 }
  AssertEquals('图标上按位置答 1', 1, d.DesignHitTest(icon.X, icon.Y, 0));
  AssertEquals('正文答 0', 0, d.DesignHitTest(body.X, body.Y, 0));
  d.CallMouseDown(icon.X, icon.Y);
  AssertSame('设计期按下也不切', w0, d.ActiveWindow);
  { ② 手势中(带 MK_LBUTTON)哪里都答 1 —— 按位置答的话,选中一变排布就把手势撕开。 }
  AssertEquals('手势中正文也答 1', 1, d.DesignHitTest(body.X, body.Y, MK_LBUTTON));
  { ③ 松开那一拍答 0 交还设计器,并且在这一拍切过去(答 0 之后设计器不再调 MouseUp)。 }
  AssertEquals('松开答 0,哪怕还在图标上', 0, d.DesignHitTest(icon.X, icon.Y, 0));
  AssertSame('松开那一拍切页', w1, d.ActiveWindow);
  { ④ 解除武装:再按位置回答。 }
  AssertEquals('解除武装后正文答 0', 0, d.DesignHitTest(body.X, body.Y, 0));
  { 点当前页的图标在设计期什么都不做(收起没有撤销、也不许写进 .lfm)。 }
  icon := d.StripItemRect(1).CenterPoint;
  d.CallMouseDown(icon.X, icon.Y);
  d.DesignHitTest(icon.X, icon.Y, 0);
  AssertFalse('设计期不收起', d.Collapsed);
  AssertSame('当前页还是它', w1, d.ActiveWindow);
end;

procedure TTyToolWindowStripTests.TestAWindowFreedWhileArmedIsNotAClick;
var
  a, b: TProbeWindow;
  p: TPoint;
begin
  a := NewWindow;
  b := NewWindow;
  NewWindow;
  FBar.ActiveWindow := a;
  p := FBar.StripItemRect(1).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  AssertEquals('前提:按在 b 上武装着', Ord(twgsArmed), Ord(FBar.GestureStateForTest));
  b.Free;
  AssertEquals('武装着的窗口走了,手势记录跟着清掉(spec §5.2)', Ord(twgsIdle),
    Ord(FBar.GestureStateForTest));
  { 这时第二格上已经是 c 了 —— 在同一个位置松开不许当成点击。 }
  FBar.CallMouseUp(p.X, p.Y);
  AssertSame('当前页不变', a, FBar.ActiveWindow);
  AssertFalse('也不收起', FBar.Collapsed);
end;

procedure TTyToolWindowStripTests.TestHoverFollowsThePointerAndIsRecheckedAfterASwitch;
var
  a, b: TProbeWindow;
  p: TPoint;
begin
  a := NewWindow;
  b := NewWindow;
  FBar.ActiveWindow := a;
  p := FBar.StripItemRect(1).CenterPoint;
  FBar.CallMouseMove(p.X, p.Y, []);
  AssertEquals('指针在第二格上', 1, FBar.StripHover);
  FBar.CallMouseLeave;
  AssertEquals('离开清掉悬停', -1, FBar.StripHover);
  FBar.CallMouseMove(p.X, p.Y, []);
  { 切页之后条上排的图标可能换了位置:按指针此刻的位置重查。这里指针其实在第一格上,
    悬停还记着第二格 —— 切页必须把它对回来(spec §5.1 第 4 步)。 }
  FBar.FakePointer := True;
  FBar.FakePoint := FBar.StripItemRect(0).CenterPoint;
  FBar.ActiveWindow := b;
  AssertEquals('切页后按指针位置重查悬停', 0, FBar.StripHover);
  FBar.FakePoint := Point(-5, -5);
  FBar.ActiveWindow := a;
  AssertEquals('指针不在条上:悬停清掉', -1, FBar.StripHover);
end;

procedure TTyToolWindowStripTests.TestStripHintComesFromTheIconUnderThePointer;
var
  a, b: TProbeWindow;
  txt: string;
  r: TRect;
  p: TPoint;
  info: THintInfo;
  res: PtrInt;
begin
  a := NewWindow;
  a.Caption := 'Explorer';
  b := NewWindow;
  b.Caption := 'Search';
  b.StripHint := 'Find in files';
  p := FBar.StripItemRect(0).CenterPoint;
  AssertTrue('图标上有提示', FBar.StripHintAt(p.X, p.Y, txt, r));
  AssertEquals('StripHint 空就用 Caption', 'Explorer', txt);
  AssertTrue('提示矩形就是那一格', EqualRect(FBar.StripItemRect(0), r));
  p := FBar.StripItemRect(1).CenterPoint;
  FBar.StripHintAt(p.X, p.Y, txt, r);
  AssertEquals('有 StripHint 用 StripHint', 'Find in files', txt);
  p := FBar.BarLayout.Content.CenterPoint;
  AssertFalse('不在图标上没有', FBar.StripHintAt(p.X, p.Y, txt, r));
  { 接线:LCL 发来的 CM_HINTSHOW 走的就是这一处。 }
  info := Default(THintInfo);
  info.HintControl := FBar;
  info.HintStr := 'bar hint';
  info.CursorPos := FBar.StripItemRect(1).CenterPoint;
  res := FBar.Perform(CM_HINTSHOW, 0, PtrInt(@info));
  AssertEquals('处理器答 0 = 显示', 0, res);
  AssertEquals('HintStr 换成图标的提示', 'Find in files', info.HintStr);
  AssertTrue('CursorRect 是那一格:指针出了这一格提示就换', EqualRect(FBar.StripItemRect(1),
    info.CursorRect));
  info.HintStr := 'bar hint';
  info.CursorPos := FBar.BarLayout.Content.CenterPoint;
  FBar.Perform(CM_HINTSHOW, 0, PtrInt(@info));
  AssertEquals('不在图标上:走继承,栏自己的提示原样', 'bar hint', info.HintStr);
end;

procedure TTyToolWindowStripTests.TestAPressOnTheStripDoesNotFireTheBarsOnClick;
var
  p: TPoint;
begin
  NewWindow;
  NewWindow;
  FBar.OnClick := @HandleClick;
  FClicks := 0;
  { LCL 的次序:按下 → Click → MouseUp(control.inc:2827-2846)。 }
  p := FBar.StripItemRect(1).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallClick;
  FBar.CallMouseUp(p.X, p.Y);
  AssertEquals('按在图标上:不是「点了栏」', 0, FClicks);
  p := FBar.BarLayout.Content.CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallClick;
  FBar.CallMouseUp(p.X, p.Y);
  AssertEquals('别处照常', 1, FClicks);
end;

procedure TTyToolWindowStripTests.TestTheOverflowMenuListsTheHiddenWindowsAndActivatesOne;
var
  w: array[0..3] of TProbeWindow;
  i: Integer;
  p: TPoint;
begin
  for i := 0 to 3 do
  begin
    w[i] := NewWindow;
    w[i].Caption := 'W' + IntToStr(i);
  end;
  FBar.Height := 3 * TyToolWindowStripItemSizeDef + TyToolWindowStripItemSizeDef div 2;
  AssertEquals('前提:第二、三个收进溢出', 2, Length(FBar.OverflowWindows));
  FBar.Collapsed := True;
  p := FBar.BarLayout.Overflow.CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  AssertTrue('按下不弹', FBar.OverflowMenu = nil);
  FBar.CallMouseUp(p.X, p.Y);
  AssertTrue('松开建出菜单', FBar.OverflowMenu <> nil);
  AssertEquals('菜单里是收进去的那两个', 2, FBar.OverflowMenu.Items.Count);
  AssertEquals('按窗口顺序', 'W1', FBar.OverflowMenu.Items[0].Caption);
  FBar.OverflowMenu.Items[0].Click;
  AssertSame('菜单项激活那个窗口', w[1], FBar.ActiveWindow);
  AssertFalse('栏收起着就一并展开', FBar.Collapsed);
end;

procedure TTyToolWindowStripTests.TestTheStripNeverStartsAnLclDrag;
begin
  NewWindow;
  FBar.DragMode := dmAutomatic;
  FBar.FakePointer := True;
  { 判据是那一道闸(StartLclAutoDrag)被放行了几次 —— 探针只数、不真的起拖。 }
  FBar.FakePoint := FBar.StripItemRect(0).CenterPoint;
  FBar.CallBeginAutoDrag;
  AssertEquals('图标上不起 LCL 拖动', 0, FBar.AutoDragStarts);
  FBar.FakePoint := Point(FBar.StripItemRect(0).CenterPoint.X, FBar.StripItemRect(0).Bottom + 20);
  AssertTrue('前提:条尾的空白在图标条里、不在任何图标上',
    PtInRect(FBar.BarLayout.Strip, FBar.FakePoint) and (FBar.WindowAtPos(FBar.FakePoint.X,
    FBar.FakePoint.Y) = nil));
  FBar.CallBeginAutoDrag;
  AssertEquals('条上的空白也不起', 0, FBar.AutoDragStarts);
  FBar.FakePoint := FBar.BarLayout.Edge.CenterPoint;
  FBar.CallBeginAutoDrag;
  AssertEquals('边缘区上也不起', 0, FBar.AutoDragStarts);
  { 对照组:内容区是用户的地盘,dmAutomatic 照常生效。 }
  FBar.FakePoint := FBar.BarLayout.Content.CenterPoint;
  FBar.CallBeginAutoDrag;
  AssertEquals('内容区照常起', 1, FBar.AutoDragStarts);
end;

{ --- 自动拖动的闸、指针、防抖窗口、设计期手势、窗口离开 ------------------------------- }

procedure TTyToolWindowStripTests.TestTheAutoDragUsesThePressPositionNotThePointer;
var
  icon, body: TPoint;
begin
  NewWindow;
  FBar.DragMode := dmAutomatic;
  { 无头没有句柄,按下消息里的 MouseCapture 会去建句柄;这条只关心按下位置怎么传到
    BeginAutoDrag,捕获关掉。 }
  FBar.ControlStyle := FBar.ControlStyle - [csCaptureMouse];
  icon := FBar.StripItemRect(0).CenterPoint;
  body := FBar.BarLayout.Content.CenterPoint;
  { 快速按下就拖:按下落在图标上,LCL 调 BeginAutoDrag 那一刻指针已经到了内容区。 }
  FBar.FakePointer := True;
  FBar.FakePoint := body;
  FBar.Perform(LM_LBUTTONDOWN, MK_LBUTTON, PtrInt((icon.Y shl 16) or (icon.X and $FFFF)));
  FBar.Perform(LM_LBUTTONUP, 0, PtrInt((icon.Y shl 16) or (icon.X and $FFFF)));
  AssertEquals('按在图标上:不起 LCL 拖动,不管指针此刻在哪', 0, FBar.AutoDragStarts);
  { 反过来:按在内容区(那里用户的 dmAutomatic 该生效),指针此刻恰好在图标上。 }
  FBar.FakePoint := icon;
  FBar.Perform(LM_LBUTTONDOWN, MK_LBUTTON, PtrInt((body.Y shl 16) or (body.X and $FFFF)));
  FBar.Perform(LM_LBUTTONUP, 0, PtrInt((body.Y shl 16) or (body.X and $FFFF)));
  AssertEquals('按在内容区:照常起', 1, FBar.AutoDragStarts);
end;

procedure TTyToolWindowStripTests.TestPointerInClientIsFalseWithoutAHandle;
var
  p: TPoint;
begin
  AssertFalse('前提:无头', FBar.HandleAllocated);
  AssertFalse('没有句柄:答 False(真实实现,不是探针)', FBar.CallRealPointerInClient(p));
  AssertEquals('并给一个在哪里都不命中的点', -1, p.X);
end;

procedure TTyToolWindowStripTests.TestTheGuardCountsFromTheLastClickThatRan;
begin
  NewWindow;
  NewWindow;
  FBar.ActiveWindow := FBar.Windows[0];
  FBar.FakeClock := True;
  FBar.Clock := 10000;
  ClickIcon(0);
  AssertTrue('0 ms:收起', FBar.Collapsed);
  FBar.Clock := 10250;
  ClickIcon(0);
  AssertTrue('250 ms:防抖挡掉', FBar.Collapsed);
  FBar.Clock := 10400;
  ClickIcon(0);
  { 被挡掉的那一下不算数:从 0 ms 那一下算起已经 400 ms。 }
  AssertFalse('400 ms:执行(被挡掉的那一下不刷新时间戳)', FBar.Collapsed);
end;

procedure TTyToolWindowStripTests.TestACancelledDesignGestureIgnoresTheNextBareHitTest;
var
  bar: TBarAccess;
  a, b: TProbeWindow;
  p: TPoint;
begin
  bar := NewDesignBar;
  a := NewWindowIn(bar, FDesignOwner);
  b := NewWindowIn(bar, FDesignOwner);
  bar.ActiveWindow := a;
  p := bar.StripItemRect(1).CenterPoint;
  { 三条解除武装的路:LM_CANCELMODE、设计期离开、捕获被别人拿走。 }
  bar.CallMouseDown(p.X, p.Y);
  bar.Perform(LM_CANCELMODE, 0, 0);
  bar.DesignHitTest(p.X, p.Y, 0);
  AssertSame('LM_CANCELMODE 之后那条不带按键的命中测试不是松开:不切页', a, bar.ActiveWindow);
  bar.CallMouseDown(p.X, p.Y);
  bar.CallMouseLeave;
  bar.DesignHitTest(p.X, p.Y, 0);
  AssertSame('设计期离开之后:不切页', a, bar.ActiveWindow);
  bar.CallMouseDown(p.X, p.Y);
  bar.CallCaptureChanged;
  bar.DesignHitTest(p.X, p.Y, 0);
  AssertSame('捕获被拿走之后:不切页', a, bar.ActiveWindow);
  { 对照:没被打断的那一次照常在松开时切。 }
  bar.CallMouseDown(p.X, p.Y);
  bar.DesignHitTest(p.X, p.Y, 0);
  AssertSame('正常松开照切', b, bar.ActiveWindow);
end;

procedure TTyToolWindowStripTests.TestAWindowLeavingKeepsThePressedIconOnItsWindow;
var
  a, c: TProbeWindow;
  p: TPoint;
begin
  a := NewWindow;
  NewWindow;
  c := NewWindow;
  FBar.ActiveWindow := a;
  p := FBar.StripItemRect(2).CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  AssertEquals('前提:按下态在第 2 格', 2, FBar.StripPressed);
  a.Free;
  AssertEquals('a 走了,c 挪到第 1 格:按下态跟着 c', 1, FBar.StripPressed);
  p := FBar.StripItemRect(1).CenterPoint;
  FBar.CallMouseUp(p.X, p.Y);
  AssertSame('松开照常点中 c', c, FBar.ActiveWindow);
end;

procedure TTyToolWindowStripTests.TestADesignGestureFollowsItsWindowWhenAnotherLeaves;
var
  bar: TBarAccess;
  a, b, c: TProbeWindow;
  p: TPoint;
begin
  bar := NewDesignBar;
  a := NewWindowIn(bar, FDesignOwner);
  b := NewWindowIn(bar, FDesignOwner);
  c := NewWindowIn(bar, FDesignOwner);
  bar.ActiveWindow := b;
  p := bar.StripItemRect(2).CenterPoint;
  bar.CallMouseDown(p.X, p.Y);
  a.Free;
  { 设计器里删掉了别的窗口:按下的那个记的是窗口,不是序号。 }
  p := bar.StripItemRect(1).CenterPoint;
  bar.DesignHitTest(p.X, p.Y, 0);
  AssertSame('松开在 c 现在的位置上:切到 c', c, bar.ActiveWindow);
end;

{ --- 溢出按钮的状态与菜单方向 ------------------------------------------------------ }

procedure TTyToolWindowStripTests.TestTheOverflowButtonPaintsHoverAndPressedInTheStripInk;
const
  Cyan = TColor($FFFF00);    { CSS #00FFFF:悬停叠加色 }
  Green = TColor($008000);   { CSS #008000:按下叠加色 }
  Orange = TColor($0080FF);  { CSS #FF8000:标签行墨色,条上不许出现 }
var
  i: Integer;
  r: TRect;
  p: TPoint;

  function Shot: TBitmap;
  begin
    Result := RenderRegion(FBar, FBar.ClientWidth, FBar.ClientHeight, r, Wipe);
  end;

var
  bmp: TBitmap;
  reds: Integer;
begin
  FCtl.StyleOverride := StripTheme + ' :root { --toolwindow-tab-ink: #FF8000;' +
    ' --toolwindow-overlay-hover: #00FFFF; --toolwindow-overlay-active: #008000; }';
  for i := 1 to 4 do NewWindow;
  FBar.Height := 3 * TyToolWindowStripItemSizeDef + TyToolWindowStripItemSizeDef div 2;
  r := FBar.BarLayout.Overflow;
  AssertTrue('前提:有溢出按钮', r.Bottom > r.Top);
  bmp := Shot;
  try
    AssertTrue('静止:字形是图标条的墨色', CountInk(bmp, Ground, RestInk) > 0);
    AssertEquals('静止:不是标签行的墨色', 0, CountInk(bmp, Ground, Orange));
    AssertEquals('静止:没有悬停底色', 0, CountExact(bmp, Cyan));
  finally
    bmp.Free;
  end;
  p := r.CenterPoint;
  FBar.CallMouseMove(p.X, p.Y, []);
  bmp := Shot;
  try
    AssertTrue('悬停:铺 :hover 的底色', CountExact(bmp, Cyan) > 0);
    { 青底上画黄墨:抗锯齿按伽马混合,不落在 CountInk 的线性混合线上;判据用红通道 ——
      青底和静止的蓝墨红通道都是 0,只有黄墨(悬停墨色)把它抬起来。 }
    reds := 0;
    for i := 0 to bmp.Width * bmp.Height - 1 do
      if Red(ColorToRGB(bmp.Canvas.Pixels[i mod bmp.Width, i div bmp.Width])) > 128 then Inc(reds);
    AssertTrue('悬停:字形换成图标条悬停的墨色', reds > 0);
  finally
    bmp.Free;
  end;
  FBar.CallMouseDown(p.X, p.Y);
  bmp := Shot;
  try
    AssertTrue('按下:铺 :active 的底色', CountExact(bmp, Green) > 0);
  finally
    bmp.Free;
  end;
  FBar.CallMouseMove(p.X, p.Y + 1000, []);   { 丢了松开:回到 Idle,不弹菜单 }
  FBar.Enabled := False;
  FBar.CallMouseMove(p.X, p.Y, []);
  bmp := Shot;
  try
    AssertEquals('禁用:不接悬停', 0, CountExact(bmp, Cyan));
  finally
    bmp.Free;
  end;
end;

procedure TTyToolWindowStripTests.TestTheOverflowMenuOpensTowardsTheContent;
var
  r: TRect;
  p: TPoint;
  al: TPopupAlignment;
begin
  r := Rect(10, 100, 46, 136);
  TyToolWindowOverflowMenuAnchor(r, twpLeft, False, p, al);
  AssertEquals('左栏:挂在溢出按钮右沿', 46, p.X);
  AssertEquals('左栏:上沿', 100, p.Y);
  AssertEquals('左栏 LTR:往右开 = 贴阅读起点', Ord(paLeft), Ord(al));
  TyToolWindowOverflowMenuAnchor(r, twpRight, False, p, al);
  AssertEquals('右栏:挂在溢出按钮左沿', 10, p.X);
  AssertEquals('右栏 LTR:往左开 = 贴阅读终点', Ord(paRight), Ord(al));
  { 菜单跟着栏读 RTL 时,对齐方式是阅读顺序的量:物理方向不变,名字反过来。 }
  TyToolWindowOverflowMenuAnchor(r, twpLeft, True, p, al);
  AssertEquals('左栏 RTL:锚点不变', 46, p.X);
  AssertEquals('左栏 RTL:往右开 = 贴阅读终点', Ord(paRight), Ord(al));
  TyToolWindowOverflowMenuAnchor(r, twpRight, True, p, al);
  AssertEquals('右栏 RTL:往左开 = 贴阅读起点', Ord(paLeft), Ord(al));
end;

procedure TTyToolWindowStripTests.TestShowingTheOverflowMenuSetsItsAlignment;
var
  i: Integer;
  p: TPoint;
begin
  for i := 1 to 4 do NewWindow;
  FBar.Height := 3 * TyToolWindowStripItemSizeDef + TyToolWindowStripItemSizeDef div 2;
  FBar.Placement := twpRight;
  p := FBar.BarLayout.Overflow.CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseUp(p.X, p.Y);
  AssertTrue('前提:菜单建出来了', FBar.OverflowMenu <> nil);
  AssertEquals('右栏:菜单往左(内容区)开', Ord(paRight), Ord(FBar.OverflowMenu.Alignment));
  FBar.Placement := twpLeft;
  p := FBar.BarLayout.Overflow.CenterPoint;
  FBar.CallMouseDown(p.X, p.Y);
  FBar.CallMouseUp(p.X, p.Y);
  AssertEquals('左栏:往右开', Ord(paLeft), Ord(FBar.OverflowMenu.Alignment));
end;

initialization
  RegisterTest(TTyToolWindowStripTests);
end.
