unit umain;

{ TTyToggleSwitch 示例：
  - 两个开关：第一个默认关闭，第二个默认开启（Checked := True）
  - ON 状态在内部通过 CurrentStates 映射为 :active，主题以此渲染高亮颜色
  - OnChange 事件更新底部状态标签
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.ToggleSwitch, tyControls.TyLabel;

type
  TMainForm = class(TForm)
  private
    FSwitch1: TTyToggleSwitch;
    FSwitch2: TTyToggleSwitch;
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

function BoolToStr(B: Boolean): string;
begin
  if B then Result := '开' else Result := '关';
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Lbl1, Lbl2: TTyLabel;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyToggleSwitch 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 320, 220);

  // 加载主题：未显式指定 Controller 的控件自动使用全局 TyDefaultController
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // 开关一（默认关闭）
  Lbl1 := TTyLabel.Create(Self);
  Lbl1.Parent := Self;
  Lbl1.SetBounds(16, 24, 200, 24);
  Lbl1.Caption := '深色模式：';

  FSwitch1 := TTyToggleSwitch.Create(Self);
  FSwitch1.Parent := Self;
  FSwitch1.SetBounds(220, 24, 44, 24);
  FSwitch1.Checked := False;   // 默认关闭
  FSwitch1.OnChange := @SwitchChange;

  // 开关二（默认开启；ON 映射 :active，主题以高亮色渲染轨道）
  Lbl2 := TTyLabel.Create(Self);
  Lbl2.Parent := Self;
  Lbl2.SetBounds(16, 72, 200, 24);
  Lbl2.Caption := '接收通知：';

  FSwitch2 := TTyToggleSwitch.Create(Self);
  FSwitch2.Parent := Self;
  FSwitch2.SetBounds(220, 72, 44, 24);
  FSwitch2.Checked := True;    // 默认开启，CurrentStates 包含 tysActive
  FSwitch2.OnChange := @SwitchChange;

  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(16, 160, 280, 40);
  UpdateStatus;
end;

procedure TMainForm.SwitchChange(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TMainForm.UpdateStatus;
begin
  FStatus.Caption := Format('深色模式：%s    接收通知：%s',
    [BoolToStr(FSwitch1.Checked), BoolToStr(FSwitch2.Checked)]);
end;

end.
