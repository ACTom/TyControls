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
  AssertEquals('full date', '12/34/5678', TyMaskApply('##/##/####', '12345678'));
  AssertEquals('partial no trailing sep', '12', TyMaskApply('##/##/####', '12'));
  AssertEquals('partial through sep', '12/3', TyMaskApply('##/##/####', '123'));
  AssertEquals('phone literals', '(123) 456-7890', TyMaskApply('(###) ###-####', '1234567890'));
  AssertEquals('leading literal', '(1', TyMaskApply('(###)', '1'));
end;

procedure TMaskEditTest.TestExtractRoundTrip;
begin
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
var m: TAccessMask;
begin
  m := TAccessMask.Create(nil);
  try
    m.Mask := '##/##/####';
    m.Key('1'); m.Key('2');
    AssertEquals('two digits', '12', m.Text);
    m.Key('a');   // wrong type -> rejected
    AssertEquals('letter rejected', '12', m.Text);
    m.Key('3'); m.Key('4');
    AssertEquals('auto separator', '12/34', m.Text);
    m.Key('5'); m.Key('6'); m.Key('7'); m.Key('8');
    AssertEquals('full', '12/34/5678', m.Text);
    AssertTrue('complete', m.IsComplete);
    m.Key('9');   // full -> rejected, no overflow
    AssertEquals('no overflow', '12/34/5678', m.Text);
  finally m.Free; end;
end;

initialization
  RegisterTest(TMaskEditTest);
end.
