unit test.edit.undo;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, LCLType,
  LazUTF8,
  tyControls.Edit;
type
  // Access subclass: in-memory clipboard + exposes undo/redo internals and a
  // KeyDown probe and an OnChange counter for headless testing.
  TTyEditUndoAccess = class(TTyEdit)
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
    property ClipText: string read FClipText write FClipText;
    property ChangeCount: Integer read FChangeCount;
  end;

  TTyEditUndoTest = class(TTestCase)
  published
    procedure TestTypeUndoRestoresPrevious;
    procedure TestUndoThenRedoRestoresTyped;
    procedure TestMultiStepUndoBackToEmpty;
    procedure TestTypingRunIsOneUndoStep;
    procedure TestBackspaceBreaksCoalesce;
    procedure TestNavBreaksCoalesce;
    procedure TestPasteIsOneUndoStep;
    procedure TestCutIsOneUndoStep;
    procedure TestUndoFiresOnChangeOnce;
    procedure TestRedoFiresOnChangeOnce;
    procedure TestDisabledIgnoresUndoKeys;
    procedure TestNewEditClearsRedo;
  end;

implementation

// ---- TTyEditUndoAccess ----

constructor TTyEditUndoAccess.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FClipText := '';
  FChangeCount := 0;
  OnChange := @HandleChange;
end;

procedure TTyEditUndoAccess.HandleChange(Sender: TObject);
begin
  Inc(FChangeCount);
end;

function TTyEditUndoAccess.ReadClipboardText: string;
begin
  Result := FClipText;
end;

procedure TTyEditUndoAccess.WriteClipboardText(const S: string);
begin
  FClipText := S;
end;

function TTyEditUndoAccess.CaptureStateEx: string;
begin
  Result := CaptureState;
end;

procedure TTyEditUndoAccess.RestoreStateEx(const S: string);
begin
  RestoreState(S);
end;

