unit test.accel;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.Accel;
type
  TAccelTest = class(TTestCase)
  published
    procedure TestParseMnemonic;
    procedure TestGatePosOffByDefault;
  end;
implementation
procedure TAccelTest.TestParseMnemonic;
var d: string; p: Integer; m: Char;
begin
  m := TyParseMnemonic('&File', d, p);
  AssertEquals('display', 'File', d);
  AssertEquals('mnemonic', 'F', m);
  AssertEquals('pos', 1, p);
  m := TyParseMnemonic('a && b', d, p);
  AssertEquals('literal amp', 'a & b', d);
  AssertEquals('no mnemonic', #0, m);
end;
procedure TAccelTest.TestGatePosOffByDefault;
begin
  // No Alt held in a headless run -> gate returns 0 (underline suppressed).
  AssertEquals('gate off', 0, TyAccelGatePos(3));
end;
initialization
  RegisterTest(TAccelTest);
end.
