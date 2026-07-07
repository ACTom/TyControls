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
    procedure TestPrecedence;
    procedure TestExpressionShown;
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
    procedure TestEvalRejectsMalformed;
    procedure TestNegateOnEResult;
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

procedure TCalculatorTest.TestPrecedence;
var c: TTyCalculator;
begin
  // Operator precedence: 2 + 3 * 4 = 2 + 12 = 14 (× before +), NOT left-to-right 20.
  c := TTyCalculator.Create(nil);
  try
    Press(c, '2+3*4=');
    AssertEquals('precedence', 14.0, c.Value, 1e-9);
    AssertEquals('display', '14', c.Display);
  finally c.Free; end;
end;

procedure TCalculatorTest.TestExpressionShown;
var c: TTyCalculator;
begin
  // The full expression is shown for proof-reading; the bottom line live-previews the value.
  c := TTyCalculator.Create(nil);
  try
    Press(c, '333*222');
    AssertEquals('expression shown', '333*222', c.Expression);
    AssertEquals('current entry on the big line', '222', c.Display);
    AssertEquals('value = full expression result', 73926.0, c.Value, 1e-9);
    Press(c, '=');
    AssertEquals('result', '73926', c.Display);
    AssertEquals('value', 73926.0, c.Value, 1e-9);
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

procedure TCalculatorTest.TestEvalRejectsMalformed;
var r: Double;
begin
  // TyEvalExpr must reject digit-less / incomplete tokens (StrToFloatDef tolerates some of them).
  AssertFalse('incomplete exponent 1e+', TyEvalExpr('1e+', r));
  AssertFalse('lone dot', TyEvalExpr('.', r));
  AssertFalse('digit-less operand 9*.', TyEvalExpr('9*.', r));
  AssertFalse('trailing operator 5+', TyEvalExpr('5+', r));
  AssertTrue('precedence still ok', TyEvalExpr('2+3*4', r));
  AssertEquals('=14', 14.0, r, 1e-9);
  AssertTrue('sci-notation ok', TyEvalExpr('1E3', r));
  AssertEquals('1E3 = 1000', 1000.0, r, 1e-9);
end;

procedure TCalculatorTest.TestNegateOnEResult;
var c: TTyCalculator;
begin
  // A result formatted in E-notation ('1E-7') must negate as a WHOLE number, not corrupt the
  // exponent (the old TrailingNumberStart mistook '-7' for the entry and made '1E--7').
  c := TTyCalculator.Create(nil);
  try
    c.Value := 1e-7;
    c.PressKey('N');
    AssertEquals('negated E-result', -1e-7, c.Value, 1e-13);
  finally c.Free; end;
end;

initialization
  RegisterTest(TCalculatorTest);
end.
