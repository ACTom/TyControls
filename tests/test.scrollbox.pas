unit test.scrollbox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, LMessages,
  fpcunit, testregistry,
  tyControls.Types, tyControls.Controller,
  tyControls.Base, tyControls.Panel, tyControls.ScrollBar, tyControls.ScrollBox,
  tyControls.ScrollContent;
type
  { Pure scroll-math functions — the headless-tested core. }
  TTyScrollBoxMathTest = class(TTestCase)
  published
    procedure TestScrollNeeded;
    procedure TestScrollMax;
    procedure TestClampScroll;
    procedure TestThumbPage;
  end;

  { The control: range computation, bar visibility, offset clamping, wheel. }
  TTyScrollBoxTest = class(TTestCase)
  private
    FForm: TForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKeyIsScrollBox;
    procedure TestNoBarsWhenContentFits;
    procedure TestVerticalBarWhenContentTaller;
    procedure TestBarsStayAboveContentChildren;
    // the explicit viewport
    procedure TestViewportSitsInsideTheFrame;
    procedure TestViewportHostsTheMeasuredContent;
    procedure TestViewportIsNotItselfContent;
    procedure TestWithoutAViewportNothingChanges;
    procedure TestHorizontalBarWhenContentWider;
    procedure TestBothBarsWhenContentBigger;
    procedure TestRangeIsChildBoundingBox;
    procedure TestScrollbarSyncsOffset;
    procedure TestOffsetClampsWhenBoxGrows;
    procedure TestWheelScrollsVertically;
    procedure TestScrollBarsAreNoDesignVisible;
    procedure TestBarInheritsController;
    procedure TestScrollByDeltaReclampsAfterContentShrinks;
    { The container contract — a scroll box is a CONTAINER, so the LCL alignment engine
      has to be told (a) that the bars own a gutter and (b) where the scrolled origin is.
      Both were missing, and the pure math above stayed green throughout.

      What is NOT here: whether ALIGNED children actually end up off the bar and actually
      scroll. That needs the LCL align engine to run, and it never does in this suite —
      TControl.AdjustSize walks to the top parent and bails out on AutoSizeDelayedHandle,
      which is always true for a TForm.CreateNew that is never shown. Asserting on aligned
      children here passes on the BROKEN code too. That coverage was checked on a real
      machine during development (scroll cases 3, 4, 10, 11). }
    procedure TestClientRectExcludesBarGutters;
    procedure TestChildAreaExcludesBarGutters;
    procedure TestChildAreaGrowsToContentOnScrollingAxisOnly;
    procedure TestChildAreaFollowsScrollOffset;
    procedure TestChildAreaIsFullBoxWithoutBars;
    { 论坛 #12/#15:拖滑块时闪烁。机理是**两处**停靠代码算出不同的矩形 ——
      MeasureAndDock 停在 (Width-thick-bw, bw),ScrollContentTo 里的补停回
      (Width-thick, 0)。于是每滚一步两条都被搬开一个边框宽再被搬回去,
      肉眼就是 1px 抖动,而每一次 SetBounds 都要整框重排一轮子控件。
      真机计数(开发期实测):12 步拖动 → 120 轮对齐(修后 24 轮)。 }
    procedure TestScrollLeavesTheBarsOnTheirGutter;
    procedure TestRepeatedScrollsNeverDriftTheBars;
    { 上面两条只管**可见**的那两条。RedockBars 的条件里有 `.Visible and`,所以藏着的
      那一条会被 ScrollBy 搬走再也放不回来 —— 这两条量的就是"它露面的那一刻在哪"。
      判决记在 RedockBars 的注释里,别把这两条读成"漂移无害"的许可。 }
    procedure TestHiddenBarIsDockedTheMomentItIsFirstShown;
    procedure TestHiddenBarIsDockedWhenItComesBackAfterBeingHidden;
    { 论坛 #12/#15:滚轮第一格方向反。TestWheelScrollsVertically 测不到它 —— 它直接调
      DoMouseWheel,而真滚轮进来的是一条 LM_MOUSEWHEEL,先经 TControl.WMMouseWheel
      才到 DoMouseWheel。而且它只滚一格,"第一格和后面不一样"这种坏法要**连滚**才看得见。 }
    procedure TestFirstWheelTickGoesTheSameWayAsTheSecond;
    procedure TestWheelIsSymmetricAndClampsAtTheTop;
  end;

  { 视口的容器契约。

    一旦给盒子配了 TTyScrollContent,内容就住在**视口**里,于是 TTyScrollBox 为自己
    的子控件讲的那两条(布局原点跟着偏移走、布局区涨到内容)对它们统统失效 —— 那两个
    钩子在盒子上,而它们不是盒子的子控件。表现:视口里的对齐子控件**一格都不滚**
    (真机计数,开发期实测 A4c:ScrollY 走到 76,首行 Top 158 → 158)。

    这里量的正是那两个钩子,不是"子控件滚没滚" —— 无头环境下 LCL 的对齐引擎根本
    不跑(AutoSizeDelayedHandle),对子控件位置下断言在坏代码上一样是绿的。 }
  TTyScrollViewportTest = class(TTestCase)
  private
    FForm: TForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestViewportLayoutOriginFollowsTheScrollOffset;
    procedure TestViewportLayoutAreaGrowsToTheContent;
    procedure TestViewportLayoutAreaStaysTheViewportWhenContentFits;
    procedure TestViewportOriginIsZeroBeforeAnyScroll;
  end;
