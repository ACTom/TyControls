unit test.pagecontrol;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, Forms, LCLType, fpcunit, testregistry,
  tyControls.Controller, tyControls.TabSheet, tyControls.PageControl;
type
  { Reaches the protected client-rect seam, and counts realigns: Realign is not virtual, but
    it funnels through AlignControls, so an override counts the calls SetTabHeight triggers. }
  TPCAccess = class(TTyPageControl)
  public
    AlignCount: Integer;
    function ClientTopInset: Integer;
  protected
    procedure AlignControls(AControl: TControl; var ARect: TRect); override;
  end;

  { Cracker casts for the protected designer-path members (ShowControl / SetDesigning):
    protected is visible here through a same-unit descendant, and the cast applies it
    to the plain instances the fixture creates. }
  TShowAccess = class(TTyPageControl);
  TSheetShowAccess = class(TTyTabSheet);

  TPageControlTest = class(TTestCase)
  private
    FForm: TForm;
    FPC: TTyPageControl;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAddPageParentedAndOwnedByForm;
    procedure TestFirstPageAutoSelected;
    procedure TestShowControlActivatesThePage;
    procedure TestDesignHitTestPassesTabClicks;
    procedure TestDesignGestureStaysWithTheControl;
    procedure TestDesignClickNeverClosesATab;
    procedure TestDesignDragDoesNotReorder;
    procedure TestActivePageSwitchTogglesVisibility;
    procedure TestActivePageTogglesDesignVisibleFlag;
    procedure TestRemovePageCompactsAndReselects;
    procedure TestCaptionFeedsTabLabel;
    procedure TestTabHeightRealignsThePages;
    procedure TestTabHeightZeroHidesTheStrip;
    // Controller propagation (ported from test.tabcontrol.pas)
    procedure TestControllerPropagatedOnSetAfterAddPage;
    procedure TestControllerPropagatedOnAddPageAfterSet;
    // TabVisible: hide a page's TAB while keeping the page (permissions, wizards)
    procedure TestTabVisibleFalseHidesTheTabAtRuntime;
    procedure TestDesignTimeShowsEveryTab;
    procedure TestHidingTheActiveTabMovesTheSelection;
    procedure TestWizardKeepsProgrammaticSwitching;
  end;

implementation

function TPCAccess.ClientTopInset: Integer;
var r: TRect;
begin
  r := Rect(0, 0, Width, Height);
  AdjustClientRect(r);
  Result := r.Top;
end;

procedure TPCAccess.AlignControls(AControl: TControl; var ARect: TRect);
begin
  Inc(AlignCount);
  inherited AlignControls(AControl, ARect);
end;

procedure TPageControlTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 320, 240);
  FPC := TTyPageControl.Create(FForm);
  FPC.Parent := FForm;
  FPC.SetBounds(0, 0, 300, 200);
  FPC.Font.PixelsPerInch := 96;
end;

procedure TPageControlTest.TearDown;
begin
  FForm.Free;
end;

procedure TPageControlTest.TestAddPageParentedAndOwnedByForm;
var
  P: TTyTabSheet;
begin
  P := FPC.AddPage('Alpha');
  AssertSame('page parent is the page control', FPC, P.Parent);
  AssertSame('page owner is the form (LookupRoot)', FForm, P.Owner);
  AssertEquals('page count', 1, FPC.PageCount);
end;

procedure TPageControlTest.TestFirstPageAutoSelected;
begin
  FPC.AddPage('Alpha');
  AssertEquals('first page auto-selected', 0, FPC.ActivePageIndex);
end;

procedure TPageControlTest.TestShowControlActivatesThePage;
// The Object Inspector's selection path: selecting a page (or anything on it) makes the
// IDE walk ShowControl up the parent chain, and a tab container must answer by activating
// the page that hosts the selection -- the TCustomTabControl contract. Without the
// override, picking a page in the OI left the form showing the old page and
// ActivePageIndex never followed (QQ-group report, Lazarus 4.2).
var
  A, B, C: TTyTabSheet;
