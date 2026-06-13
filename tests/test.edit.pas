unit test.edit;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Forms, Controls, Graphics, LCLType, LCLIntf,
  LazUTF8,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.Edit;
type
  TTyEditAccess = class(TTyEdit)
  public
    procedure RenderTo(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
    procedure SimulateKeyDown(Key: Word);
    procedure SimulateKeyDownShift(Key: Word; Shift: TShiftState);
    procedure SimulateKeyDownShiftRef(var Key: Word; Shift: TShiftState);
    procedure SimulateMouseDown(X, Y: Integer; Shift: TShiftState = []);
    procedure SimulateMouseMove(X, Y: Integer; Shift: TShiftState = []);
    procedure SimulateMouseUp(X, Y: Integer);
    // EDIT.4: expose CaretPixelX for headless caret-rendering tests
    function CaretPixelX(APPI: Integer): Integer;
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
    // EDIT.4: caret + selection rendering
    procedure TestSelectionBandRendered;
    procedure TestCaretFollowsPosition;
    // EDIT.5: fix 1 — measure/draw font-size agreement
    procedure TestMeasureDrawFontSizeAgreement;
    // EDIT.6: fix 2 — width cache perf
    procedure TestWidthCachePerf;
    // EDIT.7: fix 4 — paste empty/CRLF-only
    procedure TestPasteEmptyClipboardNoOp;
    procedure TestPasteCRLFOnlyDeletesSelection;
    // EDIT.8: fix 5 — modifier+arrow falls through
    procedure TestCtrlLeftDoesNotMove;
    // EDIT.9: fuzz invariants
    procedure TestFuzzInvariants;
    // EDIT.10: hit-test round-trip
    procedure TestHitTestRoundTrip;
    // EDIT.11: horizontal scroll
    procedure TestEndScrollsCaretIntoView;
    procedure TestHomeResetsScroll;
    procedure TestClickMapsUnderScroll;
    procedure TestScrollClampsOnShrink;
    procedure TestRenderedTextShiftsWithScroll;
    // EDIT.12: fix — scrolled text must not bleed past right padding/border
    procedure TestScrolledTextDoesNotBleedPastRightPadding;
    // EDIT.13: fix — caret aligns with drawn text end (measure uses painter BGRA engine)
    procedure TestCaretAlignsWithDrawnTextEnd;
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

procedure TTyEditAccess.SimulateKeyDownShiftRef(var Key: Word; Shift: TShiftState);
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

function TTyEditAccess.CaretPixelX(APPI: Integer): Integer;
begin
  Result := CaretPixelXAt(CaretPos, APPI);
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

// ---- EDIT.4: caret + selection rendering tests ----

procedure TEditTest.TestSelectionBandRendered;
{ Stylesheet: TyEdit { background: #FFFFFF; color: #000000; padding: 4px; }
               TyEdit:focus { border-color: #0000FF; }
  Text 'aaaa', SelectAll. Render into white-initialized bitmap.
  The 35%-alpha blue band over white gives B≈255, R≈165 → blue > red.
  At vertical centre, scan x range in the text area; assert at least one
  pixel has blue > red (the band was drawn).
  Control: render WITHOUT selection → no blue-dominant pixel. }
var
  Ctl: TTyStyleController;
  E: TTyEditAccess;
  Form: TForm;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  Px: TBGRAPixel;
  X, MidY: Integer;
  FoundBlue: Boolean;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyEdit { background: #FFFFFF; color: #000000; padding: 4px; }' +
      ' TyEdit:focus { border-color: #0000FF; }');
    E := TTyEditAccess.Create(Form);
    E.Parent := Form;
    E.Controller := Ctl;
    E.Text := 'aaaa';
    E.SelectAll;  // has selection

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(200, 28);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 200, 28);
    E.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 28), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      MidY := 14;
      FoundBlue := False;
      for X := 5 to 195 do
      begin
        Px := Reread.GetPixel(X, MidY);
        if Px.blue > Px.red then
        begin
          FoundBlue := True;
          Break;
        end;
      end;
      AssertTrue('Selection band: at least one blue-dominant pixel found', FoundBlue);

      // Control: render without selection → no blue-dominant pixel
      Bmp.Canvas.Brush.Color := clWhite;
      Bmp.Canvas.FillRect(0, 0, 200, 28);
      E.ClearSelection;
      E.RenderTo(Bmp.Canvas, Rect(0, 0, 200, 28), 96);
    finally
      Reread.Free;
    end;
    Reread := TBGRABitmap.Create(Bmp);
    try
      FoundBlue := False;
      for X := 5 to 195 do
      begin
        Px := Reread.GetPixel(X, MidY);
        if Px.blue > Px.red then
        begin
          FoundBlue := True;
          Break;
        end;
      end;
      AssertFalse('No selection: no blue-dominant pixel found', FoundBlue);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

procedure TEditTest.TestCaretFollowsPosition;
{ CaretPixelX should grow strictly as CaretPos advances 0→4 for wide text 'WWWW'. }
var
  F: TCustomForm;
  E: TTyEditAccess;
  Prev, Curr: Integer;
  I: Integer;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    E.Text := 'WWWW';
    Prev := -1;
    for I := 0 to 4 do
    begin
      E.CaretPos := I;
      Curr := E.CaretPixelX(96);
      AssertTrue('CaretPixelX grows at pos ' + IntToStr(I), Curr > Prev);
      Prev := Curr;
    end;
  finally
    F.Free;
  end;
end;

// ---- EDIT.5: Fix 1 — measure/draw font-size agreement ----

procedure TEditTest.TestMeasureDrawFontSizeAgreement;
// Stylesheet WITHOUT font-size: exercises the EffectiveFontSize fallback.
// Text 'WWWWWWWW'. Render to bitmap, pixel-scan rightmost non-white column.
// Assert |rightEdge - CaretPixelXAt(8,96)| <= 6 (measure agrees with draw).
// Also test WITH explicit font-size for regression.
var
  Ctl: TTyStyleController;
  E: TTyEditAccess;
  Form: TForm;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  X, Y, RightEdge, MeasuredX: Integer;
  Padding: Integer;
begin
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    // Test A: stylesheet without font-size (exercises the fallback path)
    Ctl.LoadThemeCss('TyEdit { background: #FFFFFF; color: #000000; padding: 4px; }');
    E := TTyEditAccess.Create(Form);
    E.Parent := Form;
    E.Controller := Ctl;
    E.Text := 'WWWWWWWW';
    E.ClearSelection;

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(300, 28);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 300, 28);
    E.RenderTo(Bmp.Canvas, Rect(0, 0, 300, 28), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      Padding := 4;  // px at 96ppi, matches padding:4px
      RightEdge := -1;
      for X := 299 downto 0 do
      begin
        for Y := 0 to 27 do
          if Reread.GetPixel(X, Y).red < 200 then
          begin
            RightEdge := X;
            Break;
          end;
        if RightEdge >= 0 then Break;
      end;
      MeasuredX := E.CaretPixelXAt(8, 96);
      // The right edge of drawn text should be very close to the measured caret position
      if RightEdge >= Padding then
        AssertTrue(
          'Without font-size: |rightEdge - measured| <= 6 (got rightEdge=' +
          IntToStr(RightEdge) + ' measured=' + IntToStr(MeasuredX) + ')',
          Abs(RightEdge - MeasuredX) <= 6
        );
    finally
      Reread.Free;
    end;
    E.Free;

    // Test B: stylesheet WITH explicit font-size (regression)
    Ctl.LoadThemeCss('TyEdit { background: #FFFFFF; color: #000000; padding: 4px; font-size: 12px; }');
    E := TTyEditAccess.Create(Form);
    E.Parent := Form;
    E.Controller := Ctl;
    E.Text := 'WWWWWWWW';
    E.ClearSelection;

    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 300, 28);
    E.RenderTo(Bmp.Canvas, Rect(0, 0, 300, 28), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      RightEdge := -1;
      for X := 299 downto 0 do
      begin
        for Y := 0 to 27 do
          if Reread.GetPixel(X, Y).red < 200 then
          begin
            RightEdge := X;
            Break;
          end;
        if RightEdge >= 0 then Break;
      end;
      MeasuredX := E.CaretPixelXAt(8, 96);
      if RightEdge >= Padding then
        AssertTrue(
          'With font-size: |rightEdge - measured| <= 6 (got rightEdge=' +
          IntToStr(RightEdge) + ' measured=' + IntToStr(MeasuredX) + ')',
          Abs(RightEdge - MeasuredX) <= 6
        );
    finally
      Reread.Free;
    end;
    E.Free;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

// ---- EDIT.6: Fix 2 — width cache perf ----

procedure TEditTest.TestWidthCachePerf;
{ Build a 300-codepoint text, call CaretPixelXAt 200 times, assert < 500ms. }
var
  F: TCustomForm;
  E: TTyEditAccess;
  s: string;
  i: Integer;
  T0: QWord;
  Elapsed: QWord;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    s := '';
    for i := 1 to 300 do
      s := s + 'W';
    E.Text := s;

    T0 := GetTickCount64;
    for i := 1 to 200 do
      E.CaretPixelXAt(150, 96);
    Elapsed := GetTickCount64 - T0;

    AssertTrue(
      '200x CaretPixelXAt on 300-cp text should be < 500ms (got ' +
      IntToStr(Elapsed) + 'ms)',
      Elapsed < 500
    );
  finally
    F.Free;
  end;
end;

// ---- EDIT.7: Fix 4 — paste empty/CRLF-only ----

procedure TEditTest.TestPasteEmptyClipboardNoOp;
{ Clipboard '' → true no-op: text unchanged, caret unchanged }
var
  F: TCustomForm;
  E: TTyEditClipboardAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditClipboardAccess.Create(F);
    E.Parent := F;
    E.Text := 'ab';
    E.CaretPos := 1;
    E.ClipText := '';
    E.PasteFromClipboard;
    AssertEquals('Empty clipboard: text unchanged', 'ab', E.Text);
    AssertEquals('Empty clipboard: caret unchanged', 1, E.CaretPos);
  finally
    F.Free;
  end;
end;

procedure TEditTest.TestPasteCRLFOnlyDeletesSelection;
{ Clipboard '#13#10' with active selection → selection deleted, text without it }
var
  F: TCustomForm;
  E: TTyEditClipboardAccess;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditClipboardAccess.Create(F);
    E.Parent := F;
    E.Text := 'abcd';
    // Select 'bc' (indices 1..3)
    E.CaretPos := 1;
    E.SimulateKeyDownShift(VK_RIGHT, [ssShift]);
    E.SimulateKeyDownShift(VK_RIGHT, [ssShift]);
    AssertEquals('Pre: SelLength=2', 2, E.SelLength);
    E.ClipText := #13#10;
    E.PasteFromClipboard;
    // Selection deleted, nothing inserted → 'ad'
    AssertEquals('CRLF paste deletes selection', 'ad', E.Text);
    AssertEquals('CRLF paste: SelLength=0', 0, E.SelLength);
  finally
    F.Free;
  end;
end;

// ---- EDIT.8: Fix 5 — modifier+arrow falls through ----

procedure TEditTest.TestCtrlLeftDoesNotMove;
{ v1.8: Ctrl+VK_LEFT is now word-wise (Win/Linux convention; macOS uses
  Option=ssAlt). On 'abc' caret 2 -> jumps to word start 0 and consumes Key.
  (Method name kept for history; behavior intentionally updated in v1.8.) }
var
  F: TCustomForm;
  E: TTyEditAccess;
  Key: Word;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    E.Text := 'abc';
    E.CaretPos := 2;
    Key := VK_LEFT;
    E.SimulateKeyDownShiftRef(Key, [ssCtrl]);
    AssertEquals('Ctrl+Left: word-wise to start', 0, E.CaretPos);
    AssertTrue('Ctrl+Left: Key consumed (0)', Key = 0);
  finally
    F.Free;
  end;
end;

// ---- EDIT.9: fuzz invariants ----

procedure TEditTest.TestFuzzInvariants;
const
  EMOJI_STR = #$F0#$9F#$98#$80;
var
  F: TCustomForm;
  E: TTyEditClipboardAccess;
  i, opn, L: Integer;
  Keys: array[0..3] of Word;
  InsChars: array[0..3] of string;
  KW: Word;
  OldSeed: LongInt;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditClipboardAccess.Create(F);
    E.Parent := F;

    Keys[0] := VK_LEFT;
    Keys[1] := VK_RIGHT;
    Keys[2] := VK_HOME;
    Keys[3] := VK_END;
    InsChars[0] := 'a';
    InsChars[1] := '你';
    InsChars[2] := EMOJI_STR;
    InsChars[3] := 'W';

    OldSeed := RandSeed;
    RandSeed := 42;
    E.Text := '';

    for i := 1 to 300 do
    begin
      opn := Random(10);
      case opn of
        0: E.InjectKey(InsChars[Random(4)]);
        1: E.InjectBackspace;
        2: E.InjectDelete;
        3: begin KW := Keys[Random(4)]; E.SimulateKeyDownShift(KW, []); end;
        4: begin KW := Keys[Random(4)]; E.SimulateKeyDownShift(KW, [ssShift]); end;
        5: E.SelectAll;
        6: E.CaretPos := Random(10) - 2;
        7: begin
             E.ClipText := InsChars[Random(4)] + #13#10 + 'q';
             E.SimulateKeyDownShift(VK_V, [ssCtrl]);
           end;
        8: E.SimulateKeyDownShift(VK_X, [ssCtrl]);
        9: if Random(4) = 0 then E.Text := 'a你' + EMOJI_STR;
      end;

      L := UTF8Length(E.Text);
      AssertTrue('fuzz #' + IntToStr(i) + ': SelStart >= 0', E.SelStart >= 0);
      AssertTrue('fuzz #' + IntToStr(i) + ': SelStart + SelLength <= Len',
        E.SelStart + E.SelLength <= L);
      AssertTrue('fuzz #' + IntToStr(i) + ': CaretPos in [0,Len]',
        (E.CaretPos >= 0) and (E.CaretPos <= L));

      // Keep text bounded to avoid runaway growth
      if L > 60 then E.Text := '';
    end;

    RandSeed := OldSeed;
  finally
    F.Free;
  end;
end;

// ---- EDIT.10: hit-test round-trip ----

procedure TEditTest.TestHitTestRoundTrip;
// For 'iW你il', for each boundary b in 0..5,
// CaretIndexAtX(CaretPixelXAt(b, PPI)) = b, using the same PPI both ways.
var
  F: TCustomForm;
  E: TTyEditAccess;
  b, PPI, XPx, idx: Integer;
begin
  F := TCustomForm.CreateNew(nil);
  try
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    E.Text := 'iW你il';
    // Use the same PPI that CaretIndexAtX uses internally (Font.PixelsPerInch)
    PPI := E.Font.PixelsPerInch;
    for b := 0 to 5 do
    begin
      XPx := E.CaretPixelXAt(b, PPI);
      idx := E.CaretIndexAtX(XPx);
      AssertEquals('HitTest round-trip boundary ' + IntToStr(b), b, idx);
    end;
  finally
    F.Free;
  end;
end;

// ---- EDIT.11: horizontal scroll tests ----

procedure TEditTest.TestEndScrollsCaretIntoView;
{ Narrow edit (width 80, padding 4px), long text (40 × 'W').
  VK_END → ScrollX > 0 AND the effective caret pixel (CaretPixelXAt - ScrollX)
  is within the visible window [0, 80]. }
var
  F: TCustomForm;
  E: TTyEditAccess;
  Ctl: TTyStyleController;
  PPI, EffCaretX, Len: Integer;
begin
  F := TCustomForm.CreateNew(nil);
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss('TyEdit { background: #FFFFFF; color: #000000; padding: 4px; }');
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    E.Controller := Ctl;
    // Narrow control so text overflows
    E.SetBounds(0, 0, 80, 24);
    // Long text
    E.Text := StringOfChar('W', 40);
    E.CaretPos := 0;  // start at beginning, scroll=0

    // Press END
    E.SimulateKeyDown(VK_END);

    Len := UTF8Length(E.Text);
    AssertEquals('VK_END moves caret to end', Len, E.CaretPos);
    AssertTrue('ScrollX > 0 after END on long text', E.ScrollX > 0);

    // Effective caret pixel: CaretPixelXAt(len, ppi) - ScrollX
    PPI := E.Font.PixelsPerInch;
    EffCaretX := E.CaretPixelXAt(Len, PPI) - E.ScrollX;
    AssertTrue(
      'Effective caret x >= 0 (got ' + IntToStr(EffCaretX) + ')',
      EffCaretX >= 0
    );
    AssertTrue(
      'Effective caret x <= 80 (got ' + IntToStr(EffCaretX) + ')',
      EffCaretX <= 80
    );
  finally
    F.Free;
    Ctl.Free;
  end;
end;

procedure TEditTest.TestHomeResetsScroll;
{ After scrolling to end via VK_END, VK_HOME must set ScrollX = 0. }
var
  F: TCustomForm;
  E: TTyEditAccess;
  Ctl: TTyStyleController;
begin
  F := TCustomForm.CreateNew(nil);
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss('TyEdit { background: #FFFFFF; color: #000000; padding: 4px; }');
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    E.Controller := Ctl;
    E.SetBounds(0, 0, 80, 24);
    E.Text := StringOfChar('W', 40);
    E.CaretPos := 0;

    E.SimulateKeyDown(VK_END);
    AssertTrue('Pre: ScrollX > 0 after END', E.ScrollX > 0);

    E.SimulateKeyDown(VK_HOME);
    AssertEquals('ScrollX = 0 after VK_HOME', 0, E.ScrollX);
    AssertEquals('CaretPos = 0 after VK_HOME', 0, E.CaretPos);
  finally
    F.Free;
    Ctl.Free;
  end;
end;

procedure TEditTest.TestClickMapsUnderScroll;
{ Scroll to end, then verify CaretIndexAtX round-trips correctly for a
  boundary near the caret (last char boundary): the click position accounts
  for the scroll offset. }
var
  F: TCustomForm;
  E: TTyEditAccess;
  Ctl: TTyStyleController;
  PPI, Len, ClickX, HitIdx: Integer;
begin
  F := TCustomForm.CreateNew(nil);
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss('TyEdit { background: #FFFFFF; color: #000000; padding: 4px; }');
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    E.Controller := Ctl;
    E.SetBounds(0, 0, 80, 24);
    E.Text := StringOfChar('W', 40);
    E.CaretPos := 0;

    // Scroll to end
    E.SimulateKeyDown(VK_END);
    Len := UTF8Length(E.Text);
    AssertTrue('Pre: ScrollX > 0', E.ScrollX > 0);

    // The click position for boundary Len in control coords:
    // CaretPixelXAt(Len, PPI) is the absolute pixel position;
    // in control coords (accounting for scroll) it is: CaretPixelXAt(Len) - ScrollX
    PPI := E.Font.PixelsPerInch;
    ClickX := E.CaretPixelXAt(Len, PPI) - E.ScrollX;

    // CaretIndexAtX should resolve that click back to boundary Len
    HitIdx := E.CaretIndexAtX(ClickX);
    AssertEquals(
      'CaretIndexAtX round-trips at scrolled end (boundary ' + IntToStr(Len) + ')',
      Len, HitIdx
    );

    // Also verify boundary Len-1 (one char back)
    ClickX := E.CaretPixelXAt(Len - 1, PPI) - E.ScrollX;
    HitIdx := E.CaretIndexAtX(ClickX);
    AssertEquals(
      'CaretIndexAtX round-trips at scrolled boundary ' + IntToStr(Len - 1),
      Len - 1, HitIdx
    );
  finally
    F.Free;
    Ctl.Free;
  end;
end;

procedure TEditTest.TestScrollClampsOnShrink;
{ Scroll to end with long text, then SetText to a short string.
  ScrollX must be clamped to new MaxScroll (likely 0 for short text). }
var
  F: TCustomForm;
  E: TTyEditAccess;
  Ctl: TTyStyleController;
  PPI, NewTextWidth, ViewWidth: Integer;
  S: string;
begin
  F := TCustomForm.CreateNew(nil);
  Ctl := TTyStyleController.Create(nil);
  try
    Ctl.LoadThemeCss('TyEdit { background: #FFFFFF; color: #000000; padding: 4px; }');
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    E.Controller := Ctl;
    E.SetBounds(0, 0, 80, 24);
    E.Text := StringOfChar('W', 40);
    E.CaretPos := 0;

    // Scroll to end
    E.SimulateKeyDown(VK_END);
    AssertTrue('Pre: ScrollX > 0', E.ScrollX > 0);

    // Replace with short text
    E.Text := 'Hi';
    PPI := E.Font.PixelsPerInch;
    // For 'Hi' (width << 80), MaxScroll should be 0, so ScrollX clamped to 0
    NewTextWidth := E.CaretPixelXAt(2, PPI) - E.CaretPixelXAt(0, PPI);
    ViewWidth := 80 - 4 - 4;  // width - leftPad - rightPad
    if NewTextWidth <= ViewWidth then
      AssertEquals('ScrollX clamped to 0 after shrinking text', 0, E.ScrollX)
    else
      AssertTrue('ScrollX <= new MaxScroll', E.ScrollX <= (NewTextWidth - ViewWidth));
  finally
    F.Free;
    Ctl.Free;
  end;
end;

procedure TEditTest.TestRenderedTextShiftsWithScroll;
{ Narrow edit (80px), long text (40×'W'), white background, black text.
  Render at HOME (scroll=0) and after END (scrolled).
  The two bitmaps must differ in the content area (scroll shifted content).
  Also verify effective caret is within visible range after END. }
var
  F: TCustomForm;
  E: TTyEditAccess;
  Ctl: TTyStyleController;
  Bmp1, Bmp2: TBitmap;
  BgraHome, BgraEnd: TBGRABitmap;
  X, Y: Integer;
  Differ: Boolean;
  PPI, EffCaret: Integer;
begin
  F := TCustomForm.CreateNew(nil);
  Ctl := TTyStyleController.Create(nil);
  Bmp1 := TBitmap.Create;
  Bmp2 := TBitmap.Create;
  try
    Ctl.LoadThemeCss('TyEdit { background: #FFFFFF; color: #000000; padding: 4px; }');
    E := TTyEditAccess.Create(F);
    E.Parent := F;
    E.Controller := Ctl;
    E.SetBounds(0, 0, 80, 24);
    E.Text := StringOfChar('W', 40);
    E.CaretPos := 0;
    AssertEquals('Pre: ScrollX = 0 at HOME', 0, E.ScrollX);

    // Render at HOME
    Bmp1.PixelFormat := pf32bit;
    Bmp1.SetSize(80, 24);
    Bmp1.Canvas.Brush.Color := clWhite;
    Bmp1.Canvas.FillRect(0, 0, 80, 24);
    E.RenderTo(Bmp1.Canvas, Rect(0, 0, 80, 24), 96);

    // Scroll to END
    E.SimulateKeyDown(VK_END);
    AssertTrue('ScrollX > 0 after END', E.ScrollX > 0);

    // Render at END (scrolled)
    Bmp2.PixelFormat := pf32bit;
    Bmp2.SetSize(80, 24);
    Bmp2.Canvas.Brush.Color := clWhite;
    Bmp2.Canvas.FillRect(0, 0, 80, 24);
    E.RenderTo(Bmp2.Canvas, Rect(0, 0, 80, 24), 96);

    BgraHome := TBGRABitmap.Create(Bmp1);
    BgraEnd  := TBGRABitmap.Create(Bmp2);
    try
      // Compare content area (skip padding columns)
      Differ := False;
      for X := 4 to 75 do
        for Y := 4 to 19 do
          if BgraHome.GetPixel(X, Y).red <> BgraEnd.GetPixel(X, Y).red then
          begin
            Differ := True;
            Break;
          end;
      AssertTrue('Scrolled render differs from HOME render', Differ);
    finally
      BgraHome.Free;
      BgraEnd.Free;
    end;

    // Effective caret pixel visible in [0, 80] after END
    PPI := E.Font.PixelsPerInch;
    EffCaret := E.CaretPixelXAt(E.CaretPos, PPI) - E.ScrollX;
    AssertTrue('Effective caret >= 0 in scrolled state', EffCaret >= 0);
    AssertTrue('Effective caret <= 80 in scrolled state', EffCaret <= 80);
  finally
    Bmp1.Free;
    Bmp2.Free;
    F.Free;
    Ctl.Free;
  end;
end;

// ---- EDIT.12: regression — scrolled text must not bleed past right padding/border ----

procedure TEditTest.TestScrolledTextDoesNotBleedPastRightPadding;
{ Setup: narrow edit (width=120), padding=4px, border-width=2px via stylesheet,
  white text on black background, long text, then VK_END to scroll.
  Render to a black bitmap. The right-padding strip x in [ContentRight..Width-1]
  (i.e., pixels right of the content area) must contain no white glyph pixels.
  ContentRight = Width - padding(4) - borderWidth(2) = 120 - 4 - 2 = 114.
  Pre-fix the DrawText rect Right was far past ContentRect.Right so glyphs bled
  into the padding/border strip; post-fix they are clamped. }
var
  Ctl: TTyStyleController;
  E: TTyEditAccess;
  Form: TForm;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  X, Y: Integer;
  StrayCount: Integer;
  Px: TBGRAPixel;
  W, ContentRight: Integer;
begin
  W := 120;
  Ctl := TTyStyleController.Create(nil);
  Form := TForm.CreateNew(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss(
      'TyEdit { background: #000000; color: #FFFFFF; padding: 4px; border-width: 2px; border-color: #333333; }');
    E := TTyEditAccess.Create(Form);
    E.Parent := Form;
    E.Controller := Ctl;
    E.Font.PixelsPerInch := 96;
    E.SetBounds(0, 0, W, 24);
    // Long text to force horizontal scroll
    E.Text := StringOfChar('W', 40);
    E.CaretPos := 0;
    // Scroll to the end so FScrollX > 0
    E.SimulateKeyDown(VK_END);
    AssertTrue('Pre: ScrollX > 0 after VK_END', E.ScrollX > 0);

    // Render onto a black bitmap
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(W, 24);
    Bmp.Canvas.Brush.Color := clBlack;
    Bmp.Canvas.FillRect(0, 0, W, 24);
    E.RenderTo(Bmp.Canvas, Rect(0, 0, W, 24), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // ContentRight = Width - right-padding(4) - border-width(2)
      ContentRight := W - 4 - 2;
      StrayCount := 0;
      for X := ContentRight to W - 1 do
        for Y := 0 to 23 do
        begin
          Px := Reread.GetPixel(X, Y);
          // A white glyph pixel has all channels >= 200
          if (Px.red >= 200) and (Px.green >= 200) and (Px.blue >= 200) then
            Inc(StrayCount);
        end;
      AssertEquals(
        'No white glyph pixels should exist in the right padding/border strip ' +
        '(x in [' + IntToStr(ContentRight) + '..' + IntToStr(W - 1) + '])',
        0, StrayCount);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Form.Free;
    Ctl.Free;
  end;
end;

// ---- EDIT.13: caret aligns with drawn text end ----

procedure TEditTest.TestCaretAlignsWithDrawnTextEnd;
{ The caret-x for the end boundary must sit within a few px of the actual
  right edge of the drawn text. Measurement (LCL TBitmap) used to disagree
  with the painter's BGRA engine, so the caret drifted right of the ink and
  the gap grew with text length. With a longish string that fits (no scroll)
  the rightmost ink column should match CaretPixelXAt(end). }
var
  Ctl: TTyStyleController;
  E: TTyEditAccess;
  Bmp: TBitmap;
  Reread: TBGRABitmap;
  caretX, rightmostInk, x, y, Len: Integer;
  foundInk: Boolean;
begin
  Ctl := TTyStyleController.Create(nil);
  Bmp := TBitmap.Create;
  try
    Ctl.LoadThemeCss('TyEdit { background:#FFFFFF; color:#000000; padding:4px; font-size:12px; }');
    E := TTyEditAccess.Create(nil);
    E.Controller := Ctl;
    E.Font.PixelsPerInch := 96;
    // Wide control so a long string fits without horizontal scroll; the longer
    // the string the more the (per-glyph) measure/draw mismatch accumulates,
    // pushing the end-caret well past the ink under the old measurement.
    E.SetBounds(0, 0, 1200, 28);
    E.Text := 'abcdefghijklmnopqrstuvwxyz0123456789' +
              'abcdefghijklmnopqrstuvwxyz0123456789' +
              'abcdefghijklmnopqrstuvwxyz0123456789';
    Len := UTF8Length(E.Text);
    E.CaretPos := Len;  // caret at end
    // Guard: this text must fit at width 1200 (no horizontal scroll)
    AssertEquals('text fits, no horizontal scroll', 0, E.ScrollX);

    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(1200, 28);
    Bmp.Canvas.Brush.Color := clWhite;
    Bmp.Canvas.FillRect(0, 0, 1200, 28);
    E.RenderTo(Bmp.Canvas, Rect(0, 0, 1200, 28), 96);

    Reread := TBGRABitmap.Create(Bmp);
    try
      // rightmost column containing dark (text) ink
      rightmostInk := -1;
      for x := 1199 downto 0 do
      begin
        foundInk := False;
        for y := 4 to 23 do
          if Reread.GetPixel(x, y).red < 128 then begin foundInk := True; Break; end;
        if foundInk then begin rightmostInk := x; Break; end;
      end;
      caretX := E.CaretPixelXAt(Len, 96);  // end-caret x
      // caret must sit within a few px of the last drawn glyph's right edge
      AssertTrue(Format('caret(%d) near rightmost ink(%d)', [caretX, rightmostInk]),
        Abs(caretX - rightmostInk) <= 6);
    finally
      Reread.Free;
    end;
  finally
    Bmp.Free;
    Ctl.Free;
    E.Free;
  end;
end;

initialization
  RegisterTest(TEditTest);
end.
