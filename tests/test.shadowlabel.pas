unit test.shadowlabel;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.Types, tyControls.ShadowLabel;
type
  TShadowLabelTest = class(TTestCase)
  published
    procedure TestSmoke;
  end;
implementation

procedure TShadowLabelTest.TestSmoke;
var
  L: TTyShadowLabel;
begin
  // Construct, set the label's own props, and free with no crash.
  L := TTyShadowLabel.Create(nil);
  try
    L.Caption := 'Hello shadow';
    L.ShadowColor := TyRGBA(10, 20, 30, 90);
    L.ShadowOffsetX := 3;
    L.ShadowOffsetY := 2;
    AssertEquals('caption round-trips', 'Hello shadow', L.Caption);
    AssertEquals('offset X round-trips', 3, L.ShadowOffsetX);
    AssertEquals('offset Y round-trips', 2, L.ShadowOffsetY);
    AssertTrue('shadow colour round-trips', L.ShadowColor = TyRGBA(10, 20, 30, 90));
  finally
    L.Free;
  end;
end;

initialization
  RegisterTest(TShadowLabelTest);
end.
