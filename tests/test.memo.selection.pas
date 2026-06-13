unit test.memo.selection;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, LCLType, LazUTF8, fpcunit, testregistry,
  BGRABitmap, BGRABitmapTypes,
  tyControls.Types, tyControls.Controller, tyControls.Base,
  tyControls.ScrollBar,
  tyControls.Memo;
type
  { Probe subclass: exposes the protected 2D-selection API for headless tests. }
  TTyMemoSelProbe = class(TTyMemo)
  public
    function ProbeHasSelection: Boolean;
    function ProbeSelText: string;
    procedure ProbeSelectAll;
    procedure ProbeClearSelection;
    procedure ProbeSetCaret(ALine, ACol: Integer);
    procedure ProbeSetAnchor(ALine, ACol: Integer);
    function ProbeCaretLine: Integer;
    function ProbeCaretCol: Integer;
    procedure ProbeSelStart(out SL, SC: Integer);
    procedure ProbeSelEnd(out EL, EC: Integer);
    procedure ProbeDeleteSelection;
    function ProbeLineCount: Integer;
    function ProbeLine(AIndex: Integer): string;
  end;

  TTyMemoSelectionTest = class(TTestCase)
  private
    FCtl: TTyStyleController;
    FMemo: TTyMemoSelProbe;
    FChangeCount: Integer;
    procedure SetUpMemo;
    procedure LoadLines(const AItems: array of string);
    procedure OnMemoChange(Sender: TObject);
  protected
    procedure TearDown; override;
  published
    procedure TestNoSelectionInitially;
    procedure TestSelectAllSpansDocument;
    procedure TestSelTextSingleLine;
    procedure TestSelTextMultiLineJoinedByLineEnding;
    procedure TestOrderedSelLexicographic;
    procedure TestClearSelectionCollapses;
    // --- T2: DeleteSelection 2D + typing/Enter/Backspace/Delete routing ---
    procedure TestDeleteSelectionWithinLine;
    procedure TestDeleteSelectionMultiLineMergesHeadTail;
    procedure TestTypingReplacesSelection;
    procedure TestEnterReplacesSelection;
    procedure TestBackspaceDeletesSelectionNotPrevChar;
    procedure TestBackspaceNoSelectionStillNoopAtOrigin;
  end;

implementation

{ TTyMemoSelProbe }

function TTyMemoSelProbe.ProbeHasSelection: Boolean;
begin
  Result := HasSelection;
end;

function TTyMemoSelProbe.ProbeSelText: string;
begin
  Result := SelText;
end;

procedure TTyMemoSelProbe.ProbeSelectAll;
begin
  SelectAll;
end;

procedure TTyMemoSelProbe.ProbeClearSelection;
begin
  ClearSelection;
end;

procedure TTyMemoSelProbe.ProbeSetCaret(ALine, ACol: Integer);
begin
  SetCaret(ALine, ACol);
end;

procedure TTyMemoSelProbe.ProbeSetAnchor(ALine, ACol: Integer);
begin
  SetSelAnchor(ALine, ACol);
end;

function TTyMemoSelProbe.ProbeCaretLine: Integer;
begin
  Result := CaretLine;
end;

function TTyMemoSelProbe.ProbeCaretCol: Integer;
begin
  Result := CaretCol;
end;

procedure TTyMemoSelProbe.ProbeSelStart(out SL, SC: Integer);
begin
  SL := SelStartLine;
  SC := SelStartCol;
end;

procedure TTyMemoSelProbe.ProbeSelEnd(out EL, EC: Integer);
begin
  EL := SelEndLine;
  EC := SelEndCol;
end;

procedure TTyMemoSelProbe.ProbeDeleteSelection;
begin
  DeleteSelection;
end;

function TTyMemoSelProbe.ProbeLineCount: Integer;
begin
  Result := Lines.Count;
end;

function TTyMemoSelProbe.ProbeLine(AIndex: Integer): string;
begin
  Result := Lines[AIndex];
end;

{ TTyMemoSelectionTest }

