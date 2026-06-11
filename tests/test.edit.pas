unit test.edit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Forms, Controls, LCLType,
  tyControls.Base, tyControls.Edit;
type
  TEditTest = class(TTestCase)
  published
    procedure TestTypeKey;
    procedure TestKeyInputAppendsText;
    procedure TestBackspaceRemovesChar;
    procedure TestPaintSmoke;
  end;
implementation

procedure TEditTest.TestTypeKey;
var
  E: TTyEdit;
begin
  E := TTyEdit.Create(nil);
  try
    AssertEquals('TyEdit', (E as ITyStyleable).GetStyleTypeKey);
  finally
    E.Free;
  end;
end;

procedure TEditTest.TestKeyInputAppendsText;
var
  F: TCustomForm;
  E: TTyEdit;
  K: TUTF8Char;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEdit.Create(F);
    E.Parent := F;
    E.Text := '';
    K := 'A';
    E.InjectKey(K);
    K := 'b';
    E.InjectKey(K);
    AssertEquals('Ab', E.Text);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestBackspaceRemovesChar;
var
  F: TCustomForm;
  E: TTyEdit;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEdit.Create(F);
    E.Parent := F;
    E.Text := 'abc';
    E.InjectBackspace;
    AssertEquals('ab', E.Text);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestPaintSmoke;
var
  F: TCustomForm;
  E: TTyEdit;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEdit.Create(F);
    E.Parent := F;
    E.SetBounds(0, 0, 140, 24);
    E.Text := 'typed';
    E.Repaint;
    AssertTrue('edit painted without crash', True);
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TEditTest);
end.