procedure TTyEditUndoAccess.ProbeKeyDown(Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;

// ---- Tests ----

procedure TTyEditUndoTest.TestTypeUndoRestoresPrevious;
var
  E: TTyEditUndoAccess;
begin
  E := TTyEditUndoAccess.Create(nil);
  try
    E.InjectKey('a');
    AssertEquals('typed', 'a', E.Text);
    AssertTrue('CanUndo after typing', E.CanUndo);
    E.Undo;
    AssertEquals('undo back to empty', '', E.Text);
  finally
    E.Free;
  end;
end;

procedure TTyEditUndoTest.TestUndoThenRedoRestoresTyped;
var
  E: TTyEditUndoAccess;
begin
  E := TTyEditUndoAccess.Create(nil);
  try
    E.InjectKey('a');
    E.Undo;
    AssertEquals('after undo', '', E.Text);
    AssertTrue('CanRedo after undo', E.CanRedo);
    E.Redo;
    AssertEquals('after redo', 'a', E.Text);
  finally
    E.Free;
  end;
end;

procedure TTyEditUndoTest.TestMultiStepUndoBackToEmpty;
var
  E: TTyEditUndoAccess;
begin
  E := TTyEditUndoAccess.Create(nil);
  try
    // Three distinct non-coalescing steps separated by nav breaks.
    E.InjectKey('a');               // step 1: '' -> 'a'
    E.CaretPos := 0;                // nav break
    E.InjectKey('b');               // step 2: 'a' -> 'ba'
    E.CaretPos := 0;                // nav break
    E.InjectKey('c');               // step 3: 'ba' -> 'cba'
    AssertEquals('text', 'cba', E.Text);
    // Undo three times -> back to empty.
    E.Undo;
    AssertEquals('after 1 undo', 'ba', E.Text);
    E.Undo;
    AssertEquals('after 2 undo', 'a', E.Text);
    E.Undo;
    AssertEquals('back to empty', '', E.Text);
    AssertFalse('no more undo', E.CanUndo);
  finally
    E.Free;
  end;
end;

procedure TTyEditUndoTest.TestTypingRunIsOneUndoStep;
var
  E: TTyEditUndoAccess;
begin
  E := TTyEditUndoAccess.Create(nil);
  try
    E.InjectKey('a');
    E.InjectKey('b');
    E.InjectKey('c');
    AssertEquals('typed run', 'abc', E.Text);
    E.Undo;
    AssertEquals('single undo clears whole run', '', E.Text);
    AssertFalse('no more undo', E.CanUndo);
  finally
    E.Free;
  end;
end;

procedure TTyEditUndoTest.TestBackspaceBreaksCoalesce;
var
  E: TTyEditUndoAccess;
begin
  E := TTyEditUndoAccess.Create(nil);
  try
    E.InjectKey('a');
    E.InjectKey('b');       // 'ab'
    E.InjectBackspace;      // 'a'  (delete step)
    E.InjectKey('c');       // 'ac' (new typing run)
    AssertEquals('text', 'ac', E.Text);
    E.Undo;
    AssertEquals('undo removes only the c', 'a', E.Text);
  finally
    E.Free;
  end;
end;

procedure TTyEditUndoTest.TestNavBreaksCoalesce;
var
  E: TTyEditUndoAccess;
begin
  E := TTyEditUndoAccess.Create(nil);
  try
    E.InjectKey('a');       // 'a', caret at 1
    E.CaretPos := 0;        // nav: breaks coalescing
    E.InjectKey('b');       // 'ba', caret at 1
    AssertEquals('text', 'ba', E.Text);
    E.Undo;
    AssertEquals('undo removes only the b', 'a', E.Text);
  finally
    E.Free;
  end;
end;

procedure TTyEditUndoTest.TestPasteIsOneUndoStep;
var
  E: TTyEditUndoAccess;
begin
  E := TTyEditUndoAccess.Create(nil);
  try
    E.Text := 'hello';
    E.SelectAll;            // select all (breaks coalesce, no push)
    E.ClipText := 'XYZ';
    E.PasteFromClipboard;   // deletes selection + inserts -> ONE step
    AssertEquals('after paste', 'XYZ', E.Text);
    E.Undo;
    AssertEquals('single undo reverts whole paste', 'hello', E.Text);
  finally
    E.Free;
  end;
end;

procedure TTyEditUndoTest.TestCutIsOneUndoStep;
var
  E: TTyEditUndoAccess;
begin
  E := TTyEditUndoAccess.Create(nil);
  try
    E.Text := 'hello';
    E.SelectAll;
    E.CutToClipboard;       // copy + delete selection -> ONE step
    AssertEquals('after cut', '', E.Text);
    AssertEquals('clipboard has text', 'hello', E.ClipText);
    E.Undo;
    AssertEquals('single undo reverts whole cut', 'hello', E.Text);
  finally
    E.Free;
  end;
end;

procedure TTyEditUndoTest.TestUndoFiresOnChangeOnce;
var
  E: TTyEditUndoAccess;
  Before: Integer;
begin
  E := TTyEditUndoAccess.Create(nil);
  try
    E.InjectKey('a');
    Before := E.ChangeCount;
    E.Undo;
    AssertEquals('OnChange fires exactly once on undo', Before + 1, E.ChangeCount);
  finally
    E.Free;
  end;
end;

procedure TTyEditUndoTest.TestRedoFiresOnChangeOnce;
var
  E: TTyEditUndoAccess;
  Before: Integer;
begin
  E := TTyEditUndoAccess.Create(nil);
  try
    E.InjectKey('a');
    E.Undo;
    Before := E.ChangeCount;
    E.Redo;
    AssertEquals('OnChange fires exactly once on redo', Before + 1, E.ChangeCount);
  finally
    E.Free;
  end;
end;

procedure TTyEditUndoTest.TestDisabledIgnoresUndoKeys;
var
  E: TTyEditUndoAccess;
begin
  E := TTyEditUndoAccess.Create(nil);
  try
    E.InjectKey('a');
    E.Enabled := False;
    E.ProbeKeyDown(VK_Z, [ssCtrl]);  // should be a no-op while disabled
    AssertEquals('disabled Ctrl+Z is a no-op', 'a', E.Text);
  finally
    E.Free;
  end;
end;

procedure TTyEditUndoTest.TestNewEditClearsRedo;
var
  E: TTyEditUndoAccess;
begin
  E := TTyEditUndoAccess.Create(nil);
  try
    E.InjectKey('a');
    E.Undo;
    AssertTrue('CanRedo after undo', E.CanRedo);
    E.InjectKey('b');       // new edit clears redo
    AssertFalse('redo cleared by new edit', E.CanRedo);
  finally
    E.Free;
  end;
end;

initialization
  RegisterTest(TTyEditUndoTest);
end.
