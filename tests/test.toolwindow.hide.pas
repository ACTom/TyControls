unit test.toolwindow.hide;
{$mode objfpc}{$H+}

{ 一侧没有窗口时隐藏(spec §6.9,E 期)与拖动时的放置预览(spec §9.4 / §9.8)。夹具在
  test.toolwindow.manager(TTyToolWindowManagerFixture)。 }

interface

uses
  Classes, SysUtils, Types, TypInfo, Controls, Forms, Graphics, LCLType, LCLProc, LMessages,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Base, tyControls.Controller, tyControls.StrConsts,
  tyControls.Painter,
  tyControls.ToolWindows, tyControls.ToolWindows.Layout, tyControls.ToolWindows.Manager,
  test.toolwindow.window, test.toolwindow.bar, test.toolwindow.manager;

type
  TTyToolWindowHideTests = class(TTyToolWindowManagerFixture)
  private
    { 窗体上一条 APlacement 的空栏(照 NewBarOn,只是不加窗口)。 }
    function NewEmptyBar(APlacement: TTyToolWindowPlacement): TBarAccess;
    function Chrome(ABar: TBarAccess): Integer;
  published
    { --- Task 7:HideWhenEmpty(spec §6.9) --- }
    procedure TestHiddenAsEmptyAnswersPerBar;
    procedure TestAHiddenBarIsZeroWideAndLaysOutNothing;
    procedure TestAKeptEmptyBarShowsItsStrip;
    procedure TestAHiddenBarAllowsAZeroMinimumWidth;
    procedure TestTheBottomBarIgnoresTheProperty;
    procedure TestTheLastWindowLeavingHidesTheBar;
    procedure TestHidingNeverWritesCollapsedOrExpandedSize;
    procedure TestTogglingThePropertyRederives;
    procedure TestAHiddenBarStaysUsable;
    procedure TestAHiddenBarGivesItsShareBack;
    procedure TestALayoutHidesAndShowsBars;
    procedure TestHideWhenEmptyStreamsOnlyWhenOff;
    procedure TestDesignTimeNeverHides;
    { --- Task 8:放置预览(spec §9.4 / §9.8) --- }
    procedure TestEnteringADragShowsThePreview;
    procedure TestThePreviewSitsWhereTheBarWouldOpen;
    procedure TestThePreviewNarrowsWithTheParent;
    procedure TestAPressWithoutADragShowsNoPreview;
    procedure TestPointingIntoThePreviewTargetsTheHiddenBar;
    procedure TestLeavingThePreviewClearsIt;
    procedure TestDroppingInThePreviewMovesTheWindowThere;
    procedure TestEscOrCancelDragPutsThePreviewAway;
    procedure TestAVetoedHiddenBarIsNoTarget;
    procedure TestAKeptEmptyBarShowsNoPreview;
    procedure TestABottomTabDragShowsNoPreview;
    procedure TestADisabledHiddenBarShowsNoPreview;
    procedure TestThePreviewIsNotAWatchedSibling;
    procedure TestThePreviewPaintsOpaqueWithTextAndHover;
    procedure TestThePreviewTextFitsTheDefaultWidth;
    procedure TestFreeingTheHiddenBarOrTheManagerMidDrag;
    procedure TestThePreviewGoesAwayWhenTheBarStopsHiding;
  private
    FMgr: TTyToolWindowManager;
    FLeft, FRight: TBarAccess;
    FEditor: TBodyChild;
    FSearch, FOutline: TTyToolWindow;
    { 左栏 Explorer / Search / Git,右栏 Outline;先把 Outline 挪到左边,右栏空了、隐藏;
      一个 alClient 的编辑区;窗体对齐一遍。 }
    procedure NewHiddenRight;
    procedure AlignForm;
    { 在左栏 Search 图标上按下、横拖过阈值。 }
    procedure StartDrag;
    procedure MoveTo(const AScreen: TPoint);
    procedure ReleaseAt(const AScreen: TPoint);
    function PreviewCentre: TPoint;
    function EditorPoint: TPoint;
    { 右栏「有一个窗口、展开着」时的推导宽:临时关掉 HideWhenEmpty、放一个窗口量,量完还原。 }
    function ShownWidthOfRight: Integer;
  end;

implementation

type
  { 流式化的根(同 test.toolwindow.window 的 TToolWindowHostForm,那一个在实现段里拿不到)。 }
  THideHostForm = class(TForm)
  end;