implementation

type
  TScrollBoxAccess = class(TTyScrollBox)
  public
    function StyleTypeKey: string;
    function VBar: TTyScrollBar;
    function HBar: TTyScrollBar;
    procedure CallWheel(WheelDelta: Integer);
    procedure CallScrollByDelta(ADx, ADy: Integer);
    { The rect the LCL alignment engine hands to child controls. }
    function Frame: Integer;   // the themed border the content area must stay inside
    function ChildArea: TRect;
  end;

function TScrollBoxAccess.StyleTypeKey: string;
begin
  Result := GetStyleTypeKey;
end;

function TScrollBoxAccess.VBar: TTyScrollBar;
var i: Integer;
begin
  Result := nil;
  for i := 0 to ControlCount - 1 do
    if (Controls[i] is TTyScrollBar)
       and (TTyScrollBar(Controls[i]).Kind = sbVertical) then
      Exit(TTyScrollBar(Controls[i]));
end;

function TScrollBoxAccess.HBar: TTyScrollBar;
var i: Integer;
begin
  Result := nil;
  for i := 0 to ControlCount - 1 do
    if (Controls[i] is TTyScrollBar)
       and (TTyScrollBar(Controls[i]).Kind = sbHorizontal) then
      Exit(TTyScrollBar(Controls[i]));
end;

procedure TScrollBoxAccess.CallWheel(WheelDelta: Integer);
begin
  DoMouseWheel([], WheelDelta, Point(0, 0));
end;

procedure TScrollBoxAccess.CallScrollByDelta(ADx, ADy: Integer);
begin
  ScrollByDelta(ADx, ADy);
end;

{ Exactly what LCL does to lay children out:
    TWinControl.AlignControl:  ARect := GetLogicalClientRect;
    TWinControl.AlignControls: AdjustClientRect(ARect);
  Measuring ClientRect instead would silently skip the grow-to-content half. }
function TScrollBoxAccess.Frame: Integer;
begin
  Result := FrameInset;
end;

function TScrollBoxAccess.ChildArea: TRect;
begin
  Result := GetLogicalClientRect;
  AdjustClientRect(Result);
end;

{ helper: a plain child of a given size at a given position }
function MakeChild(AParent: TWinControl; AL, AT, AW, AH: Integer): TControl;
var c: TTyPanel;
begin
  c := TTyPanel.Create(AParent);
  c.Parent := AParent;
  c.SetBounds(AL, AT, AW, AH);
  Result := c;
end;

{ TTyScrollBoxMathTest }

procedure TTyScrollBoxMathTest.TestScrollNeeded;
begin
  AssertTrue('content taller than viewport needs a bar', TyScrollNeeded(300, 150));
  AssertFalse('content equal to viewport needs no bar', TyScrollNeeded(150, 150));
  AssertFalse('content shorter than viewport needs no bar', TyScrollNeeded(80, 150));
end;

procedure TTyScrollBoxMathTest.TestScrollMax;
begin
  AssertEquals('range = content - viewport', 150, TyScrollMax(300, 150));
  AssertEquals('fits -> 0', 0, TyScrollMax(100, 150));
  AssertEquals('equal -> 0', 0, TyScrollMax(150, 150));
end;

procedure TTyScrollBoxMathTest.TestClampScroll;
begin
  // content 300, viewport 150 -> max offset 150
  AssertEquals('mid stays', 40, TyClampScroll(40, 300, 150));
  AssertEquals('above max clamps to max', 150, TyClampScroll(999, 300, 150));
  AssertEquals('negative clamps to 0', 0, TyClampScroll(-5, 300, 150));
  // content fits -> everything pins to 0
  AssertEquals('fits pins to 0', 0, TyClampScroll(40, 100, 150));
end;

procedure TTyScrollBoxMathTest.TestThumbPage;
begin
  AssertEquals('page = viewport', 150, TyScrollThumbPage(150, 300));
  AssertEquals('never below 1', 1, TyScrollThumbPage(0, 300));
end;

{ TTyScrollBoxTest }

procedure TTyScrollBoxTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
end;

procedure TTyScrollBoxTest.TearDown;
begin
  FForm.Free;
end;

procedure TTyScrollBoxTest.TestTypeKeyIsScrollBox;
var SB: TScrollBoxAccess;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  AssertEquals('own typeKey (a scroll well is not a panel)', 'TyScrollBox', SB.StyleTypeKey);
end;

