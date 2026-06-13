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
    procedure SimulateMouseDown(X, Y: Integer);
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
    procedure TestDragRoundTrip;
    procedure TestDisabledMouseIgnored;
  end;

  TTyTrackBarPixelTest = class(TTestCase)
  published
    procedure TestThumbPixelBlueAtPos0;
    { A1 regression: non-zero origin ARect must not displace thumb relative to track }
    procedure TestOffsetOriginThumbPositionConsistent;
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

procedure TTyTrackBarProbe.SimulateMouseDown(X, Y: Integer);
begin
  MouseDown(mbLeft, [], X, Y);
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

procedure TTyTrackBarControlTest.TestDragRoundTrip;
{ For every Pos in [0..100] with bounds 200x24 @96ppi:
  set Position := Pos, get ThumbRect, DragTo center of thumb,
  assert Position is unchanged (zero mismatches allowed). }
var
  Bar: TTyTrackBar;
  Form: TForm;
  Pos, Mismatches, FirstBad, CX: Integer;
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
    Mismatches := 0;
    FirstBad := -1;
    for Pos := 0 to 100 do
    begin
      Bar.Position := Pos;
      R := Bar.ThumbRect;
      CX := (R.Left + R.Right) div 2;
      Bar.DragTo(CX);
      if Bar.Position <> Pos then
      begin
        Inc(Mismatches);
        if FirstBad < 0 then FirstBad := Pos;
      end;
    end;
    AssertEquals(Format('DragTo(ThumbRect center) is identity for all 0..100 (mismatches=%d firstBad=%d)',
      [Mismatches, FirstBad]), 0, Mismatches);
  finally
    Form.Free;
  end;
end;

procedure TTyTrackBarControlTest.TestDisabledMouseIgnored;
var
  Bar: TTyTrackBarProbe;
begin
  Bar := TTyTrackBarProbe.Create(FForm);
  Bar.Parent := FForm;
  Bar.SetBounds(0, 30, 200, 24);
  Bar.Font.PixelsPerInch := 96;
  Bar.Min := 0;
  Bar.Max := 100;
  Bar.Position := 0;
  try
    Bar.Enabled := False;
    // MouseDown at far right would normally drag thumb to Max
    Bar.SimulateMouseDown(200, 12);
    AssertEquals('disabled trackbar mouse ignored', 0, Bar.Position);
  finally
    Bar.Free;
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

{ TestOffsetOriginThumbPositionConsistent
  Regression for A1: TrackBar RenderTo used ARect-absolute coords, so a
  non-zero origin would displace the thumb rectangle on the local bitmap.

  ARect = Rect(20, 5, 220, 29) — a 200x24 control starting at (20,5).
  Render into a 240x34 bitmap.  Position=0 → thumb covers local x=0..12.

  At 96 ppi, thumb centre in local bitmap: (6, 12).
  In destination bitmap: (20+6, 5+12) = (26, 17).

  Assert (26, 17) is blue-dominant (thumb).
  Assert (20+100, 5+12) = (120, 17) is NOT blue-dominant (groove).
  Before the fix, with ARect-absolute, ThumbR would use R.Left=20 as offset,
  so the thumb would appear at local x=20..32 → blit destination (40..52),
  and (26,17) would be groove-dark. }
procedure TTyTrackBarPixelTest.TestOffsetOriginThumbPositionConsistent;
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

    { Render into a 240x34 bitmap with ARect starting at (20, 5). }
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(240, 34);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, 240, 34);
    Bar.RenderTo(Bmp.Canvas, Rect(20, 5, 220, 29), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      { (20+6, 5+12) = (26, 17): inside thumb (local x=0..12) → blue }
      PxThumb := Reread.GetPixel(26, 17);
      { (20+100, 5+12) = (120, 17): groove (local x=100) → dark }
      PxGroove := Reread.GetPixel(120, 17);

      AssertTrue(
        Format('offset-origin thumb B > 180 (blue, got R=%d G=%d B=%d)',
          [PxThumb.red, PxThumb.green, PxThumb.blue]),
        PxThumb.blue > 180);
      AssertTrue(
        Format('offset-origin thumb R < 120 (not red, got R=%d G=%d B=%d)',
          [PxThumb.red, PxThumb.green, PxThumb.blue]),
        PxThumb.red < 120);

      AssertTrue(
        Format('offset-origin groove NOT blue-dominant (got R=%d G=%d B=%d)',
          [PxGroove.red, PxGroove.green, PxGroove.blue]),
        PxGroove.blue <= PxGroove.red + 80);
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
