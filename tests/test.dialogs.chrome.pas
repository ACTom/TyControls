unit test.dialogs.chrome;
{$mode objfpc}{$H+}
{ Regression tests for the TTyDialog base-class chrome + theme fix (fix/dialog-chrome-theme).

  A CreateNew dialog used to render with NO title bar (TTyForm is born chrome-less, and
  CreateNew never associated a TTyTitleBar) and in the built-in default theme (its Controller
  was nil, so its controls fell back to TyDefaultController instead of the app's controller).

  These tests are construct-only (NO Show / ShowModal — win32-1407 headless):
    1. the base ctor associates a title bar (so GetTitleHeight > 0 and ContentRect.Top insets it);
    2. setting Caption syncs the title-bar caption (TextChanged mirror);
    3. ApplyControllerNow adopts the owner form's controller onto the dialog AND its children. }
interface
uses
  Classes, SysUtils, Types, Controls, Dialogs, fpcunit, testregistry,
  tyControls.Types, tyControls.Form, tyControls.Controller,
  tyControls.Dialogs, tyControls.Button;

type
  TDialogChromeTest = class(TTestCase)
  published
    procedure TestTitleBarAssociatedAndInsetsContent;
    procedure TestCaptionSyncsToTitleBar;
    procedure TestOwnerControllerAppliedToDialogAndChildren;
    procedure TestNoOwnerControllerLeavesControllerNil;
  end;

implementation

{ 1. The base ctor must create + associate a title bar, so the dialog gets a caption strip.
     Once a bar exists, GetTitleHeight (published as TitleHeight) returns its height and
     ContentRect.Top gains that inset (content sits BELOW the caption, not at the top). }
procedure TDialogChromeTest.TestTitleBarAssociatedAndInsetsContent;
var d: TTyDialog; cr: TRect;
begin
  d := TyBuildMessageDialog('Hello', mtInformation, [mbOK], 'Info');
  try
    AssertTrue('title bar associated', d.TitleBar <> nil);
    AssertTrue('title height > 0', d.TitleHeight > 0);
    cr := d.ContentRect;
    AssertTrue('content top insets the title height',
      cr.Top >= d.TitleHeight);
  finally
    d.Free;
  end;
end;

{ 2. TextChanged mirrors Caption onto the bar (so a builder's Result.Caption := ... shows). }
procedure TDialogChromeTest.TestCaptionSyncsToTitleBar;
var d: TTyDialog;
begin
  d := TTyDialog.CreateNew(nil);
  try
    d.Caption := 'Hi';
    AssertEquals('title bar caption follows form caption', 'Hi', d.TitleBar.Caption);
    d.Caption := 'Renamed';
    AssertEquals('title bar caption re-syncs', 'Renamed', d.TitleBar.Caption);
  finally
    d.Free;
  end;
end;

{ 3. ApplyControllerNow (the DoShow seam) must adopt the owner form's controller onto the
     dialog itself AND recurse it onto the body/button-bar child controls. }
procedure TDialogChromeTest.TestOwnerControllerAppliedToDialogAndChildren;
var
  owner: TTyForm;
  ctrl: TTyStyleController;
  d: TTyDialog;
  btn: TTyButton;
begin
  owner := TTyForm.CreateNew(nil);
  ctrl := TTyStyleController.Create(owner);   // owned by the form -> freed together, no dangling ref
  d := nil;
  try
    owner.Controller := ctrl;                 // theme the "app" onto its own controller
    d := TTyDialog.CreateNew(owner);          // owner-parented dialog (Controller starts nil)
    d.AddButton('OK', mrOk, True, False);     // a known child on the button bar
    AssertTrue('precondition: at least one button', d.ButtonCount >= 1);

    d.ApplyControllerNow;                      // the DoShow seam, driven without Show

    AssertTrue('dialog adopts the owner controller', d.Controller = ctrl);
    btn := d.Buttons[0];
    AssertTrue('a child button adopts the owner controller', btn.Controller = ctrl);
  finally
    d.Free;
    owner.Free;   // frees ctrl (owned)
  end;
end;

{ 4. With no owner controller and no themed main form, the seam is a no-op (Controller stays nil,
     so the dialog keeps falling back to the built-in default -- unchanged behaviour, no crash). }
procedure TDialogChromeTest.TestNoOwnerControllerLeavesControllerNil;
var d: TTyDialog;
begin
  d := TTyDialog.CreateNew(nil);   // no owner form, no controller
  try
    d.ApplyControllerNow;
    AssertTrue('controller stays nil when none resolves', d.Controller = nil);
  finally
    d.Free;
  end;
end;

initialization
  RegisterTest(TDialogChromeTest);
end.
