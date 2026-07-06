unit test.comboedit;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.ComboEdit;
type
  TAccessCombo = class(TTyComboEdit)
  public
    function Reserve(APPI: Integer): Integer;
  end;

  TComboEditTest = class(TTestCase)
  private
    FFired: Boolean;
    procedure HandleDrop(Sender: TObject);
  published
    procedure TestDropDownFires;
    procedure TestReservesButton;
  end;

implementation

function TAccessCombo.Reserve(APPI: Integer): Integer;
begin
  Result := RightReserve(APPI);
end;

procedure TComboEditTest.HandleDrop(Sender: TObject);
begin
  FFired := True;
end;

procedure TComboEditTest.TestDropDownFires;
var c: TTyComboEdit;
begin
  c := TTyComboEdit.Create(nil);
  try
    FFired := False;
    c.OnDropDown := @HandleDrop;
    c.DropDown;
    AssertTrue('OnDropDown fired', FFired);
  finally c.Free; end;
end;

procedure TComboEditTest.TestReservesButton;
var c: TAccessCombo;
begin
  c := TAccessCombo.Create(nil);
  try
    AssertTrue('reserves a trailing zone', c.Reserve(96) > 0);
  finally c.Free; end;
end;

initialization
  RegisterTest(TComboEditTest);
end.