function TTyToolWindowHideTests.NewEmptyBar(APlacement: TTyToolWindowPlacement): TBarAccess;
begin
  Result := TBarAccess.Create(FForm);
  Result.Placement := APlacement;
  Result.Parent := FForm;
  Result.Controller := FCtl;
  Result.Font.PixelsPerInch := 96;
  if APlacement = twpBottom then Result.Width := 600 else Result.Height := 400;
end;

function TTyToolWindowHideTests.Chrome(ABar: TBarAccess): Integer;
begin
  Result := ABar.ChromeInsetPx;
end;

{ --- Task 7 --------------------------------------------------------------------- }

procedure TTyToolWindowHideTests.TestHiddenAsEmptyAnswersPerBar;
var
  b: TBarAccess;
begin
  b := NewEmptyBar(twpLeft);
  AssertTrue('运行时左栏,没有窗口', b.HiddenAsEmpty);
  b := NewEmptyBar(twpRight);
  AssertTrue('运行时右栏,没有窗口', b.HiddenAsEmpty);
  b := NewEmptyBar(twpLeft);
  b.HideWhenEmpty := False;
  AssertFalse('HideWhenEmpty 关掉', b.HiddenAsEmpty);
  b := NewBarOn(twpLeft, ['Solo']);
  AssertFalse('有一个窗口', b.HiddenAsEmpty);
  b := NewEmptyBar(twpLeft);
  b.InsertControl(TBodyChild.Create(FForm));
  AssertTrue('漏进来的非窗口子控件不算窗口', b.HiddenAsEmpty);
  b := NewDesignBar;
  AssertFalse('设计期不隐藏', b.HiddenAsEmpty);
  b := NewEmptyBar(twpBottom);
  AssertFalse('底栏不管(高本来就是 0)', b.HiddenAsEmpty);
  b := NewEmptyBar(twpLeft);
  b.Collapsed := True;
  AssertTrue('收起着也照样隐藏', b.HiddenAsEmpty);
end;

procedure TTyToolWindowHideTests.TestAHiddenBarIsZeroWideAndLaysOutNothing;
var
  b: TBarAccess;
  L: TTyToolWindowBarLayout;
begin
  b := NewEmptyBar(twpLeft);
  AssertEquals('推导宽 0', 0, b.CallDerivedAxisPx);
  AssertEquals('Width = 0', 0, b.Width);
  AssertTrue('Visible 不写', b.Visible);
  L := b.BarLayout;
  AssertTrue('没有图标条', IsRectEmpty(L.Strip));
  AssertTrue('没有排图标的那一段', IsRectEmpty(L.Cells));
  AssertTrue('没有边缘区', IsRectEmpty(L.Edge));
  AssertTrue('没有内容区', IsRectEmpty(L.Content));
end;

procedure TTyToolWindowHideTests.TestAKeptEmptyBarShowsItsStrip;
var
  b: TBarAccess;
begin
  b := NewEmptyBar(twpLeft);
  b.HideWhenEmpty := False;
  AssertEquals('HideWhenEmpty = False:图标条 + 2 × chrome(A 期的样子)',
    StripPx + 2 * Chrome(b), b.CallDerivedAxisPx);
end;

procedure TTyToolWindowHideTests.TestAHiddenBarAllowsAZeroMinimumWidth;
var
  b: TBarAccess;
  minW, minH, maxW, maxH: TConstraintSize;
begin
  b := NewEmptyBar(twpLeft);
  minW := 0;
  minH := 0;
  maxW := 0;
  maxH := 0;
  b.CallConstrainedResize(minW, minH, maxW, maxH);
  AssertEquals('隐藏时下限 0(否则 LCL 把宽 0 钳回图标条宽)', 0, minW);
  b.HideWhenEmpty := False;
  b.CallConstrainedResize(minW, minH, maxW, maxH);
  AssertEquals('对照:不隐藏时下限是图标条', StripPx + 2 * Chrome(b), minW);
end;

procedure TTyToolWindowHideTests.TestTheBottomBarIgnoresTheProperty;
var
  b: TBarAccess;
  withWin: Integer;
