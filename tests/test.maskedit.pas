unit test.maskedit;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, LCLType, fpcunit, testregistry, tyControls.MaskEdit;
type
  { Exposes the protected UTF8KeyPress so the masked entry can be driven headlessly
    (InjectKey bypasses UTF8KeyPress, so it can't exercise the mask filter). }
  TAccessMask = class(TTyMaskEdit)
  public
    procedure Key(c: Char);
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
  end;

implementation

procedure TAccessMask.Key(c: Char);
var k: TUTF8Char;
begin
  k := c;
  UTF8KeyPress(k);
end;

procedure TMaskEditTest.TestApply;
begin
  { Skeleton form (ABlank <> #0): the whole mask always, placeholders where the input ran
    out -- including trailing literals the short form deliberately drops. }
  AssertEquals('empty skeleton', '__/__/____', TyMaskApply('##/##/####', '', '_'));
  AssertEquals('half-typed skeleton', '12/__/____', TyMaskApply('##/##/####', '12', '_'));
  AssertEquals('a trailing literal belongs to the skeleton', '(1__)',
    TyMaskApply('(###)', '1', '_'));
  AssertEquals('a full value is the same either way', '12/34',
    TyMaskApply('##/##', '1234', '_'));
  { Short form (still the default of the unit function) is untouched. }
  AssertEquals('full date', '12/34/5678', TyMaskApply('##/##/####', '12345678'));
  AssertEquals('partial no trailing sep', '12', TyMaskApply('##/##/####', '12'));
  AssertEquals('partial through sep', '12/3', TyMaskApply('##/##/####', '123'));
  AssertEquals('phone literals', '(123) 456-7890', TyMaskApply('(###) ###-####', '1234567890'));
  AssertEquals('leading literal', '(1', TyMaskApply('(###)', '1'));
end;

procedure TMaskEditTest.TestExtractRoundTrip;
begin
  { A placeholder is the END of the input, never a character of it -- otherwise the skeleton
    reads back as content and an untouched field reports itself full. }
  AssertEquals('blanks are not content', '12',
    TyMaskExtract('##/##/####', '12/__/____', '_'));
  AssertEquals('an empty skeleton holds nothing', '',
    TyMaskExtract('##/##/####', '__/__/____', '_'));
  AssertFalse('and is not complete', TyMaskIsComplete('##/##', '__/__', '_'));
  AssertTrue('a filled one is', TyMaskIsComplete('##/##', '12/34', '_'));
  AssertEquals('extract full', '12345678', TyMaskExtract('##/##/####', '12/34/5678'));
  AssertEquals('extract partial', '123', TyMaskExtract('##/##/####', '12/3'));
  // round-trip: extract(apply(raw)) = raw
  AssertEquals('roundtrip', '1234567890',
    TyMaskExtract('(###) ###-####', TyMaskApply('(###) ###-####', '1234567890')));
end;

procedure TMaskEditTest.TestSlots;
begin
  AssertEquals('first slot', '#', TyMaskNextSlot('##/##', 0));
  AssertEquals('third slot', '#', TyMaskNextSlot('##/##', 2));
  AssertEquals('full -> none', #0, TyMaskNextSlot('##/##', 4));
  AssertTrue('digit accepts digit', TyMaskSlotAccepts('#', '5'));
  AssertFalse('digit rejects letter', TyMaskSlotAccepts('#', 'a'));
  AssertTrue('letter accepts letter', TyMaskSlotAccepts('L', 'a'));
  AssertFalse('letter rejects digit', TyMaskSlotAccepts('L', '5'));
  AssertTrue('complete', TyMaskIsComplete('##/##', '12/34'));
  AssertFalse('incomplete', TyMaskIsComplete('##/##', '12'));
end;

procedure TMaskEditTest.TestControlEntry;
{ Entry with the default placeholder in force, i.e. what a user actually sees: the whole
  skeleton from the start, filling in left to right. (This test used to read the display as
  '12' after two keystrokes -- it was pinning the fact that the field showed nothing at all
  until something had been typed into it.) }
var m: TAccessMask;
begin
  m := TAccessMask.Create(nil);
  try
    m.Mask := '##/##/####';
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
    m.Mask := '##/##/####';
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
    m.Mask := '##/##';
    m.Key('1');
    AssertEquals('the default placeholder', '1_/__', m.Text);
    m.SpaceChar := '*';
    AssertEquals('re-rendered under the new one', '1*/**', m.Text);
    AssertEquals('the value survived the change', '1', m.MaskedValue);
    m.SpaceChar := #0;
    AssertEquals('#0 turns the skeleton off entirely', '1', m.Text);
    AssertEquals('value unchanged again', '1', m.MaskedValue);
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
    m.Mask := '##/##';
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

initialization
  RegisterTest(TMaskEditTest);
end.
