unit test.edit.word;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, fpcunit, testregistry, Forms, LCLType,
  LazUTF8,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.Edit;
type
  // Access subclass exposing the private word-boundary helpers publicly.
  TTyEditWordAccess = class(TTyEdit)
  public
    function NextWordBoundary(AIdx: Integer): Integer;
    function PrevWordBoundary(AIdx: Integer): Integer;
  end;

  // Access subclass exposing KeyDown simulation for word-wise caret movement.
  // CaretPos/SelStart/SelLength are already public on TTyEdit.
  TTyEditWordKeyAccess = class(TTyEdit)
  public
    procedure SimulateKeyDownShift(Key: Word; Shift: TShiftState);
    procedure SimulateKeyDownShiftRef(var Key: Word; Shift: TShiftState);
  end;

  TEditWordTest = class(TTestCase)
  private
    FForm: TCustomForm;
    FEdit: TTyEditWordAccess;
    procedure SetText(const S: string);
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestFooBarNext;
    procedure TestFooBarPrev;
    procedure TestFooDotBar;
    procedure TestAPlusB;
    procedure TestLeadingSpaces;
    procedure TestLeadingDashes;
    procedure TestTrailingSpaces;
    procedure TestAllPunct;
    procedure TestEmpty;
    procedure TestAccented;
    procedure TestCJK;
    procedure TestOutOfRangeClamp;
  end;

  // WORD.2: Alt+Left/Alt+Right move caret by word (collapse selection);
  // Ctrl+arrow keeps falling through unchanged.
  TEditWordKeyTest = class(TTestCase)
  private
    FForm: TCustomForm;
    FEdit: TTyEditWordKeyAccess;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAltRightWalksForward;
    procedure TestAltLeftWalksBackward;
    procedure TestAltLeftCollapsesSelection;
    procedure TestAltRightCollapsesSelection;
    procedure TestAltRightMultibyte;
    procedure TestCtrlLeftStillFallsThrough;
    procedure TestPlainLeftStillMovesOne;
  end;

  // WORD.3: Alt+Shift+Left/Alt+Shift+Right extend selection to word boundary
  // (move only FCaret, keep FSelAnchor); Ctrl+Shift+arrow stays single-char.
  TEditWordExtendTest = class(TTestCase)
  private
    FForm: TCustomForm;
    FEdit: TTyEditWordKeyAccess;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestAltShiftRightExtendsForward;
    procedure TestAltShiftLeftExtendsBackward;
    procedure TestAltExtendThenCollapse;
    procedure TestCtrlShiftRightStillSingleChar;
  end;

  // WORD.4: Ctrl/Alt+Backspace deletes the previous word; Ctrl/Alt+Delete
  // deletes the next word. Selection present -> delete selection only (no
  // word-delete). Plain (unmodified) VK_BACK/VK_DELETE still delete one cp.
  TEditWordDeleteTest = class(TTestCase)
  private
    FForm: TCustomForm;
    FEdit: TTyEditWordKeyAccess;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestCtrlBackspaceDeletesPrevWord;
    procedure TestAltBackspaceDeletesPrevWord;
    procedure TestCtrlBackspaceStopsAtPunct;
    procedure TestAltDeleteDeletesNextWord;
    procedure TestSelectionWinsOverWordBackspace;
    procedure TestSelectionWinsOverWordDelete;
    procedure TestCtrlBackspaceAtStartIsNoOp;
    procedure TestCtrlDeleteAtEndIsNoOp;
    procedure TestCtrlBackspaceMultibyte;
    procedure TestPlainBackspaceStillDeletesOne;
  end;

implementation

function TTyEditWordAccess.NextWordBoundary(AIdx: Integer): Integer;
begin
  Result := inherited NextWordBoundary(AIdx);
end;

function TTyEditWordAccess.PrevWordBoundary(AIdx: Integer): Integer;
begin
  Result := inherited PrevWordBoundary(AIdx);
