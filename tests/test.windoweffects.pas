unit test.windoweffects;
{$mode objfpc}{$H+}
interface
uses Classes, SysUtils, fpcunit, testregistry, Forms,
  {$IFDEF LCLWin32}Windows,{$ENDIF}
  tyControls.Types, tyControls.StyleModel, tyControls.WindowEffects;
type
  { The frame/shadow trade, pinned on its own: the platform code that reads it cannot be
    exercised headlessly, but the RULE can. }
  TNcFrameEatTest = class(TTestCase)
  published
    procedure TestFrameIsKeptOnlyWhenAShadowWillActuallyAppear;
  end;

  TWindowEffectsTest = class(TTestCase)
  published
    procedure TestWindowShadowParsesTrue;
    procedure TestWindowShadowAbsentIsNotPresent;
    procedure TestRadiusToCornerPref;
    procedure TestApplyIsNoOpWhenNoHandle;
    procedure TestDefaultsOnWhenTokensAbsent;
    procedure TestBorderRadiusZeroTurnsCornersOff;
    procedure TestWindowShadowFalseTurnsShadowOff;
    procedure TestMergeCopiesWindowShadowValue;
    { The TyLastWindowEffect/TyWindowEffectApplies seam: records REAL applies only (a window
      handle existed), verbatim. This is what lets the form-level tests in test.form pin that a
      theme's / StyleOverride's window-shadow + border-radius actually reach the platform apply
      layer — the exact seam the forum "window-shadow: false is ignored" bug slipped past. }
    procedure TestApplySeamSkipsWhenNoHandle;
    procedure TestApplySeamRecordsEffectVerbatim;
    { Windows only (Ignore elsewhere): read DWMWA_NCRENDERING_ENABLED back from the REAL HWND
      after each apply. This pins the actual DWM mechanism of the fix — window-shadow:false must
      DISABLE per-window NC rendering (the standard frame shadow of a resizable TTyForm ignores
      the DwmExtendFrameIntoClientArea margins entirely), and a later shadow-on flip must
      re-enable it on the SAME window. Without this read-back, deleting the
      DWMWA_NCRENDERING_POLICY call would survive every headless test and only die on a real
      screenshot. }
    procedure TestShadowTogglesNcRenderingOnRealWindow;
  end;
implementation

