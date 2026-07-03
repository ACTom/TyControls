unit umain;

{ TTyEdit 示例（TTyForm 自绘窗框 + TTyTitleBar）：
    演示 TTyEdit 的核心已发布属性，每个输入框展示一种模式：
      - TextHint      占位提示（空文本时以暗色显示）
      - PasswordChar  密码遮罩字符
      - CharCase      大小写强制（ecUppercase）
      - MaxLength     最大字符数限制
      - NumbersOnly   仅允许数字
      - ReadOnly      只读
      - Alignment     文本对齐（taRightJustify）
    第一个输入框接 OnChange，实时把内容写到底部状态栏 TTyLabel。
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls,
  tyControls.Controller, tyControls.Form,
  tyControls.TyLabel, tyControls.Edit;

type
  TMainForm = class(TTyForm)
  private
    FStatus: TTyLabel;
    procedure EditChanged(Sender: TObject);   // OnChange -> 状态栏
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

  { 便捷：创建一个左侧说明 label + 右侧输入框，返回输入框以便进一步设置 }
  function AddRow(const ACaption: string; ATop: Integer): TTyEdit;
  var
    Lbl: TTyLabel;
  begin
    Lbl := TTyLabel.Create(Self);
    Lbl.Parent := Self;
    Lbl.SetBounds(24, ATop + 5, 130, 22);
    Lbl.Caption := ACaption;

    Result := TTyEdit.Create(Self);
    Result.Parent := Self;
    Result.SetBounds(160, ATop, 260, 30);
  end;

var
  Bar: TTyTitleBar;
  Ed: TTyEdit;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm：无边框 + 持久引擎
  Caption := 'TTyEdit 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 460, 400);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // 先加载主题

  Bar := TTyTitleBar.Create(Self);         // Owner=Self 自动关联为 TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'TTyEdit  · TyControls';

  // 1) TextHint：空文本占位提示 + OnChange 接状态栏
  Ed := AddRow('占位提示 + OnChange', 52);
  Ed.TextHint := '在此输入，下方实时回显…';
  Ed.OnChange := @EditChanged;             // 输入即回显

  // 2) PasswordChar：密码遮罩
  Ed := AddRow('密码遮罩', 92);
  Ed.PasswordChar := '●';                  // 显示为圆点
  Ed.Text := 'secret';

  // 3) CharCase：强制大写
  Ed := AddRow('强制大写', 132);
  Ed.CharCase := ecUppercase;              // 输入自动转大写
  Ed.TextHint := '输入将转为大写';

  // 4) MaxLength：最多 8 个字符
  Ed := AddRow('最大长度 8', 172);
  Ed.MaxLength := 8;
  Ed.TextHint := '最多 8 字';

  // 5) NumbersOnly：仅数字
  Ed := AddRow('仅数字', 212);
  Ed.NumbersOnly := True;                  // 非数字字符被拒绝
  Ed.TextHint := '只能输入 0-9';

  // 6) ReadOnly：只读
  Ed := AddRow('只读', 252);
  Ed.ReadOnly := True;
  Ed.Text := '只读内容，无法编辑';

  // 7) Alignment：右对齐
  Ed := AddRow('右对齐', 292);
  Ed.Alignment := taRightJustify;
  Ed.Text := '1234.56';

  // 底部状态栏
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(24, 348, 412, 24);
  FStatus.Caption := '（第一个输入框内容将在此显示）';

  ApplyChromeTheme(TyDefaultController);   // 最后给整套窗框 + 背景上色
end;

procedure TMainForm.EditChanged(Sender: TObject);
begin
  // 实时读取 TTyEdit.Text
  FStatus.Caption := '当前输入：' + (Sender as TTyEdit).Text;
end;

end.
