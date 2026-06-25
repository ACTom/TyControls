unit test.memo.undo;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, LCLType,
  LazUTF8,
  tyControls.Memo;
type
  // Access subclass: in-memory clipboard + exposes undo/redo internals, a KeyDown
  // probe, a forced-focus toggle and an OnChange counter for headless testing.
  TTyMemoUndoAccess = class(TTyMemo)
  private
    FClipText: string;
    FChangeCount: Integer;
    procedure HandleChange(Sender: TObject);
  protected
    function ReadClipboardText: string; override;
    procedure WriteClipboardText(const S: string); override;
  public
    constructor Create(AOwner: TComponent); override;
    function CaptureStateEx: string;
    procedure RestoreStateEx(const S: string);
    procedure ProbeKeyDown(Key: Word; Shift: TShiftState);
    procedure ProbeSetForceFocused(AValue: Boolean);
    // SetCaret collapses the selection, so callers set the caret first then the
    // anchor to establish a non-empty selection.
    procedure SetCaretEx(ALine, ACol: Integer);
    procedure SetSelAnchorEx(ALine, ACol: Integer);
    property ClipText: string read FClipText write FClipText;
    property ChangeCount: Integer read FChangeCount;
  end;

  TTyMemoUndoTest = class(TTestCase)
  published
    procedure TestTypeUndoRestoresPrevious;
    procedure TestUndoRedoRoundTrip;
    procedure TestEnterSplitThenUndoMergesLines;
    procedure TestTypingRunCoalescesSingleUndo;
    procedure TestBackspaceMergeThenUndoRestoresTwoLines;
    procedure TestDeleteSelectionMultiLineThenUndoRestores;
    procedure TestUndoRestoresSelection;
    procedure TestPasteCollapsesSelection;
    procedure TestEnterCollapsesSelection;
    procedure TestPasteMultiLineThenUndoIsOneStep;
    procedure TestCutMultiLineThenUndoIsOneStep;
    procedure TestTrailingEmptyLineRoundTrips;
    procedure TestUndoFiresOnChangeOnce;
    procedure TestDisabledIgnoresUndoKeys;
    procedure TestNewEditClearsRedo;
  end;

implementation

// ---- TTyMemoUndoAccess ----

constructor TTyMemoUndoAccess.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FClipText := '';
  FChangeCount := 0;
  OnChange := @HandleChange;
end;

procedure TTyMemoUndoAccess.HandleChange(Sender: TObject);
begin
  Inc(FChangeCount);
end;

function TTyMemoUndoAccess.ReadClipboardText: string;
begin
  Result := FClipText;
end;

procedure TTyMemoUndoAccess.WriteClipboardText(const S: string);
begin
  FClipText := S;
end;

function TTyMemoUndoAccess.CaptureStateEx: string;
begin
  Result := CaptureState;
end;

procedure TTyMemoUndoAccess.RestoreStateEx(const S: string);
begin
  RestoreState(S);
end;

