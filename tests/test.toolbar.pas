unit test.toolbar;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, Graphics, Forms, LCLType,
  fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.ToolBar, tyControls.Button;
type
  TToolBarGeomTest = class(TTestCase)
  published
    procedure TestLayoutSingleRow;
    procedure TestLayoutWraps;
  end;

  TTyToolBarAccess = class(TTyToolBar)
  public
    procedure ForceLayout;
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TToolBarControlTest = class(TTestCase)
  published
    procedure TestArrangesButtons;
  end;

  TToolBarPixelTest = class(TTestCase)
  published
    procedure TestBottomHairlineIsLighterThanBody;
  end;

implementation

{ TTyToolBarAccess }
procedure TTyToolBarAccess.ForceLayout;
var dummy: TRect;
begin
  // AlignControls uses ClientWidth internally (it ignores the ARect arg); in the headless
  // runner ClientWidth matches TB.Width, so positions are deterministic.
  dummy := Rect(0, 0, Width, Height);
  AlignControls(nil, dummy);
end;

procedure TTyToolBarAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;
procedure TToolBarGeomTest.TestLayoutSingleRow;
var r: TTyRectArray; rows: Integer;
begin
  // two 40x20 items, indent 4, spacing 2, buttonHeight 24, bar 200 wide
  r := TyToolbarLayout([Size(40,20), Size(40,20)], 200, 4, 2, 24, True, rows);
  AssertEquals('rows', 1, rows);
  AssertEquals('i0.left', 4, r[0].Left);     AssertEquals('i0.right', 44, r[0].Right);
  AssertEquals('i1.left', 46, r[1].Left);    AssertEquals('i1.right', 86, r[1].Right);
  AssertEquals('i0.height=buttonHeight', 24, r[0].Bottom - r[0].Top);
end;
procedure TToolBarGeomTest.TestLayoutWraps;
var r: TTyRectArray; rows: Integer;
begin
  // bar only 90 wide -> third item wraps to row 2
  r := TyToolbarLayout([Size(40,20), Size(40,20), Size(40,20)], 90, 4, 2, 24, True, rows);
  AssertEquals('rows', 2, rows);
  AssertEquals('i2 wrapped to indent', 4, r[2].Left);
  AssertEquals('i2.Top = indent + buttonHeight + spacing', 30, r[2].Top);
end;

{ TToolBarControlTest }

procedure TToolBarControlTest.TestArrangesButtons;
var
  Form: TForm;
  TB: TTyToolBarAccess;
  B1, B2: TTyButton;
  ExpectedLeft: Integer;
begin
  // In headless LCL, Realign posts a deferred message that is never processed
  // without a message pump.  We use a thin probe subclass (TTyToolBarAccess)
  // that calls AlignControls directly, bypassing the deferred path.
  // Width is set explicitly so ClientWidth is a known bar width; AlignControls
  // uses ClientWidth internally (it ignores the ARect arg), so positions are deterministic.
  Form := TForm.CreateNew(nil);
  try
    Form.SetBounds(0, 0, 400, 200);

    TB := TTyToolBarAccess.Create(Form);
    TB.Parent := Form;
    // alNone: prevent LCL alignment engine from fighting our explicit bounds
    TB.Align := alNone;
    TB.Width := 300;
    TB.Indent := 4;
    TB.ButtonSpacing := 2;
    TB.ButtonHeight := 24;
    TB.Wrapable := True;

    B1 := TTyButton.Create(Form);
    B1.Parent := TB;
    B1.Width := 60;

    B2 := TTyButton.Create(Form);
    B2.Parent := TB;
    B2.Width := 60;

    // Direct synchronous layout call (probe exposes the protected AlignControls).
    // The dummy rect uses TB.Width so the bar-width is 300 and no wrapping occurs.
    TB.ForceLayout;

    // Button 1 should start at Indent; Button 2 right after: Indent + B1.Width + ButtonSpacing
    AssertEquals('b1.Left = indent', TB.Indent, B1.Left);
    ExpectedLeft := TB.Indent + B1.Width + TB.ButtonSpacing;
    AssertEquals('b2.Left = indent + b1.width + spacing', ExpectedLeft, B2.Left);
  finally
    Form.Free;
  end;
end;

{ TToolBarPixelTest }

procedure TToolBarPixelTest.TestBottomHairlineIsLighterThanBody;
{ Theme: background: #202020 (32,32,32), border-color: #404040 (64,64,64).
  Control: 200x30 toolbar. RenderTo draws the full body in #202020 and
  a 1px bottom hairline in #404040 (border-color).
  At PPI 96, Scale(BorderWidth=1) = 1px, so y=29 is the hairline row.
  Assert the bottom row (y=29) red channel > mid-body (y=15) red channel.
}
var
  Ctl: TTyStyleController;
  Form: TForm;
  TB: TTyToolBarAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  PxBody, PxHairline: TBGRAPixel;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyToolBar { background: #202020; border-color: #404040; border-width: 1px; }');

    TB := TTyToolBarAccess.Create(Form);
    TB.Parent := Form;
    TB.Controller := Ctl;
    TB.Align := alNone;
    TB.SetBounds(0, 0, 200, 30);
    TB.Font.PixelsPerInch := 96;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 30);
    TB.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 30), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // Mid-body pixel (x=10, y=15): should be dark #202020
      PxBody := Reread.GetPixel(10, 15);
      // Bottom hairline pixel (x=10, y=29): should be #404040 — lighter
      PxHairline := Reread.GetPixel(10, 29);

      AssertTrue(
        Format('body pixel should be dark (r=%d g=%d b=%d, expected < 60)',
          [PxBody.red, PxBody.green, PxBody.blue]),
        (PxBody.red < 60) and (PxBody.green < 60) and (PxBody.blue < 60));

      AssertTrue(
        Format('bottom hairline should be lighter than body (hairline.red=%d > body.red=%d)',
          [PxHairline.red, PxBody.red]),
        PxHairline.red > PxBody.red);
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
  RegisterTest(TToolBarGeomTest);
  RegisterTest(TToolBarControlTest);
  RegisterTest(TToolBarPixelTest);
end.
