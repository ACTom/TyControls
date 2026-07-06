unit test.urledit;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.URLEdit;
type
  TAccessURL = class(TTyURLEdit)
  public
    function Reserve(APPI: Integer): Integer;
  end;

  TURLEditTest = class(TTestCase)
  published
    procedure TestReservesButton;
    procedure TestOpenEmptyIsNoOp;
  end;

implementation

function TAccessURL.Reserve(APPI: Integer): Integer;
begin
  Result := RightReserve(APPI);
end;

procedure TURLEditTest.TestReservesButton;
var c: TAccessURL;
begin
  c := TAccessURL.Create(nil);
  try
    AssertTrue('reserves a trailing zone', c.Reserve(96) > 0);
  finally c.Free; end;
end;

procedure TURLEditTest.TestOpenEmptyIsNoOp;
var c: TTyURLEdit;
begin
  // Empty text must NOT launch a browser (guarded) and must not crash.
  c := TTyURLEdit.Create(nil);
  try
    c.Text := '';
    c.OpenURL;
    AssertEquals('still empty', '', c.Text);
  finally c.Free; end;
end;

initialization
  RegisterTest(TURLEditTest);
end.
