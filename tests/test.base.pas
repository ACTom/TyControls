unit test.base;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Controls, fpcunit, testregistry,
  tyControls.Types, tyControls.Base;
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

initialization
  RegisterTest(TBaseTest);
end.
