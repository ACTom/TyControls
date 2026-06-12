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
{ Stylesheet: background #FF0000, opacity 0.5.
  Render over a white-filled TBitmap.
  The full control rect should be a ~50% blend of red over white:
    R = 0.5*255 + 0.5*255 = 255 (high)
    G = 0.5*0   + 0.5*255 = ~128 (between 100 and 160)
    B = 0.5*0   + 0.5*255 = ~128 (between 100 and 160)
  If DrawFrame was NOT called, opacity would not apply and the pixel
  would be full red (G=0, B=0) because box rendering draws directly. }
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
      // Sample a pixel in the top-left area that is clearly within ARect
      // and covered by the DrawFrame background fill (the full control rect).
      // We pick x=60, y=11 (center) which is well away from the box-square edge.
      Px := Reread.GetPixel(60, 11);
      AssertTrue('DrawFrame opacity: green > 100 (white bleeds through)',  Px.green > 100);
      AssertTrue('DrawFrame opacity: green < 160 (not fully white)',       Px.green < 160);
      AssertTrue('DrawFrame opacity: blue > 100 (white bleeds through)',   Px.blue > 100);
      AssertTrue('DrawFrame opacity: blue < 160 (not fully white)',        Px.blue < 160);
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
  RegisterTest(TCheckBoxTest);
end.
