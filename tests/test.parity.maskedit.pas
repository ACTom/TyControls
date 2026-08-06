unit test.parity.maskedit;
{$mode objfpc}{$H+}
{ Guards for TTyMaskEdit's parity with LCL/Delphi TMaskEdit.

  Both original defects were the same shape as the ones pinned in test.parity: something
  that ran, returned, and quietly did the wrong thing. Nothing raised, nothing logged, and
  the control kept painting a perfectly plausible string.

  1. `Ed.Text := S` bypassed the mask entirely. Typing, Delete/Backspace and paste were
     all filtered; the plainest assignment of all was not.
  2. A Lazarus EditMask string was ACCEPTED and meant something else. This control spoke a
     three-code dialect ('#' digit, 'L' letter, 'C' any) in which '000-0000' has no
     editable slot at all and the field can never take a keystroke -- silently.

  (2) is now closed at the root: the language IS LCL/Delphi's. The tests below pin the
  vocabulary, the two deliberate departures from it, and the one refusal that survives.

  The defect assertions were watched go RED against the code as it shipped. The ones that
  describe the NEW vocabulary could not be -- half of them do not compile against a unit
  with no MaskSavesLiterals and no TyMaskIsLiteralAt -- so each is instead pinned by a
  mutant: breaking the rule it names, rebuilding, and confirming this file goes red. }
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
    procedure TextAssignmentTruncatesTheOverflowAndPadsTheShortfall;
    procedure TextAssignmentIsIdempotent;
    procedure IsCompleteAnswersAboutAStringTheMaskApproved;
    procedure StreamedTextSurvivesAndConforms;
    procedure AMaskWithNoEditableSlotIsRefused;
    procedure AnLclMaskTripleIsHonoured;
    procedure LclSlotCodesMeanWhatLclMeansByThem;
    procedure TheOneCodeTheTwoLanguagesDisagreeAboutIsRefused;
    procedure TheSeparatorCodesStayLiterals;
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
    M.Mask := '000';                 { something valid in force first }
    Raised := False;
    try
      M.Mask := AMask;
    except
      on ETyMaskError do Raised := True;
    end;
    AssertTrue(AWhat + ': must not be accepted in silence', Raised);
    AssertEquals(AWhat + ': and the refused mask must not have taken effect',
      '000', M.Mask);
    AssertTrue(AWhat + ': TyMaskRejectReason must say so without raising',
      TyMaskRejectReason(AMask) <> '');
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
    AssertEquals(AWhat + ': and TyMaskRejectReason must agree', '',
      TyMaskRejectReason(AMask));
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
    M.Mask := '000-000';
    M.Text := 'hello world';
    AssertEquals('nothing the mask rejects may land', '', M.MaskedValue);
    AssertEquals('and the box shows the empty skeleton', '___-___', M.Text);
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
    M.Mask := '0000-00-00';
    M.Text := '2026/07/30';               { slashes where the mask wants dashes }
    AssertEquals('rebuilt with the mask''s own literals', '2026-07-30', M.Text);
    AssertEquals('and it reads back', '20260730',
      TyMaskExtract('0000-00-00', M.Text, M.SpaceChar));
    AssertTrue('complete', M.IsComplete);
  finally
    M.Free;
  end;
end;

{ LCL truncates an over-long value (maskedit.pp ApplyMaskToText) and pads a short one out
  with blank chars; we now do both. }
procedure TMaskParityTest.TextAssignmentTruncatesTheOverflowAndPadsTheShortfall;
var
  M: TTyMaskEdit;