begin
  b := NewEmptyBar(twpBottom);
  AssertEquals('空底栏高 0', 0, b.CallDerivedAxisPx);
  b.HideWhenEmpty := False;
  AssertEquals('关掉也是 0', 0, b.CallDerivedAxisPx);
  NewWindowIn(b, FForm);
  withWin := b.CallDerivedAxisPx;
  b.HideWhenEmpty := True;
  AssertEquals('有窗口时两种设置一样', withWin, b.CallDerivedAxisPx);
end;

procedure TTyToolWindowHideTests.TestTheLastWindowLeavingHidesTheBar;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
  outline: TTyToolWindow;
begin
  m := NewManager;
  l := NewBarOn(twpLeft, ['Outline']);
  r := NewBarOn(twpRight, ['Other']);
  l.Manager := m;
  r.Manager := m;
  outline := l.Windows[0];
  AssertTrue('前提:挪得过去', m.MoveWindow(outline, r));
  AssertEquals('最后一个窗口走了:左栏宽 0', 0, l.Width);
  AssertTrue('再挪回来', m.MoveWindow(outline, l));
  AssertEquals('左栏出现:图标条 + 2 × chrome + 边缘区 + 内容',
    StripPx + 2 * Chrome(l) + EdgePx + TyToolWindowDefaultExpandedSize, l.Width);
end;

procedure TTyToolWindowHideTests.TestHidingNeverWritesCollapsedOrExpandedSize;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
  outline: TTyToolWindow;
begin
  m := NewManager;
  l := NewBarOn(twpLeft, ['Outline']);
  r := NewBarOn(twpRight, ['Other']);
  l.Manager := m;
  r.Manager := m;
  outline := l.Windows[0];
  l.ExpandedSize := 200;
  l.Collapsed := True;
  m.MoveWindow(outline, r);
  AssertEquals('前提:隐藏了', 0, l.Width);
  AssertTrue('隐藏期间 Collapsed 不被写', l.Collapsed);
  AssertEquals('ExpandedSize 不变', 200, l.ExpandedSize);
  m.MoveWindow(outline, l);
  AssertFalse('挪回来照 §9.5 展开目标栏', l.Collapsed);
  AssertEquals('ExpandedSize 还是 200', 200, l.ExpandedSize);
end;

procedure TTyToolWindowHideTests.TestTogglingThePropertyRederives;
var
  b: TBarAccess;
begin
  b := NewEmptyBar(twpRight);
  AssertEquals('前提:隐藏', 0, b.Width);
  b.HideWhenEmpty := False;
  AssertTrue('关掉:宽 > 0', b.Width > 0);
  b.HideWhenEmpty := True;
  AssertEquals('打开:宽 0', 0, b.Width);
end;

procedure TTyToolWindowHideTests.TestAHiddenBarStaysUsable;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
begin
  m := NewManager;
  l := NewBarOn(twpLeft, ['Explorer', 'Search']);
  r := NewEmptyBar(twpRight);
  l.Manager := m;
  r.Manager := m;
  AssertTrue('前提:右栏隐藏', r.HiddenAsEmpty);
  AssertTrue('隐藏的栏照样可用', m.IsBarUsable(r));
  AssertSame('UsableBar 答它', r, m.UsableBar(twpRight));
  AssertTrue('MoveWindow 过去答 True', m.MoveWindow(l.Windows[0], r));
  AssertTrue('右栏出现', r.Width > 0);
end;

procedure TTyToolWindowHideTests.TestAHiddenBarGivesItsShareBack;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
  hiddenW, aloneW: Integer;
begin
  { 窄到左栏自己都要收窄:隐藏的右栏还按图标条扣固定部分的话,左栏会少一截。 }
  FForm.SetBounds(0, 0, 250, 600);
  m := NewManager;
  l := NewBarOn(twpLeft, ['Explorer']);
  r := NewBarOn(twpRight, ['Outline']);
  l.Manager := m;
  r.Manager := m;
  m.MoveWindow(r.Windows[0], l);
  AssertTrue('前提:右栏隐藏了', r.HiddenAsEmpty);
  hiddenW := l.Width;
  r.Visible := False;
  aloneW := l.Width;
  AssertTrue('前提:左栏自己也收窄着', aloneW < StripPx + 2 * Chrome(l) + EdgePx
    + TyToolWindowDefaultExpandedSize);
  AssertEquals('隐藏的栏分空间为 0:左栏拿到它不跟右栏分时的宽', aloneW, hiddenW);
end;

