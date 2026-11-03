unit test.comboedit;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, Types, Controls, fpcunit, testregistry, tyControls.ComboEdit;
type
  TAccessCombo = class(TTyComboEdit)
  public
    function Reserve(APPI: Integer): Integer;
    procedure ClickButton;
  end;

  TComboEditTest = class(TTestCase)
  private
    FFired: Boolean;
    procedure HandleDrop(Sender: TObject);
  published
    procedure TestDropDownFires;
    procedure TestReservesButton;
    procedure TestAReadOnlyButtonDoesNotDrop;
  end;

implementation

function TAccessCombo.Reserve(APPI: Integer): Integer;
begin
  Result := RightReserve(APPI);
end;

procedure TAccessCombo.ClickButton;
var z: TRect;
begin
  z := TrailingZone(Font.PixelsPerInch);
  MouseDown(mbLeft, [], (z.Left + z.Right) div 2, (z.Top + z.Bottom) div 2);
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

{ #159: ReadOnly disables the button, as LCL's TEditButton does: a click fires no OnDropDown. }
procedure TComboEditTest.TestAReadOnlyButtonDoesNotDrop;
var c: TAccessCombo;
begin
  c := TAccessCombo.Create(nil);
  try
    c.Font.PixelsPerInch := 96;
    c.SetBounds(0, 0, 160, 26);
    c.OnDropDown := @HandleDrop;
    FFired := False;
    c.ClickButton;
    AssertTrue('setup: the button drops', FFired);
    c.ReadOnly := True;
    FFired := False;
    c.ClickButton;
    AssertFalse('read-only, it does not', FFired);
  finally c.Free; end;
end;

initialization
  RegisterTest(TComboEditTest);
end.
