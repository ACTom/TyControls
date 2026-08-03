unit test.parity.maskedit;
{$mode objfpc}{$H+}
{ Guards for TTyMaskEdit's two remaining parity gaps against LCL/Delphi TMaskEdit.

  Both are the same shape as the ones already pinned in test.parity: something that ran,
  returned, and quietly did the wrong thing. Nothing raised, nothing logged, and the
  control kept painting a perfectly plausible string.

  1. `Ed.Text := S` bypassed the mask entirely. Typing, Delete/Backspace and paste were
     all filtered; the plainest assignment of all was not.
  2. A Lazarus EditMask string was ACCEPTED and meant something else. '000-0000' has no
     '#' in it, so under this control's three slot codes every character is a literal and
     the field can never take a keystroke -- silently. tests/test.grid.pas shipped exactly
     that mask and was green.

  Every assertion below was watched go RED against the code as it shipped. }
interface
uses
  Classes, SysUtils, Forms, fpcunit, testregistry,
  tyControls.MaskEdit;

type
  TMaskParityTest = class(TTestCase)
  private
    { Assert that AMask is refused, and that refusing it did not disturb the mask in
      force. A setter that raises after it has already written the field is worse than
      one that never checked. }
    procedure AssertMaskRefused(const AWhat, AMask: string);
    procedure AssertMaskTaken(const AWhat, AMask: string);
  published
    procedure TextAssignmentGoesThroughTheMask;
    procedure TextAssignmentRebuildsTheLiterals;
    procedure TextAssignmentTruncatesTheOverflow;
    procedure TextAssignmentIsIdempotent;
    procedure IsCompleteAnswersAboutAStringTheMaskApproved;
    procedure StreamedTextSurvivesAndConforms;
    procedure AnLclMaskWithNoSlotIsRefused;
    procedure AnLclMaskTripleIsRefused;
    procedure TheThreeSlotCodesStillWork;
  end;

implementation

type
  { A streamable root for the .lfm round trip. }
  THostForm = class(TForm)
  published
    ME: TTyMaskEdit;
  end;

procedure TMaskParityTest.AssertMaskRefused(const AWhat, AMask: string);
var
  M: TTyMaskEdit;
  Raised: Boolean;
begin
  M := TTyMaskEdit.Create(nil);
  try
    M.Mask := '###';                 { something valid in force first }
    Raised := False;
    try
      M.Mask := AMask;
    except
      on ETyMaskError do Raised := True;
    end;
    AssertTrue(AWhat + ': must not be accepted in silence', Raised);
    AssertEquals(AWhat + ': and the refused mask must not have taken effect',
      '###', M.Mask);
  finally
    M.Free;
  end;
end;

procedure TMaskParityTest.AssertMaskTaken(const AWhat, AMask: string);
var
  M: TTyMaskEdit;
begin
  M := TTyMaskEdit.Create(nil);
  try
    M.Mask := AMask;
    AssertEquals(AWhat + ': must still be accepted', AMask, M.Mask);
  finally
    M.Free;
  end;
end;

{ ------------------------------------------------------- Defect 1: Text := ------- }

{ The headline case. UTF8KeyPress, KeyDown and FilterInsert are all overridden, so every
  way a USER can put text in is masked -- and the way a PROGRAM does it was not. }
procedure TMaskParityTest.TextAssignmentGoesThroughTheMask;
var
  M: TTyMaskEdit;
begin
  M := TTyMaskEdit.Create(nil);
  try
    M.Mask := '###-###';
    M.Text := 'hello world';
    AssertEquals('nothing the mask rejects may land', '', M.Text);
    AssertFalse('and it is certainly not complete', M.IsComplete);

    { Same rule as paste: keep what fits, drop the rest, in order. }
    M.Text := '12a3-45x6789';
    AssertEquals('digits laid into slots, everything else dropped', '123-456', M.Text);
    AssertTrue('all slots filled', M.IsComplete);
  finally
    M.Free;
  end;
