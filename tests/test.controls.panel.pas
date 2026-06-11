unit test.controls.panel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, StdCtrls, fpcunit, testregistry,
  tyControls.Base, tyControls.Panel;
type
  TTyPanelTest = class(TTestCase)
  private
    FForm: TForm;
    FPanel: TTyPanel;
  protected
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestTypeKey;
    procedure TestDefaultCaptionEmpty;
    procedure TestImplementsStyleable;
    procedure TestHostsChild;
  end;
implementation
procedure TTyPanelTest.SetUp;
begin
  FForm := TForm.CreateNew(nil);
  FPanel := TTyPanel.Create(FForm);
  FPanel.Parent := FForm;
end;
procedure TTyPanelTest.TearDown;
begin
  FForm.Free;
end;
procedure TTyPanelTest.TestTypeKey;
begin
  AssertEquals('TyPanel', FPanel.GetStyleTypeKey);
end;
procedure TTyPanelTest.TestDefaultCaptionEmpty;
begin
  AssertEquals('', FPanel.Caption);
end;
procedure TTyPanelTest.TestImplementsStyleable;
var
  Styleable: ITyStyleable;
begin
  AssertTrue('TTyPanel must support ITyStyleable',
    Supports(FPanel, ITyStyleable, Styleable));
  AssertEquals('TyPanel', Styleable.GetStyleTypeKey);
end;
procedure TTyPanelTest.TestHostsChild;
var
  Child: TButton;
begin
  Child := TButton.Create(FPanel);
  Child.Parent := FPanel;
  AssertSame('child parent must be the panel', FPanel, Child.Parent);
  AssertEquals('panel must report one child control', 1, FPanel.ControlCount);
end;
initialization
  RegisterTest(TTyPanelTest);
end.
