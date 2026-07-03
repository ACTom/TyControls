unit umain;

{ TTyStatusBar 示例:
  - 底部状态栏(Align=alBottom),多面板 Panels(每个面板 Text/Width/Alignment)
  - 宽度 <=0 的面板自动填满剩余空间(fill 面板)
  - SizeGrip 右下角尺寸手柄
  - SimplePanel/SimpleText:切换到单一整条文本模式
  - 点击按钮更新面板文本(多面板模式)或整条文本(简单模式)
  纯代码创建 UI(无 .lfm),主体为 TTyForm + TTyTitleBar,主题经全局 TyDefaultController 加载。 }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls,
  tyControls.Controller, tyControls.Form,
  tyControls.StatusBar, tyControls.Button, tyControls.TyLabel;

type
  TMainForm = class(TTyForm)
  private
    FBar: TTyStatusBar;
    FClicks: Integer;
    procedure UpdatePanel(Sender: TObject);       // 更新左侧面板文本
    procedure ToggleSimple(Sender: TObject);      // 切换 SimplePanel 模式
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
var
  Bar: TTyTitleBar;
  HintLbl: TTyLabel;
  BtnUpdate, BtnSimple: TTyButton;
  P: TTyStatusPanel;
begin
  inherited CreateNew(AOwner, 0);          // TTyForm:无边框 + 常驻引擎
  Caption := 'TTyStatusBar 示例';
  Position := poScreenCenter;
  SetBounds(0, 0, 520, 320);

  TyDefaultController.LoadTheme(ThemesDir + 'light.tycss');   // 先加载主题

  Bar := TTyTitleBar.Create(Self);         // Owner=Self -> 自动关联为 TTyForm.TitleBar
  Bar.Parent := Self;
  Bar.Align := alTop;
  Bar.Height := 34;
  Bar.Caption := 'TTyStatusBar  · TyControls';

  // 说明标签
  HintLbl := TTyLabel.Create(Self);
  HintLbl.Parent := Self;
  HintLbl.SetBounds(24, 56, 472, 24);
  HintLbl.Caption := '底部状态栏:多面板 + 尺寸手柄。点击按钮更新面板文本。';

  // 底部状态栏 —— 三个固定面板 + 一个自动填满的 fill 面板。
  FBar := TTyStatusBar.Create(Self);
  FBar.Parent := Self;
  FBar.Align := alBottom;                   // 停靠底部(默认已是 alBottom)
  FBar.Height := 24;
  FBar.SizeGrip := True;                     // 右下角尺寸手柄

  P := FBar.Panels.Add;                      // 面板 0:状态(fill,Width<=0 撑满剩余)
  P.Text := '就绪';
  P.Width := 0;                              // 填充面板
  P.Alignment := taLeftJustify;

  P := FBar.Panels.Add;                      // 面板 1:点击计数(居中,固定宽)
  P.Text := '点击:0';
  P.Width := 110;
  P.Alignment := taCenter;

  P := FBar.Panels.Add;                      // 面板 2:右对齐提示(固定宽)
  P.Text := 'TyControls';
  P.Width := 110;
  P.Alignment := taRightJustify;

  // 操作按钮
  BtnUpdate := TTyButton.Create(Self);
  BtnUpdate.Parent := Self;
  BtnUpdate.SetBounds(24, 100, 200, 34);
  BtnUpdate.Caption := '更新状态面板';
  BtnUpdate.StyleClass := 'primary';
  BtnUpdate.OnClick := @UpdatePanel;

  BtnSimple := TTyButton.Create(Self);
  BtnSimple.Parent := Self;
  BtnSimple.SetBounds(24, 144, 200, 34);
  BtnSimple.Caption := '切换 SimplePanel 模式';
  BtnSimple.OnClick := @ToggleSimple;

  ApplyChromeTheme(TyDefaultController);   // 最后统一主题化窗体外壳与背景
end;

procedure TMainForm.UpdatePanel(Sender: TObject);
begin
  Inc(FClicks);
  if FBar.SimplePanel then
    // 简单模式:更新整条文本(SetSimpleText 会触发重绘)
    FBar.SimpleText := Format('SimplePanel 模式 · 已点击 %d 次', [FClicks])
  else
  begin
    // 多面板模式:分别更新填充面板与计数面板
    FBar.Panels[0].Text := Format('已更新 · %s', [FormatDateTime('hh:nn:ss', Now)]);
    FBar.Panels[1].Text := Format('点击:%d', [FClicks]);
  end;
end;

procedure TMainForm.ToggleSimple(Sender: TObject);
begin
  FBar.SimplePanel := not FBar.SimplePanel;   // 在多面板 / 整条文本之间切换
  if FBar.SimplePanel then
    FBar.SimpleText := 'SimplePanel:单一整条状态文本'
  else
    FBar.Panels[0].Text := '就绪';
end;

end.
