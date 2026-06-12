unit mainform;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Button, tyControls.TyLabel,
  tyControls.Edit, tyControls.CheckBox, tyControls.Panel,
  tyControls.ComboBox, tyControls.ScrollBar, tyControls.Form,
  tyControls.ListBox, tyControls.ProgressBar, tyControls.ToggleSwitch,
  tyControls.TrackBar, tyControls.GroupBox;
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
    ListBox1: TTyListBox;
    Progress1: TTyProgressBar;
    Toggle1: TTyToggleSwitch;
    TrackBar1: TTyTrackBar;
    GroupBox1: TTyGroupBox;
    procedure TrackBar1Change(Sender: TObject);
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

procedure TDemoMainForm.TrackBar1Change(Sender: TObject);
begin
  if Assigned(Progress1) then
    Progress1.Position := TrackBar1.Position;
end;

procedure TDemoMainForm.FormCreate(Sender: TObject);
begin
  ApplyTheme('light.tycss');

  { -- v1.1 gallery controls, created entirely in code -- }

  { TTyGroupBox: hosts the existing radio and a new label; sits right column }
  GroupBox1 := TTyGroupBox.Create(Self);
  GroupBox1.Parent := Self;
  GroupBox1.Caption := 'Options';
  GroupBox1.Left   := 460;
  GroupBox1.Top    := 240;
  GroupBox1.Width  := 160;
  GroupBox1.Height := 110;
  GroupBox1.Controller := Controller;

  { TTyListBox: a few items, left column below ComboBox }
  ListBox1 := TTyListBox.Create(Self);
  ListBox1.Parent := Self;
  ListBox1.Left   := 16;
  ListBox1.Top    := 270;
  ListBox1.Width  := 200;
  ListBox1.Height := 110;
  ListBox1.Controller := Controller;
  ListBox1.Items.Add('Alpha');
  ListBox1.Items.Add('Beta');
  ListBox1.Items.Add('Gamma');
  ListBox1.Items.Add('Delta');
  ListBox1.ItemIndex := 0;

  { TTyProgressBar: horizontal, middle column }
  Progress1 := TTyProgressBar.Create(Self);
  Progress1.Parent := Self;
  Progress1.Left     := 240;
  Progress1.Top      := 240;
  Progress1.Width    := 200;
  Progress1.Height   := 22;
  Progress1.Position := 60;
  Progress1.Controller := Controller;

  { TTyTrackBar: below the progress bar; OnChange drives the progress bar }
  TrackBar1 := TTyTrackBar.Create(Self);
  TrackBar1.Parent := Self;
  TrackBar1.Left     := 240;
  TrackBar1.Top      := 278;
  TrackBar1.Width    := 200;
  TrackBar1.Height   := 30;
  TrackBar1.Position := 60;
  TrackBar1.OnChange := @TrackBar1Change;
  TrackBar1.Controller := Controller;

  { TTyToggleSwitch: below trackbar }
  Toggle1 := TTyToggleSwitch.Create(Self);
  Toggle1.Parent := Self;
  Toggle1.Left    := 240;
  Toggle1.Top     := 324;
  Toggle1.Width   := 56;
  Toggle1.Height  := 28;
  Toggle1.Checked := True;
  Toggle1.Controller := Controller;

  { Enlarge form to accommodate new row of controls }
  Height := 420;
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
