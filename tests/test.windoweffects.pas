unit test.windoweffects;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry,
  tyControls.Types, tyControls.StyleModel;
type
  TWindowEffectsTest = class(TTestCase)
  published
    procedure TestWindowShadowParsesTrue;
    procedure TestWindowShadowAbsentIsNotPresent;
  end;
implementation
procedure TWindowEffectsTest.TestWindowShadowParsesTrue;
var M: TTyStyleModel; S: TTyStyleSet;
begin
  M := TTyStyleModel.Create;
  try
    M.LoadFromCss('TyForm { window-shadow: true; }');
    S := M.ResolveStyle('TyForm', '', []);
    AssertTrue('tpWindowShadow present', tpWindowShadow in S.Present);
    AssertTrue('WindowShadow = true', S.WindowShadow);
  finally M.Free; end;
end;
procedure TWindowEffectsTest.TestWindowShadowAbsentIsNotPresent;
var M: TTyStyleModel; S: TTyStyleSet;
begin
  M := TTyStyleModel.Create;
  try
    M.LoadFromCss('TyForm { background: #FFFFFF; }');
    S := M.ResolveStyle('TyForm', '', []);
    AssertFalse('tpWindowShadow not present', tpWindowShadow in S.Present);
  finally M.Free; end;
end;
initialization
  RegisterTest(TWindowEffectsTest);
end.