procedure TTyScrollBoxTest.TestNoBarsWhenContentFits;
var SB: TScrollBoxAccess;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 10, 10, 100, 80);   // well inside
  SB.UpdateScrollRange;
  AssertTrue('no vertical bar when content fits',
    (SB.VBar = nil) or (not SB.VBar.Visible));
  AssertTrue('no horizontal bar when content fits',
    (SB.HBar = nil) or (not SB.HBar.Visible));
end;

procedure TTyScrollBoxTest.TestScrollByDeltaReclampsAfterContentShrinks;
var SB: TScrollBoxAccess; child: TControl;
begin
  // ScrollByDelta (the auto-pan hook) must re-measure so it clamps to the FRESH range, not a
  // stale scrollbar Max — else a live reflow that shrinks the content lets it scroll past the end.
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 200, 200);
  child := MakeChild(SB, 0, 0, 100, 600);   // taller than the viewport -> vertical overflow
  SB.UpdateScrollRange;
  SB.CallScrollByDelta(0, 1000);            // scroll to the bottom
  AssertTrue('scrolled down', SB.ScrollY > 0);
  child.Height := 60;                        // content now fits — WITHOUT a manual UpdateScrollRange
  SB.CallScrollByDelta(0, 1000);            // must re-measure: no overflow -> offset clamps to 0
  AssertEquals('re-measured to the fresh range (offset 0)', 0, SB.ScrollY);
end;

procedure TTyScrollBoxTest.TestVerticalBarWhenContentTaller;
var SB: TScrollBoxAccess;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 10, 10, 100, 500);  // taller than the 200px viewport
  SB.UpdateScrollRange;
  AssertNotNull('vertical bar exists', SB.VBar);
  AssertTrue('vertical bar visible when content taller', SB.VBar.Visible);
end;

procedure TTyScrollBoxTest.TestHorizontalBarWhenContentWider;
var SB: TScrollBoxAccess;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 10, 10, 800, 80);   // wider than the 300px viewport
  SB.UpdateScrollRange;
  AssertNotNull('horizontal bar exists', SB.HBar);
  AssertTrue('horizontal bar visible when content wider', SB.HBar.Visible);
end;

procedure TTyScrollBoxTest.TestBothBarsWhenContentBigger;
var SB: TScrollBoxAccess;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 10, 10, 800, 500);  // bigger on both axes
  SB.UpdateScrollRange;
  AssertTrue('vertical bar visible', (SB.VBar <> nil) and SB.VBar.Visible);
  AssertTrue('horizontal bar visible', (SB.HBar <> nil) and SB.HBar.Visible);
end;

procedure TTyScrollBoxTest.TestRangeIsChildBoundingBox;
var SB: TScrollBoxAccess;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  // Two children; far edges at (20+150)=170 wide and (30+400)=430 tall.
  MakeChild(SB, 5, 5, 60, 60);
  MakeChild(SB, 20, 30, 150, 400);
  SB.UpdateScrollRange;
  AssertEquals('content width = far right edge', 170, SB.ContentWidth);
  AssertEquals('content height = far bottom edge', 430, SB.ContentHeight);
end;

procedure TTyScrollBoxTest.TestScrollbarSyncsOffset;
var SB: TScrollBoxAccess;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 0, 0, 100, 600);   // vertical overflow (range 400+)
  SB.UpdateScrollRange;
  AssertNotNull('vbar present', SB.VBar);
  AssertEquals('offset starts at 0', 0, SB.ScrollY);

  // Move the scrollbar -> the box offset must follow.
  SB.VBar.Position := 50;
  AssertEquals('vertical offset follows scrollbar', 50, SB.ScrollY);
end;

procedure TTyScrollBoxTest.TestOffsetClampsWhenBoxGrows;
var SB: TScrollBoxAccess;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 0, 0, 100, 600);   // range 400 (content 600 - view 200)
  SB.UpdateScrollRange;
  SB.VBar.Position := SB.VBar.Max;  // scroll to the very bottom
  AssertTrue('scrolled toward bottom', SB.ScrollY > 0);

  // Grow the box so the content now fits: offset must clamp back to 0 and the bar hide.
  SB.SetBounds(0, 0, 300, 700);
  SB.UpdateScrollRange;
  AssertEquals('offset clamped to 0 when content fits again', 0, SB.ScrollY);
  AssertTrue('vertical bar hidden when content fits again',
    (SB.VBar = nil) or (not SB.VBar.Visible));
end;

procedure TTyScrollBoxTest.TestWheelScrollsVertically;
var SB: TScrollBoxAccess;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 0, 0, 100, 600);   // vertical overflow
  SB.UpdateScrollRange;
  AssertEquals('starts unscrolled', 0, SB.ScrollY);

  // Wheel DOWN (negative delta) scrolls content up -> offset increases.
  SB.CallWheel(-120);
  AssertTrue('wheel down increases the vertical offset', SB.ScrollY > 0);

  // Wheel UP back toward the top.
  SB.CallWheel(120);
  AssertEquals('wheel up returns to the top', 0, SB.ScrollY);
end;

