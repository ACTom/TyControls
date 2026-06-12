unit test.trackbar;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.TrackBar;
type
  { Probe subclass: exposes protected RenderTo and keyboard handler }
  TTyTrackBarProbe = class(TTyTrackBar)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure SimulateKeyDown(var Key: Word);
  end;

  TChangeCounter = class
  public
    Count: Integer;
    procedure Handle(Sender: TObject);
  end;

  TTyTrackBarGeometryTest = class(TTestCase)
  published
    procedure TestThumbRectPos0Left;
    procedure TestThumbRectPos100Right;
    procedure TestThumbRectPos50Centered;
  end;

  TTyTrackBarControlTest = class(TTestCase)
  private
    FForm: TForm;
    FBar: TTyTrackBar;
    FCounter: TChangeCounter;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestDragToMinAtZero;
    procedure TestDragToMaxPastEnd;
    procedure TestDragToMid;
    procedure TestOnChangeOnlyOnRealChange;
    procedure TestVKLeftDecrement;
    procedure TestVKRightIncrement;
    procedure TestVKLeftClampsAtMin;
    procedure TestVKRightClampsAtMax;
  end;

  TTyTrackBarPixelTest = class(TTestCase)
  published
    procedure TestThumbPixelBlueAtPos0;
  end;

implementation

procedure TChangeCounter.Handle(Sender: TObject);
begin
  Inc(Count);
end;

procedure TTyTrackBarProbe.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyTrackBarProbe.SimulateKeyDown(var Key: Word);
var
  Shift: TShiftState;
begin
  Shift := [];
  KeyDown(Key, Shift);
end;

{ TTyTrackBarGeometryTest }

procedure TTyTrackBarGeometryTest.TestThumbRectPos0Left;
{ Bounds 200x24 @96ppi. ThumbW = Scale(12) = 12.
  Travel = 200 - 12 = 188. Pos=0 → thumbLeft = 0.
}
var
  Form: TForm;
  Bar: TTyTrackBar;
  R: TRect;
begin
  Form := TForm.CreateNew(nil);
  try
    Bar := TTyTrackBar.Create(Form);
    Bar.Parent := Form;
    Bar.SetBounds(0, 0, 200, 24);
    Bar.Font.PixelsPerInch := 96;
    Bar.Min := 0;
    Bar.Max := 100;
    Bar.Position := 0;
    R := Bar.ThumbRect;
    AssertEquals('Pos=0: thumb Left = 0', 0, R.Left);
    AssertEquals('Pos=0: thumb Width = 12', 12, R.Right - R.Left);
  finally
    Form.Free;
  end;
end;

procedure TTyTrackBarGeometryTest.TestThumbRectPos100Right;
{ Pos=100: thumbLeft = Travel = 188, Right = 200. }
var
  Form: TForm;
  Bar: TTyTrackBar;
  R: TRect;
begin
  Form := TForm.CreateNew(nil);
  try
    Bar := TTyTrackBar.Create(Form);
    Bar.Parent := Form;
    Bar.SetBounds(0, 0, 200, 24);
    Bar.Font.PixelsPerInch := 96;
    Bar.Min := 0;
    Bar.Max := 100;
    Bar.Position := 100;
    R := Bar.ThumbRect;
    AssertEquals('Pos=100: thumb Right = 200', 200, R.Right);
  finally
    Form.Free;
  end;
end;

procedure TTyTrackBarGeometryTest.TestThumbRectPos50Centered;
{ Pos=50: thumbLeft = round(188 * 50 / 100) = 94. }
var
  Form: TForm;
  Bar: TTyTrackBar;
  R: TRect;
begin
  Form := TForm.CreateNew(nil);
  try
    Bar := TTyTrackBar.Create(Form);
    Bar.Parent := Form;
    Bar.SetBounds(0, 0, 200, 24);
    Bar.Font.PixelsPerInch := 96;
    Bar.Min := 0;
    Bar.Max := 100;
    Bar.Position := 50;
    R := Bar.ThumbRect;
    AssertEquals('Pos=50: thumb Left = 94', 94, R.Left);
  finally
    Form.Free;
  end;
end;

{ TTyTrackBarControlTest }

procedure TTyTrackBarControlTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 300, 100);
  FBar := TTyTrackBar.Create(FForm);
  FBar.Parent := FForm;
  FBar.SetBounds(0, 0, 200, 24);
  FBar.Font.PixelsPerInch := 96;
  FBar.Min := 0;
  FBar.Max := 100;
  FBar.Position := 0;
  FCounter := TChangeCounter.Create;
  FBar.OnChange := @FCounter.Handle;
end;

procedure TTyTrackBarControlTest.TearDown;
begin
  FCounter.Free;
  FForm.Free;
end;

procedure TTyTrackBarControlTest.TestTypeKey;
begin
  AssertEquals('TyTrackBar', (FBar as ITyStyleable).GetStyleTypeKey);
end;

procedure TTyTrackBarControlTest.TestDragToMinAtZero;
begin
  { DragTo(0): centers thumb at x=0; NewLeft = clamp(0 - 6, 0, 188) = 0 → Pos = Min = 0 }
  FBar.DragTo(0);
  AssertEquals('DragTo(0) → Position = 0 (Min)', 0, FBar.Position);
end;

procedure TTyTrackBarControlTest.TestDragToMaxPastEnd;
begin
  { DragTo(10000): clamps to max → Position = Max }
  FBar.DragTo(10000);
  AssertEquals('DragTo(10000) → Position = 100 (Max)', 100, FBar.Position);