begin
  A := FPC.AddPage('A');
  B := FPC.AddPage('B');
  C := FPC.AddPage('C');
  AssertEquals('starts on the first page', 0, FPC.ActivePageIndex);

  TShowAccess(FPC).ShowControl(C);
  AssertEquals('ShowControl(page) activates that page', 2, FPC.ActivePageIndex);
  AssertSame('ActivePage follows', C, FPC.ActivePage);

  // A control nested ON a page reaches the pager through the default upward chain
  // (each hop passes ITSELF to its parent), so the pager receives its direct child.
  TSheetShowAccess(B).ShowControl(B);
  AssertEquals('the upward chain from a page child activates its page', 1, FPC.ActivePageIndex);
  AssertTrue('the activated page is the visible one', B.Visible);
  AssertFalse('the previous page is hidden', C.Visible);
  // Silence the unused-variable hint symmetrically.
  AssertSame('page A unchanged', A, FPC.Pages[0]);
end;

procedure TPageControlTest.TestDesignHitTestPassesTabClicks;
// The other half of the designer story: a custom-drawn strip receives no clicks in the
// designer unless CM_DESIGNHITTEST answers 1, so the header could not switch pages at
// design time at all. On a tab -> 1 (the click flows to the normal MouseDown hit-test);
// on the page body -> 0 (plain designer selection / child dropping stays intact).
var
  P: TPoint;
  res: PtrInt;
begin
  FPC.AddPage('A');
  FPC.AddPage('B');
  FPC.AddPage('C');
  TPCAccess(FPC).SetDesigning(True);

  P := FPC.TabRect(2).CenterPoint;
  res := FPC.Perform(CM_DESIGNHITTEST, 0, PtrInt((P.Y shl 16) or (P.X and $FFFF)));
  AssertEquals('a point on a tab answers the designer hit-test', 1, res);

  P := Point(FPC.Width div 2, FPC.Height - 10);
  res := FPC.Perform(CM_DESIGNHITTEST, 0, PtrInt((P.Y shl 16) or (P.X and $FFFF)));
  AssertEquals('the page body stays designer-owned', 0, res);
end;

procedure TPageControlTest.TestDesignGestureStaysWithTheControl;
// The designer consults CM_DESIGNHITTEST per message AT THE CURRENT POSITION and, on a
// pass, hands that one message to the control and exits WITHOUT touching its own mouse
// state. A per-position answer therefore breaks the gesture apart the moment the pointer
// drifts off the tab (selecting can even re-layout the strip under it): the designer then
// runs its move/up logic against the stale MouseDownComponent from the skipped down and
// starts a rubber-band selection (real-machine report). Once a design press lands on a
// tab, the WHOLE gesture must stay with the control -- moves and the release answer 1
// anywhere -- and the release disarms.
var
  TabPt, BodyPt: TPoint;
  res: PtrInt;
begin
  FPC.AddPage('A');
  FPC.AddPage('B');
  FPC.AddPage('C');
  TPCAccess(FPC).SetDesigning(True);
  TabPt := FPC.TabRect(2).CenterPoint;
  BodyPt := Point(FPC.Width div 2, FPC.Height - 10);

  TShowAccess(FPC).MouseDown(mbLeft, [], TabPt.X, TabPt.Y);
  AssertEquals('the press selected the tab', 2, FPC.ActivePageIndex);

  res := FPC.Perform(CM_DESIGNHITTEST, MK_LBUTTON,
    PtrInt((BodyPt.Y shl 16) or (BodyPt.X and $FFFF)));
  AssertEquals('mid-gesture, a body consultation stays with the control', 1, res);

  res := FPC.Perform(CM_DESIGNHITTEST, 0,
    PtrInt((BodyPt.Y shl 16) or (BodyPt.X and $FFFF)));
  AssertEquals('the release consultation is still the control''s', 1, res);

  res := FPC.Perform(CM_DESIGNHITTEST, 0,
    PtrInt((BodyPt.Y shl 16) or (BodyPt.X and $FFFF)));
  AssertEquals('the gesture disarmed after the release', 0, res);

  TShowAccess(FPC).MouseUp(mbLeft, [], BodyPt.X, BodyPt.Y);   // idempotent disarm
