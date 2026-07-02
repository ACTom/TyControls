unit test.dialogs.color;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Graphics, Controls, fpcunit, testregistry,
  tyControls.Types, tyControls.ColorMath, tyControls.Dialogs.Color;
type
  TColorControlsTest = class(TTestCase)
  published
    procedure TestSquareHueRoundTrip;
  end;
implementation
procedure TColorControlsTest.TestSquareHueRoundTrip;
var sq: TTyHSVSquare; hb: TTyHueBar;
begin
  sq := TTyHSVSquare.Create(nil);   // parentless construct-only (TTyCustomControl)
  try
    sq.SetHSV(210, 0.5, 0.8);
    AssertEquals('H', 210.0, sq.Hue, 0.5);
    AssertEquals('S', 0.5, sq.Sat, 0.01);
    AssertEquals('V', 0.8, sq.Val, 0.01);
  finally sq.Free; end;
  hb := TTyHueBar.Create(nil);
  try
    hb.Hue := 300;
    AssertEquals('huebar', 300.0, hb.Hue, 0.5);
  finally hb.Free; end;
end;
initialization
  RegisterTest(TColorControlsTest);
end.
