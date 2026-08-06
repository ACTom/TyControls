unit test.maskedit;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, LCLType, fpcunit, testregistry, tyControls.MaskEdit;
type
  { Exposes the protected UTF8KeyPress and KeyDown so masked entry can be driven headlessly
    (InjectKey bypasses UTF8KeyPress, so it can't exercise the mask filter). }
  TAccessMask = class(TTyMaskEdit)
  public
    { The clipboard the mask edit reads, without touching the real one. }
    Clip: string;
    procedure Key(c: Char);
    procedure Press(k: Word);
    procedure PressWith(k: Word; Shift: TShiftState);
    function ReadClipboardText: string; override;
    procedure WriteClipboardText(const S: string); override;
  end;

  TMaskEditTest = class(TTestCase)
  published
    procedure TestApply;
    procedure TestExtractRoundTrip;
    procedure TestSlots;
    procedure TestControlEntry;
    procedure TestSkeletonAndCaret;
    procedure TestSpaceCharChangesTheSkeleton;
    procedure TestValidateEdit;
    procedure TestOptionalSlotsNeedNotBeFilled;
    procedure TestCaseForcingRegions;
    procedure TestEscapeMakesTheNextCharALiteral;
    procedure TestReadOnlyMaskedFieldTakesNoDictation;
    { The in-place half. }
    procedure TestTypingOverwritesTheSlotUnderTheCaret;
    procedure TestBackspaceTakesTheSlotBeforeAndDeleteTheSlotAt;
    procedure TestASlotCanBeEmptiedInTheMiddle;
    procedure TestPasteLandsAtTheCaret;
    procedure TestTypingOverASelectionClearsIt;
    procedure TestCutClearsTheSelectedSlotsInPlace;
    procedure TestShortFormKeepsItsOwnPastePath;
  end;

implementation

procedure TAccessMask.Key(c: Char);
var k: TUTF8Char;
begin
  k := c;
  UTF8KeyPress(k);
end;

procedure TAccessMask.Press(k: Word);
begin
  PressWith(k, []);
end;

procedure TAccessMask.PressWith(k: Word; Shift: TShiftState);
var w: Word;
begin
  w := k;
  KeyDown(w, Shift);
end;

function TAccessMask.ReadClipboardText: string;
begin
  Result := Clip;
end;

procedure TAccessMask.WriteClipboardText(const S: string);
begin
  Clip := S;
end;

procedure TMaskEditTest.TestApply;
begin
  { Skeleton form (ABlank <> #0): the whole mask always, placeholders where the input ran
    out -- including trailing literals the short form deliberately drops. }
  AssertEquals('empty skeleton', '__/__/____', TyMaskApply('00/00/0000', '', '_'));
  AssertEquals('half-typed skeleton', '12/__/____', TyMaskApply('00/00/0000', '12', '_'));
  AssertEquals('a trailing literal belongs to the skeleton', '(1__)',
    TyMaskApply('(000)', '1', '_'));
  AssertEquals('a full value is the same either way', '12/34',
    TyMaskApply('00/00', '1234', '_'));
  { Short form (still the default of the unit function) is untouched. }
  AssertEquals('full date', '12/34/5678', TyMaskApply('00/00/0000', '12345678'));
  AssertEquals('partial no trailing sep', '12', TyMaskApply('00/00/0000', '12'));
  AssertEquals('partial through sep', '12/3', TyMaskApply('00/00/0000', '123'));
  AssertEquals('phone literals', '(123) 456-7890', TyMaskApply('(000) 000-0000', '1234567890'));
  AssertEquals('leading literal', '(1', TyMaskApply('(000)', '1'));
end;

procedure TMaskEditTest.TestExtractRoundTrip;
begin
  { A placeholder is a slot nobody filled, never a character of the value. }
  AssertEquals('blanks are not content', '12',
    TyMaskExtract('00/00/0000', '12/__/____', '_'));
  AssertEquals('an empty skeleton holds nothing', '',
    TyMaskExtract('00/00/0000', '__/__/____', '_'));
  { In-place editing can leave a hole in the MIDDLE. Recovery skips it rather than
    stopping there -- stopping was only ever right while entry was append-only. }
  AssertEquals('a hole in the middle is skipped, not an end marker', '134',
    TyMaskExtract('00/00', '1_/34', '_'));
  AssertFalse('and is not complete', TyMaskIsComplete('00/00', '__/__', '_'));
  AssertFalse('nor is a holed one', TyMaskIsComplete('00/00', '1_/34', '_'));
  AssertTrue('a filled one is', TyMaskIsComplete('00/00', '12/34', '_'));
  AssertEquals('extract full', '12345678', TyMaskExtract('00/00/0000', '12/34/5678'));
  AssertEquals('extract partial', '123', TyMaskExtract('00/00/0000', '12/3'));
  // round-trip: extract(apply(raw)) = raw
  AssertEquals('roundtrip', '1234567890',
    TyMaskExtract('(000) 000-0000', TyMaskApply('(000) 000-0000', '1234567890')));
end;

procedure TMaskEditTest.TestSlots;
begin
  AssertEquals('first slot', '0', TyMaskNextSlot('00/00', 0));
  AssertEquals('third slot', '0', TyMaskNextSlot('00/00', 2));
  AssertEquals('full -> none', #0, TyMaskNextSlot('00/00', 4));
  { The optional half of each pair reports its own code, so a caller can tell the two
    apart -- that difference is the whole point of the lower-case codes. }
  AssertEquals('an optional digit is not a required one', '9', TyMaskNextSlot('90', 0));
  AssertEquals('and the required one follows it', '0', TyMaskNextSlot('90', 1));

  AssertTrue('digit accepts digit', TyMaskSlotAccepts('0', '5'));
  AssertFalse('digit rejects letter', TyMaskSlotAccepts('0', 'a'));
  AssertTrue('optional digit has the same range', TyMaskSlotAccepts('9', '5'));
  AssertTrue('letter accepts letter', TyMaskSlotAccepts('L', 'a'));
  AssertFalse('letter rejects digit', TyMaskSlotAccepts('L', '5'));
  AssertTrue('alphanumeric takes both', TyMaskSlotAccepts('A', '5'));
  AssertTrue('alphanumeric takes both, letters too', TyMaskSlotAccepts('A', 'z'));
  AssertFalse('alphanumeric rejects punctuation', TyMaskSlotAccepts('A', '-'));
  AssertTrue('hex takes f', TyMaskSlotAccepts('H', 'f'));
  AssertFalse('hex rejects g', TyMaskSlotAccepts('H', 'g'));
  AssertTrue('binary takes 1', TyMaskSlotAccepts('B', '1'));
  AssertFalse('binary rejects 2', TyMaskSlotAccepts('B', '2'));
  { LCL's C is "any character except the placeholder", so it must be given one to
    exclude; with none it excludes nothing. }
  AssertTrue('any takes punctuation', TyMaskSlotAccepts('C', '-'));
  AssertFalse('but never the placeholder', TyMaskSlotAccepts('C', '_', '_'));
  AssertFalse('a literal is not a slot code', TyMaskSlotAccepts('/', '/'));

  AssertTrue('complete', TyMaskIsComplete('00/00', '12/34'));
  AssertFalse('incomplete', TyMaskIsComplete('00/00', '12'));
end;

procedure TMaskEditTest.TestControlEntry;
{ Entry with the default placeholder in force, i.e. what a user actually sees: the whole
  skeleton from the start, filling in left to right. }
var m: TAccessMask;
begin
  m := TAccessMask.Create(nil);
  try
    m.Mask := '00/00/0000';
    AssertEquals('an empty field shows its shape', '__/__/____', m.Text);
    m.Key('1'); m.Key('2');
    AssertEquals('two digits', '12/__/____', m.Text);
    m.Key('a');   // wrong type -> rejected
    AssertEquals('letter rejected', '12/__/____', m.Text);
    m.Key('3'); m.Key('4');
    AssertEquals('auto separator', '12/34/____', m.Text);
    m.Key('5'); m.Key('6'); m.Key('7'); m.Key('8');
    AssertEquals('full', '12/34/5678', m.Text);
    AssertTrue('complete', m.IsComplete);
    m.Key('9');   // full -> rejected, no overflow
    AssertEquals('no overflow', '12/34/5678', m.Text);
  finally m.Free; end;
end;

procedure TMaskEditTest.TestSkeletonAndCaret;
{ The three things the skeleton has to get right, none of which follow from "emit the
  placeholder": the VALUE behind the display stays clean, backspace walks back through it,
  and the caret lands on the slot the next keystroke will fill -- not at the end of a
  display string that now runs on past it. }
var m: TAccessMask;
begin
  m := TAccessMask.Create(nil);
  try
    m.Mask := '00/00/0000';
    AssertEquals('nothing typed, nothing held', '', m.MaskedValue);
    AssertEquals('the caret waits on the first slot', 0, m.CaretPos);
    m.Key('1'); m.Key('2');
    AssertEquals('the value is the digits alone', '12', m.MaskedValue);
    { '12/__/____': the caret belongs at index 3, PAST the separator, on the next digit
      slot -- index 10 (the end of the display) would point at nothing typeable. }
    AssertEquals('the caret sits on the next editable slot', 3, m.CaretPos);
    m.InjectBackspace;
    AssertEquals('backspace walks back into the skeleton', '1_/__/____', m.Text);
    AssertEquals('and takes the value with it', '1', m.MaskedValue);
    AssertEquals('caret follows', 1, m.CaretPos);
  finally m.Free; end;
end;

procedure TMaskEditTest.TestSpaceCharChangesTheSkeleton;
var m: TAccessMask;
begin
  m := TAccessMask.Create(nil);
  try
    m.Mask := '00/00';
    m.Key('1');
    AssertEquals('the default placeholder', '1_/__', m.Text);
    m.SpaceChar := '*';
    AssertEquals('re-rendered under the new one', '1*/**', m.Text);
    AssertEquals('the value survived the change', '1', m.MaskedValue);
    m.SpaceChar := #0;
    AssertEquals('#0 turns the skeleton off entirely', '1', m.Text);
    AssertEquals('value unchanged again', '1', m.MaskedValue);
  finally m.Free; end;

  { A hole has to survive the swap WHERE IT IS. Re-deriving the display from the value --
    which is all the old placeholder-swap could do, because the old model had no holes --
    packs the survivors back to the left and silently moves the user's digits. }
  m := TAccessMask.Create(nil);
  try
    m.Mask := '00/00';
    m.Text := '12/34';
    m.CaretPos := 0;
    m.Press(VK_DELETE);
    AssertEquals('a hole at the front', '_2/34', m.Text);
    m.SpaceChar := '*';
    AssertEquals('the hole stayed where the user made it', '*2/34', m.Text);
  finally m.Free; end;
end;

procedure TMaskEditTest.TestValidateEdit;
{ ValidateEdit is the validation MOMENT the control did not have: without it a half-typed
  value left the field in silence and every caller had to remember to poll IsComplete. }
var
  m: TAccessMask;
  raised: Boolean;
begin
  m := TAccessMask.Create(nil);
  try
    m.Mask := '00/00';
    m.Key('1'); m.Key('2');
    raised := False;
    try m.ValidateEdit; except on ETyMaskError do raised := True; end;
    AssertTrue('a half-filled mask must not pass validation', raised);

    m.Key('3'); m.Key('4');
    raised := False;
    try m.ValidateEdit; except on ETyMaskError do raised := True; end;
    AssertFalse('a filled mask passes', raised);

    { An unmasked edit has nothing to validate against and must never raise. }
    m.Mask := '';
    m.Text := 'anything';
    raised := False;
    try m.ValidateEdit; except on ETyMaskError do raised := True; end;
    AssertFalse('no mask, no complaint', raised);
  finally m.Free; end;
end;

procedure TMaskEditTest.TestOptionalSlotsNeedNotBeFilled;
{ The lower-case codes are OPTIONAL, and that is the only thing that distinguishes them.
  A control that treated them as required would make every ported '99/99/00' unsubmittable;
  one that treated the upper-case codes as optional would make every required field pass
  validation while empty -- which is exactly why '#' is refused rather than reinterpreted. }
var
  m: TAccessMask;
  raised: Boolean;
begin
  AssertTrue('optional slots may all be blank', TyMaskIsComplete('999', '___', '_'));
  AssertFalse('required ones may not', TyMaskIsComplete('000', '___', '_'));
  AssertTrue('a required prefix filled, the optional tail blank',
    TyMaskIsComplete('00-99', '12-__', '_'));
  AssertFalse('but not the other way round',
    TyMaskIsComplete('00-99', '__-12', '_'));

  m := TAccessMask.Create(nil);
  try
    m.Mask := '00-99';
    m.Key('1'); m.Key('2');
    AssertEquals('the required pair is in', '12-__', m.Text);
    AssertTrue('and the optional tail does not hold it back', m.IsComplete);
    raised := False;
    try m.ValidateEdit; except on ETyMaskError do raised := True; end;
    AssertFalse('so validation passes', raised);
    m.Key('3');
    AssertEquals('the optional slot still accepts input', '12-3_', m.Text);
    AssertEquals('and it is part of the value', '123', m.MaskedValue);
  finally m.Free; end;
end;

procedure TMaskEditTest.TestCaseForcingRegions;
{ '>' and '<' are regions, not one-shot prefixes, and '<>' ends one. The character is
  CONVERTED and then range-checked (LCL's CanInsertChar), so a lower-case letter typed
  into a '>' region is accepted as upper case rather than rejected. }
var m: TAccessMask;
begin
  m := TAccessMask.Create(nil);
  try
    m.Mask := '>LL<LL';
    m.Key('a'); m.Key('b'); m.Key('C'); m.Key('D');
    AssertEquals('upper region then lower region', 'ABcd', m.Text);
    AssertEquals('the value carries the forced case', 'ABcd', m.MaskedValue);
  finally m.Free; end;

  m := TAccessMask.Create(nil);
  try
    m.Mask := '<LL<>LL';
    m.Key('A'); m.Key('B'); m.Key('C'); m.Key('d');
    AssertEquals('<> ends the region, the rest is as typed', 'abCd', m.Text);
  finally m.Free; end;
end;

procedure TMaskEditTest.TestEscapeMakesTheNextCharALiteral;
{ Without '\' there is no way to write a literal that happens to be a slot code, and
  every one of the twelve codes is an ordinary character somebody wants in a mask. }
var m: TAccessMask;
begin
  AssertEquals('the escape itself takes no display position', 2, TyMaskCellCount('\00'));
  AssertTrue('the escaped code became a literal', TyMaskIsLiteralAt('\00', 1));
  AssertFalse('and the bare one did not', TyMaskIsLiteralAt('\00', 2));
  m := TAccessMask.Create(nil);
  try
    m.Mask := '\0\0-00';
    AssertEquals('the escaped pair is drawn, not editable', '00-__', m.Text);
    m.Key('1'); m.Key('2');
    AssertEquals('input lands only in the real slots', '00-12', m.Text);
    AssertEquals('and the literals are not part of the value', '12', m.MaskedValue);
  finally m.Free; end;

  { '\#' is the documented way to keep a literal '#', and the only one -- a bare '#'
    is refused. }
  m := TAccessMask.Create(nil);
  try
    m.Mask := '\#000';
    AssertEquals('a literal hash', '#___', m.Text);
    m.Key('7');
    AssertEquals('typed past it', '#7__', m.Text);
  finally m.Free; end;
end;

procedure TMaskEditTest.TestReadOnlyMaskedFieldTakesNoDictation;
{ TTyEdit reaches ReadOnly (and Enabled) through InjectKey; this control's UTF8KeyPress
  overrides the whole path and never called it, so a read-only masked field accepted
  every keystroke -- the one control on which ReadOnly meant nothing. }
var m: TAccessMask;
begin
  m := TAccessMask.Create(nil);
  try
    m.Mask := '00/00';
    m.ReadOnly := True;
    m.Key('1'); m.Key('2');
    AssertEquals('a read-only mask edit is not a notepad', '__/__', m.Text);
    m.ReadOnly := False;
    m.Key('1');
    AssertEquals('and it still works when it is not read-only', '1_/__', m.Text);
  finally m.Free; end;
end;

procedure TMaskEditTest.TestTypingOverwritesTheSlotUnderTheCaret;
{ The append-only model could only ever add to the end: putting the caret in the middle of
  '12/34/5678' and typing appended past the eighth digit or did nothing at all, so
  correcting the month of a date meant deleting the year first. }
var m: TAccessMask;
begin
  m := TAccessMask.Create(nil);
  try
    m.Mask := '00/00/0000';
    m.Text := '12/34/5678';
    m.CaretPos := 3;              // on the first digit of the middle pair
    m.Key('9');
    AssertEquals('the slot under the caret is overwritten', '12/94/5678', m.Text);
    AssertEquals('the caret moved on by one slot', 4, m.CaretPos);
    m.Key('9');
    AssertEquals('and again', '12/99/5678', m.Text);
    { Past the last slot of a group the caret steps over the literal by itself. }
    AssertEquals('the caret skipped the separator', 6, m.CaretPos);
    m.Key('0');
    AssertEquals('landing in the year', '12/99/0678', m.Text);

    { A character the slot refuses changes nothing and moves nothing. }
    m.CaretPos := 0;
    m.Key('x');
    AssertEquals('a refused character leaves the slot alone', '12/99/0678', m.Text);
    AssertEquals('and the caret with it', 0, m.CaretPos);
  finally m.Free; end;
end;

procedure TMaskEditTest.TestBackspaceTakesTheSlotBeforeAndDeleteTheSlotAt;
{ The two keys stopped meaning the same thing the moment the caret could sit in the
  middle: Backspace clears what is BEHIND the caret, Delete what is UNDER it. While entry
  was append-only both could only mean "drop the last character" -- and the code said so. }
var m: TAccessMask;
begin
  m := TAccessMask.Create(nil);
  try
    m.Mask := '00/00';
    m.Text := '12/34';
    m.CaretPos := 4;
    m.Press(VK_BACK);
    AssertEquals('backspace took the slot before the caret', '12/_4', m.Text);
    AssertEquals('and the caret moved onto it', 3, m.CaretPos);

    m.Text := '12/34';
    m.CaretPos := 3;
    m.Press(VK_DELETE);
    AssertEquals('delete took the slot at the caret', '12/_4', m.Text);
    AssertEquals('and the caret stayed on it', 3, m.CaretPos);

    { Backspace at the very front has nothing behind it and must not touch a literal. }
    m.Text := '12/34';
    m.CaretPos := 0;
    m.Press(VK_BACK);
    AssertEquals('nothing behind the first slot', '12/34', m.Text);

    { Backspace stepping over a separator lands on the slot before it, never on the
      separator itself. }
    m.Text := '12/34';
    m.CaretPos := 3;
    m.Press(VK_BACK);
    AssertEquals('the separator is stepped over, not erased', '1_/34', m.Text);
    AssertEquals('caret on the slot it cleared', 1, m.CaretPos);
  finally m.Free; end;
end;

procedure TMaskEditTest.TestASlotCanBeEmptiedInTheMiddle;
{ A hole is a state the append-only model could not represent at all, and the one every
  helper had to learn: the value skips it, completeness fails on it, and re-assigning the
  display string keeps it rather than packing the survivors to the left. }
var m: TAccessMask;
begin
  m := TAccessMask.Create(nil);
  try
    m.Mask := '00/00';
    m.Text := '12/34';
    m.CaretPos := 0;
    m.Press(VK_DELETE);
    AssertEquals('a hole at the front', '_2/34', m.Text);
    AssertEquals('the value skips it', '234', m.MaskedValue);
    AssertFalse('and a holed mask is not complete', m.IsComplete);
    m.Text := m.Text;
    AssertEquals('re-assigning the display keeps the hole where it is', '_2/34', m.Text);
    m.CaretPos := 0;
    m.Key('9');
    AssertEquals('and it can be filled back in', '92/34', m.Text);
    AssertTrue('complete again', m.IsComplete);
  finally m.Free; end;
end;

procedure TMaskEditTest.TestPasteLandsAtTheCaret;
var m: TAccessMask;
begin
  m := TAccessMask.Create(nil);
  try
    m.Mask := '0000-00-00';
    m.CaretPos := 5;
    m.Clip := '0730';
    m.PressWith(VK_V, [ssCtrl]);
    AssertEquals('the paste started at the caret, not at slot one', '____-07-30', m.Text);

    { And the literals in a pasted value are dropped, not matched: the mask puts its own
      back. }
    m.Text := '';
    m.Clip := '2026/07/30';
    m.PressWith(VK_V, [ssCtrl]);
    AssertEquals('slashes dropped, dashes rebuilt', '2026-07-30', m.Text);
    AssertTrue('complete', m.IsComplete);

    { A read-only field takes no paste either. }
    m.Text := '';
    m.ReadOnly := True;
    m.Clip := '20260730';
    m.PressWith(VK_V, [ssCtrl]);
    AssertEquals('read-only refuses a paste', '____-__-__', m.Text);
  finally m.Free; end;
end;

procedure TMaskEditTest.TestTypingOverASelectionClearsIt;
{ TTyEdit answers a keystroke over a selection by splicing the selected characters OUT of
  the string -- which, on a fixed-width skeleton, slides every character after the cut into
  a cell that means something else. The mask has to clear those slots in place instead. }
var m: TAccessMask;
begin
  m := TAccessMask.Create(nil);
  try
    m.Mask := '00/00/0000';
    m.Text := '12/34/5678';
    m.SelStart := 3;
    m.SelLength := 2;             // the middle pair
    m.Key('7');
    AssertEquals('the selection was blanked and the key landed in its first slot',
      '12/7_/5678', m.Text);
    AssertEquals('display length is fixed no matter what', 10, Length(m.Text));

    { Even when the key is refused, the selection it was meant to replace is gone --
      LCL does the same (maskedit.pp InsertChar). }
    m.Text := '12/34/5678';
    m.SelStart := 3;
    m.SelLength := 2;
    m.Key('z');
    AssertEquals('a refused key still clears what it was replacing', '12/__/5678', m.Text);
    AssertEquals('and the length still holds', 10, Length(m.Text));
  finally m.Free; end;
end;

procedure TMaskEditTest.TestCutClearsTheSelectedSlotsInPlace;
{ Cut is the other TTyEdit routine that SPLICES: CutToClipboard removes the selected
  characters from the string, which on a fixed-width skeleton shortens the display and
  slides everything after the cut into a cell that means something else. Neither it nor
  DeleteSelection is virtual, so the mask has to catch the shortcut at the key. }
var m: TAccessMask;
begin
  m := TAccessMask.Create(nil);
  try
    m.Mask := '00/00/0000';
    m.Text := '12/34/5678';
    m.SelStart := 3;
    m.SelLength := 2;
    m.PressWith(VK_X, [ssCtrl]);
    AssertEquals('the cut text still reached the clipboard', '34', m.Clip);
    AssertEquals('and the slots it came from were blanked, not spliced out',
      '12/__/5678', m.Text);
    AssertEquals('the display is still exactly the mask', 10, Length(m.Text));
  finally m.Free; end;
end;

procedure TMaskEditTest.TestShortFormKeepsItsOwnPastePath;
{ SpaceChar := #0 draws no placeholder, so there is no full-length display string for the
  positional paths to start from. Normalising one anyway writes the blank character -- #0 --
  into every unfilled slot, which is a NUL in the middle of Text: a string that prints as
  the right prefix, compares equal to nothing, and truncates the moment it reaches an API
  that takes a PChar. The keyboard shortcuts have to stay out of the way in that mode. }
var m: TAccessMask;
begin
  m := TAccessMask.Create(nil);
  try
    m.Mask := '00/00';
    m.SpaceChar := #0;
    m.Key('1'); m.Key('2');
    AssertEquals('append-only entry, short display', '12', m.Text);
    m.Clip := '34';
    m.PressWith(VK_V, [ssCtrl]);
    AssertEquals('paste still appends through the mask', '12/34', m.Text);
    AssertEquals('and no NUL was written into the display', 0, Pos(#0, m.Text));
  finally m.Free; end;
end;

initialization
  RegisterTest(TMaskEditTest);
end.
