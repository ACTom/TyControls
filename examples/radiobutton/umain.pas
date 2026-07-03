unit umain;

{ TTyRadioButton 示例（TTyForm + TitleBar 骨架）：
  - 两个 TTyPanel 容器，各含 3 个 TTyRadioButton
  - 互斥（UncheckSiblings）按 Parent 分组：同一 Panel 内互斥，跨组独立
  - Checked：每组默认选中一项
  - OnChange：任一按钮状态变化都刷新底部 TTyLabel 状态读数
  - 演示一个 Enabled=False 的禁用项
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.CheckBox, tyControls.Panel, tyControls.TyLabel;

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

{ 在指定 Panel 内创建一个 TTyRadioButton，事件挂到 OnChange }
function AddRadio(APanel: TTyPanel; const ACaption: string; ATop: Integer;
  AHandler: TNotifyEvent): TTyRadioButton;
begin
  Result := TTyRadioButton.Create(APanel);
  Result.Parent := APanel;
  Result.SetBounds(12, ATop, 150, 26);
  Result.Caption := ACaption;
  Result.OnChange := AHandler;
end;

constructor TMainForm.Create(AOwner: TComponent);
var
  Bar: TTyTitleBar;
  PanelA, PanelB: TTyPanel;
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

  { --- 组 A：水果（同一 Panel 内互斥） --- }
  PanelA := TTyPanel.Create(Self);
  PanelA.Parent := Self;
  PanelA.Caption := '水果';
  PanelA.SetBounds(16, 52, 190, 160);

  FFruitApple  := AddRadio(PanelA, '苹果', 34, @RadioChanged);
  FFruitApple.Checked := True;             // 默认选中第一项
  FFruitBanana := AddRadio(PanelA, '香蕉', 72, @RadioChanged);
  FFruitMango  := AddRadio(PanelA, '芒果（缺货）', 110, @RadioChanged);
  FFruitMango.Enabled := False;            // 禁用项：不可选、置灰

  { --- 组 B：颜色（另一个 Panel，与组 A 互不影响） --- }
  PanelB := TTyPanel.Create(Self);
  PanelB.Parent := Self;
  PanelB.Caption := '颜色';
  PanelB.SetBounds(232, 52, 190, 160);

  FColorRed   := AddRadio(PanelB, '红色', 34, @RadioChanged);
  FColorGreen := AddRadio(PanelB, '绿色', 72, @RadioChanged);
  FColorGreen.Checked := True;             // 默认选中第二项
  FColorBlue  := AddRadio(PanelB, '蓝色', 110, @RadioChanged);

  { --- 状态标签：OnChange 实时读数 --- }
  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(16, 228, 408, 24);
  UpdateStatus;

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