procedure TTyScrollBoxTest.TestScrollBarsAreNoDesignVisible;
var SB: TScrollBoxAccess;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 0, 0, 800, 600);   // force both bars to exist
  SB.UpdateScrollRange;
  AssertTrue('vbar is csNoDesignVisible',
    csNoDesignVisible in SB.VBar.ControlStyle);
  AssertTrue('hbar is csNoDesignVisible',
    csNoDesignVisible in SB.HBar.ControlStyle);
end;

procedure TTyScrollBoxTest.TestBarInheritsController;
var
  Ctl: TTyStyleController;
  SB: TScrollBoxAccess;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    SB := TScrollBoxAccess.Create(FForm);
    SB.Parent := FForm;
    SB.Font.PixelsPerInch := 96;
    SB.Controller := Ctl;
    SB.SetBounds(0, 0, 300, 200);
    MakeChild(SB, 0, 0, 100, 600);
    SB.UpdateScrollRange;
    AssertNotNull('vbar present', SB.VBar);
    AssertTrue('embedded bar inherits the box Controller', SB.VBar.Controller = Ctl);
  finally
    Ctl.Free;
  end;
end;

procedure TTyScrollBoxTest.TestClientRectExcludesBarGutters;
var
  SB: TScrollBoxAccess;
  thick: Integer;
begin
  // Not cosmetic: LCL banks a child's anchor baseline from Parent.ClientWidth/ClientHeight
  // (TControl.UpdateBaseBounds) but lays it out against the layout rect. Let those two
  // disagree by a scrollbar and every ScrollBy re-banks the difference — an akRight child
  // loses a bar's width per scroll until it is gone.
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 0, 0, 800, 600);        // overflows on both axes -> both bars
  SB.UpdateScrollRange;
  AssertTrue('both bars visible', SB.VBar.Visible and SB.HBar.Visible);
  thick := SB.VBar.Width;
  AssertEquals('ClientWidth gives up the vertical bar gutter', 300 - thick, SB.ClientWidth);
  AssertEquals('ClientHeight gives up the horizontal bar gutter', 200 - thick, SB.ClientHeight);
end;

procedure TTyScrollBoxTest.TestChildAreaExcludesBarGutters;
var
  SB: TScrollBoxAccess;
  area: TRect;
  thick: Integer;
begin
  // A visible bar owns a gutter. If the child area still spans the full box, every
  // alClient/alRight/alBottom child is sized over the bar and buries it. Measured on the
  // non-scrolling axis, which never grows to the content.
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 0, 0, 100, 600);        // vertical overflow only -> vertical bar alone
  SB.UpdateScrollRange;
  AssertTrue('vertical bar visible', SB.VBar.Visible);
  AssertTrue('no horizontal bar', not SB.HBar.Visible);
  thick := SB.VBar.Width;
  area := SB.ChildArea;
  { The content area owes the bar its gutter AND the control its own painted border, on both
    sides -- the border is chrome, not content, which is the whole reason scrolled rows used to
    be drawn over it. }
  AssertEquals('child area gives up the vertical bar gutter and the frame',
    300 - thick - 2 * SB.Frame, area.Right - area.Left);
end;

procedure TTyScrollBoxTest.TestChildAreaGrowsToContentOnScrollingAxisOnly;
var
  SB: TScrollBoxAccess;
  area: TRect;
begin
  // The scrolling axis must grow to the content, or DoAlign(alTop) clamps its running
  // offset and piles every row past the fold onto the last visible one. The OTHER axis
  // must NOT grow: an aligned child's size comes from this rect and feeds back into the
  // content extent, so growing it unconditionally latches the child at the full box width.
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 0, 0, 100, 600);        // vertical overflow only
  SB.UpdateScrollRange;
  AssertEquals('precondition: content measured', 600, SB.ContentHeight);
  AssertTrue('precondition: vertical bar up', SB.VBar.Visible);
  AssertEquals('precondition: ClientHeight untouched (no horizontal bar)', 200, SB.ClientHeight);
  area := SB.ChildArea;
  AssertEquals('scrolling axis grows to the content', 600, area.Bottom - area.Top);
  { The scrolling axis grows to the CONTENT exactly -- the frame is added before the inset takes
    it back, so children get the full 600 to stack in. The still axis is a viewport and owes both
    the gutter and the frame. }
  AssertEquals('the still axis stays at the viewport, less the frame',
    300 - SB.VBar.Width - 2 * SB.Frame,
    area.Right - area.Left);
end;

procedure TTyScrollBoxTest.TestChildAreaFollowsScrollOffset;
var
  SB: TScrollBoxAccess;
  area: TRect;
begin
  // Children are stored SCROLLED, so the layout origin must be the scrolled origin —
  // otherwise the align engine keeps snapping aligned children back to the top.
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 0, 0, 100, 600);
  SB.UpdateScrollRange;
  area := SB.ChildArea;
  { Unscrolled, the origin is the inside of the frame -- not 0, which was on the border line. }
  AssertEquals('unscrolled origin sits inside the frame', SB.Frame, area.Top);

  SB.VBar.Position := 120;
  AssertEquals('offset followed the bar', 120, SB.ScrollY);
  area := SB.ChildArea;
  AssertEquals('layout origin moved with the scroll', SB.Frame - 120, area.Top);
