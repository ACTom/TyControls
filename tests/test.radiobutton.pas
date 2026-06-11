unit test.radiobutton;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Forms, Controls, ExtCtrls, Graphics,
  tyControls.Base, tyControls.CheckBox;
type
  TTyRadioButtonAccess = class(TTyRadioButton)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TRadioButtonTest = class(TTestCase)
  published
    procedure TestTypeKey;
    procedure TestClickClearsGroup;
    procedure TestSeparateParentsAreIndependent;
    procedure TestPaintSmoke;
  end;
implementation

procedure TTyRadioButtonAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
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

initialization
  RegisterTest(TRadioButtonTest);
end.
