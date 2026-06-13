unit umain;

{ TTyMemo 示例：
  - 多行文本编辑器：支持回车换行、退格/删除跨行合并、方向键/Home/End 导航
  - 内容超出可见区域时自动显示右侧垂直滚动条；支持鼠标滚轮滚动
  - OnChange 在文本模型变化时触发，实时更新行数标签
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Memo, tyControls.TyLabel;

type
  TMainForm = class(TForm)
  private
    FMemo: TTyMemo;
    FInfo: TTyLabel;
    procedure MemoChange(Sender: TObject);
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
  Lbl: TTyLabel;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyMemo 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 420, 360);

  // 加载主题：未显式指定 Controller 的控件自动使用全局 TyDefaultController
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  Lbl := TTyLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.SetBounds(16, 16, 388, 20);
  Lbl.Caption := '多行文本（回车换行、方向键导航、滚轮滚动）：';

  FMemo := TTyMemo.Create(Self);
  FMemo.Parent := Self;
  FMemo.SetBounds(16, 44, 388, 240);
  // 预置若干行以演示垂直滚动条
  FMemo.Lines.Text :=
    '第一行：欢迎使用 TyControls TTyMemo。' + LineEnding +
    '第二行：按回车换行，退格/删除可跨行合并。' + LineEnding +
    '第三行：方向键、Home/End 用于光标导航。' + LineEnding +
    '第四行：内容超出可见区域时右侧出现滚动条。' + LineEnding +
    '第五行：也可以用鼠标滚轮上下滚动。' + LineEnding +
    '第六行：再多几行……' + LineEnding +
    '第七行：……以触发垂直滚动。' + LineEnding +
    '第八行：最后一行。';
  FMemo.OnChange := @MemoChange;

  FInfo := TTyLabel.Create(Self);
  FInfo.Parent := Self;
  FInfo.SetBounds(16, 296, 388, 20);
  FInfo.Caption := Format('行数：%d', [FMemo.Lines.Count]);
end;

procedure TMainForm.MemoChange(Sender: TObject);
begin
  FInfo.Caption := Format('行数：%d', [(Sender as TTyMemo).Lines.Count]);
end;

end.
