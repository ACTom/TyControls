unit test.about;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, TypInfo, Forms, fpcunit, testregistry,
  tyControls.Types, tyControls.Button, tyControls.TyLabel, tyControls.Panel,
  tyControls.Edit, tyControls.Controller, tyControls.Menu, tyControls.Form;
type
  TAboutTest = class(TTestCase)
  published
    procedure TestVersionConstantPinned;
    procedure TestEveryComponentAboutReturnsVersion;
  end;

implementation

procedure TAboutTest.TestVersionConstantPinned;
begin
  AssertEquals('TyVersion pinned for this release', '2.1.0', TyVersion);
end;

procedure TAboutTest.TestEveryComponentAboutReturnsVersion;

  procedure Chk(C: TComponent);
  begin
    try
      // GetStrProp raises if the published About property is missing -> red.
      AssertEquals(C.ClassName + '.About', TyVersion, GetStrProp(C, 'About'));
    finally
      C.Free;
    end;
  end;

begin
  Chk(TTyButton.Create(nil));          // covers one control base
  Chk(TTyLabel.Create(nil));
  Chk(TTyPanel.Create(nil));
  Chk(TTyEdit.Create(nil));            // covers the other control base
  Chk(TTyStyleController.Create(nil)); // non-visual TComponent
  Chk(TTyPopupMenu.Create(nil));       // non-visual TPopupMenu
  Chk(TTyForm.CreateNew(nil));         // the form
end;

initialization
  RegisterTest(TAboutTest);
end.
