unit test.numericedit;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.NumericEdit;
type
  TNumericEditTest = class(TTestCase)
  published
    procedure TestFormat;
    procedure TestParse;
    procedure TestControl;
  end;
implementation

procedure TNumericEditTest.TestFormat;
begin
  AssertEquals('grouped', '1,234.50', TyFormatNumber(1234.5, 2, ',', '.', True));
  AssertEquals('ungrouped', '1234.50', TyFormatNumber(1234.5, 2, ',', '.', False));
  AssertEquals('negative', '-1,234.50', TyFormatNumber(-1234.5, 2, ',', '.', True));
  AssertEquals('zero', '0.00', TyFormatNumber(0, 2, ',', '.', True));
  AssertEquals('int millions', '1,234,567', TyFormatNumber(1234567, 0, ',', '.', True));
  AssertEquals('euro separators', '1.234,50', TyFormatNumber(1234.5, 2, '.', ',', True));
end;

procedure TNumericEditTest.TestParse;
var d: Double;
begin
  AssertTrue('parses grouped', TyParseNumber('1,234.50', ',', '.', d));
  AssertEquals('grouped value', 1234.5, d, 1e-9);
  AssertTrue('parses negative', TyParseNumber('-1,234.50', ',', '.', d));
  AssertEquals('negative value', -1234.5, d, 1e-9);
  AssertFalse('rejects non-number', TyParseNumber('abc', ',', '.', d));
  AssertEquals('failed -> 0', 0.0, d, 1e-9);
  AssertTrue('parses euro', TyParseNumber('1.234,50', '.', ',', d));   // thousands '.', decimal ','
  AssertEquals('euro value', 1234.5, d, 1e-9);
end;

procedure TNumericEditTest.TestControl;
var c: TTyNumericEdit;
begin
  c := TTyNumericEdit.Create(nil);
  try
    AssertEquals('default text', '0.00', c.Text);
    AssertEquals('default value', 0.0, c.Value, 1e-9);
    c.Value := 1234.5;
    AssertEquals('grouped display', '1,234.50', c.Text);
    AssertEquals('value roundtrip', 1234.5, c.Value, 1e-9);
    c.MaxValue := 100;   // enables clamping (Max > Min)
    c.Value := 500;
    AssertEquals('clamped to max', 100.0, c.Value, 1e-9);
  finally c.Free; end;
end;

initialization
  RegisterTest(TNumericEditTest);
end.
