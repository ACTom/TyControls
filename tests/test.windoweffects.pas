unit test.windoweffects;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, Forms,
  tyControls.Types, tyControls.StyleModel, tyControls.WindowEffects;
type
  TWindowEffectsTest = class(TTestCase)
  published
    procedure TestWindowShadowParsesTrue;
    procedure TestWindowShadowAbsentIsNotPresent;
    procedure TestRadiusToCornerPref;
    procedure TestApplyIsNoOpWhenNoHandle;
    procedure TestDefaultsOnWhenTokensAbsent;
    procedure TestBorderRadiusZeroTurnsCornersOff;
    procedure TestWindowShadowFalseTurnsShadowOff;
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
procedure TWindowEffectsTest.TestRadiusToCornerPref;
begin
  // 0 -> 0 (DONOTROUND), 1..5 -> 3 (ROUNDSMALL), >5 -> 2 (ROUND)
  AssertEquals('0 -> donotround', 0, TyRadiusToCornerPref(0, False));
  AssertEquals('4 -> roundsmall', 3, TyRadiusToCornerPref(4, False));
  AssertEquals('8 -> round', 2, TyRadiusToCornerPref(8, False));
  AssertEquals('maximized -> donotround', 0, TyRadiusToCornerPref(8, True));
end;
procedure TWindowEffectsTest.TestApplyIsNoOpWhenNoHandle;
var F: TForm; E: TTyWindowEffect;
begin
  F := TForm.CreateNew(nil);   // no Show -> HandleAllocated False (headless)
  try
    E.RadiusPx := 8; E.Shadow := True; E.Maximized := False;
    TyApplyWindowEffects(F, E);   // must NOT raise
    AssertTrue('no-op safe with no handle', True);
  finally F.Free; end;
end;
procedure TWindowEffectsTest.TestDefaultsOnWhenTokensAbsent;
var M: TTyStyleModel; E: TTyWindowEffect;
begin
  M := TTyStyleModel.Create;
  try
    M.LoadFromCss('TyForm { background: #FFFFFF; }');     // no radius, no window-shadow
    E := TyResolveWindowEffect(M.ResolveStyle('TyForm', '', []), False);
    AssertEquals('default radius on', TyDefaultWindowRadiusPx, E.RadiusPx);
    AssertTrue('default shadow on', E.Shadow);
  finally M.Free; end;
end;
procedure TWindowEffectsTest.TestBorderRadiusZeroTurnsCornersOff;
var M: TTyStyleModel; E: TTyWindowEffect;
begin
  M := TTyStyleModel.Create;
  try
    M.LoadFromCss('TyForm { border-radius: 0; }');        // present-with-0 -> opt out
    E := TyResolveWindowEffect(M.ResolveStyle('TyForm', '', []), False);
    AssertEquals('corners off via border-radius:0', 0, E.RadiusPx);
  finally M.Free; end;
end;
procedure TWindowEffectsTest.TestWindowShadowFalseTurnsShadowOff;
var M: TTyStyleModel; E: TTyWindowEffect;
begin
  M := TTyStyleModel.Create;
  try
    M.LoadFromCss('TyForm { window-shadow: false; }');
    E := TyResolveWindowEffect(M.ResolveStyle('TyForm', '', []), False);
    AssertFalse('shadow off via window-shadow:false', E.Shadow);
  finally M.Free; end;
end;
initialization
  RegisterTest(TWindowEffectsTest);
end.
