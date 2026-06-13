unit test.checkbox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Forms, Controls, Graphics,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.CheckBox;
type
  TTyCheckBoxAccess = class(TTyCheckBox)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TCheckBoxTest = class(TTestCase)
  published
    procedure TestTypeKey;
    procedure TestClickTogglesChecked;
    procedure TestPaintSmoke;
    procedure TestDrawFrameOpacityApplied;
    procedure TestDisabledClickIgnored;
  end;
implementation

procedure TTyCheckBoxAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TCheckBoxTest.TestTypeKey;
var
  C: TTyCheckBox;
begin
  C := TTyCheckBox.Create(nil);
  try
    AssertEquals('TyCheckBox', (C as ITyStyleable).GetStyleTypeKey);
  finally
    C.Free;
  end;
end;

procedure TCheckBoxTest.TestClickTogglesChecked;
var
  F: TCustomForm;
  C: TTyCheckBox;
begin
  F := TCustomForm.CreateNew(nil);
  try
    C := TTyCheckBox.Create(F);
    C.Parent := F;
    AssertFalse('starts unchecked', C.Checked);
    C.Click;
    AssertTrue('checked after first click', C.Checked);
    C.Click;
    AssertFalse('unchecked after second click', C.Checked);
  finally
    F.Free;
  end;
end;

procedure TCheckBoxTest.TestPaintSmoke;
var
  F: TCustomForm;
  C: TTyCheckBoxAccess;
  Bmp: TBitmap;
begin
  F := TCustomForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    C := TTyCheckBoxAccess.Create(F);
    C.Parent := F;
    C.Caption := 'Accept';
    C.Checked := True;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 22);
    C.RenderTo(Bmp.Canvas, Rect(0, 0, 120, 22), 96);
    AssertTrue('checkbox RenderTo executed without exception', True);
  finally
    Bmp.Free;
    F.Free;
  end;
end;

procedure TCheckBoxTest.TestDrawFrameOpacityApplied;
{ Stylesheet: background #FF0000, opacity 0.5. Render over white.
  The theme background styles the BOX (not the whole control), so:
  - a BOX-interior pixel must be a ~50% blend of red over white
    (G and B between 100 and 160 — opacity applied via DrawFrame);
  - a CAPTION-area pixel must stay pure white (no control-wide fill —
    guards the regression where DrawFrame painted S.Background full-width).
  If DrawFrame was not called at all, opacity would not apply and the
  box pixel would be full red (G=0, B=0). }
var
  Ctl: TTyStyleController;
  C: TTyCheckBoxAccess;
  Form: TForm;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyCheckBox { opacity: 0.5; background: #FF0000; border-width: 0px; }');
    C := TTyCheckBoxAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Caption := '';
    C.Checked := False;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 22);
    // White backdrop
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 120, 22);
    C.RenderTo(Bmp.Canvas, Rect(0, 0, 120, 22), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Box interior: box is 16px @96ppi at the left edge, vertically
      // centered in 22px -> spans (0,3)-(16,19); probe its middle.
      Px := Reread.GetPixel(8, 11);
      AssertTrue('box opacity: green > 100 (white bleeds through)',  Px.green > 100);
      AssertTrue('box opacity: green < 160 (not fully white)',       Px.green < 160);
      AssertTrue('box opacity: blue > 100 (white bleeds through)',   Px.blue > 100);
      AssertTrue('box opacity: blue < 160 (not fully white)',        Px.blue < 160);
      // Caption area: must remain untouched white (no control-wide fill).
      Px := Reread.GetPixel(60, 11);
      AssertTrue('caption area stays white (R)', Px.red >= 250);
      AssertTrue('caption area stays white (G)', Px.green >= 250);
      AssertTrue('caption area stays white (B)', Px.blue >= 250);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TCheckBoxTest.TestDisabledClickIgnored;
var
  C: TTyCheckBox;
  R: TTyRadioButton;
begin
  C := TTyCheckBox.Create(nil);
  try
    C.Enabled := False;
    C.Click;
    AssertFalse('disabled checkbox click ignored', C.Checked);
  finally
    C.Free;
  end;
  R := TTyRadioButton.Create(nil);
  try
    R.Enabled := False;
    R.Click;
    AssertFalse('disabled radiobutton click ignored', R.Checked);
  finally
    R.Free;
  end;
end;

initialization
  RegisterTest(TCheckBoxTest);
end.
