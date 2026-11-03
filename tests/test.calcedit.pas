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
    procedure TestAReadOnlyEditKeepsTheCalculatorShut;
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

{ #159: with ReadOnly the button opens no calculator, as LCL's TCalcEdit disables it -- for the
  currency edit too -- and a calculator already up when the edit turned read-only writes nothing
  back. }
procedure TCalcEditTest.TestAReadOnlyEditKeepsTheCalculatorShut;
var
  f: TForm;
  e: TTyCalcEdit;
  cc: TTyCalcCurrencyEdit;
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
    e.ReadOnly := True;
    d := TTyCalcDropdown.Create(e);
    d.Toggle;
    AssertFalse('the button opens nothing', d.IsOpen);
    cc := TTyCalcCurrencyEdit.Create(f);
    cc.Parent := f;
    cc.SetBounds(0, 40, 160, 26);
    cc.ReadOnly := True;
    d := TTyCalcDropdown.Create(cc);
    d.Toggle;
    AssertFalse('nor on the currency edit', d.IsOpen);
    e.ReadOnly := False;
    d := TTyCalcDropdown.Create(e);
    d.Toggle;
    c := d.CalculatorForTest;
    AssertNotNull('setup: the calculator is up', c);
    e.ReadOnly := True;
    c.Value := 7;
    c.PressKey('=');
    AssertEquals('a read-only edit takes no result', 42, e.Value, 1e-9);
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
    AssertTrue('is a numeric edit', e is TTyCustomNumericEdit);
    { 4.0 hangs the derived edits on the custom chain, the LCL way: a calc edit is a
      TTyCustomNumericEdit and no longer a TTyNumericEdit (an intended incompatibility, see
      docs/subclassing.md). TObject() because the compiler rejects `is` between classes it
      can see are unrelated -- which is exactly the point being pinned. }
    AssertFalse('and no longer a TTyNumericEdit', TObject(e) is TTyNumericEdit);
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
    AssertTrue('is a currency edit', e is TTyCustomCurrencyEdit);
    AssertFalse('and no longer a TTyCurrencyEdit', TObject(e) is TTyCurrencyEdit);
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
