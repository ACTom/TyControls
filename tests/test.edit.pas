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
    procedure SimulateMouseDown(X, Y: Integer; Shift: TShiftState = []);
    procedure SimulateMouseMove(X, Y: Integer; Shift: TShiftState = []);
    procedure SimulateMouseUp(X, Y: Integer);
  end;

  // Subclass with in-memory clipboard for headless testing
  TTyEditClipboardAccess = class(TTyEditAccess)
  private
    FClipText: string;
  protected
    function ReadClipboardText: string; override;
    procedure WriteClipboardText(const S: string); override;
  public
    property ClipText: string read FClipText write FClipText;
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
    // EDIT.3: mouse caret + clipboard
    procedure TestCaretIndexAtXBounds;
    procedure TestCaretIndexAtXMonotonic;
    procedure TestMouseDownPositionsCaret;
    procedure TestMouseDragSelects;
    procedure TestDoubleClickSelectsAll;
    procedure TestCopyToClipboard;
    procedure TestCutToClipboard;
    procedure TestPasteFromClipboard;
    procedure TestPasteStripsNewlines;
    procedure TestCtrlCCopies;
    procedure TestCtrlXCuts;
    procedure TestCtrlVPastes;
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

procedure TTyEditAccess.SimulateMouseDown(X, Y: Integer; Shift: TShiftState);
begin
  MouseDown(mbLeft, Shift, X, Y);
end;

procedure TTyEditAccess.SimulateMouseMove(X, Y: Integer; Shift: TShiftState);
begin
  MouseMove(Shift, X, Y);
end;

procedure TTyEditAccess.SimulateMouseUp(X, Y: Integer);
begin
  MouseUp(mbLeft, [], X, Y);
end;

// TTyEditClipboardAccess

function TTyEditClipboardAccess.ReadClipboardText: string;
begin
  Result := FClipText;
end;

procedure TTyEditClipboardAccess.WriteClipboardText(const S: string);
begin
  FClipText := S;
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

// ---- EDIT.3: mouse caret + clipboard tests ----

procedure TEditTest.TestCaretIndexAtXBounds;
var
  F: TCustomForm;
  E: TTyEditAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    E.Text := 'Hello';
    // x=0 or below left padding → caret at 0
    AssertEquals('x=0 → caret 0', 0, E.CaretIndexAtX(0));
    // very large x → caret at end
    AssertEquals('x=10000 → caret at len', 5, E.CaretIndexAtX(10000));
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestCaretIndexAtXMonotonic;
var
  F: TCustomForm;
  E: TTyEditAccess;
  PrevIdx, Idx: Integer;
  X: Integer;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    E.Text := 'abcde';
    PrevIdx := -1;
    X := 0;
    while X <= 300 do
    begin
      Idx := E.CaretIndexAtX(X);
      AssertTrue('CaretIndexAtX must be non-decreasing at x=' + IntToStr(X),
        Idx >= PrevIdx);
      PrevIdx := Idx;
      Inc(X, 5);
    end;
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestMouseDownPositionsCaret;
var
  F: TCustomForm;
  E: TTyEditAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    E.Text := 'Hello';
    // Click at x=0 should position caret at 0
    E.SimulateMouseDown(0, 5);
    AssertEquals('MouseDown at x=0 sets caret to 0', 0, E.CaretPos);
    AssertEquals('MouseDown at x=0: no selection', 0, E.SelLength);
    // Click at far right should position caret at end
    E.SimulateMouseDown(10000, 5);
    AssertEquals('MouseDown at far x sets caret to end', 5, E.CaretPos);
    AssertEquals('MouseDown at far x: no selection', 0, E.SelLength);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestMouseDragSelects;
var
  F: TCustomForm;
  E: TTyEditAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    E.Text := 'Hello';
    // Click at start, drag to end
    E.SimulateMouseDown(0, 5);
    AssertEquals('After MouseDown anchor=0', 0, E.SelLength);
    // Move to far right while button is down
    E.SimulateMouseMove(10000, 5);
    // Should have a selection from 0 to end
    AssertEquals('After drag SelStart=0', 0, E.SelStart);
    AssertEquals('After drag SelLength=5', 5, E.SelLength);
    // Release
    E.SimulateMouseUp(10000, 5);
    // Selection should remain after release
    AssertEquals('Selection persists after MouseUp', 5, E.SelLength);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestDoubleClickSelectsAll;
