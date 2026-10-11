unit test.currencyedit;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Forms, fpcunit, testregistry, tyControls.NumericEdit,
  tyControls.CurrencyEdit;
type
  TCurrencyEditTest = class(TTestCase)
  published
    procedure TestSymbol;
    procedure TestASymbolWithADotKeepsTheValue;
    procedure TestASymbolWithADigitAddsNothingToTheNumber;
    procedure TestFocusingTheFieldKeepsTheValue;
    procedure TestChangingTheSymbolKeepsTheValue;
    procedure TestAFormFileWithSuchASymbolReadsBack;
    procedure TestReadingAFormStillClampsTheValue;
  end;

  { DoEnter / DoExit are what focusing and leaving the field run; reachable without a window. }
  TCurrencyFocusProbe = class(TTyCurrencyEdit)
  public
    procedure Enter;
    procedure Leave;
  end;
implementation

procedure TCurrencyFocusProbe.Enter;
begin
  DoEnter;
end;

procedure TCurrencyFocusProbe.Leave;
begin
  DoExit;
end;

function CurFromText(const AText: string): TForm;
var ts: TStringStream; bs: TMemoryStream;
begin
  Result := TForm.CreateNew(nil);
  ts := TStringStream.Create(AText);
  bs := TMemoryStream.Create;
  try
    ObjectTextToBinary(ts, bs);
    bs.Position := 0;
    bs.ReadComponent(Result);
  finally
    bs.Free;
    ts.Free;
  end;
end;

procedure TCurrencyEditTest.TestSymbol;
var c: TTyCurrencyEdit;
begin
  c := TTyCurrencyEdit.Create(nil);
  try
    AssertEquals('default prefix', '$0.00', c.Text);
    c.Value := 1234.5;
    AssertEquals('symbol + grouped', '$1,234.50', c.Text);
    AssertEquals('value drops symbol', 1234.5, c.Value, 1e-9);
    c.SymbolBefore := False;
    AssertEquals('suffix', '1,234.50$', c.Text);
    c.CurrencySymbol := 'USD';
    AssertEquals('new suffix symbol', '1,234.50USD', c.Text);
    AssertEquals('value still clean', 1234.5, c.Value, 1e-9);
  finally c.Free; end;
end;

{ A symbol with a dot in it -- 'Fr.', 'kr.' -- used to read back 0 once the field had lost focus:
  the parser kept the dot and saw '.1234.50'. Both sides. }
procedure TCurrencyEditTest.TestASymbolWithADotKeepsTheValue;
var c: TTyCurrencyEdit;
begin
  c := TTyCurrencyEdit.Create(nil);
  try
    c.CurrencySymbol := 'Fr.';
    c.Value := 1234.5;
    AssertEquals('setup: the symbol leads', 'Fr.1,234.50', c.Text);
    AssertEquals('the value reads back from the display', 1234.5, c.Value, 1e-9);
    c.SymbolBefore := False;
    AssertEquals('setup: the symbol trails', '1,234.50Fr.', c.Text);
    AssertEquals('and reads back trailing too', 1234.5, c.Value, 1e-9);
  finally c.Free; end;
end;

{ Worse than 0: a digit in the symbol joined the number, so the value read wrong and looked fine. }
procedure TCurrencyEditTest.TestASymbolWithADigitAddsNothingToTheNumber;
var c: TTyCurrencyEdit;
begin
  c := TTyCurrencyEdit.Create(nil);
  try
    c.CurrencySymbol := 'US$1';
    c.Value := 1234.5;
    AssertEquals('setup', 'US$11,234.50', c.Text);
    AssertEquals('the 1 of the symbol is not a digit of the value', 1234.5, c.Value, 1e-9);
  finally c.Free; end;
end;

{ Focusing re-displays the raw number from the value, and that read is what turned the value
  into 0 for good. }
procedure TCurrencyEditTest.TestFocusingTheFieldKeepsTheValue;
var c: TCurrencyFocusProbe;
begin
  c := TCurrencyFocusProbe.Create(nil);
  try
    c.CurrencySymbol := 'kr.';
    c.SymbolBefore := False;
    c.Value := 1234.5;
    c.Enter;
    AssertEquals('focused: the raw number to edit', '1234.50', c.Text);
    c.Leave;
    AssertEquals('left: grouped and decorated again', '1,234.50kr.', c.Text);
    AssertEquals('the value survived the round trip', 1234.5, c.Value, 1e-9);
  finally c.Free; end;
end;

procedure TCurrencyEditTest.TestChangingTheSymbolKeepsTheValue;
var c: TTyCurrencyEdit;
begin
  c := TTyCurrencyEdit.Create(nil);
  try
    c.CurrencySymbol := 'Fr.';
    c.Value := 1234.5;
    c.CurrencySymbol := 'kr.';   // the text still carried 'Fr.' when the new symbol arrived
    AssertEquals('a new symbol', 'kr.1,234.50', c.Text);
    AssertEquals('over the same value', 1234.5, c.Value, 1e-9);
    c.SymbolBefore := False;
    AssertEquals('moved behind', '1,234.50kr.', c.Text);
    AssertEquals('still the same value', 1234.5, c.Value, 1e-9);
  finally c.Free; end;
end;

{ A form file writes Text before the properties that shape it, so it is read before them: parsed
  then, 'Fr.1,234.500' met the default '$' and three decimals not yet set, and came back 0. }
procedure TCurrencyEditTest.TestAFormFileWithSuchASymbolReadsBack;
const
  LFM =
    'object Form1: TForm' + LineEnding +
    '  object C: TTyCurrencyEdit' + LineEnding +
    '    Text = ''Fr.1,234.500''' + LineEnding +
    '    Decimals = 3' + LineEnding +
    '    CurrencySymbol = ''Fr.''' + LineEnding +
    '  end' + LineEnding +
    'end' + LineEnding;
var f: TForm; c: TTyCurrencyEdit;
begin
  f := CurFromText(LFM);
  try
    c := f.FindComponent('C') as TTyCurrencyEdit;
    AssertEquals('the value the form was saved with', 1234.5, c.Value, 1e-9);
    AssertEquals('shown as it was saved', 'Fr.1,234.500', c.Text);
  finally f.Free; end;
end;

{ Reading a form displays once, after every property arrived -- and that display still clamps,
  as the setters' own reformat did before it waited for Loaded. }
procedure TCurrencyEditTest.TestReadingAFormStillClampsTheValue;
const
  LFM =
    'object Form1: TForm' + LineEnding +
    '  object N: TTyNumericEdit' + LineEnding +
    '    Text = ''5.00''' + LineEnding +
    '    MinValue = 10' + LineEnding +
    '    MaxValue = 20' + LineEnding +
    '  end' + LineEnding +
    'end' + LineEnding;
var f: TForm; n: TTyNumericEdit;
begin
  f := CurFromText(LFM);
  try
    n := f.FindComponent('N') as TTyNumericEdit;
    AssertEquals('the read text is clamped into range', '10.00', n.Text);
  finally f.Free; end;
end;

initialization
  RegisterTest(TCurrencyEditTest);
end.
