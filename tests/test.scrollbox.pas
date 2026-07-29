unit test.scrollbox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller,
  tyControls.Base, tyControls.Panel, tyControls.ScrollBar, tyControls.ScrollBox;
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
      children here passes on the BROKEN code too. That coverage lives in the real-machine
      probe tests/scrollverify (cases 3, 4, 10, 11). }
    procedure TestClientRectExcludesBarGutters;
    procedure TestChildAreaExcludesBarGutters;
    procedure TestChildAreaGrowsToContentOnScrollingAxisOnly;
    procedure TestChildAreaFollowsScrollOffset;
    procedure TestChildAreaIsFullBoxWithoutBars;
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
  AssertEquals('child area gives up the vertical bar gutter', 300 - thick,
    area.Right - area.Left);
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
  AssertEquals('the still axis stays at the viewport', 300 - SB.VBar.Width,
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
  AssertEquals('unscrolled origin is 0', 0, area.Top);

  SB.VBar.Position := 120;
  AssertEquals('offset followed the bar', 120, SB.ScrollY);
  area := SB.ChildArea;
  AssertEquals('layout origin moved with the scroll', -120, area.Top);
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
  AssertEquals('full width when nothing overflows', 300, area.Right - area.Left);
  AssertEquals('full height when nothing overflows', 200, area.Bottom - area.Top);
  AssertEquals('origin unshifted', 0, area.Left);
  AssertEquals('origin unshifted', 0, area.Top);
end;

initialization
  RegisterTest(TTyScrollBoxMathTest);
  RegisterTest(TTyScrollBoxTest);
end.
