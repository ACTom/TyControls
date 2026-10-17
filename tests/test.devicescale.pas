unit test.devicescale;
{$mode objfpc}{$H+}

{ #83: where the device scale of a canvas comes from.

  On a Retina Mac one LCL pixel is one point and covers two device pixels; a control that wants
  sharp output has to ask TControl.GetCanvasScaleFactor how many, and only LCL-Cocoa answers with
  anything but 1. TyCanvasDeviceScale is the one place the library asks. Windows never answers
  2, so everything here that is not 1 comes through the test seam -- or through the registry
  an S-times offscreen cache puts its own canvas into. }

interface

uses
  Classes, SysUtils, Math, Graphics, Forms, Controls, fpcunit, testregistry,
  tyControls.Painter, tyControls.PlatformWS, tyControls.Button;

type
  TDeviceScaleSourceTest = class(TTestCase)
  protected
    procedure TearDown; override;
  published
    procedure TestScaleOfRoundsAndClamps;
    procedure TestNilAndBitmapCanvasesAreOne;
    procedure TestControlCanvasOnWindowsIsOne;
    procedure TestSeamWinsOverEverything;
    procedure TestRegisteredCanvas;
    procedure TestSwitchOffForcesOne;
    { The painter asks the platform facade, not LCL directly: the one place a widgetset that
      scales without saying so (Qt6, GTK3) will get its own query. }
    procedure TestControlScaleComesFromThePlatform;
  end;

implementation

procedure AssertScale(ATest: TTestCase; const AMsg: string; const AGot: TTyCanvasScale;
  AScale: Integer; ADeviceUnits: Boolean);
begin
  ATest.AssertEquals(AMsg + ': scale', AScale, AGot.Scale);
  ATest.AssertEquals(AMsg + ': device units', ADeviceUnits, AGot.DeviceUnits);
end;

procedure TDeviceScaleSourceTest.TearDown;
begin
  TyForceDeviceScaleForTest(0, False);
  TyDeviceScaleRendering := True;
  TyResetTestPlatform;
  inherited TearDown;
end;

procedure TDeviceScaleSourceTest.TestScaleOfRoundsAndClamps;
const
  CIn: array[0..9] of Double = (0, -1, 0, 0.5, 1.0, 1.49, 1.5, 2.0, 3.0, 7.0);
  COut: array[0..9] of Integer = (1, 1, 1, 1, 1, 1, 2, 2, 3, 4);
var
  i: Integer;
  f: Double;
begin
  for i := 0 to High(CIn) do
  begin
    f := CIn[i];
    if i = 2 then f := NaN;   // a constant array cannot hold NaN
    AssertEquals(Format('factor #%d (%g)', [i, f]), COut[i], TyDeviceScaleOf(f));
  end;
end;

procedure TDeviceScaleSourceTest.TestNilAndBitmapCanvasesAreOne;
var
  bmp: TBitmap;
begin
  AssertScale(Self, 'nil', TyCanvasDeviceScale(nil), 1, False);
  bmp := TBitmap.Create;
  try
    bmp.SetSize(4, 4);
    AssertScale(Self, 'an offscreen bitmap', TyCanvasDeviceScale(bmp.Canvas), 1, False);
  finally
    bmp.Free;
  end;
end;

procedure TDeviceScaleSourceTest.TestControlCanvasOnWindowsIsOne;
var
  f: TForm;
  b: TTyButton;
begin
  f := TForm.CreateNew(nil);
  try
    b := TTyButton.Create(f);
    b.Parent := f;
    AssertScale(Self, 'a control''s own canvas off Cocoa', TyCanvasDeviceScale(b.Canvas), 1, False);
  finally
    f.Free;
  end;
end;

procedure TDeviceScaleSourceTest.TestSeamWinsOverEverything;
var
  f: TForm;
  b: TTyButton;
  bmp: TBitmap;