var
  F: TCustomForm;
  E: TTyEditAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    E.Text := 'Hello';
    // Simulate double-click: pass ssDouble in Shift
    E.SimulateMouseDown(5, 5, [ssDouble]);
    AssertEquals('Double-click SelStart=0', 0, E.SelStart);
    AssertEquals('Double-click SelLength=5', 5, E.SelLength);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestCopyToClipboard;
var
  F: TCustomForm;
  E: TTyEditClipboardAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditClipboardAccess.Create(F);
    E.Parent := F;
    E.Text := 'Hello';
    // Select 'ell'
    E.CaretPos := 1;
    E.SimulateKeyDownShift(VK_RIGHT, [ssShift]);
    E.SimulateKeyDownShift(VK_RIGHT, [ssShift]);
    E.SimulateKeyDownShift(VK_RIGHT, [ssShift]);
    AssertEquals('Pre: SelText=ell', 'ell', E.SelText);
    E.CopyToClipboard;
    AssertEquals('CopyToClipboard writes SelText to clipboard', 'ell', E.ClipText);
    // Text unchanged
    AssertEquals('Text unchanged after copy', 'Hello', E.Text);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestCutToClipboard;
var
  F: TCustomForm;
  E: TTyEditClipboardAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditClipboardAccess.Create(F);
    E.Parent := F;
    E.Text := 'Hello';
    E.CaretPos := 1;
    E.SimulateKeyDownShift(VK_RIGHT, [ssShift]);
    E.SimulateKeyDownShift(VK_RIGHT, [ssShift]);
    E.SimulateKeyDownShift(VK_RIGHT, [ssShift]);
    AssertEquals('Pre: SelText=ell', 'ell', E.SelText);
    E.CutToClipboard;
    AssertEquals('CutToClipboard writes to clipboard', 'ell', E.ClipText);
    AssertEquals('CutToClipboard removes selection from Text', 'Ho', E.Text);
    AssertEquals('CutToClipboard: SelLength=0', 0, E.SelLength);
    AssertEquals('CutToClipboard: CaretPos=1', 1, E.CaretPos);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestPasteFromClipboard;
var
  F: TCustomForm;
  E: TTyEditClipboardAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditClipboardAccess.Create(F);
    E.Parent := F;
    E.Text := 'Hi';
    E.CaretPos := 1;
    E.ClipText := 'AB';
    E.PasteFromClipboard;
    AssertEquals('Paste inserts at caret', 'HABi', E.Text);
    AssertEquals('Paste advances caret', 3, E.CaretPos);
    AssertEquals('Paste: no selection', 0, E.SelLength);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestPasteStripsNewlines;
var
  F: TCustomForm;
  E: TTyEditClipboardAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditClipboardAccess.Create(F);
    E.Parent := F;
    E.Text := '';
    E.ClipText := 'ab' + #13#10 + 'cd';
    E.PasteFromClipboard;
    AssertEquals('Paste strips CR+LF', 'abcd', E.Text);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestCtrlCCopies;
var
  F: TCustomForm;
  E: TTyEditClipboardAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditClipboardAccess.Create(F);
    E.Parent := F;
    E.Text := 'Test';
    E.SelectAll;
    E.SimulateKeyDownShift(VK_C, [ssCtrl]);
    AssertEquals('Ctrl+C copies to clipboard', 'Test', E.ClipText);
    AssertEquals('Ctrl+C: text unchanged', 'Test', E.Text);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestCtrlXCuts;
var
  F: TCustomForm;
  E: TTyEditClipboardAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditClipboardAccess.Create(F);
    E.Parent := F;
    E.Text := 'Test';
    E.SelectAll;
    E.SimulateKeyDownShift(VK_X, [ssCtrl]);
    AssertEquals('Ctrl+X copies to clipboard', 'Test', E.ClipText);
    AssertEquals('Ctrl+X: text removed', '', E.Text);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestCtrlVPastes;
var
  F: TCustomForm;
  E: TTyEditClipboardAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditClipboardAccess.Create(F);
    E.Parent := F;
    E.Text := 'Bye';
    E.CaretPos := 0;
    E.ClipText := 'Hi ';
    E.SimulateKeyDownShift(VK_V, [ssCtrl]);
    AssertEquals('Ctrl+V pastes at caret', 'Hi Bye', E.Text);
    AssertEquals('Ctrl+V advances caret', 3, E.CaretPos);
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TEditTest);
end.
