unit test.ribbon;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, fpcunit, testregistry,
  tyControls.Base, tyControls.Ribbon;

type
  TRibbonTest = class(TTestCase)
  private
    FChanged: Integer;
    procedure HandleChange(Sender: TObject);
  published
    procedure GroupContentRectSubtractsBand;
    procedure GroupContentRectClampsBand;
    procedure TypeKeys;
    procedure AddPageGrowsCountAndActivates;
    procedure TabCaptionFollowsPages;
    procedure RemovePageReindexesActive;
    procedure RemoveActivePageFiresOnChange;
    procedure ContextPageHiddenUntilContextShown;
    procedure HidingActiveContextReanchorsAndFires;
    procedure SettingContextHidesTabWhenInactive;
    procedure DefaultAligns;
  end;

implementation

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

initialization
  RegisterTest(TRibbonTest);
end.