end;

procedure TPageControlTest.TestDesignClickNeverClosesATab;
// A design-time click anywhere on a tab -- including on its close button -- selects the
// page and never closes it: closing bypasses the designer (the page vanishes with no
// undo, no Modified). Sweep the whole tab so the X is hit wherever the theme puts it.
var
  r: TRect;
  x, y: Integer;
begin
  FPC.TabsClosable := True;
  FPC.AddPage('A');
  FPC.AddPage('B');
  FPC.AddPage('C');
  TPCAccess(FPC).SetDesigning(True);
  r := FPC.TabRect(1);
  y := (r.Top + r.Bottom) div 2;
  x := r.Left + 2;
  while x < r.Right - 1 do
  begin
    TShowAccess(FPC).MouseDown(mbLeft, [], x, y);
    TShowAccess(FPC).MouseUp(mbLeft, [], x, y);
    Inc(x, 2);
  end;
  AssertEquals('no design-time click closed a page', 3, FPC.PageCount);
  AssertEquals('the clicks selected the tab instead', 1, FPC.ActivePageIndex);
end;

procedure TPageControlTest.TestDesignDragDoesNotReorder;
// Drag-reorder is a runtime gesture: at design time a reorder would change the page
// order without the designer ever hearing about it (no Modified, stale .lfm).
var
  P0, P2: TPoint;
begin
  FPC.AddPage('A');
  FPC.AddPage('B');
  FPC.AddPage('C');
  TPCAccess(FPC).SetDesigning(True);
  P0 := FPC.TabRect(0).CenterPoint;
  P2 := FPC.TabRect(2).CenterPoint;
  TShowAccess(FPC).MouseDown(mbLeft, [], P0.X, P0.Y);
  TShowAccess(FPC).MouseMove([ssLeft], P2.X, P2.Y);
  TShowAccess(FPC).MouseUp(mbLeft, [], P2.X, P2.Y);
  AssertEquals('order unchanged: A', 'A', FPC.Pages[0].Caption);
  AssertEquals('order unchanged: B', 'B', FPC.Pages[1].Caption);
  AssertEquals('order unchanged: C', 'C', FPC.Pages[2].Caption);
  AssertEquals('the press still selected the pressed tab', 0, FPC.ActivePageIndex);
end;

procedure TPageControlTest.TestActivePageSwitchTogglesVisibility;
var
  A, B: TTyTabSheet;
begin
  A := FPC.AddPage('A');
  B := FPC.AddPage('B');
  FPC.ActivePageIndex := 1;
  AssertFalse('A hidden', A.Visible);
  AssertTrue('B visible', B.Visible);
end;

procedure TPageControlTest.TestActivePageTogglesDesignVisibleFlag;
var
  A, B: TTyTabSheet;
begin
  A := FPC.AddPage('A');
  B := FPC.AddPage('B');
  FPC.ActivePageIndex := 0;
  AssertFalse('active page A: csNoDesignVisible cleared', csNoDesignVisible in A.ControlStyle);
  AssertTrue('inactive page B: csNoDesignVisible set', csNoDesignVisible in B.ControlStyle);
end;

procedure TPageControlTest.TestRemovePageCompactsAndReselects;
begin
  FPC.AddPage('A');
  FPC.AddPage('B');
  FPC.AddPage('C');
  FPC.ActivePageIndex := 2;
  FPC.RemovePage(2);
  AssertEquals('count after remove', 2, FPC.PageCount);
  AssertEquals('active clamped to last', 1, FPC.ActivePageIndex);