procedure TTyToolWindowHideTests.TestALayoutHidesAndShowsBars;
var
  m: TTyToolWindowManager;
  l, r: TBarAccess;
  withRight, emptyRight: string;
begin
  m := NewManager;
  l := NewBarOn(twpLeft, ['Explorer', 'Search']);
  r := NewBarOn(twpRight, ['Outline']);
  l.Manager := m;
  r.Manager := m;
  withRight := m.SaveLayoutToString;
  m.MoveWindow(r.Windows[0], l);
  emptyRight := m.SaveLayoutToString;
  AssertTrue('前提:读回有窗口的那份', m.LoadLayoutFromString(withRight));
  AssertTrue('右栏有窗口:出现', r.Width > 0);
  AssertTrue('前提:读回空右栏的那份', m.LoadLayoutFromString(emptyRight));
  AssertEquals('右栏空了:宽 0', 0, r.Width);
  AssertTrue(m.LoadLayoutFromString(withRight));
  AssertTrue('再读回来:又出现', r.Width > 0);
end;

procedure TTyToolWindowHideTests.TestHideWhenEmptyStreamsOnlyWhenOff;
var
  src, dst: TForm;
  ms: TMemoryStream;
  txt: TStringStream;
  bar, dbar: TTyToolWindowBar;
  b: TTyToolWindowBar;
begin
  b := TTyToolWindowBar.Create(nil);
  try
    AssertEquals('HideWhenEmpty 的 default 等于构造值', Ord(b.HideWhenEmpty),
      GetPropInfo(b, 'HideWhenEmpty')^.Default);
    AssertTrue('构造值 True', b.HideWhenEmpty);
  finally
    b.Free;
  end;
  src := THideHostForm.CreateNew(nil);
  src.Name := 'HostForm1';
  dst := THideHostForm.CreateNew(nil);
  ms := TMemoryStream.Create;
  txt := TStringStream.Create('');
  try
    bar := TTyToolWindowBar.Create(src);
    bar.Name := 'Bar';
    bar.Parent := src;
    ms.WriteComponent(src);
    ms.Position := 0;
    ObjectBinaryToText(ms, txt);
    AssertEquals('True 不写进 .lfm', 0, Pos('HideWhenEmpty', txt.DataString));
    bar.HideWhenEmpty := False;
    ms.Clear;
    ms.WriteComponent(src);
    ms.Position := 0;
    ms.ReadComponent(dst);
    dbar := dst.FindComponent('Bar') as TTyToolWindowBar;
    AssertFalse('False 写进去、读回来', dbar.HideWhenEmpty);
  finally
    txt.Free;
    ms.Free;
    dst.Free;
    src.Free;
  end;
end;

procedure TTyToolWindowHideTests.TestDesignTimeNeverHides;
var
  d: TBarAccess;
begin
  d := NewDesignBar;
  AssertEquals('设计期空左栏按展开算', StripPx + 2 * Chrome(d) + EdgePx
    + TyToolWindowDefaultExpandedSize, d.Width);
  AssertFalse('照旧画「添加工具窗口」', IsRectEmpty(d.BarLayout.EmptyNote));
end;

{ --- Task 8 --------------------------------------------------------------------- }

type
  TFormAccess = class(TForm);
  { 受保护的命中测试、预览的 RenderTo:只转发。 }
  TMgrAccess = class(TTyToolWindowManager);
  TPreviewAccess = class(TTyToolWindowDropPreview);

procedure TTyToolWindowHideTests.AlignForm;
var
  r: TRect;
begin
  r := FForm.ClientRect;
  TFormAccess(FForm).AdjustClientRect(r);
  TFormAccess(FForm).AlignControls(nil, r);
  LayOut(FLeft);
end;

procedure TTyToolWindowHideTests.NewHiddenRight;
begin
  FMgr := NewManager;
  FMgr.OnWindowMoved := @LogMoved;
  FLeft := NewBarOn(twpLeft, ['Explorer', 'Search', 'Git']);
  FRight := NewBarOn(twpRight, ['Outline']);
  FLeft.Manager := FMgr;
  FRight.Manager := FMgr;
  FSearch := FLeft.Windows[1];
  FOutline := FRight.Windows[0];
  FEditor := TBodyChild.Create(FForm);
  FEditor.Parent := FForm;
  FEditor.Align := alClient;
  AssertTrue('前提:Outline 挪到左边', FMgr.MoveWindow(FOutline, FLeft));
  AssertTrue('前提:右栏隐藏了', FRight.HiddenAsEmpty);
  AlignForm;
  FLog := '';
  FCanCalls := 0;
