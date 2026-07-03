unit umain;

{ TTyLabel 示例（TTyForm + TTyTitleBar）：
  演示 TTyLabel 的核心已发布特性——
    - Alignment：taLeftJustify / taCenter / taRightJustify 水平对齐
    - Layout：tlTop / tlCenter / tlBottom 垂直对齐（固定高度内）
    - WordWrap：长文本按控件宽度在空格处自动折行
    - AutoSize：开 = 随文本自动收缩/增长；关 = 固定边框
    - Transparent：True = 背景透明；False = 用主题面板色填充
    - FocusControl + & 助记符：Alt+字母把焦点送给关联的 TTyEdit
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。
  注意：字号/字重与 StyleClass.primary 由主题(light.tycss)控制，TyLabel
  没有对应规则，故本示例不演示这些无效属性。 }

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

  // ===== 段标题（字号/字重由主题决定，此处不做无效的 Font 覆盖）=====
  LHead := TTyLabel.Create(Self);
  LHead.Parent := Self;
  LHead.SetBounds(20, 46, 440, 26);
  LHead.Caption := '标签特性一览';

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

  // ===== Transparent=False：用主题面板色填充背景（区别于其它透明标签）=====
  L := TTyLabel.Create(Self);
  L.Parent := Self;
  L.SetBounds(20, 166, 440, 22);
  L.AutoSize := False;
  L.Transparent := False;
  L.Alignment := taCenter;
  L.Caption := 'Transparent=False：带填充背景';

  // ===== AutoSize=True：边框随文字收紧（默认）=====
  L := TTyLabel.Create(Self);
  L.Parent := Self;
  L.SetBounds(20, 194, 10, 10);           // 尺寸会被 AutoSize 覆盖
  L.AutoSize := True;
  L.Caption := 'AutoSize=True：宽高随文字自适应';

  // ===== WordWrap：长文本在空格处按控件宽度自动折行 =====
  //  折行只在 ASCII 空格处发生，故此处用以空格分隔的词语，折行效果真实可见。
  L := TTyLabel.Create(Self);
  L.Parent := Self;
  L.SetBounds(20, 224, 440, 60);
  L.AutoSize := False;
  L.WordWrap := True;
  L.Alignment := taLeftJustify;
  L.Caption := 'WordWrap=True : this label wraps onto several lines because '
             + 'the words are separated by spaces — 中文 与 English 混排 也 '
             + '能 在 空格 处 换行，超出 控件 宽度 就 自动 折行。';

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
