unit test.statusbar;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, fpcunit, testregistry, tyControls.Types, tyControls.StatusBar;
type
  TStatusBarGeomTest = class(TTestCase)
  published
    procedure TestPanelRectsFixed;
    procedure TestPanelRectsFillPanel;
    procedure TestPanelRectsPadding;
    procedure TestPanelRectsFillFirstOnly;
    procedure TestPanelRectsOverflowAndEmpty;
  end;
implementation
procedure TStatusBarGeomTest.TestPanelRectsFixed;
var r: TTyRectArray;
begin
  r := TyStatusPanelRects([50, 80], 200, 0);
  AssertEquals('count', 2, Length(r));
  AssertEquals('p0.left', 0, r[0].Left);   AssertEquals('p0.right', 50, r[0].Right);
  AssertEquals('p1.left', 50, r[1].Left);  AssertEquals('p1.right', 130, r[1].Right);
  AssertEquals('p0.top sentinel', 0, r[0].Top); AssertEquals('p0.bottom sentinel', 0, r[0].Bottom);
end;
procedure TStatusBarGeomTest.TestPanelRectsFillPanel;
var r: TTyRectArray;
begin
  // a panel with Width<=0 fills the remaining width (first such panel only)
  r := TyStatusPanelRects([50, 0, 40], 200, 0);
  AssertEquals('fill panel right', 160, r[1].Right);   // 50 + (200-50-40)=110 -> 50..160
  AssertEquals('p2 left', 160, r[2].Left);             AssertEquals('p2 right', 200, r[2].Right);
end;
procedure TStatusBarGeomTest.TestPanelRectsPadding;
var r: TTyRectArray;
begin
  r := TyStatusPanelRects([50, 80], 200, 10);
  AssertEquals('p0.left', 10, r[0].Left);   AssertEquals('p0.right', 60, r[0].Right);
  AssertEquals('p1.left', 60, r[1].Left);   AssertEquals('p1.right', 140, r[1].Right);
end;
procedure TStatusBarGeomTest.TestPanelRectsFillFirstOnly;
var r: TTyRectArray;
begin
  // two <=0 panels: only the FIRST fills; the second gets zero width
  r := TyStatusPanelRects([0, 0, 40], 200, 0);
  AssertEquals('fill panel right', 160, r[0].Right);          // 200-40
  AssertEquals('second <=0 zero width', r[1].Left, r[1].Right);
  AssertEquals('p2 left', 160, r[2].Left);                   AssertEquals('p2 right', 200, r[2].Right);
end;
procedure TStatusBarGeomTest.TestPanelRectsOverflowAndEmpty;
var r: TTyRectArray;
begin
  // fixed widths exceed total + a fill panel -> fill clamps to 0
  r := TyStatusPanelRects([150, 0, 120], 200, 0);
  AssertEquals('overflow fill collapses', r[1].Left, r[1].Right);
  // empty input -> empty result
  r := TyStatusPanelRects([], 200, 0);
  AssertEquals('empty', 0, Length(r));
end;
initialization
  RegisterTest(TStatusBarGeomTest);
end.
