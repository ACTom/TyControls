unit mainform;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Button, tyControls.TyLabel,
  tyControls.Edit, tyControls.CheckBox, tyControls.Panel,
  tyControls.ComboBox, tyControls.ScrollBar, tyControls.Form;
type
  TDemoMainForm = class(TForm)
    Controller: TTyStyleController;
    Chrome: TTyFormChrome;
    BtnLight: TTyButton;
    BtnDark: TTyButton;
    BtnShowcase: TTyButton;
    BtnPrimary: TTyButton;
    BtnDanger: TTyButton;
    LblHello: TTyLabel;
    EditName: TTyEdit;
    ChkAgree: TTyCheckBox;
    RadOne: TTyRadioButton;
    PanelBox: TTyPanel;
    ComboKind: TTyComboBox;
    ScrollV: TTyScrollBar;
    procedure FormCreate(Sender: TObject);
    procedure BtnLightClick(Sender: TObject);
    procedure BtnDarkClick(Sender: TObject);
    procedure BtnShowcaseClick(Sender: TObject);
  private
    function ThemeDir: string;
    procedure ApplyTheme(const AFile: string);
  end;
var
  DemoMainForm: TDemoMainForm;
implementation
{$R *.lfm}

function TDemoMainForm.ThemeDir: string;
begin
  Result := ExtractFilePath(ParamStr(0)) + '..' + PathDelim + '..' +
    PathDelim + 'themes' + PathDelim;
end;

procedure TDemoMainForm.ApplyTheme(const AFile: string);
begin
  Controller.LoadTheme(ThemeDir + AFile);
  Controller.Changed;
end;

procedure TDemoMainForm.FormCreate(Sender: TObject);
begin
  ApplyTheme('light.tycss');
end;

procedure TDemoMainForm.BtnLightClick(Sender: TObject);
begin
  ApplyTheme('light.tycss');
end;

procedure TDemoMainForm.BtnDarkClick(Sender: TObject);
begin
  ApplyTheme('dark.tycss');
end;

procedure TDemoMainForm.BtnShowcaseClick(Sender: TObject);
begin
  ApplyTheme('showcase.tycss');
end;

end.
