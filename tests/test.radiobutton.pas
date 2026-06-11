unit test.radiobutton;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Forms, Controls, ExtCtrls,
  tyControls.Base, tyControls.CheckBox;
type
  TRadioButtonTest = class(TTestCase)
  published
    procedure TestTypeKey;
    procedure TestClickClearsGroup;
    procedure TestSeparateParentsAreIndependent;
  end;
implementation

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

initialization
  RegisterTest(TRadioButtonTest);
end.
