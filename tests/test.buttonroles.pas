unit test.buttonroles;
{ #119: a button set Default or Cancel before it has a parent registers once it has one; the
  button that loses the role to another clears its own flag; a colour button applies its
  ModalResult only when the user accepts a colour; a speed button group shares AllowAllUp,
  and joining a group releases its pressed member -- each as LCL's own button does. }
{$mode objfpc}{$H+}
interface

uses
  Classes, SysUtils, Controls, Forms, fpcunit, testregistry,
  tyControls.Types, tyControls.Button, tyControls.ColorButton, tyControls.GlyphButtons;

type
  TButtonRolesTest = class(TTestCase)
  private
    FForm: TForm;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestDefaultSetBeforeTheParentRegisters;
    procedure TestCancelSetBeforeTheParentRegisters;
    procedure TestTheButtonThatLosesTheRoleClearsItsFlag;
    procedure TestMovingToAnotherFormTakesTheRoleAlong;
    procedure TestAColourButtonClosesTheFormOnlyOnAnAcceptedColour;
    procedure TestAllowAllUpIsTheGroups;
    procedure TestJoiningAGroupReleasesItsPressedMember;
  end;

implementation

type
  TPickProbe = class(TTyColorButton)
  public
    Accept: Boolean;
  protected
    function PickColor(var AColor: TTyColor): Boolean; override;
  end;

function TPickProbe.PickColor(var AColor: TTyColor): Boolean;
begin
  Result := Accept;
end;

procedure TButtonRolesTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
end;

procedure TButtonRolesTest.TearDown;
begin
  FreeAndNil(FForm);
end;

procedure TButtonRolesTest.TestDefaultSetBeforeTheParentRegisters;
var
  b: TTyButton;
begin
  b := TTyButton.Create(FForm);
  b.Default := True;
  b.Parent := FForm;
  AssertTrue('the form routes Enter to it', FForm.DefaultControl = b);
end;

procedure TButtonRolesTest.TestCancelSetBeforeTheParentRegisters;
var
  b: TTyButton;
begin
  b := TTyButton.Create(FForm);
  b.Cancel := True;
  b.Parent := FForm;
  AssertTrue('the form routes Escape to it', FForm.CancelControl = b);
end;

procedure TButtonRolesTest.TestTheButtonThatLosesTheRoleClearsItsFlag;
var
  a, b: TTyButton;
begin
  a := TTyButton.Create(FForm);
  a.Parent := FForm;
  b := TTyButton.Create(FForm);
  b.Parent := FForm;
  a.Default := True;
  b.Default := True;
  AssertTrue('the second one is the default now', FForm.DefaultControl = b);
  AssertFalse('the first no longer says it is', a.Default);
  a.Cancel := True;
  FForm.CancelControl := b;
  AssertFalse('the same for Cancel', a.Cancel);
  AssertTrue('and the new one says so', b.Cancel);
end;

procedure TButtonRolesTest.TestMovingToAnotherFormTakesTheRoleAlong;
var
  other: TForm;
  b: TTyButton;
begin
  other := TForm.CreateNew(nil);
  try
    b := TTyButton.Create(FForm);
    b.Parent := FForm;
    b.Default := True;
    b.Parent := other;
    AssertTrue('the old form lets go of it', FForm.DefaultControl <> b);
    AssertTrue('the new one takes it', other.DefaultControl = b);
    AssertTrue('and it is still Default', b.Default);
    b.Parent := nil;
  finally
    other.Free;
  end;
end;

procedure TButtonRolesTest.TestAColourButtonClosesTheFormOnlyOnAnAcceptedColour;
var
  c: TPickProbe;
begin
  c := TPickProbe.Create(FForm);
  c.Parent := FForm;
  c.ModalResult := mrOK;
  c.Accept := False;
  FForm.ModalResult := mrNone;
  c.Click;
  AssertTrue('a cancelled colour leaves the form open', FForm.ModalResult = mrNone);
  c.Accept := True;
  c.Click;
  AssertTrue('an accepted one closes it', FForm.ModalResult = mrOK);
end;

procedure TButtonRolesTest.TestAllowAllUpIsTheGroups;
var
  a, b: TTySpeedButton;
begin
  a := TTySpeedButton.Create(FForm);
  a.Parent := FForm;
  a.GroupIndex := 1;
  b := TTySpeedButton.Create(FForm);
  b.Parent := FForm;
  b.GroupIndex := 1;
  a.AllowAllUp := True;
  AssertTrue('the other member takes it', b.AllowAllUp);
end;

procedure TButtonRolesTest.TestJoiningAGroupReleasesItsPressedMember;
var
  a, b: TTySpeedButton;
begin
  a := TTySpeedButton.Create(FForm);
  a.Parent := FForm;
  a.GroupIndex := 1;
  a.Down := True;
  b := TTySpeedButton.Create(FForm);
  b.Parent := FForm;
  b.Down := True;   // no group yet: it may be down alongside
  b.GroupIndex := 1;
  AssertFalse('the group''s pressed member is released', a.Down);
  AssertTrue('the one that joined stays down', b.Down);
end;

initialization
  RegisterTest(TButtonRolesTest);
end.