end;

procedure TTyToolWindowHideTests.StartDrag;
var
  p: TPoint;
begin
  p := FLeft.StripItemRect(FLeft.IndexOfWindow(FSearch)).CenterPoint;
  FLeft.CallMouseDown(p.X, p.Y);
  FLeft.CallMouseMove(p.X + 10, p.Y);
  AssertTrue('前提:拖起来了', FLeft.IsDraggingForTest);
end;

procedure TTyToolWindowHideTests.MoveTo(const AScreen: TPoint);
var
  q: TPoint;
begin
  q := FLeft.ScreenToClient(AScreen);
  FLeft.CallMouseMove(q.X, q.Y);
end;

procedure TTyToolWindowHideTests.ReleaseAt(const AScreen: TPoint);
var
  q: TPoint;
begin
  q := FLeft.ScreenToClient(AScreen);
  FLeft.CallClick;
  FLeft.CallMouseUp(q.X, q.Y);
end;

function TTyToolWindowHideTests.PreviewCentre: TPoint;
begin
  AssertNotNull('前提:有预览', FRight.DropPreview);
  Result := FForm.ClientToScreen(FRight.DropPreview.BoundsRect.CenterPoint);
end;

function TTyToolWindowHideTests.EditorPoint: TPoint;
begin
  { 靠左的一点:编辑区右边那一截被右侧的放置预览盖着(预览就是展开后的右栏那么宽)。 }
  Result := FEditor.ClientToScreen(Point(10, FEditor.ClientHeight div 2));
  AssertFalse('前提:这一点不在预览里', (FRight <> nil) and (FRight.DropPreview <> nil)
    and FRight.DropPreview.Visible
    and PtInRect(FRight.DropPreview.BoundsRect, FForm.ScreenToClient(Result)));
end;

function TTyToolWindowHideTests.ShownWidthOfRight: Integer;
var
  w: TProbeWindow;
begin
  FRight.HideWhenEmpty := False;
  w := NewWindowIn(FRight, FForm);
  Result := FRight.CallDerivedAxisPx;
  w.Free;
  FRight.HideWhenEmpty := True;
  AssertTrue('前提:量完又隐藏了', FRight.HiddenAsEmpty);
end;

procedure TTyToolWindowHideTests.TestEnteringADragShowsThePreview;
var
  pv: TTyToolWindowDropPreview;
begin
  NewHiddenRight;
  StartDrag;
  pv := FRight.DropPreview;
  AssertNotNull('进入拖动:隐藏的右栏有了放置预览', pv);
  AssertTrue('看得见', pv.Visible);
  AssertTrue('挂在右栏的父控件上', pv.Parent = FRight.Parent);
  AssertFalse('不在任何栏里', pv.Parent is TTyToolWindowBar);
  FLeft.CallMouseUp(0, 0);
end;

procedure TTyToolWindowHideTests.TestThePreviewSitsWhereTheBarWouldOpen;
var
  want: Integer;
  r: TRect;
begin
  NewHiddenRight;
  want := ShownWidthOfRight;
  AlignForm;
  StartDrag;
  r := FRight.DropPreview.BoundsRect;
  AssertEquals('右沿贴着右栏(宽 0)', FRight.Left + FRight.Width, r.Right);
  AssertEquals('顶同右栏', FRight.Top, r.Top);
  AssertEquals('高同右栏', FRight.Height, r.Bottom - r.Top);
  AssertEquals('宽 = 右栏有一个窗口、展开着时的推导宽', want, r.Right - r.Left);
  AssertTrue('前提:比 ExpandedSize 宽(含图标条 / chrome / 边缘区)',
    want > TyToolWindowDefaultExpandedSize);
  FLeft.CallMouseUp(0, 0);
end;

procedure TTyToolWindowHideTests.TestThePreviewNarrowsWithTheParent;
var
  want: Integer;
  r, client: TRect;
