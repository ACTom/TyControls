unit test.checkbox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Forms, Controls, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.CheckBox;
type
  TTyCheckBoxAccess = class(TTyCheckBox)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure DoKeyDown(var Key: Word; Shift: TShiftState);
  end;

  TCheckBoxTest = class(TTestCase)
  published
    procedure TestTypeKey;
    procedure TestClickTogglesChecked;
    procedure TestPaintSmoke;
    procedure TestDrawFrameOpacityApplied;
    procedure TestDisabledClickIgnored;
    procedure TestCheckBoxShadowLocalRectAtOffset;
    procedure TestSpaceTogglesChecked;
    procedure TestDisabledSpaceNoToggle;
  end;
implementation

procedure TTyCheckBoxAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyCheckBoxAccess.DoKeyDown(var Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
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

procedure TCheckBoxTest.TestCheckBoxShadowLocalRectAtOffset;
{ Offset-origin regression: RenderTo must pass a (0,0)-local rect to DrawFrame,
  not the caller's absolute ARect. The painter builds a (W x H) bitmap and blits
  it at ARect.Left/Top; if DrawFrame receives the absolute rect, the shadow is
  drawn at (ARect.Left, ARect.Top) inside the W x H bitmap, shifting it off the
  control and clipping it.

  Theme: zero-blur, zero-offset, opaque red shadow that fills the rounded box
  rect; background fully transparent and border-width 0 (so only the shadow
  paints). Render an 80x28 checkbox at Rect(20,5,100,33) into a 120x40 white
  bitmap.
  - With the bug: shadow shifted by (20,5) and clipped, so the control's local
    interior (host pixels just inside (20,5)) stays white.
  - With the fix: shadow fills the local box rect, so those pixels are red. }
var
  Ctl: TTyStyleController;
  C: TTyCheckBoxAccess;
  Form: TForm;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  X, Y, MaxRedInside: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyCheckBox { shadow: 0px 0px 0px #FF0000FF; border-width: 0px; ' +
      'background: alpha(#000000, 0); }');
    C := TTyCheckBoxAccess.Create(Form);
    C.Parent := Form;
    C.Controller := Ctl;
    C.Font.PixelsPerInch := 96;
    C.Caption := '';
    C.Checked := False;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 40);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 120, 40);
    { Render an 80x28 control at a non-zero origin. }
    C.RenderTo(Bmp.Canvas, Rect(20, 5, 100, 33), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      { The 16px box sits at the control's left edge, vertically centred in 28px.
        Probe a host pixel 4px inside the control origin -> (24, 9). The shadow
        fills the box rect, so with the fix this is red; with the bug it is the
        white backdrop. }
      Px := Reread.GetPixel(24, 9);
      AssertTrue('local box interior must be red-dominant (shadow at local rect)',
        (Px.red > 200) and (Px.green < 80) and (Px.blue < 80));

      { Robustness: scan the control rect's interior for the maximum red and
        assert a clearly-red pixel exists somewhere inside the box area. }
      MaxRedInside := 0;
      for Y := 6 to 31 do
        for X := 21 to 99 do
        begin
          Px := Reread.GetPixel(X, Y);
          if (Px.green < 80) and (Px.blue < 80) and (Px.red > MaxRedInside) then
            MaxRedInside := Px.red;
        end;
      AssertTrue('max red intensity inside the control rect > 200', MaxRedInside > 200);

      { The shadow must NOT be translated past the control's right/bottom edge:
        no red pixels should appear beyond x=100 or y=33 (the control's extent),
        which is where a shifted-and-clipped shadow could never reach anyway, but
        more importantly the fill stays within the local box, not pushed outside. }
      AssertTrue('no red leak below the control (host y=37)',
        not ((Reread.GetPixel(24, 37).red > 200) and
             (Reread.GetPixel(24, 37).green < 80)));
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TCheckBoxTest.TestSpaceTogglesChecked;
var F: TCustomForm; C: TTyCheckBoxAccess; K: Word;
begin
  F := TCustomForm.CreateNew(nil);
  try
    C := TTyCheckBoxAccess.Create(F); C.Parent := F;
    AssertFalse('starts unchecked', C.Checked);
    K := VK_SPACE; C.DoKeyDown(K, []);
    AssertTrue('space checked it', C.Checked);
    AssertEquals('space consumed', 0, Integer(K));
  finally F.Free; end;
end;

procedure TCheckBoxTest.TestDisabledSpaceNoToggle;
var F: TCustomForm; C: TTyCheckBoxAccess; K: Word;
begin
  F := TCustomForm.CreateNew(nil);
  try
    C := TTyCheckBoxAccess.Create(F); C.Parent := F; C.Enabled := False;
    K := VK_SPACE; C.DoKeyDown(K, []);
    AssertFalse('disabled: not toggled', C.Checked);
  finally F.Free; end;
end;

initialization
  RegisterTest(TCheckBoxTest);
end.
