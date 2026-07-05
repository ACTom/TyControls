unit test.circularprogress;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, tyControls.CircularProgress;
type
  TCircularProgressTest = class(TTestCase)
  published
    procedure TestPositionClamp;
    procedure TestMinMaxReclamp;
  end;
implementation

procedure TCircularProgressTest.TestPositionClamp;
var c: TTyCircularProgress;
begin
  c := TTyCircularProgress.Create(nil);
  try
    c.Position := 200;                              // > Max (100)
    AssertEquals('clamp high', 100, c.Position);
    c.Position := -5;                               // < Min (0)
    AssertEquals('clamp low', 0, c.Position);
    c.Position := 42;
    AssertEquals('in range', 42, c.Position);
  finally c.Free; end;
end;

procedure TCircularProgressTest.TestMinMaxReclamp;
var c: TTyCircularProgress;
begin
  c := TTyCircularProgress.Create(nil);
  try
    c.Position := 80;
    c.Max := 50;                                    // Position (80) re-clamps to Max
    AssertEquals('Max reclamps Position', 50, c.Position);
    c.Max := 100; c.Position := 10;
    c.Min := 30;                                    // Position (10) re-clamps up to Min
    AssertEquals('Min reclamps Position', 30, c.Position);
  finally c.Free; end;
end;

initialization
  RegisterTest(TCircularProgressTest);
end.
