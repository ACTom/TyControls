unit umain;

{ TTyLabel 示例（TTyForm + TTyTitleBar）：
  演示 TTyLabel 的核心已发布特性——
    - Alignment：taLeftJustify / taCenter / taRightJustify 水平对齐
    - WordWrap：长文本按控件宽度自动折行
    - AutoSize：开 = 随文本自动收缩/增长；关 = 固定边框
    - Font：自定义字体（字号 / 加粗 / 字体名）
    - StyleClass：选择主题变体（如 'primary'）
    - FocusControl + & 助记符：Alt+字母把焦点送给关联的 TTyEdit
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics,
  tyControls.Controller, tyControls.Form,
  tyControls.TyLabel, tyControls.Edit;

type
  TMainForm = class(TTyForm)
  private
    { fields + event handlers }
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
  Bar: TTyTitleBar;
  LHead, L: TTyLabel;
  LFocus: TTyLabel;
  Ed: TTyEdit;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm: 无边框 + 常驻引擎
  Caption := 'TTyLabel 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 480, 440);
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // 先加载主题

  Bar := TTyTitleBar.Create(Self);         // Owner=Self -> 自动关联为 TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'TTyLabel  · TyControls';

  // ===== 段标题：加粗大字体演示 Font =====
  LHead := TTyLabel.Create(Self);
  LHead.Parent := Self;
  LHead.SetBounds(20, 46, 440, 26);
  LHead.Caption := '标签特性一览';
  LHead.Font.Size := 14;
  LHead.Font.Style := [fsBold];

  // ===== Alignment：三种水平对齐（AutoSize=False 才能看出对齐效果）=====
  L := TTyLabel.Create(Self);
  L.Parent := Self;
  L.SetBounds(20, 82, 440, 22);
  L.AutoSize := False;
  L.Alignment := taLeftJustify;
  L.Caption := '左对齐（taLeftJustify）';

  L := TTyLabel.Create(Self);
  L.Parent := Self;
  L.SetBounds(20, 108, 440, 22);
  L.AutoSize := False;
  L.Alignment := taCenter;
  L.Caption := '居中对齐（taCenter）';

  L := TTyLabel.Create(Self);
  L.Parent := Self;
  L.SetBounds(20, 134, 440, 22);
  L.AutoSize := False;
  L.Alignment := taRightJustify;
  L.Caption := '右对齐（taRightJustify）';

  // ===== StyleClass：主题变体（primary）=====
  L := TTyLabel.Create(Self);
  L.Parent := Self;
  L.SetBounds(20, 166, 440, 22);
  L.StyleClass := 'primary';
  L.Caption := '带 StyleClass = primary 的标签';

  // ===== AutoSize=True：边框随文字收紧（默认）=====
  L := TTyLabel.Create(Self);
  L.Parent := Self;
  L.SetBounds(20, 194, 10, 10);           // 尺寸会被 AutoSize 覆盖
  L.AutoSize := True;
  L.Caption := 'AutoSize=True：宽高随文字自适应';

  // ===== WordWrap：长文本在固定宽度内自动折行 =====
  L := TTyLabel.Create(Self);
  L.Parent := Self;
  L.SetBounds(20, 224, 440, 60);
  L.AutoSize := False;
  L.WordWrap := True;
  L.Alignment := taLeftJustify;
  L.Caption := 'WordWrap=True：这是一段较长的说明文字，当它超过标签宽度时会自动换到下一行，'
             + '而不是被裁剪或溢出到控件之外，方便展示多行文本内容。';

  // ===== FocusControl + & 助记符：Alt+N 聚焦到下面的输入框 =====
  Ed := TTyEdit.Create(Self);
  Ed.Parent := Self;
  Ed.SetBounds(180, 300, 240, 28);
  Ed.Text := '';

  LFocus := TTyLabel.Create(Self);
  LFocus.Parent := Self;
  LFocus.SetBounds(20, 304, 150, 22);
  LFocus.Caption := '姓名(&N)：';        // & 生成助记符：按 Alt+N 触发
  LFocus.FocusControl := Ed;             // 点击标签 / Alt+N -> Ed 获得焦点

  ApplyChromeTheme(TyDefaultController);   // 最后统一给整个窗口铬 + 背景上色
end;

end.
