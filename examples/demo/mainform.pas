unit mainform;
{$mode objfpc}{$H+}
interface
uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, Menus, ComCtrls,
  tyControls.Controller, tyControls.Button, tyControls.TyLabel,
  tyControls.Edit, tyControls.CheckBox, tyControls.Panel,
  tyControls.ComboBox, tyControls.ScrollBar, tyControls.Form,
  tyControls.ListBox, tyControls.ProgressBar, tyControls.ToggleSwitch,
  tyControls.TrackBar, tyControls.GroupBox, tyControls.PageControl, tyControls.TabSheet,
  tyControls.SpinEdit, tyControls.Memo, tyControls.Menu, tyControls.BuiltinThemes;
type

  { TDemoMainForm — ALL controls live in the designer (mainform.lfm), including the docked
    TTyTitleBar, the theme switcher (ThemeCombo + appearance buttons + random), the
    PageControl's pages, TTySpinEdit and TTyMemo. Code only does logic (data + handlers);
    it NEVER creates UI controls (project rule: demo UI is edited in the .lfm only). }

  TDemoMainForm = class(TTyForm)
    Controller: TTyStyleController;
    TyButton1: TTyButton;
    TyButton2: TTyButton;
    TyEdit1: TTyEdit;
    TyTitleBar1: TTyTitleBar;
    ThemeCombo: TTyComboBox;
    BtnApLight: TTyButton;
    BtnApDark: TTyButton;
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
    TabCtrl1: TTyPageControl;
    TyTabSheet1: TTyTabSheet;
    TyTabSheet2: TTyTabSheet;
    TyTabSheet3: TTyTabSheet;
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
    procedure GroupBox1Click(Sender: TObject);
    procedure MnuViewToggleClick(Sender: TObject);
    procedure MnuFileExitClick(Sender: TObject);
    procedure PopupCtxHelloClick(Sender: TObject);
    procedure PopupCtxAgreeClick(Sender: TObject);
    procedure TrackBar1Change(Sender: TObject);
    procedure ThemeComboChange(Sender: TObject);
    procedure ApLightClick(Sender: TObject);
    procedure ApDarkClick(Sender: TObject);
    procedure ApAutoClick(Sender: TObject);
    procedure RandomClick(Sender: TObject);
  private
    function ThemeDir: string;
    procedure InitThemes;
    procedure ApplyBuiltin(const AName: string);
    procedure SetAppearance(AFollow: TTyThemeFollow; const AMode: string; ASelected: TTyButton);
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
  // 从 exe 所在目录向上逐级查找 themes/(兼容工程目录 / lib/<cpu>-<os>/ / macOS .app 包)。
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then
      Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim; // 兜底:相对当前目录
end;

procedure TDemoMainForm.TrackBar1Change(Sender: TObject);
begin
  if Assigned(Progress1) then
    Progress1.Position := TrackBar1.Position;
end;

procedure TDemoMainForm.FormCreate(Sender: TObject);
begin
  Randomize;                  // 给「随机换肤」一个种子
  // Controls (incl. the title bar/tabs/spin/memo AND the theme switcher) come from the
  // .lfm. Associate the themed menu bar (shortcut dispatch / macOS global menu), then
  // fill the theme dropdown + set the initial theme/appearance — data only, no UI build.
  MenuBar := TyMenuBar1;
  InitThemes;
end;

procedure TDemoMainForm.GroupBox1Click(Sender: TObject);
begin

end;

procedure TDemoMainForm.InitThemes;
var
  names: TStringArray;
  i: Integer;
begin
  // 控件全部来自 .lfm;这里只填数据 + 设初始状态,绝不创建控件。
  TyRegisterBuiltinThemes;
  names := TyBuiltinThemeNames;
  ThemeCombo.Items.Clear;
  for i := 0 to High(names) do ThemeCombo.Items.Add(names[i]);
  ThemeCombo.Items.Add('自定义…');
  ThemeCombo.ItemIndex := 0;                 // default
  ApplyBuiltin('default');
  SetAppearance(tfFollowSystem, '', nil);   // 初始外观:跟随系统
end;

procedure TDemoMainForm.ApplyBuiltin(const AName: string);
begin
  // 只换主题,不动 Follow/Mode(外观轴由三态独占)。
  Controller.ThemeName := AName;
  ApplyChromeTheme(Controller);
end;

procedure TDemoMainForm.ThemeComboChange(Sender: TObject);
var idx: Integer; dlg: TOpenDialog;
begin
  idx := ThemeCombo.ItemIndex;
  if idx < 0 then Exit;
  if ThemeCombo.Items[idx] = '自定义…' then
  begin
    dlg := TOpenDialog.Create(Self);
    try
      dlg.Filter := 'TyControls 主题 (*.tycss)|*.tycss';
      dlg.InitialDir := ThemeDir;
      if dlg.Execute then
      begin
        Controller.ThemeFile := dlg.FileName;   // 自定义文件(REPLACE)
        ApplyChromeTheme(Controller);
      end;
    finally dlg.Free; end;
  end
  else
    ApplyBuiltin(ThemeCombo.Items[idx]);
end;

procedure TDemoMainForm.SetAppearance(AFollow: TTyThemeFollow; const AMode: string;
  ASelected: TTyButton);
begin
  Controller.Follow := AFollow;
  if AFollow = tfManual then Controller.Mode := AMode;   // 跟随系统时 Mode 由 OS 决定
  // 三态互斥:用 ghost 的 Down 选中态高亮当前外观。
  BtnApLight.Down := (ASelected = BtnApLight);
  BtnApDark.Down  := (ASelected = BtnApDark);
  ApplyChromeTheme(Controller);
end;

procedure TDemoMainForm.ApLightClick(Sender: TObject);
begin SetAppearance(tfManual, 'light', BtnApLight); end;

procedure TDemoMainForm.ApDarkClick(Sender: TObject);
begin SetAppearance(tfManual, 'dark', BtnApDark); end;

procedure TDemoMainForm.ApAutoClick(Sender: TObject);
begin
end;

procedure TDemoMainForm.RandomClick(Sender: TObject);
begin

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

end.