begin
  M := TTyMaskEdit.Create(nil);
  try
    M.Mask := '000';
    M.Text := '123456789';
    AssertEquals('everything past the last slot is dropped', '123', M.Text);

    M.Text := '7';
    AssertEquals('a short value is padded out to the mask', '7__', M.Text);
    AssertEquals('and the value behind it is just what was set', '7', M.MaskedValue);
    AssertFalse('and says so', M.IsComplete);

    { SpaceChar := #0 is the documented way back to the short form. }
    M.SpaceChar := #0;
    AssertEquals('no placeholder, no padding', '7', M.Text);
    AssertFalse('still incomplete either way', M.IsComplete);
  finally
    M.Free;
  end;
end;

{ `Ed.Text := Ed.Text` must be identity, or copying a value between two masked edits (or
  loading one from a .lfm) corrupts it. The trap is the 'C' code: it accepts any character
  bar the placeholder -- INCLUDING the mask's own literals -- so a re-filter that packs the
  display string back through the free slots eats the '-' as CONTENT and 'a-b' becomes
  'a--'. The setter therefore has to test conformance and keep a conforming value verbatim;
  that test is the only thing standing between `Text := Text` and data loss. }
procedure TMaskParityTest.TextAssignmentIsIdempotent;
var
  M: TTyMaskEdit;
begin
  M := TTyMaskEdit.Create(nil);
  try
    M.Mask := 'C-C';
    M.Text := 'ab';                        { two loose chars: packed into the two slots }
    AssertEquals('accepted chars laid in, literal rebuilt', 'a-b', M.Text);

    { The trap, spelled out: this string is ALREADY the mask's own output, and re-packing
      it would consume the '-' as the second slot's content. }
    M.Text := 'a-b';
    AssertEquals('a conforming value is kept verbatim, not re-filtered', 'a-b', M.Text);
    M.Text := M.Text;
    AssertEquals('assigning its own text changes nothing', 'a-b', M.Text);
    M.Text := M.Text;
    AssertEquals('still nothing the second time', 'a-b', M.Text);

    { Same trap with a hole in it -- in-place editing makes '_' a legal interior state,
      and the placeholder must not be re-read as content either. }
    M.Text := 'a-_';
    AssertEquals('a conforming value with a hole survives too', 'a-_', M.Text);
    AssertEquals('and the hole is not part of the value', 'a', M.MaskedValue);
  finally
    M.Free;
  end;
end;

{ TyMaskExtract copies the chars sitting at slot POSITIONS; it never asked whether they
  were legal for those slots. So IsComplete counted 6 characters in '000-000' holding
  'abc-def' and reported a fully-filled phone number made of letters. The fix is upstream
  of it: a string that never conformed can no longer be in Text to be counted. }
procedure TMaskParityTest.IsCompleteAnswersAboutAStringTheMaskApproved;
var
  M: TTyMaskEdit;
begin
  M := TTyMaskEdit.Create(nil);
  try
    M.Mask := '000-000';
    M.Text := 'abc-def';
    AssertFalse('six letters are not a filled digit mask', M.IsComplete);
    AssertEquals('and there is nothing to read back', '',
      TyMaskExtract('000-000', M.Text, M.SpaceChar));
    AssertEquals('nor through the control', '', M.MaskedValue);
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
    Src.ME.Mask := '00/00';
    Src.ME.Text := '12/34';
    MS.WriteComponent(Src);

    MS.Position := 0;
    MS.ReadComponent(Dst);
    D := Dst.FindComponent('ME') as TTyMaskEdit;
    AssertNotNull('the control survived', D);
    AssertEquals('the mask survived', '00/00', D.Mask);
    AssertEquals('and so did the designed text', '12/34', D.Text);
    AssertTrue('conforming, therefore complete', D.IsComplete);
  finally
    MS.Free;
    Dst.Free;
    Src.Free;
  end;
end;

{ ---------------------------------------------------- Defect 2: the language ------- }

{ The only refusal left. A mask with no editable cell cannot accept a keystroke, so it has
  no legitimate use: an inert field is spelled Mask := '' (plain edit) or ReadOnly := True.
  ('000-0000' and '99/99/00' used to land here -- under the three-code dialect every one of
  their characters was a literal. They are ordinary working masks now.) }
procedure TMaskParityTest.AMaskWithNoEditableSlotIsRefused;
begin
  AssertMaskRefused('literals only', '---');
  AssertMaskRefused('punctuation only', '()');
  AssertMaskRefused('every code escaped away', '\0\0');
  AssertMaskRefused('directives with nothing to direct', '>!<');
end;

{ ';' is LCL's `mask;save;blank` separator (maskedit.pp SplitEditMask). It used to be
  refused BY NAME, because a mask like '00/00;1;_' has real slots and would otherwise have
  taken digits and thrown the ';1;_' away unseen -- trailing literals with no slot after
  them never even render. The tail is parsed now, so there is nothing left to refuse. }
procedure TMaskParityTest.AnLclMaskTripleIsHonoured;
var
  M: TTyMaskEdit;
begin
  M := TTyMaskEdit.Create(nil);
  try
    M.Mask := '00/00;1;*';
    AssertEquals('the fields are stripped off the mask, not drawn', '**/**', M.Text);
    AssertEquals('the third field set the placeholder', '*', M.SpaceChar);
    AssertTrue('the second field set MaskSavesLiterals', M.MaskSavesLiterals);
    M.Text := '12/34';
    AssertEquals('and with save on, the literal is part of the value', '12/34',
      M.MaskedValue);
  finally
    M.Free;
  end;

  M := TTyMaskEdit.Create(nil);
  try
    M.Mask := '00/00;0;_';
    AssertFalse('save off', M.MaskSavesLiterals);
    M.Text := '12/34';
    AssertEquals('so the literal is stripped back out', '1234', M.MaskedValue);
  finally
    M.Free;
  end;

  { The real LCL time mask, whole, exactly as it is written in ported code. Under the
    three-code dialect this had no slot at all AND a ';' -- it was refused twice over. }
  M := TTyMaskEdit.Create(nil);
  try
    M.Mask := '!90:00;1;_';
    AssertEquals('a ported LCL time mask now works', '__:__', M.Text);
    M.Text := '0930';
    AssertEquals('and takes a time', '09:30', M.Text);
    AssertEquals('with the literal kept, as its save field asked', '09:30', M.MaskedValue);
  finally
    M.Free;
  end;

  { A mask that does NOT spell the fields keeps this control's own defaults, so every
    mask written before the fields existed reads the same as it always did. }
  M := TTyMaskEdit.Create(nil);
  try
    M.Mask := '00/00';
    AssertFalse('no field spelled, no literals saved', M.MaskSavesLiterals);
    AssertEquals('and the placeholder is untouched', '_', M.SpaceChar);
  finally
    M.Free;
  end;
end;

{ The vocabulary itself: every code LCL defines, meaning what LCL means by it. Under the
  three-code dialect each of these was a literal, so a ported mask ran and meant something
  else -- '000-0000' took no input at all, and nothing said so. }
procedure TMaskParityTest.LclSlotCodesMeanWhatLclMeansByThem;
var
  M: TTyMaskEdit;
begin
  AssertMaskTaken('LCL digit codes', '000-0000');
  AssertMaskTaken('LCL date mask', '99/99/00');
  AssertMaskTaken('LCL letter/alnum codes', 'AAA-aaa');
  AssertMaskTaken('optional letters', 'lll');
  AssertMaskTaken('any-char codes', 'ccc');
  AssertMaskTaken('hex', 'HHhh');
  AssertMaskTaken('binary', 'BBbb');
  AssertMaskTaken('case forcing', '>LLL<lll');
  AssertMaskTaken('an escaped literal beside a slot', '\A0');
  AssertMaskTaken('leading bang', '!00');

  { '' is the documented way to say "no mask": it must not be refused. }
  M := TTyMaskEdit.Create(nil);
  try
    M.Mask := '000';
    M.Mask := '';
    AssertEquals('the empty mask is a plain edit, not an error', '', M.Mask);
    M.Text := 'anything at all';
    AssertEquals('and it takes anything', 'anything at all', M.Text);
  finally
    M.Free;
  end;

  { The ported mask that used to be inert now takes exactly what LCL says it takes. }
  M := TTyMaskEdit.Create(nil);
  try
    M.Mask := '000-0000';
    AssertEquals('seven editable slots, not eight literals', '___-____', M.Text);
    M.Text := '0211234';
    AssertEquals('and it holds a phone number', '021-1234', M.Text);
    AssertTrue('complete', M.IsComplete);
  finally
    M.Free;
  end;

  { Hex and binary are Lazarus extensions, and were the two codes with no dialect
    equivalent at all. }
  M := TTyMaskEdit.Create(nil);
  try
    M.Mask := 'HH';
    M.Text := 'fg';
    AssertEquals('f is a hex digit and g is not', 'f_', M.Text);
  finally
    M.Free;
  end;

  M := TTyMaskEdit.Create(nil);
  try
    M.Mask := 'BBB';
    M.Text := '1021';
    AssertEquals('binary takes 0 and 1 only', '101', M.Text);
  finally
    M.Free;
  end;
end;

{ '#' is the ONE code the two languages disagree about. Here it meant a REQUIRED digit;
  in LCL/Delphi it means an OPTIONAL digit-or-sign. Reading an existing '##/##/####' the
  new way would leave a mask that IsComplete and ValidateEdit pass while it is EMPTY --
  a validator going quiet, which is the single failure a masked edit exists to prevent,
  and it would happen without a compile error or a run-time complaint anywhere. So the
  code is refused rather than reinterpreted, and the message names both readings. }
procedure TMaskParityTest.TheOneCodeTheTwoLanguagesDisagreeAboutIsRefused;
begin
  AssertMaskRefused('the old required-digit spelling', '##/##/####');
  AssertMaskRefused('one hash among working slots', '19##');
  AssertMaskRefused('a hash in the body of a triple', '##;1;_');
  { ...but a '#' is a perfectly good PLACEHOLDER, and the blank field is not mask body. }
  AssertMaskTaken('a hash as the blank character', '00/00;1;#');
  AssertTrue('and the reason names the replacement',
    Pos('"0"', TyMaskRejectReason('###')) > 0);

  { Escaped, it is an ordinary literal -- which is the documented way to keep one. }
  AssertMaskTaken('an escaped hash is a literal', '\#000');
  AssertEquals('and it draws', '#___', TyMaskApply('\#000', '', '_'));
end;

{ The other deliberate departure. In LCL ':' and '/' render the locale's time and date
  separator; here they are ordinary literals. Text IS the display string and it is
  published and streamed, so a locale-dependent literal would make one .lfm mean two
  different strings on two machines -- and '12/34' would stop conforming to '00/00' on
  any box whose date separator is not '/'. }
procedure TMaskParityTest.TheSeparatorCodesStayLiterals;
var
  M: TTyMaskEdit;
begin
  M := TTyMaskEdit.Create(nil);
  try
    M.Mask := '00:00/00';
    AssertEquals('both draw as themselves', '__:__/__', M.Text);
    AssertTrue('the colon is a literal, not a slot', TyMaskIsLiteralAt('00:00/00', 3));
    AssertTrue('and so is the slash', TyMaskIsLiteralAt('00:00/00', 6));
    M.Text := '123456';
    AssertEquals('and the digits step over them', '12:34/56', M.Text);
  finally
    M.Free;
  end;
end;

initialization
  RegisterClasses([TTyMaskEdit]);
  RegisterTest(TMaskParityTest);
end.