begin
  FForm.SetBounds(0, 0, 400, 600);
  NewHiddenRight;
  want := ShownWidthOfRight;
  AlignForm;
  AssertTrue('前提:收窄了', want < StripPx + EdgePx + TyToolWindowDefaultExpandedSize);
  StartDrag;
  r := FRight.DropPreview.BoundsRect;
  AssertEquals('预览按 §6.2 收窄', want, r.Right - r.Left);
  client := FForm.ClientRect;
  TFormAccess(FForm).AdjustClientRect(client);
  AssertTrue('钳在父控件调整后的客户区里', (r.Left >= client.Left) and (r.Right <= client.Right)
    and (r.Top >= client.Top) and (r.Bottom <= client.Bottom));
  FLeft.CallMouseUp(0, 0);
end;

procedure TTyToolWindowHideTests.TestAPressWithoutADragShowsNoPreview;
var
  p: TPoint;
begin
  NewHiddenRight;
  p := FLeft.StripItemRect(FLeft.IndexOfWindow(FSearch)).CenterPoint;
  FLeft.CallMouseDown(p.X, p.Y);
  AssertTrue('按下未过阈值:没有预览',
    (FRight.DropPreview = nil) or not FRight.DropPreview.Visible);
  FLeft.CallMouseUp(p.X, p.Y);
end;

procedure TTyToolWindowHideTests.TestPointingIntoThePreviewTargetsTheHiddenBar;
var
  c: TPoint;
  slot: Integer;
begin
  NewHiddenRight;
  StartDrag;
  c := PreviewCentre;
  AssertSame('探测矩形是预览:命中右栏', FRight, TMgrAccess(FMgr).DropTargetAt(FLeft, c, slot));
  AssertEquals('空栏的「最后一个之后」:槽位 0', 0, slot);
  MoveTo(c);
  AssertTrue('预览亮起(它是此刻的目标)', FRight.DropPreview.Hot);
  AssertEquals('光标 crDrag', Ord(crDrag), Ord(FLeft.DragCursorForTest));
  FLeft.CallMouseUp(0, 0);
end;

procedure TTyToolWindowHideTests.TestLeavingThePreviewClearsIt;
begin
  NewHiddenRight;
  StartDrag;
  MoveTo(PreviewCentre);
  AssertTrue('前提:亮着', FRight.DropPreview.Hot);
  MoveTo(EditorPoint);
  AssertFalse('回到编辑区:不亮', FRight.DropPreview.Hot);
  AssertEquals('光标 crNoDrop', Ord(crNoDrop), Ord(FLeft.DragCursorForTest));
  FLeft.CallMouseUp(0, 0);
end;

procedure TTyToolWindowHideTests.TestDroppingInThePreviewMovesTheWindowThere;
var
  c: TPoint;
begin
  NewHiddenRight;
  StartDrag;
  c := PreviewCentre;
  MoveTo(c);
  ReleaseAt(c);
  AssertSame('Search 到了右栏', TTyToolWindowBar(FRight), FSearch.Bar);
  AssertSame('是右栏的当前页', FSearch, FRight.ActiveWindow);
  AssertTrue('右栏出现', FRight.Width > 0);
  AssertFalse('展开着', FRight.Collapsed);
  AssertFalse('预览收掉了', FRight.DropPreview.Visible);
  AssertEquals('OnWindowMoved 发了一次', 1, Length(FLog) - Length(StringReplace(FLog, 'moved(', 'moved', [rfReplaceAll])));
end;

procedure TTyToolWindowHideTests.TestEscOrCancelDragPutsThePreviewAway;
begin
  NewHiddenRight;
  StartDrag;
  AssertTrue('前提:预览在', FRight.DropPreview.Visible);
  FEditor.Perform(CN_KEYDOWN, VK_ESCAPE, 0);
  AssertFalse('Esc:预览收掉', FRight.DropPreview.Visible);
  FLeft.CallMouseUp(0, 0);
  StartDrag;
  AssertTrue('前提:预览又在', FRight.DropPreview.Visible);
  FMgr.CancelDrag;
  AssertFalse('CancelDrag:预览收掉', FRight.DropPreview.Visible);
  FLeft.CallMouseUp(0, 0);
end;

procedure TTyToolWindowHideTests.TestAVetoedHiddenBarIsNoTarget;
var
  c: TPoint;
  slot: Integer;