end;

procedure TTyScrollBoxTest.TestChildAreaIsFullBoxWithoutBars;
var
  SB: TScrollBoxAccess;
  area: TRect;
begin
  // No overflow -> no gutters to reserve: a scroll box with content that fits must lay
  // its children out exactly like the TTyPanel it descends from.
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 10, 10, 100, 80);
  SB.UpdateScrollRange;
  area := SB.ChildArea;
  { "Exactly like the TTyPanel it descends from" still holds -- but a panel paints a themed
    border too, and content has never belonged on top of it. With no bars the only thing owed
    is that frame. }
  AssertEquals('full width less the frame', 300 - 2 * SB.Frame, area.Right - area.Left);
  AssertEquals('full height less the frame', 200 - 2 * SB.Frame, area.Bottom - area.Top);
  AssertEquals('origin starts inside the frame', SB.Frame, area.Left);
  AssertEquals('origin starts inside the frame', SB.Frame, area.Top);
end;

procedure TTyScrollBoxTest.TestBarsStayAboveContentChildren;
{ The bars are created in the constructor, so they start at the BOTTOM of the child z-order and
  every control the application adds afterwards paints over them. A content child wider than the
  viewport therefore buried the vertical bar, leaving it visible only in the gaps between rows --
  reported from a running app and reproduced identically on Windows, so it is not a widgetset
  quirk.

  Z-order is the parent's control list, and it is deterministic without a window, so this is one
  of the few layout facts that a headless test can actually pin. }
var
  SB: TScrollBoxAccess;
  i, barIdx, contentIdx: Integer;
  c: TControl;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  { Wider AND taller than the viewport, so both bars show and the child spans the bar column. }
  MakeChild(SB, 10, 10, 420, 500);
  SB.UpdateScrollRange;
  AssertTrue('the fixture shows a vertical bar', SB.VBar.Visible);

  barIdx := -1; contentIdx := -1;
  for i := 0 to SB.ControlCount - 1 do
  begin
    c := SB.Controls[i];
    if c = SB.VBar then barIdx := i
    else if not (c is TTyScrollBar) then contentIdx := i;
  end;
  AssertTrue('found both the bar and a content child', (barIdx >= 0) and (contentIdx >= 0));
  AssertTrue(Format('the vertical bar must sit ABOVE the content in z-order '
    + '(bar at %d, content at %d)', [barIdx, contentIdx]), barIdx > contentIdx);
end;

{ ── the explicit viewport ──────────────────────────────────────────────────────
  A child is clipped by its parent's window, and nothing reachable from Pascal moves that
  boundary -- so on a container whose content MOVES the content necessarily crosses the frame.
  The fix is a real window to clip against: a TTyScrollContent inset by the frame, hosting the
  content. It is explicit, the shape TTyPageControl already uses for TTyTabSheet.

  A box WITHOUT one keeps its old behaviour exactly, which is what lets an existing form gain
  the clipping by being given a viewport rather than by being rewritten. }

function MakeViewport(ABox: TTyScrollBox): TTyScrollContent;
begin
  Result := TTyScrollContent.Create(ABox);
  Result.Parent := ABox;
end;

procedure TTyScrollBoxTest.TestViewportSitsInsideTheFrame;
var
  SB: TScrollBoxAccess;
  vp: TTyScrollContent;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  vp := MakeViewport(SB);
  SB.UpdateScrollRange;
  AssertEquals('viewport starts inside the left frame', SB.Frame, vp.Left);
  AssertEquals('and inside the top frame', SB.Frame, vp.Top);
  AssertEquals('and gives the frame back on the right too',
    300 - 2 * SB.Frame, vp.Width);
end;

procedure TTyScrollBoxTest.TestViewportHostsTheMeasuredContent;
var
  SB: TScrollBoxAccess;
  vp: TTyScrollContent;
begin
  { The content extent must be measured from the VIEWPORT's children once there is one --
    measuring the box's own would find nothing and the bar would never appear. }
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  vp := MakeViewport(SB);
  MakeChild(vp, 0, 0, 100, 600);      // taller than the viewport
  SB.UpdateScrollRange;
  AssertTrue('content inside the viewport still raises a bar', SB.VBar.Visible);
  AssertTrue('and the extent came from it', SB.ContentHeight >= 600);
end;

procedure TTyScrollBoxTest.TestViewportIsNotItselfContent;
var
  SB: TScrollBoxAccess;
begin
  { The viewport's size comes FROM the box, so counting it as content would feed the layout
    back into itself -- a full-size child would demand a bar, which shrinks the viewport, which
    changes the child... }
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeViewport(SB);
  SB.UpdateScrollRange;
  AssertFalse('an empty viewport raises no vertical bar', SB.VBar.Visible);
  AssertFalse('nor a horizontal one', SB.HBar.Visible);
end;

procedure TTyScrollBoxTest.TestWithoutAViewportNothingChanges;
var
  SB: TScrollBoxAccess;
begin
  { The migration promise: an existing form that never heard of a viewport behaves exactly as
    it did. }
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 0, 0, 100, 600);
  SB.UpdateScrollRange;
  AssertTrue('a bar still appears for direct children', SB.VBar.Visible);
  AssertTrue('measured from them', SB.ContentHeight >= 600);
