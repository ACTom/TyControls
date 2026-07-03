unit umain;

{ TTyGroupBox 示例：
  - Caption：每个分组框带标题
  - Alignment：标题左对齐 / 居中 / 右对齐三种（taLeftJustify / taCenter / taRightJustify）
  - 容纳子控件：分组框内放 TTyRadioButton / TTyCheckBox
  - 分组框内嵌一个 TTyEdit（输入框），演示任意子控件都能作为容器成员
  - 事件汇总到底部 TTyLabel 状态栏
  纯代码创建 UI（无 .lfm），主窗体为 TTyForm 并带 TTyTitleBar，
  主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.GroupBox, tyControls.CheckBox, tyControls.Edit,
  tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FGroupSize: TTyGroupBox;      // 标题左对齐 + 单选按钮
    FGroupOpt: TTyGroupBox;       // 标题居中 + 复选框
    FGroupName: TTyGroupBox;      // 标题右对齐 + 内嵌输入框
    FStatus: TTyLabel;
    FRadioA, FRadioB, FRadioC: TTyRadioButton;
    FCheckBold, FCheckItalic: TTyCheckBox;
    FNameEdit: TTyEdit;
    procedure RadioClick(Sender: TObject);
    procedure CheckClick(Sender: TObject);
    procedure NameChange(Sender: TObject);
    procedure UpdateStatus;
    function SelectedRadio: string;
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

function TMainForm.SelectedRadio: string;
begin
  Result := '（未选）';
  if FRadioA.Checked then Result := FRadioA.Caption
  else if FRadioB.Checked then Result := FRadioB.Caption
  else if FRadioC.Checked then Result := FRadioC.Caption;
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm：无边框 + 常驻引擎
  Caption := 'TTyGroupBox 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 620, 320);

  // 先加载主题：未显式指定 Controller 的控件自动使用全局 TyDefaultController
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  Bar := TTyTitleBar.Create(Self);         // Owner=Self → 自动关联为 TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'GroupBox  · TyControls';

  // ── 分组框一：标题左对齐（默认），内含单选按钮 ────────────────────
  FGroupSize := TTyGroupBox.Create(Self);
  FGroupSize.Parent := Self;
  FGroupSize.SetBounds(16, 52, 185, 130);
  FGroupSize.Caption := '字体大小（左对齐）';
  FGroupSize.Alignment := taLeftJustify;

  FRadioA := TTyRadioButton.Create(FGroupSize);
  FRadioA.Parent := FGroupSize;
  FRadioA.SetBounds(10, 8, 160, 26);
  FRadioA.Caption := '小（12pt）';
  FRadioA.OnClick := @RadioClick;

  FRadioB := TTyRadioButton.Create(FGroupSize);
  FRadioB.Parent := FGroupSize;
  FRadioB.SetBounds(10, 38, 160, 26);
  FRadioB.Caption := '中（14pt）';
  FRadioB.Checked := True;                 // 默认选中
  FRadioB.OnClick := @RadioClick;

  FRadioC := TTyRadioButton.Create(FGroupSize);
  FRadioC.Parent := FGroupSize;
  FRadioC.SetBounds(10, 68, 160, 26);
  FRadioC.Caption := '大（18pt）';
  FRadioC.OnClick := @RadioClick;

  // ── 分组框二：标题居中，内含复选框 ────────────────────────────────
  FGroupOpt := TTyGroupBox.Create(Self);
  FGroupOpt.Parent := Self;
  FGroupOpt.SetBounds(217, 52, 185, 130);
  FGroupOpt.Caption := '样式（居中）';
  FGroupOpt.Alignment := taCenter;

  FCheckBold := TTyCheckBox.Create(FGroupOpt);
  FCheckBold.Parent := FGroupOpt;
  FCheckBold.SetBounds(10, 8, 160, 26);
  FCheckBold.Caption := '加粗';
  FCheckBold.OnClick := @CheckClick;

  FCheckItalic := TTyCheckBox.Create(FGroupOpt);
  FCheckItalic.Parent := FGroupOpt;
  FCheckItalic.SetBounds(10, 38, 160, 26);
  FCheckItalic.Caption := '斜体';
  FCheckItalic.OnClick := @CheckClick;

  // ── 分组框三：标题右对齐，内嵌一个输入框 ──────────────────────────
  FGroupName := TTyGroupBox.Create(Self);
  FGroupName.Parent := Self;
  FGroupName.SetBounds(418, 52, 185, 130);
  FGroupName.Caption := '名称（右对齐）';
  FGroupName.Alignment := taRightJustify;

  FNameEdit := TTyEdit.Create(FGroupName);
  FNameEdit.Parent := FGroupName;
  FNameEdit.SetBounds(10, 12, 160, 30);
  FNameEdit.TextHint := '请输入名称…';
  FNameEdit.OnChange := @NameChange;

  // ── 底部状态栏 ────────────────────────────────────────────────────
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(16, 200, 588, 60);
  UpdateStatus;

  ApplyChromeTheme(TyDefaultController);    // 最后统一主题化窗体外壳 + 背景
end;

procedure TMainForm.RadioClick(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TMainForm.CheckClick(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TMainForm.NameChange(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TMainForm.UpdateStatus;
var
  Styles: string;
begin
  Styles := '';
  if FCheckBold.Checked then Styles := Styles + '加粗 ';
  if FCheckItalic.Checked then Styles := Styles + '斜体 ';
  if Styles = '' then Styles := '（无）';

  FStatus.Caption := Format('字体大小：%s    样式：%s    名称：%s',
    [SelectedRadio, Trim(Styles),
     IfThen(FNameEdit.Text = '', '（空）', FNameEdit.Text)]);
end;

end.
