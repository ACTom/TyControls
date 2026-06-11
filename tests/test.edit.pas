unit test.edit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Forms, Controls, Graphics, LCLType,
  tyControls.Base, tyControls.Edit;
type
  TTyEditAccess = class(TTyEdit)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;

  TEditTest = class(TTestCase)
  published
    procedure TestTypeKey;
    procedure TestKeyInputAppendsText;
    procedure TestBackspaceRemovesChar;
    procedure TestBackspaceUTF8;
    procedure TestPaintSmoke;
  end;
implementation

procedure TTyEditAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

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

procedure TEditTest.TestBackspaceUTF8;
var
  F: TCustomForm;
  E: TTyEdit;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEdit.Create(F);
    E.Parent := F;
    // 'a' + Chinese char '你' (UTF-8: 3 bytes E4 BD A0)
    E.Text := 'a你';
    E.InjectBackspace;
    AssertEquals('UTF-8 backspace removes whole codepoint', 'a', E.Text);
    // café: backspace should remove 'é' (2 bytes C3 A9) leaving 'caf'
    E.Text := 'café';
    E.InjectBackspace;
    AssertEquals('UTF-8 backspace removes accented char', 'caf', E.Text);
    // ASCII: still works
    E.Text := 'abc';
    E.InjectBackspace;
    AssertEquals('ASCII backspace still works', 'ab', E.Text);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestPaintSmoke;
var
  F: TCustomForm;
  E: TTyEditAccess;
  Bmp: TBitmap;
begin
  F := TCustomForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    E.Text := 'typed';
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(140, 24);
    E.RenderTo(Bmp.Canvas, Rect(0, 0, 140, 24), 96);
    AssertTrue('edit RenderTo executed without exception', True);
  finally
    Bmp.Free;
    F.Free;
  end;
end;

initialization
  RegisterTest(TEditTest);
end.
