unit test.button;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Forms, Controls,
  tyControls.Base, tyControls.Button;
type
  TButtonTest = class(TTestCase)
  private
    FClicked: Integer;
    procedure HandleClick(Sender: TObject);
  published
    procedure TestTypeKey;
    procedure TestOnClickFires;
    procedure TestPaintSmoke;
  end;
implementation

procedure TButtonTest.HandleClick(Sender: TObject);
begin
  Inc(FClicked);
end;

procedure TButtonTest.TestTypeKey;
var
  B: TTyButton;
begin
  B := TTyButton.Create(nil);
  try
    AssertEquals('TyButton', (B as ITyStyleable).GetStyleTypeKey);
  finally
    B.Free;
  end;
end;

procedure TButtonTest.TestOnClickFires;
var
  F: TCustomForm;
  B: TTyButton;
begin
  FClicked := 0;
  F := TCustomForm.CreateNew(nil);
  try
    B := TTyButton.Create(F);
    B.Parent := F;
    B.OnClick := @HandleClick;
    B.Click;
    AssertEquals(1, FClicked);
  finally
    F.Free;
  end;
end;

procedure TButtonTest.TestPaintSmoke;
var
  F: TCustomForm;
  B: TTyButton;
begin
  F := TCustomForm.CreateNew(nil);
  try
    B := TTyButton.Create(F);
    B.Parent := F;
    B.SetBounds(0, 0, 80, 28);
    B.Caption := 'OK';
    B.Repaint;
    AssertTrue('button painted without crash', True);
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TButtonTest);
end.
