unit umain;

{ TTySpinEdit 示例：
  - 第一个 SpinEdit（0..100，步进 1），OnChange 实时更新数值标签
  - 支持点击上/下小箭头按钮、键盘上/下方向键、鼠标滚轮来改变 Value
  - 第二个 SpinEdit 展示自定义范围（-10..10）与步进 2
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.SpinEdit, tyControls.TyLabel;

type
  TMainForm = class(TForm)
  private
    FSpin1: TTySpinEdit;
    FLabel1: TTyLabel;
    FSpin2: TTySpinEdit;
    FLabel2: TTyLabel;
    procedure Spin1Change(Sender: TObject);
    procedure Spin2Change(Sender: TObject);
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
  LblA, LblB: TTyLabel;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'TTySpinEdit 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 360, 260);

  // 加载主题：未显式指定 Controller 的控件自动使用全局 TyDefaultController
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // SpinEdit 一：0..100，步进 1
  LblA := TTyLabel.Create(Self);
  LblA.Parent := Self;
  LblA.SetBounds(16, 24, 320, 20);
  LblA.Caption := '数量（0..100，箭头/方向键/滚轮）：';

  FSpin1 := TTySpinEdit.Create(Self);
  FSpin1.Parent := Self;
  FSpin1.SetBounds(16, 52, 120, 28);
  FSpin1.MinValue := 0;
  FSpin1.MaxValue := 100;
  FSpin1.Value := 10;
  FSpin1.OnChange := @Spin1Change;

  FLabel1 := TTyLabel.Create(Self);
  FLabel1.Parent := Self;
  FLabel1.SetBounds(16, 88, 320, 20);
  FLabel1.Caption := Format('数量：%d', [FSpin1.Value]);

  // SpinEdit 二：-10..10，步进 2，展示负值范围与自定义步进
  LblB := TTyLabel.Create(Self);
  LblB.Parent := Self;
  LblB.SetBounds(16, 140, 320, 20);
  LblB.Caption := '偏移（-10..10，步进 2）：';

  FSpin2 := TTySpinEdit.Create(Self);
  FSpin2.Parent := Self;
  FSpin2.SetBounds(16, 168, 120, 28);
  FSpin2.MinValue := -10;
  FSpin2.MaxValue := 10;
  FSpin2.Increment := 2;
  FSpin2.Value := 0;
  FSpin2.OnChange := @Spin2Change;

  FLabel2 := TTyLabel.Create(Self);
  FLabel2.Parent := Self;
  FLabel2.SetBounds(16, 204, 320, 20);
  FLabel2.Caption := '偏移：0';
end;

procedure TMainForm.Spin1Change(Sender: TObject);
begin
  FLabel1.Caption := Format('数量：%d', [(Sender as TTySpinEdit).Value]);
end;

procedure TMainForm.Spin2Change(Sender: TObject);
begin
  FLabel2.Caption := Format('偏移：%d', [(Sender as TTySpinEdit).Value]);
end;

end.
