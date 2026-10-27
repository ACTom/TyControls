unit test.ribbon;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, Forms, LCLType, fpcunit, testregistry,
  tyControls.Base, tyControls.Ribbon, tyControls.PopupSurface, tyControls.Button;

type
  { Cracker for the protected designer-path members (SetDesigning). }
  TRibbonDesignAccess = class(TTyRibbon);

  TRibbonTest = class(TTestCase)
  private
    FChanged: Integer;
    procedure HandleChange(Sender: TObject);
  published
    procedure GroupContentRectSubtractsBand;
    procedure DesignHitTestPassesPageTabsNotFileChrome;
    procedure GroupContentRectClampsBand;
    procedure TypeKeys;
    procedure AddPageGrowsCountAndActivates;
    procedure TabCaptionFollowsPages;
    procedure RemovePageReindexesActive;
    procedure RemoveActivePageFiresOnChange;
    procedure ContextPageHiddenUntilContextShown;
    procedure HidingActiveContextReanchorsAndFires;
    procedure SettingContextHidesTabWhenInactive;
    procedure OverflowCountCollapsesTrailingGroups;
    procedure VisibleGroupCountFits;
    procedure CollapseRectAtRightEnd;
    procedure MinimizedCollapsesAndRestoresHeight;
    procedure FileTabRoundTripAndDefaults;
    procedure DefaultAligns;
    { The page keeps its groups in step after the first layout (#136): a freed group leaves the
      layout, one added later goes last, and one the application hid stays hidden. }
    procedure APageForgetsAFreedGroup;
    procedure AGroupAddedLaterGoesLast;
    procedure AHiddenGroupStaysHidden;
    procedure AnOverflowedGroupComesBackWithRoom;
    procedure AGroupHiddenWhileOverflowedStaysHidden;
    procedure AGroupMovedAwayIsForgotten;
    { Freed while the overflow fly-out holds it, where the page is not its parent. }
    procedure AGroupFreedInTheFlyOutIsForgotten;
  end;

implementation

type
  TRibbonPageAccess = class(TTyRibbonPage)
  public
    procedure Lay;
  end;

procedure TRibbonPageAccess.Lay;
var
  r: TRect;
begin
  r := Rect(0, 0, Width, Height);
  AlignControls(nil, r);
end;

const
  GroupW = 100;
  GroupGap = 9;   // the page's inter-group gap at 96 PPI

{ A page AWidth wide with three 100-px groups, laid out once; the groups come back in visual
  order, the ones that did not fit last. }
function MakeGroupPage(AForm: TForm; AWidth: Integer; out A, B, C: TTyRibbonGroup;
  AGroupOwner: TComponent = nil; AOwnGroups: Boolean = True): TRibbonPageAccess;
var
  g: array[0..2] of TTyRibbonGroup;
  i, j: Integer;
  t: TTyRibbonGroup;
begin
  Result := TRibbonPageAccess.Create(AForm);
  Result.Parent := AForm;
  Result.Align := alNone;
  Result.Font.PixelsPerInch := 96;
  Result.SetBounds(0, 0, AWidth, 100);
  Result.Visible := True;
  for i := 0 to 2 do
  begin
    if AOwnGroups then g[i] := TTyRibbonGroup.Create(AForm)
    else g[i] := TTyRibbonGroup.Create(AGroupOwner);
    g[i].Parent := Result;
    g[i].Width := GroupW;
  end;
  Result.Lay;
  for i := 1 to 2 do
    for j := i downto 1 do
      if (Ord(not g[j].Visible) * 100000 + g[j].Left)
         < (Ord(not g[j - 1].Visible) * 100000 + g[j - 1].Left) then
      begin
        t := g[j]; g[j] := g[j - 1]; g[j - 1] := t;
      end;
  A := g[0]; B := g[1]; C := g[2];
end;

procedure TRibbonTest.HandleChange(Sender: TObject);
begin
  Inc(FChanged);
end;

procedure TRibbonTest.GroupContentRectSubtractsBand;
var R: TRect;
begin
  // 96x80 group, 18px caption band -> content is 96 x 62.
  R := TyRibbonGroupContentRect(96, 80, 18);
  AssertEquals('left', 0, R.Left);
  AssertEquals('top', 0, R.Top);
  AssertEquals('width', 96, R.Right);
  AssertEquals('height above band', 80 - 18, R.Bottom);
end;

procedure TRibbonTest.DesignHitTestPassesPageTabsNotFileChrome;
// Ribbon side of the designer tab-click story: real page tabs answer the designer
// hit-test (so clicking them in the designer switches the page), while the File
// pseudo-tab keeps answering 0 -- it lives in x < HeaderLeftInset, outside the base's
// tab rects, so a designer click there still just selects the ribbon (no backstage
// mis-trigger). The collapse chevron and KeyTip chips sit outside the tab rects too.
var
  Rib: TTyRibbon;
  Pt: TPoint;
  res: PtrInt;
begin
  Rib := TTyRibbon.Create(nil);
  try
    Rib.Font.PixelsPerInch := 96;
    Rib.SetBounds(0, 0, 600, 140);
    Rib.FileTab := True;
    Rib.AddPage('Home');
    Rib.AddPage('Insert');
    TRibbonDesignAccess(Rib).SetDesigning(True);

    Pt := Rib.TabRect(0).CenterPoint;
    AssertTrue('fixture: the first page tab starts past the File tab',
      Pt.X > Rib.FileTabWidth);
    res := Rib.Perform(CM_DESIGNHITTEST, 0, PtrInt((Pt.Y shl 16) or (Pt.X and $FFFF)));
    AssertEquals('a page tab answers the designer hit-test', 1, res);

    Pt := Point(Rib.FileTabWidth div 2, Pt.Y);
    res := Rib.Perform(CM_DESIGNHITTEST, 0, PtrInt((Pt.Y shl 16) or (Pt.X and $FFFF)));
    AssertEquals('the File pseudo-tab stays designer-owned', 0, res);
  finally
    Rib.Free;
  end;
end;

procedure TRibbonTest.GroupContentRectClampsBand;
var R: TRect;
begin
  // A band taller than the group clamps to the height (empty content, not negative).
  R := TyRibbonGroupContentRect(50, 10, 30);
  AssertEquals('clamped bottom', 0, R.Bottom);
  R := TyRibbonGroupContentRect(50, 40, -5);   // negative band clamps to 0
  AssertEquals('neg band -> full height', 40, R.Bottom);
end;

procedure TRibbonTest.TypeKeys;
var
  Rib: TTyRibbon;
  Grp: TTyRibbonGroup;
begin
  Rib := TTyRibbon.Create(nil);
  Grp := TTyRibbonGroup.Create(nil);
  try
    AssertEquals('ribbon typeKey', 'TyRibbon', (Rib as ITyStyleable).GetStyleTypeKey);
    AssertEquals('group typeKey', 'TyRibbonGroup', (Grp as ITyStyleable).GetStyleTypeKey);
  finally
    Grp.Free;
    Rib.Free;
  end;
end;

procedure TRibbonTest.AddPageGrowsCountAndActivates;
var
  Rib: TTyRibbon;
  P1, P2: TTyRibbonPage;
begin
  Rib := TTyRibbon.Create(nil);
  try
    AssertEquals('empty', 0, Rib.PageCount);
    AssertEquals('no active index', -1, Rib.ActivePageIndex);
    P1 := Rib.AddPage('Home');
    AssertEquals('one page', 1, Rib.PageCount);
    AssertEquals('first auto-active', 0, Rib.ActivePageIndex);
    AssertTrue('active page is P1', Rib.ActivePage = P1);
    P2 := Rib.AddPage('Insert');
    AssertEquals('two pages', 2, Rib.PageCount);
    AssertEquals('active stays 0', 0, Rib.ActivePageIndex);
    Rib.ActivePage := P2;
    AssertEquals('active moved to 1', 1, Rib.ActivePageIndex);
  finally
    Rib.Free;   // owns P1/P2 (created with Owner=Rib when Rib.Owner=nil)
  end;
end;

procedure TRibbonTest.TabCaptionFollowsPages;
var
  Rib: TTyRibbon;
begin
  Rib := TTyRibbon.Create(nil);
  try
    Rib.AddPage('Home');
    Rib.AddPage('View');
    AssertEquals('tab count = page count', 2, Rib.TabCount);
    AssertEquals('cap 0', 'Home', Rib.TabCaption(0));
    AssertEquals('cap 1', 'View', Rib.TabCaption(1));
  finally
    Rib.Free;
  end;
end;

procedure TRibbonTest.RemovePageReindexesActive;
var
  Rib: TTyRibbon;
begin
  Rib := TTyRibbon.Create(nil);
  try
    Rib.AddPage('A'); Rib.AddPage('B'); Rib.AddPage('C');
    Rib.ActivePageIndex := 2;   // C active
    Rib.RemovePage(0);          // drop A -> active clamps down to index 1 (C)
    AssertEquals('count', 2, Rib.PageCount);
    AssertEquals('active reindexed', 1, Rib.ActivePageIndex);
    AssertEquals('cap 0 now B', 'B', Rib.TabCaption(0));
  finally
    Rib.Free;
  end;
end;

procedure TRibbonTest.RemoveActivePageFiresOnChange;
var
  Rib: TTyRibbon;
begin
  Rib := TTyRibbon.Create(nil);
  try
    Rib.AddPage('A'); Rib.AddPage('B'); Rib.AddPage('C');
    Rib.ActivePageIndex := 2;      // C active
    Rib.OnChange := @HandleChange;
    FChanged := 0;
    Rib.RemovePage(2);             // remove the ACTIVE page -> active becomes B -> OnChange fires
    AssertEquals('OnChange fired when the active page was removed', 1, FChanged);
    // Now [A, B] with B active (index 1). Removing A shifts B's index but keeps the
    // SAME active page object -> no OnChange (matches TTyPageControl).
    FChanged := 0;
    Rib.RemovePage(0);
    AssertEquals('no OnChange when the active page object is unchanged', 0, FChanged);
  finally
    Rib.Free;
  end;
end;

procedure TRibbonTest.ContextPageHiddenUntilContextShown;
var
  Rib: TTyRibbon;
  Ctx: TTyRibbonPage;
begin
  Rib := TTyRibbon.Create(nil);
  try
    Rib.AddPage('Home');            // always visible
    Ctx := Rib.AddPage('Table Tools');
    Ctx.Context := 'table';         // contextual — hidden while 'table' inactive
    AssertEquals('only the normal tab shows', 1, Rib.TabCount);
    AssertFalse('table context inactive', Rib.IsContextActive('table'));
    Rib.ShowContext('table');
    AssertTrue('table context active', Rib.IsContextActive('table'));
    AssertEquals('contextual tab now shows', 2, Rib.TabCount);
    AssertEquals('contextual caption', 'Table Tools', Rib.TabCaption(1));
    Rib.HideContext('table');
    AssertEquals('contextual tab hidden again', 1, Rib.TabCount);
  finally
    Rib.Free;
  end;
end;

procedure TRibbonTest.HidingActiveContextReanchorsAndFires;
var
  Rib: TTyRibbon;
  Home, Ctx: TTyRibbonPage;
begin
  FChanged := 0;
  Rib := TTyRibbon.Create(nil);
  try
    Home := Rib.AddPage('Home');
    Ctx := Rib.AddPage('Ctx');
    Ctx.Context := 'x';
    Rib.ShowContext('x');           // now [Home, Ctx] both visible
    Rib.ActivePage := Ctx;          // activate the contextual page
    AssertTrue('ctx active', Rib.ActivePage = Ctx);
    Rib.OnChange := @HandleChange;
    FChanged := 0;
    Rib.HideContext('x');           // the active contextual tab disappears
    AssertEquals('active re-anchored to Home', PtrInt(Home), PtrInt(Rib.ActivePage));
    AssertEquals('only Home visible', 1, Rib.TabCount);
    AssertEquals('OnChange fired on active-context hide', 1, FChanged);
  finally
    Rib.Free;
  end;
end;

procedure TRibbonTest.SettingContextHidesTabWhenInactive;
var
  Rib: TTyRibbon;
  P: TTyRibbonPage;
begin
  Rib := TTyRibbon.Create(nil);
  try
    Rib.AddPage('Home');
    P := Rib.AddPage('Maybe');
    AssertEquals('both visible', 2, Rib.TabCount);
    P.Context := 'ctx';             // becomes contextual, context inactive -> hides
    AssertEquals('contextual page hidden', 1, Rib.TabCount);
    P.Context := '';                // back to a normal always-visible tab
    AssertEquals('visible again', 2, Rib.TabCount);
  finally
    Rib.Free;
  end;
end;

procedure TRibbonTest.OverflowCountCollapsesTrailingGroups;
begin
  // 3 groups of natural width 100, collapsed button = 30.
  AssertEquals('all fit -> 0', 0, TyRibbonOverflowCount([100, 100, 100], 400, 30));
  AssertEquals('collapse 1 -> fits', 1, TyRibbonOverflowCount([100, 100, 100], 250, 30));
  AssertEquals('collapse all 3', 3, TyRibbonOverflowCount([100, 100, 100], 150, 30));
  AssertEquals('exactly fits -> 0', 0, TyRibbonOverflowCount([100, 100, 100], 300, 30));
  AssertEquals('empty -> 0', 0, TyRibbonOverflowCount([], 100, 30));
end;

procedure TRibbonTest.VisibleGroupCountFits;
begin
  // 3 groups of 100; how many LEADING groups fit in the available width.
  AssertEquals('all fit', 3, TyRibbonVisibleGroupCount([100, 100, 100], 300));
  AssertEquals('two fit', 2, TyRibbonVisibleGroupCount([100, 100, 100], 250));
  AssertEquals('one fits', 1, TyRibbonVisibleGroupCount([100, 100, 100], 150));
  AssertEquals('always at least one', 1, TyRibbonVisibleGroupCount([100, 100, 100], 10));
  AssertEquals('empty -> 0', 0, TyRibbonVisibleGroupCount([], 300));
end;

procedure TRibbonTest.CollapseRectAtRightEnd;
var R: TRect;
begin
  // A TabH-square at the right end of a TabH-tall strip.
  R := TyRibbonCollapseRect(300, 28);
  AssertEquals('left', 300 - 28, R.Left);
  AssertEquals('top', 0, R.Top);
  AssertEquals('right', 300, R.Right);
  AssertEquals('bottom', 28, R.Bottom);
  // Too narrow to hold the button -> empty (no negative rect).
  R := TyRibbonCollapseRect(20, 28);
  AssertTrue('empty when narrower than the button', (R.Right - R.Left) <= 0);
  R := TyRibbonCollapseRect(0, 28);
  AssertTrue('empty at zero width', (R.Right - R.Left) <= 0);
end;

procedure TRibbonTest.MinimizedCollapsesAndRestoresHeight;
var
  Rib: TTyRibbon;
  Full: Integer;
begin
  Rib := TTyRibbon.Create(nil);
  try
    Full := Rib.Height;                 // 118 by default
    Rib.Minimized := True;
    AssertTrue('minimized shrinks the height', Rib.Height < Full);
    Rib.Minimized := False;
    AssertEquals('restored to the full height', Full, Rib.Height);
  finally
    Rib.Free;
  end;
end;

procedure TRibbonTest.FileTabRoundTripAndDefaults;
var Rib: TTyRibbon;
begin
  Rib := TTyRibbon.Create(nil);
  try
    AssertFalse('File tab off by default', Rib.FileTab);
    { English, and a LITERAL rather than a resourcestring. It used to be a hardcoded
      Chinese caption, which an English application had no way to avoid. It is not a
      resourcestring for the same reason TTyDateTimePicker.TextForNullDate is not: a
      property default that follows the locale makes the .lfm a form writes depend on the
      language it was saved under. A localised File tab comes from the designer -- the
      property is TCaption now, so LCL's form translator walks it -- or from assigning a
      resourcestring in code. }
    AssertEquals('default caption', 'File', Rib.FileTabCaption);
    AssertEquals('default width', 52, Rib.FileTabWidth);
    Rib.FileTab := True;
    Rib.FileTabCaption := 'File';
    Rib.FileTabWidth := 60;
    AssertTrue('File tab on', Rib.FileTab);
    AssertEquals('caption set', 'File', Rib.FileTabCaption);
    AssertEquals('width set', 60, Rib.FileTabWidth);
  finally
    Rib.Free;
  end;
end;

procedure TRibbonTest.DefaultAligns;
var
  Rib: TTyRibbon;
  Grp: TTyRibbonGroup;
begin
  Rib := TTyRibbon.Create(nil);
  Grp := TTyRibbonGroup.Create(nil);
  try
    AssertTrue('ribbon docks top', Rib.Align = alTop);
    AssertTrue('group flows left', Grp.Align = alLeft);
  finally
    Grp.Free;
    Rib.Free;
  end;
end;

procedure TRibbonTest.APageForgetsAFreedGroup;
var
  form: TForm;
  page: TRibbonPageAccess;
  a, b, c: TTyRibbonGroup;
begin
  form := TForm.CreateNew(nil);
  try
    page := MakeGroupPage(form, 600, a, b, c);
    AssertEquals('precondition: the third group is third', 2 * (GroupW + GroupGap), c.Left);
    b.Free;
    page.Lay;
    AssertEquals('the freed group leaves the layout: the third moves up', GroupW + GroupGap, c.Left);
    AssertEquals('the first stays first', 0, a.Left);
  finally
    form.Free;
  end;
end;

procedure TRibbonTest.AGroupAddedLaterGoesLast;
var
  form: TForm;
  page: TRibbonPageAccess;
  a, b, c, d: TTyRibbonGroup;
begin
  form := TForm.CreateNew(nil);
  try
    page := MakeGroupPage(form, 600, a, b, c);
    d := TTyRibbonGroup.Create(form);
    d.Parent := page;
    d.Width := GroupW;
    page.Lay;
    AssertEquals('the added group goes after the others', 3 * (GroupW + GroupGap), d.Left);
    AssertEquals('instead of on top of the first', 0, a.Left);
    AssertTrue('and is shown', d.Visible);
  finally
    form.Free;
  end;
end;

procedure TRibbonTest.AHiddenGroupStaysHidden;
var
  form: TForm;
  page: TRibbonPageAccess;
  a, b, c: TTyRibbonGroup;
begin
  form := TForm.CreateNew(nil);
  try
    page := MakeGroupPage(form, 600, a, b, c);
    b.Visible := False;
    page.Lay;
    AssertFalse('a group the application hid stays hidden', b.Visible);
    AssertEquals('and takes no room', GroupW + GroupGap, c.Left);
  finally
    form.Free;
  end;
end;

procedure TRibbonTest.AnOverflowedGroupComesBackWithRoom;
var
  form: TForm;
  page: TRibbonPageAccess;
  a, b, c: TTyRibbonGroup;
begin
  form := TForm.CreateNew(nil);
  try
    page := MakeGroupPage(form, 600, a, b, c);
    page.Width := 250;
    page.Lay;
    AssertFalse('precondition: the third group does not fit', c.Visible);
    page.Width := 600;
    page.Lay;
    AssertTrue('with room again it comes back', c.Visible);
    AssertEquals('in its place', 2 * (GroupW + GroupGap), c.Left);
  finally
    form.Free;
  end;
end;

procedure TRibbonTest.AGroupHiddenWhileOverflowedStaysHidden;
var
  form: TForm;
  page: TRibbonPageAccess;
  a, b, c: TTyRibbonGroup;
begin
  form := TForm.CreateNew(nil);
  try
    page := MakeGroupPage(form, 600, a, b, c);
    page.Width := 250;
    page.Lay;
    AssertFalse('precondition: the third group does not fit', c.Visible);
    c.Visible := False;   // the application hides it too
    page.Width := 600;
    page.Lay;
    AssertFalse('it stays hidden when room comes back', c.Visible);
  finally
    form.Free;
  end;
end;

procedure TRibbonTest.AGroupMovedAwayIsForgotten;
var
  form: TForm;
  page: TRibbonPageAccess;
  a, b, c: TTyRibbonGroup;
begin
  form := TForm.CreateNew(nil);
  try
    page := MakeGroupPage(form, 600, a, b, c);
    b.Parent := form;
    page.Lay;
    AssertEquals('the group moved away leaves the layout', GroupW + GroupGap, c.Left);
  finally
    form.Free;
  end;
end;

{ The fly-out is a real window. The console runner never calls Application.Initialize, so
  CreateHandle fails with 1407 without this; lazy, the pattern test.base uses. }
var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

procedure TRibbonTest.AGroupFreedInTheFlyOutIsForgotten;
var
  form: TForm;
  page: TRibbonPageAccess;
  a, b, c: TTyRibbonGroup;
  i: Integer;
  more: TTyButton;
  fly: TTyPopupSurface;
begin
  NeedWidgetSet;
  form := TForm.CreateNew(nil);
  a := nil;
  b := nil;
  try
    { Owned by no one, so only the page's own free notice can tell it. }
    page := MakeGroupPage(form, 250, a, b, c, nil, False);
    AssertFalse('precondition: the third group does not fit', c.Visible);
    more := nil;
    for i := 0 to page.ControlCount - 1 do
      if page.Controls[i] is TTyButton then more := TTyButton(page.Controls[i]);
    AssertNotNull('precondition: the more button is there', more);
    more.Click;
    fly := nil;
    for i := 0 to page.ComponentCount - 1 do
      if page.Components[i] is TTyPopupSurface then fly := TTyPopupSurface(page.Components[i]);
    AssertNotNull('precondition: the fly-out was made', fly);
    AssertSame('precondition: the fly-out holds the third group', TWinControl(fly), c.Parent);
    c.Free;
    fly.ClosePopup;
    page.Width := 600;
    page.Lay;
    AssertEquals('the other two are laid out without it', GroupW + GroupGap, b.Left);
    AssertTrue('and shown', b.Visible);
  finally
    form.Free;
    a.Free;
    b.Free;
  end;
end;

initialization
  RegisterTest(TRibbonTest);
end.
