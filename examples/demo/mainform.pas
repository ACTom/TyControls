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
var
  Dir: string;
  i: Integer;
begin
  // 从 exe 所在目录向上逐级查找 themes/，对以下位置均健壮：
  //   <repo>/examples/demo/demo（工程目录）
  //   <repo>/examples/demo/lib/<cpu>-<os>/demo（lazbuild 默认输出）
  //   <repo>/examples/demo/demo.app/Contents/MacOS/demo（macOS 包）
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then
      Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim; // 兜底：相对当前目录
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