begin
  NewHiddenRight;
  FAllow := False;
  StartDrag;
  AssertTrue('否决要等指针进去才知道:预览照样显示', FRight.DropPreview.Visible);
  AssertEquals('进入拖动时没问 CanMoveWindow', 0, FCanCalls);
  c := PreviewCentre;
  MoveTo(c);
  AssertNull('否决:没有目标', TMgrAccess(FMgr).DropTargetAt(FLeft, c, slot));
  AssertEquals('光标 crNoDrop', Ord(crNoDrop), Ord(FLeft.DragCursorForTest));
  AssertFalse('预览不亮', FRight.DropPreview.Hot);
  FLeft.CallMouseUp(0, 0);
end;

procedure TTyToolWindowHideTests.TestAKeptEmptyBarShowsNoPreview;
begin
  NewHiddenRight;
  FRight.HideWhenEmpty := False;
  AlignForm;
  StartDrag;
  AssertTrue('保留图标条的空栏没有预览(照旧是插入线目标)',
    (FRight.DropPreview = nil) or not FRight.DropPreview.Visible);
  FLeft.CallMouseUp(0, 0);
end;

procedure TTyToolWindowHideTests.TestABottomTabDragShowsNoPreview;
var
  b: TBarAccess;
  w: TProbeWindow;
  g: TTyToolWindowHeaderGeom;
  p: TPoint;
  i: Integer;
begin
  NewHiddenRight;
  b := NewBarOn(twpBottom, ['Problems', 'Output']);
  b.Manager := FMgr;
  AlignForm;
  LayOut(b);
  w := b.ActiveWindow as TProbeWindow;
  g := w.HeaderGeomAt(Rect(0, 0, w.ClientWidth, w.ClientHeight), w.Font.PixelsPerInch);
  p := Point(-1, -1);
  for i := 0 to High(g.Tabs) do
    if g.Tabs[i].ItemIndex = b.IndexOfWindow(w) then p := g.Tabs[i].ItemRect.CenterPoint;
  AssertTrue('前提:当前页的标签排上了', p.X >= 0);
  w.CallMouseDown(p.X, p.Y);
  w.CallMouseMove(p.X + 10, p.Y, [ssLeft]);
  AssertTrue('前提:底栏标签拖起来了', b.IsDraggingForTest);
  AssertTrue('底栏标签的拖动不跨栏:没有预览',
    (FRight.DropPreview = nil) or not FRight.DropPreview.Visible);
  w.CallMouseUp(p.X, p.Y);
end;

procedure TTyToolWindowHideTests.TestADisabledHiddenBarShowsNoPreview;
begin
  NewHiddenRight;
  FRight.Enabled := False;
  StartDrag;
  AssertTrue('禁用的栏不是候选:没有预览',
    (FRight.DropPreview = nil) or not FRight.DropPreview.Visible);
  FLeft.CallMouseUp(0, 0);
end;

procedure TTyToolWindowHideTests.TestThePreviewIsNotAWatchedSibling;
var
  before: Integer;
begin
  NewHiddenRight;
  FLeft.ExpandedSize := FLeft.ExpandedSize + 1;     { 推导一次:兄弟挂好 }
  before := FLeft.WatchedSiblingCountForTest;
  StartDrag;
  AssertTrue('前提:预览在', FRight.DropPreview.Visible);
  FLeft.ExpandedSize := FLeft.ExpandedSize + 1;     { 再推导一次 }
  AssertEquals('预览不是兄弟监听对象', before, FLeft.WatchedSiblingCountForTest);
  FLeft.CallMouseUp(0, 0);
end;

procedure TTyToolWindowHideTests.TestThePreviewPaintsOpaqueWithTextAndHover;
const
  { 栏底和预览底都钉成品红(Ground),墨蓝(RestInk),边框黑,:hover 底青。 }
  PvTheme = ':root { --toolwindow-bg: #FF00FF; --toolwindow-ink: #0000FF;' +
    ' --toolwindow-drop-color: #000000; --toolwindow-dropzone-bg: #FF00FF;' +
    ' --toolwindow-dropzone-bg-hover: #00FFFF; }';
var
  pv: TTyToolWindowDropPreview;
  bmp: TBitmap;
  w, h: Integer;
  cold: Boolean;

  function Render: TBitmap;
  begin
    Result := TBitmap.Create;
    Result.PixelFormat := pf32bit;
    Result.SetSize(w, h);
    Result.Canvas.Brush.Color := Wipe;
    Result.Canvas.FillRect(0, 0, w, h);
    TPreviewAccess(pv).RenderTo(Result.Canvas, Rect(0, 0, w, h), 96);
  end;