end;

{ An assignment with the WRONG separators still lands, because literals are rebuilt from
  the mask rather than matched against the input -- exactly what a paste does. }
procedure TMaskParityTest.TextAssignmentRebuildsTheLiterals;
var
  M: TTyMaskEdit;
begin
  M := TTyMaskEdit.Create(nil);
  try
    M.Mask := '####-##-##';
    M.Text := '2026/07/30';               { slashes where the mask wants dashes }
    AssertEquals('rebuilt with the mask''s own literals', '2026-07-30', M.Text);
    AssertEquals('and it reads back', '20260730',
      TyMaskExtract('####-##-##', M.Text));
    AssertTrue('complete', M.IsComplete);
  finally
    M.Free;
  end;
end;

{ LCL truncates an over-long value (maskedit.pp ApplyMaskToText); so do we. What we do
  NOT do is LCL's other half, padding a short value out with blank chars -- this control
  has no blank char, and IsComplete is defined by how many slots are filled. }
procedure TMaskParityTest.TextAssignmentTruncatesTheOverflow;
var
  M: TTyMaskEdit;
begin
  M := TTyMaskEdit.Create(nil);
  try
    M.Mask := '###';
    M.Text := '123456789';
    AssertEquals('everything past the last slot is dropped', '123', M.Text);

    M.Text := '7';
    AssertEquals('a short value stays short -- no blank padding', '7', M.Text);
    AssertFalse('and says so', M.IsComplete);
  finally
    M.Free;
  end;
end;