end;

{ ── 停靠只能有一处权威 ─────────────────────────────────────────────────── }

procedure TTyScrollBoxTest.TestScrollLeavesTheBarsOnTheirGutter;
var
  SB: TScrollBoxAccess;
  vBefore, hBefore: TRect;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 0, 0, 800, 600);          { 两轴都溢出 -> 两条都在 }
  SB.UpdateScrollRange;
  AssertTrue('前置条件:两条都出来了', SB.VBar.Visible and SB.HBar.Visible);
  vBefore := SB.VBar.BoundsRect;
  hBefore := SB.HBar.BoundsRect;

  { 滚一步。ScrollBy 会把**每一个**子控件搬走(两条也在内),补停那一步必须把它们
    放回**停靠代码算出来的同一个矩形**,而不是再算一遍。 }
  SB.CallScrollByDelta(0, 40);
  AssertEquals('滚动后垂直条还在原来的槽上(左)', vBefore.Left, SB.VBar.BoundsRect.Left);
  AssertEquals('滚动后垂直条还在原来的槽上(上)', vBefore.Top, SB.VBar.BoundsRect.Top);
  AssertEquals('滚动后垂直条尺寸没变(高)',
    vBefore.Bottom - vBefore.Top, SB.VBar.Height);
  AssertEquals('滚动后水平条还在原来的槽上(左)', hBefore.Left, SB.HBar.BoundsRect.Left);
  AssertEquals('滚动后水平条还在原来的槽上(上)', hBefore.Top, SB.HBar.BoundsRect.Top);
end;

procedure TTyScrollBoxTest.TestRepeatedScrollsNeverDriftTheBars;
var
  SB: TScrollBoxAccess;
  vBefore: TRect;
  i: Integer;
begin
  { 一步看不出漂移的话,连滚会。两处停靠不一致时每一步都要来回搬一次,
    所以这一条既盯住"最终位置对",也盯住"过程中不来回"。 }
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 0, 0, 800, 600);
  SB.UpdateScrollRange;
  vBefore := SB.VBar.BoundsRect;
  for i := 1 to 8 do
  begin
    SB.CallScrollByDelta(0, 20);
    AssertEquals(Format('第 %d 次滚动后垂直条没有离开槽', [i]),
      vBefore.Left, SB.VBar.BoundsRect.Left);
    AssertEquals(Format('第 %d 次滚动后垂直条顶端没动', [i]),
      vBefore.Top, SB.VBar.BoundsRect.Top);
  end;
  AssertTrue('前置条件:这 8 步真的滚出去了', SB.ScrollY > 0);
end;

{ ── 藏着的那一条:漂了,但没人看得见 ─────────────────────────────────────────

  RedockBars 只放回**可见**的条,于是一条藏着的条会跟着每一次 ScrollBy 走。这是真的:
  LCL 的 TWinControl.ScrollBy(wincontrol.inc:6255)无条件遍历 Controls[] 逐个
  SetBounds,不看 Visible。ScrollBox 那一轮的日志里 `hbar visible=False (0,-43 ...)`
  就是它 —— 注意 Left=0:那条**从来没停靠过**,所以它不是"被搬离了槽",而是还在出厂
  位置 (0,0) 上被搬。

  那一轮把它判成无害,理由是"MeasureAndDock 在它变可见之前会先停靠它"。这两条把那句话
  变成可执行的断言:一条量**第一次**露面(FHBarRect 还是空的,补停帮不上忙的那种),
  一条量藏起来又回来(FHBarRect 非空,补停本可以帮忙的那种)。两条都盯同一个不变量 ——
  **可见的那一刻,它在自己的槽上**。

  顺带说清一件这一轮里差点做错的事:那一轮提议的"一行修法 —— 把 `.Visible and` 去掉"
  修不了它自己看见的那个现象。去掉之后条件里还剩 `not IsRectEmpty(FHBarRect)`,而
  从没露过面的条 FHBarRect 恒为空,补停照样跳过它,(0,-43) 一模一样。 }

procedure TTyScrollBoxTest.TestHiddenBarIsDockedTheMomentItIsFirstShown;
var
  SB: TScrollBoxAccess;
  child: TControl;
  bw, thick, drifted: Integer;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  child := MakeChild(SB, 0, 0, 200, 900);   { 只纵向溢出 -> 只有纵条 }
  SB.UpdateScrollRange;
  AssertTrue('前置:纵条出来了', SB.VBar.Visible);
  AssertFalse('前置:横条还藏着', SB.HBar.Visible);

  SB.CallScrollByDelta(0, 60);
  drifted := SB.HBar.Top;
  AssertTrue(Format('前置:藏着的横条确实跟着漂了(top=%d)—— 这一条要是不成立,'
    + '下面量的就不是这个题目了', [drifted]), drifted <> 0);

  { 内容加宽,横条第一次露面。 }
  child.Width := 900;
  SB.UpdateScrollRange;
  AssertTrue('横条露面了', SB.HBar.Visible);

  bw := SB.Frame;
  thick := SB.VBar.Width;      { 两条同厚 —— 就是 ScrollbarThick }
  AssertEquals('露面时它左端贴着框内边,而不是停在漂过的位置',
    bw, SB.HBar.Left);
  AssertEquals('露面时它贴着框的下内边', SB.Height - thick - bw, SB.HBar.Top);
  AssertTrue(Format('而且它确实不在漂过的位置上(漂到 %d,停在 %d)',
    [drifted, SB.HBar.Top]), SB.HBar.Top <> drifted);