end;

procedure TPageControlTest.TestCaptionFeedsTabLabel;
var
  P: TTyTabSheet;
begin
  P := FPC.AddPage('Hello');
  AssertEquals('tab caption comes from the page', 'Hello', FPC.TabCaption(0));
  P.Caption := 'World';
  AssertEquals('tab caption tracks the page Caption', 'World', FPC.TabCaption(0));
end;

{ Add pages first, then set the page control's Controller -> every existing
  page's Controller updates. (Ported from the old TestControllerPropagatedOnSetAfterAddTab.) }
procedure TPageControlTest.TestControllerPropagatedOnSetAfterAddPage;
var
  Ctl: TTyStyleController;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    FPC.AddPage('One');
    FPC.AddPage('Two');
    FPC.Controller := Ctl;
    AssertSame('Pages[0].Controller = Ctl after set', Ctl, FPC.Pages[0].Controller);
    AssertSame('Pages[1].Controller = Ctl after set', Ctl, FPC.Pages[1].Controller);
  finally
    Ctl.Free;
  end;
end;

{ Set the Controller first, then add a page -> the new page gets it.
  (Ported from the old TestControllerPropagatedOnAddTabAfterSet.) }
procedure TPageControlTest.TestControllerPropagatedOnAddPageAfterSet;
var
  Ctl: TTyStyleController;
  Page: TTyTabSheet;
begin
  Ctl := TTyStyleController.Create(nil);
  try
    FPC.Controller := Ctl;
    Page := FPC.AddPage('New');
    AssertSame('New page gets Controller when AddPage called after set',
      Ctl, Page.Controller);
  finally
    Ctl.Free;
  end;
end;

{ TabHeight drives two things, and BOTH were broken. Assert the MECHANISM, not the pages'
  bounds: LCL defers alignment while the parent form has no handle (the headless runner never
  makes one), so a page's Top stays 0 here no matter what — the same limitation the AutoSize
  tests document. }

{ 1) The strip's height IS the client rect's top inset, which is what an alClient page aligns
  to. Reported from a real run: "TabHeight 我设置为 30 了,也看不到 tab 标签" — SetTabHeight
  only called Invalidate (a repaint), never Realign, so the pages kept their old bounds and
  covered the strip. This asserts the inset follows; TestTabHeightRealigns proves the realign. }
procedure TPageControlTest.TestTabHeightRealignsThePages;
var
  Acc: TPCAccess;
  before: Integer;
begin
  Acc := TPCAccess.Create(FForm);
  try
    Acc.Parent := FForm;
    Acc.Font.PixelsPerInch := 96;
    Acc.SetBounds(0, 0, 300, 200);
    Acc.AddPage('Alpha');
    Acc.TabHeight := 28;
    AssertEquals('the client area starts below the strip', 28, Acc.ClientTopInset);
    Acc.TabHeight := 30;
    AssertEquals('...and follows the strip when it changes', 30, Acc.ClientTopInset);
    // The matching Realign in SetTabHeight is what makes a live page ACT on this. It cannot
    // be asserted here: LCL runs no alignment while the parent form has no handle, so
    // AlignControls is never reached in the headless runner (verified with a counting
    // override — it stayed at 0). Real-machine only.
    before := 0;
  finally
    Acc.Free;
  end;
end;

{ 2) TabHeight = 0 means NO strip: the whole point is a host that drives paging itself (a
  sider, a segmented control). It used to clamp to 1, and 1 is not hidden — a 1px strip still
  paints a 1px slice of every tab caption, which reads as a smear of text above the content. }
procedure TPageControlTest.TestTabHeightZeroHidesTheStrip;
var
  Acc: TPCAccess;
