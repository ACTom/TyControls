unit umain;

{ TTyLabel 最小示例：
  - TTyLabel 是无边框纯文本控件，文字颜色来自主题的 color 属性
  - 可通过 StyleClass 选择不同主题变体（空字符串 = 基础样式）
  - Enabled:=False 触发 :disabled 状态（主题里通常变灰）
  - TTyButton 点击后修改某个 label 的 Caption
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Button, tyControls.TyLabel;

type
  TMainForm = class(TForm)
  private
    FClickCount: Integer;
    FDynLabel: TTyLabel;   // 被按钮动态修改的 label
    procedure ButtonClicked(Sender: TObject);
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

constructor TMainForm.Create(AOwner: TComponent);
var
  LBase, LDisabled: TTyLabel;
  Btn: TTyButton;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyLabel 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 360, 260);

  // 加载主题：未显式指定 Controller 的控件自动使用全局 TyDefaultController
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // 基础样式（StyleClass 为空 = TyLabel 默认外观）
  LBase := TTyLabel.Create(Self);
  LBase.Parent := Self;
  LBase.SetBounds(24, 24, 280, 24);
  LBase.Caption := '基础标签（无 StyleClass）';
  LBase.StyleClass := '';   // 空字符串 = 主题中 TyLabel 的默认规则

  // 禁用态：Enabled:=False 会触发 :disabled 伪类，主题通常降低不透明度
  LDisabled := TTyLabel.Create(Self);
  LDisabled.Parent := Self;
  LDisabled.SetBounds(24, 60, 280, 24);
  LDisabled.Caption := '已禁用的标签';
  LDisabled.Enabled := False;

  // 动态 label：内容由按钮点击后更新
  FDynLabel := TTyLabel.Create(Self);
  FDynLabel.Parent := Self;
  FDynLabel.SetBounds(24, 100, 280, 24);
  FDynLabel.Caption := '（等待点击…）';

  // 按钮：点击后把点击次数写入 FDynLabel.Caption
  Btn := TTyButton.Create(Self);
  Btn.Parent := Self;
  Btn.SetBounds(24, 144, 160, 32);
  Btn.Caption := '修改标签文字';
  Btn.StyleClass := 'primary';
  Btn.OnClick := @ButtonClicked;
end;

procedure TMainForm.ButtonClicked(Sender: TObject);
begin
  Inc(FClickCount);
  FDynLabel.Caption := Format('已点击 %d 次', [FClickCount]);
end;

end.
