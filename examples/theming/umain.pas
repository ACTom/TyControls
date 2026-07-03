unit umain;

{ 运行时主题热切换示例（TTyForm + TTyTitleBar 版）：
  - 顶部三个按钮分别 LoadTheme light.tycss / dark.tycss / green.tycss；
  - LoadTheme 内部会调用 Changed()，遍历所有已注册控件并 Invalidate，
    因此示例区的按钮 / 文本框 / 复选框 / 进度条会「实时」重新着色；
  - 同时调用 ApplyChromeTheme 让窗口 chrome（标题栏 + 窗体背景）一并换肤；
  - 一个状态标签实时显示当前主题名。
  纯代码 UI（无 .lfm）。}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.Button, tyControls.TyLabel,
  tyControls.Edit, tyControls.CheckBox, tyControls.ProgressBar;

type
  TMainForm = class(TTyForm)
  private
    FStatusLabel: TTyLabel;
    { 主题切换事件 }
    procedure SwitchLight(Sender: TObject);
    procedure SwitchDark(Sender: TObject);
    procedure SwitchGreen(Sender: TObject);
    procedure ApplyTheme(const AFileName: string);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ 从 exe 所在目录向上查找 themes/ 目录 }
function ThemesDir: string;
var
  Dir: string;
  i: Integer;
begin
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 8 do
  begin
    if DirectoryExists(Dir + 'themes') then
      Exit(Dir + 'themes' + PathDelim);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := 'themes' + PathDelim;
end;

constructor TMainForm.Create(AOwner: TComponent);

  function MakeSwitch(const ACaption, AClass: string; ALeft: Integer;
    AHandler: TNotifyEvent): TTyButton;
  begin
    Result := TTyButton.Create(Self);
    Result.Parent := Self;
    Result.SetBounds(ALeft, 52, 116, 34);
    Result.Caption := ACaption;
    Result.StyleClass := AClass;
    Result.OnClick := AHandler;
  end;

var
  Bar:         TTyTitleBar;
  SampleLbl:   TTyLabel;
  SampleBtn:   TTyButton;
  GhostBtn:    TTyButton;
  DisabledBtn: TTyButton;
  SampleEdit:  TTyEdit;
  SampleCheck: TTyCheckBox;
  Progress:    TTyProgressBar;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm：无边框 + 常驻绘制引擎
  Caption := '主题系统 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 470, 340);

  // 先加载初始主题，再建 chrome
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  Bar := TTyTitleBar.Create(Self);         // Owner=Self → 自动关联为 TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := '主题系统  · TyControls';

  // ── 主题切换按钮行（点击后 LoadTheme + ApplyChromeTheme 实时换肤）──
  MakeSwitch('亮色 Light', 'primary', 16,  @SwitchLight);
  MakeSwitch('暗色 Dark',  '',        148, @SwitchDark);
  MakeSwitch('绿色 Green', '',        280, @SwitchGreen);

  // 当前主题提示
  FStatusLabel := TTyLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.SetBounds(16, 96, 430, 20);
  FStatusLabel.Caption := '当前主题：light.tycss';

  // ── 示例控件区：这些控件随主题实时重新着色 ──────────────
  SampleLbl := TTyLabel.Create(Self);
  SampleLbl.Parent := Self;
  SampleLbl.SetBounds(16, 128, 300, 20);
  SampleLbl.Caption := '示例标签 TTyLabel';

  SampleBtn := TTyButton.Create(Self);
  SampleBtn.Parent := Self;
  SampleBtn.SetBounds(16, 156, 120, 34);
  SampleBtn.Caption := '主要按钮';
  SampleBtn.StyleClass := 'primary';

  GhostBtn := TTyButton.Create(Self);
  GhostBtn.Parent := Self;
  GhostBtn.SetBounds(148, 156, 100, 34);
  GhostBtn.Caption := '幽灵按钮';
  GhostBtn.StyleClass := 'ghost';

  DisabledBtn := TTyButton.Create(Self);
  DisabledBtn.Parent := Self;
  DisabledBtn.SetBounds(260, 156, 100, 34);
  DisabledBtn.Caption := '禁用态';
  DisabledBtn.Enabled := False;

  SampleEdit := TTyEdit.Create(Self);
  SampleEdit.Parent := Self;
  SampleEdit.SetBounds(16, 204, 220, 30);
  SampleEdit.Text := '可编辑文本框';

  SampleCheck := TTyCheckBox.Create(Self);
  SampleCheck.Parent := Self;
  SampleCheck.SetBounds(260, 208, 160, 24);
  SampleCheck.Caption := '复选框示例';
  SampleCheck.Checked := True;

  Progress := TTyProgressBar.Create(Self);
  Progress.Parent := Self;
  Progress.SetBounds(16, 252, 420, 18);
  Progress.Min := 0;
  Progress.Max := 100;
  Progress.Position := 65;

  ApplyChromeTheme(TyDefaultController);    // 最后统一给 chrome + 窗体背景换肤
end;

procedure TMainForm.ApplyTheme(const AFileName: string);
begin
  // LoadTheme 内部：FModel.LoadFromFile → Changed()，
  // Changed() 遍历已注册控件并全部 Invalidate → 示例控件实时换肤；
  // 再调 ApplyChromeTheme 让标题栏 + 窗体背景一起跟随。
  TyDefaultController.LoadTheme(ThemesDir + AFileName);
  ApplyChromeTheme(TyDefaultController);
  FStatusLabel.Caption := '当前主题：' + AFileName;
end;

procedure TMainForm.SwitchLight(Sender: TObject);
begin
  ApplyTheme('light.tycss');
end;

procedure TMainForm.SwitchDark(Sender: TObject);
begin
  ApplyTheme('dark.tycss');
end;

procedure TMainForm.SwitchGreen(Sender: TObject);
begin
  ApplyTheme('green.tycss');
end;

end.
