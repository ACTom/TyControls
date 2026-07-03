unit umain;

{ TTyButton 示例：
  - StyleClass 变体：默认 / primary / danger / ghost
  - Down(:selected 常驻选中态,点击切换)
  - 角标 ShowBadge / BadgeValue / BadgePosition(>99 显示 99+)
  - Default(回车触发) / Cancel(Esc 触发) / ModalResult
  - & 助记符(Alt+字母激活)
  - Enabled 禁用态
  - OnClick 汇报到状态标签
  纯代码创建 UI(无 .lfm),主体为 TTyForm + TTyTitleBar,主题经全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.Button, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FCount: Integer;
    FStatus: TTyLabel;
    procedure ButtonClicked(Sender: TObject);
    procedure GhostToggle(Sender: TObject);   // 点击切换 ghost 按钮的选中态
    procedure DefaultClicked(Sender: TObject);
    procedure CancelClicked(Sender: TObject);
  public
    constructor Create(AOwner: TComponent); override;
  end;

var
  MainForm: TMainForm;

implementation

{ 从 exe 所在目录向上查找仓库的 themes/ 目录(兼容 lib/<cpu>-<os>/ 与 .app 包) }
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

  function AddButton(const ACaption, AStyleClass: string;
    ALeft, ATop: Integer): TTyButton;
  begin
    Result := TTyButton.Create(Self);
    Result.Parent := Self;
    Result.SetBounds(ALeft, ATop, 168, 32);
    Result.Caption := ACaption;
    Result.StyleClass := AStyleClass;   // 对应 .tycss 里的 TyButton.<变体>
    Result.OnClick := @ButtonClicked;
  end;

var
  Bar: TTyTitleBar;
  B: TTyButton;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm:无边框 + 常驻引擎
  Caption := 'TTyButton 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 460, 420);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // 先加载主题

  Bar := TTyTitleBar.Create(Self);         // Owner=Self -> 自动关联为 TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'TTyButton  · TyControls';

  // 左列:StyleClass 变体 + 禁用态。& 前缀 = 助记符(Alt+字母触发)。
  AddButton('默认按钮(&D)', '', 24, 52);
  AddButton('主要按钮(&P)', 'primary', 24, 92);   // TyButton.primary
  AddButton('危险按钮(&X)', 'danger', 24, 132);   // TyButton.danger

  B := AddButton('禁用按钮', 'primary', 24, 172);
  B.Enabled := False;                     // :disabled(主题里通常用 opacity 变暗)

  // 左列:Ghost(透明)+ 选中态 —— 平时透明,hover/点击/选中才显边框底色。
  B := TTyButton.Create(Self);
  B.Parent := Self;
  B.SetBounds(24, 212, 168, 32);
  B.Caption := 'Ghost / 选中';
  B.StyleClass := 'ghost';                 // TyButton.ghost
  B.Down := True;                          // 常驻选中(:selected)
  B.OnClick := @GhostToggle;               // 点击切换选中

  // 右列:数字角标 —— 不同角位,>99 显示 99+,样式由 TyBadge 主题键控制。
  B := TTyButton.Create(Self);
  B.Parent := Self;
  B.SetBounds(256, 52, 168, 32);
  B.Caption := '消息';
  B.ShowBadge := True;
  B.BadgeValue := 128;                     // 显示 "99+"
  B.BadgePosition := bpTopRight;
  B.OnClick := @ButtonClicked;

  B := TTyButton.Create(Self);
  B.Parent := Self;
  B.SetBounds(256, 92, 168, 32);
  B.Caption := '通知';
  B.ShowBadge := True;
  B.BadgeValue := 3;
  B.BadgePosition := bpBottomRight;
  B.OnClick := @ButtonClicked;

  // 右列:Default / Cancel / ModalResult —— 回车触发 Default,Esc 触发 Cancel。
  B := AddButton('确定(回车)', 'primary', 256, 132);
  B.Default := True;                       // 表单回车激活
  B.ModalResult := mrOk;                   // 模态时置 Form.ModalResult
  B.OnClick := @DefaultClicked;

  B := AddButton('取消(Esc)', '', 256, 172);
  B.Cancel := True;                        // 表单 Esc 激活
  B.ModalResult := mrCancel;
  B.OnClick := @CancelClicked;

  FStatus := TTyLabel.Create(Self);
  FStatus.Parent := Self;
  FStatus.SetBounds(24, 356, 412, 24);
  FStatus.Caption := '点击次数:0';

  ApplyChromeTheme(TyDefaultController);   // 最后统一主题化窗体外壳与背景
end;

procedure TMainForm.ButtonClicked(Sender: TObject);
begin
  Inc(FCount);
  FStatus.Caption := Format('点击次数:%d(%s)',
    [FCount, (Sender as TTyButton).Caption]);
end;

procedure TMainForm.GhostToggle(Sender: TObject);
begin
  with Sender as TTyButton do
    Down := not Down;   // 切换常驻选中态
  ButtonClicked(Sender);
end;

procedure TMainForm.DefaultClicked(Sender: TObject);
begin
  Inc(FCount);
  FStatus.Caption := Format('点击次数:%d(默认按钮 · 回车/ModalResult=mrOk)', [FCount]);
end;

procedure TMainForm.CancelClicked(Sender: TObject);
begin
  Inc(FCount);
  FStatus.Caption := Format('点击次数:%d(取消按钮 · Esc/ModalResult=mrCancel)', [FCount]);
end;

end.
