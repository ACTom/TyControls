unit test.calcedit;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Forms, fpcunit, testregistry,
  tyControls.NumericEdit, tyControls.CurrencyEdit,
  tyControls.CalcEdit, tyControls.CalcCurrencyEdit, tyControls.Calculator;
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
    procedure TestOnlyAnAcceptedResultIsWrittenBack;
  end;
implementation

var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

{ #191: the calculator writes its value into the edit when it is accepted ('=' or Enter), as
  LCL's TCalcEdit writes back on OK alone. Put away any other way it leaves the edit be: Esc
  first clears it, so writing back on every close set the field to 0. }
procedure TCalcEditTest.TestOnlyAnAcceptedResultIsWrittenBack;
var
  f: TForm;
  e: TTyCalcEdit;
  d: TTyCalcDropdown;
  c: TTyCalculator;
begin
  NeedWidgetSet;
  f := TForm.CreateNew(nil);
  try
    f.SetBounds(-4000, -4000, 300, 200);
    f.Visible := True;
    e := TTyCalcEdit.Create(f);
    e.Parent := f;
    e.SetBounds(0, 0, 160, 26);
    e.Value := 42;
    d := TTyCalcDropdown.Create(e);
    d.Toggle;
    c := d.CalculatorForTest;
    AssertNotNull('setup: the calculator is up', c);
    AssertEquals('seeded from the edit', 42, c.Value, 1e-9);
    c.Value := 99;
    d.Toggle;   // put away with no '='
    AssertFalse('setup: closed', d.IsOpen);
    AssertEquals('the edit keeps its value', 42, e.Value, 1e-9);
    d := TTyCalcDropdown.Create(e);
    d.Toggle;
    c := d.CalculatorForTest;
    c.Value := 7;
    c.PressKey('=');
    AssertEquals('''='' writes the result back', 7, e.Value, 1e-9);
  finally
    f.Free;
  end;
end;

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
