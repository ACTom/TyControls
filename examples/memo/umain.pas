unit umain;

{ TTyMemo 示例（TTyForm 无边框自绘窗框 + TTyTitleBar）：
  - Lines：多行文本模型（回车换行、退格/删除跨行合并、方向键/Home/End 导航）
  - ScrollBars：默认 ssAutoVertical，内容溢出时右侧出现垂直滚动条；支持鼠标滚轮
  - ReadOnly：勾选后忽略一切用户编辑（仍可导航/选择/复制）
  - WordWrap：勾选后长逻辑行按词边界软换行为多个视觉行
  - OnChange：文本模型变化时触发，实时更新行数/字符数标签
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, StdCtrls,
  tyControls.Controller, tyControls.Form,
  tyControls.Memo, tyControls.TyLabel, tyControls.CheckBox;

type
  TMainForm = class(TTyForm)
  private
    FMemo: TTyMemo;
    FInfo: TTyLabel;
    FReadOnlyChk: TTyCheckBox;
    FWordWrapChk: TTyCheckBox;
    procedure MemoChange(Sender: TObject);
    procedure ReadOnlyClick(Sender: TObject);
    procedure WordWrapClick(Sender: TObject);
    procedure UpdateInfo;
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
  Lbl: TTyLabel;
begin
  // TTyForm.CreateNew → 无边框 + 持久引擎，但默认无标题栏
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyMemo 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 480, 420);

  // 主题须先加载，未显式指定 Controller 的控件自动使用全局 TyDefaultController
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // 标题栏：Owner=Self 即自动关联到本窗体的 TitleBar 属性
  Bar := TTyTitleBar.Create(Self);
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'TTyMemo  · TyControls';

  // ── 客户区内容（标题栏下方） ──
  Lbl := TTyLabel.Create(Self);
  Lbl.Parent := Self;
  Lbl.SetBounds(16, 46, 448, 20);
  Lbl.Caption := '多行文本编辑器（回车换行、方向键导航、滚轮滚动）：';

  // 可编辑的多行 TTyMemo
  FMemo := TTyMemo.Create(Self);
  FMemo.Parent := Self;
  FMemo.SetBounds(16, 72, 448, 240);
  // ssAutoVertical 为默认值：内容溢出时右侧自动出现垂直滚动条
  FMemo.ScrollBars := ssAutoVertical;
  FMemo.WordWrap := False;   // 初始不软换行，长行可横向滚动
  // 预置若干行以演示垂直滚动条
  FMemo.Lines.Text :=
    '第一行：欢迎使用 TyControls TTyMemo 多行编辑控件。' + LineEnding +
    '第二行：按回车换行，退格/删除可跨行合并。' + LineEnding +
    '第三行：方向键、Home/End 用于光标导航，支持选择与复制粘贴。' + LineEnding +
    '第四行：内容超出可见区域时右侧出现垂直滚动条。' + LineEnding +
    '第五行：也可以用鼠标滚轮上下滚动。' + LineEnding +
    '第六行：勾选下方“自动换行”后，超长的一行会按词边界折行为多个视觉行——这是一条足够长用于演示软换行效果的文字。' + LineEnding +
    '第七行：勾选“只读”后将无法编辑，但仍可导航与复制。' + LineEnding +
    '第八行：最后一行。';
  FMemo.OnChange := @MemoChange;

  // 只读切换
  FReadOnlyChk := TTyCheckBox.Create(Self);
  FReadOnlyChk.Parent := Self;
  FReadOnlyChk.SetBounds(16, 322, 120, 24);
  FReadOnlyChk.Caption := '只读 (ReadOnly)';
  FReadOnlyChk.OnClick := @ReadOnlyClick;

  // 自动换行切换
  FWordWrapChk := TTyCheckBox.Create(Self);
  FWordWrapChk.Parent := Self;
  FWordWrapChk.SetBounds(150, 322, 140, 24);
  FWordWrapChk.Caption := '自动换行 (WordWrap)';
  FWordWrapChk.OnClick := @WordWrapClick;

  // 状态标签（行数 / 字符数）
  FInfo := TTyLabel.Create(Self);
  FInfo.Parent := Self;
  FInfo.SetBounds(16, 356, 448, 20);
  UpdateInfo;

  // 整套窗框 + 背景色随主题
  ApplyChromeTheme(TyDefaultController);
end;

procedure TMainForm.UpdateInfo;
begin
  FInfo.Caption := Format('行数：%d    字符数：%d',
    [FMemo.Lines.Count, Length(FMemo.Text)]);
end;

procedure TMainForm.MemoChange(Sender: TObject);
begin
  // OnChange：文本模型每次变化时刷新统计
  UpdateInfo;
end;

procedure TMainForm.ReadOnlyClick(Sender: TObject);
begin
  FMemo.ReadOnly := FReadOnlyChk.Checked;
end;

procedure TMainForm.WordWrapClick(Sender: TObject);
begin
  FMemo.WordWrap := FWordWrapChk.Checked;
end;

end.
