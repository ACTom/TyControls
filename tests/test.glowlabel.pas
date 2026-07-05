unit test.glowlabel;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.GlowLabel;
type
  TGlowLabelTest = class(TTestCase)
  published
    procedure TestClampRadius;
    procedure TestSmoke;
  end;
implementation

procedure TGlowLabelTest.TestClampRadius;
begin
  AssertEquals('negative -> 0', 0, TyGlowClampRadius(-3));
  AssertEquals('zero passes', 0, TyGlowClampRadius(0));
  AssertEquals('in range passes', 4, TyGlowClampRadius(4));
  AssertEquals('upper bound', 64, TyGlowClampRadius(64));
  AssertEquals('over max clamps', 64, TyGlowClampRadius(999));
end;

procedure TGlowLabelTest.TestSmoke;
var G: TTyGlowLabel;
begin
  // Construct, set the effect props, free — no crash (headless).
  G := TTyGlowLabel.Create(nil);
  try
    G.Caption := 'Glow &Label';
    G.GlowColor := $80FF3366;
    G.GlowRadius := 6;
    AssertEquals('radius stored', 6, G.GlowRadius);
    G.GlowRadius := -10;   // clamps through the setter
    AssertEquals('radius clamped', 0, G.GlowRadius);
  finally
    G.Free;
  end;
end;

initialization
  RegisterTest(TGlowLabelTest);
end.
