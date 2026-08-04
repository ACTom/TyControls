unit test.parity.container;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, TypInfo, Controls, Forms, Graphics, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Base, tyControls.Panel, tyControls.ScrollBox, tyControls.TabStrip,
  tyControls.TabSheet, tyControls.PageControl, tyControls.Splitter;

type
  { The dock probe. The audit claimed TTyPanel could not be a dock site "at all"; the
    counter-claim was that every member is TWinControl's and a republish would do. Neither
    can be settled by reading -- our AdjustClientRect/surface structure could be blocking
    LCL's dock manager -- so this docks a real control into a real TTyPanel and asserts
    what actually happened. }
  TTyContainerDockProbe = class(TTestCase)
  published
    procedure ManualDockReparentsTheClientIntoThePanel;
    procedure DockSiteTracksItsDockClients;
    procedure UndockingReleasesTheClient;
    procedure DockDropNotificationReachesTheSite;
    procedure TheDockSurfaceIsReachableFromTheDesigner;
  end;

  { TTyPanel's caption axis, its child gutter and its accessibility identity. }
  TTyPanelMemberParity = class(TTestCase)
  published
    procedure BorderWidthInsetsTheChildArea;
    procedure BorderWidthOfZeroChangesNothing;
    procedure VerticalAlignmentMovesTheCaptionInk;
    procedure WordWrapPutsInkOnASecondLine;
    procedure ShowAccelCharEatsTheAmpersand;
    procedure ShowAccelCharOffPaintsTheAmpersand;
    procedure PanelAnnouncesItselfAsAGroup;
    procedure SplitterAnnouncesItselfAsAResizeGrip;
    procedure TheNewCaptionMembersAreReachableFromTheDesigner;
  end;

  { TTyScrollBox: the ScrollBy meaning, ScrollInView, UpdateScrollbars. }
  TTyScrollBoxMemberParity = class(TTestCase)
  private
    FForm: TForm;
    FBox: TTyScrollBox;
    FTall: TTyPanel;
    procedure BuildOverflowingBox;
  protected
    procedure TearDown; override;
  published
    procedure ScrollByScrollsTheViewNotJustTheChildren;
    procedure ScrollByLeavesTheScrollbarsDocked;
    procedure ScrollByAgreesWithTheLclSignConvention;
    procedure ScrollInViewBringsAnOffscreenChildIn;
    procedure ScrollInViewLeavesAVisibleChildAlone;
    procedure UpdateScrollbarsIsUpdateScrollRange;
    procedure OnConstrainedResizeIsReachableFromTheDesigner;
  end;

  { The tab family's LCL-named members. }
  TTyTabMemberParity = class(TTestCase)
  private
    FForm: TForm;
    FPager: TTyPageControl;
    procedure BuildPager(ACount: Integer);
  protected
    procedure TearDown; override;
  published
    procedure TabRectFollowsTheScrollOffset;
    procedure IndexOfTabAtNamesTheTabUnderThePoint;
    procedure IndexOfTabAtSaysMinusOneOffTheTabs;
    procedure IndexOfTabAtSaysMinusOneBelowTheBand;
    procedure DisplayRectIsTheBodyBelowTheBand;
    procedure ScrollTabsCountsInTabsNotPixels;
    procedure AddTabSheetCreatesAPage;
    procedure IndexOfPageAtNamesTheShownPage;
    procedure PageControlReadsAndWritesTheHost;
    procedure PageIndexMovesThePage;
    procedure OnShowAndOnHideFireOnTheSwitch;
    procedure ReorderKeepsTheShownPageOnTheSelectedTab;
    procedure PageGeometryIsNotStreamed;
  end;

implementation

type
  TPanelInk = class(TTyPanel)
  public
    procedure Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure PublicAdjustClientRect(var ARect: TRect);
  end;

procedure TPanelInk.Render(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;

{ AdjustClientRect is protected and the headless runner never runs LCL's align pass, so the
  rule is driven through its own seam rather than asserted on a child's Left after a
  SetBounds -- which would be fake-green either way. }
procedure TPanelInk.PublicAdjustClientRect(var ARect: TRect);
begin
  AdjustClientRect(ARect);
end;

{ Ink helpers: render the panel onto a white bitmap and report where the dark pixels are. }
function InkRows(APanel: TPanelInk; AW, AH: Integer; out ATop, ABottom, ACount: Integer): Boolean;
var
  bmp: TBitmap;
  reread: TBGRABitmap;
  x, y: Integer;
  px: TBGRAPixel;
begin
  ATop := -1; ABottom := -1; ACount := 0;
  bmp := TBitmap.Create;
  try
    bmp.PixelFormat := pf32bit;
    bmp.SetSize(AW, AH);
    bmp.Canvas.Brush.Color := clWhite;
    bmp.Canvas.FillRect(0, 0, AW, AH);
    APanel.Font.PixelsPerInch := 96;
    APanel.Render(bmp.Canvas, Rect(0, 0, AW, AH), 96);
    reread := TBGRABitmap.Create(bmp);
    try
      for y := 0 to AH - 1 do
        for x := 0 to AW - 1 do
        begin
          px := reread.GetPixel(x, y);
          if (px.red < 160) and (px.green < 160) and (px.blue < 160) then
          begin
            if ATop < 0 then ATop := y;
            ABottom := y;
            Inc(ACount);
          end;
        end;
    finally
      reread.Free;
    end;
  finally
    bmp.Free;
  end;
  Result := ACount > 0;
end;

type
  { OnDockDrop is a method pointer, so the probe needs an object to hang it on. }
  TDockSpy = class
  public
    Dropped: Integer;
    Undocked: Integer;
    Shown: Integer;
    procedure HandleDockDrop(Sender: TObject; Source: TDragDockObject; X, Y: Integer);
    procedure HandleUnDock(Sender: TObject; Client: TControl;
      NewTarget: TWinControl; var Allow: Boolean);
    procedure HandleShowHide(Sender: TObject);
  end;

procedure TDockSpy.HandleShowHide(Sender: TObject);
begin
  Inc(Shown);
end;

procedure TDockSpy.HandleDockDrop(Sender: TObject; Source: TDragDockObject; X, Y: Integer);
begin
  Inc(Dropped);
end;

procedure TDockSpy.HandleUnDock(Sender: TObject; Client: TControl;
  NewTarget: TWinControl; var Allow: Boolean);
begin
  Inc(Undocked);
  Allow := True;
end;

procedure TTyContainerDockProbe.ManualDockReparentsTheClientIntoThePanel;
var
  Form: TForm;
  Site, Client: TTyPanel;
begin
  Form := TForm.CreateNew(nil);
  try
    Form.SetBounds(0, 0, 400, 300);
    Site := TTyPanel.Create(Form);
    Site.Parent := Form;
    Site.SetBounds(0, 0, 200, 200);
    Site.DockSite := True;

    Client := TTyPanel.Create(Form);
    Client.Parent := Form;
    Client.SetBounds(220, 0, 100, 100);
    Client.DragKind := dkDock;

    Client.ManualDock(Site, nil, alClient);

    AssertSame('a manual dock must reparent the client into the site',
      TWinControl(Site), TWinControl(Client.Parent));
    AssertSame('HostDockSite must name the site it was docked into',
      TWinControl(Site), TWinControl(Client.HostDockSite));
  finally
    Form.Free;
  end;
end;

procedure TTyContainerDockProbe.DockSiteTracksItsDockClients;
var
  Form: TForm;
  Site, Client: TTyPanel;
begin
  Form := TForm.CreateNew(nil);
  try
    Form.SetBounds(0, 0, 400, 300);
    Site := TTyPanel.Create(Form);
    Site.Parent := Form;
    Site.SetBounds(0, 0, 200, 200);
    Site.DockSite := True;
    AssertEquals('a fresh dock site has no dock clients', 0, Site.DockClientCount);

    Client := TTyPanel.Create(Form);
    Client.Parent := Form;
    Client.DragKind := dkDock;
    Client.ManualDock(Site, nil, alClient);

    AssertEquals('the docked control must appear in the site''s dock client list',
      1, Site.DockClientCount);
    AssertSame('and it must be the control we docked',
      TObject(Client), TObject(Site.DockClients[0]));
  finally
    Form.Free;
  end;
end;

{ Re-docking to a SECOND site rather than floating out. Floating (ManualDock(nil)) has to
  create a top-level host window, which the headless runner cannot do -- that is the test
  harness, not the control -- so the release half is exercised the way it can be observed
  here: the client must leave the first site's list and appear in the second's. }
procedure TTyContainerDockProbe.UndockingReleasesTheClient;
var
  Form: TForm;
  SiteA, SiteB, Client: TTyPanel;
begin
  Form := TForm.CreateNew(nil);
  try
    Form.SetBounds(0, 0, 400, 300);
    SiteA := TTyPanel.Create(Form);
    SiteA.Parent := Form;
    SiteA.SetBounds(0, 0, 200, 200);
    SiteA.DockSite := True;
    SiteB := TTyPanel.Create(Form);
    SiteB.Parent := Form;
    SiteB.SetBounds(200, 0, 200, 200);
    SiteB.DockSite := True;

    Client := TTyPanel.Create(Form);
    Client.Parent := Form;
    Client.DragKind := dkDock;
    Client.ManualDock(SiteA, nil, alClient);
    AssertEquals('precondition: docked into A', 1, SiteA.DockClientCount);

    Client.ManualDock(SiteB, nil, alClient);
    AssertEquals('leaving a site must drop the client from its dock list',
      0, SiteA.DockClientCount);
    AssertEquals('and add it to the new site''s', 1, SiteB.DockClientCount);
    AssertSame('HostDockSite must follow the move',
      TWinControl(SiteB), TWinControl(Client.HostDockSite));
  finally
    Form.Free;
  end;
end;

procedure TTyContainerDockProbe.DockDropNotificationReachesTheSite;
var
  Form: TForm;
  Site, SiteB, Client: TTyPanel;
  Spy: TDockSpy;
begin
  Spy := TDockSpy.Create;
  Form := TForm.CreateNew(nil);
  try
    Form.SetBounds(0, 0, 400, 300);
    Site := TTyPanel.Create(Form);
    Site.Parent := Form;
    Site.SetBounds(0, 0, 200, 200);
    Site.DockSite := True;
    Site.OnDockDrop := @Spy.HandleDockDrop;
    Site.OnUnDock := @Spy.HandleUnDock;
    SiteB := TTyPanel.Create(Form);
    SiteB.Parent := Form;
    SiteB.SetBounds(200, 0, 200, 200);
    SiteB.DockSite := True;

    Client := TTyPanel.Create(Form);
    Client.Parent := Form;
    Client.DragKind := dkDock;
    Client.ManualDock(Site, nil, alClient);
    AssertEquals('OnDockDrop must fire on the site when a client lands', 1, Spy.Dropped);

    Client.ManualDock(SiteB, nil, alClient);
    AssertEquals('OnUnDock must fire on the site when a client leaves', 1, Spy.Undocked);
  finally
    Form.Free;
    Spy.Free;
  end;
end;

{ The probe above proves the dock MACHINERY works, but it cannot guard the republish:
  DockSite, UseDockManager, OnDockDrop, OnDockOver and OnUnDock are PUBLIC on TWinControl,
  so every line of it compiled before the republish too. What the republish adds is the
  designer/.lfm surface -- plus OnGetSiteInfo, OnGetDockCaption, OnStartDock and OnEndDock,
  which are protected upstream and had no route at all. RTTI is what sees that difference. }
procedure TTyContainerDockProbe.TheDockSurfaceIsReachableFromTheDesigner;
const
  Names: array[0..8] of string = ('DockSite', 'UseDockManager', 'OnDockDrop', 'OnDockOver',
    'OnUnDock', 'OnGetSiteInfo', 'OnGetDockCaption', 'OnStartDock', 'OnEndDock');
var
  I: Integer;
begin
  for I := Low(Names) to High(Names) do
    AssertTrue('TTyPanel must publish ' + Names[I],
      GetPropInfo(TTyPanel, Names[I]) <> nil);
end;

{ --- TTyPanel ------------------------------------------------------------------- }

procedure TTyPanelMemberParity.BorderWidthInsetsTheChildArea;
var
  P: TPanelInk;
  R0, R8: TRect;
begin
  P := TPanelInk.Create(nil);
  try
    P.SetBounds(0, 0, 200, 100);
    R0 := Rect(0, 0, 200, 100);
    P.PublicAdjustClientRect(R0);
    P.BorderWidth := 8;
    R8 := Rect(0, 0, 200, 100);
    P.PublicAdjustClientRect(R8);
    AssertEquals('BorderWidth must move the child area''s left edge in by 8',
      R0.Left + 8, R8.Left);
    AssertEquals('...its top edge', R0.Top + 8, R8.Top);
    AssertEquals('...its right edge', R0.Right - 8, R8.Right);
    AssertEquals('...its bottom edge', R0.Bottom - 8, R8.Bottom);
  finally
    P.Free;
  end;
end;

procedure TTyPanelMemberParity.BorderWidthOfZeroChangesNothing;
var
  P: TPanelInk;
  R: TRect;
begin
  P := TPanelInk.Create(nil);
  try
    P.SetBounds(0, 0, 200, 100);
    R := Rect(0, 0, 200, 100);
    P.PublicAdjustClientRect(R);
    AssertEquals('the default (0) must leave the client area exactly as it was', 0, R.Left);
    AssertEquals('', 0, R.Top);
    AssertEquals('', 200, R.Right);
    AssertEquals('', 100, R.Bottom);
  finally
    P.Free;
  end;
end;

procedure TTyPanelMemberParity.VerticalAlignmentMovesTheCaptionInk;
  function Centre(AV: TTextLayout): Double;
  var
    P: TPanelInk;
    t, b, n: Integer;
  begin
    P := TPanelInk.Create(nil);
    try
      P.Caption := 'Hi';
      P.VerticalAlignment := AV;
      if not InkRows(P, 160, 80, t, b, n) then Exit(-1);
      Result := (t + b) / 2;
    finally
      P.Free;
    end;
  end;
var
  top, mid, bot: Double;
begin
  top := Centre(tlTop);
  mid := Centre(tlCenter);
  bot := Centre(tlBottom);
  AssertTrue('a top-aligned caption must have ink', top > 0);
  AssertTrue('tlTop must sit above tlCenter', top < mid - 8);
  AssertTrue('tlBottom must sit below tlCenter', bot > mid + 8);
end;

procedure TTyPanelMemberParity.WordWrapPutsInkOnASecondLine;
  function InkHeight(AWrap: Boolean): Integer;
  var
    P: TPanelInk;
    t, b, n: Integer;
  begin
    P := TPanelInk.Create(nil);
    try
      P.Caption := 'wrapping this caption over more than one single line';
      P.WordWrap := AWrap;
      P.VerticalAlignment := tlTop;
      if not InkRows(P, 90, 90, t, b, n) then Exit(0);
      Result := b - t + 1;
    finally
      P.Free;
    end;
  end;
var
  flat, wrapped: Integer;
begin
  flat := InkHeight(False);
  wrapped := InkHeight(True);
  AssertTrue('the unwrapped caption must be one line of ink', flat > 0);
  AssertTrue('wrapping must make the caption taller than one line (was ' +
    IntToStr(flat) + ', wrapped ' + IntToStr(wrapped) + ')', wrapped > flat + 4);
end;

{ Off, the '&' is a character like any other and paints; on, it is eaten. Ink COUNT is the
  observable: the same caption minus one glyph. (The underline itself only shows while Alt
  is physically held, which a headless run cannot arrange.) }
procedure TTyPanelMemberParity.ShowAccelCharEatsTheAmpersand;
var
  P: TPanelInk;
  t, b, nWith, nPlain: Integer;
begin
  P := TPanelInk.Create(nil);
  try
    P.Caption := 'File &Options';
    P.ShowAccelChar := True;
    InkRows(P, 200, 40, t, b, nWith);
  finally
    P.Free;
  end;
  P := TPanelInk.Create(nil);
  try
    P.Caption := 'File Options';   // what the '&' version must end up looking like
    P.ShowAccelChar := True;
    InkRows(P, 200, 40, t, b, nPlain);
  finally
    P.Free;
  end;
  AssertTrue('the caption must paint something', nPlain > 0);
  AssertEquals('with ShowAccelChar the ''&'' must be consumed, not painted',
    nPlain, nWith);
end;

procedure TTyPanelMemberParity.ShowAccelCharOffPaintsTheAmpersand;
var
  P: TPanelInk;
  t, b, nAmp, nPlain: Integer;
begin
  P := TPanelInk.Create(nil);
  try
    P.Caption := 'File &Options';
    InkRows(P, 200, 40, t, b, nAmp);      // ShowAccelChar defaults False
  finally
    P.Free;
  end;
  P := TPanelInk.Create(nil);
  try
    P.Caption := 'File Options';
    InkRows(P, 200, 40, t, b, nPlain);
  finally
    P.Free;
  end;
  AssertTrue('with the feature off the ampersand is an ordinary character and must paint ' +
    '(amp ' + IntToStr(nAmp) + ' vs plain ' + IntToStr(nPlain) + ')', nAmp > nPlain);
end;

procedure TTyPanelMemberParity.PanelAnnouncesItselfAsAGroup;
var
  P: TTyPanel;
begin
  P := TTyPanel.Create(nil);
  try
    AssertTrue('a container must announce itself as a group, not as larUnknown',
      P.AccessibleRole = larGroup);
  finally
    P.Free;
  end;
end;

procedure TTyPanelMemberParity.SplitterAnnouncesItselfAsAResizeGrip;
var
  S: TTySplitter;
begin
  S := TTySplitter.Create(nil);
  try
    AssertTrue('a splitter must announce itself as a resize grip',
      S.AccessibleRole = larResizeGrip);
  finally
    S.Free;
  end;
end;

procedure TTyPanelMemberParity.TheNewCaptionMembersAreReachableFromTheDesigner;
begin
  AssertTrue('VerticalAlignment', GetPropInfo(TTyPanel, 'VerticalAlignment') <> nil);
  AssertTrue('WordWrap', GetPropInfo(TTyPanel, 'WordWrap') <> nil);
  AssertTrue('ShowAccelChar', GetPropInfo(TTyPanel, 'ShowAccelChar') <> nil);
end;

{ --- TTyScrollBox --------------------------------------------------------------- }

procedure TTyScrollBoxMemberParity.BuildOverflowingBox;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 500, 400);
  FBox := TTyScrollBox.Create(FForm);
  FBox.Parent := FForm;
  FBox.SetBounds(0, 0, 200, 150);
  FTall := TTyPanel.Create(FForm);
  FTall.Parent := FBox;
  FTall.Align := alNone;
  FTall.SetBounds(0, 0, 100, 600);   // taller than the viewport -> a vertical bar
  FBox.UpdateScrollRange;
end;

procedure TTyScrollBoxMemberParity.TearDown;
begin
  FreeAndNil(FForm);
  inherited TearDown;
end;

{ The headline of the whole item: ScrollBy is LCL's name for "scroll the view" on a
  scrolling container, and ours used to reach TWinControl's child-mover instead -- same
  name, same arity, same parameter types, no compile error, wrong answer. }
procedure TTyScrollBoxMemberParity.ScrollByScrollsTheViewNotJustTheChildren;
begin
  BuildOverflowingBox;
  AssertEquals('precondition: at the top', 0, FBox.ScrollY);
  FBox.ScrollBy(0, -50);
  AssertEquals('ScrollBy must move the box''s own scroll offset, not only the children',
    50, FBox.ScrollY);
end;

procedure TTyScrollBoxMemberParity.ScrollByLeavesTheScrollbarsDocked;
var
  I: Integer;
  C: TControl;
  BarTop: Integer;
begin
  BuildOverflowingBox;
  FBox.ScrollBy(0, -50);
  BarTop := MaxInt;
  for I := 0 to FBox.ControlCount - 1 do
  begin
    C := FBox.Controls[I];
    if (C <> FTall) and C.Visible and (C.Height > C.Width) then
      BarTop := C.Top;                   // the vertical bar
  end;
  AssertTrue('the vertical scrollbar must still exist after a ScrollBy', BarTop <> MaxInt);
  { The child-mover re-bounds EVERY child, the two scrollbars included, so the unfixed
    version dragged the bar 50px off the top of the box along with the content. }
  AssertTrue('a view scroll must leave the vertical bar docked, not carry it off with the ' +
    'content (bar top ' + IntToStr(BarTop) + ')', BarTop >= 0);
end;

{ LCL's arguments say how far the CONTENT moves. Negative DeltaY pushes the content up,
  which is scrolling DOWN. A fix that dropped the negation would still make the offset
  change -- and would scroll the wrong way. }
procedure TTyScrollBoxMemberParity.ScrollByAgreesWithTheLclSignConvention;
begin
  BuildOverflowingBox;
  FBox.ScrollBy(0, -40);
  AssertEquals('negative delta = content moves up = scrolled down', 40, FBox.ScrollY);
  FBox.ScrollBy(0, 25);
  AssertEquals('positive delta = content moves down = scrolled back up', 15, FBox.ScrollY);
end;

procedure TTyScrollBoxMemberParity.ScrollInViewBringsAnOffscreenChildIn;
var
  Deep: TTyPanel;
begin
  BuildOverflowingBox;
  Deep := TTyPanel.Create(FForm);
  Deep.Parent := FBox;
  Deep.Align := alNone;
  Deep.SetBounds(0, 500, 60, 20);     // well past the ~150px viewport
  FBox.UpdateScrollRange;
  AssertEquals('precondition: at the top', 0, FBox.ScrollY);
  FBox.ScrollInView(Deep);
  AssertTrue('ScrollInView must scroll far enough for the child''s bottom edge to be ' +
    'inside the viewport (offset ' + IntToStr(FBox.ScrollY) + ')',
    520 - FBox.ScrollY <= FBox.ClientHeight);
  AssertTrue('...and no further than it has to', FBox.ScrollY <= 520);
end;

procedure TTyScrollBoxMemberParity.ScrollInViewLeavesAVisibleChildAlone;
var
  Near: TTyPanel;
begin
  BuildOverflowingBox;
  Near := TTyPanel.Create(FForm);
  Near.Parent := FBox;
  Near.Align := alNone;
  Near.SetBounds(0, 10, 60, 20);      // already inside the viewport
  FBox.UpdateScrollRange;
  FBox.ScrollInView(Near);
  AssertEquals('a child already in view must not move the viewport', 0, FBox.ScrollY);
end;

procedure TTyScrollBoxMemberParity.UpdateScrollbarsIsUpdateScrollRange;
var
  W, H: Integer;
begin
  BuildOverflowingBox;
  FTall.SetBounds(0, 0, 100, 900);
  FBox.UpdateScrollbars;              // the LCL spelling must do the same job
  W := FBox.ContentWidth;
  H := FBox.ContentHeight;
  AssertEquals('UpdateScrollbars must re-measure the content extent', 900, H);
  AssertEquals('', 100, W);
end;

procedure TTyScrollBoxMemberParity.OnConstrainedResizeIsReachableFromTheDesigner;
begin
  AssertTrue('TTyScrollBox must publish OnConstrainedResize -- it is protected on TControl, ' +
    'so without a republish it is unreachable from code as well as from the OI',
    GetPropInfo(TTyScrollBox, 'OnConstrainedResize') <> nil);
end;

{ --- the tab family ------------------------------------------------------------- }

procedure TTyTabMemberParity.BuildPager(ACount: Integer);
var
  I: Integer;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 600, 400);
  FPager := TTyPageControl.Create(FForm);
  FPager.Parent := FForm;
  FPager.SetBounds(0, 0, 220, 200);
  for I := 1 to ACount do
    FPager.AddPage('Page ' + IntToStr(I));
end;

procedure TTyTabMemberParity.TearDown;
begin
  FreeAndNil(FForm);
  inherited TearDown;
end;

{ TabRect carries LCL's name, so it has to carry LCL's meaning: the rect AS DRAWN. The
  pre-existing TyTabHeaderRect is the unshifted one, and the two agree until the strip
  scrolls -- which is exactly when a caller placing a menu over a tab needs the difference. }
procedure TTyTabMemberParity.TabRectFollowsTheScrollOffset;
var
  Before, After, U0, U1: TRect;
begin
  BuildPager(12);                       // certain to overflow 220px
  FPager.SetHeaderScroll(0);
  AssertTrue('precondition: the strip really does overflow', FPager.TyMaxHeaderScroll > 60);
  Before := FPager.TabRect(3);
  U0     := FPager.TyTabHeaderRect(3);
  FPager.SetHeaderScroll(60);
  After  := FPager.TabRect(3);
  U1     := FPager.TyTabHeaderRect(3);
  AssertEquals('TabRect must move by exactly the scroll offset -- it is the rect AS DRAWN',
    Before.Left - 60, After.Left);
  AssertEquals('TyTabHeaderRect is the UNSHIFTED twin and must not have moved at all',
    U0.Left, U1.Left);
end;

procedure TTyTabMemberParity.IndexOfTabAtNamesTheTabUnderThePoint;
var
  R: TRect;
  I: Integer;
begin
  BuildPager(3);
  for I := 0 to 2 do
  begin
    R := FPager.TabRect(I);
    AssertEquals('the point in the middle of tab ' + IntToStr(I) + ' must resolve to it',
      I, FPager.IndexOfTabAt((R.Left + R.Right) div 2, (R.Top + R.Bottom) div 2));
  end;
end;

{ The distinction the drag-target helper cannot make. TyDropIndexAt clamps into
  [0, Count-1] and so names the LAST tab for a click on the empty strip past it; a context
  menu built on that would open on a tab the user never aimed at. }
procedure TTyTabMemberParity.IndexOfTabAtSaysMinusOneOffTheTabs;
var
  R: TRect;
  X, Y: Integer;
begin
  BuildPager(2);
  R := FPager.TabRect(1);
  X := R.Right + 20;                    // empty strip, past the last tab
  Y := (R.Top + R.Bottom) div 2;
  AssertTrue('precondition: the strip is not full', X < FPager.Width);
  AssertEquals('a point on the empty strip is on NO tab', -1, FPager.IndexOfTabAt(X, Y));
  AssertEquals('the drag-target helper is a different question and still clamps',
    1, FPager.TyDropIndexAt(X, 96));
end;

procedure TTyTabMemberParity.IndexOfTabAtSaysMinusOneBelowTheBand;
var
  R: TRect;
begin
  BuildPager(3);
  R := FPager.TabRect(0);
  AssertEquals('a point on the page BODY is on no tab', -1,
    FPager.IndexOfTabAt((R.Left + R.Right) div 2, R.Bottom + 30));
end;

procedure TTyTabMemberParity.DisplayRectIsTheBodyBelowTheBand;
var
  Body: TRect;
  Hdr: TRect;
begin
  BuildPager(3);
  Body := FPager.DisplayRect;
  Hdr := FPager.TabRect(0);
  AssertEquals('the body starts where the header band ends', Hdr.Bottom, Body.Top);
  AssertEquals('and runs to the control''s bottom', FPager.Height, Body.Bottom);
  AssertEquals('across its full width', FPager.Width, Body.Right);
end;

{ ScrollTabs is LCL's name and therefore LCL's UNIT: tabs. SetHeaderScroll takes device px,
  so a mechanical rename would have scrolled two pixels for ScrollTabs(2). }
procedure TTyTabMemberParity.ScrollTabsCountsInTabsNotPixels;
var
  Tab2ContentLeft, BandLeft: Integer;
begin
  BuildPager(12);
  FPager.SetHeaderScroll(0);
  AssertTrue('precondition: the strip overflows', FPager.TyMaxHeaderScroll > 0);
  Tab2ContentLeft := FPager.TyTabHeaderRect(2).Left;
  AssertTrue('precondition: two tabs are far more than two pixels (' +
    IntToStr(Tab2ContentLeft) + ')', Tab2ContentLeft > 2);

  FPager.ScrollTabs(2);

  BandLeft := FPager.TyTabScrollLeftRect.Right;   // where the visible band starts
  AssertEquals('two TABS of scroll must land tab 2 at the start of the visible band; a ' +
    'px-unit member wearing this name would have nudged the strip by two pixels',
    BandLeft, FPager.TabRect(2).Left);
end;

procedure TTyTabMemberParity.AddTabSheetCreatesAPage;
var
  Sheet: TTyTabSheet;
begin
  BuildPager(2);
  Sheet := FPager.AddTabSheet;
  AssertTrue('AddTabSheet must return a page', Sheet <> nil);
  AssertEquals('...owned by the pager', 3, FPager.PageCount);
  AssertSame('...and parented to it', TWinControl(FPager), TWinControl(Sheet.Parent));
  AssertEquals('LCL''s AddTabSheet takes no caption and invents none', '', Sheet.Caption);
end;

procedure TTyTabMemberParity.IndexOfPageAtNamesTheShownPage;
var
  Body: TRect;
  Hdr: TRect;
begin
  BuildPager(3);
  FPager.ActivePageIndex := 1;
  Body := FPager.DisplayRect;
  AssertEquals('a point on the body names the shown page', 1,
    FPager.IndexOfPageAt((Body.Left + Body.Right) div 2, (Body.Top + Body.Bottom) div 2));
  Hdr := FPager.TabRect(0);
  AssertEquals('a point on the tab band is not a page hit', -1,
    FPager.IndexOfPageAt((Hdr.Left + Hdr.Right) div 2, (Hdr.Top + Hdr.Bottom) div 2));
end;

procedure TTyTabMemberParity.PageControlReadsAndWritesTheHost;
var
  Other: TTyPageControl;
  Sheet: TTyTabSheet;
begin
  BuildPager(2);
  Sheet := FPager.Pages[0];
  AssertSame('reading PageControl must name the host', TObject(FPager),
    TObject(Sheet.PageControl));
  Other := TTyPageControl.Create(FForm);
  Other.Parent := FForm;
  Other.SetBounds(240, 0, 200, 200);
  Sheet.PageControl := Other;
  AssertSame('assigning it must move the page to the other pager', TObject(Other),
    TObject(Sheet.PageControl));
  AssertEquals('the old pager loses the page', 1, FPager.PageCount);
  AssertEquals('the new one gains it', 1, Other.PageCount);
end;

procedure TTyTabMemberParity.PageIndexMovesThePage;
var
  First: TTyTabSheet;
begin
  BuildPager(3);
  First := FPager.Pages[0];
  AssertEquals('precondition', 0, First.PageIndex);
  First.PageIndex := 2;
  AssertEquals('assigning PageIndex must MOVE the page', 2, First.PageIndex);
  AssertSame('...to that slot', TObject(First), TObject(FPager.Pages[2]));
  AssertEquals('...and the tab caption order must follow it',
    'Page 1', FPager.TabCaption(2));
end;

procedure TTyTabMemberParity.OnShowAndOnHideFireOnTheSwitch;
var
  Spy: TDockSpy;
begin
  Spy := TDockSpy.Create;
  try
    BuildPager(2);
    FPager.ActivePageIndex := 0;
    FPager.Pages[0].OnHide := @Spy.HandleShowHide;
    FPager.Pages[1].OnShow := @Spy.HandleShowHide;
    Spy.Shown := 0;
    FPager.ActivePageIndex := 1;
    AssertEquals('switching pages must fire the leaving page''s OnHide and the arriving ' +
      'page''s OnShow', 2, Spy.Shown);
  finally
    Spy.Free;
  end;
end;

{ Found while wiring PageIndex: the selection is pinned to the POSITION (the documented
  rule), but only the HEADER was following it. Visible belongs to the page object and
  nothing re-assigned it after the array was permuted, so dragging a tab past the selected
  one left the highlighted tab and the shown page disagreeing until the next click. }
procedure TTyTabMemberParity.ReorderKeepsTheShownPageOnTheSelectedTab;
begin
  BuildPager(3);
  FPager.ActivePageIndex := 0;
  FPager.MovePage(0, 2);
  AssertEquals('the selection stays on slot 0', 0, FPager.ActivePageIndex);
  AssertTrue('and the page now IN slot 0 is the one that is shown',
    FPager.Pages[0].Visible);
  AssertFalse('the moved page must have been hidden with its slot',
    FPager.Pages[2].Visible);
end;

procedure TTyTabMemberParity.PageGeometryIsNotStreamed;
const
  Names: array[0..5] of string = ('Left', 'Top', 'Width', 'Height', 'TabOrder', 'Visible');
var
  Sheet: TTyTabSheet;
  I: Integer;
begin
  BuildPager(1);
  Sheet := FPager.Pages[0];
  for I := Low(Names) to High(Names) do
    AssertFalse('the pager owns ' + Names[I] + ', so a page must not stream it',
      IsStoredProp(Sheet, Names[I]));
  AssertFalse('nor PageIndex -- the streaming order already carries it',
    IsStoredProp(Sheet, 'PageIndex'));
end;

initialization
  RegisterTest(TTyContainerDockProbe);
  RegisterTest(TTyPanelMemberParity);
  RegisterTest(TTyScrollBoxMemberParity);
  RegisterTest(TTyTabMemberParity);
end.