end;

procedure TTyScrollBoxTest.TestHiddenBarIsDockedWhenItComesBackAfterBeingHidden;
var
  SB: TScrollBoxAccess;
  child: TControl;
  bw, thick, docked, drifted: Integer;
begin
  { 第二条路:先让它露过面(于是 FHBarRect 非空),再藏起来漂,再回来。 }
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  child := MakeChild(SB, 0, 0, 900, 900);   { 两轴都溢出 }
  SB.UpdateScrollRange;
  AssertTrue('前置:两条都出来了', SB.VBar.Visible and SB.HBar.Visible);
  docked := SB.HBar.Top;

  child.Width := 100;                        { 横向装得下了 -> 横条收起来 }
  SB.UpdateScrollRange;
  AssertFalse('前置:横条藏起来了', SB.HBar.Visible);

  SB.CallScrollByDelta(0, 60);
  drifted := SB.HBar.Top;
  AssertTrue(Format('前置:藏着之后它又漂了(%d -> %d)。这一条**红了不一定是坏事**:'
    + '把 RedockBars 里的 `.Visible and` 去掉,停靠过的条就不再漂,这里就会红在 %d -> %d 上。'
    + '真要那么改,先读 RedockBars 的注释 —— 那一改修不了它想修的那个现象'
    + '(从没停靠过的条 FVBarRect/FHBarRect 恒为空,照样漏掉),代价是每条藏着的条'
    + '每滚一步多一次 SetBounds。改完把这一条改成断言"不漂"。', [docked, drifted, docked, drifted]),
    drifted <> docked);

  child.Width := 900;                        { 回来 }
  SB.UpdateScrollRange;
  AssertTrue('横条又露面了', SB.HBar.Visible);
  bw := SB.Frame;
  thick := SB.VBar.Width;
  AssertEquals('回来时仍旧贴着框内左边', bw, SB.HBar.Left);
  AssertEquals('回来时仍旧贴着框的下内边', SB.Height - thick - bw, SB.HBar.Top);
end;

{ ── 滚轮:第一格 ───────────────────────────────────────────────────────── }

{ 真滚轮走的是 WndProc:LCL 把 WM_MOUSEWHEEL 变成一条 LM_MOUSEWHEEL 派发给控件,
  由 TControl.WMMouseWheel 接住再调 DoMouseWheel。这里照那条路投递,而不是直接调
  DoMouseWheel —— 报的是"第一格",而第一格与后面的差别只可能出在路上。 }
procedure WheelTick(ATarget: TControl; ADelta: Integer);
var
  msg: TLMMouseEvent;
begin
  FillChar(msg{%H-}, SizeOf(msg), 0);
  msg.Msg := LM_MOUSEWHEEL;
  msg.WheelDelta := ADelta;
  ATarget.Dispatch(msg);
end;

procedure TTyScrollBoxTest.TestFirstWheelTickGoesTheSameWayAsTheSecond;
var
  SB: TScrollBoxAccess;
  y0, y1, y2, y3: Integer;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 0, 0, 100, 900);
  SB.UpdateScrollRange;
  AssertTrue('前置条件:有垂直条', SB.VBar.Visible);
  SB.ScrollTo(0, 0);

  y0 := SB.ScrollY;
  WheelTick(SB, -120);                { 第一格:向下 }
  y1 := SB.ScrollY;
  WheelTick(SB, -120);                { 第二格:同向 }
  y2 := SB.ScrollY;
  WheelTick(SB, -120);
  y3 := SB.ScrollY;

  AssertTrue(Format('第一格向下滚就要动(%d -> %d)', [y0, y1]), y1 > y0);
  AssertEquals('第一格与第二格步长相同', y1 - y0, y2 - y1);
  AssertEquals('第三格也一样', y2 - y1, y3 - y2);
end;

procedure TTyScrollBoxTest.TestWheelIsSymmetricAndClampsAtTheTop;
var
  SB: TScrollBoxAccess;
  down, back: Integer;