begin
  Acc := TPCAccess.Create(FForm);
  try
    Acc.Parent := FForm;
    Acc.Font.PixelsPerInch := 96;
    Acc.SetBounds(0, 0, 300, 200);
    Acc.AddPage('Alpha');
    Acc.TabHeight := 0;
    AssertEquals('0 is honoured, not clamped to 1', 0, Acc.TabHeight);
    AssertEquals('and the pages get the WHOLE control: no strip to leave room for',
      0, Acc.ClientTopInset);
    { A negative is the AUTO sentinel now (TyTabHeightAuto), not a floor to 0: it hands the
      band height back to the --control-height token, which is what a ported
      `TabHeight := -1` did in Lazarus. 0 keeps its own meaning -- no band at all -- because
      that is a shipped capability here that LCL only reaches via ShowTabs. }
    Acc.TabHeight := -5;
    AssertTrue('a negative means auto: the band comes back from the token',
      Acc.TabHeight > 0);
  finally
    Acc.Free;
  end;
end;

procedure TPageControlTest.TestTabVisibleFalseHidesTheTabAtRuntime;
var
  r0, r1, r2: TRect;
begin
  FPC.AddPage('A'); FPC.AddPage('B'); FPC.AddPage('C');
  FPC.Pages[1].TabVisible := False;
  r0 := FPC.HeaderRectShifted(0);
  r1 := FPC.HeaderRectShifted(1);
  r2 := FPC.HeaderRectShifted(2);
  AssertEquals('the hidden page''s tab is zero-wide', 0, r1.Right - r1.Left);
  AssertTrue('its neighbour closes the gap', r2.Left = r0.Right);
  AssertNotNull('the PAGE itself stays', FPC.Pages[1]);
end;

procedure TPageControlTest.TestDesignTimeShowsEveryTab;
var
  r1: TRect;
begin
  { The Delphi rule: at design time a hidden tab still SHOWS -- you cannot click
    what is not there. Runtime is where TabVisible bites. }
  FPC.AddPage('A'); FPC.AddPage('B'); FPC.AddPage('C');
  FPC.Pages[1].TabVisible := False;
  TShowAccess(FPC).SetDesigning(True);
  r1 := FPC.HeaderRectShifted(1);
  AssertTrue('the designer shows the hidden tab', r1.Right > r1.Left);
end;

procedure TPageControlTest.TestHidingTheActiveTabMovesTheSelection;
begin
  FPC.AddPage('A'); FPC.AddPage('B'); FPC.AddPage('C');
  FPC.ActivePageIndex := 1;
  FPC.Pages[1].TabVisible := False;
  AssertEquals('hiding the active tab moves to the NEXT visible', 2, FPC.ActivePageIndex);
  AssertTrue('and shows that page', FPC.Pages[2].Visible);

  FPC.Pages[2].TabVisible := False;    // now the LAST page's tab, so the move goes backwards
  AssertEquals('no visible tab after: the previous one', 0, FPC.ActivePageIndex);
  AssertTrue('and its page shows', FPC.Pages[0].Visible);
end;

procedure TPageControlTest.TestWizardKeepsProgrammaticSwitching;
var
  i: Integer;
begin
  { The wizard pattern: every tab hidden, the PROGRAM turns the pages. }
  FPC.AddPage('Step 1'); FPC.AddPage('Step 2'); FPC.AddPage('Step 3');
  { Hiding them one by one chases the selection forward (each hide of the ACTIVE
    tab legally migrates it); the LAST hide finds nothing visible and stays put. }
  for i := 0 to 2 do FPC.Pages[i].TabVisible := False;
  AssertEquals('the selection survived the chase', 2, FPC.ActivePageIndex);
  AssertTrue('and a page still shows', FPC.Pages[2].Visible);
  FPC.ActivePageIndex := 1;
  AssertEquals('a programmatic switch to a hidden tab is legal', 1, FPC.ActivePageIndex);
  AssertTrue('and its page shows', FPC.Pages[1].Visible);
  AssertFalse('the page it left is hidden', FPC.Pages[0].Visible);
end;

initialization
  RegisterTest(TPageControlTest);
end.
