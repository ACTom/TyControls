unit test.base;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, Forms, LCLIntf, TypInfo, fpcunit, testregistry,
  tyControls.Types, tyControls.Base,
  tyControls.Panel, tyControls.GroupBox, tyControls.ComboBox;
type
  TTestStyleControl = class(TTyCustomControl)
  protected
    function GetStyleTypeKey: string; override;
  public
    procedure SetHover(AValue: Boolean);
    procedure SetPressed(AValue: Boolean);
    function PublicCurrentStates: TTyStateSet;
  end;

  TBaseTest = class(TTestCase)
  published
    procedure TestNormalState;
    procedure TestHoverState;
    procedure TestPressedAddsActive;
    procedure TestDisabledState;
    procedure TestStyleTypeKey;
    procedure TestBaselinePropertiesPublished;
    procedure TestEnabledReachesTheWidgetset;
    procedure TestDisabledReachesTheWidgetset;
  end;
implementation

function TTestStyleControl.GetStyleTypeKey: string;
begin
  Result := 'TyButton';
end;

procedure TTestStyleControl.SetHover(AValue: Boolean);
begin
  FHover := AValue;
end;

procedure TTestStyleControl.SetPressed(AValue: Boolean);
begin
  FPressed := AValue;
end;

function TTestStyleControl.PublicCurrentStates: TTyStateSet;
begin
  Result := CurrentStates;
end;

procedure TBaseTest.TestNormalState;
var
  ctl: TTestStyleControl;
begin
  ctl := TTestStyleControl.Create(nil);
  try
    AssertTrue('normal present', tysNormal in ctl.PublicCurrentStates);
    AssertFalse('hover absent', tysHover in ctl.PublicCurrentStates);
  finally
    ctl.Free;
  end;
end;

procedure TBaseTest.TestHoverState;
var
  ctl: TTestStyleControl;
begin
  ctl := TTestStyleControl.Create(nil);
  try
    ctl.SetHover(True);
    AssertTrue('hover present', tysHover in ctl.PublicCurrentStates);
  finally
    ctl.Free;
  end;
end;

procedure TBaseTest.TestPressedAddsActive;
var
  ctl: TTestStyleControl;
begin
  ctl := TTestStyleControl.Create(nil);
  try
    ctl.SetPressed(True);
    AssertTrue('active present', tysActive in ctl.PublicCurrentStates);
  finally
    ctl.Free;
  end;
end;

procedure TBaseTest.TestDisabledState;
var
  ctl: TTestStyleControl;
begin
  ctl := TTestStyleControl.Create(nil);
  try
    ctl.Enabled := False;
    AssertTrue('disabled present', tysDisabled in ctl.PublicCurrentStates);
    AssertFalse('normal absent when disabled', tysNormal in ctl.PublicCurrentStates);
  finally
    ctl.Free;
  end;
end;

procedure TBaseTest.TestStyleTypeKey;
var
  ctl: TTestStyleControl;
begin
  ctl := TTestStyleControl.Create(nil);
  try
    AssertEquals('typekey', 'TyButton', ctl.GetStyleTypeKey);
  finally
    ctl.Free;
  end;
end;

procedure TBaseTest.TestBaselinePropertiesPublished;
{ Baseline props must be PUBLISHED (streamable + Object Inspector) on controls
  that previously omitted them. RTTI: GetPropInfo returns nil for a non-published
  property. }
var P: TTyPanel; G: TTyGroupBox; C: TTyComboBox;
begin
  P := TTyPanel.Create(nil);
  G := TTyGroupBox.Create(nil);
  C := TTyComboBox.Create(nil);
  try
    AssertTrue('Panel.Font published',     GetPropInfo(P, 'Font') <> nil);
    AssertTrue('Panel.Hint published',     GetPropInfo(P, 'Hint') <> nil);
    AssertTrue('Panel.ShowHint published', GetPropInfo(P, 'ShowHint') <> nil);
    AssertTrue('GroupBox.Font published',  GetPropInfo(G, 'Font') <> nil);
    AssertTrue('ComboBox.Font published',  GetPropInfo(C, 'Font') <> nil);
    AssertTrue('Panel.TabOrder published (TWinControl)', GetPropInfo(P, 'TabOrder') <> nil);
  finally P.Free; G.Free; C.Free; end;
end;

{ These two are the only tests in the suite that need a REAL native window. The console
  runner never calls Application.Initialize, so the widgetset's window classes are
  unregistered and CreateHandle fails with 1407 (cannot find window class). Do it once,
  lazily, so the other ~3960 handle-less tests keep starting as fast as they do now. }
var
  WidgetSetReady: Boolean = False;

procedure NeedWidgetSet;
begin
  if WidgetSetReady then Exit;
  Forms.Application.Initialize;
  WidgetSetReady := True;
end;

{ Both of these guard ONE bug, from its two sides: TTyCustomControl used to answer
  CM_ENABLEDCHANGED with a bare Invalidate and no `inherited`, which swallowed the message
  before TWinControl could run EnableWindow(Handle, Enabled).

  What that produced is nastier than "the control looks wrong", which is why a repaint test
  would never have caught it: the control repainted in the RIGHT state every time. Only the
  native window disagreed. A control whose handle was created while disabled — the normal
  case for anything a form arms after streaming, e.g. TTyTransfer's rail — stayed
  input-DEAD forever: it drew itself enabled, the user clicked it, and Windows dropped the
  message because the HWND was still disabled.

  So the assertion has to be about the WINDOW, not the control's own field. It needs a real
  handle, hence the form; LCLIntf.IsWindowEnabled is the LCL-wide spelling, so this is not a
  Win32-only test. }
procedure TBaseTest.TestEnabledReachesTheWidgetset;
var
  F: TForm;
  ctl: TTestStyleControl;
begin
  NeedWidgetSet;
  F := TForm.CreateNew(nil);
  try
    ctl := TTestStyleControl.Create(F);
    ctl.Parent := F;
    ctl.Enabled := False;
    F.HandleNeeded;
    ctl.HandleNeeded;
    AssertFalse('a control disabled BEFORE its handle exists must come up disabled',
      IsWindowEnabled(ctl.Handle));

    ctl.Enabled := True;
    AssertTrue('enabling after the handle exists must reach EnableWindow',
      IsWindowEnabled(ctl.Handle));
  finally
    F.Free;
  end;
end;

procedure TBaseTest.TestDisabledReachesTheWidgetset;
var
  F: TForm;
  ctl: TTestStyleControl;
begin
  NeedWidgetSet;
  F := TForm.CreateNew(nil);
  try
    ctl := TTestStyleControl.Create(F);
    ctl.Parent := F;
    F.HandleNeeded;
    ctl.HandleNeeded;
    AssertTrue('sanity: it starts enabled', IsWindowEnabled(ctl.Handle));

    ctl.Enabled := False;
    AssertFalse('disabling must reach EnableWindow too, or a "disabled" control still '
      + 'takes clicks', IsWindowEnabled(ctl.Handle));
  finally
    F.Free;
  end;
end;

initialization
  RegisterTest(TBaseTest);
end.