procedure TTyMemoSelectionTest.SetUpMemo;
begin
  FCtl := TTyStyleController.Create(nil);
  FCtl.LoadThemeCss(
    'TyMemo { background:#FFFFFF; color:#000000; padding:0px; font-size:14px; }');
  FMemo := TTyMemoSelProbe.Create(nil);
  FMemo.Controller := FCtl;
  FMemo.Font.PixelsPerInch := 96;
  FMemo.SetBounds(0, 0, 200, 120);
  FChangeCount := 0;
  FMemo.OnChange := @OnMemoChange;
end;

procedure TTyMemoSelectionTest.OnMemoChange(Sender: TObject);
begin
  Inc(FChangeCount);
end;

procedure TTyMemoSelectionTest.LoadLines(const AItems: array of string);
var
  L: TStringList;
  i: Integer;
begin
  L := TStringList.Create;
  try
    for i := Low(AItems) to High(AItems) do
      L.Add(AItems[i]);
    FMemo.Lines := L;
  finally
    L.Free;
  end;
end;

procedure TTyMemoSelectionTest.TearDown;
begin
  FMemo.Free;
  FMemo := nil;
  FCtl.Free;
  FCtl := nil;
end;

procedure TTyMemoSelectionTest.TestNoSelectionInitially;
begin
  SetUpMemo;
  AssertFalse('fresh memo has no selection', FMemo.ProbeHasSelection);
  AssertEquals('fresh memo SelText empty', '', FMemo.ProbeSelText);
end;

procedure TTyMemoSelectionTest.TestSelectAllSpansDocument;
var
  SL, SC, EL, EC: Integer;
begin
  SetUpMemo;
  LoadLines(['ab', 'c中d', '']);
  FMemo.ProbeSelectAll;
  FMemo.ProbeSelStart(SL, SC);
  FMemo.ProbeSelEnd(EL, EC);
  AssertEquals('SelStartLine=0', 0, SL);
  AssertEquals('SelStartCol=0', 0, SC);
  AssertEquals('SelEndLine=2 (last line)', 2, EL);
  AssertEquals('SelEndCol=0 (empty last line)', 0, EC);
  AssertTrue('SelectAll yields a selection', FMemo.ProbeHasSelection);
end;

procedure TTyMemoSelectionTest.TestSelTextSingleLine;
begin
  SetUpMemo;
  LoadLines(['abcde']);
  FMemo.ProbeSetCaret(0, 4);
  FMemo.ProbeSetAnchor(0, 1);
  AssertEquals('single-line SelText', 'bcd', FMemo.ProbeSelText);
end;

procedure TTyMemoSelectionTest.TestSelTextMultiLineJoinedByLineEnding;
begin
  SetUpMemo;
  LoadLines(['hello', 'wor中ld', 'tail']);
  FMemo.ProbeSetCaret(2, 2);
  FMemo.ProbeSetAnchor(0, 2);
  AssertEquals('multi-line SelText joined by LineEnding',
    'llo' + LineEnding + 'wor中ld' + LineEnding + 'ta', FMemo.ProbeSelText);
end;

procedure TTyMemoSelectionTest.TestOrderedSelLexicographic;
var
  SL, SC, EL, EC: Integer;
begin
  SetUpMemo;
  LoadLines(['abcde', 'fghij', 'klmno']);
  // Anchor AFTER caret: ordering must be independent of which side is the anchor.
  FMemo.ProbeSetCaret(0, 3);
  FMemo.ProbeSetAnchor(2, 1);
  FMemo.ProbeSelStart(SL, SC);
  FMemo.ProbeSelEnd(EL, EC);
  AssertEquals('SelStartLine=0', 0, SL);
  AssertEquals('SelStartCol=3', 3, SC);
  AssertEquals('SelEndLine=2', 2, EL);
  AssertEquals('SelEndCol=1', 1, EC);
end;

procedure TTyMemoSelectionTest.TestClearSelectionCollapses;
begin
  SetUpMemo;
  LoadLines(['abcde', 'fghij']);
  FMemo.ProbeSetCaret(1, 2);
  FMemo.ProbeSetAnchor(0, 1);
  AssertTrue('selection present before clear', FMemo.ProbeHasSelection);
  FMemo.ProbeClearSelection;
  AssertFalse('no selection after clear', FMemo.ProbeHasSelection);
  AssertEquals('caret line unchanged after clear', 1, FMemo.ProbeCaretLine);
  AssertEquals('caret col unchanged after clear', 2, FMemo.ProbeCaretCol);