begin
  SB := TScrollBoxAccess.Create(FForm);
  SB.Parent := FForm;
  SB.Font.PixelsPerInch := 96;
  SB.SetBounds(0, 0, 300, 200);
  MakeChild(SB, 0, 0, 100, 900);
  SB.UpdateScrollRange;
  SB.ScrollTo(0, 0);

  { 顶端向上滚一格:必须原地不动,不能反向跑出去。 }
  WheelTick(SB, 120);
  AssertEquals('顶端向上滚不动', 0, SB.ScrollY);

  WheelTick(SB, -120);
  down := SB.ScrollY;
  AssertTrue('向下滚动了', down > 0);
  WheelTick(SB, 120);
  back := SB.ScrollY;
  AssertEquals('一下一上回到原点(两个方向步长相同)', 0, back);
  AssertTrue('前置条件:确实来回走了一格', down > back);
end;

{ ── 视口的容器契约 ──────────────────────────────────────────────────────── }

type
  TViewportAccess = class(TTyScrollContent)
  public
    { LCL 摆放子控件时真正用的那个矩形:
        TWinControl.AlignControl:  ARect := GetLogicalClientRect;
        TWinControl.AlignControls: AdjustClientRect(ARect); }
    function ChildArea: TRect;
  end;

function TViewportAccess.ChildArea: TRect;
begin
  Result := GetLogicalClientRect;
  AdjustClientRect(Result);
end;

procedure TTyScrollViewportTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
end;

procedure TTyScrollViewportTest.TearDown;
begin
  FreeAndNil(FForm);
end;

function MakeBoxWithViewport(AForm: TForm; out AVp: TViewportAccess;
  AChildW, AChildH: Integer): TScrollBoxAccess;
var
  kid: TTyPanel;
begin
  Result := TScrollBoxAccess.Create(AForm);
  Result.Parent := AForm;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, 300, 200);
  AVp := TViewportAccess.Create(Result);
  AVp.Parent := Result;
  if (AChildW > 0) and (AChildH > 0) then
  begin
    kid := TTyPanel.Create(AVp);
    kid.Parent := AVp;
    kid.SetBounds(0, 0, AChildW, AChildH);
  end;
  Result.UpdateScrollRange;
end;

procedure TTyScrollViewportTest.TestViewportOriginIsZeroBeforeAnyScroll;
var
  SB: TScrollBoxAccess;
  vp: TViewportAccess;
begin
  SB := MakeBoxWithViewport(FForm, vp, 100, 600);
  AssertEquals('没滚动时视口的布局原点就是 0', 0, vp.ChildArea.Top);
  AssertEquals('横向同理', 0, vp.ChildArea.Left);
  AssertEquals('前置条件:还没滚', 0, SB.ScrollY);
end;

procedure TTyScrollViewportTest.TestViewportLayoutOriginFollowsTheScrollOffset;
var
  SB: TScrollBoxAccess;
  vp: TViewportAccess;
begin
  { 这一条就是"视口里的对齐子控件不滚"的根因。子控件的 Left/Top 被 ScrollBy 搬成了
    **已滚动**坐标,视口的布局原点却还停在 0 —— 于是每一轮 realign 都把对齐的那些
    原样拉回去,滑块走了、内容没动。 }
  SB := MakeBoxWithViewport(FForm, vp, 100, 600);
  AssertTrue('前置条件:内容溢出,有垂直条', SB.VBar.Visible);
  SB.CallScrollByDelta(0, 120);
  AssertEquals('前置条件:盒子的偏移真的走到了 120', 120, SB.ScrollY);
  AssertEquals('视口的布局原点跟着偏移走', -120, vp.ChildArea.Top);
end;

procedure TTyScrollViewportTest.TestViewportLayoutAreaGrowsToTheContent;
var
  SB: TScrollBoxAccess;
  vp: TViewportAccess;
begin
  { 溢出的对齐行要有地方堆:DoAlign(alTop) 把running offset 钳在这个矩形的 Bottom 上,
    不涨的话越过折线的每一行都会叠在最后一行可见的那一行上。 }
  SB := MakeBoxWithViewport(FForm, vp, 100, 600);
  AssertTrue('前置条件:测到了 600 的内容高', SB.ContentHeight >= 600);
  AssertEquals('视口的布局区涨到了内容高', 600,
    vp.ChildArea.Bottom - vp.ChildArea.Top);
end;

procedure TTyScrollViewportTest.TestViewportLayoutAreaStaysTheViewportWhenContentFits;
var
  SB: TScrollBoxAccess;
  vp: TViewportAccess;
begin
  { 无条件涨会把轴**锁死**:对齐子控件的尺寸来自这个矩形、又反过来喂给内容测量,
    涨一次就再也回不来。放得下的时候必须还是视口本身那么大。 }
  SB := MakeBoxWithViewport(FForm, vp, 60, 40);
  AssertFalse('前置条件:放得下,没有条', SB.VBar.Visible);
  AssertEquals('布局区就是视口高', vp.Height, vp.ChildArea.Bottom - vp.ChildArea.Top);
  AssertEquals('布局区就是视口宽', vp.Width, vp.ChildArea.Right - vp.ChildArea.Left);
end;

initialization
  RegisterTest(TTyScrollBoxMathTest);
  RegisterTest(TTyScrollBoxTest);
  RegisterTest(TTyScrollViewportTest);
end.
