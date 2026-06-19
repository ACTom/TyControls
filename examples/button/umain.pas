unit umain;

{ TTyButton 最小示例：
  - 默认 / primary / danger 变体（StyleClass）
  - 禁用态（:disabled，主题里通常配 opacity）
  - OnClick 事件
  纯代码创建 UI（无 .lfm），主题通过全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Button, tyControls.TyLabel;

type
  TMainForm = class(TForm)
  private
    FCount: Integer;
    FStatus: TTyLabel;
    procedure ButtonClicked(Sender: TObject);
    procedure GhostToggle(Sender: TObject);   // 点击切换 ghost 按钮的选中态
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

  function AddButton(const ACaption, AStyleClass: string; ATop: Integer): TTyButton;
  begin
    Result := TTyButton.Create(Self);
    Result.Parent := Self;
    Result.SetBounds(24, ATop, 160, 32);
    Result.Caption := ACaption;
    Result.StyleClass := AStyleClass;   // 对应 .tycss 里的 TyButton.<变体>
    Result.OnClick := @ButtonClicked;
  end;

var
  B: TTyButton;
begin
  inherited CreateNew(AOwner, 0);
  Caption := 'TTyButton 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 400, 240);

  // 加载主题：未显式指定 Controller 的控件自动使用全局 TyDefaultController
  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');

  AddButton('默认按钮', '', 24);
  AddButton('主要按钮', 'primary', 64);   // TyButton.primary
  AddButton('危险按钮', 'danger', 104);   // TyButton.danger

  B := AddButton('禁用按钮', 'primary', 144);
  B.Enabled := False;                     // :disabled（主题里通常用 opacity 变暗）

  // 右列：Ghost(透明)+ 选中态 —— 平时透明，hover/点击/选中才显边框底色。
  B := TTyButton.Create(Self);
  B.Parent := Self;
  B.SetBounds(208, 24, 160, 32);
  B.Caption := 'Ghost / 选中';
  B.StyleClass := 'ghost';                 // TyButton.ghost
  B.Down := True;                          // 常驻选中（:selected）
  B.OnClick := @GhostToggle;               // 点击切换选中

  // 右列：数字角标 —— >99 显示 99+，样式由 TyBadge 主题键控制。
  B := TTyButton.Create(Self);
  B.Parent := Self;
  B.SetBounds(208, 64, 160, 32);
  B.Caption := '消息';
  B.ShowBadge := True;
  B.BadgeValue := 128;                     // 显示 "99+"
  B.BadgePosition := bpBottomRight;

  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(24, 196, 352, 20);
  FStatus.Caption := '点击次数：0';
end;

procedure TMainForm.ButtonClicked(Sender: TObject);
begin
  Inc(FCount);
  FStatus.Caption := Format('点击次数：%d（%s）',
    [FCount, (Sender as TTyButton).Caption]);
end;

procedure TMainForm.GhostToggle(Sender: TObject);
begin
  with Sender as TTyButton do
    Down := not Down;   // 切换常驻选中态
end;

end.
