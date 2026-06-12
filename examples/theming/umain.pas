unit umain;

{ 运行时主题热切换示例：
  - 三个按钮分别切换 light.tycss / dark.tycss / custom.tycss
  - TyDefaultController.LoadTheme 内部调用 Changed()，
    Changed() 遍历已注册控件并全部 Invalidate——无需额外调用。
  - custom.tycss 通过 FindFileUpwards 从 exe 目录向上搜索
    'examples/theming/custom.tycss'（兼容 lib/<cpu>-<os>/ 构建输出）。
  纯代码 UI（无 .lfm）。}

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller,
  tyControls.Button, tyControls.TyLabel,
  tyControls.Edit, tyControls.CheckBox;

type
  TMainForm = class(TForm)
  private
    FStatusLabel: TTyLabel;
    { 主题切换按钮 }
    procedure SwitchLight(Sender: TObject);
    procedure SwitchDark(Sender: TObject);
    procedure SwitchCustom(Sender: TObject);
    procedure ApplyTheme(const APath: string);
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

{ 向上搜索 RelPath（相对路径片段，用 '/' 分隔），返回首个存在的绝对路径；
  找不到返回空字符串。用于定位 examples/theming/custom.tycss。 }
function FindFileUpwards(const ARelPath: string): string;
var
  Dir, Target, NormRel: string;
  i: Integer;
begin
  NormRel := StringReplace(ARelPath, '/', PathDelim, [rfReplaceAll]);
  Dir := ExtractFilePath(ExpandFileName(ParamStr(0)));
  for i := 1 to 10 do
  begin
    Target := Dir + NormRel;
    if FileExists(Target) then
      Exit(Target);
    Dir := ExtractFilePath(ExcludeTrailingPathDelimiter(Dir));
    if Dir = '' then Break;
  end;
  Result := '';
end;

constructor TMainForm.Create(AOwner: TComponent);

  function MakeSwitch(const ACaption, AClass: string; ALeft: Integer;
    AHandler: TNotifyEvent): TTyButton;
  begin
    Result := TTyButton.Create(Self);
    Result.Parent := Self;
    Result.SetBounds(ALeft, 16, 100, 32);
    Result.Caption := ACaption;
    Result.StyleClass := AClass;
    Result.OnClick := AHandler;
  end;

var
  SampleBtn:   TTyButton;
  SampleLbl:   TTyLabel;
  SampleEdit:  TTyEdit;
  SampleCheck: TTyCheckBox;
  DisabledBtn: TTyButton;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'TyControls 运行时主题切换';
  Position := poScreenCenter;
  SetBounds(0, 0, 440, 260);

  // 初始主题
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // ── 主题切换按钮行 ──────────────────────────────────────────
  MakeSwitch('亮色 Light',   'primary', 16,  @SwitchLight);
  MakeSwitch('暗色 Dark',    '',        128, @SwitchDark);
  MakeSwitch('自定义 Custom','',        240, @SwitchCustom);

  // 当前主题路径提示
  FStatusLabel := TTyLabel.Create(Self);
  FStatusLabel.Parent := Self;
  FStatusLabel.SetBounds(16, 56, 400, 18);
  FStatusLabel.Caption := '当前主题：light.tycss';

  // ── 示例控件区 ────────────────────────────────────────────
  SampleLbl := TTyLabel.Create(Self);
  SampleLbl.Parent := Self;
  SampleLbl.SetBounds(16, 88, 200, 20);
  SampleLbl.Caption := '示例标签 TTyLabel';

  SampleBtn := TTyButton.Create(Self);
  SampleBtn.Parent := Self;
  SampleBtn.SetBounds(16, 116, 120, 32);
  SampleBtn.Caption := '示例按钮';
  SampleBtn.StyleClass := 'primary';

  DisabledBtn := TTyButton.Create(Self);
  DisabledBtn.Parent := Self;
  DisabledBtn.SetBounds(148, 116, 100, 32);
  DisabledBtn.Caption := '禁用态';
  DisabledBtn.Enabled := False;

  SampleEdit := TTyEdit.Create(Self);
  SampleEdit.Parent := Self;
  SampleEdit.SetBounds(16, 160, 200, 28);
  SampleEdit.Text := '可编辑文本框';

  SampleCheck := TTyCheckBox.Create(Self);
  SampleCheck.Parent := Self;
  SampleCheck.SetBounds(16, 200, 160, 24);
  SampleCheck.Caption := '复选框示例';
  SampleCheck.Checked := True;
end;

procedure TMainForm.ApplyTheme(const APath: string);
begin
  // LoadTheme 内部：FModel.LoadFromFile → Changed()
  // Changed() 遍历 FControls 列表并 Invalidate 所有已注册控件
  // → 无需额外调用 TyDefaultController.Changed
  TyDefaultController.LoadTheme(APath);
  FStatusLabel.Caption := '当前主题：' + ExtractFileName(APath);
end;

procedure TMainForm.SwitchLight(Sender: TObject);
begin
  ApplyTheme(ThemesDir + 'light.tycss');
end;

procedure TMainForm.SwitchDark(Sender: TObject);
begin
  ApplyTheme(ThemesDir + 'dark.tycss');
end;

procedure TMainForm.SwitchCustom(Sender: TObject);
var
  Path: string;
begin
  // 优先从 exe 向上查找仓库内的 examples/theming/custom.tycss
  Path := FindFileUpwards('examples/theming/custom.tycss');
  if Path = '' then
  begin
    // 回退：尝试与 exe 同目录（部署场景：将 custom.tycss 复制到 exe 旁）
    Path := ExtractFilePath(ExpandFileName(ParamStr(0))) + 'custom.tycss';
    if not FileExists(Path) then
    begin
      FStatusLabel.Caption := '未找到 custom.tycss（已找：examples/theming/ 或 exe 同级目录）';
      Exit;
    end;
  end;
  ApplyTheme(Path);
end;

end.
