unit test.radiobutton;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Forms, Controls, ExtCtrls, Graphics, LCLType,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.CheckBox;
type
  TTyRadioButtonAccess = class(TTyRadioButton)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure DoKeyDown(var Key: Word; Shift: TShiftState);
  end;

  TRadioButtonTest = class(TTestCase)
  published
    procedure TestTypeKey;
    procedure TestClickClearsGroup;
    procedure TestSeparateParentsAreIndependent;
    procedure TestPaintSmoke;
    procedure TestRadioButtonShadowLocalRectAtOffset;
    procedure TestSpaceSelectsRadio;
    procedure TestGroupIndexSeparatesGroups;
  end;
implementation

procedure TTyRadioButtonAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyRadioButtonAccess.DoKeyDown(var Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;

procedure TRadioButtonTest.TestTypeKey;
var
  Rb: TTyRadioButton;
begin
  Rb := TTyRadioButton.Create(nil);
  try
    AssertEquals('TyRadioButton', (Rb as ITyStyleable).GetStyleTypeKey);
  finally
    Rb.Free;
  end;
end;

procedure TRadioButtonTest.TestClickClearsGroup;
var
  F: TCustomForm;
  A, B, C: TTyRadioButton;
begin
  F := TCustomForm.CreateNew(nil);
  try
    A := TTyRadioButton.Create(F); A.Parent := F;
    B := TTyRadioButton.Create(F); B.Parent := F;
    C := TTyRadioButton.Create(F); C.Parent := F;
    A.Click;
    AssertTrue('A checked', A.Checked);
    B.Click;
    AssertTrue('B checked', B.Checked);
    AssertFalse('A cleared by B', A.Checked);
    AssertFalse('C still clear', C.Checked);
  finally
    F.Free;
  end;
end;

procedure TRadioButtonTest.TestSeparateParentsAreIndependent;
var
  F: TCustomForm;
  P1, P2: TPanel;
  A, B: TTyRadioButton;
begin
  F := TCustomForm.CreateNew(nil);
  try
    P1 := TPanel.Create(F); P1.Parent := F;
    P2 := TPanel.Create(F); P2.Parent := F;
    A := TTyRadioButton.Create(F); A.Parent := P1;
    B := TTyRadioButton.Create(F); B.Parent := P2;
    A.Click;
    B.Click;
    AssertTrue('A stays checked in its own group', A.Checked);
    AssertTrue('B checked in its own group', B.Checked);
  finally
    F.Free;
  end;
end;

procedure TRadioButtonTest.TestPaintSmoke;
var
  F: TCustomForm;
  R: TTyRadioButtonAccess;
  Bmp: TBitmap;
begin
  F := TCustomForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    R := TTyRadioButtonAccess.Create(F);
    R.Parent := F;
    R.Caption := 'Option A';
    R.Checked := True;
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 22);
    R.RenderTo(Bmp.Canvas, Rect(0, 0, 120, 22), 96);
    AssertTrue('radiobutton RenderTo executed without exception', True);
  finally
    Bmp.Free;
    F.Free;
  end;
end;

procedure TRadioButtonTest.TestRadioButtonShadowLocalRectAtOffset;
{ Same offset-origin regression as the checkbox: RenderTo must pass a (0,0)-local
  rect to DrawFrame so the shadow lands inside the W x H painter bitmap, not at
  the absolute ARect origin where it is shifted and clipped. }
var
  Ctl: TTyStyleController;
  R: TTyRadioButtonAccess;
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
      'TyRadioButton { shadow: 0px 0px 0px #FF0000FF; border-width: 0px; ' +
      'background: alpha(#000000, 0); }');
    R := TTyRadioButtonAccess.Create(Form);
    R.Parent := Form;
    R.Controller := Ctl;
    R.Font.PixelsPerInch := 96;
    R.Caption := '';
    R.Checked := False;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 40);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 120, 40);
    R.RenderTo(Bmp.Canvas, Rect(20, 5, 100, 33), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      Px := Reread.GetPixel(24, 9);
      AssertTrue('local box interior must be red-dominant (shadow at local rect)',
        (Px.red > 200) and (Px.green < 80) and (Px.blue < 80));

      MaxRedInside := 0;
      for Y := 6 to 31 do
        for X := 21 to 99 do
        begin
          Px := Reread.GetPixel(X, Y);
          if (Px.green < 80) and (Px.blue < 80) and (Px.red > MaxRedInside) then
            MaxRedInside := Px.red;
        end;
      AssertTrue('max red intensity inside the control rect > 200', MaxRedInside > 200);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TRadioButtonTest.TestSpaceSelectsRadio;
var F: TCustomForm; R: TTyRadioButtonAccess; K: Word;
begin
  F := TCustomForm.CreateNew(nil);
  try
    R := TTyRadioButtonAccess.Create(F); R.Parent := F;
    AssertFalse('starts unchecked', R.Checked);
    K := VK_SPACE; R.DoKeyDown(K, []);
    AssertTrue('space selected it', R.Checked);
    AssertEquals('space consumed', 0, Integer(K));
  finally F.Free; end;
end;

procedure TRadioButtonTest.TestGroupIndexSeparatesGroups;
var F: TCustomForm; A, B, C, D: TTyRadioButton;
begin
  F := TCustomForm.CreateNew(nil);
  try
    // group 0: A,B ; group 1: C,D ; all under the SAME parent F
    A := TTyRadioButton.Create(F); A.Parent := F; A.GroupIndex := 0;
    B := TTyRadioButton.Create(F); B.Parent := F; B.GroupIndex := 0;
    C := TTyRadioButton.Create(F); C.Parent := F; C.GroupIndex := 1;
    D := TTyRadioButton.Create(F); D.Parent := F; D.GroupIndex := 1;
    A.Click; C.Click;
    AssertTrue('A checked', A.Checked);
    AssertTrue('C checked (other group)', C.Checked);
    B.Click;
    AssertFalse('A cleared by B (same group)', A.Checked);
    AssertTrue('C still checked (different group)', C.Checked);
    D.Click;
    AssertFalse('C cleared by D (same group)', C.Checked);
    AssertTrue('B still checked (different group)', B.Checked);
  finally F.Free; end;
end;

initialization
  RegisterTest(TRadioButtonTest);
end.