begin
  f := TForm.CreateNew(nil);
  bmp := TBitmap.Create;
  try
    b := TTyButton.Create(f);
    b.Parent := f;
    bmp.SetSize(4, 4);
    TyForceDeviceScaleForTest(2, True);
    AssertScale(Self, 'seam (2, True), nil', TyCanvasDeviceScale(nil), 2, True);
    AssertScale(Self, 'seam (2, True), bitmap', TyCanvasDeviceScale(bmp.Canvas), 2, True);
    AssertScale(Self, 'seam (2, True), control', TyCanvasDeviceScale(b.Canvas), 2, True);
    TyForceDeviceScaleForTest(3, False);
    AssertScale(Self, 'seam (3, False)', TyCanvasDeviceScale(bmp.Canvas), 3, False);
    TyForceDeviceScaleForTest(0, False);
    AssertScale(Self, 'seam off again', TyCanvasDeviceScale(bmp.Canvas), 1, False);
  finally
    bmp.Free;
    f.Free;
  end;
end;

procedure TDeviceScaleSourceTest.TestRegisteredCanvas;
var
  bmp, other: TBitmap;
begin
  bmp := TBitmap.Create;
  other := TBitmap.Create;
  try
    TyRegisterRasterCanvas(bmp.Canvas, 2);
    AssertScale(Self, 'registered', TyCanvasDeviceScale(bmp.Canvas), 2, True);
    AssertScale(Self, 'another canvas is not', TyCanvasDeviceScale(other.Canvas), 1, False);
    TyRegisterRasterCanvas(bmp.Canvas, 2);
    TyUnregisterRasterCanvas(bmp.Canvas);
    AssertScale(Self, 'registered twice, unregistered once: gone', TyCanvasDeviceScale(bmp.Canvas),
      1, False);
    TyRegisterRasterCanvas(bmp.Canvas, 2);
    TyRegisterRasterCanvas(bmp.Canvas, 3);
    AssertScale(Self, 'registering again updates the scale', TyCanvasDeviceScale(bmp.Canvas), 3, True);
  finally
    TyUnregisterRasterCanvas(bmp.Canvas);
    other.Free;
    bmp.Free;
  end;
end;

procedure TDeviceScaleSourceTest.TestSwitchOffForcesOne;
var
  bmp: TBitmap;
begin
  bmp := TBitmap.Create;
  try
    TyRegisterRasterCanvas(bmp.Canvas, 2);
    TyForceDeviceScaleForTest(2, True);
    TyDeviceScaleRendering := False;
    AssertScale(Self, 'switch off beats the seam', TyCanvasDeviceScale(nil), 1, False);
    TyForceDeviceScaleForTest(0, False);
    AssertScale(Self, 'switch off beats the registry', TyCanvasDeviceScale(bmp.Canvas), 1, False);
  finally
    TyUnregisterRasterCanvas(bmp.Canvas);
    bmp.Free;
  end;
end;

procedure TDeviceScaleSourceTest.TestControlScaleComesFromThePlatform;
var
  f: TForm;
  b: TTyButton;
begin
  f := TForm.CreateNew(nil);
  try
    b := TTyButton.Create(f);
    b.Parent := f;
    AssertEquals('the facade answers 1 off Cocoa', 1.0, TyControlDeviceScale(b), 0);
    AssertEquals('and 1 for no control', 1.0, TyControlDeviceScale(nil), 0);
    TyResetTestPlatform;
    TyTestPlatform.Active := True;
    TyTestPlatform.DeviceScale := 2;
    AssertEquals('the platform seam answers for the facade', 2.0, TyControlDeviceScale(b), 0);
    AssertScale(Self, 'and the painter takes it from there', TyCanvasDeviceScale(b.Canvas), 2, False);
    TyTestPlatform.DeviceScale := 0;
    AssertScale(Self, 'an unset seam scale leaves LCL''s answer', TyCanvasDeviceScale(b.Canvas), 1, False);
  finally
    f.Free;
  end;
end;

initialization
  RegisterTest(TDeviceScaleSourceTest);

end.
