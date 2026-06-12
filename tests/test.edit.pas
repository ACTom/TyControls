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
    procedure SimulateKeyDownShift(Key: Word; Shift: TShiftState);
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
    // EDIT.2: selection model
    procedure TestSelLengthZeroInitially;
    procedure TestShiftRightExtendsSelection;
    procedure TestInjectKeyReplacesSelection;
    procedure TestInjectBackspaceDeletesSelection;
    procedure TestInjectDeleteDeletesSelection;
    procedure TestSelectAll;
    procedure TestCollapseOnUnshiftedLeft;
    procedure TestCollapseOnUnshiftedRight;
    procedure TestCtrlASelectsAll;
    procedure TestMetaASelectsAll;
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

procedure TTyEditAccess.SimulateKeyDownShift(Key: Word; Shift: TShiftState);
begin
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

// ---- EDIT.2: selection model tests ----

procedure TEditTest.TestSelLengthZeroInitially;
var
  F: TCustomForm;
  E: TTyEdit;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEdit.Create(F);
    E.Parent := F;
    E.Text := 'a你bc';
    AssertEquals('SelLength is 0 after SetText', 0, E.SelLength);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestShiftRightExtendsSelection;
var
  F: TCustomForm;
  E: TTyEditAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    E.Text := 'a你bc';
    E.CaretPos := 0;
    E.SimulateKeyDownShift(VK_RIGHT, [ssShift]);
    E.SimulateKeyDownShift(VK_RIGHT, [ssShift]);
    AssertEquals('SelStart=0 after Shift+Right x2', 0, E.SelStart);
    AssertEquals('SelLength=2 after Shift+Right x2', 2, E.SelLength);
    AssertEquals('SelText = a你', 'a你', E.SelText);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestInjectKeyReplacesSelection;
var
  F: TCustomForm;
  E: TTyEditAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    E.Text := 'a你bc';
    E.CaretPos := 0;
    E.SimulateKeyDownShift(VK_RIGHT, [ssShift]);
    E.SimulateKeyDownShift(VK_RIGHT, [ssShift]);
    // selection covers 'a你', inject 'X' should replace it
    E.InjectKey('X');
    AssertEquals('Text after replace selection', 'Xbc', E.Text);
    AssertEquals('CaretPos after replace', 1, E.CaretPos);
    AssertEquals('SelLength is 0 after replace', 0, E.SelLength);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestInjectBackspaceDeletesSelection;
var
  F: TCustomForm;
  E: TTyEditAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    // Build selection 1..3: caret at 1, Shift+Right x2
    E.Text := 'a你bc';
    E.CaretPos := 1;
    E.SimulateKeyDownShift(VK_RIGHT, [ssShift]);
    E.SimulateKeyDownShift(VK_RIGHT, [ssShift]);
    AssertEquals('Pre: SelStart=1', 1, E.SelStart);
    AssertEquals('Pre: SelLength=2', 2, E.SelLength);
    E.InjectBackspace;
    AssertEquals('Text after backspace-delete selection', 'ac', E.Text);
    AssertEquals('CaretPos after backspace-delete', 1, E.CaretPos);
    AssertEquals('SelLength=0 after backspace-delete', 0, E.SelLength);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestInjectDeleteDeletesSelection;
var
  F: TCustomForm;
  E: TTyEditAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    // Build selection 1..3: caret at 1, Shift+Right x2
    E.Text := 'a你bc';
    E.CaretPos := 1;
    E.SimulateKeyDownShift(VK_RIGHT, [ssShift]);
    E.SimulateKeyDownShift(VK_RIGHT, [ssShift]);
    E.InjectDelete;
    AssertEquals('Text after delete-delete selection', 'ac', E.Text);
    AssertEquals('CaretPos after delete-delete', 1, E.CaretPos);
    AssertEquals('SelLength=0 after delete-delete', 0, E.SelLength);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestSelectAll;
var
  F: TCustomForm;
  E: TTyEdit;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEdit.Create(F);
    E.Parent := F;
    E.Text := 'a你bc';
    E.SelectAll;
    AssertEquals('SelectAll: SelStart=0', 0, E.SelStart);
    AssertEquals('SelectAll: SelLength=4', 4, E.SelLength);
    AssertEquals('SelectAll: SelText=a你bc', 'a你bc', E.SelText);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestCollapseOnUnshiftedLeft;
var
  F: TCustomForm;
  E: TTyEditAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    E.Text := 'a你bc';
    E.CaretPos := 0;
    // Build selection: Shift+Right x2 -> SelStart=0, SelLength=2, caret=2
    E.SimulateKeyDownShift(VK_RIGHT, [ssShift]);
    E.SimulateKeyDownShift(VK_RIGHT, [ssShift]);
    AssertEquals('Pre: SelLength=2', 2, E.SelLength);
    // plain Left -> collapse to left (SelStart) edge, no extra movement
    E.SimulateKeyDown(VK_LEFT);
    AssertEquals('Caret collapsed to left edge', 0, E.CaretPos);
    AssertEquals('SelLength=0 after collapse left', 0, E.SelLength);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestCollapseOnUnshiftedRight;
var
  F: TCustomForm;
  E: TTyEditAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    E.Text := 'a你bc';
    E.CaretPos := 0;
    // Build selection: Shift+Right x2 -> SelStart=0, SelLength=2, caret=2
    E.SimulateKeyDownShift(VK_RIGHT, [ssShift]);
    E.SimulateKeyDownShift(VK_RIGHT, [ssShift]);
    // plain Right -> collapse to right (SelStart+SelLength) edge, no extra movement
    E.SimulateKeyDown(VK_RIGHT);
    AssertEquals('Caret collapsed to right edge', 2, E.CaretPos);
    AssertEquals('SelLength=0 after collapse right', 0, E.SelLength);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestCtrlASelectsAll;
var
  F: TCustomForm;
  E: TTyEditAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    E.Text := 'a你bc';
    E.SimulateKeyDownShift(VK_A, [ssCtrl]);
    AssertEquals('Ctrl+A: SelStart=0', 0, E.SelStart);
    AssertEquals('Ctrl+A: SelLength=4', 4, E.SelLength);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestMetaASelectsAll;
var
  F: TCustomForm;
  E: TTyEditAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    E.Text := 'a你bc';
    E.SimulateKeyDownShift(VK_A, [ssMeta]);
    AssertEquals('Meta+A: SelStart=0', 0, E.SelStart);
    AssertEquals('Meta+A: SelLength=4', 4, E.SelLength);
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TEditTest);
end.
