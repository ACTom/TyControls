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
  tyControls.SpinEdit, tyControls.Memo, tyControls.Menu, tyControls.BuiltinThemes;
type

  { TDemoMainForm ᾿all controls are placed in the designer (mainform.lfm),
    including the docked TTyTitleBar (associated via the form's TitleBar
    property), the TabControl's tabs, TTySpinEdit and TTyMemo. }

  TDemoMainForm = class(TTyForm)
    Controller: TTyStyleController;
    TyButton1: TTyButton;
    TyTitleBar1: TTyTitleBar;
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
    procedure TrackBar1Change(Sender: TObject);
  private
    ThemeCombo: TTyComboBox;
    BtnApLight, BtnApDark, BtnApAuto, BtnRandom: TTyButton;
    function ThemeDir: string;
    procedure BuildSwitcher;
    procedure ApplyBuiltin(const AName: string);
    procedure ThemeComboChange(Sender: TObject);
    procedure SetAppearance(AFollow: TTyThemeFollow; const AMode: string; ASelected: TTyButton);
    procedure ApLightClick(Sender: TObject);
    procedure ApDarkClick(Sender: TObject);
    procedure ApAutoClick(Sender: TObject);
    procedure RandomClick(Sender: TObject);
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

procedure TDemoMainForm.TrackBar1Change(Sender: TObject);
begin
  if Assigned(Progress1) then
    Progress1.Position := TrackBar1.Position;
end;

procedure TDemoMainForm.FormCreate(Sender: TObject);
begin
  Randomize;                  // 给「随机换肤」一个种子
  // Controls (incl. the title bar/tabs/spin/memo) come from the .lfm; load the theme.
  // Associate the themed menu bar so the form drives shortcut dispatch (and, on macOS,
  // hands MainMenu1 to the native global menu bar). See TTyForm.MenuBar (Task 6).
  MenuBar := TyMenuBar1;
  BuildSwitcher;             // 创建换肤 UI 并设初始主题/外观
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

procedure TDemoMainForm.BuildSwitcher;
var
  names: TStringArray;
  i: Integer;
begin
  TyRegisterBuiltinThemes;

  ThemeCombo := TTyComboBox.Create(Self);
  ThemeCombo.Parent := Self;
  ThemeCombo.SetBounds(16, 8, 160, 28);
  ThemeCombo.Controller := Controller;
  names := TyBuiltinThemeNames;
  for i := 0 to High(names) do ThemeCombo.Items.Add(names[i]);
  ThemeCombo.Items.Add('自定义…');
  ThemeCombo.ItemIndex := 0;                 // default
  ThemeCombo.OnChange := @ThemeComboChange;

  BtnApLight := TTyButton.Create(Self);
  BtnApLight.Parent := Self; BtnApLight.SetBounds(188, 8, 56, 28);
  BtnApLight.Caption := '浅色'; BtnApLight.StyleClass := 'ghost';
  BtnApLight.Controller := Controller; BtnApLight.OnClick := @ApLightClick;

  BtnApDark := TTyButton.Create(Self);
  BtnApDark.Parent := Self; BtnApDark.SetBounds(248, 8, 56, 28);
  BtnApDark.Caption := '深色'; BtnApDark.StyleClass := 'ghost';
  BtnApDark.Controller := Controller; BtnApDark.OnClick := @ApDarkClick;

  BtnApAuto := TTyButton.Create(Self);
  BtnApAuto.Parent := Self; BtnApAuto.SetBounds(308, 8, 84, 28);
  BtnApAuto.Caption := '跟随系统'; BtnApAuto.StyleClass := 'ghost';
  BtnApAuto.Controller := Controller; BtnApAuto.OnClick := @ApAutoClick;

  BtnRandom := TTyButton.Create(Self);
  BtnRandom.Parent := Self; BtnRandom.SetBounds(400, 8, 84, 28);
  BtnRandom.Caption := '随机换肤'; BtnRandom.StyleClass := 'primary';
  BtnRandom.Controller := Controller; BtnRandom.OnClick := @RandomClick;

  // 初始:default 主题 + 跟随系统外观
  ApplyBuiltin('default');
  SetAppearance(tfFollowSystem, '', BtnApAuto);
end;

procedure TDemoMainForm.ApplyBuiltin(const AName: string);
begin
  // 只换主题,不动 Follow/Mode(外观轴由三态独占)。
  Controller.ThemeName := AName;
  ApplyChromeTheme(Controller);
  if TitleBar <> nil then TitleBar.Caption := 'TyControls Demo';
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
  BtnApAuto.Down  := (ASelected = BtnApAuto);
  ApplyChromeTheme(Controller);
end;

procedure TDemoMainForm.ApLightClick(Sender: TObject);
begin SetAppearance(tfManual, 'light', BtnApLight); end;

procedure TDemoMainForm.ApDarkClick(Sender: TObject);
begin SetAppearance(tfManual, 'dark', BtnApDark); end;

procedure TDemoMainForm.ApAutoClick(Sender: TObject);
begin SetAppearance(tfFollowSystem, '', BtnApAuto); end;

procedure TDemoMainForm.RandomClick(Sender: TObject);
var names: TStringArray; i, pick: Integer;
begin
  names := TyBuiltinThemeNames;
  if Length(names) = 0 then Exit;
  pick := ThemeCombo.ItemIndex;
  for i := 0 to 7 do          // 随机取一个不同的内置主题
  begin
    pick := Random(Length(names));
    if pick <> ThemeCombo.ItemIndex then Break;
  end;
  ThemeCombo.ItemIndex := pick;     // 同步下拉(ApplyBuiltin 幂等,OnChange 若再触发也无副作用)
  ApplyBuiltin(names[pick]);
end;

end.
