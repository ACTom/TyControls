unit test.calcedit;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry,
  tyControls.NumericEdit, tyControls.CurrencyEdit,
  tyControls.CalcEdit, tyControls.CalcCurrencyEdit;
type
  { Access subclasses to reach the protected RightReserve. }
  TCalcEditAccess = class(TTyCalcEdit)
  public function Reserve: Integer;
  end;
  TCalcCurrAccess = class(TTyCalcCurrencyEdit)
  public function Reserve: Integer;
  end;

  TCalcEditTest = class(TTestCase)
  published
    procedure TestCalcEditIsNumeric;
    procedure TestCalcEditReservesButton;
    procedure TestCalcCurrencyIsCurrency;
    procedure TestCalcCurrencyReservesButton;
  end;
implementation

function TCalcEditAccess.Reserve: Integer;
begin
  Result := RightReserve(96);
end;

function TCalcCurrAccess.Reserve: Integer;
begin
  Result := RightReserve(96);
end;

procedure TCalcEditTest.TestCalcEditIsNumeric;
var e: TTyCalcEdit;
begin
  e := TTyCalcEdit.Create(nil);
  try
    AssertTrue('is a numeric edit', e is TTyNumericEdit);
    e.Value := 42.5;
    AssertEquals('value round-trips', 42.5, e.Value, 1e-9);
  finally e.Free; end;
end;

procedure TCalcEditTest.TestCalcEditReservesButton;
var e: TCalcEditAccess;
begin
  e := TCalcEditAccess.Create(nil);
  try
    AssertTrue('reserves space for the calc button', e.Reserve > 0);
  finally e.Free; end;
end;

procedure TCalcEditTest.TestCalcCurrencyIsCurrency;
var e: TTyCalcCurrencyEdit;
begin
  e := TTyCalcCurrencyEdit.Create(nil);
  try
    AssertTrue('is a currency edit', e is TTyCurrencyEdit);
    e.Value := 1234.5;
    AssertEquals('value round-trips', 1234.5, e.Value, 1e-9);
  finally e.Free; end;
end;

procedure TCalcEditTest.TestCalcCurrencyReservesButton;
var e: TCalcCurrAccess;
begin
  e := TCalcCurrAccess.Create(nil);
  try
    AssertTrue('reserves space for the calc button', e.Reserve > 0);
  finally e.Free; end;
end;

initialization
  RegisterTest(TCalcEditTest);
end.
