unit umain;

{ TTyRadioButton 示例（TTyForm + TitleBar 骨架）：
  - 两个 TTyGroupBox 容器（标题栏由 GroupBox 顶部预留），各含 3 个 TTyRadioButton
  - 互斥（UncheckSiblings）按 Parent 分组：同一 GroupBox 内互斥，跨组独立
  - Checked：每组默认选中一项
  - OnChange：任一按钮状态变化都刷新底部 TTyLabel 状态读数
  - 演示一个 Enabled=False 的禁用项
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.GroupBox, tyControls.CheckBox, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FStatus: TTyLabel;
    { 组 A：水果 }
    FFruitApple, FFruitBanana, FFruitMango: TTyRadioButton;
    { 组 B：颜色 }
    FColorRed, FColorGreen, FColorBlue: TTyRadioButton;
    procedure RadioChanged(Sender: TObject);
    procedure UpdateStatus;
    function SelectedIn(A, B, C: TTyRadioButton): string;
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

{ 在指定 GroupBox 内创建一个 TTyRadioButton，事件挂到 OnChange。
  Top 为 GroupBox 客户区坐标（GroupBox 已通过 AdjustClientRect 让出顶部标题带）。 }
function AddRadio(AGroup: TTyGroupBox; const ACaption: string; ATop: Integer;
  AHandler: TNotifyEvent): TTyRadioButton;
begin
  Result := TTyRadioButton.Create(AGroup);
  Result.Parent := AGroup;
  Result.SetBounds(10, ATop, 160, 26);
  Result.Caption := ACaption;
  Result.OnChange := AHandler;
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
  GroupA, GroupB: TTyGroupBox;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm：无边框 + 持久引擎
  Caption := 'RadioButton 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 440, 320);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // 先加载主题

  Bar := TTyTitleBar.Create(Self);         // Owner=Self -> 自动关联为 TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'RadioButton  · TyControls';

  { --- 状态标签：先建好，OnChange 首次触发时它必须已存在 ---
    （AddRadio 挂 OnChange，随后 .Checked := True 会立刻触发 RadioChanged
     -> UpdateStatus -> FStatus.Caption；FStatus 必须先于任何单选组创建） }
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(16, 236, 408, 24);

  { --- 组 A：水果（同一 GroupBox 内互斥，标题左对齐） --- }
  GroupA := TTyGroupBox.Create(Self);
  GroupA.Parent := Self;
  GroupA.SetBounds(16, 52, 190, 168);
  GroupA.Caption := '水果';
  GroupA.Alignment := taLeftJustify;

  FFruitApple  := AddRadio(GroupA, '苹果', 24, @RadioChanged);  // Top>=24 让出 16px 标题带
  FFruitBanana := AddRadio(GroupA, '香蕉', 56, @RadioChanged);
  FFruitMango  := AddRadio(GroupA, '芒果（缺货）', 88, @RadioChanged);
  FFruitMango.Enabled := False;            // 禁用项：不可选、置灰

  { --- 组 B：颜色（另一个 GroupBox，与组 A 互不影响，标题居中） --- }
  GroupB := TTyGroupBox.Create(Self);
  GroupB.Parent := Self;
  GroupB.SetBounds(232, 52, 190, 168);
  GroupB.Caption := '颜色';
  GroupB.Alignment := taCenter;

  FColorRed   := AddRadio(GroupB, '红色', 24, @RadioChanged);
  FColorGreen := AddRadio(GroupB, '绿色', 56, @RadioChanged);
  FColorBlue  := AddRadio(GroupB, '蓝色', 88, @RadioChanged);

  { 默认选中必须放在所有单选字段创建之后：设 Checked 会立刻触发 OnChange ->
    RadioChanged -> UpdateStatus，而 UpdateStatus 读取全部 6 个字段——若此时仍有
    字段为 nil 就会崩溃(启动即 AV，这正是之前没修好的原因)。 }
  FFruitApple.Checked := True;             // 水果：默认第一项
  FColorGreen.Checked := True;             // 颜色：默认第二项
  UpdateStatus;                            // 所有单选建完，刷一次最终读数

  ApplyChromeTheme(TyDefaultController);    // 最后统一给 chrome + 窗体背景上主题
end;

{ 返回一组里当前选中项的 Caption }
function TMainForm.SelectedIn(A, B, C: TTyRadioButton): string;
begin
  if A.Checked then Result := A.Caption
  else if B.Checked then Result := B.Caption
  else if C.Checked then Result := C.Caption
  else Result := '（无）';
end;

procedure TMainForm.UpdateStatus;
begin
  FStatus.Caption := Format('当前选中  →  水果：%s     颜色：%s',
    [SelectedIn(FFruitApple, FFruitBanana, FFruitMango),
     SelectedIn(FColorRed, FColorGreen, FColorBlue)]);
end;

procedure TMainForm.RadioChanged(Sender: TObject);
begin
  { 任一按钮的 Checked 变化（含被 UncheckSiblings 取消的）都会进来 }
  UpdateStatus;
end;

end.
