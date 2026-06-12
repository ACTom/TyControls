unit umain;

{ TTyListBox 示例：
  - 12 个列表项，列表高度小于总内容高度，内置滚动条自动出现
  - 键盘上下键移动选中项；鼠标滚轮滚动列表
  - OnChange 事件更新底部 TTyLabel，显示当前选中项文本
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.ListBox, tyControls.TyLabel;

type
  TMainForm = class(TForm)
  private
    FListBox: TTyListBox;
    FStatus: TTyLabel;
    procedure ListBoxChange(Sender: TObject);
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
  LblTitle: TTyLabel;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyListBox 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 360, 340);

  // 加载主题：未显式指定 Controller 的控件自动使用全局 TyDefaultController
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  LblTitle := TTyLabel.Create(Self);
  LblTitle.Parent := Self;
  LblTitle.SetBounds(16, 12, 320, 20);
  LblTitle.Caption := '城市列表（上下键 / 滚轮可滚动）：';

  // 列表框：12 项，高度 200，不足以显示全部 → 自动出现内置滚动条
  FListBox := TTyListBox.Create(Self);
  FListBox.Parent := Self;
  FListBox.SetBounds(16, 36, 320, 200);
  FListBox.OnChange := @ListBoxChange;

  // 填充 12 个列表项（超出可视行数，触发内置滚动条）
  FListBox.Items.Add('北京');
  FListBox.Items.Add('上海');
  FListBox.Items.Add('广州');
  FListBox.Items.Add('深圳');
  FListBox.Items.Add('成都');
  FListBox.Items.Add('杭州');
  FListBox.Items.Add('武汉');
  FListBox.Items.Add('西安');
  FListBox.Items.Add('南京');
  FListBox.Items.Add('天津');
  FListBox.Items.Add('重庆');
  FListBox.Items.Add('苏州');

  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(16, 252, 320, 20);
  FStatus.Caption := '当前选中：（无）';
end;

procedure TMainForm.ListBoxChange(Sender: TObject);
var
  LB: TTyListBox;
begin
  LB := Sender as TTyListBox;
  if LB.ItemIndex >= 0 then
    FStatus.Caption := Format('当前选中：%s（第 %d 项）',
      [LB.Items[LB.ItemIndex], LB.ItemIndex + 1])
  else
    FStatus.Caption := '当前选中：（无）';
end;

end.
