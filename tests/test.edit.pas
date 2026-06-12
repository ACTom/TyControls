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
    procedure SimulateKeyDown(Key: Word);
  end;

  TEditTest = class(TTestCase)
  published
    procedure TestTypeKey;
    procedure TestKeyInputAppendsText;
    procedure TestBackspaceRemovesChar;
    procedure TestBackspaceUTF8;
    procedure TestPaintSmoke;
    // EDIT.1: caret model
    procedure TestCaretDefaultsToEnd;
    procedure TestCaretClamps;
    procedure TestInsertAtCaret;
    procedure TestBackspaceAtCaret;
    procedure TestDeleteAtCaret;
    procedure TestDeleteAtEndIsNoop;
    procedure TestCaretKeys;
  end;
implementation

procedure TTyEditAccess.RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  inherited RenderTo(ACanvas, ARect, APPI);
end;

procedure TTyEditAccess.SimulateKeyDown(Key: Word);
var
  Shift: TShiftState;
begin
  Shift := [];
  KeyDown(Key, Shift);
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

// ---- EDIT.1 caret model tests ----

procedure TEditTest.TestCaretDefaultsToEnd;
var
  F: TCustomForm;
  E: TTyEdit;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEdit.Create(F);
    E.Parent := F;
    E.Text := 'a你b';
    AssertEquals('CaretPos defaults to end after SetText', 3, E.CaretPos);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestCaretClamps;
var
  F: TCustomForm;
  E: TTyEdit;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEdit.Create(F);
    E.Parent := F;
    E.Text := 'a你b';
    E.CaretPos := 99;
    AssertEquals('CaretPos clamped to end (3)', 3, E.CaretPos);
    E.CaretPos := -1;
    AssertEquals('CaretPos clamped to 0', 0, E.CaretPos);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestInsertAtCaret;
var
  F: TCustomForm;
  E: TTyEdit;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEdit.Create(F);
    E.Parent := F;
    E.Text := 'a你b';
    E.CaretPos := 1;
    E.InjectKey('X');
    AssertEquals('Text after insert at caret 1', 'aX你b', E.Text);
    AssertEquals('CaretPos advances to 2', 2, E.CaretPos);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestBackspaceAtCaret;
var
  F: TCustomForm;
  E: TTyEdit;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEdit.Create(F);
    E.Parent := F;
    // Set text then position caret after '你' (index 2)
    E.Text := 'a你b';
    E.CaretPos := 2;
    E.InjectBackspace;
    AssertEquals('Text after backspace at caret 2 removes 你', 'ab', E.Text);
    AssertEquals('CaretPos retreats to 1', 1, E.CaretPos);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestDeleteAtCaret;
var
  F: TCustomForm;
  E: TTyEdit;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEdit.Create(F);
    E.Parent := F;
    E.Text := 'a你b';
    E.CaretPos := 1;
    E.InjectDelete;
    AssertEquals('Text after delete at caret 1 removes 你', 'ab', E.Text);
    AssertEquals('CaretPos stays at 1', 1, E.CaretPos);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestDeleteAtEndIsNoop;
var
  F: TCustomForm;
  E: TTyEdit;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEdit.Create(F);
    E.Parent := F;
    E.Text := 'a你b';
    E.CaretPos := 3;
    E.InjectDelete;
    AssertEquals('InjectDelete at end is no-op', 'a你b', E.Text);
    AssertEquals('CaretPos stays at end', 3, E.CaretPos);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestCaretKeys;
var
  F: TCustomForm;
  E: TTyEditAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    E.Text := 'a你b';
    // starts at end (3)
    E.SimulateKeyDown(VK_LEFT);
    AssertEquals('VK_LEFT from 3 -> 2', 2, E.CaretPos);
    E.SimulateKeyDown(VK_RIGHT);
    AssertEquals('VK_RIGHT from 2 -> 3', 3, E.CaretPos);
    // clamp at right end
    E.SimulateKeyDown(VK_RIGHT);
    AssertEquals('VK_RIGHT clamps at end (3)', 3, E.CaretPos);
    // VK_HOME
    E.SimulateKeyDown(VK_HOME);
    AssertEquals('VK_HOME -> 0', 0, E.CaretPos);
    // clamp at left end
    E.SimulateKeyDown(VK_LEFT);
    AssertEquals('VK_LEFT clamps at 0', 0, E.CaretPos);
    // VK_END
    E.SimulateKeyDown(VK_END);
    AssertEquals('VK_END -> 3', 3, E.CaretPos);
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TEditTest);
end.
