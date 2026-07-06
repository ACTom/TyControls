unit test.currencyedit;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.CurrencyEdit;
type
  TCurrencyEditTest = class(TTestCase)
  published
    procedure TestSymbol;
  end;
implementation

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

initialization
  RegisterTest(TCurrencyEditTest);
end.
