unit mainform;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, Dialogs, Graphics,
  tyControls.Types, tyControls.StyleModel,
  tyControls.Controller, tyControls.Button, tyControls.TyLabel,
  tyControls.Edit, tyControls.CheckBox, tyControls.Panel,
  tyControls.ComboBox, tyControls.ScrollBar, tyControls.Form,
  tyControls.ListBox, tyControls.ProgressBar, tyControls.ToggleSwitch,
  tyControls.TrackBar, tyControls.GroupBox, tyControls.TabControl,
  tyControls.SpinEdit, tyControls.Memo;
type

  { TDemoMainForm }

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
    GroupBox1: TTyGroupBox;
    ListBox1: TTyListBox;
    Progress1: TTyProgressBar;
    TrackBar1: TTyTrackBar;
    Toggle1: TTyToggleSwitch;
    TabCtrl1: TTyTabControl;
    TySpinEdit1: TTySpinEdit;
    procedure BtnDangerClick(Sender: TObject);
    procedure FormCreate(Sender: TObject);
    procedure BtnLightClick(Sender: TObject);
    procedure BtnDarkClick(Sender: TObject);
    procedure BtnShowcaseClick(Sender: TObject);
    procedure TrackBar1Change(Sender: TObject);
  private
    Spin1: TTySpinEdit;   // v1.9: created in code (gallery demo)
    Memo1: TTyMemo;       // v1.9a: created in code (gallery demo)
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
var
  bg: TTyStyleSet;
begin
  Controller.LoadTheme(ThemeDir + AFile);
  Controller.Changed;

  // Window follows theme: tint the plain TForm from the theme's TyForm token.
  bg := Controller.Model.ResolveStyle('TyForm', '', []);
  if (tpBackground in bg.Present) and (bg.Background.Kind = tfkSolid) then
    Self.Color := TyColorToLCL(bg.Background.Color);
end;

procedure TDemoMainForm.TrackBar1Change(Sender: TObject);
begin
  if Assigned(Progress1) then
    Progress1.Position := TrackBar1.Position;
end;

procedure TDemoMainForm.FormCreate(Sender: TObject);
begin
  ApplyTheme('light.tycss');

  { 多数 gallery 控件已放到 .lfm 中（与顶部控件一致）。TTyTabControl 的页签由
    AddTab 在运行时创建对应的 TTyPanel，尚无法在设计器中定义，故控件本身放在
    .lfm，其页签在此添加。 }
  with TabCtrl1.AddTab('General') do
  begin
    with TTyLabel.Create(Self) do
    begin
      Parent  := TabCtrl1.Pages[0];
      Caption := 'Name:';
      SetBounds(8, 8, 60, 20);
      Controller := Self.Controller;
    end;
    with TTyButton.Create(Self) do
    begin
      Parent  := TabCtrl1.Pages[0];
      Caption := 'OK';
      SetBounds(8, 36, 80, 28);
      Controller := Self.Controller;
    end;
  end;
  TabCtrl1.AddTab('Appearance');
  TabCtrl1.AddTab('About');

  { TTySpinEdit (v1.9): numeric up/down, right column below the group box. }
  Spin1 := TTySpinEdit.Create(Self);
  Spin1.Parent := Self;
  Spin1.SetBounds(460, 362, 120, 28);
  Spin1.MinValue := 0;
  Spin1.MaxValue := 10;
  Spin1.Value := 3;
  Spin1.Controller := Controller;

  { TTyMemo (v1.9a): multi-line editor with auto vertical scrollbar, right column. }
  Memo1 := TTyMemo.Create(Self);
  Memo1.Parent := Self;
  Memo1.SetBounds(460, 400, 165, 140);
  Memo1.Controller := Controller;
  Memo1.Lines.Text :=
    'TTyMemo' + LineEnding +
    'multi-line edit' + LineEnding +
    'Enter / Backspace' + LineEnding +
    'arrows / Home / End' + LineEnding +
    'wheel scrolls' + LineEnding +
    'when overflowing' + LineEnding +
    'the visible rows.';
end;

procedure TDemoMainForm.BtnDangerClick(Sender: TObject);
begin
  ShowMessage('Danger');
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