end;

procedure TTyTrackBarControlTest.TestDragToMid;
{ DragTo(100): NewLeft = clamp(100 - 6, 0, 188) = 94.
  Position = 0 + round(94 * 100 / 188). 94*100=9400, 9400/188=50.
  Allow ±1 tolerance. }
begin
  FBar.DragTo(100);
  AssertTrue('DragTo(100) → Position near 50',
    (FBar.Position >= 49) and (FBar.Position <= 51));
end;

procedure TTyTrackBarControlTest.TestOnChangeOnlyOnRealChange;
begin
  FCounter.Count := 0;
  FBar.Position := 50;
  AssertEquals('First set fires OnChange once', 1, FCounter.Count);
  FBar.Position := 50;
  AssertEquals('Second set to same value does not fire OnChange', 1, FCounter.Count);
end;

procedure TTyTrackBarControlTest.TestVKLeftDecrement;
var
  Probe: TTyTrackBarProbe;
  Key: Word;
begin
  Probe := TTyTrackBarProbe.Create(FForm);
  Probe.Parent := FForm;
  Probe.SetBounds(0, 30, 200, 24);
  Probe.Font.PixelsPerInch := 96;
  Probe.Min := 0;
  Probe.Max := 100;
  Probe.Position := 50;
  try
    Key := VK_LEFT;
    Probe.SimulateKeyDown(Key);
    AssertEquals('VK_LEFT decrements by 1', 49, Probe.Position);
    AssertEquals('VK_LEFT key consumed (Key=0)', 0, Integer(Key));
  finally
    Probe.Free;
  end;
end;

procedure TTyTrackBarControlTest.TestVKRightIncrement;
var
  Probe: TTyTrackBarProbe;
  Key: Word;
begin
  Probe := TTyTrackBarProbe.Create(FForm);
  Probe.Parent := FForm;
  Probe.SetBounds(0, 30, 200, 24);
  Probe.Font.PixelsPerInch := 96;
  Probe.Min := 0;
  Probe.Max := 100;
  Probe.Position := 50;
  try
    Key := VK_RIGHT;
    Probe.SimulateKeyDown(Key);
    AssertEquals('VK_RIGHT increments by 1', 51, Probe.Position);
    AssertEquals('VK_RIGHT key consumed (Key=0)', 0, Integer(Key));
  finally
    Probe.Free;
  end;
end;

procedure TTyTrackBarControlTest.TestVKLeftClampsAtMin;
var
  Probe: TTyTrackBarProbe;
  Key: Word;
begin
  Probe := TTyTrackBarProbe.Create(FForm);
  Probe.Parent := FForm;
  Probe.SetBounds(0, 30, 200, 24);
  Probe.Font.PixelsPerInch := 96;
  Probe.Min := 0;
  Probe.Max := 100;
  Probe.Position := 0;
  try
    Key := VK_LEFT;
    Probe.SimulateKeyDown(Key);
    AssertEquals('VK_LEFT at Min stays at Min', 0, Probe.Position);
  finally
    Probe.Free;
  end;
end;

procedure TTyTrackBarControlTest.TestVKRightClampsAtMax;
var
  Probe: TTyTrackBarProbe;
  Key: Word;
begin
  Probe := TTyTrackBarProbe.Create(FForm);
  Probe.Parent := FForm;
  Probe.SetBounds(0, 30, 200, 24);
  Probe.Font.PixelsPerInch := 96;
  Probe.Min := 0;
  Probe.Max := 100;
  Probe.Position := 100;
  try
    Key := VK_RIGHT;
    Probe.SimulateKeyDown(Key);
    AssertEquals('VK_RIGHT at Max stays at Max', 100, Probe.Position);
  finally
    Probe.Free;
  end;
end;

{ TTyTrackBarPixelTest }

procedure TTyTrackBarPixelTest.TestThumbPixelBlueAtPos0;
{ Stylesheet: groove dark (#202020), thumb blue (#3B82F6).
  200x24 bitmap @96ppi. Pos=0 → thumb at x=0..12.
  Pixel (6, 12) is inside the thumb → blue-dominant (B>180, R<120).
  Pixel (100, 12) is in the groove → NOT blue-dominant (B <= R+80).
}
var
  Ctl: TTyStyleController;
  Form: TForm;
  Bar: TTyTrackBarProbe;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  PxThumb, PxGroove: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyTrackBar { background: #202020; border-width: 0px; border-radius: 0px; }' +
      'TyTrackThumb { background: #3B82F6; border-radius: 0px; }');
    Bar := TTyTrackBarProbe.Create(Form);
    Bar.Parent := Form;
    Bar.Controller := Ctl;
    Bar.SetBounds(0, 0, 200, 24);
    Bar.Font.PixelsPerInch := 96;
    Bar.Min := 0;
    Bar.Max := 100;
    Bar.Position := 0;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 24);
    Bar.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 24), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      PxThumb := Reread.GetPixel(6, 12);    // inside thumb (0..12)
      PxGroove := Reread.GetPixel(100, 12); // in groove

      AssertTrue('thumb pixel B > 180 (blue-dominant)', PxThumb.blue > 180);
      AssertTrue('thumb pixel R < 120 (not red)',        PxThumb.red < 120);

      AssertTrue('groove pixel NOT blue-dominant (B <= R+80)', PxGroove.blue <= PxGroove.red + 80);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

initialization
  RegisterTest(TTyTrackBarGeometryTest);
  RegisterTest(TTyTrackBarControlTest);
  RegisterTest(TTyTrackBarPixelTest);
end.
