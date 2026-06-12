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
    procedure TestCaptionRowHasNonTransparentPixel;
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

procedure TTyGroupBoxTest.TestCaptionRowHasNonTransparentPixel;
{ When Caption <> '' with a styled background, at least one pixel in the
  caption band (y ~ capH/2 = 8) should be visible (not black/transparent).
  We use a bright red background to make it easy to detect.
  Pixel at (50, 8) inside caption band should have some red presence. }
var
  Ctl: TTyStyleController;
  Form: TForm;
  Probe: TTyGroupBoxProbe;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  PxCaption: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyGroupBox { background: #FF0000; border-color: #FFFFFF; border-width: 1px; border-radius: 0px; color: #FFFFFF; font-size: 12px; }');
    Probe := TTyGroupBoxProbe.Create(Form);
    Probe.Parent := Form;
    Probe.Controller := Ctl;
    Probe.Caption := 'Group';
    Probe.SetBounds(0, 0, 185, 105);
    Probe.Font.PixelsPerInch := 96;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(185, 105);
    Probe.RenderTo(Bmp.Canvas, Rect(0, 0, 185, 105), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Caption band near y=8 (half of capH=16). Check pixel at x=50
      PxCaption := Reread.GetPixel(50, 8);
      // With red background, alpha must be > 0 and red > 0
      AssertTrue('caption band: alpha > 0 (something painted)', PxCaption.alpha > 0);
      AssertTrue('caption band: red > 100 (background color visible)', PxCaption.red > 100);
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
