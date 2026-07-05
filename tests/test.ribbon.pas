unit test.ribbon;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Controls, fpcunit, testregistry,
  tyControls.Base, tyControls.Ribbon;

type
  TRibbonTest = class(TTestCase)
  published
    procedure GroupContentRectSubtractsBand;
    procedure GroupContentRectClampsBand;
    procedure TypeKeys;
    procedure AddPageGrowsCountAndActivates;
    procedure TabCaptionFollowsPages;
    procedure RemovePageReindexesActive;
    procedure DefaultAligns;
  end;

implementation

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
