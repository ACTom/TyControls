unit test.controls.panel;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Types, Graphics, Forms, Controls, StdCtrls, fpcunit, testregistry,
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
    procedure TestPaintSmoke;
  end;
implementation
type
  TPanelAccess = class(TTyPanel)
  public
    procedure SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
  end;
procedure TPanelAccess.SmokeRender(ACanvas: TCanvas; const ARect: TRect; APPI: Integer);
begin
  RenderTo(ACanvas, ARect, APPI);
end;
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
procedure TTyPanelTest.TestPaintSmoke;
var
  Acc: TPanelAccess;
  Bmp: TBitmap;
begin
  Acc := TPanelAccess.Create(FForm);
  Acc.Parent := FForm;
  Acc.Caption := 'Panel';
  Bmp := TBitmap.Create;
  try
    Bmp.PixelFormat := pf32bit;
    Bmp.SetSize(120, 60);
    Acc.SmokeRender(Bmp.Canvas, Rect(0, 0, 120, 60), 96);
    AssertTrue('panel RenderTo executed without exception', True);
  finally
    Bmp.Free;
  end;
end;
initialization
  RegisterTest(TTyPanelTest);
end.