{ `Ed.Text := Ed.Text` must be identity, or copying a value between two masked edits (or
  loading one from a .lfm) corrupts it. The trap is the 'C' code: it accepts any non-space
  char, so a naive re-filter eats the mask's own '-' as CONTENT and 'a-b' becomes 'a--'. }
procedure TMaskParityTest.TextAssignmentIsIdempotent;
var
  M: TTyMaskEdit;
begin
  M := TTyMaskEdit.Create(nil);
  try
    M.Mask := 'C-C';
    M.Text := 'a b';                       { space: illegal for 'C', must be dropped }
    AssertEquals('accepted chars laid in, literal rebuilt', 'a-b', M.Text);
    M.Text := M.Text;
    AssertEquals('assigning its own text changes nothing', 'a-b', M.Text);
    M.Text := M.Text;
    AssertEquals('still nothing the second time', 'a-b', M.Text);
  finally
    M.Free;
  end;
end;

{ TyMaskExtract copies the chars sitting at slot POSITIONS; it never asked whether they
  were legal for those slots. So IsComplete counted 6 characters in '###-###' holding
  'abc-def' and reported a fully-filled phone number made of letters. The fix is upstream
  of it: a string that never conformed can no longer be in Text to be counted. }
procedure TMaskParityTest.IsCompleteAnswersAboutAStringTheMaskApproved;
var
  M: TTyMaskEdit;
begin
  M := TTyMaskEdit.Create(nil);
  try
    M.Mask := '###-###';
    M.Text := 'abc-def';
    AssertFalse('six letters are not a filled digit mask', M.IsComplete);
    AssertEquals('and there is nothing to read back', '',
      TyMaskExtract('###-###', M.Text));
  finally
    M.Free;
  end;
end;

{ Text keeps the RTTI slot it inherited from TTyEdit, so the writer emits it BEFORE the
  descendant's Mask and the reader hands it over with no mask yet in force. SetMask then
  cleared it, and every value designed in the Object Inspector was lost on load. }
procedure TMaskParityTest.StreamedTextSurvivesAndConforms;
var
  Src, Dst: THostForm;
  MS: TMemoryStream;
  D: TTyMaskEdit;
begin
  Src := THostForm.CreateNew(nil);
  Dst := THostForm.CreateNew(nil);
  MS := TMemoryStream.Create;
  try
    Src.Name := 'MaskHost1';
    Src.ME := TTyMaskEdit.Create(Src);
    Src.ME.Name := 'ME';
    Src.ME.Parent := Src;
    Src.ME.Mask := '##/##';
    Src.ME.Text := '12/34';
    MS.WriteComponent(Src);

    MS.Position := 0;
    MS.ReadComponent(Dst);
    D := Dst.FindComponent('ME') as TTyMaskEdit;
    AssertNotNull('the control survived', D);
    AssertEquals('the mask survived', '##/##', D.Mask);
    AssertEquals('and so did the designed text', '12/34', D.Text);
    AssertTrue('conforming, therefore complete', D.IsComplete);
  finally
    MS.Free;
    Dst.Free;
    Src.Free;
  end;
end;

{ ---------------------------------------------------- Defect 2: the language ------- }

{ The dangerous half of the language gap is not the ~17 token codes we do not implement,
  it is that a Lazarus EditMask string is well-formed input to OUR parser and means
  something else. '000-0000' and '99/99/00' contain no '#', 'L' or 'C', so every character
  is a literal, there is no editable slot at all, and the field takes no input -- with no
  error anywhere. A mask that cannot accept a keystroke has no legitimate use: an inert
  field is spelled Mask := '' (plain edit) or ReadOnly := True. }
procedure TMaskParityTest.AnLclMaskWithNoSlotIsRefused;
begin
  AssertMaskRefused('LCL digit codes', '000-0000');
  AssertMaskRefused('LCL date mask', '99/99/00');
  AssertMaskRefused('LCL letter/alnum codes', 'AAA-aaa');
  AssertMaskRefused('literals only', '---');
end;

{ ';' is LCL's `mask;save;blank` separator and nothing else -- there is no mask anyone
  writes with a semicolon as a literal. This one has real slots, so the no-slot rule above
  cannot see it: '##/##;1;_' would have quietly taken two-digit pairs and thrown the ';1;_'
  away (trailing literals with no slot after them never even render). }
procedure TMaskParityTest.AnLclMaskTripleIsRefused;
begin
  AssertMaskRefused('mask;save;blank triple', '##/##;1;_');
  AssertMaskRefused('LCL time mask, whole triple', '!90:00;1;_');
end;

{ The boundary must be drawn without breaking the three codes that do work -- including
  masks that merely CONTAIN an LCL code as a literal ('19##' is a perfectly good year
  mask; refusing it to catch a hypothetical port would be the cure killing the patient). }
procedure TMaskParityTest.TheThreeSlotCodesStillWork;
var
  M: TTyMaskEdit;
begin
  AssertMaskTaken('digits', '###');
  AssertMaskTaken('letters', 'LLL');
  AssertMaskTaken('any non-space', 'CCC');
  AssertMaskTaken('date', '##/##/####');
  AssertMaskTaken('phone with literals', '(###) ###-####');
  AssertMaskTaken('IP', '###.###.###.###');
  AssertMaskTaken('digit literal next to slots', '19##');
  AssertMaskTaken('bang as a plain literal', '!##');

  { '' is the documented way to say "no mask": it must not be refused. }
  M := TTyMaskEdit.Create(nil);
  try
    M.Mask := '###';
    M.Mask := '';
    AssertEquals('the empty mask is a plain edit, not an error', '', M.Mask);
    M.Text := 'anything at all';
    AssertEquals('and it takes anything', 'anything at all', M.Text);
  finally
    M.Free;
  end;

  { Entry through the three codes is unchanged end to end. }
  M := TTyMaskEdit.Create(nil);
  try
    M.Mask := 'LL-###';
    M.Text := 'ab123';
    AssertEquals('letters then digits, separator rebuilt', 'ab-123', M.Text);
    AssertTrue('complete', M.IsComplete);
    AssertEquals('reads back', 'ab123', TyMaskExtract('LL-###', M.Text));
  finally
    M.Free;
  end;
end;

initialization
  RegisterClasses([TTyMaskEdit]);
  RegisterTest(TMaskParityTest);
end.
