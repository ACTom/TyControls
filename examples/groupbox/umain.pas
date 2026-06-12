unit umain;

{ TTyGroupBox + TTyRadioButton 示例：
  - 两个 TTyGroupBox，每个各含 3 个 TTyRadioButton
  - TTyRadioButton.UncheckSiblings 按 Parent 分组：两组互相独立
  - OnClick 事件更新底部标签，报告两组各自的当前选项
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.GroupBox, tyControls.CheckBox,
  tyControls.TyLabel;

type
  TMainForm = class(TForm)
  private
    FGroup1: TTyGroupBox;
    FGroup2: TTyGroupBox;
    FStatus: TTyLabel;
    // 每组 3 个单选按钮
    FRadio1A, FRadio1B, FRadio1C: TTyRadioButton;
    FRadio2A, FRadio2B, FRadio2C: TTyRadioButton;
    procedure RadioClick(Sender: TObject);
    procedure UpdateStatus;
    function SelectedInGroup(AGroup: TTyGroupBox): string;
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

function TMainForm.SelectedInGroup(AGroup: TTyGroupBox): string;
var
  I: Integer;
  Ctrl: TControl;
begin
  Result := '（未选）';
  for I := 0 to AGroup.ControlCount - 1 do
  begin
    Ctrl := AGroup.Controls[I];
    if (Ctrl is TTyRadioButton) and TTyRadioButton(Ctrl).Checked then
    begin
      Result := TTyRadioButton(Ctrl).Caption;
      Exit;
    end;
  end;
end;

constructor TMainForm.Create(AOwner: TComponent);
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyGroupBox 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 420, 320);

  // 加载主题：未显式指定 Controller 的控件自动使用全局 TyDefaultController
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  // ── 分组框一：字体大小 ────────────────────────────────────────────
  FGroup1 := TTyGroupBox.Create(Self);
  FGroup1.Parent := Self;
  FGroup1.SetBounds(16, 16, 175, 120);
  FGroup1.Caption := '字体大小';

  FRadio1A := TTyRadioButton.Create(FGroup1);
  FRadio1A.Parent := FGroup1;
  FRadio1A.SetBounds(8, 8, 150, 24);
  FRadio1A.Caption := '小（12pt）';
  FRadio1A.OnClick := @RadioClick;

  FRadio1B := TTyRadioButton.Create(FGroup1);
  FRadio1B.Parent := FGroup1;
  FRadio1B.SetBounds(8, 36, 150, 24);
  FRadio1B.Caption := '中（14pt）';
  FRadio1B.Checked := True;    // 默认选中
  FRadio1B.OnClick := @RadioClick;

  FRadio1C := TTyRadioButton.Create(FGroup1);
  FRadio1C.Parent := FGroup1;
  FRadio1C.SetBounds(8, 64, 150, 24);
  FRadio1C.Caption := '大（18pt）';
  FRadio1C.OnClick := @RadioClick;

  // ── 分组框二：主题色 ──────────────────────────────────────────────
  FGroup2 := TTyGroupBox.Create(Self);
  FGroup2.Parent := Self;
  FGroup2.SetBounds(220, 16, 175, 120);
  FGroup2.Caption := '主题色';

  FRadio2A := TTyRadioButton.Create(FGroup2);
  FRadio2A.Parent := FGroup2;
  FRadio2A.SetBounds(8, 8, 150, 24);
  FRadio2A.Caption := '浅色';
  FRadio2A.Checked := True;    // 默认选中
  FRadio2A.OnClick := @RadioClick;

  FRadio2B := TTyRadioButton.Create(FGroup2);
  FRadio2B.Parent := FGroup2;
  FRadio2B.SetBounds(8, 36, 150, 24);
  FRadio2B.Caption := '深色';
  FRadio2B.OnClick := @RadioClick;

  FRadio2C := TTyRadioButton.Create(FGroup2);
  FRadio2C.Parent := FGroup2;
  FRadio2C.SetBounds(8, 64, 150, 24);
  FRadio2C.Caption := '跟随系统';
  FRadio2C.OnClick := @RadioClick;

  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(16, 220, 380, 40);
  UpdateStatus;
end;

procedure TMainForm.RadioClick(Sender: TObject);
begin
  UpdateStatus;
end;

procedure TMainForm.UpdateStatus;
begin
  FStatus.Caption := Format('字体大小：%s    主题色：%s',
    [SelectedInGroup(FGroup1), SelectedInGroup(FGroup2)]);
end;

end.
