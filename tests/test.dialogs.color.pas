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
  TColorDialogTest = class(TTestCase)
  published
    procedure TestSyncHexToChannels;
    procedure TestSyncRGBToHex;
    procedure TestComponentTwoWay;
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

procedure TColorDialogTest.TestSyncHexToChannels;
var d: TTyColorForm;
begin
  d := TyBuildColorDialog('Pick', TyRGB(0,0,0));
  try
    d.ApplyHexText('#3399CC');
    AssertEquals('R', $33, TyRedOf(d.CurrentColor));
    AssertEquals('G', $99, TyGreenOf(d.CurrentColor));
    AssertEquals('B', $CC, TyBlueOf(d.CurrentColor));
  finally d.Free; end;
end;

procedure TColorDialogTest.TestSyncRGBToHex;
var d: TTyColorForm;
begin
  d := TyBuildColorDialog('Pick', TyRGB(0,0,0));
  try
    d.SetColor(TyRGB($12,$34,$56));
    AssertEquals('hex', '#123456', LowerCase(d.HexText));
  finally d.Free; end;
end;

procedure TColorDialogTest.TestComponentTwoWay;
var comp: TTyColorDialog;
begin
  comp := TTyColorDialog.Create(nil);
  try
    comp.Color := TyRGBA($10,$20,$30,$80);
    AssertEquals('lcl rt', Integer(TyColorToLCL(TyRGB($10,$20,$30))), Integer(comp.LCLColor));
    AssertEquals('alpha', $80, comp.Alpha);
    comp.Alpha := $FF;
    AssertEquals('alpha2', $FF, TyAlphaOf(comp.Color));
    comp.LCLColor := clRed;   // sets RGB, preserves alpha
    AssertEquals('lcl set keeps alpha', $FF, TyAlphaOf(comp.Color));
  finally comp.Free; end;
end;

initialization
  RegisterTest(TColorControlsTest);
  RegisterTest(TColorDialogTest);
end.
