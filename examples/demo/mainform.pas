unit mainform;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus,
  tyControls.Controller, tyControls.Button, tyControls.TyLabel,
  tyControls.Edit, tyControls.CheckBox, tyControls.Panel,
  tyControls.ComboBox, tyControls.ScrollBar, tyControls.Form,
  tyControls.ListBox, tyControls.ProgressBar, tyControls.ToggleSwitch,
  tyControls.TrackBar, tyControls.GroupBox, tyControls.TabControl,
  tyControls.SpinEdit, tyControls.Memo, tyControls.Menu;
type

  { TDemoMainForm ᾿all controls are placed in the designer (mainform.lfm),
    including the docked TTyTitleBar (associated via the form's TitleBar
    property), the TabControl's tabs, TTySpinEdit and TTyMemo. }

  TDemoMainForm = class(TTyForm)
    Controller: TTyStyleController;
    TyButton1: TTyButton;
    TyTitleBar1: TTyTitleBar;
    BtnLight: TTyButton;
    BtnDark: TTyButton;
    BtnShowcase: TTyButton;
    BtnGreen: TTyButton;
    BtnAuto: TTyButton;
    BtnSystem: TTyButton;
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
    SpinKind: TTySpinEdit;
    Memo1: TTyMemo;
    MainMenu1: TMainMenu;
    MnuFile: TMenuItem;
    MnuFileNew: TMenuItem;
    MnuFileOpen: TMenuItem;
    MnuFileSep: TMenuItem;
    MnuFileExit: TMenuItem;
    MnuEdit: TMenuItem;
    MnuEditCut: TMenuItem;
    MnuEditCopy: TMenuItem;
    MnuEditPaste: TMenuItem;
    MnuView: TMenuItem;
    MnuViewToggle: TMenuItem;
    MnuViewMore: TMenuItem;
    MnuViewMoreA: TMenuItem;
    MnuViewMoreB: TMenuItem;
    TyMenuBar1: TTyMenuBar;
    PopupCtx: TTyPopupMenu;
    PopupCtxHello: TMenuItem;
    PopupCtxAgree: TMenuItem;
    procedure FormCreate(Sender: TObject);
    procedure MnuViewToggleClick(Sender: TObject);
    procedure MnuFileExitClick(Sender: TObject);
    procedure PopupCtxHelloClick(Sender: TObject);
    procedure PopupCtxAgreeClick(Sender: TObject);
    procedure BtnLightClick(Sender: TObject);
    procedure BtnDarkClick(Sender: TObject);
    procedure BtnShowcaseClick(Sender: TObject);
    procedure BtnGreenClick(Sender: TObject);
    procedure BtnAutoClick(Sender: TObject);
    procedure BtnSystemClick(Sender: TObject);
    procedure TrackBar1Change(Sender: TObject);
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
  // exe 扜目录向上逐级查找 themes/，对以下位置均健壮：
  //   <repo>/examples/demo/demo（工程目录）
  //   <repo>/examples/demo/lib/<cpu>-<os>/demo（lazbuild 默认输出ﺿ  //   <repo>/examples/demo/demo.app/Contents/MacOS/demo（macOS 包）
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
  // An explicit theme pick is a MANUAL choice; the Auto/System buttons re-enable
  // OS-follow after calling this (so picking Light/Dark/etc. stops tracking the OS).
  Controller.Follow := tfManual;
  Controller.LoadTheme(ThemeDir + AFile);
  Controller.Changed;

  // Window chrome + backdrop follow the theme via the TyForm token.
  ApplyChromeTheme(Controller);
  if TitleBar <> nil then TitleBar.Caption := 'TyControls Demo';
end;

procedure TDemoMainForm.TrackBar1Change(Sender: TObject);
begin
  if Assigned(Progress1) then
    Progress1.Position := TrackBar1.Position;
end;

procedure TDemoMainForm.FormCreate(Sender: TObject);
begin
  // Controls (incl. the title bar/tabs/spin/memo) come from the .lfm; load the theme.
  // Associate the themed menu bar so the form drives shortcut dispatch (and, on macOS,
  // hands MainMenu1 to the native global menu bar). See TTyForm.MenuBar (Task 6).
  MenuBar := TyMenuBar1;
  ApplyTheme('light.tycss');
end;

procedure TDemoMainForm.MnuViewToggleClick(Sender: TObject);
begin
  // Demonstrates a checked item driving a control: flip the label text + the check mark.
  MnuViewToggle.Checked := not MnuViewToggle.Checked;
  if MnuViewToggle.Checked then
    LblHello.Caption := 'Hello TyControls'
  else
    LblHello.Caption := 'Greeting hidden';
end;

procedure TDemoMainForm.MnuFileExitClick(Sender: TObject);
begin
  Close;
end;

procedure TDemoMainForm.PopupCtxHelloClick(Sender: TObject);
begin
  LblHello.Caption := 'Hello from the context menu';
end;

procedure TDemoMainForm.PopupCtxAgreeClick(Sender: TObject);
begin
  ChkAgree.Checked := not ChkAgree.Checked;
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

procedure TDemoMainForm.BtnGreenClick(Sender: TObject);
begin
  ApplyTheme('green.tycss');
end;

procedure TDemoMainForm.BtnAutoClick(Sender: TObject);
begin
  // auto.tycss is a single-file dual-mode theme (@mode light/dark). Following the
  // system pulls the OS scheme into the active mode so it shows the right variant.
  ApplyTheme('auto.tycss');
  Controller.Follow := tfFollowSystem;
  ApplyChromeTheme(Controller);   // re-resolve chrome for the OS-selected mode
end;

procedure TDemoMainForm.BtnSystemClick(Sender: TObject);
begin
  // system.tycss seeds its accent + mode from the live OS (system-accent/system-mode).
  ApplyTheme('system.tycss');
  Controller.Follow := tfFollowSystem;
  ApplyChromeTheme(Controller);
end;

end.
