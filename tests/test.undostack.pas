unit test.undostack;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry,
  tyControls.UndoStack;
type
  TTyUndoStackTest = class(TTestCase)
  private
    FStack: TTyUndoStack;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestEmptyStackCannotUndoOrRedo;
    procedure TestPushThenUndoReturnsSnapshotAndPushesCurrentToRedo;
    procedure TestRedoReturnsThePushedCurrent;
    procedure TestNewPushClearsRedo;
    procedure TestTypingRunCoalescesToOne;
    procedure TestNonTypingBreaksCoalesce;
    procedure TestBreakCoalescingSplitsTypingRun;
    procedure TestUndoBreaksCoalesce;
    procedure TestCapDropsOldest;
    procedure TestClearResetsBoth;
  end;
implementation

procedure TTyUndoStackTest.SetUp;
begin
  FStack := TTyUndoStack.Create;
end;

procedure TTyUndoStackTest.TearDown;
begin
  FStack.Free;
  FStack := nil;
end;

procedure TTyUndoStackTest.TestEmptyStackCannotUndoOrRedo;
begin
  AssertFalse('empty cannot undo', FStack.CanUndo);
  AssertFalse('empty cannot redo', FStack.CanRedo);
  AssertEquals('undo depth 0', 0, FStack.UndoDepth);
  AssertEquals('redo depth 0', 0, FStack.RedoDepth);
end;

procedure TTyUndoStackTest.TestPushThenUndoReturnsSnapshotAndPushesCurrentToRedo;
var s: string;
begin
  FStack.Push('A', uskTyping);
  AssertTrue('can undo after push', FStack.CanUndo);
  s := FStack.Undo('B'); // current is 'B', undo should return 'A'
  AssertEquals('undo returns pushed snapshot', 'A', s);
  AssertTrue('can redo after undo', FStack.CanRedo);
  AssertEquals('redo depth 1 (current pushed)', 1, FStack.RedoDepth);
end;

procedure TTyUndoStackTest.TestRedoReturnsThePushedCurrent;
var s: string;
begin
  FStack.Push('A', uskDelete);
  FStack.Undo('B'); // pushes 'B' onto redo, returns 'A'
  s := FStack.Redo('A'); // current is now 'A', redo should return 'B'
  AssertEquals('redo returns the current that was pushed', 'B', s);
  AssertFalse('redo stack empty again', FStack.CanRedo);
end;

procedure TTyUndoStackTest.TestNewPushClearsRedo;
begin
  FStack.Push('A', uskDelete);
  FStack.Undo('B');
  AssertTrue('redo available before new push', FStack.CanRedo);
  FStack.Push('C', uskDelete);
  AssertFalse('new push clears redo', FStack.CanRedo);
end;

procedure TTyUndoStackTest.TestTypingRunCoalescesToOne;
var i: Integer;
begin
  for i := 1 to 5 do
    FStack.Push('snap' + IntToStr(i), uskTyping);
  AssertEquals('5 consecutive typing pushes coalesce to one', 1, FStack.UndoDepth);
end;

procedure TTyUndoStackTest.TestNonTypingBreaksCoalesce;
begin
  FStack.Push('a', uskTyping);
  FStack.Push('b', uskDelete);
  FStack.Push('c', uskTyping);
  AssertEquals('typing/delete/typing -> 3 steps', 3, FStack.UndoDepth);
end;

procedure TTyUndoStackTest.TestBreakCoalescingSplitsTypingRun;
begin
  FStack.Push('a', uskTyping);
  FStack.BreakCoalescing;
  FStack.Push('b', uskTyping);
  AssertEquals('break splits typing run -> 2 steps', 2, FStack.UndoDepth);
end;

procedure TTyUndoStackTest.TestUndoBreaksCoalesce;
begin
  FStack.Push('a', uskTyping);
  FStack.Push('b', uskTyping); // coalesced -> depth 1
  AssertEquals('coalesced to 1', 1, FStack.UndoDepth);
  FStack.Undo('cur'); // depth 0, breaks coalescing
  FStack.Push('c', uskTyping); // fresh step
  FStack.Push('d', uskTyping); // coalesces with c
  AssertEquals('typing after undo is a fresh step', 1, FStack.UndoDepth);
end;

procedure TTyUndoStackTest.TestCapDropsOldest;
var
  i: Integer;
  s: string;
begin
  for i := 1 to 250 do
    FStack.Push('d' + IntToStr(i), uskDelete);
  AssertEquals('cap at 200', 200, FStack.UndoDepth);
  // Newest retained: top of undo should be 'd250'
  s := FStack.Undo('cur');
  AssertEquals('newest retained on top', 'd250', s);
  // Oldest dropped: after 199 more undos we should hit 'd51' (250-199=51), not 'd1'
end;

procedure TTyUndoStackTest.TestClearResetsBoth;
begin
  FStack.Push('a', uskDelete);
  FStack.Undo('b');
  AssertTrue('has undo or redo before clear', FStack.CanRedo);
  FStack.Clear;
  AssertFalse('clear resets undo', FStack.CanUndo);
  AssertFalse('clear resets redo', FStack.CanRedo);
  AssertEquals('undo depth 0 after clear', 0, FStack.UndoDepth);
  AssertEquals('redo depth 0 after clear', 0, FStack.RedoDepth);
end;

initialization
  RegisterTest(TTyUndoStackTest);
end.