begin
  NewHiddenRight;
  FCtl.StyleOverride := PvTheme;
  StartDrag;
  pv := FRight.DropPreview;
  w := pv.Width;
  h := pv.Height;
  bmp := Render;
  try
    AssertEquals('不透明:一个底漆像素都不留', 0, CountExact(bmp, Wipe));
    AssertTrue('正中一行字(--toolwindow-ink)', CountInk(bmp, Ground, RestInk) > 0);
    cold := PixelIs(bmp, 5, 5, Ground);
    AssertTrue('前提:静止态底色是钉住的那个', cold);
  finally
    bmp.Free;
  end;
  pv.Hot := True;
  bmp := Render;
  try
    AssertFalse(':hover 的底色和静止态不同', PixelIs(bmp, 5, 5, Ground));
  finally
    bmp.Free;
  end;
  FLeft.CallMouseUp(0, 0);
end;

procedure TTyToolWindowHideTests.TestThePreviewTextFitsTheDefaultWidth;

  procedure Check(APlacement: TTyToolWindowPlacement; const AText: string);
  var
    b: TBarAccess;
    S: TTyStyleSet;
    r: TRect;
    fs, tw, th, rw, pad, avail: Integer;
  begin
    b := NewEmptyBar(APlacement);
    AssertEquals('前提:默认展开尺寸', 240, b.ExpandedSize);
    { 右栏要先被对齐引擎摆到窗体右边(宽 0 的栏,预览从它的位置往左展开)。 }
    r := FForm.ClientRect;
    TFormAccess(FForm).AdjustClientRect(r);
    TFormAccess(FForm).AlignControls(nil, r);
    S := FCtl.Model.ResolveStyle(TyToolWindowDropZoneKey, '', [tysNormal]);
    fs := TyResolveFontSize(S, True, 0, FCtl);
    TyMeasureTextBlock(AText, S.FontName, fs, S.FontWeight, 96, 0, 0, tw, th);
    rw := TyMeasureRenderedTextWidth(AText, S.FontName, fs, S.FontWeight, 96);
    if rw > tw then tw := rw;
    pad := FCtl.Metric(TyToolWindowHeaderPadVar, TyToolWindowHeaderPadDef);
    avail := b.DropPreviewRect.Right - b.DropPreviewRect.Left - 2 * pad;
    AssertTrue(Format('%s 放得下(可用 %d,字宽 %d)', [AText, avail, tw]), avail >= tw);
    b.Free;
  end;

begin
  Check(twpLeft, rsTyToolWindowDropLeft);
  Check(twpRight, rsTyToolWindowDropRight);
end;

procedure TTyToolWindowHideTests.TestFreeingTheHiddenBarOrTheManagerMidDrag;
begin
  NewHiddenRight;
  StartDrag;
  AssertTrue('前提:预览在', FRight.DropPreview.Visible);
  FRight.Free;
  FRight := nil;
  ReleaseAt(EditorPoint);
  AssertSame('松开不挪', TTyToolWindowBar(FLeft), FSearch.Bar);
  StartDrag;
  FMgr.Free;
  FMgr := nil;
  AssertFalse('manager 走了:拖动收尾', FLeft.IsDraggingForTest);
  FLeft.CallMouseUp(0, 0);
end;

procedure TTyToolWindowHideTests.TestThePreviewGoesAwayWhenTheBarStopsHiding;
var
  w: TProbeWindow;
begin
  NewHiddenRight;
  StartDrag;
  AssertTrue('前提:预览在', FRight.DropPreview.Visible);
  FRight.HideWhenEmpty := False;
  AssertFalse('HideWhenEmpty 关了:收掉', FRight.DropPreview.Visible);
  FLeft.CallMouseUp(0, 0);
  FRight.HideWhenEmpty := True;
  StartDrag;
  AssertTrue('前提:预览又在', FRight.DropPreview.Visible);
  w := TProbeWindow.Create(FForm);
  w.Parent := FRight;
  AssertFalse('来了一个窗口:收掉', FRight.DropPreview.Visible);
  FLeft.CallMouseUp(0, 0);
end;

initialization
  RegisterClass(THideHostForm);
  RegisterTest(TTyToolWindowHideTests);
end.
