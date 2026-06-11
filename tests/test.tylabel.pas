unit test.tylabel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Forms, Controls,
  tyControls.Base, tyControls.TyLabel;
type
  TLabelTest = class(TTestCase)
  published
    procedure TestTypeKey;
    procedure TestCaptionProperty;
    procedure TestPaintSmoke;
  end;
implementation

procedure TLabelTest.TestTypeKey;
var
  L: TTyLabel;
begin
  L := TTyLabel.Create(nil);
  try
    AssertEquals('TyLabel', (L as ITyStyleable).GetStyleTypeKey);
  finally
    L.Free;
  end;
end;

procedure TLabelTest.TestCaptionProperty;
var
  L: TTyLabel;
begin
  L := TTyLabel.Create(nil);
  try
    L.Caption := 'Hello';
    AssertEquals('Hello', L.Caption);
  finally
    L.Free;
  end;
end;

procedure TLabelTest.TestPaintSmoke;
var
  F: TCustomForm;
  L: TTyLabel;
begin
  F := TCustomForm.CreateNew(nil);
  try
    L := TTyLabel.Create(F);
    L.Parent := F;
    L.SetBounds(0, 0, 120, 20);
    L.Caption := 'Label';
    L.Repaint;
    AssertTrue('label painted without crash', True);
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TLabelTest);
end.