procedure TTyMemoUndoAccess.ProbeKeyDown(Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;

procedure TTyMemoUndoAccess.ProbeSetForceFocused(AValue: Boolean);
begin
  SetForceFocused(AValue);
end;

procedure TTyMemoUndoAccess.SetCaretEx(ALine, ACol: Integer);
begin
  SetCaret(ALine, ACol);
end;

procedure TTyMemoUndoAccess.SetSelAnchorEx(ALine, ACol: Integer);
begin
  SetSelAnchor(ALine, ACol);
end;

// ---- Tests ----

procedure TTyMemoUndoTest.TestTypeUndoRestoresPrevious;
var
  M: TTyMemoUndoAccess;
begin
  M := TTyMemoUndoAccess.Create(nil);
  try
    M.Font.PixelsPerInch := 96;
    M.InjectChar('a');
    AssertEquals('typed line count', 1, M.Lines.Count);
    AssertEquals('typed', 'a', M.Lines[0]);
    AssertTrue('CanUndo after typing', M.CanUndo);
    M.Undo;
    AssertEquals('undo back to empty', 0, M.Lines.Count);
  finally
    M.Free;
  end;
end;

procedure TTyMemoUndoTest.TestUndoRedoRoundTrip;
var
  M: TTyMemoUndoAccess;
begin
  M := TTyMemoUndoAccess.Create(nil);
  try
    M.Font.PixelsPerInch := 96;
    M.InjectChar('x');
    M.Undo;
    AssertEquals('after undo', 0, M.Lines.Count);
    AssertTrue('CanRedo after undo', M.CanRedo);
    M.Redo;
    AssertEquals('after redo line count', 1, M.Lines.Count);
    AssertEquals('after redo text', 'x', M.Lines[0]);
  finally
    M.Free;
  end;
end;

procedure TTyMemoUndoTest.TestEnterSplitThenUndoMergesLines;
var
  M: TTyMemoUndoAccess;
begin
  M := TTyMemoUndoAccess.Create(nil);
  try
    M.Font.PixelsPerInch := 96;
    M.Lines.Text := 'abcd';
    M.SetCaretEx(0, 2);          // caret between 'ab' and 'cd'
    M.ProbeKeyDown(VK_RETURN, []);
    AssertEquals('split into two lines', 2, M.Lines.Count);
    AssertEquals('first line head', 'ab', M.Lines[0]);
    AssertEquals('second line tail', 'cd', M.Lines[1]);
    M.Undo;
    AssertEquals('undo merges back to one line', 1, M.Lines.Count);
    AssertEquals('merged text', 'abcd', M.Lines[0]);
  finally
    M.Free;
  end;
end;

procedure TTyMemoUndoTest.TestTypingRunCoalescesSingleUndo;
var
  M: TTyMemoUndoAccess;
begin
  M := TTyMemoUndoAccess.Create(nil);
  try
    M.Font.PixelsPerInch := 96;
    M.InjectChar('a');
    M.InjectChar('b');
    M.InjectChar('c');
    AssertEquals('typed run', 'abc', M.Lines[0]);
    M.Undo;
    AssertEquals('single undo clears the whole run', 0, M.Lines.Count);
    AssertFalse('no more undo', M.CanUndo);
  finally
    M.Free;
  end;
end;

procedure TTyMemoUndoTest.TestBackspaceMergeThenUndoRestoresTwoLines;
var
  M: TTyMemoUndoAccess;
begin
  M := TTyMemoUndoAccess.Create(nil);
  try
    M.Font.PixelsPerInch := 96;
    M.Lines.Text := 'ab' + LineEnding + 'cd';
    AssertEquals('two lines initially', 2, M.Lines.Count);
    M.SetCaretEx(1, 0);          // start of second line
    M.ProbeKeyDown(VK_BACK, []); // merges line 1 onto line 0
    AssertEquals('merged into one line', 1, M.Lines.Count);
    AssertEquals('merged text', 'abcd', M.Lines[0]);
    M.Undo;
    AssertEquals('undo restores two lines', 2, M.Lines.Count);
    AssertEquals('line 0 restored', 'ab', M.Lines[0]);
    AssertEquals('line 1 restored', 'cd', M.Lines[1]);
  finally
    M.Free;
  end;
end;

procedure TTyMemoUndoTest.TestDeleteSelectionMultiLineThenUndoRestores;
var
  M: TTyMemoUndoAccess;
begin
  M := TTyMemoUndoAccess.Create(nil);
  try
    M.Font.PixelsPerInch := 96;
    M.Lines.Text := 'hello' + LineEnding + 'world' + LineEnding + 'foo';
    AssertEquals('three lines initially', 3, M.Lines.Count);
    // Select from (0,2) to (2,1): 'llo'\n'world'\n'f'
    M.SetCaretEx(0, 2);
    M.SetSelAnchorEx(2, 1);      // anchor differs from caret -> selection
    M.ProbeKeyDown(VK_DELETE, []);
    AssertEquals('collapsed to one line', 1, M.Lines.Count);
    AssertEquals('spliced text', 'heoo', M.Lines[0]);
    M.Undo;
    AssertEquals('undo restores three lines', 3, M.Lines.Count);
    AssertEquals('line 0', 'hello', M.Lines[0]);
    AssertEquals('line 1', 'world', M.Lines[1]);
    AssertEquals('line 2', 'foo', M.Lines[2]);
  finally
    M.Free;
  end;
end;

procedure TTyMemoUndoTest.TestUndoRestoresSelection;
// Undo must RE-SELECT what a delete removed. Regression guard: AfterEdit was briefly made to collapse
// the anchor unconditionally, which silently defeated RestoreState's selection restore (the existing
// delete-undo tests only check text, so nothing caught it).
var
  M: TTyMemoUndoAccess;
begin
  M := TTyMemoUndoAccess.Create(nil);
  try
    M.Font.PixelsPerInch := 96;
    M.Lines.Text := 'hello';
    M.SetCaretEx(0, 1);
    M.SetSelAnchorEx(0, 4);          // select cols 1..4 ('ell')
    AssertEquals('selection before delete', 3, M.SelLength);
    M.ProbeKeyDown(VK_DELETE, []);
    AssertEquals('no selection after delete', 0, M.SelLength);
    AssertEquals('text after delete', 'ho', M.Lines[0]);
    M.Undo;
    AssertEquals('undo restores text', 'hello', M.Lines[0]);
    AssertEquals('undo restores the selection', 3, M.SelLength);
  finally
    M.Free;
  end;
end;

procedure TTyMemoUndoTest.TestPasteCollapsesSelection;
// Paste leaves the caret AFTER the inserted text with NO selection (not the pasted text selected).
var
  M: TTyMemoUndoAccess;
begin
  M := TTyMemoUndoAccess.Create(nil);
  try
    M.Font.PixelsPerInch := 96;
    M.Lines.Text := 'hello';
    M.ClipText := 'XY';
    M.SetCaretEx(0, 5);              // caret at end of line
    M.PasteFromClipboard;
    AssertEquals('text after paste', 'helloXY', M.Lines[0]);
    AssertEquals('paste leaves no selection', 0, M.SelLength);
    AssertEquals('caret sits after the pasted text', 7, M.SelStart);
  finally
    M.Free;
  end;
end;

procedure TTyMemoUndoTest.TestEnterCollapsesSelection;
// Enter over a selection replaces it with a line break and leaves NO selection (not the new break
// selected). WantReturns defaults True.
var
  M: TTyMemoUndoAccess;
begin
  M := TTyMemoUndoAccess.Create(nil);
  try
    M.Font.PixelsPerInch := 96;
    M.Lines.Text := 'hello';
    M.SetCaretEx(0, 1);
    M.SetSelAnchorEx(0, 4);          // select 'ell'
    M.ProbeKeyDown(VK_RETURN, []);
    AssertEquals('enter leaves no selection', 0, M.SelLength);
    AssertEquals('split into two lines', 2, M.Lines.Count);
    AssertEquals('line 0', 'h', M.Lines[0]);
    AssertEquals('line 1', 'o', M.Lines[1]);
  finally
    M.Free;
  end;
end;

procedure TTyMemoUndoTest.TestPasteMultiLineThenUndoIsOneStep;
var
  M: TTyMemoUndoAccess;
begin
  M := TTyMemoUndoAccess.Create(nil);
  try
    M.Font.PixelsPerInch := 96;
    M.Lines.Text := 'start';
    M.SetCaretEx(0, 5);          // end of 'start'
    M.ClipText := 'X' + LineEnding + 'Y' + LineEnding + 'Z';
    M.PasteFromClipboard;
    AssertEquals('paste added lines', 3, M.Lines.Count);
    AssertEquals('first joined', 'startX', M.Lines[0]);
    AssertEquals('mid', 'Y', M.Lines[1]);
    AssertEquals('last', 'Z', M.Lines[2]);
    M.Undo;
    AssertEquals('single undo reverts whole paste (line count)', 1, M.Lines.Count);
    AssertEquals('single undo reverts whole paste (text)', 'start', M.Lines[0]);
  finally
    M.Free;
  end;
end;

procedure TTyMemoUndoTest.TestCutMultiLineThenUndoIsOneStep;
var
  M: TTyMemoUndoAccess;
begin
  M := TTyMemoUndoAccess.Create(nil);
  try
    M.Font.PixelsPerInch := 96;
    M.Lines.Text := 'aa' + LineEnding + 'bb' + LineEnding + 'cc';
    // Select whole document.
    M.SetCaretEx(0, 0);
    M.SetSelAnchorEx(2, 2);
    M.CutToClipboard;
    AssertEquals('clipboard has the cut text', 'aa' + LineEnding + 'bb' + LineEnding + 'cc', M.ClipText);
    AssertEquals('cut collapsed to one empty line', 1, M.Lines.Count);
    AssertEquals('remaining empty', '', M.Lines[0]);
    M.Undo;
    AssertEquals('single undo reverts whole cut', 3, M.Lines.Count);
    AssertEquals('line 0', 'aa', M.Lines[0]);
    AssertEquals('line 1', 'bb', M.Lines[1]);
    AssertEquals('line 2', 'cc', M.Lines[2]);
  finally
    M.Free;
  end;
end;

procedure TTyMemoUndoTest.TestTrailingEmptyLineRoundTrips;
var
  M: TTyMemoUndoAccess;
begin
  M := TTyMemoUndoAccess.Create(nil);
  try
    M.Font.PixelsPerInch := 96;
    M.InjectChar('a');
    M.ProbeKeyDown(VK_RETURN, []);  // 'a' then a trailing empty line
    AssertEquals('two logical lines', 2, M.Lines.Count);
    AssertEquals('line 0', 'a', M.Lines[0]);
    AssertEquals('line 1 empty', '', M.Lines[1]);
    M.Undo;                          // undo the Enter
    AssertEquals('undo back to one line', 1, M.Lines.Count);
    AssertEquals('line 0 after undo', 'a', M.Lines[0]);
    M.Redo;                          // redo restores the trailing empty line
    AssertEquals('redo restores two lines (Count, not .Text)', 2, M.Lines.Count);
    AssertEquals('redo line 0', 'a', M.Lines[0]);
    AssertEquals('redo line 1 empty', '', M.Lines[1]);
  finally
    M.Free;
  end;
end;

procedure TTyMemoUndoTest.TestUndoFiresOnChangeOnce;
var
  M: TTyMemoUndoAccess;
  Before: Integer;
begin
  M := TTyMemoUndoAccess.Create(nil);
  try
    M.Font.PixelsPerInch := 96;
    M.InjectChar('a');
    Before := M.ChangeCount;
    M.Undo;
    AssertEquals('OnChange fires exactly once on undo', Before + 1, M.ChangeCount);
  finally
    M.Free;
  end;
end;

procedure TTyMemoUndoTest.TestDisabledIgnoresUndoKeys;
var
  M: TTyMemoUndoAccess;
begin
  M := TTyMemoUndoAccess.Create(nil);
  try
    M.Font.PixelsPerInch := 96;
    M.InjectChar('a');
    M.Enabled := False;
    M.ProbeKeyDown(VK_Z, [ssCtrl]);  // no-op while disabled
    AssertEquals('disabled Ctrl+Z is a no-op', 'a', M.Lines[0]);
  finally
    M.Free;
  end;
end;

procedure TTyMemoUndoTest.TestNewEditClearsRedo;
var
  M: TTyMemoUndoAccess;
begin
  M := TTyMemoUndoAccess.Create(nil);
  try
    M.Font.PixelsPerInch := 96;
    M.InjectChar('a');
    M.Undo;
    AssertTrue('CanRedo after undo', M.CanRedo);
    M.InjectChar('b');               // new edit clears redo
    AssertFalse('redo cleared by new edit', M.CanRedo);
  finally
    M.Free;
  end;
end;

initialization
  RegisterTest(TTyMemoUndoTest);
end.
