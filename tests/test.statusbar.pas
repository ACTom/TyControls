unit test.statusbar;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, fpcunit, testregistry, tyControls.Types, tyControls.StatusBar;
type
  TStatusBarGeomTest = class(TTestCase)
  published
    procedure TestPanelRectsFixed;
    procedure TestPanelRectsFillPanel;
  end;
implementation
procedure TStatusBarGeomTest.TestPanelRectsFixed;
var r: TTyRectArray;
begin
  r := TyStatusPanelRects([50, 80], 200, 0);
  AssertEquals('count', 2, Length(r));
  AssertEquals('p0.left', 0, r[0].Left);   AssertEquals('p0.right', 50, r[0].Right);
  AssertEquals('p1.left', 50, r[1].Left);  AssertEquals('p1.right', 130, r[1].Right);
end;
procedure TStatusBarGeomTest.TestPanelRectsFillPanel;
var r: TTyRectArray;
begin
  // a panel with Width<=0 fills the remaining width (first such panel only)
  r := TyStatusPanelRects([50, 0, 40], 200, 0);
  AssertEquals('fill panel right', 160, r[1].Right);   // 50 + (200-50-40)=110 -> 50..160
  AssertEquals('p2 left', 160, r[2].Left);             AssertEquals('p2 right', 200, r[2].Right);
end;
initialization
  RegisterTest(TStatusBarGeomTest);
end.