end;

// --- T2: DeleteSelection 2D + typing/Enter/Backspace/Delete routing ---

procedure TTyMemoSelectionTest.TestDeleteSelectionWithinLine;
begin
  SetUpMemo;
  LoadLines(['abcdef']);
  FMemo.ProbeSetAnchor(0, 1);
  FMemo.ProbeSetCaret(0, 4);  // SetCaret collapses; re-anchor after
  FMemo.ProbeSetAnchor(0, 1);
  AssertTrue('selection present', FMemo.ProbeHasSelection);
  FMemo.ProbeDeleteSelection;
  AssertEquals('line spliced to aef', 'aef', FMemo.ProbeLine(0));
  AssertEquals('caret line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('caret col 1', 1, FMemo.ProbeCaretCol);
  AssertFalse('selection collapsed', FMemo.ProbeHasSelection);
end;

procedure TTyMemoSelectionTest.TestDeleteSelectionMultiLineMergesHeadTail;
begin
  SetUpMemo;
  LoadLines(['hello', 'middle', 'world']);
  FMemo.ProbeSetCaret(2, 3);
  FMemo.ProbeSetAnchor(0, 2);
  AssertTrue('selection present', FMemo.ProbeHasSelection);
  FMemo.ProbeDeleteSelection;
  AssertEquals('collapsed to single line', 1, FMemo.ProbeLineCount);
  AssertEquals('head he + tail ld', 'held', FMemo.ProbeLine(0));
  AssertEquals('caret line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('caret col 2', 2, FMemo.ProbeCaretCol);
end;

procedure TTyMemoSelectionTest.TestTypingReplacesSelection;
begin
  SetUpMemo;
  LoadLines(['abc', 'def']);
  FMemo.ProbeSetCaret(1, 1);
  FMemo.ProbeSetAnchor(0, 1);
  FMemo.InjectChar('X');
  AssertEquals('collapsed to single line', 1, FMemo.ProbeLineCount);
  AssertEquals('aXef', 'aXef', FMemo.ProbeLine(0));
  AssertEquals('caret line 0', 0, FMemo.ProbeCaretLine);
  AssertEquals('caret col 2', 2, FMemo.ProbeCaretCol);
  AssertEquals('OnChange fired once', 1, FChangeCount);
end;

procedure TTyMemoSelectionTest.TestEnterReplacesSelection;
begin
  SetUpMemo;
  LoadLines(['abc', 'def']);
  FMemo.ProbeSetCaret(1, 1);
  FMemo.ProbeSetAnchor(0, 1);
  FMemo.InjectKey(VK_RETURN, []);
  AssertEquals('two lines after split', 2, FMemo.ProbeLineCount);
  AssertEquals('line 0 = a', 'a', FMemo.ProbeLine(0));
  AssertEquals('line 1 = ef', 'ef', FMemo.ProbeLine(1));
end;

procedure TTyMemoSelectionTest.TestBackspaceDeletesSelectionNotPrevChar;
begin
  SetUpMemo;
  LoadLines(['abcd']);
  FMemo.ProbeSetCaret(0, 3);
  FMemo.ProbeSetAnchor(0, 1);
  FMemo.InjectBackspace;
  AssertEquals('selection deleted to ad', 'ad', FMemo.ProbeLine(0));
  AssertEquals('caret col 1', 1, FMemo.ProbeCaretCol);
  AssertFalse('selection collapsed', FMemo.ProbeHasSelection);
end;

procedure TTyMemoSelectionTest.TestBackspaceNoSelectionStillNoopAtOrigin;
begin
  SetUpMemo;
  LoadLines(['abc']);
  FMemo.ProbeSetCaret(0, 0);  // no anchor diff -> no selection
  AssertFalse('no selection', FMemo.ProbeHasSelection);
  FMemo.InjectBackspace;
  AssertEquals('line unchanged', 'abc', FMemo.ProbeLine(0));
  AssertEquals('OnChange not fired (additivity)', 0, FChangeCount);
end;

initialization
  RegisterTest(TTyMemoSelectionTest);
end.
