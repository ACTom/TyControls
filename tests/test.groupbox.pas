unit test.groupbox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, StdCtrls, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.GroupBox;
type
  TTyGroupBoxProbe = class(TTyGroupBox)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure CallAdjustClientRect(var ARect: TRect);
  end;

  TTyGroupBoxTest = class(TTestCase)
  private
    FForm: TForm;
    FBox: TTyGroupBox;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestCaptionSettable;
    procedure TestHostsChild;
    procedure TestPaintSmoke;
    procedure TestCaptionBandErasedBorderNotVisible;
    procedure TestClientRectInsetBelowCaption;
  end;

implementation

procedure TTyGroupBoxProbe.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyGroupBoxProbe.CallAdjustClientRect(var ARect: TRect);
begin
  AdjustClientRect(ARect);
end;

procedure TTyGroupBoxTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FForm.SetBounds(0, 0, 300, 200);
  FBox := TTyGroupBox.Create(FForm);
  FBox.Parent := FForm;
  FBox.SetBounds(0, 0, 185, 105);
  FBox.Font.PixelsPerInch := 96;
end;

procedure TTyGroupBoxTest.TearDown;
begin
  FForm.Free;
end;

procedure TTyGroupBoxTest.TestTypeKey;
begin
  AssertEquals('TyGroupBox', (FBox as ITyStyleable).GetStyleTypeKey);
end;

procedure TTyGroupBoxTest.TestCaptionSettable;
begin
  FBox.Caption := 'Group';
  AssertEquals('Caption settable and readable', 'Group', FBox.Caption);
end;

procedure TTyGroupBoxTest.TestHostsChild;
var
  Child: TButton;
begin
  Child := TButton.Create(FBox);
  Child.Parent := FBox;
  AssertSame('child parent must be the groupbox', FBox, Child.Parent);
  AssertEquals('groupbox must report one child control', 1, FBox.ControlCount);
end;

procedure TTyGroupBoxTest.TestPaintSmoke;
var
  Probe: TTyGroupBoxProbe;
  Bmp: TBitmap;
begin
  Probe := TTyGroupBoxProbe.Create(FForm);
  Probe.Parent := FForm;
  Probe.Caption := 'Test Group';
  Probe.SetBounds(0, 0, 185, 105);
  Probe.Font.PixelsPerInch := 96;
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(185, 105);
    Probe.RenderTo(Bmp.Canvas, Rect(0, 0, 185, 105), 96);
    AssertTrue('groupbox RenderTo executed without exception', True);
  finally
    Bmp.Free;
  end;
end;

procedure TTyGroupBoxTest.TestCaptionBandErasedBorderNotVisible;
{ With a red border, transparent background, and caption '组' rendered over a
  white bitmap:
  (a) A border pixel on the top edge OUTSIDE the caption band x-range must be
      red-dominant (border visible where no text erasing occurred).
  (b) A pixel INSIDE the band at the border's y (capH div 2 = 8) must NOT be
      red-dominant — the band was erased so the white backdrop shows through. }
var
  Ctl: TTyStyleController;
  Form: TForm;
  Probe: TTyGroupBoxProbe;
  Bmp: TBitmap;
  BgBmp: TBGRABitmap;
  Reread: TBGRABitmap;
  PxOutside, PxInside: TBGRAPixel;
  CapY: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGroupBox { border-color: #FF0000; border-width: 2px; border-radius: 0px; ' +
      'background: alpha(#000000,0); color: #000000; font-size: 12px; }');
    Probe := TTyGroupBoxProbe.Create(Form);
    Probe.Parent := Form;
    Probe.Controller := Ctl;
    Probe.Caption := '组';
    Probe.SetBounds(0, 0, 185, 105);
    Probe.Font.PixelsPerInch := 96;

    // Fill canvas white so erased regions show white
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(185, 105);
    BgBmp := TBGRABitmap.Create(185, 105, BGRA(255, 255, 255, 255));
    try
      BgBmp.Draw(Bmp.Canvas, 0, 0, False);
    finally
      BgBmp.Free;
    end;

    Probe.RenderTo(Bmp.Canvas, Rect(0, 0, 185, 105), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // CapH = MulDiv(16, 96, 96) = 16; border is at y = CapH div 2 = 8
      CapY := 8;
      // (a) Far-right pixel at border y — outside the caption band x-range
      PxOutside := Reread.GetPixel(180, CapY);
      AssertTrue('border outside band: red > 100 (border visible)', PxOutside.red > 100);
      AssertTrue('border outside band: red > blue (red-dominant)', PxOutside.red > PxOutside.blue);
      // (b) Pixel inside the erased band (x=20 is safely within the band gap)
      PxInside := Reread.GetPixel(20, CapY);
      AssertTrue('inside erased band: red < 100 (border not visible, white shows through)',
        PxInside.red < 100);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

{ TestClientRectInsetBelowCaption
  PPI pinned to 96. CapH = MulDiv(16, 96, 96) = 16.
  Start with Rect(0, 0, 185, 105), call AdjustClientRect directly,
  assert ARect.Top = 16 (inset by exactly the caption band height). }
procedure TTyGroupBoxTest.TestClientRectInsetBelowCaption;
var
  Probe: TTyGroupBoxProbe;
  ARect: TRect;
begin
  Probe := TTyGroupBoxProbe.Create(FForm);
  Probe.Parent := FForm;
  Probe.Font.PixelsPerInch := 96;
  Probe.SetBounds(0, 0, 185, 105);
  try
    ARect := Rect(0, 0, 185, 105);
    Probe.CallAdjustClientRect(ARect);
    AssertEquals('AdjustClientRect insets Top by caption band height (16px@96ppi)',
      16, ARect.Top);
  finally
    Probe.Free;
  end;
end;

initialization
  RegisterTest(TTyGroupBoxTest);
end.
