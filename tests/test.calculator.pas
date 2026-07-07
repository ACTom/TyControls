unit test.calculator;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry,
  tyControls.Calculator;
type
  TCalculatorTest = class(TTestCase)
  private
    procedure Press(c: TTyCalculator; const AKeys: string);
  published
    procedure TestAddition;
    procedure TestChainIsLeftToRight;
    procedure TestSubtractMultiplyDivide;
    procedure TestDivideByZeroError;
    procedure TestErrorIsSticky;
    procedure TestDivZeroMidChainStaysError;
    procedure TestOverflowIsError;
    procedure TestDecimal;
    procedure TestClear;
    procedure TestClearEntryKeepsPendingOp;
    procedure TestBackspace;
    procedure TestNegate;
    procedure TestSetValueThenContinue;
    procedure TestOpAfterEqualsUsesResult;
  end;
implementation

procedure TCalculatorTest.Press(c: TTyCalculator; const AKeys: string);
var i: Integer;
begin
  for i := 1 to Length(AKeys) do
    c.PressKey(AKeys[i]);
end;

procedure TCalculatorTest.TestAddition;
var c: TTyCalculator;
begin
  c := TTyCalculator.Create(nil);
  try
    Press(c, '12+3=');
    AssertEquals('display', '15', c.Display);
    AssertEquals('value', 15.0, c.Value, 1e-9);
  finally c.Free; end;
end;

procedure TCalculatorTest.TestChainIsLeftToRight;
var c: TTyCalculator;
begin
  // No operator precedence: 2 + 3 * 4 evaluates left-to-right = (2+3)*4 = 20.
  c := TTyCalculator.Create(nil);
  try
    Press(c, '2+3*4=');
    AssertEquals('left-to-right', 20.0, c.Value, 1e-9);
  finally c.Free; end;
end;

procedure TCalculatorTest.TestSubtractMultiplyDivide;
var c: TTyCalculator;
begin
  c := TTyCalculator.Create(nil);
  try
    Press(c, '20-5=');  AssertEquals('sub', 15.0, c.Value, 1e-9);
    c.Clear;
    Press(c, '6*7=');   AssertEquals('mul', 42.0, c.Value, 1e-9);
    c.Clear;
    Press(c, '84/4=');  AssertEquals('div', 21.0, c.Value, 1e-9);
  finally c.Free; end;
end;

procedure TCalculatorTest.TestDivideByZeroError;
var c: TTyCalculator;
begin
  c := TTyCalculator.Create(nil);
  try
    Press(c, '5/0=');
    AssertEquals('error display', 'Error', c.Display);
    AssertEquals('error value is 0', 0.0, c.Value, 1e-9);
  finally c.Free; end;
end;

procedure TCalculatorTest.TestErrorIsSticky;
var c: TTyCalculator;
begin
  c := TTyCalculator.Create(nil);
  try
    Press(c, '5/0=');
    Press(c, '7');       // sticky: digits are ignored until an explicit clear
    AssertEquals('still Error', 'Error', c.Display);
    c.PressKey('C');     // clear leaves the error state
    Press(c, '7');
    AssertEquals('recovered after clear', '7', c.Display);
    AssertEquals('value', 7.0, c.Value, 1e-9);
  finally c.Free; end;
end;

procedure TCalculatorTest.TestDivZeroMidChainStaysError;
var c: TTyCalculator;
begin
  // A divide-by-zero in the middle of a chain must NOT silently vanish into a bogus result.
  c := TTyCalculator.Create(nil);
  try
    Press(c, '5/0*2=');
    AssertEquals('stays Error, not 2', 'Error', c.Display);
  finally c.Free; end;
end;

procedure TCalculatorTest.TestOverflowIsError;
var c: TTyCalculator;
begin
  c := TTyCalculator.Create(nil);
  try
    c.Value := 1e308;
    Press(c, '*9=');     // 1e308 * 9 overflows -> Error (no crash, no +Inf)
    AssertEquals('overflow -> Error', 'Error', c.Display);
    AssertEquals('value 0 in error', 0.0, c.Value, 1e-9);
  finally c.Free; end;
end;

procedure TCalculatorTest.TestDecimal;
var c: TTyCalculator;
begin
  c := TTyCalculator.Create(nil);
  try
    Press(c, '1.5+2.5=');
    AssertEquals('value', 4.0, c.Value, 1e-9);
    // second '.' in the same entry is ignored
    c.Clear; Press(c, '1..5');
    AssertEquals('single dot', '1.5', c.Display);
  finally c.Free; end;
end;

procedure TCalculatorTest.TestClear;
var c: TTyCalculator;
begin
  c := TTyCalculator.Create(nil);
  try
    Press(c, '99+1');
    c.PressKey('C');
    AssertEquals('display 0', '0', c.Display);
    AssertEquals('value 0', 0.0, c.Value, 1e-9);
    Press(c, '3+4=');   // fully usable after clear
    AssertEquals('after clear', 7.0, c.Value, 1e-9);
  finally c.Free; end;
end;

procedure TCalculatorTest.TestClearEntryKeepsPendingOp;
var c: TTyCalculator;
begin
  c := TTyCalculator.Create(nil);
  try
    Press(c, '12+34');
    c.PressKey('E');    // clear ENTRY -> display 0, but 12 + is kept
    AssertEquals('entry cleared', '0', c.Display);
    Press(c, '5=');
    AssertEquals('12 + 5', 17.0, c.Value, 1e-9);
  finally c.Free; end;
end;

procedure TCalculatorTest.TestBackspace;
var c: TTyCalculator;
begin
  c := TTyCalculator.Create(nil);
  try
    Press(c, '123');
    c.PressKey('B');
    AssertEquals('one deleted', '12', c.Display);
    c.PressKey('B'); c.PressKey('B');
    AssertEquals('down to 0', '0', c.Display);
  finally c.Free; end;
end;

procedure TCalculatorTest.TestNegate;
var c: TTyCalculator;
begin
  c := TTyCalculator.Create(nil);
  try
    Press(c, '5');
    c.PressKey('N');
    AssertEquals('negated', '-5', c.Display);
    AssertEquals('value', -5.0, c.Value, 1e-9);
    c.PressKey('N');
    AssertEquals('un-negated', '5', c.Display);
  finally c.Free; end;
end;

procedure TCalculatorTest.TestSetValueThenContinue;
var c: TTyCalculator;
begin
  c := TTyCalculator.Create(nil);
  try
    c.Value := 3.25;
    AssertEquals('seeded display', '3.25', c.Display);
    Press(c, '+1=');
    AssertEquals('continues from seeded value', 4.25, c.Value, 1e-9);
  finally c.Free; end;
end;

procedure TCalculatorTest.TestOpAfterEqualsUsesResult;
var c: TTyCalculator;
begin
  c := TTyCalculator.Create(nil);
  try
    Press(c, '2+3=');       // 5
    Press(c, '*4=');        // 5 * 4 = 20 (op right after '=' continues from the result)
    AssertEquals('continues from result', 20.0, c.Value, 1e-9);
  finally c.Free; end;
end;

initialization
  RegisterTest(TCalculatorTest);
end.
