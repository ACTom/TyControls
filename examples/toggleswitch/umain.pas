unit umain;

{ TTyToggleSwitch 示例：
  - Checked：默认关/开两种初始状态（ON 经 CurrentStates 映射为 :active，主题渲染高亮轨道）
  - Caption：开关右侧内建文本标签
  - Enabled：禁用状态的开关不可点击/切换
  - OnChange：切换时刷新底部状态标签
  纯代码创建 UI（无 .lfm），主窗体为 TTyForm + TTyTitleBar，主题由全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.ToggleSwitch, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FSwitchDark: TTyToggleSwitch;    // 默认关闭
    FSwitchNotify: TTyToggleSwitch;  // 默认开启
    FSwitchCaption: TTyToggleSwitch; // 带 Caption
    FSwitchDisabled: TTyToggleSwitch; // 禁用
    FStatus: TTyLabel;
    procedure SwitchChange(Sender: TObject);
    procedure UpdateStatus;
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ 从 exe 所在目录向上查找仓库的 themes/ 目录（兼容 lib/<cpu>-<os>/ 与 .app 包） }
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

function OnOff(B: Boolean): string;
begin
  if B then Result := '开' else Result := '关';
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
  LblDark, LblNotify: TTyLabel;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm：无边框 + 持久化引擎
  Caption := 'ToggleSwitch 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 400, 300);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // 先加载主题

  Bar := TTyTitleBar.Create(Self);         // Owner=Self → 自动关联为 TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'ToggleSwitch  · TyControls';

  // 开关一：默认关闭
  LblDark := TTyLabel.Create(Self);
  LblDark.Parent := Self;
  LblDark.SetBounds(24, 56, 220, 24);
  LblDark.Caption := '深色模式：';

  FSwitchDark := TTyToggleSwitch.Create(Self);
  FSwitchDark.Parent := Self;
  FSwitchDark.SetBounds(250, 56, 44, 24);
  FSwitchDark.Checked := False;            // 默认关闭
  FSwitchDark.OnChange := @SwitchChange;

  // 开关二：默认开启（ON → :active，主题以高亮色渲染）
  LblNotify := TTyLabel.Create(Self);
  LblNotify.Parent := Self;
  LblNotify.SetBounds(24, 100, 220, 24);
  LblNotify.Caption := '接收通知：';

  FSwitchNotify := TTyToggleSwitch.Create(Self);
  FSwitchNotify.Parent := Self;
  FSwitchNotify.SetBounds(250, 100, 44, 24);
  FSwitchNotify.Checked := True;           // 默认开启，CurrentStates 含 tysActive
  FSwitchNotify.OnChange := @SwitchChange;

  // 开关三：内建 Caption（文本绘制在开关右侧）
  FSwitchCaption := TTyToggleSwitch.Create(Self);
  FSwitchCaption.Parent := Self;
  FSwitchCaption.SetBounds(24, 144, 220, 24);
  FSwitchCaption.Caption := '自动保存';    // Caption 属性
  FSwitchCaption.Checked := True;
  FSwitchCaption.OnChange := @SwitchChange;

  // 开关四：禁用状态（不可点击/切换）
  FSwitchDisabled := TTyToggleSwitch.Create(Self);
  FSwitchDisabled.Parent := Self;
  FSwitchDisabled.SetBounds(24, 188, 220, 24);
  FSwitchDisabled.Caption := '试验功能（禁用）';
  FSwitchDisabled.Checked := False;
  FSwitchDisabled.Enabled := False;        // Enabled=False → 禁用
  FSwitchDisabled.OnChange := @SwitchChange;

  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(24, 240, 360, 40);
  UpdateStatus;

  ApplyChromeTheme(TyDefaultController);   // 最后统一主题化整个 chrome + 窗体背景
end;

procedure TMainForm.SwitchChange(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TMainForm.UpdateStatus;
begin
  FStatus.Caption := Format('深色模式：%s   接收通知：%s   自动保存：%s',
    [OnOff(FSwitchDark.Checked), OnOff(FSwitchNotify.Checked),
     OnOff(FSwitchCaption.Checked)]);
end;

end.
