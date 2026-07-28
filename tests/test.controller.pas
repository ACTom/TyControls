unit test.controller;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, fpcunit, testregistry,
  tyControls.Types, tyControls.Controller, tyControls.Base, tyControls.ThemeRegistry;
type
  { Minimal TTyCustomControl descendant that counts Invalidate calls }
  TCountingControl = class(TTyCustomControl)
  public
    InvalidateCount: Integer;
    procedure Invalidate; override;
  protected
    function GetStyleTypeKey: string; override;
  end;

  TControllerTest = class(TTestCase)
  published
    procedure TestLoadThemeCssResolves;
    procedure TestThemeNameRetriesAfterAFailedResolve;
    procedure TestDefaultControllerIsSingleton;
    procedure TestDefaultControlRegisteredForHotReload;
    procedure TestFreeControllerFirstNocrash;
    procedure TestFreeControlFirstThenControllerChanged;
  end;
implementation

{ TCountingControl }

function TCountingControl.GetStyleTypeKey: string;
begin
  Result := 'TyButton';
end;

procedure TCountingControl.Invalidate;
begin
  Inc(InvalidateCount);
  { Do NOT call inherited: no Parent/handle in tests, would be a no-op or crash }
end;

{ TControllerTest }

procedure TControllerTest.TestLoadThemeCssResolves;
var
  c: TTyStyleController;
  s: TTyStyleSet;
begin
  c := TTyStyleController.Create(nil);
  try
    c.LoadThemeCss('TyButton { color: #FF0000; border-width: 3px; }');
    s := c.Model.ResolveStyle('TyButton', '', []);
    AssertTrue('TextColor present', tpTextColor in s.Present);
    AssertEquals('TextColor value', Integer(TyRGB($FF, $00, $00)), Integer(s.TextColor));
    AssertEquals('BorderWidth value', 3, s.BorderWidth);
  finally
    c.Free;
  end;
end;

procedure TControllerTest.TestDefaultControllerIsSingleton;
begin
  AssertSame('same instance', TyDefaultController, TyDefaultController);
  AssertTrue('not nil', TyDefaultController <> nil);
end;

procedure TControllerTest.TestDefaultControlRegisteredForHotReload;
{ Fix 1 regression: a control created without an explicit controller must be
  invalidated when TyDefaultController.Changed is called. }
var
  ctl: TCountingControl;
  beforeCount: Integer;
begin
  ctl := TCountingControl.Create(nil);
  try
    { Drain any Create-time Invalidate calls (none expected, but be safe) }
    beforeCount := ctl.InvalidateCount;
    { Trigger a theme hot-reload on the default controller }
    TyDefaultController.LoadThemeCss('TyButton { color: #00FF00; }');
    { The control must have been invalidated at least once by Changed }
    AssertTrue('default control invalidated by TyDefaultController.Changed',
      ctl.InvalidateCount > beforeCount);
  finally
    ctl.Free;
  end;
end;

procedure TControllerTest.TestFreeControllerFirstNocrash;
{ Fix 2 regression: freeing a TTyStyleController while a control still
  references it must not cause an access violation when the control is
  subsequently freed or its ActiveController is used. }
var
  ctrl: TTyStyleController;
  ctl: TCountingControl;
begin
  ctrl := TTyStyleController.Create(nil);
  ctl := TCountingControl.Create(nil);
  try
    ctl.Controller := ctrl;
  except
    ctl.Free;
    ctrl.Free;
    raise;
  end;
  { Free controller first — Notification should nil FController }
  ctrl.Free;
  { Now freeing or using the control must not crash }
  try
    { ActiveController should fall back to TyDefaultController }
    { Just call CurrentStyle; if FController was left dangling this would AV }
    ctl.CurrentStyle;
    AssertTrue('falls back to default without crash', True);
    ctl.Free;
  except
    on E: Exception do
    begin
      Fail('crash after freeing controller first: ' + E.Message);
    end;
  end;
end;

procedure TControllerTest.TestFreeControlFirstThenControllerChanged;
{ Reverse order: free the control first, then call controller.Changed — must
  not crash (control must have unregistered itself on free). }
var
  ctrl: TTyStyleController;
  ctl: TCountingControl;
begin
  ctrl := TTyStyleController.Create(nil);
  ctl := TCountingControl.Create(nil);
  try
    ctl.Controller := ctrl;
    { Free control first }
    ctl.Free;
    ctl := nil;
    { Changed must not deref freed control }
    ctrl.Changed;
    AssertTrue('no crash after freeing control first', True);
  finally
    ctl.Free;
    ctrl.Free;
  end;
end;

{ A .lfm sets ThemeName during STREAMING, which runs before the form's OnCreate -- so before
  an app has had a chance to register its themes. The name was recorded regardless, and the
  next attempt (the app's own ApplyBuiltin('default') in OnCreate, with the themes now
  registered) early-outed on "same name" and never loaded anything. The model stayed on the
  base layer permanently, which is single-mode: the demo's Dark button did nothing under
  `default`, and only started working once a DIFFERENT skin was picked, because a different
  name did not hit the early-out.

  So: re-assigning the same name must RETRY while the previous attempt did not resolve. }
procedure TControllerTest.TestThemeNameRetriesAfterAFailedResolve;
const
  CName = 'ty-test-late-registered';
var
  c: TTyStyleController;
  before, after_: TTyColor;
begin
  TyUnregisterTheme(CName);            // make sure it is genuinely unknown first
  c := TTyStyleController.Create(nil);
  try
    { Streaming order: the name is set while nothing can resolve it. }
    c.ThemeName := CName;
    before := c.Model.ResolveStyle('TyForm', '', []).Background.Color;

    { What the app does next in its OnCreate -- register, then set the SAME name. This is the
      assignment the early-out used to swallow. }
    TyRegisterThemeCss(CName, 'TyForm { background: #123456; }');
    c.ThemeName := CName;
    after_ := c.Model.ResolveStyle('TyForm', '', []).Background.Color;

    AssertTrue('the retry actually loaded the theme', after_ <> before);
    AssertEquals('and it is the theme we registered', $FF123456, after_);
  finally
    c.Free;
    TyUnregisterTheme(CName);
  end;
end;

initialization
  RegisterTest(TControllerTest);
end.
