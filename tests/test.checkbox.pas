unit test.checkbox;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Forms, Controls,
  tyControls.Base, tyControls.CheckBox;
type
  TCheckBoxTest = class(TTestCase)
  published
    procedure TestTypeKey;
    procedure TestClickTogglesChecked;
    procedure TestPaintSmoke;
  end;
implementation

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
  C: TTyCheckBox;
begin
  F := TCustomForm.CreateNew(nil);
  try
    C := TTyCheckBox.Create(F);
    C.Parent := F;
    C.SetBounds(0, 0, 120, 22);
    C.Caption := 'Accept';
    C.Checked := True;
    C.Repaint;
    AssertTrue('checkbox painted without crash', True);
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TCheckBoxTest);
end.