{ The console runner never calls Application.Initialize, so widget window classes are
  unregistered and CreateHandle fails with 1407. Lazy one-shot init, only for the tests that
  need a REAL native window — the same pattern (and reasoning) as test.base's NeedWidgetSet. }
var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

procedure TNcFrameEatTest.TestFrameIsKeptOnlyWhenAShadowWillActuallyAppear;
{ The Win32 non-client calc keeps the left/right/bottom frame for ONE reason: the DWM hangs
  the window shadow on it. On a version with NO DWM the frame is kept for a shadow that can
  never be drawn, while the OS legacy-paints its own ring in those bands (XP's Luna blue) and
  repaints a classic caption over our chrome whenever a dropdown steals activation.

  The second argument is the OS VERSION test, NOT "is composition on" -- that distinction is
  the point of this test. Vista and Win7 can run with composition switched off and still have
  a DWM frame and the shell gestures that ride on WS_CAPTION, so they must keep the handling
  they have; only the versions with no DWM at all change behaviour. }
begin
  AssertFalse('a wanted shadow on a DWM version keeps the frame -- Vista/7/10/11 unchanged',
    TyNcFullFrameEat(True, False));
  AssertTrue('a wanted shadow on a legacy-NC version eats the frame -- the XP case',
    TyNcFullFrameEat(True, True));
  AssertTrue('the theme opting out eats the frame on a DWM version, as it always did',
    TyNcFullFrameEat(False, False));
  AssertTrue('and on a legacy-NC version too', TyNcFullFrameEat(False, True));
end;

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
  // 0 -> 1 (DONOTROUND), 1..5 -> 3 (ROUNDSMALL), >5 -> 2 (ROUND)
  AssertEquals('0 -> donotround', 1, TyRadiusToCornerPref(0, False));
  AssertEquals('4 -> roundsmall', 3, TyRadiusToCornerPref(4, False));
  AssertEquals('8 -> round', 2, TyRadiusToCornerPref(8, False));
  AssertEquals('maximized -> donotround', 1, TyRadiusToCornerPref(8, True));
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
procedure TWindowEffectsTest.TestMergeCopiesWindowShadowValue;
var M: TTyStyleModel; base, over: TTyStyleSet;
begin
  // Regression: TyMergeStyleSet must copy the WindowShadow VALUE under tpWindowShadow,
  // not just union the present-flag (else a per-instance window-shadow:false is lost).
  M := TTyStyleModel.Create;
  try
    M.LoadFromCss('A { window-shadow: true; } B { window-shadow: false; }');
    base := M.ResolveStyle('A', '', []);
    over := M.ResolveStyle('B', '', []);
    TyMergeStyleSet(base, over);
    AssertTrue('tpWindowShadow present after merge', tpWindowShadow in base.Present);
    AssertFalse('override window-shadow:false copied into base', base.WindowShadow);
  finally M.Free; end;
end;
procedure TWindowEffectsTest.TestApplySeamSkipsWhenNoHandle;
var F: TForm; E: TTyWindowEffect; c0: Cardinal;
begin
  F := TForm.CreateNew(nil);   // no handle -> the guard exits BEFORE the seam records
  try
    E.RadiusPx := 3; E.Shadow := False; E.Maximized := False; E.BorderColorRGB := 0;
    c0 := TyWindowEffectApplies;
    TyApplyWindowEffects(F, E);
    AssertEquals('no-handle apply must not count as a real apply', c0, TyWindowEffectApplies);
  finally F.Free; end;
end;
procedure TWindowEffectsTest.TestApplySeamRecordsEffectVerbatim;
var F: TForm; E: TTyWindowEffect; c0: Cardinal;
begin
  NeedWidgetSet;
  F := TForm.CreateNew(nil);
  try
    F.HandleNeeded;   // real HWND, no Show needed
    AssertTrue('precondition: handle allocated', F.HandleAllocated);
    E.RadiusPx := 5; E.Shadow := False; E.Maximized := True; E.BorderColorRGB := TyDwmColorNone;
    c0 := TyWindowEffectApplies;
    TyApplyWindowEffects(F, E);
    AssertEquals('one real apply counted', c0 + 1, TyWindowEffectApplies);
    AssertEquals('radius recorded verbatim', 5, TyLastWindowEffect.RadiusPx);
    AssertFalse('shadow recorded verbatim', TyLastWindowEffect.Shadow);
    AssertTrue('maximized recorded verbatim', TyLastWindowEffect.Maximized);
  finally F.Free; end;
end;
procedure TWindowEffectsTest.TestShadowTogglesNcRenderingOnRealWindow;
{$IFDEF LCLWin32}
type
  TDwmGetAttr = function(h: HWND; a: DWORD; pv: Pointer; cb: DWORD): HRESULT; stdcall;
const
  DWMWA_NCRENDERING_ENABLED = 1;   // read-only query: is DWM rendering this window's NC?
var
  F: TForm; E: TTyWindowEffect;
  lib: HMODULE; GetAttr: TDwmGetAttr;
  en: BOOL;
begin
  NeedWidgetSet;
  lib := LoadLibrary('dwmapi.dll');
  if lib = 0 then begin Ignore('no dwmapi.dll (pre-Vista)'); Exit; end;
  try
    Pointer(GetAttr) := GetProcAddress(lib, 'DwmGetWindowAttribute');
    if not Assigned(GetAttr) then begin Ignore('no DwmGetWindowAttribute'); Exit; end;
    F := TForm.CreateNew(nil);
    try
      F.HandleNeeded;
      E.RadiusPx := 8; E.Maximized := False; E.BorderColorRGB := TyDwmColorNone;
      // OFF: the shadow of a frame window is DWM NC rendering — margins can't remove it,
      // the policy must. Read the LIVE state back from the window.
      E.Shadow := False;
      TyApplyWindowEffects(F, E);
      en := True;
      if GetAttr(F.Handle, DWMWA_NCRENDERING_ENABLED, @en, SizeOf(en)) <> 0 then
        begin Ignore('DwmGetWindowAttribute failed (no composition?)'); Exit; end;
      AssertFalse('window-shadow:false must DISABLE DWM NC rendering on the window', en);
      // ON again, SAME window: the flip back must re-enable it (a granted opt-out is undoable).
      E.Shadow := True;
      TyApplyWindowEffects(F, E);
      en := False;
      GetAttr(F.Handle, DWMWA_NCRENDERING_ENABLED, @en, SizeOf(en));
      AssertTrue('window-shadow:true must re-enable DWM NC rendering live', en);
      // And OFF once more — the ordering never wedges.
      E.Shadow := False;
      TyApplyWindowEffects(F, E);
      en := True;
      GetAttr(F.Handle, DWMWA_NCRENDERING_ENABLED, @en, SizeOf(en));
      AssertFalse('second opt-out still lands', en);
    finally F.Free; end;
  finally
    FreeLibrary(lib);
  end;
end;
{$ELSE}
begin
  Ignore('DWM NC rendering is a Win32-only mechanism');
end;
{$ENDIF}

initialization
  RegisterTest(TNcFrameEatTest);
  RegisterTest(TWindowEffectsTest);
end.