end;

procedure TTyEditWordKeyAccess.SimulateKeyDownShift(Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;

procedure TTyEditWordKeyAccess.SimulateKeyDownShiftRef(var Key: Word; Shift: TShiftState);
begin
  KeyDown(Key, Shift);
end;

procedure TEditWordTest.SetText(const S: string);
begin
  FEdit.Text := S;
end;

procedure TEditWordTest.SetUp;
begin
  FForm := TCustomForm.CreateNew(nil);
  FEdit := TTyEditWordAccess.Create(FForm);
  FEdit.Parent := FForm;
end;

procedure TEditWordTest.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FEdit := nil;
end;

// 'foo bar': Next(0)=4, Next(3)=4, Next(4)=7, Next(7)=7(end).
procedure TEditWordTest.TestFooBarNext;
begin
  SetText('foo bar');
  AssertEquals('Next(0)', 4, FEdit.NextWordBoundary(0));
  AssertEquals('Next(3)', 4, FEdit.NextWordBoundary(3));
  AssertEquals('Next(4)', 7, FEdit.NextWordBoundary(4));
  AssertEquals('Next(7) end', 7, FEdit.NextWordBoundary(7));
end;

// Prev(7)=4, Prev(4)=0, Prev(3)=0, Prev(0)=0.
procedure TEditWordTest.TestFooBarPrev;
begin
  SetText('foo bar');
  AssertEquals('Prev(7)', 4, FEdit.PrevWordBoundary(7));
  AssertEquals('Prev(4)', 0, FEdit.PrevWordBoundary(4));
  AssertEquals('Prev(3)', 0, FEdit.PrevWordBoundary(3));
  AssertEquals('Prev(0)', 0, FEdit.PrevWordBoundary(0));
end;

// 'foo.bar' (dot is punct): Next(0)=4, Next(4)=7. Prev(7)=4, Prev(4)=0.
procedure TEditWordTest.TestFooDotBar;
begin
  SetText('foo.bar');
  AssertEquals('Next(0)', 4, FEdit.NextWordBoundary(0));
  AssertEquals('Next(4)', 7, FEdit.NextWordBoundary(4));
  AssertEquals('Prev(7)', 4, FEdit.PrevWordBoundary(7));
  AssertEquals('Prev(4)', 0, FEdit.PrevWordBoundary(4));
end;

// 'a+b': Next(0)=2, Prev(3)=2, Prev(2)=0.
procedure TEditWordTest.TestAPlusB;
begin
  SetText('a+b');
  AssertEquals('Next(0)', 2, FEdit.NextWordBoundary(0));
  AssertEquals('Prev(3)', 2, FEdit.PrevWordBoundary(3));
  AssertEquals('Prev(2)', 0, FEdit.PrevWordBoundary(2));
end;

// '  foo': Next(0)=2 (lands on 'f').
procedure TEditWordTest.TestLeadingSpaces;
begin
  SetText('  foo');
  AssertEquals('Next(0) lands on f', 2, FEdit.NextWordBoundary(0));
end;

// '--foo': Next(0)=2 (word-run loop skips nothing at 0, punct-run skips '--').
// DOCUMENT/assert 2 not 5.
procedure TEditWordTest.TestLeadingDashes;
begin
  SetText('--foo');
  AssertEquals('Next(0) is 2 not 5', 2, FEdit.NextWordBoundary(0));
end;

// 'foo   ' (trailing spaces): Next(0)=6 (end), Next(3)=6. Prev(6)=0.
procedure TEditWordTest.TestTrailingSpaces;
begin
  SetText('foo   ');
  AssertEquals('Next(0)', 6, FEdit.NextWordBoundary(0));
  AssertEquals('Next(3)', 6, FEdit.NextWordBoundary(3));
  AssertEquals('Prev(6)', 0, FEdit.PrevWordBoundary(6));
end;

// '....' (all punct): Next(0)=4, Prev(4)=0.
procedure TEditWordTest.TestAllPunct;
begin
  SetText('....');
  AssertEquals('Next(0)', 4, FEdit.NextWordBoundary(0));
  AssertEquals('Prev(4)', 0, FEdit.PrevWordBoundary(4));
end;

// '' (empty): Next(0)=0, Prev(0)=0.
procedure TEditWordTest.TestEmpty;
begin
  SetText('');
  AssertEquals('Next(0)', 0, FEdit.NextWordBoundary(0));
  AssertEquals('Prev(0)', 0, FEdit.PrevWordBoundary(0));
end;

// 'café bàr' — multibyte; indices are codepoint counts.
// 'café'=4 codepoints, then space at 4, 'bàr'=3 codepoints -> total 8.
// Next(0): skip word 'café' (4) then skip space -> 5.
// Next(5): skip word 'bàr' (to 8) -> 8 (end).
// Prev(8)=5, Prev(5)=0, Prev(4)=0.
procedure TEditWordTest.TestAccented;
begin
  SetText('café bàr');
  AssertEquals('codepoint length', 8, UTF8Length(FEdit.Text));
  AssertEquals('Next(0)', 5, FEdit.NextWordBoundary(0));
  AssertEquals('Next(5)', 8, FEdit.NextWordBoundary(5));
  AssertEquals('Prev(8)', 5, FEdit.PrevWordBoundary(8));
  AssertEquals('Prev(5)', 0, FEdit.PrevWordBoundary(5));
  AssertEquals('Prev(4)', 0, FEdit.PrevWordBoundary(4));
end;

// '你好 世界': each CJK char = 1 codepoint. '你好'=2, space at 2, '世界'=2 -> total 5.
// Next(0)=3 (skip word '你好' (2), skip space -> 3, lands on '世').
// Prev(5)=3, Prev(3)=0.
procedure TEditWordTest.TestCJK;
begin
  SetText('你好 世界');
  AssertEquals('codepoint length', 5, UTF8Length(FEdit.Text));
  AssertEquals('Next(0) lands on 世', 3, FEdit.NextWordBoundary(0));
  AssertEquals('Prev(5)', 3, FEdit.PrevWordBoundary(5));
  AssertEquals('Prev(3)', 0, FEdit.PrevWordBoundary(3));
end;

// Out-of-range clamp on 'foo bar' (Len=7):
// Next(-5) behaves as Next(0)=4; Next(999)=Len=7; Prev(-1)=0; Prev(999)=PrevWordBoundary(Len)=Prev(7)=4.
procedure TEditWordTest.TestOutOfRangeClamp;
begin
  SetText('foo bar');
  AssertEquals('Next(-5) == Next(0)', 4, FEdit.NextWordBoundary(-5));
  AssertEquals('Next(999) == Len', 7, FEdit.NextWordBoundary(999));
  AssertEquals('Prev(-1) == 0', 0, FEdit.PrevWordBoundary(-1));
  AssertEquals('Prev(999) == Prev(Len)', 4, FEdit.PrevWordBoundary(999));
end;

// ---- WORD.2: Alt+Left/Alt+Right word-wise caret movement ----

procedure TEditWordKeyTest.SetUp;
begin
  FForm := TCustomForm.CreateNew(nil);
  FEdit := TTyEditWordKeyAccess.Create(FForm);
  FEdit.Parent := FForm;
end;

procedure TEditWordKeyTest.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FEdit := nil;
end;

// 'foo bar baz', from 0: Alt+Right -> 4 -> 8 -> 11 -> 11 (clamp). SelLength=0 throughout.
procedure TEditWordKeyTest.TestAltRightWalksForward;
begin
  FEdit.Text := 'foo bar baz';
  FEdit.CaretPos := 0;
  FEdit.SimulateKeyDownShift(VK_RIGHT, [ssAlt]);
  AssertEquals('1st Alt+Right', 4, FEdit.CaretPos);
  AssertEquals('1st SelLength', 0, FEdit.SelLength);
  FEdit.SimulateKeyDownShift(VK_RIGHT, [ssAlt]);
  AssertEquals('2nd Alt+Right', 8, FEdit.CaretPos);
  AssertEquals('2nd SelLength', 0, FEdit.SelLength);
  FEdit.SimulateKeyDownShift(VK_RIGHT, [ssAlt]);
  AssertEquals('3rd Alt+Right', 11, FEdit.CaretPos);
  AssertEquals('3rd SelLength', 0, FEdit.SelLength);
  FEdit.SimulateKeyDownShift(VK_RIGHT, [ssAlt]);
  AssertEquals('4th Alt+Right clamp', 11, FEdit.CaretPos);
  AssertEquals('4th SelLength', 0, FEdit.SelLength);
end;

// 'foo bar baz', from 11: Alt+Left -> 8 -> 4 -> 0 -> 0 (clamp). SelLength=0 throughout.
procedure TEditWordKeyTest.TestAltLeftWalksBackward;
begin
  FEdit.Text := 'foo bar baz';
  FEdit.CaretPos := 11;
  FEdit.SimulateKeyDownShift(VK_LEFT, [ssAlt]);
  AssertEquals('1st Alt+Left', 8, FEdit.CaretPos);
  AssertEquals('1st SelLength', 0, FEdit.SelLength);
  FEdit.SimulateKeyDownShift(VK_LEFT, [ssAlt]);
  AssertEquals('2nd Alt+Left', 4, FEdit.CaretPos);
  AssertEquals('2nd SelLength', 0, FEdit.SelLength);
  FEdit.SimulateKeyDownShift(VK_LEFT, [ssAlt]);
  AssertEquals('3rd Alt+Left', 0, FEdit.CaretPos);
  AssertEquals('3rd SelLength', 0, FEdit.SelLength);
  FEdit.SimulateKeyDownShift(VK_LEFT, [ssAlt]);
  AssertEquals('4th Alt+Left clamp', 0, FEdit.CaretPos);
  AssertEquals('4th SelLength', 0, FEdit.SelLength);
end;

// 'foo bar', SelectAll (Sel 0..7), Alt+Left -> caret=PrevWordBoundary(7)=4, selection collapsed.
procedure TEditWordKeyTest.TestAltLeftCollapsesSelection;
begin
  FEdit.Text := 'foo bar';
  FEdit.SelectAll;
  AssertEquals('pre SelLength', 7, FEdit.SelLength);
  FEdit.SimulateKeyDownShift(VK_LEFT, [ssAlt]);
  AssertEquals('Alt+Left caret = PrevWordBoundary(7)', 4, FEdit.CaretPos);
  AssertEquals('selection collapsed', 0, FEdit.SelLength);
end;

// 'foo bar', SelectAll (Sel 0..7), Alt+Right -> caret=NextWordBoundary(7)=7, selection collapsed.
procedure TEditWordKeyTest.TestAltRightCollapsesSelection;
begin
  FEdit.Text := 'foo bar';
  FEdit.SelectAll;
  AssertEquals('pre SelLength', 7, FEdit.SelLength);
  FEdit.SimulateKeyDownShift(VK_RIGHT, [ssAlt]);
  AssertEquals('Alt+Right caret = NextWordBoundary(7)', 7, FEdit.CaretPos);
  AssertEquals('selection collapsed', 0, FEdit.SelLength);
end;

// 'café bàr' (multibyte), from 0: Alt+Right -> 5 (codepoint count past 'café'+space).
procedure TEditWordKeyTest.TestAltRightMultibyte;
begin
  FEdit.Text := 'café bàr';
  FEdit.CaretPos := 0;
  FEdit.SimulateKeyDownShift(VK_RIGHT, [ssAlt]);
  AssertEquals('Alt+Right past café+space', 5, FEdit.CaretPos);
  AssertEquals('SelLength', 0, FEdit.SelLength);
end;

// v1.8: Ctrl+Left is word-wise too (Win/Linux); jumps to word start and
// consumes Key. (macOS Option=ssAlt covered by the Alt tests.)
procedure TEditWordKeyTest.TestCtrlLeftStillFallsThrough;
var
  Key: Word;
begin
  FEdit.Text := 'abc';
  FEdit.CaretPos := 2;
  Key := VK_LEFT;
  FEdit.SimulateKeyDownShiftRef(Key, [ssCtrl]);
  AssertEquals('Ctrl+Left word-wise to start', 0, FEdit.CaretPos);
  AssertTrue('Ctrl+Left Key consumed', Key = 0);
end;

// Sanity: plain VK_LEFT (no modifier) still moves one codepoint.
procedure TEditWordKeyTest.TestPlainLeftStillMovesOne;
begin
  FEdit.Text := 'abc';
  FEdit.CaretPos := 2;
  FEdit.SimulateKeyDownShift(VK_LEFT, []);
  AssertEquals('plain Left moves one', 1, FEdit.CaretPos);
end;

// ---- WORD.3: Alt+Shift+Left/Right word-wise selection extension ----

procedure TEditWordExtendTest.SetUp;
begin
  FForm := TCustomForm.CreateNew(nil);
  FEdit := TTyEditWordKeyAccess.Create(FForm);
  FEdit.Parent := FForm;
end;

procedure TEditWordExtendTest.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FEdit := nil;
end;

// 'foo bar baz', from 0: Alt+Shift+Right -> anchor 0, caret 4, sel 0..4 'foo '.
// Again -> caret 8, sel 0..8.
procedure TEditWordExtendTest.TestAltShiftRightExtendsForward;
begin
  FEdit.Text := 'foo bar baz';
  FEdit.CaretPos := 0;
  FEdit.SimulateKeyDownShift(VK_RIGHT, [ssAlt, ssShift]);
  AssertEquals('1st SelStart', 0, FEdit.SelStart);
  AssertEquals('1st SelLength', 4, FEdit.SelLength);
  AssertEquals('1st SelText', 'foo ', FEdit.SelText);
  FEdit.SimulateKeyDownShift(VK_RIGHT, [ssAlt, ssShift]);
  AssertEquals('2nd SelStart', 0, FEdit.SelStart);
  AssertEquals('2nd SelLength', 8, FEdit.SelLength);
end;

// 'foo bar baz', from 11: Alt+Shift+Left -> anchor 11, caret 8, sel 8..11 'baz'.
// Again -> caret 4, sel 4..11.
procedure TEditWordExtendTest.TestAltShiftLeftExtendsBackward;
begin
  FEdit.Text := 'foo bar baz';
  FEdit.CaretPos := 11;
  FEdit.SimulateKeyDownShift(VK_LEFT, [ssAlt, ssShift]);
  AssertEquals('1st SelStart', 8, FEdit.SelStart);
  AssertEquals('1st SelLength', 3, FEdit.SelLength);
  AssertEquals('1st SelText', 'baz', FEdit.SelText);
  FEdit.SimulateKeyDownShift(VK_LEFT, [ssAlt, ssShift]);
  AssertEquals('2nd SelStart', 4, FEdit.SelStart);
  AssertEquals('2nd SelLength', 7, FEdit.SelLength);
end;

// 'foo bar baz', from 0: Alt+Shift+Right (sel 0..4), then Alt+Left ([ssAlt])
// collapses to caret=PrevWordBoundary(4)=0, SelLength=0.
procedure TEditWordExtendTest.TestAltExtendThenCollapse;
begin
  FEdit.Text := 'foo bar baz';
  FEdit.CaretPos := 0;
  FEdit.SimulateKeyDownShift(VK_RIGHT, [ssAlt, ssShift]);
  AssertEquals('extended SelLength', 4, FEdit.SelLength);
  FEdit.SimulateKeyDownShift(VK_LEFT, [ssAlt]);
  AssertEquals('collapse caret', 0, FEdit.CaretPos);
  AssertEquals('collapse SelLength', 0, FEdit.SelLength);
end;

// v1.8: Ctrl+Shift+Right is word-wise (Win/Linux); extends to next word
// boundary. 'foo bar' from 0 -> selects 'foo ' (4).
procedure TEditWordExtendTest.TestCtrlShiftRightStillSingleChar;
begin
  FEdit.Text := 'foo bar';
  FEdit.CaretPos := 0;
  FEdit.SimulateKeyDownShift(VK_RIGHT, [ssCtrl, ssShift]);
  AssertEquals('Ctrl+Shift+Right word-wise', 4, FEdit.SelLength);
end;

// ---- WORD.4: Ctrl/Alt+Backspace/Delete word-wise deletion ----

procedure TEditWordDeleteTest.SetUp;
begin
  FForm := TCustomForm.CreateNew(nil);
  FEdit := TTyEditWordKeyAccess.Create(FForm);
  FEdit.Parent := FForm;
end;

procedure TEditWordDeleteTest.TearDown;
begin
  FForm.Free;
  FForm := nil;
  FEdit := nil;
end;

// 'foo bar baz', caret 11: Ctrl+Back -> 'foo bar ' caret 8; again -> 'foo ' caret 4.
procedure TEditWordDeleteTest.TestCtrlBackspaceDeletesPrevWord;
begin
  FEdit.Text := 'foo bar baz';
  FEdit.CaretPos := 11;
  FEdit.SimulateKeyDownShift(VK_BACK, [ssCtrl]);
  AssertEquals('1st Ctrl+Back text', 'foo bar ', FEdit.Text);
  AssertEquals('1st Ctrl+Back caret', 8, FEdit.CaretPos);
  FEdit.SimulateKeyDownShift(VK_BACK, [ssCtrl]);
  AssertEquals('2nd Ctrl+Back text', 'foo ', FEdit.Text);
  AssertEquals('2nd Ctrl+Back caret', 4, FEdit.CaretPos);
end;

// Same as above but with Alt — proves both modifiers trigger word-delete.
procedure TEditWordDeleteTest.TestAltBackspaceDeletesPrevWord;
begin
  FEdit.Text := 'foo bar baz';
  FEdit.CaretPos := 11;
  FEdit.SimulateKeyDownShift(VK_BACK, [ssAlt]);
  AssertEquals('Alt+Back text', 'foo bar ', FEdit.Text);
  AssertEquals('Alt+Back caret', 8, FEdit.CaretPos);
end;

// 'foo.bar' caret 7: Ctrl+Back -> 'foo.' caret 4 (stops at punct boundary).
procedure TEditWordDeleteTest.TestCtrlBackspaceStopsAtPunct;
begin
  FEdit.Text := 'foo.bar';
  FEdit.CaretPos := 7;
  FEdit.SimulateKeyDownShift(VK_BACK, [ssCtrl]);
  AssertEquals('Ctrl+Back stops at punct text', 'foo.', FEdit.Text);
  AssertEquals('Ctrl+Back stops at punct caret', 4, FEdit.CaretPos);
end;

// 'foo bar baz', caret 0: Alt+Delete -> 'bar baz' caret 0; again -> 'baz' caret 0.
procedure TEditWordDeleteTest.TestAltDeleteDeletesNextWord;
begin
  FEdit.Text := 'foo bar baz';
  FEdit.CaretPos := 0;
  FEdit.SimulateKeyDownShift(VK_DELETE, [ssAlt]);
  AssertEquals('1st Alt+Delete text', 'bar baz', FEdit.Text);
  AssertEquals('1st Alt+Delete caret', 0, FEdit.CaretPos);
  FEdit.SimulateKeyDownShift(VK_DELETE, [ssAlt]);
  AssertEquals('2nd Alt+Delete text', 'baz', FEdit.Text);
  AssertEquals('2nd Alt+Delete caret', 0, FEdit.CaretPos);
end;

// Selection wins: SelectAll, Ctrl+Back -> deletes selection only -> '' caret 0.
procedure TEditWordDeleteTest.TestSelectionWinsOverWordBackspace;
begin
  FEdit.Text := 'foo bar';
  FEdit.SelectAll;
  FEdit.SimulateKeyDownShift(VK_BACK, [ssCtrl]);
  AssertEquals('selection deleted text', '', FEdit.Text);
  AssertEquals('selection deleted caret', 0, FEdit.CaretPos);
  AssertEquals('no selection after', 0, FEdit.SelLength);
end;

// Selection wins: SelectAll, Ctrl+Delete -> deletes selection only -> '' caret 0.
procedure TEditWordDeleteTest.TestSelectionWinsOverWordDelete;
begin
  FEdit.Text := 'foo bar';
  FEdit.SelectAll;
  FEdit.SimulateKeyDownShift(VK_DELETE, [ssCtrl]);
  AssertEquals('selection deleted text', '', FEdit.Text);
  AssertEquals('selection deleted caret', 0, FEdit.CaretPos);
  AssertEquals('no selection after', 0, FEdit.SelLength);
end;

// No-op edge: caret 0, Ctrl+Back -> text unchanged.
procedure TEditWordDeleteTest.TestCtrlBackspaceAtStartIsNoOp;
begin
  FEdit.Text := 'foo bar';
  FEdit.CaretPos := 0;
  FEdit.SimulateKeyDownShift(VK_BACK, [ssCtrl]);
  AssertEquals('Ctrl+Back at start no-op', 'foo bar', FEdit.Text);
  AssertEquals('caret stays 0', 0, FEdit.CaretPos);
end;

// No-op edge: caret at end, Ctrl+Delete -> text unchanged.
procedure TEditWordDeleteTest.TestCtrlDeleteAtEndIsNoOp;
begin
  FEdit.Text := 'foo bar';
  FEdit.CaretPos := 7;
  FEdit.SimulateKeyDownShift(VK_DELETE, [ssCtrl]);
  AssertEquals('Ctrl+Delete at end no-op', 'foo bar', FEdit.Text);
  AssertEquals('caret stays at end', 7, FEdit.CaretPos);
end;

// Multibyte: 'café bàr' caret at end (8 cp), Ctrl+Back -> 'café ' caret 5.
procedure TEditWordDeleteTest.TestCtrlBackspaceMultibyte;
begin
  FEdit.Text := 'café bàr';
  FEdit.CaretPos := UTF8Length(FEdit.Text);
  FEdit.SimulateKeyDownShift(VK_BACK, [ssCtrl]);
  AssertEquals('Ctrl+Back multibyte text', 'café ', FEdit.Text);
  AssertEquals('Ctrl+Back multibyte caret', 5, FEdit.CaretPos);
end;

// Regression guard: plain VK_BACK [] on 'abc' caret 3 deletes one char -> 'ab'.
procedure TEditWordDeleteTest.TestPlainBackspaceStillDeletesOne;
begin
  FEdit.Text := 'abc';
  FEdit.CaretPos := 3;
  FEdit.SimulateKeyDownShift(VK_BACK, []);
  AssertEquals('plain Back deletes one', 'ab', FEdit.Text);
  AssertEquals('plain Back caret', 2, FEdit.CaretPos);
end;

initialization
  RegisterTest(TEditWordTest);
  RegisterTest(TEditWordKeyTest);
  RegisterTest(TEditWordExtendTest);
  RegisterTest(TEditWordDeleteTest);
end.
